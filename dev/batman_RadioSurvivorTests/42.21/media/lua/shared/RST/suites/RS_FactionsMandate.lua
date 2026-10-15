--[[
rs.factions.mandate - team identifier of the mod and negotiation mandates (E09-T03, server/RadioSurvivor/
RS_Factions.lua) with real clients of a dedicated server:
    MP  the requester client creates a vanilla faction through the faction panel packet (RST.Steps "rs.faction":
        sendFactionCreate), the server adds the second client as a member (Faction:addPlayer, what an accepted
        invitation does on the server; the invitation dialog itself is not driven). Both players share one team id.
        The member without mandate cannot conclude: canConclude false ("no_mandate"), no offer (negotiation), the
        conclusion refused ("no mandate"), and its own notebook command "mandate" to designate itself is refused
        ("MandateOwner", read on its client). The owner concludes a truce with a test group id, then renames the faction
        through the panel packet (sendFactionChangeTitle): same team id for both players, same agreement (id, kind),
        new name in the team record. The owner designates the member by the notebook command (Team tab): the member
        may conclude ("negotiator"); withdrawn, it may not any more.
    solo the player forms a personal team and may conclude as its owner (no vanilla faction in solo).
Tags "server" and "world": the authority (solo, or RST.server from an admin client), save rstest*. MP with two clients:
autoclient.py --mp --clients 2 --server-suite rs.factions.mandate --server-tags world.
Cleanup: the agreement is removed (RS_Factions.cancelAgreement), the faction disbanded by its owner (sendFactionDisband;
removed from Faction.getFactions() by the server if still there). Outside the game: tests/test_rs_mp_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_PeerChecksRadio"

local PR = RST.PeerRadio
local Steps = RST.Steps
local GID = "grp-990001"   -- test group id: RS_Factions checks its form only; never a group of the engine

local function modules(t)
    if type(isClient) == "function" and isClient() then t:skip("RS_Factions is authority only (solo or server)") end
    local okF, F = pcall(require, "RadioSurvivor/RS_Factions")
    t:ok(okF and type(F) == "table" and type(F.canConclude) == "function", "RadioSurvivor/RS_Factions not loaded")
    local Server = RS_CarnetServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (RS_CarnetServer)")
    end
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    return F, Server, p
end

local function recordOf(F, id)
    for _, rec in ipairs(F.list()) do if rec.id == id then return rec end end
    return nil
end

local function testName(prefix)
    return prefix .. tostring(ZombRand(10000, 99999))
end

RST.suite("rs.factions.mandate", { tags = { "server", "world" }, testTimeoutMs = 120000 }, function(s)
    s.test("solo: the player owns a personal team and may conclude (E09-T03)", function(t)
        local F, _, p = modules(t)
        if type(isServer) == "function" and isServer() then t:skip("solo only (factions are covered by the MP test)") end
        local id = F.idOf(p)
        t:ok(type(id) == "string" and string.find(id, "^fac%-%d+$") ~= nil, "team id " .. tostring(id))
        local ok, role, team = F.canConclude(p)
        t:eq(true, ok, "may conclude")
        t:eq("owner", role, "role")
        t:eq(id, team, "team of canConclude")
        t:eq(id, F.idOf(p), "team id stable")
    end)

    s.test("renamed faction keeps its id and agreements; a member without mandate cannot conclude (E09-T03)", function(t)
        local F, _, p1 = modules(t)
        if not (type(isServer) == "function" and isServer()) then
            t:skip("vanilla factions exist on a dedicated server only (MP campaign, two clients)")
        end
        local others = Steps.others(t)
        local u2 = others[1]
        local p2 = u2 and Steps.playerOf(u2)
        if p2 == nil then t:skip("no second client online (autoclient.py --mp --clients 2)") end
        local u1 = p1:getUsername()
        if Faction.getPlayerFaction(u1) ~= nil or Faction.getPlayerFaction(u2) ~= nil then
            t:skip("a test account is already in a faction")
        end
        local name, renamed = testName("RST"), testName("RSR")
        Steps.ask(t, "rs.faction", { op = "create", name = name }, { target = "requester", timeoutMs = PR.FACTION_MS },
            function(t2)
            t2:defer(function(tc)
                local f = Faction.getPlayerFaction(u1)
                if f == nil then return end
                Steps.ask(tc, "rs.faction", { op = "disband" }, { target = "requester", timeoutMs = PR.FACTION_MS,
                    assert = false }, function(tc2)
                    tc2:waitQuiet(function() return not Faction.getFactions():contains(f) end, PR.FACTION_MS,
                        function() end, "faction still there")
                end)
            end, "test faction disbanded by its owner")
            t2:waitUntil(function() return Faction.getPlayerFaction(u1) end, PR.FACTION_MS, function(t3, f)
                f:addPlayer(u2)
                t3:ok(f:isMember(u2), u2 .. " not added to the faction")
                F.sync(true)
                local team = F.idOf(p1)
                t3:eq(team, F.idOf(p2), "both players in one team")
                local ok2, why2 = F.canConclude(p2)
                t3:eq(false, ok2, "member without mandate may conclude")
                t3:eq("no_mandate", why2, "refusal reason")
                local offer, whyOffer = F.negotiation(p2, GID)
                t3:eq(nil, offer, "terms offered to a member without mandate")
                t3:eq("no_mandate", whyOffer, "reason of no offer")
                local okc, whyc = F.conclude(p2, GID, "truce", { team = team, revision = 0 }, {})
                t3:eq(false, okc, "conclusion by a member without mandate")
                t3:eq("no mandate", whyc, "conclusion refusal")
                t3:eq(nil, F.agreementOf(GID, team), "agreement written by a refused conclusion")
                local ok1, why1, a = F.conclude(p1, GID, "truce", { team = team, revision = 0 }, {})
                t3:ok(ok1, "owner conclusion: " .. tostring(why1))
                t3:defer(function() F.cancelAgreement(GID, team) end, "test agreement removed")
                Steps.ask(t3, "carnet.mandate", { member = u2, action = "grant" }, { target = { u2 }, timeoutMs = 8000 },
                    function(t4, res)
                    local e = res.by[u2]
                    t4:eq("MandateOwner", e and e.data and e.data.lastError, "self-designation of the member")
                    t4:eq(false, (F.canConclude(p2)), "member may conclude after its own designation")
                    Steps.ask(t4, "rs.faction", { op = "rename", name = renamed },
                        { target = "requester", timeoutMs = PR.FACTION_MS }, function(t5)
                        t5:waitUntil(function() return f:getName() == renamed end, PR.FACTION_MS, function(t6)
                            F.sync(true)
                            t6:eq(team, F.idOf(p1), "team id of the owner after the rename")
                            t6:eq(team, F.idOf(p2), "team id of the member after the rename")
                            local now = F.agreementOf(GID, team)
                            t6:ok(now ~= nil, "agreement lost by the rename")
                            t6:eq(a.id, now.id, "agreement id")
                            t6:eq("truce", now.kind, "agreement kind")
                            local rec = recordOf(F, team)
                            t6:eq(renamed, rec and rec.name, "name of the team record")
                            Steps.ask(t6, "carnet.mandate", { member = u2, action = "grant" },
                                { target = "requester", timeoutMs = 8000 }, function(t7, r7)
                                local e7 = r7.by[u1]
                                t7:eq(nil, e7 and e7.data and e7.data.lastError, "designation by the owner refused")
                                local okg, roleg = F.canConclude(p2)
                                t7:eq(true, okg, "designated member may conclude")
                                t7:eq("negotiator", roleg, "role of the designated member")
                                Steps.ask(t7, "carnet.mandate", { member = u2, action = "revoke" },
                                    { target = "requester", timeoutMs = 8000 }, function(t8)
                                    t8:eq(false, (F.canConclude(p2)), "member may still conclude after the withdrawal")
                                end)
                            end)
                        end, "faction never renamed on the server (FactionChangeTitle)")
                    end)
                end)
            end, "faction never created on the server (FactionCreate refused: server option Faction?)")
        end)
    end)
end)
