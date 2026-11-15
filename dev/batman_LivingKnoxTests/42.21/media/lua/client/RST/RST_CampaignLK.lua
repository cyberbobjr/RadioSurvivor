--[[
RST_CampaignLK - parts of the RST campaigns that run the Living Knox suites (E21-T07, registry of RST_Campaign.lua in
batman_CoreAITests: rank 20, suites that must come last 90). Development mod only (batman_LivingKnoxTests).
Order: short suites first, long group suites (chores, defense) last. lk.conversations and lk.initiatives need the
Python bridge (the real model; autoclient.py BRIDGE_SUITES starts it).
]]

require "RST/RST_Campaign"

RST.Campaigns.add({ "solo-lk", "solo" }, 20, {
    "lk.fitness",       -- LK05-T16
    "lk.teamneeds",     -- LK05-T15
    "lk.health",        -- LK07-T06
    "lk.loot",          -- LK07-T07
    "lk.equipment",     -- LK02-T13
    "lk.appearance",    -- LK02-T12 (two runs across a restart)
    "lk.bodies",        -- LK02-T11
    "lk.anims",         -- LK02-T11, LK06-T10
    "lk.senses",        -- LK05-T01
    "lk.executor",      -- LK03-T07
    "lk.ownerreports",  -- LK03-T02 (owner part; the non-owner part is noted in solo)
    "lk.spawnclean",    -- LK03-T06
    "rst.fixtures.npc", -- E01-T10, E01-T18 (test API of Living Knox, debug mode)
    "lk.conversations", -- E08-T04, E08-T05 (E01-T19, bridge)
    "lk.initiatives",   -- E08-T03 (E01-T19, bridge)
    "lk.deathswing",    -- LK06-T13
    "lk.windowlure",    -- LK06-T10
    "lk.revenge",       -- LK11-T05 (E01-T19)
    "lk.traversal",     -- LK04-T03..T18 (E01-T19; about 7 minutes)
    "lk.doors",         -- LK04-T02 (2026-10-15: sites found by RST.Places when missing near the player)
    "lk.melee",         -- LK06-T02
    "lk.upkeep",        -- LK05-T10 (E01-T19)
    "lk.garden",        -- LK15-T04..T06 (garden of the gardener: seeds, furrow, sowing)
    "lk.chores",        -- LK05-T04
    "lk.defense",       -- LK06-T07, LK06-T14
    "lk.windowsally",   -- E18-T34
    "lk.force",         -- LK04-T04 (2026-10-15: solo proof)
    "lk.repair",        -- LK14-T06 (2026-10-15: solo proof)
    "lk.expedition",    -- LK05-T05 (2026-10-15: solo proof)
    "lk.meals",         -- LK05-T07 (2026-10-15: solo proof)
    "lk.provisions",    -- LK05-T20 (provisions carried, canteen, replaced at home)
    "lk.zombies",       -- LK06-T04 (2026-10-15: solo proof)
    "lk.admin",         -- LK13-T01 (2026-10-15: solo window by the debug menu button)
    "lk.npcsheet",      -- LK13-T13 (2026-10-15: solo sheet by the right-click menu)
    "lk.debugview",     -- LK13-T14..T16 (2026-10-15: solo panel, live activity)
    "lk.load",          -- LK13-T02 (2026-10-15: solo measure from the admin window)
    "lk.forage",        -- LK05-T11 (2026-10-15; LAST: moves the clock to 9:00 outside 7 h - 15 h)
})

-- Suites with a FAIL or SKIP in the solo campaign of 2026-10-13 (report 20261013-202155-solo.txt), fixed since.
RST.Campaigns.add("solo-retry", 20, {
    "lk.health",        -- bleeding started by the hit
    "lk.anims",         -- place check on a stale current square
    "lk.windowlure",    -- npc pushed outside the window
    "lk.chores",        -- player seen as an intruder at home
})

