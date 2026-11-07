*Français : [Présentation](../fr/01-presentation.md)*

# Presentation

Radio Survivor brings other survivors into Knox County, July 1993: **voices on the radio**, a **field notebook** that
keeps track of everyone you meet, and **Living Knox**, groups of human survivors who live, fight and fortify their
homes. Singleplayer and multiplayer, Project Zomboid **Build 42.21**.

It is one Workshop item with **three mods**: **Radio Survivor** (`batman_RadioSurvivor`: the radio and its voices),
**Living Knox** (`batman_LivingKnox`: the NPC groups) and **Radio Survivor Core** (`batman_RadioSurvivorCore`: what the
two share, enabled for you). You can play with Radio Survivor, with Living Knox, or with both
([which mods to tick](04-installation.md)). This page describes everything; each part tells which mod brings it.

The voices and the NPCs speak through an AI model, reached by a small program, **the bridge**
([Installation and configuration](02-installation-and-configuration.md)). The game server decides everything that happens:
the AI only writes the words and picks from closed lists.

## Voices on the radio (Radio Survivor)

Six voices answer on real frequencies drawn for each game: Walt the old radio amateur, a nurse, a deserter, a
besieged family, a pirate station and a smuggler. Each one has its own story, its listening hours and its memory of
you.

Take a transmitting radio **in hand** (walkie-talkie, HAM radio) or a manpack radio on your back, switch it on, tune
it, open the microphone, and type your sentence in the **Transmit** section of the radio window. The answer comes
back on the radio, like any other broadcast.

![Radio window with the Transmit section and an answer from Walt](../../images/screenshots/en-radio-transmit.png)

![The answer of Walt heard in game, above the player](../../images/screenshots/en-walkie-in-hand.png)

The frequencies are never given for free: they are written on notes found in the loot (radio log page, patient card,
National Guard notice, scribbled note, flyer). Read the note to learn where to listen.

![Frequency note of Walt](../../images/screenshots/en-frequency-note.png)

## The notebook

The **Notebook** button of the left bar opens the field notebook of your character. The Core holds the notebook, so it
exists with either mod. It keeps:

- **Contacts**: everyone you spoke to, their group, their temperament, the conversations your character heard, your
  private note, and **what they think of you**;
- **Missions**: offers and missions in progress, their objective, deadline and reward;
- **Radio** (Radio Survivor): the history of each frequency you listened to;
- **Reputation**: your reputation among the survivors and what people remember of your acts.

![Notebook, Contacts tab](../../images/screenshots/en-notebook-contacts.png)

## Living Knox (Living Knox)

Living Knox fills the county with 3 to 5 groups of human survivors: settlers, neutrals and raiders. Each group has a
home, a leader, real supplies, needs and routines. Its members defend and fortify their home, fight zombies, go on
expeditions and keep living while you are far away.

![A Living Knox group at its home](../../images/screenshots/en-group-home.png)

Walk up to a survivor and talk: they answer in a speech bubble, in their own voice, and remember the conversation.
With Radio Survivor you select them with **Ctrl+G** and speak through the notebook; with Living Knox alone you speak
in the local chat (`/say`) or with the right-click menu **Talk**.

![A survivor answering in a speech bubble](../../images/screenshots/en-npc-bubble.png)

## Missions and reputation

Survivors and voices ask for help: deliver supplies, scout a place, find a missing person, clear an area, recover a
stash, light a signal. The server checks each objective. Some missions circle an approximate area on your world map.

![Circle of a scouting mission on the world map](../../images/screenshots/en-map-zone.png)

What you do is remembered: missions kept or failed, people rescued or killed. It changes your reputation and the
attitude of each survivor toward you.

## See also

- [Installation and configuration](02-installation-and-configuration.md)
- [Usage](03-usage.md): step-by-step player guide
- [FAQ](12-faq.md)
