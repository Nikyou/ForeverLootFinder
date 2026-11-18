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

-- ID 0: FDJ hasn't learned it yet, merge by name
function Index.KeyOf(entry)
    if entry.id and entry.id > 0 then return entry.id end
    return "name:" .. (entry.name or ""):lower()
end

local SOURCE_FIELDS = {
    "dungeon", "bossIndex", "bossName", "kind", "faction", "mobs", "allTrash", "chance", "questName", "questID", "questLevel",
    "classOnly",
    -- fdj, questie, atlasloot or tradeskill
    "provider",
    "zoneKey", "zoneName", "reqLevel", "raceMask", "classMask",
    -- every area a quest touches, to tie it to a raid
    "areas",
    "profession", "professionName", "skill", "spell", "recipe", "recipeSource",
    "factionID", "factionName", "standing", "pvpRank", "eventName", "section",
    -- to open AtlasLoot's window there
    "alModule", "alContent", "alBoss",
    -- set when the chance was borrowed from another addon
    "chanceFrom",
    -- count, ids and zones only on a "many" source
    "npcID", "npcName", "npcLevel", "npcs", "zone", "zones", "moreZones", "levelMin", "levelMax", "rare", "many", "count",
    "creature", "worldDrop",
    -- FDJ: the halves of a combined item, an extremely rare drop, which trash drops it
    "parts", "rareDrop", "chanceGuess", "sourceTip",
}

-- FDJ knows Forever's dungeons best, Questie has quest IDs and levels, AtlasLoot has craft skill levels
Index.DEFAULT_PRIORITY = {
    drops = {"fdj", "atlasloot", "questie"},
    quests = {"questie", "fdj", "atlasloot"},
    crafts = {"atlasloot", "tradeskill"},
}

local function groupOf(kind)
    if Index.DROP_KINDS[kind] then return "drops" end
    if kind == "quest" or kind == "zoneQuest" then return "quests" end
    if kind == "craft" then return "crafts" end
    return nil
end

local function lower(text) return type(text) == "string" and text:lower() or nil end

local function overlap(group, a, b)
    if group == "drops" then return a.dungeon ~= nil and a.dungeon == b.dungeon end
    if group == "crafts" then return a.profession == b.profession end
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
                if rankOf(priority, group, b.provider) < rankOf(priority, group, a.provider) then winner, loser = b, a end
                removed[loser] = true
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
        record = {key = key, id = entry.id or 0, name = entry.name, sources = {}, randomBonus = false}
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

local KIND_ORDER = {zoneQuest = 1000, vendor = 1500, npcDrop = 1600, craft = 2000, reputation = 3000, pvp = 3100,
                    event = 3200, world = 3300}

-- a creature drop inside a dungeon becomes its boss, rare or trash, to overlap with FDJ and AtlasLoot
local function tieCreature(source, placeByArea, dungeonByKey)
    if source.kind ~= "npcDrop" or source.dungeon or not source.zone then return end
    local key = placeByArea[source.zone]
    if not (key and dungeonByKey[key]) then return end
    source.dungeon, source.creature = key, true
    if source.many then
        source.kind = "trash"
    else
        source.kind = source.rare and "rare" or "boss"
        source.bossName = source.npcName
    end
end

local function addSource(index, entry, provider)
    local record = newRecord(index, entry)
    local source = {}
    for _, field in ipairs(SOURCE_FIELDS) do source[field] = entry[field] end
    source.provider = source.provider or provider
    tieCreature(source, index.placeByArea, index.dungeonByKey)
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

-- AtlasLoot's world epics and QuestieDB's spread-out drops are the same thing: one line, AtlasLoot's section with
-- QuestieDB's creature levels
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
        if not (source.provider == "silverdragon" and source.npcID and creatures[source.npcID]) then kept[#kept + 1] = source end
    end
    if #kept < #record.sources then record.sources = kept end
end

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
            if source.section and not first.section then first.section, first.provider = source.section, source.provider end
            first.levelMin = math.min(first.levelMin or source.levelMin or 99, source.levelMin or first.levelMin or 99)
            if first.levelMin == 99 then first.levelMin = nil end
            first.levelMax = math.max(first.levelMax or 0, source.levelMax or 0)
            if first.levelMax == 0 then first.levelMax = nil end
            first.worldDrop = first.worldDrop or source.worldDrop
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

local function sourceOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    local bossA, bossB = a.bossIndex or 999, b.bossIndex or 999
    if bossA ~= bossB then return bossA < bossB end
    local levelA, levelB = a.reqLevel or a.skill or 0, b.reqLevel or b.skill or 0
    if levelA ~= levelB then return levelA < levelB end
    if (a.kind or "") ~= (b.kind or "") then return (a.kind or "") < (b.kind or "") end
    return (a.questName or a.professionName or a.section or "") < (b.questName or b.professionName or b.section or "")
end

-- extras: entry lists or {entries, dungeons, provider}, their dungeons go after FDJ's
function Index.Build(data, extras, priority)
    local index = {records = {}, byKey = {}, dungeons = {}, dungeonByKey = {}, hasChance = false, placeByArea = {}}
    for _, dungeon in ipairs(data.dungeons or {}) do
        index.dungeons[#index.dungeons + 1] = dungeon
        index.dungeonByKey[dungeon.key] = dungeon
    end
    for key, dungeon in pairs(data.dungeonByKey or {}) do index.dungeonByKey[key] = index.dungeonByKey[key] or dungeon end
    for _, extra in ipairs(extras or {}) do
        for area, key in pairs(extra.areas or {}) do index.placeByArea[area] = index.placeByArea[area] or key end
        for _, dungeon in ipairs(extra.dungeons or {}) do
            if not index.dungeonByKey[dungeon.key] then
                dungeon.order = #index.dungeons + 1
                index.dungeons[#index.dungeons + 1] = dungeon
                index.dungeonByKey[dungeon.key] = dungeon
            end
        end
    end
    for _, entry in ipairs(data.entries or {}) do addSource(index, entry, "fdj") end
    for _, extra in ipairs(extras or {}) do
        for _, entry in ipairs(extra.entries or extra) do
            if entry.id and entry.id > 0 then addSource(index, entry, extra.provider) end
        end
    end
    priority = priority or Index.DEFAULT_PRIORITY
    for _, record in ipairs(index.records) do
        shareChances(record)
        resolveOverlaps(record, priority, index.dungeonByKey)
        mergeWorld(record)
        dropRepeatedRares(record)
        for _, source in ipairs(record.sources) do tieToPlace(source, index.placeByArea, index.dungeonByKey) end
        crossCheckQuests(record)
        if #record.sources > 1 then table.sort(record.sources, sourceOrder) end
        local dungeons = {}
        for _, source in ipairs(record.sources) do if source.dungeon then dungeons[source.dungeon] = true end end
        record.dungeons = dungeons
        record.order = record.sources[1] and record.sources[1].order or 999
    end
    return index
end
