--[[
rs.mission.zones - circles of the missions "retrieve" (E11-T05) and "recover" (E11-T06) on the map of every client,
and their notebook line "found" translated there (E01-T16). Tag "server" (authority: RST.server from the admin client
of the MP campaign, or solo). Selected by the campaign entry "rs.mission".

Each test builds the mission in an in-memory state (as rs.mission.retrieve / rs.mission.recover: requester stand-in
at the player's position, nothing saved, nothing placed in the world) and sends its notebook row, as the server
projects it for a participant (RS_Missions.projection), to every client in a notebook snapshot (real command
"snapshot", RST.PeerChecks2.checkZones); each client checks its world map (RST.Steps "map.zones"):
    accepted   the circles are drawn once with their labels (retrieve: search area; recover: cache area and depot);
    found      the circles stay, the notebook line "found" exists in the language of the client;
    closed     after the success the circles are removed.
The real notebook snapshots are sent again at the end. SKIP when no building fits around the player; without the
notebook state: FAIL on a server, SKIP in solo (RST.PeerChecks2.checkZones).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_PeerChecks2"

local PC2 = RST.PeerChecks2

local function modules(t, which)
    if type(isClient) == "function" and isClient() then t:skip("missions live on the authority") end
    local M = require "RadioSurvivor/RS_Missions"
    local T
    if which == "retrieve" then
        T = require "RadioSurvivor/RS_MissionRetrieve"
    else
        T = require "RadioSurvivor/RS_MissionRecover"
    end
    if type(M) ~= "table" or type(T) ~= "table" then t:skip("mission modules did not return their table here") end
    return M, T, require "RadioSurvivor/RS_Config"
end

-- In-memory mission of template id accepted by "char1"; nil when no building fits (SKIP).
local function accepted(t, M, T, c, npcId, p)
    local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
    local npc = { id = npcId, incarnation = npcId }
    state.npcs[npc.id] = npc
    state.characters.char1 = { name = "Tester", contacts = { [npc.id] = { trust = "Cautious" } }, knownMissions = {} }
    local ox, oy = p:getX(), p:getY()
    local body = { getX = function() return ox end, getY = function() return oy end }
    T.resetForTests()
    if not T.offer(c, npc, nil, body) then
        t:skip("no building fits around the player (" .. c.minDistance .. "-" .. c.maxDistance .. " tiles)")
    end
    local m = M.create(state, npc, "char1", c.id)
    t:ok(m ~= nil, c.id .. " mission not created")
    t:eq(true, M.accept(state, m, "char1", "Tester"))
    return m
end

-- accepted -> found (with the notebook line key) -> closed, checked on every client.
local function zonesChain(t, M, m, rings, lineKey)
    local uid = "rst-" .. m.id .. "-" .. tostring(getTimestampMs())
    PC2.checkZones(t, (PC2.zoneRow(M, m, "char1", uid)), rings, "present", nil, function(t2)
        m.found, m.foundBy = true, "Tester"
        local row = PC2.zoneRow(M, m, "char1", uid)
        PC2.checkZones(t2, row, rings, "present", { key = lineKey, arg = "Tester" }, function(t3)
            m.state = "success"
            PC2.checkZones(t3, (PC2.zoneRow(M, m, "char1", uid)), rings, "absent", nil)
        end)
    end)
end

RST.suite("rs.mission.zones", { tags = { "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("retrieve: search circle drawn, kept once found, removed after the success (E11-T05)", function(t)
        local M, T, Config = modules(t, "retrieve")
        local p = RST.Fixtures.player(t)
        if not p then t:skip("no target player") end
        local m = accepted(t, M, T, Config.Missions.retrieve_id, "rst-zones-retrieve", p)
        local _, rings = PC2.zoneRow(M, m, "char1", "probe")
        t:eq(1, #rings, "circles of the accepted mission")
        zonesChain(t, M, m, rings, "IGUI_RS_RetrieveFound")
    end)

    s.test("recover: cache and depot circles drawn, kept once found, removed after the success (E11-T06)", function(t)
        local M, T, Config = modules(t, "recover")
        local P = require "RadioSurvivor/RS_NPCProvider"
        local p = RST.Fixtures.player(t)
        if not p then t:skip("no target player") end
        local ox, oy, oz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
        local presence = P.presence
        P.presence = function(id)
            if id == "rst-zones-recover" then return { away = false, x = ox, y = oy, z = oz } end
            return presence(id)
        end
        t:defer(function() P.presence = presence end, "restore RS_NPCProvider.presence")
        local m = accepted(t, M, T, Config.Missions.recover, "rst-zones-recover", p)
        local _, rings = PC2.zoneRow(M, m, "char1", "probe")
        t:eq(2, #rings, "circles of the accepted mission (cache area, depot)")
        zonesChain(t, M, m, rings, "IGUI_RS_RecoverFound")
    end)
end)
