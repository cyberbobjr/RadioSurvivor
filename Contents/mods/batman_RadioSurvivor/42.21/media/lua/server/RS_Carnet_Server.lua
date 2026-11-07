if isClient() then return end
if RS_CarnetServer then return RS_CarnetServer end
local C = require 'RadioSurvivor/RS_Config'
local Codec = require 'RadioSurvivorCore/RC_Codec'
local P = require 'RadioSurvivor/RS_NPCProvider'; local WorldStart = require 'RadioSurvivorCore/RC_WorldStart'
local S = require 'RadioSurvivor/RS_State'; require 'RadioSurvivorCore/RC_MissionClear' -- E11-T04: template clear
local Identity = require 'RadioSurvivorCore/RC_Identity' -- E18-T03: identity of the characters (core mod)
local M = require 'RadioSurvivorCore/RC_Missions'
local MissionList = require 'RadioSurvivorCore/RC_MissionList' -- E18-T06
local History = require 'RadioSurvivorCore/RC_History' -- E18-T11: exchange history of the core mod
require 'RadioSurvivorCore/RC_MissionScout'; require 'RadioSurvivorCore/RC_MissionRetrieve'
local Rep = require 'RadioSurvivorCore/RC_Reputation' -- E18-T22: reputation kept by the core mod
local Contacts = require 'RadioSurvivorCore/RC_Contacts' -- E18-T26: contacts given to the core notebook
-- Reputation of the snapshot: the core projection as it is (E18-T25: actions only, each notebook page translates the
-- acts its mod knows).
local function repProjection(character) return Rep.projection(character) end
local Radio = require 'RadioSurvivor/RadioSurvivor_Const'
local Obs = require 'RadioSurvivor/RS_Observations'
local Triggers = require 'RadioSurvivor/RS_ObservationTriggers' -- E08-T07: observation triggers
local Teams = require 'RadioSurvivorCore/RC_Teams' -- E09-T03, E18-T20: team ids and mandates of the core mod
-- E18-T20: agreements, personal truces and incidents are Living Knox's (LK_Agreements), read through its global; nil
-- without Living Knox (no agreement offered, none applied). E18-T17: so is the speech of the NPCs (LK_Talk).
local function Agreements() return type(LivingKnox) == 'table' and LivingKnox.Agreements or nil end
local MissionTalk = require 'RadioSurvivorCore/RC_MissionTalk'
local Relations = require 'RadioSurvivor/RS_Relations' -- E09-T04, E18-T21: relation kept by Living Knox, read by its API
local RateLimit = require 'RadioSurvivorCore/RC_RateLimit' -- C21: per-account limit of the notebook commands
-- E18-T17: Server.talk = the speech of the NPCs (LivingKnox.Talk), set when the world starts; nil without Living Knox.
local Server = {store = S, bound = {}, selected = {}, objects = {}, quotes = {}}
-- Export only on the authority, also used by the real-Lua simulation tests.
RS_CarnetServer = Server
local saveAt, checkAt, pruneAt = 0, 0, 0
-- E11-T20 (C27): mission and offer delays count play time (RC_GameClock: stopped while paused, faster at x2/x3),
-- not the real time of OnTickEvenPaused; one meter for every caller of M.advance.
local playMeter = require('RadioSurvivorCore/RC_GameClock').meter()

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

local IDENTITY_KEY = Identity.KEY -- 'RS_CarnetCharacter'

local function ownerOf(player)
    return Identity.ownerOf(player)
end

-- E18-T03: the identity of the character is decided by the core mod (RC_Identity: server modData copy, client claim
-- as a checked fallback, new identity, retirement at death; rules of E00-T01/E00-T02). The notebook keeps its own
-- record of the character (name, contacts, missions) under the same id, created at the first hello.
local function identity(player, claimed)
    if Server.bound[player] then
        claimed = Server.bound[player]
        send(player, 'identity', {character = claimed, world = S.data.world, run = S.run})
        return claimed
    end
    local id = Identity.bind(player, claimed)
    if not id then return nil end
    local record = S.data.characters[id]
    if record and record.retired then return nil end -- retired by the notebook (death seen before the core registry)
    if not record then
        S.data.characters[id] = {id = id, owner = ownerOf(player), slot = player:getPlayerNum(),
            name = displayName(player), contacts = {}, knownMissions = {}}
        if not S.save() then
            S.data.characters[id] = nil
            return nil
        end
    end
    Server.bound[player] = id
    send(player, 'identity', {character = id, world = S.data.world, run = S.run})
    return id
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
        record.contacts[npc.id] = {history = History.lines(character, npc.id), note = '', trust = trust,
            trend = 'Stable', stage = 'stranger', exchanges = 0}
        if npc.enrichState == 'idle' then npc.enrichState = 'needed' end
    end
    return record.contacts[npc.id]
