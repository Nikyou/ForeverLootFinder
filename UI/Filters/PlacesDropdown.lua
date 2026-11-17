-- filters.dungeons and filters.raids, nil is every place
local _, ns = ...
local L = ns.L

local PlacesDropdown = {}
ns.PlacesDropdown = PlacesDropdown

local KINDS = {
    dungeons = {raid = false, all = L["All dungeons"], count = L["%d dungeons"]},
    raids = {raid = true, all = L["All raids"], count = L["%d raids"]},
}

local function filters() return ns.Filters() end
local function changed() ns.FireChange("filters") end

function PlacesDropdown.Places(field)
    local index, list = ns.GetIndex(), {}
    local raid = KINDS[field].raid
    for _, dungeon in ipairs(index and index.dungeons or {}) do
        if (dungeon.raid == true) == raid then list[#list + 1] = dungeon end
    end
    return list, index
end

-- nil for all
function PlacesDropdown.Count(set)
    if set == nil then return nil end
    local count = 0
    for _ in pairs(set) do count = count + 1 end
    return count
end

function PlacesDropdown.Text(field)
    local count = PlacesDropdown.Count(filters()[field])
    if count == nil then return KINDS[field].all end
    return count == 0 and L["None"] or format(KINDS[field].count, count)
end

-- the stock button text joins every ticked entry, 35 names
function PlacesDropdown.Create(parent, width, field)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    if dropdown.SetSelectionText then dropdown:SetSelectionText(function() return PlacesDropdown.Text(field) end) end
    local function isOpen() return dropdown.IsMenuOpen and dropdown:IsMenuOpen() end
    function dropdown:ShowSummary()
        local text = PlacesDropdown.Text(field)
        if self.summary == text then return end
        if self.OverrideText then
            self:OverrideText(text)
        elseif isOpen() then
            -- rebuilding an open menu redraws it under the mouse, wait till it closes
            self.pending = true
            return
        else
            self:SetDefaultText(text)
            self:GenerateMenu()
            if self.Text and not self.SetSelectionText then self.Text:SetText(text) end
        end
        self.pending = nil
        self.summary = text
    end
    if dropdown.RegisterCallback and DropdownButtonMixin and DropdownButtonMixin.Event
        and DropdownButtonMixin.Event.OnMenuClose then
        dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, function()
            if dropdown.pending then C_Timer.After(0, function() ns.Guard(dropdown.ShowSummary, dropdown) end) end
        end, dropdown)
    end

    local function isSelected(key)
        local set = filters()[field]
        return set == nil or set[key] == true
    end
    local function toggle(key)
        local places = PlacesDropdown.Places(field)
        local set = filters()[field]
        if set == nil then
            set = {}
            for _, dungeon in ipairs(places) do set[dungeon.key] = true end
        end
        set[key] = not set[key] or nil
        local all = true
        for _, dungeon in ipairs(places) do if not set[dungeon.key] then all = false end end
        filters()[field] = (not all) and set or nil
        changed()
    end
    dropdown:SetupMenu(function(_, root)
        local places, index = PlacesDropdown.Places(field)
        root:CreateButton(KINDS[field].all, function()
            filters()[field] = nil
            changed()
        end)
        root:CreateButton(L["None"], function()
            filters()[field] = {}
            changed()
        end)
        root:CreateDivider()
        for _, dungeon in ipairs(places) do
            root:CreateCheckbox(ns.Tooltip.DungeonLabel(dungeon.key, index.dungeonByKey), isSelected, toggle, dungeon.key)
        end
        if #places > 20 then root:SetScrollMode(400) end
    end)
    return dropdown
end
