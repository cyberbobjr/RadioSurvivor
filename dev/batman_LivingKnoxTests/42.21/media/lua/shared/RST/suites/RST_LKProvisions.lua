--[[
lk.provisions - provisions carried by Living Knox npcs and their never emptied canteen (LK05-T20,
server/LivingKnox/LK_Provisions.lua and LK_ProvisionMeal.lua, extension "provision" of LK_Decisions.lua): every body
gets real non perishable food items (LivingKnox.Provisions.CFG.COUNT) and a full canteen with its loot; away from home a
hungry member eats one provision where it stands (one item less in its body inventory, hunger lowered once by
Needs.CFG.MEAL), a thirsty one drinks from its canteen (thirst lowered by Needs.CFG.DRINK, canteen content unchanged);
back home, the missing provision is replaced from the home stock (one item less in the home containers, its id gone
from the stock reference, nothing created).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house that has at least one container near the player (the test group gets its home on the player's square,
no furnishing: LivingKnox.Homes.skip). Solo: RST.run({ suite = "lk.provisions", tags = "world" }). Asynchronous run
only (about 2 to 4 minutes). The fight case (disengage, eat sitting, fight again) is proven by the bench only
(tests/livingknox/test_lk_provisions.py): this suite removes the zombies.

What is done:
    - the target player is made untouchable (setGodMod) and vanilla zombies are removed around the home at every poll;
    - a test group "settlers" (one fighter, two workers) is created with its home on the player's square, the players
      hidden from its perception; the clock is moved to 6:59 first when it is night or late evening;
    - fixture: two cans of beans in the first container of the home (sorted key), marked explored; stock reference read;
    - the members get bodies; once m-2 was evaluated and its loot built: it carries COUNT provisions and a canteen;
    - "away": the home radius of the decisions (LivingKnox.Decisions.CFG.HOME_RADIUS) is set to -1 for the scene, so
      every member is away from home where it stands; m-2 gets hunger 95 and thirst 95: it eats one provision (one
      less, hunger lowered once), then drinks (thirst lowered, canteen unchanged);
    - "home": the radius is set back; m-2 is home with one provision missing: it takes one from the home stock.
Every phase prints "[LKP] measure ..." lines. Cleanup (t:defer): home radius and god mode restored, fixture items still
in place removed, stock reference erased, bodies removed, test group removed. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local CLEAR_RADIUS = 30      -- squares around the home cleared of vanilla zombies at every poll
local UNLOCK_RADIUS = 12     -- squares around the home whose locked doors and windows are unlocked
local measure = K.measurer("[LKP]")

local BODIES_MS = 60000      -- materialization of the three members and loot of m-2
local EAT_MS = 120000        -- eating sitting (game minutes of ProvisionMeal.CFG.EAT_MINUTES) after a decision
local DRINK_MS = 90000       -- drinking (ProvisionMeal.CFG.DRINK_MINUTES)
local REFILL_MS = 60000      -- replaced at home (decision passes, Provisions.CFG.REFILL_MINUTES between tries)
local HOUR_GROWTH = 7        -- gauge gained if an hour step falls in the scene (Needs.CFG.RATES, at most)

local function LK() return LivingKnox end
local function S() return LivingKnox.Stock end
local function P() return LivingKnox.Provisions end

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

local function bodyOf(gid, mid)
    local npc = memberNpcs(gid)[mid]
    return npc ~= nil and LK().Bodies.find(npc) or nil, npc
end

-- Evaluated once by the decision frame (the needs of the scene are set only after that, lesson of lk.meals) and loot
-- built (provisions given).
local function ready(gid, mid)
    local z, npc = bodyOf(gid, mid)
    return z ~= nil and LK().Decisions.get(npc) ~= nil and z:getModData()[LK().Loot.MD_BUILT] ~= nil
end

local function homeContainers(gid, home)
    local style, def = LK().Homes.ready(home)
    if style == nil then return nil end
    return S().containers(gid, home, style, def ~= nil and def:getIDString() or nil)
end

-- Provision items (Provisions.isProvision) in the home containers: set of ids and count.
local function homeProvisions(gid, home)
    local out, n = {}, 0
    for _, ct in ipairs(homeContainers(gid, home) or {}) do
        local items = ct.container:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if P().isProvision(it) then
                out[it:getID()] = it:getFullType()
                n = n + 1
            end
        end
    end
    return out, n
end

local function gauges(gid, mid)
    local v = LK().Needs.get(gid, mid)
    return v and v.hunger or nil, v and v.thirst or nil
end

local function canteenAmount(z)
    local _, _, c = P().carried(z)
    local fc = c ~= nil and c:getFluidContainer() or nil
    return fc ~= nil and fc:getAmount() or nil
end

local function setNeeds(t, gid, mid, hunger, thirst)
    local hour = LK().Needs.currentHour() or 0
    t:ok(LK().Groups.update(function(d)
        local m = d.groups[gid].members[mid]
        m.vitals = { hunger = hunger, thirst = thirst, fatigue = 20, fear = 0, hour = hour }
        return true, true
    end), "needs not set")
end

RST.suite("lk.provisions", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("provisions carried, eaten away from home, canteen never emptied, replaced at home", function(t)
        if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
        local E = LK()
        t:ok(E ~= nil and E.Provisions ~= nil and E.ProvisionMeal ~= nil and E.Stock ~= nil and E.Needs ~= nil
            and E.Homes ~= nil and E.Loot ~= nil, "LivingKnox provisions (Provisions, ProvisionMeal, Stock, Needs, "
            .. "Homes, Loot) are not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local radius = E.Decisions.CFG.HOME_RADIUS
        t:defer(function() E.Decisions.CFG.HOME_RADIUS = radius end, "restore the home radius of the decisions")
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST provisions", day = G.today(), home = home }))
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
        local function clear(tt)
            K.clearZombiesNear(tt, home.x, home.y, home.z, CLEAR_RADIUS)
        end
        clear(t)

        -- Fixture: two cans of beans in the first container of the home.
        local cts = homeContainers(gid, home)
        if cts == nil or #cts == 0 then t:skip("no container in the house around the player") end
        fixtureBox = cts[1].container
        if not fixtureBox:isExplored() then fixtureBox:setExplored(true) end
        for _ = 1, 2 do
            local it = instanceItem("Base.TinnedBeans")
            t:ok(it ~= nil, "item Base.TinnedBeans not created")
            fixtureBox:AddItem(it)
            if isServer() then sendAddItemToContainer(fixtureBox, it) end
            fixture[#fixture + 1] = it
        end
        local r, why = S().check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))

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
        local unlocked = K.unlockDoorsNear(t, sq, UNLOCK_RADIUS)
        if unlocked > 0 then t:note(unlocked .. " locked door(s) or window(s) of the house unlocked") end
        t:waitUntil(function()
            clear(t)
            local now = getGameTime():getTimeOfDay()
            return bodyCount(gid) == 3 and now >= 7 and now < 21.5 and ready(gid, "m-2")
        end, BODIES_MS, function(t2)
            local Ex = E.Expeditions
            if Ex ~= nil and Ex.cancel ~= nil and Ex.cancel(gid, "suite lk.provisions") then
                t2:note("expedition of " .. gid .. " cancelled before the scene")
            end
            local z, npc = bodyOf(gid, "m-2")
            local count = P().CFG.COUNT
            local carried = P().carried(z)
            local water = canteenAmount(z)
            measure(string.format("carried: m-2 %s %d provision(s), canteen %s l", npc, carried, tostring(water)))
            t2:eq(count, carried, "provisions carried after the loot")
            t2:ok(water ~= nil and water > 0, "no canteen with water carried")

            -- Away from home where it stands: hunger and thirst.
            E.Decisions.CFG.HOME_RADIUS = -1
            setNeeds(t2, gid, "m-2", 95, 95)
            local h0, th0 = gauges(gid, "m-2")
            local meal, drink = E.Needs.CFG.MEAL, E.Needs.CFG.DRINK
            local seen = false
            t2:waitUntil(function()
                clear(t2)
                local st = E.Decisions.get(npc)
                if st ~= nil and st.b == "provision" then seen = true end
                local h = gauges(gid, "m-2")
                return h ~= nil and h <= h0 - meal + HOUR_GROWTH
            end, EAT_MS, function(t3)
                local h = gauges(gid, "m-2")
                local left = P().carried(bodyOf(gid, "m-2"))
                measure(string.format("eaten away: hunger %d -> %d, provisions %d -> %d, behaviour seen %s", h0, h,
                    carried, left, tostring(seen)))
                t3:ok(seen, "behaviour provision never seen")
                t3:eq(carried - 1, left, "provisions after the meal (exactly one eaten)")
                t3:ok(h0 - h >= meal - HOUR_GROWTH and h0 - h <= meal + 2, "hunger not lowered once by the meal")
                t3:waitUntil(function()
                    clear(t3)
                    local _, th = gauges(gid, "m-2")
                    return th ~= nil and th <= th0 - drink + HOUR_GROWTH
                end, DRINK_MS, function(t4)
                    local _, th = gauges(gid, "m-2")
                    local after = canteenAmount(bodyOf(gid, "m-2"))
                    measure(string.format("drunk away: thirst %d -> %d, canteen %s -> %s l", th0, th, tostring(water),
                        tostring(after)))
                    t4:eq(water, after, "canteen content after drinking")
                    t4:eq(carried - 1, P().carried(bodyOf(gid, "m-2")), "provisions after drinking")

                    -- Home again: the missing provision comes from the home stock.
                    E.Decisions.CFG.HOME_RADIUS = radius
                    local before, nBefore = homeProvisions(gid, home)
                    t4:waitUntil(function()
                        clear(t4)
                        return P().carried(bodyOf(gid, "m-2")) >= count
                    end, REFILL_MS, function(t5)
                        local after2, nAfter = homeProvisions(gid, home)
                        measure(string.format("replaced at home: provisions %d, provisions in the home %d -> %d",
                            P().carried(bodyOf(gid, "m-2")), nBefore, nAfter))
                        t5:eq(nBefore - 1, nAfter, "provisions in the home containers (exactly one taken)")
                        local taken
                        for id in pairs(before) do
                            if after2[id] == nil then taken = id end
                        end
                        t5:ok(taken ~= nil, "no item of the home taken")
                        for _, e in ipairs(S().reference(gid).items) do
                            t5:ok(e.i ~= taken, "taken item still in the stock reference")
                        end
                        local c = S().check(gid, { force = true })
                        t5:ok(type(c) == "table", "stock not checked after the refill")
                        t5:eq(0, c.lost, "items counted as lost")
                        t5:eq(0, #c.thefts, "thefts counted")
                    end, "provision not replaced at home")
                end, "member did not drink (thirst not lowered)")
            end, "member did not eat a provision (hunger not lowered)")
        end, "group members not materialized, evaluated and given their loot")
    end)
end)
