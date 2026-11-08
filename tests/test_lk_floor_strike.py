"""Tests hors jeu du coup au sol (LK06-T09 : un zombie à terre, tombé ou renversé, frappé comme le joueur vanilla vise
le sol) : server/LivingKnox/LK_Combat.lua (geste selon l'arme et l'état du zombie), LK_Zombies.lua (dégâts au sol,
réaction « Floor » qui le garde à terre), client/LivingKnox/LK_ZombiesClient.lua (réaction posée par le client qui
simule le zombie). Repris de test_lk_window_kill.py, retiré avec l'offensive à la fenêtre (E18-T34).

    python RadioSurvivor/tests/test_lk_floor_strike.py

Pile de test_lk_zombies.py (solo et serveur + deux clients) ; doublures IsoZombie.setHitReaction / getHitReaction,
HandWeapon.getCriticalDamageMultiplier : NE PROUVENT PAS l'API réelle.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LK_LUA  # noqa: E402  (E18-T07)
from test_lk_zombies import ZombieBase  # noqa: E402

MOD_FILES = [LK_LUA / 'server/LivingKnox/LK_Combat.lua', LK_LUA / 'server/LivingKnox/LK_Zombies.lua',
             LK_LUA / 'client/LivingKnox/LK_CombatClient.lua', LK_LUA / 'client/LivingKnox/LK_ZombiesClient.lua']

# Réaction et multiplicateur critique (pile de combat).
FLOOR_DOUBLES = r'''
local C = HARNESS.classes
local Zc = C.IsoZombie
function Zc:setHitReaction(r)
    if type(r) ~= 'string' then error('No implementation found for setHitReaction', 2) end
    self.hitReaction = r
    REACTIONS = (REACTIONS or 0) + 1
end
function Zc:getHitReaction() return self.hitReaction or '' end
CRIT = { ['Base.BaseballBat'] = 2.0 }
function C.HandWeapon:getCriticalDamageMultiplier() return CRIT[self.t] or 2.0 end
'''


class FloorStrikeTests(ZombieBase):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', FLOOR_DOUBLES)
        return h

    def down(self, zid, down=True, crawling=False):
        self.run_lua(f'HARNESS.zombies[{zid}].onFloor = {str(down).lower()} '
                     f'HARNESS.zombies[{zid}].crawling = {str(crawling).lower()}')

    def test_floor_gesture_by_weapon_and_standing_or_crawling_zombie(self):
        self.npc_zid = self.npc()
        zid = self.vanilla(8201, 1.0, 0, health=50.0)
        self.down(zid)
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 1)
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'stomp')       # mains nues : piétinement
        self.down(zid, False)
        self.c('step("lk-1")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'strike')      # debout
        self.down(zid, True, crawling=True)
        self.c('step("lk-1")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'strike')      # rampant : frappé debout
        self.c('disengage("lk-1", "test")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        self.down(zid)
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 2)
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'strikefloor')  # arme visée au sol
        self.c('disengage("lk-1", "test")')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')        # geste au sol retiré aussi

    def test_floor_damage_follows_the_vanilla_floor_attack(self):
        self.npc_zid = self.npc()

        def dmg(t, hits, floor):
            return self.z(f'damageOf("lk-1", {{ c = 1 }}, instanceItem("{t}"), {hits}, {str(floor).lower()})')
        roll = self.ev('LivingKnox.Combat.roll("lk-1", 1, 1001)')
        level = 1.5 * (0.3 + 3 * 0.1)
        bat = 0.8 + (1.1 - 0.8) * roll / 99
        self.assertAlmostEqual(dmg('Base.BaseballBat', 1, False), bat * level * 0.15, places=9)
        # Arme visée au sol : x max(5, critique 2).
        self.assertAlmostEqual(dmg('Base.BaseballBat', 1, True), bat * level * 5 * 0.15, places=9)
        self.run_lua('CRIT["Base.BaseballBat"] = 7')
        self.assertAlmostEqual(dmg('Base.BaseballBat', 1, True), bat * level * 7 * 0.15, places=9)
        # Mains nues au sol : piétinement Rand(0,7, 1,0) + Force 5 x 0,2, chaussures 1,0, sans le x 5.
        stomp = 0.7 + 0.3 * roll / 99 + 5 * 0.2
        self.assertAlmostEqual(dmg('Base.BareHands', 1, True), stomp * level * 0.15, places=9)
        # Dès le 4e coup de mêlée : x (coups - 2) x 1,5, au sol comme debout.
        roll4 = self.ev('LivingKnox.Combat.roll("lk-1", 1, 1004)')
        stomp4 = 0.7 + 0.3 * roll4 / 99 + 1.0
        self.assertAlmostEqual(dmg('Base.BareHands', 4, True), stomp4 * level * 3 * 0.15, places=9)
        # Arme à feu : aucun effet du sol.
        self.assertAlmostEqual(dmg('Base.Pistol', 1, True), dmg('Base.Pistol', 1, False), places=12)

    def test_floor_hit_keeps_the_zombie_down_and_is_applied_once(self):
        self.npc_zid = self.npc()
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        zid = self.vanilla(8202, 1.0, 0, health=50.0)
        self.down(zid)
        self.c(f'engage("lk-1", HARNESS.zombies[{zid}])')
        for _ in range(20):
            self.seconds(0.5)
            if self.zstat('hits') >= 2:
                break
        hits = self.zstat('hits')
        self.assertGreaterEqual(hits, 2)                                 # impacts minutés sur le geste au sol
        self.assertEqual(self.zstat('floorHits'), hits)
        self.assertEqual(self.c('stats.applied'), hits)
        self.assertEqual(self.ev('REACTIONS'), hits)                     # réaction « Floor » à chaque coup
        self.assertEqual(self.ev(f'HARNESS.zombies[{zid}].hitReaction'), 'Floor')
        dealt = sum(self.z(f'damageOf("lk-1", {{ c = 1 }}, instanceItem("Base.BaseballBat"), {k}, true)')
                    for k in range(1, hits + 1))
        self.assertAlmostEqual(self.health(zid), 50.0 - dealt, places=6)
        # Debout : coup ordinaire, aucune réaction posée.
        self.run_lua(f'HARNESS.zombies[{zid}].hitReaction = nil REACTIONS = 0')
        self.down(zid, False)
        before = self.zstat('hits')
        for _ in range(20):
            self.seconds(0.5)
            if self.zstat('hits') > before:
                break
        self.assertGreater(self.zstat('hits'), before)
        self.assertEqual(self.ev('REACTIONS'), 0)
        self.assertEqual(self.zstat('floorHits'), hits)

    def test_zombie_killed_on_the_floor(self):
        self.npc_zid = self.npc()
        zid = self.vanilla(8203, 1.0, 0, health=1.0)
        self.down(zid)
        self.c(f'engage("lk-1", HARNESS.zombies[{zid}])')
        for _ in range(40):
            self.seconds(0.5)
            if self.h.zombie('solo', zid).killDone:
                break
        self.assertTrue(self.h.zombie('solo', zid).killDone)
        self.assertEqual(self.zstat('kills'), 1)
        self.assertTrue(any('killed zombie' in line and 'on the floor' in line for line in self.lk()), self.lk()[-5:])


class FloorReactionMultiplayerTests(ZombieBase):
    def make(self, root=None):
        h = super().make(root)
        for m in ('server', 'A', 'B'):
            h.load(m, FLOOR_DOUBLES)
        return h

    def test_reaction_sent_to_the_client_that_simulates_the_zombie(self):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for cl in ('A', 'B'):
            self.h.eval(cl, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.move_player('A', srv.x + 8, srv.y)
        self.h.move_player('B', srv.x + 9, srv.y)
        self.npc_zid = zid
        z = self.vanilla(8301, 1.0, 0, owner='B', health=5.0)
        for m in ('server', 'A', 'B'):
            self.h.eval(m, f'(function() HARNESS.zombies[{z}].onFloor = true return true end)()')
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        ok = self.run_lua(f'local o = {{ c = 1 }} return (LivingKnox.Zombies.hurt("lk-1", o, HARNESS.zombies[{z}], '
                          'instanceItem("Base.BaseballBat")))')
        self.assertIs(ok, True)
        self.assertEqual(self.ev(f'HARNESS.zombies[{z}].hitReaction'), 'Floor')       # copie du serveur
        self.h.pump()
        self.assertEqual(self.h.eval('B', f'HARNESS.zombies[{z}].hitReaction'), 'Floor')   # client qui le simule
        self.assertIsNone(self.h.eval('A', f'HARNESS.zombies[{z}].hitReaction'))
        self.assertLess(self.health(z, 'B'), 5.0)
        # Réaction inconnue : ignorée.
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'zombieHurt', {'o': z, 'd': 0.1, 'r': 'Shot'})
        self.assertEqual(self.h.eval('B', 'REACTIONS'), 1)


class SourceTests(unittest.TestCase):
    def test_sources_are_ascii_and_kahlua_safe(self):
        for path in MOD_FILES:
            raw = path.read_text(encoding='utf-8')
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw, flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII code in {path.name}')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b', r'\bbit32\b', r'<<|>>'):
                self.assertIsNone(re.search(pattern, code), (path.name, pattern))


if __name__ == '__main__':
    unittest.main(verbosity=1)
