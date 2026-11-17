"""Type de mission `route` (E20-T13, ADR D10) : passer DANS L'ORDRE par plusieurs points des lieux communs
nommés par la clé points= de la section d'une voix (E25-T01), à pied ou en véhicule ; passage lu par le serveur sur sa copie du participant, compte rendu
à la radio.

    python RadioSurvivor/tests/radiosurvivor/test_mission_route.py

Vrai RadioSurvivor_Server, vrai CA_NotebookServer (gabarit CA_MissionRoute inscrit au chargement), vrai RS_MissionVoice
(départ et compte rendu d'une voix), vrai RS_MissionWaypoints (points de la section), vrai RS_Persona et
RS_PersonaParams (lecture de la fiche, nature de paramètre `places`), vrai client du carnet (page, cercles de la carte) ;
doublures fidèles au Java 42.22 relevé (ROUTE_WORLD). Preuve de la logique Lua, pas de l'API Java réelle ni du réseau :
la suite en jeu rs.voiceroute le confirme sur un serveur dédié.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
import test_carnet as carnet_helpers
from test_carnet import MAP_DOUBLE, NOTEBOOK_UI, bridge_module, convert
from test_personas import LuaPersona
from persona_fixtures import place  # noqa: E402
from test_persona_sections import BASE, PLACES, PROMPT, ZONE_HERE
import npc_protocol as protocol

ROOT = Path(__file__).resolve().parents[2]
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
TESTS_LUA = tests_lua()
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_MissionRoute.lua'

# Doublures fidèles au Java 42.22 (E:\pz-source-42.22\java\zombie, relevé du 2026-11-15) :
# - IsoGameCharacter.getVehicle() : véhicule où le personnage est assis, nil à pied ; la copie serveur le connaît
#   (paquet VehicleEnter).
# - BaseVehicle getX/getY/getZ (hérités d'IsoMovingObject) : position du véhicule ; BaseVehicle.update replace chaque
#   passager à son siège (BaseVehicle.java:3369-3378), la position du joueur suit donc le véhicule avec une mise à jour
#   de retard au plus.
# - IsoMovingObject setX/setY : position posée tout de suite (la suite en jeu déplace la copie serveur du joueur).
ROUTE_WORLD = r'''
local function class(name)
    local c = {__javaName = name}
    c.__index = c
    return c
end
local Vehicle = class('BaseVehicle')
function Vehicle:getX() return self.x end
function Vehicle:getY() return self.y end
function Vehicle:getZ() return self.z end
local Player = class('IsoPlayer')
function Player:getVehicle() return self.vehicle end
function Player:setX(x) self.x = x end
function Player:setY(y) self.y = y end
for _, p in pairs(PLAYERS) do
    p.getVehicle = Player.getVehicle
    p.setX = Player.setX
    p.setY = Player.setY
end
function newVehicle(x, y) return setmetatable({x = x, y = y, z = 0}, Vehicle) end
'''

# Lieux communs lus avec la fiche d'une voix qui donne la mission route (E25-T01) : trois points, une zone.
SHEET_PLACES = [
    {'id': 'a', 'x': 40, 'y': 10, 'z': 0, 'label': 'Point A'},
    {'id': 'b', 'x': 40, 'y': 40, 'z': 0, 'label': 'Point B'},
    {'id': 'c', 'x': 10, 'y': 40, 'z': 0, 'label': 'Point C'},
    {'id': 'yard', 'z': 0, 'label': 'Yard', 'area': {'x1': 60, 'y1': 60, 'x2': 80, 'y2': 80}},
]
POINTS = {'a': (40, 10), 'b': (40, 40), 'c': (10, 40)}


class RouteMissionTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def world(self, name):
        sim = self.voice_sim(name)
        rt = sim.server.rt
        rt.execute(ROUTE_WORLD)
        # The game loads every server file of the mod: the set-up of the route points registers itself (no require).
        rt.eval("require('RadioSurvivor/RS_MissionWaypoints')")
        rt.eval("require('CoreAI/CA_MissionRoute')").resetForTests()
        return sim, rt.eval("require('RadioSurvivor/RS_MissionVoice')"), rt.eval("require('CoreAI/CA_NotebookStore')")

    def sheet(self, sim, points=('a', 'b', 'c')):
        rt = sim.server.rt
        places = {p['id']: rt.table_from({**p, **({'area': rt.table_from(p['area'])} if 'area' in p else {})})
                  for p in SHEET_PLACES}
        params = {} if points is None else {'points': rt.table_from(list(points))}
        section = rt.table_from({'id': 'route', 'type': 'route', 'target': rt.table_from({'kind': 'near'}),
                                 'params': rt.table_from(params)})
        return rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from([section]),
                              'places': rt.table_from(places)})

    def start(self, sim, voice, store, sheet):
        return voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, 'route')

    def go(self, sim, store, where):
        """alice moves to the point (or x, y), then the server poll of the engine (CA_Missions.observe)."""
        alice = sim.server.g.PLAYERS.alice
        alice.x, alice.y = POINTS[where] if isinstance(where, str) else where
        return self.poll(sim, store)

    def poll(self, sim, store):
        sim.clock.offset += 1000
        present = sim.server.rt.table_from([sim.server.rt.table_from(
            {'player': sim.server.g.PLAYERS.alice, 'character': sim.character('alice')})])
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").observe(store.data, present, store)

    def report(self, sim, voice, store, sheet):
        return voice.report(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)

    def ready(self, sim, m):
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").reportReady(m)

    def started(self, name, points=('a', 'b', 'c')):
        sim, voice, store = self.world(name)
        sheet = self.sheet(sim, points)
        m = self.start(sim, voice, store, sheet)
        self.assertFalse(isinstance(m, tuple), str(m))
        self.poll(sim, store)  # first reading: alice at (10, 10), far from every point
        return sim, voice, store, sheet, m

    def test_mission_is_given_by_a_voice_with_the_points_of_its_section(self):
        sim, voice, store, sheet, m = self.started('route-start')
        self.assertEqual((m.template, m.donor, m.report, m.state), ('route', 'voice', 'radio', 'active'))
        self.assertEqual([(p.id, p.label, p.x, p.y) for p in carnet_helpers.lua_list(m.points)],
                         [('a', 'Point A', 40, 10), ('b', 'Point B', 40, 40), ('c', 'Point C', 10, 40)])
        self.assertEqual(m.crossed, 0)
        self.assertFalse(self.ready(sim, m))
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))

    def test_points_crossed_in_order_then_radio_report_accepted(self):
        sim, voice, store, sheet, m = self.started('route-order')
        for i, point in enumerate('abc', start=1):
            with self.subTest(point=point):
                self.assertTrue(self.go(sim, store, point))
                self.assertEqual(m.crossed, i)
        self.assertTrue(self.ready(sim, m))
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)
        self.assertEqual(m.state, 'success')

    def test_point_within_the_radius_counts_and_outside_does_not(self):
        sim, voice, store, sheet, m = self.started('route-radius')
        self.assertFalse(self.go(sim, store, (40, 19)))   # 9 tiles from A
        self.assertEqual(m.crossed, 0)
        self.assertTrue(self.go(sim, store, (46, 15)))    # 7.8 tiles from A
        self.assertEqual(m.crossed, 1)

    def test_skipped_point_is_refused(self):
        sim, voice, store, sheet, m = self.started('route-skip')
        self.assertFalse(self.go(sim, store, 'b'))        # B before A: not counted
        self.assertEqual(m.crossed, 0)
        self.assertTrue(self.go(sim, store, 'a'))
        self.assertFalse(self.go(sim, store, 'c'))        # C before B: not counted
        self.assertEqual(m.crossed, 1)
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))
        self.assertTrue(self.go(sim, store, 'b'))
        self.assertTrue(self.go(sim, store, 'c'))
        self.assertEqual(m.crossed, 3)
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)

    def test_vehicle_position_counts(self):
        sim, voice, store, sheet, m = self.started('route-vehicle')
        g = sim.server.g
        g.PLAYERS.alice.vehicle = g.newVehicle(41, 11)    # the player's own copy is a step behind
        self.assertTrue(self.poll(sim, store))
        self.assertEqual(m.crossed, 1)

    def test_point_passed_between_two_readings_counts(self):
        sim, voice, store, sheet, m = self.started('route-fast')
        g = sim.server.g
        g.PLAYERS.alice.vehicle = g.newVehicle(20, 10)
        self.poll(sim, store)
        g.PLAYERS.alice.vehicle.x = 60                     # through A (40, 10) at 40 tiles a second
        self.assertTrue(self.poll(sim, store))
        self.assertEqual(m.crossed, 1)

    def test_jump_longer_than_any_drive_counts_only_where_it_lands(self):
        sim, voice, store, sheet, m = self.started('route-jump')
        self.go(sim, store, (-100, 10))
        self.assertFalse(self.go(sim, store, (100, 10)))  # 200 tiles in one reading: a teleport, A not passed
        self.assertEqual(m.crossed, 0)

    def test_dead_participant_does_not_count(self):
        sim, voice, store, sheet, m = self.started('route-dead')
        sim.server.g.PLAYERS.alice.dead = True
        self.assertFalse(self.go(sim, store, 'a'))
        self.assertEqual(m.crossed, 0)

    def test_start_refused_without_valid_points(self):
        for case, points in {'no points': None, 'one point': ('a',), 'unknown point': ('a', 'zz'),
                             'zone instead of a point': ('a', 'yard')}.items():
            with self.subTest(case=case):
                sim, voice, store = self.world('route-refused-' + case.replace(' ', '-').replace('=', '-'))
                self.assertEqual(self.start(sim, voice, store, self.sheet(sim, points)), (None, 'no_points'))
                self.assertEqual([m for m in sim.state().missions.values() if m.donor == 'voice'], [])

    def test_npc_fiches_are_never_offered_a_route(self):
        sim, _, _ = self.world('route-npc')
        offer = sim.server.rt.eval("""(function()
            local c = require('CoreAI/CA_MissionConfig').Missions.route
            return require('CoreAI/CA_MissionRoute').offer(c, {id = 'npc1', incarnation = 1}, {}, nil)
        end)()""")
        self.assertIsNone(offer)

    def test_notebook_page_and_map_circles_point_by_point(self):
        sim, voice, store, sheet, m = self.started('route-page')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load_notebook()
        maps = c.rt.eval("require('CoreAI/CA_MapZones')")
        maps.resetForTests(); maps.resetZonesForTests()

        def snapshot():
            sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
            drawn = [convert(s) for s in carnet_helpers.lua_list(c.rt.eval('mapSymbols()'))]
            return (sorted(s['text'] for s in drawn if s['kind'] == 'text'),
                    sorted((s['x'], s['y']) for s in drawn if s['kind'] == 'texture'))

        self.assertEqual(snapshot(), (['IGUI_CA_MapZoneRoute|Point A'], [(40, 10)]))
        c.g.CoreAI.notebook.toggle()
        window = c.g.CoreAI.notebookClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        for key in ('IGUI_CA_RouteProgress|0|3', 'IGUI_CA_RouteNext|Point A', 'IGUI_CA_RouteMapZone',
                    'IGUI_CA_RouteRule', 'IGUI_CA_RouteReport'):
            self.assertIn(key, text)
        self.assertNotIn('Point B', text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a route mission')
        self.go(sim, store, 'a')
        self.assertEqual(snapshot(), (['IGUI_CA_MapZoneRoute|Point A', 'IGUI_CA_MapZoneRoute|Point B'],
                                      [(40, 10), (40, 40)]))
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_CA_RouteProgress|1|3', window.detail.text)
        self.assertIn('IGUI_CA_RouteNext|Point B', window.detail.text)
        self.go(sim, store, 'b')
        self.go(sim, store, 'c')
        self.assertEqual(len(snapshot()[1]), 3)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_CA_RouteProgress|3|3', window.detail.text)
        self.assertIn('IGUI_CA_RouteAllCrossed', window.detail.text)


class RouteBriefTests(unittest.TestCase):
    setUp, tearDown = RouteMissionTests.setUp, RouteMissionTests.tearDown
    voice_sim, world, sheet, start = (RouteMissionTests.voice_sim, RouteMissionTests.world, RouteMissionTests.sheet,
                                      RouteMissionTests.start)
    poll, go, started = RouteMissionTests.poll, RouteMissionTests.go, RouteMissionTests.started

    def told(self, voice, ctx):
        field = voice.field(ctx)
        generic = {'kind', 'state', 'turn', 'place', 'clues', 'remainingMs', 'toReport', 'reward', 'job', 'facts'}
        self.assertLessEqual(set(protocol.decode(bytes.fromhex(field))), generic)
        mission = bridge_module.mission_context({'mission': field}, SimpleNamespace(marks=[]))
        return mission, bridge_module.mission_prompt(mission, 'Caller')

    def test_job_and_verified_progress_told_to_the_voice(self):
        sim, voice, store, sheet, m = self.started('route-brief')
        mission, prompt = self.told(voice, voice.context(m, 'not_yet'))
        self.assertEqual((mission['kind'], mission['place']), ('route', 'Point A'))
        self.assertIn('Point A, then Point B, then Point C', mission['job'])
        self.assertIn('Points crossed in order (checked by the server): 0 of 3; next: Point A.', prompt)
        for point in 'abc':
            self.go(sim, store, point)
        heard = voice.heard(sheet, sim.server.g.PLAYERS.alice, sim.character('alice'), 160000, store)
        self.assertEqual((heard.turn, heard.toReport), ('report_due', True))
        _, prompt = self.told(voice, heard)
        self.assertIn('Points crossed in order (checked by the server): 3 of 3; all crossed.', prompt)


class RouteSheetTests(unittest.TestCase):
    """The sheet reader accepts a route section with at least two shared points in points=, and refuses an unknown
    place, a zone, a single point, the same point twice in a row and any other parameter; with the real RS_Persona and
    the template registered as at game load. Shared places of the cases (E25-T01): PLACES and a bridge."""
    # BASE ends at line 4: mission header at 5, type at 6, first key at 7.

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.tmp.name)
        (cls.folder / '_places.txt').write_text(PLACES + place('bridge', '5,6,0', 'Old bridge'), encoding='utf-8')
        cls.lua = LuaPersona(cls.folder)
        cls.lua.rt.eval('require("CoreAI/CA_MissionRoute")')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, body: str):
        text = BASE + '[mission m]\ntype=route\n' + body + PROMPT
        (self.folder / 'case.txt').write_bytes(text.encode('utf-8'))
        return self.lua.read('case.txt')

    def test_valid_section(self):
        p = self.read('points=clinic, bridge,clinic\n')
        self.assertFalse(isinstance(p, tuple), p)
        self.assertEqual(p.missions[1].type, 'route')
        self.assertEqual(list(carnet_helpers.lua_list(p.missions[1].params.points)), ['clinic', 'bridge', 'clinic'])

    def test_refusals(self):
        for body, why in (
                ('points=clinic,nowhere\n', "line 7: unknown place 'nowhere'"),
                ('points=clinic,town\n', 'line 7: ' + ZONE_HERE),
                ('points=clinic\n', 'line 7: bad place list (2 to 8 places)'),
                ('points=clinic,bridge,bridge\n', "line 7: place 'bridge' twice in a row"),
                ('points=' + ','.join(['clinic', 'bridge'] * 5) + '\n', 'line 7: bad place list (2 to 8 places)'),
                ('points=clinic,bridge\ncount=2\n', "line 8: unknown key 'count' for mission type 'route'")):
            with self.subTest(body=body):
                self.assertEqual(self.read(body), (None, why))


class RouteSuiteTests(unittest.TestCase):
    """The in-game suite rs.voiceroute run by the real RST engine on the bench world (server side): three points around
    the player, crossed in order with one skipped point refused, then the report accepted."""
    setUp, tearDown = RouteMissionTests.setUp, RouteMissionTests.tearDown
    voice_sim, world = RouteMissionTests.voice_sim, RouteMissionTests.world

    def test_suite_passes_on_the_bench_world(self):
        sim, _, _ = self.world('route-suite')
        rt, g = sim.server.rt, sim.server.g
        alice = g.PLAYERS.alice
        rt.execute(f'package.path = [[{TESTS_LUA.as_posix()}/shared/?.lua;]] .. package.path')
        rt.execute('require "RST/RST"')
        # A world suite runs only on a test save (rstest*), as in game.
        rt.execute("local grid = getWorld():getMetaGrid(); getWorld = function() return {getGameMode = function() "
                   "return 'Multiplayer' end, getWorld = function() return 'rstest-route' end, "
                   "getMetaGrid = function() return grid end} end")
        rt.execute(f'dofile([[{SUITE.as_posix()}]])')
        report = rt.eval('(function(p) return RST.runSync("rs.voiceroute", {player = p}) end)')(alice)
        results = {r.test: (r.status, r.message) for _, r in report.results.items()}
        self.assertEqual([s for s, _ in results.values()], ['PASS'], results)
        self.assertEqual((alice.x, alice.y), (10, 10), 'player not put back where the suite found them')


if __name__ == '__main__':
    unittest.main()
