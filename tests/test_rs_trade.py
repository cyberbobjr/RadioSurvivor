"""Livre du passeur et action propose_trade (E13-T02) : RS_Trade.lua dans lupa, le pont (radio_bridge.py) et le
serveur radio complet (RadioSurvivor_Server.lua, doublures de tests/test_protocol.py).

    python RadioSurvivor/tests/test_rs_trade.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) : RS_Trade, RS_Actions, RS_Persona, RS_Codec,
RS_TradeValues, RS_OutsideNews, RadioSurvivor_Const ; doublures : GameTime (âge du monde), ZombRand, état privé
RS_State (table en mémoire), journal admin RS_ActionLog. Couvre : catalogue d'apport conforme à la table validée
(docs/specifications-techniques/passeur-table.md, section 3 ; poids relus dans les scripts vanilla 42.21), tirage du stock reproductible et dans
les fourchettes, prix ligne par ligne (exemples de la table), offre figée avec révision, réserve et remplacement,
refus hors table (stock, marge, poids, plafond, forme), stocks jamais négatifs sur un tirage aléatoire de
propositions, mémoire des affaires (marge la plus basse, tricherie, issue, expiration au passage suivant),
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
TRADE_LUA = LUA / 'server/RadioSurvivor/RS_Trade.lua'
DOC = ROOT / 'docs/specifications-techniques/passeur-table.md'
VANILLA_ITEMS = pz_paths.media_dir() / 'scripts/generated/items'
sys.path.insert(0, str(ROOT / 'bridge'))
sys.path.insert(0, str(ROOT / 'tests'))

import npc_protocol as npc  # noqa: E402
import radio_bridge as rb  # noqa: E402


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
"""

SHEET = {'id': 'gus', 'actions': ['say', 'propose_trade']}


class TradeHarness(unittest.TestCase):

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.rt.execute(STUBS)
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        self.T = self.rt.eval('require("RadioSurvivor/RS_Trade")')
        self.Actions = self.rt.eval('require("RadioSurvivor/RS_Actions")')
        self.Codec = self.rt.eval('require("RadioSurvivor/RS_Codec")')
        self.TV = self.rt.eval('require("RadioSurvivor/RS_TradeValues")')
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
        names = [e.n for e in lua_list(self.T.SUPPLY)]
        full = {n: stock.get(n, 0) for n in names}
        self.T.drawStock = lambda seed, passage: self.t(full)

    def propose(self, caller, items, margin=None, cid=None):
        return self.two(self.T.propose, caller, cid, items, margin)

    def available(self, caller='x', cid=None):
        a = self.T.available(caller, cid)
        return {k: a[k] for k in a.keys()}


