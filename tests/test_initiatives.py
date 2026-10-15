"""Initiatives de parole des PNJ (E08-T03) : vrai serveur du carnet, vrai moteur Living Knox (registres, API, corps,
parole LK11-T04), vrai fournisseur RS_LivingKnox.lua, deux clients, vrai pont hors ligne (pont factice) ; lupa, Lua 5.1.

    python tests/test_initiatives.py

Couvre : une observation récente d'une fiche incarnée et entendue ouvre UNE demande npc_initiative sans texte de
joueur dans la file du PNJ, la réplique passe par LivingKnox.Speech chez les deux joueurs qui l'entendent ; aucune
répétition du même événement (sortie puis retour dans la portée, reconnexion, mémoire remise à zéro) ; quotas de chaque
niveau de l'option enum (délai par PNJ en heures de jeu, plafond serveur par heure réelle, plafond commun MAX_PER_HOUR) ;
PNJ occupé (coup reçu < 30 s, combat, sommation, alerte) : rien, et réponse caduque si la situation change ; pont arrêté :
aucune nouvelle demande, réplique de gabarit ou silence ; contrat du pont (npc_protocol). Doublures du jeu : ne prouve
pas l'API Java réelle.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from test_carnet import LK_WORLD, Simulation, convert
from test_protocol import ROOT, lua_list, pump, start_bridge

sys.path.insert(0, str(ROOT / 'bridge'))
import npc_protocol as protocol  # noqa: E402
import radio_bridge as bridge_module  # noqa: E402

LOAD = r'''
require 'LivingKnox/LK_Speech'
require 'LivingKnox/LK_Encounters'
SPEECH_SENT = {}
local send = sendServerCommand
sendServerCommand = function(p, module, command, args)
    if module == 'LivingKnox' and command == 'speech' then
        SPEECH_SENT[#SPEECH_SENT + 1] = {to = p.username, id = args.u.id, t = args.u.t, k = args.u.k}
    end
    return send(p, module, command, args)
end
'''


class InitiativeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-init-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, level=3, name='init'):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        sim.add_client('bob')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.g.SandboxVars.RadioSurvivor.InitiativeFrequency = level
        self.rt.execute(LOAD)
        self.server = self.g.RS_CarnetServer
        self.obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        self.init = self.rt.eval("require('RadioSurvivor/RS_Initiatives')")
        self.init.reset()
        # E08-T04: no conversation between the nearby fiches of this bench (range 0): initiatives only.
        self.rt.eval("require('RadioSurvivor/RS_Conversations')").CFG.RANGE = 0
        # One pass per carnet tick (1 s): the bench clock stays close to real time (the bridge refuses requests sent
        # more than 10 s in the future).
        self.init.CFG.EVERY_MS = 0
        self.fiche = self.server.ensure(self.g.LK_LEADER)
        self.sim.tick()  # scan: body of the fiche mapped
        return sim

    def record(self, fiche=None, fact='weather', subject='storm', day=3, place='everywhere'):
        key, reason = self.obs.record((fiche or self.fiche).id, self.rt.table_from(
            dict(fact=fact, subject=subject, day=day, place=place)))
        self.assertIn(reason, ('ok', 'upgraded'))
        return key

    def step(self, ms=1001):
        self.sim.clock.offset += ms
        self.sim.tick()

    def initiatives(self):
        return [r for r in lua_list(self.server.pending) if r.kind == 'npc_initiative']

    def said(self):
        return [convert(s) for s in lua_list(self.g.SPEECH_SENT)]

    def test_one_initiative_heard_by_both_players_through_the_speech_channel(self):
        sim = self.world()
        alice = sim.character('alice')
        self.server.ensure(self.g.LK_LEADER)
        sim.command('alice', 'select', incarnation=self.g.LK_LEADER)  # alice already knows the NPC (contact)
        key = self.record()
        self.step()
        reqs = self.initiatives()
        self.assertEqual(len(reqs), 1)
        req = reqs[0]
        self.assertEqual((req.character, req.text, req.npc), ('system', None, self.fiche.id))
        self.assertEqual(convert(req.offers), {})
        self.assertEqual((req.event.fact, req.event.subject, req.event.place), ('weather', 'storm', 'everywhere'))
        self.assertEqual(convert(req.context)['audience'], 2)
        self.assertNotIn('group', convert(req.context).get('group') or {}, 'group name given to strangers')
        mine = lua_list(self.init.times)
        self.assertEqual(len(mine), 1)
        self.assertIn(mine[0], lua_list(self.server.times), 'initiative outside the common cap')
        # Same event: never a second request, even later or after the players leave and come back.
        self.step()
        self.assertEqual(len(self.initiatives()), 1)
        self.process = start_bridge(sim.path)
        self.assertTrue(pump(lambda: not self.initiatives(), [lambda: self.step(1001)]), 'initiative never answered')
        lines = self.said()
        self.assertEqual(sorted(s['to'] for s in lines), ['alice', 'bob'])
        self.assertEqual(len({s['id'] for s in lines}), 1, 'one line, one id for every listener')
        self.assertTrue(lines[0]['t'])
        self.assertLessEqual(len(lines[0]['t'].encode('utf-8')), protocol.INITIATIVE_REPLY_BYTES)
        history = lua_list(sim.state().characters[alice].contacts[self.fiche.id].history)
        self.assertEqual(history[-1].text, lines[0]['t'])
        bob = sim.character('bob')
        self.assertIsNone(sim.state().characters[bob].contacts[self.fiche.id], 'contact created by an initiative')
        for name in ('alice', 'bob'):
            sim.server.g.PLAYERS[name].x = 200
        self.step()
        for name in ('alice', 'bob'):
            sim.server.g.PLAYERS[name].x = 10
        self.step(); self.step()
        self.assertEqual(len(self.initiatives()), 0)
        self.assertEqual(len(self.said()), 2)
        self.assertIsNotNone(sim.state().initiatives.done[self.fiche.id + '|' + key], 'event not kept in the state')

    def test_quotas_of_each_level(self):
        sim = self.world(level=1)
        others = [self.server.ensure(self.g[n]) for n in ('LK_MATE', 'LK_RAIDER', 'LK_LONER')]
        self.step()
        fiches = [self.fiche] + others
        for f in fiches:
            self.record(f)
        for _ in range(6):
            self.step()
        self.assertEqual(len(self.initiatives()), 0, 'disabled level opened an initiative')
        # Rare: 2 LLM requests per real hour for the server, the others fall back (weather: silence).
        self.g.SandboxVars.RadioSurvivor.InitiativeFrequency = 2
        for _ in range(6):
            self.step()
        self.assertEqual(len(self.initiatives()), 2)
        self.assertEqual(convert(self.init.stats)['silent'], 2)
        # One per NPC per game day: a new event of the same NPC within the day opens nothing.
        self.sim.server.g.PLAYERS.alice.x = 10
        self.server.pending = self.rt.table()
        self.sim.clock.offset += 3600001
        self.record(self.fiche, subject='blizzard')
        self.step()
        self.assertEqual(len(self.initiatives()), 0, 'rare level: second initiative of the NPC within a game day')
        # Normal: one per NPC per game hour, 6 per real hour.
        self.g.SandboxVars.RadioSurvivor.InitiativeFrequency = 3
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 1
        for f in fiches:
            self.record(f, subject='tropical_storm')
        for _ in range(6):
            self.step()
        self.assertEqual(len(self.initiatives()), 4)
        # Frequent: half an hour is enough, 12 per real hour; the common cap MAX_PER_HOUR applies to all.
        self.server.pending = self.rt.table()
        self.g.SandboxVars.RadioSurvivor.InitiativeFrequency = 4
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 0.5
        self.record(self.fiche, fact='helicopter', subject='helicopter')
        self.step()
        self.assertEqual(len(self.initiatives()), 1)
        self.server.pending = self.rt.table()
        cap = self.rt.eval("require('RadioSurvivor/RS_Config')").MAX_PER_HOUR
        now = self.g.getTimestampMs()
        for _ in range(cap):
            self.server.times[len(self.server.times) + 1] = now
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 0.5
        self.record(self.fiche, fact='power_cut', subject='power')
        self.step()
        self.assertEqual(len(self.initiatives()), 0, 'common cap MAX_PER_HOUR ignored')

    def test_busy_npc_never_speaks_and_a_stale_reply_is_dropped(self):
        sim = self.world()
        api = self.rt.eval('LivingKnox.API')
        leader = self.g.LK_LEADER
        self.record()
        hits = self.rt.eval('LivingKnox.Bodies.lastHits')
        hits[leader] = self.rt.table_from({'ms': self.g.getTimestampMs()})
        self.assertEqual(api.engaged(leader), (True, 'hit'))
        self.step()
        self.assertEqual(len(self.initiatives()), 0, 'NPC hit less than 30 s ago spoke')
        # 30 s later (the clock of the bench stays close to real time: the bridge refuses requests from the future).
        hits[leader] = self.rt.table_from({'ms': self.g.getTimestampMs() - 30001})
        self.assertFalse(api.engaged(leader))
        enc = self.rt.eval('LivingKnox.Encounters.state.list')
        enc['x'] = self.rt.table_from({'npc': leader, 'stage': 1})
        self.assertEqual(api.engaged(leader), (True, 'warning'))
        self.step()
        self.assertEqual(len(self.initiatives()), 0, 'NPC warning a player spoke')
        enc['x'] = None
        orders = self.rt.eval('LivingKnox.Combat and LivingKnox.Combat.orders')
        if orders is not None:
            orders[leader] = self.rt.table()
            self.assertEqual(api.engaged(leader), (True, 'combat'))
            orders[leader] = None
        self.step()
        self.assertEqual(len(self.initiatives()), 1)
        # The situation changes while the bridge writes: the late reply is refused, nothing is said.
        hits[leader] = self.rt.table_from({'ms': self.g.getTimestampMs()})
        self.process = start_bridge(sim.path)
        self.assertTrue(pump(lambda: not self.initiatives(), [lambda: self.step(1001)]))
        self.assertEqual(self.said(), [])
        self.assertEqual(convert(self.init.stats)['stale'], 1)

    def test_bridge_stopped_silence(self):
        """E08-T09 : pont arrêté, budget épuisé ou option « Désactivées » : aucune réplique de gabarit, silence."""
        sim = self.world()
        alice = sim.character('alice')
        mate = self.server.ensure(self.g.LK_MATE)
        provider = self.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        barks = []
        provider.bark = lambda *args: barks.append(args)  # never called (E08-T09)
        self.step()
        self.record()
        self.step()
        self.assertEqual(len(self.initiatives()), 1)
        self.sim.clock.offset += 151000
        self.sim.tick()
        self.assertEqual(len(self.initiatives()), 0)
        self.assertTrue(self.init.bridge.down)
        self.assertTrue(any('initiatives and conversations stay silent' in line for line in lua_list(self.g.LOGS)))
        # A known character comes back (former template greeting) and a storm: no request, nothing said.
        silent = convert(self.init.stats)['silent']
        self.record(mate, fact='player_return', subject=alice, place='area-0-0')
        self.step()
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 1
        self.record(mate, subject='blizzard')
        self.step()
        self.assertEqual(len(lua_list(self.server.pending)), 0, 'request sent to a stopped bridge')
        self.assertEqual(self.said(), [], 'line said without the bridge')
        self.assertEqual(barks, [], 'Provider.bark called by the initiatives')
        self.assertEqual(convert(self.init.stats)['silent'], silent + 2)
        self.assertNotIn('template', convert(self.init.stats))
        # A reply of the bridge (a talk) brings the initiatives back: the next event asks the model.
        self.init.observe(None, True)
        self.assertFalse(self.init.bridge.down)
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 1
        self.record(mate, subject='tropical_storm')
        self.step()
        self.assertEqual(len(self.initiatives()), 1)
        # Budget spent (common cap): silence again, nothing said, no request.
        self.server.pending = self.rt.table()
        cap = self.rt.eval("require('RadioSurvivor/RS_Config')").MAX_PER_HOUR
        now = self.g.getTimestampMs()
        for _ in range(cap):
            self.server.times[len(self.server.times) + 1] = now
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 1
        self.record(mate, fact='helicopter', subject='helicopter')
        self.step()
        self.assertEqual((len(self.initiatives()), self.said(), barks), (0, [], []))
        # Option Off: no initiative at all, even a bridge back with budget.
        self.server.times = self.rt.table()
        self.g.SandboxVars.RadioSurvivor.InitiativeFrequency = 1
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 1
        self.record(mate, fact='power_cut', subject='power')
        self.step()
        self.assertEqual((len(self.initiatives()), self.said(), barks), (0, [], []))

    def test_no_repetition_after_reconnection_or_memory_reset(self):
        sim = self.world()
        self.record()
        self.step()
        self.assertEqual(len(self.initiatives()), 1)
        self.server.pending = self.rt.table()
        # Reconnection (player objects bound again) and a reset of the module memory: the event stays consumed.
        sim.clients['bob'].g.RS_CarnetClient.hello()
        self.init.reset()
        for _ in range(3):
            self.step()
        self.assertEqual(len(self.initiatives()), 0)
        # An old observation (more than one game hour) never opens one.
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 2
        self.record(subject='blizzard')
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 1.5
        self.step()
        self.assertEqual(len(self.initiatives()), 0)


def count_times(server):
    return len(lua_list(server.times))


class InitiativeProtocolTests(unittest.TestCase):
    def request(self, **change):
        req = {'version': 2, 'kind': 'npc_initiative', 'id': 'run-1-npc-1', 'world': 'w', 'run': 'run', 'npc': 'npc-1',
               'character': 'system', 'order': 1, 'revision': 1, 'sent': 1, 'channel': 'say', 'language': 'FR',
               'personality': {'style': 'Direct', 'sociability': 4}, 'context': {'name': 'Ann', 'audience': 2},
               'offers': {}, 'event': {'fact': 'weather', 'subject': 'storm', 'day': 3, 'place': 'everywhere',
                                       'source': 'seen', 'hops': 0}}
        req.update(change)
        req = {k: v for k, v in req.items() if v is not None}
        return {'id': req['id'], 'kind': req['kind'], 'payload': protocol.encode(req).hex()}

    def test_contract(self):
        req = protocol.unpack_request(self.request())
        self.assertEqual(req['event']['fact'], 'weather')
        for bad in ({'text': 'hello'}, {'character': 'char-1'}, {'offers': {'x': {'kind': 'scout'}}},
                    {'event': None}, {'event': {'fact': 'rumour', 'subject': 's', 'day': 1, 'place': 'p',
                                                'source': 'seen', 'hops': 0}}):
            with self.assertRaises(ValueError, msg=str(bad)):
                protocol.unpack_request(self.request(**bad))
        reply = protocol.bounded_reply(req, {'text': 'x' * 400, 'intent': 'none', 'offer': ''})
        self.assertLessEqual(len(reply['text'].encode('utf-8')), protocol.INITIATIVE_REPLY_BYTES)
        for bad in ({'intent': 'offer', 'offer': 'first_aid_v1'}, {'intent': 'accept'}):
            with self.assertRaises(ValueError):
                protocol.bounded_reply(req, dict({'text': 'Hey.', 'offer': ''}, **bad))
        self.assertEqual(protocol.model_reply(req, '{"text": "Sale temps.", "intent": "offer", "offer": "x"}')[0]
                         ['intent'], 'none')
        messages = protocol.prompt(req, [])
        self.assertEqual(messages[-1], {'role': 'user', 'content': protocol.INITIATIVE_TURN})
        self.assertIn('Recent event: day 3, everywhere: a weather change', messages[0]['content'])
        self.assertIn('Speak in French', messages[0]['content'])
        self.assertEqual(protocol.memory_turn(req), protocol.INITIATIVE_TURN)
        self.assertEqual(protocol.offline(req)['intent'], 'none')

    def test_bridge_memory_keeps_a_marker_never_a_player_text(self):
        with tempfile.TemporaryDirectory(prefix='rs-init-mem-') as folder:
            conv = bridge_module.NpcConversations(Path(folder))
            req = protocol.unpack_request(self.request())
            reply = conv.propose({'OFFLINE': '1'}, req)
            self.assertTrue(conv.acknowledge({'request': req['id'], 'world': 'w', 'run': 'run', 'npc': 'npc-1',
                                              'order': 1, 'revision': 1, 'status': 'accepted', 'applied': {}}))
            self.assertEqual(conv.load(req)['messages'], [{'role': 'user', 'content': protocol.INITIATIVE_TURN},
                                                          {'role': 'assistant', 'content': reply['text']}])
            # An offer or acceptance applied to an initiative is never acknowledged.
            second = protocol.unpack_request(self.request(id='run-2-npc-1', order=2))
            conv.propose({'OFFLINE': '1'}, second)
            self.assertFalse(conv.acknowledge({'request': second['id'], 'world': 'w', 'run': 'run', 'npc': 'npc-1',
                                               'order': 2, 'revision': 1, 'status': 'accepted',
                                               'applied': {'offer': 'first_aid_v1'}}))


if __name__ == '__main__':
    unittest.main(verbosity=2)
