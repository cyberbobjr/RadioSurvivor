--[[
lk.forage - food production of Living Knox groups (LK05-T11): foraging trips drawn from the vanilla foraging tables
(server/LivingKnox/LK_Food.lua, run as an expedition of kind "forage" by LK_Expeditions.lua) and watering of the
home's farming plants with water of the home stock (job "water" of LK_Upkeep.lua).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house (the test group gets its home on the player's square, no furnishing: LivingKnox.Homes.skip). Solo:
RST.run({ suite = "lk.forage", tags = "world" }). Asynchronous run only (about 3 to 8 minutes). Stay near the house
during the run (bodies far from every player are taken out of the world: the trip would go offscreen).
Multiplayer: final session.

Test 1 "draws are reproducible and come from the vanilla tables" (no world change): for the foraging zones found
    around the player (LivingKnox.Food.zonesNear), 20 draws of a fake trip are made twice with the same stream and the
    same conditions: same results; every item drawn has a vanilla foraging definition (forageSystem.itemDefs) and is
    food. SKIP when no foraging zone is known near the player (cells never approached in this game).
Test 2 "foragers gather vanilla food near home and store it" (by day; the clock is moved to 9:00 first when the
    hour of day is outside 7 h - 15 h): a group "settlers" (fighter leader, worker, two scouts) gets bodies near the
    player; its stock is read; the group is set to objective "supply" with both scouts as foragers. SKIP when food is
    not what the home lacks most, or when no foraging zone 40 squares around has enough food this season
    (LivingKnox.Food.pickTarget). Expected: a trip of kind "forage" leaves, reaches the zone (phase search), the
    scouts kneel and draw, the team comes back and unloads (journal "return"); every item added to the home
    containers during the trip is a vanilla forageable type (forageSystem.itemDefs, or a seed of the vanilla seed
    table); the food items are in the stock reference; a stock check finds no missing item, no loss, no theft.
Test 3 "a thirsty plant of the home is watered from the stock" (by day, SKIP when it rains): a plant is plowed and
    seeded (vanilla SFarmingSystem) on a free outdoor square within 8 squares of the player, its water level set to 0;
    a water bottle holding 1 l of tainted water is put in the first container of the home; a group (fighter, two
    workers) does its chores. Expected once: the plant's water level rises by 10 per dose, the bottle loses 0.2 l per
    dose, a stock check finds nothing lost.
Decision of 2026-10-15 (nothing cut): test 2 finds its house with RST.Places (a house with a foraging zone that gives
    food now; solo and dedicated server, players moved and brought back) and makes food what the home lacks most (food
    items of the home set aside, the other categories filled up; both undone afterwards).
Test 4 "a ripe plant of the home is harvested and its produce stored" and test 5 "fishers bring vanilla fish home at
    dawn" check the harvest job of LivingKnox.Upkeep and the fishing trips of LivingKnox.Expeditions (vanilla net
    tables). Test 4 waits for ITS plant: other ripe plants of the home garden may be harvested before it.
Tests 2 to 5 keep ordinary zombies away from the home (removed within 40 squares, every 30 ticks): a zombie drifting
    to the house raises an alert, the members stand guard instead of foraging or doing their chores.
Every phase prints "[LKF2] measure ..." lines; the user checks the walk, the kneeling and the watering on screen.
Cleanup (t:defer): trip cancelled, stock reference erased, bodies and test group removed, plant removed, fixture
bottle removed. Items brought back stay in the house; the clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Places"

local K = RST.LKHelpers
local measure = K.measurer("[LKF2]")

local BODIES_MS = 60000     -- materialization of the members
local REACH_MS = 180000     -- the team reaches the foraging zone
local FORAGE_MS = 240000    -- the team has foraged and starts back
local BACK_MS = 240000      -- the team is home and has unloaded
local WATER_MS = 300000     -- the plant is watered

local function LK() return LivingKnox end
local function X() return LivingKnox.Expeditions end
local function F() return LivingKnox.Food end
local function S() return LivingKnox.Stock end
local function U() return LivingKnox.Upkeep end

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

local function phaseOf(gid)
    local t = X().get(gid)
    return t and t.phase or nil
end