class CatalogueTests(TradeHarness):

    def test_supply_matches_the_validated_table(self):
        doc = DOC.read_text(encoding='utf-8')
        section = doc[doc.index('## 3. Ce que le passeur apporte'):doc.index('## 4.')]
        for e in lua_list(self.T.SUPPLY):
            with self.subTest(e.n):
                self.assertTrue(f'`{e.n}`' in section or f'`{e.t}`' in section, e.n)
                self.assertGreater(self.TV.sellValue(e.t), 0)
                if e.gr is None:
                    rng = f'{e.min} – {e.max}' if e.min != e.max else None
                    if rng:
                        row = next(line for line in section.splitlines() if f'`{e.n}`' in line)
                        self.assertIn(rng, row)
        self.assertEqual((self.T.GROUPS.seeds.min, self.T.GROUPS.seeds.max, self.T.GROUPS.seeds.kinds), (3, 8, 4))
        self.assertIn('3 – 8 sachets, 4 sortes au plus', section)
        self.assertEqual((self.T.GROUPS.alcohol.min, self.T.GROUPS.alcohol.max), (1, 4))
        self.assertIn('1 – 4 bouteilles au total', section)
        self.assertEqual((self.T.CAP_POINTS, self.T.CAP_KG), (120, 10))
        self.assertIn('au plus 120 points', doc)
        self.assertIn('pèse **au plus 10 kg**', doc)
        self.assertEqual((self.T.MARGIN_MIN, self.T.MARGIN_DEFAULT, self.T.MARGIN_MAX, self.T.M_MAX, self.T.RARITY),
                         (0.10, 0.25, 0.50, 1.75, 1.25))
        caps = {t.k: t.cap for t in lua_list(self.T.TAKES)}
        self.assertEqual(caps, {'valuables': 60, 'images': 40, 'papers': 30, 'military': 60})

    @unittest.skipUnless(VANILLA_ITEMS.is_dir(), 'vanilla 42.21 scripts missing')
    def test_weights_are_the_vanilla_ones_with_their_fluid(self):
        text = {f.name: f.read_text(encoding='utf-8', errors='replace') for f in VANILLA_ITEMS.glob('*.txt')}
        for e in lua_list(self.T.SUPPLY):
            if not e.t.startswith('Base.'):
                continue
            name = e.t[5:]
            block = None
            for body in text.values():
                m = re.search(r'(?m)^\s*item\s+' + re.escape(name) + r'\s*\n\s*\{(.*?)\n    \}', body, re.S)
                if m:
                    block = m.group(1)
                    break
            with self.subTest(name):
                self.assertIsNotNone(block)
                weight = float(re.search(r'Weight\s*=\s*([\d.]+)', block).group(1))
                cap = re.search(r'Capacity\s*=\s*([\d.]+)', block)
                self.assertAlmostEqual(e.w, weight + (float(cap.group(1)) if cap else 0.0), places=6)

    def test_news_weight_is_the_mod_script(self):
        script = (MOD / 'media/scripts/RadioSurvivor_outsidenews.txt').read_text(encoding='utf-8')
        news = next(e for e in lua_list(self.T.SUPPLY) if e.n == 'OutsideNews')
        self.assertAlmostEqual(news.w, float(re.search(r'Weight\s*=\s*([\d.]+)', script).group(1)))
        self.assertEqual((news.min, news.max), (1, 1))


class StockTests(TradeHarness):

    def test_draw_is_reproducible_and_within_ranges(self):
        seen = set()
        for passage in range(1, 400):
            a = self.T.drawStock(123456, passage)
            b = self.T.drawStock(123456, passage)
            stock = {k: a[k] for k in a.keys()}
            self.assertEqual(stock, {k: b[k] for k in b.keys()})
            seen.add(tuple(sorted(stock.items())))
            for e in lua_list(self.T.SUPPLY):
                if e.gr is None:
                    self.assertTrue(e.min <= stock[e.n] <= e.max, (passage, e.n, stock[e.n]))
            seeds = [stock[e.n] for e in lua_list(self.T.SUPPLY) if e.gr == 'seeds']
            self.assertTrue(3 <= sum(seeds) <= 8 and 1 <= sum(1 for s in seeds if s) <= 4, seeds)
            alcohol = [stock[e.n] for e in lua_list(self.T.SUPPLY) if e.gr == 'alcohol']
            self.assertTrue(1 <= sum(alcohol) <= 4, alcohol)
        self.assertGreater(len(seen), 300)
        self.assertNotEqual({k: v for k, v in self.T.drawStock(1, 5).items()},
                            {k: v for k, v in self.T.drawStock(2, 5).items()})

    def test_seed_drawn_once_and_kept_in_the_private_state(self):
        self.T.stock()
        seed = self.g.STATE.data.trade.seed
        self.assertTrue(1 <= seed <= 2147483646)
        self.T.stock()
        self.assertEqual(self.g.STATE.data.trade.seed, seed)
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
        # Exemple 4 : un seul antibiotique au stock (rareté), cordon 1,25 : 16 / 14 / 19 selon la marge.
        self.force_stock({'Antibiotics': 1})
        self.T.setCordon(self.T.passage(), 1.25)
        prices = {}
        for margin in (0.25, 0.10, 0.50):
            store = self.g.STATE.data.trade
            book = store.books['kate']
            book.deals = self.t([{'state': 'done', 'rev': 0, 'passage': 0, 'items': 'Battery:1', 'price': 1}] * 3)
            offer, why = self.propose('kate', 'Antibiotics', margin)
            prices[margin] = offer.price if offer else why
        self.assertEqual(prices, {0.25: 16, 0.10: 14, 0.50: 19})

    def test_multiplier_capped(self):
        self.force_stock({'Antibiotics': 1})
        self.T.setCordon(self.T.passage(), 1.5)   # 1,5 x 1,25 = 1,875 -> 1,75
        offer, _ = self.propose('kate', 'Antibiotics:1', 0.25)
        self.assertEqual(offer.price, 18)          # ceil(8 x 1,25 x 1,75) = ceil(17,5)
        self.assertFalse(self.T.setCordon(self.T.passage(), 2))


