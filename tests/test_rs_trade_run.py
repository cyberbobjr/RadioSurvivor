"""Passage réservé et rendez-vous du passeur (E13-T03) : RS_Trade.lua et RS_TradeRun.lua dans lupa, et le pont
(radio_bridge.py : passage du livre, prompt).

    python RadioSurvivor/tests/test_rs_trade_run.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) : RS_Trade, RS_TradeRun, RS_Actions, RS_Persona, RS_Codec,
RS_TradeValues, RS_OutsideNews, RadioSurvivor_Const ; doublures : GameTime (âge du monde), joueurs en ligne (serveur
MP), équipes (RS_Factions.idOf), repère sur la carte (RS_MapMarks.give), serveur radio (RS_RadioServer.frequency/air),
traducteur fidèle (table anglaise du mod, nil pour une clé inconnue), ClimateManager, Signal Smoke (module public du
mod requis), état privé RS_State en mémoire, journal admin. Couvre : nuit du rendez-vous (01:00 à 03:00,
au moins 6 h après, dans la semaine), une seule réservation par passage et par équipe (refus booked / run_over,
autre membre de la même équipe, passage suivant), contexte par équipe relu par le pont (lieu seulement pour l'équipe
qui a réservé), cordon tiré et monté par l'hélicoptère, annulations (patrouille, hélicoptère, orage, retard) annoncées
une fois sur la fréquence de la voix, retard ancien non annoncé, voix hors antenne, signal (lampe en main, fusée rouge
de Signal Smoke) d'un membre au ponton pendant la fenêtre, traductions EN/FR, fiche de Gus.
Ne prouve ni l'API Java réelle ni le comportement du LLM : suite en jeu rs.trade_run.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21'
LUA = MOD / 'media/lua'
RUN_LUA = LUA / 'server/RadioSurvivor/RS_TradeRun.lua'
TRADE_LUA = LUA / 'server/RadioSurvivor/RS_Trade.lua'
TRANSLATE = LUA / 'shared/Translate'
sys.path.insert(0, str(ROOT / 'bridge'))

import npc_protocol as npc  # noqa: E402
import persona_store  # noqa: E402
import radio_bridge as rb  # noqa: E402

EN = json.loads((TRANSLATE / 'EN/IG_UI.json').read_text(encoding='utf-8'))
FR = json.loads((TRANSLATE / 'FR/IG_UI.json').read_text(encoding='utf-8'))


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


STUBS = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
isClient = function() return false end
SERVER = true
isServer = function() return SERVER end
CLOCK = { hours = 0 }
getGameTime = function() return {
    getWorldAgeHours = function() return CLOCK.hours end,
    getYear = function() return 1993 end, getMonth = function() return 6 end, getDay = function() return 9 end,
    getHour = function() return 4 end, getMinutes = function() return 0 end } end
local r = 0
ZombRand = function(a, b) r = r + 1 if b then return a + (r % (b - a)) end return (r * 7) % a end
getTimestampMs = function() return 1000 end
STATE = { data = nil, blocked = false, dirty = false }
package.preload["RadioSurvivor/RS_State"] = function() return STATE end
ACTION_LOG = {}
package.preload["RadioSurvivor/RS_ActionLog"] = function() return {
    format = function(d, voice, caller, name) return name .. ":" .. tostring(d.reason) end,
    append = function(lines) for _, l in ipairs(lines) do ACTION_LOG[#ACTION_LOG + 1] = l end end } end
-- Équipes : champ team du joueur (doublure de RS_Factions.idOf) ; compte = name.
package.preload["RadioSurvivor/RS_Factions"] = function() return {
    idOf = function(p) return p.team end, keyOf = function(p) return p.name end } end
MARKS = {}
package.preload["RadioSurvivor/RS_MapMarks"] = function() return {
    give = function(player, cid, khz, place) MARKS[#MARKS + 1] = { who = player.name, place = place, khz = khz } end }
end
-- Serveur radio : la voix gus tient 160000 tant que ON_AIR.
ON_AIR = true
AIRED = {}
RS_RadioServer = {
    frequency = function(id) if id == "gus" and ON_AIR then return 160000 end return nil end,
    air = function(khz, lines) AIRED[#AIRED + 1] = { khz = khz, lines = lines } end,
}
STORM = false
getClimateManager = function() return { getIsThunderStorming = function() return STORM end } end
PLAYERS = {}
getOnlinePlayers = function() return { size = function() return #PLAYERS end, get = function(_, i) return PLAYERS[i + 1] end } end
getPlayer = function() return PLAYERS[1] end
function makePlayer(name, team, x, y)
    local p = { name = name, team = team, x = x or 0, y = y or 0, dead = false, hands = {} }
    p.getUsername = function(self) return self.name end
    p.getX = function(self) return self.x end
    p.getY = function(self) return self.y end
    p.isDead = function(self) return self.dead end
    p.getPrimaryHandItem = function(self) return self.hands[1] end
    p.getSecondaryHandItem = function(self) return self.hands[2] end
    PLAYERS[#PLAYERS + 1] = p
    return p
end
function lamp(on) return { isEmittingLight = function() return on end } end
HANDLERS = {}
Events = setmetatable({}, { __index = function(t, name)
    local e = { Add = function(f) HANDLERS[name] = f end }
    rawset(t, name, e)
    return e
end })
-- Mod requis Signal Smoke : un abonné.
SIGNAL = {}
package.preload["SignalSmoke/SignalSmoke"] = function() return {
    onSignal = function(f) SIGNAL[#SIGNAL + 1] = f return true end,
    COLORS = { red = { r = 1.0, g = 0.25, b = 0.2 }, green = { r = 0.3, g = 1.0, b = 0.3 } } } end
"""

