*Français : [Utilisation](../fr/03-utilisation.md)*

# Usage

A step-by-step guide for the player. The bridge must be running for the voices and the survivors to speak
([Installation and configuration](02-installation-and-configuration.md)).

## 1. Find a frequency

The voices are on frequencies drawn for each game. They are written on **notes** found in the loot: radio log page,
patient card, National Guard notice, scribbled note, Night Owl flyer. Each note sits where its voice would leave it
(how often: sandbox option **Frequency notes in the loot**).

Right click the note → **Inspect** (or **Read**) to open it. Walt is the first voice to look for: he answers at any
hour.

![Frequency note of Walt](../../images/screenshots/en-frequency-note.png)

## 2. Talk to a voice on the radio

1. Take a transmitting radio **in hand**: walkie-talkie, HAM radio (or a manpack radio worn on the back).
2. Switch it on and tune it to the frequency of the note.
3. Open the microphone (section **Microphone** of the radio window).
4. Type your sentence in the **Transmit** section at the bottom of the radio window, then press Enter or
   **Transmit**.

![The answer of the voice heard in game, above the player](../../images/screenshots/en-walkie-in-hand.png)

The field is greyed while the voice answers; the answer is played on the radio and shown in the last lines of the
section. Keep it short: a voice that is spoken to without a pause asks you to catch your breath. A walkie-talkie on the
belt receives, but it does not transmit: hold it in hand to speak.

![Transmit section and the answer of Walt](../../images/screenshots/en-radio-transmit.png)

Every voice has its listening hours and remembers you. The **Radio** tab of the notebook keeps what was said on each
frequency.

## 3. Meet a Living Knox group

Groups of survivors live in houses or camps across the county: settlers, neutrals and raiders. A group has a leader,
fighters and workers, a home it barricades, supplies and needs. Approach slowly and do not point a weapon: a group
defends its home, and raiders attack.

![A group at its home](../../images/screenshots/en-group-home.png)

## 4. Speak to a survivor (Ctrl+G)

*This section describes Radio Survivor and Living Knox enabled together. With Living Knox alone there is no Ctrl+G and
no **Talk** button in the notebook: say a sentence in the local chat (`/say`) while you are close to a survivor, or
right click them and choose **Talk**; the nearest survivor answers in a speech bubble, and the missions it offers
appear in the Missions tab of the notebook. Next to the survivor who gave the mission, the **Deliver** button of that
tab hands over the items asked for, and **Claim the reward** collects the reward once the mission has succeeded: an item
the group has to spare, else the reward announced with the mission, else a lot that depends on the group (tools from
settlers, food from neutrals, ammunition from raiders), shown in the notebook.*

1. Near a survivor you can see, press **Ctrl+G**: the nearest visible NPC is selected (key **Select a RadioSurvivor
   NPC** in the game options). The **Talk** button of a contact in the notebook does the same.
2. Write on the **Say** line of the notebook (**Contacts** tab). In multiplayer, the local chat (`/say`) works too.
3. The survivor answers in a speech bubble above their head. A long answer comes in several bubbles.

![A survivor answering in a speech bubble](../../images/screenshots/en-npc-bubble.png)

A stranger does not tell you everything: names, story and requests come once you have spoken a few times. **Clear
target** ends the conversation.

## 5. Missions and report

When a survivor or a voice asks for help, the offer appears in the **Missions** tab of the notebook ("New offer in the
notebook").

- **Accept personally** commits you; **Invite without committing** brings another player of your team in;
  **Abandon for the group** gives it up (it costs reputation).
- **Deliver** opens the delivery window: pick the items the requester accepts.
- Scouting, search, clearing, recovery and signal missions circle an **approximate area** on the world map: the place
  is somewhere inside, not at its centre.
- When the objective is met, the mission shows **To report**: go back to the requester and tell them (**Talk**), or
  use **Report** next to them. For a radio voice, call it back on its frequency. The mission succeeds only then, and
  the deadline still runs.

### What you earn

After success and reporting, voice missions improve reputation and may grant **one** material cache, another voice's frequency, a vanilla stash map or a skill lesson. Darlene offers medical rewards and first-aid lessons; Cody offers ammunition and aiming lessons. The server draws the reward at random among those the voice offers, and the contents of a cache at random within its category; you choose neither. Frequencies enter only your notebook; voice caches get a marker only on your map. Physical supplies remain real world items.

Depending on their sheet, voices can request scouting, a delivery drop, missing papers, clearing or a Signal Smoke signal. NPCs can also offer recovery and group supplies. Always report an NPC mission **in person** to its requester.

### Radio deliveries: discreet collection

A delivery mission of a voice offers **all its dead drops at once** (key `drops=` of its section; without it, every `use=drop` place of the sheet), each circled on your map with its name. Leave the goods wherever you want: items left at several drops add up toward the requested quantity. At each drop, the server designates a suitable existing box (every other mission) or, without one, requests a bag on the ground. The voice collects a drop only **out of everyone's sight** (no player within 100 tiles on x and on y, whatever the floor, or the square unloaded) **and after about 6 game hours** (set by the voice's sheet). The wait follows the game clock: it stops while paused, runs faster at higher speed or while sleeping, and does not count while the server is stopped. A player back in sight before the end resets it. A drop whose wait ran out while its square was unloaded is emptied as soon as the square loads again.

