--[[
lk.fortify_offscreen - offscreen catch-up of the home fortification (LK14-T05, server/LivingKnox/LK_Fortify.lua:
Fortify.snapshot / offscreenHour / applyPending, called by LK_Simulation.advance and by the LoadChunk and
EveryOneMinute scan; materials taken from the stock reference through its pending changes, LK_Stock.offscreenTake).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player and one outer window, empty door frame or closed single
door other than the entrance (the test group gets its home on the player's square, no furnishing:
LivingKnox.Homes.skip). Solo: RST.run({ suite = "lk.fortify_offscreen", tags = "world" }). Dedicated server:
RST.server({ suite = "lk.fortify_offscreen", tags = "world" }) from an admin client standing in such a house.
The offscreen hour is not waited for: the offscreen rule is called directly on the registry (as the simulation step
does, members never materialized: the test runs within one call), the home staying loaded around the player; the
application that follows plays the arrival of a player.

What is checked (nominal path):
    - fixture: one hammer, NEED planks and NEED loose nails (NEED = planks the first barricade site still needs) in
      the first container of the home (sorted key); member m-2 of a "settlers" group is a builder in the registry;
    - the survey kept in the registry (Fortify.feasible) holds the site;
    - one offscreen hour by day: NEED planks planned on the site, the stock reference has NEED planks and NEED nails
      less (pending changes), the opening and the container untouched;
    - the application (Fortify.applyPending): planks on the opening = planks before + NEED (state placed = state
      simulated), exactly NEED planks and NEED nails gone from the container, the hammer kept, nothing pending, no
      application mark left, a stock check with nothing missing, lost or stolen;
    - no duplicate: a second application and one after LivingKnox.Fortify.reset() (memory lost) place nothing.
Every phase prints "[LKF] measure ..." lines. Cleanup (t:defer): planks added by the test removed from the barricade
(removePlank, sent to the clients), hammer removed, planks and nails removed down to their counts before the
test (the stock may use the house ones first), stock reference erased, test group removed.
Outside the game: tests/test_lk_fortify_offscreen.py (doubles).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local measure = K.measurer("[LKF]")

local DAY_HOUR = 4   -- simulated hour whose start is 10:00 ((4 + 6) % 24)

local function LK() return LivingKnox end
local function S() return LivingKnox.Stock end
local function F() return LivingKnox.Fortify end

local function homeContainers(gid, home)
    local style, def = LK().Homes.ready(home)
    if style == nil then return nil end
    return S().containers(gid, home, style, def ~= nil and def:getIDString() or nil)
end

local function countType(box, ft)
    local n = 0
    local items = box:getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == ft then n = n + 1 end
    end
    return n
end

local function marked(box)
    local n = 0
    local items = box:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:hasModData() and it:getModData()[F().OP_TAG] ~= nil then n = n + 1 end
    end
    return n
end

-- Planks on both sides of the opening of a site: same square, opposite square, opening, application marks (on the
-- opening and its barricades).
local function planksAt(site)
    local o = F().openingOf(site)
    if o == nil then return nil end
    local a, b = o:getBarricadeOnSameSquare(), o:getBarricadeOnOppositeSquare()
    local marks = 0
    for _, bar in ipairs({ o, a, b }) do
        if bar ~= nil and bar:hasModData() and bar:getModData()[F().OP_TAG] ~= nil then marks = marks + 1 end
    end
    return a ~= nil and a:getNumPlanks() or 0, b ~= nil and b:getNumPlanks() or 0, o, marks
end

local function fortOf(gid)
    local g = LK().Groups.get(gid)
    return g ~= nil and LK().Fortify.fortView(g.fort, g.home) or nil   -- working view (compact form, LK13-T07)
end

RST.suite("lk.fortify_offscreen", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("offscreen barricade placed on arrival as simulated", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Fortify ~= nil and E.Fortify.offscreenHour ~= nil and E.Stock ~= nil
            and E.Stock.offscreenTake ~= nil and E.Homes ~= nil, "LivingKnox offscreen fortification is not loaded")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST offscreen fortify", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)   -- no furnishing (LK08-T04) on the test site
        assert(G.addMember(gid, { role = "fighter", profile = "guard", female = false, day = G.today() }))
        assert(G.addMember(gid, { role = "worker", profile = "handyman", female = false, day = G.today() }))
        assert(G.setLeader(gid, "m-1", G.today()))
        t:defer(function()
            S().clear(gid)
            G.remove(gid)
            F().reset()
        end, "remove the stock reference and group " .. gid)
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        local plan = F().plan(gid, { force = true })
        t:ok(plan ~= nil, "no fortification plan for the home")
        local site
        for _, st in ipairs(plan.sites) do
            if site == nil and st.kind == "barricade" and not st.done then
                local o = F().openingOf(st)
                if o ~= nil and not (F().openingKind(o) == "door" and o:IsOpen()) then site = st end
            end
        end
        if site == nil then t:skip("no closed outer opening left to barricade in this house") end
        local need = site.steps - site.have
        local before = { planksAt(site) }

        -- Fixture: hammer, planks and loose nails in the first container of the home.
        local box = cts[1].container
        if not box:isExplored() then box:setExplored(true) end
        local fixture = {}
        local function put(ft)
            local it = instanceItem(ft)
            t:ok(it ~= nil, "item " .. ft .. " not created")
            box:AddItem(it)
            if isServer() then sendAddItemToContainer(box, it) end
            fixture[#fixture + 1] = it
            return it
        end
        local planks0, nails0 = countType(box, "Base.Plank"), countType(box, "Base.Nails")
        local hammer = put("Base.Hammer")
        for _ = 1, need do
            put("Base.Plank")
            put("Base.Nails")
        end
        local added = 0
        local base = { ["Base.Plank"] = planks0, ["Base.Nails"] = nails0 }
        t:defer(function()
            -- The stock may have used the planks and nails of the house instead of the fixture ones: fixture items
            -- are removed only down to the counts found before the test (the hammer always).
            for _, it in ipairs(fixture) do
                local ft = it:getFullType()
                local keep = base[ft] ~= nil and countType(box, ft) <= base[ft]
                if not keep and box:containsID(it:getID()) then
                    box:DoRemoveItem(it)
                    if isServer() then sendRemoveItemFromContainer(box, it) end
                end
            end
            local a, _, o = planksAt(site)
            if o ~= nil and added > 0 then
                local bar = (a or 0) > (before[1] or 0) and o:getBarricadeOnSameSquare() or o:getBarricadeOnOppositeSquare()
                for _ = 1, added do
                    if bar ~= nil and bar:getNumPlanks() > 0 then
                        bar:removePlank(nil)
                        if bar:getNumPlanks() > 0 and isServer() then bar:sendObjectChange(IsoObjectChange.STATE) end
                    end
                end
                measure("cleanup: " .. added .. " plank(s) removed from " .. site.id)
            end
        end, "fixture items and test planks removed")
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        t:ok(G.update(function(d)
            d.groups[gid].members["m-2"].duty = "builder"
            return true, true
        end), "builder not set")

        -- Survey kept in the registry (home loaded).
        F().invalidate(gid)
        t:ok(F().feasible(gid) ~= nil, "no feasible list")
        local fort = fortOf(gid)
        t:ok(type(fort) == "table", "no offscreen survey in the registry")
        local kept = false
        for _, e in ipairs(fort.sites) do
            if e.id == site.id then kept = true end
        end
        t:ok(kept, "site " .. site.id .. " not in the offscreen survey")
        local nPlanks, nNails = countType(box, "Base.Plank"), countType(box, "Base.Nails")
        measure(string.format("fixture of %s in %s: site %s (%s, %d/%d plank(s), %d needed), planks %d, nails %d, "
            .. "%d site(s) in the survey", gid, cts[1].key, site.id, tostring(site.opening), site.have, site.steps,
            need, nPlanks, nNails, #fort.sites))

        -- One offscreen hour by day (registry only, as the simulation step does), with just the work time of the
        -- NEED planks (one builder): other openings of the house stay untouched.
        local workMinutes = F().CFG.OFF_WORK_MINUTES
        F().CFG.OFF_WORK_MINUTES = need * F().CFG.PLANK_MINUTES
        t:defer(function() F().CFG.OFF_WORK_MINUTES = workMinutes end, "offscreen work time restored")
        local out
        t:ok(G.update(function(d)
            out = F().offscreenHour(d.groups[gid], gid, DAY_HOUR)
            return true, true
        end), "registry not written")
        t:ok(out ~= nil, "offscreen hour did nothing")
        t:eq(need, out.steps, "offscreen steps")
        fort = fortOf(gid)
        local planned = 0
        for _, op in ipairs(fort.pend.ops) do
            if op.id == site.id then planned = planned + op.b - op.a end
        end
        t:eq(need, planned, "planks planned on the site")
        local a0, b0 = planksAt(site)
        t:eq((before[1] or 0) + (before[2] or 0), (a0 or 0) + (b0 or 0), "planks on the opening before the arrival")
        t:eq(nPlanks, countType(box, "Base.Plank"), "planks in the container before the arrival")
        measure(string.format("offscreen hour: %d builder(s), %d step(s) on %d site(s), %d change(s) to place, %d stock "
            .. "change(s) pending", out.builders, out.steps, out.sites, #fort.pend.ops, S().reference(gid).pending))

        -- Arrival: the work is placed.
        local rep
        rep, why = F().applyPending(gid)
        t:ok(type(rep) == "table", "offscreen work not placed: " .. tostring(why))
        local a, b, _, marks = planksAt(site)
        added = (a or 0) + (b or 0) - (before[1] or 0) - (before[2] or 0)
        measure(string.format("placed: %d change(s), %d step(s), %d already, %d dropped; %s planks %d+%d -> %d+%d; "
            .. "planks in the box %d, nails %d", rep.placed, rep.steps, rep.already, rep.dropped, site.id,
            before[1] or 0, before[2] or 0, a or 0, b or 0, countType(box, "Base.Plank"), countType(box, "Base.Nails")))
        t:eq(need, added, "planks placed on the opening (state placed = state simulated)")
        t:eq(site.steps, math.max(a or 0, b or 0), "planks on the opening")
        S().check(gid, { force = true })   -- stock pending changes applied (planks and nails taken)
        t:eq(planks0, countType(box, "Base.Plank"), "planks left in the container (exactly " .. need .. " used)")
        t:eq(nails0, countType(box, "Base.Nails"), "nails left in the container (exactly " .. need .. " used)")
        t:ok(box:containsID(hammer:getID()), "hammer taken from the container")
        t:eq(0, marks + marked(box), "application marks left")
        fort = fortOf(gid)
        t:eq(0, #fort.pend.ops + #fort.boxes, "offscreen changes still pending")
        t:eq(0, S().reference(gid).pending, "stock changes still pending")
        local c = S().check(gid, { force = true })
        t:ok(type(c) == "table", "stock not checked after the arrival")
        t:eq(0, c.missing, "missing items at the check after the arrival")
        t:eq(0, c.lost, "items counted as lost")
        t:eq(0, #c.thefts, "thefts counted")

        -- No duplicate.
        t:eq(nil, (F().applyPending(gid)), "second application")
        F().reset()
        t:eq(nil, (F().applyPending(gid)), "application after a memory reset")
        local a2, b2 = planksAt(site)
        t:eq((a or 0) + (b or 0), (a2 or 0) + (b2 or 0), "planks on the opening after the second application")
    end)
end)
