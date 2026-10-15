--[[
lk.teamneeds - a high need keeps a forager at home unless the expedition answers it (LK05-T15,
server/LivingKnox/LK_Expeditions.lua Ex.needBlocker and Ex.teamOf). Tags "world" and "server": the authority only, on
a save named rstest*; the suite puts the player inside a house by itself (RST.Places, solo) and gives the test group
its home there; the Living Knox option Enabled on. Solo: RST.run({ suite = "lk.teamneeds", tags = "world" }).
Asynchronous run only (under 1 minute).

What is done (real group, real registry, no expedition started):
    - a test group "settlers" (fighter leader, worker, two scouts) gets its home on the player's square; its members
      get bodies at home;
    - both scouts are made foragers and their gauges are set in the registry: m-3 exhausted (fatigue 95), m-4
      starving (hunger 95), the others low;
    - team asked for an expedition that looks for ammo: neither m-3 nor m-4 is in it;
    - team asked for an expedition that looks for food: m-3 (exhausted) is still kept home, m-4 (starving) may go
      (no blocking need; in the team unless it refuses the order, refusal printed);
    - the decision of m-4 after a scoring pass is printed (it eats at home instead of leaving: measure only).
Figures are printed as "[LKN] measure ..." lines. Cleanup (t:defer): bodies and test group removed, player back.
]]

require "RST/RST"
require "RST/RST_Places"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local Pl = RST.Places
local measure = K.measurer("[LKN]")

local BODIES_MS = 60000

local function LK() return LivingKnox end
local function X() return LivingKnox.Expeditions end

local function memberNpcs(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    if g == nil then return out end
    for mid, m in pairs(g.members) do
        if m.npc ~= nil then out[mid] = m.npc end
    end
    return out
end

local function atHome(gid, home)
    local n = 0
    local r = LK().Decisions.CFG.HOME_RADIUS
    for _, npc in pairs(memberNpcs(gid)) do
        local z = LK().Bodies.find(npc)
        if z == nil or z:isOnFloor() then return false end
        if math.max(math.abs(z:getX() - home.x - 0.5), math.abs(z:getY() - home.y - 0.5)) > r then return false end
        n = n + 1
    end
    return n == 4
end

local function has(list, v)
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

local function houseSpot(p)
    local sq = p:getCurrentSquare()
    if not Pl.inside(sq) then return nil end
    return Pl.freeNear(sq, 3)
end

RST.suite("lk.teamneeds", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 180000 }, function(s)
    s.test("exhausted forager stays home; starving forager leaves only for food", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Expeditions ~= nil and E.Expeditions.needBlocker ~= nil and E.Needs ~= nil,
            "LivingKnox.Expeditions (LK05-T15) is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        Pl.ensure(t, { name = "house (ground floor)", spot = houseSpot }, function(t1, sq)
            local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
            local G = E.Groups
            local g = assert(G.create({ type = "settlers", name = "RST team needs", day = G.today(), home = home }))
            local gid = g.id
            if E.Homes and E.Homes.skip then E.Homes.skip(gid) end
            t1:defer(function()
                local npcs = memberNpcs(gid)
                G.remove(gid)
                for _, npc in pairs(npcs) do
                    E.Directives.forget(npc)
                    E.Bodies.despawn(npc, true)
                end
            end, "remove group " .. gid)
            for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "handyman" }, { "scout", "scout" },
                { "scout", "scout" } }) do
                assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
            end
            assert(G.setLeader(gid, "m-1", G.today()))
            t1:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
            t1:waitUntil(function() return atHome(gid, home) end, BODIES_MS, function(t2)
                local hour = E.Needs.currentHour() or 0
                local function gauges(hunger, thirst, fatigue, fear)
                    return { hunger = hunger, thirst = thirst, fatigue = fatigue, fear = fear, hour = hour }
                end
                -- Duties and gauges set in the same step as the reading: no pass runs in between.
                t2:ok(G.update(function(d)
                    local live = d.groups[gid]
                    live.members["m-3"].duty = "forager"
                    live.members["m-4"].duty = "forager"
                    live.members["m-1"].vitals = gauges(10, 10, 10, 0)
                    live.members["m-2"].vitals = gauges(10, 10, 10, 0)
                    live.members["m-3"].vitals = gauges(10, 10, 95, 0)
                    live.members["m-4"].vitals = gauges(95, 10, 10, 0)
                    return true, true
                end), "duties and gauges not set")
                local live = G.get(gid)
                local D = E.Decisions
                local ammo, food = { { c = "ammo", m = 4 } }, { { c = "food", m = 4 } }
                local b3a = X().needBlocker(D.needsOf(gid, "m-3"), ammo)
                local b4a = X().needBlocker(D.needsOf(gid, "m-4"), ammo)
                local b3f = X().needBlocker(D.needsOf(gid, "m-3"), food)
                local b4f = X().needBlocker(D.needsOf(gid, "m-4"), food)
                local teamA = X().teamOf(live, gid, ammo)
                local teamF = X().teamOf(live, gid, food)
                local refusal = D.refusalFor and D.refusalFor(live.members["m-4"].npc, "expedition") or nil
                measure(string.format("ammo trip: blockers m-3 %s, m-4 %s, team {%s}; food trip: blockers m-3 %s, "
                    .. "m-4 %s, team {%s}; m-4 refusal %s", tostring(b3a), tostring(b4a), table.concat(teamA, " "),
                    tostring(b3f), tostring(b4f), table.concat(teamF, " "), tostring(refusal and refusal.reason)))
                t2:ok(b3a ~= nil and b3f ~= nil, "exhausted m-3 not blocked")
                t2:ok(b4a ~= nil, "starving m-4 not blocked for an ammo trip")
                t2:eq(nil, b4f, "starving m-4 blocked for a food trip")
                t2:eq(false, has(teamA, "m-3") or has(teamF, "m-3"), "exhausted m-3 in a team")
                t2:eq(false, has(teamA, "m-4"), "starving m-4 in the ammo team")
                t2:ok(has(teamF, "m-4") or refusal ~= nil, "starving m-4 neither in the food team nor refusing")
                D.scorePass(nil, nil)
                t2:sleep(2000, function(t3)
                    local st = D.get(live.members["m-4"].npc)
                    measure("m-4 after a scoring pass: " .. tostring(st and st.b) .. " (" .. tostring(st and st.why)
                        .. "), gauges " .. tostring(D.needsOf(gid, "m-4").hunger) .. " hunger")
                    t3:ok(st == nil or st.b ~= "expedition", "starving m-4 left on an expedition")
                end)
            end, "group members not at home and standing")
        end)
    end)
end)
