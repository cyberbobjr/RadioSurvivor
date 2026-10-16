# Changelog

## Unreleased

### Gameplay

- Talking helps: each time a survivor answers your character on the radio, their boredom and unhappiness go down a little (shown above the character). Overhearing two survivors talk to each other eases a little boredom too. At most 5 comforts per in-game hour; four new sandbox options set the amounts and the limit (0 turns one off).
- Corpses carrying a walkie-talkie now have a 35% chance to also contain a frequency note when their loot is generated. The existing note rarity setting adjusts this chance (14% on Rare, 87.5% on Frequent, disabled on None).
- Increased the availability of Walt's frequency note in home and office desks, garages, electronics crates and amateur radio shelves.

### Reliability

- Corpse notes only select active voices with an available frequency. Repeated loot generation preserves the original roll and avoids duplicate notes already in the corpse.

### Validation

- Frequency notes: 27 automated tests passed; protocol and notebook tests passed; Lua lint and project plan checks passed.
- Actual corpse loot in solo and multiplayer remains to be checked in game after restarting.
