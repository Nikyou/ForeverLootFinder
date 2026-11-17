-- the card view behind every tab except By slot and Favourites
local _, ns = ...
local L = ns.L
local W, Style, Labels = ns.Widgets, ns.Style, ns.Labels

local Cards = {}
ns.Cards = Cards

local ICON, GAP = 32, 4
Cards.TOP = 32 -- the tab's top bar, also a card's header

-- every card tab shares one slot setting
local function slotItems()
    local items = {{value = "ALL", text = L["All slots"]}}
    for _, slot in ipairs(ns.Index.SLOTS) do items[#items + 1] = {value = slot, text = Labels.Slot(slot)} end
    return items
end

function Cards.SlotDropdown(parent)
    local label = W.Label(parent, L["Slot:"], 11, Style.MUTED)
    label:SetPoint("TOPLEFT", 4, -6)
    local dropdown = W.Dropdown(parent, 180, slotItems, function(value)
        ns.Filters().dungeonSlot = value
        ns.FireChange("filters")
    end)
    dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
    return dropdown
end

function Cards.Slot()
    local slot = ns.Filters().dungeonSlot
    return slot ~= "ALL" and slot or nil
end

function Cards.Create(parent, top)
    local view = {cards = {}, icons = {}}
    view.scroll = W.ScrollArea(parent)
    view.scroll:SetPoint("TOPLEFT", 0, -(top or Cards.TOP))
    view.scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    view.empty = W.Label(parent, L["No items match the filters."], 12, Style.MUTED)
    view.empty:SetPoint("CENTER")
    view.empty:SetJustifyH("CENTER")

    local function card(i)
        local c = view.cards[i]
        if c then return c end
        c = W.Group(view.scroll.content)
        c.name = CreateFrame("Button", nil, c)
        c.name:SetPoint("TOPLEFT", 10, -8)
        c.name:SetHeight(18)
        c.name.text = W.Label(c.name, "", 13, Style.ACCENT)
        c.name.text:SetPoint("LEFT")
        c.name:SetScript("OnClick", function(self) if self.onClick then ns.Guard(self.onClick) end end)
        W.AddTooltip(c.name, function(tooltip)
            if c.name.fillTooltip then
                c.name.fillTooltip(tooltip)
            else
                tooltip:AddLine(c.name.text:GetText() or "")
            end
        end)
        c.info = W.Label(c, "", 11, Style.MUTED)
        c.info:SetPoint("LEFT", c.name, "RIGHT", 10, 0)
        c.glow = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        c.glow:SetPoint("TOPLEFT", 3, -3)
        c.glow:SetPoint("BOTTOMRIGHT", -3, 3)
        c.glow:SetColorTexture(0.2, 0.6, 0.2, 0.18)
        c.labels = {}
        view.cards[i] = c
        return c
    end

    local function iconButton(i)
        local b = view.icons[i]
        if b then return b end
        b = CreateFrame("Button", nil, view.scroll.content)
        b:SetSize(ICON, ICON)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.border = b:CreateTexture(nil, "OVERLAY")
        b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
        b.border:SetAllPoints()
        b.star = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.star:SetSize(14, 14)
        b.star:SetPoint("TOPRIGHT", 3, 3)
        b.chance = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.chance:SetPoint("BOTTOMRIGHT", 1, 1)
        b.chance:SetJustifyH("RIGHT")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self) ns.Guard(ns.Row.ShowTooltip, self) end)
        b:SetScript("OnLeave", function() ns.Row.HideTooltip() end)
        b:SetScript("OnClick", function(self, mouse) ns.Guard(ns.Row.OnClick, self, mouse) end)
        view.icons[i] = b
        return b
    end

    -- so group headers draw above the card's backdrop
    local function groupLabel(c, i)
        local label = c.labels[i]
        if label then return label end
        label = W.Label(c, "", 11, Style.MUTED)
        label:SetWordWrap(false)
        c.labels[i] = label
        return label
    end

    function view:ScrollToTop() self.scroll:SetVerticalScroll(0) end

    -- buttons stay shown while rebound, so a hovered icon keeps its tooltip
    function view:Render(list, opts)
        local width = self.scroll:GetWidth()
        if not width or width < 100 then width = 600 end
        local perLine = math.max(1, math.floor((width - 24) / (ICON + GAP)))
        local profile = ns.addon.db.profile
        local y, used = 0, 0
        for i, entry in ipairs(list) do
            local c = card(i)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, -y)
            c:SetPoint("RIGHT", -2, 0)
            c.name.onClick, c.name.fillTooltip = entry.onClick, entry.fillTooltip
            c.name.text:SetText(entry.title or "?")
            c.name:SetWidth(c.name.text:GetStringWidth() + 4)
            c.info:SetText(entry.info or "")
            c.glow:SetShown(entry.glow and true or false)
            c:SetAlpha(entry.dim and 0.45 or 1)
            local inner, labelCount = Cards.TOP, 0
            for _, group in ipairs(entry.groups or {}) do
                if group.label and group.label ~= "" then
                    labelCount = labelCount + 1
                    local label = groupLabel(c, labelCount)
                    label:ClearAllPoints()
                    label:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -inner)
                    label:SetPoint("RIGHT", c, "RIGHT", -12, 0)
                    label:SetText(group.label)
                    label:Show()
                    inner = inner + 16
                end
                for n, row in ipairs(group.rows) do
                    used = used + 1
                    row.opts = opts
                    local b = iconButton(used)
                    b.data = row
                    local column, line = (n - 1) % perLine, math.floor((n - 1) / perLine)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + column * (ICON + GAP), -(inner + line * (ICON + GAP)))
                    b.icon:SetTexture(row.info.icon or 134400)
                    b.border:SetVertexColor(Labels.QualityRGB(row.info.quality))
                    local tier = row.record.id > 0 and ns.Favourites.Get(row.record.id)
                    b.star:SetShown(profile.stars and tier and true or false)
                    if tier then W.SetStar(b.star, tier) end
                    local chance = profile.cardChance ~= false and group.chances and group.chances[n]
                    b.chance:SetText(chance and ns.Labels.Chance(chance) or "")
                    b:SetAlpha((row.status == "unknown" or row.status == "missing") and 0.5 or 1)
                    b:SetFrameLevel(c:GetFrameLevel() + 5)
                    b:Show()
                    ns.Row.RefreshTooltip(b)
                end
                inner = inner + math.ceil(#group.rows / perLine) * (ICON + GAP) + 4
            end
            for n = labelCount + 1, #c.labels do c.labels[n]:Hide() end
            c:SetHeight(math.max(36, inner + 6))
            c:Show()
            y = y + c:GetHeight() + 6
        end
        for i = #list + 1, #self.cards do self.cards[i]:Hide() end
        for i = used + 1, #self.icons do
            local b = self.icons[i]
            if GameTooltip:GetOwner() == b then ns.Row.HideTooltip() end
            b.data = nil
            b:Hide()
        end
        self.scroll:SetContentHeight(y)
    end

    return view
end

-- an item counts once per card however many of its groups it's in
local function collect(spec, rows, ctx, grouped)
    local cards, order, shown, counted = {}, {}, 0, {}
    for _, row in ipairs(rows) do
        local seen = {}
        for _, source in ipairs(row.sources) do
            if spec.accept(source, ctx) then
                local cardKey, title, cardOrder = spec.card(source, ctx)
                local card = cards[cardKey]
                if not card then
                    card = {key = cardKey, title = title, order = cardOrder or 0, groups = {}, list = {}, items = 0, has = {}}
                    cards[cardKey] = card
                    order[#order + 1] = card
                end
                if spec.onSource then spec.onSource(card, source, ctx) end
                local groupKey, groupLabel, groupOrder = "", "", 0
                if grouped then groupKey, groupLabel, groupOrder = spec.group(source, ctx) end
                local seenKey = tostring(cardKey) .. "\001" .. tostring(groupKey)
                if not seen[seenKey] then
                    seen[seenKey] = true
                    local group = card.groups[groupKey]
                    if not group then
                        group = {label = groupLabel or "", order = groupOrder or (#card.list + 1), rows = {}, chances = {}}
                        card.groups[groupKey] = group
                        card.list[#card.list + 1] = group
                    end
                    group.rows[#group.rows + 1] = row
                    group.chances[#group.rows] = source.chance
                    if not card.has[row] then
                        card.has[row] = true
                        card.items = card.items + 1
                    end
                    if not counted[row] then
                        counted[row] = true
                        shown = shown + 1
                    end
                end
            end
        end
    end
    for _, card in ipairs(order) do
        table.sort(card.list, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.label < b.label
        end)
    end
    return cards, order, shown
end

local function plainEntries(_, order, _, _)
    table.sort(order, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.title < b.title
    end)
    local list = {}
    for _, card in ipairs(order) do
        list[#list + 1] = {title = card.title, info = format(L["%d items"], card.items), groups = card.list}
    end
    return list
end

-- spec: key, label, accept, card, group?, grouping?, onSource?, entries?, emptyHint?. see DungeonTab for a full one.
-- without spec.grouping a tab with group() always groups
function Cards.Tab(spec)
    local ui = {}

    local function create(parent)
        ui.slot = Cards.SlotDropdown(parent)
        if spec.grouping then
            ui.group = W.CheckBox(parent, "", function(on)
                spec.grouping.set(ns.addon.db.profile, on)
                ns.FireChange("view")
            end)
            ui.group.Text:SetFontObject("GameFontHighlightSmall")
            ui.group:SetLabel(spec.grouping.label)
            ui.group:SetPoint("LEFT", ui.slot, "RIGHT", 14, 0)
        end
        ui.view = Cards.Create(parent)
    end

    local function refresh(ctx, kinds)
        local index = ns.GetIndex()
        if not index then return end
        local slot = ns.Filters().dungeonSlot or "ALL"
        ui.slot:SetValue(slot)
        local grouped = spec.group ~= nil
        if spec.grouping then
            grouped = spec.grouping.get(ns.addon.db.profile) and true or false
            ui.group:SetChecked(grouped)
        end
        local rows
        rows, ctx = ns.MainWindow.Rows(nil, Cards.Slot(), nil, ctx)
        local cards, order, shown = collect(spec, rows, ctx, grouped)
        local list = (spec.entries or plainEntries)(cards, order, ctx, index)
        ui.view:Render(list, ns.MainWindow.RowOptions(nil, nil, ctx))
        -- new data keeps the scroll position
        if (kinds and kinds.tab) or ui.shownSlot ~= slot then
            ui.view:ScrollToTop()
            -- card by card, top first: the first dungeon (raid, zone) fills in before the next
            local records = {}
            for _, entry in ipairs(list) do
                for _, group in ipairs(entry.groups or {}) do
                    for _, row in ipairs(group.rows) do records[#records + 1] = row.record end
                end
            end
            ns.Items.Request(records, true)
        end
        ui.shownSlot = slot
        ns.MainWindow.shownCount = shown
        local empty = L["No items match the filters."]
        local hint = spec.emptyHint and spec.emptyHint(index)
        if hint then empty = empty .. "\n" .. hint end
        ui.view.empty:SetText(ns.MainWindow.EmptyText(empty))
        ui.view.empty:SetShown(shown == 0)
    end

    table.insert(ns.MainTabs, {key = spec.key, label = spec.label, Create = create, Refresh = refresh})
    return ui
end
