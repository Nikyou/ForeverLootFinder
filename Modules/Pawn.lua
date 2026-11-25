-- the only file that calls Pawn. everything in pcall, Pawn prints chat errors on misuse. GearQuest Forever's
-- weights come in as more scales ("gq:<spec>", Modules/GearQuest.lua), after Pawn's
local _, ns = ...

local Pawn = {}
ns.Pawn = Pawn

local Util = ns.Util

local STEP_MS = 3 -- each value is a hidden tooltip scan inside Pawn

-- [scale][id] = number or false. the inner tables are Core/Cache.lua's when it's loaded
local values = {}
local signatures = {}
local slotValues = {} -- [scale][invSlot], false = empty
-- a stack, so the list on screen comes first. an id asked again moves up and leaves false behind
local queue, position, live = {}, {}, 0
-- the other slots' items, for their counts: only once the stack above is empty, in the order asked
local later, laterHead, inLater = {}, 1, {}
-- Pawn had nothing for these a few times this session (often not in the client's cache): left alone till next login
local LATER_TRIES, LATER_RETRY = 3, 2
local laterTries, noValue = {}, {}
-- the other slots' items the client doesn't have: not queued again till ItemReady
local waiting = {}
local paused = false
local listeners = {}
local changePending = false
Pawn.timing = {count = 0, ms = 0, lastPassMs = nil, longestFrame = 0, fromCache = 0}

local isSecret = Util.IsSecret

local function call(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return false end
    local result = {pcall(fn, ...)}
    if not result[1] then return false end
    return true, unpack(result, 2)
end

function Pawn.IsInstalled() return ns.Util.AddOnLoaded("Pawn") end

-- Pawn sets itself up on PLAYER_LOGIN
local function pawnReady()
    if not Pawn.IsInstalled() then return false end
    local ok, ready = call("PawnIsReady")
    return ok and ready == true
end

-- a scale to score with: GearQuest's only without Pawn. an installed Pawn is waited for, or the scale picked in it
-- would be swapped for GearQuest's before Pawn has set itself up
function Pawn.IsReady()
    if Pawn.IsInstalled() then return pawnReady() end
    return ns.GearQuest.Installed()
end

local function isGearQuest(scale) return ns.GearQuest.IsScale(scale) end

function Pawn.Exists(scale)
    if isGearQuest(scale) then return ns.GearQuest.Exists(scale) end
    if type(scale) ~= "string" or scale == "" or not pawnReady() then return false end
    local ok, exists = call("PawnDoesScaleExist", scale)
    return ok and exists == true
end

-- Pawn's first, visible ones first as Pawn sorts them, then GearQuest's
function Pawn.Scales()
    local list = {}
    local ok, scales = false, nil
    if pawnReady() then ok, scales = call("PawnGetAllScalesEx") end
    for _, scale in ipairs(ok and type(scales) == "table" and scales or {}) do
        if type(scale) == "table" and type(scale.Name) == "string" then
            list[#list + 1] = {
                name = scale.Name,
                label = type(scale.LocalizedName) == "string" and scale.LocalizedName or scale.Name,
                header = type(scale.Header) == "string" and scale.Header or nil,
                visible = scale.IsVisible == true,
            }
        end
    end
    for _, scale in ipairs(ns.GearQuest.Scales()) do list[#list + 1] = scale end
    return list
end

-- with nothing picked: a scale Pawn shows, else the spec GearQuest goes by
function Pawn.Resolve(saved)
    if saved and Pawn.Exists(saved) then return saved end
    local scales = Pawn.Scales()
    for _, scale in ipairs(scales) do
        if scale.visible and not isGearQuest(scale.name) then return scale.name end
    end
    local gearQuest = ns.GearQuest.Default()
    if gearQuest then return gearQuest end
    return scales[1] and scales[1].name or nil
end

function Pawn.Color(scale)
    if isGearQuest(scale) then return ns.GearQuest.COLOR end
    if not Pawn.Exists(scale) then return "|cff8ec3e6" end
    local ok, color = call("PawnGetScaleColor", scale)
    if ok and type(color) == "string" and not isSecret(color) then return color end
    return "|cff8ec3e6"
end

function Pawn.Label(scale)
    if isGearQuest(scale) then return ns.GearQuest.Label(scale) end
    if not Pawn.Exists(scale) then return scale end
    local ok, label = call("PawnGetScaleLocalizedName", scale)
    return ok and type(label) == "string" and label or scale
end

-- base value, drops have no enchants
local function valueOf(item, scale)
    local ok, value, unenchanted = call("PawnGetSingleValueFromItem", item, scale)
    if not ok then return nil end
    local result = unenchanted or value
    if type(result) ~= "number" or isSecret(result) then return nil end
    return result
end

-- Pawn reads the item through a tooltip, which asks the server again for one the client doesn't have
local function clientHas(id)
    if not C_Item.IsItemDataCachedByID then return true end
    local ok, result = pcall(C_Item.IsItemDataCachedByID, id)
    return not ok or result == true
end

-- nil: not scored yet (the client lacks it, or Pawn got nothing). false: no stats to score
function Pawn.Compute(id, scale)
    if not Pawn.Exists(scale) then return nil end
    if not clientHas(id) then return nil, "uncached" end
    if isGearQuest(scale) then return ns.GearQuest.Value(id, scale) end
    local ok, item = call("PawnGetItemData", "item:" .. id)
    if not ok then return nil end
    if type(item) ~= "table" then
        -- cached and still nothing: no stats
        if C_Item.GetItemInfo(id) then return false end
        return nil
    end
    return valueOf(item, scale) or false
end

-- changes with the weights, the normalization or Pawn's version, so saved values of an edited scale aren't used
local function hash(text)
    local h = 5381
    -- %x takes a 32-bit long on Windows
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
    return format("%d-%08x", #text, h)
end

function Pawn.Signature(scale)
    if not Pawn.Exists(scale) then return nil end
    if isGearQuest(scale) then
        local text = ns.GearQuest.SignatureText(scale)
        return text and hash(text) or nil
    end
    local ok, weights = call("PawnGetAllStatValues", scale)
    if not ok or type(weights) ~= "table" then return nil end
    local keys = {}
    for key, value in pairs(weights) do
        if type(key) == "string" and type(value) == "number" and not isSecret(value) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local parts = {}
    for i, key in ipairs(keys) do parts[i] = key .. "=" .. weights[key] end
    -- read only, Pawn has no getter for the normalization
    local common = rawget(_G, "PawnCommon")
    local options = type(common) == "table" and type(common.Scales) == "table" and common.Scales[scale]
    if type(options) == "table" and type(options.NormalizationFactor) == "number" then
        parts[#parts + 1] = "norm=" .. options.NormalizationFactor
    end
    parts[#parts + 1] = "pawn=" .. tostring(rawget(_G, "PawnVersion"))
    return hash(table.concat(parts, ";"))
end

local function scaleValues(scale)
    local byScale = values[scale]
    if byScale then return byScale end
    local signature = Pawn.Signature(scale)
    byScale = ns.Cache and ns.Cache.PawnValues(scale, signature) or {}
    for _ in pairs(byScale) do Pawn.timing.fromCache = Pawn.timing.fromCache + 1 end
    values[scale], signatures[scale] = byScale, signature
    return byScale
end

local function compact()
    local kept = {}
    for _, job in ipairs(queue) do
        if job then
            kept[#kept + 1] = job
            position[job.key] = #kept
        end
    end
    queue = kept
end

local function want(id, scale)
    local key = scale .. ":" .. id
    local at = position[key]
    if at and at == #queue then return end
    local job
    if at then
        job = queue[at]
        queue[at] = false
    else
        job = {id = id, scale = scale, key = key}
        live = live + 1
    end
    queue[#queue + 1] = job
    position[key] = #queue
    if #queue > 2 * live + 64 then compact() end
end

local function pop()
    while #queue > 0 do
        local job = table.remove(queue)
        if job then
            position[job.key] = nil
            live = live - 1
            return job
        end
    end
    return nil
end

-- nil: not known yet, now queued
function Pawn.Lookup(id, scale)
    if not id or id <= 0 or not scale then return nil end
    local value = scaleValues(scale)[id]
    -- one Pawn couldn't read waits for its data (ItemReady) or the next view, it isn't queued on every redraw
    if value == nil and not waiting[scale .. ":" .. id] then want(id, scale) end
    return value
end

-- a slot or tab opened: what waited is tried again
function Pawn.ResetWaiting() wipe(waiting) end

function Pawn.Value(id, scale) return Pawn.Lookup(id, scale) or nil end

-- like Lookup, but an unknown value waits behind everything Lookup asked for
function Pawn.Peek(id, scale)
    if not id or id <= 0 or not scale then return nil end
    local value = scaleValues(scale)[id]
    if value == nil then
        local key = scale .. ":" .. id
        if noValue[key] then return false end
        if not position[key] and not inLater[key] and not waiting[key] then
            inLater[key] = true
            later[#later + 1] = {id = id, scale = scale, key = key}
        end
    end
    return value
end

local function popLater()
    while laterHead <= #later do
        local job = later[laterHead]
        laterHead = laterHead + 1
        inLater[job.key] = nil
        if scaleValues(job.scale)[job.id] == nil then return job end
    end
    wipe(later)
    laterHead = 1
    return nil
end

local function pending() return live > 0 or laterHead <= #later end


function Pawn.Tables() return {values = values} end

function Pawn.Forget(id)
    for _, byScale in pairs(values) do byScale[id] = nil end
    if ns.Cache then ns.Cache.ForgetPawn(id) end
end

function Pawn.SlotValue(invSlot, scale)
    if not Pawn.Exists(scale) then return nil end
    slotValues[scale] = slotValues[scale] or {}
    local cached = slotValues[scale][invSlot]
    if cached ~= nil then return cached end
    local link = GetInventoryItemLink("player", invSlot)
    if not link or isSecret(link) then
        slotValues[scale][invSlot] = false
        return false
    end
    if isGearQuest(scale) then
        local value = ns.GearQuest.SlotValue(link, scale)
        if value ~= nil then slotValues[scale][invSlot] = value end
        return value
    end
    local ok, item = call("PawnGetItemDataForInventorySlot", invSlot, true)
    if not ok then return nil end
    -- nothing Pawn can score (a trinket with only a "Use:") is worth 0, not "not scored yet": every trinket
    -- would wait on it for good
    if type(item) ~= "table" then
        if C_Item.GetItemInfo(link) then return 0 end
        return nil
    end
    local value = valueOf(item, scale) or 0
    slotValues[scale][invSlot] = value
    return value
end

local function notify()
    changePending = false
    for _, fn in ipairs(listeners) do ns.Guard(fn) end
end

function Pawn.OnChange(fn) listeners[#listeners + 1] = fn end

-- two decimals are plenty and keep the saved file small
local function round(value)
    if type(value) ~= "number" then return value end
    return math.floor(value * 100 + 0.5) / 100
end

-- the item loader just got it: score it for the scales in use while the client surely has it
local READY_TRIES, READY_RETRY = 4, 0.5
local readyTries = {}

-- Pawn reads a tooltip, and its lines can come a moment after the item's data: a few more tries then
function Pawn.ItemReady(id)
    if not Pawn.IsReady() then return end
    local any, missing = false, false
    for scale in pairs(signatures) do
        local byScale = scaleValues(scale)
        if byScale[id] == nil and Pawn.Exists(scale) then
            local value = Pawn.Compute(id, scale)
            if value ~= nil then
                byScale[id] = round(value)
                noValue[scale .. ":" .. id] = nil
                waiting[scale .. ":" .. id] = nil
                any = true
            else
                missing = true
            end
        end
    end
    if missing then
        local tries = (readyTries[id] or 0) + 1
        readyTries[id] = tries
        if tries < READY_TRIES then C_Timer.After(READY_RETRY, function() ns.Guard(Pawn.ItemReady, id) end) end
    else
        readyTries[id] = nil
    end
    if any and not changePending then
        changePending = true
        C_Timer.After(0.5, notify)
    end
end

-- for /flf dump pawn, no side effects
function Pawn.Known(id, scale) return scale and values[scale] and values[scale][id] end
function Pawn.ReadyTries(id) return readyTries[id] or 0 end
function Pawn.Waiting(id, scale) return scale ~= nil and waiting[scale .. ":" .. id] == true end

local passStart
function Pawn.Step()
    if paused or not pending() then return end
    local left = math.min(Util.BackgroundLeft(), STEP_MS)
    if left <= 0 then return end
    local clock = Util.Clock()
    passStart = passStart or clock
    local stored = 0
    repeat
        local job = pop()
        local fromLater = false
        if not job then
            job, fromLater = popLater(), true
        end
        if not job then break end
        local started = Util.Clock()
        local value, why = Pawn.Compute(job.id, job.scale)
        Pawn.timing.count = Pawn.timing.count + 1
        Pawn.timing.ms = Pawn.timing.ms + (Util.Clock() - started)
        if value ~= nil then
            scaleValues(job.scale)[job.id] = round(value)
            stored = stored + 1
        elseif why == "uncached" then
            -- the shown slot's: the item loader fetches it (within its limits). the other slots' wait till they're shown
            -- or the client has them anyway. ItemReady scores it then
            waiting[job.key] = true
            if not fromLater and ns.Items and ns.Items.Refetch then ns.Items.Refetch(job.id) end
        elseif not fromLater then
            -- the client has it but Pawn got nothing: its tooltip may be a moment behind
            waiting[job.key] = true
            local id = job.id
            C_Timer.After(READY_RETRY, function() ns.Guard(Pawn.ItemReady, id) end)
        else
            laterTries[job.key] = (laterTries[job.key] or 0) + 1
            if laterTries[job.key] >= LATER_TRIES then
                noValue[job.key] = true
            else
                -- the client may have it by then
                C_Timer.After(LATER_RETRY, function() Pawn.Peek(job.id, job.scale) end)
            end
        end
    until Util.Clock() - clock >= left
    local spent = Util.Clock() - clock
    Util.BackgroundUsed(spent)
    Pawn.timing.longestFrame = math.max(Pawn.timing.longestFrame, spent)
    if live == 0 then wipe(queue) end
    if not pending() then
        Pawn.timing.lastPassMs = Util.Clock() - passStart
        passStart = nil
    end
    -- only new values redraw: a redraw asks again, and nothing new would only go round
    if stored > 0 and not changePending then
        changePending = true
        C_Timer.After(pending() and 1 or 0.3, notify)
    end
end

function Pawn.IsBusy() return pending() end
function Pawn.QueueLength() return live + math.max(0, #later - laterHead + 1) end
function Pawn.SetPaused(value) paused = value and true or false end

local function cleared()
    if ns.Owned then ns.Owned.InvalidateEnv() end
    if ns.InvalidateScale then ns.InvalidateScale() end
end

function Pawn.ClearValues()
    wipe(values)
    wipe(signatures)
    if ns.Cache then ns.Cache.ClearPawn() end
    wipe(queue)
    wipe(position)
    wipe(later)
    wipe(inLater)
    wipe(laterTries)
    wipe(noValue)
    wipe(waiting)
    live, laterHead = 0, 1
    cleared()
end

function Pawn.ClearEquipped()
    wipe(slotValues)
    cleared()
end

-- Pawn has no event for edited weights
function Pawn.CheckScales()
    local changed = false
    for scale, signature in pairs(signatures) do
        if Pawn.Signature(scale) ~= signature then
            values[scale], signatures[scale] = nil, nil
            changed = true
        end
    end
    if changed then
        wipe(laterTries)
        wipe(noValue)
        wipe(waiting)
        cleared()
    end
    return changed
end

function Pawn.ScalesInUse()
    local list = {}
    for scale, byScale in pairs(values) do
        local count = 0
        for _ in pairs(byScale) do count = count + 1 end
        list[#list + 1] = {scale = scale, signature = signatures[scale], values = count}
    end
    table.sort(list, function(a, b) return a.scale < b.scale end)
    return list
end

function Pawn.Init()
    local frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function() if pending() then ns.Guard(Pawn.Step) end end)
    Pawn.frame = frame
end
