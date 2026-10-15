--[[
rs.factions.accord - faction agreements with a Living Knox group (E09-T05, server/RadioSurvivor/RS_Factions.lua) on
the running engine: the server offers fixed terms to a player who may conclude for its team (here the player's own
team: owner of its faction, or of its personal team in solo), a truce is concluded with a group whose body is loaded
near the player (directly by RS_Factions.conclude: the model's decision is the bridge's part, proven outside the
game), the target choice consults the hook at once (the player is covered, never a target), the agreement stays
"pending" until the next decisions of the group members (LivingKnox.Decisions.aims), then becomes "applicable"
(the notebook announces it on screen: "Truce with <group> now in force"); the attitude of the group toward the
player is unchanged.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (the
private notebook state is written: test saves "rstest*" only). Asynchronous run (RST.start / RST.server). Next to a
group of the initial population (LK08-T05) that group is used; otherwise a fixture group is created near the player and
removed at the end (RST.LKGroup, RST_LKGroupFixture.lua, E01-T19). The notebook character is bound when missing
("hello" asked directly, RST.RSHelpers.character).
Cleanup: the agreement is removed (RS_Factions.cancelAgreement); an agreement already there makes the test skip.
Test 2 (all modes): two conclusions built on one revision, only the first applied. Test 3 (dedicated server, two
clients; SKIP in solo or with one client): a member without mandate gets no offer and concludes nothing, then two
negotiators of one faction speak to the leader at once: one agreement (RST_PeerChecksE09.lua, replies of the test
read by the real notebook reply path, no bridge needed).
Outside the game: tests/test_agreements.py, tests/test_e09_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKGroupFixture"
require "RST/RST_RSHelpers"
require "RST/RST_PeerChecksE09"

local Fx = RST.Fixtures

local function modules(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Factions is authority only (solo or dedicated server)")
    end
    local E = LivingKnox
    if type(E) ~= "table" or type(E.Config) ~= "table" or not E.Config.isEnabled() then
        t:skip("Living Knox is disabled (sandbox LivingKnox.Enabled)")
    end
    if type(E.Hostility) ~= "table" or type(E.Decisions) ~= "table" or type(E.Decisions.aims) ~= "function" then
        t:skip("Living Knox server part not loaded here")
    end
    local F = require "RadioSurvivor/RS_Factions"
    local Server = RS_CarnetServer
    if type(F) ~= "table" or type(Server) ~= "table" or not Server.store or not Server.store.data then
        t:skip("notebook server state not ready")
    end
    return F, E, Server
end

-- First loaded body of a Living Knox group: gid, npc id (the fixture group of RST_LKGroupFixture.lua is created
-- before when none is loaded: E01-T19).
local function loadedGroup(t, E)
    local P = require "RadioSurvivor/RS_NPCProvider"
    local ids = {}
    for id in pairs(P.objects()) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local gid = E.Groups.findNpc(id)
        if gid then return gid, id end
    end
    t:skip("no body of a Living Knox group loaded near the player: go next to a group and run again")
end

RST.suite("rs.factions.accord", { tags = { "server", "world" }, testTimeoutMs = 300000, timeoutMs = 600000 },
    function(s)
    s.test("truce concluded: covered at once, applicable after the next decisions, attitude unchanged", function(t0)
        local F, E = modules(t0)
        local p = Fx.player(t0)
        if not p then t0:skip("no target player") end
        -- E01-T19: notebook character bound when missing ("hello" asked directly), fixture group when none is near.
        local cid = RST.RSHelpers.character(t0, p)
        RST.LKGroup.ensure(t0, p, function(t)
            local gid, npc = loadedGroup(t, E)
            local team = F.idOf(p)
            if F.agreementOf(gid, team) then t:skip("an agreement of this team with " .. gid .. " already exists") end
            local before = E.Hostility.get(gid, cid)
            local neg, why = F.negotiation(p, gid)
            t:ok(neg ~= nil, "offer of the server: " .. tostring(why))
            t:eq(team, neg.team)
            t:eq("none", neg.current)
            t:ok(neg.terms.truce ~= nil and neg.terms.alliance ~= nil, "truce and alliance offered")
            local ok, reason, a = F.conclude(p, gid, "truce", { team = team, revision = neg.revision }, { character = cid })
            t:ok(ok, "concluded: " .. tostring(reason))
            t:defer(function() F.cancelAgreement(gid, team) end, "agreement removed")
            t:eq("pending", a.state)
            t:eq(true, E.Hostility.isCovered(gid, cid, npc), "player covered by the hook")
            local res = E.Hostility.chooseTarget(gid, npc, { { u = p:getUsername(), key = cid, d = 2 } })
            t:eq(nil, res and res.target, "the player is never a target")
            t:waitUntil(function()
                local now = F.agreementOf(gid, team)
                return now ~= nil and now.state == "applicable"
            end, 60000, function(t2)
                local now = F.agreementOf(gid, team)
                t2:eq("truce", now.kind)
                t2:eq(1, now.revision)
                local after = E.Hostility.get(gid, cid)
                t2:eq(before.level, after.level, "attitude level unchanged")
                t2:note("agreement " .. now.id .. " applicable " .. tostring(now.appliedAt - now.concludedAt)
                    .. " ms after its conclusion")
            end, "agreement confirmed by the next decisions of the group")
        end)
    end)

    -- E09-T05: two conclusions built on one revision of the agreement (two offers read at the same time): only the first
    -- is applied, the second is refused on its revision. Test group id: RS_Factions checks its form only.
    s.test("two conclusions on one revision: only the first is applied (E09-T05)", function(t)
        local F = modules(t)
        local p = Fx.player(t)
        if not p then t:skip("no target player") end
        local cid = RST.RSHelpers.character(t, p)
        local gid = "grp-990002"
        local team = F.idOf(p)
        t:ok(F.agreementOf(gid, team) == nil, "an agreement of this team with " .. gid .. " already exists")
        t:defer(function() F.cancelAgreement(gid, team) end, "test agreement removed")
        local neg, why = F.negotiation(p, gid)
        t:ok(neg ~= nil, "offer of the server: " .. tostring(why))
        local expect = { team = team, revision = neg.revision }
        local ok1, why1 = F.conclude(p, gid, "truce", expect, { character = cid })
        local ok2, why2 = F.conclude(p, gid, "alliance", expect, { character = cid })
        t:ok(ok1, "first conclusion: " .. tostring(why1))
        t:eq(false, ok2, "second conclusion on the same revision applied")
        t:eq("agreement revision changed", why2, "refusal of the second conclusion")
        local a = F.agreementOf(gid, team)
        t:eq("truce", a and a.kind, "agreement kind")
        t:eq(1, a and a.revision, "agreement revision")
    end)

    -- E09-T05 with two clients (RST_PeerChecksE09.lua): the requester owns a vanilla faction, the second client is a
    -- member. Through the REAL reply path of the notebook (replies put in the bridge reply file by the test): the member
    -- without mandate speaking to the leader gets no agreement offer and its "negotiate" concludes nothing; once
    -- designated negotiator, it speaks to the leader at the same time as the owner (both requests built on revision
    -- 0, both replies released together: "negotiate truce" and "negotiate alliance"): ONE agreement, revision 1, both
    -- lines kept (E09-T09).
    s.test("two negotiators at once: one agreement; a member without mandate concludes nothing (E09-T05)", function(t0)
        local F, _, Server = modules(t0)
        local R, E9 = RST.RSHelpers, RST.PeerChecksE09
        local C = require "RadioSurvivor/RS_Config"
        local p1 = Fx.player(t0)
        t0:ok(p1 ~= nil, "no target player")
        local p2, u2 = E9.requireSecond(t0, "two negotiators")
        R.god(t0, p1)
        R.god(t0, p2)
        local stamp = tostring(getTimestampMs() % 100000)
        E9.faction(t0, p1, u2, function(t1)
            local team = F.idOf(p1)
            t1:eq(team, F.idOf(p2), "both players in one team")
            Fx.movePlayer(t1, p2, p1:getX() + 1, p1:getY(), p1:getZ(), function(t2)
                local a1 = E9.who(t2, p1, "owner")
                local a2 = E9.who(t2, p2, "client " .. u2)
                E9.fixture(t2, p1, function(t3, gid, leaderNpc)
                    t3:ok(F.agreementOf(gid, team) == nil, "an agreement with the new fixture group already exists")
                    t3:defer(function() F.cancelAgreement(gid, team) end, "agreement removed")
                    E9.fiche(t3, Server, leaderNpc, function(t4, fl)
                        local ctl = E9.intercept(t4)
                        ctl.quiet({ [fl.id] = true })
                        local plan = {}
                        ctl.rule(function(req)
                            return req.kind == "npc_talk" and req.npc == fl.id and plan[req.text] ~= nil
                        end, function(req)
                            local w = plan[req.text]
                            if w.hold then return nil end
                            return E9.reply(req, { intent = "negotiate", offer = w.kind })
                        end)
                        local c = { Server = Server, C = C, fiche = fl, npc = leaderNpc }
                        local textM = "RST mandate " .. stamp
                        local textA, textB = "RST owner " .. stamp, "RST negotiator " .. stamp
                        plan[textM] = { kind = "truce" }
                        plan[textA] = { kind = "truce", hold = true }
                        plan[textB] = { kind = "alliance", hold = true }
                        local okN, whyN = F.negotiation(p2, gid)
                        t4:eq(nil, okN, "terms offered to a member without mandate")
                        t4:eq("no_mandate", whyN, "reason of no offer")
                        E9.selectBy(t4, a2, c, function(t5)
                            t5:ok(E9.acquainted(c, a2.cid) ~= nil, "no contact of " .. a2.label .. " with the leader")
                            E9.talkBy(t5, a2, c, textM, function(t6, reqM)
                                t6:eq(nil, reqM.context.negotiation, "agreement offered to a member without mandate")
                                t6:waitUntil(function() return E9.settled(c, reqM) end, E9.REQUEST_MS, function(t7)
                                    t7:ok(E9.heard(Server, a2.cid, fl, reqM.id) ~= nil, "member: reply not kept")
                                    t7:eq(nil, F.agreementOf(gid, team), "agreement concluded by a member without mandate")
                                    local okG, whyG = F.designate(p1, u2, true)
                                    t7:ok(okG, "designation of " .. u2 .. ": " .. tostring(whyG))
                                    t7:defer(function() F.designate(p1, u2, false) end, "mandate withdrawn")
                                    E9.selectBy(t7, a1, c, function(t8)
                                        t8:ok(E9.acquainted(c, a1.cid) ~= nil, "no contact of the owner with the leader")
                                        E9.talkBy(t8, a1, c, textA, function(t9, reqA)
                                            local negA = reqA.context.negotiation
                                            t9:ok(negA ~= nil and negA.role == "owner", "no agreement offered to the owner")
                                            E9.talkBy(t9, a2, c, textB, function(t10, reqB)
                                                local negB = reqB.context.negotiation
                                                t10:ok(negB ~= nil, "no agreement offered to the designated negotiator")
                                                t10:eq("negotiator", negB.role, "role of the second client")
                                                t10:eq(team, Server.collectives[reqA.id].team, "team of the owner")
                                                t10:eq(team, Server.collectives[reqB.id].team, "team of the negotiator")
                                                t10:eq(0, Server.collectives[reqA.id].revision, "owner revision")
                                                t10:eq(0, Server.collectives[reqB.id].revision, "negotiator revision")
                                                plan[textA].hold, plan[textB].hold = false, false
                                                t10:waitUntil(function()
                                                    return E9.settled(c, reqA) and E9.settled(c, reqB)
                                                end, E9.REQUEST_MS * 2, function(t11)
                                                    local a = F.agreementOf(gid, team)
                                                    t11:ok(a ~= nil, "no agreement concluded")
                                                    t11:eq(1, a.revision, "one conclusion applied")
                                                    t11:eq("truce", a.kind, "the first reply read wins (owner, truce)")
                                                    local n = 0
                                                    for _, x in ipairs(F.agreements()) do
                                                        if x.group == gid then n = n + 1 end
                                                    end
                                                    t11:eq(1, n, "agreements with " .. gid)
                                                    t11:ok(E9.heard(Server, a1.cid, fl, reqA.id) ~= nil,
                                                        "owner reply not kept")
                                                    t11:ok(E9.heard(Server, a2.cid, fl, reqB.id) ~= nil,
                                                        "negotiator reply not kept (E09-T09)")
                                                    t11:note("agreement " .. a.id .. " (" .. a.kind .. ") signed by "
                                                        .. tostring(a.signed and a.signed.account))
                                                end, "replies of the two negotiators never read")
                                            end)
                                        end)
                                    end)
                                end, "reply of the member without mandate never read")
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
