"""Échange sans contact au lieu du rendez-vous (E13-T04 ; E20-T07 : hors de vue de tout joueur et après un délai de
jeu ; E23-T07 : tout ou rien sur ce qui a été déposé après la réservation) : RS_TradeExchange.lua et RS_TradeDeposit.lua
avec RS_Trade.lua et RS_TradeRun.lua dans lupa.

    python RadioSurvivor/tests/test_rs_trade_exchange.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) : RS_TradeExchange, RS_TradeDeposit, RS_Trade, RS_TradeRun,
RS_Actions, CA_TradeValues, CA_Reputation, RS_OutsideNews ; doublures (celles de test_rs_trade_run.py, plus) : objets
d'inventaire (identifiant, type, nom affiché et nom du script, état, utilisations, poids, ModData, contenu), sacs au sol
et cellule (cases chargées ou non), instanceItem, envois sendAddItemToContainer / sendRemoveItemFromContainer, création
du journal du dehors. Couvre : conditions de la table (état, filtre, sac vide, papiers nominatifs, nom d'un joueur,
objets du mod ou hors barème), contenu du lieu noté au premier sondage après la réservation et gardé au redémarrage,
butin déjà là ignoré, objets ajoutés à un sac déjà là comptés, deux sacs additionnés, marchandise dans le sac qui tenait
le plus du paiement (le premier à égalité), liste prise exactement (le reste en place), dépôt incomplet gardé avec la
sanction de tricherie, rien d'ajouté = moitié de la sanction, échange fait une seule fois, lieu déchargé, reprise d'un
échange appliqué sans état écrit, annulation sans toucher au dépôt, annonces traduites.
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
DEPOSIT_LUA = LUA / 'server/RadioSurvivor/RS_TradeDeposit.lua'
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
SUITE = tests_lua() / 'shared' / 'RST' / 'suites' / 'RS_TradeExchange.lua'

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
package.preload["RadioSurvivor/RS_Config"] = function() return { Reputation = { success = 5, failure = -5 },
    TradeMargin = { good = 0.10, neutral = 0.25, bad = 0.40 } } end
"""

ID_BASE = 'ID Card'


class ExchangeHarness(RunHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute(WORLD)
        self.Ex = self.rt.eval('require("RadioSurvivor/RS_TradeExchange")')
        self.g.STATE.data.outcomes = self.rt.table_from({})
        # E18-T22: reputation of the core mod on this table (its facts read below).
        self.rt.eval('require("CoreAI/CA_Reputation")').useData(self.g.STATE.data)
        self.item = self.g.makeItem
        self.pay = 'MoneyBundle:2'      # E23-T06 : 20 points, le prix de deux antibiotiques

    def decide(self, player, gives='Battery:2', caller=None, voice='gus', wants=None):
        """Accord, puis un sondage de l'échange : le serveur voit le lieu chargé et note son contenu (E23-T07)."""
        reason = super().decide(player, gives, caller, voice, wants)
        if reason == 'ok':
            self.Ex.updateTrader(voice, None)
        return reason

    def it(self, full, **o):
        return self.item('Base.' + full if '.' not in full else full, self.t(o) if o else None)

    def bag_items(self, bag):
        return [x.t for x in lua_list(bag.inv.list)]

    def sent(self):
        return lua_list(self.g.SENT)

    def fact(self, key):
        return self.g.STATE.data.outcomes[key]

    def arrived(self, gives='Antibiotics:2', hours=18.5, wants=None):
        """kate (fac-1) conclut l'accord à 4 h (contenu du lieu noté), la barque arrive au ponton à `hours` ; kate
        reste au ponton."""
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, gives, wants=wants), 'ok')
        self.g.CLOCK.hours = hours
        kate.x, kate.y = 6041, 5217
        self.assertTrue(self.T.arrive('lamp'))
        return kate

    def poll(self):
        """Sondage de l'échange du passage de Gus à l'heure du monde (E20-T07 : un passage par marchand)."""
        return self.Ex.updateTrader('gus', None)

    def leave(self, player, x=9000):
        """Le joueur part hors de vue : premier sondage (l'attente commence), puis le délai de jeu passe."""
        player.x = x
        self.assertIsNone(self.poll())
        self.g.CLOCK.hours = self.g.CLOCK.hours + self.Ex.DELAY_HOURS


