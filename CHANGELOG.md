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

- One trader per vanilla town. Riverside, West Point, Brandenburg and Louisville get a smuggler who comes by boat at night; Muldraugh, March Ridge, Irvington and Echo Creek get one who drives up to the roadside; in Rosewood, Ekron and Fallas Lake nobody shows up: you leave the payment in a container and the goods appear there later. Each trader has their own story, stock, hours and frequency note.
- Trades happen only once every player is out of sight of the meeting place, after a short in-game delay; come back too early and nothing has moved yet.
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
- Server owners can write their own radio voices in a single text file: places, jobs, rewards, item categories, trade stock and frequency notes all go in that one sheet (see the wiki page "Creating a radio voice").

### Voice workshop

- New voice workshop: make, change and share radio voices in your web browser, without writing a file. Start it with `atelier.bat` (Windows), `atelier.sh` (Linux) or `atelier.command` (macOS) in the bridge folder, or `python radio_bridge.py --atelier`. The bridge keeps answering the game, and the workshop opens even without an AI configured. In English and French.
- Five simple steps: who, where and when, what she knows, missions and rewards (each one Rarely, Normally or Often), plus an optional trader stock and frequency note. A "?" on every setting explains it with an example. The game hears a saved voice within 30 seconds, without a restart.
- Record places in game: right click a square, "Voice workshop: record this place" (in solo, or an admin in multiplayer), and the place shows up in the workshop under "Recorded in game"; "Add to this voice" makes it one of the voice's places, with a suggested name and use (a container becomes a dead drop).
- The bridge's AI can write a voice's personality from a few sentences in your own language, suggest what she says to give a job, and let you try the voice before saving it.
- When the game refuses a sheet, the voice gets a red dot and a banner names the line in plain words, with a button to the right step.
- Live journal for server owners: what players say to the voices, their replies and the sheets the game refused, filtered by voice. It stays on the machine running the workshop.
- Export a voice to a file and import it elsewhere; a voice of the mod can be taken off the air or brought back to the mod's version.
- A trader's stock no longer needs item weights: write `item=Base.Battery:4-12` (or pick the item by its name in the workshop) and the server reads the weight from the game's item (a full bottle counts its liquid); an item the game does not know makes the sheet refused, with its line in the server log.
- A new radio voice can have its own frequency note and its own spontaneous call without touching the mod: the note's text and the call are written in the voice's sheet, in any language. The note is found in the loot as a handwritten note showing that voice's text and its frequency.
- Every radio voice now remembers every caller permanently, up to 2,000 characters of notes per character, and remembers those who died: talk to a voice about a dead friend and it may recall them.

### Living Knox survivors

- Gardeners dig furrows, sow seeds from their supplies and water the plants of their home, after the daily upkeep.
- Survivors carry provisions on their trips and refill their water before they run dry.
- Members of a group chat with each other at home, across rooms, where you can overhear them.
- Survivors remember what they saw (and who), and act on their own initiative more or less often depending on the sandbox settings.
- A survivor who finds a window refused goes through the doors on the next trips; a zombie stuck at a window is attacked from outside instead of from the window.
- Raiders wait for their breaker before forcing a way in.
- Living Knox missions can be given, delivered and rewarded without Radio Survivor.

### Fixes

- The Night Owl's evening memorial no longer reads a dead animal as "None None", and the Night Owl no longer says he won't give the names right before they are read.
- A busy radio channel no longer holds back the lines of the other frequencies.
- The notebook stays whole on screen after switching to a smaller resolution.
- Compatibility with Build 42.22.

### Reliability

- A misbehaving client can no longer freeze the server by flooding notebook, radio or NPC requests, or by sending a radio message made of tens of thousands of spaces; normal play and reconnections are not affected.
- Radio voices can no longer be steered by a character or radio name written as an order, nor tricked by a message that pretends to come from another caller on the same frequency.
- The AI bridge caps the cost of every request: each attempt is limited in length, an answer cut by that limit is not retried, and an oversized prompt is never sent (the voice answers with static). Server admins can tune both limits in the bridge settings (`LLM_MAX_TOKENS`, `LLM_MAX_PROMPT_CHARS`).
- A notebook save that fails once (disk busy, file locked) no longer switches the notebook off until the next restart: the save is retried and nothing is lost.
- A very large notebook state on a long-running server can no longer produce a save file that the next session cannot read; dead characters' old notebook data is cleared after a few in-game weeks to keep the save small.
- Corpse notes only select active voices with an available frequency. Repeated loot generation preserves the original roll and avoids duplicate notes already in the corpse.
