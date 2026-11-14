--[[
rs.comfort - social comfort in game (E05-T15, server/RadioSurvivor/RS_Comfort.lua): when the answer of a voice to a
player goes on the air, the authority lowers his boredom and unhappiness by the sandbox amounts (ComfortBoredom,
ComfortSadness), syncs the stats to his client (syncPlayerStats) and tells it (command "comfort"), whose client shows
the vanilla down-arrow halo (RS_RadioTalk). Tags "server" and "world": the authority (solo, or RST.server from an admin
client, campaign mp), save rstest*.

    answer on the air   every online player starts from a synced baseline (boredom and unhappiness BASE, set on the
                        authority and synced like the comfort is); each client arms its halo recorder and reads the
                        baseline (RST.Steps "rs.comfort.arm", RST_PeerChecksComfort.lua). A test line is then queued on
                        the channel of a served voice through the REAL air queue of RadioSurvivor_Server with the REAL
                        comfort callback of the requester (GroupRadio.state.air and .comfort, bound by
                        GroupRadio.bind(queueAir, notify, comfortOnAir): the path of every answer to a player). Once it
                        aired: the authority copy dropped by the configured amounts; the requester client reads the
                        same drop on its own gauges and its two halos (Boredom, Unhappiness, arrow down)
                        ("rs.comfort.read"); every other client (second client in MP) reads no drop and no halo.
                        The real callback is called through CS.probe, which records the facts around it, so a failure
                        names its step: never aired (CS.whyNotAired: channel gone, busy with broadcast X, or line still
                        queued) or aired without comfort (CS.whyNotEased: requester not found or another player
                        object, notebook character changed, hourly cap, gauges eased through another RS_Comfort
                        table, refusal with gauges unchanged).
Cleanup (t:defer): stats of every touched player restored and synced, hourly cap counters and counters of RS_Comfort
restored, the test line removed from the radio histories. Solo runs the same code with the local player (no other
client: noted). Outside the game: tests/test_rs_comfort_suite.py (doubles), tests/test_comfort.py (module and wiring).
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_PeerChecksRadio"
require "RST/RST_PeerChecksComfort"

RST.ComfortSuite = RST.ComfortSuite or {}
local CS = RST.ComfortSuite
CS.MARK = "RST comfort "
CS.BASE = 50          -- baseline of both gauges (room for any amount up to 50)
CS.ASK_MS = 15000     -- client deadline of a step
CS.AIR_MS = 60000     -- the channel may be busy with another broadcast first
CS.TOLERANCE = 0.5    -- the client keeps simulating its own gauges between two reads

local Steps = RST.Steps
local PR = RST.PeerRadio

local function isServerSide() return type(isServer) == "function" and isServer() end

-- Modules of the authority; skips on an MP client or when the comfort is off.
local function setup(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the comfort is decided by the authority (solo or dedicated server), not an MP client")
    end
    local okC, Const = pcall(require, "RadioSurvivor/RadioSurvivor_Const")
    t:ok(okC and type(Const) == "table" and type(Const.comfortBoredom) == "function",
        "RadioSurvivor_Const (E05-T15) not loaded")
    if not Const.isEnabled() then t:skip("sandbox option RadioSurvivor.Enabled is off") end
    local boredom, sadness = Const.comfortBoredom(), Const.comfortSadness()
    if (boredom <= 0 and sadness <= 0) or Const.comfortPerHour() <= 0 then
        t:skip("comfort turned off by the sandbox options (ComfortBoredom, ComfortSadness, ComfortPerHour)")
    end
    local Comfort = require "RadioSurvivor/RS_Comfort"
    local GroupRadio = require "RadioSurvivor/RS_GroupRadio"
    local state = type(GroupRadio) == "table" and GroupRadio.state or {}
    t:ok(type(state.air) == "function" and type(state.comfort) == "function",
        "air queue and comfort callback not bound by RadioSurvivor_Server (GroupRadio.bind)")
    local p = t.ctx and t.ctx.player or nil
    if p == nil and not isServerSide() and type(getPlayer) == "function" then p = getPlayer() end
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    return { Const = Const, Comfort = Comfort, state = state, Personas = require "RadioSurvivor/RS_Personas",
        Log = require "RadioSurvivor/RS_RadioLog", p = p,
        drop = { boredom = math.min(boredom, CS.BASE), sadness = math.min(sadness, CS.BASE) } }
end

-- A frequency served by a voice channel, a free one first (the line airs at once); nil when none.
function CS.servedKhz(Personas)
    local busy = nil
    for _, id in ipairs(Personas.ids()) do
        for _, khz in ipairs(Personas.served(id)) do
            local channel = Personas.channel(khz)
            if channel ~= nil then
                if channel:getAiringBroadcast() == nil then return khz end
                busy = busy or khz
            end
        end
    end
    return busy
end

-- Caller key of RadioSurvivor_Server (callerKey): account name on a server, "solo" otherwise.
local function callerKey(p)
    if isServerSide() then return p:getUsername() end
    return "solo"
end

-- Players whose gauges the test sets: the requester and, on a server, every other online player.
local function players(t, p)
    local out = { { name = Steps.LOCAL, player = p } }
    if isServerSide() then
        out[1].name = p:getUsername()
        for _, name in ipairs(Steps.others(t)) do
            local other = Steps.playerOf(name)
            if other ~= nil then out[#out + 1] = { name = name, player = other } end
        end
    end
    return out
end

local function gauges(player)
    local s = player:getStats()
    return { boredom = s:get(CharacterStat.BOREDOM), sadness = s:get(CharacterStat.UNHAPPINESS) }
end

-- Sets both gauges on the authority and syncs them to the client like RS_Comfort does (no packet outside a server).
local function setGauges(player, values)
    local s = player:getStats()
    s:set(CharacterStat.BOREDOM, values.boredom)
    s:set(CharacterStat.UNHAPPINESS, values.sadness)
    if isServerSide() then
        syncPlayerStats(player, SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.BOREDOM)
            + SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.UNHAPPINESS))
    end
end

-- Gauges of every listed player restored (and synced) at the end, baseline set now.
local function baseline(t, list)
    for _, e in ipairs(list) do
        local saved = gauges(e.player)
        t:defer(function() setGauges(e.player, saved) end, "gauges of " .. e.name .. " restored")
        setGauges(e.player, { boredom = CS.BASE, sadness = CS.BASE })
    end
end

-- Hourly cap entries and counters of RS_Comfort restored at the end; the cap of key cleared now.
local function guardCap(t, Comfort, key)
    local saved = {}
    for k, e in pairs(Comfort.counts) do saved[k] = { hour = e.hour, given = e.given } end
    local applied, capped = Comfort.stats.applied, Comfort.stats.capped
    t:defer(function()
        local drop = {}
        for k in pairs(Comfort.counts) do drop[#drop + 1] = k end
        for _, k in ipairs(drop) do Comfort.counts[k] = nil end
        for k, e in pairs(saved) do Comfort.counts[k] = e end
        Comfort.stats.applied, Comfort.stats.capped = applied, capped
    end, "hourly comfort cap restored")
    Comfort.counts[key] = nil
end

-- Comfort key of RS_Comfort (keyOf): notebook character, else account (server) or "solo".
local function capKey(p, cid)
    if cid then return "c:" .. tostring(cid) end
    if isServerSide() then return "u:" .. tostring(p:getUsername()) end
    return "solo"
end

local function answerOf(res) return res and res.list and res.list[1] or {} end

local function mhz(khz) return string.format("%.1f MHz", (tonumber(khz) or 0) / 1000) end

-- Why the queued test line is not on the air yet (failure message of the wait): channel gone (the air queue drops
-- the line), channel still busy with another broadcast, or channel free with the line still queued.
function CS.whyNotAired(Personas, khz)
    local channel = Personas.channel(khz)
    if channel == nil then return "voice channel of " .. mhz(khz) .. " gone (RS_Personas.channel nil): line dropped" end
    local bc = channel:getAiringBroadcast()
    if bc ~= nil then
        return "voice channel of " .. mhz(khz) .. " still busy with broadcast " .. tostring(bc:getID())
    end
    return "voice channel of " .. mhz(khz) .. " free but the line still queued (air queue not drained)"
end

-- The real comfort callback of the requester (GroupRadio.state.comfort), with the facts around its call recorded
-- in probe: aired, requester found online under the caller key, notebook character on the air, RS_Comfort counters
-- and gauges of the requester on the authority before and after. The real callback alone decides the comfort.
function CS.probe(c, key, cid)
    local probe = { aired = false, key = key, cid = cid }
    local real = c.state.comfort(key, cid)
    probe.onAir = function()
        probe.aired = true
        local found = c.p
        if isServerSide() then found = Steps.playerOf(key) end
        probe.found, probe.same = found ~= nil, found == c.p
        probe.current = c.Log.characterOf(c.p)
        probe.dead = c.p:isDead()
        probe.applied, probe.capped = c.Comfort.stats.applied, c.Comfort.stats.capped
        probe.before = gauges(c.p)
        real()
        probe.after = gauges(c.p)
        probe.appliedAfter, probe.cappedAfter = c.Comfort.stats.applied, c.Comfort.stats.capped
    end
    return probe
end

-- Why the line aired without comforting the requester (failure message), from the facts of CS.probe.
function CS.whyNotEased(probe)
    if not probe.found then
        return "requester '" .. tostring(probe.key) .. "' not found online by the comfort callback (findPlayer)"
    end
    if not probe.same then
        return "the online player of '" .. tostring(probe.key) .. "' is another object than the requester of the run"
    end
    if probe.current ~= probe.cid then
        return "notebook character changed: " .. tostring(probe.cid) .. " at the request, " .. tostring(probe.current)
            .. " on the air (no comfort by design)"
    end
    if probe.cappedAfter > probe.capped then
        return "hourly cap of RS_Comfort refused the comfort (capped " .. probe.capped .. " -> " .. probe.cappedAfter .. ")"
    end
    local b, a = probe.before, probe.after
    if a.boredom < b.boredom or a.sadness < b.sadness then
        return "gauges eased on the authority but RS_Comfort.stats.applied unchanged (" .. probe.applied .. " -> "
            .. probe.appliedAfter .. "): the server comforts through another RS_Comfort table than the suite reads"
    end
    return string.format("RS_Comfort.answered refused with gauges unchanged (boredom %.2f, unhappiness %.2f, dead %s)",
        b.boredom, b.sadness, tostring(probe.dead))
end

RST.suite("rs.comfort", { tags = { "server", "world" } }, function(s)
    s.test("an answer on the air eases the requester only: gauges and halo on his client (E05-T15)", function(t)
        local c = setup(t)
        local khz = CS.servedKhz(c.Personas)
        if khz == nil then t:skip("no voice channel served in this world (RS_Personas): nothing can go on the air") end
        local cid = c.Log.characterOf(c.p)
        local list = players(t, c.p)
        t:defer(function() PR.stripHistory(CS.MARK) end, "test line removed from the radio histories")
        guardCap(t, c.Comfort, capKey(c.p, cid))
        baseline(t, list)
        local base = { boredom = CS.BASE, sadness = CS.BASE, tolerance = CS.TOLERANCE }
        Steps.ask(t, "rs.comfort.arm", base, { target = "all", timeoutMs = CS.ASK_MS }, function(t2, armed)
            local before = {}
            for _, e in ipairs(armed.list) do
                local d = e.data or {}
                t2:ok(d.synced == true, "client " .. e.user .. " never saw the synced baseline " .. CS.BASE
                    .. " (boredom " .. tostring(d.boredom) .. ", unhappiness " .. tostring(d.sadness) .. ")")
                before[e.user] = { boredom = d.boredom, sadness = d.sadness, watched = d.watched, why = d.why }
            end
            local probe = CS.probe(c, callerKey(c.p), cid)
            c.state.air(khz, { CS.MARK .. tostring(ZombRand(1000, 9999)) }, cid, probe.onAir)
            t2:waitUntil(function() return probe.aired end, CS.AIR_MS, function(t3)
                t3:ok(probe.appliedAfter > probe.applied, "the answer aired on " .. mhz(khz)
                    .. " without its comfort: " .. CS.whyNotEased(probe))
                local now = gauges(c.p)
                t3:near(CS.BASE - c.drop.boredom, now.boredom, 0.01, "boredom of the requester on the authority")
                t3:near(CS.BASE - c.drop.sadness, now.sadness, 0.01, "unhappiness of the requester on the authority")
                for i = 2, #list do
                    local other = gauges(list[i].player)
                    t3:near(CS.BASE, other.boredom, 0.01, "boredom of " .. list[i].name .. " on the authority")
                    t3:near(CS.BASE, other.sadness, 0.01, "unhappiness of " .. list[i].name .. " on the authority")
                end
                local me = list[1].name
                Steps.ask(t3, "rs.comfort.read", { before = before[me], drop = c.drop, tolerance = CS.TOLERANCE },
                    { target = "requester", timeoutMs = CS.ASK_MS }, function(t4, res)
                    local d = answerOf(res).data or {}
                    t4:near(c.drop.boredom, d.droppedBoredom, CS.TOLERANCE, "boredom drop read by the requester client")
                    t4:near(c.drop.sadness, d.droppedSadness, CS.TOLERANCE,
                        "unhappiness drop read by the requester client")
                    if d.watched then
                        t4:eq(c.drop.boredom > 0, d.haloBoredom == true, "Boredom halo (arrow down) on the requester")
                        t4:eq(c.drop.sadness > 0, d.haloSadness == true,
                            "Unhappiness halo (arrow down) on the requester")
                    else
                        t4:note("halo not observable on the requester client: " .. tostring(before[me].why)
                            .. "; gauges checked only")
                    end
                    local others = Steps.others(t4)
                    if #others == 0 then
                        t4:note("no other client online: isolation not checked")
                        return
                    end
                    -- No drop expected: each other client reads after RST.PeerComfort.SETTLE_MS (packets had time).
                    Steps.ask(t4, "rs.comfort.read", { tolerance = CS.TOLERANCE }, { target = others,
                        timeoutMs = CS.ASK_MS },
                        function(t5, res2)
                        for _, e in ipairs(res2.list) do
                            local o = e.data or {}
                            local b = before[e.user] or {}
                            t5:near(0, (tonumber(b.boredom) or 0) - (tonumber(o.boredom) or 0), CS.TOLERANCE,
                                "boredom drop read by the other client " .. e.user)
                            t5:near(0, (tonumber(b.sadness) or 0) - (tonumber(o.sadness) or 0), CS.TOLERANCE,
                                "unhappiness drop read by the other client " .. e.user)
                            t5:eq(0, tonumber(o.halos) or 0, "halos shown on the other client " .. e.user)
                        end
                    end)
                end)
            end, function() return "the answer never went on the air: " .. CS.whyNotAired(c.Personas, khz) end)
        end)
    end, { timeoutMs = 120000 })
end)

return CS
