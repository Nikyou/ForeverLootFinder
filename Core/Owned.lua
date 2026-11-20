-- Syndicator first, it also knows the bank from earlier sessions and the mail. our own scan is the fallback
local _, ns = ...
local StatMap, Util = ns.StatMap, ns.Util

local Owned = {}
ns.Owned = Owned

Owned.SLOT_INV = {
    HEAD = {1},
    NECK = {2},
    SHOULDER = {3},
    BACK = {15},
    CHEST = {5},
    WRIST = {9},
    HANDS = {10},
    WAIST = {6},
    LEGS = {7},
    FEET = {8},
    FINGER = {11, 12},
    TRINKET = {13, 14},
    ONEHAND = {16},
    MAINHAND = {16},
    TWOHAND = {16},
    OFFHAND = {17},
    RANGED = {18},
    RELIC = {18},
}
local MAIN_HAND, OFF_HAND = 16, 17
local FIRST_SLOT, LAST_SLOT = 1, 19
local BAGS = {0, 1, 2, 3, 4}
local DUAL_WIELD = {ROGUE = 10, WARRIOR = 20, HUNTER = 20}

local equipped = {} -- [id] = {invSlot, ...}
local inBags = {}
local fromSyndicator = {} -- [id] = "equipped", "bags", "bank" or "mail"
local ownedSet

local isSecret = Util.IsSecret
local idFromLink = Util.ItemIDFromLink

local function bank() return ns.addon.db.char.bank end

function Owned.ScanEquipped()
    ownedSet = nil
    wipe(equipped)
    for slot = FIRST_SLOT, LAST_SLOT do
        local id = idFromLink(GetInventoryItemLink("player", slot))
        if id then
            equipped[id] = equipped[id] or {}
            table.insert(equipped[id], slot)
        end
    end
end

local function scanContainers(list, into)
    for _, bag in ipairs(list) do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and type(slots) == "number" and not isSecret(slots) then
            for slot = 1, slots do
                local infoOk, item = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if infoOk and type(item) == "table" and not isSecret(item.itemID) and type(item.itemID) == "number" then
                    into[item.itemID] = true
                end
            end
        end
    end
end

function Owned.ScanBags()
    ownedSet = nil
    wipe(inBags)
    scanContainers(BAGS, inBags)
end

