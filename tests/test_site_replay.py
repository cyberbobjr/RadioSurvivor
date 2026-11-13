"""Site réel des campagnes rejoué au banc (E19-T08, ADR banc mimétique D05).

    python RadioSurvivor/tests/test_site_replay.py

- SiteParseTests, SiteWorldTests (toujours joués) : lecture d'un export synthétique (tests/site_world.py), chargement
  dans les doublures des bancs d'obstacles (tests/test_lk_obstacles.py), aller-retour de l'exporteur en jeu
  (dev/.../RST/suites/RST_SiteExport.lua) sur ce monde, itinéraire LivingKnox par une porte.
- SiteReplayTests (sautés sans export local, site_world.available()) : le vrai site exporté par la suite site.export ;
  itinéraire LivingKnox (LK_Routing : Obstacles.findRoute, modèle "npc") qui passe une porte extérieure, recherches de
  site de la suite lk.traversal (RST.LKTraversal.findSite, findExitSite, findLooseExitSite).
"""
from __future__ import annotations

import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import site_world  # noqa: E402
from test_lk_obstacles import ObstacleBase  # noqa: E402

TRAVERSAL_SUITE = 'shared/RST/suites/RST_LKTraversal.lua'
EXPORT_SUITE = 'shared/RST/suites/RST_SiteExport.lua'

# Maison B1 (x 104..108, y 100..104) : cuisine r1 (x 104..105), chambre r2 (x 106..108) ; dehors autour (x 96..112,
# y 96..108). Porte extérieure fermée sur le bord ouest de (104, 102) ; porte intérieure ouverte (106, 101) W ;
# fenêtre fermée (106, 105) N ; clôture basse (100, 98) N ; escalier (107, 103) ; étage (105, 101, 1) ; lit, frigo.
HOUSE = (104, 100, 108, 104)


def synthetic_export() -> str:
    lines = ['# synthetic site (test_site_replay.py)', 'H 104 102 0 12 42.22.0 test', 'G B1 77 104 100 109 105']
    x1, y1, x2, y2 = HOUSE
    for x in range(96, 113):
        for y in range(96, 109):
            inside = x1 <= x <= x2 and y1 <= y <= y2
            if inside:
                room = ('r1', 'kitchen') if x <= 105 else ('r2', 'bedroom')
                flags = 'blocked' if (x, y) == (108, 104) else '-'
                lines.append(f'S {x} {y} 0 B1 {room[0]} {room[1]} {flags}')
            else:
                flags = 'outside,tree,blocked' if (x, y) == (98, 106) else 'outside'
                lines.append(f'S {x} {y} 0 - - - {flags}')
    lines.append('S 105 101 1 B1 r3 attic nofloor')
    walls = [f'{x1},{y},0,W' for y in range(y1, y2 + 1) if y != 102]
    walls += [f'{x2 + 1},{y},0,W' for y in range(y1, y2 + 1)]
    walls += [f'{x},{y1},0,N' for x in range(x1, x2 + 1)]
    walls += [f'{x},{y2 + 1},0,N' for x in range(x1, x2 + 1) if x != 106]
    walls += [f'106,{y},0,W' for y in range(y1, y2 + 1) if y != 101]
    lines += ['W ' + w.replace(',', ' ') for w in walls]
    lines += ['D 104 102 0 W door -1 -1 -1 -', 'D 106 101 0 W door -1 -1 -1 open',
              'O 106 105 0 N window -', 'F 100 98 0 N', 'T 107 103 0',
              'C 105 101 0 fridge', 'B 107 101 0 goodBed']
    return '\n'.join(lines) + '\n'


def records(site: site_world.Site, kind: str) -> set[tuple]:
    return {tuple(sorted(r.items())) for r in site.of(kind)}


