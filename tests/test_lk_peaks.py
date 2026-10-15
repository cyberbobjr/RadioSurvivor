"""Tests hors jeu des pointes de LK13-T11 : relevé de fortification de la minute étalé (server/LivingKnox/LK_Fortify.lua,
file Fortify.minuteJobs, trois étapes par relevé, une par image, et relecture du stock qui attend le relevé de son
groupe) et lecture en place des types de groupe (shared/LivingKnox/LK_GroupTypes.lua,
GroupTypes.peek ; appelants LK_Decisions.lua, LK_Hostility.lua).

    python RadioSurvivor/tests/test_lk_peaks.py

Banc : pile de test_lk_fortify_offscreen.py (maison HOUSE, foyer 110,110, caisse garnie, ouvrier m-2) pour la file
d'un groupe ; banc de charge complet tools/load_bench.py (5 groupes, 4 joueurs) pour la file de plusieurs groupes et
le déterminisme (mêmes octets du registre des groupes, des attitudes et du registre des PNJ, mêmes lignes « fortify: »
dans le même ordre, avec le relevé fait dans l'image de la minute ou un groupe par image).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from test_lk_fortify_offscreen import DAY_HOUR, NIGHT_HOUR, OffscreenStack  # noqa: E402
from test_lk_barricade import F, ST  # noqa: E402

Q = f'{F}.minuteJobs'

# Ancien chemin (avant LK13-T11) : relevés de la minute faits dans l'image de la minute (file vidée aussitôt).
INLINE = r'''
local F = LivingKnox.Fortify
local scan = F.scan
F.scan = function(reason)
    local n = scan(reason)
    if reason == "minute" then F.finishQueue() end
    return n
end
'''

STATE = ('(function() local C = require "RadioSurvivor/RS_Codec" local LK = LivingKnox '
         'local H = LK.Hostility.state.data local S = LK.Store.data() '
         'return C.hexBytes(C.encodeBytes(LK.Groups.state.data)) .. "|" .. C.hexBytes(C.encodeBytes(H)) .. "|" .. '
         'C.hexBytes(C.encodeBytes(S)) end)()')
FINISH = ('local S, St, F = LivingKnox.Simulation, LivingKnox.Stock, LivingKnox.Fortify '
          'S.finishHour() St.finishQueue() F.finishQueue() LivingKnox.Groups.flush()')


class Base(OffscreenStack):
    mode = 'solo'

    def group(self, builder=False):
        gid = self.mk(builder=builder)
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        if builder:
            self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].members["m-2"].duty = '
                         '"builder" return true, true end))')
        self.h.tick(2)                                             # écritures du registre faites
        return gid

    def surveys(self):
        return self.ev(f'{F}.stats.surveys')

    def queued(self, gid):
        return self.ev(f'{Q}.queued["{gid}"] ~= nil')

    def minute(self, expire=True):
        if expire:                                                 # plan relevé par la mise en place : expiré
            self.h.advance_ms(self.ev(f'{F}.CFG.PLAN_MS'))
        t = self.ev('getTimestampMs()')
        self.ev(f'{F}.scan("minute")')
        return t


class MinuteQueueTests(Base):
    def test_survey_leaves_the_minute_frame_and_keeps_the_minute_clock(self):
        gid = self.group()
        s0 = self.surveys()
        t = self.minute()
        self.assertEqual(self.surveys(), s0)                       # rien dans l'image de la minute
        self.assertTrue(self.queued(gid))
        self.h.tick(1)                                             # étape 1 : relevé du monde
        self.assertEqual(self.surveys(), s0 + 1)
        self.assertTrue(self.queued(gid))
        self.assertIsNone(self.ev(f'{F}.clockAt'))
        self.h.tick(1)                                             # étape 2 : plan gardé avec l'heure de la minute
        self.assertEqual(self.ev(f'{F}.state.plans["{gid}"].ms'), t)   # PLAN_MS compté depuis la minute
        self.assertTrue(self.queued(gid))
        self.h.tick(1)                                             # étape 3 : faisabilité, relevé hors écran
        self.assertEqual(self.surveys(), s0 + 1)
        self.assertFalse(self.queued(gid))
        self.assertGreater(self.ev('getTimestampMs()'), t)
        self.assertEqual(self.ev(f'{F}.state.plans["{gid}"].ms'), t)
        self.assertIsNone(self.ev(f'{F}.clockAt'))
        self.h.tick(3)
        self.assertEqual(self.surveys(), s0 + 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_duplicate_and_fresh_plan_not_queued(self):
        gid = self.group()
        self.minute()
        self.minute(expire=False)                                  # deux minutes sans image : un seul relevé
        self.assertEqual(self.ev(f'#{Q}.list - {Q}.head + 1'), 1)
        s0 = self.surveys()
        self.h.tick(3)                                             # trois étapes, une image chacune
        self.assertEqual(self.surveys(), s0 + 1)
        self.minute(expire=False)                                  # plan frais (moins de PLAN_MS) : rien en file
        self.assertFalse(self.queued(gid))
        self.minute()
        self.assertTrue(self.queued(gid))

    def test_reading_the_plan_runs_the_queued_survey_first(self):
        gid = self.group()
        t = self.minute()
        self.h.advance_ms(700)
        s0 = self.surveys()
        self.assertIsNotNone(self.ev(f'{F}.levelOf("{gid}")'))
        self.assertEqual(self.surveys(), s0 + 1)
        self.assertEqual(self.ev(f'{F}.state.plans["{gid}"].ms'), t)
        self.assertEqual(self.ev(f'{F}.stats.settled'), 1)
        self.h.tick(3)                                             # entrée de la file déjà faite : sautée
        self.assertEqual(self.surveys(), s0 + 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_reading_the_plan_between_two_steps_runs_the_rest(self):
        gid = self.group()
        t = self.minute()
        self.h.tick(1)                                             # étape 1 faite
        s0 = self.surveys()
        self.assertIsNotNone(self.ev(f'{F}.levelOf("{gid}")'))   # étapes 2 et 3 tout de suite, sans nouveau relevé
        self.assertEqual(self.surveys(), s0)
        self.assertFalse(self.queued(gid))
        self.assertEqual(self.ev(f'{F}.state.plans["{gid}"].ms'), t)
        self.assertEqual(self.ev(f'{F}.stats.settled'), 1)
        self.assertIsNone(self.ev(f'{F}.givenPlan'))
        self.h.tick(3)
        self.assertEqual(self.surveys(), s0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_stock_check_of_the_group_waits_for_its_queued_survey(self):
        gid = self.group()
        self.minute()
        self.h.tick(1)                                             # étape 1 faite
        self.run_lua(f'local St = {ST} St.queue.list, St.queue.head, St.queue.queued = {{ "{gid}" }}, 1, '
                     f'{{ ["{gid}"] = true }} St.queue.fresh = false')
        self.assertFalse(self.ev(f'{ST}.onFrame()'))               # relecture du stock en attente du relevé
        self.assertEqual(self.ev(f'{ST}.queue.head'), 1)
        self.assertTrue(self.queued(gid))
        self.assertTrue(self.ev('LivingKnox.Groups.isHeld()'))
        self.assertEqual(self.ev(f'{ST}.finishQueue()'), 1)        # file vidée : relevé fini d'abord
        self.assertFalse(self.queued(gid))
        self.assertEqual(self.ev(f'{F}.stats.settled'), 1)

    def test_invalidate_runs_the_queued_survey_then_forgets_the_plan(self):
        gid = self.group()
        self.minute()
        s0 = self.surveys()
        self.run_lua(f'{F}.invalidate("{gid}")')
        self.assertEqual(self.surveys(), s0 + 1)
        self.assertFalse(self.queued(gid))
        self.assertLess(self.ev(f'{F}.state.plans["{gid}"].ms'), -1e17)

    def test_one_registry_write_after_the_queue_and_save_empties_it(self):
        gid = self.group()
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].fort = nil return true, true end))')
        self.h.tick(2)                                             # relevé hors écran effacé (écrit)
        self.assertIsNone(self.ev(f'FORT("{gid}")'))
        w0 = self.ev('LivingKnox.Groups.stats.writes')
        self.minute()
        self.h.tick(2)                                             # relevé du monde, plan : rien écrit
        self.assertIsNone(self.ev(f'FORT("{gid}")'))
        self.h.tick(1)                                             # faisabilité : premier relevé hors écran, retenu
        self.assertIsNotNone(self.ev(f'FORT("{gid}")'))
        self.assertEqual(self.ev('LivingKnox.Groups.stats.writes'), w0)
        self.assertTrue(self.ev('LivingKnox.Groups.isHeld()'))
        self.h.tick(1)                                             # image de l'écriture seule
        self.assertEqual(self.ev('LivingKnox.Groups.stats.writes'), w0 + 1)
        self.assertFalse(self.ev('LivingKnox.Groups.isHeld()'))
        self.minute()
        s0 = self.surveys()
        self.h.fire('solo', 'OnSave')
        self.assertEqual(self.surveys(), s0 + 1)
        self.assertFalse(self.queued(gid))
        self.assertFalse(self.ev('LivingKnox.Groups.isHeld()'))

    def test_failing_survey_is_logged_and_the_queue_goes_on(self):
        gid = self.group()
        self.run_lua(f'local f = {F}.feasible {F}.feasible = function() error("boom") end ORIG_FEASIBLE = f')
        self.minute()
        self.h.tick(3)                                             # erreur à la troisième étape (faisabilité)
        self.assertTrue(any(f'fortify: group {gid} survey failed' in line and 'boom' in line for line in self.lk()))
        self.assertFalse(self.queued(gid))
        self.assertIsNone(self.ev(f'{F}.clockAt'))

    def test_offscreen_hour_reads_the_survey_of_the_minute(self):
        gid = self.group(builder=True)
        self.run_lua('LivingKnox.Simulation.isEmbodied = function() return false end')
        self.minute()
        self.assertIsNone(self.off(gid, NIGHT_HOUR))               # nuit : heure sans effet, relevé laissé en file
        self.assertTrue(self.queued(gid))
        r = self.off(gid, DAY_HOUR)                                # jour : relevé de la minute fait d'abord
        self.assertFalse(self.queued(gid))
        self.assertEqual(self.ev(f'{F}.stats.settled'), 1)
        self.assertEqual((r.builders, r.steps, r.sites), (1, 8, 2))
        self.assertEqual(self.h.errors('solo'), [])


class GroupTypesPeekTests(Base):
    def test_peek_returns_the_live_type_and_get_a_copy(self):
        t = self.ev('LivingKnox.GroupTypes.ids()[1]')
        self.assertIsNotNone(t)
        self.assertTrue(self.ev(f'rawequal(LivingKnox.GroupTypes.peek("{t}"), LivingKnox.GroupTypes.state.types["{t}"])'))
        self.assertFalse(self.ev(f'rawequal(LivingKnox.GroupTypes.get("{t}"), LivingKnox.GroupTypes.state.types["{t}"])'))
        self.assertIsNone(self.ev('LivingKnox.GroupTypes.peek("no-such-type")'))
        self.assertIsNone(self.ev('LivingKnox.GroupTypes.peek(nil)'))


class LoadBenchQueueTests(unittest.TestCase):
    """Banc de charge complet : plusieurs groupes, un relevé par image, mêmes octets qu'avec le relevé à la minute."""

    def test_one_step_per_frame_after_the_minute(self):
        import load_bench as lb
        bench = lb.LoadBench(seed=7)
        try:
            seen = 0
            for _ in range(60 * lb.TICKS_PER_MINUTE):
                bench.frame()
                left = bench.h.eval('server', f'#{Q}.list - {Q}.head + 1')
                if left >= 2 and bench.ticks % lb.TICKS_PER_MINUTE == 0:
                    settled = bench.h.eval('server', f'{F}.stats.settled')
                    frames = bench.h.eval('server', f'{F}.JOB_FRAMES') * left
                    for _ in range(frames):
                        bench.frame()
                        now = bench.h.eval('server', f'#{Q}.list - {Q}.head + 1')
                        if bench.h.eval('server', f'{F}.stats.settled') == settled:
                            self.assertIn(now, (left, left - 1))         # une étape par image
                        left, settled = now, bench.h.eval('server', f'{F}.stats.settled')
                        if left == 0:
                            break
                    self.assertEqual(left, 0)
                    seen += 1
                    if seen >= 3:
                        break
            self.assertGreaterEqual(seen, 3)
            self.assertEqual(bench.errors()['server'], [])
        finally:
            bench.close()

    def test_same_registry_and_fortify_log_full_load_bench(self):
        import load_bench as lb
        out = []
        for inline in (True, False):
            bench = lb.LoadBench(seed=7)
            try:
                if inline:
                    bench.h.load('server', INLINE)
                bench.run_minutes(181)                            # trois heures de jeu
                bench.h.load('server', FINISH)
                out.append((bench.h.eval('server', STATE),
                            [line for line in bench.h.logs('server') if 'fortify:' in line],
                            bench.h.eval('server', f'{F}.stats.surveys'), bench.errors()['server']))
            finally:
                bench.close()
        (old, old_log, old_n, old_err), (new, new_log, new_n, new_err) = out
        self.assertEqual((old_err, new_err), ([], []))
        self.assertGreater(new_n, 10)
        self.assertEqual(old_n, new_n)
        self.assertEqual(old_log, new_log)
        self.assertEqual(old, new)


