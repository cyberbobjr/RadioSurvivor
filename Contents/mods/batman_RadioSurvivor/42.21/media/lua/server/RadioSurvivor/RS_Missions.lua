if isClient() then return end
--[[
Mission engine (authority only) and its templates (E11-T02; E11-T03 `scout` in RS_MissionScout.lua). The engine owns
what every mission shares: admissible offers, creation, acceptance, clock and offer expiry, collective result and
reputation, write-ahead progress transactions, the common reward lot, pruning, projection, polling of templates that
watch the participants (M.observe) and reports by speech (M.spoken). Catalogue: RS_Config.Missions[name] (`entry`;
`entry.id` is the offer id seen by the bridge). A saved mission without `template` is `deliver` (before E11-T02).
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
fields the engine reads and writes: id, mission, missionCount, nextOfferAt.
Engine supplies (E17-T03): for an NPC of a provider that defines supplies (RS_NPCProvider.hasSupplies, Living Knox),
`deliver` offers come only from Provider.supplies (real needs of its group); the mission counts value points V
(m.unit = 'value', m.values), each delivery goes through Provider.supplyDeliver with the transaction token as receipt,
and an offer closed by the engine closes the mission as 'cancelled_closed' (no reputation change, like
'cancelled_dead'). Details at the `deliver` template.
]]
local Config = require 'RadioSurvivor/RS_Config'
local Rep = require 'RadioSurvivor/RS_Reputation'
local P = require 'RadioSurvivor/RS_NPCProvider'
local M = {}

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

-- Server-configured allocations an NPC may offer now, never fabricated by the model or the client (E11-T06: MAX_OFFERS).
-- E04-T05 (Q11, Q12): a character of bad reputation gets the simple missions only (RS_Reputation.offerAllowed); the
-- level is read on the server, the bridge only sees the offers left (and the level in context.reputation, E04-T10).
-- M.create revalidates an accepted offer against this same catalog (RS_Carnet_Server.reply).
function M.offers(npc, record, body, character)
    if npc.mission or not record or record.hostile ~= false then return {} end
    if npc.nextOfferAt and getTimestampMs() < npc.nextOfferAt then return {} end
    local level = type(character) == 'string' and Rep.level(character) or nil
    local catalog, n = {}, 0
    for _, name in ipairs(order) do
        local entry = n < (Config.MAX_OFFERS or 4) and Config.Missions[name]
        local offer = entry and templates[name].offer(entry, npc, record, body, character)
        if offer and Rep.offerAllowed(level, name, offer) then catalog[entry.id], n = offer, n + 1 end
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

-- Requester record of a mission: NPC fiche, or radio voice donor (E11-T08); nil when it is gone.
function M.donorOf(state, mission)
    return state.npcs[mission.npc] or (state.voiceDonors and state.voiceDonors[mission.npc]) or nil
end

-- A closed mission frees its requester for a later offer, after a cooldown.
local function release(state, mission)
    mission.closedAt = getTimestampMs()
    local npc = M.donorOf(state, mission)
    if npc and npc.mission == mission.id then
        npc.mission = nil
        npc.nextOfferAt = mission.closedAt + Config.OFFER_COOLDOWN_MS
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
    -- Cancellations (requester dead, engine offer closed) change no reputation. Otherwise one reputation fact per
    -- registered participant, connected or not, same act and same amount for everyone (E04-T08); the public reason
    -- argument is the requester's name (fiche or radio voice).
    if string.sub(result, 1, 10) ~= 'cancelled_' then
        local delta = result == 'success' and Config.Reputation.success or Config.Reputation.failure
        local donor = M.donorOf(state, mission)
        local requester = donor and donor.name or mission.requesterName
        for character in pairs(mission.participants) do
            local record = state.characters[character]
            local known = record and record.contacts[mission.npc]
            if known then
                known.trust = result == 'success' and 'Favourable' or 'Cautious'
                known.trend = result == 'success' and 'Rising' or 'Falling'
            end
            Rep.record(state, mission.id .. '-' .. character .. '-result', character,
                'mission.' .. result, delta, {mission = mission.id, result = result},
                type(requester) == 'string' and {requester} or nil)
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
    return P.supplyOpen(m.supply.ref, m.supply.offer) == false
end

function M.advance(state, elapsedMs)
    local changed = false
    elapsedMs = math.max(0, elapsedMs)
    for _, m in pairs(state.missions) do
        if (m.state == 'active' or m.state == 'offer') and supplyClosed(m) then
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

-- Closed missions are kept for the notebook, then dropped; an unclaimed lot stays longer.
function M.prune(state, now)
    local removed = false
    for id, m in pairs(state.missions) do
        local closed = m.state ~= 'offer' and m.state ~= 'active' and not m.transaction
        if closed and not m.closedAt then m.closedAt = now end
        -- A mission without a reward lot (radio voice, E11-T08) has nothing left to claim.
        local unclaimed = m.state == 'success' and m.claimedBy == '' and (m.rewardCount or 0) > 0
        local keep = unclaimed and Config.UNCLAIMED_RETENTION_MS or Config.MISSION_RETENTION_MS
        if closed and now - m.closedAt > keep then
            state.missions[id] = nil
            for _, record in pairs(state.characters) do record.knownMissions[id] = nil end
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
    m.claimedName = store.data.characters[character].name
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
    if t and t.reportBySpeech then p.toReport = M.reportReady(m) end
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
    if t and t.reportBySpeech then ctx.toReport = M.reportReady(m) end
    return ctx
end

