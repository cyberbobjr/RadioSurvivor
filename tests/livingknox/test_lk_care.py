"""Tests hors jeu du saignement et des soins des PNJ Living Knox (LK07-T03, LK21-T05) : server/LivingKnox/LK_Health.lua
(section « saignement » : Health.bleeding, bleedPass, stopBleeding), server/LivingKnox/LK_Care.lua (blessés, soignant,
soin le plus urgent, matériel pris, gestes, soin appliqué une fois), le registre des soins (LK_CareTreatments.lua,
server/LivingKnox/Care/LK_Treat_<Id>.lua), les sources de matériel (LK_CareSupplies.lua, Care/LK_CareSource_<Id>.lua)
et l'extension de recouvrement inscrite dans LivingKnox.Decisions (ADR adr-blessures-soins.md D05, D06).

    python tests/livingknox/test_lk_care.py

Pile complète des repas réels (test_lk_meals.MealStack : groupe « deciders » dans la maison HOUSE, vrais LK_Homes et
LK_Stock, caisse de la cuisine en 112,112) + LK_Health, les plaies et les soins, en solo (marche simulée). Doublures
ajoutées, relevées dans le Java 42.22 (J = zombie/) : InventoryItem.isCanBandage (J/inventory/InventoryItem.java:2617),
getBandagePower (:3103), isAlcoholic (:3087), getAlcoholPower (:3095), IsDrainable (:1981), getCurrentUses (:2321),
getCurrentUsesFloat (:2334), hasTag (:2677), getType, getFullType, Use (:1153-1200 : une utilisation, ReplaceOnUse
ajouté au conteneur, retiré à 0) ; ItemContainer.containsID (J/inventory/ItemContainer.java:2966) ; FluidContainer
getAmount (:520), getProperties (:476), adjustAmount (:647), SealedFluidProperties.getAlcohol (:341) ;
IsoGameCharacter.getInventory (inventaire du corps) ; étiquettes ItemTag (J/scripting/objects/ItemTag.java:347-438).
Objets (media/scripts/generated/items 42.22) : Bandage (BandagePower 4, ReplaceOnUse BandageDirty), BandageDirty
(0,5, ReusableBandage), AlcoholWipes (AlcoholPower 4, 5 utilisations), Disinfectant (0,5 l d'alcool), Thread
(20 utilisations), Needle (SewingNeedle), SutureNeedle, Splint, Tweezers (RemoveBullet, RemoveGlass).
Elles NE PROUVENT PAS l'API réelle ni le rendu des gestes : seulement la logique (matériel réel pris et consommé une
fois, référence du stock à jour sans perte ni vol, effet sur la plaie, soin le plus urgent d'abord). Rendu et réseau :
en jeu (suite lk.care).
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
W = 'LivingKnox.Wounds'
CA = 'LivingKnox.Care'
ST = 'LivingKnox.Stock'
ROOT = Path(__file__).resolve().parents[2]
HEALTH = 'server/LivingKnox/LK_Health.lua'
CARE = 'server/LivingKnox/LK_Care.lua'
LUA_ROOT = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'
CARE_DIR = LUA_ROOT / 'server' / 'LivingKnox' / 'Care'
SUITE = 'shared/RST/suites/RST_LKCare.lua'
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
SUITE_FILE = tests_lua('lk') / SUITE
MEDIC_LEVEL = 3   # LK_Care.lua, Care.CFG.LEVEL.medic
ONE_MINUTE = 2e-4 * 180   # une minute de jeu (180 ticks) d'alcool évaporé ou de points qui tiennent, à nu (2e-4 par tick)


def care_files():
    """LK21-T05 : sources de matériel et soins (server/LivingKnox/Care/), chargés par le jeu, triés par nom ; chacun
    s'inscrit à son registre."""
    return [f'server/LivingKnox/Care/{p.name}' for p in sorted(CARE_DIR.glob('*.lua'), key=lambda p: p.name.lower())]


