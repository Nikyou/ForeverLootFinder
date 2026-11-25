-- the Reputation, PvP and World events tabs, from FDJ's, AtlasLoot's and ATT's lists. Questie's holiday quests fill
-- events too, and a vendor's or quest's item that needs a rank or a standing goes where its tooltip says
local _, ns = ...
local L = ns.L

local function standingLabel(standing) return standing and ns.AtlasLootLists.StandingName(standing) or "" end

local function emptyHint()
    if ns.AtlasLootLists.Installed() or ns.ATT.Installed() then return nil end
    return L["Needs AtlasLoot or ALL THE THINGS."]
end

local function ofKind(kind) return function(source, _, row) return ns.Filter.KindOf(source, row and row.info) == kind end end

local function infoOf(row) return row and row.info or {} end

ns.Cards.Tab({
    key = "reputation",
    label = L["Reputation"],
    accept = ofKind("reputation"),
    own = {"reputation"},
    card = function(source, _, row)
        local name = source.factionName or infoOf(row).reqReputation
        return name or source.factionID or "reputation", name or L["Reputation"]
    end,
    group = function(source, _, row)
        local standing = source.standing or infoOf(row).reqStanding
        return standing or 0, standingLabel(standing), standing or 0
    end,
    emptyHint = emptyHint,
})

-- one card per battleground whoever lists it, then Honor & Ranks and the rest by their section
ns.Cards.Tab({
    key = "pvp",
    label = L["PvP"],
    accept = ofKind("pvp"),
    own = {"pvp"},
    card = function(source, _, row)
        local info = infoOf(row)
        local key = source.pvpKey or info.pvpFaction
        local name = ns.DungeonJournal.BattlegroundName(key) or source.section or info.reqReputation
        return key or source.section or "pvp", name or L["PvP"]
    end,
    group = function(source, _, row)
        local info = infoOf(row)
        local rank = source.pvpRank or info.pvpRank
        local standing = source.standing or info.reqStanding
        local label, order
        if source.fromQuest then
            label, order = L["Quest rewards"], 9
        elseif rank then
            label, order = ns.Tooltip.RankName(rank, source.faction), 10 + rank
        else
            label, order = standingLabel(standing), standing or 0
        end
        local faction = source.faction == "Horde" and L["Horde"] or (source.faction == "Alliance" and L["Alliance"]) or nil
        if faction then label = label ~= "" and (label .. " " .. ns.Labels.DOT .. " " .. faction) or faction end
        return order .. tostring(source.faction), label, order * 10 + (source.faction == "Horde" and 1 or 0)
    end,
    emptyHint = function()
        if ns.DungeonJournal.Installed() or not emptyHint() then return nil end
        return L["Needs DungeonJournal, AtlasLoot or ALL THE THINGS."]
    end,
})

ns.Cards.Tab({
    key = "events",
    label = L["World events"],
    accept = ofKind("event"),
    own = {"event"},
    -- one card per holiday, whichever addon lists it and whatever it calls it
    card = function(source)
        local name = ns.Holidays.EventName(source) or "?"
        return source.holiday or name, name
    end,
    emptyHint = function() return not ns.Questie.Installed() and emptyHint() or nil end,
})
