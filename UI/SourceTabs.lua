-- AtlasLoot's Reputation, PvP and World events tabs
local _, ns = ...
local L = ns.L

local function standingLabel(standing)
    return standing and ns.Loot.StandingName(standing) or ""
end

local function emptyHint()
    if ns.Loot.Installed() then return nil end
    return L["Needs AtlasLoot."]
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
    card = function(source) return source.eventName or "?", source.eventName or "?" end,
    emptyHint = emptyHint,
})
