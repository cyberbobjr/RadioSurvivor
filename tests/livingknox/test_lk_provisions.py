"""Tests hors jeu des provisions sur soi et de la gourde inépuisable des PNJ Living Knox (LK05-T20) :
server/LivingKnox/LK_Provisions.lua (provisions du corps : don au butin, remplacement sur le stock, repas, boisson),
LK_ProvisionMeal.lua (extension de la cascade « provision » : règles, décrochage, repas assis), le registre des
extensions de LK_Decisions.lua (Decisions.registerExtension) et celui du contenu du butin de LK_Loot.lua
(Loot.registerContent), et la suite en jeu lk.provisions (dev/.../RST_LKProvisions.lua) jouée sur les doublures.

    python tests/livingknox/test_lk_provisions.py

Décision de l'utilisateur du 2026-11-04 (plan LK05) : deux vrais aliments non périssables dans l'inventaire du corps,
remplacés sur le stock du foyer ; une gourde jamais vidée ; repas d'une provision loin du foyer ; en combat, faim >= 90
sans ennemi à 3 cases ou moins : décrochage d'environ 8 cases, repas assis, reprise ; ennemi au contact : la menace
d'abord ; le cadavre garde ce qui reste.

Doublures ajoutées, relevées dans le Java 42.22 (E:/pz-source-42.22) :
- InventoryItem.getOffAgeMax (InventoryItem.java:2453 ; défaut 1000000000, :165 ; aliment sans DaysTotallyRotten :
  Item.java:111, 1563) ;
- inventaire du corps (IsoGameCharacter.getInventory, IsoGameCharacter.java:2987) : ItemContainer de MEAL_DOUBLES
  (AddItem, DoRemoveItem : ItemContainer.java:472, 2004) ;
- gourde Base.CanteenMilitaryFull (media/scripts/generated/items/normal.txt:14015-14040 : 0,9 l d'eau à la création,
  FluidContainerScript.getInitialAmount :330-333) : FluidContainer.getAmount (FluidContainer.java:520) ;
- aliments Base.GranolaBar, Base.BeefJerky, Base.DriedApricots (food.txt:12842, 12691, 8721 : DisplayCategory Food,
  sans DaysFresh ni DaysTotallyRotten).
Elles NE PROUVENT PAS l'API réelle ni le rendu : seulement la logique (un objet en moins, faim soulagée une fois, gourde
intacte, rien de créé sur un stock vide, mêmes consignes chez deux clients, effet décidé par le serveur seul).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_decisions import PureBase  # noqa: E402
from harness import routine_files  # noqa: E402
from test_lk_meals import MealStack  # noqa: E402
from phase_sweep import WORLDS, other_groups, sweep  # noqa: E402
from test_lk_loot import LootBase  # noqa: E402

D = 'LivingKnox.Decisions'
P = 'LivingKnox.Provisions'
PM = 'LivingKnox.ProvisionMeal'
ST = 'LivingKnox.Stock'
N = 'LivingKnox.Needs'
ROOT = Path(__file__).resolve().parents[2]
PROVISIONS = 'server/LivingKnox/LK_Provisions.lua'
PROVISION_MEAL = 'server/LivingKnox/LK_ProvisionMeal.lua'
SUITE = 'shared/RST/suites/RST_LKProvisions.lua'
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
SUITE_FILE = tests_lua('lk') / SUITE
FOODS = ('Base.GranolaBar', 'Base.BeefJerky', 'Base.DriedApricots')
CANTEEN = 'Base.CanteenMilitaryFull'

# Doublures des provisions, sur la pile des repas (MEAL_DOUBLES de test_lk_meals.py).
PROVISION_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Item = C.InventoryItem
-- InventoryItem.getOffAgeMax (InventoryItem.java:2453) : 1000000000 par défaut (:165), DaysTotallyRotten sinon.
function Item:getOffAgeMax() return rawget(self, 'offAgeMax') or 1000000000 end
-- FluidContainer.getAmount (FluidContainer.java:520).
function C.FluidContainer:getAmount() return self.amount or 0 end
-- IsoGameCharacter.getInventory (IsoGameCharacter.java:2987) : inventaire du corps.
local Z = C.IsoZombie
function Z:getInventory()
    local inv = rawget(self, 'inv')
    if not inv then inv = NEW_CTR('none') self.inv = inv end
    return inv
end
CREATED = 0
-- instanceItem : aliments des provisions, gourde pleine (0,9 l d'eau), boîtes et bouteilles des repas.
local prevInstance = instanceItem
instanceItem = function(t)
    if type(t) ~= 'string' then error('No implementation found for instanceItem', 2) end
    if t == 'Base.GranolaBar' or t == 'Base.BeefJerky' or t == 'Base.DriedApricots' or t == 'Base.TinnedBeans' then
        CREATED = CREATED + 1
        return MEAL_ITEM(t)
    end
    if t == 'Base.CanteenMilitaryFull' then
        CREATED = CREATED + 1
        local it = MEAL_ITEM('Base.WaterBottle', { amount = 0.9 })
        it.t, it.cat = t, 'WaterContainer'
        return it
    end
    return prevInstance(t)
end
function C.InventoryItem:getFullType() return self.t end
-- Contenu de l'inventaire du corps : types triés.
function BODY_ITEMS(z)
    local out = {}
    for _, it in ipairs(z:getInventory():getItems().items) do out[#out + 1] = it:getFullType() end
    table.sort(out)
    return table.concat(out, ',')
end
-- Cible de combat d'un membre (LivingKnox.Zombies.targetFor), posée par le test : TARGETS[npc] = { x, y, d }.
TARGETS = {}
LivingKnox.Zombies = LivingKnox.Zombies or {}
LivingKnox.Zombies.targetFor = function(id)
    local t = TARGETS[id]
    if t == nil then return nil end
    return { kind = 'zombie', u = 'z' .. tostring(t.o or 900), d = t.d, x = t.x, y = t.y }
end
'''


def provision_loads(h, machine):
    h.load(machine, PROVISION_DOUBLES)


class PureProvisionTests(PureBase):
    """Cascade pure : règles de l'extension « provision » (ctx.provisions posé par le test)."""

    def setUp(self):
        super().setUp()
        for rel in routine_files():
            self.h.load(self.srv, rel)
        self.h.load(self.srv, PROVISIONS)
        self.h.load(self.srv, PROVISION_MEAL)

    def pick(self, over):
        return self.run_lua(f'local o = {D}.decide(CTX({{ {over} }})) return o.rule, o.b, o.key')

    def test_away_hunger_and_thirst_use_what_the_member_carries(self):
        away = 'atHome = false, meals = true, provisions = { food = 2, canteen = true }'
        self.assertEqual(self.pick(away + ', needs = { hunger = 75 }'), ('provision.hunger', 'provision', 'hunger'))
        self.assertEqual(self.pick(away + ', needs = { thirst = 75 }'), ('provision.thirst', 'provision', 'thirst'))
        self.assertEqual(self.pick(away + ', needs = { hunger = 75, thirst = 90 }')[2], 'hunger')
        # Rien sur soi : retour au foyer comme avant (règles hunger / thirst).
        empty = 'atHome = false, meals = true, provisions = { food = 0, canteen = false }'
        self.assertEqual(self.pick(empty + ', needs = { hunger = 75 }')[:2], ('hunger', 'home'))
        self.assertEqual(self.pick(empty + ', needs = { thirst = 75 }')[:2], ('thirst', 'home'))
        # Au foyer : repas réel dans le stock (LK05-T07), pas de provision.
        home = 'atHome = true, meals = true, provisions = { food = 2, canteen = true }'
        self.assertEqual(self.pick(home + ', needs = { hunger = 75 }')[:2], ('hunger', 'meal'))
        self.assertEqual(self.pick(home + ', needs = { thirst = 75 }')[:2], ('thirst', 'meal'))
        # Sans foyer : la provision.
        self.assertEqual(self.pick('home = false, provisions = { food = 1 }, needs = { hunger = 80 }')[1], 'provision')
        # Faim sous le seuil : rien.
        self.assertEqual(self.pick(away + ', needs = { hunger = 60 }')[0], 'duty')

    def test_combat_hunger_disengages_only_without_enemy_in_contact(self):
        fight = ('combatant = true, role = "fighter", allowed = { guard = true, fight = true, defend = true }, '
                 'provisions = { food = 2, canteen = true }, ')
        def tgt(d):
            return (f'target = {{ kind = "zombie", u = "z42", d = {d} }}, threats = {{ ZOMBIE({d}) }}, '
                    f'threat = ZOMBIE({d}), ')
        self.assertEqual(self.pick(fight + tgt(6) + 'needs = { hunger = 95 }'),
                         ('provision.fight', 'provision', 'fight'))
        self.assertEqual(self.pick(fight + tgt(3.5) + 'needs = { hunger = 90 }')[1], 'provision')
        # Ennemi à 3 cases ou moins : la menace d'abord.
        self.assertEqual(self.pick(fight + tgt(3) + 'needs = { hunger = 95 }')[:2], ('threat', 'fight'))
        self.assertEqual(self.pick(fight + tgt(1.2) + 'needs = { hunger = 100 }')[:2], ('threat', 'fight'))
        # Faim sous 90 ou rien sur soi : combat.
        self.assertEqual(self.pick(fight + tgt(6) + 'needs = { hunger = 89 }')[:2], ('threat', 'fight'))
        nofood = fight.replace('food = 2', 'food = 0')
        self.assertEqual(self.pick(nofood + tgt(6) + 'needs = { hunger = 95 }')[:2], ('threat', 'fight'))
        # Autre ennemi proche que la cible : contact.
        near = (f'target = {{ kind = "zombie", u = "z42", d = 6 }}, threats = {{ ZOMBIE(2), ZOMBIE(6) }}, '
                'threat = ZOMBIE(2), ')
        self.assertEqual(self.pick(fight + near + 'needs = { hunger = 95 }')[1], 'fight')
        # Constantes mauvaises (peur) : la retraite de la règle threat.
        self.assertEqual(self.pick(fight + tgt(6) + 'needs = { hunger = 95, fear = 90 }')[:2],
                         ('threat', 'retreat'))
        # Menace perçue sans cible (regard) : décrochage aussi ; sans menace ni cible : pas de combat.
        self.assertEqual(self.pick(fight + 'threats = { ZOMBIE(9) }, threat = ZOMBIE(9), needs = { hunger = 95 }')[2],
                         'fight')

    def test_registry_keeps_the_ranks_and_refuses_bad_specs(self):
        self.assertEqual(self.ev(f'{D}.BEHAVIOURS.provision.vigil'), 'guard')
        self.assertEqual(lua_list(self.ev(f'{D}.PRIORITIES')),
                         ['threat', 'fear', 'wound', 'hunger', 'thirst', 'fatigue', 'duty', 'routine'])
        out = self.run_lua(f'local o = {D}.decide(CTX({{ atHome = false, provisions = {{ food = 1 }}, '
                           'needs = { hunger = 80 } })) return o.p')
        self.assertEqual(out, 4)                                   # rang de la règle hunger
        for bad in ('{ id = "x" }', '{ id = "x", order = 1, rules = { { name = "r", before = "nope", '
                    'rule = function() end } } }', '{ id = "x", order = 1, behaviour = { vigil = "rest" } }',
                    '{ id = "fight", order = 1, behaviour = { vigil = "guard" }, apply = function() end }'):
            ok, err = self.run_lua(f'return pcall({D}.registerExtension, {bad})')
            self.assertFalse(ok, bad)
            self.assertIn('registerExtension', err)
        self.assertEqual(self.ev(f'{N}.BEHAVIOUR_ACTIVITY.provision'), 'idle')

    def test_kit_is_deterministic_vanilla_food(self):
        a = lua_list(self.ev(f'{P}.kitFor("lk-7", 2)'))
        self.assertEqual(a, lua_list(self.ev(f'{P}.kitFor("lk-7", 2)')))
        self.assertEqual(len(a), 2)
        for t in a:
            self.assertIn(t, FOODS)
        self.assertEqual(lua_list(self.ev(f'{P}.CFG.FOODS')), list(FOODS))
        self.assertEqual(self.ev(f'{P}.CFG.CANTEEN'), CANTEEN)
        self.assertEqual(self.ev(f'{P}.CFG.COUNT'), 2)


