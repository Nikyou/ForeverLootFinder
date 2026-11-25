-- ALL THE THINGS' Forever data. read-only, and only raw fields are read so none of ATT's own lookups run
local _, ns = ...

local ATT = {}
ns.ATT = ATT

local Util = ns.Util
local MAX_EACH = 5 -- creatures listed on an item, more make one "many" source
-- reputation points per standing
local STANDINGS = {{42000, 8}, {21000, 7}, {9000, 6}, {3000, 5}, {0, 4}}
-- Enum.FlightPathFaction
local SIDES = {[1] = "Horde", [2] = "Alliance"}
local SKIP_CATEGORIES = {
    NeverImplemented = true,
    HiddenQuestTriggers = true,
    Unsorted = true,
    Secrets = true,
    ExpansionFeatures = true,
    Promotions = true,
}
local CATEGORY_KIND = {PVP = "pvp", Holidays = "event", WorldDrops = "world", Craftables = "craft"}
-- ATT's event numbers on its holiday headers (e=), to ns.Holidays' keys
local HOLIDAYS = {
    [1] = "darkmoon",
    [18] = "lunar",
    [9] = "love",
    [15] = "noblegarden",
    [13] = "children",
    [11] = "midsummer",
    [6] = "fishing",
    [17] = "harvest",
    [16] = "hallows",
    [14] = "winterVeil",
}
-- ATT keeps a split dungeon whole, its wings are headers under it (their notes in its LocalizationDB say which portal)
local WINGS = {
    [-361] = "Scarlet Monastery: Graveyard",
    [-362] = "Scarlet Monastery: Library",
    [-363] = "Scarlet Monastery: Armory",
    [-364] = "Scarlet Monastery: Cathedral",
    [-353] = "Lower Blackrock Spire",
    [-354] = "Upper Blackrock Spire",
    [-355] = "Dire Maul: East",
    [-356] = "Dire Maul: North",
    [-357] = "Dire Maul: West",
    [-365] = "Stratholme: Living",
    [-366] = "Stratholme: Undead",
}

local status = Util.NewStatus("att", {items = 0, places = 0, matched = 0, recipes = 0, ms = 0})
local stats = status.counts
local EMPTY = {provider = "att", entries = {}, dungeons = {}, areas = {}}
local extra = EMPTY
local learnedAt = {} -- [spell] = skill, from ATT's recipes
local placeNames = {} -- ["att:316"] = name, for places FDJ doesn't have
local ready = false

local function app()
    local att = rawget(_G, "AllTheThings")
    if type(att) ~= "table" or type(att.AddEventHandler) ~= "function" then return nil end
    return att
end

-- ATT replaces it once the tree is built, only then is asking early safe
local firstRootGetter = app() and rawget(app(), "GetDatabaseRoot")

function ATT.Installed() return app() ~= nil end
function ATT.Enabled() return ns.addon.db.profile.att ~= false end
function ATT.State() return status.state end
function ATT.Status() return status end
function ATT.Stats() return stats end
function ATT.Entries() return ATT.Enabled() and extra or EMPTY end
function ATT.LearnedAt(spell) return ATT.Enabled() and learnedAt[spell] or nil end
function ATT.Name(key) return placeNames[key] end

local function raw(node, key) return rawget(node, key) end

local function standingOf(value)
    if type(value) ~= "number" then return nil end
    for _, step in ipairs(STANDINGS) do if value >= step[1] then return step[2] end end
    return nil
end

local function classMask(classes)
    if type(classes) ~= "table" then return nil end
    local mask = 0
    for _, id in ipairs(classes) do if type(id) == "number" and id > 0 then mask = mask + 2 ^ (id - 1) end end
    return mask > 0 and mask or nil
end

-- shared down the tree, changed only on a copy
local function with(ctx, key, value)
    local copy = {}
    for k, v in pairs(ctx) do copy[k] = v end
    copy[key] = value
    return copy
end

