if isClient() then return end
-- E09-T04 / E18-T21 / E21-T04: personal relation of a Living Knox NPC toward a notebook character, as the shared
-- notebook reads it (authority only). The relation is kept by LivingKnox.PersonalRelation (rules unchanged; design
-- docs/annexes/conception/relations.md) and read through LivingKnox.API.relation*. The notebook calls these functions
-- through the relation operations of its NPC provider (CA_NPCProvider.relationOffer, relationApply, relationPanel,
-- debugPair, contacts), implemented by the Living Knox provider.
--
-- `npc` is a notebook fiche ({ id, incarnation = Living Knox NPC id }). The notebook's own citable facts (golden rule
-- of 2026-11-06: each mod gives its context) are passed as `extra` at the offer and again at the reply:
--   seen      observations of this NPC seen by itself (LK_Observations, source 'seen') whose subject is the
--             character: mission_done (+1), assault_seen (-1): 'obs:<observation key>';
--   mission   closed missions of this NPC (mission store of the core mod, CA_MissionStore) the character took part in:
--             success (+1), failed or abandoned (-1): 'mis:<mission id>'.
-- The panel adds the agreements of the group with the reader's team and the incident suspension (LK_Agreements).
require 'LivingKnox/LK_Core'
local P = require 'CoreAI/CA_NPCProvider'
local World = require 'CoreAI/CA_WorldFacts'
local MissionStore = require 'CoreAI/CA_MissionStore'

local R = {}

R.OBS_SIGNS = {mission_done = 1, assault_seen = -1}
R.MISSION_SIGNS = {success = 1, failed = -1, abandoned = -1}

local function api()
    local API = LivingKnox.API
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
    local Obs = LivingKnox.Observations
    for _, o in ipairs(Obs and Obs.list(npc.id) or {}) do
        if o.source == 'seen' and o.subject == character and R.OBS_SIGNS[o.fact] then
            out[#out + 1] = {key = 'obs:' .. o.key, fact = o.fact, sign = R.OBS_SIGNS[o.fact], day = o.day,
                source = 'seen'}
        end
    end
    local missions = {}
    for id, m in pairs(MissionStore.data and MissionStore.data.missions or {}) do
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

-- { level, trend, group } or nil (no NPC).
function R.view(npc, character)
    local API, id = api(), npcOf(npc)
    if not API or not id then return nil end
    return API.relation(id, character)
end

-- context.relation of a request and its server binding (nil, nil without an NPC).
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
-- Relation panel of a contact, for ONE character (the one who reads the notebook) and its team. Personal relation:
-- { level (nil: nothing known), trend, group, today, facts } (LivingKnox.API.relationPanel); then
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
    local A = LivingKnox.Agreements
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

-- team: team of the reader (CA_Teams.projection of its player: { id, kind }); nil: no agreement listed.
function R.panel(npc, character, team)
    local API, id = api(), npcOf(npc)
    local out = API and id and API.relationPanel(id, character) or {today = World.today(), facts = {}}
    local gid = groupOf(npc)
    out.agreements = panelAgreements(npc, gid, type(team) == 'table' and team.id or nil,
        type(team) == 'table' and team.kind == 'personal')
    out.suspended = gid ~= nil and LivingKnox.Agreements ~= nil and LivingKnox.Agreements.isIncidentAuthor(gid, character) or nil
    return out
end

-- Copy of the relation of a fiche (tests, server diagnostic): holds the gap, never to be sent to a client.
function R.debugPair(npc, character)
    local PR, id = LivingKnox.PersonalRelation, npcOf(npc)
    if not PR or not id then return nil end
    return PR.debugPair(id, character)
end

-- Living Knox NPC ids that keep a personal relation toward this character (decision 2 of carnet-commun-e21.md: kept
-- among the notebook contacts), sorted.
function R.contacts(character)
    local PR = LivingKnox.PersonalRelation
    local ids = {}
    for id in pairs(PR and PR.knownBy(character) or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

return R
