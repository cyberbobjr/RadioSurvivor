# Changelog

## Unreleased

### Gameplay

- Rarely, a radio voice may introduce you to another voice and give you its frequency: only after several conversations over different days (or with a good reputation), when you have negotiated, earned its trust or truly convinced it, and never often. Walt and Gus can now do it too, as Darlene and Cody already could.
- The notebook's Radio tab now shows who speaks on a frequency and when they listen, as soon as they have answered you, you have heard them, or you have read their frequency note. Reading a frequency note adds it to the notebook.
- The Night Owl's evening memorial no longer reads a dead animal as "None None", and the Night Owl no longer says he won't give the names right before they are read.
- Talking helps: each time a survivor answers your character on the radio, their boredom and unhappiness go down a little (shown above the character). Overhearing two survivors talk to each other eases a little boredom too. At most 5 comforts per in-game hour; four new sandbox options set the amounts and the limit (0 turns one off).
- Corpses carrying a walkie-talkie now have a 35% chance to also contain a frequency note when their loot is generated. The existing note rarity setting adjusts this chance (14% on Rare, 87.5% on Frequent, disabled on None).
- Increased the availability of Walt's frequency note in home and office desks, garages, electronics crates and amateur radio shelves.

- A successful mission's unclaimed shared reward is now kept for 7 in-game days instead of 7 real days: the wait stops while the game is paused or the server is empty. Rewards already waiting keep the time they had left (at most 7 in-game days).

### Reliability

- A misbehaving client can no longer freeze the server by flooding notebook, radio or NPC requests, or by sending a radio message made of tens of thousands of spaces; normal play and reconnections are not affected.
- Radio voices can no longer be steered by a character or radio name written as an order, nor tricked by a message that pretends to come from another caller on the same frequency.
- The AI bridge caps the cost of every request: each attempt is limited in length, an answer cut by that limit is not retried, and an oversized prompt is never sent (the voice answers with static). Server admins can tune both limits in the bridge settings (`LLM_MAX_TOKENS`, `LLM_MAX_PROMPT_CHARS`).
- A notebook save that fails once (disk busy, file locked) no longer switches the notebook off until the next restart: the save is retried and nothing is lost.
- A very large notebook state on a long-running server can no longer produce a save file that the next session cannot read; dead characters' old notebook data is cleared after a few in-game weeks to keep the save small.
- Corpse notes only select active voices with an available frequency. Repeated loot generation preserves the original roll and avoids duplicate notes already in the corpse.

### Validation

- Frequency notes: 27 automated tests passed; protocol and notebook tests passed; Lua lint and project plan checks passed.
- Actual corpse loot in solo and multiplayer remains to be checked in game after restarting.