end

-- E17-T08: acquaintance of a character with an NPC, kept on its contact (stage, exchanges, firstHour; RC_MissionTalk).
local function acquaintance(character, npc, known)
    return MissionTalk.acquaintance(S.data.missions, character, npc, known)
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

-- E18-T26: the fiche of an engine NPC (Living Knox: incarnation) belongs to its engine: without it the fiche is
-- hidden from the notebook and kept (never pruned), found again as it was when the engine comes back.
local function engineMissing(npc)
    return npc ~= nil and npc.incarnation ~= nil and P.available() ~= true
end
Server.engineMissing = engineMissing

-- Contacts of a character as the notebook shows them (snapshot, and source 'rs' of the core contacts, E18-T26).
local function contactRows(player, character, team)
    local record = character and S.data.characters[character]
    local contacts = {}
    if not record then return contacts end
    for id, known in pairs(record.contacts) do
        local npc = S.data.npcs[id]
        if npc and not engineMissing(npc) then
            contacts[#contacts + 1] = {id = id, name = npc.name, alive = npc.alive,
                groupName = groupName(npc), personality = npc.personality, background = npc.background,
                revision = npc.revision, near = P.near(player, Server.objects[id], C.SELECT_RANGE),
                history = known.history, note = known.note,
                -- E09-T07: relation panel of THIS character only (identifiers and game days, translated by the client;
                -- agreements of the NPC's group with this character's team). Replaces trust/trend keys of 0.2.
                relation = Relations.panel(npc, character, team)}
        end
    end
    table.sort(contacts, function(a, b) return a.name < b.name end)
    return contacts
end
Contacts.registerSource('rs', {list = function(character, player)
    return contactRows(player, character, Teams.projection(player))
end})

