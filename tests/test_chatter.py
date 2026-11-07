"""Bavardages entre membres d'un groupe à leur foyer (E18-T32) : vrai serveur du carnet, vrai moteur Living Knox
(registres, corps, parole), vrai fournisseur RS_LivingKnox.lua, vraies conversations (LK_Conversations), vrai pont hors
ligne ; lupa, Lua 5.1.

    python tests/test_chatter.py

Couvre : ouverture au foyer devant un joueur, 2 à 4 répliques selon le sujet, sujet tiré de l'état du groupe (besoin
urgent d'abord), délai par groupe de l'option, rien loin du foyer ni sans auditeur, rien sans pont ni option
« Désactivées » (et rien consommé), une observation à transmettre passe avant, intervention d'un joueur, contrat du
pont (sujet fermé, sans carte d'événement). Doublures du jeu : ne prouve pas l'API Java réelle.
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

LOAD = r'''
require 'LivingKnox/LK_Speech'
require 'LivingKnox/LK_Encounters'
SPEECH_SENT = {}
local send = sendServerCommand
sendServerCommand = function(p, module, command, args)
    if module == 'LivingKnox' and command == 'speech' then
        SPEECH_SENT[#SPEECH_SENT + 1] = {to = p.username, id = args.u.id, t = args.u.t, k = args.u.k, npc = args.u.npc}
    end
    return send(p, module, command, args)
end
-- The home of the settlers where their two bodies stand (x 12 and 14, y 10).
assert(LivingKnox.Groups.setHome(LK_GROUP, 13, 10, 0))
'''


class ChatterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-chatter-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, listen=True):
        """listen False: alice out of earshot too, so the first pass opens nothing."""
        sim = Simulation(self.path / 'chatter', living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        sim.add_client('bob')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.rt.execute(LOAD)
        self.server = self.g.RS_CarnetServer
        self.conv = self.rt.eval("require('LivingKnox/LK_Conversations')")
        self.init = self.rt.eval("require('LivingKnox/LK_Initiatives')")
        self.chat = self.rt.eval("require('LivingKnox/LK_Chatter')")
        self.obs = self.rt.eval("require('LivingKnox/LK_Observations')")
        for module in (self.conv, self.init, self.chat):
            module.reset()
        self.conv.CFG.EVERY_MS = 0
        self.conv.CFG.TURN_GAP_MS = 0
        self.conv.CFG.MAX_MS = 3600000
        self.chat.CFG.EVERY_MS = 0
        self.rt.execute("require('LivingKnox/LK_Chatter').draw = function(n) return n end")  # last topic: leader
        self.leader = self.server.ensure(self.g.LK_LEADER)
        self.mate = self.server.ensure(self.g.LK_MATE)
        self.away('bob')
        if not listen:
            self.away('alice')
        self.step()
        return sim

    def near(self, name='alice'):
        self.g.PLAYERS[name].x = 10

    def away(self, *names):
        for name in names:
            self.g.PLAYERS[name].x = 200

    def step(self, ms=1001):
        self.sim.clock.offset += ms
        self.sim.tick()

    def requests(self):
        return [r for r in lua_list(self.server.talk.pending) if r.kind == 'npc_converse']

    def said(self):
        return [convert(s) for s in lua_list(self.g.SPEECH_SENT)]

    def last(self):
        data = self.server.talk.data.chatter
        return convert(data.last) if data else {}

    def test_chatter_at_home_lines_by_topic_and_group_delay(self):
        sim = self.world()
        alice = sim.character('alice')
        sim.command('alice', 'select', incarnation=self.g.LK_MATE)  # alice knows the mate (contact)
        reqs = self.requests()
        self.assertEqual(len(reqs), 1, 'no chatter opened at home in front of alice')
        req = reqs[0]
        context = convert(req.context)
        self.assertEqual(context['topic']['subject'], 'leader')
        self.assertEqual(context['topic']['detail'], self.leader.name)
        self.assertEqual((context['role'], context['turn'], context['turns']),
                         ('teller', 1, convert(self.chat.TURNS)['leader']))
        self.assertIsNone(req.event, 'observation card in a chatter request')
        self.assertIn(lua_list(self.conv.times)[0], lua_list(self.server.talk.times), 'line outside the common cap')
        self.assertEqual(self.last(), {self.g.LK_GROUP: self.g.WORLD_HOURS})
        # The request passes the bridge contract.
        plain = {k: v for k, v in convert(req).items() if v is not None}
        checked = protocol.unpack_request({'id': plain['id'], 'kind': plain['kind'],
                                           'payload': protocol.encode(plain).hex()})
        self.assertEqual(checked['context']['topic'], {'subject': 'leader', 'detail': self.leader.name})
        self.process = start_bridge(sim.path)
        cap = self.sim.clock.offset + 5000

        def close():
            self.sim.clock.offset = min(self.sim.clock.offset + 1001, cap)
            self.sim.tick()
        self.assertTrue(pump(lambda: convert(self.conv.stats)['ended'] >= 1, [close], timeout=60), 'chatter never ended')
        lines = self.said()
        self.assertEqual(len(lines), convert(self.chat.TURNS)['leader'], lines)
        self.assertEqual({s['to'] for s in lines}, {'alice'})
        self.assertEqual([s['npc'] for s in lines], [self.g.LK_LEADER, self.g.LK_MATE, self.g.LK_LEADER])
        # Existing contacts only: the mate's line in alice's notebook, no contact created for the leader.
        history = [h.text for h in lua_list(sim.state().characters[alice].contacts[self.mate.id].history)]
        self.assertEqual(history[-1:], [lines[1]['t']])
        self.assertIsNone(sim.state().characters[alice].contacts[self.leader.id])
        # Group delay (Normal: one game hour): nothing more this hour, a new chatter the next one.
        for _ in range(3):
            self.step()
        self.assertEqual(convert(self.chat.stats)['opened'], 1)
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 1
        self.step()
        self.assertEqual(convert(self.chat.stats)['opened'], 2)

    def test_nothing_away_from_home_or_without_listener(self):
        self.world(listen=False)
        self.rt.execute('assert(LivingKnox.Groups.setHome(LK_GROUP, 10637, 9412, 0))')
        self.near()
        self.step()
        self.assertEqual(self.requests(), [], 'chatter away from home')
        self.rt.execute('assert(LivingKnox.Groups.setHome(LK_GROUP, 13, 10, 0))')
        self.away('alice')
        self.step()
        self.assertEqual(self.requests(), [], 'chatter nobody hears')
        self.assertEqual(self.last(), {}, 'group delay consumed without chatter')

    def test_no_bridge_or_option_off_silence_nothing_consumed(self):
        self.world(listen=False)
        self.near()
        self.init.bridge.down = True
        self.step()
        self.assertEqual(self.requests(), [], 'chatter while the bridge is stopped')
        self.init.bridge.down = False
        self.rt.execute('SandboxVars.LivingKnox = {InitiativeFrequency = 1}')
        self.step()
        self.assertEqual(self.requests(), [], 'chatter with the option Off')
        self.assertEqual(self.last(), {})
        self.rt.execute('SandboxVars.LivingKnox = {InitiativeFrequency = 3}')
        self.step()
        self.assertEqual(len(self.requests()), 1, 'no chatter once the bridge and the option allow it')

    def test_observation_to_pass_on_goes_first(self):
        self.world(listen=False)
        key, why = self.obs.record(self.leader.id, self.rt.table_from(
            dict(fact='weather', subject='storm', day=3, place='everywhere')))
        self.assertEqual(why, 'ok')
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 2  # no initiative competes
        self.near()
        self.step()
        reqs = self.requests()
        self.assertEqual(len(reqs), 1)
        self.assertIsNotNone(reqs[0].event, 'chatter opened before the observation conversation')
        self.assertIsNone(convert(reqs[0].context).get('topic'))
        self.assertEqual(convert(self.chat.stats)['opened'], 0)

    def test_chatter_goes_on_at_home_and_stops_when_one_leaves(self):
        """Essai en jeu du 2026-11-07 : un membre parti à 9 cases hors de vue, toujours au foyer, coupait le bavardage.
        Il dure tant que les deux restent au foyer ; il s'arrête quand l'un en sort."""
        self.world()
        conv = self.conv.of(self.leader.id)
        self.assertIsNotNone(conv)
        bodies = self.rt.eval('LivingKnox.Bodies.bound')
        bodies[self.g.LK_MATE].x = 22   # 9 squares from the leader, still within the home radius
        bodies[self.g.LK_MATE].visible = False
        conv.waiting = None             # no line pending: the next turn checks the participants
        self.step()
        self.assertIsNotNone(self.conv.active[conv.id], 'chatter cut while both stay at home')
        bodies[self.g.LK_MATE].x = 40   # out of the home
        conv.waiting = None
        self.step()
        self.assertIsNone(self.conv.active[conv.id], 'chatter going on after a member left home')

    def test_player_joins_the_chatter(self):
        self.world()
        conv = self.conv.of(self.leader.id)
        self.assertIsNotNone(conv, 'no chatter running')
        self.assertIsNotNone(conv.chatter)
        talk = convert(self.conv.talkContext(conv, self.mate.id))
        self.assertEqual(talk['partner'], self.leader.name)
        self.assertIn('Answer them, ignore them', talk['note'])

    def test_topic_from_the_group_state(self):
        self.world()
        topics = self.rt.eval('''function(stock, morale, weather)
            local Ch = require('LivingKnox/LK_Chatter')
            local World = require('RadioSurvivorCore/RC_WorldFacts')
            LivingKnox.Stock = {needs = function() return stock end}
            World.weather = function() return weather end
            local g = LivingKnox.Groups.get(LK_GROUP)
            local saved = g.morale
            g.morale = morale
            local list, urgent = Ch.topics(LK_GROUP, g)
            local picked = Ch.topic(LK_GROUP, g)
            g.morale = saved
            local out = {}
            for i, t in ipairs(list) do out[i] = t.subject .. '=' .. t.detail end
            return table.concat(out, ','), urgent and urgent.subject or '', picked.subject
        end''')
        low = self.rt.table_from({'needs': self.rt.table_from([self.rt.table_from({'c': 'food', 'status': 'low'})])})
        listed, urgent, picked = topics(low, 20, 'rain')
        self.assertEqual(listed, 'needs=food low,morale=low,weather=rain,leader=' + self.leader.name)
        self.assertEqual((urgent, picked), ('', 'leader'))
        critical = self.rt.table_from({'needs': self.rt.table_from([self.rt.table_from({'c': 'water',
                                                                                         'status': 'critical'})])})
        listed, urgent, picked = topics(critical, 80, None)
        self.assertEqual(listed, 'needs=water critical,morale=high,leader=' + self.leader.name)
        self.assertEqual((urgent, picked), ('needs', 'needs'))
        turns = convert(self.chat.TURNS)
        self.assertEqual(sorted(turns.values()), [2, 3, 3, 4])

    def test_bridge_contract_and_prompt(self):
        base = {'version': 2, 'kind': 'npc_converse', 'id': 'run-1-npc-1', 'world': 'w', 'run': 'run',
                'npc': 'npc-1', 'character': 'system', 'order': 1, 'revision': 1, 'sent': 1, 'channel': 'say',
                'language': 'EN', 'personality': {'style': 'Direct', 'sociability': 4}, 'offers': {},
                'context': {'name': 'Ann', 'audience': 1, 'partner': 'Paul', 'role': 'teller', 'turn': 1,
                            'turns': 3, 'lines': {}, 'topic': {'subject': 'leader', 'detail': 'Ruth'}}}

        def unpack(**change):
            req = dict(base, **change)
            return protocol.unpack_request({'id': req['id'], 'kind': req['kind'],
                                            'payload': protocol.encode(req).hex()})
        value = unpack()
        self.assertEqual(value['context']['topic'], {'subject': 'leader', 'detail': 'Ruth'})
        system = protocol.prompt(value, [])[0]['content']
        self.assertIn("Topic of the chat: your group's leader, Ruth.", system)
        self.assertNotIn('Subject of the conversation', system)
        self.assertNotIn('unverified memory', system)
        self.assertEqual(protocol.offline(value)['text'], 'Listen, I have to tell you something.')
        with self.assertRaises(ValueError):
            unpack(event={'fact': 'weather', 'subject': 'storm', 'day': 3, 'place': 'everywhere'})
        for topic in ({'subject': 'politics', 'detail': 'x'}, {'subject': 'leader'}, 'leader',
                      {'subject': 'leader', 'detail': 'Ruth', 'extra': 1}):
            with self.assertRaises(ValueError, msg=str(topic)):
                unpack(context=dict(base['context'], topic=topic))
        with self.assertRaises(ValueError):   # a detail longer than the server bound is refused, never cut
            unpack(context=dict(base['context'], topic={'subject': 'needs', 'detail': 'x' * 200}))
        self.assertEqual(set(protocol.CHATTER_SUBJECTS), set(convert_turns()))


def convert_turns():
    from lupa import LuaRuntime
    rt = LuaRuntime(unpack_returned_tuples=True)
    source = (ROOT / 'Contents/mods/batman_LivingKnox/42.21/media/lua/server/LivingKnox/LK_Chatter.lua')
    text = source.read_text(encoding='utf-8')
    start = text.index('Ch.TURNS = ')
    line = text[start:text.index('\n', start)]
    rt.execute('Ch = {}; ' + line)
    return list(rt.eval('Ch.TURNS').keys())


if __name__ == '__main__':
    unittest.main(verbosity=2)
