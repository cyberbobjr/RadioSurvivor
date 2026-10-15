--[[
lk.meals - real meals of Living Knox npcs taken from their home stock (LK05-T07, server/LivingKnox/LK_Routines.lua
section "meals", behaviour "meal" of LK_Decisions.lua, LivingKnox.Stock.findMeal / takeMeal, LivingKnox.Needs.relieve):
a hungry member walks to a container of its home, faces it, rummages, takes ONE edible item (removed from the
container and from the clients, removed from the stock reference in the same registry write), eats it sitting, and its
hunger drops once by Needs.CFG.MEAL x the ration portion (Stock.portion, at least the strict one).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player (the test group gets its home on the player's square,
no furnishing: LivingKnox.Homes.skip). Solo: RST.run({ suite = "lk.meals", tags = "world" }). Asynchronous run only
(about 1 to 3 minutes). Multiplayer: final session.

What is done:
    - a test group "settlers" (one fighter, two workers) is created with its home on the player's square, the players
      hidden from its perception (a player in the home is an intruder: its alert comes before hunger); the clock is
      moved to 6:59 first when it is night or late evening (by day, no sleep);
    - fixture: two cans of beans and one bottle filled with water are put in the first container of the home (sorted
      key), marked explored; the stock reference is read (LivingKnox.Stock.check);
    - the members get bodies near the player; member m-2 gets hunger 95;
    - m-2 reaches its meal: at a square beside the container, the item taken (one edible food item less in the home
      containers, its id gone from the reference), sitting gesture;
    - the meal ends: hunger lowered once by the expected relief; a stock check finds no missing item (no loss, no
      theft) and no player holds the item.
Every phase prints "[LKM] measure ..." lines; the user checks the gestures on screen. Cleanup (t:defer): fixture
items still in place removed, stock reference erased, bodies removed, test group removed. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local measure = K.measurer("[LKM]")

local BODIES_MS = 60000     -- materialization of the three members
local TAKE_MS = 120000      -- the hungry member reaches the container and takes an item
local EAT_MS = 120000       -- the meal ends (game minutes of Routines.CFG.MEAL_EAT_MINUTES)

local function LK() return LivingKnox end
local function R() return LivingKnox.Routines end
local function S() return LivingKnox.Stock end

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

-- Containers of the home (LivingKnox.Stock.containers), or nil.
local function homeContainers(gid, home)
    local style, def = LK().Homes.ready(home)
    if style == nil then return nil end
    return S().containers(gid, home, style, def ~= nil and def:getIDString() or nil)
end

-- Ids of the edible food items in the home containers: set and count.
local function foodIds(gid, home)
    local out, n = {}, 0
    for _, e in ipairs(S().read(homeContainers(gid, home) or {})) do
        if e.c == "food" and S().consumable(e.item, "food") then
            out[e.i] = e.t
            n = n + 1
        end
    end
    return out, n
end

local function hungerOf(gid, mid)
    local v = LK().Needs.get(gid, mid)
    return v and v.hunger or nil
end

RST.suite("lk.meals", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("hungry member eats one real item from the home stock", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Routines ~= nil and E.Routines.runMeal ~= nil and E.Stock ~= nil
            and E.Stock.findMeal ~= nil and E.Needs ~= nil and E.Homes ~= nil,
            "LivingKnox meals (Routines, Stock, Needs, Homes) are not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST meals", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)   -- no furnishing (LK08-T04) on the test site
        K.hidePlayersFrom(t, gid)   -- the player in the home would be an intruder (alert before hunger)
        local fixture = {}
        local fixtureBox
        t:defer(function()
            if fixtureBox ~= nil then
                for _, it in ipairs(fixture) do
                    if fixtureBox:containsID(it:getID()) then
                        fixtureBox:DoRemoveItem(it)
                        if isServer() then sendRemoveItemFromContainer(fixtureBox, it) end
                    end
                end
            end
            S().clear(gid)
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove the fixture items, the stock reference, the bodies and group " .. gid)

        -- Fixture: food and water in the first container of the home.
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        fixtureBox = cts[1].container
        if not fixtureBox:isExplored() then fixtureBox:setExplored(true) end
        for _, ft in ipairs({ "Base.TinnedBeans", "Base.TinnedBeans", "Base.WaterBottle" }) do
            local it = instanceItem(ft)
            t:ok(it ~= nil, "item " .. ft .. " not created")
            if it:getFluidContainer() ~= nil then
                it:getFluidContainer():Empty()
                it:getFluidContainer():addFluid(Fluid.Water, it:getFluidContainer():getCapacity())
            end
            fixtureBox:AddItem(it)
            if isServer() then sendAddItemToContainer(fixtureBox, it) end
            fixture[#fixture + 1] = it
        end
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        measure(string.format("stock of %s: %d food, %d water, ration %s, container %s", gid, r.totals.food,
            r.totals.water, tostring(S().needs(gid) and S().needs(gid).rationName), cts[1].key))

        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "handyman" }, { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 20 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        t:waitUntil(function()
            local now = getGameTime():getTimeOfDay()
            return bodyCount(gid) == 3 and allStanding(gid) and now >= 7 and now < 21.5
        end, BODIES_MS, function(t2)
            local hour = E.Needs.currentHour() or 0
            t2:ok(G.update(function(d)
                local m = d.groups[gid].members["m-2"]
                m.vitals = { hunger = 95, thirst = 20, fatigue = 20, fear = 0, hour = hour }
                return true, true
            end), "hunger not set")
            local npc = memberNpcs(gid)["m-2"]
            local before, nBefore = foodIds(gid, home)
            local hungerBefore = hungerOf(gid, "m-2")
            local portion = math.max(S().portion(gid), S().PORTIONS[3])
            local relief = math.floor(E.Needs.CFG.MEAL * portion + 0.5)
            measure(string.format("hungry: %s %s hunger %d, %d edible food item(s), expected relief %d", "m-2", npc,
                hungerBefore, nBefore, relief))
            t2:waitUntil(function()
                local m = R().get(npc)
                return m ~= nil and m.took ~= nil
            end, TAKE_MS, function(t3)
                local m = R().get(npc)
                local z = E.Bodies.find(npc)
                local after, nAfter = foodIds(gid, home)
                measure(string.format("taken: %s from %s, body %.1f,%.1f facing %d, gesture %s, %d edible food left",
                    m.took.t, m.took.k, z:getX(), z:getY(), math.floor(z:getDirectionAngle()), E.Anim.gestureOf(npc),
                    nAfter))
                t3:eq(nBefore - 1, nAfter, "edible food items after the take")
                t3:ok(before[m.took.i] ~= nil and after[m.took.i] == nil, "taken item still in the home containers")
                for _, e in ipairs(S().reference(gid).items) do
                    t3:ok(e.i ~= m.took.i, "taken item still in the stock reference")
                end
                t3:ok(S().holderOf(m.took.i) == nil, "a player holds the taken item")
                t3:eq("meal", E.Decisions.get(npc).b, "behaviour of the member during its meal")
                -- The ration may change between the set-up and the meal (first stock check of the test group: strict
                -- ration, seen in game on 2026-10-12): the relief follows the portion of the moment of the meal.
                portion = math.max(S().portion(gid), S().PORTIONS[3])
                relief = math.floor(E.Needs.CFG.MEAL * portion + 0.5)
                measure(string.format("ration portion at the meal %.2f, expected relief %d", portion, relief))
                local tookId = m.took.i
                t3:waitUntil(function()
                    local h = hungerOf(gid, "m-2")
                    return h ~= nil and h <= hungerBefore - relief + 2
                end, EAT_MS, function(t4)
                    local h = hungerOf(gid, "m-2")
                    measure(string.format("eaten: hunger %d -> %d, behaviour %s, gesture %s", hungerBefore, h,
                        tostring(E.Decisions.get(npc) and E.Decisions.get(npc).b), E.Anim.gestureOf(npc)))
                    t4:ok(hungerBefore - h >= relief - 2 and hungerBefore - h <= relief + 2,
                        "hunger not lowered once by the relief")
                    local c = S().check(gid, { force = true })
                    t4:ok(type(c) == "table", "stock not checked after the meal")
                    t4:eq(0, c.missing, "missing items at the check after the meal")
                    t4:eq(0, c.lost, "items counted as lost")
                    t4:eq(0, #c.thefts, "thefts counted")
                    local _, nEnd = foodIds(gid, home)
                    t4:eq(nBefore - 1, nEnd, "edible food items at the end (exactly one eaten, none created)")
                    t4:ok(S().holderOf(tookId) == nil, "a player holds the eaten item")
                end, "meal not finished (hunger not lowered)")
            end, "hungry member did not take an item")
        end, "group members not materialized and standing")
    end)
end)
