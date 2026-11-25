-- the Reputation, PvP and World events tabs, from AtlasLoot's and ATT's lists. Questie's holiday quests fill events too
local _, ns = ...
local L = ns.L

local function standingLabel(standing)
    return standing and ns.AtlasLootLists.StandingName(standing) or ""
end

local function emptyHint()
    if ns.AtlasLootLists.Installed() or ns.ATT.Installed() then return nil end
    return L["Needs AtlasLoot or ALL THE THINGS."]
end

local function ofKind(kind) return function(source) return source.kind == kind end end

ns.Cards.Tab({
    key = "reputation",
    label = L["Reputation"],
    accept = ofKind("reputation"),
    card = function(source) return source.factionID or source.factionName, source.factionName or L["Reputation"] end,
    group = function(source) return source.standing or 0, standingLabel(source.standing), source.standing or 0 end,
    emptyHint = emptyHint,
})

ns.Cards.Tab({
    key = "pvp",
    label = L["PvP"],
    accept = ofKind("pvp"),
    card = function(source) return source.section or "pvp", source.section or L["PvP"] end,
    group = function(source)
        local faction = source.faction == "Horde" and L["Horde"] or (source.faction == "Alliance" and L["Alliance"]) or nil
        local label = standingLabel(source.standing)
        if faction then label = label ~= "" and (label .. " " .. ns.Labels.DOT .. " " .. faction) or faction end
        return tostring(source.standing) .. tostring(source.faction), label, (source.standing or 0) * 10
                 + (source.faction == "Horde" and 1 or 0)
    end,
    emptyHint = emptyHint,
})

ns.Cards.Tab({
    key = "events",
    label = L["World events"],
    accept = ofKind("event"),
    -- one card per holiday, whichever addon lists it and whatever it calls it
    card = function(source)
        local name = ns.Holidays.EventName(source) or "?"
        return source.holiday or name, name
    end,
    emptyHint = function() return not ns.Questie.Installed() and emptyHint() or nil end,
})
