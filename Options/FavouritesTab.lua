local _, ns = ...
local L = ns.L
local W, Options = ns.Widgets, ns.Options

local controls = {}
local selected
local bisList

local function bisLists()
    local data = ns.addon.db.global.characters[ns.charKey]
    return ns.AtlasLootBiS.Lists(data and data.class)
end

local function bisItems()
    local items = {}
    for _, list in ipairs(bisLists()) do items[#items + 1] = {value = list.key, text = ns.AtlasLootBiS.Label(list)} end
    return items
end

local function refreshBiS()
    local lists = bisLists()
    local found
    for _, list in ipairs(lists) do if list.key == bisList then found = list end end
    found = found or lists[1]
    bisList = found and found.key or nil
    controls.bis:SetValue(bisList, true)
    controls.bis:SetEnabled(found ~= nil)
    controls.bisImport:SetEnabled(found ~= nil)
    if found then
        controls.bisImport.why = nil
    elseif ns.AtlasLootBiS.Installed() then
        controls.bisImport.why = {reason = L["It has no lists for your class yet."]}
    else
        controls.bisImport.why = {needs = {"AtlasLoot Classic"}}
    end
end

local function F() return ns.Favourites end

local function tierItems()
    local items = {}
    for _, tier in ipairs(F().TIERS) do items[#items + 1] = {value = tier.key, text = tier.label} end
    return items
end

local function characterItems()
    local items = {}
    for _, entry in ipairs(F().Characters()) do
        local count = 0
        for _ in pairs(F().List(entry.key)) do count = count + 1 end
        local data = entry.data
        local class = data.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class) or "?"
        items[#items + 1] = {
            value = entry.key,
            text = format(L["%s (%s %d, %d favourites)"], F().CharacterLabel(entry.key), class, data.level or 0, count),
        }
    end
    return items
end

local function refresh()
    controls.defaultTier:SetValue(ns.addon.db.profile.favourites.defaultTier)
    if not selected or not ns.addon.db.global.characters[selected] then selected = ns.charKey end
    controls.character:SetValue(selected, true)
    controls.delete:SetEnabled(selected ~= ns.charKey)
    local hasFDJ = F().HasFDJList()
    controls.fdj:SetShown(hasFDJ)
    controls.fdjHelp:SetShown(hasFDJ)
    refreshBiS()
end

local function create(parent)
    local left = W.Column(parent, 0, Options.COLUMN)
    left.title(L["Tiers"])
    local lines = {}
    for _, tier in ipairs(F().TIERS) do
        lines[#lines + 1] = F().TierColor(tier.key) .. ns.Tooltip.STAR .. " " .. tier.label .. "|r"
    end
    left.label(table.concat(lines, "    "))
    left.label(L["Click adds items with this tier:"])
    controls.defaultTier = W.Dropdown(parent, 220, tierItems,
                                      function(value) ns.addon.db.profile.favourites.defaultTier = value end)
    left.place(controls.defaultTier, 34)

    left.title(L["From the Dungeon Journal"])
    controls.fdjHelp = left.help(L["Copies this character's Dungeon Journal favourites once, as \"Nice to have\"."], 0)
    controls.fdj = W.Button(parent, L["Import FDJ favourites"], nil, 22, function() Options:ImportFDJ() end)
    controls.fdj:FitWidth()
    left.place(controls.fdj, 30)

    left.title(L["AtlasLoot BiS lists"])
    left.help(L["Adds a list's items as \"BiS\". Nothing is imported until you click."], 0)
    controls.bis = W.Dropdown(parent, Options.COLUMN - 20, bisItems, function(value) bisList = value end)
    left.place(controls.bis, 34)
    controls.bisImport = W.Button(parent, L["Import BiS list"], nil, 22, function()
        for _, list in ipairs(bisLists()) do if list.key == bisList then return Options:ImportBiS(list) end end
    end)
    controls.bisImport:FitWidth()
    W.WhyTooltip(controls.bisImport, L["AtlasLoot BiS lists"])
    left.place(controls.bisImport, 30)

    local right = W.Column(parent, Options.RIGHT, Options.COLUMN)
    right.title(L["Characters"])
    controls.character = W.Dropdown(parent, Options.COLUMN - 20, characterItems, function(value)
        selected = value
        refresh()
    end)
    right.place(controls.character, 34)
    controls.delete = W.Button(parent, L["Delete character"], nil, 22, function()
        Options:Confirm(format(L["Delete %s and their favourites?"], selected), {
            {
                label = L["Delete"],
                onClick = function()
                    F().DeleteCharacter(selected)
                    selected = ns.charKey
                    refresh()
                end,
            }, {label = L["Cancel"]},
        })
    end)
    controls.delete:FitWidth()
    right.place(controls.delete, 34)
    right.help(L["Characters are added on login. The current one can't be deleted."], 0)

    right.title(L["Share"])
    right.help(L["The selected character's favourites and tiers, as a string."], 0)
    local export = W.Button(parent, L["Export favourites"], nil, 22, function() Options:ShowFavouritesExport(selected) end)
    export:FitWidth()
    right.place(export, 0)
    local import = W.Button(parent, L["Import favourites"], nil, 22, function() Options:ShowFavouritesImport(selected) end)
    import:FitWidth()
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
end

table.insert(ns.OptionsTabs, {key = "favourites", label = L["Favourites"], Create = create, Refresh = refresh})
