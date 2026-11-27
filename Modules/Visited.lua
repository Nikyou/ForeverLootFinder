-- what the vendors this account visited sell, read at the merchant window and kept for good: the gear as vendor lines,
-- the recipe items for the line under a craft. Forever's vendors the addons don't list yet
local _, ns = ...

local Visited = {}
ns.Visited = Visited

local Util = ns.Util
local RECIPE_CLASS = 9

local status = Util.NewStatus("visited", {vendors = 0, gear = 0, recipes = 0})
local stats = status.counts
local EMPTY = {provider = "visited", entries = {}}
local extra -- built from the saved vendors when the index asks
local recipeVendors = {}

local function store() return ns.addon.db.global.vendors end

local function readable(value) return value ~= nil and not Util.IsSecret(value) and value or nil end

local function isRecipe(item) return select(6, Util.SafeCall(C_Item.GetItemInfoInstant, item)) == RECIPE_CLASS end

local function mapName(map)
    local info = C_Map and C_Map.GetMapInfo and Util.SafeCall(C_Map.GetMapInfo, map)
    local name = type(info) == "table" and readable(info.name)
    return type(name) == "string" and name ~= "" and name or nil
end

function Visited.Installed() return true end
function Visited.Enabled() return ns.addon.db.profile.visited ~= false end
function Visited.State() return status.state end
function Visited.Status() return status end

-- pure, for tests. vendors: [npcID] = {name, faction, map, x, y, items = {[itemID] = true}}
function Visited.Read(vendors, opt)
    local out, recipes, counts = {}, {}, {vendors = 0, gear = 0, recipes = 0}
    for npcID, vendor in pairs(vendors) do
        if type(npcID) == "number" and type(vendor) == "table" and type(vendor.items) == "table" then
            counts.vendors = counts.vendors + 1
            local zone = vendor.map and ("m" .. vendor.map)
            local zoneName = vendor.map and opt.mapName(vendor.map)
            for item in pairs(vendor.items) do
                if opt.equippable(item) then
                    out[#out + 1] = {
                        id = item,
                        kind = "vendor",
                        npcID = npcID,
                        npcName = vendor.name,
                        npcs = {npcID},
                        faction = vendor.faction,
                        zone = zone,
                        zoneKey = zone,
                        zoneName = zoneName,
                    }
                    counts.gear = counts.gear + 1
                elseif opt.isRecipe(item) then
                    recipes[item] = recipes[item] or {}
                    table.insert(recipes[item], {name = vendor.name, zone = zoneName, faction = vendor.faction})
                    counts.recipes = counts.recipes + 1
                end
            end
        end
    end
    return out, recipes, counts
end

local function build()
    if extra then return end
    local out, recipes, counts = Visited.Read(store(), {equippable = Util.Equippable, isRecipe = isRecipe, mapName = mapName})
    extra, recipeVendors = {provider = "visited", entries = out}, recipes
    for key, value in pairs(counts) do stats[key] = value end
    status.state = "done"
end

function Visited.Stats()
    if Visited.Enabled() then build() end
    return stats
end

function Visited.Entries()
    if not Visited.Enabled() then return EMPTY end
    build()
    return extra
end

function Visited.RecipeVendors(item)
    if not (item and Visited.Enabled()) then return nil end
    build()
    return recipeVendors[item]
end

-- the merchant window is open: who it is, what it sells, where the player stands. its GUID and name are secret in some
-- restricted states, then nothing is kept
function Visited.OnMerchant()
    if not Visited.Enabled() then return end
    local guid = readable(UnitGUID("npc"))
    local npcID = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
    local name = readable(UnitName("npc"))
    local count = readable(GetMerchantNumItems())
    if not (npcID and type(name) == "string" and type(count) == "number") then return end
    local vendor = store()[npcID] or {items = {}}
    local added = false
    for slot = 1, count do
        local item = readable(GetMerchantItemID(slot))
        if type(item) == "number" and not vendor.items[item] and (Util.Equippable(item) or isRecipe(item)) then
            vendor.items[item] = true
            added = true
        end
    end
    if not next(vendor.items) then return end
    local faction = readable(UnitFactionGroup("npc"))
    vendor.name, vendor.faction = name, (faction == "Alliance" or faction == "Horde") and faction or nil
    local map = C_Map and C_Map.GetBestMapForUnit and readable(Util.SafeCall(C_Map.GetBestMapForUnit, "player"))
    if type(map) == "number" then
        vendor.map = map
        local position = C_Map.GetPlayerMapPosition and Util.SafeCall(C_Map.GetPlayerMapPosition, map, "player")
        local x, y = nil, nil
        if type(position) == "table" and position.GetXY then x, y = position:GetXY() end
        if readable(x) and readable(y) then vendor.x, vendor.y = x, y end
    end
    store()[npcID] = vendor
    if added then
        extra = nil
        ns.RebuildIndex()
    end
end

function Visited.Init() status.state = Visited.Enabled() and "waiting" or "off" end

function Visited.SetEnabled(value)
    ns.addon.db.profile.visited = value and true or false
    extra = nil
    status.state = value and "waiting" or "off"
    ns.RebuildIndex()
end
