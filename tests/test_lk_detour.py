"""Tests hors jeu du détour après un refus au contact (LK17-T01, ADR docs/architecture/decisions/adr-chemin-vanilla.md) :
LK_Detour.lua (autorité), Directives.reroute (LK_Directives.lua), refus de LK_Obstacles.lua.

    python tests/test_lk_detour.py

Banc et doublures de tests/test_lk_obstacles.py (portes, fenêtres, clôtures, bâtiments ; ObstacleBase charge aussi
LK_Detour.lua, dont les sources sont contrôlées par SourceTests de ce banc). La marche des doublures va en ligne droite
vers l'étape courante (STEP_W) et s'arrête contre une porte ou une fenêtre fermée : elle tient lieu du chemin du jeu,
qui traverse une fenêtre sans surcoût pour un corps de zombie. Seuls les points de passage du détour font passer le
corps par une porte. Preuve de la logique Lua, pas du chemin natif réel.

Maison WALLED (B5, x 100..105, y 100..109) : mur extérieur sur le bord ouest de x = 106 ; corps dedans en (103, 102),
destination dehors (111, 102), droit sur la fenêtre (106, 102) W ; porte (106, 107) W dans le même mur.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_obstacles import SENT, ObstacleBase  # noqa: E402

WALLED = {'id': 'B5', 'x1': 100, 'y1': 100, 'x2': 106, 'y2': 110}
WINDOW_KEY = '106,102,0,W'
DOOR_KEY = '106,107,0,W'
START = (103, 102)
TARGET = (111, 102)


class DetourBase(ObstacleBase):
    def house(self, window=None, door=None, home=False):
        """Maison WALLED, fenêtre (106, 102) W (champs window) et porte (106, 107) W (champs door, None : aucune)."""
        self.building(WALLED)
        self.window(x=106, y=102, **(window or {}))
        if door is not None:
            self.door(x=106, y=107, **door)
        self.init()
        if home:
            return self.group(member=False, home=(102, 104, 0), name='Owners')
        return None

    def body(self, at=START):
        _, b = self.spawn(x=at[0], y=at[1])
        return b.onlineID

    def go(self, target=TARGET):
        return self.d(f'moveTo("lk-1", {target[0]}, {target[1]}, 0)')

    def steps(self):
        w = self.entry('w')
        return [] if w is None else [(w[i].x, w[i].y) for i in range(1, len(w) + 1)]

    def rerouted(self):
        return lambda: self.entry('w') is not None or self.entry('lr') is True or self.ev(
            'LivingKnox.Directives.entries["lk-1"].done') is True


class SoloDetourTests(DetourBase):
    mode = 'solo'

    def test_refused_sealed_window_gives_a_detour_through_the_nearest_door_at_once(self):
        self.house(window={'locked': True}, door={})
        zid = self.body()
        v = self.go()
        self.assertIsNone(self.entry('w'))                       # chemin du jeu seul au départ
        self.walk_w(zid, 1500, until=self.rerouted())
        # Refusée au contact : même consigne (même numéro), aussitôt rendue avec le détour par la porte voisine.
        self.assertIs(self.entry('done'), False)
        self.assertEqual(self.entry('v'), v)
        self.assertEqual(self.steps(), [(105, 107), (106, 107)])
        self.assertIsNone(self.entry('lr'))
        self.assertEqual(self.o('lastRefused.key'), WINDOW_KEY)
        self.assertTrue(any('detour through the door 106,107,0,W' in s for s in self.lk()), self.lk())
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('v'), v)
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.wstate('solo', WINDOW_KEY), 'false false')   # fenêtre jamais touchée
        self.assertTrue(any('door 106,107,0,W opened' in s for s in self.lk()), self.lk())
        # Aucune case écartée après un détour (pas d'évitement de 60 s) : la même destination est acceptée.
        again = self.go()
        self.assertNotIsInstance(again, tuple, again)
        self.assertEqual(self.h.errors('solo'), [])

    def test_refused_door_of_another_group_home_gives_a_detour_through_another_door(self):
        # Foyer FOREIGN d'un autre groupe (x 106..111, y 100..104) sur la ligne droite (102, 102) -> (114, 102) dehors :
        # sa porte (106, 102) W est refusée ; la porte de jardin (106, 106) W, dehors des deux côtés, sert de détour.
        self.building({'id': 'F1', 'x1': 106, 'y1': 100, 'x2': 112, 'y2': 105})
        self.door(x=106, y=102)
        self.door(x=106, y=106)
        self.init()
        gid = self.group(member=False, home=(108, 102, 0), name='Owners')
        zid = self.body(at=(102, 102))
        v = self.go(target=(114, 102))
        self.walk_w(zid, 1500, until=self.rerouted())
        self.assertIs(self.entry('done'), False)
        self.assertEqual(self.entry('v'), v)
        self.assertEqual(self.o('lastRefused.why'), f'door of the home of {gid} (not a member)')
        self.assertEqual(self.steps(), [(105, 106), (106, 106)])
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.state('solo', '106,102,0,W'), 'false false false')   # porte du foyer jamais ouverte
        self.assertEqual(self.h.errors('solo'), [])

    def test_trapped_inside_without_usable_door_last_resort_through_the_locked_window(self):
        # Seule porte barricadée : aucune porte pour sortir ; corps dedans : dernier recours (LK04-T20), la fenêtre
        # verrouillée abordée de l'intérieur est permise au contact.
        self.house(window={'locked': True}, door={'barricaded': True})
        zid = self.body()
        v = self.go()
        self.walk_w(zid, 1500, until=self.rerouted())
        self.assertIs(self.entry('done'), False)
        self.assertEqual(self.entry('v'), v)
        self.assertIs(self.entry('lr'), True)
        self.assertEqual(self.steps(), [])                       # même ouverture : aucun point, chemin du jeu
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + WINDOW_KEY])
        self.assertEqual(self.state('solo', DOOR_KEY), 'false false false')       # barricadée : jamais touchée
        self.assertEqual(self.h.errors('solo'), [])

    def test_trapped_in_the_home_of_another_group_out_through_its_door(self):
        # LK04-T20 (campagne MP du 2026-10-15, lk-7) : PNJ sans groupe dans le foyer d'un autre groupe ; la porte
        # (106, 107) W est refusée (foyer d'un autre groupe), aucune autre porte : dernier recours, la même porte
        # abordée de l'intérieur.
        gid = self.house(window={'locked': True}, door={}, home=True)
        zid = self.body(at=(103, 107))
        self.go(target=(111, 107))
        self.walk_w(zid, 1500, until=self.rerouted())
        self.assertEqual(self.o('lastRefused.why'), f'door of the home of {gid} (not a member)')
        self.assertIs(self.entry('lr'), True)
        self.assertEqual(self.steps(), [])
        self.assertTrue(any('last resort through the refused door ' + DOOR_KEY in s for s in self.lk()), self.lk())
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertTrue(any('door 106,107,0,W opened' in s for s in self.lk()), self.lk())
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_move_without_any_refusal_has_no_waypoint(self):
        # Fenêtre fermée ordinaire sur le chemin, porte à côté : aucun point de passage, la fenêtre est ouverte au
        # contact et franchie (chemin du jeu seul).
        self.house(door={})
        zid = self.body()
        self.go()
        self.assertIsNone(self.entry('w'))
        self.assertIsNone(self.entry('lr'))
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertIsNone(self.entry('w'))
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + WINDOW_KEY])
        self.assertEqual(self.o('stats.refused'), 0)

    def test_no_usable_door_outside_keeps_the_refusal(self):
        # Corps dehors, fenêtre verrouillée, porte barricadée : aucun détour, aucun dernier recours (dehors) : refus.
        self.house(window={'locked': True}, door={'barricaded': True})
        zid = self.body(at=(113, 102))
        self.go(target=(102, 102))
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertIsNone(self.entry('lr'))
        self.assertEqual(self.o('lastRefused.why'), 'locked window')
        self.assertTrue(any('no detour after the refused window ' + WINDOW_KEY in s for s in self.lk()), self.lk())

    def test_refused_opening_is_never_taken_by_a_later_detour_of_the_same_move(self):
        # Fenêtre refusée : détour par la porte la plus proche (106, 104) W. Cette porte refusée à son tour (refus
        # rejoué ici) : le détour suivant prend (106, 108) W, jamais une ouverture déjà refusée pendant ce trajet,
        # même si les règles de contact la jugent utilisable.
        self.house(window={'locked': True})
        self.door(x=106, y=104)
        self.door(x=106, y=108)
        zid = self.body()
        v = self.go()
        self.walk_w(zid, 1500, until=self.rerouted())
        self.assertEqual(self.steps(), [(105, 104), (106, 104)])
        rerouted = self.run_lua(
            'local O = LivingKnox.Obstacles local c = getCell() '
            'local cand = { e = O.edge(105, 104, 0, "W"), sqA = c:getGridSquare(105, 104, 0), '
            'sqB = c:getGridSquare(106, 104, 0), door = DOORS["106,104,0,W"] } '
            'return LivingKnox.Detour.afterRefusal("lk-1", LivingKnox.Directives.entries["lk-1"], cand, '
            '"test refusal", "door")')
        self.assertIs(rerouted, True)
        self.assertEqual(self.entry('v'), v)
        self.assertEqual(self.steps(), [(105, 108), (106, 108)])
        # Même ouverture refusée une seconde fois pendant ce trajet : plus de détour, refus inchangé.
        again = self.run_lua(
            'local O = LivingKnox.Obstacles local c = getCell() '
            'local cand = { e = O.edge(105, 104, 0, "W"), sqA = c:getGridSquare(105, 104, 0), '
            'sqB = c:getGridSquare(106, 104, 0), door = DOORS["106,104,0,W"] } '
            'return LivingKnox.Detour.afterRefusal("lk-1", LivingKnox.Directives.entries["lk-1"], cand, '
            '"test refusal", "door")')
        self.assertIs(again, False)


def crossed_edges(points, forbidden):
    """Bords interdits (clés « x,y,0,W|N ») traversés par la ligne brisée points (coordonnées réelles), échantillonnée au
    quart de case comme Directives.hazardsOnLine ; passage en diagonale par un coin : les deux bords de chacun des deux
    chemins en L comptent (le chemin du jeu peut prendre l'un ou l'autre). Oracle indépendant du module testé."""
    def edge(a, b):
        (ax, ay), (bx, by) = a, b
        if bx == ax + 1:
            return f'{bx},{by},0,W'
        if bx == ax - 1:
            return f'{ax},{ay},0,W'
        if by == ay + 1:
            return f'{bx},{by},0,N'
        return f'{ax},{ay},0,N'

    hits = []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        n = max(1, int(((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5 * 4) + 1)
        cur = (int(x0 // 1), int(y0 // 1))
        for i in range(1, n + 1):
            nxt = (int((x0 + (x1 - x0) * i / n) // 1), int((y0 + (y1 - y0) * i / n) // 1))
            if nxt == cur:
                continue
            if nxt[0] != cur[0] and nxt[1] != cur[1]:
                m1, m2 = (nxt[0], cur[1]), (cur[0], nxt[1])
                keys = [edge(cur, m1), edge(m1, nxt), edge(cur, m2), edge(m2, nxt)]
            else:
                keys = [edge(cur, nxt)]
            hits += [k for k in keys if k in forbidden]
            cur = nxt
    return hits


# Maison WALLED vue de l'ouest (correctif du 2026-11-15, campagne tools/autoclient/runs/20261115-193703-95dea46b0c64) :
# murs sur tout son pourtour, fenêtre verrouillée sur le mur ouest (100, 102) W, porte sur le mur est (106, 104) W.
WEST_WINDOW = (100, 102)
WEST_WINDOW_KEY = '100,102,0,W'
EAST_DOOR = (106, 104)
EAST_DOOR_KEY = '106,104,0,W'


def house_walls(skip=()):
    keys = [f'100,{y},0,W' for y in range(100, 110)] + [f'106,{y},0,W' for y in range(100, 110)]
    keys += [f'{x},100,0,N' for x in range(100, 106)] + [f'{x},110,0,N' for x in range(100, 106)]
    return [k for k in keys if k not in skip]


class CorridorDetourTests(DetourBase):
    """Couloir d'approche du détour (LK_DetourCorridor.lua) : du corps à la case avant de la porte choisie, chaque
    segment droit entre deux points ne traverse ni mur, ni fenêtre, ni porte, ni clôture basse ; pour un corps de zombie
    une fenêtre ne coûte rien au chemin natif (base pz-knowledge pathfinding-and-obstacles.md), le chemin le plus court
    entre deux points n'a alors aucune raison de repasser par la fenêtre refusée."""
    mode = 'solo'

    def walls(self, keys):
        for m in self.machines:
            self.h.load(m, '; '.join(f'WALLS["{k}"] = true' for k in keys))

    def west_house(self, doors=(EAST_DOOR,), extra_walls=()):
        """Maison WALLED murée, fenêtre verrouillée WEST_WINDOW, portes doors : (x, y, kind) ou (x, y) (bord W)."""
        self.building(WALLED)
        self.window(x=WEST_WINDOW[0], y=WEST_WINDOW[1], locked=True)
        skip = [WEST_WINDOW_KEY]
        for d in doors:
            kind = d[2] if len(d) > 2 else 'W'
            self.door(x=d[0], y=d[1], kind=kind)
            skip.append(f'{d[0]},{d[1]},0,{kind}')
        self.walls(house_walls(skip) + list(extra_walls))
        self.init()
        return set(house_walls(skip)) | set(extra_walls) | set(skip)

    def plan_on(self, rows, start, target, margin=15):
        """Couloir de LK_DetourCorridor.plan sur une grille dessinée (rows : '#' case impraticable, '.' libre ; x =
        colonne, y = ligne), accès aux cases injecté. Rend 'x,y x,y' (coins) ou None (inaccessible)."""
        lua_rows = ', '.join(f'"{r}"' for r in rows)
        code = (f'local rows = {{ {lua_rows} }} local made = {{}} '
                'local grid = { square = function(x, y) local r = rows[y + 1] '
                'if r == nil or x < 0 or x >= #r then return nil end local k = x .. "," .. y '
                'made[k] = made[k] or { x = x, y = y, c = r:sub(x + 1, x + 1) } return made[k] end, '
                'open = function(a, b) return a.c ~= "#" and b.c ~= "#" end } '
                f'local p = LivingKnox.DetourCorridor.plan(grid, {start[0] + 0.5}, {start[1] + 0.5}, {target[0]}, '
                f'{target[1]}, {margin}) '
                'if p == nil then return nil end local out = {} '
                'for i, c in ipairs(p) do out[i] = c.x .. "," .. c.y end return table.concat(out, " ")')
        return self.run_lua(code)

    @staticmethod
    def blocked_on(rows, points):
        """Cases '#' traversées par la ligne brisée points (centres de cases), au quart de case."""
        hits = []
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            n = max(1, int(((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5 * 4) + 1)
            for i in range(n + 1):
                x, y = int((x0 + (x1 - x0) * i / n) // 1), int((y0 + (y1 - y0) * i / n) // 1)
                if rows[y][x] == '#':
                    hits.append((x, y))
        return hits

    # Module seul (accès aux cases injecté) ----------------------------------------------------------------------
    def test_corridor_straight_clear_line_adds_no_point(self):
        self.init()
        self.assertEqual(self.plan_on(['.......'] * 5, (0, 2), (6, 2)), '')

    def test_corridor_goes_around_a_wall_with_clear_segments(self):
        self.init()
        rows = ['.......',
                '..#....',
                '..#....',
                '..#....',
                '.......']
        got = self.plan_on(rows, (0, 2), (4, 2))
        self.assertIsNotNone(got)
        corners = [tuple(int(v) for v in c.split(',')) for c in got.split()]
        self.assertTrue(1 <= len(corners) <= 2, corners)
        points = [(0.5, 2.5)] + [(x + 0.5, y + 0.5) for x, y in corners] + [(4.5, 2.5)]
        self.assertEqual(self.blocked_on(rows, points), [])
        self.assertEqual(self.plan_on(rows, (0, 2), (4, 2)), got)                 # déterministe

    def test_corridor_unreachable_target_gives_nil(self):
        self.init()
        rows = ['.......',
                '...###.',
                '...#.#.',
                '...###.',
                '.......']
        self.assertIsNone(self.plan_on(rows, (0, 2), (4, 2)))

    def test_corridor_target_beyond_the_box_gives_nil(self):
        # Seul passage à 3 lignes du corps et de la cible : hors d'une boîte de marge 1.
        self.init()
        rows = ['.......',
                '.......',
                '.......',
                '..#....',
                '..#....',
                '..#....']
        self.assertIsNotNone(self.plan_on(rows, (0, 4), (4, 4), margin=3))
        self.assertIsNone(self.plan_on(rows, (0, 4), (4, 4), margin=1))

    # Détour complet --------------------------------------------------------------------------------------------
    def test_refused_window_seen_from_outside_detour_goes_around_the_house(self):
        forbidden = self.west_house()
        zid = self.body(at=(96, 102))
        v = self.go(target=(103, 102))
        self.walk_w(zid, 1500, until=self.rerouted())
        self.assertEqual(self.entry('v'), v)
        self.assertEqual(self.o('lastRefused.key'), WEST_WINDOW_KEY)
        zb = self.h.zombie('solo', zid)
        steps = self.steps()
        self.assertEqual(steps[-2:], [(106, 104), (105, 104)], steps)          # case avant, case après la porte
        self.assertGreater(len(steps), 2, steps)                                # coins pour longer la maison dehors
        path = [(zb.x, zb.y)] + [(x + 0.5, y + 0.5) for x, y in steps[:-1]]
        self.assertEqual(crossed_edges(path, forbidden), [], path)
        self.assertEqual(self.entry('dk'), len(steps))                          # tous ces points mènent à la porte
        self.walk_w(zid, 4000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('v'), v)
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.wstate('solo', WEST_WINDOW_KEY), 'false false')
        self.assertFalse(any('refused again' in s for s in self.lk()), self.lk())
        self.assertTrue(any('door ' + EAST_DOOR_KEY + ' opened' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('solo'), [])

    def yard(self):
        """Cour fermée à l'ouest de la maison (x 95..99, y 98..108) : murs ouest, nord, sud, et bord ouest de x = 100
        aux lignes 98 et 99 ; la maison ferme le côté est."""
        keys = [f'95,{y},0,W' for y in range(98, 109)] + [f'{x},98,0,N' for x in range(95, 100)]
        keys += [f'{x},109,0,N' for x in range(95, 100)] + ['100,98,0,W', '100,99,0,W']
        return keys

    def test_unreachable_nearer_door_is_skipped_for_a_reachable_one(self):
        # Porte nord (101, 100) N plus proche du corps, mais sa case avant (101, 99) est hors de la cour : écartée ;
        # porte de la cour (100, 107) W retenue, en ligne droite le long du mur (aucun coin).
        self.west_house(doors=((101, 100, 'N'), (100, 107)), extra_walls=self.yard())
        zid = self.body(at=(97, 102))
        self.go(target=(103, 102))
        self.walk_w(zid, 1500, until=self.rerouted())
        self.assertEqual(self.o('lastRefused.key'), WEST_WINDOW_KEY)
        self.assertEqual(self.steps(), [(99, 107), (100, 107)])
        self.walk_w(zid, 4000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_reachable_door_keeps_the_refusal(self):
        # Seule porte hors de la cour : aucun détour (corps dehors, pas de dernier recours) : refus inchangé.
        self.west_house(doors=((101, 100, 'N'),), extra_walls=self.yard())
        zid = self.body(at=(97, 102))
        self.go(target=(103, 102))
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.o('lastRefused.key'), WEST_WINDOW_KEY)
        self.assertTrue(any('no detour after the refused window ' + WEST_WINDOW_KEY in s for s in self.lk()),
                        self.lk())


class SuiteDetourTests(DetourBase):
    """Test « locked window: refused, detour through a door of the house » de lk.traversal (RST_LKTraversal.lua) joué au
    banc : recherche du site (findDetourSite), fenêtre verrouillée par le test, détour, arrivée, fenêtre rendue."""
    mode = 'solo'

    def test_suite_detour_test_passes_on_the_bench(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        self.house(door={})
        probe = ('local s = RST.LKTraversal.findDetourSite({ getX = function() return 100 end, getY = function() '
                 'return 102 end, getZ = function() return 0 end }) '
                 'return s and s.e.key, s and s.doorEdges[1].key')
        self.assertEqual(self.run_lua(probe), (WINDOW_KEY, DOOR_KEY))
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.traversal", tags = "world", test = '
                                          '"locked window: refused, detour through a door of the house" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(8000):
            self.h.tick()
            self.h.load('solo', 'for id, z in pairs(LivingKnox.Bodies.bound) do z.onFloor = false; '
                                'STEP_W(z.onlineID, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.wstate('solo', WINDOW_KEY), 'false false')       # fenêtre rendue (ni ouverte, ni cassée)
        self.assertIs(self.ev(f'WINDOWS["{WINDOW_KEY}"].locked'), False)       # verrou rendu tel qu'il était


class MultiplayerDetourTests(DetourBase):
    """Serveur dédié : le serveur refuse au contact et décide du détour ; A simule le corps et suit les points reçus."""
    mode = 'mp'

    def setUp(self):
        super().setUp()
        SENT.clear()

    def test_server_decides_the_detour_and_the_owner_follows_it(self):
        self.house(window={'locked': True}, door={})
        _, body = self.spawn(x=START[0], y=START[1])
        zid = body.onlineID
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.pump()
        v = self.go()
        self.h.pump()
        self.walk_w(zid, 1500, until=self.rerouted())
        self.h.pump()
        self.assertEqual(self.entry('v'), v)
        self.assertEqual(self.steps(), [(105, 107), (106, 107)])
        self.assertEqual(self.h.eval('A', '#LivingKnox.Executor.remote.d["lk-1"].w'), 2)
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('A'), [])
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.wstate(m, WINDOW_KEY), 'false false', m)
        self.assertEqual(self.h.errors('server'), [])

    def test_server_gives_the_last_resort_and_the_owner_climbs_the_locked_window(self):
        # LK04-T20 en MP : dernier recours décidé sur le serveur (e.lr jamais envoyé), fenêtre ouverte par le serveur,
        # franchie par le corps que simule A, refermée derrière lui.
        self.house(window={'locked': True}, door={'barricaded': True})
        _, body = self.spawn(x=START[0], y=START[1])
        zid = body.onlineID
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.pump()
        v = self.go()
        self.h.pump()
        self.walk_w(zid, 1500, until=self.rerouted())
        self.h.pump()
        self.assertEqual(self.entry('v'), v)
        self.assertIs(self.entry('lr'), True)
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.remote.d["lk-1"].lr'))   # jamais envoyé
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('A'), ['climbwindow ' + WINDOW_KEY])
        self.assertEqual(self.wcount('A'), (0, 0))                               # bascules sur le serveur seulement
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.wstate(m, WINDOW_KEY), 'false false', m)     # ouverte puis refermée derrière
        self.assertEqual(self.h.errors('server'), [])


if __name__ == '__main__':
    unittest.main()