TRANSLATOR = r'''
local texts = ...
getTextOrNull = function(key) return texts[key] end
'''

SHEET = {'id': 'gus', 'actions': ['say', 'propose_trade']}
PIER = (6041, 5217)


class RunHarness(unittest.TestCase):

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.rt.execute(STUBS)
        self.rt.execute(TRANSLATOR, self.rt.table_from(EN))
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        self.T = self.rt.eval('require("RadioSurvivor/RS_Trade")')
        self.Run = self.rt.eval('require("RadioSurvivor/RS_TradeRun")')
        self.Actions = self.rt.eval('require("RadioSurvivor/RS_Actions")')
        self.g.STATE.data = self.rt.table_from({'schema': 2})
        self.T.resetForTests()
        self.T.setCordon(1, 1.0)
        names = [e.n for e in lua_list(self.T.SUPPLY)]
        full = {n: 0 for n in names}
        full.update({'Battery': 10, 'Antibiotics': 4})
        self.T.drawStock = lambda seed, passage: self.rt.table_from(full)
        self.patrol_roll = self.T.patrolRoll
        self.T.patrolRoll = lambda passage: 99          # aucune patrouille, sauf test dédié
        self.make = self.g.makePlayer

    def t(self, value):
        if isinstance(value, dict):
            return self.rt.table_from({k: self.t(v) for k, v in value.items()})
        if isinstance(value, list):
            return self.rt.table_from([self.t(v) for v in value])
        return value

    def decide(self, player, items='Battery:2', caller=None):
        caller = caller or player.name
        ctx = self.t({'cid': None, 'day': '1993-07-10', 'khz': 160000})
        ctx.player = player
        out = self.Actions.decide(self.t(SHEET), caller, self.t([{'type': 'propose_trade', 'items': items}]), 1000, ctx)
        return lua_list(out)[0].reason

    def current_run(self):
        return self.T.lastRun()

    def aired(self):
        return [lua_list(a.lines) for a in lua_list(self.g.AIRED)]

    def logs(self, text):
        return [line for line in lua_list(self.g.LOGS) if text in line]

    def context(self, caller):
        hexed = self.T.field(self.t(SHEET), caller, None)
        return rb.trade_context({'trade': hexed}, FakeSheet())

    def booked(self, hours=4.0):
        """Kate (équipe fac-1) réserve à `hours` ; rend le passage."""
        self.g.CLOCK.hours = hours
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate), 'ok')
        return kate, self.current_run()


class FakeSheet:
    def __init__(self):
        self.id = 'gus'
        self.secrets = []
        self.actions = ['say', 'propose_trade']
        self.places = []


