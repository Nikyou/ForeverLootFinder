-- AtlasLoot's lists besides crafting. read-only. its set lists are skipped, every piece is listed where it drops
local _, ns = ...
local Util = ns.Util

local Lists = {}
ns.AtlasLootLists = Lists

local MODULES = {
    "AtlasLootClassic_DungeonsAndRaids", "AtlasLootClassic_Factions", "AtlasLootClassic_PvP", "AtlasLootClassic_Collections",
}
local LOAD_DELAY, LOAD_GAP = 4, 1 -- AtlasLoot collects garbage after each module

-- numbered per module in the order its data.lua adds them
local DR_RAID_TYPES = {[3] = true, [4] = true, [5] = true} -- Forever Raids, 20 Raids, 40 Raids
local SKIP_CONTENT = {Mounts = true, Companions = true, Tabards = true, Legendarys = true}

local ALIAS = {
    Ragefire = {"Ragefire Chasm"},
    ["TheTempleOfAtal'Hakkar"] = {"Sunken Temple"},
    Stratholme = {"Stratholme: Living", "Stratholme: Undead"},
}

local function newExtra()
    return {provider = "atlasloot", entries = {}, dungeons = {}, areas = {}, names = {}, instances = {}, npcs = {}}
end

-- areas: [area ID] = place key, so a raid's quests can go with it. instances: [instance map ID] = place keys, the
-- wings share one. npcs: [creature ID] = its boss. both tie other addons' creature drops to the place
local extra = newExtra()
local EMPTY = newExtra()
local status = Util.NewStatus("atlasloot lists", {modules = 0, items = 0, matched = 0, places = 0, skippedSets = 0, chances = 0})
local stats = status.counts

local isSecret = Util.IsSecret
local equippable = Util.Equippable

function Lists.Installed() return ns.AtlasLoot.Installed() and type(ns.AtlasLoot.Get().ItemDB) == "table" end
function Lists.Enabled() return ns.AtlasLoot.Enabled() end
function Lists.State() return status.state end
function Lists.Stats() return stats end
function Lists.Status() return status end
function Lists.Entries() return Lists.Enabled() and extra or EMPTY end
Lists.Extra = Lists.Entries

function Lists.Name(key) return extra.names[key] end

local function clean(text)
    if type(text) ~= "string" or isSecret(text) then return nil end
    return Util.StripCodes(text)
end

