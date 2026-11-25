-- the only file that reads GearQuest Forever: its stat weights, as scales after Pawn's. read-only
local _, ns = ...
local Util = ns.Util

local GearQuest = {}
ns.GearQuest = GearQuest

local ADDON = "GearQuestForever"
local PREFIX = "gq:"
local COLOR = "|cff66ccff" -- GearQuest's own, as in its chat lines
-- before talents GearQuest has one set for the whole class (GQ.Spec.TALENT_LEVEL), so each spec's scale uses it
local LEVELLING, TALENT_LEVEL = "levelling_1_9", 10
-- damage specs don't count healing (GearQuest's Compare.lua)
local HEALERS = {
    PALADIN = {holy = true},
    DRUID = {restoration = true},
    SHAMAN = {restoration = true},
    PRIEST = {holy = true, discipline = true},
}
-- its weight keys to Data/StatMap.lua's. ranged attack power counts as attack power, as GearQuest scores it
local STATS = {
    str = {"STR"},
    agi = {"AGI"},
    sta = {"STA"},
    int = {"INT"},
    spi = {"SPI"},
    ap = {"AP", "RAP"},
    feralAp = {"FERALAP"},
    hit = {"HIT"},
    crit = {"CRIT"},
    haste = {"HASTE"},
    expertise = {"EXPERTISE"},
    sp = {"SPELLDMG"},
    heal = {"HEAL"},
    spArcane = {"ARCANEDMG"},
    spFire = {"FIREDMG"},
    spFrost = {"FROSTDMG"},
    spHoly = {"HOLYDMG"},
    spNature = {"NATUREDMG"},
    spShadow = {"SHADOWDMG"},
    mp5 = {"MP5"},
    hp5 = {"HP5"},
    mana = {"MANA"},
    health = {"HEALTH"},
    armor = {"ARMOR", "BONUSARMOR"},
    defense = {"DEFENSE"},
    dodge = {"DODGE"},
    parry = {"PARRY"},
    blockRating = {"BLOCK"},
    blockValue = {"BLOCKVALUE"},
    resist = {"ARCANERES", "FIRERES", "FROSTRES", "NATURERES", "SHADOWRES"},
}
local RANGED = {INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true}
GearQuest.STATS = STATS

local isSecret = Util.IsSecret

local function addon()
    if not Util.AddOnLoaded(ADDON) then return nil end
    local gq = rawget(_G, "GearQuest")
    return type(gq) == "table" and type(gq.ScoringWeights) == "table" and gq or nil
end

function GearQuest.Installed() return addon() ~= nil end

