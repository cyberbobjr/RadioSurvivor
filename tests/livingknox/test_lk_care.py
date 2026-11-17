"""Tests hors jeu du saignement et des soins des PNJ Living Knox (LK07-T03) : server/LivingKnox/LK_Health.lua (section
« saignement » : Health.bleeding, bleedPass, stopBleeding, blessure qui fait saigner), server/LivingKnox/LK_Care.lua
(blessés, soigneur, objet pris au stock, gestes, soin appliqué une fois, Care.afterAttack) et le point d'appel de
LivingKnox.Decisions.apply.

    python tests/livingknox/test_lk_care.py

Pile complète des repas réels (test_lk_meals.MealStack : groupe « deciders » dans la maison HOUSE, vrais LK_Homes et
LK_Stock, caisse de la cuisine en 112,112) + LK_Health et LK_Care, en solo (marche simulée). Doublures ajoutées,
relevées dans le Java 42.21.0 : InventoryItem.isCanBandage (InventoryItem.java:2607, script CanBandage),
getBandagePower (:3088 ; Bandage 4, BandageDirty 0,5 : media/scripts/generated/items/normal.txt) ; zombie
setInvulnerable / isInvulnerable, isFakeDead / setFakeDead. Elles NE PROUVENT PAS l'API réelle ni le rendu des
gestes : seulement la logique (objet retiré une fois, référence du stock à jour sans perte ni vol, saignement arrêté,
santé rendue une fois, mort par perte de sang décidée une fois). Rendu et réseau : en jeu.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from phase_sweep import WORLDS, other_groups, sweep  # noqa: E402
from harness import lua_src  # noqa: E402  (E18-T07)
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_meals import MealStack  # noqa: E402
from test_lk_health import fixed_rnd, regen_per_minute, vanilla_loss, wound_files  # noqa: E402  (LK21-T02)

D = 'LivingKnox.Decisions'
H = 'LivingKnox.Health'
CA = 'LivingKnox.Care'
ST = 'LivingKnox.Stock'
ROOT = Path(__file__).resolve().parents[2]
HEALTH = 'server/LivingKnox/LK_Health.lua'
CARE = 'server/LivingKnox/LK_Care.lua'
LUA_ROOT = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'
SUITE = 'shared/RST/suites/RST_LKCare.lua'
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
SUITE_FILE = tests_lua('lk') / SUITE

CARE_DOUBLES = r'''
local HH = HARNESS
local C = HH.classes
local Item = C.InventoryItem
function Item:isCanBandage() return rawget(self, 'band') ~= nil end
function Item:getBandagePower() return rawget(self, 'band') or 0 end
local Z = C.IsoZombie
function Z:isInvulnerable() return self.invulnerable == true end
function Z:setInvulnerable(b)
    if type(b) ~= 'boolean' then error('No implementation found for setInvulnerable', 2) end
    self.invulnerable = b
end
function Z:isFakeDead() return self.fakeDead == true end
function Z:setFakeDead(b) self.fakeDead = b end
-- Objet de soin : CanBandage, BandagePower, catégorie d'affichage du script.
function CARE_ITEM(t, power, cat)
    local it = MEAL_ITEM(t, { cat = cat or 'FirstAid' })
    it.band = power
    return it
end
'''

# Bandes sales d'abord dans la caisse, puis un pansement propre (préféré).
SUPPLIES = r'''
DIRTY = CARE_ITEM('Base.BandageDirty', 0.5)
CLEAN = CARE_ITEM('Base.Bandage', 4)
PANTRY.container:AddItem(DIRTY)
PANTRY.container:AddItem(CLEAN)
'''


class CareStack(MealStack):
    """Pile des repas + santé de référence et soins ; équipe : combattant m-1, ouvrier m-2, médecin m-3."""

    mode = 'solo'
    CREW = [('fighter', 'gunner', 'false'), ('worker', 'cook', 'false'), ('medic', 'doc', 'true')]

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', CARE_DOUBLES)
        h.load('solo', HEALTH)
        for path in wound_files():
            h.load('solo', path)
        h.load('solo', CARE)
        h.load('solo', SUPPLIES)
        return h

    def mk(self):
        gid = super().mk()
        self.run_lua(f'{CA}.reset() for k in pairs({CA}.stats) do {CA}.stats[k] = 0 end')
        return gid

    def full(self, gid, mid):
        return self.ev(f'{H}.get(MEMBER_NPC("{gid}", "{mid}")).max')

    def hp(self, gid, mid):
        return self.ev(f'{H}.get(MEMBER_NPC("{gid}", "{mid}")).hp')

    def bleed(self, gid, mid):
        return self.ev(f'{H}.bleeding(MEMBER_NPC("{gid}", "{mid}"))')

    def wound(self, gid, mid, fraction, part='Hand_L', source='blunt', rnd=0.2):
        """Blessure de fraction x santé de naissance, par le chemin des coups (Health.applyHit), plaie faite par la
        source nommée avec un tirage fixe (LK21-T02). Par défaut : coupure de contondant (tirage 0,2 : 1 sur 4) à la
        main gauche, qui saigne ; source "blade", tirage 0,1 : plaie profonde (1 sur 6)."""
        self.run_lua(fixed_rnd(rnd))
        return self.run_lua(f'local id = MEMBER_NPC("{gid}", "{mid}") local z = MAT_BODY("{gid}", "{mid}") '
                            f'local full = {H}.get(id).max '
                            f'return {H}.applyHit(id, z, full * {fraction}, "{part}", nil, nil, '
                            f'{{ source = "{source}" }})')

    def care(self, gid, mid):
        return self.run_lua(f'local m = {CA}.get(MEMBER_NPC("{gid}", "{mid}")) if m == nil then return nil end '
                            'return m.phase, m.pmid, m.took and m.took.t or nil')

    def gesture(self, gid, mid):
        return self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{mid}"))')

    def care_log(self, gid):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'care']


class PureCareTests(CareStack):
    def test_care_gestures_are_existing_generated_nodes(self):
        table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        for g in (self.ev(f'{CA}.TAKE_GESTURE'), self.ev(f'{CA}.TREAT_GESTURE')):
            self.assertIn(g, table['gestures'])
            self.assertTrue(any(['LKGesture', 'STRING', g] in n['conditions'] for n in table['nodes']), g)

    def test_care_items_are_what_vanilla_accepts_for_bandaging(self):
        self.assertTrue(self.ev(f'{CA}.isCareItem(CLEAN)'))
        self.assertTrue(self.ev(f'{CA}.isCareItem(DIRTY)'))
        self.assertFalse(self.ev(f'{CA}.isCareItem(BEANS[1])'))
        self.assertFalse(self.ev(f'{CA}.isCareItem(MEAL_ITEM("Base.Pills", {{ cat = "FirstAid" }}))'))
        self.assertFalse(self.ev(f'{CA}.isCareItem(nil)'))


TPM = 180                 # ticks vanilla par minute de jeu (2 x 90 minutes par jour, LK_Wounds.lua en-tête)
DS = 0.0057142857         # BodyPart.java:30 (damageScaler)
BLEED = 0.2857143         # BodyPart.java:29 (bleedDamage)


def bleed_per_hour(bleed):
    """Fraction de la santé perdue par heure par un saignement bleed (BodyPart.java:161-163)."""
    return BLEED * DS * bleed / 10 * TPM * 60 / 100


class BleedingTests(CareStack):
    """LK21-T02 (ADR adr-blessures-soins.md D03) : le saignement vient des plaies (Wounds.bleeding) et la santé suit
    leur évolution (saignement et dégâts de partie, Wounds.advance). Les attendus de LK07-T03 (saignement unique de
    0,5 x fraction retirée, moitié toutes les 3 heures, plafond MAX) sont remplacés par les règles du vanilla."""

    def test_wound_bleeds_and_unattended_bleeding_kills_once(self):
        gid = self.mk()
        self.run_lua(f'{CA}.state.aside["{gid}"] = 1e9')                          # aucun soin
        full = self.full(gid, 'm-1')
        hp = self.wound(gid, 'm-1', 0.4, part='Torso_Upper', source='blade', rnd=0.1)
        self.assertAlmostEqual(hp, full * 0.6, places=3)
        bleed = (0.7 + 0.3 * 0.1) * (15 + 5 * 0.1) * 0.5                        # plaie profonde au torse
        self.assertAlmostEqual(self.bleed(gid, 'm-1'), bleed_per_hour(bleed), places=6)
        self.assertEqual(self.ev(f'{H}.get(MEMBER_NPC("{gid}", "m-1")).bleed'), self.bleed(gid, 'm-1'))
        self.assertRegex(self.npc(gid, 'm-1', 'wounds'), r'^deep:Torso_Upper:')   # sauvegardée avec le registre
        self.assertIsNone(self.npc(gid, 'm-1', 'bleed'))
        self.h.advance(1)                                                        # premier passage : repère
        before = self.hp(gid, 'm-1')
        self.h.advance(60)
        lost = before - self.hp(gid, 'm-1')
        # Perte du joueur vanilla sous la même plaie en une heure (oracle vanilla_loss : dégâts de partie, saignement,
        # régénération), environ 39 points sur 100 ; écart toléré 2 points.
        self.assertAlmostEqual(lost / full, vanilla_loss('Torso_Upper', 3.125, bleed, 61) / 100, delta=0.02)
        self.assertLess(self.bleed(gid, 'm-1'), bleed_per_hour(bleed))          # le saignement décroît
        # Une seconde plaie profonde (ventre) : la régénération du vanilla (environ 6 points par heure) ne suit plus le
        # saignement des deux plaies ; sans soin, mort dans la journée.
        self.wound(gid, 'm-1', 0.01, part='Torso_Lower', source='blade', rnd=0.1)
        for _ in range(24 * 60):
            self.h.advance(1)
            if self.ev(f'{H}.stats.bleedDeaths') > 0:
                break
        self.assertEqual(self.ev(f'{H}.stats.bleedDeaths'), 1)
        self.assertEqual(self.ev(f'{H}.stats.deaths'), 1)
        self.assertEqual(self.ev(f'{H}.stats.engineDeaths'), 0)
        self.assertFalse(self.member(gid, 'm-1', 'alive'))
        self.assertTrue(any('bled to death' in line for line in self.lk()))
        self.h.advance(30)
        self.assertEqual(self.ev(f'{H}.stats.deaths'), 1)                       # une seule mort
        self.assertEqual(self.h.errors('solo'), [])

    def test_small_wound_stops_bleeding_on_its_own(self):
        gid = self.mk()
        self.run_lua(f'{CA}.state.aside["{gid}"] = 1e9')
        self.wound(gid, 'm-2', 0.02)                                             # coupure à la main
        bleed = (0.7 + 0.3 * 0.2) * (10 + 10 * 0.2) * 0.2
        self.assertAlmostEqual(self.bleed(gid, 'm-2'), bleed_per_hour(bleed), places=6)
        minutes = bleed / (2e-5 * TPM)                                           # 2e-5 par tick à nu (:211)
        self.h.advance(1)
        self.h.advance(int(minutes) + 2)
        self.assertEqual(self.bleed(gid, 'm-2'), 0)
        self.assertEqual(self.ev(f'#{H}.get(MEMBER_NPC("{gid}", "m-2")).wounds'), 1)   # la coupure reste, sans saigner
        self.assertTrue(self.member(gid, 'm-2', 'alive'))
        self.assertGreater(self.hp(gid, 'm-2'), self.full(gid, 'm-2') * 0.7)
        self.assertEqual(self.ev(f'{H}.stats.bleedStops'), 1)

    def test_bandage_stops_the_loss_and_only_heal_raises_the_reference(self):
        gid = self.mk()
        self.run_lua(f'{CA}.state.aside["{gid}"] = 1e9')
        self.wound(gid, 'm-2', 0.1, part='Torso_Upper')
        self.wound(gid, 'm-2', 0.1, part='ForeArm_R')
        both = self.bleed(gid, 'm-2')
        self.assertEqual(self.ev(f'#{H}.get(MEMBER_NPC("{gid}", "m-2")).wounds'), 2)
        before = self.hp(gid, 'm-2')
        self.assertAlmostEqual(self.ev(f'{H}.stopBleeding(MEMBER_NPC("{gid}", "m-2"))'), both, places=9)
        self.assertEqual(self.bleed(gid, 'm-2'), 0)
        self.h.advance(30)
        # Bandées : plus aucune perte ; la santé remonte par la régénération du vanilla (29 minutes après le repère).
        gained = self.hp(gid, 'm-2') - before
        self.assertAlmostEqual(gained, regen_per_minute() * 29 * self.full(gid, 'm-2'), delta=self.full(gid, 'm-2') * 0.003)


class SoloCareTests(CareStack):
    def run_until(self, cond, seconds=200, walk=1.0, watch=None):
        for _ in range(seconds):
            self.dpass(1, walk=walk)
            self.h.advance(1)
            if watch is not None:
                watch()
            if cond():
                return True
        return False

    def test_medic_takes_one_clean_bandage_and_treats_the_bleeding_member(self):
        gid = self.mk()
        self.jump_to(11)
        full = self.full(gid, 'm-1')
        self.wound(gid, 'm-1', 0.3)
        self.assertGreater(self.bleed(gid, 'm-1'), 0)
        before_box, before_ref = self.box_ids(), self.ref_ids(gid)
        clean = self.ev('CLEAN.id')
        seen = set()

        def watch():
            seen.add((self.care(gid, 'm-3') or (None,))[0])
            seen.add(self.gesture(gid, 'm-3'))
        hp_low = []

        def treated():
            hp_low.append(self.hp(gid, 'm-1'))
            return self.ev(f'{CA}.stats.treated') >= 1
        self.assertTrue(self.run_until(treated, watch=watch), (self.care(gid, 'm-3'), self.lk()[-8:]))
        self.assertIn('rummage', seen)
        self.assertIn('kneel', seen)
        self.assertIn('patient', seen)
        self.assertEqual(self.bleed(gid, 'm-1'), 0)
        heal = 0.03 * 4 * full * 1.5                                              # pansement 4, médecin x 1,5
        self.assertAlmostEqual(self.hp(gid, 'm-1') - min(hp_low[:-1]), heal, delta=full * 0.01)
        # Un seul objet retiré (le pansement propre), ôté de la référence : ni perte ni vol à la relecture.
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual(self.box_ids(), [i for i in before_box if i != clean])
        self.assertEqual(self.ref_ids(gid), [i for i in before_ref if i != clean])
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        log = self.care_log(gid)
        self.assertEqual(len(log), 1)
        self.assertTrue(log[0].startswith('m-3 treated m-1 with Base.Bandage'), log)
        # Médecin à côté du blessé au moment du soin, puis remis debout ; plus de tâche.
        for _ in range(3):
            self.dpass(1)
            self.h.advance(1)
        self.assertIsNone(self.care(gid, 'm-3'))
        self.assertNotIn(self.gesture(gid, 'm-3'), ('kneel', 'rummage'))
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 1)
        self.assertEqual(self.ev(f'{CA}.stats.selfCare'), 0)
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_member_without_medic_treats_itself(self):
        self.CREW = MealStack.CREW
        gid = self.mk()
        self.jump_to(11)
        full = self.full(gid, 'm-2')
        self.wound(gid, 'm-2', 0.3)
        hp_low = []

        def treated():
            hp_low.append(self.hp(gid, 'm-2'))
            return self.ev(f'{CA}.stats.treated') >= 1
        self.assertTrue(self.run_until(treated), (self.care(gid, 'm-2'), self.lk()[-8:]))
        self.assertEqual(self.ev(f'{CA}.stats.selfCare'), 1)
        self.assertEqual(self.bleed(gid, 'm-2'), 0)
        self.assertAlmostEqual(self.hp(gid, 'm-2') - min(hp_low[:-1]), 0.03 * 4 * full, delta=full * 0.01)
        self.assertTrue(self.care_log(gid)[0].startswith('m-2 treated its own wound with Base.Bandage'))
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_bleeding_medic_treats_itself_first(self):
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-3', 0.2)
        self.assertTrue(self.run_until(lambda: self.ev(f'{CA}.stats.treated') >= 1))
        self.assertTrue(self.care_log(gid)[0].startswith('m-3 treated its own wound'), self.care_log(gid))

    def test_empty_stock_raises_the_shortage_and_bleeding_goes_on(self):
        gid = self.mk()
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, CLEAN) HARNESS.listRemove(PANTRY.container.items, '
                     'DIRTY)')
        self.run_lua(f'{ST}.check("{gid}", {{ force = true }})')
        self.jump_to(11)
        self.wound(gid, 'm-1', 0.3)
        self.assertTrue(self.run_until(lambda: self.ev(f'{CA}.stats.shortages') >= 1, seconds=30))
        for _ in range(10):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.ev(f'{CA}.stats.shortages'), 1)                   # mis de côté : une seule fois
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 0)
        self.assertGreater(self.bleed(gid, 'm-1'), 0)
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 0)
        log = [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'shortage']
        self.assertEqual(len(log), 1)
        self.assertTrue(log[0].startswith('no bandage to treat a wound left for m-3'), log)
        self.assertEqual(self.h.errors('solo'), [])

    def test_wounded_noted_after_an_attack_are_treated_without_bleeding(self):
        gid = self.mk()
        self.jump_to(11)
        full = self.full(gid, 'm-2')
        self.run_lua(f'local id = MEMBER_NPC("{gid}", "m-2") LivingKnox.Store.data().npcs[id].hp = {full * 0.6}')
        n = self.ev(f'{CA}.afterAttack("{gid}", {{ minute = {D}.currentMinute(), wounded = {{ "m-2" }} }})')
        self.assertEqual(n, 1)
        start = self.ev(f'{D}.currentMinute()')
        self.assertTrue(self.run_until(lambda: self.ev(f'{CA}.stats.treated') >= 1))
        # Soin (+ 0,03 x 4 x 1,5) et régénération du vanilla pendant les minutes passées (LK21-T02).
        minutes = self.ev(f'{D}.currentMinute()') - start
        cared = full * 0.6 + 0.03 * 4 * full * 1.5
        self.assertGreaterEqual(self.hp(gid, 'm-2'), cared - 1e-3)
        self.assertLessEqual(self.hp(gid, 'm-2'), cared + regen_per_minute() * (minutes + 1) * full + 1e-3)
        self.assertTrue(self.care_log(gid)[0].startswith('m-3 treated m-2'), self.care_log(gid))
        for _ in range(5):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 1)                      # note consommée : une fois
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)

    def test_threat_after_the_take_applies_the_care_once(self):
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-1', 0.3)
        npc = self.npc_of(gid, 'm-3')
        self.assertTrue(self.run_until(lambda: (self.care(gid, 'm-3') or (None,))[0] in ('patient', 'pface',
                                                                                        'treat')))
        self.assertGreater(self.bleed(gid, 'm-1'), 0)
        x, y = self.body_xy(gid, 'm-3')
        self.run_lua(f'SEE_ZOMBIE("{npc}", {int(x) + 3}, {int(y)}, 3, 960)')
        self.dpass(2)
        self.assertIsNone(self.care(gid, 'm-3'))
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 1)                      # objet pris : soin appliqué
        self.assertEqual(self.bleed(gid, 'm-1'), 0)
        self.run_lua('PERCEPTION = {}')
        for _ in range(10):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 1)
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual(self.h.errors('solo'), [])


class SuiteTests(CareStack):
    CREW = MealStack.CREW

    def test_suite_lk_care_passes_on_the_doubles(self, start=(9, 0)):
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', r'''
            local mk = instanceItem
            instanceItem = function(t)
                if t == 'Base.Bandage' then return CARE_ITEM(t, 4) end
                return mk(t)
            end''')
        self.h.move_player('A', 110, 110)
        if start is not None:
            self.h.jump_to(*start)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.care", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.care')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.care", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(6000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 10 == 9:
                self.h.advance(1)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKC' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKC] measure stock of ', '[LKC] measure wounded: ', '[LKC] measure bleeding: ',
                     '[LKC] measure treated: '):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), other_groups(self))
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_lk_care_passes_under_the_phase_sweep(self):
        """E19-T05 : changement d'heure, de jour, nuit et aube à des instants différents de la scène."""
        sweep(self, lambda phase: self.test_suite_lk_care_passes_on_the_doubles(start=None), worlds=WORLDS)

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)

    def test_mod_sources_are_ascii_safe_for_kahlua(self):
        for path in (CARE,):
            raw = lua_src(path, LUA_ROOT).read_bytes()
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('utf-8'), flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), path)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.'):
                self.assertIsNone(re.search(pattern, code), (path, pattern))


class MultiplayerCareTests(MealStack):
    mode = 'mp'

    def test_clients_stop_at_the_guard(self):
        h = self.h
        for c in ('A', 'B'):
            h.load(c, CARE)
            self.assertIsNone(h.eval(c, 'LivingKnox.Care'))


if __name__ == '__main__':
    unittest.main(verbosity=1)
