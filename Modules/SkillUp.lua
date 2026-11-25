-- SkillUp Forever, through its public API (SkillUpForever.API). read-only. its crafts carry the skill a recipe needs
-- on Forever, from the client's own recipe items
local _, ns = ...

local SkillUp = {}
ns.SkillUp = SkillUp

local Util = ns.Util
local ADDON = "SkillUpForever"
-- its API is there once ForeverCore has started it (at login, or after combat) and its saved data is loaded
local POLL, POLL_FOR = 2, 120

local status = Util.NewStatus("skillup", {recipes = 0, items = 0, skills = 0, ms = 0})
local stats = status.counts
local EMPTY = {provider = "skillup", entries = {}}
local extra = EMPTY
-- [spell] = {skill, trainer}: a trainer's is SkillUp's guess from Classic's until the player has been to one
local required = {}
local appliedFor

local function api()
    local addon = rawget(_G, "SkillUpForever")
    local found = type(addon) == "table" and addon.API
    return type(found) == "table" and type(found.Recipes) == "function" and found or nil
end

function SkillUp.Installed() return Util.AddOnLoaded(ADDON) end
function SkillUp.Enabled() return ns.addon.db.profile.skillup ~= false end
function SkillUp.State() return status.state end
function SkillUp.Status() return status end
function SkillUp.Stats() return stats end
function SkillUp.Entries() return SkillUp.Enabled() and extra or EMPTY end

-- recipe items: SkillUp's, from the client. trainer recipes: ATT's, which is Forever's, before SkillUp's guess
function SkillUp.LearnedAt(spell)
    local known = SkillUp.Enabled() and required[spell]
    local att = ns.ATT.LearnedAt(spell)
    if not known then return att end
    if known[2] then return att or known[1] end
    return known[1]
end

-- ATT may finish after this did
function SkillUp.ApplySkills()
    local att = ns.ATT.State() .. tostring(ns.ATT.Enabled())
    if appliedFor == att then return end
    appliedFor = att
    for _, entry in ipairs(extra.entries) do entry.skill = SkillUp.LearnedAt(entry.spell) or entry.skill end
end

function SkillUp.Read(source, opt)
    local out, skills = {}, {}
    local counts = {recipes = 0, items = 0, skills = 0}
    local list = Util.SafeCall(source.Recipes)
    for _, spell in ipairs(type(list) == "table" and list or {}) do
        counts.recipes = counts.recipes + 1
        local need = Util.SafeCall(source.RecipeRequirement, spell)
        local skill = type(need) == "table" and tonumber(need.skill) or nil
        if skill then
            skills[spell] = {skill, need.source == "trainer"}
            counts.skills = counts.skills + 1
        end
        local recipe = Util.SafeCall(source.Recipe, spell)
        local output = type(recipe) == "table" and type(recipe.output) == "table" and tonumber(recipe.output.itemID)
        local profession = type(recipe) == "table" and tonumber(recipe.skillLineID)
        if output and profession and opt.professions[profession] and opt.equippable(output) then
            out[#out + 1] = {
                id = output,
                kind = "craft",
                profession = profession,
                skill = skill,
                spell = spell,
                recipe = need and need.source == "item" and tonumber(need.recipeItem) or nil,
            }
            counts.items = counts.items + 1
        end
        if opt.checkpoint then opt.checkpoint() end
    end
    return out, counts, skills
end

local professions = {}
for id in pairs(ns.Crafts.BY_ID) do professions[id] = true end

local function read(source)
    status.state, status.error = "scanning", nil
    local found, counts, skills
    Util.RunSliced(function(checkpoint)
        found, counts, skills = SkillUp.Read(source,
                                             {equippable = Util.Equippable, professions = professions, checkpoint = checkpoint})
    end, function(ok, err, ms)
        if not ok then
            status.error = tostring(err)
            ns.ReportError(err)
        end
        stats.ms, status.ms = ms, ms
        if found then
            for key, value in pairs(counts) do stats[key] = value end
            for _, entry in ipairs(found) do entry.professionName = ns.Crafts.Name(entry.profession) end
            extra, required, appliedFor = {provider = "skillup", entries = found}, skills, nil
        end
        status.state = found and #found > 0 and "done" or "nodata"
        ns.RebuildIndex()
    end)
end

-- "loading" until SkillUp's saved data is in
local function poll(waited)
    local source = api()
    local list, why = nil, nil
    if source then list, why = Util.SafeCall(source.Recipes) end
    if type(list) == "table" then return read(source) end
    if why == "none" or waited >= POLL_FOR then
        status.state = "nodata"
        return
    end
    C_Timer.After(POLL, function() ns.Guard(poll, waited + POLL) end)
end

function SkillUp.Init()
    if not (SkillUp.Installed() and SkillUp.Enabled()) then
        status.state = "off"
        return
    end
    status.state = "waiting"
    poll(0)
end

function SkillUp.SetEnabled(value)
    ns.addon.db.profile.skillup = value and true or false
    if value and status.state == "off" then SkillUp.Init() end
    ns.RebuildIndex()
end
