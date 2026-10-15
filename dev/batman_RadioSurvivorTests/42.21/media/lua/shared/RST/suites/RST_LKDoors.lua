--[[
lk.doors - doors on the trip of a Living Knox npc (LK04-T02, server/LivingKnox/LK_Obstacles.lua): opened and closed
behind the npc by the authority only, once; doors of a home locked and opened by its members only; a barricaded door
refused and left as it is; every client sees the same door state (no double toggle). Tags "world" and "server": the
authority only, on a save named rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.doors", tags = "world" }); dedicated server: RST.server({ suite = "lk.doors",
tags = "world" }) from an admin client (MP campaign with two clients: the second client watches the doors too).
Asynchronous run only (about 4 minutes).

Sites (helpers of lk.traversal, RST_LKTraversal.lua): the nearest single exterior door of a building that is no group's
home, with a free lane of six squares through it (findSite + pickHomeDoor; from outside: findSiteFrom). When none is
near the player, the players are moved to the nearest buildings of the metagrid (RST.LKTraversal.atSite, RST.Places:
solo and dedicated server, same places in the same order at each run) and the players go back afterwards.

    - closed door on the trip: the door is closed and unlocked; a npc without group walks through it: the authority
      opens it once (Obstacles.stats.opened + 1), the body goes through the door edge and arrives, the door is closed
      behind it within CLOSE_MS (stats.closed + 1), and SETTLE_MS later still exactly one opening and one closing by
      the authority, the door closed and unlocked. Every client (solo: the local player) watched the door from before
      the trip (RST.Steps "lk.door.watch" / "lk.door.seen", RST_PeerChecksDoors.lua): exactly one opening and one
      closing seen there, and the same final state ("lk.door.state").
    - home door, member: a settlers group gets its home in the building of the door and the npc as member (key of the
      building on the body); the door is closed and locked; the member walks in from outside: opened with the key, the
      body arrives, the door is closed and locked again behind it; every client sees it closed and locked.
    - home door, non-member: same home (a group of the test), the npc of no group walks in from outside: the move is
      refused at the door (directive failed, reason "door of the home of <group> (not a member)"), the door stays
      closed and locked, no opening by the authority; every client sees it closed and locked. The detour around
      refused doors is off for this test (LivingKnox.Obstacles.AVOID_REFUSED), otherwise the npc would look for
      another way in.
    - barricaded door: one plank nailed on the start side of the closed door (IsoBarricade.AddBarricadeToObject), a
      npc of no group: the move is refused (reason "barricaded door", detour off), the door and the plank stay as they
      were, no opening; every client sees the door closed.
Every test removes its npc, its group, the barricade and restores the door with t:defer. Figures: "[LKDR] measure".
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksDoors"
require "RST/suites/RST_LKTraversal"

local K = RST.LKHelpers
local measure = K.measurer("[LKDR]")
local CLOSE_MS = 15000       -- door closed behind the body within this time after its arrival
local SETTLE_MS = 3000       -- no second toggle during this time
local STEP_MS = 15000        -- client deadline of the door steps

local function O() return LivingKnox and LivingKnox.Obstacles end
local function GR() return LivingKnox and LivingKnox.Groups end
local function TR() return RST.LKTraversal end

local function ready(t)
    local o, tr = O(), TR()
    t:ok(o ~= nil and o.setDoor ~= nil and o.decide ~= nil, "LivingKnox.Obstacles (LK04-T02) is not loaded here")
    t:ok(tr ~= nil and tr.atSite ~= nil and tr.trip ~= nil, "RST.LKTraversal helpers are not loaded")
    return o, tr
end

-- Door closed (and locked when lock), its lock taken off first when it must stay unlocked.
local function setClosed(o, door, lock)
    if not lock and o.isLocked(door) then
        door:setLockedByKey(false, false)
        door:setIsLocked(false)
        if isServer() then door:sync() end
    end
    o.setDoor(door, false, lock)
end

-- Every client (solo: the local player) has the door in the state open / locked.
local function clientsSee(t, key, open, locked, after)
    RST.Steps.ask(t, "lk.door.state", { key = key, open = open, locked = locked }, { target = "all",
        timeoutMs = STEP_MS }, after)
end

-- Detour around refused doors off for the test (the refusal itself is checked).
local function noDetour(t, o)
    if o.AVOID_REFUSED == nil then return end
    local was = o.AVOID_REFUSED
    o.AVOID_REFUSED = false
    t:defer(function() o.AVOID_REFUSED = was end, "restore the detour around refused doors")
end

