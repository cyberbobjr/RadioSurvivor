-- Objective of a radio voice mission (E25-T01, E25-T02, ADR shared places D01, D03). Authority only.
-- The [mission] section of a sheet carries its objective as data (RS_Persona): section.target = { kind = 'place', id }
-- (a shared place, point or zone) or { kind = 'near' | 'far' | 'very_far' } (a distance from the caller), with an
-- optional building (a kind of CA_Sites.KINDS) for a zone or a distance; 'near' when the section names none.
-- A.resolve turns it, once per start (RS_MissionVoice.start), into the place every template works on: the place handed
-- to the template's offer (argument aim: scout, clear, retrieve, signal) and to the set-ups (RS_MissionTarget, aimAt:
-- barricade, relay, watch, item), so that they all aim at the same spot. Only a template with an objective takes one
-- (declaration aimed, or aimAt): deliver, route or talk never draw anything.
-- A point is the objective itself. A zone or a distance is a building drawn by the common draw (CA_Sites.draw) at each
-- start, so two offers of the same section may name two buildings; the template keeps it for this requester until the
-- mission is created (CA_MissionScout.aimedSite and the others). Zone: a building whose site point lies inside the
-- rectangle. Distance: a building whose footprint lies at the band's distance (RS_Config.Targets.bands, the core
-- mod's CA_MissionConfig.Targets) from the caller's server position (IsoPlayer:getX/getY of the server copy, never a
-- client claim). Both: same habitability and known-base rules as every draw (baseDistance), the section's building
-- kind when it names one, and the template's own rule (declaration acceptSite(entry, site): clear's density), a
-- refused building being skipped for the next one. The drawn place is { id, label = kind of building in English,
-- x, y, z = its site point, kind }. Nothing found: refusal no_place.
-- One resolver per target kind, registered here or by another file (A.register): adding a kind never touches the
-- engine; one resolver per band of RS_Config.Targets.bands.
-- resolver(sheet, target, player, accept) -> place { id, label, x, y, z }, or nil and a refusal reason ([a-z_]).
-- ASCII only (Kahlua lexer).
if isClient() then return end
local Persona = require 'RadioSurvivor/RS_Persona'
local Config = require 'RadioSurvivor/RS_Config'
local Const = require 'RadioSurvivor/RadioSurvivor_Const'
local Sites = require 'CoreAI/CA_Sites'

local A = {}

local resolvers = {}

function A.register(kind, resolver)
    resolvers[kind] = resolver
    return resolver
end

-- True when the template works on an objective (offer argument aim, or set-up aimAt).
function A.wanted(t)
    return type(t) == 'table' and (t.aimed == true or t.aimAt ~= nil)
end

-- Place the section aims at for this caller (player: server copy), or nil and a refusal reason; nil and no reason for
-- a template without objective. t, entry: the template and its catalogue entry (CA_Missions.voiceTemplate).
function A.resolve(sheet, section, player, t, entry)
    if not A.wanted(t) then return nil end
    local target = type(section) == 'table' and section.target or nil
    local resolver = type(target) == 'table' and resolvers[target.kind] or nil
    if not resolver then return nil, 'no_place' end
    local accept = nil
    if type(t.acceptSite) == 'function' then
        accept = function(site) return t.acceptSite(entry, site) end
    end
    return resolver(sheet, target, player, accept)
end

-- Common draw of a building for a target (opts: around or area), as a place; nil and no_place when nothing fits.
local function drawn(sheet, target, region, accept)
    local T = Config.Targets
    local opts = {kind = target.building, minDistance = T.baseDistance, maxAttempts = T.maxAttempts,
        maxCells = T.maxCells, accept = accept, noClues = true,
        seed = tostring(sheet.id) .. ':' .. tostring(target.id or target.kind) .. ':' .. tostring(getTimestampMs())}
    for k, v in pairs(region) do opts[k] = v end
    local site, why = Sites.draw(opts)
    if not site then
        Const.log('voice ' .. tostring(sheet.id) .. ': no building for target ' .. tostring(target.id or target.kind)
            .. ' (' .. tostring(why) .. ')')
        return nil, 'no_place'
    end
    return {id = target.id or target.kind, label = site.label, x = site.x, y = site.y, z = site.z, kind = site.kind}
end

-- A shared place named by target=: a point is the objective itself; a zone draws a building inside it.
local function sharedPlace(sheet, target, _, accept)
    local place = Persona.placeOf(sheet, target.id)
    if not place then return nil, 'no_place' end
    if not place.area then return place end
    return drawn(sheet, target, {area = place.area}, accept)
end

A.register('place', sharedPlace)

-- A distance band: a building drawn around the caller's server position.
local function bandResolver(band)
    return function(sheet, target, player, accept)
        if not player then return nil, 'no_player' end
        return drawn(sheet, target, {around = {x = player:getX(), y = player:getY(), min = band.min, max = band.max}},
            accept)
    end
end

for kind, band in pairs(Config.Targets.bands) do A.register(kind, bandResolver(band)) end

return A
