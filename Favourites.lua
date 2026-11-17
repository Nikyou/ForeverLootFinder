local _, ns = ...
local L = ns.L

local Favourites = {}
ns.Favourites = Favourites

-- saved data only stores the key
Favourites.TIERS = {
    {key = "BIS", label = L["BiS"], color = {1, 0.5, 0}}, {key = "MUST", label = L["Must have"], color = {0.64, 0.21, 0.93}},
    {key = "NICE", label = L["Nice to have"], color = {0.25, 0.6, 1}},
}
Favourites.BY_TIER = {}
for index, tier in ipairs(Favourites.TIERS) do
    tier.order = index
    Favourites.BY_TIER[tier.key] = tier
end
Favourites.IMPORT_TIER = "NICE"

local PREFIX = "!FLFF1!"
local PAYLOAD_VERSION = 1

-- global: AceDB's global table
local function global() return ns.addon.db.global end

function Favourites.TierColor(tier)
    local data = Favourites.BY_TIER[tier]
    local c = data and data.color or {1, 1, 1}
    return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

function Favourites.TierLabel(tier)
    local data = Favourites.BY_TIER[tier]
    return data and data.label or tostring(tier)
end

function Favourites.GetIn(store, charKey, id)
    local list = store[charKey]
    return list and list[id] or nil
end

function Favourites.SetIn(store, charKey, id, tier)
    if tier ~= nil and not Favourites.BY_TIER[tier] then return end
    store[charKey] = store[charKey] or {}
    store[charKey][id] = tier
end

function Favourites.WhoIn(store, id)
    local out = {}
    for charKey, list in pairs(store) do
        local tier = list[id]
        if tier then
            out[tier] = out[tier] or {}
            table.insert(out[tier], charKey)
        end
    end
    for _, list in pairs(out) do table.sort(list) end
    return out
end

