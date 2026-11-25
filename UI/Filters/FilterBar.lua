-- the filter panel. plain on/off filters are described in CHECKS
local _, ns = ...
local L = ns.L
local W, Style, Labels = ns.Widgets, ns.Style, ns.Labels

local FilterBar = {}
ns.FilterBar = FilterBar

local SLIDER_DELAY = 0.2 -- a slider drag redraws once it rests
local controls = {}
local lastCtx

local function filters() return ns.Filters() end
local function changed() ns.FireChange("filters") end
local changedSoon = W.Debounce(SLIDER_DELAY, changed)

local NEEDS = {
    questie = {"Questie", "QuestieDB"},
    atlasloot = {"AtlasLoot Classic"},
    pawn = {"Pawn", "GearQuest Forever"},
    auctionator = {"Auctionator"},
}

local function parentReason(...)
    local names = {...}
    if #names == 1 then return {reason = format(L["Turn on \"%s\" first."], names[1])} end
    return {reason = format(L["Turn on \"%s\" or \"%s\" first."], names[1], names[2])}
end

-- default: what nil means, newer switches count nil as on
local LABELS = {
    dungeon = L["Dungeon drops"],
    raid = L["Raids and world bosses"],
    quest = L["Dungeon quests"],
    zoneQuest = L["Other quests (Questie)"],
    craft = L["Crafted items"],
    craftOwnBoP = L["BoP only from my professions"],
    ownSkill = L["Hide items for other professions"],
    reputation = L["Reputation rewards"],
    pvp = L["PvP rewards"],
    chanceOn = L["Hide drops rarer than this"],
    priceMaxOn = L["Max auction price (gold)"],
}

local function dropsOn(f) return f.sources.dungeon ~= false or f.sources.raid ~= false end

local function dropPart(field, label, summary)
    return {
        field = field,
        group = "sources",
        default = false,
        label = label,
        indent = 20,
        usable = function(_, env) return env.drops, parentReason(LABELS.dungeon, LABELS.raid) end,
        summary = summary,
        summaryIf = dropsOn,
    }
end

local function atlasSource(field, label, summary)
    return {
        field = field,
        group = "sources",
        default = true,
        label = label,
        usable = function(_, env) return env.atlas, env.atlasWhy end,
        summary = {[false] = summary},
    }
end

