if isClient() then return end
--[[
Living Knox: the queue of the NPC speech requests (E18-T17; contract docs/specifications-techniques/protocole-carnet-v2.md).
Authority only. Decision of 2026-11-06: an NPC of the world has Living Knox as its origin; the core mod only carries the
requests (RC_Transport, lanes npc and acks) and gives each answer back to this module.

Here: the admitted sentence of a player (Talk.speak), the requests npc_talk, npc_enrich, npc_member, npc_incident,
npc_initiative and npc_converse, their order and revision per speaker, delays, refusals, acknowledgements, the checks
of every reply, the decisions that belong to a group (collective binding, agreement, departure, member reactions).
The host (LK_TalkHost) gives the speakers and adds its context and its actions.

One request per speaker at the bridge: heads of the queue only (Talk.sync); the others wait.

Private state, two slot files written in turn (RC_SlotFile): Zomboid/Lua/batman_LivingKnox/talk-<hex of
"mode/world">-<0|1>.txt, header LKTALK1, never a global ModData:
  data = { acks = bounded outbox of acknowledgements, a restart must not lose them,
           initiatives = { done, last } (LK_Initiatives), conversations = { pairs } (LK_Conversations) }
The requests in the queue live in memory only: after a restart the bridge answers no old session.
Console messages in English.
]]
local Talk = require "LivingKnox/LK_TalkHost"
local Speech = require "RadioSurvivorCore/RC_SpeechConfig"
local Transport = require "RadioSurvivorCore/RC_Transport"
local Codec = require "RadioSurvivorCore/RC_Codec"
local Rep = require "RadioSurvivorCore/RC_Reputation"
local SlotFile = require "RadioSurvivorCore/RC_SlotFile"
local WorldStart = require "RadioSurvivorCore/RC_WorldStart"
require "LivingKnox/LK_Incidents"
require "LivingKnox/LK_Initiatives"
require "LivingKnox/LK_Conversations"

local P, Obs = Talk.provider, Talk.observations

Talk.DIR = "batman_LivingKnox/"
Talk.HEADER = "LKTALK1"
Talk.MAX_ACKS = 16
Talk.MAX_REFUSALS = 16
Talk.MEMBER_REACTIONS = 2
Talk.MEMBER_REPLY_BYTES = 200 -- LivingKnox.Speech.MAX_TEXT: the line is spoken by the engine's proximity speech
Talk.pending = Talk.pending or {}         -- queue, oldest first
Talk.times = Talk.times or {}             -- calls of the last real hour, common cap Speech.MAX_PER_HOUR
Talk.enrichTimes = Talk.enrichTimes or {}
Talk.enrichAttempts = Talk.enrichAttempts or {}
Talk.lastTalk = Talk.lastTalk or {}       -- [character] = time of its last admitted sentence
Talk.collectives = Talk.collectives or {} -- [request id] = group binding of a collective intention (E10-T02)
Talk.relations = Talk.relations or {}     -- [request id] = relation binding (E09-T04)
Talk.reactions = Talk.reactions or {}     -- [request id] = { ref, about } of a member reaction (E10-T03)
Talk.reactionQueue = Talk.reactionQueue or {}
Talk.refusals = Talk.refusals or {}       -- last refused requests, newest last (E17-T15)
Talk.store = Talk.store or { seq = 0, base = nil, blocked = false }

local enrichAt = 0

Transport.register("npc", { order = 20 })
Transport.register("acks", { order = 30 })

local function Agreements() return type(LivingKnox) == "table" and LivingKnox.Agreements or nil end

local function oneLine(text)
    text = string.gsub(tostring(text or ""), "[\r\n\t]", " ")
    local first = string.find(text, "%S")
    if not first then return "" end
    return string.sub(text, first, string.find(text, "%S%s*$", first))
end
Talk.oneLine = oneLine

-- Host ------------------------------------------------------------------------------------------------------------

function Talk.fiche(id) return Talk.host.fiche(id) end
function Talk.find(id) return Talk.host.find(id) end
function Talk.ensure(id) return Talk.host.ensure(id) end
function Talk.objects() return Talk.host.objects() end
function Talk.bound() return Talk.host.bound() end
function Talk.characterName(character) return Talk.host.characterName(character) end
function Talk.remember(npc, id, text, players) return Talk.host.remember(npc, id, text, players) end

-- Storage ---------------------------------------------------------------------------------------------------------

local function log(msg) print("[LivingKnox] talk: " .. tostring(msg)) end