class ProvisionStack(MealStack):
    """Pile des repas (groupe « deciders » dans la maison, caisse garnie) + butin, provisions et cible injectée."""

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        provision_loads(h, srv)
        for path in ('server/LivingKnox/LK_Ammo.lua', 'server/LivingKnox/LK_Loot.lua', PROVISIONS, PROVISION_MEAL):
            for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
                h.load(m, path)
        # Fusil à pompe des combattants : aucune doublure d'arme à feu sur ce banc (cache de LK_Ammo.spec, munitions
        # prouvées par test_lk_loot.py).
        h.load(srv, 'LivingKnox.Ammo.specs["Base.Shotgun"] = { bad = "no firearm double on this bench" }')
        return h

    def mk(self):
        gid = super().mk()
        self.h.advance_ms(self.ev('LivingKnox.Config.LOOT.EVERY_MS'))
        self.h.tick(1)                                            # butin des corps (provisions comprises)
        return gid

    def inv(self, gid, mid):
        return self.ev(f'BODY_ITEMS(MAT_BODY("{gid}", "{mid}"))').split(',')

    def food(self, gid, mid):
        return sum(1 for t in self.inv(gid, mid) if t in FOODS or t == 'Base.TinnedBeans')

    def place(self, gid, mid, x, y):
        self.run_lua(f'HARNESS.place(MAT_BODY("{gid}", "{mid}"), {x}, {y}, 0)')

    def canteen(self, gid, mid):
        return self.run_lua(f'for _, it in ipairs(MAT_BODY("{gid}", "{mid}"):getInventory():getItems().items) do '
                            f'if it:getFullType() == "{CANTEEN}" then return it:getFluidContainer():getAmount(), '
                            'it:getFluidContainer():getPrimaryFluid().name end end return nil')

    def tick_until(self, cond, seconds=60, walk=1.0):
        for _ in range(seconds):
            self.dpass(1, walk=walk)
            self.h.advance(1)
            if cond():
                return True
        return False


