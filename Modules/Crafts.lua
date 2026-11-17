-- AtlasLoot's crafting lists, plus whatever the profession window shows that AtlasLoot lacks
local _, ns = ...
local L = ns.L
local Util = ns.Util

local Crafts = {}
ns.Crafts = Crafts

local CRAFTING_MODULE = "AtlasLootClassic_Crafting"
local LOAD_DELAY = 3 -- keep it out of the loading screen

Crafts.PROFESSIONS = {
    {id = 164, name = "Blacksmithing", label = L["Blacksmithing"]},
    {id = 165, name = "Leatherworking", label = L["Leatherworking"]},
    {id = 197, name = "Tailoring", label = L["Tailoring"]},
    {id = 202, name = "Engineering", label = L["Engineering"]},
    {id = 333, name = "Enchanting", label = L["Enchanting"]},
    {id = 171, name = "Alchemy", label = L["Alchemy"]},
    {id = 755, name = "Jewelcrafting", label = L["Jewelcrafting"]},
    {id = 185, name = "Cooking", label = L["Cooking"]},
    {id = 129, name = "First Aid", label = L["First Aid"]},
    {id = 186, name = "Mining", label = L["Mining"]},
    {id = 182, name = "Herbalism", label = L["Herbalism"]},
    {id = 393, name = "Skinning", label = L["Skinning"]},
    {id = 356, name = "Fishing", label = L["Fishing"]},
}
Crafts.BY_ID = {}
for order, profession in ipairs(Crafts.PROFESSIONS) do
    profession.order = order
    Crafts.BY_ID[profession.id] = profession
end
-- AtlasLoot has its own numbers (Data\Profession.lua)
local ATLASLOOT_PROFESSION = {
    [1] = 129, [2] = 164, [3] = 165, [4] = 171, [5] = 182, [6] = 185, [7] = 186, [8] = 197, [9] = 202, [10] = 333,
    [11] = 356, [12] = 393, [14] = 755,
}

local atlasEntries = {}
local status = Util.NewStatus("atlasloot crafts", {sections = 0, spells = 0, equippable = 0, missing = 0, ms = 0})
local stats = status.counts

local isSecret = Util.IsSecret
local equippable = Util.Equippable

local function professionData()
    local al = ns.AtlasLoot.Get()
    local data = al and type(al.Data) == "table" and al.Data
    return data and type(data.Profession) == "table" and data or nil
end

function Crafts.Installed() return ns.AtlasLoot.Installed() and professionData() ~= nil end
function Crafts.Enabled() return ns.AtlasLoot.Enabled() end
function Crafts.State() return status.state end
function Crafts.Stats() return stats end
function Crafts.Status() return status end

-- only the game's name is kept, early on it may not know the profession yet
local nameCache = {}
local nameToID -- lower-case name in any language, for "Requires Engineering"
function Crafts.Name(id)
    if nameCache[id] then return nameCache[id] end
    if C_SkillInfo then
        local info = Util.SafeCall(C_SkillInfo.GetSkillLineInfoByID, id)
        if type(info) == "table" and type(info.name) == "string" and not isSecret(info.name) and info.name ~= "" then
            nameCache[id] = info.name
            if nameToID and Crafts.BY_ID[id] then nameToID[info.name:lower()] = id end
            return info.name
        end
    end
    local profession = Crafts.BY_ID[id]
    return profession and profession.label or tostring(id)
end

-- header rows have a string. Mining and Fishing list items, not spells
local function collect(data, storage, found, checkpoint)
    local Profession, Recipe = data.Profession, data.Recipe
    local seen = {}
    for contentKey, content in pairs(storage) do
        if type(content) == "table" and type(content.items) == "table" then
            for sectionIndex, section in ipairs(content.items) do
                if type(section) == "table" then
                    stats.sections = stats.sections + 1
                    for key, rows in pairs(section) do
                        if type(key) == "number" and type(rows) == "table" then
                            for _, row in ipairs(rows) do
                                local spell = type(row) == "table" and row[2]
                                if type(spell) == "number" and not seen[spell] then
                                    seen[spell] = true
                                    local ok, result = pcall(Profession.GetProfessionData, spell)
                                    if ok and type(result) == "table" and type(result[1]) == "number" then
                                        stats.spells = stats.spells + 1
                                        local itemID = result[1]
                                        if equippable(itemID) then
                                            stats.equippable = stats.equippable + 1
                                            local profession = ATLASLOOT_PROFESSION[result[2]]
                                            local recipe = Recipe and Util.SafeCall(Recipe.GetRecipeForSpell, spell)
                                            found[#found + 1] = {
                                                id = itemID,
                                                kind = "craft",
                                                profession = profession or ("al:" .. tostring(result[2])),
                                                skill = type(result[3]) == "number" and result[3] or nil,
                                                spell = spell,
                                                recipe = type(recipe) == "number" and recipe or nil,
                                                section = type(section.name) == "string" and section.name or nil,
                                                alModule = CRAFTING_MODULE,
                                                alContent = contentKey,
                                                alBoss = sectionIndex,
                                            }
                                        end
                                    elseif ok and result == nil then
                                        stats.missing = stats.missing + 1
                                    end
                                end
                            end
                        end
                    end
                    checkpoint()
                end
            end
        end
    end
end

-- swapped in whole, an index built meanwhile keeps the last full read
local function read()
    local storage, data = ns.AtlasLoot.Storage(CRAFTING_MODULE), professionData()
    if not (storage and data) then
        status.state = "nodata"
        return
    end
    status.state, status.error = "scanning", nil
    stats.sections, stats.spells, stats.equippable, stats.missing = 0, 0, 0, 0
    local found = {}
    Util.RunSliced(function(checkpoint) collect(data, storage, found, checkpoint) end, function(ok, err, ms)
        if not ok then
            status.error = tostring(err)
            ns.ReportError(err)
        end
        stats.ms, status.ms = ms, ms
        atlasEntries = found
        status.state = #found > 0 and "done" or "nodata"
        ns.RebuildIndex()
    end)
