"""Tests hors jeu du pas horaire étalé et de la relecture du stock étalée (LK13-T09) : LK_Simulation.lua (file des
passes horaires), LK_Groups.lua (écriture retenue), LK_Server.lua (abonnés), LK_Stock.lua (un groupe par image).

    python RadioSurvivor/tests/test_lk_spread.py

Banc tests/harness.py. EveryHours et EveryOneMinute sont déclenchés par le test (le banc n'émule pas GameTime.update) :
l'ordre réel « EveryHours avant OnTick dans la même image » est rejoué à la main (OnTickEvenPaused, EveryHours,
OnTick). Déterminisme : mêmes octets du registre des groupes (journal compris) et des attitudes, avec les passes
dans la même image (ancien chemin : Simulation.defer et Stock.queueScan remplacés par l'appel direct) ou étalées,
sur le banc léger de test_lk_simulation et sur le banc de charge complet (tools/load_bench.py, 5 groupes, 4 joueurs).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import test_lk_simulation as tsim  # noqa: E402
import test_lk_stock as tstock  # noqa: E402

SIM = 'LivingKnox.Simulation'
G = 'LivingKnox.Groups'
ST = 'LivingKnox.Stock'
NOW = ('Population', 'Simulation', 'Needs')          # dans l'image de l'EveryHours
LATER = ('Decisions', 'Hostility')                   # une par image ensuite
PASSES = NOW + LATER

# Trace des passes horaires : nom, heure reçue, image du banc (FRAME, avancée par le test).
TRACE = r'''
FRAME = 0
TRACE = {}
local function wrap(mod, name)
    local M = LivingKnox[mod]
    local fn = M.onEveryHours
    M.onEveryHours = function(hour, ...)
        TRACE[#TRACE + 1] = name .. ":" .. tostring(hour) .. ":" .. tostring(FRAME)
        return fn(hour, ...)
    end
end
wrap("Population", "Population")
wrap("Simulation", "Simulation")
wrap("Needs", "Needs")
wrap("Decisions", "Decisions")
wrap("Hostility", "Hostility")
function TRACE_TEXT() return table.concat(TRACE, " ") end
'''

# Ancien chemin (avant LK13-T09) : chaque passe part aussitôt, dans l'abonné EveryHours ; relecture du stock de la
# minute dans l'abonné EveryOneMinute.
INLINE = r'''
LivingKnox.Simulation.defer = function(name, fn) fn(LivingKnox.Simulation.currentHour()) end
if LivingKnox.Stock ~= nil then
    LivingKnox.Stock.queueScan = function() return LivingKnox.Stock.scan("minute") end
end
'''

STATE = ('(function() local C = require "RadioSurvivor/RS_Codec" '
         'local H = LivingKnox.Hostility and LivingKnox.Hostility.state and LivingKnox.Hostility.state.data '
         'return C.hexBytes(C.encodeBytes(LivingKnox.Groups.state.data)) .. "|" .. '
         '(H and C.hexBytes(C.encodeBytes(H)) or "") end)()')


class SpreadBase(tsim.Base):
    def setUp(self):
        super().setUp()
        self.setup_world()
        self.h.load(self.srv, TRACE)

    def trace(self):
        text = self.ev('TRACE_TEXT()')
        return text.split(' ') if text else []

    def frame(self, n=1):
        for _ in range(n):
            self.run_lua('FRAME = FRAME + 1')
            self.h.tick(1)

    def writes(self):
        return self.ev(f'{G}.stats.writes')

    def next_hour(self):
        self.h.advance(60)
        self.h.fire(self.srv, 'EveryHours')
        return self.hour()


class HourlyQueueTests(SpreadBase):
    def test_scoring_leaves_the_hour_frame_and_runs_one_pass_per_frame_in_order(self):
        self.frame()
        hour = self.next_hour()
        self.assertEqual([t.split(':')[0] for t in self.trace()], list(NOW))   # jauges avancées dans l'image
        self.assertTrue(self.ev(f'{SIM}.hourPending()'))
        self.assertTrue(self.ev(f'{G}.isHeld()'))
        for i, name in enumerate(PASSES, start=1):
            if name in LATER:
                self.frame()
            self.assertEqual(len(self.trace()), max(i, len(NOW)))
            got, at, frame = self.trace()[i - 1].split(':')
            self.assertEqual(got, name)
            if name in LATER:
                self.assertEqual(int(frame), self.ev('FRAME'))   # une passe par image
            if name in ('Simulation', 'Needs', 'Decisions'):
                self.assertEqual(int(float(at)), hour)           # heure lue à l'EveryHours
        self.assertEqual(self.ev('LivingKnox.Groups.state.data.simHour'), hour)

    def test_one_group_write_for_the_whole_hour(self):
        self.frame(2)
        before = self.writes()
        self.next_hour()
        self.frame(len(LATER))
        self.assertEqual(self.writes(), before)                   # écriture retenue pendant les passes
        self.assertTrue(self.ev(f'{G}.isDirty()'))
        self.frame()                                              # image de l'écriture seule
        self.assertEqual(self.writes(), before + 1)
        self.assertFalse(self.ev(f'{G}.isDirty()'))
        self.assertFalse(self.ev(f'{G}.isHeld()'))
        self.assertFalse(self.ev(f'{SIM}.hourPending()'))
        self.frame(3)
        self.assertEqual(self.writes(), before + 1)

    def test_game_order_hour_before_tick_in_the_same_frame(self):
        # GameTime.update (EveryHours) part avant l'OnTick de la même image : aucune passe dans cette image.
        self.h.fire(self.srv, 'OnTickEvenPaused', 1.0)
        self.h.advance(60)
        self.h.fire(self.srv, 'EveryHours')
        self.h.fire(self.srv, 'OnTick', 1.0)
        self.assertEqual([t.split(':')[0] for t in self.trace()], list(NOW))
        self.frame()
        self.assertEqual(self.trace()[-1].split(':')[0], 'Decisions')

    def test_new_hour_runs_the_rest_of_the_previous_hour_first(self):
        self.frame()
        first = self.next_hour()                                  # Decisions et Hostility en file
        second = self.next_hour()
        names = [(t.split(':')[0], int(float(t.split(':')[1])) if t.split(':')[1] != 'nil' else None)
                 for t in self.trace()]
        self.assertEqual([n for n, _ in names], list(PASSES) + list(NOW))   # l'heure précédente finie d'abord
        self.assertEqual(names[3][1], first)                      # notation restée sur l'heure précédente
        self.assertEqual(names[6][1], second)
        self.frame(len(LATER))
        later = [t.split(':') for t in self.trace()[8:]]
        self.assertEqual([t[0] for t in later], list(LATER))
        self.assertEqual(int(float(later[0][1])), second)
        self.assertEqual(self.ev(f'{SIM}.spreadStats.flushedEarly'), 1)
        self.assertEqual(self.ev('LivingKnox.Groups.state.data.simHour'), second)

    def test_failing_pass_is_logged_and_the_next_ones_run(self):
        self.run_lua('LivingKnox.Decisions.onEveryHours = function() error("boom") end')
        self.frame()
        self.next_hour()
        self.frame(len(LATER) + 1)
        self.assertEqual([t.split(':')[0] for t in self.trace()], ['Population', 'Simulation', 'Needs', 'Hostility'])
        self.assertTrue(any('hourly pass Decisions failed' in line and 'boom' in line for line in self.lk()), self.lk())
        self.assertEqual(self.ev(f'{SIM}.spreadStats.errors'), 1)
        self.assertFalse(self.ev(f'{G}.isHeld()'))

    def test_save_runs_the_remaining_passes_and_writes(self):
        self.frame()
        before = self.writes()
        self.next_hour()
        self.h.fire(self.srv, 'OnSave')                          # notation et attitudes encore en file
        self.assertEqual([t.split(':')[0] for t in self.trace()], list(PASSES))
        self.assertEqual(self.writes(), before + 1)
        self.assertFalse(self.ev(f'{G}.isDirty()'))
        self.assertFalse(self.ev(f'{SIM}.hourPending()'))

    def test_held_write_is_bounded_in_frames(self):
        self.frame()
        before = self.writes()
        self.run_lua(f'{G}.hold("test", 3) {G}.markDirty()')
        self.frame(2)
        self.assertEqual(self.writes(), before)
        self.frame(1)
        self.assertEqual(self.writes(), before + 1)              # retenue échue sans release

    def test_explicit_flush_is_never_held(self):
        self.frame()
        before = self.writes()
        self.run_lua(f'{G}.hold("test", 10) {G}.markDirty() assert({G}.flush())')
        self.assertEqual(self.writes(), before + 1)


class DeterminismTests(unittest.TestCase):
    """Mêmes heures, mêmes octets : passes dans l'image de l'EveryHours (ancien chemin) ou une par image."""

    def run_hours(self, inline, hours=30):
        case = tsim.Base(methodName='run')
        case.setUp()
        try:
            case.setup_world()
            if inline:
                case.h.load(case.srv, INLINE)
            for _ in range(hours):
                case.h.advance(60)
                case.h.fire(case.srv, 'EveryHours')
                case.h.tick(len(LATER) + 2)
            case.h.load(case.srv, f'{G}.flush()')
            return case.ev(STATE), case.lk()
        finally:
            case.tearDown()

    def test_same_registry_and_log_light_bench(self):
        old, old_log = self.run_hours(inline=True)
        new, new_log = self.run_hours(inline=False)
        self.assertEqual(old, new)
        self.assertEqual([line for line in old_log if 'simulation:' in line or 'objective' in line],
                         [line for line in new_log if 'simulation:' in line or 'objective' in line])

    def test_same_registry_full_load_bench(self):
        import load_bench as lb
        out = []
        for inline in (True, False):
            bench = lb.LoadBench(seed=7)
            try:
                if inline:
                    bench.h.load('server', INLINE)
                bench.run_minutes(181)                            # trois heures de jeu
                bench.h.load('server', f'{SIM}.finishHour() {ST}.finishQueue() {G}.flush()')
                out.append((bench.h.eval('server', STATE), bench.h.eval('server', f'{SIM}.spreadStats.jobs'),
                            bench.errors()['server']))
            finally:
                bench.close()
        (old, old_jobs, old_err), (new, new_jobs, new_err) = out
        self.assertEqual((old_err, new_err), ([], []))
        self.assertEqual(old_jobs, 0)
        self.assertEqual(new_jobs, 3 * len(LATER))
        self.assertEqual(old, new)


class StockQueueTests(tstock.Base):
    """Relecture de la minute : un groupe par image, à partir de l'image qui suit la minute, sans doublon."""

    def setUp(self):
        super().setUp()
        self.run_lua(tstock.HOUSE)
        self.run_lua(tstock.KITCHEN)

    def checks(self):
        return self.ev(f'{ST}.stats.checks')

    def test_one_group_per_frame_after_the_minute(self):
        a = self.group(name='Mill')
        b = self.group(name='Farm', home=(104, 105, 0))
        self.minute()                                             # aménagement, remplissage (file vidée)
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{a}").stock.fill'), 'done')
        start = self.checks()
        self.h.advance_ms(5000)
        self.h.advance(1)
        self.assertEqual(self.checks(), start)                    # rien dans l'image de la minute
        self.assertEqual(self.ev(f'#{ST}.queue.list - {ST}.queue.head + 1'), 2)
        self.h.tick(1)
        self.assertEqual(self.checks(), start + 1)
        self.h.tick(1)
        self.assertEqual(self.checks(), start + 2)
        self.h.tick(3)
        self.assertEqual(self.checks(), start + 2)
        self.assertNotEqual(a, b)

    def test_one_group_write_for_the_whole_queue(self):
        a = self.group(name='Mill')
        b = self.group(name='Farm', home=(104, 105, 0))
        self.minute()
        self.h.tick(2)
        for gid in (a, b):                                        # deux références qui changent
            self.take(gid, 'Base.TinnedBeans')
        before = self.ev('LivingKnox.Groups.stats.writes')
        self.h.advance_ms(5000)
        self.h.advance(1)
        self.h.tick(2)                                            # deux relectures, écriture retenue
        self.assertEqual(self.ev('LivingKnox.Groups.stats.writes'), before)
        self.assertTrue(self.ev('LivingKnox.Groups.isDirty()'))
        self.h.tick(1)                                            # image de l'écriture seule
        self.assertEqual(self.ev('LivingKnox.Groups.stats.writes'), before + 1)
        self.assertFalse(self.ev('LivingKnox.Groups.isHeld()'))

    def test_no_duplicate_and_same_result_as_a_scan(self):
        gid = self.group()
        self.minute()
        self.run_lua('BIND("A", "c-alpha")')
        self.take(gid, 'Base.Rope')
        self.h.advance_ms(5000)
        self.h.advance(1)
        self.h.advance(1)                                         # deux minutes sans image : un seul passage
        self.assertEqual(self.ev(f'#{ST}.queue.list - {ST}.queue.head + 1'), 1)
        self.h.tick(1)
        self.assertEqual(self.ev(f'#LivingKnox.Hostility.state.data.groups["{gid}"]["c-alpha"].facts'), 1)
        self.assertEqual(list(self.ev(f'REF_IDS("{gid}")').values()), list(self.ev(f'REAL_IDS("{gid}")').values()))


if __name__ == '__main__':
    unittest.main()