class SoloProvisionTests(ProvisionStack):
    mode = 'solo'

    def test_every_body_carries_two_provisions_and_a_full_canteen(self):
        gid = self.mk()
        for mid in ('m-1', 'm-2', 'm-3'):
            items = self.inv(gid, mid)
            self.assertEqual(sum(1 for t in items if t in FOODS), 2, items)
            self.assertEqual(items.count(CANTEEN), 1, items)
            self.assertEqual(self.canteen(gid, mid), (0.9, 'Water'))
        self.assertTrue(any('2 provision(s) and a canteen' in x for x in self.lk()), self.lk()[-5:])
        # Corps relu : jamais deux fois.
        before = self.inv(gid, 'm-2')
        self.run_lua(f'LivingKnox.Loot.build(MEMBER_NPC("{gid}", "m-2"), MAT_BODY("{gid}", "m-2"))')
        self.assertEqual(self.inv(gid, 'm-2'), before)
        self.assertEqual(self.h.errors('solo'), [])

    def test_hungry_member_away_eats_one_provision_once(self):
        gid = self.mk()
        self.jump_to(11)
        npc = self.npc_of(gid, 'm-2')
        self.place(gid, 'm-2', 135.5, 110.5)                      # 25 cases du foyer
        self.set_needs(gid, 'm-2', hunger=95)
        meal = self.ev(f'{N}.CFG.MEAL')
        before_box = self.box_ids()
        sat = []
        ok = self.tick_until(lambda: sat.append(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")')) or
                             self.needs(gid, 'm-2')[0] < 95, seconds=40, walk=0.0)
        self.assertTrue(ok, self.lk()[-8:])
        self.assertIn('sit', sat)                                 # mangé assis
        self.assertEqual(self.needs(gid, 'm-2')[0], 95 - meal)
        self.assertEqual(self.food(gid, 'm-2'), 1)                # un objet en moins
        self.assertTrue(any('ate provision' in x for x in self.lk()), self.lk()[-5:])
        # Plus jamais deux fois ; geste remis debout quand il repart.
        for _ in range(10):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(self.food(gid, 'm-2'), 1)
        self.assertEqual(self.needs(gid, 'm-2')[0], 95 - meal)
        self.assertNotEqual(self.b(gid, 'm-2'), 'provision')
        self.assertNotEqual(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")'), 'sit')
        self.assertEqual(self.box_ids(), before_box)              # stock du foyer intact
        self.assertEqual(self.ev(f'{P}.stats.eaten'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_thirst_away_is_relieved_without_emptying_the_canteen(self):
        gid = self.mk()
        self.jump_to(11)
        self.place(gid, 'm-2', 135.5, 110.5)
        self.set_needs(gid, 'm-2', thirst=95)
        drink = self.ev(f'{N}.CFG.DRINK')
        before = self.inv(gid, 'm-2')
        self.assertTrue(self.tick_until(lambda: self.needs(gid, 'm-2')[1] < 95, seconds=30, walk=0.0))
        self.assertEqual(self.needs(gid, 'm-2')[1], 95 - drink)
        self.assertEqual(self.canteen(gid, 'm-2'), (0.9, 'Water'))   # jamais vidée
        self.assertEqual(self.inv(gid, 'm-2'), before)
        # Assoiffé à nouveau : encore.
        self.set_needs(gid, 'm-2', thirst=95)
        self.assertTrue(self.tick_until(lambda: self.needs(gid, 'm-2')[1] < 95, seconds=40, walk=0.0))
        self.assertEqual(self.canteen(gid, 'm-2'), (0.9, 'Water'))
        self.assertEqual(self.ev(f'{P}.stats.drunk'), 2)
        self.assertEqual(self.h.errors('solo'), [])

    def test_nothing_carried_sends_the_member_home(self):
        gid = self.mk()
        self.jump_to(11)
        self.run_lua(f'local inv = MAT_BODY("{gid}", "m-2"):getInventory() local gone = {{}} '
                     'for _, it in ipairs(inv:getItems().items) do if instanceof(it, "Food") then '
                     'gone[#gone + 1] = it end end for _, it in ipairs(gone) do inv:DoRemoveItem(it) end')
        self.place(gid, 'm-2', 135.5, 110.5)
        self.set_needs(gid, 'm-2', hunger=95)
        self.dpass(2)
        self.assertEqual(self.b(gid, 'm-2'), 'home')
        self.assertEqual(self.needs(gid, 'm-2')[0], 95)
        self.assertEqual(self.h.errors('solo'), [])

    def test_provisions_replaced_at_home_from_the_stock(self):
        gid = self.mk()
        self.jump_to(11)
        self.run_lua(f'local inv = MAT_BODY("{gid}", "m-2"):getInventory() '
                     'for _, it in ipairs(inv:getItems().items) do if instanceof(it, "Food") then '
                     'inv:DoRemoveItem(it) break end end')
        self.assertEqual(self.food(gid, 'm-2'), 1)
        created = self.ev('CREATED')
        before_box, before_ref = self.box_ids(), self.ref_ids(gid)
        beans = self.ev('BEANS[1].id')
        self.assertTrue(self.tick_until(lambda: self.food(gid, 'm-2') == 2, seconds=20))
        self.assertEqual(self.box_ids(), [i for i in before_box if i != beans])
        self.assertEqual(self.ref_ids(gid), [i for i in before_ref if i != beans])
        self.assertIn('Base.TinnedBeans', self.inv(gid, 'm-2'))   # l'objet du stock, pas un neuf
        self.assertEqual(self.ev('CREATED'), created)
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        self.assertTrue(any('for provisions' in x for x in self.lk()), self.lk()[-5:])
        # Plein : plus rien de pris.
        for _ in range(15):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual(len(self.box_ids()), len(before_box) - 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_perishable_food_is_not_a_provision_and_an_empty_stock_creates_nothing(self):
        gid = self.mk()
        self.jump_to(11)
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end '
                     'APPLE = MEAL_ITEM("Base.Apple") APPLE.offAgeMax = 8 PANTRY.container:AddItem(APPLE)')
        self.run_lua(f'{ST}.check("{gid}", {{ force = true }})')
        self.run_lua(f'local inv = MAT_BODY("{gid}", "m-2"):getInventory() local gone = {{}} '
                     'for _, it in ipairs(inv:getItems().items) do if instanceof(it, "Food") then '
                     'gone[#gone + 1] = it end end for _, it in ipairs(gone) do inv:DoRemoveItem(it) end')
        created = self.ev('CREATED')
        for _ in range(30):
            self.dpass(1, walk=1.0)
            self.h.advance(1)
        self.assertEqual(self.food(gid, 'm-2'), 0)
        self.assertEqual(self.ev('CREATED'), created)             # jamais créé de rien
        self.assertTrue(self.run_lua('for _, it in ipairs(PANTRY.container.items.items) do '
                                     'if it == APPLE then return true end end return false'))
        # Essais bornés : au plus un par REFILL_MINUTES et par membre.
        tries = self.ev(f'{P}.stats.refillTries')
        self.assertLessEqual(tries, 3 * (30 // self.ev(f'{P}.CFG.REFILL_MINUTES') + 1), tries)
        self.assertEqual(self.h.errors('solo'), [])

    def fight_scene(self, gid, d):
        """m-2 au loin, zombie cible à d cases à l'est, perçu ; faim 95."""
        npc = self.npc_of(gid, 'm-2')
        self.place(gid, 'm-2', 135.5, 110.5)
        self.run_lua(f'TARGETS["{npc}"] = {{ x = {135 + d}, y = 110, d = {d} }} '
                     f'SEE_ZOMBIE("{npc}", {135 + d}, 110, {d}, 900)')
        self.set_needs(gid, 'm-2', hunger=95)
        return npc

    def test_combat_hunger_disengages_eats_sitting_then_fights_again(self):
        gid = self.mk()
        self.jump_to(11)
        # Mur au nord-ouest : la case à 8 cases à l'ouest est vue par le zombie, celle au nord-ouest est cachée.
        self.run_lua('WALLS = WALLS or {} WALLS[#WALLS + 1] = { axis = "y", at = 106, lo = 120, hi = 132, kind = "wall" }')
        npc = self.fight_scene(gid, 6)
        self.dpass(1)
        self.assertEqual(self.b(gid, 'm-2'), 'provision')
        op, x, y = self.entry(gid, 'm-2')[:3]
        self.assertEqual(op, 'move')
        self.assertEqual(self.run_lua(f'return LivingKnox.Directives.get("{npc}").g'), 'run')
        self.assertGreaterEqual(max(abs(x + 0.5 - 135.5), abs(y + 0.5 - 110.5)), 5)          # environ 8 cases
        self.assertLess(x, 135)                                                               # loin du zombie
        self.assertLess(y, 106)                                                               # derrière le mur
        self.assertTrue(any('disengages' in s and 'out of sight' in s for s in self.lk()), self.lk()[-5:])
        # Le zombie reste à distance (cible et perception suivent le membre) ; repas assis, puis le combat reprend.
        meal = self.ev(f'{N}.CFG.MEAL')
        seen = []

        def follow():
            bx, by = self.body_xy(gid, 'm-2')
            self.run_lua(f'TARGETS["{npc}"].d = 7 SEE_ZOMBIE("{npc}", {int(bx) + 7}, {int(by)}, 7, 900)')
            seen.append((self.b(gid, 'm-2'), self.ev(f'LivingKnox.Anim.gestureOf("{npc}")')))
            return self.needs(gid, 'm-2')[0] < 95

        self.assertTrue(self.tick_until(follow, seconds=60), seen[-6:])
        self.assertIn(('provision', 'sit'), seen)
        self.assertEqual(self.needs(gid, 'm-2')[0], 95 - meal)
        self.assertEqual(self.food(gid, 'm-2'), 1)
        self.dpass(2)
        self.assertEqual(self.b(gid, 'm-2'), 'fight')                                         # reprise
        self.assertNotEqual(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")'), 'sit')
        self.assertEqual(self.h.errors('solo'), [])

    def test_enemy_in_contact_comes_first(self):
        gid = self.mk()
        self.jump_to(11)
        self.fight_scene(gid, 2)
        for _ in range(5):
            self.dpass(1)
            self.h.advance(1)
            self.assertEqual(self.b(gid, 'm-2'), 'fight')
        self.assertEqual(self.food(gid, 'm-2'), 2)
        self.assertEqual(self.needs(gid, 'm-2')[0], 95)
        self.assertEqual(self.h.errors('solo'), [])

    def test_contact_during_the_meal_interrupts_it_without_eating(self):
        gid = self.mk()
        self.jump_to(11)
        npc = self.fight_scene(gid, 6)
        self.assertTrue(self.tick_until(lambda: self.ev(f'LivingKnox.Anim.gestureOf("{npc}")') == 'sit', seconds=30),
                        self.lk()[-5:])
        bx, by = self.body_xy(gid, 'm-2')
        self.run_lua(f'TARGETS["{npc}"] = {{ x = {int(bx) + 1}, y = {int(by)}, d = 1.5 }} '
                     f'SEE_ZOMBIE("{npc}", {int(bx) + 1}, {int(by)}, 1.5, 900)')
        self.dpass(2)
        self.assertEqual(self.b(gid, 'm-2'), 'fight')
        self.assertNotEqual(self.ev(f'LivingKnox.Anim.gestureOf("{npc}")'), 'sit')
        self.assertEqual(self.food(gid, 'm-2'), 2)                 # rien mangé, rien perdu
        self.assertEqual(self.needs(gid, 'm-2')[0], 95)
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerProvisionTests(ProvisionStack):
    """Serveur dédié + deux clients : repas d'une provision décidé par le serveur ; mêmes consignes et gestes chez A et
    B ; aucun module de provisions chez un client."""

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

    def test_server_feeds_the_member_from_its_provisions_and_both_clients_agree(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Provisions'))
            self.assertIsNone(self.h.eval(c, 'LivingKnox.ProvisionMeal'))
        self.assertEqual(self.food(gid, 'm-2'), 2)
        self.jump_to(11)
        self.place(gid, 'm-2', 130.5, 110.5)
        self.set_needs(gid, 'm-2', hunger=95, thirst=95)
        seen = []
        for _ in range(60):
            # Banc MP : corps tenus par le serveur, aucun exécutant ; arrêt rapporté fini (Directives.onReport en jeu).
            self.run_lua(f'local npc = MEMBER_NPC("{gid}", "m-2") local e = LivingKnox.Directives.entries[npc] '
                         'if e and e.op == "stop" and not e.done then e.done, e.s = true, "stopped" '
                         'LivingKnox.Directives.sync(npc, true) end')
            self.dpass(1)
            self.h.advance(1)
            v = self.view(gid)
            self.assertEqual(v['A'], v['B'])
            seen.append(v['A'])
            hunger, thirst = self.needs(gid, 'm-2')
            if hunger < 95 and thirst < 95:
                break
        self.assertLess(self.needs(gid, 'm-2')[0], 95, seen[-5:])
        self.assertLess(self.needs(gid, 'm-2')[1], 95, seen[-5:])
        self.assertEqual(self.food(gid, 'm-2'), 1)
        self.assertEqual(self.canteen(gid, 'm-2'), (0.9, 'Water'))
        self.assertTrue(any(s.endswith('|sit') for s in seen), seen)
        self.assertEqual(self.ev('#MEAL_SENT'), 0)                 # rien envoyé : inventaire du corps, serveur seul
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class CorpseProvisionTests(LootBase):
    """Butin réel (LootBase de test_lk_loot.py) : provisions données par le registre du butin, gardées par le cadavre."""

    mode = 'mp'

    def make(self, root=None):
        h = super().make(root)
        h.load('server', r'''
            local H = HARNESS
            local C = H.classes
            local Item = C.InventoryItem
            local Food = H.class('Food', Item)
            function Item:getDisplayCategory() return rawget(self, 'cat') end
            function Item:getFluidContainer() return rawget(self, 'fc') end
            function Item:getOffAgeMax() return rawget(self, 'offAgeMax') or 1000000000 end
            NEXT_ID = 7000
            function Item:getID()                                  -- InventoryItem.java:3346
                if rawget(self, 'id') == nil then NEXT_ID = NEXT_ID + 1 self.id = NEXT_ID end
                return self.id
            end
            function Item:isCooked() return false end
            function Food:isRotten() return false end
            function Food:isFrozen() return false end
            function Food:isbDangerousUncooked() return false end
            local FC = H.class('FluidContainer')
            function FC:isEmpty() return (self.amount or 0) <= 0 end
            function FC:getPrimaryFluid() return self.fluid end
            function FC:getAmount() return self.amount or 0 end
            Fluid = Fluid or { Water = { name = 'Water' } }
            local prev = instanceItem
            instanceItem = function(t)
                if t == 'Base.GranolaBar' or t == 'Base.BeefJerky' or t == 'Base.DriedApricots' then
                    return setmetatable({ t = t, fullType = t, cat = 'Food' }, Food)
                end
                if t == 'Base.CanteenMilitaryFull' then
                    return setmetatable({ t = t, fullType = t, cat = 'WaterContainer',
                        fc = setmetatable({ fluid = Fluid.Water, amount = 0.9 }, FC) }, Item)
                end
                return prev(t)
            end''')
        h.load('server', PROVISIONS)
        return h

    def test_kit_from_the_loot_registry_and_the_corpse_keeps_what_is_left(self):
        self.armed('Base.Pistol', 'worker')
        inv = self.inv().split(',')
        self.assertEqual(sum(1 for t in inv if t in FOODS), 2, inv)
        self.assertEqual(inv.count(CANTEEN), 1, inv)
        self.assertIn('Base.Nails', inv)                                    # poches du rôle gardées
        self.assertTrue(any('loot built: Base.Pistol' in x and '2 provision(s) and a canteen' in x
                            for x in self.lk()), self.lk()[-5:])
        gid, mid = self.run_lua('return LivingKnox.Groups.findNpc("lk-1")')
        self.run_lua(f'local g = LivingKnox.Groups.state.data.groups["{gid}"] g.members["{mid}"].vitals = '
                     f'{{ hunger = 90, thirst = 20, fatigue = 20, fear = 0, hour = {N}.currentHour() or 0 }}')
        self.assertIn(self.run_lua(f'return {P}.eat("{gid}", "{mid}", {self.body()})'), FOODS)
        self.kill()
        corpse = self.content().split(',')
        self.assertEqual(sum(1 for t in corpse if t in FOODS), 1, corpse)
        self.assertEqual(corpse.count(CANTEEN), 1, corpse)
        self.assertEqual(self.h.errors('server'), [])


class SuiteTests(ProvisionStack):
    mode = 'solo'

    def run_suite(self, start=(9, 0)):
        """start : heure de départ (None : horloge déjà placée par le balayage des phases)."""
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
        # IsoGameCharacter.isGodMod / setGodMod(boolean) (IsoGameCharacter.java:11192, 11237), comme test_lk_garden.py.
        self.h.load('solo', 'local Pl = HARNESS.classes.IsoPlayer function Pl:isGodMod() return self.god == true end '
                            'function Pl:setGodMod(b) if type(b) ~= "boolean" then '
                            'error("No implementation found for setGodMod", 2) end self.god = b end')
        self.h.move_player('A', 110, 110)
        if start is not None:
            self.h.jump_to(*start)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.provisions", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.provisions')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.provisions", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(8000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 10 == 9:
                self.h.advance(1)
        return self.h.eval('solo', 'RST.last()')

    def test_suite_lk_provisions_passes_on_the_doubles(self):
        self.check(self.run_suite())

    def test_suite_lk_provisions_passes_under_the_phase_sweep(self):
        sweep(self, lambda phase: self.check(self.run_suite(start=None)), worlds=WORLDS)   # E19-T05

    def check(self, report):
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKP' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKP] measure carried: ', '[LKP] measure eaten away: ', '[LKP] measure drunk away: ',
                     '[LKP] measure replaced at home: '):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), other_groups(self))
        self.assertEqual(self.ev(f'{D}.CFG.HOME_RADIUS'), 10)        # réglage du test remis
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)


class SourceTests(unittest.TestCase):
    def test_new_modules_are_authority_only_and_kahlua_safe(self):
        base = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'
        for rel in (PROVISIONS, PROVISION_MEAL):
            src = (base / rel).read_text(encoding='utf-8')
            self.assertIn('if isClient() then return end', src)
            code = re.sub(r'--[^\n]*', '', src)
            self.assertTrue(all(ord(ch) < 128 for ch in code), rel)
            self.assertIsNone(re.search(r'\bnext\s*\(', code), rel)


if __name__ == '__main__':
    unittest.main(verbosity=1)
