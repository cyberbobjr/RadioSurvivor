"""Tests hors jeu des priorités de passage et de l'arbitrage entre deux PNJ (LK18-T01, ADR adr-ceder-le-passage.md
D01 à D03, D05) : shared/LivingKnox/LK_Passage.lua (registre) et shared/LivingKnox/LK_PassageArbiter.lua (pur).

    python tests/test_lk_passage.py

Bancs :
- arbitrage pur (vrai Lua du mod sous lupa, Lua 5.1, `next` retiré comme dans Kahlua) : chaque cas de l'ADR
  (priorité plus haute, égalité départagée par le plus petit identifiant, bloqueur qui ne peut pas bouger, case de
  retrait hors du trajet, recul dans un couloir) ;
- registre ouvert/fermé : un comportement inscrit par le test est arbitré sans toucher au module de passage ;
- déclarations : chaque fichier de comportement du mod, chargé comme le jeu (banc tests/harness.py, Living Knox
  seul), déclare sa priorité dans l'ordre de l'ADR (fuite et combat, soin, défense, expédition, corvées, garde,
  repos par défaut).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

from lupa.lua51 import LuaError, LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LK_SHARED = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'shared'
P = 'LivingKnox.Passage'


class PassageBase(unittest.TestCase):
    def setUp(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        self.rt.globals().next = None   # absent de Kahlua
        self.rt.execute(f'package.path = [[{LK_SHARED.as_posix()}/?.lua;]]; package.cpath = ""')
        self.rt.execute('require "LivingKnox/LK_Passage"')
        # Priorités de test (le module de passage n'en connaît aucune).
        self.rt.execute(f'{P}.priority("t.urgent", 100) {P}.priority("t.work", 50) {P}.priority("t.guard", 30)')

    def run_lua(self, code):
        return self.rt.execute(code)

    def decide(self, mover, blocker, free, path):
        """(action, x, y) de Passage.arbitrate, ou (None, None, None)."""
        return self.run_lua(f'local d = {P}.arbitrate({mover}, {blocker}, {free}, {path}) '
                            'if d == nil then return nil, nil, nil end return d.action, d.to.x, d.to.y')


# Couloir horizontal : demandeur en 10,10 qui va vers l'est, bloqueur en 11,10, trajet 11..14,10.
MOVER = '{ id = "lk-5", kind = "t.urgent", x = 10, y = 10, z = 0 }'
PATH = '{ { x = 11, y = 10 }, { x = 12, y = 10 }, { x = 13, y = 10 }, { x = 14, y = 10 } }'


def blocker(kind='t.guard', bid='lk-9', can_move=True, moving=True):
    """Bloqueur en 11,10 ; moving : en marche (consigne ouverte), sinon immobile (D07 : il cède toujours)."""
    return (f'{{ id = "{bid}", kind = "{kind}", x = 11, y = 10, z = 0'
            f'{"" if can_move else ", canMove = false"}{", moving = true" if moving else ""} }}')


def squares(*xy):
    return '{ ' + ', '.join(f'{{ x = {x}, y = {y}, z = 0 }}' for x, y in xy) + ' }'


class ArbitrationTests(PassageBase):
    def test_lower_priority_blocker_steps_aside_off_the_path(self):
        free = squares((12, 10), (11, 9), (11, 11))   # 12,10 est sur le trajet : jamais retenue
        action, x, y = self.decide(MOVER, blocker(), free, PATH)
        self.assertEqual(action, 'stepAside')
        self.assertIn((x, y), [(11, 9), (11, 11)])
        self.assertNotEqual((x, y), (12, 10))

    def test_step_aside_choice_is_stable(self):
        free = squares((11, 11), (11, 9))
        first = self.decide(MOVER, blocker(), free, PATH)
        again = self.decide(MOVER, blocker(), squares((11, 9), (11, 11)), PATH)
        self.assertEqual(first, again)
        self.assertEqual(first, ('stepAside', 11, 9))   # même distance : y puis x

    def test_orthogonal_side_square_before_a_diagonal_one(self):
        action, x, y = self.decide(MOVER, blocker(), squares((12, 11), (11, 11)), PATH)
        self.assertEqual((action, x, y), ('stepAside', 11, 11))

    def test_higher_priority_blocker_keeps_its_place(self):
        mover = '{ id = "lk-5", kind = "t.guard", x = 10, y = 10, z = 0 }'
        self.assertEqual(self.decide(mover, blocker(kind='t.urgent'), squares((11, 9)), PATH), (None, None, None))

    def test_equal_priority_smaller_id_passes(self):
        mover = '{ id = "lk-5", kind = "t.work", x = 10, y = 10, z = 0 }'
        self.assertEqual(self.decide(mover, blocker(kind='t.work', bid='lk-12'), squares((11, 9)), PATH)[0],
                         'stepAside')
        # Numéro plus grand : le demandeur garde son blocage (numérique, pas l'ordre du texte : 12 > 5).
        mover12 = '{ id = "lk-12", kind = "t.work", x = 10, y = 10, z = 0 }'
        self.assertIsNone(self.decide(mover12, blocker(kind='t.work', bid='lk-5'), squares((11, 9)), PATH)[0])

    def test_blocker_unable_to_move_gives_nothing(self):
        self.assertIsNone(self.decide(MOVER, blocker(can_move=False), squares((11, 9)), PATH)[0])

    def test_corridor_face_to_face_lower_priority_backs_off_behind(self):
        # Aucune case de côté libre ; derrière le bloqueur (est), seule une niche hors trajet en 13,11 ; une case
        # libre devant lui (ouest, 10,11) n'est pas un recul.
        free = squares((12, 10), (13, 10), (13, 11), (9, 11))
        self.assertEqual(self.decide(MOVER, blocker(), free, PATH), ('backOff', 13, 11))

    def test_corridor_without_any_free_square_gives_nothing(self):
        self.assertIsNone(self.decide(MOVER, blocker(), squares((12, 10), (13, 10)), PATH)[0])

    def test_squares_of_the_mover_and_the_blocker_are_never_targets(self):
        self.assertIsNone(self.decide(MOVER, blocker(), squares((10, 10), (11, 10)), PATH)[0])

    def test_unknown_kinds_have_the_lowest_default(self):
        mover = '{ id = "lk-20", kind = "t.guard", x = 10, y = 10, z = 0 }'
        self.assertEqual(self.decide(mover, blocker(kind='nobody.declared', bid='lk-1'), squares((11, 9)), PATH)[0],
                         'stepAside')
        self.assertEqual(self.run_lua(f'return {P}.priorityOf("nobody.declared")'),
                         self.run_lua(f'return {P}.DEFAULT'))
        self.assertEqual(self.run_lua(f'return {P}.priorityOf(nil)'), self.run_lua(f'return {P}.DEFAULT'))

    def test_pure_arbiter_takes_an_injected_priority_query(self):
        # Sans registre : la requête injectée décide seule.
        out = self.run_lua('return LivingKnox.PassageArbiter.decide({ id = "lk-9", kind = "a", x = 10, y = 10, z = 0 }, '
                           '{ id = "lk-1", kind = "b", x = 11, y = 10, z = 0 }, { { x = 11, y = 9, z = 0 } }, {}, '
                           'function(k) if k == "a" then return 7 end return 3 end).action')
        self.assertEqual(out, 'stepAside')


class StationaryBlockerTests(PassageBase):
    """Mise à jour du 2026-11-15 (soir) de l'ADR : D07 (un PNJ immobile cède toujours à un PNJ en marche, sauf s'il
    ne peut pas bouger) et D08 (pas de case voisine : la case libre la plus proche, jusqu'à 3 cases). Les trois refus
    de la campagne MP du 2026-11-15 (serveur, PNJ de foyer au poste 10656,10136) rejoués en données d'arbitrage."""

    def setUp(self):
        super().setUp()
        # Priorités de l'ADR (D02), déclarées ici comme les fichiers des comportements.
        self.run_lua(f'{P}.priority("chore", 50) {P}.priority("meal", 50) {P}.priority("guard", 30) '
                     f'{P}.priority("patrol", 30)')

    def test_campaign_guard_vs_meal_stationary_meal_steps_aside(self):
        # « lk-140: blocked by npc lk-141 ..., no passage: blocker has priority (guard vs meal) »
        mover = '{ id = "lk-140", kind = "guard", x = 10, y = 10, z = 0 }'
        b = blocker(kind='meal', bid='lk-141', moving=False)
        self.assertEqual(self.decide(mover, b, squares((11, 9)), PATH), ('stepAside', 11, 9))

    def test_campaign_patrol_vs_chore_stationary_chore_steps_aside(self):
        # « lk-191: blocked by npc lk-192 ..., no passage: blocker has priority (patrol vs chore) »
        mover = '{ id = "lk-191", kind = "patrol", x = 10, y = 10, z = 0 }'
        b = blocker(kind='chore', bid='lk-192', moving=False)
        self.assertEqual(self.decide(mover, b, squares((11, 11)), PATH), ('stepAside', 11, 11))

    def test_campaign_chore_vs_guard_without_neighbour_goes_further(self):
        # « lk-5: blocked by npc lk-7 ..., no passage: no free square for the blocker (chore vs guard) » : aucune
        # case voisine hors trajet ni derrière ; une case libre à 2 cases sur le côté (D08).
        mover = '{ id = "lk-5", kind = "chore", x = 10, y = 10, z = 0 }'
        b = blocker(kind='guard', bid='lk-7', moving=False)
        free = squares((12, 10), (13, 10), (11, 8), (9, 12))
        self.assertEqual(self.decide(mover, b, free, PATH), ('stepAside', 11, 8))

    def test_moving_blockers_are_still_decided_by_priority(self):
        mover = '{ id = "lk-140", kind = "guard", x = 10, y = 10, z = 0 }'
        self.assertIsNone(self.decide(mover, blocker(kind='meal', bid='lk-141'), squares((11, 9)), PATH)[0])

    def test_stationary_blocker_unable_to_move_keeps_its_place(self):
        mover = '{ id = "lk-140", kind = "guard", x = 10, y = 10, z = 0 }'
        b = blocker(kind='meal', bid='lk-141', moving=False, can_move=False)
        self.assertIsNone(self.decide(mover, b, squares((11, 9)), PATH)[0])

    def test_fallback_never_takes_the_path_or_the_mover_square(self):
        mover = '{ id = "lk-5", kind = "chore", x = 10, y = 10, z = 0 }'
        b = blocker(kind='guard', bid='lk-7', moving=False)
        self.assertIsNone(self.decide(mover, b, squares((12, 10), (13, 10), (10, 10)), PATH)[0])


class RegistryTests(PassageBase):
    def test_a_new_behaviour_declares_its_priority_without_touching_the_passage_module(self):
        # Comportement ajouté par le test, plus haut que tout : il fait céder un bloqueur « urgent ».
        self.run_lua(f'{P}.priority("test.rescue", 500)')
        mover = '{ id = "lk-40", kind = "test.rescue", x = 10, y = 10, z = 0 }'
        self.assertEqual(self.decide(mover, blocker(kind='t.urgent', bid='lk-1'), squares((11, 9)), PATH)[0],
                         'stepAside')
        self.assertEqual(self.run_lua(f'return {P}.priorityOf("test.rescue")'), 500)

    def test_a_new_declaration_replaces_the_old_one(self):
        self.run_lua(f'{P}.priority("t.work", 10)')
        self.assertEqual(self.run_lua(f'return {P}.priorityOf("t.work")'), 10)

    def test_bad_declarations_are_refused_with_the_registry_name(self):
        for args in ('nil, 3', '"", 3', '"x", "high"', '"x", 0/0', f'"x", {P}.DEFAULT - 1'):
            ok, err = self.run_lua(f'return pcall(function() {P}.priority({args}) end)')
            self.assertFalse(ok, args)
            self.assertIn('LivingKnox.Passage.priority', err, args)
        self.assertEqual(self.run_lua(f'return {P}.priorityOf("x")'), self.run_lua(f'return {P}.DEFAULT'))

    def test_reloading_the_module_keeps_the_declarations(self):
        self.run_lua('package.loaded["LivingKnox/LK_Passage"] = nil require "LivingKnox/LK_Passage"')
        self.assertEqual(self.run_lua(f'return {P}.priorityOf("t.urgent")'), 100)


# Fichiers qui définissent un comportement, chargés comme le jeu (le require de chacun tire ses dépendances).
DECLARING_FILES = [
    'server/LivingKnox/LK_Decisions.lua',
    'server/LivingKnox/Decisions/LK_Decide_Defence.lua',
    'server/LivingKnox/Decisions/LK_Decide_Post.lua',
    'server/LivingKnox/LK_Combat.lua',
    'server/LivingKnox/LK_Care.lua',
    'server/LivingKnox/LK_Defense.lua',
    'server/LivingKnox/LK_Encounters.lua',
    'server/LivingKnox/LK_Relations.lua',
    'server/LivingKnox/LK_Expeditions.lua',
    'server/LivingKnox/LK_ProvisionMeal.lua',
    'server/LivingKnox/Routines/LK_Routine_Chores.lua',
    'server/LivingKnox/Routines/LK_Routine_Meal.lua',
]


class DeclarationTests(unittest.TestCase):
    """Ordre de l'ADR (D02) relevé sur les déclarations réelles des fichiers de comportement."""

    @classmethod
    def setUpClass(cls):
        cls.h = Harness(with_rs=False, mode='solo')
        for path in DECLARING_FILES:
            cls.h.load('solo', path)

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def prio(self, kind):
        return self.h.eval('solo', f'{P}.priorityOf("{kind}")')

    def test_adr_order_flee_fight_care_defense_expedition_chores_guard_rest(self):
        tiers = [('flee', 'fight', 'retreat'), ('care',), ('defend', 'alert', 'watch', 'warn', 'surrender', 'revenge'),
                 ('expedition',), ('chore', 'meal', 'provision'), ('guard', 'patrol'), ('rest', 'home', 'sleep')]
        values = [[self.prio(k) for k in tier] for tier in tiers]
        for tier, vals in zip(tiers, values):
            self.assertEqual(len(set(vals)), 1, f'{tier}: {vals}')
        flat = [vals[0] for vals in values]
        self.assertEqual(flat, sorted(flat, reverse=True), f'{tiers} -> {flat}')
        self.assertEqual(len(set(flat)), len(flat), flat)
        self.assertEqual(flat[-1], self.h.eval('solo', f'{P}.DEFAULT'))   # repos : non déclaré, le plus bas

    def test_every_behaviour_of_the_cascade_has_a_rank(self):
        # Comportements déclarés par le cadre de décision : chacun est soit déclaré, soit au défaut (repos).
        kinds = self.h.load('solo', 'local out = {} for k in pairs(LivingKnox.Decisions.BEHAVIOURS) do '
                                    'out[#out + 1] = k end table.sort(out) return out')
        names = [kinds[i] for i in range(1, len(kinds) + 1)]
        idle = {'rest', 'home', 'sleep'}
        for k in names:
            if k not in idle:
                self.assertGreater(self.prio(k), self.h.eval('solo', f'{P}.DEFAULT'), k)


if __name__ == '__main__':
    unittest.main(verbosity=2)
