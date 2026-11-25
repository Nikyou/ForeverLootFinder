-- item data. only what's on screen is asked for (a slot, a tab's cards, the favourites); everything else comes from
-- Core/Cache.lua, which keeps it between sessions, or waits till it's shown
local _, ns = ...
local Index, Restrictions, StatMap, Util = ns.Index, ns.Restrictions, ns.StatMap, ns.Util

local Items = {}
ns.Items = Items

-- asked and not answered yet. more than this and the server starts dropping requests: no answer, then given up
local MAX_IN_FLIGHT = 60
local MAX_REQUESTS = 30 -- per frame
-- per item and view (opening a slot or tab again allows more), for one the client dropped before it was finished or
-- before Pawn could read it
local REFETCHES = 2
local BUILD_MS = 4 -- leaves Pawn its share of the frame
local BURST_BUILD_MS = 10
local REDRAW_DELAY = 0.4
local REDRAW_MAX_WAIT = 2 -- during a long burst
local TOOLTIP_RETRIES, TOOLTIP_RETRY_DELAY = 5, 1
-- the server answers in well under a second, or never (an item it won't talk about). one that never answers holds a
-- place among the requests in flight, so it's given up soon
local ANSWER_TIMEOUT, ANSWER_TRIES, CHECK_EVERY = 5, 2, 1
-- one the server didn't give last session either: once, briefly. it's likely still not there
local UNAVAILABLE_TIMEOUT, UNAVAILABLE_TRIES = 2, 1
local UNKNOWN_ICON = 134400

local BIND = {[1] = "BOP", [2] = "BOE", [3] = "BOU", [4] = "QUEST"}

local cache = {} -- [key] = info
local dirty = {}
local requested = {} -- once per session
local failed = {} -- the server doesn't know it
-- the client evicts items again, so "is it cached now" can't measure progress
local seen = {}
local tooltipTries = {}
local askedAt, asks = {}, {}
local inFlight = 0
local refetches, refetchQueue, refetchHead = {}, {}, 1
local gaveUp = {} -- no answer after ANSWER_TRIES requests
local started = false -- the window was opened
local tracked = {} -- ids in the index
local recordOf = {}
local queue, queued = {}, {}
local listeners = {}
local paused = false
local trackedCount = 0
local doneCount = 0
local wake -- restarts the OnUpdate, set by Items.Init

-- tooltips are slow, so infos are built a slice per frame rather than inside a redraw
local deferred = false
local buildFirst, firstHead, buildLater, buildHead = {}, 1, {}, 1
local hurry = {} -- what's on screen
local buildScheduled = false

Items.timing = {
    requests = 0,
    requestMs = 0,
    builds = 0,
    buildMs = 0,
    tooltipMs = 0,
    quick = 0,
    slices = 0,
    longestSlice = 0,
    redraws = 0,
    ignored = 0,
    loadStarted = nil,
    loadDone = nil,
}
local timing = Items.timing

local isSecret = Util.IsSecret

local function isDone(id) return seen[id] or failed[id] or gaveUp[id] end

local function ask(id)
    if not askedAt[id] then inFlight = inFlight + 1 end
    askedAt[id] = GetTime()
    -- may fire GET_ITEM_INFO_RECEIVED synchronously
    pcall(C_Item.RequestLoadItemDataByID, id)
end

local function settle(id)
    if askedAt[id] then
        askedAt[id] = nil
        inFlight = inFlight - 1
    end
end

-- false: the client doesn't have it. calling GetItemInfo then asks the server again, every time
local function clientHas(id)
    if not C_Item.IsItemDataCachedByID then return nil end
    local ok, result = pcall(C_Item.IsItemDataCachedByID, id)
    if not ok then return nil end
    return result == true
end

-- every way an item becomes done goes through here, or the count drifts
local function markDone(set, id)
    if set[id] then return end
    local was = isDone(id)
    set[id] = true
    if tracked[id] and not was then doneCount = doneCount + 1 end
    -- remembered for the next session, forgotten once it loads
    if ns.Cache then ns.Cache.SetUnavailable(id, set == failed and "failed" or set == gaveUp and "noanswer" or nil) end
end

local function unavailable(id) return ns.Cache ~= nil and ns.Cache.Unavailable(id) ~= nil end

local patternSets, englishSet
-- the client's rank and standing names to their numbers: 5 Private/Scout .. 18 Grand Marshal/High Warlord, 1 Hated ..
-- 8 Exalted, so the filter can weigh them against the character's
local rankOf, standingOf = {}, {}
local function patterns()
    if not patternSets then
        local G = {}
        for _, key in ipairs(Restrictions.GLOBALS) do
            local value = _G[key]
            if type(value) == "string" and not isSecret(value) then G[key] = value end
        end
        -- PVP_RANK_5_0 to PVP_RANK_19_1, both sides' names. AtlasLoot reads them the same way
        G.PVP_RANKS = {}
        for rank = 1, 30 do
            for side = 0, 1 do
                local value = rawget(_G, "PVP_RANK_" .. rank .. "_" .. side)
                if type(value) == "string" and not isSecret(value) and value ~= "" then
                    G.PVP_RANKS[#G.PVP_RANKS + 1] = value
                    rankOf[value] = rank
                end
            end
        end
        for standing = 1, 8 do
            for _, suffix in ipairs({"", "_FEMALE"}) do
                local value = rawget(_G, "FACTION_STANDING_LABEL" .. standing .. suffix)
                if type(value) == "string" and not isSecret(value) then standingOf[value] = standing end
            end
        end
        local lineTypes = Enum and Enum.TooltipDataLineType
        local client = Restrictions.BuildPatterns(G, lineTypes)
        englishSet = Restrictions.BuildPatterns(Restrictions.ENGLISH)
        patternSets = {client}
        -- FDJ's tip is English
        local english = GetLocale and GetLocale() == "enUS"
        Items.tipPatterns = english and {client} or {client, englishSet}
    end
    return patternSets
end

local function buildWork() return firstHead <= #buildFirst or buildHead <= #buildLater end

local changePending, pendingSince, lastChange = false, 0, 0

local function notify()
    changePending = false
    timing.redraws = timing.redraws + 1
    if not timing.loadDone and timing.loadStarted and Items.Pending() == 0 and not buildWork() then timing.loadDone = GetTime() end
    for _, fn in ipairs(listeners) do ns.Guard(fn) end
end

local function flushChange()
    local now = GetTime()
    local quiet = now - lastChange
    if (quiet < REDRAW_DELAY or buildWork()) and now - pendingSince < REDRAW_MAX_WAIT then
        return C_Timer.After(math.max(0.05, REDRAW_DELAY - quiet), flushChange)
    end
    notify()
end

local function scheduleChange()
    lastChange = GetTime()
    if changePending then return end
    changePending, pendingSince = true, lastChange
    C_Timer.After(REDRAW_DELAY, flushChange)
end

-- never inside the event that loaded the data
function Items.OnChange(fn) listeners[#listeners + 1] = fn end

local buildSlice

local function scheduleBuild()
    if buildScheduled or paused or not buildWork() then return end
    buildScheduled = true
    C_Timer.After(0, buildSlice)
end

-- an item doesn't change within a session: once built in full it stays, even when the client drops it from its cache.
-- asking again would never end, the client holds fewer items than FLF lists. one from the saved cache is brought up to
-- date by the first answer only
local refreshed = {}
local function complete(info)
    return info ~= nil and info.loaded and info.tooltipLoaded and not info.partial and (not info.fromCache or refreshed[info.id])
end

local function markDirty(id)
    if dirty[id] then return end
    dirty[id] = true
    if not deferred then return end
    local list = hurry[id] and buildFirst or buildLater
    list[#list + 1] = id
    scheduleBuild()
end

local function tooltipLines(id)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    if not ok or type(data) ~= "table" or isSecret(data) or type(data.lines) ~= "table" then return nil end
    local lines = {}
    for _, line in ipairs(data.lines) do
        local left, right = line.leftText, line.rightText
        if isSecret(left) then left = nil end
        if isSecret(right) then right = nil end
        local lineType = line.type
        if isSecret(lineType) then lineType = nil end
        lines[#lines + 1] = {leftText = left, rightText = right, type = lineType}
    end
    if #lines < 2 then return nil end
    local first = lines[1].leftText
    if not first or first == "" or (RETRIEVING_ITEM_INFO and first == RETRIEVING_ITEM_INFO) then return nil end
    return lines
end

local function retryTooltip(id)
    local tries = (tooltipTries[id] or 0) + 1
    tooltipTries[id] = tries
    if tries > TOOLTIP_RETRIES then return false end
    C_Timer.After(TOOLTIP_RETRY_DELAY, function()
        markDirty(id)
        scheduleChange()
    end)
    return true
end

local function applyParsed(info, parsed)
    info.classes, info.races = parsed.classes, parsed.races
    -- not a specialization or riding
    local skill = parsed.reqSkill
    local profession = skill and ns.Crafts and ns.Crafts.ProfessionByName(skill.name)
    info.reqSkill = profession and {id = profession, name = skill.name, rank = skill.rank} or nil
    info.unique = parsed.unique
    info.pvpRank = parsed.pvpRank and rankOf[parsed.pvpRank] or nil
    info.reqReputation = parsed.reqReputation
    info.reqStanding = parsed.reqStanding and standingOf[parsed.reqStanding] or nil
    info.speed, info.dps = parsed.speed, info.dps or parsed.dps
    info.hasUse, info.hasProc = parsed.hasUse or nil, parsed.hasProc or nil
    info.cosmetic = info.cosmetic or parsed.cosmetic or nil
    info.setName, info.setTotal = parsed.setName, parsed.setTotal
    info.setBonuses = parsed.setBonuses and #parsed.setBonuses > 0 and parsed.setBonuses or nil
end

local function buildFromFDJ(record, info)
    info.slot, info.itemType = Index.FromSlotText(record.slotText)
    info.name, info.quality = record.name, record.quality
    info.icon = UNKNOWN_ICON
    info.notInGame = true
    if record.tip then
        patterns()
        local parsed = Restrictions.ParseLines(Restrictions.TipLines(record.tip), Items.tipPatterns)
        applyParsed(info, parsed)
        info.minLevel = parsed.minLevel or 1
        info.bind = parsed.bind
        info.tooltipLoaded = true
    end
end

local function instant(record, info)
    local ok, itemID, _, _, equipLoc, icon, classID, subclassID = pcall(C_Item.GetItemInfoInstant, record.id)
    if ok and itemID then
        info.icon = icon
        info.slot = Index.SlotFromEquipLoc(equipLoc)
        info.itemType = Index.TypeFromClass(classID, subclassID, equipLoc)
    else
        info.slot, info.itemType = Index.FromSlotText(record.slotText)
        info.icon = UNKNOWN_ICON
    end
end

-- quick: no tooltip, the builder reads it later
local function build(record, quick)
    local info = {id = record.id}
    local id = record.id
    if not id or id <= 0 then
        buildFromFDJ(record, info)
        return info
    end
    instant(record, info)
    info.failed = failed[id]
    -- GetItemInfo asks the server again for anything the client lacks, and an item the server doesn't know answers
    -- "no" every time: that never ends
    if failed[id] or gaveUp[id] then
        info.name, info.quality = record.name, record.quality
        info.missing = failed[id] and "failed" or "noanswer"
        return info
    end
    -- not loaded yet, or dropped again: the request queue asks, the answer builds it
    if clientHas(id) == false then
        info.name, info.quality = record.name, record.quality
        return info
    end
    local name, link, quality, ilvl, minLevel, _, _, _, _, texture, _, _, _, bindType, _, setID = C_Item.GetItemInfo(id)
    if name and not isSecret(name) then
        markDone(seen, id)
        info.loaded = true
        info.name, info.link, info.quality, info.ilvl = name, link, quality, ilvl
        info.minLevel = (type(minLevel) == "number" and minLevel > 0) and minLevel or 1
        info.icon = texture or info.icon
        info.bind = BIND[bindType]
        info.setID = (type(setID) == "number" and setID > 0) and setID or nil
        -- the tooltip's "Cosmetic" line covers clients without the flag
        if C_Item.IsCosmeticItem then
            local cosmeticOk, cosmetic = pcall(C_Item.IsCosmeticItem, link or id)
            if cosmeticOk and cosmetic == true then info.cosmetic = true end
        end
        local statsOk, raw = pcall(C_Item.GetItemStats, link or ("item:" .. id))
        info.stats, info.otherStats = StatMap.Convert(statsOk and raw or nil)
        -- ~12k items: a field less often halves the table
        if next(info.otherStats) == nil then info.otherStats = nil end
        if info.stats.DPS then info.dps = info.stats.DPS end
        if quick and info.slot then
            info.partial = true
        elseif info.slot then
            patterns()
            local clock = Util.Clock()
            local lines = tooltipLines(id)
            if lines then
                applyParsed(info, Restrictions.ParseLines(lines, patternSets))
                info.tooltipLoaded = true
            elseif not retryTooltip(id) then
                -- better than greyed out for good
                info.tooltipLoaded = true
                info.tooltipMissing = true
            end
            timing.tooltipMs = timing.tooltipMs + (Util.Clock() - clock)
        end
        if not info.unique and C_Item.GetItemUniquenessByID then
            local uOk, isUnique = pcall(C_Item.GetItemUniquenessByID, id)
            if uOk and isUnique == true then info.unique = "unique" end
        end
    else
        info.name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or nil
        if isSecret(info.name) then info.name = nil end
        info.quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) or nil
        if isSecret(info.quality) then info.quality = nil end
    end
    info.name = info.name or record.name
    info.quality = info.quality or record.quality
    -- only the server can tell whether an item exists on Forever
    if not info.loaded then info.missing = failed[id] and "failed" or gaveUp[id] and "noanswer" or nil end
    return info
end

local function fromCache(record)
    local text = ns.Cache and ns.Cache.Get(record.id)
    if not text then return nil end
    local info = {id = record.id}
    instant(record, info)
    if not info.slot then return nil end
    ns.Cache.Decode(text, info)
    info.fromCache = true
    return info
end

-- changed data means the Pawn values are stale too
local function keep(id, info)
    if not (ns.Cache and id and id > 0) then return end
    if failed[id] then return ns.Cache.Remove(id) end
    if ns.Cache.Put(id, info) == "changed" and ns.Pawn then ns.Pawn.Forget(id) end
end

function Items.Info(record, now)
    local id = record.id
    local info = cache[record.key]
    if info and not (id and dirty[id]) and not (now and info.partial) then return info end
    -- stale: the old data serves until the builder gets to it
    if info and deferred and not now then return info end
    if not info and id and id > 0 and not failed[id] and not now and (deferred or not dirty[id]) then
        info = fromCache(record)
        if info then
            ns.Cache.stats.hits = ns.Cache.stats.hits + 1
            cache[record.key] = info
            return info
        end
        if ns.Cache and ns.Cache.Loaded() then ns.Cache.stats.misses = ns.Cache.stats.misses + 1 end
    end
    local quick = deferred and not now and not info
    if id then dirty[id] = nil end
    local old = info
    local clock = Util.Clock()
    info = build(record, quick)
    if quick then
        timing.quick = timing.quick + 1
    else
        timing.builds, timing.buildMs = timing.builds + 1, timing.buildMs + (Util.Clock() - clock)
    end
    if info.partial then markDirty(id) end
    if old and old.loaded and not info.loaded and not failed[id] then
        -- evicted from the client cache: keep what we had, ask again only if it wasn't finished
        if not complete(old) then Items.Refetch(id) end
        return old
    end
    if not info.partial then keep(id, info) end
    cache[record.key] = info
    return info
end

local function nextBuild()
    while firstHead <= #buildFirst do
        local id = buildFirst[firstHead]
        firstHead = firstHead + 1
        if dirty[id] then return id end
    end
    wipe(buildFirst)
    firstHead = 1
    while buildHead <= #buildLater do
        local id = buildLater[buildHead]
        buildHead = buildHead + 1
        if dirty[id] then return id end
    end
    wipe(buildLater)
    buildHead = 1
    return nil
end

buildSlice = function()
    buildScheduled = false
    if paused then return end
    local burst = firstHead <= #buildFirst
    local left = math.min(Util.BackgroundLeft(burst), burst and BURST_BUILD_MS or BUILD_MS)
    if left > 0 then
        local clock = Util.Clock()
        local built = 0
        repeat
            local id = nextBuild()
            if not id then break end
            local record = recordOf[id]
            if record then
                ns.Guard(Items.Info, record, true)
                built = built + 1
            end
            dirty[id] = nil
        until Util.Clock() - clock >= left
        local spent = Util.Clock() - clock
        Util.BackgroundUsed(spent)
        timing.slices = timing.slices + 1
        timing.longestSlice = math.max(timing.longestSlice, spent)
        if built > 0 then scheduleChange() end
    end
    scheduleBuild()
end
Items.BuildSlice = function() return ns.Guard(buildSlice) end

function Items.Track(index)
    wipe(tracked)
    wipe(recordOf)
    trackedCount, doneCount = 0, 0
    for _, record in ipairs(index.records) do
        local id = record.id
        if id and id > 0 and not tracked[id] then
            tracked[id] = true
            recordOf[id] = record
            trackedCount = trackedCount + 1
            if isDone(id) then doneCount = doneCount + 1 end
        end
    end
end

function Items.Tracked() return trackedCount > 0 and tracked or nil end
-- for the memory line of /flf dump status
function Items.Tables() return {info = cache, tracked = tracked, records = recordOf, queue = queue} end

local urgent, inUrgent, urgentHead = {}, {}, 1 -- what's on screen jumps the queue, in its order

-- has something to show already: built this session, or saved in the cache
local function hasData(record)
    local info = cache[record.key]
    if info and info.loaded then return true end
    return ns.Cache ~= nil and ns.Cache.Get(record.id) ~= nil
end

-- isUrgent: the category shown (a slot, a tab's cards, the favourites). items with nothing to show go first, then the
-- cached ones, which the answer brings up to date, then the ones the server didn't give last time. each keeps the
-- order it came in (card by card)
function Items.Request(records, isUrgent)
    started = true
    timing.loadStarted = timing.loadStarted or GetTime()
    -- the newest view wins, what it replaced waits till it's shown again
    if isUrgent then
        wipe(hurry)
        wipe(buildFirst)
        wipe(urgent)
        wipe(inUrgent)
        firstHead, urgentHead = 1, 1
        if ns.Pawn and ns.Pawn.ResetWaiting then ns.Pawn.ResetWaiting() end
    end
    local later, last = {}, {}
    for _, record in ipairs(records) do
        local id = record.id
        if id and id > 0 then
            -- a favourite no addon lists isn't in the index, its answer still has to find it
            if not tracked[id] then
                tracked[id], recordOf[id] = true, record
                trackedCount = trackedCount + 1
                if isDone(id) then doneCount = doneCount + 1 end
            end
            if isUrgent then
                hurry[id] = true
                if dirty[id] and deferred then buildFirst[#buildFirst + 1] = id end
                refetches[id] = nil
            end
            if requested[id] then
            elseif isUrgent then
                -- each view asks again
                if not inUrgent[id] then
                    inUrgent[id] = true
                    if unavailable(id) then
                        last[#last + 1] = id
                    elseif hasData(record) then
                        later[#later + 1] = id
                    else
                        urgent[#urgent + 1] = id
                    end
                end
            elseif not queued[id] then
                queued[id] = true
                queue[#queue + 1] = id
            end
        end
    end
    for _, id in ipairs(later) do urgent[#urgent + 1] = id end
    -- the server didn't give these last time: after everything else, so they don't hold the others up
    for _, id in ipairs(last) do urgent[#urgent + 1] = id end
    scheduleBuild()
    if wake then wake() end
end

local head = 1
local function nextID()
    while urgentHead <= #urgent do
        local id = urgent[urgentHead]
        urgentHead = urgentHead + 1
        inUrgent[id] = nil
        if not requested[id] then return id end
    end
    wipe(urgent)
    urgentHead = 1
    if head <= #queue then
        head = head + 1
        return queue[head - 1]
    end
    return nil
end

-- the answer builds it right away: a build later may find the client has dropped it again
local function built(id)
    local record = recordOf[id]
    if not record then return end
    dirty[id] = true
    ns.Guard(Items.Info, record, true)
    if ns.Pawn and ns.Pawn.ItemReady then ns.Guard(ns.Pawn.ItemReady, id) end
end

-- once more for an item the client dropped before it was finished (or Pawn could read it). one the server didn't
-- answer earlier may still show from the cache, it's worth asking again
function Items.Refetch(id)
    if not tracked[id] or failed[id] or askedAt[id] then return end
    local record = recordOf[id]
    if gaveUp[id] and not (record and cache[record.key] and cache[record.key].loaded) then return end
    local count = refetches[id] or 0
    if count >= REFETCHES then return end
    refetches[id] = count + 1
    refetchQueue[#refetchQueue + 1] = id
    if wake then wake() end
end

local function nextRefetch()
    while refetchHead <= #refetchQueue do
        local id = refetchQueue[refetchHead]
        refetchHead = refetchHead + 1
        if not askedAt[id] then return id end
    end
    wipe(refetchQueue)
    refetchHead = 1
    return nil
end

local function step()
    if paused then return end
    local left = Util.BackgroundLeft(urgentHead <= #urgent)
    if left <= 0 then return end
    local clock = Util.Clock()
    local sent = 0
    while sent < MAX_REQUESTS and inFlight < MAX_IN_FLIGHT and Util.Clock() - clock < left do
        -- a refetch is for something on screen that needs it now (Pawn, or a row that lost its data): first
        local id = nextRefetch()
        if id then
            sent = sent + 1
            if clientHas(id) then
                built(id)
                scheduleChange()
            else
                ask(id)
            end
        else
            id = nextID()
            if not id then break end
            if not requested[id] then
                requested[id] = true
                sent = sent + 1
                if clientHas(id) ~= false and C_Item.GetItemInfo(id) then
                    markDone(seen, id)
                    built(id)
                    scheduleChange()
                else
                    asks[id] = 1
                    ask(id)
                end
            end
        end
    end
    if head > #queue then
        wipe(queue)
        head = 1
    end
    local spent = Util.Clock() - clock
    Util.BackgroundUsed(spent)
    timing.requests, timing.requestMs = timing.requests + sent, timing.requestMs + spent
end
Items.Step = step

-- give up after a few tries so the progress can finish
local lastCheck = 0
local function checkWaiting()
    local now = GetTime()
    if now - lastCheck < CHECK_EVERY then return end
    lastCheck = now
    local changed = false
    -- recounted, so a count that ever drifted can't hold back every request after it
    local count = 0
    for _ in pairs(askedAt) do count = count + 1 end
    if count ~= inFlight then
        timing.recounts = (timing.recounts or 0) + 1
        inFlight = count
    end
    for id, at in pairs(askedAt) do
        local known = unavailable(id)
        if failed[id] or gaveUp[id] then
            settle(id)
        elseif now - at > (known and UNAVAILABLE_TIMEOUT or ANSWER_TIMEOUT) then
            if clientHas(id) then
                markDone(seen, id)
                settle(id)
                built(id)
                changed = true
            elseif (asks[id] or 1) >= (known and UNAVAILABLE_TRIES or ANSWER_TRIES) then
                -- a refetch of an item seen before isn't given up: it just stays as it was
                if not seen[id] then markDone(gaveUp, id) end
                settle(id)
                markDirty(id)
                changed = true
            else
                asks[id] = (asks[id] or 1) + 1
                ask(id)
            end
        end
    end
    if changed then scheduleChange() end
end
Items.CheckWaiting = function()
    lastCheck = -math.huge
    checkWaiting()
end

function Items.OnItemInfo(id, success)
    if isSecret(id) or type(id) ~= "number" or not tracked[id] then return end
    settle(id)
    -- someone else asked for an item already built (another addon, or the client refilling its cache)
    local record = recordOf[id]
    local info = record and cache[record.key]
    if success ~= false and info and info.fromCache and info.loaded and not refreshed[id] then
        -- from the saved cache: this answer brings it up to date, later ones are ignored
        refreshed[id] = true
    elseif success ~= false and complete(info) then
        timing.ignored = timing.ignored + 1
        if not seen[id] then
            markDone(seen, id)
            failed[id], gaveUp[id] = nil, nil
        end
        if ns.Pawn and ns.Pawn.ItemReady then ns.Guard(ns.Pawn.ItemReady, id) end
        return
    end
    -- the server said so already
    if success == false and failed[id] then
        timing.ignored = timing.ignored + 1
        return
    end
    if success == false then
        if seen[id] then return end
        markDone(failed, id)
        gaveUp[id] = nil
        markDirty(id)
    else
        markDone(seen, id)
        failed[id], gaveUp[id] = nil, nil
        built(id)
    end
    scheduleChange()
end

function Items.Progress() return doneCount, trackedCount end

-- for /flf dump pawn: where an item is in loading
function Items.Diagnose(id)
    local hasIt = "no API"
    if C_Item.IsItemDataCachedByID then
        local ok, result = pcall(C_Item.IsItemDataCachedByID, id)
        if ok then
            hasIt = tostring(result)
        else
            hasIt = "error"
        end
    end
    return {
        state = (Items.LoadState(id)),
        client = hasIt,
        refetches = refetches[id] or 0,
        waiting = askedAt[id] ~= nil,
        requested = requested[id] == true,
        urgent = inUrgent[id] == true,
        tracked = tracked[id] == true,
    }
end

-- what's asked for and not in yet: the status line's "loading"
function Items.Pending()
    return math.max(0, #urgent - urgentHead + 1) + math.max(0, #queue - head + 1) + inFlight
             + math.max(0, #refetchQueue - refetchHead + 1)
end

-- loaded, failed, noanswer, waiting or queued
function Items.LoadState(id)
    if seen[id] then return "loaded" end
    if failed[id] then return "failed" end
    if gaveUp[id] then return "noanswer" end
    if requested[id] then return "waiting", asks[id] or 0 end
    return "queued"
end

function Items.QueueInfo()
    local toBuild = 0
    for _ in pairs(dirty) do toBuild = toBuild + 1 end
    return {
        queued = math.max(0, #queue - head + 1),
        urgent = math.max(0, #urgent - urgentHead + 1),
        started = started,
        paused = paused,
        toBuild = toBuild,
        inFlight = inFlight,
        recounts = timing.recounts or 0,
        refetches = math.max(0, #refetchQueue - refetchHead + 1),
    }
end

function Items.Waiting()
    local list = {}
    for id in pairs(tracked) do
        if requested[id] and not seen[id] and not failed[id] and not gaveUp[id] then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

function Items.SetPaused(value)
    paused = value and true or false
    if not paused then
        scheduleBuild()
        if wake then wake() end
    end
end

local function busy() return urgentHead <= #urgent or head <= #queue or refetchHead <= #refetchQueue or next(askedAt) ~= nil end

function Items.Init()
    deferred = true
    local frame = CreateFrame("Frame")
    local running = false
    local function onUpdate()
        ns.Guard(step)
        ns.Guard(checkWaiting)
        if not busy() then
            running = false
            frame:SetScript("OnUpdate", nil)
        end
    end
    wake = function()
        if running then return end
        running = true
        frame:SetScript("OnUpdate", onUpdate)
    end
    wake()
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, _, id, success) ns.Guard(Items.OnItemInfo, id, success) end)
    Items.frame = frame
end

function Items.Link(record)
    local info = Items.Info(record)
    if info.link then return info.link end
    if record.id and record.id > 0 then
        local _, link = C_Item.GetItemInfo(record.id)
        if link and not isSecret(link) then return link end
        return "item:" .. record.id
    end
    return nil
end

function Items.InvalidateAll()
    for _, info in pairs(cache) do if info.id then markDirty(info.id) end end
    scheduleChange()
end
