if isClient() then return end
--[[
Mission template `watch` (E20-T14, ADR D02, D10): keep watch at a place named by the giver for a duration in game
hours, then report by radio what was seen. Authority only. Catalogue: CA_MissionConfig.Missions.watch (offer id
watch_v1). Registered in CA_Missions (M.register); required by CA_NotebookServer.

Giver: a radio voice only, under the name `watch` (declaration voiceName); an NPC fiche is never offered one. The
spot is the place `target` of the voice sheet (use=target), handed over by the voice set-up of the templates
that declare aimAt. Parameter hours (sheet, kind count; default entry.hours), from 1 to
entry.maxHours, else the start is refused: bad_hours.
Watch (server authority, the server copy of each participant, never a claim): a participant watches while within
entry.radius tiles of the place on the ground plane (any level: a roof or an upper floor of the place counts). Time is
the world age (CA_GameClock.hours, game hours: it stops while the game is paused, runs faster at x2/x3 and while
sleeping), read by the engine poll of each participant (CA_Missions.observe, once a second on the server):
- between two readings with someone at the spot, the time counts (m.watched, game hours);
- when nobody is at the spot, the absence starts at the last reading with someone there and its time never counts;
  someone back within entry.absenceMinutes game minutes and the watch goes on, a longer absence starts it again from
  zero (m.breaks counted, facts forgotten);
- two readings more than entry.gapHours apart (every participant off the server) are a long absence too;
- the world age going back (an admin's setTimeOfDay) restarts the reading without counting anything.
Several participants read at the same instant (one engine poll) count once: one of them at the spot is enough (so the
length of an absence is judged from the next instant on).
Objective met when m.watched reaches m.hours (latched: leaving afterwards changes nothing, reportReady): the mission
waits "to report" and succeeds by the report on the voice's frequency (the voice's report, CA_Missions.spoken).
Facts (CA_WatchFacts, sources in WatchFacts/): sampled while someone is at the spot during the watch, at most every
entry.scanMs per mission (real time); recorded in m.facts and told to the voice as plain English lines (voiceBrief),
never a coordinate. Notebook (MissionViews/CA_View_Watch): place label, time watched of the duration,
radius and absence rule; map: a circle around the place (m.mapZone, style Watch).
ASCII only (Kahlua lexer).
]]
local M = require 'CoreAI/CA_Missions'
local Config = require 'CoreAI/CA_MissionConfig'
local Clock = require 'CoreAI/CA_GameClock'
local Facts = require 'CoreAI/CA_WatchFacts'

local Watch = {idPrefix = 'watch', reportBySpeech = true, voiceName = 'watch', mapStyle = 'Watch',
    voiceText = 'keep watch at a place for some game hours, then report what was seen',
    -- E20-T03: sheet values of its mission section; the place is the common key target (a place with use=target).
    params = {hours = 'count'}}

local sampledAt = {} -- mission id -> real ms of its last sampling of the facts (memory only)
-- Game hours of rounding allowed at the end: the world age is a Java float (GameTime.java:824-827), so a sum of
-- differences of readings may fall a hair short of a whole duration.
Watch.EPSILON = 1 / 3600

local function entry() return Config.Missions.watch end

-- True when the server copy of the player stands within the radius of the spot.
function Watch.at(m, player)
    local spot, r = m.spot, m.radius or entry().radius
    local dx, dy = player:getX() - spot.x, player:getY() - spot.y
    return dx * dx + dy * dy <= r * r
end

local function restart(m)
    m.watched, m.seenAt, m.awayFrom, m.awayMark, m.watchFrom, m.facts = 0, nil, nil, nil, nil, {}
    m.breaks = (m.breaks or 0) + 1
end

local function present(m, hour)
    if m.seenAt ~= nil and (m.awayFrom == nil or m.awayMark == hour) then
        m.watched = (m.watched or 0) + (hour - m.seenAt)
    end
    if m.watchFrom == nil then m.watchFrom = hour end
    m.seenAt, m.awayFrom, m.awayMark = hour, nil, nil
    if m.watched + Watch.EPSILON >= m.hours then m.watchDone = true end
end

local function absent(m, hour, c)
    if m.seenAt == nil or m.seenAt == hour then return end -- not watching, or someone at the spot at this instant
    -- First reading without anyone: another participant of the same instant may still be at the spot, so the length
    -- of the absence is judged from the next instant on.
    if m.awayFrom == nil then
        m.awayFrom, m.awayMark = m.seenAt, hour
    elseif m.awayMark ~= hour and hour - m.awayFrom > c.absenceMinutes / 60 then
        restart(m)
    end
end

