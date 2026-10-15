--[[
lk.handover - ownership of a Living Knox body handed over during a trip, without loss of state (LK03-T03,
LivingKnox.Directives handover, LK_Executor). Tags "world" and "server". Dedicated server with two clients only
(autoclient --mp --clients 2): RST.server({ suite = "lk.handover", tags = "world" }); solo or a single client: SKIP
(one machine simulates every body). Asynchronous run only (about 2 minutes).

What is done, on the server: an npc 2 squares east of the requester gets a "move" of TRIP squares east (walk). The two
clients then approach it in turn: the client that does not own the body is moved BEHIND squares behind it (F.movePlayer, vanilla
"/teleportto" sent by that client) and the owner AWAY squares behind, so that the engine gives the body to the
other connection (nearest player, NetworkZombieManager); then again the other way round. Measured during the trip:
    - each owner change seen by the server (Directives.ownerName at every tick) and the resumption by the new executor
      (Directives.stats.resumed / resumeLast: delay from the change to its first accepted execution report);
    - the stop of the body around each change: gap between the last execution report showing progress (more than
      MOVE_EPS squares since the previous one) before the change and the first one after it; the executor reports
      once per REPORT_MS while walking, so a resumption within one second gives a gap of at most REPORT_MS +
      STALL_MS (the server copy is not used: it only follows the owner's zombie packets, every 4 s);
    - one directive, carried to its end ("arrived", same number; directives issued meanwhile for any npc printed),
      no suspect
      state report refused for that npc (Reports.rejectedOf).
Accepted (plan): the npc goes on with its action without a stop longer than one second: resumption <= RESUME_MS and
progress gap <= REPORT_MS + STALL_MS at each change. Figures: "[LKH] measure ..." lines. Players go back to their places and the
npc is forgotten with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecksLK"

local K = RST.LKHelpers
local PL = RST.PeerChecksLK
local measure = K.measurer("[LKH]")
local TRIP = 30             -- squares east (pathfind walk measured at about 0.8 square/s: about 40 s)
local TRIP_MIN = 20         -- shortest trip accepted when nothing is free TRIP squares east (two hand-overs fit)
local AWAY = 20             -- squares behind: beyond the owner hysteresis (x 1.618) of the nearest-player rule, and
                            -- still inside the loaded area of that client (MP campaign of 2026-10-15, commit 54087fb:
                            -- with 60, the client sent away no longer had a copy of the body; brought back for the
                            -- next hand-over, its copy came back with the area 3357 ms after it got the body)
local BEHIND = 2            -- squares behind the body, away from its next step (players are solid)
local SWITCH_MS = 20000     -- owner change after the moves (2 s between two changes, ZombieList up to 3 s)
local ARRIVE_MS = 90000
local RESUME_MS = 1000
local STALL_MS = 1000
local MOVE_EPS = 0.3     -- squares between two execution reports: the body walked
local REPORT_MS = 1000   -- Directives.REPORT_MS: one execution report per second while walking
local CLIMB_RECOVER_MS = 1000   -- still after a climb before the path goes on (934 ms measured by lk.traversal)
local HOLD_MS = 3000     -- the engine keeps an owner 2 s at least after a change (lastChangeOwner): the next hand-over
                         -- waits that long and for a progress by the new owner (MP campaign of 2026-10-15: the new
                         -- owner was sent away 200 ms after it got the body, 2 s without progress counted twice)
local OUT_MS = 20000     -- the body out of its start building (door) before the first hand-over

local function B() return LivingKnox and LivingKnox.Bodies end
local function D() return LivingKnox and LivingKnox.Directives end
local function R() return LivingKnox and LivingKnox.Reports end

-- Sampler of the trip, run at each server tick (OnTick, removed by t:defer): owner changes, resumptions, and the
-- progress of the body read from the accepted execution reports (Directives.accepted: position and server time of
-- each report of the executor, about one per REPORT_MS while walking). The server copy of a remote zombie is not
-- used: it only follows the owner's zombie packets (every 4 s, Config.REPORTS) and stops between two of them.
local function sampler(t, id)
    local m = { changes = {}, progress = {}, owner = nil, last = nil, seenMs = nil, resumed = {},
        resumed0 = D().stats.resumed or 0, climbs = {} }
    local function tick()
        local z = B().find(id)
        local e = D().get(id)
        if z == nil or e == nil then return end
        -- Climbs of the body (state climbwindow / climbfence, "-network" on a copy): no progress there by nature
        -- (MP campaign of 2026-10-15: path over 2 fence crossings, gap of 3049 ms around a change during a climb).
        local okName, name = pcall(function() return z:getActionStateName() end)
        local climbing = okName and type(name) == "string" and string.find(name, "^climb") ~= nil
        -- A gesture of the npc (window opened on its way, force, wait: LivingKnox.Anim.actOf on the authority) is a
        -- stop by design too. A door is no gesture (the executor waits for its synchronised state): the hand-overs
        -- start once the body is out of its start building (OUT_MS).
        local A = LivingKnox and LivingKnox.Anim
        if not climbing and A ~= nil and A.actOf ~= nil and A.actOf(id) ~= nil then climbing = true end
        local open = m.climbs[#m.climbs]
        if climbing and (open == nil or open.to ~= nil) then
            m.climbs[#m.climbs + 1] = { from = getTimestampMs() }
        elseif not climbing and open ~= nil and open.to == nil then
            open.to = getTimestampMs()
        end
        local owner = D().ownerName(z)
        if m.owner ~= nil and owner ~= m.owner then
            m.changes[#m.changes + 1] = { from = m.owner, to = owner, ms = getTimestampMs() }
        end
        m.owner = owner
        local st = D().stats
        if (st.resumed or 0) > m.resumed0 + #m.resumed then m.resumed[#m.resumed + 1] = st.resumeLast end
        local a = D().accepted[id]
        if a ~= nil and a.ms ~= m.seenMs then
            m.seenMs = a.ms
            if m.last == nil or D().dist(a.x, a.y, m.last.x, m.last.y) > MOVE_EPS then
                m.progress[#m.progress + 1] = a.ms
                m.last = { x = a.x, y = a.y }
            end
        end
    end
    Events.OnTick.Add(tick)
    t:defer(function() Events.OnTick.Remove(tick) end, "trip sampler removed")
    m.tick = tick
    return m
end

-- Longest time without progress around each owner change: gap between the last progress report before the change
-- (at the earliest the change itself: a stop of the previous owner before the change is not the hand-over's; MP pass
-- of 2026-10-15 09:42, 2277 ms of which 1.6 s before the change) and the first one after it, less the time the body
-- spent climbing (and CLIMB_RECOVER_MS after each climb) inside that gap (nil when the trip ended first).
local function stopsAround(m)
    local out = {}
    for i, c in ipairs(m.changes) do
        local before, after = nil, nil
        for _, ms in ipairs(m.progress) do
            if ms <= c.ms then before = ms elseif after == nil then after = ms end
        end
        if before ~= nil and after ~= nil then
            if before < c.ms then before = c.ms end
            local gap = after - before
            for _, cl in ipairs(m.climbs) do
                local from, to = cl.from, (cl.to or after) + CLIMB_RECOVER_MS
                local lo, hi = math.max(from, before), math.min(to, after)
                if hi > lo then gap = gap - (hi - lo) end
            end
            out[i] = gap
        end
    end
    return out
end

-- Moves the current owner AWAY squares west of the body and the other client behind it; then suite(t, name).
local function handTo(t, id, players, m, suite)
    local z = B().find(id)
    t:ok(z ~= nil, "npc body lost")
    local owner = D().ownerName(z)
    local other = nil
    for name in pairs(players) do
        if name ~= owner then other = name end
    end
    if owner == "server" or players[owner] == nil then
        t:note("owner before the moves: " .. tostring(owner))
        owner = nil
        for name in pairs(players) do
            if name ~= other then owner = name end
        end
    end
    local bx, by, bz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    local n0 = #m.changes
    -- The new owner stands BEHIND squares behind the body, opposite to its next step, from the last accepted
    -- execution report (the server copy lags up to 4 s): MP campaign of 2026-10-15, the client placed at bx - 1, by + 1
    -- of the server copy landed on the square of the body after a turn of its path and blocked it (players are
    -- solid), 3 s without progress.
    local e, a = D().get(id), D().accepted[id]
    local px, py = (a and a.x) or z:getX(), (a and a.y) or z:getY()
    local vx, vy = 1, 0
    if e ~= nil then
        local tx, ty = D().stepTarget(e, e.k)
        if type(tx) == "number" and type(ty) == "number" then
            local dx, dy = tx + 0.5 - px, ty + 0.5 - py
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.1 then vx, vy = dx / len, dy / len end
        end
    end
    local nx, ny = math.floor(px - vx * BEHIND) + 0.5, math.floor(py - vy * BEHIND) + 0.5
    -- The other client first stands behind the body, then the owner goes away: never a moment with the owner far
    -- and no successor near.
    RST.Fixtures.movePlayer(t, players[other], nx, ny, bz, function(t2)
        RST.Fixtures.movePlayer(t2, players[owner], bx - AWAY, by, bz, function(t3)
            t3:waitUntil(function()
                local c = m.changes[#m.changes]
                if #m.changes <= n0 or m.owner ~= other or c == nil then return false end
                if getTimestampMs() - c.ms < HOLD_MS then return false end
                local last = m.progress[#m.progress]
                local cur = D().get(id)
                return (last ~= nil and last > c.ms) or (cur ~= nil and cur.done)
            end, SWITCH_MS + HOLD_MS, function(t4)
                measure("owner " .. tostring(owner) .. " -> " .. other .. " after the moves; changes so far "
                    .. #m.changes .. ", resumptions " .. #m.resumed)
                return suite(t4, other)
            end, "body not handed to (or not walked by) " .. tostring(other))
        end)
    end)
end

RST.suite("lk.handover", { tags = { "world", "server" }, testTimeoutMs = 240000, timeoutMs = 300000 }, function(s)
    s.test("two clients approach in turn: the npc walks on, resumed within 1 s each time", function(t)
        if RST.Steps.isSolo() or PL.peer(t) == nil then
            t:skip("needs a dedicated server with two clients (ownership changes between connections)")
        end
        t:ok(B() ~= nil and D() ~= nil and R() ~= nil, "LivingKnox.Bodies, Directives or Reports not loaded here")
        local p = RST.Fixtures.player(t)
        local peerName = PL.peer(t)
        local players = {}
        players[PL.accountOf(p)] = p
        players[peerName] = RST.Steps.playerOf(peerName)
        t:ok(players[peerName] ~= nil, "second client " .. peerName .. " not online")
        local id, body = B().spawn({}, math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ()))
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        t:defer(function()
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
            local z = B().find(id)
            -- Destination TRIP squares east, else the nearest shorter trip (down to TRIP_MIN) or a lateral offset:
            -- campaign MP 2026-10-15, nothing free around 10688,10136 (Bodies.findFreeSquare: loaded, walkable,
            -- nobody standing). The reason of the last refusal is kept for the message.
            local sq, refusal, trip = nil, nil, nil
            for d = TRIP, TRIP_MIN, -2 do
                for _, dy in ipairs({ 0, 4, -4, 8, -8 }) do
                    if sq == nil then
                        local q, w = B().findFreeSquare(math.floor(z:getX()) + d, math.floor(z:getY()) + dy,
                            math.floor(z:getZ()))
                        if q ~= nil then sq, trip = q, d else refusal = w end
                    end
                end
            end
            t2:ok(sq ~= nil, "no free square " .. TRIP_MIN .. " to " .. TRIP .. " squares east of the body: "
                .. tostring(refusal))
            if trip ~= TRIP then measure("destination " .. trip .. " squares east (none free at " .. TRIP .. ")") end
            local issued = D().stats.issued
            local v, why = D().moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk")
            t2:ok(v ~= nil, "move refused: " .. tostring(why))
            local _, sus0 = R().rejectedOf(id)
            local m = sampler(t2, id)
            -- The npc is spawned next to the player, often inside the house of the spawn point: it goes out by a
            -- door first (an executor wait, no gesture); the hand-overs are measured once it is outside.
            local outFrom = getTimestampMs()
            t2:waitQuiet(function()
                local q = B().find(id)
                local qs = q and q:getCurrentSquare() or nil
                return getTimestampMs() - outFrom >= 3000
                    and ((qs ~= nil and qs:getBuildingDef() == nil) or getTimestampMs() - outFrom >= OUT_MS)
            end, OUT_MS + 5000, function(t3)
                handTo(t3, id, players, m, function(t4)
                    handTo(t4, id, players, m, function(t5)
                        t5:waitUntil(function()
                            local e = D().get(id)
                            return e ~= nil and e.done
                        end, ARRIVE_MS, function(t6)
                            local e = D().get(id)
                            local _, sus1 = R().rejectedOf(id)
                            local resumes = {}
                            for i, ms in ipairs(m.resumed) do resumes[i] = tostring(ms) end
                            local changes = {}
                            for i, c in ipairs(m.changes) do changes[i] = c.from .. ">" .. c.to end
                            local transfers = 0   -- between the two clients (the server holds a new body first)
                            for _, c in ipairs(m.changes) do
                                if c.from ~= "server" and c.to ~= "server" then transfers = transfers + 1 end
                            end
                            local stops = stopsAround(m)
                            local stopText, maxStop = {}, 0
                            for i = 1, #m.changes do
                                stopText[i] = tostring(stops[i])
                                if stops[i] ~= nil and stops[i] > maxStop then maxStop = stops[i] end
                            end
                            measure(string.format("trip %s #%s (issued +%d): owner changes %d (%s), resumptions %d "
                                .. "(%s ms; server max %s), progress gaps around the changes %s ms (climbs or gestures %d), "
                                .. "suspect refusals %d",
                                tostring(e and e.s),
                                tostring(e and e.v), D().stats.issued - issued, #m.changes, table.concat(changes, " "),
                                #m.resumed, table.concat(resumes, ", "), tostring(D().stats.resumeMax),
                                table.concat(stopText, ", "), #m.climbs, sus1 - sus0))
                            t6:eq("arrived", e and e.s, "directive state at the end of the trip")
                            t6:eq(v, e and e.v, "directive number")
                            for _, ms in ipairs(m.resumed) do
                                t6:ok(ms <= RESUME_MS, "resumed " .. tostring(ms) .. " ms after the owner change")
                            end
                            t6:ok(transfers >= 2, "fewer than two owner changes between the clients during the trip")
                            t6:ok(#m.resumed >= 2, "fewer than two resumptions by a new executor")
                            t6:ok(maxStop <= REPORT_MS + STALL_MS, "no progress for " .. maxStop
                                .. " ms around an owner change (one report per " .. REPORT_MS .. " ms)")
                            t6:eq(0, sus1 - sus0, "suspect state reports refused during the trip")
                        end, "trip not finished")
                    end)
                end)
            end)
        end, "npc still on the floor")
    end)
end)
