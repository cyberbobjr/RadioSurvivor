"""Tests hors jeu des fonctions de test de l'API Living Knox (E01-T10) : LK_APITest.lua, et de bout en bout la
fixture PNJ du moteur de tests en jeu (RST.Fixtures.spawnNpc) et sa suite rst.fixtures.npc.

    python RadioSurvivor/tests/test_lk_apitest.py

Banc tests/harness.py (solo, ou serveur dédié + deux clients) avec les doublures du Java de tests/test_lk_bodies.py
(création par addZombiesInOutfit -> createCorpse -> reanimate, retrait, liste des zombies). Le moteur est réel :
LK_Store, LK_Bodies, LK_Server, LK_API, LK_APITest, le fournisseur du carnet RS_NPCProvider + RS_LivingKnox, le
moteur RST, ses fixtures et la suite en jeu. Les doublures NE PROUVENT PAS l'API réelle, seulement la logique.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, LUA  # noqa: E402
import test_lk_bodies as tb  # noqa: E402

API_TEST_FILE = LUA / 'server' / 'LivingKnox' / 'LK_APITest.lua'

LOAD = r'''
for _, m in ipairs({ 'LivingKnox/LK_APITest', 'RadioSurvivor/RS_NPCProvider', 'RadioSurvivor/RS_LivingKnox' }) do
    require(m)
end
'''

RST_LOAD = r'''
require 'RST/RST'
require 'RST/RST_Fixtures'
require 'RST/suites/RST_FixturesNpc'
'''


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Base(tb.Base):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        names = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in names:
            h.load(m, LOAD)
        return h

    def api(self, code):
        return self.run_lua('return LivingKnox.API.' + code)


class ApiTests(Base):
    def test_spawn_and_remove_on_a_test_save(self):
        self.init()
        npc_id = self.api('testSpawnNpc(102, 102, 0)')
        self.assertEqual(npc_id, 'lk-1')
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)
        self.assertEqual(lua_list(self.api('testNpcs()')), ['lk-1'])
        self.assertEqual(self.ev('(LivingKnox.Bodies.find("lk-1")) ~= nil'), True)
        self.assertEqual(self.api('testRemoveNpc("lk-1")'), (True, 1))
        self.assertEqual(self.ev('TAGGED("lk-1")'), 0)
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"]'))
        self.assertEqual(lua_list(self.api('testNpcs()')), [])
        self.assertEqual(self.api('testRemoveNpc("lk-1")'), (False, 'npc lk-1 was not created by testSpawnNpc'))

    def test_refused_on_a_normal_save_and_bad_arguments(self):
        self.init()
        self.run_lua('WORLD_NAME = "Survie 1"')
        self.assertEqual(self.api('testSpawnNpc(102, 102, 0)'),
                         (None, "save 'Survie 1' is not a test save (rstest*)"))
        self.run_lua('WORLD_NAME = ""')
        self.assertEqual(self.api('testAllowed()'), (False, 'save name unavailable (getWorld():getWorld())'))
        self.run_lua('WORLD_NAME = "RSTest-Solo"')
        self.assertEqual(self.api('testAllowed()'), True)
        self.assertEqual(self.api('testSpawnNpc(102, "a", 0)'), (None, 'position must be three numbers'))
        self.assertEqual(self.api('testSpawnNpc(102, 102, 0, "x")'), (None, 'profile must be a table'))
        self.assertEqual([c for c in self.calls() if c.startswith('addZombiesInOutfit')], [])

    def test_refused_outside_debug_mode(self):
        # E01-T18 : hors mode debug (isDebugEnabled() faux ou absent), refus clair et journalisé, rien n'est créé.
        self.init()
        why = 'debug mode off (isDebugEnabled() is false on this machine)'
        self.run_lua('isDebugEnabled = function() return false end')
        self.assertEqual(self.api('testAllowed()'), (False, why))
        self.assertEqual(self.api('testSpawnNpc(102, 102, 0)'), (None, why))
        self.assertEqual(self.api('testRemoveNpc("lk-1")'), (False, why))
        self.run_lua('isDebugEnabled = nil')
        self.assertEqual(self.api('testSpawnNpc(102, 102, 0)'), (None, why))
        self.assertEqual([c for c in self.calls() if c.startswith('addZombiesInOutfit')], [])
        logs = [line for line in self.h.logs('solo') if 'test API' in line]
        self.assertEqual(logs, ['[LivingKnox] test API testSpawnNpc refused: ' + why,
                                '[LivingKnox] test API testRemoveNpc refused: ' + why,
                                '[LivingKnox] test API testSpawnNpc refused: ' + why])
        # Mode debug rendu : l'API agit de nouveau (même partie rstest*).
        self.run_lua('isDebugEnabled = function() return true end')
        self.assertEqual(self.api('testSpawnNpc(102, 102, 0)'), 'lk-1')
        self.assertEqual(self.api('testRemoveNpc("lk-1")'), (True, 1))

    def test_debug_mode_checked_before_save_name(self):
        self.init()
        self.run_lua('isDebugEnabled = function() return false end')
        self.run_lua('WORLD_NAME = "Survie 1"')
        self.assertEqual(self.api('testAllowed()')[1], 'debug mode off (isDebugEnabled() is false on this machine)')
        self.run_lua('isDebugEnabled = function() return true end')
        self.assertEqual(self.api('testAllowed()')[1], "save 'Survie 1' is not a test save (rstest*)")

    def test_only_test_npcs_can_be_removed(self):
        self.init()
        other = self.spawn()[0]  # PNJ de la partie, créé hors de l'API de test
        self.assertEqual(self.api(f'testRemoveNpc("{other}")'),
                         (False, f'npc {other} was not created by testSpawnNpc'))
        self.assertEqual(self.ev(f'TAGGED("{other}")'), 1)
        self.assertEqual(lua_list(self.api('testNpcs()')), [])

    def test_engine_refusal_is_returned(self):
        self.init()
        self.run_lua('SandboxVars = { LivingKnox = { Enabled = false } }')
        self.assertEqual(self.api('testSpawnNpc(102, 102, 0)'), (None, 'Living Knox is disabled (sandbox)'))
        self.run_lua('SandboxVars = nil')
        self.run_lua('UNLOAD(96, 200, 96, 200)')
        npc_id, why = self.api('testSpawnNpc(102, 102, 0)')
        self.assertIsNone(npc_id)
        self.assertIsInstance(why, str)


class MpTests(Base):
    mode = 'mp'

    def test_server_only(self):
        self.init()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.API'))
        self.assertEqual(self.ev('LivingKnox.API.testSpawnNpc(102, 102, 0)'), 'lk-1')
        self.assertEqual(self.ev('(LivingKnox.API.testRemoveNpc("lk-1"))'), True)

    def test_dedicated_server_without_debug_refuses(self):
        # Serveur dédié lancé sans -Ddebug : isDebugEnabled() faux sur le serveur, refus même sur une partie rstest*.
        self.init()
        self.h.load('server', 'isDebugEnabled = function() return false end')
        self.assertEqual(self.ev('LivingKnox.API.testSpawnNpc(102, 102, 0)'),
                         (None, 'debug mode off (isDebugEnabled() is false on this machine)'))
        self.assertEqual([c for c in self.calls() if c.startswith('addZombiesInOutfit')], [])


class AutoclientServerTests(unittest.TestCase):
    def test_test_server_runs_in_debug_mode(self):
        # GameServer lit la propriété Java « debug » (System.getProperty), pas un argument -debug : -Ddebug doit
        # précéder la classe principale pour que isDebugEnabled() soit vrai sur le serveur de test.
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools' / 'autoclient'))
        import autoclient
        cmd = autoclient.server_java_command(Path('G'), Path(r'C:\c'), 'rs_mp1', 'pw')
        self.assertIn('-Ddebug', cmd)
        self.assertLess(cmd.index('-Ddebug'), cmd.index('zombie.network.GameServer'))
        self.assertNotIn('-debug', cmd)
        self.assertIn('-Ddebug', autoclient.with_xmx(cmd, '4096m'))


class SuiteTests(Base):
    def make(self, root=None):
        h = super().make(root)
        h.load('solo', RST_LOAD)
        return h

    def run_suite(self, flt='{ suite = "rst.fixtures.npc", tags = "world" }'):
        self.run_lua(f'DONE = nil; assert(RST.start({flt}, {{ ctx = {{ side = "solo", player = getPlayer() }}, '
                     'onDone = function(r) DONE = r end }))')
        for _ in range(2000):
            if not self.ev('RST.running()'):
                break
            self.h.tick()
        self.assertIsNotNone(self.ev('DONE'))
        report = self.ev('DONE')
        return [(r.test, r.status, r.message) for r in (report.results[i] for i in range(1, len(report.results) + 1))]

    def test_suite_passes_with_the_real_provider(self):
        self.init()
        self.assertEqual(self.ev('require("RadioSurvivor/RS_NPCProvider").active().name'), 'livingknox')
        results = self.run_suite()
        self.assertEqual(len(results), 2)
        for test, status, msg in results:
            self.assertEqual(status, 'PASS', f'{test}: {msg}')
        self.assertEqual(self.ev('TAGGED("lk-1")'), 0)
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"]'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_skipped_when_living_knox_is_not_the_provider(self):
        # Living Knox coupé : il ne s'enregistre pas, le carnet garde le fournisseur vide.
        self.run_lua('SandboxVars = { LivingKnox = { Enabled = false } }')
        self.init()
        results = self.run_suite()
        self.assertEqual(results, [(t, 'SKIP', 'no NPC provider active (RS_NPCProvider: none)') for t in
                                   ('spawnNpc makes an NPC seen by the provider',
                                    'the NPC is gone after the previous test')])
        self.assertEqual([c for c in self.calls() if c.startswith('addZombiesInOutfit')], [])


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_and_independent_of_radiosurvivor(self):
        src = API_TEST_FILE.read_text(encoding='utf-8')
        code = '\n'.join(re.sub(r'--.*$', '', line) for line in src.splitlines())
        self.assertTrue(code.isascii())
        first = next(line for line in src.splitlines() if 'isClient' in line)
        self.assertTrue(first.startswith('if isClient() then return end'))
        for word in (r'\bnext\s*\(', r'\bgoto\b', r'coroutine', r'ModData', r'sendServerCommand', r'getFileWriter',
                     r'RadioSurvivor', r'\bRS_', r'Provider', r'[&|~]\s*\d', r'<<|>>'):
            self.assertIsNone(re.search(word, code), word)


if __name__ == '__main__':
    unittest.main()
