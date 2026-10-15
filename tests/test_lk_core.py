"""Tests hors jeu du squelette Living Knox (LK01-T02) : espace de noms, options, journal, entrées serveur/client.

    python RadioSurvivor/tests/test_lk_core.py

Banc tests/harness.py (simulation, pas validation de l'API Java). Les options sandbox sont simulées ici :
getSandboxOptions():getOptionByName(nom) rend nil pour une option inconnue (SandboxOptions.java), sinon un objet
dont getValue() rend la valeur courante.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

SANDBOX = r'''
JAVA_OPTIONS = {}
local SandboxOptionsStub = {}
SandboxOptionsStub.__index = SandboxOptionsStub
function SandboxOptionsStub:getOptionByName(name)
    local value = JAVA_OPTIONS[name]
    if value == nil then return nil end
    return { getValue = function() return JAVA_OPTIONS[name] end }
end
local instance = setmetatable({}, SandboxOptionsStub)
getSandboxOptions = function() return instance end
'''

SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'
CLIENT = 'client/LivingKnox/LK_Client.lua'


def lk_lines(h, machine):
    return [line for line in h.logs(machine) if line.startswith('[LivingKnox]')]


class Base(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = Harness(mode=self.mode)
        for m in self.machines():
            self.h.load(m, SANDBOX)

    def tearDown(self):
        self.h.close()

    def machines(self):
        return ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')

    def boot(self, machine):
        """Ordre du jeu : shared, puis client (sauf dédié), puis server."""
        for path in SHARED:
            self.h.load(machine, path)
        if machine != 'server':
            self.h.load(machine, CLIENT)
        self.h.load(machine, SERVER)


class LoadTests(Base):
    def test_server_side(self):
        self.boot('server')
        self.assertEqual(self.h.eval('server', 'LivingKnox.side()'), 'server')
        self.assertTrue(self.h.eval('server', 'LivingKnox.isAuthority()'))
        self.assertEqual(lk_lines(self.h, 'server'), [])  # rien au chargement
        self.h.fire('server', 'OnGameBoot')
        self.h.fire('server', 'OnGameStart')
        self.assertEqual(lk_lines(self.h, 'server'), [])
        self.h.fire('server', 'OnServerStarted')
        lines = lk_lines(self.h, 'server')
        self.assertEqual(len(lines), 1)
        self.assertRegex(lines[0], r'^\[LivingKnox\] INFO engine \d+\.\d+\.\d+ started \(side=server, '
                                   r'enabled=true, debug=false\)$')
        self.assertIsNone(self.h.eval('server', 'LivingKnox.Client'))
        self.assertEqual(self.h.errors('server'), [])

    def test_client_side_guard(self):
        self.boot('A')
        self.assertEqual(self.h.eval('A', 'LivingKnox.side()'), 'client')
        self.assertFalse(self.h.eval('A', 'LivingKnox.isAuthority()'))
        # Le fichier serveur, chargé aussi par un client MP, ne fait rien.
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Server'))
        self.assertIsNone(self.h.eval('A', 'LivingKnox.handlers["OnGameStart/Server.onStart"]'))
        self.assertIsNone(self.h.eval('A', 'LivingKnox.handlers["OnServerStarted/Server.onStart"]'))
        self.h.fire('A', 'OnGameStart')
        lines = lk_lines(self.h, 'A')
        self.assertEqual(len(lines), 1)
        self.assertRegex(lines[0], r'^\[LivingKnox\] INFO client \S+ ready \(side=client, enabled=true\)$')
        self.assertEqual(self.h.errors('A'), [])
        self.assertIsNone(self.h.eval('B', 'LivingKnox'))  # machines isolées

    def test_client_file_does_nothing_on_server(self):
        for path in SHARED:
            self.h.load('server', path)
        self.h.load('server', CLIENT)
        self.assertIsNone(self.h.eval('server', 'LivingKnox.Client'))
        self.h.fire('server', 'OnGameStart')
        self.assertEqual(lk_lines(self.h, 'server'), [])

    def test_namespace_not_overwritten(self):
        self.h.load('server', 'LivingKnox = { Other = { keep = 1 } }')
        self.boot('server')
        self.assertEqual(self.h.eval('server', 'LivingKnox.Other.keep'), 1)
        self.assertEqual(self.h.eval('server', 'type(LivingKnox.Config.read)'), 'function')
        # require rend les tables du namespace
        self.assertTrue(self.h.eval('server', 'require("LivingKnox/LK_Log") == LivingKnox.Log'))
        self.assertTrue(self.h.eval('server', 'require("LivingKnox/LK_Config") == LivingKnox.Config'))
        self.assertTrue(self.h.eval('server', 'require("LivingKnox/LK_Core") == LivingKnox'))

    def test_require_only(self):
        # Les modules partagés se chargent par require seul, sans ordre imposé.
        self.h.load('server', 'require "LivingKnox/LK_Log"')
        self.assertEqual(self.h.eval('server', 'type(LivingKnox.Config.isDebug)'), 'function')
        self.assertEqual(self.h.eval('server', 'LivingKnox.TAG'), '[LivingKnox]')

    def test_wrappable_by_table(self):
        self.boot('server')
        self.h.load('server', '''
            local old = LivingKnox.Server.onStart
            WRAPPED = 0
            LivingKnox.Server.onStart = function(...) WRAPPED = WRAPPED + 1; return old(...) end
        ''')
        self.h.fire('server', 'OnServerStarted')
        self.assertEqual(self.h.eval('server', 'WRAPPED'), 1)
        self.assertEqual(len(lk_lines(self.h, 'server')), 1)

    def test_reload_no_double_subscription(self):
        self.boot('server')
        self.h.load('server', SERVER)
        self.h.load('server', SERVER)
        self.h.fire('server', 'OnServerStarted')
        self.assertEqual(len(lk_lines(self.h, 'server')), 1)
        self.boot('A')
        self.h.load('A', CLIENT)
        self.h.fire('A', 'OnGameStart')
        self.assertEqual(len(lk_lines(self.h, 'A')), 1)


class LogTests(Base):
    def setUp(self):
        super().setUp()
        self.boot('server')

    def test_levels(self):
        self.h.load('server', '''
            LivingKnox.Log.info("hello %d", 3)
            LivingKnox.Log.warn("careful")
            LivingKnox.Log.error("broken: %s", "x")
            LivingKnox.Log.debug("hidden")
            LivingKnox.Log.info("100%")
        ''')
        self.assertEqual(lk_lines(self.h, 'server'), [
            '[LivingKnox] INFO hello 3', '[LivingKnox] WARN careful', '[LivingKnox] ERROR broken: x',
            '[LivingKnox] INFO 100%'])

    def test_debug_switch(self):
        self.assertFalse(self.h.eval('server', 'LivingKnox.Log.debug("a")'))
        self.h.load('server', 'JAVA_OPTIONS["LivingKnox.Debug"] = true')
        self.assertTrue(self.h.eval('server', 'LivingKnox.Log.debug("b %s", "on")'))
        self.h.load('server', 'JAVA_OPTIONS["LivingKnox.Debug"] = false')
        self.assertFalse(self.h.eval('server', 'LivingKnox.Log.debug("c")'))
        self.assertEqual(lk_lines(self.h, 'server'), ['[LivingKnox] DEBUG b on'])

    def test_disable(self):
        self.h.load('server', 'JAVA_OPTIONS["LivingKnox.Debug"] = true')
        self.h.load('server', 'LivingKnox.Log.setEnabled(false)')
        self.assertFalse(self.h.eval('server', 'LivingKnox.Log.isEnabled()'))
        for level in ('debug', 'info', 'warn', 'error'):
            self.assertFalse(self.h.eval('server', f'LivingKnox.Log.{level}("x")'))
        self.assertEqual(lk_lines(self.h, 'server'), [])
        # L'état survit au rechargement du module.
        self.h.load('server', 'shared/LivingKnox/LK_Log.lua')
        self.assertFalse(self.h.eval('server', 'LivingKnox.Log.isEnabled()'))
        self.h.load('server', 'LivingKnox.Log.setEnabled(true)')
        self.assertTrue(self.h.eval('server', 'LivingKnox.Log.info("back")'))
        self.assertEqual(lk_lines(self.h, 'server'), ['[LivingKnox] INFO back'])


class ConfigTests(Base):
    def setUp(self):
        super().setUp()
        self.boot('server')

    def read(self, name):
        return self.h.eval('server', f'LivingKnox.Config.read("{name}")')

    def test_defaults(self):
        self.assertIs(self.read('Enabled'), True)
        self.assertIs(self.read('Debug'), False)
        self.assertTrue(self.h.eval('server', 'LivingKnox.Config.isEnabled()'))
        self.assertFalse(self.h.eval('server', 'LivingKnox.Config.isDebug()'))

    def test_without_sandbox_api(self):
        self.h.load('server', 'getSandboxOptions = nil')
        self.assertIs(self.read('Enabled'), True)

    def test_order_java_then_sandboxvars_then_default(self):
        self.h.load('server', 'SandboxVars = { LivingKnox = { Enabled = false, Debug = true } }')
        self.assertIs(self.read('Enabled'), False)  # option Java absente -> SandboxVars
        self.assertIs(self.read('Debug'), True)
        self.h.load('server', 'JAVA_OPTIONS["LivingKnox.Enabled"] = true')
        self.assertIs(self.read('Enabled'), True)  # option Java présente : prioritaire
        self.h.load('server', 'SandboxVars = { RadioSurvivor = { Enabled = false } }')
        self.assertIs(self.read('Debug'), False)  # ni Java ni SandboxVars -> défaut
        self.assertTrue(self.h.eval('server', 'LivingKnox.Config.isEnabled()'))

    def test_changed_during_game(self):
        self.h.load('server', 'SandboxVars = { LivingKnox = { Enabled = true } }')
        self.h.load('server', 'JAVA_OPTIONS["LivingKnox.Enabled"] = true')
        self.assertTrue(self.h.eval('server', 'LivingKnox.Config.isEnabled()'))
        # Changement en cours de partie : l'option Java change, SandboxVars reste périmé.
        self.h.load('server', 'JAVA_OPTIONS["LivingKnox.Enabled"] = false')
        self.assertFalse(self.h.eval('server', 'LivingKnox.Config.isEnabled()'))
        self.h.fire('server', 'OnServerStarted')
        self.assertIn('enabled=false', lk_lines(self.h, 'server')[-1])


class PublishTests(Base):
    """E08-T07 : faits publiés par le moteur (LivingKnox.listen / publish)."""

    def test_listen_is_idempotent_and_errors_are_isolated(self):
        self.boot('server')
        self.h.load('server', '''
            GOT = {}
            LivingKnox.listen("memberDied", "a", function(i) GOT[#GOT + 1] = "a1:" .. i.member end)
            LivingKnox.listen("memberDied", "b", function() error("boom") end)
            LivingKnox.listen("memberDied", "c", function(i) GOT[#GOT + 1] = "c:" .. i.member end)
            LivingKnox.listen("memberDied", "a", function(i) GOT[#GOT + 1] = "a2:" .. i.member end)
            CALLED = LivingKnox.publish("memberDied", { member = "m-1" })
            NONE = LivingKnox.publish("nobody", {})
        ''')
        self.assertEqual(list(self.h.eval('server', 'GOT').values()), ['a2:m-1', 'c:m-1'])
        self.assertEqual(self.h.eval('server', 'CALLED'), 2)
        self.assertEqual(self.h.eval('server', 'NONE'), 0)
        self.assertTrue(any('ERROR' in line and 'listener b of memberDied failed' in line
                            for line in lk_lines(self.h, 'server')))


class SoloTests(Base):
    mode = 'solo'

    def test_solo(self):
        self.boot('solo')
        self.assertEqual(self.h.eval('solo', 'LivingKnox.side()'), 'solo')
        self.assertTrue(self.h.eval('solo', 'LivingKnox.isAuthority()'))
        self.assertTrue(self.h.eval('solo', 'LivingKnox.hasLocalPlayer()'))
        self.h.fire('solo', 'OnServerStarted')  # jamais déclenché en solo ; aucun abonné
        self.assertEqual(lk_lines(self.h, 'solo'), [])
        self.h.fire('solo', 'OnGameStart')
        lines = lk_lines(self.h, 'solo')
        self.assertEqual(len(lines), 2)
        self.assertTrue(any('INFO engine' in line and 'side=solo' in line for line in lines))
        self.assertTrue(any('INFO client' in line and 'side=solo' in line for line in lines))
        self.assertEqual(self.h.errors('solo'), [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
