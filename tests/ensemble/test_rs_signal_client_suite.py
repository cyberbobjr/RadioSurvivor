"""Banc hors jeu de la suite en jeu ca.mission.signal.client (E11-T07, CA_MissionSignalSuite.lua) et de ses étapes client
(RST_PeerChecksSignal.lua).

    python RadioSurvivor/tests/ensemble/test_rs_signal_client_suite.py

Serveur dédié et deux clients du banc du carnet (test_carnet.Simulation : machines lupa séparées, réseau direct) :
alice est le demandeur, bob le second client. Réels : moteur RST (RST.lua, RST_Steps.lua), la suite et ses étapes
(RST_PeerChecks.lua carnet.send, RST_PeerChecks2.lua map.zones, RST_PeerChecksSignal.lua), CA_NotebookServer.lua et
CA_NotebookClient.lua (commandes accept, report, claim du carnet), gabarit CA_MissionSignal.lua et son écouteur, CA_MapZones.lua
sur les clients. Doublures : Signal Smoke (tests/commun/signalsmoke_double.py), métagrille et carte (SCOUT_GRID, MAP_DOUBLE de
test_carnet), PNJ du faux fournisseur (corps 2001) à la place du PNJ de test Living Knox (RST.SignalClientSuite.requester
remplacé), paquets d'objets (sendAddItemToContainer / sendRemoveItemFromContainer : copie de l'objet dans l'inventaire
du client propriétaire, comme le paquet du jeu).
La suite passe sur les doublures et échoue sur chaque défaut injecté (DEFECTS) : signal hors des heures compté, cercle
absent chez le demandeur, cercle montré au second client, réclamation sans objet (autorité), objets jamais reçus par le
client. Ne prouve ni l'API Java (paquets d'objets, carte du monde, Signal Smoke réel) ni le solo : la campagne réelle
reste nécessaire.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
bench_paths.use('radiosurvivor', 'livingknox')  # tests that check both mods together (D09)
from test_carnet import MAP_DOUBLE, SCOUT_GRID, TESTS_SHARED, Simulation, convert
from bench_game import lua_list

ROOT_LK = Path(__file__).resolve().parents[2] / 'Contents/mods/batman_LivingKnox/42.21/media/lua'
REQUESTER, OTHER = 'alice', 'bob'
SUITE = 'ca.mission.signal.client'
TEST_NAME = ('requester client: accept, circle on its map only, signal outside the window ignored, report and claim')

# Toutes les machines : mod de développement sur le chemin des modules, suite et étapes chargées. Les fonctions du
# banc écrites en Python (horloge, joueur local) sont des userdata pour Lua : RST et RST_Steps testent
# type(...) == "function", d'où des fonctions Lua qui les appellent. Le rapport d'étapes des clients n'est pas écrit
# (écrivain de fichier du banc sans writeln) : simple ligne d'erreur au journal du client.
RST_LOAD = r'''
local clock, localPlayer = getTimestampMs, getPlayer
getTimestampMs = function() return clock() end
if localPlayer ~= nil then getPlayer = function() return localPlayer() end end
require "RST/RST"
RST.clock = getTimestampMs
require "RST/RST_Steps"
require "RST/suites/CA_MissionSignalSuite"
'''

# Autorité : monde de test (balise world), demandeur = fiche du PNJ 2001 du banc et son corps.
SERVER = r'''
local grid = getWorld():getMetaGrid()
getWorld = function() return {getGameMode = function() return setmetatable({}, {__tostring = function()
    return 'Multiplayer' end}) end, getWorld = function() return 'rstest-signal' end,
    getMetaGrid = function() return grid end} end
RST.SignalClientSuite.requester = function(t, p, Signal, c, after)
    local fiche = CoreAI.notebookServer.ensure(2001)
    return after(t, { fiche = fiche, body = CoreAI.notebookServer.objects[fiche.id] })
end
'''

# E11-T21 (chaque mod paie ses missions) : la vraie source de récompense de Living Knox inscrite au moteur commun, comme
# en jeu avec les deux mods ; le PNJ 2001 du faux fournisseur n'est membre d'aucun groupe Living Knox (LivingKnox.Groups
# absent) : règle de Living Knox seul, le lot annoncé avec la mission. Chaque délégation est comptée.
LK_SOURCE = r'''
package.path = [[%s/?.lua;%s/?.lua;]] .. package.path
require "LivingKnox/LK_MissionRewards"
local M = require 'CoreAI/CA_Missions'
local source = M.npcReward()
LK_DELEGATED = {}
M.registerNpcReward({ lot = source.lot, claim = function(store, m, player, character, token, npcId)
    LK_DELEGATED[#LK_DELEGATED + 1] = npcId
    return source.claim(store, m, player, character, token, npcId)
end })
''' % ((ROOT_LK / 'shared').as_posix(), (ROOT_LK / 'server').as_posix())

DEFECT_LUA = {
    'any_hour': ('server', "require('CoreAI/CA_MissionSignal').inWindow = function() return true end"),
    'no_circle': (REQUESTER, "require('CoreAI/CA_MapZones').zones = function() return {added = 0, removed = 0} end"),
    'empty_claim': ('server', r'''
        local M = require 'CoreAI/CA_Missions'
        M.claim = function(store, m, player, character)
            m.claimedBy, m.claimedName, m.revision = character, 'nobody', m.revision + 1
            return true
        end'''),
}


class SignalClientSuiteBench(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-signal-client-')
        self.path = Path(self.tmp.name)
        self.lost_items = False
        self.misroute = False

    def tearDown(self):
        self.tmp.cleanup()

    def build(self, defect=''):
        sim = Simulation(self.path / (defect or 'nominal'))
        self.sim = sim
        sim.add_client(REQUESTER); sim.add_client(OTHER)
        sim.server.rt.execute(SCOUT_GRID)
        sim.server.g.scoutHouse(5001, 20, 12, 8, 8)    # too close to the requester
        sim.server.g.scoutHouse(5002, 100, 10, 10, 10)  # reachable
        for c in sim.clients.values():
            c.rt.execute(MAP_DOUBLE)
        sim.select(REQUESTER)
        shared = TESTS_SHARED.as_posix() + '/?.lua'
        for game in [sim.server, *sim.clients.values()]:
            game.rt.execute(f'package.path = [[{shared};]] .. package.path')
            game.rt.execute(RST_LOAD)
        sim.server.rt.execute(SERVER)
        sim.server.rt.execute(LK_SOURCE)
        self.rawequal = sim.server.rt.eval('rawequal')
        sim.server.g.sendAddItemToContainer = self.item_added
        sim.server.g.sendRemoveItemFromContainer = self.item_removed
        deliver = sim.deliver_to_client

        def routed(*call):
            # Defect: the second client gets the notebook snapshots of the requester in place of its own.
            if self.misroute and len(call) == 4 and call[2] == 'snapshot':
                if call[0].username == OTHER:
                    return
                if call[0].username == REQUESTER:
                    deliver(sim.server.g.PLAYERS[OTHER], *call[1:])
            deliver(*call)
        sim.server.g.sendServerCommand = routed
        self.misroute = defect == 'circle_elsewhere'
        self.lost_items = defect == 'lost_items'
        if defect in DEFECT_LUA:
            machine, code = DEFECT_LUA[defect]
            game = sim.server if machine == 'server' else sim.clients[machine]
            game.rt.execute(code)
        return sim

    # Paquets d'objets du serveur : l'objet copié (même type, même id) dans l'inventaire du client propriétaire.
    def owner(self, container):
        for name in self.sim.clients:
            if self.rawequal(self.sim.server.g.PLAYERS[name].inv, container):
                return self.sim.clients[name]
        return None

    def item_added(self, container, it):
        client = self.owner(container)
        if client is None or self.lost_items:
            return
        local = client.g.getPlayer()
        local.inv.AddItem(local.inv, client.g.item(it.kind, it.id))

    def item_removed(self, container, it):
        client = self.owner(container)
        if client is None:
            return
        local = client.g.getPlayer()
        found = local.inv.getItemWithID(local.inv, it.id)
        if found is not None:
            local.inv.Remove(local.inv, found)

    def run_suite(self, frames=4000):
        sim = self.sim
        alice = sim.server.g.PLAYERS[REQUESTER]
        started = sim.server.rt.eval(f'function(p) return RST.start("{SUITE}", '
                                     '{ attach = false, ctx = { player = p } }) end')(alice)
        self.assertTrue(started)
        for _ in range(frames):
            running = sim.server.rt.eval('RST.step()')
            for c in sim.clients.values():
                c.g.fire('OnTick')
            sim.tick()
            sim.clock.offset += 100
            if not running:
                break
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: r for r in report.results.values()}
        self.assertEqual(list(results), [TEST_NAME])
        r = results[TEST_NAME]
        notes = list(r.notes.values()) if r.notes else []
        return r.status, r.message or '', notes

    def kinds(self, inv):
        return [it.kind for it in lua_list(inv['items'])]

    def assert_restored(self):
        sim = self.sim
        self.assertEqual([m for m in sim.state().missions.values() if m.template == 'signal'], [])
        npc = sim.state().npcs[next(iter(sim.state().npcs))]
        self.assertIsNone(npc.mission)
        self.assertEqual(len(list(lua_list(sim.server.g.SS_LISTENERS))), 1, 'listener of the template only')
        self.assertEqual(self.kinds(sim.server.g.PLAYERS[REQUESTER].inv), [], 'reward left on the authority')
        self.assertEqual(self.kinds(sim.clients[REQUESTER].g.getPlayer().inv), [], 'reward left on the client')
        self.assertEqual(sim.reputation().outcomes is None or len(list(sim.reputation().outcomes.keys())), 0)
        char = sim.character(REQUESTER)
        self.assertEqual(list(sim.state().characters[char].knownMissions.keys()), [])
        for c in sim.clients.values():
            self.assertEqual([convert(s) for s in lua_list(c.rt.eval('mapSymbols()'))], [], 'circle left on a map')

    # ------------------------------------------------------------------------------------------------ tests

    def test_mp_accept_circle_hours_report_and_claim(self):
        self.build()
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''), notes)
        self.assertTrue(any('client alice: map.zones: mission active here: 1 ring(s) 1 label(s)' in n for n in notes),
                        notes)
        self.assertTrue(any('client bob: map.zones: mission closed here: 0 ring(s) 0 label(s)' in n for n in notes),
                        notes)
        self.assertTrue(any('client alice: carnet.signal.send: claim sent: row success' in n
                            and 'gained 20 x Base.Bullets9mm' in n for n in notes), notes)
        # The claim of the engine NPC went through Living Knox's source once, with its engine id (incarnation).
        self.assertEqual(list(self.sim.server.g.LK_DELEGATED.values()), [2001])
        self.assert_restored()

    def test_without_second_client_the_absence_is_noted(self):
        self.build()
        sim = self.sim
        sim.server.rt.execute(f'PLAYERS["{OTHER}"] = nil')
        status, message, notes = self.run_suite()
        self.assertEqual((status, message), ('PASS', ''))
        self.assertTrue(any('no other client online' in n for n in notes), notes)

    # ------------------------------------------------------------------------------------------------ defects

    DEFECTS = {
        'any_hour': 'signal outside the window counted',
        'no_circle': "client alice: step 'map.zones' FAIL",
        'circle_elsewhere': "client bob: step 'map.zones' FAIL",
        'empty_claim': 'the claim gave no item on the authority',
        'lost_items': 'items of the claim received in the inventory of the requester client',
    }

    def test_each_defect_fails_the_suite(self):
        for defect, expected in self.DEFECTS.items():
            with self.subTest(defect=defect):
                self.build(defect)
                status, message, _ = self.run_suite()
                self.assertEqual(status, 'FAIL', message)
                self.assertIn(expected, message)


if __name__ == '__main__':
    unittest.main(verbosity=2)
