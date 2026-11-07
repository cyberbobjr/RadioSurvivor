"""Identity of the player characters in the core mod batman_RadioSurvivorCore (E18-T03).

    python RadioSurvivor/tests/test_core_identity.py

Rules kept from E00-T01 / E00-T02, now owned by RC_Identity (shared/RadioSurvivorCore/RC_Identity.lua):
- the server writes the identity into its copy of the player modData (key RS_CarnetCharacter, the only copy saved in
  MP); the client value is only a fallback, accepted for the same account and slot, never for a retired character;
- a new character gets a new identity; OnCharacterDeath (players only) retires it for good;
- private registry of the core mod (Zomboid/Lua/batman_RadioSurvivorCore/identity-*.txt), kept across restarts;
- Living Knox keys its attitudes on it without RadioSurvivor (LK_Hostility.keyOf).
"""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

ID = 'require("RadioSurvivorCore/RC_Identity")'
# Engine globals the bench does not provide (IsoWorld, ZombRand); fixed values.
WORLD = ('getWorld = getWorld or function() return { getWorld = function() return "rstest-identity" end, '
         'getGameMode = function() return "Multiplayer" end } end; '
         'ZombRand = ZombRand or function(a, b) return a end')


class Base(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='rc_identity_'))
        self.h = self.start()

    def tearDown(self):
        self.h.close()
        shutil.rmtree(self.root, ignore_errors=True)

    def start(self, new_world=False, server_md=None):
        h = Harness(mode=self.mode, root=self.root)
        for m in h.machines:
            h.load(m, WORLD)
            h.load(m, f'IDENTITY = {ID}')
        if server_md:
            for name, cid in server_md.items():
                h.machine('server' if self.mode == 'mp' else 'solo').g.SET_MD = cid
                h.load('server' if self.mode == 'mp' else 'solo',
                       f'HARNESS.players["{name}"]:getModData().RS_CarnetCharacter = SET_MD')
        h.fire(self.srv, 'OnInitGlobalModData', new_world)
        return h

    @property
    def srv(self):
        return 'server' if self.mode == 'mp' else 'solo'

    def join(self, name):
        self.h.fire(name if self.mode == 'mp' else 'solo', 'OnGameStart')
        if self.mode == 'mp':
            self.h.pump()
            self.h.pump()

    def server_id(self, name):
        return self.h.eval(self.srv, f'IDENTITY.of(HARNESS.players["{name}"])')

    def server_md(self, name):
        return self.h.eval(self.srv, f'HARNESS.players["{name}"]:getModData().RS_CarnetCharacter')

    def client_md(self, name):
        return self.h.eval(name if self.mode == 'mp' else 'solo', 'getPlayer():getModData().RS_CarnetCharacter')


class IdentityMP(Base):
    def test_new_character_gets_a_server_identity(self):
        self.join('A')
        self.join('B')
        a, b = self.server_id('A'), self.server_id('B')
        self.assertRegex(a, r'^character-\d+-\d+-\d+$')
        self.assertNotEqual(a, b)
        self.assertEqual(self.server_md('A'), a)
        self.assertEqual(self.client_md('A'), a)
        files = sorted(p.name for p in (self.h.file_root('server') / 'batman_RadioSurvivorCore').glob('identity-*'))
        self.assertTrue(files, 'private registry file of the core mod')

    def test_reconnection_without_client_modData_keeps_the_identity(self):
        self.join('A')
        a = self.server_id('A')
        self.h.load('A', 'getPlayer():getModData().RS_CarnetCharacter = nil')
        self.h.load('server', 'IDENTITY.bound = {}')   # new connection: no binding yet
        self.join('A')
        self.assertEqual(self.server_id('A'), a)
        self.assertEqual(self.client_md('A'), a)

    def test_claim_of_another_account_is_refused(self):
        self.join('A')
        a = self.server_id('A')
        self.h.machine('B').g.CLAIM = a
        self.h.load('B', 'getPlayer():getModData().RS_CarnetCharacter = CLAIM')
        self.join('B')
        self.assertNotEqual(self.server_id('B'), a)

    def test_death_retires_the_identity(self):
        self.join('A')
        a = self.server_id('A')
        self.h.kill_player('A')
        self.assertIsNone(self.server_md('A'))
        self.assertIsNone(self.server_id('A'))
        self.assertEqual(self.h.eval('server', 'IDENTITY.idOf(HARNESS.players.A)'), a)
        self.assertIs(self.h.eval('server', f'IDENTITY.record("{a}").retired'), True)
        # The next character of the account claims the dead one: refused, new identity.
        self.h.load('server', 'HARNESS.players.A.dead = false; IDENTITY.bound = {}')
        self.h.machine('A').g.CLAIM = a
        self.h.load('A', 'getPlayer():getModData().RS_CarnetCharacter = CLAIM')
        self.join('A')
        self.assertNotEqual(self.server_id('A'), a)

    def test_a_zombie_death_retires_nothing(self):
        self.join('A')
        a = self.server_id('A')
        self.h.spawn_zombie(7, 1, 1)
        self.h.kill_zombie(7)
        self.assertEqual(self.server_id('A'), a)

    def test_restart_keeps_identities_and_retirements(self):
        self.join('A')
        self.join('B')
        a, b = self.server_id('A'), self.server_id('B')
        self.h.kill_player('B')
        self.h.close()
        self.h = self.start(server_md={'A': a})
        self.join('A')
        self.assertEqual(self.server_id('A'), a)
        self.h.machine('B').g.CLAIM = b
        self.h.load('B', 'getPlayer():getModData().RS_CarnetCharacter = CLAIM')
        self.join('B')
        self.assertNotEqual(self.server_id('B'), b)

    def test_new_world_starts_an_empty_registry(self):
        self.join('A')
        a = self.server_id('A')
        self.h.close()
        self.h = self.start(new_world=True)
        self.h.advance_ms(5000)
        self.assertIsNone(self.h.eval('server', f'IDENTITY.record("{a}")'))
        self.h.machine('A').g.CLAIM = a
        self.h.load('A', 'getPlayer():getModData().RS_CarnetCharacter = CLAIM')
        self.join('A')
        self.assertNotEqual(self.server_id('A'), a)

    def test_living_knox_keys_attitudes_without_radiosurvivor(self):
        self.h.load('server', 'require "LivingKnox/LK_Core"; require "LivingKnox/LK_Hostility"')
        self.assertIsNone(self.h.eval('server', 'RS_CarnetServer'))
        self.assertIsNone(self.h.eval('server', '(LivingKnox.Hostility.keyOf(HARNESS.players.A))'))
        self.join('A')
        self.assertEqual(self.h.eval('server', '(LivingKnox.Hostility.keyOf(HARNESS.players.A))'),
                         self.server_id('A'))


class IdentitySolo(Base):
    mode = 'solo'

    def test_solo_character_gets_an_identity(self):
        self.join('A')
        a = self.server_id('A')
        self.assertRegex(a, r'^character-')
        self.assertEqual(self.server_md('A'), a)
        self.assertEqual(self.h.eval('solo', f'IDENTITY.record("{a}").owner'), 'solo')


if __name__ == '__main__':
    unittest.main()
