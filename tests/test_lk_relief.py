"""Décimation et relève des groupes (LK09-T04) : LK_Population.lua (constat, délai, relève), marque `gone` de
LK_Groups.lua, foyer abandonné jamais aménagé (LK_Homes.pending).

    python RadioSurvivor/tests/test_lk_relief.py

Banc lupa de tests/test_lk_population.py (carte de test, vrai registre, vrais types, histoires et sites ; un
« redémarrage » = nouvelle VM, mêmes fichiers). Les heures sont passées explicitement à `Population.reliefStep(now)`,
sauf pour l'accroche horaire (horloge de test). Ne prouve pas l'API Java réelle (voir la suite en jeu `lk.relief`).
"""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_population import Bench, lua_list  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
POP = 'LivingKnox.Population'
GROUPS = 'LivingKnox.Groups'


class ReliefBench(Bench):
    def setUp(self):
        super().setUp()
        ids, why = self.run_pop()
        self.assertIsNone(why)
        self.assertEqual(len(lua_list(ids)), 4)

    def step(self, now):
        r, why = self.ev(f'local r, why = {POP}.reliefStep({now}) return r, why')
        self.assertIsNone(why)
        return lua_list(r)

    def group(self, gid):
        return self.data().groups[gid]

    def living(self, gid):
        g = self.group(gid)
        return [m.id for m in self.members(g) if m is not None and m.alive]

    def kill(self, gid, keep=0):
        for mid in self.living(gid)[keep:]:
            ok, why = self.ev(f'local ok, why = {GROUPS}.markDead("{gid}", "{mid}") return ok, why')
            self.assertTrue(ok, why)

    def kinds(self, gid):
        g = self.group(gid)
        return [(g.log[i].kind, g.log[i].text) for i in range(1, len(g.log) + 1)]


class GoneTests(ReliefBench):
    def test_wiped_group_is_marked_gone_and_kept_with_its_traces(self):
        self.rt.execute(f'{GROUPS}.state.data.groups["grp-1"].furnish = {{ v = 1, state = "done", placed = {{}} }} '
                        f'{GROUPS}.state.data.groups["grp-1"].stock = {{ v = 1, items = {{}} }} {GROUPS}.save()')
        home = dict(self.group('grp-1').home.items())
        self.kill('grp-1')
        self.assertEqual(self.step(100), [])
        g = self.group('grp-1')
        self.assertEqual(g.gone.cause, 'wiped')
        self.assertEqual(g.gone.hour, 100)
        self.assertEqual(g.gone.day, 5)
        self.assertTrue(100 + 2 * 24 <= g.gone.due <= 100 + 5 * 24)
        self.assertEqual((g.gone.due - 100) % 24, 0)
        self.assertIsNone(g.gone.relief)
        self.assertEqual(dict(g.home.items()), home)            # foyer abandonné, pas effacé
        self.assertEqual(g.furnish.state, 'done')               # aménagement et stock laissés comme traces
        self.assertIsNotNone(g.stock)
        self.assertEqual(self.kinds('grp-1')[-1], ('gone', 'wiped'))
        for other in ('grp-2', 'grp-3', 'grp-4'):
            self.assertIsNone(self.group(other).gone)
        self.assertTrue(any('group grp-1 gone (wiped) at hour 100' in line for line in self.logs('INFO')))
        # Constat unique : un second pas ne change rien.
        seq = self.ev(f'{GROUPS}.state.seq')
        self.step(101)
        self.assertEqual(self.ev(f'{GROUPS}.state.seq'), seq)
        self.assertEqual(self.group('grp-1').gone.hour, 100)

    def test_group_without_members_ever_is_not_gone(self):
        self.ev(f'{GROUPS}.create({{ type = "settlers", name = "Empty" }})')
        self.step(10)
        self.assertIsNone(self.group('grp-5').gone)

    def test_all_members_left_counts_as_wiped(self):
        for mid in self.living('grp-2'):
            self.ev(f'{GROUPS}.removeMember("grp-2", "{mid}")')
        self.step(10)
        self.assertEqual(self.group('grp-2').gone.cause, 'wiped')

    def test_dispersed_lone_survivor_leaves_offscreen(self):
        self.kill('grp-1', keep=1)
        last = self.living('grp-1')[0]
        self.step(30)
        g = self.group('grp-1')
        self.assertEqual(g.gone.cause, 'dispersed')
        self.assertEqual(self.living('grp-1'), [])
        self.assertIsNone(g.members[last])                      # parti, retiré du groupe
        self.assertIn(('left', last), self.kinds('grp-1'))
        self.assertEqual(self.kinds('grp-1')[-1], ('gone', 'dispersed'))

    def test_dispersal_waits_for_an_expedition_or_a_body_and_can_be_disabled(self):
        self.kill('grp-1', keep=1)
        last = self.living('grp-1')[0]
        self.rt.execute(f'{GROUPS}.state.data.groups["grp-1"].expedition = {{ place = "houses", team = {{ "{last}" }}, '
                        'departed = 1, returns = 50 }')
        self.step(30)
        self.assertIsNone(self.group('grp-1').gone)
        self.rt.execute(f'{GROUPS}.state.data.groups["grp-1"].expedition = nil')
        self.rt.execute('LivingKnox.Simulation = { isEmbodied = function(m) return true end }')
        self.step(31)
        self.assertIsNone(self.group('grp-1').gone)
        self.rt.execute('LivingKnox.Simulation = nil')
        self.rt.execute(f'{POP}.RELIEF.DISPERSE_AT = 0')
        self.step(32)
        self.assertIsNone(self.group('grp-1').gone)
        self.assertEqual(self.living('grp-1'), [last])
        self.rt.execute(f'{POP}.RELIEF.DISPERSE_AT = 1')
        self.step(33)
        self.assertEqual(self.group('grp-1').gone.cause, 'dispersed')

    def test_gone_group_refuses_new_members_and_is_validated_at_load(self):
        self.kill('grp-1')
        self.step(10)
        r, why = self.ev(f'local r, why = {GROUPS}.addMember("grp-1", {{ role = "fighter" }}) return r, why')
        self.assertIsNone(r)
        self.assertEqual(why, 'group grp-1 is gone')
        cases = (('gone.cause = "lost"', 'bad gone cause'), ('gone.due = 1', 'bad gone hours'),
                 ('gone.relief = "grp-99"', 'bad relief group'), ('gone = 3', 'gone is not a table'),
                 ('members["m-1"].alive = true', 'gone group has a living member m-1'))
        for change, reason in cases:
            with self.subTest(change=change):
                code = (f'local d = {GROUPS}.copy({GROUPS}.state.data) d.groups["grp-1"].{change} '
                        f'local _, dropped = {GROUPS}.validate(d) return #dropped, dropped[1] and dropped[1].why')
                self.assertEqual(self.ev(code), (1, reason))
        n = self.ev(f'local _, dropped = {GROUPS}.validate({GROUPS}.copy({GROUPS}.state.data)) return #dropped')
        self.assertEqual(n, 0)

    def test_delay_follows_the_options_and_is_reproducible(self):
        self.opt('ReliefDaysMin', 3)
        self.opt('ReliefDaysMax', 3)
        self.kill('grp-1')
        self.step(200)
        self.assertEqual(self.group('grp-1').gone.due, 200 + 72)
        self.opt('ReliefDaysMin', 2)
        self.opt('ReliefDaysMax', 5)
        delays = {self.ev(f'{POP}.reliefDelay(LivingKnox.Config.population(), "grp-{n}")') for n in range(1, 41)}
        self.assertEqual(delays, {48, 72, 96, 120})
        a = self.ev(f'{POP}.reliefDelay(LivingKnox.Config.population(), "grp-7")')
        self.assertEqual(self.ev(f'{POP}.reliefDelay(LivingKnox.Config.population(), "grp-7")'), a)

    def test_disabled_engine_does_nothing(self):
        self.kill('grp-1')
        self.rt.execute('LivingKnox.Config.isEnabled = function() return false end')
        self.assertEqual(self.ev(f'local r, why = {POP}.reliefStep(10) return why'), 'disabled')
        self.assertIsNone(self.group('grp-1').gone)


