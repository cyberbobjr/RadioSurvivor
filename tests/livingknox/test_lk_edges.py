"""Tests hors jeu des règles des bords de cases (LK17-T03, ADR adr-bords-des-cases.md D02) :
shared/LivingKnox/Edges/LK_EdgeRules.lua, fonctions pures sur les faits que rend LivingKnox.Edges.read.

    python tests/livingknox/test_lk_edges.py

Aucune carte : chaque cas est une table de faits (vrai Lua du mod sous lupa, Lua 5.1, `next` retiré comme dans Kahlua).
Les bancs des appelants (test_lk_obstacles, test_lk_movement, test_lk_stop_place, test_lk_detour) restent la preuve
que la lecture du jeu et la composition n'ont pas changé le comportement.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
LK_SHARED = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'shared'
R = 'LivingKnox.EdgeRules'

FREE = '{}'
WALL = '{ wall = true, blocked = true }'
STAIRS = '{ blocked = true }'
CLOSED_DOOR = '{ door = { open = false, lowGate = false }, blocked = true }'
OPEN_DOOR = '{ door = { open = true, lowGate = false } }'
LOW_GATE = '{ door = { open = false, lowGate = true }, hoppable = true }'
CLOSED_WINDOW = '{ window = { kind = "window", open = false, destroyed = false, barricaded = false } }'
OPEN_WINDOW = '{ window = { kind = "window", open = true, destroyed = false, barricaded = false } }'
BROKEN_WINDOW = '{ window = { kind = "window", open = false, destroyed = true, barricaded = false } }'
BOARDED_WINDOW = '{ window = { kind = "window", open = true, destroyed = false, barricaded = true } }'
FRAME = '{ window = { kind = "frame", barricaded = false } }'
BOARDED_FRAME = '{ window = { kind = "frame", barricaded = true } }'
FENCE = '{ fence = true, hoppable = true }'
HOPPABLE_UNDER_WALL = '{ hoppable = true, wall = true, blocked = true }'


class EdgeRulesTests(unittest.TestCase):
    def setUp(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        self.rt.globals().next = None   # absent de Kahlua
        self.rt.execute(f'package.path = [[{LK_SHARED.as_posix()}/?.lua;]]; package.cpath = ""')
        self.rt.execute('require "LivingKnox/Edges/LK_EdgeRules"')

    def call(self, fn, *args):
        return self.rt.execute(f'return {R}.{fn}({", ".join(args)})')

    def test_closed_to_walking(self):
        for edge in (WALL, STAIRS, CLOSED_DOOR, OPEN_DOOR, LOW_GATE, CLOSED_WINDOW, OPEN_WINDOW, FRAME, FENCE):
            with self.subTest(edge=edge):
                self.assertIs(self.call('closed', edge), True)
        self.assertIs(self.call('closed', FREE), False)

    def test_door_stops_the_body_when_closed_and_not_a_low_gate(self):
        self.assertIs(self.call('doorStops', '{ open = false, lowGate = false }'), True)
        self.assertIs(self.call('doorStops', '{ open = true, lowGate = false }'), False)
        self.assertIs(self.call('doorStops', '{ open = false, lowGate = true }'), False)

    def test_window_stops_the_body_when_closed_and_whole_or_boarded(self):
        cases = {CLOSED_WINDOW: True, OPEN_WINDOW: False, BROKEN_WINDOW: False, BOARDED_WINDOW: True,
                 FRAME: False, BOARDED_FRAME: True}
        for edge, stops in cases.items():
            with self.subTest(edge=edge):
                self.assertIs(self.rt.execute(f'return {R}.windowStops(({edge}).window)'), stops)

    def test_arrival_is_not_reached_across_a_closed_door_a_window_or_a_wall(self):
        cases = {CLOSED_DOOR: True, OPEN_DOOR: False, LOW_GATE: False, CLOSED_WINDOW: True, OPEN_WINDOW: True,
                 FRAME: True, WALL: True, FENCE: False, FREE: False}
        for edge, stops in cases.items():
            with self.subTest(edge=edge):
                self.assertIs(self.call('stopsArrival', edge), stops)

    def test_diagonal_arrival_only_on_the_same_side_of_the_building(self):
        self.assertIs(self.call('stopsDiagonalArrival', 'true', 'false'), True)
        self.assertIs(self.call('stopsDiagonalArrival', 'false', 'true'), True)
        self.assertIs(self.call('stopsDiagonalArrival', 'true', 'true'), False)
        self.assertIs(self.call('stopsDiagonalArrival', 'false', 'false'), False)

    def sides(self, n='nil', e='nil', s='nil', w='nil'):
        return f'{{ [1] = {n}, [2] = {e}, [3] = {s}, [4] = {w} }}'

    @staticmethod
    def side(edge=FREE, walkable=True):
        return f'{{ walkable = {str(walkable).lower()}, edge = {edge} }}'

    def test_stop_place_refused_on_a_door_edge_open_or_closed(self):
        for door in (CLOSED_DOOR, OPEN_DOOR, LOW_GATE):
            with self.subTest(door=door):
                sides = self.sides(self.side(), self.side(door), self.side(), self.side())
                self.assertEqual(self.call('stopRefusal', sides), self.rt.eval(f'{R}.DOOR'))

    def test_stop_place_refused_in_a_one_square_wide_passage(self):
        free = self.side()
        for sides in (self.sides(self.side(WALL), free, 'nil', free),
                      self.sides(free, self.side(CLOSED_WINDOW), free, self.side(walkable=False))):
            with self.subTest(sides=sides):
                self.assertEqual(self.call('stopRefusal', sides), self.rt.eval(f'{R}.NARROW'))

    def test_stop_place_allowed_with_two_adjacent_closed_sides(self):
        free = self.side()
        self.assertIsNone(self.call('stopRefusal', self.sides(self.side(WALL), self.side(WALL), free, free)))
        self.assertIsNone(self.call('stopRefusal', self.sides(free, free, free, free)))

    def test_corridor_step(self):
        yes, no = 'function() return true end', 'function() return false end'
        self.assertIs(self.call('corridorStep', FREE, no), True)
        self.assertIs(self.call('corridorStep', CLOSED_DOOR, yes), True)    # porte : la règle de contact décide
        self.assertIs(self.call('corridorStep', OPEN_DOOR, no), False)
        for edge in (OPEN_WINDOW, BROKEN_WINDOW, FRAME, FENCE, WALL, STAIRS):
            with self.subTest(edge=edge):
                self.assertIs(self.call('corridorStep', edge, yes), False)
        # Objet enjambable que le moteur ne voit pas comme une clôture (sous un mur) : le mur décide.
        self.assertIs(self.call('corridorStep', HOPPABLE_UNDER_WALL, yes), False)
        self.assertIs(self.call('corridorStep', '{ hoppable = true }', yes), True)


if __name__ == '__main__':
    unittest.main()
