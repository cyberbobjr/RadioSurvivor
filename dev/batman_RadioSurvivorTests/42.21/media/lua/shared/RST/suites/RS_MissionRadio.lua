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
state, no history line, no ModData. The test sheet has no [place]: no map mark is given (reputation only).
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
-- E18-T22: facts of the missions in the reputation of the core mod.
local function repOutcomes()
    local Rep = require "CoreAI/CA_Reputation"
    Rep.ensure()
    return Rep.data and Rep.data.outcomes or {}
end

local function mapActions()
    if type(isServer) == "function" and isServer() then return nil end
    local ok, MapActions = pcall(require, "CoreAI/CA_MapZones")
    if ok and type(MapActions) == "table" and MapActions.symbolsAPI() ~= nil then return MapActions end
    return nil
end

-- Mission rows given to CA_MapZones.zones: the test row first, then the real notebook missions (their areas stay).
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
    local M = require "CoreAI/CA_Missions"
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
        require("CoreAI/CA_MissionScout").resetForTests()
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
        -- E20-T02: generic context, the visit told by the template's facts.
        t:eq({ "not_yet", "active", false, "scout" }, { before.turn, before.state, before.toReport, before.kind })
        t:eq("The caller has been to the place (checked by the server): no.", before.facts and before.facts[1])
        t:eq({ nil, "not_done" }, { V.report(store, sheet, "char1", p, 199800) }, "report before the visit")
        t:eq(nil, before.zone, "zone in the bridge context")
        for _, clue in ipairs(before.clues) do t:ok(not string.find(clue, "%d"), "clue with a digit: " .. clue) end
        -- E11-T09: title of the template; clues projected to the notebook as keys (one per English clue).
        local row = M.projection(m, "char1")
        t:eq("IGUI_CA_Mission_Scout", row.titleKey)
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
            t2:eq(nil, after.reward, "reward place from a sheet without [place]")
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
                            t5:eq("mission.success", repOutcomes()[mission.id .. "-" .. cid .. "-result"].action)
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
        local Scout = require "CoreAI/CA_MissionScout"
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
                        t5:eq("mission.success", repOutcomes()[m.id .. "-" .. cid .. "-result"].action)
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

