if isClient() then return end
--[[
Living Knox alone: host of the speech of the NPCs when RadioSurvivor is not an active mod (E18-T18, LK_TalkHost lists
the hooks). With RadioSurvivor the notebook is the host and nothing here runs. Authority only.

A sentence said near an NPC (client: LK_TalkView, command "npcSay" of the module "LivingKnox") goes to the bridge with
the context of the NPC (group, role, needs, attitude, relation, reputation) and comes back as a bubble. The bridge keeps
the memory of an NPC; the lines also go to the history of the core mod (RC_History, peer "lk:<id>"), read by the Contacts
tab of the common notebook.

Speakers: one record per NPC spoken to, in the private speech file of Living Knox (LK_Talk, Talk.data):
    speakers = { [lk id] = { id, incarnation, signature, name, clan, groupName, alive, order, revision, personality,
                             agreements, background, enrichState } }
    contacts = { [character] = { [lk id] = { stage, exchanges, firstHour } } }
    known    = { [character] = { [mission id] = true } }   missions listed in the journal of the common notebook
    world                                                  identifier of the requests
The id of a speaker is the Living Knox NPC id, so a mission of an NPC reads "lk-3-<template><n>".

Missions: engine of the core mod on its private state (RC_MissionStore), giver "npc" registered here (RC_MissionTalk:
offer, acceptance and report by speech). Rewards: the common lot, no notebook button here (see the plan).
Observations, initiatives, conversations and incidents do not run alone (E18-T27).
]]
require "LivingKnox/LK_Core"
require "LivingKnox/LK_TalkHost"

local Hearing = require "RadioSurvivorCore/RC_Hearing"
local History = require "RadioSurvivorCore/RC_History"
local Identity = require "RadioSurvivorCore/RC_Identity"
local M = require "RadioSurvivorCore/RC_Missions"
local MissionStore = require "RadioSurvivorCore/RC_MissionStore"
local MissionTalk = require "RadioSurvivorCore/RC_MissionTalk"
local Speech = require "RadioSurvivorCore/RC_SpeechConfig"
local Transport = require "RadioSurvivorCore/RC_Transport"
local WorldStart = require "RadioSurvivorCore/RC_WorldStart"
local playMeter = require("RadioSurvivorCore/RC_GameClock").meter()

local Talk = LivingKnox.Talk

local Alone = LivingKnox.TalkAlone or {}
LivingKnox.TalkAlone = Alone

Alone.MODULE = "LivingKnox"
Alone.CMD_SAY = "npcSay"           -- client -> server: { text, language, channel = "say", npc?, chat? }
Alone.CMD_REFUSED = "talkRefused"  -- server -> client: { reason }
Alone.CMD_SPEECH = "talkSpeech"    -- server -> client: { npc, text }
Alone.CMD_OFFER = "talkOffer"      -- server -> client: { mission }
Alone.PASS_MS = 1000
Alone.started = Alone.started or false

local function log(msg) print("[LK_TalkAlone] " .. tostring(msg)) end

local function send(player, command, args)
    if isServer() then
        sendServerCommand(player, Alone.MODULE, command, args)
    elseif LivingKnox.TalkView then
        LivingKnox.TalkView.receive(command, args)
    end
end

local function peer(npc) return "lk:" .. npc.id end

