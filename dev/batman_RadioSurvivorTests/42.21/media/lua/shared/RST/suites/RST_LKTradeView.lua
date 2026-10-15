--[[
lk.tradeview - direct trade with a friendly Living Knox group through the Trade menu of two real clients (LK11-T08,
E01-T16; server/LivingKnox/LK_Trade.lua, client/LivingKnox/LK_TradeView.lua). Tags "world" and "server": the
authority only, on a dedicated server with two clients (SKIP otherwise), the requester standing INSIDE a house.

A one-member settlers group at home on the requester's square (furnished, stock read), its member embodied, both
players moved next to it, three batteries given to each; both clients open the "Trade" option of their context menu on
the npc and propose their batteries for the SAME cheap item of the stock at the same moment (RST.Steps
"lk.trade.window", RST_PeerChecksLK2.lua: TradeView.fill, option clicked, TradeView.propose): exactly one proposal
accepted, the item in exactly one inventory, nothing missing at the next stock check.
Cleanup (t:defer): test items removed from both inventories, furnishing, stock reference, group and body removed.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksLK2"

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

RST.suite("lk.tradeview", { tags = { "world", "server" }, testTimeoutMs = 150000 }, function(s)
    s.test("two clients ask the same item through the Trade menu: one winner", function(t)
        local E = module(t)
        if not isServer() then t:skip("needs a dedicated server and a second client (MP campaign)") end
        local others = RST.Steps.others(t)
        if #others == 0 then t:skip("no second client online (MP campaign, --clients 2)") end
        local T, S, G, F, K = E.Trade, E.Stock, E.Groups, RST.Fixtures, RST.LKHelpers
        local p = t.ctx and t.ctx.player
        local peer = RST.Steps.playerOf(others[1])
        t:ok(p ~= nil and peer ~= nil, "players not found")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local keyA, keyB = E.Hostility.keyOf(p), E.Hostility.keyOf(peer)
        if keyA == nil or keyB == nil then t:skip("both players need a notebook character (trade key)") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local g = assert(G.create({ type = "settlers", name = "RST trade two", day = G.today(), home = home }))
        local gid = g.id
        assert(G.addMember(gid, { role = "worker", day = G.today() }))
        local given = {}   -- { player, id }
        local npc
        t:defer(function()
            for _, e in ipairs(given) do
                local inv = e.player:getInventory()
                local it = inv:getItemWithIDRecursiv(e.id)
                if it ~= nil then
                    inv:DoRemoveItem(it)
                    sendRemoveItemFromContainer(inv, it)
                end
            end
            S.clear(gid)
            E.Homes.clear(gid)
            G.remove(gid)
            if npc ~= nil then E.Bodies.despawn(npc, true) end
        end, "remove the test items, the furnishing and group " .. gid)
        local mark, why = E.Homes.check(gid, { force = true })
        t:ok(type(mark) == "table", "home not furnished: " .. tostring(why))
        t:ok(type(S.check(gid, { force = true })) == "table", "stock not checked")
        t:waitUntil(function()
            local m = G.get(gid) and G.get(gid).members["m-1"]
            npc = m and m.npc or nil
            return npc ~= nil and E.Bodies.find(npc) ~= nil and K.standing(npc)()
        end, 60000, function(t2)
            local body = E.Bodies.find(npc)
            local a, b = K.target(body, -1, 0), K.target(body, 1, 0)
            t2:ok(a ~= nil and b ~= nil, "no free squares next to the npc")
            F.movePlayer(t2, p, a:getX() + 0.5, a:getY() + 0.5, a:getZ(), function(t3)
                F.movePlayer(t3, peer, b:getX() + 0.5, b:getY() + 0.5, b:getZ(), function(t4)
                    for _, pl in ipairs({ p, peer }) do
                        local inv = pl:getInventory()
                        for _ = 1, 3 do
                            local it = instanceItem("Base.Battery")
                            inv:AddItem(it)
                            sendAddItemToContainer(inv, it)
                            given[#given + 1] = { player = pl, id = it:getID() }
                        end
                    end
                    local offer = T.offer(gid, keyA, p)
                    t4:ok(offer ~= nil, "no offer for the requester")
                    local want
                    for _, e in ipairs(offer.take) do
                        if want == nil and e.v <= 2 then want = e end
                    end
                    t4:ok(want ~= nil, "the group offers nothing cheap")
                    given[#given + 1] = { player = p, id = want.i }
                    given[#given + 1] = { player = peer, id = want.i }
                    local done0 = T.stats.done
                    RST.Steps.ask(t4, "lk.trade.window", { npc = npc, give = "Base.Battery", take = want.i },
                        { target = "all", timeoutMs = 20000 }, function(t5, res)
                            local winners, lines = 0, {}
                            for _, e in ipairs(res.list) do
                                if e.data and e.data.ok then winners = winners + 1 end
                                lines[#lines + 1] = e.user .. " " .. tostring(e.data and e.data.reason)
                            end
                            local holders = 0
                            for _, pl in ipairs({ p, peer }) do
                                if pl:getInventory():getItemWithIDRecursiv(want.i) ~= nil then holders = holders + 1 end
                            end
                            t5:note("same item " .. tostring(want.t) .. " asked by both: " .. table.concat(lines, ", "))
                            t5:eq(1, winners, "accepted proposals")
                            t5:eq(1, T.stats.done - done0, "trades done by the authority")
                            t5:eq(1, holders, "inventories holding the item")
                            local r = S.check(gid, { force = true })
                            t5:eq(0, r and r.missing, "items missing at the next check (loss or theft)")
                        end)
                end)
            end)
        end, "group member not embodied and standing")
    end, { timeoutMs = 150000 })
end)
