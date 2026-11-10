"""Reputation kept by the core mod (E18-T22, user decision of 2026-11-06).

    python RadioSurvivor/tests/test_core_reputation.py

RC_Reputation (core mod, authority): one reputation per character, one private file
Zomboid/Lua/batman_RadioSurvivorCore/reputation-<world>-<0|1>.txt (RC_SlotFile, header RCREP1); same rules as before
(tests/test_reputation.py). Each mod reports its own facts: the common mission engine its results (with or without
RadioSurvivor), Living Knox the death of a group member (LK_Reputation), RadioSurvivor the cheated trade and the
killed requester.
"""
from __future__ import annotations

import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, CORE_LUA  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents' / 'mods'
LK_LUA = MODS / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'
RS_LUA = MODS / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
WORLD = ("getWorld = function() return {getGameMode = function() return setmetatable({}, {__tostring = function() return 'Multiplayer' end}) end, "
         "getWorld = function() return 'e18t22' end} end")
WORLD_HEX = '4d756c7469706c617965722f653138743232'


class Base(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp')
        self.root = self.h.file_root('server')
        self.h.machine('server').rt.execute(WORLD)

    def tearDown(self):
        self.h.close()

    def ev(self, code):
        return self.h.eval('server', '(function() ' + code + ' end)()')

    def score(self, character):
        return self.ev(f'return require("RadioSurvivorCore/RC_Reputation").scoreOf("{character}")')

    def restart(self):
        """New Lua state of the same server on the same files (modules and globals reset)."""
        self.ev('package.loaded["RadioSurvivorCore/RC_Reputation"] = nil RC_Reputation = nil '
                'package.loaded["RadioSurvivorCore/RC_Identity"] = nil RC_Identity = nil '
                'package.loaded["RadioSurvivor/RS_State"] = nil')

    def identity(self, character, owner, retired=False):
        """Character known to the identity registry of the core mod (as RC_Identity.bind writes it)."""
        flag = 'true' if retired else 'nil'
        self.ev('local I = require("RadioSurvivorCore/RC_Identity") assert(I.ensure()) '
                f'I.state.data.characters["{character}"] = {{owner = "{owner}", slot = 1, retired = {flag}}} I.save()')


class ModuleTests(unittest.TestCase):
    def test_one_copy_in_the_core_ascii(self):
        core = CORE_LUA / 'server' / 'RadioSurvivorCore'
        for name in ('RC_Reputation.lua', 'RC_ReputationEvents.lua'):
            self.assertTrue((core / name).read_bytes().isascii(), name)
        self.assertTrue((CORE_LUA / 'shared' / 'RadioSurvivorCore' / 'RC_ReputationConfig.lua').read_bytes().isascii())
        self.assertFalse((RS_LUA / 'server' / 'RadioSurvivor' / 'RS_Reputation.lua').exists())
        old = re.compile(r'RadioSurvivor/RS_Reputation|RS_Reputation\.lua')
        for base in ('Contents', 'dev', 'tests', 'tools', 'bridge'):
            for path in (ROOT / base).rglob('*'):
                if path.suffix in ('.lua', '.py') and path.name != Path(__file__).name:
                    self.assertIsNone(old.search(path.read_text(encoding='utf-8', errors='replace')), str(path))

    def test_living_knox_reports_through_the_core_only(self):
        text = (LK_LUA / 'server' / 'LivingKnox' / 'LK_Reputation.lua').read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'require\s*\(?\s*"([^"]+)"', text),
                         ['RadioSurvivorCore/RC_Reputation', 'RadioSurvivorCore/RC_Identity'])
        self.assertTrue(text.isascii())

    def test_core_mod_reports_no_text_of_another_mod(self):
        text = (CORE_LUA / 'server' / 'RadioSurvivorCore' / 'RC_Reputation.lua').read_text(encoding='utf-8')
        self.assertNotIn('IGUI_RS_', re.sub(r'--\[==\[.*?\]==\]', '', text, flags=re.S))


class StorageTests(Base):
    def test_recorded_saved_and_read_again_after_a_restart(self):
        self.identity('c-ann', 'ann')
        self.ev('local R = require("RadioSurvivorCore/RC_Reputation") assert(R.init(true)) '
                'R.record(nil, "e1", "c-ann", "mission.success", nil, nil, {"Ruth"})')
        files = sorted((self.root / 'batman_RadioSurvivorCore').glob('reputation-*.txt'))
        self.assertTrue(files)
        self.assertTrue(files[-1].read_text(encoding='utf-8').startswith('RCREP1='))
        self.restart()
        self.assertTrue(self.ev('return require("RadioSurvivorCore/RC_Reputation").init(false)'))
        self.assertEqual(self.score('c-ann'), 5)
        self.ev('return require("RadioSurvivorCore/RC_Reputation").record(nil, "e1", "c-ann", '
                '"mission.success", nil, nil, nil)')
        self.assertEqual(self.score('c-ann'), 5, 'replayed event after a restart')

    def test_new_world_starts_neutral_and_retired_character_purged(self):
        self.identity('c-ann', 'ann')
        self.ev('local R = require("RadioSurvivorCore/RC_Reputation") assert(R.init(true)) '
                'R.record(nil, "e1", "c-ann", "mission.failed", nil, nil, nil)')
        self.assertEqual(self.score('c-ann'), -5)
        # Death: RC_Identity retires the identity, the core reputation starts its purge clock (RC_ReputationEvents).
        self.ev('dofile([[' + (CORE_LUA / 'server' / 'RadioSurvivorCore' / 'RC_ReputationEvents.lua').as_posix() + ']]) '
                'local I = require("RadioSurvivorCore/RC_Identity") I.state.data.characters["c-ann"].retired = true '
                'for _, fn in ipairs(I.listeners.retire) do fn(nil, "c-ann") end')
        self.assertIsNone(self.score('c-ann'))
        self.assertTrue(self.ev('local R = require("RadioSurvivorCore/RC_Reputation") '
                                'return type(R.data.reputation["c-ann"].retiredDay) == "number"'))
        self.assertTrue(self.ev('local R = require("RadioSurvivorCore/RC_Reputation") '
                                'local d = R.data.reputation["c-ann"].retiredDay R.prune(R.data, d + 7) '
                                'return R.data.reputation["c-ann"] == nil and R.data.outcomes.e1 == nil'))


