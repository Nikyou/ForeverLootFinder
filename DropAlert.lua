-- never sends anything to other players
local _, ns = ...
local L = ns.L

local DropAlert = {}
ns.DropAlert = DropAlert

local DEDUPE_SECONDS = 5
local TOAST_SECONDS = 8

local isSecret = ns.Util.IsSecret

function DropAlert.ShouldAlert(seen, id, now)
    local last = seen[id]
    if last and now - last < DEDUPE_SECONDS then return false end
    seen[id] = now
    return true
end

function DropAlert.LinksIn(text)
    local links = {}
    if type(text) ~= "string" or isSecret(text) then return links end
    for link in text:gmatch("|c%x+|Hitem:.-|h.-|h|r") do links[#links + 1] = link end
    if #links == 0 then for link in text:gmatch("|Hitem:.-|h.-|h") do links[#links + 1] = link end end
    return links
end

local seen = {}
DropAlert.skippedSecret = 0

local toast
local function createToast()
    local W = ns.Widgets
    toast = CreateFrame("Button", "ForeverLootFinderToast", UIParent, "BackdropTemplate")
    toast:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    toast:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    toast:SetSize(340, 56)
    toast:SetPoint("TOP", 0, -90)
    toast:SetFrameStrata("HIGH")
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(36, 36)
    toast.icon:SetPoint("LEFT", 10, 0)
    toast.title = W.Label(toast, "", 13, ns.Style.ACCENT)
    toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 8, 0)
    toast.text = W.Label(toast, "")
    toast.text:SetPoint("BOTTOMLEFT", toast.icon, "BOTTOMRIGHT", 8, 0)
    toast.text:SetPoint("RIGHT", -10, 0)
    toast.text:SetWordWrap(false)
    toast:SetScript("OnClick", function(self) self:Hide() end)
    toast:Hide()
end

local function showToast(link, tier, id)
    if not toast then createToast() end
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    toast.icon:SetTexture((not isSecret(icon) and icon) or 134400)
    toast.title:SetText(
      format(L["Favourite dropped (%s)"], ns.Favourites.TierColor(tier) .. ns.Favourites.TierLabel(tier) .. "|r"))
    toast.text:SetText(link)
    toast:Show()
    toast.serial = (toast.serial or 0) + 1
    local serial = toast.serial
    C_Timer.After(TOAST_SECONDS, function() if toast.serial == serial then toast:Hide() end end)
end

function DropAlert.Check(link)
    local id = ns.Util.ItemIDFromLink(link)
    if not id then return end
    local tier = ns.Favourites.Get(id)
    if not tier then return end
    if not DropAlert.ShouldAlert(seen, id, GetTime()) then return end
    local settings = ns.addon.db.profile.dropAlert
    if settings.toast then showToast(link, tier, id) end
    if settings.chat then ns.Print(format(L["Favourite dropped: %s (%s)"], link, ns.Favourites.TierLabel(tier))) end
    if settings.sound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master") end
end

function DropAlert.OnLootReady()
    local ok, count = pcall(GetNumLootItems)
    if not ok or isSecret(count) or type(count) ~= "number" then return end
    for slot = 1, count do
        local linkOk, link = pcall(GetLootSlotLink, slot)
        if linkOk then DropAlert.Check(link) end
    end
end

function DropAlert.OnLootRoll(rollID)
    if isSecret(rollID) or rollID == nil then return end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if ok then DropAlert.Check(link) end
end

-- chat text can be secret inside instances
function DropAlert.OnChatLoot(text)
    if isSecret(text) then
        DropAlert.skippedSecret = DropAlert.skippedSecret + 1
        return
    end
    for _, link in ipairs(DropAlert.LinksIn(text)) do DropAlert.Check(link) end
end
