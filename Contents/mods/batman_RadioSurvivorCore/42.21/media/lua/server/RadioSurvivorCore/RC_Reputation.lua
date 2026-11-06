if isClient() then return end
--[==[
RadioSurvivorCore: reputation of the player characters, kept by the core mod (E18-T22, user decision of 2026-11-06;
moved from RadioSurvivor's RS_Reputation, rules unchanged: E04-T08, E04-T09, E04-T12, design
docs/annexes/conception/reputation-interne.md). Authority only (dedicated server or solo): never loaded by an MP
client. One reputation per character (RC_Identity), read the same way by the radio voices (RadioSurvivor) and by the
NPCs (Living Knox); each mod reports its own facts.

Private state, two slot files written in turn (RC_SlotFile): Zomboid/Lua/batman_RadioSurvivorCore/reputation-<hex of
"mode/world">-<0|1>.txt, header RCREP1, never a global ModData:
    data = { schema = 1, reputation = { [character] = entry }, outcomes = { [eventId] = outcome } }
    entry = { score, revision, trend, signs, reasons, gainDay, gainSum, retiredDay, change }
Every new character starts neutral (score 0). The score is never sent to a client nor to the bridge: readers get the
level, the trend and the public reasons only.

Sources (closed list R.ACTIONS, nothing from a client command or from a sentence):
    mission.success / mission.failed / mission.abandoned   RC_Missions.finish, one fact per registered participant
                                                           (same amount for everyone; cancellations change nothing)
    trade.cheated          RadioSurvivor (RS_TradeExchange finish 'cheated'), the caller of the passage
    npc.requesterKilled    RadioSurvivor (RS_Carnet_Server.dead, E04-T07): attributed killer who takes part in an
                           active mission of the dead requester; proof.body = id of the dead body
    npc.memberKilled       Living Knox (LK_Reputation, fact npcDied): attributed killer of a group member, unless
                           npc.requesterKilled already charged this death to this character (R.chargedFor)
    rescue.success         reserved for E12 (same call)

Rules (RC_ReputationConfig, values of section 9 of the design):
    score bounded min..max (-100..100), start 0; level bad <= badAt (-20) < neutral < goodAt (20) <= good;
    amounts +5 success, -5 failed / abandoned / cheated, -50 requester killed, -10 member killed, +5 rescue;
    gains capped at dailyGainCap (+10) per character and game day (7 am to 7 am): the surplus is recorded with no
    effect (rep = 'capped'); losses are never capped; no decay over time (Q4);
    trend = sign of the sum of the signs of the last trendFacts (3) acts: up, down, stable;
    reasons = the last `reasons` (5) acts, newest first: { action, reasonArgs, sign, capped, day }. The text of a
    reason belongs to the mod that shows it (RadioSurvivor's notebook: IGUI_RS_RepReason_<action>).

Idempotence: R.record writes outcomes[eventId] once and applies the amount in the same Lua call, then saves. A
replay (double death event, restart, second finish) finds the entry and does nothing. Outcome fields:
    id, character, action, proposedDelta (amount of the action), proof (server only), day (game day),
    rep ('applied' | 'capped' | 'no_character' | 'retired'), appliedDelta, before, after;
    applied = false, status = 'api_unavailable': state of the optional CharacterReputation service (contract RSREP-1
    section 4, adapter E04-T13), independent from the internal application.

A living character is an identity of RC_Identity that is not retired, or, for a state that carries its own
`characters` records (isolated world of the in-game test fixtures), a record that is not retired (R.setLiveness
replaces the rule, tests only).
Death of a character (RC_Identity retire listener, R.onRetire): the purge clock starts. Purge (R.prune, at start and
every game day, R.everyDay; both subscribed by RC_ReputationEvents): outcomes kept keepOutcomeDays (30) game days; a
retired character is no longer read and is dropped with its outcomes retiredPurgeDays (7) game days after its death.

Games saved before the split (decision D08 of adr-separation-mods.md): RadioSurvivor's notebook hands its
`reputation` and `outcomes` once (R.adopt); an entry already in this file is never replaced, so a second hand-over
changes nothing. Storage blocked (a file exists but no slot can be read, or a newer schema): nothing is written.

Public API (server Lua only). `state` is optional everywhere: the data table above, R.data by default.
    R.ACTIONS                                   closed list of actions -> config key of the amount
    R.amount(action) -> number | nil            amount of an action of the closed list
    R.record(state, eventId, character, action, delta, proof, reasonArgs) -> outcome, 'duplicate' | nil | (nil, err)
        delta is a legacy argument: the amount always comes from RC_ReputationConfig by action.
    R.chargedFor(body, character [, state]) -> boolean   npc.requesterKilled already recorded for this dead body
    R.level(character [, state]) -> 'bad' | 'neutral' | 'good' | nil     nil: no living character
    R.trend(character [, state]) -> 'up' | 'down' | 'stable' | nil
    R.reasons(character [, n [, state]]) -> { {action, reasonArgs, sign, capped}, ... } (copies)
    R.projection(character [, state]) -> {available = true, level, trend, reasons, change, today}
                                       | {available = false}     (reasons carry their game day)
    R.change(character [, state]) -> {from, to, day, n} | nil   last change of level (Q9 warning, E04-T04)
    R.publicContext(character [, state]) -> {level, last = {act, about}} | nil   LLM context (E04-T10, Q10)
    R.sensitive(template, offer), R.offerAllowed(level, template, offer)    offers by level (E04-T05, Q11, Q12)
    R.testSetLevel(state, character, level)     test saves in debug mode only (E04-T14)
    R.scoreOf(character [, state]) -> number | nil   server-internal only (tests, admin), never sent
    R.retire(state, character)                  marks the day of the death (purge clock)
    R.prune(state [, today]) -> boolean         purge described above
    R.today() -> game day (1 = first) or nil
    R.descriptor()                              descriptor of the optional CharacterReputation mod (E04-T13)
    R.init(newWorld), R.ensure(), R.adopt(legacy), R.save(), R.useData(data) (tests)
Console messages in English.
]==]
local Config = require 'RadioSurvivorCore/RC_ReputationConfig'
local SlotFile = require 'RadioSurvivorCore/RC_SlotFile'
-- Identity and world start subscribe to engine events when loaded: required at call time (benches load this file
-- alone). Engine events of this module: RC_ReputationEvents.
local function Identity() return require('RadioSurvivorCore/RC_Identity') end

local R = RC_Reputation or {}
RC_Reputation = R

R.DIR = 'batman_RadioSurvivorCore/'
R.HEADER = 'RCREP1'
R.SCHEMA = 1
R.store = R.store or { seq = 0, base = nil, blocked = false }

local function log(msg)
    print('[RadioSurvivorCore] reputation: ' .. tostring(msg))
end

-- Closed list: action -> key of its amount in RC_ReputationConfig.
R.ACTIONS = {
    ['mission.success'] = 'success',
    ['mission.failed'] = 'failure',
    ['mission.abandoned'] = 'failure',
    ['trade.cheated'] = 'failure',
    ['npc.requesterKilled'] = 'requesterKilled',
    ['npc.memberKilled'] = 'memberKilled',
    ['rescue.success'] = 'rescue',
}

-- Values of section 9 of the design, used when the configuration lacks a key.
local DEFAULTS = {success = 5, failure = -5, requesterKilled = -50, memberKilled = -10, rescue = 5,
    min = -100, max = 100, start = 0, badAt = -20, goodAt = 20, dailyGainCap = 10, reasons = 5, trendFacts = 3,
    keepOutcomeDays = 30, retiredPurgeDays = 7}

local MAX_ARGS, MAX_ARG_CHARS = 2, 48

local function cfg(key)
    local v = Config[key]
    if type(v) ~= 'number' then v = DEFAULTS[key] end
    return v
end

local function fresh()
    return {schema = R.SCHEMA, reputation = {}, outcomes = {}}
end

-- Storage ---------------------------------------------------------------------------------------------------------

function R.init(newWorld)
    local st = R.store
    if R.data ~= nil or st.blocked then return R.data ~= nil end
    st.base = SlotFile.worldBase(R.DIR, 'reputation')
    if require('RadioSurvivorCore/RC_WorldStart').isNewWorld(newWorld == true) then
        R.data, st.seq = fresh(), 0
        return R.save()
    end
    local best, broken = SlotFile.read(st.base, R.HEADER)
    st.seq = best and best.seq or 0
    if best then
        local data = best.data
        if type(data.schema) ~= 'number' or data.schema > R.SCHEMA then
            st.blocked = true
            log('STORAGE BLOCKED: reputation written by a newer schema; preserve files for recovery')
            return false
        end
        if type(data.reputation) ~= 'table' then data.reputation = {} end
        if type(data.outcomes) ~= 'table' then data.outcomes = {} end
        R.data = data
    elseif broken then
        st.blocked = true
        log('STORAGE BLOCKED: both reputation slots invalid; preserve files for recovery')
        return false
    else
        R.data = fresh()
    end
    R.prune(R.data)
    return true
end

-- True when the state is loaded (loaded now if the world exists and OnInitGlobalModData was missed).
function R.ensure()
    if R.data ~= nil then return true end
    if R.store.blocked or getWorld == nil or getWorld() == nil then return false end
    return R.init(false)
end

function R.save()
    local st = R.store
    if st.blocked or not R.data then return false end
    if st.base == nil then return true end -- data handed by a test (R.useData): nothing to write
    local ok, why = SlotFile.write(st.base, R.HEADER, st.seq + 1, R.data)
    if not ok then
        log('STORAGE WRITE FAILED (' .. tostring(why) .. '); kept in memory, retried at the next save')
        return false
    end
    st.seq = st.seq + 1
    return true
end

-- Tests: work on this data table, never on a file.
function R.useData(data)
    R.data, R.store = data, {seq = 0, base = nil, blocked = false}
end

-- Hand-over of a game saved before the split: legacy = { reputation = {...}, outcomes = {...} } of the notebook.
-- Entries already here win. Returns the number of entries taken over (saved when > 0), or nil when blocked.
function R.adopt(legacy)
    if not R.ensure() then return nil end
    local n = 0
    if type(legacy) == 'table' then
        for _, field in ipairs({'reputation', 'outcomes'}) do
            for k, v in pairs(type(legacy[field]) == 'table' and legacy[field] or {}) do
                if type(k) == 'string' and type(v) == 'table' and R.data[field][k] == nil then
                    R.data[field][k] = v
                    n = n + 1
                end
            end
        end
    end
    if n > 0 then
        if not R.save() then return nil end
        log('taken over ' .. n .. ' entr' .. (n == 1 and 'y' or 'ies') .. ' of a game saved before the split')
    end
    return n
end

local function dataOf(state)
    if state ~= nil then return state end
    R.ensure()
    return R.data
end

-- Rules -----------------------------------------------------------------------------------------------------------

-- A state handed by the caller that carries its own `characters` records (isolated world of the in-game test fixtures)
-- decides who lives; otherwise the identity registry of the core mod does.
local function identityLiveness(character, state)
    local r
    if type(state) == 'table' and type(state.characters) == 'table' then r = state.characters[character]
    else r = Identity().record(character) end
    if type(r) ~= 'table' then return 'no_character' end
    if r.retired then return 'retired' end
    return nil
end
local liveness = identityLiveness

-- Tests: fn(character, state) -> nil when living, else 'no_character' | 'retired'; nil restores RC_Identity.
function R.setLiveness(fn)
    liveness = fn or identityLiveness
end

local function live(state, character)
    if type(state) ~= 'table' or type(character) ~= 'string' then return false, 'no_character' end
    local why = liveness(character, state)
    if why then return false, why end
    return true
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

-- Copy of a kept reason (a reason saved by RadioSurvivor before the split also holds a reasonKey: not returned).
local function copyReason(r)
    local args = {}
    for i, v in ipairs(r.reasonArgs or {}) do args[i] = v end
    return {action = r.action, reasonArgs = args, sign = r.sign, capped = r.capped}
end

-- Applies the amount of one new act to a living character. Returns rep status, applied delta, score before, after.
local function apply(state, character, action, amount, day, args)
    local ok, why = live(state, character)
    if not ok then return why, 0 end
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
    table.insert(e.reasons, 1, {action = action, reasonArgs = cleanArgs(args), sign = sign, capped = capped,
        day = day})
    while #e.reasons > cfg('reasons') do table.remove(e.reasons) end
    return capped and 'capped' or 'applied', e.score - before, before, e.score
end

function R.record(state, eventId, character, action, delta, proof, reasonArgs)
    local own = state == nil
    state = dataOf(state)
    if type(state) ~= 'table' or type(eventId) ~= 'string' or eventId == '' then return nil, 'argument' end
    if type(state.outcomes) ~= 'table' then state.outcomes = {} end
    local existing = state.outcomes[eventId]
    if existing then return existing, 'duplicate' end
    local amount = R.amount(action)
    if amount == nil or amount == 0 then
        print('[RadioSurvivorCore] reputation: refused unknown action ' .. tostring(action) .. ' (' .. eventId .. ')')
        return nil, 'action'
    end
    local _ = delta -- legacy argument (E04-T03 era); the amount comes from the closed list
    local day = R.today()
    local o = {id = eventId, character = character, action = action, proposedDelta = amount, proof = proof,
        day = day, applied = false, status = 'api_unavailable'}
    state.outcomes[eventId] = o
    o.rep, o.appliedDelta, o.before, o.after = apply(state, character, action, amount, day, reasonArgs)
    if own or state == R.data then R.save() end
    return o
end

-- npc.requesterKilled already recorded for the death of this body and this character (Living Knox then does not
-- add npc.memberKilled for the same death).
function R.chargedFor(body, character, state)
    state = dataOf(state)
    if type(state) ~= 'table' or type(state.outcomes) ~= 'table' or body == nil then return false end
    for _, o in pairs(state.outcomes) do
        if type(o) == 'table' and o.action == 'npc.requesterKilled' and o.character == character
            and type(o.proof) == 'table' and o.proof.body == body then
            return true
        end
    end
    return false
end

function R.scoreOf(character, state)
    state = dataOf(state)
    if not live(state, character) then return nil end
    local e = entryOf(state, character, false)
    return e and e.score or cfg('start')
end

function R.level(character, state)
    local score = R.scoreOf(character, state)
    if score == nil then return nil end
    return levelOf(score)
end

function R.trend(character, state)
    state = dataOf(state)
    if not live(state, character) then return nil end
    local e = entryOf(state, character, false)
    return e and e.trend or 'stable'
end

function R.reasons(character, n, state)
    state = dataOf(state)
    local out = {}
    if not live(state, character) then return out end
    local e = entryOf(state, character, false)
    local limit = math.min(type(n) == 'number' and n or cfg('reasons'), cfg('reasons'))
    for i, r in ipairs(e and e.reasons or {}) do
        if i > limit then break end
        out[#out + 1] = copyReason(r)
    end
    return out
end

-- Last change of level of a living character: {from, to, day, n} (copy; n = revision of the act, a stable key for
-- the client warning), or nil when the level never changed.
function R.change(character, state)
    state = dataOf(state)
    if not live(state, character) then return nil end
    local e = entryOf(state, character, false)
    local c = e and e.change
    if type(c) ~= 'table' then return nil end
    return {from = c.from, to = c.to, day = c.day, n = c.n}
end

-- Snapshot for the player of this character only (RadioSurvivor's notebook adds the text of each reason). No number
-- but game days (today, day of each reason and of the last change), translated into words by the client.
function R.projection(character, state)
    state = dataOf(state)
    if not live(state, character) then return {available = false} end
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
-- a place. nil without a living character (the bridge then says nothing about it).
function R.publicContext(character, state)
    state = dataOf(state)
    if not live(state, character) then return nil end
    local out = {level = R.level(character, state)}
    local last = R.reasons(character, 1, state)[1]
    if last then out.last = {act = last.action, about = last.reasonArgs[1]} end
    return out
end

-- E04-T05 (Q11, Q12): missions offered to a level. Simple missions (deliver, signal, scout, clear) stay open to every
-- level, so that a bad reputation can be redeemed; sensitive ones (RC_ReputationConfig.sensitive: retrieve_id,
-- recover, and the group supply missions, offer kind 'supply') are closed to a bad reputation only.
local SENSITIVE = {retrieve_id = true, recover = true, supply = true}

function R.sensitive(template, offer)
    local list = type(Config.sensitive) == 'table' and Config.sensitive or SENSITIVE
    if type(template) == 'string' and list[template] then return true end
    return type(offer) == 'table' and type(offer.kind) == 'string' and list[offer.kind] == true
end

function R.offerAllowed(level, template, offer)
    if level ~= 'bad' then return true end
    return not R.sensitive(template, offer)
end

-- E04-T14: test baseline of a living character, for the in-game test suites only: refused outside a test save in
-- debug mode (authority, isDebugEnabled, save rstest*). Score of the level (bad -40, neutral 0, good 40), trend stable
-- (no sign kept), daily gain cap cleared; reasons and last change kept; no outcome: the next real act is counted
-- normally. Returns true, or false and the reason.
R.TEST_SAVE_PREFIX = 'rstest'
local TEST_SCORES = {bad = -40, neutral = 0, good = 40}

function R.testAllowed()
    if isClient() then return false, 'not the authority (MP client)' end
    if type(isDebugEnabled) ~= 'function' or isDebugEnabled() ~= true then
        return false, 'debug mode off (isDebugEnabled() is false on this machine)'
    end
    local ok, name = pcall(function() return getWorld():getWorld() end)
    if not ok or type(name) ~= 'string' then return false, 'save name unavailable (getWorld():getWorld())' end
    if string.lower(string.sub(name, 1, #R.TEST_SAVE_PREFIX)) ~= R.TEST_SAVE_PREFIX then
        return false, "save '" .. name .. "' is not a test save (" .. R.TEST_SAVE_PREFIX .. '*)'
    end
    return true
end

function R.testSetLevel(state, character, level)
    local ok, why = R.testAllowed()
    if not ok then
        log('testSetLevel refused: ' .. tostring(why))
        return false, why
    end
    if TEST_SCORES[level] == nil then return false, 'unknown level' end
    local own = state == nil
    state = dataOf(state)
    local living, dead = live(state, character)
    if not living then return false, dead end
    local e = entryOf(state, character, true)
    e.score, e.revision = TEST_SCORES[level], e.revision + 1
    e.signs, e.trend, e.gainDay, e.gainSum = {}, 'stable', -1, 0
    if own or state == R.data then R.save() end
    return true
end

-- Death of the character: starts the purge clock of its reputation.
function R.retire(state, character)
    state = dataOf(state)
    if type(state) ~= 'table' or type(character) ~= 'string' then return end
    local e = entryOf(state, character, true)
    if e.retiredDay == nil then e.retiredDay = R.today() or 0 end
end

function R.prune(state, today)
    state = dataOf(state)
    today = today or R.today()
    if type(state) ~= 'table' or type(today) ~= 'number' then return false end
    -- Identity registry unreadable: every character would look unknown and be dropped 7 days later; nothing pruned.
    if liveness == identityLiveness and not Identity().ensure() then return false end
    local changed, gone, drop = false, {}, {}
    if type(state.reputation) == 'table' then
        for cid, e in pairs(state.reputation) do
            if not live(state, cid) then
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

-- Death of a character (RC_Identity retire listener, RC_ReputationEvents): starts its purge clock.
function R.onRetire(_, character)
    if not R.ensure() then return end
    R.retire(R.data, character)
    R.save()
end

-- Every game day (RC_ReputationEvents): purge, saved when something was dropped.
function R.everyDay()
    if R.ensure() and R.prune(R.data) then R.save() end
end

return R
