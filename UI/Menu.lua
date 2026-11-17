local _, ns = ...
local L = ns.L

local Menu = {}
ns.Menu = Menu

local function insertLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
end
Menu.InsertLink = insertLink

local function firstSource(row, record, test)
    for _, source in ipairs(row and row.sources or record.sources) do if test(source) then return source end end
    for _, source in ipairs(record.sources) do if test(source) then return source end end
    return nil
end

local function showEntries(root, row, record, id)
    -- only for what FDJ lists itself
    local fdj = firstSource(row, record, function(source) return source.provider == "fdj" and source.dungeon ~= nil end)
    if fdj and ns.Source.CanOpenDungeon() then
        root:CreateButton(L["Show in Dungeon Journal"], function() ns.Source.OpenDungeon(fdj.dungeon, fdj.bossIndex) end)
    elseif fdj and id and ns.Source.CanOpenItem() then
        root:CreateButton(L["Show in Dungeon Journal"], function() ns.Source.OpenItem(id) end)
    end
    local atlas = firstSource(row, record, function(source) return source.provider == "atlasloot" and ns.Loot.CanOpen(source) end)
    if atlas then root:CreateButton(L["Show in AtlasLoot"], function() ns.Loot.Open(atlas) end) end
    local quest = firstSource(row, record, function(source)
        return source.questID ~= nil and ns.Quests.CanOpen(source.questID)
    end)
    if quest then
        root:CreateButton(format(L["Quest in Questie: %s"], quest.questName or quest.section or "?"),
                          function() ns.Quests.Open(quest.questID) end)
    end
end

local MAX_WAYPOINTS = 3
local function waypointEntries(root, row, record)
    local seen, count = {}, 0
    for _, list in ipairs({row and row.sources or {}, record.sources}) do
        for _, source in ipairs(list) do
            for _, target in ipairs(ns.Navigation.Targets(source)) do
                local key = target.name .. ":" .. target.mapID
                if count < MAX_WAYPOINTS and not seen[key] then
                    seen[key] = true
                    count = count + 1
                    root:CreateButton(format(L["Waypoint: %s"], target.name), function() ns.Navigation.Go(target) end)
                end
            end
        end
        if count > 0 then return end
    end
end

-- searching needs the auction house open, the shopping list doesn't
local function auctionEntries(root, record, info)
    local AH = ns.Auctionator
    local name = info.name or record.name
    if not name or not AH.Sellable(info) then return end
    if AH.CanSearch() then root:CreateButton(L["Search in Auctionator"], function() AH.Search(name) end) end
    if AH.CanAddToList() then
        root:CreateButton(L["Add to Auctionator shopping list"], function()
            local result = AH.AddToList(name)
            if result == "present" then
                ns.Print(format(L["Already on shopping list \"%s\"."], AH.SHOPPING_LIST))
            elseif result then
                ns.Print(format(L["Added to shopping list \"%s\"."], AH.SHOPPING_LIST))
            else
                ns.Print(L["Auctionator couldn't add it."])
            end
        end)
    end
end

-- charKey: an alt picked on the Favourites tab
function Menu.Row(owner, record, row, charKey)
    local info = ns.Items.Info(record)
    local id = record.id and record.id > 0 and record.id or nil
    ns.Widgets.ContextMenu(owner, function(_, root)
        root:CreateTitle(info.name or record.name or "?")
        if id then
            local function isTier(tier) return ns.Favourites.Get(id, charKey) == tier end
            local function setTier(tier) ns.Favourites.Set(id, tier, charKey) end
            for _, tier in ipairs(ns.Favourites.TIERS) do
                root:CreateRadio(ns.Favourites.TierColor(tier.key) .. tier.label .. "|r", isTier, setTier, tier.key)
            end
            if ns.Favourites.Get(id, charKey) then
                root:CreateButton(L["Remove from favourites"], function() setTier(nil) end)
            end
            root:CreateDivider()
        end
        showEntries(root, row, record, id)
        waypointEntries(root, row, record)
        auctionEntries(root, record, info)
        if info.setID or info.setName then root:CreateButton(L["Show whole set"], function() ns.SetPanel.Show(record) end) end
        local link = ns.Items.Link(record)
        if link and link:find("|H", 1, true) then root:CreateButton(L["Link to chat"], function() insertLink(link) end) end
        root:CreateButton(L["Hide this item"], function()
            ns.addon.db.char.hidden[record.key] = true
            ns.FireChange("filters")
        end)
    end)
end
