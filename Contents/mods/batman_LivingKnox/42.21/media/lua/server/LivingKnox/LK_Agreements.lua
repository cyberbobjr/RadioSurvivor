if isClient() then return end
--[==[
Living Knox: agreements between one of its groups ('grp-<n>') and a team of players ('fac-<n>', RC_Teams of the core
mod), personal truces kept by an NPC who left its group, and incidents of an agreement (E09-T05, E09-T06, E10-T04;
kept by Living Knox since E18-T20, user decision of 2026-11-06, moved from RadioSurvivor's RS_Factions, rules
unchanged). Authority only. Fiches: docs/annexes/conception/accords.md, incidents.md, depart.md.

Kinds, from the weakest: truce, alliance; both impose non-aggression in their scope (ADR B08), neither changes the
attitude of LK_Hostility. Scope (explicit, same for every agreement): every member of the group, every CURRENT member
of the team (vanilla faction read again by RC_Teams; a player who joins is covered, one who leaves is not) or the owner
of a personal team. Offer issued by the server (A.negotiation: fixed terms, kinds above the current one, only for a
player who may conclude now: owner or negotiator, RC_Teams.canConclude), conclusion by A.conclude (mandate read again,
same team, same revision of the agreement: two conclusions built on the same revision, only the first one is applied).
The group side (leader, composition) is checked by the caller before A.conclude.
Application: the hook LivingKnox.Hooks.covered (LK_Hostility.chooseTarget, LK_Decisions.helpTarget) is A.covered, the
only implementation; a concluded agreement is 'pending' until A.pollApplications sees, at the next decision of every
embodied member of the group (LivingKnox.Decisions.aims), that none of them aims at a covered player; it is then
'applicable' and only then announced (by the caller).
Until E18-T17 the speech of the NPCs (offer in the context, intent of the model, incident decision asked to the leader)
is still carried by RadioSurvivor's notebook, which calls this module through LivingKnox.Agreements.

Private state, two slot files written in turn (RC_SlotFile): Zomboid/Lua/batman_LivingKnox/agreements-<hex of
"mode/world">-<0|1>.txt, header LKAGR1, data = { schema = 1, agreementCounter, agreements = { ['<group>|<team>'] =
agreement }, truces = { [npc] = { [team] = truce } }, incidents = { counter, open, closed } }, written within a game
minute of a change. Never in a global ModData nor sent to a client. A team record dropped for good by the core mod
takes its agreements away (RC_Teams.onDrop). No hand-over of games saved before the split (user decision of
2026-11-06). Console messages in English.
]==]
require 'LivingKnox/LK_Core'
local SlotFile = require 'RadioSurvivorCore/RC_SlotFile'
local Identity = require 'RadioSurvivorCore/RC_Identity'
local Teams = require 'RadioSurvivorCore/RC_Teams'

local F = LivingKnox.Agreements or {}
LivingKnox.Agreements = F
F.AGREEMENT_KINDS = {'truce', 'alliance'} -- from the weakest
-- Explicit scope of every agreement: both sides as written in the record and sent to the model.
F.SCOPE = {group = 'all_members', team = 'current_members'}
F.DIR, F.HEADER, F.SCHEMA = 'batman_LivingKnox/', 'LKAGR1', 1
F.dirty = F.dirty or false
local KIND_RANK = {none = 0, truce = 1, alliance = 2}
local store_ = {seq = 0, base = nil, blocked = false}

-- Runtime only (never saved): agreement key -> evaluation number of LivingKnox.Decisions when it was concluded (or
-- first seen pending); incidents being asked and their next try.
local session = {marks = {}, asking = {}, retryAt = {}}

local function log(msg) print('[LivingKnox] agreements: ' .. tostring(msg)) end
local function fresh()
    return {schema = F.SCHEMA, agreementCounter = 0, agreements = {}, truces = {},
        incidents = {counter = 0, open = {}, closed = {}}}
end

function F.init(newWorld)
    if F.data ~= nil or store_.blocked then return F.data ~= nil end
    store_.base = SlotFile.worldBase(F.DIR, 'agreements')
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
            log('STORAGE BLOCKED: agreements written by a newer schema; preserve files for recovery')
            return false
        end
        if type(data.agreements) ~= 'table' then data.agreements = {} end
        if type(data.truces) ~= 'table' then data.truces = {} end
        F.data = data
    elseif broken then
        store_.blocked = true
        log('STORAGE BLOCKED: both agreement slots invalid; preserve files for recovery')
        return false
    else
        F.data = fresh()
    end
    return true
end

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
        log('STORAGE WRITE FAILED (' .. tostring(why) .. '); kept in memory, retried at the next game minute')
        return false
    end
    store_.seq = store_.seq + 1
    return true
end

-- Tests: work on this data table, never on a file.
function F.useData(data)
    F.data, store_ = data, {seq = 0, base = nil, blocked = false}
    session = {marks = {}, asking = {}, retryAt = {}}
end

local function store()
    if not F.ensure() then return nil end
    local d = F.data
    if type(d.agreements) ~= 'table' then d.agreements, d.agreementCounter = {}, d.agreementCounter or 0 end
    return d
end

local function size(set)
    local n = 0
    for _ in pairs(set or {}) do n = n + 1 end
    return n
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

