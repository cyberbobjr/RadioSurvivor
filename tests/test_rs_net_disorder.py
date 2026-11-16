"""Étapes RST de la parole d'un PNJ (lk.npctalk) sous réseau en désordre (E19-T06, ADR banc mimétique D06).

    python RadioSurvivor/tests/test_rs_net_disorder.py

Serveur dédié et deux clients du banc (tests/harness.py), vrai moteur RST (RST.lua, RST_Steps.lua,
RST_PeerChecks.lua : étape client « carnet.talk »), vrai RST_CarnetHelpers N.talk sur le serveur (E21-T11 : aide du mod
de test du commun, montage sans RadioSurvivor), vrai CA_NotebookClient.lua sur le
client demandeur (Client.talk : commande « talk » du carnet). Doublures : serveur du carnet réduit à sa liste de requêtes
(mise en file puis sauvegarde, comme CA_NotebookServer enqueue) et pont rapide qui répond à l'image suivante du serveur.

Défaut vu en jeu (campagne MP du 2026-11-05, registre docs/annexes/tests/ecarts-banc-jeu.md, catégorie F) : la commande
« talk » et la réponse de l'étape sont deux commandes Lua du même client, fiables mais NON ordonnées
(PacketTypes.java:491, reliability 2) ; la réponse de l'étape arrivée après la requête déjà répondue par le pont, la suite
ne voyait plus la requête (« no npc_talk request »). Rejoué sous tests/net_disorder.py (fifo, lifo, random à trois
graines avec retard) : l'ancien R.talk (a469d1f^) échoue sur les ordres random, l'actuel passe partout.
Ne prouve ni le vrai serveur du carnet ni le pont (tests/test_carnet.py, tests/test_fake_llm.py).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import ROOT, Harness  # noqa: E402
from net_disorder import disorder  # noqa: E402

from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
DEV_LUA = tests_lua('core')
REQUESTER = 'A'
RST_FILES = 'require "RST/RST"; require "RST/RST_Steps"; require "RST/RST_PeerChecks"; require "RST/RST_CarnetHelpers"'

# Client demandeur : le vrai carnet client (CA_NotebookClient.lua, E21-T03) ; Translator : langue du jeu (Translator.getLanguage).
CLIENT = '''
Translator = { getLanguage = function() return { name = function() return "EN" end } end }
require "CoreAI/CA_NotebookClient"
'''

# Serveur : liste des requêtes du carnet (talk.pending), sauvegarde après la mise en file (CA_NotebookServer enqueue :
# S.save()), pont qui répond à l'image suivante (requête retirée de la liste). Suite d'une étape : N.talk.
SERVER = r'''
NOTEBOOK = { store = {}, talk = { pending = {}, refusals = {} } }
SAVES, ANSWERED = 0, {}
NOTEBOOK.store.save = function() SAVES = SAVES + 1 return true end
local n, asked = 0, {}
Events.OnClientCommand.Add(function(module, command, player, args)
    if command ~= "talk" or type(args) ~= "table" then return end
    n = n + 1
    local r = { id = "req" .. n, npc = "npc-1", kind = "npc_talk", text = args.text }
    NOTEBOOK.talk.pending[#NOTEBOOK.talk.pending + 1] = r
    NOTEBOOK.store.save()
    asked[r.id] = true
end)
Events.OnTick.Add(function()
    local pending = NOTEBOOK.talk.pending
    for i = #pending, 1, -1 do
        if asked[pending[i].id] then ANSWERED[#ANSWERED + 1] = pending[i].id table.remove(pending, i) end
    end
end)
RST.suite("bench.npctalk", { tags = { "server" } }, function(s)
    s.test("the npc_talk request of the sentence is seen", function(t)
        local c = { Server = NOTEBOOK, fiche = { id = "npc-1" } }
        RST.CarnetHelpers.talk(t, c, "do you need help?", function(t2, req)
            t2:eq("do you need help?", req.text)
        end)
    end)
end)
'''

START = ('REPORT = nil; assert(RST.start({ suite = "bench.npctalk", tags = { "server" } }, { ctx = { side = "server", '
         f'player = HARNESS.players.{REQUESTER} }}, onDone = function(r) REPORT = r end }}))')


class NpcTalkUnderDisorderTests(unittest.TestCase):
    """N.talk (lk.npctalk, lk.relation ; carnet.talk de lk.conversations...) : requête vue quel que soit l'ordre de livraison."""

    def setUp(self):
        self.h = Harness(lua_roots=[DEV_LUA])
        for m in self.h.machines:
            self.h.load(m, RST_FILES)
        self.h.load(REQUESTER, CLIENT)
        self.h.load('server', SERVER)

    def tearDown(self):
        self.h.close()

    def run_suite(self, frames=600):
        h = self.h
        h.load('server', START)
        for _ in range(frames):
            h.tick()
            h.pump()
            h.advance_ms(84)   # 100 ms par image de jeu (tick_ms 16 + 84)
            if not h.eval('server', 'RST.running()'):
                break
        report = h.eval('server', 'REPORT')
        self.assertIsNotNone(report, 'run not finished')
        return {r.test: (r.status, r.message) for r in report.results.values()}

    def check(self, results):
        self.assertEqual(results, {'the npc_talk request of the sentence is seen': ('PASS', None)})
        self.assertEqual(self.h.eval('server', '#ANSWERED'), 1)

    def test_request_seen_under_network_disorder(self):
        disorder(self, lambda delivery: self.check(self.run_suite()))


if __name__ == '__main__':
    unittest.main(verbosity=2)
