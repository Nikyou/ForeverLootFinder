-- pure Lua, no WoW calls
local _, ns = ...

local Index = {}
ns.Index = Index

Index.SLOTS = {
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "ONEHAND",
    "MAINHAND", "TWOHAND", "OFFHAND", "RANGED", "RELIC",
}
-- kinds: boss, rare, trash, shared, probable, combine, quest, zoneQuest, craft, reputation, pvp, event, world, vendor,
-- npcDrop.
-- a QuestieDB creature drop inside a dungeon or raid becomes boss, rare or trash with creature = true
Index.DROP_KINDS = {boss = true, rare = true, trash = true, shared = true, probable = true}
function Index.IsQuest(source) return source.kind == "quest" or source.kind == "zoneQuest" end

local EQUIP_SLOT = {
    INVTYPE_HEAD = "HEAD",
    INVTYPE_NECK = "NECK",
    INVTYPE_SHOULDER = "SHOULDER",
    INVTYPE_CLOAK = "BACK",
    INVTYPE_CHEST = "CHEST",
    INVTYPE_ROBE = "CHEST",
    INVTYPE_WRIST = "WRIST",
    INVTYPE_HAND = "HANDS",
    INVTYPE_WAIST = "WAIST",
    INVTYPE_LEGS = "LEGS",
    INVTYPE_FEET = "FEET",
    INVTYPE_FINGER = "FINGER",
    INVTYPE_TRINKET = "TRINKET",
    INVTYPE_WEAPON = "ONEHAND",
    INVTYPE_WEAPONMAINHAND = "MAINHAND",
    INVTYPE_2HWEAPON = "TWOHAND",
    INVTYPE_WEAPONOFFHAND = "OFFHAND",
    INVTYPE_SHIELD = "OFFHAND",
    INVTYPE_HOLDABLE = "OFFHAND",
    INVTYPE_RANGED = "RANGED",
    INVTYPE_RANGEDRIGHT = "RANGED",
    INVTYPE_THROWN = "RANGED",
    INVTYPE_RELIC = "RELIC",
}
Index.EQUIP_SLOT = EQUIP_SLOT

local ARMOR_SUBCLASS = {
    [1] = "CLOTH",
    [2] = "LEATHER",
    [3] = "MAIL",
    [4] = "PLATE",
    [6] = "SHIELD",
    [7] = "LIBRAM",
    [8] = "IDOL",
    [9] = "TOTEM",
}
local WEAPON_SUBCLASS = {
    [0] = "AXE1H",
    [1] = "AXE2H",
    [2] = "BOW",
    [3] = "GUN",
    [4] = "MACE1H",
    [5] = "MACE2H",
    [6] = "POLEARM",
    [7] = "SWORD1H",
    [8] = "SWORD2H",
    [10] = "STAFF",
    [13] = "FIST",
    [15] = "DAGGER",
    [16] = "THROWN",
    [18] = "CROSSBOW",
    [19] = "WAND",
}
local CLASS_WEAPON, CLASS_ARMOR = 2, 4

local ARMOR_KINDS = {CLOTH = true, LEATHER = true, MAIL = true, PLATE = true}
Index.ARMOR_KINDS = ARMOR_KINDS

function Index.SlotFromEquipLoc(equipLoc) return EQUIP_SLOT[equipLoc] end

-- nil for jewellery and the like
function Index.TypeFromClass(classID, subclassID, equipLoc)
    if equipLoc == "INVTYPE_HOLDABLE" then return "HELD" end
    if classID == CLASS_ARMOR then return ARMOR_SUBCLASS[subclassID] end
    if classID == CLASS_WEAPON then return WEAPON_SUBCLASS[subclassID] end
    return nil
end

