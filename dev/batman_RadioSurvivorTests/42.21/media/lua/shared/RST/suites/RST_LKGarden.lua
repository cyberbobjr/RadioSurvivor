--[[
lk.garden - the home garden of a Living Knox gardener (LK15-T04, T05, T06; ADR "registre des routines" D07, D08, Q01):
jobs "seeds" (Jobs/LK_Job_SeedSupply.lua: a packet of LivingKnox.Garden.CFG.SEED_PACKET seeds of a variety in season
put in the home depot when the home holds fewer than SEED_LOW sowable seeds, at most once every SEED_DAYS game days,
for a group with a gardener), "dig" (Jobs/LK_Job_Dig.lua: one furrow on free outdoor dirt of the home area, tall
grass removed first, SFarmingSystem:plow) and "sow" (Jobs/LK_Job_Sow.lua: one seed of the stock in season sown in an
empty furrow, plant:seed(type, 0), the seed removed from its container) of LivingKnox.Upkeep.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player and free outdoor dirt within the home area (the test
group gets its home on the player's square, no furnishing: LivingKnox.Homes.skip). Solo: RST.run({ suite =
"lk.garden", tags = "world" }). Asynchronous run only (about 2 to 6 minutes).

Test "the gardener receives seeds, digs a furrow and sows it" (by day; the clock is moved to 6:59 first when it is
night or late evening):
    - SKIP when no variety of the packets is sown this month (LivingKnox.Garden.seedVariety), when the home area already
      holds MAX_PLOTS plots or an empty furrow, when it has no free outdoor dirt square, or when the home already holds
      SEED_LOW sowable seeds or more;
    - the target player is made untouchable (setGodMod) and vanilla zombies are removed around the home at every poll;
    - a group "settlers" (one fighter, two workers: role "worker" carries the behaviour "garden") gets bodies near
      the player and does its chores;
    - expected: exactly one packet of SEED_PACKET seeds received in the depot container, at least one furrow dug and
      one seed sown (the plant of a dug square is "seeded"), the sowable seeds of the home = before + packet - sown,
      and a stock check finds nothing missing, lost or stolen.
Every phase prints "[LKG] measure ..." lines. Cleanup (t:defer): plants created in the home area removed, seeds of the
packet left in the depot removed, the packet day of the group forgotten, stock reference erased, bodies and test group
removed, the god mode set back. The clock is not set back. Multiplayer: the furrow and the plant seen by both clients
are checked by eye in the MP session (no peer step yet).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local GARDEN_CLEAR_RADIUS = 30   -- squares around the home kept free of vanilla zombies during the jobs
local measure = K.measurer("[LKG]")

local BODIES_MS = 60000     -- materialization of the members
local WORK_MS = 420000      -- seeds received, furrow dug, seed sown (three jobs and a new survey of the home)

local function LK() return LivingKnox end
local function S() return LivingKnox.Stock end
local function U() return LivingKnox.Upkeep end
local function Gd() return LivingKnox.Garden end

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

-- Test group "settlers" with its home on the player's square (no furnishing, players hidden from its perception, no
-- expedition); the members are added by the returned function.
local function newGroup(t, home, specs, name)
    local E, G = LK(), LK().Groups
    local g = assert(G.create({ type = "settlers", name = name, day = G.today(), home = home }))
    local gid = g.id
    E.Homes.skip(gid)
    K.hidePlayersFrom(t, gid)
    local Ex = E.Expeditions
    if Ex ~= nil then
        local depart = Ex.tryDepart
        Ex.tryDepart = function(id, minute)
            if id == gid then return nil, "test group: no expedition" end
            return depart(id, minute)
        end
        t:defer(function() Ex.tryDepart = depart end, "restore the expeditions of group " .. gid)
    end
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

-- Plants of the home area: set of "x,y" keys.
local function plantKeys(area)
    local out = {}
    for _, e in ipairs(area.squares) do
        if Gd().plantAt(e.x, e.y, area.z) ~= nil then out[e.x .. "," .. e.y] = true end
    end
    return out
end

local function itemIds(container)
    local out = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do out[items:get(i):getID()] = true end
    return out
end

