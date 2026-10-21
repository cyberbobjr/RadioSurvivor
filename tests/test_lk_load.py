"""Mesure de charge de Living Knox (LK13-T02) : shared/LivingKnox/LK_Load.lua, requête d'administration « load » de
server/LivingKnox/LK_Admin.lua, suite en jeu lk.load et banc tools/load_bench.py.

    python RadioSurvivor/tests/test_lk_load.py

Bancs :
- tests/harness.py en MP (serveur dédié + deux clients) et en solo, moteur réduit (LK_Core, LK_Config, LK_Log,
  LK_Load) et abonnés de test inscrits par LivingKnox.subscribe ; horloge de mesure Load.clock = compteur FAKE avancé
  par les abonnés de test (coûts exacts) ; enveloppes posées au bon moment (aucun abonné appelé deux fois ni sauté),
  arguments et valeurs rendues gardés, réseau compté par commande, fenêtres, budgets, écritures des registres ;
- pile d'administration de tests/test_lk_admin.py (droit PopmanManage simulé) : refus sans donnée, départ, rapport,
  arrêt, routage MP et réponse imprimée par Load.ask ;
- suite lk.load jouée par le vrai moteur RST (mod de développement) sur le banc solo ;
- banc de charge tools/load_bench.py sur 2 minutes de jeu (5 groupes, 4 joueurs) : sans erreur, chiffres cohérents.
Les doublures NE PROUVENT PAS l'API réelle ni les coûts du jeu (lupa n'est pas Kahlua) : voir
docs/annexes/tests/validation/charge-hors-jeu-2026-10-12.md et docs/annexes/tests/validation/charge-protocole.md.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, LUA  # noqa: E402
from test_lk_admin import API_SERVER, API_SHARED, API_WORLD, NO_GRID, PERMISSIONS, POPULATE, role_for  # noqa: E402
from test_lk_bodies import DEV_LUA, lua_list  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LOAD_FILE = LUA / 'shared' / 'LivingKnox' / 'LK_Load.lua'
SUITE = 'shared/RST/suites/RST_LKLoad.lua'
CORE = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
        'shared/LivingKnox/LK_Load.lua')
L = 'LivingKnox.Load'

# Abonnés de test : chacun coûte COST[clé] sur l'horloge FAKE et compte ses appels ; rend ses arguments et deux
# valeurs (dont un nil au milieu) pour vérifier que l'enveloppe les garde.
FAKES = r'''
FAKE, CALLS, COST, SEEN = 0, {}, {}, {}
LivingKnox.Load.clock = function() return FAKE end
function FAKE_HANDLER(key)
    return function(...)
        CALLS[key] = (CALLS[key] or 0) + 1
        FAKE = FAKE + (COST[key] or 0)
        SEEN[key] = { n = select('#', ...), ... }
        return 'r1', nil, 'r3'
    end
end
function FAKE_SUB(event, key, cost)
    COST[key] = cost
    LivingKnox.subscribe(event, key, FAKE_HANDLER(key))
end
'''


class LoadBase(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = Harness(mode=self.mode)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        self.machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in self.machines:
            for path in CORE:
                self.h.load(m, path)
            self.h.load(m, FAKES)
            self.h.load(m, 'FAKE_SUB("OnTick", "Mod.tick", 2) FAKE_SUB("EveryOneMinute", "Mod.minute", 5) '
                           'FAKE_SUB("OnTickEvenPaused", "Mod.flush", 1) FAKE_SUB("OnClientCommand", "Mod.cmd", 0) '
                           'FAKE_SUB("OnServerCommand", "Mod.view", 0)')

    def tearDown(self):
        self.h.close()

    def ev(self, code, m=None):
        return self.h.eval(m or self.srv, code)

    def run_lua(self, code, m=None):
        return self.h.load(m or self.srv, code)

    def calls(self, key, m=None):
        return self.ev(f'CALLS["{key}"] or 0', m)

    def start(self, m=None, opts='{}'):
        self.assertIsNotNone(self.ev(f'{L}.start({opts})', m))

    def summary(self, m=None):
        return self.ev(f'{L}.summary()', m)

    def module_row(self, summary, name):
        return next((r for r in lua_list(summary.modules) if r.module == name), None)


class WrapTests(LoadBase):
    def test_install_is_deferred_and_no_subscriber_runs_twice_or_is_skipped(self):
        self.h.tick(1)
        base = {k: self.calls(k) for k in ('Mod.tick', 'Mod.flush')}
        self.start()
        self.assertFalse(self.ev(f'{L}.active.installed'))
        self.assertIsNone(self.ev(f'{L}.wrapped["OnTick/Mod.tick"]'))   # rien d'enveloppé avant l'image suivante
        self.h.tick(1)                                  # installation : OnTickEvenPaused puis OnTick
        self.assertTrue(self.ev(f'{L}.active.installed'))
        self.assertEqual(self.calls('Mod.tick'), base['Mod.tick'] + 1)
        self.assertEqual(self.calls('Mod.flush'), base['Mod.flush'] + 1)
        self.h.tick(3)
        self.assertEqual(self.calls('Mod.tick'), base['Mod.tick'] + 4)
        self.assertEqual(self.calls('Mod.flush'), base['Mod.flush'] + 4)
        for slot in ('OnTick/Mod.tick', 'OnTickEvenPaused/Mod.flush', 'EveryOneMinute/Mod.minute'):
            self.assertTrue(self.ev(f'LivingKnox.handlers["{slot}"] == {L}.wrapped["{slot}"].wrapper'), slot)
        # Abonnés du module de mesure jamais enveloppés.
        self.assertIsNone(self.ev(f'{L}.wrapped["OnTick/Load.counter"]'))
        self.assertIsNone(self.ev(f'{L}.wrapped["OnTickEvenPaused/Load.install"]'))

    def test_costs_per_tick_and_per_module_and_max(self):
        # Image de pose : Load.install (OnTickEvenPaused) enveloppe Mod.tick, Load.counter (inscrit avant Mod.tick) clôt
        # l'image vide puis enveloppe Mod.flush ; le coût de Mod.tick d'une image est compté dans l'image suivante.
        self.start()
        self.h.tick(1)
        self.h.tick(10)
        self.h.advance(2)                               # deux minutes de jeu : 2 x 5
        self.h.tick(1)
        s = self.summary()
        mod = self.module_row(s, 'Mod')
        slots = {x.key: x for x in lua_list(mod.slots)}
        self.assertEqual(slots['Mod.tick'].calls, 12)
        self.assertEqual(slots['Mod.tick'].ms, 24)
        self.assertEqual(slots['Mod.minute'].calls, 2)
        self.assertEqual(slots['Mod.minute'].max, 5)
        self.assertEqual(slots['Mod.flush'].calls, 11)           # pas l'image de pose
        self.assertEqual(s.ticks, 12)
        self.assertEqual(s.engineMs, 24 + 10 + 11 - 2)            # Mod.tick de la dernière image : image ouverte
        self.assertEqual(s.tickMaxMs, 2 + 10 + 1)                # image de la ligne advance : 2 + 2 x 5 + 1
        self.assertEqual(mod.tickMax, 13)
        self.assertAlmostEqual(s.perTickMs, 43 / 12)

    def test_arguments_and_returned_values_are_kept(self):
        self.start()
        self.h.tick(1)
        self.run_lua('R = { LivingKnox.handlers["EveryOneMinute/Mod.minute"]("a", nil, 3) }')
        self.assertEqual(self.ev('SEEN["Mod.minute"].n'), 3)
        self.assertEqual((self.ev('SEEN["Mod.minute"][1]'), self.ev('SEEN["Mod.minute"][3]')), ('a', 3))
        self.assertEqual(self.ev('select("#", LivingKnox.handlers["EveryOneMinute/Mod.minute"]())'), 3)
        self.assertEqual((self.ev('R[1]'), self.ev('R[2]'), self.ev('R[3]')), ('r1', None, 'r3'))

    def test_error_in_a_subscriber_reaches_the_engine_and_is_not_counted(self):
        self.run_lua('FAKE_SUB("EveryOneMinute", "Bad.minute", 1) '
                     'local f = LivingKnox.handlers["EveryOneMinute/Bad.minute"] '
                     'LivingKnox.subscribe("EveryOneMinute", "Bad.minute", function() FAKE = FAKE + 1 error("boom") end)')
        self.h.strict = False
        self.start()
        self.h.tick(1)
        self.h.advance(1)
        self.assertTrue(any('boom' in e for e in self.h.errors(self.srv)))
        s = self.summary()
        self.assertIsNone(self.module_row(s, 'Bad'))
        self.assertEqual(self.module_row(s, 'Mod').calls >= 1, True)

    def test_stop_keeps_transparent_wrappers_and_restart_reuses_them(self):
        self.start()
        self.h.tick(2)
        self.ev(f'{L}.stop()')
        self.run_lua(f'WRAPPER = {L}.wrapped["OnTick/Mod.tick"].wrapper')
        n = self.calls('Mod.tick')
        self.h.tick(3)
        self.assertEqual(self.calls('Mod.tick'), n + 3)                 # toujours appelé, une fois par image
        self.assertEqual(self.ev(f'{L}.last.ticks'), 2)
        self.start()
        self.h.tick(2)
        self.assertTrue(self.ev(f'{L}.wrapped["OnTick/Mod.tick"].wrapper == WRAPPER'))
        self.assertEqual(self.ev(f'{L}.active.wrappedNow'), 0)          # aucune nouvelle enveloppe
        self.assertEqual(self.calls('Mod.tick'), n + 5)

    def test_reloaded_module_is_not_measured_until_the_next_start(self):
        self.start()
        self.h.tick(2)
        self.run_lua('FAKE_SUB("OnTick", "Mod.tick", 7)')                # rechargement : l'enveloppe est remplacée
        self.h.tick(2)
        s = self.summary()
        slots = {x.key: x for x in lua_list(self.module_row(s, 'Mod').slots)}
        self.assertEqual(slots['Mod.tick'].calls, 2)                  # avant le rechargement seulement
        self.ev(f'{L}.stop()')
        self.start()
        self.h.tick(1)
        self.assertEqual(self.ev(f'{L}.active.wrappedNow'), 1)

    def test_double_start_refused_and_window_bounds(self):
        self.start(opts='{ windowMs = 5 }')
        self.assertEqual(self.ev(f'{L}.active.windowMs'), 1000)
        r, why = self.run_lua(f'return {L}.start()')
        self.assertIsNone(r)
        self.assertEqual(why, 'a measure is already running')
        self.ev(f'{L}.stop()')
        self.start(opts='{ windowMs = 99999999 }')
        self.assertEqual(self.ev(f'{L}.active.windowMs'), 600000)
        self.assertEqual(self.run_lua(f'{L}.stop() local s, why = {L}.stop() return why'), 'no measure running')

    def test_window_closes_and_logs_when_asked(self):
        self.start(opts='{ windowMs = 1000, log = true }')
        self.h.tick(1)
        for _ in range(70):                                              # 70 x 16 ms > 1 s
            self.h.tick(1)
        s = self.summary()
        self.assertGreaterEqual(s.windows, 1)
        self.assertEqual(s.window.ticks, 64)                             # images 1 à 64 : 63 x 16 = 1008 ms
        lines = [x for x in self.h.logs(self.srv) if 'load: window' in x]
        self.assertGreaterEqual(len(lines), 1)
        self.assertRegex(lines[0], r'\[LivingKnox\] INFO load: window 1(\.\d+)? s on server: 64 ticks, engine '
                                   r'2\.95\d* ms/tick')                 # 63 x 3 ms / 64 images

    def test_no_log_line_by_default(self):
        self.start(opts='{ windowMs = 1000 }')
        for _ in range(80):
            self.h.tick(1)
        self.assertEqual([x for x in self.h.logs(self.srv) if 'load: window' in x], [])


class NetworkTests(LoadBase):
    def test_server_commands_counted_by_command_one_or_all_and_restored(self):
        self.run_lua('ORIGINAL = sendServerCommand')
        self.start()
        self.h.tick(1)
        self.run_lua('local p = getOnlinePlayers():get(0) '
                     'sendServerCommand(p, "LivingKnox", "dirState", { a = 1, b = "xy" }) '
                     'sendServerCommand("LivingKnox", "guardRoster", { t = true }) '
                     'sendServerCommand("LivingKnox", "guardRoster", nil) '
                     'sendServerCommand(p, "Other", "x", { a = 1 })')
        self.assertEqual(len([m for m in self.h.pending() if m['module'] == 'LivingKnox']), 1 + 2 + 2)
        s = self.summary()
        self.assertEqual((s.sent.count, s.sent.toOne, s.sent.toAll), (3, 1, 2))
        cmds = {c.command: c for c in lua_list(s.sent.commands)}
        self.assertEqual(cmds['guardRoster'].count, 2)
        self.assertEqual(cmds['dirState'].bytes, 2 + 1 + 8 + 1 + 2)       # table, a, 1, b, "xy"
        self.assertEqual(lua_list(s.sent.commands)[0].command, 'guardRoster')
        self.ev(f'{L}.stop()')
        self.assertTrue(self.ev('sendServerCommand == ORIGINAL'))

    def test_received_commands_on_the_server_and_on_a_client(self):
        self.start()
        self.start('A')
        self.h.tick(1)
        self.run_lua('sendClientCommand("LivingKnox", "bodyReport", { r = { 1, 2 } })', 'A')
        self.run_lua('sendClientCommand("Other", "x", {})', 'A')
        sa = self.summary('A')
        self.assertEqual((sa.sent.count, sa.sent.toOne), (1, 1))
        self.h.pump()
        s = self.summary()
        self.assertEqual(s.recv.count, 1)
        self.assertEqual(lua_list(s.recv.commands)[0].command, 'bodyReport')
        self.run_lua('sendServerCommand("LivingKnox", "animState", { g = "walk" })')
        self.h.pump()
        self.assertEqual(self.summary('A').recv.count, 1)
        self.assertEqual(self.summary('B').recv.count if self.ev(f'{L}.active', 'B') else 0, 0)

    def test_rates_and_budget_check(self):
        self.start()
        self.h.tick(1)
        self.run_lua('for i = 1, 500 do sendServerCommand("LivingKnox", "dirState", { i = i }) end')
        self.h.advance_ms(10000)
        self.h.tick(1)
        s = self.summary()
        over = lua_list(s.over)
        self.assertTrue(any(x.startswith('sent ') and x.endswith(' > 40 msg/s') for x in over), over)
        lines = lua_list(self.ev(f'{L}.lines({L}.summary())'))
        self.assertTrue(lines[-1].startswith('budget: OVER '), lines[-1])
        self.assertTrue(any(line.startswith('net sent: 500 msg (') for line in lines), lines)


class StateAndSaveTests(unittest.TestCase):
    """Taille de l'état et écritures sur le vrai registre des groupes (pile de test_lk_admin.py)."""

    def setUp(self):
        self.h = Harness(mode='mp')
        for m in ('server', 'A', 'B'):
            self.h.load(m, API_WORLD + NO_GRID)
            self.h.load(m, PERMISSIONS)
            for path in API_SHARED + API_SERVER:
                self.h.load(m, path)
            self.h.load(m, 'server/LivingKnox/LK_Admin.lua')
            self.h.load(m, 'shared/LivingKnox/LK_Load.lua')            # fichier shared : chargé partout en jeu
        self.h.fire('server', 'OnInitGlobalModData', False)
        self.a, self.b = self.h.load('server', POPULATE)

    def tearDown(self):
        self.h.close()

    def test_state_size_matches_the_encoded_registries_and_fields(self):
        st = self.h.eval('server', f'{L}.stateSize()')
        codec = 'local C = require "RadioSurvivor/RS_Codec" '
        groups = self.h.load('server', codec + 'return #C.encodeBytes(LivingKnox.Groups.state.data) * 2')
        self.assertEqual(st.groups, groups)
        self.assertEqual(st.registry, self.h.load('server', codec + 'return #C.encodeBytes(LivingKnox.Store.state.data) * 2'))
        self.assertEqual(st.groupCount, 2)
        self.assertEqual(st.members, 4)
        self.assertGreater(st.sections.members, 0)
        self.assertGreater(st.sections.log, 0)
        self.assertGreaterEqual(st.logEntries, 2)
        self.assertIsNone(self.h.eval('A', f'({L}.stateSize())'))

    def test_registry_writes_counted_by_header_and_unwrapped_at_stop(self):
        self.h.load('server', 'LivingKnox.Groups.flush()')   # LK13-T06 : création des groupes écrite avant la mesure
        self.h.load('server', 'ORIGINAL = LivingKnox.Store.writeSlotFile')
        self.h.load('server', f'assert({L}.start())')
        self.h.tick(1)
        self.h.load('server', f'assert(LivingKnox.Groups.setMorale("{self.a}", 50))')
        self.h.load('server', f'assert(LivingKnox.Groups.setMorale("{self.a}", 40))')
        self.h.tick(1)   # LK13-T06 : les deux changements écrits en une fois, à l'image suivante
        self.h.load('server', 'assert(LivingKnox.Groups.setMorale("' + self.a + '", 30)) assert(LivingKnox.Groups.flush())')
        s = self.h.eval('server', f'{L}.summary()')
        saves = {x.header: x for x in lua_list(s.saves)}
        self.assertEqual(saves['LKGRP1'].calls, 2)
        self.assertEqual(self.h.eval('server', f'LivingKnox.Groups.get("{self.a}").morale'), 30)   # écriture réelle
        lines = lua_list(self.h.eval('server', f'{L}.lines({L}.summary())'))
        self.assertTrue(any(line.startswith('saves: LKGRP1 2 (') for line in lines), lines)
        self.assertTrue(any(line.startswith('state: registry ') for line in lines), lines)
        self.h.load('server', f'{L}.stop()')
        self.assertTrue(self.h.eval('server', 'LivingKnox.Store.writeSlotFile == ORIGINAL'))


