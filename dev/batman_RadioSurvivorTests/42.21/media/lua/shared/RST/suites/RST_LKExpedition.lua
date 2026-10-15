--[[
lk.expedition - physical expedition of Living Knox foragers and their return home (LK05-T05,
server/LivingKnox/LK_Expeditions.lua, behaviour "expedition" of LK_Decisions.lua): two foragers walk from their home
to a nearby building picked by the authority from what the home stock lacks, search its containers (real items of
the missing categories taken out, bounded load), walk back and unload into a home container; the items are the same
objects (ids), added to the stock reference, no loss and no theft at the next stock check.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house (the test home, on the player's square, no furnishing: LivingKnox.Homes.skip) with ANOTHER building
with containers 6 to 45 squares away (Expeditions.CFG.MIN_DIST..MAX_DIST). Solo:
RST.run({ suite = "lk.expedition", tags = "world" }). Asynchronous run only (about 2 to 6 minutes). Stay near the
house during the run (bodies far from every player are taken out of the world: the trip would go offscreen).
Multiplayer: final session.

What is done:
    - a test group "settlers" (fighter leader, worker, two scouts) is created with its home on the player's square;
      the clock is moved to 9:00 when the hour of day is outside the departure window (7 h - 16 h);
    - the members get bodies near the player; the stock reference is read (LivingKnox.Stock.check); the group is set
      to objective "supply" with both scouts as foragers (fixture: the house may not lack anything by itself) and the
      departure is asked (LivingKnox.Expeditions.tryDepart);
    - the team reaches the building (phase search), searches and starts back (phase back), unloads at home (trip
      closed, journal "return");
    - the carried items (ids recorded in the trip before the return) are in the home containers and in the stock
      reference; a stock check finds no missing item, no loss, no theft.
Every phase prints "[LKX] measure ..." lines; the user checks the walk, the rummaging and the return on screen.
Cleanup (t:defer): trip cancelled, stock reference erased, bodies removed, test group removed. The items brought back
stay in the house; the clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local measure = K.measurer("[LKX]")

local BODIES_MS = 60000     -- materialization of the four members
local REACH_MS = 180000     -- the team reaches the building
local SEARCH_MS = 180000    -- the team has searched and starts back
local BACK_MS = 240000      -- the team is home and has unloaded

local function LK() return LivingKnox end
local function X() return LivingKnox.Expeditions end
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

local function phaseOf(gid)
    local t = X().get(gid)
    return t and t.phase or nil
end

local function homeIds(gid, home)
    local style, def = LK().Homes.ready(home)
    if style == nil then return nil end
    local out = {}
    for _, e in ipairs(S().read(S().containers(gid, home, style, def ~= nil and def:getIDString() or nil) or {})) do
        out[e.i] = e.t
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

RST.suite("lk.expedition", { tags = { "world", "server" }, testTimeoutMs = 900000, timeoutMs = 1200000 },
    function(s)
    s.test("foragers search a nearby building and bring real items home", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Expeditions ~= nil and E.Expeditions.tryDepart ~= nil and E.Stock ~= nil
            and E.Homes ~= nil and E.Decisions ~= nil, "LivingKnox expeditions (Expeditions, Stock, Homes) not loaded")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST expedition", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)   -- no furnishing (LK08-T04) on the test site
        K.hidePlayersFrom(t, gid)   -- the players stand in the home: unknown, they are intruders (campaign MP 2026-10-15:
        -- alert "intruder rs_mp1", the members watched him instead of their duties)
        t:defer(function()
            X().cancel(gid, "test cleanup")
            S().clear(gid)
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "cancel the trip, remove the stock reference, the bodies and group " .. gid)
        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "handyman" }, { "scout", "scout" },
            { "scout", "scout" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        local tod = getGameTime():getTimeOfDay()
        local c = X().CFG
        if tod < c.DEPART_FROM or tod >= c.DEPART_TO - 1 then
            getGameTime():setTimeOfDay(9)
            measure(string.format("time of day %.2f: clock set to 9:00 first", tod))
        end
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        -- Dedicated server: the players leave the house (solid; campaign MP 2026-10-15: npcs stuck against them).
        K.clearHome(t, home, function(tc)
        tc:waitUntil(function() return bodyCount(gid) == 4 end, BODIES_MS, function(t2)
            local r, why = S().check(gid, { force = true })
            t2:ok(type(r) == "table", "stock not checked: " .. tostring(why))
            t2:ok(G.update(function(d)
                local live = d.groups[gid]
                live.objective = "supply"
                live.members["m-3"].duty = "forager"
                live.members["m-4"].duty = "forager"
                return true, true
            end), "objective and duties not set")
            local trip = X().get(gid)   -- the minute pass may already have sent the team
            local n = trip and trip.n or nil
            if n == nil then
                if X().wantOf(gid) == nil then t2:skip("the home stock lacks nothing for four members") end
                local dwhy
                n, dwhy = X().tryDepart(gid, E.Decisions.currentMinute())
                if n == nil then t2:skip("no departure: " .. tostring(dwhy)) end
                trip = X().get(gid)
            end
            measure(string.format("departure: trip %d to building %s %s at %d,%d,%d, team %s, load %d", n,
                trip.target.b, tostring(trip.target.label), trip.target.x, trip.target.y, trip.target.z,
                table.concat(trip.team, " "), trip.cap))
            t2:eq(2, #trip.team, "team size")
            t2:waitUntil(function() return phaseOf(gid) ~= "out" end, REACH_MS, function(t3)
                measure(string.format("reached: phase %s; %s; %s", tostring(phaseOf(gid)), bodyText(gid, "m-3"),
                    bodyText(gid, "m-4")))
                t3:ok(phaseOf(gid) == "search" or phaseOf(gid) == "back", "team did not start searching")
                local carried = {}
                t3:waitUntil(function()
                    local cur = X().get(gid)
                    if cur ~= nil then
                        for _, e in ipairs(cur.carry) do
                            if e.i ~= nil then carried[e.i] = e.t end
                        end
                    end
                    return cur == nil or cur.phase == "back" or cur.phase == "deliver"
                end, SEARCH_MS, function(t4)
                    local cur = X().get(gid)
                    local n2 = 0
                    for _ in pairs(carried) do n2 = n2 + 1 end
                    measure(string.format("searched: %d item(s) carried, %d container(s) searched; %s; %s", n2,
                        cur and #cur.searched or -1, bodyText(gid, "m-3"), bodyText(gid, "m-4")))
                    t4:ok(cur == nil or #cur.searched > 0, "no container searched")
                    t4:waitUntil(function() return X().get(gid) == nil end, BACK_MS, function(t5)
                        local ids = homeIds(gid, home) or {}
                        local ref = {}
                        local reference = S().reference(gid)
                        for _, e in ipairs(reference and reference.items or {}) do ref[e.i] = true end
                        local inHome, inRef = 0, 0
                        for i in pairs(carried) do
                            if ids[i] ~= nil then inHome = inHome + 1 end
                            if ref[i] then inRef = inRef + 1 end
                        end
                        local back = {}
                        for _, e in ipairs(G.get(gid).log) do
                            if e.kind == "return" then back[#back + 1] = e.text end
                        end
                        measure(string.format("home: %d of %d carried item(s) in the home containers, %d in the "
                            .. "reference; journal: %s", inHome, n2, inRef, table.concat(back, " / ")))
                        t5:eq(n2, inHome, "carried items found in the home containers")
                        t5:eq(n2, inRef, "carried items in the stock reference")
                        t5:eq(1, #back, "return entries in the group journal")
                        local chk = S().check(gid, { force = true })
                        t5:ok(type(chk) == "table", "stock not checked after the return")
                        t5:eq(0, chk.missing, "missing items at the check after the return")
                        t5:eq(0, chk.lost, "items counted as lost")
                        t5:eq(0, #chk.thefts, "thefts counted")
                        for i in pairs(carried) do
                            t5:ok(S().holderOf(i) == nil, "a player holds a carried item")
                        end
                    end, "team not back home (trip not closed)")
                end, "team did not finish its search")
            end, "team did not reach the building")
        end, "group members not materialized")
        end)
    end)
end)
