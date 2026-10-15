--[[
lk.walls - one segment of the wooden wall around the home raised by a Living Knox builder (LK14-T04,
server/LivingKnox/LK_Fortify.lua: Fortify.run / buildStep / placeStructure, called from LK_Routines.lua for a member
whose duty is "builder" and whose behaviour is "chore"; planks and nails taken through LivingKnox.Stock.takeItem).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player, on clear ground: the ring of walls runs 2 squares
around the building (the test group gets its home on the player's square, no furnishing: LivingKnox.Homes.skip).
Solo: RST.run({ suite = "lk.walls", tags = "world" }). Asynchronous run only (about 2 to 4 minutes).
Multiplayer: final session (two clients look at the same wall, then reconnect).

Test "builder raises a wall segment from the stock" (by day; the clock is moved to 6:59 first when it is night or late
evening):
    - fixture: the barricade targets are set to 0 planks for the test (Fortify.CFG.PLANKS, restored afterwards) so that
      the first site of the plan is a ring segment; one hammer, NEED planks and NEED loose nails (materials the first
      ring site still needs: frame + wall = 4 planks, 6 nails) in the first container of the home (sorted key); the
      worker of a "settlers" group (one fighter, one worker) is made the builder (LivingKnox.Decisions.assignDuties
      wrapped for the test, restored afterwards);
    - expected: the first ring site finished once (Fortify.stats.finished), a WoodenWallLvl1 object on its edge at full
      health and no WoodenWallFrame left there, the edge not in the gap of the plan, exactly NEED planks and NEED nails
      gone from the container, the hammer kept, a stock check with nothing missing, lost or stolen.
Every phase prints "[LKW] measure ..." lines. Cleanup (t:defer): the wall and any corner post added by the test removed
(transmitRemoveItemFromSquare, sent to the clients), fixture items removed, duty wrapper and plank targets restored,
stock reference erased, bodies and test group removed. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

local K = RST.LKHelpers
local measure = K.measurer("[LKW]")

local BODIES_MS = 60000     -- materialization of the members
local WORK_MS = 300000      -- the first ring segment raised

local function LK() return LivingKnox end
local function S() return LivingKnox.Stock end
local function F() return LivingKnox.Fortify end

local function memberNpcs(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    if g == nil then return out end
    for mid, m in pairs(g.members) do
        if m.npc ~= nil then out[mid] = m.npc end
    end
    return out
end

local function bodyCount(gid)
    local n = 0
    for _, npc in pairs(memberNpcs(gid)) do
        if LK().Bodies.find(npc) ~= nil then n = n + 1 end
    end
    return n
end

local function allStanding(gid)
    for _, npc in pairs(memberNpcs(gid)) do
        if not K.standing(npc)() then return false end
    end
    return true
end

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

-- Structures named name on the edge of a site (square of the site, same face).
local function onEdge(site, name)
    local sq = getCell():getGridSquare(site.x, site.y, site.z)
    local out = {}
    if sq == nil then return out end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoThumpable") and (o:getNorth() == true) == (site.north == true) and o:getName() == name then
            out[#out + 1] = o
        end
    end
    return out
end

-- Corner posts around the edge of a site (squares x..x+1, y..y+1).
local function cornersNear(site)
    local out = {}
    for dy = 0, 1 do
        for dx = 0, 1 do
            local sq = getCell():getGridSquare(site.x + dx, site.y + dy, site.z)
            if sq ~= nil then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if instanceof(o, "IsoThumpable") and o:isCorner() then out[#out + 1] = o end
                end
            end
        end
    end
    return out
end

local function contains(list, o)
    for _, v in ipairs(list) do
        if v == o then return true end
    end
    return false
end

RST.suite("lk.walls", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("builder raises a wall segment from the stock", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Fortify ~= nil and E.Fortify.buildStep ~= nil and E.Stock ~= nil
            and E.Stock.takeItem ~= nil and E.Homes ~= nil and E.Decisions ~= nil,
            "LivingKnox fortification (Fortify.buildStep, Stock, Homes) is not loaded")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST walls", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)   -- no furnishing (LK08-T04) on the test site
        -- The player stands in the home of the test group: an unknown intruder there keeps the group alerted, and in MP
        -- (spawn house, no move) the alert never closed while the builder waited (campaign of 2026-10-14).
        K.hidePlayersFrom(t, gid)
        local planks = F().CFG.PLANKS
        F().CFG.PLANKS = { ground = 0, upper = 0 }   -- barricades counted as done: the ring comes first
        t:defer(function()
            F().CFG.PLANKS = planks
            S().clear(gid)
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
            F().reset()
        end, "plank targets restored; stock reference, bodies and group " .. gid .. " removed")
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        local plan = F().plan(gid, { force = true })
        t:ok(plan ~= nil, "no fortification plan for the home")
        if plan.outerSkipped ~= nil then t:skip("no ring around this house: " .. plan.outerSkipped) end
        local site
        for _, st in ipairs(plan.sites) do
            if site == nil and st.kind == "wall" and not st.done then site = st end
        end
        if site == nil then t:skip("no wall segment left to build around this house") end
        local needPlanks, needNails = site.have == 0 and 4 or 2, site.have == 0 and 6 or 4
        local framesBefore = #onEdge(site, "WoodenWallFrame")
        local cornersBefore = cornersNear(site)

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
        for _ = 1, needPlanks do put("Base.Plank") end
        for _ = 1, needNails do put("Base.Nails") end
        local D = E.Decisions
        local assign = D.assignDuties
        D.assignDuties = function(members, objective, night, rotation)
            local out = assign(members, objective, night, rotation)
            if out["m-2"] ~= nil and not night then out["m-2"] = "builder" end
            return out
        end
        t:defer(function()
            D.assignDuties = assign
            for _, it in ipairs(fixture) do
                if box:containsID(it:getID()) then
                    box:DoRemoveItem(it)
                    if isServer() then sendRemoveItemFromContainer(box, it) end
                end
            end
            -- Structures added by the test: the wall (or a frame left by a stopped site) and new corner posts.
            local esq = getCell():getGridSquare(site.x, site.y, site.z)
            local removed = 0
            if esq ~= nil then
                for _, o in ipairs(onEdge(site, "WoodenWallLvl1")) do
                    esq:transmitRemoveItemFromSquare(o)
                    removed = removed + 1
                end
                local frames = onEdge(site, "WoodenWallFrame")
                for i = framesBefore + 1, #frames do
                    esq:transmitRemoveItemFromSquare(frames[i])
                    removed = removed + 1
                end
            end
            for _, o in ipairs(cornersNear(site)) do
                if not contains(cornersBefore, o) and o:getSquare() ~= nil then
                    o:getSquare():transmitRemoveItemFromSquare(o)
                    removed = removed + 1
                end
            end
            measure("cleanup: " .. removed .. " structure(s) removed from " .. site.id)
        end, "duty wrapper restored, fixture items and test structures removed")
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        measure(string.format("fixture of %s in %s: site %s (side %s, %d/%d stage(s)), planks %d -> %d, nails %d -> %d, "
            .. "%d gap segment(s)", gid, cts[1].key, site.id, tostring(site.side), site.have, site.steps, planks0,
            countType(box, "Base.Plank"), nails0, countType(box, "Base.Nails"), #plan.gaps))
        local base = {}
        for k, v in pairs(F().stats) do base[k] = v end

        assert(G.addMember(gid, { role = "fighter", profile = "guard", female = false, day = G.today() }))
        assert(G.addMember(gid, { role = "worker", profile = "handyman", female = false, day = G.today() }))
        assert(G.setLeader(gid, "m-1", G.today()))
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 18 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        t:waitUntil(function()
            local now = getGameTime():getTimeOfDay()
            return bodyCount(gid) == 2 and allStanding(gid) and now >= 7 and now < 21.5
        end, BODIES_MS, function(t2)
            measure("bodies ready: " .. bodyCount(gid) .. " member(s)")
            local function grew(k) return F().stats[k] - base[k] end
            t2:waitUntil(function() return grew("finished") >= 1 or grew("skipped") >= 1 end, WORK_MS, function(t3)
                local walls = onEdge(site, "WoodenWallLvl1")
                local w = walls[1]
                measure(string.format("done: %s walls %d, frames %d, health %s/%s, stages %d, corners %d, planks in the "
                    .. "box %d, nails %d, finished %d, stopped %d", site.id, #walls, #onEdge(site, "WoodenWallFrame"),
                    tostring(w and w:getHealth()), tostring(w and w:getMaxHealth()), grew("stages"), grew("corners"),
                    countType(box, "Base.Plank"), countType(box, "Base.Nails"), grew("finished"), grew("skipped")))
                t3:eq(1, grew("finished"), "sites finished (a stopped site is logged with its reason)")
                t3:eq(1, #walls, "WoodenWallLvl1 on the edge of " .. site.id)
                t3:eq(0, #onEdge(site, "WoodenWallFrame"), "frame replaced by the wall")
                t3:ok(w ~= nil and w:getMaxHealth() > 0 and w:getHealth() == w:getMaxHealth(), "wall at full health")
                for _, gp in ipairs(plan.gaps) do
                    t3:ok(#onEdge(gp, "WoodenWallFrame") + #onEdge(gp, "WoodenWallLvl1") == 0,
                        "structure in the gap at " .. gp.x .. "," .. gp.y)
                end
                t3:eq(planks0, countType(box, "Base.Plank"), "planks left (exactly " .. needPlanks .. " used)")
                t3:eq(nails0, countType(box, "Base.Nails"), "nails left (exactly " .. needNails .. " used)")
                t3:ok(box:containsID(hammer:getID()), "hammer taken from the container")
                local c = S().check(gid, { force = true })
                t3:ok(type(c) == "table", "stock not checked after the work")
                t3:eq(0, c.missing, "missing items at the check after the work")
                t3:eq(0, c.lost, "items counted as lost")
                t3:eq(0, #c.thefts, "thefts counted")
                -- E01-T16: the other clients see the same wall (and no frame) on the edge.
                local around = {}
                for dy = -1, 1 do
                    for dx = -1, 1 do around[#around + 1] = { x = site.x + dx, y = site.y + dy, z = site.z } end
                end
                RST.PeerChecks.checkSquares(t3, around, { thumpable = { "WoodenWallLvl1", "WoodenWallFrame" } })
            end, "the builder did not finish the first ring segment")
        end, "group members not materialized and standing")
    end)
end)
