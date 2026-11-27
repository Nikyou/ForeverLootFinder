-- the only file that touches ForeverDungeonJournal (DungeonJournal on CurseForge). read-only, and optional
local _, ns = ...

local DungeonJournal = {}
ns.DungeonJournal = DungeonJournal

local FDJ_ADDON = "ForeverDungeonJournal"

-- anything else shows up in /flf dump fdj. "fdj*" keys are FDJ's runtime caches
local KNOWN = {
    dungeon = {
        "level", "location", "icon", "bosses", "quests", "fullItemsTBD", "description", "entrance", "fullQuestsTBD", "noArrow",
        "parentBoss", "parentDungeon", "questChainPage", "routeGuide",
    },
    boss = {
        "name", "loot", "aliases", "npcID", "description", "trash", "rare", "recipeTab", "trackerHidden", "childOf", "fightGroup",
        "fightSig", "optional", "killWith", "lootChest", "listHidden", "portraitNpcID", "probableLoot", "summonItem",
        "customIcon", "factionOnly", "lootNote", "rareLabel", "chestLabel", "children", "displayID", "killedBefore",
        "runLogHidden", "spawnQuest", "summonChain", "trackerOnlyIfKilled", "questLink", "pairNpcID", "deadWith", "rareSig",
    },
    loot = {"allTrash", "tip", "dropNote", "makes", "sourceTip", "lootFirst"},
}
-- a stand-in for FDJ's "extremely rare" note when it has no number (Spellshock Leggings was 1/440, Bloodletter
-- Scalpel 1/611 in its notes)
DungeonJournal.RARE_DROP_CHANCE = 0.2
-- on the loot row itself, in case FDJ ever puts it there. 2.0.11 had FDJ.DROP_RATES instead, 2.0.12 took it out
-- for now
DungeonJournal.CHANCE_KEYS = {"chance", "dropChance", "dropRate", "rate", "pct"}
local QUEST_REWARD_FIELDS = {"rewardItems", "additionalRewardItems", "noteRewardItems"}

local knownSets = {}
for kind, list in pairs(KNOWN) do
    knownSets[kind] = {}
    for _, key in ipairs(list) do knownSets[kind][key] = true end
end
for _, key in ipairs(DungeonJournal.CHANCE_KEYS) do knownSets.loot[key] = true end

local isSecret = ns.Util.IsSecret

local function namespace()
    local fdj = rawget(_G, "ForeverDungeonJournal_NS")
    if type(fdj) ~= "table" then return nil end
    return fdj
end

-- "ok", "missing" or "invalid"
function DungeonJournal.Status()
    if not ns.Util.AddOnLoaded(FDJ_ADDON) then return "missing" end
    local fdj = namespace()
    if not fdj or type(fdj.DB) ~= "table" or type(fdj.ORDER) ~= "table" then return "invalid" end
    return "ok"
end

function DungeonJournal.Installed() return DungeonJournal.Status() ~= "missing" end
function DungeonJournal.Enabled() return ns.addon.db.profile.fdj ~= false end
function DungeonJournal.Active() return DungeonJournal.Enabled() and DungeonJournal.Status() == "ok" end

function DungeonJournal.Empty()
    return {dungeons = {}, dungeonByKey = {}, entries = {}, skipped = {}, unknown = {}, counts = {}, empty = true}
end

-- AtlasLoot matched its dungeons to FDJ's, so it reads again too
function DungeonJournal.SetEnabled(value)
    ns.addon.db.profile.fdj = value and true or false
    ns.AtlasLootLists.Reread()
    ns.RebuildIndex(true)
end

function DungeonJournal.Version()
    if not (C_AddOns and C_AddOns.GetAddOnMetadata) then return nil end
    local ok, version = pcall(C_AddOns.GetAddOnMetadata, FDJ_ADDON, "Version")
    return ok and type(version) == "string" and version or nil
end

local function levelRange(text)
    if type(text) == "number" then return text, text end
    if type(text) ~= "string" then return nil, nil end
    local low, high = text:match("(%d+)%D+(%d+)")
    if low then return tonumber(low), tonumber(high) end
    local single = tonumber(text:match("%d+"))
    return single, single
end

local function count(map, key) map[key] = (map[key] or 0) + 1 end

