local _, ns = ...
local L = ns.L
local W, Style, Labels = ns.Widgets, ns.Style, ns.Labels

local SlotTab = {}
ns.SlotTab = SlotTab

local RAIL_WIDTH = 170
local SLOT_HEIGHT, RAIL_PAD = 21, 6
local ui = {}

-- the window's minimum height follows this
function SlotTab.RailHeight() return 2 * RAIL_PAD + #ns.Index.SLOTS * SLOT_HEIGHT end

-- shared with the Favourites tab
function SlotTab.CreateList(parent, onSort)
    local list = {}
    list.header = ns.Row.CreateHeader(parent, onSort)
    list.box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    list.bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, data) return data.header and ns.Row.HEADER_HEIGHT or ns.Row.HEIGHT end)
    view:SetElementInitializer("Button", function(button, data) ns.Row.Bind(button, data, list.opts) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(list.box, list.bar, view)
    list.empty = W.Label(parent, "", 12, Style.MUTED)
    list.empty:SetPoint("CENTER", list.box, "CENTER")
    list.empty:SetJustifyH("CENTER")

    function list:Place(top, left, right, bottom)
        self.header:ClearAllPoints()
        self.header:SetPoint("TOPLEFT", left, top)
        self.header:SetPoint("TOPRIGHT", right - 16, top)
        self.box:ClearAllPoints()
        self.box:SetPoint("TOPLEFT", left, top - 22)
        self.box:SetPoint("BOTTOMRIGHT", right - 16, bottom)
        self.bar:ClearAllPoints()
        self.bar:SetPoint("TOPLEFT", self.box, "TOPRIGHT", 4, 0)
        self.bar:SetPoint("BOTTOMLEFT", self.box, "BOTTOMRIGHT", 4, 0)
    end

    function list:SetRows(rows, opts, emptyText, toTop)
        opts.width = self.box:GetWidth()
        opts.nameNeed = ns.Row.NameNeed(rows)
        self.opts = opts
        ns.Row.LayoutHeader(self.header, opts, ns.MainWindow.SortSettings())
        local retain = not toTop and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
        self.box:SetDataProvider(CreateDataProvider(rows), retain)
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#rows == 0)
    end
    return list
end

local function selectSlot(slot)
    local filters = ns.Filters()
    if filters.slot == slot then return end
    filters.slot = slot
    ns.Items.Request(ns.MainWindow.RecordsOfSlot(slot), true)
    ns.FireChange("filters")
end

local function create(parent)
    ui.rail = W.Panel(parent)
    ui.rail:SetPoint("TOPLEFT", 0, 0)
    ui.rail:SetPoint("BOTTOMLEFT", 0, 0)
    ui.rail:SetWidth(RAIL_WIDTH)
    ui.slots = {}
    for i, slot in ipairs(ns.Index.SLOTS) do
        local button = CreateFrame("Button", nil, ui.rail)
        button:SetHeight(SLOT_HEIGHT)
        button:SetPoint("TOPLEFT", RAIL_PAD, -RAIL_PAD - (i - 1) * SLOT_HEIGHT)
        button:SetPoint("RIGHT", -RAIL_PAD, 0)
        W.StyleRow(button)
        button.label = W.Label(button, Labels.Slot(slot), 12)
        button.label:SetPoint("LEFT", 6, 0)
        button.label:SetPoint("RIGHT", -34, 0)
        button.label:SetWordWrap(false)
        button.count = W.Label(button, "", 11, Style.MUTED)
        button.count:SetPoint("RIGHT", -4, 0)
        button.count:SetJustifyH("RIGHT")
        button:SetScript("OnClick", function() selectSlot(slot) end)
        W.FullTextTooltip(button, button.label)
        button:HookScript("OnEnter", function(self)
            if not (ui.approximate and ui.approximate[slot] and slot ~= ns.Filters().slot) then return end
            if GameTooltip:GetOwner() ~= self then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
            GameTooltip:AddLine(L["~ Some of these haven't loaded yet, or Pawn hasn't scored them. Open the slot to load them."],
                                1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
        ui.slots[slot] = button
    end
    ui.list = SlotTab.CreateList(parent, function(key) ns.MainWindow.SetSort(key) end)
    ui.list:Place(0, RAIL_WIDTH + 8, 0, 0)
end

local function refresh(ctx, kinds)
    local index = ns.GetIndex()
    if not index then return end
    local filters = ns.Filters()
    ctx = ctx or ns.FilterContext()
    -- only the slot shown is asked for; QuestieDB and AtlasLoot may add items after it was
    if (kinds and (kinds.tab or kinds.data)) or ui.requestedSlot ~= filters.slot then
        ui.requestedSlot = filters.slot
        ns.Items.Request(ns.MainWindow.RecordsOfSlot(filters.slot), true)
    end
    local rows, counts, approximate = ns.Filter.RunWithCounts(index.records, ns.Items.Info, filters, ctx, filters.slot)
    ui.approximate = approximate
    for slot, button in pairs(ui.slots) do
        local count = counts[slot] or 0
        -- items not loaded or scored yet are a guess till the slot is opened
        local about = approximate and approximate[slot] and slot ~= filters.slot and count > 0
        button.count:SetText((about and "~" or "") .. count)
        button:SetRowSelected(slot == filters.slot)
        button.label:SetTextColor(unpack((counts[slot] or 0) > 0 and Style.TEXT or Style.MUTED))
    end
    rows = ns.MainWindow.PrepareRows(rows, ctx)
    ns.MainWindow.shownCount = #rows
    local toTop = (kinds and kinds.tab) or ui.shownSlot ~= filters.slot
    ui.shownSlot = filters.slot
    ui.list:SetRows(rows, ns.MainWindow.RowOptions(nil, filters.slot, ctx),
                     ns.MainWindow.EmptyText(L["No items match the filters."]), toTop)
end

table.insert(ns.MainTabs, {key = "slot", label = L["By slot"], Create = create, Refresh = refresh})
