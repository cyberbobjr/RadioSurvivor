*Français : [[Utilisation|Usage-FR]]*

# Usage

A step-by-step guide for the player. The bridge must be running for the voices and the survivors to speak
([[Installation and configuration|Installation-and-Configuration]]).

## 1. Find a frequency

The voices are on frequencies drawn for each game. They are written on **notes** found in the loot: radio log page,
patient card, National Guard notice, scribbled note, Night Owl flyer. Each note sits where its voice would leave it
(how often: sandbox option **Frequency notes in the loot**).

Right click the note → **Inspect** (or **Read**) to open it. Walt is the first voice to look for: he answers at any
hour.

![Frequency note of Walt](images/en-frequency-note.png)

## 2. Talk to a voice on the radio

1. Take a transmitting radio **in hand**: walkie-talkie, HAM radio (or a manpack radio worn on the back).
2. Switch it on and tune it to the frequency of the note.
3. Open the microphone (section **Microphone** of the radio window).
4. Type your sentence in the **Transmit** section at the bottom of the radio window, then press Enter or
   **Transmit**.

![The answer of the voice heard in game, above the player](images/en-walkie-in-hand.png)

The field is greyed while the voice answers; the answer is played on the radio and shown in the last lines of the
section. Keep it short: a voice that is spoken to without a pause asks you to catch your breath. A walkie-talkie on the
belt receives, but it does not transmit: hold it in hand to speak.

![Transmit section and the answer of Walt](images/en-radio-transmit.png)

Every voice has its listening hours and remembers you. The **Radio** tab of the notebook keeps what was said on each
frequency.

## 3. Meet a Living Knox group

Groups of survivors live in houses or camps across the county: settlers, neutrals and raiders. A group has a leader,
fighters and workers, a home it barricades, supplies and needs. Approach slowly and do not point a weapon: a group
defends its home, and raiders attack.

![A group at its home](images/en-group-home.png)

## 4. Speak to a survivor (Ctrl+G)

1. Near a survivor you can see, press **Ctrl+G**: the nearest visible NPC is selected (key **Select a RadioSurvivor
   NPC** in the game options). The **Talk** button of a contact in the notebook does the same.
2. Write on the **Say** line of the notebook (**Contacts** tab). In multiplayer, the local chat (`/say`) works too.
3. The survivor answers in a speech bubble above their head. A long answer comes in several bubbles.

![A survivor answering in a speech bubble](images/en-npc-bubble.png)

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

After success and reporting, voice missions improve reputation and may grant **one** material cache, another voice's frequency, a vanilla stash map or a skill lesson. Darlene offers medical rewards and first-aid lessons; Cody offers ammunition and aiming lessons. The server rotates permitted rewards; you do not choose their contents. Frequencies enter only your notebook; voice caches get a marker only on your map. Physical supplies remain real world items.

Depending on their sheet, voices can request scouting, a delivery drop, missing papers, clearing or a Signal Smoke signal. NPCs can also offer recovery and group supplies. Always report an NPC mission **in person** to its requester.

### Radio deliveries: discreet collection

The server alternates an agreed drop box and a hidden bag on the ground at one of the voice's `place=` locations. A suitable existing box is marked precisely on your map; without a suitable box, the server requests a bag. Leave the complete batch and move away: **all players must remain at least 40 tiles away horizontally for 10 continuous real seconds**, even on another floor. Returning or restarting resets the wait; the exact square must be loaded before removal.

From a box, only requested items disappear; the box and other items remain. For a bag, the bag and contents disappear; a bag containing unrelated items is refused to prevent their loss. Until collection, you can take the drop back and nothing is validated. **Only after collection, report over the radio**. Solo and MP in-game validation of this collection is **pending**.

Living Knox material rewards first use real household surplus, preserving required reserves and rationed stock; otherwise, a cache near home uses a closed table for the group type. A favorable or trusting personal relationship, without bad reputation, opens stash maps and role-based lessons. A dead requester cannot grant rewards. Group missions have **one shared withdrawal** by a participant, following the previous common-lot rule. Trusted contacts can share their group's radio when available, otherwise an active radio voice. Existing supply contracts retain a reward lot already paid from group reserves, preventing a second withdrawal.

The sandbox lesson multiplier disables XP at 0. The new rewards are implemented; solo and MP in-game validation is **pending**.

![Missions tab with a mission in progress](images/en-notebook-missions.png)

![A mission to report](images/en-notebook-report.png)

![Circle of a scouting mission on the world map](images/en-map-zone.png)

## 6. The notebook

The **Notebook** button of the left bar opens it.

| Tab | Content |
|---|---|
| **Radio** | History of each frequency you listened to. |
| **Contacts** | People you met: group, temperament, conversations heard, your private note (**Save my private note**), and **What they think of you** (attitude, trend, agreements with your side). |
| **Missions** | Offers and missions: objective, deadline, reward, participants. |
| **Reputation** | Your reputation among the survivors and what people remember of your acts. |
| **Team** | Your faction and its negotiators (multiplayer). |

![Contacts tab and what they think of you](images/en-notebook-contacts.png)

![Radio tab](images/en-notebook-radio.png)

## 7. Reputation

Missions kept, people rescued, a trader short-changed, a requester killed: what you do is remembered. The
**Reputation** tab shows your level (bad, neutral, good), its trend and the last acts people remember. The attitude of
each survivor toward you is a separate thing, shown on their contact page.

![Reputation tab](images/en-notebook-reputation.png)

## 8. Administration tools

For the administrator (singleplayer in debug mode, or the `admin` / `moderator` role on a server):

- debug menu → **Living Knox - Admin**: window **Living Knox: groups** with every group, its home, members, story and
  log; move a home, force a relief group;
- right click on a survivor → **Details (Living Knox)**: the sheet of that NPC (needs, health, decision, weapon),
  with bounded settings, role, name and teleport;
- **Reputation** tab → **All reputations (admin)**.

![Living Knox administration window](images/en-admin-window.png)

![Sheet of an NPC](images/en-npc-sheet.png)
