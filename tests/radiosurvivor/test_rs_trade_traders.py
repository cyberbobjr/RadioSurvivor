"""Troc déclaré dans la fiche, un état par marchand (E20-T07, ADR D07) : RS_Trade, RS_TradeRun, RS_TradeExchange,
le registre des modes d'arrivée (RS_TradeArrivals) et le mode `boat`, avec de vraies fiches lues par RS_Persona.

    python RadioSurvivor/tests/radiosurvivor/test_rs_trade_traders.py

Doublures : celles de test_rs_trade_exchange.py (joueurs, cellule, sacs, objets, horloge du monde). Couvre : deux
marchands réservés la même semaine sans interférence (réservation, offre, stock, annulation, échange à leur propre
lieu), un faux mode d'arrivée inscrit par le banc sans toucher au moteur (signal, cause d'annulation, sons), joueur à
portée de vue = aucun échange, délai en heures de jeu hors de vue (remis à zéro par un joueur revenu), échange fait au
retour d'un joueur quand le lieu était déchargé, Gus au format (ponton, heures, cadence, mode boat).
Ne prouve ni l'API Java réelle ni le multijoueur : suite en jeu rs.trade_exchange (passage de Gus).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from test_rs_trade_exchange import ExchangeHarness  # noqa: E402
from test_rs_trade_run import EN, TraderProxy, lua_list, rb  # noqa: E402

GUS_PIER = (6041, 5217)
TESS_DOCK = (7000, 5300)

# E25-T01 : rendez-vous des marchands du banc, ajoutés aux lieux communs livrés (rules.places).
BENCH_PLACES = '''[place dock]
at=7000,5300,0
label=Old ferry dock
[place gate]
at=8000,8000,0
label=Farm gate on the county road
'''

TESS = '''format=1
id=tess
name=Tess Bench
frequency=161.0
actions=say,propose_trade
[trade]
landing=dock
arrival=boat
every_days=7
hours=01:00-03:00
delay_hours=3
item=Base.Antibiotics:2-6
item=Base.Coffee2:1-3
accept=Base.MoneyBundle
[prompt]
You are Tess, a bench trader.
'''

# Faux mode d'arrivée inscrit par le banc : un signal (lampe), une cause (brouillard), deux sons vanilla.
FAKE_MODE = r'''
FOG = false
local function fog(world) return FOG end
require("RadioSurvivor/RS_TradeArrivals").register("cart", {
    signals = { lamp = true },
    texts = { signal = "a lamp swung at the gate", arrived = "your cart is at the gate now",
        drop = "the payment goes in a bag left on the ground at the gate, never in a vehicle" },
    sounds = { approach = "VehicleHorn", leave = "VehicleDoorClose" },
    causes = { { name = "fog", text = "a thick fog on the road", fallback = "No cart tonight, fog on the road. Over.",
        check = fog } },
})
'''

CARL = '''format=1
id=carl
name=Carl Bench
frequency=162.0
actions=say,propose_trade
[trade]
landing=gate
arrival=cart
every_days=3
hours=22:00-01:00
item=Base.Battery:4-4
accept=Base.MoneyBundle
[prompt]
You are Carl, a bench trader.
'''


class TradersHarness(ExchangeHarness):
    EXTRA_PLACES = BENCH_PLACES

    def setUp(self):
        super().setUp()
        self.tess = self.add_voice(TESS, 'tess')
        self.Tess = TraderProxy(self.Trade, 'tess')

    def sounds(self):
        return [(s.name, s.x, s.y) for s in lua_list(self.g.SOUNDS)]

    def update(self, vid, hours):
        self.g.CLOCK.hours = hours
        return self.Ex.updateTrader(vid, hours)


class TwoTradersTests(TradersHarness):

    def test_two_traders_booked_the_same_week_do_not_interfere(self):
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 50, 50)
        bob = self.make('bob', 'fac-2', 60, 60)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.assertEqual(self.decide(bob, 'Antibiotics:2', voice='tess'), 'ok')       # autre marchand : libre
        gus, tess = self.T.lastRun(), self.Tess.lastRun()
        self.assertEqual((gus.team, gus.landing.x, gus.voice), ('fac-1', GUS_PIER[0], 'gus'))
        self.assertEqual((tess.team, tess.landing.x, tess.voice), ('fac-2', TESS_DOCK[0], 'tess'))
        self.assertEqual(self.decide(bob, 'Battery:1'), 'booked')                       # Gus pris par fac-1
        self.assertEqual(self.decide(kate, 'Antibiotics:1', voice='tess'), 'booked')    # Tess prise par fac-2
        self.assertEqual(self.T.offerOf('kate', None).lines[1].n, 'Antibiotics')
        self.assertIsNone(self.Tess.offerOf('kate', None))
        self.assertEqual(self.T.available('x', None).Antibiotics, 2)                    # stock propre à chacun
        self.assertNotIn('Battery', [k for k in self.Tess.available('x', None).keys()])
        # La même équipe peut aussi réserver deux marchands la même semaine.
        self.Trade.cancelRun('tess', 'patrol')
        self.assertEqual((self.T.lastRun().state, self.Tess.lastRun().state), ('booked', 'cancelled'))
        # Arrivées et échanges à leur propre lieu.
        self.g.CLOCK.hours = 170.0
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.assertEqual(self.decide(kate, 'Antibiotics:2', voice='tess'), 'ok')
        start_gus, start_tess = self.T.lastRun().start, self.Tess.lastRun().start
        self.assertEqual(start_gus, start_tess)
        self.g.CLOCK.hours = start_gus + 0.5
        self.assertTrue(self.T.arrive('lamp'))
        self.assertTrue(self.Tess.arrive('lamp'))
        gus_bag = self.g.dropBag(GUS_PIER[0], GUS_PIER[1], self.t([self.it('MoneyBundle') for _ in range(2)]))
        tess_bag = self.g.dropBag(TESS_DOCK[0], TESS_DOCK[1], self.t([self.it('MoneyBundle') for _ in range(2)]))
        kate.x, kate.y, bob.x, bob.y = 20000, 20000, 20000, 20000
        now = start_gus + 0.5
        self.assertIsNone(self.update('gus', now))
        self.assertIsNone(self.update('tess', now))
        self.assertEqual(self.update('gus', now + 1), 'done')                           # délai de Gus : 1 h
        self.assertIsNone(self.update('tess', now + 1))                                 # délai de Tess : 3 h
        self.assertEqual(self.update('tess', now + 3), 'done')
        self.assertEqual(self.bag_items(gus_bag), ['Base.Antibiotics', 'Base.Antibiotics'])
        self.assertEqual(self.bag_items(tess_bag), ['Base.Antibiotics', 'Base.Antibiotics'])
        self.assertNotEqual(self.T.lastRun().rev, self.Tess.lastRun().rev)

    def test_state_is_kept_per_trader(self):
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        self.assertEqual(self.decide(kate, 'Antibiotics:2', voice='tess'), 'ok')
        traders = self.g.STATE.data.trade.traders
        self.assertEqual(sorted(traders.keys()), ['gus', 'tess'])
        self.assertNotEqual(traders.gus.seed, None)
        self.assertEqual(traders.gus.run.voice, 'gus')
        self.assertEqual(traders.tess.run.voice, 'tess')


class FakeArrivalModeTests(TradersHarness):

    def setUp(self):
        super().setUp()
        self.rt.execute(FAKE_MODE)
        self.carl = self.add_voice(CARL, 'carl')
        self.Carl = TraderProxy(self.Trade, 'carl')

    def test_fake_mode_registered_by_the_test_works_without_engine_change(self):
        self.assertEqual((self.carl.trade.arrival, self.carl.trade.everyDays, self.carl.trade['from'],
                          self.carl.trade.hours), ('cart', 3, 22, 3))
        self.g.CLOCK.hours = 4.0                                                        # jour 1, 11:00
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Battery:2', voice='carl', wants='MoneyBundle:1'), 'ok')
        run = self.Carl.lastRun()
        self.assertEqual(run.start, 15.0)                                               # jour 1, 22:00
        self.assertEqual((run.landing.x, run.landing.y), (8000, 8000))
        hexed = self.Trade.field(self.carl, 'kate', None)
        ctx = rb.trade_context({'trade': hexed})
        prompt = rb.trade_prompt(ctx, '[Caller 1]')
        self.assertIn('a lamp swung at the gate', prompt)
        self.assertIn('Farm gate on the county road', prompt)
        self.assertNotIn('pier', prompt.lower())
        # Fusée : signal que ce mode n'attend pas ; lampe : arrivée, son d'approche au lieu.
        kate.x, kate.y = 8000, 8001
        self.g.CLOCK.hours = 15.5
        fire = lua_list(self.g.SIGNAL)[0]
        fire(self.t({'type': 'started', 'entry': {'x': 8000, 'y': 8000, 'z': 0,
                                                  'color': {'r': 1.0, 'g': 0.25, 'b': 0.2}}}))
        self.assertEqual(self.Carl.lastRun().state, 'booked')
        kate.hands = self.t({1: self.g.lamp(True)})
        self.assertEqual(self.Run.updateTrader('carl', 15.5), 'arrived')
        self.assertEqual(self.sounds(), [('VehicleHorn', 8000, 8000)])
        # Échange hors de vue après le délai par défaut, son de départ.
        bag = self.g.dropBag(8000, 8000, self.t([self.it('MoneyBundle') for _ in range(2)]))
        kate.x = 9000
        self.assertIsNone(self.update('carl', 15.6))
        self.assertEqual(self.update('carl', 15.6 + self.Ex.DELAY_HOURS), 'done')
        self.assertEqual(self.bag_items(bag), ['Base.MoneyBundle', 'Base.Battery', 'Base.Battery'])  # liste prise exactement
        self.assertEqual(self.sounds()[-1], ('VehicleDoorClose', 8000, 8000))

    def test_cause_of_the_fake_mode_cancels_and_is_aired(self):
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', 50, 50)
        self.assertEqual(self.decide(kate, 'Battery:1', voice='carl'), 'ok')
        self.g.FOG = True
        self.assertIsNone(self.Run.updateTrader('carl', 11.9))                         # avant WARN_HOURS
        self.g.STORM = True                                                             # cause de la barque : ignorée
        self.g.FOG = False
        self.assertIsNone(self.Run.updateTrader('carl', 12.0))
        self.g.FOG = True
        self.assertEqual(self.Run.updateTrader('carl', 12.1), 'fog')
        run = self.Carl.lastRun()
        self.assertEqual((run.state, run.reason), ('cancelled', 'fog'))
        self.assertEqual(self.aired()[-1][1], 'No cart tonight, fog on the road. Over.')
        ctx = rb.trade_context({'trade': self.Trade.field(self.carl, 'kate', None)})
        self.assertIn('a thick fog on the road', rb.trade_prompt(ctx, 'you'))
        self.assertEqual(self.T.lastRun(), None)                                        # Gus intact

    def test_unknown_or_broken_mode_refused(self):
        bad = CARL.replace('arrival=cart', 'arrival=zeppelin')
        result = self.Persona.parseLines(self.rt.table_from(bad.splitlines()), 'carl', self.rules)
        self.assertEqual(result[1], "line 8: unknown arrival 'zeppelin' (expected boat, cart)")
        registered = self.rt.eval('require("RadioSurvivor/RS_TradeArrivals").register("half", { signals = {} })')
        self.assertFalse(registered)


class OutOfSightTests(TradersHarness):

    def arrived_with_bag(self):
        kate = self.arrived('Antibiotics:2', hours=18.5)
        bag = self.g.dropBag(GUS_PIER[0], GUS_PIER[1], self.t([self.it('MoneyBundle') for _ in range(2)]))
        return kate, bag

    def test_player_in_view_means_no_exchange(self):
        kate, bag = self.arrived_with_bag()
        kate.x = GUS_PIER[0] + 90                                                        # 90 cases : à portée de vue
        for hours in (18.6, 19.6, 22.0, 26.0):
            self.assertIsNone(self.update('gus', hours))
        self.assertEqual(self.T.lastRun().state, 'arrived')
        self.assertEqual(self.bag_items(bag), ['Base.MoneyBundle', 'Base.MoneyBundle'])
        bob = self.make('bob', 'fac-9', GUS_PIER[0] - 50, GUS_PIER[1] + 99)            # un autre joueur, autre équipe
        kate.x = GUS_PIER[0] + 101
        self.assertIsNone(self.update('gus', 27.0))
        self.assertIsNone(self.update('gus', 29.0))
        bob.y = GUS_PIER[1] + 101
        self.assertIsNone(self.update('gus', 29.5))
        self.assertEqual(self.update('gus', 30.5), 'done')

    def test_delay_in_game_hours_reset_by_a_player_back_in_view(self):
        kate, bag = self.arrived_with_bag()
        delay = self.Ex.DELAY_HOURS
        kate.x = GUS_PIER[0] + 150
        self.assertIsNone(self.update('gus', 18.6))                                     # attente commencée
        self.assertIsNone(self.update('gus', 18.6 + delay - 0.1))
        kate.x = GUS_PIER[0] + 20                                                        # revenue voir
        self.assertIsNone(self.update('gus', 18.6 + delay))
        kate.x = GUS_PIER[0] + 150
        self.assertIsNone(self.update('gus', 19.8))                                     # attente reprise de zéro
        self.assertIsNone(self.update('gus', 19.8 + delay - 0.1))
        self.assertEqual(self.update('gus', 19.8 + delay), 'done')

    def test_sheet_delay_overrides_the_default(self):
        self.assertEqual(self.tess.trade.delayHours, 3)
        self.assertIsNone(self.gus.trade.delayHours)

    def test_unloaded_landing_exchanged_when_a_player_comes_back(self):
        kate, bag = self.arrived_with_bag()
        kate.x = GUS_PIER[0] + 300
        self.g.LOADED = False
        self.assertIsNone(self.update('gus', 18.6))
        self.assertIsNone(self.update('gus', 40.0))                                     # dû, mais lieu déchargé
        self.assertEqual(self.T.lastRun().state, 'arrived')
        self.g.LOADED = True
        kate.x = GUS_PIER[0] + 95                                                        # revient : le lieu se charge
        self.assertEqual(self.update('gus', 40.1), 'done')
        self.assertEqual(self.bag_items(bag), ['Base.Antibiotics', 'Base.Antibiotics'])

    def test_trader_leaves_when_never_left_alone(self):
        kate, bag = self.arrived_with_bag()
        kate.x = GUS_PIER[0] + 5
        self.assertIsNone(self.update('gus', 18.5 + self.Ex.WAIT_HOURS - 0.1))
        self.assertEqual(self.update('gus', 18.5 + self.Ex.WAIT_HOURS), 'watched')
        self.assertEqual(self.sounds()[-1][0], 'GeneratorStarting')


class GusSheetTests(TradersHarness):

    def test_gus_moved_to_the_format(self):
        trade = self.gus.trade
        self.assertEqual((trade.arrival, trade.everyDays, trade['from'], trade.hours), ('boat', 7, 1, 2))
        landing = lua_list(trade.landings)
        self.assertEqual([(p.id, p.x, p.y, p.z) for p in landing], [('riverside_pier', 6041, 5217, 0)])
        self.assertEqual((trade.marginMin, trade.marginMax), (0.1, 0.5))
        self.assertEqual(len(lua_list(trade['items'])), 32)

    def test_arrival_and_departure_sounds_of_the_boat(self):
        self.g.CLOCK.hours = 4.0
        kate = self.make('kate', 'fac-1', *GUS_PIER)
        self.assertEqual(self.decide(kate, 'Antibiotics:2'), 'ok')
        kate.hands = self.t({1: self.g.lamp(True)})
        self.g.CLOCK.hours = 18.5
        self.assertEqual(self.Run.updateTrader('gus', 18.5), 'arrived')
        self.assertEqual(self.sounds(), [('GeneratorStopping', GUS_PIER[0], GUS_PIER[1])])
        self.g.dropBag(GUS_PIER[0], GUS_PIER[1], self.t([self.it('MoneyBundle') for _ in range(2)]))
        kate.x = GUS_PIER[0] + 200
        self.assertIsNone(self.update('gus', 18.6))
        self.assertEqual(self.update('gus', 18.6 + self.Ex.DELAY_HOURS), 'done')
        self.assertEqual(self.sounds()[-1], ('GeneratorStarting', GUS_PIER[0], GUS_PIER[1]))


SOUND_STUBS = r"""
isClient = function() return CLIENT end
isServer = function() return SERVER end
PLAYED, SENT_CMDS = {}, {}
getWorld = function() return { getFreeEmitter = function(_, x, y, z)
    return { playSoundImpl = function(_, name, loop, obj) PLAYED[#PLAYED + 1] = { name = name, x = x, y = y, z = z,
        loop = loop, obj = obj } return 1 end } end } end
