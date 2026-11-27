-- ForeverDB (forever-db on CurseForge). read-only. its copy of QuestieDB loses to QuestieDB itself, that one is updated
-- sooner. it's load-on-demand, so it's loaded here when switched on
local _, ns = ...

local ForeverDB = {}
ns.ForeverDB = ForeverDB

local Util = ns.Util
local ADDON, LOCALES = "ForeverDB", "ForeverDB_Locales"
local MAX_EACH = 5 -- more than this make one "many" source, as with QuestieDB
local MANY_SAMPLE, MANY_NPCS, MANY_ZONES = 40, 5, 4
local WORLD_ZONES = 4
-- recipes past this are from a later expansion, the client still has them
local MAX_SKILL = 300
-- Forever's own spells and items start here, a name shared with a classic item goes by it
local FOREVER_SPELL_FIRST, FOREVER_ITEM_FIRST = 1000000, 245000
local RECIPE_CLASS, LEARN_TRIGGER = 9, 6
-- Season of Discovery's creatures, quests and items are still in the data, the same rules as for QuestieDB's
local SOD_NPC_FIRST, SOD_NPC_LAST = 200000, 244999
local SOD_QUEST_FIRST, FOREVER_QUEST_FIRST = 70000, 90000
local SOD_ITEM_FIRST, SOD_ITEM_LAST = 190000, 244999
local DUNGEON_MAP = 4
local CONTINENTS = {[0] = true, [1] = true} -- Eastern Kingdoms and Kalimdor, every other spawn map is an instance
local RARE_RANKS = {[2] = true, [4] = true}
local FACTIONS = {A = "Alliance", H = "Horde"}
local ENGLISH = {enUS = true, enGB = true}

local status = Util.NewStatus("foreverdb", {
    items = 0,
    quests = 0,
    vendors = 0,
    drops = 0,
    chances = 0,
    world = 0,
    crafts = 0,
    trainer = 0,
    implausible = 0,
    sod = 0,
    pruned = 0,
    ms = 0,
})
local stats = status.counts
local EMPTY = {provider = "foreverdb", entries = {}, areas = {}, instances = {}}
local extra = EMPTY
local recipeItems, recipeOf = {}, {} -- [recipe item] = where it comes from, [spell] = the recipe item that teaches it
local learnedFor -- ATT's state the skill levels came from
local prunedFor -- QuestieDB's list the copies were dropped for, false when there was none

local function data()
    local db = rawget(_G, "ForeverDB")
    if type(db) ~= "table" or type(db.item) ~= "table" or type(db.drop) ~= "table" then return nil end
    return db
end

local function exists(name)
    if not C_AddOns then return false end
    if Util.AddOnLoaded(name) then return true end
    -- switched off in the addon list counts as not there
    local found, _, _, _, reason = Util.SafeCall(C_AddOns.GetAddOnInfo, name)
    return found ~= nil and reason ~= "MISSING" and reason ~= "DISABLED"
end

function ForeverDB.Installed() return data() ~= nil or exists(ADDON) end
function ForeverDB.Enabled() return ns.addon.db.profile.foreverdb ~= false end
function ForeverDB.State() return status.state end
function ForeverDB.Status() return status end
function ForeverDB.Stats() return stats end
function ForeverDB.Entries() return ForeverDB.Enabled() and extra or EMPTY end
function ForeverDB.RecipeItem(spell) return ForeverDB.Enabled() and spell and recipeOf[spell] or nil end
function ForeverDB.RecipeSources(item) return ForeverDB.Enabled() and item and recipeItems[item] or nil end

local function list(value)
    if type(value) == "table" then return value end
    return {}
end

