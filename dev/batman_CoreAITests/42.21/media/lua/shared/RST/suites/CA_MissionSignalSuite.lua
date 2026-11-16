--[[
ca.mission.signal - mission template "signal" (E11-T07, server/CoreAI/CA_MissionSignal.lua) with the real
required mod Signal Smoke: a building drawn around the player on the real metagrid, a colour and an hour, a circle
centred on the building; real signals started through the public Signal Smoke API (SignalSmoke.start, as a thrown
grenade of the player: source "grenade", player = the target player) at the centre of the circle: a signal of another
colour changes nothing, a signal of the asked colour outside the circle changes nothing, the asked colour inside the
circle meets the objective: the mission stays active "to report" (E11-T13) until the report to the requester
(CA_Missions.spoken), which closes it in success through the common engine; a report before the signal is refused.
Signal Smoke is a required mod (mod.info require=): its module unusable here is a FAIL, never a SKIP.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (coloured
smoke appears for a few seconds in the circle: test saves "rstest*" only). The mission lives in an in-memory state
built by the test (requester fiche, character): no notebook state, no reward item; its hour window is moved to the
current game hour after creation. The real listener of the template only watches the notebook state, so this suite
adds its own Signal Smoke listener on the template function (Signal.count) for its state, removed at the end.
Cleanup: listener removed, signals of the test stopped.

ca.mission.signal.client - the same template seen and played by the REQUESTER client (E11-T07 "controles cote client"),
with the real notebook state and the real listener of the template. Tags "server" and "world"; selected by the campaign
entry "ca.mission" (mp) and by its own name (solo). The requester of the mission is a Living Knox test npc with its
notebook fiche next to the player (RST.CarnetHelpers.npcWithFiche; moved to the nearest town when no building fits, player
in god mode: RST.SignalClientSuite.requester). The authority creates the offer from the real draw of the template
(Signal.offer around the npc body, then CA_Missions.create), its hour window set OUTSIDE the current game hour; then
every player gesture goes through the requester client (RST.Steps, RST_PeerChecks / RST_PeerChecks2 /
RST_PeerChecksSignal: the real network path in MP, the same code in one Lua state in solo):
    accept       notebook command "accept" (RST.Steps "carnet.send", the Accept button): the mission is active and
                 the character takes part in it;
    circle       the circle of the mission on the world map of the requester, once, with its label ("map.zones",
                 present); every other client (second client of the campaign) has no circle there (absent);
    hours        a signal of the asked colour lit by the participant at the centre of the circle OUTSIDE the window
                 (SignalSmoke.start as a thrown grenade of the player): nothing changes on the authority (not lit,
                 still active, same revision) nor in the notebook of the requester ("carnet.signal.row" after a delay);
    in hours     the window moved to the current game hour, the same signal again: the requester's notebook shows the
                 mission "to report";
    report       notebook command "report" near the requester (the Report button, "carnet.signal.send"): success;
    claim        notebook command "claim" ("Reclamer", "carnet.signal.send"): the lot reserved for the character on the
                 authority, the items added to its inventory there are the items received by the requester client.
                 The lot is Living Knox's (E11-T21, each mod pays its missions; same rule as Living Knox alone): one
                 item of the household surplus of the requester's group, else the lot announced with the mission
                 (signal: rewardType x rewardCount), which is also the lot of a requester of no resolvable group.
Cleanup (t:defer): signals of the test stopped, mission, outcome and reputation entry of the character, contact and
known missions put back, the items of the claim removed (and synced), notebook snapshots sent again; the npc and the
player position are undone by the fixtures. Outside the game: tests/test_rs_signal_client_suite.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_PeerChecks"
require "RST/RST_CarnetHelpers"
require "RST/RST_PeerChecks2"
require "RST/RST_PeerChecksSignal"

local F = RST.Fixtures
local OWNER = "RST:signal"

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("CA_MissionSignal is not loaded on an MP client (authority only)")
    end
    local M = require "CoreAI/CA_Missions"
    local Signal = require "CoreAI/CA_MissionSignal"
    if type(M) ~= "table" or type(Signal) ~= "table" then
        t:skip("mission modules did not return their table here")
    end
    local lib = Signal.library()
    if not lib then t:fail("required mod Signal Smoke (batman_SignalSmoke) unusable: Signal.library() returned nil") end
    return M, Signal, lib, require "CoreAI/CA_MissionConfig"
end

-- A Signal Smoke signal started at x, y as a thrown grenade of player p (id kept in ids, stopped at the end).
local function startSignal(t, lib, ids, id, x, y, color, p)
    ids[#ids + 1] = id
    local started, err = lib.start{ x = x, y = y, z = 0, color = color, kind = "smoke", realSeconds = 15,
        radius = 0, light = false, id = id, owner = OWNER, source = "grenade", player = p }
    t:ok(started ~= nil, "Signal Smoke refused the signal: " .. tostring(err))
end

RST.suite("ca.mission.signal", { tags = { "server", "world" }, testTimeoutMs = 30000 }, function(s)
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
        local function light(n, x, y, color) startSignal(t, lib, ids, "rst-signal-" .. n, x, y, color, p) end
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

-- ---------------------------------------------------------------- ca.mission.signal.client (requester client)

RST.SignalClientSuite = RST.SignalClientSuite or {}
local SC = RST.SignalClientSuite
SC.ASK_MS = 15000      -- client deadline of a step
SC.STATE_MS = 5000     -- authority wait for the effect of a notebook command
SC.SETTLE_MS = 2000    -- delay before reading a row that must NOT have changed
SC.NPC_DX = 2
SC.HOUR_SHIFT = 12     -- window moved this many game hours away from now (the window lasts a few hours)

local Steps = RST.Steps

-- Probe of N.place: a signal offer fits around the player (requester stand-in at its position).
local function signalFits(Signal, c)
    return function(pl)
        local x, y = pl:getX(), pl:getY()
        Signal.resetForTests()
        return Signal.offer(c, { id = "rst-signal-probe", incarnation = "rst-signal-probe" }, nil,
            { getX = function() return x end, getY = function() return y end })
    end
end

-- Requester of the mission: a Living Knox test npc with its notebook fiche next to the player (in the nearest town
-- when no building fits around), the player in god mode; after(t, { fiche, body }). The bench replaces it.
function SC.requester(t, p, Signal, c, after)
    local N = RST.CarnetHelpers
    N.place(t, p, signalFits(Signal, c), function(t1)
        N.god(t1, p)
        N.npcWithFiche(t1, p, SC.NPC_DX, function(t2, _, fiche, body)
            return after(t2, { fiche = fiche, body = body })
        end)
    end)
end

-- Main inventory of the authority copy: ids now, items added since, counts by full type, removal synced on a server.
local function itemIds(inv)
    local ids, items = {}, inv:getItems()
    for i = 0, items:size() - 1 do ids[items:get(i):getID()] = true end
    return ids
end

local function itemsSince(inv, ids)
    local out, items = {}, inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if not ids[it:getID()] then out[#out + 1] = it end
    end
    return out
end

local function countTypes(list)
    local out = {}
    for _, it in ipairs(list) do
        local kind = it:getFullType()
        out[kind] = (out[kind] or 0) + 1
    end
    return out
end

local function takeBack(inv, list)
    for _, it in ipairs(list) do
        if inv:getItemWithID(it:getID()) ~= nil then
            inv:Remove(it)
            if type(isServer) == "function" and isServer() then sendRemoveItemFromContainer(inv, it) end
        end
    end
end

local function size(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

-- The test mission, the fiche fields it changes, the contact, the outcome and the reputation entry of the character
-- put back at the end (notebook state, CA_Reputation).
local function guardMission(t, Server, m, cid, fiche, saved)
    local Rep = require "CoreAI/CA_Reputation"
    Rep.ensure()
    local record = Server.store.data.characters[cid]
    local hadContact = record.contacts[fiche.id] ~= nil
    if not hadContact then
        record.contacts[fiche.id] = { history = {}, note = "", trust = "Cautious", trend = "Stable",
            stage = "stranger", exchanges = 0 }
    end
    record.knownMissions[m.id] = true
    local repEntry = RST.deepCopy(Rep.data and Rep.data.reputation and Rep.data.reputation[cid])
    t:defer(function()
        local data = Server.store.data
        data.missions[m.id] = nil
        for _, rec in pairs(data.characters) do rec.knownMissions[m.id] = nil end
        if not hadContact then record.contacts[fiche.id] = nil end
        fiche.mission, fiche.missionCount = saved.mission, saved.missionCount
        fiche.nextOfferAt, fiche.nextOfferHour = saved.nextOfferAt, saved.nextOfferHour
        if Rep.data then
            Rep.data.outcomes[m.id .. "-" .. cid .. "-result"] = nil
            Rep.data.reputation[cid] = repEntry
        end
        Server.publish()
    end, "remove mission " .. m.id .. ", its outcome and the reputation change of " .. cid)
end

-- One step of the requester client; after(t, data of its answer).
local function ask(t, step, args, after)
    Steps.ask(t, step, args, { target = "requester", timeoutMs = SC.ASK_MS }, function(t2, res)
        local e = res.list[1] or {}
        return after(t2, e.data or {})
    end)
end

-- Claim button of the requester: the items the authority put in its inventory are the items its client received.
local function claim(t, m, p, cid)
    local inv = p:getInventory()
    local before = itemIds(inv)
    local added = {}
    t:defer(function() takeBack(inv, added) end, "items of the claim removed from the inventory")
    ask(t, "carnet.signal.send", { command = "claim", mission = m.id, want = { claimed = true } }, function(t2, d)
        for _, it in ipairs(itemsSince(inv, before)) do added[#added + 1] = it end
        local given = countTypes(added)
        t2:eq(cid, m.claimedBy, "lot of the mission reserved for the requester on the authority")
        t2:ok(size(given) > 0, "the claim gave no item on the authority (reward " .. tostring(m.rewardCount) .. " x "
            .. tostring(m.rewardType) .. ")")
        t2:eq(given, d.gained or {}, "items of the claim received in the inventory of the requester client")
    end)
end

-- Signals lit after the acceptance: outside the window (nothing), inside (to report), then Report and Claim.
local function signals(t, m, p, lib, ids, zone, cid)
    local revision = m.revision
    startSignal(t, lib, ids, "rst-signal-client-1", zone.x, zone.y, m.color, p)
    t:eq({ "active", false, revision }, { m.state, m.lit == true, m.revision },
        "signal outside the window counted (state, lit, revision)")
    ask(t, "carnet.signal.row", { mission = m.id, settleMs = SC.SETTLE_MS }, function(t2, row)
        t2:eq({ "active", false, false }, { row.state, row.lit, row.toReport },
            "notebook of the requester after a signal outside the window")
        m.hour = getGameTime():getHour()
        startSignal(t2, lib, ids, "rst-signal-client-2", zone.x, zone.y, m.color, p)
        t2:eq(true, m.lit == true, "signal inside the window not counted")
        ask(t2, "carnet.signal.row", { mission = m.id, want = { state = "active", toReport = true } }, function(t3)
            ask(t3, "carnet.signal.send", { command = "report", mission = m.id, want = { state = "success" } },
                function(t4)
                t4:eq("success", m.state, "mission closed by the Report button")
                claim(t4, m, p, cid)
            end)
        end)
    end)
end

-- Accept button, then the circle on the map of the requester only.
local function acceptAndCircle(t, m, cid, zone, after)
    Steps.ask(t, "carnet.send", { command = "accept", args = { mission = m.id, revision = m.revision } },
        { target = "requester", timeoutMs = SC.ASK_MS }, function(t2)
        t2:waitUntil(function() return m.state == "active" and m.participants[cid] ~= nil end, SC.STATE_MS,
            function(t3)
            Steps.ask(t3, "map.zones", { mission = m.id, rings = { zone }, expect = "present" },
                { target = "requester", timeoutMs = SC.ASK_MS }, function(t4)
                local others = Steps.others(t4)
                if #others == 0 then
                    t4:note("no other client online: absence of the circle elsewhere not checked")
                    return after(t4)
                end
                Steps.ask(t4, "map.zones", { mission = m.id, rings = { zone }, expect = "absent" },
                    { target = others, timeoutMs = SC.ASK_MS }, after)
            end)
        end, "mission not accepted through the notebook command of the requester")
    end)
end

local function clientPlay(t)
    local M, Signal, lib, Config = modules(t)
    local N = RST.CarnetHelpers
    local c = Config.Missions.signal
    local Server = N.notebook(t)
    local p = F.player(t)
    if not p then t:skip("no target player") end
    local cid = N.character(t, p)
    SC.requester(t, p, Signal, c, function(t2, req)
        local fiche = req.fiche
        local saved = { mission = fiche.mission, missionCount = fiche.missionCount, nextOfferAt = fiche.nextOfferAt,
            nextOfferHour = fiche.nextOfferHour }
        t2:eq(nil, fiche.mission, "the test npc " .. tostring(fiche.id) .. " already requests a mission")
        Signal.resetForTests()
        local terms = Signal.offer(c, fiche, nil, req.body)
        t2:ok(terms ~= nil, "no signal offer around the requester " .. tostring(fiche.id))
        local m = M.create(Server.store.data, fiche, cid, c.id, terms)
        t2:ok(m ~= nil and m.template == "signal", "signal mission not created")
        guardMission(t2, Server, m, cid, fiche, saved)
        local ids = {}
        t2:defer(function() for _, id in ipairs(ids) do lib.stop(id) end end, "stop the test signals")
        local now = getGameTime():getHour()
        m.hour = (now + SC.HOUR_SHIFT) % 24
        local zone = { x = m.mapZone.x, y = m.mapZone.y, r = m.mapZone.r }
        t2:note("requester " .. tostring(fiche.id) .. ", circle " .. zone.x .. "," .. zone.y .. " r " .. zone.r
            .. ", colour " .. m.color .. ", window " .. m.hour .. ":00 for " .. m.windowHours .. " h, game hour "
            .. now)
        Server.publish()
        acceptAndCircle(t2, m, cid, zone, function(t3) return signals(t3, m, p, lib, ids, zone, cid) end)
    end)
end

RST.suite("ca.mission.signal.client", { tags = { "server", "world" }, testTimeoutMs = 120000 }, function(s)
    s.test("requester client: accept, circle on its map only, signal outside the window ignored, report and claim",
        clientPlay, { timeoutMs = 180000 })
end)
