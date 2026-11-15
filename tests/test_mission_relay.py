"""Type de mission `relay` (E20-T12, ADR D10) : poser une radio émettrice (talkie-walkie ou HAM), alimentée et allumée,
en hauteur dans le lieu `target` de la fiche d'une voix ; état lu par le serveur dans le monde, compte rendu à la radio.

    python RadioSurvivor/tests/test_mission_relay.py

Vrai RadioSurvivor_Server, vrai CA_NotebookServer (gabarit CA_MissionRelay inscrit au chargement), vrai RS_MissionVoice
(départ et compte rendu d'une voix), vrai RS_MissionTarget (lieu target), vrai RS_Persona (lecture de la fiche), vrai
client du carnet ; doublures du monde fidèles au Java 42.22 relevé (RELAY_WORLD). Preuve de la logique Lua, pas de
l'API Java réelle ni du réseau : la suite en jeu rs.voicerelay le confirme sur un serveur dédié.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import test_carnet as carnet_helpers
from test_carnet import MAP_DOUBLE, NOTEBOOK_UI, bridge_module, convert
from test_mission_clear import CLEAR_WORLD
from test_personas import LuaPersona
from test_persona_sections import BASE, PROMPT
import npc_protocol as protocol

ROOT = Path(__file__).resolve().parents[1]
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
TESTS_LUA = tests_lua()
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_MissionRelay.lua'

# Doublures du monde, fidèles au Java 42.22 (E:\pz-source-42.22\java\zombie, relevé du 2026-11-15) :
# - IsoMetaGrid.getBuildingAt(x, y, z) (IsoMetaGrid.java:271-280) : bâtiment de la pièce de la case, nil hors de toute
#   pièce ; BuildingDef getX/getY, getX2/getY2 exclusifs, getMinLevel/getMaxLevel (BuildingDef.java:82-100, 189-202) ;
#   le toit est au niveau getMaxLevel() + 1 (BuildingDef.java:523, getRoofRoomID :636-655).
# - IsoCell.getGridSquare(x, y, z) : nil pour une case non chargée ; IsoGridSquare getObjects (liste Java depuis 0),
#   getRoom (:7789), getBuildingDef (:7813-7816, par la pièce), hasGridPower (:10139-10141 : réseau du monde),
#   haveElectricity (:8214-8219 : générateur), AddSpecialObject (:4956), AddWorldInventoryItem (:5201),
#   transmitRemoveItemFromSquare (:5073-5100).
# - IsoRadio / IsoWaveSignal (IsoWaveSignal.java:67-100, 142-156) : un objet sans sprite reçoit un DeviceData neuf
#   (non émetteur, à pile pleine) ; setDeviceData remplace le DeviceData et en devient le parent.
# - DeviceData (radio/devices/DeviceData.java) : getIsTwoWay (:442), getIsTurnedOn (:466), setIsTurnedOn (:470-490 :
#   refusé sans courant ou pile vide, éteint alors l'appareil), setTurnedOnRaw (:497), getIsBatteryPowered (:257),
#   getHasBattery (:265), getPower / setPower (:583-595, borné 0..1), canBePoweredHere (:506-530 : toujours vrai à pile ;
#   secteur = réseau, ou générateur, et sans générateur seulement dans une pièce), getBattery (:294-306 : retire la
#   pile, puissance 0, sans éteindre : DeviceData.update l'éteint au tick suivant, :789-795).
# - Objets vanilla émetteurs (media/scripts/generated/items/radio.txt, TwoWay = true) : WalkieTalkie1..5,
#   WalkieTalkieMakeShift, ManPackRadio, HamRadio1, HamRadio2, HamRadioMakeShift, tous à pile (UsesBattery = true).
RELAY_WORLD = r'''
LOADED, GRID_ON, GENERATORS = true, true, {}
local squares = {}
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
-- Test classes named after their Java class (checked by tests/test_doubles_api.py); instanceof reads __javaName and
-- the Java supertypes (IsoRadio and IsoTelevision extend IsoWaveSignal).
local SUPER = {IsoRadio = {IsoWaveSignal = true, IsoObject = true}, IsoTelevision = {IsoWaveSignal = true, IsoObject = true},
    IsoWorldInventoryObject = {IsoObject = true}, Radio = {InventoryItem = true}}
local function class(name)
    local c = {__javaName = name}
    c.__index = c
    return c
end
local List = class('ArrayList')
function List:size() return #self.items end
function List:get(i) local v = self.items[i + 1]; if v == nil then error('IndexOutOfBounds ' .. i) end; return v end
local Def = class('BuildingDef')
function Def:getX() return self.x1 end
function Def:getY() return self.y1 end
function Def:getX2() return self.x2 end
function Def:getY2() return self.y2 end
function Def:getMinLevel() return self.zMin end
function Def:getMaxLevel() return self.zMax end
-- Two-storey house x 300..305, y 300..304, floors 0 and 1, roof at level 2.
TOWER = setmetatable({x1 = 300, y1 = 300, x2 = 306, y2 = 305, zMin = 0, zMax = 1}, Def)
local function inTower(x, y, z)
    return x >= TOWER.x1 and x < TOWER.x2 and y >= TOWER.y1 and y < TOWER.y2 and z >= TOWER.zMin and z <= TOWER.zMax
end
local Grid = class('IsoMetaGrid')
function Grid:getBuildingAt(x, y, z)
    if z == nil then error('getBuildingAt(x, y) reads the bounds only: use the room variant (x, y, z)') end
    if inTower(math.floor(x), math.floor(y), math.floor(z)) then return TOWER end
    return nil
end
SCOUT_GRID.getBuildingAt = Grid.getBuildingAt
local Room = class('IsoRoom')
local ROOM = setmetatable({}, Room)
local Sq = class('IsoGridSquare')
function Sq:getX() return self.x end
function Sq:getY() return self.y end
function Sq:getZ() return self.z end
function Sq:getObjects() return setmetatable({items = self.objects}, List) end
function Sq:getRoom() if inTower(self.x, self.y, self.z) then return ROOM end return nil end
function Sq:getBuildingDef() if inTower(self.x, self.y, self.z) then return TOWER end return nil end
function Sq:hasGridPower() return GRID_ON end
function Sq:haveElectricity() return GENERATORS[key(self.x, self.y, self.z)] == true end
function Sq:AddSpecialObject(obj, index)
    table.insert(self.objects, math.min(index, #self.objects) + 1, obj)
    obj.square = self
end
-- Server: removed for every client (GameServer.RemoveItemFromMap), index in the square.
function Sq:transmitRemoveItemFromSquare(obj)
    for i = #self.objects, 1, -1 do
        if self.objects[i] == obj then table.remove(self.objects, i); obj.square = nil; return i - 1 end
    end
    return -1
end
local WorldItem = class('IsoWorldInventoryObject')
function WorldItem:getSquare() return self.square end
function WorldItem:getItem() return self.item end
TRANSMITTED = 0
function WorldItem:transmitCompleteItemToClients() TRANSMITTED = TRANSMITTED + 1 end
function Sq:AddWorldInventoryItem(item, x, y, height, transmit)
    local w = setmetatable({item = item, square = self}, WorldItem)
    self.objects[#self.objects + 1] = w
    item.worldItem = w
    return item
end
local function square(x, y, z)
    if not LOADED or z < 0 or z > 7 then return nil end
    local k = key(x, y, z)
    squares[k] = squares[k] or setmetatable({x = x, y = y, z = z, objects = {}}, Sq)
    return squares[k]
end
local Cell = class('IsoCell')
function Cell:getGridSquare(x, y, z) return square(x, y, z) end
local cell = getCell()
cell.getGridSquare = Cell.getGridSquare
getCell = function() return cell end
local baseInstanceof = instanceof
instanceof = function(o, c)
    local mt = type(o) == 'table' and getmetatable(o) or nil
    local k = type(mt) == 'table' and rawget(mt, '__javaName') or nil
    if k == nil then return baseInstanceof(o, c) end
    return k == c or (SUPER[k] or {})[c] == true
end
local Device = class('DeviceData')
function Device:getParent() return self.parent end
function Device:setParent(p) self.parent = p end
function Device:getIsTwoWay() return self.twoWay end
function Device:setIsTwoWay(b) self.twoWay = b end
function Device:getIsTurnedOn() return self.on end
function Device:setTurnedOnRaw(b) self.on = b end
function Device:getIsBatteryPowered() return self.batteryPowered end
function Device:setIsBatteryPowered(b) self.batteryPowered = b end
function Device:getHasBattery() return self.hasBattery end
function Device:setHasBattery(b) self.hasBattery = b end
function Device:getPower() return self.power end
function Device:setPower(p) self.power = math.max(0, math.min(1, p)) end
function Device:canBePoweredHere()
    if self.batteryPowered then return true end
    local sq = self.parent and self.parent:getSquare()
    if sq == nil then return false end
    if sq:haveElectricity() then return true end
    return sq:hasGridPower() and sq:getRoom() ~= nil
end
function Device:setIsTurnedOn(b)
    if self:canBePoweredHere() then
        self.on = b and (not self.batteryPowered or self.power > 0)
    else
        self.on = false
    end
end
function Device:getBattery(inventory)
    if self.hasBattery then self.power, self.hasBattery = 0, false end
end
-- DeviceData of a vanilla two-way radio item (radio.txt: TwoWay, UsesBattery), battery full.
local function twoWayDevice(fields)
    local d = setmetatable({twoWay = true, on = false, batteryPowered = true, hasBattery = true, power = 1.0}, Device)
    for k, v in pairs(fields or {}) do d[k] = v end
    return d
end
local Iso = class('IsoRadio')
function Iso:getDeviceData() return self.data end
function Iso:setDeviceData(d) self.data = d; d:setParent(self) end
function Iso:getSquare() return self.square end
function Iso:getModData() self.md = self.md or {}; return self.md end
function Iso:transmitCompleteItemToClients() TRANSMITTED = TRANSMITTED + 1 end
function Iso:transmitModData() end
-- IsoRadio(cell, square, nil): new DeviceData (not two-way, full battery), square of the object (IsoObject ctor).
IsoRadio = {new = function(c, sq, sprite)
    local r = setmetatable({square = sq}, Iso)
    r:setDeviceData(twoWayDevice({twoWay = false}))
    return r
end}
local Tv = class('IsoTelevision')
for k, v in pairs(Iso) do if type(v) == 'function' then rawset(Tv, k, v) end end
-- Radio placed on a square of the world (as ISDropWorldItemAction:complete leaves it), switched on through the
-- server path (DeviceData.setIsTurnedOn).
function placeRadio(x, y, z, fields, javaClass)
    local sq = square(x, y, z)
    local r = setmetatable({square = sq}, javaClass == 'IsoTelevision' and Tv or Iso)
    r:setDeviceData(twoWayDevice(fields))
    sq.objects[#sq.objects + 1] = r
    r:getDeviceData():setIsTurnedOn(true)
    return r
end
function removeRadio(r) r.square:transmitRemoveItemFromSquare(r) end
-- Inventory radio item (zombie.inventory.types.Radio) of instanceItem, for the in-game suite run at the bench.
local Item = class('Radio')
function Item:getDeviceData() return self.data end
function Item:getID() return self.id end
function Item:getFullType() return self.fullType end
function Item:getWorldItem() return self.worldItem end
local baseInstanceItem, ids = instanceItem, 900
instanceItem = function(fullType)
    if string.find(fullType, 'WalkieTalkie', 1, true) then
        ids = ids + 1
        local it = setmetatable({fullType = fullType, id = ids}, Item)
        it.data = twoWayDevice()
        it.data:setParent(it)
        return it
    end
    return baseInstanceItem(fullType)
end
function radiosLeft()
    local n = 0
    for _, sq in pairs(squares) do
        for _, o in ipairs(sq.objects) do if instanceof(o, 'IsoWaveSignal') or instanceof(o, 'IsoWorldInventoryObject') then n = n + 1 end end
    end
    return n
end
'''

# Fiche d'une voix qui donne la mission relay : la maison à étage, un lieu hors de tout bâtiment, un lieu en hauteur.
SHEET_PLACES = [
    {'id': 'house', 'x': 302, 'y': 302, 'z': 0, 'label': 'Hilltop house', 'uses': ['target'], 'use': {'target': True}},
    {'id': 'deck', 'x': 400, 'y': 400, 'z': 2, 'label': 'Overpass', 'uses': ['target'], 'use': {'target': True}},
]


class RelayMissionTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def world(self, name):
        sim = self.voice_sim(name)
        rt = sim.server.rt
        rt.execute(CLEAR_WORLD)
        rt.execute(RELAY_WORLD)
        # The game loads every server file of the mod: the set-up of the target place registers itself (no require).
        rt.eval("require('RadioSurvivor/RS_MissionTarget')")
        return sim, rt.eval("require('RadioSurvivor/RS_MissionVoice')"), rt.eval("require('CoreAI/CA_NotebookStore')")

    def sheet(self, sim, section):
        rt = sim.server.rt
        places = [rt.table_from({**p, 'uses': rt.table_from(p['uses']), 'use': rt.table_from(p['use'])})
                  for p in SHEET_PLACES]
        fields = dict(section)
        fields['params'] = rt.table_from(section.get('params', {}))
        fields.setdefault('type', 'relay')
        fields.setdefault('id', 'relay')
        return rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from([rt.table_from(fields)]),
                              'places': rt.table_from(places)})

    def start(self, sim, voice, store, sheet):
        return voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, 'relay')

    def poll(self, sim, store):
        """Server poll of the engine (CA_Missions.observe) with the server copy of alice, after the scan delay."""
        sim.clock.offset += 5000
        present = sim.server.rt.table_from([sim.server.rt.table_from(
            {'player': sim.server.g.PLAYERS.alice, 'character': sim.character('alice')})])
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").observe(store.data, present, store)

    def report(self, sim, voice, store, sheet):
        return voice.report(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)

    def ready(self, sim, m):
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").reportReady(m)

    def started(self, name, target='house'):
        sim, voice, store = self.world(name)
        sheet = self.sheet(sim, {'target': target})
        m = self.start(sim, voice, store, sheet)
        self.assertFalse(isinstance(m, tuple), str(m))
        return sim, voice, store, sheet, m

    def place(self, sim, x, y, z, **fields):
        return sim.server.g.placeRadio(x, y, z, sim.server.rt.table_from(fields), None)

    def test_mission_is_given_by_a_voice_on_the_building_of_the_target_place(self):
        sim, voice, store, sheet, m = self.started('relay-start')
        self.assertEqual((m.template, m.donor, m.report, m.state), ('relay', 'voice', 'radio', 'active'))
        self.assertEqual((m.place, m.minZ, m.relayed), ('Hilltop house', 1, False))
        self.assertEqual((m.site.x1, m.site.y1, m.site.x2, m.site.y2, m.site.zMin, m.site.zMax),
                         (300, 300, 306, 305, 1, 2))
        self.assertFalse(self.ready(sim, m))
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))

    def test_powered_two_way_radio_on_an_upper_floor_or_the_roof_is_counted(self):
        for z in (1, 2):
            with self.subTest(level=z):
                sim, voice, store, sheet, m = self.started(f'relay-on-{z}')
                self.place(sim, 303, 302, z)
                self.assertTrue(self.poll(sim, store))
                self.assertTrue(m.relayed)
                self.assertTrue(self.ready(sim, m))

    def test_objective_met_then_radio_report_accepted(self):
        sim, voice, store, sheet, m = self.started('relay-report')
        self.place(sim, 301, 301, 1)
        self.poll(sim, store)
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)
        self.assertEqual(m.state, 'success')

    def test_radio_turned_off_is_refused_even_before_the_next_reading(self):
        sim, voice, store, sheet, m = self.started('relay-off')
        r = self.place(sim, 301, 301, 1)
        self.poll(sim, store)
        self.assertTrue(self.ready(sim, m))
        r.getDeviceData(r).setIsTurnedOn(r.getDeviceData(r), False)
        # Report before the engine poll reads the world again: the server reads it at the report.
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'refused'))
        self.assertEqual((m.state, m.relayed), ('active', False))
        self.poll(sim, store)
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))
        r.getDeviceData(r).setIsTurnedOn(r.getDeviceData(r), True)
        self.poll(sim, store)
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)

    def test_unpowered_radio_is_refused(self):
        sim, voice, store, sheet, m = self.started('relay-power')
        g = sim.server.g
        r = self.place(sim, 301, 301, 1)
        d = r.getDeviceData(r)
        d.getBattery(d, None)                      # battery taken out: still "on" until the device's next update
        self.assertTrue(d.getIsTurnedOn(d))
        self.poll(sim, store)
        self.assertFalse(m.relayed)
        g.removeRadio(r)
        # Mains radio (not battery powered): grid power counts only in a room; a generator anywhere.
        mains = self.place(sim, 302, 302, 1, batteryPowered=False, hasBattery=False, power=0)
        self.poll(sim, store)
        self.assertTrue(m.relayed)
        g.GRID_ON = False                          # grid shut off: the device stays "on" until its next update
        self.poll(sim, store)
        self.assertFalse(m.relayed)
        g.GENERATORS['302,302,1'] = True
        self.poll(sim, store)
        self.assertTrue(m.relayed)
        g.removeRadio(mains)
        self.place(sim, 303, 303, 1, power=0)     # flat battery: setIsTurnedOn refuses to switch it on
        self.poll(sim, store)
        self.assertFalse(m.relayed)

    def test_wrong_floor_outside_target_or_receive_only_radio_is_refused(self):
        for case, (x, y, z, fields, cls) in {
                'ground floor': (302, 302, 0, {}, None),
                'next to the house': (310, 302, 1, {}, None),
                'receive only': (302, 302, 1, {'twoWay': False}, None),
                'television': (302, 302, 1, {'twoWay': False}, 'IsoTelevision')}.items():
            with self.subTest(case=case):
                sim, voice, store, sheet, m = self.started('relay-refused-' + case.replace(' ', '-'))
                sim.server.g.placeRadio(x, y, z, sim.server.rt.table_from(fields), cls)
                self.poll(sim, store)
                self.assertFalse(m.relayed)
                self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))

    def test_removed_radio_stops_counting_and_unloaded_spot_keeps_the_last_state(self):
        sim, voice, store, sheet, m = self.started('relay-unload')
        g = sim.server.g
        r = self.place(sim, 301, 301, 1)
        self.poll(sim, store)
        self.assertTrue(m.relayed)
        g.LOADED = False
        self.assertFalse(self.poll(sim, store))
        self.assertTrue(m.relayed)
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)
        sim2, voice2, store2, sheet2, m2 = self.started('relay-removed')
        r = self.place(sim2, 301, 301, 1)
        self.poll(sim2, store2)
        sim2.server.g.removeRadio(r)
        self.assertTrue(self.poll(sim2, store2))
        self.assertFalse(m2.relayed)

    def test_place_outside_any_building_is_a_zone_from_its_own_level(self):
        sim, voice, store, sheet, m = self.started('relay-deck', target='deck')
        self.assertEqual((m.minZ, m.site.zMin), (2, 2))
        self.assertEqual((m.site.x1, m.site.y1, m.site.x2, m.site.y2), (394, 394, 407, 407))
        low = self.place(sim, 401, 401, 1)
        self.poll(sim, store)
        self.assertFalse(m.relayed)
        sim.server.g.removeRadio(low)
        self.place(sim, 401, 401, 2)
        self.poll(sim, store)
        self.assertTrue(m.relayed)

    def test_start_refused_without_target(self):
        sim, voice, store = self.world('relay-no-target')
        self.assertEqual(self.start(sim, voice, store, self.sheet(sim, {})), (None, 'no_target'))
        self.assertEqual([m for m in sim.state().missions.values() if m.donor == 'voice'], [])

    def test_npc_fiches_are_never_offered_a_relay(self):
        sim, _, _ = self.world('relay-npc')
        offer = sim.server.rt.eval("""(function()
            local c = require('CoreAI/CA_MissionConfig').Missions.relay
            return require('CoreAI/CA_MissionRelay').offer(c, {id = 'npc1', incarnation = 1}, {}, nil)
        end)()""")
        self.assertIsNone(offer)

    def test_notebook_page_and_map_circle(self):
        sim, voice, store, sheet, m = self.started('relay-page')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load_notebook()
        maps = c.rt.eval("require('CoreAI/CA_MapZones')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
        drawn = [convert(s) for s in carnet_helpers.lua_list(c.rt.eval('mapSymbols()'))]
        self.assertEqual([s['text'] for s in drawn if s['kind'] == 'text'], ['IGUI_CA_MapZoneRelay|Custom'])
        self.assertEqual([(s['x'], s['y']) for s in drawn if s['kind'] == 'texture'], [(303, 302)])
        c.g.CoreAI.notebook.toggle()
        window = c.g.CoreAI.notebookClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        for key in ('IGUI_CA_RelayPlace|Hilltop house', 'IGUI_CA_RelayMapZone', 'IGUI_CA_RelayLevel|1',
                    'IGUI_CA_RelayOff', 'IGUI_CA_RelayRule', 'IGUI_CA_RelayReport'):
            self.assertIn(key, text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a relay mission')
        self.place(sim, 301, 301, 1)
        self.poll(sim, store)
        sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_CA_RelayOn', window.detail.text)


class RelaySuiteTests(unittest.TestCase):
    """The in-game suite rs.voicerelay run by the real RST engine on the bench world (server side, alice next to the
    house): upper floor found, radio placed and switched on, counted, off refused, on again, report accepted, removed."""
    setUp, tearDown = RelayMissionTests.setUp, RelayMissionTests.tearDown
    voice_sim, world = RelayMissionTests.voice_sim, RelayMissionTests.world

    def test_suite_passes_on_the_bench_world(self):
        sim, _, _ = self.world('relay-suite')
        rt, g = sim.server.rt, sim.server.g
        alice = g.PLAYERS.alice
        alice.x, alice.y, alice.z = 303, 308, 0
        rt.execute(f'package.path = [[{TESTS_LUA.as_posix()}/shared/?.lua;]] .. package.path')
        rt.execute('require "RST/RST"')
        # A world suite runs only on a test save (rstest*), as in game.
        rt.execute("local grid = getWorld():getMetaGrid(); getWorld = function() return {getGameMode = function() "
                   "return 'Multiplayer' end, getWorld = function() return 'rstest-relay' end, "
                   "getMetaGrid = function() return grid end} end")
        rt.execute(f'dofile([[{SUITE.as_posix()}]])')
        report = rt.eval('(function(p) return RST.runSync("rs.voicerelay", {player = p}) end)')(alice)
        results = {r.test: (r.status, r.message) for _, r in report.results.items()}
        self.assertEqual([s for s, _ in results.values()], ['PASS'], results)
        self.assertEqual(g.TRANSMITTED, 2)
        self.assertEqual(g.radiosLeft(), 0)


# E20-T02: fields of mission= (RS_MissionVoice.context); per-template facts come as job and facts only.
GENERIC_FIELDS = {'kind', 'state', 'turn', 'place', 'clues', 'remainingMs', 'toReport', 'reward', 'job', 'facts'}


class RelayBriefTests(unittest.TestCase):
    setUp, tearDown = RelayMissionTests.setUp, RelayMissionTests.tearDown
    voice_sim, world, sheet = RelayMissionTests.voice_sim, RelayMissionTests.world, RelayMissionTests.sheet
    start, poll, started, place = (RelayMissionTests.start, RelayMissionTests.poll, RelayMissionTests.started,
                                   RelayMissionTests.place)

    def told(self, voice, ctx):
        field = voice.field(ctx)
        self.assertLessEqual(set(protocol.decode(bytes.fromhex(field))), GENERIC_FIELDS)
        mission = bridge_module.mission_context({'mission': field}, SimpleNamespace(secrets=[], places=[]))
        return mission, bridge_module.mission_prompt(mission, 'Caller')

    def test_job_and_verified_facts_told_to_the_voice(self):
        sim, voice, store, sheet, m = self.started('relay-brief')
        mission, prompt = self.told(voice, voice.context(m, 'not_yet'))
        self.assertEqual((mission['kind'], mission['place']), ('relay', 'Hilltop house'))
        self.assertIn('Set up a two-way radio', mission['job'])
        self.assertIn('Hilltop house', mission['job'])
        self.assertIn('A powered radio is on at the spot (checked by the server): no.', prompt)
        self.assertIn('never add report_mission', prompt)
        self.place(sim, 301, 301, 1)
        self.poll(sim, store)
        heard = voice.heard(sheet, sim.server.g.PLAYERS.alice, sim.character('alice'), 160000, store)
        self.assertEqual((heard.turn, heard.toReport), ('report_due', True))
        _, prompt = self.told(voice, heard)
        self.assertIn('A powered radio is on at the spot (checked by the server): yes.', prompt)


class RelaySheetTests(unittest.TestCase):
    """The sheet reader accepts a relay section with a target place and refuses any parameter (none declared), with
    the real RS_Persona and the template registered as at game load."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.tmp.name)
        cls.lua = LuaPersona(cls.folder)
        cls.lua.rt.eval('require("CoreAI/CA_MissionRelay")')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, body: str):
        (self.folder / 'case.txt').write_bytes((BASE + '[mission m]\n' + body + PROMPT).encode('utf-8'))
        return self.lua.read('case.txt')

    def test_valid_section(self):
        p = self.read('type=relay\ntarget=clinic\n')
        self.assertFalse(isinstance(p, tuple), p)
        self.assertEqual((p.missions[1].type, p.missions[1].target), ('relay', 'clinic'))

    def test_refusals(self):
        for body, why in (
                ('type=relay\ntarget=church\n', "line 15: place 'church' has no use=target"),
                ('type=relay\ntarget=clinic\ncount=2\n', "line 16: unknown key 'count' for mission type 'relay'")):
            with self.subTest(body=body):
                self.assertEqual(self.read(body), (None, why))


if __name__ == '__main__':
    unittest.main()
