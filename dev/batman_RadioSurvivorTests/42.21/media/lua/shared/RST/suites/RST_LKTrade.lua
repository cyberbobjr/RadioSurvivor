--[[
lk.trade - direct trade with a friendly Living Knox group (LK11-T08, server/LivingKnox/LK_Trade.lua): a player gives
items of his inventory for items of the group's real stock; the server values both sides with the shared table
(shared/RadioSurvivor/RS_TradeValues.lua), the group's needs and its attitude, then moves every item once (player's
items into the group's crate, the group's items into the player's inventory) and brings the stock reference up to
date.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
INSIDE a house (the test group gets its home on the player's square). Solo: RST.run({ suite = "lk.trade",
tags = "world" }). Dedicated server: RST.server({ suite = "lk.trade", tags = "world" }) from an admin client standing
in a house.
The trade is made with a test player key ("rst-trade-<ms>"; settlers start "favorable") and three batteries created
in the player's inventory: no npc body, no window (the context menu, the window and the reply bubble are a manual
check, docs/conception/troc.md).
Cleanup (t:defer): items still in the player's inventory from the test are removed, the stock reference erased,
everything placed removed (LivingKnox.Homes.clear, crate content included) and the group removed.

What is checked (nominal path):
    - one-member settlers group, home furnished and stock filled (LivingKnox.Homes.check, LivingKnox.Stock.check);
    - offer: the three batteries are wanted, the group offers its surplus only;
    - three batteries for up to two items of the same cheap kind: accepted, the received items are in the player's
      inventory (same ids) and nowhere in the home, the batteries are in a home container and no longer in the
      inventory, the received items left the reference, a following stock check finds nothing missing (no loss, no
      theft); one "trade" entry in the group log;
    - the same proposal again: refused "gone", nothing moves.
Outside the game: tests/test_lk_trade.py (the suite also runs there against doubles).
]]

require "RST/RST"

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Trade is not loaded on an MP client (authority only)")
    end
    local E = LivingKnox
    if E == nil or type(E.Trade) ~= "table" or type(E.Stock) ~= "table" or type(E.Homes) ~= "table" then
        t:skip("LivingKnox.Trade is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

-- Number of items of id in the home containers (any category).
local function inHome(E, gid, home, id)
    local style, def = E.Homes.ready(home)
    local cts = E.Stock.containers(gid, home, style, def and def:getIDString() or nil)
    local n = 0
    for _, ct in ipairs(cts or {}) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            if items:get(j):getID() == id then n = n + 1 end
        end
    end
    return n
end

local function inReference(E, gid, id)
    local ref = E.Stock.reference(gid)
    for _, e in ipairs(ref and ref.items or {}) do
        if e.i == id then return true end
    end
    return false
end

local function tradeLog(E, gid)
    local n = 0
    for _, e in ipairs(E.Groups.get(gid).log) do
        if e.kind == "trade" then n = n + 1 end
    end
    return n
end

RST.suite("lk.trade", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("trade moves each item once, the group keeps its reserves", function(t)
        local E = module(t)
        local T, S, G = E.Trade, E.Stock, E.Groups
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local g = assert(G.create({ type = "settlers", name = "RST trade", day = G.today(), home = home }))
        local gid = g.id
        assert(G.addMember(gid, { role = "worker", day = G.today() }))
        local key = "rst-trade-" .. tostring(getTimestampMs())
        local mine = {}
        t:defer(function()
            local inv = p:getInventory()
            for _, id in ipairs(mine) do
                local it = inv:getItemWithIDRecursiv(id)
                if it ~= nil then
                    inv:DoRemoveItem(it)
                    sendRemoveItemFromContainer(inv, it)
                end
            end
            S.clear(gid)
            E.Homes.clear(gid)
            G.remove(gid)
        end, "remove the test items, the stock reference, the furnishing and group " .. gid)

        local mark, why = E.Homes.check(gid, { force = true })
        t:ok(type(mark) == "table", "home not furnished: " .. tostring(why))
        local r
        r, why = S.check(gid, { force = true })
        t:ok(type(r) == "table", "stock not checked: " .. tostring(why))

        local inv = p:getInventory()
        local batteries = {}
        for _ = 1, 3 do
            local it = instanceItem("Base.Battery")
            inv:AddItem(it)
            if isServer() then sendAddItemToContainer(inv, it) end
            batteries[#batteries + 1] = it:getID()
            mine[#mine + 1] = it:getID()
        end

        -- Offer: the batteries are wanted; pick up to two cheap items of the same kind.
        local offer
        offer, why = T.offer(gid, key, p)
        t:ok(offer ~= nil, "no offer: " .. tostring(why))
        local wanted = 0
        for _, e in ipairs(offer.give) do
            if e.t == "Base.Battery" then wanted = wanted + 1 end
        end
        t:eq(3, wanted, "batteries the group would take")
        local take, kind = {}, nil
        for _, e in ipairs(offer.take) do
            if e.v <= 2 and (kind == nil or e.t == kind) and #take < 2 then
                kind = e.t
                take[#take + 1] = e.i
            end
        end
        t:ok(#take > 0, "the group offers nothing cheap")
        t:note("asking " .. tostring(#take) .. " x " .. tostring(kind))
        for _, id in ipairs(take) do mine[#mine + 1] = id end

        local out = T.propose(gid, key, p, batteries, take)
        t:eq("done", out.reason, "trade (" .. tostring(out.detail) .. ")")
        for _, id in ipairs(take) do
            t:ok(inv:getItemWithIDRecursiv(id) ~= nil, "received item not in the player's inventory")
            t:eq(0, inHome(E, gid, home, id), "received item still in a home container")
            t:ok(not inReference(E, gid, id), "received item still in the stock reference")
        end
        for _, id in ipairs(batteries) do
            t:ok(inv:getItemWithIDRecursiv(id) == nil, "battery still in the player's inventory")
            t:eq(1, inHome(E, gid, home, id), "battery copies in the home containers")
        end
        r = S.check(gid, { force = true })
        t:eq(0, r.missing, "items missing at the next check (loss or theft)")
        t:eq(1, tradeLog(E, gid), "trade entries in the group log")
        t:note("gave " .. tostring(out.given) .. " for " .. tostring(out.asked))

        -- Same proposal again: refused "gone", nothing moves.
        out = T.propose(gid, key, p, batteries, take)
        t:eq("gone", out.reason, "same proposal again")
        t:eq(1, tradeLog(E, gid), "trade entries after the second proposal")
    end)
end)
