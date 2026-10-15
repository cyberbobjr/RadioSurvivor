if isClient() then return end
-- E09-T04: personal relation of an NPC (notebook fiche) toward a notebook character (authority only).
-- Fiche: docs/conception/relations.md. Decision of 2026-10-13: personal gap bounded to one level above or below the
-- attitude of the NPC's group.
--
-- Key: fiche id of the NPC (S.data.npcs) + notebook character id (the player key of LK_Hostility.keyOf).
-- Shown level = level of the group attitude (Provider.relation, Living Knox: LivingKnox.API.attitude; 5 levels of
-- E09-T01) moved by the personal gap (-1, 0, +1), clamped to hostile..trusting. Without a group basis the level starts
-- from the provider's hostile flag (hostile, else cautious). Trend (E09-T01 rule): sign of the sum of the senses of
-- the three last relation facts, group facts and personal changes merged by game day (group facts first on the same
-- day); without any personal change, the trend of the group. This module never recalculates the group attitude.
--
-- A change happens only by intent change_relation of the model (RS_Carnet_Server reply) with a direction (up, down)
-- and the short id of a REAL fact this NPC knows, offered in the request (Relations.offer). The server checks again
-- at the reply: same relation revision, fact still known to this NPC and never used for a change of this relation,
-- direction consistent with the nature of the fact, gap within -1..+1. A sentence alone proves nothing (ADR B11, B15).
-- Citable facts (all with a known nature):
--   group     facts of LK_Hostility of the NPC's group toward the character (seen by a member or attributable):
--             'att:<group>:<n>', sign of the fact;
--   seen      observations of this NPC seen by itself (RS_Observations, source 'seen') whose subject is the
--             character: mission_done (+1), assault_seen (-1): 'obs:<observation key>';
--   mission   closed missions of this NPC the character took part in: success (+1), failed or abandoned (-1):
--             'mis:<mission id>'.
-- Private state RS_State (S.data.relations, never a global ModData):
--   relations = { [fiche id] = { [character] = { gap = -1..1, revision = n, changes = { { sign, day, fact, what }, ... }
--                 (TREND_FACTS last), used = { fact key, ... } (MAX_USED last, oldest first) } } }
local P = require 'RadioSurvivor/RS_NPCProvider'
local S = require 'RadioSurvivor/RS_State'
local Obs = require 'RadioSurvivor/RS_Observations'

local R = {}

R.LEVELS = {'hostile', 'wary', 'cautious', 'favorable', 'trusting'}
R.GAP_MAX = 1          -- decision 2026-10-13: one level above or below the group
R.TREND_FACTS = 3      -- decision E09-T01
R.MAX_USED = 64        -- fact keys kept per relation (a citable fact is far more recent)
R.MAX_CITABLE = 8      -- facts offered to the model per request (the most recent)
R.OBS_SIGNS = {mission_done = 1, assault_seen = -1}
R.MISSION_SIGNS = {success = 1, failed = -1, abandoned = -1}

local RANK = {}
for i, level in ipairs(R.LEVELS) do RANK[level] = i end

local function store()
    if not S.data or S.blocked then return nil end
    if type(S.data.relations) ~= 'table' then S.data.relations = {} end
    return S.data.relations
end

local function pairOf(npcId, character, create)
    local all = store()
    if not all or type(npcId) ~= 'string' or type(character) ~= 'string' then return nil end
    local byNpc = all[npcId]
    if type(byNpc) ~= 'table' then
        if not create then return nil end
        byNpc = {}
        all[npcId] = byNpc
    end
    local p = byNpc[character]
    if type(p) ~= 'table' then
        if not create then return nil end
        p = {gap = 0, revision = 0, changes = {}, used = {}}
        byNpc[character] = p
    end
    return p
end

-- Group basis: { level, trend, facts = { { key, fact, sign, day }, ... }, known = true when it comes from the group
-- attitude (false: default level without any group basis) }.
function R.base(npc, character)
    local r = P.relation(npc.incarnation, character)
    if r and RANK[r.attitude.level] then
        local trend = r.attitude.trend
        if trend ~= 'up' and trend ~= 'down' then trend = 'stable' end
        return {level = r.attitude.level, trend = trend, facts = r.facts, known = true}
    end
    local record = P.npc(npc.incarnation)
    return {level = record and record.hostile == true and 'hostile' or 'cautious', trend = 'stable', facts = {},
        known = false}
