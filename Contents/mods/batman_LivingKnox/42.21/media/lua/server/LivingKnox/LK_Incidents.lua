if isClient() then return end
-- E09-T06: decision of a group leader on an incident of a faction agreement (ADR B10). Registry, targeted defence and
-- validation: Living Knox (LK_Agreements, since E18-T20; read through LivingKnox.Agreements, nothing without it).
-- Here: the request to the model (npc_incident) and its reply (LK_Talk). Fiche:
-- docs/annexes/conception/incidents.md.
--
-- Once the facts of an open incident settled (LivingKnox.Agreements.INCIDENT.SETTLE_MS), one request per pass, within the bridge
-- quotas (RC_SpeechConfig.MAX_PENDING, MAX_PER_HOUR) and not while the bridge is considered stopped (LK_Initiatives): an
-- npc_incident request in the queue of the leader's fiche (LivingKnox.API.composition(group).leaderNpc), character
-- 'group', text = the established facts composed here in English, context.incident = facts, agreement, earlier
-- decisions, context.choices = the decisions the server allows (maintain, repair with the stock categories and the
-- quantity, break). The request is bound in memory (I.bindings[request id] = { incident, revision,
-- agreementRevision, group }), never sent to the bridge. Reply: intent maintain / repair (offer = category) / break,
-- revalidated (same leader, same incident revision, same agreement revision) then applied once by
-- LivingKnox.Agreements.decideIncident. A refused or unanswered request leaves the incident open (defence kept, no automatic
-- break): asked again after LivingKnox.Agreements.INCIDENT.RETRY_MS.
local Talk = require 'LivingKnox/LK_TalkHost'
local C = require 'RadioSurvivorCore/RC_SpeechConfig'
local P = Talk.provider
-- E18-T20: the agreements and their incidents; read when used, LK_Agreements may load after this file.
local F = {}
local function agreements() return LivingKnox.Agreements end

local I = {KIND = 'npc_incident', CHARACTER = 'group', MAX_REPLY = 400, bindings = {}}
I.DECISIONS = {maintain = true, repair = true, ['break'] = true}

local function leaderOf(gid)
    local API = type(LivingKnox) == 'table' and LivingKnox.API or nil
    local c = API ~= nil and API.composition ~= nil and API.composition(gid) or nil
    return type(c) == 'table' and c.leaderNpc or nil
end

local function characterName(key)
    local name = Talk.oneLine(Talk.characterName(key) or '')
    return name ~= '' and name or 'someone'
end

local function npcName(id)
    local record = P.npc(id)
    local name = record and Talk.oneLine(record.name or '') or ''
    return name ~= '' and name or 'one of your people'
end

