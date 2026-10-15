"""Conversations entre deux PNJ proches (E08-T04, ADR B11) : vrai serveur du carnet, vrai moteur Living Knox (registres,
API, corps, parole LK11-T04), vrai fournisseur RS_LivingKnox.lua, deux clients, vrai pont hors ligne ; lupa, Lua 5.1.

    python tests/test_conversations.py

Couvre : transmission silencieuse quand personne n'entend (une par paire et par délai) ; conversation entendue de 4
répliques npc_converse au plus, dites par LivingKnox.Speech aux seuls joueurs qui entendent le locuteur à cet instant ;
le destinataire n'apprend le récit qu'après la première réplique dite (pas à la préparation) ; retour au premier sans
duplication et fin sans boucle ; voisin sans fiche : fiche créée seulement pour un groupe déjà contacté et dans la borne
de 64 fiches ; voisin occupé ou parti : rien d'appris ; pont arrêté : répliques de gabarit smalltalk ; contrat du pont.
Doublures du jeu : ne prouve pas l'API Java réelle.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from test_carnet import LK_WORLD, Simulation, convert, count, native_table
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
        SPEECH_SENT[#SPEECH_SENT + 1] = {to = p.username, id = args.u.id, t = args.u.t, k = args.u.k, npc = args.u.npc}
    end
    return send(p, module, command, args)
end
'''


class ConversationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-conv-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, mate_fiche=True, far=False):
        sim = Simulation(self.path / 'conv', living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        sim.add_client('bob')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.rt.execute(LOAD)
        self.server = self.g.RS_CarnetServer
        self.obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        self.conv = self.rt.eval("require('RadioSurvivor/RS_Conversations')")
        self.init = self.rt.eval("require('RadioSurvivor/RS_Initiatives')")
        self.conv.reset()
        self.init.reset()
        # One pass per carnet tick (1 s); the turns stay one second apart (bench clock close to real time).
        self.conv.CFG.EVERY_MS = 0
        self.conv.CFG.TURN_GAP_MS = 0
        self.conv.CFG.MAX_MS = 3600000  # the bench clock runs one second per pump loop while the bridge starts
        self.leader = self.server.ensure(self.g.LK_LEADER)
        self.mate = self.server.ensure(self.g.LK_MATE) if mate_fiche else None
        if far:
            self.away('alice', 'bob')
        self.step()  # scan: bodies of the fiches mapped
        return sim

    def away(self, *names):
        for name in names:
            self.sim.server.g.PLAYERS[name].x = 200

    def record(self, fiche, fact='weather', subject='storm', day=3, place='everywhere'):
        key, reason = self.obs.record(fiche.id, self.rt.table_from(dict(fact=fact, subject=subject, day=day,
                                                                         place=place)))
        self.assertEqual(reason, 'ok')
        # Older than one game hour: no initiative of the teller competes with the conversation (E08-T03).
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 2
        return key

    def step(self, ms=1001):
        self.sim.clock.offset += ms
        self.sim.tick()

    def requests(self):
        return [r for r in lua_list(self.server.pending) if r.kind == 'npc_converse']

    def keys(self, fiche):
        return {item.key: [s for s in lua_list(item.chain)] for item in lua_list(self.obs.list(fiche.id))}

    def said(self):
        return [convert(s) for s in lua_list(self.g.SPEECH_SENT)]

    def test_silent_transmission_once_per_pair_and_delay(self):
        self.world(far=True)
        key = self.record(self.leader)
        self.step()
        self.assertEqual(self.requests(), [], 'LLM request while nobody hears')
        self.assertEqual(self.keys(self.mate)[key], ['seen', 'heard_from:' + self.leader.id])
        self.assertEqual(self.said(), [])
        self.assertEqual(convert(self.conv.stats)['silent'], 1)
        # A second story of the same teller: the pair waits PAIR_HOURS game hours.
        other = self.record(self.leader, subject='blizzard')
        for _ in range(3):
            self.step()
        self.assertNotIn(other, self.keys(self.mate), 'second transmission within the pair delay')
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + self.conv.CFG.PAIR_HOURS
        self.step()
        self.assertIn(other, self.keys(self.mate))
        # No loop: the story never goes back to its first teller, nothing more to tell between them.
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + self.conv.CFG.PAIR_HOURS
        before = convert(self.conv.stats)
        for _ in range(3):
            self.step()
        self.assertEqual(convert(self.conv.stats), before, 'conversation without anything to tell')
        self.assertEqual(self.keys(self.leader)[key], ['seen'])

    def test_heard_conversation_four_lines_reception_after_first_line(self):
        sim = self.world()
        alice = sim.character('alice')
        sim.command('alice', 'select', incarnation=self.g.LK_MATE)  # alice knows the mate (contact)
        self.away('bob')
        key = self.record(self.leader)
        self.step()
        reqs = self.requests()
        self.assertEqual(len(reqs), 1)
        req = reqs[0]
        self.assertEqual((req.npc, req.character, req.text), (self.leader.id, 'system', None))
        context = convert(req.context)
        self.assertEqual((context['role'], context['turn'], context['turns'], context['partner']),
                         ('teller', 1, 4, self.mate.name))
        self.assertEqual(req.event.subject, 'storm')
        self.assertEqual(len(lua_list(self.conv.times)), 1)
        self.assertIn(lua_list(self.conv.times)[0], lua_list(self.server.times), 'line outside the common cap')
        self.assertNotIn(key, self.keys(self.mate), 'learned when the request was prepared')
        self.process = start_bridge(sim.path)
        # Several requests in a row: the bench clock stays less than 10 s ahead of real time (the bridge refuses
        # requests from the future), so a pass may wait for real time to catch up.
        cap = self.sim.clock.offset + 5000

        def close():
            self.sim.clock.offset = min(self.sim.clock.offset + 1001, cap)
            self.sim.tick()
        self.assertTrue(pump(lambda: key in self.keys(self.mate), [close], timeout=30), 'story never received')
        self.assertTrue(pump(lambda: convert(self.conv.stats)['ended'] >= 1, [close], timeout=60),
                        'conversation never ended')
        lines = self.said()
        self.assertEqual(len(lines), 4, lines)
        self.assertEqual({s['to'] for s in lines}, {'alice'}, 'a player out of range heard the conversation')
        self.assertEqual([s['npc'] for s in lines], [self.g.LK_LEADER, self.g.LK_MATE] * 2)
        for s in lines:
            self.assertLessEqual(len(s['t'].encode('utf-8')), protocol.CONVERSE_REPLY_BYTES)
        self.assertEqual(self.keys(self.mate)[key], ['seen', 'heard_from:' + self.leader.id])
        # Existing contacts only: alice knows the mate, its lines are in her notebook; nothing created for the leader.
        history = [h.text for h in lua_list(sim.state().characters[alice].contacts[self.mate.id].history)]
        self.assertEqual(history[-2:], [lines[1]['t'], lines[3]['t']])
        self.assertIsNone(sim.state().characters[alice].contacts[self.leader.id], 'contact created by a conversation')
        # Back to the first teller without duplication, and no new conversation (nothing left to tell).
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + self.conv.CFG.PAIR_HOURS
        for _ in range(3):
            self.step()
        self.assertEqual(len(self.requests()), 0)
        self.assertEqual(self.keys(self.leader)[key], ['seen'])
        self.assertEqual(convert(self.conv.stats)['opened'], 1)

    def test_partner_without_fiche_only_for_a_contacted_group_within_the_bound(self):
        sim = self.world(mate_fiche=False, far=True)
        key = self.record(self.leader)
        for _ in range(2):
            self.step()
        self.assertIsNone(self.server.find(self.g.LK_MATE), 'fiche created for a group never contacted')
        # The raider (other group, not contacted) stands next to the mate: still nothing.
        self.sim.server.g.PLAYERS['alice'].x = 10
        sim.command('alice', 'select', incarnation=self.g.LK_LEADER)  # the leader's group is now contacted
        self.assertIsNotNone(sim.state().characters[sim.character('alice')].contacts[self.leader.id])
        self.away('alice')
        npcs = sim.state().npcs
        fillers = []
        for n in range(64 - len(convert(npcs))):
            fillers.append('npc-fill-%d' % n)
            npcs[fillers[-1]] = self.rt.table_from({'id': fillers[-1], 'alive': False, 'incarnation': 'none'})
        self.step()
        self.assertIsNone(self.server.find(self.g.LK_MATE), 'fiche created beyond the bound of 64 fiches')
        for name in fillers:
            npcs[name] = None
        self.step()
        mate = self.server.find(self.g.LK_MATE)
        self.assertIsNotNone(mate, 'no fiche for a member of a contacted group')
        self.assertIn(key, self.keys(mate))
        self.assertIsNone(self.server.find(self.g.LK_RAIDER), 'fiche created for another group')

    def test_busy_or_gone_partner_learns_nothing(self):
        sim = self.world()
        key = self.record(self.leader)
        hits = self.rt.eval('LivingKnox.Bodies.lastHits')
        hits[self.g.LK_MATE] = self.rt.table_from({'ms': self.g.getTimestampMs()})
        self.step()
        self.assertEqual(self.requests(), [], 'conversation with a busy NPC')
        hits[self.g.LK_MATE] = None
        self.step()
        self.assertEqual(len(self.requests()), 1)
        # The mate walks away before the line is said: the reply is stale, nothing learned.
        self.rt.eval('LivingKnox.Bodies.bound')[self.g.LK_MATE].x = 40
        self.process = start_bridge(sim.path)
        self.assertTrue(pump(lambda: not self.requests(), [lambda: self.step(1001)]))
        self.step()
        self.assertNotIn(key, self.keys(self.mate))
        self.assertEqual(self.said(), [])
        self.assertEqual(len(self.conv.active), 0)

    def test_partner_behind_a_wall_tick_returns_nil(self):
        # In-game run of 2026-10-13 (rs.conversations): teller and partner spawned on both sides of a house wall,
        # within RANGE, the player in earshot: Provider.near fails on CanSee, V.tick returns nil (neither opened nor
        # silent) and nothing is learned. Same pair in sight: a conversation opens.
        self.world()
        key = self.record(self.leader)
        teller = self.rt.eval('LivingKnox.Bodies.bound')[self.g.LK_LEADER]
        teller.visible = False  # double of IsoGameCharacter.CanSee (LosUtil.lineClear Blocked)
        self.assertIsNone(self.conv.tick(self.server))
        self.assertEqual(convert(self.conv.stats)['opened'] + convert(self.conv.stats)['silent'], 0)
        self.assertNotIn(key, self.keys(self.mate))
        teller.visible = None
        self.assertEqual(self.conv.tick(self.server)[0], 'opened')

    def test_bridge_stopped_silence(self):
        """E08-T09 : pont arrêté, budget épuisé ou option « Désactivées » : aucune conversation entendue, aucune
        réplique de gabarit, aucun récit transmis ; pont revenu : la conversation s'ouvre."""
        self.world()
        provider = self.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        barks = []
        provider.bark = lambda *args: barks.append(args)  # never called (E08-T09)
        self.init.bridge.down = True
        self.init.bridge.probeAt = self.g.getTimestampMs() + 3600000
        key = self.record(self.leader)
        for _ in range(4):
            self.step()
        self.assertEqual(self.requests(), [], 'request sent to a stopped bridge')
        self.assertEqual((self.said(), barks), ([], []))
        self.assertNotIn(key, self.keys(self.mate), 'story passed without a conversation')
        stats = convert(self.conv.stats)
        self.assertEqual((stats['opened'], stats['silent']), (0, 0))
        self.assertNotIn('template', stats)
        self.assertEqual(count(self.sim.state().conversations.pairs), 0, 'pair delay consumed by a silence')
        # Budget spent (common cap): silence too.
        self.init.bridge.down = False
        cap = self.rt.eval("require('RadioSurvivor/RS_Config')").MAX_PER_HOUR
        now = self.g.getTimestampMs()
        for _ in range(cap):
            self.server.times[len(self.server.times) + 1] = now
        self.step()
        self.assertEqual((self.requests(), self.said(), barks), ([], [], []))
        # Option Off: silence too.
        self.server.times = self.rt.table()
        self.g.SandboxVars.RadioSurvivor.InitiativeFrequency = 1
        self.step()
        self.assertEqual((self.requests(), self.said(), barks), ([], [], []))
        self.assertNotIn(key, self.keys(self.mate))
        # Bridge back, budget and option Normal: the conversation opens and asks the model.
        self.g.SandboxVars.RadioSurvivor.InitiativeFrequency = 3
        self.step()
        self.assertEqual(len(self.requests()), 1)
        self.assertEqual(convert(self.conv.stats)['opened'], 1)

    def test_conversation_ends_silently_when_the_bridge_stops(self):
        """E08-T09 : le pont tombe pendant une conversation : elle se termine au tour suivant, sans gabarit."""
        self.world()
        provider = self.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        barks = []
        provider.bark = lambda *args: barks.append(args)
        key = self.record(self.leader)
        self.step()
        [req] = self.requests()
        conv = self.conv.of(self.leader.id)
        self.assertIsNotNone(conv)
        # The line of the teller was said (as if the bridge answered), then the bridge is considered stopped.
        self.server.pending = self.rt.table()
        conv.waiting = None
        conv.turn, conv.last = 1, self.leader.id
        self.init.bridge.down = True
        self.init.bridge.probeAt = self.g.getTimestampMs() + 3600000
        self.step()
        self.assertIsNone(self.conv.of(self.leader.id))
        self.assertTrue(any(f'conversation {conv.id} ended' in line and 'no model line' in line
                            for line in lua_list(self.g.LOGS)), lua_list(self.g.LOGS))
        for _ in range(3):
            self.step()
        self.assertEqual((self.requests(), self.said(), barks), ([], [], []))
        self.assertNotIn(key, self.keys(self.mate), 'story passed without a line said')
        self.assertIsNotNone(req)


