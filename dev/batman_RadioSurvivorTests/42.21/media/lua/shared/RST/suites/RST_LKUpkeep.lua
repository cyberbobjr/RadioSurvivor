--[[
lk.upkeep - home upkeep by Living Knox npcs (LK05-T10, server/LivingKnox/LK_Upkeep.lua, called from LK_Routines.lua
for members whose behaviour is "chore"; materials taken through LivingKnox.Stock.drawFluid / takeItem):
    - a generator of the group (LK05-T19: ModData mark LivingKnox.Homes.GEN_TAG, set here by Homes.markGenerator)
      with little fuel is refuelled from a petrol can of the home stock (exact amount poured),
      and repaired with one electronics scrap of the stock when it is off and worn;
    - blood on a square of the home is cleaned with bleach (ZomboidGlobals.CleanBloodBleachAmount used) when a cleaning
      tool (tag CleanStains) is in the stock;
    - broken glass on a square of the home is removed;
    - a generator without the mark (a player's) next to it, empty and worn, is neither refuelled nor repaired;
    - at night (Upkeep.CFG.LIGHT_FROM .. LIGHT_TO), a member entering a room of the home turns its powered lights on.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player (the test group gets its home on the player's square,
no furnishing: LivingKnox.Homes.skip). Solo: RST.run({ suite = "lk.upkeep", tags = "world" }). Asynchronous run only
(about 2 to 5 minutes). Multiplayer: final session.

Test 1 "home upkeep from the stock" (by day; the clock is moved to 6:59 first when it is night or late evening):
    - fixture: a petrol can holding 4 l of petrol, one electronics scrap, a bleach bottle and a dish cloth in the first
      container of the home (sorted key); a generator (Base.Generator, fuel 2 l, condition 50, not connected, never
      started: no toxic fumes) marked as the group's on a free square of the house; a second one (fuel 0 l, condition
      30, no mark: a player's) on a fourth free square; broken glass on another free square; a blood splat on a
      third one (skipped when the blood decal option is 0);
    - a group "settlers" (one fighter, two workers) gets bodies near the player and does its chores;
    - expected once each: fuel 2 -> 6 l and the can empty, condition 50 -> 54 and the scrap gone, glass gone, blood
      gone and the bleach bottle 0.25 l lighter; the unmarked generator (LK05-T19: never a player's) still at 0 l
      and condition 30, never started; a stock check finds nothing missing, lost or stolen.
Test 2 "lights on entering a powered room at night": SKIP unless the player's room has a light switch that power
    allows to turn on (grid or generator). Its switches are turned off, the clock is moved to 20:00 when it is day, a
    group of two members gets bodies near the player; expected: a member's entry turns lights on (Upkeep.stats.lights)
    and the player's room is lit when a member stands in it.
E01-T16 (LK05-T10): at the end of test 1, every connected client sees the same generators (fuel, condition), no
broken glass and no blood on the fixture squares (step world.upkeep, RST_PeerChecksH.lua; solo: the local player).
Every phase prints "[LKU] measure ..." lines. Cleanup (t:defer): fixture items, generator, glass removed; stock
reference erased; bodies and test group removed; the player's room switches set back. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksH"

local K = RST.LKHelpers
local measure = K.measurer("[LKU]")

local BODIES_MS = 60000     -- materialization of the members
local WORK_MS = 300000      -- every upkeep job done
local LIGHT_MS = 120000     -- lights turned on

local function LK() return LivingKnox end
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

-- Free squares of the player's building around home (same level), nearest first, avoiding the home square itself.
local function freeSquares(home, max)
    local cell = getCell()
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    local bid = hsq:getBuildingDef():getIDString()
    local out = {}
    for r = 1, 5 do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local sq = cell:getGridSquare(home.x + dx, home.y + dy, home.z)
                    if sq ~= nil and sq:getBuildingDef() ~= nil and sq:getBuildingDef():getIDString() == bid
                        and sq:isFree(false) and not sq:HasStairs() and sq:getObjects():size() <= 1 then
                        out[#out + 1] = sq
                        if #out >= max then return out end
                    end
                end
            end
        end
    end
    return out
end

local function newGroup(t, home, specs, name)
    local E, G = LK(), LK().Groups
    local g = assert(G.create({ type = "settlers", name = name, day = G.today(), home = home }))
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
    end, "remove the stock reference, the bodies and group " .. gid)
    return gid, function()
        for _, spec in ipairs(specs) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
    end
end

local function amountOf(it)
    local fc = it ~= nil and it:getFluidContainer() or nil
    return fc ~= nil and fc:getAmount() or 0
end

RST.suite("lk.upkeep", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 1200000 }, function(s)
    s.test("home upkeep from the stock", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Upkeep ~= nil and E.Upkeep.run ~= nil and E.Stock ~= nil and E.Stock.drawFluid ~= nil
            and E.Homes ~= nil, "LivingKnox upkeep (Upkeep, Stock, Homes) is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local gid, addMembers = newGroup(t, home, { { "fighter", "guard" }, { "worker", "handyman" },
            { "worker", "farmer" } }, "RST upkeep")
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        local free = freeSquares(home, 4)
        if #free < 4 then t:skip("fewer than 4 free squares in the house near the player") end

        -- Fixture: materials in the first container of the home.
        local box = cts[1].container
        if not box:isExplored() then box:setExplored(true) end
        local fixture, gen, playerGen, glassSq = {}, nil, nil, free[2]
        t:defer(function()
            for _, it in ipairs(fixture) do
                if box:containsID(it:getID()) then
                    box:DoRemoveItem(it)
                    if isServer() then sendRemoveItemFromContainer(box, it) end
                end
            end
            for _, g in ipairs({ gen, playerGen }) do
                if g ~= nil and g:getObjectIndex() ~= -1 then g:getSquare():transmitRemoveItemFromSquare(g) end
            end
            local glass = glassSq:getBrokenGlass()
            if glass ~= nil then glassSq:transmitRemoveItemFromSquare(glass) end
        end, "remove the fixture items, the generator and the glass")
        local function put(ft, fluid, amount)
            local it = instanceItem(ft)
            t:ok(it ~= nil, "item " .. ft .. " not created")
            if fluid ~= nil then
                it:getFluidContainer():Empty()
                it:getFluidContainer():addFluid(Fluid[fluid], amount)
            end
            box:AddItem(it)
            if isServer() then sendAddItemToContainer(box, it) end
            fixture[#fixture + 1] = it
            return it
        end
        local can = put("Base.PetrolCan", "Petrol", 4)
        local scrap = put("Base.ElectronicsScrap")
        local bleach = put("Base.Bleach", "Bleach", 1)
        put("Base.DishCloth")
        local genItem = instanceItem("Base.Generator")
        t:ok(genItem ~= nil, "generator item not created")
        genItem:setCondition(50)
        genItem:getModData().fuel = 2
        gen = IsoGenerator.new(genItem, getCell(), free[1])
        t:ok(gen ~= nil and not gen:isActivated(), "generator not placed")
        E.Homes.markGenerator(gen, gid)   -- LK05-T19: the group's generator
        local pgItem = instanceItem("Base.Generator")
        t:ok(pgItem ~= nil, "second generator item not created")
        pgItem:setCondition(30)
        pgItem:getModData().fuel = 0
        playerGen = IsoGenerator.new(pgItem, getCell(), free[4])
        t:ok(playerGen ~= nil and not E.Homes.groupGenerator(playerGen, gid), "unmarked generator not placed")
        glassSq:addBrokenGlass()
        t:ok(glassSq:getBrokenGlass() ~= nil, "broken glass not placed")
        local bloodSq = free[3]
        -- Clean slate: blood left in the house by earlier suites (fights of the MP campaign of 2026-10-14) was cleaned
        -- too and counted ("squares cleaned: expected 1, got 2"); only the splat of this fixture is left.
        local Rd = LK().Homes.CFG.RADIUS
        local old, oldGlass = 0, 0
        for dy = -Rd, Rd do
            for dx = -Rd, Rd do
                local bsq = getCell():getGridSquare(home.x + dx, home.y + dy, home.z)
                if bsq ~= nil and bsq:haveBlood() then
                    bsq:removeBlood(false, false)
                    old = old + 1
                end
                -- Same for older broken glass (solo campaign of 2026-10-15, shard2: a window broken by the fights of
                -- lk.forage left glass at 11323,6942; it was removed first, "glass removals" was reached and the
                -- fixture glass was still there).
                local gl = bsq ~= nil and bsq:getBrokenGlass() or nil
                if gl ~= nil and bsq ~= glassSq then
                    bsq:transmitRemoveItemFromSquare(gl)
                    oldGlass = oldGlass + 1
                end
            end
        end
        if old > 0 then measure(old .. " square(s) of older blood cleaned before the fixture") end
        if oldGlass > 0 then measure(oldGlass .. " older broken glass removed before the fixture") end
        bloodSq:getChunk():addBloodSplat(bloodSq:getX() + 0.5, bloodSq:getY() + 0.5, bloodSq:getZ(), 0)
        local blood = bloodSq:haveBlood()
        if not blood then t:note("blood decals are off (option): the cleaning is not checked") end
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        local fuel0, cond0, bleach0 = gen:getFuel(), gen:getCondition(), amountOf(bleach)
        local pFuel0, pCond0 = playerGen:getFuel(), playerGen:getCondition()
        measure(string.format("fixture of %s in %s: generator %d,%d fuel %.2f condition %d, glass %d,%d, blood %d,%d "
            .. "(%s), petrol %.2f l, bleach %.2f l, unmarked generator %d,%d fuel %.2f condition %d", gid, cts[1].key,
            free[1]:getX(), free[1]:getY(), fuel0, cond0, glassSq:getX(), glassSq:getY(), bloodSq:getX(), bloodSq:getY(),
            tostring(blood), amountOf(can), bleach0, free[4]:getX(), free[4]:getY(), pFuel0, pCond0))
        local base = {}
        for k, v in pairs(U().stats) do base[k] = v end

        addMembers()
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 18 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        t:waitUntil(function()
            local now = getGameTime():getTimeOfDay()
            return bodyCount(gid) == 3 and allStanding(gid) and now >= 7 and now < 21.5
        end, BODIES_MS, function(t2)
            measure("bodies ready: " .. bodyCount(gid) .. " member(s)")
            local function grew(k) return U().stats[k] - base[k] end
            t2:waitUntil(function()
                return grew("refuels") >= 1 and grew("repairs") >= 1 and grew("glass") >= 1
                    and glassSq:getBrokenGlass() == nil and (not blood or grew("cleaned") >= 1)
            end, WORK_MS, function(t3)
                measure(string.format("done: fuel %.2f -> %.2f, can %.2f l, condition %d -> %d, glass %s, blood %s, "
                    .. "bleach %.3f -> %.3f l", fuel0, gen:getFuel(), amountOf(can), cond0, gen:getCondition(),
                    tostring(glassSq:getBrokenGlass() ~= nil), tostring(bloodSq:haveBlood()), bleach0,
                    amountOf(bleach)))
                t3:eq(1, grew("refuels"), "refuels")
                t3:eq(1, grew("repairs"), "repairs (one scrap in the stock)")
                t3:eq(1, grew("glass"), "glass removals")
                t3:ok(math.abs(gen:getFuel() - (fuel0 + 4)) < 0.01, "generator fuel not raised by the 4 l poured")
                t3:ok(amountOf(can) < 0.001, "petrol can not emptied")
                t3:eq(cond0 + U().CFG.REPAIR_STEP, gen:getCondition(), "generator condition after one repair")
                t3:ok(not box:containsID(scrap:getID()), "electronics scrap still in the container")
                t3:ok(glassSq:getBrokenGlass() == nil, "broken glass still there")
                if blood then
                    t3:eq(1, grew("cleaned"), "squares cleaned")
                    t3:ok(not bloodSq:haveBlood(), "blood still there")
                    local used = ZomboidGlobals.CleanBloodBleachAmount
                    t3:ok(math.abs(bleach0 - amountOf(bleach) - used) < 0.001, "bleach not lowered by exactly " .. used)
                end
                t3:ok(not gen:isActivated(), "generator started by the upkeep")
                measure(string.format("unmarked generator: fuel %.2f -> %.2f, condition %d -> %d", pFuel0,
                    playerGen:getFuel(), pCond0, playerGen:getCondition()))
                t3:ok(math.abs(playerGen:getFuel() - pFuel0) < 0.001, "unmarked generator refuelled")
                t3:eq(pCond0, playerGen:getCondition(), "unmarked generator condition")
                t3:ok(not playerGen:isActivated(), "unmarked generator started by the upkeep")
                local c = S().check(gid, { force = true })
                t3:ok(type(c) == "table", "stock not checked after the upkeep")
                t3:eq(0, c.missing, "missing items at the check after the upkeep")
                t3:eq(0, c.lost, "items counted as lost")
                t3:eq(0, #c.thefts, "thefts counted")
                -- LK05-T10 (E01-T16): every connected client sees the effects once: both generators with the fuel
                -- and condition of the authority, no glass and no blood left (world.upkeep, RST_PeerChecksH.lua).
                local function genOf(g)
                    local gs = g:getSquare()
                    return { x = gs:getX(), y = gs:getY(), z = gs:getZ(), fuel = g:getFuel(), cond = g:getCondition() }
                end
                local clean = { { x = glassSq:getX(), y = glassSq:getY(), z = glassSq:getZ() } }
                if blood then clean[2] = { x = bloodSq:getX(), y = bloodSq:getY(), z = bloodSq:getZ() } end
                RST.Steps.ask(t3, "world.upkeep", { gens = { genOf(gen), genOf(playerGen) }, clean = clean },
                    { target = "all", timeoutMs = 15000 })
            end, "upkeep jobs not all done")
        end, "group members not materialized and standing")
    end)

    s.test("lights on entering a powered room at night", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Upkeep ~= nil and E.Upkeep.lights ~= nil, "LivingKnox upkeep is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil or sq:getRoom() == nil then
            t:skip("the player must stand inside a room of a house")
        end
        local room = sq:getRoom()
        local list = room:getLightSwitches()
        local switches, before = {}, {}
        for i = 0, list:size() - 1 do
            local ls = list:get(i)
            if not (ls:getCanBeModified() and ls:getUseBattery()) and ls:canSwitchLight() then
                switches[#switches + 1] = ls
                before[#switches] = ls:isActivated()
            end
        end
        if #switches == 0 then t:skip("no light switch that power allows to turn on in the player's room") end
        t:defer(function()
            for i, ls in ipairs(switches) do
                if ls:getObjectIndex() ~= -1 and ls:isActivated() ~= before[i] then ls:setActive(before[i]) end
            end
        end, "light switches of the player's room set back")
        for _, ls in ipairs(switches) do ls:setActive(false) end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local gid, addMembers = newGroup(t, home, { { "worker", "handyman" }, { "worker", "farmer" } }, "RST lights")
        local tod = getGameTime():getTimeOfDay()
        if not U().dark(math.floor(tod)) then
            getGameTime():setTimeOfDay(20.0)
            measure(string.format("time of day %.2f: clock set to 20:00", tod))
        end
        U().state.rooms = {}
        local base = U().stats.lights
        addMembers()
        measure(string.format("room of the player: %d switch(es) turned off, group %s", #switches, gid))
        t:waitUntil(function() return U().stats.lights > base end, LIGHT_MS, function(t2)
            local inRoom = false
            for _, npc in pairs(memberNpcs(gid)) do
                local z = E.Bodies.find(npc)
                local zsq = z ~= nil and z:getCurrentSquare() or nil
                if zsq ~= nil and zsq:getRoom() == room then inRoom = true end
            end
            local lit = 0
            for _, ls in ipairs(switches) do
                if ls:isActivated() then lit = lit + 1 end
            end
            measure(string.format("lights: %d switch(es) turned on by members, player's room %d/%d lit, member in "
                .. "it %s", U().stats.lights - base, lit, #switches, tostring(inRoom)))
            if inRoom then t2:eq(#switches, lit, "switches of the player's room lit while a member stands in it") end
        end, "no light turned on by a member entering a room")
    end)
end)