-- Team id of an account without creating anything (core mod, RC_Teams).
local function teamOfAccount(_, account) return Teams.teamOfAccount(account) end

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
    local character = Identity.record(playerKey) -- identity of the core mod: owner account of the character
    if type(character) ~= 'table' or type(character.owner) ~= 'string' then return false end
    Teams.sync(false)
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
-- the group) is copied once, at the departure, into the private state truces[npcId][team] = { kind, agreement, group,
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
        F.dirty = true
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
    F.dirty = true
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
    local ok, role, team = Teams.canConclude(player)
    if not ok then return nil, role end
    local d = store()
    local rec = Teams.info(team)
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
    local ok, role, team = Teams.canConclude(player)
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
        signed = {account = Teams.keyOf(player), role = role, character = signer.character, npc = signer.npc}}
    d.agreements[key] = a
    local view = decisionsView(gid)
    session.marks[key] = view and view.seq or nil
    F.dirty = true
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
            F.dirty = true
        end
    end
    table.sort(out, function(a, b) return agreementKey(a.group, a.team) < agreementKey(b.group, b.team) end)
    return out
end

-- Online players of a team (IsoPlayer list given by the caller), in the given order.
function F.membersOnline(team, players)
    local out = {}
    for _, p in ipairs(players or {}) do
        if Teams.idOf(p) == team then out[#out + 1] = p end
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
    F.dirty = true
    return true
end

-- ---------------------------------------------------------------- incidents (E09-T06)
-- Fiche: docs/annexes/conception/incidents.md (ADR B10). A hit, a shot or a kill of a member of group gid attributed to a
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
-- RETRY_MS. Private state only (incidents), never a global ModData nor sent to a client.
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
    local character = Identity.record(playerKey) -- identity of the core mod: owner account of the character
    if type(character) ~= 'table' or type(character.owner) ~= 'string' then return nil end
    Teams.sync(false)
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
            if f.npc == nil and npc ~= nil then f.npc, inc.victims[npc] = npc, true; F.dirty = true end
            return copyTable(inc), 'merged'
        end
    end
    inc.authors[playerKey], inc.accounts[account] = account, true
    if npc then inc.victims[npc] = true end
    inc.facts[#inc.facts + 1] = {fact = fact, author = playerKey, npc = npc, ms = now}
    while #inc.facts > F.INCIDENT.MAX_FACTS do table.remove(inc.facts, 1) end
    inc.count, inc.revision, inc.lastAt = (inc.count or 0) + 1, inc.revision + 1, now
    F.dirty = true
    print('[LivingKnox] agreements: incident ' .. inc.id .. ' ' .. how .. ': ' .. fact .. ' by ' .. playerKey .. ' (' .. account
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
    E.listen('memberHit', 'LK_Agreements.incidents', F.onMemberHit)
    E.listen('npcDied', 'LK_Agreements.incidents', F.onNpcDied)
    E.listen('assaultSeen', 'LK_Agreements.incidents', F.onAssaultSeen)
    return true
end

local function closeOpen(book, key, inc, decision, now)
    inc.state, inc.decision, inc.closedAt = 'closed', decision, now
    book.open[key] = nil
    book.closed[#book.closed + 1] = inc
    while #book.closed > F.INCIDENT.MAX_CLOSED do table.remove(book.closed, 1) end
    local ask, retry = asking()
    ask[inc.id], retry[inc.id] = nil, nil
    F.dirty = true
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
            local rec = Teams.info(a.team)
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
    print('[LivingKnox] agreements: incident ' .. inc.id .. ' decided: ' .. choice
        .. (category and category ~= '' and (' ' .. category) or '') .. ', agreement ' .. a.id .. ' revision '
        .. a.revision .. ' (' .. a.kind .. ', ' .. a.state .. ')')
    return true, 'ok', copyTable(a), copyTable(inc)
end

F.installHook()

-- Tests and restarts of the state: forget the session bindings (Java objects).
function F.reset()
    session = {marks = {}, asking = {}, retryAt = {}}
end


-- A team record dropped for good by the core mod: nobody can be covered by its agreements any more.
Teams.onDrop(function(team)
    local d = F.data
    if type(d) ~= 'table' or type(d.agreements) ~= 'table' then return end
    local gone = {}
    for key, a in pairs(d.agreements) do if a.team == team then gone[#gone + 1] = key end end
    for _, key in ipairs(gone) do
        d.agreements[key], session.marks[key] = nil, nil
        F.closeIncident(key, 'void')
    end
    if #gone > 0 then F.dirty = true end
end)

-- Application poll of Living Knox itself (E18-T20: with or without RadioSurvivor), once a second: every agreement
-- that became applicable is handed to the listeners (F.onApplied(fn): fn(agreement copy)), e.g. RadioSurvivor's
-- notebook that announces it to the online players of the team.
F.appliedListeners = F.appliedListeners or {}
function F.onApplied(fn)
    for _, f in ipairs(F.appliedListeners) do if f == fn then return end end
    table.insert(F.appliedListeners, fn)
end
local nextPoll = 0
function F.tick()
    local now = getTimestampMs()
    if now < nextPoll or not F.data then return end
    nextPoll = now + 1000
    for _, a in ipairs(F.pollApplications()) do
        log('agreement ' .. a.id .. ' (' .. a.kind .. ') between ' .. a.group .. ' and ' .. a.team .. ' applicable')
        for _, fn in ipairs(F.appliedListeners) do fn(a) end
    end
    if F.dirty then F.save() end
end

if not F.subscribed then
    F.subscribed = true
    Events.OnInitGlobalModData.Add(function(newWorld) F.init(newWorld) end)
    Events.EveryOneMinute.Add(function() if F.dirty then F.save() end end)
    Events.OnTickEvenPaused.Add(F.tick) -- same clock as the former poll of the notebook (RS_Carnet_Server)
end

return F
