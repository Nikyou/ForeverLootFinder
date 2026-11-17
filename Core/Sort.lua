-- pure Lua. unknown values always go last
local _, ns = ...
local StatMap, Filter = ns.StatMap, ns.Filter

local Sort = {}
ns.Sort = Sort

-- desc: the first click's direction
Sort.KEYS = {
    {key = "pawn", desc = true, pawn = true}, {key = "upgrade", desc = true, pawn = true}, {key = "stat", desc = true},
    {key = "ilvl", desc = true}, {key = "reqlevel", desc = true}, {key = "dungeonlevel", desc = false},
    {key = "speed", desc = true}, {key = "dps", desc = true}, {key = "chance", desc = true, chance = true},
    {key = "price", desc = false, price = true}, {key = "name", desc = false}, {key = "quality", desc = true},
}
Sort.BY_KEY = {}
for _, entry in ipairs(Sort.KEYS) do Sort.BY_KEY[entry.key] = entry end

local function dungeonLevel(row, dungeonByKey)
    local best
    for _, source in ipairs(row.sources or row.record.sources) do
        local dungeon = dungeonByKey and dungeonByKey[source.dungeon]
        local level = dungeon and dungeon.levelMin
        if level and (not best or level < best) then best = level end
    end
    return best
end

local function bestChance(row)
    local best
    for _, source in ipairs(row.sources or row.record.sources) do
        if source.chance and (not best or source.chance > best) then best = source.chance end
    end
    return best
end

function Sort.Value(row, key, opts)
    local info = row.info
    if key == "pawn" then return row.pawn end
    if key == "upgrade" then return row.upgrade end
    if key == "stat" then return opts.stat and info.stats and StatMap.Value(info.stats, opts.stat) or nil end
    if key == "ilvl" then return info.ilvl end
    if key == "reqlevel" then return info.minLevel end
    if key == "dungeonlevel" then return dungeonLevel(row, opts.dungeonByKey) end
    if key == "speed" then return Filter.IsWeapon(info) and info.speed or nil end
    if key == "dps" then return Filter.IsWeapon(info) and info.dps or nil end
    if key == "chance" then return bestChance(row) end
    if key == "price" then return row.auction and row.auction.price or nil end
    if key == "name" then return (info.name or row.record.name or ""):lower() end
    if key == "quality" then return info.quality or row.record.quality end
    return nil
end

local function tieBreak(a, b)
    local la, lb = a.info.ilvl or 0, b.info.ilvl or 0
    if la ~= lb then return la > lb end
    local na, nb = (a.info.name or a.record.name or ""):lower(), (b.info.name or b.record.name or ""):lower()
    if na ~= nb then return na < nb end
    return tostring(a.record.key) < tostring(b.record.key)
end

function Sort.Rows(rows, opts)
    local key = opts.key or "ilvl"
    local desc = opts.desc
    if desc == nil then desc = Sort.BY_KEY[key] and Sort.BY_KEY[key].desc end
    -- 0 means the item lacks the stat
    local values = {}
    for _, row in ipairs(rows) do
        local value = Sort.Value(row, key, opts)
        if key == "stat" and value == 0 then value = nil end
        values[row] = value
    end
    table.sort(rows, function(a, b)
        local va, vb = values[a], values[b]
        if va == nil and vb == nil then return tieBreak(a, b) end
        if va == nil then return false end
        if vb == nil then return true end
        if va == vb then return tieBreak(a, b) end
        if desc then return va > vb end
        return va < vb
    end)
    return rows
end
