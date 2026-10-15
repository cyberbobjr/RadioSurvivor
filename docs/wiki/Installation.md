*Français : [[Installation|Installation-FR]]*

# Installation

## Required mods

| Mod | Mod ID | Workshop ID | Role |
|---|---|---|---|
| Radio Survivor | `batman_RadioSurvivor` | (this mod) | Voices, notebook, Living Knox NPCs |
| Belt Walkie-Talkie | `batman_BeltRadio` | 3817018338 | Walkie-talkie on the belt, common transmit rule |
| TooltipLib | `TooltipLib` | 3694097672 | Required by Belt Walkie-Talkie |
| Signal Smoke | `batman_SignalSmoke` | 3811010882 | Smoke grenades and flares watched by the server (signal mission, smuggler's flare, rescue smoke) |

Without Belt Walkie-Talkie or Signal Smoke, the game does not load Radio Survivor.

**Not compatible** with Bandits! (`Bandits2`) and Project A-Life (`ProjectALifeNPCs`): only one NPC engine per game.
The Build 42 mod selector shows the conflict.

## Singleplayer

1. Subscribe to the four mods on the Steam Workshop.
2. In the main menu, **Mods**: enable them in this order: **TooltipLib, Belt Walkie-Talkie, Signal Smoke, Radio
   Survivor**.
3. Restart the game completely after installing or updating the mods.
4. Start a **new game** (recommended for this test version). The sandbox pages **Radio Survivor** and **Living Knox**
   hold the options ([[Sandbox options|Sandbox-Options]]).
5. Start the bridge before loading the game: [[The bridge in singleplayer|Bridge-in-Singleplayer]]. Without it the
   game works, but the voices answer only with static and the NPCs stay silent.

## Multiplayer

- Every player and the server need the **same version** of the four mods.
- Players install nothing else: the bridge runs only on the server machine.
- Dedicated server: see [[The bridge on a dedicated server|Bridge-on-a-Dedicated-Server]] (`WorkshopItems=`, `Mods=`).
- Game hosted from the menu (**Host**): the bridge runs on the host's PC, exactly as in singleplayer.

## First steps in game

- **Radio**: find a frequency note in the loot (right click → **Inspect**), take a walkie-talkie or a HAM radio **in
  hand** (or a radio worn on the back), switch it on, tune it, open the microphone, and type in the **Transmit**
  section of the radio window. Walt is the first voice to look for.
- **NPCs**: near a survivor, press **Ctrl+G** to select them, then speak in the local chat (`/say`). The
  **Notebook** button opens contacts, missions and reputation.
