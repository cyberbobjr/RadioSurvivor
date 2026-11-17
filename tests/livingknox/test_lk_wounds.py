"""Tests hors jeu du modèle pur des plaies de Living Knox (LK21-T01, ADR adr-blessures-soins.md D01 et D02) :
shared/LivingKnox/LK_Wounds.lua (modèle), LK_WoundsNeeds.lua (soins demandés), LK_WoundsForm.lua (forme
sauvegardée) et un fichier par type de plaie (shared/LivingKnox/Wounds/LK_Wound_<Kind>.lua).

    python tests/livingknox/test_lk_wounds.py

Vrai Lua du mod sous lupa (Lua 5.1, `next` retiré comme dans Kahlua). Aucun appel au jeu : le temps (minutes de jeu)
et le hasard (ctx.rnd) viennent de l'appelant, donc chaque cas est déterministe.

Règles vanilla vérifiées (Java décompilé 42.22, `J/` = E:/pz-source-42.22/java/zombie/, recherche
docs/annexes/conception/blessures-moteur.md section 2) :
- unités : `GameTime.getMultiplier()` vaut ~48 par seconde réelle (`GameTime.java:911-917`), journée de 90 minutes par
  défaut (`SandboxOptions.java:72`, `:403`) : 2 x 90 = 180 unités (« ticks ») par minute de jeu ;
- `BodyPart.DamageUpdate` (`J/characters/BodyDamage/BodyPart.java:138-430`) : dégâts de partie, perte de santé par
  saignement `0.2857143 x 0.0057142857 x (bleedingTime / 10)` (`:29-30`, `:161-168`, cou x5 `:90-92`), décroissance du
  saignement 2e-5 / 2e-4 bandé (`:204`, `:211`), usure du bandage (`:185`, `:193`, `:205-208`, `:304`, `:309`, `:330`,
  `:350`, `:374`), chance d'infection 40000 et ses modificateurs, plancher 5000 (`:221-257`), niveau d'infection
  (`:258-305`), points de suture (`:371-391`), attelle (`:392-397`) ;
- durées tirées : griffure 7-15 (`:727`), coupure 10-20 (`:683`), profonde 15-20 (`:776`), morsure 50-80 (`:609`),
  verre 15-20 (`:797`), balle retirée 17-23 moins docteur / 2 (`:1076`), fracture 50-80
  (`J/characters/IsoGameCharacter.java:2170`), brûlure 30-50 (`J/characters/BodyDamage/BodyDamage.java:2641`) ;
- saignement tiré (`generateBleeding`, `BodyPart.java:1780-1815`) puis x modificateur de partie
  (`J/characters/BodyDamage/BodyPartType.java:16-32`) ;
- points : `ISStitch.lua:119` ; attelle : `ISSplint.lua:89-94` ; bandage sale = vie 0 (`ISApplyBandage.lua:112-115`,
  `BodyPart.java:134-136`) ; désinfection : `ISDisinfect.lua:71`.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)

ROOT = Path(__file__).resolve().parents[2]
LK_SHARED = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'shared'
ENGINE = LK_SHARED / 'LivingKnox' / 'LK_Wounds.lua'
MODULES = ['LK_Wounds', 'LK_WoundsNeeds', 'LK_WoundsForm']   # modèle, soins demandés, forme sauvegardée
KIND_DIR = LK_SHARED / 'LivingKnox' / 'Wounds'
W = 'LivingKnox.Wounds'

TPM = 180                 # ticks par minute de jeu (2 x 90 minutes par jour)
DS = 0.0057142857         # BodyPart.java:30 (damageScaler)
BLEED = 0.2857143         # BodyPart.java:29 (bleedDamage)
ROLLS = 0.625             # tirages d'infection par tick : 30 par seconde réelle / 48 ticks (RandInterface.java:29)
KINDS = ['scratch', 'laceration', 'deep', 'bite', 'bullet', 'glass', 'fracture', 'burn']

# Nombres vanilla de chaque type (spec inscrite par son fichier), sources dans la docstring du module.
VANILLA = {
    'scratch': {'time': [7, 15], 'heal': {'open': 1e-5, 'bandaged': 1.5e-4}, 'wear': 8e-5,
                'damage': {'open': 0.9375}, 'infect': 20000, 'virusChance': 7},
    'laceration': {'time': [10, 20], 'heal': {'open': 1e-6, 'bandaged': 5e-5}, 'wear': 1e-5,
                   'damage': {'open': 1.875}, 'infect': 25000, 'virusChance': 25},
    'deep': {'time': [15, 20], 'heal': {'open': 2e-6, 'bandaged': 2e-5}, 'wear': 1e-4, 'bleedWear': 0.005,
             'damage': {'open': 3.125, 'bandaged': 1.5625}, 'infect': 30000},
    'bite': {'time': [50, 80], 'heal': {'open': 5e-6, 'bandaged': 1e-4}, 'wear': 1e-4,
             'damage': {'open': 2.1875}, 'virusChance': 100},
    'bullet': {'damage': {'open': 3.125, 'bandaged': 1.5625}},
    'glass': {'time': [15, 20], 'heal': {'open': 2e-6, 'bandaged': 2e-5}, 'wear': 1e-4, 'bleedWear': 0.005,
              'damage': {'open': 3.125, 'bandaged': 1.5625}, 'infect': 30000, 'foreignInfect': 24000,
              'infectGrowth': 1e-4},
    'fracture': {'time': [50, 80], 'heal': {'open': 5e-6, 'splinted': 5e-5},
                 'damage': {'open': 3.125, 'bandaged': 3.125, 'splinted': 0}},
    'burn': {'time': [30, 50], 'heal': {'open': 5e-6, 'bandaged': 1e-4}, 'wear': 1e-4, 'damage': {'open': 3.75}},
}
# BodyPartType.java:16-32 : ordre vanilla, modificateurs (douleur, dégâts, saignement) et modèle de bandage.
PARTS = [
    ('Hand_L', 0.5, 0.1, 0.2, 'Base.Bandage_LeftHand'), ('Hand_R', 0.5, 0.1, 0.2, 'Base.Bandage_RightHand'),
    ('ForeArm_L', 0.6, 0.2, 0.3, 'Base.Bandage_LeftLowerArm'), ('ForeArm_R', 0.6, 0.2, 0.3, 'Base.Bandage_RightLowerArm'),
    ('UpperArm_L', 0.6, 0.3, 0.4, 'Base.Bandage_LeftUpperArm'), ('UpperArm_R', 0.6, 0.3, 0.4, 'Base.Bandage_RightUpperArm'),
    ('Torso_Upper', 0.7, 0.35, 0.5, 'Base.Bandage_Chest'), ('Torso_Lower', 0.78, 0.4, 0.9, 'Base.Bandage_Abdomen'),
    ('Head', 0.8, 0.6, 1.0, 'Base.Bandage_Head'), ('Neck', 0.8, 0.7, 1.5, 'Base.Bandage_Neck'),
    ('Groin', 0.7, 0.4, 0.5, 'Base.Bandage_Groin'),
    ('UpperLeg_L', 0.7, 0.3, 0.4, 'Base.Bandage_LeftUpperLeg'), ('UpperLeg_R', 0.7, 0.3, 0.4, 'Base.Bandage_RightUpperLeg'),
    ('LowerLeg_L', 0.6, 0.2, 0.3, 'Base.Bandage_LeftLowerLeg'), ('LowerLeg_R', 0.6, 0.2, 0.3, 'Base.Bandage_RightLowerLeg'),
    ('Foot_L', 0.5, 0.2, 0.2, 'Base.Bandage_LeftFoot'), ('Foot_R', 0.5, 0.2, 0.2, 'Base.Bandage_RightFoot'),
]
NEVER = 'function() return 0.999999 end'   # après la blessure : aucun tirage d'infection ne réussit


def bleed_points_per_tick(bleed, scaler=1.0):
    return BLEED * DS * scaler * bleed / 10


class WoundsTests(unittest.TestCase):
    def setUp(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        self.rt.globals().next = None   # absent de Kahlua
        self.rt.execute(f'package.path = [[{LK_SHARED.as_posix()}/?.lua;]]; package.cpath = ""')
        for name in MODULES:
            self.rt.execute(f'require "LivingKnox/{name}"')
        for path in sorted(KIND_DIR.glob('LK_Wound_*.lua')):
            self.rt.execute(f'require "LivingKnox/Wounds/{path.stem}"')
        # seq(t) : tirages déterministes, rejoués en boucle.
        self.rt.execute('function seq(t) local i = 0 return function() i = i % #t + 1 return t[i] end end')

    def ev(self, code):
        return self.rt.execute('return ' + code)

    def run_lua(self, code):
        return self.rt.execute(code)

    def wound(self, kind, part, rnd='seq({ 0.5 })', opts='nil', ctx_extra='', after=NEVER):
        """Liste L d'une plaie w1 tirée avec ctx C (tirages rnd), puis C.rnd = after pour la suite."""
        self.run_lua(f'C = {{ rnd = {rnd}{ctx_extra} }}; L = {{}}; w1 = {W}.add(L, "{part}", "{kind}", C, {opts}); '
                     f'C.rnd = {after}')

    # ------------------------------------------------------------------ registre et données
    def test_every_kind_registered_from_its_own_file(self):
        files = sorted(p.stem for p in KIND_DIR.glob('LK_Wound_*.lua'))
        self.assertEqual(len(files), 8)
        ids = self.ev(f'(function() local t = {{}} for _, s in ipairs({W}.kinds()) do t[#t + 1] = s.id end '
                      'return table.concat(t, ",") end)()').split(',')
        self.assertEqual(sorted(ids), sorted(KINDS))

    def test_register_same_id_replaces_and_bad_spec_is_refused(self):
        self.run_lua(f'local s = {W}.kind("burn"); B2 = {{}} for k, v in pairs(s) do B2[k] = v end; '
                     f'B2.order = 999; {W}.registerKind("burn", B2)')
        self.assertEqual(self.ev(f'#{W}.kinds()'), 8)
        self.assertEqual(self.ev(f'{W}.kind("burn").order'), 999)
        for bad in ('"Bad Id", { order = 1, time = { 1, 2 }, heal = { open = 1 } }',
                    '"x", { order = 1 }',                                         # ni durée ni corps étranger
                    '"x", { order = 1, time = { 5, 2 }, heal = { open = 1 } }',   # bornes inversées
                    '"x", { order = 1, time = { 1, 2 }, heal = { open = -1 } }',
                    '"x", { order = 1, time = { 1, 2 }, heal = { open = 1 }, blood = 3 }'):
            with self.subTest(bad=bad):
                self.assertFalse(self.ev(f'(pcall({W}.registerKind, {bad}))'))
        self.assertEqual(self.ev(f'#{W}.kinds()'), 8)

    def test_new_kind_without_engine_change(self):
        self.run_lua(f'{W}.registerKind("frostbite", {{ order = 90, time = {{ 4, 4 }}, heal = {{ open = 1e-4 }} }})')
        self.wound('frostbite', 'Foot_L')
        self.assertEqual(self.ev('w1.time'), 4)
        self.run_lua(f'R = {W}.advance(L, 4 / 1e-4 / {TPM} + 1, C)')
        self.assertEqual(self.ev('#L'), 0)

    def test_vanilla_numbers_of_each_kind(self):
        """Constantes de BodyPart.java (docstring du module) recopiées dans chaque fichier de type."""
        for kind, fields in VANILLA.items():
            for field, expected in fields.items():
                with self.subTest(kind=kind, field=field):
                    got = self.ev(f'{W}.kind("{kind}").{field}')
                    if isinstance(expected, dict):
                        for k, v in expected.items():
                            self.assertAlmostEqual(got[k], v, places=12, msg=f'{kind}.{field}.{k}')
                    elif isinstance(expected, list):
                        self.assertEqual([got[1], got[2]], expected)
                    else:
                        self.assertAlmostEqual(got, expected, places=12)

    def test_kind_flags_for_care_and_virus(self):
        S = f'{W}.kind'
        self.assertTrue(self.ev(f'{S}("deep").stitch and {S}("fracture").splint and {S}("bite").infectedOnAdd'))
        self.assertEqual(self.ev(f'{S}("bullet").foreign.becomes'), 'deep')
        self.assertEqual(list(self.ev(f'{S}("bullet").foreign.time').values()), [17, 23])
        self.assertEqual(self.ev(f'{S}("glass").foreign.becomes'), 'deep')
        self.assertIsNone(self.ev(f'{S}("glass").foreign.time'))
        self.assertFalse(self.ev(f'{S}("scratch").bleedOnAdd'))   # griffure de zombie : pas de generateBleeding
        self.assertIsNone(self.ev(f'{S}("burn").infect'))          # brûlure seule hors de la porte d'infection :219

    def test_parts_in_vanilla_order_with_blood_mapping(self):
        self.assertEqual(self.ev(f'#{W}.PARTS'), 17)
        for i, (pid, pain, dmg, bleed, bandage) in enumerate(PARTS, start=1):
            with self.subTest(part=pid):
                p = self.ev(f'{W}.PARTS[{i}]')
                self.assertEqual((p['id'], p['blood'], p['bandage']), (pid, pid, bandage))
                self.assertEqual((p['pain'], p['damage'], p['bleed']), (pain, dmg, bleed))
                self.assertEqual(p['scaler'], 5 if pid == 'Neck' else 1)
                self.assertEqual(self.ev(f'{W}.PART["{pid}"].id'), pid)

    # ------------------------------------------------------------------ création
    def test_add_rolls_from_the_kind_range_deterministically(self):
        self.wound('scratch', 'Hand_L')
        self.assertEqual(self.ev('w1.time'), 11)        # 7 + 8 x 0.5
        self.assertEqual(self.ev('w1.bleed'), 0)        # griffure de zombie : pas de saignement
        self.wound('scratch', 'Hand_L', opts='{ bleed = true }')
        self.assertAlmostEqual(self.ev('w1.bleed'), 11 * 0.45 * 0.2)   # 0.3-0.6 x durée (:1783) x main 0.2
        self.wound('bite', 'ForeArm_L')
        self.assertEqual(self.ev('w1.time'), 65)
        self.assertAlmostEqual(self.ev('w1.bleed'), 11.25 * 0.3)       # 7.5-15 (:1801) x avant-bras 0.3
        self.assertTrue(self.ev('w1.infected'))                          # SetBitten pose l'infection de plaie :608
        self.wound('bite', 'ForeArm_L', ctx_extra=', severity = 3')    # InjurySeverity 3 : x 1.5 (:693-696, :1806-1813)
        self.assertEqual(self.ev('w1.time'), 97.5)
        self.assertAlmostEqual(self.ev('w1.bleed'), 11.25 * 1.5 * 0.3)
        a = self.ev(f'(function() local L1, L2 = {{}}, {{}} '
                    f'{W}.add(L1, "Neck", "glass", {{ rnd = seq({{ 0.1, 0.7, 0.3 }}) }}) '
                    f'{W}.add(L2, "Neck", "glass", {{ rnd = seq({{ 0.1, 0.7, 0.3 }}) }}) '
                    f'return {W}.pack(L1) == {W}.pack(L2) end)()')
        self.assertTrue(a)
        self.assertIsNone(self.ev(f'({W}.add({{}}, "Tail", "scratch", C))'))
        self.assertIsNone(self.ev(f'({W}.add({{}}, "Hand_L", "nope", C))'))
        self.assertFalse(self.ev(f'(pcall({W}.add, {{}}, "Hand_L", "scratch", {{}}))'))   # ctx.rnd exigé

    # ------------------------------------------------------------------ saignement
    def test_bleeding_is_the_sum_of_open_wounds_per_game_hour(self):
        self.run_lua(f'C = {{ rnd = seq({{ 0.5 }}) }}; L = {{}}; a = {W}.add(L, "ForeArm_L", "bite", C); '
                     f'b = {W}.add(L, "Neck", "laceration", C)')
        bite, cut = 11.25 * 0.3, 15 * 0.85 * 1.5
        self.assertAlmostEqual(self.ev('a.bleed'), bite)
        self.assertAlmostEqual(self.ev('b.bleed'), cut)
        per_hour = (bleed_points_per_tick(bite) + bleed_points_per_tick(cut, 5)) * TPM * 60 / 100
        self.assertAlmostEqual(self.ev(f'{W}.bleeding(L)'), per_hour, places=9)
        self.run_lua(f'{W}.bandage(b, 4, false)')
        self.assertAlmostEqual(self.ev(f'{W}.bleeding(L)'), bleed_points_per_tick(bite) * TPM * 60 / 100, places=9)

    def test_advance_bleed_loss_and_part_damage_match_vanilla(self):
        self.wound('bite', 'ForeArm_L')
        b0 = 11.25 * 0.3
        ticks = 30 * TPM
        b1 = b0 - 2e-5 * ticks
        r = self.ev(f'{W}.advance(L, 30, C)')
        bled = BLEED * DS * ((b0 + b1) / 2) / 10 * ticks
        harm = 2.1875 * DS * ticks                       # dégâts de partie (:158-160), sous le plafond de 100
        self.assertAlmostEqual(r['bled'], bled, places=6)
        self.assertAlmostEqual(r['harmed'], harm * 0.2, places=6)   # santé générale : x modificateur de partie
        self.assertAlmostEqual(r['hpLoss'], (bled + harm * 0.2) / 100, places=8)
        self.assertAlmostEqual(self.ev('w1.bleed'), b1, places=9)
        self.assertAlmostEqual(self.ev('w1.level'), 1e-5 * ticks, places=9)   # morsure infectée qui s'aggrave :287
        self.assertEqual(self.ev('w1.age'), 30)
        # Plafond : une partie ne perd pas plus de 100 points (BodyPart.ReduceHealth :450-452).
        r = self.ev(f'{W}.advance(L, 60, C)')
        self.assertAlmostEqual(self.ev('w1.harm'), 100, places=6)
        self.assertAlmostEqual(r['harmed'], (100 - harm) * 0.2, places=6)

    def test_split_advance_equals_one_advance(self):
        self.wound('laceration', 'UpperLeg_R')
        self.run_lua(f'L2 = {{}}; {W}.add(L2, "UpperLeg_R", "laceration", {{ rnd = seq({{ 0.5 }}) }}); '
                     f'C2 = {{ rnd = {NEVER} }}')
        one = self.ev(f'{W}.advance(L, 120, C).hpLoss')
        two = self.ev(f'{W}.advance(L2, 45, C2).hpLoss + {W}.advance(L2, 75, C2).hpLoss')
        self.assertAlmostEqual(one, two, places=9)
        self.assertEqual(self.ev(f'{W}.pack(L)'), self.ev(f'{W}.pack(L2)'))

    # ------------------------------------------------------------------ bandage
    def test_clean_bandage_stops_bleeding_heals_and_wears(self):
        self.wound('scratch', 'Hand_L', opts='{ bleed = true }')
        self.run_lua(f'{W}.bandage(w1, 5, false)')
        r = self.ev(f'{W}.advance(L, 300, C)')
        self.assertEqual(r['bled'], 0)                    # bandé : aucune perte par saignement (:161)
        self.assertEqual(r['harmed'], 0)                  # griffure bandée : aucun dégât (:152)
        self.assertAlmostEqual(self.ev('w1.time'), 11 - 1.5e-4 * 300 * TPM, places=9)   # :308
        # Usure : 8e-5 (griffure, :309) + 3e-4 tant qu'elle saigne (:208).
        self.assertTrue(self.ev('w1.bandage.life < 5'))
        heal_minutes = 11 / 1.5e-4 / TPM                  # 407.4 minutes de jeu
        self.run_lua(f'R = {W}.advance(L, {heal_minutes - 300 - 1}, C)')
        self.assertEqual(self.ev('#L'), 1)
        self.run_lua(f'R = {W}.advance(L, 2, C)')
        self.assertEqual(self.ev('#L'), 0)
        self.assertEqual(self.ev('#R.healed'), 1)
        self.assertEqual(self.ev('R.healed[1].kind'), 'scratch')

    def test_deep_wound_soaks_its_bandage_and_dirty_bandage_still_covers(self):
        self.wound('deep', 'Torso_Upper')
        self.run_lua(f'{W}.bandage(w1, 4, false)')
        r = self.ev(f'{W}.advance(L, 10, C)')
        # 1e-4 (plaie profonde, :350) + 0.005 (saignement d'une plaie profonde, :206) : vide en 4 / 0.0051 ticks.
        self.assertEqual(self.ev('w1.bandage.life'), 0)
        self.assertEqual(r['bled'], 0)                    # bandage sale : toujours bandé (isBandageDirty :134)
        self.assertFalse(self.ev(f'{W}.isClean(w1)'))
        self.assertAlmostEqual(r['harmed'], 1.5625 * DS * 10 * TPM * 0.35, places=6)   # bandée : 1.5625 (:148)

    def test_unbandaged_deep_wound_never_closes(self):
        self.wound('deep', 'Torso_Upper')
        self.run_lua(f'R = {W}.advance(L, 50000, C)')
        self.assertEqual(self.ev('#L'), 1)
        self.assertEqual(self.ev('w1.time'), 3)           # plancher 3 sans bandage (:361-363)

    # ------------------------------------------------------------------ points et attelle
    def test_stitches_stop_bleeding_and_close_the_wound(self):
        self.wound('deep', 'Torso_Upper')
        self.assertTrue(self.ev(f'{W}.stitch(w1, 5)'))
        self.assertEqual((self.ev('w1.bleed'), self.ev('w1.time'), self.ev('w1.stitch')), (0, 0, 5))   # :876-882
        self.run_lua(f'{W}.bandage(w1, 10, true)')
        minutes = (50 - 5) / 5e-4 / TPM                   # 4e-4 + 1e-4 par tick bandé (:373, :378)
        self.run_lua(f'R = {W}.advance(L, {minutes - 1}, C)')
        self.assertEqual(self.ev('#L'), 1)
        self.run_lua(f'R = {W}.advance(L, 2, C)')
        self.assertEqual(self.ev('#L'), 0)
        # Sans bandage : 2e-4 par tick (:380).
        self.wound('deep', 'Torso_Upper')
        self.run_lua(f'{W}.stitch(w1, 5); R = {W}.advance(L, 60, C)')
        self.assertAlmostEqual(self.ev('w1.stitch'), 5 + 2e-4 * 60 * TPM, places=9)
        self.assertEqual(self.ev('R.bled + R.harmed'), 0)
        # Un éclat se retire avant de recoudre (ISHealthPanel.lua:1379) ; une griffure ne se recoud pas.
        self.wound('glass', 'Hand_R')
        self.assertFalse(self.ev(f'{W}.stitch(w1, 5)'))
        self.wound('scratch', 'Hand_R')
        self.assertFalse(self.ev(f'{W}.stitch(w1, 5)'))

    def test_splint_heals_the_fracture_and_stops_its_damage(self):
        self.wound('fracture', 'LowerLeg_L')
        self.assertEqual(self.ev('w1.time'), 65)
        r = self.ev(f'{W}.advance(L, 10, C)')
        self.assertAlmostEqual(r['harmed'], 3.125 * DS * 10 * TPM * 0.2, places=6)   # non attelée (:179-181)
        self.assertAlmostEqual(self.ev('w1.time'), 65 - 5e-6 * 10 * TPM, places=9)     # :396
        self.assertTrue(self.ev(f'{W}.splint(w1, 1.5)'))                                 # (docteur 2 + 1) / 2
        t0 = self.ev('w1.time')
        r = self.ev(f'{W}.advance(L, 10, C)')
        self.assertEqual(r['harmed'], 0)
        self.assertAlmostEqual(self.ev('w1.time'), t0 - 5e-5 * 1.5 * 10 * TPM, places=9)   # :394
        self.assertFalse(self.ev(f'{W}.splint({W}.add(L, "Hand_L", "scratch", C), 1)'))   # une griffure ne s'attelle pas

    # ------------------------------------------------------------------ infection de plaie
    def test_infection_chance_depends_on_bandage_and_disinfection(self):
        def chance():
            return self.ev(f'{W}.infectionChance(w1, C)')
        self.wound('laceration', 'Hand_L')
        self.assertAlmostEqual(chance(), ROLLS / 5000)            # 40000 - 10000 - 25000 = 5000 (:222-233)
        self.run_lua(f'{W}.bandage(w1, 3, false)')
        self.assertAlmostEqual(chance(), ROLLS / 15000)           # bandage propre : 40000 - 25000
        self.run_lua('w1.bandage.life = 0')
        self.assertAlmostEqual(chance(), ROLLS / 5000)            # bandage sale : - 35000, plancher 5000 (:226, :252)
        self.run_lua(f'{W}.bandage(w1, 3, true)')
        self.assertEqual(chance(), 0)                             # bandage à l'alcool encore bon (:219)
        self.run_lua(f'{W}.unbandage(w1); {W}.disinfect(w1, 1)')
        self.assertEqual(chance(), 0)                             # alcool sur la plaie : guérie au tick suivant
        self.wound('scratch', 'Hand_L')
        self.assertAlmostEqual(chance(), ROLLS / 10000)           # 40000 - 10000 - 20000
        self.run_lua('C.soiled = function(part) return true, true end')
        self.assertAlmostEqual(chance(), ROLLS / 5000)            # vêtement sale et sanglant (:246-251)
        for kind in ('bite', 'bullet', 'fracture', 'burn'):
            with self.subTest(kind=kind):
                self.wound(kind, 'Hand_L')
                self.assertEqual(chance(), 0)                     # hors de la porte de :219 (ou déjà infectée)

    def test_infection_rolls_use_the_injected_random(self):
        self.wound('laceration', 'Hand_L', after='function() return 0 end')
        r = self.ev(f'{W}.advance(L, 10, C)')
        self.assertEqual(self.ev(f'#{W}.advance(L, 0, C).infectedNow'), 0)
        self.assertEqual(len(r['infectedNow']), 1)
        self.assertTrue(self.ev('w1.infected'))
        self.wound('laceration', 'Hand_L')
        r = self.ev(f'{W}.advance(L, 10, C)')
        self.assertEqual(len(r['infectedNow']), 0)
        self.assertFalse(self.ev('w1.infected'))

    def test_infected_wound_worsens_and_disinfectant_cures_it(self):
        self.wound('laceration', 'Hand_L')
        self.run_lua('w1.infected = true')
        self.run_lua(f'{W}.advance(L, 60, C)')
        self.assertAlmostEqual(self.ev('w1.level'), 1e-5 * 60 * TPM, places=9)       # :287
        self.assertTrue(self.ev(f'{W}.pain(L) > 0'))
        self.wound('glass', 'Hand_L')
        self.run_lua(f'w1.infected = true; {W}.advance(L, 60, C)')
        self.assertAlmostEqual(self.ev('w1.level'), 1e-4 * 60 * TPM, places=9)       # éclat dans la plaie :284-285
        self.run_lua(f'{W}.disinfect(w1, 3)')                                         # ISDisinfect.lua:71
        self.run_lua(f'{W}.advance(L, 1, C)')
        self.assertAlmostEqual(self.ev('w1.level'), 1.08 - 2e-4 * TPM, places=9)     # :261-262
        self.run_lua(f'{W}.advance(L, 60, C)')
        self.assertFalse(self.ev('w1.infected'))
        self.assertAlmostEqual(self.ev('w1.alcohol'), 3 - 2e-4 * 61 * TPM, places=6)

    # ------------------------------------------------------------------ retrait d'un corps étranger
    def test_extracting_a_bullet_leaves_a_deep_wound(self):
        self.wound('bullet', 'ForeArm_R', after='seq({ 0.5 })')
        self.assertAlmostEqual(self.ev('w1.bleed'), 7.5 * 0.3)        # 5-10 (:1798)
        self.assertTrue(self.ev('w1.foreign'))
        self.assertTrue(self.ev(f'{W}.extract(w1, C, 3)'))
        self.assertEqual((self.ev('w1.kind'), self.ev('w1.foreign')), ('deep', False))
        self.assertEqual(self.ev('w1.time'), 20 - 1)                     # 17-23 - docteur / 2 entier (:1076)
        self.assertAlmostEqual(self.ev('w1.bleed'), 19 * 0.85 * 0.3)     # generateBleeding de la plaie profonde
        self.assertFalse(self.ev(f'{W}.extract(w1, C, 0)'))
        self.wound('glass', 'Hand_R')
        t, b = self.ev('w1.time'), self.ev('w1.bleed')
        self.assertTrue(self.ev(f'{W}.extract(w1, C, 0)'))                # setHaveGlass(false) : plaie gardée
        self.assertEqual((self.ev('w1.kind'), self.ev('w1.time'), self.ev('w1.bleed')), ('deep', t, b))

    # ------------------------------------------------------------------ soins demandés
    def care(self, i=1):
        return self.ev(f'(function() for _, e in ipairs({W}.needs(L)) do if e.wound == L[{i}] then '
                       'return table.concat(e.care, ",") end end return "" end)()')

    def test_needs_list_the_care_each_wound_asks_for(self):
        self.wound('bullet', 'ForeArm_R')
        self.assertEqual(self.care(), 'remove,bandage')
        self.run_lua(f'{W}.extract(w1, C, 0)')
        self.assertEqual(self.care(), 'stitch,bandage')
        self.run_lua(f'{W}.stitch(w1, 5); {W}.bandage(w1, 0, false)')
        self.assertEqual(self.care(), 'change')
        self.run_lua('w1.infected = true')
        self.assertEqual(self.care(), 'disinfect,change')
        self.wound('fracture', 'LowerLeg_L')
        self.assertEqual(self.care(), 'splint')
        self.run_lua(f'{W}.splint(w1, 1)')
        self.assertEqual(self.care(), '')
        self.assertIsNone(self.ev(f'{W}.worst(L)'))

    def test_worst_is_the_wound_that_bleeds_most(self):
        self.run_lua(f'C = {{ rnd = seq({{ 0.5 }}) }}; L = {{}}; {W}.add(L, "LowerLeg_L", "fracture", C); '
                     f'{W}.add(L, "Hand_L", "laceration", C); {W}.add(L, "Neck", "bite", C)')
        self.assertEqual(self.ev(f'{W}.worst(L).wound.part'), 'Neck')
        self.assertEqual(self.ev(f'#{W}.needs(L)'), 3)
        self.assertEqual(self.ev(f'{W}.needs(L)[3].wound.kind'), 'fracture')   # ne saigne pas : dernière

    def test_new_need_without_engine_change(self):
        self.run_lua(f'{W}.registerNeed({{ id = "rest", order = 99, test = function(w) return w.kind == "burn" end }})')
        self.wound('burn', 'Hand_L')
        self.assertEqual(self.care(), 'bandage,rest')

    # ------------------------------------------------------------------ sang visible
    def test_blood_per_visual_part(self):
        self.wound('bite', 'Neck')
        blood = self.ev(f'{W}.blood(L)')
        self.assertEqual(list(blood.keys()), ['Neck'])
        self.assertTrue(0 < blood['Neck'] <= 1)

    # ------------------------------------------------------------------ forme sauvegardée
    def test_pack_unpack_round_trip(self):
        self.run_lua(f'C = {{ rnd = seq({{ 0.37, 0.81, 0.999999 }}) }}; L = {{}}; '
                     f'for _, k in ipairs({{ "scratch", "laceration", "deep", "bite", "bullet", "glass", "fracture", '
                     f'"burn" }}) do {W}.add(L, "Head", k, C) end; '
                     f'{W}.bandage(L[2], 2.5, true); {W}.stitch(L[3], 4.2); {W}.splint(L[7], 1); '
                     f'{W}.disinfect(L[1], 0.5); {W}.advance(L, 37.5, C)')
        text = self.ev(f'{W}.pack(L)')
        self.assertTrue(text.isascii())
        self.assertEqual(text.count(';'), 7)
        self.assertEqual(self.ev(f'{W}.pack({W}.unpack({W}.pack(L)))'), text)
        self.assertTrue(self.ev(f'{W}.valid(L)'))
        self.assertEqual(self.ev(f'#{W}.unpack("")'), 0)
        self.assertEqual(self.ev(f'{W}.pack({{}})'), '')

    def test_unpack_refuses_bad_input(self):
        self.wound('laceration', 'Hand_L')
        good = self.ev(f'{W}.pack(L)')
        fields = good.split(':')
        self.assertEqual(len(fields), 14)

        def with_field(i, value):
            f = list(fields)
            f[i] = value
            return ':'.join(f)
        bad = [None, 5, 'x', good + ':1', 'zz' + good[len('laceration'):], with_field(1, 'Tail'),
               with_field(2, 'abc'), with_field(3, 'nan'), with_field(3, '1e999'), with_field(4, '-1'),
               with_field(5, '1000'), with_field(7, '60'), with_field(9, '1'), with_field(10, '2'),
               with_field(11, '11'), with_field(13, '101'), ';'.join([good] * 65)]
        self.run_lua(f'BAD = {{}}')
        for i, b in enumerate(bad, start=1):
            with self.subTest(bad=b if b is None or len(str(b)) < 80 else str(b)[:80]):
                self.rt.globals().BAD[i] = b
                self.assertIsNone(self.ev(f'({W}.unpack(BAD[{i}]))'))
        self.assertFalse(self.ev(f'({W}.valid({{ {{ kind = "nope", part = "Hand_L" }} }}))'))
        self.assertFalse(self.ev(f'({W}.valid("x"))'))

    # ------------------------------------------------------------------ règles du chantier
    def test_engine_is_pure_and_names_no_kind(self):
        sources = [ENGINE.with_name(f'{m}.lua') for m in MODULES] + sorted(KIND_DIR.glob('LK_Wound_*.lua'))
        game = re.compile(r'\b(getPlayer|getGameTime|getSandboxOptions|SandboxVars|ZombRand\w*|isServer|isClient|'
                          r'getCore|sendServerCommand|sendClientCommand|Events|getCell|getWorld)\b')
        for path in sources:
            code = '\n'.join(line.split('--', 1)[0] for line in path.read_text(encoding='utf-8').splitlines())
            with self.subTest(file=path.name):
                self.assertIsNone(game.search(code))
                self.assertNotIn('next(', code)
                self.assertTrue(code.isascii(), 'non-ASCII outside comments (Kahlua lexer)')
        engine = '\n'.join(line.split('--', 1)[0] for line in ENGINE.read_text(encoding='utf-8').splitlines())
        for kind in KINDS:
            self.assertNotIn(f'"{kind}"', engine)


