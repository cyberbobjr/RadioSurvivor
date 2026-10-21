--[[
RST_Campaign - named campaigns of in-game suites run one after the other in ONE asynchronous run with ONE report
(development mod only). From the Lua console (debug mode, solo, save named rstest*):
    RST.campaign("solo-lk")     Living Knox suites to validate in solo
    RST.campaign("solo-rs")     Journal Survivor suites to validate in solo
    RST.campaign("solo")        both lists, Living Knox first
    RST.campaign("solo-retry")  the suites that failed in the solo campaign of 2026-10-13, after their fixes
    RST.campaigns()             prints the campaigns and their suites
"mp" and "mp-ambient" are lists for the dedicated server (RST.server, see below), not for RST.campaign.
"mp-persist" lists bases of the phased MP run (autoclient.py --phases, E01-T17), not suites.
RST.campaign(name) -> true, or false and a reason. It is RST.run({ suite = <list>, exclude = {} }): every named suite,
world and server suites included (the explicit empty exclude lifts the default exclusion of RST_Client.lua; the world
guard of RST.lua still refuses world suites outside a save named rstest*). The suites run in the order of the list
(RST.select keeps the declaration order: the plan is reordered for this run only), then the usual report is printed
and written (Zomboid/Lua/batman_RadioSurvivor/tests/<stamp>-solo.txt). RST.cancel() stops it.
Order: short suites first, long group suites (chores, defense) last; no suite of solo-lk needs the Python bridge.
]]

require "RST/RST"
require "RST/RST_Client"

RST.CAMPAIGNS = RST.CAMPAIGNS or {}

RST.CAMPAIGNS["solo-lk"] = {
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
    "lk.ownerreports", -- LK03-T02 (owner part; the non-owner part is noted in solo)
    "lk.spawnclean",   -- LK03-T06
    "lk.deathswing",   -- LK06-T13
    "lk.windowlure",    -- LK06-T10
    "lk.revenge",       -- LK11-T05 (E01-T19)
    "lk.traversal",     -- LK04-T03..T18 (E01-T19; about 7 minutes)
    "lk.doors",         -- LK04-T02 (2026-10-15: sites found by RST.Places when missing near the player)
    "lk.melee",         -- LK06-T02
    "lk.upkeep",        -- LK05-T10 (E01-T19)
    "lk.chores",        -- LK05-T04
    "lk.defense",       -- LK06-T07, LK06-T14
    "lk.force",         -- LK04-T04 (2026-10-15: solo proof)
    "lk.repair",        -- LK14-T06 (2026-10-15: solo proof)
    "lk.expedition",    -- LK05-T05 (2026-10-15: solo proof)
    "lk.meals",         -- LK05-T07 (2026-10-15: solo proof)
    "lk.zombies",       -- LK06-T04 (2026-10-15: solo proof)
    "lk.admin",         -- LK13-T01 (2026-10-15: solo window by the debug menu button)
    "lk.npcsheet",      -- LK13-T13 (2026-10-15: solo sheet by the right-click menu)
    "lk.debugview",     -- LK13-T14..T16 (2026-10-15: solo panel, live activity)
    "lk.load",          -- LK13-T02 (2026-10-15: solo measure from the admin window)
    "lk.forage",        -- LK05-T11 (2026-10-15; LAST: moves the clock to 9:00 outside 7 h - 15 h)
}
-- Prefix selection (an entry selects the suite of that name and the suites "<entry>.*", never "<entry>s"):
-- "rs.missions" also runs rs.missions.radio, rs.missions.scout and rs.missions.solo, NOT the templates rs.mission.*
-- (singular: clear, retrieve, recover, signal); "rs.personas" runs .update; "rs.radiomodule" runs .world;
-- "rs.rescue" runs .pick, .run, .visit, .saved, .missed. Suites from rs.radiomodule on need the Python bridge
-- (rs.npctalk, rs.relation, rs.conversations, rs.initiatives, rs.groupradio: the real model).
RST.CAMPAIGNS["solo-rs"] = {
    "rst.guard",        -- E01-T06
    "rs.env",           -- E01-T08
    "rs.codec",         -- E01-T08
    "rs.missions",      -- E01-T08, E00-T03, E00-T10, E11-T11 (prefix: radio, scout, solo)
    "rs.notebook.ink",  -- E00-T12
    "rs.notebook.relation", -- E09-T07
    "rs.notebook.visual", -- E03-T02 (changes the display mode for a while, restored after)
    "rs.personas",      -- E05-T02, E05-T11
    "rs.notes",         -- E05-T09
    "rs.worldtriggers", -- E08-T08
    "rs.calls",         -- E05-T05
    "rs.rescue",        -- E12-T02..T05 (E01-T19)
    "rs.radiomodule",   -- E06-T02 (bridge)
    "rs.npctalk",       -- E17-T08, E17-T09 (bridge)
    "rs.relation",      -- E09-T04 (bridge)
    "rs.conversations", -- E08-T04, E08-T05 (E01-T19, bridge)
    "rs.initiatives",   -- E08-T03 (E01-T19, bridge)
    "rs.groupradio",    -- E08-T06, E08-T10, E17-T12 (E01-T19, bridge; fixture group when none holds a transmitter)
    "rs.worldradio",   -- E06-T03
    "rs.radio",        -- E06-T05
    "rs.carnet.load",  -- E00-T04
    "rs.observations", -- E08-T07
    "rs.factions.mandate", -- E09-T03
    "rs.reputation",    -- E04-T14 (E04-T04, T05, T07, T11, Q17)
    "rs.voicedelivery", -- hidden radio deposits, actual world removal
    "rs.missionrewards", -- E11: actual cache, private frequency, stash and server XP
}

