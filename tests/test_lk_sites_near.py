"""Foyer tiré dans un anneau autour d'un centre (E10-T05) : option `near` de `LivingKnox.Sites.pick`.

    python tests/test_lk_sites_near.py

Même banc que tests/test_lk_sites.py (vrai Lua du mod dans lupa, doublures fidèles de la métagrille 42.21 reprises de
tests/test_rescue.py), avec une carte d'essai dont les maisons sont posées à des distances connues de l'ancien foyer
(8004, 8004) : anneau 400-1200 cases, paliers élargis x 2 (2400) et x 4 (4800), puis carte entière. Type `loners`
(fichier de données livré). Toute lecture de case et tout parcours lent de la métagrille restent à zéro ; l'anneau
n'utilise pas getBuildings() (liste de toute la carte). Ne prouve pas l'API Java réelle : suite en jeu lk.leave.
"""
from __future__ import annotations

import math
import unittest

from test_lk_sites import SitesHarness, lua_list

# Carte d'essai : maison du centre (ancien foyer), voisine trop proche, deux maisons dans l'anneau, une à chaque palier
# élargi, une très loin (carte entière seulement). Joueur loin de tout.
RING_WORLD = r"""
PLAYER = Player(100, 100)
function House(x, y)
    return Building({ Room("bedroom", x, y, 4, 4), Room("kitchen", x + 4, y, 4, 4), Room("livingroom", x, y + 4, 8, 4) })
end
OLD = House(8000, 8000)        -- contient le centre (8004, 8004)
CLOSE = House(8100, 8000)      -- ~100 cases : sous le minimum
RING_A = House(8600, 8000)     -- ~600
RING_B = House(7000, 8500)     -- ~1120
TIER2 = House(9800, 8000)      -- ~1800 : palier x 2
TIER3 = House(8000, 11500)     -- ~3500 : palier x 4
FAR = House(14000, 2000)       -- ~8500 : carte entière seulement
finalize()
"""

CENTER = (8004, 8004)
NEAR = '{ x = 8004, y = 8004, min = 400, max = 1200 }'


