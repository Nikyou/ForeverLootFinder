-- holidays by the game's own names, off the calendar. AtlasLoot, ATT and Questie each name them their own way, so
-- their event lines carry one of these keys and get the name when shown
local _, ns = ...
local L = ns.L
local Util = ns.Util

local Holidays = {}
ns.Holidays = Holidays

-- the calendar's event IDs, as ATT's Forever data has them (Darkmoon Faire has one per place it sets up in), and a
-- name for a holiday the calendar hasn't shown yet
local KNOWN = {
    darkmoon = {ids = {374, 375, 263, 264}, name = L["Darkmoon Faire"]},
    lunar = {ids = {327}, name = L["Lunar Festival"]},
    love = {ids = {335}, name = L["Love is in the Air"]},
    noblegarden = {ids = {181}, name = L["Noblegarden"]},
    children = {ids = {201}, name = L["Children's Week"]},
    midsummer = {ids = {341}, name = L["Midsummer Fire Festival"]},
    fishing = {ids = {301}, name = L["Stranglethorn Fishing Extravaganza"]},
    harvest = {ids = {321}, name = L["Harvest Festival"]},
    hallows = {ids = {324}, name = L["Hallow's End"]},
    winterVeil = {ids = {141}, name = L["Feast of Winter Veil"]},
}
Holidays.KNOWN = KNOWN

local MONTHS = 12 -- every holiday comes round within a year
local START_DELAY = 15
-- a holiday Forever doesn't run is never on the calendar: look again a week later, not every login
local RESCAN_AFTER = 7 * 24 * 3600
local stats = {state = "off", months = 0}
Holidays.stats = stats

local function calendarName(key)
    local names = ns.Cache.HolidayNames()
    for _, id in ipairs(KNOWN[key].ids) do
        local name = names and names[id]
        if name then return name end
    end
    return nil
end

function Holidays.Name(key)
    if not KNOWN[key] then return nil end
    return calendarName(key) or KNOWN[key].name
end

-- an event line's name: its holiday's, or the one its addon gave
function Holidays.EventName(source) return source.holiday and Holidays.Name(source.holiday) or source.eventName end

function Holidays.Named()
    local count, total = 0, 0
    for key in pairs(KNOWN) do
        total = total + 1
        if calendarName(key) then count = count + 1 end
    end
    return count, total
end

-- the calendar runs every addon's CALENDAR_UPDATE_EVENT_LIST handler on each month change, so one month a frame,
-- out of combat, never while the calendar is open, and it's put back on the month it showed. chat lockdown makes its
-- values secret
local function calendarFree()
    if ns.inCombat or Util.SafeCall(rawget(_G, "InChatMessagingLockdown")) then return false end
    local frame = rawget(_G, "CalendarFrame")
    return not (type(frame) == "table" and frame.IsShown and frame:IsShown())
end

local function readMonth(calendar, names)
    local info = Util.SafeCall(calendar.GetMonthInfo, 0)
    local days = type(info) == "table" and tonumber(info.numDays) or 0
    for day = 1, days do
        for index = 1, tonumber(Util.SafeCall(calendar.GetNumDayEvents, 0, day)) or 0 do
            local event = Util.SafeCall(calendar.GetDayEvent, 0, day, index)
            local id, title = type(event) == "table" and event.eventID, type(event) == "table" and event.title
            if event and event.calendarType == "HOLIDAY" and type(id) == "number" and not Util.IsSecret(id) and type(title)
              == "string" and not Util.IsSecret(title) and title ~= "" then names[id] = title end
        end
    end
end

function Holidays.Scan()
    local calendar = rawget(_G, "C_Calendar")
    local clock = rawget(_G, "C_DateAndTime")
    local names = ns.Cache.HolidayNames()
    if not (names and type(calendar) == "table" and type(calendar.SetMonth) == "function" and clock) then
        stats.state = "no calendar"
        return
    end
    local named, total = Holidays.Named()
    if named == total or (tonumber(names.scannedAt) or 0) + RESCAN_AFTER > time() then
        stats.state = "done"
        return
    end
    if not calendarFree() then
        stats.state = "waiting"
        return C_Timer.After(START_DELAY, function() ns.Guard(Holidays.Scan) end)
    end
    local now = Util.SafeCall(clock.GetCurrentCalendarTime)
    local shown = Util.SafeCall(calendar.GetMonthInfo, 0)
    if type(now) ~= "table" or type(shown) ~= "table" then
        stats.state = "no calendar"
        return
    end
    stats.state, stats.months = "scanning", 0
    Util.SafeCall(calendar.SetAbsMonth, now.month, now.year)
    local function finish(done)
        Util.SafeCall(calendar.SetAbsMonth, shown.month, shown.year)
        if Holidays.Named() > named then ns.FireChange("holidays") end
        if done then
            stats.state, names.scannedAt = "done", time()
        else
            stats.state = "waiting"
            C_Timer.After(START_DELAY, function() ns.Guard(Holidays.Scan) end)
        end
    end
    local function step()
        if not calendarFree() then return finish(false) end
        readMonth(calendar, names)
        stats.months = stats.months + 1
        if stats.months >= MONTHS then return finish(true) end
        Util.SafeCall(calendar.SetMonth, 1)
        C_Timer.After(0, function() ns.Guard(step) end)
    end
    step()
end

-- the calendar asks the server for its list first
function Holidays.Init()
    local calendar = rawget(_G, "C_Calendar")
    if type(calendar) == "table" then Util.SafeCall(calendar.OpenCalendar) end
    stats.state = "waiting"
    C_Timer.After(START_DELAY, function() ns.Guard(Holidays.Scan) end)
end
