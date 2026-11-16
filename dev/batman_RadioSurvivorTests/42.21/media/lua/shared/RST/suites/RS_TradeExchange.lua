--[[
rs.trade_exchange - contactless exchange at the landing of a trader (E13-T04; E20-T07: Gus' run read from his sheet,
state per trader, exchange only out of everyone's view and after a delay in game hours, rule of RS_OutOfSight):
real items counted with the table of the smuggler (named ID card counts, blank card, card named after a player and
hammer do not), then Gus' full run (E23-T06/T07: a deal of two lists, all or nothing on what is added after the
booking): every online player is moved to his landing (place use=landing of personas/gus.txt), the deal is struck for
three money bundles and the server notes the landing, the boat arrives (RS_TradeRun.arrive: the signal itself is
checked by rs.trade_run and the benches), a bag with three money bundles and a hammer is put on the landing, nothing is
exchanged while the players stand there,
every player goes 150 tiles away (beyond RS_OutOfSight.VIEW_TILES), the game clock moves past the delay of the sheet
(GameTime.setTimeOfDay), every player comes back: the bag holds the goods, marked with the revision of the deal, and
the hammer (not in the deal), the run is done; later polls give nothing more.
Tags "server" and "world" (authority only: solo, or RST.server from an admin client of a dedicated server; a bag is put
on the floor: test saves "rstest*" only). Solo: RST.run({ suite = "rs.trade_exchange", tags = "world" }); dedicated
server: RST.server({ suite = "rs.trade_exchange", tags = "world" }); campaign:
python tools/autoclient/autoclient.py --mp --clients 2 --server-suite rs.trade_exchange --bridge on --llm fake.

Changes to the world: none kept. The bag is removed from the floor at the end; the trade state of Gus
(S.data.trade.traders.gus) is copied before the run and put back after it; the radio lines are captured, never aired;
the players are moved back (RST.Fixtures.movePlayers).
Outside the game: tests/test_rs_trade_exchange.py, tests/test_rs_trade_traders.py.

rs.trade_road - the same passage for a trader who comes by road (E20-T11, ADR D08): the first loaded trader whose
sheet says arrival=road (none named here), at the roadside landing of its sheet; the arrival plays the approach sound
of the mode (van door) and the exchange its leave sound (van trunk), both read from the mode and checked on the sound
port of RS_TradeRun (the sounds still reach the players through RS_TradeSound). Booking, arrival by road, bag on the
roadside, players out of sight past the delay of the sheet, exchange. Tags "server" and "world"; campaign:
python tools/autoclient/autoclient.py --mp --clients 2 --server-suite rs.trade_road --server-tags world --bridge on
--llm fake. Outside the game: tests/test_rs_town_traders.py.
]]

require "RST/RST"
require "RST/RST_ModRadioSurvivor"
require "RST/RST_Fixtures"

local F = RST.Fixtures

local GUS = "gus"       -- the delivered trader of rs.trade_exchange (his sheet holds the landing and the delay)
local AWAY = 150        -- tiles: beyond RS_OutOfSight.VIEW_TILES (100) on the x axis

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
    return Ex, require "RadioSurvivor/RS_Trade", require "RadioSurvivor/RS_State", require "RadioSurvivor/RS_TradeRun"
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

-- The bag of this id on the square (a chunk reloaded after the trip away holds a new Java object), or nil.
local function bagOn(x, y, z, id)
    local sq = getCell():getGridSquare(x, y, z)
    local objects = sq and sq:getWorldObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        local item = objects:get(i):getItem()
        if item and item:getID() == id then return item, objects:get(i), sq end
    end
    return nil
end

-- Moves the game clock forward by `hours` without crossing 7:00 (the world age would go back).
local function advance(hours)
    local gt = getGameTime()
    gt:setTimeOfDay(gt:getTimeOfDay() + hours)
end

-- First loaded trader whose [trade] section names this arrival mode, or nil.
local function traderBy(Trade, arrival)
    for _, id in ipairs(Trade.traderIds()) do
        if Trade.specOf(id).arrival == arrival then return id end
    end
    return nil
