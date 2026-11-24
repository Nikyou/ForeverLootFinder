#### 1.4.3
* Fixed the profession filters doing nothing on a character with no professions: other professions' BoP crafts and items like engineering goggles now hide for them too.
* New filter "Only up to my skill", under "BoP only from my professions": hides BoP crafts whose recipe needs more skill than you have.
* New filter "Hide items above my skill", under "Hide items for other professions": goggles that need 225 Engineering no longer show at 100.
* World drops show as one "World drop" line instead of also listing a few creatures, so unticking "World drops" now hides them.

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
