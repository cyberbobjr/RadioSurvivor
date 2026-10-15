if isClient() then return end
--[==[
Internal reputation of RadioSurvivor (E04-T08, E04-T09, E04-T12; design docs/conception/reputation-interne.md).
Authority only (dedicated server or solo): this file is never loaded by an MP client.

One global reputation per notebook character (E00-T01 identity, Q2), kept in the private state of the notebook
(RS_State: S.data.reputation, server file, never a global ModData):
    reputation[<character>] = { score, revision, trend, signs, reasons, gainDay, gainSum, retiredDay }
Every new character starts neutral (score 0); facts recorded before this module (outcomes without `rep`) are never
applied (Q1). The score is never sent to a client nor to the bridge: readers get the level, the trend and the public
reasons only.

Sources (closed list R.ACTIONS, captured at the same points as the chronicle rs.facts, never read from it):
    mission.success / mission.failed / mission.abandoned   RS_Missions.finish, one fact per registered participant
                                                           (same amount for everyone; cancellations change nothing)
    trade.cheated          RS_TradeExchange finish('cheated'), the caller of the passage
    npc.requesterKilled    RS_Carnet_Server.dead (E04-T07): attributed killer who takes part in an active mission of
                           the dead requester, this character only, eventId <npc>-killed-<character>
    npc.memberKilled       RS_Carnet_Server.npcDied (Living Knox fact npcDied, published after the provider 'death'
                           event, LK_Bodies.onZombieDead): attributed killer of a group member, unless the requester
                           rule above already applied to this death; eventId lk-<npc>-g<generation>-memberKilled-<c>
    rescue.success         reserved for E12 (same call)
Nothing comes from a client command or from a sentence.

Rules (E04-T09, RS_Config.Reputation, values of section 9 of the design confirmed by default 2026-10-15):
    score bounded min..max (-100..100), start 0; level bad <= badAt (-20) < neutral < goodAt (20) <= good;
    amounts +5 success, -5 failed / abandoned / cheated, -50 requester killed, -10 member killed, +5 rescue;
    gains capped at dailyGainCap (+10) per character and game day (7 am to 7 am): the surplus is recorded with no
    effect (rep = 'capped'); losses are never capped; no decay over time (Q4);
    trend = sign of the sum of the signs of the last trendFacts (3) acts: up, down, stable;
    reasons = the last `reasons` (5) acts, newest first: { action, reasonKey, reasonArgs, sign, capped }.

Idempotence: R.record writes outcomes[eventId] once and applies the amount in the same Lua call. A replay (double
death event, restart, second finish) finds the entry and does nothing. Outcome fields:
    id, character, action, proposedDelta (amount of the action), proof (server only), day (game day),
    rep ('applied' | 'capped' | 'no_character' | 'retired'), appliedDelta, before, after;
    applied = false, status = 'api_unavailable': state of the optional CharacterReputation service (contract RSREP-1
    section 4, adapter E04-T13), independent from the internal application.
The caller saves the state (S.save, or S.dirty for R.prune) as before.

Purge (R.prune, from the notebook prune pass): outcomes kept keepOutcomeDays (30) game days; a retired character
(death, E00-T02) is no longer read and is dropped with its outcomes retiredPurgeDays (7) game days after R.retire.

Public API (server Lua only):
    R.ACTIONS                                   closed list of actions -> config key of the amount
    R.amount(action) -> number | nil            amount of an action of the closed list
    R.record(state, eventId, character, action, delta, proof, reasonArgs) -> outcome, 'duplicate' | nil | (nil, err)
        delta is a legacy argument: the amount always comes from RS_Config.Reputation by action.
    R.level(character [, state]) -> 'bad' | 'neutral' | 'good' | nil     nil: no live notebook character
    R.trend(character [, state]) -> 'up' | 'down' | 'stable' | nil
    R.reasons(character [, n [, state]]) -> { {action, reasonKey, reasonArgs, sign, capped}, ... } (copies)
    R.projection(character [, state]) -> {available = true, level, trend, reasons, change, today}
                                       | {available = false, reason}     (reasons carry their game day)
    R.change(character [, state]) -> {from, to, day, n} | nil   last change of level (Q9 warning, E04-T04)
    R.publicContext(character [, state]) -> {level, last = {act, about}} | nil   LLM context (E04-T10, Q10)
    R.sensitive(template, offer), R.offerAllowed(level, template, offer)    offers by level (E04-T05, Q11, Q12)
    R.margin(level) -> lowest margin of the smuggler for a level (E04-T11, Q13)
    R.testSetLevel(state, character, level)     test saves in debug mode only (E04-T14)
    R.scoreOf(character [, state]) -> number | nil   server-internal only (tests, admin), never sent
    R.retire(state, character)                  marks the day of the death (purge clock)
    R.prune(state [, today]) -> boolean         purge described above
    R.today() -> game day (1 = first) or nil
    R.descriptor()                              descriptor of the optional CharacterReputation mod (E04-T13)
Console messages in English.
]==]
local Config = require 'RadioSurvivor/RS_Config'
local R = {}

