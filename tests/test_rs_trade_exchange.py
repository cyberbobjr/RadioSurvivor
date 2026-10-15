"""Échange sans contact sur la berge (E13-T04) : RS_TradeExchange.lua avec RS_Trade.lua et RS_TradeRun.lua dans lupa.

    python RadioSurvivor/tests/test_rs_trade_exchange.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) : RS_TradeExchange, RS_Trade, RS_TradeRun, RS_Actions,
RS_TradeValues, RS_Reputation, RS_OutsideNews ; doublures (celles de test_rs_trade_run.py, plus) : objets
d'inventaire (type, nom affiché et nom du script, état, utilisations, poids, ModData, contenu), sacs au sol et cellule
(cases chargées ou non), instanceItem, envois sendAddItemToContainer / sendRemoveItemFromContainer, création du
journal du dehors. Couvre : barème et conditions de la table (état, filtre, sac vide, papiers nominatifs, nom d'un
joueur, objets du mod ou hors Base, billets par lots, portefeuille, plafonds par type, par classe, pièces, points et
kilos), prise limitée au prix, échange fait une seule fois (joueur proche = attente, joueur revenu, second sondage),
tricherie (rien pris ni donné, marge au plus haut, fait de réputation non appliqué, annonce), sac sans valeur ignoré,
départ sans sac, zone non chargée, reprise d'un échange appliqué sans état écrit, annonces traduites.
Ne prouve ni l'API Java réelle ni la synchronisation MP : suite en jeu rs.trade_exchange.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_rs_trade_run import EN, FR, LUA, ROOT, RunHarness, lua_list  # noqa: E402

EXCHANGE_LUA = LUA / 'server/RadioSurvivor/RS_TradeExchange.lua'
SUITE = ROOT / 'dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RS_TradeExchange.lua'

WORLD = r"""
NEXT_ID = 100
local function list(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end
function makeContainer(items)
    local c = { list = items or {} }
    c.getItems = function(self) return list(self.list) end
    c.isEmpty = function(self) return #self.list == 0 end
    c.DoRemoveItem = function(self, item)
        for i, x in ipairs(self.list) do if x == item then table.remove(self.list, i) return end end
    end
    c.AddItem = function(self, item) self.list[#self.list + 1] = item return item end
    return c
end
-- o : name (nom affiché), base (nom du script), cond, condMax, uses, w, md, items (sac).
function makeItem(fullType, o)
    o = o or {}
    local it = { t = fullType, name = o.name or fullType, base = o.base or fullType, cond = o.cond or 10,
        condMax = o.condMax or 10, uses = o.uses or 1, w = o.w or 0.1, md = o.md, id = NEXT_ID }
    NEXT_ID = NEXT_ID + 1
    if o.items then it.inv = makeContainer(o.items) end
    function it:getFullType() return self.t end
    function it:getID() return self.id end
    function it:getDisplayName() return self.name end
    function it:getScriptItem() local b = self.base return { getDisplayName = function() return b end } end
    function it:hasModData() return self.md ~= nil end
    function it:getModData() self.md = self.md or {} return self.md end
    function it:getCondition() return self.cond end
    function it:getConditionMax() return self.condMax end
    function it:getCurrentUsesFloat() return self.uses end
    function it:getInventory() return self.inv end
    function it:getUnequippedWeight()
        local w = self.w
        if self.inv then for _, x in ipairs(self.inv.list) do w = w + x:getUnequippedWeight() end end
        return w
    end
    return it
end
instanceof = function(o, cls) return cls == "InventoryContainer" and type(o) == "table" and o.inv ~= nil end
instanceItem = function(t) return makeItem(t) end
SENT = {}
sendRemoveItemFromContainer = function(c, item) SENT[#SENT + 1] = "remove:" .. item:getFullType() end
sendAddItemToContainer = function(c, item) SENT[#SENT + 1] = "add:" .. item:getFullType() end
SQUARES = {}
LOADED = true
getCell = function() return { getGridSquare = function(_, x, y, z)
    if not LOADED or z ~= 0 then return nil end
    local items = SQUARES[x .. "," .. y] or {}
    local wos = {}
    for i, item in ipairs(items) do wos[i] = { getItem = function() return item end } end
    return { getWorldObjects = function() return list(wos) end }
end } end
function dropBag(x, y, items)
    local bag = makeItem("Base.Bag_Schoolbag", { items = items or {}, w = 0.5 })
    local key = x .. "," .. y
    SQUARES[key] = SQUARES[key] or {}
    table.insert(SQUARES[key], bag)
    return bag
end
NEWS = 0
package.preload["RadioSurvivor/RS_OutsideNewsServer"] = function() return {
    create = function(passage) NEWS = NEWS + 1 return makeItem("RadioSurvivor.OutsideNews", { md = { edition = passage } }) end }
end
package.preload["RadioSurvivor/RS_Config"] = function() return { Reputation = { success = 5, failure = -5 } } end
"""

ID_BASE = 'ID Card'


class ExchangeHarness(RunHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute(WORLD)
        self.Ex = self.rt.eval('require("RadioSurvivor/RS_TradeExchange")')
        self.g.STATE.data.outcomes = self.rt.table_from({})
        self.item = self.g.makeItem

    def it(self, full, **o):
        return self.item('Base.' + full if '.' not in full else full, self.t(o) if o else None)

    def bag_items(self, bag):
        return [x.t for x in lua_list(bag.inv.list)]

    def sent(self):
        return lua_list(self.g.SENT)

    def arrived(self, items='Antibiotics:2', hours=18.5):
        """kate (fac-1) réserve à 4 h, la barque arrive au ponton à `hours` ; kate reste au ponton."""
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, items), 'ok')
        self.g.CLOCK.hours = hours
        kate.x, kate.y = 6041, 5217
        self.assertTrue(self.T.arrive('lamp'))
        return kate

    def appraise(self, items, names=None, need=None):
        return self.Ex.appraise(self.t(items), self.t(names or []), need)


class AppraiseTests(ExchangeHarness):

    def test_values_and_conditions_of_the_table(self):
        named = dict(name='ID Card: John Doe', base=ID_BASE)
        cases = [
            ([self.it('MoneyBundle'), self.it('Necklace_Gold')], 14),
            ([self.it('IDcard', **named), self.it('IDcard', name=ID_BASE, base=ID_BASE)], 3),   # sans nom : refusée
            ([self.it('IDcard', name='ID Card: Kate Miller', base=ID_BASE)], 0),               # nom d'un joueur
            ([self.it('AssaultRifle', cond=4)], 0), ([self.it('AssaultRifle', cond=6)], 20),
            ([self.it('GasmaskFilter', uses=0.4)], 0), ([self.it('GasmaskFilter', uses=0.5)], 2),
            ([self.it('Bag_ALICEpack_Army', items=[self.it('Hammer')])], 0), ([self.it('Bag_ALICEpack_Army', items=[])], 5),
            ([self.it('CreditCard', name='Credit Card: Ann Lee', base='Credit Card')], 1),
            ([self.it('MoneyBundle', md={'RS_Cache': 'x'})], 0),                                # marque du mod
            ([self.it('MoneyBundle', md={'LKStock': 'g1'})], 0),
            ([self.it('MoneyBundle', md={'customName': 'x'})], 10),                             # ModData vanilla
            ([self.it('RadioSurvivor.OutsideNews')], 0), ([self.it('Hammer'), self.it('Photo')], 0),
            ([self.it('Battery')], 0),                                                          # ce qu'il apporte
            ([self.it('Money') for _ in range(25)], 2),                                         # lots entiers
            ([self.it('Money') for _ in range(130)], 10),                                       # 100 billets au plus
        ]
        for items, value in cases:
            res = self.appraise(items, ['Kate Miller'])
            self.assertEqual(res.value, value, [i.t for i in items])
        money = self.appraise([self.it('Money') for _ in range(25)])
        self.assertEqual(len(lua_list(money.taken)), 20)

    def test_wallet_counts_its_contents_and_is_taken_whole(self):
        inside = [self.it('IDcard', name='ID Card: John Doe', base=ID_BASE), self.it('Photo')]
        inside += [self.it('Money') for _ in range(12)]
        wallet = self.it('Wallet', items=inside)
        res = self.appraise([wallet])
        self.assertEqual(res.value, 1 + 3 + 1)
        self.assertEqual([x.t for x in lua_list(res.taken)], ['Base.Wallet'])
        self.assertEqual((res.byClass['papers'], res.byClass['valuables'], res.pieces), (4, 1, 2))

    def test_caps_by_type_class_pieces_points_and_weight(self):
        self.assertEqual(self.appraise([self.it('GoldBar', w=1), self.it('GoldBar', w=1)]).value, 40)    # 1 au plus
        self.assertEqual(self.appraise([self.it('MoneyBundle') for _ in range(7)]).value, 60)            # classe 60
        cards = [self.it('CreditCard', name=f'Credit Card: P{i} Q', base='Credit Card') for i in range(12)]
        self.assertEqual(self.appraise(cards).value, 10)                                                # 10 pièces
        self.assertEqual(self.appraise([self.it('GoldBar', w=16), self.it('SilverBar', w=10)]).value, 40)  # 20 kg
        lot = [self.it('MoneyBundle') for _ in range(6)] + [self.it('CameraExpensive') for _ in range(4)]
        lot += [self.it('Vest_BulletArmy') for _ in range(6)] + [self.it('Passport', name='Passport: A B', base='Passport')]
        res = self.appraise(lot)
        self.assertEqual(res.value, 120)                                                                # 120 points
        self.assertGreater(res.left, 0)

    def test_takes_only_what_covers_the_price(self):
        bundles = [self.it('MoneyBundle') for _ in range(3)]
        res = self.appraise(bundles, need=20)
        self.assertEqual((res.value, len(lua_list(res.taken))), (20, 2))
        res = self.appraise([self.it('Diamond'), self.it('GoldCoin')], need=11)
        self.assertEqual(res.value, 13)                                     # l'écart reste au passeur


class ExchangeTests(ExchangeHarness):

    def test_exchange_done_once(self):
        kate = self.arrived()
        offer = self.T.offerOf('kate', None)
        self.assertEqual(offer.price, 20)
        bag = self.g.dropBag(6042, 5216, self.t([
            self.it('MoneyBundle'), self.it('Necklace_Gold'), self.it('IDcard', name='ID Card: John Doe', base=ID_BASE),
            self.it('IDcard', name='ID Card: Jane Roe', base=ID_BASE), self.it('Hammer'), self.it('MoneyBundle')]))
        self.assertIsNone(self.Ex.update())                                 # kate encore au ponton
        self.assertEqual(self.sent(), [])
        kate.x = 6041 + 25
        self.assertEqual(self.Ex.update(), 'done')
        items = self.bag_items(bag)
        self.assertEqual(items, ['Base.Hammer', 'Base.MoneyBundle', 'Base.Antibiotics', 'Base.Antibiotics'])
        given = [x for x in lua_list(bag.inv.list) if x.t == 'Base.Antibiotics']
        self.assertTrue(all(x.md['RS_TradeGiven'] == offer.rev for x in given))
        self.assertEqual(self.sent(), ['remove:Base.MoneyBundle', 'remove:Base.Necklace_Gold', 'remove:Base.IDcard',
                                       'remove:Base.IDcard', 'add:Base.Antibiotics', 'add:Base.Antibiotics'])
        run = self.T.lastRun()
        self.assertEqual((run.state, run.reason, run.exchange.value, run.exchange.price, run.exchange.given),
                         ('done', 'done', 20, 20, 2))
        self.assertEqual(self.T.offerOf('kate', None).state, 'done')
        self.assertEqual(lua_list(self.T.deals('kate', None))[-1].state, 'done')
        self.assertEqual(self.T.available('bob', None).Antibiotics, 2)    # 4 tirés, 2 échangés
        self.assertEqual(self.aired(), [['<fzzt>', EN['IGUI_RS_TradeRun_Done'], '<szzt>']])
        # Joueur revenu, sondages suivants : rien de plus.
        kate.x = 6041
        for hours in (18.6, 19.0, 25.0):
            self.g.CLOCK.hours = hours
            self.assertIsNone(self.Ex.update())
        kate.x = 6041 + 25
        self.assertIsNone(self.Ex.update())
        self.assertEqual(len(self.bag_items(bag)), 4)
        self.assertEqual(len(self.sent()), 6)
        self.assertEqual(len(self.aired()), 1)
        self.assertEqual(self.decide(kate), 'run_over')

    def test_any_player_near_blocks_the_boat(self):
        kate = self.arrived()
        kate.x = 9000
        self.make('bob', 'fac-2', 6041 + 10, 5217)                          # autre équipe, sur la berge
        self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.assertIsNone(self.Ex.update())
        self.assertEqual(self.T.lastRun().state, 'arrived')

    def test_cheat_refused_nothing_moved_reputation_down(self):
        kate = self.arrived()
        bag = self.g.dropBag(6040, 5218, self.t([self.it('MoneyBundle'), self.it('SilverCoin'), self.it('Hammer')]))
        kate.x = 9000
        self.assertEqual(self.Ex.update(), 'cheated')
        self.assertEqual(self.bag_items(bag), ['Base.MoneyBundle', 'Base.SilverCoin', 'Base.Hammer'])
        self.assertEqual(self.sent(), [])
        run = self.T.lastRun()
        self.assertEqual((run.state, run.exchange.value, run.exchange.price), ('cheated', 12, 20))
        self.assertEqual(self.T.offerOf('kate', None).state, 'cheated')
        self.assertEqual(self.T.marginRange('kate', None)[0], 0.5)
        rev = self.T.offerOf('kate', None).rev
        fact = self.g.STATE.data.outcomes[f'trade-{rev}-cheated']
        self.assertEqual((fact.character, fact.action, fact.proposedDelta, fact.applied), ('kate', 'trade.cheated', -5, False))
        self.assertEqual(self.aired(), [['<fzzt>', EN['IGUI_RS_TradeRun_Cheated'], '<szzt>']])
        self.assertIsNone(self.Ex.update())
        self.assertEqual(self.decide(kate), 'run_over')

    def test_bag_without_value_ignored_then_no_drop(self):
        kate = self.arrived()
        kate.x = 9000
        self.assertIsNone(self.Ex.update())                                 # pas de sac
        self.g.dropBag(6041, 5217, self.t([self.it('Hammer'), self.it('MoneyBundle', md={'RS_Cache': 'm1'})]))
        self.assertIsNone(self.Ex.update())                                 # rien que le passeur prenne
        self.assertEqual(self.T.lastRun().state, 'arrived')
        self.g.CLOCK.hours = 20.5
        self.assertEqual(self.Ex.update(), 'no_drop')
        run = self.T.lastRun()
        self.assertEqual((run.state, run.reason), ('cancelled', 'no_drop'))
        self.assertEqual(self.T.offerOf('kate', None).state, 'cancelled')
        self.assertEqual(self.T.available('bob', None).Antibiotics, 4)    # réserve rendue
        self.assertEqual(self.aired(), [['<fzzt>', EN['IGUI_RS_TradeRun_Cancel_nodrop'], '<szzt>']])
        self.assertEqual(self.T.marginRange('kate', None)[0], 0.25)        # pas de tricherie

    def test_unloaded_pier_waits_then_leaves(self):
        kate = self.arrived()
        kate.x = 9000
        self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.g.LOADED = False
        self.assertIsNone(self.Ex.update())
        self.g.CLOCK.hours = 20.6
        self.assertEqual(self.Ex.update(), 'no_drop')
        self.assertEqual(self.sent(), [])

    def test_bag_outside_the_drop_zone_ignored(self):
        kate = self.arrived()
        kate.x = 9000
        self.g.dropBag(6041 + 4, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.assertIsNone(self.Ex.update())

    def test_best_bag_chosen(self):
        kate = self.arrived()
        kate.x = 9000
        poor = self.g.dropBag(6041, 5217, self.t([self.it('SilverCoin')]))
        rich = self.g.dropBag(6042, 5218, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.assertEqual(self.Ex.update(), 'done')
        self.assertEqual(self.bag_items(poor), ['Base.SilverCoin'])
        self.assertEqual(self.bag_items(rich), ['Base.Antibiotics', 'Base.Antibiotics'])

    def test_counterpart_already_in_a_bag_recovers_without_giving_again(self):
        kate = self.arrived()
        rev = self.T.offerOf('kate', None).rev
        given = self.it('Antibiotics', md={'RS_TradeGiven': rev})
        bag = self.g.dropBag(6041, 5217, self.t([given]))
        self.assertEqual(self.Ex.update(), 'done')                         # kate au ponton : reprise quand même
        self.assertEqual((self.T.lastRun().state, self.T.lastRun().reason), ('done', 'recovered'))
        self.assertEqual(self.bag_items(bag), ['Base.Antibiotics'])
        self.assertEqual(self.sent(), [])

    def test_outside_news_counterpart(self):
        stock = {e.n: 0 for e in lua_list(self.T.SUPPLY)}
        stock.update({'Battery': 10, 'Antibiotics': 4, 'OutsideNews': 1})
        self.T.drawStock = lambda seed, passage: self.rt.table_from(stock)
        kate = self.arrived('OutsideNews:1,Battery:2')
        kate.x = 9000
        bag = self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle')]))
        self.assertEqual(self.Ex.update(), 'done')
        self.assertEqual(sorted(self.bag_items(bag)), ['Base.Battery', 'Base.Battery', 'RadioSurvivor.OutsideNews'])
        self.assertEqual(self.g.NEWS, 1)

    def test_booked_run_not_exchanged_before_the_signal(self):
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 9000, 50)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.g.CLOCK.hours = 18.5
        self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.assertIsNone(self.Ex.update())
        self.assertEqual(self.T.lastRun().state, 'booked')

    def test_hook_installed(self):
        self.assertIsNotNone(self.g.HANDLERS['EveryOneMinute'])


class StaticTests(unittest.TestCase):

    def test_translations_and_fallbacks(self):
        source = (LUA / 'server/RadioSurvivor/RS_TradeRun.lua').read_text(encoding='utf-8')
        for name in ('Done', 'Cheated', 'Cancel_nodrop'):
            key = 'IGUI_RS_TradeRun_' + name
            self.assertIn(key, EN)
            self.assertIn(key, FR)
            self.assertNotIn('%', EN[key] + FR[key])
            self.assertLessEqual(len(FR[key]), 140)
            self.assertIn(f'{name} = "{EN[key]}"', source)
        self.assertIn('IGUI_RS_Event_trade_cheated', EN)
        self.assertIn('IGUI_RS_Event_trade_cheated', FR)

    def test_ascii_kahlua_safe_code(self):
        code = EXCHANGE_LUA.read_text(encoding='utf-8')
        body = re.sub(r'--[^\n]*', '', code)
        self.assertTrue(body.isascii())
        self.assertIsNone(re.search(r'\bnext\s*\(|\bgoto\b|coroutine|ModData\.|send(Server|Client)Command|getText',
                                    body))
        self.assertIn('if isClient() then return end', code)

    def test_in_game_suite_compiles(self):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        check = rt.eval('function(s) local f, e = loadstring(s, "=RS_TradeExchange") return f ~= nil, e end')
        text = SUITE.read_text(encoding='utf-8')
        ok, err = check(text)
        self.assertTrue(ok, err)
        self.assertIn('RST.suite("rs.trade_exchange"', text)


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
