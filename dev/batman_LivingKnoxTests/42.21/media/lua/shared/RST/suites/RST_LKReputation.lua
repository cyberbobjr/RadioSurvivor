--[[
lk.reputation - reputation of the killer of a Living Knox requester (E04-T07, E04-T14; server/CoreAI/CA_Reputation.lua,
design docs/annexes/conception/reputation-interne.md). E21-T11: split from rs.reputation; the other reputation tests
are ca.reputation (CA_Reputation.lua of batman_CoreAITests). Tags "server" and "world": the authority only (solo, or
RST.server from an admin client), save rstest* in debug mode (the test baseline CA_Reputation.testSetLevel refuses
anything else). Solo campaign solo-lk and MP campaign mp.

    requester killed     a Living Knox test npc with a notebook fiche asks a test mission of the requester (and, in MP,
                         of the second player); the requester kills it with a lethal bat hit (real IsoZombie.Hit,
                         death attributed by LivingKnox.Bodies): the killer drops to "bad" (RequesterKilled, the npc
                         name), the team mate keeps his reputation (score unchanged, asked to his client in MP)
The test restores the reputation entry of the characters it touched and drops the outcomes it created
(RST_ReputationHelpers.lua of batman_CoreAITests).
Outside the game: tests/test_reputation.py, tests/test_lk_hostility.py (doubles).
]]

require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_CarnetHelpers"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecksRep"
require "RST/RST_ReputationHelpers"

local RP = RST.ReputationSuite
local N = RST.CarnetHelpers
local K = RST.LKHelpers

RST.suite("lk.reputation", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 400000 }, function(s)
    s.test("the killer of a requester drops to bad, the team mate is spared (E04-T07)", function(t)
        local c = RP.setup(t)
        local ready, why = RST.Fixtures.npcReady()
        if not ready then t:skip("no Living Knox test npc: " .. tostring(why)) end
        RP.guard(t, c, c.cid)
        RP.baseline(t, c, c.cid, "neutral")
        RP.mute(t, c)
        local _, mateName, mate = RP.second(t)
        if mate ~= nil then
            RP.guard(t, c, mate)
            RP.baseline(t, c, mate, "neutral")
        else
            t:note("solo or one client: no team mate (the MP campaign checks him)")
        end
        N.npcWithFiche(t, c.p, 2, function(t2, id, fiche, body)
            local members = { [c.cid] = "requester" }
            if mate ~= nil then members[mate] = tostring(mateName) end
            local m = RP.testMission(t2, c, fiche.id, members)
            local mateScore = mate and c.Rep.scoreOf(mate) or nil
            t2:waitUntil(K.standing(id), K.STAND_MS, function(t3)
                local z = K.B().find(id) or body
                t3:ok(z ~= nil, "npc body lost")
                local H = LivingKnox and LivingKnox.Health
                if H ~= nil and H.setBirth ~= nil then H.setBirth(id, 0.01) end
                local w = instanceItem("Base.BaseballBat")
                z:Hit(w, c.p, 100.0, false, 1.0)
                t3:waitUntil(function() return fiche.alive == false end, RP.DEATH_MS, function(t4)
                    t4:eq("cancelled_dead", m.state, "mission of the dead requester")
                    t4:eq("player", fiche.deathAttribution, "death attribution")
                    t4:eq("bad", c.Rep.level(c.cid), "level of the killer")
                    local reason = c.Rep.reasons(c.cid, 1)[1]
                    t4:eq("npc.requesterKilled", reason and reason.action, "reason of the killer")
                    t4:eq(fiche.name, reason and reason.reasonArgs[1], "name of the requester in the reason")
                    if mate ~= nil then
                        t4:eq(mateScore, c.Rep.scoreOf(mate), "score of the team mate")
                        t4:eq("neutral", c.Rep.level(mate), "level of the team mate")
                        c.Server.publish()
                        RP.readBy(t4, { mateName }, { refresh = true }, function(t5, res)
                            t5:eq("neutral", RP.firstData(res).level, "level read by the team mate client")
                        end)
                    end
                end, "the requester npc did not die after a lethal hit")
            end, "npc still on the floor")
        end)
    end, { timeoutMs = 120000 })
end)
