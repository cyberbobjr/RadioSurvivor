if isClient() then return end
--[==[
RadioSurvivorCore: stable team identifiers and negotiation mandates (E09-T03; kept by the core mod since E18-T20,
decision confirmed by default on 2026-11-06, moved from RadioSurvivor's RS_Factions, rules unchanged). Authority only.

A vanilla Faction has only a name and an owner, both mutable, plus its members (Faction.java:24-28, 255-277): no
durable id. getPlayers() excludes the owner (members = owner + getPlayers()); two factions may share a name; no
server Lua event announces a change (base multiplayer.md). Each team therefore gets an id of the mod, 'fac-<n>',
never reused (persistent counter), and found again by a bounded poll of Faction.getFactions():
  1. same session: the Java Faction object already bound to a record (rename, owner change, any membership change
     keep the id: the server mutates the same object, FactionChangeTitlePacket / FactionChangeOwnerPacket);
  2. after a restart (record loaded from the state, not yet bound in this session): same owner;
  3. otherwise the majority of the record's known members (more than half are in the faction): an owner change
     keeps the previous owner as a member (Faction.setOwner, FactionChangeOwnerPacket), so the id survives both
     a rename and an owner change across a restart;
  4. otherwise a new id.
A record bound in this session whose object left the list is dissolved for good: a faction disbanded then created
again (even with the same owner, name or members) gets a new id. Names are never used to match (duplicates).
A player without faction forms a team alone, with a personal id ('fac-<n>', kind 'personal'), kept when that player
joins a faction and used again if the player leaves it; it never becomes the id of a faction. In solo there is no
faction (the faction panel is MP only): the player is the owner of a personal team ('solo').

Mandates: the current owner of a vanilla faction designates negotiators among its members (bounded list). They are
cleared when the owner changes, and a negotiator who leaves the faction loses the mandate. canConclude reads the
vanilla faction again at call time: the current owner, or a designated negotiator still a member.
Readers: Living Knox's agreements (LK_Agreements), RadioSurvivor's radio teams (E12: rescues, smuggler).
API: Teams.keyOf, Teams.sync, Teams.idOf, Teams.canConclude, Teams.designate, Teams.list, Teams.projection,
Teams.teamOfAccount, Teams.info, Teams.onDrop(fn) (fn(teamId) when a dissolved record is dropped for good).
Commands of the module RadioSurvivorCore (Team tab of the notebook, inscribed by Living Knox): "team" -> "team"
{ team = projection }, "mandate" { member, action = 'grant' | 'revoke' } -> "team" (or "error" { reason }).

Private state, two slot files written in turn (RC_SlotFile): Zomboid/Lua/batman_RadioSurvivorCore/teams-<hex of
"mode/world">-<0|1>.txt, header RCTEAMS1, data = { schema = 1, counter, records = { [id] = record }, personal =
{ [account] = id } }, written at each change (ids must never be given twice). Never in a global ModData.
]==]
local SlotFile = require 'RadioSurvivorCore/RC_SlotFile'
local RateLimit = require 'RadioSurvivorCore/RC_RateLimit'

local F = {
    MAX_NEGOTIATORS = 5, -- per faction
    POLL_MS = 2000, -- bounded poll of the vanilla factions; idOf / canConclude / designate force a read
    MAX_DISSOLVED = 64, -- dissolved records kept (agreements may still name them); ids are never reused
    DIR = 'batman_RadioSurvivorCore/', HEADER = 'RCTEAMS1', SCHEMA = 1,
    MODULE = 'RadioSurvivorCore',
    LIMIT = {4, 1}, -- token bucket of the team commands per account (RC_RateLimit, MP server only)
    data = nil, dirty = false, dropListeners = {},
}
RadioSurvivorCore = RadioSurvivorCore or {}
RadioSurvivorCore.teams = F
local store_ = {seq = 0, base = nil, blocked = false}

-- Runtime only (never saved): Java Faction object -> record id, id -> object, member account -> faction record id.
local session = {byObject = {}, byId = {}, memberOf = {}, synced = false, nextPoll = 0}

local function log(msg) print('[RadioSurvivorCore] teams: ' .. tostring(msg)) end
local function fresh() return {schema = F.SCHEMA, counter = 0, records = {}, personal = {}} end

function F.init(newWorld)
    if F.data ~= nil or store_.blocked then return F.data ~= nil end
    store_.base = SlotFile.worldBase(F.DIR, 'teams')
    if require('RadioSurvivorCore/RC_WorldStart').isNewWorld(newWorld == true) then
        F.data, store_.seq = fresh(), 0
        return F.save()
    end
    local best, broken = SlotFile.read(store_.base, F.HEADER)
    store_.seq = best and best.seq or 0
    if best then
        local data = best.data
        if type(data.schema) ~= 'number' or data.schema > F.SCHEMA then
            store_.blocked = true
            log('STORAGE BLOCKED: teams written by a newer schema; preserve files for recovery')
            return false
        end
        if type(data.records) ~= 'table' then data.records = {} end
        if type(data.personal) ~= 'table' then data.personal = {} end
        F.data = data
    elseif broken then
        store_.blocked = true
        log('STORAGE BLOCKED: both team slots invalid; preserve files for recovery')
        return false
    else
        F.data = fresh()
    end
    return true
end

-- True when the state is loaded (loaded now if the world exists and OnInitGlobalModData was missed).
function F.ensure()
    if F.data ~= nil then return true end
    if store_.blocked or getWorld == nil or getWorld() == nil then return false end
    return F.init(false)
end

function F.save()
    if store_.blocked or not F.data then return false end
    F.dirty = false
    if store_.base == nil then return true end -- data handed by a test (F.useData): nothing to write
    local ok, why = SlotFile.write(store_.base, F.HEADER, store_.seq + 1, F.data)
    if not ok then
        F.dirty = true
        log('STORAGE WRITE FAILED (' .. tostring(why) .. '); kept in memory, retried at the next change')
        return false
    end
    store_.seq = store_.seq + 1
    return true
end

-- Tests: work on this data table, never on a file; the session bindings are forgotten.
function F.useData(data)
    F.data, store_ = data, {seq = 0, base = nil, blocked = false}
    session = {byObject = {}, byId = {}, memberOf = {}, synced = false, nextPoll = 0}
end

function F.onDrop(fn) table.insert(F.dropListeners, fn) end

local function keyOf(player)
    -- Account name on a server (stable across reconnections, used by the factions themselves); 'solo' otherwise,
    -- as the notebook identity (the solo username changes with each character, base multiplayer.md).
    if isServer() then return player:getUsername() end
    return 'solo'
end
F.keyOf = keyOf

local function store()
    if not F.ensure() then return nil end
    return F.data
end

local function newId(d)
    d.counter = (d.counter or 0) + 1
    return 'fac-' .. string.format('%.0f', d.counter)
end

local function idNumber(id)
    return tonumber(tostring(id):match('^fac%-(%d+)$')) or 0
end

-- Vanilla factions, in list order (empty in solo or without the class).
local function vanilla()
    local out = {}
    if not isServer() or not Faction or not Faction.getFactions then return out end
    local list = Faction.getFactions()
    if not list then return out end
    for i = 0, list:size() - 1 do
        local f = list:get(i)
        if f then out[#out + 1] = f end
    end
    return out
end

-- Owner and members of a vanilla faction (owner + getPlayers, Faction.java:226-228, 263-265).
local function readFaction(f)
    local owner = f:getOwner()
    local members, count = {}, 0
    if type(owner) == 'string' and owner ~= '' then members[owner], count = true, 1 end
    local players = f:getPlayers()
    for i = 0, players:size() - 1 do
        local name = players:get(i)
        if type(name) == 'string' and not members[name] then members[name], count = true, count + 1 end
    end
    return {name = tostring(f:getName() or ''), owner = owner, members = members, count = count}
end

local function size(set)
    local n = 0
    for _ in pairs(set or {}) do n = n + 1 end
    return n
end

local function shared(a, b)
    local n = 0
    for name in pairs(a) do if b[name] then n = n + 1 end end
    return n
end

local function sameSet(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

-- Applies the current vanilla state to a record; true when something changed.
local function apply(rec, info, now)
    local changed = false
    if rec.name ~= info.name then rec.name, changed = info.name, true end
    if rec.owner ~= info.owner then
        -- Mandates are given by an owner: a new owner starts without negotiators and designates its own.
        rec.owner, rec.negotiators, changed = info.owner, {}, true
    end
    if not sameSet(rec.members or {}, info.members) then
        local copy = {}
        for k in pairs(info.members) do copy[k] = true end
        rec.members, changed = copy, true
    end
    rec.negotiators = rec.negotiators or {}
    for name in pairs(rec.negotiators) do
        -- Left the faction or became its owner: the mandate ends now.
        if not info.members[name] or name == info.owner then rec.negotiators[name], changed = nil, true end
    end
    rec.seenAt = now
    return changed
end

local function dissolve(rec, now)
    rec.state, rec.dissolvedAt, rec.negotiators = 'dissolved', now, {}
end

local function pruneDissolved(d)
    local dead = {}
    for id, rec in pairs(d.records) do if rec.state == 'dissolved' then dead[#dead + 1] = id end end
    if #dead <= F.MAX_DISSOLVED then return end
    table.sort(dead, function(a, b)
        local ra, rb = d.records[a], d.records[b]
        if (ra.dissolvedAt or 0) ~= (rb.dissolvedAt or 0) then return (ra.dissolvedAt or 0) < (rb.dissolvedAt or 0) end
        return idNumber(a) < idNumber(b)
    end)
    for i = 1, #dead - F.MAX_DISSOLVED do
        d.records[dead[i]] = nil
        -- Living Knox drops the agreements of a team record dropped for good (F.onDrop listeners).
        for _, fn in ipairs(F.dropListeners) do fn(dead[i]) end
    end
end

-- Reads the vanilla factions and binds each one to a record. Bounded (POLL_MS) unless forced. Returns true when the
-- private state changed (save and publish).
function F.sync(force)
    local d = store()
    if not d then return false end
    local now = getTimestampMs()
    if not force and session.synced and now < session.nextPoll then return false end
    session.synced, session.nextPoll = true, now + F.POLL_MS
    local changed = false
    local claimed, pairsFound, pending = {}, {}, {}
    -- 1. Same Java object as an earlier poll of this session.
    for _, f in ipairs(vanilla()) do
        local info = readFaction(f)
        local id = session.byObject[f]
        local rec = id and d.records[id]
        if rec and rec.state == 'active' and not claimed[id] then
            claimed[id] = true
            pairsFound[#pairsFound + 1] = {f = f, info = info, rec = rec}
        else pending[#pending + 1] = {f = f, info = info} end
    end
    -- Records loaded from the state and not bound yet in this session (dormant): matchable by owner or majority.
    local dormant = {}
    for id, rec in pairs(d.records) do
        if rec.kind == 'faction' and rec.state == 'active' and not session.byId[id] and not claimed[id] then
            dormant[#dormant + 1] = rec
        end
    end
    table.sort(dormant, function(a, b) return idNumber(a.id) < idNumber(b.id) end)
    -- 2. Same owner.
    local rest = {}
    for _, p in ipairs(pending) do
        local found
        for _, rec in ipairs(dormant) do
            if not claimed[rec.id] and rec.owner ~= nil and rec.owner == p.info.owner then found = rec; break end
        end
        if found then
            claimed[found.id] = true
            pairsFound[#pairsFound + 1] = {f = p.f, info = p.info, rec = found}
        else rest[#rest + 1] = p end
    end
    -- 3. Majority of the record's known members.
    local unknown = {}
    for _, p in ipairs(rest) do
        local best, bestShared
        for _, rec in ipairs(dormant) do
            if not claimed[rec.id] then
                local n = shared(rec.members or {}, p.info.members)
                if n * 2 > size(rec.members) and (not best or n > bestShared
                        or (n == bestShared and (rec.seenAt or 0) > (best.seenAt or 0))) then
                    best, bestShared = rec, n
                end
            end
        end
        if best then
            claimed[best.id] = true
            pairsFound[#pairsFound + 1] = {f = p.f, info = p.info, rec = best}
        else unknown[#unknown + 1] = p end
    end
    -- 4. New faction.
    for _, p in ipairs(unknown) do
        local id = newId(d)
        local rec = {id = id, kind = 'faction', state = 'active', name = '', members = {}, negotiators = {},
            createdAt = now}
        d.records[id] = rec
        claimed[id] = true
        pairsFound[#pairsFound + 1] = {f = p.f, info = p.info, rec = rec}
        changed = true
    end
    -- Records bound in this session whose object is gone: disbanded.
    for id, f in pairs(session.byId) do
        local rec = d.records[id]
        if not claimed[id] then
            if rec and rec.state == 'active' then dissolve(rec, now); changed = true end
            session.byId[id], session.byObject[f] = nil, nil
        end
    end
    local memberOf = {}
    for _, p in ipairs(pairsFound) do
        session.byObject[p.f], session.byId[p.rec.id] = p.rec.id, p.f
        if apply(p.rec, p.info, now) then changed = true end
        for name in pairs(p.info.members) do memberOf[name] = p.rec.id end
    end
    session.memberOf = memberOf
    pruneDissolved(d)
    if changed then F.dirty = true end
    return changed
end

local function personal(d, key)
    local id = d.personal[key]
    local rec = id and d.records[id]
    if not rec then
        id = newId(d)
        rec = {id = id, kind = 'personal', state = 'active', name = '', owner = key, members = {[key] = true},
            negotiators = {}, createdAt = getTimestampMs()}
        d.records[id], d.personal[key] = rec, id
        F.dirty = true
    end
    return rec
end

-- Team record of a player: its vanilla faction, else its personal team (created on first use).
local function teamOf(player, force)
    local d = store()
    if not d or not player then return nil end
    if force or not session.synced then F.sync(true) else F.sync(false) end
    local key = keyOf(player)
    local id = session.memberOf[key]
    local rec = id and d.records[id]
    if rec and rec.state == 'active' then return rec, key, session.byId[id] end
    return personal(d, key), key, nil
end

-- Stable team id of a player ('fac-<n>'), or nil before the private state is ready.
function F.idOf(player)
    local rec = teamOf(player, false)
    return rec and rec.id or nil
end

-- May this player conclude an agreement for its team right now? Reads the vanilla faction again (forced poll):
-- ok, reason, teamId. reason: 'owner' / 'negotiator' when allowed; 'state' (no private state), 'no_mandate'.
function F.canConclude(player)
    local rec, key, f = teamOf(player, true)
    if not rec then return false, 'state', nil end
    if rec.kind == 'personal' then return true, 'owner', rec.id end
    -- Direct read of the vanilla object, not only of the record (Faction.isOwner / isMember, Faction.java:145-155).
    if f and f:isOwner(key) then return true, 'owner', rec.id end
    if f and f:isMember(key) and rec.negotiators[key] then return true, 'negotiator', rec.id end
    return false, 'no_mandate', rec.id
end

-- Designates (grant = true) or withdraws a negotiator. Only the current owner of a vanilla faction, for one of its
-- members; at most MAX_NEGOTIATORS. ok, reason: 'not_owner', 'not_member', 'full', 'bad_args'.
function F.designate(player, member, grant)
    if type(member) ~= 'string' or member == '' or #member > 128 then return false, 'bad_args' end
    local rec, key, f = teamOf(player, true)
    if not rec then return false, 'state' end
    if rec.kind ~= 'faction' or not f or not f:isOwner(key) then return false, 'not_owner' end
    if grant then
        if not f:isMember(member) then return false, 'not_member' end
        if rec.negotiators[member] then return true, 'unchanged' end
        if size(rec.negotiators) >= F.MAX_NEGOTIATORS then return false, 'full' end
        rec.negotiators[member] = true
    else
        if not rec.negotiators[member] then return true, 'unchanged' end
        rec.negotiators[member] = nil
    end
    F.dirty = true
    return true, 'ok'
end

local function sortedKeys(set)
    local out = {}
    for k in pairs(set or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- Copy of every record (active and dissolved), sorted by id: {id, kind, state, name, owner, members, negotiators}.
function F.list()
    local d = store()
    local out = {}
    if not d then return out end
    F.sync(false)
    for _, rec in pairs(d.records) do
        out[#out + 1] = {id = rec.id, kind = rec.kind, state = rec.state, name = rec.name, owner = rec.owner,
            members = sortedKeys(rec.members), negotiators = sortedKeys(rec.negotiators)}
    end
    table.sort(out, function(a, b) return idNumber(a.id) < idNumber(b.id) end)
    return out
end

-- Notebook view of the player's own team (Team tab). Account names only, as the vanilla faction panel shows them.
function F.projection(player)
    local rec, key, f = teamOf(player, false)
    if not rec then return nil end
    local isOwner = rec.kind == 'personal' or (f ~= nil and f:isOwner(key))
    local role = isOwner and 'owner' or (rec.negotiators[key] and 'negotiator' or 'member')
    local rank = {owner = 1, negotiator = 2, member = 3}
    local members = {}
    for name in pairs(rec.members or {}) do
        local r = name == rec.owner and 'owner' or (rec.negotiators[name] and 'negotiator' or 'member')
        members[#members + 1] = {id = name, name = name, role = r}
    end
    table.sort(members, function(a, b)
        if rank[a.role] ~= rank[b.role] then return rank[a.role] < rank[b.role] end
        return a.name < b.name
    end)
    return {id = rec.id, kind = rec.kind, name = rec.name or '', role = role, isOwner = isOwner, members = members,
        negotiators = size(rec.negotiators), maxNegotiators = F.MAX_NEGOTIATORS}
end

-- Team id of an account without creating anything: its active vanilla faction (last poll), else its personal team,
-- else nil. In solo every player is the personal team 'solo' (Combat and the perception name players by username).
function F.teamOfAccount(account)
    local d = store()
    if not d or type(account) ~= 'string' then return nil end
    if not isServer() then account = 'solo' end
    local id = session.memberOf[account]
    local rec = id and d.records[id]
    if rec and rec.state == 'active' then return id end
    return d.personal[account]
end

-- { id, kind, state, name } of a team record, or nil.
function F.info(id)
    local d = store()
    local rec = d and type(id) == 'string' and d.records[id] or nil
    if not rec then return nil end
    return {id = rec.id, kind = rec.kind, state = rec.state, name = rec.name or ''}
end

-- Every change is written at once: an id handed out is never given twice, even after a crash.
local function flush()
    if F.dirty then F.save() end
end

local baseSync, baseDesignate, baseIdOf, baseProjection = F.sync, F.designate, F.idOf, F.projection
function F.sync(force) local changed = baseSync(force); flush(); return changed end
function F.designate(player, member, grant) local ok, why = baseDesignate(player, member, grant); flush(); return ok, why end
function F.idOf(player) local id = baseIdOf(player); flush(); return id end
local baseCanConclude = F.canConclude
function F.canConclude(player)
    local ok, why, id = baseCanConclude(player)
    flush()
    return ok, why, id
end
function F.projection(player) local p = baseProjection(player); flush(); return p end

-- ---------------------------------------------------------------- commands of the Team tab

local function reply(player, command, args)
    if isServer() then
        sendServerCommand(player, F.MODULE, command, args)
    else
        local notebook = RadioSurvivorCore.notebook
        if notebook and notebook.receive then notebook.receive(command, args) end
    end
end

function F.onClientCommand(module, command, player, args)
    if module ~= F.MODULE or player == nil or (command ~= 'team' and command ~= 'mandate') then return end
    if isServer() and not RateLimit.allow(player, 'core.team', F.LIMIT[1], F.LIMIT[2]) then return end
    if command == 'mandate' then
        args = type(args) == 'table' and args or {}
        if args.action ~= 'grant' and args.action ~= 'revoke' then
            reply(player, 'error', {reason = 'State'})
            return reply(player, 'team', {team = F.projection(player)})
        end
        local ok, reason = F.designate(player, args.member, args.action == 'grant')
        local errors = {not_owner = 'MandateOwner', not_member = 'MandateMember', full = 'MandateFull'}
        if not ok then reply(player, 'error', {reason = errors[reason] or 'State'}) end
    end
    reply(player, 'team', {team = F.projection(player)})
end

-- Tests and restarts of the state: forget the session bindings (Java objects).
function F.reset()
    session = {byObject = {}, byId = {}, memberOf = {}, synced = false, nextPoll = 0}
end

return F
