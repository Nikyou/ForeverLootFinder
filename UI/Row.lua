local _, ns = ...
local L = ns.L
local W, Style, Labels = ns.Widgets, ns.Style, ns.Labels

local Row = {}
ns.Row = Row

Row.HEIGHT = 40
Row.HEADER_HEIGHT = 24

-- right to left. a column shows when picked and when there's data for it
local COLUMNS = {
    {key = "upgrade", width = 64, sort = "upgrade", label = L["Upgrade"], menu = L["Upgrade"], pawn = true},
    {key = "pawn", width = 56, sort = "pawn", label = "Pawn", menu = L["Pawn value"], pawn = true},
    {key = "weapon", width = 84, sort = "speed", label = L["Speed / DPS"], menu = L["Speed / DPS"], weapon = true},
    {key = "chance", width = 50, sort = "chance", label = L["Drop %"], menu = L["Drop chance"], chance = true},
    {key = "price", width = 72, sort = "price", label = L["Price"], menu = L["Auction price"], price = true},
    {key = "source", width = 230, sort = "dungeonlevel", label = L["Source"], menu = L["Source"]},
}
Row.CHOOSABLE = {}
for i = #COLUMNS, 1, -1 do Row.CHOOSABLE[#Row.CHOOSABLE + 1] = COLUMNS[i] end

function Row.ColumnChosen(columns, key)
    local value
    if type(columns) == "table" then value = columns[key] end
    if value == nil then
        local defaults = ns.DEFAULTS and ns.DEFAULTS.profile.columns
        if defaults and defaults[key] ~= nil then return defaults[key] end
        return key ~= "price"
    end
    return value and true or false
end

function Row.ColumnStatus(key, opts)
    opts = opts or {}
    local turnedOff = L["Off in Settings, Addons tab."]
    if key == "upgrade" or key == "pawn" then
        if ns.ActiveScale() then return true end
        local reason = ns.Pawn.IsInstalled() and L["Pick a Pawn scale at the top."] or nil
        return false, {needs = {"Pawn"}, reason = reason}
    elseif key == "chance" then
        local index = ns.GetIndex()
        if index and index.hasChance then return true end
        local reason
        if ns.AtlasLootLists.Installed() then
            reason = ns.AtlasLootLists.Enabled() and L["No drop chances known yet."] or turnedOff
        end
        return false, {needs = {"AtlasLoot Classic"}, reason = reason}
    elseif key == "price" then
        if ns.Auctionator.Active() then return true end
        return false, {needs = {"Auctionator"}, reason = ns.Auctionator.Installed() and turnedOff or nil}
    elseif key == "weapon" and opts.weapons == false then
        return false, {reason = L["Weapon slots only."]}
    end
    return true
end

function Row.SetColumn(key, value)
    local profile = ns.addon.db.profile
    profile.columns = profile.columns or {}
    profile.columns[key] = value and true or false
    ns.FireChange("columns")
    if ns.Options then ns.Options:RefreshActiveTab() end
end

function Row.ColumnMenu(owner, opts)
    W.ContextMenu(owner, function(_, root)
        root:CreateTitle(L["Columns"])
        for _, column in ipairs(Row.CHOOSABLE) do
            local key = column.key
            local usable, why = Row.ColumnStatus(key, opts)
            local function chosen() return Row.ColumnChosen(ns.addon.db.profile.columns, key) end
            local text = usable and column.menu or ("|cff808080" .. column.menu .. "|r")
            local box = root:CreateCheckbox(text, chosen, function() Row.SetColumn(key, not chosen()) end, key)
            if not usable and box then
                if box.SetEnabled then box:SetEnabled(false) end
                if box.SetTooltip then box:SetTooltip(function(tooltip) W.AddWhyLines(tooltip, column.menu, why) end) end
            end
        end
    end)
end

Row.NAME_LEFT = 64 -- star, icon, gap
-- Name takes the resizing until it fits its longest line, then Source gets the rest
local SOURCE_BASE, SOURCE_MIN, NAME_MIN, NAME_CAP = 200, 110, 120, 380
local ARROW_ROOM = 14 -- the sort arrow after a header label

local measurers = {}
local function textWidth(text, font)
    local measure = measurers[font]
    if not measure then
        if not UIParent then return 0 end
        measure = UIParent:CreateFontString(nil, "OVERLAY", font)
        measure:Hide()
        measurers[font] = measure
    end
    measure:SetText(text or "")
    return math.ceil(measure:GetStringWidth() or 0)
end

