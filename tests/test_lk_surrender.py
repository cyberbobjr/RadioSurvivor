"""Tests hors jeu de la reddition visible (LK06-T12) : un PNJ qui se rend le dit une fois (réplique de gabarit
IGUI_LK_Surrender_<n>, LivingKnox.Speech.say) et lève les mains (geste "surrender", nœud généré LKActorSurrender,
clip vanilla Bob_EmoteSurrender) ; mains baissées à la fin de la reddition, à la trahison (réplique
IGUI_LK_Surrender_Betrayed_<n>) et quand le membre est oublié (mort, corps parti).

    python RadioSurvivor/tests/test_lk_surrender.py

Banc de la pile complète de test_lk_combat.py (DefenceStackTests : serveur dédié et deux clients, puis solo). La
parole est la doublure de test_lk_contest.py (répliques notées, un auditeur fictif) : la règle d'audition et la
livraison MP sont prouvées par test_lk_speech.py. Les doublures NE PROUVENT PAS l'API Java, seulement la logique.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lk_combat as tlc  # noqa: E402  (module importé : ses classes ne sont pas rejouées ici)
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_contest import SPEECH_DOUBLE, TRANSLATE  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DECISIONS = LUA / 'server' / 'LivingKnox' / 'LK_Decisions.lua'
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKRetreat.lua'


class SurrenderStackTests(tlc.DefenceStackTests):
    """Reddition d'un ouvrier d'un groupe qui ne tire pas le premier, frappé par le joueur A une fois blessé."""

    def said(self):
        return [e.key for e in lua_list(self.ev('SAID'))]

    def gesture(self, npc, m=None):
        return self.ev(f'LivingKnox.Anim.gestureOf("{npc}")', m)

    def surrender(self):
        """Ouvrier rendu au joueur A : rend gid, npc."""
        gid = self.mk_crew('keepers', [('fighter', 'thug'), ('worker', 'cook')])
        self.h.load(self.srv, SPEECH_DOUBLE)
        worker = self.npc_of(gid, 'm-2')
        self.place(self.npc_of(gid, 'm-1'), 104.5, 104.5)
        self.place(worker, 106.5, 104.5)
        self.h.move_player('A', 108.5, 104.5)
        if self.mode != 'solo':
            self.h.move_player('B', 109.5, 106.5)            # second client proche : reçoit aussi le geste
        self.run_lua(f'SEE_PLAYER("{worker}", "A", 108, 104, 2)')
        self.update(gid, 'g.members["m-2"].wound = 50')
        self.assertTrue(self.hit_by(worker))
        self.dpass(3)
        self.assertEqual(self.st(worker)[:2], ('threat', 'surrender'))
        return gid, worker

    def test_one_line_and_hands_up_while_it_lasts(self):
        gid, worker = self.surrender()
        said = self.said()
        self.assertEqual(len(said), 1, said)
        self.assertRegex(said[0], r'^IGUI_LK_Surrender_[1-4]$')
        self.assertEqual(self.gesture(worker), 'surrender')
        self.assertEqual(self.ev(f'{self.De}.stats.surrenderLines'), 1)
        self.assertTrue(any(f'npc {worker} says {said[0]} (surrender)' in line for line in self.lk()), self.lk())
        # Aucun pas pendant la reddition : aucune consigne de marche ou de course.
        e = self.run_lua(f'return DIRECTIVE("{gid}", "m-2")')
        self.assertTrue(e is None or e.op != 'move', e)
        # Reddition qui dure (passages, échéance de l'état de 2 minutes dépassée) : aucune deuxième réplique.
        self.dpass(4)
        self.h.advance(3)
        self.run_lua(f'SEE_PLAYER("{worker}", "A", 108, 104, 2)')
        self.dpass(4)
        self.assertEqual(self.st(worker)[1], 'surrender')
        self.assertEqual(len(self.said()), 1, self.said())
        self.assertEqual(self.gesture(worker), 'surrender')
        # MP : le geste arrive aux clients proches par le relais des gestes (animState), fenêtre écoulée et réseau livré.
        if self.mode != 'solo':
            self.h.tick(int(self.ev('LivingKnox.Config.RELAY.WINDOW_MS') // self.h.tick_ms) + 2)
            self.h.pump()
        for c in (() if self.mode == 'solo' else ('A', 'B')):
            self.assertEqual(self.gesture(worker, c), 'surrender', c)
            self.assertEqual(self.h.errors(c), [])
        self.assertEqual(self.h.errors(self.srv), [])

    def test_betrayal_lowers_the_hands_at_once_with_one_line(self):
        gid, worker = self.surrender()
        self.assertTrue(self.hit_by(worker))
        self.assertEqual(self.ev(f'{self.De}.stats.surrenderBroken'), 1)
        self.assertNotEqual(self.gesture(worker), 'surrender')   # sans attendre la décision suivante
        said = self.said()
        self.assertEqual(len(said), 2, said)
        self.assertRegex(said[1], r'^IGUI_LK_Surrender_Betrayed_[12]$')
        self.dpass(4)
        self.assertNotEqual(self.st(worker)[1], 'surrender')      # plus de reddition à ce joueur
        self.assertNotEqual(self.gesture(worker), 'surrender')
        self.assertEqual(len(self.said()), 2, self.said())
        self.assertEqual(self.h.errors(self.srv), [])

    def test_end_of_surrender_then_a_new_one_says_a_new_line(self):
        gid, worker = self.surrender()
        # Joueur perdu de vue, coup oublié (HIT_MINUTES) et LINGER passé : fin de la reddition, mains baissées.
        self.run_lua('PERCEPTION = {}')
        self.h.advance(4)
        self.dpass(4)
        self.assertNotEqual(self.st(worker)[1], 'surrender')
        self.assertNotEqual(self.gesture(worker), 'surrender')
        self.assertTrue(any(f'{worker} ({gid} m-2): surrender to A over' in line for line in self.lk()), self.lk())
        self.assertEqual(len(self.said()), 1)
        # Nouveau coup : nouvelle reddition, nouvelle réplique (une par reddition).
        self.run_lua(f'SEE_PLAYER("{worker}", "A", 108, 104, 2)')
        self.assertTrue(self.hit_by(worker))
        self.dpass(3)
        self.assertEqual(self.st(worker)[1], 'surrender')
        self.assertEqual(self.gesture(worker), 'surrender')
        said = self.said()
        self.assertEqual(len(said), 2, said)
        self.assertRegex(said[1], r'^IGUI_LK_Surrender_[1-4]$')

    def test_death_lowers_the_hands(self):
        gid, worker = self.surrender()
        self.update(gid, 'g.members["m-2"].alive = false')
        self.dpass(6)                                     # liste des membres refaite (ROSTER_MS) : membre oublié
        self.assertIsNone(self.ev(f'{self.De}.get("{worker}")'))
        self.assertNotEqual(self.gesture(worker), 'surrender')
        self.assertEqual(len(self.said()), 1)

    def test_nobody_hears_nothing_said_again(self):
        gid = self.mk_crew('keepers', [('fighter', 'thug'), ('worker', 'cook')])
        worker = self.npc_of(gid, 'm-2')
        self.h.load(self.srv, 'SAID = {} LivingKnox.Speech = { say = function(id, what) SAID[#SAID + 1] = '
                              '{ key = what.key } return nil, "nobody hears" end }')
        self.place(worker, 106.5, 104.5)
        self.run_lua(f'SEE_PLAYER("{worker}", "A", 108, 104, 2)')
        self.update(gid, 'g.members["m-2"].wound = 50')
        self.assertTrue(self.hit_by(worker))
        self.dpass(6)
        self.assertEqual(self.st(worker)[1], 'surrender')
        self.assertEqual(len(self.said()), 1)                # tentée une fois à l'entrée, jamais répétée
        self.assertEqual(self.ev(f'{self.De}.stats.surrenderLines'), 0)
        self.assertEqual(self.gesture(worker), 'surrender')


class SoloSurrenderStackTests(SurrenderStackTests):
    mode = 'solo'


# Méthodes héritées de la pile de défense : déjà jouées par test_lk_combat.py.
for _cls in (SurrenderStackTests, SoloSurrenderStackTests):
    for _name in dir(_cls):
        if _name.startswith('test_') and _name not in SurrenderStackTests.__dict__:
            setattr(_cls, _name, None)
del _cls, _name   # sinon la dernière classe serait collectée deux fois


class SourceTests(unittest.TestCase):
    def test_translations_and_gesture(self):
        for lang in ('EN', 'FR'):
            data = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for i in range(1, 5):
                self.assertTrue(data.get(f'IGUI_LK_Surrender_{i}'), (lang, i))
            for i in range(1, 3):
                self.assertTrue(data.get(f'IGUI_LK_Surrender_Betrayed_{i}'), (lang, i))
        table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        self.assertIn('surrender', table['gestures'])
        node = [n for n in table['nodes'] if n['name'] == 'LKActorSurrender'][0]
        self.assertEqual((node['clip'], node['states']), ('Bob_EmoteSurrender', ['idle']))
        code = DECISIONS.read_text(encoding='utf-8')
        self.assertIn('Decisions.SURRENDER_GESTURE = "surrender"', code)
        self.assertIn('n = 4,', code)
        self.assertNotIn('"kneel"', code)

    def test_suite_measures_gesture_and_line(self):
        suite = SUITE.read_text(encoding='utf-8')
        self.assertTrue(all(b < 128 for b in SUITE.read_bytes()))
        self.assertIn('"surrender line: %d said', suite)
        self.assertIn('"surrender"', suite)


if __name__ == '__main__':
    unittest.main()
