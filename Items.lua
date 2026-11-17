-- item data, loaded a slice per frame. Cache.lua keeps it between sessions
local _, ns = ...
local Index, Restrictions, StatMap, Util = ns.Index, ns.Restrictions, ns.StatMap, ns.Util

local Items = {}
ns.Items = Items

local MAX_REQUESTS = 40 -- per frame, the server answers at its own pace anyway
local BUILD_MS = 3 -- leaves Pawn its share of the frame
local REDRAW_DELAY = 0.4
local REDRAW_MAX_WAIT = 2 -- during a long burst
local TOOLTIP_RETRIES, TOOLTIP_RETRY_DELAY = 5, 1
local ANSWER_TIMEOUT, ANSWER_TRIES, CHECK_EVERY = 15, 3, 5
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
local buildFirst, buildLater, buildHead = {}, {}, 1
local hurry = {} -- the selected slot's items
local buildScheduled = false

Items.timing = {requests = 0, requestMs = 0, builds = 0, buildMs = 0, tooltipMs = 0, quick = 0, slices = 0, longestSlice = 0,
                redraws = 0, loadStarted = nil, loadDone = nil}
local timing = Items.timing

local isSecret = Util.IsSecret

local function isDone(id) return seen[id] or failed[id] or gaveUp[id] end

-- every way an item becomes done goes through here, or the count drifts
local function markDone(set, id)
    if set[id] then return end
    local was = isDone(id)
    set[id] = true
    if tracked[id] and not was then doneCount = doneCount + 1 end
end

local patternSets, englishSet
local function patterns()
    if not patternSets then
        local G = {}
        for _, key in ipairs(Restrictions.GLOBALS) do
            local value = _G[key]
            if type(value) == "string" and not isSecret(value) then G[key] = value end
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

local function buildWork() return #buildFirst > 0 or buildHead <= #buildLater end

local changePending, pendingSince, lastChange = false, 0, 0

local function notify()
    changePending = false
    timing.redraws = timing.redraws + 1
    if not timing.loadDone and timing.loadStarted and doneCount >= trackedCount and not buildWork() then
        timing.loadDone = GetTime()
    end
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
    info.speed, info.dps = parsed.speed, info.dps or parsed.dps
    info.hasUse, info.hasProc = parsed.hasUse or false, parsed.hasProc or false
    info.cosmetic = info.cosmetic or parsed.cosmetic or nil
    info.setName, info.setTotal, info.setBonuses = parsed.setName, parsed.setTotal, parsed.setBonuses
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
        info.equipLoc, info.icon, info.classID, info.subclassID = equipLoc, icon, classID, subclassID
        info.slot = Index.SlotFromEquipLoc(equipLoc)
        info.itemType = Index.TypeFromClass(classID, subclassID, equipLoc)
    else
        info.slot, info.itemType = Index.FromSlotText(record.slotText)
        info.icon = UNKNOWN_ICON
    end
end

-- quick: no tooltip, the builder reads it later
local function build(record, quick)
    local info = {key = record.key, id = record.id}
    local id = record.id
    if not id or id <= 0 then
        buildFromFDJ(record, info)
        return info
    end
    instant(record, info)
    info.failed = failed[id]
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
    local info = {key = record.key, id = record.id}
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
        -- evicted from the client cache: keep what we had and ask again
        pcall(C_Item.RequestLoadItemDataByID, id)
        return old
    end
    if not info.partial then keep(id, info) end
    cache[record.key] = info
    return info
end

local function nextBuild()
    while #buildFirst > 0 do
        local id = table.remove(buildFirst)
        if dirty[id] then return id end
    end
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
    local left = math.min(Util.BackgroundLeft(), BUILD_MS)
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
    -- Questie and AtlasLoot often finish after the window opened
    if started then Items.Request(index.records) end
end

function Items.Tracked() return trackedCount > 0 and tracked or nil end

local urgent, inUrgent = {}, {} -- the selected slot jumps the queue

function Items.Request(records, isUrgent)
    started = true
    timing.loadStarted = timing.loadStarted or GetTime()
    if isUrgent then wipe(hurry) end
    for _, record in ipairs(records) do
        local id = record.id
        if id and id > 0 then
            if isUrgent then
                hurry[id] = true
                if dirty[id] and deferred then buildFirst[#buildFirst + 1] = id end
            end
            if requested[id] then
            elseif isUrgent then
                -- each slot click asks again
                if not inUrgent[id] then
                    inUrgent[id] = true
                    urgent[#urgent + 1] = id
                end
            elseif not queued[id] then
                queued[id] = true
                queue[#queue + 1] = id
            end
        end
    end
    scheduleBuild()
    if wake then wake() end
end

local function cached(id)
    if C_Item.IsItemDataCachedByID then
        local ok, result = pcall(C_Item.IsItemDataCachedByID, id)
        if ok then return result == true end
    end
    return C_Item.GetItemInfo(id) ~= nil
end

local head = 1
local function nextID()
    while #urgent > 0 do
        local id = table.remove(urgent)
        inUrgent[id] = nil
        if not requested[id] then return id end
    end
    if head <= #queue then
        head = head + 1
        return queue[head - 1]
    end
    return nil
end

local function step()
    if paused then return end
    local left = Util.BackgroundLeft()
    if left <= 0 then return end
    local clock = Util.Clock()
    local sent = 0
    while sent < MAX_REQUESTS and Util.Clock() - clock < left do
        local id = nextID()
        if not id then break end
        if not requested[id] then
            requested[id] = true
            sent = sent + 1
            if cached(id) then
                markDone(seen, id)
                markDirty(id)
                scheduleChange()
            else
                askedAt[id], asks[id] = GetTime(), 1
                -- may fire GET_ITEM_INFO_RECEIVED synchronously, which only marks and schedules
                pcall(C_Item.RequestLoadItemDataByID, id)
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
    for id, at in pairs(askedAt) do
        if seen[id] or failed[id] or gaveUp[id] then
            askedAt[id] = nil
        elseif now - at > ANSWER_TIMEOUT then
            if cached(id) then
                markDone(seen, id)
                markDirty(id)
                askedAt[id] = nil
                changed = true
            elseif (asks[id] or 1) >= ANSWER_TRIES then
                markDone(gaveUp, id)
                markDirty(id)
                askedAt[id] = nil
                changed = true
            else
                asks[id] = (asks[id] or 1) + 1
                askedAt[id] = now
                pcall(C_Item.RequestLoadItemDataByID, id)
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
    if success == false then
        if seen[id] then return end
        markDone(failed, id)
    else
        markDone(seen, id)
        failed[id] = nil
    end
    gaveUp[id] = nil
    markDirty(id)
    scheduleChange()
end

function Items.Progress() return doneCount, trackedCount end

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
    return {queued = math.max(0, #queue - head + 1), urgent = #urgent, started = started, paused = paused, toBuild = toBuild}
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

local function busy() return #urgent > 0 or head <= #queue or next(askedAt) ~= nil end

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
