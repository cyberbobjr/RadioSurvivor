"""Type de mission `barricade` (E20-T09, ADR D02, D10) : barricader `count` fenêtres et portes extérieures du bâtiment
d'un lieu `target` de la fiche d'une voix, compte vérifié par le serveur dans le monde, compte rendu à la radio.

    python RadioSurvivor/tests/test_mission_barricade.py

Vrai RadioSurvivor_Server, vrai CA_NotebookServer (gabarit CA_MissionBarricade inscrit au chargement), vrai
RS_MissionVoice (départ et compte rendu d'une voix), vrai RS_Persona (lecture de la fiche), vrai client du carnet ;
doublures du monde fidèles au Java 42.22 relevé (BARRICADE_WORLD). Preuve de la logique Lua, pas de l'API Java réelle
ni du réseau : la suite en jeu rs.voicebarricade le confirme sur un serveur dédié.
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
from test_persona_sections import BASE, PLACES, PROMPT
import npc_protocol as protocol

ROOT = Path(__file__).resolve().parents[1]
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
TESTS_LUA = tests_lua()
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_MissionBarricade.lua'

# Doublures du monde, fidèles au Java 42.22 (E:\pz-source-42.22\java\zombie, relevé du 2026-11-15) :
# - IsoMetaGrid.getBuildingAt(x, y, z) (IsoMetaGrid.java:271-280) : bâtiment de la pièce (ou du vide extérieur du
#   lot) de la case, lu sur la métagrille : rend le bâtiment même déchargé ; nil hors de toute pièce.
# - BuildingDef (BuildingDef.java:82-100, 189-202) : getX/getY, getX2/getY2 exclusifs, getMinLevel/getMaxLevel.
# - IsoCell.getGridSquare(x, y, z) (IsoCell.java:2801) : nil pour une case non chargée ; IsoGridSquare.getObjects()
#   (IsoGridSquare.java:7781, liste Java indexée depuis 0), getBuildingDef() (:7813-7816 : par la pièce, nil dehors).
# - Ouvertures BarricadeAble (BarricadeAble.java, GridSquareEdgeElement.java:15-27) : isNorth, getSquare,
#   getOppositeSquare (case voisine nord ou ouest, nil si absente), isBarricadeAllowed (IsoDoor.java:1604-1606 :
#   refusé pour une double porte ou une porte de garage ; IsoWindow.java:1106 : toujours ; IsoWindowFrame.java:104 :
#   seulement sans fenêtre), getBarricadeOnSameSquare / OnOppositeSquare (IsoDoor.java:1584-1592 : barricade de
#   direction N/W sur la case de l'objet, S/E sur la case opposée ; cadre avec fenêtre : nil, IsoWindowFrame.java:109-127).
# - IsoBarricade (IsoBarricade.java:90-108, 138-149, 190-206, 208, 230, 739-764) : AddBarricadeToObject(obj,
#   addOpposite) rend la barricade déjà posée de ce côté ou en crée une vide (case absente : nil) ; addPlank(chr,
#   plank) : 4 planches au plus, refusé sur du métal ; addMetal(chr, metal) : refusé sur des planches ou du métal ;
#   getNumPlanks, isMetal, isMetalBar ; removePlank : planche extérieure, la dernière retire la barricade.
BARRICADE_WORLD = r'''
LOADED = true
local squares, barricades = {}, {}
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
-- Test classes named after their Java class (checked by tests/test_doubles_api.py); instanceof reads __javaName and
-- the Java supertypes (classes and interfaces: IsoDoor.java, IsoWindow.java, IsoWindowFrame.java implement BarricadeAble).
local SUPER = {IsoWindow = {IsoObject = true, BarricadeAble = true}, IsoDoor = {IsoObject = true, BarricadeAble = true},
    IsoWindowFrame = {IsoObject = true, BarricadeAble = true}, IsoBarricade = {IsoObject = true}}
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
CLINIC = setmetatable({x1 = 200, y1 = 200, x2 = 206, y2 = 205, zMin = 0, zMax = 0}, Def)
local function inClinic(x, y, z)
    return x >= CLINIC.x1 and x < CLINIC.x2 and y >= CLINIC.y1 and y < CLINIC.y2 and z >= CLINIC.zMin and z <= CLINIC.zMax
end
local Grid = class('IsoMetaGrid')
function Grid:getBuildingAt(x, y, z)
    if z == nil then error('getBuildingAt(x, y) reads the bounds only: use the room variant (x, y, z)') end
    if inClinic(math.floor(x), math.floor(y), math.floor(z)) then return CLINIC end
    return nil
end
SCOUT_GRID.getBuildingAt = Grid.getBuildingAt
local Sq = class('IsoGridSquare')
function Sq:getX() return self.x end
function Sq:getY() return self.y end
function Sq:getZ() return self.z end
function Sq:getObjects() return setmetatable({items = self.objects}, List) end
function Sq:getBuildingDef() if inClinic(self.x, self.y, self.z) then return CLINIC end return nil end
-- IsoGridSquare.java:5073-5100 (server: removed for every client), objects index from the end.
function Sq:transmitRemoveItemFromSquare(obj)
    for i = #self.objects, 1, -1 do
        if self.objects[i] == obj then
            table.remove(self.objects, i)
            if obj.key then barricades[obj.key] = nil end
            return i - 1
        end
    end
    return -1
end
for x = 195, 210 do
    for y = 195, 210 do squares[key(x, y, 0)] = setmetatable({x = x, y = y, z = 0, objects = {}}, Sq) end
end
local function square(x, y, z)
    if not LOADED then return nil end
    return squares[key(x, y, z)]
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
-- Barricades by square and direction (IsoBarricade.GetBarricadeOnSquare, IsoBarricade.java:706-717).
local function barricadeOn(sq, dir)
    if sq == nil then return nil end
    return barricades[key(sq.x, sq.y, sq.z) .. ':' .. dir]
end
local Bar = class('IsoBarricade')
function Bar:getNumPlanks()
    local n = 0
    for i = 1, 4 do if (self.planks[i] or 0) > 0 then n = n + 1 end end
    return n
end
function Bar:isMetal() return self.metal > 0 end
function Bar:isMetalBar() return self.metalBar > 0 end
function Bar:canAddPlank() return not self:isMetal() and self:getNumPlanks() < 4 and not self:isMetalBar() end
function Bar:addPlank(chr, plank)
    if not self:canAddPlank() then return end
    for i = 1, 4 do if (self.planks[i] or 0) <= 0 then self.planks[i] = 1000; return end end
end
function Bar:addMetal(chr, metal)
    if self:getNumPlanks() > 0 or self.metal > 0 then return end
    self.metal = 5000
end
function Bar:getSquare() return squares[self.sqKey] end
TRANSMITTED = 0
function Bar:transmitCompleteItemToClients() TRANSMITTED = TRANSMITTED + 1 end
function Bar:removePlank(chr)
    for i = 4, 1, -1 do
        if (self.planks[i] or 0) > 0 then
            self.planks[i] = 0
            if self:getNumPlanks() == 0 then barricades[self.key] = nil end
            return
        end
    end
end
-- Edge elements: one implementation for the window, copied to the door and the frame (same Java methods).
local Window = class('IsoWindow')
function Window:isNorth() return self.north end
function Window:getSquare() return square(self.x, self.y, self.z) end
function Window:getOppositeSquare()
    if self.north then return square(self.x, self.y - 1, self.z) end
    return square(self.x - 1, self.y, self.z)
end
function Window:isBarricadeAllowed()
    if self.frameWithWindow then return false end
    return not self.doubleDoor
end
function Window:getBarricadeOnSameSquare()
    if self.frameWithWindow then return nil end
    return barricadeOn(self:getSquare(), self.north and 'N' or 'W')
end
function Window:getBarricadeOnOppositeSquare()
    if self.frameWithWindow then return nil end
    return barricadeOn(self:getOppositeSquare(), self.north and 'S' or 'E')
end
-- IsoDoor.java:1595-1601, IsoWindow.java:1097-1103: a barricade on either side.
function Window:isBarricaded()
    return self:getBarricadeOnSameSquare() ~= nil or self:getBarricadeOnOppositeSquare() ~= nil
end
local CLASSES = {IsoWindow = Window, IsoDoor = class('IsoDoor'), IsoWindowFrame = class('IsoWindowFrame')}
for _, c in pairs(CLASSES) do
    if c ~= Window then
        for k, v in pairs(Window) do if type(v) == 'function' then rawset(c, k, v) end end
    end
end
IsoBarricade = {AddBarricadeToObject = function(o, addOpposite)
    if type(addOpposite) == 'table' then
        -- Overload (BarricadeAble, IsoGameCharacter), IsoBarricade.java:766-776: the side of the character.
        local chr, own = addOpposite, o:getSquare()
        if own == nil then return nil end
        if o.north then addOpposite = chr:getY() < own:getY() else addOpposite = chr:getX() < own:getX() end
    end
    local sq = addOpposite and o:getOppositeSquare() or o:getSquare()
    if sq == nil then return nil end
    local dir = o.north and (addOpposite and 'S' or 'N') or (addOpposite and 'E' or 'W')
    local k = key(sq.x, sq.y, sq.z) .. ':' .. dir
    if barricades[k] then return barricades[k] end
    local b = setmetatable({key = k, sqKey = key(sq.x, sq.y, sq.z), planks = {}, metal = 0, metalBar = 0}, Bar)
    barricades[k] = b
    sq.objects[#sq.objects + 1] = b
    return b
end}
OPENINGS = {}
function opening(name, javaClass, x, y, north, fields)
    local o = setmetatable({x = x, y = y, z = 0, north = north}, CLASSES[javaClass])
    for k, v in pairs(fields or {}) do o[k] = v end
    squares[key(x, y, 0)].objects[#squares[key(x, y, 0)].objects + 1] = o
    OPENINGS[name] = o
    return o
end
-- Clinic x 200..205, y 200..204 (x2 = 206, y2 = 205 exclusive): south and east walls are carried by the squares
-- outside the rectangle (y = 205, x = 206).
opening('north', 'IsoWindow', 202, 200, true)
opening('northFrame', 'IsoWindowFrame', 202, 200, true, {frameWithWindow = true}) -- same edge as the north window
opening('west', 'IsoDoor', 200, 202, false)
opening('south', 'IsoWindow', 203, 205, true)
opening('east', 'IsoWindowFrame', 206, 201, false)                          -- empty frame: barricadable
opening('inner', 'IsoDoor', 203, 202, false)                                 -- both sides inside: interior door
opening('double', 'IsoDoor', 201, 200, true, {doubleDoor = true})            -- double door: not barricadable
opening('old', 'IsoWindow', 204, 200, true)                                  -- barricaded before the mission
-- Barricade of an opening from inside (opposite = false: the square of the object) or outside, planks or metal.
function barricade(name, opposite, metal)
    local b = IsoBarricade.AddBarricadeToObject(OPENINGS[name], opposite)
    if metal then b:addMetal(nil, nil) else b:addPlank(nil, nil) end
    return b
end
'''

# Lieux communs (E25-T01) connus de la fiche d'une voix qui donne la mission barricade : la clinique et un champ vide,
# deux points, table id -> lieu comme sheet.places.
SHEET_PLACES = {
    'clinic': {'id': 'clinic', 'x': 202, 'y': 202, 'z': 0, 'label': 'West Point clinic'},
    'field': {'id': 'field', 'x': 400, 'y': 400, 'z': 0, 'label': 'Empty field'},
}


def sheet_double(rt, shared, section, mission_type, mission_id):
    """Parsed sheet double (E25-T01 shape) with one mission section: places = map id -> place (shared: dict of plain
    dicts), target = {kind='place', id} for a place id (absent: {kind='near'}, as RS_Persona sets it)."""
    places = {k: rt.table_from(p) for k, p in shared.items()}
    fields = dict(section)
    fields['params'] = rt.table_from(section.get('params', {}))
    target = section.get('target')
    fields['target'] = rt.table_from({'kind': 'place', 'id': target} if target else {'kind': 'near'})
    fields.setdefault('type', mission_type)
    fields.setdefault('id', mission_id)
    return rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from([rt.table_from(fields)]),
                          'places': rt.table_from(places)})


class BarricadeMissionTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def world(self, name):
        sim = self.voice_sim(name)
        rt = sim.server.rt
        rt.execute(CLEAR_WORLD)
        rt.execute(BARRICADE_WORLD)
        # The game loads every server file of the mod: the set-up of the target place registers itself (no require).
        rt.eval("require('RadioSurvivor/RS_MissionTarget')")
        return sim, rt.eval("require('RadioSurvivor/RS_MissionVoice')"), rt.eval("require('CoreAI/CA_NotebookStore')")

    def sheet(self, sim, section):
        return sheet_double(sim.server.rt, SHEET_PLACES, section, 'barricade', 'secure')

    def start(self, sim, voice, store, sheet):
        return voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, 'barricade')

    def poll(self, sim, store):
        """Server poll of the engine (CA_Missions.observe) with the server copy of alice, after the scan delay."""
        sim.clock.offset += 5000
        present = sim.server.rt.table_from([sim.server.rt.table_from(
            {'player': sim.server.g.PLAYERS.alice, 'character': sim.character('alice')})])
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").observe(store.data, present, store)

    def report(self, sim, voice, store, sheet):
        return voice.report(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)

    def started(self, name, params=None):
        sim, voice, store = self.world(name)
        sim.server.g.barricade('old', False, False)
        sheet = self.sheet(sim, {'target': 'clinic', 'params': params or {'count': 2}})
        m = self.start(sim, voice, store, sheet)
        self.assertFalse(isinstance(m, tuple), str(m))
        return sim, voice, store, sheet, m

    def test_mission_is_given_by_a_voice_on_the_building_of_the_target_place(self):
        sim, voice, store, sheet, m = self.started('barricade-start')
        self.assertEqual((m.template, m.donor, m.report, m.state), ('barricade', 'voice', 'radio', 'active'))
        self.assertEqual((m.place, m.count, m.barricaded), ('West Point clinic', 2, 0))
        self.assertEqual((m.site.x1, m.site.y1, m.site.x2, m.site.y2), (200, 200, 206, 205))
        engine = sim.server.rt.eval("require('CoreAI/CA_Missions')")
        self.assertFalse(engine.reportReady(m))
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))

    def test_planks_and_metal_count_once_per_opening_from_either_side(self):
        sim, voice, store, sheet, m = self.started('barricade-count', {'count': 3})
        g = sim.server.g
        g.barricade('north', False, False)             # planks, from inside
        self.assertTrue(self.poll(sim, store))
        self.assertEqual(m.barricaded, 1)
        g.barricade('north', True, False)              # the other side of the same window: still one opening
        g.barricade('west', True, True)                # metal sheet, from outside
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 2)
        g.barricade('east', False, False)              # empty window frame, east wall carried outside
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 3)
        self.assertTrue(sim.server.rt.eval("require('CoreAI/CA_Missions')").reportReady(m))

    def test_interior_and_pre_existing_barricades_never_count(self):
        sim, voice, store, sheet, m = self.started('barricade-pre')
        g = sim.server.g
        g.barricade('inner', False, False)             # interior door: both sides inside the clinic
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 0)
        g.barricade('old', False, False)               # second plank on the window barricaded before the start
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 0)
        self.assertEqual(m.openings['204,200,0,N'], 'pre')

    def test_objective_met_at_count_then_radio_report_accepted(self):
        sim, voice, store, sheet, m = self.started('barricade-report')
        g = sim.server.g
        g.barricade('north', False, False)
        self.poll(sim, store)
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))
        g.barricade('south', True, False)
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 2)
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)
        self.assertEqual(m.state, 'success')

    def test_removed_barricade_stops_counting_and_unloaded_building_keeps_the_last_count(self):
        sim, voice, store, sheet, m = self.started('barricade-unload')
        g = sim.server.g
        b = g.barricade('north', False, False)
        g.barricade('west', False, False)
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 2)
        b.removePlank(b, None)
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 1)
        g.LOADED = False
        self.assertFalse(self.poll(sim, store))
        self.assertEqual(m.barricaded, 1)

    def test_building_unloaded_at_start_takes_its_baseline_at_first_sight(self):
        sim, voice, store = self.world('barricade-late')
        g = sim.server.g
        g.barricade('old', False, False)
        g.LOADED = False
        sheet = self.sheet(sim, {'target': 'clinic', 'params': {'count': 1}})
        m = self.start(sim, voice, store, sheet)
        self.assertFalse(isinstance(m, tuple), str(m))
        self.assertEqual(m.barricaded, 0)
        g.LOADED = True
        self.poll(sim, store)
        self.assertEqual((m.barricaded, m.openings['204,200,0,N']), (0, 'pre'))
        g.barricade('north', False, False)
        self.poll(sim, store)
        self.assertEqual(m.barricaded, 1)

    def test_start_refused_without_building_or_count(self):
        for section, why in (({'target': 'field'}, 'no_building'),
                             ({'target': 'clinic', 'params': {'count': 0}}, 'bad_count')):
            with self.subTest(section=section):
                sim, voice, store = self.world('barricade-refused-' + why)
                self.assertEqual(self.start(sim, voice, store, self.sheet(sim, section)), (None, why))
                self.assertEqual([m for m in sim.state().missions.values() if m.donor == 'voice'], [])

    def test_default_count_from_the_catalogue(self):
        sim, voice, store = self.world('barricade-default')
        m = self.start(sim, voice, store, self.sheet(sim, {'target': 'clinic'}))
        self.assertEqual(m.count, 4)

    def test_npc_fiches_are_never_offered_a_barricade(self):
        sim, _, _ = self.world('barricade-npc')
        offer = sim.server.rt.eval("""(function()
            local c = require('CoreAI/CA_MissionConfig').Missions.barricade
            return require('CoreAI/CA_MissionBarricade').offer(c, {id = 'npc1', incarnation = 1}, {}, nil)
        end)()""")
        self.assertIsNone(offer)

    def test_notebook_page_and_map_circle(self):
        sim, voice, store, sheet, m = self.started('barricade-page')
        sim.server.g.barricade('north', False, False)
        self.poll(sim, store)
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load_notebook()
        maps = c.rt.eval("require('CoreAI/CA_MapZones')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
        drawn = [convert(s) for s in carnet_helpers.lua_list(c.rt.eval('mapSymbols()'))]
        self.assertEqual([s['text'] for s in drawn if s['kind'] == 'text'], ['IGUI_CA_MapZoneBarricade|Custom'])
        self.assertEqual([(s['x'], s['y']) for s in drawn if s['kind'] == 'texture'], [(203, 202)])
        c.g.CoreAI.notebook.toggle()
        window = c.g.CoreAI.notebookClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        for key in ('IGUI_CA_BarricadePlace|West Point clinic', 'IGUI_CA_BarricadeMapZone',
                    'IGUI_CA_BarricadeProgress|1|2', 'IGUI_CA_BarricadeRule', 'IGUI_CA_BarricadeReport'):
            self.assertIn(key, text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a barricade mission')


class BarricadeSuiteTests(unittest.TestCase):
    """The in-game suite rs.voicebarricade run by the real RST engine on the bench world (server side, alice next to
    the clinic): building found, barricades put up on the player's side, counted, report accepted, all removed."""
    setUp, tearDown = BarricadeMissionTests.setUp, BarricadeMissionTests.tearDown
    voice_sim, world = BarricadeMissionTests.voice_sim, BarricadeMissionTests.world

    def test_suite_passes_on_the_bench_world(self):
        sim, _, _ = self.world('barricade-suite')
        rt, g = sim.server.rt, sim.server.g
        alice = g.PLAYERS.alice
        alice.x, alice.y, alice.z = 203, 208, 0
        rt.execute(f'package.path = [[{TESTS_LUA.as_posix()}/shared/?.lua;]] .. package.path')
        rt.execute('require "RST/RST"')
        # A world suite runs only on a test save (rstest*), as in game.
        rt.execute("local grid = getWorld():getMetaGrid(); getWorld = function() return {getGameMode = function() "
                   "return 'Multiplayer' end, getWorld = function() return 'rstest-barricade' end, "
                   "getMetaGrid = function() return grid end} end")
        rt.execute(f'dofile([[{SUITE.as_posix()}]])')
        report = rt.eval('(function(p) return RST.runSync("rs.voicebarricade", {player = p}) end)')(alice)
        results = {r.test: (r.status, r.message) for _, r in report.results.items()}
        self.assertEqual([s for s, _ in results.values()], ['PASS'], results)
        self.assertEqual(g.TRANSMITTED, 3)
        self.assertFalse(any(o.key for x in range(195, 211) for y in range(195, 211)
                             for o in carnet_helpers.lua_list(rt.eval(
                                 f'getCell():getGridSquare({x}, {y}, 0):getObjects().items')) if o.key))