local function npcEntries(out, id, kind, npcIDs, chances, npcOf, zoneName)
    if #npcIDs == 0 then return 0 end
    if #npcIDs <= MAX_EACH then
        for _, npcID in ipairs(npcIDs) do
            local info = npcOf(npcID)
            local entry = {
                id = id,
                kind = kind,
                npcID = npcID,
                npcName = info.name,
                npcs = {npcID},
                zone = info.zone,
                zoneKey = info.zone,
                zoneName = info.zone and zoneName(info.zone),
                instance = info.instance,
            }
            if kind == "vendor" then
                entry.faction, entry.npcLevel = info.faction, info.maxLevel
            else
                entry.levelMin, entry.levelMax, entry.rare = info.minLevel, info.maxLevel, info.rare or nil
                entry.chance = chances and chances[npcID]
            end
            out[#out + 1] = entry
        end
        return #npcIDs
    end
    local entry = {id = id, kind = kind, many = true, count = #npcIDs, npcs = {}, zones = {}}
    local zoneSet, zoneCount, names = {}, 0, {}
    local instance
    for i = 1, math.min(#npcIDs, MANY_SAMPLE) do
        local info = npcOf(npcIDs[i])
        -- the one instance those with one spawn in, Index weighs the rest by their zones
        if info.instance and instance == nil then
            instance = info.instance
        elseif info.instance and info.instance ~= instance then
            instance = false
        end
        if #entry.npcs < MANY_NPCS then entry.npcs[#entry.npcs + 1] = npcIDs[i] end
        if #names < 3 then names[#names + 1] = info.name end
        if info.minLevel and (not entry.levelMin or info.minLevel < entry.levelMin) then entry.levelMin = info.minLevel end
        if info.maxLevel and (not entry.levelMax or info.maxLevel > entry.levelMax) then entry.levelMax = info.maxLevel end
        if info.zone and not zoneSet[info.zone] then
            zoneSet[info.zone] = true
            zoneCount = zoneCount + 1
            local name = zoneName(info.zone)
            if name and #entry.zones < MANY_ZONES then entry.zones[#entry.zones + 1] = name end
        end
    end
    if kind == "npcDrop" and zoneCount >= WORLD_ZONES then
        out[#out + 1] = {id = id, kind = "world", worldDrop = true, levelMin = entry.levelMin, levelMax = entry.levelMax}
        return 1
    end
    entry.moreZones = zoneCount > #entry.zones or nil
    if zoneCount == 1 then
        local zone = next(zoneSet)
        entry.zone, entry.zoneKey, entry.zoneName = zone, zone, zoneName(zone)
    end
    if instance then entry.instance = instance end
    entry.mobs = table.concat(names, ", ") .. (#npcIDs > #names and ", ..." or "")
    out[#out + 1] = entry
    return 1
end

-- "Pattern: Black Whelp Tunic" makes Black Whelp Tunic
local function madeName(recipeName)
    if type(recipeName) ~= "string" then return nil end
    local name = recipeName:match("^[^:]+:%s*(.+)$")
    return name and name:lower() or nil
end

-- a name two items share: the one from the same era as the spell, then the lowest ID
local function pick(ids, spell)
    if not ids then return nil end
    if #ids == 1 then return ids[1] end
    local forever = spell >= FOREVER_SPELL_FIRST
    local best
    for _, id in ipairs(ids) do if (id >= FOREVER_ITEM_FIRST) == forever and (not best or id < best) then best = id end end
    if best then return best end
    for _, id in ipairs(ids) do if not best or id < best then best = id end end
    return best
end

-- pure, for tests: opt holds the client and FDJ lookups. localItems is nil on an English client
function ForeverDB.Read(D, opt)
    local out, counts = {}, {
        items = 0,
        quests = 0,
        vendors = 0,
        drops = 0,
        chances = 0,
        world = 0,
        crafts = 0,
        trainer = 0,
        implausible = 0,
        sod = 0,
    }
    local checkpoint = opt.checkpoint or function() end
    local areas, instances = {}, {}
    local mapDungeon = {}
    local function zoneOfMap(map)
        if mapDungeon[map] == nil then
            local info = D.umap and D.umap[map]
            local key = false
            if type(info) == "table" and info[3] == DUNGEON_MAP then
                key = opt.dungeonOf(opt.mapName(map) or info[1]) or (info[1] and opt.dungeonOf(info[1])) or false
                if key then areas["m" .. map] = key end
            end
            mapDungeon[map] = key
        end
        return "m" .. map
    end
    local function zoneName(zone)
        local map = tonumber(zone:match("^m(%d+)$"))
        if map then
            local info = D.umap and D.umap[map]
            return opt.mapName(map) or (type(info) == "table" and info[1]) or nil
        end
        return opt.zoneName(tonumber(zone:match("^zone:(%d+)$")))
    end

    -- spw has the instance map of a dungeon creature's spawn. spm often has none for it, or the zone outside
    local function instanceOf(id)
        for _, spawn in ipairs(list(D.spw and D.spw["c" .. id])) do
            local map = type(spawn) == "table" and tonumber(spawn[1])
            if map and not CONTINENTS[map] then
                if instances[map] == nil then
                    local keys = opt.instancePlaces and opt.instancePlaces(map)
                    instances[map] = type(keys) == "table" and keys[1] and keys or false
                end
                return map
            end
        end
        return nil
    end

    local npcCache = {}
    local function npcOf(id)
        local info = npcCache[id]
        if info then return info end
        local row = D.npc[id]
        row = type(row) == "table" and row or {}
        local low, high = tonumber(row[3]), tonumber(row[4])
        local map
        for key in pairs(list(D.spm and D.spm["c" .. id])) do
            if type(key) == "number" and (not map or key < map) then map = key end
        end
        local side = D.nfac and D.nfac[id]
        info = {
            name = opt.npcName(id) or row[1] or ("#" .. id),
            minLevel = low and low > 0 and low or nil,
            maxLevel = high and high > 0 and high or nil,
            rare = RARE_RANKS[row[5]] == true,
            faction = FACTIONS[side],
            zone = map and zoneOfMap(map) or nil,
            instance = instanceOf(id),
        }
        npcCache[id] = info
        return info
    end

    local questCache = {}
    local function questOf(id)
        local info = questCache[id]
        if info ~= nil then return info or nil end
        local row = D.quest[id]
        if type(row) ~= "table" then
            questCache[id] = false
            return nil
        end
        local extraRow = list(D.qx and D.qx[id])
        local races, classes, zone = tonumber(extraRow[1]), tonumber(extraRow[2]), tonumber(extraRow[11])
        zone = zone and zone > 0 and zone or nil
        info = {
            questID = id,
            questName = opt.questName(id) or row[1],
            questLevel = tonumber(row[2]) and row[2] > 0 and row[2] or nil,
            reqLevel = tonumber(row[3]) and row[3] > 0 and row[3] or nil,
            raceMask = races and races > 0 and races or nil,
            classMask = classes and classes > 0 and classes or nil,
            zoneKey = zone and ("zone:" .. zone) or "zone:other",
            zoneName = zone and opt.zoneName(zone) or nil,
        }
        questCache[id] = info
        return info
    end

    local foreverNpcs = {}
    for _, field in ipairs({"qg", "qe"}) do
        for questID, givers in pairs(D[field] or {}) do
            if type(questID) == "number" and questID >= FOREVER_QUEST_FIRST then
                for _, giver in ipairs(list(givers)) do
                    local npc = type(giver) == "string" and tonumber(giver:match("^c(%d+)$"))
                    if npc then foreverNpcs[npc] = true end
                end
            end
        end
    end
    -- an item from SoD's range only counts from a creature a Forever quest uses
    local function keepNpc(npcID, sodItem)
        if foreverNpcs[npcID] or (not sodItem and (npcID < SOD_NPC_FIRST or npcID > SOD_NPC_LAST)) then return true end
        counts.sod = counts.sod + 1
        return false
    end

    local byName = {} -- English, lowercased: gear only
    local gear = {}
    local recipes = {} -- [spell] = recipe item
    for id, row in pairs(D.item) do
        if type(id) == "number" and type(row) == "table" then
            if row[5] == RECIPE_CLASS then
                for _, effect in ipairs(list(D.ieff and D.ieff[id])) do
                    if type(effect) == "table" and effect[2] == LEARN_TRIGGER and type(effect[1]) == "number" then
                        recipes[effect[1]] = recipes[effect[1]] or id
                    end
                end
            elseif opt.equippable(id) and not (opt.testItem and opt.testItem(row[1])) then
                counts.items = counts.items + 1
                gear[id] = true
                if type(row[1]) == "string" then
                    local key = row[1]:lower()
                    byName[key] = byName[key] or {}
                    table.insert(byName[key], id)
                end
                local sodItem = id >= SOD_ITEM_FIRST and id <= SOD_ITEM_LAST
                for _, questID in ipairs(list(D.rew[id])) do
                    local sodQuest = type(questID) == "number" and questID >= SOD_QUEST_FIRST and questID < FOREVER_QUEST_FIRST
                    if sodItem and sodQuest then counts.sod = counts.sod + 1 end
                    local quest = type(questID) == "number" and not (sodItem and sodQuest) and questOf(questID)
                    if quest then
                        local entry = {id = id, kind = "zoneQuest"}
                        for key, value in pairs(quest) do entry[key] = value end
                        out[#out + 1] = entry
                        counts.quests = counts.quests + 1
                    end
                end
                local vendors = {}
                for _, npcID in ipairs(list(D.vend[id])) do
                    if type(npcID) == "number" and keepNpc(npcID, sodItem) then vendors[#vendors + 1] = npcID end
                end
                counts.vendors = counts.vendors + npcEntries(out, id, "vendor", vendors, nil, npcOf, zoneName)
                local drops, chances = {}, {}
                local dropRow = list(D.drop[id])
                for i = 1, #dropRow - 1, 2 do
                    local npcID, rate = dropRow[i], dropRow[i + 1]
                    if type(npcID) == "number" and keepNpc(npcID, sodItem) then
                        if opt.implausible and opt.implausible(npcOf(npcID), row[3], row[4]) then
                            counts.implausible = counts.implausible + 1
                        else
                            drops[#drops + 1] = npcID
                            -- hundredths of a percent, 0 when unknown
                            if type(rate) == "number" and rate > 0 then
                                chances[npcID] = rate / 100
                                counts.chances = counts.chances + 1
                            end
                        end
                    end
                end
                counts.drops = counts.drops + npcEntries(out, id, "npcDrop", drops, chances, npcOf, zoneName)
                local level = D.world and D.world[id]
                if type(level) == "number" then
                    out[#out + 1] = {id = id, kind = "world", worldDrop = true, levelMin = level > 0 and level or nil}
                    counts.world = counts.world + 1
                end
            end
        end
        checkpoint()
    end

    local function craft(spell, id, recipe)
        local skillRow = list(list(D.sla[spell])[1])
        out[#out + 1] = {
            id = id,
            kind = "craft",
            profession = skillRow[1],
            skill = tonumber(skillRow[3]),
            spell = spell,
            recipe = recipe,
        }
        counts.crafts = counts.crafts + 1
    end
    local function craftable(spell)
        local skillRow = list(list(D.sla and D.sla[spell])[1])
        local skill = tonumber(skillRow[3])
        return opt.professions[skillRow[1]] and (not skill or skill <= MAX_SKILL)
    end
    -- a dungeon creature's map is often the zone outside, or none
    local function placeOf(info)
        return info.instance and opt.instanceName and opt.instanceName(info.instance) or info.zone and zoneName(info.zone)
    end

    -- a recipe item's vendors, quests and likeliest droppers, with the side or races each is for
    local function recipeFrom(item)
        local sodItem = item >= SOD_ITEM_FIRST and item <= SOD_ITEM_LAST
        local found, sold = {vendors = {}, quests = {}, drops = {}}, {}
        for _, npcID in ipairs(list(D.vend[item])) do
            if type(npcID) == "number" and keepNpc(npcID, sodItem) then
                local info = npcOf(npcID)
                sold[npcID] = true
                found.vendors[#found.vendors + 1] = {name = info.name, zone = placeOf(info), faction = info.faction}
            end
        end
        for _, questID in ipairs(list(D.rew[item])) do
            local sodQuest = type(questID) == "number" and questID >= SOD_QUEST_FIRST and questID < FOREVER_QUEST_FIRST
            local quest = type(questID) == "number" and not (sodItem and sodQuest) and questOf(questID)
            if quest then
                found.quests[#found.quests + 1] = {
                    questID = questID,
                    title = quest.questName,
                    raceMask = quest.raceMask,
                    classMask = quest.classMask,
                }
            end
        end
        local dropRow = list(D.drop[item])
        for i = 1, #dropRow - 1, 2 do
            local npcID, rate = dropRow[i], dropRow[i + 1]
            -- its vendors are among the droppers too, with no chance
            if type(npcID) == "number" and not sold[npcID] and keepNpc(npcID, sodItem) then
                local info = npcOf(npcID)
                found.drops[#found.drops + 1] = {
                    name = info.name,
                    zone = placeOf(info),
                    chance = type(rate) == "number" and rate > 0 and rate / 100 or nil,
                }
            end
        end
        table.sort(found.drops, function(a, b) return (a.chance or 0) > (b.chance or 0) end)
        for i = #found.drops, MAX_EACH + 1, -1 do found.drops[i] = nil end
        found.world = type(D.world and D.world[item]) == "number" or nil
        if #found.vendors + #found.quests + #found.drops == 0 and not found.world then return nil end
        return found
    end

    local made = {}
    for spell, recipe in pairs(recipes) do
        local recipeRow = D.item[recipe]
        local id = craftable(spell) and pick(byName[madeName(recipeRow and recipeRow[1])], spell)
        if id then
            made[spell] = true
            craft(spell, id, recipe)
        end
        checkpoint()
    end
    local byItem, bySpell = {}, {}
    for spell in pairs(made) do
        local item = recipes[spell]
        bySpell[spell] = item
        if byItem[item] == nil then byItem[item] = recipeFrom(item) or false end
        checkpoint()
    end
    -- trainers teach the rest: the spell has the item's name, in the client's language. the locale lists every item,
    -- potions and leather too, so only the gear byName has
    local names = byName
    if opt.localItems then
        names = {}
        for id, name in pairs(opt.localItems) do
            if gear[id] and type(name) == "string" then
                local key = (opt.lower or string.lower)(name)
                names[key] = names[key] or {}
                table.insert(names[key], id)
            end
        end
    end
    gear = nil
    if opt.spellName then
        for spell in pairs(D.sla or {}) do
            if type(spell) == "number" and not made[spell] and craftable(spell) then
                local name = opt.spellName(spell)
                local id = name and pick(names[(opt.lower or string.lower)(name)], spell)
                if id then
                    craft(spell, id, nil)
                    counts.trainer = counts.trainer + 1
                end
            end
            checkpoint()
        end
    end
    for map, keys in pairs(instances) do if not keys then instances[map] = nil end end
    return out, counts, areas, instances, byItem, bySpell
end

-- the client's language, from ForeverDB_Locales when it's loaded
local function localeTable()
    if ENGLISH[GetLocale()] then return nil end
    local locales = rawget(_G, "ForeverDBLocale")
    local loc = type(locales) == "table" and type(locales.loc) == "table" and locales.loc[GetLocale()]
    return type(loc) == "table" and loc or nil
end

-- the client names only the factions the character can meet, not the other side's battleground one
function ForeverDB.FactionName(id)
    local loc = ForeverDB.Enabled() and localeTable()
    local name = loc and type(loc.faction) == "table" and loc.faction[id]
    return type(name) == "string" and name or nil
end

local zoneNames = {}
local function zoneName(zone)
    if not zone then return nil end
    if zoneNames[zone] == nil then
        local name = C_Map and Util.SafeCall(C_Map.GetAreaInfo, zone)
        zoneNames[zone] = type(name) == "string" and not Util.IsSecret(name) and name ~= "" and name or false
    end
    return zoneNames[zone] or nil
end

local function mapName(map)
    local info = C_Map and C_Map.GetMapInfo and Util.SafeCall(C_Map.GetMapInfo, map)
    local name = type(info) == "table" and info.name
    return type(name) == "string" and not Util.IsSecret(name) and name ~= "" and name or nil
end

local function realZoneText(map)
    local get = rawget(_G, "GetRealZoneText")
    local name = type(get) == "function" and Util.SafeCall(get, map)
    if type(name) ~= "string" or Util.IsSecret(name) or name == "" then return nil end
    return name
end

-- FDJ knows its dungeons' instance IDs and the wings that share one. the client's name ("Deadmines") for the rest
local function instancePlaces(map)
    local keys = Util.SafeCall(ns.DungeonJournal.MatchInstance, map, realZoneText(map))
    return type(keys) == "table" and keys or nil
end

-- wings share one instance: the whole dungeon's name, as the client gives it
local function instanceName(map)
    local keys = instancePlaces(map)
    if keys and #keys == 1 then return ns.DungeonJournal.DungeonName(keys[1]) or realZoneText(map) end
    return realZoneText(map)
end

local function dungeonOf(name)
    local found = name and ns.DungeonJournal.MatchInstance(nil, name)
    return found and found[1] or nil
end

local function spellName(spell)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = Util.SafeCall(C_Spell.GetSpellName, spell)
    else
        name = Util.SafeCall(rawget(_G, "GetSpellInfo"), spell)
    end
    return type(name) == "string" and not Util.IsSecret(name) and name ~= "" and name or nil
end

local professions = {}
for id in pairs(ns.Crafts.BY_ID) do professions[id] = true end

local function read()
    local db = data()
    if not db then
        status.state = "nodata"
        return
    end
    status.state, status.error = "scanning", nil
    local loc = localeTable()
    local found, counts, areas, instances, items, spells
    Util.RunSliced(function(checkpoint)
        found, counts, areas, instances, items, spells = ForeverDB.Read(db, {
            equippable = Util.Equippable,
            npcName = function(id) return loc and type(loc.npc) == "table" and loc.npc[id] or nil end,
            questName = function(id) return loc and type(loc.quest) == "table" and loc.quest[id] or nil end,
            zoneName = zoneName,
            mapName = mapName,
            instancePlaces = instancePlaces,
            instanceName = instanceName,
            dungeonOf = dungeonOf,
            spellName = (ENGLISH[GetLocale()] or loc) and spellName or nil,
            localItems = loc and type(loc.item) == "table" and loc.item or nil,
            lower = Util.Lower,
            professions = professions,
            testItem = ns.Index.TestItem,
            implausible = ns.Questie.ImplausibleDrop,
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
            stats.pruned, prunedFor = 0, nil
            for _, entry in ipairs(found) do
                if entry.profession then entry.professionName = ns.Crafts.Name(entry.profession) end
            end
            extra = {provider = "foreverdb", entries = found, areas = areas, instances = instances}
            recipeItems, recipeOf = items or {}, spells or {}
            learnedFor = nil
        end
        status.state = found and #found > 0 and "done" or "nodata"
        ns.RebuildIndex()
    end)
end

-- its copy of QuestieDB would lose every overlap to QuestieDB itself, so those entries go once QuestieDB's are in. a
-- creature drop with a chance stays: QuestieDB's entry takes the chance from it
local load
local function key(entry)
    if entry.kind == "zoneQuest" then return entry.questID and (entry.id .. "q" .. entry.questID) end
    if entry.kind == "vendor" or entry.kind == "npcDrop" then
        if entry.many then return entry.id .. entry.kind .. "many" end
        return entry.npcID and (entry.id .. entry.kind .. entry.npcID)
    end
    if entry.kind == "world" then return entry.id .. "world" end
    return nil
end

function ForeverDB.Prune()
    if status.state ~= "done" then return end
    local questie = ns.Questie.Enabled() and ns.Questie.State() == "done" and ns.Questie.Entries() or false
    if prunedFor == questie then return end
    -- pruned for another list: QuestieDB was switched off or its kinds changed, read again
    if prunedFor then
        prunedFor = nil
        return load()
    end
    prunedFor = questie
    if not questie then return end
    local have = {}
    for _, entry in ipairs(questie) do
        local k = key(entry)
        if k then have[k] = true end
    end
    local kept = {}
    for _, entry in ipairs(extra.entries) do
        local k = not entry.chance and key(entry)
        if k and have[k] then
            stats.pruned = stats.pruned + 1
        else
            kept[#kept + 1] = entry
        end
    end
    extra = {provider = "foreverdb", entries = kept, areas = extra.areas, instances = extra.instances}
end

-- SkillUp and ATT know the skill each recipe is learned at on Forever, ForeverDB only when it turns yellow
function ForeverDB.ApplySkills()
    local learned = ns.ATT.State() .. tostring(ns.ATT.Enabled()) .. ns.SkillUp.State() .. tostring(ns.SkillUp.Enabled())
    if learnedFor == learned then return end
    learnedFor = learned
    for _, entry in ipairs(extra.entries) do
        if entry.kind == "craft" and entry.spell then
            entry.yellow = entry.yellow or entry.skill
            entry.skill = ns.SkillUp.LearnedAt(entry.spell) or entry.yellow
        end
    end
end

function load()
    if ns.inCombat then return C_Timer.After(2, load) end
    if not data() then Util.SafeCall(C_AddOns.LoadAddOn, ADDON) end
    if not ENGLISH[GetLocale()] and ns.addon.db.profile.foreverdbLocales ~= false and exists(LOCALES)
      and not Util.AddOnLoaded(LOCALES) then Util.SafeCall(C_AddOns.LoadAddOn, LOCALES) end
    ns.Guard(read)
end

-- straight away, still behind the loading screen
function ForeverDB.Init()
    if not (ForeverDB.Installed() and ForeverDB.Enabled()) then
        status.state = "off"
        return
    end
    status.state = "waiting"
    load()
end

function ForeverDB.SetEnabled(value)
    ns.addon.db.profile.foreverdb = value and true or false
    if value and status.state == "off" then ForeverDB.Init() end
    ns.RebuildIndex()
end

function ForeverDB.Loaded() return data() ~= nil end
