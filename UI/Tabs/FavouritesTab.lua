-- by tier, then by farming place
local _, ns = ...
local L = ns.L
local W, Style = ns.Widgets, ns.Style

local ui = {}
local shown -- nil: the logged-in character

local function charKey() return shown or ns.charKey end

local function characterItems()
    local items = {}
    for _, entry in ipairs(ns.Favourites.Characters()) do
        local data = entry.data
        local text = ns.Favourites.CharacterLabel(entry.key)
        if data.level then text = text .. " |cff9d9d9d" .. data.level .. "|r" end
        items[#items + 1] = {value = entry.key, text = text}
    end
    return items
end

local function create(parent)
    ui.charLabel = W.Label(parent, L["Character:"], 11, Style.MUTED)
    ui.charLabel:SetPoint("TOPLEFT", 4, -6)
    ui.character = W.Dropdown(parent, 200, characterItems, function(value)
        shown = value ~= ns.charKey and value or nil
        ns.FireChange("filters")
    end)
    ui.character:SetPoint("LEFT", ui.charLabel, "RIGHT", 8, 0)
    ui.add = W.Button(parent, L["Add item"], nil, 22, function(self) ns.AddFavourite.Toggle(self) end)
    ui.add:FitWidth()
    ui.add:SetPoint("LEFT", ui.character, "RIGHT", 12, 0)
    W.AddTooltip(ui.add, function(tooltip)
        tooltip:AddLine(L["Add item"])
        tooltip:AddLine(L["Any wearable item, even one no addon lists. It shows only here."], 1, 1, 1, true)
    end)
    ui.export = W.Button(parent, L["Export"], nil, 22, function() ns.Options:ShowFavouritesExport(charKey()) end)
    ui.export:FitWidth()
    ui.export:SetPoint("LEFT", ui.add, "RIGHT", 4, 0)
    ui.import = W.Button(parent, L["Import"], nil, 22, function() ns.Options:ShowFavouritesImport(charKey()) end)
    ui.import:FitWidth()
    ui.import:SetPoint("LEFT", ui.export, "RIGHT", 4, 0)
    ui.fdj = W.Button(parent, L["Import FDJ favourites"], nil, 22, function() ns.Options:ImportFDJ() end)
    ui.fdj:FitWidth()
    ui.fdj:SetPoint("LEFT", ui.import, "RIGHT", 4, 0)
    W.AddTooltip(ui.fdj, function(tooltip)
        tooltip:AddLine(L["Import FDJ favourites"])
        tooltip:AddLine(
          L["Copies this character's Dungeon Journal favourites once, as \"Nice to have\"."],
          1, 1, 1, true)
    end)
    ui.note = W.Label(parent, "", 11, Style.MUTED)
    ui.note:SetPoint("TOPRIGHT", -4, -10)
    ui.list = ns.SlotTab.CreateList(parent, function(key) ns.MainWindow.SetSort(key) end)
    ui.list:Place(-34, 0, 0, 0)
end

local function refresh(ctx, kinds)
    local index = ns.GetIndex()
    if not index then return end
    if shown and not ns.addon.db.global.characters[shown] then shown = nil end
    local key = charKey()
    ui.character:SetValue(key, true)
    -- FDJ's list is per character, only readable while logged in on it
    ui.fdj:SetShown(key == ns.charKey and ns.Favourites.HasFDJList())

    local favourites = ns.Favourites.List(key)
    local records, total = {}, 0
    for id in pairs(favourites) do
        total = total + 1
        local record = index.byKey[id]
        if record then records[#records + 1] = record end
    end
    -- a favourite the server doesn't know shows anyway: it was picked on purpose
    ctx = ctx or ns.FilterContext(key)
    local favCtx = setmetatable({showMissing = true}, {__index = ctx})
    local rows = ns.MainWindow.Rows(records, nil, key, favCtx)
    -- never drop a favourite silently, even when no addon lists it any more
    for id in pairs(favourites) do
        if type(id) == "number" and id > 0 and not index.byKey[id] then
            local stub = {key = id, id = id, sources = {}, orphan = true}
            local info = ns.Items.Info(stub)
            local status = info.missing and "missing" or (info.loaded and "pass" or "unknown")
            rows[#rows + 1] = {record = stub, info = info, status = status, sources = {}}
        end
    end
    if (kinds and (kinds.tab or kinds.data)) or ui.requestedFor ~= key then
        ui.requestedFor = key
        local wanted = {}
        for _, row in ipairs(rows) do wanted[#wanted + 1] = row.record end
        ns.Items.Request(wanted, true)
    end
    local function placeOf(source)
        if not source then return "?", L["Other"], 9999 end
        if source.dungeon then
            local dungeon = index.dungeonByKey[source.dungeon]
            local label = ns.Tooltip.DungeonLabel(source.dungeon, index.dungeonByKey)
            return "d:" .. source.dungeon, label, dungeon and dungeon.order or 999
        end
        if source.kind == "craft" then
            return "c:" .. tostring(source.profession), source.professionName or tostring(source.profession), 3000
        end
        if source.kind == "reputation" then
            return "r:" .. tostring(source.factionID), source.factionName or L["Reputation"], 3100
        end
        if source.kind == "pvp" then return "pvp", L["PvP"], 3200 end
        if source.kind == "event" then return "e:" .. tostring(source.eventName), source.eventName or "?", 3300 end
        if source.kind == "world" then return "world", L["World drop"], 3400 end
        -- vendors and creatures go with their zone's quests
        if (source.kind == "vendor" or source.kind == "npcDrop") and not source.zoneKey then
            if source.kind == "vendor" then return "many:vendor", L["Sold by many vendors"], 3500 end
            return "many:npcDrop", L["Dropped by many creatures"], 3600
        end
        return "q:" .. tostring(source.zoneKey), source.zoneName or L["Other quests"],
               2000 + (source.reqLevel or source.levelMin or source.npcLevel or 0)
    end
    local byTier = {}
    for _, row in ipairs(rows) do
        local tier = favourites[row.record.id]
        local key, label, order = placeOf(row.sources[1])
        if row.record.orphan then key, label, order = "orphan", L["No source listed"], 99999 end
        byTier[tier] = byTier[tier] or {order = {}, groups = {}}
        local entry = byTier[tier]
        if not entry.groups[key] then
            entry.groups[key] = {label = label, order = order, rows = {}}
            entry.order[#entry.order + 1] = entry.groups[key]
        end
        table.insert(entry.groups[key].rows, row)
    end
    local list = {}
    for _, tier in ipairs(ns.Favourites.TIERS) do
        local entry = byTier[tier.key]
        if entry then
            list[#list + 1] = {header = ns.Favourites.TierColor(tier.key) .. ns.Tooltip.STAR .. " " .. tier.label .. "|r"}
            table.sort(entry.order, function(a, b)
                if a.order ~= b.order then return a.order < b.order end
                return a.label < b.label
            end)
            for _, group in ipairs(entry.order) do
                list[#list + 1] = {header = group.label, indent = 1}
                for _, row in ipairs(group.rows) do list[#list + 1] = row end
            end
        end
    end
    ui.note:SetText(format(L["%d of %d favourites shown"], #rows, total))
    ns.MainWindow.shownCount = #rows
    local empty = total == 0 and L["No favourites yet. Click an item to add it."]
                    or L["No favourites match the filters."]
    local toTop = (kinds and kinds.tab) or ui.shownKey ~= key
    ui.shownKey = key
    ui.list:SetRows(list, ns.MainWindow.RowOptions(key, nil, ctx), empty, toTop)
end

table.insert(ns.MainTabs, {key = "favourites", label = L["Favourites"], Create = create, Refresh = refresh, CharKey = charKey})
