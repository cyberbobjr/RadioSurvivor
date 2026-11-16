"""Livre du passeur et action propose_trade (E13-T02 ; E20-T07 : stock et marges déclarés dans la section [trade]
de la fiche de Gus, état par marchand ; E23-T06 : accord = deux listes d'objets, ce que la fiche accepte en paiement,
équité au barème, accord figé à l'arrivée) : RS_Trade.lua dans lupa, le pont (radio_bridge.py) et le serveur radio
complet (RadioSurvivor_Server.lua, doublures de tests/test_protocol.py).

    python RadioSurvivor/tests/test_rs_trade.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) : RS_Trade, RS_Actions, RS_Persona, CA_Codec,
CA_TradeValues, RS_OutsideNews, RadioSurvivor_Const ; doublures : GameTime (âge du monde), ZombRand, état privé
RS_State (table en mémoire), journal admin RS_ActionLog. Couvre : catalogue d'apport conforme à la table validée
(docs/specifications-techniques/passeur-table.md, section 3 ; poids relus dans les scripts vanilla 42.21), tirage du stock reproductible et dans
les fourchettes, prix ligne par ligne (exemples de la table), offre figée avec révision, réserve et remplacement,
refus hors table (stock, poids, plafond, forme, paiement non accepté, plafond par objet, poids du dépôt,
accord inéquitable), stocks jamais négatifs sur un tirage aléatoire de propositions, mémoire des affaires (marge
selon la réputation et l'historique, tricherie, issue, expiration au passage suivant),
persistance dans l'état privé, contexte trade= relu par le pont, prompt et contrôle de forme du pont, chaîne complète
demande -> réponse -> offre -> demande suivante dans le serveur radio.
Ne prouve pas l'API Java réelle ni le comportement du LLM : la tâche est hors jeu (E13-T03 et E13-T04 en jeu).
"""
from __future__ import annotations

import math
import random
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21'
LUA = MOD / 'media/lua'
CORE_LUA = Path(__file__).resolve().parents[1] / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'  # mod commun (E18)
LK_LUA = Path(__file__).resolve().parents[1] / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'  # moteur des PNJ (E18-T07)
TRADE_LUA = LUA / 'server/RadioSurvivor/RS_Trade.lua'
DOC = ROOT / 'docs/specifications-techniques/passeur-table.md'
VANILLA_ITEMS = pz_paths.media_dir() / 'scripts/generated/items'
sys.path.insert(0, str(ROOT / 'bridge'))
sys.path.insert(0, str(ROOT / 'tests'))

import npc_protocol as npc  # noqa: E402
import radio_bridge as rb  # noqa: E402
from itemweights_double import ITEM_WEIGHTS, WEIGHTS, trade_rules_lua  # noqa: E402
from test_rs_trade_run import GUS, TraderProxy  # noqa: E402


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


STUBS = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
isClient = function() return false end
isServer = function() return false end
CLOCK = { hours = 0 }
getGameTime = function() return {
    getWorldAgeHours = function() return CLOCK.hours end,
    getYear = function() return 1993 end, getMonth = function() return 6 end, getDay = function() return 9 end,
    getHour = function() return 4 end, getMinutes = function() return 0 end } end
