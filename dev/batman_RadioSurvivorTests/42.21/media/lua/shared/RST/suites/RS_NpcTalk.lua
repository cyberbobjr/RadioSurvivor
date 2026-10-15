--[[
rs.npctalk - talking to a Living Knox npc through the notebook, with the bridge and its model (E17-T08, E17-T09).
A test npc is created next to the player and made the leader of a living group of the save (LivingKnox.Groups.setNpc
on a leader without body; given back at the end), selected and spoken to with the notebook Say line
(RS_CarnetClient.talk, the same 'talk' command as the chat). Each sentence waits for the request of the server
(checked: stage, context, offers) and for the answer of the model (checked: facts only, never words of the player).
    E17-T08  first "hello" to a stranger: request at stage "stranger", context without the group name, story, leader
             or needs, no offer catalogue; answer without the group name nor the leader name; no mission. Asking for
             help while still a stranger: same, no offer.
    E17-T08/T09  acquainted (4 answered exchanges recorded on the contact): asking for help sends the offer catalogue;
             an offer made by the model is signalled on screen ("New offer in the notebook", RS_CarnetClient
             offersShown); a clear "yes, I'll do it" then makes the offer acceptable (context.acceptable) and, when the
             model returns intent accept, the mission becomes active (zone in the snapshot for a scout mission). When
             the model makes no offer, a scout offer is created by the suite so that the spoken acceptance is still
             tried (noted).
    E17-T09  "maybe later?" after an offer: the offer stays an offer; the notebook Accept button still accepts it.
    E17-T13  a long answer asked for: its speech bubble (LK_SpeechView) is cut in pieces of whole sentences
             (RS_TextCut.pieces, PIECE characters at most, never inside a word), shown one after another, each one
             only after the previous one had its reading time (View.pieceLog). Pieces noted in the report.
Results that depend on the model (offer made, acceptance understood) are FAIL with an explicit "model" message: read
them with the answers noted in the report.
Tags "world" and "server" (test saves rstest*), bridge program running (bridge/radio_bridge.py, real model). Same suite
in solo and on a dedicated server (E01-T16): the authority creates the npc and reads its requests; everything the
player does or sees goes through the REQUESTER client (RST.Steps, target "requester": notebook select and Say line,
offer message, snapshot row, bubble pieces; RST_PeerChecks.lua), i.e. the real network path in MP (client -> 'talk'
command -> server -> bridge -> answer -> bubble and notebook on the client) and the same code in one Lua state in solo.
Solo: RST.run({ suite = "rs.npctalk", tags = "world" }). MP: RST.server({ suite = "rs.npctalk", tags = "world" }) from
an admin client (campaign mp, autoclient.py --mp --server-campaign mp, bridge on the exchange folder of the server).
Each test removes its npc, its missions and its pending requests.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_RSHelpers"

local F, R = RST.Fixtures, RST.RSHelpers

local SENTENCES = {
    FR = { hello = "Salut !", help = "Tu as besoin d'aide ? Je cherche du travail.",
        yes = "D'accord, je m'en occupe.", later = "Peut-etre plus tard ?",
        long = "Raconte-moi en detail tout ce que tu as vu depuis le debut, en plusieurs phrases." },
    EN = { hello = "Hi there!", help = "Do you need help? I am looking for work.",
        yes = "Alright, I will take care of it.", later = "Maybe later?",
        long = "Tell me in detail everything you have seen since the beginning, in several sentences." },
}

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
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

-- Ordinary zombies (no Living Knox tag) within r squares of the player removed: the test npc engages a zombie up to
-- 10 squares away (LK06-T14) and may leave the house to fight it; the player inside then cannot hear its answer
-- (RS_NPCProvider.hears: one inside, one outside = no line), and the request ends without any history (in-game run of
-- 2026-10-13: lk-219 and lk-220 fought zombie z@100006 in the yard, both "help" answers were never heard).
local CLEAR_RADIUS = 20
local function clearZombies(t, p)
    local I = LivingKnox and LivingKnox.Identity
    local list = getCell():getZombieList()
    local px, py = p:getX(), p:getY()
    local removed = 0
    for i = list:size() - 1, 0, -1 do
        local z = list:get(i)
        if z ~= nil and not z:isDead() and math.abs(z:getX() - px) <= CLEAR_RADIUS
            and math.abs(z:getY() - py) <= CLEAR_RADIUS
            and not (z:hasModData() and I ~= nil and I.readTag(z:getModData()) ~= nil) then
            z:removeFromWorld()
            z:removeFromSquare()
            removed = removed + 1
        end
    end
    if removed > 0 then t:note(removed .. " zombie(s) removed within " .. CLEAR_RADIUS .. " squares") end
end

-- Why a request left the queue without a line in the contact history: the acknowledgement of the server (S.data.acks,
-- kept until the bridge confirms it) says whether the answer was refused or applied but not heard.
local function lostAnswer(c, reqId)
    for _, ack in ipairs(c.Server.store.data.acks or {}) do
        if ack.request == reqId then
            if ack.status ~= "accepted" then
                -- E17-T15: the cause kept by the server (bridge error timeout, http_503..., no reply).
                for _, r in ipairs(c.Server.refusals or {}) do
                    if r.id == reqId then return "answer refused by the server: " .. tostring(r.reason) end
                end
                return "answer refused by the server (see the '[RS_Carnet] npc_talk " .. tostring(reqId)
                    .. " refused' line of the log)"
            end
            local body = c.Server.objects[c.fiche.id]
            local where = body and string.format("npc at %d,%d, player at %d,%d", math.floor(body:getX()),
                math.floor(body:getY()), math.floor(c.p:getX()), math.floor(c.p:getY())) or "npc body not mapped"
            return "answer applied by the server but not heard by the player (RS_NPCProvider.hears; " .. where .. ")"
        end
    end
    return "answer refused or not heard (acknowledgement already confirmed by the bridge; see the [RS_Carnet] lines)"
end

-- npc next to the player, leader of a group, fiche selected by the notebook; after(t, c).
local function setup(t, after)
    local Server = R.notebook(t)
    local C = require "RadioSurvivor/RS_Config"
    local p = F.player(t)
    t:ok(p ~= nil, "no target player")
    local cid = R.character(t, p)
    local gid, mid, g = freeLeader()
    if gid == nil then t:skip("no living group with a leader without body in this save (Living Knox population)") end
    R.god(t, p)
    clearZombies(t, p)
    R.npcWithFiche(t, p, 2, function(t2, id, fiche)
        local ok, why = LivingKnox.Groups.setNpc(gid, mid, id)
        t2:ok(ok, "npc not bound to the leader of " .. gid .. ": " .. tostring(why))
        t2:defer(function() LivingKnox.Groups.setNpc(gid, mid, nil) end, "unbind the leader of " .. gid)
        t2:defer(function()
            local data = Server.store.data
            for mid2, m in pairs(data.missions) do
                if m.npc == fiche.id then
                    data.missions[mid2] = nil
                    for _, record in pairs(data.characters) do record.knownMissions[mid2] = nil end
                end
            end
            fiche.mission = nil
            Server.publish()
        end, "remove the missions of the test npc")
        Server.ensure(id)
        local c = { Server = Server, C = C, p = p, cid = cid, id = id, fiche = fiche, gid = gid, group = g,
            groupName = g.name, words = SENTENCES[R.language()] }
        R.select(t2, c, function(t3)
            local P = require "RadioSurvivor/RS_NPCProvider"
            local full = P.context(id, cid, R.language()) or {}
            c.leaderName = full.leaderName
            c.contact = Server.store.data.characters[cid].contacts[fiche.id]
            t3:note("npc " .. id .. " leader of " .. gid .. " '" .. tostring(g.name) .. "'")
            return after(t3, c)
        end)
    end)
end

-- One sentence of the requester client (R.talk: notebook Say line once the previous answer and the cooldown are over),
-- the request of the authority (onRequest(t, req): assertions, no wait), then the answer of the model
-- (onReply(t, req, text)).
local function say(t, c, text, onRequest, onReply)
    R.talk(t, c, text, function(t2, seen)
        onRequest(t2, seen)
        t2:waitUntil(function()
            for _, h in ipairs(c.contact.history or {}) do
                if h.id == seen.id then return { text = h.text } end
            end
            for _, r in ipairs(c.Server.pending) do if r.id == seen.id then return nil end end
            return { refused = true, why = lostAnswer(c, seen.id) }
        end, c.C.REQUEST_TIMEOUT_MS + 10000, function(t3, result)
            t3:ok(not result.refused, result.why)
            local answer = result.text
            t3:note("'" .. text .. "' -> '" .. tostring(answer) .. "'")
            return onReply(t3, seen, answer)
        end, function() return "no answer within the request timeout: " .. R.bridgeCause(c.Server, seen.sent) end)
    end)
end

-- Notebook state of the requester client for mission id (RST.Steps "carnet.state"; wait = "offer" or "engaged");
-- after(t, data).
local function clientState(t, id, wait, after)
    RST.Steps.ask(t, "carnet.state", { mission = id, wait = wait }, { target = "requester", timeoutMs = 10000 },
        function(t2, res)
            local e = res.list[1]
            return after(t2, e and e.data or {})
        end)
end

local function noLeak(t, c, answer)
    for _, name in ipairs({ c.groupName, c.leaderName }) do
        if type(name) == "string" and name ~= "" then
            t:ok(string.find(string.lower(answer), string.lower(name), 1, true) == nil,
                "model: the answer of a stranger names '" .. name .. "'")
        end
    end
end

local function strangerRequest(t, req)
    local ctx = req.context or {}
    t:eq("stranger", ctx.stage, "stage of the request")
    t:eq(0, count(req.offers), "offer catalogue sent to a stranger")
    local g = ctx.group
    if type(g) == "table" then
        for _, key in ipairs({ "group", "summary", "leaderName", "needs", "story" }) do
            t:eq(nil, g[key], "context.group." .. key .. " given to a stranger")
        end
    end
end

-- Scout offer of the fiche made by the suite (the model made none); nil when no building fits around.
local function directOffer(c)
    local M = require "RadioSurvivor/RS_Missions"
    local Scout = require "RadioSurvivor/RS_MissionScout"
    local cfg = c.C.Missions.scout
    Scout.resetForTests()
    c.fiche.nextOfferAt = nil
    local terms = Scout.offer(cfg, c.fiche, nil, c.Server.objects[c.fiche.id])
    if not terms then return nil end
    local m = M.create(c.Server.store.data, c.fiche, c.cid, cfg.id, terms)
    c.Server.publish()
    return m
end

-- Scout offer possible around the player (probe npc, nothing created), for R.place.
local function scoutFits(pl)
    local C = require "RadioSurvivor/RS_Config"
    local Scout = require "RadioSurvivor/RS_MissionScout"
    local x, y = pl:getX(), pl:getY()
    Scout.resetForTests()
    return Scout.offer(C.Missions.scout, { id = "rst-npctalk-probe" }, nil,
        { getX = function() return x end, getY = function() return y end })
end

-- E17-T13: nil when each bubble piece reads alone (length bounded; a piece that does not end a sentence holds no
-- sentence end, otherwise the cut should have been made there), else the reason.
local function badCut(pieces, max, TextCut)
    for i, piece in ipairs(pieces) do
        if string.len(piece) > max then return "piece " .. i .. " longer than " .. max .. ": " .. piece end
        if i < #pieces and not TextCut.endsSentence(piece) then
            local inner = TextCut.pieces(piece, string.len(piece) - 1)
            if #inner > 1 and TextCut.endsSentence(inner[1]) then
                return "piece " .. i .. " cut mid-sentence after a possible sentence end: " .. piece
            end
        end
    end
    return nil
end

RST.suite("rs.npctalk", { tags = { "world", "server" }, testTimeoutMs = 400000, timeoutMs = 1200000 }, function(s)
    s.test("stranger: hello and help asked, no group, no home, no offer (E17-T08)", function(t)
        setup(t, function(t2, c)
            say(t2, c, c.words.hello, strangerRequest, function(t3, _, answer)
                noLeak(t3, c, answer)
                t3:eq(nil, c.fiche.mission, "offer made to a stranger")
                say(t3, c, c.words.help, strangerRequest, function(t4, _, answer2)
                    noLeak(t4, c, answer2)
                    t4:eq(nil, c.fiche.mission, "offer made to a stranger asking for help")
                    t4:eq("stranger", c.contact.stage, "stage after two exchanges")
                end)
            end)
        end)
    end)

    s.test("acquainted: help asked gives an offer, a spoken yes accepts it (E17-T08, E17-T09)", function(t)
        R.place(t, F.player(t), scoutFits, function(t1) setup(t1, function(t2, c)
            c.contact.exchanges = c.C.ACQUAINT_EXCHANGES
            say(t2, c, c.words.help, function(t3, req)
                t3:eq("acquainted", (req.context or {}).stage, "stage after " .. c.C.ACQUAINT_EXCHANGES .. " exchanges")
                t3:note("offer catalogue: " .. count(req.offers) .. " offer(s)")
            end, function(t3)
                local m = c.fiche.mission and c.Server.store.data.missions[c.fiche.mission]
                local function accept(tx)
                    say(tx, c, c.words.yes, function(t4, req)
                        local a = (req.context or {}).acceptable
                        t4:ok(type(a) == "table" and a.mission == m.id, "offer not acceptable by speech in the request")
                    end, function(t4)
                        t4:eq("active", m.state, "model: the spoken yes did not accept the offer")
                        t4:ok(m.participants[c.cid] ~= nil, "character not a participant")
                        clientState(t4, m.id, "engaged", function(t5, st)
                            local row = st.row
                            t5:ok(row ~= nil and row.engaged, "accepted mission not in the notebook snapshot")
                            if m.mapZone then t5:ok(row ~= nil and row.mapZone, "zone not sent to the participant") end
                        end)
                    end)
                end
                if m then
                    t3:note("model offered " .. m.id .. " (" .. tostring(m.template) .. ")")
                    return clientState(t3, m.id, "offer", function(t3b, st)
                        t3b:ok(st.offerShown, "no on-screen offer message")
                        return accept(t3b)
                    end)
                end
                t3:note("model made no offer: scout offer created by the suite")
                m = directOffer(c)
                if m == nil then t3:skip("no offer from the model and no building around for a scout offer") end
                return accept(t3)
            end)
        end) end)
    end)

    -- The bubble is read on the requester client (RST.Steps "lk.speech.pieces": View.lastPieces and View.pieceLog of
    -- its LK_SpeechView); the cut is judged here with the same RS_TextCut.
    s.test("a long answer is shown in bubble pieces of whole sentences, one after another (E17-T13)", function(t)
        setup(t, function(t2, c)
            local TextCut = require "RadioSurvivor/RS_TextCut"
            say(t2, c, c.words.long, function() end, function(t3, _, answer)
                RST.Steps.ask(t3, "lk.speech.pieces", { answer = answer }, { target = "requester", timeoutMs = 240000,
                    assert = false }, function(t4, res)
                    local e = res.list[1] or {}
                    local d = e.data or {}
                    local pieces = d.pieces or {}
                    t4:ok(#pieces > 0, "bubble of the answer not read on the client: " .. tostring(e.message))
                    t4:note("answer of " .. string.len(answer) .. " characters in " .. #pieces .. " piece(s)")
                    for i, piece in ipairs(pieces) do t4:note(i .. " (" .. string.len(piece) .. "): " .. piece) end
                    t4:eq(nil, badCut(pieces, d.PIECE, TextCut), "bad cut")
                    t4:eq(TextCut.pieces(answer, 0)[1], table.concat(pieces, " "), "words cut or lost")
                    if #pieces < 2 then
                        t4:note("the answer fits one bubble: order of the pieces not measured")
                        return
                    end
                    local shown = d.shown or {}
                    t4:ok(#shown >= #pieces, "the pieces of the bubble were not all shown (" .. #shown .. "/" .. #pieces
                        .. "; body gone? another line on the same body?)")
                    for i = 1, #pieces do
                        t4:eq(pieces[i], shown[i].text, "piece " .. i .. " shown out of order")
                        if i > 1 then
                            local gap = shown[i].at - shown[i - 1].at
                            t4:ok(gap >= shown[i - 1].ms, "piece " .. i .. " shown " .. gap
                                .. " ms after the previous one, before its reading time of " .. shown[i - 1].ms)
                        end
                    end
                end)
            end)
        end)
    end)

    s.test("maybe later keeps the offer, the Accept button still works (E17-T09)", function(t)
        R.place(t, F.player(t), scoutFits, function(t1)
            setup(t1, function(t2, c)
                c.contact.exchanges = c.C.ACQUAINT_EXCHANGES
                local m = directOffer(c)
                t2:ok(m ~= nil, "no scout offer around the npc")
                say(t2, c, c.words.later, function(t3, req)
                    local a = (req.context or {}).acceptable
                    t3:ok(type(a) == "table" and a.mission == m.id, "open offer not in the request context")
                end, function(t3)
                    t3:eq("offer", m.state, "model: 'maybe later' accepted the offer")
                    RST.Steps.ask(t3, "carnet.send", { command = "accept", args = { mission = m.id,
                        revision = m.revision } }, { target = "requester", timeoutMs = 10000 }, function(t3b)
                        t3b:waitUntil(function() return m.state == "active" end, 5000, function(t4)
                            t4:ok(m.participants[c.cid] ~= nil, "character not a participant after the button")
                        end, "Accept button did not accept the offer")
                    end)
                end)
            end)
        end)
    end)
end)