local function homeContainers(gid, home)
    local style, def = LK().Homes.ready(home)
    if style == nil then return nil end
    return S().containers(gid, home, style, def ~= nil and def:getIDString() or nil)
end

-- Every item of the home containers: { [id] = full type }.
local function homeItems(gid, home)
    local out = {}
    for _, ct in ipairs(homeContainers(gid, home) or {}) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            out[it:getID()] = it:getFullType()
        end
    end
    return out
end

local function bodyText(gid, mid)
    local npc = memberNpcs(gid)[mid]
    local z = npc and LK().Bodies.find(npc) or nil
    if z == nil then return mid .. " no body" end
    local st = LK().Decisions.get(npc)
    return string.format("%s %.1f,%.1f %s gesture %s", mid, z:getX(), z:getY(), tostring(st and st.b),
        tostring(LK().Anim.gestureOf(npc)))
end

local function newGroup(t, home, specs, name)
    local E, G = LK(), LK().Groups
    local g = assert(G.create({ type = "settlers", name = name, day = G.today(), home = home }))
    local gid = g.id
    E.Homes.skip(gid)   -- no furnishing (LK08-T04) on the test site
    K.hidePlayersFrom(t, gid)   -- the players stand in the home: unknown, they are intruders (campaign MP 2026-10-15:
    -- alert "intruder rs_mp1", the members watched him instead of their duties)
    t:defer(function()
        if X() ~= nil then X().cancel(gid, "test cleanup") end
        S().clear(gid)
        local npcs = memberNpcs(gid)
        G.remove(gid)
        for _, npc in pairs(npcs) do
            E.Directives.forget(npc)
            E.Bodies.despawn(npc, true)
        end
    end, "cancel the trip, remove the stock reference, the bodies and group " .. gid)
    return gid, function()
        for _, spec in ipairs(specs) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
    end
end

-- Vanilla forageable type: a foraging definition, or a seed of the vanilla seed table of a wild crop.
local function vanillaForageable(t)
    local fs = forageSystem
    if fs.itemDefs[t] ~= nil then return true end
    for _, s in pairs(fs.seedTable or {}) do
        if type(s) == "table" and s.type == t then return true end
    end
    return false
end

