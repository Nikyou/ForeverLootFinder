-- shared by Crafts.lua and Lists.lua. read-only
local _, ns = ...
local Util = ns.Util

local AtlasLoot = {}
ns.AtlasLoot = AtlasLoot

local ADDON = "AtlasLootClassic"
-- for modules that never call back
local POLL, TIMEOUT = 0.5, 20

function AtlasLoot.Get()
    local al = rawget(_G, "AtlasLoot")
    return type(al) == "table" and al or nil
end

function AtlasLoot.Installed() return Util.AddOnLoaded(ADDON) and AtlasLoot.Get() ~= nil end
function AtlasLoot.Enabled() return ns.addon.db.profile.atlasloot ~= false end

function AtlasLoot.Storage(module)
    local al = AtlasLoot.Get()
    local storage = al and type(al.ItemDB) == "table" and type(al.ItemDB.Storage) == "table" and al.ItemDB.Storage[module]
    return type(storage) == "table" and storage or nil
end

-- AtlasLoot's own loader first, else the client's. done runs once
function AtlasLoot.LoadModule(name, done)
    if ns.inCombat then return C_Timer.After(2, function() AtlasLoot.LoadModule(name, done) end) end
    local finished = false
    local function finish(loaded)
        if finished then return end
        finished = true
        ns.Guard(done, loaded)
    end
    if Util.AddOnLoaded(name) then return finish(true) end
    local al = AtlasLoot.Get()
    local loader = al and al.Loader
    local result
    if type(loader) == "table" then
        result = Util.SafeCall(loader.LoadModule, loader, name, function() finish(true) end)
        if type(result) == "string" and result ~= "InCombat" then return finish(false) end
    end
    if finished then return end
    if result ~= "InCombat" and not Util.AddOnLoaded(name) and C_AddOns and C_AddOns.LoadAddOn then
        Util.SafeCall(C_AddOns.LoadAddOn, name)
    end
    -- AtlasLoot only calls back for modules on its own list
    local waited = 0
    local function poll()
        if finished then return end
        if Util.AddOnLoaded(name) then return finish(true) end
        if not ns.inCombat then waited = waited + POLL end
        if waited >= TIMEOUT then return finish(false) end
        C_Timer.After(POLL, poll)
    end
    poll()
end

local readers = {}
function AtlasLoot.AddReader(reader) readers[#readers + 1] = reader end

function AtlasLoot.SetEnabled(value)
    ns.addon.db.profile.atlasloot = value and true or false
    if value then
        for _, reader in ipairs(readers) do if reader.State() == "off" then reader.Init() end end
    end
    ns.RebuildIndex()
end