class OfferTests(TradeHarness):

    def test_offer_frozen_with_revision_and_reserved(self):
        self.force_stock({'Antibiotics': 4, 'Battery': 6})
        offer, why = self.propose('kate', 'antibiotics:2,BATTERY:3', 0.3)
        self.assertIsNone(why)
        self.assertEqual((offer.rev, offer.state, offer.price, offer.margin, offer.weight), (1, 'open', 29, 0.3, 0.5))
        self.assertEqual(self.available('bob'), dict(self.available('kate'), Antibiotics=2, Battery=3))
        # Un autre appelant ne peut pas dépasser ce qui reste.
        self.assertEqual(self.propose('bob', 'Antibiotics:3')[1], 'over_stock')
        offer2, _ = self.propose('bob', 'Antibiotics:2')
        self.assertEqual(offer2.rev, 2)
        self.assertEqual(self.propose('carl', 'Antibiotics')[1], 'not_in_stock')
        # Même appelant : la nouvelle offre remplace l'ancienne et rend sa réserve.
        offer3, _ = self.propose('kate', 'Battery:6')
        self.assertEqual(offer3.rev, 3)
        deals = lua_list(self.T.deals('kate', None))
        self.assertEqual([(d.rev, d.state) for d in deals], [(1, 'replaced'), (3, 'open')])
        self.assertEqual(self.available('carl')['Antibiotics'], 2)
        self.assertEqual(self.available('carl')['Battery'], 0)
        self.assertTrue(any('offer 3 frozen for kate: Battery:6' in line for line in lua_list(self.g.LOGS)))

    def test_refusals_outside_the_table(self):
        self.force_stock({'Antibiotics': 20, 'CigaretteCarton': 1, 'ShotgunShellsBox': 2, 'Coffee2': 3,
                          'Vodka': 2, 'Battery': 4})
        cases = {
            'Money:2': 'not_in_stock', 'Base.Antibiotics:2': None, 'Whiskey': 'not_in_stock',
            'Battery:5': 'over_stock', 'Antibiotics:15': 'over_cap',
            'ShotgunShellsBox:2,Coffee2:3,Vodka:2,CigaretteCarton:1': 'over_weight',
            'Antibiotics:2,': 'bad_params', 'Antibiotics:0': 'bad_params', 'Antibiotics:2,antibiotics:1': 'bad_params',
            'Antibiotics x2': 'bad_params', '': 'bad_params', 'Antibiotics:100': 'bad_params',
        }
        for items, reason in cases.items():
            with self.subTest(items):
                offer, why = self.propose('kate', items)
                self.assertEqual(why, reason)
                self.assertEqual(offer is None, reason is not None)
        for margin in (0.05, 0.51, 1.0, -0.2, float('nan')):
            with self.subTest(margin=margin):
                self.assertEqual(self.propose('kate', 'Battery', margin)[1], 'bad_margin')
        self.assertEqual(self.propose('kate', 'Battery', 0.249)[1], None)   # arrondi à 0,25
        self.assertEqual(self.propose('kate', 'Battery', 0.24)[1], 'bad_margin')
        book = self.g.STATE.data.trade.books['kate']
        self.propose('kate', 'Battery:9')
        self.assertEqual(book.refused.reason, 'over_stock')

    def test_stocks_never_negative_and_no_offer_outside_the_table(self):
        rnd = random.Random(7)
        names = [e.n for e in lua_list(self.T.SUPPLY)] + ['Money', 'GoldBar', 'Base.Battery']
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
                margin = rnd.choice([None, 0.1, 0.25, 0.3, 0.5, 0.6, rnd.random()])
                caller = rnd.choice(callers)
                if rnd.random() < 0.05:
                    o = self.T.offerOf(caller, None)
                    if o is not None:
                        self.T.close(caller, None, o.rev, rnd.choice(['done', 'cheated', 'cancelled']))
                offer, why = self.propose(caller, items, margin)
                if offer is None:
                    self.assertIn(why, lua_list(self.T.REASONS))
                    continue
                accepted += 1
                self.assertTrue(0.1 - 1e-9 <= offer.margin <= 0.5 + 1e-9 and offer.price <= 120
                                and offer.weight <= 10 + 1e-9)
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
                root = self.g.STATE.data.trade
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
        tricherie 0,50 ; personnage inconnu ou sans carnet : neutre. La fourchette part dans le contexte trade=."""
        self.force_stock({'Battery': 12})
        state = self.g.STATE.data
        state.characters = self.t({'cg': {'id': 'cg'}, 'cb': {'id': 'cb'}, 'cn': {'id': 'cn'},
                                   'dead': {'id': 'dead', 'retired': True}})
        state.reputation = self.t({'cg': {'score': 40}, 'cb': {'score': -40}, 'cn': {'score': 0},
                                   'dead': {'score': -40}})
        self.assertAlmostEqual(self.T.marginRange('kate', 'cg')[0], 0.10)
        self.assertAlmostEqual(self.T.marginRange('kate', 'cn')[0], 0.25)
        self.assertAlmostEqual(self.T.marginRange('kate', 'cb')[0], 0.40)
        self.assertAlmostEqual(self.T.marginRange('kate', 'dead')[0], 0.25)
        self.assertAlmostEqual(self.T.marginRange('kate', None)[0], 0.25)
        self.assertEqual(self.propose('bad', 'Battery', 0.30, cid='cb')[1], 'bad_margin')
        offer, _ = self.propose('bad', 'Battery', None, cid='cb')
        self.assertAlmostEqual(offer.margin, 0.40)
        self.assertTrue(self.T.close('bad', 'cb', offer.rev, 'done'))
        self.assertAlmostEqual(self.T.marginRange('bad', 'cb')[0], 0.35)   # history discount on top of the level
        offer, _ = self.propose('good', 'Battery', None, cid='cg')
        self.assertAlmostEqual(offer.margin, 0.10)
        self.assertTrue(self.T.close('good', 'cg', offer.rev, 'cheated'))
        self.assertEqual(tuple(self.T.marginRange('good', 'cg')), (0.5, 0.5))
        ctx = self.T.context(self.t(SHEET), 'bad', 'cb')
        self.assertAlmostEqual(ctx.marginMin, 0.35)

    def test_margin_floor_follows_past_deals(self):
        self.force_stock({'Battery': 12})
        self.assertEqual(tuple(self.T.marginRange('kate', None)), (0.25, 0.5))
        for expected in (0.20, 0.15, 0.10, 0.10):
            offer, _ = self.propose('kate', 'Battery')
            self.assertTrue(self.T.close('kate', None, offer.rev, 'done'))
            self.assertAlmostEqual(self.T.marginRange('kate', None)[0], expected)
        self.assertEqual(self.propose('kate', 'Battery', 0.09)[1], 'bad_margin')
        offer, _ = self.propose('kate', 'Battery', 0.10)
        self.assertTrue(self.T.close('kate', None, offer.rev, 'cheated'))
        self.assertEqual(tuple(self.T.marginRange('kate', None)), (0.5, 0.5))
        self.assertEqual(self.propose('kate', 'Battery', 0.4)[1], 'bad_margin')
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
        self.propose('solo', 'Battery', None, 'c1')
        self.assertIsNone(self.T.offerOf('solo', 'c2'))
        self.assertEqual(self.T.offerOf('solo', 'c1').rev, 1)
        for i in range(60):
            self.propose(f'p{i}', 'Battery:99')   # refus : crée le livre (dernier refus)
        self.assertLessEqual(len(list(self.g.STATE.data.trade.books.keys())), self.T.MAX_BOOKS)
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
        sheet = self.t(sheet or SHEET)
        out = self.Actions.decide(sheet, caller, self.t(actions), 1000, self.t({'cid': None, 'day': '1993-07-10'}))
        return [(d.type, d.reason) for d in lua_list(out)]

    def test_executor_registered_and_judged(self):
        self.force_stock({'Antibiotics': 3, 'Battery': 4})
        self.assertEqual(self.decide([
            {'type': 'propose_trade', 'items': 'Antibiotics:2', 'margin': 0.3},
            {'type': 'propose_trade', 'items': 'Battery:9'},
            {'type': 'propose_trade', 'items': 'Battery', 'colour': 'red'},
        ]), [('propose_trade', 'ok'), ('propose_trade', 'over_stock'), ('propose_trade', 'bad_params')])
        self.assertEqual(self.decide([{'type': 'propose_trade', 'items': 'Battery', 'margin': '0.3'},
                                      {'type': 'propose_trade', 'margin': 0.3},
                                      {'type': 'propose_trade', 'items': 'Battery;Antibiotics'}]),
                         [('propose_trade', 'bad_params')] * 3)
        self.assertEqual(self.decide([{'type': 'propose_trade', 'items': 'Battery'}],
                                     sheet={'id': 'walt', 'actions': ['say']}), [('propose_trade', 'not_allowed')])
        self.assertEqual(self.T.offerOf('kate', None).rev, 1)
        self.assertIn('propose_trade:over_stock', lua_list(self.g.ACTION_LOG))


class ContextTests(TradeHarness):

    def context(self, caller='kate'):
        hexed = self.T.field(self.t(SHEET), caller, None)
        return {'trade': hexed}, npc.decode(bytes.fromhex(hexed))

    def test_field_only_for_a_trading_voice(self):
        self.assertIsNone(self.T.field(self.t({'id': 'walt', 'actions': ['say', 'remember']}), 'kate', None))
        self.assertIsNone(self.T.field(None, 'kate', None))

    def test_context_read_by_the_bridge(self):
        self.force_stock({'Antibiotics': 1, 'Battery': 6, 'OutsideNews': 1})
        offer, _ = self.propose('kate', 'Battery:2')
        self.T.close('kate', None, offer.rev, 'done')
        self.propose('kate', 'Antibiotics')
        self.propose('kate', 'Battery:9')
        req, raw = self.context()
        self.assertEqual((raw['passage'], raw['cap'], raw['kg'], raw['marginMin'], raw['marginMax']),
                         (1, 120, 10, 0.2, 0.5))
        stock = {s['n']: s['q'] for s in raw['stock'].values()}
        # Sa propre offre ouverte (l'antibiotique) reste « offrable » : une nouvelle offre la remplace.
        self.assertEqual(stock, {'Antibiotics': 1, 'Battery': 4, 'OutsideNews': 1})
        sheet = None
        ctx = rb.trade_context(req, sheet or FakeSheet())
        self.assertIsNotNone(ctx)
        self.assertEqual(ctx['offer']['items'], 'Antibiotics:1')
        self.assertEqual([d['state'] for d in ctx['deals']], ['done', 'open'])
        self.assertEqual(ctx['refused'], 'over_stock')
        prompt = rb.trade_prompt(ctx, '[Caller 1]')
        for text in ('run number 1', 'at most 120 points', 'at most 10 kg', 'from 0.2 to 0.5',
                     '- Battery: 4 left, value 2, 0.1 kg, 3 points each', 'OutsideNews: 1 left',
                     'valuables (at most 60 points per run): ', 'MoneyBundle 10', 'Money 1 per 10',
                     'AssaultRifle 20 (max 1) (condition 50%+)',
                     'papers (at most 30 points per run and 10 pieces, only papers with a name on them)',
                     'Your offer to [Caller 1] (number 2): Antibiotics:1 for 12 points (standing)',
                     'run 1: Battery:2 for 5 points, done, the caller paid in full',
                     'more than what is left', 'You may refuse a deal'):
            self.assertIn(text, prompt)
        self.assertNotRegex(prompt, r'\d{3}\.\d|kHz|MHz|secret')

    def test_bridge_ignores_a_broken_book(self):
        sheet = FakeSheet()
        good = {'passage': 1, 'cap': 120, 'kg': 10, 'marginMin': 0.25, 'marginMax': 0.5, 'cordon': 1}
        for bad in ({}, dict(good, cap='x'), dict(good, marginMin=0.6), dict(good, passage=-1)):
            self.assertIsNone(rb.trade_context({'trade': npc.encode(bad).hex()}, sheet))
        self.assertIsNone(rb.trade_context({'trade': 'zz'}, sheet))
        self.assertIsNone(rb.trade_context({'trade': 'ab' * 20000}, sheet))
        ctx = rb.trade_context({'trade': npc.encode(dict(good, stock={1: {'n': 'Bad name', 'q': 1, 'v': 1, 'w': 1,
                                                                          'unit': 1}},
                                                            offer={'rev': 1, 'items': 'x;y', 'price': 3,
                                                                   'state': 'open'},
                                                            refused='because')).hex()}, sheet)
        self.assertEqual((ctx['stock'], ctx['offer'], ctx['refused']), ([], None, None))
        self.assertIn('nothing left to sell', rb.trade_prompt(ctx, 'you'))
        self.assertEqual(rb.trade_prompt(None, 'you'), '')
        leak = dict(good, takes={1: {'k': 'papers', 'cap': 30, 'items': 'He sells the names.'}})
        self.assertIsNone(rb.trade_context({'trade': npc.encode(leak).hex()}, FakeSheet(['He sells the names.'])))


class FakeSheet:
    def __init__(self, secrets=None):
        self.id = 'gus'
        self.secrets = secrets or []
        self.actions = ['say', 'propose_trade']
        self.places = []


class BridgeFormTests(unittest.TestCase):

    def test_action_offered_described_and_bounded(self):
        sheet = FakeSheet()
        self.assertIn('propose_trade', rb.EXECUTABLE_ACTIONS)
        self.assertEqual(rb.offered_actions(sheet), ['propose_trade'])
        prompt = rb.actions_prompt(sheet)
        self.assertIn('"items"', prompt)
        self.assertIn('{"type": "propose_trade", "items": "Antibiotics:2,Battery:4", "margin": 0.25}', prompt)
        kept = rb.bounded_actions(sheet, [
            {'type': 'propose_trade', 'items': 'Antibiotics:2, Battery:4', 'margin': 0.3},
            {'type': 'propose_trade', 'items': 'Battery'},
            {'type': 'propose_trade', 'items': 'Battery', 'price': 3},
            {'type': 'propose_trade', 'items': 'Battery;Coffee2'},
            {'type': 'propose_trade', 'margin': 0.3},
            {'type': 'propose_trade', 'items': 'Battery', 'margin': 2},
            {'type': 'propose_trade', 'items': 'Battery', 'margin': True},
        ])
        self.assertEqual(kept, [{'type': 'propose_trade', 'items': 'Antibiotics:2, Battery:4', 'margin': 0.3},
                                {'type': 'propose_trade', 'items': 'Battery'}])
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
                'format=1\nid=gus\nname=Gus Bench\nfrequencies=160.0\nactions=say,propose_trade\n[prompt]\n'
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
            g.fire('OnLoadRadioScripts', g.MANAGER, True)
            state = g.require('RadioSurvivor/RS_State')
            trade = g.require('RadioSurvivor/RS_Trade')
            talk_module = g.require('RadioSurvivor/RS_RadioTalk')
            assert state.init(True) is True
            state.data.characters = t({'c1': t({'id': 'c1'})})
            g.RS_CarnetServer = t({'bound': t({})})
            g.RS_CarnetServer.bound[player] = 'c1'

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
            respond(req['id'], [{'type': 'propose_trade', 'items': f"Battery:{stock['Battery']}", 'margin': 0.3},
                                {'type': 'propose_trade', 'items': 'GoldBar:1'}])
            self.assertTrue(tp.pump(lambda: len(g.BROADCASTS) == 2, [lambda: g.fire('OnTick')]))
            offer = trade.offerOf('solo', 'c1')
            self.assertEqual((offer.rev, offer.state, offer.margin), (1, 'open', 0.3))
            logs = [line for line in tp.lua_list(g.LOGS) if line.startswith('[RadioSurvivor] action propose_trade')]
            self.assertEqual(logs, [
                '[RadioSurvivor] action propose_trade voice=gus caller=solo accepted reason=ok',
                '[RadioSurvivor] action propose_trade voice=gus caller=solo refused reason=not_in_stock'])

            req = turn(160000, 'And the price?')
            ctx = rb.trade_context(req, FakeSheet())
            self.assertEqual(ctx['offer']['items'], f"Battery:{stock['Battery']}")
            self.assertEqual(ctx['offer']['price'], offer.price)
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
        transport = (LUA / 'server/RadioSurvivor/RS_Transport.lua').read_text(encoding='utf-8')
        self.assertRegex(transport, r"'facts', 'trade'[,}]")


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
