--[[
lk.care - bleeding and care of Living Knox npcs (LK07-T03, server/LivingKnox/LK_Health.lua section "bleeding",
server/LivingKnox/LK_Care.lua): a wounded member bleeds (reference health lowered every game minute by the authority);
the medic of its group walks to a container of the home, faces it, rummages, takes ONE bandage (removed from the
container and from the clients, removed from the stock reference in the same registry write), walks to the wounded
member, kneels, then the bleeding stops and the health rises once.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player (the test group gets its home on the player's square,
no furnishing: LivingKnox.Homes.skip). Solo: RST.run({ suite = "lk.care", tags = "world" }). Asynchronous run only
(about 1 to 3 minutes). Multiplayer: final session.

What is done:
    - a test group "settlers" (a fighter, a worker, the doctor) is created with its home on the player's square; the
      clock is moved to 6:59 first when it is night or late evening (by day, no sleep);
    - fixture: two bandages (Base.Bandage) are put in the first container of the home (sorted key), marked explored;
      the stock reference is read (LivingKnox.Stock.check);
    - the members get bodies near the player; member m-1 gets a wound of 30 % of its full health (Health.applyHit, the
      path of the hits): it bleeds, its reference health drops over a few game minutes;
    - the doctor treats it: one bandage less in the home containers, its id gone from the reference, bleeding 0,
      health raised, journal entry "care"; a stock check finds no missing item (no loss, no theft).
Every phase prints "[LKC] measure ..." lines; the user checks the gestures (rummage, kneel) on screen. Cleanup
(t:defer): fixture items still in place removed, stock reference erased, bodies removed, test group removed. The clock
is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local measure = K.measurer("[LKC]")

local BODIES_MS = 60000     -- materialization of the three members
local BLEED_MS = 60000      -- the wounded member loses health by bleeding
local CARE_MS = 240000      -- the doctor fetches a bandage and treats the wounded member

local function LK() return LivingKnox end
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

local function homeContainers(gid, home)
    local style, def = LK().Homes.ready(home)
    if style == nil then return nil end
    return S().containers(gid, home, style, def ~= nil and def:getIDString() or nil)
end

-- Bandages (items vanilla accepts for bandaging) in the home containers: set of ids and count.
local function careIds(gid, home)
    local out, n = {}, 0
    for _, ct in ipairs(homeContainers(gid, home) or {}) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            if LK().Care.isCareItem(it) then
                out[it:getID()] = it:getFullType()
                n = n + 1
            end
        end
    end
    return out, n
end

local function careLog(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    for _, e in ipairs(g and g.log or {}) do
        if e.kind == "care" then out[#out + 1] = e.text end
    end
    return out
end

RST.suite("lk.care", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("doctor treats a bleeding member with one real bandage", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Care ~= nil and E.Care.apply ~= nil and E.Health ~= nil and E.Health.bleedPass ~= nil
            and E.Stock ~= nil and E.Homes ~= nil, "LivingKnox care (Care, Health, Stock, Homes) is not loaded")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST care", day = G.today(), home = home }))
        local gid = g.id
        E.Homes.skip(gid)
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

        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        fixtureBox = cts[1].container
        if not fixtureBox:isExplored() then fixtureBox:setExplored(true) end
        for _ = 1, 2 do
            local it = instanceItem("Base.Bandage")
            t:ok(it ~= nil, "item Base.Bandage not created")
            fixtureBox:AddItem(it)
            if isServer() then sendAddItemToContainer(fixtureBox, it) end
            fixture[#fixture + 1] = it
        end
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        local _, nStock = careIds(gid, home)
        measure(string.format("stock of %s: %d bandage(s), %d medical item(s), container %s", gid, nStock,
            r.totals.medical, cts[1].key))

        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "farmer" }, { "medic", "doctor" } }) do
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
            local npcs = memberNpcs(gid)
            local npc = npcs["m-1"]
            local z = E.Bodies.find(npc)
            local full = E.Health.get(npc).max
            local hp = E.Health.applyHit(npc, z, full * 0.3, "Torso_Upper", nil, nil)
            local bleed = E.Health.bleeding(npc)
            measure(string.format("wounded: m-1 %s health %.3f of %.3f, bleeding %.4f per hour, doctor %s", npc,
                hp or -1, full, bleed, tostring(npcs["m-3"])))
            t2:ok(bleed > 0, "the wound does not bleed")
            t2:waitUntil(function()
                local h = E.Health.get(npc)
                return h ~= nil and h.hp < hp - 0.0005
            end, BLEED_MS, function(t3)
                measure(string.format("bleeding: health %.3f (was %.3f)", E.Health.get(npc).hp, hp))
                local before, nBefore = careIds(gid, home)
                local treated = E.Care.stats.treated
                local low = E.Health.get(npc).hp
                t3:waitUntil(function()
                    local h = E.Health.get(npc)
                    if h ~= nil and h.hp < low then low = h.hp end
                    return E.Care.stats.treated > treated
                end, CARE_MS, function(t4)
                    local h = E.Health.get(npc)
                    local after, nAfter = careIds(gid, home)
                    local log = careLog(gid)
                    measure(string.format("treated: health %.3f -> %.3f, bleeding %.4f, bandages %d -> %d, journal %s",
                        low, h.hp, h.bleed, nBefore, nAfter, tostring(log[#log])))
                    t4:eq(0, h.bleed, "bleeding after the care")
                    t4:ok(h.hp > low, "health not raised by the care")
                    t4:eq(nBefore - 1, nAfter, "bandages after the care (exactly one used, none created)")
                    local gone
                    for id in pairs(before) do
                        if after[id] == nil then gone = id end
                    end
                    t4:ok(gone ~= nil, "no bandage left the home containers")
                    for _, e in ipairs(S().reference(gid).items) do
                        t4:ok(e.i ~= gone, "used bandage still in the stock reference")
                    end
                    t4:ok(S().holderOf(gone) == nil, "a player holds the used bandage")
                    t4:ok(#log == 1, "one care entry in the group journal")
                    local c = S().check(gid, { force = true })
                    t4:ok(type(c) == "table", "stock not checked after the care")
                    t4:eq(0, c.missing, "missing items at the check after the care")
                    t4:eq(0, c.lost, "items counted as lost")
                    t4:eq(0, #c.thefts, "thefts counted")
                end, "the wounded member was not treated")
            end, "no health lost by bleeding")
        end, "group members not materialized and standing")
    end)
end)
