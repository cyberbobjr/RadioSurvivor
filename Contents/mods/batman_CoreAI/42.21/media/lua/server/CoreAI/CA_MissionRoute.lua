if isClient() then return end
--[[
Mission template `route` (E20-T13, ADR D02, D10): cross IN ORDER several places named by the giver, on foot or by
vehicle, then report by radio. Authority only. Catalogue: CA_MissionConfig.Missions.route (offer id route_v1).
Registered in CA_Missions (M.register); required by CA_NotebookServer.

Giver: a radio voice only, under the name `route` (declaration voiceName); an NPC fiche is never offered one. The
points come with the set-up: declaration alongPoints(m, points) -> ok, reason, called by the voices'
set-up with the places { id, label, x, y, z } named in order by the section's parameter points= (kind
`places` of the sheet parameters: 2 to 8 points of the shared places, E25-T01, never the same twice in a row); also
called on a scratch table to check a section before the mission exists (fewer than 2 points: false, 'no_points').
Crossing (server authority, read on the server copy of each participant, never a claim; CA_Missions.observe, once a
second): the position is the participant's vehicle when they sit in one (IsoGameCharacter.getVehicle; BaseVehicle
.update puts each passenger on its seat, BaseVehicle.java:3369-3378), else the participant. The next point (m.next)
is crossed when that position, or the straight way from the previous reading of that participant (at most
entry.maxStep tiles long: a longer one is a jump, only its end counts), comes within entry.radius tiles of it (2D: a
place is crossed at any level). Only the next point counts: a later point reached first is not crossed and must be
crossed again after the previous ones (skipped point refused). The previous readings are kept in memory only (a
restart of the server reads the next position alone). A dead participant crosses nothing.
Objective met once every point is crossed (reportReady): the mission waits "to report" and succeeds by the report on
the voice's frequency (the voice's report, CA_Missions.spoken). Notebook (MissionViews/
CA_View_Route): points crossed "n of N", label of the next point; map: one circle per known point (m.points up to
the next one: those crossed and the next, never the later ones), centred on the place, radius entry.radius,
labelled with the place label (p.mapZones, style Route). The voice is told the job (labels in order) and the verified
count, never a coordinate.
ASCII only (Kahlua lexer).
]]
local M = require 'CoreAI/CA_Missions'
local Config = require 'CoreAI/CA_MissionConfig'

local Route = {idPrefix = 'route', reportBySpeech = true, voiceName = 'route', mapStyle = 'Route',
    voiceText = 'cross several places in a given order, on foot or by vehicle, then report',
    params = {points = 'places'}}

local MIN_POINTS = 2
local lastSeen = {} -- '<mission id>|<participant>' -> { x, y } of its previous reading (memory only)

local function entry() return Config.Missions.route end

-- Position read for a participant: its vehicle when it sits in one.
function Route.position(player)
    local vehicle = player:getVehicle()
    if vehicle then return vehicle:getX(), vehicle:getY() end
    return player:getX(), player:getY()
end

local function distanceSq(px, py, x, y)
    local dx, dy = px - x, py - y
    return dx * dx + dy * dy
end

