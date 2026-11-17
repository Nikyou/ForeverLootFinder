-- Attune's quest rewards, taken from Wowhead's Forever pages. a fallback: QuestieDB and FDJ win wherever they have
-- the same quest, Attune fills the few they miss (Catacomb Cloak, Lightning's Grasp). read-only
local _, ns = ...
local L = ns.L

local Attune = {}
ns.Attune = Attune

local Util = ns.Util
local status = Util.NewStatus("attune", {quests = 0, rewards = 0})
local stats = status.counts
local entries = {}
local builtFor -- Questie's state the names came from

local function data()
    local attune = rawget(_G, "Attune_Data")
    if type(attune) ~= "table" or type(attune.questRewards) ~= "table" then return nil end
    return attune
end

function Attune.Installed() return data() ~= nil end
function Attune.Enabled() return ns.addon.db.profile.attune ~= false end
function Attune.State() return status.state end
function Attune.Status() return status end
function Attune.Stats() return stats end

-- quest ID -> the attunement or dungeon page it's a step of
local function questPages(attune)
    local pages = {}
    for _, page in ipairs(type(attune.attunes) == "table" and attune.attunes or {}) do
        if type(page) == "table" and page.ID then pages[tostring(page.ID)] = page end
    end
    local out = {}
    for _, step in ipairs(type(attune.steps) == "table" and attune.steps or {}) do
        local questID = type(step) == "table" and tonumber(step.ID_WOWHEAD)
        local quest = step.TYPE == "Quest" or step.TYPE == "Pick Up" or step.TYPE == "Turn In"
        if quest and questID and questID > 0 and not out[questID] then out[questID] = pages[tostring(step.ID_ATTUNE)] end
    end
    return out
end

local function questName(questID)
    local name, level = ns.Questie.QuestBasics(questID)
    if name then return name, level end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if type(title) == "string" and title ~= "" and not Util.IsSecret(title) then return title, nil end
    return format(L["Quest %d"], questID), nil
end

-- pure, for tests: one entry per wearable reward
function Attune.Read(attune, equippable, nameOf, dungeonOf)
    local out, quests = {}, 0
    local pages = questPages(attune)
    for questID, reward in pairs(attune.questRewards) do
        if type(questID) == "number" and type(reward) == "table" then
            local items = {}
            for _, list in ipairs({reward.choice, reward.fixed}) do
                for _, item in ipairs(type(list) == "table" and list or {}) do
                    local id = type(item) == "table" and tonumber(item[1])
                    if id and equippable(id) then items[#items + 1] = id end
                end
            end
            if #items > 0 then
                quests = quests + 1
                local name, reqLevel = nameOf(questID)
                local page = pages[questID]
                local faction = page and (page.FACTION == "Horde" or page.FACTION == "Alliance") and page.FACTION or nil
                local placeName = page and type(page.NAME) == "string" and page.NAME or nil
                local dungeon = placeName and dungeonOf(placeName)
                for _, id in ipairs(items) do
                    local entry = {id = id, questID = questID, questName = name, reqLevel = reqLevel, faction = faction}
                    if dungeon then
                        entry.kind, entry.dungeon = "quest", dungeon
                    else
                        entry.kind = "zoneQuest"
                        entry.zoneName = placeName
                        entry.zoneKey = placeName and ("attune:" .. placeName) or nil
                    end
                    out[#out + 1] = entry
                end
            end
        end
    end
    return out, quests
end

local function dungeonOf(name)
    local found = ns.DungeonJournal.MatchInstance(nil, name)
    return found and found[1] or nil
end

local function build()
    local attune = data()
    if not attune then
        status.state = "nodata"
        entries = {}
        return
    end
    local started = Util.Clock()
    local ok, out, quests = pcall(Attune.Read, attune, Util.Equippable, questName, dungeonOf)
    if not ok then
        status.state, status.error = "nodata", tostring(out)
        ns.ReportError(out)
        entries = {}
        return
    end
    entries = out
    stats.quests, stats.rewards = quests, #out
    status.ms = Util.Clock() - started
    status.state = #out > 0 and "done" or "nodata"
end

-- names come from QuestieDB once it has read, so built again then
function Attune.Entries()
    if not Attune.Enabled() or not Attune.Installed() then return {} end
    local questie = ns.Questie.State()
    if builtFor ~= questie then
        builtFor = questie
        build()
    end
    return entries
end

function Attune.Init()
    if not Attune.Installed() then
        status.state = "off"
        return
    end
    status.state = Attune.Enabled() and "waiting" or "off"
end

function Attune.SetEnabled(value)
    ns.addon.db.profile.attune = value and true or false
    builtFor = nil
    status.state = value and "waiting" or "off"
    ns.RebuildIndex()
end