# E20-T02: fields of mission= (RS_MissionVoice.context); per-template facts come as job and facts only.
GENERIC_FIELDS = {'kind', 'state', 'turn', 'place', 'clues', 'remainingMs', 'toReport', 'reward', 'job', 'facts'}


class BarricadeBriefTests(unittest.TestCase):
    setUp, tearDown = BarricadeMissionTests.setUp, BarricadeMissionTests.tearDown
    voice_sim, world, sheet = BarricadeMissionTests.voice_sim, BarricadeMissionTests.world, BarricadeMissionTests.sheet
    start, poll, started = BarricadeMissionTests.start, BarricadeMissionTests.poll, BarricadeMissionTests.started

    def told(self, voice, ctx):
        field = voice.field(ctx)
        self.assertLessEqual(set(protocol.decode(bytes.fromhex(field))), GENERIC_FIELDS)
        mission = bridge_module.mission_context({'mission': field}, SimpleNamespace(marks=[]))
        return mission, bridge_module.mission_prompt(mission, 'Caller')

    def test_job_and_verified_facts_told_to_the_voice(self):
        sim, voice, store, sheet, m = self.started('barricade-brief')
        mission, prompt = self.told(voice, voice.context(m, 'not_yet'))
        self.assertEqual((mission['kind'], mission['place']), ('barricade', 'West Point clinic'))
        self.assertIn('Barricade 2 outside windows or doors of West Point clinic', mission['job'])
        self.assertIn('Openings barricaded since the mission started (checked by the server): 0 of 2.', prompt)
        self.assertIn('never add report_mission', prompt)
        sim.server.g.barricade('north', False, True)
        sim.server.g.barricade('west', False, False)
        self.poll(sim, store)
        heard = voice.heard(sheet, sim.server.g.PLAYERS.alice, sim.character('alice'), 160000, store)
        self.assertEqual((heard.turn, heard.toReport), ('report_due', True))
        _, prompt = self.told(voice, heard)
        self.assertIn('Openings barricaded since the mission started (checked by the server): 2 of 2.', prompt)


