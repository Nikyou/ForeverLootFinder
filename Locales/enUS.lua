-- interface strings in English, the keys every translation uses
local L = LibStub("AceLocale-3.0"):NewLocale("ForeverLootFinder", "enUS", true)
if not L then return end

-- Core.lua
L["Error (shown once): %s"] = true
L["Copy your Dungeon Journal favourites: Favourites tab, \"Import FDJ favourites\"."] = true
L["open the window"] = true
L["open the settings"] = true
L["move the windows back to the centre"] = true
L["add an item (link or ID) to favourites"] = true
L["all item stats from the client"] = true
L["Dungeon Journal data"] = true
L["Usage: /flf fav <item link or ID>"] = true
L["Added to favourites (%s)."] = true
L["Unknown command \"%s\"."] = true
L["Click: loot list"] = true
L["Right-click: settings"] = true
L["Toggle the loot list"] = true
L["Questie data"] = true
L["AtlasLoot and profession data"] = true
L["items not loaded, and why"] = true
L["all dumps but stats"] = true
L["reread the Dungeon Journal, rebuild the lists"] = true
L["Can't read DungeonJournal's loot data. Forever LootFinder may need an update."] = true
L["That item can't be worn."] = true
L["No addon lists where it's from, so it shows only under Favourites."] = true
L["the selected slot's items with no Pawn value, and why"] = true
L["Commands (also /foreverlootfinder):"] = true
L["each addon's state and memory"] = true

-- Features/Favourites.lua
L["BiS"] = true
L["Must have"] = true
L["Nice to have"] = true
L["The string is empty."] = true
L["Not a favourites string."] = true
L["The string is damaged."] = true
L["Needs a newer Forever LootFinder."] = true
L["%d favourites: %d new, %d tier changed, %d unchanged."] = true
L["From %s."] = true
L["%d new, %d unchanged, %d skipped."] = true
L["and %d more"] = true
L["no ID"] = true
L["Skipped:"] = true

-- Features/Sets.lua
L["%d of %d pieces listed"] = true
L["%d pieces listed"] = true

-- Features/Tooltip.lua
L["Quest: %s"] = true
L["Trash: %s"] = true
L["Trash"] = true
L["rare"] = true
L["shared, low chance"] = true
L["unconfirmed"] = true
L["Horde"] = true
L["Alliance"] = true
L["Drops from: %s"] = true
L["%d more (Shift)"] = true
L["%s (skill %d)"] = true
L["from level %d"] = true
L["Source: %s"] = true
L["Reputation"] = true
L["PvP: %s"] = true
L["PvP"] = true
L["World event: %s"] = true
L["World drop: %s"] = true
L["World drop"] = true
L["quest: %s"] = true
L["level %d"] = true
L["level %d–%d"] = true
L["Sold by %d vendors"] = true
L["Vendor: %s"] = true
L["Dropped by %d creatures"] = true
L["Auction: %s"] = true
L["creatures %s"] = true
L["Combine: %s"] = true
L["extremely rare"] = true
L["%d Honor"] = true
L["Rank %d"] = true

-- Features/Reminder.lua
L["Favourites in this dungeon"] = true
L["Click to close"] = true

-- Features/DropAlert.lua
L["Favourite dropped (%s)"] = true
L["Favourite dropped: %s (%s)"] = true

-- Features/Dump.lua
L["Ctrl+A, then Ctrl+C to copy."] = true
L["Close"] = true
L["Loading items; the dump opens when done."] = true
L["Stat dump"] = true
L["Dungeon Journal dump"] = true
L["Questie dump"] = true
L["Crafted items dump"] = true
L["Item data dump"] = true
L["Full dump"] = true
L["DungeonJournal isn't installed."] = true
L["Pawn dump"] = true
L["Status dump"] = true
L["Usage: /flf dump stats, fdj, questie, crafts, items, pawn, status or all"] = true

-- Features/ImportExport.lua
L["Not a Forever LootFinder profile string."] = true
L["All display and alert settings"] = true
L["Made with Forever LootFinder %s"] = true

