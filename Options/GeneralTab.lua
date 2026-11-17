-- card grouping lives on each card tab, not here
local _, ns = ...
local L = ns.L
local W, Options = ns.Widgets, ns.Options

local controls = {}

local function profile() return ns.addon.db.profile end
local function changed() ns.FireChange("profile") end

local function hiddenItems()
    local items = {}
    local index = ns.GetIndex()
    for key in pairs(ns.addon.db.char.hidden) do
        local record = index and index.byKey[key]
        local name = record and (ns.Items.Info(record).name or record.name) or tostring(key)
        items[#items + 1] = {value = key, text = name}
    end
    table.sort(items, function(a, b) return a.text < b.text end)
    return items
end

-- greyed out but still showing the choice
local function setUsable(box, usable, why)
    box:SetEnabled(usable and true or false)
    box.why = (not usable) and why or nil
    box.Text:SetTextColor(unpack(usable and ns.Style.TEXT or ns.Style.MUTED))
end

local function create(parent)
    local left = W.Column(parent, 0, Options.COLUMN)
    left.title(L["Window"])
    controls.minimap = left.check(L["Minimap button"], function(value) ns.addon:SetMinimapButtonShown(value) end)
    controls.stars = left.check(L["Favourite stars"], function(value)
        profile().stars = value
        changed()
    end)

    left.title(L["Item tooltips"])
    controls.source = left.check(L["Source on all item tooltips"], function(value)
        profile().tooltip.allItems = value
        changed()
    end)
    left.help(L["Loot Finder's windows always show it."])
    controls.favourite = left.check(L["Favourite tier"], function(value)
        profile().tooltip.favourite = value
        setUsable(controls.otherChars, value)
        changed()
    end)
    controls.otherChars = left.check(L["Other characters' favourites"], function(value)
        profile().tooltip.otherChars = value
        changed()
    end)
    controls.auction = left.check(L["Auction price (Auctionator)"], function(value)
        profile().tooltip.auction = value
        changed()
    end)
    W.WhyTooltip(controls.auction, L["Auction price (Auctionator)"])
    left.help(L["For when Auctionator's own price lines are off."])

    left.title(L["List"])
    controls.unknown = left.check(L["Show items still loading (greyed)"], function(value)
        profile().showUnknown = value
        changed()
    end)
    controls.missing = left.check(L["Show items not on this server"], function(value)
        profile().showMissing = value
        changed()
    end)
    left.help(L["Greyed. Missing favourites always show."])
    controls.random = left.check(L["Random-bonus items pass stat filters"], function(value)
        profile().randomPass = value
        changed()
    end)
    left.help(L["Their base stats differ from the drop."])
    controls.hideEmpty = left.check(L["Dungeons, Raids: hide empty places"], function(value)
        profile().dungeonTab.hideEmpty = value
        changed()
    end)
    controls.cardChance = left.check(L["Dungeons, Raids: drop chance on icons"], function(value)
        profile().cardChance = value
        changed()
    end)
    controls.learnedFirst = left.check(L["Professions: mine first"], function(value)
        profile().craftTab.learnedFirst = value
        changed()
    end)

    -- same as right-clicking the list header
    left.title(L["Columns"])
    controls.columns = {}
    for _, column in ipairs(ns.Row.CHOOSABLE) do
        local box = left.check(column.menu, function(value) ns.Row.SetColumn(column.key, value) end)
        W.WhyTooltip(box, column.menu)
        controls.columns[column.key] = box
    end
    left.help(L["Empty columns stay hidden. Also: right-click the list header."])

    local right = W.Column(parent, Options.RIGHT, Options.COLUMN)
    right.title(L["Badges on rows"])
    controls.badges = {}
    for _, badge in ipairs(ns.Labels.BADGES) do
        controls.badges[badge.key] = right.check(badge.label, function(value)
            profile().badges[badge.key] = value
            changed()
        end)
    end

    right.title(L["Hidden items"])
    right.help(L["Hidden with \"Hide this item\", this character only."], 0)
    controls.hidden = W.Dropdown(parent, 260, hiddenItems, function(key)
        ns.addon.db.char.hidden[key] = nil
        controls.hidden:SetValue(nil)
        ns.FireChange("filters")
    end, L["Show one again"])
    right.place(controls.hidden, 30)
    local all = W.Button(parent, L["Show all again"], nil, 22, function()
        wipe(ns.addon.db.char.hidden)
        controls.hidden:SetValue(nil)
        ns.FireChange("filters")
    end)
    all:FitWidth()
    right.place(all, 30)
end

local function refresh()
    local p = profile()
    controls.minimap:SetChecked(not p.minimap.hide)
    controls.stars:SetChecked(p.stars)
    controls.source:SetChecked(p.tooltip.allItems == true)
    controls.favourite:SetChecked(p.tooltip.favourite)
    controls.otherChars:SetChecked(p.tooltip.otherChars == true)
    setUsable(controls.otherChars, p.tooltip.favourite ~= false)
    controls.unknown:SetChecked(p.showUnknown)
    controls.missing:SetChecked(p.showMissing == true)
    controls.random:SetChecked(p.randomPass)
    controls.hideEmpty:SetChecked(p.dungeonTab.hideEmpty)
    controls.cardChance:SetChecked(p.cardChance ~= false)
    controls.learnedFirst:SetChecked(p.craftTab.learnedFirst ~= false)
    setUsable(controls.auction, ns.Auctionator.Active(), {needs = {"Auctionator"},
              reason = ns.Auctionator.Installed() and L["Off in Settings, Addons tab."] or nil})
    controls.auction:SetChecked(p.tooltip.auction == true)
    for key, box in pairs(controls.columns) do
        box:SetChecked(ns.Row.ColumnChosen(p.columns, key))
        setUsable(box, ns.Row.ColumnStatus(key))
    end
    for key, box in pairs(controls.badges) do box:SetChecked(p.badges[key]) end
    controls.hidden:SetValue(nil)
end

table.insert(ns.OptionsTabs, {key = "general", label = L["General"], Create = create, Refresh = refresh})
