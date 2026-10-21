--[[
rs.factions.incident - targeted defence and decision on a truce (E09-T06, server/RadioSurvivor/RS_Factions.lua and
RS_Incidents.lua) on the running engine: a truce of the player's team with a group whose body is loaded near the player
is concluded (directly by RS_Factions.conclude), then a member of that group is HIT by the player (E01-T19: simulated on
the authority, LivingKnox.Bodies.onHitZombie called with the member's body, the player and a Base.BaseballBat, as the
OnHitZombie event of a real swing does; the test waits up to 10 s): the hit (fact "memberHit") opens an incident whose
author is the player, the player is no longer covered and becomes a target of rule "incident" of the target choice,
the agreement is unchanged. Then the decision: with the bridge running, the leader's model decides (the test waits up
to 120 s for the incident to close and notes the decision); without it, the incident stays open (no automatic break) and the test
applies a "maintain" decision itself (RS_Factions.decideIncident): agreement revision + 1, player covered again.
Two players (MP): the second member of the faction stays covered during the incident (check by hand with the
debug view of the group, see docs/annexes/conception/incidents.md).
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server) and "world" (the
private notebook state is written: test saves "rstest*" only). Asynchronous run (RST.start / RST.server). No group near
the player: a fixture group is created and removed (RST.LKGroup); notebook character bound when missing ("hello").
The real swing (OnHitZombie raised by the game on the owner of the body, then the authority) stays a manual check.
Cleanup: the agreement is removed (RS_Factions.cancelAgreement, which also closes the incident); an agreement already
there makes the test skip.
Tests 2 and 3 (ADR B10 criteria, RST_PeerChecksE09.lua): two close aggressions = one incident, bridge stopped = no
break, late reply of the leader refused through the real reply path, one change per valid decision (all modes); with
two clients (dedicated server, SKIP in solo or alone): defence against the author only, innocent member of the same
faction covered, third player apart. See the comments above the tests.
Outside the game: tests/test_incidents.py, tests/test_e09_suites.py.
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
    if type(F) ~= "table" or type(F.incidentFact) ~= "function" or type(Server) ~= "table" or not Server.store
            or not Server.store.data then
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

local HIT_WEAPON = "Base.BaseballBat"

local function openIncident(F, gid)
    for _, inc in ipairs(F.incidents()) do
        if inc.state == "open" and inc.group == gid then return inc end
    end
    return nil
end

