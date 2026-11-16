--[[
RST_Campaign - named campaigns of in-game suites run one after the other in ONE asynchronous run with ONE report
(development mod only). From the Lua console (debug mode, solo, save named rstest*):
    RST.campaign("solo-lk")     Living Knox suites to validate in solo (batman_LivingKnoxTests)
    RST.campaign("solo-rs")     RadioSurvivor suites to validate in solo (batman_RadioSurvivorTests)
    RST.campaign("solo")        every active test mod, core suites first, then Living Knox, then RadioSurvivor
    RST.campaign("solo-retry")  the suites that failed in the solo campaign of 2026-10-13, after their fixes
    RST.campaigns()             prints the campaigns and their suites
"mp", "mp-ambient" and "mp-load" are lists for the dedicated server (RST.server, RST_AutoClient serverCampaign), not
for RST.campaign. "mp-persist" lists bases of the phased MP run (autoclient.py --phases, E01-T17), not suites.

Registry (E21-T07). No test mod names another one: each registers its own part of a campaign,
    RST.Campaigns.add({ "solo-lk", "solo" }, 20, {
        "lk.fitness",
        ...
    })
names: the campaigns the part belongs to; rank: place of the part in each of them (parts sorted by rank, then by
registration; a suite already listed by an earlier part is not repeated); entries: suite names or dot prefixes. Ranks
in use: 10 core suites (this mod), 20 Living Knox, 30 RadioSurvivor, 80-90 suites that must come last (dead player,
clock moved). RST.CAMPAIGNS[name] is the merged list, rebuilt at each add (read by RST.campaign and RST_AutoClient).
Keep the layout above (one entry per line, the list closed by "})" at the start of a line): tools/autoclient reads
these files to know the campaigns of a run.

RST.campaign(name) -> true, or false and a reason. It is RST.run({ suite = <list>, exclude = {} }): every named suite,
world and server suites included (the explicit empty exclude lifts the default exclusion of RST_Client.lua; the world
guard of RST.lua still refuses world suites outside a save named rstest*). The suites run in the order of the list
(RST.select keeps the declaration order: the plan is reordered for this run only), then the usual report is printed
and written (Zomboid/Lua/batman_CoreAITests/tests/<stamp>-solo.txt). RST.cancel() stops it. A suite of a mod that is
not active is SKIP (RST.modsRefusal).
]]

require "RST/RST"
require "RST/RST_Client"

RST.CAMPAIGNS = RST.CAMPAIGNS or {}
RST.Campaigns = RST.Campaigns or { parts = {}, seq = 0 }
local Campaigns = RST.Campaigns

local function merge(parts)
    table.sort(parts, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.seq < b.seq
    end)
    local out, seen = {}, {}
    for _, part in ipairs(parts) do
        for _, name in ipairs(part.entries) do
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    return out
end

-- names: campaign name or list of names; rank: number; entries: list of suite names or prefixes.
function Campaigns.add(names, rank, entries)
    if type(names) == "string" then names = { names } end
    if type(names) ~= "table" or type(rank) ~= "number" or type(entries) ~= "table" then
        error("RST.Campaigns.add(names, rank, entries): bad arguments", 2)
    end
    Campaigns.seq = Campaigns.seq + 1
    for _, name in ipairs(names) do
        Campaigns.parts[name] = Campaigns.parts[name] or {}
        table.insert(Campaigns.parts[name], { rank = rank, seq = Campaigns.seq, entries = entries })
        RST.CAMPAIGNS[name] = merge(Campaigns.parts[name])
    end
end

