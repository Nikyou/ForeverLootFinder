-- shared helpers, loaded first
local _, ns = ...

local Util = {}
ns.Util = Util

-- secret values (instances, combat) can't be compared or read
function Util.IsSecret(value) return issecretvalue ~= nil and issecretvalue(value) end
ns.IsSecret = Util.IsSecret

local function results(ok, ...)
    if ok then return ... end
    return nil
end

-- nil on error, never the error message
function Util.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    return results(pcall(fn, ...))
end

function Util.AddOnLoaded(name)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    local loaded = Util.SafeCall(C_AddOns.IsAddOnLoaded, name)
    return loaded == true or loaded == 1
end

-- GetItemInfoInstant only, no server request
function Util.Equippable(id)
    local itemID, _, _, equipLoc = Util.SafeCall(C_Item.GetItemInfoInstant, id)
    return itemID ~= nil and ns.Index.EQUIP_SLOT[equipLoc] ~= nil
end

-- string.lower only knows ASCII, Russian names need their capitals too
local CYRILLIC = {}
local D0, D1 = string.char(0xD0), string.char(0xD1)
for code = 0x90, 0x9F do CYRILLIC[D0 .. string.char(code)] = D0 .. string.char(code + 0x20) end
for code = 0xA0, 0xAF do CYRILLIC[D0 .. string.char(code)] = D1 .. string.char(code - 0x20) end
CYRILLIC[D0 .. string.char(0x81)] = D1 .. string.char(0x91) -- Ё
local CAPITAL = D0 .. "[" .. string.char(0x80) .. "-" .. string.char(0xAF) .. "]"
function Util.Lower(text)
    if type(text) ~= "string" then return "" end
    return (text:lower():gsub(CAPITAL, CYRILLIC))
end

function Util.ItemIDFromLink(link)
    if type(link) ~= "string" or Util.IsSecret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- strips colours, textures and atlas icons
function Util.StripCodes(text)
    if type(text) ~= "string" or Util.IsSecret(text) then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.Clock() return debugprofilestop and debugprofilestop() or 0 end

-- rough bytes a value keeps alive, for /flf dump status: Lua 5.1 on 64-bit, tables, keys and strings. seen is shared so
-- two parts don't count the same table twice. metatables and functions aren't followed
local function slots(n)
    local size = 1
    while size < n do size = size * 2 end
    return n > 0 and size or 0
end
function Util.SizeOf(root, seen)
    local total, stack = 0, {root}
    while #stack > 0 do
        local value = table.remove(stack)
        local kind = type(value)
        if (kind == "table" or kind == "string") and not seen[value] then
            seen[value] = true
            if kind == "string" then
                total = total + 25 + #value
            else
                local array, hash = #value, 0
                for key, item in pairs(value) do
                    if not (type(key) == "number" and key >= 1 and key <= array and key % 1 == 0) then
                        hash = hash + 1
                        stack[#stack + 1] = key
                    end
                    stack[#stack + 1] = item
                end
                total = total + 56 + 16 * slots(array) + 40 * slots(hash)
            end
        end
    end
    return total
end

local COINS = {
    gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

-- short form for list columns: no copper above 1g, no silver above 100g
function Util.Money(copper, full)
    if type(copper) ~= "number" or copper < 0 or Util.IsSecret(copper) then return "" end
    copper = math.floor(copper + 0.5)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local group = rawget(_G, "BreakUpLargeNumbers")
    local parts = {}
    if gold > 0 then parts[#parts + 1] = (type(group) == "function" and group(gold) or tostring(gold)) .. COINS.gold end
    if silver > 0 and (full or gold < 100) then parts[#parts + 1] = silver .. COINS.silver end
    if (rest > 0 and (full or gold == 0)) or #parts == 0 then parts[#parts + 1] = rest .. COINS.copper end
    return table.concat(parts, " ")
end

function Util.Encode(prefix, payload)
    local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate")
    local compressed = LibDeflate:CompressDeflate(LibSerialize:Serialize(payload), {level = 9})
    return prefix .. LibDeflate:EncodeForPrint(compressed)
end

-- nil plus "empty", "prefix" or "damaged"
function Util.Decode(text, prefix)
    if type(text) ~= "string" then return nil, "empty" end
    text = text:gsub("%s", "")
    if text == "" then return nil, "empty" end
    if text:sub(1, #prefix) ~= prefix then return nil, "prefix" end
    local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate")
    local decoded = LibDeflate:DecodeForPrint(text:sub(#prefix + 1))
    local inflated = decoded and LibDeflate:DecompressDeflate(decoded)
    if not inflated then return nil, "damaged" end
    local ok, payload = LibSerialize:Deserialize(inflated)
    if not ok or type(payload) ~= "table" then return nil, "damaged" end
    return payload
end

Util.FRAME_BUDGET_MS = 6

-- shared per frame by item requests, info builds and Pawn values. GetTime() is constant within a frame.
-- a burst (what's on screen) may take more for the few frames it lasts
Util.BACKGROUND_MS = 6
Util.BURST_MS = 12
local budgetFrame, budgetUsed = nil, 0

function Util.BackgroundLeft(burst)
    local frame = GetTime()
    if frame ~= budgetFrame then budgetFrame, budgetUsed = frame, 0 end
    return (burst and Util.BURST_MS or Util.BACKGROUND_MS) - budgetUsed
end

function Util.BackgroundUsed(ms) budgetUsed = budgetUsed + ms end

-- don't call checkpoint inside a pcall, 5.1 can't yield across it
function Util.RunSliced(fn, done, budget)
    budget = budget or Util.FRAME_BUDGET_MS
    local co = coroutine.create(fn)
    local frameStart, spent = 0, 0
    local function checkpoint() if Util.Clock() - frameStart > budget then coroutine.yield() end end
    local function step()
        if ns.inCombat then return C_Timer.After(1, step) end
        frameStart = Util.Clock()
        local ok, err = coroutine.resume(co, checkpoint)
        spent = spent + (Util.Clock() - frameStart)
        if not ok then return done(false, err, spent) end
        if coroutine.status(co) == "dead" then return done(true, nil, spent) end
        C_Timer.After(0, step)
    end
    step()
end

-- state: off, waiting, scanning, done or nodata
function Util.NewStatus(name, counts) return {name = name, state = "off", error = nil, ms = 0, counts = counts or {}} end
