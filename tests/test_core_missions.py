"""Mission engine of the core mod batman_RadioSurvivorCore (E18-T05).

    python RadioSurvivor/tests/test_core_missions.py

- one copy of the engine, of its templates (deliver, scout, clear, recover, retrieve_id, signal), of the site draw and
  of the caches, as RC_* modules of the core mod; none left in RadioSurvivor; old names gone from the code, the
  in-game suites, the benches and the tools; Living Knox requires no mission module of RadioSurvivor;
- the core mod requires Signal Smoke (template "signal", user decision of 2026-11-05);
- a giver registered without RadioSurvivor (no RadioSurvivor module loaded) offers, opens, closes and releases a
  mission through the same engine (registerDonor, hooks).
"""
from __future__ import annotations

import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents' / 'mods'
CORE = MODS / 'batman_RadioSurvivorCore' / '42.21'
CORE_LUA = CORE / 'media' / 'lua'
RS_LUA = MODS / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'

SERVER_MODULES = ('RC_Missions', 'RC_MissionStore', 'RC_MissionScout', 'RC_MissionClear', 'RC_MissionRecover',
                  'RC_MissionRetrieve', 'RC_MissionSignal', 'RC_Caches', 'RC_Sites')
SHARED_MODULES = ('RC_MissionConfig',)
MOVED = ('Missions', 'MissionScout', 'MissionClear', 'MissionRecover', 'MissionRetrieve', 'MissionSignal', 'Caches')
# Built by concatenation so that this file does not match its own search.
OLD_REQUIRE = re.compile(r'RadioSurvivor/RS' + r'_(' + '|'.join(MOVED) + r')\b')
OLD_WORD = re.compile(r'\bRS' + r'_(' + '|'.join(MOVED) + r')\b')
SCANNED = ('Contents', 'dev', 'tests', 'tools', 'bridge')
SKIPPED_PARTS = {'runs', '__pycache__', 'fixtures'}
SUFFIXES = {'.lua', '.py', '.ps1', '.json', '.txt', '.info'}

WORLD = ("getWorld = function() return {getGameMode = function() return 'Multiplayer' end, "
         "getWorld = function() return 'e18t05' end} end")


def scanned_files():
    for top in SCANNED:
        for path in (ROOT / top).rglob('*'):
            if path.is_file() and path.suffix in SUFFIXES and not SKIPPED_PARTS & set(path.relative_to(ROOT).parts):
                yield path


class LayoutTests(unittest.TestCase):
    def test_each_module_lives_once_in_the_core(self):
        for side, names in (('server', SERVER_MODULES), ('shared', SHARED_MODULES)):
            for name in names:
                path = CORE_LUA / side / 'RadioSurvivorCore' / f'{name}.lua'
                self.assertTrue(path.is_file(), path)
        for name in MOVED:
            self.assertEqual([p for p in MODS.rglob(f'RS_{name}.lua')], [], name)

    def test_no_old_name_left(self):
        hits = []
        for path in scanned_files():
            if path.resolve() == Path(__file__).resolve():
                continue
            in_mods = path.is_relative_to(MODS)
            text = path.read_text(encoding='utf-8', errors='replace')
            for n, line in enumerate(text.splitlines(), 1):
                if OLD_REQUIRE.search(line) or (in_mods and OLD_WORD.search(line)):
                    hits.append(f'{path.relative_to(ROOT)}:{n}: {line.strip()[:100]}')
        self.assertEqual(hits, [])

    def test_living_knox_requires_no_mission_module_of_radiosurvivor(self):
        req = re.compile(r'require\s*\(?\s*["\']RadioSurvivor/RS_(Mission\w*|NPCRewards|Caches|Rewards)["\']')
        hits = [str(p.relative_to(ROOT)) for p in RS_LUA.rglob('*.lua')
                if 'LivingKnox' in p.parts and req.search(p.read_text(encoding='utf-8'))]
        self.assertEqual(hits, [])

    def test_core_requires_signal_smoke(self):
        info = (CORE / 'mod.info').read_text(encoding='utf-8')
        line = next((l for l in info.splitlines() if l.startswith('require=')), '')
        self.assertIn('batman_SignalSmoke', line)

    def test_core_lua_is_ascii(self):
        for path in CORE_LUA.rglob('*.lua'):
            self.assertTrue(path.read_bytes().isascii(), path)