-- Options/Options.lua
L["Settings"] = true
L["Please confirm"] = true
L["Export profile"] = true
L["Copy (Ctrl+C) and share."] = true
L["Import profile"] = true
L["Paste a profile string (Ctrl+V)."] = true
L["Import"] = true
L["Enter a profile name."] = true
L["Profile \"%s\" exists. Overwrite?"] = true
L["Overwrite"] = true
L["Cancel"] = true
L["Import into a new profile or over \"%s\"?"] = true
L["New profile name"] = true
L["Imported"] = true
L["Create profile"] = true
L["Into current"] = true
L["Overwrite \"%s\"?"] = true
L["Export favourites"] = true
L["Favourites of %s. Copy (Ctrl+C) and share."] = true
L["Import favourites"] = true
L["Paste a favourites string (Ctrl+V) for %s."] = true
L["Merge adds new items and keeps your tiers. Overwrite replaces the list."] = true
L["Merge"] = true
L["Nothing new to import."] = true
L["Copy this character's Dungeon Journal favourites as \"Nice to have\"?"] = true
L["Add %s to your favourites as \"BiS\"?"] = true

-- UI/Labels.lua
L["Head"] = true
L["Neck"] = true
L["Shoulder"] = true
L["Back"] = true
L["Chest"] = true
L["Wrist"] = true
L["Hands"] = true
L["Waist"] = true
L["Legs"] = true
L["Feet"] = true
L["Finger"] = true
L["Trinket"] = true
L["One-hand"] = true
L["Main hand"] = true
L["Two-hand"] = true
L["Off hand"] = true
L["Ranged"] = true
L["Relic"] = true
L["Cloth"] = true
L["Leather"] = true
L["Mail"] = true
L["Plate"] = true
L["Shield"] = true
L["Held in off-hand"] = true
L["Libram"] = true
L["Idol"] = true
L["Totem"] = true
L["One-handed axe"] = true
L["Two-handed axe"] = true
L["Bow"] = true
L["Gun"] = true
L["One-handed mace"] = true
L["Two-handed mace"] = true
L["Polearm"] = true
L["One-handed sword"] = true
L["Two-handed sword"] = true
L["Staff"] = true
L["Fist weapon"] = true
L["Dagger"] = true
L["Thrown"] = true
L["Crossbow"] = true
L["Wand"] = true
L["Weapon skill"] = true
L["Weapon DPS"] = true
L["Vendor"] = true
L["Creature"] = true

-- UI/Row.lua
L["Upgrade"] = true
L["Speed / DPS"] = true
L["Drop %"] = true
L["Source"] = true
L["+%d more"] = true
L["Unique"] = true
L["new"] = true
L["Name"] = true
L["Unique: already equipped"] = true
L["Unique: already owned"] = true
L["Two-hand weapon equipped."] = true
L["Slot empty."] = true
L["Pawn (%s): %.1f"] = true
L["Set: %s (%s)"] = true
L["Item data still loading."] = true
L["Not in the game data yet"] = true
L["Price"] = true
L["Auction price"] = true
L["No drop chances known yet."] = true
L["Weapon slots only."] = true
L["Columns"] = true
L["Click: sort. Right-click: columns."] = true
L["Auction price: %s"] = true
L["Cheapest random-bonus version."] = true
L["Last seen at auction %d days ago."] = true
L["Not seen at auction for 21+ days."] = true
L["Not on this server: it says the item doesn't exist."] = true
L["Maybe not on this server: it never sent the item."] = true
L["binding"] = true
L["quality"] = true
L["stats"] = true
L["weapon speed"] = true
L["sets only"] = true
L["search"] = true
L["owned"] = true
L["price"] = true
L["drop chance or source"] = true
L["Your filters hide it elsewhere: %s."] = true
L["Above your level filter for now."] = true
L["better"] = true
L["PvP rank"] = true
L["reputation"] = true
L["not an upgrade"] = true
L["Score"] = true
L["Pick a scale at the top."] = true
L["Scores count base stats only; the bonus is random."] = true
L["Scores don't count set bonuses."] = true
L["Not scored yet."] = true

