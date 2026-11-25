-- one card per item set with pieces the character can use, like the Dungeon Journal's tier pages. the game has no
-- piece list for a set: DungeonJournal's and AtlasLoot's set lists add the pieces no addon gives a source for, marked.
-- the "of N" is the game's own count. the filters choose the sets, a chosen set shows all its pieces
local _, ns = ...
local L = ns.L

local SLOT_ORDER = {}
for i, slot in ipairs(ns.Index.SLOTS) do SLOT_ORDER[slot] = i end

local function setOf(row) return row and row.info and ns.Sets.KeyOf(row.info) end

-- whether an item is a set piece is only known once its data is in, so every item the character might use and that
-- hasn't loaded is asked for too, after the pieces shown
local maybePieces = {}

-- the filters pick the sets, but a set shows whole: what an item is like (binding, quality, stats, price, Pawn, owned,
-- search) and the level limit don't take a piece out. who can use it and where it comes from still do
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
    wipe(maybePieces)
    for _, row in ipairs(shown) do
        if row.status == "unknown" and not row.info.loaded and row.record.id > 0 then
            maybePieces[#maybePieces + 1] = row.record
        end
    end
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
    local records, pieceOf = {}, {}
    for _, record in ipairs(index.records) do
        local key = ns.Sets.KeyOf(ns.Items.Info(record))
        if key and picked[key] then
            records[#records + 1] = record
            if record.id > 0 then pieceOf[key] = pieceOf[key] or record.id end
        end
    end
    -- the search box and the level limit are read from the context, not the filters
    local looseCtx = setmetatable({search = "", maxLevel = false}, {__index = ctx})
    local whole = ns.Filter.Run(records, ns.Items.Info, wholeSets(ns.Filters()), looseCtx)
    -- a piece the filters would hide stays, greyed (red when it's only the level), and its tooltip says why
    local filters = ns.Filters()
    local noLevel = setmetatable({maxLevel = false}, {__index = ctx})
    for _, row in ipairs(whole) do
        if not passed[row.record] then
            local status, _, why = ns.Filter.Evaluate(row.record, row.info, filters, ctx)
            if status == "fail" then
                local without = ns.Filter.Evaluate(row.record, row.info, filters, noLevel)
                row.filteredOut = without ~= "fail" and "level" or why
            end
        end
    end
    -- the pieces no addon gives a source for: who can use one still counts, the rest of the filters can't tell
    for key, id in pairs(pieceOf) do
        for _, record in ipairs(ns.Sets.Sourceless(key, id, index)) do
            local info = ns.Items.Info(record)
            if not ctx.hidden[record.key] and (ctx.showMissing or not info.missing) and not (ctx.slot and info.slot ~= ctx.slot)
              and not ns.Filter.ForOtherClass(record, info, ctx) and not ns.Filter.ForOtherRace(info, ctx) then
                local status = info.missing and "missing" or (info.loaded and info.tooltipLoaded and "pass" or "unknown")
                local row = {record = record, info = info, status = status, sources = record.sources}
                if ctx.maxLevel and info.minLevel and info.minLevel > ctx.maxLevel then row.filteredOut = "level" end
                whole[#whole + 1] = row
            end
        end
    end
    -- in equipment order within a slot's block too
    table.sort(whole, function(a, b)
        local sa, sb = SLOT_ORDER[a.info.slot] or 99, SLOT_ORDER[b.info.slot] or 99
        if sa ~= sb then return sa < sb end
        return (a.info.name or "") < (b.info.name or "")
    end)
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
        list[#list + 1] = {title = card.title, info = info, groups = card.list, inline = true}
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
    -- a header per slot, the slots side by side
    group = function(_, _, row)
        local slot = row.info.slot
        return slot, ns.Labels.Slot(slot), SLOT_ORDER[slot] or 99
    end,
    onSource = onSource,
    entries = entries,
    rows = rows,
    alsoLoad = function() return maybePieces end,
    emptyHint = function() return L["No set pieces match the filters."] end,
})
