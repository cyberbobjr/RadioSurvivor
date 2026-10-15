"""Banc (lupa) de RST_Places.lua (mod de développement) : retour du joueur après un déplacement vers un décor.

Campagne solo du 2026-10-15 (commit 54087fb, runs/20261015-114001-parallel-2-54087fb0f84f) : après lk.traversal, le
joueur était remis à sa place par le nettoyage du test, mais la suite suivante démarrait aussitôt, zone pas encore
rechargée : « npc spawn refused: square 11316,6942,0 is not loaded » (11 tests). Pl.areaBack fait attendre le
nettoyage jusqu'au chargement des cases autour de la place de départ (au plus Pl.BACK_LOAD_MS, puis une note).

Lancer : python RadioSurvivor/tests/test_lk_places.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from test_lk_bodies import DEV_LUA, lua_list  # noqa: E402

SUITE = r'''
require "RST/RST"
require "RST/RST_Places"
ORX, ORY = 100, 100
UNLOADED = false
NEXT_SEEN = nil
local cell = getCell()
local orig = cell.getGridSquare
cell.getGridSquare = function(self, x, y, z)
    if UNLOADED and math.abs(x - ORX) <= 30 and math.abs(y - ORY) <= 30 then return nil end
    return orig(self, x, y, z)
end
RST.suite("t.places", {}, function(s)
    s.test("moved away and back", function(t)
        local p = getPlayer()
        local origin = { x = ORX + 0.5, y = ORY + 0.5, z = 0 }
        t:defer(function(tt)
            HARNESS.place(p, origin.x, origin.y, 0)   -- way back (placeLocal in the game)
            return RST.Places.areaBack(tt, p, origin)
        end, "player back")
        HARNESS.place(p, 400.5, 400.5, 0)
        UNLOADED = true          -- the start place is out of the loaded area while the player is away
        t:ok(true)
    end)
    s.test("next test spawns next to the start place", function(t)
        NEXT_SEEN = getTimestampMs()
        t:ok(getCell():getGridSquare(ORX + 2, ORY, 0) ~= nil, "square next to the start place not loaded")
    end)
end)
'''


class PlacesBackTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='solo', lua_roots=[DEV_LUA])
        self.h.load('solo', SUITE)

    def tearDown(self):
        self.h.close()

    def run_suites(self, load_after_ticks):
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "t.places" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(3000):
            if i == load_after_ticks:
                self.h.load('solo', 'UNLOADED = false')
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        return [(r.test, r.status, r.message) for r in lua_list(report.results)]

    def test_next_test_waits_until_the_start_place_is_loaded_again(self):
        res = self.run_suites(load_after_ticks=120)     # zone rechargée environ 2 s après le retour
        self.assertEqual([r[1] for r in res], ['PASS', 'PASS'], res)
        self.assertTrue(any('loaded again after' in line for line in self.h.logs('solo')), self.h.logs('solo'))

    def test_never_loaded_ends_with_a_note_not_a_hang(self):
        res = self.run_suites(load_after_ticks=10 ** 6)  # jamais rechargée : la suivante échoue, sans blocage
        self.assertEqual(res[0][1], 'PASS', res)
        self.assertEqual(res[1][1], 'FAIL', res)


if __name__ == '__main__':
    unittest.main()
