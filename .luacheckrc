-- without luacheck, Dev/tests/check_globals.lua still catches stray globals
std = "lua51"
max_line_length = 130
exclude_files = {"Libs/", "Dev/"}
-- event handlers and callbacks take arguments they don't need
unused_args = false

-- Bindings.xml and the key binding UI read these
globals = {
    "BINDING_HEADER_FOREVERLOOTFINDER",
    "BINDING_NAME_FOREVERLOOTFINDER_TOGGLE",
    "ForeverLootFinder_Toggle",
    "ForeverLootFinderCache", -- created at login when missing
}

read_globals = {
    -- same as .vscode/settings.json
    "issecretvalue", "TooltipDataProcessor", "TooltipUtil", "ItemRefTooltip", "UISpecialFrames", "SOUNDKIT",
    "ScrollingEdit_OnCursorChanged", "ScrollingEdit_OnUpdate", "CreateMinimalSliderFormatter",
    "MinimalSliderWithSteppersMixin", "ButtonFrameTemplate_HidePortrait", "PanelTemplates_SetNumTabs",
    "PanelTemplates_TabResize", "PanelTemplates_SetTab", "CreateScrollBoxListLinearView", "ScrollUtil",
    "ScrollBoxConstants", "CreateDataProvider", "MenuUtil", "MenuResponse", "Menu", "HandleModifiedItemClick",
    "DressUpItemLink", "ChatFrameUtil", "ChatEdit_InsertLink", "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE",
    "RETRIEVING_ITEM_INFO", "ForeverDungeonJournal_NS", "ForeverDungeonJournalDB", "ForeverDungeonJournalCharacterDB",
    "ForeverDungeonJournalFrame", "PawnIsReady", "PawnDoesScaleExist", "PawnGetAllScalesEx", "PawnGetScaleColor",
    "PawnGetScaleLocalizedName", "PawnGetItemData", "PawnGetSingleValueFromItem", "PawnGetItemDataForInventorySlot",
    "PawnGetAllStatValues", "PawnCommon", "PawnVersion",
    "ITEM_QUALITY_COLORS", "GameTooltip_ShowCompareItem", "RAID_CLASS_COLORS", "RunNextFrame",
    "ScrollFrame_OnScrollRangeChanged",
    -- the rest, from luac -l
    "BreakUpLargeNumbers", "C_AddOns", "C_Bank", "C_Container", "C_CreatureInfo", "C_Item", "C_Map", "C_QuestLog",
    "C_Reputation", "C_SkillInfo", "C_Timer", "C_TooltipInfo", "C_TradeSkillUI", "CreateColorFromHexString", "CreateFrame",
    "DropdownButtonMixin", "Enum", "GameTooltip", "GetBuildInfo", "GetInstanceInfo", "GetInventoryItemLink", "GetLocale",
    "GetLootRollItemLink", "GetLootSlotLink", "GetNumLootItems", "GetRealmName", "GetTime", "GRAY_FONT_COLOR",
    "HIGHLIGHT_FONT_COLOR", "IsInInstance", "IsModifiedClick", "IsShiftKeyDown", "LibStub", "NORMAL_FONT_COLOR",
    "PlaySound", "RED_FONT_COLOR", "Syndicator", "UIParent", "UnitClass", "UnitFactionGroup", "UnitLevel", "UnitName",
    "UnitRace", "date", "debugprofilestop", "debugstack", "format", "strtrim", "tinsert", "wipe",
}
