--[[
RST_PeerChecksE09 - authority helpers of the relation, agreement, incident and leader suites (E09-T04, E09-T05,
E09-T06, E10-T02: rs.relation, rs.factions.accord, rs.factions.incident, rs.carnet.leader). Development mod only.
Load with: require "RST/RST_PeerChecksE09" (shared; the helpers run on the authority: solo or dedicated server; the
client side uses the existing steps "carnet.send", "carnet.talk", "carnet.state" of RST_PeerChecks.lua and
"rs.faction" of RST_PeerChecksRadio.lua). No side effect at load time.

The model's decision is never awaited: the suites put in the bridge reply file a reply of their own (fabricated, valid
for the request) and let the REAL notebook server read and check it (RS_Carnet_Server poll -> reply -> Relations.apply,
Factions.conclude, collectiveCheck, RS_Incidents.reply). The bridge, real or fake, may run: its answer to a request
taken by a rule is dropped. Works without any bridge.

    local E9 = RST.PeerChecksE09
    E9.intercept(t) -> ctl    wraps RS_Transport.readNpc (restored by t:defer) with rules, first match wins:
        ctl.rule(match, build) -> rule   match(req) -> bool for a pending request of the notebook; build(req) -> the
                                         reply (E9.reply) or nil to HOLD it (no reply now, the bridge answer dropped)
        rule.off = true                  the rule stops matching (requests go back to the bridge)
        rule.seen = { [request id] = req }, rule.sent = { [request id] = true }
        ctl.quiet(ficheIds)              npc_enrich / initiative / conversation / member requests of these fiches
                                         answered at once with a neutral reply (one request per fiche at a time)
        ctl.blackout = true              no reply at all is read (bridge silent, as when it is stopped): no request
                                         leaves the queue, so RS_Initiatives never sees an answer meanwhile
    E9.faction(t, p1, u2, after)     vanilla faction of the requester with u2 as a plain member (MP only)
    E9.reply(req, fields)     npc_reply of a request: version, kind, id, world, run, npc, order, revision copied;
                              text E9.TEXT, intent "none", offer "" unless given in fields
    E9.fixture(t, p, suite)   a NEW fixture group (RST.LKGroup: settlers, leader m-1, fighter m-2) near p even when a
                              group of the population is loaded (two members of one group, both embodied);
                              suite(t, gid, leaderNpc, memberNpc)
    E9.fiche(t, Server, npc, after)
                              notebook fiche of npc, waited until its body is mapped by the notebook; after(t, fiche)
    E9.who(t, p, label)       { name (account, "local" in solo), player, cid, label, target (RST.Steps target) }
    E9.second(t)              the second online player of a dedicated server: player, account; nil in solo or alone
    E9.requireSecond(t, why)  SKIP in solo ("solo: <why>"), SKIP on a server with one client, else player, account
    E9.sight(t, who, c, after)       body of c.npc in sight (SELECT_RANGE - E9.SIGHT_MARGIN, clear line) and hearing
                                     of who: when it is not within E9.SIGHT_SETTLE_MS, who is moved next to it (free
                                     square, of its room first, clear line both ways; moved back at the end); after(t)
    E9.inSight(who, c[, margin])     Provider.near of the selection (range reduced by margin) and Provider.hears of
                                     the reply line
    E9.why(who, c)                   diagnostic text: positions, range, sight, binding, selection
    E9.selectBy(t, who, c, after)    E9.sight, then who selects c.fiche with the notebook (step "carnet.send" select,
                                     as RST.RSHelpers.select for any client); after(t)
    E9.acquainted(c, cid)            contact of cid with c.fiche, exchanges set to ACQUAINT_EXCHANGES
    E9.talkBy(t, who, c, text, after) notebook cooldown of the client spent first (E9.talkAt), then sight, hearing
                                     and selection restored (E9.sight, E9.selectBy when the notebook cleared it), then
                                     who says text (step "carnet.talk"); waits for its npc_talk request (E9.requestOf:
                                     install E9.intercept first); after(t, req)
    E9.settled(c, req)               true once req left the pending list of the notebook
    E9.heard(Server, cid, fiche, reqId) -> text of the history line of reqId in the contact of cid, or nil
    E9.pendingOf(Server, kind, ficheId[, character, text]) -> first pending request of that kind for that fiche, or nil
    E9.requestOf(...)                same, or a request already answered that the reader of E9.intercept saw pending
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_LKGroupFixture"
require "RST/RST_PeerChecks"
require "RST/RST_RSHelpers"

RST.PeerChecksE09 = RST.PeerChecksE09 or {}
local E9 = RST.PeerChecksE09
local Steps = RST.Steps

E9.TEXT = "RST fabricated reply of the test."
E9.MAPPED_MS = 10000
E9.SELECT_MS = 5000
E9.REQUEST_MS = 15000
E9.TALK_MS = 60000

local function isServerSide() return type(isServer) == "function" and isServer() end

-- ---------------------------------------------------------------- replies

function E9.reply(req, fields)
    local r = { version = 2, kind = "npc_reply", id = req.id, world = req.world, run = req.run, npc = req.npc,
        order = req.order, revision = req.revision, text = E9.TEXT, intent = "none", offer = "" }
    for k, v in pairs(fields or {}) do r[k] = v end
    return r
end

function E9.intercept(t)
    local T = require "RadioSurvivor/RS_Transport"
    local Server = RS_CarnetServer
    local ctl = { rules = {}, seenAll = {} }
    local original = T.readNpc
    local function wrapped()
        if ctl.blackout then return {} end
        local answers = original()
        local out = {}
        for k, v in pairs(answers or {}) do out[k] = v end
        for _, req in ipairs(Server and Server.pending or {}) do
            ctl.seenAll[req.id] = req
            for _, rule in ipairs(ctl.rules) do
                if not rule.off and rule.match(req) then
                    rule.seen[req.id] = req
                    out[req.id] = nil
                    local res = rule.build(req)
                    if res ~= nil then
                        out[req.id] = res
                        rule.sent[req.id] = true
                    end
                    break
                end
            end
        end
        return out
    end
    T.readNpc = wrapped
    E9.active = ctl
    t:defer(function()
        if T.readNpc == wrapped then T.readNpc = original end
        if E9.active == ctl then E9.active = nil end
    end, "bridge reply file read as usual")
    function ctl.rule(match, build)
        local rule = { match = match, build = build, seen = {}, sent = {} }
        ctl.rules[#ctl.rules + 1] = rule
        return rule
    end
    -- Requests of these fiches other than npc_talk and npc_incident (background enrichment, initiative, conversation,
    -- member reaction) answered at once with a neutral reply: the notebook serves one request per fiche at a time, a
    -- background request left to an absent bridge would hold the talk requests of the test for REQUEST_TIMEOUT_MS.
    function ctl.quiet(ficheIds)
        return ctl.rule(function(req)
            return ficheIds[req.npc] == true and req.kind ~= "npc_talk" and req.kind ~= "npc_incident"
        end, function(req)
            if req.kind == "npc_enrich" then return E9.reply(req, { background = "A survivor of the test." }) end
            return E9.reply(req, {})
        end)
    end
    return ctl
end

-- ---------------------------------------------------------------- players

function E9.who(t, p, label)
    local R = RST.RSHelpers
    local mp = isServerSide()
    local name = mp and p:getUsername() or Steps.LOCAL
    local requester = t.ctx and t.ctx.player
    local target = (not mp or p == requester) and "requester" or { name }
    return { name = name, player = p, cid = R.character(t, p), label = label, target = target }
end

function E9.second(t)
    if not isServerSide() then return nil end
    local others = Steps.others(t)
    local name = others[1]
    local p = name and Steps.playerOf(name) or nil
    if p == nil then return nil end
    return p, name
end

function E9.requireSecond(t, why)
    if not isServerSide() then t:skip("solo: " .. why .. " needs a second player (MP campaign, two clients)") end
    local p, name = E9.second(t)
    if p == nil then t:skip("one client online: " .. why .. " needs a second client (autoclient.py --mp --clients 2)") end
    return p, name
end

-- Vanilla faction of the requester p1 (created by its faction panel packet, step "rs.faction" of
-- RST_PeerChecksRadio.lua) with account u2 as a plain member (Faction:addPlayer, what an accepted invitation does on
-- the server); disbanded by its owner at the end. FAIL when a test account is already in a faction (a former suite
-- left it there). after(t, faction). Dedicated server only.
E9.FACTION_MS = 10000
function E9.faction(t, p1, u2, after)
    local F = require "RadioSurvivor/RS_Factions"
    local u1 = p1:getUsername()
    t:ok(Faction.getPlayerFaction(u1) == nil and Faction.getPlayerFaction(u2) == nil,
        "a test account is already in a faction (left by a former suite?)")
    local name = "RSE" .. tostring(ZombRand(10000, 99999))
    Steps.ask(t, "rs.faction", { op = "create", name = name }, { target = "requester", timeoutMs = E9.FACTION_MS },
        function(t2)
            t2:defer(function(tc)
                local f = Faction.getPlayerFaction(u1)
                if f == nil then return end
                Steps.ask(tc, "rs.faction", { op = "disband" }, { target = "requester", timeoutMs = E9.FACTION_MS,
                    assert = false }, function(tc2)
                    tc2:waitQuiet(function() return not Faction.getFactions():contains(f) end, E9.FACTION_MS,
                        function() end, "faction still there")
                end)
            end, "test faction disbanded by its owner")
            t2:waitUntil(function() return Faction.getPlayerFaction(u1) end, E9.FACTION_MS, function(t3, f)
                f:addPlayer(u2)
                t3:ok(f:isMember(u2), u2 .. " not added to the faction")
                F.sync(true)
                return after(t3, f)
            end, "faction never created on the server (FactionCreate refused: server option Faction?)")
        end)
end

-- ---------------------------------------------------------------- group and fiches

function E9.fixture(t, p, suite)
    local LG = RST.LKGroup
    local calls = 0
    LG.ensure(t, p, function(t2, gid, _, created)
        t2:ok(created == true, "no fixture group created (a group of the population was used)")
        return suite(t2, gid, LG.memberNpc(gid, "m-1"), LG.memberNpc(gid, "m-2"))
    end, { ready = function()
        calls = calls + 1
        return calls > 1
    end })
end

function E9.fiche(t, Server, npc, after)
    local fiche = Server.ensure(npc)
    t:ok(fiche ~= nil, "no notebook fiche for " .. tostring(npc))
    t:waitQuiet(function() return Server.objects[fiche.id] ~= nil end, E9.MAPPED_MS,
        function(t2) return after(t2, fiche) end, "body of " .. tostring(npc) .. " never mapped by the notebook")
end

function E9.acquainted(c, cid)
    local C = require "RadioSurvivor/RS_Config"
    local record = c.Server.store.data.characters[cid]
    local contact = record and record.contacts[c.fiche.id]
    if contact ~= nil then contact.exchanges = math.max(contact.exchanges or 0, C.ACQUAINT_EXCHANGES) end
    return contact
end

-- ---------------------------------------------------------------- sight of the selecting player

-- The notebook selects and serves a talk only while the npc body is in sight (RS_Carnet_Server: Provider.near, same
-- floor, SELECT_RANGE, IsoGameCharacter.CanSee = LosUtil.lineClear ~= Blocked), checked again every second. A fixture
-- group walks to its posts (sentry at a door or window, forager outside the room) and a second player stands one
-- square aside: the body may be behind a wall of the house (MP campaign of 2026-10-15: "did not select lk-2", "client
-- rs_mp2 did not select lk-13"). E9.sight brings the player next to the body first, on a free square with a clear
-- line both ways (moved back by the t:defer of RST.Fixtures.movePlayer); nothing moves when it is already in sight.
E9.SIGHT_MARGIN = 2         -- squares kept under SELECT_RANGE (the body keeps walking)
E9.SIGHT_SETTLE_MS = 2000   -- the body may come into sight by itself (walk in progress)

local function provider() return require "RadioSurvivor/RS_NPCProvider" end

local function bodyOf(c) return c.Server.objects[c.fiche.id] end

local function clear(cell, ax, ay, az, bx, by, bz)
    return tostring(LosUtil.lineClear(cell, ax, ay, az, bx, by, bz, false)) ~= "Blocked"
end

-- In sight for the selection AND within hearing of the reply: the notebook keeps the answer line only for the players
-- who hear the body (Provider.hears: same room, or both outside within 0.6 x HEARING_RANGE; a body outside behind a
-- closed door is seen through a window but not heard: SOLO campaign of 2026-10-15, "reply of the help not kept").
function E9.inSight(who, c, margin)
    local C = require "RadioSurvivor/RS_Config"
    local P, body = provider(), bodyOf(c)
    return body ~= nil and P.near(who.player, body, C.SELECT_RANGE - (margin or 0))
        and P.hears(body, who.player, C.HEARING_RANGE)
end

-- Diagnostic of a refused selection or talk (positions, range, line of sight, binding of the player).
function E9.why(who, c)
    local R, C = RST.RSHelpers, require "RadioSurvivor/RS_Config"
    local body, p = bodyOf(c), who.player
    if body == nil then return "body of " .. tostring(c.npc) .. " not mapped by the notebook" end
    local bound = c.Server.bound[p]
    return "body at " .. R.at(body) .. "," .. math.floor(body:getZ()) .. ", player at " .. R.at(p) .. ","
        .. math.floor(p:getZ()) .. ", near " .. tostring(provider().near(p, body, C.SELECT_RANGE)) .. ", hears "
        .. tostring(provider().hears(body, p, C.HEARING_RANGE)) .. ", sight "
        .. (LosUtil ~= nil and R.sightOf(p, body) or "unknown") .. ", npc alive " .. tostring(c.fiche.alive)
        .. ", bound " .. tostring(bound == who.cid) .. " (" .. tostring(bound) .. "), selected "
        .. tostring(c.Server.selected[who.cid])
end

-- Free square next to the body (1 then 2 squares) with a clear line both ways, the nearest to the player: first in
-- the body's room (or outside with it: the reply is heard), then any (a sentry at a door or window post may have no
-- free square of its room around it: MP campaign of 2026-10-15); or nil.
local function sightSquare(who, body)
    local cell = getCell()
    local bx, by, bz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
    local here = cell:getGridSquare(bx, by, bz)
    local room = here ~= nil and here:getRoom() or nil
    local px, py = who.player:getX(), who.player:getY()
    for pass = 1, 2 do
        for ring = 1, 2 do
            local best, bestD = nil, nil
            for dx = -ring, ring do
                for dy = -ring, ring do
                    if math.max(math.abs(dx), math.abs(dy)) == ring then
                        local x, y = bx + dx, by + dy
                        local sq = cell:getGridSquare(x, y, bz)
                        if sq ~= nil and sq:isFree(false) and not sq:HasStairs() and sq:getMovingObjects():size() == 0
                            and (pass == 2 or sq:getRoom() == room)
                            and clear(cell, x, y, bz, bx, by, bz) and clear(cell, bx, by, bz, x, y, bz) then
                            local d = (x + 0.5 - px) * (x + 0.5 - px) + (y + 0.5 - py) * (y + 0.5 - py)
                            if bestD == nil or d < bestD then best, bestD = sq, d end
                        end
                    end
                end
            end
            if best ~= nil then return best end
        end
    end
    return nil
end

function E9.sight(t, who, c, after)
    t:waitQuiet(function() return bodyOf(c) ~= nil end, E9.MAPPED_MS, function(t1)
        local deadline = RST.now() + E9.SIGHT_SETTLE_MS
        t1:waitQuiet(function()
            return E9.inSight(who, c, E9.SIGHT_MARGIN) or RST.now() >= deadline
        end, E9.SIGHT_SETTLE_MS + 1000, function(t2)
            if E9.inSight(who, c, E9.SIGHT_MARGIN) then return after(t2) end
            local sq = sightSquare(who, bodyOf(c))
            t2:ok(sq ~= nil, "no free square in sight of " .. tostring(c.npc) .. " for " .. who.label .. ": "
                .. E9.why(who, c))
            t2:note(who.label .. " moved next to " .. tostring(c.npc) .. " (" .. E9.why(who, c) .. ")")
            RST.Fixtures.movePlayer(t2, who.player, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), function(t3)
                t3:waitUntil(function() return E9.inSight(who, c) end, E9.SIGHT_SETTLE_MS, after, function()
                    return who.label .. " still out of sight of " .. tostring(c.npc) .. " after the move: "
                        .. E9.why(who, c)
                end)
            end)
        end, "body of " .. tostring(c.npc) .. " never settled")
    end, "body of " .. tostring(c.npc) .. " never mapped by the notebook")
end

-- The body keeps walking (fixture group: forager out of the house, sentry to its post) between the sight check and
-- the command: a selection refused for range or sight is tried again (E9.ATTEMPTS, sight checked again each time;
-- MP campaign of 2026-10-15: "body at 10658,10142, sight Blocked" after a check passed).
E9.ATTEMPTS = 3

function E9.selectBy(t, who, c, after, attempt)
    attempt = attempt or 1
    E9.sight(t, who, c, function(t1)
        Steps.ask(t1, "carnet.send", { command = "select", args = { incarnation = c.npc } },
            { target = who.target, timeoutMs = 10000 }, function(t2)
                local deadline = RST.now() + E9.SELECT_MS
                t2:waitQuiet(function()
                    if c.Server.selected[who.cid] == c.fiche.id then return "selected" end
                    if RST.now() >= deadline then return "late" end
                    return nil
                end, E9.SELECT_MS + 1000, function(t3, res)
                    if res == "selected" then return after(t3) end
                    if attempt < E9.ATTEMPTS then
                        t3:note(who.label .. ": selection of " .. tostring(c.npc) .. " refused, tried again ("
                            .. E9.why(who, c) .. ")")
                        return E9.selectBy(t3, who, c, after, attempt + 1)
                    end
                    t3:ok(false, who.label .. " did not select " .. tostring(c.npc) .. " with the notebook (range or "
                        .. "sight) after " .. attempt .. " attempt(s): " .. E9.why(who, c))
                end, "selection of " .. tostring(c.npc) .. " never answered")
            end)
    end)
end

local function matches(r, kind, ficheId, character, text)
    return r.kind == kind and r.npc == ficheId and (character == nil or r.character == character)
        and (text == nil or r.text == text)
end

function E9.pendingOf(Server, kind, ficheId, character, text)
    for _, r in ipairs(Server.pending) do
        if matches(r, kind, ficheId, character, text) then return r end
    end
    return nil
end

-- Pending now, or seen pending by the reader of E9.intercept (a reply of the test may take it out of the queue at the
-- very pass that follows its creation, before the suite's next wait step).
function E9.requestOf(Server, kind, ficheId, character, text)
    local r = E9.pendingOf(Server, kind, ficheId, character, text)
    if r ~= nil or E9.active == nil then return r end
    for _, seen in pairs(E9.active.seenAll) do
        if matches(seen, kind, ficheId, character, text) then return seen end
    end
    return nil
end

-- The body may have walked out of sight since the selection (the notebook then clears it): sight and selection
-- are restored first (no step when both still hold).
local function selectedNow(t, who, c, after)
    E9.sight(t, who, c, function(t1)
        if c.Server.selected[who.cid] == c.fiche.id then return after(t1) end
        return E9.selectBy(t1, who, c, after)
    end)
end

local function talkNow(t, who, c, text, after, attempt)
    local C = require "RadioSurvivor/RS_Config"
    Steps.ask(t, "carnet.talk", { text = text, cooldownMs = C.COOLDOWN_MS + 500 },
        { target = who.target, timeoutMs = E9.TALK_MS }, function(t1)
            E9.talkAt[who.name] = RST.now()
            local deadline = RST.now() + E9.REQUEST_MS
            t1:waitQuiet(function()
                local req = E9.requestOf(c.Server, "npc_talk", c.fiche.id, who.cid, text)
                if req ~= nil then return { req = req } end
                -- A talk refused for range or sight clears the selection at once (RS_Carnet_Server talk).
                if c.Server.selected[who.cid] ~= c.fiche.id and attempt < E9.ATTEMPTS then return { lost = true } end
                if RST.now() >= deadline then return { missing = true } end
                return nil
            end, E9.REQUEST_MS + 1000, function(t2, res)
                if res.req ~= nil then return after(t2, res.req) end
                if res.lost then
                    t2:note(who.label .. ": '" .. text .. "' refused (selection lost: " .. E9.why(who, c)
                        .. "), said again")
                    return E9.talkBy(t2, who, c, text, after, attempt + 1)
                end
                local last = c.Server.refusals[#c.Server.refusals]
                t2:ok(false, "no npc_talk request of " .. who.label .. " for '" .. text .. "'"
                    .. (last and (" (last refusal: " .. tostring(last.reason) .. ")") or "") .. ": " .. E9.why(who, c))
            end, "npc_talk request of " .. who.label .. " never awaited")
        end)
end

-- The client step waits for the notebook cooldown (C.COOLDOWN_MS after its last sentence) before it speaks: the body
-- may walk away meanwhile (SOLO campaign of 2026-10-15: the leader went out and closed the door during the wait).
-- The wait is spent here first (the last sentence of this account through E9, or a whole cooldown when unknown: a
-- former suite may have spoken), so that sight and hearing are checked right before the sentence leaves. A sentence
-- refused because the body walked out of sight (selection cleared, no request) is said again (E9.ATTEMPTS).
E9.talkAt = E9.talkAt or {}
E9.COOLDOWN_SLACK_MS = 700

function E9.talkBy(t, who, c, text, after, attempt)
    attempt = attempt or 1
    local C = require "RadioSurvivor/RS_Config"
    local last = E9.talkAt[who.name]
    local free = (last or RST.now()) + C.COOLDOWN_MS + E9.COOLDOWN_SLACK_MS
    t:waitQuiet(function() return RST.now() >= free end, C.COOLDOWN_MS + E9.COOLDOWN_SLACK_MS + 1000, function(t1)
        selectedNow(t1, who, c, function(t0) return talkNow(t0, who, c, text, after, attempt) end)
    end, "notebook cooldown never over")
end

function E9.settled(c, req)
    for _, r in ipairs(c.Server.pending) do if r.id == req.id then return false end end
    return true
end

function E9.heard(Server, cid, fiche, reqId)
    local record = Server.store.data.characters[cid]
    local contact = record and record.contacts[fiche.id]
    for _, h in ipairs(contact and contact.history or {}) do
        if h.id == reqId then return h.text end
    end
    return nil
end

return E9
