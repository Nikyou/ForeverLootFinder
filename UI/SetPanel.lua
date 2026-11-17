local _, ns = ...
local L = ns.L
local W, Style, Labels = ns.Widgets, ns.Style, ns.Labels

local SetPanel = {}
ns.SetPanel = SetPanel

local WIDTH = 520
local frame, current

local function create()
    frame = CreateFrame("Frame", "ForeverLootFinderSet", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetSize(WIDTH, 420)
    frame:SetPoint("CENTER", 200, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ForeverLootFinderSet")
    frame.Inset:ClearAllPoints()
    frame.Inset:SetPoint("TOPLEFT", 4, -26)
    frame.Inset:SetPoint("BOTTOMRIGHT", -6, 36)
    frame.summary = W.Label(frame.Inset, "", 11, Style.MUTED)
    frame.summary:SetPoint("TOPLEFT", 10, -8)
    frame.summary:SetPoint("RIGHT", -10, 0)
    frame.scroll = W.ScrollArea(frame.Inset)
    frame.scroll:SetPoint("TOPLEFT", 8, -28)
    frame.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    frame.rows = {}
    frame.bonus = W.Label(frame.scroll.content, "", 11)
    frame.bonus:SetJustifyV("TOP")
    frame.addAll = W.Button(frame, L["Favourite all pieces"], nil, 22, function()
        if not current then return end
        local tier = ns.addon.db.profile.favourites.defaultTier
        for _, record in ipairs(current.pieces) do
            if record.id and record.id > 0 and not ns.Favourites.Get(record.id) then ns.Favourites.Set(record.id, tier) end
        end
    end)
    frame.addAll:FitWidth()
    frame.addAll:SetPoint("BOTTOMLEFT", 10, 8)
    frame:Hide()
end

local function pieceRow(index)
    local row = frame.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, frame.scroll.content)
    row:SetHeight(34)
    W.StyleRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = W.Label(row, "")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.name:SetPoint("RIGHT", -4, 0)
    row.name:SetWordWrap(false)
    row.sub = W.Label(row, "", 11, Style.MUTED)
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.sub:SetPoint("RIGHT", -4, 0)
    row.sub:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.opts = {}
    row:SetScript("OnEnter", function(self) ns.Guard(ns.Row.ShowTooltip, self) end)
    row:SetScript("OnLeave", function() ns.Row.HideTooltip() end)
    row:SetScript("OnClick", function(self, mouse) ns.Guard(ns.Row.OnClick, self, mouse) end)
    frame.rows[index] = row
    return row
end

function SetPanel.Refresh()
    if not frame or not current or not frame:IsShown() then return end
    local index = ns.GetIndex()
    frame:SetTitle(ns.Sets.Name(current))
    frame.summary:SetText(ns.Sets.Summary(current, L) .. "  " .. L["Pawn doesn't count set bonuses."])
    for _, row in ipairs(frame.rows) do row:Hide() end
    local y = 0
    local ctx = ns.FilterContext()
    local pieces = {}
    for _, record in ipairs(current.pieces) do
        local info = ns.Items.Info(record)
        if not ns.Filter.ForOtherClass(record, info, ctx) and not ns.Filter.ForOtherRace(info, ctx) then
            pieces[#pieces + 1] = record
        end
    end
    table.sort(pieces, function(a, b)
        local sa, sb = ns.Items.Info(a).slot or "", ns.Items.Info(b).slot or ""
        if sa ~= sb then return sa < sb end
        return (a.name or "") < (b.name or "")
    end)
    local showPrice = ns.Auctionator.Active() and ns.Row.ColumnChosen(ns.addon.db.profile.columns, "price")
    for i, record in ipairs(pieces) do
        local info = ns.Items.Info(record)
        local row = pieceRow(i)
        local doable = ns.DoableSources(record.sources)
        row.data = {record = record, info = info, sources = doable}
        row.opts.charKey = ns.charKey
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT")
        row.icon:SetTexture(info.icon or 134400)
        local owned = record.id and ns.Owned.Where(record.id)
        local tier = record.id and ns.Favourites.Get(record.id)
        local name = Labels.QualityHex(info.quality) .. (info.name or record.name or "?") .. "|r"
        if tier then name = ns.Tooltip.STAR .. " " .. name end
        if owned then name = name .. "  |cff80ff80" .. L["Owned"] .. "|r" end
        -- only while the Price column is picked
        if showPrice then
            local price = ns.Auctionator.ForRecord(record, info)
            if price then name = name .. "  " .. ns.Auctionator.Text(price) end
        end
        row.name:SetText(name)
        local sources = {}
        for _, source in ipairs(ns.Tooltip.MergeQuests(doable)) do
            sources[#sources + 1] = ns.Tooltip.SourceText(source, index and index.dungeonByKey)
        end
        row.sub:SetText(Labels.Slot(info.slot) .. " — " .. table.concat(sources, "; "))
        row:Show()
        ns.Row.RefreshTooltip(row)
        y = y + 36
    end
    local bonuses = current.bonuses
    if bonuses and #bonuses > 0 then
        frame.bonus:ClearAllPoints()
        frame.bonus:SetPoint("TOPLEFT", 4, -(y + 8))
        frame.bonus:SetWidth(WIDTH - 60)
        frame.bonus:SetText(table.concat(bonuses, "\n"))
        frame.bonus:Show()
        y = y + 16 + frame.bonus:GetStringHeight()
    else
        frame.bonus:Hide()
    end
    frame.scroll:SetContentHeight(y)
end

function SetPanel.Show(record)
    local set = ns.Sets.For(record)
    if not set then return end
    if not frame then create() end
    current = set
    frame:Show()
    frame:Raise()
    SetPanel.Refresh()
end

function SetPanel.Hide() if frame then frame:Hide() end end

ns.OnChange(function(kinds)
    if kinds.favourites or kinds.items or kinds.owned or kinds.data or kinds.prices or kinds.columns then SetPanel.Refresh() end
end)