-- Suites with a FAIL or SKIP in the solo campaign of 2026-10-13 (report 20261013-202155-solo.txt), fixed since.
-- rs.npctalk needs the Python bridge (real model).
RST.CAMPAIGNS["solo-retry"] = {
    "lk.health",        -- bleeding started by the hit
    "lk.anims",         -- place check on a stale current square
    "lk.windowlure",    -- npc pushed outside the window
    "lk.chores",        -- player seen as an intruder at home
    "rs.personas",      -- probe frequency above 999.8, conflict test without walt
    "rs.worldtriggers", -- storm forced at once (modded weather period)
    "rs.npctalk",       -- zombies cleared, exact reason of a lost answer (bridge)
}

-- Multiplayer (E01-T15): suites run ON THE DEDICATED SERVER by an admin client, RST.server (the automatic client:
-- autoclient.py --mp --server-campaign mp; the driver adds exclude = { "manual" }). Server and shared suites first,
-- then world suites around the requester (spawn point of the test server: a house of Muldraugh; the suites that look
-- for another place move the players there, RST.Places with SERVER_MOVES: "/teleportto" asked by RST.Fixtures
-- "fx.move", every moved player brought back at the end), long group suites last. Not for RST.campaign
-- on a client: the client suites of the plan stay in solo-lk / solo-rs. E01-T16: with --clients 2 the second client
-- answers the client checks of the suites (RST.Steps, RST_PeerChecks.lua) and is set to the access level "user" for
-- the rights tests; the notebook suites act through the requester client.
-- E01-T19: the server keeps only the "server" and "shared" suites of the list (RST_Server.lua: default tags, "client"
-- always excluded), so every entry here is tagged "server" (or "shared"); a suite tagged "world" only never runs here.
-- Suites whose check is drawn by a client (lk.equipment, lk.speech, lk.ranged, rs.actions.map, rs.actions.reveal) ask
-- the requester client through RST.Steps (RST_ViewSteps.lua). rs.missions selects rs.missions.radio/.scout/.solo
-- (.solo SKIPs on a server: notebook window and map on the client); rs.mission selects the templates rs.mission.clear,
-- .retrieve, .recover and .signal (required mod Signal Smoke: FAIL without it). Suites that need a group near the player
-- (rs.carnet.lk, rs.carnet.lk.supply, rs.groupradio, rs.factions.*) create one around the requester when none is
-- loaded (RST_LKGroupFixture.lua). Suites that move the game clock: lk.expedition, lk.forage (9:00), lk.meals,
-- lk.repair (6:59 at night), and lk.routines (23:00 then dawn) LAST.
RST.CAMPAIGNS["mp"] = {
    "rst.selftest",     -- engine on the server
    "rs.env",           -- E01-T08
    "rs.codec",         -- E01-T08
    "rs.identity",      -- E00-T01, E03-T04 (each online player bound to an identity)
    "rs.claim",         -- E00-T01 (E01-T16: the second client claiming another identity is refused)
    "rs.facts",         -- E14-T01, E14-T03
    "rs.lifelog",       -- E15-T01
    "rs.freqdebug",     -- E05-T14
    "rst.rights",       -- E01-T05 (E01-T16: a real user client refused RST.server, an admin told busy)
    "rs.voices",        -- E05-T06
    "rs.missions",      -- E11-T03, E11-T08 (prefix: radio, scout, solo; NOT the templates rs.mission.*)
    "rs.mission",       -- E11-T04..T07, E01-T19 (prefix: clear, retrieve, recover, signal)
    "rs.carnet.lk",     -- E10-T02, E17-T03 (prefix: supply; fixture group, E01-T19)
    "rs.carnet.leader", -- E10-T02 (non-leader member, reply after a death or a succession)
    "rs.factions.accord", -- E09-T05 (E01-T19)
    "rs.factions.incident", -- E09-T06 (E01-T19: hit simulated on the authority)
    "rs.trade_exchange", -- E13-T04 (E01-T19)
    "rs.trade_run",     -- E13-T03 (E01-T19)
    "rs.rescue",        -- E12-T02..T05
    "lk.load",          -- LK13-T02
    "lk.fitness",       -- LK05-T16
    "lk.sites",         -- LK08
    "rs.killer",        -- E04-T06
    "rs.reputation",    -- E04-T14 (two clients: killer and team mate, admin view)
    "rs.voicedelivery", -- all online witnesses leave before physical collection
    "rs.missionrewards", -- E11: recipient client XP and unrelated client isolation
    "rs.lastpages",     -- E15-T02, E15-T03 (prefix: corpse)
    "rs.bulletin",      -- E14-T02
    "rs.notes",         -- E05-T09
    "rs.actions.map",   -- E07-T04, E07-T08 (E01-T19: map and history checked by the requester client)
    "rs.actions.reveal", -- E07-T05 (E01-T19)
    "rs.personas",      -- E05-T02, E05-T11
    "rs.worldtriggers", -- E08-T08
    -- E01-T16: notebook suites through the requester client (RST.Steps): real network path, bridge on the server.
    "rs.npctalk",       -- E17-T08, E17-T09, E17-T13 (bridge)
    "rs.relation",      -- E09-T04 (bridge)
    "rs.conversations", -- E08-T04, E08-T05
    "rs.initiatives",   -- E08-T03 (bridge)
    "rs.groupradio",    -- E08-T06, E08-T10, E17-T12 (E01-T19, bridge)
    "rs.worldradio",   -- E06-T03
    "rs.radio",        -- E06-T05
    "rs.carnet.load",  -- E00-T04
    "rs.observations", -- E08-T07
    "rs.factions.mandate", -- E09-T03
    "lk.bodies",        -- LK02-T11, LK03-T04
    "lk.appearance",    -- LK02-T03, LK02-T12
    "lk.guard",         -- LK02-T04
    "lk.executor",      -- LK02-T07, LK03-T01, LK03-T02
    "lk.ownerreports", -- LK03-T02 (client 2 forges a report)
    "lk.handover",     -- LK03-T03
    "lk.relay",        -- LK03-T05
    "lk.spawnclean",   -- LK03-T06
    "lk.health",        -- LK07-T02, LK07-T06
    "lk.death",         -- LK07-T04
    "lk.loot",          -- LK07-T05
    "lk.melee",         -- LK06-T02, LK06-T11, LK06-T13
    "lk.deathswing",   -- LK06-T13 (client 2 hears no swing after the death)
    "lk.equipment",     -- LK02-T06, LK02-T13 (E01-T19: requester client checks)
    "lk.ranged",        -- LK06-T03 (E01-T19: shots played by the requester client)
    "lk.speech",        -- LK11-T04, LK11-T09 (E01-T19: bubble checked by the requester client)
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
    "lk.barricade",     -- LK14-T03
    "lk.walls",         -- LK14-T04
    "lk.fortify_offscreen", -- LK14-T05
    "lk.windowkill",    -- LK06-T11
    "lk.retreat",       -- LK06-T12
    "lk.defense",       -- LK05-T09, LK06-T14
    "lk.chores",        -- LK05-T04
    "lk.meals",         -- LK05-T07 (E01-T19; clock to 6:59 at night)
    "lk.repair",        -- LK14-T06 (E01-T19; clock to 6:59 at night)
    "lk.expedition",    -- LK05-T05 (E01-T19; clock to 9:00 outside 7 h - 16 h)
    "lk.forage",        -- LK05-T11 (E01-T19; clock to 9:00 outside 7 h - 15 h)
    "rs.death",         -- E00-T02, E03-T04, E15-T02 (E01-T16: client 2 really dies, then respawns)
    "lk.routines",      -- LK05-T03 (E01-T19) LAST: moves the clock to 23:00 then to dawn
}