-- Template `deliver` (M01): bring `quantity` accepted items to the requester, in one or several deliveries.
-- Engine supplies (E17-T03): when the provider defines supplies (RS_NPCProvider.hasSupplies), the offer of an NPC fiche
-- is the open supply offer of its group with the lowest reserve (Provider.supplies for the notebook character; none:
-- no `deliver` offer, the static catalogue is never offered for these NPCs). Adaptation V <-> items: the mission counts
-- value points V instead of items (m.unit = 'value'): quantity = V still requested when the offer is accepted,
-- delivered = V counted by the engine, m.values = V of one accepted item. Only the last item may exceed the rest (an
-- item more than needed is refused, 'TooMany', checked before any effect and again by the engine). A delivery is
-- checked against the engine offer (still open: 'SupplyClosed'), the write-ahead marker is saved, then
-- Provider.supplyDeliver(ref, offer, { [type] = count }, token, character) raises the reserve ONCE (receipt key =
-- transaction token: a replay is a duplicate); an engine refusal at that point removes the marker (refusal before any
-- effect), then the items are removed. Reward lot = engine reward item at completion (none, or withdrawn by the
-- engine: rewardCount 0), claimed by the common lot mechanism (M.claim).
local Deliver = {idPrefix = 'delivery'}

local SUPPLY_TITLES = {food = 'IGUI_RS_Supply_food', medical = 'IGUI_RS_Supply_medical', ammo = 'IGUI_RS_Supply_ammo'}

local function copyMap(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

-- Engine supply offer of an NPC fiche for a character (lowest reserve first), as bridge terms; nil without any.
local function supplyOffer(c, npc, character)
    if type(character) ~= 'string' then return nil end
    local best
    for _, o in ipairs(P.supplies(npc.incarnation, character)) do
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
    if npc and npc.incarnation ~= nil and P.hasSupplies() then return supplyOffer(c, npc, character) end
    return {quantity = c.quantity, durationMs = c.durationMs, accepted = c.accepted,
        rewardType = c.rewardType, rewardCount = c.rewardCount, noRefund = true}
end

function Deliver.create(m, c, npc, terms)
    if type(terms) == 'table' and terms.kind == 'supply' then
        m.quantity, m.delivered, m.unit = terms.quantity, 0, 'value'
        m.accepted, m.values = copyMap(terms.accepted), copyMap(terms.values)
        m.supply = {ref = terms.supplier, offer = terms.supply, need = terms.need}
        m.titleKey = SUPPLY_TITLES[terms.need] or 'IGUI_RS_Supply'
        m.rewardCount = terms.rewardCount or 0
        m.rewardType = m.rewardCount > 0 and terms.rewardType or c.rewardType
        return
    end
    -- Engine supplies: no mission outside its offers for its NPC fiches.
    if npc and npc.incarnation ~= nil and P.hasSupplies() then return false end
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

function Deliver.check(m, player, ids)
    local items = Deliver.checkItems(player, m, ids)
    if not items then return nil, 'Items' end
    local types = {}
    for i, item in ipairs(items) do types[i] = item:getFullType() end
    local e = {ids = ids, items = items, types = types}
    if m.unit == 'value' and type(m.supply) == 'table' then
        local total, smallest, counts = Deliver.value(m, items)
        local rest = m.quantity - m.delivered
        if total > rest and total - smallest >= rest then return nil, 'TooMany' end
        if P.supplyOpen(m.supply.ref, m.supply.offer) ~= true then return nil, 'SupplyClosed' end
        e.value, e.counts = total, counts
    end
    return e
end

function Deliver.prepare(m, e)
    return {kind = 'delivery', ids = e.ids, types = e.types, before = m.delivered, count = #e.items, value = e.value}
end

function Deliver.apply(m, e)
    if e.counts then
        local tx = m.transaction
        local result = P.supplyDeliver(m.supply.ref, m.supply.offer, e.counts, tx.token, tx.character)
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
    return #e.items, m.delivered == m.quantity
end

-- The supplies are already escrowed by each delivery; the reward lot is the engine's.
function Deliver.complete() end

function Deliver.project(m, p)
    p.quantity, p.delivered, p.accepted = m.quantity, m.delivered, {}
    for k, v in pairs(m.accepted) do p.accepted[k] = v end
    if m.unit == 'value' then
        p.unit, p.values = 'value', copyMap(m.values)
        p.need = m.supply and m.supply.need or nil
    end
end

function Deliver.context(m, ctx)
    ctx.quantity, ctx.delivered, ctx.accepted = m.quantity, m.delivered, m.accepted
    if m.unit == 'value' then
        ctx.unit, ctx.values = 'value', m.values
        ctx.need = m.supply and m.supply.need or nil
    end
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
        local t = m.state == 'active' and not m.transaction and M.template(m)
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
    return t and t.reportBySpeech == true and type(t.reportReady) == 'function' and t.reportReady(m) == true or false
end

-- A participant reported to the requester (E11-T13: report_done of the model on an admitted notebook talk, the
-- notebook button "Report" near the requester, or report_mission of a radio voice on its frequency): for a template
-- with reportBySpeech, a contribution checked by the template ('speech' payload: objective met), through the common
-- M.report. Returns M.report's result, or false, 'State' when it is not a report of this mission. One accepted
-- report closes the mission, so the receipt token is per character (a refused report leaves no receipt).
function M.spoken(store, m, player, character)
    local t = m and M.template(m)
    if not t or not t.reportBySpeech or m.state ~= 'active' or not m.participants[character] then
        return false, 'State'
    end
    return M.report(store, m, player, character, 'speech', 'speech-' .. character)
end

return M
