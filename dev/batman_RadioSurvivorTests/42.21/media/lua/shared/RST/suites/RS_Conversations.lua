--[[
rs.conversations - conversations between two nearby NPCs (E08-T04, server/RadioSurvivor/RS_Conversations.lua): two
Living Knox npcs created next to the player, both given a notebook fiche; the first one noticed a storm (observation
recorded here); E08-T11: their spots are searched around the player (RST.RSHelpers.pairSquares, bounded) where the
bodies see each other and the player hears the teller.
Heard by the player: a conversation opens and the second npc learns the story only once the first line is said
(heard_from:<teller>); a busy partner (hit less than 30 s ago) gets nothing. Tags "world" and "server": the authority
(solo or dedicated server), a save named rstest*, with a target player (t.ctx.player); Living Knox enabled.
Solo: RST.run({ suite = "rs.conversations", tags = "world" }); MP: RST.server({ suite = "rs.conversations",
tags = "world" }) from an admin client (campaign mp). E01-T16: the lines said by the npcs must reach the requester
client (RST.Steps "lk.speech.seen", its speech view) in solo and in MP.
E08-T05: "a player line joins the conversation in order" selects the teller and says one sentence through the notebook
of the REQUESTER client (RST.Steps "carnet.send" / "carnet.talk": same command as the local chat; the real network path
in MP).
The heard conversations need the bridge program running (bridge/radio_bridge.py): the lines are written by the
model. E08-T09: without an answer of the model two npcs do not talk (no template line): "a stopped bridge: no
conversation, no story" marks the bridge as stopped (RS_Initiatives.bridge, no bridge program needed). Every test
removes its npcs and their pending requests with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_PeerChecks"
require "RST/RST_RSHelpers"

RST.RSConversations = RST.RSConversations or {}

local function B() return LivingKnox and LivingKnox.Bodies end

local function setup(t)
    if not (LivingKnox and LivingKnox.isAuthority()) then t:skip("authority only (solo or dedicated server)") end
    local Server = RS_CarnetServer
    t:ok(Server ~= nil and Server.store.data ~= nil, "notebook server not ready")
    local V = require "RadioSurvivor/RS_Conversations"
    V.reset()
    local every = V.CFG.EVERY_MS
    V.CFG.EVERY_MS = 0
    t:defer(function() V.CFG.EVERY_MS = every end, "restore EVERY_MS")
    return Server, V, require "RadioSurvivor/RS_Observations"
end

-- New npc on the square sq (Bodies.spawn keeps a free square as is) with its notebook fiche; nil and the reason when
-- refused (the next spot is tried).
local function spawn(t, Server, sq)
    local id, body = B().spawn({}, sq:getX(), sq:getY(), sq:getZ())
    if id == nil then return nil, "spawn refused: " .. tostring(body) end
    local fiche = Server.ensure(id)
    t:defer(function()
        local kept = {}
        for _, r in ipairs(Server.pending) do if not fiche or r.npc ~= fiche.id then kept[#kept + 1] = r end end
        Server.pending = kept
        B().despawn(id, true)
    end, "forget " .. id)
    if fiche == nil then return nil, "no fiche for " .. tostring(id) end
    return id, fiche, body
end

-- E08-T11: spots searched around the player (RST.RSHelpers.pairSquares, bounded): the teller heard by the player, the
-- partner in sight of the teller (RS_Conversations.partnerOf: Provider.near, IsoGameCharacter.CanSee). Fixed offsets
-- failed next to the start house of the MP test server (2026-10-15: every pair behind a wall or out of earshot). The
-- rule is checked again on the real bodies, for at most SETTLE_MS (square of a new body), before the next pair.
local SETTLE_MS = 2000

-- Two npcs next to the player, in sight of each other, both mapped by the notebook, the teller with an observation.
local function pair(t, Server, Obs, subject, after)
    local P = require "RadioSurvivor/RS_NPCProvider"
    local C = require "RadioSurvivor/RS_Config"
    local V = require "RadioSurvivor/RS_Conversations"
    local R = RST.RSHelpers
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local spots = R.pairSquares(p, V.CFG.RANGE)
    t:ok(#spots > 0, "no pair of free squares in sight of each other, the first heard by the player, within "
        .. R.SPOT_RADIUS .. " squares of " .. R.at(p))
    local tried = {}
    local function ready(tb, pb) return P.near(tb, pb, V.CFG.RANGE) and P.hears(tb, p, C.HEARING_RANGE) end
    local function mapped(t1, c)
        t1:waitUntil(function() return Server.objects[c.teller.id] ~= nil and Server.objects[c.partner.id] ~= nil end,
            5000, function(t2)
                local key, why = Obs.record(c.teller.id, { fact = "weather", subject = subject, day = Obs.today(),
                    place = "everywhere" })
                t2:ok(key ~= nil, "observation refused: " .. tostring(why))
                c.key = key
                after(t2, c)
            end, "bodies of the fiches never mapped by the notebook")
    end
    local function attempt(t1, i)
        local spot = spots[i]
        t1:ok(spot ~= nil, "no spot where the two npcs see each other near the player " .. R.at(p) .. ": "
            .. table.concat(tried, ", "))
        local tid, tf, tb = spawn(t1, Server, spot.a)
        local pid, pf, pb
        if tid ~= nil then pid, pf, pb = spawn(t1, Server, spot.b) end
        if pid == nil then
            tried[#tried + 1] = R.at(spot.a) .. "/" .. R.at(spot.b) .. " (" .. tostring(pf or tf) .. ")"
            if tid ~= nil then B().despawn(tid, true) end
            return attempt(t1, i + 1)
        end
        local deadline = getTimestampMs() + SETTLE_MS
        t1:waitQuiet(function() return ready(tb, pb) or getTimestampMs() >= deadline end, SETTLE_MS + 1000,
            function(t2)
                if ready(tb, pb) then
                    return mapped(t2, { tellerId = tid, teller = tf, partnerId = pid, partner = pf })
                end
                tried[#tried + 1] = R.at(spot.a) .. "/" .. R.at(spot.b) .. " -> " .. R.at(tb) .. "/" .. R.at(pb)
                    .. " (sight " .. R.sightOf(tb, pb) .. "/" .. R.sightOf(pb, tb)
                    .. (P.hears(tb, p, C.HEARING_RANGE) and "" or ", player does not hear") .. ")"
                B().despawn(tid, true)
                B().despawn(pid, true)
                return attempt(t2, i + 1)
            end, "spot check never ended")
    end
    attempt(t, 1)
end

-- Delay of the notebook server between two sentences of a character (RS_Carnet_Server talk: C.COOLDOWN_MS, or the
-- chat slow mode of a dedicated server when longer).
local function talkCooldown()
    local C = require "RadioSurvivor/RS_Config"
    local slow = isServer() and getServerOptions():getInteger("ChatMessageSlowModeTime") * 1000 or 0
    return math.max(C.COOLDOWN_MS, slow)
end

local function knows(Obs, fiche, key)
    for _, item in ipairs(Obs.list(fiche.id)) do
        if item.key == key then return item end
    end
    return nil
end

-- E08-T05: the player line joined the conversation; it keeps its place until the conversation ends.
local function joined(t3, c, V, Server, conv, joined0)
    local recent = 0
    for _, when in ipairs(Server.times or {}) do
        if getTimestampMs() - when < 3600000 then recent = recent + 1 end
    end
    t3:eq(joined0 + 1, V.stats.joined, "player line not joined: " .. #Server.pending
        .. " pending request(s), " .. recent .. " request(s) in the last hour")
    local index = #conv.lines
    local mine = conv.lines[index]
    t3:ok(mine and mine.player == true, "last line is not the player's")
    local asked = V.stats.llm
    t3:waitUntil(function() return V.of(c.teller.id) == nil end, 100000, function(t4)
        t4:ok(conv.lines[index] == mine, "the player line lost its place in the conversation")
        t4:note("conversation over: " .. #conv.lines .. " line(s), stale lines: "
            .. tostring(V.stats.stale) .. ", lines asked after the sentence: "
            .. tostring(V.stats.llm - asked))
    end, "conversation never ended within 100 s")
end

-- E08-T05: the sentence joins at its admission (RS_Carnet_Server talk, before any model call): no wait for the model.
-- Not joined within 10 s: the refusal read on the requester client (notebook error: Cooldown, Busy, Range...) names
-- the cause.
local function waitJoined(t, c, V, Server, conv, joined0)
    local deadline = getTimestampMs() + 10000
    t:waitQuiet(function() return V.stats.joined > joined0 or getTimestampMs() >= deadline end, 15000, function(t3)
        if V.stats.joined > joined0 then return joined(t3, c, V, Server, conv, joined0) end
        RST.Steps.ask(t3, "carnet.state", {}, { target = "requester", timeoutMs = 5000 }, function(t4, res)
            local e = res.list[1]
            local why = e and e.data and e.data.lastError or nil
            t4:ok(false, "player line not joined within 10 s (notebook refusal " .. tostring(why) .. ", "
                .. #Server.pending .. " pending request(s), conversation "
                .. (V.of(c.teller.id) and "open" or "over") .. ")")
        end)
    end, "player line wait never ended")
end

RST.suite("rs.conversations", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 }, function(s)
    s.test("a heard conversation passes the story after the first line", function(t)
        local Server, V, Obs = setup(t)
        local said = RST.PeerChecks.recordSpeech(t)
        pair(t, Server, Obs, "storm", function(t2, c)
            local kind = V.tick(Server)
            t2:eq("opened", kind, "no conversation opened (is the player within earshot?)")
            local since = getTimestampMs()   -- E17-T15: cause of a missing line named by the failure message
            t2:waitUntil(function() return knows(Obs, c.partner, c.key) ~= nil end, 90000, function(t3)
                local item = knows(Obs, c.partner, c.key)
                t3:eq("heard_from:" .. c.teller.id, item.source, "provenance of the story")
                t3:ok(knows(Obs, c.teller, c.key).source == "seen", "story went back to its teller")
                t3:note("story received; lines said: " .. tostring(V.stats.said))
                -- E01-T16: the lines heard by the requester reached its speech view (bubbles).
                local mine = {}
                for _, line in ipairs(said) do
                    if line.npc == c.tellerId or line.npc == c.partnerId then mine[#mine + 1] = line end
                end
                t3:ok(#mine > 0, "no conversation line said through LivingKnox.Speech")
                RST.Steps.ask(t3, "lk.speech.seen", { lines = mine }, { target = "requester", timeoutMs = 10000 })
            end, function() return "story never received within 90 s: " .. RST.RSHelpers.bridgeCause(Server, since) end)
        end)
    end)

    -- E08-T05: the player selects the teller (same path as Ctrl+G) and speaks (same path as the notebook Say line):
    -- the sentence joins the conversation in order; no conversation line is asked while the answer is awaited.
    s.test("a player line joins the conversation in order", function(t)
        local Server, V, Obs = setup(t)
        -- The notebook server refuses a sentence of the same character within C.COOLDOWN_MS of its previous one
        -- (Server.lastTalk, 'Cooldown'; slow mode of the chat in MP): the previous suites talk a few seconds before
        -- (campaign 2026-10-15: refused 9 s after rs.relation). Wait for it BEFORE the pair is made: the observation
        -- recorded by pair() lets the server pass open the conversation by itself (EVERY_MS = 0).
        local cid0 = Server.bound[RST.Fixtures.player(t)]
        local quiet = talkCooldown()
        t:waitQuiet(function()
            local last = cid0 and Server.lastTalk[cid0]
            return last == nil or getTimestampMs() - last >= quiet + 200
        end, quiet + 5000, function(t1)
            pair(t1, Server, Obs, "fog", function(t2, c)
                t2:eq("opened", V.tick(Server), "no conversation opened (is the player within earshot?)")
                local conv = V.of(c.teller.id)
                t2:ok(conv ~= nil, "conversation not found")
                local Steps = RST.Steps
                local joined0 = V.stats.joined
                -- Requester client: select the teller (same path as Ctrl+G), then the notebook Say line. Solo:
                -- sendClientCommand queues the commands (SinglePlayerServer.addIncoming), read at the next logic
                -- update; MP: network delay and commands not ordered: the Say line is sent only once the authority
                -- selected the teller.
                local cid = Server.bound[RST.Fixtures.player(t2)]
                Steps.ask(t2, "carnet.send", { command = "select", args = { incarnation = c.tellerId } },
                    { target = "requester", timeoutMs = 10000 }, function(t2a)
                        t2a:waitUntil(function() return cid ~= nil and Server.selected[cid] == c.teller.id end, 5000,
                            function(t2b)
                                local say = { text = "What are you two talking about?", cooldownMs = 0 }
                                Steps.ask(t2b, "carnet.talk", say, { target = "requester", timeoutMs = 30000 },
                                    function(t2c) waitJoined(t2c, c, V, Server, conv, joined0) end)
                            end, "teller not selected by the notebook")
                    end)
            end)
        end, "previous sentence of the character still within the notebook cooldown")
    end)

    -- E08-T09: without an answer of the model, no heard conversation opens: no line, no template, no story passed.
    s.test("a stopped bridge: no conversation, no story", function(t)
        local Server, V, Obs = setup(t)
        local I = require "RadioSurvivor/RS_Initiatives"
        local P = require "RadioSurvivor/RS_NPCProvider"
        local said = RST.PeerChecks.recordSpeech(t)
        local barks, bark = 0, P.bark
        P.bark = function(...) barks = barks + 1; return bark(...) end
        t:defer(function() P.bark = bark end, "restore Provider.bark")
        local down, probeAt = I.bridge.down, I.bridge.probeAt
        I.bridge.down, I.bridge.probeAt = true, getTimestampMs() + 600000
        t:defer(function() I.bridge.down, I.bridge.probeAt = down, probeAt end, "restore the bridge state")
        pair(t, Server, Obs, "rain", function(t2, c)
            t2:eq(nil, V.tick(Server), "conversation opened without the bridge")
            t2:eq(nil, V.of(c.teller.id), "conversation in progress without the bridge")
            t2:eq(nil, knows(Obs, c.partner, c.key), "story passed without a conversation")
            t2:eq(0, barks, "Provider.bark called without the bridge")
            local mine = 0
            for _, line in ipairs(said) do
                if line.npc == c.tellerId or line.npc == c.partnerId then mine = mine + 1 end
            end
            t2:eq(0, mine, "line said without the bridge")
        end)
    end)

    s.test("a busy partner (hit less than 30 s ago) learns nothing", function(t)
        local Server, V, Obs = setup(t)
        pair(t, Server, Obs, "blizzard", function(t2, c)
            B().lastHits[c.partnerId] = { ms = getTimestampMs() }
            t2:eq(nil, V.tick(Server), "conversation with a busy npc")
            t2:eq(nil, knows(Obs, c.partner, c.key), "story learned by a busy npc")
            B().lastHits[c.partnerId] = nil
        end)
    end)
end)

return RST.RSConversations
