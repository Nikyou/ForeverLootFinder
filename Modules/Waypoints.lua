-- waypoints to quest givers, vendors and entrances. not to creatures, they roam and one spawn of many is no help
local _, ns = ...
local L = ns.L
local Util = ns.Util

local Waypoints = {}
ns.Waypoints = Waypoints

Waypoints.SETTINGS = {"auto", "tomtom", "pin"}
local MAX_TARGETS = 3
local MAX_GIVERS = 2

local function tomtom()
    local addon = rawget(_G, "TomTom")
    if type(addon) == "table" and type(addon.AddWaypoint) == "function" then return addon end
    return nil
end

local function pinAPI()
    local map, point = rawget(_G, "C_Map"), rawget(_G, "UiMapPoint")
    if type(map) == "table" and type(map.SetUserWaypoint) == "function" and type(point) == "table"
      and type(point.CreateFromCoordinates) == "function" then return map, point end
    return nil
end

function Waypoints.HasTomTom() return tomtom() ~= nil end
function Waypoints.HasPin() return pinAPI() ~= nil end

local function pinWorksOn(mapID)
    local map = pinAPI()
    if not map then return false end
    if type(map.CanSetUserWaypointOnMap) ~= "function" then return true end
    return Util.SafeCall(map.CanSetUserWaypointOnMap, mapID) == true
end

function Waypoints.Setting()
    local value = ns.addon.db.profile.waypoints
    if value == "tomtom" or value == "pin" then return value end
    return "auto"
end

function Waypoints.Method()
    local setting = Waypoints.Setting()
    if setting ~= "pin" and tomtom() then return "tomtom" end
    if setting ~= "tomtom" and pinAPI() then return "pin" end
    return nil
end

function Waypoints.Available() return Waypoints.Method() ~= nil end

function Waypoints.MethodFor(mapID)
    if type(mapID) ~= "number" then return nil end
    local method = Waypoints.Method()
    if method == "pin" and not pinWorksOn(mapID) then return nil end
    return method
end

local function playerPosition()
    local map = rawget(_G, "C_Map")
    if type(map) ~= "table" then return nil end
    local mapID = Util.SafeCall(map.GetBestMapForUnit, "player")
    if type(mapID) ~= "number" or Util.IsSecret(mapID) then return nil end
    local position = Util.SafeCall(map.GetPlayerMapPosition, mapID, "player")
    local x, y
    if type(position) == "table" and type(position.GetXY) == "function" then x, y = Util.SafeCall(position.GetXY, position) end
    if type(x) ~= "number" or type(y) ~= "number" or Util.IsSecret(x) or Util.IsSecret(y) then return mapID end
    return mapID, x, y
end

-- nearest on the player's map, else the first
function Waypoints.Nearest(points)
    local usable = {}
    for _, point in ipairs(points or {}) do if Waypoints.MethodFor(point.mapID) then usable[#usable + 1] = point end end
    if #usable == 0 then return nil end
    local mapID, px, py = playerPosition()
    local best, bestDistance
    for _, point in ipairs(usable) do
        if point.mapID == mapID then
            local distance = px and ((point.x - px) ^ 2 + (point.y - py) ^ 2) or 0
            if not bestDistance or distance < bestDistance then best, bestDistance = point, distance end
        end
    end
    return best or usable[1]
end

-- FDJ's entrance, else QuestieDB's (AtlasLoot's raids too)
function Waypoints.EntranceTarget(placeKey)
    if not placeKey or not Waypoints.Available() then return nil end
    local index = ns.GetIndex()
    local place = index and index.dungeonByKey[placeKey]
    if not place then return nil end
    local name = format(L["%s (entrance)"], ns.DungeonJournal.DungeonName(placeKey))
    local points = {}
    local entrance = place.entrance
    if entrance then
        points[1] = {mapID = entrance.mapID, x = entrance.x, y = entrance.y, name = name}
    else
        for area, key in pairs(index.placeByArea or {}) do
            if key == placeKey then
                for _, point in ipairs(ns.Questie.DungeonEntrances(area) or {}) do
                    points[#points + 1] = {mapID = point.mapID, x = point.x, y = point.y, name = name}
                end
            end
        end
    end
    return Waypoints.Nearest(points)
end

local function npcTarget(npcIDs)
    local points = {}
    for _, id in ipairs(npcIDs or {}) do
        for _, point in ipairs(ns.Questie.Locations("Npc", id)) do points[#points + 1] = point end
    end
    return Waypoints.Nearest(points)
end

-- only points some method can mark
function Waypoints.Targets(source)
    local out, seen = {}, {}
    if not source or not Waypoints.Available() or not ns.Questie.Installed() and not source.dungeon then return out end
    local function add(target)
        if not target or #out >= MAX_TARGETS then return end
        local key = target.name .. ":" .. target.mapID
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = target
    end
    if source.questID and ns.Questie.Installed() then
        local givers = 0
        for _, giver in ipairs(ns.Questie.Starters(source.questID)) do
            if givers >= MAX_GIVERS then break end
            local target = Waypoints.Nearest(ns.Questie.Locations(giver.kind, giver.id))
            if target then
                givers = givers + 1
                add(target)
            end
        end
    end
    if source.kind == "vendor" and ns.Questie.Installed() then add(npcTarget(source.npcs or (source.npcID and {source.npcID}))) end
    if source.dungeon then add(Waypoints.EntranceTarget(source.dungeon)) end
    return out
end

function Waypoints.Go(target)
    local method = target and Waypoints.MethodFor(target.mapID)
    local done = false
    if method == "tomtom" then
        local addon = tomtom()
        done = pcall(addon.AddWaypoint, addon, target.mapID, target.x, target.y,
                     {title = target.name, from = ns.TITLE, crazy = true})
    elseif method == "pin" then
        local map, point = pinAPI()
        local pin = Util.SafeCall(point.CreateFromCoordinates, target.mapID, target.x, target.y)
        done = pin ~= nil and pcall(map.SetUserWaypoint, pin)
        local super = rawget(_G, "C_SuperTrack")
        if done and type(super) == "table" and type(super.SetSuperTrackedUserWaypoint) == "function" then
            pcall(super.SetSuperTrackedUserWaypoint, true)
        end
    end
    if done then ns.Print(format(L["Waypoint set: %s"], target.name)) end
    return done
end

function Waypoints.DumpLines()
    local map = rawget(_G, "C_Map")
    local lines = {}
    lines[#lines + 1] = format("navigation: setting %s, in use %s; TomTom %s, map pin %s (map check %s, super track %s)",
                               Waypoints.Setting(), tostring(Waypoints.Method() or "none"), tostring(Waypoints.HasTomTom()),
                               tostring(Waypoints.HasPin()),
                               tostring(type(map) == "table" and type(map.CanSetUserWaypointOnMap) == "function"),
                               tostring(type(rawget(_G, "C_SuperTrack")) == "table"))
    local sources = ns.Questie.MapSources()
    local index = ns.GetIndex()
    local fdjEntrances, places, questieEntrances = 0, 0, 0
    for _, place in ipairs(index and index.dungeons or {}) do
        places = places + 1
        if place.entrance then
            fdjEntrances = fdjEntrances + 1
        elseif Waypoints.EntranceTarget(place.key) then
            questieEntrances = questieEntrances + 1
        end
    end
    lines[#lines + 1] = format("area to map: Questie ZoneDB %s, QuestieDB support data %d areas; entrances: %d of %d places "
                                 .. "from FDJ, %d more from QuestieDB", tostring(sources.zoneDB), sources.support, fdjEntrances,
                               places, questieEntrances)
    return lines
end
