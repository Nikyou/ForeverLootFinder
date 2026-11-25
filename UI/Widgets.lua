-- widget helpers on stock Blizzard templates
local _, ns = ...

local Style = {
    ACCENT = {NORMAL_FONT_COLOR:GetRGBA()},
    TEXT = {HIGHLIGHT_FONT_COLOR:GetRGBA()},
    MUTED = {GRAY_FONT_COLOR:GetRGBA()},
    WARN = {RED_FONT_COLOR:GetRGBA()},
    GOOD = {0.25, 1, 0.25},
    SELECTED = {1, 0.82, 0, 0.25},
    HIGHLIGHT_TEXTURE = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
}
ns.Style = Style

local W = {}
ns.Widgets = W

-- size -> font object: 14+ large gold, 13 gold, 12 white, 11 small white, 10 small grey
local function fontObject(size)
    if size and size >= 14 then return "GameFontNormalLarge" end
    if size == 13 then return "GameFontNormal" end
    if size == 11 then return "GameFontHighlightSmall" end
    if size and size <= 10 then return "GameFontDisableSmall" end
    return "GameFontHighlight"
end

function W.Label(parent, text, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject(size))
    if color then label:SetTextColor(unpack(color)) end
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    return label
end

local GROUP_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 3, right = 3, top = 5, bottom = 3},
}

function W.Group(parent)
    local group = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    group:SetBackdrop(GROUP_BACKDROP)
    group:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    group:SetBackdropBorderColor(0.4, 0.4, 0.4)
    return group
end

W.Panel = W.Group

function W.Divider(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    return line
end

function W.StyleRow(row)
    row:SetHighlightTexture(Style.HIGHLIGHT_TEXTURE, "ADD")
    row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTexture:SetAllPoints()
    row.selectedTexture:SetTexture(Style.HIGHLIGHT_TEXTURE)
    row.selectedTexture:SetBlendMode("ADD")
    row.selectedTexture:SetVertexColor(unpack(Style.SELECTED))
    row.selectedTexture:Hide()
    function row:SetRowSelected(selected) self.selectedTexture:SetShown(selected and true or false) end
end

function W.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 100, height or 22)
    button:SetText(text or "")
    button:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    function button:SetLabel(value) self:SetText(value) end
    function button:FitWidth(padding) self:SetWidth(self:GetTextWidth() + (padding or 24)) end
    return button
end

function W.IconButton(parent, texture, size, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size or 20, size or 20)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(texture)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    return button
end

function W.CheckBox(parent, text, onChange)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box.Text:SetFontObject("GameFontHighlight")
    box:SetScript("OnClick", function(self) if onChange then onChange(self:GetChecked()) end end)
    function box:SetLabel(value)
        self.Text:SetText(value)
        self:SetHitRectInsets(0, -(self.Text:GetStringWidth() + 4), 0, 0)
    end
    function box:GetFullWidth() return 24 + self.Text:GetStringWidth() + 4 end
    box:SetLabel(text or "")
    return box
end

-- fill(tooltip) runs on every hover
function W.AddTooltip(widget, fill)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fill(GameTooltip)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- why = {reason} or {needs = addon names}, hint optional
function W.AddWhyLines(tooltip, title, why)
    local L = ns.L
    tooltip:AddLine(title)
    if why.reason then
        tooltip:AddLine(why.reason, 1, 1, 1, true)
    elseif why.needs then
        tooltip:AddLine(L["Needs one of these addons:"], 1, 1, 1, true)
        for _, name in ipairs(why.needs) do tooltip:AddLine("  " .. name, 0.6, 0.8, 1) end
    end
    if why.hint then tooltip:AddLine(why.hint, 1, 1, 1, true) end
end

function W.WhyTooltip(widget, title)
    -- a disabled button gets no OnEnter without it, and the why is only there while disabled
    if widget.SetMotionScriptsWhileDisabled then widget:SetMotionScriptsWhileDisabled(true) end
    widget:HookScript("OnEnter", function(self)
        if not self.why then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        W.AddWhyLines(GameTooltip, title, self.why)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function(self) if self.why then GameTooltip:Hide() end end)
end

-- shows a cut-short label in full on hover
function W.FullTextTooltip(widget, label)
    widget:HookScript("OnEnter", function(self)
        local text = label:GetText()
        if not text or text == "" or (label.IsTruncated and not label:IsTruncated()) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
end

function W.Debounce(delay, fn)
    local token = 0
    return function(...)
        token = token + 1
        local mine, args, count = token, {...}, select("#", ...)
        C_Timer.After(delay, function() if mine == token then fn(unpack(args, 1, count)) end end)
    end
end

-- onChange only fires for user edits, not SetText
function W.EditBox(parent, width, onChange)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width or 200, 20)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetScript("OnEnterPressed", edit.ClearFocus)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnTextChanged", function(self, userInput) if userInput and onChange then onChange(self:GetText()) end end)
    return edit
