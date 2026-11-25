-- the only file that reads Questie/QuestieDB. read-only. waits for Questie's corrections when Questie is loaded
local _, ns = ...

local Questie = {}
ns.Questie = Questie

local FRAME_BUDGET_MS = 6 -- QuestieDB decodes rows on first read, so budget by time, not rows
local ALONE_DELAY = 5 -- QuestieDB without Questie
local QUEST_FIELDS = {
    "name", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "zoneOrSort", "startedBy", "objectives",
    "sourceItemId",
}
local MAX_DROPPERS = 4 -- per item, for the areas a quest touches
local MAX_EACH = 5 -- more than this make one "many" source
local MANY_SAMPLE = 40
local MANY_ZONES = 4
local MANY_NPCS = 5
-- droppers spread over this many zones: a world drop, any creature of the right level can have it
local WORLD_ZONES = 4
-- QuestieDB's Forever data has joke drops: Sulfuras on a levelless "Super Hogger", Molten Core rings on level 5
-- boars. item level is capped at 60 so Naxxramas (92 from level 63 bosses) stays
local DROP_REQ_GAP, DROP_ILVL_GAP, DROP_ILVL_CAP = 10, 20, 60
-- the Molten Core copies (288890-288931, Bonereaver's Edge, Band of Sulfuras) mostly have no level of their own, so
-- they're judged by the original. Wowhead lists them as not available to players
local ORIGINAL_LAST = 25000
local SKIPPED_SAMPLES = 25
-- QuestieDB still has SoD's NPCs (rune brokers, Mokvar, guards selling SoD gear). skip those unless a Forever quest
-- uses them, or a SoD-era quest that rewards a Forever item. that's what keeps Pix Xizzix
local SOD_NPC_FIRST, SOD_NPC_LAST = 200000, 244999
local SOD_QUEST_FIRST, FOREVER_QUEST_FIRST = 70000, 90000
local FOREVER_ITEM_FIRST = 245000
local SOD_SAMPLES = 30
-- SoD gear also drops from old-world creatures in QuestieDB (Dyadic Icon from Bristleback Shaman) and the server
-- still knows it, so only the source can tell. checked against Wowhead's Forever pages
local SOD_ITEM_FIRST, SOD_ITEM_LAST = 190000, 244999

local Util = ns.Util
local L = ns.L
local entries = {}
local status = Util.NewStatus("questie", {items = 0, equippable = 0, rewards = 0, quests = 0, hidden = 0, errors = 0, ms = 0,
                                          vendors = 0, drops = 0, manyVendors = 0, manyDrops = 0, npcs = 0,
                                          implausible = 0, implausibleItems = 0, sodSkipped = 0, sodNpcs = 0, sodKept = 0,
                                          sodRefs = 0, sodItems = 0, worldDrops = 0})
local stats = status.counts
local skippedSamples = {}
-- SoD-range NPCs that Forever's quests use. nil without Quest.GetAllIds, then nothing is skipped
local foreverNpcs
local sodSkipped = {}
local keptSodQuests = {}
local sodItemSamples = {}
-- id -> name of every wearable item, to find one by name when adding a favourite
local itemNames = {}
-- id -> why a wearable item with QuestieDB sources got none: "sod", "implausible" or "hidden"
local skipReasons = {}
-- lowercased name -> item level of classic items, for Forever's copies
local originals = {}
local scanToken = 0

local isSecret = Util.IsSecret

local function db()
    local lib = rawget(_G, "LibQuestieDB")
    if type(lib) ~= "table" or type(lib.Item) ~= "table" or type(lib.Quest) ~= "table" then return nil end
    return lib
end

local function questie()
    local addon = rawget(_G, "Questie")
    if type(addon) ~= "table" or type(addon.API) ~= "table" then return nil end
    return addon
end

-- Questie itself only adds the hidden-quest corrections
function Questie.Installed() return db() ~= nil end
function Questie.Enabled() return ns.addon.db.profile.questie ~= false end
function Questie.State() return status.state end
function Questie.Stats() return stats end
function Questie.Status() return status end
function Questie.SkippedSamples() return skippedSamples end
function Questie.ItemNames() return itemNames end
function Questie.SkipReason(id) return skipReasons[id] end
function Questie.SodRuleOn() return foreverNpcs ~= nil end
function Questie.SodItems() return stats.sodItems, sodItemSamples end

function Questie.SodSkipped()
    local list = {}
    for _, info in pairs(sodSkipped) do list[#list + 1] = info end
    table.sort(list, function(a, b)
        if a.items ~= b.items then return a.items > b.items end
        return a.id < b.id
    end)
    for i = #list, SOD_SAMPLES + 1, -1 do list[i] = nil end
    return list
end

local KIND_SWITCH = {zoneQuest = "quests", vendor = "vendors", npcDrop = "drops"}
local KIND_DEFAULTS = {quests = true, vendors = true, drops = true}
function Questie.KindEnabled(switch)
    local kinds = ns.addon.db.profile.questieKinds
    local value
    if type(kinds) == "table" then value = kinds[switch] end
    -- not written back, so an untouched profile follows a new default
    if value == nil then return KIND_DEFAULTS[switch] == true end
    return value ~= false
end

function Questie.SetKindEnabled(switch, value)
    local profile = ns.addon.db.profile
    profile.questieKinds = profile.questieKinds or {}
    profile.questieKinds[switch] = value and true or false
    ns.RebuildIndex()
end

local filtered, filteredFor, filteredKey
function Questie.Entries()
    if not Questie.Enabled() then return {} end
    local key = ""
    for _, switch in ipairs({"quests", "vendors", "drops"}) do key = key .. (Questie.KindEnabled(switch) and "1" or "0") end
    if key == "111" then return entries end
    if filteredFor ~= entries or filteredKey ~= key then
        filtered, filteredFor, filteredKey = {}, entries, key
        for _, entry in ipairs(entries) do
            local switch = KIND_SWITCH[entry.kind]
            if not switch or Questie.KindEnabled(switch) then filtered[#filtered + 1] = entry end
        end
    end
    return filtered
end

local function get(kind, id, field)
    local lib = db()
    local getter = lib and lib[kind] and lib[kind].Get
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, id, field)
    if not ok then
        stats.errors = stats.errors + 1
        return nil
    end
    return value
end

function Questie.Keys(kind)
    local lib = db()
    local meta = lib and type(lib.Meta) == "table" and lib.Meta[kind]
    local keys = type(meta) == "table" and meta.keys
    if type(keys) ~= "table" then return nil end
    local list = {}
    for name in pairs(keys) do list[#list + 1] = tostring(name) end
    table.sort(list)
    return list
end
-- name and required level of any quest, for other addons' quest lists
function Questie.QuestBasics(questID)
    if not db() then return nil end
    local name = get("Quest", questID, "name")
    if type(name) ~= "string" then return nil end
    local level = get("Quest", questID, "requiredLevel")
    return name, type(level) == "number" and level > 0 and level or nil
end


local function ids(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for key, value in pairs(list) do
        if type(value) == "number" then
            out[#out + 1] = value
        elseif type(key) == "number" then
            out[#out + 1] = key
        end
    end
    return out
end

-- Forever's own races sit past bit 32
function Questie.RaceBit(raceID)
    if type(raceID) ~= "number" then return nil end
    local lib = db()
    local byID = lib and type(lib.Enum) == "table" and lib.Enum.raceMaskById
    if type(byID) == "table" and type(byID[raceID]) == "number" then return byID[raceID] end
    return 2 ^ (raceID - 1)
end

function Questie.FactionRaces(faction)
    local lib = db()
    local masks = lib and type(lib.Enum) == "table" and lib.Enum.factionRaceMasks
    local mask = type(masks) == "table" and masks[faction]
    return type(mask) == "number" and mask > 0 and mask or nil
end

function Questie.ClassBit(classID)
    if type(classID) ~= "number" or classID < 1 then return nil end
    return 2 ^ (classID - 1)
end

-- Questie may still be loading, try again a second later. its hidden list is filled in while it starts
local corrections, events, modulesTriedAt
local function questieModules()
    if not corrections and (not modulesTriedAt or GetTime() - modulesTriedAt >= 1) then
        modulesTriedAt = GetTime()
        local loader = rawget(_G, "QuestieLoader")
        if type(loader) == "table" then
            local found = Util.SafeCall(loader.ImportModule, loader, "QuestieCorrections")
            if type(found) == "table" then corrections = found end
            found = Util.SafeCall(loader.ImportModule, loader, "QuestieEvent")
            if type(found) == "table" then events = found end
        end
    end
    return corrections, events
end

-- Questie's own rule: "HIDE_ON_MAP" quests are only kept off its map, and a holiday's quests sit in the hidden
-- list all year (Questie shows them while the holiday runs). Other addons' quest lines go through this too
function Questie.HiddenQuest(questID)
    local fixes, holidays = questieModules()
    local list = fixes and fixes.hiddenQuests
    local hidden = type(list) == "table" and list[questID]
    if not hidden or hidden == "HIDE_ON_MAP" then return false end
    return not (holidays and Util.SafeCall(holidays.IsEventQuest, questID) == true)
end

-- Questie's holiday names, to ns.Holidays' keys. the rest (Brewfest and later ones) aren't Classic's
local HOLIDAYS = {
    ["Darkmoon Faire"] = "darkmoon", ["Lunar Festival"] = "lunar", ["Love is in the Air"] = "love",
    ["Noblegarden"] = "noblegarden", ["Children's Week"] = "children", ["Midsummer"] = "midsummer",
    ["Harvest Festival"] = "harvest", ["Hallow's End"] = "hallows", ["Winter Veil"] = "winterVeil",
}

-- the holiday a quest belongs to, nil for any other quest
function Questie.Holiday(questID)
    local _, holidays = questieModules()
    local name = holidays and Util.SafeCall(holidays.GetEventNameFor, questID)
    if type(name) ~= "string" or Util.IsSecret(name) then return nil end
    return HOLIDAYS[name]
end

local zoneNames = {}
local function zoneName(zoneID)
    if zoneNames[zoneID] == nil then
        local name = C_Map and Util.SafeCall(C_Map.GetAreaInfo, zoneID)
        zoneNames[zoneID] = type(name) == "string" and not isSecret(name) and name ~= "" and name or false
    end
    return zoneNames[zoneID] or nil
end

local function questZone(zoneOrSort, startedBy)
    if type(zoneOrSort) == "number" and zoneOrSort > 0 then return zoneOrSort end
    if type(startedBy) == "table" then
        local npcs, objects = startedBy[1], startedBy[2]
        local npc = type(npcs) == "table" and npcs[1]
        if type(npc) == "number" then
            local zone = get("Npc", npc, "zoneID")
            if type(zone) == "number" and zone > 0 then return zone end
        end
        local object = type(objects) == "table" and objects[1]
        if type(object) == "number" then
            local zone = get("Object", object, "zoneID")
            if type(zone) == "number" and zone > 0 then return zone end
        end
    end
    return nil
end

-- givers, kill targets and droppers too, so "Head of Onyxia" ends up at Onyxia's Lair
local npcZones = {}
local function npcZone(npc)
    if npcZones[npc] == nil then
        local zone = get("Npc", npc, "zoneID")
        npcZones[npc] = type(zone) == "number" and zone > 0 and zone or false
    end
    return npcZones[npc] or nil
end

local function first(value) return type(value) == "table" and value[1] or value end

local function questAreas(fields)
    local set, list = {}, {}
    local function add(zone)
        if type(zone) == "number" and zone > 0 and not set[zone] then
            set[zone] = true
            list[#list + 1] = zone
        end
    end
    local function addItem(item)
        if type(item) ~= "number" then return end
        local droppers = get("Item", item, "npcDrops")
        if type(droppers) ~= "table" then return end
        for i = 1, math.min(#droppers, MAX_DROPPERS) do add(npcZone(droppers[i])) end
    end
    add(fields.zoneOrSort)
    local startedBy = fields.startedBy
    if type(startedBy) == "table" then
        for _, npc in ipairs(type(startedBy[1]) == "table" and startedBy[1] or {}) do add(npcZone(npc)) end
        for _, item in ipairs(type(startedBy[3]) == "table" and startedBy[3] or {}) do addItem(item) end
    end
    local objectives = fields.objectives
    if type(objectives) == "table" then
        for _, creature in ipairs(type(objectives[1]) == "table" and objectives[1] or {}) do add(npcZone(first(creature))) end
        for _, item in ipairs(type(objectives[3]) == "table" and objectives[3] or {}) do addItem(first(item)) end
    end
    addItem(fields.sourceItemId)
    return #list > 0 and list or nil
end

local questCache = {}
local function quest(questID)
    local cached = questCache[questID]
    if cached ~= nil then return cached or nil end
    local fields = {}
    for _, field in ipairs(QUEST_FIELDS) do fields[field] = get("Quest", questID, field) end
    if type(fields.name) ~= "string" then
        questCache[questID] = false
        return nil
    end
    local zone = questZone(fields.zoneOrSort, fields.startedBy)
    local entry = {
        questID = questID,
        questName = fields.name,
        reqLevel = type(fields.requiredLevel) == "number" and fields.requiredLevel > 0 and fields.requiredLevel or nil,
        questLevel = type(fields.questLevel) == "number" and fields.questLevel > 0 and fields.questLevel or nil,
        raceMask = type(fields.requiredRaces) == "number" and fields.requiredRaces > 0 and fields.requiredRaces or nil,
        classMask = type(fields.requiredClasses) == "number" and fields.requiredClasses > 0 and fields.requiredClasses or nil,
        zoneKey = zone and ("zone:" .. zone) or "zone:other",
        zoneName = zone and zoneName(zone) or nil,
        areas = questAreas(fields),
    }
    questCache[questID] = entry
    stats.quests = stats.quests + 1
    return entry
end

-- cmangos ranks: 2 rare elite, 3 boss, 4 rare
local RARE_RANKS = {[2] = true, [4] = true}
local FACTIONS = {A = "Alliance", H = "Horde"}

local npcCache = {}
local function npc(id)
    local cached = npcCache[id]
    if cached ~= nil then return cached or nil end
    local name = get("Npc", id, "name")
    if type(name) ~= "string" or name == "" then
        npcCache[id] = false
        return nil
    end
    local low, high = get("Npc", id, "minLevel"), get("Npc", id, "maxLevel")
    low = type(low) == "number" and low > 0 and low or nil
    high = type(high) == "number" and high > 0 and high or nil
    local zone = npcZone(id)
    if not zone then
        local spawns = get("Npc", id, "spawns")
        for area in pairs(type(spawns) == "table" and spawns or {}) do
            if type(area) == "number" and area > 0 and (not zone or area < zone) then zone = area end
        end
    end
    local info = {
        id = id,
        name = name,
        zone = zone,
        minLevel = low or high,
        maxLevel = high or low,
        rare = RARE_RANKS[get("Npc", id, "rank")] == true,
        faction = FACTIONS[get("Npc", id, "friendlyToFaction")],
    }
    npcCache[id] = info
    stats.npcs = stats.npcs + 1
    return info
end

-- Forever's own creatures have no levels in QuestieDB, the item's required level stands in
function Questie.ImplausibleDrop(creature, reqLevel, itemLevel)
    local req = type(reqLevel) == "number" and reqLevel > 1 and reqLevel or nil
    local level = creature.maxLevel
    if level and req and level + DROP_REQ_GAP < req then return "required level " .. req end
    level = level or req or 1
    if type(itemLevel) == "number" and level + DROP_ILVL_GAP < math.min(DROP_ILVL_CAP, itemLevel) then
        return "item level " .. itemLevel
    end
    return nil
end

local function zoneFields(entry, zone)
    entry.zone = zone
    entry.zoneKey = zone and ("zone:" .. zone) or nil
    entry.zoneName = zone and zoneName(zone) or nil
end

local function npcEntries(found, item, itemName, kind, list, sodItem)
    local npcIDs = ids(list)
    if #npcIDs == 0 then return 0 end
    if sodItem then
        local kept = {}
        for _, npcID in ipairs(npcIDs) do
            if foreverNpcs[npcID] then kept[#kept + 1] = npcID else stats.sodSkipped = stats.sodSkipped + 1 end
        end
        npcIDs = kept
        if #npcIDs == 0 then return 0 end
    elseif foreverNpcs then
        local kept = {}
        for _, npcID in ipairs(npcIDs) do
            if npcID < SOD_NPC_FIRST or npcID > SOD_NPC_LAST then
                kept[#kept + 1] = npcID
            elseif foreverNpcs[npcID] then
                stats.sodKept = stats.sodKept + 1
                kept[#kept + 1] = npcID
            else
                stats.sodSkipped = stats.sodSkipped + 1
                local skipped = sodSkipped[npcID]
                if not skipped then
                    local info = npc(npcID)
                    skipped = {id = npcID, name = info and info.name or "?", items = 0}
                    sodSkipped[npcID] = skipped
                    stats.sodNpcs = stats.sodNpcs + 1
                end
                skipped.items = skipped.items + 1
                skipped[kind == "vendor" and "vendor" or "drop"] = true
            end
        end
        npcIDs = kept
        if #npcIDs == 0 then return 0 end
    end
    if kind == "npcDrop" then
        -- before the count, so a few real droppers don't vanish into a "many" source
        local reqLevel, itemLevel = get("Item", item, "requiredLevel"), get("Item", item, "itemLevel")
        local original = item >= FOREVER_ITEM_FIRST and type(itemName) == "string" and originals[itemName:lower()]
        -- not the required level: a levelless creature (Super Hogger) would borrow it and pass
        if original and original > (type(itemLevel) == "number" and itemLevel or 0) then itemLevel = original end
        local kept = {}
        for _, npcID in ipairs(npcIDs) do
            local info = npc(npcID)
            local why = info and Questie.ImplausibleDrop(info, reqLevel, itemLevel)
            if why then
                stats.implausible = stats.implausible + 1
                if #skippedSamples < SKIPPED_SAMPLES then
                    skippedSamples[#skippedSamples + 1] = format("%d %s: %s (%d, level %s-%s), %s", item,
                        tostring(itemName), info.name, info.id, tostring(info.minLevel or "?"),
                        tostring(info.maxLevel or "?"), why)
                end
            else
                kept[#kept + 1] = npcID
            end
        end
        if #kept == 0 then stats.implausibleItems = stats.implausibleItems + 1 end
        npcIDs = kept
        if #npcIDs == 0 then return 0 end
    end
    local many = #npcIDs > MAX_EACH
    local added = 0
    if not many then
        for _, npcID in ipairs(npcIDs) do
            local info = npc(npcID)
            if info then
                local entry = {id = item, name = itemName, kind = kind, npcID = info.id, npcName = info.name, npcs = {info.id}}
                zoneFields(entry, info.zone)
                if kind == "vendor" then
                    entry.faction, entry.npcLevel = info.faction, info.maxLevel
                else
                    entry.levelMin, entry.levelMax, entry.rare = info.minLevel, info.maxLevel, info.rare or nil
                end
                found[#found + 1] = entry
                added = added + 1
            end
        end
        return added
    end
    local entry = {id = item, name = itemName, kind = kind, many = true, count = #npcIDs, npcs = {}, zones = {}}
    local zoneSet, zoneCount, names, faction, oneFaction = {}, 0, {}, nil, true
    for i = 1, math.min(#npcIDs, MANY_SAMPLE) do
        local info = npc(npcIDs[i])
        if info then
            if #entry.npcs < MANY_NPCS then entry.npcs[#entry.npcs + 1] = info.id end
            if #names < 3 then names[#names + 1] = info.name end
            if info.minLevel and (not entry.levelMin or info.minLevel < entry.levelMin) then entry.levelMin = info.minLevel end
            if info.maxLevel and (not entry.levelMax or info.maxLevel > entry.levelMax) then entry.levelMax = info.maxLevel end
            if info.zone and not zoneSet[info.zone] then
                zoneSet[info.zone] = true
                zoneCount = zoneCount + 1
                local name = zoneName(info.zone)
                if name and #entry.zones < MANY_ZONES then entry.zones[#entry.zones + 1] = name end
            end
            if faction == nil then
                faction = info.faction or false
            elseif faction ~= (info.faction or false) then
                oneFaction = false
            end
        end
    end
    if #entry.npcs == 0 then return 0 end
    if kind == "npcDrop" and zoneCount >= WORLD_ZONES then
        entry.kind, entry.worldDrop, entry.mobs = "world", true, nil
        entry.zones, entry.npcs = {}, {}
        found[#found + 1] = entry
        return 1, true
    end
    entry.moreZones = zoneCount > #entry.zones or nil
    -- all in one zone, Index may tie it to a dungeon
    if zoneCount == 1 then zoneFields(entry, next(zoneSet)) end
    -- a dungeon's trash often comes with a few creatures outside: Index ties it where the item drops in the dungeon
    if zoneCount > 1 and kind == "npcDrop" then
        entry.zoneSet = {}
        for zone in pairs(zoneSet) do entry.zoneSet[#entry.zoneSet + 1] = zone end
    end
    entry.mobs = table.concat(names, ", ") .. (#npcIDs > #names and ", ..." or "")
    if kind == "vendor" and oneFaction and faction then entry.faction = faction end
    found[#found + 1] = entry
    return 1
end

local function questieModule(name)
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local module = Util.SafeCall(loader.ImportModule, loader, name)
    return type(module) == "table" and module or nil
end

-- the same tables Questie's ZoneDB decodes at start
local function supportZones()
    local lib = rawget(_G, "LibQuestieDB")
    local support = type(lib) == "table" and type(lib.Support) == "table" and lib.Support or nil
    local zones = support and Util.SafeCall(support.Get, "ZoneDB")
    return type(zones) == "table" and type(zones.private) == "table" and zones.private or nil
end

-- Lua source in a string, run it in an empty environment
local function decode(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" then return nil end
    local compile, setEnv = rawget(_G, "loadstring"), rawget(_G, "setfenv")
    if type(compile) ~= "function" or type(setEnv) ~= "function" then return nil end
    local chunk = compile(value)
    if not chunk then return nil end
    setEnv(chunk, {})
    local ok, result = pcall(chunk)
    return ok and type(result) == "table" and result or nil
end

local areaMaps -- false once the support data turned out unusable
local function supportAreaMaps()
    if areaMaps == nil then
        local private = supportZones()
        if not private then return nil end
        areaMaps = false
        local base = decode(private.areaIdToUiMapId)
        if base then
            local copy = {}
            for area, map in pairs(base) do copy[area] = map end
            for area, map in pairs(decode(private.areaIdToUiMapIdOverride) or {}) do copy[area] = map end
            areaMaps = copy
        end
    end
    return areaMaps or nil
end

function Questie.MapSources()
    local zoneDB = questieModule("ZoneDB")
    local maps = supportAreaMaps()
    local count = 0
    for _ in pairs(maps or {}) do count = count + 1 end
    return {zoneDB = zoneDB ~= nil and type(zoneDB.GetUiMapIdByAreaId) == "function", support = count}
end

-- 0 means hidden
function Questie.UiMapForArea(area)
    if type(area) ~= "number" then return nil end
    local zoneDB = questieModule("ZoneDB")
    local map = zoneDB and Util.SafeCall(zoneDB.GetUiMapIdByAreaId, zoneDB, area)
    if type(map) ~= "number" or map <= 0 then
        local maps = supportAreaMaps()
        map = maps and maps[area]
    end
    return type(map) == "number" and map > 0 and map or nil
end

local dungeonAreas
local function dungeons()
    if dungeonAreas then return dungeonAreas end
    local private = supportZones()
    local raw = private and private.dungeons
    if type(raw) ~= "table" then
        local zoneDB = questieModule("ZoneDB")
        raw = zoneDB and Util.SafeCall(zoneDB.GetDungeons, zoneDB)
    end
    local list = {}
    for area, entry in pairs(type(raw) == "table" and raw or {}) do
        if type(area) == "number" and type(entry) == "table" then
            local info = {area = area, name = type(entry[1]) == "string" and entry[1] or nil,
                          locations = type(entry[4]) == "table" and entry[4] or {}}
            list[area] = info
            for _, other in ipairs(type(entry[2]) == "table" and entry[2] or {}) do list[other] = list[other] or info end
        end
    end
    if next(list) ~= nil then dungeonAreas = list end
    return list
end

function Questie.DungeonEntrances(area)
    local dungeon = dungeons()[area]
    if not dungeon then return nil end
    local out = {}
    for _, location in ipairs(dungeon.locations) do
        local zone, x, y = location[1], location[2], location[3]
        local map = Questie.UiMapForArea(zone)
        if map and type(x) == "number" and type(y) == "number" then out[#out + 1] = {mapID = map, x = x / 100, y = y / 100} end
    end
    return out, dungeon.name
end

-- by name, so creature drops and quests find FDJ's dungeons without AtlasLoot
local placeAreas, placeAreasFor, placeAreasAtlas
-- FDJ's dungeons, then AtlasLoot's own places: without FDJ they're all it has
function Questie.Areas()
    local data = ns.SourceData and ns.SourceData()
    local squash = ns.AtlasLootLists and ns.AtlasLootLists.Squash
    if not data or not squash or not Questie.Enabled() then return {} end
    local atlas = ns.AtlasLootLists.Entries()
    local list = dungeons()
    local same = placeAreasFor == data and placeAreasAtlas == atlas
    if same and placeAreas and next(list) ~= nil then return placeAreas end
    local byName = {}
    for _, dungeon in ipairs(data.dungeons or {}) do
        for _, text in ipairs({dungeon.key, ns.DungeonJournal.DungeonName(dungeon.key)}) do
            local key = squash(text)
            if key and not byName[key] then byName[key] = dungeon.key end
        end
    end
    for _, dungeon in ipairs(atlas.dungeons or {}) do
        local key = squash(dungeon.name)
        if key and not byName[key] then byName[key] = dungeon.key end
    end
    local out = {}
    for area, info in pairs(list) do
        local key = byName[squash(info.name) or ""] or byName[squash(zoneName(area)) or ""]
        if key then out[area] = key end
    end
    if next(list) ~= nil then placeAreas, placeAreasFor, placeAreasAtlas = out, data, atlas end
    return out
end

-- a spawn inside a dungeon becomes the dungeon's entrance
local spawnCache = {}
function Questie.Tables()
    return {entries = entries, names = itemNames, skipReasons = skipReasons, spawns = spawnCache, sod = sodSkipped}
end

function Questie.Locations(kind, id)
    local cacheKey = kind .. ":" .. tostring(id)
    if spawnCache[cacheKey] then return spawnCache[cacheKey] end
    local name = get(kind, id, "name")
    local spawns = get(kind, id, "spawns")
    local out = {}
    for area, points in pairs(type(spawns) == "table" and spawns or {}) do
        local entrances, dungeonName = Questie.DungeonEntrances(area)
        if entrances then
            local label = format(L["%s (entrance)"], zoneName(area) or dungeonName or "?")
            for _, point in ipairs(entrances) do
                out[#out + 1] = {mapID = point.mapID, x = point.x, y = point.y, name = label}
            end
        else
            local map = Questie.UiMapForArea(area)
            for i, point in ipairs(map and type(points) == "table" and points or {}) do
                if i > 50 then break end
                local x, y = type(point) == "table" and point[1], type(point) == "table" and point[2]
                if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                    out[#out + 1] = {mapID = map, x = x / 100, y = y / 100, name = type(name) == "string" and name or "?"}
                end
            end
        end
    end
    spawnCache[cacheKey] = out
    return out
end

function Questie.Starters(questID)
    local startedBy = type(questID) == "number" and get("Quest", questID, "startedBy")
    local out = {}
    if type(startedBy) ~= "table" then return out end
    for _, id in ipairs(type(startedBy[1]) == "table" and startedBy[1] or {}) do
        if type(id) == "number" then out[#out + 1] = {kind = "Npc", id = id} end
    end
    for _, id in ipairs(type(startedBy[2]) == "table" and startedBy[2] or {}) do
        if type(id) == "number" then out[#out + 1] = {kind = "Object", id = id} end
    end
    return out
end

local equippable = Util.Equippable

local refQuests = {}
local function addQuestRefs(questID)
    if refQuests[questID] then return end
    refQuests[questID] = true
    local function add(id)
        id = first(id)
        if type(id) == "number" and id >= SOD_NPC_FIRST and id <= SOD_NPC_LAST and not foreverNpcs[id] then
            foreverNpcs[id] = true
            stats.sodRefs = stats.sodRefs + 1
        end
    end
    for _, field in ipairs({"startedBy", "finishedBy"}) do
        local value = get("Quest", questID, field)
        local npcs = type(value) == "table" and value[1]
        for _, id in ipairs(type(npcs) == "table" and npcs or {}) do add(id) end
    end
    local objectives = get("Quest", questID, "objectives")
    local creatures = type(objectives) == "table" and objectives[1]
    for _, creature in ipairs(type(creatures) == "table" and creatures or {}) do add(creature) end
end

local function finish(found, token)
    if token ~= scanToken then return end
    entries = found
    -- only the scan needs these
    wipe(questCache)
    wipe(npcCache)
    wipe(npcZones)
    wipe(originals)
    wipe(refQuests)
    wipe(keptSodQuests)
    status.state = (stats.rewards + stats.vendors + stats.drops) > 0 and "done" or "nodata"
    ns.RebuildIndex()
end

local function scan()
    scanToken = scanToken + 1
    local token = scanToken
    local lib = db()
    if not lib or type(lib.Item.GetAllIds) ~= "function" then
        status.state = "nodata"
        return
    end
    local list = ids(Util.SafeCall(lib.Item.GetAllIds))
    -- classic items first, so their names are known when Forever's copies come up
    table.sort(list)
    status.state, status.error = "scanning", nil
    stats.items, stats.equippable, stats.rewards, stats.quests, stats.hidden, stats.errors = #list, 0, 0, 0, 0, 0
    stats.vendors, stats.drops, stats.manyVendors, stats.manyDrops, stats.npcs = 0, 0, 0, 0, 0
    stats.implausible, stats.implausibleItems = 0, 0
    stats.sodSkipped, stats.sodNpcs, stats.sodKept, stats.sodRefs = 0, 0, 0, 0
    wipe(skippedSamples)
    wipe(questCache)
    wipe(npcZones)
    wipe(npcCache)
    wipe(sodSkipped)
    wipe(refQuests)
    wipe(keptSodQuests)
    wipe(sodItemSamples)
    wipe(originals)
    wipe(itemNames)
    wipe(skipReasons)
    stats.sodItems, stats.worldDrops = 0, 0
    -- foreverNpcs has to be complete before any source is judged
    local questIDs = type(lib.Quest.GetAllIds) == "function" and Util.SafeCall(lib.Quest.GetAllIds) or nil
    foreverNpcs = type(questIDs) == "table" and {} or nil
    questIDs = foreverNpcs and questIDs or {}
    local phase = foreverNpcs and "quests" or "items"
    local found, position = {}, 1
    local started = Util.Clock()
    local step
    local function run()
        local ok, err = pcall(step)
        if ok or token ~= scanToken then return end
        -- keep what was found so far
        status.error = tostring(err)
        ns.ReportError(err)
        finish(found, token)
    end
    step = function()
        if token ~= scanToken then return end
        if ns.inCombat then return C_Timer.After(1, run) end
        local frameStart = Util.Clock()
        if phase == "quests" then
            while position <= #questIDs do
                local questID = questIDs[position]
                position = position + 1
                if type(questID) == "number" and questID >= FOREVER_QUEST_FIRST then addQuestRefs(questID) end
                if Util.Clock() - frameStart > FRAME_BUDGET_MS then return C_Timer.After(0, run) end
            end
            phase, position = "rewards", 1
        end
        if phase == "rewards" then
            while position <= #list do
                local id = list[position]
                position = position + 1
                if id >= FOREVER_ITEM_FIRST then
                    for _, questID in ipairs(ids(get("Item", id, "questRewards"))) do
                        if questID >= SOD_QUEST_FIRST and questID < FOREVER_QUEST_FIRST then
                            keptSodQuests[questID] = true
                            addQuestRefs(questID)
                        end
                    end
                end
                if Util.Clock() - frameStart > FRAME_BUDGET_MS then return C_Timer.After(0, run) end
            end
            phase, position = "items", 1
        end
        local i = position
        while i <= #list do
            local id = list[i]
            i = i + 1
            if equippable(id) and not ns.Index.TestItem(get("Item", id, "name")) then
                stats.equippable = stats.equippable + 1
                local itemName = get("Item", id, "name")
                if type(itemName) == "string" then itemNames[id] = itemName end
                local sodBefore, implausibleBefore, hiddenBefore = stats.sodSkipped, stats.implausible, stats.hidden
                if id < ORIGINAL_LAST and type(itemName) == "string" then
                    local key = itemName:lower()
                    local ilvl = get("Item", id, "itemLevel")
                    if type(ilvl) == "number" and not originals[key] then originals[key] = ilvl end
                end
                local rewards = get("Item", id, "questRewards")
                local sodItem = foreverNpcs ~= nil and id >= SOD_ITEM_FIRST and id <= SOD_ITEM_LAST
                local before = #found
                if type(rewards) == "table" then
                    for _, questID in ipairs(ids(rewards)) do
                        if sodItem and questID >= SOD_QUEST_FIRST and questID < FOREVER_QUEST_FIRST
                          and not keptSodQuests[questID] then
                            stats.sodSkipped = stats.sodSkipped + 1
                        elseif Questie.HiddenQuest(questID) then
                            stats.hidden = stats.hidden + 1
                        else
                            local info = quest(questID)
                            if info then
                                stats.rewards = stats.rewards + 1
                                local entry = {id = id, kind = "zoneQuest", name = itemName}
                                for key, value in pairs(info) do entry[key] = value end
                                found[#found + 1] = entry
                            end
                        end
                    end
                end
                local itemStart = before
                before = #found
                local sold = npcEntries(found, id, itemName, "vendor", get("Item", id, "vendors"), sodItem)
                stats.vendors = stats.vendors + sold
                if found[#found] and found[#found].many and #found > before then stats.manyVendors = stats.manyVendors + 1 end
                before = #found
                local dropped, world = npcEntries(found, id, itemName, "npcDrop", get("Item", id, "npcDrops"), sodItem)
                stats.drops = stats.drops + dropped
                if world then
                    stats.worldDrops = stats.worldDrops + 1
                elseif found[#found] and found[#found].many and #found > before then
                    stats.manyDrops = stats.manyDrops + 1
                end
                if #found == itemStart then
                    -- SoD first: its gear is often a joke drop too
                    if stats.sodSkipped > sodBefore then
                        skipReasons[id] = "sod"
                    elseif stats.implausible > implausibleBefore then
                        skipReasons[id] = "implausible"
                    elseif stats.hidden > hiddenBefore then
                        skipReasons[id] = "hidden"
                    end
                end
                if sodItem and #found == itemStart and (type(rewards) == "table" or get("Item", id, "vendors")
                                                        or get("Item", id, "npcDrops")) then
                    stats.sodItems = stats.sodItems + 1
                    if #sodItemSamples < SOD_SAMPLES then
                        sodItemSamples[#sodItemSamples + 1] = id .. " " .. tostring(itemName)
                    end
                end
            end
            if Util.Clock() - frameStart > FRAME_BUDGET_MS then break end
        end
        position = i
        if position <= #list then return C_Timer.After(0, run) end
        stats.ms = Util.Clock() - started
        status.ms = stats.ms
        finish(found, token)
    end
    run()
end

function Questie.Init()
    if not Questie.Installed() or not Questie.Enabled() then
        status.state = "off"
        return
    end
    status.state = "waiting"
    local function ready() ns.Guard(scan) end
    local addon = questie()
    if addon and type(addon.API.RegisterOnReady) == "function" then
        local ok = pcall(addon.API.RegisterOnReady, ready)
        if ok then return end
    end
    if addon and addon.API.isReady then return ready() end
    C_Timer.After(ALONE_DELAY, ready)
end

function Questie.SetEnabled(value)
    ns.addon.db.profile.questie = value and true or false
    if value then
        if status.state == "off" then Questie.Init() else ns.RebuildIndex() end
    else
        ns.RebuildIndex()
    end
end

-- not Questie's public API, every step is checked
local function searchResults()
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local ok, module = pcall(loader.ImportModule, loader, "QuestieSearchResults")
    if ok and type(module) == "table" and type(module.GetDetailFrame) == "function" then return module end
    return nil
end

function Questie.CanOpen(questID) return type(questID) == "number" and questie() ~= nil and searchResults() ~= nil end

function Questie.Open(questID)
    if not Questie.CanOpen(questID) then return false end
    local module = searchResults()
    return (pcall(module.GetDetailFrame, module, "quest", questID))
end

-- only the logged-in character's are known

local completed = {}
local allLoaded, tried = false, false

local function loadCompleted()
    tried, allLoaded = true, true
    wipe(completed)
    local getAll = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs
    if type(getAll) == "function" then
        local ok, list = pcall(getAll)
        if ok and type(list) == "table" then
            for _, id in ipairs(list) do if type(id) == "number" then completed[id] = true end end
            return
        end
    end
    allLoaded = false
end

function Questie.IsCompleted(questID)
    if not tried then loadCompleted() end
    local known = completed[questID]
    if known ~= nil then return known end
    if allLoaded then return false end
    local check = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or rawget(_G, "IsQuestFlaggedCompleted")
    local ok, done = false, nil
    if type(check) == "function" then ok, done = pcall(check, questID) end
    completed[questID] = ok and done == true
    return completed[questID]
end

function Questie.OnQuestTurnedIn(questID)
    if type(questID) == "number" and not isSecret(questID) then completed[questID] = true end
end
