-- Mission rewards: closed server policy, no model-selected item, frequency, location or XP.
-- E20-T04 (ADR D05): draw engine. A successful mission of a voice draws one entry of the [rewards] pool of its sheet
-- (RS_Persona: list of {kind, param, weight}), weighted by `weight`, among the entries whose kind is realizable now.
-- Each kind is one file of server/RadioSurvivor/Rewards/ registered here (R.register); adding a kind never touches
-- this engine. Kinds are required by the composition root (RadioSurvivor_Server.lua) so that they are known before
-- the first sheet is read (RS_Personas.rules reads R.KINDS).
--
-- Contract of a kind (def), every function receives ctx = {store, state, source, m, cid, player, khz, param, entry,
-- random} (param: parameter of the drawn pool entry; random(n) -> 0..n-1, the injected generator):
--   param             kind of its parameter (RS_PersonaParams), nil when it takes none
--   available(ctx)    -> detail (any true value) when realizable now, else nil; no lasting effect
--   reserve(ctx, rec, detail) -> true, or nil and a reason; fills the record before it is saved (write-ahead)
--   cancel(ctx, rec)  optional: undoes reserve when the reservation could not be saved
--   apply(ctx, rec, detail)   -> true, or false when the effect is left to recovery
--   resume(ctx, rec)  optional (E23-T05, ADR D10): detail of a reserved record whose apply did nothing, so that
--                     R.retry applies it again; nil = not now. Only a kind whose apply has no effect when it returns
--                     false defines it; a kind without resume is never reissued (its effect may have started).
--   describe(rec)     -> English line for the voice context (never a frequency, a place or an item list)
if isClient() then return end
local R = {}

-- Kind name -> parameter of a pool entry, for the sheet reader (RS_Personas.rules). Derived from the registry.
R.KINDS = {}
-- Skills a lesson may teach (pool entry lesson:<skill>:<weight>): names of vanilla Perks.
R.SKILLS = {'Doctor', 'Aiming', 'Reloading', 'Woodwork', 'Mechanics', 'Electricity', 'MetalWelding', 'Cooking',
    'Farming', 'Fishing', 'Trapping', 'PlantScavenging'}

local registry = {}

function R.register(name, def)
    registry[name] = def
    R.KINDS[name] = {param = def.param}
end

local function defaultRandom(n)
    return ZombRand(n)
end

local random = defaultRandom

-- Generator of the draws (tests inject a seeded one); nil restores ZombRand.
function R.setRandom(fn)
    random = fn or defaultRandom
end

-- Pool of the sheet ([rewards] pool=, RS_Persona): list of {kind, param, weight}.
local function pool(source)
    return type(source.rewards) == 'table' and source.rewards or {}
end

local function context(base, entry)
    local ctx = {}
    for key, value in pairs(base) do ctx[key] = value end
    ctx.entry, ctx.param = entry, entry.param
    return ctx
end

-- Weighted draw among the realizable entries: entry, ctx and detail of the drawn one, or nil.
local function draw(base)
    local found, total = {}, 0
    for _, entry in ipairs(pool(base.source)) do
        local def = registry[entry.kind]
        local ctx = def and context(base, entry)
        local detail = ctx and def.available(ctx)
        if detail then
            found[#found + 1] = {entry = entry, ctx = ctx, detail = detail}
            total = total + entry.weight
        end
    end
    if total <= 0 then return nil end
    local roll = random(total)
    for _, row in ipairs(found) do
        roll = roll - row.entry.weight
        if roll < 0 then return row.entry, row.ctx, row.detail end
    end
    return nil
end

-- Entry drawn for this mission (no effect), and its detail; nil when nothing in the pool is realizable now.
function R.choose(state, source, m, cid, player)
    local entry, _, detail = draw({state = state, source = source, m = m, cid = cid, player = player, random = random})
    return entry, detail
end

-- The effect of a reserved record happened: applied, told on the frequency of the reply, saved.
local function applied(store, rec, cid, khz)
    rec.status = 'applied'
    if khz then require('RadioSurvivor/RS_RadioLog').add(cid, khz, 'reward', rec.kind) end
    if not store.save() then return rec, 'recovery' end
    return rec
end

-- Reserve before irreversible effects. An interrupted effect is kept as 'reserved', never silently reissued (except a
-- kind that can resume it, R.retry).
function R.grant(store, source, m, player, cid, khz)
    if store.blocked or type(store.data) ~= 'table' then return nil, 'storage' end
    if not player or m.state ~= 'success' or not m.participants[cid] then return nil, 'state' end
    if m.extendedReward then return m.extendedReward, 'already_reserved' end
    local entry, ctx, detail = draw({store = store, state = store.data, source = source, m = m, cid = cid,
        player = player, khz = khz, random = random})
    if not entry then return nil, 'unavailable' end
    local def = registry[entry.kind]
    local rec = {kind = entry.kind, character = cid, source = source.id, status = 'reserved'}
    local ok, why = def.reserve(ctx, rec, detail)
    if not ok then return nil, why end
    m.extendedReward = rec
    if not store.save() then
        m.extendedReward = nil
        if def.cancel then def.cancel(ctx, rec) end
        return nil, 'storage'
    end
    if not def.apply(ctx, rec, detail) then return rec, 'recovery' end
    return applied(store, rec, cid, khz)
end

-- E23-T05 (ADR D10): applies again a reserved reward of this character whose effect did not happen (inventory full),
-- when its kind can resume it. Returns the record once applied, or nil and a reason: state, not_resumable, not_now.
function R.retry(store, source, m, player, cid, khz)
    local rec = type(m) == 'table' and m.extendedReward or nil
    if store.blocked or type(store.data) ~= 'table' or not player or type(rec) ~= 'table'
            or rec.status ~= 'reserved' or rec.character ~= cid then
        return nil, 'state'
    end
    local def = registry[rec.kind]
    if not def or not def.resume then return nil, 'not_resumable' end
    local ctx = {store = store, state = store.data, source = source, m = m, cid = cid, player = player, khz = khz,
        random = random}
    local detail = def.resume(ctx, rec)
    if not detail or not def.apply(ctx, rec, detail) then return nil, 'not_now' end
    return applied(store, rec, cid, khz)
end

function R.context(rec)
    local def = rec and registry[rec.kind]
    return def and def.describe(rec) or nil
end

return R