-- only for items without an ID. English, with a few spellings
local TEXT_SLOT = {
    ["head"] = "HEAD",
    ["neck"] = "NECK",
    ["shoulder"] = "SHOULDER",
    ["back"] = "BACK",
    ["chest"] = "CHEST",
    ["wrist"] = "WRIST",
    ["hands"] = "HANDS",
    ["waist"] = "WAIST",
    ["legs"] = "LEGS",
    ["feet"] = "FEET",
    ["finger"] = "FINGER",
    ["trinket"] = "TRINKET",
    ["one-hand"] = "ONEHAND",
    ["main hand"] = "MAINHAND",
    ["two-hand"] = "TWOHAND",
    ["off hand"] = "OFFHAND",
    ["held in off-hand"] = "OFFHAND",
    ["ranged"] = "RANGED",
    ["thrown"] = "RANGED",
    ["relic"] = "RELIC",
}
local TEXT_TYPE = {
    cloth = "CLOTH",
    leather = "LEATHER",
    mail = "MAIL",
    plate = "PLATE",
    shield = "SHIELD",
    libram = "LIBRAM",
    idol = "IDOL",
    totem = "TOTEM",
    dagger = "DAGGER",
    ["fist weapon"] = "FIST",
    polearm = "POLEARM",
    staff = "STAFF",
    bow = "BOW",
    gun = "GUN",
    crossbow = "CROSSBOW",
    wand = "WAND",
    thrown = "THROWN",
}
local HANDED = {sword = "SWORD", axe = "AXE", mace = "MACE"}

function Index.FromSlotText(text)
    if type(text) ~= "string" then return nil, nil end
    local first, second = text:match("^%s*([^,]+),%s*(.-)%s*$")
    first = (first or text):lower():gsub("%s+$", "")
    second = second and second:lower() or nil
    local slot = TEXT_SLOT[first]
    if not slot then return nil, nil end
    local itemType
    if first == "held in off-hand" then
        itemType = "HELD"
    elseif first == "thrown" then
        itemType = "THROWN"
    elseif second then
        itemType = TEXT_TYPE[second]
        if not itemType and HANDED[second] then itemType = HANDED[second] .. (slot == "TWOHAND" and "2H" or "1H") end
    end
    if slot == "BACK" or slot == "NECK" or slot == "FINGER" or slot == "TRINKET" then itemType = nil end
    return slot, itemType
end

-- the developers' own items, still in the game's data: "Ring of Uber Resists (TEST)", "Monster - Spear, Rusty",
-- "OLDThug Belt". English on every client. "Testament of Hope" is a real one
local TEST_NAMES = {
    "%f[%a][Tt][Ee][Ss][Tt]%f[%A]", "^Monster %- ", "^OLD%u", "%[PH%]", "^Deprecated ", "^Unused ", "^[Zz][Zz]", "^Placeholder$",
}
function Index.TestItem(name)
    if type(name) ~= "string" then return false end
    for _, pattern in ipairs(TEST_NAMES) do if name:find(pattern) then return true end end
    return false
end

-- ID 0: FDJ hasn't learned it yet, merge by name
function Index.KeyOf(entry)
    if entry.id and entry.id > 0 then return entry.id end
    return "name:" .. (entry.name or ""):lower()
end

-- FDJ and ATT know Forever's dungeons, Questie has quest IDs and levels, ForeverDB links recipes to their items, FDJ
-- has Forever's PvP rewards. the rest fill gaps
Index.DEFAULT_PRIORITY = {
    drops = {"fdj", "att", "atlasloot", "questie", "foreverdb"},
    quests = {"questie", "fdj", "att", "foreverdb", "atlasloot"},
    crafts = {"skillup", "foreverdb", "atlasloot", "att", "tradeskill"},
    vendors = {"questie", "foreverdb", "att"},
    creatures = {"questie", "foreverdb", "att"},
    lists = {"fdj", "atlasloot", "att"},
}

-- Forever has no raids open yet: what the addons list for raids and world bosses is classic's. off, their places go and
-- so does every line tied to one
Index.RAIDS_OPEN = false
-- for creature drops no raid place took: the classic raids' instances and areas and the world bosses (AtlasLoot's raid
-- lists; Naxxramas's instance from forever-db's spawns)
local RAID_INSTANCES = {[409] = true, [249] = true, [309] = true, [469] = true, [509] = true, [531] = true, [533] = true}
local RAID_AREAS = {[2717] = true, [2159] = true, [1977] = true, [2677] = true, [3429] = true, [3428] = true, [3456] = true}
local WORLD_BOSSES = {[6109] = true, [12397] = true, [14887] = true, [14888] = true, [14889] = true, [14890] = true}