class BarricadeSheetTests(unittest.TestCase):
    """The sheet reader refuses a bad target or count of a barricade section (common key target, declared param
    count), with the real RS_Persona and the template registered as at game load."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.tmp.name)
        (cls.folder / '_places.txt').write_text(PLACES, encoding='utf-8')   # E25-T01: shared places of the cases
        cls.lua = LuaPersona(cls.folder)
        # Registered as at game load (every server file before the sheets): the reader looks the type up when it reads.
        cls.lua.rt.eval('require("CoreAI/CA_MissionBarricade")')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, body: str):
        (self.folder / 'case.txt').write_bytes((BASE + '[mission m]\n' + body + PROMPT).encode('utf-8'))
        return self.lua.read('case.txt')

    def test_valid_section(self):
        p = self.read('type=barricade\ntarget=clinic\ncount=3\n')
        self.assertFalse(isinstance(p, tuple), p)
        m = p.missions[1]
        self.assertEqual((m.type, m.target.kind, m.target.id, m.params['count']), ('barricade', 'place', 'clinic', 3))

    def test_refusals(self):
        for body, why in (
                ('type=barricade\ntarget=mill\n', "line 7: unknown place 'mill'"),
                ('type=barricade\ntarget=clinic\ncount=many\n',
                 "line 8: bad count 'many' (whole number from 0 to 999999)"),
                ('type=barricade\ntarget=clinic\nwindows=3\n',
                 "line 8: unknown key 'windows' for mission type 'barricade'")):
            with self.subTest(body=body):
                self.assertEqual(self.read(body), (None, why))


if __name__ == '__main__':
    unittest.main()
