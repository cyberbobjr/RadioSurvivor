"""Server guards against a modified client (review points C21, C22, C31): RS_RateLimit.lua (per-account token
buckets of client commands) and RadioSurvivor_Const.oneLine (linear trim).

    python RadioSurvivor/tests/test_server_guards.py

Lua 5.1 through lupa with stub globals (isServer, getTimestampMs, print). Does not prove the cost in the Kahlua VM:
the trim keeps the same two patterns as the game (string.find), linear in both matchers.
"""
from __future__ import annotations

import re
import time
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'


def runtime(server=True):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute('NOW = 0; LOGS = {}; SERVER = ' + ('true' if server else 'false'))
    rt.execute('isServer = function() return SERVER end\n'
               'getTimestampMs = function() return NOW end\n'
               'print = function(s) LOGS[#LOGS + 1] = s end\n'
               'function PLAYER(name) return { getUsername = function() return name end } end')
    return rt


def load(rt, rel):
    return rt.execute(Path(LUA, rel).read_text(encoding='utf-8'))


class RateLimitTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.rt.globals().RL = load(self.rt, 'shared/RadioSurvivor/RS_RateLimit.lua')

    def allow(self, name='A', key='k', cap=3, rate=0.5):
        return self.rt.eval(f'RL.allow(PLAYER("{name}"), "{key}", {cap}, {rate})')

    def test_burst_then_refill(self):
        self.assertEqual([self.allow() for _ in range(5)], [True, True, True, False, False])
        self.rt.execute('NOW = 1999')
        self.assertFalse(self.allow())
        self.rt.execute('NOW = 2000')   # 0.5 per second: one token after 2 s
        self.assertTrue(self.allow())
        self.assertFalse(self.allow())
        self.rt.execute('NOW = 600000')  # a reconnection much later finds a full bucket, never more
        self.assertEqual([self.allow() for _ in range(4)], [True, True, True, False])

    def test_accounts_and_keys_are_independent(self):
        for _ in range(3):
            self.allow('A', 'k')
        self.assertFalse(self.allow('A', 'k'))
        self.assertTrue(self.allow('B', 'k'))
        self.assertTrue(self.allow('A', 'other'))

    def test_refusals_logged_once_per_window(self):
        for _ in range(50):
            self.allow()
        logs = list(self.rt.eval('LOGS').values())
        self.assertEqual(len(logs), 1)
        self.assertIn('rate limit', logs[0])
        self.assertIn(' from A', logs[0])
        self.rt.execute('NOW = 60000')
        for _ in range(40):
            self.allow()
        logs = list(self.rt.eval('LOGS').values())
        self.assertEqual(len(logs), 2)
        self.assertRegex(logs[1], r'dropped \d+ command')

    def test_clock_going_back_grants_nothing(self):
        self.rt.execute('NOW = 10000')
        for _ in range(3):
            self.allow()
        self.rt.execute('NOW = 5000')
        self.assertFalse(self.allow())

    def test_solo_is_never_limited(self):
        rt = runtime(server=False)
        rt.globals().RL = load(rt, 'shared/RadioSurvivor/RS_RateLimit.lua')
        self.assertTrue(all(rt.eval('RL.allow(PLAYER("A"), "k", 1, 0)') for _ in range(100)))


class OneLineTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.rt.execute('SandboxVars = {}; getText = function(k) return k end; getTextOrNull = function() end\n'
                        'Events = setmetatable({}, { __index = function() return { Add = function() end } end })')
        self.rt.globals().Const = load(self.rt, 'shared/RadioSurvivor/RadioSurvivor_Const.lua')

    def one(self, s):
        return self.rt.globals().Const.oneLine(s)

    def test_same_result_as_the_former_pattern(self):
        samples = ['', ' ', '   ', 'a', ' a ', '\t a\r\nb  ', 'a  b', '  x  y  z  ', '\n\n', 'é à b ', '\x0b a \x0c']
        for s in samples:
            expected = re.sub(r'[\r\n\t]', ' ', s)
            expected = re.sub(r'^[ \t\r\n\x0b\x0c]*', '', expected)
            expected = re.sub(r'[ \t\r\n\x0b\x0c]*$', '', expected)
            self.assertEqual(self.one(s), expected, repr(s))

    def test_long_runs_of_spaces_are_linear(self):
        text = ' ' * 100000 + 'x' + ' ' * 100000 + 'y' + ' ' * 100000
        start = time.perf_counter()
        out = self.one(text)
        self.assertLess(time.perf_counter() - start, 1.0)
        self.assertEqual(out, 'x' + ' ' * 100000 + 'y')


if __name__ == '__main__':
    unittest.main()
