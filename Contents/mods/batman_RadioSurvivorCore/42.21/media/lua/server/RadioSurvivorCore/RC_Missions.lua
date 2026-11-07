if isClient() then return end
--[[
RadioSurvivorCore: common mission engine (authority only) and its template `deliver` (E11-T02, moved to the core mod
by E18-T05; the other templates are RC_MissionScout, RC_MissionClear, RC_MissionRecover, RC_MissionRetrieve and
RC_MissionSignal). The engine owns what every mission shares: admissible offers, creation, acceptance, clock and offer
expiry, collective result, write-ahead progress transactions, the common reward lot, pruning, projection, polling of
templates that watch the participants (M.observe) and reports by speech (M.spoken). Catalogue:
RC_MissionConfig.Missions[name] (`entry`; `entry.id` is the offer id seen by the bridge). A saved mission without
`template` is `deliver` (before E11-T02).

Givers (E18-T05, user decision of 2026-11-05: registration and hooks). A mod registers its kind of giver:
    M.registerDonor(kind, { find(state, id) -> record | nil,          giver record of a mission (m.donor, default 'npc')
                            claim(store, m, player, character, token) -> handled, reason | nil   optional reward path
                            observeDeliver(m, player, name, state, store) -> changed }       optional, `deliver` poll
The engine keeps its fields on the giver record, owned by that mod: id, name, mission, missionCount, nextOfferHour.
Reputation (E18-T22): the engine records the fact of each participant of a closed mission in the reputation of the
core mod (RC_Reputation: mission.success, mission.failed, mission.abandoned; not for the cancelled_* results) and
keeps the sensitive offers from a character of bad reputation (RC_Reputation.offerAllowed, E04-T05), for every giver.
A mission world that carries its own `outcomes` table (isolated world of the in-game test fixtures) keeps the facts of
its missions in that table; the state of a game never does (the core mod's file holds them).
Hooks (all optional; none registered: a mission changes no notebook):
    M.addResultListener(fn(state, m, result, character, requesterName))   once per participant of a closed mission
                                                                         (not for the cancelled_* results)
    M.addPruneListener(fn(state, id, m))        a closed mission is dropped
    M.addChangeListener(fn())                   a template changed a mission outside a request (kill, signal seen)
    M.setOfferFilter(fn(character, name, offer) -> boolean)   an admissible offer may be shown to this character
                                                              (after the reputation rule above)
    M.setCharacterName(fn(state, character) -> name)          name kept with a claimed lot
    M.setBinding(fn() -> { [server player] = character })     default: identities of the core mod (RC_Identity)
    M.setKnownMissions(fn(state, character) -> { [id] = true })  missions still listed for a character (E18-T06)
    M.setProvider(provider)                     NPC engine (ids, presence, supplies), default: no NPC engine
    M.useStore(store)                           store { data, save, blocked, dirty } of the templates that save on
                                                their own; default: the private mission state RC_MissionStore
Template interface (M.register(name, template)); observe and reportBySpeech are optional:
    idPrefix                                    mission ids are <npc>-<idPrefix><n>, n counted per NPC
    offer(entry, npc, record, body, character) -> offer | nil
                                                bounded parameters for the bridge `offers` (body: NPC body or nil;
                                                character: notebook character the offer is computed for, or nil)
    create(m, entry, npc, terms) -> false | nil template fields of a new mission (copies); false: no mission created;
                                                terms: the admissible offer just revalidated (M.create), or nil
    check(m, player, payload) -> evidence | nil, reason
                                                server verification of a contribution, before any mutation
    prepare(m, evidence) -> transaction         template fields of the write-ahead marker (kind, ids...)
    apply(m, evidence) -> errorCode | nil, refused
                                                effects outside the state (inventory); an error keeps the marker,
                                                except a refusal before any effect (refused = true, E17-T03): the
                                                marker is removed and the error code returned to the player
    progress(m, evidence) -> count, done        state change of the contribution; done = mission accomplished
    complete(state, m)                          effects of the template at success; the reward lot stays common
    project(m, p)                               template fields of the client projection (copies only)
    context(m, ctx)                             template fields of the bridge context of an open mission
    observe(m, player, name, state, store)      poll of a participant of an active mission (server copy, never a claim)
    reportBySpeech                              true: a report said to the requester is a contribution ('speech')
    reportReady(m) -> boolean                   (with reportBySpeech) the objective is met, checked by the server
                                                (zone visited, count reached, bag deposited, signal seen): the
                                                mission waits "to report" (E11-T13) and succeeds only by M.spoken
Report to the requester (E11-T13, user decision of 2026-10-14): the templates scout, clear, recover and signal never
succeed by themselves. Their objective met, the mission stays 'active' and is projected with toReport = true (the
notebook shows "to report"); it succeeds only when a participant reports to the requester: in person to the NPC
(RS_Carnet_Server: talk request carrying context.reportable, intent report_done chosen by the model and checked again
here, or the notebook button "Report" near the requester, without the bridge), or for a radio voice requester on its
frequency (RS_MissionVoice: action report_mission of the voice's reply). M.spoken is that single entry point: it
refuses a mission whose objective is not met (no claim ever validates anything). The delay keeps running meanwhile
(same rule as scout since E11-T03); a requester who dies first closes it as 'cancelled_dead' (no reputation change).
Requester ("donor"): an NPC fiche of the notebook (state.npcs[m.npc]) or, since E11-T08, a radio voice
(RS_MissionVoice.lua: state.voiceDonors[m.npc], id 'voice:<voice>:<character>', m.donor = 'voice'). Both carry the
fields the engine reads and writes: id, mission, missionCount, nextOfferHour (nextOfferAt before E11-T20).
Game time (E11-T20, user decision of 2026-10-21): remainingMs and offerRemainingMs are play ms (RC_GameClock: real
ms at normal speed, stopped while the game is paused, faster at x2/x3), decreased by M.advance with the play time
measured by the caller; the delay before the next offer is a world age (nextOfferHour, game hours). Saved missions
keep their remainingMs (same unit at normal speed); a saved nextOfferAt (real ms) is converted once by M.offerWait.
closedAt stays real time (notebook retention and ordering, housekeeping only). An unclaimed lot is kept until a world age
(unclaimedUntilHour, UNCLAIMED_RETENTION_HOURS = 7 game days after the success, user decision of 2026-10-21): see
M.prune.
Engine supplies (E17-T03): for an NPC of a provider that defines supplies (RS_NPCProvider.hasSupplies, Living Knox),
`deliver` offers come only from Provider.supplies (real needs of its group); the mission counts value points V
(m.unit = 'value', m.values), each delivery goes through Provider.supplyDeliver with the transaction token as receipt,
and an offer closed by the engine closes the mission as 'cancelled_closed' (no reputation change, like
'cancelled_dead'). Details at the `deliver` template.
]]
local Config = require 'RadioSurvivorCore/RC_MissionConfig'
local Clock = require 'RadioSurvivorCore/RC_GameClock'
local M = {}

-- ---------------------------------------------------------------- givers and hooks (E18-T05)

local donors, donorOrder = {}, {}
local resultListeners, pruneListeners, changeListeners = {}, {}, {}
local offerFilter, characterName, binding, hostStore, knownMissions = nil, nil, nil, nil, nil

-- Engine of NPC bodies seen through the notebook interface (RS_NPCProvider, E17), or no engine at all.
local NO_ENGINE = {
    id = function() return nil end,
    presence = function() return nil end,
    hasSupplies = function() return false end,
    supplies = function() return {} end,
    supplyOpen = function() return nil end,
    supplyDeliver = function() return nil, 'no engine' end,
}
local provider = NO_ENGINE

-- Registering a kind again replaces its giver and keeps its place.
function M.registerDonor(kind, donor)
    if not donors[kind] then donorOrder[#donorOrder + 1] = kind end
    donors[kind] = donor
    return donor
end

function M.donor(kind) return donors[kind] end

local function kindOf(m) return m.donor or 'npc' end

-- E18-T25 (decision of 2026-11-06): a mission is present while the mod of its giver is active: its kind is registered
-- and the giver's optional present(m, state) does not say false (RadioSurvivor: the fiche of an engine NPC needs its
-- engine; state = the engine's store when not given). A mission that
-- is not present is hidden from every list and frozen (no delay counted, no expiry, no poll, never pruned): never
-- erased nor failed by the absence of its mod, found again as it was when the mod is ticked again.
function M.present(m)
    local d = donors[kindOf(m)]
    if d == nil then return false end
    if d.present then
        local store = M.store()
        return d.present(m, type(store) == "table" and store.data or nil) ~= false
    end
    return true
end

local function addOnce(list, fn)
    for _, f in ipairs(list) do
        if f == fn then return fn end
    end
    list[#list + 1] = fn
    return fn
end

function M.addResultListener(fn) return addOnce(resultListeners, fn) end
function M.addPruneListener(fn) return addOnce(pruneListeners, fn) end
function M.addChangeListener(fn) return addOnce(changeListeners, fn) end
function M.setOfferFilter(fn) offerFilter = fn end
function M.setCharacterName(fn) characterName = fn end
function M.setBinding(fn) binding = fn end
function M.setKnownMissions(fn) knownMissions = fn end
function M.setProvider(p) provider = p or NO_ENGINE end
function M.provider() return provider end
function M.useStore(s) hostStore = s end

function M.store()
    return hostStore or require('RadioSurvivorCore/RC_MissionStore')
end

-- Character of each server player, for the templates that count world events (clear, signal).
function M.binding()
    if binding then return binding() or {} end
    return require('RadioSurvivorCore/RC_Identity').bound or {}
end

-- Missions a character still knows besides its own and its invitations (RadioSurvivor's notebook: set of ids), or nil.
function M.knownMissions(state, character)
    if knownMissions then return knownMissions(state, character) end
    return nil
end

-- Name of the requester shown in the lists (E18-T06): the name kept on the mission (radio voice), else the giver's.
function M.requester(state, m)
    if type(m.requesterName) == 'string' then return m.requesterName end
    local donor = M.donorOf(state, m)
    return donor and type(donor.name) == 'string' and donor.name or ''
end

-- A template changed a mission from a world event: the listeners publish it (RadioSurvivor's notebook).
function M.changed()
    for _, fn in ipairs(changeListeners) do fn() end
end

local DEFAULT = 'deliver'
local templates, order = {}, {}

-- Registering again replaces the template and keeps its place in the offer order.
function M.register(name, template)
    if not templates[name] then order[#order + 1] = name end
    templates[name] = template
    return template
end

function M.template(m)
    return templates[m.template or DEFAULT]
end

local function templateForOffer(offerId)
    for _, name in ipairs(order) do
        local entry = Config.Missions[name]
        if entry and entry.id == offerId then return name end
    end
end

-- E11-T20: true while the requester record (NPC fiche or voice donor) waits before its next offer. The wait is a world
-- age (nextOfferHour), never longer than OFFER_COOLDOWN_MS of play from now (world age set back by an admin). A saved
-- nextOfferAt (real ms of getTimestampMs, before E11-T20) is converted once: the real time it had left becomes play
-- time at normal speed (no offer unblocked early, none blocked for good).
function M.offerWait(record)
    if type(record) ~= 'table' then return false end
    local h = Clock.hours()
    if h == nil then return record.nextOfferHour ~= nil or record.nextOfferAt ~= nil end
    if record.nextOfferAt ~= nil then
        local left = (tonumber(record.nextOfferAt) or 0) - getTimestampMs()
        record.nextOfferAt = nil
        record.nextOfferHour = left > 0 and Clock.after(math.min(left, Config.OFFER_COOLDOWN_MS)) or nil
    end
    local wait = record.nextOfferHour
    if type(wait) ~= 'number' then
        record.nextOfferHour = nil
        return false
    end
    if wait <= h then
        record.nextOfferHour = nil
        return false
    end
    local cap = Clock.after(Config.OFFER_COOLDOWN_MS)
    if wait > cap then record.nextOfferHour = cap end
    return true
end

-- Server-configured allocations a giver may offer now, never fabricated by the model or the client (E11-T06:
-- MAX_OFFERS). A bad reputation keeps the sensitive offers from a character (E04-T05, Q11, Q12), then the offer filter
-- (hook) may keep one too; the bridge only sees the offers left. M.create revalidates an accepted offer against this
-- same catalog.
function M.offers(npc, record, body, character)
    if npc.mission or not record or record.hostile ~= false then return {} end
    if M.offerWait(npc) then return {} end
    local catalog, n = {}, 0
    local Rep = require('RadioSurvivorCore/RC_Reputation')
    local level = type(character) == 'string' and Rep.level(character) or nil
    for _, name in ipairs(order) do
        local entry = n < (Config.MAX_OFFERS or 4) and Config.Missions[name]
        local offer = entry and templates[name].offer(entry, npc, record, body, character)
        local shown = offer and Rep.offerAllowed(level, name, offer)
        if shown and (not offerFilter or offerFilter(character, name, offer)) then
            catalog[entry.id], n = offer, n + 1
        end
    end
    return catalog
end

function M.create(state, npc, character, offerId, terms)
    if npc.mission then return state.missions[npc.mission] end
    local name = DEFAULT
    if offerId ~= nil then name = templateForOffer(offerId) end
    local t, c = templates[name], name and Config.Missions[name]
    if not t or not c then return nil end
    -- Each NPC may offer again after a closed mission: ids stay unique per NPC.
    npc.missionCount = (npc.missionCount or 0) + 1
    local m = {id = npc.id .. '-' .. t.idPrefix .. npc.missionCount, npc = npc.id, template = name, offer = c.id,
        titleKey = c.titleKey, state = 'offer', revision = 1,
        durationMs = c.durationMs, remainingMs = c.durationMs, offerRemainingMs = Config.OFFER_TTL_MS,
        participants = {}, invited = {[character] = true},
        rewardType = c.rewardType, rewardCount = c.rewardCount, claimedBy = '', receipts = {}}
    if t.create(m, c, npc, terms) == false then return nil end
    state.missions[m.id], npc.mission = m, m.id
    return m
end

-- Requester record of a mission (giver of its kind first, then the other kinds); nil when it is gone.
function M.donorOf(state, mission)
    local own = donors[kindOf(mission)]
    local record = own and own.find(state, mission.npc)
    if record then return record end
    for _, kind in ipairs(donorOrder) do
        local d = donors[kind]
        if d ~= own then
            record = d.find(state, mission.npc)
            if record then return record end
        end
    end
    return nil
end

-- A closed mission frees its requester for a later offer, after a cooldown of play time (E11-T20). closedAt (real
-- time) only dates the closure for the notebook retention.
local function release(state, mission)
    mission.closedAt = getTimestampMs()
    if mission.state == 'success' then
        local h = Clock.hours()
        mission.unclaimedUntilHour = h and h + Config.UNCLAIMED_RETENTION_HOURS or nil
    end
    local npc = M.donorOf(state, mission)
    if npc and npc.mission == mission.id then
        npc.mission = nil
        npc.nextOfferAt, npc.nextOfferHour = nil, Clock.after(Config.OFFER_COOLDOWN_MS)
    end
end

function M.finish(state, mission, result)
    if mission.state ~= 'active' then return false end
    mission.state, mission.revision = result, mission.revision + 1
    release(state, mission)
    if result == 'success' then
        local t = M.template(mission)
        if t and t.complete then t.complete(state, mission) end
    end
    -- E08-T07: optional listener of closed missions (RS_Carnet_Server: observation mission_done of the requester).
    if M.onFinished then M.onFinished(state, mission, result) end
    -- Cancellations (requester dead, engine offer closed) tell no listener. Otherwise the result listeners hear once
    -- per registered participant, connected or not (RadioSurvivor: reputation fact and notebook trust, E04-T08); the
    -- requester's name (giver record, else the name kept on the mission) is handed to them and to the reputation.
    if string.sub(result, 1, 10) ~= 'cancelled_' then
        local donor = M.donorOf(state, mission)
        local requester = donor and donor.name or mission.requesterName
        local Rep = require('RadioSurvivorCore/RC_Reputation')
        local facts = type(state.outcomes) == 'table' and state or nil
        for character in pairs(mission.participants) do
            -- E04-T08: same amount for every registered participant, connected or not; once per mission (eventId).
            Rep.record(facts, mission.id .. '-' .. character .. '-result', character, 'mission.' .. result, nil,
                {mission = mission.id, result = result}, type(requester) == 'string' and {requester} or nil)
            for _, fn in ipairs(resultListeners) do fn(state, mission, result, character, requester) end
        end
    end
    return true
end

-- Engine supply offers (E17-T03) still open, polled at most every SUPPLY_POLL_MS per mission: an offer closed by the
-- engine (expired in game time, filled by another delivery, supplier gone) closes the mission without penalty.
local SUPPLY_POLL_MS = 10000
local supplyPolled = {}
local function supplyClosed(m)
    if type(m.supply) ~= 'table' or m.transaction then return false end
    local now = getTimestampMs()
    if supplyPolled[m.id] and now - supplyPolled[m.id] < SUPPLY_POLL_MS then return false end
    supplyPolled[m.id] = now
    return provider.supplyOpen(m.supply.ref, m.supply.offer) == false
end

-- elapsedMs: play ms since the previous call (RC_GameClock.meter, E11-T20); negative values are ignored.
function M.advance(state, elapsedMs)
    local changed = false
    elapsedMs = math.max(0, elapsedMs)
    for _, m in pairs(state.missions) do
        if not M.present(m) then -- luacheck: ignore 542 (frozen while the mod of its giver is not active)
        elseif (m.state == 'active' or m.state == 'offer') and supplyClosed(m) then
            if m.state == 'active' then
                changed = M.finish(state, m, 'cancelled_closed') or changed
            else
                m.state, m.revision = 'expired', m.revision + 1
                release(state, m)
                changed = true
            end
        elseif m.state == 'active' then
            m.remainingMs = math.max(0, m.remainingMs - elapsedMs)
            if m.remainingMs <= 0 then changed = M.finish(state, m, 'failed') or changed end
        elseif m.state == 'offer' then
            -- Missions saved before offer expiry existed get a full delay.
            m.offerRemainingMs = math.max(0, (m.offerRemainingMs or Config.OFFER_TTL_MS) - elapsedMs)
            if m.offerRemainingMs <= 0 and not m.transaction then
                m.state, m.revision = 'expired', m.revision + 1
                release(state, m)
                changed = true
            end
        end
    end
    return changed
end

-- True while an unclaimed lot is still kept: until the world age unclaimedUntilHour (7 game days after the success,
-- user decision of 2026-10-21), never further than UNCLAIMED_RETENTION_HOURS from now (world age set back by an
-- admin). A lot saved before that decision (closedAt only, real ms) is converted once: the real time it had left of
-- the former 7 real days becomes game hours at normal speed, capped to 7 game days (no lot dropped early by the
-- change, none kept for weeks). Without game time the lot is kept.
local function keepUnclaimed(m, now)
    local h = Clock.hours()
    if h == nil then return true end
    local cap = h + Config.UNCLAIMED_RETENTION_HOURS
    local due = m.unclaimedUntilHour
    if type(due) ~= 'number' or due ~= due then
        local left = Config.UNCLAIMED_RETENTION_MS - (now - (tonumber(m.closedAt) or now))
        due = h + math.max(0, left) / Clock.msPerHour()
    end
    if due > cap then due = cap end
    m.unclaimedUntilHour = due
    return due > h
end

-- Closed missions are kept for the notebook, then dropped (MISSION_RETENTION_MS, real time); an unclaimed lot stays
-- 7 game days (keepUnclaimed).
function M.prune(state, now)
    local removed = false
    for id, m in pairs(state.missions) do
        local closed = m.state ~= 'offer' and m.state ~= 'active' and not m.transaction
        if closed and not m.closedAt then m.closedAt = now end
        -- A mission without a reward lot (radio voice, E11-T08) has nothing left to claim.
        local unclaimed = m.state == 'success' and m.claimedBy == '' and (m.rewardCount or 0) > 0
        local drop
        if not closed or not M.present(m) then
            drop = false
        elseif unclaimed then
            drop = not keepUnclaimed(m, now)
        else
            drop = now - m.closedAt > Config.MISSION_RETENTION_MS
        end
        if drop then
            state.missions[id] = nil
            for _, fn in ipairs(pruneListeners) do fn(state, id, m) end
            local npc = M.donorOf(state, m)
            if npc and npc.mission == id then npc.mission = nil end
            removed = true
        end
    end
    return removed
end

function M.accept(state, m, character, name)
    if not m or not m.invited[character] or m.transaction or (m.state ~= 'offer' and m.state ~= 'active') then
        return false
    end
    if m.participants[character] then return true end
    if m.state == 'offer' then m.state = 'active' end
    m.participants[character] = {name = name}
    m.revision = m.revision + 1
    return true
end

-- Called from a single server Lua event thread. The contribution is checked before any mutation.
-- Write-ahead marker stays visible and blocks replay if persistence/inventory completion is uncertain.
function M.report(store, m, player, character, payload, token)
    if m.transaction or m.state ~= 'active' or not m.participants[character] then return false, 'State' end
    if m.receipts[token] then return true end
    local t = M.template(m)
    if not t then return false, 'State' end
    local evidence, reason = t.check(m, player, payload)
    if not evidence then return false, reason or 'Items' end
    local transaction = t.prepare(m, evidence)
    transaction.token, transaction.character, transaction.stage = token, character, 'prepared'
    m.transaction = transaction
    if not store.save() then return false, 'Storage' end
    local err, refused = t.apply(m, evidence)
    if err and refused then
        -- Refused before any effect (E17-T03: engine refusal): nothing to reconcile, the marker goes away.
        m.transaction = nil
        store.save()
        return false, err
    end
    if err then m.transaction.error = err; store.save(); return false, 'Recovery' end
    local count, done = t.progress(m, evidence)
    m.receipts[token] = {character = character, count = count}
    m.revision = m.revision + 1
    if done then M.finish(store.data, m, 'success') end
    m.transaction.stage = 'applied'
    if not store.save() then return false, 'Recovery' end
    m.transaction = nil
    if not store.save() then return false, 'Recovery' end
    return true
end

-- Common reward lot of a successful mission, claimed once for the whole group.
function M.claim(store, m, player, character, token)
    -- Reward path of the giver (RadioSurvivor: household surplus of a Living Knox NPC); nil keeps the common lot.
    local giver = donors[kindOf(m)]
    if giver and giver.claim then
        local handled, reason = giver.claim(store, m, player, character, token)
        if handled ~= nil then return handled, reason end
    end
    if m.transaction or m.state ~= 'success' or not m.participants[character] or m.claimedBy ~= ''
            or (m.rewardCount or 0) < 1 then
        return false, 'State'
    end
    local items, ids = {}, {}
    local weight = 0
    for i = 1, m.rewardCount do
        local item = instanceItem(m.rewardType)
        if not item then return false, 'Items' end
        items[i], ids[i] = item, item:getID()
        weight = weight + item:getActualWeight()
    end
    local inv = player:getInventory()
    if inv:getCapacityWeight() + weight > inv:getEffectiveCapacity(player) then return false, 'Capacity' end
    m.transaction = {kind = 'reward', token = token, character = character, ids = ids, stage = 'prepared'}
    if not store.save() then return false, 'Storage' end
    -- Reserve the unique lot before sending any items, never once per participant.
    m.claimedBy = character
    m.claimedName = characterName and characterName(store.data, character) or m.participants[character].name
    m.revision = m.revision + 1
    for _, item in ipairs(items) do
        local ok = pcall(function()
            if not inv:AddItem(item) then error('inventory_add') end
            sendAddItemToContainer(inv, item)
        end)
        if not ok then m.transaction.error = 'inventory_add'; store.save(); return false, 'Recovery' end
    end
    m.transaction.stage = 'applied'
    if not store.save() then return false, 'Recovery' end
    m.transaction = nil
    if not store.save() then return false, 'Recovery' end
    return true
end

function M.projection(m, character)
    -- Clone; never leak server receipts, inventory item IDs or another player's private data.
    local p = {id = m.id, npc = m.npc, titleKey = m.titleKey, state = m.state, revision = m.revision,
        remainingMs = m.remainingMs, durationMs = m.durationMs,
        rewardType = m.rewardType, rewardCount = m.rewardCount, claimedName = m.claimedName or '',
        engaged = m.participants[character] ~= nil, invited = m.invited[character] == true,
        recovery = m.transaction ~= nil, participants = {}}
    -- Radio voice requester (E11-T08): no body to join, nothing to claim; the notebook adapts its page.
    if m.donor == 'voice' then p.donor = 'voice' end
    local t = M.template(m)
    if t then t.project(m, p) end
    -- E11-T13: objective met, the report to the requester is still expected (templates with a report only).
    if t and (t.reportBySpeech or m.donor == 'voice') then p.toReport = M.reportReady(m) end
    for _, member in pairs(m.participants) do p.participants[#p.participants + 1] = member.name end
    table.sort(p.participants)
    return p
end

-- Open mission as told to the bridge (npc_talk context).
function M.context(m)
    local ctx = {state = m.state, remainingMs = m.remainingMs, rewardType = m.rewardType, rewardCount = m.rewardCount}
    local t = M.template(m)
    if t then t.context(m, ctx) end
    -- E11-T13: objective met (server fact), the report is expected (templates with a report only).
    if t and (t.reportBySpeech or m.donor == 'voice') then ctx.toReport = M.reportReady(m) end
    return ctx
end

-- Template `deliver` (M01): bring `quantity` accepted items to the requester, in one or several deliveries.
-- Engine supplies (E17-T03): when the provider defines supplies (provider.hasSupplies), the offer of an NPC fiche
-- is the open supply offer of its group with the lowest reserve (Provider.supplies for the notebook character; none:
-- no `deliver` offer, the static catalogue is never offered for these NPCs). Adaptation V <-> items: the mission counts
-- value points V instead of items (m.unit = 'value'): quantity = V still requested when the offer is accepted,
-- delivered = V counted by the engine, m.values = V of one accepted item. Only the last item may exceed the rest (an
-- item more than needed is refused, 'TooMany', checked before any effect and again by the engine). A delivery is
-- checked against the engine offer (still open: 'SupplyClosed'), the write-ahead marker is saved, then
-- provider.supplyDeliver(ref, offer, { [type] = count }, token, character) raises the reserve ONCE (receipt key =
-- transaction token: a replay is a duplicate); an engine refusal at that point removes the marker (refusal before any
-- effect), then the items are removed. Reward lot = engine reward item at completion (none, or withdrawn by the
-- engine: rewardCount 0), claimed by the common lot mechanism (M.claim).
local Deliver = {idPrefix = 'delivery'}

local SUPPLY_TITLES = {food = 'IGUI_RC_Mission_Supply_food', medical = 'IGUI_RC_Mission_Supply_medical',
    ammo = 'IGUI_RC_Mission_Supply_ammo'}

local function copyMap(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

-- Engine supply offer of an NPC fiche for a character (lowest reserve first), as bridge terms; nil without any.
local function supplyOffer(c, npc, character)
    if type(character) ~= 'string' then return nil end
    local best
    for _, o in ipairs(provider.supplies(npc.incarnation, character)) do
        local valid = type(o) == 'table' and type(o.ref) == 'string' and type(o.offer) == 'string'
            and type(o.need) == 'string' and type(o.remaining) == 'number' and o.remaining >= 1
            and type(o.items) == 'table' and #o.items > 0
        if valid and (not best or (o.level or 0) < (best.level or 0)) then best = o end
    end
    if not best then return nil end
    local accepted, values = {}, {}
    for _, it in ipairs(best.items) do
        if type(it.type) == 'string' and type(it.value) == 'number' and it.value >= 1 then
            accepted[it.type], values[it.type] = true, it.value
        end
    end
    local reward = type(best.reward) == 'table' and best.reward or nil
    return {kind = 'supply', unit = 'value', need = best.need, level = best.level, quantity = best.remaining,
        durationMs = c.durationMs, accepted = accepted, values = values,
        rewardType = reward and reward.type or '', rewardCount = reward and reward.count or 0, noRefund = true,
        supplier = best.ref, supply = best.offer}
end

function Deliver.offer(c, npc, record, body, character)
    -- npc.incarnation: an NPC fiche of the notebook (a radio voice donor has none).
    if npc and npc.incarnation ~= nil and provider.hasSupplies() then return supplyOffer(c, npc, character) end
    return {quantity = c.quantity, durationMs = c.durationMs, accepted = c.accepted,
        rewardType = c.rewardType, rewardCount = c.rewardCount, noRefund = true}
end

function Deliver.create(m, c, npc, terms)
    if type(terms) == 'table' and terms.kind == 'supply' then
        m.quantity, m.delivered, m.unit = terms.quantity, 0, 'value'
        m.accepted, m.values = copyMap(terms.accepted), copyMap(terms.values)
        m.supply = {ref = terms.supplier, offer = terms.supply, need = terms.need}
        m.titleKey = SUPPLY_TITLES[terms.need] or 'IGUI_RC_Mission_Supply'
        m.rewardCount = terms.rewardCount or 0
        m.rewardType = m.rewardCount > 0 and terms.rewardType or c.rewardType
        return
    end
    -- Engine supplies: no mission outside its offers for its NPC fiches.
    if npc and npc.incarnation ~= nil and provider.hasSupplies() then return false end
    m.quantity, m.delivered, m.accepted = c.quantity, 0, {}
    for k, v in pairs(c.accepted) do m.accepted[k] = v end
end

function Deliver.eligible(item, m)
    return item and m.accepted[item:getFullType()] == true and item:getCondition() > 0
        and not item:isFavorite() and not item:isEquipped()
end

function Deliver.checkItems(player, m, ids)
    -- Value missions: every accepted item is worth 1 V at least, so the rest in V bounds the count too.
    if type(ids) ~= 'table' or #ids < 1 or #ids > m.quantity - m.delivered then return nil end
    local found, seen = {}, {}
    local inv = player:getInventory()
    for _, id in ipairs(ids) do
        if type(id) ~= 'number' or id ~= math.floor(id) or seen[id] then return nil end
        seen[id] = true
        local item = inv:getItemWithIDRecursiv(id)
        if not Deliver.eligible(item, m) then return nil end
        found[#found + 1] = item
    end
    return found
end

-- Value V of items for a value mission: total, smallest unit value, { [type] = count }.
function Deliver.value(m, items)
    local total, smallest, counts = 0, nil, {}
    for _, item in ipairs(items) do
        local fullType = item:getFullType()
        local v = (m.values or {})[fullType] or 0
        total = total + v
        if not smallest or v < smallest then smallest = v end
        counts[fullType] = (counts[fullType] or 0) + 1
    end
    return total, smallest or 0, counts
end

function Deliver.voiceReportReady(m) return m.delivered >= m.quantity end

function Deliver.check(m, player, ids)
    if m.donor == 'voice' and ids == 'speech' then
        if not Deliver.voiceReportReady(m) then return nil, 'Items' end
        return {report = true}
    end
    local items = Deliver.checkItems(player, m, ids)
    if not items then return nil, 'Items' end
    local types = {}
    for i, item in ipairs(items) do types[i] = item:getFullType() end
    local e = {ids = ids, items = items, types = types}
    if m.unit == 'value' and type(m.supply) == 'table' then
        local total, smallest, counts = Deliver.value(m, items)
        local rest = m.quantity - m.delivered
        if total > rest and total - smallest >= rest then return nil, 'TooMany' end
        if provider.supplyOpen(m.supply.ref, m.supply.offer) ~= true then return nil, 'SupplyClosed' end
        e.value, e.counts = total, counts
    end
    return e
end

function Deliver.prepare(m, e)
    if e.report then return {kind = "voice_delivery_report"} end
    return {kind = 'delivery', ids = e.ids, types = e.types, before = m.delivered, count = #e.items, value = e.value}
end

function Deliver.apply(m, e)
    if e.report then return end
    if e.counts then
        local tx = m.transaction
        local result = provider.supplyDeliver(m.supply.ref, m.supply.offer, e.counts, tx.token, tx.character)
        if type(result) ~= 'table' then return 'SupplyRefused', true end
        e.result = result
        tx.counted = result.value
    end
    for _, item in ipairs(e.items) do
        local container = item:getContainer()
        local ok = pcall(function()
            container:Remove(item)
            sendRemoveItemFromContainer(container, item)
        end)
        if not ok then return 'inventory_remove' end
    end
end

function Deliver.progress(m, e)
    if e.report then return 0, true end
    -- Completed supplies belong to the requester, stored as a server receipt/escrow.
    -- Do not append to the NPC engine inventory: its own AI could materialize/overwrite it.
    m.supplies = m.supplies or {}
    for _, itemType in ipairs(e.types) do m.supplies[itemType] = (m.supplies[itemType] or 0) + 1 end
    if e.result then
        local counted = math.max(0, math.min(tonumber(e.result.value) or 0, m.quantity - m.delivered))
        m.delivered = m.delivered + counted
        if e.result.completed then
            -- Reward lot of the engine at completion: its item, or none (withdrawn by the engine).
            local reward = e.result.reward
            if type(reward) == 'table' and type(reward.type) == 'string' and (reward.count or 0) > 0 then
                m.rewardType, m.rewardCount = reward.type, reward.count
            else
                m.rewardCount = 0
            end
        end
        return counted, e.result.completed == true or m.delivered >= m.quantity
    end
    m.delivered = m.delivered + #e.items
    return #e.items, m.donor ~= "voice" and m.delivered == m.quantity
end

-- The supplies are already escrowed by each delivery; the reward lot is the engine's.
function Deliver.complete() end

function Deliver.project(m, p)
    if m.donor == 'voice' then
        p.report, p.place = 'radio', m.place
        p.depositMode = m.deposit and m.deposit.mode
        p.depositReady = m.deposit and m.deposit.ready == true
        p.depositCollected = m.delivered >= m.quantity
        if p.engaged and m.mapZone then p.mapZone = copyMap(m.mapZone) end
    end
    p.quantity, p.delivered, p.accepted = m.quantity, m.delivered, {}
    for k, v in pairs(m.accepted) do p.accepted[k] = v end
    if m.unit == 'value' then
        p.unit, p.values = 'value', copyMap(m.values)
        p.need = m.supply and m.supply.need or nil
    end
end

function Deliver.context(m, ctx)
    if m.donor == 'voice' then
        ctx.kind, ctx.place, ctx.report = 'deliver', m.place, 'radio'
        ctx.depositMode = m.deposit and m.deposit.mode or 'box'
        ctx.depositCollected = m.delivered >= m.quantity
        ctx.collectionRule = 'Leave the complete requested goods in the designated box, or a bag containing only '
            .. 'the requested goods on the ground. Everyone must move at least forty tiles away for ten seconds '
            .. 'before collection. Then report by radio.'
    end
    ctx.quantity, ctx.delivered, ctx.accepted = m.quantity, m.delivered, m.accepted
    if m.unit == 'value' then
        ctx.unit, ctx.values = 'value', m.values
        ctx.need = m.supply and m.supply.need or nil
    end
end

-- Poll of the giver (RadioSurvivor's radio voice: deferred, unseen collection of the complete dead drop; never
-- consume goods in front of a player).
function Deliver.observe(m, player, memberName, state, store)
    local giver = donors[kindOf(m)]
    if giver and giver.observeDeliver then return giver.observeDeliver(m, player, memberName, state, store) end
    return false
end

M.register('deliver', Deliver)

-- M01 facades, kept for the server commands and the existing tests.
M.eligible, M.checkItems, M.supplyValue = Deliver.eligible, Deliver.checkItems, Deliver.value
M.deliver = M.report

-- Server poll of the templates that watch their participants (E11-T03). present: list of {player, character} built
-- by the caller from the server copies of the connected players (never from a position sent by a client). Returns
-- true when a mission changed (revision raised). store (E11-T06, optional): RS_State or a double { save } handed to
-- the templates that must save before acting on the world (recover cache).
function M.observe(state, present, store)
    local changed = false
    for _, m in pairs(state.missions) do
        local t = m.state == 'active' and not m.transaction and M.present(m) and M.template(m)
        if t and t.observe then
            for _, entry in ipairs(present) do
                local member = m.participants[entry.character]
                -- state (E11-T06): a template that closes the mission from its poll (recover depot) calls M.finish.
                if member and m.state == 'active' and t.observe(m, entry.player, member.name, state, store) then
                    m.revision, changed = m.revision + 1, true
                end
            end
        end
    end
    return changed
end

-- E11-T13: true when the objective of an active mission is met (server fact) and its report to the requester is
-- still expected; false otherwise (template without report, objective not met, mission closed).
function M.reportReady(m)
    local t = type(m) == 'table' and m.state == 'active' and M.template(m)
    if t and m.donor == 'voice' and t.voiceReportReady then return t.voiceReportReady(m) == true end
    return t and t.reportBySpeech == true and type(t.reportReady) == 'function' and t.reportReady(m) == true or false
end

-- A participant reported to the requester (E11-T13: report_done of the model on an admitted notebook talk, the
-- notebook button "Report" near the requester, or report_mission of a radio voice on its frequency): for a template
-- with reportBySpeech, a contribution checked by the template ('speech' payload: objective met), through the common
-- M.report. Returns M.report's result, or false, 'State' when it is not a report of this mission. One accepted
-- report closes the mission, so the receipt token is per character (a refused report leaves no receipt).
function M.spoken(store, m, player, character)
    local t = m and M.template(m)
    if not t or not (t.reportBySpeech or (m.donor == 'voice' and t.voiceReportReady))
            or m.state ~= 'active' or not m.participants[character] then
        return false, 'State'
    end
    return M.report(store, m, player, character, 'speech', 'speech-' .. character)
end

return M