-- UI/Menu.lua
L["Remove from favourites"] = true
L["Show in Dungeon Journal"] = true
L["Show whole set"] = true
L["Link to chat"] = true
L["Hide this item"] = true
L["Show in AtlasLoot"] = true
L["Quest in Questie: %s"] = true
L["Waypoint: %s"] = true
L["Search in Auctionator"] = true
L["Add to Auctionator shopping list"] = true
L["Already on shopping list \"%s\"."] = true
L["Added to shopping list \"%s\"."] = true
L["Auctionator couldn't add it."] = true

-- UI/SetPanel.lua
L["Favourite all pieces"] = true
L["Owned"] = true

-- UI/Filters/FilterBar.lua
L["Attributes"] = true
L["Spell"] = true
L["Physical"] = true
L["Defense"] = true
L["Resistances"] = true
L["Click: want, exclude, any. Right-click: any."] = true
L["Any binding"] = true
L["Bind on pickup only"] = true
L["Bind on equip only"] = true
L["My level + N"] = true
L["Fixed level"] = true
L["Any wanted stat"] = true
L["All wanted stats"] = true
L["All dungeons"] = true
L["None"] = true
L["Armor type"] = true
L["Cloaks, rings, necks and trinkets always show."] = true
L["Weapon type"] = true
L["Stats"] = true
L["Has a Use or proc effect"] = true
L["Sources"] = true
L["Rare spawns"] = true
L["Trash drops"] = true
L["Shared loot (low chance)"] = true
L["Unconfirmed drops"] = true
L["Hide the other faction"] = true
L["Max required level"] = true
L["Hide items above this level"] = true
L["My level"] = true
L["My level + 5"] = true
L["Dungeon level"] = true
L["Only dungeons in this level range"] = true
L["Binding"] = true
L["BoE items can also be bought or traded."] = true
L["Weapon speed"] = true
L["Weapons in this speed range (sec)"] = true
L["Other items aren't affected."] = true
L["More"] = true
L["Only set pieces"] = true
L["Hide items I own"] = true
L["Equipped, bags, and bank once opened."] = true
L["Minimum quality"] = true
L["Dungeons"] = true
L["%d dungeons"] = true
L["Max required level: off"] = true
L["Max required level: %d"] = true
L["their level"] = true
L["your level"] = true
L["Max required level: %d (%s + %d)"] = true
L["no armor"] = true
L["no weapons"] = true
L["%d weapon types"] = true
L["All of: %s"] = true
L["Any of: %s"] = true
L["Without: %s"] = true
L["no rares"] = true
L["no trash"] = true
L["no shared loot"] = true
L["with unconfirmed"] = true
L["both factions"] = true
L["dungeons %d–%d"] = true
L["BoP only"] = true
L["BoE only"] = true
L["speed %.1f–%.1f"] = true
L["set pieces"] = true
L["Use or proc"] = true
L["%s or better"] = true
L["name has \"%s\""] = true
L["not owned"] = true
L["upgrades only"] = true
L["Equipped, bags, bank and mail (Syndicator)."] = true
L["Dungeon drops"] = true
L["Dungeon quests"] = true
L["Other quests (Questie)"] = true
L["Hide done quests"] = true
L["Not if you still have the item."] = true
L["BoP only from my professions"] = true
L["no dungeon drops"] = true
L["no dungeon quests"] = true
L["no other quests"] = true
L["no crafted"] = true
L["with done quests"] = true
L["Raids and world bosses"] = true
L["Reputation rewards"] = true
L["PvP rewards"] = true
L["World events"] = true
L["World drops"] = true
L["no raids"] = true
L["no reputation"] = true
L["no PvP"] = true
L["no world events"] = true
L["no world drops"] = true
L["Hide items for other professions"] = true
L["Like engineering goggles: wearable only with the profession."] = true
L["with other professions' items"] = true
L["Hide cosmetic items"] = true
L["with cosmetic items"] = true
L["All raids"] = true
L["%d raids"] = true
L["Raids"] = true
L["Needs one of these addons:"] = true
L["Places"] = true
L["Quests tied to a raid go with it."] = true
L["Item"] = true
L["Off in Settings, Addons tab."] = true
L["Without it, open a profession window to list its items."] = true
L["Hide drops rarer than this"] = true
L["Keep drops with unknown chance"] = true
L["AtlasLoot's chances, per boss. Often unknown for trash and shared loot. Quests and crafts aren't affected."] = true
L["drop chance %s or more"] = true
L["no unknown chances"] = true
L["Also hides dungeons and quests above this level."] = true
L["Turn on \"%s\" first."] = true
L["Turn on \"%s\" or \"%s\" first."] = true
L["Sold by vendors"] = true
L["no vendors"] = true
L["Creature drops (outside dungeons)"] = true
L["no creature drops"] = true
L["Max auction price (gold)"] = true
L["Only items with a price"] = true
L["with an auction price"] = true
L["Auctionator's prices from your scans. BoP and unpriced items: hidden by the first box, kept by the max price."] = true
L["Only up to my skill"] = true
L["Hide items above my skill"] = true
L["Only standings I have"] = true
L["my standings"] = true
L["Only ranks I have"] = true
L["my PvP rank"] = true
L["Upgrades only"] = true
L["my battleground standings"] = true