TRACE = r'''
-- E08-T05: every conversation line requested (with the talk requests pending at that instant), every line said.
CONV_ASKED, CONV_SAID = {}, {}
local server = RS_CarnetServer
local enqueue = server.enqueue
server.enqueue = function(npc, kind, ...)
    local talks = 0
    for _, r in ipairs(server.pending) do if r.kind == 'npc_talk' then talks = talks + 1 end end
    local req = enqueue(npc, kind, ...)
    if req and kind == 'npc_converse' then CONV_ASKED[#CONV_ASKED + 1] = {req = req, talks = talks} end
    return req
end
local said = server.conversationReply
server.conversationReply = function(req, result, npc)
    local ok, why = said(req, result, npc)
    if ok then CONV_SAID[#CONV_SAID + 1] = req.id end
    return ok, why
end
'''


class InterventionTests(unittest.TestCase):
    """E08-T05 (ADR B11 « Intervention du joueur », ADR B04 « Ordre ») : un joueur qui a sélectionné l'un des deux PNJ
    d'une conversation entendue et lui parle s'insère dans la liste canonique des répliques ; la réplique de conversation
    déjà demandée est revalidée (refusée puis redemandée avec les nouveaux tours) ; aucune réplique de conversation n'est
    demandée tant que l'intervention attend sa réponse ; le joueur ne reçoit pas les tours qu'il n'a pas entendus ;
    aucun droit nouveau. Deux clients, vrai pont hors ligne."""

    setUp, tearDown, world, away = (ConversationTests.setUp, ConversationTests.tearDown, ConversationTests.world,
                                    ConversationTests.away)
    record, step, requests = ConversationTests.record, ConversationTests.step, ConversationTests.requests
    keys, said = ConversationTests.keys, ConversationTests.said

    def start(self, **kw):
        sim = self.world(**kw)
        self.rt.execute(TRACE)
        return sim

    def talks(self):
        return [r for r in lua_list(self.server.pending) if r.kind == 'npc_talk']

    def asked(self):
        return [convert(a) for a in lua_list(self.g.CONV_ASKED)]

    def run_bridge(self, until, timeout=60):
        if not self.process:
            self.process = start_bridge(self.sim.path)
        cap = self.sim.clock.offset + 5000   # requests stay less than 10 s ahead of real time (bridge rule)

        def close():
            self.sim.clock.offset = min(self.sim.clock.offset + 1001, cap)
            self.sim.tick()
        self.assertTrue(pump(until, [close], timeout=timeout))

    def test_player_joins_in_canonical_order_pending_line_revalidated(self):
        sim = self.start()
        alice = sim.character('alice')
        sim.command('alice', 'select', incarnation=self.g.LK_LEADER)
        self.away('bob')
        key = self.record(self.leader)
        self.step()
        first = self.requests()
        self.assertEqual(len(first), 1)
        conv = self.conv.of(self.leader.id)
        self.assertIsNotNone(conv)
        # Alice speaks to the leader while its first line is awaited: her sentence joins the conversation.
        self.assertTrue(sim.clients['alice'].g.RS_CarnetClient.talk('Hello you two, what happened?', False))
        talks = self.talks()
        self.assertEqual(len(talks), 1)
        talk = talks[0]
        self.assertEqual((talk.npc, talk.character), (self.leader.id, alice))
        context = convert(talk.context)
        self.assertEqual(context['conversation']['partner'], self.mate.name)
        self.assertEqual(convert(context['conversation']['lines']), {}, 'lines nobody said yet')
        order = [r.id for r in lua_list(self.server.pending) if r.npc == self.leader.id]
        self.assertEqual(order, [first[0].id, talk.id], 'the talk overtook the line already requested')
        self.assertEqual(sim.clients['alice'].g.RS_CarnetClient.waiting.id, talk.id)
        self.assertEqual(convert(self.conv.stats)['joined'], 1)
        # No second engagement while the talk waits: no new line requested, whatever the clock.
        for _ in range(3):
            self.step()
        self.assertEqual(len(self.asked()), 1)
        self.run_bridge(lambda: self.conv.of(self.leader.id) is None, timeout=90)
        lines = [convert(line) for line in lua_list(conv.lines)]
        name = sim.state().characters[alice].name
        self.assertEqual([line['who'] for line in lines], [name, self.leader.name, self.mate.name, self.leader.name])
        self.assertTrue(lines[0].get('player'))
        self.assertEqual(lines[0]['text'], 'Hello you two, what happened?')
        # The first line, asked before the intervention, was refused unsaid then asked again with the new lines.
        self.assertGreaterEqual(convert(self.conv.stats)['stale'], 1)
        said = [s for s in lua_list(self.g.CONV_SAID)]
        self.assertNotIn(first[0].id, said, 'stale line said')
        asked = self.asked()
        self.assertTrue(all(a['talks'] == 0 for a in asked), 'line requested while a talk waited')
        # Each later line carries every line the speaker heard, in the canonical order (bridge contract checked).
        mate_line = [a['req'] for a in asked if a['req']['npc'] == self.mate.id][0]
        heard = [line['who'] for line in convert(mate_line['context']['lines']).values()]
        self.assertEqual(heard, [name, self.leader.name])
        self.assertEqual(mate_line['context']['turn'], 3)
        for a in asked:   # every line request passes the bridge contract (lines heard = turn - 1)
            req = {k: v for k, v in a['req'].items() if v is not None}
            checked = protocol.unpack_request({'id': req['id'], 'kind': req['kind'],
                                               'payload': protocol.encode(req).hex()})
            self.assertEqual(len(checked['context']['lines']), checked['context']['turn'] - 1)
        self.assertIn(key, self.keys(self.mate), 'story not received after the teller answered')
        self.assertIsNone(sim.clients['alice'].g.RS_CarnetClient.waiting, 'wait not ended by the answer')

    def test_sentence_within_the_cooldown_never_joins(self):
        """E08-T05 (campagne solo du 2026-10-15) : une phrase dite moins de COOLDOWN_MS après la précédente du même
        personnage est refusée par le carnet (« Cooldown ») et n'entre pas dans la conversation, qui reste ouverte et
        inchangée ; la même phrase après le délai la rejoint."""
        sim = self.start()
        client = sim.clients['alice'].g.RS_CarnetClient
        sim.command('alice', 'select', incarnation=self.g.LK_LEADER)
        self.away('bob')
        self.server.lastTalk[sim.character('alice')] = self.sim.clock() - 8000   # sentence of a previous test
        self.record(self.leader)
        self.step()
        conv = self.conv.of(self.leader.id)
        self.assertIsNotNone(conv)
        self.assertTrue(client.talk('What are you two talking about?', False))
        self.assertEqual(self.talks(), [])
        self.assertEqual(client.lastError, 'Cooldown')
        self.assertEqual(convert(self.conv.stats)['joined'], 0)
        self.assertEqual(len(lua_list(conv.lines)), 0)
        self.assertEqual(self.conv.of(self.leader.id).id, conv.id, 'conversation ended by a refused sentence')
        self.step(1000)   # 10 s after the previous sentence
        client.waiting = None
        self.assertTrue(client.talk('What are you two talking about?', False))
        self.assertEqual(len(self.talks()), 1)
        self.assertEqual(convert(self.conv.stats)['joined'], 1)
        self.assertTrue(convert(lua_list(conv.lines)[0]).get('player'))

    def test_long_line_joined_in_whole_sentences(self):
        """E17-T13 : une ligne plus longue que MAX_REPLY (phrase du joueur, réponse au joueur) entre dans la liste
        canonique coupée à une fin de phrase, jamais au milieu d'un mot (ancien code : coupe à l'octet)."""
        sim = self.start()
        sim.command('alice', 'select', incarnation=self.g.LK_LEADER)
        self.away('bob')
        self.record(self.leader)
        self.step()
        conv = self.conv.of(self.leader.id)
        self.assertIsNotNone(conv)
        text = ('We saw smoke over the river this morning. Three trucks drove north without lights. '
                'Somebody fired twice near the bridge. Then everything went quiet until noon, '
                'and the dogs started barking again for a long while')
        self.assertGreater(len(text.encode('utf-8')), self.conv.CFG.MAX_REPLY)
        self.assertTrue(sim.clients['alice'].g.RS_CarnetClient.talk(text, False))
        line = convert(lua_list(conv.lines)[0])
        self.assertEqual(line['text'], 'We saw smoke over the river this morning. Three trucks drove north without '
                                       'lights. Somebody fired twice near the bridge.')

    def test_player_does_not_receive_lines_he_did_not_hear(self):
        sim = self.start()
        bob = sim.character('bob')
        sim.command('alice', 'select', incarnation=self.g.LK_LEADER)
        self.away('bob')
        self.record(self.leader)
        self.step()
        self.run_bridge(lambda: len(lua_list(self.g.CONV_SAID)) >= 1)
        before = set(lua_list(self.g.CONV_SAID))
        sent_before = len(self.said())
        # Bob comes, selects the mate and speaks to it in the middle of the conversation.
        self.sim.server.g.PLAYERS['bob'].x = self.sim.server.g.PLAYERS['alice'].x
        sim.command('bob', 'select', incarnation=self.g.LK_MATE)
        self.assertTrue(sim.clients['bob'].g.RS_CarnetClient.talk('Mind if I join?', False))
        self.assertEqual(len(self.talks()), 1)
        self.run_bridge(lambda: self.conv.of(self.leader.id) is None, timeout=90)
        history = [convert(h) for h in lua_list(sim.state().characters[bob].contacts[self.mate.id].history)]
        ids = {h['id'] for h in history}
        self.assertFalse(ids & before, 'bob got a line said before he could hear it')
        self.assertFalse([s for s in self.said()[:sent_before] if s['to'] == 'bob'])
        self.assertIn('Mind if I join?', [h['text'] for h in history])
        self.assertTrue([h for h in history if h['author'] == self.mate.name], 'bob never got the answer')

    def test_unanswered_intervention_ends_conversation_without_new_rights(self):
        sim = self.start()
        sim.command('alice', 'select', incarnation=self.g.LK_MATE)
        self.away('bob')
        self.record(self.leader)
        self.step()
        self.assertTrue(sim.clients['alice'].g.RS_CarnetClient.talk('Who are you people?', False))
        inside = convert(self.talks()[0].context)
        self.assertIn('conversation', inside)
        self.assertNotIn('negotiation', inside)
        # No bridge: the line and the talk time out; the conversation ends, no line is asked again.
        self.step(151000)
        self.step()
        self.assertIsNone(self.conv.of(self.leader.id))
        self.assertEqual(len(self.asked()), 1)
        self.assertEqual(self.talks(), [])
        # The same character outside any conversation: the same context, without the conversation (no right added).
        self.step(11000)
        self.assertTrue(sim.clients['alice'].g.RS_CarnetClient.talk('Who are you people?', False))
        outside = convert(self.talks()[0].context)
        self.assertEqual(set(inside) - {'conversation'}, set(outside))
        self.assertEqual({k: v for k, v in inside.items() if k != 'conversation'}, outside)

    def test_client_wait_ends_only_on_its_own_answer(self):
        sim = self.start()
        client = sim.clients['alice']
        cc = client.g.RS_CarnetClient
        cc.waiting = client.rt.table_from({'at': self.g.getTimestampMs(), 'npc': 'npc-x', 'id': 'req-alice'})
        args = {'world': cc.world, 'run': cc.run, 'npc': 'npc-x', 'incarnation': 'none', 'name': 'X', 'text': 'Hi.',
                'x': 0, 'y': 0, 'z': 0}
        cc.receive('speech', native_table(client, dict(args, id='req-bob')))
        self.assertIsNotNone(cc.waiting, "another player's answer ended the wait")
        cc.receive('speech', native_table(client, dict(args, id='req-alice')))
        self.assertIsNone(cc.waiting)


