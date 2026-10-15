"""Tests hors jeu des seuils « blessé » et « apeuré » réglables des PNJ Living Knox (LK05-T16) : options sandbox
LivingKnox.WoundedHealth (pour cent de la santé de naissance) et LivingKnox.AfraidFear (peur 0..100) de
sandbox-options.txt et leurs traductions, lecture par LK_Config.lua (Config.FITNESS, Config.danger) et emploi par
LK_Decisions.lua (Decisions.woundRatio, fearHigh, needHigh : inaptitude, repos du blessé, fuite apeurée, cascade de la
peur) et LK_Expeditions.lua (Ex.needBlocker).

    python RadioSurvivor/tests/test_lk_fitness.py

Bancs :
- fichiers : options entières de la page LivingKnox (bornes, défaut = valeur d'avant LK05-T16), table Config.FITNESS
  identique au fichier, libellé et infobulle EN et FR (sans « % » : Translator) ;
- logique pure (serveur d'un banc tests/harness.py, doublure de getSandboxOptions():getOptionByName de
  test_lk_thresholds.py) : option absente ou invalide = valeur d'avant (0,5 et 70), changement relu à l'appel suivant
  (sondage) ; changer l'option change la décision au passage suivant (combat ou retraite, fuite apeurée, repos du
  blessé, cascade de la peur, départ en expédition) ;
- suite en jeu lk.fitness (RST_LKFitness.lua) jouée sur des doublures d'IntegerConfigOption (getValue, setValue).
Les doublures NE PROUVENT PAS l'API réelle ni le comportement en jeu. La défense du foyer (liste locale des défenseurs
de LK_Defense) lit les mêmes fonctions ; elle n'a pas de banc pur ici (bancs de test_lk_defense.py aux défauts).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lk_thresholds as tlt  # noqa: E402

D = 'LivingKnox.Decisions'
C = 'LivingKnox.Config'
EX = 'LivingKnox.Expeditions'

# (min, max, défaut de sandbox-options.txt) ; défaut = valeur d'avant LK05-T16 (WOUND_RATIO 0,5 ; NEED_HIGH.fear 70).
OPTIONS = {'WoundedHealth': (10, 90, 50), 'AfraidFear': (30, 100, 70)}

WORKER = 'role = "worker", allowed = { chores = true, cook = true }, combatant = false'
ZT = 'target = { kind = "zombie", u = "z:5", d = 2 }'


class FileTests(unittest.TestCase):
    def test_options_of_the_living_knox_page(self):
        blocks = tlt.sandbox_blocks()
        for name, (lo, hi, default) in OPTIONS.items():
            b = blocks.get(name)
            self.assertIsNotNone(b, name)
            self.assertEqual(b['type'].strip(), 'integer', name)
            self.assertEqual((int(b['min']), int(b['max']), int(b['default'])), (lo, hi, default), name)
            self.assertEqual(b['page'].strip(), 'LivingKnox', name)
            self.assertEqual(b['translation'].strip(), 'LivingKnox_' + name, name)

    def test_config_table_matches_the_file(self):
        code = tlt.CONFIG.read_text(encoding='utf-8')
        block = code[code.index('Config.FITNESS = {'):]
        block = block[:block.index('\n}')]
        found = {n: (int(a), int(b), int(c)) for n, a, b, c in
                 re.findall(r'(\w+) = \{ (\d+), (\d+), (\d+) \}', block)}
        self.assertEqual(found, OPTIONS)

    def test_label_and_tooltip_in_english_and_french(self):
        for lang in ('EN', 'FR'):
            data = json.loads((tlt.TRANSLATE / lang / 'Sandbox.json').read_text(encoding='utf-8'))
            for name in OPTIONS:
                label = data.get(f'Sandbox_LivingKnox_{name}')
                tip = data.get(f'Sandbox_LivingKnox_{name}_tooltip')
                self.assertTrue(label and tip, (lang, name))
                self.assertNotIn('%', label + tip, (lang, name))


class FitnessBase(tlt.PureThresholdBase):
    def setUp(self):
        super().setUp()
        self.run_lua('require "LivingKnox/LK_Expeditions"')

    def decide(self, over):
        return self.run_lua(f'local o = {D}.decide(CTX({{ {over} }})) return o.rule, o.b, o.why')


class ReadTests(FitnessBase):
    def test_missing_options_keep_the_values_from_before(self):
        self.assertEqual(self.ev(f'{D}.woundRatio()'), 0.5)
        self.assertEqual(self.ev(f'{D}.fearHigh()'), 70)
        self.assertEqual(self.ev(f'{D}.needHigh("fear")'), 70)
        self.assertEqual(self.ev(f'{D}.needHigh("fatigue")'), 80)

    def test_defaults_of_the_file_options_and_polling(self):
        self.opt('WoundedHealth', 50)
        self.opt('AfraidFear', 70)
        self.assertEqual((self.ev(f'{D}.woundRatio()'), self.ev(f'{D}.fearHigh()')), (0.5, 70))
        self.opt('WoundedHealth', 35)
        self.opt('AfraidFear', 90)
        self.assertEqual((self.ev(f'{D}.woundRatio()'), self.ev(f'{D}.fearHigh()')), (0.35, 90))
        self.assertEqual(self.ev(f'{D}.needHigh("fear")'), 90)
        self.assertEqual(self.ev(f'{D}.needHigh("hunger")'), 70)   # autres envies : inchangées
        self.opt('WoundedHealth', None)
        self.assertEqual(self.ev(f'{D}.woundRatio()'), 0.5)

    def test_invalid_value_keeps_the_previous_value_with_one_warning(self):
        for bad in (9, 91, 50.5, '"x"'):
            self.opt('WoundedHealth', bad)
            self.assertEqual(self.ev(f'{D}.woundRatio()'), 0.5, bad)
            self.assertEqual(self.ev(f'{D}.woundRatio()'), 0.5, bad)
        for bad in (29, 101):
            self.opt('AfraidFear', bad)
            self.assertEqual(self.ev(f'{D}.fearHigh()'), 70, bad)
        logs = self.h.logs(self.srv)
        self.assertEqual(len([x for x in logs if 'LivingKnox.WoundedHealth' in x]), 4, logs[-8:])
        self.assertEqual(len([x for x in logs if 'LivingKnox.AfraidFear' in x]), 2, logs[-8:])
        self.assertTrue(any('previous value 50 used' in x for x in logs if 'WoundedHealth' in x))


class EffectTests(FitnessBase):
    def test_unfit_follows_both_options(self):
        unfit = f'{D}.unfitOf(CTX({{ health = 0.4, needs = {{ fear = 75 }} }}))'
        self.assertEqual(self.ev(unfit), 'health 40% < 50%')
        self.opt('WoundedHealth', 30)
        self.assertEqual(self.ev(unfit), 'fear 75 >= 70')
        self.opt('AfraidFear', 80)
        self.assertIsNone(self.ev(unfit))
        self.opt('WoundedHealth', 60)
        self.assertEqual(self.ev(unfit), 'health 40% < 60%')

    def test_changing_the_wounded_option_changes_the_next_decision(self):
        rule, b, why = self.decide(f'{WORKER}, {ZT}, health = 0.4')
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('health 40% < 50%', why)
        self.opt('WoundedHealth', 30)                                    # 40 % n'est plus « blessé » : il se bat
        self.assertEqual(self.decide(f'{WORKER}, {ZT}, health = 0.4')[:2], ('threat', 'fight'))
        # Repos du blessé (règle wound) sans menace.
        self.assertNotEqual(self.decide('health = 0.4, atHome = false')[0], 'wound')
        self.opt('WoundedHealth', 50)
        self.assertEqual(self.decide('health = 0.4, atHome = false')[0], 'wound')

    def test_changing_the_afraid_option_changes_the_next_decision(self):
        needs = 'needs = { fear = 75, hunger = 0, thirst = 0, fatigue = 0 }'
        afraid = f'{WORKER}, threat = ZOMBIE(9), atHome = false, {needs}'
        self.assertEqual(self.decide(afraid)[:2], ('threat', 'flee'))   # apeuré : fuite à FleeDistanceAfraid (12)
        self.opt('AfraidFear', 80)
        self.assertEqual(self.decide(afraid)[:2], ('threat', 'watch'))
        self.assertEqual(self.decide(f'{WORKER}, {ZT}, needs = {{ fear = 75 }}')[1], 'fight')
        # Cascade de la peur sans menace : abri au foyer à partir du seuil.
        fear = 'needs = { fear = 75, hunger = 0, thirst = 0, fatigue = 0 }'
        self.assertNotEqual(self.decide(fear)[0], 'fear')
        self.opt('AfraidFear', 75)
        self.assertEqual(self.decide(fear)[:2], ('fear', 'rest'))

    def test_expedition_blocker_follows_the_afraid_option(self):
        food = '{ { c = "food", m = 10 } }'
        self.assertEqual(self.ev(f'{EX}.needBlocker({{ fear = 75 }}, {food})'), 'fear 75')
        self.opt('AfraidFear', 90)
        self.assertIsNone(self.ev(f'{EX}.needBlocker({{ fear = 75 }}, {food})'))
        self.assertEqual(self.ev(f'{EX}.needBlocker({{ fatigue = 85 }}, {food})'), 'fatigue 85')


SUITE = 'shared/RST/suites/RST_LKFitness.lua'

# Options réelles de SandboxOptions (IntegerConfigOption) : getValue, setValue hors bornes refusé sans erreur.
REAL_OPTIONS = r"""
local function intOption(v, lo, hi)
    local o = { v = v }
    function o:getValue() return self.v end
    function o:setValue(n) if n >= lo and n <= hi then self.v = n end end
    return o