-- One reading of a participant at the world age `hour`: updates the watch; true when its visible state changed.
function Watch.read(m, here, hour)
    local c = entry()
    local before = {m.watched, m.breaks, m.watchDone}
    local last = m.readAt
    m.readAt = hour
    if last ~= nil and hour < last then
        m.seenAt, m.awayFrom, m.awayMark = nil, nil, nil -- world age went back: the reading restarts
    elseif last ~= nil and hour - last > c.gapHours and m.seenAt ~= nil then
        restart(m)
    end
    if here then present(m, hour) else absent(m, hour, c) end
    return m.watched ~= before[1] or m.breaks ~= before[2] or m.watchDone ~= before[3]
end

local function sample(m)
    local now = getTimestampMs()
    local last = sampledAt[m.id]
    if last and now - last < entry().scanMs then return false end
    sampledAt[m.id] = now
    return Facts.observe(m, m.spot)
end

-- Declaration aimAt (set-up of a voice mission with a target place, the voices' set-up): the spot at
-- `place` and the hours of `params`; also called on a scratch table to check a section before the mission exists.
-- Returns true, or false and the reason ([a-z_]).
function Watch.aimAt(m, place, params)
    local c = entry()
    local hours = type(params) == 'table' and params.hours or c.hours
    if type(hours) ~= 'number' or hours < 1 or hours > c.maxHours then return false, 'bad_hours' end
    local x, y = math.floor(place.x), math.floor(place.y)
    m.spot, m.hours, m.place = {x = x, y = y, z = math.floor(tonumber(place.z) or 0)}, hours, tostring(place.label or '')
    m.radius, m.absenceMinutes = c.radius, c.absenceMinutes
    m.mapZone = {x = x, y = y, r = math.max(c.zoneRadius, c.radius)}
    return true
end

-- Bench: forget the sampling times.
function Watch.resetForTests()
    sampledAt = {}
end

-- ---------------------------------------------------------------- engine interface

-- A radio voice only (its donor record carries `voice`); the spot comes with the set-up (aimAt).
function Watch.offer(c, npc)
    if type(npc) ~= 'table' or npc.voice == nil then return nil end
    return {kind = 'watch', report = 'radio'}
end

function Watch.create(m, c)
    m.hours, m.watched, m.breaks, m.watchDone, m.place, m.facts = c.hours, 0, 0, false, '', {}
    -- No delivery: the delivery commands of the notebook find nothing to accept.
    m.quantity, m.delivered, m.accepted = 0, 0, {}
end

-- Poll of a participant (server copy).
function Watch.observe(m, player)
    if m.watchDone or type(m.spot) ~= 'table' then return false end
    local hour = Clock.hours()
    if hour == nil then return false end
    local here = Watch.at(m, player)
    local changed = Watch.read(m, here, hour)
    if here and not m.watchDone and sample(m) then changed = true end
    return changed
end

function Watch.reportReady(m)
    return m.watchDone == true
end

-- Only the report (payload 'speech', CA_Missions.spoken) is a contribution, once the watch is done.
function Watch.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not Watch.reportReady(m) then return nil, 'Zone' end
    return {kind = 'report'}
end
function Watch.prepare() return {kind = 'watch'} end
function Watch.apply() end
function Watch.progress(m) return m.watchDone and 1 or 0, Watch.reportReady(m) end
function Watch.complete() end

local function minutes(m)
    return math.floor(math.min(m.watched or 0, m.hours or 0) * 60 + 0.5)
end

function Watch.project(m, p)
    p.template, p.place, p.report = 'watch', m.place or '', 'radio'
    p.watchedMinutes, p.hours, p.watchDone = minutes(m), m.hours or 0, m.watchDone == true
    p.radius, p.absenceMinutes = m.radius or entry().radius, m.absenceMinutes or entry().absenceMinutes
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Watch.context(m, ctx)
    ctx.kind, ctx.place, ctx.report = 'watch', m.place, 'radio'
    ctx.watchedMinutes, ctx.hours = minutes(m), m.hours or 0
end

-- E20-T02: the job told to the voice (verified time and facts only).
function Watch.voiceBrief(m)
    local hours = m.hours or 0
    local facts = {'Time watched at the spot (checked by the server): ' .. tostring(minutes(m)) .. ' of '
        .. tostring(hours * 60) .. ' game minutes.',
        'Leaving the spot for more than ' .. tostring(m.absenceMinutes or entry().absenceMinutes)
        .. ' game minutes starts the watch again from zero.'}
    for _, line in ipairs(Facts.lines(m)) do facts[#facts + 1] = line end
    return {job = 'Keep watch at ' .. tostring(m.place) .. ' for ' .. tostring(hours) .. ' game hour(s), staying within '
        .. tostring(m.radius or entry().radius) .. ' tiles of the spot, then report to you on this frequency what was '
        .. 'seen.', facts = facts}
end

M.register('watch', Watch)

return Watch
