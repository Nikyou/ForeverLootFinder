-- one card per item set with pieces the character can use, like the Dungeon Journal's tier pages. the game has no
-- piece list for a set, so a card holds the pieces some addon lists; the "of N" is the game's own count. the filters
-- choose the sets, a chosen set shows all its pieces
local _, ns = ...
local L = ns.L

local SLOT_ORDER = {}
for i, slot in ipairs(ns.Index.SLOTS) do SLOT_ORDER[slot] = i end

local function setOf(row) return row and row.info and ns.Sets.KeyOf(row.info) end

-- the filters pick the sets, but a set shows whole: what an item is like (binding, quality, stats, price, Pawn, owned,
-- search) doesn't take a piece out. who can use it and where it comes from still do
local function wholeSets(state)
    local loose = {}
    for key, value in pairs(state) do loose[key] = value end
    loose.stats, loose.statMode = {}, "ANY"
    loose.bind, loose.minQuality = "ANY", 0
    loose.speed = {on = false}
    loose.setsOnly, loose.special = false, false
    loose.chance = {on = false}
    loose.price = {only = false, maxOn = false}
    loose.search, loose.hideOwned, loose.pawnUpgradesOnly = "", false, false
    return loose
end

local function rows(slot, ctx)
    local shown
    shown, ctx = ns.MainWindow.Rows(nil, slot, nil, ctx)
    local picked, any = {}, false
    for _, row in ipairs(shown) do
        local key = setOf(row)
        if key then
            picked[key] = true
            any = true
        end
    end
    if not any then return shown, ctx end
    local passed = {}
    for _, row in ipairs(shown) do passed[row.record] = true end
    local index = ns.GetIndex()
    local records = {}
    for _, record in ipairs(index.records) do
        local key = ns.Sets.KeyOf(ns.Items.Info(record))
        if key and picked[key] then records[#records + 1] = record end
    end
    -- the search box is read from the context, not the filters
    local looseCtx = setmetatable({search = ""}, {__index = ctx})
    local whole = ns.Filter.Run(records, ns.Items.Info, wholeSets(ns.Filters()), looseCtx)
    -- a piece the filters would hide stays, greyed, and its tooltip says which filter
    local filters = ns.Filters()
    for _, row in ipairs(whole) do
        if not passed[row.record] then
            local status, _, why = ns.Filter.Evaluate(row.record, row.info, filters, ctx)
            if status == "fail" then row.filteredOut = why end
        end
    end
    return ns.MainWindow.PrepareRows(whole, ctx), ctx
end

-- the set's lowest required level: a card for each step of levelling, in order
local function onSource(card, _, _, row)
    card.pieces = card.pieces or {}
    if card.pieces[row] then return end
    card.pieces[row] = true
    card.count = (card.count or 0) + 1
    card.total = card.total or row.info.setTotal
    card.setID = card.setID or row.info.setID
    local level = row.info.minLevel or 0
    if not card.level or level < card.level then card.level = level end
end

local function entries(_, order)
    table.sort(order, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return a.title < b.title
    end)
    local list = {}
    for _, card in ipairs(order) do
        local info = card.total and format(L["%d of %d pieces"], card.count or 0, card.total)
                       or format(L["%d items"], card.count or 0)
        if card.level and card.level > 1 then info = info .. "   " .. format(L["level %d"], card.level) end
        list[#list + 1] = {title = card.title, info = info, groups = card.list}
    end
    return list
end

ns.Cards.Tab({
    key = "sets",
    label = L["Sets"],
    -- every source of an item puts it on the same card, the card view counts it once
    accept = function(_, _, row) return setOf(row) ~= nil end,
    card = function(_, _, row)
        local key = setOf(row)
        local name = row.info.setName or ns.Sets.Name({key = key})
        return key, name, 0
    end,
    group = function(_, _, row)
        local slot = row.info.slot
        return slot, ns.Labels.Slot(slot), SLOT_ORDER[slot] or 99
    end,
    onSource = onSource,
    entries = entries,
    rows = rows,
    emptyHint = function() return L["No set pieces match the filters."] end,
})
