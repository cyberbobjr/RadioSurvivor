if isClient() then return end
--[[
RadioSurvivorCore: the missions in a conversation with an NPC (E18-T18, moved from RS_Carnet_Server, same rules), for
whichever mod hosts the speech of the NPCs: the notebook of RadioSurvivor, or Living Knox alone. Authority only.

    T.openOffer(state, npc, character) -> mission | nil
    T.acquaintance(missions, character, npc, known) -> "stranger" | "acquainted"
    T.context(context, state, npc, character, group, catalog) -> offers, bound
        context.stage already set; catalog() -> offers of this NPC for this character
    T.acceptance(state, req, result, npc, name) -> mission | nil
    T.report(store, req, result, npc, bound) -> mission | nil, reason
    T.actions(host, req, result, npc, binding, ignored) -> { applied, decided, offer } | false, reason
        host: state, store, bound(), catalog(npc, character), collectiveCheck(binding, npc),
        accept(req, result, npc) -> mission | nil

A collective intention commits the whole group of the NPC: today a group mission (offer of kind 'supply', real need of
the group). Only the leader of the registry is offered one; another member may talk about the group's needs and refers
the character to the leader (context.collective).
]]
local M = require "RadioSurvivorCore/RC_Missions"
local Speech = require "RadioSurvivorCore/RC_SpeechConfig"

local T = {}

local function isCollective(terms) return type(terms) == "table" and terms.kind == "supply" end
local function collectiveMission(m) return type(m) == "table" and type(m.supply) == "table" end
T.isCollective, T.collectiveMission = isCollective, collectiveMission

-- E17-T09: offer of this NPC still open for this character (state offer, invited, not engaged): the next sentence of
-- the character may accept it. nil otherwise.
function T.openOffer(state, npc, character)
    local m = npc.mission and state.missions[npc.mission]
    if not m or m.npc ~= npc.id or m.state ~= "offer" or m.transaction or not m.invited[character]
            or m.participants[character] then return nil end
    return m
end

-- E17-T08: a stranger becomes acquainted, for good, when it talks again at least ACQUAINT_HOURS game hours after the
-- first answered exchange, after ACQUAINT_EXCHANGES answered exchanges, or when it took part in a mission of this NPC.
-- known: { stage, exchanges, firstHour }, updated here.
function T.acquaintance(missions, character, npc, known)
    if known.stage ~= "acquainted" then
        local met = (known.exchanges or 0) >= Speech.ACQUAINT_EXCHANGES
            or (type(known.firstHour) == "number"
                and getGameTime():getWorldAgeHours() - known.firstHour >= Speech.ACQUAINT_HOURS)
        if not met then
            for _, m in pairs(missions) do
                if m.npc == npc.id and m.participants[character] then met = true end
            end
        end
        known.stage = met and "acquainted" or "stranger"
    end
    return known.stage
end

-- E17-T08, E17-T09, E17-T10, E10-T02: what a sentence may do about the missions of this NPC, in its request.
function T.context(context, state, npc, character, group, catalog)
    local open = npc.mission and state.missions[npc.mission]
    if open then context.mission = M.context(open) end
    -- E11-T13: the objective of this NPC's mission is met (server fact) and the speaker takes part in it: this sentence
    -- may be the report. The model alone judges whether it is one (intent report_done, any language, no word list).
    if open and M.reportReady(open) and open.participants[character] then
        context.reportable = { mission = open.id, revision = open.revision }
    end
    -- E17-T09: an offer of this NPC open for this character may be accepted by this sentence (checked again by reply).
    local offered = T.openOffer(state, npc, character)
    -- E17-T10: an acquainted NPC receives its offer catalog with every sentence; the model alone judges whether the
    -- player asks for help or work (no word list: any language). A stranger gets no offer.
    local offers = context.stage == "acquainted" and catalog() or {}
    local bound = false
    if group and not group.leader then
        local kept = {}
        for key, terms in pairs(offers) do
            if not isCollective(terms) then kept[key] = terms end
        end
        offers = kept
        if collectiveMission(offered) then offered = nil end
    end
    if offered then
        context.acceptable = { mission = offered.id, revision = offered.revision }
        bound = collectiveMission(offered)
    end
    for _, terms in pairs(offers) do
        if isCollective(terms) then bound = true end
    end
    if group and context.stage == "acquainted" then
        context.collective = group.leader and { speaker = "leader" }
            or { speaker = "member", leaderName = group.leaderName }
    end
    return offers, bound
