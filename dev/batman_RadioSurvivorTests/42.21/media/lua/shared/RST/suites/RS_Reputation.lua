--[[
rs.reputation - internal reputation of RadioSurvivor in game (E04-T14; server/RadioSurvivor/RS_Reputation.lua, design
docs/conception/reputation-interne.md). Tags "server" and "world": the authority only (solo, or RST.server from an
admin client), save rstest* in debug mode (the test baseline RS_Reputation.testSetLevel refuses anything else).
Solo campaign solo-rs and MP campaign mp; persistence base of mp-persist (rs.reputation.before / .after-restart).

    mission success      a finished test mission (RS_Missions.finish, real path, listeners of closed missions muted)
                         gives +5 to its participant only: level, trend "up", reason MissionSuccess with the requester
                         name; the requester client reads it in its own notebook snapshot and Reputation tab (no
                         digit shown); every other bound character is unchanged (server side, and the second client
                         reads its own snapshot in MP)
    requester killed     a Living Knox test npc with a notebook fiche asks a test mission of the requester (and, in MP,
                         of the second player); the requester kills it with a lethal bat hit (real IsoZombie.Hit,
                         death attributed by LivingKnox.Bodies): the killer drops to "bad" (RequesterKilled, the npc
                         name), the team mate keeps his reputation (score unchanged, asked to his client in MP)
    simple offer         at a bad level the catalogue of RS_Missions.offers keeps no sensitive template (retrieve_id,
                         recover, group supply) and keeps the simple offers drawn here (deliver, scout, clear, signal)
    smuggler margin      RS_Trade.marginRange of a fresh book: good 0.10, neutral 0.25, bad 0.40 (Q13)
    admin view           the requester client asks 'rep_admin' (Q17): answered ok by the server for the test admin,
                         its own character listed with a level, no score field
Every test restores the reputation entry of the characters it touched and drops the outcomes it created.
Persistence (autoclient.py --mp --clients 2 --phases restart --server-campaign mp-persist):
    rs.reputation.before         (opt-in "manual") requester at a neutral baseline, one fact of a fixed event id
                                 recorded (+5), the notebook state saved; snapshot RST_Persist reputation-persist.txt
    rs.reputation.after-restart  same score and revision after the restart, the fact found once, recording the same
                                 event id again is a duplicate (score unchanged); then baseline restored
Outside the game: tests/test_reputation.py, tests/test_rs_trade.py, tests/test_lk_hostility.py (doubles).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_RSHelpers"
require "RST/RST_LKHelpers"
require "RST/RST_Persist"
require "RST/RST_PeerChecksRep"

RST.ReputationSuite = RST.ReputationSuite or {}
local RP = RST.ReputationSuite
RP.FILE = "reputation-persist.txt"
RP.HEADER = "RSREPUTATION1"
RP.REQUESTER = "RST Requester"
RP.READ_MS = 10000
RP.DEATH_MS = 8000

local Steps = RST.Steps
local R = RST.RSHelpers
local K = RST.LKHelpers

local function isServerSide() return type(isServer) == "function" and isServer() end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Notebook server, its state, the reputation module, the requester and its character.
local function setup(t)
    if type(isClient) == "function" and isClient() then t:skip("the reputation lives on the authority") end
    local Server = R.notebook(t)
    local S = Server.store
    if S.blocked then t:skip("notebook storage blocked") end
    local Rep = require "RadioSurvivor/RS_Reputation"
    t:ok(type(Rep) == "table" and type(Rep.testSetLevel) == "function", "RS_Reputation (E04) not loaded")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local cid = R.character(t, p)
    return { Server = Server, S = S, Rep = Rep, p = p, cid = cid, M = require "RadioSurvivor/RS_Missions" }
end

-- The reputation entry of cid is restored at the end; outcomes created during the test are dropped.
local function guard(t, c, cid)
    local data = c.S.data
    local saved = copy(type(data.reputation) == "table" and data.reputation[cid] or nil)
    local known = {}
    for id in pairs(data.outcomes or {}) do known[id] = true end
    t:defer(function()
        if type(data.reputation) ~= "table" then data.reputation = {} end
        data.reputation[cid] = saved
        local drop = {}
        for id in pairs(data.outcomes or {}) do if not known[id] then drop[#drop + 1] = id end end
        for _, id in ipairs(drop) do data.outcomes[id] = nil end
        c.S.dirty = true
        c.Server.publish()
    end, "reputation of " .. cid .. " restored")
end

local function baseline(t, c, cid, level)
    local ok, why = c.Rep.testSetLevel(c.S.data, cid, level)
    if not ok then t:skip("test baseline refused: " .. tostring(why)) end
end

-- Listeners of closed missions (chronicle, observations) muted during the test: a test mission is no event.
local function mute(t, c)
    local previous = c.M.onFinished
    c.M.onFinished = nil
    t:defer(function() c.M.onFinished = previous end, "listeners of closed missions restored")
end

-- Second online player and its character (MP), or nil.
local function second(t)
    if not isServerSide() then return nil end
    local name = Steps.others(t)[1]
    local p = name and Steps.playerOf(name) or nil
    if p == nil then return nil end
    return p, name, R.character(t, p)
end

-- Active test mission of `npcId` with participants { [cid] = name }, inserted in the state (removed at the end).
local function testMission(t, c, npcId, participants)
    local id = "rst-rep-" .. string.format("%.0f", RST.now())
    local m = { id = id, npc = npcId, template = "deliver", offer = "first_aid_v1", titleKey = "IGUI_RS_FirstAid",
        state = "active", revision = 1, durationMs = 3600000, remainingMs = 3600000, participants = {}, invited = {},
        rewardType = "", rewardCount = 0, claimedBy = "", receipts = {}, quantity = 1, delivered = 0, accepted = {},
        requesterName = RP.REQUESTER }
    for cid, name in pairs(participants) do m.participants[cid] = { name = name } end
    c.S.data.missions[id] = m
    t:defer(function() c.S.data.missions[id] = nil; c.S.dirty = true end, "test mission " .. id .. " removed")
    return m
end

local function revisions(c, except)
    local out = {}
    for cid, e in pairs(c.S.data.reputation or {}) do
        if cid ~= except then out[cid] = e.revision end
    end
    return out
end

local function readBy(t, target, args, after)
    Steps.ask(t, "rep.read", args, { target = target, timeoutMs = RP.READ_MS }, after)
end

local function firstData(res)
    local e = res and res.list and res.list[1]
    return e and e.data or {}
end

RST.suite("rs.reputation", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 400000 }, function(s)
    s.test("a mission success raises its participant only (E04-T04, E04-T08)", function(t)
        local c = setup(t)
        guard(t, c, c.cid)
        baseline(t, c, c.cid, "neutral")
        mute(t, c)
        local others = revisions(c, c.cid)
        local m = testMission(t, c, "rst-rep-npc", { [c.cid] = "requester" })
        t:ok(c.M.finish(c.S.data, m, "success"), "test mission not finished")
        c.S.save()
        t:eq("neutral", c.Rep.level(c.cid), "level after one success")
        t:eq("up", c.Rep.trend(c.cid), "trend after one success")
        local reason = c.Rep.reasons(c.cid, 1)[1]
        t:eq("IGUI_RS_RepReason_MissionSuccess", reason and reason.reasonKey, "newest reason")
        t:eq(RP.REQUESTER, reason and reason.reasonArgs[1], "public argument of the reason")
        for cid, rev in pairs(others) do
            t:eq(rev, c.S.data.reputation[cid] and c.S.data.reputation[cid].revision, "reputation of " .. cid .. " changed")
        end
        c.Server.publish()
        readBy(t, "requester", { refresh = true, wait = { reasonKey = "IGUI_RS_RepReason_MissionSuccess" } },
            function(t2, res)
                local d = firstData(res)
                t2:eq(true, d.available, "reputation available in the requester snapshot")
                t2:eq("neutral", d.level, "level read by the requester client")
                t2:eq("up", d.trend, "trend read by the requester client")
                t2:eq(RP.REQUESTER, d.reasonArg, "reason argument read by the requester client")
                t2:eq(false, d.digit, "a digit is shown in the Reputation tab: " .. tostring(d.lines))
                t2:note("tab: " .. tostring(d.lines))
                if second(t2) == nil then return end
                readBy(t2, "others", { refresh = true }, function(t3, res2)
                    local d2 = firstData(res2)
                    t3:ok(d2.reasonArg ~= RP.REQUESTER or d2.reasonKey ~= "IGUI_RS_RepReason_MissionSuccess",
                        "the second player received the act of the requester")
                end)
            end)
    end)

    s.test("the killer of a requester drops to bad, the team mate is spared (E04-T07)", function(t)
        local c = setup(t)
        local ready, why = RST.Fixtures.npcReady()
        if not ready then t:skip("no Living Knox test npc: " .. tostring(why)) end
        guard(t, c, c.cid)
        baseline(t, c, c.cid, "neutral")
        mute(t, c)
        local _, mateName, mate = second(t)
        if mate ~= nil then
            guard(t, c, mate)
            baseline(t, c, mate, "neutral")
        else
            t:note("solo or one client: no team mate (the MP campaign checks him)")
        end
        R.npcWithFiche(t, c.p, 2, function(t2, id, fiche, body)
            local members = { [c.cid] = "requester" }
            if mate ~= nil then members[mate] = tostring(mateName) end
            local m = testMission(t2, c, fiche.id, members)
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
                    t4:eq("IGUI_RS_RepReason_RequesterKilled", reason and reason.reasonKey, "reason of the killer")
                    t4:eq(fiche.name, reason and reason.reasonArgs[1], "name of the requester in the reason")
                    if mate ~= nil then
                        t4:eq(mateScore, c.Rep.scoreOf(mate), "score of the team mate")
                        t4:eq("neutral", c.Rep.level(mate), "level of the team mate")
                        c.Server.publish()
                        readBy(t4, { mateName }, { refresh = true }, function(t5, res)
                            t5:eq("neutral", firstData(res).level, "level read by the team mate client")
                        end)
                    end
                end, "the requester npc did not die after a lethal hit")
            end, "npc still on the floor")
        end)
    end, { timeoutMs = 120000 })

    s.test("a bad reputation keeps the simple offers only (E04-T05)", function(t)
        local c = setup(t)
        guard(t, c, c.cid)
        local npc = { id = "rst-rep-offers" }
        local record = { hostile = false }
        local function catalog()
            local out = {}
            for key, offer in pairs(c.M.offers(npc, record, c.p, c.cid)) do out[key] = offer end
            return out
        end
        local Config = require "RadioSurvivor/RS_Config"
        local sensitive = {}
        for name, entry in pairs(Config.Missions) do
            if type(entry) == "table" and entry.id ~= nil and c.Rep.sensitive(name) then sensitive[entry.id] = true end
        end
        baseline(t, c, c.cid, "neutral")
        local neutral = catalog()
        baseline(t, c, c.cid, "bad")
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

    s.test("the smuggler margin follows the level (E04-T11)", function(t)
        local c = setup(t)
        guard(t, c, c.cid)
        local Trade = require "RadioSurvivor/RS_Trade"
        local caller = "rst-rep-caller"
        for _, case in ipairs({ { "good", 0.10 }, { "neutral", 0.25 }, { "bad", 0.40 } }) do
            baseline(t, c, c.cid, case[1])
            local low = Trade.marginRange(caller, c.cid)
            t:ok(math.abs(low - case[2]) < 0.001, case[1] .. ": lowest margin " .. tostring(low) .. ", expected "
                .. case[2])
        end
    end)

    s.test("administrator view: read only, own character listed (Q17)", function(t)
        local c = setup(t)
        guard(t, c, c.cid)
        baseline(t, c, c.cid, "good")
        local name = c.S.data.characters[c.cid].name
        Steps.ask(t, "rep.admin", {}, { target = "requester", timeoutMs = RP.READ_MS }, function(t2, res)
            local d = firstData(res)
            if d.ok ~= true then t2:skip("administrator view refused here (" .. tostring(d.err) .. "): debug or role") end
            t2:ok(string.find(tostring(d.names), tostring(name), 1, true) ~= nil, "own character not listed: "
                .. tostring(d.names))
            t2:eq(false, d.score, "a score field reached the client")
        end)
    end)
end)

-- ---------------------------------------------------------------- persistence (mp-persist base rs.reputation)

RST.suite("rs.reputation.before", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("one fact of a fixed event id recorded and saved", function(t)
        local c = setup(t)
        baseline(t, c, c.cid, "neutral")
        local eventId = "rst-rep-persist-" .. string.format("%.0f", RST.now())
        local o = c.Rep.record(c.S.data, eventId, c.cid, "mission.success", nil, { test = true }, { RP.REQUESTER })
        t:ok(o ~= nil and o.rep == "applied", "fact not applied: " .. tostring(o and o.rep))
        t:ok(c.S.save(), "notebook state not saved")
        local e = c.S.data.reputation[c.cid]
        local ok, why = RST.Persist.write(RP.FILE, RP.HEADER, { cid = c.cid, eventId = eventId, score = e.score,
            revision = e.revision, level = c.Rep.level(c.cid) })
        t:ok(ok, "snapshot not written: " .. tostring(why))
        t:note("character " .. c.cid .. ", event " .. eventId .. ", level " .. tostring(c.Rep.level(c.cid)))
    end)
end)

RST.suite("rs.reputation.after-restart", { tags = { "server", "world", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("same score after the restart, the fact counted once", function(t)
        local c = setup(t)
        local snap, why = RST.Persist.read(RP.FILE, RP.HEADER)
        t:ok(snap ~= nil, why or "no snapshot")
        t:defer(function()
            c.S.data.outcomes[snap.eventId] = nil
            c.Rep.testSetLevel(c.S.data, snap.cid, "neutral")
            c.S.dirty = true
            RST.Persist.consume(RP.FILE)
        end, "test fact dropped, baseline restored")
        t:eq(snap.cid, c.cid, "character of the requester")
        local e = c.S.data.reputation and c.S.data.reputation[snap.cid]
        t:ok(e ~= nil, "reputation entry lost by the restart")
        t:eq(snap.score, e.score, "score after the restart")
        t:eq(snap.revision, e.revision, "revision after the restart")
        t:eq(snap.level, c.Rep.level(snap.cid), "level after the restart")
        t:ok(c.S.data.outcomes[snap.eventId] ~= nil, "outcome of the fact lost by the restart")
        local _, dup = c.Rep.record(c.S.data, snap.eventId, snap.cid, "mission.success", nil, nil, nil)
        t:eq("duplicate", dup, "the same event counted again")
        t:eq(snap.score, e.score, "score after the replay")
    end)
end)
