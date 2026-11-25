-- dungeon quests go under their zone when Questie knows it, else under the dungeon
local _, ns = ...
local L = ns.L

local function questLabel(source, done)
    local level = source.questLevel or source.reqLevel
    local name = source.questName or source.section or "?"
    local text = level and format("[%d] %s", level, name) or name
    if done then text = format(L["%s (done)"], text) end
    return text
end

-- each faction's or race's copy of a quest counts once
local function questKey(source)
    local name = type(source.questName) == "string" and source.questName:lower()
    return name and ("name:" .. name) or tostring(source.questID or source.section)
end

-- by name: QuestieDB keys zones by area, ATT and ForeverDB by map
local function zoneOf(source, ctx)
    if source.zoneKey and source.zoneKey ~= "zone:other" and source.zoneName then
        return "zone:" .. ns.Util.Lower(source.zoneName), source.zoneName
    end
    if source.dungeon then return "dungeon:" .. source.dungeon, ns.Tooltip.DungeonLabel(source.dungeon, ctx.dungeonByKey) end
    return "zone:other", L["Other quests"]
end

local function entries(_, order, ctx, _)
    table.sort(order, function(a, b)
        if (a.low or 999) ~= (b.low or 999) then return (a.low or 999) < (b.low or 999) end
        return a.title < b.title
    end)
    local list, level = {}, ctx.level
    for _, zone in ipairs(order) do
        local quests = 0
        for _ in pairs(zone.quests) do quests = quests + 1 end
        local info = {}
        if zone.low then
            info[#info + 1] = zone.low == zone.high and tostring(zone.low) or format("%d–%d", zone.low, zone.high)
        end
        info[#info + 1] = format(L["%d quests"], quests)
        info[#info + 1] = format(L["%d items"], zone.items)
        list[#list + 1] = {
            title = zone.title,
            info = table.concat(info, "   "),
            glow = zone.low ~= nil and zone.low <= level + 3 and (zone.high or zone.low) >= level - 2,
            groups = zone.list,
        }
    end
    return list
end

ns.Cards.Tab({
    key = "quests",
    label = L["Quests"],
    accept = function(source) return ns.Index.IsQuest(source) end,
    card = zoneOf,
    group = function(source, ctx)
        local done = source.questID and ctx.completed and ctx.completed(source.questID)
        return questKey(source), questLabel(source, done), source.questLevel or source.reqLevel or 0
    end,
    grouping = {
        label = L["Group by quest"],
        get = function(profile) return profile.questTab.byQuest ~= false end,
        set = function(profile, on) profile.questTab.byQuest = on end,
    },
    onSource = function(zone, source)
        zone.quests = zone.quests or {}
        zone.quests[questKey(source)] = true
        local questLevel = source.questLevel or source.reqLevel
        if questLevel then
            zone.low = math.min(zone.low or questLevel, questLevel)
            zone.high = math.max(zone.high or questLevel, questLevel)
        end
    end,
    entries = entries,
    emptyHint = function()
        if not ns.Questie.Installed() then return L["Install Questie for quests outside dungeons."] end
        local state = ns.Questie.State()
        if state == "scanning" or state == "waiting" then return L["Reading Questie..."] end
    end,
})
