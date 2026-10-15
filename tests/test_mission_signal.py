"""Gabarit « signaler » (E11-T07, RS_MissionSignal.lua) sur le banc du carnet : vrai Lua serveur et client, pont
absent, mod requis Signal Smoke (installation cassée : erreur au journal, aucune offre).

Doublures seulement (aucune API Java prouvée ici) : le module public 'SignalSmoke/SignalSmoke' est la doublure de
tests/signalsmoke_double.py (installée par test_protocol.Game), fidèle à son API documentée (Workshop/SignalSmoke,
SignalSmoke.lua : COLORS, onSignal, removeSignalListener, start, stop ; événement « started » avec entry { x, y, z,
color { r, g, b }, kind, source, owner } et player / username, abonnés appelés sous pcall au moment de start) ;
l'heure du jeu est HOUR de test_protocol (GameTime:getHour).
python RadioSurvivor/tests/test_mission_signal.py
"""
from __future__ import annotations

import tempfile
import unittest
import unittest.mock
from pathlib import Path

from test_carnet import (MAP_DOUBLE, NOTEBOOK_UI, SCOUT_GRID, TESTS_SHARED, ReportCases, Simulation, convert,
                         report_turn)
from test_protocol import lua_list
import npc_protocol as protocol

class SignalMissionTests(unittest.TestCase):
    """Module de Signal Smoke cassé : erreur au journal, aucune offre. Sinon : couleur, heure et cercle tirés par le serveur, signal
    reconnu par l'événement du mod (participant, couleur, cercle, fenêtre horaire), réussite par le moteur commun."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-signal-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def sim(self, name):
        sim = Simulation(self.path / name)
        sim.add_client('alice'); sim.add_client('bob')
        sim.server.rt.execute(SCOUT_GRID)
        sim.server.g.scoutHouse(5001, 20, 12, 8, 8)    # too close to the requester
        sim.server.g.scoutHouse(5002, 100, 10, 10, 10)  # reachable
        signal = sim.server.rt.eval("require('RadioSurvivor/RS_MissionSignal')")
        signal.resetForTests()
        signal.install()
        sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        record = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')").npc(2001)
        return sim, npc, record, signal

    def catalog(self, sim, npc, record):
        return convert(sim.server.g.RS_CarnetServer.offerCatalogFor(npc, record))

    def active(self, name, bob=False):
        sim, npc, record, signal = self.sim(name)
        self.assertIn('signal_v1', self.catalog(sim, npc, record))
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        m = missions.create(sim.state(), npc, sim.character('alice'), 'signal_v1')
        sim.request_mission('alice', 'accept')
        self.assertEqual(m.state, 'active')
        if bob:
            char = sim.character('bob')
            m.invited[char] = True
            sim.state().characters[char].knownMissions[m.id] = True
            sim.request_mission('bob', 'accept')
        sim.server.g.HOUR = m.hour
        return sim, npc, m, missions

    def light(self, sim, who, color, x=105, y=15, **extra):
        g = sim.server.g
        opts = {'x': x, 'y': y, 'z': 0, 'color': color, 'kind': 'smoke', 'source': 'grenade'}
        if who:
            opts['player'] = g.PLAYERS[who]
        opts.update(extra)
        return g.SS_FAKE.start(sim.server.rt.table_from(opts))

    def row(self, sim, name):
        rows = [convert(r) for r in lua_list(sim.clients[name].g.RS_CarnetClient.snapshot.missions)]
        [row] = [r for r in rows if r['template'] == 'signal']
        return row

    def test_broken_module_of_the_required_mod_logs_an_error_and_offers_nothing(self):
        sim, npc, record, signal = self.sim('broken')
        sim.server.rt.execute("package.loaded['SignalSmoke/SignalSmoke'] = {COLORS = {}}")
        signal.resetForTests()
        sim.server.rt.execute("LOGGED = {}; print = function(s) LOGGED[#LOGGED + 1] = tostring(s) end")
        self.assertIsNone(signal.library())
        self.assertIn('[RadioSurvivor] ERROR signal: required mod batman_SignalSmoke is broken: module '
                      'SignalSmoke/SignalSmoke has no onSignal or COLORS (template signal disabled)',
                      list(lua_list(sim.server.g.LOGGED)))
        self.assertFalse(signal.install())
        catalog = self.catalog(sim, npc, record)
        self.assertNotIn('signal_v1', catalog)
        self.assertIn('scout_v1', catalog)

    def test_with_signal_smoke_the_offer_names_place_colour_and_hour(self):
        sim, npc, record, signal = self.sim('offer')
        g = sim.server.g
        self.assertIsNotNone(signal.library())
        self.assertEqual(len(list(lua_list(g.SS_LISTENERS))), 1, 'listener not subscribed once')
        self.assertTrue(signal.install())
        self.assertEqual(len(list(lua_list(g.SS_LISTENERS))), 1, 'listener subscribed twice')
        catalog = self.catalog(sim, npc, record)
        self.assertEqual(sorted(catalog), ['first_aid_v1', 'scout_v1', 'signal_v1'])
        offer = catalog['signal_v1']
        self.assertEqual(set(offer), {'kind', 'place', 'clues', 'color', 'hour', 'windowHours', 'report', 'durationMs',
                                      'rewardType', 'rewardCount'})
        self.assertEqual((offer['kind'], offer['place'], offer['report'], offer['windowHours']),
                         ('signal', 'house', 'in_person', 2))
        self.assertIn(offer['color'], ('green', 'red', 'yellow', 'purple'))
        self.assertIn(offer['hour'], (23, 0, 1), 'hour not 2 to 4 game hours after 21:00')
        clues = [offer['clues'][i] for i in sorted(offer['clues'])]
        self.assertFalse(any(ch.isdigit() for line in clues for ch in line), 'a clue carries a number')
        self.assertEqual(self.catalog(sim, npc, record)['signal_v1'], offer, 'the kept place changed')
        # An untyped donor is refused; declared radio voices may offer this template.
        c = sim.server.rt.eval("require('RadioSurvivor/RS_Config').Missions.signal")
        donor = sim.server.rt.table_from({'id': 'voice:walt:c1', 'missionCount': 0})
        self.assertIsNone(signal.offer(c, donor, None, g.PLAYERS.alice))
        self.assertTrue(sim.server.rt.eval("require('RadioSurvivor/RS_MissionVoice')").TEMPLATES['signal'])
        # Window across midnight.
        self.assertEqual([signal.inWindow(23, 2, h) for h in (22, 23, 0, 1)], [False, True, True, False])

    def test_mission_circle_and_no_coordinate_to_the_bridge(self):
        sim, npc, m, missions = self.active('create')
        self.assertEqual((m.id, m.template, m.offer, m.place), (npc.id + '-signal1', 'signal', 'signal_v1', 'house'))
        self.assertEqual(convert(m.mapZone), {'x': 105, 'y': 15, 'r': 20})
        context = convert(missions.context(m))
        self.assertEqual((context['kind'], context['color'], context['hour'], context['windowHours'], context['lit']),
                         ('signal', m.color, m.hour, 2, False))
        for key in ('mapZone', 'siteKey', 'x', 'y'):
            self.assertNotIn(key, context)
        row = self.row(sim, 'alice')
        self.assertEqual((row['color'], row['hour'], row['lit'], row['mapZone']),
                         (m.color, m.hour, False, {'x': 105, 'y': 15, 'r': 20}))
        self.assertNotIn('siteKey', row)
        [bandage] = sim.items('alice', 'Base.Bandage')
        sim.request_mission('alice', 'prepare_delivery', items=[bandage])
        self.assertIsNone(sim.server.g.RS_CarnetServer.quotes[sim.character('alice')])

    def test_signals_that_do_not_count(self):
        sim, npc, m, missions = self.active('ignored')
        g = sim.server.g
        other = 'red' if m.color != 'red' else 'green'
        self.light(sim, 'alice', other)                          # wrong colour
        self.light(sim, 'alice', m.color, x=130)                 # outside the circle (25 tiles from its centre)
        self.light(sim, 'bob', m.color)                          # not a participant
        self.light(sim, None, m.color)                           # nobody at the origin (script)
        self.light(sim, 'alice', m.color, eventType='stopped')   # not a start
        g.HOUR = (m.hour + 2) % 24
        self.light(sim, 'alice', m.color)                        # past the window
        g.HOUR = (m.hour + 23) % 24
        self.light(sim, 'alice', m.color)                        # before the window
        self.assertEqual((m.state, m.lit), ('active', False))
        self.assertEqual(len(list(lua_list(g.SS_STARTED))), 7)

    def test_right_signal_then_report_succeeds_and_is_saved(self):
        sim, npc, m, missions = self.active('success', bob=True)
        g = sim.server.g
        g.HOUR = (m.hour + 1) % 24
        self.light(sim, 'bob', m.color, x=118, y=28, kind='flare', source='flare')
        # E11-T13: the signal seen meets the objective; the mission waits for its report.
        self.assertEqual((m.state, m.lit, m.litBy), ('active', True, 'bob Doe'))
        row = self.row(sim, 'alice')
        self.assertEqual((row['state'], row['toReport']), ('active', True))
        revision = m.revision
        self.light(sim, 'alice', m.color)
        self.assertEqual(m.revision, revision, 'a second signal was judged')
        report_turn(sim, 'bob', 'Your signal is lit.', 'report_done')
        self.assertEqual(m.state, 'success')
        char = sim.character('bob')
        outcome = sim.state().outcomes[m.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        self.assertIsNone(sim.state().npcs[m.npc].mission)
        self.assertEqual(sim.state().missions[m.id].state, 'success')
        row = self.row(sim, 'alice')
        self.assertEqual((row['state'], row['lit'], row['litBy']), ('success', True, 'bob Doe'))
        self.assertNotIn('mapZone', row)
        # A later signal changes nothing.
        revision = m.revision
        self.light(sim, 'alice', m.color)
        self.assertEqual(m.revision, revision)
        # Saved: a restarted server reads the closed mission back.
        g.fire('OnSave')
        restart = Simulation(self.path / 'success', sim.clock, saved_players=sim.saved())
        old = restart.mission()
        self.assertEqual((old.template, old.state, old.lit, old.color), ('signal', 'success', True, m.color))

    def test_reset_does_not_subscribe_the_listener_twice(self):
        # E11-T14: the in-game suites call Signal.resetForTests in a running session; the next installs must not
        # subscribe the listener once more to the same module (this double does not deduplicate, unlike the real one).
        sim, npc, m, missions = self.active('once')
        g, rt = sim.server.g, sim.server.rt
        self.assertEqual(len(list(lua_list(g.SS_LISTENERS))), 1)
        rt.execute("function SS_FAKE.onSignal(fn) SS_LISTENERS[#SS_LISTENERS + 1] = fn; return true end")
        signal = rt.eval("require('RadioSurvivor/RS_MissionSignal')")
        for _ in range(2):
            signal.resetForTests()
            self.assertTrue(signal.install())
            self.assertTrue(signal.install())
        self.assertEqual(len(list(lua_list(g.SS_LISTENERS))), 1, 'listener subscribed again after a reset')
        rt.execute("""
            local Signal = require('RadioSurvivor/RS_MissionSignal')
            local count = Signal.count
            SIGNAL_COUNTED = 0
            Signal.count = function(...) SIGNAL_COUNTED = SIGNAL_COUNTED + 1; return count(...) end
        """)
        g.HOUR = (m.hour + 1) % 24
        self.light(sim, 'alice', m.color)
        self.assertEqual(g.SIGNAL_COUNTED, 1, 'one signal judged more than once')
        self.assertEqual((m.state, m.lit, m.litBy), ('active', True, 'alice Doe'))

    def test_player_found_by_account_when_the_event_has_no_player(self):
        sim, npc, m, missions = self.active('account')
        self.light(sim, None, m.color, username='alice')
        self.assertEqual((m.state, m.lit, m.litBy), ('active', True, 'alice Doe'))

    def test_expiry_closes_the_mission(self):
        sim, npc, m, missions = self.active('expiry')
        sim.clock.offset += 7200001; sim.tick()
        self.assertEqual(m.state, 'failed')
        self.light(sim, 'alice', m.color)
        self.assertEqual((m.state, m.lit), ('failed', False))

    def test_notebook_page_and_area_label(self):
        sim, npc, m, missions = self.active('notebook')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load('client/RS_Carnet_Client.lua')
        maps = c.rt.eval("require('RadioSurvivor/RS_MapActions')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        texts = [convert(s)['text'] for s in lua_list(c.rt.eval('mapSymbols()')) if convert(s)['kind'] == 'text']
        self.assertEqual(texts, ['IGUI_RS_MapZoneSignal|Real Bandit'])
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        label = c.rt.eval('RS_CarnetClient.window.list.items[1].text')
        self.assertTrue(label.startswith('IGUI_RS_Signal - '), label)
        end = (m.hour + 2) % 24
        for key in ('IGUI_RS_ScoutPlace', 'IGUI_RS_ScoutClues', 'IGUI_RS_SignalMapZone',
                    'IGUI_RS_SignalColor|IGUI_RS_SignalColor_' + m.color, f'IGUI_RS_SignalHour|{m.hour}|{end}',
                    'IGUI_RS_SignalNotLit', 'IGUI_RS_SignalRule', 'IGUI_RS_SignalReport'):
            self.assertIn(key, window.detail.text)
        for key in ('IGUI_RS_Progress', 'IGUI_RS_ScoutReport', 'IGUI_RS_NoRefund'):
            self.assertNotIn(key, window.detail.text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a signal mission')

    def test_offline_bridge_tells_the_offer(self):
        req = {'kind': 'npc_talk', 'language': 'EN', 'offers': {'signal_v1': {
            'kind': 'signal', 'place': 'house', 'clues': ['The place is a house.'], 'color': 'green', 'hour': 23,
            'windowHours': 2, 'report': 'none', 'durationMs': 7200000, 'rewardType': 'Base.Bullets9mm',
            'rewardCount': 20}}, 'context': {}, 'character': 'c1', 'text': 'Work?', 'id': 'r1'}
        with unittest.mock.patch.object(protocol, 'bounded_reply', lambda r, reply: reply):
            reply = protocol.offline(req, intent='')
            self.assertEqual((reply['intent'], reply['offer']), ('offer', 'signal_v1'))
            self.assertIn('green signal', reply['text'])
            self.assertIn('between 23:00 and 1:00', reply['text'])
            req['language'] = 'FR'
            self.assertIn('signal vert', protocol.offline(req, intent='')['text'])

    def test_in_game_suite_on_the_simulated_server(self):
        """rs.mission.signal (dev mod) run by the real RST engine on the server machine, with the Signal Smoke double
        above in place of the real mod."""
        sim, npc, record, signal = self.sim('suite')
        shared = (TESTS_SHARED.as_posix() + '/?.lua')
        sim.server.rt.execute(f'package.path = [[{shared};]] .. package.path')
        sim.server.rt.execute("""
            local grid = getWorld():getMetaGrid()
            getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
                getWorld = function() return 'rstest-signal' end, getMetaGrid = function() return grid end} end
            require 'RST/RST'
        """)
        sim.server.rt.execute((TESTS_SHARED / 'RST' / 'suites' / 'RS_MissionSignal.lua').read_text(encoding='utf-8'))
        alice = sim.server.g.PLAYERS.alice
        self.assertTrue(sim.server.rt.eval('function(p) return RST.start("rs.mission.signal", '
                                           '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(100):
            if not sim.server.rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        self.assertEqual(results, {'a signal of the asked colour lit by the participant inside the circle succeeds, '
                                   'other signals do not': ('PASS', None)})
        # The test listener is removed; the template listener stays.
        self.assertEqual(len(list(lua_list(sim.server.g.SS_LISTENERS))), 1)
        self.assertEqual([m for m in sim.state().missions.values() if m.template == 'signal'], [])


class SignalReportTests(ReportCases, unittest.TestCase):
    """E11-T13 : compte rendu au PNJ demandeur d'une mission « signaler » (cas communs de ReportCases)."""

    setUp, tearDown, sim, catalog, light = (SignalMissionTests.setUp, SignalMissionTests.tearDown,
                                            SignalMissionTests.sim, SignalMissionTests.catalog,
                                            SignalMissionTests.light)

    def active(self, name):
        return SignalMissionTests.active(self, name)

    def fulfil(self, sim, m):
        self.light(sim, 'alice', m.color)
        self.assertTrue(m.lit)


if __name__ == '__main__':
    unittest.main(verbosity=2)
