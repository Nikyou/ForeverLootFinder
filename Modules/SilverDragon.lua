-- SilverDragon's rares and what they drop. a rare inside a dungeon joins it (FDJ's entry wins when it has the same
-- one), the rest are creature drops in their zone. read-only
local _, ns = ...

local SilverDragon = {}
ns.SilverDragon = SilverDragon

local Util = ns.Util
local status = Util.NewStatus("silverdragon", {rares = 0, items = 0})
local stats = status.counts
local entries = {}
local built = false

local function core()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    local addon = ace and ace:GetAddon("SilverDragon", true)
    if type(addon) ~= "table" or type(addon.datasources) ~= "table" then return nil end
    return addon
end

function SilverDragon.Installed() return core() ~= nil end
function SilverDragon.Enabled() return ns.addon.db.profile.silverdragon ~= false end
function SilverDragon.State() return status.state end
function SilverDragon.Status() return status end
function SilverDragon.Stats() return stats end

-- loot is item IDs, or SilverDragon's reward objects once it has read them (toys, mounts and pets too)
local function itemID(item)
    if type(item) == "number" then return item end
    if type(item) == "table" then return tonumber(item.id) or tonumber(item[1]) end
    return nil
end

local function firstMap(locations)
    local best
    for map in pairs(type(locations) == "table" and locations or {}) do
        if type(map) == "number" and (not best or map < best) then best = map end
    end
    return best
end

-- pure, for tests. mapName(uiMap) and dungeonOf(name) are the client's and FDJ's
function SilverDragon.Read(sources, equippable, mapName, dungeonOf)
    local out, rares = {}, 0
    for _, mobs in pairs(sources) do
        for npcID, mob in pairs(type(mobs) == "table" and mobs or {}) do
            if type(npcID) == "number" and type(mob) == "table" and type(mob.name) == "string" then
                local items = {}
                for _, item in ipairs(type(mob.loot) == "table" and mob.loot or {}) do
                    local id = itemID(item)
                    if id and id > 0 and equippable(id) then items[#items + 1] = id end
                end
                if #items > 0 then
                    rares = rares + 1
                    local map = firstMap(mob.locations)
                    local place = map and mapName(map)
                    local dungeon = place and dungeonOf(place)
                    for _, id in ipairs(items) do
                        local entry = {id = id, npcID = npcID, npcName = mob.name, npcs = {npcID}, rare = true}
                        if dungeon then
                            entry.kind, entry.dungeon, entry.bossName, entry.creature = "rare", dungeon, mob.name, true
                        else
                            entry.kind = "npcDrop"
                            entry.zoneName = place
                            entry.zoneKey = map and ("map:" .. map) or nil
                        end
                        out[#out + 1] = entry
                    end
                end
            end
        end
    end
    return out, rares
end

local function mapName(map)
    local info = C_Map and C_Map.GetMapInfo and Util.SafeCall(C_Map.GetMapInfo, map)
    local name = type(info) == "table" and info.name
    return type(name) == "string" and not Util.IsSecret(name) and name or nil
end

local function dungeonOf(name)
    local found = ns.DungeonJournal.MatchInstance(nil, name)
    return found and found[1] or nil
end

local function build()
    local addon = core()
    if not addon then
        status.state = "nodata"
        return
    end
    local ok, out, rares = pcall(SilverDragon.Read, addon.datasources, Util.Equippable, mapName, dungeonOf)
    if not ok then
        status.state, status.error = "nodata", tostring(out)
        ns.ReportError(out)
        return
    end
    entries = out
    stats.rares, stats.items = rares, #out
    status.state = #out > 0 and "done" or "nodata"
end

-- SilverDragon registers its data while it loads, so read on first use
function SilverDragon.Entries()
    if not SilverDragon.Enabled() or not SilverDragon.Installed() then return {} end
    if not built then
        built = true
        build()
    end
    return entries
end

function SilverDragon.Init()
    status.state = (SilverDragon.Installed() and SilverDragon.Enabled()) and "waiting" or "off"
end

function SilverDragon.SetEnabled(value)
    ns.addon.db.profile.silverdragon = value and true or false
    built = false
    status.state = value and "waiting" or "off"
    ns.RebuildIndex()
end