local CHECKS = {
    special = {field = "special", default = false, label = L["Has a Use or proc effect"], summary = {[true] = L["Use or proc"]}},
    dungeon = {
        field = "dungeon",
        group = "sources",
        default = true,
        label = LABELS.dungeon,
        summary = {[false] = L["no dungeon drops"]},
    },
    raid = {
        field = "raid",
        group = "sources",
        default = true,
        label = LABELS.raid,
        usable = function(_, env) return env.atlas and env.hasRaids, env.atlasWhy end,
        summary = {[false] = L["no raids"]},
    },
    rare = dropPart("rare", L["Rare spawns"], {[false] = L["no rares"]}),
    trash = dropPart("trash", L["Trash drops"], {[false] = L["no trash"]}),
    shared = dropPart("shared", L["Shared loot (low chance)"], {[false] = L["no shared loot"]}),
    probable = dropPart("probable", L["Unconfirmed drops"], {[true] = L["with unconfirmed"]}),
    quest = {
        field = "quest",
        group = "sources",
        default = true,
        label = LABELS.quest,
        summary = {[false] = L["no dungeon quests"]},
    },
    zoneQuest = {
        field = "zoneQuest",
        group = "sources",
        default = true,
        label = LABELS.zoneQuest,
        usable = function(_, env) return env.zoneQuests, env.zoneQuestWhy end,
        summary = {[false] = L["no other quests"]},
    },
    vendor = {
        field = "vendor",
        group = "sources",
        default = true,
        label = L["Sold by vendors"],
        usable = function(_, env) return env.vendors, env.vendorWhy end,
        summary = {[false] = L["no vendors"]},
    },
    npcDrop = {
        field = "npcDrop",
        group = "sources",
        default = true,
        label = L["Creature drops (outside dungeons)"],
        usable = function(_, env) return env.creatures, env.creatureWhy end,
        summary = {[false] = L["no creature drops"]},
    },
    hideCompleted = {
        field = "hideCompleted",
        default = true,
        label = L["Hide done quests"],
        indent = 20,
        usable = function(f, env)
            return f.sources.quest ~= false or (env.zoneQuests and f.sources.zoneQuest ~= false),
                   parentReason(LABELS.quest, LABELS.zoneQuest)
        end,
        summary = {[false] = L["with done quests"]},
    },
    craft = {
        field = "craft",
        group = "sources",
        default = true,
        label = LABELS.craft,
        usable = function(_, env)
            local why = env.atlasWhy
            return env.crafts,
                   {needs = why.needs, reason = why.reason, hint = L["Without it, open a profession window to list its items."]}
        end,
        summary = {[false] = L["no crafted"]},
    },
    craftOwnBoP = {
        field = "craftOwnBoP",
        default = true,
        label = LABELS.craftOwnBoP,
        indent = 20,
        usable = function(f, env)
            if not env.crafts then return false, env.atlasWhy end
            return f.sources.craft ~= false, parentReason(LABELS.craft)
        end,
    },
    craftOwnSkill = {
        field = "craftOwnSkill",
        default = true,
        label = L["Only up to my skill"],
        indent = 40,
        usable = function(f, env)
            if not env.crafts then return false, env.atlasWhy end
            if f.sources.craft == false then return false, parentReason(LABELS.craft) end
            return f.craftOwnBoP ~= false, parentReason(LABELS.craftOwnBoP)
        end,
    },
    -- without AtlasLoot the item's "Requires" line still makes it one
    reputation = {
        field = "reputation",
        group = "sources",
        default = true,
        label = LABELS.reputation,
        summary = {[false] = L["no reputation"]},
    },
    repOwnStanding = {
        field = "repOwnStanding",
        default = false,
        label = L["Only standings I have"],
        indent = 20,
        usable = function(f) return f.sources.reputation ~= false, parentReason(LABELS.reputation) end,
        summary = {[true] = L["my standings"]},
    },
    pvp = {field = "pvp", group = "sources", default = true, label = LABELS.pvp, summary = {[false] = L["no PvP"]}},
    pvpOwnRank = {
        field = "pvpOwnRank",
        default = false,
        label = L["Only ranks I have"],
        indent = 20,
        usable = function(f) return f.sources.pvp ~= false, parentReason(LABELS.pvp) end,
        summary = {[true] = L["my PvP rank"]},
    },
    event = atlasSource("event", L["World events"], L["no world events"]),
    world = {
        field = "world",
        group = "sources",
        default = true,
        label = L["World drops"],
        -- AtlasLoot's world epics, or QuestieDB's creature drops spread over many zones
        usable = function(_, env)
            if env.atlas or env.creatures then return true end
            return false, {needs = {"AtlasLoot Classic", "Questie"}, reason = env.atlasWhy.reason or env.creatureWhy.reason}
        end,
        summary = {[false] = L["no world drops"]},
    },
    faction = {field = "faction", default = false, label = L["Hide the other faction"], summary = {[false] = L["both factions"]}},
    chanceOn = {
        field = "on",
        group = "chance",
        default = false,
        label = LABELS.chanceOn,
        usable = function(_, env) return env.hasChance, env.atlasWhy end,
    },
    chanceUnknown = {
        field = "keepUnknown",
        group = "chance",
        default = true,
        label = L["Keep drops with unknown chance"],
        indent = 20,
        usable = function(f, env)
            if not env.hasChance then return false, env.atlasWhy end
            return f.chance ~= nil and f.chance.on == true, parentReason(LABELS.chanceOn)
        end,
    },
    priceOnly = {
        field = "only",
        group = "price",
        default = false,
        label = L["Only items with a price"],
        usable = function(_, env) return env.auction, env.auctionWhy end,
        summary = {[true] = L["with an auction price"]},
        summaryIf = function() return ns.Auctionator.Active() end,
    },
    priceMaxOn = {
        field = "maxOn",
        group = "price",
        default = false,
        label = LABELS.priceMaxOn,
        usable = function(_, env) return env.auction, env.auctionWhy end,
    },
    dungeonLevelOn = {field = "on", group = "dungeonLevel", default = false, label = L["Only dungeons in this level range"]},
    levelOn = {field = "on", group = "maxLevel", default = false, label = L["Hide items above this level"]},
    speedOn = {field = "on", group = "speed", default = false, label = L["Weapons in this speed range (sec)"]},
    setsOnly = {field = "setsOnly", default = false, label = L["Only set pieces"], summary = {[true] = L["set pieces"]}},
    ownSkill = {
        field = "ownSkill",
        default = true,
        label = LABELS.ownSkill,
        summary = {[false] = L["with other professions' items"]},
    },
    ownSkillRank = {
        field = "ownSkillRank",
        default = true,
        label = L["Hide items above my skill"],
        indent = 20,
        usable = function(f) return f.ownSkill ~= false, parentReason(LABELS.ownSkill) end,
    },
    hideCosmetic = {
        field = "hideCosmetic",
        default = true,
        label = L["Hide cosmetic items"],
        summary = {[false] = L["with cosmetic items"]},
    },
    upgradesOnly = {
        field = "pawnUpgradesOnly",
        default = false,
        label = L["Upgrades only"],
        usable = function(_, env)
            local reason = ns.Pawn.IsInstalled() and L["Pick a scale at the top."] or nil
            return env.pawn, {needs = NEEDS.pawn, reason = reason}
        end,
        summary = {[true] = L["upgrades only"]},
        summaryIf = function() return ns.ActiveScale() ~= nil end,
    },
    hideOwned = {field = "hideOwned", default = false, label = L["Hide items I own"], summary = {[true] = L["not owned"]}},
}
FilterBar.CHECK_ORDER = {
    "special", "dungeon", "raid", "rare", "trash", "shared", "probable", "quest", "zoneQuest", "hideCompleted", "vendor",
    "npcDrop", "craft", "craftOwnBoP", "craftOwnSkill", "reputation", "repOwnStanding", "pvp", "pvpOwnRank", "event", "world",
    "faction", "chanceOn", "chanceUnknown", "priceOnly", "priceMaxOn", "dungeonLevelOn", "levelOn", "speedOn", "setsOnly",
    "ownSkill", "ownSkillRank", "hideCosmetic", "upgradesOnly", "hideOwned",
}
FilterBar.CHECKS = CHECKS