class WithoutRadioSurvivorTests(Base):
    """Core mod (and Living Knox) without any RadioSurvivor module."""

    def no_radiosurvivor(self):
        self.assertFalse(self.ev('for name in pairs(package.loaded) do '
                                 'if string.find(name, "^RadioSurvivor/") then return true end end return false'))

    def test_mission_result_and_offers_by_level_without_radiosurvivor(self):
        self.identity('c-ann', 'ann')
        self.ev('local R = require("RadioSurvivorCore/RC_Reputation") assert(R.init(true))')
        out = self.ev('''
            local M = require("RadioSurvivorCore/RC_Missions")
            local state = {missions = {}, npcs = {}}
            local m = {id = "npc1-delivery1", state = "active", revision = 1, npc = "npc1", template = "deliver",
                participants = {["c-ann"] = {name = "Ann"}}, invited = {}, requesterName = "Ruth"}
            state.missions[m.id] = m
            assert(M.finish(state, m, "failed"))
            local R = require("RadioSurvivorCore/RC_Reputation")
            local o = R.data.outcomes["npc1-delivery1-c-ann-result"]
            return o.action .. "|" .. R.scoreOf("c-ann") .. "|" .. R.reasons("c-ann")[1].reasonArgs[1]
        ''')
        self.assertEqual(out, 'mission.failed|-5|Ruth')
        # Bad reputation: the sensitive offers are kept from the character, simple ones stay (E04-T05).
        self.ev('local R = require("RadioSurvivorCore/RC_Reputation") for i = 1, 3 do '
                'R.record(nil, "f" .. i, "c-ann", "mission.failed", nil, nil, nil) end')
        allowed = self.ev('''
            local M = require("RadioSurvivorCore/RC_Missions")
            local function fake(kind) return {idPrefix = "f", offer = function() return {kind = kind} end,
                create = function() end} end
            M.register("recover", fake("recover")) M.register("signal", fake("signal"))
            local C = require("RadioSurvivorCore/RC_MissionConfig")
            local npc = {id = "npc-x"}
            local bad, neutral = M.offers(npc, {hostile = false}, nil, "c-ann"), M.offers(npc, {hostile = false}, nil, "nobody")
            return tostring(bad[C.Missions.recover.id] ~= nil) .. tostring(bad[C.Missions.signal.id] ~= nil)
                .. tostring(neutral[C.Missions.recover.id] ~= nil)
        ''')
        self.assertEqual(allowed, 'falsetruetrue')
        self.no_radiosurvivor()

    def test_living_knox_alone_member_killed_once(self):
        self.identity('c-ann', 'ann')
        path = (LK_LUA / 'server' / 'LivingKnox' / 'LK_Reputation.lua').as_posix()
        out = self.ev(f'''
            local R = require("RadioSurvivorCore/RC_Reputation") assert(R.init(true))
            local I = require("RadioSurvivorCore/RC_Identity")
            local ann = {{getUsername = function() return "ann" end}}
            I.bound[ann] = "c-ann"
            local FACTS = {{}}
            LivingKnox = {{listen = function(name, key, fn) FACTS[name] = fn end,
                Bodies = {{livingPlayers = function() return {{ann}} end}}}}
            dofile([[{path}]])
            local info = {{npc = "lk-7", generation = 1, group = "grp-1", killer = "ann", cause = "melee"}}
            FACTS.npcDied(info) FACTS.npcDied(info)
            FACTS.npcDied({{npc = "lk-8", generation = 1, killer = "ann"}})          -- not a group member
            FACTS.npcDied({{npc = "lk-9", generation = 1, group = "grp-1"}})         -- no attributed killer
            -- Death already charged to ann as a killed requester: no member kill on top.
            R.record(nil, "fiche-killed-c-ann", "c-ann", "npc.requesterKilled", nil, {{body = "lk-10"}}, nil)
            FACTS.npcDied({{npc = "lk-10", generation = 1, group = "grp-1", killer = "ann"}})
            return R.scoreOf("c-ann") .. "|" .. R.reasons("c-ann", 5)[2].action .. "|" .. R.level("c-ann")
        ''')
        self.assertEqual(out, '-60|npc.memberKilled|bad')
        self.no_radiosurvivor()


if __name__ == '__main__':
    unittest.main()
