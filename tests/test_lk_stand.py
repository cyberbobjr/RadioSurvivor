"""Tests hors jeu de la remise debout des corps de PNJ Living Knox (LK02-T14) : LK_Stand.lua, LK_Bodies.createBody,
LK_ZombieGuard.adopt.

    python RadioSurvivor/tests/test_lk_stand.py

Banc tests/harness.py, doublures de tests/test_lk_bodies.py (création B réelle par LivingKnox.Bodies) et de
tests/test_lk_guard.py (copies reçues par le réseau). Les doublures reproduisent le Java 42.21.0 relevé ; elles NE
PROUVENT PAS l'API réelle, seulement la logique :
- réanimation : corps au sol, état d'action onground, ZombieOnGroundState, non collidable
  (IsoDeadBody.java:1875-1880, 1930-1937 ; ZombieOnGroundState.java:37-67) ;
- relevé et rejeu de l'état d'action (IsoGameCharacter.java:11516-11528, ActionStateContainer.java:199-243) : rejeu
  immédiat de l'état d'action, état Java changé par changeState seulement (StateMachine.java:34-72) ;
- copie d'un client MP (NetworkZombieSimulator.java:176-234) : OnZombieCreate sur un zombie neuf (état d'action
  « idle »), drapeaux du paquet, état réseau getRealState du paquet, puis ZombieOnGroundState forcé par
  l'identifiant du cadavre réanimé (au sol, non collidable), l'état d'action ne suivant qu'à la mise à jour
  suivante (non simulée : posé ici à « idle » ou « onground » selon le cas).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_guard import GuardBase  # noqa: E402

STAND_DOUBLES = r'''
local H = HARNESS
-- Copie d'un corps de PNJ reçue par le réseau (voir l'en-tête) ; action = état d'action au moment du passage.
function NET_BODY(id, owner, outfitId, realState, action)
    local zb = NET_CREATE(id, 102, 102, 0, owner, outfitId, true)
    zb.realState = realState
    zb.onFloor, zb.collidable = true, false
    zb.aiState = ZombieOnGroundState.instance()
    zb.actionState = action
    return zb
end
-- Prochains zombies de addZombiesInOutfit dans un autre état d'action que « idle » (patron impossible).
NOT_IDLE = false
local add = addZombiesInOutfit
addZombiesInOutfit = function(...)
    local out = add(...)
    if NOT_IDLE then
        for i = 0, out:size() - 1 do out:get(i).actionState = 'walktoward' end
    end
    return out
end
function POSE(zb)
    if zb == nil then return 'nil' end
    return 'floor=' .. tostring(zb:isOnFloor()) .. ' action=' .. zb:getActionStateName()
        .. ' ai=' .. tostring(zb:getCurrentState().name) .. ' collidable=' .. tostring(zb:isCollidable())
        .. ' front=' .. tostring(zb:isFallOnFront()) .. ' knocked=' .. tostring(zb:isKnockedDown())
        .. ' alpha=' .. tostring(zb:getAlpha())
end
'''

STOOD = 'floor=false action=idle ai=ZombieIdleState collidable=true front=false knocked=false'
LYING = 'floor=true action=onground ai=ZombieOnGroundState collidable=false'


class StandBase(GuardBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, STAND_DOUBLES)
        return h

    def pose(self, m, zid):
        return self.h.eval(m, f'POSE(HARNESS.zombies[{zid}])')

    def stats(self, m):
        return self.h.eval(m, 'LivingKnox.Stand.stats')


class AuthorityTests(StandBase):
    def test_server_body_is_standing_when_spawn_returns(self):
        zid = self.npc()
        self.assertEqual(self.pose('server', zid), STOOD + ' alpha=1')  # aucun fondu sur un serveur dédié
        self.assertEqual(self.stats('server').stood, 1)
        self.assertIsNotNone(self.ev('LivingKnox.Stand.snapshot'))   # relevé sur le zombie temporaire
        self.assertEqual([line for line in self.lk() if 'vanilla get-up' in line], [])
        self.assertEqual(self.h.errors('server'), [])

    def test_no_idle_snapshot_leaves_the_vanilla_get_up_and_warns_once(self):
        self.run_lua('NOT_IDLE = true')
        self.init()
        first, body = self.spawn()
        second, _ = self.spawn(110, 110)
        self.assertEqual((first, second), ('lk-1', 'lk-2'))   # création réussie malgré tout
        self.assertTrue(self.pose('server', body.onlineID).startswith(LYING), self.pose('server', body.onlineID))
        self.assertIsNone(self.ev('LivingKnox.Stand.snapshot'))
        warnings = [line for line in self.lk() if 'vanilla get-up' in line]
        self.assertEqual(len(warnings), 1, warnings)
        self.assertIn('no idle state snapshot yet', warnings[0])

    def test_engine_error_does_not_cancel_the_creation(self):
        self.init()
        self.run_lua('HARNESS.classes.IsoGameCharacter.playbackSetCurrentStateSnapshot = '
                     'function() error("RuntimeException: boom") end')
        npc_id, body = self.spawn()
        self.assertEqual(npc_id, 'lk-1')
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].state'), 'embodied')
        self.assertIs(self.ev('(LivingKnox.Bodies.find("lk-1")) ~= nil'), True)
        warnings = [line for line in self.lk() if 'vanilla get-up' in line]
        self.assertEqual(len(warnings), 1)
        self.assertIn('engine error', warnings[0])

    def test_body_knocked_down_later_is_left_to_the_vanilla_get_up(self):
        zid = self.npc()
        # Coup ou chute plus tard : au sol par le moteur (ZombieOnGroundState.enter).
        self.h.load('server', f'local z = HARNESS.zombies[{zid}]; z:setOnFloor(true); z.actionState = "onground"; '
                              f'z:changeState(ZombieOnGroundState.instance()); z:setCollidable(false)')
        self.h.tick(60)
        self.h.advance_ms(10000)
        self.h.tick(60)
        self.assertTrue(self.pose('server', zid).startswith(LYING))
        self.assertEqual(self.stats('server').stood, 1)   # la seule remise debout : la création


class SoloTests(StandBase):
    mode = 'solo'

    def test_solo_body_is_standing_and_fades_in(self):
        zid = self.npc()
        self.assertEqual(self.pose('solo', zid), STOOD + ' alpha=0')   # alpha remonté par le moteur ensuite
        self.assertEqual(self.h.eval('solo', '#LivingKnox.Stand.watched'), 0)   # aucune surveillance hors client
        self.assertEqual(self.h.errors('solo'), [])


class ClientCopyTests(StandBase):
    def copy(self, m, realState, action='idle', owner='server'):
        """PNJ créé sur le serveur, liste livrée, copie reçue par le réseau chez m puis adoptée à l'image suivante."""
        zid = self.npc()
        outfit = self.ev(f'HARNESS.zombies[{zid}]:getPersistentOutfitID()')
        self.h.pump()
        self.h.eval(m, f'NET_BODY({zid}, "{owner}", {outfit}, "{realState}", "{action}")')
        self.h.tick(1)
        self.assertIs(self.h.eval(m, f'LivingKnox.ZombieGuard.cache["lk-1"] == HARNESS.zombies[{zid}]'), True)
        return zid

    def test_remote_copy_stands_at_its_adoption_when_the_authority_stands(self):
        for action in ('idle', 'onground'):
            with self.subTest(action=action):
                self.h.close()
                self.h = self.make()
                zid = self.copy('A', 'idle', action)
                self.assertEqual(self.pose('A', zid), STOOD + ' alpha=0')
                self.assertEqual(self.stats('A').stood, 1)
                self.assertEqual(self.h.eval('A', '#LivingKnox.Stand.watched'), 0)
                self.assertEqual(self.h.errors('A'), [])

    def test_remote_copy_waits_for_the_authority_state_then_stands(self):
        """Premier paquet parti avant la mise à jour du corps sur le serveur : état réseau encore « onground »."""
        zid = self.copy('A', 'onground', 'onground')
        self.assertTrue(self.pose('A', zid).startswith(LYING))
        self.assertEqual(self.h.eval('A', '#LivingKnox.Stand.watched'), 1)
        self.h.tick(5)
        self.assertTrue(self.pose('A', zid).startswith(LYING))
        self.h.load('A', f'HARNESS.zombies[{zid}].realState = "idle"')   # paquet suivant
        self.h.tick(1)
        self.assertEqual(self.pose('A', zid), STOOD + ' alpha=0')
        self.assertEqual(self.h.eval('A', '#LivingKnox.Stand.watched'), 0)

    def test_copy_simulated_here_stands_at_once(self):
        zid = self.copy('A', 'onground', 'onground', owner='A')
        self.assertEqual(self.pose('A', zid), STOOD + ' alpha=0')

    def test_authority_still_down_after_the_watch_is_left_alone(self):
        zid = self.copy('B', 'falldown', 'onground')
        self.h.advance_ms(self.ev('LivingKnox.Stand.WATCH_MS') + 1)
        self.h.tick(1)
        self.assertEqual(self.h.eval('B', 'LivingKnox.Stand.stats.dropped'), 1)
        self.h.load('B', f'HARNESS.zombies[{zid}].realState = "idle"')
        self.h.tick(3)
        self.assertTrue(self.pose('B', zid).startswith(LYING))   # relevé vanilla, plus le nôtre
        self.assertEqual(self.h.eval('B', 'LivingKnox.Stand.stats.stood'), 0)

    def test_copy_seen_standing_is_never_stood_again_after_a_fall(self):
        zid = self.copy('A', 'idle', 'idle')
        self.assertEqual(self.stats('A').stood, 1)
        self.h.load('A', f'local z = HARNESS.zombies[{zid}]; z:setOnFloor(true); z.actionState = "onground"')
        self.h.tick(10)
        self.assertEqual(self.stats('A').stood, 1)
        self.assertTrue(self.pose('A', zid).startswith('floor=true action=onground'))

    def test_vanilla_zombie_copy_is_never_watched(self):
        self.npc()
        self.h.pump()
        self.h.eval('A', 'NET_BODY(7000, "server", 12 * 65536 + 3, "idle", "onground")')   # vrai joueur réanimé
        self.h.tick(3)
        self.assertTrue(self.pose('A', 7000).startswith(LYING))
        self.assertEqual(self.h.eval('A', 'LivingKnox.Stand.stats.stood'), 0)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_source(self):
        path = Path(__file__).resolve().parents[1] / ('Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/'
                                                      'LivingKnox/LK_Stand.lua')
        text = path.read_text(encoding='utf-8')
        code = re.sub(r'--[^\n]*', '', text)
        self.assertTrue(all(ord(ch) < 128 for ch in code), 'non ASCII character in code')
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


if __name__ == '__main__':
    unittest.main()