class RendezvousTests(RunHarness):

    def test_night_window_at_least_six_hours_later_inside_the_week(self):
        T = self.T
        self.assertEqual(T.rendezvous(0, 1), 18)                     # jour 1 07:00 -> jour 2 01:00
        for tenth in range(0, 1600):
            hours = tenth / 10
            passage = int(hours // 168) + 1
            start = T.rendezvous(hours, passage)
            if start is None:
                self.assertGreater(hours + 6 + 2, 168 * passage - 24, hours)
                continue
            self.assertEqual((start + 7) % 24, 1, hours)
            self.assertGreaterEqual(start, hours + 6 - 1e-9)
            self.assertLess(start, hours + 30)
            self.assertLessEqual(start + 2, 168 * passage)
        self.assertIsNone(T.rendezvous(160, 1))                      # dernier jour : plus de nuit possible
        self.assertEqual(T.rendezvous(150, 1), 162)

    def test_cordon_drawn_per_passage_and_reproducible(self):
        counts = {1.0: 0, 1.25: 0, 1.5: 0}
        for passage in range(1, 2001):
            c = self.T.drawCordon(424242, passage)
            self.assertEqual(c, self.T.drawCordon(424242, passage))
            counts[c] += 1
        self.assertTrue(1050 < counts[1.0] < 1350 and 450 < counts[1.25] < 750 and 120 < counts[1.5] < 280, counts)
        self.assertEqual(self.T.cordon(1), 1.0)                      # fixé par setCordon
        self.assertEqual(self.T.cordon(3), self.T.drawCordon(self.g.STATE.data.trade.seed, 3))


class BookingTests(RunHarness):

    def test_one_booking_per_passage_for_one_team(self):
        kate, run = self.booked(4.0)
        self.assertEqual((run.passage, run.team, run.state, run.start, run.voice, run.khz, run.caller),
                         (1, 'fac-1', 'booked', 18, 'gus', 160000, 'kate'))
        marks = lua_list(self.g.MARKS)
        self.assertEqual(len(marks), 1)
        self.assertEqual((marks[0].who, marks[0].place.x, marks[0].place.y, marks[0].place.label),
                         ('kate', 6041, 5217, EN['IGUI_RS_TradeRun_Pier']))
        self.assertTrue(self.logs('run 1 booked by team fac-1 (kate), meeting at world hour 18'))
        # Une autre équipe : refus, aucune offre ; même équipe, autre membre : l'offre du passage change de main.
        bob = self.make('bob', 'fac-2', 0, 0)
        self.assertEqual(self.decide(bob), 'booked')
        self.assertIsNone(self.T.offerOf('bob', None))
        ann = self.make('ann', 'fac-1', 0, 0)
        self.assertEqual(self.decide(ann, 'Battery:9'), 'ok')       # l'offre de kate ne compte plus comme prise
        self.assertEqual(self.T.offerOf('kate', None).state, 'replaced')
        run = self.current_run()
        self.assertEqual((run.caller, run.rev, run.start), ('ann', self.T.offerOf('ann', None).rev, 18))
        self.assertEqual(len(lua_list(self.g.MARKS)), 1, 'a second booking mark')
        self.assertIn('propose_trade:booked', lua_list(self.g.ACTION_LOG))
        # Passage suivant : libre de nouveau.
        self.g.CLOCK.hours = 170
        self.assertEqual(self.decide(bob), 'ok')
        self.assertEqual((self.current_run().passage, self.current_run().team), (2, 'fac-2'))

    def test_no_offer_once_the_run_is_over_or_too_late(self):
        kate, _ = self.booked(4.0)
        self.Run.cancel('storm')
        self.assertEqual(self.decide(kate), 'run_over')
        self.assertEqual(self.decide(self.make('bob', 'fac-2')), 'run_over')
        self.g.CLOCK.hours = 168 + 161                               # dernier jour du passage 2
        self.assertEqual(self.decide(kate), 'run_over')
        self.assertEqual(self.T.runStatus('fac-1')[0], 'over')
        # Appel direct sans équipe (bancs E13-T02) : aucune réservation.
        offer, why, booked = self.T.propose('carl', None, 'Battery:1', None)
        self.assertIsNotNone(offer)
        self.assertFalse(booked)

    def test_offer_closed_by_the_exchange_ends_the_run(self):
        kate, run = self.booked(4.0)
        self.assertTrue(self.T.close('kate', None, run.rev, 'done'))
        self.assertEqual(self.current_run().state, 'done')
        self.assertEqual(self.T.runStatus('fac-1')[0], 'over')

    def test_volatile_run_without_state(self):
        self.g.STATE.data = None
        self.g.STATE.dirty = False
        kate, run = self.booked(4.0)
        self.assertEqual(run.team, 'fac-1')
        self.assertFalse(self.g.STATE.dirty)


class ContextTests(RunHarness):

    def test_context_per_team_read_by_the_bridge(self):
        self.g.CLOCK.hours = 4.0
        self.make('kate', 'fac-1')
        self.make('bob', 'fac-2')
        ctx = self.context('kate')
        self.assertEqual(ctx['run'], {'status': 'free', 'from': 1, 'to': 3, 'days': 1, 'inHours': 14.0})
        prompt = rb.trade_prompt(ctx, '[Caller 1]')
        self.assertIn('not booked yet', prompt)
        self.assertIn('the coming night, between 01:00 and 03:00 in the morning', prompt)
        self.assertNotIn('Riverside', prompt)
        self.assertEqual(self.decide(PLAYERS(self, 0)), 'ok')
        ctx = self.context('kate')
        self.assertEqual(ctx['run']['status'], 'yours')
        self.assertEqual(ctx['run']['state'], 'booked')
        prompt = rb.trade_prompt(ctx, '[Caller 1]')
        for text in ('booked by the group of [Caller 1]', 'west end of Riverside', 'red flare or a lit lamp',
                     'nobody there by 03:00', 'marked the landing on their map'):
            self.assertIn(text, prompt)
        self.assertNotRegex(prompt, r'6041|5217|\d{3}\.\d|kHz|MHz')
        other = self.context('bob')
        self.assertEqual(other['run'], {'status': 'taken', 'from': 1, 'to': 3})
        prompt = rb.trade_prompt(other, '[Caller 2]')
        self.assertIn('already booked by another group', prompt)
        self.assertNotIn('Riverside', prompt)
        self.Run.cancel('patrol')
        self.assertEqual(self.context('bob')['run'], {'status': 'over', 'from': 1, 'to': 3, 'reason': 'patrol'})
        self.assertIn('over (a patrol boat on the river)', rb.trade_prompt(self.context('kate'), 'you'))

    def test_bridge_rejects_a_broken_run(self):
        good = {'status': 'yours', 'from': 1, 'to': 3, 'days': 1, 'inHours': 5, 'state': 'booked',
                'place': 'the old pier'}
        self.assertEqual(rb.trade_run(good)['place'], 'the old pier')
        for bad in (dict(good, status='mine'), dict(good, place='pier 6041'), dict(good, state='gone'),
                    dict(good, place=''), dict(good, **{'from': 30}), {k: v for k, v in good.items() if k != 'days'},
                    {'status': 'free', 'from': 1, 'to': 3}, None, 'yours'):
            self.assertIsNone(rb.trade_run(bad), bad)
        self.assertEqual(rb.trade_run({'status': 'over', 'from': 1, 'to': 3, 'reason': 'odd'})['reason'], 'cancelled')
        self.assertEqual(rb.trade_run_lines(None, 'you'), [])
        self.assertIn('right now', rb.trade_run_lines(dict(rb.trade_run(good), inHours=-0.5), 'you')[0])
        self.assertIn('in 2 days', rb.trade_run_lines(dict(rb.trade_run(good), days=2), 'you')[0])
        self.assertIn('booked', rb.TRADE_REFUSALS)
        self.assertIn('run_over', rb.TRADE_REFUSALS)


def PLAYERS(case, i):
    return case.g.PLAYERS[i + 1]


class RuleTests(RunHarness):

    def update(self, hours):
        self.g.CLOCK.hours = hours
        return self.Run.update()

    def test_storm_cancels_and_is_announced_once(self):
        kate, run = self.booked(4.0)
        self.g.STORM = True
        self.assertIsNone(self.update(16.9))                        # avant 00:00 : rien
        self.assertEqual(self.update(17.0), 'storm')
        self.assertEqual(self.current_run().state, 'cancelled')
        self.assertEqual(self.current_run().reason, 'storm')
        self.assertEqual(self.T.offerOf('kate', None).state, 'cancelled')
        self.assertEqual(self.aired(), [['<fzzt>', EN['IGUI_RS_TradeRun_Cancel_storm'], '<szzt>']])
        self.assertEqual(lua_list(self.g.AIRED)[0].khz, 160000)
        self.assertIsNone(self.update(17.5))
        self.assertEqual(len(self.aired()), 1)

    def test_patrol_drawn_by_cordon(self):
        kate, run = self.booked(4.0)
        self.T.patrolRoll = lambda passage: 4                       # < 5 % du cordon calme
        self.assertEqual(self.update(17.0), 'patrol')
        self.assertEqual(self.aired()[0][1], EN['IGUI_RS_TradeRun_Cancel_patrol'])

    def test_patrol_chance_follows_the_cordon(self):
        kate, run = self.booked(4.0)
        self.T.patrolRoll = lambda passage: 29
        self.assertIsNone(self.update(17.0))                         # calme : 29 >= 5
        self.T.setCordon(1, 1.5)
        self.assertEqual(self.update(17.5), 'patrol')                # cordon serré : 29 < 30

    def test_patrol_roll_is_reproducible(self):
        roll = self.patrol_roll
        rolls = [roll(p) for p in range(1, 400)]
        self.assertEqual(rolls, [roll(p) for p in range(1, 400)])
        self.assertTrue(all(0 <= x < 100 for x in rolls))
        self.assertGreater(len(set(rolls)), 60)

    def test_helicopter_raises_the_cordon_and_cancels_near_the_night(self):
        self.g.CLOCK.hours = 2.0
        self.Run.onWorldSound(100, 100, 0, 600, 600, None)          # autre son : rien
        self.Run.onWorldSound(100, 100, 1, 500, 500, None)
        self.assertEqual(self.T.cordon(1), 1.0)
        self.Run.onWorldSound(100, 100, 0, 500, 500, None)
        self.Run.onWorldSound(120, 100, 0, 500, 500, None)
        self.assertEqual(self.T.cordon(1), 1.25)                    # un cran, une fois par passage
        self.assertEqual(len(self.logs('helicopter heard in passage 1')), 1)
        kate, run = self.booked(4.0)
        self.assertIsNone(self.update(17.0))                         # entendu à 2 h, bien avant 22 h
        self.g.CLOCK.hours = 15.5                                    # 22:30
        self.Run.onWorldSound(100, 100, 0, 500, 500, None)
        self.assertEqual(self.update(17.0), 'helicopter')
        self.assertEqual(self.aired()[0][1], EN['IGUI_RS_TradeRun_Cancel_helicopter'])
        self.assertEqual(self.T.cordon(1), 1.25)

    def test_late_announced_unless_long_past(self):
        kate, run = self.booked(4.0)
        self.assertIsNone(self.update(19.9))
        self.assertEqual(self.update(20.0), 'late')
        self.assertEqual(self.aired()[0][1], EN['IGUI_RS_TradeRun_Cancel_late'])
        # Serveur arrêté pendant la nuit : retard constaté trop tard, rien à l'antenne.
        self.g.CLOCK.hours = 170
        self.make('bob', 'fac-2')
        self.assertEqual(self.decide(PLAYERS(self, 1)), 'ok')
        self.assertEqual(self.update(170 + 14 + 6), 'late')
        self.assertEqual(len(self.aired()), 1)
        self.assertEqual(self.current_run().state, 'cancelled')

    def test_voice_off_air_logged(self):
        kate, run = self.booked(4.0)
        self.g.ON_AIR = False
        self.g.STORM = True
        self.assertEqual(self.update(17.0), 'storm')
        self.assertEqual(self.aired(), [])
        self.assertTrue(self.logs("not aired: voice 'gus' is off the air"))

    def test_lamp_of_a_member_at_the_pier_during_the_window(self):
        kate, run = self.booked(4.0)
        stranger = self.make('zed', 'fac-9', *PIER)
        stranger.hands = self.t({1: self.g.lamp(True)})
        kate.x, kate.y = PIER[0] + 20, PIER[1]
        kate.hands = self.t({1: self.g.lamp(True)})
        self.assertIsNone(self.update(18.5))                         # trop loin
        kate.x = PIER[0] - 10
        kate.hands = self.t({2: self.g.lamp(False)})
        self.assertIsNone(self.update(18.5))                         # lampe éteinte
        kate.hands = self.t({2: self.g.lamp(True)})
        self.assertIsNone(self.update(17.5))                         # avant 01:00
        self.assertEqual(self.update(18.5), 'arrived')
        self.assertEqual((self.current_run().state, self.current_run().signal), ('arrived', 'lamp'))
        self.assertIsNone(self.update(20.5))                         # arrivée : plus de retard ni d'annonce
        self.assertEqual(self.aired(), [])

    def test_red_flare_of_signal_smoke(self):
        kate, run = self.booked(4.0)
        listeners = lua_list(self.g.SIGNAL)
        self.assertEqual(len(listeners), 1)
        fire = listeners[0]
        red = {'r': 1.0, 'g': 0.25, 'b': 0.2}
        event = lambda color, x=PIER[0] + 3, y=PIER[1]: self.t({'type': 'started', 'entry': {'x': x, 'y': y, 'z': 0,
                                                                                               'color': color}})
        self.g.CLOCK.hours = 18.5
        kate.x, kate.y = PIER
        fire(event(red, PIER[0] + 40))                               # loin du ponton
        fire(event({'r': 0.3, 'g': 1.0, 'b': 0.3}))                  # verte
        self.g.CLOCK.hours = 17.5
        fire(event(red))                                             # avant la fenêtre
        self.assertEqual(self.current_run().state, 'booked')
        self.g.CLOCK.hours = 18.5
        kate.x = PIER[0] + 30
        fire(event(red))                                             # personne de l'équipe au ponton
        self.assertEqual(self.current_run().state, 'booked')
        kate.x = PIER[0]
        fire(event(red))
        self.assertEqual((self.current_run().state, self.current_run().signal), ('arrived', 'flare'))

    def test_hooks_installed(self):
        same = self.rt.eval('function(a, b) return a == b end')
        self.assertTrue(same(self.T.onBooked, self.Run.onBooked))
        for name in ('EveryTenMinutes', 'OnWorldSound'):
            self.assertIsNotNone(self.g.HANDLERS[name], name)


class StaticTests(unittest.TestCase):

    def test_translations_and_fallbacks(self):
        source = RUN_LUA.read_text(encoding='utf-8')
        names = ['Pier'] + ['Cancel_' + r for r in ('patrol', 'helicopter', 'storm', 'late')]
        for name in names:
            key = 'IGUI_RS_TradeRun_' + name
            self.assertIn(key, EN)
            self.assertIn(key, FR)
            self.assertNotIn('%', EN[key] + FR[key])
            self.assertLessEqual(len(FR[key]), 140)
            self.assertIn(f'{name} = "{EN[key]}"', source)

    def test_ascii_kahlua_safe_code(self):
        for path in (RUN_LUA, TRADE_LUA):
            code = path.read_text(encoding='utf-8')
            body = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(body.isascii(), path.name)
            self.assertIsNone(re.search(r'\bnext\s*\(|\bgoto\b|coroutine|ModData\.|send(Server|Client)Command', body))
            self.assertIn('if isClient() then return end', code)
        self.assertNotIn('getText', re.sub(r'--[^\n]*', '', TRADE_LUA.read_text(encoding='utf-8')))

    def test_in_game_suite_compiles(self):
        suite = ROOT / 'dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RS_TradeRun.lua'
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        check = rt.eval('function(s) local f, e = loadstring(s, "=RS_TradeRun") return f ~= nil, e end')
        ok, err = check(suite.read_text(encoding='utf-8'))
        self.assertTrue(ok, err)
        self.assertIn('RST.suite("rs.trade_run", { tags = { "world", "server" } }', suite.read_text(encoding='utf-8'))

    def test_gus_sheet_trades(self):
        sheet = persona_store.load_file(MOD / 'personas/gus.txt')
        self.assertIn('propose_trade', sheet.actions)
        self.assertEqual(rb.offered_actions(sheet), ['propose_trade'])
        self.assertIn('trade book', sheet.prompt)
        self.assertNotIn('Never give a meeting place', sheet.prompt)


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
