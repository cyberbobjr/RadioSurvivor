"""Tests hors jeu du client de requêtes commun de Living Knox (LK20-T06, ADR simplification D06) :
client/LivingKnox/LK_ClientRequest.lua (LivingKnox.ClientRequest).

    python tests/test_lk_client_request.py

Banc tests/harness.py. MP (serveur dédié et clients A, B) : la requête part par sendClientCommand avec le module et
la commande de sa route ; la réponse revient par l'unique abonnement OnServerCommand, aiguillée par module et
commande vers les vues inscrites, dans l'ordre d'inscription (une inscription de même clé remplace l'ancienne).
Solo : relais direct vers LivingKnox[route.server].request, réponse rendue pendant l'appel, refus fabriqué quand
l'autorité ne rend rien, faux quand l'autorité n'est pas chargée ; aucun abonnement OnServerCommand.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

CR = 'LivingKnox.ClientRequest'
ROUTE = '{ module = "LivingKnox", request = "testRequest", server = "TestAuthority" }'


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class MP(unittest.TestCase):
    def setUp(self):
        self.h = Harness(with_rs=False, mode='mp')
        for m in ('server', 'A'):
            self.h.load(m, 'shared/LivingKnox/LK_Core.lua')
        self.h.load('A', 'client/LivingKnox/LK_ClientRequest.lua')
        self.h.load('server', 'GOT = {} Events.OnClientCommand.Add(function(module, command, player, args) '
                              'GOT[#GOT + 1] = { module = module, command = command, n = args.n, op = args.op } end)')
        self.h.load('A', 'SEEN = {}')

    def tearDown(self):
        self.h.close()

    def reply(self, module, command, n):
        self.h.load('server', f'sendServerCommand(getOnlinePlayers():get(0), "{module}", "{command}", {{ n = {n} }})')
        self.h.pump()

    def listen(self, command, key, tag):
        self.h.load('A', f'{CR}.listen("LivingKnox", "{command}", "{key}", function(module, command, args) '
                         f'SEEN[#SEEN + 1] = "{tag}:" .. module .. ":" .. command .. ":" .. args.n end)')

    def test_send_goes_through_send_client_command(self):
        self.assertTrue(self.h.eval('A', f'{CR}.send({ROUTE}, getSpecificPlayer(0), {{ op = "list", n = 7 }}, '
                                         'function() SEEN[#SEEN + 1] = "local" end)'))
        self.h.pump()
        got = lua_list(self.h.eval('server', 'GOT'))
        self.assertEqual([(g.module, g.command, g.op, g.n) for g in got], [('LivingKnox', 'testRequest', 'list', 7)])
        self.assertEqual(lua_list(self.h.eval('A', 'SEEN')), [])     # rien rendu sur place en MP

    def test_reply_dispatched_by_module_and_command_in_registration_order(self):
        self.listen('testReply', 'One', 'one')
        self.listen('testReply', 'Two', 'two')
        self.listen('otherReply', 'Three', 'three')
        self.reply('LivingKnox', 'testReply', 1)
        self.reply('Other', 'testReply', 2)
        self.reply('LivingKnox', 'otherReply', 3)
        self.assertEqual(lua_list(self.h.eval('A', 'SEEN')),
                         ['one:LivingKnox:testReply:1', 'two:LivingKnox:testReply:1', 'three:LivingKnox:otherReply:3'])

    def test_same_key_replaces_the_handler(self):
        self.listen('testReply', 'One', 'old')
        self.listen('testReply', 'One', 'new')
        self.reply('LivingKnox', 'testReply', 4)
        self.assertEqual(lua_list(self.h.eval('A', 'SEEN')), ['new:LivingKnox:testReply:4'])

    def test_failing_handler_does_not_deprive_the_next(self):
        self.h.load('A', f'{CR}.listen("LivingKnox", "testReply", "Bad", function() error("boom") end)')
        self.listen('testReply', 'Good', 'good')
        self.reply('LivingKnox', 'testReply', 5)
        self.assertEqual(lua_list(self.h.eval('A', 'SEEN')), ['good:LivingKnox:testReply:5'])
        self.assertTrue(any('handler Bad failed' in line for line in self.h.logs('A')))

    def test_one_server_command_subscription(self):
        self.assertTrue(self.h.eval('A', 'LivingKnox.handlers["OnServerCommand/ClientRequest.onServerCommand"] ~= nil'))


class Solo(unittest.TestCase):
    def setUp(self):
        self.h = Harness(with_rs=False, mode='solo')
        self.h.load('solo', 'shared/LivingKnox/LK_Core.lua')
        self.h.load('solo', 'client/LivingKnox/LK_ClientRequest.lua')
        self.h.load('solo', 'SEEN = {} RECEIVE = function(reply) SEEN[#SEEN + 1] = reply end')

    def tearDown(self):
        self.h.close()

    def send(self, op='list', n=3):
        return self.h.eval('solo', f'{CR}.send({ROUTE}, getSpecificPlayer(0), {{ op = "{op}", n = {n} }}, RECEIVE)')

    def seen(self):
        return lua_list(self.h.eval('solo', 'SEEN'))

    def test_relay_to_the_authority_reply_given_during_the_call(self):
        self.h.load('solo', 'LivingKnox.TestAuthority = { request = function(player, args) '
                            'return { op = args.op, n = args.n, ok = true, who = player ~= nil } end }')
        self.assertTrue(self.send())
        got = self.seen()
        self.assertEqual(len(got), 1)
        self.assertEqual((got[0].op, got[0].n, got[0].ok, got[0].who), ('list', 3, True, True))

    def test_nil_reply_becomes_a_refusal(self):
        self.h.load('solo', 'LivingKnox.TestAuthority = { request = function() return nil, "bad request" end }')
        self.assertTrue(self.send('open', 9))
        got = self.seen()
        self.assertEqual(sorted(got[0].keys()), ['err', 'n', 'ok', 'op'])
        self.assertEqual((got[0].op, got[0].n, got[0].ok, got[0].err), ('open', 9, False, 'bad request'))

    def test_authority_not_loaded(self):
        self.assertFalse(self.send())
        self.assertEqual(self.seen(), [])

    def test_no_server_command_subscription_in_solo(self):
        self.assertTrue(self.h.eval('solo', 'LivingKnox.handlers["OnServerCommand/ClientRequest.onServerCommand"] '
                                            '== nil'))


if __name__ == '__main__':
    unittest.main()