local function fresh() return { acks = {}, initiatives = { done = {}, last = {} }, conversations = { pairs = {} } } end

function Talk.init(newWorld)
    local st = Talk.store
    if Talk.data ~= nil or st.blocked then return Talk.data ~= nil end
    st.base = SlotFile.worldBase(Talk.DIR, "talk")
    local isNew = WorldStart.isNewWorld(newWorld == true)
    local best, broken = nil, false
    if not isNew then best, broken = SlotFile.read(st.base, Talk.HEADER) end
    if broken then
        st.blocked = true
        log("STORAGE BLOCKED: file unreadable, kept as is; speech state is not saved this session")
        return false
    end
    Talk.data, st.seq = best and best.data or fresh(), best and best.seq or 0
    Transport.acks = Talk.data.acks
    return true
end

-- True when the state is loaded (loaded now if the world exists and OnInitGlobalModData was missed).
function Talk.ensureData()
    if Talk.data ~= nil then return true end
    if Talk.store.blocked or getWorld == nil or getWorld() == nil then return false end
    return Talk.init(false)
end

local function writeState()
    local st = Talk.store
    if Talk.data == nil or st.blocked then return false end
    local ok, why = SlotFile.write(st.base, Talk.HEADER, st.seq + 1, Talk.data)
    if not ok then
        log("ERROR not saved: " .. tostring(why))
        return false
    end
    st.seq, Talk.dirty = st.seq + 1, false
    return true
end

-- Saves this module (when changed) and the host. False when one of them could not be written.
function Talk.save()
    local ok = not Talk.dirty or writeState()
    return Talk.host.save() and ok
end

function Talk.attach(host)
    Talk.host = host
    return Talk.ensureData()
end

-- Requests --------------------------------------------------------------------------------------------------------