end

-- a number box: onChange(number) on Enter or focus loss, clamped
function W.NumberBox(parent, width, minValue, maxValue, onChange)
    local edit = W.EditBox(parent, width)
    edit:SetNumeric(false)
    edit:SetJustifyH("CENTER")
    local function commit(self)
        local value = tonumber(((self:GetText() or ""):gsub(",", ".")))
        if value then
            value = math.max(minValue, math.min(maxValue, value))
            if onChange then onChange(value) end
        end
    end
    edit:SetScript("OnEnterPressed", function(self)
        commit(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", commit)
    edit:SetScript("OnTextChanged", nil)
    return edit
end

-- the scroll bar hangs off the right edge, leave ~20px for it
function W.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    scroll:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    function scroll:SetContentHeight(height) content:SetHeight(math.max(1, height)) end
    return scroll
end

-- clicking anywhere on the panel focuses the edit box
function W.MultiLineEditBox(parent)
    local panel = W.Panel(parent)
    local scroll = W.ScrollArea(panel)
    scroll:SetPoint("TOPLEFT", 8, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, scroll.content)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetPoint("TOPLEFT")
    edit:SetPoint("TOPRIGHT")
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnTextChanged", function(self, userInput)
        scroll:SetContentHeight(self:GetHeight())
        if userInput and self.onUserInput then self.onUserInput(self) end
    end)
    edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    edit:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function() edit:SetFocus() end)
    panel.edit = edit
    return panel
end

-- onChange only fires for user changes, holder:SetValue() is silent
function W.Slider(parent, text, minValue, maxValue, step, width, onChange)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, text and 40 or 20)
    holder.label = W.Label(holder, text)
    holder.label:SetPoint("TOPLEFT")

    local slider = CreateFrame("Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("BOTTOMLEFT")
    slider:SetPoint("BOTTOMRIGHT", -40, 0)
    slider:SetHeight(20)
    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right,
                                                                                    function(value)
            return step < 1 and format("%.1f", value) or tostring(math.floor(value + 0.5))
        end),
    }
    slider:Init(minValue, minValue, maxValue, (maxValue - minValue) / step, formatters)

    local updating = false
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
                            function(_, value) if not updating and onChange then onChange(value) end end, holder)

    function holder:SetValue(value)
        updating = true
        slider:SetValue(value)
        updating = false
    end
    -- e.g. "level + 0..10" vs a fixed 1..60
    function holder:SetRange(low, high, value)
        if self.low == low and self.high == high then return self:SetValue(value) end
        self.low, self.high = low, high
        updating = true
        slider:Init(value, low, high, (high - low) / step, formatters)
        updating = false
    end
    holder.slider = slider
    return holder
end

local MENU_SCROLL_EXTENT = 400

function W.CloseMenu()
    local manager = Menu and Menu.GetManager and Menu.GetManager()
    if manager then manager:CloseMenus() end
end

-- getItems() -> {{value, text, header?}}, read again when the menu opens or on SetValue(value, true)
function W.Dropdown(parent, width, getItems, onSelect, placeholder)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    if placeholder then dropdown:SetDefaultText(placeholder) end

    local items
    local relabel = false
    local function isSelected(value) return dropdown.value == value end
    local disabled = {}
    local function setSelected(value)
        -- older menus have no SetEnabled, a greyed entry stays clickable there
        if disabled[value] then return end
        dropdown.value = value
        onSelect(value)
    end
    dropdown:SetupMenu(function(_, root)
        if not (relabel and items) then items = getItems() end
        wipe(disabled)
        for _, item in ipairs(items) do
            if item.header then
                root:CreateTitle(item.text)
            else
                local text = item.disabled and ("|cff808080" .. item.text .. "|r") or item.text
                local radio = root:CreateRadio(text, isSelected, setSelected, item.value)
                if item.disabled then
                    disabled[item.value] = true
                    if radio and radio.SetEnabled then radio:SetEnabled(false) end
                end
                if item.tooltip and radio and radio.SetTooltip then
                    radio:SetTooltip(function(tooltip) item.tooltip(tooltip) end)
                end
            end
        end
        if #items > 20 then root:SetScrollMode(MENU_SCROLL_EXTENT) end
    end)

    local function find(value)
        for _, item in ipairs(items) do if not item.header and item.value == value then return item.text end end
    end
    -- may be new, e.g. a Pawn scale
    local function labelOf(value)
        if not items then items = getItems() end
        local label = find(value)
        if label == nil and value ~= nil then
            items = getItems()
            label = find(value)
        end
        return label
    end
    local function isOpen() return dropdown.IsMenuOpen and dropdown:IsMenuOpen() end
    -- GenerateMenu() on an open menu rebuilds it under the mouse, and the window refreshes a lot while items
    -- load. only on a real change, and once the menu is closed
    local function apply()
        local label = labelOf(dropdown.value)
        if dropdown.shownValue == dropdown.value and dropdown.shownLabel == label then return end
        if isOpen() then
            dropdown.pending = true
            return
        end
        dropdown.pending = nil
        dropdown.shownValue, dropdown.shownLabel = dropdown.value, label
        relabel = true
        dropdown:GenerateMenu()
        relabel = false
    end
    if dropdown.RegisterCallback and DropdownButtonMixin and DropdownButtonMixin.Event and DropdownButtonMixin.Event.OnMenuClose then
        dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose,
                                  function() if dropdown.pending then C_Timer.After(0, apply) end end, dropdown)
    end

    -- reread: the texts may have changed too (a count, a level)
    function dropdown:SetValue(value, reread)
        self.value = value
        if reread then
            items = nil
        elseif value == self.shownValue then
            return
        end
        apply()
    end
    return dropdown
