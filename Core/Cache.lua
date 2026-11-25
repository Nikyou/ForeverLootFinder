-- ForeverLootFinderCache: item data and Pawn values, so a new session doesn't wait on the server and Pawn.
-- dropped whole on a new client build, locale or format
local _, ns = ...

local Cache = {}
ns.Cache = Cache

Cache.VERSION = 2
local SEP = "^"

-- reset: why the cache was dropped at login
Cache.stats = {hits = 0, misses = 0, written = 0, changed = 0, removed = 0, pruned = 0, reset = nil}

local db

local function buildText()
    local getBuild = rawget(_G, "GetBuildInfo")
    if type(getBuild) ~= "function" then return "?" end
    local version, build = getBuild()
    return tostring(version) .. "." .. tostring(build)
end

local function localeText()
    local getLocale = rawget(_G, "GetLocale")
    return type(getLocale) == "function" and tostring(getLocale()) or "?"
end

function Cache.Load(saved)
    local build, locale = buildText(), localeText()
    local reason
    if type(saved) ~= "table" then
        reason = "new"
    elseif saved.version ~= Cache.VERSION then
        reason = "format"
    elseif saved.build ~= build then
        reason = "build"
    elseif saved.locale ~= locale then
        reason = "locale"
    end
    if reason then saved = {version = Cache.VERSION, build = build, locale = locale, createdAt = time()} end
    for _, key in ipairs({"items", "sets", "pawn", "unavailable", "holidays"}) do
        if type(saved[key]) ~= "table" then saved[key] = {} end
    end
    Cache.stats.reset = reason
    db = saved
    return saved
end

function Cache.Loaded() return db ~= nil end

-- one short string per item, "^" between fields, trailing empty ones left off
local BIND = {BOP = "P", BOE = "E", BOU = "U", QUEST = "Q"}
local BIND_BACK = {P = "BOP", E = "BOE", U = "BOU", Q = "QUEST"}

-- two decimals are plenty and keep the file small
local function num(value)
    if type(value) ~= "number" then return "" end
    return (format("%.2f", value):gsub("%.?0+$", ""))
end

local function list(names) return names and table.concat(names, ",") or "" end

local function split(text, sep)
    local out = {}
    if text == "" then return out end
    for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return out
end

