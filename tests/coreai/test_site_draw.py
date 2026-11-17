"""Tirage commun d'un bâtiment (E25-T02, ADR lieux communs D01, D03) : CA_Sites.draw dans lupa.

    python RadioSurvivor/tests/coreai/test_site_draw.py

Vrai Lua du mod commun (Lua 5.1, `next` retiré comme dans Kahlua), doublures fidèles de la métagrille 42.22 partagées
(tests/commun/metagrid_doubles.py : IsoMetaCell.getBuildingsIntersecting par cellule, lectures de cellules comptées). Couvre :
bande de distance autour d'un point (Près, Plus loin, Très loin), zone (point du bâtiment dans le rectangle), genre de
bâtiment, bases connues évitées, rien trouvé, graine reproductible, règle supplémentaire de l'appelant (accept), et le
coût borné de « Très loin » (cellules lues). Ne prouve pas l'API Java réelle ni le temps de calcul en jeu.
"""
from __future__ import annotations

import unittest
from pathlib import Path

import lupa.lua51 as lupa

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from metagrid_doubles import DOUBLES

ROOT = Path(__file__).resolve().parents[2]
CORE_LUA = ROOT / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'

# Caller at (2000, 2000). Gaps between a footprint and the caller's tile (2000..2001).
WORLD = r"""
CALLER = Player(2000, 2000)
function House(x, y)
    return Building({ Room("bedroom", x, y, 4, 4), Room("kitchen", x + 4, y, 4, 4), Room("livingroom", x, y + 4, 8, 4) })
end
TOO_CLOSE = House(2030, 2000)                                   -- gap 29: a known base (the caller) and below 100
NEAR = House(2150, 2000)                                        -- gap 149: near (100-200)
CHURCH = Building({ Room("church", 2000, 2150, 12, 12) })        -- gap 149, a church
FAR = House(2350, 2000)                                         -- gap 349: far (200-500)
VERY_FAR = House(3000, 2000)                                    -- gap 999: very far (500-1500)
BEYOND = House(3600, 2000)                                      -- gap 1599: out of every band
IN_ZONE = House(5040, 5040)                                     -- inside the zone 5000..5100
OUT_ZONE = House(5200, 5040)                                    -- right of the zone
EDGE = House(4995, 5040)                                        -- footprint crosses the zone, site point outside
finalize()
ZONE = { x1 = 5000, y1 = 5000, x2 = 5100, y2 = 5100 }
Sites = require("CoreAI/CA_Sites")
function around(min, max, extra)
    local opts = { around = { x = CALLER:getX(), y = CALLER:getY(), min = min, max = max }, minDistance = 60 }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return opts
end
"""

BANDS = {'near': (100, 200), 'far': (200, 500), 'very_far': (500, 1500)}


class DrawHarness(unittest.TestCase):

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None  # absent from Kahlua
        self.rt.execute(DOUBLES)
        paths = [CORE_LUA / 'shared', CORE_LUA / 'server']
        self.rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')

    def world(self, extra: str = ''):
        self.rt.execute(WORLD + extra)

    def draw(self, opts: str):
        """(site key, reason) of Sites.draw(opts)."""
        return self.rt.execute(f'local s, r = Sites.draw({opts}) return s and s.key, r')

    def keys_of(self, opts_for_seed: str, seeds=range(30)):
        """Keys drawn over several seeds; SEED in the options is replaced by each seed."""
        return {self.draw(opts_for_seed.replace('SEED', str(s)))[0] for s in seeds}

    def key(self, name: str) -> str:
        return 'b' + str(self.g[name].id)


