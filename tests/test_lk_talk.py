"""File des demandes de parole des PNJ portée par Living Knox (E18-T17).

    python tests/test_lk_talk.py

Banc lupa (Lua 5.1) sur le vrai `CA_NotebookServer.lua` et le vrai `LK_Talk.lua`, mod commun et Living Knox seuls sur
le chemin des modules (E21-T08, Game.WITH_RS = False) : voies `npc` et `acks` à leur place dans le fichier ;
acquittements et délais des initiatives relus après un redémarrage dans le fichier privé de Living Knox, plus dans
l'état du carnet ; numéros d'ordre tenus par la file ; le carnet sans Living Knox n'a aucune file. Doublures : ne
prouve ni le réseau ni Java.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, Clock, protocol
from test_protocol import Game

Game.WITH_RS = False   # E21-T08: core mod and Living Knox only on the module path (one bench per process)

ROOT = Path(__file__).resolve().parents[1]
LK = ROOT / 'Contents/mods/batman_LivingKnox/42.21/media/lua/server/LivingKnox'
FILES = ('LK_TalkHost.lua', 'LK_Talk.lua', 'LK_Initiatives.lua', 'LK_Conversations.lua', 'LK_Incidents.lua')


class SourceTests(unittest.TestCase):
    def test_speech_code_reaches_the_notebook_through_its_host(self):
        for name in FILES:
            self.assertNotIn('CoreAI.notebookServer', (LK / name).read_text(encoding='utf-8'), name)

    def test_lanes_keep_their_place_in_the_requests_file(self):
        text = (LK / 'LK_Talk.lua').read_text(encoding='utf-8')
        self.assertIn('Transport.register("npc", { order = 20 })', text)
        self.assertIn('Transport.register("acks", { order = 30 })', text)


class StateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-talk-')
        self.path = Path(self.tmp.name) / 'w'
        self.clock = Clock()

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, new_world=False):
        return Simulation(self.path, clock=self.clock, new_world=new_world, rs_hooks=False)

    def test_acknowledgements_and_delays_survive_a_restart_outside_the_notebook(self):
        sim = self.world(True)
        talk = sim.talk()
        talk.data.initiatives.last['npc-1'] = 12
        talk.data.conversations.pairs['a|b'] = 3
        req = sim.server.rt.eval('{id = "r-1", world = "w", run = "x", npc = "npc-1", order = 1, revision = 1}')
        talk.acknowledge(req, True)
        self.assertTrue(talk.save())
        self.assertIsNone(sim.state().acks)
        self.assertIsNone(sim.state().initiatives)
        self.assertIsNone(sim.state().conversations)
        again = self.world()
        talk = again.talk()
        self.assertEqual(talk.data.acks[1].request, 'r-1')
        self.assertEqual(talk.data.initiatives.last['npc-1'], 12)
        self.assertEqual(talk.data.conversations.pairs['a|b'], 3)
        self.assertEqual(again.server.rt.eval('#require("CoreAI/CA_Transport").acks'), 1)

    def test_a_new_world_starts_empty(self):
        sim = self.world(True)
        sim.talk().data.initiatives.last['npc-1'] = 12
        sim.talk().dirty = True
        self.assertTrue(sim.talk().save())
        fresh = Simulation(Path(self.tmp.name) / 'w', clock=self.clock, new_world=True, rs_hooks=False)
        self.assertIsNone(fresh.talk().data.initiatives.last['npc-1'])

    def test_order_of_a_speaker_is_numbered_by_the_queue(self):
        sim = self.world(True)
        talk = sim.talk()
        npc = sim.server.rt.eval('{id = "npc-9", incarnation = 2001, order = 4, revision = 2, personality = {}}')
        req = talk.enqueue(npc, 'npc_enrich', 'system', 'x', 'EN', sim.server.rt.table(), sim.server.rt.table())
        self.assertEqual((req.order, req.revision, npc.order), (5, 2, 5))
        self.assertTrue(req.id.endswith('-5-npc-9'))


class ReplyKindTests(unittest.TestCase):
    """LK16-T03 (G-Z01) : un genre de requête s'ajoute par sa ligne dans Talk.REPLY_KINDS, sans toucher à reply."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-talk-')
        self.sim = Simulation(Path(self.tmp.name) / 'w', clock=Clock(), new_world=True, rs_hooks=False)
        self.rt = self.sim.server.rt
        self.rt.execute('''
            local Talk = CoreAI.notebookServer.talk
            PROBE_NPC = { id = "npc-9", incarnation = 2001, order = 0, revision = 2, alive = true, personality = {} }
            Talk.fiche = function(id) if id == "npc-9" then return PROBE_NPC end return nil end
            SERVED = {}
            local function served(req) SERVED[#SERVED + 1] = req.kind Talk.acknowledge(req, true, {}) return true end
            Talk.REPLY_KINDS.npc_probe = { reply = served }
            Talk.REPLY_KINDS.npc_early = { beforeClaim = true, reply = served }
        ''')

    def tearDown(self):
        self.tmp.cleanup()

    def answer(self, kind, intent):
        req = self.rt.eval(f'CoreAI.notebookServer.talk.enqueue(PROBE_NPC, "{kind}", "system", "x", "EN", {{}}, {{}})')
        body = {'version': 2, 'kind': 'npc_reply', 'id': req.id, 'world': req.world, 'run': req.run, 'npc': req.npc,
                'order': req.order, 'revision': req.revision, 'text': 'Noted.', 'intent': intent, 'offer': ''}
        (self.sim.path / 'responses.txt').write_text(f"resp={req.id}\npayload={protocol.encode(body).hex()}\nend\n",
                                                     encoding='utf-8')
        for _ in range(3):
            self.sim.clock.offset += 1001
            self.sim.tick()
        return req

    def served(self):
        return list(self.rt.eval('SERVED').values())

    def test_added_kind_is_served_after_the_intent_checks(self):
        self.answer('npc_probe', 'none')
        self.assertEqual(self.served(), ['npc_probe'])
        refusals = self.rt.eval('CoreAI.notebookServer.talk.refusals')
        self.answer('npc_probe', 'leave_group')                    # intention réservée à npc_talk : refusée
        self.assertEqual(self.served(), ['npc_probe'])
        self.assertEqual(refusals[len(refusals)].reason, 'invalid intent')

    def test_added_kind_before_the_claim_skips_the_speech_intents(self):
        self.answer('npc_early', 'its_own_vocabulary')
        self.assertEqual(self.served(), ['npc_early'])


class AloneTests(unittest.TestCase):
    def test_notebook_without_living_knox_has_no_queue(self):
        with tempfile.TemporaryDirectory(prefix='lk-talk-') as tmp:
            sim = Simulation(Path(tmp) / 'alone', provider=False, rs_hooks=False)
            self.assertIsNone(sim.server.g.CoreAI.notebookServer.talk)
            sim.clock.offset += 2000
            sim.tick()
            self.assertEqual(sim.server.errors() if hasattr(sim.server, 'errors') else [], [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
