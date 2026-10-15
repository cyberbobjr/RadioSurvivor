--[[
lk.offscreen_stock - abstract stock kept consistent with the real containers (LK09-T06,
server/LivingKnox/LK_Stock.lua, called by LK_Simulation): while the group lives offscreen, its daily abstract meal
(Stock.offscreenHour, members at home x ration share) and the loot of an abstract expedition (Stock.offscreenLoot)
change the private reference inventory and leave pending changes; when the home area is readable again (a player
arrives: Stock.check), the pending changes are applied to the real containers (items removed, vanilla items created)
before anything else, then the reference equals the real content.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house (the test group gets its home on the player's square). Solo: RST.run({ suite = "lk.offscreen_stock",
tags = "world" }). Dedicated server: RST.server({ suite = "lk.offscreen_stock", tags = "world" }) from an admin
client standing in a house.
The offscreen hours are not waited for: the two offscreen rules are called directly on the registry (as the
simulation step does), the home staying loaded around the player; the check that follows plays the arrival.
Cleanup (t:defer): the stock reference is erased, everything placed is removed (LivingKnox.Homes.clear, the crate goes
with its content) and the group is removed.

What is checked (nominal path):
    - the home is furnished and its stock filled (LK08-T06);
    - one offscreen meal (4 members) and the loot of one abstract expedition change the reference only: totals as
      expected, changes pending, real containers untouched;
    - the next check (arrival) applies them: no item missing or lost, as many items removed and created as pending,
      created items in the group containers, reference ids = real ids, nothing pending, totals unchanged;
    - no duplicate: a second check and a check after LivingKnox.Stock.reset() (memory lost) create nothing.
Outside the game: tests/test_lk_stock.py (the suite also runs there against doubles).
]]

require "RST/RST"

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Stock is not loaded on an MP client (authority only)")
    end
    local E = LK()
    if E == nil or type(E.Stock) ~= "table" or type(E.Homes) ~= "table" or type(E.Groups) ~= "table"
        or type(E.Stock.offscreenHour) ~= "function" then
        t:skip("LivingKnox.Stock (LK09-T06) is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

local function sortedIds(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.i end
    table.sort(out)
    return table.concat(out, ",")
end

local function realEntries(E, gid, home)
    local style, def = E.Homes.ready(home)
    local cts = E.Stock.containers(gid, home, style, def and def:getIDString() or nil)
    if cts == nil then return {} end
    return E.Stock.read(cts)
end

local function describe(totals)
    local parts = {}
    for _, c in ipairs(LivingKnox.Stock.CATEGORIES) do parts[#parts + 1] = tostring(totals[c]) .. " " .. c end
    return table.concat(parts, ", ")
end

RST.suite("lk.offscreen_stock", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("offscreen meal and loot applied to the home containers on arrival", function(t)
        local E = module(t)
        local S = E.Stock
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST offscreen stock", day = G.today(), home = home }))
        local gid = g.id
        for _, role in ipairs({ "worker", "fighter", "medic", "scout" }) do
            assert(G.addMember(gid, { role = role, day = G.today() }))
        end
        t:defer(function()
            S.clear(gid)
            E.Homes.clear(gid)
            G.remove(gid)
        end, "remove the stock reference, the furnishing and group " .. gid)

        local mark, why = E.Homes.check(gid, { force = true })
        t:ok(type(mark) == "table", "home not furnished: " .. tostring(why))
        local r
        r, why = S.check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        t:eq("filled", r.action, "first check")
        local before = S.reference(gid)
        local realBefore = sortedIds(realEntries(E, gid, home))
        t:note("stock before: " .. describe(before.totals) .. ", ration " .. tostring(S.needs(gid).rationName))

        -- Offscreen: one daily meal and one abstract expedition back with loot, on the registry only.
        local hour = S.OFFSCREEN.MEAL_HOUR - 6
        if hour < 0 then hour = hour + 24 end
        local meal, loot
        t:ok(G.update(function(d)
            local live = d.groups[gid]
            meal = S.offscreenHour(live, gid, hour, G.today())
            loot = S.offscreenLoot(live, gid, { food = 10, medical = 5, ammo = 5 }, G.today())
            return true, true
        end), "registry not written")
        t:ok(meal ~= nil, "no offscreen meal")
        t:eq(4, meal.eaters, "members eating offscreen")
        t:eq(4, loot, "items brought back by the abstract expedition")
        local mid = S.reference(gid)
        t:eq(before.totals.food - meal.food + 2, mid.totals.food, "food in the reference after the offscreen day")
        t:eq(before.totals.water - meal.water, mid.totals.water, "water in the reference after the offscreen day")
        t:eq(before.totals.ammo + 1, mid.totals.ammo, "ammo in the reference after the offscreen day")
        t:eq(meal.food + meal.water + loot, mid.pending, "pending changes")
        t:eq(realBefore, sortedIds(realEntries(E, gid, home)), "real containers untouched before the arrival")
        t:note(string.format("offscreen meal: %d eater(s), ration share %s, food %d, water %d; loot %d item(s)",
            meal.eaters, tostring(meal.portion), meal.food, meal.water, loot))

        -- Arrival: the check applies the pending changes first.
        r, why = S.check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked on arrival: " .. tostring(why))
        t:eq("checked", r.action, "check on arrival")
        t:ok(r.applied ~= nil, "pending changes not applied")
        t:eq(meal.food + meal.water, r.applied.removed, "items removed from the containers")
        t:eq(loot, r.applied.made, "items created in the containers")
        t:eq(0, r.missing, "items missing after the arrival")
        t:eq(0, r.lost, "items lost after the arrival")
        local after = S.reference(gid)
        t:eq(0, after.pending, "changes still pending")
        t:eq(sortedIds(realEntries(E, gid, home)), sortedIds(after.items), "reference ids = real ids")
        t:eq(describe(mid.totals), describe(after.totals), "totals after the arrival")
        t:note("stock after: " .. describe(after.totals))

        -- No duplicate.
        r = S.check(gid, { force = true })
        t:eq(0, r.missing + r.added, "changes found by the second check")
        S.reset()
        r = S.check(gid, { force = true })
        t:eq("checked", r.action, "check after a memory reset")
        t:eq(0, r.missing + r.added, "changes found after a memory reset")
        t:eq(describe(mid.totals), describe(S.reference(gid).totals), "totals after the memory reset")
    end)
end)
