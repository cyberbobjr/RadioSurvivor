--[[
rs.relation - personal relation of a Living Knox npc toward the player's character (E09-T04, intent change_relation,
server/RadioSurvivor/RS_Relations.lua), with the bridge and its model.
A test npc is created next to the player, made the leader of a living group of the save (same setup as rs.npctalk),
selected by the notebook and treated as acquainted. A REAL fact is recorded through the engine (LivingKnox.Hostility
.record: a gift seen by the group), then the player speaks of it with the notebook Say line:
    1. the request offers the fact (context.relation.facts: short id, nature good, never its key) with the relation
       level of the group; when the model returns change_relation the relation goes one level above the group and the
       fact is used (offered no more); when it does not, nothing changes (both noted; the decision is the model's);
    2. without any real fact, a sentence claiming a help never changes the relation (no fact offered, no change),
       whatever the model answers.
Tags "world" and "server" (test saves rstest*), bridge program running (bridge/radio_bridge.py, real model). Same
suite in solo and on a dedicated server (E01-T16): the notebook select and Say line are done by the REQUESTER client
(RST.Steps, RST_RSHelpers R.select / R.talk): the real network path in MP, the same code in solo.
Solo: RST.run({ suite = "rs.relation", tags = "world" }); MP: RST.server({ suite = "rs.relation", tags = "world" })
from an admin client (campaign mp). Cleanup: the attitude pair of the group toward the character is
restored, the relation of the test npc removed, its npc and requests removed by the fixtures.
Test 3 (E09-T04 acceptance in game, no bridge needed; RST_PeerChecksE09.lua): a NEW fixture group (leader A,
member B, RST.LKGroup) near the player. A gift is recorded, the requester client speaks to A with the notebook and
the reply put in the bridge reply file by the test (E9.intercept: the model's decision is not awaited) cites the
offered fact with change_relation up: the REAL notebook reply path applies it (A one level above the group). A theft
(betrayal) is recorded, the requester speaks again, change_relation down on the theft: A back to the group level,
two changes, revision 2, both facts used. A binding of the older revision is refused, a change without any offered
fact is refused; B cites the gift directly on the server (Relations.offer / apply): B one level above, A at the
group level: two npcs of one group differ.
Outside the game: tests/test_relations.py, scenario_relation_change of tests/test_protocol.py,
tests/test_e09_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_RSHelpers"
require "RST/RST_PeerChecksE09"

local F, R, E9 = RST.Fixtures, RST.RSHelpers, RST.PeerChecksE09

local SENTENCES = {
    FR = { gift = "Tu te souviens du sac de provisions que j'ai laisse a ton groupe ?",
        claim = "Je vous ai sauve la vie la semaine derniere, vous me devez tout." },
    EN = { gift = "Do you remember the bag of supplies I left for your group?",
        claim = "I saved your lives last week, you owe me everything." },
}

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

-- Living group of the save whose leader has no body: gid, leader member id, group.
local function freeLeader()
    local G = LivingKnox and LivingKnox.Groups
    if not G then return nil end
    local ids = G.list()
    table.sort(ids)
    for _, gid in ipairs(ids) do
        local g = G.get(gid)
        local m = g and g.leader and g.members[g.leader]
        if m and m.alive and m.npc == nil and g.name then return gid, g.leader, g end
    end
    return nil
end

-- Attitude pair of the group toward the character restored at the end (a fact recorded by the test is removed).
local function keepAttitude(t, gid, cid)
    local H = LivingKnox.Hostility
    local before = H.debugPair(gid, cid)
    t:defer(function()
        local data = H.state.data
        if data and data.groups[gid] then
            data.groups[gid][cid] = deepCopy(before)
            H.save()
        end
    end, "attitude of " .. gid .. " toward the character restored")
end

-- npc next to the player, leader of a group, acquainted, fiche selected; after(t, c).
local function setup(t, after)
    local Server = R.notebook(t)
    local C = require "RadioSurvivor/RS_Config"
    local Rel = require "RadioSurvivor/RS_Relations"
    local p = F.player(t)
    t:ok(p ~= nil, "no target player")
    local cid = R.character(t, p)
    local gid, mid, g = freeLeader()
    if gid == nil then t:skip("no living group with a leader without body in this save (Living Knox population)") end
    R.god(t, p)
    keepAttitude(t, gid, cid)
    R.npcWithFiche(t, p, 2, function(t2, id, fiche)
        local ok, why = LivingKnox.Groups.setNpc(gid, mid, id)
        t2:ok(ok, "npc not bound to the leader of " .. gid .. ": " .. tostring(why))
        t2:defer(function() LivingKnox.Groups.setNpc(gid, mid, nil) end, "unbind the leader of " .. gid)
        t2:defer(function()
            local rel = Server.store.data.relations
            if type(rel) == "table" then rel[fiche.id] = nil end
            Server.store.dirty = true
        end, "relation of the test npc removed")
        local c = { Server = Server, C = C, Rel = Rel, p = p, cid = cid, id = id, fiche = fiche, gid = gid,
            words = SENTENCES[R.language()] }
        -- The spawned body may stand behind a wall of the house (MP campaign of 2026-10-15: "near false, sight
        -- Blocked"): the player is brought next to it first (E9.sight, nothing moves when it is in sight).
        local who = E9.who(t2, p, "requester")
        E9.sight(t2, who, { Server = Server, fiche = fiche, npc = id }, function(t2b)
            R.select(t2b, c, function(t3)
                local contact = Server.store.data.characters[cid].contacts[fiche.id]
                contact.exchanges = C.ACQUAINT_EXCHANGES
                c.contact = contact
                t3:note("npc " .. id .. " leader of " .. gid .. " '" .. tostring(g.name) .. "'")
                return after(t3, c)
            end)
        end)
    end)
end

-- One sentence of the requester client (notebook Say line, R.talk): waits for the request (onRequest(t, req)), then
-- for its end (answer heard or refused): onDone(t, req, answer or nil).
local function say(t, c, text, onRequest, onDone)
    R.talk(t, c, text, function(t2, req)
        onRequest(t2, req)
        t2:waitUntil(function()
            for _, h in ipairs(c.contact.history or {}) do
                if h.id == req.id then return { text = h.text } end
            end
            for _, r in ipairs(c.Server.pending) do if r.id == req.id then return nil end end
            return { text = nil }
        end, c.C.REQUEST_TIMEOUT_MS + 10000, function(t3, result)
            t3:note("'" .. text .. "' -> '" .. tostring(result.text) .. "'")
            return onDone(t3, req, result.text)
        end, "no answer within the request timeout (is the bridge running?)")
    end)
end

RST.suite("rs.relation", { tags = { "world", "server" }, testTimeoutMs = 300000, timeoutMs = 900000 }, function(s)
    s.test("a real gift is offered as a fact; the change (or none) is checked by the server (E09-T04)", function(t)
        setup(t, function(t2, c)
            local res, why = LivingKnox.Hostility.record(c.gid, c.cid, "gift", { witnessed = true })
            t2:ok(res ~= nil, "gift not recorded by the engine: " .. tostring(why))
            local before = c.Rel.view(c.fiche, c.cid)
            t2:note("relation before: " .. before.level .. " (group " .. before.group .. ")")
            say(t2, c, c.words.gift, function(t3, req)
                local rel = (req.context or {}).relation
                t3:ok(type(rel) == "table", "no relation in the request context")
                t3:eq(before.level, rel.level, "relation level sent to the model")
                local found = nil
                for _, f in ipairs(rel.facts or {}) do
                    if f.fact == "gift" and f.nature == "good" then found = f end
                    t3:ok(string.find(tostring(f.id), "^f%d+$") ~= nil, "fact id is not a short id: " .. tostring(f.id))
                end
                t3:ok(found ~= nil, "the recorded gift is not offered as a citable fact")
            end, function(t3)
                local pair = c.Rel.debugPair(c.fiche.id, c.cid)
                local after = c.Rel.view(c.fiche, c.cid)
                if pair and pair.gap == 1 then
                    t3:eq(1, count(pair.used), "one fact used by the change")
                    t3:note("model changed the relation: " .. before.level .. " -> " .. after.level)
                    local context = c.Rel.offer(c.fiche, c.cid)
                    for _, f in ipairs(context.facts) do
                        t3:ok(f.nature ~= "good", "a good fact still offered at the upper bound")
                    end
                else
                    t3:eq(before.level, after.level, "relation changed without a recorded change")
                    t3:note("model kept the relation (no change_relation, or refused: see the [RS_Carnet] lines)")
                end
            end)
        end)
    end)

    s.test("a claimed help without any real fact never changes the relation (E09-T04)", function(t)
        setup(t, function(t2, c)
            local before = c.Rel.view(c.fiche, c.cid)
            local context = c.Rel.offer(c.fiche, c.cid)
            if #context.facts > 0 then t2:skip("the group already holds facts about this character in this save") end
            say(t2, c, c.words.claim, function(t3, req)
                local rel = (req.context or {}).relation
                t3:ok(type(rel) == "table", "no relation in the request context")
                t3:eq(0, count(rel.facts), "facts offered without any real fact")
            end, function(t3)
                t3:eq(nil, c.Rel.debugPair(c.fiche.id, c.cid), "relation changed by words alone")
                t3:eq(before.level, c.Rel.view(c.fiche, c.cid).level, "relation level")
            end)
        end)
    end)

    -- E09-T04 acceptance: help then betrayal = two changes (real reply path, fabricated replies); two npcs differ.
    s.test("help then betrayal: two changes; two npcs of one group differ (E09-T04)", function(t0)
        local Server = R.notebook(t0)
        local C = require "RadioSurvivor/RS_Config"
        local Rel = require "RadioSurvivor/RS_Relations"
        local H = LivingKnox and LivingKnox.Hostility
        if H == nil then t0:skip("Living Knox server part not loaded here") end
        local p = F.player(t0)
        t0:ok(p ~= nil, "no target player")
        R.god(t0, p)
        local me = E9.who(t0, p, "requester")
        local stamp = tostring(getTimestampMs() % 100000)
        E9.fixture(t0, p, function(t, gid, leaderNpc, mateNpc)
            E9.fiche(t, Server, leaderNpc, function(t1, fa)
                E9.fiche(t1, Server, mateNpc, function(t2, fb)
                    t2:defer(function()
                        local rel = Server.store.data.relations
                        if type(rel) == "table" then rel[fa.id], rel[fb.id] = nil, nil end
                        Server.store.dirty = true
                    end, "relations of the fixture npcs removed")
                    local ctl = E9.intercept(t2)
                    ctl.quiet({ [fa.id] = true, [fb.id] = true })
                    local want = {}
                    ctl.rule(function(req)
                        return req.kind == "npc_talk" and req.npc == fa.id and want[req.text] ~= nil
                    end, function(req)
                        local w = want[req.text]
                        local rel = type(req.context) == "table" and req.context.relation or nil
                        for _, f in ipairs(type(rel) == "table" and rel.facts or {}) do
                            if f.fact == w.fact and f.nature == w.nature then w.id = f.id end
                        end
                        if w.id == nil then return E9.reply(req, {}) end
                        return E9.reply(req, { intent = "change_relation", dir = w.dir, fact = w.id })
                    end)
                    local c = { Server = Server, C = C, fiche = fa, npc = leaderNpc }
                    local help = "RST help " .. stamp
                    local betrayal = "RST betrayal " .. stamp
                    want[help] = { fact = "gift", nature = "good", dir = "up" }
                    want[betrayal] = { fact = "theft", nature = "bad", dir = "down" }
                    E9.selectBy(t2, me, c, function(t3)
                        local okG, whyG = H.record(gid, me.cid, "gift", { witnessed = true })
                        t3:ok(okG ~= nil, "gift not recorded: " .. tostring(whyG))
                        E9.talkBy(t3, me, c, help, function(t4, req1)
                            t4:waitUntil(function() return E9.settled(c, req1) end, E9.REQUEST_MS, function(t5)
                                t5:ok(want[help].id ~= nil, "the gift was not offered as a citable fact")
                                t5:ok(E9.heard(Server, me.cid, fa, req1.id) ~= nil, "reply of the help not kept")
                                local pair = Rel.debugPair(fa.id, me.cid)
                                t5:eq(1, pair and pair.gap, "help: one level above the group")
                                local okT, whyT = H.record(gid, me.cid, "theft", { witnessed = true })
                                t5:ok(okT ~= nil, "theft not recorded: " .. tostring(whyT))
                                local _, stale = Rel.offer(fa, me.cid)
                                t5:ok(stale ~= nil, "no citable fact after the theft")
                                E9.talkBy(t5, me, c, betrayal, function(t6, req2)
                                    t6:waitUntil(function() return E9.settled(c, req2) end, E9.REQUEST_MS, function(t7)
                                        t7:ok(want[betrayal].id ~= nil, "the theft was not offered as a citable fact")
                                        local now = Rel.debugPair(fa.id, me.cid)
                                        t7:eq(0, now and now.gap, "betrayal: back to the group level")
                                        t7:eq(2, now and now.revision, "two changes, two revisions")
                                        t7:eq(2, now and #now.changes, "changes kept")
                                        t7:eq(1, now and now.changes[1].sign, "first change: help")
                                        t7:eq(-1, now and now.changes[2].sign, "second change: betrayal")
                                        t7:eq(2, now and #now.used, "both facts used")
                                        local theftId = nil
                                        for id, key in pairs(stale.ids) do
                                            if key == now.used[2] then theftId = id end
                                        end
                                        local v, why = Rel.apply(fa, me.cid, stale, "down", theftId or "f1")
                                        t7:eq(nil, v, "change on an older revision applied")
                                        t7:eq("relation revision changed", why, "refusal of the older revision")
                                        local v2, why2 = Rel.apply(fb, me.cid, nil, "up", "f1")
                                        t7:eq(nil, v2, "change without any offered fact applied")
                                        t7:ok(why2 ~= nil, "refusal without fact")
                                        local ctxB, bindB = Rel.offer(fb, me.cid)
                                        local giftB = nil
                                        for _, f in ipairs(ctxB.facts) do
                                            if f.fact == "gift" and f.nature == "good" then giftB = f.id end
                                        end
                                        t7:ok(giftB ~= nil, "the gift is not citable for the second npc")
                                        local vb, whyB = Rel.apply(fb, me.cid, bindB, "up", giftB)
                                        t7:ok(vb ~= nil, "second npc change refused: " .. tostring(whyB))
                                        local va = Rel.view(fa, me.cid)
                                        t7:ok(vb.level ~= va.level, "two npcs of one group differ: "
                                            .. tostring(va.level) .. " / " .. tostring(vb.level))
                                        t7:note("group " .. gid .. ": npc A " .. tostring(va.level) .. ", npc B "
                                            .. tostring(vb.level) .. " (group level " .. tostring(va.group) .. ")")
                                    end, "reply of the betrayal never read by the notebook")
                                end)
                            end, "reply of the help never read by the notebook")
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