CARE_DOUBLES = r'''
local HH = HARNESS
local C = HH.classes
local Item = C.InventoryItem
function Item:getFullType() return self.t end
function Item:getType() return (string.gsub(self.t, '^.-%.', '')) end
function Item:isCanBandage() return rawget(self, 'band') ~= nil end
function Item:getBandagePower() return rawget(self, 'band') or 0 end
function Item:isAlcoholic() return rawget(self, 'alcoholic') == true end
function Item:getAlcoholPower() return rawget(self, 'apower') or 0 end
function Item:IsDrainable() return rawget(self, 'drain') == true end
function Item:getCurrentUses() return rawget(self, 'uses') or 1 end
function Item:getCurrentUsesFloat() return (rawget(self, 'uses') or 1) * (rawget(self, 'delta') or 1) end
function Item:hasTag(tag)
    if type(tag) ~= 'string' then error('No implementation found for hasTag', 2) end
    local tags = rawget(self, 'tags')
    return tags ~= nil and tags[tag] == true
end
ItemTag = { REUSABLE_BANDAGE = 'base:reusablebandage', REMOVE_GLASS = 'base:removeglass',
    REMOVE_BULLET = 'base:removebullet', SEWING_NEEDLE = 'base:sewingneedle', THREAD = 'base:thread' }
-- Conteneur d'un objet suivi par AddItem / DoRemoveItem (InventoryItem.container, Use le lit).
local Ctr = C.ItemContainer
local add, remove = Ctr.AddItem, Ctr.DoRemoveItem
function Ctr:AddItem(it)
    rawset(it, 'ctr', self)
    return add(self, it)
end
function Ctr:DoRemoveItem(it)
    if type(it) == 'table' and rawget(it, 'ctr') == self then rawset(it, 'ctr', nil) end
    return remove(self, it)
end
-- InventoryItem.Use (J/inventory/InventoryItem.java:1153-1200) : une utilisation ; ReplaceOnUse ajouté au conteneur ;
-- retiré du conteneur à 0.
function Item:Use()
    self.uses = (rawget(self, 'uses') or 1) - 1
    local ctr = rawget(self, 'ctr')
    if rawget(self, 'replace') ~= nil and ctr ~= nil then ctr:AddItem(instanceItem(self.replace)) end
    if self.uses <= 0 and ctr ~= nil then
        HH.listRemove(ctr.items, self)
        self.ctr = nil
    end
end
local FC = C.FluidContainer
local Props = HH.class('SealedFluidProperties')
function FC:getAmount() return self.amount or 0 end
function FC:getProperties() return setmetatable({ alcohol = (self.alcohol or 0) }, Props) end
function FC:adjustAmount(v)
    if type(v) ~= 'number' then error('No implementation found for adjustAmount', 2) end
    local ratio = (self.amount or 0) > 0 and (self.alcohol or 0) / self.amount or 0
    self.amount = v
    self.alcohol = v * ratio
end
function Props:getAlcohol() return self.alcohol end
local Z = C.IsoZombie
function Z:getInventory()
    local inv = rawget(self, 'inv')
    if not inv then inv = NEW_CTR('none') self.inv = inv end
    return inv
end
function Z:isInvulnerable() return self.invulnerable == true end
function Z:setInvulnerable(b)
    if type(b) ~= 'boolean' then error('No implementation found for setInvulnerable', 2) end
    self.invulnerable = b
end
function Z:isFakeDead() return self.fakeDead == true end
function Z:setFakeDead(b) self.fakeDead = b end
-- Objet de soin : champs du script (band = BandagePower, uses, delta, drain, apower, tags, replace, alcoholic,
-- fluid = { amount, alcohol }).
function CARE_ITEM(t, o)
    o = o or {}
    local it = MEAL_ITEM(t, { cat = o.cat or 'FirstAid' })
    for k, v in pairs(o) do
        if k ~= 'cat' and k ~= 'fluid' then it[k] = v end
    end
    if o.fluid ~= nil then
        it.fc = setmetatable({ fluid = Fluid.Water, amount = o.fluid.amount, alcohol = o.fluid.alcohol }, FC)
    end
    return it
end
local prevInstance = instanceItem
CARE_CREATED = {}
instanceItem = function(t)
    if t == 'Base.Bandage' then
        CARE_CREATED[#CARE_CREATED + 1] = t
        return CARE_ITEM(t, { band = 4, replace = 'Base.BandageDirty' })
    end
    if t == 'Base.BandageDirty' then
        CARE_CREATED[#CARE_CREATED + 1] = t
        return CARE_ITEM(t, { band = 0.5, tags = { ['base:reusablebandage'] = true } })
    end
    if t == 'Base.SutureNeedle' then return CARE_ITEM(t) end
    return prevInstance(t)
end
-- Types (triés) des objets d'un inventaire de corps.
function INV_TYPES(z)
    local out = {}
    for _, it in ipairs(z:getInventory():getItems().items) do out[#out + 1] = it:getFullType() end
    table.sort(out)
    return table.concat(out, ',')
end
'''

