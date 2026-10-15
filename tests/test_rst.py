"""Tests hors jeu du noyau RST (moteur de tests en jeu) et de son installateur.

    python RadioSurvivor/tests/test_rst.py

Charge le vrai `RST.lua` dans `lupa.lua51` (Lua 5.1, `next` retiré comme dans Kahlua, horloge simulée)
et l'exerce sur des suites factices. Ne vérifie pas l'API Java du jeu : le test en jeu reste nécessaire.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'dev' / 'batman_RadioSurvivorTests'
LUA = MOD / '42.21' / 'media' / 'lua'
RST_FILE = LUA / 'shared' / 'RST' / 'RST.lua'
CLIENT_FILE = LUA / 'client' / 'RST' / 'RST_Client.lua'
SELFTEST_FILE = LUA / 'shared' / 'RST' / 'suites' / 'RST_SelfTest.lua'
FAILURES_FILE = LUA / 'shared' / 'RST' / 'suites' / 'RST_Failures.lua'
SERVER_FILE = LUA / 'server' / 'RST' / 'RST_Server.lua'
FIXTURES_FILE = LUA / 'shared' / 'RST' / 'RST_Fixtures.lua'
FIXTURES_SUITE_FILE = LUA / 'shared' / 'RST' / 'suites' / 'RST_FixturesSuite.lua'
sys.path.insert(0, str(ROOT / 'tools'))
import install_tests  # noqa: E402

PRELUDE = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
CLOCK = 1000
function logged(pattern) for _, l in ipairs(LOGS) do if string.find(l, pattern) then return true end end return false end
"""


class LuaHarness(unittest.TestCase):
    """Environnement lupa commun (aucun test ici)."""

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.rt.globals()
        g.next = None  # absent de Kahlua
        self.rt.execute(PRELUDE)
        self.rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('getTimestampMs = function() return CLOCK end')
        self.rt.execute('RST_MODULE = require "RST/RST"')
        self.g = g

    def lua(self, code):
        return self.rt.execute(code)

    def run_suites(self, code, flt='nil'):
        self.lua(code)
        return self.lua(f'REPORT = RST.runSync({flt}) return REPORT')

    def results(self):
        out = []
        for _, r in self.g.REPORT.results.items():
            out.append((r.suite, r.test, r.status, r.message))
        return out

    def status(self, suite, test):
        for s, t, st, msg in self.results():
            if s == suite and t == test:
                return st, msg
        self.fail(f'{suite} :: {test} absent du rapport')


class RstTests(LuaHarness):

    # ------------------------------------------------------------- chargement

    def test_module_loaded_by_require_and_global(self):
        self.assertTrue(self.lua('return RST_MODULE == RST and type(RST.suite) == "function"'))
        self.assertEqual(self.lua('return RST.clock()'), 1000)

    def test_reload_keeps_existing_table_and_registry(self):
        self.lua('RST.suite("a", function(s) s.test("x", function(t) t:ok(true) end) end)')
        self.lua('package.loaded["RST/RST"] = nil; local old = RST; require "RST/RST"; SAME = (old == RST)')
        self.assertTrue(self.g.SAME)
        self.assertEqual(self.lua('return #RST._suites'), 1)

    def test_default_clock_without_getTimestampMs(self):
        self.lua('getTimestampMs = nil; RST.clock = nil; package.loaded["RST/RST"] = nil; require "RST/RST"')
        self.assertGreater(self.lua('return RST.clock()'), 1_000_000_000_000)

    def test_no_next_no_goto_in_source(self):
        for path in (RST_FILE, CLIENT_FILE, SELFTEST_FILE, FAILURES_FILE, SERVER_FILE, FIXTURES_FILE, FIXTURES_SUITE_FILE):
            src = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', src, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code), path.name)
            self.assertIsNone(re.search(r'\bgoto\b', code), path.name)
            self.assertIsNone(re.search(r'debug\.traceback|%q|coroutine\.wrap', code), path.name)

    # ------------------------------------------------------------- isolation et statuts

    def test_counters_and_statuses(self):
        rep = self.run_suites(r'''
        RST.suite("demo", function(s)
            s.test("pass", function(t) t:ok(true); t:eq(1, 1) end)
            s.test("fail", function(t) t:eq(1, 2, "numbers"); t:ok(true) end)
            s.test("error", function(t) local x = nil; return x.field end)
            s.test("skipped by opts", function(t) end, { skip = "later" })
            s.skip("skipped by s.skip", "not ready")
            s.test("skipped by t", function(t) t:skip("no world") end)
            s.test("empty", function(t) end)
        end)''')
        self.assertEqual((rep['pass'], rep.fail, rep.error, rep.skip,
                          rep.empty, rep.total), (1, 1, 1, 3, 1, 7))
        self.assertFalse(rep.ok)
        self.assertEqual(self.status('demo', 'fail'), ('FAIL', 'numbers: expected 1, got 2'))
        st, msg = self.status('demo', 'error')
        self.assertEqual(st, 'ERROR')
        self.assertIn('nil', msg)
        self.assertEqual(self.status('demo', 'skipped by opts'), ('SKIP', 'later'))
        self.assertEqual(self.status('demo', 'skipped by s.skip'), ('SKIP', 'not ready'))
        self.assertEqual(self.status('demo', 'skipped by t'), ('SKIP', 'no world'))
        self.assertEqual(self.status('demo', 'empty'), ('EMPTY', 'no assertion'))

    def test_all_pass_is_ok(self):
        rep = self.run_suites('RST.suite("a", function(s) s.test("x", function(t) t:ok(1) end) end)')
        self.assertTrue(rep.ok)

    def test_empty_alone_makes_report_not_ok(self):
        rep = self.run_suites('RST.suite("a", function(s) s.test("x", function(t) end) end)')
        self.assertEqual((rep.empty, rep.ok), (1, False))

    def test_crashing_suite_does_not_stop_others(self):
        self.run_suites(r'''
        RST.suite("first", function(s) s.test("boom", function(t) error("kaboom") end)
            s.test("after boom", function(t) t:ok(true) end) end)
        RST.suite("second", function(s) s.test("still runs", function(t) t:ok(true) end) end)''')
        self.assertEqual(self.status('first', 'boom')[0], 'ERROR')
        self.assertIn('kaboom', self.status('first', 'boom')[1])
        self.assertEqual(self.status('first', 'after boom')[0], 'PASS')
        self.assertEqual(self.status('second', 'still runs')[0], 'PASS')

    def test_declaration_error_is_reported(self):
        rep = self.run_suites(r'''
        RST.suite("broken", function(s) s.test("a", function(t) t:ok(true) end) error("bad decl") end)
        RST.suite("fine", function(s) s.test("b", function(t) t:ok(true) end) end)''')
        st, msg = self.status('broken', '(declaration)')
        self.assertEqual(st, 'ERROR')
        self.assertIn('bad decl', msg)
        self.assertEqual(self.status('fine', 'b')[0], 'PASS')
        self.assertEqual((rep.total, rep.error, rep['pass']), (2, 1, 1))
        self.assertTrue(self.lua('return logged("declaration of suite .broken. failed")'))

    def test_hooks_order_and_before_failure(self):
        self.run_suites(r'''
        CALLS = {}
        RST.suite("hooks", function(s)
            s.before(function(t) CALLS[#CALLS + 1] = "before"; if t.ctx and t.ctx.breakBefore then error("setup") end end)
            s.after(function(t) CALLS[#CALLS + 1] = "after" end)
            s.test("x", function(t) CALLS[#CALLS + 1] = "test"; t:ok(true) end)
        end)''')
        self.assertEqual(list(self.g.CALLS.values()), ['before', 'test', 'after'])
        self.lua('CALLS = {}; REPORT = RST.runSync("hooks", { breakBefore = true })')
        self.assertEqual(list(self.g.CALLS.values()), ['before', 'after'])
        st, msg = self.status('hooks', 'x')
        self.assertEqual(st, 'ERROR')
        self.assertTrue(msg.startswith('before: '))

    def test_before_assertion_is_fail_and_after_called(self):
        self.run_suites(r'''
        AFTER = 0
        RST.suite("h", function(s)
            s.before(function(t) t:ok(false, "precondition") end)
            s.after(function(t) AFTER = AFTER + 1 end)
            s.test("x", function(t) t:ok(true) end)
        end)''')
        self.assertEqual(self.status('h', 'x'), ('FAIL', 'before: precondition: expected a true value, got false'))
        self.assertEqual(self.g.AFTER, 1)

    def test_after_failure_turns_pass_into_fail_and_appends(self):
        self.run_suites(r'''
        RST.suite("h", function(s)
            s.after(function(t) t:ok(false, "cleanup") end)
            s.test("passing", function(t) t:ok(true) end)
            s.test("failing", function(t) t:ok(false, "body") end)
        end)''')
        self.assertEqual(self.status('h', 'passing')[0], 'FAIL')
        self.assertEqual(self.status('h', 'passing')[1], 'after: cleanup: expected a true value, got false')
        st, msg = self.status('h', 'failing')
        self.assertEqual(st, 'FAIL')
        self.assertIn('body', msg)
        self.assertIn('; after: cleanup', msg)

    def test_hook_assertions_do_not_hide_empty_test(self):
        self.run_suites(r'''
        RST.suite("h", function(s) s.before(function(t) t:ok(true) end) s.test("x", function(t) end) end)''')
        self.assertEqual(self.status('h', 'x')[0], 'EMPTY')

    def test_durations_with_simulated_clock(self):
        rep = self.run_suites(r'''
        RST.suite("time", function(s) s.test("slow", function(t) CLOCK = CLOCK + 12; t:ok(true) end) end)''')
        self.assertEqual(self.lua('return REPORT.results[1].ms'), 12)
        self.assertEqual(rep.durationMs, 12)

    # ------------------------------------------------------------- assertions

    def test_deep_equality_and_message(self):
        self.run_suites(r'''
        RST.suite("eq", function(s)
            s.test("deep ok", function(t) t:eq({ a = 1, b = { 1, 2, { c = "x" } } }, { b = { 1, 2, { c = "x" } }, a = 1 }) end)
            s.test("deep ko", function(t) t:eq({ a = 1, b = { 1, 2 } }, { a = 1, b = { 1, 3 } }) end)
            s.test("extra key", function(t) t:eq({ a = 1 }, { a = 1, z = true }) end)
            s.test("string", function(t) t:eq("a\nb", "a") end)
            s.test("cycle", function(t) local a = {}; a.self = a; local b = {}; b.self = b; t:eq(a, b) end)
            s.test("ne ok", function(t) t:ne({ 1 }, { 2 }) end)
            s.test("ne ko", function(t) t:ne({ 1 }, { 1 }, "same") end)
        end)''')
        self.assertEqual(self.status('eq', 'deep ok')[0], 'PASS')
        self.assertEqual(self.status('eq', 'deep ko'),
                         ('FAIL', 'expected {a=1, b={1, 2}}, got {a=1, b={1, 3}} (first difference at .b[2])'))
        self.assertEqual(self.status('eq', 'extra key'),
                         ('FAIL', 'expected {a=1}, got {a=1, z=true} (first difference at .z)'))
        self.assertEqual(self.status('eq', 'string'), ('FAIL', 'expected "a\\nb", got "a"'))
        self.assertEqual(self.status('eq', 'cycle')[0], 'PASS')
        self.assertEqual(self.status('eq', 'ne ok')[0], 'PASS')
        self.assertEqual(self.status('eq', 'ne ko'), ('FAIL', 'same: expected a value different from {1}'))

    def test_render_is_bounded(self):
        out = self.lua(r'''local t = {} for i = 1, 100 do t[i] = i end t.k = { { { { "deep" } } } } return RST.render(t)''')
        self.assertTrue(out.endswith('...}'), out)
        self.assertNotIn('13', out)
        long = self.lua('return RST.render(string.rep("x", 1000))')
        self.assertLessEqual(len(long), 240)
        deep = self.lua('return RST.render({ a = { b = { c = { d = 1 } } } })')
        self.assertEqual(deep, '{a={b={c={...}}}}')

    def test_near(self):
        self.run_suites(r'''
        RST.suite("near", function(s)
            s.test("ok", function(t) t:near(1.0, 1.05, 0.1) end)
            s.test("ko", function(t) t:near(1.0, 1.5, 0.1) end)
            s.test("type", function(t) t:near(1.0, "1") end)
        end)''')
        self.assertEqual(self.status('near', 'ok')[0], 'PASS')
        self.assertEqual(self.status('near', 'ko'), ('FAIL', 'expected 1 +/- 0.1, got 1.5'))
        self.assertEqual(self.status('near', 'type')[0], 'FAIL')

    def test_fails_with_and_without_pattern(self):
        self.run_suites(r'''
        RST.suite("fails", function(s)
            s.test("any error", function(t) local m = t:fails(function() error("boom 42") end); t:ok(string.find(m, "boom")) end)
            s.test("pattern ok", function(t) t:fails(function() error("code 42") end, "code %d+") end)
            s.test("pattern ko", function(t) t:fails(function() error("other") end, "^code") end)
            s.test("no error", function(t) t:fails(function() end, nil, "must raise") end)
        end)''')
        self.assertEqual(self.status('fails', 'any error')[0], 'PASS')
        self.assertEqual(self.status('fails', 'pattern ok')[0], 'PASS')
        st, msg = self.status('fails', 'pattern ko')
        self.assertEqual(st, 'FAIL')
        self.assertIn('does not match "^code"', msg)
        self.assertEqual(self.status('fails', 'no error'), ('FAIL', 'must raise: expected an error, none raised'))

    # ------------------------------------------------------------- filtres et liste

    SUITES = r'''
    RST.suite("rst", function(s) s.test("root", function(t) t:ok(true) end) end)
    RST.suite("rst.selftest", { tags = { "shared" } }, function(s)
        s.test("alpha one", function(t) t:ok(true) end)
        s.test("beta", function(t) t:ok(true) end)
    end)
    RST.suite("rstx", { tags = { "client" } }, function(s) s.test("x", function(t) t:ok(true) end) end)
    RST.suite("rs.codec", { tags = { "shared", "world" } }, function(s) s.test("decode", function(t) t:ok(true) end) end)
    RST.suite("srv", { tags = "server" }, function(s) s.test("s", function(t) t:ok(true) end) end)
    '''

    def names(self, flt):
        sel = self.lua(f'local out = {{}} for _, it in ipairs(RST.select({flt})) do '
                       'out[#out + 1] = it.suite.name .. ":" .. #it.tests end return table.concat(out, " ")')
        return sel.split(' ') if sel else []

    def test_filters(self):
        self.lua(self.SUITES)
        self.assertEqual(self.names('nil'), ['rst:1', 'rst.selftest:2', 'rstx:1', 'rs.codec:1', 'srv:1'])
        self.assertEqual(self.names('"rst"'), ['rst:1', 'rst.selftest:2'])
        self.assertEqual(self.names('"rst.selftest"'), ['rst.selftest:2'])
        self.assertEqual(self.names('"rs."'), ['rs.codec:1'])
        self.assertEqual(self.names('"nothing"'), [])
        self.assertEqual(self.names('{ suite = { "rstx", "srv" } }'), ['rstx:1', 'srv:1'])
        self.assertEqual(self.names('{ test = "^al" }'), ['rst.selftest:1'])
        self.assertEqual(self.names('{ tags = { "shared", "server" } }'), ['rst.selftest:2', 'rs.codec:1', 'srv:1'])
        self.assertEqual(self.names('{ tags = "shared", exclude = { "world" } }'), ['rst.selftest:2'])
        self.assertEqual(self.names('{ exclude = "world" }'), ['rst:1', 'rst.selftest:2', 'rstx:1', 'srv:1'])
        self.assertEqual(self.names('{ suite = "rst", test = "beta" }'), ['rst.selftest:1'])
        self.assertTrue(self.lua('return not pcall(RST.select, 42)'))

    def test_run_with_filter_only_runs_selected(self):
        self.lua(self.SUITES)
        rep = self.lua('REPORT = RST.runSync({ suite = "rst", test = "beta" }) return REPORT')
        self.assertEqual(rep.total, 1)
        self.assertEqual(self.results()[0][:3], ('rst.selftest', 'beta', 'PASS'))

    def test_declaration_error_visible_with_test_pattern(self):
        self.lua(self.SUITES + 'RST.suite("rst.broken", function(s) error("x") end)')
        self.assertEqual(self.names('{ suite = "rst", test = "zzz" }'), ['rst.broken:0'])

    def test_list(self):
        self.lua(self.SUITES + 'RST.suite("rst.broken", function(s) error("nope") end)')
        self.lua('LOGS = {}; LIST = RST.list("rst")')
        lst = self.g.LIST
        self.assertEqual([(e.name, e.count) for e in lst.values()],
                         [('rst', 1), ('rst.selftest', 2), ('rst.broken', 0)])
        self.assertEqual(list(lst[2].tags.values()), ['shared'])
        self.assertIn('nope', lst[3].error)
        logs = list(self.g.LOGS.values())
        self.assertIn('[RST] rst.selftest [shared] 2 test(s)', logs)
        self.assertIn('[RST] 3 suite(s)', logs)
        self.lua('LOGS = {}; RST.list(nil, true)')
        self.assertEqual(len(self.g.LOGS), 0)

    def test_redeclaration_replaces_in_place_with_warning(self):
        self.lua(r'''
        RST.suite("a", function(s) s.test("old", function(t) t:ok(true) end) end)
        RST.suite("b", function(s) s.test("b", function(t) t:ok(true) end) end)
        RST.suite("a", function(s) s.test("new", function(t) t:ok(true) end) end)''')
        self.assertEqual(self.names('nil'), ['a:1', 'b:1'])
        self.lua('REPORT = RST.runSync("a")')
        self.assertEqual(self.results()[0][1], 'new')
        self.assertTrue(self.lua('return logged("WARNING: suite .a. declared again")'))

    def test_duplicate_test_name_last_wins(self):
        self.run_suites(r'''RST.suite("d", function(s)
            s.test("x", function(t) t:ok(false) end) s.test("x", function(t) t:ok(true) end) end)''')
        self.assertEqual(self.results(), [('d', 'x', 'PASS', None)])

    def test_suite_argument_errors(self):
        self.assertTrue(self.lua('return not pcall(RST.suite, "x")'))
        self.assertTrue(self.lua('return not pcall(RST.suite, "", function() end)'))

    # ------------------------------------------------------------- rapport texte

    def test_format_report(self):
        self.run_suites(r'''
        RST.suite("fmt", function(s)
            s.test("ok", function(t) CLOCK = CLOCK + 12; t:ok(true) end)
            s.test("bad", function(t) t:eq(1, 2) end)
            s.skip("later", "reason")
        end)''')
        lines = list(self.lua('return RST.formatReport(REPORT, { "PZ 42.21", "side: client" })').values())
        self.assertEqual(lines, [
            'PZ 42.21',
            'side: client',
            'PASS   fmt :: ok (12 ms)',
            'FAIL   fmt :: bad (0 ms) expected 1, got 2',
            'SKIP   fmt :: later (0 ms) reason',
            'FAILED - 3 test(s): 1 pass, 1 fail, 0 error, 1 skip, 0 empty (12 ms)',
        ])
        lines = list(self.lua('return RST.formatReport(RST.runSync("nothing"))').values())
        self.assertEqual(lines, ['OK - 0 test(s): 0 pass, 0 fail, 0 error, 0 skip, 0 empty (0 ms)'])

    def test_multiline_error_message_stays_on_one_line(self):
        self.run_suites('RST.suite("m", function(s) s.test("x", function(t) error("a\\nb", 0) end) end)')
        lines = list(self.lua('return RST.formatReport(REPORT)').values())
        self.assertEqual(lines[0], 'ERROR  m :: x (0 ms) a / b')


