--[[
lk.executor - Living Knox directives (LK02-T07, LivingKnox.Directives / Executor). Tags "world" and "server": the
authority only, on a save named rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.executor", tags = "world" }); dedicated server: RST.server({ suite = "lk.executor",
tags = "world" }) from an admin client standing still (the body is then simulated, and the directive executed, by a
client: checks that only the simulator can make are skipped there). Asynchronous run only (about 2 minutes; do not
pause the game).

What is measured here, on the authority:
    - "move" to a free square 9 squares east of the body: arrival within ARRIVE_MS, gesture walk during the trip and
      idle after it, travel flag off and useless back on the body (where it is simulated here);
    - "stop" 2 s after a 10-square "move": the directive is closed as stopped and the body stays still for 2 s;
    - "face" S: the directive is closed as faced and the body faces south (90 degrees) within 20 degrees;
    - LK03-T02: state reports of the body (LivingKnox.Reports, on the authority) accepted during the 9-square move,
      no suspect refusal for that npc (Reports.rejectedOf; none at all where the body is simulated here, a
      "previous lease" race being expected on a server when the move is leased to the client taking the body
      over), last accepted activity "arrived" (sent by the client that simulates the body on a server);
    - LK03-T05: gesture relay traffic during that move on a server (messages, entries, bytes, per second, per tick,
      deferred, emission delay, clients); solo: no relay message (direct call);
    - LK03-T01: solo, the body leaves the known bodies for one pass and comes back, the open "move" is resumed and
      closed once; an older or already finished directive is never started again. Dedicated server (2026-10-15):
      every client goes 300 squares away until the server unloads the square of the body, then back; the open move
      is sent again, resumed and closed "arrived" once with the same number, no new directive, the body stays at
      its target (serverReappearance).
Position and angle are read on the body where it is simulated here, else (dedicated server) from the last state
report accepted from its owner: the server copy of a remote zombie lags behind the owner's packets.
E01-T16 (LK02-T07): on a dedicated server, every client follows its own copy of the body during the 9-square move
(RST.Steps "lk.track", RST_PeerChecksLK2.lua): copy seen, then standing within 1.5 squares of the target; after the
face S directive every client sees the copy facing south (RST.Steps "lk.facing", RST_PeerChecksH.lua). The transfer
of ownership in the middle of a move is lk.handover (LK03-T03).
Figures are printed as "[LKX] measure ..." lines. Every test removes its npc (and its directive) with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksH"
require "RST/RST_PeerChecksLK2"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local ARRIVE_MS = 40000     -- 9 squares; pathfind walk measured at 6.5 squares in 8 s (LK02-T10)
local DONE_MS = 10000
local TRIP = 9
local STOP_AFTER_MS = 2000
local STILL_MS = 2000
local SETTLE_MS = 1500      -- server: rest, then one state report (STATE_MS) after the "stopped" one

local function B() return LivingKnox and LivingKnox.Bodies end
local function D() return LivingKnox and LivingKnox.Directives end
local function A() return LivingKnox and LivingKnox.Anim end
local function G() return LivingKnox and LivingKnox.ZombieGuard end

local function measure(text)
    print("[LKX] measure " .. tostring(text))
end

local round, standing, target, angleGap = K.round, K.standing, K.target, K.angleGap
local serverReappearance   -- LK03-T01 on a dedicated server, below

local function spawnNpc(t, dx, dy)
    t:ok(B() ~= nil and D() ~= nil and A() ~= nil, "LivingKnox.Bodies, Directives or Anim is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    -- Server only: there the house is the home of many earlier test groups, which lock its doors; in solo the
    -- unlocked window let the npc climb out and stay open, which changed the next suites (lk.defense in solo-lk).
    local unlocked = isServer() and K.unlockDoorsNear(t, p, 12) or 0
    if unlocked > 0 then measure(unlocked .. " locked door(s) or window(s) near the player unlocked") end
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function()
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id, body, p
end

-- LK02-T07 (E01-T16): step asked to every client on a dedicated server only (solo: the authority is the display).
local function viewStep(t, step, args, ms, after)
    if not isServer() then return after(t) end
    RST.Steps.ask(t, step, args, { target = "all", timeoutMs = ms }, after)
end

local function done(id)
    return function()
        local e = D().get(id)
        return e ~= nil and e.done == true
    end
end

local function owner(z)
    return G().simulatedHere(z) and "here" or "a client"
end

-- Position and facing of the body as known by the authority. On a dedicated server a body simulated by a client is a
-- remote zombie: its server copy follows the owner's packets with a delay (NetworkZombieAI.parse: realx set from the
-- packet, the copy walks there and is teleported only beyond 3 squares; the angle comes with the next packet), seen
-- up to 4.3 squares behind at the arrival in the MP campaign of 2026-10-14. The owner's accepted state report
-- (LivingKnox.Reports, LK03-T02) is then the position and angle of the body; elsewhere the body itself.
local function pose(id, b)
    local R = LivingKnox.Reports
    if b ~= nil and not G().simulatedHere(b) and R ~= nil then
        local s = R.get(id)
        if s ~= nil then return s.x, s.y, s.z, s.a, "report" end
        return nil
    end
    if b == nil then return nil end
    return b:getX(), b:getY(), b:getZ(), b:getDirectionAngle(), "body"