class CountsTests(ExchangeHarness):

    def test_conditions_of_the_table(self):
        named = dict(name='ID Card: John Doe', base=ID_BASE)
        cases = [
            (self.it('MoneyBundle'), True), (self.it('IDcard', **named), True),
            (self.it('IDcard', name=ID_BASE, base=ID_BASE), False),                 # sans nom
            (self.it('IDcard', name='ID Card: Kate Miller', base=ID_BASE), False),  # nom d'un joueur
            (self.it('AssaultRifle', cond=4), False), (self.it('AssaultRifle', cond=6), True),
            (self.it('GasmaskFilter', uses=0.4), False), (self.it('GasmaskFilter', uses=0.5), True),
            (self.it('Bag_ALICEpack_Army', items=[self.it('Hammer')]), False),
            (self.it('Bag_ALICEpack_Army', items=[]), True),
            (self.it('Wallet', items=[self.it('Photo')]), True),                    # portefeuille compté seul
            (self.it('MoneyBundle', md={'CA_Cache': 'x'}), False),                  # marque du mod
            (self.it('MoneyBundle', md={'LKStock': 'g1'}), False),
            (self.it('MoneyBundle', md={'customName': 'x'}), True),                 # ModData vanilla
            (self.it('Hammer'), False),                                              # hors barème
        ]
        for item, counts in cases:
            with self.subTest(item.t):
                self.assertEqual(bool(self.Ex.counts(item, self.t(['Kate Miller']))), counts)