-- the battlegrounds' factions, to FDJ's battleground keys: their rewards are PvP rewards, not reputation ones.
-- Darkspear Islands is Forever's own
Index.PVP_FACTIONS = {
    [890] = "WSG",
    [889] = "WSG",
    [509] = "AB",
    [510] = "AB",
    [730] = "AV",
    [729] = "AV",
    [2799] = "DI",
    [2798] = "DI",
}

local LIST_GROUP = {reputation = true, pvp = true, event = true}
local function groupOf(kind)
    if Index.DROP_KINDS[kind] then return "drops" end
    if kind == "quest" or kind == "zoneQuest" then return "quests" end
    if kind == "craft" then return "crafts" end
    if kind == "vendor" then return "vendors" end
    if kind == "npcDrop" then return "creatures" end
    if LIST_GROUP[kind] then return "lists" end
    return nil
end

local function lower(text) return type(text) == "string" and text:lower() or nil end

local function sameCreature(a, b)
    if a.many and b.many then return true end
    local ids = {}
    for _, id in ipairs(a.npcs or {}) do ids[id] = true end
    if a.npcID then ids[a.npcID] = true end
    if b.npcID and ids[b.npcID] then return true end
    for _, id in ipairs(b.npcs or {}) do if ids[id] then return true end end
    return false
end