local function insideHouse(t)
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local sq = p:getCurrentSquare()
    if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
    return { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
end

local function amountOf(it)
    local fc = it ~= nil and it:getFluidContainer() or nil
    return fc ~= nil and fc:getAmount() or 0
end

-- Ordinary zombies (no Living Knox tag) kept away from the home during the test: removed within SWEEP_RADIUS squares
-- now and every SWEEP_TICKS ticks until the end of the test (t:defer). Solo campaign of 2026-10-15 (shard2,
-- lk.forage test 2): zombies drifting one by one to the test house (after lk.defense) raised alerts and defenses for
-- 40 game minutes, the foragers stood guard and the trip came back on "search time over" without a single draw.
local SWEEP_RADIUS = 40
local SWEEP_TICKS = 30
local function keepZombiesAway(t, home)
    local I = LK().Identity
    local removed, n = 0, 0
    local function sweep()
        local list = getCell():getZombieList()
        for i = list:size() - 1, 0, -1 do
            local z = list:get(i)
            if z ~= nil and not z:isDead() and math.abs(z:getX() - home.x) <= SWEEP_RADIUS
                and math.abs(z:getY() - home.y) <= SWEEP_RADIUS
                and not (z:hasModData() and I ~= nil and I.readTag(z:getModData()) ~= nil) then
                z:removeFromWorld()
                z:removeFromSquare()
                removed = removed + 1
            end
        end
    end
    local function tick()
        n = n + 1
        if n % SWEEP_TICKS == 0 then sweep() end
    end
    sweep()
    Events.OnTick.Add(tick)
    t:defer(function()
        Events.OnTick.Remove(tick)
        if removed > 0 then measure(removed .. " ordinary zombie(s) kept away from the home during the test") end
    end, "stop keeping zombies away from the home")
end

-- Door (IsoDoor, or a built door) on a square within DOOR_MARGIN squares of sq.
local DOOR_MARGIN = 2
local function nearDoor(sq)
    local cell = getCell()
    for dy = -DOOR_MARGIN, DOOR_MARGIN do
        for dx = -DOOR_MARGIN, DOOR_MARGIN do
            local q = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local objs = q ~= nil and q:getObjects() or nil
            for i = 0, (objs ~= nil and objs:size() or 0) - 1 do
                local o = objs:get(i)
                if instanceof(o, "IsoDoor") or (instanceof(o, "IsoThumpable") and o:isDoor()) then return true end
            end
        end
    end
    return false
end

-- Free outdoor square 3 to 8 squares from home for the plant of tests 3 and 4, nearest first, away from the doors:
-- a plant beside a door exit makes the npcs drop the door route (they avoid trampling plants) and that side of the
-- house became unreachable (solo run of 2026-10-15: carrot at 11314,6939 next to the door 11313,6940,N, the farmer and
-- the handyman stuck at 11317.5,6938.5 for 11 minutes, harvest never done).
local function plantSpot(E, home)
    local cell = getCell()
    for r = 3, 8 do
        for _, d in ipairs(E.Bodies.ring(r)) do
            local sq = cell:getGridSquare(home.x + d[1], home.y + d[2], home.z)
            if sq ~= nil and sq:getBuildingDef() == nil and sq:isFree(false)
                and not sq:HasStairs() and not sq:hasFarmingPlant() and not sq:isWaterSquare()
                and sq:getObjects():size() <= 1 and E.Bodies.findFreeSquare(sq:getX(), sq:getY(), sq:getZ())
                and not nearDoor(sq) then
                return sq
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- decor of test 2 (decision of 2026-10-15)

-- House with a foraging zone that gives food at this season within Food.CFG.MAX_DIST squares, the player inside on
-- the ground floor: the square of the player, or nil (RST.Places spot).
local function forageSpot(p)
    local sq = p:getCurrentSquare()
    if not RST.Places.inside(sq) then return nil end
    local c = F().conditions()
    for _, zn in ipairs(F().zonesNear(sq:getX(), sq:getY(), F().CFG.MAX_DIST)) do
        if F().yield(zn.type, c) >= F().CFG.MIN_YIELD then return sq end
    end
    return nil
end

-- House with water (IsoFlagType.water) within Food.CFG.MAX_DIST squares of the player standing inside on the ground
-- floor: the square of the player, or nil (RST.Places spot of the fishing test).
local function waterSpot(p)
    local sq = p:getCurrentSquare()
    if not RST.Places.inside(sq) then return nil end
    local cell, r = getCell(), F().CFG.MAX_DIST
    for dy = -r, r, 2 do
        for dx = -r, r, 2 do
            local q = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, 0)
            if q ~= nil and q:isWaterSquare() then return sq end
        end
    end
    return nil
end

-- Items that fill a category of the stock (vanilla 42.21, as the kits of LK_Stock.lua).
local FILLERS = { water = { t = "Base.WaterBottle", fill = "Water" }, medical = { t = "Base.Bandage" },
    ammo = { t = "Base.Bullets9mmBox" }, materials = { t = "Base.NailsBox" } }

local function sendAdd(c, it) if isServer() then sendAddItemToContainer(c, it) end end
local function sendRemove(c, it) if isServer() then sendRemoveItemFromContainer(c, it) end end

