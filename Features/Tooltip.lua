-- source, "who wants it" and auction lines on item tooltips
local _, ns = ...
local L = ns.L

local Tooltip = {}
ns.Tooltip = Tooltip

local MAX_SOURCES = 3
local SOURCE_COLOR = {1, 0.82, 0}
local MUTED = "|cffaaaaaa"
-- tooltip fonts have no star character
Tooltip.STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
Tooltip.STAR = "|T" .. Tooltip.STAR_TEXTURE .. ":12:12|t"

local isSecret = ns.Util.IsSecret

-- "21%", "0.1%", "<0.1%"
function Tooltip.ChanceText(chance)
    if chance >= 10 then return format("%d%%", math.floor(chance + 0.5)) end
    if chance >= 0.1 then return (format("%.1f", chance):gsub("%.0$", "")) .. "%" end
    return "<0.1%"
end

function Tooltip.DungeonLabel(key, dungeonByKey)
    local dungeon = dungeonByKey and dungeonByKey[key]
    -- its provider may be turned off
    local name = (key ~= nil and ns.DungeonJournal.DungeonName(key)) or (dungeon and dungeon.name) or tostring(key or "?")
    if dungeon and dungeon.levelText then return format("%s (%s)", name, (dungeon.levelText:gsub("%-", "–"))) end
    return name
end

