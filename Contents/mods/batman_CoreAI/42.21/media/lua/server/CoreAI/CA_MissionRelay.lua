if isClient() then return end
--[[
Mission template `relay` (E20-T12, ADR D02, D10): set up a radio relay, that is a two-way radio placed high at a place
named by the giver, powered and turned on, then report by radio. Authority only. Catalogue:
CA_MissionConfig.Missions.relay (offer id relay_v1). Registered in CA_Missions (M.register); required by
RS_Carnet_Server.

Giver: a radio voice only, under the name `relay` (declaration voiceName); an NPC fiche is never offered one. The spot
is the place `target` of the voice sheet (use=target), handed over by RadioSurvivor's set-up of the templates that
declare aimAt (RS_MissionTarget). No parameter of its own.
Spot (Relay.locate): the building at the place (IsoMetaGrid:getBuildingAt(x, y, z), by the room of the tile, loaded or
not: IsoMetaGrid.java:271-280), its whole footprint (BuildingDef getX/getY, getX2/getY2 exclusive: BuildingDef.java
82-100, 189-202) from the lowest level allowed up to its roof (getMaxLevel() + 1, the roof level of the engine:
BuildingDef.java:523, 636-655); a place outside any room (a deck, a roof named as such) is a square zone of
entry.zoneHalf tiles around it, entry.zoneLevels levels high. Lowest level allowed: max(entry.minZ, level of the
place): an upper floor or the roof of a ground place, at least the place's own level when the sheet names a high
place (decision of E20-T12: the sheet says how high, without a parameter).
Radio (Relay.isRelay, vanilla objects read in the 42.22 sources): a radio object of the world (instanceof
IsoWaveSignal: a scenery radio, or the IsoRadio a player's placement adds next to the item, ISDropWorldItemAction
.lua:93-108) whose DeviceData (IsoWaveSignal.getDeviceData, IsoWaveSignal.java:142) can transmit (getIsTwoWay,
DeviceData.java:442: the TwoWay items of media/scripts/generated/items/radio.txt, walkie-talkies, ManPackRadio and ham
radios; a television or a receive-only radio never), is turned on (getIsTurnedOn, :466) and powered: by its battery
(getIsBatteryPowered, getHasBattery, getPower > 0: :257, 265, 583; a battery taken out leaves the power at 0 but
the device on until its next update, :294-306, 789-795), else by the place (canBePoweredHere, :506-530: grid power
in a room, or a generator).
State (server authority, read in the world, never a claim): m.relayed is true while such a radio stands at the spot,
m.radioAt the square where it was last seen. Each reading scans the loaded squares of the spot; when no radio is
found and the square of the last one is not loaded, the last state is kept (an unloaded radio cannot be read:
IsoWaveSignal.removeFromWorld, IsoWaveSignal.java:331-338). Read by the engine poll of a participant
(CA_Missions.observe, once a second on the server) at most every entry.scanMs per mission, and again when the report
is checked, so that a radio turned off, unpowered or taken away refuses the report at once.
Objective met while m.relayed (reportReady): the mission waits "to report" and succeeds by the report on the voice's
frequency (RS_MissionVoice.report, CA_Missions.spoken). Notebook (MissionViews/CA_View_Relay): place
label, lowest level, yes/no; map: a circle around the spot (m.mapZone, style Relay). The voice is told the job and the
verified yes/no, never a coordinate.
ASCII only (Kahlua lexer).
]]
local M = require 'CoreAI/CA_Missions'
local Config = require 'CoreAI/CA_MissionConfig'
local Clear = require 'CoreAI/CA_MissionClear' -- Clear.zone: circle around the spot's bounds

local Relay = {idPrefix = 'relay', reportBySpeech = true, voiceName = 'relay', mapStyle = 'Relay',
    voiceText = 'set up a powered two-way radio, turned on, on an upper floor or the roof of a place'}

local scannedAt = {} -- mission id -> real ms of its last reading (memory only)

local function entry() return Config.Missions.relay end

local function powered(d)
    if d:getIsBatteryPowered() then return d:getHasBattery() and d:getPower() > 0 end
    return d:canBePoweredHere()
end

-- True for a two-way radio object of the world, turned on and powered.
function Relay.isRelay(o)
    if not instanceof(o, 'IsoWaveSignal') then return false end
    local d = o:getDeviceData()
    return d ~= nil and d:getIsTwoWay() and d:getIsTurnedOn() and powered(d)
end

local function hasRelay(sq)
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        if Relay.isRelay(objects:get(i)) then return true end
    end
    return false
end

-- Square { x, y, z } of a relay on the loaded squares of the spot, or nil.
function Relay.find(site)
    local cell = getCell()
    for z = site.zMin, site.zMax do
        for x = site.x1, site.x2 - 1 do
            for y = site.y1, site.y2 - 1 do
                local sq = cell:getGridSquare(x, y, z)
                if sq and hasRelay(sq) then return {x = x, y = y, z = z} end
            end
        end
    end
    return nil