class AdminTests(unittest.TestCase):
    """Requête d'administration « load » : droit vérifié d'abord, puis départ, rapport et arrêt."""

    def setUp(self):
        self.h = Harness(mode='mp')
        for m in ('server', 'A', 'B'):
            self.h.load(m, API_WORLD + NO_GRID)
            self.h.load(m, PERMISSIONS)
            for path in API_SHARED + API_SERVER:
                self.h.load(m, path)
            self.h.load(m, 'server/LivingKnox/LK_Admin.lua')
            self.h.load(m, 'shared/LivingKnox/LK_Load.lua')            # fichier shared : chargé partout en jeu
        self.h.load('server', 'ADMINS.A = true local l = getOnlinePlayers() '
                              'for i = 0, l:size() - 1 do GIVE_ROLE(l:get(i)) end')
        self.h.fire('server', 'OnInitGlobalModData', False)
        self.h.load('server', POPULATE)
        self.h.load('A', role_for(True))
        self.h.load('B', role_for(False))

    def tearDown(self):
        self.h.close()

    def req(self, who, **args):
        fields = ', '.join(f'{k} = {v!r}'.replace("'", '"') for k, v in args.items())
        return self.h.eval('server', f'LivingKnox.Admin.request(getOnlinePlayers():get({who}), {{ {fields} }})')

    def test_non_admin_is_refused_without_data_and_nothing_starts(self):
        r = self.req(1, op='load', action='start', n=4)
        self.assertEqual(sorted(r.keys()), ['err', 'n', 'ok', 'op'])
        self.assertEqual(r.err, 'denied')
        self.assertIsNone(self.h.eval('server', f'{L}.active'))

    def test_admin_starts_reads_and_stops_a_measure(self):
        r = self.req(0, op='load', action='start', n=1, windowMs=5000)
        self.assertTrue(r.ok, r.err)
        self.assertTrue(r.running)
        self.assertIn('measure started on server (window 5000 ms', lua_list(r.lines)[0])
        self.assertEqual(self.req(0, op='load', action='start', n=2).err, 'a measure is already running')
        self.h.tick(5)
        r = self.req(0, op='load', action='report', n=3)
        self.assertTrue(r.ok and r.running)
        lines = lua_list(r.lines)
        self.assertTrue(lines[0].startswith('load on server (running): '), lines[0])
        r = self.req(0, op='load', action='stop', n=4)
        self.assertTrue(r.ok)
        self.assertFalse(r.running)
        self.assertEqual(self.req(0, op='load', action='stop', n=5).err, 'no measure running')
        self.assertEqual(self.req(0, op='load', action='wipe', n=6).err, 'unknown load action')
        logs = self.h.logs('server')
        self.assertTrue(any('admin: A started a load measure (window 5000 ms)' in x for x in logs))
        self.assertTrue(any('admin: A stopped the load measure' in x for x in logs))
        self.assertTrue(any('[LivingKnox] INFO load: load on server: ' in x for x in logs))

    def test_client_ask_routes_to_the_server_and_prints_the_reply(self):
        self.assertTrue(self.h.eval('A', f'{L}.ask("start", {{ windowMs = 2000 }})'))
        self.h.pump()
        self.h.pump()
        self.assertTrue(any('load: server measure started on server (window 2000 ms' in x for x in self.h.logs('A')))
        self.assertTrue(self.h.eval('B', f'{L}.ask("report")'))
        self.h.pump()
        self.h.pump()
        self.assertTrue(any('load: server refused the load request: denied' in x for x in self.h.logs('B')))
        self.assertFalse(self.h.eval('server', f'{L}.ask("report")'))    # l'autorité n'envoie rien