local GROUP_DEFAULTS = {
    chance = function() return {on = false, min = 5, keepUnknown = true} end,
    price = function() return {only = false, maxOn = false, max = 50} end,
}
local function groupOf(f, group)
    if not group then return f end
    if f[group] == nil and GROUP_DEFAULTS[group] then f[group] = GROUP_DEFAULTS[group]() end
    f[group] = f[group] or {}
    return f[group]
end

function FilterBar.CheckValue(f, spec)
    local holder = spec.group and f[spec.group] or (not spec.group and f) or nil
    local value = holder and holder[spec.field]
    if value == nil then return spec.default end
    return value and true or false
end

local addWhyTooltip = W.WhyTooltip

local function setUsable(widget, enabled, why)
    widget:SetEnabled(enabled and true or false)
    widget.why = (not enabled) and why or nil
    -- dropdowns grey their own text
    local label = widget:GetObjectType() == "CheckButton" and rawget(widget, "Text")
    if type(label) == "table" then label:SetTextColor(unpack(enabled and Style.TEXT or Style.MUTED)) end
end

-- the first tick copies the class preselection, from then on the list is the player's
local function toggleSet(field, effective, key, value)
    local set = {}
    for k, v in pairs(effective or {}) do if v then set[k] = true end end
    set[key] = value and true or nil
    filters()[field] = set
    changed()
end

local GROUPS = {
    {key = "primary", label = L["Attributes"]}, {key = "spell", label = L["Spell"]}, {key = "physical", label = L["Physical"]},
    {key = "tank", label = L["Defense"]}, {key = "resist", label = L["Resistances"]},
}

local function statButton(parent, key, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 20)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.mark = W.Label(button, "", 13)
    button.mark:SetPoint("LEFT", 2, 0)
    button.mark:SetWidth(14)
    button.mark:SetJustifyH("CENTER")
    button.label = W.Label(button, Labels.Stat(key), 11)
    button.label:SetPoint("LEFT", 18, 0)
    button.label:SetPoint("RIGHT")
    button.label:SetWordWrap(false)
    button:SetHighlightTexture(Style.HIGHLIGHT_TEXTURE, "ADD")
    button:SetScript("OnClick", function(_, mouse)
        local stats = filters().stats
        local current = stats[key]
        if mouse == "RightButton" then
            stats[key] = nil
        elseif current == nil then
            stats[key] = 1
        elseif current == 1 then
            stats[key] = -1
        else
            stats[key] = nil
        end
        changed()
    end)
    W.AddTooltip(button, function(tooltip)
        tooltip:AddLine(Labels.Stat(key))
        tooltip:AddLine(L["Click: want, exclude, any. Right-click: any."], 1, 1, 1, true)
    end)
    function button:SetMode(mode)
        if mode == 1 then
            self.mark:SetText("|cff40ff40+|r")
            self.label:SetTextColor(0.5, 1, 0.5)
        elseif mode == -1 then
            self.mark:SetText("|cffff4040x|r")
            self.label:SetTextColor(1, 0.45, 0.45)
        else
            self.mark:SetText("|cff666666-|r")
            self.label:SetTextColor(0.85, 0.85, 0.85)
        end
    end
    return button