class SiteParseTests(unittest.TestCase):
    """Format de l'export (tests/site_world.py), sans banc Lua."""

    def test_header_and_record_kinds(self):
        site = site_world.parse(synthetic_export())
        self.assertEqual(site.origin, (104, 102, 0))
        self.assertEqual(site.header['radius'], 12)
        self.assertEqual(site.header['version'], '42.22.0 test')
        self.assertEqual(site.of('G'), [{'id': 'B1', 'keyId': 77, 'x1': 104, 'y1': 100, 'x2': 109, 'y2': 105}])
        self.assertEqual(len(site.of('S')), 17 * 13 + 1)
        self.assertIn({'x': 104, 'y': 102, 'z': 0, 'edge': 'W', 'cls': 'door', 'keyId': -1, 'ddi': -1, 'gdi': -1,
                       'flags': frozenset()}, site.of('D'))
        self.assertEqual(site.of('O'), [{'x': 106, 'y': 105, 'z': 0, 'edge': 'N', 'cls': 'window',
                                         'flags': frozenset()}])
        self.assertEqual(site.of('C'), [{'x': 105, 'y': 101, 'z': 0, 'type': 'fridge'}])
        self.assertEqual(site.of('B'), [{'x': 107, 'y': 101, 'z': 0, 'bedType': 'goodBed'}])
        self.assertEqual(site.of('T'), [{'x': 107, 'y': 103, 'z': 0}])

    def test_square_fields_and_flags(self):
        _, inside = site_world.parse_line('S 105 101 0 B1 r1 kitchen -')
        self.assertEqual(inside, {'x': 105, 'y': 101, 'z': 0, 'building': 'B1', 'roomId': 'r1', 'room': 'kitchen',
                                  'flags': frozenset()})
        _, out = site_world.parse_line('S 98 106 0 - - - outside,tree,blocked')
        self.assertIsNone(out['building'])
        self.assertIsNone(out['room'])
        self.assertEqual(out['flags'], frozenset({'outside', 'tree', 'blocked'}))
        _, door = site_world.parse_line('D 1 2 0 N thump 4242 -1 2 locked,lockedByKey')
        self.assertEqual((door['cls'], door['keyId'], door['gdi'], door['flags']),
                         ('thump', 4242, 2, frozenset({'locked', 'lockedByKey'})))

    def test_kahlua_integral_doubles_are_integers(self):
        _, r = site_world.parse_line('T 10650.0 9538.0 0.0')
        self.assertEqual(r, {'x': 10650, 'y': 9538, 'z': 0})
        with self.assertRaises(ValueError):
            site_world.parse_line('T 10650.5 9538 0')

    def test_malformed_exports_are_refused_with_the_line(self):
        cases = {
            'H 1 2 0 70 v\nQ 1 2 3': 'unknown record kind',
            'H 1 2 0 70 v\nW 1 2 0': 'needs 4 fields',
            'H 1 2 0 70 v\nW 1 2 0 W extra': 'has 5 fields',
            'H 1 2 0 70 v\nS x 2 0 - - - -': 'bad x',
            'W 1 2 0 W': 'record before the header',
            'H 1 2 0 70 v\nH 1 2 0 70 v': 'second header',
            '# nothing\n': 'no header',
        }
        for text, why in cases.items():
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, why):
                site_world.parse(text)
        with self.assertRaisesRegex(ValueError, 'line 2'):
            site_world.parse('H 1 2 0 70 v\nQ 1')

    def test_export_search_order(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            env_file, fixture, runs = d / 'env.txt', d / 'fixture' / 'site-export.txt', d / 'runs'
            game = d / 'home' / 'Zomboid' / 'Lua' / 'batman_RadioSurvivor' / 'tests' / 'site-export.txt'
            old, new = runs / 'r1' / 'site-export.txt', runs / 'r2' / 'site-export.txt'
            kw = dict(environ={site_world.ENV_VAR: str(env_file), 'USERPROFILE': str(d / 'home')},
                      runs=runs, fixture=fixture)
            self.assertIsNone(site_world.find_export(**kw))
            for p in (old, new):
                p.parent.mkdir(parents=True)
                p.write_text('H 0 0 0 1 v\n', encoding='ascii')
            os.utime(old, (time.time() - 100, time.time() - 100))
            self.assertEqual(site_world.find_export(**kw), new)
            for p in (fixture, game, env_file):
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('H 0 0 0 1 v\n', encoding='ascii')
                self.assertEqual(site_world.find_export(**kw), p)
            kw['environ'] = {'USERPROFILE': str(d / 'home')}
            self.assertEqual(site_world.find_export(**kw), game)


class SiteBase(ObstacleBase):
    """Banc solo des obstacles avec un site chargé (site_world.install)."""
    mode = 'solo'

    def install(self, site, radius=None):
        self.site = site
        site_world.install(self.h, self.machines, site, radius)
        ox, oy, oz = site.origin
        self.h.move_player('A', ox + 0.5, oy + 0.5, oz)

    def sq(self, x, y, z=0):
        return f'getCell():getGridSquare({x}, {y}, {z})'

    def door_crossings(self, start, target, z=0):
        """Itinéraire LivingKnox (Obstacles.findRoute, modèle "npc") de la case start à la case target : bords des
        portes passées (liste de clés de bord) et nombre d'escalades ; (None, raison) sans itinéraire."""
        doors, climbs = self.run_lua(
            f'local r, _, why = LivingKnox.Obstacles.findRoute("lk-1", {start[0] + 0.5}, {start[1] + 0.5}, '
            f'{target[0]}, {target[1]}, {z}, "npc") '
            'if r == nil then return nil, why end '
            'local d, c = {}, 0 for i = 2, #r do '
            f'local a, b = HARNESS.square(r[i - 1].x, r[i - 1].y, {z}), HARNESS.square(r[i].x, r[i].y, {z}) '
            'if r[i].cross == "door" then d[#d + 1] = EDGE_KEY(a, b) '
            'elseif r[i].cross == "climb" then c = c + 1 end end return table.concat(d, " "), c')
        if doors is None:
            return None, climbs
        return (doors.split() if doors else []), climbs

    def probe_player(self):
        x, y, z = self.site.origin
        return (f'{{ getX = function() return {x + 0.5} end, getY = function() return {y + 0.5} end, '
                f'getZ = function() return {z} end }}')


class SiteWorldTests(SiteBase):
    """Export synthétique chargé dans les doublures : ce que le jeu lirait sur ces cases."""

    def setUp(self):
        super().setUp()
        self.install(site_world.parse(synthetic_export()))

    def test_building_and_room_are_read_per_square(self):
        self.assertEqual(self.ev(f'{self.sq(105, 101)}:getBuildingDef():getIDString()'), 'B1')
        self.assertEqual(self.ev(f'{self.sq(105, 101)}:getRoom():getName()'), 'kitchen')
        self.assertEqual(self.ev(f'{self.sq(107, 101)}:getRoom():getRoomDef():getIDString()'), 'r2')
        self.assertIsNone(self.ev(f'{self.sq(103, 102)}:getBuildingDef()'))
        self.assertIs(self.ev(f'{self.sq(103, 102)}:isOutside()'), True)
        self.assertIs(self.ev(f'{self.sq(105, 101)}:isOutside()'), False)
        self.assertEqual(self.ev('getWorld():getMetaGrid():getBuildingAt(108, 104, 0):getX2()'), 109)
        self.assertIsNone(self.ev('getWorld():getMetaGrid():getBuildingAt(109, 104, 0)'))
        self.assertIs(self.ev(f'{self.sq(108, 104)}:isFree(false)'), False)
        self.assertIs(self.ev(f'{self.sq(98, 106)}:HasTree()'), True)
        self.assertIs(self.ev(f'{self.sq(105, 101, 1)}:TreatAsSolidFloor()'), False)

    def test_edges_carry_walls_doors_windows_fences_and_stairs(self):
        self.assertIs(self.ev(f'{self.sq(104, 101)}:isWallTo({self.sq(103, 101)})'), True)
        self.assertIs(self.ev(f'{self.sq(104, 102)}:isWallTo({self.sq(103, 102)})'), False)
        self.assertEqual(self.state('solo', '104,102,0,W'), 'false false false')
        self.assertEqual(self.state('solo', '106,101,0,W'), 'true false false')
        self.assertEqual(self.ev(f'{self.sq(103, 102)}:getDoorTo({self.sq(104, 102)}):checkKeyId()'), 77)
        self.assertEqual(self.ev(f'{self.sq(106, 101)}:getDoorTo({self.sq(105, 101)}):checkKeyId()'), -1)
        self.assertEqual(self.wstate('solo', '106,105,0,N'), 'false false')
        self.assertIs(self.o(f'isFenceTo({self.sq(100, 97)}, {self.sq(100, 98)})'), True)
        self.assertIs(self.ev(f'{self.sq(107, 103)}:HasStairs()'), True)

    def test_beds_and_containers_are_objects_of_their_square(self):
        self.assertIs(self.ev(f'{self.sq(107, 101)}:getObjects():get(0):getProperties():has(IsoFlagType.bed)'), True)
        self.assertEqual(self.ev(f'{self.sq(107, 101)}:getObjects():get(0):getProperties():get("BedType")'), 'goodBed')
        self.assertEqual(self.ev(f'{self.sq(105, 101)}:getObjects():get(0):getContainerByIndex(0):getType()'),
                         'fridge')

    def test_squares_out_of_the_export_or_far_from_the_players_are_unloaded(self):
        self.assertIsNone(self.ev(self.sq(60, 60)))
        self.assertIsNotNone(self.ev(self.sq(112, 108)))
        self.run_lua('SITE.radius = 5')
        self.assertIsNone(self.ev(self.sq(112, 108)))
        self.assertIsNotNone(self.ev(self.sq(108, 104)))
        self.h.move_player('A', 111.5, 107.5, 0)
        self.assertIsNotNone(self.ev(self.sq(112, 108)))

    def test_route_into_the_house_passes_the_door(self):
        self.init()
        self.assertEqual(self.door_crossings((100, 102), (105, 103)), (['104,102,0,W'], 0))
        self.run_lua('DOORS["104,102,0,W"].barricaded = true')
        doors, _ = self.door_crossings((100, 102), (105, 103))
        self.assertNotIn('104,102,0,W', doors or [])           # porte barricadée : jamais passée

    def test_exporter_round_trip(self):
        """L'exporteur en jeu, joué sur ce monde, rend l'export chargé."""
        self.h.load('solo', EXPORT_SUITE)
        text = self.run_lua('local X = RST.SiteExport local job = X.newJob(104, 102, 0, 12) '
                            'X.advance(job, 1000) return table.concat(job.lines, "\\n")')
        back = site_world.parse(text)
        source = site_world.parse(synthetic_export())
        self.assertEqual(back.origin, source.origin)
        self.assertEqual(back.header['radius'], 12)
        for kind in site_world.KINDS:
            if kind != 'H':
                self.assertEqual(records(back, kind), records(source, kind), kind)
        self.assertEqual(self.h.errors('solo'), [])


@unittest.skipUnless(site_world.available(), 'no local site export (RS_SITE_EXPORT, Zomboid/Lua/batman_RadioSurvivor/'
                     'tests/site-export.txt, tests/fixtures/local/, tools/autoclient/runs/): run the suite site.export')
class SiteReplayTests(SiteBase):
    """Vrai site des campagnes (export local)."""
    DOOR_TRIES = 10

    @classmethod
    def setUpClass(cls):
        cls.export = site_world.load_export()

    def setUp(self):
        super().setUp()
        self.install(self.export)
        self.h.load('solo', TRAVERSAL_SUITE)
        self.init()

    def walkable(self):
        z = self.export.origin[2]
        return {(r['x'], r['y']) for r in self.export.of('S') if r['z'] == z
                and not r['flags'] & {'blocked', 'nofloor'}} - {(r['x'], r['y']) for r in self.export.of('T')}

    def door_lanes(self):
        """Portes extérieures simples, ni barricadées, ni verrouillées (sauf ouvertes), ni portails, du niveau de
        l'origine : (case de départ dehors, case visée dedans) à deux cases de part et d'autre, la plus proche
        d'abord."""
        ox, oy, oz = self.export.origin
        inside = {(r['x'], r['y']) for r in self.export.of('S') if r['z'] == oz and r['building']}
        free = self.walkable()
        out = []
        for d in self.export.of('D'):
            f = d['flags']
            if d['z'] != oz or d['ddi'] != -1 or d['gdi'] != -1 or f & {'barricaded', 'hoppable', 'obstructed'}:
                continue
            if 'open' not in f and f & {'locked', 'lockedByKey', 'padlock'}:
                continue
            b = (d['x'], d['y'])
            a = (b[0] - 1, b[1]) if d['edge'] == 'W' else (b[0], b[1] - 1)
            if (a in inside) == (b in inside):
                continue
            o, i = (a, b) if b in inside else (b, a)
            dx, dy = i[0] - o[0], i[1] - o[1]
            lane = [(o[0] - k * dx, o[1] - k * dy) for k in (2, 1, 0)] + [(i[0] + k * dx, i[1] + k * dy)
                                                                         for k in (0, 1, 2)]
            if all(p in free for p in lane):
                out.append((abs(b[0] - ox) + abs(b[1] - oy), lane[0], lane[-1]))
        return [(s, t) for _, s, t in sorted(out)]

    def test_route_through_an_exterior_door(self):
        lanes = self.door_lanes()
        if not lanes:
            self.skipTest('no single unlocked exterior door with a free lane at the origin level')
        tried = []
        for start, target in lanes[:self.DOOR_TRIES]:
            doors, why = self.door_crossings(start, target, self.export.origin[2])
            tried.append((start, target, doors, why))
            if doors:
                break
        else:
            self.fail(f'no LivingKnox route through a door: {tried}')
        self.assertEqual(self.h.errors('solo'), [])

    def test_traversal_window_site(self):
        res = self.run_lua(f'local s = RST.LKTraversal.findSite({self.probe_player()}, RST.LKTraversal.pickWindow) '
                           'return s and s.e.key')
        self.assertIsNotNone(res, 'lk.traversal: no window site around the origin')

    def test_traversal_exit_site(self):
        res = self.run_lua(f'local s = RST.LKTraversal.findExitSite({self.probe_player()}) return s and s.e.key')
        self.assertIsNotNone(res, 'lk.traversal: no exit site (window routed through a door by the exit rule)')

    def test_traversal_loose_exit_site(self):
        res = self.run_lua(f'local s = RST.LKTraversal.findLooseExitSite({self.probe_player()}) '
                           'return s and s.e.key')
        self.assertIsNotNone(res, 'lk.traversal: no loose exit site (door of another building to lock)')


if __name__ == '__main__':
    unittest.main()