class SoloTests(LoadBase):
    mode = 'solo'

    def test_solo_wraps_send_server_command_and_counts_nothing_sent_by_the_network(self):
        self.start()
        self.h.tick(2)
        self.assertEqual(self.ev(f'{L}.active.netName'), 'sendServerCommand')
        self.assertEqual(self.ev(f'{L}.active.side'), 'solo')
        lines = lua_list(self.ev(f'{L}.lines({L}.summary())'))
        self.assertTrue(lines[0].startswith('load on solo (running): '), lines)
        self.assertTrue(self.ev(f'{L}.print()'))


class SuiteTests(unittest.TestCase):
    """Suite en jeu lk.load jouée par le vrai moteur RST sur le banc solo (pile d'administration)."""

    def setUp(self):
        self.h = Harness(mode='solo', lua_roots=[DEV_LUA], tick_ms=100)
        self.h.load('solo', API_WORLD + NO_GRID)
        self.h.load('solo', PERMISSIONS)
        for path in API_SHARED + API_SERVER:
            self.h.load('solo', path)
        self.h.load('solo', 'server/LivingKnox/LK_Admin.lua')
        self.h.fire('solo', 'OnInitGlobalModData', False)
        self.h.load('solo', POPULATE)
        self.h.load('solo', 'require "RST/RST"')
        self.h.load('solo', SUITE)
        self.h.load('solo', 'RST_LK_LOAD_MS = 3000')

    def tearDown(self):
        self.h.close()

    def run_suite(self):
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.load", tags = "server" }, '
                                          '{ attach = false, ctx = { player = getPlayer() } }))'), True)
        for _ in range(2000):
            self.h.tick(1)
            if not self.h.eval('solo', 'RST.step()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in lua_list(report.results)}

    def test_suite_listed_with_the_server_tag_only(self):
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.load" }, true)[1]')
        self.assertEqual(lua_list(listed.tags), ['server'])
        self.assertEqual(listed.count, 4)   # fenêtre solo (2026-10-15) comprise
        self.assertIsNone(listed.error)

    def test_suite_passes_and_leaves_no_measure(self):
        report, results = self.run_suite()
        # Fenêtre solo (2026-10-15) : client solo du jeu seulement (aucune fenêtre sur ce banc, SKIP ici)
        self.assertEqual(results.pop('solo window: measure started, read and stopped with the admin window buttons')[0],
                         'SKIP')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 4)
        self.assertIsNone(self.h.eval('solo', f'{L}.active'))
        notes = lua_list(lua_list(report.results)[3].notes)   # après la fenêtre solo (SKIP)
        self.assertTrue(any(n.startswith('load on solo: ') for n in notes), notes)
        self.assertTrue(any(n.startswith('budget: ') for n in notes), notes)

    def test_suite_detects_a_missing_access_check(self):
        self.h.load('solo', 'LivingKnox.Admin.isAllowed = function() return true end')
        _, results = self.run_suite()
        self.assertEqual(results['a request without an allowed player is refused without data'][0], 'FAIL')