local function projection(player, pushed)
    local character = Server.bound[player]
    local record = character and S.data.characters[character]
    if not record then return end
    local missions, inviteTargets = {}, {}
    local team = Teams.projection(player) -- E09-T03: own team (agreements of the relation panel)
    local contacts = contactRows(player, character, team)
    -- E18-T06: the same list as the mission journal of the core mod (RC_MissionList: who sees it, order, state).
    for _, m in pairs(S.data.missions) do
        if M.present(m) and MissionList.visible(m, character, record.knownMissions) then
            local p = M.projection(m, character)
            -- E11-T08: a radio voice requester has no fiche nor body (name of its sheet, never near).
            p.requester = M.requester(S.data, m)
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
    MissionList.sort(missions)
    local snapshot = {world = S.data.world, run = S.run, contacts = contacts, missions = missions, selected = Server.selected[character] or '',
        -- E04-T12: reputation of this character only (level, trend, reasons), never a number.
        reputation = repProjection(character), inviteTargets = inviteTargets,
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

-- Server-configured mission allocations (RC_Missions templates), not fabricated by the model or the client.
-- character: notebook character the offers are computed for (engine supplies depend on its attitude, E17-T03).
local function offerCatalog(npc, record, character)
    return M.offers(npc, record, Server.objects[npc.id], character) -- body: where a scout place is drawn around
end

Server.offerCatalogFor = offerCatalog

local function talk(player, character, args)
    local id = Server.selected[character]
    local npc = activeNpc(player, character, id, C.SELECT_RANGE)
    if not npc or not Server.talk then
        -- E17-T06: the cleared target reaches the notebook at once (its Say line greys).
        Server.selected[character] = nil; projection(player)
        return reject(player, 'Range')
    end
    local req, reason = Server.talk.speak(player, character, npc, args)
    if not req then return reject(player, reason) end
    send(player, 'queued', {id = req.id})
end

-- E17-T09, E17-T10: acceptance spoken to the NPC (RC_MissionTalk), for a character of the notebook still alive.
local function spokenAcceptance(req, result, npc)
    local record = S.data.characters[req.character]
    if not record or record.retired then return nil end
    local m = MissionTalk.acceptance(S.data, req, result, npc, record.name)
    if m then record.knownMissions[m.id] = true end
    return m
end

-- E11-T13: report spoken to the requester (RC_MissionTalk).
function Server.spokenReport(req, result, npc) return MissionTalk.report(S, req, result, npc, Server.bound) end

local function missionFor(player, character, args, range)
    local m = type(args.mission) == 'string' and S.data.missions[args.mission]
    if not m or (not m.invited[character] and not m.participants[character]) then return nil end
    if not M.present(m) then return nil end -- E18-T25: giver of a mod not active, mission hidden
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


-- An empty argument table arrives as nil (SinglePlayerClient.java:126, GameClient.java:1760: args sent only when not
-- empty): the first hello of a new character ({character = nil}) used to be dropped here, so no notebook character
-- was ever created and the radio history (RS_RadioLog) stayed empty. nil is read as {}.
-- C21: per-account token buckets {capacity, per second} (RC_RateLimit, MP server only). hello and snapshot rebuild
-- and send the whole projection, rep_admin logs its refusals; every other command shares one bucket. The client polls
-- every 3 s with the notebook open: far below these limits. A dropped command gets no reply.
Server.RATE_LIMITS = {hello = {4, 0.5}, snapshot = {6, 1}, rep_admin = {3, 0.2}}
Server.RATE_LIMIT_OTHER = {20, 4}

function Server.command(module, command, player, args)
    if module ~= C.MODULE or not player then return end
    local limit = Server.RATE_LIMITS[command]
    local bucket = limit and ('carnet.' .. command) or 'carnet'
    limit = limit or Server.RATE_LIMIT_OTHER
    if not RateLimit.allow(player, bucket, limit[1], limit[2]) then return end
    if type(args) ~= 'table' then args = {} end
    if not S.data or S.blocked then return reject(player, 'Storage') end
    if player:isDead() then return reject(player, 'State') end
    M.advance(S.data, playMeter())
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
-- (Living Knox, LK_Reputation). No penalty by proximity, never an accusation relayed from a client.
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
        Rep.record(nil, npc.id .. '-killed-' .. killer, killer, 'npc.requesterKilled', nil,
            {npc = npc.id, mission = sanctioned.id, body = id, cause = cause.cause}, {npc.name})
    end
    -- 'player': attributed to a notebook character; 'unbound': a player account without a notebook character;
    -- 'unavailable_server_evidence': no killer established by the server (fire, trap, unseen death).
    npc.deathAttribution = killer and 'player' or (account and 'unbound') or 'unavailable_server_evidence'
    Obs.forget(npc.id)
    S.save(); publish()
end

-- E18-T22: npc.memberKilled is reported by Living Knox itself (LK_Reputation), which reads the reputation of the core
-- mod directly (first welcome of a group, LK_Hostility.reputationOf).

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
        local p = repProjection(id)
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
    for _, r in ipairs(Server.talk and Server.talk.pending or {}) do kept[r.npc] = true end
    for id, npc in pairs(S.data.npcs) do
        -- E18-T26: a fiche of an engine NPC is never dropped because its engine is not active (kept for its return).
        if not kept[id] and not Server.objects[id] and not engineMissing(npc)
                and (not npc.alive or now - (npc.seenAt or 0) > C.NPC_UNSEEN_MS) then
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
    -- E18-T21: personal relations are kept and purged by Living Knox (LivingKnox.PersonalRelation.prune).
    return removed
end

local function clockRunning()
    for _, m in pairs(S.data.missions) do if m.state == 'active' or m.state == 'offer' then return true end end
    return false
end

local Caches = require 'RadioSurvivor/RS_CacheAction' -- E11-T06: caches (core RC_Caches with the voice action)
require 'RadioSurvivorCore/RC_MissionRecover' -- E11-T06: template recover
require 'RadioSurvivorCore/RC_MissionSignal' -- E11-T07: template signal (required mod Signal Smoke)
local function tick()
    if not S.data or S.blocked then return end
    local now = getTimestampMs()
    local changed = M.advance(S.data, playMeter())
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
        Triggers.returns(Server)
        if Server.talk then Server.talk.turns(now) end -- E18-T17: initiatives, conversations, incidents (LK_Talk)
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
        if Server.talk then Server.talk.poll() end
        -- E09-T03: bounded poll of the vanilla factions (no server event): renames, owners, members, disbands.
        if Teams.sync(false) then changed = true end
        -- E09-T05: agreements confirmed by the next decisions of the group (polled by Living Knox, E18-T20): announced
        -- when they become applicable, never before, to the online players of the team (listener Server.announce).
        if Agreements() then Agreements().onApplied(Server.announce) end
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
    if Server.talk then Server.talk.enrich(now) end
end

local function init(newWorld) -- OnInitGlobalModData arg: always true on a dedicated server (RC_WorldStart)
    if S.data then return end
    if S.init(newWorld == true and WorldStart.isNewWorld(true)) then
        Identity.init(newWorld) -- E18-T03: core registry first (same OnInitGlobalModData argument)
        Identity.adopt(S.data.characters) -- notebook records of a game made before the split, retirements included
        local now = getTimestampMs()
        saveAt = now + C.SAVE_INTERVAL_MS
        playMeter() -- start of the play clock: nothing counted for the time before the world loaded
        for _, npc in pairs(S.data.npcs) do if npc.enrichState == 'pending' then npc.enrichState = 'needed' end end
        scan()
        Server.attachTalk()
        print('[RS_Carnet] authoritative state ready, NPC provider=' .. tostring(P.active().name)
            .. ', available=' .. tostring(P.available()))
    end
end

-- E08-T06: radio of the equipped groups (RS_GroupRadio): a call on a group frequency is an npc_talk of the queue.
Server.contact, Server.acquaintance = contact, acquaintance
Server.groupRadio = require 'RadioSurvivor/RS_GroupRadio'

-- E18-T17: what the notebook adds to the speech of the NPCs (LK_TalkHost). --------------------------------------------

-- E17-T08, E17-T09, E17-T10, E10-T02: fiche of the speaker in the context of a sentence, its offers and their bindings.
local function talkContext(context, npc, character, _, _, group)
    local known = contact(character, npc)
    -- E09-T04: personal relation of the NPC toward this character (labels only) and the real facts it may cite to
    -- change it (short ids; the keys stay on the server). Replaces the former trust.
    local relation, relationBinding = Relations.offer(npc, character)
    context.relation = relation
    -- E17-T08: a stranger never learns the group nor its home (name, story, leader, needs withheld from the prompt).
    context.stage = acquaintance(character, npc, known)
    local g = context.group
    if g and context.stage == 'stranger' then context.group = {member = g.member, role = g.role, attitude = g.attitude} end
    local offers, bound = MissionTalk.context(context, S.data, npc, character, group, function()
        return offerCatalog(npc, P.npc(npc.incarnation), character)
    end)
    return offers, bound, relationBinding
end

-- The player's canonical speech is already sent by vanilla. Record only for admitted nearby listeners.
local function talkQueued(req, player, npc, character, text)
    for _, listener in ipairs(players()) do
        local cid = Server.bound[listener]
        if cid and P.hears(player, listener, C.HEARING_RANGE) then
            local k = contact(cid, npc)
            k.history[#k.history + 1] = {id = req.id .. '-player', author = S.data.characters[character].name, text = text}
            while #k.history > C.MAX_HISTORY do table.remove(k.history, 1) end
        end
    end
    S.save()
end

-- Missions of a reply (RC_MissionTalk).
local function talkActions(req, result, npc, binding, ignored)
    return MissionTalk.actions({state = S.data, store = S, bound = function() return Server.bound end,
        catalog = function(n, character) return offerCatalog(n, P.npc(n.incarnation), character) end,
        collectiveCheck = Server.talk.collectiveCheck, accept = spokenAcceptance}, req, result, npc, binding, ignored)
end

-- Listeners of a reply: the line goes to their history; E17-T08: one more answered exchange of the speaking character,
-- the first one dates the first meeting.
local function heard(req, result, npc, object, outcome)
    local audiences = {}
    for _, listener in ipairs(players()) do
        local cid = Server.bound[listener]
        if cid and P.hears(object, listener, C.HEARING_RANGE) then
            local k = contact(cid, npc)
            k.history[#k.history + 1] = {id = req.id, author = npc.name, text = result.text}
            while #k.history > C.MAX_HISTORY do table.remove(k.history, 1) end
            if outcome.offer then S.data.characters[cid].knownMissions[outcome.offer.id] = true end
            audiences[#audiences + 1] = listener
        end
    end
    local speaker = S.data.characters[req.character]
    local known = speaker and speaker.contacts[npc.id]
    if known then
        known.exchanges = (known.exchanges or 0) + 1
        if type(known.firstHour) ~= 'number' then known.firstHour = getGameTime():getWorldAgeHours() end
    end
    return audiences
end

-- A line said by npc, kept in the history of the listeners who already know it (no contact created).
local function remember(npc, id, text, listeners)
    for _, p in ipairs(listeners) do
        local cid = Server.bound[p]
        local record = cid and S.data.characters[cid]
        local known = record and record.contacts[npc.id]
        if known then
            known.history[#known.history + 1] = {id = id, author = npc.name, text = text}
            while #known.history > C.MAX_HISTORY do table.remove(known.history, 1) end
        end
    end
end

-- Groups already known to a character: group of each fiche among its contacts.
local function contactedGroups()
    local out = {}
    for _, record in pairs(S.data.characters or {}) do
        for id in pairs(type(record.contacts) == 'table' and record.contacts or {}) do
            local npc = S.data.npcs[id]
            if npc and type(npc.clan) == 'string' and npc.clan ~= '' then out[npc.clan] = true end
        end
    end
    return out
end

local HOST = {
    provider = P,
    observations = Obs,
    session = function() return S.data.world, S.run end,
    fiche = function(id) return S.data.npcs[id] end,
    fiches = function() return S.data.npcs end,
    find = Server.find,
    ensure = Server.ensure,
    objects = function() return Server.objects end,
    bound = function() return Server.bound end,
    players = players,
    scan = scan,
    characterName = function(character)
        local record = S.data.characters[character]
        return record and record.name or nil
    end,
    save = S.save,
    publish = publish,
    reject = function(character, reason)
        for player, cid in pairs(Server.bound) do if cid == character then reject(player, reason) end end
    end,
    remember = remember,
    contactedGroups = contactedGroups,
    overheard = function(player, character, seen) require('RadioSurvivor/RS_Comfort').overheard(player, character, seen) end,
    callLanguage = Radio.callLanguage,
    claim = function(req)
        if not Server.groupRadio.owns(req.id) then return nil end
        return function(r, result, npc) return Server.groupRadio.reply(Server, r, result, npc) end
    end,
    talkContext = talkContext,
    talkQueued = talkQueued,
    relationApply = function(npc, character, binding, dir, fact) return Relations.apply(npc, character, binding, dir, fact) end,
    talkActions = talkActions,
    heard = heard,
    speech = function(listeners, req, result, npc, object)
        for _, listener in ipairs(listeners) do
            send(listener, 'speech', {world = S.data.world, run = S.run, id = req.id, npc = npc.id,
                incarnation = npc.incarnation, name = npc.name, text = result.text, x = object:getX(),
                y = object:getY(), z = object:getZ()})
        end
    end,
    offered = function(m, character)
        for player, cid in pairs(Server.bound) do
            if cid == character then send(player, 'offer', {mission = m.id}) end
        end
    end,
    -- E09-T06: decision of a group leader on an incident, announced on screen to the online players of the team.
    incidentDecided = function(a, inc, npc)
        for _, p in ipairs(Agreements().membersOnline(a.team, players())) do
            send(p, 'incident', {id = inc.id, decision = inc.decision, category = inc.category or '',
                revision = a.revision, groupName = npc.groupName or ''})
        end
    end,
}

-- Living Knox active: the notebook is the host of its speech. Called once the state of the notebook is ready.
function Server.attachTalk()
    local talk = type(LivingKnox) == 'table' and LivingKnox.Talk or nil
    if type(talk) ~= 'table' or type(talk.attach) ~= 'function' then return end
    if talk.attach(HOST) then
        Server.talk = talk
        talk.sync()
    else
        print('[RS_Carnet] speech of the NPCs not ready: Living Knox state unavailable')
    end
end

-- E09-T05: an agreement that became applicable (LivingKnox.Agreements.onApplied), announced on screen to the online
-- players of its team with the name of the signer's group.
function Server.announce(a)
    local signer = a.signed and S.data and S.data.npcs[a.signed.npc]
    local name = signer and signer.groupName or ''
    print('[RS_Carnet] agreement ' .. a.id .. ' (' .. a.kind .. ') between ' .. a.group .. ' and ' .. a.team
        .. ' applicable')
    for _, p in ipairs(Agreements().membersOnline(a.team, players())) do
        send(p, 'agreement', {id = a.id, revision = a.revision, kind = a.kind, state = a.state, groupName = name})
    end
    publish()
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
    -- E18-T03: the core mod may have retired the identity first (its OnCharacterDeath subscriber): idOf keeps it.
    local id = Server.bound[character] or md[IDENTITY_KEY] or Identity.idOf(character)
    local record = type(id) == 'string' and S.data.characters[id] or nil
    if not record or record.owner ~= ownerOf(character) or record.retired then return end
    record.retired = true
    -- radio history of a dead character (E06-T04): never shown again, frees the private state (core mod, E18-T19)
    local H = require 'RadioSurvivorCore/RC_History'
    if H.data and type(H.data.radio) == 'table' and H.data.radio[id] ~= nil then
        H.data.radio[id], H.dirty = nil, true
    end
    -- What the voices remembered about this character (E07-T03, action remember): forgotten with it.
    require('RadioSurvivor/RS_Memory').forgetCharacter(id)
    md[IDENTITY_KEY] = nil
    Server.bound[character], Server.selected[id], Server.quotes[id] = nil, nil, nil
    S.save()
end
Events.OnCharacterDeath.Add(Server.characterDeath)
return Server
