if isClient() then return end
--[[
Missions given by a radio voice (E11-T08): action start_mission, report on the radio. Authority only.
Required by RadioSurvivor_Server (executor registered at load, context joined to the voice's requests).

Requester ("donor"): no notebook NPC fiche and no body. One donor record per voice and per notebook character, in
the private state (RS_State: data.voiceDonors['voice:<voice>:<character>'] = { id, voice, character, mission,
missionCount, nextOfferAt, given }), never in global ModData. The common engine (RS_Missions) runs the mission as any
other: clock and delay, collective result, reputation scale of M01 (RS_Config.Reputation), purge; the mission keeps
m.npc = donor id and m.donor = 'voice', m.voice, m.requesterName (name of the sheet), m.khz (frequency of the reply),
m.report = 'radio', and no reward lot (rewardType '', rewardCount 0).
One open mission at a time per caller and per voice; after its closure, the next one waits RS_Config.OFFER_COOLDOWN_MS
(same rule as an NPC, M01). start_mission also has the RS_Actions controls: sheet actions=, budget.start_mission per
game day, START_MISSION_COOLDOWN_MS per voice.

start_mission { template }: closed list V.TEMPLATES, further restricted by the sheet's missions list.
The server draws the place with the template's
offer (RS_MissionScout: habitable building at 60-250 tiles of the caller's server position, same rules as E11-T03),
creates and accepts the mission for the caller, writes the history line "mission" (kind of place, no coordinate) on
the frequency of the reply. Refusals (reason): no_player (caller not connected: no server position), storage
(private state not loaded or blocked), no_character (no notebook character bound), mission_open (this caller already
has an open mission from this voice), recent_mission (OFFER_COOLDOWN_MS after the previous one), no_place, reputation
(E04-T05: sensitive template refused to a bad reputation; scout is a simple mission, always allowed).

Visit: the same server poll as E11-T03 (RS_Missions.observe from the notebook loop, server copy of the player).
Report (E11-T13, user decision of 2026-10-14): once the objective is met (RS_Missions.reportReady: zone reached), the
mission waits "to report". The participant announces it to this voice on its frequency (command talk, voice routed
by the frequency, request sent to the bridge with turn 'report_due'); the model playing the voice judges whether the
call is that report (any language, no word list) and then returns the action report_mission (no parameter), allowed
to every voice whose sheet allows start_mission (RS_Actions.IMPLIED). Its executor checks the facts again: an open
mission of this voice for this caller, objective met, caller a participant (RS_Missions.spoken: template check,
write-ahead transaction), then success. Before the objective, a call is never a report (turn 'not_yet') and the
action is refused (not_done). Another frequency reaches another voice (or none): never this mission. Reward
(V.reward): reputation by the engine, plus a mark_map of the first place of the voice sheet not yet given to this
character by this voice (MapMarks.give: map mark and history line "mark", no budget). A sheet without place= lines
(or all already given): reputation only. The place that would be given is told to the voice with turn 'report_due'
(field reward). The mark is sent after the success is saved: a crash in between loses the mark, never the success.
Without the bridge the voice never answers: a voice mission waits for the bridge (or its delay); no notebook button.

Bridge context (V.context, field mission= of the radio request, hex RSV2): kind, state, place (kind of building in
English), clues (no digits), zoneReached, report = 'radio', remainingMs, turn ('briefing': the mission was just
created, the voice must now tell the clues; 'not_yet': the caller has not reached the place; 'report_due': the place
was reached, this call may be the report (action report_mission); 'success': the report was accepted; 'open':
otherwise), toReport (objective met), reward (label of the place given, or to be given at the report). Never a
coordinate nor the zone.
Briefing (E11-T09): the reply that proposes start_mission is aired before the action is judged, so it cannot know the
place. Once the mission is created, V.onStarted(m, ctx) (set by RadioSurvivor_Server) queues one more request to the
bridge for this caller and this voice, with turn = 'briefing': the voice then says the kind of place and its clues on
its frequency. The clues are also shown, translated, by the notebook (RS_MissionScout, p.clues).
]]
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Config = require "RadioSurvivor/RS_Config"
local Codec = require "RadioSurvivor/RS_Codec"
local M = require "RadioSurvivor/RS_Missions"
local Rep = require "RadioSurvivor/RS_Reputation"
require "RadioSurvivor/RS_MissionScout" -- registers the scout template
require "RadioSurvivor/RS_MissionClear"
require "RadioSurvivor/RS_MissionRetrieve"
local S = require "RadioSurvivor/RS_State"
local Actions = require "RadioSurvivor/RS_Actions"
local Log = require "RadioSurvivor/RS_RadioLog"
local MapMarks = require "RadioSurvivor/RS_MapMarks"

local V = {}

-- Closed list of the start_mission parameter `template` (names of RS_Missions templates and RS_Config.Missions).
V.TEMPLATES = { scout = true, deliver = true, retrieve = true, clear = true, signal = true }
local TEMPLATE_NAMES = {retrieve = "retrieve_id"}
V.COOLDOWN_MS = Const.START_MISSION_COOLDOWN_MS

function V.donorId(voice, cid)
    return "voice:" .. tostring(voice) .. ":" .. tostring(cid)
end

-- Donor record of this voice for this character; created when asked.
function V.donor(state, voice, cid, create)
    if type(state.voiceDonors) ~= "table" then
        if not create then return nil end
        state.voiceDonors = {}
    end
    local id = V.donorId(voice, cid)
    local d = state.voiceDonors[id]
    if not d and create then
        d = { id = id, voice = voice, character = cid, missionCount = 0, given = {} }
        state.voiceDonors[id] = d
    end
    return d
end

-- Open mission (offer or active) of this voice for this character, or nil.
function V.open(state, voice, cid)
    if type(state) ~= "table" or type(voice) ~= "string" or type(cid) ~= "string" then return nil end
    local d = V.donor(state, voice, cid, false)
    local m = d and d.mission and state.missions[d.mission]
    if m and (m.state == "active" or m.state == "offer") then return m end
    return nil
end

local function publish()
    local server = RS_CarnetServer
    if server and type(server.publish) == "function" then server.publish() end
end

-- Creates and accepts a mission of this voice for the caller. store: RS_State or a double { data, blocked, save }.
-- Returns the mission, or nil and a refusal reason ([a-z_]).
function V.start(store, sheet, cid, player, khz, template)
    if not player then return nil, "no_player" end
    local state = store.data
    if type(state) ~= "table" or store.blocked then return nil, "storage" end
    local record = type(cid) == "string" and state.characters[cid] or nil
    if not record or record.retired then return nil, "no_character" end
    if V.open(state, sheet.id, cid) then return nil, "mission_open" end
    local d = V.donor(state, sheet.id, cid, true)
    if d.nextOfferAt and getTimestampMs() < d.nextOfferAt then return nil, "recent_mission" end
    local allowed = sheet.missions or {"scout"}
    local permitted = false
    for _, name in ipairs(allowed) do if name == template then permitted = true end end
    if not V.TEMPLATES[template] or not permitted then return nil, "bad_template" end
    local name = TEMPLATE_NAMES[template] or template
    if name == "signal" then require "RadioSurvivor/RS_MissionSignal" end
    local c = Config.Missions[name]
    -- E04-T05 (Q11): a sensitive template is never started for a bad reputation (V.TEMPLATES holds simple ones only).
    if not Rep.offerAllowed(Rep.level(cid, state), name) then return nil, "reputation" end
    local t = V.TEMPLATES[template] and c and M.template({ template = name })
    -- The template's offer draws the place around the caller (server copy of the player: never a client claim).
    local terms = t and t.offer(c, d, nil, player, cid)
    if not terms then return nil, "no_place" end
    if template == "deliver" and (type(sheet.places) ~= "table" or #sheet.places == 0) then
        return nil, "no_place"
    end
    local m = M.create(state, d, cid, c.id, terms)
    if not m then return nil, "no_place" end
    m.donor, m.voice, m.requesterName, m.khz, m.report = "voice", sheet.id, tostring(sheet.name or sheet.id), khz, "radio"
    m.rewardType, m.rewardCount = "", 0
    if template == "deliver" then
        local place = sheet.places[(d.missionCount - 1) % #sheet.places + 1]
        m.deposit = {x = place.x, y = place.y, z = place.z or 0,
            mode = d.missionCount % 2 == 1 and 'box' or 'bag'}
        m.place, m.placeKind = place.label, "dead drop"
        -- Saved atomically with acceptance below; do not persist a half-created mission.
        require("RadioSurvivor/RS_VoiceDelivery").prepare(m, {save = function() return true end})
        m.mapZone = m.mapZone or {x = place.x, y = place.y, r = 3}
    end
    M.accept(state, m, cid, record.name or "")
    if type(record.knownMissions) == "table" then record.knownMissions[m.id] = true end
    if not store.save() then
        state.missions[m.id], d.mission, d.missionCount = nil, nil, d.missionCount - 1
        if type(record.knownMissions) == "table" then record.knownMissions[m.id] = nil end
        return nil, "storage"
    end
    return m
end

-- Successful missions use RS_Rewards when explicitly enabled by the sheet; legacy sheets retain map marks.
function V.reward(store, sheet, m, player, cid, khz)
    if type(sheet.rewards) == 'table' and #sheet.rewards > 0 then
        local R = require 'RadioSurvivor/RS_Rewards'
        local rec, why = R.grant(store, sheet, m, player, cid, khz)
        if rec then m.rewardLabel = rec.status == 'applied' and R.context(rec) or nil end
        if why then Const.log('voice mission reward ' .. tostring(m.id) .. ': ' .. why) end
        return rec
    end
    local d = M.donorOf(store.data, m)
    local given = d and type(d.given) == "table" and d.given or {}
    local place = nil
    for _, p in ipairs(type(sheet.places) == "table" and sheet.places or {}) do
        if type(p) == "table" and type(p.id) == "string" and not given[p.id] then
            place = p
            break
        end
    end
    if not place then
        Const.log("voice mission " .. tostring(m.id) .. ": no place left to give, reputation only")
        return nil
    end
    if d then
        d.given = given
        given[place.id] = true
    end
    m.rewardPlace, m.rewardLabel = place.id, place.label
    store.save()
    if player then MapMarks.give(player, cid, khz, place) end
    return place
end

-- Place of the sheet the next success would give (first not yet given to this character by this voice), or nil.
function V.nextPlace(state, sheet, m)
    if type(sheet.rewards) == 'table' and #sheet.rewards > 0 then
        -- No irreversible promise before the server has actually applied the effect.
        return nil
    end
    local d = M.donorOf(state, m)
    local given = d and type(d.given) == "table" and d.given or {}
    for _, p in ipairs(type(sheet) == "table" and type(sheet.places) == "table" and sheet.places or {}) do
        if type(p) == "table" and type(p.id) == "string" and not given[p.id] then return p end
    end
    return nil
end

-- Bridge context of an open (or just closed) voice mission; turn: 'not_yet', 'report_due', 'success' or 'open'.
-- place: the place that the report would give (turn 'report_due'), told to the voice beforehand.
function V.context(m, turn, place)
    local ctx = M.context(m)
    ctx.rewardType, ctx.rewardCount = nil, nil
    ctx.turn = turn
    if m.rewardLabel then ctx.reward = m.rewardLabel
    elseif type(place) == "table" and type(place.label) == "string" then ctx.reward = place.label end
    return ctx
end

-- The caller (notebook character cid) speaks to this voice and the request goes to the bridge (E11-T13): nothing is
-- judged here; the turn tells the voice whether the objective is met (report_due: the call may be the report, then
-- action report_mission). Returns the bridge context of this voice's mission for this caller, or nil.
function V.heard(sheet, player, cid, khz, store)
    store = store or S
    local state = store.data
    if type(state) ~= "table" or store.blocked or type(sheet) ~= "table" then return nil end
    local m = V.open(state, sheet.id, cid)
    if not m then return nil end
    local turn, place = "open", nil
    if m.state == "active" and M.reportReady(m) then
        turn, place = "report_due", V.nextPlace(state, sheet, m)
    elseif m.state == "active" then
        turn = "not_yet"
    end
    return V.context(m, turn, place)
end

-- The caller reports this voice's mission on its frequency (E11-T13, action report_mission accepted by RS_Actions).
-- store: RS_State or a double { data, blocked, save }. Returns the mission once succeeded, or nil and a refusal
-- reason ([a-z_]): storage, no_mission (no open mission of this voice for this caller), not_done (objective not
-- met: a claim validates nothing), refused (engine refusal).
function V.report(store, sheet, cid, player, khz)
    local state = store.data
    if type(state) ~= "table" or store.blocked then return nil, "storage" end
    local m = type(sheet) == "table" and V.open(state, sheet.id, cid) or nil
    if not m or m.state ~= "active" or not m.participants[cid] then return nil, "no_mission" end
    if not M.reportReady(m) then return nil, "not_done" end
    local ok = M.spoken(store, m, player, cid)
    if not ok or m.state ~= "success" then return nil, "refused" end
    V.reward(store, sheet, m, player, cid, khz)
    publish()
    return m
end

-- Field mission= of a radio request (hex RSV2), nil without context.
function V.field(ctx)
    if type(ctx) ~= "table" then return nil end
    return Codec.hexBytes(Codec.encodeBytes(ctx))
end

-- Executor -----------------------------------------------------------------------------------------------------

-- Single parameter `template`, from the closed list.
local function validate(params)
    for key in pairs(params) do
        if key ~= "template" then return false end
    end
    return type(params.template) == "string" and V.TEMPLATES[params.template] == true
end

local function execute(params, ctx)
    if type(ctx) ~= "table" or type(ctx.sheet) ~= "table" then return false, "failed" end
    local m, why = V.start(S, ctx.sheet, ctx.cid, ctx.player, ctx.khz, params.template)
    if not m then return false, why end
    Log.add(ctx.cid, ctx.khz, "mission", m.placeKind or m.place or params.template)
    Const.log("voice mission " .. m.id .. " started (" .. tostring(m.placeKind) .. ")")
    publish()
    -- E11-T09: the voice tells the clues right away (briefing request, RadioSurvivor_Server).
    if type(V.onStarted) == "function" then V.onStarted(m, ctx) end
    return true
end

-- report_mission (E11-T13): no parameter; allowed with start_mission (RS_Actions.IMPLIED), no budget nor delay.
local function validateReport(params)
    local n = 0
    for _ in pairs(params) do n = n + 1 end
    return n == 0
end

local function executeReport(_, ctx)
    if type(ctx) ~= "table" or type(ctx.sheet) ~= "table" then return false, "failed" end
    local m, why = V.report(S, ctx.sheet, ctx.cid, ctx.player, ctx.khz)
    if not m then return false, why end
    Const.log("voice mission " .. m.id .. " reported on the radio: success")
    return true
end

local function executeShare(_, ctx)
    if type(ctx) ~= 'table' or type(ctx.sheet) ~= 'table' or not ctx.player or not ctx.cid then
        return false, 'no_player'
    end
    if S.blocked or not S.data or not S.data.characters[ctx.cid] then return false, 'storage' end
    local detail = require('RadioSurvivor/RS_Rewards').frequency(ctx.sheet)
    if not detail then return false, 'unavailable' end
    local label = (detail.name or detail.voice) .. ' (' .. string.format('%.1f MHz', detail.khz / 1000) .. ')'
    if not Log.add(ctx.cid, detail.khz, 'reply', label) then
        return false, 'storage'
    end
    if not S.save() then return false, 'storage' end
    return true
end

function V.register()
    local started = Actions.register("start_mission", { validate = validate, cooldownMs = V.COOLDOWN_MS,
        execute = execute })
    local report = Actions.register("report_mission", { validate = validateReport, execute = executeReport })
    local share = Actions.register("share_frequency", {validate = validateReport,
        cooldownMs = V.COOLDOWN_MS, execute = executeShare})
    return started and report and share
end

V.register()

return V
