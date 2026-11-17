-- the only file that calls Pawn. everything in pcall, Pawn prints chat errors on misuse
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
function Pawn.IsReady()
    if not Pawn.IsInstalled() then return false end
    local ok, ready = call("PawnIsReady")
    return ok and ready == true
end

function Pawn.Exists(scale)
    if type(scale) ~= "string" or scale == "" or not Pawn.IsReady() then return false end
    local ok, exists = call("PawnDoesScaleExist", scale)
    return ok and exists == true
end

-- visible scales first, as Pawn sorts them
function Pawn.Scales()
    local list = {}
    if not Pawn.IsReady() then return list end
    local ok, scales = call("PawnGetAllScalesEx")
    if not ok or type(scales) ~= "table" then return list end
    for _, scale in ipairs(scales) do
        if type(scale) == "table" and type(scale.Name) == "string" then
            list[#list + 1] = {
                name = scale.Name,
                label = type(scale.LocalizedName) == "string" and scale.LocalizedName or scale.Name,
                header = type(scale.Header) == "string" and scale.Header or nil,
                visible = scale.IsVisible == true,
            }
        end
    end
    return list
end

function Pawn.Resolve(saved)
    if saved and Pawn.Exists(saved) then return saved end
    local scales = Pawn.Scales()
    for _, scale in ipairs(scales) do if scale.visible then return scale.name end end
    return scales[1] and scales[1].name or nil
end

function Pawn.Color(scale)
    if not Pawn.Exists(scale) then return "|cff8ec3e6" end
    local ok, color = call("PawnGetScaleColor", scale)
    if ok and type(color) == "string" and not isSecret(color) then return color end
    return "|cff8ec3e6"
end

function Pawn.Label(scale)
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

-- nil: Pawn needs the item cached first
function Pawn.Compute(id, scale)
    if not Pawn.Exists(scale) then return nil end
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
    if value == nil then want(id, scale) end
    return value
end

function Pawn.Value(id, scale) return Pawn.Lookup(id, scale) or nil end

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
    local ok, item = call("PawnGetItemDataForInventorySlot", invSlot, true)
    if not ok or type(item) ~= "table" then return nil end
    local value = valueOf(item, scale)
    if value then slotValues[scale][invSlot] = value end
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

local passStart
function Pawn.Step()
    if paused or live == 0 then return end
    local left = math.min(Util.BackgroundLeft(), STEP_MS)
    if left <= 0 then return end
    local clock = Util.Clock()
    passStart = passStart or clock
    repeat
        local job = pop()
        if not job then break end
        local started = Util.Clock()
        local value = Pawn.Compute(job.id, job.scale)
        Pawn.timing.count = Pawn.timing.count + 1
        Pawn.timing.ms = Pawn.timing.ms + (Util.Clock() - started)
        if value ~= nil then scaleValues(job.scale)[job.id] = round(value) end
    until Util.Clock() - clock >= left
    local spent = Util.Clock() - clock
    Util.BackgroundUsed(spent)
    Pawn.timing.longestFrame = math.max(Pawn.timing.longestFrame, spent)
    if live == 0 then
        wipe(queue)
        Pawn.timing.lastPassMs = Util.Clock() - passStart
        passStart = nil
    end
    if not changePending then
        changePending = true
        C_Timer.After(live > 0 and 1 or 0.3, notify)
    end
end

function Pawn.IsBusy() return live > 0 end
function Pawn.QueueLength() return live end
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
    live = 0
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
    if changed then cleared() end
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
    frame:SetScript("OnUpdate", function() if live > 0 then ns.Guard(Pawn.Step) end end)
    Pawn.frame = frame
end