local headerWidths = {}
local function fitWidth(column)
    if column.key == "source" then return column.width end
    local fit = headerWidths[column.key]
    if not fit then
        fit = textWidth(column.label, "GameFontHighlightSmall") + ARROW_ROOM
        -- fonts load late, don't keep a zero width
        if fit > ARROW_ROOM then headerWidths[column.key] = fit end
    end
    return math.max(column.width, fit)
end

function Row.Columns(opts, width)
    local list, right = {}, 6
    for _, column in ipairs(COLUMNS) do
        local shown = (not column.pawn or opts.pawn) and (not column.chance or opts.chance)
                          and (not column.weapon or opts.weapons ~= false) and (not column.price or opts.price)
                          and Row.ColumnChosen(opts.columns, column.key)
        if shown then
            local w = fitWidth(column)
            if column.key == "source" and width and width > 0 then
                local free = width - right - Row.NAME_LEFT - 14 -- shared by Name and Source
                local need = math.max(NAME_MIN, math.min(NAME_CAP, opts.nameNeed or NAME_CAP))
                if free - SOURCE_BASE >= need then
                    w = free - need
                else
                    w = math.max(SOURCE_MIN, math.min(SOURCE_BASE, free - NAME_MIN))
                end
            end
            list[#list + 1] = {key = column.key, width = w, right = right, sort = column.sort, label = column.label}
            right = right + w + 6
        end
    end
    return list, right
end

local function layoutKey(opts)
    local chosen = {}
    for i, column in ipairs(COLUMNS) do chosen[i] = Row.ColumnChosen(opts.columns, column.key) and "1" or "0" end
    return (opts.pawn and "p" or "") .. (opts.chance and "c" or "") .. (opts.weapons ~= false and "w" or "")
             .. (opts.price and "$" or "") .. table.concat(chosen) .. math.floor(opts.width or 0) .. ":"
             .. math.floor(opts.nameNeed or 0)
end

local function setup(button)
    button:SetHeight(Row.HEIGHT)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    W.StyleRow(button)
    button.star = button:CreateTexture(nil, "ARTWORK")
    button.star:SetSize(16, 16)
    button.star:SetPoint("LEFT", 4, 0)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(32, 32)
    button.icon:SetPoint("LEFT", 24, 0)
    button.name = W.Label(button, "")
    button.name:SetWordWrap(false)
    button.sub = W.Label(button, "", 11, Style.MUTED)
    button.sub:SetWordWrap(false)
    button.cells = {}
    for _, column in ipairs(COLUMNS) do
        local cell = W.Label(button, "", column.key == "source" and 11 or nil)
        cell:SetJustifyH(column.key == "source" and "LEFT" or "RIGHT")
        cell:SetWordWrap(column.key == "source")
        if column.key == "source" then cell:SetMaxLines(2) end
        button.cells[column.key] = cell
    end
    button.headerText = W.Label(button, "", 13, Style.ACCENT)
    button:SetScript("OnEnter", function(self) ns.Guard(Row.ShowTooltip, self) end)
    button:SetScript("OnLeave", function() Row.HideTooltip() end)
    button:SetScript("OnClick", function(self, mouse) ns.Guard(Row.OnClick, self, mouse) end)
    button.created = true
end

local function layout(button, opts)
    local key = layoutKey(opts)
    if button.layout == key then return end
    button.layout = key
    local columns, used = Row.Columns(opts, opts.width)
    for _, cell in pairs(button.cells) do
        cell:ClearAllPoints()
        cell:Hide()
    end
    for _, column in ipairs(columns) do
        local cell = button.cells[column.key]
        cell:SetPoint("RIGHT", -column.right, 0)
        cell:SetWidth(column.width)
        cell:Show()
    end
    button.name:ClearAllPoints()
    button.name:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 8, -1)
    button.name:SetPoint("RIGHT", -(used + 2), 0)
    button.sub:ClearAllPoints()
    button.sub:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMRIGHT", 8, 1)
    button.sub:SetPoint("RIGHT", -(used + 2), 0)
end

local BADGE_OF = {zoneQuest = "quest", npcDrop = "creature"}

