if isClient() then return end
-- E09-T03: stable team identifiers of the mod and negotiation mandates (authority only).
--
-- A vanilla Faction has only a name and an owner, both mutable, plus its members (Faction.java:24-28, 255-277): no
-- durable id. getPlayers() excludes the owner (members = owner + getPlayers()); two factions may share a name; no
-- server Lua event announces a change (base multiplayer.md). Each team therefore gets an id of the mod, 'fac-<n>',
-- never reused (persistent counter), kept in the private RS_State (never a global ModData), and found again by a
-- bounded poll of Faction.getFactions():
--   1. same session: the Java Faction object already bound to a record (rename, owner change, any membership change
--      keep the id: the server mutates the same object, FactionChangeTitlePacket / FactionChangeOwnerPacket);
--   2. after a restart (record loaded from the state, not yet bound in this session): same owner;
--   3. otherwise the majority of the record's known members (more than half are in the faction): an owner change
--      keeps the previous owner as a member (Faction.setOwner, FactionChangeOwnerPacket), so the id survives both
--      a rename and an owner change across a restart;
--   4. otherwise a new id.
-- A record bound in this session whose object left the list is dissolved for good: a faction disbanded then created
-- again (even with the same owner, name or members) gets a new id. Names are never used to match (duplicates).
-- A player without faction forms a team alone, with a personal id ('fac-<n>', kind 'personal'), kept when that
-- player joins a faction and used again if the player leaves it; it never becomes the id of a faction.
-- In solo there is no faction (the faction panel is MP only): the player is the owner of a personal team.
--
-- Mandates: the current owner of a vanilla faction designates negotiators among its members (bounded list). They
-- are cleared when the owner changes, and a negotiator who leaves the faction loses the mandate. canConclude reads
-- the vanilla faction again at call time: the current owner, or a designated negotiator still a member.
-- API for E09-T05 (agreements) and E12 (teams): Factions.idOf, Factions.canConclude, Factions.list.
--
-- E09-T05: agreements between a Living Knox group ('grp-<n>') and a team ('fac-<n>'), private state only
-- (S.data.factions.agreements, key '<group>|<team>'). Kinds, from the weakest: truce, alliance; both impose
-- non-aggression in their scope (ADR B08), neither changes the attitude of LK_Hostility. Scope (explicit, same for
-- every agreement): every member of the group, every CURRENT member of the team (vanilla faction read again by the
-- bounded poll; a player who joins is covered, one who leaves is not) or the owner of a personal team.
-- Offer issued by the server (F.negotiation: fixed terms, kinds above the current one, only for a player who may
-- conclude now), conclusion by F.conclude (mandate read again, same team, same revision of the agreement: two
-- conclusions built on the same revision, only the first one is applied). The group side (leader, composition) is
-- checked by the notebook (RS_Carnet_Server.collectiveCheck) before F.conclude.
-- Application: the hook LivingKnox.Hooks.covered (LK_Hostility.chooseTarget, LK_Decisions.helpTarget) is F.covered,
-- the only implementation; a concluded agreement is 'pending' until F.pollApplications sees, at the next decision of
-- every embodied member of the group (LivingKnox.Decisions.aims), that none of them aims at a covered player; it is
-- then 'applicable' and only then announced (RS_Carnet_Server). Fiche: docs/conception/accords.md.
-- E10-T04: an NPC who leaves its group keeps the truces of that group as personal truces (F.keepTruces, read by
-- F.covered with the npcId of the hook). Fiche: docs/conception/depart.md.
-- E09-T06: incidents of an agreement (aggression of a covered player), targeted defence and decision of the leader:
-- end of the file. Fiche: docs/conception/incidents.md.
local S = require 'RadioSurvivor/RS_State'

local F = {
    MAX_NEGOTIATORS = 5, -- per faction
    POLL_MS = 2000, -- bounded poll of the vanilla factions (tick); idOf / canConclude / designate force a read
    MAX_DISSOLVED = 64, -- dissolved records kept (agreements may still name them); ids are never reused
    AGREEMENT_KINDS = {'truce', 'alliance'}, -- E09-T05, from the weakest
    -- Explicit scope of every agreement (E09-T05): both sides as written in the record and sent to the model.
    SCOPE = {group = 'all_members', team = 'current_members'},
}
local KIND_RANK = {none = 0, truce = 1, alliance = 2}