-- Private state of the notebook, required only when a reader passes no state (RS_State is loaded on the authority
-- before any reader runs; kept out of the load-time requires so that RS_Missions loads without it).
local function stateData()
    return require('RadioSurvivor/RS_State').data
end

-- Closed list: action -> key of its amount in RS_Config.Reputation.
R.ACTIONS = {
    ['mission.success'] = 'success',
    ['mission.failed'] = 'failure',
    ['mission.abandoned'] = 'failure',
    ['trade.cheated'] = 'failure',
    ['npc.requesterKilled'] = 'requesterKilled',
    ['npc.memberKilled'] = 'memberKilled',
    ['rescue.success'] = 'rescue',
}

-- Translation key of the reason of each action (IGUI_RS_RepReason_*).
R.REASON_KEYS = {
    ['mission.success'] = 'IGUI_RS_RepReason_MissionSuccess',
    ['mission.failed'] = 'IGUI_RS_RepReason_MissionFailed',
    ['mission.abandoned'] = 'IGUI_RS_RepReason_MissionAbandoned',
    ['trade.cheated'] = 'IGUI_RS_RepReason_TradeCheated',
    ['npc.requesterKilled'] = 'IGUI_RS_RepReason_RequesterKilled',
    ['npc.memberKilled'] = 'IGUI_RS_RepReason_MemberKilled',
    ['rescue.success'] = 'IGUI_RS_RepReason_RescueSuccess',
}

-- Values of section 9 of the design, used when RS_Config lacks a key.
local DEFAULTS = {success = 5, failure = -5, requesterKilled = -50, memberKilled = -10, rescue = 5,
    min = -100, max = 100, start = 0, badAt = -20, goodAt = 20, dailyGainCap = 10, reasons = 5, trendFacts = 3,
    keepOutcomeDays = 30, retiredPurgeDays = 7}

local MAX_ARGS, MAX_ARG_CHARS = 2, 48

local function cfg(key)
    local c = Config.Reputation
    local v = type(c) == 'table' and c[key] or nil
    if type(v) ~= 'number' then v = DEFAULTS[key] end
    return v
end

function R.descriptor()
    if CharacterReputation and type(CharacterReputation.getDescriptor) == 'function' then
        return CharacterReputation.getDescriptor()
    end
    return {status = 'missing', capabilities = {}}
end

function R.amount(action)
    local key = type(action) == 'string' and R.ACTIONS[action] or nil
    if not key then return nil end
    return cfg(key)
end

-- Game day, 1 = first (world age starts at 7 am: a day runs from 7 am to 7 am), or nil without a clock.
function R.today()
    local gt = getGameTime and getGameTime()
    if not gt or not gt.getWorldAgeHours then return nil end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= 'number' or hours ~= hours or hours < 0 then return nil end
    return math.floor(hours / 24) + 1
