-- patterns are built from the client's own format strings, so nothing here is English. pure Lua
local _, ns = ...

local Restrictions = {}
ns.Restrictions = Restrictions

Restrictions.GLOBALS = {
    "ITEM_CLASSES_ALLOWED", "ITEM_RACES_ALLOWED", "ITEM_MIN_LEVEL", "ITEM_UNIQUE", "ITEM_UNIQUE_EQUIPPABLE",
    "ITEM_UNIQUE_MULTIPLE", "ITEM_LIMIT_CATEGORY", "ITEM_LIMIT_CATEGORY_MULTIPLE", "ITEM_BIND_ON_PICKUP", "ITEM_BIND_ON_EQUIP",
    "ITEM_BIND_ON_USE", "ITEM_SET_NAME", "ITEM_SET_BONUS", "ITEM_SET_BONUS_GRAY", "ITEM_SPELL_TRIGGER_ONUSE",
    "ITEM_SPELL_TRIGGER_ONPROC", "DAMAGE_TEMPLATE", "DAMAGE_TEMPLATE_WITH_SCHOOL", "SINGLE_DAMAGE_TEMPLATE",
    "ITEM_REQ_SKILL", "ITEM_REQ_REPUTATION", "ITEM_COSMETIC",
}

-- FDJ's tip lines are English on every client
Restrictions.ENGLISH = {
    ITEM_CLASSES_ALLOWED = "Classes: %s",
    ITEM_RACES_ALLOWED = "Races: %s",
    ITEM_MIN_LEVEL = "Requires Level %d",
    ITEM_UNIQUE = "Unique",
    ITEM_UNIQUE_EQUIPPABLE = "Unique-Equipped",
    ITEM_UNIQUE_MULTIPLE = "Unique (%d)",
    ITEM_BIND_ON_PICKUP = "Binds when picked up",
    ITEM_BIND_ON_EQUIP = "Binds when equipped",
    ITEM_BIND_ON_USE = "Binds when used",
    ITEM_SET_NAME = "%s (%d/%d)",
    ITEM_SET_BONUS = "Set: %s",
    ITEM_SET_BONUS_GRAY = "(%d) Set: %s",
    ITEM_SPELL_TRIGGER_ONUSE = "Use:",
    ITEM_SPELL_TRIGGER_ONPROC = "Chance on hit:",
    DAMAGE_TEMPLATE = "%s - %s Damage",
    DAMAGE_TEMPLATE_WITH_SCHOOL = "%s - %s %s Damage",
    SINGLE_DAMAGE_TEMPLATE = "%s Damage",
    ITEM_REQ_SKILL = "Requires %s",
    ITEM_REQ_REPUTATION = "Requires %s - %s",
    ITEM_COSMETIC = "Cosmetic",
}

local stripCodes = ns.Util.StripCodes
Restrictions.StripCodes = stripCodes

