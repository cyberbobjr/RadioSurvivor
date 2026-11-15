if isClient() then return end
--[[
Mission template `barricade` (E20-T09, ADR D02, D10): barricade `count` outside windows and doors of a building named
by the giver. Authority only. Catalogue: RC_MissionConfig.Missions.barricade (offer id barricade_v1). Registered in
RC_Missions (M.register); required by RS_Carnet_Server.

Giver: a radio voice only, under the name `barricade` (declaration voiceName); an NPC fiche is never offered one. The
building is the one at the place `target` of the voice sheet (use=target), handed over by RadioSurvivor's set-up of
the templates that declare aimAt (RS_MissionTarget): Barricade.aimAt(m, place, params) finds the building on the
metagrid (IsoMetaGrid:getBuildingAt(x, y, z), by the room of the tile, loaded or not: IsoMetaGrid.java:271-280) and
keeps its bounds (BuildingDef getX/getY, getX2/getY2 exclusive, getMinLevel..getMaxLevel: BuildingDef.java:82-100,
189-202). Parameter count (sheet, kind count; default entry.count), at least 1. Refusals: no_building (no room at the
place), bad_count.
Openings (vanilla barricades read in the 42.22 sources): every object of the building's squares, bounds widened by one tile to
the south and east (the south and east walls are carried by the squares outside the rectangle), every floor, that is
BarricadeAble (instanceof on the interface, as vanilla MOBarricade.lua:15 does: IsoWindow, IsoDoor, IsoWindowFrame,
IsoThumpable) and allows a barricade (isBarricadeAllowed:
double and garage doors refused, IsoDoor.java:1604-1606; a frame holding a window refused, the window counts:
IsoWindowFrame.java:104-106; a built door or window only when canBarricade, IsoThumpable.java:1497). Only the outside
ones count: one side of the edge (square of the object, getOppositeSquare: GridSquareEdgeElement.java:17-20) inside
the building, the other outside (no room, another building, or no square at all: an upper floor); a square is inside
when getBuildingDef() (by its room, IsoGridSquare.java:7813-7816) has the bounds of the mission's building. One
opening = one edge (square, floor, N or W), whatever its objects.
Barricaded: a barricade of either side (getBarricadeOnSameSquare / OnOppositeSquare, IsoDoor.java:1584-1592) with at
least one plank (getNumPlanks), a metal sheet (isMetal) or metal bars (isMetalBar) (IsoBarricade.java:138-145, 208,
230). Planks and metal count the same, an opening counts once.
Count (server authority, read in the world, never a claim): m.openings[edge] = 'pre' (barricaded when first seen),
'open' or 'done' (barricaded since); m.barricaded = number of 'done'. The first reading is taken when the mission is
set up, and for each opening whose square was not loaded then, at the first reading where it is: an opening first
seen barricaded is never counted. A barricade removed again stops counting. Squares not loaded keep their last state
(the count of an unloaded building stays the last verified one). Read by the engine poll of a participant
(RC_Missions.observe, once a second on the server) at most every entry.scanMs per mission.
Objective met when m.barricaded >= m.count (reportReady): the mission waits "to report" and succeeds by the report on
the voice's frequency (RS_MissionVoice.report, RC_Missions.spoken). Notebook (RadioSurvivor MissionViews/
RS_View_Barricade): place label, count; map: a circle around the building (m.mapZone, style Barricade). The voice is
told the job and the verified count, never a coordinate.
ASCII only (Kahlua lexer).
]]
local M = require 'RadioSurvivorCore/RC_Missions'
local Config = require 'RadioSurvivorCore/RC_MissionConfig'
local Clear = require 'RadioSurvivorCore/RC_MissionClear' -- Clear.zone: circle around a building's bounds

local Barricade = {idPrefix = 'barricade', reportBySpeech = true, voiceName = 'barricade', mapStyle = 'Barricade',
    voiceText = 'barricade the outside windows and doors of a building',
    -- E20-T03: sheet values of its mission section; the building is the common key target (a place with use=target).
    params = {count = 'count'}}

local scannedAt = {} -- mission id -> real ms of its last reading (memory only)

local function entry() return Config.Missions.barricade end

-- True when the square lies in the building of these bounds (by its room).
local function inside(sq, site)
    local def = sq and sq:getBuildingDef()
    return def ~= nil and def:getX() == site.x1 and def:getY() == site.y1 and def:getX2() == site.x2
        and def:getY2() == site.y2
end

local function closes(b)
    return b ~= nil and (b:getNumPlanks() > 0 or b:isMetal() or b:isMetalBar())
end

-- Edge key of an outside opening of the building, or nil.
local function outsideEdge(o, sq, site)
    if not instanceof(o, 'BarricadeAble') or not o:isBarricadeAllowed() then return nil end
    if inside(sq, site) == inside(o:getOppositeSquare(), site) then return nil end
    return sq:getX() .. ',' .. sq:getY() .. ',' .. sq:getZ() .. ',' .. (o:isNorth() and 'N' or 'W')
end