-- Core suites of every solo campaign (needs the core mod only).
Campaigns.add({ "solo-lk", "solo-rs", "solo" }, 10, {
    "rst.guard",        -- E01-T06
    "ca.codec",         -- E01-T08
    "ca.notebook",      -- E18-T24 (bookmarks of the active mods)
    "ca.factions.mandate", -- E09-T03 (E21-T11: from the RadioSurvivor tests)
    "ca.reputation",    -- E04-T14 (E04-T04, T05, Q17; E21-T11: from the RadioSurvivor tests)
    -- E21-T11: suites of the core mod formerly in the RadioSurvivor tests.
    "ca.missions",      -- E01-T08, E00-T03, E00-T10, E11-T11, E11-T20 (prefix: clock, unclaimed, scout, solo)
    "ca.mission.signal.client", -- E11-T07 (requester notebook and map: accept, circle, hours, report, claim)
    "ca.notebook.ink",  -- E00-T12
    "ca.caches",        -- E11-T06 (every reward table of the caches holds real item scripts)
})

-- Multiplayer (E01-T15): suites run ON THE DEDICATED SERVER by an admin client, RST.server (the automatic client:
-- autoclient.py --mp --server-campaign mp; the driver adds exclude = { "manual" }). Server and shared suites first,
-- then world suites around the requester (spawn point of the test server: a house of Muldraugh; the suites that look
-- for another place move the players there, RST.Places with SERVER_MOVES: "/teleportto" asked by RST.Fixtures
-- "fx.move", every moved player brought back at the end), long group suites last. E01-T16: with --clients 2 the
-- second client answers the client checks of the suites (RST.Steps, RST_PeerChecks.lua) and is set to the access
-- level "user" for the rights tests. E01-T19: the server keeps only the "server" and "shared" suites of the list
-- (RST_Server.lua: default tags, "client" always excluded), so every entry is tagged "server" (or "shared").
Campaigns.add("mp", 10, {
    "rst.selftest",     -- engine on the server
    "ca.codec",         -- E01-T08
    "ca.identity",      -- E00-T01, E03-T04 (each online player bound to an identity)
    "ca.journal",       -- E18-T06 (rows of the mission journal of the core mod)
    "ca.factions.mandate", -- E09-T03 (two clients: vanilla faction, mandates of the Team tab)
    "ca.reputation",    -- E04-T14 (two clients: success of the requester only, admin view)
    -- E21-T11: suites of the core mod formerly in the RadioSurvivor tests.
    "ca.claim",         -- E00-T01 (E01-T16: the second client claiming another identity is refused)
    "rst.rights",       -- E01-T05 (E01-T16: a real user client refused RST.server, an admin told busy)
    "ca.missions",      -- E11-T03 (prefix: clock, unclaimed, scout, solo; NOT the templates ca.mission.*)
    "ca.mission",       -- E11-T04..T07, E01-T19 (prefix: clear, retrieve, recover, signal, signal.client, zones)
    "ca.caches",        -- E11-T06
})

-- E01-T19: robustness with the vanilla population of Muldraugh and mortal players (see RST_CampaignLK.lua).
Campaigns.add("mp-ambient", 10, {
    "ca.identity",      -- E00-T01, E03-T04
})

-- E01-T17: persistence across a reconnection and a restart of the dedicated server (bases, not suites).
Campaigns.add("mp-persist", 10, {
    "ca.identity",      -- E00-T01: same identity, notes, engagements after reconnection and restart
    "ca.reputation",    -- E04-T14: score and facts kept by a restart, no duplicate
    "ca.mission.recover", -- E11-T06: one cache bag after a restart
    "ca.state",         -- E16-T08: notebook state purged after game weeks, kept records and file valid after a restart
})

-- E01-T17: persistence across a reconnection (bases, see the test mods: autoclient.py --phases).
Campaigns.add("mp-persist", 85, {
    "rst.disconnect",   -- E01-T05: client 2 leaves (reconnect2) during the run it asked; report kept, not busy
})

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
    local list = RST.CAMPAIGNS[name]
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
    local names = {}
    for key in pairs(RST.CAMPAIGNS) do names[#names + 1] = key end
    table.sort(names)
    for _, key in ipairs(names) do
        local list = RST.CAMPAIGNS[key]
        print("[RST] " .. key .. " (" .. #list .. "): " .. table.concat(list, ", "))
    end
end
