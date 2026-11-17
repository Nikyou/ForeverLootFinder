-- the client's own strings where it has them, so most of the UI is translated for free
local _, ns = ...
local L = ns.L

local Labels = {}

function Labels.Chance(percent)
    if type(percent) ~= "number" then return "" end
    if percent >= 10 or percent == math.floor(percent) then return format("%d%%", math.floor(percent + 0.5)) end
    return format("%.1f%%", percent)
end
ns.Labels = Labels

Labels.BADGES = {
    {key = "rare", label = L["Rare"], color = "ffa335ee"},
    {key = "trash", label = L["Trash"], color = "ff9d9d9d"},
    {key = "shared", label = L["Shared"], color = "ff40c0ff"},
    {key = "quest", label = L["Quest"], color = "ffffd100"},
    {key = "craft", label = L["Crafted"], color = "ffff9a3c"},
    {key = "probable", label = L["Unconfirmed"], color = "ffff7f50"},
    {key = "random", label = L["Random bonus"], color = "ff1eff00"},
    {key = "faction", label = L["Faction"], color = "ffff4040"},
    {key = "notInGame", label = L["Not in game data yet"], color = "ffff4040"},
    {key = "owned", label = L["Owned"], color = "ff80ff80"},
    {key = "boe", label = L["BoE"], color = "ff00ccff"},
    {key = "unique", label = L["Unique"], color = "ffffffff"},
    {key = "set", label = L["Set"], color = "ffffd100"},
    {key = "vendor", label = L["Vendor"], color = "ffc0e080"},
    {key = "creature", label = L["Creature"], color = "ffd08060"},
}

-- the ruRU, koKR and zh fonts have no middle dot. "||" is an escaped "|"
local DOT_FONTS = {enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, ptBR = true, itIT = true}
Labels.DOT = (not GetLocale or DOT_FONTS[GetLocale()]) and "·" or "||"
function Labels.Join(parts, pad)
    pad = pad or " "
    return table.concat(parts, pad .. Labels.DOT .. pad)
end

local function global(name)
    local value = name and _G[name]
    if type(value) == "string" and value ~= "" and not ns.IsSecret(value) then return value end
    return nil
end

local SLOT_GLOBALS = {
    HEAD = "INVTYPE_HEAD",
    NECK = "INVTYPE_NECK",
    SHOULDER = "INVTYPE_SHOULDER",
    BACK = "INVTYPE_CLOAK",
    CHEST = "INVTYPE_CHEST",
    WRIST = "INVTYPE_WRIST",
    HANDS = "INVTYPE_HAND",
    WAIST = "INVTYPE_WAIST",
    LEGS = "INVTYPE_LEGS",
    FEET = "INVTYPE_FEET",
    FINGER = "INVTYPE_FINGER",
    TRINKET = "INVTYPE_TRINKET",
    ONEHAND = "INVTYPE_WEAPON",
    MAINHAND = "INVTYPE_WEAPONMAINHAND",
    TWOHAND = "INVTYPE_2HWEAPON",
    OFFHAND = "INVTYPE_WEAPONOFFHAND",
    RANGED = "INVTYPE_RANGED",
    RELIC = "INVTYPE_RELIC",
}
local SLOT_FALLBACK = {
    HEAD = L["Head"],
    NECK = L["Neck"],
    SHOULDER = L["Shoulder"],
    BACK = L["Back"],
    CHEST = L["Chest"],
    WRIST = L["Wrist"],
    HANDS = L["Hands"],
    WAIST = L["Waist"],
    LEGS = L["Legs"],
    FEET = L["Feet"],
    FINGER = L["Finger"],
    TRINKET = L["Trinket"],
    ONEHAND = L["One-hand"],
    MAINHAND = L["Main hand"],
    TWOHAND = L["Two-hand"],
    OFFHAND = L["Off hand"],
    RANGED = L["Ranged"],
    RELIC = L["Relic"],
}

function Labels.Slot(slot) return global(SLOT_GLOBALS[slot]) or SLOT_FALLBACK[slot] or slot end