-- UI/MainWindow.lua
L["Item level"] = true
L["Required level"] = true
L["Drop chance"] = true
L["Quality"] = true
L["One stat"] = true
L["Visible scales"] = true
L["Other scales"] = true
L["Search"] = true
L["Sort:"] = true
L["Filters"] = true
L["Reset"] = true
L["Reset filters to class defaults"] = true
L["Paused in combat"] = true
L["%d items"] = true
L["Nothing to list yet."] = true
L["Loading %s items..."] = true
L["Upgrade %"] = true
L["Scale:"] = true
L["Reread scores (after editing a Pawn scale)"] = true
L["Scores..."] = true

-- UI/Tabs/SlotTab.lua
L["No items match the filters."] = true
L["By slot"] = true
L["~ Some of these haven't loaded yet, or aren't scored yet. Open the slot to load them."] = true

-- UI/Tabs/DungeonTab.lua
L["All slots"] = true
L["Click: open in Dungeon Journal"] = true
L["Slot:"] = true
L["loot list incomplete"] = true
L["Raid, from AtlasLoot"] = true
L["From AtlasLoot"] = true
L["Raids and world bosses need AtlasLoot."] = true
L["Group by boss"] = true
L["Shift-click: waypoint to the entrance"] = true
L["Combined"] = true

-- UI/Tabs/FavouritesTab.lua
L["Character:"] = true
L["Export"] = true
L["Import FDJ favourites"] = true
L["Copies this character's Dungeon Journal favourites once, as \"Nice to have\"."] = true
L["%d of %d favourites shown"] = true
L["No favourites yet. Click an item to add it."] = true
L["No favourites match the filters."] = true
L["Favourites"] = true
L["Other"] = true
L["Sold by many vendors"] = true
L["Dropped by many creatures"] = true
L["No source listed"] = true
L["Add item"] = true
L["Any wearable item, even one no addon lists. It shows only here."] = true

-- Options/GeneralTab.lua
L["Rare"] = true
L["Shared"] = true
L["Quest"] = true
L["Unconfirmed"] = true
L["Random bonus"] = true
L["Faction"] = true
L["Not in game data yet"] = true
L["BoE"] = true
L["Set"] = true
L["Window"] = true
L["Minimap button"] = true
L["Favourite stars"] = true
L["Item tooltips"] = true
L["List"] = true
L["Show items still loading (greyed)"] = true
L["Random-bonus items pass stat filters"] = true
L["Their base stats differ from the drop."] = true
L["Badges on rows"] = true
L["Hidden items"] = true
L["Hidden with \"Hide this item\", this character only."] = true
L["Show one again"] = true
L["Show all again"] = true
L["General"] = true
L["Crafted"] = true
L["Professions: mine first"] = true
L["Dungeons, Raids: hide empty places"] = true
L["Dungeons, Raids: drop chance on icons"] = true
L["Auction price (Auctionator)"] = true
L["For when Auctionator's own price lines are off."] = true
L["Empty columns stay hidden. Also: right-click the list header."] = true
L["Source on all item tooltips"] = true
L["LootFinder's windows always show it."] = true
L["Show items not on this server"] = true
L["Greyed. Missing favourites always show."] = true
L["Favourite tier"] = true
L["Other characters' favourites"] = true