-- Runtime only (never saved): Java Faction object -> record id, id -> object, member account -> faction record id;
-- marks: agreement key -> evaluation number of LivingKnox.Decisions when it was concluded (or first seen pending).
local session = {byObject = {}, byId = {}, memberOf = {}, synced = false, nextPoll = 0, marks = {}}

local function keyOf(player)
    -- Account name on a server (stable across reconnections, used by the factions themselves); 'solo' otherwise,
    -- as the notebook identity (the solo username changes with each character, base multiplayer.md).
    if isServer() then return player:getUsername() end
    return 'solo'
end
F.keyOf = keyOf

local function store()
    if not S.data then return nil end
    local d = S.data.factions
    if type(d) ~= 'table' then
        d = {counter = 0, records = {}, personal = {}}
        S.data.factions = d
    end
    if type(d.agreements) ~= 'table' then d.agreements, d.agreementCounter = {}, d.agreementCounter or 0 end
    return d
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
    for i = 1, #dead - F.MAX_DISSOLVED do d.records[dead[i]] = nil end
    -- E09-T05: agreements of a team record dropped for good (nobody can be covered by them any more).
    local gone = {}
    for key, a in pairs(d.agreements) do if not d.records[a.team] then gone[#gone + 1] = key end end
    for _, key in ipairs(gone) do
        d.agreements[key], session.marks[key] = nil, nil
        F.closeIncident(key, 'void') -- E09-T06
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
    if changed then S.dirty = true end
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
        S.dirty = true
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
    S.dirty = true
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

-- ---------------------------------------------------------------- agreements (E09-T05)

local function copyTable(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copyTable(x) end
    return out
end

local function agreementKey(gid, team) return gid .. '|' .. team end

local function validGroup(gid) return type(gid) == 'string' and gid:match('^grp%-%d+$') ~= nil end

-- Team id of an account without creating anything: its active vanilla faction (last poll), else its personal team,
-- else nil. In solo every player is the personal team 'solo' (Combat and the perception name players by username).
local function teamOfAccount(d, account)
    if type(account) ~= 'string' then return nil end
    if not isServer() then account = 'solo' end
    local id = session.memberOf[account]
    local rec = id and d.records[id]
    if rec and rec.state == 'active' then return id end
    return d.personal[account]
end

-- Evaluation number reached by the decision frame of Living Knox (nil without the engine part).
local function decisionsView(gid)
    local E = LivingKnox
    local De = type(E) == 'table' and E.Decisions or nil
    if type(De) ~= 'table' or type(De.aims) ~= 'function' then return nil end
    return De.aims(gid)
end

-- Hook LivingKnox.Hooks.covered(groupId, playerKey, npcId) -> boolean (LK_Hostility, LK06-T01): true when the
-- notebook character playerKey belongs (now) to a team that has a truce or an alliance with the group, pending or
-- applicable, or (E10-T04) a personal truce kept by the NPC npcId when it left its group. Never creates anything.
function F.covered(gid, playerKey, npcId)
    local d = store()
    if not d or not validGroup(gid) or type(playerKey) ~= 'string' then return false end
    local characters = S.data.characters
    local character = type(characters) == 'table' and characters[playerKey] or nil
    if type(character) ~= 'table' or type(character.owner) ~= 'string' then return false end
    F.sync(false)
    local team = teamOfAccount(d, character.owner)
    -- E09-T06: the author of an open incident with this group loses the protection of its team (targeted defence).
    if F.isIncidentAuthor(gid, playerKey) then return false end
    local a = team and d.agreements[agreementKey(gid, team)]
    if a ~= nil and KIND_RANK[a.kind] ~= nil and KIND_RANK[a.kind] > 0 then return true end
    local mine = team and type(npcId) == 'string' and type(d.truces) == 'table' and d.truces[npcId] or nil
    local kept = type(mine) == 'table' and mine[team] or nil
    return type(kept) == 'table' and KIND_RANK[kept.kind] ~= nil and KIND_RANK[kept.kind] > 0
end

-- E10-T04: personal truces of an NPC who left its group (ADR B13: kept without renegotiation). Every agreement of the
-- old group gid that covers its members now (truce or alliance, pending or applicable: the scope is every member of
-- the group) is copied once, at the departure, into S.data.factions.truces[npcId][team] = { kind, agreement, group,
-- revision, keptAt } (the strongest kind is kept per team). F.covered reads them for this NPC whatever its group; an
-- agreement concluded with the old group after the departure does not cover it. Returns the number of teams copied.
local MAX_TRUCES_PER_NPC = 64
function F.keepTruces(npcId, gid)
    local d = store()
    if not d or type(npcId) ~= 'string' or npcId == '' or #npcId > 64 or not validGroup(gid) then return 0 end
    if type(d.truces) ~= 'table' then d.truces = {} end
    local mine = type(d.truces[npcId]) == 'table' and d.truces[npcId] or {}
    local keys, n = {}, 0
    for key in pairs(d.agreements) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local a = d.agreements[key]
        local cur = mine[a.team]
        if a.group == gid and (KIND_RANK[a.kind] or 0) > 0 and size(mine) < MAX_TRUCES_PER_NPC
                and (cur == nil or KIND_RANK[a.kind] > (KIND_RANK[cur.kind] or 0)) then
            mine[a.team] = {kind = a.kind, agreement = a.id, group = gid, revision = a.revision, keptAt = getTimestampMs()}
            n = n + 1
        end
    end
    if n > 0 then
        d.truces[npcId] = mine
        S.dirty = true
    end
    return n
end

-- Personal truces of an NPC (copies, sorted by team), or {}.
function F.trucesOf(npcId)
    local d = store()
    local out = {}
    local mine = d and type(d.truces) == 'table' and d.truces[npcId] or nil
    for team, t in pairs(type(mine) == 'table' and mine or {}) do
        local c = copyTable(t)
        c.team = team
        out[#out + 1] = c
    end
    table.sort(out, function(a, b) return a.team < b.team end)
    return out
end

-- Tests and administration only: forgets the personal truces of an NPC. true when it had some.
function F.dropTruces(npcId)
    local d = store()
    if not d or type(d.truces) ~= 'table' or d.truces[npcId] == nil then return false end
    d.truces[npcId] = nil
    S.dirty = true
    return true
end

-- Installs the hook (idempotent): at load, and again before each application poll (engine loaded later in a test).
function F.installHook()
    if type(LivingKnox) ~= 'table' then return false end
    if type(LivingKnox.Hooks) ~= 'table' then LivingKnox.Hooks = {} end
    LivingKnox.Hooks.covered = F.covered
    LivingKnox.Hooks.incident = F.isIncidentAuthor -- E09-T06: rule 1 of the target choice (LK_Hostility)
    F.linkIncidents()
    return true
end

-- Agreement of a group with a team (copy), or nil.
function F.agreementOf(gid, team)
    local d = store()
    if not d or not validGroup(gid) or type(team) ~= 'string' then return nil end
    return copyTable(d.agreements[agreementKey(gid, team)])
end

-- Every agreement (copies), sorted by key.
function F.agreements()
    local d = store()
    local out = {}
    if not d then return out end
    for _, a in pairs(d.agreements) do out[#out + 1] = copyTable(a) end
    table.sort(out, function(a, b) return agreementKey(a.group, a.team) < agreementKey(b.group, b.team) end)
    return out
end

-- Offer of the server to a player talking to the leader of group gid, or nil and a reason: only when the player may
-- conclude for its team right now (owner or designated negotiator, faction read again). Fixed terms: the kinds above
-- the current agreement, each with the explicit scope. { team, teamName, personal, role, current, revision, terms =
-- { [kind] = { kind, scope } } }; revision = revision of the agreement (0 without one), checked again by F.conclude.
function F.negotiation(player, gid)
    if not validGroup(gid) then return nil, 'bad_group' end
    local ok, role, team = F.canConclude(player)
    if not ok then return nil, role end
    local d = store()
    local rec = d.records[team]
    local a = d.agreements[agreementKey(gid, team)]
    local current = a and a.kind or 'none'
    local terms, any = {}, false
    for _, kind in ipairs(F.AGREEMENT_KINDS) do
        if KIND_RANK[kind] > KIND_RANK[current] then
            terms[kind], any = {kind = kind, scope = copyTable(F.SCOPE)}, true
        end
    end
    if not any then return nil, 'nothing_to_offer' end
    return {team = team, teamName = rec and rec.name or '', personal = rec ~= nil and rec.kind == 'personal',
        role = role, current = current, revision = a and a.revision or 0, terms = terms}
end

-- Conclusion of an agreement of kind for the team of player with group gid (the group side is checked by the
-- caller). expect = { team, revision } of the offer the reply was built on; signer = { character, npc } (notebook
-- character and NPC fiche, written in the record). Revalidated now: mandate (faction read again), same team, same
-- revision, kind still above the current one. ok, reason, agreement (copy). Reasons (English, logged by the caller):
-- 'no mandate', 'team changed', 'agreement revision changed', 'agreement not admissible', 'bad arguments'.
function F.conclude(player, gid, kind, expect, signer)
    local d = store()
    if not d then return false, 'state' end
    if not validGroup(gid) or KIND_RANK[kind] == nil or kind == 'none' or type(expect) ~= 'table' then
        return false, 'bad arguments'
    end
    local ok, role, team = F.canConclude(player)
    if not ok then return false, 'no mandate' end
    if team ~= expect.team then return false, 'team changed' end
    local key = agreementKey(gid, team)
    local a = d.agreements[key]
    local revision = a and a.revision or 0
    if revision ~= expect.revision then return false, 'agreement revision changed' end
    if KIND_RANK[kind] <= KIND_RANK[a and a.kind or 'none'] then return false, 'agreement not admissible' end
    local id = a and a.id
    if not id then
        d.agreementCounter = (d.agreementCounter or 0) + 1
        id = 'agr-' .. string.format('%.0f', d.agreementCounter)
    end
    signer = type(signer) == 'table' and signer or {}
    a = {id = id, group = gid, team = team, kind = kind, state = 'pending', revision = revision + 1,
        scope = copyTable(F.SCOPE), concludedAt = getTimestampMs(),
        signed = {account = keyOf(player), role = role, character = signer.character, npc = signer.npc}}
    d.agreements[key] = a
    local view = decisionsView(gid)
    session.marks[key] = view and view.seq or nil
    S.dirty = true
    return true, 'ok', copyTable(a)
end

-- true when the next decision of every embodied member of the group came after the mark and none of them aims at a
-- covered player of the team; false and the reason otherwise.
local function confirmed(d, key, a)
    local view = decisionsView(a.group)
    if not view then return false, 'decisions of the group unavailable' end
    local mark = session.marks[key]
    if mark == nil then
        -- Concluded before a restart (or without the engine): the next decisions from now on.
        mark = view.seq
        session.marks[key] = mark
    end
    for _, m in ipairs(view.members or {}) do
        -- E09-T06: a member defending itself against the author of an open incident does not hold the agreement back.
        if m.u ~= nil and teamOfAccount(d, m.u) == a.team and not F.isIncidentAccount(a.group, m.u) then
            return false, 'member aims at a covered player'
        end
        if m.active and (m.eval or 0) <= mark then return false, 'member not decided again yet' end
    end
    return true
end

-- Application poll (notebook tick, once a second): pending agreements confirmed by the decision frame become
-- 'applicable'. Returns the copies of the agreements that became applicable now (to announce), sorted by key.
function F.pollApplications()
    F.installHook()
    local d = store()
    local out = {}
    if not d then return out end
    for key, a in pairs(d.agreements) do
        if a.state == 'pending' and confirmed(d, key, a) then
            a.state, a.appliedAt = 'applicable', getTimestampMs()
            session.marks[key] = nil
            out[#out + 1] = copyTable(a)
            S.dirty = true
        end
    end
    table.sort(out, function(a, b) return agreementKey(a.group, a.team) < agreementKey(b.group, b.team) end)
    return out
end

-- Online players of a team (IsoPlayer list given by the caller), in the given order.
function F.membersOnline(team, players)
    local out = {}
    for _, p in ipairs(players or {}) do
        if F.idOf(p) == team then out[#out + 1] = p end
    end
    return out
end

-- Tests and administration only: removes an agreement (no announcement). true when one existed.
function F.cancelAgreement(gid, team)
    local d = store()
    if not d or type(gid) ~= 'string' or type(team) ~= 'string' then return false end
    local key = agreementKey(gid, team)
    if not d.agreements[key] then return false end
    d.agreements[key], session.marks[key] = nil, nil
    F.closeIncident(key, 'void')
    S.dirty = true
    return true
end

-- ---------------------------------------------------------------- incidents (E09-T06)
-- Fiche: docs/conception/incidents.md (ADR B10). A hit, a shot or a kill of a member of group gid attributed to a
-- player covered by an agreement of its team with gid (truce or alliance, pending or applicable) opens an INCIDENT,
-- one per agreement (key '<group>|<team>'): { id = 'inc-<n>', group, team, agreement, state = 'open', revision (+1
-- per new fact), authors = { [notebook character] = account }, accounts = { [account] = true }, victims = { [npc] =
-- true }, facts = { { fact, author, npc, ms } } (MAX_FACTS last ones), count, openedAt, lastAt }. Facts of the same
-- incident are grouped (two close aggressions: one incident, one decision); the same fact seen by a witness and hit
-- directly within MERGE_MS counts once. Sources (LivingKnox.listen): 'memberHit' (LK_Bodies.onHitZombie: hit or shot
-- by weapon category), 'npcDied' (LK_Bodies.deathCause: killer of a member), 'assaultSeen' (LK_Hostility.record of a
-- seen hit, shot or kill).
-- Immediate targeted defence, without waiting for the model: the authors of an open incident with gid are no longer
-- covered for gid (F.covered) and the hook LivingKnox.Hooks.incident (F.isIncidentAuthor) makes them a target of
-- rule 1 of the target choice; every other member of the team stays covered, a third player is not concerned.
-- A member's riposte is never an initial aggression: a member's own attack writes no fact here, and the hit of a
-- covered player on a member that is aiming at that player right now (LivingKnox.Decisions.aims) opens nothing.
-- Decision: asked to the model through the fiche of the group leader by the notebook (RS_Incidents.lua) once the facts
-- settled (SETTLE_MS), bound to the incident revision and to the agreement revision; F.decideIncident applies a valid
-- decision once (maintain, repair in a stock category allowed by the server, break): the agreement revision goes up
-- by one, the incident is closed. A reply built on an older revision (new aggression meanwhile) is refused and the
-- decision asked again. Without bridge: the incident stays open (defence kept), no automatic break; asked again after
-- RETRY_MS. Private state only (S.data.factions.incidents), never a global ModData nor sent to a client.
F.INCIDENT = {
    SETTLE_MS = 5000, -- quiet delay after the last fact before the decision is asked
    RETRY_MS = 120000, -- decision asked again after a refused or unanswered request
    MERGE_MS = 2000, -- the same fact of the same author, one copy without victim: one fact
    MAX_FACTS = 16,
    MAX_AUTHORS = 8,
    MAX_CLOSED = 32,
}
F.INCIDENT_DECISIONS = {'maintain', 'repair', 'break'}
F.REPAIR_QUANTITY = 5 -- items of the chosen category asked as reparation (recorded; delivery: not in E09-T06)
local INCIDENT_FACT = {hit = true, shot = true, kill = true}
local DECISION = {maintain = true, repair = true, ['break'] = true}
local REPAIR_FALLBACK = {'food', 'water', 'medical', 'ammo', 'materials'} -- = LK_Stock.CATEGORIES

local function incidentBook(d)
    if type(d.incidents) ~= 'table' then d.incidents = {counter = 0, open = {}, closed = {}} end
    local book = d.incidents
    if type(book.open) ~= 'table' then book.open = {} end
    if type(book.closed) ~= 'table' then book.closed = {} end
    return book
end

local function asking()
    session.asking = session.asking or {}
    session.retryAt = session.retryAt or {}
    return session.asking, session.retryAt
end

-- Categories of the reparation the server allows: the engine stock categories (LK_Stock.CATEGORIES).
function F.repairCategories()
    local St = type(LivingKnox) == 'table' and LivingKnox.Stock or nil
    local list = St ~= nil and type(St.CATEGORIES) == 'table' and St.CATEGORIES or REPAIR_FALLBACK
    local out = {}
    for _, c in ipairs(list) do if type(c) == 'string' then out[#out + 1] = c end end
    return out
end

-- Agreement of the team of a notebook character with gid that covers it (truce or alliance, pending or applicable),
-- whatever the incidents: key, agreement, account; or nil.
local function coveringAgreement(d, gid, playerKey)
    local characters = S.data.characters
    local character = type(characters) == 'table' and characters[playerKey] or nil
    if type(character) ~= 'table' or type(character.owner) ~= 'string' then return nil end
    F.sync(false)
    local team = teamOfAccount(d, character.owner)
    local key = team and agreementKey(gid, team)
    local a = key and d.agreements[key]
    if a ~= nil and (KIND_RANK[a.kind] or 0) > 0 then return key, a, character.owner end
    return nil
end

-- Is the member npc of gid aiming at this account right now (engagement or fight / warn of the cascade)?
local function aimedBy(gid, npc, account)
    local view = decisionsView(gid)
    for _, m in ipairs(view and view.members or {}) do
        if m.npc == npc and m.u == account then return true end
    end
    return false
end

-- Hook LivingKnox.Hooks.incident(groupId, playerKey, npcId): true when playerKey is an author of an open incident
-- with the group. Read only.
function F.isIncidentAuthor(gid, playerKey)
    local d = store()
    if not d or type(d.incidents) ~= 'table' or type(playerKey) ~= 'string' then return false end
    for _, inc in pairs(d.incidents.open or {}) do
        if inc.group == gid and inc.authors[playerKey] ~= nil then return true end
    end
    return false
end

-- Same, by account (members of LivingKnox.Decisions.aims name players by account).
function F.isIncidentAccount(gid, account)
    local d = store()
    if not d or type(d.incidents) ~= 'table' or type(account) ~= 'string' then return false end
    for _, inc in pairs(d.incidents.open or {}) do
        if inc.group == gid and inc.accounts[account] then return true end
    end
    return false
end

-- Fact of an aggression of the notebook character playerKey against group gid (fact hit, shot or kill). opts = { npc
-- = victim 'lk-<n>' or nil, ms }. Returns the incident (copy) and 'opened' / 'added' / 'merged', or nil and the reason
-- ('not covered', 'riposte', 'incident full', 'bad arguments', 'state').
function F.incidentFact(gid, playerKey, fact, opts)
    opts = type(opts) == 'table' and opts or {}
    local d = store()
    if not d then return nil, 'state' end
    if not validGroup(gid) or not INCIDENT_FACT[fact] or type(playerKey) ~= 'string' then return nil, 'bad arguments' end
    local key, a, account = coveringAgreement(d, gid, playerKey)
    if not key then return nil, 'not covered' end
    local book = incidentBook(d)
    local inc = book.open[key]
    local npc = type(opts.npc) == 'string' and opts.npc or nil
    local author = inc ~= nil and inc.authors[playerKey] ~= nil
    if not author and npc ~= nil and aimedBy(gid, npc, account) then return nil, 'riposte' end
    if not author and inc ~= nil and size(inc.authors) >= F.INCIDENT.MAX_AUTHORS then return nil, 'incident full' end
    local now = type(opts.ms) == 'number' and opts.ms or getTimestampMs()
    local how = 'added'
    if inc == nil then
        book.counter = (book.counter or 0) + 1
        inc = {id = 'inc-' .. string.format('%.0f', book.counter), group = gid, team = a.team, agreement = a.id,
            state = 'open', revision = 0, count = 0, authors = {}, accounts = {}, victims = {}, facts = {},
            openedAt = now, lastAt = now}
        book.open[key] = inc
        how = 'opened'
    end
    for _, f in ipairs(inc.facts) do
        if f.fact == fact and f.author == playerKey and (f.npc == nil or npc == nil)
                and math.abs(now - f.ms) <= F.INCIDENT.MERGE_MS then
            if f.npc == nil and npc ~= nil then f.npc, inc.victims[npc] = npc, true; S.dirty = true end
            return copyTable(inc), 'merged'
        end
    end
    inc.authors[playerKey], inc.accounts[account] = account, true
    if npc then inc.victims[npc] = true end
    inc.facts[#inc.facts + 1] = {fact = fact, author = playerKey, npc = npc, ms = now}
    while #inc.facts > F.INCIDENT.MAX_FACTS do table.remove(inc.facts, 1) end
    inc.count, inc.revision, inc.lastAt = (inc.count or 0) + 1, inc.revision + 1, now
    S.dirty = true
    print('[RS_Factions] incident ' .. inc.id .. ' ' .. how .. ': ' .. fact .. ' by ' .. playerKey .. ' (' .. account
        .. ') on ' .. tostring(npc) .. ', agreement ' .. a.id .. ' (' .. gid .. '|' .. a.team .. '), revision '
        .. inc.revision)
    return copyTable(inc), how
end

-- Fact listeners of the engine (LivingKnox.listen, idempotent by key).
local function keyOfPlayer(p)
    local H = type(LivingKnox) == 'table' and LivingKnox.Hostility or nil
    if p == nil or H == nil or H.keyOf == nil then return nil end
    return H.keyOf(p)
end

function F.onMemberHit(info)
    if type(info) ~= 'table' or type(info.group) ~= 'string' then return end
    local key = keyOfPlayer(info.player)
    if not key then return end
    F.incidentFact(info.group, key, info.category == 'firearm' and 'shot' or 'hit', {npc = info.npc, ms = info.ms})
end

function F.onNpcDied(info)
    if type(info) ~= 'table' or type(info.group) ~= 'string' or type(info.killer) ~= 'string' then return end
    local B = LivingKnox.Bodies
    local p = nil
    for _, q in ipairs(B ~= nil and B.livingPlayers ~= nil and B.livingPlayers() or {}) do
        if q:getUsername() == info.killer then p = q end
    end
    local key = keyOfPlayer(p)
    if not key then return end
    F.incidentFact(info.group, key, 'kill', {npc = info.npc})
end

function F.onAssaultSeen(info)
    if type(info) ~= 'table' or type(info.group) ~= 'string' or type(info.player) ~= 'string' then return end
    F.incidentFact(info.group, info.player, info.fact, {})
end

function F.linkIncidents()
    local E = LivingKnox
    if type(E) ~= 'table' or type(E.listen) ~= 'function' then return false end
    E.listen('memberHit', 'RS_Factions.incidents', F.onMemberHit)
    E.listen('npcDied', 'RS_Factions.incidents', F.onNpcDied)
    E.listen('assaultSeen', 'RS_Factions.incidents', F.onAssaultSeen)
    return true
end

local function closeOpen(book, key, inc, decision, now)
    inc.state, inc.decision, inc.closedAt = 'closed', decision, now
    book.open[key] = nil
    book.closed[#book.closed + 1] = inc
    while #book.closed > F.INCIDENT.MAX_CLOSED do table.remove(book.closed, 1) end
    local ask, retry = asking()
    ask[inc.id], retry[inc.id] = nil, nil
    S.dirty = true
end

-- Closes the open incident of an agreement key without decision (agreement removed): decision 'void'.
function F.closeIncident(key, decision)
    local d = store()
    local book = d and type(d.incidents) == 'table' and incidentBook(d) or nil
    local inc = book and book.open[key]
    if not inc then return false end
    closeOpen(book, key, inc, decision or 'void', getTimestampMs())
    return true
end

local function findOpen(book, incId)
    for key, inc in pairs(book.open) do
        if inc.id == incId then return key, inc end
    end
    return nil
end

-- Open incident (copy) by id, or nil.
function F.incident(incId)
    local d = store()
    local book = d and type(d.incidents) == 'table' and incidentBook(d) or nil
    if not book then return nil end
    local _, inc = findOpen(book, incId)
    return inc and copyTable(inc) or nil
end

-- Every incident (copies: open ones, then the closed ones kept), sorted by number.
function F.incidents()
    local d = store()
    local out = {}
    local book = d and type(d.incidents) == 'table' and incidentBook(d) or nil
    if not book then return out end
    for _, inc in pairs(book.open) do out[#out + 1] = copyTable(inc) end
    for _, inc in ipairs(book.closed) do out[#out + 1] = copyTable(inc) end
    table.sort(out, function(a, b)
        return (tonumber(a.id:match('%d+')) or 0) < (tonumber(b.id:match('%d+')) or 0)
    end)
    return out
end

-- Open incidents whose decision may be asked now (facts settled, none in flight, retry delay over): copies with the
-- agreement (agreementKind, agreementRevision, teamName), sorted by id.
function F.incidentsToAsk(now)
    local d = store()
    local out = {}
    local book = d and type(d.incidents) == 'table' and incidentBook(d) or nil
    if not book then return out end
    local ask, retry = asking()
    for key, inc in pairs(book.open) do
        local a = d.agreements[key]
        if not a or (KIND_RANK[a.kind] or 0) == 0 then
            closeOpen(book, key, inc, 'void', now)
        elseif not ask[inc.id] and now - inc.lastAt >= F.INCIDENT.SETTLE_MS and now >= (retry[inc.id] or 0) then
            local c = copyTable(inc)
            local rec = d.records[a.team]
            c.agreementKind, c.agreementRevision, c.teamName = a.kind, a.revision, rec and rec.name or ''
            c.agreementState = a.state
            out[#out + 1] = c
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.id:match('%d+')) or 0) < (tonumber(b.id:match('%d+')) or 0) end)
    return out
end

-- Decision request of an incident: in flight (rid) or finished (rid nil: retry after RETRY_MS if still open).
function F.incidentAsked(incId, rid, now)
    local ask, retry = asking()
    if rid then
        ask[incId] = rid
    else
        ask[incId] = nil
        if F.incident(incId) then retry[incId] = (now or getTimestampMs()) + F.INCIDENT.RETRY_MS end
    end
end

-- Earlier decisions on the same agreement (closed incidents, oldest first): { { id, decision, category } }.
function F.incidentHistory(agreementId)
    local out = {}
    local d = store()
    local book = d and type(d.incidents) == 'table' and incidentBook(d) or nil
    for _, inc in ipairs(book and book.closed or {}) do
        if inc.agreement == agreementId and inc.decision ~= 'void' then
            out[#out + 1] = {id = inc.id, decision = inc.decision, category = inc.category}
        end
    end
    return out
end

local function inList(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

-- Applies the decision on incident incId, once. expect = { revision = incident revision, agreementRevision } of the
-- request; choice among INCIDENT_DECISIONS; category: stock category for 'repair' only; signer = { npc } (leader fiche).
-- ok, reason, agreement (copy), incident (copy). Reasons (English): 'incident closed', 'incident revision changed',
-- 'agreement revision changed', 'agreement gone', 'repair category not allowed', 'bad arguments'.
function F.decideIncident(incId, expect, choice, category, signer)
    local d = store()
    if not d then return false, 'state' end
    if type(expect) ~= 'table' or not DECISION[choice] then return false, 'bad arguments' end
    local book = incidentBook(d)
    local key, inc = findOpen(book, incId)
    if not inc then return false, 'incident closed' end
    if inc.revision ~= expect.revision then return false, 'incident revision changed' end
    local now = getTimestampMs()
    local a = d.agreements[key]
    if not a or (KIND_RANK[a.kind] or 0) == 0 then
        closeOpen(book, key, inc, 'void', now)
        return false, 'agreement gone'
    end
    if a.revision ~= expect.agreementRevision then return false, 'agreement revision changed' end
    if choice == 'repair' then
        if not inList(F.repairCategories(), category) then return false, 'repair category not allowed' end
    elseif category ~= nil and category ~= '' then
        return false, 'bad arguments'
    end
    signer = type(signer) == 'table' and signer or {}
    a.revision = a.revision + 1
    a.decision = {incident = inc.id, choice = choice, at = now, npc = signer.npc}
    if choice == 'repair' then
        a.repair = {category = category, quantity = F.REPAIR_QUANTITY, incident = inc.id, at = now}
        inc.category = category
    elseif choice == 'break' then
        a.kind, a.state, a.brokenAt, a.repair = 'none', 'broken', now, nil
        session.marks[key] = nil
    end
    inc.agreementRevision = a.revision
    closeOpen(book, key, inc, choice, now)
    print('[RS_Factions] incident ' .. inc.id .. ' decided: ' .. choice .. (category and category ~= '' and (' ' .. category)
        or '') .. ', agreement ' .. a.id .. ' revision ' .. a.revision .. ' (' .. a.kind .. ', ' .. a.state .. ')')
    return true, 'ok', copyTable(a), copyTable(inc)
end

F.installHook()

-- Tests and restarts of the state: forget the session bindings (Java objects).
function F.reset()
    session = {byObject = {}, byId = {}, memberOf = {}, synced = false, nextPoll = 0, marks = {}, asking = {},
        retryAt = {}}
end

return F