-- keeps bytes past ASCII: %w only knows a-z and Cyrillic names would squash to ""
local function squash(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("(%l)(%u)", "%1 %2"):lower()
    text = (" " .. text .. " "):gsub("[%s%p%c]+", " "):gsub(" the ", " ")
    text = text:gsub("%s+", "")
    return text ~= "" and text or nil
end
Lists.Squash = squash

local function call(object, method, ...)
    local fn = type(object) == "table" and object[method]
    return Util.SafeCall(fn, object, ...)
end

-- rates are per NPC and item. a section may name several NPCs, the first with a rate wins
local function dropRate(section, id)
    local al = ns.AtlasLoot.Get()
    local droprate = al and type(al.Data) == "table" and al.Data.Droprate
    if type(droprate) ~= "table" then return nil end
    local npcs = section.npcID
    if type(npcs) == "number" then npcs = {npcs} end
    if type(npcs) ~= "table" then return nil end
    for _, npc in ipairs(npcs) do
        local rate = call(droprate, "GetData", npc, id)
        if type(rate) == "number" and not isSecret(rate) and rate > 0 then return rate end
    end
    return nil
end

local function fdjDungeons()
    local byName = {}
    local data = ns.SourceData()
    for _, dungeon in ipairs(data and data.dungeons or {}) do
        for _, text in ipairs({dungeon.key, ns.DungeonJournal.DungeonName(dungeon.key)}) do
            local key = squash(text)
            if key and not byName[key] then byName[key] = dungeon end
        end
    end
    return byName
end

local function matchDungeons(key, name, byName)
    local list = {}
    local function find(text)
        local squashed = squash(text)
        return squashed and byName[squashed] or nil
    end
    for _, alias in ipairs(ALIAS[key] or {}) do
        local dungeon = find(alias)
        if dungeon then list[#list + 1] = dungeon end
    end
    if #list > 0 then return list end
    local dungeon = find(key) or find(name)
    return dungeon and {dungeon} or nil
end

-- Stratholme is two FDJ dungeons
local function pickDungeon(list, bossName)
    if #list == 1 or not bossName then return list[1] end
    local wanted = squash(bossName)
    if not wanted then return list[1] end
    for _, dungeon in ipairs(list) do
        for _, boss in ipairs(dungeon.bosses or {}) do if squash(boss.name) == wanted then return dungeon end end
    end
    return list[1]
end

local STANDING = {
    [4] = "FACTION_STANDING_LABEL4",
    [5] = "FACTION_STANDING_LABEL5",
    [6] = "FACTION_STANDING_LABEL6",
    [7] = "FACTION_STANDING_LABEL7",
    [8] = "FACTION_STANDING_LABEL8",
}
function Lists.StandingName(standing)
    local value = STANDING[standing] and rawget(_G, STANDING[standing])
    return type(value) == "string" and value or tostring(standing)
end

local function factionName(id)
    local name = Util.SafeCall(rawget(_G, "GetFactionInfoByID"), id)
    if type(name) == "string" and not isSecret(name) then return name end
    local data = C_Reputation and Util.SafeCall(C_Reputation.GetFactionDataByID, id)
    if type(data) == "table" and type(data.name) == "string" then return data.name end
    return nil
end

-- a second item with a count beside the item is what it costs: 125 Tarnished Undermine Reals, 1200 Darkmoon tickets
local AMOUNT2 = 904
local function rowPrice(row)
    local currency, count = row and row[3], row and row[AMOUNT2]
    if type(currency) == "number" and currency > 0 and type(count) == "number" and count > 0 then
        return {{item = currency, count = count}}
    end
    return nil
end

local PRICED = {vendor = true, event = true, pvp = true, reputation = true}

local function rowItems(row, diffFaction)
    local out = {}
    if type(row) ~= "table" then return out end
    local value = row[2]
    if type(value) == "number" and value > 0 then
        local faction = diffFaction
        if row[901] == true then
            faction = "Horde"
        elseif row[902] == true then
            faction = "Alliance"
        end
        out[#out + 1] = {id = value, faction = faction}
    elseif value == nil then
        if type(row[901]) == "number" then out[#out + 1] = {id = row[901], faction = "Horde"} end
        if type(row[902]) == "number" then out[#out + 1] = {id = row[902], faction = "Alliance"} end
    end
    return out
end

-- header rows come along for the standing markers
local function sectionRows(section, factionOf)
    local list = {}
    for diff, rows in pairs(section) do
        if type(diff) == "number" and type(rows) == "table" then
            for _, row in ipairs(rows) do list[#list + 1] = {row = row, faction = factionOf[diff]} end
        end
    end
    return list
end

-- TableType is the number AddItemTableType gave, its format table starts with the type's name
local SET_TYPE = "Set"
local function isSetTable(storage, content, section)
    local function setType(index)
        local format = type(index) == "number" and call(storage, "GetItemTableType", index)
        return type(format) == "table" and format[1] == SET_TYPE
    end
    return setType(section.TableType) or setType(content.TableType)
end

-- AtlasLoot's holiday lists, to ns.Holidays' keys
local HOLIDAYS = {
    Darkmoon = "darkmoon",
    LunarFestival = "lunar",
    Valentineday = "love",
    Noblegarden = "noblegarden",
    ChildrensWeek = "children",
    MidsummerFestival = "midsummer",
    FishingExtravaganza = "fishing",
    HarvestFestival = "harvest",
    Halloween = "hallows",
    WinterVeil = "winterVeil",
}

-- classify returns nil to skip a content
local function readModule(module, storage, classify, out, byName, checkpoint)
    local factionOf = {}
    local alliance = call(storage, "GetDifficultyByName", "alliance")
    local horde = call(storage, "GetDifficultyByName", "horde")
    if type(alliance) == "number" then factionOf[alliance] = "Alliance" end
    if type(horde) == "number" then factionOf[horde] = "Horde" end
    local types = call(storage, "GetContentTypes") or {}
    for key, content in pairs(storage) do
        if type(key) == "string" and type(content) == "table" and type(content.items) == "table"
          and not (type(content.gameVersion) == "number" and content.gameVersion > 1) and not SKIP_CONTENT[key] then
            local typeIndex = type(content.ContentType) == "number" and content.ContentType or nil
            -- a type is {name, colour}
            local typeName = typeIndex and type(types[typeIndex]) == "table" and types[typeIndex][1] or nil
            local name = clean(call(content, "GetName", true)) or clean(content.name) or key
            local how = classify(content, typeIndex, key, typeName)
            if how then
                stats.places = stats.places + 1
                -- FDJ has no raids
                local matched = how.place == "dungeon" and not how.raid and matchDungeons(key, name, byName) or nil
                local ownKey
                if how.place == "dungeon" and not matched then
                    ownKey = "al:" .. key
                    out.names[ownKey] = name
                    local range = type(content.LevelRange) == "table" and content.LevelRange or {}
                    local low, high = tonumber(range[2] or range[1]), tonumber(range[3] or range[2] or range[1])
                    -- max-level content whatever level lets you in
                    if how.raid then low, high = ns.Filter.MAX_LEVEL, ns.Filter.MAX_LEVEL end
                    out.dungeons[#out.dungeons + 1] = {
                        key = ownKey,
                        name = name,
                        raid = how.raid,
                        levelMin = low,
                        levelMax = high,
                        levelText = low and (low == high and tostring(low) or format("%d-%d", low, high or low)) or nil,
                        bosses = {},
                        atlasloot = true,
                    }
                elseif matched then
                    stats.matched = stats.matched + 1
                end
                local area = tonumber(content.MapID)
                local placeKey = ownKey or (matched and matched[1].key)
                if area and placeKey and not out.areas[area] then out.areas[area] = placeKey end
                local instance = tonumber(content.InstanceID)
                if instance and placeKey then
                    local keys = out.instances[instance] or {}
                    out.instances[instance] = keys
                    for _, place in ipairs(matched or {{key = ownKey}}) do
                        local known = false
                        for _, k in ipairs(keys) do if k == place.key then known = true end end
                        if not known then keys[#keys + 1] = place.key end
                    end
                end
                for index, section in ipairs(content.items) do
                    if type(section) == "table" and not section.IgnoreAsSource then
                        if isSetTable(storage, content, section) then
                            stats.skippedSets = stats.skippedSets + 1
                        else
                            local sectionName = clean(section.name) or clean(call(content, "GetNameForItemTable", index, true))
                                                  or name
                            local base = how.base(sectionName, section, name, content)
                            if base then
                                local dungeonKey = ownKey
                                if matched then dungeonKey = pickDungeon(matched, sectionName).key end
                                local npcs = section.npcID
                                if type(npcs) == "number" then npcs = {npcs} end
                                if dungeonKey and base.bossName and type(npcs) == "table" then
                                    for _, npc in ipairs(npcs) do
                                        if type(npc) == "number" and not out.npcs[npc] then
                                            out.npcs[npc] = {dungeon = dungeonKey, bossName = base.bossName, kind = base.kind}
                                        end
                                    end
                                end
                                local standing, standingFaction
                                for _, item in ipairs(sectionRows(section, factionOf)) do
                                    local marker = type(item.row) == "table" and item.row[2]
                                    if type(marker) == "string" then
                                        -- "f529rep8": faction and standing for the rows below
                                        local factionID, rank = marker:match("^f(%d+)rep(%d+)$")
                                        if factionID then
                                            standing, standingFaction = tonumber(rank), tonumber(factionID)
                                        end
                                    end
                                    for _, row in ipairs(rowItems(item.row, item.faction)) do
                                        if equippable(row.id) then
                                            local entry = {
                                                id = row.id,
                                                provider = "atlasloot",
                                                dungeon = dungeonKey,
                                                faction = row.faction,
                                                alModule = module,
                                                alContent = key,
                                                alBoss = index,
                                            }
                                            for field, value in pairs(base) do
                                                entry[field] = value
                                            end
                                            if entry.kind == "reputation" or entry.kind == "pvp" then
                                                entry.standing = entry.standing or standing
                                                entry.factionID = entry.factionID or standingFaction
                                                entry.factionName =
                                                  entry.factionID and factionName(entry.factionID) or entry.factionName
                                            end
                                            if PRICED[entry.kind] then
                                                entry.price = rowPrice(item.row)
                                            end
                                            if entry.bossName then
                                                entry.bossIndex = index
                                            end
                                            entry.chance = dropRate(section, row.id)
                                            if entry.chance then
                                                stats.chances = stats.chances + 1
                                            end
                                            -- a vendor list without a price isn't one
                                            if entry.kind ~= "vendor" or entry.price then
                                                out.entries[#out.entries + 1] = entry
                                                stats.items = stats.items + 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    checkpoint()
                end
            end
        end
    end
end

-- AtlasLoot doesn't mark quest sections, so go by the name. the Forever ones are English on every client
-- ("Quest Rewards (Eye of Mugg)")
local function hasWord(text, english, localized)
    if text:find(english, 1, true) then return true end
    return type(localized) == "string" and localized ~= "" and not isSecret(localized) and text:find(localized, 1, true) ~= nil
end

-- AtlasLoot.Locales stays empty: its __index hands out the translation, or the key itself
local function localeText(text)
    local al = ns.AtlasLoot.Get()
    local locales = al and al.Locales
    if type(locales) ~= "table" then return text end
    local ok, value = pcall(function() return locales[text] end)
    return ok and type(value) == "string" and not isSecret(value) and value or text
end

local function questWord() return localeText("Quest") end

local function dungeonSection(sectionName, section)
    local text = sectionName or "?"
    if section.ExtraList then
        if hasWord(text, "Quest", questWord()) then
            local faction = (hasWord(text, "Horde", rawget(_G, "FACTION_HORDE")) and "Horde")
                              or (hasWord(text, "Alliance", rawget(_G, "FACTION_ALLIANCE")) and "Alliance") or nil
            -- no quest ids, so it overlaps with any quest of that dungeon
            return {kind = "quest", section = text, faction = faction}
        end
        return {kind = "trash", section = text}
    end
    return {kind = section.specialType == "rare" and "rare" or "boss", bossName = text}
end
Lists.DungeonSection = dungeonSection

local CLASSIFY = {
    AtlasLootClassic_DungeonsAndRaids = function(content, typeIndex, key)
        local raid = key == "WorldBosses" or DR_RAID_TYPES[typeIndex] == true
        return {
            place = "dungeon",
            raid = raid,
            base = function(sectionName, section) return dungeonSection(sectionName, section) end,
        }
    end,
    AtlasLootClassic_Factions = function(content)
        return {
            base = function(_, _, name)
                return {kind = "reputation", factionID = tonumber(content.FactionID), factionName = name}
            end,
        }
    end,
    AtlasLootClassic_PvP = function(content, typeIndex, key, typeName)
        return {base = function(sectionName, _, name)
            return {kind = "pvp", section = typeIndex == 1 and name or sectionName}
        end}
    end,
    -- by the type's name: AtlasLoot Forever added types in front, shifting the numbers
    AtlasLootClassic_Collections = function(_, _, key, typeName)
        if typeName == nil then return nil end
        if typeName == localeText("World Events") then
            return {base = function(_, _, name) return {kind = "event", eventName = name, holiday = HOLIDAYS[key]} end}
        end
        if typeName == localeText("Collections") then
            return {base = function(sectionName) return {kind = "world", section = sectionName} end}
        end
        -- AtlasLoot Forever's own type, not translated: the Tarnished Undermine Real vendor. it names no vendor
        if typeName == "Forever" then return {base = function() return {kind = "vendor"} end} end
        return nil
    end,
}

-- Forever's raids only have "loot will be updated" rows so far
local function dropEmptyPlaces(out)
    local used, kept = {}, {}
    for _, entry in ipairs(out.entries) do if entry.dungeon then used[entry.dungeon] = true end end
    for _, dungeon in ipairs(out.dungeons) do if used[dungeon.key] then kept[#kept + 1] = dungeon end end
    for area, key in pairs(out.areas) do if key:sub(1, 3) == "al:" and not used[key] then out.areas[area] = nil end end
    local function gone(key) return key:sub(1, 3) == "al:" and not used[key] end
    for npc, boss in pairs(out.npcs) do if gone(boss.dungeon) then out.npcs[npc] = nil end end
    for instance, keys in pairs(out.instances) do
        local kept = {}
        for _, key in ipairs(keys) do if not gone(key) then kept[#kept + 1] = key end end
        out.instances[instance] = #kept > 0 and kept or nil
    end
    out.dungeons = kept
end

-- swapped in whole, an index built meanwhile keeps the last full read
local function readAll()
    if not ns.AtlasLoot.Get() then
        status.state = "nodata"
        return
    end
    status.state, status.error, status.ms = "scanning", nil, 0
    stats.modules, stats.items, stats.matched, stats.places, stats.skippedSets, stats.chances = 0, 0, 0, 0, 0, 0
    local out = newExtra()
    local byName = fdjDungeons()
    local i = 0
    local function nextModule()
        i = i + 1
        local module = MODULES[i]
        if not module then
            dropEmptyPlaces(out)
            extra = out
            stats.ms = status.ms
            status.state = #out.entries > 0 and "done" or "nodata"
            return ns.RebuildIndex()
        end
        local storage = ns.AtlasLoot.Storage(module)
        if not storage then return nextModule() end
        stats.modules = stats.modules + 1
        Util.RunSliced(function(checkpoint) readModule(module, storage, CLASSIFY[module], out, byName, checkpoint) end,
                       function(ok, err, ms)
            status.ms = status.ms + ms
            if not ok then
                status.error = module .. ": " .. tostring(err)
                ns.ReportError(err)
            end
            nextModule()
        end)
    end
    nextModule()
end

local function loadModules(i)
    local module = MODULES[i]
    if not module then return ns.Guard(readAll) end
    ns.AtlasLoot.LoadModule(module, function() C_Timer.After(LOAD_GAP, function() loadModules(i + 1) end) end)
end

function Lists.CanOpen(source)
    local al = ns.AtlasLoot.Get()
    local frame = al and type(al.GUI) == "table" and al.GUI.frame
    return type(frame) == "table" and source ~= nil and source.alModule ~= nil and source.alContent ~= nil
end

function Lists.Open(source)
    if not Lists.CanOpen(source) then return false end
    local frame = ns.AtlasLoot.Get().GUI.frame
    -- Show runs AtlasLoot's auto-select, so pick after it
    if not frame:IsShown() then frame:Show() end
    local function pick(select, value)
        if type(select) == "table" and type(select.SetSelected) == "function" and value ~= nil then
            return pcall(select.SetSelected, select, value)
        end
        return false
    end
    pick(frame.moduleSelect, source.alModule)
    pick(frame.subCatSelect, source.alContent)
    pick(frame.boss, source.alBoss or 1)
    return true
end

-- the modules are in, only the matching to FDJ's dungeons changes
function Lists.Reread()
    local state = status.state
    if (state == "done" or state == "nodata") and Lists.Installed() and Lists.Enabled() then ns.Guard(readAll) end
end

function Lists.Init()
    if not (Lists.Installed() and Lists.Enabled()) then
        status.state = "off"
        return
    end
    status.state = "waiting"
    C_Timer.After(LOAD_DELAY, function() loadModules(1) end)
end

Lists.SetEnabled = ns.AtlasLoot.SetEnabled
ns.AtlasLoot.AddReader(Lists)
