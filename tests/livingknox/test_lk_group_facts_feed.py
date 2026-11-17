"""Living Knox feeds the neutral group facts of the core mod (E21-T06 slice 14): LK_GroupFactsFeed.lua listens to
the public events of LK_API (OnLivingKnoxMemberDied, GroupGone, GroupCreated) and emits CA_GroupFacts member_died,
group_gone and group_created with the readable name of the group.

    python tests/livingknox/test_lk_group_facts_feed.py

Bench of tests/livingknox/test_lk_api.py (tests/commun/harness.py, dedicated server and two clients): the doubles of the engine do NOT
prove the real API, only the logic of the mods.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from test_lk_api import Base  # noqa: E402

RECORDER = r'''
GF = {}
local Facts = require 'CoreAI/CA_GroupFacts'
for _, kind in ipairs({ 'member_died', 'group_gone', 'group_created' }) do
    Facts.on(kind, function(f) GF[#GF + 1] = { kind = kind, f = f } end)
end
'''


class FeedTests(Base):
    def setUp(self):
        super().setUp()
        self.run_lua("require 'LivingKnox/LK_GroupFactsFeed'")
        self.run_lua(RECORDER)

    def flush(self):
        self.h.fire(self.srv, 'OnTickEvenPaused', 0.0)

    def facts(self, kind=None):
        return [r.f for r in self.ev('GF').values() if kind is None or r.kind == kind]

    def test_created_and_death_with_the_readable_name(self):
        self.flush()
        self.assertEqual([r.kind for r in self.ev('GF').values()],
                         ['group_created', 'group_created', 'member_died'])
        a, b = self.facts('group_created')
        self.assertEqual((a.id, a.group, a.typeKey, a.area.x, a.area.y),
                         (self.a, 'Mill Folk', self.ev('LivingKnox.API.getGroup("%s").typeNameKey' % self.a),
                          10650, 9450))
        self.assertIsNotNone(a.typeKey)
        self.assertEqual((b.id, b.group, b.area), (self.b, 'Crows', None))
        d = self.facts('member_died')[0]
        self.assertEqual((d.id, d.member, d.group, d.role, d.offscreen, d.byPlayer, d.cause),
                         (self.a, 'm-3', 'Mill Folk', 'medic', True, False, None))
        self.assertEqual(self.h.errors(self.srv), [])

    def test_group_gone_with_the_readable_name(self):
        self.flush()
        self.run_lua(f'''
            local G = LivingKnox.Groups
            assert(G.markDead("{self.a}", "m-1")); assert(G.markDead("{self.a}", "m-2"))
        ''')
        self.flush()
        gone = self.facts('group_gone')
        self.assertEqual([(f.id, f.group, f.reason) for f in gone], [(self.a, 'Mill Folk', 'dead')])
        self.assertEqual(len(self.facts('member_died')), 3)

    def test_reload_keeps_one_subscription(self):
        self.run_lua("package.loaded['LivingKnox/LK_GroupFactsFeed'] = nil; require 'LivingKnox/LK_GroupFactsFeed'")
        self.flush()
        self.assertEqual(len(self.facts('group_created')), 2)


if __name__ == '__main__':
    unittest.main()
