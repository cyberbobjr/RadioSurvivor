"""Défense ciblée et décision sur la trêve (E09-T06, ADR B10).

    python tests/test_incidents.py

Banc lupa (Lua 5.1, `next` retiré comme dans Kahlua) : vrai serveur du carnet (`RS_Carnet_Server.lua`), vrais
`RS_Factions.lua` et `RS_Incidents.lua`, moteur Living Knox réel (registres, `LK_Hostility`, `LK_Decisions`,
`LK_Relations`) et vrai pont hors ligne (`RS_OFFLINE_INTENT=incident:<décision>[:<catégorie>]`, drapeau du banc qui
tient lieu d'un modèle, jamais tiré d'un texte) ; doublure fidèle de la faction vanilla de `tests/test_factions.py`.
Les coups sont publiés comme `LK_Bodies.onHitZombie` le fait (fait `memberHit`), la mort comme `LK_Bodies.onZombieDead`
(fait `npcDied`). Critères de l'ADR B10 : agresseur et membre innocent présents ensemble, joueur tiers, deux agressions
rapprochées, réponse tardive, pont indisponible ; l'accord change une seule fois par décision valide.
Doublures seulement : ne prouve ni l'API Java ni le réseau.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, LK_WORLD, convert, protocol
from test_factions import FACTION_DOUBLE
from test_protocol import start_bridge, pump, lua_list

SETTLE = 1100   # F.INCIDENT.SETTLE_MS shortened to 1000 by the bench
RETRY = 1100    # F.INCIDENT.RETRY_MS shortened to 1000


class IncidentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-incidents-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, name, intent='incident:maintain', bridge=True, clients=('alice', 'bob', 'carol', 'dave')):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(FACTION_DOUBLE)
        sim.server.rt.execute(LK_WORLD)
        for c in clients:
            sim.add_client(c)
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.F = self.rt.eval("require('RadioSurvivor/RS_Factions')")
        self.H = self.rt.eval('LivingKnox.Hostility')
        self.D = self.rt.eval('LivingKnox.Decisions')
        self.gid = self.g.LK_GROUP
        # Short delays: the offline bridge ignores a request sent more than 10 s ahead of its own clock, and the bench
        # clock only moves forward.
        self.rt.execute("local F = require('RadioSurvivor/RS_Factions') F.INCIDENT.SETTLE_MS = 1000 "
                        "F.INCIDENT.RETRY_MS = 1000")
        # Faction "North": alice owner, bob and carol members; dave is a third player without faction.
        self.rt.execute('NORTH = FACTION_CREATE("North", "alice", {"bob", "carol"})')
        self.poll()
        ok, why, _ = self.F.conclude(self.g.PLAYERS['alice'], self.gid, 'truce',
                                     self.rt.table_from({'team': self.team(), 'revision': 0}),
                                     self.rt.table_from({'character': self.cid('alice')}))
        self.assertTrue(ok, why)
        if bridge:
            self.process = start_bridge(sim.path, intent)
        return sim

    def poll(self, ms=2100):
        self.sim.clock.offset += ms
        self.sim.tick()

    def cid(self, name):
        return self.sim.character(name)

    def team(self):
        return self.F.idOf(self.g.PLAYERS['alice'])

    def agreement(self):
        return convert(self.F.agreementOf(self.gid, self.team()))

    def open_incident(self):
        found = [convert(i) for i in lua_list(self.F.incidents()) if i.state == 'open']
        return found[0] if found else None

    def hit(self, name, npc=None, category='melee'):
        npc = npc or self.g.LK_MATE
        self.rt.execute(f'LivingKnox.publish("memberHit", {{ group = LK_GROUP, npc = "{npc}", player = PLAYERS["{name}"], '
                        f'u = "{name}", category = "{category}", weapon = "Base.Axe", ms = getTimestampMs() }})')

    def target(self, name, npc=None):
        res = self.H.chooseTarget(self.gid, npc or self.g.LK_MATE, self.rt.table_from(
            [self.rt.table_from({'u': name, 'key': self.cid(name), 'd': 2})]))
        t = res.target
        return (t.action, t.reason) if t else None

    def incident_requests(self):
        return [r for r in self.server.pending.values() if r.kind == 'npc_incident']

    def logs(self):
        return [self.g.LOGS[i] for i in range(1, len(self.g.LOGS) + 1)]

    def halos(self, name):
        return [h for h in lua_list(self.sim.clients[name].g.PLAYERS[name].halos) if 'Incident' in h]

    def answered(self):
        self.assertTrue(pump(lambda: not self.incident_requests(), [self.sim.tick]), 'no reply to the incident')

    def test_aggressor_alone_loses_protection_innocent_and_third_player_unchanged(self):
        self.world('defence')
        gid, mate = self.gid, self.g.LK_MATE
        self.assertTrue(self.F.covered(gid, self.cid('bob')))
        self.assertIsNone(self.target('bob'))
        third = self.target('dave')
        self.hit('bob')
        inc = self.open_incident()
        self.assertEqual((inc['group'], inc['team'], inc['revision'], inc['count']), (gid, self.team(), 1, 1))
        self.assertEqual(inc['authors'], {self.cid('bob'): 'bob'})
        self.assertEqual(inc['victims'], {mate: True})
        self.assertEqual(inc['agreement'], self.agreement()['id'])
        # Immediate targeted defence, without waiting for the model: bob only.
        self.assertFalse(self.F.covered(gid, self.cid('bob')))
        self.assertTrue(self.H.isIncidentAuthor(gid, self.cid('bob'), mate))
        self.assertEqual(self.target('bob'), ('attack', 'incident'))
        self.assertTrue(self.F.covered(gid, self.cid('carol')), 'innocent member of the team lost its protection')
        self.assertIsNone(self.target('carol'))
        self.assertEqual(self.target('dave'), third, 'third player affected')
        # Both present together: the choice of the member picks bob, never carol.
        res = self.H.chooseTarget(gid, mate, self.rt.table_from([
            self.rt.table_from({'u': 'carol', 'key': self.cid('carol'), 'd': 1}),
            self.rt.table_from({'u': 'bob', 'key': self.cid('bob'), 'd': 4})]))
        self.assertEqual([(d.u, d.reason) for d in lua_list(res.list)], [('bob', 'incident')])
        # The agreement keeps its state until a valid decision.
        a = self.agreement()
        self.assertEqual((a['kind'], a['revision']), ('truce', 1))
        # A member defending itself against bob does not hold a pending agreement back.
        self.rt.execute(f'LivingKnox.Decisions.state.members["{mate}"] = {{ b = "fight", p = 1, rule = "threat", '
                        f'key = "pbob", why = "attack player bob", start = 0, untilMin = 999999 }}')
        self.D.markEvaluated(mate)
        self.D.markEvaluated(self.g.LK_LEADER)
        self.poll()
        self.assertEqual(self.agreement()['state'], 'applicable')
        # Third player hitting: no incident for him.
        self.assertIsNone(self.F.incidentFact(gid, self.cid('dave'), 'hit', self.rt.table_from({'npc': mate}))[0])

    def test_two_close_aggressions_one_incident_one_decision(self):
        self.world('close', 'incident:maintain')
        self.hit('bob')
        self.hit('bob', category='firearm')
        self.poll(500)
        self.assertEqual(self.incident_requests(), [], 'decision asked before the facts settled')
        inc = self.open_incident()
        self.assertEqual((inc['revision'], inc['count'], [f['fact'] for f in inc['facts'].values()]),
                         (2, 2, ['hit', 'shot']))
        self.poll(SETTLE)
        [req] = self.incident_requests()
        req = convert(req)
        self.assertEqual((req['character'], req['npc']), ('group', self.server.find(self.g.LK_LEADER).id))
        self.assertIn('hit your people 1 time(s), shot at your people 1 time(s)', req['text'])
        self.assertEqual(req['context']['incident']['agreement'], 'truce')
        self.assertEqual(sorted(req['context']['choices']), ['break', 'maintain', 'repair'])
        self.assertNotIn(self.cid('bob'), req['text'] + str(req['context']), 'notebook key sent to the bridge')
        system = protocol.prompt(req, [])[0]['content']
        self.assertIn('Decide what becomes of the agreement', system)
        self.answered()
        a = self.agreement()
        self.assertEqual((a['kind'], a['state'], a['revision'], a['decision']['choice']), ('truce', 'applicable', 2,
                                                                                            'maintain'))
        self.assertIsNone(self.open_incident())
        self.assertTrue(self.F.covered(self.gid, self.cid('bob')), 'maintained: bob covered again')
        name = self.server.ensure(self.g.LK_LEADER).groupName
        for player in ('alice', 'bob', 'carol'):
            self.assertEqual(self.halos(player), [f'IGUI_RS_Incident_maintain|{name}'], player)
        self.assertEqual(self.halos('dave'), [])
        # Nothing asked again: one decision only.
        self.poll(SETTLE)
        self.assertEqual(self.incident_requests(), [])
        self.assertEqual(self.agreement()['revision'], 2)

    def test_late_reply_after_a_new_aggression_is_refused_then_asked_again(self):
        self.world('late', 'incident:break')
        self.hit('bob')
        self.poll(SETTLE)
        [req] = self.incident_requests()
        rid = req.id
        self.hit('carol', npc=self.g.LK_LEADER)  # a second author before the reply
        self.assertTrue(pump(lambda: not any(r.id == rid for r in self.incident_requests()), [self.sim.tick]))
        self.assertTrue(any('refused: incident revision changed' in line for line in self.logs()), self.logs())
        a = self.agreement()
        self.assertEqual((a['kind'], a['revision']), ('truce', 1), 'late reply applied')
        inc = self.open_incident()
        self.assertEqual(sorted(inc['authors']), sorted([self.cid('bob'), self.cid('carol')]))
        self.assertFalse(self.F.covered(self.gid, self.cid('carol')))
        # Asked again after the retry delay, on the new revision: one break, applied once.
        self.poll(RETRY)
        self.assertEqual(self.incident_requests(), [])
        self.poll(RETRY)
        [again] = self.incident_requests()
        self.assertEqual(len(convert(again)['context']['incident']['authors']), 2)
        self.answered()
        a = self.agreement()
        self.assertEqual((a['kind'], a['state'], a['revision']), ('none', 'broken', 2))
        for name in ('alice', 'bob', 'carol'):
            self.assertFalse(self.F.covered(self.gid, self.cid(name)), name)
        self.assertEqual(len(self.halos('alice')), 1)
        self.assertTrue(self.halos('alice')[0].startswith('IGUI_RS_Incident_break|'))
        # A broken agreement may be negotiated again from nothing.
        neg = self.F.negotiation(self.g.PLAYERS['alice'], self.gid)
        self.assertEqual((neg.current, neg.revision), ('none', 2))

    def test_bridge_unavailable_keeps_defence_without_break(self):
        self.world('nobridge', bridge=False)
        self.rt.execute("require('RadioSurvivor/RS_Config').REQUEST_TIMEOUT_MS = 1000")
        self.hit('bob')
        self.poll(SETTLE)
        self.assertEqual(len(self.incident_requests()), 1)
        self.poll(1100)
        self.assertEqual(self.incident_requests(), [])
        self.assertTrue(any('npc_incident' in line and 'refused: no reply' in line for line in self.logs()), self.logs())
        a = self.agreement()
        self.assertEqual((a['kind'], a['revision']), ('truce', 1), 'automatic change without the bridge')
        self.assertIsNotNone(self.open_incident())
        self.assertFalse(self.F.covered(self.gid, self.cid('bob')), 'defence dropped without a decision')
        self.assertEqual(self.target('bob'), ('attack', 'incident'))
        self.assertTrue(self.F.covered(self.gid, self.cid('carol')))
        self.poll(1100)  # next notebook check: the request is gone, the decision is asked again after RETRY_MS
        self.assertEqual(self.incident_requests(), [], 'asked again before the retry delay')
        self.poll(RETRY)
        self.assertEqual(len(self.incident_requests()), 1, 'not asked again once the delay is over')
        self.rt.execute("require('RadioSurvivor/RS_Config').REQUEST_TIMEOUT_MS = 150000")
        # The bridge comes back: the pending request is answered, one decision.
        self.process = start_bridge(self.sim.path, 'incident:repair:medical')
        self.answered()
        a = self.agreement()
        self.assertEqual((a['kind'], a['revision'], a['repair']['category'], a['repair']['quantity']),
                         ('truce', 2, 'medical', self.F.REPAIR_QUANTITY))
        self.assertTrue(self.F.covered(self.gid, self.cid('bob')))
        name = self.server.ensure(self.g.LK_LEADER).groupName
        # The getText double of the bench shows the first argument only (tests/test_protocol.py).
        self.assertEqual(self.halos('carol'), [f'IGUI_RS_Incident_repair|{name}'])

    def test_riposte_kill_and_no_revenge_on_the_team(self):
        self.world('riposte', bridge=False)
        mate = self.g.LK_MATE
        # The member is aiming at carol (fight state of the cascade): her blow is a riposte, not an aggression.
        self.rt.execute(f'LivingKnox.Decisions.state.members["{mate}"] = {{ b = "fight", p = 1, rule = "threat", '
                        f'key = "pcarol", why = "attack player carol", start = 0, untilMin = 999999 }}')
        self.hit('carol')
        self.assertIsNone(self.open_incident())
        self.assertTrue(self.F.covered(self.gid, self.cid('carol')))
        # bob kills the member (killer identified by LK_Bodies.deathCause): one incident, fact kill.
        self.rt.execute('LivingKnox.Decisions.state.members["' + mate + '"] = nil')
        self.rt.execute(f'LivingKnox.publish("npcDied", {{ npc = "{mate}", cause = "melee", killer = "bob", '
                        f'group = LK_GROUP, member = "m-2", x = 12, y = 0, z = 0 }})')
        inc = self.open_incident()
        self.assertEqual([f['fact'] for f in inc['facts'].values()], ['kill'])
        self.assertEqual(inc['authors'], {self.cid('bob'): 'bob'})
        # Seen by a witness too (LK_Hostility.record, witnessed): the same kill counts once.
        self.H.record(self.gid, self.cid('bob'), 'kill', self.rt.table_from({'witnessed': True}))
        self.assertEqual(self.open_incident()['count'], 1)
        # The other members of the covered team stay covered (no target, whatever the kill), bob is the target.
        for name in ('alice', 'carol'):
            self.assertIsNone(self.target(name, self.g.LK_LEADER), name)
        self.assertEqual(self.target('bob', self.g.LK_LEADER), ('attack', 'incident'))
        # Two valid replies on the same incident: the agreement changes once.
        inc = self.open_incident()
        expect = self.rt.table_from({'revision': inc['revision'], 'agreementRevision': 1})
        ok, why, a, _ = self.F.decideIncident(inc['id'], expect, 'maintain', '', None)
        self.assertTrue(ok, why)
        self.assertEqual((a.revision, a.kind), (2, 'truce'))
        self.assertEqual(self.F.decideIncident(inc['id'], expect, 'break', '', None)[:2], (False, 'incident closed'))
        self.assertEqual((self.agreement()['revision'], self.agreement()['kind']), (2, 'truce'))
        self.assertEqual(self.F.decideIncident('inc-404', expect, 'repair', 'gold', None)[:2], (False, 'incident closed'))

    def test_bridge_contract_for_incident(self):
        base = {'kind': 'npc_incident', 'id': 'r-1-npc-1', 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'order': 1,
                'revision': 1, 'language': 'FR', 'channel': 'say', 'character': 'group', 'personality': {}, 'offers': {},
                'text': 'Incident', 'context': {'incident': {'agreement': 'truce'},
                                                'choices': {'maintain': {}, 'break': {},
                                                            'repair': {'categories': ['food', 'medical'],
                                                                       'quantity': 5}}}}
        r = protocol.bounded_reply(base, {'text': 'Ok.', 'intent': 'repair', 'offer': 'medical'})
        self.assertEqual((r['intent'], r['offer']), ('repair', 'medical'))
        self.assertEqual(protocol.bounded_reply(base, {'text': 'Ok.', 'intent': 'break', 'offer': ''})['intent'], 'break')
        for bad in ({'intent': 'repair', 'offer': 'gold'}, {'intent': 'maintain', 'offer': 'food'},
                    {'intent': 'negotiate', 'offer': 'truce'}, {'intent': 'offer', 'offer': ''}):
            with self.assertRaises(ValueError):
                protocol.bounded_reply(base, dict(bad, text='Ok.'))
        no_break = dict(base, context={'choices': {'maintain': {}}})
        with self.assertRaises(ValueError):
            protocol.bounded_reply(no_break, {'text': 'Ok.', 'intent': 'break', 'offer': ''})
        out, why = protocol.model_reply(base, '{"text": "Fini.", "intent": "repair", "offer": "gold"}')
        self.assertEqual((out['intent'], why), ('none', 'inadmissible reparation'))
        self.assertEqual(protocol.offline(base, 'incident:repair:medical')['offer'], 'medical')
        self.assertEqual(protocol.offline(base, 'incident:break')['intent'], 'break')
        self.assertEqual(protocol.offline(base, '')['intent'], 'maintain')
        self.assertIn('Speak in French', protocol.prompt(base, [])[0]['content'])
        # Request envelope accepted by the bridge.
        payload = protocol.encode(dict(base, version=2, sent=1)).hex()
        value = protocol.unpack_request({'id': base['id'], 'kind': 'npc_incident', 'payload': payload})
        self.assertEqual(value['kind'], 'npc_incident')


if __name__ == '__main__':
    unittest.main(verbosity=2)
