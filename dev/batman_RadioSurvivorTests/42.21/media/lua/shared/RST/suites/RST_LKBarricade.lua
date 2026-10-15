--[[
lk.barricade - doors and windows of the home barricaded by a Living Knox builder (LK14-T03, server/LivingKnox/
LK_Fortify.lua: Fortify.run / nailPlank, called from LK_Routines.lua for a member whose duty is "builder" and whose
behaviour is "chore"; planks and nails taken through LivingKnox.Stock.takeItem).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player and one outer window, empty door frame or single door
other than the entrance (the test group gets its home on the player's square, no furnishing: LivingKnox.Homes.skip).
Solo: RST.run({ suite = "lk.barricade", tags = "world" }). Asynchronous run only (about 2 to 4 minutes).
Multiplayer: final session (two clients look at the same opening).

Test "builder nails planks from the stock" (by day; the clock is moved to 6:59 first when it is night or late evening):
    - fixture: one hammer, NEED planks and NEED loose nails (NEED = planks the first site of the plan still needs) in
      the first container of the home (sorted key); the worker of a "settlers" group (one fighter, one worker) is
      made the builder (LivingKnox.Decisions.assignDuties wrapped for the test, restored afterwards);
    - expected: the first site of the plan reaches its planned planks once (Fortify.stats.finished), exactly NEED
      planks and NEED nails gone from the container, the hammer kept, the entrance of the home without any new plank,
      a stock check with nothing missing, lost or stolen.
Every phase prints "[LKB] measure ..." lines. Cleanup (t:defer): planks added by the test removed from the barricade
(removePlank, sent to the clients), fixture items removed, duty wrapper restored, stock reference erased, bodies and
test group removed. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

local K = RST.LKHelpers
local measure = K.measurer("[LKB]")

local BODIES_MS = 60000     -- materialization of the members
local WORK_MS = 300000      -- the first site barricaded

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

-- Planks on both sides of the opening of a site (entry or plan site): same square, opposite square.
local function planksAt(site)
    local o = F().openingOf(site)
    if o == nil then return nil end
    local a, b = o:getBarricadeOnSameSquare(), o:getBarricadeOnOppositeSquare()
    return a ~= nil and a:getNumPlanks() or 0, b ~= nil and b:getNumPlanks() or 0, o
end

RST.suite("lk.barricade", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("builder nails planks from the stock", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Fortify ~= nil and E.Fortify.run ~= nil and E.Stock ~= nil and E.Stock.takeItem ~= nil
            and E.Homes ~= nil and E.Decisions ~= nil, "LivingKnox fortification (Fortify, Stock, Homes) is not loaded")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST barricade", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)   -- no furnishing (LK08-T04) on the test site
        -- The player stands in the home of the test group: an unknown intruder there keeps the group alerted, and in MP
        -- (spawn house, no move) the alert never closed while the builder waited (campaign of 2026-10-14).
        K.hidePlayersFrom(t, gid)
        t:defer(function()
            S().clear(gid)
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
            F().reset()
        end, "remove the stock reference, the bodies and group " .. gid)
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        local plan = F().plan(gid, { force = true })
        t:ok(plan ~= nil, "no fortification plan for the home")
        local site
        for _, st in ipairs(plan.sites) do
            if site == nil and st.kind == "barricade" and not st.done then site = st end
        end
        if site == nil then t:skip("no outer opening left to barricade in this house") end
        local need = site.steps - site.have
        local before = { planksAt(site) }
        local entry = plan.entry
        local entryBefore = entry ~= nil and { planksAt({ x = entry.x, y = entry.y, z = entry.z, north = entry.north }) }
            or nil

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
        local D = E.Decisions
        local assign = D.assignDuties
        D.assignDuties = function(members, objective, night, rotation)
            local out = assign(members, objective, night, rotation)
            if out["m-2"] ~= nil and not night then out["m-2"] = "builder" end
            return out
        end
        local added = 0
        t:defer(function()
            D.assignDuties = assign
            for _, it in ipairs(fixture) do
                if box:containsID(it:getID()) then
                    box:DoRemoveItem(it)
                    if isServer() then sendRemoveItemFromContainer(box, it) end
                end
            end
            -- Planks added by the test: removed from the side that gained them (the last one removes the barricade
            -- and sends the removal itself, IsoBarricade.removePlank).
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
        end, "duty wrapper restored, fixture items and test planks removed")
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        measure(string.format("fixture of %s in %s: site %s (%s, %d/%d plank(s), %d needed), entry %s, planks %d -> %d, "
            .. "nails %d -> %d", gid, cts[1].key, site.id, tostring(site.opening), site.have, site.steps, need,
            entry ~= nil and (entry.x .. "," .. entry.y) or "none", planks0, countType(box, "Base.Plank"), nails0,
            countType(box, "Base.Nails")))
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
                local a, b = planksAt(site)
                added = grew("planks")
                measure(string.format("done: %s planks %d+%d -> %d+%d, %d nailed, planks in the box %d, nails %d, "
                    .. "finished %d, stopped %d", site.id, before[1] or 0, before[2] or 0, a or 0, b or 0, added,
                    countType(box, "Base.Plank"), countType(box, "Base.Nails"), grew("finished"), grew("skipped")))
                t3:eq(1, grew("finished"), "sites finished (a stopped site is logged with its reason)")
                t3:eq(need, added, "planks nailed")
                t3:eq(site.steps, math.max(a or 0, b or 0), "planks on the opening")
                t3:eq(planks0, countType(box, "Base.Plank"), "planks left in the container (exactly " .. need .. " used)")
                t3:eq(nails0, countType(box, "Base.Nails"), "nails left in the container (exactly " .. need .. " used)")
                t3:ok(box:containsID(hammer:getID()), "hammer taken from the container")
                if entryBefore ~= nil then
                    local ea, eb = planksAt({ x = entry.x, y = entry.y, z = entry.z, north = entry.north })
                    t3:eq((entryBefore[1] or 0) + (entryBefore[2] or 0), (ea or 0) + (eb or 0), "planks on the entrance")
                end
                local c = S().check(gid, { force = true })
                t3:ok(type(c) == "table", "stock not checked after the work")
                t3:eq(0, c.missing, "missing items at the check after the work")
                t3:eq(0, c.lost, "items counted as lost")
                t3:eq(0, #c.thefts, "thefts counted")
                -- E01-T16: the other clients see the same barricades around the opening.
                local around = {}
                for dy = -1, 1 do
                    for dx = -1, 1 do around[#around + 1] = { x = site.x + dx, y = site.y + dy, z = site.z } end
                end
                RST.PeerChecks.checkSquares(t3, around, { barricade = true })
            end, "the builder did not finish the first site")
        end, "group members not materialized and standing")
    end)
end)