class NearHarness(SitesHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute(RING_WORLD)
        for name in ('LivingKnox/LK_Core', 'LivingKnox/LK_Config', 'LivingKnox/LK_Log', 'LivingKnox/LK_GroupTypes',
                     'LivingKnox/Data/LK_Type_settlers', 'LivingKnox/Data/LK_Type_raiders',
                     'LivingKnox/Data/LK_Type_loners'):
            self.rt.execute(f'require "{name}"')
        self.rt.execute('require "LivingKnox/LK_Groups"; LivingKnox.Groups.init(true)')
        self.rt.execute('require "LivingKnox/LK_Sites"')
        self.reset_counts()

    def key(self, name):
        return 'b' + self.ev(f'return {name}:getIDString()')

    def explore(self, *names):
        for name in names:
            self.rt.execute(f'{name}.rooms.items[1].explored = true')

    def near_pick(self, seed, near=NEAR, extra=''):
        return self.pick('loners', f'{{ seed = {seed}, near = {near}{extra} }}')

    def logs(self):
        return lua_list(self.g.LOGS)

    def assert_distance(self, site, lo, hi):
        d = math.hypot(site.x - CENTER[0], site.y - CENTER[1])
        self.assertEqual(site.nearDistance, math.floor(d))
        self.assertGreaterEqual(d, lo)
        self.assertLessEqual(d, hi)


class RingTests(NearHarness):

    def test_home_in_the_ring_and_varied_by_seed(self):
        ring = {self.key('RING_A'), self.key('RING_B')}
        seen = set()
        for seed in range(1, 21):
            with self.subTest(seed=seed):
                site, why = self.near_pick(seed)
                self.assertIsNotNone(site, why)
                self.assertIn(site.key, ring)
                self.assertEqual((site.kind, site.groupType, site.nearTier, site.nearMin, site.nearMax),
                                 ('building', 'loners', 1, 400, 1200))
                self.assertIsNone(site.nearFallback)
                self.assert_distance(site, 400, 1200)
                seen.add(site.key)
        self.assertEqual(seen, ring, 'the seed never changes the home')

    def test_seed_is_reproducible(self):
        for seed in (3, 'leave/npc-12'):
            s = repr(seed) if isinstance(seed, int) else f'"{seed}"'
            a, _ = self.near_pick(s)
            b, _ = self.near_pick(s)
            self.assertEqual((a.key, a.x, a.y, a.nearDistance), (b.key, b.x, b.y, b.nearDistance))

    def test_widening_tiers_then_whole_map(self):
        # Ring empty (both houses explored): x 2 (2400), then x 4 (4800), then the whole map; each tier logged.
        self.explore('RING_A', 'RING_B')
        site, why = self.near_pick(1)
        self.assertIsNotNone(site, why)
        self.assertEqual((site.key, site.nearTier, site.nearMax), (self.key('TIER2'), 2, 2400))
        self.assert_distance(site, 1200, 2400)
        self.assertTrue(any('WARN sites: no building for loners in ring 1 (400-1200 squares from 8004,8004)' in line
                            and 'explored by a player 2' in line and line.endswith('; widening')
                            for line in self.logs()), self.logs()[-3:])
        self.assertTrue(any('INFO sites: ' + site.key + ' for loners in widened ring 2 (400-2400 squares)' in line
                            for line in self.logs()))
        self.explore('TIER2')
        site, why = self.near_pick(1)
        self.assertEqual((site.key, site.nearTier, site.nearMax), (self.key('TIER3'), 3, 4800))
        self.assert_distance(site, 2400, 4800)
        self.explore('TIER3')
        self.g.LOGS = self.rt.table()
        site, why = self.near_pick(1)
        self.assertIsNotNone(site, why)
        self.assertEqual((site.key, site.nearTier, site.nearMax), (self.key('FAR'), 0, None))
        self.assertGreaterEqual(site.nearDistance, 400)
        self.assertTrue(site.nearFallback.startswith('ring 1 (400-1200 squares from 8004,8004)'), site.nearFallback)
        self.assertIn('ring 3 (400-4800', site.nearFallback)
        warns = [line for line in self.logs() if 'WARN sites: no building for loners in ring' in line]
        self.assertEqual(len(warns), 3)
        self.assertTrue(warns[-1].endswith('; whole map next'))
        self.assertTrue(any('whole map: ' + site.key in line for line in self.logs()))

    def test_whole_map_keeps_the_minimum_and_failure_reason(self):
        self.explore('RING_A', 'RING_B', 'TIER2', 'TIER3', 'FAR')
        site, why = self.near_pick(1)
        # CLOSE (about 100 squares) is never taken, even on the whole map; OLD neither.
        self.assertIsNone(site)
        self.assertIn('; whole map: no suitable building after 300 draw(s): ', why)
        self.assertIn('too close to the center', why)
        self.assertIn('center building', why)

    def test_old_building_and_other_homes_excluded(self):
        # min 0: the building that holds the center is still refused.
        old = self.key('OLD')
        for seed in range(1, 16):
            site, _ = self.near_pick(seed, '{ x = 8004, y = 8004, min = 0, max = 1200 }')
            self.assertNotEqual(site.key, old)
        ctx = 'LivingKnox.Sites.context("loners", { near = LivingKnox.Sites.normalizeNear(' + NEAR + ') }, GRID)'
        self.assertEqual(self.ev(f'local s, r = LivingKnox.Sites.checkBuilding(OLD, {ctx}, false) return s, r'),
                         (None, 'center building'))
        self.assertEqual(self.ev(f'local s, r = LivingKnox.Sites.checkBuilding(CLOSE, {ctx}, false) return s, r'),
                         (None, 'too close to the center'))
        self.assertEqual(self.ev(f'local s, r = LivingKnox.Sites.checkBuilding(TIER2, {ctx}, false) return s, r'),
                         (None, 'beyond the ring'))
        # Another group's home next to RING_A: GROUP_DISTANCE (400) still applies inside the ring.
        gid = self.ev('local g = LivingKnox.Groups.create({ type = "settlers", name = "Next door",'
                      ' home = { x = 8604, y = 8004, z = 0 } }) return g.id')
        self.assertIsNotNone(gid)
        for seed in range(1, 16):
            with self.subTest(seed=seed):
                site, why = self.near_pick(seed)
                self.assertEqual(site.key, self.key('RING_B'), why)
                self.assertGreaterEqual(site.groupDistance, 400)
        # exclude (keys already taken) also applies.
        site, _ = self.near_pick(1, extra=f', exclude = {{ ["{self.key("RING_B")}"] = true }}')
        self.assertEqual((site.key, site.nearTier), (self.key('TIER2'), 2))

    def test_attempts_bounded_per_tier(self):
        self.explore('RING_A', 'RING_B')
        site, why = self.near_pick(1, extra=', maxAttempts = 1')
        # One examination per tier at most: ring 1 sees one of its two houses, then x 2 the other or TIER2.
        warns = [line for line in self.logs() if 'in ring 1 ' in line]
        self.assertIn('1 examined', warns[-1])
        self.assertIsNotNone(site, why)

    def test_bad_options(self):
        for near in ('{ x = 1, y = 2, min = 10 }', '{ x = 1, y = 2, min = 10, max = 10 }',
                     '{ x = "a", y = 2, min = 0, max = 10 }', '{ x = 1, y = 2, min = -1, max = 10 }', '5'):
            with self.subTest(near=near):
                self.assertEqual(self.near_pick(1, near), (None, 'bad near option'))
        self.assertEqual(self.near_pick(1, '{ x = 1, y = 2, min = 0, max = 10, widen = { 2, 2 } }'),
                         (None, 'bad near option (widen)'))
        self.assertEqual(self.pick('raiders', '{ seed = 1, near = ' + NEAR + ' }'),
                         (None, 'near option needs a building home'))
        # Custom widening tiers.
        self.explore('RING_A', 'RING_B', 'TIER2')
        site, _ = self.near_pick(1, '{ x = 8004, y = 8004, min = 400, max = 1200, widen = { 3 } }')
        self.assertEqual((site.key, site.nearTier, site.nearMax), (self.key('TIER3'), 2, 3600))

    def test_no_square_read_no_slow_scan_no_full_list(self):
        site, why = self.near_pick(1)
        self.assertIsNotNone(site, why)
        self.assertEqual(self.counts(), {'get': 0, 'cell': 0, 'square': 0, 'slow': 0, 'zones': 0})

    def test_without_near_unchanged(self):
        # No near option: plain data, no ring field, the usual draw over the whole list.
        site, why = self.pick('loners', '{ seed = 1 }')
        self.assertIsNotNone(site, why)
        self.assertIsNone(site.nearTier)
        self.assertIsNone(site.nearDistance)
        self.assertGreater(self.g.COUNT.get, 0)
        self.assertIsNone(self.ev('return LivingKnox.Sites.context("loners", {}, GRID).near'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
