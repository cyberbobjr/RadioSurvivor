"""Tests hors jeu des petites fonctions pures communes de Living Knox (LK20-T01, ADR simplification D01).

    python tests/test_lk_num_geo.py

LivingKnox.Num (finite, isInt, clamp) et LivingKnox.Geo (cheb, angleGap, squaresAround), chargés par LK_Core :
une seule copie, appelée par les modules au moment de l'exécution. Banc tests/harness.py (fonctions pures).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402


class NumGeo(unittest.TestCase):
    def setUp(self):
        self.h = Harness(with_rs=False, mode='solo')
        self.h.load('solo', 'shared/LivingKnox/LK_Core.lua')

    def tearDown(self):
        self.h.close()

    def ev(self, expr):
        return self.h.eval('solo', expr)

    def test_core_loads_num_and_geo(self):
        self.assertTrue(self.ev('type(LivingKnox.Num) == "table" and type(LivingKnox.Geo) == "table"'))
        self.assertTrue(self.ev('require("LivingKnox/LK_Num") == LivingKnox.Num'))
        self.assertTrue(self.ev('require("LivingKnox/LK_Geo") == LivingKnox.Geo'))

    def test_finite(self):
        N = 'LivingKnox.Num.finite'
        self.assertTrue(self.ev(f'{N}(0) and {N}(-5.5) and {N}(999999999)'))
        self.assertFalse(self.ev(f'{N}(0/0) or {N}(1/0) or {N}(-1/0) or {N}(1e9) or {N}(-1e9)'))
        self.assertFalse(self.ev(f'{N}("1") or {N}(nil) or {N}({{}})'))

    def test_is_int(self):
        N = 'LivingKnox.Num.isInt'
        self.assertTrue(self.ev(f'{N}(3, 1, 5) and {N}(1, 1, 5) and {N}(5, 1, 5)'))
        self.assertFalse(self.ev(f'{N}(0, 1, 5) or {N}(6, 1, 5) or {N}(2.5, 1, 5)'))
        self.assertFalse(self.ev(f'{N}(0/0, -10, 10) or {N}("3", 1, 5) or {N}(nil, 1, 5)'))

    def test_clamp(self):
        N = 'LivingKnox.Num.clamp'
        self.assertEqual(self.ev(f'{N}(-3, 0, 10)'), 0)
        self.assertEqual(self.ev(f'{N}(12, 0, 10)'), 10)
        self.assertEqual(self.ev(f'{N}(4.5, 0, 10)'), 4.5)

    def test_cheb(self):
        self.assertEqual(self.ev('LivingKnox.Geo.cheb(0, 0, 3, -7)'), 7)
        self.assertEqual(self.ev('LivingKnox.Geo.cheb(2.5, 1, 0, 0)'), 2.5)
        self.assertEqual(self.ev('LivingKnox.Geo.cheb(4, 4, 4, 4)'), 0)

    def test_angle_gap(self):
        G = 'LivingKnox.Geo.angleGap'
        self.assertEqual(self.ev(f'{G}(10, 350)'), 20)
        self.assertEqual(self.ev(f'{G}(0, 180)'), 180)
        self.assertEqual(self.ev(f'{G}(-90, 90)'), 180)
        self.assertEqual(self.ev(f'{G}(720, 45)'), 45)

    def squares(self, cx, cy, r):
        out = self.ev(f'''(function()
            local out = {{}}
            for x, y in LivingKnox.Geo.squaresAround({cx}, {cy}, {r}) do out[#out + 1] = x .. "," .. y end
            return table.concat(out, " ")
        end)()''')
        return out.split(' ') if out else []

    def test_squares_around_full_square_in_loop_order(self):
        # Same order as « for dy = -r, r do for dx = -r, r do » : rows of y, then x.
        self.assertEqual(self.squares(10, 20, 1),
                         ['9,19', '10,19', '11,19', '9,20', '10,20', '11,20', '9,21', '10,21', '11,21'])
        self.assertEqual(len(self.squares(0, 0, 3)), 49)

    def test_squares_around_degenerate_radius(self):
        self.assertEqual(self.squares(5, 6, 0), ['5,6'])
        self.assertEqual(self.squares(5, 6, -1), [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
