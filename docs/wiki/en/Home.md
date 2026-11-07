*Français : [Accueil](../fr/Home.md)*

# Radio Survivor

Radio Survivor is a Project Zomboid **Build 42.21** project, singleplayer and multiplayer, published as **one Workshop
item with three mods**. Knox County, July 1993: voices answer on the radio, and groups of human survivors live, fight
and fortify in the county.

> **Test version.** Expect bugs and balance changes. Start a new game and keep a backup of any save you care about.

## The three mods

| Mod | Mod ID | Brings |
|---|---|---|
| Radio Survivor | `batman_RadioSurvivor` | The radio: six AI voices, the Radio tab of the notebook, factions |
| Living Knox | `batman_LivingKnox` | Groups of NPC survivors: homes, needs, routines, fights |
| Radio Survivor Core | `batman_RadioSurvivorCore` | What both share: missions and their journal, link with the bridge, identity, conversation history, reputation, the notebook. Enabled for you; useless alone |

Tick **Radio Survivor**, **Living Knox** or **both**: each works without the other (the Core is always added). Details
and the load order: [Installation](04-installation.md).

## What the mods add

- **Voices on the radio** (Radio Survivor): Walt, a nurse, a deserter, a besieged family, a pirate station and a
  smuggler, each on a real frequency drawn for each game. Their frequencies are found on notes in the loot. You talk
  to them with any transmitting radio held in hand or worn on the back (**Transmit** section of the radio window).
  They are played by an AI and remember you.
- **Field notebook** (**Notebook** button): contacts, missions, rewards, reputation, and with Radio Survivor the radio
  history by frequency.
- **Living Knox survivor groups** (Living Knox): 3 to 5 groups of human NPCs with a home, a leader, real supplies,
  needs and routines. They defend and fortify their home, fight zombies and keep living off screen. Settlers,
  neutrals and raiders.
- **Missions**: deliver, scout, find a missing person, clear a place, recover a stash, signal. The server checks every
  objective.
- **Rescue** of a besieged family, **the Ohio smuggler** (trades by radio), **evening chronicle** of the server,
  **last pages** of the dead, **reputation** (Radio Survivor).

The server decides everything: the AI only writes words and picks from closed lists.

## The bridge

The AI is reached through **the bridge**, a small Python program you start yourself on the machine that runs the
server (your PC in singleplayer). It is the same program for any choice of mods. Without it the game stays playable,
and the voices and NPCs stay silent.

## Pages

- [Presentation](01-presentation.md): the mods in pictures.
- [Installation and configuration](02-installation-and-configuration.md): from the Workshop to a game where everyone speaks.
- [Usage](03-usage.md): step-by-step player guide (radio, Ctrl+G, missions, notebook, admin tools).
- [Installation](04-installation.md): which mods to tick, required mods, load order, first game.
- [The bridge in singleplayer](05-bridge-in-singleplayer.md)
- [The bridge on a dedicated server](06-bridge-on-a-dedicated-server.md)
- [AI provider configuration](08-ai-provider-configuration.md)
- [Sandbox options](09-sandbox-options.md)
- [Creating radio voices](10-creating-radio-voices.md): edit a voice or add your own.
- [Troubleshooting](11-troubleshooting.md)
- [FAQ](12-faq.md)
