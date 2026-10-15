--[[
rs.missions.scout - mission template "scout" (E11-T03, server/RadioSurvivor/RS_MissionScout.lua) on the real
metagrid: a place drawn around the requester, the zone reached only through the server poll (RS_Missions.observe on
the server copy of the player), a report refused before the visit and accepted after it.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (the
player is moved: test saves "rstest*" only). Asynchronous run (RST.start / RST.server): the move waits in steps.
The mission lives in an in-memory state built by the test (requester fiche, character, store whose save does
nothing): no notebook state, no ModData, no reward item. The requester body is a stand-in at the player's position.
Outside the game: tests/test_carnet.py (ScoutMissionTests, metagrid double).
]]

require "RST/RST"
require "RST/RST_Fixtures"

local F = RST.Fixtures

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_MissionScout is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivor/RS_Missions"
    local Scout = require "RadioSurvivor/RS_MissionScout"
    if type(M) ~= "table" or type(Scout) ~= "table" then t:skip("mission modules did not return their table here") end
    return M, Scout, require "RadioSurvivor/RS_Config"
end

RST.suite("rs.missions.scout", { tags = { "server", "world" }, testTimeoutMs = 60000 }, function(s)
    s.test("place, server poll of the visit, report only after it", function(t)
        local M, Scout, Config = modules(t)
        local c = Config.Missions.scout
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
        local npc = { id = "rst-scout" }
        state.npcs[npc.id] = npc
        state.characters.char1 = { name = "Tester", contacts = { [npc.id] = { trust = "Cautious" } }, knownMissions = {} }
        local ox, oy = p:getX(), p:getY()
        local body = { getX = function() return ox end, getY = function() return oy end }
        Scout.resetForTests()
        local offer = Scout.offer(c, npc, nil, body)
        if not offer then t:skip("no building fits around the player (" .. c.minDistance .. "-" .. c.maxDistance
            .. " tiles): move to a town and run again") end
        t:eq("scout", offer.kind)
        t:ok(#offer.clues >= 2, "fewer than two clues")
        for _, clue in ipairs(offer.clues) do t:ok(not string.find(clue, "%d"), "clue with a digit: " .. clue) end
        t:eq(nil, offer.zone, "zone in the offer")
        local m = M.create(state, npc, "char1", c.id)
        t:ok(m ~= nil and m.template == "scout", "scout mission not created")
        t:eq(true, M.accept(state, m, "char1", "Tester"))
        local store = { data = state, save = function() return true end }
        local watched = { { player = p, character = "char1" } }
        t:eq({ false, "Zone" }, { M.spoken(store, m, p, "char1") }, "report before the visit")
        t:eq(false, M.observe(state, watched), "zone reached without moving")
        local z = m.zone
        local tx, ty = math.floor((z.x1 + z.x2) / 2) + 0.5, math.floor((z.y1 + z.y2) / 2) + 0.5
        t:note("place " .. m.place .. " " .. m.siteKey .. " zone " .. z.x1 .. "," .. z.y1 .. " - " .. z.x2 .. "," .. z.y2
            .. "; clues: " .. table.concat(m.clues, " | "))
        F.movePlayer(t, p, tx, ty, 0, function(t2)
            t2:eq(true, M.observe(state, watched), "server poll inside the zone")
            t2:eq(true, m.zoneReached)
            t2:eq("active", m.state, "a visit alone is not a success")
            t2:eq(true, M.reportReady(m), "E11-T13: visit not marked to report")
            t2:eq({ true }, { M.spoken(store, m, p, "char1") }, "report after the visit")
            t2:eq("success", m.state)
            t2:eq("mission.success", state.outcomes[m.id .. "-char1-result"].action)
        end)
    end)
end)
