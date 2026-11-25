-- tabs register themselves in ns.MainTabs
local _, ns = ...
local L = ns.L
local W, Style = ns.Widgets, ns.Style

local MainWindow = {}
ns.MainWindow = MainWindow
ns.MainTabs = ns.MainTabs or {}

local MIN_WIDTH = 900
local PANEL_WIDTH = 300
local INSET_TOP, INSET_BOTTOM = 60, 26
local BODY_TOP, BODY_PAD = 54, 6 -- below the top bar and the filter summary
local SEARCH_DELAY = 0.2
local frame, activeTab
local tabFrames = {}

-- changes not drawn yet, while hidden or in combat
local missed, missedAll = {}, true

function MainWindow.IsShown() return frame ~= nil and frame:IsShown() end
function MainWindow.Frame() return frame end

-- tall enough for the slot rail
local function minHeight() return INSET_TOP + INSET_BOTTOM + BODY_TOP + BODY_PAD + ns.SlotTab.RailHeight() end

function MainWindow.SortSettings()
    local sort = ns.addon.db.char.sort
    local key = sort.key
    local scale = ns.ActiveScale()
    local entry = key and ns.Sort.BY_KEY[key]
    -- Pawn or Auctionator may be off by now
    if not key or (entry and entry.pawn and not scale) or (entry and entry.price and not ns.Auctionator.Active()) then
        key = scale and "pawn" or "ilvl"
    end
    local desc = sort.desc
    if desc == nil or sort.key ~= key then desc = ns.Sort.BY_KEY[key] and ns.Sort.BY_KEY[key].desc end
    return {key = key, desc = desc, stat = sort.stat}
end

-- the compare with worn gear only for the logged-in character
function MainWindow.PrepareRows(rows, ctx)
    local index = ns.GetIndex()
    local scale = ns.ActiveScale()
    local compare = ctx.ownCharacter ~= false and ctx.compare or nil
    local prices = ns.Auctionator.Active()
    for _, row in ipairs(rows) do
        local record, info = row.record, row.info
        if prices then row.auction = ns.Auctionator.ForRecord(record, info) end
        if scale and info.loaded and record.id > 0 then
            row.pawn = ns.Pawn.Value(record.id, scale)
            if compare then
                row.compare = compare(record, info)
                row.upgrade = row.compare.unique ~= "equipped" and row.compare.upgrade or nil
            end
        end
    end
    local sort = MainWindow.SortSettings()
    sort.dungeonByKey = index and index.dungeonByKey or {}
    ns.Sort.Rows(rows, sort)
    return rows
end

-- a card tab always shows its own sources: "PvP rewards" off still leaves the PvP tab its items
function MainWindow.Filters(tab)
    local filters = ns.Filters()
    local own = ns.Cards.OWN[tab or activeTab]
    if not own then return filters end
    local copy = {}
    for key, value in pairs(filters) do copy[key] = value end
    copy.sources = {}
    for key, value in pairs(filters.sources or {}) do copy.sources[key] = value end
    for _, kind in ipairs(own) do copy.sources[kind] = true end
    return copy
end

function MainWindow.ActiveTab() return activeTab end

function MainWindow.Rows(records, slot, charKey, ctx, state)
    local index = ns.GetIndex()
    if not index then return {}, ctx end
    ctx = ctx or ns.FilterContext(charKey)
    ctx.slot = slot
    local rows = ns.Filter.Run(records or index.records, ns.Items.Info, state or ns.Filters(), ctx)
    return MainWindow.PrepareRows(rows, ctx), ctx
end

-- every item of a slot, worked out once per index
local slotMaps = setmetatable({}, {__mode = "k"})
function MainWindow.RecordsOfSlot(slot)
    local index = ns.GetIndex()
    if not index then return {} end
    local map = slotMaps[index]
    if not map then
        map = {}
        for _, record in ipairs(index.records) do
            local itemSlot = ns.Items.Info(record).slot
            if itemSlot then
                map[itemSlot] = map[itemSlot] or {}
                table.insert(map[itemSlot], record)
            end
        end
        slotMaps[index] = map
    end
    return map[slot] or {}