class ReliefTests(ReliefBench):
    def gone_and_due(self, gid='grp-1', hour=100):
        self.kill(gid)
        self.step(hour)
        return self.group(gid).gone.due

    def test_relief_in_the_delay_far_from_the_old_site_and_only_once(self):
        old = dict(self.group('grp-1').home.items())
        due = self.gone_and_due()
        self.assertEqual(self.step(due - 1), [])
        created = self.step(due)
        self.assertEqual(created, ['grp-5'])
        new = self.group('grp-5')
        self.assertIsNotNone(new.home)
        self.assertGreaterEqual(math.hypot(new.home.x - old['x'], new.home.y - old['y']),
                                self.ev('LivingKnox.Sites.CONFIG.GROUP_DISTANCE'))
        for other in ('grp-2', 'grp-3', 'grp-4'):
            h = self.group(other).home
            self.assertGreaterEqual(math.hypot(new.home.x - h.x, new.home.y - h.y), 400)
        self.assertEqual(self.group('grp-1').gone.relief, 'grp-5')
        self.assertIn(('relieved', 'grp-5'), self.kinds('grp-1'))
        self.assertIn(('relief', 'grp-1'), self.kinds('grp-5'))
        members = [m for m in self.members(new) if m is not None]
        self.assertGreaterEqual(len(members), 4)
        self.assertIsNotNone(new.leader)
        self.assertTrue(new.members[new.leader].alive)
        self.assertEqual(new.founded, due // 24 + 1)
        self.assertTrue(any('relief: grp-5' in line and 'replaces grp-1' in line for line in self.logs('INFO')))
        # Une seule relève, même plus tard et après un redémarrage.
        self.assertEqual(self.step(due + 1), [])
        self.restart()
        self.assertEqual(self.step(due + 200), [])
        self.assertEqual(lua_list(self.g.LivingKnox.Groups.list()), ['grp-1', 'grp-2', 'grp-3', 'grp-4', 'grp-5'])
        self.assertEqual(self.group('grp-1').gone.relief, 'grp-5')

    def test_due_hour_survives_a_restart(self):
        due = self.gone_and_due()
        self.restart()
        g = self.group('grp-1')
        self.assertEqual((g.gone.cause, g.gone.due), ('wiped', due))
        self.assertEqual(self.step(due - 2), [])
        self.assertEqual(self.step(due + 3), ['grp-5'])

    def test_reproducible_relief(self):
        due = self.gone_and_due()
        self.step(due)
        first = (self.group('grp-5').type, dict(self.group('grp-5').home.items()), self.group('grp-5').name)
        self.files = {}
        self.boot(new_world=True)
        self.run_pop()
        self.assertEqual(self.gone_and_due(), due)
        self.step(due)
        self.assertEqual((self.group('grp-5').type, dict(self.group('grp-5').home.items()),
                          self.group('grp-5').name), first)

    def test_no_site_retries_a_day_later(self):
        due = self.gone_and_due()
        self.rt.execute('SAVED_GRID = GRID GRID = nil')
        self.assertEqual(self.step(due), [])
        g = self.group('grp-1')
        self.assertEqual(g.gone.due, due + 24)
        self.assertIsNone(g.gone.relief)
        self.assertTrue(any('relief: no relief for grp-1 (no site: no metagrid), next try at hour' in line
                            for line in self.logs('WARN')))
        self.rt.execute('GRID = SAVED_GRID')
        self.assertEqual(self.step(due + 23), [])
        self.assertEqual(self.step(due + 24), ['grp-5'])

    def test_two_gone_groups_get_distinct_reliefs(self):
        self.kill('grp-1')
        self.kill('grp-2')
        self.step(100)
        due = max(self.group('grp-1').gone.due, self.group('grp-2').gone.due)
        created = self.step(due)
        self.assertEqual(created, ['grp-5', 'grp-6'])
        self.assertEqual({self.group('grp-1').gone.relief, self.group('grp-2').gone.relief}, {'grp-5', 'grp-6'})
        a, b = self.group('grp-5').home, self.group('grp-6').home
        self.assertGreaterEqual(math.hypot(a.x - b.x, a.y - b.y), 400)

    def test_hourly_hook_runs_the_relief(self):
        due = self.gone_and_due()
        self.rt.execute(f'getGameTime = function() return {{ getWorldAgeHours = function() return {due} + 0.5 end }} end')
        self.rt.execute(f'{POP}.state.started = true')
        self.ev(f'{POP}.onEveryHours()')
        self.assertEqual(self.group('grp-1').gone.relief, 'grp-5')


TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKRelief.lua'


class SuiteTests(ReliefBench):
    """Suite en jeu lk.relief exécutée par le vrai moteur RST contre la carte de test."""

    def setUp(self):
        super().setUp()
        self.rt.execute(f'package.path = [[{TESTS_LUA.as_posix()}/shared/?.lua;]] .. package.path')
        self.rt.execute('getGameTime = function() return { getWorldAgeHours = function() return 300.25 end } end')
        self.rt.execute('if PLAYER.getZ == nil then PLAYER.getZ = function() return 0 end end')
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE.as_posix()}]])')

    def run_suite(self):
        self.assertTrue(self.ev('RST.start("lk.relief", { attach = false, ctx = { player = PLAYER } })'))
        for _ in range(200):
            if not self.ev('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 100
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        return report, results

    def test_suite_passes_and_cleans_up(self):
        report, results = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 2)
        self.assertEqual(lua_list(self.g.LivingKnox.Groups.list()), ['grp-1', 'grp-2', 'grp-3', 'grp-4'])

    def test_suite_detects_a_relief_near_the_old_home(self):
        # Défaut simulé : le plan garde un foyer voisin de l'ancien (contrôle de distance contourné).
        self.rt.execute('local P = LivingKnox.Population local old = P.planRelief '
                        'P.planRelief = function(o, s, i) local p, why = old(o, s, i) '
                        'if p then p.home = { x = o.home.x + 1, y = o.home.y, z = o.home.z } end return p, why end')
        _, results = self.run_suite()
        status, message = results['a wiped-out group is marked gone, then relieved once far from its home']
        self.assertEqual(status, 'FAIL')
        self.assertIn('squares from the old home', message)


class HomesTests(ReliefBench):
    def test_abandoned_home_is_never_furnished_later(self):
        src = (ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/LivingKnox/LK_Homes.lua').read_text(
            encoding='utf-8')
        self.assertIn('g.gone == nil and not Homes.validMark(g.furnish, home)', src)
        self.rt.execute('require "LivingKnox/LK_Homes"')
        before = sorted(p.gid for p in lua_list(self.ev('LivingKnox.Homes.pending()')))
        self.assertIn('grp-1', before)
        self.kill('grp-1')
        self.step(10)
        after = sorted(p.gid for p in lua_list(self.ev('LivingKnox.Homes.pending()')))
        self.assertEqual(after, [g for g in before if g != 'grp-1'])


if __name__ == '__main__':
    unittest.main(verbosity=1)
