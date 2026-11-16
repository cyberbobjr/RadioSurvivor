if isClient() then return end
--[[
CoreAI: server of the notebook (E21-T04, design carnet-commun-e21.md).
Authority only (dedicated server or solo). Loaded for every mod that uses the core mod: with no NPC provider
registered it still serves the identity of the characters, the missions of the givers without a body, the reputation
and the snapshot of the notebook.

Global CoreAI.notebookServer (also read by the real-Lua simulation tests). Private state: CA_NotebookStore
(characters, NPC fiches, bindings; missions and histories in their own files of the core mod). Network module
CA_NotebookConfig.MODULE ('CoreAI'), commands registered by Server.registerCommand (an unknown command is ignored).
Mission engine (CA_Missions): store, NPC provider, giver 'npc' (notebook fiches of the provider's NPCs) and its hooks
are attached here (Server.attachMissions), with every mission template of the core mod.
Registries filled by the mods that use the notebook (read here only):
  Server.addPoll(fn)        fn(state, store, watched) -> true when it changed the state (saved and published);
                            called once a second while identified players are connected (watched = { {player,
                            character}, ... }).
  Server.hooks.overheard    list of fn(player, character, seen): a player heard two NPCs talk (speech host).
  Server.hooks.claim        list of fn(request) -> reply handler or nil: a reply handled by its mod (first one wins).
  Server.hooks.callLanguage fn() -> forced language of the NPC initiatives, or nil (one per server).
The NPC provider (CA_NPCProvider) gives the bodies, the speech engine (speech()) and the relations (relation*).
]]
CoreAI = CoreAI or {}
if CoreAI.notebookServer then return CoreAI.notebookServer end
local C = require 'CoreAI/CA_NotebookConfig'
local Speech = require 'CoreAI/CA_SpeechConfig'
local TextCut = require 'CoreAI/CA_TextCut'
local Access = require 'CoreAI/CA_AdminAccess'
local Codec = require 'CoreAI/CA_Codec'
local P = require 'CoreAI/CA_NPCProvider'; local WorldStart = require 'CoreAI/CA_WorldStart'
local S = require 'CoreAI/CA_NotebookStore'
local Identity = require 'CoreAI/CA_Identity' -- E18-T03: identity of the characters (core mod)
local M = require 'CoreAI/CA_Missions'
local Giver = require 'CoreAI/CA_NotebookGiver'
local MissionList = require 'CoreAI/CA_MissionList' -- E18-T06
local MissionLoss = require 'CoreAI/CA_MissionLoss' -- E23-T02: missions lost with a dead character
local History = require 'CoreAI/CA_History' -- E18-T11: exchange history of the core mod
-- Mission templates of the core mod (CA_Missions.register at load; deliver is the engine's own).
require 'CoreAI/CA_MissionScout'; require 'CoreAI/CA_MissionRetrieve'; require 'CoreAI/CA_MissionClear'
require 'CoreAI/CA_MissionRecover'; require 'CoreAI/CA_MissionSignal'; require 'CoreAI/CA_MissionBarricade'
require 'CoreAI/CA_MissionRelay'; require 'CoreAI/CA_MissionWatch'; require 'CoreAI/CA_MissionRoute'
require 'CoreAI/CA_MissionItem'
local Rep = require 'CoreAI/CA_Reputation' -- E18-T22: reputation kept by the core mod
local Contacts = require 'CoreAI/CA_Contacts' -- E18-T26: contacts given by the other sources of the mods
-- Reputation of the snapshot: the core projection as it is (E18-T25: actions only, each notebook page translates the
-- acts its mod knows).
local function repProjection(character) return Rep.projection(character) end
-- E18-T27: observations of the NPCs and their triggers belong to the NPC engine.
local Teams = require 'CoreAI/CA_Teams' -- E09-T03, E18-T20: team ids and mandates of the core mod
local MissionTalk = require 'CoreAI/CA_MissionTalk'
local RateLimit = require 'CoreAI/CA_RateLimit' -- C21: per-account limit of the notebook commands
-- E18-T17, E21-T04: Server.talk = the speech engine of the NPC provider (CA_NPCProvider.speech), set when the world
-- starts; nil when the provider has none.
local Server = {store = S, bound = {}, selected = {}, objects = {}, quotes = {}}
CoreAI.notebookServer = Server
local saveAt, checkAt, pruneAt = 0, 0, 0
local function log(msg) print('[CoreAI] notebook: ' .. tostring(msg)) end
Server.polls = {}
Server.hooks = {overheard = {}, claim = {}, callLanguage = nil}
function Server.addPoll(fn)
    for _, known in ipairs(Server.polls) do if known == fn then return end end
    Server.polls[#Server.polls + 1] = fn
end
-- E11-T20 (C27): mission and offer delays count play time (CA_GameClock: stopped while paused, faster at x2/x3),
-- not the real time of OnTickEvenPaused; one meter for every caller of M.advance.
local playMeter = require('CoreAI/CA_GameClock').meter()

local function send(player, command, args)
    args = args or {}
    if S.data then args.world, args.run = S.data.world, S.run end
    if isServer() then sendServerCommand(player, C.MODULE, command, args or {})
    else
        -- solo: same Lua, the notebook client of the core mod receives the answer by name (E21-T03)
        local client = CoreAI and CoreAI.notebookClient
        if client then client.receive(command, args or {}) end
    end
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
    return TextCut.oneLine(d:getForename() .. ' ' .. d:getSurname())
end

local IDENTITY_KEY = Identity.KEY -- 'CA_Character'

local function ownerOf(player)
    return Identity.ownerOf(player)
end

-- E18-T03: the identity of the character is decided by the core mod (CA_Identity: server modData copy, client claim
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
        npc = {id = key, incarnation = id, signature = signature, name = TextCut.oneLine(record.name or 'Survivor'),
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
    npc.groupName = TextCut.oneLine(record.groupName or '') -- E17-T06: readable name for the notebook ('' none)
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

-- The provider recreated an NPC under a new id ('reincarnated' event of CA_NPCProvider): keep the
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

-- E17-T08: acquaintance of a character with an NPC, kept on its contact (stage, exchanges, firstHour; CA_MissionTalk).
local function acquaintance(character, npc, known)
    return MissionTalk.acquaintance(S.data.missions, character, npc, known)
end

-- Readable group name of an NPC (E17-T06): live provider record, else the name kept on the fiche; never the raw
-- group id ("grp-<n>"), '' when the NPC has no group or the provider gives no name.
local function groupName(npc)
    local record = P.npc(npc.incarnation)
    if record then return TextCut.oneLine(record.groupName or '') end
    return npc.groupName or ''
end

-- E00-T04: a pushed snapshot (publish) is sent only when its content changed for this player since the last one sent
-- to it; an answer to the player's own request (hello, snapshot and every command of this player) is always sent.
-- Comparison on the encoded snapshot without its timestamp `at`. Several modules publish after a change that is not
-- this player's (a line said by an NPC nobody of this character knows, a reply polled then published twice...): an
-- idle player no longer receives the same snapshot again (lk.carnet.load, E00-T04).
Server.lastSnapshot = {} -- player -> {key, body}; entries of absent players dropped by tick (no weak table in Kahlua)

-- E18-T26: the fiche of an engine NPC (incarnation) belongs to its engine: without it the fiche is
-- hidden from the notebook and kept (never pruned), found again as it was when the engine comes back.
local function engineMissing(npc)
    return npc ~= nil and npc.incarnation ~= nil and P.available() ~= true
end
Server.engineMissing = engineMissing

-- E21-T04 (decision 2 of carnet-commun-e21.md): NPCs the character knows only through a personal relation
-- (CA_NPCProvider.contacts) stay among its contacts: their fiche becomes a contact of the character.
local function adoptRelated(character, record)
    for _, id in ipairs(P.contacts(character)) do
        local npc = Server.ensure(id)
        if npc and npc.incarnation == id and not record.contacts[npc.id] then
            contact(character, npc)
            S.dirty = true
        end
    end
end

-- Contacts of a character as the notebook shows them: its fiches, then the rows of the contact sources of the mods
-- (CA_Contacts, E18-T26: interlocutors a mod knows without a fiche of the notebook; such a row carries its source).
local function contactRows(player, character, team)
    local record = character and S.data.characters[character]
    local contacts = {}
    if not record then return contacts end
    adoptRelated(character, record)
    for id, known in pairs(record.contacts) do
        local npc = S.data.npcs[id]
        if npc and not engineMissing(npc) then
            contacts[#contacts + 1] = {id = id, name = npc.name, alive = npc.alive,
                groupName = groupName(npc), personality = npc.personality, background = npc.background,
                revision = npc.revision, near = P.near(player, Server.objects[id], Speech.SELECT_RANGE),
                history = known.history, note = known.note, page = P.name(),
                -- E09-T07: relation panel of THIS character only (identifiers and game days, translated by the client;
                -- agreements of the NPC's group with this character's team), given by the NPC provider (E21-T04).
                relation = P.relationPanel(npc, character, team)}
        end
    end
    for _, row in ipairs(Contacts.rows(character, player)) do contacts[#contacts + 1] = row end
    table.sort(contacts, function(a, b) return a.name < b.name end)
    return contacts
end

-- Requester of a mission next to this player (DELIVERY_RANGE): the giver's near(m, player); a giver without one (remote
-- giver) is never near.
local function nearRequester(m, player)
    local giver = M.donor(m.donor or 'npc')
    return giver ~= nil and giver.near ~= nil and giver.near(m, player) == true
end

local function projection(player, pushed)
    local character = Server.bound[player]
    local record = character and S.data.characters[character]
    if not record then return end
    local missions, inviteTargets = {}, {}
    local team = Teams.projection(player) -- E09-T03: own team (agreements of the relation panel)
    local contacts = contactRows(player, character, team)
    -- E18-T06: the same list as the mission journal of the core mod (CA_MissionList: who sees it, order, state).
    local known = M.knownMissions(S.data, character)
    for _, m in pairs(S.data.missions) do
        if M.present(m) and MissionList.visible(m, character, known) then
            local p = M.projection(m, character)
            -- E11-T08: a remote giver (radio voice) has no fiche nor body (name of its sheet, never near).
            p.requester = M.requester(S.data, m)
            p.near = nearRequester(m, player)
            missions[#missions + 1] = p
        end
    end
    for _, other in ipairs(players()) do
        local id = Server.bound[other]
        if id and id ~= character and P.near(player, other, Speech.SELECT_RANGE) then
            inviteTargets[#inviteTargets + 1] = {id = id, name = S.data.characters[id].name}
        end
    end
    MissionList.sort(missions)
    local snapshot = {world = S.data.world, run = S.run, contacts = contacts, missions = missions,
        selected = Server.selected[character] or '',
        -- E04-T12: reputation of this character only (level, trend, reasons), never a number.
        reputation = repProjection(character), inviteTargets = inviteTargets,
        team = team,
        -- E23-T02: missions the previous character of this account lost with its death.
        lostMissions = MissionLoss.notices(S.data, record),
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

-- Also called by the mods whose remote givers start or close a mission (E11-T08).
Server.publish = publish

local function activeNpc(player, character, id, range)
    local npc = type(id) == 'string' and S.data.npcs[id]
    local object = npc and Server.objects[id]
    if not npc or not npc.alive or not P.near(player, object, range) then return nil end
    if not S.data.characters[character].contacts[id] then return nil end
    return npc, object
end

-- Server-configured mission allocations (CA_Missions templates), not fabricated by the model or the client.
-- character: notebook character the offers are computed for (engine supplies depend on its attitude, E17-T03).
local function offerCatalog(npc, record, character)
    return M.offers(npc, record, Server.objects[npc.id], character) -- body: where a scout place is drawn around
end

Server.offerCatalogFor = offerCatalog

-- Fiche of the provider NPC with this id (incarnation), next to the player (SELECT_RANGE), made a contact of the
-- character; nil when it is not near. A fiche created now has no mapped body yet: scanned again.
local function reach(player, character, incarnation)
    local npc = Server.ensure(incarnation)
    if not npc or npc.incarnation ~= incarnation then return nil end
    if not Server.objects[npc.id] then scan() end
    if not npc.alive or not P.near(player, Server.objects[npc.id], Speech.SELECT_RANGE) then return nil end
    contact(character, npc)
    return npc
end

-- E17-T06: target of the local chat. args.incarnation: the NPC of the provider with this id, else args.npc: a fiche id.
-- Returns the selected fiche, or nil (target cleared) when it is not near.
local function selectTarget(player, character, args)
    local npc
    if type(args.incarnation) == 'number' or type(args.incarnation) == 'string' then
        npc = reach(player, character, args.incarnation)
    else
        local known = type(args.npc) == 'string' and S.data.npcs[args.npc] or nil
        if known and known.alive and P.near(player, Server.objects[known.id], Speech.SELECT_RANGE) then
            contact(character, known)
            npc = known
        end
    end
    Server.selected[character] = npc and npc.id or nil
    return npc
end

-- Decision 1 of carnet-commun-e21.md: fiche of the nearest provider NPC next to the player (SELECT_RANGE), made a
-- contact of the character, or nil.
local function nearestNpc(player, character)
    local nearest, distance
    for id, body in pairs(P.available() and P.objects() or {}) do
        if P.near(player, body, Speech.SELECT_RANGE) then
            local dx, dy = body:getX() - player:getX(), body:getY() - player:getY()
            local d = dx * dx + dy * dy
            if not distance or d < distance then nearest, distance = id, d end
        end
    end
    return nearest and reach(player, character, nearest) or nil
end

local function speak(player, character, npc, args)
    local req, reason = Server.talk.speak(player, character, npc, args)
    if not req then return reject(player, reason) end
    send(player, 'queued', {id = req.id})
end

-- A sentence of a character. args.incarnation (menu of an NPC engine on a body): that NPC is selected first, then
-- spoken to. args.chat (say chat) without a selected target: the nearest NPC, nothing and no message when none is near.
local function talk(player, character, args)
    if args.incarnation ~= nil then
        if not Server.talk or not selectTarget(player, character, args) then
            projection(player)
            return reject(player, 'Range')
        end
        S.save(); projection(player)
    elseif args.chat == true and (Server.selected[character] or '') == '' then
        local nearest = Server.talk and nearestNpc(player, character) or nil
        if nearest then speak(player, character, nearest, args) end
        return
    end
    local id = Server.selected[character]
    local npc = activeNpc(player, character, id, Speech.SELECT_RANGE)
    if not npc or not Server.talk then
        -- E17-T06: the cleared target reaches the notebook at once (its Say line greys).
        Server.selected[character] = nil; projection(player)
        return reject(player, 'Range')
    end
    speak(player, character, npc, args)
end

-- E17-T09, E17-T10: acceptance spoken to the NPC (CA_MissionTalk), for a character of the notebook still alive.
local function spokenAcceptance(req, result, npc)
    local record = S.data.characters[req.character]
    if not record or record.retired then return nil end
    local m = MissionTalk.acceptance(S.data, req, result, npc, record.name)
    if m then record.knownMissions[m.id] = true end
    return m
end

-- E11-T13: report spoken to the requester (CA_MissionTalk).
function Server.spokenReport(req, result, npc) return MissionTalk.report(S, req, result, npc, Server.bound) end

-- Mission of a gesture, or nil, the reason of the refusal (State; Range: the requester is not next to the player) and
-- what failed (server log only).
local function missionFor(player, character, args, ranged)
    local m = type(args.mission) == 'string' and S.data.missions[args.mission]
    if not m then return nil, 'State', 'unknown mission' end
    if not m.invited[character] and not m.participants[character] then return nil, 'State', 'not invited' end
    if not M.present(m) then return nil, 'State', 'giver absent' end -- E18-T25: giver of a mod not active, mission hidden
    local giver = M.donor(m.donor or 'npc')
    -- E11-T08, E21-T04: a remote giver (radio voice) has no body to join: only accept and abandon (no range), never
    -- invite or claim.
    if giver.remote then
        if ranged then return nil, 'State', 'remote giver' end
        if m.transaction then return nil, 'State', 'transaction pending' end
        return m
    end
    local requester = M.donorOf(S.data, m)
    if not requester or requester.alive == false then return nil, 'State', 'requester gone' end
    if ranged then
        if not nearRequester(m, player) then return nil, 'Range', 'requester not near' end
        -- A fiche of the notebook speaks only to the characters that know it (contact).
        if S.data.npcs[m.npc] and not S.data.characters[character].contacts[m.npc] then
            return nil, 'State', 'requester not a contact'
        end
    end
    if m.transaction then return nil, 'State', 'transaction pending' end
    return m
end

-- E21-T03: gestures on a mission, one entry per notebook command. ranged: next to the requester (DELIVERY_RANGE).
-- apply(player, character, m, args) -> true (done: saved and published), false and the reason of a refusal, or
-- ANSWERED when it answered itself (quote).
local ANSWERED = 'answered'
local gestures = {}
gestures.report = {ranged = true, apply = function(player, character, m)
    -- E11-T13: notebook button "Report" (works without the bridge), next to the living requester's body
    -- (DELIVERY_RANGE, never for a radio voice: missionFor), objective met and sender a participant.
    if not M.reportReady(m) or not m.participants[character] then return false, 'State' end
    return M.spoken(S, m, player, character)
end}
gestures.accept = {apply = function(_, character, m)
    if not M.accept(S.data, m, character, S.data.characters[character].name) then return false, 'State' end
    return true
end}
gestures.invite = {ranged = true, apply = function(player, character, m, args)
    if m.state ~= 'active' or not m.participants[character] or type(args.character) ~= 'string' then return false, 'State' end
    local other
    for _, p in ipairs(players()) do if Server.bound[p] == args.character then other = p end end
    if not other or not P.near(player, other, Speech.SELECT_RANGE) then return false, 'Range' end
    m.invited[args.character] = true
    S.data.characters[args.character].knownMissions[m.id] = true
    local npc = S.data.npcs[m.npc]
    if npc then contact(args.character, npc) end
    m.revision = m.revision + 1
    return true
end}
gestures.abandon = {apply = function(_, character, m)
    if not m.participants[character] or not M.finish(S.data, m, 'abandoned') then return false, 'State' end
    return true
end}
gestures.prepare_delivery = {ranged = true, apply = function(player, character, m, args)
    if m.state ~= 'active' or not m.participants[character] or not M.checkItems(player, m, args.items) then
        return false, 'Items'
    end
    local token = S.uid('quote')
    Server.quotes[character] = {token = token, mission = m.id, revision = m.revision, items = args.items,
        untilMs = getTimestampMs() + 30000}
    local quote = {token = token, mission = m.id, revision = m.revision, count = #args.items,
        remaining = m.quantity - m.delivered, requester = M.requester(S.data, m)}
    -- E17-T03: value mission of an engine supply offer: value V of the chosen items.
    if m.unit == 'value' then quote.unit, quote.value = 'value', M.supplyValue(m, M.checkItems(player, m, args.items)) end
    send(player, 'quote', quote)
    return ANSWERED
end}
gestures.confirm_delivery = {ranged = true, apply = function(player, character, m, args)
    local q = Server.quotes[character]
    Server.quotes[character] = nil
    if not q or q.token ~= args.token or q.mission ~= m.id or q.revision ~= m.revision or q.untilMs < getTimestampMs() then
        return false, 'State'
    end
    return M.deliver(S, m, player, character, q.items, q.token)
end}
gestures.claim = {ranged = true, apply = function(player, character, m)
    return M.claim(S, m, player, character, S.uid('claim'))
end}

-- A refused gesture is logged on the server (MP run 20261115-163137: a claim refused without a trace), then answered.
local function refuse(player, name, character, args, reason, detail)
    log('gesture ' .. name .. ' refused for ' .. tostring(character) .. ' on ' .. tostring(args.mission) .. ': '
        .. tostring(reason) .. (detail and (' (' .. detail .. ')') or ''))
    return reject(player, reason)
end

local function transact(player, character, name, gesture, args)
    local m, why, detail = missionFor(player, character, args, gesture.ranged)
    if not m then return refuse(player, name, character, args, why, detail) end
    if m.revision ~= args.revision then
        return refuse(player, name, character, args, 'State',
            'revision ' .. tostring(args.revision) .. ', mission at ' .. tostring(m.revision))
    end
    local ok, reason = gesture.apply(player, character, m, args)
    if ok == ANSWERED then return end
    if not ok then return refuse(player, name, character, args, reason) end
    S.save()
    publish()
end


-- An empty argument table arrives as nil (SinglePlayerClient.java:126, GameClient.java:1760: args sent only when not
-- empty): the first hello of a new character ({character = nil}) used to be dropped here, so no notebook character
-- was ever created and the histories kept by character stayed empty. nil is read as {}.
-- C21: per-account token buckets {capacity, per second} (CA_RateLimit, MP server only). hello and snapshot rebuild
-- and send the whole projection, rep_admin logs its refusals; every other command shares one bucket. The client polls
-- every 3 s with the notebook open: far below these limits. A dropped command gets no reply.
Server.RATE_LIMITS = {}
Server.RATE_LIMIT_OTHER = {20, 4}

-- E21-T03: registry of the notebook commands on the network module of the core mod (CA_NotebookConfig.MODULE =
-- 'CoreAI'). fn(player, args, character): character is the bound notebook character, nil for an open command (open:
-- served before the identity and session checks: hello, rep_admin). limit: own token bucket, else the shared one. A
-- command no one registered is ignored (no token taken, no reply): the other commands of the module belong to
-- CA_Teams (team, mandate) and CA_Identity (hello, which the notebook owns while it is loaded: Identity.yieldHello).
Server.commands = {}
function Server.registerCommand(name, fn, limit, open)
    Server.commands[name] = {fn = fn, open = open == true}
    Server.RATE_LIMITS[name] = limit
    if name == 'hello' then Identity.yieldHello() end
end

function Server.command(module, command, player, args)
    if module ~= C.MODULE or not player then return end
    local entry = Server.commands[command]
    if not entry then return end
    local limit = Server.RATE_LIMITS[command]
    local bucket = limit and ('carnet.' .. command) or 'carnet'
    limit = limit or Server.RATE_LIMIT_OTHER
    if not RateLimit.allow(player, bucket, limit[1], limit[2]) then return end
    if type(args) ~= 'table' then args = {} end
    if not S.data or S.blocked then return reject(player, 'Storage') end
    if player:isDead() then return reject(player, 'State') end
    M.advance(S.data, playMeter())
    if entry.open then return entry.fn(player, args) end
    local character = Server.bound[player]
    if not character then return reject(player, 'Identity') end
    if args.world ~= S.data.world or args.run ~= S.run then return reject(player, 'Session') end
    scan()
    entry.fn(player, args, character)
end

Server.registerCommand('hello', function(player, args)
    identity(player, args.character)
    scan(); projection(player)
end, {4, 0.5}, true)
Server.registerCommand('rep_admin', function(player) send(player, 'rep_admin', Server.reputationAdmin(player)) end,
    {3, 0.2}, true)
Server.registerCommand('snapshot', function(player) projection(player) end, {6, 1})
Server.registerCommand('select', function(player, args, character)
    if selectTarget(player, character, args) then S.save(); projection(player)
    else projection(player); reject(player, 'Range') end
end)
Server.registerCommand('deselect', function(player, _, character)
    Server.selected[character] = nil; projection(player)
end)
Server.registerCommand('talk', function(player, args, character) talk(player, character, args) end)
Server.registerCommand('note', function(player, args, character)
    local npc = type(args.npc) == 'string' and S.data.npcs[args.npc]
    local known = npc and S.data.characters[character].contacts[npc.id]
    if not known then return reject(player, 'State') end
    if type(args.text) ~= 'string' or #args.text > 2000 then return reject(player, 'Text') end
    -- Multi-line note (E17-T06): line breaks kept, other control characters replaced by a space.
    local note = args.text:gsub('\r\n?', '\n'):gsub('[%c]', function(c) return c == '\n' and c or ' ' end)
    known.note = note
    S.save(); projection(player)
end)
for name, gesture in pairs(gestures) do
    Server.registerCommand(name, function(player, args, character)
        transact(player, character, name, gesture, args)
    end)
end

-- Notebook character of the account named by a server death cause (E04-T07), or nil: connected player of this
-- account, then its identity (CA_Identity, bound on the authority), else its notebook binding. Read only; never a
-- client claim.
function Server.killerCharacter(account)
    if type(account) ~= 'string' or account == '' then return nil end
    local player
    for _, p in ipairs(players()) do if p:getUsername() == account then player = p end end
    if not player then return nil end
    local key = Identity.of(player) or Server.bound[player]
    local record = type(key) == 'string' and S.data.characters[key] or nil
    if not record or record.retired then return nil end
    return key
end

-- 'death' event of CA_NPCProvider: the provider body with this id died. cause (optional, E04-T06) is established on
-- the authority by the engine (its death cause: last hit of a player within 5 s, driver of a vehicle; fire,
-- trap without thrower, unseen death: no killer). E04-T07: a killer who takes part in an active mission of this
-- requester loses Reputation.requesterKilled (Q7), this character only, once per death (eventId
-- <npc>-killed-<character>); team mates are spared; a killer who does not take part is left to npc.memberKilled
-- (reported by the NPC engine). No penalty by proximity, never an accusation relayed from a client.
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
    S.save(); publish()
end

-- E18-T22: npc.memberKilled is reported by the NPC engine itself, which reads the reputation of the core mod directly.

-- E04-T14 (Q17): read-only view of every live character's reputation for an administrator: name, level, trend, last
-- acts (no score, no proof, no account). Access checked at each request on the authority (CA_AdminAccess, debug mode
-- required in solo). Refusal: {ok = false, err = 'denied'} without data.
Server.REP_ADMIN_MAX = 64
function Server.reputationAdmin(player)
    local allowed, why = Access.allowed(player, true)
    if not allowed then
        log('reputation admin view refused for ' .. tostring(player and player:getUsername()) .. ': ' .. tostring(why))
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
    -- E18-T21: personal relations are kept and purged by the NPC engine.
    return removed
end

local function clockRunning()
    for _, m in pairs(S.data.missions) do if m.state == 'active' or m.state == 'offer' then return true end end
    return false
end

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
        if Server.talk then Server.talk.turns(now) end -- E18-T17: initiatives, conversations, incidents (speech)
        for player, character in pairs(Server.bound) do
            local id = Server.selected[character]
            if id and not activeNpc(player, character, id, Speech.SELECT_RANGE) then
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
        -- E21-T04: polls of the mods that use the notebook (Server.addPoll).
        if #watched > 0 then
            for _, poll in ipairs(Server.polls) do
                if poll(S.data, S, watched) then
                    S.save()
                    changed = true
                end
            end
        end
        if Server.talk then Server.talk.poll() end
        -- E09-T03: bounded poll of the vanilla factions (no server event): renames, owners, members, disbands.
        if Teams.sync(false) then changed = true end
        checkAt = now + 1000
    end
    if now >= pruneAt then
        changed = prune(now) or changed
        pruneAt = now + C.PRUNE_INTERVAL_MS
    end
    -- Snapshots are pushed on changes; clients poll only while their notebook is open.
    if changed then S.dirty = true; publish() end
    if now >= saveAt then
        if S.needsSave() or clockRunning() then S.save() end
        saveAt = now + C.SAVE_INTERVAL_MS
    end
    if Server.talk then Server.talk.enrich(now) end
end

local function init(newWorld) -- OnInitGlobalModData arg: always true on a dedicated server (CA_WorldStart)
    if S.data then return end
    if S.init(newWorld == true and WorldStart.isNewWorld(true)) then
        Identity.init(newWorld) -- E18-T03: core registry first (same OnInitGlobalModData argument)
        local now = getTimestampMs()
        saveAt = now + C.SAVE_INTERVAL_MS
        playMeter() -- start of the play clock: nothing counted for the time before the world loaded
        for _, npc in pairs(S.data.npcs) do if npc.enrichState == 'pending' then npc.enrichState = 'needed' end end
        scan()
        Server.attachTalk()
        log('authoritative state ready, NPC provider=' .. tostring(P.active().name)
            .. ', available=' .. tostring(P.available()))
    end
end

-- Contacts and acquaintance of a character, also used by the mods that talk through the notebook (E08-T06).
Server.contact, Server.acquaintance = contact, acquaintance

-- E18-T17: what the notebook adds to the speech of the NPCs (host of the speech engine). ----------------------------

-- E17-T08, E17-T09, E17-T10, E10-T02: fiche of the speaker in the context of a sentence, its offers and their bindings.
local function talkContext(context, npc, character, _, _, group)
    local known = contact(character, npc)
    -- E09-T04: personal relation of the NPC toward this character (labels only) and the real facts it may cite to
    -- change it (short ids; the keys stay on the server), given by the NPC provider (E21-T04).
    local relation, relationBinding = P.relationOffer(npc, character)
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
        if cid and P.hears(player, listener, Speech.HEARING_RANGE) then
            local k = contact(cid, npc)
            k.history[#k.history + 1] = {id = req.id .. '-player', author = S.data.characters[character].name, text = text}
            while #k.history > Speech.MAX_HISTORY do table.remove(k.history, 1) end
        end
    end
    S.save()
end

-- Missions of a reply (CA_MissionTalk).
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
        if cid and P.hears(object, listener, Speech.HEARING_RANGE) then
            local k = contact(cid, npc)
            k.history[#k.history + 1] = {id = req.id, author = npc.name, text = result.text}
            while #k.history > Speech.MAX_HISTORY do table.remove(k.history, 1) end
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
            while #known.history > Speech.MAX_HISTORY do table.remove(known.history, 1) end
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
    session = function() return S.data.world, S.run end,
    fiche = function(id) return S.data.npcs[id] end,
    fiches = function() return S.data.npcs end,
    -- E18-T27: a character knows a fiche (contact of its notebook record): comebacks of the observation triggers.
    knows = function(character, id)
        local record = S.data.characters[character]
        return record ~= nil and type(record.contacts) == 'table' and record.contacts[id] ~= nil
    end,
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
    overheard = function(player, character, seen)
        for _, fn in ipairs(Server.hooks.overheard) do fn(player, character, seen) end
    end,
    callLanguage = function()
        local fn = Server.hooks.callLanguage
        if fn then return fn() end
        return nil
    end,
    claim = function(req)
        for _, fn in ipairs(Server.hooks.claim) do
            local handler = fn(req)
            if handler then return handler end
        end
        return nil
    end,
    talkContext = talkContext,
    talkQueued = talkQueued,
    relationApply = P.relationApply,
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
}

-- Speech engine of the NPC provider (CA_NPCProvider.speech): the notebook is its host. Called once the state of the
-- notebook is ready.
function Server.attachTalk()
    local engine = P.speech()
    if type(engine) ~= 'table' or type(engine.attach) ~= 'function' then return end
    if engine.attach(HOST) then
        Server.talk = engine
        engine.sync()
    else
        log('speech of the NPCs not ready: speech engine state unavailable')
    end
end

-- E18-T05, E21-T04: the common mission engine on the notebook (CA_NotebookGiver: store, NPC provider, giver 'npc' and
-- hooks, attached when it loads); the notebook gives it the loaded bodies of the fiches, its binding and its push.
function Server.attachMissions()
    Giver.objects = function() return Server.objects end
    Giver.bound = function() return Server.bound end
    Giver.publish = publish
end
Server.attachMissions()
Server.init = init

Events.OnInitGlobalModData.Add(init)
Events.OnServerStarted.Add(function() init(false) end)
Events.OnGameStart.Add(function() init(false) end)
Events.OnClientCommand.Add(Server.command)
Events.OnTickEvenPaused.Add(tick)
P.on('death', Server.dead)
P.on('reincarnated', Server.reincarnated)
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
    -- E21-T04: what the mods keep about this character is forgotten by their CA_Identity.onRetire listeners.
    md[IDENTITY_KEY] = nil
    Server.bound[character], Server.selected[id], Server.quotes[id] = nil, nil, nil
    -- E23-T02 (ADR D07): his participation in the missions ends at once; the other participants see it.
    local lost = MissionLoss.died(S.data, id, record)
    S.save()
    if lost > 0 then publish() end
end
Events.OnCharacterDeath.Add(Server.characterDeath)
return Server