-- Settlers group of the test with its home in the building of the square inside; member (npc id) or none.
local function homeGroup(t, inside, member)
    local g = GR().create({ type = "settlers", name = "Doors",
        home = { x = inside:getX(), y = inside:getY(), z = inside:getZ() } })
    t:ok(g ~= nil, "group not created")
    t:defer(function() GR().remove(g.id) end, "remove the group " .. tostring(g and g.id))
    local H = LivingKnox.Homes
    if g ~= nil and H and H.skip then H.skip(g.id) end   -- no furnishing (LK08-T04) on the test site
    if member ~= nil then
        t:ok(GR().addMember(g.id, { role = "worker", npc = member }) ~= nil, "member not added")
    end
    O().refreshHomes(true)
    return g
end

-- One plank on the start side of the door (as RST_LKForce.lua), removed afterwards if still there.
local function barricade(t, door, site)
    local opposite = door:getSquare() ~= site.e.a
    local b = IsoBarricade.AddBarricadeToObject(door, opposite)
    t:ok(b ~= nil, "barricade not added")
    b:addPlank(nil, nil)
    if isServer() then b:transmitCompleteItemToClients() end
    t:defer(function()
        local sq = b:getSquare()
        if sq ~= nil and b:getObjectIndex() ~= -1 then
            if isServer() then sq:transmitRemoveItemFromSquare(b) else sq:RemoveTileObject(b) end
        end
    end, "remove the barricade")
    return b
end

-- Exterior door of a building without a home, lane from outside (fromOutside) or from either side.
local function findDoor(fromOutside)
    return function(p)
        local tr = TR()
        if fromOutside then return tr.findSiteFrom(p, tr.pickHomeDoor, false) end
        return tr.findSite(p, tr.pickHomeDoor)
    end
end

local SITE = "free single exterior door of a building without a home, with a free lane"

-- ---------------------------------------------------------------- closed door on the trip

local function plainRun(t, site)
    local o, tr = O(), TR()
    local door, e = site.obj, site.e
    print("[LKDR] closed door " .. e.key .. ", start " .. site.start:getX() .. "," .. site.start:getY() .. ", target "
        .. site.target:getX() .. "," .. site.target:getY())
    local id = tr.spawnAt(t, site.start)
    tr.keepDoors(t, { { door = door, key = e.key } })
    tr.isolate(t, id)
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        tr.onStartSide(t2, id, site)
        setClosed(o, door, false)
        t2:ok(not o.isOpen(door) and not o.isLocked(door), "door not closed and unlocked")
        RST.Steps.ask(t2, "lk.door.watch", { key = e.key }, { target = "all", timeoutMs = STEP_MS }, function(t3)
            local opened0, closed0 = o.stats.opened or 0, o.stats.closed or 0
            tr.trip(t3, id, site.target, "closed door", false, function(t4)
                t4:eq(opened0 + 1, o.stats.opened or 0, "doors opened by the authority")
                t4:waitUntil(function() return not o.isOpen(door) end, CLOSE_MS, function(t5)
                    t5:sleep(SETTLE_MS, function(t6)
                        measure(string.format("closed door %s: opened %d, closed %d by the authority, now %s", e.key,
                            (o.stats.opened or 0) - opened0, (o.stats.closed or 0) - closed0,
                            RST.PeerChecksDoors.stateText(door)))
                        t6:eq(opened0 + 1, o.stats.opened or 0, "doors opened by the authority (no second toggle)")
                        t6:eq(closed0 + 1, o.stats.closed or 0, "doors closed behind the body by the authority")
                        t6:ok(not o.isOpen(door) and not o.isLocked(door), "door not closed and unlocked at the end")
                        RST.Steps.ask(t6, "lk.door.seen", { key = e.key, opens = 1, closes = 1, settleMs = 1500 },
                            { target = "all", timeoutMs = STEP_MS }, function(t7)
                                clientsSee(t7, e.key, false, false)
                            end)
                    end)
                end, "door not closed behind the body")
            end, e)
        end)
    end, "npc still on the floor")
end

-- ---------------------------------------------------------------- home door