end

local WEAPON_COLUMN_SLOTS = {ONEHAND = true, MAINHAND = true, TWOHAND = true, OFFHAND = true, RANGED = true}

function MainWindow.RowOptions(charKey, slot, ctx)
    local index = ns.GetIndex()
    local scale = ns.ActiveScale()
    return {
        pawn = scale ~= nil,
        scaleColor = scale and ns.Pawn.Color(scale) or "",
        chance = index and index.hasChance or false,
        dungeonByKey = index and index.dungeonByKey or {},
        charKey = charKey or ns.charKey,
        weapons = slot == nil or WEAPON_COLUMN_SLOTS[slot] == true,
        price = ns.Auctionator.Active(),
        columns = ns.addon.db.profile.columns,
        compare = ctx and ctx.ownCharacter ~= false and ctx.compare or nil,
    }
end

local function sortItems()
    local items = {}
    local scale = ns.ActiveScale()
    local index = ns.GetIndex()
    if scale then
        items[#items + 1] = {value = "pawn", text = L["Score"]}
        items[#items + 1] = {value = "upgrade", text = L["Upgrade %"]}
    end
    items[#items + 1] = {value = "ilvl", text = L["Item level"]}
    items[#items + 1] = {value = "reqlevel", text = L["Required level"]}
    items[#items + 1] = {value = "dungeonlevel", text = L["Dungeon level"]}
    items[#items + 1] = {value = "speed", text = L["Weapon speed"]}
    items[#items + 1] = {value = "dps", text = L["Weapon DPS"]}
    if index and index.hasChance then items[#items + 1] = {value = "chance", text = L["Drop chance"]} end
    -- the sort list follows the data, not the visible columns
    if ns.Auctionator.Active() then items[#items + 1] = {value = "price", text = L["Auction price"]} end
    items[#items + 1] = {value = "name", text = L["Name"]}
    items[#items + 1] = {value = "quality", text = L["Quality"]}
    items[#items + 1] = {header = true, text = L["One stat"]}
    for _, stat in ipairs(ns.StatMap.STATS) do
        items[#items + 1] = {value = "stat:" .. stat.key, text = ns.Labels.Stat(stat.key)}
    end
    return items
end

function MainWindow.SetSort(key, stat)
    local sort = ns.addon.db.char.sort
    local current = MainWindow.SortSettings()
    if key == current.key and (key ~= "stat" or stat == sort.stat) then
        sort.desc = not current.desc
    else
        sort.desc = nil
    end
    sort.key = key
    if stat then sort.stat = stat end
    ns.FireChange("sort")
end

local function pawnItems()
    local items, lastHeader = {}, nil
    for _, scale in ipairs(ns.Pawn.Scales()) do
        local header = scale.header or (scale.visible and L["Visible scales"] or L["Other scales"])
        if header ~= lastHeader then
            items[#items + 1] = {header = true, text = header}
            lastHeader = header
        end
        items[#items + 1] = {value = scale.name, text = scale.label}
    end
    return items
end

-- By slot and Favourites can't be hidden
MainWindow.OPTIONAL_TABS = {
    dungeon = true,
    raids = true,
    quests = true,
    crafts = true,
    reputation = true,
    pvp = true,
    events = true,
}

function MainWindow.TabShown(key)
    if not MainWindow.OPTIONAL_TABS[key] then return true end
    if key == "raids" and not ns.Index.RAIDS_OPEN then return false end
    local tabs = ns.addon.db.profile.tabs
    return not (tabs and tabs[key] == false)
end

local function layoutTabs()
    local previous
    for index, tab in ipairs(ns.MainTabs) do
        local button = frame.Tabs[index]
        local shown = MainWindow.TabShown(tab.key)
        button:SetShown(shown)
        if shown then
            button:ClearAllPoints()
            if previous then
                button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else
                button:SetPoint("BOTTOMLEFT", frame.Inset, "TOPLEFT", 8, -2)
            end
            previous = button
        end
    end
end

local function selectTab(key)
    if not MainWindow.TabShown(key) then key = ns.MainTabs[1].key end
    activeTab = key
    for index, tab in ipairs(ns.MainTabs) do
        local selected = tab.key == key
        if selected then PanelTemplates_SetTab(frame, index) end
        if selected and not tabFrames[tab.key] then
            local content = CreateFrame("Frame", nil, frame.body)
            content:SetAllPoints()
            tab.Create(content)
            tabFrames[tab.key] = content
        end
        if tabFrames[tab.key] then tabFrames[tab.key]:SetShown(selected) end
    end
    ns.addon.db.char.tab = key
    MainWindow.Refresh({tab = true})
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ns.addon.db.profile.window.point = {point, relativePoint, x, y}
    ns.addon.db.profile.window.width, ns.addon.db.profile.window.height = frame:GetWidth(), frame:GetHeight()
end

local function applyPanelShown()
    local shown = ns.addon.db.profile.window.filters ~= false
    frame.panel:SetShown(shown)
    frame.body:ClearAllPoints()
    frame.body:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", BODY_PAD, -BODY_TOP)
    frame.body:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", shown and -(PANEL_WIDTH + 10) or -BODY_PAD, BODY_PAD)
end

-- labels go first, then the search box and dropdowns shrink
local BAR_STEPS = {
    {search = 170, labels = true, dropdown = 150}, {search = 170, labels = false, dropdown = 150},
    {search = 120, labels = false, dropdown = 150}, {search = 110, labels = false, dropdown = 120},
}
local function layoutBar()
    local bar = frame.bar
    local pawn = frame.pawn:IsShown()
    local right = frame.filtersToggle:GetWidth() + frame.reset:GetWidth() + frame.settings:GetWidth() + 24
    local function need(step)
        local width = 6 + step.search + 14 + step.dropdown
        if step.labels then width = width + frame.sortLabel:GetStringWidth() + 6 end
        if pawn then
            width = width + 14 + step.dropdown + 4 + frame.pawnRefresh:GetWidth()
            if step.labels then width = width + frame.pawnLabel:GetStringWidth() + 6 end
        end
        return width + right
    end
    local available = bar:GetWidth() or 0
    local pick = BAR_STEPS[#BAR_STEPS]
    for _, step in ipairs(BAR_STEPS) do
        if need(step) <= available then
            pick = step
            break
        end
    end
    if frame.barStep == pick and frame.barPawn == pawn then return end
    frame.barStep, frame.barPawn = pick, pawn
    frame.search:SetWidth(pick.search)
    frame.sortLabel:SetShown(pick.labels)
    frame.pawnLabel:SetShown(pick.labels and pawn)
    frame.sort:SetWidth(pick.dropdown)
    frame.pawn:SetWidth(pick.dropdown)
    frame.sort:ClearAllPoints()
    frame.sort:SetPoint("LEFT", pick.labels and frame.sortLabel or frame.search, "RIGHT", pick.labels and 6 or 14, 0)
    frame.pawn:ClearAllPoints()
    frame.pawn:SetPoint("LEFT", pick.labels and frame.pawnLabel or frame.sort, "RIGHT", pick.labels and 6 or 14, 0)
end

local function create()
    local settings = ns.addon.db.profile.window
    local minimum = minHeight()
    frame = CreateFrame("Frame", "ForeverLootFinderFrame", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetTitle(ns.TITLE)
    frame:SetSize(math.max(MIN_WIDTH, settings.width or 1040), math.max(minimum, settings.height or 640))
    if settings.point then
        frame:SetPoint(settings.point[1], UIParent, settings.point[2], settings.point[3], settings.point[4])
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(false)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(MIN_WIDTH, minimum) end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "ForeverLootFinderFrame")

    frame.Inset:ClearAllPoints()
    frame.Inset:SetPoint("TOPLEFT", 4, -INSET_TOP)
    frame.Inset:SetPoint("BOTTOMRIGHT", -6, INSET_BOTTOM)
    local r, g, b = CreateColorFromHexString("ff1f1e21"):GetRGB()
    frame.Bg:SetColorTexture(r, g, b, 0.92)
    frame.Inset.Bg:Hide()

    frame.Tabs = {}
    for index, tab in ipairs(ns.MainTabs) do
        local button = CreateFrame("Button", nil, frame, "PanelTopTabButtonTemplate")
        button:SetID(index)
        button:SetText(tab.label)
        PanelTemplates_TabResize(button, 0)
        button:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            selectTab(tab.key)
        end)
        frame.Tabs[index] = button
    end
    PanelTemplates_SetNumTabs(frame, #frame.Tabs)
    layoutTabs()

    local gear = W.IconButton(frame, 136243, 18, function() ns.Options:Toggle() end)
    gear:SetPoint("TOPRIGHT", -28, -3)
    W.AddTooltip(gear, function(tooltip) tooltip:AddLine(L["Settings"]) end)

    local bar = CreateFrame("Frame", nil, frame.Inset)
    bar:SetPoint("TOPLEFT", 8, -6)
    bar:SetPoint("TOPRIGHT", -8, -6)
    bar:SetHeight(26)
    frame.bar = bar

    local searchChanged = W.Debounce(SEARCH_DELAY, function() ns.FireChange("filters") end)
    frame.search = W.EditBox(bar, 170, function(text)
        ns.Filters().search = text
        searchChanged()
    end)
    frame.search:SetPoint("LEFT", 6, 0)
    -- first Escape empties the box, the second closes the window
    frame.search:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
            ns.Filters().search = ""
            ns.FireChange("filters")
        end
        self:ClearFocus()
    end)
    frame.searchHint = W.Label(frame.search, L["Search"], 11, Style.MUTED)
    frame.searchHint:SetPoint("LEFT", 4, 0)
    frame.search:HookScript("OnEditFocusGained", function() frame.searchHint:Hide() end)
    frame.search:HookScript("OnEditFocusLost", function(self) frame.searchHint:SetShown(self:GetText() == "") end)

    frame.sortLabel = W.Label(bar, L["Sort:"], 11, Style.MUTED)
    frame.sortLabel:SetPoint("LEFT", frame.search, "RIGHT", 14, 0)
    frame.sort = W.Dropdown(bar, 150, sortItems, function(value)
        local stat = value:match("^stat:(.+)$")
        MainWindow.SetSort(stat and "stat" or value, stat)
    end)
    frame.sort:SetPoint("LEFT", frame.sortLabel, "RIGHT", 6, 0)

    frame.pawnLabel = W.Label(bar, L["Scale:"], 11, Style.MUTED)
    frame.pawnLabel:SetPoint("LEFT", frame.sort, "RIGHT", 14, 0)
    frame.pawn = W.Dropdown(bar, 150, pawnItems, function(value)
        ns.addon.db.char.pawnScale = value
        ns.FireChange("pawn")
    end)
    frame.pawn:SetPoint("LEFT", frame.pawnLabel, "RIGHT", 6, 0)
    -- Pawn has no event for edited weights
    frame.pawnRefresh = W.IconButton(bar, "Interface\\Buttons\\UI-RefreshButton", 18, function()
        ns.Pawn.ClearValues()
        ns.Pawn.ClearEquipped()
        ns.FireChange("pawn")
    end)
    frame.pawnRefresh:SetPoint("LEFT", frame.pawn, "RIGHT", 4, 0)
    W.AddTooltip(frame.pawnRefresh, function(tooltip) tooltip:AddLine(L["Reread scores (after editing a Pawn scale)"]) end)

    frame.filtersToggle = W.Button(bar, L["Filters"], nil, 22, function()
        ns.addon.db.profile.window.filters = not (ns.addon.db.profile.window.filters ~= false)
        applyPanelShown()
        MainWindow.Refresh({window = true})
    end)
    frame.filtersToggle:FitWidth()
    frame.filtersToggle:SetPoint("RIGHT", -2, 0)
    frame.reset = W.Button(bar, L["Reset"], nil, 22, function() ns.ResetFilters() end)
    frame.reset:FitWidth()
    frame.reset:SetPoint("RIGHT", frame.filtersToggle, "LEFT", -6, 0)
    -- the title bar gear is easy to miss
    frame.settings = W.Button(bar, L["Settings"], nil, 22, function() ns.Options:Toggle() end)
    frame.settings:FitWidth()
    frame.settings:SetPoint("RIGHT", frame.reset, "LEFT", -6, 0)
    W.AddTooltip(frame.reset, function(tooltip) tooltip:AddLine(L["Reset filters to class defaults"]) end)
    bar:SetScript("OnSizeChanged", function() layoutBar() end)

    frame.summary = W.Label(frame.Inset, "", 11, Style.MUTED)
    frame.summary:SetPoint("TOPLEFT", 14, -36)
    frame.summary:SetPoint("RIGHT", -14, 0)
    frame.summary:SetWordWrap(false)
    frame.summaryHover = CreateFrame("Frame", nil, frame.Inset)
    frame.summaryHover:SetAllPoints(frame.summary)
    frame.summaryHover:EnableMouse(true)
    W.FullTextTooltip(frame.summaryHover, frame.summary)

    frame.body = CreateFrame("Frame", nil, frame.Inset)
    frame.panel = ns.FilterBar.Create(frame.Inset, PANEL_WIDTH)
    frame.panel:SetPoint("TOPRIGHT", frame.Inset, "TOPRIGHT", -BODY_PAD, -BODY_TOP)
    frame.panel:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -BODY_PAD, BODY_PAD)
    frame.panel:SetWidth(PANEL_WIDTH)

    frame.status = W.Label(frame, "", 11, Style.MUTED)
    frame.status:SetPoint("BOTTOMLEFT", 14, 8)

    frame.versionText = W.Label(frame, ns.Options.GetVersionText(), 10)
    frame.versionText:SetPoint("BOTTOMRIGHT", -24, 8)
    frame.versionText:SetJustifyH("RIGHT")

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePosition()
        MainWindow.Refresh({window = true})
    end)

    frame:SetScript("OnHide", function()
        W.CloseMenu()
        GameTooltip:Hide()
        MainWindow.UpdateStatus()
    end)
    frame:SetScript("OnShow", function() MainWindow.OnOpen() end)
    applyPanelShown()
end

function MainWindow.UpdateStatus()
    if not frame then return end
    local pending = ns.Items.Pending()
    local busy = pending > 0 or ns.Pawn.IsBusy()
    local tick = busy and frame:IsShown()
    if tick and not frame.statusTicker then
        frame.statusTicker = C_Timer.NewTicker(1, function() ns.Guard(MainWindow.UpdateStatus) end)
    elseif not tick and frame.statusTicker then
        frame.statusTicker:Cancel()
        frame.statusTicker = nil
    end
    if not frame:IsShown() then return end
    local parts = {}
    if pending > 0 then parts[#parts + 1] = format(L["Loading %s items..."], BreakUpLargeNumbers(pending)) end
    if ns.Pawn.IsBusy() then parts[#parts + 1] = L["Scores..."] end
    if ns.inCombat then parts[#parts + 1] = L["Paused in combat"] end
    if MainWindow.shownCount then parts[#parts + 1] = format(L["%d items"], MainWindow.shownCount) end
    frame.status:SetText(ns.Labels.Join(parts, "   "))
end

-- any other kind only redraws the tab's list
local BAR_KINDS = {
    tab = true,
    window = true,
    filters = true,
    sort = true,
    pawn = true,
    profile = true,
    data = true,
    prices = true,
}
local PANEL_KINDS = {
    tab = true,
    window = true,
    filters = true,
    pawn = true,
    profile = true,
    data = true,
    professions = true,
    level = true,
    prices = true,
}

local function wants(kinds, set)
    if not kinds then return true end
    for kind in pairs(kinds) do if set[kind] then return true end end
    return false
end

local function withMissed(kinds)
    if missedAll then
        missedAll = false
        wipe(missed)
        return nil
    end
    if next(missed) == nil then return kinds end
    local all = {}
    for kind in pairs(missed) do all[kind] = true end
    for kind in pairs(kinds or {}) do all[kind] = true end
    wipe(missed)
    return kinds and all or nil
end

local function remember(kinds)
    if not kinds then
        missedAll = true
        return
    end
    for kind in pairs(kinds) do missed[kind] = true end
end

-- a tab's empty text. when no addon has anything, and none is still reading, it says which addons FLF reads
function MainWindow.EmptyText(text)
    if #ns.GetIndex().records > 0 then return text end
    for _, provider in ipairs({ns.Questie, ns.Crafts, ns.AtlasLootLists, ns.ATT, ns.SkillUp, ns.ForeverDB}) do
        local state = provider.State()
        if state == "waiting" or state == "scanning" then return text end
    end
    return L["Nothing to list yet."] .. "\n\n" .. L["Needs one of these addons:"] .. "\n"
             .. "DungeonJournal\nQuestie, QuestieDB\nAtlasLoot Classic Forever\nALL THE THINGS\nforever-db\nSkillUp Forever"
end

-- kinds nil redraws everything
function MainWindow.Refresh(kinds)
    if not frame or not frame:IsShown() then return remember(kinds) end
    if ns.inCombat then
        remember(kinds)
        ns.FireChange("window")
        MainWindow.UpdateStatus()
        return
    end
    kinds = withMissed(kinds)
    frame.panel:SetShown(ns.addon.db.profile.window.filters ~= false)
    layoutTabs()
    -- the tab in use was just hidden in the settings
    if activeTab and not MainWindow.TabShown(activeTab) then return selectTab(ns.MainTabs[1].key) end

    if wants(kinds, BAR_KINDS) then
        local hasPawn = ns.ActiveScale() ~= nil
        frame.pawn:SetShown(hasPawn)
        frame.pawnRefresh:SetShown(hasPawn)
        if hasPawn then frame.pawn:SetValue(ns.ActiveScale()) end
        local sort = MainWindow.SortSettings()
        frame.sort:SetValue(sort.key == "stat" and ("stat:" .. tostring(sort.stat)) or sort.key)
        if not frame.search:HasFocus() then
            frame.search:SetText(ns.Filters().search or "")
            frame.searchHint:SetShown((ns.Filters().search or "") == "")
        end
        frame.barStep = nil
        layoutBar()
    end

    local tab
    for _, entry in ipairs(ns.MainTabs) do if entry.key == activeTab then tab = entry end end
    local charKey = tab and tab.CharKey and tab.CharKey() or ns.charKey
    local ctx = ns.FilterContext(charKey)
    if wants(kinds, PANEL_KINDS) then
        frame.summary:SetText(ns.FilterBar.Summary(MainWindow.Filters(), ctx))
        if frame.panel:IsShown() then ns.FilterBar.Refresh(ctx) end
    end
    if tab and tab.Refresh then tab.Refresh(ctx, kinds) end
    MainWindow.UpdateStatus()
end

ns.OnChange(function(kinds) MainWindow.Refresh(kinds) end)

function MainWindow.OnOpen()
    -- a scale may have been edited while the window was closed
    if ns.Pawn.CheckScales() then ns.FireChange("pawn") end
    -- the tab asks for what it shows
    MainWindow.Refresh({tab = true})
end

function MainWindow.Toggle()
    if not frame then
        create()
        selectTab(ns.addon.db.char.tab or (ns.MainTabs[1] and ns.MainTabs[1].key))
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function MainWindow.Show() if not frame or not frame:IsShown() then MainWindow.Toggle() end end

function MainWindow.ShowTab(key)
    MainWindow.Show()
    selectTab(key)
end

function MainWindow.ResetPosition()
    if not frame then
        create()
        selectTab(ns.addon.db.char.tab or ns.MainTabs[1].key)
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    ns.addon.db.profile.window.point = nil
end

function MainWindow.IsDirty() return missedAll or next(missed) ~= nil end