From a box, only requested items disappear, never more than the remaining quantity: the box, other items and the surplus remain. For a bag, the bag and contents disappear; a bag containing unrelated items, or more than the remaining quantity, is refused to prevent their loss. Each item counts only once, even after a restart. Until collection, you can take the drop back and nothing is validated. **Only once the whole quantity is collected, report over the radio**. Solo and MP in-game validation of this collection is **pending**.

**Missing papers for a voice.** The ID card taken from the body is not handed over on the radio: leave it at one of the mission's dead drops, marked on your map as for a delivery (in the designated box, or alone in a bag on the ground). The voice collects it by the same rule, out of sight and after the wait; only the card of that body is taken, another ID card stays where it is. **Only once the card is collected, report over the radio**: the report removes nothing from your inventory. MP in-game validation: **pending**.

Living Knox material rewards first use real household surplus, preserving required reserves and rationed stock; otherwise, a cache near home uses a closed table for the group type. A favorable or trusting personal relationship, without bad reputation, opens stash maps and role-based lessons. A dead requester cannot grant rewards. Group missions have **one shared withdrawal** by a participant, following the previous common-lot rule. Trusted contacts can share their group's radio when available, otherwise an active radio voice. Existing supply contracts retain a reward lot already paid from group reserves, preventing a second withdrawal.

The sandbox lesson multiplier disables XP at 0. The new rewards are implemented; solo and MP in-game validation is **pending**.

![Missions tab with a mission in progress](../../images/screenshots/en-notebook-missions.png)

![A mission to report](../../images/screenshots/en-notebook-report.png)

![Circle of a scouting mission on the world map](../../images/screenshots/en-map-zone.png)

### Trading with a trader

A radio trader (Gus, the Ohio smuggler) sells his stock over the radio. Your first firm offer books his **run** for
your group: he gives you the place, the night and the signal, and the place is marked on your map. Another trader has
his own run: booking one never blocks the other. During the window, show the signal there (Gus: a lit lamp in hand or a
red flare); you hear his engine as he comes alongside. Leave a bag within 3 tiles of the place with enough to pay, then
**walk away out of sight**: he only comes once nobody is within 100 tiles on x and on y **for about one game hour**
(set by the trader's sheet). Coming back too early resets the wait; gone long enough, the exchange is made when you come
back. The bag then holds your goods; a bag that does not cover the price is cheating (nothing is taken). A run can be
called off (patrol, helicopter, storm), and the trader leaves if he never gets a quiet moment. In-game MP validation of
Gus's run: **pending**.

## 6. The notebook

The **Notebook** button of the left bar opens it.

| Tab | Content |
|---|---|
| **Radio** | History of each frequency you listened to. |
| **Contacts** | People you met: group, temperament, conversations heard, your private note (**Save my private note**), and **What they think of you** (attitude, trend, agreements with your side). |
| **Missions** | Offers and missions: objective, deadline, reward, participants. |
| **Reputation** | Your reputation among the survivors and what people remember of your acts. |
| **Team** | Your faction and its negotiators (multiplayer). |

![Contacts tab and what they think of you](../../images/screenshots/en-notebook-contacts.png)

![Radio tab](../../images/screenshots/en-notebook-radio.png)

## 7. Reputation

Missions kept, people rescued, a trader short-changed, a requester killed: what you do is remembered. The
**Reputation** tab shows your level (bad, neutral, good), its trend and the last acts people remember. The attitude of
each survivor toward you is a separate thing, shown on their contact page.

![Reputation tab](../../images/screenshots/en-notebook-reputation.png)

## 8. Administration tools

For the administrator (singleplayer in debug mode, or the `admin` / `moderator` role on a server):

- debug menu → **Living Knox - Admin**: window **Living Knox: groups** with every group, its home, members, story and
  log; move a home, force a relief group;
- right click on a survivor → **Details (Living Knox)**: the sheet of that NPC (needs, health, decision, weapon),
  with bounded settings, role, name and teleport;
- **Reputation** tab → **All reputations (admin)**.

![Living Knox administration window](../../images/screenshots/en-admin-window.png)

![Sheet of an NPC](../../images/screenshots/en-npc-sheet.png)
