if isClient() then return end
if RS_CarnetServer then return RS_CarnetServer end
local C = require 'RadioSurvivor/RS_Config'
local Codec = require 'RadioSurvivor/RS_Codec'
local P = require 'RadioSurvivor/RS_NPCProvider'; local WorldStart = require 'RadioSurvivor/RS_WorldStart'
local S = require 'RadioSurvivor/RS_State'; require 'RadioSurvivor/RS_MissionClear' -- E11-T04: template clear
local M = require 'RadioSurvivor/RS_Missions'; require 'RadioSurvivor/RS_MissionScout'; require 'RadioSurvivor/RS_MissionRetrieve'
local Rep = require 'RadioSurvivor/RS_Reputation'
local T = require 'RadioSurvivor/RS_Transport'
local Radio = require 'RadioSurvivor/RadioSurvivor_Const'
local Obs = require 'RadioSurvivor/RS_Observations'
local Triggers = require 'RadioSurvivor/RS_ObservationTriggers' -- E08-T07: observation triggers
local Factions = require 'RadioSurvivor/RS_Factions' -- E09-T03: team ids and negotiation mandates
local Relations = require 'RadioSurvivor/RS_Relations' -- E09-T04: personal relation of an NPC toward a character
local Server = {store = S, bound = {}, selected = {}, objects = {}, quotes = {}, pending = {}, times = {}, enrichTimes = {}, enrichAttempts = {}, lastTalk = {}, collectives = {}, reactions = {}, reactionQueue = {}, relations = {}, refusals = {}, MAX_REFUSALS = 16} -- E09-T04: relation bindings -- E17-T15: last refused requests (see poll) -- E10-T03: reactions, reaction queue
-- Export only on the authority, also used by the real-Lua simulation tests.
RS_CarnetServer = Server
local tickAt, saveAt, checkAt, enrichAt, pruneAt = 0, 0, 0, 0, 0

local function send(player, command, args)
    args = args or {}
    if S.data then args.world, args.run = S.data.world, S.run end
    if isServer() then sendServerCommand(player, C.MODULE, command, args or {})
    elseif RS_CarnetClient then RS_CarnetClient.receive(command, args or {}) end
end

local function reject(player, reason)
    send(player, 'error', {reason = reason})
end

local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    elseif getPlayer() then out[1] = getPlayer() end
    return out
end

local function displayName(player)
    local d = player:getDescriptor()
    return Radio.oneLine(d:getForename() .. ' ' .. d:getSurname())
end

local IDENTITY_KEY = 'RS_CarnetCharacter'

local function ownerOf(player)
    return isServer() and player:getUsername() or 'solo'
end

local function usable(id, owner, slot)
    local record = type(id) == 'string' and S.data.characters[id] or nil
    return record and record.owner == owner and record.slot == slot and not record.retired
end

-- In MP only the server IsoPlayer is saved: a value written by the client into its own modData
-- is lost at reconnection. The server writes the identity into its copy; the client claim is
-- only a fallback for states created before this rule, and must match the authenticated owner.
local function identity(player, claimed)
    if Server.bound[player] then
        claimed = Server.bound[player]
        send(player, 'identity', {character = claimed, world = S.data.world, run = S.run})
        return claimed
    end
    local owner, slot = ownerOf(player), player:getPlayerNum()
    local md = player:getModData()
    local stored = md[IDENTITY_KEY]
    if usable(stored, owner, slot) then claimed = stored
    elseif not usable(claimed, owner, slot) then
        claimed = S.uid('character')
        S.data.characters[claimed] = {id = claimed, owner = owner, slot = slot, name = displayName(player),
            contacts = {}, knownMissions = {}}
        if not S.save() then return nil end
    end
    md[IDENTITY_KEY] = claimed
    Server.bound[player] = claimed
    send(player, 'identity', {character = claimed, world = S.data.world, run = S.run})
    return claimed
end

-- Existing fiche of the provider NPC with this id, without creating one.
function Server.find(id)
    local record = S.data and P.npc(id)
    local existing = record and S.data.bindings[record.signature]
    return existing and S.data.npcs[existing] or nil
end

-- Fiche of an NPC a player selects. Never called for every spawn: the private state would grow
-- with the NPC population and each fiche would cost an LLM enrichment.
function Server.ensure(id)
    local record = S.data and P.npc(id)
    if not record then return nil end
    local signature = record.signature
    local npc = Server.find(id)
    if not npc then
        local key = S.uid('npc')
        npc = {id = key, incarnation = id, signature = signature, name = Radio.oneLine(record.name or 'Survivor'),
            revision = 1, order = 0, alive = true, clan = tostring(record.group or ''),
            personality = P.personality(signature),
            agreements = {}, background = '', enrichState = 'idle', seenAt = getTimestampMs()}
        if type(record.traits) == 'table' then
            for _, trait in ipairs({'smoker', 'alcoholic', 'compulsiveCleaner', 'comicsCollector', 'fromPoland'}) do
                if type(record.traits[trait]) == 'boolean' then npc.personality[trait] = record.traits[trait] end
            end
        end
        S.data.npcs[key], S.data.bindings[signature] = npc, key
    end
    -- Group changes do not erase agreements, memories or identity.
    npc.clan = tostring(record.group or '')
    npc.groupName = Radio.oneLine(record.groupName or '') -- E17-T06: readable name for the notebook ('' none)
    return npc
end

local function scan()
    if not P.available() then Server.objects = {}; return end
    local now = getTimestampMs()
    local objects = {}
    for id, object in pairs(P.objects()) do
        local npc = Server.find(id)
        if npc and npc.alive and npc.incarnation == id then
            objects[npc.id] = object
            -- Coarse timestamp: avoids marking the state dirty on every scan.
            if now - (npc.seenAt or 0) > 60000 then npc.seenAt, S.dirty = now, true end
        end
    end
    Server.objects = objects
end

-- The provider recreated an NPC under a new id ('reincarnated' event of RS_NPCProvider): keep the
-- canonical fiche (memories, agreements, missions) on the new incarnation. Nothing else migrates.
function Server.reincarnated(oldSignature, newId, newSignature)
    if not S.data or type(oldSignature) ~= 'string' or type(newSignature) ~= 'string' then return end
    local existing = S.data.bindings[oldSignature]
    local old = existing and S.data.npcs[existing]
    if not old or not old.alive then return end
    local temporary = S.data.bindings[newSignature]
    if temporary and temporary ~= old.id then S.data.npcs[temporary] = nil end
    S.data.bindings[newSignature] = old.id
    old.incarnation, old.signature = newId, newSignature
    S.dirty = true
end

local function contact(character, npc)
    local record = S.data.characters[character]
    if not record.contacts[npc.id] then
        local data = P.npc(npc.incarnation)
        local trust = data and (data.hostile == true and 'Hostile' or data.hostile == false and 'Cautious') or 'Unassessed'
        record.contacts[npc.id] = {history = {}, note = '', trust = trust, trend = 'Stable', stage = 'stranger', exchanges = 0}
        if npc.enrichState == 'idle' then npc.enrichState = 'needed' end
    end
    return record.contacts[npc.id]
end

-- E17-T08: acquaintance of a character with an NPC, kept on its contact (stage, exchanges, firstHour). A stranger
-- becomes acquainted, for good, when it talks again at least C.ACQUAINT_HOURS game hours after the first answered
-- exchange, after C.ACQUAINT_EXCHANGES answered exchanges, or when it took part in a mission of this NPC (contacts saved
-- before this rule, missions already accepted). Contacts without the fields are strangers with no exchange.
local function acquaintance(character, npc, known)
    if known.stage ~= 'acquainted' then
        local met = (known.exchanges or 0) >= C.ACQUAINT_EXCHANGES
            or (type(known.firstHour) == 'number' and getGameTime():getWorldAgeHours() - known.firstHour >= C.ACQUAINT_HOURS)
        if not met then
            for _, m in pairs(S.data.missions) do
                if m.npc == npc.id and m.participants[character] then met = true end
            end
        end
        known.stage = met and 'acquainted' or 'stranger'
    end
    return known.stage
end

-- E17-T09: offer of this NPC still open for this character (state offer, invited, not engaged): the next sentence
-- of the character may accept it. nil otherwise.
local function openOffer(npc, character)
    local m = npc.mission and S.data.missions[npc.mission]
    if not m or m.npc ~= npc.id or m.state ~= 'offer' or m.transaction or not m.invited[character]
            or m.participants[character] then return nil end
    return m
end

-- Readable group name of an NPC (E17-T06): live provider record, else the name kept on the fiche; never the raw
-- group id ("grp-<n>"), '' when the NPC has no group or the provider gives no name.
local function groupName(npc)
    local record = P.npc(npc.incarnation)
    if record then return Radio.oneLine(record.groupName or '') end
    return npc.groupName or ''