class ExchangeTests(ExchangeHarness):

    def test_exchange_done_once_taking_exactly_the_list(self):
        kate = self.arrived(wants='MoneyBundle:1,Necklace_Gold:1,IDcard:2')
        offer = self.T.offerOf('kate', None)
        self.assertEqual((offer.price, offer.value), (20, 20))
        bag = self.g.dropBag(6042, 5216, self.t([
            self.it('MoneyBundle'), self.it('Necklace_Gold'), self.it('IDcard', name='ID Card: John Doe', base=ID_BASE),
            self.it('IDcard', name='ID Card: Jane Roe', base=ID_BASE), self.it('Hammer'), self.it('MoneyBundle')]))
        self.assertIsNone(self.poll())                                      # kate encore au ponton
        self.assertEqual(self.sent(), [])
        self.leave(kate)
        self.assertEqual(self.poll(), 'done')
        items = self.bag_items(bag)
        self.assertEqual(items, ['Base.Hammer', 'Base.MoneyBundle', 'Base.Antibiotics', 'Base.Antibiotics'])
        given = [x for x in lua_list(bag.inv.list) if x.t == 'Base.Antibiotics']
        self.assertTrue(all(x.md['RS_TradeGiven'] == offer.rev for x in given))
        self.assertEqual(self.sent(), ['remove:Base.MoneyBundle', 'remove:Base.Necklace_Gold', 'remove:Base.IDcard',
                                       'remove:Base.IDcard', 'add:Base.Antibiotics', 'add:Base.Antibiotics'])
        run = self.T.lastRun()
        self.assertEqual((run.state, run.reason, run.exchange.took, run.exchange.given), ('done', 'done', 4, 2))
        self.assertEqual(self.T.offerOf('kate', None).state, 'done')
        self.assertEqual(lua_list(self.T.deals('kate', None))[-1].state, 'done')
        self.assertEqual(self.T.available('bob', None).Antibiotics, 2)    # 4 tirés, 2 échangés
        self.assertEqual(self.aired(), [['<fzzt>', EN['IGUI_RS_TradeRun_Done'], '<szzt>']])
        # Joueur revenu, sondages suivants : rien de plus.
        kate.x = 6041
        for hours in (19.6, 20.0, 25.0):
            self.g.CLOCK.hours = hours
            self.assertIsNone(self.poll())
        kate.x = 9000
        self.assertIsNone(self.poll())
        self.assertEqual(len(self.bag_items(bag)), 4)
        self.assertEqual(len(self.sent()), 6)
        self.assertEqual(len(self.aired()), 1)
        self.assertEqual(self.decide(kate), 'run_over')

    def test_loot_already_at_the_landing_does_not_count(self):
        # E23-T07, ADR D02 : un sac déjà là quand le serveur note le lieu (butin, planque d'un autre) ne compte pas.
        self.g.CLOCK.hours = 4.0
        old = self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(3)]))
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.assertIsNotNone(self.T.lastRun().seen)
        self.g.CLOCK.hours = 18.5
        kate.x, kate.y = 6041, 5217
        self.assertTrue(self.T.arrive('lamp'))
        self.leave(kate)
        self.assertEqual(self.poll(), 'no_drop')                            # rien d'ajouté
        self.assertEqual(len(self.bag_items(old)), 3)
        self.assertEqual(self.sent(), [])
        run = self.T.lastRun()
        self.assertEqual((run.state, run.reason), ('cancelled', 'no_drop'))
        fact = self.fact(f'trade-{run.rev}-no_drop')
        self.assertEqual((fact.character, fact.action, fact.proposedDelta), ('kate', 'trade.nodrop', -2.5))
        self.assertEqual(self.aired(), [['<fzzt>', EN['IGUI_RS_TradeRun_Cancel_nodrop'], '<szzt>']])
        self.assertEqual(self.T.marginRange('kate', None)[0], 0.25)        # pas une tricherie
        self.assertEqual(self.T.available('bob', None).Antibiotics, 4)    # réserve rendue

    def test_items_added_to_a_bag_already_there_count(self):
        self.g.CLOCK.hours = 4.0
        old = self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle')]))
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.g.CLOCK.hours = 18.5
        kate.x, kate.y = 6041, 5217
        self.assertTrue(self.T.arrive('lamp'))
        old.inv.list[2] = self.it('MoneyBundle')
        old.inv.list[3] = self.it('MoneyBundle')
        self.leave(kate)
        self.assertEqual(self.poll(), 'done')
        self.assertEqual(self.bag_items(old), ['Base.MoneyBundle', 'Base.Antibiotics', 'Base.Antibiotics'])

    def test_two_bags_add_up_and_goods_go_where_most_was_paid(self):
        kate = self.arrived(wants='MoneyBundle:1,GoldCoin:2,SilverCoin:2')     # 10 + 6 + 4
        small = self.g.dropBag(6040, 5217, self.t([self.it('MoneyBundle')]))
        big = self.g.dropBag(6042, 5218, self.t([self.it('GoldCoin'), self.it('GoldCoin'), self.it('SilverCoin'),
                                                 self.it('SilverCoin')]))
        self.leave(kate)
        self.assertEqual(self.poll(), 'done')
        self.assertEqual(self.bag_items(small), [])
        self.assertEqual(self.bag_items(big), ['Base.Antibiotics', 'Base.Antibiotics'])

    def test_tie_puts_the_goods_in_the_first_hold(self):
        kate = self.arrived(wants='MoneyBundle:2,GoldCoin:2')                  # deux objets payés dans chaque sac
        first = self.g.dropBag(6040, 5217, self.t([self.it('MoneyBundle'), self.it('GoldCoin')]))
        second = self.g.dropBag(6042, 5218, self.t([self.it('GoldCoin'), self.it('MoneyBundle'), self.it('Hammer')]))
        self.leave(kate)
        self.assertEqual(self.poll(), 'done')
        self.assertEqual(self.bag_items(first), ['Base.Antibiotics', 'Base.Antibiotics'])
        self.assertEqual(self.bag_items(second), ['Base.Hammer'])

    def test_incomplete_drop_is_kept_with_the_cheat_sanction(self):
        # ADR D03 : dépôt incomplet, le marchand garde tout ce qui a été ajouté et ne laisse rien.
        self.g.CLOCK.hours = 4.0
        other = self.g.dropBag(6041, 5218, self.t([self.it('MoneyBundle'), self.it('Diamond')]))   # déjà là
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.g.CLOCK.hours = 18.5
        kate.x, kate.y = 6041, 5217
        self.assertTrue(self.T.arrive('lamp'))
        bag = self.g.dropBag(6040, 5218, self.t([self.it('MoneyBundle'), self.it('SilverCoin'), self.it('Hammer'),
                                                  self.it('MoneyBundle', md={'CA_Cache': 'm1'})]))
        self.leave(kate)
        self.assertEqual(self.poll(), 'cheated')
        self.assertEqual(self.bag_items(bag), ['Base.MoneyBundle'])        # objet de quête jamais pris
        self.assertEqual(self.bag_items(other), ['Base.MoneyBundle', 'Base.Diamond'])
        self.assertEqual(self.sent(), ['remove:Base.MoneyBundle', 'remove:Base.SilverCoin', 'remove:Base.Hammer'])
        run = self.T.lastRun()
        self.assertEqual((run.state, run.reason, run.exchange.kept), ('cheated', 'short', 3))
        self.assertEqual(run.exchange.missing['Base.MoneyBundle'], 1)
        self.assertEqual(self.T.offerOf('kate', None).state, 'cheated')
        self.assertEqual(self.T.marginRange('kate', None)[0], 0.5)
        fact = self.fact(f'trade-{run.rev}-short')
        self.assertEqual((fact.character, fact.action, fact.proposedDelta, fact.applied),
                         ('kate', 'trade.cheated', -5, False))
        self.assertEqual(self.aired(), [['<fzzt>', EN['IGUI_RS_TradeRun_Cheated'], '<szzt>']])
        self.assertIsNone(self.poll())
        self.assertEqual(self.decide(kate), 'run_over')

    def test_damaged_item_does_not_count_for_its_line(self):
        kate = self.arrived(wants='AssaultRifle:1')
        bag = self.g.dropBag(6041, 5217, self.t([self.it('AssaultRifle', cond=3)]))
        self.leave(kate)
        self.assertEqual(self.poll(), 'cheated')
        self.assertEqual(self.bag_items(bag), [])

    def test_nothing_added_means_no_drop(self):
        kate = self.arrived()
        self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle', md={'CA_Cache': 'm1'})]))
        self.leave(kate)
        self.assertEqual(self.poll(), 'no_drop')                            # seul un objet de quête ajouté

    def test_unloaded_landing_waits_for_a_player_to_come_back(self):
        kate = self.arrived()
        bag = self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.g.LOADED = False
        self.leave(kate)
        self.assertIsNone(self.poll())                                      # dû, case déchargée
        self.g.CLOCK.hours = 60.0
        self.assertIsNone(self.poll())                                      # jamais de départ tant qu'il est dû
        self.assertEqual(self.sent(), [])
        self.g.LOADED = True
        self.assertEqual(self.poll(), 'done')
        self.assertEqual(self.bag_items(bag), ['Base.Antibiotics', 'Base.Antibiotics'])

    def test_note_kept_across_a_restart(self):
        # E23-T07 : le contenu noté est gardé avec le passage dans l'état privé (redémarrage du serveur).
        self.g.CLOCK.hours = 4.0
        old = self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        codec = self.rt.eval('require("CoreAI/CA_Codec")')
        self.g.STATE.data = codec.decodeBytes(codec.encodeBytes(self.g.STATE.data))
        self.rt.eval('require("CoreAI/CA_Reputation")').useData(self.g.STATE.data)
        self.g.CLOCK.hours = 18.5
        kate.x, kate.y = 6041, 5217
        self.assertTrue(self.T.arrive('lamp'))
        self.leave(kate)
        self.assertEqual(self.poll(), 'no_drop')
        self.assertEqual(len(self.bag_items(old)), 2)

    def test_bag_outside_the_drop_zone_means_no_drop(self):
        kate = self.arrived()
        bag = self.g.dropBag(6041 + 4, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.leave(kate)
        self.assertEqual(self.poll(), 'no_drop')
        self.assertEqual(len(self.bag_items(bag)), 2)

    def test_counterpart_already_in_a_bag_recovers_without_giving_again(self):
        kate = self.arrived()
        rev = self.T.offerOf('kate', None).rev
        given = self.it('Antibiotics', md={'RS_TradeGiven': rev})
        bag = self.g.dropBag(6041, 5217, self.t([given]))
        self.assertEqual(self.poll(), 'done')                              # kate au ponton : reprise quand même
        self.assertEqual((self.T.lastRun().state, self.T.lastRun().reason), ('done', 'recovered'))
        self.assertEqual(self.bag_items(bag), ['Base.Antibiotics'])
        self.assertEqual(self.sent(), [])

    def test_outside_news_counterpart(self):
        stock = {e.n: 0 for e in lua_list(self.gus.trade['items'])}
        stock.update({'Battery': 10, 'Antibiotics': 4, 'OutsideNews': 1})
        self.T.drawStock = lambda spec, seed, passage: self.rt.table_from(stock)
        kate = self.arrived('OutsideNews:1,Battery:2', wants='MoneyBundle:1')
        bag = self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle')]))
        self.leave(kate)
        self.assertEqual(self.poll(), 'done')
        self.assertEqual(sorted(self.bag_items(bag)), ['Base.Battery', 'Base.Battery', 'RadioSurvivor.OutsideNews'])
        self.assertEqual(self.g.NEWS, 1)

    def test_booked_run_not_exchanged_before_the_signal(self):
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 9000, 50)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.g.CLOCK.hours = 18.5
        self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.g.CLOCK.hours = 30.0
        self.assertIsNone(self.poll())
        self.assertEqual(self.T.lastRun().state, 'booked')

    def test_cancelled_run_touches_no_deposit(self):
        # E23-T08, ADR D05 : une annulation par le marchand ne touche à aucun dépôt et ne coûte rien.
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 6041, 5217)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        bag = self.g.dropBag(6041, 5217, self.t([self.it('MoneyBundle') for _ in range(2)]))
        self.g.STORM = True
        self.g.CLOCK.hours = 15.0
        self.Run.update(15.0)
        self.assertEqual(self.T.lastRun().state, 'cancelled')
        for hours in (18.5, 20.0, 30.0):
            self.g.CLOCK.hours = hours
            self.assertIsNone(self.poll())
        self.assertEqual(len(self.bag_items(bag)), 2)
        self.assertEqual(self.sent(), [])
        self.assertEqual(len(list(self.g.STATE.data.outcomes.keys())), 0)
        self.assertEqual(self.T.marginRange('kate', None)[0], 0.25)

    def test_hook_installed(self):
        self.assertIsNotNone(self.g.HANDLERS['EveryOneMinute'])


class StaticTests(unittest.TestCase):

    def test_translations_and_fallbacks(self):
        source = (LUA / 'server/RadioSurvivor/RS_TradeRun.lua').read_text(encoding='utf-8')
        for name in ('Done', 'Cheated', 'Cancel_nodrop', 'Cancel_watched'):
            key = 'IGUI_RS_TradeRun_' + name
            self.assertIn(key, EN)
            self.assertIn(key, FR)
            self.assertNotIn('%', EN[key] + FR[key])
            self.assertLessEqual(len(FR[key]), 140)
            self.assertIn(f'{name} = "{EN[key]}"', source)
        for key in ('IGUI_RS_Event_trade_cheated', 'IGUI_RS_Event_trade_nodrop', 'IGUI_RS_RepReason_TradeNoDrop'):
            self.assertIn(key, EN)
            self.assertIn(key, FR)

    def test_ascii_kahlua_safe_code(self):
        for path in (EXCHANGE_LUA, DEPOSIT_LUA):
            code = path.read_text(encoding='utf-8')
            body = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(body.isascii(), path.name)
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