-- Suite limit above the test one: the decision wait alone is 120 s (suite default 120 s: timeout in the MP campaign
-- of 2026-10-15 while the bridge got no answer from the model).
RST.suite("rs.factions.incident", { tags = { "server", "world" }, testTimeoutMs = 300000, timeoutMs = 900000 },
    function(s)
    s.test("hit under a truce: incident, defence against the author only, one decision", function(t0)
        local F, E = modules(t0)
        local p = Fx.player(t0)
        if not p then t0:skip("no target player") end
        -- E01-T19: notebook character bound when missing ("hello" asked directly), fixture group when none is near.
        local cid = RST.RSHelpers.character(t0, p)
        RST.LKGroup.ensure(t0, p, function(t)
            local gid, npc = loadedGroup(t, E)
            local team = F.idOf(p)
            if F.agreementOf(gid, team) then t:skip("an agreement of this team with " .. gid .. " already exists") end
            local neg, why = F.negotiation(p, gid)
            t:ok(neg ~= nil, "offer of the server: " .. tostring(why))
            local ok, reason = F.conclude(p, gid, "truce", { team = team, revision = neg.revision }, { character = cid })
            t:ok(ok, "concluded: " .. tostring(reason))
            t:defer(function() F.cancelAgreement(gid, team) end, "agreement removed")
            t:eq(true, F.covered(gid, cid, npc), "covered before the incident")
            -- E01-T19: the hit is simulated on the authority on behalf of the player: the OnHitZombie subscriber of
            -- Living Knox (LivingKnox.Bodies.onHitZombie, the one a real swing reaches) gets the body of the member,
            -- the player as wielder and a real melee weapon; it records the hit and publishes "memberHit".
            local body = E.Bodies.find(npc)
            t:ok(body ~= nil, "body of " .. tostring(npc) .. " not loaded on the authority")
            local weapon = instanceItem(HIT_WEAPON)
            t:ok(weapon ~= nil and instanceof(weapon, "HandWeapon"), HIT_WEAPON .. " is not a weapon here")
            E.Bodies.onHitZombie(body, p, nil, weapon)
            t:note("hit of " .. tostring(p:getUsername()) .. " on " .. npc .. " (" .. gid .. ") with " .. HIT_WEAPON
                .. ", simulated on the authority")
            t:waitUntil(function() return openIncident(F, gid) ~= nil end, 10000, function(t2)
                local inc = openIncident(F, gid)
                -- Account of the author: the user name on a server, the single key "solo" in solo (callerKey of
                -- RadioSurvivor_Server.lua; in-game run of 2026-10-13).
                local account = (type(isServer) == "function" and isServer()) and p:getUsername() or "solo"
                t2:eq(account, inc.authors[cid], "author = this player")
                t2:eq(false, F.covered(gid, cid, npc), "author no longer covered")
                local res = E.Hostility.chooseTarget(gid, npc, { { u = p:getUsername(), key = cid, d = 2 } })
                t2:eq("incident", res and res.target and res.target.reason, "author is a target (rule incident)")
                local a = F.agreementOf(gid, team)
                t2:eq("truce", a.kind, "agreement kept until a decision")
                t2:eq(1, a.revision)
                -- With the bridge, the leader decides; without it nothing changes: wait for either, 120 s at most.
                local deadline = getTimestampMs() + 120000
                t2:waitUntil(function() return openIncident(F, gid) == nil or getTimestampMs() >= deadline end, 130000,
                        function(t3)
                    local still = openIncident(F, gid)
                    if still == nil then
                        t3:eq(2, F.agreementOf(gid, team).revision, "one decision, one change")
                        local d = F.agreementOf(gid, team).decision
                        t3:note("decision of the model: " .. tostring(d and d.choice))
                        return
                    end
                    t3:eq(1, F.agreementOf(gid, team).revision, "no automatic change without a decision")
                    t3:eq(false, F.covered(gid, cid, npc), "defence kept while the incident is open")
                    local done, r = F.decideIncident(still.id, { revision = still.revision, agreementRevision = 1 },
                        "maintain", "", { npc = npc })
                    t3:ok(done, "maintain applied: " .. tostring(r))
                    t3:eq(2, F.agreementOf(gid, team).revision, "one decision, one change")
                    t3:eq(true, F.covered(gid, cid, npc), "covered again after the decision")
                    t3:note("no bridge decision in 120 s: maintain applied by the test")
                end, "decision of the leader, or 120 s without a bridge")
            end, "incident opened by the hit")
        end)
    end)

    -- E09-T06, ADR B10 criteria with one player (all modes; RST_PeerChecksE09.lua). A NEW fixture group (leader m-1,
    -- fighter m-2) and a truce of the player's team; the bridge is held "stopped" (RS_Initiatives bridge.down, what the
    -- notebook concludes after an unanswered request) while two close aggressions hit both members: ONE incident (two
    -- facts, two victims), the author is a target (rule incident) and no decision is asked nor applied: the truce is not
    -- broken (no automatic change). The bridge comes back: the decision request of the leader is held by the test, a
    -- third aggression comes meanwhile, then the reply "maintain" built on the older revision is read by the REAL reply
    -- path and refused ("incident revision changed"): incident open, agreement unchanged. A valid decision then changes
    -- the agreement ONCE (revision 2); the same decision again is refused (incident closed).
    s.test("B10: close aggressions one incident, bridge down no break, late reply refused, one change", function(t0)
        local F, E, Server = modules(t0)
        local R, E9 = RST.RSHelpers, RST.PeerChecksE09
        local p = Fx.player(t0)
        t0:ok(p ~= nil, "no target player")
        R.god(t0, p)
        local cid = R.character(t0, p)
        local account = (type(isServer) == "function" and isServer()) and p:getUsername() or "solo"
        E9.fixture(t0, p, function(t, gid, leaderNpc, mateNpc)
            local team = F.idOf(p)
            local neg, why = F.negotiation(p, gid)
            t:ok(neg ~= nil, "offer of the server: " .. tostring(why))
            local okC, whyC = F.conclude(p, gid, "truce", { team = team, revision = neg.revision }, { character = cid })
            t:ok(okC, "concluded: " .. tostring(whyC))
            t:defer(function() F.cancelAgreement(gid, team) end, "agreement removed")
            local Ini = Server.initiatives
            local was = { down = Ini.bridge.down, probeAt = Ini.bridge.probeAt }
            Ini.bridge.down, Ini.bridge.probeAt = true, getTimestampMs() + 3600000
            t:defer(function()
                Ini.bridge.down, Ini.bridge.probeAt = was.down, was.probeAt
            end, "bridge state of the notebook restored")
            local weapon = instanceItem(HIT_WEAPON)
            t:ok(weapon ~= nil and instanceof(weapon, "HandWeapon"), HIT_WEAPON .. " is not a weapon here")
            local function hit(tc, npc)
                local body = E.Bodies.find(npc)
                tc:ok(body ~= nil, "body of " .. tostring(npc) .. " not loaded on the authority")
                E.Bodies.onHitZombie(body, p, nil, weapon)
            end
            E9.fiche(t, Server, leaderNpc, function(t1, fl)
                local ctl = E9.intercept(t1)
                ctl.quiet({ [fl.id] = true })
                ctl.blackout = true
                local held = { hold = true }
                ctl.rule(function(req) return req.kind == "npc_incident" and req.npc == fl.id end, function(req)
                    if held.hold then return nil end
                    return E9.reply(req, { intent = "maintain", text = "We keep the truce." })
                end)
                hit(t1, leaderNpc)
                hit(t1, mateNpc)
                t1:waitUntil(function()
                    local inc = openIncident(F, gid)
                    return inc ~= nil and inc.count >= 2 and inc
                end, 10000, function(t2, inc)
                    t2:eq(account, inc.authors[cid], "author = this player")
                    t2:eq(true, inc.victims[leaderNpc] and inc.victims[mateNpc], "both victims in one incident")
                    local n = 0
                    for _, x in ipairs(F.incidents()) do if x.group == gid then n = n + 1 end end
                    t2:eq(1, n, "incidents of " .. gid .. " after two close aggressions")
                    t2:eq(false, F.covered(gid, cid, leaderNpc), "author no longer covered")
                    local res = E.Hostility.chooseTarget(gid, leaderNpc, { { u = p:getUsername(), key = cid, d = 2 } })
                    t2:eq("incident", res and res.target and res.target.reason, "author is a target (rule incident)")
                    t2:sleep(F.INCIDENT.SETTLE_MS + 3000, function(t3)
                        t3:eq(nil, E9.requestOf(Server, "npc_incident", fl.id), "decision asked while the bridge is down")
                        local still = openIncident(F, gid)
                        t3:ok(still ~= nil and still.id == inc.id, "incident closed without a decision")
                        local a = F.agreementOf(gid, team)
                        t3:eq("truce", a and a.kind, "truce broken without a decision (bridge down)")
                        t3:eq(1, a and a.revision, "agreement changed without a decision")
                        t3:eq(false, F.covered(gid, cid, leaderNpc), "defence dropped while the bridge is down")
                        Ini.bridge.down, ctl.blackout = false, false
                        t3:waitUntil(function() return E9.pendingOf(Server, "npc_incident", fl.id) end, 10000,
                            function(t4, reqI)
                            local b = Server.incidents.bindings[reqI.id]
                            t4:ok(b ~= nil and b.incident == inc.id, "decision request not bound to the incident")
                            local asked = b.revision
                            hit(t4, mateNpc)
                            t4:waitUntil(function()
                                local now = openIncident(F, gid)
                                return now ~= nil and now.revision > asked
                            end, 10000, function(t5)
                                held.hold = false
                                t5:waitUntil(function() return E9.settled({ Server = Server }, reqI) end, E9.REQUEST_MS,
                                    function(t6)
                                    local refused = nil
                                    for _, r in ipairs(Server.refusals) do
                                        if r.id == reqI.id then refused = r.reason end
                                    end
                                    t6:eq("incident revision changed", refused, "late reply of the leader")
                                    local open = openIncident(F, gid)
                                    t6:ok(open ~= nil and open.id == inc.id, "incident closed by a late reply")
                                    t6:eq(1, F.agreementOf(gid, team).revision, "agreement changed by a late reply")
                                    local ok1, r1 = F.decideIncident(open.id, { revision = open.revision,
                                        agreementRevision = 1 }, "maintain", "", { npc = fl.id })
                                    t6:ok(ok1, "valid decision refused: " .. tostring(r1))
                                    local ok2, r2 = F.decideIncident(open.id, { revision = open.revision,
                                        agreementRevision = 1 }, "maintain", "", { npc = fl.id })
                                    t6:eq(false, ok2, "the same decision applied twice")
                                    t6:eq("incident closed", r2, "refusal of the second decision")
                                    t6:eq(2, F.agreementOf(gid, team).revision, "one decision, one change")
                                    t6:eq(true, F.covered(gid, cid, leaderNpc), "covered again after the decision")
                                    t6:note("incident " .. inc.id .. ": " .. open.count .. " fact(s), late reply refused, "
                                        .. "one decision applied")
                                end, "late reply of the leader never read")
                            end, "third aggression not added to the incident")
                        end, "no decision asked once the bridge is back")
                    end)
                end, "one incident with both aggressions")
            end)
        end)
    end)

    -- E09-T06, ADR B10 with two clients (dedicated server; SKIP in solo or with one client): the requester (aggressor)
    -- and the second client (innocent member of the same vanilla faction) stand together; the requester hits a member of
    -- a group under truce with their team: the defence aims at the author only (the innocent member, even closer, stays
    -- covered and is never a target); then the second client leaves the faction: a third player, neither covered nor
    -- an author, never a target of rule incident. Bridge held "stopped" during the checks (no decision closes the
    -- incident meanwhile); a valid decision closes it at the end.
    s.test("B10 two players: defence against the author only, innocent member covered, third player apart", function(t0)
        local F, E, Server = modules(t0)
        local R, E9 = RST.RSHelpers, RST.PeerChecksE09
        local p1 = Fx.player(t0)
        t0:ok(p1 ~= nil, "no target player")
        local p2, u2 = E9.requireSecond(t0, "an innocent member and a third player")
        R.god(t0, p1)
        R.god(t0, p2)
        local u1 = p1:getUsername()
        E9.faction(t0, p1, u2, function(t1, f)
            local team = F.idOf(p1)
            t1:eq(team, F.idOf(p2), "both players in one team")
            local cid1, cid2 = R.character(t1, p1), R.character(t1, p2)
            Fx.movePlayer(t1, p2, p1:getX() + 1, p1:getY(), p1:getZ(), function(t2)
                E9.fixture(t2, p1, function(t3, gid, leaderNpc)
                    local neg, why = F.negotiation(p1, gid)
                    t3:ok(neg ~= nil, "offer of the server: " .. tostring(why))
                    local okC, whyC = F.conclude(p1, gid, "truce", { team = team, revision = neg.revision },
                        { character = cid1 })
                    t3:ok(okC, "concluded: " .. tostring(whyC))
                    t3:defer(function() F.cancelAgreement(gid, team) end, "agreement removed")
                    t3:eq(true, F.covered(gid, cid2, leaderNpc), "innocent member covered before")
                    local Ini = Server.initiatives
                    local was = { down = Ini.bridge.down, probeAt = Ini.bridge.probeAt }
                    Ini.bridge.down, Ini.bridge.probeAt = true, getTimestampMs() + 3600000
                    t3:defer(function()
                        Ini.bridge.down, Ini.bridge.probeAt = was.down, was.probeAt
                    end, "bridge state of the notebook restored")
                    E9.intercept(t3).blackout = true
                    local body = E.Bodies.find(leaderNpc)
                    t3:ok(body ~= nil, "body of " .. tostring(leaderNpc) .. " not loaded on the authority")
                    local weapon = instanceItem(HIT_WEAPON)
                    E.Bodies.onHitZombie(body, p1, nil, weapon)
                    t3:waitUntil(function() return openIncident(F, gid) end, 10000, function(t4, inc)
                        t4:eq(u1, inc.authors[cid1], "author = the requester")
                        t4:eq(nil, inc.authors[cid2], "the innocent member is an author")
                        t4:eq(false, F.covered(gid, cid1, leaderNpc), "author still covered")
                        t4:eq(true, F.covered(gid, cid2, leaderNpc), "innocent member lost the protection")
                        local res = E.Hostility.chooseTarget(gid, leaderNpc,
                            { { u = u1, key = cid1, d = 3 }, { u = u2, key = cid2, d = 1 } })
                        t4:eq(u1, res and res.target and res.target.u, "target of the defence")
                        t4:eq("incident", res and res.target and res.target.reason, "rule of the defence")
                        for _, e in ipairs(res and res.list or {}) do
                            t4:ok(e.u ~= u2, "the innocent member is a target (" .. tostring(e.reason) .. ")")
                        end
                        f:removePlayer(u2)
                        F.sync(true)
                        t4:ok(F.idOf(p2) ~= team, "the second client still in the team after leaving the faction")
                        t4:eq(false, F.covered(gid, cid2, leaderNpc), "third player covered by the truce")
                        t4:eq(false, F.isIncidentAuthor(gid, cid2), "third player is an author")
                        local res2 = E.Hostility.chooseTarget(gid, leaderNpc, { { u = u2, key = cid2, d = 1 } })
                        for _, e in ipairs(res2 and res2.list or {}) do
                            t4:ok(e.reason ~= "incident", "third player aimed at by rule incident")
                        end
                        local okD, whyD = F.decideIncident(inc.id, { revision = inc.revision, agreementRevision = 1 },
                            "maintain", "", {})
                        t4:ok(okD, "decision: " .. tostring(whyD))
                        t4:eq(true, F.covered(gid, cid1, leaderNpc), "author covered again after the decision")
                        t4:note("incident " .. inc.id .. ": defence against " .. u1 .. " only; " .. u2
                            .. " covered as a member, apart as a third player")
                    end, "incident opened by the hit")
                end)
            end)
        end)
    end)
end)
