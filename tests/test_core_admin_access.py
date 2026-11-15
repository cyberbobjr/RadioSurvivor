"""CA_AdminAccess (batman_CoreAI, E21-T04 slice 11): the one rule of the administration and debug tools of the mods,
under Lua 5.1 (lupa) with doubles of the engine functions (isClient, isServer, isDebugEnabled, Capability,
checkPermissions, IsoPlayer:getRole). NOT an in-game validation.

Authority (Access.allowed): MP server = checkPermissions(player, Capability.PopmanManage) AND the role of the player
holds that capability (checkPermissions is true when no connection is found); solo = the local player, debug mode
required when asked; MP client never. Display (Access.canUse): MP client = role capability of the local player; solo
or host = debug mode, or always when asked.

    python RadioSurvivor/tests/test_core_admin_access.py
"""
from __future__ import annotations

import unittest
from pathlib import Path

import lupa.lua51 as lua

CORE_LUA = Path(__file__).resolve().parents[1] / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'

BOOT = r'''
MODE, DEBUG, PERMIT = 'solo', false, true
isClient = function() return MODE == 'client' end
isServer = function() return MODE == 'server' end
isDebugEnabled = function() return DEBUG end
Capability = {PopmanManage = 'cap:PopmanManage'}
checkPermissions = function(player, cap) return PERMIT and cap == Capability.PopmanManage end
function makePlayer(caps)
    local role = {hasCapability = function(_, cap) return caps[cap] == true end}
    return {getRole = function() return role end}
end
ADMIN, PLAIN = makePlayer({['cap:PopmanManage'] = true}), makePlayer({})
LOCAL = PLAIN
getSpecificPlayer = function() return LOCAL end
'''


class AdminAccessTests(unittest.TestCase):
    def setUp(self):
        self.rt = lua.LuaRuntime(unpack_returned_tuples=True)
        self.rt.execute(BOOT)
        self.g = self.rt.globals()
        source = (CORE_LUA / 'shared' / 'CoreAI' / 'CA_AdminAccess.lua').read_text(encoding='utf-8')
        self.A = self.rt.execute(source)

    def allowed(self, player, debug_in_solo=None):
        result = self.A.allowed(player, debug_in_solo)
        ok, why = result if isinstance(result, tuple) else (result, None)
        return bool(ok), why

    def test_capability_of_every_tool(self):
        self.assertEqual(self.A.CAPABILITY, 'PopmanManage')

    def test_server_needs_permission_and_role(self):
        self.g.MODE = 'server'
        self.assertEqual(self.allowed(self.g.ADMIN), (True, None))
        ok, why = self.allowed(self.g.PLAIN)
        self.assertFalse(ok)
        self.assertIn('(role)', why)
        self.g.PERMIT = False
        ok, why = self.allowed(self.g.ADMIN)
        self.assertFalse(ok)
        self.assertEqual(why, 'missing capability PopmanManage')
        self.g.Capability = None
        self.assertEqual(self.allowed(self.g.ADMIN), (False, 'capability PopmanManage unknown'))

    def test_solo_debug_only_when_asked(self):
        self.assertEqual(self.allowed(self.g.PLAIN), (True, None))
        self.assertEqual(self.allowed(self.g.PLAIN, True), (False, 'debug mode off (solo)'))
        self.g.DEBUG = True
        self.assertEqual(self.allowed(self.g.PLAIN, True), (True, None))

    def test_mp_client_and_missing_player_refused(self):
        self.g.MODE = 'client'
        self.assertEqual(self.allowed(self.g.ADMIN), (False, 'MP client'))
        self.g.MODE = 'server'
        self.assertEqual(self.allowed(None), (False, 'no player'))

    def test_display_rule(self):
        self.g.MODE = 'client'
        self.assertFalse(self.A.canUse())
        self.g.LOCAL = self.g.ADMIN
        self.assertTrue(self.A.canUse())
        self.assertFalse(self.A.canUse(self.g.PLAIN))
        self.g.Capability = None
        self.assertFalse(self.A.canUse())
        self.g.MODE = 'solo'
        self.assertFalse(self.A.canUse(), 'solo without debug mode')
        self.assertTrue(self.A.canUse(None, True), 'solo tool open without debug mode')
        self.g.DEBUG = True
        self.assertTrue(self.A.canUse())


if __name__ == '__main__':
    unittest.main()
