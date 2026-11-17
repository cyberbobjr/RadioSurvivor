# Changelog

## Unreleased

### Three mods in one Workshop item

- Radio Survivor and Living Knox are now two separate mods in the same Workshop item: play with the radio voices alone, with the Living Knox survivors alone, or with both. Each one works on its own.
- The parts both mods share live in a third mod, Core AI (batman_CoreAI); it is enabled automatically by Radio Survivor or Living Knox.
- The notebook now belongs to Core AI: it works the same with Radio Survivor, Living Knox or both. Each mod adds its own tabs (Radio for the voices), and the Contacts, Missions and Reputation tabs are shared.
- With Living Knox alone the notebook is complete (notes, NPC selection, quoted deliveries, report button) and group agreements and incidents are announced.
- A chat line said without a selected target goes to the nearest NPC within 8 squares (nothing happens if nobody is near). The shortcut is now called Select the nearest NPC (Ctrl+G).
- Character Reputation is no longer needed: reputation is now part of the shared mod.
- Saves started before the split are not carried over: start a new game.

### Radio voices

- Each voice now needs a kind of radio: some answer any walkie-talkie, others only a good, pro or tactical walkie, a ham radio or army gear. Each new game gives every voice a free frequency that its radio tunes and simpler radios do not, so a better radio lets you find more voices; two voices never share a frequency. In the voice workshop, pick the radio on a card, or choose a fixed frequency yourself and a badge shows which radio it needs.
- Every voice's frequency note can now be found wherever papers lie around (office and home desks, filing cabinets, bedside tables, kitchen drawers, post offices, police and school desks), in car glove boxes and on zombies: any zombie may rarely carry one, a zombie with a walkie-talkie much more often. Each voice also keeps its own themed places.
- One trader per vanilla town. Riverside, West Point, Brandenburg and Louisville get a smuggler who comes by boat at night; Muldraugh, March Ridge, Irvington and Echo Creek get one who drives up to the roadside; in Rosewood, Ekron and Fallas Lake nobody shows up: you leave the payment in a container and the goods appear there later. Each trader has their own story, stock, hours and frequency note.
- Trades happen only once every player is out of sight of the meeting place, after a short in-game delay; come back too early and nothing has moved yet.
- Trading is simpler: you and the trader agree on the radio on two lists of items, what you bring and what they leave ("bring me 2 boxes of shells, I leave you 3 cans"). No points or prices any more, and the agreed deal is written in your notebook's Radio tab. Once the trader has arrived, the deal no longer changes.
- Each trader says what they accept as payment (cash, jewelry, cameras, papers of the dead, military gear, medicine...), and only asks for those items.
- Leave exactly what was agreed at the meeting place, on the ground in one or more bags or, for a dead drop, in one or more containers of the place (never in a vehicle). Only what you leave after the deal counts: loot already there or another player's bag is never taken. The trader takes exactly the agreed list and leaves the goods where most of your payment was. If something is missing, the trader keeps what you left and leaves nothing; if you leave nothing at all, your reputation drops a little.
- Cancelled trades are rare now (a patrol about 1 time in 75, a helicopter 1 time in 100, or a real storm for boats and vans) and the voice repeats the news every hour until the meeting time. A cancelled trade never touches what you left and costs you nothing.
- Dead drops feel real: the voice collects what you left only once nobody can see the spot (about 100 tiles) and a few in-game hours later (6 by default). Coming back before that restarts the wait, and you can take your goods back until then.
- A job can offer several drop points at once; you choose where to leave the goods, and deposits at different points add up.
- A missing person's ID card is no longer taken from your inventory when you report: leave it at one of the drop points like any other delivery. Only that card counts.
- Delivery jobs now ask for items of a category (for example medical: bandages, disinfectant, painkillers) and a quantity that can vary from one job to the next.
- Rewards are random: each voice draws a reward among what it can actually give right now, and a supply cache holds a random mix from its category instead of a fixed list.
- New radio jobs: board up the windows and doors of a building, put a powered radio high up as a relay, cross several places in the right order (on foot or by car), keep watch on a place for a few in-game hours (the voice asks what you saw: a helicopter, a horde passing by), or find someone's personal keepsake and leave it at a drop point.
- Jobs can follow each other: some only open once a previous one is done, and a voice's story can move on when its last job succeeds.
- Darlene has a story now: after the night she locked the clinic door on people begging to get in, she left the West Point clinic and hides elsewhere in town. Help her make the clinic safe again (scout it, clear the dead around it, board it up, bring medicine) and she goes back.
- Rarely, a radio voice may introduce you to another voice and give you its frequency: only after several conversations over different days (or with a good reputation), when you have negotiated, earned its trust or truly convinced it, and never often. Walt and Gus can now do it too, as Darlene and Cody already could.
- The notebook's Radio tab now shows who speaks on a frequency and when they listen, as soon as they have answered you, you have heard them, or you have read their frequency note. Reading a frequency note adds it to the notebook.
- Talking helps: each time a survivor answers your character on the radio, their boredom and unhappiness go down a little (shown above the character). Overhearing two survivors talk to each other eases a little boredom too. At most 5 comforts per in-game hour; four new sandbox options set the amounts and the limit (0 turns one off).
- Corpses carrying a walkie-talkie now have a 35% chance to also contain a frequency note when their loot is generated. The existing note rarity setting adjusts this chance (14% on Rare, 87.5% on Frequent, disabled on None).
- Increased the availability of Walt's frequency note in home and office desks, garages, electronics crates and amateur radio shelves.
- A successful mission's unclaimed shared reward is now kept for 7 in-game days instead of 7 real days: the wait stops while the game is paused or the server is empty.
- Radio voices no longer repeat fixed claims about the map (such as a clinic being surrounded) once your game has changed it: what a voice knows of the world now comes only from what happens in your game. Its past, skills and what it keeps to itself are written in its personality text.
- Radio jobs no longer always send you to the same building: a job can aim at a building near you (100 to 200 tiles), farther away (200 to 500) or far away (500 to 1500), or at a building inside an area, drawn again for each new job; the voice can also ask for a kind of building (house, farmhouse, motel, church, school, police station, clinic...). Every kind of job works this way, and a job with no place set looks near you.
- Server owners can write their own radio voices in a single text file: jobs, rewards, item categories, trade stock and frequency notes all go in that one sheet, and the places shared by every voice go in one places file (see the wiki page "Creating a radio voice").
- Ask a radio voice how to make something, in your own language: voices with a trade (Darlene and Odessa heal, Delphine cooks, Virgil farms, Hollis knows mechanics, Cody weapons, Maxine makeshift tricks) answer with the real recipes of your game, mod recipes included, and never make one up. They only help once your reputation is high enough; some look through their notes first and ask you to call back in an hour, half a day or a day. The recipe is written in your notebook's Radio tab, and with a good reputation a recipe that must be learned is really learned, as with a magazine.

