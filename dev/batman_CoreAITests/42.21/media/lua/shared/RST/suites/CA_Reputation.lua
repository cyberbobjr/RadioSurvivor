--[[
ca.reputation - internal reputation of the core mod in game (E04-T14; server/CoreAI/CA_Reputation.lua, design
docs/annexes/conception/reputation-interne.md). Tags "server" and "world": the authority only (solo, or RST.server from an
admin client), save rstest* in debug mode (the test baseline CA_Reputation.testSetLevel refuses anything else).
Solo campaigns (core part) and MP campaign mp; persistence base of mp-persist (ca.reputation.before / .after-restart).
E21-T11: split from rs.reputation; the killed requester is lk.reputation (RST_LKReputation.lua of
batman_LivingKnoxTests), the smuggler margin stays rs.reputation (batman_RadioSurvivorTests).

    mission success      a finished test mission (CA_Missions.finish, real path, listeners of closed missions muted)
                         gives +5 to its participant only: level, trend "up", reason MissionSuccess with the requester
                         name; the requester client reads it in its own notebook snapshot and Reputation tab (no
                         digit shown); every other bound character is unchanged (server side, and the second client
                         reads its own snapshot in MP)
    simple offer         at a bad level the catalogue of CA_Missions.offers keeps no sensitive template (retrieve_id,
                         recover, group supply) and keeps the simple offers drawn here (deliver, scout, clear, signal)
    admin view           the requester client asks 'rep_admin' (Q17): answered ok by the server for the test admin,
                         its own character listed with a level, no score field
Every test restores the reputation entry of the characters it touched and drops the outcomes it created
(RST_ReputationHelpers.lua).
Persistence (autoclient.py --mp --clients 2 --phases restart --server-campaign mp-persist):
    ca.reputation.before         (opt-in "manual") requester at a neutral baseline, one fact of a fixed event id
                                 recorded (+5), the notebook state saved; snapshot RST_Persist reputation-persist.txt
    ca.reputation.after-restart  same score and revision after the restart, the fact found once, recording the same
                                 event id again is a duplicate (score unchanged); then baseline restored
Outside the game: tests/test_reputation.py (doubles).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_Persist"
require "RST/RST_PeerChecksRep"
require "RST/RST_ReputationHelpers"

local RP = RST.ReputationSuite
local Steps = RST.Steps

RST.suite("ca.reputation", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 400000 }, function(s)
    s.test("a mission success raises its participant only (E04-T04, E04-T08)", function(t)
        local c = RP.setup(t)
        RP.guard(t, c, c.cid)
        RP.baseline(t, c, c.cid, "neutral")
        RP.mute(t, c)
        local others = RP.revisions(c, c.cid)
        local m = RP.testMission(t, c, "rst-rep-npc", { [c.cid] = "requester" })
        t:ok(c.M.finish(c.S.data, m, "success"), "test mission not finished")
        c.S.save()
        t:eq("neutral", c.Rep.level(c.cid), "level after one success")
        t:eq("up", c.Rep.trend(c.cid), "trend after one success")
        local reason = c.Rep.reasons(c.cid, 1)[1]
        t:eq("mission.success", reason and reason.action, "newest reason")
        t:eq(RP.REQUESTER, reason and reason.reasonArgs[1], "public argument of the reason")
        for cid, rev in pairs(others) do
            local entry = c.Rep.data.reputation[cid]
            t:eq(rev, entry and entry.revision, "reputation of " .. cid .. " changed")
        end
        c.Server.publish()
        RP.readBy(t, "requester", { refresh = true, wait = { action = "mission.success" } },
            function(t2, res)
                local d = RP.firstData(res)
                t2:eq(true, d.available, "reputation available in the requester snapshot")
                t2:eq("neutral", d.level, "level read by the requester client")
                t2:eq("up", d.trend, "trend read by the requester client")
                t2:eq(RP.REQUESTER, d.reasonArg, "reason argument read by the requester client")
                t2:eq(false, d.digit, "a digit is shown in the Reputation tab: " .. tostring(d.lines))
                t2:note("tab: " .. tostring(d.lines))
                if RP.second(t2) == nil then return end
                RP.readBy(t2, "others", { refresh = true }, function(t3, res2)
                    local d2 = RP.firstData(res2)
                    t3:ok(d2.reasonArg ~= RP.REQUESTER or d2.action ~= "mission.success",
                        "the second player received the act of the requester")
                end)
            end)
    end)

    s.test("a bad reputation keeps the simple offers only (E04-T05)", function(t)
        local c = RP.setup(t)
        RP.guard(t, c, c.cid)
        local npc = { id = "rst-rep-offers" }
        local record = { hostile = false }
        local function catalog()
            local out = {}
            for key, offer in pairs(c.M.offers(npc, record, c.p, c.cid)) do out[key] = offer end
            return out
        end
        local Config = require "CoreAI/CA_MissionConfig"
        local sensitive = {}
        for name, entry in pairs(Config.Missions) do
            if type(entry) == "table" and entry.id ~= nil and c.Rep.sensitive(name) then sensitive[entry.id] = true end
        end
        RP.baseline(t, c, c.cid, "neutral")
        local neutral = catalog()
        RP.baseline(t, c, c.cid, "bad")
        local bad = catalog()
        local simple = 0
        for key, offer in pairs(bad) do
            t:ok(not sensitive[key] and offer.kind ~= "supply", "sensitive offer " .. key .. " made to a bad reputation")
            simple = simple + 1
        end
        local drawn = {}
        for key in pairs(neutral) do drawn[#drawn + 1] = key end
        t:note("neutral offers: " .. table.concat(drawn, ", ") .. "; bad: " .. simple .. " simple offer(s)")
        local neutralSimple = 0
        for key, offer in pairs(neutral) do
            if not sensitive[key] and offer.kind ~= "supply" then neutralSimple = neutralSimple + 1 end
        end
        if neutralSimple == 0 then t:skip("no simple offer drawn around the player here") end
        t:ok(simple > 0, "a bad reputation received no simple offer")
    end)

    s.test("administrator view: read only, own character listed (Q17)", function(t)
        local c = RP.setup(t)
        RP.guard(t, c, c.cid)
        RP.baseline(t, c, c.cid, "good")
        local name = c.S.data.characters[c.cid].name
        Steps.ask(t, "rep.admin", {}, { target = "requester", timeoutMs = RP.READ_MS }, function(t2, res)
            local d = RP.firstData(res)
            if d.ok ~= true then t2:skip("administrator view refused here (" .. tostring(d.err) .. "): debug or role") end
            t2:ok(string.find(tostring(d.names), tostring(name), 1, true) ~= nil, "own character not listed: "
                .. tostring(d.names))
            t2:eq(false, d.score, "a score field reached the client")
        end)
    end)
end)

-- ---------------------------------------------------------------- persistence (mp-persist base ca.reputation)

RST.suite("ca.reputation.before", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("one fact of a fixed event id recorded and saved", function(t)
        local c = RP.setup(t)
        RP.baseline(t, c, c.cid, "neutral")
        local eventId = "rst-rep-persist-" .. string.format("%.0f", RST.now())
        local o = c.Rep.record(nil, eventId, c.cid, "mission.success", nil, { test = true }, { RP.REQUESTER })
        t:ok(o ~= nil and o.rep == "applied", "fact not applied: " .. tostring(o and o.rep))
        t:ok(c.S.save(), "notebook state not saved")
        local e = c.Rep.data.reputation[c.cid]
        local ok, why = RST.Persist.write(RP.FILE, RP.HEADER, { cid = c.cid, eventId = eventId, score = e.score,
            revision = e.revision, level = c.Rep.level(c.cid) })
        t:ok(ok, "snapshot not written: " .. tostring(why))
        t:note("character " .. c.cid .. ", event " .. eventId .. ", level " .. tostring(c.Rep.level(c.cid)))
    end)
end)

RST.suite("ca.reputation.after-restart", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("same score after the restart, the fact counted once", function(t)
        local c = RP.setup(t)
        local snap, why = RST.Persist.read(RP.FILE, RP.HEADER)
        t:ok(snap ~= nil, why or "no snapshot")
        t:defer(function()
            c.Rep.data.outcomes[snap.eventId] = nil
            c.Rep.testSetLevel(nil, snap.cid, "neutral")
            c.S.dirty = true
            RST.Persist.consume(RP.FILE)
        end, "test fact dropped, baseline restored")
        t:eq(snap.cid, c.cid, "character of the requester")
        local e = c.Rep.data.reputation and c.Rep.data.reputation[snap.cid]
        t:ok(e ~= nil, "reputation entry lost by the restart")
        t:eq(snap.score, e.score, "score after the restart")
        t:eq(snap.revision, e.revision, "revision after the restart")
        t:eq(snap.level, c.Rep.level(snap.cid), "level after the restart")
        t:ok(c.Rep.data.outcomes[snap.eventId] ~= nil, "outcome of the fact lost by the restart")
        local _, dup = c.Rep.record(nil, snap.eventId, snap.cid, "mission.success", nil, nil, nil)
        t:eq("duplicate", dup, "the same event counted again")
        t:eq(snap.score, e.score, "score after the replay")
    end)
end)