end

local function loaded(at)
    return type(at) == 'table' and getCell():getGridSquare(at.x, at.y, at.z) ~= nil
end

-- Updates m.relayed and m.radioAt from the world; true when m.relayed changed.
function Relay.scan(m)
    if type(m.site) ~= 'table' then return false end
    local was = m.relayed == true
    local at = Relay.find(m.site)
    if at then
        m.relayed, m.radioAt = true, at
    elseif m.radioAt == nil or loaded(m.radioAt) then
        m.relayed, m.radioAt = false, nil
    end
    return (m.relayed == true) ~= was
end

-- Spot of a place of the sheet ({ x, y, z, label }): bounds and levels.
function Relay.locate(place, c)
    local z = math.floor(tonumber(place.z) or 0)
    local minZ = math.max(c.minZ, z)
    local world = getWorld()
    local grid = world and world:getMetaGrid()
    local def = grid and grid:getBuildingAt(place.x, place.y, z)
    if def then
        return {x1 = def:getX(), y1 = def:getY(), x2 = def:getX2(), y2 = def:getY2(), zMin = minZ,
            zMax = math.max(minZ, def:getMaxLevel() + 1)}
    end
    local x, y, h = math.floor(place.x), math.floor(place.y), c.zoneHalf
    return {x1 = x - h, y1 = y - h, x2 = x + h + 1, y2 = y + h + 1, zMin = minZ, zMax = minZ + c.zoneLevels - 1}
end

-- Declaration aimAt (set-up of a voice mission with a target place, RadioSurvivor's RS_MissionTarget): the spot at
-- `place`; also called on a scratch table to check a section before the mission exists. Returns true.
function Relay.aimAt(m, place)
    local c = entry()
    local site = Relay.locate(place, c)
    m.site, m.minZ, m.place = site, site.zMin, tostring(place.label or '')
    m.mapZone = Clear.zone(site, c)
    m.relayed, m.radioAt = false, nil
    Relay.scan(m)
    return true
end

-- Bench: forget the reading times.
function Relay.resetForTests()
    scannedAt = {}
end

-- ---------------------------------------------------------------- engine interface

-- A radio voice only (its donor record carries `voice`); the spot comes with the set-up (aimAt).
function Relay.offer(c, npc)
    if type(npc) ~= 'table' or npc.voice == nil then return nil end
    return {kind = 'relay', report = 'radio'}
end

function Relay.create(m, c)
    m.relayed, m.minZ, m.place = false, c.minZ, ''
    -- No delivery: the delivery commands of the notebook find nothing to accept.
    m.quantity, m.delivered, m.accepted = 0, 0, {}
end

-- Poll of a participant (server copy): reads the spot at most every scanMs.
function Relay.observe(m)
    local now = getTimestampMs()
    local last = scannedAt[m.id]
    if last and now - last < entry().scanMs then return false end
    scannedAt[m.id] = now
    return Relay.scan(m)
end

function Relay.reportReady(m)
    return m.relayed == true
end

-- Only the report (payload 'speech', CA_Missions.spoken) is a contribution, while the relay stands: read again here.
function Relay.check(m, player, payload)
    if payload ~= 'speech' then return nil, 'State' end
    Relay.scan(m)
    if not Relay.reportReady(m) then return nil, 'Zone' end
    return {kind = 'report'}
end
function Relay.prepare() return {kind = 'relay'} end
function Relay.apply() end
function Relay.progress(m) return m.relayed and 1 or 0, Relay.reportReady(m) end
function Relay.complete() end

function Relay.project(m, p)
    p.template, p.place, p.report = 'relay', m.place or '', 'radio'
    p.relayed, p.minZ = m.relayed == true, m.minZ or 1
    local z = m.mapZone
    if type(z) == 'table' and m.state == 'active' and p.engaged then p.mapZone = {x = z.x, y = z.y, r = z.r} end
end

function Relay.context(m, ctx)
    ctx.kind, ctx.place, ctx.report = 'relay', m.place, 'radio'
    ctx.relayed = m.relayed == true
end

-- E20-T02: the job told to the voice (verified yes/no only).
function Relay.voiceBrief(m)
    local levels = m.minZ or 1
    return {job = 'Set up a two-way radio (walkie-talkie or ham radio), turned on and powered, at least '
        .. tostring(levels) .. ' floor(s) above the ground in or on ' .. tostring(m.place)
        .. ', then report to you on this frequency.',
        facts = {'A powered radio is on at the spot (checked by the server): ' .. (m.relayed and 'yes' or 'no') .. '.',
            'A radio turned off, without power or taken away stops counting.'}}
end

M.register('relay', Relay)

return Relay