function Row.Badges(row)
    local shown = ns.addon.db.profile.badges
    local record, info = row.record, row.info
    local has = {}
    for _, source in ipairs(row.sources or record.sources) do
        if source.kind ~= "boss" then has[BADGE_OF[source.kind] or source.kind] = true end
        if source.faction then has.faction = true end
        if source.rare then has.rare = true end
    end
    if record.randomBonus then has.random = true end
    if info.notInGame or info.missing then has.notInGame = true end
    if record.id and ns.Owned.Where(record.id) then has.owned = true end
    if info.bind == "BOE" then has.boe = true end
    if info.unique then has.unique = true end
    if info.setID or info.setName then has.set = true end
    local parts = {}
    for _, badge in ipairs(Labels.BADGES) do
        if has[badge.key] and shown[badge.key] then parts[#parts + 1] = "|c" .. badge.color .. badge.label .. "|r" end
    end
    return table.concat(parts, " ")
end

-- kept on the row: NameNeed measures it and Bind draws it
function Row.SubText(data)
    if data.subText then return data.subText end
    local record, info = data.record, data.info
    local sub = {Labels.ItemKind(record, info)}
    local stats = Labels.StatLine(info.stats, 4)
    if stats and stats ~= "" then sub[#sub + 1] = stats end
    local badges = Row.Badges(data)
    if badges ~= "" then sub[#sub + 1] = badges end
    data.subText = table.concat(sub, "  ")
    return data.subText
end

function Row.NameNeed(rows)
    local need = 0
    for _, data in ipairs(rows) do
        if not data.header and data.record then
            local name = data.info.name or data.record.name or "?"
            need = math.max(need, textWidth(name, "GameFontHighlight"), textWidth(Row.SubText(data), "GameFontHighlightSmall"))
            if need >= NAME_CAP then return NAME_CAP end
        end
    end
    return need + 8
end

local function sourceCell(row, dungeonByKey)
    local sources = ns.Tooltip.MergeQuests(row.sources or row.record.sources)
    if #sources == 0 then return "" end
    local text = ns.Tooltip.SourceText(sources[1], dungeonByKey)
    if #sources > 1 then text = text .. "\n" .. format(L["+%d more"], #sources - 1) end
    return text
end

local function upgradeText(row)
    local compare = row.compare
    if compare and compare.unique == "equipped" then return "|cff9d9d9d" .. L["Unique"] .. "|r" end
    local upgrade = row.upgrade
    if upgrade == nil then return "" end
    if compare and compare.emptySlot then return "|cff40ff40" .. L["new"] .. "|r" end
    local percent = upgrade * 100
    if percent > 0.5 then return format("|cff40ff40+%.0f%%|r", percent) end
    if percent < -0.5 then return format("|cffff5050%.0f%%|r", percent) end
    return "|cffaaaaaa0%|r"
end

Row.HEADER_INDENT = 16 -- per level of a header's indent

local function refreshTooltip(button)
    if GameTooltip:GetOwner() == button and button:IsVisible() then ns.Guard(Row.ShowTooltip, button) end
end
Row.RefreshTooltip = refreshTooltip

-- data: a row, or {header = text, indent?}
function Row.Bind(button, data, opts)
    if not button.created then setup(button) end
    button.data = data
    button.opts = opts
    local isHeader = data.header ~= nil
    button.headerText:SetShown(isHeader)
    button.star:SetShown(not isHeader)
    button.icon:SetShown(not isHeader)
    button.name:SetShown(not isHeader)
    button.sub:SetShown(not isHeader)
    if isHeader then
        for _, cell in pairs(button.cells) do cell:Hide() end
        button.layout = nil
        button:SetHeight(Row.HEADER_HEIGHT)
        button.headerText:ClearAllPoints()
        button.headerText:SetPoint("LEFT", 8 + (data.indent or 0) * Row.HEADER_INDENT, 0)
        button.headerText:SetText(data.header)
        button:SetAlpha(1)
        if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
        return
    end
    button:SetHeight(Row.HEIGHT)
    layout(button, opts)
    local record, info = data.record, data.info
    button.icon:SetTexture(info.icon or 134400)
    button.name:SetText(Labels.QualityHex(info.quality) .. (info.name or record.name or "?") .. "|r")
    button.sub:SetText(Row.SubText(data))
    local tier = record.id and record.id > 0 and ns.Favourites.Get(record.id, opts.charKey)
    if ns.addon.db.profile.stars then
        W.SetStar(button.star, tier)
        button.star:Show()
    else
        button.star:SetShown(tier ~= nil and tier ~= false)
        if tier then W.SetStar(button.star, tier) end
    end
    local cells = button.cells
    cells.source:SetText(sourceCell(data, opts.dungeonByKey))
    if ns.Filter.IsWeapon(info) and info.speed then
        cells.weapon:SetText(format("%.2f / %.1f", info.speed, info.dps or 0))
    else
        cells.weapon:SetText("")
    end
    if opts.chance then
        local best
        for _, source in ipairs(data.sources or record.sources) do
            if source.chance and (not best or source.chance > best) then best = source.chance end
        end
        cells.chance:SetText(best and format("%.1f%%", best) or "")
    end
    if opts.price then
        -- nothing for bind on pickup, a dash for unseen
        local price = data.auction or ns.Auctionator.ForRecord(record, info)
        if price then
            cells.price:SetText(ns.Auctionator.Text(price))
        else
            cells.price:SetText(ns.Auctionator.Sellable(info) and "|cff808080—|r" or "")
        end
    end
    if opts.pawn then
        cells.pawn:SetText(data.pawn and (opts.scaleColor .. format("%.1f", data.pawn) .. "|r") or "")
        cells.upgrade:SetText(upgradeText(data))
    end
    button:SetAlpha((data.status == "unknown" or data.status == "missing") and 0.55 or 1)
    refreshTooltip(button)
end

function Row.CreateHeader(parent, onSort)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(20)
    header.buttons = {}
    local function button(key)
        local b = CreateFrame("Button", nil, header)
        b:SetHeight(20)
        b.text = W.Label(b, "", 11, Style.ACCENT)
        b.text:SetAllPoints()
        b:SetHighlightTexture(Style.HIGHLIGHT_TEXTURE, "ADD")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then return ns.Guard(Row.ColumnMenu, self, header.opts) end
            onSort(self.sortKey)
        end)
        W.AddTooltip(b, function(tooltip)
            tooltip:AddLine(b.text:GetText() or "")
            tooltip:AddLine(L["Click: sort. Right-click: columns."], 1, 1, 1, true)
        end)
        header.buttons[key] = b
        return b
    end
    header:EnableMouse(true)
    header:SetScript("OnMouseUp", function(self, mouse)
        if mouse == "RightButton" then ns.Guard(Row.ColumnMenu, self, self.opts) end
    end)
    local name = button("name")
    name.sortKey = "name"
    name.text:SetText(L["Name"])
    for _, column in ipairs(COLUMNS) do button(column.key) end
    return header
end

function Row.LayoutHeader(header, opts, sort)
    header.opts = opts
    local columns, used = Row.Columns(opts, opts.width)
    for _, column in ipairs(COLUMNS) do header.buttons[column.key]:Hide() end
    -- no arrow glyphs in the fonts, so the texture is flipped for ascending
    local arrow = sort.desc and " |TInterface\\Buttons\\UI-SortArrow:10:10:0:0:16:16:0:16:0:16|t"
                    or " |TInterface\\Buttons\\UI-SortArrow:10:10:0:0:16:16:0:16:16:0|t"
    for _, column in ipairs(columns) do
        local b = header.buttons[column.key]
        b:ClearAllPoints()
        b:SetPoint("RIGHT", -column.right, 0)
        b:SetWidth(column.width)
        b.sortKey = column.sort
        b.text:SetJustifyH(column.key == "source" and "LEFT" or "RIGHT")
        b.text:SetText(column.label .. (sort.key == column.sort and arrow or ""))
        b:Show()
    end
    local name = header.buttons.name
    name.text:SetText(L["Name"] .. (sort.key == "name" and arrow or ""))
    name:ClearAllPoints()
    name:SetPoint("LEFT", Row.NAME_LEFT, 0)
    name:SetPoint("RIGHT", -(used + 2), 0)
end

local hovered
local function optionsOf(button, row) return button.opts or row.opts or {} end

local function compareLines(tooltip, row, opts)
    local record, info = row.record, row.info
    if opts.charKey and opts.charKey ~= ns.charKey then return end
    local scale = ns.ActiveScale()
    local compare = row.compare or (opts.compare and opts.compare(record, info))
    if not compare then
        local character = ns.Character()
        compare = ns.Owned.Compare(record, info, scale, character.class, character.level)
    end
    tooltip:AddLine(" ")
    if compare.unique == "equipped" then
        tooltip:AddLine(L["Unique: already equipped"], 1, 0.4, 0.4)
    elseif compare.unique == "owned" then
        tooltip:AddLine(L["Unique: already owned"], 1, 0.6, 0.2)
    end
    if compare.twoHandBlock then
        tooltip:AddLine(L["Two-hand weapon equipped."], 0.7, 0.7, 0.7)
    elseif compare.empty then
        tooltip:AddLine(L["Slot empty."], 0.7, 0.7, 0.7)
    end
    -- no stat diff, the game's Shift compare already shows it
    if scale then
        local value = row.pawn or ns.Pawn.Value(record.id, scale)
        local label = ns.Pawn.Color(scale) .. ns.Pawn.Label(scale) .. "|r"
        if value then
            local upgrade = upgradeText({compare = compare, upgrade = compare.upgrade})
            tooltip:AddDoubleLine(format(L["Pawn (%s): %.1f"], label, value), upgrade, 1, 1, 1)
        end
        if record.randomBonus then
            tooltip:AddLine(L["Pawn rates base stats only; the bonus is random."], 0.7, 0.7, 0.7, true)
        end
        if info.setID or info.setName then tooltip:AddLine(L["Pawn doesn't count set bonuses."], 0.7, 0.7, 0.7, true) end
    end
    local price = row.auction or (opts.price and ns.Auctionator.ForRecord(record, info))
    if price and (price.old or not price.exact) then
        tooltip:AddLine(format(L["Auction price: %s"], ns.Auctionator.Text(price, true)), 1, 1, 1)
        if not price.exact then tooltip:AddLine(L["Cheapest random-bonus version."], 0.7, 0.7, 0.7, true) end
        if price.age then
            tooltip:AddLine(format(L["Last seen at auction %d days ago."], price.age), 0.7, 0.7, 0.7, true)
        else
            tooltip:AddLine(L["Not seen at auction for 21+ days."], 0.7, 0.7, 0.7, true)
        end
    end
    local set = (info.setID or info.setName) and ns.Sets.For(record)
    if set then tooltip:AddLine(format(L["Set: %s (%s)"], ns.Sets.Name(set), ns.Sets.Summary(set, L)), 1, 0.82, 0, true) end
    if row.status == "unknown" then tooltip:AddLine(L["Item data still loading."], 0.7, 0.7, 0.7, true) end
    if info.missing == "failed" then
        tooltip:AddLine(L["Not on this server: it says the item doesn't exist."], 1, 0.25, 0.25, true)
    elseif info.missing == "noanswer" then
        tooltip:AddLine(L["Maybe not on this server: it never sent the item."], 1, 0.25, 0.25, true)
    end
end

function Row.ShowTooltip(button)
    local row = button.data
    if not row or row.header then return end
    hovered = button
    local record, info = row.record, row.info
    local own = {sources = row.sources, charKey = optionsOf(button, row).charKey}
    ns.Tooltip.SetOwn(button, own)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if record.id and record.id > 0 then
        GameTooltip:SetItemByID(record.id)
    else
        -- no item tooltip runs for these, so the source goes here
        GameTooltip:SetText(info.name or record.name or "?", Labels.QualityRGB(info.quality))
        GameTooltip:AddLine(L["Not in the game data yet"], 1, 0.4, 0.4)
        for _, line in ipairs(ns.Restrictions.TipLines(record.tip)) do
            local left = ns.Restrictions.StripCodes(line.leftText)
            if left ~= "" then
                if line.rightText then
                    GameTooltip:AddDoubleLine(left, ns.Restrictions.StripCodes(line.rightText), 1, 1, 1, 1, 1, 1)
                else
                    GameTooltip:AddLine(left, 1, 1, 1, true)
                end
            end
        end
        own.noItem = true
        ns.Tooltip.Add(GameTooltip, record, own)
    end
    compareLines(GameTooltip, row, optionsOf(button, row))
    GameTooltip:Show()
    if record.id and record.id > 0 and IsShiftKeyDown() and GameTooltip_ShowCompareItem then
        pcall(GameTooltip_ShowCompareItem, GameTooltip)
    end
end

function Row.HideTooltip()
    hovered = nil
    GameTooltip:Hide()
end

local modifierFrame = CreateFrame("Frame")
modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
modifierFrame:SetScript("OnEvent", function()
    if hovered and hovered:IsVisible() and GameTooltip:GetOwner() == hovered then ns.Guard(Row.ShowTooltip, hovered) end
end)

function Row.LinkOf(record) return ns.Items.Link(record) end

function Row.OnClick(button, mouse)
    local row = button.data
    if not row or row.header then return end
    local record = row.record
    local link = Row.LinkOf(record)
    if link and IsModifiedClick() and HandleModifiedItemClick(link) then return end
    local charKey = optionsOf(button, row).charKey
    if mouse == "RightButton" then
        ns.Menu.Row(button, record, row, charKey)
    elseif record.id and record.id > 0 then
        ns.Favourites.Toggle(record.id, charKey)
    end
end
