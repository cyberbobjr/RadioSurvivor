"""Banc (lupa) de RST.LKHelpers.whenLoaded (mod de développement) : attente des cases autour du joueur avant un PNJ.

Campagne solo du 2026-10-15 (runs/20261015-114001-parallel-2-54087fb0f84f) : lk.equipment, lk.melee, lk.ownerreports,
lk.health et lk.loot appelaient LivingKnox.Bodies.spawn à 2 ou 3 cases du joueur juste après le retour d'une suite
précédente : « npc spawn refused: square 11316,6942,0 is not loaded » (12 tests). K.whenLoaded attend les cases de
K.SPAWN_RADIUS autour du joueur (au plus K.SPAWN_LOAD_MS, puis un échec qui le dit).

Lancer : python RadioSurvivor/tests/test_lk_spawn_area.py
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_bodies import DEV_LUA, lua_list  # noqa: E402

SUITES_DIR = DEV_LUA / 'shared/RST/suites'
FIXED = ('RST_LKEquipment.lua', 'RST_LKMelee.lua', 'RST_LKOwnerReports.lua', 'RST_LKHealth.lua', 'RST_LKLoot.lua')

SUITE = r'''
require "RST/RST"
require "RST/RST_LKHelpers"
UNLOADED_UNTIL = 0
local cell = getCell()
local orig = cell.getGridSquare
cell.getGridSquare = function(self, x, y, z)
    if getTimestampMs() < UNLOADED_UNTIL and math.abs(x - 100) <= 30 and math.abs(y - 100) <= 30 then return nil end
    return orig(self, x, y, z)
end
RST.suite("t.area", {}, function(s)
    s.test("spawn after the area is loaded", function(t)
        local p = getPlayer()
        RST.LKHelpers.whenLoaded(t, p, function(t2)
            t2:ok(getCell():getGridSquare(math.floor(p:getX()) + 3, math.floor(p:getY()), 0) ~= nil, "square not loaded")
        end)
    end)
end)
'''


class WhenLoadedTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='solo', lua_roots=[DEV_LUA])
        self.h.load('solo', SUITE)
        self.h.load('solo', 'HARNESS.place(getPlayer(), 100.5, 100.5, 0)')

    def tearDown(self):
        self.h.close()

    def run_suite(self, unloaded_ms):
        self.h.load('solo', f'UNLOADED_UNTIL = getTimestampMs() + {unloaded_ms}')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "t.area" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(3000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        return [(r.status, r.message) for r in lua_list(report.results)]

    def test_waits_until_the_squares_around_the_player_are_loaded(self):
        self.assertEqual(self.run_suite(2000), [('PASS', None)])

    def test_loaded_at_once(self):
        self.assertEqual(self.run_suite(0), [('PASS', None)])

    def test_never_loaded_fails_with_the_area(self):
        res = self.run_suite(10 ** 9)
        self.assertEqual(res[0][0], 'FAIL', res)
        self.assertIn('squares within 5 of 100,100,0 not loaded', res[0][1])


class SuitesUseItTests(unittest.TestCase):
    def test_failing_suites_wait_for_the_area_before_spawning(self):
        for name in FIXED:
            text = (SUITES_DIR / name).read_text(encoding='utf-8')
            self.assertTrue(re.search(r'B\(\)\.spawn\(', text), name)
            self.assertRegex(text, r'(K|RST\.LKHelpers)\.whenLoaded\(t, \w+, ', f'{name}: spawn without K.whenLoaded')


if __name__ == '__main__':
    unittest.main()
