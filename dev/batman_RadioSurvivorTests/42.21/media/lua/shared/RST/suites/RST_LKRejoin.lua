--[[
lk.rejoin - the executor of a directive disconnects and joins again while the other client stays connected (LK03-T01,
E01-T17: "reconnexion de l'executant sans consigne doublee ni perdue"; server/LivingKnox/LK_Directives.lua: lease,
suspend, transfer, guardHello; client/LivingKnox/LK_Executor.lua). Dedicated server with two clients only:
autoclient.py --mp --clients 2 --phases reconnect2 --server-suite lk.rejoin (or in --server-campaign mp-persist with
reconnect2 among the phases). Solo or a single client: SKIP.
    lk.rejoin.before            (opt-in "manual") the requester (client 1) is moved FAR squares north, beyond the
                                owner candidate range of the engine (48 to 80 squares) but inside the release radius
                                of the bodies (Config.BODIES.RELEASE_RADIUS 120): the npc spawned outdoors near client 2
                                belongs to client 2; it gets a "move" TRIP squares east (walk), and the step ends once
                                client 2 has sent an accepted execution report. State kept in the SERVER Lua
                                (RST.LKRejoin.state: the server keeps running with reconnect2), a sampler records the
                                owner changes and the end of the trip at each server tick.
    (launcher, reconnect2)      client 2 alone quits (disconnection: the body goes to the server, the directive is
                                suspended) and joins again with the same account; client 1 stays connected.
    lk.rejoin.after-reconnect2  client 2 is back (a new IsoPlayer object for its account), the trip ends "arrived"
                                with the SAME directive number (never issued again, never dropped), at least one
                                resumption by an executor after the disconnection, no suspect report refused; 5 s
                                later the directive is still the same and the body still at its target (not walked
                                twice). Then the npc is forgotten and despawned and client 1 goes back to its place.
    SKIP when the trip ended before client 2 left (lengthen TRIP, or an obstacle stopped it) or when the body never
    left client 2.
Tags "world", "server", "manual": authority only, test saves rstest* only, exact names only. Figures: "[LKJ] measure"
lines. Outside the game: tests/test_persist_suites.py (listing).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecksLK"

local K = RST.LKHelpers
local PL = RST.PeerChecksLK
local measure = K.measurer("[LKJ]")

RST.LKRejoin = RST.LKRejoin or {}
local J = RST.LKRejoin
J.TRIP = 55            -- squares east (under the 60-square move limit) (about 0.8 square/s: over a minute, longer
                       -- than the step end + quit)
J.FAR = 100            -- squares north for client 1: beyond the owner candidate range, inside RELEASE_RADIUS 120
J.OWNER_MS = 30000
J.REPORT_MS = 20000
J.MOVE_MS = 60000
J.ARRIVE_MS = 180000
J.STILL_MS = 5000
J.TARGET_EPS = 2.0

local function B() return LivingKnox and LivingKnox.Bodies end
local function D() return LivingKnox and LivingKnox.Directives end
local function R() return LivingKnox and LivingKnox.Reports end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Teleport without the way back of RST.Fixtures.movePlayer (the requester must stay away between the steps).
local function teleport(p, x, y, z)
    sendServerCommand(p, "RST", RST.Fixtures.COMMAND, { x = x, y = y, z = z })
end

local function near(p, x, y)
    return p ~= nil and dist(p:getX(), p:getY(), x, y) < 2
end

local function stopSampler()
    local st = J.state
    if st and st.tick then
        Events.OnTick.Remove(st.tick)
        st.tick = nil
    end
end

-- Forgets the npc of a previous state and removes its sampler (the requester is sent back to its place).
local function clear(sendBack)
    local st = J.state
    if st == nil then return end
    stopSampler()
    if st.id and D() then D().forget(st.id) end
    if st.id and B() then B().despawn(st.id, true) end
    if sendBack and st.requester and st.origin then
        teleport(st.requester, st.origin.x, st.origin.y, st.origin.z)
    end
    J.state = nil
end

-- Sampler of the trip (server OnTick): owner changes and the tick the directive closed.
local function sampler(st)
    st.changes, st.owner, st.doneMs = {}, nil, nil
    st.tick = function()
        local z = B().find(st.id)
        local e = D().get(st.id)
        if e ~= nil and e.done and st.doneMs == nil then st.doneMs = getTimestampMs() end
        if z == nil then return end
        local owner = D().ownerName(z)
        if st.owner ~= nil and owner ~= st.owner then
            st.changes[#st.changes + 1] = { from = st.owner, to = owner, ms = getTimestampMs() }
        end
        st.owner = owner
    end
    Events.OnTick.Add(st.tick)
end

-- Start of the trip outside any building, with an outdoor target TRIP squares east: the step is about the executor
-- rejoining, not about leaving a house (the persistence bases of the same campaign furnish and barricade the house
-- of the players: a body spawned inside got stuck on its windows, run 20261015-043927). Nearest such square within
-- START_RADIUS of the second client (loaded squares only), or nil.
-- The straight way east must be open too: the walls a fortifying group of the same campaign raises OUTER_MARGIN (2)
-- squares around its house stopped the body 3 squares after its start (run 20261015-051633: "stuck: no path"), so
-- no wall, fence or window on the line and no building within CLEAR squares north or south of it.
J.START_RADIUS = 30
J.CLEAR = 4
local function outdoor(sq)
    return sq ~= nil and sq:isOutside() and sq:getBuilding() == nil and sq:isFree(false)
end
local function openLine(cell, x, y, z)
    local prev = nil
    for i = 0, J.TRIP do
        local sq = cell:getGridSquare(x + i, y, z)
        if not outdoor(sq) then return false end
        if prev ~= nil and (prev:isBlockedTo(sq) or prev:isWallTo(sq) or prev:isHoppableTo(sq)) then return false end
        for k = 1, J.CLEAR do
            local n, so = cell:getGridSquare(x + i, y - k, z), cell:getGridSquare(x + i, y + k, z)
            if (n ~= nil and n:getBuilding() ~= nil) or (so ~= nil and so:getBuilding() ~= nil) then return false end
        end
        prev = sq
    end
    return true
end
function J.outdoorStart(px, py, pz)
    local cell = getCell()
    for r = 2, J.START_RADIUS do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local sq = cell:getGridSquare(px + dx, py + dy, pz)
                    if outdoor(sq) and outdoor(B().findFreeSquare(px + dx + J.TRIP, py + dy, pz))
                        and openLine(cell, px + dx, py + dy, pz) then
                        return px + dx, py + dy
                    end
                end
            end
        end
    end
    return nil
end

local function needTwoClients(t)
    if RST.Steps.isSolo() or PL.peer(t) == nil then
        t:skip("needs a dedicated server with two clients (the executor rejoins while the other stays)")
    end
    t:ok(B() ~= nil and D() ~= nil and R() ~= nil, "LivingKnox.Bodies, Directives or Reports not loaded here")
end

RST.suite("lk.rejoin.before", { tags = { "world", "server", "manual" }, testTimeoutMs = 240000 }, function(s)
    s.test("a trip executed by client 2, client 1 far away", function(t)
        needTwoClients(t)
        clear(true)
        local p = RST.Fixtures.player(t)
        local peerName = PL.peer(t)
        local peer = RST.Steps.playerOf(peerName)
        t:ok(peer ~= nil, "second client " .. tostring(peerName) .. " not online")
        local st = { peer = peerName, peerObj = peer, requester = p,
            origin = { x = p:getX(), y = p:getY(), z = p:getZ() } }
        local px, py, pz = math.floor(peer:getX()), math.floor(peer:getY()), math.floor(peer:getZ())
        local sx, sy = J.outdoorStart(px, py, pz)
        if sx == nil then
            sx, sy = px + 2, py
            t:note("no outdoor start with an outdoor target near " .. peerName .. ": npc spawned next to it")
        end
        local id, body = B().spawn({}, sx, sy, pz)
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        st.id = id
        J.state = st
        local fx, fy = math.floor(st.origin.x) + 0.5, math.floor(st.origin.y) - J.FAR + 0.5
        teleport(p, fx, fy, math.floor(st.origin.z))
        t:waitUntil(function() return near(p, fx, fy) and K.standing(id)() end, J.MOVE_MS, function(t2)
            t2:waitUntil(function()
                local z = B().find(id)
                return z ~= nil and D().ownerName(z) == peerName
            end, J.OWNER_MS, function(t3)
                local z = B().find(id)
                -- The free square found near TRIP squares east may lie a few squares farther than TRIP, and the body
                -- may stand off its spawn square: the move limit (Directives.MAX_TRIP 60) refused 60.5 squares (MP
                -- run 20261015-060712). Shorter offsets are tried until the target is within the limit.
                local sq = nil
                local limit = (D().MAX_TRIP or 60) - 1
                for dx = J.TRIP, J.TRIP - 15, -1 do
                    local c = K.target(z, dx, 0)
                    if c ~= nil and dist(z:getX(), z:getY(), c:getX() + 0.5, c:getY() + 0.5) <= limit then
                        sq = c
                        break
                    end
                end
                t3:ok(sq ~= nil, "no free square near " .. J.TRIP .. " squares east of the body within the move limit")
                st.issued0 = D().stats.issued
                st.resumed0 = D().stats.resumed or 0
                st.suspended0 = D().stats.suspended or 0
                local _, sus0 = R().rejectedOf(id)
                st.sus0 = sus0
                local v, why = D().moveTo(id, sq:getX(), sq:getY(), sq:getZ(), "walk")
                t3:ok(v ~= nil, "move refused: " .. tostring(why))
                st.v = D().get(id).v
                st.target = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
                sampler(st)
                t3:waitUntil(function()
                    local a = D().accepted[id]
                    return a ~= nil and a.by == peerName and a.v == st.v
                end, J.REPORT_MS, function(t4)
                    local e = D().get(id)
                    t4:ok(e ~= nil and not e.done, "trip already over")
                    measure(string.format("npc %s: move #%s to %d,%d by %s; requester %d squares north", id,
                        tostring(st.v), st.target.x, st.target.y, peerName, J.FAR))
                    t4:note("npc " .. id .. " walking, executor " .. peerName)
                end, "no accepted execution report of " .. peerName)
            end, "body not owned by " .. peerName)
        end, "requester not moved away, or npc still on the floor")
    end)
end)

RST.suite("lk.rejoin.after-reconnect2", { tags = { "world", "server", "manual" }, testTimeoutMs = 300000 },
    function(s)
    s.test("the executor rejoined: same directive carried to its end once", function(t)
        needTwoClients(t)
        local st = J.state
        t:ok(st ~= nil and st.id ~= nil and st.v ~= nil, "no state of lk.rejoin.before in this server session "
            .. "(a restart loses it: use the reconnect2 phase)")
        t:defer(function() clear(true) end, "npc " .. st.id .. " forgotten, requester sent back")
        local peer = RST.Steps.playerOf(st.peer)
        t:ok(peer ~= nil, st.peer .. " not online again")
        t:ok(peer ~= st.peerObj, st.peer .. " has the same player object: it did not reconnect")
        t:waitUntil(function()
            local e = D().get(st.id)
            return e ~= nil and e.done
        end, J.ARRIVE_MS, function(t2)
            local e = D().get(st.id)
            local left = nil
            for _, c in ipairs(st.changes) do
                if left == nil and c.from == st.peer then left = c end
            end
            local changes = {}
            for i, c in ipairs(st.changes) do changes[i] = c.from .. ">" .. c.to end
            local _, sus1 = R().rejectedOf(st.id)
            local resumed = (D().stats.resumed or 0) - st.resumed0
            measure(string.format("trip %s #%s (issued +%d): owner changes %s, resumptions %d, suspensions %d, "
                .. "suspect refusals %d", tostring(e.s), tostring(e.v), D().stats.issued - st.issued0,
                table.concat(changes, " "), resumed, (D().stats.suspended or 0) - st.suspended0, sus1 - st.sus0))
            if left == nil then t2:skip("the body never left " .. st.peer .. " (no owner change seen)") end
            if st.doneMs ~= nil and st.doneMs <= left.ms then
                if e.s ~= "arrived" then
                    t2:skip("the trip ended (" .. tostring(e.s) .. ") before " .. st.peer .. " left: obstacle on "
                        .. "the way east of the start")
                end
                t2:skip("the trip ended before " .. st.peer .. " left: lengthen TRIP")
            end
            t2:eq("arrived", e.s, "directive state at the end of the trip")
            t2:eq(st.v, e.v, "directive number (issued again, or another directive)")
            t2:ok(resumed >= 1, "no resumption by an executor after the disconnection")
            t2:eq(0, sus1 - st.sus0, "suspect state reports refused")
            t2:sleep(J.STILL_MS, function(t3)
                local e2 = D().get(st.id)
                local z = B().find(st.id)
                t3:eq(st.v, e2 and e2.v, "directive number after the arrival")
                t3:eq("arrived", e2 and e2.s, "directive state after the arrival")
                t3:ok(z ~= nil and dist(z:getX(), z:getY(), st.target.x + 0.5, st.target.y + 0.5) <= J.TARGET_EPS,
                    "body left its target after the arrival")
                stopSampler()
                local o = st.origin
                teleport(st.requester, o.x, o.y, o.z)
                t3:waitQuiet(function() return near(st.requester, o.x, o.y) end, J.MOVE_MS, nil,
                    "requester not back at its place")
            end)
        end, "trip not finished after the reconnection")
    end)
end)
