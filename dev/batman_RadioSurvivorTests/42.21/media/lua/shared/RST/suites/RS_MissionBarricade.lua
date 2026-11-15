-- Voice mission `barricade` (E20-T09, ADR D10) on a real building near the player. Real start path of a voice
-- (RS_MissionVoice.start, sheet with one [mission] of type barricade, count 2, and one place use=target inside the
-- building), real set-up of the target place (RS_MissionTarget), real engine poll (CA_Missions.observe: the template
-- reads the building's openings on the server), real radio report (RS_MissionVoice.report).
-- The barricades are put up as the server part of the player's gesture does (vanilla ISBarricadeAction:complete,
-- media/lua/shared/TimedActions/ISBarricadeAction.lua:109-160 in 42.22): IsoBarricade.AddBarricadeToObject(opening,
-- player) on the player's side, addPlank(player, plank) or addMetal(player, sheet), transmitCompleteItemToClients().
-- The 42.22 construction path of the context menu (ISBuildIsoEntity, BuildAction packet) needs a client cursor and is
-- not driven here.
-- Steps: one outside opening barricaded before the start (never counted), report refused at 0 of 2; a plank on a
-- second opening counts 1; a metal sheet on a third counts 2, objective met, radio report accepted. Every barricade
-- put up by the suite is removed at the end. In-memory state (store whose save does nothing): no notebook state.
require 'RST/RST'
require "RST/RST_ModRadioSurvivor"
require 'RST/RST_Fixtures'
local F = RST.Fixtures

local KHZ = 199800
local RADIUS = 40      -- tiles around the player searched for a building
local NEEDED = 3       -- free outside openings: one barricaded before the start, two during the mission

local function defKey(def)
    return def and (def:getX() .. ',' .. def:getY() .. ',' .. def:getX2() .. ',' .. def:getY2()) or nil
end

-- Free outside opening of a building on this square: { o, def, inside } or nil.
local function freeOpening(o, sq)
    if not instanceof(o, 'BarricadeAble') or not o:isBarricadeAllowed() or o:isBarricaded() then return nil end
    local other = o:getOppositeSquare()
    local a, b = sq:getBuildingDef(), other and other:getBuildingDef() or nil
    if defKey(a) == defKey(b) then return nil end
    if a then return {o = o, def = a, inside = sq} end
    return {o = o, def = b, inside = other}
end

-- Building near the player with at least NEEDED free outside openings: list of openings (same building), or nil.
local function findBuilding(p)
    local cell, px, py, pz = getCell(), math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local byDef, best = {}, nil
    for x = px - RADIUS, px + RADIUS do
        for y = py - RADIUS, py + RADIUS do
            local sq = cell:getGridSquare(x, y, pz)
            local objects = sq and sq:getObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local found = freeOpening(objects:get(i), sq)
                if found then
                    local k = defKey(found.def)
                    byDef[k] = byDef[k] or {}
                    table.insert(byDef[k], found)
                    if #byDef[k] >= NEEDED and not best then best = byDef[k] end
                end
            end
        end
    end
    return best
end

local function nail(o, p, metal, made)
    local b = IsoBarricade.AddBarricadeToObject(o, p)
    if not b then return nil end
    if metal then b:addMetal(p, instanceItem('Base.SheetMetal')) else b:addPlank(p, instanceItem('Base.Plank')) end
    if isServer() then b:transmitCompleteItemToClients() end
    made[#made + 1] = b
    return b
end

local function run(t)
    if isClient() then t:skip('authority only') end
    local M = require 'CoreAI/CA_Missions'
    local V = require 'RadioSurvivor/RS_MissionVoice'
    local B = require 'CoreAI/CA_MissionBarricade'
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local openings = findBuilding(p)
    if not openings then
        t:skip('no building with ' .. NEEDED .. ' free outside windows or doors within ' .. RADIUS .. ' tiles')
    end
    local made = {}
    t:defer(function()
        for _, b in ipairs(made) do
            local sq = b:getSquare()
            if sq then sq:transmitRemoveItemFromSquare(b) end
        end
    end, 'remove the barricades of the suite')
    local inside = openings[1].inside
    t:note('building ' .. defKey(openings[1].def) .. ', target place ' .. inside:getX() .. ',' .. inside:getY())
    t:ok(nail(openings[1].o, p, false, made) ~= nil, 'barricade before the start not put up')
    local sheet = {id = 'rst-voice-barricade', name = 'RST Voice', actions = {'say', 'start_mission'}, budgets = {},
        missions = {{id = 'secure', type = 'barricade', target = 'site', params = {count = 2}}},
        places = {{id = 'site', label = 'RST building', x = inside:getX(), y = inside:getY(), z = inside:getZ(),
            uses = {'target'}, use = {target = true}}}}
    local state = {missions = {}, npcs = {}, voiceDonors = {}, characters = {}, outcomes = {}}
    state.characters.char1 = {name = 'Tester', contacts = {}, knownMissions = {}}
    local store = {data = state, save = function() return true end}
    local m, why = V.start(store, sheet, 'char1', p, KHZ, 'barricade')
    t:ok(m ~= nil, 'barricade mission not created: ' .. tostring(why))
    local function poll()
        B.resetForTests() -- no wait between two readings of the suite
        return M.observe(state, {{player = p, character = 'char1'}}, store)
    end
    poll()
    t:eq({'barricade', 2, 0}, {m.template, m.count, m.barricaded}, 'mission at its start')
    t:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, 'report before any barricade')
    t:ok(nail(openings[2].o, p, false, made) ~= nil, 'plank barricade not put up')
    poll()
    t:eq(1, m.barricaded, 'plank barricade not counted (or the old one counted)')
    t:ok(nail(openings[3].o, p, true, made) ~= nil, 'metal barricade not put up')
    poll()
    t:eq(2, m.barricaded, 'metal barricade not counted')
    t:eq(true, M.reportReady(m), 'objective not met at the count')
    t:eq(true, V.report(store, sheet, 'char1', p, KHZ) == m, 'radio report refused at the count')
    t:eq('success', m.state)
end

RST.suite("rs.voicebarricade", {tags = {"server", "world"}, testTimeoutMs = 60000}, function(s)
    s.test('outside openings of a real building barricaded, counted by the server, then the radio report', run)
end)
