-- Dungeons and Raids, in FDJ's order with AtlasLoot's places after
local _, ns = ...
local L = ns.L

local function bossGroup(source)
    if source.kind == "combine" then return L["Combined"], L["Combined"] end
    local label = source.kind == "quest" and format(L["Quest: %s"], source.questName or source.section or "?")
                    or ns.DungeonJournal
                      .BossName(source.bossName or source.section or (source.kind == "trash" and L["Trash"]) or "?")
    return label, label
end

local function placeEntries(raids)
    return function(cards, _, ctx, index)
        local list, level = {}, ctx.level
        local hideEmpty = ns.addon.db.profile.dungeonTab.hideEmpty
        for _, dungeon in ipairs(index.dungeons) do
            local card = cards[dungeon.key]
            if (dungeon.raid == true) == raids and (card or not hideEmpty) then
                local info = {dungeon.levelText and (dungeon.levelText:gsub("%-", "–")) or ""}
                if dungeon.incomplete then info[#info + 1] = "|cffff8040" .. L["loot list incomplete"] .. "|r" end
                info[#info + 1] = format(L["%d items"], card and card.items or 0)
                local placeKey = dungeon.key
                local bossIndex = dungeon.bosses and dungeon.bosses[1] and dungeon.bosses[1].index or 1
                list[#list + 1] = {
                    title = ns.DungeonJournal.DungeonName(placeKey),
                    info = table.concat(info, "   "),
                    glow = dungeon.levelMin and level >= dungeon.levelMin and level <= (dungeon.levelMax or dungeon.levelMin),
                    dim = card == nil,
                    -- AtlasLoot's places aren't in the Dungeon Journal
                    onClick = function()
                        if IsShiftKeyDown() then
                            local target = ns.Waypoints.EntranceTarget(placeKey)
                            if target then ns.Waypoints.Go(target) end
                        elseif not dungeon.atlasloot then
                            ns.DungeonJournal.OpenDungeon(placeKey, bossIndex)
                        end
                    end,
                    fillTooltip = function(tooltip)
                        tooltip:AddLine(ns.DungeonJournal.DungeonName(placeKey))
                        if dungeon.atlasloot then
                            tooltip:AddLine(dungeon.raid and L["Raid, from AtlasLoot"] or L["From AtlasLoot"], 1, 1, 1)
                        elseif ns.DungeonJournal.CanOpenDungeon() then
                            tooltip:AddLine(L["Click: open in Dungeon Journal"], 1, 1, 1)
                        end
                        if dungeon.location then tooltip:AddLine(dungeon.location, 1, 1, 1) end
                        if ns.Waypoints.EntranceTarget(placeKey) then
                            tooltip:AddLine(L["Shift-click: waypoint to the entrance"], 0.6, 0.8, 1)
                        end
                    end,
                    groups = card and card.list or {},
                }
            end
        end
        return list
    end
end

local function placeSpec(key, label, raids)
    return {
        key = key,
        label = label,
        accept = function(source, ctx)
            local place = source.dungeon and ctx.dungeonByKey[source.dungeon]
            return place ~= nil and (place.raid == true) == raids
        end,
        card = function(source) return source.dungeon end,
        own = {raids and "raid" or "dungeon"},
        group = bossGroup,
        entries = placeEntries(raids),
    }
end

local dungeons = placeSpec("dungeon", L["Dungeons"], false)
dungeons.grouping = {
    label = L["Group by boss"],
    get = function(profile) return profile.dungeonTab.byBoss end,
    set = function(profile, on) profile.dungeonTab.byBoss = on end,
}
ns.Cards.Tab(dungeons)

local raids = placeSpec("raids", L["Raids"], true)
raids.emptyHint = function(index)
    for _, dungeon in ipairs(index.dungeons) do if dungeon.raid then return nil end end
    return L["Raids and world bosses need AtlasLoot."]
end
ns.Cards.Tab(raids)