local function sortedKeys(set)
    local out = {}
    for k in pairs(set or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- Established facts of the incident, by author: { { name, hit, shot, kill, killed = { names } } }, victims' names.
local function summary(inc)
    local byAuthor, order = {}, {}
    for _, f in ipairs(inc.facts or {}) do
        local s = byAuthor[f.author]
        if not s then
            s = {name = characterName(f.author), hit = 0, shot = 0, kill = 0, killed = {}}
            byAuthor[f.author], order[#order + 1] = s, f.author
        end
        s[f.fact] = s[f.fact] + 1
        if f.fact == 'kill' and f.npc then s.killed[#s.killed + 1] = npcName(f.npc) end
    end
    local authors = {}
    for _, key in ipairs(order) do authors[#authors + 1] = byAuthor[key] end
    local victims = {}
    for _, id in ipairs(sortedKeys(inc.victims)) do victims[#victims + 1] = npcName(id) end
    return authors, victims
end

-- English text of the request: the facts only, composed by the server.
function I.text(inc, authors)
    local parts = {}
    for _, s in ipairs(authors) do
        local acts = {}
        if s.hit > 0 then acts[#acts + 1] = 'hit your people ' .. s.hit .. ' time(s)' end
        if s.shot > 0 then acts[#acts + 1] = 'shot at your people ' .. s.shot .. ' time(s)' end
        if #s.killed > 0 then acts[#acts + 1] = 'killed ' .. table.concat(s.killed, ', ')
        elseif s.kill > 0 then acts[#acts + 1] = 'killed one of your people' end
        parts[#parts + 1] = s.name .. ' ' .. table.concat(acts, ', ')
    end
    local team = inc.teamName ~= '' and inc.teamName or 'their team'
    return 'Incident during your ' .. inc.agreementKind .. ' with ' .. team .. ': ' .. table.concat(parts, '; ')
        .. '. Your people defend themselves against ' .. (#authors == 1 and 'this person' or 'these people')
        .. ' only. Decide what becomes of the ' .. inc.agreementKind .. '.'
end

local function bridgeDown(server)
    local Ini = server.initiatives
    return type(Ini) == 'table' and type(Ini.bridge) == 'table' and Ini.bridge.down == true
end

-- One pass of the notebook tick (once a second). Returns the number of requests sent (0 or 1).
function I.tick(server, now)
    F = agreements()
    if not F then return end
    F.installHook()
    -- Requests no longer pending (answered, refused or timed out): the incident, if still open, is asked again later.
    local live = {}
    for _, r in ipairs(server.pending) do live[r.id] = true end
    for rid, b in pairs(I.bindings) do
        if not live[rid] then
            I.bindings[rid] = nil
            F.incidentAsked(b.incident, nil, now)
        end
    end
    for _, inc in ipairs(F.incidentsToAsk(now)) do
        if #server.pending >= C.MAX_PENDING or #server.times >= C.MAX_PER_HOUR or bridgeDown(server) then return 0 end
        local leaderId = leaderOf(inc.group)
        local npc = leaderId and server.ensure(leaderId) or nil
        if not npc or not npc.alive then
            F.incidentAsked(inc.id, nil, now) -- no leader now (dead, succession pending): later
        else
            local authors, victims = summary(inc)
            local names = {}
            for _, s in ipairs(authors) do names[#names + 1] = s.name end
            local language = C.NARRATIVE_LANGUAGE
            local context = {name = npc.name, background = npc.background, stage = 'leader',
                group = P.context(leaderId, nil, language),
                incident = {agreement = inc.agreementKind, state = inc.agreementState, teamName = inc.teamName,
                    authors = names, victims = victims, facts = inc.count, defence = 'authors_only',
                    earlier = F.incidentHistory(inc.agreement)},
                choices = {maintain = {}, ['break'] = {},
                    repair = {categories = F.repairCategories(), quantity = F.REPAIR_QUANTITY}}}
            local req = server.enqueue(npc, I.KIND, I.CHARACTER, I.text(inc, authors), language, context, {})
            if not req then return 0 end
            I.bindings[req.id] = {incident = inc.id, revision = inc.revision, agreementRevision = inc.agreementRevision,
                group = inc.group}
            F.incidentAsked(inc.id, req.id, now)
            server.times[#server.times + 1] = now
            server.sync()
            print('[RS_Incidents] decision on incident ' .. inc.id .. ' (revision ' .. inc.revision .. ') asked to '
                .. npc.id .. ', leader of ' .. inc.group)
            return 1
        end
    end
    return 0
end

-- Reply of the model (common checks already made by the notebook). Returns true, the agreement and the incident
-- (copies), or false and the reason.
function I.reply(_, req, result, npc)
    F = agreements() or F
    local b = I.bindings[req.id]
    if type(b) ~= 'table' then return false, 'incident request without binding' end
    if not F.decideIncident then return false, 'no Living Knox agreements' end
    if not I.DECISIONS[result.intent] then return false, 'no incident decision (' .. tostring(result.intent) .. ')' end
    local category = ''
    if result.intent == 'repair' then category = result.offer
    elseif result.offer ~= '' then return false, 'offer without repair' end
    if #result.text > I.MAX_REPLY then return false, 'incident text too long (' .. #result.text .. ')' end
    if leaderOf(b.group) ~= npc.incarnation then return false, 'NPC no longer the group leader' end
    local ok, why, a, inc = F.decideIncident(b.incident, {revision = b.revision, agreementRevision = b.agreementRevision},
        result.intent, category, {npc = npc.id})
    if not ok then return false, why end
    return true, a, inc
end

Talk.incidents = I

return I
