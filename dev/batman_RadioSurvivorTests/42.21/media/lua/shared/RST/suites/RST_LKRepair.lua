--[[
lk.repair - a damaged barricade of the home repaired first after an attack by a Living Knox builder (LK14-T06,
server/LivingKnox/LK_Fortify.lua: Fortify.plan puts the "repair" sites first while the mark of LivingKnox.Defense.after
is recent, Fortify.run / Fortify.repair replaces the damaged outer plank; plank and nail taken through
LivingKnox.Stock.takeItem).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player and one outer window, empty door frame or single door
other than the entrance, without any barricade yet (the test group gets its home on the player's square, no
furnishing: LivingKnox.Homes.skip).
Solo: RST.run({ suite = "lk.repair", tags = "world" }). Asynchronous run only (about 2 to 4 minutes).
Multiplayer: final session (two clients look at the same barricade).

Test "builder repairs a damaged barricade after an attack" (by day; the clock is moved to 6:59 first when it is night
or late evening):
    - fixture: on the first opening of the plan without planks, a complete barricade (planned planks, planned side)
      whose outer plank is damaged to 30 % (IsoBarricade.Damage, sent to the clients); a defence mark of the group
      ("an attack was just repelled", LivingKnox.Defense.state.after); one hammer, ONE plank and ONE loose nail in the
      first container of the home (sorted key); the worker of a "settlers" group (one fighter, one worker) is made the
      builder (LivingKnox.Decisions.assignDuties wrapped for the test, restored afterwards);
    - expected: the plan is "urgent" with the repair site first; one repair done (Fortify.stats.repairs), the
      barricade still has its planned planks and its outer plank is sound again; in the container one sound plank and
      one nail used and the damaged plank given back (same plank count, one more worn plank, nails as before the
      fixture), the hammer kept, a stock check with nothing missing, lost or stolen.
Every phase prints "[LKR] measure ..." lines. Cleanup (t:defer): the test barricade removed (sent to the clients),
fixture items and the plank given back removed, duty wrapper restored, defence mark, stock reference, bodies and test
group removed. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local measure = K.measurer("[LKR]")

local BODIES_MS = 60000     -- materialization of the members
local WORK_MS = 300000      -- the repair done
local DAMAGE = 700          -- hit points removed from the outer plank (1000 when new)

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

-- Planks of a type in a container: total, and those below their maximum condition.
local function plankCounts(box)
    local n, worn = 0, 0
    local items = box:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:getFullType() == "Base.Plank" then
            n = n + 1
            if it:getCondition() < it:getConditionMax() then worn = worn + 1 end
        end
    end
    return n, worn
end

local function countType(box, ft)
    local n = 0
    local items = box:getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == ft then n = n + 1 end
    end
    return n
end

local function idsOf(box, ft)
    local out = {}
    local items = box:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it:getFullType() == ft then out[it:getID()] = true end
    end
    return out
end

-- Wooden barricade with planks on the opening of a site (the side with the most planks), or nil.
local function barricadeOf(site)
    local o = F().openingOf(site)
    if o == nil then return nil end
    local a, b = o:getBarricadeOnSameSquare(), o:getBarricadeOnOppositeSquare()
    local na = a ~= nil and a:getNumPlanks() or 0
    local nb = b ~= nil and b:getNumPlanks() or 0
    if na > 0 and na >= nb then return a end
    if nb > 0 then return b end
    return nil
end

RST.suite("lk.repair", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("builder repairs a damaged barricade after an attack", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Fortify ~= nil and E.Fortify.repair ~= nil and E.Stock ~= nil
            and E.Stock.takeItem ~= nil and E.Homes ~= nil and E.Decisions ~= nil and E.Defense ~= nil
            and E.Defense.state ~= nil, "LivingKnox fortification (Fortify.repair, Stock, Homes, Defense) is not loaded")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST repair", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)   -- no furnishing (LK08-T04) on the test site
        K.hidePlayersFrom(t, gid)   -- the players stand in the home: unknown, they are intruders (campaign MP 2026-10-15:
        -- alert "intruder rs_mp1", the members watched him instead of their duties)
        t:defer(function()
            E.Defense.state.after[gid] = nil
            S().clear(gid)
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
            F().reset()
        end, "remove the defence mark, the stock reference, the bodies and group " .. gid)
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        local plan = F().plan(gid, { force = true })
        t:ok(plan ~= nil, "no fortification plan for the home")
        local site
        for _, st in ipairs(plan.sites) do
            if site == nil and st.kind == "barricade" and st.have == 0 and not st.done then site = st end
        end
        if site == nil then t:skip("no outer opening without planks in this house") end

        -- Fixture 1: a complete barricade on the planned side, outer plank damaged.
        local o = F().openingOf(site)
        t:ok(o ~= nil, "opening of " .. site.id .. " not found")
        local bar = IsoBarricade.AddBarricadeToObject(o, site.opp == true)
        t:ok(bar ~= nil, "barricade not added on " .. site.id)
        for _ = 1, site.steps do bar:addPlank(nil, nil) end
        if isServer() then bar:transmitCompleteItemToClients() end
        bar:Damage(DAMAGE)   -- outer plank only; sync() on a server (IsoBarricade.Damage)
        t:defer(function()
            local b = barricadeOf(site)
            if b ~= nil and b:getSquare() ~= nil then b:getSquare():transmitRemoveItemFromSquare(b) end
            measure("cleanup: test barricade removed from " .. site.id)
        end, "test barricade removed")
        E.Defense.state.after[gid] = { id = "rst-repair", minute = E.Decisions.currentMinute(), minutes = 1,
            wounded = {}, why = "test" }

        -- Fixture 2: hammer, one plank and one loose nail in the first container of the home.
        local box = cts[1].container
        if not box:isExplored() then box:setExplored(true) end
        local plankIds0 = idsOf(box, "Base.Plank")
        local fixture = {}
        local function put(ft)
            local it = instanceItem(ft)
            t:ok(it ~= nil, "item " .. ft .. " not created")
            box:AddItem(it)
            if isServer() then sendAddItemToContainer(box, it) end
            fixture[#fixture + 1] = it
            return it
        end
        local planks0, worn0 = plankCounts(box)
        local nails0 = countType(box, "Base.Nails")
        local hammer = put("Base.Hammer")
        put("Base.Plank")
        put("Base.Nails")
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
            -- Planks given back by the repair (not in the container before the test).
            local back = {}
            local items = box:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it:getFullType() == "Base.Plank" and not plankIds0[it:getID()] then back[#back + 1] = it end
            end
            for _, it in ipairs(back) do
                box:DoRemoveItem(it)
                if isServer() then sendRemoveItemFromContainer(box, it) end
            end
            measure("cleanup: " .. #back .. " plank(s) given back removed")
        end, "duty wrapper restored, fixture items and given back planks removed")
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        plan = F().plan(gid, { force = true })
        local first = plan.sites[1]
        measure(string.format("fixture of %s in %s: site %s (%s, %d plank(s), outer %.2f), plan urgent %s, first %s, "
            .. "planks %d (%d worn), nails %d", gid, cts[1].key, site.id, tostring(site.opening), bar:getNumPlanks(),
            bar:getThumpCondition(), tostring(plan.urgent), tostring(first and first.id), planks0, worn0, nails0))
        t:ok(plan.urgent == true, "plan not urgent after the defence mark")
        t:eq("repair:" .. string.sub(site.id, string.len("barricade:") + 1), first and first.id or "none",
            "first site of the urgent plan")
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
        -- Dedicated server: the players leave the house (solid; campaign MP 2026-10-15: npcs stuck against them).
        K.clearHome(t, home, function(tc)
        tc:waitUntil(function()
            local now = getGameTime():getTimeOfDay()
            return bodyCount(gid) == 2 and allStanding(gid) and now >= 7 and now < 21.5
        end, BODIES_MS, function(t2)
            measure("bodies ready: " .. bodyCount(gid) .. " member(s)")
            local function grew(k) return F().stats[k] - base[k] end
            -- A stopped site (a passing block on the way: MP campaign of 2026-10-15, "cannot reach" after one stuck
            -- move and the 60 s avoidance of its target) is noted; the builder takes the urgent repair again later.
            local stops = 0
            t2:waitUntil(function()
                local sk = grew("skipped")
                if sk > stops then
                    stops = sk
                    measure("site stopped " .. sk .. " time(s) (reason in the [LivingKnox] log), the builder tries "
                        .. "again")
                end
                return grew("repairs") >= 1
            end, WORK_MS, function(t3)
                local b = barricadeOf(site)
                local n, worn = plankCounts(box)
                measure(string.format("done: %s planks %d, outer %.2f, repairs %d, stopped %d, planks in the box %d "
                    .. "(%d worn), nails %d", site.id, b and b:getNumPlanks() or 0, b and b:getThumpCondition() or 0,
                    grew("repairs"), grew("skipped"), n, worn, countType(box, "Base.Nails")))
                t3:eq(1, grew("repairs"), "repairs done (a stopped site is logged with its reason)")
                t3:ok(b ~= nil, "barricade still on " .. site.id)
                t3:eq(site.steps, b and b:getNumPlanks() or 0, "planks on the opening")
                t3:ok(b ~= nil and b:getThumpCondition() >= F().CFG.REPAIR_BELOW, "outer plank sound again")
                t3:eq(planks0 + 1, n, "planks in the container (the damaged one given back)")
                t3:eq(worn0 + 1, worn, "worn planks in the container")
                t3:eq(nails0, countType(box, "Base.Nails"), "nails left in the container")
                t3:ok(box:containsID(hammer:getID()), "hammer taken from the container")
                local c = S().check(gid, { force = true })
                t3:ok(type(c) == "table", "stock not checked after the work")
                t3:eq(0, c.missing, "missing items at the check after the work")
                t3:eq(0, c.lost, "items counted as lost")
                t3:eq(0, #c.thefts, "thefts counted")
            end, "the builder did not repair the barricade")
        end, "group members not materialized and standing")
        end)
    end)
end)