-- "Classes: %s" -> "^Classes: (.+)$", including the |3 and |4 grammar codes of ruRU
function Restrictions.FormatToPattern(format, anchored)
    if type(format) ~= "string" or format == "" then return nil end
    local out, i, n = {}, 1, #format
    while i <= n do
        local c = format:sub(i, i)
        if c == "%" then
            local spec = format:match("^%%(%d*%$?[%-%d%.]*[sdifg%%])", i)
            if spec == "%" then
                out[#out + 1] = "%%"
                i = i + 2
            elseif spec then
                local kind = spec:sub(-1)
                out[#out + 1] = (kind == "s") and "(.-)" or "([%d%.,]+)"
                i = i + 1 + #spec
            else
                out[#out + 1] = "%%"
                i = i + 1
            end
        elseif c == "|" and format:sub(i + 1, i + 1) == "3" then
            -- |3-6(%s): declined noun
            local close = format:find(")", i, true)
            out[#out + 1] = "(.-)"
            i = close and close + 1 or n + 1
        elseif c == "|" and format:sub(i + 1, i + 1) == "4" then
            -- |4singular:plural; any form will do
            local close = format:find(";", i, true)
            out[#out + 1] = ".-"
            i = close and close + 1 or n + 1
        elseif c:match("[%^%$%(%)%.%[%]%*%+%-%?]") then
            out[#out + 1] = "%" .. c
            i = i + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    local pattern = table.concat(out)
    if pattern:sub(-4) == "(.-)" then pattern = pattern:sub(1, -5) .. "(.+)" end
    if anchored ~= false then pattern = "^" .. pattern .. "$" end
    return pattern
end

local function prefix(text)
    if type(text) ~= "string" or text == "" then return nil end
    return stripCodes(text)
end

function Restrictions.BuildPatterns(G, lineTypes)
    local p = {}
    p.classes = Restrictions.FormatToPattern(G.ITEM_CLASSES_ALLOWED)
    p.races = Restrictions.FormatToPattern(G.ITEM_RACES_ALLOWED)
    p.minLevel = Restrictions.FormatToPattern(G.ITEM_MIN_LEVEL)
    -- after the level and reputation lines, they start the same way
    p.reqSkill = Restrictions.FormatToPattern(G.ITEM_REQ_SKILL)
    p.reqReputation = Restrictions.FormatToPattern(G.ITEM_REQ_REPUTATION)
    p.uniqueExact = {}
    for _, key in ipairs({"ITEM_UNIQUE", "ITEM_UNIQUE_EQUIPPABLE"}) do
        if type(G[key]) == "string" then p.uniqueExact[G[key]] = key end
    end
    p.uniquePatterns = {}
    for _, key in ipairs({"ITEM_UNIQUE_MULTIPLE", "ITEM_LIMIT_CATEGORY", "ITEM_LIMIT_CATEGORY_MULTIPLE"}) do
        local pattern = Restrictions.FormatToPattern(G[key])
        if pattern then p.uniquePatterns[#p.uniquePatterns + 1] = pattern end
    end
    p.bop, p.boe, p.bou = G.ITEM_BIND_ON_PICKUP, G.ITEM_BIND_ON_EQUIP, G.ITEM_BIND_ON_USE
    p.cosmetic = G.ITEM_COSMETIC
    p.setName = Restrictions.FormatToPattern(G.ITEM_SET_NAME)
    p.setBonus = Restrictions.FormatToPattern(G.ITEM_SET_BONUS)
    p.setBonusGray = Restrictions.FormatToPattern(G.ITEM_SET_BONUS_GRAY)
    p.use, p.proc = prefix(G.ITEM_SPELL_TRIGGER_ONUSE), prefix(G.ITEM_SPELL_TRIGGER_ONPROC)
    p.damage = {}
    -- school form first, the plain one reads "133 Frost" as the high number
    for _, key in ipairs({"DAMAGE_TEMPLATE_WITH_SCHOOL", "DAMAGE_TEMPLATE", "SINGLE_DAMAGE_TEMPLATE"}) do
        local pattern = Restrictions.FormatToPattern(G[key])
        if pattern then p.damage[#p.damage + 1] = pattern end
    end
    if type(lineTypes) == "table" then
        p.useType, p.procType = lineTypes.ItemSpellTriggerOnUse, lineTypes.ItemSpellTriggerOnProc
    end
    return p
end

-- some languages have their own comma
function Restrictions.SplitList(text)
    local list = {}
    text = text:gsub("\227\128\129", ","):gsub("\239\188\140", ",")
    for part in (text .. ","):gmatch("(.-),") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then list[#list + 1] = part end
    end
    return list
end

local function number(text)
    if not text then return nil end
    return tonumber((text:gsub(",", ".")))
end

-- lines: {{left, right, type}}
function Restrictions.ParseLines(lines, patternSets)
    local out = {setBonuses = {}}
    local inSet = false
    for index, line in ipairs(lines or {}) do
        local left, right = stripCodes(line.leftText), stripCodes(line.rightText)
        for _, p in ipairs(patternSets) do
            if not out.classes and p.classes then
                local list = left:match(p.classes)
                if list then out.classes = Restrictions.SplitList(list) end
            end
            if not out.races and p.races then
                local list = left:match(p.races)
                if list then out.races = Restrictions.SplitList(list) end
            end
            local levelLine = p.minLevel and left:match(p.minLevel)
            if not out.minLevel and levelLine then out.minLevel = number(levelLine) end
            if not out.reqSkill and p.reqSkill and not levelLine
              and not (p.reqReputation and left:match(p.reqReputation)) then
                local text = left:match(p.reqSkill)
                if text then
                    local name, rank = text:match("^(.-)%s*%((%d+)%)$")
                    out.reqSkill = {name = name or text, rank = tonumber(rank)}
                end
            end
            if not out.unique then
                if p.uniqueExact[left] then
                    out.unique = p.uniqueExact[left] == "ITEM_UNIQUE_EQUIPPABLE" and "equipped" or "unique"
                else
                    for _, pattern in ipairs(p.uniquePatterns) do
                        if left:match(pattern) then out.unique = "unique" end
                    end
                end
            end
            if p.cosmetic and left == p.cosmetic then out.cosmetic = true end
            if not out.bind then
                if left == p.bop then
                    out.bind = "BOP"
                elseif left == p.boe then
                    out.bind = "BOE"
                elseif left == p.bou then
                    out.bind = "BOU"
                end
            end
            -- right half of the damage line, the label differs between clients
            if not out.speed and right ~= "" then
                for _, pattern in ipairs(p.damage) do
                    local low, high = left:match(pattern)
                    if low then
                        out.speed = number(right:match("(%d+[%.,]%d+)"))
                        low, high = number(low:match("[%d%.,]+")), high and number(high:match("[%d%.,]+"))
                        if out.speed and out.speed > 0 and low then
                            out.dps = (low + (high or low)) / 2 / out.speed
                        end
                        break
                    end
                end
            end
            -- Equip lines are skipped, GetItemStats has those
            if (p.useType and line.type == p.useType) or (p.use and left:sub(1, #p.use) == p.use) then
                out.hasUse = true
            end
            if (p.procType and line.type == p.procType) or (p.proc and left:sub(1, #p.proc) == p.proc) then
                out.hasProc = true
            end
            if not out.setName and p.setName and index > 1 then
                local name, _, total = left:match(p.setName)
                if name and tonumber(total) then
                    out.setName, out.setTotal = name, tonumber(total)
                    inSet = true
                end
            end
            if inSet and p.setBonus and (left:match(p.setBonus) or (p.setBonusGray and left:match(p.setBonusGray))) then
                if out.setBonuses[#out.setBonuses] ~= left then out.setBonuses[#out.setBonuses + 1] = left end
            end
        end
    end
    return out
end

function Restrictions.TipLines(tip)
    local lines = {}
    if type(tip) ~= "table" then return lines end
    for _, entry in ipairs(tip) do
        if type(entry) == "string" then
            lines[#lines + 1] = {leftText = entry}
        elseif type(entry) == "table" then
            lines[#lines + 1] = {leftText = entry[1], rightText = entry[2]}
        end
    end
    -- no name line in a tip, so the set line can't be first
    table.insert(lines, 1, {leftText = ""})
    return lines
end

function Restrictions.NameSet(names)
    local set = {}
    for _, name in ipairs(names) do if type(name) == "string" and name ~= "" then set[name:lower()] = true end end
    return set
end

function Restrictions.ExcludesName(list, nameSet)
    if not list then return false end
    for _, name in ipairs(list) do if nameSet[name:lower()] then return false end end
    return true
end