end

-- E17-T09: acceptance spoken to the NPC. The request carried context.acceptable. E17-T10: accepted only when the model
-- returned intent accept, and only if the same mission is still an open offer of this NPC for this character at the
-- same revision. Same path as a button (M.accept), once: the state becomes active, so a replay finds no open offer.
function T.acceptance(state, req, result, npc, name)
    local context = type(req.context) == "table" and req.context or {}
    local a = context.acceptable
    if type(a) ~= "table" or result.intent ~= "accept" then return nil end
    local m = type(a.mission) == "string" and state.missions[a.mission]
    if not m or m.revision ~= a.revision or T.openOffer(state, npc, req.character) ~= m then return nil end
    if not M.accept(state, m, req.character, name) then return nil end
    return m
end

-- E11-T13: report spoken to the requester. Applied only when the model returned intent report_done and, at the reply,
-- the same mission is still this NPC's open mission, its objective still met and the speaker still one of its
-- participants (M.spoken checks again and runs the common write-ahead report). The revision may have moved since
-- (another participant joined): the facts are checked, not the revision. Returns the mission once succeeded.
function T.report(store, req, result, npc, bound)
    local r = type(req.context) == "table" and req.context.reportable
    if type(r) ~= "table" or result.intent ~= "report_done" then return nil, "no report" end
    local m = type(r.mission) == "string" and store.data.missions[r.mission]
    if not m or npc.mission ~= m.id or m.npc ~= npc.id then return nil, "mission no longer open with this NPC" end
    if not M.reportReady(m) then return nil, "objective no longer met" end
    if not m.participants[req.character] then return nil, "speaker not a participant" end
    local speaker = nil
    for p, cid in pairs(bound) do if cid == req.character then speaker = p end end
    local ok, why = M.spoken(store, m, speaker, req.character)
    if not ok or m.state ~= "success" then return nil, "report refused: " .. tostring(why) end
    return m
end

-- Missions of a reply: new offer, spoken acceptance, spoken report. Returns { applied, decided, offer }, or false and
-- the reason when the whole reply is refused.
function T.actions(host, req, result, npc, binding, ignored)
    local state = host.state
    local applied, m = {}, nil
    local acceptable = type(req.context) == "table" and req.context.acceptable
    local acceptance = result.intent == "accept"
    if acceptance and type(acceptable) == "table" and type(acceptable.mission) == "string"
            and collectiveMission(state.missions[acceptable.mission]) then
        local ok, why = host.collectiveCheck(binding, npc)
        if not ok then acceptance = false; ignored("collective acceptance", why) end
    end
    if result.intent == "offer" then
        local terms = host.catalog(npc, req.character)[result.offer]
        if not req.offers[result.offer] or not terms then return false, "offer no longer admissible" end
        local ok, why = true, nil
        if isCollective(terms) or isCollective(req.offers[result.offer]) then
            ok, why = host.collectiveCheck(binding, npc)
        end
        if ok then
            m = M.create(state, npc, req.character, result.offer, terms)
            applied.offer = result.offer
        else
            ignored("collective offer", why) -- E09-T09: no mission, the line is still said
        end
    end
    local taken = acceptance and host.accept(req, result, npc) or nil
    if taken then applied.accept = taken.id end
    -- E11-T13: report of the met objective to this requester; a refused report is only ignored (E09-T09).
    if result.intent == "report_done" then
        local reported, why = T.report(host.store, req, result, npc, host.bound())
        if reported then
            applied.report = reported.id
            print("[RC_Missions] mission " .. reported.id .. " reported to " .. npc.id .. " by "
                .. tostring(req.character) .. ": success")
        else
            ignored("mission report", why)
        end
    end
    local decided = (collectiveMission(m) and { kind = "offer", need = m.supply.need })
        or (collectiveMission(taken) and { kind = "accept", need = taken.supply.need }) or nil
    return { applied = applied, decided = decided, offer = m }
end

return T
