*Français : [[FAQ|FAQ-FR]]*

# FAQ

**Do I need the bridge to play?**
No. Without it the game stays playable: the radio voices answer only with static, the evening bulletin and the last
pages use short fixed texts, and the NPCs stay silent. The groups still live, fight and fortify.

**Why can't the mod call the AI by itself?**
Project Zomboid's Lua has no network access, and a Workshop mod cannot start a program. The bridge is a small Python
program that reads the game's requests from a file and writes the answers back.

**Do players on my server need the bridge or a key?**
No. Only the machine that runs the server runs the bridge. Players install the mods only.

**Does it cost money?**
Your AI provider bills each call. Every radio message is one call; spontaneous calls, the evening bulletin, the last
pages and NPC dialogues are calls too. Cap them with `MaxPerHour` and the other options
([[Sandbox options|Sandbox-Options]]), and set a spending limit at your provider. Usage is logged in
`token_usage.jsonl`. Or run `--offline` for free (the voices echo you).

**Which AI can I use?**
Any provider compatible with the OpenAI `/chat/completions` API, including local servers. See
[[AI provider configuration|AI-Provider-Configuration]].

**How do I find the voices?**
Their frequencies are drawn for each game and never sent to the players: look for notes in the loot (a radio log page,
a patient file, a National Guard notice, a scribbled note, a radio flyer) and **Inspect** them. One voice stays silent
until its rescue starts.

**Why does the radio refuse to transmit from my belt?**
Transmitting needs a radio in hand or worn on the back (or set down nearby, or a vehicle radio). A walkie-talkie on the
belt can listen (with Belt Walkie-Talkie) but not transmit.

**How do I talk to an NPC?**
Get close, press **Ctrl+G** to select the nearest visible NPC (8 squares at most), then speak in the local chat
(`/say`). General, faction and private chat do not reach NPCs.

**Can I use it with Bandits! or Project A-Life?**
No. Radio Survivor has its own NPC engine (Living Knox); only one NPC engine per game.

**Can I add it to an existing save?**
Possible, but this is a test version: a **new game** is strongly recommended. The number of groups is set when the
world is created.

**Can I change a voice's personality?**
Yes, as the server admin: edit `<exchange folder>/personas/<voice>.txt` (text after `[prompt]`, plus `knows`,
`ignores`, `secret`). It is reread every 30 s, and an edited sheet is never overwritten by a mod update.

**Does it work in multiplayer?**
Yes, it is designed for dedicated servers: the server decides everything, the AI only writes words. Multiplayer is
checked by automated test campaigns; report anything odd. See
[[The bridge on a dedicated server|Bridge-on-a-Dedicated-Server]].

**Can two servers share one bridge?**
No. One bridge per server and per exchange folder; give each server its own `-cachedir`.

**What should I send with a bug report?**
`console.txt` (or the server log) and the bridge output without `--debug`. Never send your `.env` or a `--debug` log as
is (it holds the prompts and dialogues).
