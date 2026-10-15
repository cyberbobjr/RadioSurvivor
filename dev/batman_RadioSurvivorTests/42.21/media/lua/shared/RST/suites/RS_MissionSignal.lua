--[[
rs.mission.signal - mission template "signal" (E11-T07, server/RadioSurvivor/RS_MissionSignal.lua) with the real
required mod Signal Smoke: a building drawn around the player on the real metagrid, a colour and an hour, a circle
centred on the building; real signals started through the public Signal Smoke API (SignalSmoke.start, as a thrown
grenade of the player: source "grenade", player = the target player) at the centre of the circle: a signal of another
colour changes nothing, a signal of the asked colour outside the circle changes nothing, the asked colour inside the
circle meets the objective: the mission stays active "to report" (E11-T13) until the report to the requester
(RS_Missions.spoken), which closes it in success through the common engine; a report before the signal is refused.
Signal Smoke is a required mod (mod.info require=): its module unusable here is a FAIL, never a SKIP.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (coloured
smoke appears for a few seconds in the circle: test saves "rstest*" only). The mission lives in an in-memory state
built by the test (requester fiche, character): no notebook state, no reward item; its hour window is moved to the
current game hour after creation. The real listener of the template only watches the notebook state, so this suite
adds its own Signal Smoke listener on the template function (Signal.count) for its state, removed at the end.
Cleanup: listener removed, signals of the test stopped.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local F = RST.Fixtures
local OWNER = "RST:signal"

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_MissionSignal is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivor/RS_Missions"
    local Signal = require "RadioSurvivor/RS_MissionSignal"
    if type(M) ~= "table" or type(Signal) ~= "table" then
        t:skip("mission modules did not return their table here")
    end
    local lib = Signal.library()
    if not lib then t:fail("required mod Signal Smoke (batman_SignalSmoke) unusable: Signal.library() returned nil") end
    return M, Signal, lib, require "RadioSurvivor/RS_Config"
end

RST.suite("rs.mission.signal", { tags = { "server", "world" }, testTimeoutMs = 30000 }, function(s)
    s.test("a signal of the asked colour lit by the participant inside the circle succeeds, other signals do not",
            function(t)
        local M, Signal, lib, Config = modules(t)
        local c = Config.Missions.signal
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
        local npc = { id = "rst-signal", incarnation = "rst-signal" }
        state.npcs[npc.id] = npc
        state.characters.char1 = { name = "Tester", contacts = { [npc.id] = { trust = "Cautious" } }, knownMissions = {} }
        local ox, oy = p:getX(), p:getY()
        local body = { getX = function() return ox end, getY = function() return oy end }
        Signal.resetForTests()
        local offer = Signal.offer(c, npc, nil, body)
        if not offer then t:skip("no building around the player (" .. c.minDistance .. "-" .. c.maxDistance
            .. " tiles): move to a town and run again") end
        t:eq("signal", offer.kind)
        t:ok(lib.COLORS[offer.color] ~= nil, "colour unknown to Signal Smoke: " .. tostring(offer.color))
        for _, clue in ipairs(offer.clues) do t:ok(not string.find(clue, "%d"), "clue with a digit: " .. clue) end
        local m = M.create(state, npc, "char1", c.id)
        t:ok(m ~= nil and m.template == "signal", "signal mission not created")
        t:eq(offer.color, m.color, "colour of the offer")
        t:eq(offer.hour, m.hour, "hour of the offer")
        t:eq(true, M.accept(state, m, "char1", "Tester"))
        local store = { data = state, save = function() return true end }
        t:eq({ false, "Zone" }, { M.spoken(store, m, p, "char1") }, "E11-T13: report before the signal accepted")
        m.hour = getGameTime():getHour()
        t:note("place " .. m.place .. " " .. m.siteKey .. ", circle " .. m.mapZone.x .. "," .. m.mapZone.y .. " r "
            .. m.mapZone.r .. ", colour " .. m.color .. ", window moved to " .. m.hour .. ":00")
        local other = m.color == "green" and "red" or "green"
        local function resolve(player) if rawequal(player, p) then return "char1" end end
        local credited = {}
        local function listener(event)
            if event.type == "started" and event.entry and event.entry.owner == OWNER then
                credited[#credited + 1] = Signal.count(state, event, resolve) ~= nil
            end
        end
        lib.onSignal(listener)
        local ids = {}
        t:defer(function()
            lib.removeSignalListener(listener)
            for _, id in ipairs(ids) do lib.stop(id) end
        end, "remove the test listener and stop the test signals")
        local function light(n, x, y, color)
            local id = "rst-signal-" .. n
            ids[#ids + 1] = id
            local started, err = lib.start{ x = x, y = y, z = 0, color = color, kind = "smoke", realSeconds = 15,
                radius = 0, light = false, id = id, owner = OWNER, source = "grenade", player = p }
            t:ok(started ~= nil, "Signal Smoke refused the signal: " .. tostring(err))
        end
        local cx, cy, r = m.mapZone.x, m.mapZone.y, m.mapZone.r
        -- 1. Another colour at the centre of the circle.
        light(1, cx, cy, other)
        t:eq(false, credited[1], "signal of another colour counted")
        t:eq("active", m.state)
        -- 2. The asked colour outside the circle.
        light(2, cx + r + 5, cy, m.color)
        t:eq(false, credited[2], "signal outside the circle counted")
        t:eq("active", m.state)
        -- 3. The asked colour inside the circle, by the participant, in the window: objective met (E11-T13), then the
        -- report to the requester: success.
        light(3, cx, cy, m.color)
        t:eq(true, credited[3], "right signal not counted")
        t:eq({ "active", true, true }, { m.state, m.lit, M.reportReady(m) }, "signal seen, report expected")
        t:eq({ true }, { M.spoken(store, m, p, "char1") }, "report to the requester")
        t:eq("success", m.state)
        t:eq(true, m.lit)
        t:eq("mission.success", state.outcomes[m.id .. "-char1-result"].action)
    end)
end)