-- Options/AlertsTab.lua
L["Small window"] = true
L["Chat"] = true
L["Off"] = true
L["Dungeon reminder"] = true
L["On entering a dungeon: your favourites there and their bosses."] = true
L["Drop alert"] = true
L["When a favourite drops: loot window, group roll or chat."] = true
L["On-screen notice"] = true
L["Chat line"] = true
L["Sound"] = true
L["Alerts"] = true

-- Options/FavouritesTab.lua
L["%s (%s %d, %d favourites)"] = true
L["Tiers"] = true
L["From the Dungeon Journal"] = true
L["Characters"] = true
L["Delete character"] = true
L["Delete %s and their favourites?"] = true
L["Delete"] = true
L["Characters are added on login. The current one can't be deleted."] = true
L["Share"] = true
L["The selected character's favourites and tiers, as a string."] = true
L["Click adds items with this tier:"] = true
L["It has no lists for your class yet."] = true
L["AtlasLoot BiS lists"] = true
L["Adds a list's items as \"BiS\". Nothing is imported until you click."] = true
L["Import BiS list"] = true

-- Options/ProfilesTab.lua
L["Current profile"] = true
L["Profiles hold display and alert settings. Filters and favourites are per character."] = true
L["New profile"] = true
L["Create"] = true
L["Copy from"] = true
L["Copies another profile into this one."] = true
L["Overwrite the current profile with \"%s\"?"] = true
L["Copy"] = true
L["Select a profile"] = true
L["Delete a profile"] = true
L["Delete the profile \"%s\"?"] = true
L["Reset current profile"] = true
L["Reset this profile?"] = true
L["Share this profile as a string. Import asks before replacing."] = true
L["Profiles"] = true

-- Modules/AtlasLoot/Crafts.lua
L["Blacksmithing"] = true
L["Leatherworking"] = true
L["Tailoring"] = true
L["Engineering"] = true
L["Enchanting"] = true
L["Alchemy"] = true
L["Jewelcrafting"] = true
L["Cooking"] = true
L["First Aid"] = true
L["Mining"] = true
L["Herbalism"] = true
L["Skinning"] = true
L["Fishing"] = true

-- UI/Tabs/QuestTab.lua
L["Other quests"] = true
L["%d quests"] = true
L["Install Questie for quests outside dungeons."] = true
L["Reading Questie..."] = true
L["Quests"] = true
L["%s (done)"] = true
L["Group by quest"] = true

-- UI/Tabs/CraftTab.lua
L["Apprentice (1–74)"] = true
L["Journeyman (75–149)"] = true
L["Expert (150–224)"] = true
L["Artisan (225–299)"] = true
L["Master (300+)"] = true
L["Skill unknown"] = true
L["your skill %d"] = true
L["Learned (skill %d)."] = true
L["Not learned: the filter hides its BoP items."] = true
L["Professions"] = true
L["Group by skill"] = true
L["Install forever-db for all crafted items, or open your professions once."] = true

-- Options/AddonsTab.lua
L["Waiting to load..."] = true
L["Reading..."] = true
L["Loaded, but no data found. See /flf dump questie or crafts."] = true
L["Not installed."] = true
L["In use."] = true
L["Addons"] = true
L["Profession window"] = true
L["Dungeon and raid drops"] = true
L["Quest rewards"] = true
L["Crafted items"] = true
L["Use for owned items"] = true
L["Knows your gear, bags, bank and mail across sessions. Without it, the bank counts once opened."] = true
L["Use for crafts, raids and other lists"] = true
L["Crafts, raid and world boss loot, reputation, PvP and event rewards."] = true
L["When addons overlap"] = true
L["Same item, same place (dungeon, quest, profession): the first addon's entry wins."] = true
L["%d crafted, %d other items."] = true
L["Tabs"] = true
L["Show the %s tab"] = true
L["%s (default)"] = true
L["Use for quests, vendors and creature drops"] = true
L["Vendors"] = true
L["Creature drops"] = true
L["Questie's database: quest rewards, vendor goods and creature drops."] = true
L["Waypoints"] = true
L["Auto (TomTom, else map pin)"] = true
L["Game map pin"] = true
L["This client has no map pins."] = true
L["Right-click an item for a waypoint to its source. Shift-click a dungeon name for its entrance."] = true
L["%d quest rewards, %d vendor, %d creature sources."] = true
L["In use: TomTom."] = true
L["In use: the game's map pin."] = true
L["Not available: install TomTom."] = true
L["Use auction prices"] = true
L["Price column, sort, filters and shopping list. Prices are from your scans."] = true
L["In use: %d of %d sellable items priced."] = true
L["In use: %d dungeons."] = true
L["Use for quests the others miss"] = true
L["Quest rewards from Wowhead's Forever pages. QuestieDB and DungeonJournal come first."] = true
L["Use for rare creatures"] = true
L["Rares and their loot. DungeonJournal and QuestieDB come first."] = true
L["%d quests, %d rewards."] = true
L["%d rares, %d items."] = true
L["Use for its Forever database"] = true
L["Dungeon loot, quests, vendors, crafts, reputation, PvP and event rewards. Fills what the others miss, and gives recipes their skill level on Forever."] =
  true
