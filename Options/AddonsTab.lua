local _, ns = ...
local L = ns.L
local W, Options = ns.Widgets, ns.Options

local controls = {}

local function profile() return ns.addon.db.profile end

local function good(text) return "|cff40ff40" .. text .. "|r" end
local function muted(text) return "|cff9d9d9d" .. text .. "|r" end

-- the status may wrap, the column is restacked after each refresh
local function section(col, title, text, help, onChange)
    col.title(title)
    local box = col.check(text, onChange)
    col.help(help)
    local status = col.label("")
    return {box = box, status = status}
end

local PROVIDER_NAMES = {
    fdj = "DungeonJournal",
    questie = "Questie",
    atlasloot = "AtlasLoot",
    tradeskill = L["Profession window"],
}

local function orders(list)
    if #list <= 1 then return {list} end
    local out = {}
    for i, first in ipairs(list) do
        local rest = {}
        for j, name in ipairs(list) do if j ~= i then rest[#rest + 1] = name end end
        for _, tail in ipairs(orders(rest)) do
            local order = {first}
            for _, name in ipairs(tail) do order[#order + 1] = name end
            out[#out + 1] = order
        end
    end
    return out
end

local function orderText(order)
    local names = {}
    for _, name in ipairs(order) do names[#names + 1] = PROVIDER_NAMES[name] or name end
    return table.concat(names, " > ")
end

local GROUPS = {
    {key = "drops", label = L["Dungeon and raid drops"]},
    {key = "quests", label = L["Quest rewards"]},
    {key = "crafts", label = L["Crafted items"]},
}

local function priorityDropdown(col, parent, group)
    col.label(group.label)
    local dropdown = W.Dropdown(parent, Options.COLUMN - 20, function()
        local items = {}
        for _, order in ipairs(orders(ns.Index.DEFAULT_PRIORITY[group.key])) do
            local value = table.concat(order, ">")
            local text = orderText(order)
            if value == table.concat(ns.Index.DEFAULT_PRIORITY[group.key], ">") then text = format(L["%s (default)"], text) end
            items[#items + 1] = {value = value, text = text}
        end
        return items
    end, function(value)
        local list = {}
        for name in value:gmatch("[^>]+") do list[#list + 1] = name end
        ns.SetPriority(group.key, list)
    end)
    col.place(dropdown, 32)
    return dropdown
end

local function create(parent)
    local left = W.Column(parent, 0, Options.COLUMN)
    controls.fdj = section(left, "DungeonJournal", L["Use for dungeon loot and quests"],
                           L["The main source: Forever's dungeons, bosses and dungeon quests."],
                           function(value) ns.DungeonJournal.SetEnabled(value) end)
    local syndicatorHelp = L["Knows your gear, bags, bank and mail across sessions. Without it, the bank counts once opened."]
    controls.syndicator = section(left, "Syndicator", L["Use for owned items"], syndicatorHelp,
                                  function(value)
        profile().syndicator = value
        ns.Owned.ScanSyndicator()
        ns.FireChange("owned")
        ns.FireChange("profile") -- the filter panel says what counts as owned
    end)
    left.title("QuestieDB")
    controls.questie = {box = left.check(L["Use for quests, vendors and creature drops"],
                                         function(value) ns.Questie.SetEnabled(value) end)}
    controls.questieKinds = {}
    for _, kind in ipairs({
        {key = "quests", label = L["Quest rewards"]}, {key = "vendors", label = L["Vendors"]},
        {key = "drops", label = L["Creature drops"]},
    }) do
        controls.questieKinds[kind.key] = left.check(kind.label,
                                                     function(value) ns.Questie.SetKindEnabled(kind.key, value) end, 20)
    end
    left.help(L["Questie's database: quest rewards, vendor goods and creature drops."])
    controls.questie.status = left.label("")
    controls.atlasloot = section(left, "AtlasLoot", L["Use for crafts, raids and other lists"],
                                 L["Crafts, raid and world boss loot, reputation, PvP and event rewards."],
                                 function(value) ns.AtlasLoot.SetEnabled(value) end)

    controls.attune = section(left, "Attune", L["Use for quests the others miss"],
                              L["Quest rewards from Wowhead's Forever pages. QuestieDB and DungeonJournal come first."],
                              function(value) ns.Attune.SetEnabled(value) end)
    controls.silverdragon = section(left, "SilverDragon", L["Use for rare creatures"],
                                    L["Rares and their loot. DungeonJournal and QuestieDB come first."],
                                    function(value) ns.SilverDragon.SetEnabled(value) end)

    controls.auctionator = section(left, "Auctionator", L["Use auction prices"],
                                   L["Price column, sort, filters and shopping list. Prices are from your scans."],
                                   function(value) ns.Auctionator.SetEnabled(value) end)

    left.title(L["Waypoints"])
    controls.waypoints = W.Dropdown(parent, Options.COLUMN - 20, function()
        local hasTomTom, hasPin = ns.Waypoints.HasTomTom(), ns.Waypoints.HasPin()
        local function needs(names)
            return function(tooltip)
                tooltip:AddLine(L["Needs one of these addons:"], 1, 1, 1, true)
                for _, name in ipairs(names) do tooltip:AddLine("  " .. name, 0.6, 0.8, 1) end
            end
        end
        return {
            {value = "auto", text = L["Auto (TomTom, else map pin)"],
             disabled = not (hasTomTom or hasPin), tooltip = not (hasTomTom or hasPin) and needs({"TomTom"}) or nil},
            {value = "tomtom", text = "TomTom", disabled = not hasTomTom, tooltip = not hasTomTom and needs({"TomTom"}) or nil},
            {value = "pin", text = L["Game map pin"], disabled = not hasPin, tooltip = not hasPin and function(tooltip)
                tooltip:AddLine(L["This client has no map pins."], 1, 1, 1, true)
            end or nil},
        }
    end, function(value)
        profile().waypoints = value
        ns.Options:RefreshActiveTab()
    end)
    left.place(controls.waypoints, 32)
    left.help(L["Right-click an item for a waypoint to its source. Shift-click a dungeon name for its entrance."], 0)
    controls.waypointStatus = left.label("")

    local right = W.Column(parent, Options.RIGHT, Options.COLUMN)
    right.title(L["When addons overlap"])
    right.help(L["Same item, same place (dungeon, quest, profession): the first addon's entry wins."], 0)
    controls.priority = {}
    for _, group in ipairs(GROUPS) do controls.priority[group.key] = priorityDropdown(right, parent, group) end

    -- By slot and Favourites always show
    right.title(L["Tabs"])
    controls.tabs = {}
    for _, tab in ipairs({
        {key = "dungeon", label = L["Dungeons"]}, {key = "raids", label = L["Raids"]}, {key = "quests", label = L["Quests"]},
        {key = "crafts", label = L["Professions"]},
        {key = "reputation", label = L["Reputation"]}, {key = "pvp", label = L["PvP"]},
        {key = "events", label = L["World events"]},
    }) do
        controls.tabs[tab.key] = right.check(format(L["Show the %s tab"], tab.label), function(value)
            profile().tabs[tab.key] = value
            ns.FireChange("profile")
        end)
    end
end

local STATE_TEXT = {
    waiting = L["Waiting to load..."],
    scanning = L["Reading..."],
    nodata = L["Loaded, but no data found. See /flf dump questie or crafts."],
}

local function setStatus(entry, installed, on, text)
    entry.box:SetChecked(on)
    entry.box:SetEnabled(installed)
    entry.box.Text:SetTextColor(unpack(installed and ns.Style.TEXT or ns.Style.MUTED))
    if not installed then
        entry.status:SetText(muted(L["Not installed."]))
    elseif not on then
        entry.status:SetText(muted(L["Off"]))
    else
        entry.status:SetText(text)
    end
end

local function refresh()
    local p = profile()
    local fdjText = good(format(L["In use: %d dungeons."], #ns.SourceData().dungeons))
    if ns.DungeonJournal.Status() == "invalid" then fdjText = ns.FDJMessage() or "" end
    setStatus(controls.fdj, ns.DungeonJournal.Installed(), p.fdj ~= false, fdjText)
    setStatus(controls.syndicator, type(rawget(_G, "Syndicator")) == "table", p.syndicator ~= false,
              ns.Owned.HasSyndicator() and good(L["In use."]) or STATE_TEXT.waiting)
    local questState = ns.Questie.State()
    local qs = ns.Questie.Stats()
    local questText = questState == "done" and good(format(L["%d quest rewards, %d vendor, %d creature sources."],
                                                           qs.rewards, qs.vendors, qs.drops))
                        or STATE_TEXT[questState] or ""
    setStatus(controls.questie, ns.Questie.Installed(), p.questie ~= false, questText)
    local kindsUsable = ns.Questie.Installed() and p.questie ~= false
    for key, box in pairs(controls.questieKinds) do
        box:SetChecked(ns.Questie.KindEnabled(key))
        box:SetEnabled(kindsUsable)
        box.Text:SetTextColor(unpack(kindsUsable and ns.Style.TEXT or ns.Style.MUTED))
    end
    controls.waypoints:SetValue(ns.Waypoints.Setting(), true)
    local method = ns.Waypoints.Method()
    controls.waypointStatus:SetText(method == "tomtom" and good(L["In use: TomTom."])
                                      or method == "pin" and good(L["In use: the game's map pin."])
                                      or muted(L["Not available: install TomTom."]))
    local craftState, lootState = ns.Crafts.State(), ns.AtlasLootLists.State()
    local atlasText
    if craftState == "done" or lootState == "done" then
        atlasText = good(format(L["%d crafted, %d other items."], ns.Crafts.Stats().equippable,
                                ns.AtlasLootLists.Stats().items))
    else
        atlasText = STATE_TEXT[lootState] or STATE_TEXT[craftState] or ""
    end
    setStatus(controls.atlasloot, ns.Crafts.Installed(), p.atlasloot ~= false, atlasText)
    local attune = ns.Attune.Stats()
    setStatus(controls.attune, ns.Attune.Installed(), p.attune ~= false,
              ns.Attune.State() == "done" and good(format(L["%d quests, %d rewards."], attune.quests, attune.rewards))
                or STATE_TEXT[ns.Attune.State()] or "")
    local rares = ns.SilverDragon.Stats()
    setStatus(controls.silverdragon, ns.SilverDragon.Installed(), p.silverdragon ~= false,
              ns.SilverDragon.State() == "done" and good(format(L["%d rares, %d items."], rares.rares, rares.items))
                or STATE_TEXT[ns.SilverDragon.State()] or "")
    local auctionText = ""
    if ns.Auctionator.Active() then
        local index = ns.GetIndex()
        local coverage = ns.Auctionator.Coverage(index and index.records or {}, ns.Items.Info)
        auctionText = good(format(L["In use: %d of %d sellable items priced."], coverage.priced, coverage.sellable))
    end
    setStatus(controls.auctionator, ns.Auctionator.Installed(), p.auctionator ~= false, auctionText)
    for key, box in pairs(controls.tabs) do box:SetChecked(p.tabs[key] ~= false) end
    local priority = ns.Priority()
    for group, dropdown in pairs(controls.priority) do dropdown:SetValue(table.concat(priority[group], ">")) end
end

table.insert(ns.OptionsTabs, {key = "addons", label = L["Addons"], Create = create, Refresh = refresh})

ns.OnChange(function(kinds) if kinds.data or kinds.owned or kinds.prices then ns.Options:RefreshActiveTab() end end)