function GearQuest.IsScale(scale) return type(scale) == "string" and scale:sub(1, #PREFIX) == PREFIX end

local function specOf(scale) return GearQuest.IsScale(scale) and scale:sub(#PREFIX + 1) or nil end

-- the character's class only: a scale is a spec of it
local function classWeights()
    local gq = addon()
    if not gq then return nil end
    local class = ns.Character().class
    local byClass = class and gq.ScoringWeights[class]
    return type(byClass) == "table" and byClass or nil, class, gq
end

local function rowOf(byClass, spec)
    local row = byClass and spec and byClass[spec]
    return type(row) == "table" and type(row.weights) == "table" and row or nil
end

function GearQuest.Exists(scale)
    local spec = specOf(scale)
    return spec ~= nil and spec ~= LEVELLING and rowOf(classWeights(), spec) ~= nil
end

-- "Holy - healing" is GearQuest's longer label, the part before the dash is enough here
local function specLabel(spec)
    local byClass, class, gq = classWeights()
    local specs = gq and type(gq.Spec) == "table" and gq.Spec
    local label = specs and Util.SafeCall(specs.GetSpecLabel, specs, spec, class)
    if type(label) ~= "string" or isSecret(label) or label == "" then label = rowOf(byClass, spec).label end
    label = type(label) == "string" and label or spec
    return (label:gsub(" %- .*$", ""))
end

function GearQuest.Label(scale)
    if not GearQuest.Exists(scale) then return scale end
    return "GearQuest: " .. specLabel(specOf(scale))
end

GearQuest.COLOR = COLOR

function GearQuest.Scales()
    local list = {}
    local byClass = classWeights()
    for spec in pairs(byClass or {}) do
        local scale = PREFIX .. tostring(spec)
        if GearQuest.Exists(scale) then
            list[#list + 1] = {name = scale, label = GearQuest.Label(scale), header = "GearQuest", visible = true}
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- the spec GearQuest itself goes by: the one picked there, else the talents, else its default
function GearQuest.Default()
    local _, _, gq = classWeights()
    local specs = gq and type(gq.Spec) == "table" and gq.Spec
    local spec = specs and Util.SafeCall(specs.GetDisplaySpec, specs)
    if type(spec) == "string" and GearQuest.Exists(PREFIX .. spec) then return PREFIX .. spec end
    local list = GearQuest.Scales()
    return list[1] and list[1].name or nil
end

-- the set in use: below talent level the class's levelling one, which counts no healing (no spec yet)
local function weightsFor(scale)
    local byClass, class = classWeights()
    local spec = specOf(scale)
    local row = rowOf(byClass, spec)
    if not row then return nil end
    if (ns.Character().level or 1) < TALENT_LEVEL and rowOf(byClass, LEVELLING) then
        return rowOf(byClass, LEVELLING), false, LEVELLING
    end
    return row, HEALERS[class] ~= nil and HEALERS[class][spec] == true, spec
end

function GearQuest.Score(stats, equipLoc, scale)
    local row, healer = weightsFor(scale)
    if not row or type(stats) ~= "table" then return nil end
    local total = 0
    for key, keys in pairs(STATS) do
        local weight = tonumber(row.weights[key])
        if weight and weight ~= 0 and (key ~= "heal" or healer) then
            for _, stat in ipairs(keys) do total = total + weight * (tonumber(stats[stat]) or 0) end
        end
    end
    local dpsWeight = tonumber(RANGED[equipLoc] and row.dpsWeightRanged or row.dpsWeight)
    if dpsWeight and tonumber(stats.DPS) then total = total + dpsWeight * stats.DPS end
    return total
end

local function statsOf(item)
    local ok, raw = pcall(C_Item.GetItemStats, item)
    local stats = ns.StatMap.Convert(ok and raw or nil)
    local equipLoc = select(4, Util.SafeCall(C_Item.GetItemInfoInstant, item))
    return stats, equipLoc
end

-- like Pawn's: nil while the client lacks the item, false when there's nothing to score
function GearQuest.Value(id, scale)
    if not C_Item.GetItemInfo(id) then return nil, "uncached" end
    local stats, equipLoc = statsOf("item:" .. id)
    local value = GearQuest.Score(stats, equipLoc, scale)
    if value == nil then return nil end
    return value > 0 and value or false
end

function GearQuest.SlotValue(link, scale)
    if not C_Item.GetItemInfo(link) then return nil end
    local stats, equipLoc = statsOf(link)
    return GearQuest.Score(stats, equipLoc, scale) or 0
end

-- what the values depend on: GearQuest's weights revision, the set in use (it changes at talent level) and its numbers
function GearQuest.SignatureText(scale)
    local row, healer, set = weightsFor(scale)
    if not row then return nil end
    local keys = {}
    for key, value in pairs(row.weights) do if type(value) == "number" then keys[#keys + 1] = key end end
    table.sort(keys)
    local parts = {"gq", tostring(addon().SCORING_WEIGHTS_REVISION), set, tostring(healer)}
    for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. row.weights[key] end
    parts[#parts + 1] = "dps=" .. tostring(row.dpsWeight) .. "/" .. tostring(row.dpsWeightRanged)
    return table.concat(parts, ";")
end