--[[
rs.missions.voicetemplates (E11-T17, tags "server" and "world"): the other templates a radio voice may give
(RS_MissionVoice.TEMPLATES: deliver, retrieve, clear, signal; scout is rs.missions.radio), each one through the real
start path of a voice (RS_MissionVoice.start, the executor of start_mission) with a test sheet whose only [mission]
permits that template. For every template: the mission is created for the caller with the engine template
(retrieve -> retrieve_id), radio report, no reward lot; a second one is refused while it is open; another caller
(the second client's character when one is online, else a character of the test state) has no open mission, hears
nothing, cannot report it and is not engaged in the notebook projection; a report before the objective is refused
("not_done").
Two templates are played to the end with the real objective mechanism of their rs.mission.* suite:
    - clear: a real zombie spawned next to the player, killed by a lethal bat hit of the player, counted by the
      template (Clear.noteHit / Clear.count on OnHitZombie / OnZombieDead subscribers of the test, as rs.mission.clear);
      the counting circle is moved onto the player and the target lowered to 1 (as the solo test of rs.mission.clear);
    - signal: real signals started through the public Signal Smoke API (SignalSmoke.start, source "grenade", player
      = the target player) at the centre of the circle, judged by Signal.count (listener of the test, as
      rs.mission.signal); the hour window is moved to the current game hour; another colour is not counted.
  Then the report on another frequency (another voice) changes nothing, the voice turn is "report_due", a report by
  another caller is refused, the report on the voice's frequency closes the mission in success; a second report is
  refused, the reputation fact is written once and the mission has no lot to claim (no reward doubled).
Each mission lives in an in-memory state built by the test (characters char1 and char2, store whose save does
nothing): no notebook state, no history line, no ModData of the notebook. The test sheets have one [place] only
(use=drop, its dead drop point is the player's square, used by deliver and retrieve): reputation only, no map mark. A dead
drop in "box" mode leaves an opaque key in the ModData of a nearby container: removed at the end. Cleanup: zombies and
corpses of the test removed, Signal Smoke listener removed and test signals stopped, god mode restored.
Outside the game: tests/test_rs_e11_voice_npc_suites.py (voice simulation of tests/test_carnet.py, clear and Signal
Smoke doubles).
]]

require "RST/RST_Steps"

local TEMPLATE_OF = { deliver = "deliver", retrieve = "retrieve_id", clear = "clear", signal = "signal" }
local VOICE_KHZ, OTHER_KHZ = 199800, 199900
local MARK = "RST_VoiceClearZombie"
local OWNER = "RST:voicesignal"
local LETHAL = 100.0
local DEATH_MS = 5000

-- Server copy of the second online player, or nil (solo, or no second client).
local function peerPlayer(t)
    local others = RST.Steps.others(t)
    return others[1] and RST.Steps.playerOf(others[1]) or nil
end

-- Facts of mission m written in a test state (reputation events of the engine).
local function factsOf(state, m)
    local n, prefix = 0, m.id .. "-"
    for key in pairs(state.outcomes) do
        if string.sub(key, 1, string.len(prefix)) == prefix then n = n + 1 end
    end
    return n
end

-- A mission of a test voice whose sheet permits only `template`, started for char1 through RS_MissionVoice.start.
-- Returns { M, V, p, peer, sheet, state, store, m }; SKIP when the template has no place around the player.
local function voiceMission(t, template)
    local M, V, Actions = modules(t)
    t:eq(true, Actions.isKnown("start_mission"), "start_mission not in the catalogue")
    t:eq(true, V.register(), "start_mission or report_mission executor not registered")
    local p = F.player(t)
    if not p then t:skip("no target player") end
    local sheet = { id = "rst-voice-" .. template, name = "RST Voice", actions = { "say", "start_mission" },
        budgets = {}, missions = { { id = template, type = template } }, places = {} }
    -- E20-T03: the dead drop of a voice is a place of its sheet with use=drop (E20-T06: deliver and retrieve use it;
    -- the other templates ignore it).
    sheet.places[1] = { id = "drop", label = "RST drop", x = math.floor(p:getX()), y = math.floor(p:getY()),
        z = math.floor(p:getZ()), uses = { "drop" }, use = { drop = true } }
    local state = { missions = {}, npcs = {}, characters = {}, outcomes = {} }
    state.characters.char1 = { name = "Tester", contacts = {}, knownMissions = {} }
    state.characters.char2 = { name = "Mate", contacts = {}, knownMissions = {} }
    local store = { data = state, save = function() return true end }
    require("CoreAI/CA_MissionScout").resetForTests()
    require("CoreAI/CA_MissionClear").resetForTests()
    require("CoreAI/CA_MissionRetrieve").resetForTests()
    require("CoreAI/CA_MissionSignal").resetForTests()
    local m, why = V.start(store, sheet, "char1", p, VOICE_KHZ, template)
    if not m and why == "no_place" and template == "clear" then
        -- Same rule as rs.mission.clear: a quiet spawn area has no building above minDensity; the draw is made again
        -- with a test catalogue entry without minimum density (the suite brings its own zombie).
        local c = require("RadioSurvivor/RS_Config").Missions.clear
        local minDensity = c.minDensity
        c.minDensity = 0
        require("CoreAI/CA_MissionClear").resetForTests()
        m, why = V.start(store, sheet, "char1", p, VOICE_KHZ, template)
        c.minDensity = minDensity
        t:note("no building above minDensity " .. tostring(minDensity) .. ": drawn again without minimum density")
    end
    if not m and why == "no_place" then
        t:skip("no place for a " .. template .. " mission around the player: move to a town and run again")
    end
    t:ok(m ~= nil, template .. " mission not created: " .. tostring(why))
    for _, drop in ipairs(type(m.drops) == "table" and m.drops or {}) do
        local box, z = drop.box, drop.z
        if box then
            t:defer(function()
                local sq = getCell() and getCell():getGridSquare(box.x, box.y, z)
                local objects = sq and sq:getObjects()
                local o = objects and box.object < objects:size() and objects:get(box.object) or nil
                local md = o and o:getModData()
                if md and type(md.RS_DeadDrop) == "table" then md.RS_DeadDrop[box.key] = nil end
            end, "remove the dead drop key of the test box")
        end
    end
    return { M = M, V = V, p = p, peer = peerPlayer(t), sheet = sheet, state = state, store = store, m = m }
end

-- Created for the caller with the engine template, radio report and no lot; refused while open; a report before
-- the objective refused; another caller gets nothing.
local function created(t, c, template)
    local M, V, m, p = c.M, c.V, c.m, c.p
    t:eq({ TEMPLATE_OF[template], "voice", c.sheet.id, "radio", "active", 0 },
        { m.template, m.donor, m.voice, m.report, m.state, m.rewardCount }, template .. " mission of the voice")
    t:eq(true, m.participants.char1 ~= nil, "caller not engaged")
    t:eq({ nil, "mission_open" }, { V.start(c.store, c.sheet, "char1", p, VOICE_KHZ, template) },
        "second mission for the same caller")
    local heard = V.heard(c.sheet, p, "char1", VOICE_KHZ, c.store)
    t:eq({ "not_yet", false }, { heard and heard.turn, heard and heard.toReport }, "turn before the objective")
    t:eq({ nil, "not_done" }, { V.report(c.store, c.sheet, "char1", p, VOICE_KHZ) }, "report before the objective")
    t:eq("active", m.state, "a report before the objective closed the mission")
    -- Another caller: the second client's character when one is online, else char2 of the test state.
    local who = c.peer or p
    t:note("other caller: " .. (c.peer and "second client" or "test character without a client"))
    t:eq(nil, V.open(c.state, c.sheet.id, "char2"), "another caller has the mission")
    t:eq(nil, V.heard(c.sheet, who, "char2", VOICE_KHZ, c.store), "another caller hears the mission")
    t:eq({ nil, "no_mission" }, { V.report(c.store, c.sheet, "char2", who, VOICE_KHZ) }, "report by another caller")
    t:eq(nil, m.participants.char2, "another caller engaged")
    local row = M.projection(m, "char2")
    t:eq({ false, nil }, { row.engaged, row.mapZone }, "notebook projection of another caller")
end

-- Objective met (reportReady): report on another frequency, by another caller, then on the voice's frequency; no
-- second report, one reputation fact, nothing to claim.
local function reported(t, c)
    local M, V, m, p, store = c.M, c.V, c.m, c.p, c.store
    t:eq(true, M.reportReady(m), "objective met but the mission does not wait for its report")
    local other = { id = "rst-other", name = "RST Other", actions = { "say", "start_mission" }, places = {} }
    t:eq(nil, V.heard(other, p, "char1", OTHER_KHZ, store), "another voice hears the mission")
    t:eq({ nil, "no_mission" }, { V.report(store, other, "char1", p, OTHER_KHZ) }, "report on another frequency")
    t:eq("active", m.state, "a report on another frequency closed the mission")
    local due = V.heard(c.sheet, p, "char1", VOICE_KHZ, store)
    t:eq({ "report_due", true }, { due and due.turn, due and due.toReport }, "turn after the objective")
    t:eq({ nil, "no_mission" }, { V.report(store, c.sheet, "char2", c.peer or p, VOICE_KHZ) },
        "report by another caller after the objective")
    t:eq("active", m.state, "a report by another caller closed the mission")
    t:eq(true, V.report(store, c.sheet, "char1", p, VOICE_KHZ) == m, "report on the voice's frequency refused")
    t:eq("success", m.state)
    t:eq("mission.success", c.state.outcomes[m.id .. "-char1-result"].action)
    local facts = factsOf(c.state, m)
    t:eq({ nil, "no_mission" }, { V.report(store, c.sheet, "char1", p, VOICE_KHZ) }, "second report")
    t:eq(facts, factsOf(c.state, m), "reputation fact written twice")
    t:eq(false, (M.claim(store, m, p, "char1", "rst-voice-claim")), "a voice mission gave a lot to claim")
    t:eq({ 0, nil }, { m.rewardCount, m.rewardPlace }, "reward of a sheet without a [place] to mark")
    t:eq(nil, V.open(c.state, c.sheet.id, "char1"), "mission still open after the report")
end

-- Clear: one real zombie next to the player, lethal bat hit of the player, counted by the template.
local function playClear(t, c)
    local Clear = require "CoreAI/CA_MissionClear"
    local m, p = c.m, c.p
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    t:note("clear target " .. tostring(m.target) .. " lowered to 1, circle moved onto the player")
    m.target, m.mapZone = 1, { x = px, y = py, r = 8 }
    local mine, credited = {}, {}
    local function resolve(player) if rawequal(player, p) then return "char1" end end
    local function onHit(z, wielder, _, weapon) if mine[z] then Clear.noteHit(z, wielder, weapon) end end
    local function onDead(z) if mine[z] then credited[#credited + 1] = Clear.count(c.state, z, resolve) ~= nil end end
    Events.OnHitZombie.Add(onHit)
    Events.OnZombieDead.Add(onDead)
    t:defer(function() Events.OnHitZombie.Remove(onHit); Events.OnZombieDead.Remove(onDead) end,
        "remove the test subscribers")
    local wasGod = p:isGodMod()
    p:setGodMod(true)
    t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
    local function spawn(t1)
        local list = addZombiesInOutfit(px + 2, py, pz, 1, nil, 50)
        t1:ok(list ~= nil and list:size() == 1, "zombie not created")
        local z = list:get(0)
        z:getModData()[MARK] = true
        mine[z] = true
        t1:defer(function()
            if not z:isDead() then z:removeFromWorld(); z:removeFromSquare() end
            local sq = getCell() and getCell():getGridSquare(px + 2, py, pz)
            local objects = sq and sq:getStaticMovingObjects()
            for i = (objects and objects:size() or 0) - 1, 0, -1 do
                local o = objects:get(i)
                if instanceof(o, "IsoDeadBody") and o:hasModData() and o:getModData()[MARK] then sq:removeCorpse(o, false) end
            end
        end, "remove the zombie and corpse of the test")
        z:Hit(instanceItem("Base.BaseballBat"), p, LETHAL, false, 1.0)
        t1:waitUntil(function() return z:isDead() and #credited >= 1 end, DEATH_MS, function(t2)
            t2:eq({ true, 1, 1 }, { credited[1], m.kills, m.tally.char1 }, "kill of the caller in the circle")
            t2:eq(nil, Clear.count(c.state, z, resolve), "same zombie counted again")
            t2:eq(1, m.kills, "count after a second death event")
            reported(t2, c)
        end, "zombie not dead after a lethal hit")
    end
    if F.WAIT_LOADED then F.waitSquare(t, px + 2, py, pz, nil, spawn) else spawn(t) end
end

-- Signal: another colour, then the asked colour at the centre of the circle, lit by the player in the window.
local function playSignal(t, c)
    local Signal = require "CoreAI/CA_MissionSignal"
    local lib = Signal.library()
    if not lib then t:fail("required mod Signal Smoke (batman_SignalSmoke) unusable: Signal.library() returned nil") end
    local m, p = c.m, c.p
    t:ok(lib.COLORS[m.color] ~= nil, "colour unknown to Signal Smoke: " .. tostring(m.color))
    m.hour = getGameTime():getHour()
    t:note("signal colour " .. tostring(m.color) .. ", window moved to " .. m.hour .. ":00")
    local function resolve(player) if rawequal(player, p) then return "char1" end end
    local credited, ids = {}, {}
    local function listener(event)
        if event.type == "started" and event.entry and event.entry.owner == OWNER then
            credited[#credited + 1] = Signal.count(c.state, event, resolve) ~= nil
        end
    end
    lib.onSignal(listener)
    t:defer(function()
        lib.removeSignalListener(listener)
        for _, id in ipairs(ids) do lib.stop(id) end
    end, "remove the test listener and stop the test signals")
    local function light(n, color)
        local id = "rst-voicesignal-" .. n
        ids[#ids + 1] = id
        local started, err = lib.start{ x = m.mapZone.x, y = m.mapZone.y, z = 0, color = color, kind = "smoke",
            realSeconds = 15, radius = 0, light = false, id = id, owner = OWNER, source = "grenade", player = p }
        t:ok(started ~= nil, "Signal Smoke refused the signal: " .. tostring(err))
    end
    light(1, m.color == "green" and "red" or "green")
    t:eq({ false, false }, { credited[1], m.lit }, "signal of another colour counted")
    light(2, m.color)
    t:eq({ true, true }, { credited[2], m.lit }, "signal of the asked colour not counted")
    reported(t, c)
end

RST.suite("rs.missions.voicetemplates", { tags = { "server", "world" }, testTimeoutMs = 60000 }, function(s)
    s.test("deliver: created for the caller only, drop at the voice's place, no report before collection", function(t)
        local c = voiceMission(t, "deliver")
        created(t, c, "deliver")
        -- E20-T05: every use=drop place of the sheet is a drop of the mission.
        local d, place = c.m.drops and c.m.drops[1], c.sheet.places[1]
        t:eq({ place.x, place.y, place.z }, { d and d.x, d and d.y, d and d.z }, "dead drop point of the sheet")
        t:ok(d.mode == "box" or d.mode == "bag", "dead drop mode " .. tostring(d.mode))
        t:note("dead drop mode " .. tostring(d.mode))
    end)

    s.test("retrieve: created for the caller only as retrieve_id, no report without the card", function(t)
        local c = voiceMission(t, "retrieve")
        created(t, c, "retrieve")
        t:eq({ false, false }, { c.m.placed, c.m.found }, "body placed or card found at creation")
        -- E20-T06: the card is left at a drop of the sheet; the mission keeps its search place.
        local d = c.m.drops and c.m.drops[1]
        t:eq({ 1, c.sheet.places[1].x, c.sheet.places[1].y }, { c.m.drops and #c.m.drops, d and d.x, d and d.y },
            "dead drop of the retrieve mission")
        t:ok(c.m.place ~= "RST drop", "the search place was replaced by the drop")
    end)

    s.test("clear: kill of the caller counted, report on the voice's frequency only, no reward doubled", function(t)
        local c = voiceMission(t, "clear")
        created(t, c, "clear")
        playClear(t, c)
    end)

    s.test("signal: asked colour counted, report on the voice's frequency only, no reward doubled", function(t)
        local c = voiceMission(t, "signal")
        created(t, c, "signal")
        playSignal(t, c)
    end)
end)
