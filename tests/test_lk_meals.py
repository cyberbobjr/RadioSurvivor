"""Tests hors jeu des repas réels des PNJ Living Knox pris dans le stock du foyer (LK05-T07) :
server/LivingKnox/LK_Routines.lua (section « repas réels », comportement « meal »), LK_Stock.lua (findMeal, takeMeal,
reportShortage, consumable), LK_Needs.lua (relieve, realMeals), LK_Decisions.lua (règles hunger/thirst, ctx.meals,
ctx.unfed) et la suite en jeu lk.meals (dev/.../RST_LKMeals.lua) dans le banc.

    python RadioSurvivor/tests/test_lk_meals.py

Bancs :
- logique pure (cascade : faim et soif -> « meal » au foyer, « home » loin du foyer ou sans routine des repas, besoin mis
  de côté -> règle suivante ; gestes du repas présents dans tools/anim_table.json) ;
- pile complète (groupe « deciders » de test_lk_routines.py dans la maison HOUSE, vrais LK_Homes et LK_Stock, foyer
  marqué aménagé sans pose par LivingKnox.Homes.skip) : solo (marche simulée) et serveur dédié + deux clients.
Doublures ajoutées, relevées dans le Java 42.21.0 :
- objets : InventoryItem.getID (InventoryItemFactory.java:126), getDisplayCategory (:2873), getFluidContainer, isCooked
  (:2413) ; Food (sous-classe) isRotten, isFrozen, isbDangerousUncooked (Food.java:1653, 1974, 1671) ; FluidContainer
  isEmpty, getPrimaryFluid ; Fluid.Water / TaintedWater ;
- conteneur d'un meuble (IsoObject.getContainerCount / getContainerByIndex, IsoObject.java:4822-4840) : ItemContainer
  getType, getItems, DoRemoveItem (ItemContainer.java:1979, une seule surcharge ; objet compté), containsID,
  getItemWithIDRecursiv ; sendRemoveItemFromContainer (LuaManager.java:9734 : envoi par le serveur seulement, aux
  clients proches du meuble, GameServer.java:2269-2277) compté sur le serveur ;
- BuildingDef.isFullyStreamedIn vrai (LK_Homes.ready).
Elles NE PROUVENT PAS l'API réelle ni le rendu des gestes : seulement la logique (un objet retiré une fois, référence à
jour sans perte ni vol, rien de créé, faim baissée une fois, pénurie au journal, mêmes consignes chez deux clients).
Le rendu et l'envoi réel se vérifient en jeu (suite lk.meals, puis séance MP).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from test_lk_routines import TIME_OF_DAY, RoutineStack  # noqa: E402

R = 'LivingKnox.Routines'
D = 'LivingKnox.Decisions'
ST = 'LivingKnox.Stock'
N = 'LivingKnox.Needs'
ROOT = Path(__file__).resolve().parents[1]
SUITE = 'shared/RST/suites/RST_LKMeals.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE

MEAL_DOUBLES = r'''
local H = HARNESS
local C = H.classes
MEAL_COUNT = { removed = 0, sent = 0 }
MEAL_SENT = {}
local FluidCls = H.class('Fluid')
Fluid = {}
for _, n in ipairs({ 'Water', 'TaintedWater', 'Cola' }) do Fluid[n] = setmetatable({ name = n }, FluidCls) end
local FC = H.class('FluidContainer')
function FC:isEmpty() return self.fluid == nil or (self.amount or 0) <= 0 end
function FC:getPrimaryFluid() return self.fluid end
local Item = C.InventoryItem
local Food = H.class('Food', Item)
function Item:getID() return self.id end
function Item:getDisplayCategory() return self.cat end
function Item:getFluidContainer() return rawget(self, 'fc') end
function Item:hasModData() return false end
function Item:isCooked() return self.cooked == true end
function Food:isRotten() return self.rotten == true end
function Food:isFrozen() return self.frozen == true end
function Food:isbDangerousUncooked() return self.raw == true end
MEAL_NEXT = 5000
-- Objet de repas : nourriture (Food), bouteille (fluide au choix, vide si amount = 0), autre objet (cat donnée).
function MEAL_ITEM(t, o)
    o = o or {}
    MEAL_NEXT = MEAL_NEXT + 3
    if t == 'Base.WaterBottle' then
        local it = setmetatable({ id = MEAL_NEXT, t = t, cat = 'Water' }, Item)
        it.fc = setmetatable({ fluid = Fluid[o.fluid or 'Water'], amount = o.amount or 1 }, FC)
        return it
    end
    if o.cat ~= nil then return setmetatable({ id = MEAL_NEXT, t = t, cat = o.cat }, Item) end
    return setmetatable({ id = MEAL_NEXT, t = t, cat = 'Food', rotten = o.rotten, frozen = o.frozen, raw = o.raw,
        cooked = o.cooked }, Food)
end
local Ctr = H.class('ItemContainer')
function Ctr:getType() return self.type end
function Ctr:getItems() return self.items end
function Ctr:isExplored() return true end
function Ctr:setExplored() end
function Ctr:AddItem(it) self.items:add(it) return it end
function Ctr:DoRemoveItem(it)
    if type(it) ~= 'table' then error('No implementation found for DoRemoveItem', 2) end
    if H.listRemove(self.items, it) then MEAL_COUNT.removed = MEAL_COUNT.removed + 1 end
end
function Ctr:containsID(id)
    for _, it in ipairs(self.items.items) do if it.id == id then return true end end
    return false
end
function Ctr:getItemWithIDRecursiv(id)
    for _, it in ipairs(self.items.items) do if it.id == id then return it end end
    return nil
end
function NEW_CTR(kind) return setmetatable({ type = kind, items = H.list() }, Ctr) end
function C.IsoObject:getContainerCount()
    local c = rawget(self, 'container')
    return (c ~= nil and getmetatable(c) == Ctr) and 1 or 0
end
function C.IsoObject:getContainerByIndex(i)
    H.num(i, 'getContainerByIndex')
    if i == 0 and self:getContainerCount() == 1 then return self.container end
    return nil
end
function C.IsoPlayer:getInventory()
    local inv = rawget(self, 'inv')
    if not inv then inv = NEW_CTR('none') self.inv = inv end
    return inv
end
sendRemoveItemFromContainer = function(c, it)
    if getmetatable(c) ~= Ctr or type(it) ~= 'table' then
        error('No implementation found for sendRemoveItemFromContainer', 2)
    end
    if isServer() then
        MEAL_COUNT.sent = MEAL_COUNT.sent + 1
        MEAL_SENT[#MEAL_SENT + 1] = c.type .. ':' .. tostring(it.id)
    end
end
sendAddItemToContainer = function() end
-- Meuble à conteneur posé dans la maison (case pleine ; sprite sans drapeau « bed »).
local Box = H.class('IsoObject_MealBox', C.IsoObject)
function Box:getSprite() return nil end
function MEAL_BOX(x, y, kind, items)
    local o = setmetatable({}, Box)
    o.container = NEW_CTR(kind)
    for _, it in ipairs(items or {}) do o.container:AddItem(it) end
    H.addObject(x, y, 0, o)
    H.square(x, y, 0).blocked = true
    return o
end
-- Identifiants (triés) des objets d'un conteneur.
function BOX_IDS(box)
    local out = {}
    for _, it in ipairs(box.container.items.items) do out[#out + 1] = it.id end
    table.sort(out)
    return out
end
function REF_IDS(gid)
    local out = {}
    for _, e in ipairs(LivingKnox.Groups.get(gid).stock.items) do out[#out + 1] = e.i end
    table.sort(out)
    return out
end
-- LK_Homes.ready : bâtiment chargé en entier.
local def = getCell():getGridSquare(110, 110, 0):getBuildingDef()
getmetatable(def).isFullyStreamedIn = function() return true end
'''

# Caisse de la cuisine (112,112) : deux boîtes de haricots, une pourrie, une crue dangereuse, une gelée, de l'eau
# croupie, une bouteille vide, de l'eau propre, un pansement.
PANTRY = r'''
BEANS = { MEAL_ITEM('Base.TinnedBeans'), MEAL_ITEM('Base.TinnedBeans') }
WATER = MEAL_ITEM('Base.WaterBottle')
PANTRY = MEAL_BOX(112, 112, 'crate', {
    MEAL_ITEM('Base.TinnedBeans', { rotten = true }), MEAL_ITEM('Base.Chicken', { raw = true }),
    MEAL_ITEM('Base.IcePop', { frozen = true }), MEAL_ITEM('Base.WaterBottle', { fluid = 'TaintedWater' }),
    MEAL_ITEM('Base.WaterBottle', { amount = 0 }), BEANS[1], BEANS[2], WATER, MEAL_ITEM('Base.Bandage', { cat = 'FirstAid' }) })
'''


class PureMealTests(PureBase):
    def test_cascade_sends_hunger_and_thirst_to_a_meal(self):
        on = 'meals = true'
        self.assertEqual(self.decide(on + ', needs = { hunger = 75 }')[:2], ('hunger', 'meal'))
        self.assertEqual(self.decide(on + ', needs = { thirst = 75 }')[:2], ('thirst', 'meal'))
        self.assertEqual(self.decide(on + ', needs = { hunger = 75, thirst = 90 }')[:2], ('hunger', 'meal'))
        self.assertEqual(self.decide(on + ', needs = { hunger = 75 }, atHome = false')[:2], ('hunger', 'home'))
        self.assertEqual(self.decide('needs = { hunger = 75 }')[:2], ('hunger', 'home'))      # sans routine des repas
        # Besoin mis de côté (rien à prendre, repas récent) : règle suivante.
        self.assertEqual(self.decide(on + ', needs = { hunger = 75, thirst = 80 }, unfed = { hunger = true }')[:2],
                         ('thirst', 'meal'))
        self.assertEqual(self.decide(on + ', needs = { hunger = 75 }, unfed = { hunger = true }')[:2],
                         ('duty', 'home'))
        self.assertEqual(self.decide(on + ', needs = { hunger = 75 }, threat = ZOMBIE(3)')[:2], ('threat', 'watch'))   # LK06-T07 : membre valide, il tient
        self.assertEqual(self.ev(f'{D}.BEHAVIOURS.meal.vigil'), 'rest')
        self.assertTrue(self.ev(f'{R}.handles("meal")'))
        self.assertEqual(self.ev(f'{N}.BEHAVIOUR_ACTIVITY.meal'), 'idle')

    def test_meal_gestures_are_existing_generated_nodes(self):
        table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        for g in (self.ev(f'{R}.MEAL_TAKE_GESTURE'), self.ev(f'{R}.MEAL_EAT_GESTURE')):
            self.assertIn(g, table['gestures'])
            self.assertTrue(any(['LKGesture', 'STRING', g] in n['conditions'] for n in table['nodes']), g)
            self.assertTrue(self.ev(f'{R}.GESTURES["{g}"]'), g)                 # remis debout par leave

    def test_unfed_window(self):
        self.run_lua(f'{R}.reset() {R}.fast("g", "m-1", "hunger", 700) {R}.fast("g", "m-1", "hunger", 650)')
        self.assertEqual(self.run_lua(f'local u = {R}.unfed("g", "m-1", 699) return u.hunger, u.thirst'), (True, None))
        self.assertIsNone(self.ev(f'{R}.unfed("g", "m-1", 700)'))                 # plus long gardé, borne exclue
        self.assertIsNone(self.ev(f'{R}.unfed("g", "m-2", 600)'))


class MealStack(RoutineStack):
    """Pile complète + LK_Homes, LK_Stock et une caisse garnie dans la maison ; foyer marqué aménagé (skip)."""

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            for path in ('server/LivingKnox/LK_Homes.lua', 'server/LivingKnox/LK_Stock.lua'):
                h.load(m, path)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, MEAL_DOUBLES)
        h.load(srv, PANTRY)
        return h

    def mk(self):
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "deciders", name = "Mill", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) assert(LivingKnox.Homes.skip(g.id)) ')
        for role, profile, female in self.CREW:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = {female}, day = 1 }})) '
        gid = self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        self.run_lua(f'{D}.state.lastPass = 1e18')
        self.h.move_player('A', 100, 100)
        if self.mode == 'mp':
            self.h.move_player('B', 101, 112)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(self.CREW):
                break
        self.assertEqual(len(self.bodies(gid)), len(self.CREW))
        self.run_lua(f'{D}.reset() {R}.reset() for k in pairs({D}.stats) do {D}.stats[k] = 0 end '
                     f'for k in pairs({R}.stats) do {R}.stats[k] = 0 end')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual(r.action, 'filled')                                   # skip : rien de créé, caisse lue
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 0)
        return gid

    def set_needs(self, gid, mid, hunger=20, thirst=20):
        self.update(gid, f'g.members["{mid}"].vitals = {{ hunger = {hunger}, thirst = {thirst}, fatigue = 20, '
                         f'fear = 0, hour = {N}.currentHour() }}')

    def needs(self, gid, mid):
        v = self.ev(f'{N}.get("{gid}", "{mid}")')
        return v.hunger, v.thirst

    def meal(self, gid, mid):
        return self.run_lua(f'local m = {R}.get(MEMBER_NPC("{gid}", "{mid}")) if m == nil or m.kind ~= "meal" then '
                            'return nil end return m.phase, m.took and m.took.i or nil, m.took and m.took.t or nil')

    def run_until(self, cond, seconds=120, walk=1.0):
        for _ in range(seconds):
            self.dpass(1, walk=walk)
            self.h.advance(1)                                                  # une minute de jeu par seconde
            if cond():
                return True
        return False

    def box_ids(self):
        return lua_list(self.ev('BOX_IDS(PANTRY)'))

    def ref_ids(self, gid):
        return lua_list(self.ev(f'REF_IDS("{gid}")'))


class StockMealTests(MealStack):
    mode = 'solo'

    def test_find_meal_skips_what_cannot_be_eaten_or_drunk(self):
        gid = self.mk()
        food = self.run_lua(f'local s = assert({ST}.findMeal("{gid}", "food")) return s.i, s.t, s.key, s.x, s.y')
        self.assertEqual(food, (self.ev('BEANS[1].id'), 'Base.TinnedBeans', '112,112,0,crate,1', 112, 112))
        water = self.run_lua(f'local s = assert({ST}.findMeal("{gid}", "water")) return s.i')
        self.assertEqual(water, self.ev('WATER.id'))                           # croupie et vide écartées
        self.assertEqual(self.run_lua(f'return {ST}.findMeal("{gid}", "medical")'), (None, 'bad category'))
        self.assertEqual(self.run_lua(f'return {ST}.findMeal("no-such", "food")'), (None, 'no group or no home'))
        cooked = self.run_lua('local it = MEAL_ITEM("Base.Chicken", { raw = true, cooked = true }) '
                              f'return {ST}.consumable(it, "food")')
        self.assertTrue(cooked)
        self.assertEqual(self.h.errors('solo'), [])

    def test_take_meal_removes_one_item_once_and_keeps_the_reference_honest(self):
        gid = self.mk()
        before_box, before_ref = self.box_ids(), self.ref_ids(gid)
        got = self.run_lua(f'local seen = 0 local r = assert({ST}.takeMeal("{gid}", "food", "112,112,0,crate,1", '
                           'function(g) seen = seen + 1 end, "m-2")) return r.i, r.t, seen')
        beans = self.ev('BEANS[1].id')
        self.assertEqual(got, (beans, 'Base.TinnedBeans', 1))                 # apply dans la même écriture
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual(self.box_ids(), [i for i in before_box if i != beans])
        self.assertEqual(self.ref_ids(gid), [i for i in before_ref if i != beans])
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))   # ni perte ni vol
        self.assertTrue(any('m-2 ate Base.TinnedBeans' in line for line in self.lk()), self.lk()[-5:])
        self.assertEqual(self.ev('MEAL_COUNT.sent'), 0)                        # solo : rien à envoyer
        # Deuxième boîte, puis plus rien de consommable dans la caisse.
        self.run_lua(f'assert({ST}.takeMeal("{gid}", "food", "112,112,0,crate,1"))')
        self.assertEqual(self.run_lua(f'return {ST}.takeMeal("{gid}", "food", "112,112,0,crate,1")'), (None, 'gone'))
        self.assertEqual(self.run_lua(f'return {ST}.findMeal("{gid}", "food")'), (None, 'none'))
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 2)
        self.assertEqual(self.run_lua(f'return {ST}.takeMeal("{gid}", "food", "1,1,0,crate,1")'),
                         (None, 'container gone'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_shortage_is_logged_once_per_window(self):
        gid = self.mk()
        self.assertTrue(self.ev(f'{ST}.reportShortage("{gid}", "food", "m-2")'))
        self.assertFalse(self.ev(f'{ST}.reportShortage("{gid}", "food", "m-3")'))
        self.assertTrue(self.ev(f'{ST}.reportShortage("{gid}", "water", "m-3")'))
        entries = [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'shortage']
        self.assertEqual(len(entries), 2)
        self.assertTrue(entries[0].startswith('no food to eat left for m-2 (ration '), entries)
        self.h.advance(6 * 60)
        self.assertTrue(self.ev(f'{ST}.reportShortage("{gid}", "food", "m-2")'))


class SoloMealTests(MealStack):
    mode = 'solo'

    def test_hungry_member_walks_to_the_crate_takes_one_item_and_eats_it_once(self):
        gid = self.mk()
        self.jump_to(11)
        self.set_needs(gid, 'm-2', hunger=95)
        npc = self.npc_of(gid, 'm-2')
        portion = self.ev(f'math.max({ST}.portion("{gid}"), {ST}.PORTIONS[3])')
        relief = int(self.ev(f'{N}.CFG.MEAL') * portion + 0.5)
        before_box = self.box_ids()
        self.assertTrue(self.run_until(lambda: (self.meal(gid, 'm-2') or (None,))[0] == 'eat'), self.meal(gid, 'm-2'))
        phase, took, ttype = self.meal(gid, 'm-2')
        self.assertEqual((took, ttype), (self.ev('BEANS[1].id'), 'Base.TinnedBeans'))
        self.assertEqual(self.b(gid, 'm-2'), 'meal')
        self.assertEqual(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")'), 'sit')
        bx, by = self.body_xy(gid, 'm-2')
        self.assertLessEqual(((bx - 112.5) ** 2 + (by - 111.5) ** 2) ** 0.5, 1.0, (bx, by))   # place au nord
        self.assertEqual(self.entry(gid, 'm-2')[3], 90)                        # tourné vers la caisse (sud)
        self.assertEqual(self.needs(gid, 'm-2')[0], 95)                         # pas encore appliqué
        self.assertEqual(self.box_ids(), [i for i in before_box if i != took])
        self.assertNotIn(took, self.ref_ids(gid))
        self.assertTrue(self.run_until(lambda: self.needs(gid, 'm-2')[0] < 95, seconds=20))
        self.assertEqual(self.needs(gid, 'm-2')[0], 95 - relief)
        # Repas fini : un seul objet retiré en tout, rien de créé, plus de repas (pause), geste remis debout.
        for _ in range(5):
            self.dpass(1)
            self.h.advance(1)
        self.assertNotEqual(self.b(gid, 'm-2'), 'meal')
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual(len(self.box_ids()), len(before_box) - 1)
        self.assertEqual(self.needs(gid, 'm-2')[0], 95 - relief)
        self.assertNotEqual(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")'), 'sit')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost), (0, 0))
        self.assertEqual(self.ev(f'{R}.stats.meals'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_thirsty_member_drinks_clean_water_only(self):
        gid = self.mk()
        self.jump_to(11)
        self.set_needs(gid, 'm-2', thirst=90)
        self.assertTrue(self.run_until(lambda: (self.meal(gid, 'm-2') or (None,))[0] == 'eat'))
        self.assertEqual(self.meal(gid, 'm-2')[1:], (self.ev('WATER.id'), 'Base.WaterBottle'))
        self.assertTrue(self.run_until(lambda: self.needs(gid, 'm-2')[1] < 90, seconds=20))
        self.assertLess(self.needs(gid, 'm-2')[1], 90)
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_empty_stock_raises_the_need_to_the_group_and_the_member_goes_back_to_work(self):
        gid = self.mk()
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end')
        self.run_lua(f'{ST}.check("{gid}", {{ force = true }})')
        self.jump_to(11)
        self.set_needs(gid, 'm-2', hunger=95)
        self.assertTrue(self.run_until(lambda: self.ev(f'{R}.stats.fasts') >= 1, seconds=20))
        for _ in range(4):
            self.dpass(1)
            self.h.advance(1)
        self.assertNotEqual(self.b(gid, 'm-2'), 'meal')                          # poste repris
        self.assertEqual(self.needs(gid, 'm-2')[0], 95)                          # rien mangé
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 0)
        log = [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == 'shortage']
        self.assertEqual(len(log), 1)
        self.assertTrue(log[0].startswith('no food to eat left for m-2'), log)
        # Rationnement relu : objets non consommables (pourri, cru, gelé) encore comptés comme nourriture (limite).
        self.assertEqual(self.ev(f'{ST}.needs("{gid}").rationName'), 'strict')
        self.assertEqual(self.h.errors('solo'), [])

    def test_threat_after_the_take_applies_the_meal_once(self):
        gid = self.mk()
        self.jump_to(11)
        self.set_needs(gid, 'm-2', hunger=95)
        npc = self.npc_of(gid, 'm-2')
        portion = self.ev(f'math.max({ST}.portion("{gid}"), {ST}.PORTIONS[3])')
        relief = int(self.ev(f'{N}.CFG.MEAL') * portion + 0.5)
        self.assertTrue(self.run_until(lambda: (self.meal(gid, 'm-2') or (None,))[0] == 'eat'))
        x, y = self.body_xy(gid, 'm-2')
        self.run_lua(f'SEE_ZOMBIE("{npc}", {int(x) + 3}, {int(y)}, 3, 960)')
        self.dpass(2)
        self.assertIn(self.b(gid, 'm-2'), ('flee', 'watch'))
        self.assertIsNone(self.meal(gid, 'm-2'))
        self.assertEqual(self.needs(gid, 'm-2')[0], 95 - relief)                 # repas pris : appliqué maintenant
        self.run_lua('PERCEPTION = {}')
        self.h.advance(15)
        for _ in range(10):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)                       # jamais deux fois
        self.assertEqual(self.needs(gid, 'm-2')[0], 95 - relief)
        self.assertEqual(self.h.errors('solo'), [])

    def test_seen_member_has_no_abstract_meal_when_the_stock_is_real(self):
        gid = self.mk()
        code = (f'local g = LivingKnox.Groups.state.data.groups["{gid}"] local m = g.members["m-2"] '
                f'm.vitals = {{ hunger = 80, thirst = 80, fatigue = 20, fear = 0, hour = 99 }} '
                f'{N}.observe("{gid}", "m-2", "chore", true, 99 * 60 + 10) '
                f'{N}.advanceMember(g, "{gid}", "m-2", m, 100) return m.vitals.hunger, m.vitals.thirst')
        self.assertEqual(self.run_lua(code), (85, 87))                           # travail : +5, +7, aucun repas
        self.run_lua(f'{ST}.clear("{gid}")')
        self.assertEqual(self.run_lua(code), (25, 27))                           # sans stock réel : repas abstrait


class MultiplayerMealTests(MealStack):
    """Serveur dédié + deux clients : prise faite par le serveur, envoyée une fois ; mêmes consignes et gestes chez A
    et B ; aucun repas ni stock chez un client."""

    mode = 'mp'

    def view(self, gid):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        out = {}
        npc = self.npc_of(gid, 'm-2')
        for c in ('A', 'B'):
            out[c] = self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                    'local d = e and (e.op .. ":" .. tostring(e.x) .. "," .. tostring(e.y) .. "@" '
                                    '.. tostring(e.a) .. ":" .. tostring(e.v)) or "none" '
                                    f'return d .. "|" .. LivingKnox.Anim.gestureOf("{npc}") end)()')
        return out

    def test_server_takes_the_item_once_and_both_clients_see_the_same_meal(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Routines'))
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Stock'))
        self.jump_to(11)
        self.set_needs(gid, 'm-2', hunger=95)
        seen = []
        for _ in range(90):
            # Banc MP : corps tenus par le serveur (consignes suspendues, aucun exécutant) ; arrivée posée à la place
            # du repas et regard rapporté fini à la place de l'exécutant propriétaire (Directives.onReport en jeu).
            self.run_lua(f'local npc = MEMBER_NPC("{gid}", "m-2") HARNESS.place(MAT_BODY("{gid}", "m-2"), 112.5, '
                         '111.5, 0) local e = LivingKnox.Directives.entries[npc] '
                         'if e and e.op == "face" and not e.done then e.done, e.s = true, "faced" '
                         'LivingKnox.Directives.sync(npc, true) end')
            self.dpass(1)
            self.h.advance(1)
            v = self.view(gid)
            self.assertEqual(v['A'], v['B'])
            seen.append(v['A'])
            if self.needs(gid, 'm-2')[0] < 95:
                break
        self.assertLess(self.needs(gid, 'm-2')[0], 95, seen[-5:])
        beans = self.ev('BEANS[1].id')
        self.assertEqual(lua_list(self.ev('MEAL_SENT')), [f'crate:{beans}'])   # une seule suppression envoyée
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 1)
        self.assertTrue(any(s.endswith('|rummage') for s in seen), seen)
        self.assertTrue(any(s.endswith('|sit') for s in seen), seen)
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class SuiteTests(MealStack):
    mode = 'solo'

    def test_suite_lk_meals_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        # Fixture de la suite : instanceItem des boîtes et de la bouteille (doublures de repas), Fluid.Water.
        self.h.load('solo', r'''
            local mk = instanceItem
            instanceItem = function(t)
                if t == 'Base.TinnedBeans' or t == 'Base.WaterBottle' then
                    local it = MEAL_ITEM(t)
                    if it.fc then
                        local fc = it.fc
                        function fc.Empty(f) f.fluid, f.amount = nil, 0 end
                        function fc.addFluid(f, fl, a) f.fluid, f.amount = fl, a end
                        function fc.getCapacity() return 1 end
                    end
                    return it
                end
                return mk(t)
            end''')
        self.h.move_player('A', 110, 110)
        self.jump_to(9)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.meals", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.meals')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.meals", tags = "world" }, '
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
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKM' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKM] measure stock of ', '[LKM] measure hungry: ', '[LKM] measure taken: ',
                     '[LKM] measure eaten: '):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


if __name__ == '__main__':
    unittest.main(verbosity=1)
