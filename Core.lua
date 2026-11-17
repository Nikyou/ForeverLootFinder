-- the index and the filter context live in Core/State.lua
local ADDON_NAME, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("ForeverLootFinder")

local addon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0")
ns.addon = addon
ns.L = L
ns.TITLE = "Forever Loot Finder"

local ICON = 134344
local isSecret = ns.Util.IsSecret

local defaults = {
    profile = {
        minimap = {hide = false, showInCompartment = true},
        window = {width = 1040, height = 640},
        showUnknown = true, -- not loaded yet
        showMissing = false, -- the server doesn't know them. favourites show anyway
        randomPass = true, -- random-bonus items pass stat filters
        badges = {
            rare = true,
            trash = true,
            shared = true,
            quest = true,
            craft = true,
            probable = true,
            random = true,
            faction = true,
            notInGame = true,
            owned = true,
            boe = true,
            unique = true,
            set = true,
            vendor = true,
            creature = true,
        },
        stars = true,
        -- allItems: every tooltip, not only FLF's windows. auction off by default, Auctionator has its own line
        tooltip = {allItems = false, favourite = true, otherChars = false, auction = false},
        dungeonTab = {hideEmpty = false, byBoss = false},
        cardChance = true,
        favourites = {defaultTier = "MUST"},
        reminder = {mode = "window"}, -- off, chat or window
        dropAlert = {toast = true, chat = true, sound = true},
        fdj = true,
        syndicator = true,
        questie = true,
        questieKinds = {quests = true, vendors = true, drops = true},
        waypoints = "auto", -- auto (TomTom, else the map pin), tomtom or pin
        atlasloot = true,
        auctionator = true,
        -- a column with no data hides whatever the choice
        columns = {upgrade = true, pawn = true, weapon = true, chance = true, source = true, price = false},
        questTab = {byQuest = true},
        tabs = {dungeon = true, raids = true, quests = true, crafts = true, reputation = true, pvp = true, events = true},
        craftTab = {bySkill = false, learnedFirst = true},
        -- priority = {drops = "fdj>atlasloot", ...}, see Core/State.lua
    },
    char = {
        filters = ns.Filter.Defaults(),
        sort = {stat = "SPELLDMG"},
        pawnScale = nil,
        hidden = {}, -- [item key] = true
        bank = {items = {}, seen = false},
        reminder = {}, -- the instance it last showed for
        fdjHint = false,
    },
    global = {
        characters = {}, -- ["Name-Realm"] = {name, realm, class, classID, race, raceID, level, faction, professions}
        favourites = {}, -- ["Name-Realm"] = {[itemID] = tier}
        tradeSkills = {}, -- [skill line] = {[itemID] = spell or true}, from profession windows
    },
}
ns.DEFAULTS = defaults

-- MIGRATIONS[scope][n] upgrades from version n - 1
local SCHEMA = {profile = 2, char = 1, global = 1}
local MIGRATIONS = {
    profile = {
        [1] = function() end,
        -- AceDB saves only changes and the old switch defaulted to on, so a saved value can only mean "off"
        [2] = function(profile) if type(profile.tooltip) == "table" then profile.tooltip.source = nil end end,
    },
    char = {[1] = function() end},
    global = {[1] = function() end},
}
ns.SCHEMA_VERSION = SCHEMA.profile
ns.MIGRATIONS = MIGRATIONS

function addon:Migrate(scope)
    local data = self.db[scope]
    local version = type(data.schemaVersion) == "number" and data.schemaVersion or 0
    for target = version + 1, SCHEMA[scope] do
        local migrate = MIGRATIONS[scope][target]
        if migrate then migrate(data, self.db) end
    end
    data.schemaVersion = SCHEMA[scope]
end

function addon:MigrateProfile() self:Migrate("profile") end

-- skill lines we don't know can't show anywhere
local function pruneTradeSkills(global)
    for id, items in pairs(global.tradeSkills) do
        if not ns.Crafts.BY_ID[id] or type(items) ~= "table" then global.tradeSkills[id] = nil end
    end
end

function addon:Print(...) print("|cff66ccff" .. ns.TITLE .. "|r:", ...) end
function ns.Print(...) addon:Print(...) end

-- one chat notice per session, the rest go to /flf dump all
local MAX_ERRORS = 10
local errors = {} -- oldest first
local errorNoticeShown = false