-- Food is what the home lacks most, whatever the house held: the food items of the home containers are set aside
-- (put back by t:defer), and every other category is filled up to its target for members living members (filler
-- items removed by t:defer). Returns the numbers set aside and added, or nil and why.
local function foodShortage(t, gid, home, members)
    local cts = homeContainers(gid, home)
    if cts == nil or #cts == 0 then return nil, "no container in the house of the player" end
    local taken, have = {}, {}
    for _, ct in ipairs(cts) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            local cat = S().categoryOf(it)
            if cat == "food" then
                taken[#taken + 1] = { c = ct.container, item = it }
            elseif cat ~= nil then
                have[cat] = (have[cat] or 0) + 1
            end
        end
    end
    for _, e in ipairs(taken) do
        e.c:DoRemoveItem(e.item)
        sendRemove(e.c, e.item)
    end
    t:defer(function()
        for _, e in ipairs(taken) do
            if e.item:getContainer() == nil then
                e.c:AddItem(e.item)
                sendAdd(e.c, e.item)
            end
        end
    end, "put back the " .. #taken .. " food item(s) of the house")
    local totals = { food = 0 }
    for c in pairs(FILLERS) do totals[c] = have[c] or 0 end
    local a = S().assess(totals, members)
    local box, added = cts[1].container, {}
    if not box:isExplored() then box:setExplored(true) end
    for c, f in pairs(FILLERS) do
        for _ = 1, math.max(0, (a and a.want[c] or 0) - (have[c] or 0)) do
            local it = instanceItem(f.t)
            if it ~= nil then
                local fc = f.fill ~= nil and it:getFluidContainer() or nil
                if fc ~= nil then
                    fc:Empty()
                    fc:addFluid(Fluid[f.fill], fc:getCapacity())
                end
                box:AddItem(it)
                sendAdd(box, it)
                added[#added + 1] = it
            end
        end
    end
    t:defer(function()
        for _, it in ipairs(added) do
            local c = it:getContainer()
            if c ~= nil then
                c:DoRemoveItem(it)
                sendRemove(c, it)
            end
        end
    end, "remove the " .. #added .. " filler item(s) of the stock")
    return #taken, #added
end

RST.suite("lk.forage", { tags = { "world", "server" }, testTimeoutMs = 900000, timeoutMs = 1800000 }, function(s)
    s.test("draws are reproducible and come from the vanilla tables", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        t:ok(LK() ~= nil and F() ~= nil and F().draw ~= nil, "LivingKnox.Food is not loaded on this side")
        t:ok(F().vanilla() ~= nil, "vanilla foraging tables (forageSystem.lootTable) not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local zones = F().zonesNear(math.floor(p:getX()), math.floor(p:getY()), F().CFG.MAX_DIST)
        if #zones == 0 then t:skip("no foraging zone known within " .. F().CFG.MAX_DIST .. " squares") end
        local c = F().conditions()
        local zone = zones[1].type
        local first, food = {}, 0
        for k = 1, 20 do
            local list, text = F().round("grp-99999", 1, k, zone, c, 8)
            first[k] = text
            for _, e in ipairs(list) do
                food = food + 1
                t:ok(vanillaForageable(e.t), e.t .. " has no vanilla foraging definition")
                t:ok(F().isFood(e.t), e.t .. " is not food")
            end
        end
        for k = 1, 20 do
            local _, text = F().round("grp-99999", 1, k, zone, c, 8)
            t:eq(first[k], text, "draw " .. k .. " repeated")
        end
        measure(string.format("draws: zone %s at %d squares, %s, yield %.2f, %d food item(s) in 20 draws: %s", zone,
            zones[1].d, F().conditionText(c), F().yield(zone, c), food, table.concat(first, " / ")))
    end)

    s.test("foragers gather vanilla food near home and store it", function(t0)
        if type(isClient) == "function" and isClient() then t0:skip("authority only (not on an MP client)") end
        local E0 = LK()
        t0:ok(E0 ~= nil and E0.Expeditions ~= nil and E0.Food ~= nil and E0.Stock ~= nil and E0.Homes ~= nil,
            "LivingKnox foraging (Expeditions, Food, Stock, Homes) not loaded")
        t0:ok(F().vanilla() ~= nil, "vanilla foraging tables (forageSystem.lootTable) not ready")
        -- Decor (decision of 2026-10-15, nothing cut): a house with a foraging zone that gives food now within
        -- MAX_DIST squares, found around the player or at the nearest buildings (RST.Places, solo and server).
        RST.Places.ensure(t0, { name = "house with a foraging zone that gives food within " .. F().CFG.MAX_DIST
            .. " squares", spot = forageSpot, radius = 600, tries = 12 }, function(t)
        local E = LK()
        t:ok(E.Groups.ensure(), "group registry not ready")
        local home = insideHouse(t)
        local G = E.Groups
        local gid, addMembers = newGroup(t, home, { { "fighter", "guard" }, { "worker", "handyman" },
            { "scout", "scout" }, { "scout", "scout" } }, "RST forage")
        keepZombiesAway(t, home)
        addMembers()
        -- Food is what the home lacks most (fixture): no SKIP "food is not what the home lacks most".
        local taken, filled = foodShortage(t, gid, home, 4)
        if taken == nil then t:skip(filled) end
        measure(string.format("fixture: %d food item(s) of the house set aside, %d filler item(s) added", taken, filled))
        local tod = getGameTime():getTimeOfDay()
        local c = X().CFG
        if tod < c.DEPART_FROM or tod >= c.DEPART_TO - 1 then
            getGameTime():setTimeOfDay(9)
            measure(string.format("time of day %.2f: clock set to 9:00 first", tod))
        end
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        local before
        -- Dedicated server: the players leave the house (solid; campaign MP 2026-10-15: npcs stuck against them).
        K.clearHome(t, home, function(tc)
        tc:waitUntil(function() return bodyCount(gid) == 4 end, BODIES_MS, function(t2)
            local r, why = S().check(gid, { force = true })
            t2:ok(type(r) == "table", "stock not checked: " .. tostring(why))
            before = homeItems(gid, home)
            t2:ok(G.update(function(d)
                local live = d.groups[gid]
                live.objective = "supply"
                live.members["m-3"].duty = "forager"
                live.members["m-4"].duty = "forager"
                return true, true
            end), "objective and duties not set")
            local trip = X().get(gid)   -- the minute pass may already have sent the team
            if trip == nil then
                local want = X().wantOf(gid)
                if not F().wanted(want) then t2:skip("food is not what the home lacks most") end
                local target, fwhy = F().pickTarget(gid, G.get(gid))
                if target == nil then t2:skip("no foraging place: " .. tostring(fwhy)) end
                local n, dwhy = X().tryDepart(gid, E.Decisions.currentMinute())
                if n == nil then t2:skip("no departure: " .. tostring(dwhy)) end
                trip = X().get(gid)
            end
            t2:eq("forage", trip.kind, "kind of the trip")
            measure(string.format("departure: trip %d to %s at %d,%d,%d, team %s, load %d, draws %d", trip.n,
                tostring(trip.target.label), trip.target.x, trip.target.y, trip.target.z, table.concat(trip.team, " "),
                trip.cap, trip.r))
            t2:waitUntil(function() return phaseOf(gid) ~= "out" end, REACH_MS, function(t3)
                measure(string.format("reached: phase %s; %s; %s", tostring(phaseOf(gid)), bodyText(gid, "m-3"),
                    bodyText(gid, "m-4")))
                t3:ok(phaseOf(gid) == "search" or phaseOf(gid) == "back", "team did not start foraging")
                local drawn = 0
                t3:waitUntil(function()
                    local cur = X().get(gid)
                    if cur ~= nil then drawn = math.max(drawn, cur.k or 0) end
                    return cur == nil or cur.phase == "back" or cur.phase == "deliver"
                end, FORAGE_MS, function(t4)
                    local cur = X().get(gid)
                    measure(string.format("foraged: %d draw(s), %d item(s) to bring; %s; %s", drawn,
                        cur and #cur.carry or -1, bodyText(gid, "m-3"), bodyText(gid, "m-4")))
                    t4:ok(drawn > 0, "no draw made")
                    t4:waitUntil(function() return X().get(gid) == nil end, BACK_MS, function(t5)
                        local after = homeItems(gid, home)
                        local ref = {}
                        local reference = S().reference(gid)
                        for _, e in ipairs(reference and reference.items or {}) do ref[e.i] = e.c end
                        local added, foods, inRef, types = 0, 0, 0, {}
                        for i, ft in pairs(after) do
                            if before[i] == nil then
                                added = added + 1
                                types[#types + 1] = ft
                                t5:ok(vanillaForageable(ft), ft .. " is not a vanilla forageable type")
                                if F().isFood(ft) then
                                    foods = foods + 1
                                    if ref[i] == "food" then inRef = inRef + 1 end
                                end
                            end
                        end
                        local back = {}
                        for _, e in ipairs(G.get(gid).log) do
                            if e.kind == "return" then back[#back + 1] = e.text end
                        end
                        measure(string.format("home: %d new item(s) (%d food, %d in the reference): %s; journal: %s",
                            added, foods, inRef, table.concat(types, " "), table.concat(back, " / ")))
                        t5:eq(1, #back, "return entries in the group journal")
                        t5:eq(foods, inRef, "foraged food items in the stock reference")
                        local chk = S().check(gid, { force = true })
                        t5:ok(type(chk) == "table", "stock not checked after the return")
                        t5:eq(0, chk.missing, "missing items at the check after the return")
                        t5:eq(0, chk.lost, "items counted as lost")
                        t5:eq(0, #chk.thefts, "thefts counted")
                    end, "team not back home (trip not closed)")
                end, "team did not finish foraging")
            end, "team did not reach the foraging zone")
        end, "group members not materialized")
        end)
        end)
    end)

    s.test("a thirsty plant of the home is watered from the stock", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Upkeep ~= nil and E.Upkeep.waterUses ~= nil and E.Stock ~= nil,
            "LivingKnox upkeep (watering) not loaded")
        local sys = SFarmingSystem and SFarmingSystem.instance
        t:ok(sys ~= nil, "SFarmingSystem is not loaded on this side (authority only)")
        t:ok(E.Groups.ensure(), "group registry not ready")
        if U().raining() then t:skip("it rains: no watering under the rain") end
        local home = insideHouse(t)
        local gid, addMembers = newGroup(t, home, { { "fighter", "guard" }, { "worker", "handyman" },
            { "worker", "farmer" } }, "RST watering")
        keepZombiesAway(t, home)
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        local spot = plantSpot(E, home)
        if spot == nil then t:skip("no free outdoor square 3 to 8 squares from the player, away from the doors") end
        local px, py, pz = spot:getX(), spot:getY(), spot:getZ()
        t:defer(function()
            local q = sys:getLuaObjectAt(px, py, pz)
            if q ~= nil then sys:removePlant(q) end
        end, "remove the plant")
        sys:plow(spot)
        local plant = sys:getLuaObjectAt(px, py, pz)
        t:ok(plant ~= nil, "plow created no plant")
        plant:seed("Carrots", 0)
        plant.waterLvl = 0
        plant:saveData()
        local uses = U().waterUses(plant)
        if uses <= 0 then t:skip("the seeded plant needs no water (waterNeeded " .. tostring(plant.waterNeeded) .. ")") end
        local box = cts[1].container
        if not box:isExplored() then box:setExplored(true) end
        local bottle = instanceItem("Base.WaterBottle")
        t:ok(bottle ~= nil and bottle:getFluidContainer() ~= nil, "water bottle not created")
        bottle:getFluidContainer():Empty()
        bottle:getFluidContainer():addFluid(Fluid.TaintedWater, 1)
        box:AddItem(bottle)
        if isServer() then sendAddItemToContainer(box, bottle) end
        t:defer(function()
            if box:containsID(bottle:getID()) then
                box:DoRemoveItem(bottle)
                if isServer() then sendRemoveItemFromContainer(box, bottle) end
            end
        end, "remove the fixture bottle")
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        local level0, water0 = plant.waterLvl, amountOf(bottle)
        local base = U().stats.watered or 0
        measure(string.format("fixture: plant %d,%d needs %s (level %d, %d dose(s)), bottle %.2f l in %s", px, py,
            tostring(plant.waterNeeded), level0, uses, water0, cts[1].key))
        addMembers()
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 18 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        -- Dedicated server: the players leave the house (solid; campaign MP 2026-10-15: npcs stuck against them).
        K.clearHome(t, home, function(tc)
        tc:waitUntil(function() return (U().stats.watered or 0) > base end, BODIES_MS + WATER_MS, function(t2)
            local q = sys:getLuaObjectAt(px, py, pz)
            local doses = math.floor((water0 - amountOf(bottle)) / 0.2 + 0.5)
            measure(string.format("watered: level %d -> %d, bottle %.2f -> %.2f l (%d dose(s))", level0,
                q and q.waterLvl or -1, water0, amountOf(bottle), doses))
            t2:eq(1, (U().stats.watered or 0) - base, "waterings")
            t2:ok(doses >= 1, "no water taken from the bottle")
            -- An hourly update of the vanilla farming system may lower the level a little in between.
            t2:ok(q.waterLvl >= math.min(100, level0 + 10 * doses) - 2, "plant water level not raised by the doses")
            t2:ok(q.state ~= "destroyed", "plant destroyed")
            local c = S().check(gid, { force = true })
            t2:ok(type(c) == "table", "stock not checked after the watering")
            t2:eq(0, c.lost, "items counted as lost")
            t2:eq(0, #c.thefts, "thefts counted")
        end, "plant not watered")
        end)
    end)

    -- LK05-T11 (decision of 2026-10-15, nothing cut): the harvest of the home garden. Contract asked to the
    -- production code (described in the report of 2026-10-15): job "harvest" of LivingKnox.Upkeep, counted in
    -- LivingKnox.Upkeep.stats.harvested, the produce of farming_vegetableconf.props[type].vegetableName (and its
    -- seeds) put in the home containers, the plant emptied as SFarmingSystem:harvest does (hasVegetable false),
    -- without a player. Missing production code: FAIL that says so.
    s.test("a ripe plant of the home is harvested and its produce stored", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Upkeep ~= nil and E.Stock ~= nil, "LivingKnox upkeep not loaded")
        t:ok(U().stats.harvested ~= nil, "harvest of the home garden not coded in production (LK05-T11: job "
            .. "harvest of LivingKnox.Upkeep, LivingKnox.Upkeep.stats.harvested)")
        local sys = SFarmingSystem and SFarmingSystem.instance
        t:ok(sys ~= nil, "SFarmingSystem is not loaded on this side (authority only)")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local home = insideHouse(t)
        local gid, addMembers = newGroup(t, home, { { "fighter", "guard" }, { "worker", "handyman" },
            { "worker", "farmer" } }, "RST harvest")
        keepZombiesAway(t, home)
        local spot = plantSpot(E, home)
        if spot == nil then t:skip("no free outdoor square 3 to 8 squares from the player, away from the doors") end
        local px, py, pz = spot:getX(), spot:getY(), spot:getZ()
        t:defer(function()
            local q = sys:getLuaObjectAt(px, py, pz)
            if q ~= nil then sys:removePlant(q) end
        end, "remove the plant")
        sys:plow(spot)
        local plant = sys:getLuaObjectAt(px, py, pz)
        t:ok(plant ~= nil, "plow created no plant")
        plant:seed("Carrots", 0)
        local props = farming_vegetableconf and farming_vegetableconf.props and farming_vegetableconf.props.Carrots
        t:ok(props ~= nil and props.vegetableName ~= nil, "vanilla carrot definition not found")
        plant.hasVegetable = true            -- ripe, as farming_vegetableconf.lua:328 marks it
        plant.waterLvl = 100
        plant:saveData()
        local before = homeItems(gid, home)
        local base = U().stats.harvested or 0
        measure(string.format("fixture: ripe carrot plant at %d,%d, produce %s", px, py, tostring(props.vegetableName)))
        addMembers()
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 18 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        -- Wait for THIS plant: other ripe plants of the home garden (lavender, poppies of the house in the solo
        -- campaign of 2026-10-15) may be harvested first, each one counted in stats.harvested.
        local function ownHarvested()
            local q = sys:getLuaObjectAt(px, py, pz)
            return q == nil or q.hasVegetable ~= true
        end
        K.clearHome(t, home, function(tc)
        tc:waitUntil(ownHarvested, BODIES_MS + 2 * WATER_MS, function(t2)
            local q = sys:getLuaObjectAt(px, py, pz)
            local after = homeItems(gid, home)
            local produce, types = 0, {}
            for i, ft in pairs(after) do
                if before[i] == nil then
                    types[#types + 1] = ft
                    if ft == props.vegetableName or ft == "Base." .. tostring(props.vegetableName) then
                        produce = produce + 1
                    end
                end
            end
            measure(string.format("harvested: %d harvest(s), %d produce item(s) stored, new items: %s, plant has "
                .. "vegetable %s", (U().stats.harvested or 0) - base, produce, table.concat(types, " "),
                tostring(q and q.hasVegetable)))
            t2:ok((U().stats.harvested or 0) - base >= 1, "harvest not counted in LivingKnox.Upkeep.stats.harvested")
            t2:ok(produce >= 1, "no produce of the plant in the home containers")
            t2:ok(q == nil or q.hasVegetable ~= true, "plant still ripe after the harvest")
            local c = S().check(gid, { force = true })
            t2:ok(type(c) == "table", "stock not checked after the harvest")
            t2:eq(0, c.lost, "items counted as lost")
        end, "plant not harvested")
        end)
    end)

    -- LK05-T11 (decision of 2026-10-15): fishing at dawn and dusk. Contract asked to the production code (report of
    -- 2026-10-15): a trip of kind LivingKnox.Expeditions.FISH ("fish") when food is what the home lacks most and the
    -- hour is in LivingKnox.Food.FISH_HOURS (dawn or dusk) and water is within reach (LivingKnox.Food.fishTarget),
    -- catches drawn from the vanilla net tables (Fishing.fishNet, Fishing.fishNetWithBait, Fishing.fishes), stored
    -- in the home containers. Missing production code: FAIL that says so.
    s.test("fishers bring vanilla fish home at dawn", function(t0)
        if type(isClient) == "function" and isClient() then t0:skip("authority only (not on an MP client)") end
        t0:ok(X().FISH ~= nil and F().fishTarget ~= nil and type(F().FISH_HOURS) == "table",
            "fishing not coded in production (LK05-T11: LivingKnox.Expeditions.FISH, LivingKnox.Food.fishTarget, "
            .. "LivingKnox.Food.FISH_HOURS)")
        RST.Places.ensure(t0, { name = "house with water within " .. F().CFG.MAX_DIST .. " squares",
            spot = waterSpot, radius = 1500, tries = 12 }, function(t)
        local E = LK()
        t:ok(E.Groups.ensure(), "group registry not ready")
        local home = insideHouse(t)
        local G = E.Groups
        local gid, addMembers = newGroup(t, home, { { "fighter", "guard" }, { "worker", "handyman" },
            { "scout", "scout" }, { "scout", "scout" } }, "RST fishing")
        keepZombiesAway(t, home)
        addMembers()
        local taken, filled = foodShortage(t, gid, home, 4)
        if taken == nil then t:skip(filled) end
        local dawn = F().FISH_HOURS[1]
        getGameTime():setTimeOfDay(dawn + 0.1)
        measure(string.format("fixture: %d food item(s) set aside, %d filler(s), clock set to %.2f", taken, filled,
            dawn + 0.1))
        local before
        K.clearHome(t, home, function(tc)
        tc:waitUntil(function() return bodyCount(gid) == 4 end, BODIES_MS, function(t2)
            t2:ok(type(S().check(gid, { force = true })) == "table", "stock not checked")
            before = homeItems(gid, home)
            t2:ok(G.update(function(d)
                local live = d.groups[gid]
                live.objective = "supply"
                live.members["m-3"].duty = "forager"
                live.members["m-4"].duty = "forager"
                return true, true
            end), "objective and duties not set")
            local trip = X().get(gid)
            if trip == nil then
                local n, why = X().tryDepart(gid, E.Decisions.currentMinute())
                t2:ok(n ~= nil, "no departure: " .. tostring(why))
                trip = X().get(gid)
            end
            t2:eq(X().FISH, trip and trip.kind, "kind of the trip")
            t2:waitUntil(function() return X().get(gid) == nil end, REACH_MS + FORAGE_MS + BACK_MS, function(t3)
                local fish = {}
                for _, ty in ipairs(Fishing and Fishing.fishNet or {}) do fish[ty] = true end
                for _, ty in ipairs(Fishing and Fishing.fishNetWithBait or {}) do fish[ty] = true end
                for _, cfg in ipairs(Fishing and Fishing.fishes or {}) do fish[cfg.itemType] = true end
                local caught, types = 0, {}
                for i, ft in pairs(homeItems(gid, home)) do
                    if before[i] == nil then
                        types[#types + 1] = ft
                        local short = string.gsub(ft, "^Base%.", "")
                        if fish[ft] or fish[short] then caught = caught + 1 end
                    end
                end
                measure(string.format("fishing: %d vanilla fish item(s) stored, new items: %s", caught,
                    table.concat(types, " ")))
                t3:ok(caught >= 1, "no vanilla fish in the home containers after the trip")
                t3:eq(caught, #types, "items brought back that are not vanilla fish")
                local chk = S().check(gid, { force = true })
                t3:eq(0, chk.missing, "missing items at the check after the return")
                t3:eq(0, chk.lost, "items counted as lost")
            end, "fishing trip not closed")
        end, "group members not materialized")
        end)
        end)
    end)
end)