# Bandes sales d'abord dans la caisse, puis un pansement propre (préféré).
SUPPLIES = r'''
DIRTY = CARE_ITEM('Base.BandageDirty', { band = 0.5, tags = { ['base:reusablebandage'] = true } })
CLEAN = CARE_ITEM('Base.Bandage', { band = 4, replace = 'Base.BandageDirty' })
PANTRY.container:AddItem(DIRTY)
PANTRY.container:AddItem(CLEAN)
'''

# Objets des soins (scripts 42.22), créés par le test à la demande.
ITEMS = {
    'wipes': "CARE_ITEM('Base.AlcoholWipes', { drain = true, apower = 4, uses = 5, delta = 0.2 })",
    'bottle': "CARE_ITEM('Base.Disinfectant', { fluid = { amount = 0.5, alcohol = 0.5 } })",
    'needle': "CARE_ITEM('Base.Needle', { tags = { ['base:sewingneedle'] = true } })",
    'thread': "CARE_ITEM('Base.Thread', { drain = true, uses = 20, delta = 0.05, tags = { ['base:thread'] = true } })",
    'suture': "CARE_ITEM('Base.SutureNeedle')",
    'splint': "CARE_ITEM('Base.Splint')",
    'tweezers': "CARE_ITEM('Base.Tweezers', { tags = { ['base:removebullet'] = true, ['base:removeglass'] = true } })",
}


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
        for path in care_files():
            h.load('solo', path)
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

    def add_wound(self, gid, mid, kind, part, lua=''):
        """Plaie de type kind posée directement (Wounds.add, tirage 0,2), puis lua sur la plaie w ; plaies enregistrées."""
        self.run_lua(fixed_rnd(0.2))
        self.run_lua(f'local id = MEMBER_NPC("{gid}", "{mid}") local L = {H}.wounds(id) '
                     f'local w = assert({W}.add(L, "{part}", "{kind}", LivingKnox.WoundContext.current())) {lua} '
                     f'{H}.woundsChanged(id)')

    def wounds(self, gid, mid):
        return lua_list(self.ev(f'{H}.wounds(MEMBER_NPC("{gid}", "{mid}"))'))

    def put(self, where, gid, mid, *names):
        """Objets ITEMS posés dans la caisse (where = "stock") ou l'inventaire du corps du membre mid ; rend leurs id."""
        ids = []
        for name in names:
            if where == 'stock':
                ids.append(self.run_lua(f'local it = {ITEMS[name]} PANTRY.container:AddItem(it) return it.id'))
            else:
                ids.append(self.run_lua(f'local it = {ITEMS[name]} MAT_BODY("{gid}", "{mid}"):getInventory():AddItem(it) '
                                        'return it.id'))
        if where == 'stock':
            self.run_lua(f'{ST}.check("{gid}", {{ force = true }})')
        return ids

    def inv(self, gid, mid):
        return self.ev(f'INV_TYPES(MAT_BODY("{gid}", "{mid}"))')

    def empty_stock(self, gid):
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, CLEAN) HARNESS.listRemove(PANTRY.container.items, '
                     'DIRTY)')
        self.run_lua(f'{ST}.check("{gid}", {{ force = true }})')

    def care(self, gid, mid):
        return self.run_lua(f'local m = {CA}.get(MEMBER_NPC("{gid}", "{mid}")) if m == nil then return nil end '
                            'return m.phase, m.pmid, m.plan and m.plan.id or nil')

    def gesture(self, gid, mid):
        return self.ev(f'LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "{mid}"))')

    def care_log(self, gid):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'care']

    def run_until(self, cond, seconds=200, walk=1.0, watch=None):
        for _ in range(seconds):
            self.dpass(1, walk=walk)
            self.h.advance(1)
            if watch is not None:
                watch()
            if cond():
                return True
        return False

    def treated(self, n=1, seconds=200, watch=None):
        return self.run_until(lambda: self.ev(f'{CA}.stats.treated') >= n, seconds=seconds, watch=watch)