-- Reads one loaded square into seen[edge] = barricaded.
local function readSquare(sq, site, seen)
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        local edge = outsideEdge(o, sq, site)
        if edge then
            seen[edge] = seen[edge] == true or closes(o:getBarricadeOnSameSquare()) or closes(o:getBarricadeOnOppositeSquare())
        end
    end
end

-- Openings of the loaded squares of the building: { [edge] = barricaded }.
function Barricade.read(site)
    local seen, cell = {}, getCell()
    for z = site.zMin, site.zMax do
        for x = site.x1, site.x2 do
            for y = site.y1, site.y2 do
                local sq = cell:getGridSquare(x, y, z)
                if sq then readSquare(sq, site, seen) end
            end
        end
    end
    return seen
end

-- Updates m.openings and m.barricaded from the world; true when the count changed.
function Barricade.scan(m)
    if type(m.site) ~= 'table' then return false end
    m.openings = type(m.openings) == 'table' and m.openings or {}
    for edge, closed in pairs(Barricade.read(m.site)) do
        local was = m.openings[edge]
        if was == nil then
            m.openings[edge] = closed and 'pre' or 'open'
        elseif was ~= 'pre' then
            m.openings[edge] = closed and 'done' or 'open'
        end
    end
    local n = 0
    for _, state in pairs(m.openings) do
        if state == 'done' then n = n + 1 end
    end
    local changed = n ~= (m.barricaded or 0)
    m.barricaded = n
    return changed
end

-- Building at a place of the sheet ({ x, y, z, label }): bounds and floors, or nil and the refusal reason.
function Barricade.locate(place)
    local world = getWorld()
    local grid = world and world:getMetaGrid()
    local def = grid and grid:getBuildingAt(place.x, place.y, place.z or 0)
    if not def then return nil, 'no_building' end
    return {x1 = def:getX(), y1 = def:getY(), x2 = def:getX2(), y2 = def:getY2(), zMin = def:getMinLevel(),
        zMax = def:getMaxLevel()}
end

-- Declaration aimAt (set-up of a voice mission with a target place, RadioSurvivor's RS_MissionTarget): the building
-- at `place` and the count of `params`; also called on a scratch table to check a section before the mission exists.
-- Returns true, or false and the reason ([a-z_]).
function Barricade.aimAt(m, place, params)
    local c = entry()
    local count = type(params) == 'table' and params.count or c.count
    if type(count) ~= 'number' or count < 1 then return false, 'bad_count' end
    local site, why = Barricade.locate(place)
    if not site then return false, why end
    m.site, m.count, m.place = site, count, tostring(place.label or '')
    m.mapZone = Clear.zone(site, c)
    m.openings, m.barricaded = {}, 0
    Barricade.scan(m)
    return true
end

-- Bench: forget the reading times.
function Barricade.resetForTests()
    scannedAt = {}
end

-- ---------------------------------------------------------------- engine interface

-- A radio voice only (its donor record carries `voice`); the place comes with the set-up (aimAt).
function Barricade.offer(c, npc)
    if type(npc) ~= 'table' or npc.voice == nil then return nil end
    return {kind = 'barricade', report = 'radio'}
end

function Barricade.create(m, c)
    m.count, m.barricaded, m.openings, m.place = c.count, 0, {}, ''
    -- No delivery: the delivery commands of the notebook find nothing to accept.
    m.quantity, m.delivered, m.accepted = 0, 0, {}
end

-- Poll of a participant (server copy): reads the building at most every scanMs.
function Barricade.observe(m)
    local now = getTimestampMs()
    local last = scannedAt[m.id]
    if last and now - last < entry().scanMs then return false end
    scannedAt[m.id] = now
    return Barricade.scan(m)
end

function Barricade.reportReady(m)
    return (m.barricaded or 0) >= (m.count or 1)
end

-- Only the report (payload 'speech', RC_Missions.spoken) is a contribution, once the count is reached.
function Barricade.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    if not Barricade.reportReady(m) then return nil, 'Zone' end
    return {kind = 'report'}
end
function Barricade.prepare() return {kind = 'barricade'} end
function Barricade.apply() end
function Barricade.progress(m) return m.barricaded or 0, Barricade.reportReady(m) end
function Barricade.complete() end

function Barricade.project(m, p)
    p.template, p.place, p.report = 'barricade', m.place or '', 'radio'
    p.barricaded, p.count = m.barricaded or 0, m.count or 0
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Barricade.context(m, ctx)
    ctx.kind, ctx.place, ctx.report = 'barricade', m.place, 'radio'
    ctx.barricaded, ctx.count = m.barricaded or 0, m.count or 0
end

-- E20-T02: the job told to the voice (verified count only).
function Barricade.voiceBrief(m)
    local count = m.count or 0
    return {job = 'Barricade ' .. tostring(count) .. ' outside windows or doors of ' .. tostring(m.place)
        .. ' (planks or metal, from inside or outside), then report to you on this frequency.',
        facts = {'Openings barricaded since the mission started (checked by the server): '
            .. tostring(m.barricaded or 0) .. ' of ' .. tostring(count) .. '.',
            'Openings already barricaded when the mission started do not count; a barricade removed again stops '
            .. 'counting.'}}
end

M.register('barricade', Barricade)

return Barricade
