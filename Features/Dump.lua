-- /flf dump: raw data in a copy box, for bug reports
local _, ns = ...
local L = ns.L

local Dump = {}
ns.Dump = Dump

local LOAD_TIMEOUT = 60

local function show(title, lines)
    ns.Options:ShowDialog({
        instance = "dump",
        title = title,
        message = L["Ctrl+A, then Ctrl+C to copy."],
        input = {text = table.concat(lines, "\n"), readOnly = true},
        buttons = {{label = L["Close"]}},
    })
end

local function header(lines, kind)
    local version, build = GetBuildInfo()
    lines[#lines + 1] = format("# %s %s dump, %s, client %s (%s), %s", ns.TITLE, kind, GetLocale(), tostring(version),
                               tostring(build), date("%Y-%m-%d"))
end

local function sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function statsText(id)
    local ok, raw = pcall(C_Item.GetItemStats, "item:" .. id)
    if not ok or type(raw) ~= "table" then return "" end
    local parts = {}
    for _, key in ipairs(sortedKeys(raw)) do parts[#parts + 1] = key .. "=" .. tostring(raw[key]) end
    return table.concat(parts, ",")
end

function Dump.StatsText(index)
    local lines = {}
    header(lines, "stats")
    lines[#lines + 1] = "# id;equipLoc;classID;subclassID;loaded;stats"
    local records = {}
    for _, record in ipairs(index.records) do if record.id and record.id > 0 then records[#records + 1] = record end end
    table.sort(records, function(a, b) return a.id < b.id end)
    local unmapped = {}
    for _, record in ipairs(records) do
        local info = ns.Items.Info(record)
        local _, _, _, equipLoc, _, classID, subclassID = ns.Util.SafeCall(C_Item.GetItemInfoInstant, record.id)
        lines[#lines + 1] = format("%d;%s;%s;%s;%s;%s", record.id, tostring(equipLoc or ""), tostring(classID or ""),
                                   tostring(subclassID or ""), info.loaded and "1" or "0", statsText(record.id))
        for key in pairs(info.otherStats or {}) do unmapped[key] = (unmapped[key] or 0) + 1 end
    end
    lines[#lines + 1] = "# client keys with no FLF stat (shown under Other):"
    for _, key in ipairs(sortedKeys(unmapped)) do lines[#lines + 1] = format("#   %s x%d", key, unmapped[key]) end
    return lines
end

function Dump.Stats()
    local index = ns.GetIndex()
    ns.Items.Request(index.records)
    ns.Print(L["Loading items; the dump opens when done."])
    local started = GetTime()
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        local done, total = ns.Items.Progress()
        if done >= total or GetTime() - started > LOAD_TIMEOUT then
            ticker:Cancel()
            -- a rebuild while waiting made a new one
            local current = ns.GetIndex()
            if current then ns.Guard(function() show(L["Stat dump"], Dump.StatsText(current)) end) end
        end
    end)
end

local function statusLine(status)
    return format("%s: state %s, read in %.0f ms%s", status.name, status.state, status.ms or 0,
                  status.error and (", error: " .. status.error) or "")
end

function Dump.FDJText(index, data)
    local lines = {}
    header(lines, "fdj")
    local add = function(text) lines[#lines + 1] = text end
    add(format("FDJ status: %s, used: %s, version: %s", ns.DungeonJournal.Status(), tostring(ns.DungeonJournal.Enabled()),
               tostring(ns.DungeonJournal.Version())))
    add(format("FDJ source line on item tooltips: %s", tostring(ns.DungeonJournal.ItemSourceLineOn())))
    add(format("dungeons: %d, items (one per ID): %d, drop chance field found: %s (keys checked: %s)", #data.dungeons,
               #index.records, tostring(index.hasChance), table.concat(ns.DungeonJournal.CHANCE_KEYS, ", ")))
    local kinds = {}
    for _, kind in ipairs(sortedKeys(data.counts)) do kinds[#kinds + 1] = kind .. "=" .. data.counts[kind] end
    add("rows by source: " .. table.concat(kinds, ", "))
    if data.error then add("read error: " .. tostring(data.error)) end

    add("")
    add("## dungeons and bosses")
    for _, dungeon in ipairs(data.dungeons) do
        local bosses = {}
        for _, boss in ipairs(dungeon.bosses) do bosses[#bosses + 1] = format("%s[%s]", boss.name, boss.kind) end
        add(format("%d %s (%s)%s: %s", dungeon.order, dungeon.key, tostring(dungeon.levelText),
                   dungeon.incomplete and " incomplete" or "", table.concat(bosses, ", ")))
    end

    add("")
    add("## skipped")
    for _, entry in ipairs(data.skipped) do
        add(format("%s / %s: %s (%d rows)", tostring(entry.dungeon), tostring(entry.boss), entry.reason, entry.rows))
    end

    add("")
    add("## unknown fields")
    for _, key in ipairs(sortedKeys(data.unknown)) do add(format("%s x%d", key, data.unknown[key])) end

    local idZero, disagree, notEquip, failed = {}, {}, {}, {}
    for _, record in ipairs(index.records) do
        local info = ns.Items.Info(record)
        if not record.id or record.id <= 0 then
            idZero[#idZero + 1] = format("%s (%s)", record.name or "?", tostring(record.slotText))
        else
            local textSlot = ns.Index.FromSlotText(record.slotText)
            if textSlot and info.slot and textSlot ~= info.slot then
                disagree[#disagree + 1] = format("%d %s: FDJ \"%s\", client %s", record.id, record.name or "?", record.slotText,
                                                 tostring(select(4, ns.Util.SafeCall(C_Item.GetItemInfoInstant, record.id))))
            elseif textSlot and not info.slot then
                notEquip[#notEquip + 1] = format("%d %s: FDJ \"%s\", client %s", record.id, record.name or "?", record.slotText,
                                                 tostring(select(4, ns.Util.SafeCall(C_Item.GetItemInfoInstant, record.id))))
            end
            if info.failed then failed[#failed + 1] = format("%d %s", record.id, record.name or "?") end
        end
    end
    add("")
    add(format("## items without an ID (%d)", #idZero))
    for _, text in ipairs(idZero) do add(text) end
    add("")
    add(format("## slot text vs client (%d)", #disagree))
    for _, text in ipairs(disagree) do add(text) end
    add(format("## FDJ slot says equippable, the client doesn't (%d)", #notEquip))
    for _, text in ipairs(notEquip) do add(text) end
    add(format("## not on this server (%d)", #failed))
    for _, text in ipairs(failed) do add(text) end

    local ctx = ns.FilterContext()
    local hidden = {}
    for _, record in ipairs(index.records) do
        local info = ns.Items.Info(record)
        if info.slot then
            local reason = ns.Filter.ForOtherClass(record, info, ctx)
            reason = reason and ("class: " .. reason) or (ns.Filter.ForOtherRace(info, ctx) and "race: race list")
            if reason then
                local extra = info.classes and (" [" .. table.concat(info.classes, ", ") .. "]") or ""
                if info.races then extra = extra .. " [" .. table.concat(info.races, ", ") .. "]" end
                hidden[#hidden + 1] = format("%s %s: %s%s", tostring(record.id), info.name or record.name or "?", reason, extra)
            end
        end
    end
    add("")
    add(format("## hidden for %s (%d)", tostring(ctx.class), #hidden))
    for _, text in ipairs(hidden) do add(text) end

    add("")
    local done, total = ns.Items.Progress()
    add(format("item data loaded: %d / %d", done, total))
    local waiting = ns.Items.Waiting()
    if #waiting > 0 then
        local shown = {}
        for i = 1, math.min(#waiting, 60) do shown[i] = tostring(waiting[i]) end
        add(format("asked for, no answer yet (%d): %s%s", #waiting, table.concat(shown, ", "), #waiting > 60 and ", ..." or ""))
    end
    add(Dump.PawnLine())
    add(format("loot chat lines skipped as secret: %d", ns.DropAlert.skippedSecret))
    return lines
end

function Dump.FDJ()
    if not ns.DungeonJournal.Installed() then
        ns.Print(L["DungeonJournal isn't installed."])
        return
    end
    show(L["Dungeon Journal dump"], Dump.FDJText(ns.GetIndex(), ns.SourceData()))
end

-- the key names show whether QuestieDB still has "questRewards"
function Dump.QuestieText()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    header(lines, "questie")
    local Questie = ns.Questie
    add(format("Questie installed: %s, on: %s, state: %s",
               tostring(Questie.Installed()), tostring(Questie.Enabled()), Questie.State()))
    add(format("LibQuestieDB: %s", tostring(type(rawget(_G, "LibQuestieDB")) == "table")))
    add(statusLine(Questie.Status()))
    local stats = Questie.Stats()
    add(format("items in QuestieDB: %d, equippable: %d, quest rewards: %d, quests: %d, hidden quests skipped: %d, errors: %d",
               stats.items, stats.equippable, stats.rewards, stats.quests, stats.hidden, stats.errors))
    add(format("vendor sources: %d (%d items sold by more than 5), creature drop sources: %d (%d items dropped by more "
               .. "than 5), creatures read: %d; switches: quests %s, vendors %s, drops %s", stats.vendors, stats.manyVendors,
               stats.drops, stats.manyDrops, stats.npcs, tostring(Questie.KindEnabled("quests")),
               tostring(Questie.KindEnabled("vendors")), tostring(Questie.KindEnabled("drops"))))
    add(format("implausible creature drops skipped: %d (%d items left with no creature)", stats.implausible or 0,
               stats.implausibleItems or 0))
    add(format("world drops (creatures in %d+ zones): %d items", 4, stats.worldDrops or 0))
    if Questie.SodRuleOn() then
        add(format("SoD-only vendors and creatures (ids 200000-244999 unused by Forever quests) skipped: %d sources from %d "
                   .. "NPCs; SoD-range NPCs Forever's quests use: %d (%d sources kept)", stats.sodSkipped or 0,
                   stats.sodNpcs or 0, stats.sodRefs or 0, stats.sodKept or 0))
        local count = Questie.SodItems()
        add(format("SoD gear (ids 190000-244999) left with no Questie source: %d items", count or 0))
    else
        add("SoD-only vendors and creatures: not skipped (QuestieDB has no Quest.GetAllIds)")
    end
    for _, kind in ipairs({"Item", "Quest", "Npc"}) do
        local keys = Questie.Keys(kind)
        add(format("%s keys: %s", kind, keys and table.concat(keys, ", ") or "not found"))
    end
    add("")
    add("## samples")
    local index = ns.GetIndex()
    local shown = 0
    for _, record in ipairs(index and index.records or {}) do
        for _, source in ipairs(record.sources) do
            if source.kind == "zoneQuest" and shown < 25 then
                shown = shown + 1
                add(format("%d %s: quest %s \"%s\", req %s, level %s, zone %s (%s), races %s, classes %s", record.id,
                           record.name or "?", tostring(source.questID), source.questName or "?", tostring(source.reqLevel),
                           tostring(source.questLevel), tostring(source.zoneName), tostring(source.zoneKey),
                           tostring(source.raceMask), tostring(source.classMask)))
            end
        end
    end
    local merged = 0
    for _, record in ipairs(index and index.records or {}) do
        for _, source in ipairs(record.sources) do if source.kind == "quest" and source.zoneKey then merged = merged + 1 end end
    end
    add(format("dungeon quests matched with Questie: %d", merged))
    local kinds, tied, vendorSamples, dropSamples = {}, {}, {}, {}
    for _, record in ipairs(index and index.records or {}) do
        for _, source in ipairs(record.sources) do
            if source.provider == "questie" and (source.kind == "vendor" or source.kind == "npcDrop" or source.creature) then
                local kind = source.creature and "creature at a place" or source.kind
                kinds[kind] = (kinds[kind] or 0) + 1
                if source.creature then tied[source.dungeon] = (tied[source.dungeon] or 0) + 1 end
                local samples = source.kind == "vendor" and vendorSamples or dropSamples
                if #samples < 15 then
                    samples[#samples + 1] = format("%d %s: %s", record.id, record.name or "?",
                                                   ns.Util.StripCodes(ns.Tooltip.SourceText(source, index.dungeonByKey)))
                end
            end
        end
    end
    local kindList, placeList = {}, {}
    for _, kind in ipairs(sortedKeys(kinds)) do kindList[#kindList + 1] = kind .. " " .. kinds[kind] end
    for _, place in ipairs(sortedKeys(tied)) do placeList[#placeList + 1] = format("%s %d", place, tied[place]) end
    add("QuestieDB vendor and creature sources kept: " .. (#kindList > 0 and table.concat(kindList, ", ") or "none"))
    add("creature drops tied to places: " .. (#placeList > 0 and table.concat(placeList, ", ") or "none"))
    local areas = 0
    for _ in pairs(Questie.Areas()) do areas = areas + 1 end
    add(format("dungeon areas matched to FDJ dungeons by name: %d", areas))
    add("")
    add("## vendor samples")
    for _, text in ipairs(vendorSamples) do add(text) end
    add("## creature drop samples")
    for _, text in ipairs(dropSamples) do add(text) end
    add("## implausible creature drops skipped (samples): item: creature (id, levels), why")
    for _, text in ipairs(Questie.SkippedSamples()) do add(text) end
    add("## SoD-only NPCs skipped (most items first): id name: items, sells/drops. a Forever NPC here is a mistake")
    for _, info in ipairs(Questie.SodSkipped()) do
        add(format("%d %s: %d items, %s", info.id, info.name, info.items,
                   info.vendor and info.drop and "sells and drops" or info.vendor and "sells" or "drops"))
    end
    add("## SoD gear left with no Questie source (samples). a Forever item here is a mistake")
    local _, sodItems = Questie.SodItems()
    for _, text in ipairs(sodItems or {}) do add(text) end
    return lines
end

function Dump.CraftsText()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    header(lines, "crafts")
    local Crafts = ns.Crafts
    add(format("AtlasLoot installed: %s, on: %s, state: %s",
               tostring(Crafts.Installed()), tostring(Crafts.Enabled()), Crafts.State()))
    add(statusLine(Crafts.Status()))
    add(statusLine(ns.AtlasLootLists.Status()))
    local stats = Crafts.Stats()
    add(format("sections: %d, craft spells: %d, equippable results: %d, spells AtlasLoot has no data for: %d",
               stats.sections, stats.spells, stats.equippable, stats.missing))
    local loot = ns.AtlasLootLists.Stats()
    add(format("AtlasLoot loot lists: state %s, modules %d, places %d (%d matched to FDJ dungeons), items %d, "
               .. "set lists skipped %d", ns.AtlasLootLists.State(), loot.modules, loot.places, loot.matched, loot.items,
               loot.skippedSets))
    local shared = 0
    for _, record in ipairs(ns.GetIndex() and ns.GetIndex().records or {}) do
        for _, source in ipairs(record.sources) do if source.chanceFrom then shared = shared + 1 end end
    end
    add(format("drop chances: %d from AtlasLoot, %d of them passed to the Dungeon Journal's entry for the same boss",
               loot.chances or 0, shared))
    local priority = ns.Priority()
    add(format("priority: drops %s; quests %s; crafts %s", table.concat(priority.drops, " > "),
               table.concat(priority.quests, " > "), table.concat(priority.crafts, " > ")))
    local perKind, perPlace = {}, {}
    local idx = ns.GetIndex()
    for _, record in ipairs(idx and idx.records or {}) do
        for _, source in ipairs(record.sources) do
            if source.provider == "atlasloot" and source.kind ~= "craft" then
                perKind[source.kind] = (perKind[source.kind] or 0) + 1
                if source.dungeon then perPlace[source.dungeon] = (perPlace[source.dungeon] or 0) + 1 end
            end
        end
    end
    local kinds = {}
    for kind, count in pairs(perKind) do kinds[#kinds + 1] = kind .. " " .. count end
    table.sort(kinds)
    add("AtlasLoot sources kept after overlaps: " .. (#kinds > 0 and table.concat(kinds, ", ") or "none"))
    local places = {}
    for place, count in pairs(perPlace) do places[#places + 1] = format("%s %d", ns.DungeonJournal.DungeonName(place), count) end
    table.sort(places)
    add("by place: " .. table.concat(places, ", "))
    local listed, noLevel = 0, {}
    for _, record in ipairs(idx and idx.records or {}) do
        for _, source in ipairs(record.sources) do
            if source.provider == "atlasloot" and (source.kind == "reputation" or source.kind == "pvp"
                                                    or source.kind == "event" or source.kind == "world") then
                listed = listed + 1
                local info = ns.Items.Info(record)
                local estimate = ns.Filter.EstimatedLevel(source, info)
                if estimate then
                    noLevel[#noLevel + 1] = format("%d %s (%s, item level %d): counts as level %d", record.id,
                                                   info.name or record.name or "?", source.kind, info.ilvl, estimate)
                end
                break
            end
        end
    end
    add(format("reputation, PvP, event and world drop items: %d; loaded with no required level: %d (held to item level - %d)",
               listed, #noLevel, ns.Filter.ILVL_MARGIN))
    table.sort(noLevel)
    for i = 1, math.min(#noLevel, 60) do add("  " .. noLevel[i]) end
    if #noLevel > 60 then add(format("  ... and %d more", #noLevel - 60)) end
    local learned = Crafts.LearnedProfessions()
    local names = {}
    for id, rank in pairs(learned or {}) do names[#names + 1] = format("%s %d", Crafts.Name(id), rank) end
    add("learned: " .. (learned and (#names > 0 and table.concat(names, ", ") or "none") or "unknown"))
    local perProfession = {}
    local index = ns.GetIndex()
    for _, record in ipairs(index and index.records or {}) do
        for _, source in ipairs(record.sources) do
            if source.kind == "craft" then
                local key = source.professionName or tostring(source.profession)
                perProfession[key] = (perProfession[key] or 0) + 1
            end
        end
    end
    add("")
    add("## crafted items per profession")
    for name, count in pairs(perProfession) do add(format("%s: %d", name, count)) end
    local saved = ns.addon.db.global.tradeSkills

    add("")
    add("## from profession windows")
    for profession, items in pairs(saved) do
        local count = 0
        for _ in pairs(items) do count = count + 1 end
        add(format("%s: %d", Crafts.Name(profession), count))
    end
    return lines
end

-- lists every item: the high IDs (Forever's own and SoD's) are the interesting part
local ID_RANGES = {{25000, "<25k"}, {190000, "25k-190k"}, {240000, "190k-240k"}, {260000, "240k-260k"},
                   {math.huge, "260k+"}}

local function idRange(id)
    for _, range in ipairs(ID_RANGES) do if id < range[1] then return range[2] end end
end

function Dump.PawnLine()
    local Pawn = ns.Pawn
    local timing = Pawn.timing
    local scales = {}
    for _, entry in ipairs(Pawn.ScalesInUse()) do
        scales[#scales + 1] = format("%s (%s, %d values)", entry.scale, tostring(entry.signature), entry.values)
    end
    return format("Pawn: ready %s, queue %d, values computed %d in %.1f ms (longest frame %.1f ms), last full pass %s ms, "
                  .. "%d values from the cache; scales in use: %s", tostring(Pawn.IsReady()), Pawn.QueueLength(),
                  timing.count, timing.ms, timing.longestFrame, timing.lastPassMs and format("%.0f", timing.lastPassMs) or "-",
                  timing.fromCache, #scales > 0 and table.concat(scales, ", ") or "none")
end

local function ago(stamp)
    if type(stamp) ~= "number" then return "never" end
    local hours = (time() - stamp) / 3600
    return format("%s (%.1f h ago)", date("%Y-%m-%d %H:%M", stamp), hours)
end

function Dump.LoadLines()
    local lines = {}
    local t = ns.Items.timing
    local queue = ns.Items.QueueInfo()
    local finished = t.loadDone and t.loadStarted and format("in %.1f s", t.loadDone - t.loadStarted) or "not yet"
    lines[#lines + 1] = format("loading: %d requests (%.0f ms); %d infos built (%.0f ms, tooltips %.0f ms), %d quick ones "
                               .. "without the tooltip; %d build slices, longest %.1f ms; %d left to build; %d redraws; "
                               .. "finished %s", t.requests, t.requestMs, t.builds, t.buildMs, t.tooltipMs, t.quick, t.slices,
                               t.longestSlice, queue.toBuild, t.redraws, finished)
    lines[#lines + 1] = format("answers for finished items, ignored: %d; asked and waiting: %d; to fetch again: %d",
                               t.ignored or 0, queue.inFlight or 0, queue.refetches or 0)
    local cache = ns.Cache.Summary()
    if not cache then
        lines[#lines + 1] = "cache: not loaded"
    else
        local s = ns.Cache.stats
        lines[#lines + 1] = format("cache: %d items, %d sets, %d the server didn't give last time, about %.0f KB; client %s, "
                                   .. "%s; created %s, last saved %s; started over at login: %s", cache.items, cache.sets,
                                   cache.unavailable or 0, cache.bytes / 1024,
                                   tostring(cache.build), tostring(cache.locale), ago(cache.createdAt), ago(cache.savedAt),
                                   s.reset or "no")
        lines[#lines + 1] = format("cache this session: %d hits, %d misses, %d new, %d changed, %d removed (not on the "
                                   .. "server), %d pruned", s.hits, s.misses, s.written, s.changed, s.removed, s.pruned)
        for _, entry in ipairs(cache.scales) do
            lines[#lines + 1] = format("cache Pawn %s: %d values, weights %s", tostring(entry.scale), entry.values,
                                       tostring(entry.sig))
        end
    end
    lines[#lines + 1] = Dump.PawnLine()
    return lines
end

function Dump.ItemsText(index)
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    header(lines, "items")
    local Items = ns.Items
    local done, total = Items.Progress()
    local queue = Items.QueueInfo()
    add(format("item data loaded: %d / %d; loading started %s, paused %s, queued %d, urgent %d", done, total,
               tostring(queue.started), tostring(queue.paused), queue.queued, queue.urgent))
    for _, line in ipairs(Dump.LoadLines()) do add(line) end
    local ranked, reputation = {}, {}
    for _, info in pairs(Items.Tables().info) do
        if info.pvpRank then ranked[#ranked + 1] = info.name or "?" end
        if info.reqReputation then reputation[#reputation + 1] = info.name or "?" end
    end
    table.sort(ranked)
    table.sort(reputation)
    add(format("from tooltips: needs a PvP rank %d (%s); needs a reputation %d (%s)", #ranked,
               table.concat(ranked, ", ", 1, math.min(#ranked, 5)), #reputation,
               table.concat(reputation, ", ", 1, math.min(#reputation, 5))))
    add("states: loaded; failed = the server said it doesn't exist; noanswer = asked 3 times, no answer; "
        .. "waiting = asked, still in time; queued = not asked yet")
    local byState, byProvider, list, seenIDs = {}, {}, {}, {}
    local byRange, hidden = {}, {}
    for _, range in ipairs(ID_RANGES) do byRange[range[2]] = {} end
    for _, record in ipairs(index.records) do
        local id = record.id
        if id and id > 0 and not seenIDs[id] then
            seenIDs[id] = true
            local loadState, tries = Items.LoadState(id)
            byState[loadState] = (byState[loadState] or 0) + 1
            local range = byRange[idRange(id)]
            range[loadState] = (range[loadState] or 0) + 1
            if loadState ~= "loaded" then
                local providers, kinds = {}, {}
                for _, source in ipairs(record.sources) do
                    local provider = source.provider or "?"
                    if not providers[provider] then
                        providers[provider] = true
                        providers[#providers + 1] = provider
                    end
                    if not kinds[source.kind or "?"] then
                        kinds[source.kind or "?"] = true
                        kinds[#kinds + 1] = source.kind or "?"
                    end
                end
                table.sort(providers)
                local providerText = table.concat(providers, "+")
                local key = loadState .. " " .. providerText
                byProvider[key] = (byProvider[key] or 0) + 1
                range[key] = (range[key] or 0) + 1
                if Items.Info(record).missing then hidden[providerText] = (hidden[providerText] or 0) + 1 end
                local ok, itemID, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, id)
                local client = ok and itemID and (equipLoc ~= "" and equipLoc or "not equippable") or "not in the client"
                list[#list + 1] = {id = id, text = format("%d;%s;%s;%s;%s;%s;%s", id, loadState, tostring(tries or ""),
                                                           client, providerText, table.concat(kinds, "+"),
                                                           record.name or "?")}
            end
        end
    end
    local states = {}
    for _, key in ipairs(sortedKeys(byState)) do states[#states + 1] = key .. " " .. byState[key] end
    add("by state: " .. table.concat(states, ", "))
    add("")
    add("## not loaded, by state and addon")
    for _, key in ipairs(sortedKeys(byProvider)) do add(format("%s: %d", key, byProvider[key])) end
    add("")
    local hiddenTotal, hiddenList = 0, {}
    for _, key in ipairs(sortedKeys(hidden)) do
        hiddenTotal = hiddenTotal + hidden[key]
        hiddenList[#hiddenList + 1] = format("%s %d", key, hidden[key])
    end
    add(format("## not on this server (failed or noanswer): %d, %s in the lists; by addon: %s", hiddenTotal,
               ns.addon.db.profile.showMissing and "shown greyed" or "hidden",
               #hiddenList > 0 and table.concat(hiddenList, ", ") or "none"))
    add("")
    add("## by ID range: every state, then not loaded by state and addon")
    for _, info in ipairs(ID_RANGES) do
        local counts, states, detail = byRange[info[2]], {}, {}
        for _, key in ipairs(sortedKeys(counts)) do
            local target = key:find(" ", 1, true) and detail or states
            target[#target + 1] = key .. " " .. counts[key]
        end
        if #states > 0 then
            add(format("%s: %s", info[2], table.concat(states, ", ")))
            if #detail > 0 then add("    " .. table.concat(detail, ", ")) end
        end
    end
    add("")
    add(format("## not loaded (%d): id;state;requests;client equip slot;addons;kinds;name", #list))
    table.sort(list, function(a, b) return a.id < b.id end)
    for _, entry in ipairs(list) do add(entry.text) end
    return lines
end

function Dump.AuctionatorLines()
    local AH = ns.Auctionator
    local status = AH.Status()
    local lines = {format("auctionator: installed %s, on %s, state %s, API calls %d, errors %d%s", tostring(AH.Installed()),
                          tostring(AH.Enabled()), status.state, status.counts.calls, status.counts.errors,
                          status.error and (", last error: " .. status.error) or "")}
    if AH.Active() then
        local index = ns.GetIndex()
        local c = AH.Coverage(index and index.records or {}, ns.Items.Info)
        lines[#lines + 1] = format("auction prices: %d items, %d can be sold (not bind on pickup), %d with a price; bind on "
                                   .. "equip %d, %d with a price; old (over %d days) %d, not exact %d; prices cached %d",
                                   c.items, c.sellable, c.priced, c.boe, c.pricedBoe, AH.OLD_DAYS, c.old, c.inexact,
                                   status.counts.cached)
        lines[#lines + 1] = format("auctionator API: search %s, shopping list %s, update callback %s, auction house open %s",
                                   tostring(AH.Has("MultiSearchExact")), tostring(AH.CanAddToList()),
                                   tostring(AH.Has("RegisterForDBUpdate")), tostring(AH.AuctionHouseOpen()))
    end
    return lines
end

function Dump.StatusText()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    header(lines, "status")
    local source = ns.SourceData()
    local fdjError = source and source.error and (", error: " .. tostring(source.error)) or ""
    local index = ns.indexStats
    add(format("fdj: state %s%s, read %d times, last read in %.0f ms%s", ns.DungeonJournal.Status(),
               ns.DungeonJournal.Enabled() and "" or " (off)", index.fdjReads, index.fdjMs, fdjError))
    for _, provider in ipairs({ns.Questie, ns.Crafts, ns.AtlasLootLists}) do add(statusLine(provider.Status())) end
    for _, provider in ipairs({ns.ATT, ns.ForeverDB, ns.Attune, ns.SilverDragon}) do
        local counts = {}
        for _, key in ipairs(sortedKeys(provider.Stats())) do
            if key ~= "ms" then counts[#counts + 1] = key .. "=" .. tostring(provider.Stats()[key]) end
        end
        add(statusLine(provider.Status()) .. (#counts > 0 and ("; " .. table.concat(counts, ", ")) or ""))
    end
    add(format("index: built %d times, last in %.0f ms, %.0f ms in total", index.builds, index.lastMs, index.ms))
    -- creature drops tied to a place (by boss creature, name, instance, zones, no spawn), lines merged into a list's
    local merged = {}
    for _, key in ipairs(sortedKeys(index.merged or {})) do merged[#merged + 1] = key .. " " .. index.merged[key] end
    add("merged: " .. (#merged > 0 and table.concat(merged, ", ") or "none"))
    add(format("quest lines Questie hides, left out: %d", index.hiddenQuests or 0))
    local named, holidays = ns.Holidays.Named()
    add(format("holidays: calendar %s, %d months read, %d of %d named by the game", ns.Holidays.stats.state,
               ns.Holidays.stats.months, named, holidays))
    -- after a full collection: what's kept, not garbage waiting for it
    local update, usage = rawget(_G, "UpdateAddOnMemoryUsage"), rawget(_G, "GetAddOnMemoryUsage")
    if update and usage then
        local before = collectgarbage("count")
        collectgarbage("collect")
        ns.Util.SafeCall(update)
        local parts = {}
        for _, name in ipairs({"ForeverLootFinder", "ForeverDB", "ForeverDB_Locales", "AllTheThings", "QuestieDB", "Questie",
                               "AtlasLootClassic"}) do
            local kb = ns.Util.SafeCall(usage, name)
            if type(kb) == "number" and kb > 0 then parts[#parts + 1] = format("%s %.1f MB", name, kb / 1024) end
        end
        add(format("memory: %s; all addons %.0f MB, %.0f MB of it garbage", table.concat(parts, ", "),
                   collectgarbage("count") / 1024, (before - collectgarbage("count")) / 1024))
    end
    -- what holds it, roughly. shared tables count once, for the part listed first
    local seen, sizes = {}, {}
    local function measure(label, value)
        local bytes = ns.Util.SizeOf(value, seen)
        if bytes >= 51200 then sizes[#sizes + 1] = format("%s %.1f", label, bytes / 1048576) end
    end
    measure("questie", ns.Questie.Tables())
    measure("foreverdb", ns.ForeverDB.Entries())
    measure("att", ns.ATT.Entries())
    measure("atlasloot", ns.AtlasLootLists.Entries())
    measure("crafts", ns.Crafts.Entries())
    measure("attune", ns.Attune.Entries())
    measure("silverdragon", ns.SilverDragon.Entries())
    measure("fdj", ns.SourceData())
    -- after the addons': its sources point at their entries
    measure("index", ns.GetIndex())
    measure("item data", ns.Items.Tables())
    measure("pawn", ns.Pawn.Tables())
    measure("cache file", rawget(_G, "ForeverLootFinderCache"))
    measure("settings file", rawget(_G, "ForeverLootFinderDB"))
    add("memory held, estimated MB: " .. table.concat(sizes, ", "))
    for _, line in ipairs(Dump.AuctionatorLines()) do add(line) end
    for _, line in ipairs(ns.Waypoints.DumpLines()) do add(line) end
    local errors = ns.Errors()
    add("")
    add(format("## errors caught (%d)", #errors))
    for _, entry in ipairs(errors) do
        add(format("x%d %s", entry.count, entry.message))
        if entry.stack and entry.stack ~= "" then
            for line in entry.stack:gmatch("[^\n]+") do add("    " .. line) end
        end
    end
    return lines
end

-- not stats, it waits for the item data
function Dump.AllText(index)
    local lines = {}
    local function append(part)
        if #lines > 0 then lines[#lines + 1] = "" end
        for _, line in ipairs(part) do lines[#lines + 1] = line end
    end
    append(Dump.StatusText())
    append(Dump.FDJText(index, ns.SourceData()))
    append(Dump.QuestieText())
    append(Dump.CraftsText())
    append(Dump.ItemsText(index))
    return lines
end

-- the selected slot's shown items without a Pawn value, and where each is stuck
function Dump.PawnText()
    local lines = {}
    header(lines, "pawn")
    lines[#lines + 1] = Dump.PawnLine()
    local scale = ns.ActiveScale()
    local slot = ns.Filters().slot
    local q = ns.Items.QueueInfo()
    lines[#lines + 1] = format("active scale: %s; selected slot: %s", tostring(scale), tostring(slot))
    lines[#lines + 1] = format("item loader: asked and waiting %d, on-screen queue %d, refetch queue %d, other queue %d, "
                               .. "to build %d, paused %s, started %s, count fixes %d", q.inFlight or 0, q.urgent or 0,
                               q.refetches or 0, q.queued or 0, q.toBuild or 0, tostring(q.paused), tostring(q.started),
                               q.recounts or 0)
    if not scale then return lines end
    local ctx = ns.FilterContext()
    local filters = ns.Filters()
    local shown, missing, out = 0, 0, {}
    for _, record in ipairs(ns.MainWindow.RecordsOfSlot(slot)) do
        if record.id and record.id > 0 then
            local info = ns.Items.Info(record)
            local status = ns.Filter.Evaluate(record, info, filters, ctx, true, true)
            if ns.Filter.Shows(status, ctx) then
                shown = shown + 1
                if ns.Pawn.Known(record.id, scale) == nil then
                    missing = missing + 1
                    local d = ns.Items.Diagnose(record.id)
                    out[#out + 1] = format("%d;%s;%s;%s;%s;%s;%s;%s;%d;%s;%d;%s", record.id, tostring(info.name), status,
                                           tostring(info.loaded), tostring(info.fromCache == true), d.client, d.state,
                                           tostring(d.requested), d.refetches, tostring(d.waiting),
                                           ns.Pawn.ReadyTries(record.id), tostring(ns.Pawn.Waiting(record.id, scale)))
                end
            end
        end
    end
    lines[#lines + 1] = format("shown in the slot: %d, without a value: %d", shown, missing)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## no value yet: id;name;status;loaded;from cache;in client;load state;requested;refetches this view;"
                        .. "asked and waiting;Pawn tries on arrival;Pawn waits for it"
    for _, line in ipairs(out) do lines[#lines + 1] = line end
    return lines
end

function Dump.Start(arg)
    if arg == "stats" then
        Dump.Stats()
    elseif arg == "fdj" then
        Dump.FDJ()
    elseif arg == "questie" then
        show(L["Questie dump"], Dump.QuestieText())
    elseif arg == "crafts" then
        show(L["Crafted items dump"], Dump.CraftsText())
    elseif arg == "pawn" then
        show(L["Pawn dump"], Dump.PawnText())
    elseif arg == "status" then
        show(L["Status dump"], Dump.StatusText())
    elseif arg == "items" or arg == "all" then
        local index = ns.GetIndex()
        if arg == "items" then
            show(L["Item data dump"], Dump.ItemsText(index))
        else
            show(L["Full dump"], Dump.AllText(index))
        end
    else
        ns.Print(L["Usage: /flf dump stats, fdj, questie, crafts, items, pawn, status or all"])
    end
end