end

-- Refusals of the state reports of npc id: total, suspect ones (Reports.SUSPECT). A "previous lease" refusal when the
-- move is leased to the client that just took the body over is an expected network race (INFO), not a fault.
local function rejectedOf(R, id)
    if R.rejectedOf ~= nil then return R.rejectedOf(id) end
    return R.stats.rejected, R.stats.rejected
end

-- LK03-T01 on a dedicated server (decision of 2026-10-15, nothing cut): every client goes REAPPEAR_FAR squares away
-- (RST.Fixtures.movePlayers), so that the server unloads the square of the body (no client keeps it), then comes back:
-- the body comes back with its chunk, the open "move" (issued before the departure, REAPPEAR_TRIP squares) is
-- re-emitted to its new owner (Directives.watch: owner or body), resumed and closed "arrived" ONCE with the same
-- directive number, no new directive issued; REAPPEAR_STILL_MS later the directive is unchanged and the body (last
-- accepted report) still at its target: neither walked twice nor dropped. The release of bodies far from every player
-- (Config.BODIES.RELEASE_DELAY_MS, 60 s) is lengthened for the test, so that the npc stays embodied while away.
local REAPPEAR_FAR = 300
local REAPPEAR_TRIP = 25
local REAPPEAR_UNLOAD_MS = 60000
local REAPPEAR_ARRIVE_MS = 120000
local REAPPEAR_STILL_MS = 5000

serverReappearance = function(t)
    local F = RST.Fixtures
    local C = LivingKnox.Config.BODIES
    local delay = C.RELEASE_DELAY_MS
    C.RELEASE_DELAY_MS = 600000
    t:defer(function() C.RELEASE_DELAY_MS = delay end, "restore the release delay of the bodies")
    local id, _, p = spawnNpc(t, 2, 0)
    t:waitUntil(standing(id), STAND_MS, function(t2)
        local z = B().find(id)
        local sq = target(z, REAPPEAR_TRIP, 0)
        t2:ok(sq ~= nil, "no free target square " .. REAPPEAR_TRIP .. " squares east of the body")
        local tx, ty = sq:getX() + 0.5, sq:getY() + 0.5
        local v, why = D().moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk")
        t2:ok(v ~= nil, "move refused: " .. tostring(why))
        local st = D().stats
        local issued, reemitted, leases, unsuspended = st.issued, st.reemitted or 0, st.leases or 0, st.unsuspended or 0
        local bx, by, bz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
        local ox, oy, oz = p:getX(), p:getY(), p:getZ()
        t2:sleep(1500, function(t3)
            F.movePlayers(t3, p, ox + REAPPEAR_FAR, oy, oz, function(t4)
                local unloaded = function() return getCell():getGridSquare(bx, by, bz) == nil end
                t4:waitUntil(unloaded, REAPPEAR_UNLOAD_MS, function(t5)
                    local e5 = D().get(id)
                    measure("reappearance (server): body square unloaded, directive " .. tostring(e5 and e5.op) .. " #"
                        .. tostring(e5 and e5.v) .. " done " .. tostring(e5 and e5.done) .. ", suspended "
                        .. tostring(e5 and e5.suspended ~= nil))
                    t5:ok(e5 ~= nil and e5.v == v and not e5.done, "move closed or replaced while the body was away")
                    F.movePlayers(t5, p, ox, oy, oz, function(t6)
                        t6:waitUntil(function() return B().find(id) ~= nil end, 30000, function(t7)
                            t7:waitUntil(done(id), REAPPEAR_ARRIVE_MS, function(t8)
                                local e = D().get(id)
                                local s2 = D().stats
                                measure("reappearance (server): " .. tostring(e and e.s) .. ", directive #"
                                    .. tostring(e and e.v) .. ", issued +" .. (s2.issued - issued) .. ", re-emitted +"
                                    .. ((s2.reemitted or 0) - reemitted) .. ", leases +" .. ((s2.leases or 0) - leases)
                                    .. ", resumed after suspension +" .. ((s2.unsuspended or 0) - unsuspended)
                                    .. ", executed by " .. tostring(e and e.by))
                                t8:eq("arrived", e and e.s, "directive state")
                                t8:eq(v, e and e.v, "directive number")
                                t8:eq(issued, s2.issued, "no directive issued meanwhile")
                                t8:ok((s2.reemitted or 0) - reemitted + (s2.leases or 0) - leases >= 1,
                                    "move never sent again after the reappearance (no re-emission nor new lease)")
                                t8:sleep(REAPPEAR_STILL_MS, function(t9)
                                    local e9 = D().get(id)
                                    local x9, y9 = pose(id, B().find(id))
                                    local away = x9 and D().dist(x9, y9, tx, ty) or nil
                                    measure("reappearance (server): " .. REAPPEAR_STILL_MS .. " ms later directive #"
                                        .. tostring(e9 and e9.v) .. " " .. tostring(e9 and e9.s) .. ", body "
                                        .. tostring(away and round(away)) .. " squares from the target")
                                    t9:eq(v, e9 and e9.v, "directive number after the arrival")
                                    t9:eq("arrived", e9 and e9.s, "directive state after the arrival")
                                    t9:ok(away ~= nil and away < 2.5, "body away from its target after the arrival: "
                                        .. tostring(away and round(away)))
                                end)
                            end, "move not finished after the reappearance")
                        end, "npc body not back after the way back")
                    end)
                end, "square of the body still loaded with every player away")
            end)
        end)
    end, "npc still on the floor")
