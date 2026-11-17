local _, ns = ...

local Classes = {}
ns.Classes = Classes

Classes.ORDER = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}
Classes.ARMOR_TYPES = {"CLOTH", "LEATHER", "MAIL", "PLATE"}
Classes.WEAPON_TYPES = {
    "SWORD1H", "SWORD2H", "AXE1H", "AXE2H", "MACE1H", "MACE2H", "DAGGER", "FIST", "POLEARM", "STAFF", "BOW", "GUN", "CROSSBOW",
    "WAND", "THROWN", "SHIELD", "HELD", "LIBRAM", "IDOL", "TOTEM",
}
Classes.RELIC_CLASS = {LIBRAM = "PALADIN", IDOL = "DRUID", TOTEM = "SHAMAN"}

local ARMOR_RANK = {CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4}

-- weapons as if every skill were learned. Forever differs from classic here: rogue axes, shaman two-handers
-- without the talent, druid polearms
local DATA = {
    WARRIOR = {
        armor = {{1, "MAIL"}, {40, "PLATE"}},
        weapons = {
            "SWORD1H", "SWORD2H", "AXE1H", "AXE2H", "MACE1H", "MACE2H", "DAGGER", "FIST", "POLEARM", "STAFF", "BOW", "GUN",
            "CROSSBOW", "THROWN", "SHIELD", "HELD",
        },
    },
    PALADIN = {
        armor = {{1, "MAIL"}, {40, "PLATE"}},
        weapons = {"SWORD1H", "SWORD2H", "AXE1H", "AXE2H", "MACE1H", "MACE2H", "POLEARM", "SHIELD", "HELD", "LIBRAM"},
    },
    -- hunters get thrown on Forever
    HUNTER = {
        armor = {{1, "LEATHER"}, {40, "MAIL"}},
        weapons = {
            "SWORD1H", "SWORD2H", "AXE1H", "AXE2H", "DAGGER", "FIST", "POLEARM", "STAFF", "BOW", "GUN", "CROSSBOW", "THROWN",
            "HELD",
        },
    },
    ROGUE = {
        armor = {{1, "LEATHER"}},
        weapons = {"SWORD1H", "AXE1H", "MACE1H", "DAGGER", "FIST", "BOW", "GUN", "CROSSBOW", "THROWN", "HELD"},
    },
    PRIEST = {armor = {{1, "CLOTH"}}, weapons = {"MACE1H", "DAGGER", "STAFF", "WAND", "HELD"}},
    SHAMAN = {
        armor = {{1, "LEATHER"}, {40, "MAIL"}},
        weapons = {"AXE1H", "AXE2H", "MACE1H", "MACE2H", "DAGGER", "FIST", "STAFF", "SHIELD", "HELD", "TOTEM"},
    },
    MAGE = {armor = {{1, "CLOTH"}}, weapons = {"SWORD1H", "DAGGER", "STAFF", "WAND", "HELD"}},
    WARLOCK = {armor = {{1, "CLOTH"}}, weapons = {"SWORD1H", "DAGGER", "STAFF", "WAND", "HELD"}},
    DRUID = {armor = {{1, "LEATHER"}}, weapons = {"MACE1H", "MACE2H", "DAGGER", "FIST", "POLEARM", "STAFF", "HELD", "IDOL"}},
}

function Classes.BestArmor(class, level)
    local data = DATA[class]
    if not data then return nil end
    local best
    for _, step in ipairs(data.armor) do if (level or 1) >= step[1] then best = step[2] end end
    return best
end

function Classes.CanEverWear(class, armorType)
    local data = DATA[class]
    if not data or not ARMOR_RANK[armorType] then return true end
    local top = data.armor[#data.armor][2]
    return ARMOR_RANK[armorType] <= ARMOR_RANK[top]
end

-- every lighter type too, a holy paladin may well want cloth
function Classes.ArmorPreselect(class, level)
    local best = Classes.BestArmor(class, level)
    local set = {}
    for _, armorType in ipairs(Classes.ARMOR_TYPES) do
        if not best or ARMOR_RANK[armorType] <= ARMOR_RANK[best] then set[armorType] = true end
    end
    return set
end

function Classes.WeaponPreselect(class)
    local set = {}
    local data = DATA[class]
    if not data then
        for _, weaponType in ipairs(Classes.WEAPON_TYPES) do set[weaponType] = true end
        return set
    end
    for _, weaponType in ipairs(data.weapons) do set[weaponType] = true end
    return set
end

function Classes.CanEverUse(class, weaponType)
    local data = DATA[class]
    if not data or not weaponType then return true end
    for _, known in ipairs(data.weapons) do if known == weaponType then return true end end
    return false
end
