"""Shared tools of the core mod batman_CoreAI (E18-T02).

    python RadioSurvivor/tests/test_core_tools.py

- one copy of each tool, as an CA_* module of the core mod (shared/CoreAI/), none left in RadioSurvivor;
- no old module name left in the code, the in-game suites, the benches or the tools (Living Knox included);
- files written by the code before the move (fixtures/e18-t02, written with the old RadioSurvivor codec) are read back
  by the moved codec and by the real readers (RS_State, LK_Store), and written again byte for byte (RSV2 unchanged).
"""
from __future__ import annotations

import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents' / 'mods'
CORE_LUA = MODS / 'batman_CoreAI' / '42.21' / 'media' / 'lua'
RS_LUA = MODS / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
FIXTURES = Path(__file__).resolve().parent / 'fixtures' / 'e18-t02'

TOOLS = ('Codec', 'RateLimit', 'TextCut', 'TradeValues', 'WorldStart', 'GameClock')
# Built by concatenation so that this file does not match its own search.
OLD_NAME = re.compile(r'\bRS' + r'_(' + '|'.join(TOOLS) + r')\b')
SCANNED = ('Contents', 'dev', 'tests', 'tools', 'bridge')
SKIPPED_PARTS = {'runs', '__pycache__', 'fixtures'}
SUFFIXES = {'.lua', '.py', '.ps1', '.json', '.txt', '.info'}


def scanned_files():
    for top in SCANNED:
        for path in (ROOT / top).rglob('*'):
            if path.is_file() and path.suffix in SUFFIXES and not SKIPPED_PARTS & set(path.relative_to(ROOT).parts):
                yield path


class LayoutTests(unittest.TestCase):
    def test_each_tool_lives_once_in_the_core(self):
        for tool in TOOLS:
            core = CORE_LUA / 'shared' / 'CoreAI' / f'CA_{tool}.lua'
            self.assertTrue(core.is_file(), core)
            copies = [p for p in MODS.rglob(f'*_{tool}.lua') if p != core]
            self.assertEqual(copies, [], f'second copy of {tool}')

    def test_no_old_name_left(self):
        hits = []
        for path in scanned_files():
            if path.resolve() == Path(__file__).resolve():
                continue
            text = path.read_text(encoding='utf-8', errors='replace')
            for n, line in enumerate(text.splitlines(), 1):
                if OLD_NAME.search(line):
                    hits.append(f'{path.relative_to(ROOT)}:{n}: {line.strip()[:100]}')
        self.assertEqual(hits, [])

    def test_living_knox_requires_no_radiosurvivor_tool(self):
        req = re.compile(r'require\s*\(?\s*["\']RadioSurvivor/RS_(' + '|'.join(TOOLS) + r')["\']')
        hits = [str(p.relative_to(ROOT)) for p in RS_LUA.rglob('LivingKnox/*.lua')
                if req.search(p.read_text(encoding='utf-8'))]
        self.assertEqual(hits, [])

    def test_core_lua_is_ascii(self):
        for path in CORE_LUA.rglob('*.lua'):
            self.assertTrue(path.read_bytes().isascii(), path)


class TradeValuesTests(unittest.TestCase):
    """E21-T06: an item of a mod (outside the Base module) is sold only once that mod registers its sale value."""

    def setUp(self):
        self.h = Harness(mode='mp')

    def tearDown(self):
        self.h.close()

    def test_sell_only_item_registered_by_its_mod(self):
        out = self.h.eval('server', '(function() local TV = require("CoreAI/CA_TradeValues") '
                                    'local before = TV.sellValue("SomeMod.Paper") '
                                    'TV.registerSellOnly("SomeMod.Paper", { v = 3, k = "supply", cap = 1 }) '
                                    'return before .. "|" .. TV.sellValue("SomeMod.Paper") .. "|" '
                                    '.. TV.value("SomeMod.Paper") .. "|" .. TV.SELL_ONLY["SomeMod.Paper"].cap end)()')
        self.assertEqual(out, '0|3|0|1')


class OldFilesTests(unittest.TestCase):
    """Files written by the pre-move code, read back and written again by the moved code."""

    def setUp(self):
        self.h = Harness(mode='mp')
        self.root = self.h.file_root('server')

    def tearDown(self):
        self.h.close()

    def lines(self, name):
        return (FIXTURES / name).read_bytes().decode('latin-1').split('\n')

    def put(self, name, dest):
        target = self.root / dest
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(FIXTURES / name, target)

    def codec_round_trip(self, name):
        _, raw, checksum, finish, _ = self.lines(name)
        self.assertEqual(finish, 'end')
        self.h.machine('server').g.RAW = raw
        ok = self.h.eval('server', '(function() local C = require("CoreAI/CA_Codec") '
                                   'local b = C.unhexBytes(RAW) local d = C.decodeBytes(b) '
                                   'return tostring(C.checksumBytes(b)) .. "|" .. C.hexOfBytes(C.encodeBytes(d)) end)()')
        sum_, again = ok.split('|')
        self.assertEqual(sum_, checksum)
        self.assertEqual(again, raw, 'RSV2 bytes changed')

    def test_codec_reads_and_rewrites_old_files(self):
        for name in ('rs-state-0.txt', 'lk-registry-0.txt'):
            with self.subTest(name=name):
                self.codec_round_trip(name)

    def test_rs_state_reader_reads_old_state(self):
        self.put('rs-state-0.txt', 'batman_RadioSurvivor/e18-old-0.txt')
        raw = self.lines('rs-state-0.txt')[1]
        out = self.h.eval('server', '(function() local S = require("RadioSurvivor/RS_State") '
                                    'local C = require("CoreAI/CA_Codec") '
                                    'local r = S._read("batman_RadioSurvivor/e18-old-0.txt") '
                                    'if not r then return "unread" end '
                                    'return r.generation .. "|" .. C.hexOfBytes(C.encodeBytes(r.data)) end)()')
        gen, again = out.split('|')
        self.assertEqual(gen, '7')
        self.assertEqual(again, raw)

    def test_lk_store_reads_old_registry(self):
        self.put('lk-registry-0.txt', 'batman_RadioSurvivor/livingknox/e18-old-0.txt')
        raw = self.lines('lk-registry-0.txt')[1]
        out = self.h.eval('server', '(function() require("LivingKnox/LK_Store") local St = LivingKnox.Store '
                                    'local C = require("CoreAI/CA_Codec") '
                                    'local r = St.readSlotFile("batman_RadioSurvivor/livingknox/e18-old-0.txt", "LKREG1") '
                                    'if not r then return "unread" end '
                                    'return r.seq .. "|" .. St.hexOfBytes(C.encodeBytes(r.data)) end)()')
        seq, again = out.split('|')
        self.assertEqual(seq, '3')
        self.assertEqual(again, raw)


if __name__ == '__main__':
    unittest.main()
