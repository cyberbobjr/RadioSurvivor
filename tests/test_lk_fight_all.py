"""Tests hors jeu de LK06-T07 (« tout le monde se bat ») : tout membre valide, quel que soit son rôle, se bat contre un
zombie à portée ; la fuite, l'abri et la retraite ne restent qu'aux constantes mauvaises (santé sous WOUND_RATIO, peur
>= NEED_HIGH.fear) et au groupe débordé. Code : server/LivingKnox/LK_Decisions.lua (Decisions.unfitOf,
overwhelmedOf, threatWeight, ableNear, règle threat), LK_Defense.lua (membres valides de tout rôle aux postes).

    python RadioSurvivor/tests/test_lk_fight_all.py

Bancs :
- logique pure de la cascade (constantes, débordement et hystérésis, combat d'un ouvrier, cible joueur réservée aux
  combattants, retraite d'un membre blessé ou apeuré, défense du foyer qui garde son propre repli) ;
- pile complète en solo (groupe « deciders » de test_lk_defense.py : combattant m-1, ouvrier m-2, combattant m-3) :
  ouvrier valide loin du foyer qui attaque un zombie au lieu de fuir, puis blessé qui se retire ; ouvrier seul
  débordé par quatre zombies qui se replie ; défense du foyer : ouvrier valide à un poste, qui frappe le zombie arrivé
  à sa fenêtre. Les doublures NE PROUVENT PAS l'API réelle, seulement la logique.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_defense import DefenseStack  # noqa: E402

D = 'LivingKnox.Decisions'
Df = 'LivingKnox.Defense'

WORKER = 'role = "worker", allowed = { chores = true, cook = true }, combatant = false'
FIGHTER = 'role = "fighter", allowed = { fight = true, guard = true, defend = true }, combatant = true'
ZT = 'target = { kind = "zombie", u = "z:5", d = 2 }'


class PureFightAllTests(PureBase):
    def test_unfit_means_health_under_wound_ratio_or_high_fear(self):
        self.assertIsNone(self.ev(f'{D}.unfitOf(CTX())'))
        self.assertIsNone(self.ev(f'{D}.unfitOf(CTX({{ health = 0.5, needs = {{ fear = 69 }} }}))'))
        self.assertEqual(self.ev(f'{D}.unfitOf(CTX({{ health = 0.49 }}))'), 'health 49% < 50%')
        self.assertEqual(self.ev(f'{D}.unfitOf(CTX({{ needs = {{ fear = 70 }} }}))'), 'fear 70 >= 70')

    def test_overwhelmed_ratio_and_hysteresis(self):
        self.assertIsNone(self.ev(f'{D}.overwhelmedOf(0, 0, false)'))
        self.assertEqual(self.ev(f'{D}.overwhelmedOf(1, 0, false)'), 'overwhelmed: threat 1, no able member')
        self.assertIsNone(self.ev(f'{D}.overwhelmedOf(6, 2, false)'))                    # 6 <= 3 x 2
        self.assertEqual(self.ev(f'{D}.overwhelmedOf(7, 2, false)'), 'overwhelmed: threat 7 > 3 x 2 able member(s)')
        self.assertEqual(self.ev(f'{D}.overwhelmedOf(5, 2, true)'), 'overwhelmed: threat 5 > 2 x 2 able member(s)')
        self.assertIsNone(self.ev(f'{D}.overwhelmedOf(4, 2, true)'))                     # retour : 4 <= 2 x 2
        # Poids : zombies 1, joueur hostile 3, au plus RetreatDangerDistance (repli 15) ; menace sans fuite ignorée.
        w = ('{ { kind = "zombie", flee = true, d = 2 }, { kind = "player", flee = true, d = 5 }, '
             '{ kind = "player", flee = false, d = 1 }, { kind = "zombie", flee = true, d = 20 } }')
        self.assertEqual(self.ev(f'{D}.threatWeight({w})'), 4)

    def test_any_able_role_fights_a_zombie_but_only_combatants_attack_players(self):
        rule, b, why = self.decide(f'{WORKER}, {ZT}')
        self.assertEqual((rule, b, why), ('threat', 'fight', 'fight zombie z:5 at 2.0'))
        self.assertEqual(self.decide(f'{FIGHTER}, {ZT}')[1], 'fight')
        player = 'target = { u = "A", d = 3, reason = "help" }'
        self.assertNotEqual(self.decide(f'{WORKER}, {player}')[1], 'fight')
        self.assertEqual(self.decide(f'{FIGHTER}, {player}')[1], 'fight')
        # Zombie à 3 cases sans cible (pas de ligne dégagée, hors portée d'engagement) : un membre valide tient.
        rule, b, why = self.decide(f'{WORKER}, threat = ZOMBIE(3)')
        self.assertEqual(b, 'watch')
        self.assertIn('able member holds', why)

    def test_wounded_or_afraid_member_retreats_or_flees_instead_of_fighting(self):
        rule, b, why = self.decide(f'{WORKER}, {ZT}, health = 0.4')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertEqual(why, 'zombie z:5 at 2.0, health 40% < 50%, hiding at home')
        self.assertIn('back home', self.decide(f'{WORKER}, {ZT}, needs = {{ fear = 75 }}, atHome = false')[2])
        self.assertIn('fleeing', self.decide(f'{FIGHTER}, {ZT}, health = 0.45, home = false')[2])
        rule, b, why = self.decide(f'{WORKER}, threat = ZOMBIE(3), needs = {{ fear = 75 }}, atHome = false')
        self.assertEqual((rule, b), ('threat', 'flee'))
        self.assertEqual(why, 'zombie 42 at 3.0 (seen), too close, fear 75 >= 70')

    def test_overwhelmed_member_retreats_unless_the_home_defense_handles_it(self):
        over = 'overwhelmed = "overwhelmed: threat 4 > 3 x 1 able member(s)", threat = ZOMBIE(3)'
        rule, b, why = self.decide(f'{WORKER}, {ZT}, {over}, atHome = false')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertEqual(why, 'overwhelmed: threat 4 > 3 x 1 able member(s), back home')
        self.assertEqual(self.ev(f'{D}.decide(CTX({{ {WORKER}, {ZT}, {over}, atHome = false }})).key'), 'overwhelmed')
        self.assertIn('hiding at home', self.decide(f'{WORKER}, {ZT}, {over}')[2])
        dv = 'defense = { id = "def-1", role = "post", key = "def:post 110,115,0", why = "home defense def-1 hold" }'
        self.assertEqual(self.decide(f'{WORKER}, {ZT}, {over}, {dv}')[1], 'defend')   # repli collectif de LK_Defense


class SoloFightAllTests(DefenseStack):
    mode = 'solo'

    def put(self, gid, mid, x, y):
        self.run_lua(f'HARNESS.place(LivingKnox.Bodies.find(MEMBER_NPC("{gid}", "{mid}")), {x}, {y}, 0)')

    def test_able_worker_attacks_a_zombie_then_retreats_when_wounded(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        self.put(gid, 'm-2', 135.5, 110.5)                                   # loin du foyer (110,110) : pas de défense
        z = self.horde([(137, 110)])
        self.dpass(3)
        self.assertIsNone(self.ev(f'{Df}.get("{gid}")'))
        self.assertEqual(self.b(gid, 'm-2'), 'fight')
        self.assertEqual(self.engaged(gid, 'm-2'), f'z:{z[0]}')
        # Blessé (santé 40 % < 50 %) : plus de combat, il rentre au foyer.
        self.hurt(gid, 'm-2', 0.4)
        self.dpass(2)
        self.assertEqual(self.b(gid, 'm-2'), 'retreat')
        self.assertIsNone(self.engaged(gid, 'm-2'))
        self.assertTrue(any(f'retreats: zombie z:{z[0]} at ' in line and 'health 40% < 50%, back home' in line
                            for line in self.lk()), self.lk()[-10:])
        self.assertEqual(self.h.errors('solo'), [])

    def test_lone_fighter_overwhelmed_by_four_zombies_falls_back(self):
        # Combattant seul (peur x 0,5 : 4 zombies proches = 40, encore valide) : 4 > 3 x 1 membre valide, repli. Un
        # ouvrier seul aurait déjà peur (80 >= 70) : retraite pour constantes mauvaises (banc pur).
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        self.put(gid, 'm-1', 140.5, 110.5)                                   # seul : les autres sont à 30 cases
        self.horde([(142, 110), (142, 111), (141, 112), (143, 109)])
        self.dpass(3)
        self.assertEqual(self.b(gid, 'm-1'), 'retreat')
        st = self.run_lua(f'local s = {D}.get(MEMBER_NPC("{gid}", "m-1")) return s.key, s.why')
        self.assertEqual(st[0], 'overwhelmed')
        self.assertIn('overwhelmed: threat 4 > 3 x 1 able member(s), back home', st[1])
        self.assertEqual(self.h.errors('solo'), [])

    def test_able_worker_holds_a_post_and_strikes_the_zombie_at_its_window(self):
        gid = self.mk()
        self.jump_to(11)
        self.dpass(2)
        z = self.horde([(110, 121), (111, 122)])
        self.dpass(3)
        phase, places, _, _ = self.plan(gid)
        self.assertEqual(phase, 'hold')
        self.assertIn('m-2=post ', places)
        self.assertTrue(self.settle(gid))
        self.dpass(2)
        self.assertEqual(self.gesture(gid, 'm-2'), 'guard')
        post = self.place_of(gid, 'm-2')                                     # "post x,y,z"
        px, py, _ = (int(v) for v in post.split(' ')[1].split(','))
        self.h.move_zombie(z[1], px - 0.5 if px == 105 else px + 0.5, py + 0.5 if px == 105 else py - 0.5)
        self.dpass(2)
        self.assertEqual(self.engaged(gid, 'm-2'), f'z:{z[1]}')
        self.assertEqual(self.ev('OUTSIDE'), 0)
        self.assertEqual(self.h.errors('solo'), [])


if __name__ == '__main__':
    unittest.main()
