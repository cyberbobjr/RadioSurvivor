--[[
lk.aid - aid requests to a Living Knox group (LK11-T06, server/LivingKnox/LK_Relations.lua): a player asks a group
for food, water or medical supplies; the group decides on its attitude towards the player and on its real stock
(it never gives what it lacks: LK08-T07 targets), at most one request per group per period; a gift really leaves
the home containers and the stock reference, once, and lands in the player's inventory.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house (the test group gets its home on the player's square). Solo: RST.run({ suite = "lk.aid",
tags = "world" }). Dedicated server: RST.server({ suite = "lk.aid", tags = "world" }) from an admin client standing
in a house.
The request is made with a test player key ("rst-aid-<ms>"; settlers start "favorable") and the player passed as the
recipient: no npc body, no reply line (the context menu and the reply bubble are a manual check, docs/conception/
aide.md).
Cleanup (t:defer): the given item is removed from the player's inventory, the supply targets restored, the stock
reference erased, everything placed removed (LivingKnox.Homes.clear) and the group removed.

What is checked (nominal path):
    - one-member settlers group, home furnished and stock filled (LivingKnox.Homes.check, LivingKnox.Stock.check);
    - request "food": accepted, the item is in the player's inventory (same id), absent from the home containers and
      from the reference, a following stock check finds nothing missing (no loss, no theft); group log entry "aid";
    - second request (any kind) within the period: refused "again", nothing taken;
    - period cleared, medical targets raised above the stock: request "care" refused "short", nothing taken.
Outside the game: tests/test_lk_aid.py (the suite also runs there against doubles).
]]

require "RST/RST"

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Relations is not loaded on an MP client (authority only)")
    end
    local E = LivingKnox
    if E == nil or type(E.Relations) ~= "table" or type(E.Stock) ~= "table" or type(E.Homes) ~= "table" then
        t:skip("LivingKnox.Relations is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

local function realIds(E, gid, home)
    local style, def = E.Homes.ready(home)
    local cts = E.Stock.containers(gid, home, style, def and def:getIDString() or nil)
    local out = {}
    for _, e in ipairs(cts and E.Stock.read(cts) or {}) do out[e.i] = true end
    return out
end

local function inReference(E, gid, id)
    local ref = E.Stock.reference(gid)
    for _, e in ipairs(ref and ref.items or {}) do
        if e.i == id then return true end
    end
    return false
end

local function aidLog(E, gid)
    local n = 0
    for _, e in ipairs(E.Groups.get(gid).log) do
        if e.kind == "aid" then n = n + 1 end
    end
    return n
end

RST.suite("lk.aid", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("aid given once from the stock, period and shortage respected", function(t)
        local E = module(t)
        local R, S, G = E.Relations, E.Stock, E.Groups
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local g = assert(G.create({ type = "settlers", name = "RST aid", day = G.today(), home = home }))
        local gid = g.id
        assert(G.addMember(gid, { role = "worker", day = G.today() }))
        local key = "rst-aid-" .. tostring(getTimestampMs())
        local given
        local medical = S.SUPPLY.PER_MEMBER.medical
        t:defer(function()
            S.SUPPLY.PER_MEMBER.medical = medical
            if given ~= nil then
                local inv = p:getInventory()
                local it = inv:getItemWithIDRecursiv(given)
                if it ~= nil then
                    inv:Remove(it)
                    sendRemoveItemFromContainer(inv, it)
                end
            end
            S.clear(gid)
            E.Homes.clear(gid)
            G.remove(gid)
        end, "remove the given item, the stock reference, the furnishing and group " .. gid)

        local mark, why = E.Homes.check(gid, { force = true })
        t:ok(type(mark) == "table", "home not furnished: " .. tostring(why))
        local r
        r, why = S.check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))
        local before = S.needs(gid)
        t:ok(before ~= nil, "no stock assessment")
        t:note("food " .. tostring(before.have.food) .. " (keep " .. tostring(before.want.food) .. ")")

        -- Food: accepted, item moved from the home to the player's inventory, once.
        local out
        out, why = R.requestAid(gid, key, "food", { player = p })
        t:ok(out ~= nil, "request refused: " .. tostring(why))
        t:eq("given", out.reason, "food request (" .. tostring(out.detail) .. ")")
        t:eq("inventory", out.where, "where the gift went")
        given = out.item.i
        t:ok(p:getInventory():getItemWithIDRecursiv(given) ~= nil, "gift not in the player's inventory")
        t:ok(not realIds(E, gid, home)[given], "gift still in a home container")
        t:ok(not inReference(E, gid, given), "gift still in the stock reference")
        t:eq(before.have.food - 1, S.needs(gid).have.food, "food left in the stock")
        r = S.check(gid, { force = true })
        t:eq(0, r.missing, "items missing at the next check (loss or theft)")
        t:eq(1, aidLog(E, gid), "aid entries in the group log")
        t:note("gave " .. out.item.t .. " (" .. tostring(given) .. ")")

        -- Same period: refused "again", nothing taken.
        local left = S.needs(gid).have.food
        out = R.requestAid(gid, key, "food", { player = p })
        t:eq("again", out.reason, "second request within the period")
        t:eq(left, S.needs(gid).have.food, "food after the second request")

        -- Period cleared, medical targets above the stock: refused "short", nothing taken.
        t:ok(G.update(function(d)
            d.groups[gid].aid = nil
            return true, true
        end), "period mark not cleared")
        S.SUPPLY.PER_MEMBER.medical = 1000
        local care = S.needs(gid).have.medical
        out = R.requestAid(gid, key, "care", { player = p })
        t:eq("short", out.reason, "care request above the stock")
        t:eq(care, S.needs(gid).have.medical, "medical items after the refusal")
        t:eq(2, aidLog(E, gid), "aid entries in the group log after the refusal")
    end)
end)