-- Dedicated server (RST.server, see RST_Campaign.lua). Suites whose check is drawn by a client (lk.equipment,
-- lk.speech, lk.ranged) ask the requester client through RST.Steps. Suites that move the game clock: lk.expedition,
-- lk.forage (9:00), lk.meals, lk.provisions, lk.repair (6:59 at night), and lk.routines (23:00 then dawn) LAST.
RST.Campaigns.add("mp", 20, {
    "lk.load",          -- LK13-T02
    "lk.fitness",       -- LK05-T16
    "lk.sites",         -- LK08
    "lk.bodies",        -- LK02-T11, LK03-T04
    "lk.appearance",    -- LK02-T03, LK02-T12
    "lk.guard",         -- LK02-T04
    "lk.executor",      -- LK02-T07, LK03-T01, LK03-T02
    "lk.ownerreports",  -- LK03-T02 (client 2 forges a report)
    "lk.handover",      -- LK03-T03
    "lk.relay",         -- LK03-T05
    "lk.spawnclean",    -- LK03-T06
    "rst.fixtures.npc", -- E01-T10, E01-T18 (test API on the server started in debug mode)
    "lk.health",        -- LK07-T02, LK07-T06
    "lk.death",         -- LK07-T04
    "lk.loot",          -- LK07-T05
    "lk.melee",         -- LK06-T02, LK06-T11, LK06-T13
    "lk.deathswing",    -- LK06-T13 (client 2 hears no swing after the death)
    "lk.killer",        -- E04-T06 (who killed a Living Knox npc, on the authority)
    "lk.equipment",     -- LK02-T06, LK02-T13 (E01-T19: requester client checks)
    "lk.ranged",        -- LK06-T03 (E01-T19: shots played by the requester client)
    "lk.speech",        -- LK11-T04, LK11-T09 (E01-T19: bubble checked by the requester client)
    "lk.talk",          -- E18-T18, E21-T05 (proximity speech of the npcs)
    "lk.missions",      -- E18-T29, E21-T05 (missions of an npc in the notebook)
    "lk.chatter",       -- E18-T32
    "lk.conversations", -- E08-T04, E08-T05 (E01-T16: notebook of the requester client, bridge on the server)
    "lk.initiatives",   -- E08-T03 (bridge)
    "lk.zombies",       -- LK06-T04
    "lk.traversal",     -- LK04-T03..T18 (E01-T19; sites missing near the spawn house: SKIP per test)
    "lk.doors",         -- LK04-T02 (2026-10-15: both clients see the same door state, no double toggle)
    "lk.force",         -- LK04-T04 (E01-T19)
    "lk.stuck",         -- LK04-T05 (E01-T19)
    "lk.milestone1",    -- LK02-T08 (E01-T19)
    "lk.essai",         -- LK02-T10 (E01-T19)
    "lk.npcsheet",      -- LK13-T13, LK13-T15
    "lk.debugview",     -- LK13-T14
    "lk.admin",         -- LK13-T01
    "lk.relief",        -- LK09-T04
    "lk.materialize",   -- LK09-T03
    "lk.homes",         -- LK08-T04
    "lk.stock",         -- LK08-T06
    "lk.offscreen_stock", -- LK09-T06
    "lk.warn",          -- LK11-T02
    "lk.aid",           -- LK11-T06
    "lk.trade",         -- LK11-T08
    "lk.tradeview",     -- LK11-T08 (E01-T16: Trade menu of both clients, one winner)
    "lk.revenge",       -- LK11-T05
    "lk.raid",          -- LK11-T07
    "lk.alert",         -- LK05-T08
    "lk.leave",         -- E10-T04, E10-T05
    "lk.contest",       -- E10-T03
    "lk.upkeep",        -- LK05-T10
    "lk.garden",        -- LK15-T04..T06
    "lk.barricade",     -- LK14-T03
    "lk.walls",         -- LK14-T04
    "lk.fortify_offscreen", -- LK14-T05
    "lk.retreat",       -- LK06-T12
    "lk.windowsally",   -- E18-T34 (replaces lk.windowkill)
    "lk.defense",       -- LK05-T09, LK06-T14
    "lk.chores",        -- LK05-T04
    "lk.meals",         -- LK05-T07 (E01-T19; clock to 6:59 at night)
    "lk.provisions",    -- LK05-T20 (clock to 6:59 at night)
    "lk.repair",        -- LK14-T06 (E01-T19; clock to 6:59 at night)
    "lk.expedition",    -- LK05-T05 (E01-T19; clock to 9:00 outside 7 h - 16 h)
    "lk.forage",        -- LK05-T11 (E01-T19; clock to 9:00 outside 7 h - 15 h)
})
RST.Campaigns.add("mp", 90, {
    "lk.routines",      -- LK05-T03 (E01-T19) LAST: moves the clock to 23:00 then to dawn
})

-- E01-T19: robustness with the vanilla population of Muldraugh and mortal players, on the dedicated server only
-- (autoclient.py --mp --server-campaign mp-ambient --ambient-zombies --no-godmode).
RST.Campaigns.add("mp-ambient", 20, {
    "lk.load",          -- LK13-T02
    "lk.zombies",       -- LK06-T04
    "lk.alert",         -- LK05-T08
    "lk.defense",       -- LK05-T09, LK06-T14
})

-- LK13-T02 (2026-10-15): load measure with 5 groups and 4 players, on the dedicated server only (autoclient.py --mp
-- --load: new world with LivingKnox.GroupCount = 5, clients rs_mp1..rs_mp4). lk.load first (short measure, 20 s),
-- then lk.loadmp (players placed around the homes as in docs/annexes/tests/validation/charge-protocole.md, three
-- phases of 5 min, server and two client measures checked against the budgets; RST_LK_LOADMP_PHASE_MS on the server
-- overrides 5 min).
RST.Campaigns.add("mp-load", 20, {
    "lk.load",          -- LK13-T02 (short measure of the authority)
    "lk.loadmp",        -- LK13-T02 (protocol of charge-protocole.md, sections 2 to 5)
})

-- E01-T17: persistence across a reconnection and a restart of the dedicated server. Entries are BASES, not suites:
-- autoclient.py --mp --clients 2 --phases reconnect2,reconnect,restart --server-campaign mp-persist runs
-- <base>.before, then <base>.after-<action> when the suite exists (phase_plan).
RST.Campaigns.add("mp-persist", 20, {
    "lk.homes",         -- LK08-T04: no second furnishing after a restart
    "lk.leave",         -- E10-T04: loner group and departure kept by a restart
    "lk.walls",         -- LK14-T04: wall kept after a reconnection and a restart
})
RST.Campaigns.add("mp-persist", 90, {
    "lk.rejoin",        -- LK03-T01: the executor rejoins (reconnect2); LAST: its before step moves the requester away
})
