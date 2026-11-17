-- GetItemStats keys as of 1.60.1. Forever merged melee, ranged and spell ratings, so they fold into one stat
local _, ns = ...

local StatMap = {}
ns.StatMap = StatMap

-- parent: counts as that stat too
StatMap.STATS = {
    {key = "STR", label = "ITEM_MOD_STRENGTH_SHORT", group = "primary"},
    {key = "AGI", label = "ITEM_MOD_AGILITY_SHORT", group = "primary"},
    {key = "STA", label = "ITEM_MOD_STAMINA_SHORT", group = "primary"},
    {key = "INT", label = "ITEM_MOD_INTELLECT_SHORT", group = "primary"},
    {key = "SPI", label = "ITEM_MOD_SPIRIT_SHORT", group = "primary"},
    {key = "HEAL", label = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", group = "spell"},
    {key = "SPELLDMG", label = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", group = "spell"},
    {key = "ARCANEDMG", label = "ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT", group = "spell", parent = "SPELLDMG"},
    {key = "FIREDMG", label = "ITEM_MOD_FIRE_DAMAGE_DONE_SHORT", group = "spell", parent = "SPELLDMG"},
    {key = "FROSTDMG", label = "ITEM_MOD_FROST_DAMAGE_DONE_SHORT", group = "spell", parent = "SPELLDMG"},
    {key = "HOLYDMG", label = "ITEM_MOD_HOLY_DAMAGE_DONE_SHORT", group = "spell", parent = "SPELLDMG"},
    {key = "NATUREDMG", label = "ITEM_MOD_NATURE_DAMAGE_DONE_SHORT", group = "spell", parent = "SPELLDMG"},
    {key = "SHADOWDMG", label = "ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT", group = "spell", parent = "SPELLDMG"},
    {key = "SPELLPEN", label = "ITEM_MOD_SPELL_PENETRATION_SHORT", group = "spell"},
    {key = "MP5", label = "ITEM_MOD_POWER_REGEN0_SHORT", group = "spell"},
    {key = "AP", label = "ITEM_MOD_ATTACK_POWER_SHORT", group = "physical"},
    {key = "RAP", label = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", group = "physical"},
    {key = "FERALAP", label = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT", group = "physical"},
    {key = "HIT", label = "ITEM_MOD_HIT_RATING_SHORT", group = "physical"},
    {key = "CRIT", label = "ITEM_MOD_CRIT_RATING_SHORT", group = "physical"},
    {key = "HASTE", label = "ITEM_MOD_HASTE_RATING_SHORT", group = "physical"},
    {key = "ARMORPEN", label = "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", group = "physical"},
    {key = "EXPERTISE", label = "ITEM_MOD_EXPERTISE_RATING_SHORT", group = "physical"},
    {key = "WEAPONSKILL", label = nil, fallback = "Weapon skill", group = "physical"},
    {key = "DPS", label = nil, fallback = "Weapon DPS", group = "physical"},
    {key = "DEFENSE", label = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", group = "tank"},
    {key = "BLOCK", label = "ITEM_MOD_BLOCK_RATING_SHORT", group = "tank"},
    {key = "BLOCKVALUE", label = "ITEM_MOD_BLOCK_VALUE_SHORT", group = "tank"},
    {key = "DODGE", label = "ITEM_MOD_DODGE_RATING_SHORT", group = "tank"},
    {key = "PARRY", label = "ITEM_MOD_PARRY_RATING_SHORT", group = "tank"},
    {key = "ARMOR", label = "RESISTANCE0_NAME", group = "tank"},
    {key = "BONUSARMOR", label = "ITEM_MOD_EXTRA_ARMOR_SHORT", group = "tank"},
    {key = "HEALTH", label = "ITEM_MOD_HEALTH_SHORT", group = "tank"},
    {key = "HP5", label = "ITEM_MOD_HEALTH_REGEN_SHORT", group = "tank"},
    {key = "MANA", label = "ITEM_MOD_MANA_SHORT", group = "spell"},
    {key = "ARCANERES", label = "RESISTANCE6_NAME", group = "resist"},
    {key = "FIRERES", label = "RESISTANCE2_NAME", group = "resist"},
    {key = "FROSTRES", label = "RESISTANCE4_NAME", group = "resist"},
    {key = "NATURERES", label = "RESISTANCE3_NAME", group = "resist"},
    {key = "SHADOWRES", label = "RESISTANCE5_NAME", group = "resist"},
}

StatMap.BY_KEY = {}
for index, stat in ipairs(StatMap.STATS) do
    stat.order = index
    StatMap.BY_KEY[stat.key] = stat
end

local RESISTS = {"ARCANERES", "FIRERES", "FROSTRES", "NATURERES", "SHADOWRES"}

-- a list folds one client key into several stats
StatMap.MAP = {
    ITEM_MOD_STRENGTH_SHORT = "STR",
    ITEM_MOD_AGILITY_SHORT = "AGI",
    ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT",
    ITEM_MOD_SPIRIT_SHORT = "SPI",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SPELLDMG",
    ITEM_MOD_SPELL_POWER_SHORT = {"SPELLDMG", "HEAL"},
    ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "ARCANEDMG",
    ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "FIREDMG",
    ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "FROSTDMG",
    ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "HOLYDMG",
    ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "NATUREDMG",
    ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "SHADOWDMG",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELLPEN",
    ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FERALAP",
    ITEM_MOD_HIT_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT",
    ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "CRIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_RANGED_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ARMORPEN",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEFENSE",
    ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
    ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
    ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
    RESISTANCE0_NAME = "ARMOR",
    ITEM_MOD_EXTRA_ARMOR_SHORT = "BONUSARMOR",
    ITEM_MOD_HEALTH_SHORT = "HEALTH",
    ITEM_MOD_MANA_SHORT = "MANA",
    ITEM_MOD_HEALTH_REGEN_SHORT = "HP5",
    ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
    RESISTANCE2_NAME = "FIRERES",
    RESISTANCE3_NAME = "NATURERES",
    RESISTANCE4_NAME = "FROSTRES",
    RESISTANCE5_NAME = "SHADOWRES",
    RESISTANCE6_NAME = "ARCANERES",
    ITEM_MOD_SPELL_RESISTANCE_ALL_SCHOOLS_SHORT = RESISTS,
    ITEM_MOD_TWOHANDED_AXES_SHORT = "WEAPONSKILL",
    ITEM_MOD_TWOHANDED_MACES_SHORT = "WEAPONSKILL",
    ITEM_MOD_TWOHANDED_SWORDS_SHORT = "WEAPONSKILL",
    ITEM_MOD_AXES_SHORT = "WEAPONSKILL",
    ITEM_MOD_BOWS_SHORT = "WEAPONSKILL",
    ITEM_MOD_CROSSBOWS_SHORT = "WEAPONSKILL",
    ITEM_MOD_DAGGERS_SHORT = "WEAPONSKILL",
    ITEM_MOD_DUAL_WIELD_SHORT = "WEAPONSKILL",
    ITEM_MOD_FIST_WEAPONS_SHORT = "WEAPONSKILL",
    ITEM_MOD_GUNS_SHORT = "WEAPONSKILL",
    ITEM_MOD_MACES_SHORT = "WEAPONSKILL",
    ITEM_MOD_POLEARMS_SHORT = "WEAPONSKILL",
    ITEM_MOD_STAVES_SHORT = "WEAPONSKILL",
    ITEM_MOD_SWORDS_SHORT = "WEAPONSKILL",
    ITEM_MOD_THROWN_SHORT = "WEAPONSKILL",
    ITEM_MOD_WANDS_SHORT = "WEAPONSKILL",
}

-- second result: keys with no stat of ours
function StatMap.Convert(raw)
    local stats, other = {}, {}
    if type(raw) ~= "table" then return stats, other end
    for key, value in pairs(raw) do
        if type(key) == "string" and type(value) == "number" and value ~= 0 then
            local target = StatMap.MAP[key]
            if type(target) == "table" then
                for _, stat in ipairs(target) do stats[stat] = (stats[stat] or 0) + value end
            elseif target then
                stats[target] = (stats[target] or 0) + value
            else
                other[key] = value
            end
        end
    end
    return stats, other
end

-- generic spell damage counts for every school
function StatMap.Value(stats, key)
    if not stats then return nil end
    local value = stats[key] or 0
    local stat = StatMap.BY_KEY[key]
    if stat and stat.parent then value = value + (stats[stat.parent] or 0) end
    return value
end