class BenchTests(unittest.TestCase):
    """Banc de charge tools/load_bench.py sur 2 minutes de jeu : sans erreur d'abonné, chiffres cohérents."""

    def test_two_game_minutes_with_five_groups_and_four_players(self):
        sys.path.insert(0, str(ROOT / 'tools'))
        import load_bench
        info, result = load_bench.run(minutes=2, warmup=1)
        self.assertEqual(info['groups'], ['grp-1', 'grp-2', 'grp-3', 'grp-4', 'grp-5'])
        self.assertEqual(info['errors'], {'server': 0, 'A': 0, 'B': 0, 'C': 0, 'D': 0})
        self.assertGreater(info['bodies'], 0)
        self.assertEqual(sorted(result), ['A', 'B', 'C', 'D', 'server'])
        srv = result['server']['summary']
        self.assertEqual(srv['ticks'], 2 * load_bench.TICKS_PER_MINUTE)
        self.assertGreater(srv['measured'], 30)
        self.assertGreater(srv['sent']['count'], 0)
        self.assertGreater(srv['recv']['count'], 0)
        self.assertGreater(info['state']['groups'], 0)
        self.assertEqual(result['D']['summary']['sent']['count'], 0)      # joueur loin de tout : rien à rapporter
        self.assertTrue(result['server']['lines'][0].startswith('load on server: '))