local TYPE_CLASS = {
    CLOTH = {4, 1},
    LEATHER = {4, 2},
    MAIL = {4, 3},
    PLATE = {4, 4},
    SHIELD = {4, 6},
    LIBRAM = {4, 7},
    IDOL = {4, 8},
    TOTEM = {4, 9},
    AXE1H = {2, 0},
    AXE2H = {2, 1},
    BOW = {2, 2},
    GUN = {2, 3},
    MACE1H = {2, 4},
    MACE2H = {2, 5},
    POLEARM = {2, 6},
    SWORD1H = {2, 7},
    SWORD2H = {2, 8},
    STAFF = {2, 10},
    FIST = {2, 13},
    DAGGER = {2, 15},
    THROWN = {2, 16},
    CROSSBOW = {2, 18},
    WAND = {2, 19},
}
local TYPE_FALLBACK = {
    CLOTH = L["Cloth"],
    LEATHER = L["Leather"],
    MAIL = L["Mail"],
    PLATE = L["Plate"],
    SHIELD = L["Shield"],
    HELD = L["Held in off-hand"],
    LIBRAM = L["Libram"],
    IDOL = L["Idol"],
    TOTEM = L["Totem"],
    AXE1H = L["One-handed axe"],
    AXE2H = L["Two-handed axe"],
    BOW = L["Bow"],
    GUN = L["Gun"],
    MACE1H = L["One-handed mace"],
    MACE2H = L["Two-handed mace"],
    POLEARM = L["Polearm"],
    SWORD1H = L["One-handed sword"],
    SWORD2H = L["Two-handed sword"],
    STAFF = L["Staff"],
    FIST = L["Fist weapon"],
    DAGGER = L["Dagger"],
    THROWN = L["Thrown"],
    CROSSBOW = L["Crossbow"],
    WAND = L["Wand"],
}

local typeCache = {}
function Labels.Type(itemType)
    if not itemType then return nil end
    if typeCache[itemType] then return typeCache[itemType] end
    local label
    if itemType == "HELD" then
        label = global("INVTYPE_HOLDABLE")
    else
        local ids = TYPE_CLASS[itemType]
        if ids and C_Item and C_Item.GetItemSubClassInfo then
            local ok, name = pcall(C_Item.GetItemSubClassInfo, ids[1], ids[2])
            if ok and type(name) == "string" and name ~= "" and not ns.IsSecret(name) then label = name end
        end
    end
    label = label or TYPE_FALLBACK[itemType] or itemType
    typeCache[itemType] = label
    return label
end

-- stats with no client string of their own
local STAT_FALLBACK = {WEAPONSKILL = L["Weapon skill"], DPS = L["Weapon DPS"]}

function Labels.Stat(key)
    local stat = ns.StatMap.BY_KEY[key]
    if not stat then return global(key) or key end
    return global(stat.label) or STAT_FALLBACK[key] or key
end

function Labels.OtherStat(clientKey) return global(clientKey) or clientKey end

function Labels.Quality(quality) return global("ITEM_QUALITY" .. tostring(quality) .. "_DESC") or tostring(quality) end

function Labels.QualityHex(quality)
    if quality and C_Item and C_Item.GetItemQualityColor then
        local ok, _, _, _, hex = pcall(C_Item.GetItemQualityColor, quality)
        if ok and type(hex) == "string" and not ns.IsSecret(hex) then return "|c" .. hex end
    end
    local colors = rawget(_G, "ITEM_QUALITY_COLORS")
    local color = colors and quality and colors[quality]
    if color and color.hex then return color.hex end
    return "|cffffffff"
end

function Labels.QualityRGB(quality)
    if quality and C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok and type(r) == "number" and not ns.IsSecret(r) then return r, g, b end
    end
    return 1, 1, 1
end

function Labels.ItemKind(record, info)
    if not info.slot then return record.slotText and ns.Source.SlotName(record.slotText) or "" end
    local slot = Labels.Slot(info.slot)
    local itemType = Labels.Type(info.itemType)
    if itemType and itemType ~= slot then return slot .. " " .. Labels.DOT .. " " .. itemType end
    return slot
end

-- armor and DPS have their own columns
local SKIP = {ARMOR = true, DPS = true}
function Labels.StatLine(stats, count)
    if not stats then return nil end
    local list = {}
    for key, value in pairs(stats) do if not SKIP[key] and value ~= 0 then list[#list + 1] = {key = key, value = value} end end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return ns.StatMap.BY_KEY[a.key].order < ns.StatMap.BY_KEY[b.key].order
    end)
    local parts = {}
    for i = 1, math.min(count or 4, #list) do
        parts[#parts + 1] = format("+%s %s", Labels.Number(list[i].value), Labels.Stat(list[i].key))
    end
    return table.concat(parts, ", ")
end

function Labels.Number(value)
    if value == math.floor(value) then return tostring(value) end
    return format("%.1f", value)
end
