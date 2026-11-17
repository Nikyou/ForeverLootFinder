-- favourites that drop in the dungeon you just entered
local _, ns = ...
local L = ns.L

local Reminder = {}
ns.Reminder = Reminder

local CHECK_DELAY = 2 -- the map and instance info settle after the loading screen
local MAX_ROWS = 14

-- pure. one group per wing
function Reminder.Collect(index, favourites, keys, doable)
    local groups = {}
    for _, key in ipairs(keys) do
        local group = {dungeon = key, items = {}}
        for id, tier in pairs(favourites) do
            local record = index.byKey[id]
            if record then
                local bosses, seen = {}, {}
                local sources = doable(record.sources)
                for _, source in ipairs(sources) do
                    if source.dungeon == key then
                        local label =
                          source.kind == "quest" and format(L["Quest: %s"], source.questName or "?") or source.bossName or "?"
                        if not seen[label] then
                            seen[label] = true
                            bosses[#bosses + 1] = {label = label, kind = source.kind}
                        end
                    end
                end
                if #bosses > 0 then
                    group.items[#group.items + 1] = {record = record, tier = tier, bosses = bosses, sources = sources}
                end
            end
        end
        table.sort(group.items, function(a, b)
            local ta, tb = ns.Favourites.BY_TIER[a.tier].order, ns.Favourites.BY_TIER[b.tier].order
            if ta ~= tb then return ta < tb end
            return (a.record.name or "") < (b.record.name or "")
        end)
        if #group.items > 0 then groups[#groups + 1] = group end
    end
    return groups
end

local function bossText(boss)
    if boss.kind == "quest" then return boss.label end
    return ns.Source.BossName(boss.label)
end

local function itemText(entry)
    local info = ns.Items.Info(entry.record)
    local name = info.link or info.name or entry.record.name
    local bosses = {}
    for _, boss in ipairs(entry.bosses) do bosses[#bosses + 1] = bossText(boss) end
    return format("%s%s|r %s — %s", ns.Favourites.TierColor(entry.tier), ns.Favourites.TierLabel(entry.tier), name,
                  table.concat(bosses, ", "))
end

local ICON = 18
local frame

local function close() if frame then frame:Hide() end end

local function onClick(self, mouse)
    local row = self.data
    local link = row and row.record and ns.Items.Link(row.record)
    if row and link and IsModifiedClick() and HandleModifiedItemClick(link) then return end
    close()
end

local function createFrame()
    local W = ns.Widgets
    frame = CreateFrame("Button", "ForeverLootFinderReminder", UIParent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6)
    frame:SetFrameStrata("MEDIUM")
    frame:SetPoint("TOP", 0, -140)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnClick", onClick)
    frame.title = W.Label(frame, "", 13, ns.Style.ACCENT)
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.hint = W.Label(frame, L["Click to close"], 10, ns.Style.MUTED)
    frame.hint:SetPoint("TOPRIGHT", -12, -12)
    frame.lines = {}
    frame.items = {}
    frame:Hide()
end

local function itemButton(n)
    local b = frame.items[n]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHeight(ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT")
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.border:SetAllPoints(b.icon)
    b:SetHighlightTexture(ns.Style.HIGHLIGHT_TEXTURE, "ADD")
    b:SetScript("OnEnter", function(self) ns.Guard(ns.Row.ShowTooltip, self) end)
    b:SetScript("OnLeave", function() ns.Row.HideTooltip() end)
    b:SetScript("OnClick", onClick)
    b.opts = {}
    frame.items[n] = b
    return b
end

function Reminder.ShowWindow(groups, wings)
    if not frame then createFrame() end
    local W = ns.Widgets
    frame.title:SetText(L["Favourites in this dungeon"])
    for _, line in ipairs(frame.lines) do line:Hide() end
    for _, b in ipairs(frame.items) do
        b:Hide()
        b.data = nil
    end
    local y, used, items, width = 32, 0, 0, 320
    local function add(text, header, entry)
        used = used + 1
        local line = frame.lines[used]
        if not line then
            line = W.Label(frame, "")
            frame.lines[used] = line
        end
        line:SetFontObject(header and "GameFontNormal" or "GameFontHighlight")
        line:ClearAllPoints()
        local left = header and 12 or 20
        if entry then
            items = items + 1
            local b = itemButton(items)
            local info = ns.Items.Info(entry.record)
            b.data = {record = entry.record, info = info, sources = entry.sources}
            b.opts.charKey = ns.charKey
            b.icon:SetTexture(info.icon or 134400)
            b.border:SetVertexColor(ns.Labels.QualityRGB(info.quality))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", left, -y + 1)
            b:SetPoint("RIGHT", -12, 0)
            b:Show()
            left = left + ICON + 6
        end
        line:SetPoint("TOPLEFT", left, -y)
        line:SetText(text)
        line:Show()
        width = math.max(width, left + line:GetStringWidth() + 20)
        y = y + (entry and ICON + 2 or 16)
    end
    local rows = 0
    for _, group in ipairs(groups) do
        if wings then add(ns.Source.DungeonName(group.dungeon), true) end
        for _, entry in ipairs(group.items) do
            rows = rows + 1
            if rows > MAX_ROWS then break end
            add(itemText(entry), false, entry)
        end
    end
    if rows > MAX_ROWS then add(format(L["and %d more"], rows - MAX_ROWS)) end
    frame:SetSize(math.min(width, 640), y + 12)
    frame:Show()
end

function Reminder.ShowChat(groups, wings)
    ns.Print(L["Favourites in this dungeon"])
    for _, group in ipairs(groups) do
        if wings then print("  |cffffd100" .. ns.Source.DungeonName(group.dungeon) .. "|r") end
        for _, entry in ipairs(group.items) do print("    " .. itemText(entry)) end
    end
end

-- AtlasLoot's places, by name: all there is without FDJ
function Reminder.MatchPlace(index, instanceName)
    local squash = ns.Loot.Squash
    local wanted = type(instanceName) == "string" and not ns.IsSecret(instanceName) and squash(instanceName)
    if not wanted then return nil end
    for _, place in ipairs(index.dungeons) do
        if place.atlasloot and squash(ns.Source.DungeonName(place.key)) == wanted then return {place.key} end
    end
    return nil
end

function Reminder.Check(isReload)
    local mode = ns.addon.db.profile.reminder.mode
    local saved = ns.addon.db.char.reminder
    local inInstance = IsInInstance()
    if not inInstance then
        saved.instance = nil
        return
    end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if ns.IsSecret(instanceID) then return end
    -- not again after a /reload in the same run
    if isReload and saved.instance == instanceID then return end
    saved.instance = instanceID
    if mode == "off" then return end
    local index = ns.GetIndex()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if ns.IsSecret(mapID) then mapID = nil end
    local keys, wings = ns.Source.MatchInstance(instanceID, name, mapID)
    if not keys then keys = Reminder.MatchPlace(index, name) end
    if not keys then return end
    local groups = Reminder.Collect(index, ns.Favourites.List(), keys,
                                    function(sources) return ns.DoableSources(sources, nil, true) end)
    if #groups == 0 then return end
    if mode == "chat" then
        Reminder.ShowChat(groups, wings)
    else
        Reminder.ShowWindow(groups, wings)
    end
end

function Reminder.OnEnteringWorld(isReload)
    close()
    C_Timer.After(CHECK_DELAY, function() ns.Guard(Reminder.Check, isReload) end)
end

Reminder.Hide = close
