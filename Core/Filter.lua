-- pure Lua, no WoW calls
local _, ns = ...
local Classes, Index, StatMap, Restrictions = ns.Classes, ns.Index, ns.StatMap, ns.Restrictions

local Filter = {}
ns.Filter = Filter

Filter.MAX_LEVEL = 60

-- per character (AceDB char)
function Filter.Defaults()
    return {
        slot = "HEAD",
        dungeonSlot = "ALL",
        armor = nil, -- nil follows the class and level, a table once the player picks
        weapons = nil,
        stats = {}, -- [STAT] = 1 want, -1 exclude
        statMode = "ANY",
        -- rare, trash, shared and probable are parts of dungeon
        sources = {
            dungeon = true,
            rare = true,
            trash = true,
            shared = true,
            quest = true,
            probable = false,
            zoneQuest = true,
            craft = true,
            raid = true, -- raids and world bosses
            reputation = true,
            pvp = true,
            event = true,
            world = true,
            vendor = true,
            npcDrop = true,
        },
        hideCompleted = true, -- unless the item is owned
        craftOwnBoP = true, -- BoP crafts only from this character's professions
        ownSkill = true, -- "Requires Engineering" only when the character has it
        hideCosmetic = true,
        faction = true,
        maxLevel = {on = true, mode = "relative", fixed = 60, plus = 5},
        dungeonLevel = {on = false, min = 1, max = 60},
        bind = "ANY",
        speed = {on = false, min = 1.0, max = 4.0},
        setsOnly = false,
        special = false,
        minQuality = 2,
        -- AtlasLoot's drop rates
        chance = {on = false, min = 5, keepUnknown = true},
        -- max is in gold. items with no price stay
        price = {only = false, maxOn = false, max = 50},
        dungeons = nil, -- nil is all
        raids = nil,
        search = "",
        hideOwned = false,
        pawnUpgradesOnly = false,
    }
end

local ARMOR_SLOTS = {
    HEAD = true,
    SHOULDER = true,
    CHEST = true,
    WRIST = true,
    HANDS = true,
    WAIST = true,
    LEGS = true,
    FEET = true,
}
local WEAPON_SLOTS = {ONEHAND = true, MAINHAND = true, TWOHAND = true, RANGED = true}

function Filter.IsWeapon(info)
    if WEAPON_SLOTS[info.slot] then return true end
    return info.slot == "OFFHAND" and info.itemType ~= nil and info.itemType ~= "SHIELD" and info.itemType ~= "HELD"
end

-- Forever's race masks go past 32 bits, too wide for bit ops
function Filter.HasBit(mask, bit) return math.floor(mask / bit) % 2 == 1 end

function Filter.MasksOverlap(a, b)
    local bit = 1
    while bit <= a and bit <= b do
        if Filter.HasBit(a, bit) and Filter.HasBit(b, bit) then return true end
        bit = bit * 2
    end
    return false
end

-- fallback for QuestieDB's Enum.factionRaceMasks: classic races plus each side's Skyborne (bits 32 and 33)
Filter.FACTION_RACES = {Alliance = 1 + 4 + 8 + 64 + 2 ^ 32, Horde = 2 + 16 + 32 + 128 + 2 ^ 33}

function Filter.CharacterContext(character)
    local ctx = {class = character.class, faction = character.faction, classBit = character.classBit,
                 raceBit = character.raceBit}
    local races = character.factionRaces or Filter.FACTION_RACES[character.faction or ""]
    if races and ctx.raceBit and not Filter.HasBit(races, ctx.raceBit) then races = races + ctx.raceBit end
    ctx.factionRaces = races
    return ctx
end

-- "class" and "race" are final, "faction" is up to the faction filter. class quests often have one copy per race
function Filter.SourceBlock(source, ctx)
    if source.classOnly and source.classOnly ~= ctx.class then return "class" end
    local mask = source.classMask
    if mask and mask > 0 and ctx.classBit and not Filter.HasBit(mask, ctx.classBit) then return "class" end
    mask = source.raceMask
    if mask and mask > 0 and ctx.raceBit and not Filter.HasBit(mask, ctx.raceBit) then
        if ctx.factionRaces and Filter.MasksOverlap(mask, ctx.factionRaces) then return "race" end
        return "faction"
    end
    if source.faction and ctx.faction and source.faction ~= ctx.faction then return "faction" end
    return nil
end