class PureCareTests(CareStack):
    def test_care_gestures_are_existing_generated_nodes(self):
        table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        gestures = {self.ev(f'{CA}.TAKE_GESTURE')}
        for t in lua_list(self.ev(f'{CA}.treatmentList')):
            gestures.add(self.ev(f'{CA}.gestureOf({CA}.treatmentById["{t.id}"])'))
        for g in gestures:
            self.assertIn(g, table['gestures'])
            self.assertTrue(any(['LKGesture', 'STRING', g] in n['conditions'] for n in table['nodes']), g)

    def test_treatments_answer_registered_wound_needs(self):
        ids = sorted(t.id for t in lua_list(self.ev(f'{CA}.treatmentList')))
        self.assertEqual(ids, ['bandage', 'changebandage', 'disinfect', 'removebullet', 'removeglass', 'splint',
                               'stitch'])
        for i in ids:
            self.assertIsNotNone(self.ev(f'{W}.needById[{CA}.treatmentById["{i}"].need]'), i)
        sources = [s.id for s in lua_list(self.ev(f'{CA}.supplySources'))]
        self.assertEqual(sources, ['carer', 'patient', 'stock'])                 # porté d'abord, puis le foyer

    def test_most_urgent_feasible_treatment_first(self):
        # Griffure à la main (ne saigne pas) et plaie profonde au torse (saigne) : la plaie qui saigne d'abord, et pour
        # elle les points avant le bandage (ordre des besoins, ISHealthPanel) ; sans aiguille, le bandage ; sans rien,
        # aucun soin (raison "material").
        self.run_lua(f'CTX = {{ rnd = function() return 0.2 end }} L = {{}} '
                     f'{W}.add(L, "Hand_L", "scratch", CTX, {{ bleed = false }}) {W}.add(L, "Torso_Upper", "deep", CTX)')
        plan = self.ev(f'({CA}.choose(L, CTX, function() return {{}} end))')
        self.assertEqual((plan.id, plan.part, plan.option), ('stitch', 'Torso_Upper', 1))
        plan = self.ev(f'({CA}.choose(L, CTX, function(o) if o.materials[1] and o.materials[1].id == "bandage" then '
                       'return {} end return nil end))')
        self.assertEqual((plan.id, plan.part), ('bandage', 'Torso_Upper'))
        self.assertEqual(self.run_lua(f'return {CA}.choose(L, CTX, function() return nil end)'), (None, 'material'))
        self.assertEqual(self.run_lua(f'return {CA}.choose({{}}, CTX, function() return {{}} end)'), (None, 'none'))

    def test_care_is_a_registered_cover_extension_of_the_decisions(self):
        # Extension « care » : recouvrement (cover -> Care.apply) et oubli (forget -> Care.leave), sans comportement.
        self.run_lua(f'CALLED = {{}} local a, l = {CA}.apply, {CA}.leave '
                     f'{CA}.apply = function(id) CALLED[#CALLED + 1] = "apply " .. id return true end '
                     f'{CA}.leave = function(id) CALLED[#CALLED + 1] = "leave " .. id return true end '
                     f'for _, x in ipairs({D}.extensions) do if x.id == "care" then '
                     'EXT = { x.apply == nil and x.leave == nil, x.cover("n-1", {}, {}, true), x.forget("n-2") } end end '
                     f'{CA}.apply, {CA}.leave = a, l')
        self.assertEqual(lua_list(self.ev('EXT')), [True, True, True])
        self.assertEqual(lua_list(self.ev('CALLED')), ['apply n-1', 'leave n-2'])
        # Une extension de recouvrement tient le membre avant la routine (Decisions.apply).
        self.run_lua(f'COVERED = {{}} {D}.registerExtension({{ id = "zz_cover", order = 999, '
                     'cover = function(id, st) COVERED[#COVERED + 1] = st.b return true end })')
        gid = self.mk()
        self.dpass(2)
        self.assertGreater(self.ev('#COVERED'), 0)
        self.run_lua(f'for i = #{D}.extensions, 1, -1 do if {D}.extensions[i].id == "zz_cover" then '
                     f'table.remove({D}.extensions, i) end end')
        self.assertEqual(self.h.errors('solo'), [], gid)


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
    def test_medic_bandages_with_one_clean_bandage_from_the_stock(self):
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-1', 0.3)
        self.assertGreater(self.bleed(gid, 'm-1'), 0)
        before_box, before_ref = self.box_ids(), self.ref_ids(gid)
        clean = self.ev('CLEAN.id')
        seen = set()

        def watch():
            seen.add((self.care(gid, 'm-3') or (None,))[0])
            seen.add(self.gesture(gid, 'm-3'))
        self.run_lua(fixed_rnd(0.5))
        self.assertTrue(self.treated(watch=watch), (self.care(gid, 'm-3'), self.lk()[-8:]))
        self.assertIn('rummage', seen)
        self.assertIn('kneel', seen)
        self.assertIn('patient', seen)
        self.assertEqual(self.bleed(gid, 'm-1'), 0)
        w = self.wounds(gid, 'm-1')[0]
        # ISApplyBandage.lua:112 : vie tirée dans [(niveau + 1) x 0,5, (niveau + 1)] (tirage 0,5) + BandagePower 4.
        life = (MEDIC_LEVEL + 1) * 0.5 + 0.5 * (MEDIC_LEVEL + 1) * 0.5 + 4
        self.assertAlmostEqual(w.bandage.life, life, delta=0.06)                # usure d'une minute (Wounds.advance)
        self.assertEqual((w.bandage.item, w.bandage.alcohol), ('Base.Bandage', False))
        self.assertIn(':Base.Bandage', self.npc(gid, 'm-1', 'wounds'))           # type gardé avec la plaie
        # Le pansement propre seul est sorti de la caisse et de la référence, puis consommé : ni perte ni vol.
        self.assertEqual(self.box_ids(), [i for i in before_box if i != clean])
        self.assertEqual(self.ref_ids(gid), [i for i in before_ref if i != clean])
        self.assertEqual(self.inv(gid, 'm-3'), '')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        log = self.care_log(gid)
        self.assertEqual(len(log), 1)
        self.assertTrue(log[0].startswith('m-3 treated m-1: bandage on Hand_L with Base.Bandage'), log)
        for _ in range(3):
            self.dpass(1)
            self.h.advance(1)
        self.assertIsNone(self.care(gid, 'm-3'))
        # Geste du soin retiré à la fin ; la routine reprend (une corvée peut s'agenouiller à son tour).
        self.assertNotEqual(self.gesture(gid, 'm-3'), 'rummage')
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 1)
        self.assertEqual(self.ev(f'{CA}.stats.selfCare'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_dirty_bandage_is_changed_and_returned_dirty(self):
        gid = self.mk()
        self.jump_to(11)
        self.add_wound(gid, 'm-1', 'laceration', 'ForeArm_R',
                       f'w.bleed = 0 {W}.bandage(w, 0, false) w.bandage.item = "Base.Bandage"')
        self.assertTrue(self.treated(), self.lk()[-8:])
        w = self.wounds(gid, 'm-1')[0]
        self.assertGreater(w.bandage.life, 4)                                     # pansement propre neuf
        self.assertEqual(w.bandage.item, 'Base.Bandage')
        # ISApplyBandage.lua:128-140 : l'ancien bandage revient au soignant, sale (Use : ReplaceOnUse BandageDirty).
        self.assertEqual(self.inv(gid, 'm-3'), 'Base.BandageDirty')
        self.assertTrue(self.care_log(gid)[0].startswith('m-3 treated m-1: changebandage on ForeArm_R'))

    def test_infected_wound_is_disinfected_with_the_medic_wipes_before_the_bandage(self):
        gid = self.mk()
        self.jump_to(11)
        self.add_wound(gid, 'm-1', 'scratch', 'Hand_R', 'w.bleed = 0 w.infected = true')
        self.put('medic', gid, 'm-3', 'wipes')
        seen = set()
        self.assertTrue(self.treated(watch=lambda: seen.add(self.gesture(gid, 'm-3'))), self.lk()[-8:])
        self.assertNotIn('rummage', seen)                                        # porté : pas de détour au stock
        w = self.wounds(gid, 'm-1')[0]
        # AlcoholPower 4 (ISDisinfect.lua:71), moins une minute d'évaporation (2e-4 par tick, BodyPart.java:258-305).
        self.assertAlmostEqual(w.alcohol, 4 - ONE_MINUTE, places=6)
        self.assertIsNone(w.bandage)
        self.assertEqual(self.ev(f'MAT_BODY("{gid}", "m-3"):getInventory():getItems().items[1].uses'), 4)
        self.assertTrue(self.care_log(gid)[0].startswith('m-3 treated m-1: disinfect on Hand_R with Base.AlcoholWipes'))
        self.assertTrue(self.treated(2), self.lk()[-8:])                          # puis le bandage
        self.assertIsNotNone(self.wounds(gid, 'm-1')[0].bandage)

    def test_disinfectant_bottle_from_the_stock_loses_one_dose(self):
        gid = self.mk()
        self.jump_to(11)
        self.add_wound(gid, 'm-1', 'scratch', 'Hand_R', 'w.bleed = 0 w.infected = true')
        self.put('stock', gid, 'm-3', 'bottle')
        self.assertTrue(self.treated(), self.lk()[-8:])
        self.assertAlmostEqual(self.wounds(gid, 'm-1')[0].alcohol, 4 * 0.5 / 0.5 - ONE_MINUTE, places=6)   # :76
        self.assertAlmostEqual(self.ev(f'MAT_BODY("{gid}", "m-3"):getInventory():getItems().items[1].fc.amount'),
                               0.35, places=6)                                   # 0,15 l pris (:83-84)

    def test_deep_wound_is_stitched_with_needle_and_thread_then_bandaged(self):
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-1', 0.2, part='Torso_Upper', source='blade', rnd=0.1)
        self.put('stock', gid, 'm-3', 'needle', 'thread')
        self.run_lua(fixed_rnd(0.5))
        self.assertTrue(self.treated(), self.lk()[-8:])
        w = self.wounds(gid, 'm-1')[0]
        self.assertEqual(w.kind, 'deep')
        # ISStitch.lua:118-120 : (1 + niveau) / 2 x [2, 5] (tirage 0,5) ; saignement et durée arrêtés (setStitched).
        self.assertAlmostEqual(w.stitch, (1 + MEDIC_LEVEL) / 2 * 3.5 + ONE_MINUTE, places=6)   # + 2e-4 par tick (:371)
        self.assertEqual((w.bleed, w.time), (0, 0))
        self.assertFalse(w.infected)                       # tirage 0,5 x (5 + 3 x 2,5) : pas 0 (ISStitch.lua:123)
        self.assertEqual(self.inv(gid, 'm-3'), 'Base.Needle,Base.Thread')         # aiguille gardée, fil entamé
        self.assertEqual(self.ev(f'(function() for _, it in ipairs(MAT_BODY("{gid}", "m-3"):getInventory():getItems()'
                                 '.items) do if it.t == "Base.Thread" then return it.uses end end end)()'), 19)
        self.assertTrue(self.care_log(gid)[0].startswith('m-3 treated m-1: stitch on Torso_Upper'))
        self.assertTrue(self.treated(2), self.lk()[-8:])
        self.assertIsNotNone(self.wounds(gid, 'm-1')[0].bandage)                 # puis le pansement

    def test_suture_needle_carried_by_the_patient_is_used_up(self):
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-1', 0.2, part='Torso_Upper', source='blade', rnd=0.1)
        self.put('patient', gid, 'm-1', 'suture')
        self.assertTrue(self.treated(), self.lk()[-8:])
        self.assertIsNotNone(self.wounds(gid, 'm-1')[0].stitch)
        self.assertEqual((self.inv(gid, 'm-1'), self.inv(gid, 'm-3')), ('', ''))  # utilisée une fois (ISStitch:101)

    def test_fracture_gets_a_splint(self):
        gid = self.mk()
        self.jump_to(11)
        self.add_wound(gid, 'm-1', 'fracture', 'LowerLeg_L')
        self.put('stock', gid, 'm-3', 'splint')
        self.assertTrue(self.treated(), self.lk()[-8:])
        self.assertEqual(self.wounds(gid, 'm-1')[0].splint, (MEDIC_LEVEL + 1) / 2)   # ISSplint.lua:90
        self.assertEqual(self.inv(gid, 'm-3'), '')                                # attelle retirée (:101)

    def test_bullet_is_removed_with_tweezers_kept_by_the_medic(self):
        gid = self.mk()
        self.jump_to(11)
        self.add_wound(gid, 'm-1', 'bullet', 'UpperArm_L')
        self.put('stock', gid, 'm-3', 'tweezers')
        self.assertTrue(self.treated(), self.lk()[-8:])
        w = self.wounds(gid, 'm-1')[0]
        self.assertEqual((w.kind, w.foreign), ('deep', False))                     # setHaveBullet(false)
        self.assertEqual(self.inv(gid, 'm-3'), 'Base.Tweezers')

    def test_glass_is_removed_by_hand_without_tool(self):
        gid = self.mk()
        self.jump_to(11)
        self.empty_stock(gid)
        self.add_wound(gid, 'm-1', 'glass', 'Hand_L')
        self.assertTrue(self.treated(), self.lk()[-8:])
        w = self.wounds(gid, 'm-1')[0]
        self.assertEqual((w.kind, w.foreign), ('deep', False))
        self.assertTrue(self.care_log(gid)[0].startswith('m-3 treated m-1: removeglass on Hand_L with bare hands'))

    def test_member_without_medic_treats_itself(self):
        self.CREW = MealStack.CREW
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-2', 0.3)
        self.assertTrue(self.treated(), (self.care(gid, 'm-2'), self.lk()[-8:]))
        self.assertEqual(self.ev(f'{CA}.stats.selfCare'), 1)
        self.assertEqual(self.bleed(gid, 'm-2'), 0)
        self.assertTrue(self.care_log(gid)[0].startswith('m-2 treated its own wound: bandage on Hand_L'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_bleeding_medic_treats_itself_first(self):
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-3', 0.2)
        self.assertTrue(self.treated())
        self.assertTrue(self.care_log(gid)[0].startswith('m-3 treated its own wound'), self.care_log(gid))

    def test_no_material_no_care_shortage_once_and_bleeding_goes_on(self):
        gid = self.mk()
        self.empty_stock(gid)
        self.jump_to(11)
        self.wound(gid, 'm-1', 0.3)
        self.assertTrue(self.run_until(lambda: self.ev(f'{CA}.stats.shortages') >= 1, seconds=30))
        for _ in range(10):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.ev(f'{CA}.stats.shortages'), 1)                   # mis de côté : une seule fois
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 0)
        self.assertGreater(self.bleed(gid, 'm-1'), 0)
        self.assertIsNone(self.wounds(gid, 'm-1')[0].bandage)
        log = [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'shortage']
        self.assertEqual(len(log), 1)
        self.assertTrue(log[0].startswith('no bandage to treat a wound left for m-3'), log)
        self.assertEqual(self.h.errors('solo'), [])

    def test_threat_interrupts_the_care_and_the_taken_bandage_stays_with_the_medic(self):
        gid = self.mk()
        self.jump_to(11)
        self.wound(gid, 'm-1', 0.3)
        npc = self.npc_of(gid, 'm-3')
        self.assertTrue(self.run_until(lambda: (self.care(gid, 'm-3') or (None,))[0] in ('patient', 'pface',
                                                                                        'treat')))
        x, y = self.body_xy(gid, 'm-3')
        self.run_lua(f'SEE_ZOMBIE("{npc}", {int(x) + 3}, {int(y)}, 3, 960)')
        self.dpass(2)
        self.assertIsNone(self.care(gid, 'm-3'))
        self.assertEqual(self.ev(f'{CA}.stats.treated'), 0)                     # rien posé : soin interrompu
        self.assertGreater(self.bleed(gid, 'm-1'), 0)
        self.assertEqual(self.inv(gid, 'm-3'), 'Base.Bandage')                   # pris, gardé par le médecin
        box = self.box_ids()
        self.run_lua('PERCEPTION = {}')
        self.assertTrue(self.treated(), self.lk()[-8:])                          # repris avec le pansement porté
        self.assertEqual(self.bleed(gid, 'm-1'), 0)
        self.assertEqual(self.inv(gid, 'm-3'), '')
        self.assertEqual(self.box_ids(), box)                                    # rien de plus pris au stock
        self.assertEqual(self.h.errors('solo'), [])


class SuiteTests(CareStack):
    CREW = MealStack.CREW

    def test_suite_lk_care_passes_on_the_doubles(self, start=(9, 0)):
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
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
                     '[LKC] measure stitched: ', '[LKC] measure bandaged: '):
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
        paths = [CARE, 'server/LivingKnox/LK_CareTreatments.lua', 'server/LivingKnox/LK_CareSupplies.lua',
                 *care_files()]
        for path in paths:
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
            for path in ('server/LivingKnox/LK_CareTreatments.lua', 'server/LivingKnox/LK_CareSupplies.lua',
                         *care_files()):
                h.load(c, path)
            self.assertIsNone(h.eval(c, 'LivingKnox.Care'))


if __name__ == '__main__':
    unittest.main(verbosity=1)
