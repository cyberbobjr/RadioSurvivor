*Français : [Options sandbox](../fr/09-options-sandbox.md)*

# Sandbox options

Two pages in the sandbox settings: **Radio Survivor** and **Living Knox**. On a dedicated server they are in
`<Zomboid>/Server/<server name>_SandboxVars.lua`. The in-game tooltip of each option gives the details.

## Radio Survivor

| Option | Default | Role |
|---|---|---|
| Enable the radio survivor (`Enabled`) | on | Turns all radio voices on or off. |
| Delay between two messages of a player (`PlayerCooldown`) | 10 s | Real delay between two messages sent to a voice. |
| Messages per hour, all players (`MaxPerHour`) | 60 | Radio messages per real hour for the whole server; each one is an AI call. `0` = unlimited: avoid on a public server. |
| Spontaneous calls (`SpontaneousCalls`) | on | General calls of the voices during their listening hours; counted in `MaxPerHour`. |
| Language of spontaneous calls (`CallLanguage`) | Server language | Server language, English or French. Answers always follow each caller's language. |
| Frequency notes in the loot (`NoteRarity`) | Normal | None, Rare, Normal, Common. Read when the world loads. |
| Hour of the evening bulletin (`ChronicleHour`) | 20 | In-game hour at which the pirate station reads the news of the day. |
| Last pages of the dead (`LastPages`) | on | A dead character's journal is left on the body. |
| NPC initiatives (`InitiativeFrequency`) | Normal | Off, Rare, Normal, Frequent: how often a nearby NPC speaks up on his own (each line is an AI call; at most 2, 6 or 12 per real hour). |
| Days of supplies of a group to rescue (`RescueDays`) | 3 | Time you have to reach a besieged family (1 to 10 game days). |

Fixed limits, without option: 8 pending radio requests, 5 s between two sentences on the client side, 15 sentences per
minute per player, 60 NPC dialogues and 12 biographies per real hour.

## Living Knox

| Option | Default | Role |
|---|---|---|
| Enable the Living Knox NPC engine (`Enabled`) | on | Turns the survivor groups on. Off: no group lives and no NPC appears. |
| Living Knox debug log (`Debug`) | off | Detailed engine messages in the console log. |
| Number of survivor groups (`GroupCount`) | 4 | 3 to 5, created once when the world starts: change it before creating the world. |
| Share of settler / raider / neutral groups (`WeightSettlers`, `WeightRaiders`, `WeightNeutrals`) | 40 / 35 / 25 | Relative weights of the group kinds. |
| Members per group, minimum / maximum (`GroupSizeMin`, `GroupSizeMax`) | 4 / 8 | Group size. |
| Days before a new group arrives, minimum / maximum (`ReliefDaysMin`, `ReliefDaysMax`) | 2 / 5 | Delay before a wiped-out group is replaced elsewhere. |
| Raider raids on player bases (`RaidsEnabled`) | on | Raiders may send scouts, then raid a player base. |
| Days between two raids (`RaidDays`) | 14 | Minimum game days between two raids, and before the first. |
| Hours before a revenge (`RevengeDelayHours`) | 72 | Game hours between an oath of revenge and the departure of the first team. |

Combat and alert distances (in squares) can also be tuned: zombie alert distance (10), alert reach (20), alert shout
radius (10), flee distances (4, 8 when afraid), zombie engage distance per role (10), home defense radius (8),
withdraw ratio (3), retreat danger distance (8), reinforcement radius (15), warning radii around the home (14) and a
member (10), wounded threshold (50 % health) and afraid threshold (fear 70).

## Recommended for a public server

- Keep `MaxPerHour` low enough for your budget and **never 0**.
- Set a spending limit at your AI provider: [AI provider configuration](08-ai-provider-configuration.md).
- `InitiativeFrequency` on Rare if the NPC chatter costs too much.