local function homeRun(member)
    return function(t, site)
        local o, tr = O(), TR()
        local door, e = site.obj, site.e
        local inside = e.a:getBuildingDef() ~= nil and e.a or e.b
        print("[LKDR] home door " .. e.key .. " (" .. (member and "member" or "non-member") .. "), start "
            .. site.start:getX() .. "," .. site.start:getY() .. ", target " .. site.target:getX() .. ","
            .. site.target:getY())
        if not member then noDetour(t, o) end
        local id = tr.spawnAt(t, site.start)
        tr.keepDoors(t, { { door = door, key = e.key } })
        tr.keepDoors(t, tr.exteriorDoors(inside:getBuildingDef(), inside:getZ(), door))   -- the arrival may close them
        tr.isolate(t, id)
        local g = homeGroup(t, inside, member and id or nil)
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
            tr.onStartSide(t2, id, site)
            local z = LivingKnox.Bodies.find(id)
            if member then o.giveKey(id, z) end
            setClosed(o, door, true)
            t2:ok(not o.isOpen(door) and o.isLocked(door), "door not closed and locked")
            if member then
                t2:ok(o.hasKey(z, o.doorKeyId(door)), "the member has no key of the door")
            else
                t2:eq(nil, o.groupOf(id), "group of the non-member")
            end
            local opened0, refused0 = o.stats.opened or 0, o.stats.refused or 0
            tr.trip(t2, id, site.target, member and "home door, member" or "home door, non-member", not member,
                function(t3)
                    if member then
                        t3:eq(opened0 + 1, o.stats.opened or 0, "doors opened by the authority")
                        t3:waitUntil(function() return not o.isOpen(door) end, CLOSE_MS, function(t4)
                            t4:ok(o.isLocked(door), "home door closed behind the member but not locked")
                            clientsSee(t4, e.key, false, true)
                        end, "home door not closed behind the member")
                    else
                        local r = o.lastRefused
                        measure("home door, non-member: refusal " .. tostring(r and r.why) .. " on "
                            .. tostring(r and r.key))
                        t3:eq(opened0, o.stats.opened or 0, "doors opened by the authority")
                        t3:eq(refused0 + 1, o.stats.refused or 0, "refusals by the authority")
                        t3:eq(e.key, r and r.key, "edge of the refusal")
                        t3:eq("door of the home of " .. g.id .. " (not a member)", r and r.why, "reason of the refusal")
                        t3:ok(not o.isOpen(door) and o.isLocked(door), "home door changed by a non-member")
                        clientsSee(t3, e.key, false, true)
                    end
                end, e)
        end, "npc still on the floor")
    end
end

-- ---------------------------------------------------------------- barricaded door

local function barricadeRun(t, site)
    local o, tr = O(), TR()
    local door, e = site.obj, site.e
    print("[LKDR] barricaded door " .. e.key .. ", start " .. site.start:getX() .. "," .. site.start:getY())
    noDetour(t, o)
    local id = tr.spawnAt(t, site.start)
    tr.keepDoors(t, { { door = door, key = e.key } })
    tr.isolate(t, id)
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        tr.onStartSide(t2, id, site)
        setClosed(o, door, false)
        local b = barricade(t2, door, site)
        local planks = b:getNumPlanks()
        t2:ok(door:isBarricaded(), "door not barricaded")
        local opened0, refused0 = o.stats.opened or 0, o.stats.refused or 0
        tr.trip(t2, id, site.target, "barricaded door", true, function(t3)
            local r = o.lastRefused
            measure("barricaded door: refusal " .. tostring(r and r.why) .. " on " .. tostring(r and r.key)
                .. ", planks " .. tostring(b:getNumPlanks()))
            t3:eq(opened0, o.stats.opened or 0, "doors opened by the authority")
            t3:eq(refused0 + 1, o.stats.refused or 0, "refusals by the authority")
            t3:eq(e.key, r and r.key, "edge of the refusal")
            t3:eq("barricaded door", r and r.why, "reason of the refusal")
            t3:ok(not o.isOpen(door), "barricaded door opened")
            t3:eq(planks, b:getNumPlanks(), "planks of the barricade")
            clientsSee(t3, e.key, false, nil)
        end, e)
    end, "npc still on the floor")
end

RST.suite("lk.doors", { tags = { "world", "server" }, testTimeoutMs = 300000, timeoutMs = 1500000 }, function(s)
    s.test("closed door on the trip: opened once, closed behind, same state on every client", function(t)
        local _, tr = ready(t)
        tr.atSite(t, SITE, findDoor(false), plainRun)
    end)

    s.test("home door: a member opens it with the key, locked again behind him", function(t)
        local _, tr = ready(t)
        t:ok(GR() ~= nil and GR().isReady(), "LivingKnox.Groups is not ready here")
        tr.atSite(t, SITE .. " from outside", findDoor(true), homeRun(true))
    end)

    s.test("home door: a non-member is refused, the door stays closed and locked", function(t)
        local _, tr = ready(t)
        t:ok(GR() ~= nil and GR().isReady(), "LivingKnox.Groups is not ready here")
        tr.atSite(t, SITE .. " from outside", findDoor(true), homeRun(false))
    end)

    s.test("barricaded door: refused, left closed with its plank", function(t)
        ready(t)
        TR().atSite(t, SITE, findDoor(false), barricadeRun)
    end)
end)