L["Use for crafts, quests, vendors and drop chances"] = true
L["Links every recipe to what it makes, Forever's own included. Creature drops get their chance, mostly Classic's."] = true
L["%d sources, %d places."] = true
L["%d crafts, %d quest rewards, %d vendor and %d creature sources."] = true
L["Use for crafts and recipe skill"] = true
L["Gives recipes the skill they need on Forever. For trainer recipes ALL THE THINGS comes first."] = true
L["%d crafts, %d recipe skills."] = true
L["Use for dungeon loot, quests and PvP rewards"] = true
L["The main source: Forever's dungeons, bosses, dungeon quests and PvP rewards."] = true

-- UI/Tabs/SourceTabs.lua
L["Needs AtlasLoot or ALL THE THINGS."] = true
L["Needs DungeonJournal, AtlasLoot or ALL THE THINGS."] = true

-- Modules/Questie.lua
L["%s (entrance)"] = true
L["Darkmoon Faire"] = true
L["Lunar Festival"] = true
L["Love is in the Air"] = true
L["Noblegarden"] = true
L["Children's Week"] = true
L["Midsummer Fire Festival"] = true
L["Harvest Festival"] = true
L["Hallow's End"] = true
L["Feast of Winter Veil"] = true

-- Modules/Waypoints.lua
L["Waypoint set: %s"] = true

-- UI/Filters/FilterSummary.lua
L["auction price up to %s"] = true

-- Options/CreditsTab.lua
L["By %s"] = true
L["%s (comes with %s)"] = true
L["By the Questie team: %s and others"] = true
L["Quest rewards, vendors and creature drops."] = true
L["Raids, crafted gear, reputation, PvP and event rewards, drop chances."] = true
L["Item scores and upgrades."] = true
L["Items in bags, bank and mail across characters."] = true
L["Auction prices and shopping lists."] = true
L["Made by %s"] = true
L["It reads its data from these addons. Thanks to their authors!"] = true
L["Credits"] = true
L["Quest rewards from Wowhead's Forever pages."] = true
L["Rare creatures and their loot."] = true
L["Dungeon loot, bosses, quests and PvP rewards."] = true

-- Modules/AtlasLoot/BiS.lua
L["%s, phase %d"] = true

-- UI/AddFavourite.lua
L["%s added (%s)."] = true
L["No known source: it shows only here."] = true
L["no source"] = true
L["Nothing found. Try a link (Shift-click the item) or its ID."] = true
L["Add a favourite"] = true
L["Item name, ID, or Shift-click an item."] = true
L["SoD only"] = true
L["unlikely drop"] = true
L["removed quest"] = true
L["not on this server"] = true
L["Hidden by LootFinder: %s."] = true
L["You can still add it."] = true

-- Modules/Attune.lua
L["Quest %d"] = true

-- UI/Tabs/SetsTab.lua
L["%d of %d pieces"] = true
L["Sets"] = true
L["No set pieces match the filters."] = true

-- Core/Holidays.lua
L["Stranglethorn Fishing Extravaganza"] = true

-- Modules/DungeonJournal.lua
L["Honor & Ranks"] = true
