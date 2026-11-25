-- tabs register themselves in ns.OptionsTabs
local ADDON_NAME, ns = ...
local L = ns.L
local W, Style = ns.Widgets, ns.Style

local Options = {}
ns.Options = Options
ns.OptionsTabs = ns.OptionsTabs or {}

local WIDTH, HEIGHT = 820, 600
Options.COLUMN, Options.COLUMN_GAP = 360, 30
Options.RIGHT = Options.COLUMN + Options.COLUMN_GAP
local frame, activeTab
local tabFrames = {} -- scroll areas by tab key

-- restack once the texts are set, they may wrap
local function fit(scroll) W.FitColumns(scroll) end

local function selectTab(key)
    activeTab = key
    for index, tab in ipairs(ns.OptionsTabs) do
        local selected = tab.key == key
        if selected then PanelTemplates_SetTab(frame, index) end
        if selected and not tabFrames[tab.key] then
            -- every tab scrolls, for long languages and small screens
            local scroll = W.ScrollArea(frame.Inset)
            scroll:SetPoint("TOPLEFT", 12, -12)
            scroll:SetPoint("BOTTOMRIGHT", -30, 12)
            tab.Create(scroll.content)
            tabFrames[tab.key] = scroll
        end
        local scroll = tabFrames[tab.key]
        if scroll then
            scroll:SetShown(selected)
            if selected then
                if tab.Refresh then tab.Refresh() end
                fit(scroll)
            end
        end
    end
end

function Options.GetVersionText()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    if not version or not version:match("^v?%d") then return "" end
    return format("v%s", (version:gsub("^v", "")))
end

