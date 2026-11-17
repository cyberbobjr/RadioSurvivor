--[[
RST_CampaignRS - parts of the RST campaigns that run the RadioSurvivor suites (E21-T07, registry of RST_Campaign.lua
in batman_CoreAITests: rank 30, suites that must come last 80). Development mod only (batman_RadioSurvivorTests).
Prefix selection (an entry selects the suite of that name and the suites "<entry>.*", never "<entry>s"):
"rs.missions" also runs rs.missions.radio and rs.missions.voicetemplates; "rs.personas" runs .update; "rs.radiomodule"
runs .world; "rs.rescue" runs .pick, .run, .visit, .saved, .missed. Suites from rs.radiomodule on need the Python bridge
(rs.groupradio: the real model). The suites that need Living Knox too are SKIP without it (opts.mods). E21-T11: the
notebook suites of the Living Knox npcs are in RST_CampaignLK.lua (lk.*), those of the core mod (notebook, mission
engine and templates, identity, state) in RST_Campaign.lua (ca.*).
]]

require "RST/RST_Campaign"

RST.Campaigns.add({ "solo-rs", "solo" }, 30, {
    "rs.env",           -- E01-T08
    "rs.missions",      -- E11-T08, E11-T17 (prefix: radio, voicetemplates)
    "rs.comfort",       -- E05-T15 (gauges and halo of the local player)
    "rs.memorial",      -- E14-T04 (animal death kept out, bulletin announces the names)
    "rs.notebook.visual", -- E03-T02 (changes the display mode for a while, restored after)
    "rs.personas",      -- E05-T02, E05-T11
    "rs.notes",         -- E05-T09
    "rs.calls",         -- E05-T05
    "rs.rescue",        -- E12-T02..T05 (E01-T19)
    "rs.radiomodule",   -- E06-T02 (bridge)
    "rs.groupradio",    -- E08-T06, E08-T10, E17-T12 (E01-T19, bridge; fixture group when none holds a transmitter)
    "rs.worldradio",    -- E06-T03
    "rs.radio",         -- E06-T05
    "rs.notebook.voices", -- E06-T07 (voice and hours in the Radio tab; client 2 sees nothing)
    "rs.actions.share", -- E07-T10 (exceptional share_frequency: bond, 7/3-day delays, known voice never given)
    "rs.reputation",    -- E04-T14 (E04-T11: smuggler margin)
    "rs.voicedelivery", -- hidden radio deposits, actual world removal
    "rs.voiceretrieve", -- E20-T06: ID card of a voice mission left at a dead drop, then the radio report
    "rs.voicebarricade", -- E20-T09: outside openings of a real building barricaded, then the radio report
    "rs.voicerelay",    -- E20-T12: powered radio turned on upstairs in a real building, off refused, then the report
    "rs.voicewatch",    -- E20-T14: watch counted in game time at the spot, long absence resets, then the report
    "rs.voiceroute",    -- E20-T13: three places crossed in order, skipped points refused, then the report
    "rs.voiceitem",     -- E20-T15: personal item spawned by the server, left at a drop with a decoy, then the report
    "rs.voicedarlene",  -- E20-T10: Darlene's chain with her real sheet at the West Point clinic, up to returned
    "rs.missionrewards", -- E11: actual cache, private frequency, stash and server XP
    "rs.reciperadio",   -- E27-T04: delayed search kept, delivery at good teaches the recipe and notes it
})

-- Suites with a FAIL or SKIP in the solo campaign of 2026-10-13 (report 20261013-202155-solo.txt), fixed since.
RST.Campaigns.add("solo-retry", 30, {
    "rs.personas",      -- probe frequency above 999.8, conflict test without walt
})

