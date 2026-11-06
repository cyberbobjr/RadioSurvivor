if isClient() then return end
-- E09-T04 / E18-T21: personal relation of an NPC toward a notebook character, as the notebook reads it (authority
-- only). The relation is kept by Living Knox since E18-T21 (LivingKnox.PersonalRelation, rules unchanged; design
-- docs/annexes/conception/relations.md) and read through its public API (LivingKnox.API.relation*), never by a
-- require: without Living Knox there is no NPC fiche and no relation (view nil, panel without level).
--
-- `npc` is a notebook fiche ({ id, incarnation = Living Knox NPC id }). The notebook brings its own citable facts
-- (golden rule of 2026-11-06: each mod gives its context), passed as `extra` at the offer and again at the reply:
--   seen      observations of this NPC seen by itself (RS_Observations, source 'seen') whose subject is the
--             character: mission_done (+1), assault_seen (-1): 'obs:<observation key>';
--   mission   closed missions of this NPC the character took part in: success (+1), failed or abandoned (-1):
--             'mis:<mission id>'.
-- The panel adds what belongs to the notebook: agreements of the group with the reader's team and the incident
-- suspension (Living Knox's LK_Agreements since E18-T20, read through LivingKnox.Agreements).
local S = require 'RadioSurvivor/RS_State'
local P = require 'RadioSurvivor/RS_NPCProvider'
local Obs = require 'RadioSurvivor/RS_Observations'
local function Factions() return type(LivingKnox) == 'table' and LivingKnox.Agreements or nil end

local R = {}

R.OBS_SIGNS = {mission_done = 1, assault_seen = -1}
R.MISSION_SIGNS = {success = 1, failed = -1, abandoned = -1}

local function api()
    local API = type(LivingKnox) == 'table' and LivingKnox.API or nil
    if type(API) ~= 'table' or type(API.relation) ~= 'function' then return nil end
    return API
end

local function npcOf(npc)
    if type(npc) ~= 'table' or type(npc.incarnation) ~= 'string' then return nil end
    return npc.incarnation
end

-- Citable facts the notebook knows (oldest first within each source): observations, then missions.
function R.extra(npc, character)
    local out = {}
    for _, o in ipairs(Obs.list(npc.id)) do
        if o.source == 'seen' and o.subject == character and R.OBS_SIGNS[o.fact] then
            out[#out + 1] = {key = 'obs:' .. o.key, fact = o.fact, sign = R.OBS_SIGNS[o.fact], day = o.day,
                source = 'seen'}
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
    for _, m in ipairs(missions) do
        out[#out + 1] = {key = m.key, fact = m.fact, sign = m.sign, source = 'mission', kind = m.kind}
    end
    return out
end

-- { level, trend, group } or nil (no Living Knox, no NPC).
function R.view(npc, character)
    local API, id = api(), npcOf(npc)
    if not API or not id then return nil end
    return API.relation(id, character)
end

-- context.relation of a request and its server binding (nil, nil without Living Knox).
function R.offer(npc, character)
    local API, id = api(), npcOf(npc)
    if not API or not id then return nil, nil end
    return API.relationOffer(id, character, R.extra(npc, character))
end

-- change_relation of the model: new view and fact key, or nil and the reason (English).
function R.apply(npc, character, binding, dir, factId)
    local API, id = api(), npcOf(npc)
    if not API or not id then return nil, 'no NPC engine for relations' end
    return API.relationApply(id, character, binding, dir, factId, R.extra(npc, character))
end

-- ---------------------------------------------------------------- notebook panel (E09-T07)
-- Relation panel of a contact, for ONE character (the one who reads the notebook) and its team. Living Knox part:
-- { level (nil: nothing known), trend, group, today, facts } (LivingKnox.API.relationPanel); notebook part:
--   agreements = { { kind = 'truce' | 'alliance' | 'none', state = 'pending' | 'applicable' | 'broken' | 'kept',
--           scope = { group = 'all_members' | 'this_npc', team = 'current_members' | 'you' } }, ... },
--   suspended = true when this character is the author of an open incident with the group (protection lost).

-- Group of the NPC now (provider record), else the one kept on the fiche; nil without group.
local function groupOf(npc)
    local record = P.npc(npc.incarnation)
    local gid = record and record.group or npc.clan
    if type(gid) ~= 'string' or gid == '' then return nil end
    return gid
end

-- Agreements that apply between the NPC and the team of the reader: agreement of its group with the team, else the
-- personal truce the NPC kept when it left a group (E10-T04). Kind 'none' (broken) is shown as broken.
local function panelAgreements(npc, gid, team, personalTeam)
    local out = {}
    if type(team) ~= 'string' then return out end
    local teamScope = personalTeam and 'you' or 'current_members'
    local A = Factions()
    if not A then return nil end
    local a = gid and A.agreementOf(gid, team) or nil
    if a and (a.state == 'pending' or a.state == 'applicable' or a.state == 'broken') then
        out[#out + 1] = {kind = a.kind, state = a.state, scope = {group = 'all_members', team = teamScope}}
    end
    for _, t in ipairs(A.trucesOf(npc.incarnation)) do
        if t.team == team and t.group ~= gid then
            out[#out + 1] = {kind = t.kind, state = 'kept', scope = {group = 'this_npc', team = teamScope}}
        end
    end
    return out
end

-- team: team of the reader (RC_Teams.projection of its player: { id, kind }); nil: no agreement listed.
function R.panel(npc, character, team)
    local API, id = api(), npcOf(npc)
    local out = API and id and API.relationPanel(id, character) or {today = Obs.today(), facts = {}}
    local gid = groupOf(npc)
    out.agreements = panelAgreements(npc, gid, type(team) == 'table' and team.id or nil,
        type(team) == 'table' and team.kind == 'personal')
    out.suspended = gid ~= nil and Factions() ~= nil and Factions().isIncidentAuthor(gid, character) or nil
    return out
end

-- Copy of a relation of a fiche (tests, server diagnostic): holds the gap, never to be sent to a client.
function R.debugPair(ficheId, character)
    local PR = type(LivingKnox) == 'table' and LivingKnox.PersonalRelation or nil
    local fiche = S.data and S.data.npcs and S.data.npcs[ficheId]
    if not PR or not fiche then return nil end
    return PR.debugPair(fiche.incarnation, character)
end

return R