-- E01-T19: robustness with the vanilla population of Muldraugh and mortal players, on the dedicated server only.
-- The list does not change the world settings: the launcher does (autoclient.py --mp --server-campaign mp-ambient
-- --ambient-zombies --no-godmode, docs/annexes/tests/tests-en-jeu.md). Short suites whose outcome depends on zombies around:
-- registry load, zombie fights, alert and defence of a group, identity and facts of the players.
RST.CAMPAIGNS["mp-ambient"] = {
    "rs.identity",      -- E00-T01, E03-T04
    "rs.facts",         -- E14-T01, E14-T03
    "lk.load",          -- LK13-T02
    "lk.zombies",       -- LK06-T04
    "lk.alert",         -- LK05-T08
    "lk.defense",       -- LK05-T09, LK06-T14
}

-- LK13-T02 (2026-10-15): load measure with 5 groups and 4 players, on the dedicated server only (autoclient.py --mp
-- --load: new world with LivingKnox.GroupCount = 5, clients rs_mp1..rs_mp4). lk.load first (short measure, 20 s),
-- then lk.loadmp (players placed around the homes as in docs/annexes/tests/validation/charge-protocole.md, three phases of 5 min,
-- server and two client measures checked against the budgets; RST_LK_LOADMP_PHASE_MS on the server overrides 5 min).
RST.CAMPAIGNS["mp-load"] = {
    "lk.load",          -- LK13-T02 (short measure of the authority)
    "lk.loadmp",        -- LK13-T02 (protocol of charge-protocole.md, sections 2 to 5)
}