end
LK_REAL = { ["LivingKnox.WoundedHealth"] = intOption(50, 10, 90), ["LivingKnox.AfraidFear"] = intOption(70, 30, 100) }
getSandboxOptions = function() return { getOptionByName = function(_, n) return LK_REAL[n] end } end
"""


class SuiteTests(FitnessBase):
    def test_suite_lk_fitness_passes_on_the_doubles(self):
        self.run_lua(REAL_OPTIONS)
        dev = (tlt.tla.DEV_LUA / 'shared').as_posix()
        self.run_lua(f'package.path = package.path .. ";{dev}/?.lua"')   # banc sans la racine du mod de dev
        self.run_lua((tlt.tla.DEV_LUA / SUITE).read_text(encoding='utf-8'))
        self.assertIs(self.h.load(self.srv, 'return (RST.start({ suite = "lk.fitness" }))'), True)
        for _ in range(50):
            if not self.h.eval(self.srv, 'RST.running()'):
                break
            self.h.tick()
            self.h.advance_ms(100)
        report = self.h.eval(self.srv, 'RST.last()')
        results = [(r.test, r.status, r.message) for r in tlt.lua_list(report.results)]
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        logs = self.h.logs(self.srv)
        for text in ('[LKF] measure thresholds: WoundedHealth 50 -> ratio 0.5, AfraidFear 70 -> fear 70',
                     '[LKF] measure changed: WoundedHealth 30 -> ratio 0.3, AfraidFear 90 -> fear 90'):
            self.assertTrue(any(text in line for line in logs), (text, logs[-6:]))
        # Nettoyage : options rendues à leur valeur d'avant.
        self.assertEqual(self.ev(f'{D}.woundRatio()'), 0.5)
        self.assertEqual(self.ev(f'{D}.fearHigh()'), 70)

    def test_suite_lk_fitness_is_ascii(self):
        raw = (tlt.tla.DEV_LUA / SUITE).read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')


if __name__ == '__main__':
    unittest.main()
