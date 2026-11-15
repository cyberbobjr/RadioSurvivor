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