end

RST.suite("lk.executor", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 600000 }, function(s)
    s.test("move 9 squares: arrival, walk then idle, useless back", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local sq = target(z, TRIP, 0)
            t2:ok(sq ~= nil, "no free target square near " .. TRIP .. " squares east of the body")
            local x0, y0 = z:getX(), z:getY()
            local key = id .. "-" .. tostring(getTimestampMs())
            viewStep(t2, "lk.track", { phase = "begin", key = key, npc = id }, 5000, function(t2b)
                t2 = t2b
            local v, why = D().moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk")
            t2:ok(v ~= nil, "move refused: " .. tostring(why))
            local start = getTimestampMs()
            local seen = { walk = false, states = {}, travel = false }
            local R = LivingKnox.Reports
            local rs = R and R.stats
            local acc0, rej0, sus0 = rs and rs.accepted or 0, 0, 0
            if R ~= nil then rej0, sus0 = rejectedOf(R, id) end
            local RL = LivingKnox.Relay
            local relay0 = RL and RL.stats and { m = RL.stats.messages, b = RL.stats.bytes, e = RL.stats.entries } or nil
            -- Largest emission delay of THIS move: the session maximum included a server stall of an earlier suite
            -- (354 ms in the MP campaign of 2026-10-14); the session value is put back after the measure.
            if relay0 ~= nil then
                relay0.maxDelay = RL.stats.maxDelay
                RL.stats.maxDelay = -1
                t2:defer(function() RL.stats.maxDelay = math.max(RL.stats.maxDelay, relay0.maxDelay) end,
                    "session maximum of the gesture emission delay put back")
            end
            local function arrived()
                if A().gestureOf(id) == "walk" then seen.walk = true end
                if G().isTravelling(id) then seen.travel = true end
                local b = B().find(id)
                if b ~= nil then seen.states[tostring(b:getCurrentStateName())] = true end
                return done(id)()
            end
            t2:waitUntil(arrived, ARRIVE_MS, function(t3)
                local e = D().get(id)
                local b = B().find(id)
                local ms = getTimestampMs() - start
                local names = {}
                for k in pairs(seen.states) do names[#names + 1] = k end
                table.sort(names)
                local goal = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
                local copy = nil
                if b ~= nil then copy = D().distToTarget(goal, b:getX(), b:getY(), b:getZ()) end
                measure("move " .. TRIP .. " squares: " .. tostring(e and e.s) .. " in " .. ms .. " ms, path from "
                    .. round(x0) .. "," .. round(y0) .. " to " .. sq:getX() .. "," .. sq:getY() .. ", distance to target "
                    .. tostring(copy and round(copy)) .. " (copy here), executed by " .. tostring(e and e.by)
                    .. ", states " .. table.concat(names, " ") .. ", travel flag seen " .. tostring(seen.travel))
                t3:ok(b ~= nil, "npc body lost")
                t3:eq("arrived", e and e.s, "directive state")
                t3:ok(seen.walk, "gesture walk not seen during the trip")
                t3:eq("idle", A().gestureOf(id), "gesture after the arrival")
                t3:sleep(1000, function(t4)
                    local px, py, pz, _, from = pose(id, B().find(id))
                    local dist = px and D().distToTarget(goal, px, py, pz) or nil
                    measure("arrival position (" .. tostring(from) .. "): " .. tostring(dist and round(dist))
                        .. " squares from the target")
                    t4:ok(dist ~= nil and dist <= D().ARRIVE + 1, "body " .. tostring(dist) .. " squares from the target")
                    if rs ~= nil then
                        local rejN, susN = rejectedOf(R, id)
                        local acc, rej, sus = rs.accepted - acc0, rejN - rej0, susN - sus0
                        local last = R.get(id)
                        measure("state reports during the move: " .. acc .. " accepted, " .. rej .. " refused, last "
                            .. tostring(last and last.act) .. " pose " .. tostring(last and last.pose) .. " health "
                            .. tostring(last and round(last.hp)) .. " by " .. tostring(last and last.by) .. ", suspect "
                            .. sus)
                        t4:ok(acc >= 2, "only " .. acc .. " state report(s) accepted during the move")
                        t4:eq(0, sus, "suspect state reports refused during the move")
                        local zb = B().find(id)
                        if zb == nil or G().simulatedHere(zb) then
                            t4:eq(0, rej, "state reports refused during the move")   -- no network race here
                        end
                        t4:eq("arrived", last and last.act, "last reported activity")
                    else
                        measure("state reports not checked: LivingKnox.Reports is not loaded here")
                    end
                    -- LK03-T05: gesture relay traffic during the move (server only; solo calls directly).
                    if isServer() and relay0 ~= nil then
                        local rst = RL.stats
                        measure(string.format("gesture relay during the move: %d msg, %d entries, %d B; max %d msg/s"
                            .. " %d B/s, max %d msg per tick, %d deferred; emission delay last %d max %d mean %.1f ms"
                            .. " (kept states max %d ms); clients %s", rst.messages - relay0.m, rst.entries - relay0.e,
                            rst.bytes - relay0.b, rst.maxMsgsPerSec, rst.maxBytesPerSec, rst.maxPerTick, rst.deferred,
                            rst.lastDelay, rst.maxDelay, RL.meanDelay(), rst.keptMaxDelay, RL.clientLine(rst.byClient)))
                        t4:ok(rst.messages > relay0.m, "no gesture relayed during the move")
                        t4:ok(rst.maxDelay <= LivingKnox.Config.RELAY.WINDOW_MS + 200,
                            "gesture emission delay " .. tostring(rst.maxDelay) .. " ms")
                    else
                        measure("gesture relay not used here (solo: direct call, no message)")
                        t4:ok(RL == nil or RL.stats == nil or RL.stats.messages == 0, "gesture relay sent messages in solo")
                    end
                    local z4 = B().find(id)
                    t4:ok(z4 ~= nil, "npc body lost")
                    t4:eq(false, G().isTravelling(id), "travel flag after the arrival")
                    if G().simulatedHere(z4) then
                        t4:eq(true, z4:isUseless(), "useless after the arrival")
                    else
                        measure("useless after the arrival not checked here: simulated by " .. owner(z4))
                    end
                    -- LK02-T07 (E01-T16): every client saw its copy walk to the target.
                    viewStep(t4, "lk.track", { phase = "end", key = key, target = goal, tol = 1.5 }, 10000,
                        function() end)
                end)
            end, "move not finished")
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 120000 })

    s.test("stop during a move: closed as stopped, body still", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local sq = target(z, TRIP + 1, 0)
            t2:ok(sq ~= nil, "no free target square")
            local v, why = D().moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk")
            t2:ok(v ~= nil, "move refused: " .. tostring(why))
            t2:sleep(STOP_AFTER_MS, function(t3)
                local sv, swhy = D().stop(id)
                t3:ok(sv ~= nil, "stop refused: " .. tostring(swhy))
                t3:waitUntil(done(id), DONE_MS, function(t4)
                    local e = D().get(id)
                    local b = B().find(id)
                    t4:eq("stopped", e and e.s, "directive state")
                    t4:ok(b ~= nil, "npc body lost")
                    local function still(tS)
                        local x1, y1, _, _, from = pose(id, B().find(id))
                        tS:ok(x1 ~= nil, "no position of the body after the stop")
                        tS:sleep(STILL_MS, function(t5)
                            local b5 = B().find(id)
                            t5:ok(b5 ~= nil, "npc body lost")
                            local x5, y5 = pose(id, b5)
                            local moved = D().dist(x5, y5, x1, y1)
                            measure("stop after " .. STOP_AFTER_MS .. " ms of walk: moved " .. round(moved)
                                .. " squares in " .. STILL_MS .. " ms after the stop (" .. tostring(from)
                                .. "), executed by " .. tostring(e.by) .. ", gesture " .. A().gestureOf(id))
                            t5:ok(moved < 0.5, "body moved " .. round(moved) .. " squares after the stop")
                            t5:eq("idle", A().gestureOf(id), "gesture after the stop")
                        end)
                    end
                    if G().simulatedHere(b) then
                        still(t4)
                    else
                        -- Server: the "stopped" report leaves the owner when the walk is cut, before the body
                        -- has come to rest (0.51 and 0.53 squares in the MP campaign of 2026-10-14, 0.12 to 0.45
                        -- otherwise): the reference is the report SETTLE_MS later.
                        t4:sleep(SETTLE_MS, function(t4b) still(t4b) end)
                    end
                end, "stop not finished")
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 90000 })

    -- LK03-T01, solo only (the executor runs on this machine): the body leaves the known bodies for one pass (as when
    -- its chunk unloads) and comes back; the open "move" is resumed from the current position, same directive, closed
    -- once; then an older or already finished directive is never started again.
    s.test("body reappearance: open move resumed, stale directive ignored", function(t)
        local X = LivingKnox and LivingKnox.Executor
        if isServer() then return serverReappearance(t) end
        if X == nil then
            t:skip("the executor is not loaded here")
            return
        end
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local sq = target(z, TRIP, 0)
            t2:ok(sq ~= nil, "no free target square")
            local v, why = D().moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk")
            t2:ok(v ~= nil, "move refused: " .. tostring(why))
            local issued = D().stats.issued
            t2:sleep(1500, function(t3)
                local resumed = X.stats.resumed or 0
                local saved = B().bound[id]
                t3:ok(saved ~= nil, "npc body lost")
                B().bound[id] = nil
                X.pass()
                local released = X.runs[id] == nil
                B().bound[id] = saved
                t3:ok(released, "execution not released while the body was gone")
                t3:waitUntil(done(id), ARRIVE_MS, function(t4)
                    local e = D().get(id)
                    measure("reappearance: " .. tostring(e and e.s) .. ", directive #" .. tostring(e and e.v)
                        .. ", resumed " .. tostring((X.stats.resumed or 0) - resumed) .. " time(s)")
                    t4:eq("arrived", e and e.s, "directive state")
                    t4:eq(v, e and e.v, "directive number")
                    t4:eq(issued, D().stats.issued, "no directive issued meanwhile")
                    t4:ok((X.stats.resumed or 0) > resumed, "move not resumed after the reappearance")
                    local sv = D().stop(id)
                    t4:ok(sv ~= nil, "stop refused")
                    t4:waitUntil(done(id), DONE_MS, function(t5)
                        local e5 = D().get(id)
                        local ok1, why1 = X.mayStart(id, { v = v, l = e5.l })
                        local ok2, why2 = X.mayStart(id, { v = e5.v, l = e5.l })
                        measure("stale: older directive " .. tostring(why1) .. ", finished directive "
                            .. tostring(why2))
                        t5:eq(false, ok1, "older directive accepted")
                        t5:eq("stale", why1, "older directive")
                        t5:eq(false, ok2, "finished directive accepted again")
                    end, "stop not finished")
                end, "move not finished after the reappearance")
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 330000 })

    s.test("face S: closed as faced, body facing south", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local v, why = D().face(id, "S")
            t2:ok(v ~= nil, "face refused: " .. tostring(why))
            t2:waitUntil(done(id), DONE_MS, function(t3)
                local e = D().get(id)
                t3:eq("faced", e and e.s, "directive state")
                t3:sleep(1500, function(t4)
                    local b = B().find(id)
                    t4:ok(b ~= nil, "npc body lost")
                    local _, _, _, a, from = pose(id, b)
                    t4:ok(a ~= nil, "no angle of the body after the face")
                    measure("face S: angle " .. round(a) .. " degrees (" .. tostring(from) .. ", expected 90; copy here "
                        .. round(b:getDirectionAngle()) .. "), simulated by " .. owner(b))
                    t4:ok(angleGap(a, 90) <= 20, "body faces " .. round(a) .. " degrees, not south (90)")
                    -- LK02-T07 (E01-T16): every client sees its copy facing south (a point 10 squares south).
                    viewStep(t4, "lk.facing", { bodies = { { npc = id, x = b:getX(), y = b:getY() + 10 } }, maxDeg = 30 },
                        5000, function() end)
                end)
            end, "face not finished")
        end, "npc still on the floor")
    end, { timeoutMs = 60000 })

    -- LK03-T07: a body put aside when its chunk unloads stays bound (same Java object, not dead) but leaves the zombie
    -- list; the executor stops reporting it (Executor.loadedBodies) instead of sending reports refused "no body". The
    -- release delay is lengthened for the test so that the npc stays embodied while the player is away.
    s.test("unloaded body: no state report refused, reports and walk resumed on return", function(t)
        local F = RST.Fixtures
        if (type(isClient) == "function" and isClient()) or isServer() then
            t:skip("solo only: the executor and the authority run in the same game")
        end
        local Rp, X = LivingKnox.Reports, LivingKnox.Executor
        t:ok(Rp ~= nil and X ~= nil and X.loadedBodies ~= nil, "LivingKnox.Reports or Executor (LK03-T07) not loaded")
        local C = LivingKnox.Config.BODIES
        local delay = C.RELEASE_DELAY_MS
        C.RELEASE_DELAY_MS = 900000
        t:defer(function() C.RELEASE_DELAY_MS = delay end, "restore the release delay")
        local id, _, p = spawnNpc(t, 2, 0)
        local ox, oy, oz = p:getX(), p:getY(), p:getZ()
        local function noBody() return Rp.stats.why["no body"] or 0 end
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local bx, by, bz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
            local sq = target(z, TRIP, 0)
            t2:ok(sq ~= nil, "no free target square near " .. TRIP .. " squares east of the body")
            t2:ok(D().moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk") ~= nil, "move refused")
            local nb0, ul0 = noBody(), X.stats.unloaded or 0
            F.movePlayer(t2, p, ox + K.FAR, oy, oz, function(t3)
                t3:waitUntil(function() return getCell():getGridSquare(bx, by, bz) == nil end, 60000, function(t4)
                    t4:sleep(10000, function(t5)
                        local _, state = B().find(id)
                        measure(string.format("away: npc %s, refused no body +%d, executor unloaded passes +%d, "
                            .. "directive %s", tostring(state), noBody() - nb0, (X.stats.unloaded or 0) - ul0,
                            tostring(D().get(id) and D().get(id).s)))
                        t5:eq("embodied", state, "npc state while its body is out of the loaded area")
                        t5:eq(0, noBody() - nb0, "state reports refused \"no body\" while away")
                        F.movePlayer(t5, p, ox, oy, oz, function(t6)
                            F.waitSquare(t6, bx, by, bz, 30000, function(t7)
                                t7:waitUntil(function() return B().find(id) ~= nil end, 20000, function(t8)
                                    local back = getTimestampMs()
                                    t8:waitUntil(function()
                                        local r = Rp.get(id)
                                        return r ~= nil and r.ms ~= nil and r.ms >= back
                                    end, 10000, function(t9)
                                        local first = D().get(id)
                                        local zb = B().find(id)
                                        local sq2 = target(zb, -5, 0) or target(zb, 5, 0)
                                        t9:ok(sq2 ~= nil, "no free square 5 squares from the body")
                                        t9:ok(D().moveTo(id, sq2:getX(), sq2:getY(), sq2:getZ(), "walk") ~= nil,
                                            "move after the return refused")
                                        t9:waitUntil(done(id), ARRIVE_MS, function(t10)
                                            local e = D().get(id)
                                            measure(string.format("back: first move %s, new move %s, refused no body "
                                                .. "+%d", tostring(first and first.s), tostring(e and e.s),
                                                noBody() - nb0))
                                            t10:eq("arrived", e and e.s, "walk after the return")
                                            t10:eq(0, noBody() - nb0, "state reports refused \"no body\"")
                                        end, "move after the return not finished")
                                    end, "no state report accepted after the return")
                                end, "body not bound again after the return")
                            end)
                        end)
                    end)
                end, "body square still loaded")
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 240000 })
end)
