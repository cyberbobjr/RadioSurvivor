"""Tests hors jeu du relais des gestes et des poses Living Knox (LK03-T05) : LK_Relay.lua (serveur), LK_Anim.lua et
LK_Presentation.lua (clients).

    python RadioSurvivor/tests/test_lk_relay.py

Banc tests/harness.py et doublures de test_lk_bodies.py, test_lk_guard.py, test_lk_anim.py et test_lk_directives.py.
Images du serveur de 100 ms comme un serveur dédié (J/network/GameServer.java:261, 835-836). Simulation : le banc
compte les appels sendServerCommand du serveur ; seule une séance MP mesure le réseau réel (protocole de
docs/annexes/conception/corps-et-animations.md, « Relais des gestes »).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA  # noqa: E402
from test_lk_directives import DirectiveBase, TARGET  # noqa: E402

RELAY = 'server/LivingKnox/LK_Relay.lua'
TICK_MS = 100
FAR = [f'C{i:02d}' for i in range(1, 19)]   # 18 joueurs loin du PNJ (0, 0) : 20 joueurs dont 2 proches


class RelayBase(DirectiveBase):
    def setUp(self):
        super().setUp()
        self.h.tick_ms = TICK_MS
        self.run_lua('SandboxVars = SandboxVars or {}\n'
                     'SandboxVars[LivingKnox.Config.NAMESPACE] = SandboxVars[LivingKnox.Config.NAMESPACE] or {}\n'
                     'SandboxVars[LivingKnox.Config.NAMESPACE].Debug = true')

    def r(self, code):
        return self.ev('LivingKnox.Relay.' + code)

    def cfg(self, name):
        return self.ev(f'LivingKnox.Config.RELAY.{name}')

    def mirror(self, zid, owner, machines=('A', 'B')):
        srv = self.h.zombie('server', zid)
        for c in machines:
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        for c in self.h.clients:                                  # joueurs sans le mod chargé : copie nue
            if c not in machines:
                self.h.machine(c).H.spawnZombie(zid, srv.x, srv.y, srv.z, owner)
        self.h.set_owner(zid, owner)

    def ready(self, owner='A'):
        zid = self.npc()
        self.mirror(zid, owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def gesture(self, g, npc='lk-1'):
        self.assertIs(self.ev(f'LivingKnox.Anim.setGesture("{npc}", "{g}")'), True)

    def anim_msgs(self):
        return [m for m in self.h.pending() if m['module'] == 'LivingKnox' and m['command'] == 'animState']

    def collect(self, ticks, log):
        """ticks images : messages animState relevés avant livraison ({client: [entrées de lk-1]}), puis livrés."""
        per_tick = []
        for _ in range(ticks):
            self.h.tick(1)
            msgs = self.anim_msgs()
            per_tick.append(len(msgs))
            for m in msgs:
                e = m['args']['d'].get('lk-1')
                if e is not None:
                    log.setdefault(m['to'], []).append('gone' if e.get('gone') else e.get('g'))
            self.h.pump()
        return per_tick


class TrafficTests(RelayBase):
    """Banc d'acceptation : même trafic de gestes avec 2 puis 20 joueurs, dont 2 proches."""

    def scenario(self):
        zid = self.ready('A')
        self.d(f'moveTo("lk-1", {TARGET[0]}, {TARGET[1]}, {TARGET[2]}, "walk")')
        self.h.pump()
        self.walk(zid, 200, speed=0.25, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.relayed()
        for g in ('aim', 'strike', 'guard', 'idle'):   # changements rapprochés : regroupés, strike gardé
            self.gesture(g)
            self.h.tick(1)
            self.h.pump()
        self.relayed()
        self.relayed()
        st = self.r('stats')
        out = {'messages': st.messages, 'bytes': st.bytes, 'clients': sorted(st.byClient.keys()),
               'maxDelay': st.maxDelay, 'gestures': [self.h.eval(c, 'LivingKnox.Anim.gestureOf("lk-1")')
                                                     for c in ('A', 'B')],
               'poses': self.h.eval('B', 'LivingKnox.Presentation.poseOf("lk-1").s')}
        print(f"\n[bench] {len(self.h.clients)} players: {out['messages']} gesture msg, {out['bytes']} B, "
              f"clients {out['clients']}, max emission delay {out['maxDelay']} ms, published {st.published}, "
              f"coalesced {st.coalesced}, kept {st.kept}, max per tick {st.maxPerTick}", file=sys.stderr)
        return out

    def test_traffic_follows_near_players_not_the_total(self):
        two = self.scenario()
        self.h.close()
        self.clients = ('A', 'B', *FAR)
        self.setUp()
        self.assertEqual(len(self.h.clients), 20)
        twenty = self.scenario()
        self.assertEqual(two['clients'], ['A', 'B'])
        self.assertEqual(twenty['clients'], ['A', 'B'])          # les 18 joueurs lointains ne reçoivent rien
        self.assertEqual(twenty['messages'], two['messages'])
        self.assertEqual(twenty['bytes'], two['bytes'])
        self.assertGreater(two['messages'], 0)
        for out in (two, twenty):
            self.assertEqual(out['gestures'], ['idle', 'idle'])   # geste final jamais perdu
            self.assertEqual(out['poses'], 'arrived')
            # Délai d'émission (changement -> envoi) : au plus une fenêtre de regroupement + une image.
            self.assertGreaterEqual(out['maxDelay'], 0)
            self.assertLessEqual(out['maxDelay'], self.cfg('WINDOW_MS') + TICK_MS)


class CadenceTests(RelayBase):
    def test_cadence_bounded_per_npc_and_last_state_wins(self):
        self.ready('A')
        self.relayed()
        log = {}
        gestures = ['aim', 'guard'] * 15
        per_tick = []
        for g in gestures:                                       # un changement par image pendant 3 s
            self.gesture(g)
            per_tick += self.collect(1, log)
        per_tick += self.collect(5, log)
        window = self.cfg('WINDOW_MS')
        for c in ('A', 'B'):
            seq = log[c]
            self.assertEqual(seq[-1], 'guard')                     # dernier état gagnant, toujours remis
            # 30 changements en 3 s : au plus 1 + 3000 / fenêtre arrondie à l'image (200 ms) envois par client.
            self.assertLessEqual(len(seq), 1 + 3000 // 200 + 1, seq)
            self.assertLess(len(seq), len(gestures))
        self.assertEqual(self.h.eval('A', 'LivingKnox.Anim.gestureOf("lk-1")'), 'guard')
        self.assertGreater(self.r('stats.coalesced'), 0)
        # Fenêtre : jamais deux publications du même PNJ à moins de WINDOW_MS (images de 100 ms : une sur deux).
        sends = [i for i, n in enumerate(per_tick) if n > 0]
        self.assertTrue(all(b - a >= window / TICK_MS for a, b in zip(sends, sends[1:])), sends)

    def test_strike_and_final_pose_are_kept_through_grouping(self):
        self.ready('A')
        self.relayed()
        log = {}
        self.gesture('aim')
        self.collect(1, log)                                     # aim publié, fenêtre ouverte
        self.gesture('strike')
        self.gesture('idle')                                     # strike remplacé avant d'être publié
        self.collect(10, log)
        for c in ('A', 'B'):
            self.assertEqual(log[c], ['aim', 'strike', 'idle'])
        self.assertEqual(self.r('stats.kept'), 1)
        self.assertGreaterEqual(self.r('stats.keptMaxDelay'), 0)

    def test_several_npcs_grouped_in_one_message_per_client(self):
        self.ready('A')
        self.relayed()
        self.run_lua('return LivingKnox.Bodies.spawn({}, 104, 103, 0)')
        self.gesture('aim')
        self.gesture('guard', npc='lk-2')
        self.h.tick(1)
        msgs = self.anim_msgs()
        self.assertEqual(sorted(m['to'] for m in msgs), ['A', 'B'])   # un message par client
        for m in msgs:
            self.assertEqual(sorted(m['args']['d']), ['lk-1', 'lk-2'])
        self.h.pump()
        self.assertEqual(self.h.eval('B', 'LivingKnox.Anim.gestureOf("lk-2")'), 'guard')


class BudgetTests(RelayBase):
    clients = ('A', 'B', 'C01', 'C02', 'C03', 'C04')

    def setUp(self):
        super().setUp()
        for i, c in enumerate(self.clients[2:]):
            self.h.move_player(c, 98 + i, 100, 0)               # tous dans le rayon
        self.run_lua('LivingKnox.Config.RELAY.MAX_PER_TICK = 2')

    def tearDown(self):
        self.run_lua('LivingKnox.Config.RELAY.MAX_PER_TICK = 16')
        super().tearDown()

    def test_budget_per_tick_respected_and_rest_deferred_in_order(self):
        self.ready('A')
        self.relayed()
        self.run_lua('LivingKnox.Relay.resetStats()')
        log = {}
        self.gesture('aim')
        per_tick = self.collect(4, log)
        self.assertEqual(per_tick, [2, 2, 2, 0])                  # 6 clients, 2 par image, aucun oubli
        self.assertEqual(sorted(log), sorted(self.clients))
        self.assertTrue(all(seq == ['aim'] for seq in log.values()), log)
        self.assertEqual(self.r('stats.maxPerTick'), 2)
        self.assertEqual(self.r('stats.deferred'), 4 + 2)          # 4 puis 2 clients reportés
        # Changement pendant un retard : le client différé reçoit l'état courant (rien de figé ni de perdu).
        log = {}
        self.gesture('guard')
        self.collect(1, log)
        self.gesture('crouch')
        per_tick = self.collect(8, log)
        self.assertTrue(all(n <= 2 for n in per_tick), per_tick)
        for c in self.clients:
            self.assertEqual(log[c][-1], 'crouch', log)
            self.assertEqual(self.h.eval(c, 'LivingKnox.Anim.gestureOf("lk-1")') if c in ('A', 'B') else 'crouch',
                             'crouch')

    def test_important_gesture_reaches_every_deferred_client_before_the_next(self):
        self.ready('A')
        self.relayed()
        log = {}
        self.gesture('strike')
        self.collect(1, log)                                      # 2 clients servis, 4 différés
        self.gesture('idle')
        self.collect(12, log)
        for c in self.clients:
            self.assertEqual(log[c], ['strike', 'idle'], log)


class RangeTests(RelayBase):
    clients = ('A', 'B', 'C01')

    def test_client_entering_gets_the_current_state_and_leaving_gets_gone(self):
        self.ready('A')
        self.gesture('aim')
        self.relayed()
        self.assertEqual(self.h.eval('B', 'LivingKnox.Anim.gestureOf("lk-1")'), 'aim')
        log = {}
        self.collect(self.cfg('SCAN_EVERY') + 1, log)
        self.assertNotIn('C01', log)                              # loin : rien
        self.h.move_player('C01', 100, 100, 0)
        self.collect(self.cfg('SCAN_EVERY') + 1, log)
        self.assertEqual(log['C01'], ['aim'])                     # entré : état courant, une fois
        self.h.move_player('C01', 0, 0, 0)
        self.collect(self.cfg('SCAN_EVERY') + 1, log)
        self.assertEqual(log['C01'], ['aim', 'gone'])             # sorti : { gone }
        self.gesture('guard')
        self.collect(4, log)
        self.assertEqual(log['C01'], ['aim', 'gone'])             # plus rien tant qu'il est loin
        self.assertEqual(log['B'][-1], 'guard')

    def test_forgotten_npc_sends_gone_to_its_holders(self):
        self.ready('A')
        self.gesture('aim')
        self.relayed()
        log = {}
        self.run_lua('LivingKnox.Bodies.despawn("lk-1", true)')
        self.collect(self.cfg('SCAN_EVERY') + 1, log)
        self.assertEqual(log.get('B'), ['gone'])
        self.assertIsNone(self.r('items["lk-1"]'))
        self.assertEqual(self.h.eval('B', 'LivingKnox.Anim.gestureOf("lk-1")'), 'idle')


class MeterTests(RelayBase):
    def test_traffic_counters_per_client_and_per_second(self):
        self.ready('A')
        self.gesture('aim')
        self.relayed()
        self.h.tick(12)                                           # seconde complète écoulée
        st = self.r('stats')
        self.assertGreaterEqual(st.maxMsgsPerSec, 2)
        self.assertGreaterEqual(st.second.ms, 1000)
        self.assertGreater(st.maxBytesPerSec, 0)
        self.assertEqual(st.byClient.A.msgs, st.byClient.B.msgs)
        lines = [line for line in self.lk() if 'gesture relay:' in line]
        self.assertTrue(lines, self.lk())
        self.assertRegex(lines[0], r'gesture relay: \d+ msg, \d+ B in \d+ ms \(A \d+/\d+B, B \d+/\d+B\)')


class SoloRelayTests(RelayBase):
    mode = 'solo'

    def test_solo_unchanged_direct_call_no_message(self):
        self.h.load('solo', RELAY)
        self.npc()
        self.gesture('aim')
        self.h.tick(5)
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.r('stats.touched'), 0)
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'aim')


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_source(self):
        import re
        text = (LUA / RELAY).read_text(encoding='utf-8')
        code = re.sub(r'--[^\n]*', '', text)
        self.assertTrue(all(ord(ch) < 128 for ch in code))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertNotIn('LKProbe', text)


if __name__ == '__main__':
    unittest.main()