end

local function qualityItems()
    local items = {}
    for quality = 0, 5 do
        items[#items + 1] = {value = quality, text = Labels.QualityHex(quality) .. Labels.Quality(quality) .. "|r"}
    end
    return items
end

local function bindItems()
    return {
        {value = "ANY", text = L["Any binding"]}, {value = "BOP", text = L["Bind on pickup only"]},
        {value = "BOE", text = L["Bind on equip only"]},
    }
end

local function modeItems() return {{value = "relative", text = L["My level + N"]}, {value = "fixed", text = L["Fixed level"]}} end

local function statModeItems() return
  {{value = "ANY", text = L["Any wanted stat"]}, {value = "ALL", text = L["All wanted stats"]}} end

local function folded()
    local window = ns.addon.db.profile.window
    window.folded = window.folded or {}
    return window.folded
end

local HEADER_HEIGHT, SECTION_GAP = 26, 6
FilterBar.PRICE_SLIDER_MAX = 200 -- gold, the number box takes more

function FilterBar.Create(parent, width)
    local panel = W.Panel(parent)
    local scroll = W.ScrollArea(panel)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local content = scroll.content
    local inner = width - 40 -- the panel's border and the scroll bar
    local half = math.floor(inner / 2) -- two checkboxes or stat buttons per line
    local sections = {}
    local body, col
    controls.checks = {}

    local function layout()
        local y, state = 0, folded()
        for _, section in ipairs(sections) do
            local open = not state[section.key]
            section.header:ClearAllPoints()
            section.header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            section.header.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up"
                                             or "Interface\\Buttons\\UI-PlusButton-Up")
            y = y + HEADER_HEIGHT
            section.body:SetShown(open)
            if open then
                local height = section.col.layout()
                section.body:SetHeight(math.max(1, height))
                section.body:ClearAllPoints()
                section.body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                y = y + height + SECTION_GAP
            end
        end
        scroll:SetContentHeight(y + 20)
    end
    panel.Relayout = layout

    local function section(key, title)
        local header = CreateFrame("Button", nil, content)
        header:SetSize(inner, 22)
        header.icon = header:CreateTexture(nil, "ARTWORK")
        header.icon:SetSize(14, 14)
        header.icon:SetPoint("LEFT", 0, 0)
        header.text = W.Label(header, title, 13, Style.ACCENT)
        header.text:SetPoint("LEFT", header.icon, "RIGHT", 6, 0)
        header.line = header:CreateTexture(nil, "ARTWORK")
        header.line:SetHeight(1)
        header.line:SetPoint("LEFT", header.text, "RIGHT", 8, 0)
        header.line:SetPoint("RIGHT", -2, 0)
        header.line:SetColorTexture(1, 0.82, 0, 0.25)
        header:SetHighlightTexture(Style.HIGHLIGHT_TEXTURE, "ADD")
        header:SetScript("OnClick", function()
            local state = folded()
            state[key] = not state[key] or nil
            layout()
        end)
        body = CreateFrame("Frame", nil, content)
        body:SetSize(inner, 10)
        col = W.Column(body, 0, inner)
        sections[#sections + 1] = {key = key, header = header, body = body, col = col}
    end

    local function check(key)
        local spec = CHECKS[key]
        local box = col.check(spec.label, function(value)
            groupOf(filters(), spec.group)[spec.field] = value and true or false
            changed()
        end, spec.indent)
        addWhyTooltip(box, spec.label)
        controls.checks[key] = box
        return box
    end

    local function pair(list)
        local boxes = {}
        for i = 1, #list, 2 do
            local entries = {}
            for n = i, math.min(i + 1, #list) do
                local entry = list[n]
                local box = W.CheckBox(body, entry.label, entry.onChange)
                box.Text:SetFontObject("GameFontHighlightSmall")
                box.Text:SetWidth(half - 26)
                box.Text:SetWordWrap(false)
                W.FullTextTooltip(box, box.Text)
                boxes[entry.key] = box
                entries[#entries + 1] = {box, n == i and 0 or half}
            end
            col.row(24, entries)
        end
        return boxes
    end

    local function rangeBoxes(field, minValue, maxValue, step)
        local low = W.NumberBox(body, 50, minValue, maxValue, function(value)
            filters()[field].min = step and value or math.floor(value)
            changed()
        end)
        local high = W.NumberBox(body, 50, minValue, maxValue, function(value)
            filters()[field].max = step and value or math.floor(value)
            changed()
        end)
        local dash = W.Label(body, "–")
        dash:SetPoint("LEFT", low, "RIGHT", 6, 0)
        high:SetPoint("LEFT", dash, "RIGHT", 10, 0)
        col.place(low, 28, 6)
        return low, high
    end

    local function typeList(types, field)
        local list = {}
        for _, key in ipairs(types) do
            list[#list + 1] = {
                key = key,
                label = Labels.Type(key),
                onChange = function(value) toggleSet(field, lastCtx and lastCtx[field], key, value) end,
            }
        end
        return list
    end

    section("armor", L["Armor type"])
    controls.armor = pair(typeList(ns.Classes.ARMOR_TYPES, "armor"))
    col.help(L["Cloaks, rings, necks and trinkets always show."], 0)

    section("weapons", L["Weapon type"])
    controls.weapons = pair(typeList(ns.Classes.WEAPON_TYPES, "weapons"))

    section("stats", L["Stats"])
    controls.statMode = W.Dropdown(body, inner, statModeItems, function(value)
        filters().statMode = value
        changed()
    end)
    col.place(controls.statMode, 30)
    controls.stats = {}
    for _, group in ipairs(GROUPS) do
        col.label("|cffffd100" .. group.label .. "|r")
        local line = {}
        for _, stat in ipairs(ns.StatMap.STATS) do
            if stat.group == group.key then
                local button = statButton(body, stat.key, half)
                controls.stats[stat.key] = button
                line[#line + 1] = {button, #line == 0 and 0 or half}
                if #line == 2 then
                    col.row(20, line)
                    line = {}
                end
            end
        end
        if #line > 0 then col.row(20, line) end
    end
    check("special")

    section("sources", L["Sources"])
    -- rares, trash and the rest are parts of both
    for _, key in ipairs({"dungeon", "raid", "rare", "trash", "shared", "probable", "quest", "zoneQuest", "hideCompleted"}) do
        check(key)
    end
    col.help(L["Not if you still have the item."], 48)
    check("vendor")
    check("npcDrop")
    check("craft")
    check("craftOwnBoP")
    check("craftOwnSkill")
    for _, key in ipairs({"reputation", "repOwnStanding", "pvp", "pvpOwnRank", "event", "world", "faction"}) do check(key) end

    section("chance", L["Drop chance"])
    local function chanceState() return groupOf(filters(), "chance") end
    check("chanceOn")
    controls.chanceBox = W.NumberBox(body, 50, 0, 100, function(value)
        chanceState().min = math.floor(value * 10 + 0.5) / 10
        changed()
    end)
    controls.chanceSlider = W.Slider(body, nil, 0, 50, 1, inner - 60, function(value)
        chanceState().min = math.floor(value + 0.5)
        changedSoon()
    end)
    col.row(28, {{controls.chanceBox, 6}, {controls.chanceSlider, 64}})
    check("chanceUnknown")
    col.help(L["AtlasLoot's chances, per boss. Often unknown for trash and shared loot. Quests and crafts aren't affected."], 0)

    section("price", L["Auction price"])
    local function priceState() return groupOf(filters(), "price") end
    check("priceOnly")
    check("priceMaxOn")
    controls.priceBox = W.NumberBox(body, 50, 0, 1000000, function(value)
        priceState().max = math.floor(value + 0.5)
        changed()
    end)
    controls.priceSlider = W.Slider(body, nil, 1, FilterBar.PRICE_SLIDER_MAX, 1, inner - 60, function(value)
        priceState().max = math.floor(value + 0.5)
        changedSoon()
    end)
    col.row(28, {{controls.priceBox, 6}, {controls.priceSlider, 64}})
    controls.priceHelp = col.help(
                           L["Auctionator's prices from your scans. BoP and unpriced items: hidden by the first box, kept by the max price."],
                           0)

    section("places", L["Places"])
    col.label(L["Dungeons"])
    controls.dungeons = ns.PlacesDropdown.Create(body, inner, "dungeons")
    col.place(controls.dungeons, 30)
    controls.raidsLabel = col.label(L["Raids"])
    controls.raids = ns.PlacesDropdown.Create(body, inner, "raids")
    addWhyTooltip(controls.raids, L["Raids"])
    col.place(controls.raids, 30)
    col.help(L["Quests tied to a raid go with it."], 0)
    check("dungeonLevelOn")
    controls.dungeonMin, controls.dungeonMax = rangeBoxes("dungeonLevel", 1, ns.Filter.MAX_LEVEL)

    section("level", L["Max required level"])
    check("levelOn")
    controls.levelMode = W.Dropdown(body, inner, modeItems, function(value)
        filters().maxLevel.mode = value
        changed()
    end)
    col.place(controls.levelMode, 30)
    controls.levelBox = W.NumberBox(body, 50, 0, ns.Filter.MAX_LEVEL, function(value)
        local limit = filters().maxLevel
        if limit.mode == "fixed" then
            limit.fixed = math.max(1, math.floor(value))
        else
            limit.plus = math.min(10, math.floor(value))
        end
        changed()
    end)
    controls.levelSlider = W.Slider(body, nil, 0, 10, 1, inner - 60, function(value)
        local limit = filters().maxLevel
        if limit.mode == "fixed" then
            limit.fixed = math.max(1, math.floor(value + 0.5))
        else
            limit.plus = math.floor(value + 0.5)
        end
        changedSoon()
    end)
    col.row(26, {{controls.levelBox, 6}, {controls.levelSlider, 64}})
    local mine = W.Button(body, L["My level"], nil, 20, function()
        local limit = filters().maxLevel
        limit.on, limit.mode, limit.plus = true, "relative", 0
        changed()
    end)
    mine:FitWidth(16)
    local plusFive = W.Button(body, L["My level + 5"], nil, 20, function()
        local limit = filters().maxLevel
        limit.on, limit.mode, limit.plus = true, "relative", 5
        changed()
    end)
    plusFive:FitWidth(16)
    plusFive:SetPoint("LEFT", mine, "RIGHT", 4, 0)
    col.place(mine, 26)
    controls.levelText = col.label("")
    col.help(L["Also hides dungeons and quests above this level."], 0)

    section("item", L["Item"])
    col.label(L["Minimum quality"])
    controls.quality = W.Dropdown(body, inner, qualityItems, function(value)
        filters().minQuality = value
        changed()
    end)
    col.place(controls.quality, 30)
    col.label(L["Binding"])
    controls.bind = W.Dropdown(body, inner, bindItems, function(value)
        filters().bind = value
        changed()
    end)
    col.place(controls.bind, 30)
    col.help(L["BoE items can also be bought or traded."], 0)
    check("speedOn")
    controls.speedMin, controls.speedMax = rangeBoxes("speed", 1, 5, 0.1)
    col.help(L["Other items aren't affected."], 0)
    check("setsOnly")

    section("more", L["More"])
    check("ownSkill")
    check("ownSkillRank")
    col.help(L["Like engineering goggles: wearable only with the profession."], 28)
    check("hideCosmetic")
    check("upgradesOnly")
    check("hideOwned")
    -- the text changes with Syndicator and may wrap
    controls.ownedHelp = col.help(L["Equipped, bags, and bank once opened."], 28)

    layout()
    panel.scroll = scroll
    controls.panel = panel
    return panel
end

local function environment(f)
    local atlasInstalled, atlasOn = ns.AtlasLootLists.Installed(), ns.AtlasLootLists.Enabled()
    local questInstalled, questOn = ns.Questie.Installed(), ns.Questie.Enabled()
    local craftWindows = next(ns.addon.db.global.tradeSkills or {}) ~= nil
    local turnedOff = L["Off in Settings, Addons tab."]
    local index = ns.GetIndex()
    local env = {
        atlas = atlasInstalled and atlasOn,
        atlasWhy = {needs = NEEDS.atlasloot, reason = atlasInstalled and not atlasOn and turnedOff or nil},
        quests = questInstalled and questOn,
        questWhy = {needs = NEEDS.questie, reason = questInstalled and not questOn and turnedOff or nil},
        crafts = (ns.Crafts.Installed() and ns.Crafts.Enabled()) or craftWindows,
        hasRaids = #ns.PlacesDropdown.Places("raids") > 0,
        hasChance = index and index.hasChance or false,
        pawn = ns.ActiveScale() ~= nil,
        auction = ns.Auctionator.Active(),
        auctionWhy = {needs = NEEDS.auctionator, reason = ns.Auctionator.Installed() and turnedOff or nil},
    }
    local function questKind(switch)
        local on = env.quests and ns.Questie.KindEnabled(switch)
        local off = questInstalled and not on and turnedOff or nil
        return on, {needs = NEEDS.questie, reason = off}
    end
    env.zoneQuests, env.zoneQuestWhy = questKind("quests")
    env.vendors, env.vendorWhy = questKind("vendors")
    env.creatures, env.creatureWhy = questKind("drops")
    env.drops = f.sources.dungeon ~= false or (env.atlas and f.sources.raid ~= false)
    return env
end

function FilterBar.Refresh(ctx)
    lastCtx = ctx
    local f = filters()
    local env = environment(f)
    for key, box in pairs(controls.checks) do
        local spec = CHECKS[key]
        box:SetChecked(FilterBar.CheckValue(f, spec))
        if spec.usable then
            setUsable(box, spec.usable(f, env))
        else
            setUsable(box, true)
        end
    end
    for key, box in pairs(controls.armor) do box:SetChecked(ctx.armor[key] == true) end
    for key, box in pairs(controls.weapons) do box:SetChecked(ctx.weapons[key] == true) end
    controls.statMode:SetValue(f.statMode)
    for key, button in pairs(controls.stats) do button:SetMode(f.stats[key]) end

    local chance = f.chance or {}
    if not controls.chanceBox:HasFocus() then controls.chanceBox:SetText((Labels.Chance(chance.min or 5):gsub("%%", ""))) end
    controls.chanceSlider:SetValue(math.min(50, chance.min or 5))

    local price = f.price or {}
    if not controls.priceBox:HasFocus() then controls.priceBox:SetText(tostring(price.max or 50)) end
    controls.priceSlider:SetValue(math.max(1, math.min(FilterBar.PRICE_SLIDER_MAX, price.max or 50)))

    local limit = f.maxLevel
    controls.levelMode:SetValue(limit.mode)
    local fixed = limit.mode == "fixed"
    if not controls.levelBox:HasFocus() then controls.levelBox:SetText(tostring(fixed and limit.fixed or limit.plus)) end
    controls.levelSlider:SetRange(fixed and 1 or 0, fixed and ns.Filter.MAX_LEVEL or 10, fixed and limit.fixed or limit.plus)

    if not controls.dungeonMin:HasFocus() then controls.dungeonMin:SetText(tostring(f.dungeonLevel.min)) end
    if not controls.dungeonMax:HasFocus() then controls.dungeonMax:SetText(tostring(f.dungeonLevel.max)) end
    controls.bind:SetValue(f.bind)
    if not controls.speedMin:HasFocus() then controls.speedMin:SetText(format("%.1f", f.speed.min)) end
    if not controls.speedMax:HasFocus() then controls.speedMax:SetText(format("%.1f", f.speed.max)) end
    controls.quality:SetValue(f.minQuality)
    controls.dungeons:ShowSummary()
    controls.raids:ShowSummary()
    setUsable(controls.raids, env.hasRaids, env.atlasWhy)
    controls.raidsLabel:SetTextColor(unpack(env.hasRaids and Style.TEXT or Style.MUTED))

    -- these may wrap differently, restack when they change
    local levelText = FilterBar.LevelText(f, ctx)
    local ownedText = ns.Owned.HasSyndicator() and L["Equipped, bags, bank and mail (Syndicator)."]
                        or L["Equipped, bags, and bank once opened."]
    if controls.levelText:GetText() ~= levelText or controls.ownedHelp:GetText() ~= ownedText then
        controls.levelText:SetText(levelText)
        controls.ownedHelp:SetText(ownedText)
        controls.panel.Relayout()
    end
end