-- returns the list itself when all pass
function Filter.Doable(sources, ctx, hideFaction)
    local out
    for i, source in ipairs(sources) do
        local block = Filter.SourceBlock(source, ctx)
        local ok = block == nil or (block == "faction" and not hideFaction)
        if ok then
            if out then out[#out + 1] = source end
        elseif not out then
            out = {}
            for j = 1, i - 1 do out[j] = sources[j] end
        end
    end
    return out or sources
end

function Filter.MaxLevel(state, level)
    local limit = state.maxLevel
    if not limit or not limit.on then return nil end
    if limit.mode == "fixed" then return limit.fixed end
    return math.min(Filter.MAX_LEVEL, (level or 1) + (limit.plus or 0))
end

local function statLists(stats)
    local wanted, excluded = {}, {}
    for key, mode in pairs(stats or {}) do
        if mode == 1 then
            wanted[#wanted + 1] = key
        elseif mode == -1 then
            excluded[#excluded + 1] = key
        end
    end
    return wanted, excluded
end

-- one context per list pass, it caches what it works out
function Filter.Context(state, character, opts)
    opts = opts or {}
    local ctx = Filter.CharacterContext(character)
    for key, value in pairs({
        race = character.race,
        level = character.level or 1,
        classNames = Restrictions.NameSet(character.classNames or {}),
        raceNames = Restrictions.NameSet(character.raceNames or {}),
        showUnknown = opts.showUnknown ~= false,
        showMissing = opts.showMissing == true,
        randomPass = opts.randomPass ~= false,
        owned = opts.owned or {},
        hidden = opts.hidden or {},
        dungeonByKey = opts.dungeonByKey or {},
        pawnUpgrade = opts.pawnUpgrade,
        auctionPrice = opts.auctionPrice,
        completed = opts.completed,
        professions = character.professions,
    }) do ctx[key] = value end
    ctx.armor = state.armor or Classes.ArmorPreselect(ctx.class, ctx.level)
    ctx.weapons = state.weapons or Classes.WeaponPreselect(ctx.class)
    ctx.maxLevel = Filter.MaxLevel(state, ctx.level)
    ctx.search = state.search and ns.Util.Lower(state.search):gsub("^%s+", ""):gsub("%s+$", "") or ""
    ctx.stats = state.stats
    ctx.wanted, ctx.excluded = statLists(state.stats)
    return ctx
end

-- not a filter, the player can't switch it off
function Filter.ForOtherClass(record, info, ctx)
    local itemType = info.itemType
    local relicClass = itemType and Classes.RELIC_CLASS[itemType]
    if relicClass and relicClass ~= ctx.class then return "relic" end
    if itemType and Index.ARMOR_KINDS[itemType] and info.slot ~= "BACK" and not Classes.CanEverWear(ctx.class, itemType) then
        return "armor type"
    end
    if itemType and not Index.ARMOR_KINDS[itemType] and not Classes.CanEverUse(ctx.class, itemType) then return "weapon type" end
    if info.classes and Restrictions.ExcludesName(info.classes, ctx.classNames) then return "class list" end
    local otherClass = 0
    for _, source in ipairs(record.sources) do
        if Index.IsQuest(source) and Filter.SourceBlock(source, ctx) == "class" then otherClass = otherClass + 1 end
    end
    if otherClass > 0 and otherClass == #record.sources then return "class quest" end
    return nil
end

function Filter.ForOtherRace(info, ctx)
    if info.races and Restrictions.ExcludesName(info.races, ctx.raceNames) then return "race list" end
    return nil
end

-- reputation, event and vendor gear often has no required level: item level minus this is close enough
local NO_LEVEL_KINDS = {reputation = true, pvp = true, event = true, world = true, vendor = true}
Filter.ILVL_MARGIN = 5

function Filter.EstimatedLevel(source, info)
    -- also a quest reward: Index gave it the quest's level
    if source.reqLevel then return nil end
    if not (NO_LEVEL_KINDS[source.kind] and info and info.loaded) then return nil end
    if (info.minLevel or 1) > 1 or type(info.ilvl) ~= "number" then return nil end
    local level = math.min(Filter.MAX_LEVEL, info.ilvl - Filter.ILVL_MARGIN)
    return level > 1 and level or nil
end

local function dungeonFits(dungeon, range)
    if not dungeon or not dungeon.levelMin then return true end
    return dungeon.levelMin <= range.max and (dungeon.levelMax or dungeon.levelMin) >= range.min
end

-- raids have their own switch instead of "dungeon drops", the parts (rares, trash, shared) count for both
local function kindOn(kind, kinds, raid)
    -- a combined item follows its dungeon's drops
    if kind == "combine" then kind = "boss" end
    if Index.DROP_KINDS[kind] then
        if raid then
            if kinds.raid == false then return false end
        elseif kinds.dungeon == false then
            return false
        end
        return kind == "boss" or kinds[kind] == true
    end
    return kinds[kind] ~= false
end

-- second result: a crafted item's binding hasn't loaded yet, so craftOwnBoP can't decide.
-- returns record.sources itself when all pass, callers only read it
function Filter.Sources(record, state, ctx, info)
    local out
    local kinds = state.sources or {}
    local unknown = false
    local all = record.sources
    for i, source in ipairs(all) do
        local placeKey = source.dungeon or source.tiedTo
        local place = placeKey and ctx.dungeonByKey[placeKey]
        local ok = kindOn(source.kind, kinds, place and place.raid)
        local block = ok and Filter.SourceBlock(source, ctx)
        if block and (block ~= "faction" or state.faction) then ok = false end
        if ok and placeKey then
            if place and place.raid and kinds.raid == false then ok = false end
            local picked = state.dungeons
            if place and place.raid then picked = state.raids end
            if ok and picked and not picked[placeKey] then ok = false end
            if ok and state.dungeonLevel and state.dungeonLevel.on and not dungeonFits(place, state.dungeonLevel) then
                ok = false
            end
            -- loot from high dungeons often has no required level
            if ok and ctx.maxLevel and place and place.levelMin and place.levelMin > ctx.maxLevel then ok = false end
        end
        local chance = state.chance
        if ok and chance and chance.on and Index.DROP_KINDS[source.kind] then
            if source.chance then
                if source.chance < (chance.min or 0) - 0.0001 then ok = false end
            elseif chance.keepUnknown == false then
                ok = false
            end
        end
        if ok and ctx.maxLevel and (source.kind == "npcDrop" or source.kind == "world") and source.levelMin
          and source.levelMin > ctx.maxLevel then
            ok = false
        end
        if ok and ctx.maxLevel and source.reqLevel and source.reqLevel > ctx.maxLevel then ok = false end
        if ok and ctx.maxLevel then
            local estimate = Filter.EstimatedLevel(source, info)
            if estimate and estimate > ctx.maxLevel then ok = false end
        end
        if ok and state.hideCompleted ~= false and source.questID and ctx.completed and ctx.completed(source.questID)
          and not (record.id and ctx.owned[record.id]) then ok = false end
        if ok and state.hideCompleted ~= false and source.viaQuests and ctx.completed
          and not (record.id and ctx.owned[record.id]) then
            local allDone = true
            for _, questID in ipairs(source.viaQuests) do if not ctx.completed(questID) then allDone = false end end
            if allDone then ok = false end
        end
        if ok and source.kind == "craft" and state.craftOwnBoP ~= false and ctx.professions
          and not ctx.professions[source.profession] then
            if info and info.bind == "BOP" then
                ok = false
            elseif info and not info.loaded then
                unknown = true
            end
        end
        if ok then
            if out then out[#out + 1] = source end
        elseif not out then
            -- everything before this one passed
            out = {}
            for j = 1, i - 1 do out[j] = all[j] end
        end
    end
    return out or all, unknown
end

local function statsPass(record, info, state, ctx)
    local wanted, excluded = ctx.wanted, ctx.excluded
    if not wanted or ctx.stats ~= state.stats then wanted, excluded = statLists(state.stats) end
    if #wanted == 0 and #excluded == 0 then return "pass" end
    if record.randomBonus and ctx.randomPass then return "pass" end
    if not info.stats then return "unknown" end
    for _, key in ipairs(excluded) do if (StatMap.Value(info.stats, key) or 0) > 0 then return "fail" end end
    if #wanted == 0 then return "pass" end
    local hits = 0
    for _, key in ipairs(wanted) do if (StatMap.Value(info.stats, key) or 0) > 0 then hits = hits + 1 end end
    if state.statMode == "ALL" then return hits == #wanted and "pass" or "fail" end
    return hits > 0 and "pass" or "fail"
end

-- "pass", "unknown" (greyed), "missing" (would pass, the server doesn't know it) or "fail"
function Filter.Evaluate(record, info, state, ctx, ignoreSlot, skipUpgrade)
    if not info.slot then return "fail", nil, "not equippable" end
    if not ignoreSlot and ctx.slot and info.slot ~= ctx.slot then return "fail", nil, "slot" end
    if ctx.hidden[record.key] then return "fail", nil, "hidden" end
    if info.missing and not ctx.showMissing then return "fail", nil, "missing" end
    local other = Filter.ForOtherClass(record, info, ctx)
    if other then return "fail", nil, "class: " .. other end
    other = Filter.ForOtherRace(info, ctx)
    if other then return "fail", nil, "race: " .. other end
    local unknown = false
    if record.id and record.id > 0 and not info.tooltipLoaded then unknown = true end

    -- cheap checks before the sources, which may build a list
    local itemType = info.itemType
    if itemType and Index.ARMOR_KINDS[itemType] and ARMOR_SLOTS[info.slot] then
        if not ctx.armor[itemType] then return "fail", nil, "armor" end
    elseif itemType and not Index.ARMOR_KINDS[itemType] then
        if not ctx.weapons[itemType] then return "fail", nil, "weapon" end
    end

    local quality = info.quality or record.quality or 0
    if quality < (state.minQuality or 0) then return "fail", nil, "quality" end

    if ctx.maxLevel then
        if info.minLevel == nil then
            unknown = true
        elseif info.minLevel > ctx.maxLevel then
            return "fail", nil, "level"
        end
    end

    local sources, sourceUnknown = Filter.Sources(record, state, ctx, info)
    if #sources == 0 then return "fail", nil, "source" end
    if sourceUnknown then unknown = true end

    if state.bind == "BOP" or state.bind == "BOE" then
        if info.bind == nil and not info.loaded and not info.tooltipLoaded then
            unknown = true
        elseif info.bind ~= state.bind then
            return "fail", nil, "bind"
        end
    end

    if state.speed and state.speed.on and Filter.IsWeapon(info) then
        if not info.speed then
            unknown = true
        elseif info.speed < state.speed.min - 0.001 or info.speed > state.speed.max + 0.001 then
            return "fail", nil, "speed"
        end
    end

    if state.hideCosmetic ~= false and info.cosmetic then return "fail", nil, "cosmetic" end

    -- engineering goggles and such, whatever the binding
    if state.ownSkill ~= false and info.reqSkill and ctx.professions and not ctx.professions[info.reqSkill.id] then
        return "fail", nil, "profession"
    end

    if state.setsOnly then
        if not info.setID and not info.setName then
            if info.loaded and info.tooltipLoaded or info.notInGame then return "fail", nil, "set" end
            unknown = true
        end
    end

    if state.special then
        if not info.tooltipLoaded then
            unknown = true
        elseif not (info.hasUse or info.hasProc) then
            return "fail", nil, "special"
        end
    end

    local stats = statsPass(record, info, state, ctx)
    if stats == "fail" then return "fail", nil, "stats" end
    if stats == "unknown" then unknown = true end

    local search = ctx.search
    if search ~= "" then
        local name = ns.Util.Lower(info.name or record.name or "")
        if not name:find(search, 1, true) and not ns.Util.Lower(record.name or ""):find(search, 1, true) then
            return "fail", nil, "search"
        end
    end

    if state.hideOwned and record.id and ctx.owned[record.id] then return "fail", nil, "owned" end

    if state.pawnUpgradesOnly and ctx.pawnUpgrade and not skipUpgrade then
        local upgrade = ctx.pawnUpgrade(record, info)
        if upgrade == nil then
            unknown = true
        elseif upgrade <= 0 then
            return "fail", nil, "upgrade"
        end
    end

    local price = state.price
    if ctx.auctionPrice and price and (price.only or price.maxOn) then
        local value = info.bind ~= "BOP" and ctx.auctionPrice(record, info) or nil
        if value == nil then
            if price.only and info.bind == nil and not info.loaded then
                unknown = true
            elseif price.only then
                return "fail", nil, "price"
            end
        elseif price.maxOn and value > (price.max or 0) * 10000 then
            return "fail", nil, "price"
        end
    end

    if info.missing then return "missing", sources end
    return unknown and "unknown" or "pass", sources
end

function Filter.Shows(status, ctx)
    return status == "pass" or (status == "unknown" and ctx.showUnknown) or (status == "missing" and ctx.showMissing)
end

function Filter.CountBySlot(records, infoOf, state, ctx)
    local counts = {}
    for _, record in ipairs(records) do
        local info = infoOf(record)
        if info.slot then
            local status = Filter.Evaluate(record, info, state, ctx, true)
            if Filter.Shows(status, ctx) then counts[info.slot] = (counts[info.slot] or 0) + 1 end
        end
    end
    return counts
end

-- rows of one slot and the rail's counts in one pass. the Pawn upgrade check is the slow part, so only the
-- shown slot gets it; the third result says the other counts skipped it
function Filter.RunWithCounts(records, infoOf, state, ctx, slot)
    local rows, counts = {}, {}
    local approximate = slot ~= nil and state.pawnUpgradesOnly and ctx.pawnUpgrade ~= nil or false
    for _, record in ipairs(records) do
        local info = infoOf(record)
        local itemSlot = info.slot
        if itemSlot then
            local status, sources = Filter.Evaluate(record, info, state, ctx, true, approximate and itemSlot ~= slot)
            if Filter.Shows(status, ctx) then
                counts[itemSlot] = (counts[itemSlot] or 0) + 1
                if slot == nil or itemSlot == slot then
                    rows[#rows + 1] = {record = record, info = info, status = status, sources = sources}
                end
            end
        end
    end
    return rows, counts, approximate
end

function Filter.Run(records, infoOf, state, ctx)
    local rows = {}
    for _, record in ipairs(records) do
        local info = infoOf(record)
        local status, sources = Filter.Evaluate(record, info, state, ctx)
        if Filter.Shows(status, ctx) then
            rows[#rows + 1] = {record = record, info = info, status = status, sources = sources}
        end
    end
    return rows
end
