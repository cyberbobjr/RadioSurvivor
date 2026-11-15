--[[
lk.passage - Living Knox npcs give way to each other (LK18-T02, ADR adr-ceder-le-passage.md D01, D03, D06):
client/LivingKnox/LK_PassageSignal.lua (the blocked executor signals the npc in front of it), server/LivingKnox/
LK_PassageAuthority.lua (the authority checks, arbitrates and orders), server/LivingKnox/Decisions/
LK_Decide_StepAside.lua (the blocker steps aside, waits for the other npc or a bounded time, then resumes).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) near a
house with a single exterior door and a free lane through it (the site of the key tests of lk.traversal:
RST.LKTraversal.pickHomeDoor, looked for around the player, then at the places of RST.Places.ensure), the Living Knox
option Enabled on. Solo: RST.run({ suite = "lk.passage", tags = "world" }); dedicated server:
RST.server({ suite = "lk.passage", tags = "world" }) from an admin client standing still (the bodies are then
simulated, and the blocked npc signalled, by a client). Asynchronous run only (about 2 minutes; do not pause the game).

The door of the site is opened for the test (state restored afterwards). The target player is untouchable (god mode)
and vanilla zombies are removed around the site at every poll. Both npcs have no group (same passage priority).
Placement by the test, outside the stop-place rule (LK_StopPlace): the npcs are spawned right next to the door.
    - face to face in the doorway (a 1-wide passage): npc 1 on the second square before the door edge, npc 2 on the
      second square past it (the spawn keeps one free square around a body), both sent through the door at the same
      time, each to the start square of the other (two moving npcs: the priority, then the smaller id, decides, ADR
      D02). Both arrive within TRIP_MS (the npc that steps aside gets its own move back afterwards); at least one
      passage is granted and one npc stepped aside;
    - npc standing guard on the passage: npc 2 stands still ON the door square (facing through the door), npc 1 is
      sent through the door. A still npc always yields (ADR update of 2026-11-15 evening, D07): npc 2 is ordered aside,
      npc 1 arrives, then npc 2 comes back within Directives.ARRIVE squares of the door square.
Figures are printed as "[LKPG] measure ..." lines (time, passages granted, step-asides). Every test removes its npcs.
]]

require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_Places"
require "RST/RST_LKHelpers"
require "RST/suites/RST_LKTraversal"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local TRIP_MS = 60000       -- both npcs through the door (two blockings, a wait and a step aside at most)
local BACK_MS = 30000       -- the npc that stepped aside back on its square
local CLEAR_RADIUS = 20     -- squares around the site cleared of vanilla zombies at every poll
local measure = K.measurer("[LKPG]")   -- "[LKP]" is taken by lk.provisions
local B, D = K.B, K.D

local function O() return LivingKnox and LivingKnox.Obstacles end
local function PA() return LivingKnox and LivingKnox.PassageAuthority end
local function SA() return LivingKnox and LivingKnox.StepAside end

local function ready(t)
    t:ok(B() ~= nil and D() ~= nil and O() ~= nil, "LivingKnox.Bodies, Directives or Obstacles is not loaded here")
    t:ok(PA() ~= nil and SA() ~= nil, "LivingKnox.PassageAuthority or StepAside (LK18-T02) is not loaded here")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    RST.Places.protect(t, p)
end

-- Door of the site open during the test, its state restored afterwards.
local function openDoor(t, s)
    local door = s.obj
    local wasOpen, wasLocked = O().isOpen(door), door:isLocked() or door:isLockedByKey()
    O().setDoor(door, true, false)
    t:defer(function()
        if door:getSquare() ~= nil and door:getObjectIndex() ~= -1 then O().setDoor(door, wasOpen, wasLocked) end
    end, "restore the door " .. s.e.key)
end