class AsyncTests(LuaHarness):
    """Ordonnanceur asynchrone : RST.start / RST.step pilotés par une horloge simulée (CLOCK)."""

    def start(self, flt='nil', opts=''):
        return self.lua(f'DONE = nil; return RST.start({flt}, {{ attach = false, '
                        f'onDone = function(r) DONE = r; REPORT = r end, {opts} }})')

    def tick(self, dt=100):
        """Un tick de jeu : RST.step() puis l'horloge avance de dt ms. Renvoie le retour de step."""
        return self.lua(f'local r = RST.step(); CLOCK = CLOCK + {dt}; return r')

    def run_to_end(self, dt=100, limit=10000):
        for i in range(limit):
            if not self.tick(dt):
                self.assertIsNotNone(self.g.DONE, 'onDone non appelé')
                self.assertFalse(self.lua('return RST.running()'))
                return i + 1
        self.fail('le passage ne se termine pas')

    # ------------------------------------------------------------- attentes

    def test_wait_until_success_and_assertions_around_wait(self):
        self.lua(r'''
        FLAG = false
        RST.suite("w", function(s)
            s.before(function(t) t:sleep(100) end)
            s.test("only wait", function(t) t:waitUntil(function() return FLAG end, 5000) end)
            s.test("around", function(t)
                t:ok(true)
                t:waitUntil(function() return FLAG end, 5000, function(t2, v)
                    t2:eq(42, v)
                    t2:eq(1, 2, "after wait")
                end)
            end)
        end)''')
        self.assertTrue(self.start())
        for _ in range(5):
            self.assertTrue(self.tick())
        self.assertTrue(self.lua('return RST.running()'))
        self.assertEqual(self.lua('return #RST._run.report.results'), 0)
        self.lua('FLAG = 42')
        self.run_to_end()
        self.assertEqual(self.status('w', 'only wait'), ('PASS', None))
        self.assertEqual(self.status('w', 'around'), ('FAIL', 'after wait: expected 1, got 2'))
        self.assertTrue(self.lua('return RST.last() == DONE'))

    def test_wait_checked_right_after_the_step_then_once_per_tick(self):
        self.lua(r'''
        CALLS = 0
        RST.suite("w", function(s)
            s.test("x", function(t)
                t:waitUntil(function() CALLS = CALLS + 1; return CALLS >= 3 end, 5000, function(t2) t2:ok(true) end)
            end)
        end)''')
        self.start()
        self.tick()
        self.assertEqual(self.g.CALLS, 1)  # même tick que l'étape
        self.tick()
        self.assertEqual(self.g.CALLS, 2)
        self.run_to_end()
        self.assertEqual(self.g.CALLS, 3)
        self.assertEqual(self.status('w', 'x')[0], 'PASS')

    def test_wait_until_timeout(self):
        self.lua(r'''RST.suite("w", function(s)
            s.test("never", function(t) t:waitUntil(function() return false end, 1000, "bridge reply") end)
            s.test("never4", function(t) t:waitUntil(function() return false end, 1000, nil, "with suite slot") end)
            s.test("next", function(t) t:ok(true) end)
        end)''')
        self.start()
        self.run_to_end()
        st, msg = self.status('w', 'never')
        self.assertEqual((st, msg), ('FAIL', 'bridge reply: condition not met within 1000 ms'))
        ms = self.lua('return REPORT.results[1].ms')
        self.assertGreaterEqual(ms, 1000)
        self.assertLess(ms, 1100)
        self.assertEqual(self.status('w', 'never4'), ('FAIL', 'with suite slot: condition not met within 1000 ms'))
        self.assertEqual(self.status('w', 'next')[0], 'PASS')

    def test_failed_wait_is_not_an_assertion(self):
        self.lua(r'''RST.suite("w", function(s)
            s.test("a", function(t) t:waitUntil(function() return false end, 300) end)
            s.test("quiet", function(t) t:waitQuiet(function() return true end, 300) end)
            s.test("counted", function(t) t:waitUntil(function() return true end, 300) end)
        end)''')
        self.start()
        self.run_to_end()
        self.assertEqual(self.status('w', 'a')[0], 'FAIL')
        self.assertEqual(self.status('w', 'quiet'), ('EMPTY', 'no assertion'))
        self.assertEqual(self.status('w', 'counted'), ('PASS', None))

    def test_sleep_resumes_at_the_right_tick(self):
        self.lua(r'''RST.suite("s", function(s)
            s.test("2 s", function(t) T0 = RST.now(); t:sleep(2000, function(t2) T1 = RST.now(); t2:ok(true) end) end)
            s.test("0 ms", function(t)
                Z0 = RST._run.tick
                t:sleep(0, function(t2) Z1 = RST._run.tick; t2:ok(true) end)
            end)
        end)''')
        self.start()
        self.run_to_end(dt=300)
        # ticks à +0, +300, ..., +2100 : premier tick où 2 s sont écoulées.
        self.assertEqual(self.g.T1 - self.g.T0, 2100)
        self.assertEqual(self.status('s', '2 s')[0], 'PASS')
        self.assertEqual(self.g.Z1, self.g.Z0 + 1)  # jamais au même tick
        self.assertEqual(self.status('s', '0 ms')[0], 'PASS')

    def test_sleep_and_wait_refused_under_run_sync(self):
        rep = self.run_suites(r'''RST.suite("sync", function(s)
            s.test("wait", function(t) t:waitUntil(function() return true end, 10) end)
            s.test("quiet", function(t) t:waitQuiet(function() return true end, 10) end)
            s.test("sleep", function(t) t:sleep(10) end)
            s.test("plain", function(t) t:ok(true) end)
        end)''')
        for name in ('wait', 'quiet', 'sleep'):
            st, msg = self.status('sync', name)
            self.assertEqual(st, 'ERROR')
            self.assertIn('needs an asynchronous run (RST.start); RST.runSync cannot wait', msg)
        self.assertEqual(self.status('sync', 'plain')[0], 'PASS')
        self.assertEqual(rep.total, 4)

    def test_wait_argument_errors(self):
        self.lua(r'''RST.suite("a", function(s)
            s.test("cond", function(t) t:waitUntil(42) end)
            s.test("ms", function(t) t:waitUntil(function() end, "x") end)
            s.test("suite", function(t) t:waitUntil(function() end, 10, 42) end)
            s.test("sleep ms", function(t) t:sleep("x") end)
            s.test("sleep suite", function(t) t:sleep(10, 42) end)
        end)''')
        self.start()
        self.run_to_end()
        self.assertEqual(self.status('a', 'cond'),
                         ('ERROR', 't:waitUntil(cond[, ms[, suite[, msg]]]) expects a function'))
        self.assertIn('expects ms to be a number', self.status('a', 'ms')[1])
        self.assertIn('expects suite to be a function', self.status('a', 'suite')[1])
        self.assertEqual(self.status('a', 'sleep ms'), ('ERROR', 't:sleep(ms[, suite]) expects a number'))
        self.assertIn('expects suite to be a function', self.status('a', 'sleep suite')[1])

    # ------------------------------------------------------------- règle « une attente par étape »

    def test_one_wait_per_step(self):
        self.lua(r'''
        CONT = 0
        RST.suite("o", function(s)
            s.test("two waits", function(t)
                t:sleep(10, function() CONT = CONT + 1 end); t:waitUntil(function() return true end)
            end)
            s.test("assert after wait", function(t)
                t:waitUntil(function() return true end, 10, function() CONT = CONT + 1 end); t:eq(1, 1)
            end)
            s.test("fails after wait", function(t)
                t:sleep(10); t:fails(function() error("x") end)
            end)
            s.test("defer and skip after wait", function(t)
                t:sleep(10); t:defer(function() DEFERRED = true end); t:skip("later")
            end)
            s.test("error after wait wins", function(t)
                t:sleep(10, function() CONT = CONT + 1 end); error("boom", 0)
            end)
            s.test("next step may wait again", function(t)
                t:sleep(10, function(t2) t2:sleep(10, function(t3) t3:ok(true) end) end)
            end)
        end)''')
        self.start()
        self.run_to_end()
        self.assertEqual(self.status('o', 'two waits'),
                         ('ERROR', 't:waitUntil after t:sleep in the same step: one wait per step; put the rest in '
                                   'the continuation function'))
        self.assertEqual(self.status('o', 'assert after wait')[1],
                         't:eq after t:waitUntil in the same step: one wait per step; put the rest in the '
                         'continuation function')
        self.assertEqual(self.status('o', 'fails after wait')[0], 'ERROR')
        self.assertEqual(self.status('o', 'defer and skip after wait'), ('SKIP', 'later'))
        self.assertTrue(self.g.DEFERRED)
        self.assertEqual(self.status('o', 'error after wait wins'), ('ERROR', 'boom'))
        self.assertEqual(self.status('o', 'next step may wait again')[0], 'PASS')
        self.assertEqual(self.g.CONT, 0)  # aucune étape enregistrée avant l'erreur n'a tourné

    # ------------------------------------------------------------- erreurs dans une étape différée

    def test_errors_in_deferred_steps(self):
        self.lua(r'''RST.suite("y", function(s)
            s.test("error", function(t) t:sleep(100, function() error("late boom") end) end)
            s.test("assert", function(t) t:sleep(100, function(t2) t2:eq(1, 2) end) end)
            s.test("skip", function(t) t:sleep(100, function(t2) t2:skip("later") end) end)
            s.test("caught then real", function(t)
                pcall(function() t:ok(false) end); t:sleep(100, function() error("real", 0) end) end)
            s.test("cond error", function(t) t:waitUntil(function() error("cond boom", 0) end, 1000) end)
            s.test("cond assert", function(t) t:waitUntil(function() t:eq(1, 3) end, 1000) end)
            s.test("cond index nil", function(t) t:waitUntil(function() local x = nil; return x.y end, 1000) end)
            s.test("after all", function(t) t:sleep(1, function(t2) t2:ok(true) end) end)
        end)''')
        self.start()
        self.run_to_end()
        st, msg = self.status('y', 'error')
        self.assertEqual(st, 'ERROR')
        self.assertIn('late boom', msg)
        self.assertEqual(self.status('y', 'assert'), ('FAIL', 'expected 1, got 2'))
        self.assertEqual(self.status('y', 'skip'), ('SKIP', 'later'))
        self.assertEqual(self.status('y', 'caught then real'), ('ERROR', 'real'))
        self.assertEqual(self.status('y', 'cond error'), ('ERROR', 'waitUntil condition raised: cond boom'))
        self.assertEqual(self.status('y', 'cond assert'), ('FAIL', 'expected 1, got 3'))
        st, msg = self.status('y', 'cond index nil')
        self.assertEqual(st, 'ERROR')
        self.assertTrue(msg.startswith('waitUntil condition raised: '))
        self.assertEqual(self.status('y', 'after all')[0], 'PASS')

    def test_signal_object_comes_back_through_pcall(self):
        self.lua(r'''RST.suite("k", function(s)
            s.test("assert", function(t) t:sleep(100, function(t2) t2:eq(1, 2) end) end)
            s.test("skip", function(t) t:skip("no world") end)
            s.test("error", function(t) pcall(function() t:ok(false) end); error("real", 0) end)
            s.test("raw table", function(t) error({ code = 7 }) end)
        end)''')
        self.start()
        self.run_to_end()
        self.assertEqual(self.status('k', 'assert'), ('FAIL', 'expected 1, got 2'))
        self.assertEqual(self.status('k', 'skip'), ('SKIP', 'no world'))
        self.assertEqual(self.status('k', 'error'), ('ERROR', 'real'))
        st, msg = self.status('k', 'raw table')
        self.assertEqual(st, 'ERROR')
        self.assertTrue(msg.startswith('table'))

    def test_no_coroutine_in_the_engine(self):
        self.lua('coroutine = nil')
        self.lua(r'''RST.suite("c", function(s)
            s.test("x", function(t) t:sleep(10, function(t2) t2:waitUntil(function() return true end) end) end)
        end)''')
        self.assertTrue(self.start())
        self.run_to_end()
        self.assertEqual(self.status('c', 'x')[0], 'PASS')
        for path in LUA.rglob('*.lua'):
            code = '\n'.join(line.split('--', 1)[0] for line in path.read_text(encoding='utf-8').splitlines())
            self.assertNotIn('coroutine', code, path.name)

    def test_hooks_wait_in_steps(self):
        self.lua(r'''
        TRAIL = {}
        local function o(x) TRAIL[#TRAIL + 1] = x end
        RST.suite("h", function(s)
            s.before(function(t) o("b1"); t:sleep(100, function(t2) o("b2"); t2:waitUntil(function() return 7 end, 100,
                function(_, v) o("b3:" .. v) end) end) end)
            s.after(function(t) o("a1"); t:sleep(100, function() o("a2") end) end)
            s.after(function() o("a-next") end)
            s.test("x", function(t) o("body"); t:sleep(1, function(t2) o("body2"); t2:ok(true) end) end)
        end)''')
        self.start()
        self.run_to_end()
        self.assertEqual(self.status('h', 'x'), ('PASS', None))
        self.assertEqual(lua_list(self.g.TRAIL), ['b1', 'b2', 'b3:7', 'body', 'body2', 'a1', 'a2', 'a-next'])

    def test_failures_suite_ends_with_expected_statuses(self):
        self.lua(f'dofile([[{FAILURES_FILE.as_posix()}]])')
        self.assertEqual(lua_list(self.lua('local out = {} for i, e in ipairs(RST.list(nil, true)) do out[i] = e.name end '
                                           'return out')), [])
        self.assertTrue(self.start('"rst.failures"'))
        self.run_to_end()
        got = {test: st for _, test, st, _msg in self.results()}
        self.assertEqual(len(got), 13)
        for test, st in got.items():
            expected = test.split(' expected', 1)[0]
            if 'Java exception' in test:
                expected = 'SKIP'  # aucune classe Java sous lupa
            self.assertEqual(st, expected, test)
        self.assertEqual(self.status('rst.failures', 'ERROR expected: error() in a cleanup that waits')[1],
                         'cleanup waiting cleanup: deliberate error in a cleanup step')
        self.assertFalse(self.g.DONE.ok)

    def test_selfcheck_suites_are_opt_in(self):
        self.lua(r'''
        RST.suite("rst.failures", { tags = { "shared", "selfcheck" } }, function(s) s.test("f", function(t) t:ok(false) end) end)
        RST.suite("rst.selftest", { tags = { "shared" } }, function(s) s.test("p", function(t) t:ok(true) end) end)''')
        names = lambda flt: [e.name for _, e in self.lua(f'return RST.list({flt}, true)').items()]
        self.assertEqual(names('nil'), ['rst.selftest'])
        self.assertEqual(names('"rst"'), ['rst.selftest'])
        self.assertEqual(names('"rst."'), ['rst.selftest'])
        self.assertEqual(names('{ tags = "shared" }'), ['rst.selftest'])
        self.assertEqual(names('"rst.failures"'), ['rst.failures'])
        self.assertEqual(names('{ suite = { "rst", "rst.failures" } }'), ['rst.failures', 'rst.selftest'])
        self.assertEqual(names('{ tags = { "selfcheck" } }'), ['rst.failures'])
        self.assertEqual(names('{ suite = "rst.failures", exclude = "selfcheck" }'), [])

    def test_manual_suites_are_opt_in_on_their_own_tag(self):
        self.lua(r'''
        RST.suite("rs.id", { tags = { "server" } }, function(s) s.test("p", function(t) t:ok(true) end) end)
        RST.suite("rs.id.before", { tags = { "server", "manual" } }, function(s) s.test("p", function(t) t:ok(true) end) end)
        RST.suite("rst.failures", { tags = { "shared", "selfcheck" } }, function(s) s.test("f", function(t) t:ok(false) end) end)''')
        names = lambda flt: [e.name for _, e in self.lua(f'return RST.list({flt}, true)').items()]
        self.assertEqual(names('nil'), ['rs.id'])
        self.assertEqual(names('"rs"'), ['rs.id'])
        self.assertEqual(names('"rs.id"'), ['rs.id'])
        self.assertEqual(names('"rs.id.before"'), ['rs.id.before'])
        self.assertEqual(names('{ suite = "rs.id.before", tags = { "server", "shared" } }'), ['rs.id.before'])
        self.assertEqual(names('{ tags = "manual" }'), ['rs.id.before'])
        self.assertEqual(names('{ tags = "selfcheck" }'), ['rst.failures'], 'one opt-in tag opens only its suites')

    # ------------------------------------------------------------- délais

    def test_test_timeout_calls_after_and_continues(self):
        self.lua(r'''
        AFTER = 0
        RST.suite("t", function(s)
            s.after(function(t) AFTER = AFTER + 1 end)
            s.test("stuck", function(t) t:waitUntil(function() return false end) end, { timeoutMs = 1000 })
            s.test("default", function(t) t:sleep(60000) end)
            s.test("next", function(t) t:ok(true) end)
        end)''')
        self.start(opts='testTimeoutMs = 2000')
        self.run_to_end()
        self.assertEqual(self.status('t', 'stuck'), ('FAIL', 'timeout: test exceeded 1000 ms'))
        self.assertEqual(self.status('t', 'default'), ('FAIL', 'timeout: test exceeded 2000 ms'))
        self.assertEqual(self.status('t', 'next')[0], 'PASS')
        self.assertEqual(self.g.AFTER, 3)

    def test_default_test_timeout(self):
        self.assertEqual(self.lua('return RST.DEFAULT_TEST_TIMEOUT_MS'), 30000)
        self.assertEqual(self.lua('return RST.DEFAULT_SUITE_TIMEOUT_MS'), 120000)
        self.lua('RST.suite("t", function(s) s.test("stuck", function(t) t:sleep(10 ^ 9) end) end)')
        self.start()
        self.run_to_end(dt=1000)
        self.assertEqual(self.status('t', 'stuck'), ('FAIL', 'timeout: test exceeded 30000 ms'))

    def test_after_hook_timeout(self):
        self.lua(r'''RST.suite("t", function(s)
            s.after(function(t) t:sleep(10 ^ 9) end)
            s.test("x", function(t) t:ok(true) end, { timeoutMs = 500 })
        end)''')
        self.start()
        self.run_to_end()
        self.assertEqual(self.status('t', 'x'), ('FAIL', 'after: timeout: hook exceeded 500 ms'))

    def test_suite_timeout(self):
        self.lua(r'''
        AFTER = 0
        RST.suite("slow", { timeoutMs = 1500 }, function(s)
            s.after(function(t) AFTER = AFTER + 1 end)
            s.test("one", function(t) t:sleep(1000, function(t2) t2:ok(true) end) end)
            s.test("two", function(t) t:sleep(1000, function(t2) t2:ok(true) end) end)
            s.test("three", function(t) t:ok(true) end)
        end)
        RST.suite("fast", function(s) s.test("ok", function(t) t:ok(true) end) end)''')
        self.start()
        self.run_to_end()
        self.assertEqual(self.status('slow', 'one')[0], 'PASS')
        self.assertEqual(self.status('slow', 'two'), ('FAIL', "timeout: suite 'slow' exceeded 1500 ms"))
        self.assertEqual(self.status('slow', 'three'), ('FAIL', "timeout: suite 'slow' exceeded 1500 ms (not run)"))
        self.assertEqual(self.status('fast', 'ok')[0], 'PASS')
        self.assertEqual(self.g.AFTER, 2)

    def test_suite_timeout_from_start_opts(self):
        self.lua(r'''RST.suite("slow", function(s)
            s.test("one", function(t) t:sleep(10 ^ 9) end, { timeoutMs = 10 ^ 9 })
        end)''')
        self.start(opts='suiteTimeoutMs = 800')
        self.run_to_end()
        self.assertEqual(self.status('slow', 'one'), ('FAIL', "timeout: suite 'slow' exceeded 800 ms"))

    # ------------------------------------------------------------- passage unique, annulation, budget

    def test_second_start_refused(self):
        self.lua('RST.suite("a", function(s) s.test("x", function(t) t:sleep(500, function(t2) t2:ok(true) end) end) end)')
        self.assertTrue(self.start())
        ok, reason = self.lua('return RST.start(nil, { attach = false })')
        self.assertFalse(ok)
        self.assertEqual(reason, 'a run is already in progress')
        self.assertTrue(self.lua('return logged("start refused: a run is already in progress")'))
        self.run_to_end()
        self.assertEqual(self.lua('return DONE.total'), 1)
        self.assertTrue(self.start())  # de nouveau possible après la fin
        self.run_to_end()

    def test_start_with_bad_filter_refused(self):
        ok, reason = self.lua('return RST.start(42, { attach = false })')
        self.assertFalse(ok)
        self.assertIn('filter', reason)
        self.assertFalse(self.lua('return RST.running()'))

    def test_cancel(self):
        self.lua(r'''
        AFTER = 0
        RST.suite("c", function(s)
            s.after(function(t) AFTER = AFTER + 1 end)
            s.test("waiting", function(t) t:waitUntil(function() return false end) end)
            s.test("rest", function(t) t:ok(true) end)
        end)
        RST.suite("d", function(s) s.test("other", function(t) t:ok(true) end) end)''')
        self.start()
        self.tick()
        self.tick()
        self.assertTrue(self.lua('return RST.cancel()'))
        self.assertFalse(self.lua('return RST.running()'))
        self.assertIsNotNone(self.g.DONE)
        self.assertEqual(self.results(), [('c', 'waiting', 'SKIP', 'cancelled'), ('c', 'rest', 'SKIP', 'cancelled'),
                                          ('d', 'other', 'SKIP', 'cancelled')])
        self.assertEqual(self.g.AFTER, 1)
        ok, reason = self.lua('return RST.cancel()')
        self.assertFalse(ok)
        self.assertEqual(reason, 'no run in progress')

    def test_budget_spreads_sync_tests_over_ticks(self):
        self.lua(r'''RST.suite("b", function(s)
            for i = 1, 10 do s.test("t" .. i, function(t) CLOCK = CLOCK + 20; t:ok(true) end) end
        end)''')
        self.start()
        self.assertTrue(self.lua('return RST.step()'))
        done = self.lua('return #RST._run.report.results')
        self.assertGreater(done, 0)
        self.assertLess(done, 10)
        self.run_to_end(dt=0)
        self.assertEqual((self.g.DONE['pass'], self.g.DONE.total), (10, 10))

    def test_on_done_error_is_caught(self):
        self.lua('RST.suite("a", function(s) s.test("x", function(t) t:ok(true) end) end)')
        self.lua('RST.start(nil, { attach = false, onDone = function() error("boom") end })')
        self.assertFalse(self.lua('return RST.step()'))
        self.assertFalse(self.lua('return RST.running()'))
        self.assertTrue(self.lua('return logged("onDone failed")'))

    # ------------------------------------------------------------- événements de tick

    FAKE_EVENTS = r'''
    local function fakeEvent()
        local e = { handlers = {}, adds = 0, removes = 0 }
        e.Add = function(f) e.adds = e.adds + 1; e.handlers[#e.handlers + 1] = f end
        e.Remove = function(f)
            for i, h in ipairs(e.handlers) do if h == f then table.remove(e.handlers, i); e.removes = e.removes + 1; return end end
        end
        e.fire = function() local copy = {} for i, h in ipairs(e.handlers) do copy[i] = h end for _, h in ipairs(copy) do h() end end
        return e
    end
    Events = { OnTick = fakeEvent(), OnTickEvenPaused = fakeEvent() }
    '''

    def test_attach_ticks_idempotent_and_detached_at_end(self):
        self.lua(self.FAKE_EVENTS)
        self.lua('RST.suite("a", function(s) s.test("x", function(t) t:sleep(200, function(t2) t2:ok(true) end) end) end)')
        self.assertTrue(self.lua('return RST.attachTicks()'))
        self.assertTrue(self.lua('return RST.attachTicks()'))
        self.lua('package.loaded["RST/RST"] = nil; require "RST/RST"')  # rechargement du fichier
        self.assertTrue(self.lua('return RST.attachTicks()'))
        self.assertEqual(self.lua('return Events.OnTick.adds'), 1)
        self.assertTrue(self.lua('DONE = nil; return RST.start(nil, { onDone = function(r) DONE = r end })'))
        self.assertEqual(self.lua('return Events.OnTick.adds'), 1)
        self.assertEqual(self.lua('return Events.OnTickEvenPaused.adds'), 0)
        for _ in range(20):
            if self.g.DONE is not None:
                break
            self.lua('Events.OnTick.fire(); CLOCK = CLOCK + 100')
        self.assertIsNotNone(self.g.DONE)
        self.assertEqual(self.lua('return DONE["pass"]'), 1)
        self.assertEqual(self.lua('return #Events.OnTick.handlers'), 0)
        self.assertEqual(self.lua('return Events.OnTick.removes'), 1)
        self.assertFalse(self.lua('return RST.detachTicks()'))

    def test_attach_ticks_on_dedicated_server(self):
        self.lua(self.FAKE_EVENTS)
        self.lua('isServer = function() return true end')
        self.assertTrue(self.lua('return RST.attachTicks()'))
        self.assertEqual(self.lua('return Events.OnTickEvenPaused.adds'), 1)
        self.assertEqual(self.lua('return Events.OnTick.adds'), 0)
        self.assertTrue(self.lua('return RST.detachTicks()'))
        self.assertEqual(self.lua('return #Events.OnTickEvenPaused.handlers'), 0)
        self.lua('isServer = function() return false end')
        self.assertTrue(self.lua('return RST.attachTicks()'))
        self.assertEqual(self.lua('return Events.OnTick.adds'), 1)

    def test_attach_ticks_without_events(self):
        ok, reason = self.lua('Events = nil; return RST.attachTicks()')
        self.assertFalse(ok)
        self.assertEqual(reason, 'Events not available')

    def test_nothing_attached_at_load(self):
        self.lua(self.FAKE_EVENTS + 'package.loaded["RST/RST"] = nil; require "RST/RST"')
        self.assertEqual(self.lua('return Events.OnTick.adds + Events.OnTickEvenPaused.adds'), 0)
        self.assertFalse(self.lua('return RST.step()'))


