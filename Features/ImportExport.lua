local ADDON_NAME, ns = ...
local L = ns.L

local ImportExport = {}
ns.ImportExport = ImportExport

local PREFIX = "!FLF1!"
local PAYLOAD_VERSION = 1
local ENUMS = {mode = {off = true, chat = true, window = true}}
local SECTIONS = {"badges", "tooltip", "dungeonTab", "favourites", "reminder", "dropAlert", "tabs", "questTab", "craftTab",
                  "questieKinds", "columns"}
local FLAGS = {"showUnknown", "showMissing", "randomPass", "stars", "cardChance", "syndicator", "questie", "atlasloot",
               "auctionator"}
local WAYPOINTS = {auto = true, tomtom = true, pin = true}

local function allowed(key, value)
    if key == "defaultTier" then return ns.Favourites.BY_TIER[value] ~= nil end
    return not (ENUMS[key] and not ENUMS[key][value])
end

-- only values of the default's type get through, so a broken string can't break the profile
local function sanitize(source, defaults)
    local out = {}
    for key, default in pairs(defaults) do
        local value = source[key]
        if type(default) == "table" then
            if type(value) == "table" then out[key] = sanitize(value, default) end
        elseif type(value) == type(default) and allowed(key, value) then
            out[key] = value
        end
    end
    return out
end

local function sanitizePriority(source)
    local out = {}
    if type(source) ~= "table" then return out end
    for group, order in pairs(ns.Index.DEFAULT_PRIORITY) do
        local text = source[group]
        if type(text) == "string" then
            local known, list = {}, {}
            for _, name in ipairs(order) do known[name] = true end
            for name in text:gmatch("[^>%s]+") do if known[name] then list[#list + 1] = name end end
            if #list > 0 then out[group] = table.concat(list, ">") end
        end
    end
    return out
end

function ImportExport.GetAddonVersion() return C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") end

function ImportExport.ExportProfile(profile)
    profile = profile or ns.addon.db.profile
    local data = {minimap = {hide = profile.minimap.hide}, priority = profile.priority, waypoints = profile.waypoints}
    for _, section in ipairs(SECTIONS) do data[section] = profile[section] end
    for _, flag in ipairs(FLAGS) do data[flag] = profile[flag] end
    return ns.Util.Encode(PREFIX, {
        v = PAYLOAD_VERSION,
        addonVersion = ImportExport.GetAddonVersion(),
        schema = ns.SCHEMA_VERSION,
        profile = data,
    })
end

local DECODE_ERRORS = {
    empty = L["The string is empty."],
    prefix = L["Not a Forever LootFinder profile string."],
    damaged = L["The string is damaged."],
}

function ImportExport.Decode(text)
    local payload, why = ns.Util.Decode(text, PREFIX)
    if not payload then return nil, DECODE_ERRORS[why] end
    if type(payload.profile) ~= "table" then return nil, L["The string is damaged."] end
    if payload.v ~= PAYLOAD_VERSION then return nil, L["Needs a newer Forever LootFinder."] end
    if type(payload.schema) == "number" and payload.schema > ns.SCHEMA_VERSION then
        return nil, L["Needs a newer Forever LootFinder."]
    end
    local source, defaults = payload.profile, ns.DEFAULTS.profile
    local data = {}
    for _, section in ipairs(SECTIONS) do
        data[section] = sanitize(type(source[section]) == "table" and source[section] or {}, defaults[section])
    end
    for _, flag in ipairs(FLAGS) do if type(source[flag]) == "boolean" then data[flag] = source[flag] end end
    -- false must come through too
    local minimap = type(source.minimap) == "table" and source.minimap.hide
    if type(minimap) == "boolean" then data.minimapHide = minimap end
    data.priority = sanitizePriority(source.priority)
    if WAYPOINTS[source.waypoints] then data.waypoints = source.waypoints end
    data.addonVersion = type(payload.addonVersion) == "string" and payload.addonVersion or nil
    return data
end

function ImportExport.Summary(data)
    local lines = {L["All display and alert settings"]}
    if data.addonVersion and data.addonVersion:match("^v?%d") then
        lines[#lines + 1] = format(L["Made with Forever LootFinder %s"], data.addonVersion)
    end
    return table.concat(lines, "\n")
end

function ImportExport.Apply(data, profile)
    profile = profile or ns.addon.db.profile
    for _, section in ipairs(SECTIONS) do
        if type(profile[section]) ~= "table" then profile[section] = {} end
        for key, value in pairs(data[section] or {}) do profile[section][key] = value end
    end
    for _, flag in ipairs(FLAGS) do if data[flag] ~= nil then profile[flag] = data[flag] end end
    if data.minimapHide ~= nil then profile.minimap.hide = data.minimapHide end
    if data.waypoints then profile.waypoints = data.waypoints end
    if data.priority and next(data.priority) then
        profile.priority = profile.priority or {}
        for group, text in pairs(data.priority) do profile.priority[group] = text end
    end
    ns.addon:OnProfileChanged()
end