local function create()
    frame = CreateFrame("Frame", "ForeverLootFinderOptions", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetTitle(ns.TITLE .. " — " .. L["Settings"])
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    -- not clamped, /flf reset brings it back
    frame:SetClampedToScreen(false)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "ForeverLootFinderOptions")

    frame.Inset:ClearAllPoints()
    frame.Inset:SetPoint("TOPLEFT", 4, -60)
    frame.Inset:SetPoint("BOTTOMRIGHT", -6, 26)

    local r, g, b = CreateColorFromHexString("ff1f1e21"):GetRGB()
    frame.Bg:SetColorTexture(r, g, b, 0.8)
    frame.Inset.Bg:Hide()

    frame.Tabs = {}
    for index, tab in ipairs(ns.OptionsTabs) do
        local button = CreateFrame("Button", nil, frame, "PanelTopTabButtonTemplate")
        button:SetID(index)
        button:SetText(tab.label)
        PanelTemplates_TabResize(button, 0)
        if index == 1 then
            button:SetPoint("BOTTOMLEFT", frame.Inset, "TOPLEFT", 8, -2)
        else
            button:SetPoint("LEFT", frame.Tabs[index - 1], "RIGHT", 4, 0)
        end
        button:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            selectTab(tab.key)
        end)
        frame.Tabs[index] = button
    end
    PanelTemplates_SetNumTabs(frame, #frame.Tabs)

    local version = W.Label(frame, Options.GetVersionText(), 10)
    version:SetPoint("BOTTOMRIGHT", -12, 8)
    version:SetJustifyH("RIGHT")
    frame.versionText = version

    frame:SetScript("OnHide", W.CloseMenu)
    selectTab(ns.OptionsTabs[1].key)
end

function Options:ResetPosition()
    if not frame then create() end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
end

function Options:Toggle()
    if not frame then create() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        selectTab(activeTab)
    end
end

function Options:Open(tabKey)
    if not frame then create() end
    frame:Show()
    selectTab(tabKey or activeTab)
end

function Options:IsShown() return frame ~= nil and frame:IsShown() end

function Options:RefreshActiveTab()
    if not frame or not frame:IsShown() then return end
    for _, tab in ipairs(ns.OptionsTabs) do
        if tab.key == activeTab then
            if tab.Refresh then tab.Refresh() end
            if tabFrames[tab.key] then fit(tabFrames[tab.key]) end
        end
    end
end

function Options:OnProfileChanged() self:RefreshActiveTab() end

local dialogs = {} -- "main", "dump"

local function createDialog()
    local dialog = CreateFrame("Frame", nil, UIParent)
    dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTranslucentTemplate")
    dialog.Border:SetAllPoints()
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetToplevel(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetPoint("CENTER")
    dialog.title = W.Label(dialog, "", 14)
    dialog.title:SetPoint("TOP", 0, -16)
    dialog.title:SetJustifyH("CENTER")
    dialog.message = W.Label(dialog, "")
    dialog.message:SetJustifyV("TOP")
    dialog.input = W.MultiLineEditBox(dialog)
    dialog.fieldLabel = W.Label(dialog, "", nil, Style.MUTED)
    dialog.field = W.EditBox(dialog, 300)
    dialog.buttons = {}
    dialog:Hide()
    return dialog
end

-- opts: title, buttons {{label, onClick(value)}}, and message, input {text, readOnly}, field {label, text}, instance.
-- instance "dump" opens beside the main dialog instead of replacing it
function Options:ShowDialog(opts)
    local key = opts.instance or "main"
    local dialog = dialogs[key]
    if not dialog then
        dialog = createDialog()
        dialogs[key] = dialog
        if key ~= "main" then dialog:SetFrameLevel(dialog:GetFrameLevel() + 50) end
    end
    W.CloseMenu()
    local width = opts.input and 620 or 460
    local inner = width - 48
    local y = 44
    dialog.title:SetText(opts.title or "")

    dialog.message:SetShown(opts.message ~= nil)
    if opts.message then
        dialog.message:ClearAllPoints()
        dialog.message:SetPoint("TOPLEFT", 24, -y)
        dialog.message:SetWidth(inner)
        dialog.message:SetText(opts.message)
        y = y + dialog.message:GetStringHeight() + 12
    end

    dialog.fieldLabel:SetShown(opts.field ~= nil)
    dialog.field:SetShown(opts.field ~= nil)
    if opts.field then
        dialog.fieldLabel:SetText(opts.field.label or "")
        dialog.fieldLabel:ClearAllPoints()
        dialog.fieldLabel:SetPoint("TOPLEFT", 24, -y)
        dialog.field:ClearAllPoints()
        dialog.field:SetPoint("TOPLEFT", 30, -(y + 16))
        dialog.field:SetText(opts.field.text or "")
        y = y + 50
    end

    dialog.input:SetShown(opts.input ~= nil)
    if opts.input then
        dialog.input:ClearAllPoints()
        dialog.input:SetPoint("TOPLEFT", 24, -y)
        dialog.input:SetSize(inner, 300)
        y = y + 312
        local edit = dialog.input.edit
        edit:SetText(opts.input.text or "")
        if opts.input.readOnly then
            -- read-only, typing puts the text back
            local fixed = opts.input.text or ""
            edit.onUserInput = function(box)
                box:SetText(fixed)
                box:HighlightText()
            end
        else
            edit.onUserInput = nil
        end
        edit:SetFocus()
        edit:HighlightText()
    elseif opts.field then
        dialog.field:SetFocus()
    end

    dialog:SetSize(width, math.max(140, y + 56))

    for _, button in ipairs(dialog.buttons) do button:Hide() end
    local right = -24
    for index = #opts.buttons, 1, -1 do
        local spec = opts.buttons[index]
        local button = dialog.buttons[index]
        if not button then
            button = W.Button(dialog, "", nil, 24)
            dialog.buttons[index] = button
        end
        button:SetLabel(spec.label)
        button:FitWidth(30)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", right, 20)
        right = right - button:GetWidth() - 6
        button:SetScript("OnClick", function()
            local value
            if opts.input then
                value = dialog.input.edit:GetText()
            elseif opts.field then
                value = dialog.field:GetText()
            end
            dialog:Hide()
            if spec.onClick then spec.onClick(value) end
        end)
        button:Show()
    end
    dialog:Show()
    dialog:Raise()
    return dialog
end

function Options:DialogText(instance)
    local dialog = dialogs[instance or "main"]
    return dialog and dialog:IsShown() and dialog.input.edit:GetText() or nil
end

function Options:Confirm(message, buttons) self:ShowDialog({title = L["Please confirm"], message = message, buttons = buttons}) end

function Options:ShowMessage(message) self:ShowDialog({title = ns.TITLE, message = message, buttons = {{label = L["Close"]}}}) end

function Options:ShowProfileExport()
    self:ShowDialog({
        title = L["Export profile"],
        message = L["Copy (Ctrl+C) and share."],
        input = {text = ns.ImportExport.ExportProfile(), readOnly = true},
        buttons = {{label = L["Close"]}},
    })
end

function Options:ShowProfileImport()
    local IE = ns.ImportExport
    local db = ns.addon.db
    self:ShowDialog({
        title = L["Import profile"],
        message = L["Paste a profile string (Ctrl+V)."],
        input = {text = ""},
        buttons = {
            {
                label = L["Import"],
                onClick = function(text)
                    local data, err = IE.Decode(text)
                    if not data then
                        self:ShowMessage(err)
                        return
                    end
                    local function intoNew(name)
                        name = strtrim(name or "")
                        if name == "" then
                            self:ShowMessage(L["Enter a profile name."])
                            return
                        end
                        local exists = false
                        for _, existing in ipairs(db:GetProfiles()) do
                            if existing == name then exists = true end
                        end
                        local function apply()
                            db:SetProfile(name)
                            if exists then db:ResetProfile() end
                            IE.Apply(data)
                        end
                        if exists then
                            self:Confirm(format(L["Profile \"%s\" exists. Overwrite?"], name),
                                         {{label = L["Overwrite"], onClick = apply}, {label = L["Cancel"]}})
                        else
                            apply()
                        end
                    end
                    self:ShowDialog({
                        title = L["Import profile"],
                        message = IE.Summary(data) .. "\n\n"
                          .. format(L["Import into a new profile or over \"%s\"?"], db:GetCurrentProfile()),
                        field = {label = L["New profile name"], text = L["Imported"]},
                        buttons = {
                            {label = L["Create profile"], onClick = intoNew}, {
                                label = L["Into current"],
                                onClick = function()
                                    self:Confirm(format(L["Overwrite \"%s\"?"], db:GetCurrentProfile()), {
                                        {label = L["Overwrite"], onClick = function()
                                            IE.Apply(data)
                                        end}, {label = L["Cancel"]},
                                    })
                                end,
                            }, {label = L["Cancel"]},
                        },
                    })
                end,
            }, {label = L["Cancel"]},
        },
    })
end

function Options:ShowFavouritesExport(charKey)
    self:ShowDialog({
        title = L["Export favourites"],
        message = format(L["Favourites of %s. Copy (Ctrl+C) and share."], ns.Favourites.CharacterName(charKey)),
        input = {text = ns.Favourites.Export(charKey), readOnly = true},
        buttons = {{label = L["Close"]}},
    })
end

function Options:ShowFavouritesImport(charKey)
    local F = ns.Favourites
    self:ShowDialog({
        title = L["Import favourites"],
        message = format(L["Paste a favourites string (Ctrl+V) for %s."], F.CharacterName(charKey)),
        input = {text = ""},
        buttons = {
            {
                label = L["Import"],
                onClick = function(text)
                    local data, err = F.Decode(text)
                    if not data then
                        self:ShowMessage(err)
                        return
                    end
                    self:ShowDialog({
                        title = L["Import favourites"],
                        message = F.Summary(data, charKey) .. "\n\n"
                          .. L["Merge adds new items and keeps your tiers. Overwrite replaces the list."],
                        buttons = {
                            {label = L["Merge"], onClick = function()
                                F.ApplyDecoded(data, "merge", charKey)
                            end}, {label = L["Overwrite"], onClick = function()
                                F.ApplyDecoded(data, "overwrite", charKey)
                            end}, {label = L["Cancel"]},
                        },
                    })
                end,
            }, {label = L["Cancel"]},
        },
    })
end

function Options:ImportBiS(list)
    local F = ns.Favourites
    local plan = F.BiSPlan(list)
    if #plan.new == 0 then
        self:ShowMessage(L["Nothing new to import."] .. "\n\n" .. F.FDJSummary(plan))
        return
    end
    self:Confirm(format(L["Add %s to your favourites as \"BiS\"?"], ns.AtlasLootBiS.Label(list)) .. "\n\n" .. F.FDJSummary(plan),
                 {{label = L["Import"], onClick = function() F.ApplyBiS(plan) end}, {label = L["Cancel"]}})
end

-- FDJ's own list is left alone

function Options:ImportFDJ()
    local F = ns.Favourites
    local plan = F.FDJPlan()
    if #plan.new == 0 then
        self:ShowMessage(L["Nothing new to import."] .. "\n\n" .. F.FDJSummary(plan))
        return
    end
    self:Confirm(L["Copy this character's Dungeon Journal favourites as \"Nice to have\"?"] .. "\n\n" .. F.FDJSummary(plan),
                 {{label = L["Import"], onClick = function() F.ApplyFDJ(plan) end}, {label = L["Cancel"]}})
end