-- " (quest: Name, from level 60)" for a list entry that's also a quest reward
function Tooltip.ViaQuestNote(source)
    if not source.viaQuests then return "" end
    local parts = {format(L["quest: %s"], source.viaQuestName or "?")}
    if source.reqLevel then parts[#parts + 1] = format(L["from level %d"], source.reqLevel) end
    return " " .. MUTED .. "(" .. table.concat(parts, ", ") .. ")|r"
end

local function iconText(icon, count)
    if icon == nil or isSecret(icon) then return tostring(count) end
    return format("%d |T%s:0|t", count, tostring(icon))
end

-- coins for gold, the item's or currency's icon with the count for the rest
function Tooltip.PriceText(price)
    if type(price) ~= "table" then return nil end
    local parts = {}
    local currencies = rawget(_G, "C_CurrencyInfo")
    for _, cost in ipairs(price) do
        if cost.money then
            local coins = currencies and ns.Util.SafeCall(currencies.GetCoinTextureString, cost.money)
            parts[#parts + 1] = type(coins) == "string" and not isSecret(coins) and coins or format("%dc", cost.money)
        elseif cost.item then
            local icon = C_Item and select(5, ns.Util.SafeCall(C_Item.GetItemInfoInstant, cost.item))
            parts[#parts + 1] = iconText(icon, cost.count or 1)
        elseif cost.currency then
            local info = currencies and ns.Util.SafeCall(currencies.GetCurrencyInfo, cost.currency)
            parts[#parts + 1] = iconText(type(info) == "table" and info.iconFileID or nil, cost.count or 1)
        end
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end

local function withPrice(text, source)
    local price = Tooltip.PriceText(source.price)
    return price and (text .. "  " .. price) or text
end

local function zonesText(source)
    if source.zones and #source.zones > 0 then return table.concat(source.zones, ", ") .. (source.moreZones and ", ..." or "") end
    return source.zoneName
end

local function levelText(low, high)
    if not low then return nil end
    if not high or high == low then return format(L["level %d"], low) end
    return format(L["level %d–%d"], low, high)
end

local function npcText(source, withDungeon)
    local text, notes = nil, {}
    if source.kind == "vendor" then
        text = source.many and format(L["Sold by %d vendors"], source.count or 0)
                 or (source.npcName and format(L["Vendor: %s"], source.npcName)) or L["Vendor"]
        if source.faction then notes[#notes + 1] = source.faction == "Horde" and L["Horde"] or L["Alliance"] end
    else
        text = source.many and format(L["Dropped by %d creatures"], source.count or 0)
                 or format(L["Drops from: %s"], source.npcName or "?")
        if source.rare then notes[#notes + 1] = L["rare"] end
        notes[#notes + 1] = levelText(source.levelMin, source.levelMax)
    end
    if #notes > 0 then text = text .. " " .. MUTED .. "(" .. table.concat(notes, ", ") .. ")|r" end
    text = withPrice(text, source)
    local where = zonesText(source)
    if withDungeon == false or not where then return text end
    return text .. " — " .. where
end

-- these say what they are, no "Drops from" label needed
Tooltip.SELF_LABELLED = {vendor = true, npcDrop = true}

function Tooltip.SourceText(source, dungeonByKey, withDungeon)
    if Tooltip.SELF_LABELLED[source.kind] then return npcText(source, withDungeon) end
    if source.kind == "craft" then
        local name = source.professionName or tostring(source.profession)
        return source.skill and format(L["%s (skill %d)"], name, source.skill) or name
    end
    if source.kind == "reputation" then
        local name = source.factionName or L["Reputation"]
        local text = source.standing and format("%s: %s", name, ns.AtlasLootLists.StandingName(source.standing)) or name
        return withPrice(text, source) .. Tooltip.ViaQuestNote(source)
    end
    if source.kind == "pvp" then
        local text = source.section and format(L["PvP: %s"], source.section) or L["PvP"]
        if source.standing then
            text = text .. " " .. MUTED .. "(" .. ns.AtlasLootLists.StandingName(source.standing) .. ")|r"
        end
        return withPrice(text, source)
    end
    if source.kind == "event" then
        local name = ns.Holidays.EventName(source) or "?"
        return withPrice(format(L["World event: %s"], name), source) .. Tooltip.ViaQuestNote(source)
    end
    if source.kind == "world" then
        local text = source.section and format(L["World drop: %s"], source.section) or L["World drop"]
        local level = levelText(source.levelMin, source.levelMax)
        -- the creatures' levels, not a requirement
        if level then text = text .. " " .. MUTED .. "(" .. format(L["creatures %s"], level) .. ")|r" end
        return text .. Tooltip.ViaQuestNote(source)
    end
    if source.kind == "zoneQuest" then
        local text = format(L["Quest: %s"], source.questName or "?")
        local level = source.reqLevel and format(L["from level %d"], source.reqLevel)
        if level then text = text .. " " .. MUTED .. "(" .. level .. ")|r" end
        if withDungeon == false or not source.zoneName then return text end
        return text .. " — " .. source.zoneName
    end
    local where
    if source.kind == "combine" then
        local parts = {}
        for _, part in ipairs(source.parts or {}) do
            local text = part.name or "?"
            if part.bossName then
                text = text .. " " .. MUTED .. "(" .. ns.DungeonJournal.BossName(part.bossName) .. ")|r"
            end
            parts[#parts + 1] = text
        end
        where = format(L["Combine: %s"], table.concat(parts, " + "))
        if withDungeon == false or source.dungeon == nil then return where end
        return where .. " — " .. Tooltip.DungeonLabel(source.dungeon, dungeonByKey)
    elseif source.kind == "quest" then
        where = format(L["Quest: %s"], source.questName or source.section or "?")
    elseif source.kind == "trash" then
        local mobs = source.mobs and source.mobs ~= "" and source.mobs or nil
        where = mobs and format(L["Trash: %s"], mobs) or L["Trash"]
    else
        where = ns.DungeonJournal.BossName(source.bossName or "?") or "?"
    end
    local notes = {}
    if source.kind == "rare" then notes[#notes + 1] = L["rare"] end
    if source.kind == "shared" then notes[#notes + 1] = L["shared, low chance"] end
    if source.kind == "probable" then notes[#notes + 1] = L["unconfirmed"] end
    if source.sourceTip and source.sourceTip ~= source.bossName then notes[#notes + 1] = source.sourceTip end
    if source.faction then notes[#notes + 1] = source.faction == "Horde" and L["Horde"] or L["Alliance"] end
    if source.rareDrop then notes[#notes + 1] = L["extremely rare"] end
    -- without a real number FDJ's note says it all
    if source.chance and not (source.chanceGuess and not source.chanceFrom) then
        notes[#notes + 1] = Tooltip.ChanceText(source.chance)
    end
    if #notes > 0 then where = where .. " " .. MUTED .. "(" .. table.concat(notes, ", ") .. ")|r" end
    if withDungeon == false or source.dungeon == nil then return where end
    return where .. " — " .. Tooltip.DungeonLabel(source.dungeon, dungeonByKey)
end

-- each faction's or race's copy of a quest makes one line
local MERGED_DROP = {"faction", "zoneKey", "zoneName", "dungeon", "questLevel"}
function Tooltip.MergeQuests(sources)
    local out, byName, copies
    for i, source in ipairs(sources) do
        local name = ns.Index.IsQuest(source) and type(source.questName) == "string" and source.questName:lower()
        local first = name and byName and byName[name]
        if first then
            if not out then
                out = {}
                for j = 1, i - 1 do out[j] = sources[j] end
            end
            copies = copies or {}
            local merged = copies[first]
            if not merged then
                merged = ns.Index.Flat(out[first])
                merged.questIDs, merged.merged = {out[first].questID}, 1
                copies[first] = merged
                out[first] = merged
            end
            merged.merged = merged.merged + 1
            if source.questID then merged.questIDs[#merged.questIDs + 1] = source.questID end
            if source.reqLevel and (not merged.reqLevel or source.reqLevel < merged.reqLevel) then
                merged.reqLevel = source.reqLevel
            end
            for _, field in ipairs(MERGED_DROP) do if merged[field] ~= source[field] then merged[field] = nil end end
        else
            if out then out[#out + 1] = source end
            if name then
                byName = byName or {}
                byName[name] = out and #out or i
            end
        end
    end
    return out or sources
end

-- pure. opts.showAll: Shift is down
function Tooltip.Lines(record, dungeonByKey, opts)
    local lines = {}
    local sources = opts.sources or record.sources
    -- FDJ's line already covers its own loot and quests
    if opts.fdjLineOn then
        local rest = {}
        for _, source in ipairs(sources) do
            local fdjQuest = source.kind == "quest" and source.dungeon and not tostring(source.dungeon):find("^al:")
            if source.kind == "probable" or (source.provider ~= "fdj" and not fdjQuest) then rest[#rest + 1] = source end
        end
        sources = rest
    end
    sources = Tooltip.MergeQuests(sources)
    if opts.showSource and #sources > 0 then
        local limit = opts.showAll and #sources or math.min(#sources, MAX_SOURCES)
        local label = L["Drops from: %s"]
        for i = 1, limit do if not ns.Index.DROP_KINDS[sources[i].kind] then label = L["Source: %s"] end end
        for i = 1, limit do
            local text = Tooltip.SourceText(sources[i], dungeonByKey)
            if i > 1 then
                text = "    " .. text
            elseif not Tooltip.SELF_LABELLED[sources[i].kind] then
                text = format(label, text)
            end
            lines[#lines + 1] = {text = text, color = SOURCE_COLOR}
        end
        if limit < #sources then
            lines[#lines + 1] = {text = "    " .. format(L["%d more (Shift)"], #sources - limit), color = {0.6, 0.6, 0.6}}
        end
    end
    -- off by default, Auctionator has its own line
    if opts.auction then lines[#lines + 1] = {text = format(L["Auction: %s"], opts.auction), color = {1, 1, 1}} end
    if opts.showFavourite and opts.who then
        for _, tier in ipairs(ns.Favourites.TIERS) do
            local names = opts.who[tier.key]
            if names then
                local text = Tooltip.STAR .. " " .. tier.label
                -- just your own tier needs no name
                if #names > 0 then text = text .. " — " .. table.concat(names, ", ") end
                lines[#lines + 1] = {text = text, color = tier.color}
            end
        end
    end
    return lines
end

-- a tier with an empty list is yours alone
function Tooltip.WhoNames(who, myKey, others, nameOf)
    local out = {}
    for tier, keys in pairs(who) do
        local names, mine = {}, false
        for _, key in ipairs(keys) do
            if key == myKey then mine = true end
            if others then names[#names + 1] = nameOf(key) end
        end
        if others or mine then
            if not others or (mine and #keys == 1) then names = {} end
            out[tier] = names
        end
    end
    return out
end

local function whoNames(id)
    local others = ns.addon.db.profile.tooltip.otherChars == true
    return Tooltip.WhoNames(ns.Favourites.Who(id), ns.charKey, others, ns.Favourites.CharacterName)
end

local function auctionText(record)
    local price = ns.Auctionator.ForRecord(record, ns.Items.Info(record))
    return price and ns.Auctionator.Text(price, true) or nil
end

-- own: set for FLF's windows. noItem: FDJ adds nothing there
function Tooltip.Add(tooltip, record, own)
    local profile = ns.addon.db.profile
    local index = ns.GetIndex()
    local showSource = own ~= nil or profile.tooltip.allItems == true
    local lines = Tooltip.Lines(record, index and index.dungeonByKey, {
        sources = showSource and (own and own.sources or ns.DoableSources(record.sources, own and own.charKey)) or nil,
        showSource = showSource,
        fdjLineOn = not (own and own.noItem) and ns.DungeonJournal.ItemSourceLineOn(),
        showAll = IsShiftKeyDown(),
        showFavourite = profile.tooltip.favourite and record.id and record.id > 0,
        who = record.id and record.id > 0 and whoNames(record.id) or nil,
        auction = profile.tooltip.auction and auctionText(record) or nil,
    })
    for _, line in ipairs(lines) do tooltip:AddLine(line.text, line.color[1], line.color[2], line.color[3], true) end
    return #lines
end

local owners = setmetatable({}, {__mode = "k"})
function Tooltip.SetOwn(owner, own) owners[owner] = own end

-- Pawn and FDJ scan items on hidden tooltips of their own
local function onItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if type(data) ~= "table" or isSecret(data) then return end
    local id = data.id
    if isSecret(id) or type(id) ~= "number" then return end
    local index = ns.GetIndex()
    local record = index and index.byKey[id]
    if not record then
        -- a favourite no addon lists still gets its tier line
        if not (index and next(ns.Favourites.Who(id))) then return end
        record = {key = id, id = id, sources = {}}
    end
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    Tooltip.Add(tooltip, record, owner and owners[owner] or nil)
end

function Tooltip.Enable()
    if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
                                            function(tooltip, data) ns.Guard(onItemTooltip, tooltip, data) end)
end