sendServerCommand = function(p, module, command, args) SENT_CMDS[#SENT_CMDS + 1] = { who = p.name, module = module,
    command = command, args = args } end
SUBSCRIBED = nil
Events = { OnServerCommand = { Add = function(f) SUBSCRIBED = f end } }
"""


class TradeSoundTests(unittest.TestCase):
    """RS_TradeSound : le serveur MP envoie le son aux joueurs proches du lieu, le solo le joue lui-même, le client le
    joue sur un émetteur libre (surcharge (nom, false, nil)) et ignore une commande mal formée."""

    def runtime(self, client: bool, server: bool):
        from test_rs_trade_run import CORE_LUA, LUA, STUBS
        import lupa.lua51 as lupa
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        rt.execute(STUBS)
        g = rt.globals()
        g.CLIENT, g.SERVER = client, server
        rt.execute(SOUND_STUBS)
        paths = ';'.join(f'{(root / side).as_posix()}/?.lua' for root in (CORE_LUA, LUA) for side in ('shared', 'server'))
        rt.execute(f'package.path = [[{paths};]] .. package.path')
        return rt, g, rt.eval('require("RadioSurvivor/RS_TradeSound")')

    def test_server_sends_to_players_near_the_landing(self):
        rt, g, sound = self.runtime(client=False, server=True)
        g.makePlayer('near', 'fac-1', 6041 + 100, 5217 - 50)
        g.makePlayer('far', 'fac-1', 6041 + 101, 5217)
        self.assertTrue(sound.playAt('GeneratorStopping', rt.table_from({'x': 6041, 'y': 5217, 'z': 0})))
        sent = lua_list(g.SENT_CMDS)
        self.assertEqual([(c.who, c.command, c.args.s, c.args.x) for c in sent],
                         [('near', 'trade_sound', 'GeneratorStopping', 6041)])
        self.assertEqual(lua_list(g.PLAYED), [])
        self.assertIsNone(g.SUBSCRIBED)                                   # le serveur n'écoute pas

    def test_solo_plays_locally_and_client_validates(self):
        rt, g, sound = self.runtime(client=False, server=False)
        sound.playAt('GeneratorStarting', rt.table_from({'x': 1, 'y': 2, 'z': 0}))
        played = lua_list(g.PLAYED)
        self.assertEqual([(p.name, p.x, p.y, p.loop, p.obj) for p in played], [('GeneratorStarting', 1, 2, False, None)])
        rt, g, sound = self.runtime(client=True, server=False)
        handler = g.SUBSCRIBED
        self.assertIsNotNone(handler)
        module = rt.eval('require("RadioSurvivor/RadioSurvivor_Const")').MODULE
        handler(module, 'trade_sound', rt.table_from({'s': 'GeneratorStopping', 'x': 5, 'y': 6, 'z': 0}))
        handler(module, 'trade_sound', rt.table_from({'s': 'bad name;', 'x': 5, 'y': 6}))
        handler(module, 'other', rt.table_from({'s': 'GeneratorStopping', 'x': 5, 'y': 6}))
        handler('OtherMod', 'trade_sound', rt.table_from({'s': 'GeneratorStopping', 'x': 5, 'y': 6}))
        self.assertEqual([(p.name, p.x, p.y) for p in lua_list(g.PLAYED)], [('GeneratorStopping', 5, 6)])


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