end

local function trendOf(base, p)
    if not p or #p.changes == 0 then return base.trend end
    local list = {}
    for i, f in ipairs(base.facts) do
        if type(f.day) == 'number' then list[#list + 1] = {sign = f.sign, day = f.day, order = 0, i = i} end
    end
    for i, c in ipairs(p.changes) do list[#list + 1] = {sign = c.sign, day = c.day, order = 1, i = i} end
    table.sort(list, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        if a.order ~= b.order then return a.order < b.order end
        return a.i < b.i
    end)
    local s = 0
    for i = math.max(1, #list - R.TREND_FACTS + 1), #list do s = s + list[i].sign end
    if s > 0 then return 'up' end
    if s < 0 then return 'down' end
    return 'stable'
end

-- Relation shown for this NPC and character: { level, trend, group = level of the group } (labels only, never the
-- gap nor a number). Read only.
function R.view(npc, character)
    local base = R.base(npc, character)
    local p = pairOf(npc.id, character, false)
    local gap = p and p.gap or 0
    local rank = math.max(1, math.min(#R.LEVELS, RANK[base.level] + gap))
    return {level = R.LEVELS[rank], trend = trendOf(base, p), group = base.level}
end

local function isUsed(p, key)
    for _, k in ipairs(p and p.used or {}) do if k == key then return true end end
    return false
end

-- Real facts this NPC knows about the character, never used for a change of this relation, oldest first:
-- { { key, fact, sign, day (or nil), source = 'group' | 'seen' | 'mission' }, ... }. Read only.
function R.facts(npc, character)
    local p = pairOf(npc.id, character, false)
    local out = {}
    local function add(f)
        if (f.sign == 1 or f.sign == -1) and not isUsed(p, f.key) then out[#out + 1] = f end
    end
    for _, f in ipairs(R.base(npc, character).facts) do
        if type(f.key) == 'string' then
            add({key = f.key, fact = f.fact, sign = f.sign, day = f.day, source = 'group'})
        end
    end
    for _, o in ipairs(Obs.list(npc.id)) do
        if o.source == 'seen' and o.subject == character and R.OBS_SIGNS[o.fact] then
            add({key = 'obs:' .. o.key, fact = o.fact, sign = R.OBS_SIGNS[o.fact], day = o.day, source = 'seen'})
        end
    end
    local missions = {}
    for id, m in pairs(S.data and S.data.missions or {}) do
        if m.npc == npc.id and type(m.participants) == 'table' and m.participants[character]
                and R.MISSION_SIGNS[m.state] then
            missions[#missions + 1] = {key = 'mis:' .. id, fact = 'mission_' .. m.state, sign = R.MISSION_SIGNS[m.state],
                source = 'mission', closedAt = tonumber(m.closedAt) or 0, kind = m.template or 'deliver'}
        end
    end
    table.sort(missions, function(a, b)
        if a.closedAt ~= b.closedAt then return a.closedAt < b.closedAt end
        return a.key < b.key
    end)
    for _, m in ipairs(missions) do add({key = m.key, fact = m.fact, sign = m.sign, source = 'mission', kind = m.kind}) end
    return out
end

-- Context of a request (context.relation) and its server binding (nil without citable fact):
-- context = { level, trend, group, facts = { { id = 'f<i>', fact, nature = 'good' | 'bad', source, day } } } (short
-- ids only; no key, no number but the game day); binding = { character, revision, ids = { ['f<i>'] = key } }. Only
-- the directions the gap still allows are offered (gap +1: no good fact; gap -1: no bad fact).
function R.offer(npc, character)
    local view = R.view(npc, character)
    local p = pairOf(npc.id, character, false)
    local gap = p and p.gap or 0
    local list = {}
    for _, f in ipairs(R.facts(npc, character)) do
        if (f.sign > 0 and gap < R.GAP_MAX) or (f.sign < 0 and gap > -R.GAP_MAX) then list[#list + 1] = f end
    end
    while #list > R.MAX_CITABLE do table.remove(list, 1) end
    local context = {level = view.level, trend = view.trend, group = view.group, facts = {}}
    if #list == 0 then return context, nil end
    local binding = {character = character, revision = p and p.revision or 0, ids = {}}
    for i, f in ipairs(list) do
        local id = 'f' .. i
        context.facts[i] = {id = id, fact = f.fact, nature = f.sign > 0 and 'good' or 'bad', source = f.source,
            day = f.day, kind = f.kind}
        binding.ids[id] = f.key
    end
    return context, binding
end

-- Applies a change_relation of the model. Returns the new view and the fact key, or nil and the reason (English).
function R.apply(npc, character, binding, dir, factId)
    if type(binding) ~= 'table' then return nil, 'no relation fact offered in the request' end
    local record = S.data and S.data.characters[character]
    if binding.character ~= character or not record or record.retired then return nil, 'relation target changed' end
    if dir ~= 'up' and dir ~= 'down' then return nil, 'bad relation direction' end
    local key = type(factId) == 'string' and binding.ids[factId] or nil
    if not key then return nil, 'relation fact not offered' end
    local p = pairOf(npc.id, character, false)
    if (p and p.revision or 0) ~= binding.revision then return nil, 'relation revision changed' end
    if isUsed(p, key) then return nil, 'relation fact already used' end
    local fact
    for _, f in ipairs(R.facts(npc, character)) do if f.key == key then fact = f end end
    if not fact then return nil, 'relation fact unknown to this NPC' end
    local sign = dir == 'up' and 1 or -1
    if fact.sign ~= sign then return nil, 'relation direction contradicts the fact' end
    local gap = p and p.gap or 0
    if gap + sign > R.GAP_MAX or gap + sign < -R.GAP_MAX then return nil, 'relation gap at its bound' end
    p = pairOf(npc.id, character, true)
    if not p then return nil, 'relation storage unavailable' end
    p.gap, p.revision = gap + sign, p.revision + 1
    -- what: nature id of the fact (E09-T07: shown by the notebook panel, translated on the client).
    p.changes[#p.changes + 1] = {sign = sign, day = Obs.today(), fact = key, what = fact.fact}
    while #p.changes > R.TREND_FACTS do table.remove(p.changes, 1) end
    p.used[#p.used + 1] = key
    while #p.used > R.MAX_USED do table.remove(p.used, 1) end
    S.dirty = true
    return R.view(npc, character), key
end

-- Relations of removed fiches and retired characters dropped. Returns true when something was removed.
function R.prune()
    local all = store()
    if not all then return false end
    local removed = false
    local doomed = {}
    for npcId, byNpc in pairs(all) do
        if type(byNpc) ~= 'table' or not S.data.npcs[npcId] then doomed[#doomed + 1] = npcId
        else
            local gone = {}
            for character in pairs(byNpc) do
                local record = S.data.characters[character]
                if not record or record.retired then gone[#gone + 1] = character end
            end
            for _, character in ipairs(gone) do byNpc[character] = nil; removed = true end
        end
    end
    for _, npcId in ipairs(doomed) do all[npcId] = nil; removed = true end
    if removed then S.dirty = true end
    return removed
end

-- ---------------------------------------------------------------- notebook panel (E09-T07)
-- Relation panel of a contact, for ONE character (the one who reads the notebook) and its team. Fiche:
-- docs/conception/relations.md, "Panneau du carnet". Identifiers and game days only, translated by the client; no gap,
-- no attitude value, no fact key, nothing about another character:
--   { level = one of LEVELS or nil (nothing known: no group basis and no personal change), trend, group = level of the
--     group (nil without group basis), today = game day,
--     facts = { { fact = nature id, nature = 'good' | 'bad' | 'neutral', source = 'group' | 'personal', day }, ... }
--             (PANEL_FACTS last ones, oldest first: attitude facts of the group toward this character and the personal
--             changes of this NPC, merged by game day as for the trend),
--     agreements = { { kind = 'truce' | 'alliance' | 'none', state = 'pending' | 'applicable' | 'broken' | 'kept',
--             scope = { group = 'all_members' | 'this_npc', team = 'current_members' | 'you' } }, ... },
--     suspended = true when this character is the author of an open incident with the group (protection lost) }.
R.PANEL_FACTS = 3
local Factions = require 'RadioSurvivor/RS_Factions'

local function natureOf(sign)
    if sign == 1 then return 'good' end
    if sign == -1 then return 'bad' end
    return 'neutral'
end

-- Group of the NPC now (provider record), else the one kept on the fiche; nil without group.
local function groupOf(npc)
    local record = P.npc(npc.incarnation)
    local gid = record and record.group or npc.clan
    if type(gid) ~= 'string' or gid == '' then return nil end
    return gid
end

local function panelFacts(base, p)
    local list = {}
    for i, f in ipairs(base.facts or {}) do
        if type(f.fact) == 'string' and type(f.day) == 'number' then
            list[#list + 1] = {fact = f.fact, nature = natureOf(f.sign), source = 'group', day = f.day, order = 0, i = i}
        end
    end
    for i, c in ipairs(p and p.changes or {}) do
        if type(c.day) == 'number' then
            list[#list + 1] = {fact = type(c.what) == 'string' and c.what or 'other', nature = natureOf(c.sign),
                source = 'personal', day = c.day, order = 1, i = i}
        end
    end
    table.sort(list, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        if a.order ~= b.order then return a.order < b.order end
        return a.i < b.i
    end)
    local out = {}
    for i = math.max(1, #list - R.PANEL_FACTS + 1), #list do
        local f = list[i]
        out[#out + 1] = {fact = f.fact, nature = f.nature, source = f.source, day = f.day}
    end
    return out
end

-- Agreements that apply between the NPC and the team of the reader: agreement of its group with the team, else the
-- personal truce the NPC kept when it left a group (E10-T04). Kind 'none' (broken) is shown as broken.
local function panelAgreements(npc, gid, team, personalTeam)
    local out = {}
    if type(team) ~= 'string' then return out end
    local teamScope = personalTeam and 'you' or 'current_members'
    local a = gid and Factions.agreementOf(gid, team) or nil
    if a and (a.state == 'pending' or a.state == 'applicable' or a.state == 'broken') then
        out[#out + 1] = {kind = a.kind, state = a.state, scope = {group = 'all_members', team = teamScope}}
    end
    for _, t in ipairs(Factions.trucesOf(npc.incarnation)) do
        if t.team == team and t.group ~= gid then
            out[#out + 1] = {kind = t.kind, state = 'kept', scope = {group = 'this_npc', team = teamScope}}
        end
    end
    return out
end

-- team: team of the reader (RS_Factions.projection of its player: { id, kind }); nil: no agreement listed.
function R.panel(npc, character, team)
    local base = R.base(npc, character)
    local p = pairOf(npc.id, character, false)
    local rank = math.max(1, math.min(#R.LEVELS, RANK[base.level] + (p and p.gap or 0)))
    local view = {level = R.LEVELS[rank], trend = trendOf(base, p)} -- same as R.view, one provider read
    local known = base.known or (p ~= nil and #p.changes > 0)
    local gid = groupOf(npc)
    local teamId = type(team) == 'table' and team.id or nil
    local personalTeam = type(team) == 'table' and team.kind == 'personal'
    return {level = known and view.level or nil, trend = known and view.trend or nil,
        group = base.known and base.level or nil, today = Obs.today(), facts = panelFacts(base, p),
        agreements = panelAgreements(npc, gid, teamId, personalTeam),
        suspended = gid ~= nil and Factions.isIncidentAuthor(gid, character) or nil}
end

-- Copy of a relation (tests, server diagnostic): holds the gap, never to be sent to a client.
function R.debugPair(npcId, character)
    local p = pairOf(npcId, character, false)
    if not p then return nil end
    local out = {gap = p.gap, revision = p.revision, changes = {}, used = {}}
    for i, c in ipairs(p.changes) do out.changes[i] = {sign = c.sign, day = c.day, fact = c.fact, what = c.what} end
    for i, k in ipairs(p.used) do out.used[i] = k end
    return out
end

return R