-- FDJ.DROP_RATES[dungeon][boss][itemID] = %, from Wowhead Forever's kill counts. only in FDJ 2.0.11, read if it's back
local function chanceOf(entry, rates, base)
    for _, key in ipairs(DungeonJournal.CHANCE_KEYS) do
        local value = entry[key]
        if type(value) == "number" then return value end
    end
    local byBoss = rates and base.dungeon and rates[base.dungeon]
    local items = type(byBoss) == "table" and base.bossName and byBoss[base.bossName]
    local value = type(items) == "table" and items[tonumber(entry[1])]
    return type(value) == "number" and value or nil
end

-- tuple: {itemID, name, slot text, quality, mobs?, "RANDOM_ENCHANT"?, allTrash = true?, tip = {}?}
local function lootEntry(item, base, unknown, rates)
    if type(item) ~= "table" then return nil end
    local entry = {}
    for key, value in pairs(base) do entry[key] = value end
    entry.id = tonumber(item[1]) or 0
    entry.name = type(item[2]) == "string" and item[2] or ""
    entry.slotText = type(item[3]) == "string" and item[3] or nil
    entry.quality = tonumber(item[4])
    if type(item[5]) == "string" and item[5] ~= "" then entry.mobs = item[5] end
    entry.randomBonus = item[6] == "RANDOM_ENCHANT"
    entry.allTrash = item.allTrash == true
    if type(item.tip) == "table" then entry.tip = item.tip end
    entry.chance = chanceOf(item, rates, base)
    if item.dropNote == "EXTREMELY_RARE_DROP" then
        entry.rareDrop = true
        if not entry.chance then entry.chance, entry.chanceGuess = DungeonJournal.RARE_DROP_CHANCE, true end
    end
    if type(item.sourceTip) == "string" and item.sourceTip ~= "" then entry.sourceTip = item.sourceTip end
    for key in pairs(item) do
        if type(key) == "number" then
            if key > 6 then count(unknown, "loot[" .. key .. "]") end
        elseif not knownSets.loot[key] then
            count(unknown, "loot." .. tostring(key))
        end
    end
    if item[6] ~= nil and item[6] ~= "RANDOM_ENCHANT" then count(unknown, "loot[6]=" .. tostring(item[6])) end
    return entry
end

-- makes = {itemID, name, slot text, quality, from = {{itemID, name, boss name}, ...}}: Jang'thraze and Sang'thraze
-- make Sul'thraze, which has no row of its own
local function combineEntry(made, dungeonKey, bossIndex)
    if type(made) ~= "table" or not tonumber(made[1]) then return nil end
    local parts = {}
    for _, part in ipairs(type(made.from) == "table" and made.from or {}) do
        if type(part) == "table" and tonumber(part[1]) then
            parts[#parts + 1] = {
                id = tonumber(part[1]),
                name = type(part[2]) == "string" and part[2] or "?",
                bossName = type(part[3]) == "string" and part[3] or nil,
            }
        end
    end
    return {
        dungeon = dungeonKey,
        bossIndex = bossIndex,
        kind = "combine",
        id = tonumber(made[1]),
        name = type(made[2]) == "string" and made[2] or "",
        slotText = type(made[3]) == "string" and made[3] or nil,
        quality = tonumber(made[4]),
        parts = parts,
    }
end

-- quest reward: {itemID, name, quality, count?}, no slot text
local function rewardEntry(item, base)
    if type(item) ~= "table" then return nil end
    local entry = {}
    for key, value in pairs(base) do entry[key] = value end
    entry.id = tonumber(item[1]) or 0
    entry.name = type(item[2]) == "string" and item[2] or ""
    entry.quality = tonumber(item[3])
    return entry
end

-- FDJ counts PvP ranks 1 to 14, FLF the client's PVP_RANK_ numbers, 5 to 18
local RANK_OFFSET = 4
local SIDES = {"Alliance", "Horde"}

