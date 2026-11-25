-- the only file that calls Auctionator, through API.v1 only. the API raises errors on misuse
local _, ns = ...
local Util = ns.Util

local AH = {}
ns.Auctionator = AH

-- the API names its temporary lists after the caller ID
AH.CALLER = "Forever LootFinder"
AH.SHOPPING_LIST = "Forever LootFinder"
-- the API gives no age past 21 days
AH.OLD_DAYS = 7

local cache = {} -- [itemID] = {price = copper or false, age, exact}
local status = Util.NewStatus("auctionator", {calls = 0, errors = 0, cached = 0})
local hooked = false

local function v1()
    local addon = rawget(_G, "Auctionator")
    local api = type(addon) == "table" and type(addon.API) == "table" and addon.API.v1
    return type(api) == "table" and api or nil
end

function AH.Installed() return Util.AddOnLoaded("Auctionator") and v1() ~= nil end
function AH.Enabled() return ns.addon.db.profile.auctionator ~= false end
function AH.Active() return AH.Installed() and AH.Enabled() end
function AH.State()
    status.state = AH.Active() and "done" or "off"
    return status.state
end
function AH.Status()
    AH.State()
    return status
end

-- quiet: an expected error (a list that doesn't exist yet), not counted for the dumps
local function invoke(quiet, name, ...)
    local api = v1()
    local fn = api and api[name]
    if type(fn) ~= "function" then return false end
    status.counts.calls = status.counts.calls + 1
    local result = {pcall(fn, AH.CALLER, ...)}
    if not result[1] then
        if not quiet then
            status.counts.errors = status.counts.errors + 1
            status.error = tostring(result[2])
        end
        return false
    end
    return true, unpack(result, 2)
end
local function call(name, ...) return invoke(false, name, ...) end

function AH.Has(name)
    local api = v1()
    return api ~= nil and type(api[name]) == "function"
end

local function number(value)
    if type(value) ~= "number" or Util.IsSecret(value) or value <= 0 then return nil end
    return value
end

function AH.Entry(id)
    if type(id) ~= "number" or id <= 0 or not AH.Active() then return nil end
    local entry = cache[id]
    if entry then return entry end
    local _, price = call("GetAuctionPriceByItemID", id)
    price = number(price)
    entry = {price = price or false}
    if price then
        local _, age = call("GetAuctionAgeByItemID", id)
        entry.age = type(age) == "number" and not Util.IsSecret(age) and age or nil
        local _, exact = call("IsAuctionDataExactByItemID", id)
        entry.exact = exact ~= false
    end
    cache[id] = entry
    status.counts.cached = status.counts.cached + 1
    return entry
end

function AH.Sellable(info) return not (info and info.bind == "BOP") end

-- random-bonus items go by their base ID, the cheapest variant, so not exact
function AH.ForRecord(record, info)
    if not record or not AH.Sellable(info) then return nil end
    local entry = AH.Entry(record.id)
    if not entry or not entry.price then return nil end
    return {
        price = entry.price,
        age = entry.age,
        -- no age: more than 21 days
        old = entry.age == nil or entry.age > AH.OLD_DAYS,
        exact = entry.exact and not record.randomBonus,
    }
end

-- greyed with a "~" when old or not exact
function AH.Text(price, full)
    if not price then return "" end
    local text = Util.Money(price.price, full)
    if price.old or not price.exact then return "|cff9d9d9d~|r" .. text end
    return text
end

function AH.Invalidate()
    wipe(cache)
    status.counts.cached = 0
    if AH.Active() then ns.FireChange("prices") end
end

-- RegisterForDBUpdate isn't in the readme, so it's checked too. it can't be undone, the callback checks the switch
function AH.Hook()
    if hooked or not AH.Active() or not AH.Has("RegisterForDBUpdate") then return end
    hooked = call("RegisterForDBUpdate", function() ns.Guard(AH.Invalidate) end)
end

function AH.Init() AH.Hook() end

function AH.SetEnabled(value)
    ns.addon.db.profile.auctionator = value and true or false
    AH.Hook()
    wipe(cache)
    status.counts.cached = 0
    ns.FireChange("prices")
end

local function shown(name)
    local frame = rawget(_G, name)
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true
end

-- the same test the API uses
function AH.AuctionHouseOpen() return shown("AuctionFrame") or shown("AuctionHouseFrame") end

function AH.CanSearch() return AH.Active() and AH.Has("MultiSearchExact") and AH.AuctionHouseOpen() end

-- the API refuses "^", ";" and terms wrapped in quotes
local function term(name)
    if type(name) ~= "string" or Util.IsSecret(name) then return nil end
    name = name:gsub("[%^;\"]", "")
    name = strtrim(name)
    return name ~= "" and name or nil
end

function AH.Search(name)
    name = term(name)
    if not name or not AH.CanSearch() then return false end
    return (call("MultiSearchExact", {name}))
end

-- works away from the auction house too
function AH.CanAddToList()
    return AH.Active() and AH.Has("CreateShoppingList") and AH.Has("GetShoppingListItems")
             and AH.Has("ConvertToSearchString")
end

function AH.AddToList(name)
    name = term(name)
    if not name or not AH.CanAddToList() then return false end
    local ok, search = call("ConvertToSearchString", {searchString = name, isExact = true})
    if not ok or type(search) ~= "string" then return false end
    -- the API errors on a missing list
    local found, items = invoke(true, "GetShoppingListItems", AH.SHOPPING_LIST)
    local list = {}
    for _, item in ipairs(found and type(items) == "table" and items or {}) do
        if type(item) == "string" then
            if item == search then return "present" end
            list[#list + 1] = item
        end
    end
    list[#list + 1] = search
    return (call("CreateShoppingList", AH.SHOPPING_LIST, list))
end

function AH.Coverage(records, infoOf)
    local out = {items = 0, sellable = 0, boe = 0, priced = 0, pricedBoe = 0, old = 0, inexact = 0}
    if not AH.Active() then return out end
    for _, record in ipairs(records) do
        if record.id and record.id > 0 then
            local info = infoOf(record)
            out.items = out.items + 1
            if AH.Sellable(info) then
                out.sellable = out.sellable + 1
                if info.bind == "BOE" then out.boe = out.boe + 1 end
                local price = AH.ForRecord(record, info)
                if price then
                    out.priced = out.priced + 1
                    if info.bind == "BOE" then out.pricedBoe = out.pricedBoe + 1 end
                    if price.old then out.old = out.old + 1 end
                    if not price.exact then out.inexact = out.inexact + 1 end
                end
            end
        end
    end
    return out
end