class SourceTests(unittest.TestCase):
    def test_code_lines_are_ascii_and_messages_english(self):
        text = LOAD_FILE.read_text(encoding='utf-8')
        for i, line in enumerate(text.splitlines(), 1):
            code = line.split('--', 1)[0]
            self.assertTrue(code.isascii(), f'LK_Load.lua:{i} non-ASCII outside a comment')
        for m in re.finditer(r'Log\.(?:info|warn|error)\("([^"]*)"', text):
            self.assertTrue(m.group(1).isascii())
        self.assertNotIn('next(', text)
        self.assertNotIn('goto ', text)
        self.assertNotIn('coroutine', text)

    def test_admin_constants_match(self):
        admin = (LUA / 'server' / 'LivingKnox' / 'LK_Admin.lua').read_text(encoding='utf-8')
        text = LOAD_FILE.read_text(encoding='utf-8')
        for name in ('MODULE', 'CMD_REQUEST', 'CMD_REPLY'):
            a = re.search(rf'^Admin\.{name} = "([^"]+)"', admin, re.M).group(1)
            b = re.search(rf'^Load\.{name} = "([^"]+)"', text, re.M).group(1)
            self.assertEqual(a, b, name)


ORDER = r'''
ORDER = {}
function ORDER_SUB(event, key)
    LivingKnox.subscribe(event, key, function() ORDER[#ORDER + 1] = key end)
end
'''


