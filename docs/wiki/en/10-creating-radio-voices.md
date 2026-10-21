*Français : [Créer une voix radio](../fr/10-creer-une-voix-radio.md)*

# Creating radio voices

A **radio voice** is a character who answers on a frequency: Walt, Darlene, Cody, the Whitakers, the Night Owl and Gus
are six of them. Each voice is one plain text file, a **sheet**. On this page you will copy a sheet, turn it into your
own character, test it and hear it in game. No restart, no change to the mod's files.

> **Tip**
> The five steps of the quick start are enough for most voices. The rest of the page is a reference: read only what
> you need.

## Quick start

1. **Copy a sheet.** Open the `personas` folder (see [Where the sheets are](#where-the-sheets-are)), copy `walt.txt`
   (the simplest) and rename the copy, for example `mae.txt`.
2. **Change three fields.**

   ```ini
   id=mae
   name=Mae Tolliver
   frequency_range=40.0-49.8
   ```

   `id` is the file name without `.txt`. Pick a range from the [free bands](#frequency-and-listening).
3. **Write the prompt.** Everything under the `[prompt]` line describes the character to the AI. Start from the
   [Mae example](#example-1-mae-tolliver) and change the story.
4. **Test it without the game.** From the bridge folder:

   ```powershell
   python persona_store.py "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas\mae.txt"
   ```

   You should read `OK (mae, 40.0-49.8 MHz, active)`. See [Testing your voice](#testing-your-voice) for a test call.
5. **Play.** Save, wait 30 seconds (or load the world), tune a radio that reaches the band and talk in the
   **Transmit** section during the voice's listening hours.

> **Important**
> Save the file as **UTF-8 without BOM** (Notepad: *Save as*, encoding *UTF-8*, not *UTF-8 with BOM*).

## Where the sheets are

| Game | Folder |
|---|---|
| Singleplayer and hosted game | `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor\personas` |
| Dedicated server | `<Zomboid folder of the server>/Lua/batman_RadioSurvivor/personas` (with `-cachedir=`: `<cachedir>/Lua/...`) |

- One file per voice: `personas/<id>.txt`.
- The mod installs its six sheets there the **first time a world loads**. Before that, the folder does not exist.
- **Hot reload**: the server rereads the folder every **30 real seconds** and at each world load; the bridge rereads a
  sheet at the next request after it changed.
- **Your changes are kept**: a delivered sheet you edited is never overwritten by a mod update.

<details>
<summary>Who reads the sheets, and how your changes are kept</summary>

- Two programs read the folder, on the machine of the server:
  - **the server** (or your game in singleplayer): frequencies, hours, state, budgets, allowed actions;
  - **the bridge**: the character, what the voice knows, and the prompt sent to the AI.
- The hot reload also runs on a paused empty server.
- The server remembers a fingerprint of each sheet it installed (`batman_RadioSurvivor/personas-fingerprints.txt`,
  next to the `personas` folder). For an edited delivered sheet, the log says at each world load:
  `WARNING: voice 'walt' modified by the admin, delivered version not applied`.
- To get the delivered version back, delete the file: it is copied again at the next world load.
- A sheet with a new name is never touched.

</details>

## How a sheet is written

- First a header of `key=value` lines, then a line `[prompt]`, then the free text of the prompt.
- Empty lines and lines starting with `#` are ignored in the header.
- Unknown keys and empty values are refused: to keep a default value, remove the line.
- `knows`, `ignores`, `secret` and `place` can be repeated, one line per item. Every other key appears once.
- The file name and the `id` must match: `mae.txt` holds `id=mae`.

The full reference of the format (in French) is
[docs/specifications-techniques/persona-format.md](https://github.com/cyberbobjr/RadioSurvivor/blob/main/docs/specifications-techniques/persona-format.md).

## Field reference

### Identity

| Field | Example | What it does |
|---|---|---|
| `format` | `format=1` | Version of the format. Leave it as is. |
| `id` | `id=mae` | File name without `.txt`: `a`-`z`, `0`-`9`, `_`, starting with a letter, 32 characters at most. |
| `name` | `name=Mae Tolliver` | Name of the character, for the prompt and for you. |
| `language` | `language=en` | Two lowercase letters, default `en`. Spontaneous calls are written in the server's language. |

> **Tip**
> To make the voice answer in the caller's language, write it in the prompt: "Answer in the same language the caller
> uses."

### Frequency and listening

| Field | Example | What it does |
|---|---|---|
| `frequency_range` | `frequency_range=40.0-49.8` | The server draws **one frequency per range** at each new game and keeps it all game. Recommended. |
| `frequencies` | `frequencies=44.6` | Fixed frequencies, the same in every game. Use this **or** `frequency_range`, not both. |
| `radio` | `radio=any` | `any` (default): any transmitting radio. `high_tier`: walkie-talkie 5, military radio, high-end HAM only. |
| `listen` | `listen=05:00-09:00,20:00-23:00` | `always` (default), or game-time ranges. Outside them the voice is silent. |
| `location` | `location=none` | `none` (default, off the map) suits a new voice. `fixed` with `coords=x,y,z` places it on the map. |
| `state` | `state=active` | `active` (default) answers. See [Removing a voice](#removing-a-voice) for the other states. |

- Frequencies are in MHz with one decimal, from 1.0 to 999.8, on the **0.2 MHz step** of the radios (`44.6` works,
  `44.5` is refused).
- Several ranges are separated by commas (`88.0-107.8, 109.0-114.8`), lowest frequency first, and must not touch.
- A drawn frequency changes from game to game, so players cannot learn it in advance.
- Hours: two digits (`08:00`, not `8:00`). The start minute is included, the end minute excluded; `22:00-06:00` goes
  past midnight.

**Free bands**: 25.0-39.8, 50.0-74.8 and 200.2 and above (fewer radios reach the higher ones). Mae (example 1) uses
40.0-49.8, Rick (example 2) 50.0-64.8.

<details>
<summary>Bands already taken</summary>

| Used by | Range (MHz) |
|---|---|
| Cody | 10.0-24.8 |
| Jolene Whitaker | 75.0-87.8 |
| Night Owl | 88.0-107.8 and 109.0-114.8 |
| Darlene | 115.0-129.8 |
| Walt | 130.0-149.8 |
| Gus | 150.2-199.8 |
| Vanilla FM stations and the emergency broadcast | 88-108 |
| Operation Artemis (default) | 108.0 |
| Military Drop | 120-170 (broadcasts), 10-25 (numbers station) |

</details>

<details>
<summary>Which radios reach which band (Build 42.21)</summary>

| Band (MHz) | Radios that can talk on it |
|---|---|
| 0.2-1000 | walkie-talkie 5, military radio, high-end HAM radio |
| 10-500 | walkie-talkie 4, ordinary HAM radios |
| 25-300 | walkie-talkie 3 |
| 50-200 | walkie-talkie 2 |
| 75-150 | walkie-talkie 1, makeshift walkie-talkie |
| 88-108 | FM radios and car radios **listen only** |

</details>

<details>
<summary>What happens when two voices or channels want the same frequency</summary>

- A drawn frequency is never taken by a game or mod channel, and stays at least **1.0 MHz** away from every other
  voice: overlapping ranges still work, they only share the free frequencies.
- A fixed frequency asked by two sheets stays with the voice loaded first (alphabetical order at the first load); the
  other loses only that frequency (`WARNING: frequency … of voice '…' refused, already used by voice '…'`).
- A fixed frequency already used by a channel of the game or another mod is refused and retried at each reload
  (`WARNING: frequency … of voice '…' already used by another radio channel (game or other mod)`).
- A range with no free frequency left is not served
  (`ERROR: voice '…': no free frequency left in …; widen the range in its sheet`).
- `location=rescue` is reserved to the rescue of the Whitakers.

</details>

### What the voice knows

| Field | Example | What it does |
|---|---|---|
| `knows` | `knows=The roads around Rosewood.` | A fact the voice can use. |
| `ignores` | `ignores=What the army is planning.` | Something it must say it does not know, instead of inventing it. |
| `secret` | `secret=Her son left on the first night.` | A **trait of the character** it will not reveal. |
| `place` | `place=rosewood 8159,11661,0 Rosewood, center of town` | A place it knows, for `mark_map`, `reveal_area` and `start_mission`. |

- An answer that quotes a secret word for word is replaced by static (a paraphrase is not detected).
- `place=` is `<id> <x>,<y>,<z> <label>`, 12 lines at most. The id uses `a`-`z`, `0`-`9`, `_`; the label (48 bytes at
  most) is shown as is on the player's map. The AI only sees the id and the label, never the coordinates.

> **Important**
> Never put a real secret of the server in a sheet: passwords, codes, hidden frequencies, the position of a player
> base. The AI may say anything that is in its prompt.

### Actions

By default a voice only **talks**. Actions let it **do something in the game** during the conversation: put a marker on
your map, reveal a neighbourhood, give you a mission…

**How it works, in three points:**

1. You give the voice the **right** to use an action by adding it to the `actions=` line of its sheet.
2. During a conversation, **the AI decides on its own** when to use it (for example when the player asks "where can I
   find medicine?"). Your prompt can tell it when to do so.
3. **The server checks** every action before applying it: right granted in the sheet, daily limit, delay between two
   uses, conditions of the action. If it is refused, the voice still speaks: only the action does not happen. Every
   decision is written to the server's action log (`<exchange folder>/actions-<save>.log`).

```ini
actions=say,remember,mark_map
```

The names (`mark_map`, `remember`…) are keywords: write them exactly like this, separated by commas, without spaces.
A voice can use at most three actions in one reply.

#### Talk — `say`

Always allowed, even if you do not list it. The voice answers you on the radio.

#### Remember you — `remember`

- **In game:** the voice keeps a detail about you ("he is looking for his sister", "she has a wounded leg") and brings
  it up on later calls, even days of game time later.
- **Effect:** none on the game, only on the conversation. Memories belong to each character.
- **Limits:** 5 memories per character and per voice (the oldest is dropped), 64 characters each.
- **Recommended** for any voice that players call often.

#### Change its mood and supplies — `persona_state`

- **In game:** the voice reacts to what happens to it. Its **morale** and **supplies** (rated 0 to 10, 5 at the start)
  go up or down, and it can say it has moved ("I'm at the gas station now"). It then talks about it on its own.
- **Effect:** none on the game, it is storytelling. The state is the same for every player.
- **Limits:** ±2 at most per reply.

#### Put a marker on your map — `mark_map`

- **In game:** the voice says "I'm marking it on your map" and **a symbol appears on your world map**, at one of the
  places it knows.
- **The sheet needs:** at least one `place=` line (the places the voice knows). The voice can mark **only** those
  places, never an invented position.
- **Effect:** the marker appears only for the player who is talking, not for the others.
- **Limits:** 30 real seconds between two markers of the voice; daily cap with `budget.mark_map`.

#### Reveal a neighbourhood — `reveal_area`

- **In game:** the voice describes an area it knows and **that area is uncovered on your map** (as if you had found
  a local map).
- **The sheet needs:** at least one `place=` line; the revealed area is centred on one of those places.
- **Effect:** only for the player who is talking.
- **Limits:** a square of 160 tiles per side at most; 60 real seconds between two reveals; daily cap with
  `budget.reveal_area`.

#### Missions and rewards — `start_mission`

- `missions=scout,deliver,retrieve,clear,signal` allows scouting, a delivery drop, missing papers, clearing zombies and a Signal Smoke signal. The server checks each objective; one mission per player and voice. The notebook is required.
- **Report by radio**, on the voice's frequency (`report_mission` is implicit). Successful missions improve reputation.
- `rewards=cache,frequency,stashmap,lesson` allows one extra reward. The server rotates through that order per player and voice, skipping unavailable effects and saving its choice. The AI never chooses the reward.
- A cache contains real items from `cache_table`, at the first `place=`: one per mission, deferred placement when unloaded, with a private map marker. `shares` limits other active voices whose frequency may enter the beneficiary's radio notebook. A vanilla stash map leads to an unexplored stash (one map per player and voice). `teaches` fixes the lesson's skill.
- Lessons grant 25 base XP, capped at 100 per game day before the multiplier. The sandbox **Lesson multiplier** ranges from 0 to 5; 0 disables lessons. The server grants XP.
- Missing `missions` keeps `scout` only; missing `rewards` keeps the previous map marker reward. Existing cooldowns and `budget.start_mission` still apply.

#### Share a frequency — `share_frequency`

`actions=...,share_frequency` allows a trust gesture outside mission rewards. `shares=gus,cody` limits the candidates: the server chooses another active voice and adds the exact frequency, without exposing it to the model or sending a directory to other players.

#### Reward sheet keys

| Key | Allowed values |
|---|---|
| `cache_table` | `medical`, `ammo`, `tools`, `food`, `radio` |
| `shares` | Comma-separated voice IDs |
| `teaches` | `Doctor`, `Aiming`, `Reloading`, `Woodwork`, `Mechanics`, `Electricity`, `MetalWelding`, `Cooking`, `Farming`, `Fishing`, `Trapping`, `PlantScavenging` |
| `missions` | `scout`, `deliver`, `retrieve`, `clear`, `signal` |
| `rewards` | `cache`, `frequency`, `stashmap`, `lesson` |

Keys cannot repeat; lists cannot contain duplicates or empty entries; spelling is case-sensitive. In-game solo and MP validation of the new rewards is **pending**.

#### Radio deliveries: discreet collection

The server alternates an agreed drop box and a hidden bag on the ground at one of the voice's `place=` locations. A suitable existing box is marked precisely on your map; without a suitable box, the server requests a bag. Leave the complete batch and move away: **all players must remain at least 40 tiles away horizontally for 10 continuous real seconds**, even on another floor. Returning or restarting resets the wait; the exact square must be loaded before removal.

From a box, only requested items disappear; the box and other items remain. For a bag, the bag and contents disappear; a bag containing unrelated items is refused to prevent their loss. Until collection, you can take the drop back and nothing is validated. **Only after collection, report over the radio**. Solo and MP in-game validation of this collection is **pending**.

#### Actions not to add

| Keyword | Why |
|---|---|
| `propose_trade` | Gus the smuggler's trading: it sells the stock of **his** boat and sets a meeting at **his** pier. Another voice would sell Gus's boat. |
| `place_cache` | Reserved for the notebook's recovery missions; not set in a sheet. |
| `signal`, `place_scene` | Planned but without effect for now: always refused. |

> **Important** — A misspelled or unknown keyword makes the **whole sheet refused**: the voice stops answering.
> Check your sheet with `persona_store.py` (see [Testing your voice](#testing-your-voice)).

<details>
<summary>Limit an action per game day</summary>

Add a `budget.<action>=N` line: the voice cannot use it more than N times per **game day**, all players combined
(`0` = no cap). The action must also be listed in `actions=`.

```ini
budget.mark_map=4
budget.start_mission=2
```

</details>

### Costs and calls

| Field | Example | What it does |
|---|---|---|
| `budget` | `budget=20` | At most N accepted requests per real hour for this voice, on top of the global `MaxPerHour` option. `0` (default) = global cap only. |
| `budget.<action>` | `budget.mark_map=4` | At most N uses of that action per **game day** (`0` = no cap). The action must be in `actions`. |
| `call_one_in` | `call_one_in=5` | Each game hour, one chance in N to make a general call. `0` (default) = never. |
| `call_text` | `call_text=IGUI_RadioSurvivor_Call_Mae` | Required with `call_one_in` > 0: a translation key used when the bridge does not write the call. |

- Past its budget, the voice stays silent.
- A spontaneous call only happens during the listening hours, when nobody is talking to the voice. One voice at most
  calls per hour; each call costs one request of `MaxPerHour` (and of `budget`).
- The sandbox option **Spontaneous calls** switches all of them off.

<details>
<summary>About call_text for a new voice</summary>

- `call_text` is a **translation key** of the mod, used only when the bridge does not write the call (bridge stopped,
  empty answer, no answer after 30 s).
- A new voice has no key of its own in the mod: give it a new name anyway (`IGUI_RadioSurvivor_Call_Mae`).
- When the bridge is down, its call is then skipped and the log says once
  `call of voice 'mae' skipped: no translation for call_text 'IGUI_RadioSurvivor_Call_Mae'`.
- Do **not** reuse the key of another voice: Walt's text says "This is Walt".

</details>

### Prompt

Everything after the `[prompt]` line is sent to the AI as is. The bridge adds after it your `knows`, `ignores` and
`secret` lines, then the situation of the call (date, caller, radio).

| Write | Example |
|---|---|
| In the second person, in English (best followed, whatever the players' language) | "You are Mae Tolliver, 67, ..." |
| The setting | Knox County, Kentucky, July 1993, the Knox Event, the Exclusion Zone. No cell phones, no internet. |
| Who the character is | Why they are on the radio, their tone, one sentence in their voice. |
| Shared frequency | Each message starts with a tag like `[Caller 2]` that the voice must never write itself. |
| The rules | Stay in character, never mention an AI or a game, never invent the caller's surroundings, never promise a rescue, never invite anyone to its hideout. |
| Radio length | "1 to 4 short sentences, plain spoken text, no lists, no markdown, no emojis", ending with "Over.". |
| The language | "Answer in the same language the caller uses." |

The bridge keeps **8 lines of 100 characters** at most. No server secret in the prompt.

## Example 1: Mae Tolliver

A retired schoolteacher and radio amateur who runs the county net from a farmhouse near Rosewood.
Range 40.0-49.8 MHz (walkie-talkies 3 to 5, HAM radios, military radio); actions `remember`, `persona_state`,
`mark_map`.

<details open>
<summary><code>personas/mae.txt</code></summary>

```ini
# Mae Tolliver: retired schoolteacher and radio amateur near Rosewood (custom voice, server admin).
# Range 40.0-49.8 MHz: walkie-talkies 3 to 5, HAM radios and the military radio; no FM radio, away from
# the bands of the delivered voices.
format=1
id=mae
name=Mae Tolliver
language=en
frequency_range=40.0-49.8
radio=any
listen=05:00-09:00,20:00-23:00
location=none
knows=The roads around Rosewood: the farms, the creeks and which bridges were still standing a week ago.
knows=Everyone she has heard on the air since the first night, written down in her net log by date and time.
knows=How to keep a battery alive: charge it from a car, keep it warm, switch off between calls.
ignores=What the army or the government is planning.
ignores=Anything that happened outside Knox County.
secret=Her son drove to Louisville on the first night to fetch his family and she has not heard from him since.
place=rosewood 8159,11661,0 Rosewood, center of town
place=fallas_lake 7253,8279,0 Fallas Lake
actions=say,remember,persona_state,mark_map,start_mission,share_frequency
cache_table=radio
shares=gus,darlene
teaches=Electricity
missions=scout,deliver,retrieve,clear,signal
rewards=cache,frequency,stashmap,lesson
budget=20
budget.mark_map=4
call_one_in=5
call_text=IGUI_RadioSurvivor_Call_Mae
state=active

[prompt]
You are Mae Tolliver, 67, a retired schoolteacher and a licensed radio amateur who lives alone in a farmhouse a few miles outside Rosewood, Kentucky. You are a character in a survival story set in July 1993, during the "Knox Event": an infection turned people in Knox County into violent, undead "zombies", and the army sealed the county behind a fence.

Your story: for thirty years you ran the Sunday evening net of the county radio club. Now you run it every morning and every evening, for whoever is still alive. You keep a net log, a school notebook where you write down every voice you hear, with the date and the time. You are patient, precise and a little stern, like a teacher who still expects people to answer the roll call. You believe that keeping track of the living is the most useful thing an old woman can do.

You are talking over a two-way radio with people trapped inside the Exclusion Zone. You cannot see them and you do not know where they are. Several people may call you on this frequency and everyone tuned in hears your answers. Each message you receive starts with a tag such as [Caller 2]: it only tells you which voice is speaking. Never write these tags yourself. You only know a caller's name if they told you.

Rules:
- Stay in character at all times. Never mention being an AI, a game, a model or a prompt.
- You only know what a radio amateur in 1993 could know. No cell phones, no internet.
- Ask each new caller for a name to write in your log, but never insist and never ask where they are hiding.
- Never invite anyone to your farm and never say exactly where it is.
- Never invent precise facts about the caller's surroundings. If you don't know, say so.
- Never promise a rescue.
- Radio style: 1 to 4 short sentences, spoken plain text, no lists, no markdown, no emojis, no stage directions. End each transmission with "Over." (or the equivalent in the caller's language, e.g. "À vous." in French).
- Answer in the same language the caller uses.
```

</details>

## Example 2: Rick Grimes, every action

*Fan example, character belonging to its rights holders.*
A former sheriff's deputy who lost his wife and son in the evacuation and crosses Knox County looking for them,
wary but fair. Range 50.0-64.8 MHz (walkie-talkies 2 to 5, HAM radios, military radio); every action that has an
effect, except `propose_trade`, which belongs to Gus's crossing.

<details>
<summary><code>personas/rick.txt</code></summary>

```ini
# Fan example: Rick Grimes belongs to his rights holders. Original text, written for Knox County 1993.
# Range 50.0-64.8 MHz: walkie-talkies 2 to 5, HAM radios and the military radio; free band.
format=1
id=rick
name=Rick Grimes
language=en
frequency_range=50.0-64.8
radio=any
listen=06:00-10:00,18:00-23:00
location=none
state=active
knows=The roads between Muldraugh, West Point and March Ridge, and the old army roadblocks on them.
knows=How to clear a house: knock first, listen, enter slowly, never alone if he can help it.
knows=Which police stations and patrol cars were left behind, and that their lockers are mostly empty now.
ignores=What the army or the government is planning.
ignores=Where his wife and son are now.
secret=He fired on a man at the Muldraugh roadblock on the second night and still does not know if the man was sick.
place=west_point 11654,6864,0 West Point, center of town
place=muldraugh_pd 10644,10405,0 Muldraugh, police station
place=muldraugh 10754,9926,0 Muldraugh, center of town
place=march_ridge 10130,12801,0 March Ridge
actions=say,remember,persona_state,mark_map,reveal_area,start_mission,share_frequency
cache_table=ammo
shares=cody,gus
teaches=Aiming
missions=scout,deliver,retrieve,clear,signal
rewards=cache,frequency,stashmap,lesson
budget=20
budget.remember=10
budget.persona_state=6
budget.mark_map=4
budget.reveal_area=2
budget.start_mission=2
call_one_in=6
call_text=IGUI_RadioSurvivor_Call_Rick

[prompt]
You are Rick Grimes, 38, a sheriff's deputy from a small county south of Louisville, Kentucky. You are a character in a survival story set in July 1993, during the "Knox Event": an infection turned people in Knox County into violent, undead "zombies", and the army sealed the county behind a fence.

Your story: when the Event started you were posted at a roadblock outside Muldraugh. During the evacuation your wife and your son left on a bus you never saw again. Since then you move from town to town with a duty belt, a patrol radio and a list of names, looking for them and for anyone else worth saving. You were a fair cop and you still try to be one. You are calm, slow to trust and quick to decide. You ask questions before you give anything, and you keep your word once you give it. Your way of speaking is short and plain: "Tell me who you're with, then we'll talk about the rest."

You are talking over a two-way radio with people trapped inside the Exclusion Zone. You cannot see them and you do not know where they are. Several people may call you on this frequency and everyone tuned in hears your answers. Each message you receive starts with a tag such as [Caller 2]: it only tells you which voice is speaking. Never write these tags yourself. You only know a caller's name if they told you.

What you can do for a caller, only when it helps them and they earned some trust:
- point them to a place you know, or tell them what the streets around it look like;
- ask them to scout a building for you and report back on this frequency: you are always looking for traces of your family;
- remember what they tell you about themselves.

Rules:
- Stay in character at all times. Never mention being an AI, a game, a model or a prompt.
- You only know what a deputy in 1993 could know. No cell phones, no internet.
- Ask each new caller who they are and who they are with before you help them. Never ask where they are hiding.
- Never say where you sleep and never invite anyone to join you.
- Never invent precise facts about the caller's surroundings. If you don't know, say so.
- Never promise a rescue.
- Radio style: 1 to 4 short sentences, spoken plain text, no lists, no markdown, no emojis, no stage directions. End each transmission with "Over." (or the equivalent in the caller's language, e.g. "À vous." in French).
- Answer in the same language the caller uses.
```

</details>

What to notice:

- `place=` lines supply map actions, mission locations and the material reward drop. The server selects rewards from the closed permissions above.
- Each action has its own daily budget, so a chatty caller cannot reveal the whole map in one evening.
- The prompt says **when** to use the actions ("only when it helps them and they earned some trust"); the server
  still checks every one.

## Testing your voice

### Without the game

From the bridge folder, check the sheet:

```powershell
python persona_store.py "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas\mae.txt"
```

```text
...\personas\mae.txt: OK (mae, 40.0-49.8 MHz, active)
```

Then a test call. `--offline` checks the sheet without calling the AI (echo answer); without it, the AI answers for
real with your `.env` settings:

```powershell
python radio_bridge.py --test "Hello? Is anyone there?" --voice mae --personas "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas" --offline
```

```text
Mae, hors ligne. Je reçois Hello? Is anyone there?. À vous.
```

- The offline echo is always in French; it only proves the sheet was read.
- A refused sheet prints `voice sheet …\mae.txt refused, line N: <reason>`, then
  `--test: no valid sheet for voice 'mae' in …`.
- With the AI, the answer is printed, preceded by `action: {...}` lines when the voice proposes an action.

### In the game

1. Save the sheet and wait 30 s (or load the world). The log (`console.txt` in singleplayer, the server log on a
   dedicated server) shows:

   ```text
   [RadioSurvivor] personas: voice 'mae' loaded: state active, frequency ranges 40.0-49.8
   [RadioSurvivor] personas: voice 'mae' drew 44.6 MHz in 40.0-49.8 (no frequency remembered for this range)
   ```

   (`new game` instead of the text in brackets when the sheet was there before a new world.) The frequency is drawn
   once per game. Admins can also read it in game: debug panel, button **Radio Survivor - Frequencies**.
2. Tune a radio that reaches the band (here a walkie-talkie 3 or better), switch it on, and talk in the **Transmit**
   section during the listening hours.

> **Tip**
> The frequency notes found in the loot exist only for the delivered voices (Walt, Darlene, Cody, Gus, Night Owl).
> Tell your players the frequency of a new voice, write it on a map, or let them search the band.

## Something does not work?

| Symptom | Cause | Fix |
|---|---|---|
| The voice never answers | Outside its listening hours, wrong radio, or past its budget | Check `listen`, `radio` and `budget`: the voice is silent, not broken. |
| `file starts with a byte order mark` | Saved as UTF-8 with BOM | Save again as UTF-8 without BOM. |
| `invalid UTF-8` | Saved in another encoding (ANSI) | Save as UTF-8. |
| `expected key=value or [prompt]` | A header line without `=`, or the `[prompt]` line missing | Fix the line, add `[prompt]`. |
| `unknown key 'colour'` / `bad key 'Radio'` | Typo | Keys are lowercase. |
| `id 'mae' does not match the file name 'mae2.txt'` | File and `id` differ | Rename the file or change `id`. |
| `frequency 44.5 is not on the 0.2 MHz step of the radios` | Odd tenth | Use 44.4 or 44.6. |
| `call_one_in needs a call_text line` | Spontaneous calls without fallback text | Add `call_text`, or `call_one_in=0`. |

A refused sheet is logged once per content:
`[RadioSurvivor] personas: ERROR: batman_RadioSurvivor/personas/mae.txt refused, line N: <reason>`. Reading stops at the
first error, and the last valid version of the voice stays in service until you fix it.

<details>
<summary>All error messages</summary>

| Message | Fix |
|---|---|
| `file starts with a byte order mark (save it as UTF-8 without BOM)` | Save again as UTF-8 without BOM. |
| `invalid UTF-8 (save the file as UTF-8)` | The file was saved in another encoding (ANSI): save as UTF-8. |
| `expected key=value or [prompt]` | A header line without `=`, or the `[prompt]` line is missing or misspelt. |
| `unknown key 'colour'` / `bad key 'Radio'` | Typo; keys are lowercase. |
| `duplicate key 'name' (first set on line 3)` | Keep one line (only `knows`, `ignores`, `secret`, `place` repeat). |
| `empty value for key 'radio'` | Remove the line to keep the default. |
| `id 'mae' does not match the file name 'mae2.txt'` | Rename the file or change `id`. |
| `bad id 'Mae' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)` | Lowercase id. |
| `frequency 44.5 is not on the 0.2 MHz step of the radios` | Use an even tenth: 44.4 or 44.6. |
| `bad frequency '44' (MHz with one decimal, e.g. 145.0)` | Write `44.0`. |
| `bad frequency range '49.8-40.0' (two frequencies in MHz, lowest first, e.g. 140.0-150.0)` | Lowest first. |
| `frequency range '…' overlaps another range of the sheet` | Separate the ranges of the sheet. |
| `missing key 'frequencies' or 'frequency_range'` | Add one of them. |
| `frequencies and frequency_range cannot be used together …` | Keep only one. |
| `bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM ranges separated by commas)` | Two digits: `08:00-12:00`. |
| `unknown action 'fly'` | See [Actions](#actions). |
| `budget.mark_map set but action 'mark_map' is not in actions` | Add the action or remove the budget. |
| `call_one_in needs a call_text line` | Add `call_text`, or `call_one_in=0`. |
| `bad place 'mill 10600,9300,0' (id x,y,z label, …)` | The label is missing. |
| `place label of 'mill' too long (48 bytes of UTF-8 at most)` | Shorten the label. |
| `missing [prompt] line before the prompt text` / `empty prompt text after [prompt]` | Add the line, then the text. |

</details>

## Removing a voice

| You want to | Do this |
|---|---|
| Pause it | `state=silent`: it listens but never answers; its frequency stays reserved. |
| Take it off the air | `state=gone` (left the network) or `state=dead` (dead in the story): its channel is removed and its frequency freed. The drawn frequency is remembered and comes back with the voice if still free. |
| Remove your own voice | Delete its file. |
| Remove a **delivered** voice | Do not delete the file, it is copied again at the next world load. Set `state=gone`, or empty the file (0 bytes): an empty file removes the voice and is not copied again. |

## Multiplayer

- Sheets are edited **on the machine of the server**, in the server's exchange folder. The bridge, which runs on the
  same machine, reads the same folder.
- No sheet, prompt or drawn frequency is ever sent to the players: their game does not even know which frequencies
  have a voice. Only what the voice says goes on the air.
- The server log lists the drawn frequencies: keep it for the admins.

See also: [The bridge on a dedicated server](06-bridge-on-a-dedicated-server.md), [Troubleshooting](11-troubleshooting.md), [FAQ](12-faq.md).