-- AtlasLoot's Tarnished Undermine Real list names no vendor: it's the one the other addons name
local function anyVendor(group, a, b)
    local function nameless(s) return not (s.many or s.npcID or (s.npcs and #s.npcs > 0)) end
    return group == "vendors" and (nameless(a) or nameless(b))
end

local function overlap(group, a, b)
    if group == "drops" then return a.dungeon ~= nil and a.dungeon == b.dungeon end
    if group == "crafts" then return a.profession == b.profession end
    if group == "vendors" or group == "creatures" then return sameCreature(a, b) or anyVendor(group, a, b) end
    if group == "lists" then
        if a.kind ~= b.kind then return false end
        if a.holiday and b.holiday then return a.holiday == b.holiday end
        return a.kind ~= "reputation" or not (a.factionID and b.factionID) or a.factionID == b.factionID
    end
    if a.questID and b.questID then return a.questID == b.questID end
    local na, nb = lower(a.questName), lower(b.questName)
    if na and nb then return na == nb end
    -- AtlasLoot's quest sections have no names
    return a.dungeon ~= nil and a.dungeon == b.dungeon
end

local QUEST_MERGE_FIELDS = {
    "dungeon", "questID", "questName", "questLevel", "reqLevel", "zoneKey", "zoneName", "raceMask", "classMask", "faction",
    "classOnly", "areas",
}
-- what the entry that stays takes from the one that goes, where it has none
local MERGE_FIELDS = {
    crafts = {"skill", "spell", "recipe"},
    creatures = {"chance", "zone", "zoneKey", "zoneName", "levelMin", "levelMax"},
    vendors = {"faction", "zone", "zoneKey", "zoneName", "price"},
    lists = {"standing", "factionID", "factionName", "section", "pvpKey", "pvpRank", "eventName", "holiday", "price"},
}

local function rankOf(priority, group, provider)
    for i, name in ipairs(priority[group] or {}) do if name == provider then return i end end
    return 99
end

-- where FDJ has no drop chance its bosses borrow AtlasLoot's before the overlap drops one of them
local function shareChances(record)
    local sources = record.sources
    if #sources < 2 then return end
    for _, from in ipairs(sources) do
        if from.chance and not from.chanceGuess and from.dungeon and Index.DROP_KINDS[from.kind] then
            local same, sameBoss = {}, nil
            local boss = lower(from.bossName)
            for _, to in ipairs(sources) do
                if to ~= from and to.provider ~= from.provider and to.dungeon == from.dungeon and Index.DROP_KINDS[to.kind]
                  and (not to.chance or to.chanceGuess) then
                    same[#same + 1] = to
                    if boss and lower(to.bossName) == boss then sameBoss = to end
                end
            end
            local to = sameBoss or (#same == 1 and same[1]) or nil
            if to then
                to.chance = from.chance
                to.chanceFrom = from.provider
            end
        end
    end
end

-- one addon's own sources never overlap each other (two bosses, one dungeon)
local function resolveOverlaps(record, priority, dungeonByKey)
    local sources = record.sources
    if #sources < 2 then return end
    local removed = {}
    for i = 1, #sources do
        for j = i + 1, #sources do
            local a, b = sources[i], sources[j]
            local group = groupOf(a.kind)
            if not removed[a] and not removed[b] and a.provider ~= b.provider and group and group == groupOf(b.kind)
              and overlap(group, a, b) then
                local winner, loser = a, b
                if rankOf(priority, group, b.provider) < rankOf(priority, group, a.provider) then
                    winner, loser = b, a
                end
                removed[loser] = true
                for _, field in ipairs(MERGE_FIELDS[group] or {}) do
                    if winner[field] == nil and loser[field] ~= nil then
                        winner[field] = loser[field]
                        if field == "chance" then winner.chanceFrom = loser.provider end
                    end
                end
                if group == "quests" then
                    for _, field in ipairs(QUEST_MERGE_FIELDS) do
                        if winner[field] == nil then winner[field] = loser[field] end
                    end
                    if winner.dungeon then
                        winner.kind = "quest"
                        local dungeon = dungeonByKey[winner.dungeon]
                        winner.order = dungeon and dungeon.order or winner.order
                    end
                end
            end
        end
    end
    if next(removed) == nil then return end
    local kept = {}
    for _, source in ipairs(sources) do if not removed[source] then kept[#kept + 1] = source end end
    record.sources = kept
end

local function newRecord(index, entry)
    local key = Index.KeyOf(entry)
    local record = index.byKey[key]
    if not record then
        record = {key = key, id = entry.id or 0, name = entry.name, sources = {}}
        index.byKey[key] = record
        index.records[#index.records + 1] = record
    end
    if not record.slotText and entry.slotText then record.slotText = entry.slotText end
    if not record.quality and entry.quality then record.quality = entry.quality end
    if not record.tip and entry.tip then record.tip = entry.tip end
    if (record.name or "") == "" then record.name = entry.name end
    if entry.randomBonus then record.randomBonus = true end
    return record
end

local KIND_ORDER = {
    zoneQuest = 1000,
    vendor = 1500,
    npcDrop = 1600,
    craft = 2000,
    reputation = 3000,
    pvp = 3100,
    event = 3200,
    world = 3300,
}

-- a creature drop inside a dungeon becomes its boss, rare or trash, to overlap with FDJ and AtlasLoot. a known boss
-- and an area wings share wait for tieByCreature
local function tieCreature(source, index)
    if source.kind ~= "npcDrop" or source.dungeon or not source.zone then return end
    if index.placesByArea[source.zone] or (not source.many and source.npcID and index.bossByNpc[source.npcID]) then return end
    local key = index.placeByArea[source.zone]
    if not (key and index.dungeonByKey[key]) then return end
    source.dungeon, source.creature = key, true
    if source.many then
        source.kind = "trash"
    else
        source.kind = source.rare and "rare" or "boss"
        source.bossName = source.npcName
    end
end

-- how: counted in index.merged for the status dump
local function tieTo(source, key, index, boss, how)
    index.merged[how] = (index.merged[how] or 0) + 1
    source.dungeon, source.creature = key, true
    if boss then
        source.kind, source.bossName = boss.kind or "boss", boss.bossName
    elseif source.many then
        source.kind = "trash"
    else
        source.kind = source.rare and "rare" or "boss"
        source.bossName = source.npcName
    end
    local dungeon = index.dungeonByKey[key]
    source.order = dungeon and dungeon.order or source.order
end

-- the item's own boss or trash line naming the creature: Forever's dungeons have no creature IDs in FDJ
local function namedBy(record, name)
    name = lower(name)
    if not name then return nil end
    for _, source in ipairs(record.sources) do
        if source.dungeon and Index.DROP_KINDS[source.kind] and not source.creature then
            if lower(source.bossName) == name then return source end
            local mobs = lower(source.mobs)
            if mobs then
                for mob in mobs:gmatch("[^/,]+") do if mob:match("^%s*(.-)%s*$") == name then return source end end
            end
        end
    end
    return nil
end

-- creature drops tieCreature couldn't place: a boss's own creature, a creature the item's boss or trash line names, a
-- spawn in a dungeon's instance or an area its wings share (the wing the item drops in), a few zones with a place the
-- item drops in among them, or creatures with no spawn at all: only instances' creatures lack one
local function tieByCreature(record, index)
    local places
    -- the places the item drops in, in its sources' order
    local function droppedIn()
        if not places then
            places = {}
            for _, source in ipairs(record.sources) do
                local key = source.dungeon
                if key and Index.DROP_KINDS[source.kind] and not places[key] then
                    places[key] = true
                    places[#places + 1] = key
                end
            end
        end
        return places
    end
    local function firstIn(keys)
        local set = droppedIn()
        for _, key in ipairs(keys) do if set[key] then return key end end
        return nil
    end
    for _, source in ipairs(record.sources) do
        if source.kind == "npcDrop" and not source.dungeon then
            local boss = not source.many and source.npcID and index.bossByNpc[source.npcID]
            local named = not source.many and not boss and namedBy(record, source.npcName)
            local key, how
            if boss and index.dungeonByKey[boss.dungeon] then
                tieTo(source, boss.dungeon, index, boss, "boss creature")
            elseif named then
                tieTo(source, named.dungeon, index,
                      {kind = named.kind, bossName = named.kind ~= "trash" and named.bossName or nil}, "name")
            elseif source.instance and index.placesByInstance[source.instance] then
                how = "instance"
                -- with creatures outside too, only where the item drops anyway
                local keys = index.placesByInstance[source.instance]
                local outside = source.zone or (source.zones and source.zones[1])
                key = firstIn(keys) or (#keys == 1 and not outside and keys[1]) or nil
            elseif source.zone and index.placesByArea[source.zone] then
                local keys = index.placesByArea[source.zone]
                key, how = firstIn(keys) or keys[1], "wing"
            elseif source.zoneSet then
                local keys = {}
                for _, zone in ipairs(source.zoneSet) do keys[#keys + 1] = index.placeByArea[zone] end
                key, how = firstIn(keys), "zones"
            elseif not source.zone and not (source.zones and source.zones[1]) then
                key, how = droppedIn()[1], "no spawn"
            end
            if key and index.dungeonByKey[key] then tieTo(source, key, index, nil, how) end
        end
    end
end

-- a line for a whole split dungeon (ATT's Scarlet Monastery, beside its wings) goes to the wing the item drops in
local function tieToWing(record, index)
    local places
    for _, source in ipairs(record.sources) do
        local wings = source.dungeon and index.splits[source.dungeon]
        if wings then
            if not places then
                places = {}
                for _, other in ipairs(record.sources) do if other.dungeon then places[other.dungeon] = true end end
            end
            for _, key in ipairs(wings) do
                if places[key] and index.dungeonByKey[key] then
                    index.merged.split = (index.merged.split or 0) + 1
                    source.dungeon = key
                    source.order = index.dungeonByKey[key].order or source.order
                    break
                end
            end
        end
    end
end

-- a source keeps its addon's entry in [1] and reads through to it, holding only what the index sets on it: a build
-- copies nothing and the entries stay as their addon made them. a field on the entry itself would often double its size
local SOURCE = {__index = function(source, key) return rawget(source, 1)[key] end}

-- a plain copy of a source, its entry's fields too
function Index.Flat(source)
    local out = {}
    local entry = rawget(source, 1)
    for key, value in pairs(entry or {}) do out[key] = value end
    for key, value in pairs(source) do if key ~= 1 then out[key] = value end end
    return out
end

local function addSource(index, entry, provider)
    if Index.TestItem(entry.name) then return end
    local record = newRecord(index, entry)
    local source = setmetatable({entry}, SOURCE)
    if not entry.provider then source.provider = provider end
    tieCreature(source, index)
    local dungeon = source.dungeon and index.dungeonByKey[source.dungeon]
    source.order = dungeon and dungeon.order or KIND_ORDER[entry.kind] or 999
    record.sources[#record.sources + 1] = source
    if source.chance then index.hasChance = true end
end

-- a raid wins over a dungeon
local function tieToPlace(source, placeByArea, dungeonByKey)
    if source.dungeon or type(source.areas) ~= "table" then return end
    local found
    for _, area in ipairs(source.areas) do
        local key = placeByArea[area]
        local place = key and dungeonByKey[key]
        if place and (not found or (place.raid and not dungeonByKey[found].raid)) then found = key end
    end
    source.tiedTo = found
end

local LIST_KINDS = {reputation = true, pvp = true, event = true, world = true}

-- SilverDragon's rare beside another addon's drop from the same creature
local function dropRepeatedRares(record)
    local creatures
    for _, source in ipairs(record.sources) do
        if source.provider ~= "silverdragon" then
            for _, id in ipairs(source.npcs or {}) do
                creatures = creatures or {}
                creatures[id] = true
            end
            if source.npcID then
                creatures = creatures or {}
                creatures[source.npcID] = true
            end
        end
    end
    if not creatures then return end
    local kept = {}
    for _, source in ipairs(record.sources) do
        if not (source.provider == "silverdragon" and source.npcID and creatures[source.npcID]) then
            kept[#kept + 1] = source
        end
    end
    if #kept < #record.sources then record.sources = kept end
end

-- AtlasLoot's world epics and QuestieDB's spread-out drops are the same thing: one line, AtlasLoot's section with
-- QuestieDB's creature levels
local function mergeWorld(record)
    local first
    local kept = {}
    for _, source in ipairs(record.sources) do
        if source.kind ~= "world" then
            kept[#kept + 1] = source
        elseif not first then
            first = source
            kept[#kept + 1] = source
        else
            if source.section and not first.section then
                first.section, first.provider = source.section, source.provider
            end
            first.levelMin = math.min(first.levelMin or source.levelMin or 99, source.levelMin or first.levelMin or 99)
            if first.levelMin == 99 then first.levelMin = nil end
            first.levelMax = math.max(first.levelMax or 0, source.levelMax or 0)
            if first.levelMax == 0 then first.levelMax = nil end
            first.worldDrop = first.worldDrop or source.worldDrop
        end
    end
    if #kept < #record.sources then record.sources = kept end
end

-- what another addon lists beside a reward list is how you get it there: the PvP or faction vendor, the event's
-- creatures, the quest the list already names (viaQuests). and a world drop's creatures are a few of the many that
-- drop it. one line, so the list's own switch decides. creature levels widen a world line's range but never start one
local REWARD_LISTS = {pvp = true, reputation = true, event = true}
local function foldIntoLists(record, merged)
    local list, world
    for _, source in ipairs(record.sources) do
        if REWARD_LISTS[source.kind] then
            list = list or source
        elseif source.kind == "world" then
            world = world or source
        end
    end
    if not list and not world then return end
    local kept = {}
    for _, source in ipairs(record.sources) do
        local kind = source.kind
        if list and (kind == "vendor" or kind == "npcDrop" or Index.IsQuest(source)) then
            merged[list.kind] = (merged[list.kind] or 0) + 1
            if kind == "vendor" then
                if list.faction == nil and source.faction then list.faction = source.faction end
                if list.price == nil and source.price then list.price = source.price end
            end
        elseif world and (kind == "npcDrop" or (source.creature and Index.DROP_KINDS[kind])) then
            merged.world = (merged.world or 0) + 1
            local low, high = source.levelMin, source.levelMax
            if world.levelMin and low and low < world.levelMin then world.levelMin = low end
            if world.levelMax and high and high > world.levelMax then world.levelMax = high end
        else
            kept[#kept + 1] = source
        end
    end
    if #kept < #record.sources then record.sources = kept end
end

-- reputation pages also list quest rewards: take the quest's level so a done quest hides it too
-- (Earthpower Vest on Cenarion Circle's page)
local function crossCheckQuests(record)
    local quests, level, name
    for _, source in ipairs(record.sources) do
        if Index.IsQuest(source) and source.questID then
            quests = quests or {}
            quests[#quests + 1] = source.questID
            name = name or source.questName
            if source.reqLevel and (not level or source.reqLevel < level) then level = source.reqLevel end
        end
    end
    if not quests then return end
    for _, source in ipairs(record.sources) do
        if LIST_KINDS[source.kind] then
            source.viaQuests, source.viaQuestName = quests, name
            if level and not source.reqLevel then source.reqLevel = level end
        end
    end
end

-- with no event list from AtlasLoot or ATT, a holiday's quest is the item's event line, so the Events switch and card
-- work without them
local function holidayLine(record, holiday, merged)
    if not holiday then return end
    local quests, line, key = {}, nil, nil
    for _, source in ipairs(record.sources) do
        if source.kind == "event" then return end
        if Index.IsQuest(source) and source.questID then
            quests[#quests + 1] = source.questID
            if not line then
                key = holiday(source.questID)
                if key then line = source end
            end
        end
    end
    if not line then return end
    line.kind, line.holiday = "event", key
    line.viaQuests, line.viaQuestName = quests, line.questName
    merged.holiday = (merged.holiday or 0) + 1
end

-- a line in a raid or world boss place, a quest tied to one, or a creature in a raid's instance or area or a world boss
local function inRaid(source, dungeonByKey)
    local key = source.dungeon or source.tiedTo
    local place = key and dungeonByKey[key]
    if place and place.raid then return true end
    if RAID_INSTANCES[source.instance or 0] or RAID_AREAS[source.zone or 0] or WORLD_BOSSES[source.npcID or 0] then return true end
    if source.many or not source.npcs or #source.npcs == 0 then return false end
    for _, id in ipairs(source.npcs) do if not WORLD_BOSSES[id] then return false end end
    return true
end

local function dropRaids(record, index)
    local kept = {}
    for _, source in ipairs(record.sources) do
        if inRaid(source, index.dungeonByKey) then
            index.raidLines = index.raidLines + 1
        else
            kept[#kept + 1] = source
        end
    end
    if #kept < #record.sources then record.sources = kept end
end

local function sourceOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    local bossA, bossB = a.bossIndex or 999, b.bossIndex or 999
    if bossA ~= bossB then return bossA < bossB end
    local levelA, levelB = a.reqLevel or a.skill or 0, b.reqLevel or b.skill or 0
    if levelA ~= levelB then return levelA < levelB end
    if (a.kind or "") ~= (b.kind or "") then return (a.kind or "") < (b.kind or "") end
    return (a.questName or a.professionName or a.section or "") < (b.questName or b.professionName or b.section or "")
end

-- extras: entry lists or {entries, dungeons, provider}, their dungeons go after FDJ's. quests: Questie's word on a
-- quest, hidden(questID) leaves it out (FDJ's are checked on Forever and stay), holiday(questID) is its holiday's key
function Index.Build(data, extras, priority, quests)
    local hiddenQuest, holiday = quests and quests.hidden, quests and quests.holiday
    local index = {
        records = {},
        byKey = {},
        dungeons = {},
        dungeonByKey = {},
        hasChance = false,
        placeByArea = {},
        placesByArea = {},
        splits = {},
        placesByInstance = {},
        bossByNpc = {},
        merged = {},
        hiddenQuests = 0,
        raidLines = 0,
        rankLines = 0, -- AtlasLoot's classic rank rewards, left out beside FDJ's Honor list
    }
    for _, dungeon in ipairs(data.dungeons or {}) do
        index.dungeons[#index.dungeons + 1] = dungeon
        index.dungeonByKey[dungeon.key] = dungeon
        for _, boss in ipairs(dungeon.bosses or {}) do
            if boss.npcID and not index.bossByNpc[boss.npcID] then
                index.bossByNpc[boss.npcID] = {dungeon = dungeon.key, bossName = boss.name, kind = boss.kind}
            end
        end
    end
    for key, dungeon in pairs(data.dungeonByKey or {}) do index.dungeonByKey[key] = index.dungeonByKey[key] or dungeon end
    for _, extra in ipairs(extras or {}) do
        for area, key in pairs(extra.areas or {}) do index.placeByArea[area] = index.placeByArea[area] or key end
        for area, keys in pairs(extra.wings or {}) do index.placesByArea[area] = index.placesByArea[area] or keys end
        for key, wings in pairs(extra.splits or {}) do index.splits[key] = wings end
        -- AtlasLoot's raids, FDJ's dungeons through ForeverDB: one may know a wing the other doesn't
        for instance, keys in pairs(extra.instances or {}) do
            local list = index.placesByInstance[instance] or {}
            index.placesByInstance[instance] = list
            for _, key in ipairs(keys) do
                local known = false
                for _, k in ipairs(list) do if k == key then known = true end end
                if not known then list[#list + 1] = key end
            end
        end
        for npc, boss in pairs(extra.npcs or {}) do index.bossByNpc[npc] = index.bossByNpc[npc] or boss end
        for _, dungeon in ipairs(extra.dungeons or {}) do
            if not index.dungeonByKey[dungeon.key] then
                dungeon.order = #index.dungeons + 1
                index.dungeons[#index.dungeons + 1] = dungeon
                index.dungeonByKey[dungeon.key] = dungeon
            end
        end
    end
    local fdjHonor = false
    for _, entry in ipairs(data.entries or {}) do
        addSource(index, entry, "fdj")
        if entry.pvpKey == "honor" then fdjHonor = true end
    end
    for _, extra in ipairs(extras or {}) do
        for _, entry in ipairs(extra.entries or extra) do
            if hiddenQuest and entry.questID and Index.IsQuest(entry) and hiddenQuest(entry.questID) then
                index.hiddenQuests = index.hiddenQuests + 1
            elseif entry.rankList and fdjHonor then
                index.rankLines = index.rankLines + 1
            elseif entry.id and entry.id > 0 then
                addSource(index, entry, extra.provider)
            end
        end
    end
    priority = priority or Index.DEFAULT_PRIORITY
    for _, record in ipairs(index.records) do
        tieByCreature(record, index)
        tieToWing(record, index)
        shareChances(record)
        resolveOverlaps(record, priority, index.dungeonByKey)
        mergeWorld(record)
        dropRepeatedRares(record)
        for _, source in ipairs(record.sources) do tieToPlace(source, index.placeByArea, index.dungeonByKey) end
        if not Index.RAIDS_OPEN then dropRaids(record, index) end
        crossCheckQuests(record)
        holidayLine(record, holiday, index.merged)
        foldIntoLists(record, index.merged)
        if #record.sources > 1 then table.sort(record.sources, sourceOrder) end
        record.order = record.sources[1] and record.sources[1].order or 999
    end
    if not Index.RAIDS_OPEN then
        local records, dungeons = {}, {}
        for _, record in ipairs(index.records) do
            if #record.sources > 0 then
                records[#records + 1] = record
            else
                index.byKey[record.key] = nil
            end
        end
        for _, dungeon in ipairs(index.dungeons) do
            if dungeon.raid then
                index.dungeonByKey[dungeon.key] = nil
            else
                dungeons[#dungeons + 1] = dungeon
            end
        end
        index.records, index.dungeons = records, dungeons
    end
    -- a whole split dungeon whose lines all went to their wings
    if next(index.splits) then
        local used, dungeons = {}, {}
        for _, record in ipairs(index.records) do
            for _, source in ipairs(record.sources) do if source.dungeon then used[source.dungeon] = true end end
        end
        for _, dungeon in ipairs(index.dungeons) do
            if index.splits[dungeon.key] and not used[dungeon.key] then
                index.dungeonByKey[dungeon.key] = nil
            else
                dungeons[#dungeons + 1] = dungeon
            end
        end
        index.dungeons = dungeons
    end
    return index
end
