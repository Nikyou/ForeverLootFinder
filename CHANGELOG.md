#### 1.4.4
* SkillUp Forever is supported: crafted gear shows the skill its recipe needs on Forever.
* GearQuest Forever is supported: its stat weights for every spec are listed as scales next to Pawn's, and score items when Pawn isn't installed.
* Items you buy show their price, in gold or in the currency you pay with (125 Tarnished Undermine Reals, 1200 Darkmoon Faire tickets).
* Holiday rewards show under their holiday on the World events tab, also without AtlasLoot.
* With Questie, quests that were never in the game or were removed no longer show.
* Fixed some quests missing, holiday quests among them.
* Fixed world events and world epics missing from AtlasLoot since 1.4.3.
* Fixed AtlasLoot's dungeon quest rewards showing as trash drops on non-English clients.

#### 1.4.3
* Items the addons list more than once are now merged, so unticking a source really hides them. Dungeon and raid loot no longer also shows as a creature drop outside dungeons, and a world drop is one "World drop" line instead of also a few creatures.
* PvP, reputation and world event rewards show as one line, with the vendor that sells them, the creatures that drop them and the quest that gives them. Unticking "PvP rewards" now hides Grand Marshal's gear, and unticking "Raids and world bosses" hides Ouro's Larvae of the Great Worm.
* "PvP rewards" and "Reputation rewards" work without AtlasLoot: an item that needs a PvP rank or a reputation counts as one, whoever sells or gives it.
* New filters "Only ranks I have" and "Only standings I have", under PvP and reputation rewards: hide what your rank or reputation doesn't let you buy yet. Off by default.
* New filter "Hide items above my skill", under "Hide items for other professions": goggles that need 225 Engineering no longer show at 100.
* New filter "Only up to my skill", under "BoP only from my professions": hides BoP crafts whose recipe needs more skill than you have.
* Fixed the profession filters doing nothing on a character with no professions.
* Fixed world epics showing as world events, and AtlasLoot's world events (Darkmoon Faire, Lunar Festival and the rest) missing.

#### 1.4.2
* Uses much less memory: the item list is built once all addons have been read, not again after each one. The item list no longer copies what the other addons give it, and each item's data is smaller.
* forever-db's copy of Questie's data is dropped where Questie already has it.

#### 1.4.1
* Trinkets and rings no longer stay greyed as "Pawn hasn't scored it yet" while you wear one with nothing Pawn can score, like a "Use:" trinket or a plain ring. Anything Pawn scores now shows as "better" than it.
* The developers' test items, like "Ring of Uber Resists (TEST)", no longer show.

#### 1.4
* What you're wearing always shows in its slot, even with no known source, filtered out, or with "Pawn upgrades only" ticked.
* ALL THE THINGS and forever-db support: Forever's own crafted gear, more quest rewards and vendors, and drop chances for creatures. Each one only fills what the other addons miss.
* forever-db now comes with Forever Loot Finder when you install it with the CurseForge app.
* Professions: every recipe shows what it makes even before you learn it, and with ALL THE THINGS the skill it's learned at on Forever.

#### 1.3
* New Sets tab: a card per item set your character can wear, its pieces by slot and where each one comes from. It can be hidden under Settings > Addons.
* Items with nothing saved from earlier sessions load first, before the ones already shown from the cache.
* "Pawn upgrades only" with a two-hander equipped: off-hands no longer stay greyed as "still loading".
* A greyed row's tooltip now says whether the item is still loading or Pawn just hasn't scored it yet.
* Fixed items staying greyed without a Pawn value until you hovered them, and "Pawn values..." blinking in the status line without end.

#### 1.2
* Fixed the game slowing down while items load: items were asked for again and again when the game had already dropped them, and Pawn did the same for items it scored.
* Items are asked for at the server's pace, so far fewer end up with no answer.
* Only what you're looking at is loaded: the selected slot, the open tab or your favourites. Everything else shows what was saved last time, Pawn scores included, until you open it.
* Dungeon drop chances now come from DungeonJournal (2.0.11 or later), measured on Forever. AtlasLoot's fill in where it has none.
* "Extremely rare" drops show their real chance too.

#### 1.1
* Fixed item data being loaded over and over after it had finished. This slowed the game down.
* Items load faster, and what's on screen comes first: the selected slot, or the cards of the Dungeons, Raids, Quests and other tabs from the top down.
* "Pawn upgrades only": the other slots' counts are now exact once Pawn has scored their items, and the slot you just left no longer turns back to "~".

#### 1.0
Addon release.