local function players()
    local out = {}
    for player in pairs(Identity.bound) do out[#out + 1] = player end
    return out
end

local function bound() return Identity.bound end

local function displayName(player)
    local d = player:getDescriptor()
    if d == nil then return player:getUsername() or "Survivor" end
    return Talk.oneLine(tostring(d:getForename()) .. " " .. tostring(d:getSurname()))
end

local function playerOf(character)
    for player, cid in pairs(Identity.bound) do
        if cid == character then return player end
    end
    return nil
end

local function characterName(character)
    local player = playerOf(character)
    return player and displayName(player) or nil
end

-- Provider of the speech: the Living Knox functions, and what RS_NPCProvider adds around them with RadioSurvivor.
local function makeProvider()
    local base = LivingKnox.NpcProvider
    return setmetatable({ near = Hearing.near, hears = Hearing.hears, personality = Hearing.personality,
        hasSupplies = function() return base.available() end }, { __index = base })
end

-- Observations stay with RadioSurvivor until E18-T27: an NPC alone has none.
local NO_OBSERVATIONS = { field = function() return nil end, list = function() return {} end, MAX_CHAIN = 0 }

-- Speakers ----------------------------------------------------------------------------------------------------------

local function find(id)
    local data = Talk.data
    return data and data.speakers[id] or nil
end

local function fiche(id)
    local npc = find(id)
    if npc and npc.alive and not Alone.provider.npc(id) then npc.alive, Talk.dirty = false, true end
    return npc
end

local function ensure(id)
    local record = Talk.data and Alone.provider.npc(id)
    if not record then return nil end
    local npc = find(id)
    if not npc then
        npc = { id = id, incarnation = id, signature = record.signature, name = Talk.oneLine(record.name or "Survivor"),
            revision = 1, order = 0, alive = true, personality = Hearing.personality(record.signature),
            agreements = {}, background = "", enrichState = "idle" }
        Talk.data.speakers[id], Talk.dirty = npc, true
    end
    npc.clan, npc.groupName = tostring(record.group or ""), Talk.oneLine(record.groupName or "")
    return npc
end

local function contact(character, npc)
    local data = Talk.data
    data.contacts[character] = data.contacts[character] or {}
    local known = data.contacts[character][npc.id]
    if not known then
        known = { stage = "stranger", exchanges = 0 }
        data.contacts[character][npc.id], Talk.dirty = known, true
        if npc.enrichState == "idle" then npc.enrichState = "needed" end
    end
    return known
end

local function line(character, npc, id, author, text)
    History.append(character, peer(npc), { id = id, author = author, text = text }, Speech.MAX_HISTORY)
end

-- Host hooks --------------------------------------------------------------------------------------------------------

local function catalog(npc, character)
    return M.offers(npc, Alone.provider.npc(npc.incarnation), Alone.provider.objects()[npc.id], character)
end

local function talkContext(context, npc, character, _, _, group)
    local known = contact(character, npc)
    local relation, relationBinding = LivingKnox.API.relationOffer(npc.id, character, {})
    context.relation = relation
    -- E17-T08: a stranger never learns the group nor its home.
    context.stage = MissionTalk.acquaintance(MissionStore.data.missions, character, npc, known)
    local g = context.group
    if g and context.stage == "stranger" then context.group = { member = g.member, role = g.role, attitude = g.attitude } end
    local offers, isBound = MissionTalk.context(context, MissionStore.data, npc, character, group, function()
        return catalog(npc, character)
    end)
    return offers, isBound, relationBinding
end

local function talkQueued(req, player, npc, character, text)
    local author = characterName(character) or "Survivor"
    for _, listener in ipairs(players()) do
        if Hearing.hears(player, listener, Speech.HEARING_RANGE) then
            line(Identity.bound[listener], npc, req.id .. "-player", author, text)
        end
    end
end

local function know(character, mission)
    local data = Talk.data
    data.known[character] = data.known[character] or {}
    data.known[character][mission], Talk.dirty = true, true
end

local function accept(req, result, npc)
    local m = MissionTalk.acceptance(MissionStore.data, req, result, npc, characterName(req.character))
    if m then know(req.character, m.id) end
    return m
end

local function talkActions(req, result, npc, binding, ignored)
    return MissionTalk.actions({ state = MissionStore.data, store = MissionStore, bound = bound, catalog = catalog,
        collectiveCheck = Talk.collectiveCheck, accept = accept }, req, result, npc, binding, ignored)
end

-- Listeners of a reply: the line goes to their history; one more answered exchange of the speaking character, the
-- first one dates the first meeting.
local function heard(req, result, npc, object, outcome)
    local audiences = {}
    for _, listener in ipairs(players()) do
        if Hearing.hears(object, listener, Speech.HEARING_RANGE) then
            local cid = Identity.bound[listener]
            line(cid, npc, req.id, npc.name, result.text)
            if outcome.offer then know(cid, outcome.offer.id) end
            audiences[#audiences + 1] = listener
        end
    end
    local known = contact(req.character, npc)
    known.exchanges = (known.exchanges or 0) + 1
    if type(known.firstHour) ~= "number" then known.firstHour = getGameTime():getWorldAgeHours() end
    Talk.dirty = true
    return audiences
end

local function speech(listeners, _, result, npc)
    for _, listener in ipairs(listeners) do
        send(listener, Alone.CMD_SPEECH, { npc = npc.id, text = result.text })
    end
end

local function nothing() end

local function makeHost(provider)
    return {
        provider = provider,
        observations = NO_OBSERVATIONS,
        session = function() return Talk.data.world, Alone.run end,
        fiche = fiche,
        fiches = function() return Talk.data.speakers end,
        find = find,
        ensure = ensure,
        objects = function() return provider.objects() end,
        bound = bound,
        players = players,
        scan = nothing,
        characterName = characterName,
        save = function() return MissionStore.save() end,
        publish = nothing,
        reject = function(character, reason)
            local player = playerOf(character)
            if player then send(player, Alone.CMD_REFUSED, { reason = reason }) end
        end,
        remember = function(npc, id, text, listeners)
            for _, p in ipairs(listeners) do
                local cid = Identity.bound[p]
                if cid and History.find(cid, peer(npc)) then line(cid, npc, id, npc.name, text) end
            end
        end,
        contactedGroups = function() return {} end,
        overheard = nothing,
        callLanguage = nothing,
        claim = nothing,
        talkContext = talkContext,
        talkQueued = talkQueued,
        relationApply = function(npc, character, binding, dir, fact)
            return LivingKnox.API.relationApply(npc.id, character, binding, dir, fact, {})
        end,
        talkActions = talkActions,
        heard = heard,
        speech = speech,
        offered = function(m, character)
            local player = playerOf(character)
            if player then send(player, Alone.CMD_OFFER, { mission = m.id }) end
        end,
        incidentDecided = nothing,
    }
end

-- Nearest loaded NPC a player can talk to, or the one asked when it is near.
local function speakerNear(player, wanted)
    local objects = Alone.provider.objects()
    if wanted ~= nil then
        return Hearing.near(player, objects[wanted], Speech.SELECT_RANGE) and wanted or nil
    end
    local nearest, distance = nil, nil
    for id, body in pairs(objects) do
        if Hearing.near(player, body, Speech.SELECT_RANGE) then
            local dx, dy = body:getX() - player:getX(), body:getY() - player:getY()
            local d = dx * dx + dy * dy
            if not distance or d < distance then nearest, distance = id, d end
        end
    end
    return nearest
end

-- A sentence of a player. args.chat: said in the chat, not addressed to an NPC: nobody near is not an error.
function Alone.say(player, args)
    if not Alone.started or type(args) ~= "table" then return nil, "Bridge" end
    local chat = args.chat == true
    -- The hello of a client may arrive before its server player exists: the authority binds it here.
    local character = Identity.bind(player)
    if not character then return nil, "Bridge" end
    local id = speakerNear(player, type(args.npc) == "string" and args.npc or nil)
    local npc = id and ensure(id) or nil
    if not npc or not npc.alive then
        if not chat then send(player, Alone.CMD_REFUSED, { reason = "Range" }) end
        return nil, "Range"
    end
    local req, reason = Talk.speak(player, character, npc, args)
    if not req then
        send(player, Alone.CMD_REFUSED, { reason = reason })
        return nil, reason
    end
    return req
end

function Alone.onClientCommand(module, command, player, args)
    if module == Alone.MODULE and command == Alone.CMD_SAY then Alone.say(player, args) end
end

-- One pass of the authority: clock and watch of the missions, answers of the bridge, background of the speakers.
function Alone.pass(now)
    if MissionStore.data == nil or MissionStore.blocked then return end
    local changed = M.advance(MissionStore.data, playMeter())
    local watched = {}
    for player, character in pairs(Identity.bound) do watched[#watched + 1] = { player = player, character = character } end
    if #watched > 0 and M.observe(MissionStore.data, watched, MissionStore) then changed = true end
    if M.prune(MissionStore.data, now) then changed = true end
    if changed then MissionStore.save() end
    Talk.poll()
    Talk.enrich(now)
end

function Alone.start(newWorld)
    if Alone.started or LivingKnox.radioSurvivorActive() then return false end
    if LivingKnox.NpcProvider == nil or not LivingKnox.Config.isEnabled() then return false end
    if not MissionStore.init(WorldStart.isNewWorld(newWorld == true)) then
        log("missions state unavailable: speech of the NPCs not started")
        return false
    end
    local provider = makeProvider()
    Alone.provider = provider
    M.setProvider(provider)
    M.registerDonor("npc", { find = function(_, id) return find(id) end })
    M.setCharacterName(function(_, character) return characterName(character) end)
    M.setKnownMissions(function(_, character) return Talk.data and Talk.data.known[character] or nil end)
    M.addPruneListener(function(_, id)
        for _, list in pairs(Talk.data and Talk.data.known or {}) do list[id] = nil end
    end)
    if not Talk.attach(makeHost(provider)) then
        log("speech state unavailable: speech of the NPCs not started")
        return false
    end
    local data = Talk.data
    data.speakers, data.contacts, data.known = data.speakers or {}, data.contacts or {}, data.known or {}
    if not data.world then data.world, Talk.dirty = "lk-" .. getTimestampMs() .. "-" .. ZombRand(1000000), true end
    Alone.run = "lk" .. getTimestampMs()
    Transport.session = Alone.run
    Talk.sync()
    Alone.started = true
    log("speech of the NPCs started, world " .. tostring(data.world))
    return true
end

if not Alone.subscribed then
    Alone.subscribed = true
    local nextPass = 0
    LivingKnox.subscribe("OnInitGlobalModData", "TalkAlone.start", function(newWorld) Alone.start(newWorld) end)
    LivingKnox.subscribe("OnClientCommand", "TalkAlone.command", Alone.onClientCommand)
    LivingKnox.subscribe("OnTick", "TalkAlone.pass", function()
        if not Alone.started then return end
        local now = getTimestampMs()
        if now >= nextPass then
            nextPass = now + Alone.PASS_MS
            Alone.pass(now)
        end
    end)
end

return Alone