### Voice workshop

- New voice workshop: make, change and share radio voices in your web browser, without writing a file. Start it with `atelier.bat` (Windows), `atelier.sh` (Linux) or `atelier.command` (macOS) in the bridge folder, or `python radio_bridge.py --atelier`. The bridge keeps answering the game, and the workshop opens even without an AI configured. In English and French.
- Five simple steps: who, where and when, personality, missions and rewards (each one Rarely, Normally or Often), plus an optional trader stock and frequency note. A "?" on every setting explains it with an example. The game hears a saved voice within 30 seconds, without a restart.
- Record places in game: right click a square, "Voice workshop: record this place" (in solo with the game's debug mode on, or an admin in multiplayer), and the place shows up in the workshop under "Recorded in game"; "Add to this voice" makes it one of the voice's places, with a suggested name and use (a container becomes a dead drop).
- The bridge's AI can write a voice's personality from a few sentences in your own language, suggest what the voice says to give a job, and let you try the voice before saving it.
- When the game refuses a sheet, the voice gets a red dot and a banner names the line in plain words, with a button to the right step.
- Live journal for server owners: what players say to the voices, their replies and the sheets the game refused, filtered by voice. It stays on the machine running the workshop.
- Export a voice to a file and import it elsewhere; a voice of the mod can be taken off the air or brought back to the mod's version.
- Open the workshop from a tablet or another computer at home: put `ATELIER_PASSWORD` in `bridge/.env` and start it with `--atelier-host 0.0.0.0`; everyone then logs in with that password, and repeated wrong passwords are slowed down.
- No more typing item names in the workshop: "Add items" opens a list you can search by name in your language and filter by category; tick several items and add them at once. A chosen item shows its name; click it to swap it for another, or remove the line.
- The workshop speaks like a player, not like a programmer: nothing technical to type anywhere. A new voice starts from its name and a card (survivor who talks, mission giver or trader) that ticks what it can do; how often it calls, when a trader comes back or how greedy it is are picked as words ("Often", "Every week", "Greedy") with the exact value tucked away; quantities use + and − buttons; a trader's bundles and own item lists are just named, and a mission's story change is written as a sentence.
- ✨ Suggest next to every text you write in the workshop (voice name, description, personality idea, place name, a job's sentence and what it changes in the story, spontaneous call, note lines, bundle and list names): the AI reads the whole voice being written (personality, places, jobs already written, notes, trade) and what the field is for, and proposes a text that fits; click again for another idea.
- Paste a position copied on the Project Zomboid map (`7966, 11751`) straight into a place's coordinates: x and y fill at once.
- New dashboard, the first tab of the workshop: every voice at a glance with the radio needed to hear it, its listening hours over 24 hours and what you can do with it (talk, jobs, trade, other frequencies, calls, rescue), with key numbers, one-click filters and sorting; click a voice to open it.
- New Places tab: every place is written once (an exact spot, or an area made of two corners pasted from the map) and every voice picks its places from a list, with "New place..." right in the list. A place a voice still uses cannot be deleted. In a job, choose its target: a place, near the player, farther or far away, and the kind of building.
- A voice's personality can be written in French as well as English: the AI understands both and keeps your text as you wrote it.
- A trader's sheet now says what the voice accepts as payment ("What the voice accepts"): whole categories such as Cash and valuables or Jewelry, or single items, only among those that have a trade price.
- Next to a place's x, y and z, a link opens the community Build 42 map on that square.
- A trader's stock in the workshop only offers the items a trader can actually sell (those with a price in the trade), and a stock line naming any other item is flagged: before, such an item could be picked but every offer naming it was refused.
- A trader's stock no longer needs item weights: write `item=Base.Battery:4-12` (or pick the item by its name in the workshop) and the server reads the weight from the game's item (a full bottle counts its liquid); an item the game does not know makes the sheet refused, with its line in the server log.
- A new radio voice can have its own frequency note and its own spontaneous call without touching the mod: the note's text and the call are written in the voice's sheet, in any language. The note is found in the loot as a handwritten note showing that voice's text and its frequency.
- Every radio voice now remembers every caller permanently, up to 2,000 characters of notes per character, and remembers those who died: talk to a voice about a dead friend and it may recall them.
- Tidier workshop: the voice list now shows only in the Voices tab, and the Places tab lists its places on the left with the place you pick on the right (and how many voices use each one); a click on a voice's name under "Used by" opens that voice. The Dashboard and the Journal use the whole width.
- New "Recipe help" block: tick the trades a voice knows, from which reputation it helps and whether it answers at once or asks the player to call back.

### Living Knox survivors

- Gardeners dig furrows, sow seeds from their supplies and water the plants of their home, after the daily upkeep.
- Survivors carry provisions on their trips and refill their water before they run dry.
- Members of a group chat with each other at home, across rooms, where you can overhear them.
- Survivors remember what they saw (and who), and act on their own initiative more or less often depending on the sandbox settings.
- A survivor who finds a window refused goes through the doors on the next trips; a zombie stuck at a window is attacked from outside instead of from the window.
- Survivors walk the game's own paths. When a window is locked or blocked, they walk around the house to a door they can use instead of pushing against the window.
- Survivors make way for each other: one standing on a passage steps aside for a survivor who needs to get through, then goes back to what it was doing. Between two walking survivors, the more urgent task goes first (fighting or fleeing before caring, defending, trips, chores and guard duty).
- Survivors no longer stop in doorways, on thresholds or in one-square corridors to wait, eat, work or keep watch.
- Raiders wait for their breaker before forcing a way in.
- Living Knox missions can be given, delivered and rewarded without Radio Survivor.
- Survivors get wounds like a player: a zombie scratches, lacerates or bites a precise body part, a knife cuts, a bat bruises, a bullet lodges, fire burns, and broken glass cuts a hand or forearm. Each wound bleeds and heals at the game's own pace, and a survivor's health follows its wounds (it also slowly comes back on its own, like a player's).
- Survivors living away from you keep the same real wounds: a member bitten on a trip comes back with the bite, bleeds if the group has no medical supplies, gets bandaged if it has some, and a survivor who meets you shows the wounds it got while you were away.
- Survivors clear the broken glass out of a smashed window before climbing through it; one who is fleeing or fighting climbs straight through and can be cut by the glass, like a player.
- Survivors bitten (or sometimes scratched) by zombies catch the Knox infection according to your sandbox settings: they die after the usual delay and rise as ordinary zombies, and their group mourns them and notes the infection in its journal. Infected wounds follow the game's rules.
- A group's medic treats wounds like a player, most urgent first: cleans with alcohol, bandages, changes dirty bandages, stitches, splints and pulls out glass or bullets, using real items from their own pockets, the patient's or the home stock.

### Fixes

- The Night Owl's evening memorial no longer reads a dead animal as "None None", and the Night Owl no longer says he won't give the names right before they are read.
- A busy radio channel no longer holds back the lines of the other frequencies.
- Living Knox survivors no longer stop outside under a window (or against a wall) as if they were back inside, and no longer stand guard outside against the wall after a fight.
- Living Knox foragers no longer freeze in front of a container instead of searching it.
- Living Knox survivors keep their home windows shut while their group is on alert and go out by the door; a survivor running back to its place no longer stops halfway to stare at the danger.
- The Living Knox admin teleport now lands right next to the survivor.
- A Living Knox survivor climbing through an open window no longer goes back to close another open window next to it.
- Living Knox gardeners sweep up broken glass and finish the home upkeep before digging new furrows, instead of digging and sowing endlessly.
- The notebook stays whole on screen after switching to a smaller resolution.
- Compatibility with Build 42.22.

### Reliability

- A misbehaving client can no longer freeze the server by flooding notebook, radio or NPC requests, or by sending a radio message made of tens of thousands of spaces; normal play and reconnections are not affected.
- Radio voices can no longer be steered by a character or radio name written as an order, nor tricked by a message that pretends to come from another caller on the same frequency.
- The AI bridge caps the cost of every request: each attempt is limited in length, an answer cut by that limit is not retried, and an oversized prompt is never sent (the voice answers with static). Server admins can tune both limits in the bridge settings (`LLM_MAX_TOKENS`, `LLM_MAX_PROMPT_CHARS`).
- A notebook save that fails once (disk busy, file locked) no longer switches the notebook off until the next restart: the save is retried and nothing is lost.
- A very large notebook state on a long-running server can no longer produce a save file that the next session cannot read; dead characters' old notebook data is cleared after a few in-game weeks to keep the save small.
- Corpse notes only select active voices with an available frequency. Repeated loot generation preserves the original roll and avoids duplicate notes already in the corpse.
