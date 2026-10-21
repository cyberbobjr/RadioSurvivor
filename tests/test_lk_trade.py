"""Tests hors jeu du troc direct avec un groupe Living Knox (LK11-T08) : server/LivingKnox/LK_Trade.lua, le barème
partagé shared/RadioSurvivor/RS_TradeValues.lua, la fenêtre client/LivingKnox/LK_TradeView.lua et la suite en jeu
lk.trade (dev/.../RST_LKTrade.lua) dans le banc.

    python RadioSurvivor/tests/test_lk_trade.py

Banc tests/harness.py (solo, ou serveur dédié + deux clients) avec le vrai registre des groupes, le vrai aménagement
des foyers (LK_Homes), le vrai stock (LK_Stock, doublures de tests/test_lk_stock.py et tests/test_lk_aid.py) et le
vrai registre des attitudes (LK_Hostility). Doublures ajoutées, relevées dans le Java 42.21.0 :
- IsoGameCharacter.isEquipped(objet) = porté ou en main, isAttachedItem(objet) (J/characters/IsoGameCharacter.java:
  9420-9432) ; InventoryItem.isFavorite (J/inventory/InventoryItem.java:3363), getCondition / getConditionMax
  (:2500, :2231) ; InventoryContainer.getInventory (J/inventory/types/InventoryContainer.java:55), ItemContainer.isEmpty
  (J/inventory/ItemContainer.java:2168) ;
- getItemNameFromFullType (J/Lua/LuaManager.java:6970) côté client ;
- déconnexion : un paquet d'un joueur parti n'est jamais traité (le banc livre la commande sans joueur).
Elles NE PROUVENT PAS l'API réelle, seulement la logique : suite en jeu lk.trade, essai de la fenêtre.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LUA  # noqa: E402
from test_lk_stock import Base as StockBase, KITCHEN, OFFSCREEN_DOUBLES  # noqa: E402
from test_lk_homes import HOUSE  # noqa: E402
from test_lk_aid import AID_DOUBLES, ENGINE_STUBS, MENU_DOUBLES  # noqa: E402

T = 'LivingKnox.Trade'
ST = 'LivingKnox.Stock'
TRADE = 'server/LivingKnox/LK_Trade.lua'
VALUES = 'shared/RadioSurvivor/RS_TradeValues.lua'
VIEW = 'client/LivingKnox/LK_TradeView.lua'
RVIEW = 'client/LivingKnox/LK_RelationsView.lua'
KEY_A, KEY_B = 'c-alpha', 'c-bravo'
ROOT = Path(__file__).resolve().parents[1]
VANILLA_ITEMS = pz_paths.media_dir() / 'scripts/generated/items'

TRADE_DOUBLES = r'''
local C = HARNESS.classes
for t, cat in pairs({ ['Base.Battery'] = 'Electronics', ['Base.Necklace_Gold'] = 'Accessory',
                      ['Base.Antibiotics'] = 'FirstAid', ['Base.Hat_Army'] = 'ProtectiveGear',
                      ['Base.Whiskey'] = 'Food', ['RadioSurvivor.NoteWalt'] = 'Literature' }) do
    ITEM_DEFS[t] = { cat = cat }
end
ITEM_DEFS['Base.Bag_Schoolbag'].container = true
local Item = C.InventoryItem
function Item:isFavorite() return rawget(self, 'fav') == true end
function Item:getCondition() return rawget(self, 'cond') or 10 end
function Item:getConditionMax() return rawget(self, 'condMax') or 10 end
local Bag = HARNESS.class('InventoryContainer', Item)
local make = instanceItem
instanceItem = function(t)
    local it = make(t)
    if it ~= nil and ITEM_DEFS[t].container then setmetatable(it, Bag) end
    return it
end
function Bag:getInventory() return self.inner end
local Ctr = getmetatable(NEW_CONTAINER('x'))
function Ctr:isEmpty() return #self.items.items == 0 end
function C.IsoPlayer:isEquipped(it) return rawget(self, 'worn') ~= nil and self.worn[it] == true end
function C.IsoPlayer:isAttachedItem(it) return rawget(self, 'attached') ~= nil and self.attached[it] == true end
getItemNameFromFullType = function(t) return 'name:' .. t end
GROUND = {}
local Sq = getmetatable(HARNESS.square(0, 0, 0))
local addWorld = Sq.AddWorldInventoryItem
function Sq:AddWorldInventoryItem(it, ...)
    local out = addWorld(self, it, ...)
    GROUND[#GROUND + 1] = it
    return out
end
-- Objets dans l'inventaire d'un joueur : identifiants.
function GIVE(name, t, n)
    local inv = HARNESS.players[name]:getInventory()
    local ids = {}
    for _ = 1, n or 1 do
        local it = instanceItem(t)
        inv:AddItem(it)
        ids[#ids + 1] = it.id
    end
    return ids
end
function WATER(name)
    local it = instanceItem('Base.WaterBottle')
    it.fc:Empty() it.fc:addFluid(Fluid.Water, 1)
    HARNESS.players[name]:getInventory():AddItem(it)
    return it.id
end
-- Identifiants des n premiers objets de type t de l'offre (côté take).
function OFFER_IDS(offer, t, n)
    local out = {}
    for _, e in ipairs(offer.take) do
        if e.t == t and #out < n then out[#out + 1] = e.i end
    end
    return out
end
-- Retire l'objet id d'un conteneur du foyer (un membre l'a pris).
function TAKE_AWAY(gid, id)
    local g = LivingKnox.Groups.get(gid)
    local style, def = LivingKnox.Homes.ready(g.home)
    for _, ct in ipairs(assert(LivingKnox.Stock.containers(gid, g.home, style, def and def:getIDString()))) do
        for _, it in ipairs(ct.container.items.items) do
            if it.id == id then ct.container:DoRemoveItem(it) return true end
        end
    end
    return false
end
-- Nombre d'exemplaires de l'objet id partout : conteneurs du foyer, inventaires des joueurs, sol.
function WHERE(gid, id)
    local n, where = 0, {}
    local g = LivingKnox.Groups.get(gid)
    local style, def = LivingKnox.Homes.ready(g.home)
    for _, ct in ipairs(assert(LivingKnox.Stock.containers(gid, g.home, style, def and def:getIDString()))) do
        for _, it in ipairs(ct.container.items.items) do
            if it.id == id then n = n + 1 where[#where + 1] = ct.key end
        end
    end
    for name, p in pairs(HARNESS.players) do
        for _, it in ipairs(p:getInventory().items.items) do
            if it.id == id then n = n + 1 where[#where + 1] = 'inv:' .. name end
        end
    end
    for _, it in ipairs(GROUND) do
        if it.id == id then n = n + 1 where[#where + 1] = 'ground' end
    end
    return n, where[1]
end
'''

TRADE_FACTS = r'''
TRADES = {}
LivingKnox.listen('tradeDone', 'test', function(info) TRADES[#TRADES + 1] = info end)
'''


class Base(StockBase):
    mode = 'solo'
    members = 1

    def setUp(self):
        super().setUp()
        for m in (('solo',) if self.mode == 'solo' else ('server', 'A', 'B')):
            self.h.load(m, OFFSCREEN_DOUBLES)
            self.h.load(m, AID_DOUBLES)
            self.h.load(m, TRADE_DOUBLES)
            self.h.load(m, VALUES)
            self.h.load(m, TRADE)
        self.run_lua(ENGINE_STUBS)
        self.run_lua(TRADE_FACTS)
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)
        self.run_lua(f'BIND("A", "{KEY_A}")')
        if self.mode != 'solo':
            self.run_lua(f'BIND("B", "{KEY_B}")')
        self.gid = self.group(gtype='settlers', members=self.members)
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) local g = d.groups["{self.gid}"] '
                     f'for _, m in pairs(g.members) do m.npc = "lk-1" break end return true, true end))')
        self.minute()
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{self.gid}").stock.fill'), 'done')
        self.run_lua('HARNESS.place(HARNESS.players.A, 103, 104, 0)')
        self.run_lua('BODY("lk-1", 104, 104, 0)')

    def offer(self, key=KEY_A, player='A'):
        return self.run_lua(f'OFFER = {T}.offer("{self.gid}", "{key}", HARNESS.players.{player}) return OFFER')

    def propose(self, give, take, key=KEY_A, player='A'):
        lua = lambda ids: '{' + ', '.join(str(i) for i in ids) + '}'
        return self.run_lua(f'return {T}.propose("{self.gid}", "{key}", HARNESS.players.{player}, {lua(give)}, '
                            f'{lua(take)}, {{ npc = "lk-1" }})')

    def ids(self, code):
        return [int(i) for i in self.ev(code).values()]

    def where(self, item_id):
        n, w = self.run_lua(f'return WHERE("{self.gid}", {item_id})')
        return n, w

    def inv_ids(self, player='A'):
        return sorted(it.id for it in self.ev(f'HARNESS.players.{player}:getInventory():getItems().items').values())

    def trade_log(self):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{self.gid}").log').values() if e.kind == 'trade']

    def said(self):
        return [s.key for s in self.ev('SAID').values()]


class ValueTests(unittest.TestCase):
    """Barème partagé (sans le moteur)."""

    @classmethod
    def setUpClass(cls):
        import lupa
        cls.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        cls.tv = cls.rt.execute((LUA / VALUES).read_text(encoding='utf-8'))

    def test_values_match_the_validated_table(self):
        doc = (ROOT / 'docs' / 'specifications-techniques' / 'passeur-table.md').read_text(encoding='utf-8')
        self.assertIn('Table validée telle quelle', doc)
        cases = {'Antibiotics': 8, 'AntibioticsBox': 90, 'CigaretteCarton': 25, 'AssaultRifle': 20, '556Box': 8,
                 'Battery': 2, 'TinnedBeans': 2, 'Bullets9mmBox': 10, '308Box': 14, 'GoldBar': 40,
                 'Ring_Left_RingFinger_GoldDiamond': 8, 'Necklace_DogTag': 4, 'VHS_Home': 6, 'Coffee2': 4}
        for name, v in cases.items():
            with self.subTest(item=name):
                self.assertEqual(self.tv.VALUES['Base.' + name].v, v)
        classes = set(self.tv.CLASSES.values())
        for t, e in self.tv.VALUES.items():
            with self.subTest(t=t):
                self.assertTrue(t.startswith('Base.'))
                self.assertIsInstance(e.v, int)
                self.assertGreater(e.v, 0)
                self.assertIn(e.k, classes)

    @unittest.skipUnless(VANILLA_ITEMS.is_dir(), 'vanilla 42.21 scripts not installed')
    def test_every_listed_item_exists_in_the_vanilla_scripts(self):
        declared = set()
        for f in VANILLA_ITEMS.glob('*.txt'):
            declared.update(re.findall(r'^\s*item\s+(\S+)\s*$', f.read_text(encoding='utf-8', errors='replace'),
                                       re.M))
        missing = sorted(t for t in self.tv.VALUES.keys() if t[5:] not in declared)
        self.assertEqual(missing, [])

    def test_prices_and_rounding(self):
        tv = self.tv
        self.assertEqual(tv.linePrice(2, 10, 1.1), 22)       # exemple de la section 5
        self.assertEqual(tv.linePrice(10, 1, 1.1), 11)       # 11,000000000000002 : pas 12
        self.assertEqual(tv.linePrice(8, 2, 1.25), 20)
        total = tv.askTotal(self.rt.eval('{ { t = "Base.TinnedBeans", v = 2 }, { t = "Base.CannedCorn", v = 2 }, '
                                         '{ t = "Base.TinnedBeans", v = 2 } }'), 1.1)
        self.assertEqual(total[0], 5 + 3)   # ceil(4,4) + ceil(2,2)
        self.assertEqual(tv.giveTotal(self.rt.eval('{ 1.5, 1.5, 0.5 }')), 3)
        self.assertEqual(tv.value('Base.Crackers', 'food')[0], 2)       # repli de catégorie
        self.assertEqual(tv.value('Base.Bullets9mm', 'ammo')[0], 0)  # munitions en vrac : aucune valeur
        self.assertEqual(tv.value('RadioSurvivor.NoteWalt', 'food')[0], 0)
        self.assertEqual(tuple(tv.value('Base.Necklace_Gold')), (4, 'valuables'))


class TradeTests(Base):
    def setUp(self):
        super().setUp()
        # Un membre : visées nourriture 3, eau 3, soins 1, munitions 1, matériaux 1 ; stock : nourriture 8, eau 3,
        # soins 6, munitions 1, matériaux 4.
        self.batteries = self.ids('GIVE("A", "Base.Battery", 3)')

    def test_buy_factor_follows_the_reserve_scale(self):
        cases = [(0, 4, 1.5), (1, 4, 1.5), (2, 4, 1.0), (4, 4, 0.5), (6, 4, 0.5), (7, 4, 0)]
        for have, want, f in cases:
            with self.subTest(have=have, want=want):
                self.assertEqual(self.ev(f'{T}.buyFactor("food", {{ have = {{ food = {have} }}, '
                                         f'want = {{ food = {want} }} }})'), f)
        self.assertEqual(self.ev(f'{T}.buyFactor(nil, nil)'), 1)

    def test_offer_lists_what_each_side_can_trade(self):
        self.run_lua('GIVE("A", "Base.Necklace_Gold") GIVE("A", "Base.Hammer") GIVE("A", "RadioSurvivor.NoteWalt")')
        water = self.ev('WATER("A")')
        o = self.offer()
        self.assertAlmostEqual(o.k, 1.1)
        give = {e.i: (e.t, e.v) for e in o.give.values()}
        self.assertEqual(give, {**{i: ('Base.Battery', 2) for i in self.batteries}, water: ('Base.WaterBottle', 1)})
        take = [(e.t, e.v) for e in o.take.values()]
        cats = self.run_lua('local n = {} for _, e in ipairs(OFFER.take) do '
                            'local c = LivingKnox.Stock.categoryOf(instanceItem(e.t)) n[c] = (n[c] or 0) + 1 end '
                            'return n')
        # Le surplus seulement : nourriture 8 - 3, soins 6 - 1, matériaux 4 - 1 ; eau et munitions à leur visée.
        self.assertEqual(dict(cats.items()), {'food': 5, 'medical': 5, 'materials': 3})
        self.assertNotIn(('Base.Hammer', 0), take)

    def test_trade_moves_each_item_once_and_updates_the_reference(self):
        o = self.offer()
        beans = self.ids(f'OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        self.assertEqual(len(beans), 2)
        food = self.ev(f'{ST}.needs("{self.gid}").have.food')
        out = self.propose(self.batteries, beans)
        self.assertEqual((out.ok, out.reason, out.given, out.asked), (True, 'done', 6, 5))   # ceil(2 x 2 x 1,1)
        self.assertEqual(self.inv_ids(), sorted(beans))
        for i in beans:
            self.assertEqual(self.where(i), (1, 'inv:A'))
        dest = self.run_lua(f'local g = LivingKnox.Groups.get("{self.gid}") local style, def = '
                            f'LivingKnox.Homes.ready(g.home) for _, ct in ipairs(LivingKnox.Stock.containers('
                            f'"{self.gid}", g.home, style, def and def:getIDString())) do if ct.owned then '
                            f'return ct.key end end')
        for i in self.batteries:
            self.assertEqual(self.where(i), (1, dest))
        self.assertEqual(self.ev(f'{ST}.needs("{self.gid}").have.food'), food - 2)
        ref = self.ids(f'REF_IDS("{self.gid}")')
        self.assertEqual(ref, self.ids(f'REAL_IDS("{self.gid}")'))
        self.assertFalse(set(beans) & set(ref))
        # Relecture suivante : ni perte ni vol.
        r = self.check(self.gid)
        self.assertEqual((r.action, r.missing, len(list(r.thefts.values()))), ('checked', 0, 0))
        self.assertEqual(self.ev(f'LivingKnox.Hostility.get("{self.gid}", "{KEY_A}").trend'), 'stable')
        self.assertEqual(self.trade_log(), [f'trade with {KEY_A}: got Base.Battery, Base.Battery, Base.Battery; '
                                            f'gave Base.TinnedBeans, Base.TinnedBeans (6 for 5)'])
        facts = [dict(f.items()) for f in self.ev('TRADES').values()]
        self.assertEqual([(f['group'], f['player'], f['given'], f['asked'], f['npc']) for f in facts],
                         [(self.gid, KEY_A, 6, 5, 'lk-1')])
        self.assertEqual(self.said(), ['IGUI_LK_Trade_Done'])
        # Même proposition renvoyée (double clic) : refus « gone », rien ne bouge.
        again = self.propose(self.batteries, beans)
        self.assertEqual((again.ok, again.reason), (False, 'gone'))
        self.assertEqual(self.inv_ids(), sorted(beans))

    def test_traded_items_can_be_bought_back_from_the_crate(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        self.assertTrue(self.propose(self.batteries, beans).ok)
        o = self.offer()
        back = [e.i for e in o.take.values() if e.t == 'Base.Battery']
        self.assertEqual(sorted(back), sorted(self.batteries))   # caisse du groupe : objets du barème hors stock
        self.assertEqual(sorted(e.i for e in o.give.values()), [])   # conserves : réserve de nourriture pleine

    def test_price_refusal_moves_nothing(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        before = self.ids(f'REF_IDS("{self.gid}")')
        out = self.propose(self.batteries[:1], beans)
        self.assertEqual((out.ok, out.reason, out.detail), (False, 'price', 'give 2, ask 5'))
        self.assertEqual(self.inv_ids(), sorted(self.batteries))
        self.assertEqual(self.ids(f'REF_IDS("{self.gid}")'), before)
        self.assertEqual(self.trade_log(), [])
        self.assertEqual(self.said(), ['IGUI_LK_Trade_Refuse_price'])

    def test_group_does_not_sell_what_it_lacks(self):
        # Eau : 3 pour une visée de 3. Une bouteille demandée seule fait passer sous la visée.
        bottle = self.run_lua(f'for _, e in ipairs(LivingKnox.Stock.reference("{self.gid}").items) do '
                              f'if e.c == "water" then return e.i end end')
        out = self.propose(self.batteries, [bottle])
        self.assertEqual((out.reason, out.detail), ('short', 'water: have 3, keep 3, after 2'))
        self.assertEqual(self.where(bottle)[0], 1)
        self.assertNotIn(bottle, self.inv_ids())
        # Contre une bouteille d'eau du joueur, la réserve reste à sa visée : accepté (1 + 2 = 3 >= ceil(2 x 1,1)).
        water = self.ev('WATER("A")')
        out = self.propose([water, self.batteries[0]], [bottle])
        self.assertEqual((out.ok, out.given, out.asked), (True, 3, 3))
        self.assertEqual(self.ev(f'{ST}.needs("{self.gid}").have.water'), 3)

    def test_refusals_for_items_the_group_will_not_take(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 1)')
        cases = [
            ('local id = GIVE("A", "Base.Necklace_Gold")[1] return id', 'unwanted', 'Base.Necklace_Gold'),
            ('local id = GIVE("A", "RadioSurvivor.NoteWalt")[1] return id', 'unwanted', 'RadioSurvivor.NoteWalt'),
            ('local id = GIVE("A", "Base.TinnedBeans")[1] return id', 'unwanted', 'Base.TinnedBeans'),  # pleine
            ('local id = GIVE("A", "Base.Battery")[1] local p = HARNESS.players.A '
             'p.worn = { [p:getInventory():getItemWithIDRecursiv(id)] = true } return id', 'worn', 'Base.Battery'),
            ('local id = GIVE("A", "Base.Battery")[1] HARNESS.players.A:getInventory():getItemWithIDRecursiv(id).fav '
             '= true return id', 'worn', 'Base.Battery'),
            ('local id = GIVE("A", "Base.Bag_Schoolbag")[1] local bag = HARNESS.players.A:getInventory()'
             ':getItemWithIDRecursiv(id) bag.inner:AddItem(instanceItem("Base.Battery")) return id', 'unwanted',
             'Base.Bag_Schoolbag'),
        ]
        for code, reason, item in cases:
            with self.subTest(item=item, reason=reason):
                bad = self.run_lua(code)
                out = self.propose(self.batteries + [bad], beans)
                self.assertEqual((out.ok, out.reason, out.item), (False, reason, item))
                self.assertIn(bad, self.inv_ids())
        self.assertEqual(self.trade_log(), [])
        # Matériel militaire usé (état < 50 %) : sans valeur.
        hat = self.run_lua('local id = GIVE("A", "Base.Hat_Army")[1] HARNESS.players.A:getInventory()'
                           ':getItemWithIDRecursiv(id).cond = 4 return id')
        self.assertEqual(self.propose([hat], beans).reason, 'unwanted')

    def test_refused_by_attitude(self):
        for _ in range(4):
            self.run_lua(f'assert(LivingKnox.Hostility.record("{self.gid}", "{KEY_A}", "theft", '
                         f'{{ attributable = true }}))')
        level = self.ev(f'LivingKnox.Hostility.get("{self.gid}", "{KEY_A}").level')
        self.assertIn(level, ('wary', 'hostile'))
        self.assertEqual(self.run_lua(f'return (select(2, {T}.offer("{self.gid}", "{KEY_A}", '
                                      f'HARNESS.players.A)))'), 'attitude')
        out = self.propose(self.batteries, [1])
        self.assertEqual((out.reason, out.detail), ('attitude', level))

    def test_items_gone_since_the_offer(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        # L'objet du joueur est passé dans un sac (plus au premier niveau de l'inventaire) : refus « gone ».
        self.run_lua(f'local inv = HARNESS.players.A:getInventory() local bag = instanceItem("Base.Bag_Schoolbag") '
                     f'inv:AddItem(bag) bag.inner:AddItem(inv:getItemWithIDRecursiv({self.batteries[0]}))')
        self.assertEqual(self.propose(self.batteries, beans).reason, 'gone')
        # Un objet du groupe pris entre-temps (mangé par un membre) : refus « gone ».
        self.assertTrue(self.ev(f'TAKE_AWAY("{self.gid}", {beans[0]})'))
        self.assertEqual(self.propose(self.batteries[1:], beans).reason, 'gone')

    def test_bad_lists_and_empty_sides(self):
        cases = [('{}', '{ 1 }', 'empty'), ('{ 1 }', '{}', 'empty'), ('{ 1, 1 }', '{ 2 }', 'empty'),
                 ('{ 1.5 }', '{ 2 }', 'empty'), ('{ "x" }', '{ 2 }', 'empty'), ('nil', '{ 2 }', 'empty')]
        for give, take, reason in cases:
            with self.subTest(give=give, take=take):
                out = self.run_lua(f'return {T}.propose("{self.gid}", "{KEY_A}", HARNESS.players.A, {give}, {take})')
                self.assertEqual((out.ok, out.reason), (False, reason))
        many = '{' + ', '.join(str(i) for i in range(1, 30)) + '}'
        self.assertEqual(self.run_lua(f'return {T}.propose("{self.gid}", "{KEY_A}", HARNESS.players.A, {many}, '
                                      f'{{ 1 }}).detail'), 'bad item list')

    def test_unreadable_home_is_refused(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        self.run_lua('REAL_READY = LivingKnox.Homes.ready LivingKnox.Homes.ready = function() return nil, "unloaded" end')
        out = self.propose(self.batteries, beans)
        self.run_lua('LivingKnox.Homes.ready = REAL_READY')
        self.assertEqual(out.reason, 'away')
        self.assertEqual(self.inv_ids(), sorted(self.batteries))

    def test_registry_not_written_moves_nothing(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        self.run_lua('REAL_UPDATE = LivingKnox.Groups.update '
                     'LivingKnox.Groups.update = function() return nil, "refused" end')
        out = self.propose(self.batteries, beans)
        self.run_lua('LivingKnox.Groups.update = REAL_UPDATE')
        self.assertEqual((out.ok, out.reason, out.detail), (False, 'away', 'registry not written'))
        self.assertEqual(self.inv_ids(), sorted(self.batteries))
        for i in beans:
            self.assertEqual(self.where(i)[0], 1)

    def test_failed_move_puts_the_item_back(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        # Le rangement de la deuxième pile dans la caisse échoue : elle revient dans l'inventaire du joueur.
        self.run_lua('local Ctr = getmetatable(NEW_CONTAINER("x")) local add = Ctr.AddItem local n = 0 '
                     'Ctr.AddItem = function(self, it) if self.type ~= "none" and it.type == "Base.Battery" then '
                     'n = n + 1 if n == 2 then error("boom") end end return add(self, it) end')
        out = self.propose(self.batteries, beans)
        self.assertTrue(out.ok)
        self.assertEqual(out.failed, 1)
        self.assertEqual(sum(1 for i in self.batteries if self.where(i)[1] == 'inv:A'), 1)
        for i in self.batteries + beans:
            self.assertEqual(self.where(i)[0], 1)

    def test_overloaded_player_gets_items_at_his_feet(self):
        self.offer()
        beans = self.ids('OFFER_IDS(OFFER, "Base.TinnedBeans", 2)')
        self.run_lua('CAPACITY = 0')
        out = self.propose(self.batteries, beans)
        self.assertEqual((out.ok, out.ground), (True, 2))
        self.assertEqual(self.inv_ids(), [])
        for i in beans:
            self.assertEqual(self.where(i), (1, 'ground'))
        self.assertEqual(self.ev('#HARNESS.square(103, 104, 0).ground'), 2)

    def test_request_checks_distance_identity_and_echoes_the_number(self):
        req = f'{T}.request(HARNESS.players.A, {{ op = "open", n = 7, npc = "lk-1" }})'
        out = self.ev(req)
        self.assertEqual((out.op, out.n, out.ok, out.npc), ('open', 7, True, 'lk-1'))
        self.assertEqual(len(list(out.offer.give.values())), 3)
        self.run_lua('HARNESS.place(HARNESS.players.A, 110, 104, 0)')
        self.assertEqual(self.run_lua(f'return select(2, {req})'), 'too far')
        self.run_lua('HARNESS.place(HARNESS.players.A, 103, 104, 0)')
        self.run_lua('RS_CarnetServer.bound[HARNESS.players.A] = nil')
        out = self.ev(req)
        self.assertEqual((out.ok, out.reason, out.line), (False, 'stranger', 'IGUI_LK_Trade_Refuse_stranger'))
        for bad in ('{ op = "steal", n = 1, npc = "lk-1" }', '{ op = "open", npc = "lk-1" }',
                    '{ op = "open", n = 1, npc = 3 }', 'nil'):
            with self.subTest(bad=bad):
                self.assertEqual(self.run_lua(f'return select(2, {T}.request(HARNESS.players.A, {bad}))'),
                                 'bad request')


class ViewTests(Base):
    def setUp(self):
        super().setUp()
        self.run_lua(MENU_DOUBLES)
        self.h.load(self.srv, RVIEW)
        self.h.load(self.srv, VIEW)
        self.batteries = self.ids('GIVE("A", "Base.Battery", 3)')

    def test_menu_opens_the_offer_and_the_window_proposes(self):
        ctx = self.run_lua('local ctx = NEW_MENU() LivingKnox.TradeView.fill(0, ctx, CLICK(104, 104), false) '
                           'return ctx')
        opts = list(ctx.options.values())
        self.assertEqual([(o.name, o.target) for o in opts], [('IGUI_LK_Trade_Menu', 'lk-1')])
        self.run_lua('local o = NEW_MENU() LivingKnox.TradeView.fill(0, o, CLICK(104, 104), false) '
                     'o.options[1].fn(o.options[1].target)')
        st = self.ev('LivingKnox.TradeView.state')
        self.assertIsNone(st.pending)
        self.assertEqual(len(list(st.offer.give.values())), 3)
        # Coche : trois piles et deux conserves ; totaux du barème partagé.
        self.run_lua('local V = LivingKnox.TradeView for _, e in ipairs(V.state.offer.give) do V.toggle("give", e.i) end '
                     'local n = 0 for _, e in ipairs(V.state.offer.take) do if e.t == "Base.TinnedBeans" and n < 2 then '
                     'V.toggle("take", e.i) n = n + 1 end end')
        self.assertEqual(tuple(self.run_lua('return LivingKnox.TradeView.totals()')), (6, 5))
        self.assertTrue(self.ev('LivingKnox.TradeView.propose()'))
        self.assertEqual(self.ev('LivingKnox.TradeView.state.status'), 'IGUI_LK_Trade_Done')
        self.assertEqual(len([i for i in self.inv_ids() if i not in self.batteries]), 2)
        self.assertEqual(self.ev('LivingKnox.TradeView.rowText({ t = "Base.Battery", v = 1.5 }, true)'),
                         '[x] name:Base.Battery  IGUI_LK_Trade_Points')

    def test_nothing_ticked_is_not_sent(self):
        self.run_lua('LivingKnox.TradeView.open("lk-1")')
        sent = self.ev('LivingKnox.TradeView.stats.sent')
        self.assertIsNone(self.ev('LivingKnox.TradeView.propose()'))
        self.assertEqual(self.ev('LivingKnox.TradeView.stats.sent'), sent)
        self.assertEqual(self.ev('LivingKnox.TradeView.state.status'), 'IGUI_LK_Trade_Refuse_empty')

    def test_controller_probe_adds_nothing(self):
        ctx = self.run_lua('local ctx = NEW_MENU() LivingKnox.TradeView.fill(0, ctx, CLICK(104, 104), true) '
                           'return ctx')
        self.assertEqual(len(list(ctx.options.values())), 0)
        self.assertTrue(self.ev('MENU.tested'))

    def test_constants_match_the_server(self):
        for k in ('MODULE', 'CMD_REQUEST', 'CMD_REPLY'):
            self.assertEqual(self.ev(f'LivingKnox.TradeView.{k}'), self.ev(f'{T}.{k}'))


class MultiplayerTests(Base):
    mode = 'mp'

    def setUp(self):
        super().setUp()
        self.run_lua('HARNESS.place(HARNESS.players.B, 103, 105, 0)')
        for c in ('A', 'B'):
            self.h.load(c, MENU_DOUBLES)
            self.h.load(c, RVIEW)
            self.h.load(c, VIEW)
        self.bat_a = self.ids('GIVE("A", "Base.Battery", 3)')
        self.bat_b = self.ids('GIVE("B", "Base.Battery", 3)')

    def open(self, c):
        self.h.eval(c, 'LivingKnox.TradeView.open("lk-1")')
        self.h.pump()
        return self.h.eval(c, 'LivingKnox.TradeView.state.offer')

    def tick(self, c, ids_give, ids_take):
        code = 'local V = LivingKnox.TradeView '
        code += ' '.join(f'V.toggle("give", {i})' for i in ids_give) + ' '
        code += ' '.join(f'V.toggle("take", {i})' for i in ids_take)
        self.h.load(c, code)

    def test_two_clients_cannot_get_the_same_item(self):
        offer_a, offer_b = self.open('A'), self.open('B')
        beans_a = [e.i for e in offer_a.take.values() if e.t == 'Base.TinnedBeans'][:2]
        beans_b = [e.i for e in offer_b.take.values() if e.t == 'Base.TinnedBeans'][:2]
        self.assertEqual(beans_a, beans_b)   # même stock, même offre
        self.tick('A', self.bat_a, beans_a)
        self.tick('B', self.bat_b, beans_b)
        removed, added = self.ev('COUNT.removeSent'), self.ev('COUNT.addSent')
        self.h.eval('A', 'LivingKnox.TradeView.propose()')
        self.h.eval('B', 'LivingKnox.TradeView.propose()')
        self.h.pump()
        self.assertEqual(self.h.eval('A', 'LivingKnox.TradeView.state.status'), 'IGUI_LK_Trade_Done')
        self.assertEqual(self.h.eval('B', 'LivingKnox.TradeView.state.status'), 'IGUI_LK_Trade_Refuse_gone')
        self.assertEqual(sorted(set(self.inv_ids('A')) - set(self.bat_a)), sorted(beans_a))
        self.assertEqual(self.inv_ids('B'), sorted(self.bat_b))
        for i in beans_a + self.bat_a:
            self.assertEqual(self.where(i)[0], 1)
        # Cinq objets déplacés : un retrait et un ajout envoyés pour chacun (inventaire du joueur, caisse).
        self.assertEqual((self.ev('COUNT.removeSent') - removed, self.ev('COUNT.addSent') - added), (5, 5))
        # Offres à jour chez les deux clients ; rien du module d'autorité sur un client.
        self.assertNotIn(beans_a[0], [e.i for e in self.h.eval('B', 'LivingKnox.TradeView.state.offer').take.values()])
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, T))

    def test_disconnect_before_the_proposal_is_processed_moves_nothing(self):
        offer = self.open('A')
        beans = [e.i for e in offer.take.values() if e.t == 'Base.TinnedBeans'][:2]
        self.tick('A', self.bat_a, beans)
        before = self.ids(f'REF_IDS("{self.gid}")')
        self.h.eval('A', 'LivingKnox.TradeView.propose()')
        self.run_lua('GONE_A = HARNESS.players.A HARNESS.players.A = nil')   # déconnexion : paquet jamais traité
        self.h.pump()
        self.assertEqual(self.ids(f'REF_IDS("{self.gid}")'), before)
        self.assertEqual(sorted(it.id for it in self.ev('GONE_A:getInventory():getItems().items').values()),
                         sorted(self.bat_a))
        self.assertEqual(self.trade_log(), [])

    def test_disconnect_after_the_trade_keeps_it_on_the_server(self):
        offer = self.open('A')
        beans = [e.i for e in offer.take.values() if e.t == 'Base.TinnedBeans'][:2]
        self.tick('A', self.bat_a, beans)
        self.h.eval('A', 'LivingKnox.TradeView.propose()')
        self.h.pump(limit=1)                                 # proposition traitée, réponse encore en route
        self.run_lua('GONE_A = HARNESS.players.A HARNESS.players.A = nil')
        self.h.queue = [m for m in self.h.queue if m['to'] != 'A']   # réponse perdue avec la connexion
        self.h.pump()
        inv = sorted(it.id for it in self.ev('GONE_A:getInventory():getItems().items').values())
        self.assertEqual(inv, sorted(beans))                 # inventaire du serveur, sauvegardé avec le joueur
        self.assertEqual(len(self.trade_log()), 1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.TradeView.state.pending'), 2)   # réponse perdue

    def test_far_player_gets_an_unavailable_reply(self):
        self.run_lua('HARNESS.place(HARNESS.players.B, 120, 105, 0)')
        self.open('B')
        self.assertEqual(self.h.eval('B', 'LivingKnox.TradeView.state.status'), 'IGUI_LK_Trade_Unavailable')
        self.assertIsNone(self.h.eval('B', 'LivingKnox.TradeView.state.offer'))


class TranslationTests(unittest.TestCase):
    def test_every_key_is_translated(self):
        tr = LUA / 'shared' / 'Translate'
        src = (LUA / TRADE).read_text(encoding='utf-8')
        m = re.search(r'Trade\.REASONS = \{([^}]*)\}', src)
        reasons = re.findall(r'"(\w+)"', m.group(1))
        self.assertEqual(len(reasons), 9)
        keys = {f'IGUI_LK_Trade_Refuse_{r}' for r in reasons} | {'IGUI_LK_Trade_Done'}
        view = (LUA / VIEW).read_text(encoding='utf-8')
        keys |= {f'IGUI_LK_Trade_{k}' for k in re.findall(r'tr\("(\w+)"', view)}
        self.assertGreater(len(keys), 15)
        for lang in ('EN', 'FR'):
            data = json.loads((tr / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for k in sorted(keys):
                with self.subTest(lang=lang, key=k):
                    self.assertIn(k, data)
                    data[k].encode('latin-1')   # police des bulles : Latin-1 seulement

    def test_sources_have_ascii_code_only(self):
        for path in (TRADE, VIEW, VALUES):
            text = (LUA / path).read_text(encoding='utf-8')
            for n, line in enumerate(text.splitlines(), 1):
                code = line.split('--', 1)[0]
                with self.subTest(path=path, line=n):
                    self.assertTrue(code.isascii(), line)
            self.assertIsNone(re.search(r'\bgoto\b|\bnext\(|coroutine\.', text), path)


SUITE = 'trade moves each item once, the group keeps its reserves'


class SuiteTests(StockBase):
    """La suite en jeu lk.trade passe dans le banc (joueur debout dans la maison de test)."""

    def run_suite(self, prep=''):
        self.h.load(self.srv, OFFSCREEN_DOUBLES)
        self.h.load(self.srv, AID_DOUBLES)
        self.h.load(self.srv, TRADE_DOUBLES)
        self.h.load(self.srv, VALUES)
        self.h.load(self.srv, TRADE)
        if prep:
            self.run_lua(prep)
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, 'shared/RST/suites/RST_LKTrade.lua')
        self.run_lua('local p = HARNESS.players.A HARNESS.place(p, 103, 104, 0) PLAYER = p')
        self.assertTrue(self.ev('RST.start({ suite = "lk.trade", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(400):
            if not self.ev('RST.step()'):
                break
            self.h.advance_ms(100)
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_cleans_up(self):
        report, results = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 1)
        self.assertEqual(len(list(self.ev('LivingKnox.Groups.list()').values())), 0)
        self.assertEqual(self.ev('HARNESS.players.A:getInventory():getItems():size()'), 0)

    def test_suite_detects_a_duplicated_item(self):
        # Défaut injecté : le groupe garde une copie de ce qu'il cède -> la suite échoue.
        _, results = self.run_suite('local apply = LivingKnox.Trade.apply LivingKnox.Trade.apply = function(gid, k, p, ev) '
                                    'for _, e in ipairs(ev.takes) do e.container:AddItem(instanceItem(e.t)) end '
                                    'local ok, out = apply(gid, k, p, ev) '
                                    'for _, e in ipairs(ev.takes) do local c = instanceItem(e.t) c.id = e.i '
                                    'e.container:AddItem(c) end return ok, out end')
        self.assertEqual(results[SUITE][0], 'FAIL')


if __name__ == '__main__':
    unittest.main()