-- {Honor, mark, marks} from t[at] on
local function honorPrice(t, at)
    local price = {}
    local honor, mark, marks = tonumber(t[at]), tonumber(t[at + 1]), tonumber(t[at + 2])
    if honor then price[1] = {honor = honor} end
    if mark and marks then price[#price + 1] = {item = mark, count = marks} end
    return #price > 0 and price or nil
end

-- a battleground faction's English name, from its quartermaster's list
function DungeonJournal.FactionName(factionID)
    local fdj = DungeonJournal.Active() and namespace()
    local rewards = fdj and type(fdj.PVP_REWARDS) == "table" and fdj.PVP_REWARDS or {}
    for _, sides in pairs(rewards) do
        for _, side in ipairs(SIDES) do
            local list = type(sides) == "table" and sides[side]
            if type(list) == "table" and list.faction == factionID and type(list.factionName) == "string" then
                return list.factionName
            end
        end
    end
    return nil
end

-- PVP_REWARDS[battleground][side][standing] (and questRewards): {name, quality, itemID, level, itemID, level, ...}, one
-- item per level bracket. supplies are consumables. PVP_HONOR: the Premier sets (a rare piece, and the epic its seal makes
-- of it at a rank), rank rewards and rank 14 weapons
local function readPvP(fdj, add)
    local rewards = type(fdj.PVP_REWARDS) == "table" and fdj.PVP_REWARDS or {}
    for key, sides in pairs(rewards) do
        for _, side in ipairs(SIDES) do
            local list = type(sides) == "table" and sides[side]
            if type(list) == "table" then
                for _, group in ipairs({1, 2, 3, 4, 5, 6, 7, 8, "questRewards"}) do
                    for _, row in ipairs(type(list[group]) == "table" and list[group] or {}) do
                        for i = 3, type(row) == "table" and #row or 0, 2 do
                            local id, level = tonumber(row[i]), tonumber(row[i + 1])
                            if id then
                                add({
                                    kind = "pvp",
                                    id = id,
                                    name = type(row[1]) == "string" and row[1] or "",
                                    quality = tonumber(row[2]),
                                    pvpKey = key,
                                    faction = side,
                                    factionID = tonumber(list.faction),
                                    factionName = type(list.factionName) == "string" and list.factionName or nil,
                                    standing = type(group) == "number" and group or nil,
                                    fromQuest = group == "questRewards" or nil,
                                    reqLevel = level and level > 1 and level or nil,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    local honor = type(fdj.PVP_HONOR) == "table" and fdj.PVP_HONOR or {}
    local names = type(fdj.PVP_ITEM_NAMES) == "table" and fdj.PVP_ITEM_NAMES or {}
    local slotCost = type(honor.slotCost) == "table" and honor.slotCost or {}
    local seals = type(honor.seals) == "table" and honor.seals or {}
    local function addHonor(id, side, rank, price)
        if not id then return end
        add({
            kind = "pvp",
            id = id,
            name = type(names[id]) == "string" and names[id] or "",
            pvpKey = "honor",
            faction = side,
            pvpRank = rank and rank + RANK_OFFSET or nil,
            price = price,
        })
    end
    local function sideList(field, side)
        local t = type(honor[field]) == "table" and honor[field][side]
        return type(t) == "table" and t or {}
    end
    for _, side in ipairs(SIDES) do
        for _, sets in pairs(sideList("sets", side)) do
            for _, set in ipairs(type(sets) == "table" and sets or {}) do
                for i = 2, type(set) == "table" and #set or 0 do
                    local piece = type(set[i]) == "table" and set[i] or {}
                    local rare, epic = tonumber(piece[2]), tonumber(piece[3])
                    addHonor(rare, side, nil, type(slotCost[piece[1]]) == "table" and honorPrice(slotCost[piece[1]], 1) or nil)
                    local seal = type(seals[piece[1]]) == "table" and seals[piece[1]] or {}
                    local price = {}
                    if tonumber(seal[3]) then price[1] = {honor = tonumber(seal[3])} end
                    if tonumber(seal[1]) then price[#price + 1] = {item = tonumber(seal[1]), count = 1} end
                    if rare then price[#price + 1] = {item = rare, count = 1} end
                    addHonor(epic, side, tonumber(seal[2]), #price > 0 and price or nil)
                end
            end
        end
        for rank, list in pairs(sideList("ranks", side)) do
            for _, row in ipairs(type(list) == "table" and list or {}) do
                if type(row) == "table" then addHonor(tonumber(row[1]), side, tonumber(rank), honorPrice(row, 2)) end
            end
        end
        for _, row in ipairs(sideList("weapons", side)) do
            if type(row) == "table" then addHonor(tonumber(row[1]), side, 14, honorPrice(row, 2)) end
        end
    end
end

local function unknownKeys(tbl, kind, unknown)
    for key in pairs(tbl) do
        if type(key) == "string" and not knownSets[kind][key] and not key:match("^fdj") then
            count(unknown, kind .. "." .. key)
        end
    end
end

-- one entry per item and source, Index merges them
function DungeonJournal.ReadData(fdj)
    local data = {dungeons = {}, dungeonByKey = {}, entries = {}, skipped = {}, unknown = {}, counts = {}}
    if type(fdj) ~= "table" or type(fdj.DB) ~= "table" or type(fdj.ORDER) ~= "table" then
        data.error = "invalid"
        return data
    end
    local counts, unknown = data.counts, data.unknown
    local function skip(dungeon, boss, reason, rows)
        data.skipped[#data.skipped + 1] = {dungeon = dungeon, boss = boss, reason = reason, rows = rows or 0}
    end
    local function add(entry)
        if entry then
            data.entries[#data.entries + 1] = entry
            count(counts, entry.kind)
            if entry.id == 0 then count(counts, "idZero") end
        end
    end
    local shared = type(fdj.SHARED_BY_BOSS) == "table" and fdj.SHARED_BY_BOSS or {}
    local rates = type(fdj.DROP_RATES) == "table" and fdj.DROP_RATES or nil

    for order, key in ipairs(fdj.ORDER) do
        local dungeon = type(key) == "string" and fdj.DB[key]
        if type(dungeon) ~= "table" then
            skip(tostring(key), nil, "not in the database")
        else
            unknownKeys(dungeon, "dungeon", unknown)
            local low, high = levelRange(dungeon.level)
            local record = {
                key = key,
                order = order,
                levelText = type(dungeon.level) == "string" and dungeon.level or nil,
                levelMin = low,
                levelMax = high,
                location = type(dungeon.location) == "string" and dungeon.location or nil,
                icon = dungeon.icon,
                incomplete = dungeon.fullItemsTBD == true,
                bosses = {},
            }
            -- from FDJ's DungeonEntrances.lua
            local entrance = type(dungeon.entrance) == "table" and dungeon.entrance or {}
            if type(entrance.mapID) == "number" and type(entrance.x) == "number" and type(entrance.y) == "number" then
                record.entrance = {mapID = entrance.mapID, x = entrance.x, y = entrance.y}
            end
            data.dungeons[#data.dungeons + 1] = record
            data.dungeonByKey[key] = record
            local bossByName = {}
            -- both halves carry it, one entry is enough
            local combined = {}
            for bossIndex, boss in ipairs(type(dungeon.bosses) == "table" and dungeon.bosses or {}) do
                if type(boss) == "table" then
                    unknownKeys(boss, "boss", unknown)
                    local lootCount = type(boss.loot) == "table" and #boss.loot or 0
                    if boss.recipeTab then
                        skip(key, boss.name, "recipe tab, repeats other bosses", lootCount)
                    elseif boss.childOf then
                        skip(key, boss.name, "copy of its boss group", lootCount)
                    else
                        local kind = boss.rare and "rare" or ((boss.trash or boss.lootChest) and "trash" or "boss")
                        local faction =
                          (boss.factionOnly == "Horde" or boss.factionOnly == "Alliance") and boss.factionOnly or nil
                        local bossRecord = {
                            index = bossIndex,
                            name = type(boss.name) == "string" and boss.name or "?",
                            npcID = tonumber(boss.npcID),
                            kind = kind,
                            faction = faction,
                            lootNote = type(boss.lootNote) == "string" and boss.lootNote or nil,
                        }
                        record.bosses[#record.bosses + 1] = bossRecord
                        bossByName[bossRecord.name] = bossRecord
                        local base = {
                            dungeon = key,
                            bossIndex = bossIndex,
                            bossName = bossRecord.name,
                            kind = kind,
                            faction = faction,
                        }
                        for _, item in ipairs(type(boss.loot) == "table" and boss.loot or {}) do
                            add(lootEntry(item, base, unknown, rates))
                            local made = type(item) == "table" and type(item.makes) == "table" and tonumber(item.makes[1])
                            if made and not combined[made] then
                                combined[made] = true
                                add(combineEntry(item.makes, key, bossIndex))
                            end
                        end
                        local probableBase = {
                            dungeon = key,
                            bossIndex = bossIndex,
                            bossName = bossRecord.name,
                            kind = "probable",
                            faction = faction,
                        }
                        for _, item in ipairs(type(boss.probableLoot) == "table" and boss.probableLoot or {}) do
                            add(lootEntry(item, probableBase, unknown, rates))
                        end
                    end
                end
            end
            -- shared drops were moved out of the bosses' own lists
            local sharedHere = type(shared[key]) == "table" and shared[key] or {}
            for bossName, list in pairs(sharedHere) do
                local boss = bossByName[bossName]
                if not boss then
                    skip(key, tostring(bossName), "shared loot of a boss FLF doesn't list", type(list) == "table" and #list or 0)
                elseif type(list) == "table" then
                    local base = {
                        dungeon = key,
                        bossIndex = boss.index,
                        bossName = boss.name,
                        kind = "shared",
                        faction = boss.faction,
                    }
                    for _, item in ipairs(list) do add(lootEntry(item, base, unknown, rates)) end
                end
            end
            for _, quest in ipairs(type(dungeon.quests) == "table" and dungeon.quests or {}) do
                if type(quest) == "table" then
                    local faction = (quest.faction == "Horde" or quest.faction == "Alliance") and quest.faction or nil
                    local base = {
                        dungeon = key,
                        kind = "quest",
                        faction = faction,
                        questName = type(quest.name) == "string" and quest.name or "?",
                        questID = tonumber(quest.id),
                        questLevel = tonumber(quest.level),
                        reqLevel = tonumber(quest.requires),
                        classOnly = type(quest.classOnly) == "string" and quest.classOnly:upper() or nil,
                    }
                    for _, field in ipairs(QUEST_REWARD_FIELDS) do
                        for _, item in ipairs(type(quest[field]) == "table" and quest[field] or {}) do
                            add(rewardEntry(item, base))
                        end
                    end
                end
            end
        end
    end
    readPvP(fdj, add)
    return data
end

function DungeonJournal.Read()
    local fdj = namespace()
    local ok, data = pcall(DungeonJournal.ReadData, fdj)
    if not ok then
        return {dungeons = {}, dungeonByKey = {}, entries = {}, skipped = {}, unknown = {}, counts = {}, error = data}
    end
    return data
end

local function call(name, ...)
    local fdj = namespace()
    local fn = fdj and fdj[name]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if not ok or isSecret(result) then return nil end
    return result
end

-- looked up every call, FDJ re-wraps its localizers while it loads
function DungeonJournal.DungeonName(key)
    if type(key) == "string" and key:sub(1, 3) == "al:" then return ns.AtlasLootLists and ns.AtlasLootLists.Name(key) or key end
    if type(key) == "string" and key:sub(1, 4) == "att:" then return ns.ATT and ns.ATT.Name(key) or key end
    local name = call("LocalizeDungeonName", key)
    return type(name) == "string" and name ~= "" and name or key
end

-- a PvP line's pvpKey: FDJ's battleground keys (WSG, AB, AV, DI) and "honor". nil when FDJ can't name it
function DungeonJournal.BattlegroundName(key)
    if key == nil then return nil end
    if key == "honor" then return ns.L["Honor & Ranks"] end
    local name = call("PvPBattlegroundName", key)
    return type(name) == "string" and name ~= "" and name ~= key and name or nil
end

function DungeonJournal.BossName(name)
    local localized = call("LocalizeBossName", name)
    return type(localized) == "string" and localized ~= "" and localized or name
end

function DungeonJournal.SlotName(text)
    local localized = call("LocalizeItemSlot", text)
    return type(localized) == "string" and localized ~= "" and localized or text
end

-- boss notes are FDJ locale keys
function DungeonJournal.Note(key)
    local text = call("L", key)
    if type(text) ~= "string" or text == "" then return nil end
    return text
end

function DungeonJournal.CanOpenItem()
    local fdj = namespace()
    return fdj ~= nil and type(fdj.OpenItemSource) == "function"
end

function DungeonJournal.CanOpenDungeon()
    local fdj = namespace()
    return fdj ~= nil and type(fdj.OpenBossPage) == "function" and type(fdj.ToggleJournal) == "function"
end

-- OpenBossPage only fills the journal, it doesn't show it
function DungeonJournal.OpenDungeon(key, bossIndex)
    if not DungeonJournal.CanOpenDungeon() then return false end
    local fdj = namespace()
    local frame = rawget(_G, "ForeverDungeonJournalFrame")
    local shown = type(frame) == "table" and frame.IsShown and frame:IsShown()
    if not shown then pcall(fdj.ToggleJournal) end
    return (pcall(fdj.OpenBossPage, key, bossIndex or 1))
end

function DungeonJournal.OpenItem(itemID)
    if not DungeonJournal.CanOpenItem() then return false end
    local ok, result = pcall(namespace().OpenItemSource, itemID)
    return ok and result ~= false
end

-- FDJ.ITEM_SETS: every set with a piece in the journal, Forever's own too. not FDJ.ItemSetOf, which also gives boxes
local setOf
function DungeonJournal.SetPieces(itemID)
    if not DungeonJournal.Active() then return nil end
    if not setOf then
        local fdj = namespace()
        local sets = fdj and fdj.ITEM_SETS
        if type(sets) ~= "table" then return nil end
        setOf = {}
        for _, set in ipairs(sets) do
            if type(set) == "table" then
                for _, id in ipairs(set) do if type(id) == "number" then setOf[id] = set end end
            end
        end
    end
    return setOf[itemID]
end

-- read every time, the player can toggle it any moment
function DungeonJournal.ItemSourceLineOn()
    if DungeonJournal.Status() ~= "ok" then return false end
    local saved = rawget(_G, "ForeverDungeonJournalDB")
    if type(saved) ~= "table" then return true end
    return saved.itemSourceStrip ~= false
end

function DungeonJournal.FavouriteItems()
    local saved = DungeonJournal.Installed() and rawget(_G, "ForeverDungeonJournalCharacterDB")
    local list = {}
    if type(saved) ~= "table" or type(saved.favouriteItems) ~= "table" then return list end
    for key, entry in pairs(saved.favouriteItems) do
        if type(entry) == "table" then
            list[#list + 1] = {
                id = tonumber(entry.id) or tonumber(key) or 0,
                name = type(entry.name) == "string" and entry.name or tostring(key),
                quality = tonumber(entry.quality),
                dungeon = type(entry.dungeon) == "string" and entry.dungeon or nil,
            }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function sameName(a, b)
    local function clean(text) return (text:lower():gsub("\226\128\153", "'"):gsub("^the%s+", "")) end
    return clean(a) == clean(b)
end

-- not FDJ's CurrentDungeon: it guesses one Scarlet wing, the reminder wants them all
function DungeonJournal.MatchInstance(instanceID, instanceName, mapID)
    local fdj = namespace()
    if not fdj or type(fdj.ORDER) ~= "table" then return nil end
    local inOrder = {}
    for _, key in ipairs(fdj.ORDER) do inOrder[key] = true end
    if type(instanceName) ~= "string" or isSecret(instanceName) then instanceName = nil end

    local wings = type(fdj.RunLogWingGroups) == "table" and instanceID and fdj.RunLogWingGroups[instanceID]
    if type(wings) == "table" then
        local byMap = type(fdj.SCARLET_WING_MAPS) == "table" and mapID and fdj.SCARLET_WING_MAPS[mapID]
        if byMap and inOrder[byMap] then return {byMap}, false end
        local list = {}
        for _, wing in ipairs(wings) do if inOrder[wing] then list[#list + 1] = wing end end
        if #list > 0 then return list, #list > 1 end
    end
    local byID = type(fdj.INSTANCE_ID_TO_DUNGEON) == "table" and instanceID and fdj.INSTANCE_ID_TO_DUNGEON[instanceID]
    if byID and inOrder[byID] then return {byID}, false end
    if instanceName then
        local key = call("DungeonFromInstanceName", instanceName)
        if key and inOrder[key] then return {key}, false end
        for _, candidate in ipairs(fdj.ORDER) do
            if sameName(DungeonJournal.DungeonName(candidate), instanceName) or sameName(candidate, instanceName) then
                return {candidate}, false
            end
        end
    end
    return nil
end