FAKE_GAME = r"""
DEBUG = true
isDebugEnabled = function() return DEBUG end
getCore = function() return { getVersion = function(self) return "42.21.0 abcdef1234" end } end
MODS = { "batman_RadioSurvivor", "batman_RadioSurvivorTests" }
getActivatedMods = function()
    return { size = function(self) return #MODS end, get = function(self, i) return MODS[i + 1] end }
end
getWorld = function() return { getWorld = function(self) return "rstest-solo" end } end
BREAK = true
SETS = {}
UIManager = {
    isShowLuaDebuggerOnError = function() return BREAK end,
    setShowLuaDebuggerOnError = function(v) BREAK = v; SETS[#SETS + 1] = v end,
}
PLAYER = { name = "player0" }
getPlayer = function() return PLAYER end
HALO = nil
HaloTextHelper = {
    addGoodText = function(p, text) HALO = { kind = "good", player = p, text = text } end,
    addBadText = function(p, text) HALO = { kind = "bad", player = p, text = text } end,
}
WRITERS = {}
FILE_FAIL = nil
getFileWriter = function(name, createIfNull, append)
    if not string.find(name, "%.txt$") or string.find(name, "%.%.") then return nil end
    local full = FILE_ROOT .. "/" .. name
    mkdirs(full)
    local f = assert(io.open(full, append and "a" or "w"))
    local w = { name = name, createIfNull = createIfNull, append = append, closed = false, lines = 0 }
    function w:writeln(line)
        if FILE_FAIL then error(FILE_FAIL) end
        f:write(line, "\n"); self.lines = self.lines + 1
    end
    function w:close() f:close(); self.closed = true end
    WRITERS[#WRITERS + 1] = w
    return w
end
-- LuaManager.getFileReader(name, createIfNull): BufferedReader, nil when the file is missing (createIfNull false).
READERS = {}
getFileReader = function(name, createIfNull)
    if string.find(name, "%.%.") then return nil end
    local f = io.open(FILE_ROOT .. "/" .. name, "r")
    if not f then return nil end
    local r = { name = name, closed = false }
    function r:readLine() return f:read("*l") end
    function r:close() f:close(); self.closed = true end
    READERS[#READERS + 1] = r
    return r
end
"""


