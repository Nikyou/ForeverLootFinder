local _, ns = ...
local L = ns.L

local TIERS = {
    {max = 74, label = L["Apprentice (1–74)"]},
    {max = 149, label = L["Journeyman (75–149)"]},
    {max = 224, label = L["Expert (150–224)"]},
    {max = 299, label = L["Artisan (225–299)"]},
    {max = math.huge, label = L["Master (300+)"]},
}

local function tierOf(skill)
    if not skill then return #TIERS + 1, L["Skill unknown"] end
    for i, tier in ipairs(TIERS) do if skill <= tier.max then return i, tier.label end end
end

local function entries(_, order, ctx, _)
    local learned = ctx.professions or {}
    local learnedFirst = ns.addon.db.profile.craftTab.learnedFirst ~= false
    table.sort(order, function(a, b)
        if learnedFirst then
            local la, lb = learned[a.key] ~= nil, learned[b.key] ~= nil
            if la ~= lb then return la end
        end
        if a.order ~= b.order then return a.order < b.order end
        return a.title < b.title
    end)
    local list = {}
    for _, card in ipairs(order) do
        local rank = learned[card.key]
        local info = {}
        if rank then info[#info + 1] = format(L["your skill %d"], rank) end
        info[#info + 1] = format(L["%d items"], card.items)
        list[#list + 1] = {
            title = card.title,
            info = table.concat(info, "   "),
            glow = rank ~= nil,
            fillTooltip = function(tooltip)
                tooltip:AddLine(card.title)
                if rank then
                    tooltip:AddLine(format(L["Learned (skill %d)."], rank), 1, 1, 1)
                else
                    tooltip:AddLine(L["Not learned: the filter hides its BoP items."],
                                    1, 1, 1, true)
                end
            end,
            groups = card.list,
        }
    end
    return list
end

ns.Cards.Tab({
    key = "crafts",
    label = L["Professions"],
    accept = function(source) return source.kind == "craft" end,
    card = function(source)
        local key = source.profession
        local profession = type(key) == "number" and ns.Crafts.BY_ID[key]
        local title = source.professionName or (type(key) == "number" and ns.Crafts.Name(key)) or tostring(key)
        return key, title, profession and profession.order or 99
    end,
    group = function(source)
        local tier, label = tierOf(source.skill)
        return tier, label, tier
    end,
    grouping = {
        label = L["Group by skill"],
        get = function(profile) return profile.craftTab.bySkill == true end,
        set = function(profile, on) profile.craftTab.bySkill = on end,
    },
    entries = entries,
    emptyHint = function()
        if ns.Crafts.Installed() or ns.ForeverDB.Installed() or ns.ATT.Installed() or ns.SkillUp.Installed() then
            return nil
        end
        return L["Install forever-db for all crafted items, or open your professions once."]
    end,
})