function ns.ReportError(err, stack)
    local message = tostring(err)
    for _, entry in ipairs(errors) do
        if entry.message == message then
            entry.count = entry.count + 1
            return
        end
    end
    errors[#errors + 1] = {message = message, stack = stack, count = 1}
    if #errors > MAX_ERRORS then table.remove(errors, 1) end
    if not errorNoticeShown then
        errorNoticeShown = true
        addon:Print(format(L["Error (shown once): %s"], message))
    end
end

function ns.Errors() return errors end

-- the handler runs before unwinding, so the stack is still there
local function onError(err)
    ns.ReportError(err, debugstack and debugstack(2) or nil)
    return err
end

-- closure because 5.1's xpcall drops extra arguments
function ns.Guard(fn, ...)
    local count = select("#", ...)
    if count == 0 then return (xpcall(fn, onError)) end
    local args = {...}
    return (xpcall(function() return fn(unpack(args, 1, count)) end, onError))
end

-- redraws wait until combat ends
local changeListeners = {}
function ns.OnChange(fn) changeListeners[#changeListeners + 1] = fn end

local pendingKinds = {}
local changeQueued = false
local function flushChanges()
    changeQueued = false
    if ns.inCombat then return end
    local kinds = pendingKinds
    pendingKinds = {}
    for _, fn in ipairs(changeListeners) do ns.Guard(fn, kinds) end
end

function ns.FireChange(kind)
    pendingKinds[kind or "data"] = true
    if changeQueued or ns.inCombat then return end
    changeQueued = true
    C_Timer.After(0, flushChanges)
end

local function sameRanks(a, b)
    if a == nil or b == nil then return a == b end
    for id, rank in pairs(a) do if b[id] ~= rank then return false end end
    for id in pairs(b) do if a[id] == nil then return false end end
    return true
end

-- true when the professions changed
local function updateCharacter()
    local key = ns.Favourites.CharKey()
    if not key then return false end
    ns.charKey = key
    local _, class, classID = UnitClass("player")
    local _, raceFile, raceID = UnitRace("player")
    local level = UnitLevel("player")
    local faction = UnitFactionGroup("player")
    local name, realm = UnitName("player"), GetRealmName()
    local data = addon.db.global.characters[key] or {}
    local before = data.professions
    data.name = not isSecret(name) and name or data.name
    data.realm = not isSecret(realm) and realm or data.realm
    if not isSecret(class) and class then data.class = class end
    if not isSecret(classID) and type(classID) == "number" then data.classID = classID end
    -- kept so alts' lists know them too
    local professions = ns.Crafts.LearnedProfessions()
    if professions then data.professions = professions end
    if not isSecret(raceFile) and raceFile then data.race = raceFile end
    if not isSecret(raceID) and raceID then data.raceID = raceID end
    if not isSecret(level) and type(level) == "number" and level > 0 then data.level = level end
    if not isSecret(faction) and faction then data.faction = faction end
    addon.db.global.characters[key] = data
    ns.InvalidateCharacters()
    return not sameRanks(before, data.professions)
end
ns.UpdateCharacter = updateCharacter

function ns.Filters() return addon.db.char.filters end

function ns.ResetFilters()
    local filters = addon.db.char.filters
    local keep = {slot = filters.slot, dungeonSlot = filters.dungeonSlot}
    for key in pairs(filters) do filters[key] = nil end
    for key, value in pairs(ns.Filter.Defaults()) do filters[key] = value end
    filters.slot, filters.dungeonSlot = keep.slot, keep.dungeonSlot
    ns.FireChange("filters")
end

local started = false

function addon:OnProfileChanged()
    self:Migrate("profile")
    LibStub("LibDBIcon-1.0"):Refresh(ADDON_NAME, self.db.profile.minimap)
    if started then
        for _, provider in ipairs({ns.Questie, ns.Crafts, ns.AtlasLootLists}) do
            if provider.Enabled() and provider.State() == "off" then provider.Init() end
        end
        ns.Owned.ScanSyndicator()
        ns.Auctionator.Hook()
        ns.Auctionator.Invalidate()
        ns.RebuildIndex()
        ns.FireChange("owned")
    end
    if ns.Options then ns.Options:OnProfileChanged() end
    ns.FireChange("profile")
end

function addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ForeverLootFinderDB", defaults, true)
    ForeverLootFinderCache = ns.Cache.Load(rawget(_G, "ForeverLootFinderCache"))
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    for scope in pairs(SCHEMA) do self:Migrate(scope) end
    pruneTradeSkills(self.db.global)
    for _, command in ipairs({"flf", "lootfinder"}) do self:RegisterChatCommand(command, "OnSlashCommand") end
    self:SetupMinimapButton()
end

local fdjNoticeShown = false
-- FDJ is optional, so only a broken one gets a message
function ns.FDJMessage()
    if ns.DungeonJournal.Enabled() and ns.DungeonJournal.Status() == "invalid" then
        return L["Can't read DungeonJournal's loot data. Forever Loot Finder may need an update."]
    end
    return nil
end

local function onCombat(inCombat)
    ns.inCombat = inCombat
    ns.Items.SetPaused(inCombat)
    ns.Pawn.SetPaused(inCombat)
    if inCombat then
        if ns.Widgets then ns.Widgets.CloseMenu() end
    else
        ns.FlushIndex()
        if next(pendingKinds) ~= nil then ns.FireChange("combat") end
    end
end

local bankOpen = false

-- a plain frame, so an event this client lacks doesn't break the others
local HANDLERS = {
    PLAYER_REGEN_DISABLED = function() onCombat(true) end,
    PLAYER_REGEN_ENABLED = function() onCombat(false) end,
    PLAYER_LEVEL_UP = function(level)
        updateCharacter()
        if type(level) == "number" and not isSecret(level) and ns.charKey then
            addon.db.global.characters[ns.charKey].level = level
            ns.InvalidateCharacters()
        end
        ns.FireChange("level")
    end,
    PLAYER_EQUIPMENT_CHANGED = function()
        ns.Owned.Invalidate()
        ns.Pawn.ClearEquipped()
        ns.FireChange("owned")
    end,
    BAG_UPDATE_DELAYED = function()
        ns.Owned.ScanBags()
        if bankOpen then ns.Owned.ScanBank() end
        ns.FireChange("owned")
    end,
    BANKFRAME_OPENED = function()
        bankOpen = true
        ns.Owned.ScanBank()
        ns.FireChange("owned")
    end,
    BANKFRAME_CLOSED = function() bankOpen = false end,
    PLAYERBANKSLOTS_CHANGED = function()
        if not bankOpen then return end
        ns.Owned.ScanBank()
        ns.FireChange("owned")
    end,
    -- FDJ loads before FLF as a rule, a late one is still read
    ADDON_LOADED = function(name)
        if name == "ForeverDungeonJournal" then
            ns.AtlasLootLists.Reread()
            ns.RebuildIndex(true)
        end
    end,
    PLAYER_ENTERING_WORLD = function(_, isReload) ns.Reminder.OnEnteringWorld(isReload == true) end,
    LOOT_READY = function() ns.DropAlert.OnLootReady() end,
    START_LOOT_ROLL = function(...) ns.DropAlert.OnLootRoll(...) end,
    CHAT_MSG_LOOT = function(...) ns.DropAlert.OnChatLoot(...) end,
    QUEST_TURNED_IN = function(...)
        ns.Questie.OnQuestTurnedIn(...)
        ns.FireChange("quests")
    end,
    AUCTION_HOUSE_CLOSED = function() ns.Auctionator.Invalidate() end,
    -- fires on every weapon skill-up too
    SKILL_LINES_CHANGED = function() if updateCharacter() then ns.FireChange("professions") end end,
    -- an index still missing an addon's items would prune them
    PLAYER_LOGOUT = function()
        local settled = ns.IndexSettled()
        for _, provider in ipairs({ns.Questie, ns.Crafts, ns.AtlasLootLists}) do
            local state = provider.State()
            if state == "waiting" or state == "scanning" then settled = false end
        end
        ns.Cache.Prune(settled and ns.Items.Tracked() or nil, ns.Pawn.IsReady() and ns.Pawn.Exists or nil)
    end,
}
local function onTradeSkill() ns.Crafts.OnTradeSkill() end
for _, event in ipairs({"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE"}) do
    HANDLERS[event] = onTradeSkill
end

local function onEvent(_, event, ...)
    local handler = HANDLERS[event]
    if handler then handler(...) end
end

function addon:OnEnable()
    started = true
    updateCharacter()
    ns.Items.Init()
    ns.Pawn.Init()
    ns.Owned.Scan()
    ns.Owned.HookSyndicator()
    ns.Questie.Init()
    ns.Crafts.Init()
    ns.AtlasLootLists.Init()
    ns.Auctionator.Init()
    ns.Tooltip.Enable()
    local frame = CreateFrame("Frame")
    for event in pairs(HANDLERS) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(...) ns.Guard(onEvent, ...) end)
    ns.Items.OnChange(function() ns.FireChange("items") end)
    ns.Pawn.OnChange(function() ns.FireChange("pawnValues") end)

    local message = ns.FDJMessage()
    if message and not fdjNoticeShown then
        fdjNoticeShown = true
        self:Print(message)
    elseif not message and not self.db.char.fdjHint and ns.Favourites.HasFDJList() then
        self.db.char.fdjHint = true
        self:Print(
          L["Copy your Dungeon Journal favourites: Favourites tab, \"Import FDJ favourites\"."])
    end
end

local function printHelp()
    local function line(usage, text) print("  |cffffd100/flf " .. usage .. "|r - " .. text) end
    addon:Print(L["Commands (also /lootfinder):"])
    print("  |cffffd100/flf|r - " .. L["open the window"])
    line("config", L["open the settings"])
    line("reset", L["move the windows back to the centre"])
    line("fav <item>", L["add an item (link or ID) to favourites"])
    line("refresh", L["reread the Dungeon Journal, rebuild the lists"])
    line("dump stats", L["all item stats from the client"])
    line("dump fdj", L["Dungeon Journal data"])
    line("dump questie", L["Questie data"])
    line("dump crafts", L["AtlasLoot and profession data"])
    line("dump items", L["items not loaded, and why"])
    line("dump all", L["all dumps but stats"])
end

function addon:OnSlashCommand(input)
    local command, nextPos = self:GetArgs(input, 1)
    command = command and command:lower()
    local rest = strtrim(input:sub(nextPos or #input + 1))
    if not command then
        ns.MainWindow.Toggle()
    elseif command == "help" then
        printHelp()
    elseif command == "config" or command == "options" then
        ns.Options:Toggle()
    elseif command == "reset" then
        ns.MainWindow.ResetPosition()
        ns.Options:ResetPosition()
    elseif command == "refresh" then
        ns.RebuildIndex(true)
    elseif command == "fav" then
        local id = ns.Util.ItemIDFromLink(rest) or tonumber(rest:match("^(%d+)$"))
        local idx = ns.GetIndex()
        if not id then
            self:Print(L["Usage: /flf fav <item link or ID>"])
        elseif not ns.Favourites.CanAdd(id) then
            self:Print(L["That item can't be worn."])
        else
            local tier = self.db.profile.favourites.defaultTier
            ns.Favourites.Set(id, tier)
            self:Print(format(L["Added to favourites (%s)."], ns.Favourites.TierLabel(tier)))
            if not (idx and idx.byKey[id]) then self:Print(L["No addon lists where it's from, so it shows only under Favourites."]) end
        end
    elseif command == "dump" then
        ns.Dump.Start(rest:lower())
    else
        self:Print(format(L["Unknown command \"%s\"."], command))
        printHelp()
    end
end

function addon:SetupMinimapButton()
    local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = ns.TITLE,
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.Options:Toggle()
            else
                ns.MainWindow.Toggle()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(ns.TITLE)
            tooltip:AddLine(L["Click: loot list"], 1, 1, 1)
            tooltip:AddLine(L["Right-click: settings"], 1, 1, 1)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register(ADDON_NAME, launcher, self.db.profile.minimap)
end

function addon:SetMinimapButtonShown(shown)
    self.db.profile.minimap.hide = not shown
    local icon = LibStub("LibDBIcon-1.0")
    if shown then
        icon:Show(ADDON_NAME)
    else
        icon:Hide(ADDON_NAME)
    end
end

-- read by Bindings.xml
BINDING_HEADER_FOREVERLOOTFINDER = ns.TITLE
BINDING_NAME_FOREVERLOOTFINDER_TOGGLE = L["Toggle the loot list"]
function ForeverLootFinder_Toggle() ns.Guard(ns.MainWindow.Toggle) end