class ClientTests(LuaHarness):
    """Lanceur client RST_Client.lua (RST.run, fichier, Break On Error) et suite rst.selftest."""

    def setUp(self):
        super().setUp()
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.g.FILE_ROOT = self.root.as_posix()
        self.g.mkdirs = lambda full: Path(full).parent.mkdir(parents=True, exist_ok=True)
        self.lua(AsyncTests.FAKE_EVENTS)
        self.lua(FAKE_GAME)
        self.lua(f'dofile([[{SELFTEST_FILE.as_posix()}]])')
        self.lua(f'dofile([[{CLIENT_FILE.as_posix()}]])')

    def tearDown(self):
        self.tmp.cleanup()

    def tick(self, dt=100):
        self.lua(f'Events.OnTick.fire(); CLOCK = CLOCK + {dt}')

    def run_to_end(self, dt=100, limit=10000):
        for i in range(limit):
            if not self.lua('return RST.running()'):
                return i
            self.tick(dt)
        self.fail('le passage ne se termine pas')

    def report_files(self):
        folder = self.root / 'batman_RadioSurvivor' / 'tests'
        return sorted(folder.glob('*.txt')) if folder.is_dir() else []

    def names(self, flt):
        sel = self.lua(f'local out = {{}} for _, it in ipairs(RST.select(RST.Client.effectiveFilter({flt}))) do '
                       f'out[#out + 1] = it.suite.name end return table.concat(out, ",")')
        return sel.split(',') if sel else []

    # ------------------------------------------------------------- chargement

    def test_loading_runs_nothing(self):
        self.assertEqual(self.lua('return Events.OnTick.adds + Events.OnTickEvenPaused.adds'), 0)
        self.assertFalse(self.lua('return RST.running()'))
        self.assertEqual(self.lua('return #SETS'), 0)
        self.assertEqual(self.lua('return #WRITERS'), 0)
        self.assertEqual(self.lua('return #RST._suites'), 1)
        # rechargement des deux fichiers : pas de double enregistrement
        self.lua(f'dofile([[{SELFTEST_FILE.as_posix()}]]); dofile([[{CLIENT_FILE.as_posix()}]])')
        self.assertEqual(self.lua('return #RST._suites'), 1)
        self.assertEqual(self.lua('return Events.OnTick.adds'), 0)

    # ------------------------------------------------------------- refus

    def test_refused_outside_debug(self):
        ok, reason = self.lua('DEBUG = false; return RST.run("rst")')
        self.assertFalse(ok)
        self.assertIn('debug mode is off', reason)
        self.assertTrue(self.lua('return logged("run refused: debug mode is off")'))
        self.assertFalse(self.lua('return RST.running()'))
        self.assertEqual(self.lua('return #SETS'), 0)
        self.assertTrue(self.g.BREAK)
        self.assertEqual(self.report_files(), [])

    def test_refused_without_isDebugEnabled(self):
        ok, _ = self.lua('isDebugEnabled = nil; return RST.run()')
        self.assertFalse(ok)
        self.assertFalse(self.lua('return RST.running()'))

    def test_second_run_refused_and_debugger_stays_off(self):
        self.assertTrue(self.lua('return RST.run("rst")'))
        self.assertFalse(self.g.BREAK)
        ok, reason = self.lua('return RST.run("rst")')
        self.assertFalse(ok)
        self.assertIn('already in progress', reason)
        self.assertFalse(self.g.BREAK)  # le premier passage continue sans débogueur
        self.run_to_end()
        self.assertTrue(self.g.BREAK)
        self.assertEqual(list(self.g.SETS.values()), [False, True])

    # ------------------------------------------------------------- passage complet

    def test_run_selftest_writes_file_with_header(self):
        self.assertTrue(self.lua('return RST.run("rst")'))
        self.assertFalse(self.g.BREAK)
        self.assertTrue(self.lua('return logged("Break On Error switched off")'))
        self.run_to_end(dt=100)
        rep = self.lua('return RST._last')
        self.assertEqual((rep['pass'], rep.total, rep.ok), (6, 6, True))
        self.assertTrue(self.g.BREAK)
        files = self.report_files()
        self.assertEqual(len(files), 1)
        self.assertRegex(files[0].name, r'^\d{8}-\d{6}-solo\.txt$')
        text = files[0].read_text(encoding='utf-8').splitlines()
        self.assertTrue(text[0].startswith('RST report (batman_RadioSurvivorTests, RST '))
        self.assertIn('game version: 42.21.0 abcdef1234', text)
        self.assertIn('side: solo', text)
        self.assertIn('save: rstest-solo', text)
        self.assertIn('filter: "rst" -> {exclude={"server", "world"}, suite="rst"}', text)
        self.assertIn('active mods (2): batman_RadioSurvivor;batman_RadioSurvivorTests', text)
        self.assertTrue(any(re.match(r'^date \(UTC\): \d{8}-\d{6}$', line) for line in text))
        self.assertTrue(any(line.startswith('PASS   rst.selftest :: sleep 2 s measured by RST.now') for line in text))
        self.assertTrue(text[-1].startswith('OK - 6 test(s): 6 pass, 0 fail'))
        w = self.g.WRITERS[1]
        self.assertTrue(w.closed)
        self.assertTrue(w.createIfNull)
        self.assertFalse(w.append)
        self.assertEqual(w.name, 'batman_RadioSurvivor/tests/' + files[0].name)
        self.assertTrue(self.lua(f'return logged("report written: Zomboid/Lua/batman_RadioSurvivor/tests/'
                                 f'{files[0].name[:8]}")'))
        self.assertTrue(self.lua('return logged("%[RST%] OK %- 6 test")'))
        self.assertEqual((self.g.HALO.kind, self.g.HALO.text), ('good', 'RST OK: 6/6 pass, 0 fail, 0 error, 0 empty'))
        # RST.last : imprime les lignes du rapport et renvoie l'objet
        self.lua('LOGS = {}')
        self.assertTrue(self.lua('return RST.last() == RST._last'))
        self.assertTrue(self.lua('return logged("game version: 42.21.0")'))
        self.assertTrue(self.lua('return logged("file: Zomboid/Lua/batman_RadioSurvivor/tests/")'))

    def test_selftest_sleep_measured(self):
        self.assertTrue(self.lua('return RST.run({ suite = "rst.selftest", test = "^sleep" })'))
        self.run_to_end(dt=300)
        rep = self.lua('return RST._last')
        self.assertEqual((rep['pass'], rep.total), (1, 1))
        ms = rep.results[1].ms
        self.assertGreaterEqual(ms, 2000)
        self.assertLess(ms, 2400)

    def test_selftest_sleep_too_long_fails(self):
        # tick de 4 s : la durée mesurée dépasse la marge, l'auto-test doit le signaler
        self.assertTrue(self.lua('return RST.run({ suite = "rst.selftest", test = "^sleep" })'))
        self.run_to_end(dt=4000)
        self.assertEqual(self.lua('return RST._last.results[1].status'), 'FAIL')
        self.assertIn('more than 3500', self.lua('return RST._last.results[1].message'))

    def test_failing_run_shows_bad_text(self):
        self.lua('RST.suite("rst.bad", function(s) s.test("x", function(t) t:eq(1, 2) end) end)')
        self.assertTrue(self.lua('return RST.run("rst.bad")'))
        self.run_to_end()
        self.assertEqual(self.g.HALO.kind, 'bad')
        self.assertTrue(self.g.HALO.text.startswith('RST FAILED: 0/1 pass, 1 fail'))
        text = self.report_files()[0].read_text(encoding='utf-8')
        self.assertIn('FAIL   rst.bad :: x', text)

    def test_no_player_no_overhead_text(self):
        self.lua('PLAYER = nil')
        self.assertTrue(self.lua('return RST.run({ suite = "rst", test = "assertions" })'))
        self.run_to_end()
        self.assertIsNone(self.g.HALO)
        self.assertEqual(len(self.report_files()), 1)

    def test_client_side_in_file_name(self):
        self.lua('isClient = function() return true end')
        self.assertTrue(self.lua('return RST.run({ suite = "rst", test = "assertions" })'))
        self.run_to_end()
        self.assertRegex(self.report_files()[0].name, r'-client\.txt$')
        self.assertIn('side: client', self.report_files()[0].read_text(encoding='utf-8'))

    # ------------------------------------------------------------- Break On Error dans tous les chemins

    def test_debugger_left_alone_when_already_off(self):
        self.lua('BREAK = false')
        self.assertTrue(self.lua('return RST.run({ suite = "rst", test = "assertions" })'))
        self.run_to_end()
        self.assertEqual(self.lua('return #SETS'), 0)
        self.assertFalse(self.g.BREAK)

    def test_cancel_restores_debugger_and_writes_file(self):
        self.lua('RST.suite("rst.wait", function(s) s.test("never", function(t) '
                 't:waitUntil(function() return false end) end) end)')
        self.assertTrue(self.lua('return RST.run("rst.wait")'))
        self.tick()
        self.tick()
        self.assertFalse(self.g.BREAK)
        self.assertTrue(self.lua('return RST.cancel()'))
        self.assertFalse(self.lua('return RST.running()'))
        self.assertTrue(self.g.BREAK)
        text = self.report_files()[0].read_text(encoding='utf-8')
        self.assertIn('SKIP   rst.wait :: never', text)
        self.assertIn('cancelled', text)

    def test_launcher_error_restores_debugger(self):
        ok, reason = self.lua('RST.start = function() error("kaboom") end; return RST.run("rst")')
        self.assertFalse(ok)
        self.assertIn('launcher error', reason)
        self.assertIn('kaboom', reason)
        self.assertTrue(self.g.BREAK)
        self.assertEqual(list(self.g.SETS.values()), [False, True])
        self.assertIsNone(self.lua('return RST.Client.savedBreak'))

    def test_core_refusal_restores_debugger(self):
        ok, _ = self.lua('return RST.run(42)')
        self.assertFalse(ok)
        self.assertTrue(self.lua('return logged("start refused")'))
        self.assertTrue(self.g.BREAK)
        self.assertFalse(self.lua('return RST.running()'))

    def test_scheduler_failure_restores_debugger(self):
        self.assertTrue(self.lua('return RST.run({ suite = "rst", test = "assertions" })'))
        self.lua('RST._run.jobs[1] = 7')  # job corrompu : erreur de l'ordonnanceur
        self.run_to_end()
        self.assertTrue(self.g.BREAK)
        self.assertIn('(scheduler)', self.report_files()[0].read_text(encoding='utf-8'))

    def test_report_failure_after_restore(self):
        self.lua('getFileWriter = function() return nil end')
        self.assertTrue(self.lua('return RST.run({ suite = "rst", test = "assertions" })'))
        self.run_to_end()
        self.assertTrue(self.g.BREAK)
        self.assertTrue(self.lua('return logged("ERROR: report not written: getFileWriter refused")'))
        self.assertTrue(self.lua('return RST.last() == RST._last'))

    def test_write_error_still_closes_writer(self):
        self.lua('FILE_FAIL = "disk full"')
        self.assertTrue(self.lua('return RST.run({ suite = "rst", test = "assertions" })'))
        self.run_to_end()
        self.assertTrue(self.g.WRITERS[1].closed)
        self.assertTrue(self.lua('return logged("report not written: write failed: .*disk full")'))
        self.assertTrue(self.g.BREAK)

    # ------------------------------------------------------------- filtre par défaut

    def test_default_filter_excludes_server_and_world(self):
        self.lua(r'''
        RST.suite("x.server", { tags = { "server" } }, function(s) s.test("a", function(t) t:ok(true) end) end)
        RST.suite("x.world", { tags = { "world", "shared" } }, function(s) s.test("a", function(t) t:ok(true) end) end)
        RST.suite("x.plain", { tags = { "shared" } }, function(s) s.test("a", function(t) t:ok(true) end) end)
        ''')
        self.assertEqual(self.names('nil'), ['rst.selftest', 'x.plain'])
        self.assertEqual(self.names('"x"'), ['x.plain'])
        self.assertEqual(self.names('{ suite = "x" }'), ['x.plain'])
        self.assertEqual(self.names('{ suite = "x", tags = { "server", "world" } }'), ['x.server', 'x.world'])
        self.assertEqual(self.names('{ suite = "x", exclude = {} }'), ['x.server', 'x.world', 'x.plain'])
        self.assertEqual(self.names('{ suite = "x", exclude = "world" }'), ['x.server', 'x.plain'])
        self.assertTrue(self.lua('local f = { suite = "x" }; RST.Client.effectiveFilter(f); return f.exclude == nil'))
        # passage réel : seules les suites non exclues tournent
        self.assertTrue(self.lua('return RST.run("x")'))
        self.run_to_end()
        self.assertEqual(self.lua('return RST._last.total'), 1)
        self.assertEqual(self.lua('return RST._last.results[1].suite'), 'x.plain')

    def test_list_prints(self):
        self.lua('LOGS = {}; RST.list("rst")')
        self.assertTrue(self.lua('return logged("%[RST%] rst.selftest %[shared%] 6 test%(s%)")'))

    def test_last_before_any_run(self):
        self.assertIsNone(self.lua('return RST.last()'))
        self.assertTrue(self.lua('return logged("no report yet")'))

    # ------------------------------------------------------------- horodatage

    def test_stamp_from_os_date_and_fallback(self):
        from datetime import datetime, timezone
        self.assertRegex(self.lua('return RST.Client.stamp()'), r'^\d{8}-\d{6}$')
        for ms in (0, 951782400000, 1791460845123, 4102444799000):
            want = datetime.fromtimestamp(ms // 1000, tz=timezone.utc).strftime('%Y%m%d-%H%M%S')
            self.assertEqual(self.lua(f'return RST.Client.stampFromMs({ms})'), want, ms)
        self.lua('os = nil; CLOCK = 1791460845123')
        self.assertEqual(self.lua('return RST.Client.stamp()'), '20261008-120045')


# ----------------------------------------------------------------- E01-T05 : serveur + deux clients

NET_EVENTS = r"""
local function netEvent()
    local e = { handlers = {}, adds = 0 }
    e.Add = function(f) e.adds = e.adds + 1; e.handlers[#e.handlers + 1] = f end
    e.Remove = function(f)
        for i, h in ipairs(e.handlers) do if h == f then table.remove(e.handlers, i); return end end
    end
    e.fire = function(...) local copy = {} for i, h in ipairs(e.handlers) do copy[i] = h end
        for _, h in ipairs(copy) do h(...) end end
    return e
end
Events = { OnTick = netEvent(), OnTickEvenPaused = netEvent(), OnClientCommand = netEvent(),
    OnServerCommand = netEvent(), OnServerStarted = netEvent() }
"""

SERVER_GAME = r"""
isServer = function() return true end
isClient = function() return false end
Capability = { DebugConsole = "cap:DebugConsole" }
CONNECTIONS = {}   -- username -> role name, as UdpConnection.getRole() (absent = no connection)
ROLES = { admin = { ["cap:DebugConsole"] = true }, debugger = { ["cap:DebugConsole"] = true }, user = {} }
PLAYERS = {}       -- username -> server IsoPlayer (role copied at login, GameServer.java:2643)
ONLINE = {}        -- usernames online, in login order
function makeRole(name)
    return { name = name, hasCapability = function(self, cap) return ROLES[name][cap] == true end }
end
function login(name, role)
    CONNECTIONS[name] = role
    local p = { username = name, role = makeRole(role), connected = true }
    function p:getUsername() return self.username end
    function p:getRole() return self.role end
    PLAYERS[name] = p
    ONLINE[#ONLINE + 1] = name
    return p
end
function logout(name)
    CONNECTIONS[name] = nil
    PLAYERS[name].connected = false
    for i, n in ipairs(ONLINE) do if n == name then table.remove(ONLINE, i) break end end
end
-- LuaManager.checkPermissions: role of the CONNECTION; true when the connection is missing.
checkPermissions = function(player, cap)
    local role = player and CONNECTIONS[player.username]
    if role == nil then return true end
    return ROLES[role][cap] == true
end
getOnlinePlayers = function()
    local list = {}
    for i, n in ipairs(ONLINE) do list[i] = PLAYERS[n] end
    return { size = function(self) return #list end, get = function(self, i) return list[i + 1] end }
end
-- GameServer.sendServerCommand(player, ...): silently dropped when the player has no active connection.
sendServerCommand = function(player, module, command, args)
    if type(player) ~= "table" or not player.connected then return end
    PY_SERVER_SEND(player.username, module, command, args)
end
RAN = {}
"""

CLIENT_GAME = r"""
isServer = function() return false end
isClient = function() return true end
sendClientCommand = function(player, module, command, args) PY_CLIENT_SEND(player.name, module, command, args) end
"""

SERVER_SUITES = r"""
RST.suite("x.server", { tags = { "server" } }, function(s) s.test("a", function(t) RAN.server = true; t:ok(true) end) end)
RST.suite("x.client", { tags = { "client" } }, function(s) s.test("a", function(t) RAN.client = true; t:ok(true) end) end)
RST.suite("x.both", { tags = { "shared", "client" } }, function(s)
    s.test("a", function(t) RAN.both = true; t:ok(true) end) end)
RST.suite("x.world", { tags = { "world", "server" } }, function(s)
    s.test("a", function(t) RAN.world = true; t:ok(true) end) end)
RST.suite("x.untagged", function(s) s.test("a", function(t) RAN.untagged = true; t:ok(true) end) end)
"""


def to_py(value):
    """TableNetworkUtils : tables copiées récursivement, fonctions et autres objets ignorés sans erreur."""
    if lupa.lua_type(value) == 'table':
        out = {}
        for k, v in value.items():
            if isinstance(k, (str, int, float)) and not isinstance(k, bool):
                conv = to_py(v)
                if conv is not None:
                    out[k] = conv
        return out
    if isinstance(value, (str, int, float, bool)):
        return value
    return None


class Machine:
    """Une machine Lua (serveur, client ou solo) avec ses fichiers dans son propre dossier Zomboid/Lua."""

    def __init__(self, root: Path, game: str, files):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.rt.execute(PRELUDE)
        self.rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('getTimestampMs = function() return CLOCK end')
        root.mkdir(parents=True, exist_ok=True)
        self.root = root
        self.g.FILE_ROOT = root.as_posix()
        self.g.mkdirs = lambda full: Path(full).parent.mkdir(parents=True, exist_ok=True)
        self.rt.execute(NET_EVENTS)
        self.rt.execute(FAKE_GAME)
        self.rt.execute(game)
        self.rt.execute('require "RST/RST"')
        for f in files:
            self.lua(f if isinstance(f, str) else f'dofile([[{f.as_posix()}]])')

    def lua(self, code):
        return self.rt.execute(code)

    def table(self, data):
        if isinstance(data, dict):
            return self.rt.table_from({k: self.table(v) for k, v in data.items()})
        return data

    def files(self):
        folder = self.root / 'batman_RadioSurvivor' / 'tests'
        return sorted(folder.glob('*.txt')) if folder.is_dir() else []


class Network:
    """Un serveur dédié et des clients, chacun dans sa machine Lua ; commandes en file, copiées comme le réseau."""

    def __init__(self, root: Path):
        self.root = root
        self.queue = []
        self.server = Machine(root / 'server', SERVER_GAME, [SELFTEST_FILE, FAILURES_FILE, SERVER_SUITES, SERVER_FILE])
        self.server.g.PY_SERVER_SEND = lambda user, m, c, a: self.queue.append(('to_client', user, m, c, to_py(a)))
        self.clients = {}
        self.clock = 1000

    def add_client(self, name, role):
        c = Machine(self.root / name, CLIENT_GAME, [SELFTEST_FILE, FAILURES_FILE, CLIENT_FILE])
        c.lua(f'PLAYER = {{ name = "{name}" }}')
        c.g.PY_CLIENT_SEND = lambda user, m, cmd, a: self.queue.append(('to_server', user, m, cmd, to_py(a)))
        self.server.lua(f'login("{name}", "{role}")')
        self.clients[name] = c
        return c

    def pump(self):
        while self.queue:
            kind, user, module, command, args = self.queue.pop(0)
            if kind == 'to_server':
                if self.server.lua(f'return CONNECTIONS["{user}"] ~= nil'):
                    player = self.server.lua(f'return PLAYERS["{user}"]')
                    self.server.g.Events.OnClientCommand.fire(module, command, player, self.server.table(args))
            elif user in self.clients:
                c = self.clients[user]
                c.g.Events.OnServerCommand.fire(module, command, c.table(args))

    def tick(self, dt=100):
        self.pump()
        for m in [self.server, *self.clients.values()]:
            m.g.CLOCK = self.clock
        self.server.g.Events.OnTickEvenPaused.fire()
        self.clock += dt
        self.pump()

    def run_server_to_end(self, limit=1000):
        self.pump()
        for _ in range(limit):
            if not self.server.lua('return RST.running()'):
                self.pump()
                return
            self.tick()
        raise AssertionError('le passage serveur ne se termine pas')


class ServerTests(unittest.TestCase):
    """RST.server / RST_Server.lua : un serveur, deux clients (admin et joueur sans droit)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.net = Network(Path(self.tmp.name))
        self.admin = self.net.add_client('alice', 'admin')
        self.user = self.net.add_client('bob', 'user')

    def tearDown(self):
        self.tmp.cleanup()

    def logged(self, machine, pattern):
        return machine.lua(f'return logged([==[{pattern}]==])')

    def test_loading_subscribes_once_and_runs_nothing(self):
        s = self.net.server
        self.assertEqual(s.lua('return Events.OnClientCommand.adds'), 1)
        s.lua(f'dofile([[{SERVER_FILE.as_posix()}]])')
        self.assertEqual(s.lua('return Events.OnClientCommand.adds'), 1)
        self.assertEqual(s.lua('return Events.OnTickEvenPaused.adds + Events.OnTick.adds'), 0)
        self.assertEqual(self.admin.lua('return Events.OnServerCommand.adds'), 1)
        self.admin.lua(f'dofile([[{CLIENT_FILE.as_posix()}]])')
        self.assertEqual(self.admin.lua('return Events.OnServerCommand.adds'), 1)

    def test_user_without_right_is_denied_and_logged(self):
        self.assertTrue(self.user.lua('return RST.server()'))
        self.net.pump()
        self.assertFalse(self.net.server.lua('return RST.running()'))
        self.assertTrue(self.logged(self.net.server, "run DENIED for account 'bob': capability DebugConsole"))
        self.assertTrue(self.logged(self.user, 'server run #1 denied: permission denied'))
        self.assertEqual(self.net.server.files(), [])
        self.assertIsNone(self.admin.lua('return RST.Client.lastServerReport'))

    def test_role_checked_even_when_check_permissions_is_lenient(self):
        # checkPermissions renvoie true sans connexion (LuaManager.checkPermissions) : le rôle du joueur décide.
        s = self.net.server
        self.assertFalse(s.lua('CONNECTIONS["bob"] = nil; return RST.Server.allowed(PLAYERS["bob"])'))
        self.assertTrue(s.lua('return RST.Server.allowed(PLAYERS["alice"])'))
        self.assertTrue(s.lua('login("carol", "debugger"); return RST.Server.allowed(PLAYERS["carol"])'))
        self.assertFalse(s.lua('return RST.Server.allowed(nil)'))
        self.assertFalse(s.lua('Capability = nil; return RST.Server.allowed(PLAYERS["alice"])'))

    def test_admin_gets_summary_and_server_file(self):
        self.assertTrue(self.admin.lua('return RST.server()'))
        self.assertTrue(self.logged(self.admin, 'server run #1 requested'))
        self.net.pump()
        self.assertTrue(self.net.server.lua('return RST.running()'))
        self.assertTrue(self.logged(self.net.server, "run started by account 'alice'"))
        self.assertTrue(self.logged(self.admin, r'server run #1 started: 7 test%(s%)'))
        self.net.run_server_to_end()
        s = self.net.server
        self.assertEqual(s.lua('return RAN.server'), True)
        for tag in ('client', 'both', 'world', 'untagged'):
            self.assertIsNone(s.lua(f'return RAN.{tag}'), tag)
        rep = self.admin.lua('return RST.Client.lastServerReport')
        self.assertEqual((rep.ok, rep.total, rep['pass'], rep.id), (True, 7, 7, 1))
        self.assertTrue(rep.summary.startswith('OK - 7 test(s): 7 pass'))
        self.assertTrue(self.logged(self.admin, r'%[RST%] server report #1: OK %- 7 test'))
        self.assertEqual(self.admin.g.HALO.text, 'RST server OK: 7/7 pass, 0 fail, 0 error, 0 empty')
        files = s.files()
        self.assertEqual(len(files), 1)
        self.assertRegex(files[0].name, r'^\d{8}-\d{6}-server\.txt$')
        self.assertEqual(rep.file, 'batman_RadioSurvivor/tests/' + files[0].name)
        self.assertTrue(rep.written)
        self.assertNotIn(':', rep.file)  # aucun chemin absolu de la machine serveur
        text = files[0].read_text(encoding='utf-8').splitlines()
        self.assertIn('side: server', text)
        self.assertIn('requested by: alice', text)
        self.assertIn('filter: nil -> {exclude={"world", "client"}, tags={"server", "shared"}}', text)
        self.assertTrue(text[-1].startswith('OK - 7 test(s)'))
        self.assertEqual(self.admin.files(), [])  # rien d'écrit chez le client
        self.assertIsNone(self.user.lua('return RST.Client.lastServerReport'))  # seul le demandeur reçoit
        self.admin.lua('LOGS = {}')
        self.assertTrue(self.admin.lua('return RST.lastServer().id == 1'))
        self.assertTrue(self.logged(self.admin, 'server file: Zomboid/Lua/batman_RadioSurvivor/tests/'))

    def test_second_request_during_run_is_busy(self):
        self.assertTrue(self.admin.lua('return RST.server("rst")'))
        self.net.pump()
        carol = self.net.add_client('carol', 'admin')
        self.assertTrue(carol.lua('return RST.server("x")'))
        self.net.pump()
        self.assertTrue(self.logged(carol, 'server run #1 busy: a run is already in progress'))
        self.assertTrue(self.logged(self.net.server, "run refused for account 'carol': a run is already in progress"))
        self.assertTrue(self.admin.lua('return RST.server("x")'))  # le demandeur lui-même aussi
        self.net.pump()
        self.assertTrue(self.logged(self.admin, 'server run #2 busy'))
        self.net.run_server_to_end()
        self.assertEqual(self.admin.lua('return RST.Client.lastServerReport.id'), 1)
        self.assertIsNone(carol.lua('return RST.Client.lastServerReport'))
        self.assertEqual(len(self.net.server.files()), 1)

    def test_explicit_filter_keeps_client_suites_out(self):
        self.assertTrue(self.admin.lua('return RST.server({ suite = "x", tags = { "client", "shared", "world" } })'))
        self.net.run_server_to_end()
        s = self.net.server
        self.assertTrue(s.lua('return RAN.world'))
        self.assertIsNone(s.lua('return RAN.client'))
        self.assertIsNone(s.lua('return RAN.both'))
        self.assertEqual(s.lua('return RST.Server.effectiveFilter({ exclude = {} }).exclude[1]'), 'client')
        self.assertEqual(s.lua('local f = RST.Server.effectiveFilter({ exclude = { "client" } }) return #f.exclude'), 1)
        self.assertTrue(s.lua('local f = { suite = "x" }; RST.Server.effectiveFilter(f); return f.exclude == nil'))

    def test_function_in_filter_refused_locally(self):
        ok, reason = self.admin.lua('return RST.server({ suite = "x", test = function() end })')
        self.assertFalse(ok)
        self.assertIn("filter field 'test' must be a string, got function", reason)
        ok, reason = self.admin.lua('return RST.server({ tags = { "server", print } })')
        self.assertFalse(ok)
        self.assertIn('must only hold strings', reason)
        ok, reason = self.admin.lua('return RST.server({ sute = "x" })')
        self.assertFalse(ok)
        self.assertIn('unknown filter field', reason)
        self.assertFalse(self.admin.lua('return (RST.server(print))'))
        self.assertEqual(self.net.queue, [])
        self.assertTrue(self.logged(self.admin, 'run refused: filter cannot be sent to the server'))

    def test_server_revalidates_filter(self):
        # un client modifié envoie une table mal formée : le serveur refuse sans démarrer
        self.admin.lua('sendClientCommand(PLAYER, "RST", "run", { id = 9, filter = { tags = { a = "x" } } })')
        self.net.pump()
        self.assertFalse(self.net.server.lua('return RST.running()'))
        self.assertTrue(self.logged(self.admin, "server run #9 refused: filter field 'tags' must be a list"))
        alice = self.net.server.lua('return PLAYERS["alice"]')
        self.net.server.g.Events.OnClientCommand.fire('RST', 'run', alice, 7)
        self.assertTrue(self.net.server.lua('return RST.running()'))  # args non table : filtre nil, id absent

    def test_requester_disconnected_before_the_end(self):
        self.assertTrue(self.admin.lua('return RST.server("rst")'))
        self.net.pump()
        self.net.tick()
        self.net.server.lua('logout("alice")')
        self.net.run_server_to_end()
        s = self.net.server
        self.assertTrue(self.logged(s, "requester 'alice' is offline: report kept in the server file only"))
        self.assertEqual(len(s.files()), 1)
        self.assertIsNone(self.admin.lua('return RST.Client.lastServerReport'))
        self.assertFalse(s.lua('return RST.running()'))
        self.assertTrue(self.user.lua('return RST.server()'))  # le serveur reste utilisable
        self.net.pump()
        self.assertTrue(self.logged(self.user, 'denied'))

    def test_requester_reconnected_gets_report(self):
        self.assertTrue(self.admin.lua('return RST.server({ suite = "x.server" })'))
        self.net.pump()
        self.net.server.lua('logout("alice"); login("alice", "admin")')  # nouvel IsoPlayer, même compte
        self.net.run_server_to_end()
        self.assertEqual(self.admin.lua('return RST.Client.lastServerReport.total'), 1)

    def test_failure_lines_are_bounded(self):
        s = self.net.server
        s.lua(r'''
        RST.suite("x.many", { tags = { "server" } }, function(s)
            for i = 1, 55 do
                s.test("t" .. i, function(t) t:eq(1, 2, string.rep("long ", 200)) end)
            end
            s.test("empty", function(t) end)
        end)''')
        self.assertTrue(self.admin.lua('return RST.server("x.many")'))
        self.net.run_server_to_end()
        rep = self.admin.lua('return RST.Client.lastServerReport')
        self.assertEqual((rep.ok, rep.total, rep.fail, rep.empty), (False, 56, 55, 1))
        failures = list(rep.failures.values())
        self.assertEqual(len(failures), 40)
        self.assertEqual((rep.failuresTotal, rep.truncated), (56, True))
        self.assertTrue(all(len(line) <= 300 for line in failures))
        self.assertTrue(failures[0].startswith('FAIL  x.many :: t1 long long'))
        self.assertTrue(failures[0].endswith('...'))
        self.assertTrue(self.logged(self.admin, '16 more failure line%(s%) in the server file'))
        self.assertEqual(self.admin.g.HALO.kind, 'bad')
        text = s.files()[0].read_text(encoding='utf-8')
        self.assertIn('EMPTY  x.many :: empty', text)

    def test_file_not_written_still_reports(self):
        self.net.server.lua('getFileWriter = function() return nil end')
        self.assertTrue(self.admin.lua('return RST.server("x.server")'))
        self.net.run_server_to_end()
        rep = self.admin.lua('return RST.Client.lastServerReport')
        self.assertFalse(rep.written)
        self.assertIsNone(rep.file)
        self.assertTrue(self.logged(self.admin, 'server file: not written'))

    def test_client_refused_outside_debug(self):
        ok, reason = self.admin.lua('DEBUG = false; return RST.server()')
        self.assertFalse(ok)
        self.assertIn('debug mode is off', reason)
        self.assertEqual(self.net.queue, [])

    def test_client_and_server_runs_coexist_in_mp(self):
        self.assertTrue(self.admin.lua('return RST.run({ suite = "rst", test = "assertions" })'))
        self.assertTrue(self.admin.lua('return RST.server("x.server")'))
        self.net.run_server_to_end()
        self.assertEqual(self.admin.lua('return RST.Client.lastServerReport.total'), 1)
        self.assertTrue(self.admin.lua('return RST.running()'))  # le passage client continue de son côté


class AutorunTests(unittest.TestCase):
    """Passage automatique d'un serveur dédié : autorun.txt lu à OnServerStarted, autorun-result.txt écrit."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.net = Network(Path(self.tmp.name))
        self.s = self.net.server
        self.s.lua('getWorld = function() return { getWorld = function() return "rstest_smoke" end } end')
        self.tests_dir = self.s.root / 'batman_RadioSurvivor' / 'tests'

    def tearDown(self):
        self.tmp.cleanup()

    def write_autorun(self, text):
        self.tests_dir.mkdir(parents=True, exist_ok=True)
        path = self.tests_dir / 'autorun.txt'
        path.write_bytes(text.encode('utf-8'))
        return path

    def start_server(self):
        self.s.g.Events.OnServerStarted.fire()

    def result_lines(self):
        return (self.tests_dir / 'autorun-result.txt').read_text(encoding='utf-8').splitlines()

    def test_subscribed_once_and_nothing_without_file(self):
        self.assertEqual(self.s.lua('return Events.OnServerStarted.adds'), 1)
        self.s.lua(f'dofile([[{SERVER_FILE.as_posix()}]])')
        self.assertEqual(self.s.lua('return Events.OnServerStarted.adds'), 1)
        self.start_server()
        self.assertFalse(self.s.lua('return RST.running()'))
        self.assertEqual(self.s.lua('return Events.OnTickEvenPaused.adds'), 0)
        self.assertEqual(self.s.files(), [])
        self.assertFalse(self.tests_dir.exists())

    def test_autorun_runs_suites_and_writes_result(self):
        src = '# default smoke\n\nrst\n'
        path = self.write_autorun(src)
        self.start_server()
        self.assertTrue(self.s.lua('return RST.running()'))
        self.assertTrue(self.s.lua('return logged("autorun started from Zomboid/Lua/batman_RadioSurvivor/tests/'
                                   'autorun.txt")'))
        self.assertFalse((self.tests_dir / 'autorun-result.txt').exists())  # écrit à la fin seulement
        self.net.run_server_to_end()
        lines = self.result_lines()
        first = lines[0]
        self.assertRegex(first, r'^RST-RESULT ok=true total=6 pass=6 fail=0 error=0 skip=0 empty=0 '
                                r'durationMs=\d+ report=batman_RadioSurvivor/tests/\d{8}-\d{6}-server\.txt$')
        self.assertEqual(lines[-1], 'RST-END')
        self.assertIn('side: server', lines)
        self.assertIn('requested by: autorun.txt', lines)
        self.assertIn('save: rstest_smoke', lines)
        self.assertIn('filter: {suite={"rst"}} -> {exclude={"world", "client"}, suite={"rst"}, '
                      'tags={"server", "shared"}}', lines)
        self.assertTrue(lines[-2].startswith('OK - 6 test(s): 6 pass'))
        report = [f for f in self.s.files() if f.name.endswith('-server.txt')]
        self.assertEqual(len(report), 1)
        self.assertEqual(report[0].read_text(encoding='utf-8').splitlines(), lines[1:-1])
        self.assertEqual(path.read_bytes().decode('utf-8'), src)  # autorun.txt jamais modifié
        self.assertTrue(self.s.lua('return READERS[1].closed'))
        self.assertTrue(self.s.lua('for _, w in ipairs(WRITERS) do if w.append then return false end end '
                                   'return true'))
        self.assertTrue(self.s.lua('return RAN.server == nil'))  # x.server non demandé
        self.assertEqual(self.net.queue, [])  # aucun joueur : rien n'est envoyé

    def test_result_written_once(self):
        self.write_autorun('rst.selftest\n')
        self.start_server()
        self.net.run_server_to_end()
        self.assertEqual(self.s.lua('local n = 0 for _, w in ipairs(WRITERS) do '
                                    'if string.find(w.name, "autorun%-result") then n = n + 1 end end return n'), 1)
        self.start_server()  # second OnServerStarted (ou rechargement) : rien de plus
        self.s.lua(f'dofile([[{SERVER_FILE.as_posix()}]])')
        self.start_server()
        self.assertFalse(self.s.lua('return RST.running()'))
        self.assertEqual(self.s.lua('local n = 0 for _, w in ipairs(WRITERS) do '
                                    'if string.find(w.name, "autorun%-result") then n = n + 1 end end return n'), 1)
        self.assertEqual(len([f for f in self.s.files() if f.name.endswith('-server.txt')]), 1)

    def test_format_comments_blank_lines_and_several_suites(self):
        self.assertEqual(self.s.lua('return RST.Server.parseAutorun({ "", "  # c", "#", "   " })'), None)
        flt = self.s.lua('return RST.Server.parseAutorun({ " x.server ", "", "# rst", "rst.selftest\\r", "\\t" })')
        self.assertEqual(lua_list(flt.suite), ['x.server', 'rst.selftest'])
        ok, reason = self.s.lua('return RST.Server.parseAutorun({ "rst", "rs codec" })')
        self.assertFalse(ok)
        self.assertEqual(reason, "autorun.txt line 2: one suite name per line, got 'rs codec'")
        self.write_autorun('# comment\r\n x.server \r\n\r\n# rst\r\n')
        self.start_server()
        self.net.run_server_to_end()
        first = self.result_lines()[0]
        self.assertTrue(first.startswith('RST-RESULT ok=true total=1 pass=1 '), first)
        self.assertTrue(self.s.lua('return RAN.server == true'))

    def test_empty_file_runs_every_server_suite(self):
        self.write_autorun('# nothing but comments\n')
        self.start_server()
        self.net.run_server_to_end()
        self.assertTrue(self.result_lines()[0].startswith('RST-RESULT ok=true total=7 pass=7 '))

    def test_bad_file_and_no_selection_are_failures(self):
        self.write_autorun('rst\nrs codec\n')
        self.start_server()
        self.assertFalse(self.s.lua('return RST.running()'))
        self.assertEqual(self.result_lines(), [
            'RST-RESULT ok=false total=0 pass=0 fail=0 error=0 skip=0 empty=0 durationMs=0 '
            "reason=autorun.txt line 2: one suite name per line, got 'rs codec'", 'RST-END'])
        net = Network(Path(self.tmp.name) / 'second')
        net.server.lua('getWorld = function() return { getWorld = function() return "rstest_smoke" end } end')
        folder = net.server.root / 'batman_RadioSurvivor' / 'tests'
        folder.mkdir(parents=True)
        (folder / 'autorun.txt').write_text('nothing.here\n', encoding='utf-8')
        net.server.g.Events.OnServerStarted.fire()
        net.run_server_to_end()
        first = (folder / 'autorun-result.txt').read_text(encoding='utf-8').splitlines()[0]
        self.assertRegex(first, r'^RST-RESULT ok=false total=0 .* report=\S+ reason=no test selected$')

    def test_busy_server_writes_refusal(self):
        self.write_autorun('rst\n')
        self.s.lua('RST.start(nil, { attach = false })')
        self.start_server()
        first = self.result_lines()[0]
        self.assertTrue(first.startswith('RST-RESULT ok=false total=0 '), first)
        self.assertIn('reason=run not started: busy: a run is already in progress', first)

    def test_not_on_a_client_or_in_solo(self):
        self.write_autorun('rst\n')
        self.s.lua('isServer = function() return false end')
        self.start_server()
        self.assertFalse(self.s.lua('return RST.running()'))
        self.assertFalse((self.tests_dir / 'autorun-result.txt').exists())

    def test_failures_and_ctx_without_player(self):
        self.s.lua(f'dofile([[{FIXTURES_FILE.as_posix()}]])')
        self.s.lua(r"""
        CTX_SEEN = "unset"
        RST.suite("x.fx", { tags = { "server" } }, function(s)
            s.test("ctx", function(t) CTX_SEEN = t.ctx.player; t:eq("server", t.ctx.side) end)
            s.test("fixture", function(t) RST.Fixtures.giveItem(t, nil, "Base.Pencil") end)
            s.test("player", function(t) t:ok(RST.Fixtures.player(t) ~= nil, "no target player") end)
        end)""")
        self.write_autorun('x.fx\n')
        self.start_server()
        self.net.run_server_to_end()
        self.assertIsNone(self.s.g.CTX_SEEN)
        lines = self.result_lines()
        self.assertTrue(lines[0].startswith('RST-RESULT ok=false total=3 pass=1 fail=1 error=1 skip=0 empty=0 '),
                        lines[0])
        self.assertTrue(any(l.startswith('ERROR  x.fx :: fixture') and 'giveItem: no target player' in l
                            for l in lines))
        self.assertTrue(any(l.startswith('FAIL   x.fx :: player') and 'no target player' in l for l in lines))
        self.assertTrue(lines[-2].startswith('FAILED - 3 test(s)'))

    def test_world_suites_excluded_by_default(self):
        self.s.lua(f'dofile([[{FIXTURES_FILE.as_posix()}]]); dofile([[{FIXTURES_SUITE_FILE.as_posix()}]])')
        self.write_autorun('rst.fixtures\n')
        self.start_server()
        self.net.run_server_to_end()
        self.assertTrue(self.result_lines()[0].endswith('reason=no test selected'))

    def test_result_not_written_is_logged(self):
        self.write_autorun('rst.selftest\n')
        self.s.lua('getFileWriter = function() return nil end')
        self.start_server()
        self.net.run_server_to_end()
        self.assertFalse((self.tests_dir / 'autorun-result.txt').exists())
        self.assertTrue(self.s.lua('return logged("ERROR: autorun result not written: getFileWriter refused")'))


class SoloServerTests(unittest.TestCase):
    """Solo : RST.server exécute les suites serveur et partagées dans la même machine, sans réseau."""

    SOLO = r"""
    isServer = function() return false end
    isClient = function() return false end
    Capability = nil
    RAN = {}
    SENT = 0
    sendClientCommand = function() SENT = SENT + 1 end
    sendServerCommand = function() SENT = SENT + 1 end
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = Machine(Path(self.tmp.name), self.SOLO, [SELFTEST_FILE, FAILURES_FILE, SERVER_SUITES, CLIENT_FILE, SERVER_FILE])

    def tearDown(self):
        self.tmp.cleanup()

    def run_to_end(self, limit=1000):
        for _ in range(limit):
            if not self.m.lua('return RST.running()'):
                return
            self.m.lua('Events.OnTick.fire(); CLOCK = CLOCK + 100')
        self.fail('le passage ne se termine pas')

    def test_solo_runs_directly_without_network(self):
        self.assertTrue(self.m.lua('return RST.server()'))
        self.assertTrue(self.m.lua('return logged("server suites started in this game")'))
        self.assertFalse(self.m.g.BREAK)  # Break On Error coupé comme pour RST.run
        self.run_to_end()
        self.assertTrue(self.m.g.BREAK)
        self.assertEqual(self.m.lua('return SENT'), 0)
        self.assertTrue(self.m.lua('return RAN.server'))
        self.assertIsNone(self.m.lua('return RAN.client'))
        rep = self.m.lua('return RST.Client.lastServerReport')
        self.assertEqual((rep.ok, rep.total), (True, 7))
        files = self.m.files()
        self.assertEqual(len(files), 1)
        self.assertRegex(files[0].name, r'-server\.txt$')
        self.assertIn('side: solo (server suites, no network)', files[0].read_text(encoding='utf-8'))
        self.assertTrue(self.m.lua('return logged("server report #1: OK")'))

    def test_solo_run_and_server_share_one_run(self):
        self.assertTrue(self.m.lua('return RST.run("rst")'))
        ok, reason = self.m.lua('return RST.server()')
        self.assertFalse(ok)
        self.assertIn('already in progress', reason)
        self.run_to_end()
        self.assertTrue(self.m.lua('return RST.server("x.server")'))
        ok, reason = self.m.lua('return RST.run()')
        self.assertFalse(ok)
        self.assertIn('already in progress', reason)
        self.run_to_end()
        self.assertTrue(self.m.g.BREAK)
        self.assertEqual(self.m.lua('return RST.Client.lastServerReport.total'), 1)

    def test_solo_without_server_file(self):
        self.m.lua('RST.Server = nil')
        ok, reason = self.m.lua('return RST.server()')
        self.assertFalse(ok)
        self.assertIn('RST_Server.lua is not loaded', reason)


class InstallerTests(unittest.TestCase):
    def run_install(self, dest, dry_run=False):
        out = []
        code = install_tests.install(dest, dry_run=dry_run, out=out.append)
        return code, out

    def test_copy_then_replace_with_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'mods'
            code, _ = self.run_install(dest)
            target = dest / install_tests.MOD_ID
            self.assertEqual(code, 0)
            self.assertTrue((target / '42.21' / 'mod.info').is_file())
            self.assertTrue((target / '42.21/media/lua/shared/RST/RST.lua').is_file())
            self.assertTrue((target / 'common').is_dir())
            self.assertTrue((target / install_tests.MARKER).is_file())
            (target / 'stale.txt').write_text('old', encoding='utf-8')
            code, out = self.run_install(dest)
            self.assertEqual(code, 0)
            self.assertFalse((target / 'stale.txt').exists())
            self.assertTrue(any('remplacement' in line for line in out))

    def test_refuses_without_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / install_tests.MOD_ID
            target.mkdir()
            (target / 'mine.txt').write_text('keep', encoding='utf-8')
            code, out = self.run_install(Path(tmp))
            self.assertEqual(code, 2)
            self.assertTrue((target / 'mine.txt').is_file())
            self.assertIn('marqueur', out[-1])

    def test_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'mods'
            code, out = self.run_install(dest, dry_run=True)
            self.assertEqual(code, 0)
            self.assertFalse(dest.exists())
            self.assertTrue(any('RST.lua' in line for line in out))

    def test_refuses_steam_workshop(self):
        code, out = self.run_install(pz_paths.workshop_dir(), dry_run=True)
        self.assertEqual(code, 2)

    def test_cli_dry_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install_tests.py'), '--dest', tmp, '--dry-run'],
                                  capture_output=True, text=True, encoding='utf-8',
                                  env={**os.environ, 'PYTHONIOENCODING': 'utf-8'})
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(list(Path(tmp).iterdir()), [])


class ModInfoTests(unittest.TestCase):
    def test_mod_info(self):
        info = dict(line.split('=', 1) for line in (MOD / '42.21' / 'mod.info').read_text(encoding='utf-8').splitlines()
                    if '=' in line)
        self.assertEqual(info['id'], 'batman_RadioSurvivorTests')
        self.assertEqual(info['require'], '\\batman_RadioSurvivor')
        self.assertEqual(info['versionMin'], '42.21')
        self.assertIn('never publish', info['description'])
        self.assertTrue((MOD / 'common').is_dir())


# ----------------------------------------------------------------- E01-T06 : garde « partie de test », nettoyages, fixtures

FAKE_WORLD = r"""
SAVE = "rstest-solo"
getWorld = function() return { getWorld = function(self) return SAVE end } end
"""

# Faux monde : objets (id, type, conteneur), conteneurs Java (AddItem, Remove, getItemWithIDRecursiv...), joueur
# (position, mains, ceinture, vêtements, véhicule), cellule (cases chargées), réseau (envois comptés).
FAKE_ITEMS = r"""
EVENTS = {}
function ev(s) EVENTS[#EVENTS + 1] = s end
NEXT_ID = 100
KNOWN = { ["Base.Pencil"] = true, ["Base.Bag"] = true }
SENT_ADD, SENT_REMOVE, SERVER_CMDS, TELEPORTS = {}, {}, {}, {}
sendAddItemToContainer = function(c, item) SENT_ADD[#SENT_ADD + 1] = item:getID() end
sendRemoveItemFromContainer = function(c, item) SENT_REMOVE[#SENT_REMOVE + 1] = item:getID() end
sendServerCommand = function(p, module, command, args)
    SERVER_CMDS[#SERVER_CMDS + 1] = { player = p, module = module, command = command, args = args }
end
SendCommandToServer = function(cmd) TELEPORTS[#TELEPORTS + 1] = cmd end
triggerEvent = function(name, p) ev("event " .. name) end

local List = {}
List.__index = List
function List:size() return #self.t end
function List:get(i) return self.t[i + 1] end

local Container = {}
Container.__index = Container
function newContainer(name, holder)
    return setmetatable({ name = name, items = {}, holder = holder }, Container)
end
local Item = {}
Item.__index = Item
function newItem(fullType)
    NEXT_ID = NEXT_ID + 1
    local it = setmetatable({ id = NEXT_ID, fullType = fullType }, Item)
    if fullType == "Base.Bag" then it.inner = newContainer("bag" .. NEXT_ID, it) end
    return it
end
function Item:getID() return self.id end
function Item:getFullType() return self.fullType end
function Item:getContainer() return self.container end
function Container:getItems() return setmetatable({ t = self.items }, List) end
function Container:getContainingItem() return self.holder end
function Container:AddItem(x)
    local item = x
    if type(x) == "string" then
        if ADD_FAIL_AFTER and ADD_FAIL_AFTER <= 0 then return nil end
        if ADD_FAIL_AFTER then ADD_FAIL_AFTER = ADD_FAIL_AFTER - 1 end
        if not KNOWN[x] then return nil end
        item = newItem(x)
    end
    if item.container then item.container:Remove(item) end
    item.container = self
    self.items[#self.items + 1] = item
    ev("add " .. item.id .. " " .. self.name)
    return item
end
function Container:Remove(item)
    for i, it in ipairs(self.items) do
        if it == item then
            table.remove(self.items, i)
            item.container = nil
            ev("remove " .. item.id .. " " .. self.name)
            return
        end
    end
end
function Container:getItemWithIDRecursiv(id)
    for _, it in ipairs(self.items) do
        if it.id == id then return it end
        if it.inner then
            local found = it.inner:getItemWithIDRecursiv(id)
            if found then return found end
        end
    end
    return nil
end

function newPlayer(name, x, y, z)
    local p = { name = name, x = x, y = y, z = z, lx = x, ly = y, lz = z, hands = {}, worn = {}, attached = {} }
    p.inv = newContainer("inv-" .. name, nil)
    function p:getInventory() return self.inv end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    -- Case courante : celle de la position, ou celle figee par SQUARE_LAG (serveur : suit la position une mise a jour
    -- plus tard).
    function p:getCurrentSquare()
        local x, y = self.x, self.y
        if self.sqx ~= nil then x, y = self.sqx, self.sqy end
        return { getX = function() return math.floor(x) end, getY = function() return math.floor(y) end }
    end
    function p:setX(v) self.x = v; return v end
    function p:setY(v) self.y = v; return v end
    function p:setZ(v) self.z = v; return v end
    function p:setLastX(v) self.lx = v; return v end
    function p:setLastY(v) self.ly = v; return v end
    function p:setLastZ(v) self.lz = v; return v end
    function p:ensureNotInVehicle() if self.vehicle then ev("exit vehicle"); self.vehicle = nil end end
    function p:removeAttachedItem(item) if self.attached[item] then ev("unattach " .. item.id) end; self.attached[item] = nil end
    function p:isEquipped(item) return self.hands[item] ~= nil or self.worn[item] ~= nil end
    function p:removeFromHands(item) if self.hands[item] then ev("unhand " .. item.id) end; self.hands[item] = nil end
    function p:removeWornItem(item, drop) if self.worn[item] then ev("unwear " .. item.id) end; self.worn[item] = nil end
    function p:getUsername() return self.name end
    function p:isDead() return self.dead == true end
    function p:getVehicle() return self.vehicle end
    return p
end

FLOOR = newContainer("floor", nil)
LOADED = {}
function loadSquare(x, y, z) LOADED[math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)] = { x = x, y = y, z = z } end
CELL = { getGridSquare = function(self, x, y, z)
    return LOADED[math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)] end }
getCell = function() return CELL end
PLAYER = newPlayer("player0", 100.5, 200.5, 0)
getPlayer = function() return PLAYER end
isServer = function() return false end
isClient = function() return false end
isDebugEnabled = function() return true end
loadSquare(100, 200, 0)
loadSquare(102, 200, 0) -- F.spawnNpc target (player x + F.NPC_OFFSET): spawnNpc waits for it since 06fb147
loadSquare(103, 200, 0)
"""



class AsyncHarness(LuaHarness):
    """Environnement lupa + ordonnanceur piloté à la main (mêmes aides que AsyncTests, sans ses tests)."""

    start = AsyncTests.start
    tick = AsyncTests.tick
    run_to_end = AsyncTests.run_to_end
    FAKE_EVENTS = AsyncTests.FAKE_EVENTS


def lua_list(value):
    return [value[i] for i in range(1, len(value) + 1)] if value is not None else []


class GuardTests(AsyncHarness):
    """Garde « partie de test » : suites taguées world refusées hors partie rstest*."""

    WORLD_SUITES = r'''
    RAN = {}
    RST.suite("w.world", { tags = { "world", "shared" } }, function(s)
        s.before(function(t) RAN.before = true end)
        s.after(function(t) RAN.after = true end)
        s.test("a", function(t) RAN.a = true; t:ok(true) end)
        s.test("b", function(t) RAN.b = true; t:ok(true) end)
    end)
    RST.suite("w.plain", { tags = { "shared" } }, function(s) s.test("c", function(t) RAN.c = true; t:ok(true) end) end)
    '''

    def setUp(self):
        super().setUp()
        self.lua(FAKE_WORLD)
        self.lua(self.WORLD_SUITES)

    def test_normal_save_skips_world_suite_even_with_explicit_filter(self):
        self.lua('SAVE = "Ma partie"')
        for flt in ('nil', '"w"', '{ suite = "w.world", tags = "world" }', '"w.world"'):
            self.lua(f'RAN = {{}}; REPORT = RST.runSync({flt})')
            reason = "world suite refused: save 'Ma partie' is not a test save (rstest*)"
            self.assertEqual(self.status('w.world', 'a'), ('SKIP', reason), flt)
            self.assertEqual(self.status('w.world', 'b'), ('SKIP', reason), flt)
            self.assertIsNone(self.g.RAN.a)
            self.assertIsNone(self.g.RAN.before)  # aucun crochet exécuté
            self.assertIsNone(self.g.RAN.after)
        self.assertTrue(self.g.REPORT.ok)  # SKIP n'est pas un échec
        self.assertTrue(self.lua('return logged("world suite refused: save .Ma partie.")'))

    def test_plain_suite_still_runs_on_normal_save(self):
        self.lua('SAVE = "Ma partie"; REPORT = RST.runSync(nil)')
        self.assertEqual(self.status('w.plain', 'c')[0], 'PASS')

    def test_test_saves_run_world_suite_case_insensitive(self):
        for name in ('rstest-solo', 'RSTest_2', 'rstest'):
            self.lua(f'SAVE = "{name}"; RAN = {{}}; REPORT = RST.runSync("w")')
            self.assertEqual(self.status('w.world', 'a')[0], 'PASS', name)
            self.assertTrue(self.g.RAN.b)
        self.assertEqual(self.lua('return RST.worldGuard()'), True)

    def test_prefix_must_start_the_name(self):
        self.lua('SAVE = "my-rstest"; REPORT = RST.runSync("w.world")')
        self.assertEqual(self.status('w.world', 'a')[0], 'SKIP')

    def test_missing_name_is_a_refusal(self):
        cases = ('getWorld = nil', 'getWorld = function() return nil end',
                 'getWorld = function() error("no world") end', 'SAVE = ""', 'SAVE = nil')
        for code in cases:
            self.lua(FAKE_WORLD + code + '; REPORT = RST.runSync("w.world")')
            self.assertEqual(self.status('w.world', 'a'),
                             ('SKIP', 'world suite refused: save name unavailable (getWorld():getWorld())'), code)

    def test_guard_in_async_run(self):
        self.lua('SAVE = "Survie"')
        self.assertTrue(self.start('"w"'))
        self.run_to_end()
        self.assertEqual(self.status('w.world', 'a')[0], 'SKIP')
        self.assertEqual(self.status('w.plain', 'c')[0], 'PASS')
        self.assertIsNone(self.g.RAN.before)

    def test_guard_evaluated_once_per_plan(self):
        self.lua('CALLS = 0; getWorld = function() CALLS = CALLS + 1; return { getWorld = function() return "x" end } end')
        self.lua('RST.suite("w.world2", { tags = "world" }, function(s) s.test("d", function(t) t:ok(true) end) end)')
        self.lua('REPORT = RST.runSync("w")')
        self.assertEqual(self.g.CALLS, 1)
        self.assertEqual(self.status('w.world2', 'd')[0], 'SKIP')


class DeferTests(AsyncHarness):
    """t:defer : nettoyages après les crochets after, en ordre inverse, même après échec, délai ou annulation."""

    def setUp(self):
        super().setUp()
        self.lua('ORDER = {}; function o(s) ORDER[#ORDER + 1] = s end')

    def order(self):
        return lua_list(self.g.ORDER)

    def test_reverse_order_after_after_hooks(self):
        self.run_suites(r'''
        RST.suite("d", function(s)
            s.before(function(t) t:defer(function() o("c-before") end, "before") end)
            s.after(function(t) o("after"); t:defer(function() o("c-after") end) end)
            s.test("x", function(t)
                t:defer(function() o("c1") end, "one")
                t:defer(function() o("c2") end, "two")
                o("body"); t:ok(true)
            end)
        end)''')
        self.assertEqual(self.order(), ['body', 'after', 'c-after', 'c2', 'c1', 'c-before'])
        self.assertEqual(self.status('d', 'x')[0], 'PASS')

    def test_cleanup_runs_after_failure_and_error(self):
        self.run_suites(r'''
        RST.suite("d", function(s)
            s.test("fail", function(t) t:defer(function() o("c-fail") end); t:ok(false, "body") end)
            s.test("error", function(t) t:defer(function() o("c-error") end); error("boom") end)
            s.test("skip", function(t) t:defer(function() o("c-skip") end); t:skip("later") end)
        end)''')
        self.assertEqual(self.order(), ['c-fail', 'c-error', 'c-skip'])
        self.assertEqual(self.status('d', 'skip'), ('SKIP', 'later'))

    def test_cleanup_error_reported_others_still_run(self):
        self.run_suites(r'''
        RST.suite("d", function(s)
            s.test("x", function(t)
                t:defer(function() o("first") end, "first")
                t:defer(function() error("undo broke", 0) end, "broken")
                t:defer(function(tt) tt:ok(false, "undo check") end, "checked")
                t:ok(true)
            end)
            s.test("y", function(t) t:defer(function() error("again", 0) end, "z"); t:ok(false, "body") end)
        end)''')
        self.assertEqual(self.order(), ['first'])
        st, msg = self.status('d', 'x')
        self.assertEqual(st, 'FAIL')
        self.assertIn('cleanup checked: undo check', msg)
        self.assertIn('cleanup broken: undo broke', msg)
        st, msg = self.status('d', 'y')
        self.assertEqual(st, 'FAIL')
        self.assertIn('body', msg)
        self.assertIn('; cleanup z: again', msg)

    def test_defer_needs_a_function(self):
        self.run_suites('RST.suite("d", function(s) s.test("x", function(t) t:defer(42) end) end)')
        st, msg = self.status('d', 'x')
        self.assertEqual(st, 'ERROR')
        self.assertIn('expects a function', msg)

    def test_cleanup_after_timeout_and_cleanup_can_wait(self):
        self.lua(r'''
        RST.suite("d", { testTimeoutMs = 1000 }, function(s)
            s.test("slow", function(t)
                t:defer(function(tt)
                    o("c-start"); tt:sleep(300, function(t2)
                        o("c-slept"); t2:waitUntil(function() return true end, 100, function() o("c-last") end)
                    end)
                end, "waits")
                t:sleep(100000)
            end)
            s.test("next", function(t) o("next"); t:ok(true) end)
        end)''')
        self.assertTrue(self.start('"d"'))
        self.run_to_end()
        self.assertEqual(self.order(), ['c-start', 'c-slept', 'c-last', 'next'])
        st, msg = self.status('d', 'slow')
        self.assertEqual(st, 'FAIL')
        self.assertIn('timeout: test exceeded 1000 ms', msg)

    def test_cleanup_timeout_is_reported(self):
        self.lua(r'''
        RST.suite("d", { testTimeoutMs = 1000 }, function(s)
            s.test("x", function(t)
                t:defer(function() o("second") end, "second")
                t:defer(function(tt) tt:sleep(100000) end, "stuck")
                t:ok(true)
            end)
        end)''')
        self.assertTrue(self.start('"d"'))
        self.run_to_end()
        self.assertEqual(self.order(), ['second'])
        st, msg = self.status('d', 'x')
        self.assertEqual(st, 'FAIL')
        self.assertEqual(msg, 'cleanup stuck: timeout: hook exceeded 1000 ms')

    def test_cleanup_after_cancel(self):
        self.lua(r'''
        RST.suite("d", function(s)
            s.test("x", function(t) t:defer(function() o("cleaned") end); t:sleep(100000) end)
            s.test("y", function(t) o("y"); t:ok(true) end)
        end)''')
        self.assertTrue(self.start('"d"'))
        self.tick()
        self.tick()
        self.lua('RST.cancel()')
        self.run_to_end()
        self.assertEqual(self.order(), ['cleaned'])
        self.assertEqual(self.status('d', 'x'), ('SKIP', 'cancelled'))
        self.assertEqual(self.status('d', 'y'), ('SKIP', 'cancelled'))


class FixtureTests(AsyncHarness):
    """RST.Fixtures avec un faux joueur, un faux inventaire et une fausse cellule."""

    def setUp(self):
        super().setUp()
        self.lua(FAKE_WORLD)
        self.lua(NET_EVENTS)
        self.lua(FAKE_ITEMS)
        self.lua(f'dofile([[{FIXTURES_FILE.as_posix()}]])')
        self.lua('F = RST.Fixtures; CTX = { side = "solo", player = PLAYER }')

    def run_async(self, code, flt='"f"', ctx='CTX'):
        self.lua(code)
        self.assertTrue(self.start(flt, f'ctx = {ctx}'))
        self.run_to_end()

    def inv_ids(self, container='PLAYER.inv'):
        return lua_list(self.lua(f'local out = {{}} for i, it in ipairs({container}.items) do out[i] = it.id end '
                                 f'return out'))

    # ------------------------------------------------------------- objets

    def test_give_then_removed_by_cleanup(self):
        self.run_async(r'''
        RST.suite("f", { tags = "world" }, function(s)
            s.test("give", function(t)
                local items = F.giveItem(t, nil, "Base.Pencil", 3)
                GIVEN = items
                t:eq(3, #items)
                t:eq(3, PLAYER.inv:getItems():size())
            end)
            s.test("after", function(t) t:eq(0, PLAYER.inv:getItems():size()) end)
        end)''')
        self.assertEqual(self.status('f', 'give')[0], 'PASS')
        self.assertEqual(self.status('f', 'after')[0], 'PASS')
        self.assertEqual(self.inv_ids(), [])
        self.assertEqual(lua_list(self.g.SENT_ADD), [])  # solo : aucun envoi

    def test_give_removed_after_failure_and_after_timeout(self):
        self.run_async(r'''
        RST.suite("f", { testTimeoutMs = 1000 }, function(s)
            s.test("fails", function(t) F.giveItem(t, PLAYER, "Base.Pencil"); t:ok(false, "boom") end)
            s.test("times out", function(t) F.giveItem(t, PLAYER, "Base.Pencil", 2); t:sleep(100000) end)
            s.test("raises", function(t) F.giveItem(t, PLAYER, "Base.Pencil"); error("oops") end)
        end)''')
        self.assertEqual(self.status('f', 'fails')[0], 'FAIL')
        self.assertIn('timeout', self.status('f', 'times out')[1])
        self.assertEqual(self.status('f', 'raises')[0], 'ERROR')
        self.assertEqual(self.inv_ids(), [])

    def test_given_item_moved_into_a_bag_is_removed_moved_out_is_logged(self):
        self.lua('BAG = PLAYER.inv:AddItem("Base.Bag")')
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("x", function(t)
                local items = F.giveItem(t, PLAYER, "Base.Pencil", 3)
                BAG.inner:AddItem(items[1])          -- dans un sac porté : retiré quand même
                FLOOR:AddItem(items[2])              -- hors du joueur : laissé, signalé
                PLAYER.hands[items[3]] = true        -- en main : retiré des mains puis de l'inventaire
                MOVED = items[2].id
                t:ok(true)
            end)
        end)''')
        self.assertEqual(self.status('f', 'x')[0], 'PASS')
        self.assertEqual(self.inv_ids(), [self.lua('return BAG.id')])
        self.assertEqual(self.inv_ids('BAG.inner'), [])
        self.assertEqual(self.inv_ids('FLOOR'), [self.g.MOVED])
        self.assertTrue(self.lua(f'return logged("WARNING: giveItem cleanup: 1 item%(s%) no longer on the player, '
                                 f'left where they are: Base.Pencil#{self.g.MOVED}")'))
        self.assertIn('unhand', ' '.join(lua_list(self.g.EVENTS)))

    def test_give_unknown_type_errors_and_cleans_partial_adds(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("unknown", function(t) F.giveItem(t, PLAYER, "Base.Nope") end)
            s.test("no module", function(t) F.giveItem(t, PLAYER, "Pencil") end)
            s.test("bad count", function(t) F.giveItem(t, PLAYER, "Base.Pencil", 0) end)
            s.test("partial", function(t) ADD_FAIL_AFTER = 2; F.giveItem(t, PLAYER, "Base.Pencil", 5) end)
        end)''')
        st, msg = self.status('f', 'unknown')
        self.assertEqual(st, 'ERROR')
        self.assertIn("refused 'Base.Nope'", msg)
        self.assertIn("full type 'Module.Item'", self.status('f', 'no module')[1])
        self.assertIn('positive integer', self.status('f', 'bad count')[1])
        self.assertEqual(self.status('f', 'partial')[0], 'ERROR')
        self.assertEqual(self.inv_ids(), [])  # les 2 objets ajoutés avant l'erreur sont retirés

    def test_items_refused_on_mp_client(self):
        self.run_async(r'''
        isClient = function() return true end
        RST.suite("f", function(s)
            s.test("give", function(t) F.giveItem(t, PLAYER, "Base.Pencil") end)
        end)''')
        st, msg = self.status('f', 'give')
        self.assertEqual(st, 'ERROR')
        self.assertIn('need the authority', msg)
        self.assertEqual(self.inv_ids(), [])

    def test_server_sends_changes_to_the_owner(self):
        self.run_async(r'''
        isServer = function() return true end
        RST.suite("f", function(s)
            s.test("give", function(t) GIVEN = F.giveItem(t, nil, "Base.Pencil", 2); t:ok(true) end)
        end)''')
        ids = [self.lua(f'return GIVEN[{i}].id') for i in (1, 2)]
        self.assertEqual(lua_list(self.g.SENT_ADD), ids)
        self.assertEqual(sorted(lua_list(self.g.SENT_REMOVE)), sorted(ids))
        self.assertEqual(self.inv_ids(), [])

    def test_server_without_requester_has_no_target(self):
        self.run_async(r'''
        isServer = function() return true end
        RST.suite("f", function(s) s.test("give", function(t) F.giveItem(t, nil, "Base.Pencil") end) end)
        ''', ctx='{ side = "server" }')
        st, msg = self.status('f', 'give')
        self.assertEqual(st, 'ERROR')
        self.assertIn('no target player', msg)

    def test_remove_item_put_back_in_its_container(self):
        self.lua(r'''
        BAG = PLAYER.inv:AddItem("Base.Bag")
        KEEP = BAG.inner:AddItem("Base.Pencil")
        WORN = PLAYER.inv:AddItem("Base.Pencil")
        PLAYER.worn[WORN] = true
        PLAYER.attached[WORN] = true
        ''')
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("remove", function(t)
                F.removeItem(t, PLAYER, KEEP)
                F.removeItem(t, PLAYER, WORN)
                t:ok(PLAYER.inv:getItemWithIDRecursiv(KEEP.id) == nil)
                t:ok(PLAYER.inv:getItemWithIDRecursiv(WORN.id) == nil)
            end)
            s.test("not on player", function(t) F.removeItem(t, PLAYER, FLOOR:AddItem("Base.Pencil")) end)
        end)''')
        self.assertEqual(self.status('f', 'remove')[0], 'PASS')
        self.assertEqual(self.inv_ids('BAG.inner'), [self.lua('return KEEP.id')])
        self.assertIn(self.lua('return WORN.id'), self.inv_ids())
        events = ' '.join(lua_list(self.g.EVENTS))
        self.assertIn('unattach', events)
        self.assertIn('unwear', events)
        self.assertIn('is not on the player', self.status('f', 'not on player')[1])

    def test_remove_item_limits_are_logged(self):
        self.lua('A = PLAYER.inv:AddItem("Base.Pencil"); B = PLAYER.inv:AddItem("Base.Pencil")')
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("x", function(t)
                F.removeItem(t, PLAYER, A); PLAYER.inv:AddItem(A)     -- déjà revenu
                F.removeItem(t, PLAYER, B); FLOOR:AddItem(B)          -- parti ailleurs
                t:ok(true)
            end)
        end)''')
        self.assertTrue(self.lua('return logged("is already back on the player; nothing done")'))
        self.assertTrue(self.lua('return logged("WARNING: removeItem cleanup: Base.Pencil#%d+ is now in another container")'))
        self.assertEqual(self.inv_ids('FLOOR'), [self.lua('return B.id')])

    def test_remove_item_back_to_main_inventory_when_bag_is_gone(self):
        self.lua('BAG = PLAYER.inv:AddItem("Base.Bag"); KEEP = BAG.inner:AddItem("Base.Pencil")')
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("x", function(t) F.removeItem(t, PLAYER, KEEP); FLOOR:AddItem(BAG); t:ok(true) end)
        end)''')
        self.assertEqual(self.inv_ids(), [self.lua('return KEEP.id')])

    # ------------------------------------------------------------- position

    def test_move_player_solo_and_restored_after_failure(self):
        self.lua('PLAYER.vehicle = "car"')
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("move", function(t)
                local origin = F.movePlayer(t, nil, 103.5, 200.5, 0)
                t:eq({ x = 100.5, y = 200.5, z = 0 }, origin)
                t:eq({ 103.5, 200.5, 0, 103.5, 200.5, 0 }, { PLAYER.x, PLAYER.y, PLAYER.z, PLAYER.lx, PLAYER.ly, PLAYER.lz })
                t:ok(false, "fails after the move")
            end)
            s.test("check", function(t) t:eq({ 100.5, 200.5, 0 }, { PLAYER.x, PLAYER.y, PLAYER.z }) end)
        end)''')
        self.assertIn('fails after the move', self.status('f', 'move')[1])
        self.assertEqual(self.status('f', 'check')[0], 'PASS')
        self.assertEqual((self.g.PLAYER.lx, self.g.PLAYER.ly), (100.5, 200.5))
        self.assertIn('exit vehicle', lua_list(self.g.EVENTS))

    def test_move_player_solo_with_continuation(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("move", function(t)
                F.movePlayer(t, nil, 103.5, 200.5, 0, function(t2, origin)
                    T2 = RST._run.tick
                    t2:eq({ x = 100.5, y = 200.5, z = 0 }, origin)
                    t2:eq(103.5, PLAYER.x)
                end)
                T1 = RST._run.tick
            end)
            s.test("check", function(t) t:eq(100.5, PLAYER.x) end)
            s.test("bad suite", function(t) F.movePlayer(t, nil, 1, 2, 0, 42) end)
        end)''')
        self.assertEqual(self.status('f', 'move'), ('PASS', None))
        self.assertEqual(self.g.T1, self.g.T2)  # solo : déplacement immédiat, suite au même tick
        self.assertEqual(self.status('f', 'check')[0], 'PASS')
        self.assertEqual(self.status('f', 'bad suite'), ('ERROR', 'movePlayer: suite must be a function, got number'))

    def test_move_player_solo_with_continuation_needs_async(self):
        self.run_suites('RST.suite("f", function(s) s.test("x", function(t) '
                        'F.movePlayer(t, nil, 1, 2, 0, function() end) end) end)', '"f", CTX')
        st, msg = self.status('f', 'x')
        self.assertEqual(st, 'ERROR')
        self.assertIn('needs an asynchronous run', msg)

    def test_move_player_rejects_bad_coordinates(self):
        self.run_async('RST.suite("f", function(s) s.test("x", function(t) F.movePlayer(t, nil, 1, "2", 0) end) end)')
        st, msg = self.status('f', 'x')
        self.assertEqual(st, 'ERROR')
        self.assertIn('y must be a number', msg)
        self.assertEqual(self.g.PLAYER.x, 100.5)

    LOAD_AROUND = r'''
        function loadAround(x, y, z)
            local r = F.LOAD_RADIUS
            for _, d in ipairs({ { 0, 0 }, { -r, -r }, { r, -r }, { -r, r }, { r, r } }) do
                loadSquare(x + d[1], y + d[2], z)
            end
        end
        '''

    def test_move_player_on_server_asks_client_and_waits(self):
        self.lua(self.LOAD_AROUND + 'loadAround(103, 200, 0); loadAround(100, 200, 0)')
        self.lua(r'''
        isServer = function() return true end
        -- le client applique la demande deux ticks plus tard (/teleportto), le serveur voit la position ensuite
        sendServerCommand = function(p, module, command, args)
            SERVER_CMDS[#SERVER_CMDS + 1] = { module = module, command = command, args = args }
            PENDING = { p = p, args = args, ticks = 2 }
        end
        Events.OnTick.Add(function()
            if PENDING then
                PENDING.ticks = PENDING.ticks - 1
                if PENDING.ticks <= 0 then
                    PENDING.p.x, PENDING.p.y, PENDING.p.z = PENDING.args.x, PENDING.args.y, PENDING.args.z
                    PENDING = nil
                end
            end
        end)
        ''')
        self.lua(r'''
        RST.suite("f", function(s)
            s.test("move", function(t)
                F.movePlayer(t, PLAYER, 103.5, 200.5, 0, function(t2, origin)
                    t2:near(103.5, PLAYER.x, 0.01)
                    t2:eq(100.5, origin.x)
                end)
            end)
            s.test("back", function(t) t:near(100.5, PLAYER.x, 0.01) end)
            s.test("only wait", function(t) F.movePlayer(t, PLAYER, 103.5, 200.5, 0) end)
            s.test("assert after a move without continuation", function(t)
                F.movePlayer(t, PLAYER, 103.5, 200.5, 0); t:ok(true)
            end)
        end)''')
        self.assertTrue(self.start('"f"', 'ctx = CTX'))
        for _ in range(200):
            if not self.lua('return RST.running()'):
                break
            self.lua('RST.step(); Events.OnTick.fire(); CLOCK = CLOCK + 100')
        self.assertEqual(self.status('f', 'move')[0], 'PASS')
        self.assertEqual(self.status('f', 'back')[0], 'PASS')
        self.assertEqual(self.status('f', 'only wait'), ('EMPTY', 'no assertion'))  # l'attente n'est pas une assertion
        st, msg = self.status('f', 'assert after a move without continuation')
        self.assertEqual(st, 'ERROR')
        self.assertIn('t:ok after t:waitQuiet in the same step', msg)
        cmds = self.g.SERVER_CMDS
        self.assertEqual((cmds[1].module, cmds[1].command, cmds[1].args.x), ('RST', 'fx.move', 103.5))
        self.assertEqual(cmds[2].args.x, 100.5)

    def test_move_player_on_server_times_out(self):
        self.lua(self.LOAD_AROUND + 'loadAround(100, 200, 0)')
        self.run_async(r'''
        isServer = function() return true end
        RST.suite("f", function(s) s.test("move", function(t) F.movePlayer(t, PLAYER, 103.5, 200.5, 0) end) end)
        ''')
        st, msg = self.status('f', 'move')
        self.assertEqual(st, 'FAIL')
        # le joueur n'a jamais quitté l'origine : la remise en place réussit tout de suite
        self.assertEqual(msg, 'movePlayer: player did not reach 103.5,200.5,0 (or its squares not loaded): '
                              'condition not met within 20000 ms')
        self.assertEqual(self.g.SERVER_CMDS[2].args.x, 100.5)

    def _server_moves(self):
        # Le client applique chaque demande deux ticks plus tard ; les cases autour de la cible arrivent 5 ticks
        # apres la position du joueur (serveur : copie du joueur avant le chargement de ses chunks).
        self.lua(self.LOAD_AROUND + r'''
        isServer = function() return true end
        OTHER = newPlayer("player1", 90.5, 210.5, 0)
        getOnlinePlayers = function()
            local list = { PLAYER, OTHER }
            return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
        end
        function PLAYER:isDead() return false end
        function OTHER:isDead() return false end
        PENDING = {}
        sendServerCommand = function(p, module, command, args)
            SERVER_CMDS[#SERVER_CMDS + 1] = { p = p, module = module, command = command, args = args }
            PENDING[#PENDING + 1] = { p = p, args = args, ticks = 2 }
        end
        Events.OnTick.Add(function()
            local keep = {}
            for _, m in ipairs(PENDING) do
                m.ticks = m.ticks - 1
                if m.ticks == 0 then
                    m.p.sqx, m.p.sqy = m.p.x, m.p.y            -- case courante encore l'ancienne
                    m.p.x, m.p.y, m.p.z = m.args.x, m.args.y, m.args.z
                elseif m.ticks == -8 then
                    m.p.sqx, m.p.sqy = nil, nil
                elseif m.ticks == -5 then
                    if m.p == PLAYER then loadAround(math.floor(m.args.x), math.floor(m.args.y), m.args.z) end
                end
                if m.ticks > -9 then keep[#keep + 1] = m end
            end
            PENDING = keep
        end)
        ''')

    def _step_all(self):
        self.assertTrue(self.start('"f"', 'ctx = CTX'))
        for _ in range(400):
            if not self.lua('return RST.running()'):
                break
            self.lua('RST.step(); Events.OnTick.fire(); CLOCK = CLOCK + 100')

    def test_move_player_on_server_waits_for_the_squares(self):
        # MP 2026-10-14 : la suite suivante trouvait « square ... is not loaded » juste apres le retour du joueur.
        self._server_moves()
        self.lua(r'''
        RST.suite("f", function(s)
            s.test("move", function(t)
                F.movePlayer(t, PLAYER, 300.5, 200.5, 0, function(t2)
                    t2:ok(CELL:getGridSquare(300 + F.LOAD_RADIUS, 200 + F.LOAD_RADIUS, 0) ~= nil, "squares loaded")
                    t2:eq(300, PLAYER:getCurrentSquare():getX(), "current square of the player")
                end)
            end)
            s.test("back loaded", function(t)
                t:near(100.5, PLAYER.x, 0.01)
                t:ok(CELL:getGridSquare(100 - F.LOAD_RADIUS, 200 - F.LOAD_RADIUS, 0) ~= nil, "origin loaded")
                t:near(90.5, OTHER.x, 0.01)
            end)
        end)''')
        self._step_all()
        self.assertEqual(self.status('f', 'move')[0], 'PASS')
        self.assertEqual(self.status('f', 'back loaded')[0], 'PASS')
        self.assertEqual(len(lua_list(self.g.SERVER_CMDS)), 2)  # movePlayer : le second joueur ne bouge pas

    def test_move_players_moves_every_online_player(self):
        self._server_moves()
        self.lua(r'''
        RST.suite("f", function(s)
            s.test("move all", function(t)
                F.movePlayers(t, PLAYER, 300.5, 200.5, 0, function(t2, origin)
                    t2:near(300.5, PLAYER.x, 0.01)
                    t2:near(290.5, OTHER.x, 0.01)
                    t2:near(210.5, OTHER.y, 0.01)
                    t2:eq(100.5, origin.x)
                end)
            end)
            s.test("all back", function(t)
                t:near(100.5, PLAYER.x, 0.01)
                t:near(90.5, OTHER.x, 0.01)
                t:near(210.5, OTHER.y, 0.01)
            end)
        end)''')
        self._step_all()
        self.assertEqual(self.status('f', 'move all')[0], 'PASS')
        self.assertEqual(self.status('f', 'all back')[0], 'PASS')
        cmds = lua_list(self.g.SERVER_CMDS)
        self.assertEqual(len(cmds), 4)
        self.assertEqual(self.lua('return SERVER_CMDS[2].p == OTHER and SERVER_CMDS[2].args.x'), 290.5)

    def test_move_players_in_solo_moves_the_player_only(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("solo", function(t)
                F.movePlayers(t, PLAYER, 103.5, 200.5, 0, function(t2) t2:near(103.5, PLAYER.x, 0.01) end)
            end)
            s.test("back", function(t) t:near(100.5, PLAYER.x, 0.01) end)
        end)''')
        self.assertEqual(self.status('f', 'solo')[0], 'PASS')
        self.assertEqual(self.status('f', 'back')[0], 'PASS')

    # ------------------------------------------------------------- garde de position (MP 2026-10-15)

    def notes(self, suite, test):
        return lua_list(self.lua(f'for _, r in ipairs(RST.last().results) do if r.suite == "{suite}" and r.test == "{test}" '
                                 f'then return r.notes or {{}} end end return {{}}'))

    def test_guard_brings_back_a_player_left_elsewhere_by_a_world_test(self):
        # rs.worldradio laissait le joueur a cote de la voiture de test : 30 suites lk sautees ensuite.
        self.run_async(r'''
        RST.suite("f", { tags = "world" }, function(s)
            s.test("leaves", function(t) PLAYER.x, PLAYER.y = 140.5, 230.5; t:ok(true) end)
            s.test("small step kept", function(t) PLAYER.x = 101.5; t:ok(true) end)
            s.test("check", function(t) t:near(101.5, PLAYER.x, 0.01); t:near(200.5, PLAYER.y, 0.01) end)
        end)''')
        self.assertEqual(self.status('f', 'leaves')[0], 'PASS')
        self.assertEqual(self.status('f', 'check')[0], 'PASS')
        self.assertEqual(self.notes('f', 'leaves'),
                         ['position guard: player player0 left at 140,230,0 by the test, moved back to 100,200,0'])
        self.assertEqual(self.notes('f', 'small step kept'), [])

    def test_guard_runs_after_the_test_cleanups_and_after_a_failure(self):
        self.lua('PLAYER.vehicle = "car"')
        self.run_async(r'''
        RST.suite("f", { tags = "world" }, function(s)
            s.test("seat", function(t)
                t:defer(function() ORDER = (ORDER or "") .. "test;" end, "test cleanup")
                PLAYER.x = 150.5
                t:ok(false, "boom")
            end)
            s.test("check", function(t) t:near(100.5, PLAYER.x, 0.01) end)
        end)''')
        self.assertEqual(self.status('f', 'seat')[0], 'FAIL')
        self.assertEqual(self.status('f', 'check')[0], 'PASS')
        self.assertEqual(self.g.ORDER, 'test;')
        self.assertIn('exit vehicle', lua_list(self.g.EVENTS))

    def test_guard_left_out_of_suites_not_tagged_world(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("leaves", function(t) PLAYER.x = 140.5; t:ok(true) end)
            s.test("check", function(t) t:near(140.5, PLAYER.x, 0.01) end)
        end)''')
        self.assertEqual(self.status('f', 'check')[0], 'PASS')

    def test_guard_on_server_moves_back_every_online_player(self):
        self._server_moves()
        self.lua(r'''
        RST.suite("f", { tags = "world" }, function(s)
            s.test("leaves", function(t) OTHER.x = 60.5; t:ok(true) end)
            s.test("check", function(t) t:near(90.5, OTHER.x, 0.01); t:near(100.5, PLAYER.x, 0.01) end)
        end)''')
        self._step_all()
        self.assertEqual(self.status('f', 'check')[0], 'PASS')
        cmds = lua_list(self.g.SERVER_CMDS)
        self.assertEqual(len(cmds), 1)
        self.assertEqual(self.lua('return SERVER_CMDS[1].p == OTHER and SERVER_CMDS[1].args.x'), 90.5)

    def test_move_player_on_server_needs_async(self):
        self.lua('isServer = function() return true end')
        self.run_suites('RST.suite("f", function(s) s.test("x", function(t) F.movePlayer(t, PLAYER, 1, 2, 0) end) end)',
                        '"f", CTX')
        self.assertIn('needs an asynchronous run', self.status('f', 'x')[1])

    def test_client_handler_requests_teleport(self):
        self.lua('Events.OnServerCommand.fire("RST", "fx.move", { x = 103.5, y = 200.5, z = 0 })')
        self.lua('Events.OnServerCommand.fire("RST", "report", {})')
        self.lua('Events.OnServerCommand.fire("RST", "fx.move", { x = "a" })')
        self.assertEqual(lua_list(self.g.TELEPORTS), ['/teleportto 103.5,200.5,0'])
        self.lua('isDebugEnabled = function() return false end')
        self.lua('Events.OnServerCommand.fire("RST", "fx.move", { x = 1, y = 2, z = 0 })')
        self.assertEqual(len(lua_list(self.g.TELEPORTS)), 1)
        self.assertTrue(self.lua('return logged("move request ignored: debug mode is off")'))
        # rechargement du fichier : un seul abonnement
        self.lua(f'dofile([[{FIXTURES_FILE.as_posix()}]])')
        self.assertEqual(self.lua('return Events.OnServerCommand.adds'), 1)

    # ------------------------------------------------------------- cases

    def test_wait_square_success_and_timeout(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("loaded later", function(t)
                local n = 0
                getCell = function() n = n + 1; if n >= 3 then loadSquare(500, 500, 0) end; return CELL end
                F.waitSquare(t, 500.5, 500.5, 0, 5000, function(t2, sq) t2:eq(500, sq.x) end)
            end)
            s.test("never", function(t) F.waitSquare(t, 900, 900, 0, 2000) end)
            s.test("no cell", function(t) getCell = function() return nil end; F.waitSquare(t, 1, 1, 0, 500) end)
        end)''')
        self.assertEqual(self.status('f', 'loaded later')[0], 'PASS')
        self.assertEqual(self.status('f', 'never'),
                         ('FAIL', 'square 900,900,0 not loaded: condition not met within 2000 ms'))
        self.assertEqual(self.status('f', 'no cell')[0], 'FAIL')

    # ------------------------------------------------------------- ordre et erreurs

    def test_fixture_cleanups_in_reverse_order(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.before(function(t) F.giveItem(t, PLAYER, "Base.Pencil") end)
            s.test("x", function(t)
                F.movePlayer(t, PLAYER, 103.5, 200.5, 0)
                local it = F.giveItem(t, PLAYER, "Base.Pencil")[1]
                F.removeItem(t, PLAYER, it)
                EVENTS = {}
                t:ok(true)
            end)
        end)''')
        events = lua_list(self.g.EVENTS)
        # removeItem remet (add), giveItem du test retire, movePlayer remet la position, giveItem du before retire
        self.assertEqual([e.split(' ')[0] for e in events], ['add', 'remove', 'remove'])
        self.assertEqual(self.g.PLAYER.x, 100.5)
        self.assertEqual(self.inv_ids(), [])

    def test_failing_fixture_cleanup_does_not_stop_others(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("x", function(t)
                F.giveItem(t, PLAYER, "Base.Pencil")
                t:defer(function() error("broken undo", 0) end, "broken")
                F.movePlayer(t, PLAYER, 103.5, 200.5, 0)
                PLAYER.ensureNotInVehicle = function() error("vehicle API failed") end
                t:ok(true)
            end)
        end)''')
        st, msg = self.status('f', 'x')
        self.assertEqual(st, 'ERROR')
        self.assertIn('cleanup movePlayer back to 100.5,200.5,0: ', msg)
        self.assertIn('vehicle API failed', msg)
        self.assertIn('cleanup broken: broken undo', msg)
        self.assertEqual(self.inv_ids(), [])  # le nettoyage de giveItem a quand même eu lieu

    def test_fixtures_need_t(self):
        self.run_suites('RST.suite("f", function(s) s.test("x", function(t) F.giveItem(PLAYER, "Base.Pencil") end) end)')
        self.assertIn('first argument must be the test object t', self.status('f', 'x')[1])

    # ------------------------------------------------------------- suite en jeu rst.fixtures

    def test_fixtures_suite_passes_on_fake_world(self):
        self.lua(f'dofile([[{FIXTURES_SUITE_FILE.as_posix()}]])')
        self.lua('PLAYER.inv:AddItem("Base.Bag")')
        self.assertTrue(self.start('{ suite = "rst.fixtures", tags = "world" }', 'ctx = CTX'))
        self.run_to_end()
        results = self.results()
        self.assertEqual(len(results), 6)
        for suite, test, status, msg in results:
            self.assertEqual(status, 'PASS', f'{test}: {msg}')
        self.assertEqual((self.g.PLAYER.x, self.g.PLAYER.y), (100.5, 200.5))
        self.assertEqual(len(self.inv_ids()), 1)

    def test_fixtures_suite_skipped_on_normal_save(self):
        self.lua(f'dofile([[{FIXTURES_SUITE_FILE.as_posix()}]])')
        self.lua('SAVE = "Survie 1"')
        self.assertTrue(self.start('{ suite = "rst.fixtures", tags = "world" }', 'ctx = CTX'))
        self.run_to_end()
        results = self.results()
        self.assertEqual(len(results), 6)
        for _, _, status, msg in results:
            self.assertEqual((status, msg), ('SKIP', "world suite refused: save 'Survie 1' is not a test save (rstest*)"))
        self.assertEqual(self.inv_ids(), [])


class LauncherContextTests(unittest.TestCase):
    """Le joueur visé passe par t.ctx.player : getPlayer() côté client et solo, le demandeur côté serveur."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    CTX_SUITE = r"""
    SEEN = {}
    RST.suite("x.ctx", { tags = { "shared", "server" } }, function(s)
        s.test("a", function(t) SEEN[#SEEN + 1] = t.ctx.player; t:ok(true) end)
    end)
    """

    def test_client_run_and_solo_server_run_target_get_player(self):
        solo = r"""
        isServer = function() return false end
        isClient = function() return false end
        Capability = nil
        """
        m = Machine(Path(self.tmp.name), solo, [self.CTX_SUITE, CLIENT_FILE, SERVER_FILE])
        self.assertTrue(m.lua('return RST.run({ suite = "x.ctx", tags = "shared" })'))
        for _ in range(100):
            if not m.lua('return RST.running()'):
                break
            m.lua('Events.OnTick.fire(); CLOCK = CLOCK + 100')
        self.assertTrue(m.lua('return RST.server("x.ctx")'))
        for _ in range(100):
            if not m.lua('return RST.running()'):
                break
            m.lua('Events.OnTick.fire(); CLOCK = CLOCK + 100')
        self.assertTrue(m.lua('return #SEEN == 2 and SEEN[1] == PLAYER and SEEN[2] == PLAYER'))

    def test_server_run_targets_the_requester(self):
        net = Network(Path(self.tmp.name))
        net.server.lua(self.CTX_SUITE)
        admin = net.add_client('alice', 'admin')
        self.assertTrue(admin.lua('return RST.server("x.ctx")'))
        net.run_server_to_end()
        self.assertTrue(net.server.lua('return #SEEN == 1 and SEEN[1] == PLAYERS["alice"]'))

    def test_world_suite_refused_on_server_with_normal_name(self):
        net = Network(Path(self.tmp.name))
        net.server.lua('getWorld = function() return { getWorld = function() return "pzserver" end } end')
        admin = net.add_client('alice', 'admin')
        self.assertTrue(admin.lua('return RST.server({ suite = "x.world", tags = "world" })'))
        net.run_server_to_end()
        self.assertIsNone(net.server.lua('return RAN.world'))
        rep = admin.lua('return RST.Client.lastServerReport')
        self.assertEqual((rep.ok, rep.total, rep.skip), (True, 1, 1))
        text = net.server.files()[0].read_text(encoding='utf-8')
        self.assertIn("SKIP   x.world :: a (0 ms) world suite refused: save 'pzserver' is not a test save (rstest*)", text)


# E01-T10 : faux fournisseur RS_NPCProvider (même forme que le module publié) et fausse API de test Living Knox. Le
# corps apparaît dans objects() SEEN_AFTER appels après la création (0 = tout de suite).
FAKE_NPC = r"""
NPC = { bodies = {}, records = {}, next = 1, seenAfter = 0, calls = 0, removed = {}, refuse = nil, failRemove = nil }
local function newBody(x, y, z)
    local b = { x = x, y = y, z = z, dead = false }
    function b:getX() return self.x end
    function b:getY() return self.y end
    function b:getZ() return self.z end
    function b:isDead() return self.dead end
    return b
end
IMPL = { name = "livingknox", available = function() return true end }
function IMPL.objects()
    NPC.calls = NPC.calls + 1
    local out = {}
    for id, b in pairs(NPC.bodies) do if NPC.calls > b.visibleAt then out[id] = b end end
    return out
end
function IMPL.id(o) for id, b in pairs(NPC.bodies) do if rawequal(b, o) then return id end end return nil end
function IMPL.npc(id) return NPC.records[id] end
FAKE_PROVIDER = {
    active = function() return IMPL end,
    available = function() return IMPL.available() == true end,
    objects = function() return IMPL.objects() end,
    id = function(o) return IMPL.id(o) end,
    npc = function(id) return IMPL.npc(id) end,
}
package.loaded["RadioSurvivor/RS_NPCProvider"] = FAKE_PROVIDER
CELL.getZombieList = function() return { contains = function(_, b) return not b.dead end } end
LivingKnox = { API = {} }
function LivingKnox.API.testSpawnNpc(x, y, z)
    if NPC.refuse then return nil, NPC.refuse end
    local id = "lk-" .. NPC.next
    NPC.next = NPC.next + 1
    local b = newBody(x + 0.5, y + 0.5, z)
    b.visibleAt = NPC.calls + NPC.seenAfter
    NPC.bodies[id], NPC.records[id] = b, { signature = "lk:" .. id }
    NPC.last = { x = x, y = y, z = z }
    return id
end
function LivingKnox.API.testRemoveNpc(id)
    if NPC.failRemove then return false, NPC.failRemove end
    local b = NPC.bodies[id]
    if not b then return false, "npc " .. tostring(id) .. " was not created by testSpawnNpc" end
    b.dead = true
    NPC.bodies[id], NPC.records[id] = nil, nil
    NPC.removed[#NPC.removed + 1] = id
    return true, 1
end
function LivingKnox.API.testNpcs()
    local out = {}
    for id in pairs(NPC.bodies) do out[#out + 1] = id end
    table.sort(out)
    return out
end
"""

NPC_SUITE_FILE = LUA / 'shared' / 'RST' / 'suites' / 'RST_FixturesNpc.lua'


class NpcFixtureTests(AsyncHarness):
    """E01-T10 : F.spawnNpc par l'API de test de Living Knox, vu par RS_NPCProvider, retiré après le test."""

    def setUp(self):
        super().setUp()
        self.lua(FAKE_WORLD)
        self.lua(NET_EVENTS)
        self.lua(FAKE_ITEMS)
        self.lua(FAKE_NPC)
        self.lua(f'dofile([[{FIXTURES_FILE.as_posix()}]])')
        self.lua('F = RST.Fixtures; CTX = { side = "solo", player = PLAYER }')

    def run_async(self, code, flt='"f"', ctx='CTX'):
        self.lua(code)
        self.assertTrue(self.start(flt, f'ctx = {ctx}'))
        self.run_to_end()

    SPAWN_SUITE = r'''
    RST.suite("f", { tags = "world" }, function(s)
        s.test("spawn", function(t)
            local id0, body0 = F.spawnNpc(t, nil, function(t2, id, body)
                SEEN = { id = id, body = body, tick = RST._run.tick }
                t2:eq("lk-1", id)
                t2:eq(id, FAKE_PROVIDER.id(body))
            end)
            FIRST = { id = id0, body = body0, tick = RST._run.tick }
        end)
        s.test("after", function(t) t:eq(0, #LivingKnox.API.testNpcs()) end)
    end)'''

    def test_spawn_near_player_waits_for_provider_and_is_removed(self):
        self.lua('NPC.seenAfter = 3')
        self.run_async(self.SPAWN_SUITE)
        self.assertEqual(self.status('f', 'spawn'), ('PASS', None))
        self.assertEqual(self.status('f', 'after')[0], 'PASS')
        self.assertEqual((self.g.NPC.last.x, self.g.NPC.last.y, self.g.NPC.last.z), (102, 200, 0))
        self.assertEqual(self.g.FIRST.id, 'lk-1')
        self.assertIsNone(self.g.FIRST.body)  # pas encore vu par le fournisseur au retour
        self.assertGreater(self.g.SEEN.tick, self.g.FIRST.tick)  # suite appelée après l'attente
        self.assertEqual(lua_list(self.g.NPC.removed), ['lk-1'])
        self.assertTrue(self.g.SEEN.body.dead)
        self.assertTrue(self.lua('return logged("%[RST%] fixtures: npc lk%-1 spawned near 102,200,0")'))

    def test_spawn_without_suite_returns_the_seen_body(self):
        self.run_async(r'''
        RST.suite("f", function(s)
            s.test("x", function(t)
                local id, body = F.spawnNpc(t, PLAYER)
                t:eq("lk-1", id)
                t:ok(body ~= nil and FAKE_PROVIDER.id(body) == "lk-1")
            end)
        end)''')
        self.assertEqual(self.status('f', 'x'), ('PASS', None))
        self.assertEqual(lua_list(self.g.NPC.removed), ['lk-1'])

    def test_provider_never_sees_the_npc(self):
        self.lua('NPC.seenAfter = 1000000')
        self.run_async('RST.suite("f", function(s) s.test("x", function(t) '
                       'F.spawnNpc(t, nil, function(t2) t2:ok(true) end) end) end)')
        self.assertEqual(self.status('f', 'x'), ('FAIL', 'spawnNpc: npc lk-1 not seen by the NPC provider: '
                                                         'condition not met within 10000 ms'))
        self.assertEqual(lua_list(self.g.NPC.removed), ['lk-1'])  # retiré quand même

    def test_removed_after_failure(self):
        self.run_async('RST.suite("f", function(s) s.test("x", function(t) F.spawnNpc(t); t:ok(false, "boom") end) end)')
        self.assertEqual(self.status('f', 'x'), ('FAIL', 'boom: expected a true value, got false'))
        self.assertEqual(lua_list(self.g.NPC.removed), ['lk-1'])

    def refusal(self, setup, expected, ctx='CTX'):
        self.lua('NPC.next = 1; NPC.removed = {}')
        self.lua(setup)
        self.run_async('RST.suite("f", function(s) s.test("x", function(t) F.spawnNpc(t, nil) end) end)', ctx=ctx)
        st, msg = self.status('f', 'x')
        self.assertEqual(st, 'ERROR', setup)
        self.assertIn(expected, msg, setup)
        self.assertEqual(lua_list(self.g.NPC.removed), [], setup)

    def test_refusals_are_clear(self):
        self.refusal('package.loaded["RadioSurvivor/RS_NPCProvider"] = nil',
                     'spawnNpc: no NPC provider active (RS_NPCProvider not loaded)')
        self.refusal('package.loaded["RadioSurvivor/RS_NPCProvider"] = FAKE_PROVIDER; '
                     'IMPL.available = function() return false end; IMPL.name = "none"',
                     'spawnNpc: no NPC provider active (RS_NPCProvider: none)')
        self.refusal('IMPL.available = function() return true end; IMPL.name = "other"',
                     'spawnNpc: the active NPC provider is other, not Living Knox (livingknox)')
        self.refusal('IMPL.name = "livingknox"; SAVED_SPAWN = LivingKnox.API.testSpawnNpc; '
                     'LivingKnox.API.testSpawnNpc = nil',
                     'spawnNpc: Living Knox test API unavailable (LivingKnox.API.testSpawnNpc)')
        self.refusal('LivingKnox.API.testSpawnNpc = SAVED_SPAWN; NPC.refuse = "no free square"',
                     'spawnNpc: Living Knox refused the NPC at 102,200,0: no free square')
        self.refusal('NPC.refuse = nil; isClient = function() return true end',
                     'spawnNpc: needs the authority (solo or server), not an MP client')
        self.refusal('isClient = function() return false end; isServer = function() return true end',
                     'spawnNpc: no target player',
                     ctx='{ side = "server" }')

    def test_refused_outside_a_test_save(self):
        self.lua('SAVE = "Survie"')
        self.run_async('RST.suite("f", function(s) s.test("x", function(t) F.spawnNpc(t) end) end)')
        self.assertEqual(self.status('f', 'x'),
                         ('ERROR', "spawnNpc: world suites only: world suite refused: save 'Survie' is not a test "
                                   "save (rstest*)"))
        self.assertIsNone(self.g.NPC.last)

    def test_bad_suite_and_sync_run(self):
        self.run_async('RST.suite("f", function(s) s.test("x", function(t) F.spawnNpc(t, nil, 42) end) end)')
        self.assertEqual(self.status('f', 'x'), ('ERROR', 'spawnNpc: suite must be a function, got number'))
        self.run_suites('RST.suite("g", function(s) s.test("x", function(t) '
                        'F.spawnNpc(t, nil, function() end) end) end)', '"g", CTX')
        self.assertIn('needs an asynchronous run', self.status('g', 'x')[1])
        self.assertIsNone(self.g.NPC.last)  # refus avant toute création

    def test_failed_removal_is_a_cleanup_error(self):
        self.lua('NPC.failRemove = "registry unavailable"')
        self.run_async('RST.suite("f", function(s) s.test("x", function(t) F.spawnNpc(t); t:ok(true) end) end)')
        st, msg = self.status('f', 'x')
        self.assertEqual(st, 'ERROR')
        self.assertIn('cleanup remove test npc lk-1: spawnNpc cleanup: npc lk-1 not removed: registry unavailable', msg)

    def test_npc_ready(self):
        self.assertEqual(self.lua('return F.npcReady()'), True)
        self.lua('IMPL.name = "other"')
        self.assertEqual(self.lua('return F.npcReady()'),
                         (False, 'the active NPC provider is other, not Living Knox (livingknox)'))

    # ------------------------------------------------------------- suite en jeu rst.fixtures.npc

    def test_npc_suite_passes_on_fake_world(self):
        self.lua(f'dofile([[{NPC_SUITE_FILE.as_posix()}]])')
        self.lua('NPC.seenAfter = 2')
        self.assertTrue(self.start('{ suite = "rst.fixtures.npc", tags = "world" }', 'ctx = CTX'))
        self.run_to_end()
        results = self.results()
        self.assertEqual(len(results), 2)
        for _, test, status, msg in results:
            self.assertEqual(status, 'PASS', f'{test}: {msg}')
        self.assertEqual(lua_list(self.g.NPC.removed), ['lk-1'])

    def test_npc_suite_skipped_without_provider_and_on_normal_save(self):
        self.lua(f'dofile([[{NPC_SUITE_FILE.as_posix()}]])')
        self.lua('IMPL.available = function() return false end; IMPL.name = "none"')
        self.assertTrue(self.start('"rst.fixtures.npc"', 'ctx = CTX'))
        self.run_to_end()
        for _, _, status, msg in self.results():
            self.assertEqual((status, msg), ('SKIP', 'no NPC provider active (RS_NPCProvider: none)'))
        self.lua('SAVE = "Survie 1"')
        self.assertTrue(self.start('"rst.fixtures.npc"', 'ctx = CTX'))
        self.run_to_end()
        for _, _, status, msg in self.results():
            self.assertEqual((status, msg), ('SKIP', "world suite refused: save 'Survie 1' is not a test save (rstest*)"))
        self.assertIsNone(self.g.NPC.last)


if __name__ == '__main__':
    unittest.main(verbosity=2)
