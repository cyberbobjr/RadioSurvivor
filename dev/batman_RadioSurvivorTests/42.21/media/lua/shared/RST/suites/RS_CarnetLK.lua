--[[
rs.carnet.lk - Living Knox provider of the notebook (E17-T03, shared/RadioSurvivor/RS_LivingKnox.lua) on the running
engine: provider registered when Living Knox is enabled, bodies loaded here named by their stable NPC id "lk-<n>",
records of the authority (signature, group "grp-<n>", name), public context for the LLM without any story secret or
home, and (suite rs.carnet.lk.supply) the supply offers of the groups checked against the real item scripts.
Tags "server" (authority only: solo, or RST.server from an admin client of a dedicated server). rs.carnet.lk reads
only, except the fixture group below. rs.carnet.lk.supply is also tagged "world": asking the offers opens them lazily
in the group registry (LivingKnox.API.missionOffers writes it), so it only runs on a test save ("rstest*"). No
delivery, no fiche, no notebook state: the full journey (selection, talk, offer, deliveries, death) is the manual protocol of
docs/annexes/tests/tests-en-jeu.md and tests/test_carnet.py (LivingKnoxCarnetTests) outside the game.
Bodies are those loaded near the player: next to a group of the initial population (LK08-T05) they are used as they
are; otherwise, on a world run (save rstest*: solo test save, or the MP test server), the tests that need a group
body create one near the player (RST.LKGroup, RST_LKGroupFixture.lua: settlers group, two members, removed at the
end) instead of a SKIP (E01-T19). Outside a world run, no group near the player is still a SKIP.
rs.carnet.leader (E10-T02, tags "server" and "world"; own campaign entry: outside the rs.carnet.lk prefix): member,
death and succession checked through the real reply path of the notebook with replies of the test
(RST_PeerChecksE09.lua), see the comment above the suite. Outside the game: tests/test_e09_suites.py.
]]

require "RST/RST"
require "RST/RST_LKGroupFixture"
require "RST/RST_RSHelpers"
require "RST/RST_PeerChecksE09"

