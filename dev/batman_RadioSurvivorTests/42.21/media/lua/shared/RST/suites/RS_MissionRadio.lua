--[[
rs.missions.radio - mission given by a radio voice (E11-T08, server/RadioSurvivor/RS_MissionVoice.lua): the
start_mission executor is registered, a test sheet with start_mission creates a scout mission drawn around the
player, a second one is refused while it is open, a phrase said to the voice before the visit is no report (turn
"not_yet", report refused "not_done"), the visit is seen by the server poll (RS_Missions.observe on the server copy of
the player), the next call is told "report_due" (E11-T13: objective met, still active), a report on another voice
(another frequency) changes nothing, and the report of this voice (RS_MissionVoice.report, executor of the action
report_mission) closes it (success, reputation event of M01).
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (the
player is moved: test saves "rstest*" only). Asynchronous run (RST.start / RST.server): the move waits in steps.
The mission lives in an in-memory state built by the test (character, store whose save does nothing): no notebook
state, no history line, no ModData. The test sheet has no place= line: no map mark is given (reputation only).
E11-T10: the mission keeps an approximate map area (m.mapZone) that holds the building footprint without being
centred on it, projected to the participant only while the mission is active, never in the bridge context. Where the
client map module is loaded with the authority (solo), the area is drawn on the world map (Circle symbol at its
centre) and removed once the mission succeeded; the real notebook missions are passed along so that their own areas
are kept. On a dedicated server that part is only noted.
Outside the game: tests/test_carnet.py (VoiceMissionTests, metagrid double).
]]

require "RST/RST"
require "RST/RST_Fixtures"

local F = RST.Fixtures

-- E11-T10: client map module beside the authority (solo), or nil (dedicated server).
local function mapActions()
    if type(isServer) == "function" and isServer() then return nil end
    local ok, MapActions = pcall(require, "RadioSurvivor/RS_MapActions")
    if ok and type(MapActions) == "table" and MapActions.symbolsAPI() ~= nil then return MapActions end
    return nil
end