class DecisionSpreadTests(unittest.TestCase):
    """LK13-T11 (suite) : membres d'un passage évalués un par image, notation de l'heure un groupe par image. Les
    écritures en place ne suivent plus l'ancien ordre : déterminisme du nouveau code (deux passages identiques)."""

    def run_bench(self, minutes=181):
        """Banc de charge complet (trois heures) : registres encodés, plus grand nombre de membres évalués dans une
        image, nombre de notations."""
        import load_bench as lb
        bench = lb.LoadBench(seed=7)
        try:
            bench.h.load('server', 'MAXSTEP = 0 local D = LivingKnox.Decisions local step = D.memberStep '
                                   'D.memberStep = function(...) local n = step(...) '
                                   'if n > MAXSTEP then MAXSTEP = n end return n end')
            bench.run_minutes(minutes)
            bench.h.load('server', FINISH)
            return (bench.h.eval('server', STATE), bench.h.eval('server', 'MAXSTEP'),
                    bench.h.eval('server', 'LivingKnox.Decisions.stats.scored'), bench.errors()['server'])
        finally:
            bench.close()

    def test_two_runs_give_the_same_registries_and_one_member_per_frame(self):
        a, b = self.run_bench(), self.run_bench()
        self.assertEqual((a[3], b[3]), ([], []))
        self.assertEqual(a[0], b[0])                                   # registres identiques à l'octet
        self.assertEqual(a[1], 1)                                      # un membre évalué par image au plus
        self.assertGreater(a[2], 0)
        self.assertEqual(a[2], b[2])


if __name__ == '__main__':
    unittest.main()
