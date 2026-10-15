--[[
lk.force - blocked way of a Living Knox npc (LK04-T04, server/LivingKnox/LK_Obstacles.lua, section "passage
bloque"): at a refused door with no way around, a settler is refused at once, a neutral waits then is refused, a
raider forces the obstacle (strike gesture, vanilla weapon hits applied by the authority: barricade planks broken, then
a locked door broken), never the home of a group friendly to the players without an explicit order
(LivingKnox.Obstacles.orderForce). Tags "world" and "server": the authority only, on a save named rstest*, with a
target player (t.ctx.player) standing near a house with a single exterior door with a free lane through it (the same
site as the key tests of lk.traversal: RST.LKTraversal.pickHomeDoor, within 25 squares; else looked for at the
places of RST.Places.ensure through RST.LKTraversal.atSite), the Living Knox option
Enabled on. Solo: RST.run({ suite = "lk.force", tags = "world" }); dedicated server: RST.server({ suite = "lk.force",
tags = "world" }) from an admin client standing still. Asynchronous run only (about 3 minutes; do not pause the game).

Every test spawns a fresh npc on the start square of the lane (outside or inside, two squares before the door), makes
it the member of a group of the tested type (no home; left out of the decisions of its group), closes the door and
sends the npc two squares past it. The door-first rule and the detour around refused doors are switched off during the
test (LivingKnox.Obstacles.DOORS_FIRST, AVOID_REFUSED, restored by t:defer): the npc has no way around and meets the
door, which is what is checked here. Barricade: one plank nailed on the side of the npc
(IsoBarricade.AddBarricadeToObject, addPlank), removed afterwards if still there.
    - barricaded door, raider with a sledgehammer: the plank is broken (LivingKnox.Obstacles.stats.planksBroken + 1,
      barricade gone), the door opened by the authority, the npc arrives; "force" act shown while striking;
    - locked door, raider with a sledgehammer, no key: the door is broken (removed from its square, planks, knob and
      hinges on the floor) and the npc arrives. THE DOOR STAYS BROKEN (test save only);
    - barricaded door, settler: the move is refused at once (reason "barricaded door"), the plank is intact;
    - barricaded door, neutral: the npc waits (act "wait") at least WAIT_MS, then the move is refused with
      "(waited ... ms)", the plank is intact;
    - barricaded home door of a settlers group (the building of the door becomes its home), raider: not forced
      (stats.forceRefused + 1), refused at once, the plank intact;
    - same, with the explicit order (orderForce right after the move): forced, plank broken, the npc arrives.
Figures are printed as "[LKT] measure ..." lines (trip time, hits, planks). Every test removes its npc, its group and
the barricade, and restores the door state (but a broken door stays broken).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/suites/RST_LKTraversal"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local TRIP_MS = 90000
local measure = K.measurer("[LKT]")
local B, D = K.B, K.D

local function O() return LivingKnox and LivingKnox.Obstacles end
local function GR() return LivingKnox and LivingKnox.Groups end
local function TR() return RST.LKTraversal end

local function count(name)
    return O().stats[name] or 0
end

-- Rule switches set for the test, restored by t:defer.
local function rules(t, doorsFirst, avoid)
    local o = O()
    local was = { o.DOORS_FIRST, o.AVOID_REFUSED }
    o.DOORS_FIRST, o.AVOID_REFUSED = doorsFirst, avoid
    t:defer(function() o.DOORS_FIRST, o.AVOID_REFUSED = was[1], was[2] end, "restore the obstacle rules")
end

-- The npc left out of the decisions of its group (same as lk.traversal: a move closed by the test must not be
-- replaced by a duty of the group before it is read).
local function isolate(t, id)
    local Dec = LivingKnox and LivingKnox.Decisions
    if Dec == nil or type(Dec.evaluate) ~= "function" then return end
    local base = Dec.evaluate
    Dec.evaluate = function(gid, g, mid, m, ...)
        if m ~= nil and m.npc == id then return nil end
        return base(gid, g, mid, m, ...)
    end
    t:defer(function() Dec.evaluate = base end, "decisions of the group back for " .. id)
end

local function spawnAt(t, sq)
    local id, body = B().spawn({}, sq:getX(), sq:getY(), sq:getZ())
    if id then
        t:defer(function()
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id
end

-- Group of type gtype with the npc id as member (no home), removed afterwards.
local function groupOf(t, id, gtype)
    isolate(t, id)
    local g = GR().create({ type = gtype, name = "Force" })
    t:ok(g ~= nil, "group not created")
    t:defer(function() GR().remove(g.id) end, "remove the group " .. tostring(g and g.id))
    t:ok(GR().addMember(g.id, { role = "fighter", npc = id }) ~= nil, "member not added")
    O().refreshHomes(true)
    return g.id
end

-- One plank nailed on the side of the start square (addOpposite: the start is west / north of the door square),
-- removed afterwards if still there (vanilla removePlank: transmitRemoveItemFromSquare on a server).
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

-- Site of the key tests of lk.traversal (single exterior door, free lane), the door state kept, or SKIP. fromOutside:
-- lane starting outside the building, whichever side of the edge that is (RST.LKTraversal.findSiteFrom): a locked
-- exterior door opens from inside without a key (LivingKnox.Obstacles.opensFromInside), so a raider starting inside
-- never forces it (campaign MP 2026-10-15: "opened and unlocked from inside", doors broken 0).
-- Solo campaign of 2026-10-15 (SKIP "no free single exterior door ... from outside, within 25 squares"): the site is
-- looked for around the player, then at the places of RST.Places.ensure (RST.LKTraversal.atSite: nearest buildings of
-- the metagrid, players moved there and back), as the lk.traversal sites; then run(t, s).
local function site(t, fromOutside, run)
    local tr = TR()
    t:ok(tr ~= nil and tr.findSite ~= nil and tr.findSiteFrom ~= nil and tr.atSite ~= nil,
        "RST.LKTraversal not loaded")
    O().refreshHomes(true)   -- home group of the previous test removed less than HOMES_MS ago
    tr.atSite(t, "free single exterior door of a building without a home, with a free lane"
        .. (fromOutside and " from outside" or ""), function(p)
        -- Single door only (solo campaign of 2026-10-15: garage door 11307,6915 W taken, "garage door not forced").
        local function pick(e)
            local d = tr.pickHomeDoor(e)
            if d ~= nil and O().kindOf(d) == "single" then return d end
            return nil
        end
        if fromOutside then return tr.findSiteFrom(p, pick, false) end
        return tr.findSite(p, pick)
    end, function(t2, s)
        return run(t2, s)
    end)
end

-- Door state of site s kept (restored by t:defer).
local function keepSiteDoor(t, s)
    local door = s.obj
    local was = { open = O().isOpen(door), locked = door:isLocked() or door:isLockedByKey() }
    t:defer(function()
        if door:getSquare() == nil or door:getObjectIndex() == -1 then return end   -- broken: stays broken
        if not was.locked and (door:isLocked() or door:isLockedByKey()) then
            door:setLockedByKey(false, false)
            door:setIsLocked(false)
            if isServer() then door:sync() end
        end
        O().setDoor(door, was.open, was.locked)
    end, "restore the door " .. s.e.key)
    print("[LKT] force test: door " .. s.e.key .. ", start " .. s.start:getX() .. "," .. s.start:getY()
        .. ", target " .. s.target:getX() .. "," .. s.target:getY())
end

-- Trip to the target of site s: move issued, then issued(v) (facultative), then then(t, info) once the move is
-- closed (info.state, info.why, info.ms, info.acts : acts seen while waiting).
local function trip(t, id, s, what, issued, after)
    local v, why = D().moveTo(id, s.target:getX(), s.target:getY(), s.target:getZ(), "walk")
    t:ok(v ~= nil, what .. ": move refused: " .. tostring(why))
    if issued then issued(v) end
    local info = { start = getTimestampMs(), acts = {} }
    t:waitUntil(function()
        local act = LivingKnox.Anim.actOf(id)
        if act ~= nil then info.acts[act] = true end
        local e = D().get(id)
        if e ~= nil and e.v ~= v then
            info.replaced = tostring(e.op) .. " #" .. tostring(e.v)
            return true
        end
        return e ~= nil and e.done == true
    end, TRIP_MS, function(t2)
        local e = D().get(id)
        info.state, info.ms = e and e.s, getTimestampMs() - info.start
        local r = O().lastRefused
        info.why = r ~= nil and r.id == id and r.why or nil
        local acts = {}
        for k in pairs(info.acts) do acts[#acts + 1] = k end
        table.sort(acts)
        measure(string.format("%s: %s in %d ms, acts [%s], refusal %s, hits %d, planks broken %d, doors broken %d",
            what, tostring(info.state), info.ms, table.concat(acts, " "), tostring(info.why), count("forceHits"),
            count("planksBroken"), count("doorsBroken")))
        t2:ok(info.replaced == nil, what .. ": move #" .. tostring(v) .. " replaced by " .. tostring(info.replaced))
        after(t2, info)
    end, what .. ": move not finished")
end

-- Common frame: site, npc of type gtype standing on the start side, door prepared by prepare(door, s, id), then trip.
local function blockedTest(gtype, weapon, prepare, what, issued, after, fromOutside)
    return function(t)
        local o = O()
        t:ok(o ~= nil and o.onBlocked ~= nil and GR() ~= nil and GR().isReady(),
            "LivingKnox.Obstacles (LK04-T04) or LivingKnox.Groups is not ready here")
        rules(t, false, false)
        site(t, fromOutside, function(t1, s)
        keepSiteDoor(t1, s)
        local id = spawnAt(t1, s.start)
        local door = s.obj
        t1:waitUntil(K.standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local ok, why = TR().onLane(s, z:getX(), z:getY(), z:getZ())
            if not ok then t2:skip(why) end
            groupOf(t2, id, gtype)
            if weapon ~= nil then
                t2:ok(LivingKnox.Equipment.setWeapon(id, weapon), "weapon " .. weapon .. " not given")
            end
            o.setDoor(door, false, false)
            local ctx = prepare(t2, door, s, id) or {}
            ctx.door, ctx.site = door, s
            trip(t2, id, s, what, issued and function(v) issued(t2, id, v, ctx) end or nil,
                function(t3, info) after(t3, info, ctx) end)
        end, "npc still on the floor")
        end)
    end
end

local function barricaded(t, door, s)
    return { bar = barricade(t, door, s), planks0 = count("planksBroken"), refused0 = count("refused") }
end

local function plankIntact(t, ctx)
    t:eq(1, ctx.bar:getNumPlanks(), "planks of the barricade")
    t:eq(ctx.planks0, count("planksBroken"), "planks broken")
end

RST.suite("lk.force", { tags = { "world", "server" }, testTimeoutMs = 150000, timeoutMs = 600000 }, function(suite)
    suite.test("barricaded door: forced by a raider, plank broken, then opened", blockedTest("raiders",
        "Base.Sledgehammer", barricaded, "barricaded door, raider", nil, function(t, info, ctx)
            t:eq("arrived", info.state, "directive state")
            t:ok(info.acts.force == true, "no force act seen")
            t:eq(ctx.planks0 + 1, count("planksBroken"), "planks broken")
            t:ok(ctx.bar:getObjectIndex() == -1 or ctx.bar:isDestroyed(), "barricade still there")
            t:ok(not ctx.door:isBarricaded(), "door still barricaded")
        end))

    suite.test("locked door: broken by a raider without the key", blockedTest("raiders", "Base.Sledgehammer",
        function(t, door)
            O().setDoor(door, false, true)
            t:ok(O().isLocked(door), "door not locked")
            return { broken0 = count("doorsBroken") }
        end, "locked door, raider", nil, function(t, info, ctx)
            t:eq("arrived", info.state, "directive state")
            t:eq(ctx.broken0 + 1, count("doorsBroken"), "doors broken")
            t:ok(ctx.door:getSquare() == nil or ctx.door:getObjectIndex() == -1, "door still on its square")
        end, true))

    suite.test("barricaded door: a settler is refused at once, nothing broken", blockedTest("settlers", nil, barricaded,
        "barricaded door, settler", nil, function(t, info, ctx)
            t:eq("failed", info.state, "directive state")
            t:eq("barricaded door", info.why, "reason of the refusal")
            t:ok(info.acts.wait == nil and info.acts.force == nil, "settler waited or forced")
            plankIntact(t, ctx)
        end))

    suite.test("barricaded door: a neutral waits, then is refused", blockedTest("neutrals", nil, barricaded,
        "barricaded door, neutral", nil, function(t, info, ctx)
            t:eq("failed", info.state, "directive state")
            t:ok(info.acts.wait == true, "no wait act seen")
            t:ok(info.ms >= O().WAIT_MS, "refused after " .. info.ms .. " ms, before the end of the wait")
            t:ok(string.find(tostring(info.why), "waited", 1, true) ~= nil, "reason: " .. tostring(info.why))
            plankIntact(t, ctx)
        end))

    -- The building of the door becomes the home of a settlers group (friendly to the players), without member.
    local function friendlyHome(t, door, s)
        local ctx = barricaded(t, door, s)
        local inside = s.e.a:getBuildingDef() ~= nil and s.e.a or s.e.b
        local g = GR().create({ type = "settlers", name = "Force home",
            home = { x = inside:getX(), y = inside:getY(), z = inside:getZ() } })
        t:ok(g ~= nil, "home group not created")
        t:defer(function() GR().remove(g.id) end, "remove the home group")
        local H = LivingKnox.Homes
        if g ~= nil and H and H.skip then H.skip(g.id) end   -- no furnishing (LK08-T04) on the test site
        O().refreshHomes(true)
        ctx.forceRefused0 = count("forceRefused")
        return ctx
    end

    suite.test("barricaded home door of settlers: not forced by a raider without an order", blockedTest("raiders",
        "Base.Sledgehammer", friendlyHome, "friendly home, raider, no order", nil, function(t, info, ctx)
            t:eq("failed", info.state, "directive state")
            t:eq(ctx.forceRefused0 + 1, count("forceRefused"), "forcings refused")
            t:ok(info.acts.force == nil, "force act seen")
            plankIntact(t, ctx)
        end))

    suite.test("barricaded home door of settlers: forced by a raider with an explicit order", blockedTest("raiders",
        "Base.Sledgehammer", friendlyHome, "friendly home, raider, order", function(t, id, v)
            t:ok(O().orderForce(id, v), "order refused")
        end, function(t, info, ctx)
            t:eq("arrived", info.state, "directive state")
            t:eq(ctx.planks0 + 1, count("planksBroken"), "planks broken")
            t:eq(ctx.forceRefused0, count("forceRefused"), "forcings refused")
        end))
end)