-- pure, for tests: opt holds the client and FDJ lookups
function ATT.Read(root, opt)
    local out, counts = {}, {items = 0, places = 0, matched = 0, recipes = 0}
    local dungeons, areas, recipes = {}, {}, {}
    local splits = {} -- ["att:316"] = the FDJ wings its headers matched
    local checkpoint = opt.checkpoint or function() end
    local used = {}

    local function nameOf(node)
        local ok, name = pcall(opt.nameOf, node)
        return ok and type(name) == "string" and name ~= "" and name or nil
    end

    local function firstOf(list) return type(list) == "table" and list[1] or nil end

    local function place(node)
        local id = raw(node, "instanceID")
        local map = raw(node, "mapID") or firstOf(raw(node, "maps"))
        local area = raw(node, "zoneTextAreaID") or firstOf(raw(node, "zoneTextAreaIDs"))
        local name = (map and opt.mapName(map)) or (area and opt.areaName and opt.areaName(area)) or nameOf(node)
        counts.places = counts.places + 1
        local key = name and opt.dungeonOf(name)
        if key then
            counts.matched = counts.matched + 1
        else
            key = "att:" .. tostring(id)
            local level = tonumber(raw(node, "lvl"))
            dungeons[#dungeons + 1] = {
                key = key,
                name = name or key,
                raid = raw(node, "isRaid") and true or nil,
                levelMin = level,
                levelMax = level,
                levelText = level and tostring(level) or nil,
                bosses = {},
                att = true,
            }
        end
        if map then areas["m" .. map] = key end
        return key
    end

    -- ATT's cost: copper, or {{"g", copper}, {"i", itemID, count}, {"c", currencyID, count}}
    local function priceOf(cost)
        if type(cost) == "number" then return cost > 0 and {{money = cost}} or nil end
        if type(cost) ~= "table" then return nil end
        local price = {}
        for _, part in ipairs(cost) do
            local what, id, count
            if type(part) == "table" then
                what, id, count = rawget(part, 1), tonumber(rawget(part, 2)), tonumber(rawget(part, 3))
            end
            if what == "g" and id then
                price[#price + 1] = {money = id}
            elseif what == "i" and id then
                price[#price + 1] = {item = id, count = count or 1}
            elseif what == "c" and id then
                price[#price + 1] = {currency = id, count = count or 1}
            end
        end
        return #price > 0 and price or nil
    end
    -- a vendor's links carry no cost, the item's own node does
    local costs = {}

    local function addItem(node, id, ctx)
        local entry = {id = id, faction = ctx.faction, classMask = ctx.classMask}
        local side = SIDES[raw(node, "r")]
        if side then entry.faction = side end
        local rep = raw(node, "minReputation")
        if type(rep) == "table" and type(rep[1]) == "number" then
            entry.kind, entry.factionID, entry.standing = "reputation", rep[1], standingOf(rep[2])
            local battleground = ns.Index.PVP_FACTIONS[rep[1]]
            if battleground then
                entry.kind, entry.pvpKey = "pvp", battleground
                if ctx.category == "pvp" then entry.section = ctx.header end
            end
        elseif ctx.category == "craft" then
            if not ctx.profession then return end
            entry.kind, entry.profession = "craft", ctx.profession
        elseif ctx.category == "pvp" then
            entry.kind, entry.section = "pvp", ctx.header
        elseif ctx.category == "event" then
            entry.kind, entry.eventName, entry.holiday = "event", ctx.header, ctx.holiday
        elseif ctx.category == "world" then
            entry.kind, entry.worldDrop = "world", true
        elseif ctx.quest then
            local name, level = opt.questBasics(ctx.quest)
            entry.questID, entry.questName = ctx.quest, name or ctx.questName
            entry.reqLevel = level or ctx.questLevel
            if ctx.dungeon then
                entry.kind, entry.dungeon = "quest", ctx.dungeon
            else
                entry.kind = "zoneQuest"
                entry.zoneKey = ctx.map and ("map:" .. ctx.map) or "zone:other"
                entry.zoneName = ctx.map and opt.mapName(ctx.map) or nil
            end
        elseif ctx.dungeon then
            entry.dungeon = ctx.dungeon
            if ctx.boss then
                entry.kind, entry.bossName, entry.bossIndex = "boss", ctx.boss, ctx.bossIndex
            elseif ctx.npc then
                local name = opt.npcName(ctx.npc) or ctx.npcName
                entry.kind, entry.bossName, entry.creature = "boss", name, true
                entry.npcID, entry.npcs, entry.npcName = ctx.npc, {ctx.npc}, name
            else
                entry.kind = "trash"
            end
        elseif ctx.npc then
            entry.kind = raw(node, "cost") and "vendor" or "npcDrop"
            entry.npcID, entry.npcs = ctx.npc, {ctx.npc}
            entry.npcName = opt.npcName(ctx.npc) or ctx.npcName
            entry.zoneKey = ctx.map and ("map:" .. ctx.map) or nil
            entry.zoneName = ctx.map and opt.mapName(ctx.map) or nil
        else
            local creatures = raw(node, "crs")
            if type(creatures) ~= "table" or #creatures == 0 then return end
            if #creatures > MAX_EACH then
                entry.kind, entry.many, entry.count, entry.npcs = "npcDrop", true, #creatures, {}
                for i = 1, MAX_EACH do entry.npcs[i] = creatures[i] end
                entry.zoneKey = ctx.map and ("map:" .. ctx.map) or nil
                entry.zoneName = ctx.map and opt.mapName(ctx.map) or nil
            else
                for _, npcID in ipairs(creatures) do
                    local one = {
                        id = id,
                        kind = "npcDrop",
                        npcID = npcID,
                        npcs = {npcID},
                        npcName = opt.npcName(npcID),
                        faction = entry.faction,
                        classMask = entry.classMask,
                    }
                    one.zoneKey = ctx.map and ("map:" .. ctx.map) or nil
                    one.zoneName = ctx.map and opt.mapName(ctx.map) or nil
                    out[#out + 1] = one
                    counts.items = counts.items + 1
                end
                return
            end
        end
        local price = priceOf(raw(node, "cost"))
        if price and not costs[id] then costs[id] = price end
        if entry.kind == "vendor" or entry.kind == "reputation" or entry.kind == "pvp" or entry.kind == "event" then
            entry.price = price
        end
        if entry.dungeon then used[entry.dungeon] = true end
        out[#out + 1] = entry
        counts.items = counts.items + 1
    end

    local function walk(node, ctx)
        if type(node) ~= "table" or raw(node, "u") then return end
        local recipe = raw(node, "recipeID")
        if recipe then
            local skill = tonumber(raw(node, "learnedAt"))
            if skill and not recipes[recipe] then
                recipes[recipe] = skill
                counts.recipes = counts.recipes + 1
            end
        end
        local id = not recipe and raw(node, "itemID")
        if type(id) == "number" and opt.equippable(id) then addItem(node, id, ctx) end
        -- a vendor's goods are links to the items: {"select", "itemID", ...}
        local npc = raw(node, "npcID")
        local links = raw(node, "sym")
        if type(npc) == "number" and npc > 0 and type(links) == "table" then
            local sells = with(ctx, "npc", npc)
            for _, link in ipairs(links) do
                if type(link) == "table" and link[1] == "select" and link[2] == "itemID" then
                    for i = 3, #link do
                        local item = link[i]
                        if type(item) == "number" and opt.equippable(item) then
                            addItem({cost = true}, item, sells)
                        end
                    end
                end
            end
        end
        local children = raw(node, "g")
        if type(children) ~= "table" or #children == 0 then return end

        local side = SIDES[raw(node, "r")]
        if side and side ~= ctx.faction then ctx = with(ctx, "faction", side) end
        local classes = classMask(raw(node, "c"))
        if classes then ctx = with(ctx, "classMask", classes) end
        local wing = ctx.dungeon and WINGS[raw(node, "headerID")]
        if raw(node, "instanceID") then
            ctx = with(ctx, "dungeon", place(node))
            ctx.bossCount = 0
        elseif wing and opt.dungeonOf(wing) then
            local key = opt.dungeonOf(wing)
            if ctx.dungeon:sub(1, 4) == "att:" then
                local list = splits[ctx.dungeon] or {}
                splits[ctx.dungeon] = list
                local known = false
                for _, k in ipairs(list) do if k == key then known = true end end
                if not known then list[#list + 1] = key end
            end
            ctx = with(ctx, "dungeon", key)
            ctx.bossCount = 0
        elseif raw(node, "mapID") and not ctx.dungeon then
            ctx = with(ctx, "map", raw(node, "mapID"))
        end
        local encounter = raw(node, "encounterID")
        if encounter and ctx.dungeon then
            ctx.bossCount = (ctx.bossCount or 0) + 1
            local creatures = raw(node, "crs")
            local name = nameOf(node) or (type(creatures) == "table" and creatures[1] and opt.npcName(creatures[1]))
            ctx = with(ctx, "boss", name or ("#" .. encounter))
            ctx.bossIndex = ctx.bossCount
        end
        if type(npc) == "number" and npc > 0 then ctx = with(ctx, "npc", npc) end
        local quest = raw(node, "questID")
        if quest then
            ctx = with(ctx, "quest", quest)
            ctx.questLevel = tonumber(raw(node, "lvl"))
        end
        local profession = raw(node, "professionID")
        if profession and opt.professions[profession] then ctx = with(ctx, "profession", profession) end
        if raw(node, "headerID") or raw(node, "autoHeaderID") then
            if ctx.category ~= "craft" then ctx = with(ctx, "header", nameOf(node) or ctx.header) end
            local holiday = HOLIDAYS[raw(node, "e")]
            if holiday then ctx = with(ctx, "holiday", holiday) end
        end
        for _, child in ipairs(children) do
            walk(child, ctx)
            checkpoint()
        end
    end

    for _, category in ipairs(type(raw(root, "g")) == "table" and raw(root, "g") or {}) do
        local key = type(category) == "table" and raw(category, "RootCategory")
        if key and not SKIP_CATEGORIES[key] then walk(category, {category = CATEGORY_KIND[key], header = nameOf(category)}) end
    end
    for _, entry in ipairs(out) do if entry.kind == "vendor" and not entry.price then entry.price = costs[entry.id] end end
    -- places with nothing wearable stay off the Raids tab (Forever's raids, for now)
    local kept = {}
    for _, dungeon in ipairs(dungeons) do if used[dungeon.key] then kept[#kept + 1] = dungeon end end
    for map, key in pairs(areas) do if key:sub(1, 4) == "att:" and not used[key] then areas[map] = nil end end
    return out, counts, kept, areas, recipes, splits
end

local function mapName(map)
    local info = C_Map and C_Map.GetMapInfo and Util.SafeCall(C_Map.GetMapInfo, map)
    local name = type(info) == "table" and info.name
    return type(name) == "string" and not Util.IsSecret(name) and name ~= "" and name or nil
end

local function dungeonOf(name)
    local found = ns.DungeonJournal.MatchInstance(nil, name)
    return found and found[1] or nil
end

local professions = {}
for id in pairs(ns.Crafts.BY_ID) do professions[id] = true end

local function read()
    local att = app()
    local root = att and type(att.GetDatabaseRoot) == "function" and Util.SafeCall(att.GetDatabaseRoot, att)
    if type(root) ~= "table" then
        status.state = "nodata"
        return
    end
    status.state, status.error = "scanning", nil
    -- ATT asks the client, which knows only creatures it has seen: Questie's name for the rest
    local names = type(att.NPCNameFromID) == "table" and att.NPCNameFromID or {}
    local seen = {}
    local function npcName(id)
        if seen[id] == nil then
            local name = names[id]
            if type(name) ~= "string" or Util.IsSecret(name) then name = ns.Questie.NpcName(id) end
            seen[id] = name or false
        end
        return seen[id] or nil
    end
    local found, counts, dungeons, areas, recipes, splits
    Util.RunSliced(function(checkpoint)
        found, counts, dungeons, areas, recipes, splits = ATT.Read(root, {
            equippable = Util.Equippable,
            nameOf = function(node) return node.name end,
            npcName = npcName,
            mapName = mapName,
            areaName = function(area)
                local name = C_Map and C_Map.GetAreaInfo and Util.SafeCall(C_Map.GetAreaInfo, area)
                return type(name) == "string" and not Util.IsSecret(name) and name ~= "" and name or nil
            end,
            questBasics = ns.Questie.QuestBasics,
            dungeonOf = dungeonOf,
            professions = professions,
            checkpoint = checkpoint,
        })
    end, function(ok, err, ms)
        if not ok then
            status.error = tostring(err)
            ns.ReportError(err)
        end
        stats.ms, status.ms = ms, ms
        if found then
            for key, value in pairs(counts) do stats[key] = value end
            local factions = {}
            for _, entry in ipairs(found) do
                if entry.profession then entry.professionName = ns.Crafts.Name(entry.profession) end
                if entry.factionID then
                    if factions[entry.factionID] == nil then
                        factions[entry.factionID] = Util.FactionName(entry.factionID) or false
                    end
                    entry.factionName = factions[entry.factionID] or nil
                end
            end
            extra = {provider = "att", entries = found, dungeons = dungeons, areas = areas, splits = splits}
            placeNames = {}
            for _, dungeon in ipairs(dungeons) do placeNames[dungeon.key] = dungeon.name end
            learnedAt = recipes
        end
        status.state = found and #found > 0 and "done" or "nodata"
        ns.RebuildIndex()
    end)
end

-- the tree is complete only after ATT's OnReady. one found earlier is read too, then again
local function whenReady()
    if ready then return end
    ready = true
    C_Timer.After(1, function() ns.Guard(read) end)
end

local function onReady()
    ready = false
    whenReady()
end

function ATT.Init()
    if not (ATT.Installed() and ATT.Enabled()) then
        status.state = "off"
        return
    end
    status.state = "waiting"
    local att = app()
    Util.SafeCall(att.AddEventHandler, "OnReady", onReady)
    -- it may have been ready before this addon was
    local getter = rawget(att, "GetDatabaseRoot")
    if getter and getter ~= firstRootGetter then
        local root = Util.SafeCall(getter, att)
        if type(root) == "table" and type(rawget(root, "g")) == "table" and #rawget(root, "g") > 0 then whenReady() end
    end
end

function ATT.SetEnabled(value)
    ns.addon.db.profile.att = value and true or false
    if value and status.state == "off" then ATT.Init() end
    ns.RebuildIndex()
end