class StorageTests(unittest.TestCase):
    """Missions in the private file of the core mod, never in the notebook state."""

    def setUp(self):
        self.h = Harness(mode='mp')
        self.root = self.h.file_root('server')
        self.h.machine('server').rt.execute(WORLD)

    def tearDown(self):
        self.h.close()

    def ev(self, code):
        return self.h.eval('server', '(function() ' + code + ' end)()')

    def restart(self):
        """New server machine on the same files (fresh Lua, as after a server restart)."""
        files = self.root
        h2 = Harness(mode='mp')
        shutil.rmtree(h2.file_root('server'), ignore_errors=True)
        shutil.copytree(files, h2.file_root('server'))
        self.h.close()
        self.h = h2
        self.root = h2.file_root('server')
        self.h.machine('server').rt.execute(WORLD)

    def seed(self):
        self.ev('local S = require("RadioSurvivor/RS_State") assert(S.init(true)) '
                'S.data.missions["m-1"] = {id = "m-1", npc = "npc-a"} assert(S.save())')

    def test_saved_in_the_core_file_and_read_after_a_restart(self):
        self.seed()
        self.restart()
        self.assertEqual(self.ev('local S = require("RadioSurvivor/RS_State") assert(S.init(false)) '
                                 'return S.data.missions["m-1"].npc'), 'npc-a')

    def test_notebook_state_holds_no_mission(self):
        self.seed()
        out = self.ev('local S = require("RadioSurvivor/RS_State") '
                      'local r0 = S._read(S.path .. "-0.txt") local r1 = S._read(S.path .. "-1.txt") '
                      'local best = r0 if r1 and (not r0 or r1.generation > r0.generation) then best = r1 end '
                      'return tostring(best.data.missions)')
        self.assertEqual(out, 'nil')

    def test_new_world_starts_without_missions(self):
        self.seed()
        self.restart()
        out = self.ev('local S = require("RadioSurvivor/RS_State") S.init(true) local n = 0 '
                      'for _ in pairs(S.data.missions) do n = n + 1 end return n')
        self.assertEqual(out, 0)


PROBE = r"""
local M = require('RadioSurvivorCore/RC_Missions')
local MC = require('RadioSurvivorCore/RC_MissionConfig')
MC.Missions.probe = {id = 'probe_v1', titleKey = 'IGUI_RC_Probe', durationMs = 1000, rewardType = 'Base.Nails',
    rewardCount = 3}
M.register('probe', {idPrefix = 'probe',
    offer = function(c) return {durationMs = c.durationMs} end,
    create = function(m) m.count = 0 end,
    check = function(m, player, payload) if payload == 'ok' then return {n = 1} end return nil, 'Items' end,
    prepare = function() return {kind = 'probe'} end,
    apply = function() end,
    progress = function(m, e) m.count = m.count + e.n return e.n, true end,
    project = function(m, p) p.count = m.count end,
    context = function(m, ctx) ctx.count = m.count end})
GIVERS = {['lk:1'] = {id = 'lk:1', name = 'Ruth'}}
STATE = {missions = {}}
RESULTS = {}
M.registerDonor('lknpc', {find = function(state, id) return GIVERS[id] end})
M.addResultListener(function(state, m, result, character, requester)
    RESULTS[#RESULTS + 1] = m.id .. ':' .. result .. ':' .. character .. ':' .. tostring(requester)
end)
STORE = {data = STATE, save = function() return true end}
"""


class GiverWithoutRadioSurvivorTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp')
        self.h.machine('server').rt.execute(SIGNAL_SMOKE)
        self.h.machine('server').rt.execute(PROBE)

    def tearDown(self):
        self.h.close()

    def ev(self, code):
        return self.h.eval('server', '(function() ' + code + ' end)()')

    def test_offer_accept_report_release(self):
        out = self.ev(
            'local M = require("RadioSurvivorCore/RC_Missions") local g = GIVERS["lk:1"] '
            'local offers = M.offers(g, {hostile = false}, nil, "c1") '
            'if not offers.probe_v1 then return "no offer" end '
            'local m = M.create(STATE, g, "c1", "probe_v1", offers.probe_v1) '
            'm.donor = "lknpc" '
            'if not M.accept(STATE, m, "c1", "Alice") then return "not accepted" end '
            'local ok, why = M.report(STORE, m, nil, "c1", "ok", "t1") '
            'return table.concat({m.id, m.state, tostring(ok), tostring(g.mission), '
            'tostring(g.nextOfferHour ~= nil), tostring(M.offerWait(g)), RESULTS[1] or "-"}, "|")')
        self.assertEqual(out, 'lk:1-probe1|success|true|nil|true|true|lk:1-probe1:success:c1:Ruth')

    def test_no_radiosurvivor_module_loaded(self):
        self.ev('local M = require("RadioSurvivorCore/RC_Missions") '
                'for _, n in ipairs({"RC_MissionScout", "RC_MissionClear", "RC_MissionRecover", '
                '"RC_MissionRetrieve", "RC_MissionSignal", "RC_Caches", "RC_Sites", "RC_MissionStore"}) do '
                'require("RadioSurvivorCore/" .. n) end')
        loaded = self.ev('local out = {} for k in pairs(package.loaded) do '
                         'if string.find(k, "^RadioSurvivor/") or string.find(k, "^LivingKnox/") then '
                         'out[#out + 1] = k end end table.sort(out) return table.concat(out, ",")')
        self.assertEqual(loaded, '')


if __name__ == '__main__':
    unittest.main()
