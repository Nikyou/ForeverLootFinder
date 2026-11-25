local _, ns = ...

local Sets = {}
ns.Sets = Sets

-- Forever's client has no piece list for a set, only the setID and the "Name (0/8)" tooltip line
function Sets.KeyOf(info)
    if info.setID then return info.setID end
    if info.setName then return "name:" .. info.setName end
    return nil
end

function Sets.Group(records, infoOf)
    local sets = {}
    for _, record in ipairs(records) do
        local info = infoOf(record)
        local key = info.slot and Sets.KeyOf(info)
        if key then
            local set = sets[key]
            if not set then
                set = {key = key, pieces = {}}
                sets[key] = set
            end
            set.name = set.name or info.setName
            set.total = set.total or info.setTotal
            if not set.bonuses and info.setBonuses and #info.setBonuses > 0 then set.bonuses = info.setBonuses end
            set.pieces[#set.pieces + 1] = record
        end
    end
    return sets
end

function Sets.Name(set)
    if set.name then return set.name end
    if type(set.key) == "number" and C_Item and C_Item.GetItemSetInfo then
        local ok, name = pcall(C_Item.GetItemSetInfo, set.key)
        if ok and type(name) == "string" and not ns.Util.IsSecret(name) then return name end
    end
    return "?"
end

-- the whole set an item is in: DungeonJournal's lists have Forever's sets, AtlasLoot's classic's
function Sets.PieceIDs(itemID) return ns.DungeonJournal.SetPieces(itemID) or ns.AtlasLoot.SetPieces(itemID) end

-- kept, so their item data stays put between refreshes
local sourceless = {}

-- the pieces no addon gives a source for, from the set lists. itemID: any piece of the set. a piece the game puts in
-- another set is left out
function Sets.Sourceless(key, itemID, index)
    local list = {}
    for _, id in ipairs(Sets.PieceIDs(itemID) or {}) do
        if type(id) == "number" and not index.byKey[id] then
            local record = sourceless[id]
            if not record then
                record = {key = id, id = id, sources = {}, noSource = true}
                sourceless[id] = record
            end
            local info = ns.Items.Info(record)
            local own = Sets.KeyOf(info)
            if info.slot and (own == nil or own == key) then list[#list + 1] = record end
        end
    end
    return list
end

-- extra: pieces shown besides the set's own
function Sets.Summary(set, L, extra)
    local count = #set.pieces + (extra or 0)
    if set.total then return format(L["%d of %d pieces listed"], count, set.total) end
    return format(L["%d pieces listed"], count)
end

local cached
function Sets.All()
    if not cached then
        local index = ns.GetIndex()
        cached = index and Sets.Group(index.records, ns.Items.Info) or {}
    end
    return cached
end

function Sets.Invalidate() cached = nil end

-- regrouped as item data arrives
ns.Items.OnChange(Sets.Invalidate)

function Sets.For(record)
    local info = ns.Items.Info(record)
    local key = Sets.KeyOf(info)
    return key and Sets.All()[key] or nil
end
