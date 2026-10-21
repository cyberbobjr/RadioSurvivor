*Français : [Installation et configuration](../fr/02-installation-et-configuration.md)*

# Installation and configuration

Four steps take you from the Workshop to a game where the voices and the survivors speak. Each step has its own page.

## 1. Install the mods

Subscribe to Radio Survivor and its three required mods (Belt Walkie-Talkie, TooltipLib, Signal Smoke), enable them in
the right order and restart the game: [Installation](04-installation.md).

## 2. Start the bridge

The bridge is a small Python program that carries the requests of the game to the AI and brings the answers back. It
runs on the machine of the server: your PC in singleplayer or in a game hosted from the menu, the server machine for a
dedicated server.

- Singleplayer and hosted game: [The bridge in singleplayer](05-bridge-in-singleplayer.md).
- Dedicated server (Windows, Linux, Docker): [The bridge on a dedicated server](06-bridge-on-a-dedicated-server.md).

Without the bridge the game stays playable: the voices answer with static and the NPCs stay silent.

## 3. Choose the AI provider

Any service with an OpenAI-compatible API works (three settings: address, model, key). Choice, cost and quotas:
[AI provider configuration](08-ai-provider-configuration.md).

## 4. Set the sandbox options

The sandbox settings of a new game have two pages, **Radio Survivor** and **Living Knox**: voices, message limits,
frequency notes, number and kind of survivor groups, their behaviour. Every option is described in
[Sandbox options](09-sandbox-options.md).

*Screenshots taken in a French game: the option names are those of the [Sandbox options](09-sandbox-options.md) page.*

![Sandbox page Radio Survivor](../../images/screenshots/fr-sandbox-rs.png)

![Sandbox page Living Knox](../../images/screenshots/fr-sandbox-lk.png)

## Check in game

Once in the world:

1. take a walkie-talkie in hand, tune it to the frequency of Walt (note found in the loot) and type a sentence in the
   **Transmit** section: Walt answers within a few seconds;
2. the **Notebook** button of the left bar opens the notebook.

![Transmit section and the answer of Walt](../../images/screenshots/en-radio-transmit.png)

Nothing answers? See [Troubleshooting](11-troubleshooting.md). Next: the player guide, [Usage](03-usage.md).

## Going further: your own voices

Every voice is a text sheet on the server machine that you can edit, or copy to create a new voice, without a
restart: [Creating radio voices](10-creating-radio-voices.md).