local function spawnOn(t, sq)
    local id, body = B().spawn({}, sq:getX(), sq:getY(), sq:getZ())
    if id then
        t:defer(function()
            local M = LivingKnox.Movement
            if M ~= nil then M.forgetStuck(id) end
            SA().leave(id)   -- order dropped, nothing resumed
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id
end

-- Site of the key tests of lk.traversal (single exterior door, free lane), or SKIP; then run(t, s).
local function site(t, run)
    local tr = RST.LKTraversal
    t:ok(tr ~= nil and tr.findSite ~= nil and tr.atSite ~= nil, "RST.LKTraversal not loaded")
    O().refreshHomes(true)
    tr.atSite(t, "free single exterior door of a building without a home, with a free lane", function(p)
        return tr.findSite(p, function(e)
            local d = tr.pickHomeDoor(e)
            if d ~= nil and O().kindOf(d) == "single" then return d end
            return nil
        end)
    end, function(t2, s)
        openDoor(t2, s)
        print("[LKPG] site: door " .. s.e.key .. ", start " .. s.start:getX() .. "," .. s.start:getY() .. ", target "
            .. s.target:getX() .. "," .. s.target:getY())
        return run(t2, s)
    end)
end

local function near(id, sq)
    local z = B().find(id)
    if z == nil or math.floor(z:getZ()) ~= sq:getZ() then return false end
    local dx, dy = z:getX() - (sq:getX() + 0.5), z:getY() - (sq:getY() + 0.5)
    return math.sqrt(dx * dx + dy * dy) <= D().ARRIVE
end

-- Square of the lane through the door of site s, k squares from the edge: k < 0 on the side of e.a (k = -1: e.a),
-- k > 0 on the side of e.b (k = 1: e.b).
local function laneSquare(s, k)
    local a, b = s.e.a, s.e.b
    local nx, ny = b:getX() - a:getX(), b:getY() - a:getY()
    local base = k < 0 and a or b
    local off = k < 0 and (-k - 1) or (k - 1)
    if k < 0 then nx, ny = -nx, -ny end
    return getCell():getGridSquare(base:getX() + nx * off, base:getY() + ny * off, a:getZ())
end

local function both(id1, id2)
    return function() return K.standing(id1)() and K.standing(id2)() end
end

local function counters()
    return { granted = PA().stats.granted or 0, ordered = SA().stats.ordered or 0 }
end

-- Polls cond() every step with the zombies around the site removed; then(t, ms) once true.
local function waitClear(t, s, cond, ms, after, what)
    local t0 = getTimestampMs()
    t:waitUntil(function()
        K.clearZombiesNear(t, s.e.a:getX(), s.e.a:getY(), s.e.a:getZ(), CLEAR_RADIUS)
        return cond()
    end, ms, function(t2) after(t2, getTimestampMs() - t0) end, what)
end

RST.suite("lk.passage", { tags = { "world", "server" }, testTimeoutMs = 150000, timeoutMs = 360000 }, function(suite)
    suite.test("face to face in a doorway: both npcs get through", function(t)
        ready(t)
        site(t, function(t1, s)
            K.clearZombiesNear(t1, s.e.a:getX(), s.e.a:getY(), s.e.a:getZ(), CLEAR_RADIUS)
            local from1, from2 = laneSquare(s, -2), laneSquare(s, 2)
            t1:ok(from1 ~= nil and from2 ~= nil, "lane squares next to the door not loaded")
            local id1 = spawnOn(t1, from1)
            local id2 = spawnOn(t1, from2)
            t1:waitUntil(both(id1, id2), STAND_MS, function(t2)
                if not near(id1, from1) or not near(id2, from2) then
                    t2:skip("an npc spawned off its square")
                end
                local c0 = counters()
                local v1, w1 = D().moveTo(id1, s.target:getX(), s.target:getY(), s.target:getZ(), "walk")
                local v2, w2 = D().moveTo(id2, s.start:getX(), s.start:getY(), s.start:getZ(), "walk")
                t2:ok(v1 ~= nil and v2 ~= nil, "move refused: " .. tostring(w1) .. " / " .. tostring(w2))
                waitClear(t2, s, function()
                    return near(id1, s.target) and near(id2, s.start) and not SA().active(id1)
                        and not SA().active(id2)
                end, TRIP_MS, function(t3, ms)
                    local c = counters()
                    measure(string.format("face to face: both through in %d ms, passages granted %d, step-asides %d",
                        ms, c.granted - c0.granted, c.ordered - c0.ordered))
                    t3:ok(c.granted > c0.granted, "no passage granted")
                    t3:ok(c.ordered > c0.ordered, "no npc stepped aside")
                end, "both npcs not through the door within " .. TRIP_MS .. " ms")
            end, "npcs still on the floor")
        end)
    end)

    suite.test("npc standing guard on the passage steps aside then comes back", function(t)
        ready(t)
        site(t, function(t1, s)
            K.clearZombiesNear(t1, s.e.a:getX(), s.e.a:getY(), s.e.a:getZ(), CLEAR_RADIUS)
            local post = s.obj:getSquare()        -- the door square itself (never a stop place of the mod)
            local mover = spawnOn(t1, s.start)
            local guard = spawnOn(t1, post)
            t1:waitUntil(both(mover, guard), STAND_MS, function(t2)
                if not near(mover, s.start) or not near(guard, post) then t2:skip("an npc spawned off its square") end
                local a = math.atan2(s.e.b:getY() - s.e.a:getY(), s.e.b:getX() - s.e.a:getX()) * 180 / math.pi
                D().face(guard, a)
                local c0 = counters()
                local ordered = false
                local v, why = D().moveTo(mover, s.target:getX(), s.target:getY(), s.target:getZ(), "walk")
                t2:ok(v ~= nil, "move refused: " .. tostring(why))
                waitClear(t2, s, function()
                    ordered = ordered or SA().active(guard)
                    return near(mover, s.target) and not SA().active(guard)
                end, TRIP_MS, function(t3, ms)
                    local c = counters()
                    measure(string.format("guard on the door square: mover through in %d ms, guard ordered aside %s, "
                        .. "passages granted %d", ms, tostring(ordered), c.granted - c0.granted))
                    t3:ok(ordered, "the guard was never ordered aside")
                    t3:ok(c.granted > c0.granted, "no passage granted")
                    waitClear(t3, s, function() return near(guard, post) end, BACK_MS, function(t4, back)
                        measure(string.format("guard back on its square %d ms after the mover passed", back))
                    end, "the guard did not come back within " .. BACK_MS .. " ms")
                end, "the mover did not get through within " .. TRIP_MS .. " ms")
            end, "npcs still on the floor")
        end)
    end)
end)