-- Mission rows given to MapActions.zones: the test row first, then the real notebook missions (their areas stay).
local function rowsWith(row)
    local rows = { row }
    local client = RS_CarnetClient
    for _, r in ipairs(client and client.snapshot and client.snapshot.missions or {}) do rows[#rows + 1] = r end
    return rows
end

-- Area symbols (Circle) at the centre of the area.
local function ringsAt(MapActions, z)
    local api, n = MapActions.symbolsAPI(), 0
    for i = 0, api:getSymbolCount() - 1 do
        local sym = api:getSymbolByIndex(i)
        if sym and sym:isTexture() and sym:getSymbolID() == MapActions.ZONE_ICON
                and math.abs(sym:getWorldX() - z.x) < 0.01 and math.abs(sym:getWorldY() - z.y) < 0.01 then
            n = n + 1
        end
    end
    return n
end

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_MissionVoice is not loaded on an MP client (authority only)")
    end
    local M = require "RadioSurvivor/RS_Missions"
    local V = require "RadioSurvivor/RS_MissionVoice"
    local Actions = require "RadioSurvivor/RS_Actions"
    if type(M) ~= "table" or type(V) ~= "table" or type(Actions) ~= "table" then
        t:skip("mission modules did not return their table here")
    end
    return M, V, Actions
end

RST.suite("rs.missions.radio", { tags = { "server", "world" }, testTimeoutMs = 60000 }, function(s)
    s.test("voice mission: one per caller, report on the radio only after the visit", function(t)
        local M, V, Actions = modules(t)
        t:eq(true, Actions.isKnown("start_mission"), "start_mission not in the catalogue")
        t:eq(true, Actions.isKnown("report_mission"), "report_mission not in the catalogue")
        t:eq(true, V.register(), "start_mission or report_mission executor not registered")
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local sheet = { id = "rst-voice", name = "RST Voice", actions = { "say", "start_mission" }, budgets = {},
            places = {} }
        local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
        state.characters.char1 = { name = "Tester", contacts = {}, knownMissions = {} }
        local store = { data = state, save = function() return true end }
        require("RadioSurvivor/RS_MissionScout").resetForTests()
        local m, why = V.start(store, sheet, "char1", p, 199800, "scout")
        if not m and why == "no_place" then
            t:skip("no building fits around the player (60-250 tiles): move to a town and run again")
        end
        t:ok(m ~= nil, "mission not created: " .. tostring(why))
        t:eq({ "voice", "rst-voice", "radio", "active", 0 }, { m.donor, m.voice, m.report, m.state, m.rewardCount })
        t:eq(true, m.participants.char1 ~= nil, "caller not engaged")
        local again, reason = V.start(store, sheet, "char1", p, 199800, "scout")
        t:eq(nil, again, "second mission for the same caller")
        t:eq("mission_open", reason)
        local before = V.heard(sheet, p, "char1", 199800, store)
        t:eq({ "not_yet", "active", false, false }, { before.turn, before.state, before.zoneReached, before.toReport })
        t:eq({ nil, "not_done" }, { V.report(store, sheet, "char1", p, 199800) }, "report before the visit")
        t:eq(nil, before.zone, "zone in the bridge context")
        for _, clue in ipairs(before.clues) do t:ok(not string.find(clue, "%d"), "clue with a digit: " .. clue) end
        -- E11-T09: title of the template; clues projected to the notebook as keys (one per English clue).
        local row = M.projection(m, "char1")
        t:eq("IGUI_RS_Scout", row.titleKey)
        t:eq(#before.clues, #row.clues, "notebook clues out of step with the bridge clues")
        t:eq("Kind", row.clues[1] and row.clues[1].key)
        t:eq("briefing", V.context(m, "briefing").turn)
        -- E11-T10: approximate area holding the footprint (m.zone minus the margin), not centred on the building.
        local area = m.mapZone
        t:ok(type(area) == "table", "no map area")
        local margin = require("RadioSurvivor/RS_Config").Missions.scout.margin
        local fx1, fy1, fx2, fy2 = m.zone.x1 + margin, m.zone.y1 + margin, m.zone.x2 - margin, m.zone.y2 - margin
        for _, c in ipairs({ { fx1, fy1 }, { fx2, fy1 }, { fx1, fy2 }, { fx2, fy2 } }) do
            local d = math.sqrt((c[1] - area.x) * (c[1] - area.x) + (c[2] - area.y) * (c[2] - area.y))
            t:ok(d <= area.r, "building corner outside the area")
        end
        t:ok(area.x ~= (fx1 + fx2) / 2 or area.y ~= (fy1 + fy2) / 2, "area centred on the building")
        t:eq({ area.x, area.y, area.r }, { row.mapZone.x, row.mapZone.y, row.mapZone.r }, "area not projected")
        t:eq(nil, before.mapZone, "area in the bridge context")
        local MapActions = mapActions()
        if MapActions then
            MapActions.zones(rowsWith(row))
            t:eq(1, ringsAt(MapActions, area), "area not drawn on the world map")
        else
            t:note("no client map here (dedicated server): drawing not checked")
        end
        t:eq("active", m.state, "a phrase before the visit closed the mission")
        local watched = { { player = p, character = "char1" } }
        t:eq(false, M.observe(state, watched), "zone reached without moving")
        local z = m.zone
        local tx, ty = math.floor((z.x1 + z.x2) / 2) + 0.5, math.floor((z.y1 + z.y2) / 2) + 0.5
        t:note("place " .. tostring(m.placeKind) .. " " .. m.siteKey .. " zone " .. z.x1 .. "," .. z.y1 .. " - "
            .. z.x2 .. "," .. z.y2)
        F.movePlayer(t, p, tx, ty, 0, function(t2)
            t2:eq(true, M.observe(state, watched), "server poll inside the zone")
            t2:eq("active", m.state, "a visit alone is not a success")
            local after = V.heard(sheet, p, "char1", 199800, store)
            t2:eq({ "report_due", "active", true }, { after.turn, m.state, after.toReport }, "call after the visit")
            t2:eq(nil, after.reward, "reward place from a sheet without place=")
            t2:eq(true, M.projection(m, "char1").toReport, "notebook row not marked to report")
            local other = { id = "rst-other", name = "RST Other", actions = { "say", "start_mission" }, places = {} }
            t2:eq({ nil, "no_mission" }, { V.report(store, other, "char1", p, 199900) }, "report to another voice")
            t2:eq("active", m.state, "a report to another voice closed the mission")
            t2:eq(true, V.report(store, sheet, "char1", p, 199800) == m, "report on the voice's frequency refused")
            t2:eq("success", m.state)
            t2:eq("mission.success", state.outcomes[m.id .. "-char1-result"].action)
            t2:eq(nil, V.open(state, "rst-voice", "char1"), "mission still open after the report")
            -- E11-T10: a closed mission projects no area; the map loses it.
            local closed = M.projection(m, "char1")
            t2:eq(nil, closed.mapZone, "area still projected after the report")
            if MapActions then
                MapActions.zones(rowsWith(closed))
                t2:eq(0, ringsAt(MapActions, area), "area left on the world map")
            end
        end)
    end)
end)

--[[
rs.missionreport.llm (E11-T13, tags "server" and "world", solo only, bridge running with the real model): the
recognition of the report by the model itself, on the real notebook state and the real server paths.
    - a delivered voice that gives jobs (darlene.txt: actions=say,start_mission) gives a scout job when the player asks
      for work on her frequency (the model returns start_mission; the server creates the mission), then, once the
      objective is met, the player's report on her frequency closes it (the model returns report_mission; the server
      checks it again);
    - a Living Knox npc requester (notebook fiche) with a scout mission whose objective is met takes the report spoken
      to it with the notebook (intent report_done of the model, context.reportable, Server.spokenReport).
The phrase is the real 'talk' command of the local player (radio held in hand, RST.RSHelpers.radioInHand) or the
notebook Say line (RST.RSHelpers.talk). The visit itself is staged (m.zoneReached set by the test): the server poll of
the visit is covered by rs.missions.radio and rs.missions.scout. The voice listens at any hour during the test (its
listening hours are restored at the end). The model may phrase things freely: the test checks only the server facts
(mission created, then succeeded) and notes the lines heard. Asynchronous run:
RST.run({ suite = "rs.missionreport.llm", tags = { "server", "world" } }) with bridge\radio_bridge.py running.
Cleanup: the test missions are removed from the notebook state (the voice donor keeps its count).
]]

require "RST/RST_RSHelpers"

local R = RST.RSHelpers
local LLM_WAIT_MS = 150000
local QUIET_MS, AIR_MAX_MS = 8000, 90000   -- airing over: no new line on the frequency for QUIET_MS

local function has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- Removes a test mission from the real notebook state (and its requester's link).
local function dropMission(S, m, cid)
    if not (S.data and m) then return end
    S.data.missions[m.id] = nil
    local donor = S.data.npcs[m.npc] or (S.data.voiceDonors and S.data.voiceDonors[m.npc])
    if donor and donor.mission == m.id then donor.mission = nil end
    local record = S.data.characters[cid]
    if record and type(record.knownMissions) == "table" then record.knownMissions[m.id] = nil end
    S.save()
end

-- A request of this voice is still waiting for the bridge in requests.txt.
local function voicePending(Const, voice)
    for _, line in ipairs(R.readLines(Const.REQUESTS_FILE) or {}) do
        if line == "voice=" .. voice then return true end
    end
    return false
end

-- Waits until the voice is done airing on khz (no line heard for QUIET_MS, AIR_MAX_MS at most), then after(t).
local function aired(t, heard, khz, after)
    local start = getTimestampMs()
    t:waitQuiet(function()
        local last = start
        for _, h in ipairs(heard) do if h.khz == khz and h.at > last then last = h.at end end
        local now = getTimestampMs()
        return now - last >= QUIET_MS or now - start >= AIR_MAX_MS
    end, AIR_MAX_MS + 5000, after, "airing of the voice never ended")
end

local function joined(list)
    return #list > 0 and table.concat(list, " / ") or "(nothing heard)"
end

RST.suite("rs.missionreport.llm", { tags = { "server", "world" }, testTimeoutMs = 420000, timeoutMs = 900000 },
        function(s)
    s.test("delivered voice gives a scout job, the radio report closes it (model)", function(t)
        R.solo(t)
        local M, V = modules(t)
        local Server = R.notebook(t)
        local S = Server.store
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local cid = R.character(t, p)
        R.god(t, p)
        local P = require "RadioSurvivor/RS_Personas"
        local Const = require "RadioSurvivor/RadioSurvivor_Const"
        local VOICE = "darlene"
        local sheet = P.get(VOICE)
        t:ok(sheet ~= nil, "voice " .. VOICE .. " not loaded")
        t:ok(has(sheet.actions, "start_mission"), "installed " .. VOICE .. ".txt does not allow start_mission "
            .. "(delivered version not installed? see the log: voice '" .. VOICE .. "' modified by the admin)")
        local khz = P.frequencies(VOICE)[1]
        t:ok(type(khz) == "number" and P.isServed(VOICE, khz), "no frequency served for " .. VOICE)
        local listen = sheet.listen
        sheet.listen = {}
        t:defer(function() sheet.listen = listen end, "restore the listening hours of " .. VOICE)
        -- A job of an earlier run is dropped; the delay after a closed job is lifted for this caller.
        local d = V.donor(S.data, VOICE, cid, true)
        local old = V.open(S.data, VOICE, cid)
        if old then dropMission(S, old, cid) end
        d.nextOfferAt, d.nextOfferHour = nil, nil
        local radio = R.radioInHand(t, p, "Base.WalkieTalkie5", khz)
        local heard = R.hear(t)
        local cooldown = Const.playerCooldownMs() + 500
        local function talk(text)
            triggerEvent("OnClientCommand", Const.MODULE, Const.CMD.TALK, p,
                { text = text, itemId = radio:getID(), channel = khz })
        end
        local mission = nil
        t:defer(function() dropMission(S, mission, cid) end, "remove the test voice mission")
        t:note("voice " .. VOICE .. " on " .. R.label(khz) .. " MHz, character " .. cid)
        t:sleep(cooldown, function(t1)
            local since1 = getTimestampMs()
            talk("Darlene, this is a survivor on a walkie. I am healthy and I have time on my hands. "
                .. "Do you have a job for me? Is there a building you need someone to go and check out for you?")
            t1:waitUntil(function() return V.open(S.data, VOICE, cid) ~= nil end, LLM_WAIT_MS, function(t2)
                mission = V.open(S.data, VOICE, cid)
                t2:eq({ "voice", VOICE, "radio", "active" }, { mission.donor, mission.voice, mission.report,
                    mission.state }, "mission of the voice")
                -- The briefing (E11-T09) follows the job: wait until the voice is done talking.
                t2:waitQuiet(function() return not voicePending(Const, VOICE) end, LLM_WAIT_MS, function(t2a)
                    aired(t2a, heard, khz, function(t3)
                    t3:note("job given (" .. tostring(mission.placeKind) .. "), heard: "
                        .. joined(R.words(heard, khz, since1)))
                    t3:eq("not_yet", V.heard(sheet, p, cid, khz).turn, "turn before the visit")
                    mission.zoneReached, mission.reachedBy, mission.reachedAt = true, "Tester", getTimestampMs()
                    S.save()
                    t3:eq(true, M.reportReady(mission), "staged visit not ready to report")
                    t3:eq("report_due", V.heard(sheet, p, cid, khz).turn, "turn after the visit")
                    t3:sleep(cooldown, function(t4)
                        local since2 = getTimestampMs()
                        local kind = type(mission.placeKind) == "string" and mission.placeKind or "building"
                        talk("Darlene, it's me again. I went to that " .. kind .. " you sent me to and looked it over, "
                            .. "inside and out. That's my report: the job is done. Over.")
                        t4:waitUntil(function() return mission.state == "success" end, LLM_WAIT_MS, function(t5)
                            t5:eq("mission.success", S.data.outcomes[mission.id .. "-" .. cid .. "-result"].action)
                            t5:eq(nil, V.open(S.data, VOICE, cid), "mission still open after the report")
                            -- The answer is aired line by line after the action: let it end before noting it.
                            aired(t5, heard, khz, function(t6)
                                t6:note("report accepted, heard: " .. joined(R.words(heard, khz, since2)))
                            end)
                        end, function()
                            return "report not accepted within " .. LLM_WAIT_MS .. " ms (state "
                                .. tostring(mission.state) .. "), heard: " .. joined(R.words(heard, khz, since2))
                        end)
                    end)
                    end)
                end, "briefing of the voice never answered")
            end, function()
                return "no job given within " .. LLM_WAIT_MS .. " ms, heard: " .. joined(R.words(heard, khz, since1))
            end)
        end)
    end)

    s.test("npc requester takes the report spoken with the notebook (model)", function(t)
        R.solo(t)
        local M = modules(t)
        local Server = R.notebook(t)
        local S = Server.store
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local cid = R.character(t, p)
        R.god(t, p)
        local Config = require "RadioSurvivor/RS_Config"
        local Scout = require "RadioSurvivor/RS_MissionScout"
        R.npcWithFiche(t, p, 2, function(t2, id, fiche)
            local c = { Server = Server, cid = cid, fiche = fiche, id = id, p = p, C = Config }
            local old = fiche.mission and S.data.missions[fiche.mission]
            if old then dropMission(S, old, cid) end
            Scout.resetForTests()
            local sc = Config.Missions.scout
            if not Scout.offer(sc, fiche, nil, p) then
                t2:skip("no building fits around the player for a scout mission: move to a town and run again")
            end
            local m = M.create(S.data, fiche, cid, sc.id)
            t2:ok(m ~= nil, "scout mission not created")
            t2:defer(function() dropMission(S, m, cid) end, "remove the test npc mission")
            local record = S.data.characters[cid]
            t2:eq(true, M.accept(S.data, m, cid, record.name or ""), "mission not accepted")
            if type(record.knownMissions) == "table" then record.knownMissions[m.id] = true end
            m.zoneReached, m.reachedBy, m.reachedAt = true, record.name or "", getTimestampMs()
            S.save()
            t2:eq(true, M.reportReady(m), "staged visit not ready to report")
            R.select(t2, c, function(t3)
                local since = getTimestampMs()
                local kind = type(m.placeKind) == "string" and m.placeKind or "building"
                R.talk(t3, c, "I went to that " .. kind .. " you asked me to scout and looked it over, inside and "
                    .. "out. That's my report: it's done.", function(t4, req)
                    t4:ok(type(req.context) == "table" and type(req.context.reportable) == "table",
                        "talk request without context.reportable")
                    t4:waitUntil(function() return m.state == "success" end, LLM_WAIT_MS, function(t5)
                        t5:eq("mission.success", S.data.outcomes[m.id .. "-" .. cid .. "-result"].action)
                        local k = S.data.characters[cid].contacts[fiche.id]
                        local answer = nil
                        for _, h in ipairs(k and k.history or {}) do
                            if h.id == req.id then answer = h.text end
                        end
                        t5:note("npc report accepted (request " .. tostring(req.id) .. "), answer: "
                            .. tostring(answer))
                    end, function()
                        return "report not accepted within " .. LLM_WAIT_MS .. " ms (state " .. tostring(m.state)
                            .. "): " .. R.bridgeCause(Server, since)
                    end)
                end)
            end)
        end)
    end)
end)