class BandTests(DrawHarness):

    def setUp(self):
        super().setUp()
        self.world()

    def test_each_band_draws_only_a_building_at_that_distance(self):
        expected = {'near': {self.key('NEAR'), self.key('CHURCH')}, 'far': {self.key('FAR')},
                    'very_far': {self.key('VERY_FAR')}}
        for band, (lo, hi) in BANDS.items():
            with self.subTest(band=band):
                keys = self.keys_of(f'around({lo}, {hi}, {{ seed = SEED }})')
                self.assertEqual(keys, expected[band])

    def test_both_near_buildings_come_out_over_seeds(self):
        """A fresh seed per offer gives another building when several fit (two offers, two places)."""
        self.assertEqual(len(self.keys_of('around(100, 200, { seed = "offer:SEED" })')), 2)

    def test_kind_filter_keeps_only_that_kind(self):
        keys = self.keys_of('around(100, 200, { kind = "church", seed = SEED })')
        self.assertEqual(keys, {self.key('CHURCH')})
        site = self.rt.execute('return Sites.draw(around(100, 200, { kind = "church", seed = 1 }))')
        self.assertEqual((site.kind, site.label), ('church', 'church'))

    def test_same_seed_same_building(self):
        first = [self.draw(f'around(100, 200, {{ seed = "s{i}" }})')[0] for i in range(10)]
        again = [self.draw(f'around(100, 200, {{ seed = "s{i}" }})')[0] for i in range(10)]
        self.assertEqual(first, again)

    def test_known_bases_are_avoided(self):
        """A safehouse or another connected player near the building rules it out (same rule as the scout draw)."""
        self.rt.execute('SAFEHOUSES[1] = { x = 2140, y = 1990, w = 30, h = 30 }')
        self.assertEqual(self.keys_of('around(100, 200, { seed = SEED })'), {self.key('CHURCH')})
        self.rt.execute('Player(2005, 2170)')
        key, reason = self.draw('around(100, 200, { seed = 3 })')
        self.assertIsNone(key)
        self.assertIn('near a known base', reason)

    def test_nothing_found_gives_a_reason(self):
        key, reason = self.draw('around(100, 200, { kind = "hospital", seed = 4 })')
        self.assertIsNone(key)
        self.assertIn('no suitable building', reason)
        self.assertIn('other kind', reason)

    def test_accept_rule_of_the_caller_tries_the_next_building(self):
        """clear keeps its density rule: a building refused by accept is skipped, the next one is examined."""
        church = self.key('CHURCH')
        self.rt.execute(f'REFUSE = "{church}"')
        accept = 'accept = function(site) if site.key == REFUSE then return false, "too few zombies" end return true end'
        self.assertEqual(self.keys_of(f'around(100, 200, {{ seed = SEED, {accept} }})'), {self.key('NEAR')})
        self.rt.execute(f'REFUSE = "{self.key("NEAR")}"')
        key, reason = self.draw(f'around(100, 200, {{ kind = "house", seed = 2, {accept} }})')
        self.assertIsNone(key)
        self.assertIn('too few zombies', reason)

    def test_no_square_is_read_and_no_slow_call(self):
        self.draw('around(500, 1500, { seed = 5 })')
        self.draw('{ area = ZONE, seed = 5 }')
        self.assertEqual((self.g.COUNT.square, self.g.COUNT.cell, self.g.COUNT.slow), (0, 0, 0))

    def test_site_holds_plain_values_only(self):
        site = self.rt.execute('return Sites.draw(around(100, 200, { seed = 9 }))')
        for k, v in site.items():
            self.assertIn(self.rt.eval('type')(v), ('string', 'number', 'table', 'boolean'), k)
        self.assertGreaterEqual(site.cells, 1)
        self.assertGreaterEqual(site.attempts, 1)


