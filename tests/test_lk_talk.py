"""File des demandes de parole des PNJ portée par Living Knox (E18-T17).

    python tests/test_lk_talk.py

Banc lupa (Lua 5.1) sur le vrai `RS_Carnet_Server.lua` et le vrai `LK_Talk.lua` : le code de la parole est chez Living
Knox et ne requiert aucun module de RadioSurvivor ; voies `npc` et `acks` à leur place dans le fichier ; acquittements
et délais des initiatives relus après un redémarrage dans le fichier privé de Living Knox, plus dans l'état du carnet ;
numéros d'ordre tenus par la file ; RadioSurvivor seul n'a aucune file. Doublures : ne prouve ni le réseau ni Java.
"""
from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, Clock

ROOT = Path(__file__).resolve().parents[1]
LK = ROOT / 'Contents/mods/batman_LivingKnox/42.21/media/lua/server/LivingKnox'
RS = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server'
FILES = ('LK_TalkHost.lua', 'LK_Talk.lua', 'LK_Initiatives.lua', 'LK_Conversations.lua', 'LK_Incidents.lua')


class SourceTests(unittest.TestCase):
    def test_speech_code_requires_nothing_of_radiosurvivor(self):
        for name in FILES:
            text = (LK / name).read_text(encoding='utf-8')
            self.assertEqual(re.findall(r'''require\s*\(?\s*['"]RadioSurvivor/[^'"]+''', text), [], name)
            self.assertNotIn('RS_CarnetServer', text, name)

    def test_old_modules_are_gone_from_radiosurvivor(self):
        for name in ('RS_Conversations.lua', 'RS_Initiatives.lua', 'RS_Incidents.lua'):
            self.assertFalse((RS / 'RadioSurvivor' / name).exists(), name)

    def test_lanes_keep_their_place_in_the_requests_file(self):
        text = (LK / 'LK_Talk.lua').read_text(encoding='utf-8')
        self.assertIn('Transport.register("npc", { order = 20 })', text)
        self.assertIn('Transport.register("acks", { order = 30 })', text)
        lanes = (RS / 'RadioSurvivor/RS_BridgeLanes.lua').read_text(encoding='utf-8')
        self.assertIn("T.register('radio', { order = 10", lanes)
        self.assertIn("T.register('lastPages', { order = 40 })", lanes)
        self.assertNotIn("T.register('npc'", lanes)


class StateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-talk-')
        self.path = Path(self.tmp.name) / 'w'
        self.clock = Clock()

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, new_world=False):
        return Simulation(self.path, clock=self.clock, new_world=new_world)

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
        self.assertEqual(again.server.rt.eval('#require("RadioSurvivorCore/RC_Transport").acks'), 1)

    def test_a_new_world_starts_empty(self):
        sim = self.world(True)
        sim.talk().data.initiatives.last['npc-1'] = 12
        sim.talk().dirty = True
        self.assertTrue(sim.talk().save())
        fresh = Simulation(Path(self.tmp.name) / 'w', clock=self.clock, new_world=True)
        self.assertIsNone(fresh.talk().data.initiatives.last['npc-1'])

    def test_order_of_a_speaker_is_numbered_by_the_queue(self):
        sim = self.world(True)
        talk = sim.talk()
        npc = sim.server.rt.eval('{id = "npc-9", incarnation = 2001, order = 4, revision = 2, personality = {}}')
        req = talk.enqueue(npc, 'npc_enrich', 'system', 'x', 'EN', sim.server.rt.table(), sim.server.rt.table())
        self.assertEqual((req.order, req.revision, npc.order), (5, 2, 5))
        self.assertTrue(req.id.endswith('-5-npc-9'))


class AloneTests(unittest.TestCase):
    def test_notebook_without_living_knox_has_no_queue(self):
        with tempfile.TemporaryDirectory(prefix='lk-talk-') as tmp:
            sim = Simulation(Path(tmp) / 'alone', provider=False)
            self.assertIsNone(sim.server.g.RS_CarnetServer.talk)
            sim.clock.offset += 2000
            sim.tick()
            self.assertEqual(sim.server.errors() if hasattr(sim.server, 'errors') else [], [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
