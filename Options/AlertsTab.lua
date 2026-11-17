local _, ns = ...
local L = ns.L
local W, Options = ns.Widgets, ns.Options

local controls = {}

local function profile() return ns.addon.db.profile end

local function modes()
    return {{value = "window", text = L["Small window"]}, {value = "chat", text = L["Chat"]}, {value = "off", text = L["Off"]}}
end

local function create(parent)
    local left = W.Column(parent, 0, Options.COLUMN)
    left.title(L["Dungeon reminder"])
    left.help(L["On entering a dungeon: your favourites there and their bosses."], 0)
    controls.reminder = W.Dropdown(parent, 220, modes, function(value) profile().reminder.mode = value end)
    left.place(controls.reminder, 34)

    local right = W.Column(parent, Options.RIGHT, Options.COLUMN)
    right.title(L["Drop alert"])
    right.help(L["When a favourite drops: loot window, group roll or chat."], 0)
    controls.toast = right.check(L["On-screen notice"], function(value) profile().dropAlert.toast = value end)
    controls.chat = right.check(L["Chat line"], function(value) profile().dropAlert.chat = value end)
    controls.sound = right.check(L["Sound"], function(value) profile().dropAlert.sound = value end)
end

local function refresh()
    local p = profile()
    controls.reminder:SetValue(p.reminder.mode)
    controls.toast:SetChecked(p.dropAlert.toast)
    controls.chat:SetChecked(p.dropAlert.chat)
    controls.sound:SetChecked(p.dropAlert.sound)
end

table.insert(ns.OptionsTabs, {key = "alerts", label = L["Alerts"], Create = create, Refresh = refresh})