local function provider(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the provider records are authority only (solo or dedicated server)")
    end
    local P = require "RadioSurvivor/RS_NPCProvider"
    local E = LivingKnox
    if type(E) ~= "table" or type(E.Config) ~= "table" or not E.Config.isEnabled() then
        t:skip("Living Knox is disabled (sandbox LivingKnox.Enabled)")
    end
    if type(E.API) ~= "table" or type(E.Groups) ~= "table" then t:skip("Living Knox server part not loaded here") end
    return P, E
end

-- Loaded Living Knox bodies with a group, by id; skip when none is loaded.
local function grouped(t, P, E)
    local out, n = {}, 0
    for id in pairs(P.objects()) do
        local gid = E.Groups.findNpc(id)
        if gid then out[id], n = gid, n + 1 end
    end
    if n == 0 then t:skip("no body of a Living Knox group loaded near the player: go next to a group and run again") end
    return out
end

-- E01-T19: body(ies) of a group loaded near the player first (the fixture group when none is), then after(t2).
local function withGroup(t, after)
    RST.LKGroup.ensure(t, nil, function(t2) return after(t2) end)
end

local function contains(text, part)
    return type(text) == "string" and type(part) == "string" and part ~= "" and string.find(text, part, 1, true) ~= nil
end

-- Every string of a plain table, concatenated (keys and values).
local function flatten(v, out)
    out = out or {}
    if type(v) == "table" then
        for k, x in pairs(v) do
            out[#out + 1] = tostring(k)
            flatten(x, out)
        end
    else
        out[#out + 1] = tostring(v)
    end
    return out
end

RST.suite("rs.carnet.lk", { tags = { "server" }, testTimeoutMs = 90000, timeoutMs = 300000 }, function(s)
    s.test("Living Knox is the notebook NPC provider", function(t)
        local P = provider(t)
        t:eq("livingknox", P.active().name)
        t:eq(true, P.available())
        t:eq("function", type(P.active().supplies), "supplies operation")
    end)

    s.test("bodies are named by their stable NPC id, records of the authority", function(t0)
        local P, E = provider(t0)
        withGroup(t0, function(t)
            local count = 0
            for id, body in pairs(P.objects()) do
                count = count + 1
                t:ok(string.match(id, "^lk%-%d+$") ~= nil, "provider id " .. tostring(id))
                t:eq(id, P.id(body), "id of the body of " .. id)
                t:eq(true, E.Bodies.inWorld(body), "body of " .. id .. " in the cell")
                local record = P.npc(id)
                t:ok(record ~= nil, "record of " .. id)
                t:eq("lk:" .. id, record.signature)
                t:ok(type(record.name) == "string" and record.name ~= "", "name of " .. id)
                local gid = E.Groups.findNpc(id)
                t:eq(gid or "", record.group, "group of " .. id)
                if gid then t:ok(string.match(gid, "^grp%-%d+$") ~= nil, "group id " .. gid) end
            end
            if count == 0 then t:skip("no Living Knox body loaded near the player") end
            t:note(count .. " body(ies) checked")
        end)
    end)

    s.test("LLM context: public story, no secret, no home", function(t0)
        local P, E = provider(t0)
        withGroup(t0, function(t)
            for id, gid in pairs(grouped(t, P, E)) do
                local g = E.Groups.get(gid)
                local ctx = P.context(id, nil, "EN")
                t:ok(type(ctx) == "table" and ctx.member == true, "context of " .. id)
                t:eq(g.name, ctx.group)
                t:eq(nil, ctx.area, "area in the context")
                t:eq(nil, ctx.home, "home in the context")
                local text = table.concat(flatten(ctx), " ")
                if g.home then
                    t:ok(not contains(text, tostring(g.home.x)) and not contains(text, tostring(g.home.y)),
                        "home coordinates of " .. gid .. " in the context")
                end
                local story = g.storySeed and E.Stories.compose(g.type, g.storySeed)
                if story then
                    t:eq(story.summary.en, ctx.summary, "public summary of " .. gid)
                    for _, secret in ipairs(story.secrets) do
                        t:ok(not contains(text, secret.en) and not contains(text, secret.fr), "secret of " .. gid)
                    end
                end
            end
        end)
    end)

    -- E10-T02: leader of the registry and composition fingerprint (read only, computed: nothing written).
    s.test("leader and composition of the loaded groups", function(t0)
        local P, E = provider(t0)
        withGroup(t0, function(t)
            for id, gid in pairs(grouped(t, P, E)) do
                local c = P.composition(id)
                local g = E.Groups.get(gid)
                local _, mid = E.Groups.findNpc(id)
                local api = E.API.composition(gid)
                t:ok(type(c) == "table", "composition of " .. id)
                t:eq(gid, c.ref, "group of " .. id)
                t:eq(api.key, c.key, "fingerprint of " .. gid)
                t:eq(api.key, E.API.composition(gid).key, "fingerprint computed twice")
                t:eq(g.leader ~= nil and g.leader == mid, c.leader, "leader flag of " .. id)
                t:eq(nil, g.composition, "stored composition field in " .. gid)
                t:note(id .. " in " .. gid .. (c.leader and " (leader)" or "") .. ": " .. c.key)
            end
        end)
    end)
end)

RST.suite("rs.carnet.lk.supply", { tags = { "server", "world" }, testTimeoutMs = 90000 }, function(s)
    s.test("supply offers of the loaded groups use real items", function(t0)
        local P, E = provider(t0)
        withGroup(t0, function(t)
            local offers = 0
            for id, gid in pairs(grouped(t, P, E)) do
                for _, o in ipairs(P.supplies(id, "rst-character")) do
                    offers = offers + 1
                    t:eq(gid, o.ref)
                    t:ok(string.match(o.offer, "^grp%-%d+%-%a+%-%d+$") ~= nil, "offer id " .. tostring(o.offer))
                    t:ok(o.remaining >= 1 and o.remaining <= o.value, "remaining value of " .. o.offer)
                    t:ok(#o.items > 0, "items of " .. o.offer)
                    for _, it in ipairs(o.items) do
                        t:ok(getScriptManager():FindItem(it.type) ~= nil, "item script " .. tostring(it.type))
                    end
                    if o.reward then
                        t:ok(getScriptManager():FindItem(o.reward.type) ~= nil,
                            "reward script " .. tostring(o.reward.type))
                    end
                    t:eq(true, P.supplyOpen(o.ref, o.offer), "offer open " .. o.offer)
                    t:note(o.offer .. ": " .. o.need .. " level " .. o.level .. ", " .. o.remaining .. " V left")
                end
            end
            if offers == 0 then t:note("no open offer: the loaded groups have no need under the threshold") end
        end)
    end)
end)

-- E10-T02 in game (RST_PeerChecksE09.lua): leader of the registry and collective intentions through the REAL reply
-- path of the notebook, with replies put in the bridge reply file by the test (the model's decision is not awaited,
-- no bridge needed). A NEW fixture group (leader m-1, fighter m-2) near the requester; the requester client selects
-- and speaks with the notebook (acquainted: ACQUAINT_EXCHANGES):
--   member     m-2: the request names the leader (context.collective member + leaderName), carries no agreement offer
--              and no group mission; a reply "negotiate truce" is kept (line heard) and concludes nothing;
--   death      m-1: the request carries the agreement offer, bound to the composition; m-2 dies (registry,
--              LivingKnox.Groups.markDead) before the reply: "negotiate truce" is ignored (composition changed), the
--              line is kept (E09-T09), no agreement;
--   succession a member m-3 joins, m-1 speaks again; m-3 becomes the leader before the reply: ignored (no longer the
--              leader), line kept, no agreement.
-- Tags "server" and "world" (fixture group, notebook state written: test saves rstest*). Cleanup: group removed,
-- agreement removed if any.
RST.suite("rs.carnet.leader", { tags = { "server", "world" }, testTimeoutMs = 240000, timeoutMs = 300000 },
    function(s)
    s.test("a member never concludes; a reply after a death or a succession concludes nothing (E10-T02)", function(t0)
        local _, E = provider(t0)
        local R, E9 = RST.RSHelpers, RST.PeerChecksE09
        local Server = R.notebook(t0)
        local C = require "RadioSurvivor/RS_Config"
        local F = require "RadioSurvivor/RS_Factions"
        local p = RST.Fixtures.player(t0)
        t0:ok(p ~= nil, "no target player")
        R.god(t0, p)
        local me = E9.who(t0, p, "requester")
        local stamp = tostring(getTimestampMs() % 100000)
        E9.fixture(t0, p, function(t, gid, leaderNpc, mateNpc)
            E9.fiche(t, Server, leaderNpc, function(t1, fl)
                E9.fiche(t1, Server, mateNpc, function(t2, fm)
                    local team = F.idOf(p)
                    t2:ok(F.agreementOf(gid, team) == nil, "an agreement with the new fixture group already exists")
                    t2:defer(function() F.cancelAgreement(gid, team) end, "agreement of the fixture group removed")
                    local ctl = E9.intercept(t2)
                    ctl.quiet({ [fl.id] = true, [fm.id] = true })
                    local plan = {}
                    ctl.rule(function(req)
                        return req.kind == "npc_talk" and plan[req.text] ~= nil
                    end, function(req)
                        local w = plan[req.text]
                        if w.hold then return nil end
                        return E9.reply(req, { intent = "negotiate", offer = "truce" })
                    end)
                    local cm = { Server = Server, C = C, fiche = fm, npc = mateNpc }
                    local cl = { Server = Server, C = C, fiche = fl, npc = leaderNpc }
                    local textM, textD, textS = "RST member " .. stamp, "RST death " .. stamp, "RST heir " .. stamp
                    plan[textM] = { hold = false }
                    plan[textD] = { hold = true }
                    plan[textS] = { hold = true }
                    local function noAgreement(tc, what)
                        tc:eq(nil, F.agreementOf(gid, team), what .. ": agreement concluded")
                    end
                    E9.selectBy(t2, me, cm, function(t3)
                        t3:ok(E9.acquainted(cm, me.cid) ~= nil, "no contact with the member after the selection")
                        E9.talkBy(t3, me, cm, textM, function(t4, reqM)
                            local col = reqM.context and reqM.context.collective
                            t4:eq("member", col and col.speaker, "member request: speaker")
                            t4:ok(col ~= nil and type(col.leaderName) == "string" and col.leaderName ~= "",
                                "member request: the leader is not named")
                            t4:eq(nil, reqM.context.negotiation, "member request: agreement offered to a member")
                            for key, terms in pairs(reqM.offers or {}) do
                                t4:ok(type(terms) ~= "table" or terms.kind ~= "supply",
                                    "member request: group mission offered (" .. tostring(key) .. ")")
                            end
                            t4:waitUntil(function() return E9.settled(cm, reqM) end, E9.REQUEST_MS, function(t5)
                                t5:ok(E9.heard(Server, me.cid, fm, reqM.id) ~= nil, "member: reply not kept")
                                noAgreement(t5, "member")
                                E9.selectBy(t5, me, cl, function(t6)
                                    t6:ok(E9.acquainted(cl, me.cid) ~= nil, "no contact with the leader")
                                    E9.talkBy(t6, me, cl, textD, function(t7, reqD)
                                        local colD = reqD.context and reqD.context.collective
                                        t7:eq("leader", colD and colD.speaker, "leader request: speaker")
                                        local neg = reqD.context.negotiation
                                        t7:ok(neg ~= nil and neg.terms ~= nil and neg.terms.truce ~= nil,
                                            "leader request: no truce offered")
                                        local binding = Server.collectives[reqD.id]
                                        t7:ok(binding ~= nil, "leader request not bound to the composition")
                                        t7:ok(E.Groups.markDead(gid, "m-2"), "m-2 not marked dead")
                                        local okD, whyD = Server.collectiveCheck(binding, fl)
                                        t7:eq(false, okD, "collective check after the death")
                                        t7:eq("group composition changed", whyD, "reason after the death")
                                        plan[textD].hold = false
                                        t7:waitUntil(function() return E9.settled(cl, reqD) end, E9.REQUEST_MS,
                                            function(t8)
                                            t8:ok(E9.heard(Server, me.cid, fl, reqD.id) ~= nil,
                                                "death: reply not kept (E09-T09)")
                                            noAgreement(t8, "reply after a death")
                                            local mid = E.Groups.addMember(gid, { role = "worker",
                                                day = E.Groups.today() })
                                            t8:ok(mid ~= nil, "third member not added")
                                            E9.talkBy(t8, me, cl, textS, function(t9, reqS)
                                                local bindS = Server.collectives[reqS.id]
                                                t9:ok(bindS ~= nil, "second leader request not bound")
                                                local heir = nil
                                                local g = E.Groups.get(gid)
                                                for k, m in pairs(g.members) do
                                                    if m.alive and k ~= "m-1" then heir = k end
                                                end
                                                t9:ok(heir ~= nil, "no living member to succeed")
                                                t9:ok(E.Groups.setLeader(gid, heir), "succession not applied")
                                                local okS, whyS = Server.collectiveCheck(bindS, fl)
                                                t9:eq(false, okS, "collective check after the succession")
                                                t9:eq("NPC no longer the group leader", whyS, "reason")
                                                plan[textS].hold = false
                                                t9:waitUntil(function() return E9.settled(cl, reqS) end,
                                                    E9.REQUEST_MS, function(t10)
                                                    t10:ok(E9.heard(Server, me.cid, fl, reqS.id) ~= nil,
                                                        "succession: reply not kept (E09-T09)")
                                                    noAgreement(t10, "reply after a succession")
                                                    t10:note(gid .. ": member, death and succession replies kept, "
                                                        .. "no agreement (heir " .. heir .. ")")
                                                end, "reply after the succession never read")
                                            end)
                                        end, "reply after the death never read")
                                    end)
                                end)
                            end, "reply of the member never read")
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
