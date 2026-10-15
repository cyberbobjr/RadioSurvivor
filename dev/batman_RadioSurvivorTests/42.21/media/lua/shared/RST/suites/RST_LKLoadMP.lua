--[[
lk.loadmp - load measure of Living Knox in multiplayer with 5 groups and 4 players (LK13-T02, protocol
docs/validation/charge-protocole.md, sections 2 to 5, automated). Tags "world" and "server": dedicated server only, on
a world named rstest*, run from the admin client 1 (RST.server) with three other clients connected
(autoclient.py --mp --load: clients rs_mp1..rs_mp4, LivingKnox.GroupCount = 5; campaign "mp-load" of
RST_Campaign.lua). Solo, or fewer than 4 players online: SKIP (the short measure lk.load covers solo). Asynchronous
run only (about 3 x PHASE_MS plus the placement: 17 minutes by default).

Placement (protocol section 2), every player moved by the server (RST.Fixtures.movePlayer: "fx.move" asks the client
to send "/teleportto"; each move undone at the end): homes read in the group registry (LivingKnox.Groups.list, groups
with a home, sorted by id; FAIL with fewer than GROUPS):
    P1 = the requester, OWNER_D squares east of the home of group 1 (owner of its bodies);
    P2 = the first other client, OBSERVER_D squares west of it (observer);
    P3 = the second other client, OWNER_D squares east of the home of group 2 (owner of its bodies);
    P4 = the third other client, at least FAR_D squares from every home (no body in range).
Then the bodies of groups 1 and 2 must be in the world (materialization, LK09-T03) within BODIES_MS.
Measure (section 3): the server measure is started by an admin request of P1 (LivingKnox.Admin op "load", window
60 s, log lines), and the local measure of P1 and P2 (RST.Steps "lk.load.local", RST_PeerChecksLoad.lua). Three
phases of PHASE_MS (RST_LK_LOADMP_PHASE_MS on the server Lua state overrides it, at least 30 s):
    1. everybody still;
    2. P1 walks around the home of group 1 (moved by MOVE_STEP squares every MOVE_EVERY_MS on a ring of OWNER_D),
       P2 goes AWAY_D squares away at the start of the phase and comes back in the middle;
    3. free (everybody still again).
A report of the server is asked at the end of phase 2 (protocol: "a mi-parcours"). End: the server measure and the
local ones are stopped; every report line is kept as a note of the test (and printed in console.txt as "load:" lines
by each machine).
Checked (section 5): server: engine per tick, each module, messages and bytes sent per second, size of the state
within LivingKnox.Load.BUDGET.authority; the heaviest tick is noted, not asserted (expected over its 25 ms budget:
registry writes, hot spot 1 of charge-hors-jeu-2026-10-12.md). Clients P1 and P2: engine per tick and each module
within the client budget; their heaviest tick noted. A budget over is a FAIL naming the measure: the hot spot becomes
a new task.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_PeerChecksLoad"

local GROUPS = 5
local PLAYERS = 4
local OWNER_D = 7            -- squares from a home: owner of its bodies (protocol: 5 to 10)
local OBSERVER_D = 20        -- squares from the home of group 1 (protocol: 15 to 25)
local FAR_D = 160            -- squares from every home (protocol: more than 150)
local AWAY_D = 100           -- P2 goes away this far during phase 2
local MOVE_STEP = 3          -- squares per move of P1 around the home of group 1
local MOVE_EVERY_MS = 10000
local BODIES_MS = 120000
local WINDOW_MS = 60000
local STEP_MS = 30000

local function LK() return LivingKnox end
local function measure(text) print("[LKLM] measure " .. tostring(text)) end

local function phaseMs()
    local v = tonumber(RST_LK_LOADMP_PHASE_MS)
    if v == nil or v < 30000 then return 300000 end
    return v
end

-- Homes of the groups of the registry: { { gid, x, y, z } }, sorted by group id.
local function homes()
    local G = LK().Groups
    local out = {}
    for _, gid in ipairs(G.list()) do
        local g = G.peek and G.peek(gid) or G.get(gid)
        local h = g and g.home
        if type(h) == "table" and h.x ~= nil then out[#out + 1] = { gid = gid, x = h.x, y = h.y, z = h.z or 0 } end
    end
    table.sort(out, function(a, b) return a.gid < b.gid end)
    return out
end

-- Bodies of the members of group gid in the world.
local function bodiesOf(gid)
    local G, B = LK().Groups, LK().Bodies
    local g = G.get(gid)
    local n = 0
    for _, m in pairs(g and g.members or {}) do
        if m.npc ~= nil and B.find(m.npc) ~= nil then n = n + 1 end
    end
    return n
end

-- A point at least FAR_D squares (x or y gap) from every home, near home 1, or nil.
local function farPoint(list)
    local h1 = list[1]
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }) do
        for _, k in ipairs({ 1, 1.5, 2 }) do
            local x, y = h1.x + d[1] * FAR_D * k, h1.y + d[2] * FAR_D * k
            local ok = x > 0 and y > 0
            for _, h in ipairs(list) do
                if math.max(math.abs(x - h.x), math.abs(y - h.y)) < FAR_D then ok = false end
            end
            if ok then return math.floor(x), math.floor(y) end
        end
    end
    return nil
end

local function admin(p, action, n, extra)
    local req = { op = "load", action = action, n = n }
    for k, v in pairs(extra or {}) do req[k] = v end
    return LK().Admin.request(p, req)
end

-- Budget overs of a summary (texts), the heaviest tick left out (noted only).
local function overs(list)
    local out, maxTick = {}, nil
    for _, text in ipairs(list or {}) do
        if string.find(text, "^max tick") then maxTick = text else out[#out + 1] = text end
    end
    return out, maxTick
end

RST.suite("lk.loadmp", { tags = { "world", "server" }, testTimeoutMs = 3000000, timeoutMs = 3600000 }, function(s)
    s.test("5 groups, 4 players: server, owner and observer within the load budgets", function(t)
        if not isServer() then t:skip("dedicated server with four clients only (solo: lk.load)") end
        local E = LK()
        t:ok(E ~= nil and E.Load ~= nil and E.Admin ~= nil and E.Groups ~= nil and E.Groups.isReady(),
            "LivingKnox.Load, Admin or Groups is not ready on the server")
        if E.Load.active ~= nil then t:skip("a measure is already running (LivingKnox.Load.stop() to end it)") end
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no requesting player (t.ctx.player)")
        local others = RST.Steps.others(t)
        table.sort(others)
        if #others + 1 < PLAYERS then
            t:skip(PLAYERS .. " players needed, " .. (#others + 1) .. " online (autoclient.py --mp --load)")
        end
        local list = homes()
        measure(#list .. " group(s) with a home: " .. (function()
            local parts = {}
            for _, h in ipairs(list) do parts[#parts + 1] = h.gid .. "@" .. h.x .. "," .. h.y .. "," .. h.z end
            return table.concat(parts, " ")
        end)())
        t:ok(#list >= GROUPS, #list .. " group(s) with a home, " .. GROUPS .. " expected (sandbox LivingKnox.GroupCount = "
            .. GROUPS .. " on a new world: autoclient.py --mp --load)")
        local h1, h2 = list[1], list[2]
        local fx, fy = farPoint(list)
        t:ok(fx ~= nil, "no point " .. FAR_D .. " squares away from every home")
        local P2, P3, P4 = RST.Steps.playerOf(others[1]), RST.Steps.playerOf(others[2]), RST.Steps.playerOf(others[3])
        local names = { p:getUsername(), others[1], others[2], others[3] }
        measure("placement: P1 " .. names[1] .. " and P2 " .. names[2] .. " at " .. h1.gid .. ", P3 " .. names[3]
            .. " at " .. h2.gid .. ", P4 " .. names[4] .. " at " .. fx .. "," .. fy)
        local F = RST.Fixtures
        F.movePlayer(t, P4, fx, fy, 0, function(ta)
        F.movePlayer(ta, P3, h2.x + OWNER_D, h2.y, h2.z, function(tb)
        F.movePlayer(tb, P2, h1.x - OBSERVER_D, h1.y, h1.z, function(tc)
        F.movePlayer(tc, p, h1.x + OWNER_D, h1.y, h1.z, function(td)
        local since = getTimestampMs()
        td:waitUntil(function() return bodiesOf(h1.gid) > 0 and bodiesOf(h2.gid) > 0 end, BODIES_MS, function(t2)
            measure(string.format("bodies in the world after %d ms: group 1 %d, group 2 %d", getTimestampMs() - since,
                bodiesOf(h1.gid), bodiesOf(h2.gid)))
            local r = admin(p, "start", 1, { windowMs = WINDOW_MS, log = true })
            t2:ok(r.ok, "server measure refused: " .. tostring(r.err))
            t2:defer(function()
                if E.Load.active ~= nil then E.Load.stop() end
            end, "stop the server measure")
            local observers = { names[1], names[2] }
            RST.Steps.ask(t2, "lk.load.local", { action = "start", windowMs = WINDOW_MS },
                { target = observers, timeoutMs = STEP_MS }, function(t3)
                local phase = phaseMs()
                measure("phase 1: everybody still for " .. phase .. " ms")
                t3:sleep(phase, function(t4)
                    measure("phase 2: P1 walks around home 1, P2 goes " .. AWAY_D .. " squares away and back")
                    local p2x, p2y = P2:getX(), P2:getY()
                    sendServerCommand(P2, "RST", F.COMMAND, { x = p2x - AWAY_D, y = p2y, z = 0 })
                    local start, k, back = getTimestampMs(), 0, false
                    local nextMove = start + MOVE_EVERY_MS
                    t4:waitQuiet(function()
                        local now = getTimestampMs()
                        if not back and now - start >= phase / 2 then
                            back = true
                            sendServerCommand(P2, "RST", F.COMMAND, { x = p2x, y = p2y, z = 0 })
                        end
                        if now >= nextMove then
                            nextMove = now + MOVE_EVERY_MS
                            k = k + 1
                            local a = (k * MOVE_STEP / OWNER_D) % (2 * 3.14159265)
                            sendServerCommand(p, "RST", F.COMMAND, { x = h1.x + 0.5 + OWNER_D * math.cos(a),
                                y = h1.y + 0.5 + OWNER_D * math.sin(a), z = h1.z })
                        end
                        return now - start >= phase
                    end, phase + 60000, function(t5)
                        local rep = admin(p, "report", 2)
                        t5:ok(rep.ok, "server report refused: " .. tostring(rep.err))
                        for _, line in ipairs(rep.lines or {}) do t5:note("mid: " .. line) end
                        sendServerCommand(p, "RST", F.COMMAND, { x = h1.x + OWNER_D + 0.5, y = h1.y + 0.5, z = h1.z })
                        measure("phase 3: free (" .. k .. " move(s) of P1 in phase 2)")
                        t5:sleep(phase, function(t6)
                            local stop = admin(p, "stop", 3)
                            t6:ok(stop.ok, "server stop refused: " .. tostring(stop.err))
                            for _, line in ipairs(stop.lines or {}) do t6:note("server: " .. line) end
                            local sum = E.Load.last
                            t6:ok(sum ~= nil and sum.ticks > 0, "no server tick measured")
                            local bad, maxTick = overs(sum and sum.over)
                            if maxTick then t6:note("server heaviest tick (noted, hot spot 1): " .. maxTick) end
                            for _, text in ipairs(bad) do t6:ok(false, "server budget over: " .. text) end
                            measure(string.format("server: %.3f ms/tick, max %.1f ms, %.1f msg/s, %d B/s, %d over",
                                sum.perTickMs or 0, sum.tickMaxMs or 0, sum.sentPerSec or 0, sum.sentBytesPerSec or 0,
                                #bad))
                            RST.Steps.ask(t6, "lk.load.local", { action = "stop" },
                                { target = observers, timeoutMs = STEP_MS, assert = false }, function(t7, res)
                                    for i, user in ipairs(observers) do
                                        local a = res.by[user]
                                        local role = i == 1 and "owner P1" or "observer P2"
                                        t7:ok(a ~= nil and a.status == "PASS", role .. " " .. user .. ": local measure "
                                            .. tostring(a and a.status) .. " " .. tostring(a and a.message))
                                        local d = a and a.data
                                        if type(d) == "table" then
                                            for _, line in ipairs(d.lines or {}) do t7:note(role .. ": " .. line) end
                                            local cbad, cmax = overs(d.over)
                                            if cmax then t7:note(role .. " heaviest tick (noted): " .. cmax) end
                                            for _, text in ipairs(cbad) do
                                                t7:ok(false, role .. " budget over: " .. text)
                                            end
                                        end
                                    end
                                end)
                        end)
                    end, "phase 2 not over")
                end)
            end)
        end, "no body of group 1 or 2 in the world")
        end) end) end) end)
    end)
end)