local r = 0
ZombRand = function(a, b) r = r + 1 if b then return a + (r % (b - a)) end return (r * 7) % a end
STATE = { data = nil, blocked = false, dirty = false }
package.preload["RadioSurvivor/RS_State"] = function() return STATE end
ACTION_LOG = {}
package.preload["RadioSurvivor/RS_ActionLog"] = function() return {
    format = function(d, voice, caller, name) return name .. ":" .. tostring(d.reason) end,
    append = function(lines) for _, l in ipairs(lines) do ACTION_LOG[#ACTION_LOG + 1] = l end end } end
-- E20-T07 : voix chargées (port RS_Trade.useVoices).
VOICES = {}
VOICE_PORT = { get = function(id) return VOICES[id] end, ids = function() return { "gus" } end }
"""


# E23-T06 : paiement par défaut des bancs, accepté par Gus (catégorie cash) et assez riche pour toute offre (120 points).
PAY = 'MoneyBundle:12'


class TradeHarness(unittest.TestCase):

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.rt.execute(STUBS)
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server'))
        paths = (CORE_LUA / 'shared').as_posix() + '/?.lua;' + (CORE_LUA / 'server').as_posix() + '/?.lua;' + (CORE_LUA / 'client').as_posix() + '/?.lua;' + (LK_LUA / 'shared').as_posix() + '/?.lua;' + (LK_LUA / 'server').as_posix() + '/?.lua;' + (LK_LUA / 'client').as_posix() + '/?.lua;' + paths  # mod commun (E18)
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        # E20-T07 : la vraie fiche de Gus (section [trade]) lue par RS_Persona, mode d'arrivée boat inscrit.
        self.rt.eval('require("RadioSurvivor/TradeArrivals/RS_TradeArrival_Boat")')
        self.rt.execute(ITEM_WEIGHTS)  # E22-T12 : poids des objets du troc, à la place des scripts du jeu
        rules = self.rt.eval(trade_rules_lua())
        persona = self.rt.eval('require("RadioSurvivor/RS_Persona")')
        self.gus = persona.parseLines(self.rt.table_from(GUS.read_text(encoding='utf-8').splitlines()), 'gus', rules)
        self.assertFalse(isinstance(self.gus, tuple), self.gus)
        self.g.VOICES.gus = self.gus
        self.spec = self.gus.trade
        self.Trade = self.rt.eval('require("RadioSurvivor/RS_Trade")')
        self.Trade.useVoices(self.g.VOICE_PORT)
        self.T = TraderProxy(self.Trade, 'gus')
        self.Actions = self.rt.eval('require("RadioSurvivor/RS_Actions")')
        self.Codec = self.rt.eval('require("CoreAI/CA_Codec")')
        self.TV = self.rt.eval('require("CoreAI/CA_TradeValues")')
        self.g.STATE.data = self.rt.table_from({'schema': 2})
        self.T.resetForTests()
        # E13-T03 : cordon tiré par passage ; les exemples de la table supposent une semaine calme au passage 1.
        self.T.setCordon(1, 1.0)
        # Deux valeurs toujours (lupa déplie une table Lua rendue seule).
        self.two = self.rt.eval('function(f, ...) local a, b = f(...) return a, b end')

    def t(self, value):
        if isinstance(value, dict):
            return self.rt.table_from({k: self.t(v) for k, v in value.items()})
        if isinstance(value, list):
            return self.rt.table_from([self.t(v) for v in value])
        return value

    def force_stock(self, stock: dict[str, int]):
        """Stock tiré imposé (toutes les autres lignes à 0)."""
        names = [e.n for e in self.supply()]
        full = {n: stock.get(n, 0) for n in names}
        self.T.drawStock = lambda spec, seed, passage: self.t(full)

    def supply(self):
        """Stock déclaré par la fiche de Gus (section [trade], lignes item=)."""
        return lua_list(self.spec['items'])

    def propose(self, caller, gives, wants=PAY, cid=None):
        """Accord proposé (E23-T06) : ce que Gus laisse, ce que l'appelant apporte (par défaut de quoi tout payer)."""
        return self.two(self.T.propose, caller, cid, gives, wants)

    def available(self, caller='x', cid=None):
        a = self.T.available(caller, cid)
        return {k: a[k] for k in a.keys()}


class CatalogueTests(TradeHarness):

    def test_supply_matches_the_validated_table(self):
        doc = DOC.read_text(encoding='utf-8')
        section = doc[doc.index('## 3. Ce que le passeur apporte'):doc.index('## 4.')]
        for e in self.supply():
            with self.subTest(e.n):
                self.assertTrue(f'`{e.n}`' in section or f'`{e.t}`' in section, e.n)
                self.assertGreater(self.TV.sellValue(e.t), 0)
                if e.gr is None:
                    rng = f'{e.min} – {e.max}' if e.min != e.max else None
                    if rng:
                        row = next(line for line in section.splitlines() if f'`{e.n}`' in line)
                        self.assertIn(rng, row)
        groups = {g.id: g for g in lua_list(self.spec.groups)}
        self.assertEqual((groups['seeds'].min, groups['seeds'].max, groups['seeds'].kinds), (3, 8, 4))
        self.assertIn('3 – 8 sachets, 4 sortes au plus', section)
        self.assertEqual((groups['alcohol'].min, groups['alcohol'].max, groups['alcohol'].kinds), (1, 4, None))
        self.assertIn('1 – 4 bouteilles au total', section)
        self.assertEqual((self.T.CAP_POINTS, self.T.CAP_KG), (120, 10))
        self.assertIn('au plus 120 points', doc)
        self.assertIn('pèse **au plus 10 kg**', doc)
        self.assertEqual((self.spec.marginMin, self.T.MARGIN_DEFAULT, self.spec.marginMax, self.T.M_MAX,
                          self.T.RARITY), (0.10, 0.25, 0.50, 1.75, 1.25))
        self.assertEqual(self.T.CAP_PAY_KG, 20)
        self.assertIn('au plus 20 kg', doc)

    def test_gus_accepts_valued_items_only(self):
        # E23-T06 : ce que la fiche accepte en paiement (accept=), résolu en types qui ont une valeur de vente.
        accepts = lua_list(self.spec.accepts)
        self.assertIn('Base.MoneyBundle', accepts)
        self.assertIn('Base.Necklace_Gold', accepts)
        self.assertIn('Base.IDcard', accepts)
        self.assertIn('Base.AssaultRifle', accepts)
        self.assertNotIn('Base.Battery', accepts)
        self.assertEqual(len(accepts), len(set(accepts)))
        self.assertTrue(all(self.TV.sellValue(t) > 0 for t in accepts))

    def test_weights_come_from_the_injected_scripts(self):
        # E22-T12 : la fiche n'écrit plus de poids ; chaque objet porte celui de la source (RS_ItemWeights).
        for e in self.supply():
            with self.subTest(e.n):
                self.assertAlmostEqual(e.w, WEIGHTS[e.t], places=6)

    @unittest.skipUnless(VANILLA_ITEMS.is_dir(), 'vanilla scripts missing')
    def test_weight_double_is_the_vanilla_scripts_with_their_fluid(self):
        # La doublure des bancs (itemweights_double.WEIGHTS) suit la règle de RS_ItemWeights : Weight du script, plus
        # Capacity d'un FluidContainer créé rempli (bloc Fluids avec une ligne fluid=).
        text = {f.name: f.read_text(encoding='utf-8', errors='replace') for f in VANILLA_ITEMS.glob('*.txt')}
        for full, kg in WEIGHTS.items():
            if not full.startswith('Base.'):
                continue
            name = full[5:]
            block = None
            for body in text.values():
                m = re.search(r'(?m)^\s*item\s+' + re.escape(name) + r'\s*\n\s*\{(.*?)\n    \}', body, re.S)
                if m:
                    block = m.group(1)
                    break
            with self.subTest(name):
                self.assertIsNotNone(block)
                weight = float(re.search(r'(?m)^\s*Weight\s*=\s*([\d.]+)', block).group(1))
                cap = re.search(r'Capacity\s*=\s*([\d.]+)', block)
                full_of = cap and re.search(r'(?im)^\s*fluid\s*=', block)
                self.assertAlmostEqual(kg, weight + (float(cap.group(1)) if full_of else 0.0), places=6)

    def test_news_weight_is_the_mod_script(self):
        script = (MOD / 'media/scripts/RadioSurvivor_outsidenews.txt').read_text(encoding='utf-8')
        news = next(e for e in self.supply() if e.n == 'OutsideNews')
        self.assertAlmostEqual(news.w, float(re.search(r'Weight\s*=\s*([\d.]+)', script).group(1)))
        self.assertEqual((news.min, news.max), (1, 1))

    def test_news_sale_value_registered_by_the_mod(self):
        # E21-T06: the sale value of the outside news is RadioSurvivor's, registered in the core scale by RS_Trade.
        self.rt.execute('package.loaded["CoreAI/CA_TradeValues"] = nil; package.loaded["RadioSurvivor/RS_Trade"] = nil')
        tv = self.rt.eval('require("CoreAI/CA_TradeValues")')
        self.rt.eval('require("RadioSurvivor/RS_Trade")')
        self.assertEqual((tv.sellValue('RadioSurvivor.OutsideNews'), tv.SELL_ONLY['RadioSurvivor.OutsideNews'].cap,
                          tv.SELL_ONLY['RadioSurvivor.OutsideNews'].k), (2, 1, 'supply'))
        self.assertEqual(tv.value('RadioSurvivor.OutsideNews')[0], 0)


class StockTests(TradeHarness):

    def test_draw_is_reproducible_and_within_ranges(self):
        seen = set()
        for passage in range(1, 400):
            a = self.Trade.drawStock(self.spec, 123456, passage)
            b = self.Trade.drawStock(self.spec, 123456, passage)
            stock = {k: a[k] for k in a.keys()}
            self.assertEqual(stock, {k: b[k] for k in b.keys()})
            seen.add(tuple(sorted(stock.items())))
            for e in self.supply():
                if e.gr is None:
                    self.assertTrue(e.min <= stock[e.n] <= e.max, (passage, e.n, stock[e.n]))
            seeds = [stock[e.n] for e in self.supply() if e.gr == 'seeds']
            self.assertTrue(3 <= sum(seeds) <= 8 and 1 <= sum(1 for s in seeds if s) <= 4, seeds)
            alcohol = [stock[e.n] for e in self.supply() if e.gr == 'alcohol']
            self.assertTrue(1 <= sum(alcohol) <= 4, alcohol)
        self.assertGreater(len(seen), 300)
        self.assertNotEqual({k: v for k, v in self.Trade.drawStock(self.spec, 1, 5).items()},
                            {k: v for k, v in self.Trade.drawStock(self.spec, 2, 5).items()})

    def test_seed_drawn_once_and_kept_in_the_private_state(self):
        self.T.stock()
        seed = self.g.STATE.data.trade.traders.gus.seed
        self.assertTrue(1 <= seed <= 2147483646)
        self.T.stock()
        self.assertEqual(self.g.STATE.data.trade.traders.gus.seed, seed)
        self.assertTrue(self.g.STATE.dirty)


class PriceTests(TradeHarness):

    def test_examples_of_the_table(self):
        # Exemple 1 : 2 antibiotiques, marge 0,25, semaine calme : 20 points.
        self.force_stock({'Antibiotics': 4, 'Battery': 6, '308Box': 2})
        offer, _ = self.propose('kate', 'Antibiotics:2')
        self.assertEqual(offer.price, 20)
        # Exemple 2 : cordon serré, une 308Box : 27 ; deux piles de plus : 8.
        self.T.setCordon(self.T.passage(), 1.5)
        offer, _ = self.propose('kate', '308Box:1, Battery:2')
        self.assertEqual([(line.n, line.price) for line in lua_list(offer.lines)], [('308Box', 27), ('Battery', 8)])
        self.assertEqual(offer.price, 35)
        # Exemple 4 : un seul antibiotique au stock (rareté), cordon 1,25 : 16 / 14 / 19 selon la marge de l'appelant
        # (neutre ; trois affaires conclues ; après une tricherie).
        self.force_stock({'Antibiotics': 1})
        self.T.setCordon(self.T.passage(), 1.25)
        prices = {}
        for label, deals in (('neutral', []), ('regular', ['done'] * 3), ('cheat', ['cheated'])):
            store = self.g.STATE.data.trade.traders.gus
            store.books['kate'] = self.t({'deals': [{'state': st, 'rev': 0, 'passage': 0, 'items': 'Battery:1',
                                                     'wants': 'Money:10'} for st in deals], 'lastRev': 0})
            offer, why = self.propose('kate', 'Antibiotics')
            prices[label] = (offer.price, offer.margin) if offer else why
        self.assertEqual(prices, {'neutral': (16, 0.25), 'regular': (14, 0.1), 'cheat': (19, 0.5)})

    def test_multiplier_capped(self):
        self.force_stock({'Antibiotics': 1})
        self.T.setCordon(self.T.passage(), 1.5)   # 1,5 x 1,25 = 1,875 -> 1,75
        offer, _ = self.propose('kate', 'Antibiotics:1')
        self.assertEqual(offer.price, 18)          # ceil(8 x 1,25 x 1,75) = ceil(17,5)
        self.assertFalse(self.T.setCordon(self.T.passage(), 2))

    def test_payment_value_must_cover_the_price(self):
        # E23-T06, ADR D01 : le barème refuse un accord inéquitable ; le joueur ne voit jamais les points.
        self.force_stock({'Antibiotics': 4})
        self.assertEqual(self.propose('kate', 'Antibiotics:2', 'MoneyBundle:1')[1], 'unfair')        # 10 < 20
        offer, why = self.propose('kate', 'Antibiotics:2', 'MoneyBundle:1,GoldCoin:3,Money:5')        # 10+9+0
        self.assertEqual(why, 'unfair')
        offer, why = self.propose('kate', 'Antibiotics:2', 'MoneyBundle:1,GoldCoin:3,Money:19')       # 10+9+1
        self.assertIsNone(why)
        self.assertEqual((offer.price, offer.value), (20, 20))
        self.assertEqual([(w.t, w.q, w.v) for w in lua_list(offer.wants)],
                         [('Base.MoneyBundle', 1, 10), ('Base.GoldCoin', 3, 9), ('Base.Money', 19, 1)])
        offer, why = self.propose('kate', 'Antibiotics:2', 'base.goldbar')                           # 40 >= 20
        self.assertEqual((why, lua_list(offer.wants)[0].t), (None, 'Base.GoldBar'))


class OfferTests(TradeHarness):

    def test_offer_frozen_with_revision_and_reserved(self):
        self.force_stock({'Antibiotics': 4, 'Battery': 6})
        offer, why = self.propose('kate', 'antibiotics:2,BATTERY:3')
        self.assertIsNone(why)
        self.assertEqual((offer.rev, offer.state, offer.price, offer.margin, offer.weight), (1, 'open', 28, 0.25, 0.5))
        self.assertEqual(self.available('bob'), dict(self.available('kate'), Antibiotics=2, Battery=3))
        # Un autre appelant ne peut pas dépasser ce qui reste.
        self.assertEqual(self.propose('bob', 'Antibiotics:3')[1], 'over_stock')
        offer2, _ = self.propose('bob', 'Antibiotics:2')
        self.assertEqual(offer2.rev, 2)
        self.assertEqual(self.propose('carl', 'Antibiotics')[1], 'not_in_stock')
        # Même appelant : le nouvel accord remplace l'ancien et rend sa réserve.
        offer3, _ = self.propose('kate', 'Battery:6', 'GoldCoin:5')
        self.assertEqual(offer3.rev, 3)
        deals = lua_list(self.T.deals('kate', None))
        self.assertEqual([(d.rev, d.state, d.wants) for d in deals],
                         [(1, 'replaced', PAY), (3, 'open', 'GoldCoin:5')])
        self.assertEqual(self.available('carl')['Antibiotics'], 2)
        self.assertEqual(self.available('carl')['Battery'], 0)
        self.assertTrue(any('offer 3 of gus frozen for kate: Battery:6 for GoldCoin:5' in line
                            for line in lua_list(self.g.LOGS)))

    def test_refusals_outside_the_table(self):
        self.force_stock({'Antibiotics': 20, 'CigaretteCarton': 1, 'ShotgunShellsBox': 2, 'Coffee2': 3,
                          'Vodka': 2, 'Battery': 4})
        cases = {
            ('Money:2', PAY): 'not_in_stock', ('Base.Antibiotics:2', PAY): None, ('Whiskey', PAY): 'not_in_stock',
            ('Battery:5', PAY): 'over_stock', ('Antibiotics:15', PAY): 'over_cap',
            ('ShotgunShellsBox:2,Coffee2:3,Vodka:2,CigaretteCarton:1', PAY): 'over_weight',
            ('Antibiotics:2,', PAY): 'bad_params', ('Antibiotics:0', PAY): 'bad_params',
            ('Antibiotics:2,antibiotics:1', PAY): 'bad_params', ('Antibiotics x2', PAY): 'bad_params',
            ('', PAY): 'bad_params', ('Antibiotics:100', PAY): 'bad_params',
            # E23-T06 : la liste de l'appelant.
            ('Battery', ''): 'bad_params', ('Battery', 'MoneyBundle;GoldCoin'): 'bad_params',
            ('Battery', 'Battery:3'): 'not_taken',             # au barème, pas accepté par Gus
            ('Battery', 'Hammer'): 'not_taken',                # hors barème
            ('Battery', 'Mod.MoneyBundle'): 'not_taken',       # autre module
            ('Battery', 'GoldBar:2'): 'over_count',            # une barre par passage
            ('Battery', 'Money:101'): 'bad_params',            # 99 au plus par ligne
            ('Battery', 'MoneyBundle:1,Diamond'): None,
        }
        for (gives, wants), reason in cases.items():
            with self.subTest(gives=gives, wants=wants):
                offer, why = self.propose('kate', gives, wants)
                self.assertEqual(why, reason)
                self.assertEqual(offer is None, reason is not None)
        book = self.g.STATE.data.trade.traders.gus.books['kate']
        self.propose('kate', 'Battery:9')
        self.assertEqual(book.refused.reason, 'over_stock')

    def test_payment_weight_capped(self):
        # E23-T06 : ce que l'appelant dépose pèse au plus CAP_PAY_KG (20 kg), poids lus dans les scripts.
        self.rt.execute('require("RadioSurvivor/RS_ItemWeights").use({ ["Base.Vest_BulletArmy"] = 4.5,'
                        ' ["Base.Battery"] = 0.1 })')
        self.force_stock({'Battery': 4})
        self.assertEqual(self.propose('kate', 'Battery', 'Vest_BulletArmy:5')[1], 'pay_weight')   # 22,5 kg
        offer, why = self.propose('kate', 'Battery', 'Vest_BulletArmy:4')                          # 18 kg
        self.assertIsNone(why)
        self.assertAlmostEqual(offer.payWeight, 18.0)

    def test_weight_cap_uses_the_weights_read_from_the_scripts(self):
        # E22-T12 : un autre poids dans la source (script d'un mod qui alourdit l'objet) change le plafond de la
        # contrepartie (CAP_KG, 10 kg) sans toucher la fiche ; poids relus quand la fiche est relue.
        self.rt.execute('require("RadioSurvivor/RS_ItemWeights").use({ ["Base.Antibiotics"] = 4.0,'
                        ' ["Base.Battery"] = 0.1, ["Base.CigaretteCarton"] = 2.0 })')
        persona = self.rt.eval('require("RadioSurvivor/RS_Persona")')
        rules = self.rt.eval(trade_rules_lua())
        # Gus cite des objets absents de cette source : sa fiche est refusée, avec la ligne du premier.
        refused = persona.parseLines(self.rt.table_from(GUS.read_text(encoding='utf-8').splitlines()), 'gus', rules)
        self.assertRegex(refused[1], r"^line \d+: unknown trade item 'Base\.\w+' \(no item script of that type\)$")
        sheet = persona.parseLines(self.rt.table_from(['format=1', 'id=gus', 'name=Gus', 'frequencies=160.0',
                                                       'actions=say,propose_trade', '[place pier]', 'at=1,2,0',
                                                       'label=Pier', 'use=landing', '[trade]', 'landing=pier',
                                                       'arrival=boat', 'every_days=7', 'hours=01:00-03:00',
                                                       'item=Base.Antibiotics:1-6', 'item=Base.Battery:1-30',
                                                       'accept=Base.MoneyBundle', '[prompt]', 'Bench.']), 'gus',
                                            rules)
        self.assertFalse(isinstance(sheet, tuple), sheet)
        self.g.VOICES.gus = sheet
        self.spec = sheet.trade
        self.assertEqual({e.n: e.w for e in self.supply()}, {'Antibiotics': 4.0, 'Battery': 0.1})
        self.assertEqual(list(lua_list(self.spec.accepts)), ['Base.MoneyBundle'])
        self.force_stock({'Antibiotics': 6, 'Battery': 30})
        self.assertEqual(self.propose('kate', 'Antibiotics:3')[1], 'over_weight')            # 12 kg
        offer, why = self.propose('kate', 'Antibiotics:2,Battery:20')                       # 8 + 2 = 10 kg
        self.assertIsNone(why)
        self.assertAlmostEqual(offer.weight, 10.0)
        self.assertEqual(self.propose('kate', 'Antibiotics:2,Battery:21')[1], 'over_weight')  # 10,1 kg

    def test_stocks_never_negative_and_no_offer_outside_the_table(self):
        rnd = random.Random(7)
        names = [e.n for e in self.supply()] + ['Money', 'GoldBar', 'Base.Battery']
        callers = [f'p{i}' for i in range(12)]
        accepted = 0
        for passage_hours in (0, 168):
            self.g.CLOCK.hours = passage_hours
            for _ in range(1500):
                pool = names
                if rnd.random() < 0.5:   # moitié des propositions parmi ce qui reste pour cet appelant
                    left = self.available(rnd.choice(callers))
                    pool = [n for n, q in left.items() if q > 0] or names
                lines = rnd.sample(pool, min(len(pool), rnd.randint(1, 4)))
                items = ','.join(f'{n}:{rnd.randint(1, 5)}' if rnd.random() < 0.8 else n for n in lines)
                wants = rnd.choice([PAY, 'MoneyBundle:1', 'GoldBar:1', 'GoldCoin:4,Diamond:2', 'Battery:1', 'Hammer'])
                caller = rnd.choice(callers)
                if rnd.random() < 0.05:
                    o = self.T.offerOf(caller, None)
                    if o is not None:
                        self.T.close(caller, None, o.rev, rnd.choice(['done', 'cheated', 'cancelled']))
                offer, why = self.propose(caller, items, wants)
                if offer is None:
                    self.assertIn(why, lua_list(self.T.REASONS))
                    continue
                accepted += 1
                self.assertTrue(0.1 - 1e-9 <= offer.margin <= 0.5 + 1e-9 and offer.price <= 120
                                and offer.weight <= 10 + 1e-9 and offer.value >= offer.price)
                drawn = self.T.stock()
                total = 0
                for line in lua_list(offer.lines):
                    self.assertGreater(drawn[line.n], 0)
                    m = min(1.75, offer.cordon * (1.25 if drawn[line.n] == 1 else 1.0))
                    expected = math.ceil(line.v * line.q * (1 + offer.margin) * m - 1e-9)
                    self.assertEqual(line.price, expected, (line.n, line.v, line.q, offer.margin, m))
                    total += line.price
                self.assertEqual(total, offer.price)
                # Pris dans le passage (échanges faits + offres ouvertes) <= stock tiré, pour chaque objet.
                avail = self.available('nobody')
                root = self.g.STATE.data.trade.traders.gus
                sold = root.sold['items']   # attribut .items de lupa = méthode Python
                for name in drawn.keys():
                    self.assertGreaterEqual(avail[name], 0)
                    taken = (sold[name] or 0) if root.sold.passage == self.T.passage() else 0
                    for book in root.books.values():
                        o = book.offer
                        if o and o.passage == self.T.passage() and o.state == 'open':
                            taken += sum(line.q for line in lua_list(o.lines) if line.n == name)
                    self.assertLessEqual(taken, drawn[name], name)
                    self.assertEqual(avail[name], drawn[name] - taken, name)
        self.assertGreater(accepted, 100)


class MemoryTests(TradeHarness):

    def test_margin_floor_follows_the_reputation_level(self):
        """E04-T11 (Q13) : bonne 0,10, neutre 0,25, mauvaise 0,40, rabais d'historique en plus (plancher 0,10),
        tricherie 0,50 ; personnage inconnu ou sans carnet : neutre. E23-T06 : la marge n'est plus choisie par le
        LLM, c'est toujours la plus basse permise ; elle entre dans le prix d'un exemplaire du contexte."""
        self.force_stock({'Battery': 12})
        state = self.g.STATE.data
        state.characters = self.t({'cg': {'id': 'cg'}, 'cb': {'id': 'cb'}, 'cn': {'id': 'cn'},
                                   'dead': {'id': 'dead', 'retired': True}})
        state.reputation = self.t({'cg': {'score': 40}, 'cb': {'score': -40}, 'cn': {'score': 0},
                                   'dead': {'score': -40}})
        # E18-T22: reputation of the core mod on this table (characters living by its records).
        self.rt.eval("require('CoreAI/CA_Reputation')").useData(state)
        self.assertAlmostEqual(self.T.marginRange('kate', 'cg')[0], 0.10)
        self.assertAlmostEqual(self.T.marginRange('kate', 'cn')[0], 0.25)
        self.assertAlmostEqual(self.T.marginRange('kate', 'cb')[0], 0.40)
        self.assertAlmostEqual(self.T.marginRange('kate', 'dead')[0], 0.25)
        self.assertAlmostEqual(self.T.marginRange('kate', None)[0], 0.25)
        offer, _ = self.propose('bad', 'Battery', cid='cb')
        self.assertAlmostEqual(offer.margin, 0.40)
        self.assertTrue(self.T.close('bad', 'cb', offer.rev, 'done'))
        self.assertAlmostEqual(self.T.marginRange('bad', 'cb')[0], 0.35)   # history discount on top of the level
        offer, _ = self.propose('good', 'Battery', cid='cg')
        self.assertAlmostEqual(offer.margin, 0.10)
        self.assertTrue(self.T.close('good', 'cg', offer.rev, 'cheated'))
        self.assertEqual(tuple(self.T.marginRange('good', 'cg')), (0.5, 0.5))
        ctx = self.Trade.context(self.gus, 'bad', 'cb')
        self.assertEqual({s.n: s.unit for s in lua_list(ctx.stock)}['Battery'], 3)   # ceil(2 x 1,35)

    def test_margin_floor_follows_past_deals(self):
        self.force_stock({'Battery': 12})
        self.assertEqual(tuple(self.T.marginRange('kate', None)), (0.25, 0.5))
        for expected in (0.20, 0.15, 0.10, 0.10):
            offer, _ = self.propose('kate', 'Battery')
            self.assertTrue(self.T.close('kate', None, offer.rev, 'done'))
            self.assertAlmostEqual(self.T.marginRange('kate', None)[0], expected)
        offer, _ = self.propose('kate', 'Battery')
        self.assertAlmostEqual(offer.margin, 0.10)
        self.assertTrue(self.T.close('kate', None, offer.rev, 'cheated'))
        self.assertEqual(tuple(self.T.marginRange('kate', None)), (0.5, 0.5))
        self.assertEqual(self.propose('kate', 'Battery')[0].margin, 0.5)
        # Mémoire bornée, issues gardées dans l'ordre.
        deals = lua_list(self.T.deals('kate', None))
        self.assertLessEqual(len(deals), self.T.MAX_DEALS)
        self.assertEqual([d.state for d in deals][-2:], ['cheated', 'open'])

    def test_close_rules_and_reservation(self):
        self.force_stock({'Battery': 4})
        offer, _ = self.propose('kate', 'Battery:3')
        self.assertEqual(self.available('bob')['Battery'], 1)
        self.assertFalse(self.T.close('kate', None, offer.rev + 1, 'cancelled'))
        self.assertFalse(self.T.close('kate', None, offer.rev, 'paid'))
        self.assertFalse(self.T.close('bob', None, offer.rev, 'cancelled'))
        self.assertTrue(self.T.close('kate', None, offer.rev, 'cancelled'))
        self.assertEqual(self.available('bob')['Battery'], 4)        # annulée : réserve rendue
        offer, _ = self.propose('kate', 'Battery:3')
        self.assertTrue(self.T.close('kate', None, offer.rev, 'done'))
        self.assertFalse(self.T.close('kate', None, offer.rev, 'cancelled'))
        self.assertEqual(self.available('bob')['Battery'], 1)        # échange fait : quantités prises
        self.propose('kate', 'Battery:1')                             # nouvelle offre : l'échange fait reste pris
        self.assertEqual(self.available('bob')['Battery'], 0)
        self.assertEqual(self.available('kate')['Battery'], 1)
        self.assertEqual(self.propose('bob', 'Battery')[1], 'not_in_stock')

    def test_next_passage_expires_open_offers(self):
        self.force_stock({'Battery': 4})
        offer, _ = self.propose('kate', 'Battery:4')
        self.assertEqual(offer.passage, 1)
        self.g.CLOCK.hours = 7 * 24
        self.assertEqual(self.T.passage(), 2)
        self.assertEqual(self.available('bob')['Battery'], 4)
        self.assertEqual(self.T.offerOf('kate', None).state, 'expired')
        self.assertEqual(lua_list(self.T.deals('kate', None))[0].state, 'expired')
        self.assertFalse(self.T.close('kate', None, offer.rev, 'done'))

    def test_book_per_character_and_bounded(self):
        self.force_stock({'Battery': 12})
        self.propose('solo', 'Battery', cid='c1')
        self.assertIsNone(self.T.offerOf('solo', 'c2'))
        self.assertEqual(self.T.offerOf('solo', 'c1').rev, 1)
        for i in range(60):
            self.propose(f'p{i}', 'Battery:99')   # refus : crée le livre (dernier refus)
        self.assertLessEqual(len(list(self.g.STATE.data.trade.traders.gus.books.keys())), self.T.MAX_BOOKS)
        self.assertIsNotNone(self.T.offerOf('solo', 'c1'))         # offre ouverte jamais évincée

    def test_volatile_without_state_and_persistence(self):
        self.force_stock({'Battery': 4})
        self.propose('kate', 'Battery:2')
        saved = self.Codec.decodeBytes(self.Codec.encodeBytes(self.g.STATE.data))
        self.g.STATE.data = saved
        self.assertEqual(self.T.offerOf('kate', None).rev, 1)
        self.assertEqual(self.available('bob')['Battery'], 2)
        self.g.STATE.data = None
        self.g.STATE.dirty = False
        offer, _ = self.propose('kate', 'Battery:1')
        self.assertEqual(offer.rev, 1)                               # mémoire volatile, sans écriture d'état
        self.assertFalse(self.g.STATE.dirty)


class ActionTests(TradeHarness):

    def decide(self, actions, sheet=None, caller='kate'):
        sheet = self.t(sheet) if sheet else self.gus
        out = self.Actions.decide(sheet, caller, self.t(actions), 1000, self.t({'cid': None, 'day': '1993-07-10'}))
        return [(d.type, d.reason) for d in lua_list(out)]

    def test_executor_registered_and_judged(self):
        self.force_stock({'Antibiotics': 3, 'Battery': 4})
        self.assertEqual(self.decide([
            {'type': 'propose_trade', 'gives': 'Antibiotics:2', 'wants': 'MoneyBundle:2'},
            {'type': 'propose_trade', 'gives': 'Battery:9', 'wants': PAY},
            {'type': 'propose_trade', 'gives': 'Battery', 'wants': PAY, 'colour': 'red'},
        ]), [('propose_trade', 'ok'), ('propose_trade', 'over_stock'), ('propose_trade', 'bad_params')])
        self.assertEqual(self.decide([{'type': 'propose_trade', 'gives': 'Battery'},
                                      {'type': 'propose_trade', 'wants': PAY},
                                      {'type': 'propose_trade', 'items': 'Battery', 'margin': 0.3},
                                      ]), [('propose_trade', 'bad_params')] * 3)
        self.assertEqual(self.decide([{'type': 'propose_trade', 'gives': 'Battery', 'wants': 'Battery;Money'}]),
                         [('propose_trade', 'bad_params')])
        self.assertEqual(self.decide([{'type': 'propose_trade', 'gives': 'Battery', 'wants': PAY}],
                                     sheet={'id': 'walt', 'actions': ['say']}), [('propose_trade', 'not_allowed')])
        self.assertEqual(self.T.offerOf('kate', None).rev, 1)
        self.assertIn('propose_trade:over_stock', lua_list(self.g.ACTION_LOG))


class ContextTests(TradeHarness):

    def context(self, caller='kate'):
        hexed = self.Trade.field(self.gus, caller, None)
        return {'trade': hexed}, npc.decode(bytes.fromhex(hexed))

    def test_field_only_for_a_trading_voice(self):
        self.assertIsNone(self.Trade.field(self.t({'id': 'walt', 'actions': ['say', 'remember']}), 'kate', None))
        self.assertIsNone(self.Trade.field(self.t({'id': 'gus', 'actions': ['say', 'propose_trade']}), 'kate', None))
        self.assertIsNone(self.Trade.field(None, 'kate', None))

    def test_context_read_by_the_bridge(self):
        self.force_stock({'Antibiotics': 1, 'Battery': 6, 'OutsideNews': 1})
        offer, _ = self.propose('kate', 'Battery:2', 'Money:50')
        self.T.close('kate', None, offer.rev, 'done')
        self.propose('kate', 'Antibiotics', 'MoneyBundle:2')
        self.propose('kate', 'Battery:9')
        req, raw = self.context()
        self.assertEqual((raw['passage'], raw['cap'], raw['kg'], raw['payKg']), (1, 120, 10, 20))
        self.assertNotIn('marginMin', raw)
        stock = {s['n']: s['q'] for s in raw['stock'].values()}
        # Son propre accord ouvert (l'antibiotique) reste « offrable » : un nouvel accord le remplace.
        self.assertEqual(stock, {'Antibiotics': 1, 'Battery': 4, 'OutsideNews': 1})
        ctx = rb.trade_context(req)
        self.assertIsNotNone(ctx)
        self.assertEqual((ctx['offer']['items'], ctx['offer']['wants']), ('Antibiotics:1', 'MoneyBundle:2'))
        self.assertEqual([d['state'] for d in ctx['deals']], ['done', 'open'])
        self.assertEqual(ctx['refused'], 'over_stock')
        self.assertEqual([t['k'] for t in ctx['takes']], ['valuables', 'images', 'papers', 'military'])
        prompt = rb.trade_prompt(ctx, '[Caller 1]')
        for text in ('run number 1', 'worth at most 120 points', 'weigh at most 10 kg', 'weighs at most 20 kg',
                     '- Battery: 4 left, 0.1 kg, 3 points each', 'OutsideNews: 1 left',
                     'What you accept in payment', 'MoneyBundle 10', 'Money 1 per 10 (max 100)',
                     'AssaultRifle 20 (max 1) (condition 50%+)', 'never say points',
                     'Your deal with [Caller 1] (number 2): they bring MoneyBundle:2; you leave Antibiotics:1 '
                     '(standing)',
                     'run 1: they bring Money:50, you leave Battery:2, done, the caller brought everything',
                     'more than what is left', 'You may refuse a deal'):
            self.assertIn(text, prompt)
        self.assertNotIn('Battery 2', prompt)        # Gus ne prend pas de piles en paiement
        self.assertNotRegex(prompt, r'\d{3}\.\d|kHz|MHz|secret|margin')

    def test_bridge_ignores_a_broken_book(self):
        good = {'passage': 1, 'cap': 120, 'kg': 10, 'payKg': 20}
        for bad in ({}, dict(good, cap='x'), dict(good, payKg=-1), dict(good, passage=-1)):
            self.assertIsNone(rb.trade_context({'trade': npc.encode(bad).hex()}))
        self.assertIsNone(rb.trade_context({'trade': 'zz'}))
        self.assertIsNone(rb.trade_context({'trade': 'ab' * 20000}))
        ctx = rb.trade_context({'trade': npc.encode(dict(good, stock={1: {'n': 'Bad name', 'q': 1, 'w': 1,
                                                                          'unit': 1}},
                                                            takes={1: {'k': 'Bad class', 'items': 'Money 1'}},
                                                            offer={'rev': 1, 'items': 'x;y', 'wants': 'Money:1',
                                                                   'state': 'open'},
                                                            refused='because')).hex()})
        self.assertEqual((ctx['stock'], ctx['takes'], ctx['offer'], ctx['refused']), ([], [], None, None))
        prompt = rb.trade_prompt(ctx, 'you')
        self.assertIn('nothing left to trade', prompt)
        self.assertIn('You accept nothing in payment', prompt)
        self.assertEqual(rb.trade_prompt(None, 'you'), '')


class FakeSheet:
    def __init__(self):
        self.id = 'gus'
        self.actions = ['say', 'propose_trade']
        self.places = []


class BridgeFormTests(unittest.TestCase):

    def test_action_offered_described_and_bounded(self):
        sheet = FakeSheet()
        self.assertIn('propose_trade', rb.EXECUTABLE_ACTIONS)
        self.assertEqual(rb.offered_actions(sheet), ['propose_trade', 'remember'])   # E22-T13: every voice remembers
        prompt = rb.actions_prompt(sheet)
        self.assertIn('"gives"', prompt)
        self.assertIn('"wants"', prompt)
        self.assertIn('{"type": "propose_trade", "gives": "Antibiotics:2,Battery:4", "wants": "MoneyBundle:3"}', prompt)
        good = {'type': 'propose_trade', 'gives': 'Antibiotics:2, Battery:4', 'wants': 'MoneyBundle:3'}
        kept = rb.bounded_actions(sheet, [
            good,
            {'type': 'propose_trade', 'gives': 'Battery', 'wants': 'GoldCoin'},
            {'type': 'propose_trade', 'gives': 'Battery'},
            {'type': 'propose_trade', 'wants': 'GoldCoin'},
            {'type': 'propose_trade', 'gives': 'Battery', 'wants': 'GoldCoin', 'price': 3},
            {'type': 'propose_trade', 'gives': 'Battery;Coffee2', 'wants': 'GoldCoin'},
            {'type': 'propose_trade', 'gives': 'Battery', 'wants': 3},
            {'type': 'propose_trade', 'items': 'Battery', 'margin': 0.3},
        ])
        self.assertEqual(kept, [good, {'type': 'propose_trade', 'gives': 'Battery', 'wants': 'GoldCoin'}])
        self.assertEqual(rb.MAX_PARAM_BYTES, 64)
        self.assertIn('trade', rb.HEX_FIELDS)


class ServerChainTests(unittest.TestCase):
    """Chaîne complète dans le serveur radio solo (doublures de tests/test_protocol.py) : trade= joint à la demande
    d'une voix qui autorise propose_trade (pas à une autre), réponse structurée avec propose_trade -> offre figée,
    demande suivante portant l'offre, relue par le pont."""

    def test_request_reply_offer_next_request(self):
        import test_protocol as tp
        tmp = Path(tempfile.mkdtemp(prefix='rs-trade-'))
        try:
            exchange = tmp / 'trade'
            folder = exchange / 'personas'
            folder.mkdir(parents=True)
            (folder / 'gus.txt').write_text(
                'format=1\nid=gus\nname=Gus Bench\nfrequencies=160.0\nactions=say,propose_trade\n'
                '[place pier]\nat=6041,5217,0\nlabel=Bench pier\nuse=landing\n'
                '[trade]\nlanding=pier\narrival=boat\nevery_days=7\nhours=01:00-03:00\n'
                'item=Base.Battery:4-12\nitem=Base.Antibiotics:2-6\naccept=Base.MoneyBundle\n[prompt]\n'
                'You are Gus Bench, a smuggler of the test bench.\n', encoding='utf-8')
            (folder / 'ps.txt').write_text(tp.PS_SHEETS['ps'], encoding='utf-8')
            clock = tp.Clock()
            game = tp.Game('solo', exchange, clock)
            game.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua',
                      'client/RadioSurvivor_Client.lua')
            g = game.g
            t = game.rt.table_from
            g.sendClientCommand = lambda p, m, c, a: g.fire('OnClientCommand', m, c, p, a)
            player = g.makePlayer('Kate')
            g.getPlayer = lambda: player
            g.getSpecificPlayer = lambda n: player
            # E20-T07 : chargés par le jeu avec tous les fichiers serveur (mode boat, racine du troc RS_TradeRun).
            g.require('RadioSurvivor/TradeArrivals/RS_TradeArrival_Boat')
            g.require('RadioSurvivor/RS_TradeRun')
            game.rt.execute(ITEM_WEIGHTS)  # E22-T12 : poids des objets du troc, à la place des scripts du jeu
            g.fire('OnLoadRadioScripts', g.MANAGER, True)
            state = g.require('RadioSurvivor/RS_State')
            trade = g.require('RadioSurvivor/RS_Trade')
            talk_module = g.require('RadioSurvivor/RS_RadioTalk')
            notebook = g.require('CoreAI/CA_NotebookStore')   # E21-T04: characters of the notebook, voices companion
            assert notebook.init(True) is True
            assert state.data is not None
            notebook.data.characters = t({'c1': t({'id': 'c1'})})
            g.CoreAI = g.CoreAI or t({})
            g.CoreAI.notebookServer = t({'bound': t({})})
            g.CoreAI.notebookServer.bound[player] = 'c1'

            def turn(khz: int, text: str) -> dict:
                player.radio.device.channel = khz
                g.finishAiring()
                clock.offset += 11000
                talk_module.resetForTests()
                self.assertEqual(g.talk(player, text), 'ok')
                parsed = rb.parse_requests((exchange / 'requests.txt').read_text(encoding='utf-8'))
                self.assertEqual(len(parsed[1]), 1)
                return parsed[1][0]

            def respond(req_id: str, acts: list) -> None:
                body = {'version': 2, 'kind': 'radio_reply', 'id': req_id, 'say': ['Deal. Over.'], 'actions': acts}
                (exchange / 'responses.txt').write_text(f'resp={req_id}\npayload={npc.encode(body).hex()}\nend\n',
                                                        encoding='utf-8')

            req = turn(157000, 'Hello State.')
            self.assertEqual(req['voice'], 'ps')
            self.assertNotIn('trade', req)
            respond(req['id'], [])
            self.assertTrue(tp.pump(lambda: len(g.BROADCASTS) == 1, [lambda: g.fire('OnTick')]))

            req = turn(160000, 'What do you bring?')
            self.assertEqual(req['voice'], 'gus')
            book = npc.decode(bytes.fromhex(req['trade']))
            self.assertNotIn('offer', book)
            stock = {s['n']: s['q'] for s in book['stock'].values()}
            self.assertIn('Battery', stock)
            respond(req['id'], [{'type': 'propose_trade', 'gives': f"Battery:{stock['Battery']}",
                                 'wants': 'MoneyBundle:4'},
                                {'type': 'propose_trade', 'gives': 'GoldBar:1', 'wants': 'MoneyBundle:4'}])
            self.assertTrue(tp.pump(lambda: len(g.BROADCASTS) == 2, [lambda: g.fire('OnTick')]))
            offer = trade.offerOf('gus', 'solo', 'c1')
            self.assertEqual((offer.rev, offer.state, offer.margin), (1, 'open', 0.25))
            # E23-T06 : l'accord est inscrit dans le carnet du personnage, deux listes, sans points.
            history = g.require('CoreAI/CA_History').radio('c1')
            lines = [line for f in tp.lua_list(history.frequencies) for line in tp.lua_list(f.lines)
                     if line.kind == 'trade']
            self.assertEqual([line.text for line in lines], [f"MoneyBundle:4|Battery:{stock['Battery']}"])
            logs = [line for line in tp.lua_list(g.LOGS) if line.startswith('[RadioSurvivor] action propose_trade')]
            self.assertEqual(logs, [
                '[RadioSurvivor] action propose_trade voice=gus caller=solo accepted reason=ok',
                '[RadioSurvivor] action propose_trade voice=gus caller=solo refused reason=not_in_stock'])

            req = turn(160000, 'And the price?')
            ctx = rb.trade_context(req)
            self.assertEqual(ctx['offer']['items'], f"Battery:{stock['Battery']}")
            self.assertEqual(ctx['offer']['wants'], 'MoneyBundle:4')
            self.assertEqual(ctx['refused'], 'not_in_stock')
            self.assertEqual({s['n']: s['q'] for s in ctx['stock']}['Battery'], stock['Battery'])  # sa propre offre
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


class StaticTests(unittest.TestCase):

    def test_ascii_kahlua_safe_code(self):
        code = TRADE_LUA.read_text(encoding='utf-8')
        body = re.sub(r'--[^\n]*', '', code)
        self.assertTrue(body.isascii())
        self.assertIsNone(re.search(r'\bnext\s*\(|\bgoto\b|coroutine|ModData\.|send(Server|Client)Command|getText',
                                    body))
        self.assertIn('if isClient() then return end', code)
        self.assertNotIn('gsub(string.gsub', body)

    def test_server_joins_the_book_and_transport_writes_it(self):
        server = (LUA / 'server/RadioSurvivor_Server.lua').read_text(encoding='utf-8')
        self.assertEqual(server.count('Trade.field('), 2)
        transport = (LUA / 'server/RadioSurvivor/RS_BridgeLanes.lua').read_text(encoding='utf-8')
        self.assertRegex(transport, r"'facts', 'trade'[,}]")


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
