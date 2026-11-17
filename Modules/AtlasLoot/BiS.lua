-- AtlasLoot's BiS tooltip addon (AtlasBIStooltips). read-only, and only when the player asks to import a list
local _, ns = ...
local L = ns.L

local BiS = {}
ns.AtlasLootBiS = BiS

local ADDON = "AtlasBIStooltips"

-- sliccNote.BIS: id -> {class, spec, comment}. sliccNote.Items: itemID -> {bis id -> rank}.
-- a spec ending in _P2 or _P3 is that phase, anything else is phase 1
local function data()
    local note = rawget(_G, "sliccNote")
    if type(note) ~= "table" or type(note.BIS) ~= "table" or type(note.Items) ~= "table" then return nil end
    return note
end

function BiS.Installed() return ns.Util.AddOnLoaded(ADDON) or data() ~= nil end

local function phaseOf(spec)
    local phase = tonumber(spec:match("_P(%d)$"))
    return phase or 1, (spec:gsub("_P%d$", ""))
end

-- pure, for tests: lists for one class, with their items sorted by rank
function BiS.ListsFrom(note, classFile)
    local lists, byID = {}, {}
    for id, record in pairs(note.BIS) do
        if type(record) == "table" and type(record.class) == "string" and record.class:upper() == classFile then
            local spec = type(record.spec) == "string" and record.spec or ""
            local phase, name = phaseOf(spec)
            local comment = type(record.comment) == "string" and record.comment ~= "" and record.comment or nil
            local list = {key = id, spec = name, phase = phase, comment = comment, items = {}}
            byID[id] = list
            lists[#lists + 1] = list
        end
    end
    for itemID, ranks in pairs(note.Items) do
        local id = tonumber(itemID)
        if id and id > 0 and type(ranks) == "table" then
            for listID, rank in pairs(ranks) do
                local list = byID[listID]
                if list then list.items[#list.items + 1] = {id = id, rank = tonumber(rank) or 99} end
            end
        end
    end
    local kept = {}
    for _, list in ipairs(lists) do
        if #list.items > 0 then
            table.sort(list.items, function(a, b)
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.id < b.id
            end)
            kept[#kept + 1] = list
        end
    end
    table.sort(kept, function(a, b)
        if a.spec ~= b.spec then return a.spec < b.spec end
        if a.phase ~= b.phase then return a.phase < b.phase end
        return tostring(a.comment or "") < tostring(b.comment or "")
    end)
    return kept
end

function BiS.Lists(classFile)
    local note = data()
    if not note or not classFile then return {} end
    local ok, lists = pcall(BiS.ListsFrom, note, classFile)
    return ok and lists or {}
end

function BiS.Label(list)
    local text = format(L["%s, phase %d"], list.spec, list.phase)
    if list.comment then text = text .. " (" .. list.comment .. ")" end
    return text .. " — " .. format(L["%d items"], #list.items)
end