function Cache.Encode(info)
    if not (info.loaded and info.tooltipLoaded) or info.tooltipMissing or not info.slot then return nil end
    local stats = {}
    for key, value in pairs(info.stats or {}) do stats[#stats + 1] = key .. "=" .. num(value) end
    table.sort(stats)
    local flags = (info.cosmetic and "c" or "") .. (info.hasUse and "u" or "") .. (info.hasProc and "p" or "")
                    .. (info.unique == "equipped" and "e" or info.unique and "q" or "")
    local skill = info.reqSkill
    local fields = {
        info.name or "", num(info.quality), num(info.ilvl), num(info.minLevel), BIND[info.bind] or "", num(info.setID), flags,
        table.concat(stats, ","), num(info.speed), num(info.dps), list(info.classes), list(info.races),
        skill and (skill.id .. "," .. num(skill.rank) .. "," .. (skill.name or "")) or "", info.setName or "", num(info.setTotal),
        num(info.pvpRank), num(info.reqStanding), info.reqReputation or "",
    }
    for _, field in ipairs(fields) do if field:find(SEP, 1, true) then return nil end end
    return (table.concat(fields, SEP):gsub("%^+$", ""))
end

local function names(text)
    if text == "" then return nil end
    return split(text, ",")
end

-- slot and type aren't saved, GetItemInfoInstant has them
function Cache.Decode(text, info)
    local f = split(text, SEP)
    info.name = f[1] ~= "" and f[1] or nil
    info.quality, info.ilvl = tonumber(f[2] or ""), tonumber(f[3] or "")
    info.minLevel = tonumber(f[4] or "") or 1
    info.bind = BIND_BACK[f[5] or ""]
    info.setID = tonumber(f[6] or "")
    local flags = f[7] or ""
    info.cosmetic = flags:find("c", 1, true) and true or nil
    info.hasUse, info.hasProc = flags:find("u", 1, true) and true or nil, flags:find("p", 1, true) and true or nil
    info.unique = flags:find("e", 1, true) and "equipped" or flags:find("q", 1, true) and "unique" or nil
    info.stats = {}
    for key, value in (f[8] or ""):gmatch("([^,=]+)=([^,]+)") do info.stats[key] = tonumber(value) end
    info.speed, info.dps = tonumber(f[9] or ""), tonumber(f[10] or "")
    info.classes, info.races = names(f[11] or ""), names(f[12] or "")
    local id, rank, skillName = (f[13] or ""):match("^(%d+),([%d.]*),(.*)$")
    info.reqSkill = id and {id = tonumber(id), rank = tonumber(rank), name = skillName} or nil
    info.setName = f[14] ~= "" and f[14] or nil
    info.setTotal = tonumber(f[15] or "")
    info.pvpRank, info.reqStanding = tonumber(f[16] or ""), tonumber(f[17] or "")
    info.reqReputation = (f[18] or "") ~= "" and f[18] or nil
    local bonuses = info.setName and db and db.sets[info.setName]
    info.setBonuses = bonuses and split(bonuses, "\n") or nil
    info.loaded, info.tooltipLoaded = true, true
    return info
end

function Cache.Get(id) return db and db.items[id] end

-- "new" or "changed", nil when nothing changed
function Cache.Put(id, info)
    if not db then return nil end
    local text = Cache.Encode(info)
    if not text then return nil end
    -- set bonuses once per set
    if info.setName and info.setBonuses and #info.setBonuses > 0 then
        db.sets[info.setName] = table.concat(info.setBonuses, "\n")
    end
    local old = db.items[id]
    if old == text then return nil end
    db.items[id] = text
    if old then
        Cache.stats.changed = Cache.stats.changed + 1
        return "changed"
    end
    Cache.stats.written = Cache.stats.written + 1
    return "new"
end

function Cache.Remove(id)
    if not (db and db.items[id]) then return end
    db.items[id] = nil
    Cache.stats.removed = Cache.stats.removed + 1
end

-- per scale, with the signature of its weights. another signature means the scale was edited: start over
function Cache.PawnValues(scale, signature)
    if not (db and signature) then return nil end
    local entry = db.pawn[scale]
    if type(entry) ~= "table" or entry.sig ~= signature or type(entry.values) ~= "table" then
        entry = {sig = signature, values = {}}
        db.pawn[scale] = entry
    end
    return entry.values
end

function Cache.ForgetPawn(id)
    if not db then return end
    for _, entry in pairs(db.pawn) do
        if type(entry) == "table" and type(entry.values) == "table" then entry.values[id] = nil end
    end
end

function Cache.ClearPawn() if db then wipe(db.pawn) end end

-- called at logout
-- items the server didn't give last time: "failed" or "noanswer". asked again, but briefly and last. a new build
-- starts over with the rest of the cache
-- the calendar's holiday names by event ID, in the client's language (a new locale starts over)
function Cache.HolidayNames() return db and db.holidays end

function Cache.Unavailable(id) return db and db.unavailable[id] end
function Cache.SetUnavailable(id, why) if db then db.unavailable[id] = why end end

function Cache.Prune(listed, scaleExists)
    if not db then return end
    if listed then
        for id in pairs(db.items) do
            if not listed[id] then
                db.items[id] = nil
                Cache.stats.pruned = Cache.stats.pruned + 1
            end
        end
        for _, entry in pairs(db.pawn) do
            if type(entry) == "table" and type(entry.values) == "table" then
                for id in pairs(entry.values) do if not listed[id] then entry.values[id] = nil end end
            end
        end
    end
    if scaleExists then for scale in pairs(db.pawn) do if not scaleExists(scale) then db.pawn[scale] = nil end end end
    db.savedAt = time()
end

function Cache.Summary()
    if not db then return nil end
    local out = {
        build = db.build,
        locale = db.locale,
        createdAt = db.createdAt,
        savedAt = db.savedAt,
        items = 0,
        sets = 0,
        unavailable = 0,
        bytes = 0,
        scales = {},
    }
    for _ in pairs(db.unavailable) do out.unavailable = out.unavailable + 1 end
    -- ["key"] = "value", plus indentation
    for id, text in pairs(db.items) do
        out.items = out.items + 1
        out.bytes = out.bytes + #tostring(id) + #text + 12
    end
    for name, text in pairs(db.sets) do
        out.sets = out.sets + 1
        out.bytes = out.bytes + #name + #text + 12
    end
    for scale, entry in pairs(db.pawn) do
        local count = 0
        for id, value in pairs(type(entry) == "table" and type(entry.values) == "table" and entry.values or {}) do
            count = count + 1
            out.bytes = out.bytes + #tostring(id) + #tostring(value) + 10
        end
        out.scales[#out.scales + 1] = {scale = scale, sig = type(entry) == "table" and entry.sig or nil, values = count}
    end
    table.sort(out.scales, function(a, b) return tostring(a.scale) < tostring(b.scale) end)
    return out
end