-- Dedicated server (RST.server, see RST_Campaign.lua). Suites whose check is drawn by a client (rs.actions.map,
-- rs.actions.reveal) ask the requester client through RST.Steps (RST_RSViewSteps.lua). rs.missions selects
-- rs.missions.radio and .voicetemplates; the mission engine and its templates are ca.missions and ca.mission
-- (RST_Campaign.lua).
-- A suite that needs a group near the player (rs.groupradio) creates one around the requester when none is loaded
-- (RST_LKGroupFixture.lua of batman_LivingKnoxTests).
RST.Campaigns.add("mp", 30, {
    "rs.env",           -- E01-T08
    "rs.facts",         -- E14-T01, E14-T03
    "rs.memorial",      -- E14-T04 (animal death kept out, bulletin announces the names)
    "rs.lifelog",       -- E15-T01
    "rs.freqdebug",     -- E05-T14
    "rs.placesurvey",   -- E22-T08: admin client records a container square; user client: no option, refused
    "rs.voices",        -- E05-T06
    "rs.comfort",       -- E05-T15 (requester client: gauges and halo; second client: no drop)
    "rs.missions",      -- E11-T08, E11-T17 (prefix: radio, voicetemplates)
    "rs.trade_exchange", -- E13-T04 (E01-T19)
    "rs.trade_run",     -- E13-T03 (E01-T19)
    "rs.trade_road",    -- E20-T11: a road trader's run, van sounds of the mode, exchange out of sight after the delay
    "rs.rescue",        -- E12-T02..T05
    "rs.reputation",    -- E04-T14 (E04-T11: smuggler margin)
    "rs.voicedelivery", -- all online witnesses leave before physical collection
    "rs.voiceretrieve", -- E20-T06: card collected out of view of every online player, then the radio report
    "rs.voicebarricade", -- E20-T09: barricades counted by the server, then the radio report
    "rs.voicerelay",    -- E20-T12: radio relay read by the server, off refused, then the radio report
    "rs.voicewatch",    -- E20-T14: watch read on the server copy in game hours, long absence resets, then the report
    "rs.voiceroute",    -- E20-T13: route crossed in order by the server copy, skipped points refused, then the report
    "rs.voiceitem",     -- E20-T15: only the marked item collected out of view of every online player, then the report
    "rs.voicedarlene",  -- E20-T10: Darlene's chain with her real sheet at the West Point clinic, up to returned
    "rs.missionrewards", -- E11: recipient client XP and unrelated client isolation
    "rs.lastpages",     -- E15-T02, E15-T03 (prefix: corpse)
    "rs.bulletin",      -- E14-T02
    "rs.notes",         -- E05-T09
    "rs.actions.map",   -- E07-T04, E07-T08 (E01-T19: map and history checked by the requester client)
    "rs.actions.reveal", -- E07-T05 (E01-T19)
    "rs.actions.share", -- E07-T10 (shared voice in the requester Radio tab only, client 2 sees nothing)
    "rs.personas",      -- E05-T02, E05-T11
    -- E01-T16: suite through the requester client (RST.Steps): real network path, bridge on the server.
    "rs.groupradio",    -- E08-T06, E08-T10, E17-T12 (E01-T19, bridge)
    "rs.worldradio",    -- E06-T03
    "rs.radio",         -- E06-T05
    "rs.notebook.voices", -- E06-T07 (voice and hours in the Radio tab; client 2 sees nothing)
})
RST.Campaigns.add("mp", 80, {
    "rs.death",         -- E00-T02, E03-T04, E15-T02 (E01-T16: client 2 really dies, then respawns)
})

-- E01-T19: robustness with the vanilla population of Muldraugh and mortal players (see RST_CampaignLK.lua).
RST.Campaigns.add("mp-ambient", 30, {
    "rs.facts",         -- E14-T01, E14-T03
})

-- E01-T17: persistence across a reconnection and a restart of the dedicated server (bases, not suites).
RST.Campaigns.add("mp-persist", 30, {
    "rs.rescue.missed", -- E12-T05: no second zombie nor notebook after a restart
    "rs.radiotab",      -- E06-T05: Radio tab history of both players kept after a reconnection
    "rs.actions.map",   -- E07-T04: map mark of the requester kept after its reconnection (reconnect)
    "rs.memory",        -- E22-T13: a fact a voice remembered comes back in the request after a restart
})