-- E01-T17: persistence across a reconnection and a restart of the dedicated server. Entries are BASES, not suites:
-- autoclient.py --mp --clients 2 --phases reconnect2,reconnect,restart --server-campaign mp-persist runs
-- <base>.before (opt-in "manual" snapshot), then after each action <base>.after-reconnect2 / .after-reconnect /
-- .after-restart when the suite exists (phase_plan).
-- Never a list for RST.campaign nor for a plain RST.server: the prefixes would only select the non-manual suites.
RST.CAMPAIGNS["mp-persist"] = {
    "rs.identity",        -- E00-T01: same identity, notes, engagements after reconnection and restart
    "lk.homes",           -- LK08-T04: no second furnishing after a restart
    "lk.leave",           -- E10-T04: loner group and departure kept by a restart
    "rs.mission.recover", -- E11-T06: one cache bag after a restart
    "rs.rescue.missed",   -- E12-T05: no second zombie nor notebook after a restart
    "lk.walls",           -- LK14-T04: wall kept after a reconnection and a restart
    "rs.radiotab",        -- E06-T05: Radio tab history of both players kept after a reconnection
    "rst.disconnect",     -- E01-T05: client 2 leaves (reconnect2) during the run it asked; report kept, not busy
    "rs.reputation",      -- E04-T14: score and facts kept by a restart, no duplicate
    "lk.rejoin",          -- LK03-T01: the executor rejoins (reconnect2); LAST: its before step moves the requester away
}

local function both()
    local out = {}
    for _, key in ipairs({ "solo-lk", "solo-rs" }) do
        for _, name in ipairs(RST.CAMPAIGNS[key] or {}) do out[#out + 1] = name end
    end
    return out
end

local function listOf(name)
    if name == "solo" and RST.CAMPAIGNS.solo == nil then return both() end
    return RST.CAMPAIGNS[name]
end

-- Index of the campaign entry selecting suite name (same rule as the filters: equal or "<entry>." prefix), or nil.
local function rank(list, name)
    for i, entry in ipairs(list) do
        if name == entry or string.sub(name, 1, #entry + 1) == entry .. "." then return i end
    end
    return nil
end

-- Jobs of the plan grouped by campaign entry, in the order of the list; jobs of other suites after, as planned.
local function reorder(jobs, list)
    local buckets, rest = {}, {}
    for _, job in ipairs(jobs) do
        local i = rank(list, job.suite and job.suite.name or "")
        if i == nil then
            rest[#rest + 1] = job
        else
            buckets[i] = buckets[i] or {}
            table.insert(buckets[i], job)
        end
    end
    local out = {}
    for i = 1, #list do
        for _, job in ipairs(buckets[i] or {}) do out[#out + 1] = job end
    end
    for _, job in ipairs(rest) do out[#out + 1] = job end
    return out
end

function RST.campaign(name)
    local list = listOf(name)
    if type(list) ~= "table" or #list == 0 then
        print("[RST] campaign refused: unknown or empty campaign '" .. tostring(name) .. "'")
        return false, "unknown or empty campaign"
    end
    local plan = RST.plan
    RST.plan = function(filter) return reorder(plan(filter), list) end
    local ok, started, reason = pcall(RST.run, { suite = list, exclude = {} })
    RST.plan = plan
    if not ok then return false, tostring(started) end
    if started then print("[RST] campaign '" .. name .. "': " .. #list .. " suite(s) in this order: "
        .. table.concat(list, ", ")) end
    return started, reason
end

function RST.campaigns()
    for _, key in ipairs({ "solo-lk", "solo-rs", "solo", "solo-retry", "mp", "mp-ambient", "mp-persist", "mp-load" }) do
        local list = listOf(key) or {}
        print("[RST] " .. key .. " (" .. #list .. "): " .. table.concat(list, ", "))
    end
end
