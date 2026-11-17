local _, ns = ...
local L = ns.L
local W, Options = ns.Widgets, ns.Options

local QUESTIE_TEAM = "Aero, Logon, Muehe, TheCrux (BreakBB), Drejjmit, Dyaxler, Cheeq, TechnoHunter, Yttrium"

local function addons()
    return {
        {name = "DungeonJournal (ForeverDungeonJournal)", by = format(L["By %s"], "Exehn"),
         use = L["Dungeon loot, bosses and quests."]},
        {name = format(L["%s (comes with %s)"], "QuestieDB", "Questie"),
         by = format(L["By the Questie team: %s and others"], QUESTIE_TEAM),
         use = L["Quest rewards, vendors and creature drops."]},
        {name = "AtlasLoot Classic Forever", by = format(L["By %s"], "sliccer"),
         use = L["Raids, crafted gear, reputation, PvP and event rewards, drop chances."]},
        {name = "Pawn", by = format(L["By %s"], "Vger"), use = L["Item scores and upgrades."]},
        {name = format(L["%s (comes with %s)"], "Syndicator", "Baganator"), by = format(L["By %s"], "plusmouse"),
         use = L["Items in bags, bank and mail across characters."]},
        {name = "Auctionator", by = format(L["By %s"], "plusmouse, Borjamacare"),
         use = L["Auction prices and shopping lists."]},
        {name = "Attune", by = format(L["By %s"], "CixiDelmont"), use = L["Quest rewards from Wowhead's Forever pages."]},
        {name = "SilverDragon", by = format(L["By %s"], "Kemayo"), use = L["Rare creatures and their loot."]},
    }
end

local function create(parent)
    local col = W.Column(parent, 0, Options.RIGHT + Options.COLUMN)
    col.title(ns.TITLE)
    col.label(format(L["Made by %s"], "Nikyou"))
    col.help(L["It reads its data from these addons. Thanks to their authors!"], 0)
    for _, addon in ipairs(addons()) do
        col.title(addon.name)
        col.label(addon.by)
        col.help(addon.use, 0)
    end
end

table.insert(ns.OptionsTabs, {key = "credits", label = L["Credits"], Create = create})
