-- the index is built on first use, then once per burst of changes, never in combat
local _, ns = ...
local Util = ns.Util

-- FDJ learns item IDs while you play
local FDJ_REREAD = 300

local index
local dirty = false
local pending = false -- a "data" change is owed once the new index is in
local scheduled = false
local sourceData, sourceReadAt, sourceForced
ns.indexStats = {builds = 0, ms = 0, lastMs = 0, fdjReads = 0, fdjMs = 0}

-- without FDJ (or with it off) an empty table, a new one each time that changes, Questie.Areas caches by it
function ns.SourceData(force)
    if not ns.DungeonJournal.Active() then
        if not (sourceData and sourceData.empty) then sourceData = ns.DungeonJournal.Empty() end
        return sourceData
    end
    if force or sourceForced or not sourceData or sourceData.empty or GetTime() - sourceReadAt > FDJ_REREAD then
        sourceForced = false
        local started = Util.Clock()
        sourceData = ns.DungeonJournal.Read()
        sourceReadAt = GetTime()
        local stats = ns.indexStats
        stats.fdjReads, stats.fdjMs = stats.fdjReads + 1, Util.Clock() - started
    end
    return sourceData
end

local function build()
    local data = ns.SourceData()
    local started = Util.Clock()
    index = ns.Index.Build(data, {
        {provider = "questie", entries = ns.Questie.Entries(), areas = ns.Questie.Areas()},
        {provider = "atlasloot", entries = ns.Crafts.Entries()},
        ns.AtlasLootLists.Entries(),
        {provider = "attune", entries = ns.Attune.Entries()},
        {provider = "silverdragon", entries = ns.SilverDragon.Entries()},
    }, ns.Priority())
    dirty = false
    ns.Sets.Invalidate()
    ns.Items.Track(index)
    local stats = ns.indexStats
    stats.lastMs = Util.Clock() - started
    stats.builds, stats.ms = stats.builds + 1, stats.ms + stats.lastMs
    return index
end

-- never nil. in combat the old index serves until it ends
function ns.GetIndex()
    if index and (not dirty or ns.inCombat) then return index end
    return build()
end

local function flush()
    scheduled = false
    if ns.inCombat or not pending then return end
    pending = false
    if dirty or not index then ns.Guard(build) end
    ns.FireChange("data")
end

function ns.RebuildIndex(rereadSource)
    dirty, pending = true, true
    if rereadSource then sourceForced = true end
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, flush)
end

function ns.IndexSettled() return index ~= nil and not dirty end

function ns.FlushIndex()
    if pending and not scheduled then
        scheduled = true
        C_Timer.After(0, flush)
    end
end