function Favourites.PlanImport(fdjList, current, known)
    local plan = {new = {}, existing = {}, skipped = {}}
    local seen = {}
    for _, entry in ipairs(fdjList) do
        local id = entry.id
        if not id or id <= 0 then
            plan.skipped[#plan.skipped + 1] = {id = id, name = entry.name, reason = "no item ID"}
        elseif not known(id) then
            plan.skipped[#plan.skipped + 1] = {id = id, name = entry.name, reason = "not an item FLF lists"}
        elseif not seen[id] then
            seen[id] = true
            if current and current[id] then
                plan.existing[#plan.existing + 1] = id
            else
                plan.new[#plan.new + 1] = id
            end
        end
    end
    return plan
end

-- only adds, existing tiers stay
function Favourites.ApplyImport(store, charKey, plan)
    for _, id in ipairs(plan.new) do
        if not Favourites.GetIn(store, charKey, id) then Favourites.SetIn(store, charKey, id, Favourites.IMPORT_TIER) end
    end
end

function Favourites.CharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if ns.IsSecret(name) or ns.IsSecret(realm) then return nil end
    return (name or "?") .. "-" .. (realm or "?")
end

function Favourites.Get(id, charKey) return Favourites.GetIn(global().favourites, charKey or ns.charKey, id) end

function Favourites.Set(id, tier, charKey)
    Favourites.SetIn(global().favourites, charKey or ns.charKey, id, tier)
    ns.FireChange("favourites")
end

function Favourites.Toggle(id, charKey)
    if Favourites.Get(id, charKey) then
        Favourites.Set(id, nil, charKey)
    else
        Favourites.Set(id, ns.addon.db.profile.favourites.defaultTier, charKey)
    end
end

function Favourites.Who(id) return Favourites.WhoIn(global().favourites, id) end

function Favourites.List(charKey) return global().favourites[charKey or ns.charKey] or {} end

function Favourites.Characters()
    local list = {}
    for key, data in pairs(global().characters) do list[#list + 1] = {key = key, data = data} end
    table.sort(list, function(a, b)
        if a.key == ns.charKey then return true end
        if b.key == ns.charKey then return false end
        return a.key < b.key
    end)
    return list
end

function Favourites.CharacterName(charKey)
    local data = global().characters[charKey]
    return data and data.name or (charKey and charKey:match("^(.-)%-") or charKey)
end

-- the realm only when it's another one
function Favourites.CharacterLabel(charKey)
    local data = global().characters[charKey] or {}
    local name = Favourites.CharacterName(charKey) or "?"
    local realm = data.realm or (charKey and charKey:match("%-(.+)$"))
    local current = ns.charKey and ns.charKey:match("%-(.+)$")
    if realm and current and realm ~= current then name = name .. " - " .. realm end
    local color = data.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
    if color and color.colorStr then name = "|c" .. color.colorStr .. name .. "|r" end
    return name
end

function Favourites.DeleteCharacter(charKey)
    global().characters[charKey] = nil
    global().favourites[charKey] = nil
    if ns.InvalidateCharacters then ns.InvalidateCharacters() end
    ns.FireChange("favourites")
end

function Favourites.Export(charKey)
    local list = {}
    for id, tier in pairs(Favourites.List(charKey)) do list[id] = tier end
    return ns.Util.Encode(PREFIX, {v = PAYLOAD_VERSION, items = list, from = Favourites.CharacterName(charKey)})
end

local DECODE_ERRORS = {
    empty = L["The string is empty."],
    prefix = L["Not a favourites string."],
    damaged = L["The string is damaged."],
}

function Favourites.Decode(text)
    local payload, why = ns.Util.Decode(text, PREFIX)
    if not payload then return nil, DECODE_ERRORS[why] end
    if type(payload.items) ~= "table" then return nil, L["The string is damaged."] end

    if payload.v ~= PAYLOAD_VERSION then return nil, L["Needs a newer Forever Loot Finder."] end
    local items, count = {}, 0
    for id, tier in pairs(payload.items) do
        if type(id) == "number" and id > 0 and id == math.floor(id) and Favourites.BY_TIER[tier] then
            items[id] = tier
            count = count + 1
        end
    end
    return {items = items, count = count, from = type(payload.from) == "string" and payload.from or nil}
end

function Favourites.Summary(data, charKey)
    local current = Favourites.List(charKey)
    local new, changed, same = 0, 0, 0
    for id, tier in pairs(data.items) do
        if not current[id] then
            new = new + 1
        elseif current[id] ~= tier then
            changed = changed + 1
        else
            same = same + 1
        end
    end
    local text = format(L["%d favourites: %d new, %d tier changed, %d unchanged."], data.count, new, changed, same)
    if data.from then text = format(L["From %s."], data.from) .. "\n" .. text end
    return text
end

function Favourites.ApplyDecoded(data, mode, charKey)
    charKey = charKey or ns.charKey
    local store = global().favourites
    if mode == "overwrite" then store[charKey] = {} end
    for id, tier in pairs(data.items) do
        if mode == "overwrite" or not Favourites.GetIn(store, charKey, id) then Favourites.SetIn(store, charKey, id, tier) end
    end
    ns.FireChange("favourites")
end

function Favourites.FDJPlan()
    local index = ns.GetIndex()
    local known = function(id)
        local record = index and index.byKey[id]
        if not record then return false end
        return ns.Items.Info(record).slot ~= nil
    end
    return Favourites.PlanImport(ns.Source.FavouriteItems(), Favourites.List(), known)
end

function Favourites.FDJSummary(plan)
    local text = format(L["%d new, %d unchanged, %d skipped."], #plan.new, #plan.existing, #plan.skipped)
    if #plan.skipped > 0 then
        local names = {}
        for i, entry in ipairs(plan.skipped) do
            if i > 10 then
                names[#names + 1] = format(L["and %d more"], #plan.skipped - 10)
                break
            end
            names[#names + 1] = format("%s (%s)", entry.name or "?",
                                       entry.id and entry.id > 0 and tostring(entry.id) or L["no ID"])
        end
        text = text .. "\n\n" .. L["Skipped:"] .. " " .. table.concat(names, ", ")
    end
    return text
end

function Favourites.ApplyFDJ(plan)
    Favourites.ApplyImport(global().favourites, ns.charKey, plan)
    ns.FireChange("favourites")
end

function Favourites.HasFDJList() return #ns.Source.FavouriteItems() > 0 end