end

-- the profession window, remembered account-wide

local function tradeStore() return ns.addon.db.global.tradeSkills end

local function professionByName(name)
    if type(name) ~= "string" or isSecret(name) then return nil end
    if not nameToID then
        nameToID = {}
        for _, profession in ipairs(Crafts.PROFESSIONS) do
            nameToID[profession.name:lower()] = profession.id
            nameToID[profession.label:lower()] = profession.id
            nameToID[Crafts.Name(profession.id):lower()] = profession.id
        end
    end
    return nameToID[name:lower()]
end

Crafts.ProfessionByName = professionByName

local function scanModern(list)
    local ui = C_TradeSkillUI
    if not (ui and ui.GetAllRecipeIDs and ui.GetBaseProfessionInfo) then return nil end
    local base = Util.SafeCall(ui.GetBaseProfessionInfo)
    local profession = type(base) == "table" and (base.professionID or professionByName(base.professionName))
    if not profession then return nil end
    local recipeIDs = Util.SafeCall(ui.GetAllRecipeIDs)
    if type(recipeIDs) ~= "table" then return nil end
    list[profession] = list[profession] or {}
    for _, recipeID in ipairs(recipeIDs) do
        local itemID
        if ui.GetRecipeSchematic then
            local schematic = Util.SafeCall(ui.GetRecipeSchematic, recipeID, false)
            itemID = type(schematic) == "table" and schematic.outputItemID or nil
        end
        if not itemID and ui.GetRecipeItemLink then
            itemID = Util.ItemIDFromLink(Util.SafeCall(ui.GetRecipeItemLink, recipeID))
        end
        if type(itemID) == "number" and equippable(itemID) then list[profession][itemID] = recipeID end
    end
    return true
end

local function scanClassic(list)
    local getLine, getCount = rawget(_G, "GetTradeSkillLine"), rawget(_G, "GetNumTradeSkills")
    local getInfo, getLink = rawget(_G, "GetTradeSkillInfo"), rawget(_G, "GetTradeSkillItemLink")
    if type(getLine) ~= "function" or type(getCount) ~= "function" or type(getLink) ~= "function" then return nil end
    local profession = professionByName(Util.SafeCall(getLine))
    if not profession then return nil end
    local count = Util.SafeCall(getCount)
    if type(count) ~= "number" then return nil end
    list[profession] = list[profession] or {}
    for i = 1, count do
        local _, kind = Util.SafeCall(getInfo, i)
        if kind ~= "header" then
            local itemID = Util.ItemIDFromLink(Util.SafeCall(getLink, i))
            if itemID and equippable(itemID) then list[profession][itemID] = true end
        end
    end
    return true
end

local function countStored(store)
    local count = 0
    for _, items in pairs(store) do for _ in pairs(items) do count = count + 1 end end
    return count
end

local tradePending = false
function Crafts.OnTradeSkill()
    if tradePending then return end
    tradePending = true
    C_Timer.After(1, function()
        tradePending = false
        ns.Guard(function()
            local store = tradeStore()
            local before = countStored(store)
            if not scanModern(store) then scanClassic(store) end
            if countStored(store) ~= before then ns.RebuildIndex() end
        end)
    end)
end

function Crafts.Entries()
    local list = {}
    if Crafts.Enabled() then
        for _, entry in ipairs(atlasEntries) do
            entry.provider = "atlasloot"
            list[#list + 1] = entry
        end
    end
    -- overlaps are settled in Index.Build
    for profession, items in pairs(tradeStore()) do
        for itemID, spell in pairs(items) do
            list[#list + 1] = {
                id = itemID,
                kind = "craft",
                provider = "tradeskill",
                profession = profession,
                spell = type(spell) == "number" and spell or nil,
            }
        end
    end
    local names = {}
    for _, entry in ipairs(list) do
        local profession = entry.profession
        if type(profession) == "number" then
            names[profession] = names[profession] or Crafts.Name(profession)
            entry.professionName = names[profession]
        end
    end
    return list
end

-- {[skill line] = rank}, nil when the client can't say

function Crafts.LearnedProfessions()
    local learned, known = {}, false
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        for _, profession in ipairs(Crafts.PROFESSIONS) do
            local info = Util.SafeCall(C_SkillInfo.GetSkillLineInfoByID, profession.id)
            if type(info) == "table" then
                known = true
                local rank = info.skillLineRank or info.rank
                if type(rank) == "number" and not isSecret(rank) and rank > 0 then learned[profession.id] = rank end
            end
        end
    end
    local count, getLine = rawget(_G, "GetNumSkillLines"), rawget(_G, "GetSkillLineInfo")
    if not known and type(count) == "function" and type(getLine) == "function" then
        local lines = Util.SafeCall(count)
        if type(lines) == "number" then
            known = true
            for i = 1, lines do
                local lineOk, name, isHeader, _, rank = pcall(getLine, i)
                local id = lineOk and not isHeader and professionByName(name)
                if id then learned[id] = type(rank) == "number" and rank or 1 end
            end
        end
    end
    return known and learned or nil
end

function Crafts.Init()
    if not (Crafts.Installed() and Crafts.Enabled()) then
        status.state = "off"
        return
    end
    status.state = "waiting"
    C_Timer.After(LOAD_DELAY, function() ns.AtlasLoot.LoadModule(CRAFTING_MODULE, read) end)
end

Crafts.SetEnabled = ns.AtlasLoot.SetEnabled
ns.AtlasLoot.AddReader(Crafts)
