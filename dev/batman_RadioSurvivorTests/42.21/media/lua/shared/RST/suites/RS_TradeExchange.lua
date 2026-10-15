--[[
rs.trade_exchange - contactless exchange on the bank (E13-T04, server/RadioSurvivor/RS_TradeExchange.lua): real items
appraised with the table of the smuggler (named ID card taken, blank card and hammer refused, price covered), then a
full exchange on a bag put on the floor next to the player: the pier is moved to the player for the test, the run is
booked and the boat arrives, nobody is counted near, one poll takes the goods out of the bag and puts the counterpart
in it, marked with the revision of the offer; the next polls give nothing more (counterpart given once).
Tags "server" and "world" (authority only: solo, or RST.server from an admin client of a dedicated server; a bag is put
on the floor: test saves "rstest*" only). Solo: RST.run({ suite = "rs.trade_exchange", tags = "world" }); dedicated
server: RST.server({ suite = "rs.trade_exchange", tags = "world" }).

Changes to the world: none kept. The bag is removed from the floor at the end; the trade state of the save
(S.data.trade) is copied before the exchange and put back after it; the radio line is captured, never aired; the pier
and the presence check are put back.
Outside the game: tests/test_rs_trade_exchange.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local F = RST.Fixtures

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the exchange runs on the authority (server files not loaded on an MP client)")
    end
    local ok, Ex = pcall(require, "RadioSurvivor/RS_TradeExchange")
    t:ok(ok and type(Ex) == "table", "RadioSurvivor/RS_TradeExchange is not loaded on this side")
    return Ex, require "RadioSurvivor/RS_Trade", require "RadioSurvivor/RS_State"
end

local function bagWith(types)
    local bag = instanceItem("Base.Bag_Schoolbag")
    local inv = bag:getInventory()
    for _, t in ipairs(types) do
        local item = instanceItem(t)
        inv:AddItem(item)
    end
    return bag, inv
end

local function named(inv, fullType, name)
    for i = 0, inv:getItems():size() - 1 do
        local item = inv:getItems():get(i)
        if item:getFullType() == fullType and item:getModData().rstNamed == nil then
            item:getModData().rstNamed = true
            item:setName(name or item:getScriptItem():getDisplayName())
            return item
        end
    end
    return nil
end

local function countType(inv, fullType)
    local n = 0
    for i = 0, inv:getItems():size() - 1 do
        if inv:getItems():get(i):getFullType() == fullType then n = n + 1 end
    end
    return n
end

RST.suite("rs.trade_exchange", { tags = { "server", "world" } }, function(s)
    s.test("real items appraised with the table", function(t)
        local Ex = modules(t)
        local _, inv = bagWith({ "Base.MoneyBundle", "Base.Necklace_Gold", "Base.IDcard", "Base.IDcard",
            "Base.Hammer" })
        named(inv, "Base.IDcard", "ID Card: Rst Example")
        named(inv, "Base.IDcard", nil)                         -- blank name: refused
        local all = Ex.appraise(Ex.itemsOf(inv), {})
        t:eq(17, all.value, "value of money bundle, gold necklace and one named card")
        t:eq(3, #all.taken, "items taken")
        local part = Ex.appraise(Ex.itemsOf(inv), {}, 10)
        t:eq(10, part.value, "value taken for a price of 10")
        t:eq(14, Ex.appraise(Ex.itemsOf(inv), { "Rst Example" }, nil).value, "card named after a player taken")
    end)

    s.test("exchange on a bag on the floor, counterpart given once", function(t)
        local Ex, Trade, S = modules(t)
        if not S.data or S.blocked then t:skip("private state not loaded") end
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        local sq = getCell():getGridSquare(x + 1, y, z)
        if not sq then t:skip("no square next to the player") end
        Trade.stock()
        local saved = deepCopy(S.data.trade)
        local pier, near, radio = Trade.PIER, Ex.anyoneNear, RS_RadioServer
        local air = type(radio) == "table" and radio.air or nil
        local bag, inv = bagWith({ "Base.MoneyBundle", "Base.Hammer" })
        t:defer(function()
            Trade.PIER, Ex.anyoneNear = pier, near
            if air then radio.air = air end
            S.data.trade = saved
            S.dirty = true
            local wos = sq:getWorldObjects()
            for i = wos:size() - 1, 0, -1 do
                local wo = wos:get(i)
                if wo:getItem() and wo:getItem():getID() == bag:getID() then sq:transmitRemoveItemFromSquare(wo) end
            end
        end, "remove the bag, put the trade state and the pier back")
        S.data.trade.run = nil
        Trade.PIER = { x = x + 1, y = y, z = z, desc = pier.desc }
        Ex.anyoneNear = function() return false end
        local captured = {}
        if air then radio.air = function(khz, lines) captured[#captured + 1] = lines end end
        local offer, why, booked = Trade.propose("rst-a", nil, "OutsideNews:1", nil, "rst-team-a", { voice = "gus" })
        if offer == nil then t:skip("no offer this week: " .. tostring(why)) end
        t:ok(booked == true, "run not booked")
        t:ok(offer.price <= 10, "price above one money bundle: " .. tostring(offer.price))
        t:eq(true, Trade.arrive("rst"), "boat not arrived")
        sq:AddWorldInventoryItem(bag, 0.5, 0.5, 0, true)
        local found = Ex.bagsIn(x + 1, y, z, 0)
        t:eq(1, found and #found or 0, "bag not found on the floor")
        t:eq("done", Ex.update(), "outcome of the first poll")
        t:eq(0, countType(inv, "Base.MoneyBundle"), "money bundle still in the bag")
        t:eq(1, countType(inv, "Base.Hammer"), "hammer (worth nothing) not left in the bag")
        t:eq(1, countType(inv, "RadioSurvivor.OutsideNews"), "counterpart in the bag")
        t:eq(true, Ex.hasMark(bag, offer.rev), "counterpart not marked")
        t:eq("done", Trade.lastRun().state, "run state")
        for _ = 1, 3 do t:eq(nil, Ex.update(), "a later poll did something") end
        t:eq(1, countType(inv, "RadioSurvivor.OutsideNews"), "counterpart given twice")
        if air then
            t:eq(1, #captured, "radio lines")
            if captured[1] then
                t:ok(string.find(captured[1][2], "IGUI_", 1, true) == nil, "untranslated key")
                t:note(captured[1][2])
            end
        end
    end)
end)