end

-- Stock item booked for the run: the outside news when the trader brings it (cheap), else the first one available.
local function goods(Trade, voice, caller)
    local free = Trade.available(voice, caller, nil)
    if (free.OutsideNews or 0) > 0 then return "OutsideNews", "RadioSurvivor.OutsideNews" end
    for _, e in ipairs(Trade.specOf(voice).items) do
        if (free[e.n] or 0) > 0 then return e.n, e.t end
    end
    return nil
end

-- Full passage of the trader VOICE. sounds: true to check the approach and leave sounds of its arrival mode.
local function passage(t, VOICE, sounds)
    local Ex, Trade, S, Run = modules(t)
    if not S.data or S.blocked then t:skip("private state not loaded") end
    if not VOICE then t:skip("no loaded trader for this arrival mode") end
    local spec = Trade.specOf(VOICE)
    if not spec then t:skip("voice " .. VOICE .. " has no [trade] section loaded") end
    local mode = require("RadioSurvivor/RS_TradeArrivals").get(spec.arrival)
    local played = {}
    if sounds then
        local Sound = require "RadioSurvivor/RS_TradeSound"
        Run.useSound(function(name, point)
            played[#played + 1] = name
            return Sound.playAt(name, point)
        end)
        t:defer(function() Run.useSound(nil) end, "sound port of RS_TradeRun put back")
    end
    local p = F.player(t)
    if not p then t:skip("no target player") end
    local gt = getGameTime()
    if (gt:getTimeOfDay() - 7) % 24 > 18 then
        gt:setTimeOfDay(8)
        t:note("game clock set to 8:00 so that it can be moved forward by a few hours")
    end
    local L = spec.landings[1]
    local delay = spec.delayHours or Ex.DELAY_HOURS
    Trade.stock(VOICE)
    local saved = deepCopy(S.data.trade.traders[VOICE])
    local radio = RS_RadioServer
    local air = type(radio) == "table" and radio.air or nil
    local captured = {}
    local bagId = nil
    t:defer(function()
        if air then radio.air = air end
        S.data.trade.traders[VOICE] = saved
        S.dirty = true
        local _, world, sq = bagOn(L.x, L.y, L.z, bagId)
        if world then sq:transmitRemoveItemFromSquare(world) end
    end, "remove the bag, put the trade state of " .. VOICE .. " back")
    S.data.trade.traders[VOICE].run = nil
    if air then radio.air = function(khz, lines) captured[#captured + 1] = lines end end
    local function poll() return Ex.updateTrader(VOICE) end
    F.movePlayers(t, p, L.x + 1, L.y, L.z, function(t1)
        F.waitSquare(t1, L.x, L.y, L.z, nil, function(t2)
            local caller = p:getUsername()
            local name, fullType = goods(Trade, VOICE, caller)
            if not name then t2:skip("nothing left in the stock of " .. VOICE) end
            local offer, why, booked = Trade.propose(VOICE, caller, nil, name .. ":1", "MoneyBundle:3",
                Trade.teamOf(caller, p), {})
            if offer == nil then t2:skip("no deal with " .. VOICE .. " now: " .. tostring(why)) end
            t2:ok(booked == true, "run not booked")
            t2:eq(nil, poll(), "poll after the booking")
            t2:ok(Trade.lastRun(VOICE).seen ~= nil, "landing content not noted after the booking")
            t2:eq(true, Run.arrive(VOICE, "rst"), VOICE .. " not arrived (" .. spec.arrival .. ")")
            if sounds then t2:eq(mode.sounds.approach, played[1], "approach sound of " .. spec.arrival) end
            local bag = bagWith({ "Base.MoneyBundle", "Base.MoneyBundle", "Base.MoneyBundle", "Base.Hammer" })
            bagId = bag:getID()
            getCell():getGridSquare(L.x, L.y, L.z):AddWorldInventoryItem(bag, 0.5, 0.5, 0, true)
            t2:eq(1, #(Ex.holdsAt(VOICE, Trade.lastRun(VOICE)) or {}), "bag not found on the landing")
            t2:eq(nil, poll(), "exchanged in front of the players")
            F.movePlayers(t2, p, L.x + 1 + AWAY, L.y, L.z, function(t3)
                poll()
                advance(delay + 0.5)
                t3:waitUntil(function()
                    poll()
                    local run = Trade.lastRun(VOICE)
                    return run and (run.due == true or run.state ~= "arrived")
                end, 20000, function(t4)
                    t4:note("away: run " .. tostring(Trade.lastRun(VOICE).state) .. ", due "
                        .. tostring(Trade.lastRun(VOICE).due))
                    F.movePlayers(t4, p, L.x + 1, L.y, L.z, function(t5)
                        F.waitSquare(t5, L.x, L.y, L.z, nil, function(t6)
                            t6:waitUntil(function()
                                poll()
                                return Trade.lastRun(VOICE).state == "done"
                            end, 20000, function(t7)
                                local item = bagOn(L.x, L.y, L.z, bagId)
                                t7:ok(item ~= nil, "bag gone from the landing")
                                local inv = item and item:getInventory()
                                t7:eq(1, inv and countType(inv, fullType) or 0, "counterpart")
                                t7:eq(true, item ~= nil and Ex.hasMark(item, offer.rev), "counterpart not marked")
                                t7:eq(1, inv and countType(inv, "Base.Hammer") or 0, "hammer taken")
                                if sounds then
                                    t7:eq(mode.sounds.leave, played[#played], "leave sound of " .. spec.arrival)
                                end
                                for _ = 1, 3 do t7:eq(nil, poll(), "a later poll did something") end
                                t7:eq(1, inv and countType(inv, fullType) or 0, "given twice")
                                if air and captured[1] then
                                    t7:ok(string.find(captured[#captured][2], "IGUI_", 1, true) == nil,
                                        "untranslated key")
                                    t7:note(captured[#captured][2])
                                end
                            end, function()
                                local run = Trade.lastRun(VOICE)
                                return "not exchanged once back: state " .. tostring(run.state) .. ", due "
                                    .. tostring(run.due) .. ", hidden since " .. tostring(run.sight and
                                    run.sight.hiddenSince)
                            end)
                        end)
                    end)
                end, function()
                    local run = Trade.lastRun(VOICE)
                    return "exchange never due away: hidden since " .. tostring(run.sight and run.sight.hiddenSince)
                        .. ", world age " .. tostring(gt:getWorldAgeHours())
                end)
            end)
        end)
    end)
end

RST.suite("rs.trade_exchange", { tags = { "server", "world" }, testTimeoutMs = 180000 }, function(s)
    s.test("real items counted with the table", function(t)
        local Ex = modules(t)
        local _, inv = bagWith({ "Base.MoneyBundle", "Base.Necklace_Gold", "Base.IDcard", "Base.IDcard",
            "Base.Hammer" })
        local card = named(inv, "Base.IDcard", "ID Card: Rst Example")
        local blank = named(inv, "Base.IDcard", nil)            -- blank name: does not count
        local counted = {}
        for i = 0, inv:getItems():size() - 1 do
            local item = inv:getItems():get(i)
            if Ex.counts(item, {}) then counted[#counted + 1] = item:getFullType() end
        end
        table.sort(counted)
        t:eq("Base.IDcard,Base.MoneyBundle,Base.Necklace_Gold", table.concat(counted, ","), "items that count")
        t:eq(true, Ex.counts(card, {}) == true, "named card")
        t:eq(false, Ex.counts(blank, {}) == true, "blank card")
        t:eq(false, Ex.counts(card, { "Rst Example" }) == true, "card named after a player")
    end)

    s.test("Gus' run: exchanged only once every player is out of view for the delay", function(t)
        passage(t, GUS, false)
    end)
end)

RST.suite("rs.trade_road", { tags = { "server", "world" }, testTimeoutMs = 180000 }, function(s)
    s.test("run of a road trader: van at the roadside, bag exchanged once every player is out of view", function(t)
        local _, Trade = modules(t)
        passage(t, traderBy(Trade, "road"), true)
    end)
end)
