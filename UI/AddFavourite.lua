-- "Add item" on the Favourites tab: a link, an ID or part of a name, even for items no addon lists
local _, ns = ...
local L = ns.L

local AddFavourite = {}
ns.AddFavourite = AddFavourite

local MAX_RESULTS = 8
local MIN_CHARS = 3
local ROW = 20
local WIDTH = 340

local frame
local tier

-- pure: index names first (in the client's language), then the other lists in order (QuestieDB's, English only).
-- each list: id -> name. a name that starts with the text beats one that only contains it, and anything the addon
-- hides on purpose (hidden(id) is true) goes after the rest
function AddFavourite.Search(text, records, nameOf, lists, limit, hidden)
    limit = limit or MAX_RESULTS
    local id = tonumber(text)
    if id then return {{id = id}} end
    local needle = ns.Util.Lower(strtrim(text or ""))
    if #needle < MIN_CHARS then return {} end
    local groups, seen = {{}, {}, {}, {}}, {}
    local function consider(itemID, name)
        if seen[itemID] or type(name) ~= "string" then return end
        local at = ns.Util.Lower(name):find(needle, 1, true)
        if not at then return end
        seen[itemID] = true
        local group = (at == 1 and 1 or 2) + (hidden and hidden(itemID) and 2 or 0)
        local list = groups[group]
        list[#list + 1] = {id = itemID, name = name}
    end
    for _, record in ipairs(records or {}) do
        if record.id and record.id > 0 then consider(record.id, nameOf(record)) end
    end
    for _, names in ipairs(lists or {}) do
        for itemID, name in pairs(names) do consider(itemID, name) end
    end
    local function byName(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end
    local out = {}
    for _, list in ipairs(groups) do
        table.sort(list, byName)
        for _, entry in ipairs(list) do
            if #out >= limit then return out end
            out[#out + 1] = entry
        end
    end
    return out
end

-- nil: listed and fine. else a short reason, and whether it's hidden on purpose
local REASONS = {sod = L["SoD only"], implausible = L["unlikely drop"], hidden = L["removed quest"]}
local function stateOf(id)
    local index = ns.GetIndex()
    local record = index and index.byKey[id]
    if record then
        if ns.Items.Info(record).missing then return L["not on this server"], true end
        return nil
    end
    local why = ns.Questie.SkipReason(id)
    if why then return REASONS[why] or why, true end
    return L["no source"], false
end
AddFavourite.StateOf = stateOf

local function search(text)
    local id = ns.Util.ItemIDFromLink(text)
    if id then return {{id = id}} end
    local index = ns.GetIndex()
    local found = AddFavourite.Search(text, index and index.records,
                                      function(record) return ns.Items.Info(record).name or record.name end,
                                      {ns.Questie.ItemNames()}, nil,
                                      function(id) return select(2, stateOf(id)) == true end)
    -- the game finds an exact name only if it has seen the item this session
    if #found == 0 and #strtrim(text or "") >= MIN_CHARS then
        local _, link = ns.Util.SafeCall(C_Item.GetItemInfo, strtrim(text))
        id = ns.Util.ItemIDFromLink(link)
        if id then found = {{id = id}} end
    end
    return found
end

local function setStatus(text, color)
    frame.status:SetText(text or "")
    frame.status:SetTextColor(unpack(color or ns.Style.MUTED))
end

local function add(id)
    if not ns.Favourites.CanAdd(id) then
        setStatus(L["That item can't be worn."], ns.Style.WARN)
        return
    end
    ns.Favourites.Set(id, tier)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or ("#" .. id)
    local index = ns.GetIndex()
    local text = format(L["%s added (%s)."], name, ns.Favourites.TierLabel(tier))
    if not (index and index.byKey[id]) then text = text .. " " .. L["No known source: it shows only here."] end
    setStatus(text, ns.Style.GOOD)
    frame.edit:SetText("")
    -- keeps the message through the redraw
    frame.status.forText = ""
    AddFavourite.Update()
end

local function resultButton(n)
    local b = frame.results[n]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:SetSize(WIDTH - 24, ROW)
    b:SetPoint("TOPLEFT", 12, -84 - (n - 1) * ROW)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ROW - 2, ROW - 2)
    b.icon:SetPoint("LEFT")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT")
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetHighlightTexture(ns.Style.HIGHLIGHT_TEXTURE, "ADD")
    b:SetScript("OnClick", function(self) add(self.id) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        if self.filtered then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format(L["Hidden by LootFinder: %s."], self.note), 1, 0.5, 0.25, true)
            GameTooltip:AddLine(L["You can still add it."], 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.results[n] = b
    return b
end

function AddFavourite.Update()
    if not (frame and frame:IsShown()) then return end
    local found = search(frame.edit:GetText())
    frame.found = found
    for n = 1, MAX_RESULTS do
        local entry = found[n]
        local b = frame.results[n]
        if entry then
            b = resultButton(n)
            local name = entry.name
            local quality
            if C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(entry.id) or name end
            if C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(entry.id) end
            local note, filtered = stateOf(entry.id)
            local text = (filtered and "|cff9d9d9d" or ns.Labels.QualityHex(quality)) .. (name or ("#" .. entry.id)) .. "|r"
            if note then text = text .. " |cff9d9d9d(" .. note .. ")|r" end
            b.id, b.note, b.filtered = entry.id, note, filtered
            b.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id) or 134400)
            b.icon:SetDesaturated(filtered == true)
            b:SetAlpha(filtered and 0.6 or 1)
            b.text:SetText(text)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    local text = strtrim(frame.edit:GetText() or "")
    if #found == 0 and text ~= "" and not tonumber(text) and #text >= MIN_CHARS then
        setStatus(L["Nothing found. Try a link (Shift-click the item) or its ID."])
    elseif frame.status.forText ~= text then
        setStatus(nil)
    end
    frame.status.forText = text
    frame:SetHeight(84 + math.max(1, math.min(#found, MAX_RESULTS)) * ROW + 36)
end

local function tierItems()
    local items = {}
    for _, entry in ipairs(ns.Favourites.TIERS) do items[#items + 1] = {value = entry.key, text = entry.label} end
    return items
end

local function create()
    local W = ns.Widgets
    frame = CreateFrame("Frame", "ForeverLootFinderAddFavourite", UIParent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6)
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(WIDTH, 160)
    frame:Hide()
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    tinsert(UISpecialFrames, "ForeverLootFinderAddFavourite")

    local title = W.Label(frame, L["Add a favourite"], 13, ns.Style.ACCENT)
    title:SetPoint("TOPLEFT", 12, -10)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    frame.edit = W.EditBox(frame, WIDTH - 140, W.Debounce(0.2, AddFavourite.Update))
    frame.edit:SetPoint("TOPLEFT", 18, -32)
    frame.edit:SetScript("OnEnterPressed", function()
        local first = frame.found and frame.found[1]
        if first then add(first.id) end
    end)
    frame.edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    tier = ns.addon.db.profile.favourites.defaultTier
    frame.tier = W.Dropdown(frame, 100, tierItems, function(value) tier = value end)
    frame.tier:SetPoint("LEFT", frame.edit, "RIGHT", 8, 0)
    frame.hint = W.Label(frame, L["Item name, ID, or Shift-click an item."], 10, ns.Style.MUTED)
    frame.hint:SetPoint("TOPLEFT", 14, -58)
    frame.status = W.Label(frame, "", 11, ns.Style.MUTED)
    frame.status:SetPoint("BOTTOMLEFT", 12, 12)
    frame.status:SetPoint("BOTTOMRIGHT", -12, 12)
    frame.status:SetJustifyH("LEFT")
    frame.results = {}
    frame:SetScript("OnShow", function()
        frame.tier:SetValue(tier, true)
        frame.edit:SetFocus()
        AddFavourite.Update()
    end)
    frame:SetScript("OnHide", function() frame.edit:ClearFocus() end)

    -- Shift-click on an item puts its link here, like it would into chat
    local function insert(link)
        if frame:IsShown() and frame.edit:HasFocus() and type(link) == "string" and link:find("|Hitem:") then
            frame.edit:SetText(link)
            AddFavourite.Update()
            return true
        end
    end
    local util = rawget(_G, "ChatFrameUtil")
    if type(util) == "table" and util.InsertLink then hooksecurefunc(util, "InsertLink", insert) end
    if rawget(_G, "ChatEdit_InsertLink") then hooksecurefunc("ChatEdit_InsertLink", insert) end
end

function AddFavourite.Toggle(anchor)
    if not frame then create() end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
        frame:SetPoint("CENTER")
    end
    setStatus(nil)
    frame:Show()
end