end

local function liveRecord(state, character)
    local chars = type(state) == 'table' and state.characters or nil
    local record = type(chars) == 'table' and type(character) == 'string' and chars[character] or nil
    if type(record) ~= 'table' then return nil, 'no_character' end
    if record.retired then return nil, 'retired' end
    return record
end

local function entryOf(state, character, create)
    if type(state.reputation) ~= 'table' then
        if not create then return nil end
        state.reputation = {}
    end
    local e = state.reputation[character]
    if not e and create then
        e = {score = cfg('start'), revision = 0, trend = 'stable', signs = {}, reasons = {}, gainDay = -1, gainSum = 0}
        state.reputation[character] = e
    end
    return e
end

local function clamp(v)
    return math.max(cfg('min'), math.min(cfg('max'), v))
end

local function levelOf(score)
    if score <= cfg('badAt') then return 'bad' end
    if score >= cfg('goodAt') then return 'good' end
    return 'neutral'
end

local function trendOf(signs)
    local sum = 0
    for _, s in ipairs(signs) do sum = sum + s end
    if sum > 0 then return 'up' elseif sum < 0 then return 'down' end
    return 'stable'
end

-- Public arguments of a reason: at most MAX_ARGS one-line strings, cut to MAX_ARG_CHARS.
local function cleanArgs(args)
    local out = {}
    if type(args) ~= 'table' then return out end
    for i = 1, MAX_ARGS do
        local v = args[i]
        if type(v) ~= 'string' then break end
        v = string.gsub(v, '[%c<>]', ' ')
        if string.len(v) > MAX_ARG_CHARS then v = string.sub(v, 1, MAX_ARG_CHARS) end
        out[#out + 1] = v
    end
    return out
end

local function copyReason(r)
    local args = {}
    for i, v in ipairs(r.reasonArgs or {}) do args[i] = v end
    return {action = r.action, reasonKey = r.reasonKey, reasonArgs = args, sign = r.sign, capped = r.capped}
end

-- Applies the amount of one new act to a live character. Returns rep status, applied delta, score before, after.
local function apply(state, character, action, amount, day, args)
    local _, why = liveRecord(state, character)
    if why then return why, 0 end
    local e = entryOf(state, character, true)
    local delta = amount
    if delta > 0 then
        local d = day or 0
        if e.gainDay ~= d then e.gainDay, e.gainSum = d, 0 end
        delta = math.min(delta, math.max(0, cfg('dailyGainCap') - e.gainSum))
        e.gainSum = e.gainSum + delta
    end
    local before = e.score
    e.score = clamp(before + delta)
    e.revision = e.revision + 1
    -- Q9 (E04-T04): the last change of level is kept for the notebook (one line, one warning over the character).
    local from, to = levelOf(before), levelOf(e.score)
    if from ~= to then e.change = {from = from, to = to, day = day, n = e.revision} end
    local sign = amount > 0 and 1 or -1
    table.insert(e.signs, sign)
    while #e.signs > cfg('trendFacts') do table.remove(e.signs, 1) end
    e.trend = trendOf(e.signs)
    local capped = delta < amount or nil
    table.insert(e.reasons, 1, {action = action, reasonKey = R.REASON_KEYS[action], reasonArgs = cleanArgs(args),
        sign = sign, capped = capped, day = day})
    while #e.reasons > cfg('reasons') do table.remove(e.reasons) end
    return capped and 'capped' or 'applied', e.score - before, before, e.score
end

function R.record(state, eventId, character, action, delta, proof, reasonArgs)
    if type(state) ~= 'table' or type(eventId) ~= 'string' or eventId == '' then return nil, 'argument' end
    if type(state.outcomes) ~= 'table' then state.outcomes = {} end
    local existing = state.outcomes[eventId]
    if existing then return existing, 'duplicate' end
    local amount = R.amount(action)
    if amount == nil or amount == 0 then
        print('[RS_Reputation] refused unknown action ' .. tostring(action) .. ' (' .. eventId .. ')')
        return nil, 'action'
    end
    local _ = delta -- legacy argument (E04-T03 era); the amount comes from the closed list
    local day = R.today()
    local o = {id = eventId, character = character, action = action, proposedDelta = amount, proof = proof,
        day = day, applied = false, status = 'api_unavailable'}
    state.outcomes[eventId] = o
    o.rep, o.appliedDelta, o.before, o.after = apply(state, character, action, amount, day, reasonArgs)
    return o
end

function R.scoreOf(character, state)
    state = state or stateData()
    if not liveRecord(state, character) then return nil end
    local e = entryOf(state, character, false)
    return e and e.score or cfg('start')
end

function R.level(character, state)
    local score = R.scoreOf(character, state)
    if score == nil then return nil end
    return levelOf(score)
end

function R.trend(character, state)
    state = state or stateData()
    if not liveRecord(state, character) then return nil end
    local e = entryOf(state, character, false)
    return e and e.trend or 'stable'
end

function R.reasons(character, n, state)
    state = state or stateData()
    local out = {}
    if not liveRecord(state, character) then return out end
    local e = entryOf(state, character, false)
    local limit = math.min(type(n) == 'number' and n or cfg('reasons'), cfg('reasons'))
    for i, r in ipairs(e and e.reasons or {}) do
        if i > limit then break end
        out[#out + 1] = copyReason(r)
    end
    return out
end

-- Last change of level of a live character: {from, to, day, n} (copy; n = revision of the act, a stable key for the
-- client warning), or nil when the level never changed.
function R.change(character, state)
    state = state or stateData()
    if not liveRecord(state, character) then return nil end
    local e = entryOf(state, character, false)
    local c = e and e.change
    if type(c) ~= 'table' then return nil end
    return {from = c.from, to = c.to, day = c.day, n = c.n}
end

-- Notebook snapshot field (sent to the player of this character only, RS_Carnet_Server.projection). No number but
-- game days (today, day of each reason and of the last change), translated into words by the client.
function R.projection(character, state)
    state = state or stateData()
    if not liveRecord(state, character) then
        return {available = false, reason = 'IGUI_RS_ReputationUnavailable'}
    end
    local reasons = R.reasons(character, cfg('reasons'), state)
    local e = entryOf(state, character, false)
    for i, r in ipairs(e and e.reasons or {}) do
        if reasons[i] then reasons[i].day = r.day end
    end
    return {available = true, level = R.level(character, state), trend = R.trend(character, state),
        reasons = reasons, change = R.change(character, state), today = R.today()}
end

-- E04-T10 (Q10): what an NPC, a group on the radio or a radio voice knows of a character: its level and its last
-- public act ({act = action of the closed list, about = public name or nil}). Never a score, a proof, an identity or
-- a place. nil without a live notebook character (the bridge then says nothing about it).
function R.publicContext(character, state)
    state = state or stateData()
    if not liveRecord(state, character) then return nil end
    local out = {level = R.level(character, state)}
    local last = R.reasons(character, 1, state)[1]
    if last then out.last = {act = last.action, about = last.reasonArgs[1]} end
    return out
end

-- E04-T05 (Q11, Q12): missions offered to a level. Simple missions (deliver, signal, scout, clear) stay open to every
-- level, so that a bad reputation can be redeemed; sensitive ones (RS_Config.Reputation.sensitive: retrieve_id,
-- recover, and the group supply missions, offer kind 'supply') are closed to a bad reputation only.
local SENSITIVE = {retrieve_id = true, recover = true, supply = true}

function R.sensitive(template, offer)
    local list = type(Config.Reputation) == 'table' and type(Config.Reputation.sensitive) == 'table'
        and Config.Reputation.sensitive or SENSITIVE
    if type(template) == 'string' and list[template] then return true end
    return type(offer) == 'table' and type(offer.kind) == 'string' and list[offer.kind] == true
end

function R.offerAllowed(level, template, offer)
    if level ~= 'bad' then return true end
    return not R.sensitive(template, offer)
end

-- E04-T11 (Q13): lowest margin of the smuggler for a level (good 0.10, neutral 0.25, bad 0.40; RS_Config
-- Reputation.margin), the default of a character without notebook identity being neutral.
local MARGINS = {good = 0.10, neutral = 0.25, bad = 0.40}

function R.margin(level)
    local list = type(Config.Reputation) == 'table' and type(Config.Reputation.margin) == 'table'
        and Config.Reputation.margin or MARGINS
    local v = list[level or 'neutral']
    if type(v) ~= 'number' then v = list.neutral or MARGINS.neutral end
    return v
end

-- E04-T14: test baseline of a live character, for the in-game test suites only: refused outside a test save in
-- debug mode (LivingKnox.API.testAllowed: authority, isDebugEnabled, save rstest*). Score of the level (bad -40,
-- neutral 0, good 40), trend stable (no sign kept), daily gain cap cleared; reasons and last change kept; no outcome:
-- the next real act is counted normally. Returns true, or false and the reason.
local TEST_SCORES = {bad = -40, neutral = 0, good = 40}

function R.testSetLevel(state, character, level)
    local API = LivingKnox and LivingKnox.API
    if type(API) ~= 'table' or type(API.testAllowed) ~= 'function' then return false, 'test API unavailable' end
    local ok, why = API.testAllowed()
    if not ok then
        print('[RS_Reputation] testSetLevel refused: ' .. tostring(why))
        return false, why
    end
    if TEST_SCORES[level] == nil then return false, 'unknown level' end
    state = state or stateData()
    local _, dead = liveRecord(state, character)
    if dead then return false, dead end
    local e = entryOf(state, character, true)
    e.score, e.revision = TEST_SCORES[level], e.revision + 1
    e.signs, e.trend, e.gainDay, e.gainSum = {}, 'stable', -1, 0
    return true
end

-- Death of the character (RS_Carnet_Server.characterDeath): starts the purge clock of its reputation.
function R.retire(state, character)
    if type(state) ~= 'table' or type(character) ~= 'string' then return end
    local e = entryOf(state, character, true)
    if e.retiredDay == nil then e.retiredDay = R.today() or 0 end
end

function R.prune(state, today)
    today = today or R.today()
    if type(state) ~= 'table' or type(today) ~= 'number' then return false end
    local changed, gone, drop = false, {}, {}
    if type(state.reputation) == 'table' then
        for cid, e in pairs(state.reputation) do
            local record = type(state.characters) == 'table' and state.characters[cid] or nil
            if type(record) ~= 'table' or record.retired then
                if type(e.retiredDay) ~= 'number' then e.retiredDay, changed = today, true
                elseif today - e.retiredDay >= cfg('retiredPurgeDays') then gone[#gone + 1] = cid end
            end
        end
        for _, cid in ipairs(gone) do state.reputation[cid] = nil end
    end
    local goneSet = {}
    for _, cid in ipairs(gone) do goneSet[cid] = true end
    if type(state.outcomes) == 'table' then
        for id, o in pairs(state.outcomes) do
            if type(o) ~= 'table' then drop[#drop + 1] = id
            elseif goneSet[o.character] then drop[#drop + 1] = id
            elseif type(o.day) ~= 'number' then o.day, changed = today, true -- fact older than E04-T08: clock starts now
            elseif today - o.day >= cfg('keepOutcomeDays') then drop[#drop + 1] = id end
        end
        for _, id in ipairs(drop) do state.outcomes[id] = nil end
    end
    if #gone > 0 or #drop > 0 then changed = true end
    return changed
end

return R