class OrderTests(LoadBase):
    """LK13-T12 : la pose des enveloppes garde l'ordre réel des abonnés du moteur (pas l'ordre alphabétique)."""

    def setUp(self):
        super().setUp()
        self.run_lua(ORDER)

    def order(self):
        out = lua_list(self.ev('ORDER'))
        self.run_lua('ORDER = {}')
        return out

    def test_wrapped_subscribers_keep_the_registration_order(self):
        self.run_lua('ORDER_SUB("EveryOneMinute", "Zed.minute") ORDER_SUB("EveryOneMinute", "Mid.minute") '
                     'ORDER_SUB("EveryOneMinute", "Alp.minute") '
                     'ORDER_SUB("OnTickEvenPaused", "Zed.frame") ORDER_SUB("OnTickEvenPaused", "Alp.frame")')
        self.h.advance(1)
        before = self.order()
        self.assertEqual(before[:3], ['Zed.minute', 'Mid.minute', 'Alp.minute'])
        self.start()
        self.h.tick(2)                                        # pose : les deux images
        self.run_lua('ORDER = {}')
        self.h.advance(1)
        self.assertEqual(self.order()[:3], ['Zed.minute', 'Mid.minute', 'Alp.minute'])
        self.h.tick(1)
        self.assertEqual(self.order(), ['Zed.frame', 'Alp.frame'])
        for slot in ('EveryOneMinute/Alp.minute', 'OnTickEvenPaused/Zed.frame'):
            self.assertTrue(self.ev(f'LivingKnox.handlers["{slot}"] == {L}.wrapped["{slot}"].wrapper'), slot)
        s = self.summary()
        self.assertEqual(self.module_row(s, 'Zed').calls, 3)    # 1 minute + 2 images mesurées

    def test_requeue_moves_the_measure_wrapper_like_the_subscriber(self):
        # Remise en fin de liste (Groups.flush, Store.flush) faite après la pose : l'enveloppe se déplace comme
        # l'abonné l'aurait fait sans mesure.
        self.run_lua('ORDER_SUB("OnTick", "First.tick") ORDER_SUB("OnTick", "Second.tick") '
                     'FIRST = LivingKnox.handlers["OnTick/First.tick"]')
        self.start()
        self.h.tick(1)
        self.run_lua('ORDER = {}')
        self.h.tick(1)
        self.assertEqual(self.order(), ['First.tick', 'Second.tick'])
        self.assertTrue(self.ev('LivingKnox.requeue("OnTick", "First.tick", FIRST)'))
        self.assertFalse(self.ev('LivingKnox.requeue("OnTick", "First.tick", function() end)'))   # autre fonction
        self.h.tick(1)
        self.assertEqual(self.order(), ['Second.tick', 'First.tick'])
        self.assertEqual(self.calls('Mod.tick'), 3)
        # Sans mesure : même déplacement de l'abonné nu.
        self.run_lua('ORDER_SUB("OnTick", "Third.tick") THIRD = LivingKnox.handlers["OnTick/Third.tick"] '
                     'ORDER_SUB("OnTick", "Fourth.tick")')
        self.assertTrue(self.ev('LivingKnox.requeue("OnTick", "Third.tick", THIRD)'))
        self.h.tick(1)
        self.assertEqual(self.order(), ['Second.tick', 'First.tick', 'Fourth.tick', 'Third.tick'])

    def test_restart_after_a_reload_follows_the_real_order(self):
        # Abonné rechargé (passé en fin de liste par subscribe) : à la session suivante, l'abonné rechargé est
        # enveloppé à sa vraie place, les enveloppes qui le précédaient restent devant.
        self.run_lua('ORDER_SUB("EveryOneMinute", "Bbb.minute") ORDER_SUB("EveryOneMinute", "Aaa.minute") '
                     'ORDER_SUB("EveryOneMinute", "Ccc.minute")')
        self.start()
        self.h.tick(1)
        self.ev(f'{L}.stop()')
        self.run_lua('ORDER_SUB("EveryOneMinute", "Bbb.minute")')                  # rechargement
        self.h.advance(1)
        expected = self.order()
        self.assertEqual(expected[:3], ['Aaa.minute', 'Ccc.minute', 'Bbb.minute'])
        self.start()
        self.h.tick(1)
        self.assertEqual(self.ev(f'{L}.active.wrappedNow'), 1)
        self.run_lua('ORDER = {}')
        self.h.advance(1)
        self.assertEqual(self.order(), expected)