end

function W.ContextMenu(owner, generator)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, generator)
end

-- the raid star desaturated, then tinted with the tier colour
function W.SetStar(texture, tier)
    texture:SetTexture(ns.Tooltip.STAR_TEXTURE)
    local data = tier and ns.Favourites.BY_TIER[tier]
    if data then
        texture:SetDesaturated(true)
        texture:SetVertexColor(data.color[1], data.color[2], data.color[3])
        texture:SetAlpha(1)
    else
        texture:SetDesaturated(true)
        texture:SetVertexColor(0.5, 0.5, 0.5)
        texture:SetAlpha(0.35)
    end
end

function W.SectionTitle(parent, text) return W.Label(parent, text, 13, Style.ACCENT) end

function W.Help(parent, text, width)
    local label = W.Label(parent, text, 11, Style.MUTED)
    label:SetWidth(width)
    return label
end

local LINE = 14 -- what an empty label reserves

-- col.layout() restacks from the current heights, texts change and widgets hide
function W.Column(parent, x, width)
    local col = {y = 0, x = x, width = width, items = {}}
    parent.columns = parent.columns or {}
    table.insert(parent.columns, col)

    local function add(widget, place, height, gap)
        col.items[#col.items + 1] = {widget = widget, place = place, height = height, gap = gap or 0}
        if col.y > 0 then col.y = col.y + (gap or 0) end
        place(col.y)
        col.y = col.y + height()
        return widget
    end
    local function at(widget, indent)
        return function(y)
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", x + (indent or 0), -y)
        end
    end
    local function fixed(height) return function() return height end end

    function col.layout()
        local y = 0
        for _, item in ipairs(col.items) do
            if not item.widget or item.widget:IsShown() then
                if y > 0 then y = y + item.gap end
                item.place(y)
                y = y + item.height()
            end
        end
        col.y = y
        return y
    end

    function col.title(text)
        local label = W.SectionTitle(parent, text)
        return add(label, at(label), fixed(24), 10)
    end
    -- Russian labels are long, let them wrap
    function col.check(text, onChange, indent)
        indent = indent or 0
        local box = W.CheckBox(parent, text, onChange)
        box.Text:SetWidth(width - indent - 30)
        box.Text:SetJustifyH("LEFT")
        box:SetHitRectInsets(0, -math.min(box.Text:GetStringWidth() + 4, width - indent - 26), 0, 0)
        return add(box, at(box, indent), function() return math.max(26, box.Text:GetStringHeight() + 12) end)
    end
    function col.help(text, indent)
        indent = indent or 28
        local label = W.Help(parent, text, width - indent)
        return add(label, at(label, indent), function() return label:GetStringHeight() + 8 end)
    end
    function col.label(text)
        local label = W.Label(parent, text)
        label:SetWidth(width)
        return add(label, at(label), function() return math.max(LINE, label:GetStringHeight()) + 6 end)
    end
    function col.place(widget, height, indent) return add(widget, at(widget, indent), fixed(height)) end
    function col.row(height, entries)
        return add(entries[1][1], function(y)
            for _, entry in ipairs(entries) do
                entry[1]:ClearAllPoints()
                entry[1]:SetPoint("TOPLEFT", x + entry[2], -y)
            end
        end, fixed(height))
    end
    return col
end

function W.FitColumns(scroll, padding)
    local height = 0
    for _, col in ipairs(scroll.content.columns or {}) do height = math.max(height, col.layout()) end
    scroll:SetContentHeight(height + (padding or 16))
    return height
end