end

-- E00-T04: a pushed snapshot (publish) is sent only when its content changed for this player since the last one sent
-- to it; an answer to the player's own request (hello, snapshot and every command of this player) is always sent.
-- Comparison on the encoded snapshot without its timestamp `at`. Several modules publish after a change that is not
-- this player's (a line said by an NPC nobody of this character knows, a reply polled then published twice...): an
-- idle player no longer receives the same snapshot again (rs.carnet.load, E00-T04).
Server.lastSnapshot = {} -- player -> {key, body}; entries of absent players dropped by tick (no weak table in Kahlua)

local function projection(player, pushed)
    local character = Server.bound[player]
    local record = character and S.data.characters[character]
    if not record then return end
    local contacts, missions, inviteTargets = {}, {}, {}
    local team = Factions.projection(player) -- E09-T03: own team and mandates (Team tab)
    for id, known in pairs(record.contacts) do
        local npc = S.data.npcs[id]
        if npc then
            contacts[#contacts + 1] = {id = id, name = npc.name, alive = npc.alive,
                groupName = groupName(npc), personality = npc.personality, background = npc.background,
                revision = npc.revision, near = P.near(player, Server.objects[id], C.SELECT_RANGE),
                history = known.history, note = known.note,
                -- E09-T07: relation panel of THIS character only (identifiers and game days, translated by the client;
                -- agreements of the NPC's group with this character's team). Replaces trust/trend keys of 0.2.
                relation = Relations.panel(npc, character, team)}
        end
    end
    for id, m in pairs(S.data.missions) do
        if m.participants[character] or m.invited[character] or record.knownMissions[id] then
            local p = M.projection(m, character)
            -- E11-T08: a radio voice requester has no fiche nor body (name of its sheet, never near).
            local requester = S.data.npcs[m.npc]
            p.requester = requester and requester.name or m.requesterName or ''
            p.near = P.near(player, Server.objects[m.npc], C.DELIVERY_RANGE)
            missions[#missions + 1] = p
        end
    end
    for _, other in ipairs(players()) do
        local id = Server.bound[other]
        if id and id ~= character and P.near(player, other, C.SELECT_RANGE) then
            inviteTargets[#inviteTargets + 1] = {id = id, name = S.data.characters[id].name}
        end
    end
    table.sort(contacts, function(a, b) return a.name < b.name end)
    table.sort(missions, function(a, b) return a.id < b.id end)
    local snapshot = {world = S.data.world, run = S.run, contacts = contacts, missions = missions, selected = Server.selected[character] or '',
        -- E04-T12: reputation of this character only (level, trend, reasons), never a number.
        reputation = Rep.projection(character, S.data), inviteTargets = inviteTargets,
        team = team,
        npcProvider = P.available() == true, storage = not S.blocked}
    local ok, body = pcall(Codec.encodeBytes, snapshot)
    body = ok and body or nil
    local key = character .. '|' .. tostring(S.data.world) .. '|' .. tostring(S.run)
    local last = Server.lastSnapshot[player]
    if pushed and body ~= nil and last ~= nil and last.key == key and last.body == body then return end
    Server.lastSnapshot[player] = {key = key, body = body}
    snapshot.at = getTimestampMs()
    send(player, 'snapshot', snapshot)
end

local function publish()
    for _, player in ipairs(players()) do projection(player, true) end
end

-- Also called by RS_MissionVoice (E11-T08) when a radio voice starts or closes a mission.
Server.publish = publish

local function activeNpc(player, character, id, range)
    local npc = type(id) == 'string' and S.data.npcs[id]
    local object = npc and Server.objects[id]
    if not npc or not npc.alive or not P.near(player, object, range) then return nil end
    if not S.data.characters[character].contacts[id] then return nil end
    return npc, object
end

local function chatAllowed(player, text)
    if player:isDead() or player:isAsleep() or player:isAllChatMuted() then return false end
    if isServer() then
        -- ChatUtility.getAllowedChatStreams uses "s" to enable say. Do not call client ChatManager here.
        local streams = (getServerOptions():getOption('ChatStreams') or ''):gsub('"', '')
        local hasSay = false
        for stream in streams:gmatch('[^,]+') do if stream:match('^%s*s%s*$') then hasSay = true end end
        if not hasSay then return false end
    end
    -- detectBadWords is an exposed global backed by the same WordsFilter as ChatServer.
    -- Reject all detected words, conservatively, rather than bypass replacement/ban/kick policy.
    return not detectBadWords(text)
end

local function enqueue(npc, kind, character, text, language, context, offers)
    npc.order = npc.order + 1
    -- E10-T03: loyalty derived now by the provider (group morale, seniority), never stored on the fiche.
    local personality, loyalty = npc.personality, P.loyalty(npc.incarnation)
    if loyalty and type(personality) == 'table' then
        personality = {}
        for k, v in pairs(npc.personality) do personality[k] = v end
        personality.loyalty = loyalty
    end
    local request = {version = 2, kind = kind, id = S.run .. '-' .. npc.order .. '-' .. npc.id,
        world = S.data.world, run = S.run, npc = npc.id, character = character,
        order = npc.order, revision = npc.revision, channel = 'say', language = language,
        text = text, sent = getTimestampMs(), personality = personality,
        context = context, offers = offers}
    -- E08-T02: the NPC's own bounded observations, unverified memories for the prompt (never proof of an action).
    if kind == 'npc_talk' then request.observations = Obs.field(npc.id) end
    Server.pending[#Server.pending + 1] = request
    if not S.save() then table.remove(Server.pending); return nil end
    return request
end

local function syncTransport()
    local heads, seen = {}, {}
    for _, r in ipairs(Server.pending) do
        if not seen[r.npc] then heads[#heads + 1], seen[r.npc] = r, true end
    end
    T.npc = heads
    return T.write()
end

-- Server-configured mission allocations (RS_Missions templates), not fabricated by the model or the client.
-- character: notebook character the offers are computed for (engine supplies depend on its attitude, E17-T03).
local function offerCatalog(npc, record, character)
    return M.offers(npc, record, Server.objects[npc.id], character) -- body: where a scout place is drawn around
end

Server.offerCatalogFor = offerCatalog

-- E10-T02: leader and collective intentions. A collective intention commits the whole group of the NPC: today a group
-- mission (offer of kind 'supply', real need of the group, E17-T03 / LK12-T03), and its acceptance by speaking. Only
-- the leader of the registry (Provider.composition, LK_Groups leader and succession) is offered one; another member may
-- talk about the group's needs and refers the character to the leader (context.collective). The request is bound to
-- the group composition it was built on (Server.collectives[request id] = { ref, key }); at the reply the server reads
-- the composition again and refuses a collective intention when the NPC left the group, is no longer its leader or the
-- living members changed (death, departure, arrival, succession). E09-T05 (agreements) calls the same two functions.
-- Server.collectives (declared with Server): those bindings, removed by poll once the request is handled.
local function isCollective(terms) return type(terms) == 'table' and terms.kind == 'supply' end
local function collectiveMission(m) return type(m) == 'table' and type(m.supply) == 'table' end

-- Binding of a collective intention of this NPC (its group now), or nil when the NPC has no group leader.
function Server.collectiveBinding(npc)
    local c = P.composition(npc.incarnation)
    if not c then return nil end
    return {ref = c.ref, key = c.key, leader = c.leader == true, leaderName = c.leaderName,
        canLeave = c.canLeave == true} -- E10-T04
end

-- true when a collective intention bound by `binding` may still be applied by this NPC; false and the reason otherwise.
function Server.collectiveCheck(binding, npc)
    if type(binding) ~= 'table' then return false, 'collective intention without a group binding' end
    local now = Server.collectiveBinding(npc)
    if not now or now.ref ~= binding.ref then return false, 'NPC no longer in the group' end
    if not now.leader then return false, 'NPC no longer the group leader' end
    if now.key ~= binding.key then return false, 'group composition changed' end
    return true
end

local function talk(player, character, args)
    local id = Server.selected[character]
    local npc, object = activeNpc(player, character, id, C.SELECT_RANGE)
    if not npc then
        -- E17-T06: the cleared target reaches the notebook at once (its Say line greys).
        Server.selected[character] = nil; projection(player)
        return reject(player, 'Range')
    end
    local text = args.text
    if type(text) ~= 'string' or #text < 1 or #Codec.toUtf8(text) > C.MAX_TEXT_BYTES or text:find('[%c]') then return reject(player, 'Text') end
    text = Radio.oneLine(text)
    if text == '' or args.channel ~= 'say' or not chatAllowed(player, text) then return reject(player, 'Chat') end
    local now = getTimestampMs()
    local slow = isServer() and getServerOptions():getInteger('ChatMessageSlowModeTime') * 1000 or 0
    if Server.lastTalk[character] and now - Server.lastTalk[character] < math.max(C.COOLDOWN_MS, slow) then return reject(player, 'Cooldown') end
    local times = {}
    for _, t in ipairs(Server.times) do if now - t < 3600000 then times[#times + 1] = t end end
    Server.times = times
    if #Server.pending >= C.MAX_PENDING or #times >= C.MAX_PER_HOUR or #T.acks >= 16 then return reject(player, 'Busy') end
    -- E17-T11: real game language of the client (any code of the right form; invalid -> EN), only a hint for the model.
    local language = C.languageCode(args.language)
    local known = contact(character, npc)
    -- E09-T04: personal relation of the NPC toward this character (labels only) and the real facts it may cite to
    -- change it (short ids; the keys stay on the server, Server.relations[request id]). Replaces the former trust.
    local relation, relationBinding = Relations.offer(npc, character)
    -- E04-T10 (Q10): reputation of the speaker as the NPC knows it (level and last public act, RS_Reputation
    -- publicContext); never a score. The model may speak about it, never change it.
    local context = {name = npc.name, background = npc.background, reputation = Rep.publicContext(character, S.data),
        agreements = npc.agreements, relation = relation, caller = S.data.characters[character].name}
    local open = npc.mission and S.data.missions[npc.mission]
    if open then context.mission = M.context(open) end
    -- E11-T13: the objective of this NPC's mission is met (server fact) and the speaker takes part in it: this sentence
    -- may be the report. The model alone judges whether it is one (intent report_done, any language, no word list);
    -- the reply is checked again by Server.spokenReport.
    if open and M.reportReady(open) and open.participants[character] then
        context.reportable = {mission = open.id, revision = open.revision}
    end
    -- E17-T03: public context of the NPC from its engine (group, public story, needs, attitude toward this character).
    context.group = P.context(npc.incarnation, character, language)
    -- E17-T08: a stranger never learns the group nor its home (name, story, leader, needs withheld from the prompt)
    -- and gets no offer. E17-T10: an acquainted NPC receives its offer catalog with every sentence; the model alone
    -- judges whether the player asks for help or work (no word list: any language).
    context.stage = acquaintance(character, npc, known)
    local g = context.group
    if g and context.stage == 'stranger' then context.group = {member = g.member, role = g.role, attitude = g.attitude} end
    -- E17-T09: an offer of this NPC open for this character may be accepted by this sentence (checked again by reply).
    local offered = openOffer(npc, character)
    local offers = {}
    if context.stage == 'acquainted' then
        offers = offerCatalog(npc, P.npc(npc.incarnation), character)
    end
    -- E10-T02: a member that is not the leader gets no collective intention (no group mission, no acceptance of one);
    -- an acquainted character learns from context.collective who decides for the group.
    local group, bound = Server.collectiveBinding(npc), false
    if group and not group.leader then
        local kept = {}
        for key, terms in pairs(offers) do
            if not isCollective(terms) then kept[key] = terms end
        end
        offers = kept
        if collectiveMission(offered) then offered = nil end
    end
    if offered then
        context.acceptable = {mission = offered.id, revision = offered.revision}
        bound = collectiveMission(offered)
    end
    for _, terms in pairs(offers) do
        if isCollective(terms) then bound = true end
    end
    if group and context.stage == 'acquainted' then
        context.collective = group.leader and {speaker = 'leader'} or {speaker = 'member', leaderName = group.leaderName}
    end
    -- E09-T05: agreement offer of the server (fixed terms), only to the leader of a group and a character whose player
    -- may conclude for its team now (owner or designated negotiator); bound to the team and the agreement revision.
    local negotiation = nil
    if group and group.leader and context.stage == 'acquainted' then
        negotiation = Factions.negotiation(player, group.ref)
        if negotiation then
            context.negotiation = {role = negotiation.role, teamName = negotiation.teamName,
                personal = negotiation.personal, current = negotiation.current, terms = negotiation.terms}
            bound = true
        end
    end
    -- E10-T04: an acquainted character talking to a member who may leave its group now: the model playing the NPC may
    -- decide to leave (intent leave_group), bound to the group and its composition like a collective intention.
    if group and group.canLeave and context.stage == 'acquainted' then
        context.leave = {alone = true}
        bound = true
    end
    -- E08-T05: the NPC is talking with another NPC (RS_Conversations): the sentence joins that conversation; the model
    -- gets the partner and the lines this NPC heard, and chooses its reaction. The character's rights stay the same.
    local conversation = Server.conversations.of(npc.id)
    if conversation then context.conversation = Server.conversations.talkContext(conversation, npc.id) end
    local req = enqueue(npc, 'npc_talk', character, text, language, context, offers)
    if req and group and bound then
        Server.collectives[req.id] = {ref = group.ref, key = group.key,
            team = negotiation and negotiation.team or nil, revision = negotiation and negotiation.revision or nil}
    end
    if req and relationBinding then Server.relations[req.id] = relationBinding end
    if not req or not syncTransport() then return reject(player, 'Bridge') end
    Server.lastTalk[character], Server.times[#Server.times + 1] = now, now
    if conversation then
        Server.conversations.intervene(Server, conversation, req, player, S.data.characters[character].name, text)
    end
    -- The player's canonical speech is already sent by vanilla. Record only for admitted nearby listeners.
    for _, listener in ipairs(players()) do
        local cid = Server.bound[listener]
        if cid and P.hears(player, listener, C.HEARING_RANGE) then
            local k = contact(cid, npc)
            k.history[#k.history + 1] = {id = req.id .. '-player', author = S.data.characters[character].name, text = text}
            while #k.history > C.MAX_HISTORY do table.remove(k.history, 1) end
        end
    end
    S.save()
    send(player, 'queued', {id = req.id})
end

local function acknowledge(req, accepted, applied)
    T.acks[#T.acks + 1] = {version = 2, kind = 'ack', id = req.id .. '-ack', request = req.id,
        world = req.world, run = req.run, npc = req.npc, order = req.order, revision = req.revision,
        sent = getTimestampMs(), status = accepted and 'accepted' or 'rejected', applied = applied or {}}
    -- Bounded persistent outbox: restart must not lose the final acknowledgement.
    S.data.acks = T.acks
end

-- E17-T09: acceptance spoken to the NPC. The talk request carried context.acceptable (an offer of this NPC open for
-- the speaking character, with its revision). E17-T10: accepted only when the model returned intent accept (the model
-- judges the player's intent in any language; no word list), and only if the same mission is still an open offer of
-- this NPC for this character at the same revision. Same path as the notebook button (M.accept), once: the state
-- becomes active, so a replay or a second yes finds no open offer. Returns the mission.
local function spokenAcceptance(req, result, npc)
    local context = type(req.context) == 'table' and req.context or {}
    local a = context.acceptable
    if type(a) ~= 'table' or result.intent ~= 'accept' then return nil end
    local record = S.data.characters[req.character]
    local m = type(a.mission) == 'string' and S.data.missions[a.mission]
    if not record or record.retired or not m or m.revision ~= a.revision or openOffer(npc, req.character) ~= m then return nil end
    if not M.accept(S.data, m, req.character, record.name) then return nil end
    record.knownMissions[m.id] = true
    return m
end

-- E10-T03: reactions of the embodied members to a collective decision of their leader, born of a conversation with a
-- character (group mission offered or accepted, agreement concluded). Each member of the same group whose body is
-- loaded here (provider objects), the leader excluded, in id order, up to MEMBER_REACTIONS per decision and within the
-- bridge quotas (MAX_PENDING, MAX_PER_HOUR): one npc_member request carrying the decision fact (English, composed by
-- the server). The model playing the member chooses accept, contest or refuse (memberReply). The request is bound to
-- the group (Server.reactions[id] = { ref, about }), never sent to the bridge. Fiche docs/annexes/conception/contestation.md.
Server.MEMBER_REACTIONS = 2
Server.MEMBER_REPLY_BYTES = 200 -- LivingKnox.Speech.MAX_TEXT: the line is spoken by the engine's proximity speech
local NEED_WORDS = {food = 'food', medical = 'medical supplies', ammo = 'ammunition'}

local function decisionFact(d)
    local who = type(d.with) == 'string' and Radio.oneLine(d.with) or ''
    if who == '' then return nil end
    local need = NEED_WORDS[d.need] or 'supplies'
    if d.kind == 'offer' then return 'The leader asked ' .. who .. ' to bring ' .. need .. ' for the group.' end
    if d.kind == 'accept' then return who .. ' agreed to bring ' .. need .. ' for the group.' end
    if d.kind == 'agreement' and type(d.agreement) == 'string' then
        return 'The leader concluded a ' .. d.agreement .. ' with ' .. who .. ' and their team.'
    end
    return nil
end

function Server.memberReactions(leader, decision, language)
    local group = Server.collectiveBinding(leader)
    local about = type(decision) == 'table' and decisionFact(decision) or nil
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
        if sent >= Server.MEMBER_REACTIONS or #Server.pending >= C.MAX_PENDING or #Server.times >= C.MAX_PER_HOUR then break end
        local npc = Server.ensure(id)
        if npc and npc.alive and npc.incarnation == id then
            local context = {name = npc.name, background = npc.background, stage = 'member',
                group = P.context(id, nil, language),
                decision = {kind = decision.kind, text = about, leaderName = leader.name}}
            local req = enqueue(npc, 'npc_member', 'group', 'Your leader decided: ' .. about, language, context, {})
            if req then
                Server.reactions[req.id] = {ref = group.ref, about = about}
                Server.times[#Server.times + 1] = now
                sent = sent + 1
            end
        end
    end
    if sent > 0 then
        syncTransport()
        print('[RS_Carnet] collective decision of ' .. tostring(leader.id) .. ': ' .. sent .. ' member reaction(s) asked')
    end
    return sent
end

-- E10-T03: reply of a member to a collective decision (npc_member). intent accept (or none): silent, nothing applied.
-- contest / refuse: the member stays in the group and keeps its memory; the provider writes the fact in the group
-- journal and the member says its line aloud (LK11-T04 proximity speech, heard by the players near its body); the
-- characters who already know this member keep the line in their notebook history. The decision itself is unchanged:
-- a member has nothing to execute in a group mission (the players deliver) nor in an agreement (applied by the
-- engine). Refused before any effect when the member left the group or became its leader.
local MEMBER_INTENTS = {none = true, accept = true, contest = true, refuse = true}
-- E11-T13: report spoken to the requester. The talk request carried context.reportable (the mission of this NPC whose
-- objective was met, the speaker a participant). Applied only when the model returned intent report_done and, at the
-- reply, the same mission is still this NPC's open mission, its objective still met and the speaker still one of its
-- participants (RS_Missions.spoken checks again and runs the common write-ahead report). The revision may have moved
-- since (another participant joined): the facts are checked, not the revision. Returns the mission once succeeded.
function Server.spokenReport(req, result, npc)
    local r = type(req.context) == 'table' and req.context.reportable
    if type(r) ~= 'table' or result.intent ~= 'report_done' then return nil, 'no report' end
    local m = type(r.mission) == 'string' and S.data.missions[r.mission]
    if not m or npc.mission ~= m.id or m.npc ~= npc.id then return nil, 'mission no longer open with this NPC' end
    if not M.reportReady(m) then return nil, 'objective no longer met' end
    if not m.participants[req.character] then return nil, 'speaker not a participant' end
    local speaker = nil
    for p, cid in pairs(Server.bound) do if cid == req.character then speaker = p end end
    local ok, why = M.spoken(S, m, speaker, req.character)
    if not ok or m.state ~= 'success' then return nil, 'report refused: ' .. tostring(why) end
    return m
end

local function memberReply(req, result, npc)
    if not MEMBER_INTENTS[result.intent] then return false, 'invalid member intent' end
    if result.offer ~= '' then return false, 'offer in a member reply' end
    if #result.text > Server.MEMBER_REPLY_BYTES then return false, 'member text too long (' .. #result.text .. ')' end
    local binding = Server.reactions[req.id]
    local now = P.composition(npc.incarnation)
    if type(binding) ~= 'table' or not now or now.ref ~= binding.ref or now.leader then
        return false, 'NPC no longer a member of the group'
    end
    if result.intent ~= 'contest' and result.intent ~= 'refuse' then
        acknowledge(req, true, {})
        if not S.save() then return false, 'state not saved' end
        return true
    end
    if not Server.objects[npc.id] then scan() end
    local object = Server.objects[npc.id]
    if not object or object:isDead() then return false, 'NPC body not loaded or dead' end
    acknowledge(req, true, {})
    if not S.save() then return false, 'state not saved' end
    local out, why = P.dissent(npc.incarnation, {choice = result.intent, about = binding.about, name = npc.name,
        text = result.text})
    print('[RS_Carnet] member ' .. npc.id .. ' ' .. result.intent .. ': ' .. binding.about .. ' (logged '
        .. tostring(out and out.logged) .. ', heard by ' .. tostring(out and out.heard or 0) .. ', '
        .. tostring(why or 'ok') .. ')')
    for _, listener in ipairs(players()) do
        local cid = Server.bound[listener]
        local k = cid and S.data.characters[cid].contacts[npc.id]
        if k and P.hears(object, listener, C.HEARING_RANGE) then
            k.history[#k.history + 1] = {id = req.id, author = npc.name, text = result.text}
            while #k.history > C.MAX_HISTORY do table.remove(k.history, 1) end
        end
    end
    S.save()
    return true
end

-- Applies a bridge reply. Returns true, or false and the reason of the refusal (English, logged once by poll, E17-T07).
local function reply(req, result)
    local npc = S.data.npcs[req.npc]
    if type(result) ~= 'table' or result.version ~= 2 or result.kind ~= 'npc_reply' then return false, 'not an npc_reply' end
    if result.error then return false, 'bridge error ' .. tostring(result.error) end
    for _, field in ipairs({'id', 'world', 'run', 'npc', 'order', 'revision'}) do
        if result[field] ~= req[field] then return false, 'field ' .. field .. ' differs from the request' end
    end
    if not npc or not npc.alive then return false, 'NPC gone or dead' end
    if npc.revision ~= req.revision then return false, 'NPC revision changed' end
    if type(result.text) ~= 'string' or #result.text < 1 then return false, 'empty text' end
    if #result.text > C.MAX_REPLY_BYTES then return false, 'text too long (' .. #result.text .. ')' end
    if result.text:find('[%c<>%[%]*]') then return false, 'text with a control character or markup' end
    -- E07-T09: raw JSON of the model is never said to a player (the bridge already refuses it; older bridge here).
    if result.text:find('{%s*"') then return false, 'text holds raw JSON' end
    if req.kind == 'npc_member' then return memberReply(req, result, npc) end -- E10-T03
    if req.kind == 'npc_incident' then return Server.incidentReply(req, result, npc) end -- E09-T06
    if Server.groupRadio.owns(req.id) then return Server.groupRadio.reply(Server, req, result, npc) end -- E08-T06: radio
    if result.intent ~= 'none' and result.intent ~= 'offer' and result.intent ~= 'accept'
            and result.intent ~= 'negotiate' and not (result.intent == 'leave_group' and req.kind == 'npc_talk')
            and not (result.intent == 'change_relation' and req.kind == 'npc_talk')
            and not (result.intent == 'report_done' and req.kind == 'npc_talk') then
        return false, 'invalid intent' -- E10-T04: leave_group, E09-T04: change_relation, E11-T13: report_done; talk only
    end
    if result.intent ~= 'change_relation' and (result.dir ~= nil or result.fact ~= nil) then
        return false, 'relation fields without intent'
    end
    if type(result.offer) ~= 'string' then return false, 'offer is not text' end
    if result.intent ~= 'offer' and result.intent ~= 'negotiate' and result.offer ~= '' then
        return false, 'offer without intent'
    end
    local applied = {}
    if req.kind == 'npc_enrich' then
        if result.intent ~= 'none' or type(result.background) ~= 'string' or #result.background > 1000 then return false, 'invalid background' end
        npc.background, npc.enrichState = result.background, 'done'
    elseif req.kind == 'npc_initiative' then return Server.initiativeReply(req, result, npc) -- E08-T03
    elseif req.kind == 'npc_converse' then return Server.conversationReply(req, result, npc) -- E08-T04
    else
        local object = Server.objects[npc.id]
        if not object or object:isDead() then return false, 'NPC body not loaded or dead' end
        -- E09-T09 (user decision 2026-10-14): an effect proposed by the model and refused by the server here (collective
        -- intention, agreement) is only ignored and logged with its reason; the line of the NPC is still said and kept
        -- in the history, like a reply with intent none (same rule as a refused relation change, E09-T08). The checks
        -- of the reply itself (fields, NPC revision, text, intent and offer of the request, body loaded) still refuse
        -- the whole reply.
        local function ignored(effect, why)
            print('[RS_Carnet] ' .. effect .. ' of ' .. npc.id .. ' toward ' .. tostring(req.character) .. ' in '
                .. tostring(req.id) .. ' ignored, reply kept: ' .. tostring(why))
        end
        -- E10-T02: a collective intention (group mission, its acceptance) is applied only by the group leader, on the
        -- composition the request was built on; otherwise only the intention is ignored (E09-T09).
        local binding = Server.collectives[req.id]
        local acceptable = type(req.context) == 'table' and req.context.acceptable
        local acceptance = result.intent == 'accept'
        if acceptance and type(acceptable) == 'table' and type(acceptable.mission) == 'string'
                and collectiveMission(S.data.missions[acceptable.mission]) then
            local ok, why = Server.collectiveCheck(binding, npc)
            if not ok then acceptance = false; ignored('collective acceptance', why) end
        end
        -- E09-T05: agreement (intent negotiate, offer = kind of the server terms of the request). Concluded only by the
        -- group leader on the same composition and by a player who may still conclude for the same team, on the same
        -- revision of the agreement; otherwise only the agreement is ignored (E09-T09). Never in ack.applied (the
        -- bridge memory keeps the exchange; the agreement is a server fact, announced once applied).
        local agreed
        if result.intent == 'negotiate' then
            local negotiation = type(req.context) == 'table' and req.context.negotiation or nil
            local ok, why = true, nil
            if type(negotiation) ~= 'table' or type(negotiation.terms) ~= 'table' or negotiation.terms[result.offer] == nil then
                ok, why = false, 'agreement not offered'
            end
            if ok then ok, why = Server.collectiveCheck(binding, npc) end
            local speaker = nil
            if ok then
                for _, p in ipairs(players()) do if Server.bound[p] == req.character then speaker = p end end
                if not speaker then ok, why = false, 'negotiator not connected' end
            end
            local a
            if ok then
                ok, why, a = Factions.conclude(speaker, binding.ref, result.offer,
                    {team = binding.team, revision = binding.revision}, {character = req.character, npc = npc.id})
            end
            if ok then
                print('[RS_Carnet] agreement ' .. a.id .. ' (' .. a.kind .. ') concluded between ' .. a.group .. ' and '
                    .. a.team .. ', revision ' .. tostring(a.revision) .. ': pending application')
                agreed = a -- E10-T03: reactions of the members
            else
                ignored('agreement', why)
            end
        end
        -- E10-T04: individual departure (intent leave_group), offered by context.leave. Same group and same composition
        -- as when the request was built (a late reply on an older composition is refused before any effect), then ONE
        -- transition by the provider (Provider.leave checks again and applies it); the truces of the old group that
        -- covered the NPC become its personal truces (RS_Factions.keepTruces). Fiche, memories, contacts: unchanged.
        if result.intent == 'leave_group' then
            if type(req.context) ~= 'table' or type(req.context.leave) ~= 'table' then return false, 'leave not offered' end
            local now = Server.collectiveBinding(npc)
            if type(binding) ~= 'table' or not now or now.ref ~= binding.ref then return false, 'NPC no longer in the group' end
            if now.key ~= binding.key then return false, 'group composition changed' end
            local left, why = P.leave(npc.incarnation, {ref = binding.ref, key = binding.key})
            if not left then return false, why end
            local kept = Factions.keepTruces(npc.incarnation, binding.ref)
            npc.clan, npc.groupName = tostring(left.ref or ''), Radio.oneLine(left.groupName or '')
            print('[RS_Carnet] ' .. npc.id .. ' left group ' .. binding.ref .. ' for ' .. tostring(left.ref) .. ', '
                .. kept .. ' truce(s) kept, walk away ' .. (left.walk and 'issued' or ('failed: ' .. tostring(left.walkWhy))))
        end
        -- E09-T04: personal relation changed by a real fact this NPC knows (offered in the request, checked again:
        -- relation revision, fact known and never used, direction of its nature, gap within -1..+1). E09-T08: a refused
        -- change is only ignored (logged with its reason): the line of the NPC is still said, nothing else depends on
        -- it. Never in ack.applied (a server fact, shown by the notebook).
        if result.intent == 'change_relation' then
            local view, why = Relations.apply(npc, req.character, Server.relations[req.id], result.dir, result.fact)
            if view then
                print('[RS_Carnet] relation of ' .. npc.id .. ' toward ' .. tostring(req.character) .. ' ' .. result.dir
                    .. ' (' .. why .. '): ' .. view.level .. ', group ' .. view.group)
            else
                print('[RS_Carnet] relation change of ' .. npc.id .. ' toward ' .. tostring(req.character) .. ' in '
                    .. tostring(req.id) .. ' ignored, reply kept: ' .. tostring(why))
            end
        end
        local m
        if result.intent == 'offer' then
            local terms = offerCatalog(npc, P.npc(npc.incarnation), req.character)[result.offer]
            if not req.offers[result.offer] or not terms then return false, 'offer no longer admissible' end
            local ok, why = true, nil
            if isCollective(terms) or isCollective(req.offers[result.offer]) then
                ok, why = Server.collectiveCheck(binding, npc)
            end
            if ok then
                m = M.create(S.data, npc, req.character, result.offer, terms)
                applied.offer = result.offer
            else
                ignored('collective offer', why) -- E09-T09: no mission, the line is still said
            end
        end
        local taken = acceptance and spokenAcceptance(req, result, npc) or nil
        if taken then applied.accept = taken.id end
        -- E11-T13: report of the met objective to this requester; a refused report is only ignored (E09-T09).
        if result.intent == 'report_done' then
            local reported, why = Server.spokenReport(req, result, npc)
            if reported then
                applied.report = reported.id
                print('[RS_Carnet] mission ' .. reported.id .. ' reported to ' .. npc.id .. ' by '
                    .. tostring(req.character) .. ': success')
            else
                ignored('mission report', why)
            end
        end
        local audiences = {}
        for _, listener in ipairs(players()) do
            local cid = Server.bound[listener]
            if cid and P.hears(object, listener, C.HEARING_RANGE) then
                local k = contact(cid, npc)
                k.history[#k.history + 1] = {id = req.id, author = npc.name, text = result.text}
                while #k.history > C.MAX_HISTORY do table.remove(k.history, 1) end
                if m then S.data.characters[cid].knownMissions[m.id] = true end
                audiences[#audiences + 1] = listener
            end
        end
        -- E17-T08: one more answered exchange of the speaking character; the first one dates the first meeting.
        local speaker = S.data.characters[req.character]
        local known = speaker and speaker.contacts[npc.id]
        if known then
            known.exchanges = (known.exchanges or 0) + 1
            if type(known.firstHour) ~= 'number' then known.firstHour = getGameTime():getWorldAgeHours() end
        end
        acknowledge(req, true, applied)
        -- Persist acceptance before rendering a reply/offer; replayed files cannot generate a second effect.
        if not S.save() then return false, 'state not saved' end
        -- E10-T02: the collective decision goes to the group journal (fact only: never the reply text nor reasons), read
        -- back in the context of every member of the group.
        local decided = (collectiveMission(m) and {kind = 'offer', mission = m})
            or (collectiveMission(taken) and {kind = 'accept', mission = taken}) or nil
        if decided and speaker then
            local ok, why = P.decide(npc.incarnation, {kind = decided.kind, need = decided.mission.supply.need,
                with = speaker.name})
            if not ok then
                print('[RS_Carnet] collective decision of ' .. tostring(npc.id) .. ' not logged: ' .. tostring(why))
            end
        end
        -- E10-T03: the embodied members react to the decision (requests sent by poll, after this reply).
        local reaction = (decided and speaker and {kind = decided.kind, need = decided.mission.supply.need, with = speaker.name})
            or (agreed and speaker and {kind = 'agreement', agreement = agreed.kind, with = speaker.name}) or nil
        if reaction then
            Server.reactionQueue[#Server.reactionQueue + 1] = {leader = npc, decision = reaction, language = req.language}
        end
        for _, listener in ipairs(audiences) do
            send(listener, 'speech', {world = S.data.world, run = S.run, id = req.id, npc = npc.id, incarnation = npc.incarnation, name = npc.name,
                text = result.text, x = object:getX(), y = object:getY(), z = object:getZ()})
        end
        Server.conversations.answered(Server, req, result, npc) -- E08-T05: an answered intervention joins its conversation
        -- E17-T09: a new offer is signalled on screen to the character it is made to, once (the offer is created once).
        if m then
            for player, cid in pairs(Server.bound) do
                if cid == req.character then send(player, 'offer', {mission = m.id}) end
            end
        end
        addSound(object, math.floor(object:getX()), math.floor(object:getY()), math.floor(object:getZ()), C.NOISE_RANGE, 10)
        return true
    end
    acknowledge(req, true, applied)
    if not S.save() then return false, 'state not saved' end
    return true
end

local function poll()
    local responses = T.readNpc() or {}
    local kept, changed, used = {}, false, {}
    for _, req in ipairs(Server.pending) do
        if not used[req.npc] then
            used[req.npc] = true
            local result = responses[req.id]
            if result or getTimestampMs() - req.sent > C.REQUEST_TIMEOUT_MS then
                local accepted, reason = false, 'no reply after ' .. C.REQUEST_TIMEOUT_MS .. ' ms'
                Server.initiatives.observe(req, result ~= nil) -- E08-T03: bridge considered stopped after a timeout
                if result then accepted, reason = reply(req, result) end
                if not accepted then
                    -- E17-T07: one line per refused request (the player only sees NoAnswer).
                    print('[RS_Carnet] ' .. tostring(req.kind) .. ' ' .. tostring(req.id) .. ' refused: ' .. tostring(reason))
                    -- E17-T15: newest last, {id, kind, npc, character, reason, at}, at most MAX_REFUSALS: the cause
                    local refusals = Server.refusals -- (bridge error timeout, http_503..., no reply) for suites/admin
                    refusals[#refusals + 1] = {id = req.id, kind = req.kind, npc = req.npc, character = req.character,
                        reason = tostring(reason), at = getTimestampMs()}
                    while #refusals > Server.MAX_REFUSALS do table.remove(refusals, 1) end
                    acknowledge(req, false)
                    local npc = S.data.npcs[req.npc]
                    if npc and req.kind == 'npc_enrich' then
                        npc.enrichState = 'deferred'
                        npc.enrichRetryAt = getTimestampMs() + C.ENRICH_RETRY_MS
                    end
                    for player, cid in pairs(Server.bound) do if cid == req.character then reject(player, 'NoAnswer') end end
                end
                Server.collectives[req.id] = nil
                Server.relations[req.id] = nil -- E09-T04
                Server.reactions[req.id] = nil -- E10-T03
                Server.conversations.settle(req.id) -- E08-T05: an unanswered intervention ends its conversation
                changed = true
            else kept[#kept + 1] = req end
        else kept[#kept + 1] = req end
    end
    Server.pending = kept
    -- E10-T03: member reactions of the decisions applied above, enqueued once the pending list is rebuilt.
    if #Server.reactionQueue > 0 then
        local queue = Server.reactionQueue
        Server.reactionQueue = {}
        for _, r in ipairs(queue) do Server.memberReactions(r.leader, r.decision, r.language) end
        changed = true
    end
    local acks = {}
    for _, ack in ipairs(T.acks) do
        local result = responses[ack.id]
        if not result or result.kind ~= 'ack_reply' or result.run ~= ack.run or result.world ~= ack.world then acks[#acks + 1] = ack
        else changed = true end
    end
    T.acks, S.data.acks = acks, acks
    if changed then S.save(); syncTransport(); publish() end
end

local function missionFor(player, character, args, range)
    local m = type(args.mission) == 'string' and S.data.missions[args.mission]
    if not m or (not m.invited[character] and not m.participants[character]) then return nil end
    -- E11-T08: a radio voice mission has no body to join: only accept and abandon (no range), never invite or claim.
    if m.donor == 'voice' then
        if range or m.transaction then return nil end
        return m
    end
    local npc = S.data.npcs[m.npc]
    if not npc or not npc.alive then return nil end
    if range and not activeNpc(player, character, m.npc, range) then return nil end
    if m.transaction then return nil end
    return m
end

local function transact(player, character, command, args)
    local range
    if command ~= 'accept' and command ~= 'abandon' then range = C.DELIVERY_RANGE end
    local m = missionFor(player, character, args, range)
    if not m or m.revision ~= args.revision then return reject(player, 'State') end
    if command == 'report' then
        -- E11-T13: notebook button "Report" (works without the bridge), next to the living requester's body
        -- (DELIVERY_RANGE, never for a radio voice: missionFor), objective met and sender a participant.
        if not M.reportReady(m) or not m.participants[character] then return reject(player, 'State') end
        local ok, reason = M.spoken(S, m, player, character)
        if not ok then return reject(player, reason) end
    elseif command == 'accept' then
        if not M.accept(S.data, m, character, S.data.characters[character].name) then return reject(player, 'State') end
    elseif command == 'invite' then
        if m.state ~= 'active' or not m.participants[character] or type(args.character) ~= 'string' then return reject(player, 'State') end
        local other
        for _, p in ipairs(players()) do if Server.bound[p] == args.character then other = p end end
        if not other or not P.near(player, other, C.SELECT_RANGE) then return reject(player, 'Range') end
        m.invited[args.character] = true
        S.data.characters[args.character].knownMissions[m.id] = true
        contact(args.character, S.data.npcs[m.npc])
        m.revision = m.revision + 1
    elseif command == 'abandon' then
        if not m.participants[character] or not M.finish(S.data, m, 'abandoned') then return reject(player, 'State') end
    elseif command == 'prepare_delivery' then
        if m.state ~= 'active' or not m.participants[character] or not M.checkItems(player, m, args.items) then return reject(player, 'Items') end
        local token = S.uid('quote')
        Server.quotes[character] = {token = token, mission = m.id, revision = m.revision, items = args.items,
            untilMs = getTimestampMs() + 30000}
        local quote = {token = token, mission = m.id, revision = m.revision, count = #args.items,
            remaining = m.quantity - m.delivered, requester = S.data.npcs[m.npc].name}
        -- E17-T03: value mission of an engine supply offer: value V of the chosen items.
        if m.unit == 'value' then quote.unit, quote.value = 'value', M.supplyValue(m, M.checkItems(player, m, args.items)) end
        send(player, 'quote', quote)
        return
    elseif command == 'confirm_delivery' then
        local q = Server.quotes[character]
        Server.quotes[character] = nil
        if not q or q.token ~= args.token or q.mission ~= m.id or q.revision ~= m.revision or q.untilMs < getTimestampMs() then return reject(player, 'State') end
        local ok, reason = M.deliver(S, m, player, character, q.items, q.token)
        if not ok then return reject(player, reason) end
    elseif command == 'claim' then
        local ok, reason = M.claim(S, m, player, character, S.uid('claim'))
        if not ok then return reject(player, reason) end
    else return end
    S.save()
    publish()
end

local MANDATE_ERRORS = {not_owner = 'MandateOwner', not_member = 'MandateMember', full = 'MandateFull'}

-- An empty argument table arrives as nil (SinglePlayerClient.java:126, GameClient.java:1760: args sent only when not
-- empty): the first hello of a new character ({character = nil}) used to be dropped here, so no notebook character
-- was ever created and the radio history (RS_RadioLog) stayed empty. nil is read as {}.
function Server.command(module, command, player, args)
    if module ~= C.MODULE or not player then return end
    if type(args) ~= 'table' then args = {} end
    if not S.data or S.blocked then return reject(player, 'Storage') end
    if player:isDead() then return reject(player, 'State') end
    local now = getTimestampMs()
    M.advance(S.data, math.max(0, now - tickAt))
    tickAt = now
    if command == 'hello' then
        identity(player, args.character)
        scan(); projection(player)
        return
    end
    if command == 'rep_admin' then return send(player, 'rep_admin', Server.reputationAdmin(player)) end
    local character = Server.bound[player]
    if not character then return reject(player, 'Identity') end
    if args.world ~= S.data.world or args.run ~= S.run then return reject(player, 'Session') end
    scan()
    if command == 'snapshot' then projection(player)
    elseif command == 'select' then
        local id = args.npc
        if type(args.incarnation) == 'number' or type(args.incarnation) == 'string' then
            local npc = Server.ensure(args.incarnation)
            id = npc and npc.incarnation == args.incarnation and npc.id or nil
            if id and not Server.objects[id] then scan() end -- a fiche created now has no mapped body yet
        end
        local npc = type(id) == 'string' and S.data.npcs[id]
        if npc and npc.alive and P.near(player, Server.objects[id], C.SELECT_RANGE) then
            contact(character, npc)
            Server.selected[character] = id
            S.save(); projection(player)
        else Server.selected[character] = nil; projection(player); reject(player, 'Range') end
    elseif command == 'deselect' then Server.selected[character] = nil; projection(player)
    elseif command == 'talk' then talk(player, character, args)
    elseif command == 'note' then
        local npc = type(args.npc) == 'string' and S.data.npcs[args.npc]
        local known = npc and S.data.characters[character].contacts[npc.id]
        if not known then return reject(player, 'State') end
        if type(args.text) ~= 'string' or #args.text > 2000 then return reject(player, 'Text') end
        -- Multi-line note (E17-T06): line breaks kept, other control characters replaced by a space.
        local note = args.text:gsub('\r\n?', '\n'):gsub('[%c]', function(c) return c == '\n' and c or ' ' end)
        known.note = note
        S.save(); projection(player)
    elseif command == 'mandate' then
        -- E09-T03: only the current owner designates or withdraws a negotiator (revalidated by RS_Factions).
        if args.action ~= 'grant' and args.action ~= 'revoke' then return reject(player, 'State') end
        local ok, reason = Factions.designate(player, args.member, args.action == 'grant')
        if not ok then return reject(player, MANDATE_ERRORS[reason] or 'State') end
        S.save(); publish()
    else transact(player, character, command, args) end
end

-- Notebook character of the account named by a server death cause (E04-T07), or nil. Same path as the revenge of
-- Living Knox (LK_Relations.onNpcDied): living player of this account (Relations.playerByName, else the connected
-- players), then its bound character (Hostility.keyOf reads Server.bound). Read only; never a client claim.
function Server.killerCharacter(account)
    if type(account) ~= 'string' or account == '' then return nil end
    local LK = LivingKnox
    local relations = type(LK) == 'table' and LK.Relations or nil
    local player = relations and relations.playerByName and relations.playerByName(account) or nil
    if not player then
        for _, p in ipairs(players()) do if p:getUsername() == account then player = p end end
    end
    if not player then return nil end
    local hostility = type(LK) == 'table' and LK.Hostility or nil
    local key = hostility and hostility.keyOf and hostility.keyOf(player) or Server.bound[player]
    local record = type(key) == 'string' and S.data.characters[key] or nil
    if not record or record.retired then return nil end
    return key
end

-- 'death' event of RS_NPCProvider: the provider body with this id died. cause (optional, E04-T06) is established on
-- the authority by the engine (LK_Bodies.deathCause: last hit of a player within 5 s, driver of a vehicle; fire,
-- trap without thrower, unseen death: no killer). E04-T07: a killer who takes part in an active mission of this
-- requester loses Reputation.requesterKilled (Q7), this character only, once per death (eventId
-- <npc>-killed-<character>); team mates are spared; a killer who does not take part is left to npc.memberKilled
-- (Server.npcDied). No penalty by proximity, never an accusation relayed from a client.
function Server.dead(id, object, cause)
    if not S.data or id == nil or not object then return end
    local npc = Server.find(id)
    if not npc then
        for _, candidate in pairs(S.data.npcs) do if candidate.incarnation == id then npc = candidate end end
    end
    if not npc or npc.incarnation ~= id or not npc.alive or not object:isDead() then return end
    npc.alive, npc.revision = false, npc.revision + 1
    local account = type(cause) == 'table' and cause.killer or nil
    local killer = Server.killerCharacter(account)
    local sanctioned = nil
    if killer then
        for _, m in pairs(S.data.missions) do
            if m.npc == npc.id and m.state == 'active' and m.participants[killer] then sanctioned = m end
        end
    end
    for _, m in pairs(S.data.missions) do if m.npc == npc.id then M.finish(S.data, m, 'cancelled_dead') end end
    if sanctioned then
        Rep.record(S.data, npc.id .. '-killed-' .. killer, killer, 'npc.requesterKilled', nil,
            {npc = npc.id, mission = sanctioned.id, body = id, cause = cause.cause}, {npc.name})
    end
    -- 'player': attributed to a notebook character; 'unbound': a player account without a notebook character;
    -- 'unavailable_server_evidence': no killer established by the server (fire, trap, unseen death).
    npc.deathAttribution = killer and 'player' or (account and 'unbound') or 'unavailable_server_evidence'
    Obs.forget(npc.id)
    S.save(); publish()
end

-- Living Knox fact npcDied (LK_Bodies.onZombieDead, published right after the provider 'death' event of the same
-- call): a group member killed by an attributed player costs Reputation.memberKilled (Q5) to this character only,
-- once per death (eventId lk-<npc>-g<generation>-memberKilled-<character>), unless the requester rule of
-- Server.dead already applied to this death.
function Server.npcDied(info)
    if not S.data or S.blocked or type(info) ~= 'table' or info.group == nil or info.npc == nil then return end
    local killer = Server.killerCharacter(info.killer)
    if not killer then return end
    for _, npc in pairs(S.data.npcs) do
        if npc.incarnation == info.npc and S.data.outcomes[npc.id .. '-killed-' .. killer] then return end
    end
    local eventId = 'lk-' .. tostring(info.npc) .. '-g' .. tostring(info.generation) .. '-memberKilled-' .. killer
    local o, dup = Rep.record(S.data, eventId, killer, 'npc.memberKilled', nil,
        {npc = info.npc, group = info.group, cause = info.cause})
    if o and not dup then S.save(); publish() end
end

-- E04-T11 (Q14): reputation level of a notebook character, read by Living Knox (LivingKnox.Hooks.reputation) for the
-- first welcome of a group that never met it (LK_Hostility.startForPlayer); nil for an unknown or dead character.
function Server.reputationLevel(character)
    if not S.data or S.blocked then return nil end
    return Rep.level(character, S.data)
end

-- Subscription to the Living Knox facts once its namespace exists (idempotent, keyed listener).
local function linkReputation()
    if Server.reputationLinked then return end
    local LK = LivingKnox
    if type(LK) ~= 'table' or type(LK.listen) ~= 'function' then return end
    LK.listen('npcDied', 'RS_Reputation.memberKilled', function(info) Server.npcDied(info) end)
    if type(LK.Hooks) ~= 'table' then LK.Hooks = {} end
    LK.Hooks.reputation = function(character) return RS_CarnetServer.reputationLevel(character) end
    Server.reputationLinked = true
end

-- E04-T14 (Q17): read-only view of every live character's reputation for an administrator: name, level, trend, last
-- acts (no score, no proof, no account). Access checked at each request on the authority, same rule as the Living
-- Knox and frequency debug tools (RS_FreqDebug.isAllowed: MP server = checkPermissions + role capability
-- PopmanManage; solo = debug mode; MP client never). Refusal: {ok = false, err = 'denied'} without data.
Server.REP_ADMIN_MAX = 64
function Server.reputationAdmin(player)
    local allowed, why = false, 'access rule unavailable'
    local Freq = RS_FreqDebug
    if Freq == nil then
        local ok, mod = pcall(require, 'RadioSurvivor/RS_FreqDebug')
        Freq = ok and mod or nil
    end
    if type(Freq) == 'table' and type(Freq.isAllowed) == 'function' then allowed, why = Freq.isAllowed(player) end
    if not allowed then
        print('[RS_Carnet] reputation admin view refused for ' .. tostring(player and player:getUsername()) .. ': '
            .. tostring(why))
        return {ok = false, err = 'denied'}
    end
    local ids = {}
    for id, record in pairs(S.data.characters) do
        if type(record) == 'table' and not record.retired then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        return tostring(S.data.characters[a].name or a) < tostring(S.data.characters[b].name or b)
    end)
    local list = {}
    for i = 1, math.min(#ids, Server.REP_ADMIN_MAX) do
        local id = ids[i]
        local p = Rep.projection(id, S.data)
        list[#list + 1] = {name = tostring(S.data.characters[id].name or '?'), level = p.level, trend = p.trend,
            reasons = p.reasons}
    end
    return {ok = true, characters = list, today = Rep.today()}
end

-- Uncontacted fiches without a loaded body, and dead ones, are dropped with their bindings.
local function prune(now)
    local removed = M.prune(S.data, now)
    local kept = {}
    for _, m in pairs(S.data.missions) do kept[m.npc] = true end
    for _, record in pairs(S.data.characters) do for id in pairs(record.contacts) do kept[id] = true end end
    for _, r in ipairs(Server.pending) do kept[r.npc] = true end
    for id, npc in pairs(S.data.npcs) do
        if not kept[id] and not Server.objects[id] and (not npc.alive or now - (npc.seenAt or 0) > C.NPC_UNSEEN_MS) then
            S.data.npcs[id] = nil
            removed = true
        end
    end
    if removed then
        for sig, id in pairs(S.data.bindings) do if not S.data.npcs[id] then S.data.bindings[sig] = nil end end
        S.dirty = true
    end
    -- Observation logs of removed or dead fiches (E08-T02).
    removed = Obs.prune() or removed
    removed = Relations.prune() or removed -- E09-T04: relations of removed fiches and retired characters
    removed = Rep.prune(S.data) or removed -- E04-T12: outcomes after 30 game days, retired characters after 7
    return removed
end

local function clockRunning()
    for _, m in pairs(S.data.missions) do if m.state == 'active' or m.state == 'offer' then return true end end
    return false
end

local Caches = require 'RadioSurvivor/RS_Caches'; require 'RadioSurvivor/RS_MissionRecover' -- E11-T06: caches, template recover
require 'RadioSurvivor/RS_MissionSignal' -- E11-T07: template signal (required mod Signal Smoke)
local function tick()
    if not S.data or S.blocked then return end
    local now = getTimestampMs()
    local changed = M.advance(S.data, math.max(0, now - tickAt)); tickAt = now
    if now >= checkAt then
        local present = {}
        for _, p in ipairs(players()) do present[p] = true end
        for p, cid in pairs(Server.bound) do
            if not present[p] then Server.bound[p], Server.selected[cid], Server.quotes[cid] = nil, nil, nil end
        end
        local gone = {}
        for p in pairs(Server.lastSnapshot) do if not present[p] then gone[#gone + 1] = p end end
        for _, p in ipairs(gone) do Server.lastSnapshot[p] = nil end
        scan()
        -- E08-T07: Living Knox facts (subscribed once its namespace exists) and comebacks of known characters.
        Triggers.link()
        linkReputation() -- E04-T09: npc.memberKilled from the Living Knox fact npcDied
        Triggers.returns(Server)
        Server.initiatives.tick(Server, now) -- E08-T03: at most one NPC initiative per pass
        Server.conversations.tick(Server, now) -- E08-T04: turns of the NPC conversations, at most one opened per pass
        Server.incidents.tick(Server, now) -- E09-T06: decision of a leader on an incident of a truce, one per pass
        for player, character in pairs(Server.bound) do
            local id = Server.selected[character]
            if id and not activeNpc(player, character, id, C.SELECT_RANGE) then
                Server.selected[character] = nil
                projection(player) -- only this player's view changed
            end
        end
        -- E11-T03: zones of the scout missions, polled once a second on the server copy of each connected,
        -- identified player (IsoPlayer position known by the server), never on a position sent by a client.
        -- No player connected: nothing is decided. E11-T05: also places a retrieve_id body (saved at once).
        local watched = {}
        for player, character in pairs(Server.bound) do watched[#watched + 1] = {player = player, character = character} end
        if #watched > 0 and M.observe(S.data, watched, S) then
            S.save()
            changed = true
        end
        -- E11-T06: caches still to place (reward cache of a voice mission; a recover cache is also placed by observe).
        if #watched > 0 and Caches.poll(S.data, S) then
            S.save()
            changed = true
        end
        poll()
        -- E09-T03: bounded poll of the vanilla factions (no server event): renames, owners, members, disbands.
        if Factions.sync(false) then changed = true end
        -- E09-T05: agreements confirmed by the next decisions of the group (nobody aims at a covered player any more):
        -- announced now, never before, to the online players of the team.
        local applied = Factions.pollApplications()
        if #applied > 0 then
            S.save()
            changed = true
            local online = players()
            for _, a in ipairs(applied) do
                local signer = a.signed and S.data.npcs[a.signed.npc]
                local name = signer and signer.groupName or ''
                print('[RS_Carnet] agreement ' .. a.id .. ' (' .. a.kind .. ') between ' .. a.group .. ' and ' .. a.team
                    .. ' applicable')
                for _, p in ipairs(Factions.membersOnline(a.team, online)) do
                    send(p, 'agreement', {id = a.id, revision = a.revision, kind = a.kind, state = a.state,
                        groupName = name})
                end
            end
        end
        checkAt = now + 1000
    end
    if now >= pruneAt then
        changed = prune(now) or changed
        pruneAt = now + C.PRUNE_INTERVAL_MS
    end
    -- Snapshots are pushed on changes; clients poll only while their notebook is open.
    if changed then S.dirty = true; publish() end
    if now >= saveAt then
        if S.dirty or clockRunning() then S.save() end
        saveAt = now + C.SAVE_INTERVAL_MS
    end
    if now >= enrichAt and #Server.pending < 2 and #T.acks < 8 then
        local times, enrichTimes = {}, {}
        for _, t in ipairs(Server.times) do if now - t < 3600000 then times[#times + 1] = t end end
        for _, t in ipairs(Server.enrichTimes) do if now - t < 3600000 then enrichTimes[#enrichTimes + 1] = t end end
        Server.times, Server.enrichTimes = times, enrichTimes
        for _, npc in pairs(S.data.npcs) do
            local attempts = Server.enrichAttempts[npc.id] or 0
            local ready = npc.enrichState == 'needed' or (npc.enrichState == 'deferred' and now >= (npc.enrichRetryAt or 0))
            if npc.alive and ready and attempts < C.ENRICH_MAX_ATTEMPTS and #times < C.MAX_PER_HOUR
                    and #enrichTimes < C.ENRICH_PER_HOUR then
                local request = enqueue(npc, 'npc_enrich', 'system', 'Describe your background.', C.NARRATIVE_LANGUAGE,
                    {name = npc.name, clan = npc.clan, group = P.context(npc.incarnation, nil, C.NARRATIVE_LANGUAGE)}, {})
                if request then
                    npc.enrichState = 'pending'
                    Server.enrichAttempts[npc.id] = attempts + 1
                    times[#times + 1], enrichTimes[#enrichTimes + 1] = now, now
                    syncTransport()
                end
                break
            end
        end
        enrichAt = now + 5000
    end
end

local function init(newWorld) -- OnInitGlobalModData arg: always true on a dedicated server (RS_WorldStart)
    if S.data then return end
    if S.init(newWorld == true and WorldStart.isNewWorld(true)) then
        T.acks = S.data.acks or {}
        local now = getTimestampMs()
        tickAt, saveAt = now, now + C.SAVE_INTERVAL_MS
        for _, npc in pairs(S.data.npcs) do if npc.enrichState == 'pending' then npc.enrichState = 'needed' end end
        scan(); syncTransport()
        print('[RS_Carnet] authoritative state ready, NPC provider=' .. tostring(P.active().name)
            .. ', available=' .. tostring(P.available()))
    end
end

-- E08-T03: NPC initiatives (RS_Initiatives), in the same per-NPC queue as the talks. A reply is said by the speech
-- channel of LK11-T04 only if the situation still holds; then acknowledged like a talk.
Server.initiatives = require 'RadioSurvivor/RS_Initiatives'
Server.enqueue, Server.syncTransport, Server.acknowledge = enqueue, syncTransport, acknowledge
-- E08-T06: radio of the equipped groups (RS_GroupRadio): a call on a group frequency is an npc_talk of this queue.
Server.contact, Server.acquaintance = contact, acquaintance
Server.groupRadio = require 'RadioSurvivor/RS_GroupRadio'
function Server.initiativeReply(req, result, npc)
    local ok, why = Server.initiatives.reply(Server, req, result, npc)
    if not ok then return false, why end
    acknowledge(req, true, {})
    if not S.save() then return false, 'state not saved' end
    publish()
    return true
end
-- E08-T04: conversations between two nearby NPCs (RS_Conversations): one line per request, said like an initiative.
Server.conversations = require 'RadioSurvivor/RS_Conversations'
function Server.conversationReply(req, result, npc)
    local ok, why = Server.conversations.reply(Server, req, result, npc)
    if not ok then return false, why end
    acknowledge(req, true, {})
    if not S.save() then return false, 'state not saved' end
    publish()
    return true
end
-- E09-T06: decision of the group leader on an incident of an agreement (RS_Incidents, RS_Factions): applied once, then
-- announced on screen to the online players of the team (decision, reparation category, group name).
Server.incidents = require 'RadioSurvivor/RS_Incidents'
function Server.incidentReply(req, result, npc)
    local ok, a, inc = Server.incidents.reply(Server, req, result, npc)
    if not ok then return false, a end
    acknowledge(req, true, {})
    if not S.save() then return false, 'state not saved' end
    for _, p in ipairs(Factions.membersOnline(a.team, players())) do
        send(p, 'incident', {id = inc.id, decision = inc.decision, category = inc.category or '',
            revision = a.revision, groupName = npc.groupName or ''})
    end
    publish()
    return true
end
Events.OnInitGlobalModData.Add(init)
Events.OnServerStarted.Add(function() init(false) end)
Events.OnGameStart.Add(function() init(false) end)
Events.OnClientCommand.Add(Server.command)
Events.OnTickEvenPaused.Add(tick)
P.on('death', Server.dead)
P.on('reincarnated', Server.reincarnated)
Triggers.attach(Server) -- E08-T07: mission_done, group_death, assault_seen
Events.OnSave.Add(function() if S.data then tick(); S.save() end end)
-- OnPlayerDeath is client-only (IsoPlayer.java:6096-6110). OnCharacterDeath also fires on the
-- dedicated server, for every character: keep players only.
function Server.characterDeath(character)
    if not S.data or not instanceof(character, 'IsoPlayer') then return end
    local md = character:getModData()
    local id = Server.bound[character] or md[IDENTITY_KEY]
    local record = type(id) == 'string' and S.data.characters[id] or nil
    if not record or record.owner ~= ownerOf(character) or record.retired then return end
    record.retired = true
    Rep.retire(S.data, id) -- E04-T12: reputation no longer read, purged with its outcomes after 7 game days
    record.radio = nil -- radio history of a dead character (E06-T04): never shown again, frees the private state
    -- What the voices remembered about this character (E07-T03, action remember): forgotten with it.
    require('RadioSurvivor/RS_Memory').forgetCharacter(id)
    md[IDENTITY_KEY] = nil
    Server.bound[character], Server.selected[id], Server.quotes[id] = nil, nil, nil
    S.save()
end
Events.OnCharacterDeath.Add(Server.characterDeath)
return Server
