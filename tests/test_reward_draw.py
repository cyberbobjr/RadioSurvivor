"""Rewards drawn at random by category (E20-T04, ADR D05): weighted draw among the realizable kinds of the [rewards]
pool, cache contents drawn in the category (shared catalogue or section of the sheet), kinds as a registry.

    python RadioSurvivor/tests/test_reward_draw.py

Real RS_Rewards, real kinds (server/RadioSurvivor/Rewards/), real RS_Persona and CA_Caches (runtime of
test_mission_rewards.py); seeded generator injected in place of ZombRand.
"""
from __future__ import annotations

import unittest
from collections import Counter

from test_mission_rewards import runtime

DRAWS = 1000
TOLERANCE = 0.05  # about 3 standard deviations of a share near one half over 1 000 draws


class RewardDrawTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.r = runtime()
        self.g = self.lua.globals()
        self.r.setRandom(self.lua.eval('seeded(12345)'))

    def draw_kinds(self, n=DRAWS):
        """Kinds chosen by n draws for a fresh mission (no effect: choose only)."""
        counts = Counter()
        for _ in range(n):
            entry, _ = self.r.choose(self.g.store.data, self.g.source, self.g.m, 'p', self.g.player)
            counts[entry.kind if entry else None] += 1
        return counts

    def test_distribution_follows_the_weights(self):
        self.lua.execute("source.rewards={{kind='cache',param='medical',weight=3},{kind='frequency',weight=1},"
                         "{kind='lesson',param='Doctor',weight=2}}")
        counts = self.draw_kinds()
        for kind, weight in (('cache', 3), ('frequency', 1), ('lesson', 2)):
            with self.subTest(kind):
                self.assertAlmostEqual(counts[kind] / DRAWS, weight / 6, delta=TOLERANCE, msg=dict(counts))

    def test_unrealizable_kind_is_never_drawn(self):
        # No active voice to share (frequency), the only stash already visited (stashmap): heavy but never drawn.
        self.lua.execute("voices.cody.state='silent';visited=true;source.rewards={{kind='frequency',weight=50},"
                         "{kind='stashmap',weight=50},{kind='lesson',param='Doctor',weight=1}}")
        self.assertEqual(self.draw_kinds(), Counter({'lesson': DRAWS}))

    def test_nothing_realizable_gives_no_reward(self):
        self.lua.execute("voices.cody.state='silent';source.rewards={{kind='frequency',weight=1}}")
        rec, why = self.r.grant(self.g.store, self.g.source, self.g.m, self.g.player, 'p', 77000)
        self.assertIsNone(rec)
        self.assertEqual(why, 'unavailable')

    def caches(self, n=300):
        """n successful missions rewarded by the pool of the source: (category, contents) of each cache."""
        out = []
        for i in range(n):
            self.lua.execute(f"m={{id='c{i}',state='success',participants={{p=true}}}}")
            rec = self.r.grant(self.g.store, self.g.source, self.g.m, self.g.player, 'p', 77000)
            self.assertEqual(rec.kind, 'cache')
            self.assertEqual(self.g.m.cache.table, rec.category)
            out.append((rec.category, [(line[1], line[2]) for line in self.g.m.cache['items'].values()]))
        return out

    def assert_contents(self, drawn, categories):
        """Every cache holds items of its drawn category only, each quantity within its range; every bound reached."""
        reached = set()
        for category, contents in drawn:
            items = {item.type: (item.min, item.max) for item in categories[category]['items'].values()}
            for item_type, count in contents:
                self.assertIn(item_type, items, f'{item_type} is not in category {category}')
                low, high = items[item_type]
                self.assertTrue(low <= count <= high, f'{item_type} x{count} outside {low}-{high}')
                reached.add((item_type, count))
        for category in {c for c, _ in drawn}:
            for item in categories[category]['items'].values():
                self.assertIn((item.type, item.min), reached)
                self.assertIn((item.type, item.max), reached)

    def test_cache_contents_drawn_from_the_catalogue_category(self):
        self.lua.execute("source.rewards={{kind='cache',param='medical',weight=1},{kind='cache',param='food',weight=1}}")
        drawn = self.caches()
        self.assertEqual({c for c, _ in drawn}, {'medical', 'food'})
        self.assert_contents(drawn, self.g.catalogue)

    def test_sheet_category_used_by_a_cache(self):
        # Real sheet reader with the rules of the server: the [category] section of the sheet, cited by its pool.
        sheet = self.lua.execute('''
        local text = {'format=1', 'id=case', 'name=Case', 'frequencies=145.0',
            '[place church]', 'at=1,2,0', 'label=Behind the church', 'use=drop',
            '[category snacks]', 'item=Base.Crisps:1-3', 'item=Base.Pop:2',
            '[rewards]', 'pool=cache:snacks:1', '[prompt]', 'You are a test voice.'}
        local Rewards = require('RadioSurvivor/RS_Rewards')
        local rules = {template = function() return nil end, rewards = Rewards.KINDS, skills = Rewards.SKILLS,
            categories = catalogue}
        return require('RadioSurvivor/RS_Persona').parseLines(text, 'case', rules)
        ''')
        self.assertFalse(isinstance(sheet, tuple), sheet)
        self.g.source = sheet
        drawn = self.caches(100)
        self.assertEqual({c for c, _ in drawn}, {'snacks'})
        self.assert_contents(drawn, sheet.categories)

    def test_cache_contents_kept_and_placed_from_the_record(self):
        # The bag of a voice reward is filled from the contents drawn at the reservation, not from a fixed table.
        self.lua.execute("source.rewards={{kind='cache',param='food',weight=1}}")
        self.r.grant(self.g.store, self.g.source, self.g.m, self.g.player, 'p', 77000)
        made = self.lua.execute('''
        local function item(fullType) return {fullType = fullType} end
        instanceItem = function(fullType)
            if fullType ~= 'Base.Bag' then return item(fullType) end
            local inside = {list = {}}
            inside.AddItem = function(self, it) self.list[#self.list + 1] = it.fullType; return it end
            local md = {}
            return {getModData = function() return md end, getItemContainer = function() return inside end,
                inside = inside}
        end
        local bag = require('CoreAI/CA_Caches').make(m.cache)
        return table.concat(bag.inside.list, ',')
        ''')
        self.assertEqual(made, 'Base.TinnedBeans,Base.TinnedBeans')

    def test_fake_reward_kind_registered_by_the_test(self):
        # A new kind is one register call: the parser accepts it in a pool and the engine draws and grants it.
        self.lua.execute('''
        gifts = 0
        local function available(ctx) return ctx.cid == 'p' and {what = 'Base.Apple'} or nil end
        local function reserve(ctx, rec, detail) rec.what = detail.what; return true end
        local function apply(ctx, rec) gifts = gifts + 1; return true end
        local function describe(rec) return 'A gift of ' .. rec.what .. ' has been left.' end
        require('RadioSurvivor/RS_Rewards').register('gift',
            {available = available, reserve = reserve, apply = apply, describe = describe})
        ''')
        sheet = self.lua.execute('''
        local text = {'format=1', 'id=case', 'name=Case', 'frequencies=145.0', '[rewards]', 'pool=gift:2, frequency:1',
            '[prompt]', 'You are a test voice.'}
        local Rewards = require('RadioSurvivor/RS_Rewards')
        local rules = {template = function() return nil end, rewards = Rewards.KINDS, skills = Rewards.SKILLS,
            categories = catalogue}
        return require('RadioSurvivor/RS_Persona').parseLines(text, 'case', rules)
        ''')
        self.assertFalse(isinstance(sheet, tuple), sheet)
        self.lua.execute("voices.cody.state='silent'")  # frequency unrealizable: the gift is the only draw
        rec = self.r.grant(self.g.store, sheet, self.g.m, self.g.player, 'p', 77000)
        self.assertEqual((rec.kind, rec.status, rec.what), ('gift', 'applied', 'Base.Apple'))
        self.assertEqual(self.g.gifts, 1)
        self.assertEqual(self.r.context(rec), 'A gift of Base.Apple has been left.')


if __name__ == '__main__':
    unittest.main()