-- Squared distance from (px, py) to the segment (ax, ay)-(bx, by).
local function segmentDistanceSq(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local len = vx * vx + vy * vy
    if len == 0 then return distanceSq(px, py, ax, ay) end
    local t = math.max(0, math.min(1, ((px - ax) * vx + (py - ay) * vy) / len))
    return distanceSq(px, py, ax + t * vx, ay + t * vy)
end

-- True when the way from `from` (or nil) to (x, y) comes within the radius of the point.
function Route.crosses(point, from, x, y, c)
    local r2 = c.radius * c.radius
    if from and distanceSq(from.x, from.y, x, y) <= c.maxStep * c.maxStep then
        return segmentDistanceSq(point.x, point.y, from.x, from.y, x, y) <= r2
    end
    return distanceSq(point.x, point.y, x, y) <= r2
end

local function crossedAll(m)
    return type(m.points) == 'table' and #m.points >= MIN_POINTS and m.crossed >= #m.points
end

local function nextPoint(m)
    return type(m.points) == 'table' and m.points[m.crossed + 1] or nil
end

-- Declaration alongPoints (set-up of a voice mission, the voices' set-up): the points in order.
function Route.alongPoints(m, points)
    if type(points) ~= 'table' or #points < MIN_POINTS then return false, 'no_points' end
    m.points, m.crossed = {}, 0
    for i, p in ipairs(points) do
        m.points[i] = {id = tostring(p.id or ''), label = tostring(p.label or ''), x = math.floor(p.x),
            y = math.floor(p.y), z = math.floor(tonumber(p.z) or 0)}
    end
    return true
end

-- Bench: forget the previous readings.
function Route.resetForTests()
    lastSeen = {}
end

-- ---------------------------------------------------------------- engine interface

-- A radio voice only (its donor record carries `voice`); the points come with the set-up (alongPoints).
function Route.offer(c, npc)
    if type(npc) ~= 'table' or npc.voice == nil then return nil end
    return {kind = 'route', report = 'radio'}
end

function Route.create(m)
    m.points, m.crossed = {}, 0
    -- No delivery: the delivery commands of the notebook find nothing to accept.
    m.quantity, m.delivered, m.accepted = 0, 0, {}
end

-- Poll of a participant (server copy): crosses the next point at most.
function Route.observe(m, player, name)
    local key = tostring(m.id) .. '|' .. tostring(name)
    if player:isDead() then
        lastSeen[key] = nil
        return false
    end
    local x, y = Route.position(player)
    local from = lastSeen[key]
    lastSeen[key] = {x = x, y = y}
    local point = nextPoint(m)
    if not point or not Route.crosses(point, from, x, y, entry()) then return false end
    m.crossed = m.crossed + 1
    return true
end

function Route.reportReady(m)
    return crossedAll(m)
end

-- Only the report (payload 'speech', CA_Missions.spoken) is a contribution, once every point is crossed.
function Route.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not crossedAll(m) then return nil, 'Zone' end
    return {kind = 'report'}
end
function Route.prepare() return {kind = 'route'} end
function Route.apply() end
function Route.progress(m) return m.crossed or 0, crossedAll(m) end
function Route.complete() end

function Route.project(m, p)
    local points = type(m.points) == 'table' and m.points or {}
    local point = nextPoint(m)
    p.template, p.report = 'route', 'radio'
    p.routeDone, p.routeTotal, p.routeNext = m.crossed or 0, #points, point and point.label or nil
    if m.state ~= 'active' or not p.engaged then return end
    local r, zones = entry().radius, {}
    for i = 1, math.min(#points, (m.crossed or 0) + 1) do
        local q = points[i]
        zones[i] = {x = q.x, y = q.y, r = r, label = q.label}
    end
    p.mapZones = zones
end

-- place: label of the next point, or of the last one once all are crossed.
function Route.context(m, ctx)
    local points = type(m.points) == 'table' and m.points or {}
    local point = nextPoint(m) or points[#points]
    ctx.kind, ctx.report = 'route', 'radio'
    ctx.place = point and point.label or ''
end

local function labels(m)
    local out = {}
    for i, p in ipairs(type(m.points) == 'table' and m.points or {}) do out[i] = tostring(p.label) end
    return table.concat(out, ', then ')
end

-- E20-T02: the job told to the voice (labels in order, verified count only).
function Route.voiceBrief(m)
    local total, point = type(m.points) == 'table' and #m.points or 0, nextPoint(m)
    local left = point and ('next: ' .. tostring(point.label)) or 'all crossed'
    return {job = 'Cross these places in this order, on foot or by vehicle: ' .. labels(m)
        .. '; then report to you on this frequency.',
        facts = {'Points crossed in order (checked by the server): ' .. tostring(m.crossed or 0) .. ' of '
            .. tostring(total) .. '; ' .. left .. '.',
            'A place reached before the previous one does not count: it must be crossed again in its turn.'}}
end

M.register('route', Route)

return Route