-- saved as text because AceDB merges saved lists with their defaults entry by entry
function ns.Priority()
    local saved = ns.addon.db.profile.priority or {}
    local out = {}
    for group, order in pairs(ns.Index.DEFAULT_PRIORITY) do
        local list, seen = {}, {}
        local text = type(saved[group]) == "string" and saved[group] or ""
        for name in text:gmatch("[^>%s]+") do
            for _, known in ipairs(order) do
                if known == name and not seen[name] then
                    seen[name] = true
                    list[#list + 1] = name
                end
            end
        end
        for _, name in ipairs(order) do if not seen[name] then list[#list + 1] = name end end
        out[group] = list
    end
    return out
end

function ns.SetPriority(group, list)
    local profile = ns.addon.db.profile
    profile.priority = profile.priority or {}
    profile.priority[group] = table.concat(list, ">")
    ns.RebuildIndex()
end

local function className(classFile, female)
    local list = female and LOCALIZED_CLASS_NAMES_FEMALE or LOCALIZED_CLASS_NAMES_MALE
    return list and list[classFile]
end

local characters = {}
function ns.InvalidateCharacters() wipe(characters) end

-- shared, don't change it
function ns.Character(charKey)
    charKey = charKey or ns.charKey
    local cached = charKey and characters[charKey]
    if cached then return cached end
    local data = ns.addon.db.global.characters[charKey] or {}
    local character = {key = charKey, class = data.class, race = data.race, level = data.level or 1, faction = data.faction}
    character.raceBit = ns.Questie.RaceBit(data.raceID)
    character.factionRaces = data.faction and ns.Questie.FactionRaces(data.faction)
    character.professions = data.professions
    -- alts saved before classID was kept
    local classID = data.classID
    character.classNames = {className(data.class, false), className(data.class, true)}
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        for id = 1, 12 do
            local info = Util.SafeCall(C_CreatureInfo.GetClassInfo, id)
            if type(info) == "table" and info.classFile == data.class and type(info.className) == "string" then
                character.classNames[#character.classNames + 1] = info.className
                if not classID then classID = type(info.classID) == "number" and info.classID or id end
            end
        end
    end
    character.classID = classID
    character.classBit = ns.Questie.ClassBit(classID)
    character.raceNames = {}
    if data.raceID and C_CreatureInfo then
        local info = Util.SafeCall(C_CreatureInfo.GetRaceInfo, data.raceID)
        if type(info) == "table" and type(info.raceName) == "string" then character.raceNames[1] = info.raceName end
    end
    if charKey == ns.charKey then
        local localized = UnitRace("player")
        if type(localized) == "string" and not Util.IsSecret(localized) then table.insert(character.raceNames, localized) end
    end
    if charKey then characters[charKey] = character end
    return character
end

-- for tooltips, the set panel and the reminder
local doableCtx = setmetatable({}, {__mode = "k"})
function ns.DoableSources(sources, charKey, hideFaction)
    local character = ns.Character(charKey)
    local ctx = doableCtx[character]
    if not ctx then
        ctx = ns.Filter.CharacterContext(character)
        doableCtx[character] = ctx
    end
    if hideFaction == nil then hideFaction = ns.Filters().faction ~= false end
    return ns.Filter.Doable(sources, ctx, hideFaction)
end

local activeScale, scaleKnown = nil, false
function ns.InvalidateScale() scaleKnown = false end

function ns.ActiveScale()
    local saved = ns.addon.db.char.pawnScale
    if scaleKnown and activeScale == saved then return activeScale end
    if not ns.Pawn.IsReady() then return nil end
    local scale = ns.Pawn.Resolve(saved)
    if scale ~= saved then ns.addon.db.char.pawnScale = scale end
    activeScale, scaleKnown = scale, true
    return scale
end

-- a new one per list pass
function ns.FilterContext(charKey)
    local profile = ns.addon.db.profile
    local character = ns.Character(charKey)
    local idx = ns.GetIndex()
    local scale = ns.ActiveScale()
    local compare = scale and ns.Owned.Comparer(scale, character.class, character.level) or nil
    local ctx = ns.Filter.Context(ns.Filters(), character, {
        showUnknown = profile.showUnknown,
        showMissing = profile.showMissing,
        randomPass = profile.randomPass,
        owned = ns.Owned.Set(),
        hidden = ns.addon.db.char.hidden,
        dungeonByKey = idx and idx.dungeonByKey or {},
        -- only the logged-in character's quest log is known
        completed = character.key == ns.charKey and ns.Questie.IsCompleted or nil,
        pawnUpgrade = compare and function(record, info)
            if not info.loaded then return nil end
            -- asking queues it, the row stays greyed till then
            if record.id > 0 and not info.unique and ns.Pawn.Lookup(record.id, scale) == nil then return nil end
            local result = compare(record, info)
            if result.unique == "equipped" then return -1 end
            if result.upgradeKnown and result.upgrade == nil then return 0 end
            return result.upgrade
        end or nil,
        auctionPrice = ns.Auctionator.Active() and function(record, info)
            local price = ns.Auctionator.ForRecord(record, info)
            return price and price.price or nil
        end or nil,
    })
    ctx.ownCharacter = character.key == ns.charKey
    ctx.compare = compare
    return ctx, character
end