function Talk.enqueue(npc, kind, character, text, language, context, offers)
    npc.order = npc.order + 1
    -- E10-T03: loyalty derived now by the provider (group morale, seniority), never stored on the fiche.
    local personality, loyalty = npc.personality, P.loyalty(npc.incarnation)
    if loyalty and type(personality) == "table" then
        personality = {}
        for k, v in pairs(npc.personality) do personality[k] = v end
        personality.loyalty = loyalty
    end
    local world, run = Talk.host.session()
    local request = { version = 2, kind = kind, id = run .. "-" .. npc.order .. "-" .. npc.id,
        world = world, run = run, npc = npc.id, character = character,
        order = npc.order, revision = npc.revision, channel = "say", language = language,
        text = text, sent = getTimestampMs(), personality = personality,
        context = context, offers = offers }
    -- E08-T02: the NPC's own bounded observations, unverified memories for the prompt (never proof of an action).
    if kind == "npc_talk" then request.observations = Obs.field(npc.id) end
    Talk.pending[#Talk.pending + 1] = request
    if not Talk.save() then table.remove(Talk.pending); return nil end
    return request
end

function Talk.sync()
    local heads, seen = {}, {}
    for _, r in ipairs(Talk.pending) do
        if not seen[r.npc] then heads[#heads + 1], seen[r.npc] = r, true end
    end
    Transport.npc = heads
    return Transport.write()
end

function Talk.acknowledge(req, accepted, applied)
    local acks = Transport.acks
    acks[#acks + 1] = { version = 2, kind = "ack", id = req.id .. "-ack", request = req.id,
        world = req.world, run = req.run, npc = req.npc, order = req.order, revision = req.revision,
        sent = getTimestampMs(), status = accepted and "accepted" or "rejected", applied = applied or {} }
    -- Bounded persistent outbox: restart must not lose the final acknowledgement.
    Talk.data.acks, Talk.dirty = acks, true
end

-- Calls of the last real hour, the list reduced to them.
function Talk.recentCalls(now)
    local times = {}
    for _, t in ipairs(Talk.times) do
        if now - t < 3600000 then times[#times + 1] = t end
    end
    Talk.times = times
    return #times
end

-- Room for one more request of a player's sentence: queue, hourly cap, acknowledgements not settled.
function Talk.room(now)
    return #Talk.pending < Speech.MAX_PENDING and Talk.recentCalls(now) < Speech.MAX_PER_HOUR
        and #Transport.acks < Talk.MAX_ACKS
end

-- Bindings of the groups (E10-T02) ---------------------------------------------------------------------------------

-- A collective intention commits the whole group of the NPC. Binding of the request to the composition it was built
-- on; at the reply the composition is read again and a collective intention is refused when the NPC left the group, is
-- no longer its leader or the living members changed (death, departure, arrival, succession).
function Talk.collectiveBinding(npc)
    local c = P.composition(npc.incarnation)
    if not c then return nil end
    return { ref = c.ref, key = c.key, leader = c.leader == true, leaderName = c.leaderName,
        canLeave = c.canLeave == true } -- E10-T04
end

-- true when a collective intention bound by `binding` may still be applied by this NPC; false and the reason otherwise.
function Talk.collectiveCheck(binding, npc)
    if type(binding) ~= "table" then return false, "collective intention without a group binding" end
    local now = Talk.collectiveBinding(npc)
    if not now or now.ref ~= binding.ref then return false, "NPC no longer in the group" end
    if not now.leader then return false, "NPC no longer the group leader" end
    if now.key ~= binding.key then return false, "group composition changed" end
    return true
end

-- A player's sentence -----------------------------------------------------------------------------------------------

local function chatAllowed(player, text)
    if player:isDead() or player:isAsleep() or player:isAllChatMuted() then return false end
    if isServer() then
        -- ChatUtility.getAllowedChatStreams uses "s" to enable say. Do not call client ChatManager here.
        local streams = string.gsub(getServerOptions():getOption("ChatStreams") or "", '"', "")
        local hasSay = false
        for stream in string.gmatch(streams, "[^,]+") do
            if string.match(stream, "^%s*s%s*$") then hasSay = true end
        end
        if not hasSay then return false end
    end
    -- detectBadWords is an exposed global backed by the same WordsFilter as ChatServer.
    -- Reject all detected words, conservatively, rather than bypass replacement/ban/kick policy.
    return not detectBadWords(text)
end

-- Sentence of a character to the speaker npc (already selected and in range). Returns the request, or nil and the
-- reason shown to the player (Text, Chat, Cooldown, Busy, Bridge).
function Talk.speak(player, character, npc, args)
    local text = args.text
    if type(text) ~= "string" or #text < 1 or #Codec.toUtf8(text) > Speech.MAX_TEXT_BYTES
            or string.find(text, "[%c]") then return nil, "Text" end
    text = oneLine(text)
    if text == "" or args.channel ~= "say" or not chatAllowed(player, text) then return nil, "Chat" end
    local now = getTimestampMs()
    local slow = isServer() and getServerOptions():getInteger("ChatMessageSlowModeTime") * 1000 or 0
    if Talk.lastTalk[character] and now - Talk.lastTalk[character] < math.max(Speech.COOLDOWN_MS, slow) then
        return nil, "Cooldown"
    end
    if not Talk.room(now) then return nil, "Busy" end
    -- E17-T11: real game language of the client (any code of the right form; invalid -> EN), only a hint for the model.
    local language = Speech.languageCode(args.language)
    local host = Talk.host
    -- E04-T10 (Q10): reputation of the speaker as the NPC knows it (level and last public act, RC_Reputation
    -- publicContext); never a score. The model may speak about it, never change it.
    local context = { name = npc.name, background = npc.background, reputation = Rep.publicContext(character),
        agreements = npc.agreements, caller = host.characterName(character) }
    -- E17-T03: public context of the NPC from its engine (group, public story, needs, attitude toward this character).
    context.group = P.context(npc.incarnation, character, language)
    local group = Talk.collectiveBinding(npc)
    local offers, bound, relation = host.talkContext(context, npc, character, player, language, group)
    -- E09-T05: agreement offer of the server (fixed terms), only to the leader of a group and a character whose player
    -- may conclude for its team now (owner or designated negotiator); bound to the team and the agreement revision.
    local negotiation = nil
    if group and group.leader and context.stage == "acquainted" then
        negotiation = Agreements() and Agreements().negotiation(player, group.ref) or nil
        if negotiation then
            context.negotiation = { role = negotiation.role, teamName = negotiation.teamName,
                personal = negotiation.personal, current = negotiation.current, terms = negotiation.terms }
            bound = true
        end
    end
    -- E10-T04: an acquainted character talking to a member who may leave its group now: the model playing the NPC may
    -- decide to leave (intent leave_group), bound to the group and its composition like a collective intention.
    if group and group.canLeave and context.stage == "acquainted" then
        context.leave = { alone = true }
        bound = true
    end
    -- E08-T05: the NPC is talking with another NPC (LK_Conversations): the sentence joins that conversation; the model
    -- gets the partner and the lines this NPC heard, and chooses its reaction. The character's rights stay the same.
    local conversation = Talk.conversations.of(npc.id)
    if conversation then context.conversation = Talk.conversations.talkContext(conversation, npc.id) end
    local req = Talk.enqueue(npc, "npc_talk", character, text, language, context, offers)
    if req and group and bound then
        Talk.collectives[req.id] = { ref = group.ref, key = group.key,
            team = negotiation and negotiation.team or nil, revision = negotiation and negotiation.revision or nil }
    end
    if req and relation then Talk.relations[req.id] = relation end
    if not req or not Talk.sync() then return nil, "Bridge" end
    Talk.lastTalk[character], Talk.times[#Talk.times + 1] = now, now
    if conversation then
        Talk.conversations.intervene(Talk, conversation, req, player, host.characterName(character), text)
    end
    host.talkQueued(req, player, npc, character, text)
    return req
end

-- E10-T03: reactions of the embodied members to a collective decision of their leader, born of a conversation with a
-- character (group mission offered or accepted, agreement concluded). Each member of the same group whose body is
-- loaded here (provider objects), the leader excluded, in id order, up to MEMBER_REACTIONS per decision and within the
-- bridge quotas (MAX_PENDING, MAX_PER_HOUR): one npc_member request carrying the decision fact (English, composed by
-- the server). The model playing the member chooses accept, contest or refuse (memberReply). The request is bound to
-- the group (Talk.reactions[id] = { ref, about }), never sent to the bridge. Fiche docs/annexes/conception/contestation.md.
local NEED_WORDS = { food = "food", medical = "medical supplies", ammo = "ammunition" }

local function decisionFact(d)
    local who = type(d.with) == "string" and oneLine(d.with) or ""
    if who == "" then return nil end
    local need = NEED_WORDS[d.need] or "supplies"
    if d.kind == "offer" then return "The leader asked " .. who .. " to bring " .. need .. " for the group." end
    if d.kind == "accept" then return who .. " agreed to bring " .. need .. " for the group." end
    if d.kind == "agreement" and type(d.agreement) == "string" then
        return "The leader concluded a " .. d.agreement .. " with " .. who .. " and their team."
    end
    return nil
end

function Talk.memberReactions(leader, decision, language)
    local group = Talk.collectiveBinding(leader)
    local about = type(decision) == "table" and decisionFact(decision) or nil
    if not group or not group.leader or not about then return 0 end
    local ids = {}
    for id in pairs(P.objects()) do
        if id ~= leader.incarnation then
            local c = P.composition(id)
            if c and c.ref == group.ref and not c.leader then ids[#ids + 1] = id end
        end
    end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    local now, sent = getTimestampMs(), 0
    for _, id in ipairs(ids) do
        if sent >= Talk.MEMBER_REACTIONS or #Talk.pending >= Speech.MAX_PENDING
                or #Talk.times >= Speech.MAX_PER_HOUR then break end
        local npc = Talk.ensure(id)
        if npc and npc.alive and npc.incarnation == id then
            local context = { name = npc.name, background = npc.background, stage = "member",
                group = P.context(id, nil, language),
                decision = { kind = decision.kind, text = about, leaderName = leader.name } }
            local req = Talk.enqueue(npc, "npc_member", "group", "Your leader decided: " .. about, language, context, {})
            if req then
                Talk.reactions[req.id] = { ref = group.ref, about = about }
                Talk.times[#Talk.times + 1] = now
                sent = sent + 1
            end
        end
    end
    if sent > 0 then
        Talk.sync()
        print("[LK_Talk] collective decision of " .. tostring(leader.id) .. ": " .. sent .. " member reaction(s) asked")
    end
    return sent
end

-- Replies -----------------------------------------------------------------------------------------------------------

-- Connected players who hear this body.
local function hearers(object)
    local out = {}
    for player, character in pairs(Talk.bound()) do
        if character and P.hears(object, player, Speech.HEARING_RANGE) then out[#out + 1] = player end
    end
    return out
end
Talk.hearers = hearers

-- E10-T03: reply of a member to a collective decision (npc_member). intent accept (or none): silent, nothing applied.
-- contest / refuse: the member stays in the group and keeps its memory; the provider writes the fact in the group
-- journal and the member says its line aloud (LK11-T04 proximity speech, heard by the players near its body); the
-- characters who already know this member keep the line in their notebook history. The decision itself is unchanged:
-- a member has nothing to execute in a group mission (the players deliver) nor in an agreement (applied by the
-- engine). Refused before any effect when the member left the group or became its leader.
local MEMBER_INTENTS = { none = true, accept = true, contest = true, refuse = true }

local function memberReply(req, result, npc)
    if not MEMBER_INTENTS[result.intent] then return false, "invalid member intent" end
    if result.offer ~= "" then return false, "offer in a member reply" end
    if #result.text > Talk.MEMBER_REPLY_BYTES then return false, "member text too long (" .. #result.text .. ")" end
    local binding = Talk.reactions[req.id]
    local now = P.composition(npc.incarnation)
    if type(binding) ~= "table" or not now or now.ref ~= binding.ref or now.leader then
        return false, "NPC no longer a member of the group"
    end
    if result.intent ~= "contest" and result.intent ~= "refuse" then
        Talk.acknowledge(req, true, {})
        if not Talk.save() then return false, "state not saved" end
        return true
    end
    if not Talk.objects()[npc.id] then Talk.host.scan() end
    local object = Talk.objects()[npc.id]
    if not object or object:isDead() then return false, "NPC body not loaded or dead" end
    Talk.acknowledge(req, true, {})
    if not Talk.save() then return false, "state not saved" end
    local out, why = P.dissent(npc.incarnation, { choice = result.intent, about = binding.about, name = npc.name,
        text = result.text })
    print("[LK_Talk] member " .. npc.id .. " " .. result.intent .. ": " .. binding.about .. " (logged "
        .. tostring(out and out.logged) .. ", heard by " .. tostring(out and out.heard or 0) .. ", "
        .. tostring(why or "ok") .. ")")
    Talk.remember(npc, req.id, result.text, hearers(object))
    Talk.save()
    return true
end

-- E09-T06: decision of the group leader on an incident of an agreement (LK_Incidents, LK_Agreements): applied once,
-- then announced by the host.
local function incidentReply(req, result, npc)
    local ok, a, inc = Talk.incidents.reply(Talk, req, result, npc)
    if not ok then return false, a end
    Talk.acknowledge(req, true, {})
    if not Talk.save() then return false, "state not saved" end
    Talk.host.incidentDecided(a, inc, npc)
    Talk.host.publish()
    return true
end

-- E08-T03, E08-T04: an initiative or a line of a conversation: said by the module, then acknowledged.
local function spokenReply(module, req, result, npc)
    local ok, why = module.reply(Talk, req, result, npc)
    if not ok then return false, why end
    Talk.acknowledge(req, true, {})
    if not Talk.save() then return false, "state not saved" end
    Talk.host.publish()
    return true
end

-- E09-T05: agreement (intent negotiate, offer = kind of the server terms of the request). Concluded only by the group
-- leader on the same composition and by a player who may still conclude for the same team, on the same revision of the
-- agreement; otherwise only the agreement is ignored (E09-T09). Never in ack.applied (the bridge memory keeps the
-- exchange; the agreement is a server fact, announced once applied).
local function negotiate(req, result, npc, binding, ignored)
    local negotiation = type(req.context) == "table" and req.context.negotiation or nil
    local ok, why = true, nil
    if type(negotiation) ~= "table" or type(negotiation.terms) ~= "table" or negotiation.terms[result.offer] == nil then
        ok, why = false, "agreement not offered"
    end
    if ok then ok, why = Talk.collectiveCheck(binding, npc) end
    local speaker = nil
    if ok then
        for p, character in pairs(Talk.bound()) do if character == req.character then speaker = p end end
        if not speaker then ok, why = false, "negotiator not connected" end
    end
    local a
    if ok and not Agreements() then ok, why = false, "no Living Knox agreements" end
    if ok then
        ok, why, a = Agreements().conclude(speaker, binding.ref, result.offer,
            { team = binding.team, revision = binding.revision }, { character = req.character, npc = npc.id })
    end
    if ok then
        print("[LK_Talk] agreement " .. a.id .. " (" .. a.kind .. ") concluded between " .. a.group .. " and "
            .. a.team .. ", revision " .. tostring(a.revision) .. ": pending application")
        return a -- E10-T03: reactions of the members
    end
    ignored("agreement", why)
    return nil
end

-- E10-T04: individual departure (intent leave_group), offered by context.leave. Same group and same composition as
-- when the request was built (a late reply on an older composition is refused before any effect), then ONE transition
-- by the provider (Provider.leave checks again and applies it); the truces of the old group that covered the NPC become
-- its personal truces (LivingKnox.Agreements.keepTruces). Fiche, memories, contacts: unchanged.
local function leaveGroup(req, npc, binding)
    if type(req.context) ~= "table" or type(req.context.leave) ~= "table" then return false, "leave not offered" end
    local now = Talk.collectiveBinding(npc)
    if type(binding) ~= "table" or not now or now.ref ~= binding.ref then return false, "NPC no longer in the group" end
    if now.key ~= binding.key then return false, "group composition changed" end
    local left, why = P.leave(npc.incarnation, { ref = binding.ref, key = binding.key })
    if not left then return false, why end
    local kept = Agreements() and Agreements().keepTruces(npc.incarnation, binding.ref) or 0
    npc.clan, npc.groupName = tostring(left.ref or ""), oneLine(left.groupName or "")
    print("[LK_Talk] " .. npc.id .. " left group " .. binding.ref .. " for " .. tostring(left.ref) .. ", "
        .. kept .. " truce(s) kept, walk away " .. (left.walk and "issued" or ("failed: " .. tostring(left.walkWhy))))
    return true
end

-- E09-T09 (user decision 2026-10-14): an effect proposed by the model and refused by the server here (collective
-- intention, agreement) is only ignored and logged with its reason; the line of the NPC is still said and kept in the
-- history, like a reply with intent none (same rule as a refused relation change, E09-T08). The checks of the reply
-- itself (fields, NPC revision, text, intent and offer of the request, body loaded) still refuse the whole reply.
local function talkReply(req, result, npc)
    local host = Talk.host
    local object = host.objects()[npc.id]
    if not object or object:isDead() then return false, "NPC body not loaded or dead" end
    local function ignored(effect, why)
        print("[LK_Talk] " .. effect .. " of " .. npc.id .. " toward " .. tostring(req.character) .. " in "
            .. tostring(req.id) .. " ignored, reply kept: " .. tostring(why))
    end
    local binding = Talk.collectives[req.id]
    local agreed = nil
    if result.intent == "negotiate" then agreed = negotiate(req, result, npc, binding, ignored) end
    if result.intent == "leave_group" then
        local left, why = leaveGroup(req, npc, binding)
        if not left then return false, why end
    end
    -- E09-T04: personal relation changed by a real fact this NPC knows (offered in the request, checked again:
    -- relation revision, fact known and never used, direction of its nature, gap within -1..+1). E09-T08: a refused
    -- change is only ignored (logged with its reason): the line of the NPC is still said, nothing else depends on it.
    -- Never in ack.applied (a server fact, shown by the notebook).
    if result.intent == "change_relation" then
        local view, why = host.relationApply(npc, req.character, Talk.relations[req.id], result.dir, result.fact)
        if view then
            print("[LK_Talk] relation of " .. npc.id .. " toward " .. tostring(req.character) .. " " .. result.dir
                .. " (" .. why .. "): " .. view.level .. ", group " .. view.group)
        else
            print("[LK_Talk] relation change of " .. npc.id .. " toward " .. tostring(req.character) .. " in "
                .. tostring(req.id) .. " ignored, reply kept: " .. tostring(why))
        end
    end
    local outcome, why = host.talkActions(req, result, npc, binding, ignored)
    if not outcome then return false, why end
    local audiences = host.heard(req, result, npc, object, outcome)
    Talk.acknowledge(req, true, outcome.applied)
    -- Persist acceptance before rendering a reply/offer; replayed files cannot generate a second effect.
    if not Talk.save() then return false, "state not saved" end
    local speaker = host.characterName(req.character)
    -- E10-T02: the collective decision goes to the group journal (fact only: never the reply text nor reasons), read
    -- back in the context of every member of the group.
    local decided = outcome.decided
    if decided and speaker then
        local ok, reason = P.decide(npc.incarnation, { kind = decided.kind, need = decided.need, with = speaker })
        if not ok then
            print("[LK_Talk] collective decision of " .. tostring(npc.id) .. " not logged: " .. tostring(reason))
        end
    end
    -- E10-T03: the embodied members react to the decision (requests sent by poll, after this reply).
    local reaction = (decided and speaker and { kind = decided.kind, need = decided.need, with = speaker })
        or (agreed and speaker and { kind = "agreement", agreement = agreed.kind, with = speaker }) or nil
    if reaction then
        Talk.reactionQueue[#Talk.reactionQueue + 1] = { leader = npc, decision = reaction, language = req.language }
    end
    host.speech(audiences, req, result, npc, object)
    Talk.conversations.answered(Talk, req, result, npc) -- E08-T05: an answered intervention joins its conversation
    -- E17-T09: a new offer is signalled on screen to the character it is made to, once (the offer is created once).
    if outcome.offer then host.offered(outcome.offer, req.character) end
    addSound(object, math.floor(object:getX()), math.floor(object:getY()), math.floor(object:getZ()),
        Speech.NOISE_RANGE, 10)
    return true
end

-- Applies a bridge reply. Returns true, or false and the reason of the refusal (English, logged once by poll, E17-T07).
local function reply(req, result)
    local npc = Talk.fiche(req.npc)
    if type(result) ~= "table" or result.version ~= 2 or result.kind ~= "npc_reply" then return false, "not an npc_reply" end
    if result.error then return false, "bridge error " .. tostring(result.error) end
    for _, field in ipairs({ "id", "world", "run", "npc", "order", "revision" }) do
        if result[field] ~= req[field] then return false, "field " .. field .. " differs from the request" end
    end
    if not npc or not npc.alive then return false, "NPC gone or dead" end
    if npc.revision ~= req.revision then return false, "NPC revision changed" end
    if type(result.text) ~= "string" or #result.text < 1 then return false, "empty text" end
    if #result.text > Speech.MAX_REPLY_BYTES then return false, "text too long (" .. #result.text .. ")" end
    if string.find(result.text, "[%c<>%[%]*]") then return false, "text with a control character or markup" end
    -- E07-T09: raw JSON of the model is never said to a player (the bridge already refuses it; older bridge here).
    if string.find(result.text, '{%s*"') then return false, "text holds raw JSON" end
    if req.kind == "npc_member" then return memberReply(req, result, npc) end -- E10-T03
    if req.kind == "npc_incident" then return incidentReply(req, result, npc) end -- E09-T06
    local claimed = Talk.host.claim(req)
    if claimed then return claimed(req, result, npc) end -- E08-T06: radio
    local intent = result.intent
    if intent ~= "none" and intent ~= "offer" and intent ~= "accept" and intent ~= "negotiate"
            and not (intent == "leave_group" and req.kind == "npc_talk")
            and not (intent == "change_relation" and req.kind == "npc_talk")
            and not (intent == "report_done" and req.kind == "npc_talk") then
        return false, "invalid intent" -- E10-T04: leave_group, E09-T04: change_relation, E11-T13: report_done; talk only
    end
    if intent ~= "change_relation" and (result.dir ~= nil or result.fact ~= nil) then
        return false, "relation fields without intent"
    end
    if type(result.offer) ~= "string" then return false, "offer is not text" end
    if intent ~= "offer" and intent ~= "negotiate" and result.offer ~= "" then return false, "offer without intent" end
    if req.kind == "npc_enrich" then
        if intent ~= "none" or type(result.background) ~= "string" or #result.background > 1000 then
            return false, "invalid background"
        end
        npc.background, npc.enrichState = result.background, "done"
        Talk.acknowledge(req, true, {})
        if not Talk.save() then return false, "state not saved" end
        return true
    end
    if req.kind == "npc_initiative" then return spokenReply(Talk.initiatives, req, result, npc) end -- E08-T03
    if req.kind == "npc_converse" then return spokenReply(Talk.conversations, req, result, npc) end -- E08-T04
    return talkReply(req, result, npc)
end

-- Reads the answers: one request per speaker at most, in the order of the queue.
function Talk.poll()
    local host = Talk.host
    local responses = Transport.readResponses() or {}
    local kept, changed, used = {}, false, {}
    for _, req in ipairs(Talk.pending) do
        if not used[req.npc] then
            used[req.npc] = true
            local result = responses[req.id]
            if result or getTimestampMs() - req.sent > Speech.REQUEST_TIMEOUT_MS then
                local accepted, reason = false, "no reply after " .. Speech.REQUEST_TIMEOUT_MS .. " ms"
                Talk.initiatives.observe(req, result ~= nil) -- E08-T03: bridge considered stopped after a timeout
                if result then accepted, reason = reply(req, result) end
                if not accepted then
                    -- E17-T07: one line per refused request (the player only sees NoAnswer).
                    print("[LK_Talk] " .. tostring(req.kind) .. " " .. tostring(req.id) .. " refused: " .. tostring(reason))
                    -- E17-T15: newest last, { id, kind, npc, character, reason, at }, at most MAX_REFUSALS: the cause
                    local refusals = Talk.refusals -- (bridge error timeout, http_503..., no reply) for suites/admin
                    refusals[#refusals + 1] = { id = req.id, kind = req.kind, npc = req.npc, character = req.character,
                        reason = tostring(reason), at = getTimestampMs() }
                    while #refusals > Talk.MAX_REFUSALS do table.remove(refusals, 1) end
                    Talk.acknowledge(req, false)
                    local npc = host.fiche(req.npc)
                    if npc and req.kind == "npc_enrich" then
                        npc.enrichState = "deferred"
                        npc.enrichRetryAt = getTimestampMs() + Speech.ENRICH_RETRY_MS
                    end
                    host.reject(req.character, "NoAnswer")
                end
                Talk.collectives[req.id] = nil
                Talk.relations[req.id] = nil -- E09-T04
                Talk.reactions[req.id] = nil -- E10-T03
                Talk.conversations.settle(req.id) -- E08-T05: an unanswered intervention ends its conversation
                changed = true
            else kept[#kept + 1] = req end
        else kept[#kept + 1] = req end
    end
    Talk.pending = kept
    -- E10-T03: member reactions of the decisions applied above, enqueued once the pending list is rebuilt.
    if #Talk.reactionQueue > 0 then
        local queue = Talk.reactionQueue
        Talk.reactionQueue = {}
        for _, r in ipairs(queue) do Talk.memberReactions(r.leader, r.decision, r.language) end
        changed = true
    end
    local acks = {}
    for _, ack in ipairs(Transport.acks) do
        local result = responses[ack.id]
        if not result or result.kind ~= "ack_reply" or result.run ~= ack.run or result.world ~= ack.world then
            acks[#acks + 1] = ack
        else changed = true end
    end
    if #acks ~= #Transport.acks then Talk.dirty = true end
    Transport.acks, Talk.data.acks = acks, acks
    if changed then Talk.save(); Talk.sync(); host.publish() end
end

-- One pass of the authority, once a second: initiatives, turns of the conversations, decisions on incidents.
function Talk.turns(now)
    Talk.initiatives.tick(Talk, now) -- E08-T03: at most one NPC initiative per pass
    Talk.conversations.tick(Talk, now) -- E08-T04: turns of the NPC conversations, at most one opened per pass
    Talk.incidents.tick(Talk, now) -- E09-T06: decision of a leader on an incident of a truce, one per pass
    if Talk.dirty then writeState() end
end

-- Background of the speakers (npc_enrich): one request per pass, out of the player budget.
function Talk.enrich(now)
    if now < enrichAt or #Talk.pending >= 2 or #Transport.acks >= 8 then return end
    local times, enrichTimes = {}, {}
    for _, t in ipairs(Talk.times) do if now - t < 3600000 then times[#times + 1] = t end end
    for _, t in ipairs(Talk.enrichTimes) do if now - t < 3600000 then enrichTimes[#enrichTimes + 1] = t end end
    Talk.times, Talk.enrichTimes = times, enrichTimes
    for _, npc in pairs(Talk.host.fiches()) do
        local attempts = Talk.enrichAttempts[npc.id] or 0
        local ready = npc.enrichState == "needed" or (npc.enrichState == "deferred" and now >= (npc.enrichRetryAt or 0))
        if npc.alive and ready and attempts < Speech.ENRICH_MAX_ATTEMPTS and #times < Speech.MAX_PER_HOUR
                and #enrichTimes < Speech.ENRICH_PER_HOUR then
            local request = Talk.enqueue(npc, "npc_enrich", "system", "Describe your background.",
                Speech.NARRATIVE_LANGUAGE, { name = npc.name, clan = npc.clan,
                    group = P.context(npc.incarnation, nil, Speech.NARRATIVE_LANGUAGE) }, {})
            if request then
                npc.enrichState = "pending"
                Talk.enrichAttempts[npc.id] = attempts + 1
                times[#times + 1], enrichTimes[#enrichTimes + 1] = now, now
                Talk.sync()
            end
            break
        end
    end
    enrichAt = now + 5000
end

if not Talk.subscribed then
    Talk.subscribed = true
    LivingKnox.subscribe("OnInitGlobalModData", "Talk.init", function(newWorld) Talk.init(newWorld) end)
    LivingKnox.subscribe("OnSave", "Talk.save", function() if Talk.dirty then writeState() end end)
end

return Talk