class BenchOrderTests(unittest.TestCase):
    """LK13-T12 : banc de charge (5 groupes, 4 joueurs) avec et sans mesure : mêmes registres, mêmes écritures."""

    def compare(self, minutes, warmup):
        sys.path.insert(0, str(ROOT / 'tools'))
        import load_bench
        plain = load_bench.run_compare(minutes, measure=False, warmup=warmup)
        measured = load_bench.run_compare(minutes, measure=True, warmup=warmup)
        for r in (plain, measured):
            self.assertEqual(r['errors'], {'server': 0, 'A': 0, 'B': 0, 'C': 0, 'D': 0})
        self.assertEqual(measured['writes'], plain['writes'])
        self.assertGreater(plain['writes'].get('LKGRP1', 0), 0)
        self.assertEqual(sorted(plain['state']), ['attitudes', 'groups', 'registry'])
        for name in plain['state']:
            self.assertEqual(measured['state'][name], plain['state'][name], name)

    def test_one_game_hour_after_warm_up_same_registries_and_writes(self):
        self.compare(62, warmup=1)              # EveryHours compris (minute 60)

    def test_measure_started_before_the_first_frame_same_registries_and_writes(self):
        self.compare(62, warmup=0)              # pose avant les remises en fin de liste de Groups et Store


if __name__ == '__main__':
    unittest.main(verbosity=1)