class ConversationProtocolTests(unittest.TestCase):
    def request(self, **change):
        req = {'version': 2, 'kind': 'npc_converse', 'id': 'run-1-npc-1', 'world': 'w', 'run': 'run', 'npc': 'npc-1',
               'character': 'system', 'order': 1, 'revision': 1, 'sent': 1, 'channel': 'say', 'language': 'FR',
               'personality': {'style': 'Direct', 'sociability': 4},
               'context': {'name': 'Ann', 'audience': 1, 'partner': 'Paul', 'role': 'listener', 'turn': 2,
                           'turns': 4, 'lines': {1: {'who': 'Paul', 'text': 'Tu as vu l\'orage ?'}}},
               'offers': {}, 'event': {'fact': 'weather', 'subject': 'storm', 'day': 3, 'place': 'everywhere',
                                       'source': 'heard', 'hops': 1, 'teller': 'Paul'}}
        req.update(change)
        req = {k: v for k, v in req.items() if v is not None}
        return {'id': req['id'], 'kind': req['kind'], 'payload': protocol.encode(req).hex()}

    def context(self, **change):
        context = {'name': 'Ann', 'audience': 1, 'partner': 'Paul', 'role': 'teller', 'turn': 1, 'turns': 4,
                   'lines': {}}
        context.update(change)
        return context

    def test_contract(self):
        req = protocol.unpack_request(self.request())
        self.assertEqual(req['context']['lines'], [{'who': 'Paul', 'text': "Tu as vu l'orage ?"}])
        first = protocol.unpack_request(self.request(context=self.context()))
        self.assertEqual(first['context']['lines'], [])
        for bad in ({'text': 'hello'}, {'character': 'char-1'}, {'offers': {'x': {'kind': 'scout'}}}, {'event': None},
                    {'context': self.context(role='judge')}, {'context': self.context(turn=5, turns=5)},
                    {'context': self.context(turn=2)}, {'context': self.context(partner='')},
                    {'context': self.context(turn=2, lines={1: {'who': 'Paul', 'text': 'x' * 300}})}):
            with self.assertRaises(ValueError, msg=str(bad)):
                protocol.unpack_request(self.request(**bad))
        reply = protocol.bounded_reply(req, {'text': 'x' * 400, 'intent': 'none', 'offer': ''})
        self.assertLessEqual(len(reply['text'].encode('utf-8')), protocol.CONVERSE_REPLY_BYTES)
        with self.assertRaises(ValueError):
            protocol.bounded_reply(req, {'text': 'Hey.', 'intent': 'accept', 'offer': ''})
        messages = protocol.prompt(req, [])
        self.assertEqual(messages[-1], {'role': 'user', 'content': "Paul (to you): Tu as vu l'orage ?"})
        self.assertIn('Subject of the conversation: day 3, everywhere: a weather change', messages[0]['content'])
        self.assertIn('Speak in French', messages[0]['content'])
        self.assertEqual(protocol.memory_turn(first), '(you start talking with Paul)')
        self.assertEqual(protocol.offline(req)['text'], 'Ah oui ? Raconte.')

    def test_bridge_memory_keeps_the_partner_line_never_a_player_text(self):
        with tempfile.TemporaryDirectory(prefix='rs-conv-mem-') as folder:
            conv = bridge_module.NpcConversations(Path(folder))
            req = protocol.unpack_request(self.request())
            reply = conv.propose({'OFFLINE': '1'}, req)
            self.assertTrue(conv.acknowledge({'request': req['id'], 'world': 'w', 'run': 'run', 'npc': 'npc-1',
                                              'order': 1, 'revision': 1, 'status': 'accepted', 'applied': {}}))
            self.assertEqual(conv.load(req)['messages'], [
                {'role': 'user', 'content': "Paul (to you): Tu as vu l'orage ?"},
                {'role': 'assistant', 'content': reply['text']}])


if __name__ == '__main__':
    unittest.main(verbosity=2)
