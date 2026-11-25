-- only what differs from showing everything
local _, ns = ...
local L = ns.L
local Labels = ns.Labels
local FilterBar = ns.FilterBar

-- "Max required level: 45 (your level + 5)"
function FilterBar.LevelText(f, ctx)
    local limit = f.maxLevel
    if not limit.on then return L["Max required level: off"] end
    if limit.mode == "fixed" then return format(L["Max required level: %d"], limit.fixed) end
    local whose = ctx.ownCharacter == false and L["their level"] or L["your level"]
    return format(L["Max required level: %d (%s + %d)"], ns.Filter.MaxLevel(f, ctx.level), whose, limit.plus)
end

local function typeNames(set, order)
    local names = {}
    for _, key in ipairs(order) do if set[key] then names[#names + 1] = Labels.Type(key) end end
    return names
end

function FilterBar.Summary(f, ctx)
    local parts = {}
    local function add(text) parts[#parts + 1] = text end

    local armor = typeNames(ctx.armor, ns.Classes.ARMOR_TYPES)
    add(#armor > 0 and table.concat(armor, ", ") or L["no armor"])
    local weapons = typeNames(ctx.weapons, ns.Classes.WEAPON_TYPES)
    add(#weapons <= 3 and (#weapons > 0 and table.concat(weapons, ", ") or L["no weapons"])
          or format(L["%d weapon types"], #weapons))
    local wants, excludes = {}, {}
    for _, stat in ipairs(ns.StatMap.STATS) do
        local mode = f.stats[stat.key]
        if mode == 1 then wants[#wants + 1] = Labels.Stat(stat.key) end
        if mode == -1 then excludes[#excludes + 1] = Labels.Stat(stat.key) end
    end
    if #wants > 0 then add(format(f.statMode == "ALL" and L["All of: %s"] or L["Any of: %s"], table.concat(wants, ", "))) end
    if #excludes > 0 then add(format(L["Without: %s"], table.concat(excludes, ", "))) end
    if f.maxLevel.on then add(FilterBar.LevelText(f, ctx)) end

    for _, key in ipairs(FilterBar.CHECK_ORDER) do
        local spec = FilterBar.CHECKS[key]
        local text = spec.summary and spec.summary[FilterBar.CheckValue(f, spec)]
        if text and (not spec.summaryIf or spec.summaryIf(f)) and (not spec.shown or spec.shown()) then add(text) end
    end

    if f.dungeonLevel.on then add(format(L["dungeons %d–%d"], f.dungeonLevel.min, f.dungeonLevel.max)) end
    if f.bind == "BOP" then
        add(L["BoP only"])
    elseif f.bind == "BOE" then
        add(L["BoE only"])
    end
    if f.speed.on then add(format(L["speed %.1f–%.1f"], f.speed.min, f.speed.max)) end
    if f.chance and f.chance.on then
        add(format(L["drop chance %s or more"], Labels.Chance(f.chance.min or 0)))
        if f.chance.keepUnknown == false then add(L["no unknown chances"]) end
    end
    if f.price and f.price.maxOn and ns.Auctionator.Active() then
        add(format(L["auction price up to %s"], ns.Util.Money((f.price.max or 0) * 10000)))
    end
    if (f.minQuality or 0) > 0 then add(format(L["%s or better"], Labels.Quality(f.minQuality))) end
    local raids = ns.Index.RAIDS_OPEN and ns.PlacesDropdown.Count(f.raids) or nil
    local dungeons = ns.PlacesDropdown.Count(f.dungeons)
    if raids then add(format(L["%d raids"], raids)) end
    if dungeons then add(format(L["%d dungeons"], dungeons)) end
    if f.search and f.search ~= "" then add(format(L["name has \"%s\""], f.search)) end
    return Labels.Join(parts, "  ")
end
