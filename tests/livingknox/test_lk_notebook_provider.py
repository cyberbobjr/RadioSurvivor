"""Living Knox's provider of the notebook of the core mod, always registered (E21-T05, slice 12 of
docs/annexes/conception/carnet-commun-e21.md).

    python tests/livingknox/test_lk_notebook_provider.py

Bench of tests/coreai/test_carnet.py (Simulation, real Living Knox engine and real notebook server of the core mod) with the
core mod and Living Knox only on the module path (Game.WITH_RS = False): the provider LK_NotebookProvider registers in
CA_NPCProvider at OnInitGlobalModData, before the notebook server starts (its speech engine is attached then), on the
server and on a client; the death of an NPC body reaches the notebook server through the provider 'death' event.
Doubles only for the Java API: proves neither the network nor Java.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from test_carnet import LK_SERVER_LOAD, LK_SERVER_STUBS, LK_WORLD, STUBS, Clock, Simulation
from bench_game import Game

# getActivatedMods (LuaManager.java:6065) of a game with the core mod and Living Knox only.
MODS = r'''
getActivatedMods = function()
    local l = {'batman_CoreAI', '\\batman_LivingKnox'}
    return {size = function() return #l end, get = function(_, i) return l[i + 1] end}
end
'''


class NotebookProviderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-provider-')
        patcher = mock.patch.object(Game, 'WITH_RS', False)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.sim = Simulation(Path(self.tmp.name) / 'w', living_knox=True, rs_hooks=False)
        self.sim.server.rt.execute(LK_WORLD)
        self.g, self.rt = self.sim.server.g, self.sim.server.rt

    def tearDown(self):
        self.tmp.cleanup()

    def test_registered_before_the_notebook_server_starts(self):
        # A server of the game with the core mod and Living Knox only (mod list read as the game gives it).
        game = Game('server', Path(self.tmp.name) / 'alone', Clock())
        game.rt.execute(STUBS)
        game.rt.execute(MODS)
        game.rt.execute(LK_SERVER_STUBS)
        game.rt.execute(LK_SERVER_LOAD)
        game.load('server/CoreAI/CA_NotebookServer.lua')
        game.g.fire('OnInitGlobalModData', True)
        provider = game.rt.eval("require('CoreAI/CA_NPCProvider')")
        self.assertEqual((provider.active().name, provider.available()), ('livingknox', True))
        self.assertTrue(game.rt.eval("rawequal(require('CoreAI/CA_NPCProvider').active(), LivingKnox.NpcProvider)"))
        # Registered at OnInitGlobalModData before the notebook server: its speech engine was attached at its start.
        self.assertTrue(game.rt.eval('rawequal(CoreAI.notebookServer.talk, LivingKnox.Talk)'))
        c = self.sim.add_client('alice')
        self.assertEqual(c.rt.eval("require('CoreAI/CA_NPCProvider').active().name"), 'livingknox')
        self.assertTrue(c.g.CoreAI.notebookClient.snapshot.npcProvider)

    def test_npc_death_reaches_the_notebook_server(self):
        self.sim.add_client('alice')
        leader = self.g.LK_LEADER
        self.sim.command('alice', 'select', incarnation=leader)
        server = self.g.CoreAI.notebookServer
        fiche = server.find(leader)
        self.assertIsNotNone(fiche)
        self.assertTrue(fiche.alive)
        body = self.g.LivingKnox.Bodies.bound[leader]
        body.dead = True
        self.g.fire('OnZombieDead', body)
        self.assertFalse(fiche.alive)
        self.assertEqual(fiche.deathAttribution, 'unavailable_server_evidence')
        contact = [r for r in self.sim.clients['alice'].g.CoreAI.notebookClient.snapshot.contacts.values()
                   if r.id == fiche.id][0]
        self.assertFalse(contact.alive)


if __name__ == '__main__':
    unittest.main(verbosity=2)