-- Forever has the tabbed bank, the bought character tabs are containers
local function bankContainers()
    local list = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum and Enum.BankType then
        local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Character)
        if ok and type(tabs) == "table" then
            for _, tab in ipairs(tabs) do
                if type(tab) == "table" and type(tab.ID) == "number" then list[#list + 1] = tab.ID end
            end
        end
    end
    if #list == 0 and Enum and Enum.BagIndex then
        for i = 1, 9 do
            local id = Enum.BagIndex["CharacterBankTab_" .. i]
            if id then list[#list + 1] = id end
        end
    end
    return list
end

function Owned.ScanBank()
    ownedSet = nil
    local saved = bank()
    wipe(saved.items)
    scanContainers(bankContainers(), saved.items)
    saved.seen = true
end

function Owned.Scan()
    Owned.ScanEquipped()
    Owned.ScanBags()
end

local function syndicator()
    local api = type(Syndicator) == "table" and Syndicator.API
    if type(api) ~= "table" or type(api.IsReady) ~= "function" or not api.IsReady() then return nil end
    if ns.addon.db.profile.syndicator == false then return nil end
    return api
end

function Owned.HasSyndicator() return syndicator() ~= nil end

local function addItems(list, where)
    for _, item in ipairs(type(list) == "table" and list or {}) do
        if type(item) == "table" and type(item.itemID) == "number" and not fromSyndicator[item.itemID] then
            fromSyndicator[item.itemID] = where
        end
    end
end

function Owned.ScanSyndicator()
    ownedSet = nil
    wipe(fromSyndicator)
    local api = syndicator()
    if not api then return end
    local ok, data = pcall(function() return api.GetByCharacterFullName(api.GetCurrentCharacter()) end)
    if not ok or type(data) ~= "table" then return end
    local slots = {}
    for _, item in pairs(type(data.equipped) == "table" and data.equipped or {}) do slots[#slots + 1] = item end
    addItems(slots, "equipped")
    for _, bag in ipairs(type(data.bags) == "table" and data.bags or {}) do addItems(bag, "bags") end
    for _, bag in ipairs(type(data.bank) == "table" and data.bank or {}) do addItems(bag, "bank") end
    addItems(data.mail, "mail")
end

function Owned.HookSyndicator()
    local registry = type(Syndicator) == "table" and Syndicator.CallbackRegistry
    if type(registry) ~= "table" or type(registry.RegisterCallback) ~= "function" then return end
    local function update(_, character)
        local api = syndicator()
        if character and api and character ~= api.GetCurrentCharacter() then return end
        Owned.ScanSyndicator()
        ns.FireChange("owned")
    end
    for _, event in ipairs({"Ready", "BagCacheUpdate", "MailCacheUpdate", "EquippedCacheUpdate"}) do
        pcall(registry.RegisterCallback, registry, event, function(...) ns.Guard(update, ...) end, Owned)
    end
    Owned.ScanSyndicator()
end

local function scanned(id)
    if equipped[id] then return "equipped" end
    if inBags[id] then return "bags" end
    if bank().items[id] then return "bank" end
    return nil
end

function Owned.Where(id)
    if not id then return nil end
    return fromSyndicator[id] or scanned(id)
end

-- shared until the next scan, don't change it
function Owned.Set()
    if ownedSet then return ownedSet end
    local set = {}
    for id in pairs(fromSyndicator) do set[id] = true end
    for id in pairs(equipped) do set[id] = true end
    for id in pairs(inBags) do set[id] = true end
    for id in pairs(bank().items) do set[id] = true end
    ownedSet = set
    return set
end

local function sumStats(list)
    local total = {}
    for _, entry in ipairs(list) do for key, value in pairs(entry.stats or {}) do total[key] = (total[key] or 0) + value end end
    return total
end

-- env is passed in so the tests can fake the client
function Owned.CompareWith(env, record, info)
    local result = {against = {}, deltas = {}}
    local id = record.id
    local where = id and id > 0 and env.owned(id) or nil
    if info.unique and where == "equipped" then
        result.unique = "equipped"
    elseif info.unique and where then
        result.unique = "owned"
    end
    local slots = Owned.SLOT_INV[info.slot]
    if not slots then return result end

    local mainHand = env.equipped(MAIN_HAND)
    local candidates
    if info.slot == "TWOHAND" then
        candidates = {MAIN_HAND}
        if not (mainHand and mainHand.twoHand) then candidates[2] = OFF_HAND end
    elseif info.slot == "OFFHAND" and mainHand and mainHand.twoHand then
        -- an off-hand alone can't be weighed against a two-hander, so it's no upgrade by itself. known, not pending:
        -- "Pawn upgrades only" would otherwise wait on it for good
        result.twoHandBlock = true
        result.upgradeKnown = true
        return result
    elseif (info.slot == "ONEHAND") and env.dualWield and not (mainHand and mainHand.twoHand) then
        candidates = {MAIN_HAND, OFF_HAND}
    else
        candidates = slots
    end

    -- rings, trinkets, dual wield: against the weaker slot
    local chosen
    if #candidates == 2 and info.slot ~= "TWOHAND" then
        local first, second = env.equipped(candidates[1]), env.equipped(candidates[2])
        if first and first.id == id then
            chosen = {candidates[2]}
        elseif second and second.id == id then
            chosen = {candidates[1]}
        elseif not first then
            chosen = {candidates[1]}
        elseif not second then
            chosen = {candidates[2]}
        else
            local va, vb = env.slotValue(candidates[1]), env.slotValue(candidates[2])
            if type(va) ~= "number" or type(vb) ~= "number" then va, vb = first.ilvl or 0, second.ilvl or 0 end
            chosen = {va <= vb and candidates[1] or candidates[2]}
        end
    else
        chosen = candidates
    end

    local items = {}
    for _, slot in ipairs(chosen) do
        local item = env.equipped(slot)
        if item then
            items[#items + 1] = item
            result.against[#result.against + 1] = {slot = slot, id = item.id, link = item.link}
        end
    end
    result.empty = #items == 0
    if info.stats then
        local before = sumStats(items)
        for key, value in pairs(info.stats) do result.deltas[key] = value - (before[key] or 0) end
        for key, value in pairs(before) do if info.stats[key] == nil then result.deltas[key] = -value end end
    end

    -- an equipped unique item is never an upgrade, whatever Pawn says
    if result.unique == "equipped" then
        result.upgrade, result.upgradeKnown = nil, true
        return result
    end
    local newValue = env.pawnValue and env.pawnValue(id)
    if type(newValue) ~= "number" then
        result.upgradeKnown = newValue == false
        return result
    end
    local base = 0
    for _, slot in ipairs(chosen) do
        if env.equipped(slot) then
            local value = env.slotValue(slot)
            if value == nil then return result end
            base = base + (value or 0)
        end
    end
    result.upgradeKnown = true
    if base <= 0 then
        result.upgrade = 1
        result.emptySlot = true
    else
        result.upgrade = (newValue - base) / base
    end
    return result
end

local equippedCache = {}
local envCache = {}
local function equippedItem(slot)
    local cached = equippedCache[slot]
    if cached ~= nil then return cached or nil end
    local link = GetInventoryItemLink("player", slot)
    local id = idFromLink(link)
    if not id then
        equippedCache[slot] = false
        return nil
    end
    local ok, raw = pcall(C_Item.GetItemStats, link)
    local stats = StatMap.Convert(ok and raw or nil)
    local _, _, _, ilvl, _, _, _, _, equipLoc = C_Item.GetItemInfo(link)
    local item = {id = id, link = link, stats = stats, ilvl = ilvl, twoHand = equipLoc == "INVTYPE_2HWEAPON"}
    if ilvl then equippedCache[slot] = item end -- only once it has loaded
    return item
end

function Owned.Invalidate()
    wipe(equippedCache)
    wipe(envCache)
    Owned.ScanEquipped()
end

function Owned.InvalidateEnv() wipe(envCache) end

local function noValue() return nil end

function Owned.Env(scale, class, level)
    local dualWield = DUAL_WIELD[class] ~= nil and (level or 1) >= DUAL_WIELD[class]
    local key = tostring(scale) .. "\001" .. tostring(dualWield)
    if envCache[key] then return envCache[key] end
    local Pawn = ns.Pawn
    local usePawn = scale and Pawn.IsReady() and Pawn.Exists(scale)
    local env = {
        equipped = equippedItem,
        owned = Owned.Where,
        pawnValue = usePawn and function(id) return Pawn.Lookup(id, scale) end or nil,
        slotValue = usePawn and function(slot) return Pawn.SlotValue(slot, scale) end or noValue,
        dualWield = dualWield,
    }
    -- don't keep an env made before Pawn was ready
    if usePawn or not scale then envCache[key] = env end
    return env
end

function Owned.Compare(record, info, scale, class, level)
    return Owned.CompareWith(Owned.Env(scale, class, level), record, info)
end

-- cached per record so a redraw only redoes what changed. not while Pawn is still working it out
local function resultsOf(env)
    local owned = Owned.Set()
    if env.resultsFor ~= owned then env.results, env.resultsFor = setmetatable({}, {__mode = "k"}), owned end
    return env.results
end

function Owned.Comparer(scale, class, level)
    local env = Owned.Env(scale, class, level)
    local results = resultsOf(env)
    return function(record, info)
        local cached = results[record]
        if cached and cached.info == info then return cached.result end
        local result = Owned.CompareWith(env, record, info)
        if result.upgradeKnown or not env.pawnValue then results[record] = {info = info, result = result} end
        return result
    end
end
