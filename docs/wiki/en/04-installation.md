*Français : [Installation](../fr/04-installation.md)*

# Installation

## Which mods to enable

One Workshop item holds **three mods**. Subscribe once, then tick in the **Mods** list what you want to play.

| Mod | Mod ID | What it brings | Needs |
|---|---|---|---|
| Radio Survivor | `batman_RadioSurvivor` | The radio: sixteen AI voices (a trader per town among them) on real frequencies, their missions, the Radio tab of the notebook, factions | Core AI, Belt Walkie-Talkie, Signal Smoke |
| Living Knox | `batman_LivingKnox` | Groups of NPC survivors with homes, needs, routines, fights and fortifications; their relations and agreements, the Team tab of the notebook | Core AI. **Not compatible** with Bandits! and Project A-Life |
| Core AI | `batman_CoreAI` | What the two others share: the link with the bridge, the whole notebook (window, Contacts, Missions and Reputation tabs, mission views, map areas), the missions, character identity, the history of conversations, reputation, contacts, teams | Signal Smoke |

- **What to tick**: Radio Survivor, Living Knox, or both. Each one works without the other.
- **The Core** is required by both: the game enables it for you. Enabled alone it adds nothing you can play.
- **The bridge** is the same single program in every case, with no setting to change: it serves the voices of Radio
  Survivor, the NPCs of Living Knox, or both ([The bridge](05-bridge-in-singleplayer.md)).

What changes with your choice:

| You enable | You play |
|---|---|
| Radio Survivor | Voices on the radio, their missions, the notebook with its Radio tab. No NPC groups. |
| Living Knox | NPC groups across the county, with the full notebook (contacts, missions, reputation, team). You talk to an NPC with **Ctrl+G** and the notebook, in the local chat (`/say`) near it, or with the right-click menu **Talk**; it answers in a speech bubble. Relations and agreements with the groups come with it. |
| Both | Everything above, in the same notebook, plus its Radio tab. |

## Required mods

| Mod | Mod ID | Workshop ID | Role |
|---|---|---|---|
| Belt Walkie-Talkie | `batman_BeltRadio` | 3817018338 | Walkie-talkie on the belt, common transmit rule (Radio Survivor only) |
| TooltipLib | `TooltipLib` | 3694097672 | Required by Belt Walkie-Talkie |
| Signal Smoke | `batman_SignalSmoke` | 3811010882 | Smoke grenades and flares watched by the server (signal mission, smuggler's flare, rescue smoke); required by the three mods |

Without Signal Smoke, the game does not load any of the three mods; without Belt Walkie-Talkie, it does not load Radio
Survivor. Living Knox alone does not need Belt Walkie-Talkie or TooltipLib.

**Not compatible** with Bandits! (`Bandits2`) and Project A-Life (`ProjectALifeNPCs`) when Living Knox is enabled: only
one NPC engine per game. The Build 42 mod selector shows the conflict.

## Singleplayer

1. Subscribe to the Radio Survivor item and to the required mods (Belt Walkie-Talkie, TooltipLib and Signal Smoke) on
   the Steam Workshop.
2. In the main menu, **Mods**: enable the mods you chose. Order for all of them: **TooltipLib, Belt Walkie-Talkie,
   Signal Smoke, Core AI, Radio Survivor, Living Knox**.
3. Restart the game completely after installing or updating the mods.
4. Start a **new game** (recommended for this test version). The sandbox pages **Radio Survivor** and **Living Knox**
   hold the options of the mods you enabled ([Sandbox options](09-sandbox-options.md)).
5. Start the bridge before loading the game: [The bridge in singleplayer](05-bridge-in-singleplayer.md). Without it the
   game works, but the voices answer only with static and the NPCs stay silent.

## Multiplayer

- Every player and the server need the **same version** and the **same set** of mods.
- Players install nothing else: the bridge runs only on the server machine.
- Dedicated server: see [The bridge on a dedicated server](06-bridge-on-a-dedicated-server.md) (`WorkshopItems=`, `Mods=`).
- Game hosted from the menu (**Host**): the bridge runs on the host's PC, exactly as in singleplayer.

## First steps in game

- **Radio** (Radio Survivor): find a frequency note in the loot (right click → **Inspect**), take a walkie-talkie or a
  HAM radio **in hand** (or a radio worn on the back), switch it on, tune it, open the microphone, and type in the
  **Transmit** section of the radio window. Walt is the first voice to look for.
- **NPCs** (Living Knox): near a survivor, press **Ctrl+G** to select them, or speak in the local chat (`/say`): a
  sentence without a selected NPC goes to the nearest one within 8 squares. **Talk** in the right-click menu works
  too. The **Notebook** button opens contacts, missions, reputation and team.