RST.suite("lk.garden", { tags = { "world", "server" }, testTimeoutMs = 720000, timeoutMs = 900000 }, function(s)
    s.test("the gardener receives seeds, digs a furrow and sows it", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Upkeep ~= nil and E.Garden ~= nil and E.Garden.receiveSeeds ~= nil
            and E.Upkeep.specs.dig ~= nil and E.Upkeep.specs.sow ~= nil and E.Upkeep.specs.seeds ~= nil,
            "LivingKnox garden jobs (dig, sow, seeds) are not loaded on this side")
        local sys = SFarmingSystem and SFarmingSystem.instance
        t:ok(sys ~= nil, "SFarmingSystem is not loaded on this side (authority only)")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local month = Gd().month()
        local variety = Gd().seedVariety(E.Groups.today(), month)
        if variety == nil then t:skip("no variety of the packets is sown in month " .. tostring(month)) end
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local gid, addMembers = newGroup(t, home, { { "fighter", "guard" }, { "worker", "farmer" },
            { "worker", "handyman" } }, "RST garden")
        K.clearZombiesNear(t, home.x, home.y, home.z, GARDEN_CLEAR_RADIUS)
        local area, why = U().area(gid, E.Groups.get(gid))
        if area == nil then t:skip("home area not ready: " .. tostring(why)) end
        local plots, empty = Gd().plots(area)
        if plots >= Gd().CFG.MAX_PLOTS then t:skip("the home area already holds " .. plots .. " plot(s)") end
        if #empty > 0 then t:skip("an empty furrow already waits in the home area") end
        local spot = Gd().digSpot(area)
        if spot == nil then t:skip("no free outdoor dirt square in the home area") end
        local r, cwhy = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(cwhy))
        local seeds0 = Gd().seedCount(gid, month)
        t:ok(seeds0 ~= nil, "seeds of the home not counted")
        if seeds0 >= Gd().CFG.SEED_LOW then t:skip("the home already holds " .. seeds0 .. " sowable seed(s)") end
        local depot = Gd().depotOf(gid, home)
        t:ok(depot ~= nil, "no depot container in the home")
        local box = depot.container
        if not box:isExplored() then box:setExplored(true) end
        local before, ids = plantKeys(area), itemIds(box)
        t:defer(function()
            for _, e in ipairs(area.squares) do
                local q = Gd().plantAt(e.x, e.y, area.z)
                if q ~= nil and not before[e.x .. "," .. e.y] then sys:removePlant(q) end
            end
            local items = box:getItems()
            for i = items:size() - 1, 0, -1 do
                local it = items:get(i)
                if it ~= nil and not ids[it:getID()] and it:getFullType() == variety.seed then
                    box:DoRemoveItem(it)
                    if isServer() then sendRemoveItemFromContainer(box, it) end
                end
            end
            Gd().state.seedDay[gid] = nil
        end, "remove the plants and the seeds of the test")
        measure(string.format("fixture of %s: month %d, packet %s (%s), dirt %d,%d, %d plot(s), %d sowable seed(s), "
            .. "depot %s", gid, month, variety.seed, variety.typeOfSeed, spot.x, spot.y, plots, seeds0, depot.key))
        local base = {}
        for _, k in ipairs({ "seedPackets", "seedsReceived", "dug", "sown" }) do base[k] = U().stats[k] or 0 end
        local function grew(k) return (U().stats[k] or 0) - base[k] end

        addMembers()
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 18 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        K.clearHome(t, home, function(tc)
            tc:waitUntil(function()
                K.clearZombiesNear(tc, home.x, home.y, home.z, GARDEN_CLEAR_RADIUS)
                return bodyCount(gid) == 3
            end, BODIES_MS, function(t2)
                measure("bodies ready: " .. bodyCount(gid) .. " member(s)")
                t2:waitUntil(function()
                    K.clearZombiesNear(t2, home.x, home.y, home.z, GARDEN_CLEAR_RADIUS)
                    return grew("seedPackets") >= 1 and grew("dug") >= 1 and grew("sown") >= 1
                end, WORK_MS, function(t3)
                    measure(string.format("done: %d packet(s) of %d seed(s), %d furrow(s) dug, %d seed(s) sown",
                        grew("seedPackets"), grew("seedsReceived"), grew("dug"), grew("sown")))
                    t3:eq(1, grew("seedPackets"), "seed packets received")
                    t3:eq(Gd().CFG.SEED_PACKET, grew("seedsReceived"), "seeds of the packet")
                    local seeded = 0
                    for _, e in ipairs(area.squares) do
                        local q = Gd().plantAt(e.x, e.y, area.z)
                        if q ~= nil and not before[e.x .. "," .. e.y] and q.state ~= "plow" and q.typeOfSeed ~= nil then
                            seeded = seeded + 1
                        end
                    end
                    t3:ok(seeded >= 1, "no plant sown on a dug square of the home area")
                    t3:eq(seeds0 + Gd().CFG.SEED_PACKET - grew("sown"), Gd().seedCount(gid, month),
                        "sowable seeds of the home after the packet and the sowing")
                    local c = S().check(gid, { force = true })
                    t3:ok(type(c) == "table", "stock not checked after the garden jobs")
                    t3:eq(0, c.missing, "missing items at the check after the garden jobs")
                    t3:eq(0, c.lost, "items counted as lost")
                    t3:eq(0, #c.thefts, "thefts counted")
                end, "garden jobs not all done (seeds, furrow, sowing)")
            end, "group members not materialized")
        end)
    end)
end)
