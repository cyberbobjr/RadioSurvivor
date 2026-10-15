"""Tests hors jeu des demandes d'aide à un groupe Living Knox (LK11-T06) : server/LivingKnox/LK_Relations.lua,
Stock.takeItem (LK_Stock.lua), le menu client/LivingKnox/LK_RelationsView.lua et la suite en jeu lk.aid
(dev/.../RST_LKAid.lua) dans le banc.

    python RadioSurvivor/tests/test_lk_aid.py

Banc tests/harness.py (solo, ou serveur dédié + deux clients) avec le vrai registre des groupes, le vrai aménagement
des foyers (LK_Homes), le vrai stock (LK_Stock, doublures de tests/test_lk_stock.py) et le vrai registre des
attitudes (LK_Hostility). Doublures ajoutées, relevées dans le Java 42.21.0 et le Lua vanilla :
- ItemContainer.getCapacityWeight / getEffectiveCapacity(personnage) (J/inventory/ItemContainer.java:2139, 208 ;
  poids d'un objet = champ w, 1 par défaut) ; IsoGridSquare.AddWorldInventoryItem(objet, x, y, h, transmit)
  (J/iso/IsoGridSquare.java:5200 : envoi aux clients sur un serveur si transmit) ;
- LivingKnox.Bodies.find (corps du PNJ : zombie du banc) et LivingKnox.Speech.say (réplique notée, non affichée :
  LK_Speech a son banc) remplacés ;
- menu contextuel : ISContextMenu:getNew, addOption, addSubMenu, ISWorldObjectContextMenu.setTest, getText.
Elles NE PROUVENT PAS l'API réelle, seulement la logique : suite en jeu lk.aid, essai du menu.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LUA  # noqa: E402
from test_lk_stock import Base as StockBase, KITCHEN, OFFSCREEN_DOUBLES  # noqa: E402
from test_lk_homes import HOUSE  # noqa: E402

R = 'LivingKnox.Relations'
ST = 'LivingKnox.Stock'
RELATIONS = 'server/LivingKnox/LK_Relations.lua'
VIEW = 'client/LivingKnox/LK_RelationsView.lua'
KEY_A, KEY_B = 'c-alpha', 'c-bravo'

AID_DOUBLES = r'''
local H = HARNESS
local Ctr = getmetatable(NEW_CONTAINER('x'))
CAPACITY = 50
COUNT.ground, COUNT.groundSent = 0, 0
function Ctr:getCapacityWeight()
    local w = 0
    for _, it in ipairs(self.items.items) do w = w + (rawget(it, 'w') or 1) end
    return w
end
function Ctr:getEffectiveCapacity(chr)
    if chr == nil then error('No implementation found for getEffectiveCapacity', 2) end
    return CAPACITY
end
local Sq = getmetatable(H.square(0, 0, 0))
function Sq:AddWorldInventoryItem(it, x, y, h, transmit)
    if type(it) ~= 'table' or type(transmit) ~= 'boolean' then error('AddWorldInventoryItem overload not expected', 2) end
    H.num(x, 'AddWorldInventoryItem') H.num(y, 'AddWorldInventoryItem') H.num(h, 'AddWorldInventoryItem')
    self.ground = self.ground or {}
    self.ground[#self.ground + 1] = it
    COUNT.ground = COUNT.ground + 1
    if transmit and isServer() then COUNT.groundSent = COUNT.groundSent + 1 end
    return it
end
COUNT.addSent = 0
local send = sendAddItemToContainer
sendAddItemToContainer = function(c, it)
    send(c, it)
    if isServer() then COUNT.addSent = COUNT.addSent + 1 end
end
'''

# Après le chargement des modules : corps des PNJ et réplique notée.
ENGINE_STUBS = r'''
BODIES = {}
LivingKnox.Bodies = LivingKnox.Bodies or {}
LivingKnox.Bodies.find = function(id) return BODIES[id] end
LivingKnox.Bodies.bound = BODIES
SAID = {}
LivingKnox.Speech = LivingKnox.Speech or {}
LivingKnox.Speech.say = function(npc, what, opts)
    SAID[#SAID + 1] = { npc = npc, key = what.key, band = opts.band, chat = opts.chat }
    return { id = 'sp', heard = {}, names = {} }
end
LivingKnox.Speech.bandOf = function(level)
    if level == 'favorable' or level == 'trusting' then return 'friendly' end
    if level == 'cautious' then return 'neutral' end
    return 'hostile'
end
FACTS = {}
LivingKnox.listen('aidDecided', 'test', function(info) FACTS[#FACTS + 1] = info end)
function BODY(id, x, y, z)
    local zb = HARNESS.spawnZombie(900 + #SAID + math.random(1, 50), x, y, z or 0, 'server')
    BODIES[id] = zb
    return zb
end
'''


class Base(StockBase):
    mode = 'solo'
    gtype = 'settlers'
    members = 1

    def setUp(self):
        super().setUp()
        for m in (('solo',) if self.mode == 'solo' else ('server', 'A', 'B')):
            self.h.load(m, OFFSCREEN_DOUBLES)
            self.h.load(m, AID_DOUBLES)
            self.h.load(m, RELATIONS)
        self.run_lua(ENGINE_STUBS)
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)
        self.run_lua(f'BIND("A", "{KEY_A}")')
        if self.mode != 'solo':
            self.run_lua(f'BIND("B", "{KEY_B}")')
        self.gid = self.group(gtype=self.gtype, members=self.members)
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) local g = d.groups["{self.gid}"] '
                     f'for _, m in pairs(g.members) do m.npc = "lk-1" break end return true, true end))')
        self.minute()
        self.assertEqual(self.ev(f'LivingKnox.Groups.get("{self.gid}").stock.fill'), 'done')
        self.run_lua('local p = HARNESS.players.A HARNESS.place(p, 103, 104, 0)')
        self.run_lua('BODY("lk-1", 104, 104, 0)')

    def ask(self, kind, key=KEY_A, player='A', npc='"lk-1"'):
        return self.run_lua(f'return {R}.requestAid("{self.gid}", "{key}", "{kind}", '
                            f'{{ player = HARNESS.players.{player}, npc = {npc} }})')

    def have(self, cat):
        return self.ev(f'{ST}.needs("{self.gid}").have.{cat}')

    def inv_ids(self, player='A'):
        return [it.id for it in self.ev(f'HARNESS.players.{player}:getInventory():getItems().items').values()]

    def aid_log(self):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{self.gid}").log').values() if e.kind == 'aid']

    def said(self):
        return [(s.npc, s.key, s.band) for s in self.ev('SAID').values()]

    def later(self, hours):
        self.h.advance(int(hours * 60))


class AidTests(Base):
    def test_gift_leaves_the_stock_once_and_reaches_the_inventory(self):
        food = self.have('food')
        out = self.ask('food')
        self.assertEqual((out.accepted, out.reason, out.where, out.decided), (True, 'given', 'inventory', True))
        self.assertEqual(self.inv_ids(), [out.item.i])
        self.assertEqual(self.have('food'), food - 1)
        self.assertNotIn(out.item.i, list(self.ev(f'REF_IDS("{self.gid}")').values()))
        self.assertNotIn(out.item.i, list(self.ev(f'REAL_IDS("{self.gid}")').values()))
        # Relecture suivante : ni perte ni vol (l'objet est chez le joueur, ôté de la référence).
        r = self.check(self.gid)
        self.assertEqual((r.action, r.missing), ('checked', 0))
        self.assertEqual(self.ev(f'LivingKnox.Hostility.get("{self.gid}", "{KEY_A}").trend'), 'stable')
        # Connue de tous les membres : journal du groupe et fait publié ; réplique du PNJ.
        self.assertEqual(self.aid_log(), [f'aid food given to {KEY_A}: {out.item.t}'])
        facts = [dict(f.items()) for f in self.ev('FACTS').values()]
        self.assertEqual([(f['group'], f['player'], f['kind'], f['accepted'], f['reason'], f['npc']) for f in facts],
                         [(self.gid, KEY_A, 'food', True, 'given', 'lk-1')])
        self.assertEqual(self.said(), [('lk-1', 'IGUI_LK_Aid_Given_food', 'friendly')])

    def test_one_request_per_group_and_period(self):
        self.assertEqual(self.ask('food').reason, 'given')
        food, care = self.have('food'), self.have('medical')
        again = self.ask('care')
        self.assertEqual((again.accepted, again.reason, again.decided), (False, 'again', False))
        self.assertGreater(again.wait, 23)
        self.assertEqual((self.have('food'), self.have('medical')), (food, care))
        self.assertEqual(len(self.aid_log()), 1)
        self.assertEqual(self.said()[-1], ('lk-1', 'IGUI_LK_Aid_Refuse_again', 'friendly'))
        # Un autre joueur du même groupe : même période (une demande par groupe).
        self.run_lua('BIND("A", "c-other")')
        self.assertEqual(self.ask('care', key='c-other').reason, 'again')
        # Période écoulée : admise de nouveau.
        self.later(24)
        out = self.ask('care')
        self.assertEqual(out.reason, 'given')
        self.assertEqual(self.have('medical'), care - 1)

    def test_refused_when_the_stock_lacks_it(self):
        # Un membre : eau visée 3, le kit en a 3 -> donner ferait passer sous la réserve.
        water = self.have('water')
        self.assertEqual(water, self.ev(f'{ST}.needs("{self.gid}").want.water'))
        out = self.ask('water')
        self.assertEqual((out.accepted, out.reason, out.decided), (False, 'short', True))
        self.assertEqual(self.have('water'), water)
        self.assertEqual(self.inv_ids(), [])
        self.assertEqual(self.aid_log(), [f'aid water refused to {KEY_A}: short (have 3, keep 3)'])
        self.assertEqual(self.said(), [('lk-1', 'IGUI_LK_Aid_Refuse_short', 'friendly')])
        # Refus = demande décidée : la période est consommée.
        self.assertEqual(self.ask('food').reason, 'again')

    def test_refused_when_nothing_usable_is_left(self):
        # Totaux suffisants mais aucun objet donnable (nourriture pourrie) : refus, rien de pris.
        self.run_lua(f'{ST}.consumable = function() return false end')
        food = self.have('food')
        out = self.ask('food')
        self.assertEqual((out.reason, out.decided, out.detail), ('short', True, 'nothing usable'))
        self.assertEqual(self.have('food'), food)

    def test_refused_by_attitude(self):
        for _ in range(4):
            self.run_lua(f'assert(LivingKnox.Hostility.record("{self.gid}", "{KEY_A}", "theft", '
                         f'{{ attributable = true }}))')
        level = self.ev(f'LivingKnox.Hostility.get("{self.gid}", "{KEY_A}").level')
        self.assertIn(level, ('wary', 'hostile', 'cautious'))
        food = self.have('food')
        out = self.ask('food')
        self.assertEqual((out.accepted, out.reason, out.detail), (False, 'attitude', level))
        self.assertEqual(self.have('food'), food)
        self.assertEqual(self.aid_log(), [f'aid food refused to {KEY_A}: attitude {level}'])
        self.assertEqual(self.said()[-1][1], 'IGUI_LK_Aid_Refuse_attitude')

    def test_ration_is_updated_after_a_food_gift(self):
        self.run_lua('for _ = 1, 9 do CUPBOARD.container:AddItem(instanceItem("Base.TinnedBeans")) end')
        self.check(self.gid)
        out = self.ask('food')
        self.assertEqual(out.reason, 'given')
        self.assertEqual(self.ev(f'{ST}.needs("{self.gid}").ration'),
                         self.ev(f'{ST}.needs("{self.gid}").next'))

    def test_overloaded_player_gets_it_on_the_ground_at_the_npc(self):
        self.run_lua('CAPACITY = 0')
        out = self.ask('food')
        self.assertEqual((out.reason, out.where), ('given', 'ground'))
        self.assertEqual(self.inv_ids(), [])
        self.assertEqual(self.ev('COUNT.ground'), 1)
        self.assertEqual(self.ev(f'#HARNESS.square(104, 104, 0).ground'), 1)
        self.assertEqual(self.ev('HARNESS.square(104, 104, 0).ground[1].id'), out.item.i)

    def test_unreadable_home_is_refused_without_using_the_period(self):
        self.run_lua(f'local real = LivingKnox.Homes.ready LivingKnox.Homes.ready = function() return nil, "unloaded" end '
                     f'OUT = {R}.requestAid("{self.gid}", "{KEY_A}", "care", '
                     f'{{ player = HARNESS.players.A, npc = "lk-1" }}) LivingKnox.Homes.ready = real')
        out = self.ev('OUT')
        self.assertEqual((out.reason, out.decided), ('away', False))
        self.assertEqual(self.said()[-1][1], 'IGUI_LK_Aid_Refuse_away')
        self.assertEqual(self.ask('care').reason, 'given')

    def test_bad_inputs_decide_nothing(self):
        cases = [
            (f'"{self.gid}", "{KEY_A}", "money"', 'bad kind'),
            (f'"{self.gid}", "bad key!", "food"', 'bad player key'),
            (f'"grp-99", "{KEY_A}", "food"', 'unknown group'),
            (f'"{self.gid}", "{KEY_A}", "food", {{ npc = "lk-7", player = HARNESS.players.A }}', 'npc not in group'),
            (f'"{self.gid}", "nobody", "food"', 'no recipient (player offline, npc not embodied)'),
        ]
        for args, why in cases:
            with self.subTest(args=args):
                self.assertEqual(self.run_lua(f'return select(2, {R}.requestAid({args}))'), why)
        self.assertEqual(self.said(), [])
        self.assertEqual(self.aid_log(), [])
        self.assertEqual(self.ask('food').reason, 'given')

    def test_player_found_by_key_without_player_object(self):
        # Chemin d'une intention du carnet : seule la clé est connue, le joueur est retrouvé (solo : joueur local).
        out = self.run_lua(f'return {R}.requestAid("{self.gid}", "{KEY_A}", "food", {{ npc = "lk-1" }})')
        self.assertEqual((out.reason, out.where), ('given', 'inventory'))
        self.assertEqual(self.inv_ids(), [out.item.i])

    def test_menu_request_checks_distance_and_identity(self):
        ask = f'return {R}.ask(HARNESS.players.A, {{ npc = "lk-1", kind = "food" }})'
        self.run_lua('HARNESS.place(HARNESS.players.A, 110, 104, 0)')
        self.assertEqual(self.run_lua(ask.replace('return ', 'return select(2, ') + ')'), 'too far')
        self.run_lua('HARNESS.place(HARNESS.players.A, 103, 104, 0)')
        self.run_lua('RS_CarnetServer.bound[HARNESS.players.A] = nil')
        out = self.run_lua(ask)
        self.assertEqual((out.reason, out.decided), ('stranger', False))
        self.assertEqual(self.said(), [('lk-1', 'IGUI_LK_Aid_Refuse_stranger', None)])
        self.run_lua(f'BIND("A", "{KEY_A}")')
        self.assertEqual(self.run_lua(ask).reason, 'given')
        for bad in ('{ npc = "lk-1", kind = "money" }', '{ npc = 3, kind = "food" }', 'nil'):
            with self.subTest(bad=bad):
                self.assertEqual(self.run_lua(f'return select(2, {R}.ask(HARNESS.players.A, {bad}))'), 'bad request')


MENU_DOUBLES = r'''
MENU = {}
local Menu = {}
Menu.__index = Menu
function Menu:addOption(name, target, fn, a, b)
    local o = { name = name, target = target, fn = fn, a = a, b = b }
    self.options[#self.options + 1] = o
    return o
end
function Menu:addSubMenu(option, sub) option.sub = sub end
ISContextMenu = { getNew = function(_, parent) return setmetatable({ options = {} }, Menu) end }
function NEW_MENU() return setmetatable({ options = {} }, Menu) end
ISWorldObjectContextMenu = { setTest = function() MENU.tested = true return true end }
getText = function(k) return k end
function CLICK(x, y)
    return { setmetatable({ square = HARNESS.square(x, y, 0) }, getmetatable(HARNESS.addObject(x, y, 0))) }
end
'''


class MenuTests(Base):
    def setUp(self):
        super().setUp()
        self.run_lua(MENU_DOUBLES)
        self.h.load(self.srv, VIEW)

    def fill(self, x, y, test=False):
        return self.run_lua(f'local ctx = NEW_MENU() LivingKnox.RelationsView.fill(0, ctx, CLICK({x}, {y}), '
                            f'{"true" if test else "false"}) return ctx')

    def test_menu_offers_three_kinds_and_sends_the_choice(self):
        ctx = self.fill(104, 104)
        opts = list(ctx.options.values())
        self.assertEqual([o.name for o in opts], ['IGUI_LK_Aid_Menu'])
        sub = list(opts[0].sub.options.values())
        self.assertEqual([(o.name, o.a, o.b) for o in sub],
                         [(f'IGUI_LK_Aid_Menu_{k}', 'lk-1', k) for k in ('food', 'water', 'care')])
        # Choix « nourriture » : appel direct de l'autorité en solo.
        self.run_lua('local ctx = NEW_MENU() LivingKnox.RelationsView.fill(0, ctx, CLICK(104, 104), false) '
                     'local o = ctx.options[1].sub.options[1] o.fn(o.target, o.a, o.b)')
        self.assertEqual(len(self.inv_ids()), 1)
        self.assertEqual(self.aid_log()[0].split(':')[0], f'aid food given to {KEY_A}')

    def test_no_option_away_from_a_body_or_too_far(self):
        self.assertEqual(len(list(self.fill(108, 106).options.values())), 0)   # clic loin du corps
        self.run_lua('HARNESS.place(HARNESS.players.A, 110, 104, 0)')
        self.assertEqual(len(list(self.fill(104, 104).options.values())), 0)   # joueur trop loin

    def test_controller_probe_adds_nothing(self):
        ctx = self.fill(104, 104, test=True)
        self.assertEqual(len(list(ctx.options.values())), 0)
        self.assertTrue(self.ev('MENU.tested'))


class MultiplayerTests(Base):
    mode = 'mp'

    def test_client_command_gives_to_that_player_only(self):
        self.run_lua('local p = HARNESS.players.B HARNESS.place(p, 103, 105, 0)')
        self.h.load('A', VIEW)
        self.h.load('A', 'getText = function(k) return k end')
        sent, removed = self.ev('COUNT.addSent'), self.ev('COUNT.removeSent')
        self.assertTrue(self.h.eval('A', 'LivingKnox.RelationsView.send(getPlayer(), "lk-1", "food")'))
        self.h.pump()
        self.assertEqual(len(self.inv_ids('A')), 1)
        self.assertEqual(self.inv_ids('B'), [])
        self.assertEqual(self.ev('COUNT.addSent') - sent, 1)
        self.assertEqual(self.ev('COUNT.removeSent') - removed, 1)
        # B dans la même période : refus « again », rien pour lui.
        self.h.load('B', VIEW)
        self.h.eval('B', 'LivingKnox.RelationsView.send(getPlayer(), "lk-1", "care")')
        self.h.pump()
        self.assertEqual(self.inv_ids('B'), [])
        self.assertEqual(self.said()[-1][1], 'IGUI_LK_Aid_Refuse_again')
        # Rien sur les clients : module d'autorité absent.
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, R))

    def test_ground_gift_is_sent_to_clients(self):
        self.run_lua('CAPACITY = 0')
        out = self.ask('food')
        self.assertEqual(out.where, 'ground')
        self.assertEqual(self.ev('COUNT.groundSent'), 1)


class TranslationTests(unittest.TestCase):
    def test_every_line_and_menu_key_is_translated(self):
        tr = LUA / 'shared' / 'Translate'
        keys = {'IGUI_LK_Aid_Menu'} | {f'IGUI_LK_Aid_Menu_{k}' for k in ('food', 'water', 'care')} \
            | {f'IGUI_LK_Aid_Given_{k}' for k in ('food', 'water', 'care')} \
            | {f'IGUI_LK_Aid_Refuse_{r}' for r in ('attitude', 'short', 'again', 'away', 'stranger')}
        src = (LUA / RELATIONS).read_text(encoding='utf-8')
        self.assertIn('Relations.REASONS = { "attitude", "short", "again", "away", "stranger" }', src)
        for lang in ('EN', 'FR'):
            data = json.loads((tr / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for k in sorted(keys):
                with self.subTest(lang=lang, key=k):
                    self.assertIn(k, data)
                    data[k].encode('latin-1')   # police des bulles : Latin-1 seulement

    def test_sources_have_ascii_code_only(self):
        for path in (RELATIONS, VIEW):
            for n, line in enumerate((LUA / path).read_text(encoding='utf-8').splitlines(), 1):
                code = line.split('--', 1)[0]
                with self.subTest(path=path, line=n):
                    self.assertTrue(code.isascii(), line)
        self.assertIsNone(re.search(r'\bgoto\b|\bnext\(', (LUA / RELATIONS).read_text(encoding='utf-8')))


SUITE = 'aid given once from the stock, period and shortage respected'


class SuiteTests(StockBase):
    """La suite en jeu lk.aid passe dans le banc (joueur debout dans la maison de test)."""

    def run_suite(self, prep=''):
        self.h.load(self.srv, OFFSCREEN_DOUBLES)
        self.h.load(self.srv, AID_DOUBLES)
        self.h.load(self.srv, RELATIONS)
        if prep:
            self.run_lua(prep)
        self.run_lua(HOUSE)
        self.run_lua(KITCHEN)
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, 'shared/RST/suites/RST_LKAid.lua')
        self.run_lua('local p = HARNESS.players.A HARNESS.place(p, 103, 104, 0) PLAYER = p')
        self.assertTrue(self.ev('RST.start({ suite = "lk.aid", tags = "world" }, '
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
        self.assertEqual(self.ev('LivingKnox.Stock.SUPPLY.PER_MEMBER.medical'), 1)

    def test_suite_detects_a_double_gift(self):
        # Défaut injecté : l'objet donné reste dans la référence (retrait non noté) -> la suite échoue.
        _, results = self.run_suite('LivingKnox.Stock.takeItem = function(gid, pred) '
                                    'local found, item = LivingKnox.Stock.findItem(gid, pred) '
                                    'if found == nil then return nil, item end '
                                    'return { i = found.i, t = found.t, k = found.key }, instanceItem(found.t) end')
        self.assertEqual(results[SUITE][0], 'FAIL')


if __name__ == '__main__':
    unittest.main()
