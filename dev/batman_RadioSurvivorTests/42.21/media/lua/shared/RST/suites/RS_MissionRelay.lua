-- Voice mission `relay` (E20-T12, ADR D10) on a real building with an upper floor near the player. Real start path of
-- a voice (RS_MissionVoice.start, sheet with one [mission] of type relay and one place use=target on the upper floor),
-- real set-up of the target place (RS_MissionTarget), real engine poll (CA_Missions.observe: the template reads the
-- radios of the spot on the server), real radio report (RS_MissionVoice.report).
-- The radio is placed as the server part of the player's placement does (vanilla ISDropWorldItemAction:complete,
-- media/lua/shared/TimedActions/ISDropWorldItemAction.lua:81-108 in 42.22): AddWorldInventoryItem, then an IsoRadio
-- on the same square holding the item's DeviceData, AddSpecialObject, transmitCompleteItemToClients. It is switched
-- on and off through the server path of the RadioDeviceDataState packet (DeviceData.setIsTurnedOn,
-- DeviceData.java:1095-1100), which checks the power itself. A walkie-talkie with a full battery (Base.WalkieTalkie3:
-- TwoWay, UsesBattery, media/scripts/generated/items/radio.txt).
-- Steps: report refused before any radio; radio placed and turned on: objective met; turned off: report refused;
-- turned on again: radio report accepted. The radio and its item are removed at the end. In-memory state (store whose
-- save does nothing): no notebook state.
require 'RST/RST'
require "RST/RST_ModRadioSurvivor"
require 'RST/RST_Fixtures'
local F = RST.Fixtures

local KHZ = 199800
local RADIUS = 40      -- tiles around the player searched for an upper floor
local LEVEL = 1        -- upper floor searched

-- Square of a room on the upper floor of a building near the player, or nil.
local function findUpperFloor(p)
    local cell, px, py = getCell(), math.floor(p:getX()), math.floor(p:getY())
    for d = 0, RADIUS do
        for x = px - d, px + d do
            for y = py - d, py + d do
                if math.max(math.abs(x - px), math.abs(y - py)) == d then
                    local sq = cell:getGridSquare(x, y, LEVEL)
                    if sq and sq:getRoom() ~= nil and sq:getBuildingDef() ~= nil then return sq end
                end
            end
        end
    end
    return nil
end

-- Walkie-talkie placed on sq as the server part of a placement leaves it: { item, radio }.
local function placeRadio(sq)
    local item = instanceItem('Base.WalkieTalkie3')
    local d = item:getDeviceData()
    d:setHasBattery(true); d:setPower(1.0)
    local placed = sq:AddWorldInventoryItem(item, 0.5, 0.5, 0, false)
    if placed and placed:getWorldItem() then placed:getWorldItem():transmitCompleteItemToClients() end
    local radio = IsoRadio.new(getCell(), sq, nil)
    radio:setDeviceData(d)
    radio:getModData().RadioItemID = item:getID()
    sq:AddSpecialObject(radio, sq:getObjects():size())
    radio:transmitCompleteItemToClients()
    radio:transmitModData()
    return {item = placed, radio = radio}
end

local function run(t)
    if isClient() then t:skip('authority only') end
    local M = require 'CoreAI/CA_Missions'
    local V = require 'RadioSurvivor/RS_MissionVoice'
    local R = require 'CoreAI/CA_MissionRelay'
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local sq = findUpperFloor(p)
    if not sq then t:skip('no building with a loaded upper floor within ' .. RADIUS .. ' tiles') end
    local placed = nil
    t:defer(function()
        if not placed then return end
        local wi = placed.item and placed.item:getWorldItem()
        sq:transmitRemoveItemFromSquare(placed.radio)
        if wi then sq:transmitRemoveItemFromSquare(wi) end
    end, 'remove the radio of the suite')
    t:note('upper floor ' .. sq:getX() .. ',' .. sq:getY() .. ',' .. sq:getZ())
    local sheet = {id = 'rst-voice-relay', name = 'RST Voice', actions = {'say', 'start_mission'}, budgets = {},
        missions = {{id = 'relay', type = 'relay', target = 'site', params = {}}},
        places = {{id = 'site', label = 'RST building', x = sq:getX(), y = sq:getY(), z = sq:getZ(),
            uses = {'target'}, use = {target = true}}}}
    local state = {missions = {}, npcs = {}, voiceDonors = {}, characters = {}, outcomes = {}}
    state.characters.char1 = {name = 'Tester', contacts = {}, knownMissions = {}}
    local store = {data = state, save = function() return true end}
    local m, why = V.start(store, sheet, 'char1', p, KHZ, 'relay')
    t:ok(m ~= nil, 'relay mission not created: ' .. tostring(why))
    local function poll()
        R.resetForTests() -- no wait between two readings of the suite
        return M.observe(state, {{player = p, character = 'char1'}}, store)
    end
    poll()
    t:eq({'relay', LEVEL, false}, {m.template, m.minZ, m.relayed}, 'mission at its start')
    t:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, 'report before any radio')
    placed = placeRadio(sq)
    local d = placed.radio:getDeviceData()
    d:setIsTurnedOn(true)
    t:eq(true, d:getIsTurnedOn(), 'radio not switched on by the server path')
    poll()
    t:eq(true, M.reportReady(m), 'powered radio turned on upstairs not counted')
    d:setIsTurnedOn(false)
    poll()
    t:eq(false, M.reportReady(m), 'radio turned off still counted')
    t:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, 'report accepted with the radio off')
    d:setIsTurnedOn(true)
    poll()
    t:eq(true, V.report(store, sheet, 'char1', p, KHZ) == m, 'radio report refused with the radio on')
    t:eq('success', m.state)
end

RST.suite("rs.voicerelay", {tags = {"server", "world"}, testTimeoutMs = 60000}, function(s)
    s.test('powered radio turned on upstairs in a real building, read by the server, off refused, then the report', run)
end)