class VanillaHealthScaleTests(unittest.TestCase):
    """LK21-T02 : santé générale perdue sous une plaie, modèle (Wounds.advance puis Wounds.regeneration et
    Wounds.healthCap, comme LK_Health.bleedPass chaque minute) contre un joueur vanilla éveillé et nourri simulé tick
    par tick (tests/livingknox/test_lk_health.py, vanilla_loss : BodyDamage.java:917-944, :1887-1928, :2079-2089 ;
    BodyPart.java:145-181, :204, :211). Tirages médians. Vanilla : (a) profonde au torse 41 points en 1 h, mort vers
    17 h ; (b) coupure à l'avant-bras 21 ; (c) morsure à l'avant-bras 21 (sans virus) ; (d) profonde bandée 26."""

    setUp, ev, run_lua, wound = WoundsTests.setUp, WoundsTests.ev, WoundsTests.run_lua, WoundsTests.wound

    CASES = [('Torso_Upper', 'deep', 3.125, 0.85 * 17.5 * 0.5, False),
             ('ForeArm_L', 'laceration', 1.875, 0.85 * 15 * 0.3, False),
             ('ForeArm_L', 'bite', 2.1875, 11.25 * 0.3, False),
             ('Torso_Upper', 'deep', 1.5625, 0.85 * 17.5 * 0.5, True)]

    def model_loss(self, part, kind, bandaged, minutes):
        return self.ev(f'''(function()
            local W = {W}
            local C = {{ rnd = function() return 0.5 end }}
            local L = {{}}
            W.add(L, "{part}", "{kind}", C)
            if {'true' if bandaged else 'false'} then W.bandage(L[1], 5, false) end
            C.rnd = {NEVER}
            local hp = 1
            for m = 1, {minutes} do
                local lowered = hp - W.advance(L, 1, C).hpLoss
                hp = lowered
                if hp <= 0 then return 1 end
                local cap = W.healthCap(L)
                local general = hp < cap - 1e-9
                local gain = W.regeneration(L, 1, C, general)
                if general then hp = math.min(cap, hp + gain) else hp = math.min(1, hp + gain) end
                if hp < lowered then hp = lowered end
            end
            return 1 - hp
        end)()''')

    def test_one_hour_loss_matches_a_vanilla_player(self):
        from test_lk_health import vanilla_loss
        for part, kind, damage, bleed, bandaged in self.CASES:
            with self.subTest(kind=kind, bandaged=bandaged):
                vanilla = vanilla_loss(part, damage, bleed, 60, bandaged) / 100
                self.assertAlmostEqual(self.model_loss(part, kind, bandaged, 60), vanilla, delta=0.02)

    def test_regeneration_spread_or_held(self):
        # Perte générale à rattraper : 0.002 x 180 x (somme des parts sans la partie tenue) / 17 par minute.
        self.wound('deep', 'Torso_Upper')
        held = sum(p[2] for p in PARTS) - 0.35
        self.assertAlmostEqual(self.ev(f'{W}.regeneration(L, 1, C, true)'), 0.002 * TPM * held / 17 / 100, places=9)
        # Sans perte générale : REGEN partagé entre les parties tenues, retiré de leurs dégâts.
        self.run_lua(f'{W}.advance(L, 10, C)')
        harm = self.ev('w1.harm')
        gain = self.ev(f'{W}.regeneration(L, 1, C, false)')
        self.assertAlmostEqual(self.ev('w1.harm'), harm - 0.002 * TPM, places=9)
        self.assertAlmostEqual(gain, 0.002 * TPM * 0.35 / 100, places=9)
        self.assertAlmostEqual(self.ev(f'{W}.healthCap(L)'), 1 - self.ev('w1.harm') * 0.35 / 100, places=9)
        # Plaie qui n'abîme plus (coupure bandée) : la partie n'est plus tenue, la santé remonte jusqu'au plein.
        self.wound('laceration', 'Hand_L')
        self.run_lua(f'{W}.advance(L, 10, C); {W}.bandage(w1, 4, false)')
        self.assertEqual(self.ev(f'{W}.healthCap(L)'), 1)


if __name__ == '__main__':
    unittest.main(verbosity=1)