class ZoneTests(DrawHarness):

    def setUp(self):
        super().setUp()
        self.world()

    def test_zone_draws_a_building_whose_point_lies_inside(self):
        self.assertEqual(self.keys_of('{ area = ZONE, seed = SEED }'), {self.key('IN_ZONE')})

    def test_zone_with_a_kind_absent_finds_nothing(self):
        key, reason = self.draw('{ area = ZONE, kind = "church", seed = 1 }')
        self.assertIsNone(key)
        self.assertIn('other kind', reason)

    def test_zone_keeps_the_known_base_rule(self):
        self.rt.execute('SAFEHOUSES[1] = { x = 5030, y = 5030, w = 30, h = 30 }')
        key, reason = self.draw('{ area = ZONE, seed = 1, minDistance = 60 }')
        self.assertIsNone(key)
        self.assertIn('near a known base', reason)


class VeryFarCostTests(DrawHarness):
    """Cost of very_far: the ring 500-1500 crosses about a hundred metagrid cells; a draw reads at most maxCells of
    them (drawn at random), one at a time, and stops at the first building that fits."""

    def test_cells_read_are_bounded_even_when_nothing_fits(self):
        # One house in every cell of the map, none of them a hospital: the draw examines cells until its bound.
        self.world('for cy = 0, 20 do for cx = 0, 20 do House(cx * 256 + 100, cy * 256 + 100) end end finalize()')
        for max_cells in (9, 4):
            with self.subTest(max_cells=max_cells):
                self.g.COUNT.cellReads = 0
                key, reason = self.draw(f'around(500, 1500, {{ kind = "hospital", seed = 1, maxCells = {max_cells} }})')
                self.assertIsNone(key)
                self.assertEqual(self.g.COUNT.cellReads, max_cells)
                self.assertIn(f'{max_cells} cell(s)', reason)

    def test_a_populated_ring_is_drawn_after_one_cell_or_so(self):
        self.world('for cy = 0, 20 do for cx = 0, 20 do House(cx * 256 + 100, cy * 256 + 100) end end finalize()')
        reads = []
        for seed in range(20):
            self.g.COUNT.cellReads = 0
            site = self.rt.execute(f'return Sites.draw(around(500, 1500, {{ seed = {seed}, noClues = true }}))')
            self.assertIsNotNone(site)
            gap = self.rt.execute(f'return Sites.gap(Sites.draw(around(500, 1500, {{ seed = {seed}, noClues = true }})).bounds, '
                                  '{ x1 = 2000, y1 = 2000, x2 = 2001, y2 = 2001 })')
            self.assertTrue(500 <= gap <= 1500, gap)
            reads.append(self.g.COUNT.cellReads)
        self.assertLessEqual(max(reads), 2 * 9)  # two draws per seed above, each at most maxCells

    def test_candidate_cells_of_each_band(self):
        """Cells of the metagrid a band may read (ring filter), before the bound: printed for the report."""
        self.world()
        counts = {band: self.rt.execute(f'return #Sites.ringCells(2000, 2000, {lo}, {hi})')
                  for band, (lo, hi) in BANDS.items()}
        self.assertLessEqual(counts['near'], 9)
        self.assertGreater(counts['very_far'], 60)
        print('candidate cells per band:', counts)


class ScoutCompatibilityTests(DrawHarness):
    """The scout draw of an NPC (60-250 tiles, CA_MissionScout.pick) is the same draw: around the requester, min 0,
    known bases (the requester among them) at 60 tiles at least."""

    def test_scout_pick_uses_the_common_draw(self):
        self.world()
        self.rt.execute('Scout = require("CoreAI/CA_MissionScout")')
        keys = {self.rt.execute('local s = Scout.pick(2000.5, 2000.5, { minDistance = 60, maxDistance = 250, '
                                f'maxAttempts = 40 }}, {s}) return s and s.key') for s in range(30)}
        self.assertEqual(keys, {self.key('NEAR'), self.key('CHURCH')})
        site = self.rt.execute('return Scout.pick(2000.5, 2000.5, { minDistance = 60, maxDistance = 250, '
                               'maxAttempts = 40 }, 1)')
        self.assertTrue(site.clues[1].startswith('The place is '), site.clues[1])


if __name__ == '__main__':
    unittest.main()
