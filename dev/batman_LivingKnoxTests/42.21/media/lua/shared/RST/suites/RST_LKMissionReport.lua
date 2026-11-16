--[[
lk.missionreport.llm (E11-T13, tags "server" and "world", solo only, bridge running with the real model; E21-T11: split
from rs.missionreport.llm of batman_RadioSurvivorTests): a Living Knox npc requester (notebook fiche) with a scout
mission whose objective is met takes the report spoken to it with the notebook (intent report_done of the model,
context.reportable, Server.spokenReport), on the real notebook state and the real server paths. The phrase is the
notebook Say line (RST.CarnetHelpers.talk). The visit itself is staged (m.zoneReached set by the test): the server
poll of the visit is covered by ca.missions.scout. The model may phrase things freely: the test checks only the server
facts (mission succeeded) and notes the answer. Asynchronous run:
RST.run({ suite = "lk.missionreport.llm", tags = { "server", "world" } }) with bridge
adio_bridge.py running.
Cleanup: the test mission is removed from the notebook state.
]]

require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_PeerChecks"
require "RST/RST_CarnetHelpers"
require "RST/RST_ReputationHelpers"

local F, N = RST.Fixtures, RST.CarnetHelpers
local LLM_WAIT_MS = 150000


RST.suite("lk.missionreport.llm", { tags = { "server", "world" }, testTimeoutMs = 420000, timeoutMs = 900000 },
        function(s)
    s.test("npc requester takes the report spoken with the notebook (model)", function(t)
        N.solo(t)
        local M = require "CoreAI/CA_Missions"
        local Server = N.notebook(t)
        local S = Server.store
        local p = F.player(t)
        if not p then t:skip("no target player") end
        local cid = N.character(t, p)
        N.god(t, p)
        local Config = require "CoreAI/CA_MissionConfig"
        local Scout = require "CoreAI/CA_MissionScout"
        N.npcWithFiche(t, p, 2, function(t2, id, fiche)
            local c = { Server = Server, cid = cid, fiche = fiche, id = id, p = p }
            local old = fiche.mission and S.data.missions[fiche.mission]
            if old then N.dropMission(S, old, cid) end
            Scout.resetForTests()
            local sc = Config.Missions.scout
            if not Scout.offer(sc, fiche, nil, p) then
                t2:skip("no building fits around the player for a scout mission: move to a town and run again")
            end
            local m = M.create(S.data, fiche, cid, sc.id)
            t2:ok(m ~= nil, "scout mission not created")
            t2:defer(function() N.dropMission(S, m, cid) end, "remove the test npc mission")
            local record = S.data.characters[cid]
            t2:eq(true, M.accept(S.data, m, cid, record.name or ""), "mission not accepted")
            if type(record.knownMissions) == "table" then record.knownMissions[m.id] = true end
            m.zoneReached, m.reachedBy, m.reachedAt = true, record.name or "", getTimestampMs()
            S.save()
            t2:eq(true, M.reportReady(m), "staged visit not ready to report")
            N.select(t2, c, function(t3)
                local since = getTimestampMs()
                local kind = type(m.placeKind) == "string" and m.placeKind or "building"
                N.talk(t3, c, "I went to that " .. kind .. " you asked me to scout and looked it over, inside and "
                    .. "out. That's my report: it's done.", function(t4, req)
                    t4:ok(type(req.context) == "table" and type(req.context.reportable) == "table",
                        "talk request without context.reportable")
                    t4:waitUntil(function() return m.state == "success" end, LLM_WAIT_MS, function(t5)
                        t5:eq("mission.success", RST.ReputationSuite.outcomes()[m.id .. "-" .. cid .. "-result"].action)
                        local k = S.data.characters[cid].contacts[fiche.id]
                        local answer = nil
                        for _, h in ipairs(k and k.history or {}) do
                            if h.id == req.id then answer = h.text end
                        end
                        t5:note("npc report accepted (request " .. tostring(req.id) .. "), answer: "
                            .. tostring(answer))
                    end, function()
                        return "report not accepted within " .. LLM_WAIT_MS .. " ms (state " .. tostring(m.state)
                            .. "): " .. RST.PeerChecks.bridgeCause(Server, since)
                    end)
                end)
            end)
        end)
    end)
end)
