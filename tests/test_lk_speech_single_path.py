"""One speech path for the NPCs of Living Knox: the notebook server of the core mod (E21-T05, slice 13 of
docs/annexes/conception/carnet-commun-e21.md).

    python tests/test_lk_speech_single_path.py

Bench of tests/test_carnet.py (Simulation: dedicated server and MP clients, real Living Knox engine, its provider
LK_NotebookProvider, real notebook server and client of the core mod, the installed vanilla ISChat input) with the core
mod and Living Knox only on the module path (Game.WITH_RS = False). A sentence said in the say chat without a selected
target goes to the nearest NPC (decision 1 of the design, nothing and no message when nobody is near); the world menu
"Talk" of Living Knox (LK_TalkView) selects its NPC and speaks through CoreAI.notebookClient.talkTo; each gives ONE
npc_talk request and the answer comes back as a bubble over the client copy of the body. The NPC is listed in the
Contacts tab with its relation (page of the provider), also when known by a personal relation only; a mission offered by
speech is accepted, handed over and claimed from the notebook (Range refusal far from the requester, lot announced and
claim button for a mission whose lot is created by the group: rewardCount 0). Initiatives, conversations and chatter of
the NPCs run with this host; the acquaintance survives a restart; a lost hello is sent again by the client poll.
Cases moved from the former benches of Living Knox alone (test_lk_talk_alone.py, test_lk_contacts.py).
Doubles: the bridge answers by the responses file written here; proves neither the network nor Java.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from test_carnet import LK_WORLD, Simulation, convert, lua_list, open_notebook, protocol, talk_requests
from test_protocol import Game


class SpeechSinglePathTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-speech-')
        self.path = Path(self.tmp.name) / 'w'
        patcher = mock.patch.object(Game, 'WITH_RS', False)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.sim = self.world(new_world=True)
        self.sim.server.rt.execute(LK_WORLD)
        self.c = self.sim.add_client('alice')
        self.client = self.c.g.CoreAI.notebookClient
        self.alice = self.sim.character('alice')
        # Copies of the bodies on the client (roster of LK_ZombieGuard), where the player sees them.
        self.leader_copy = self.c.rt.eval('lkCopy')(self.g.LK_LEADER, 5001, 12)
        self.mate_copy = self.c.rt.eval('lkCopy')(self.g.LK_MATE, 5002, 14)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, new_world):
        sim = Simulation(self.path, living_knox=True, rs_hooks=False, new_world=new_world)
        self.g, self.rt = sim.server.g, sim.server.rt
        self.server = sim.server.g.CoreAI.notebookServer
        return sim

    # ---------------------------------------------------------------- helpers

    def say(self, text):
        """The say chat of alice (installed vanilla ISChat input), past the delays of the previous sentence."""
        self.sim.clock.offset += 11000
        self.sim.say('alice', '/say ' + text)

    def menu(self, npc, text):
        """World menu "Talk" of Living Knox on the NPC npc: the sentence of its text box."""
        self.sim.clock.offset += 11000
        self.c.rt.execute('require "LivingKnox/LK_TalkView"')
        return self.c.g.LivingKnox.TalkView.sayTo(self.c.g.getPlayer(), npc, text)

    def tick(self, n=1):
        for _ in range(n):
            self.sim.clock.offset += 1001
            self.sim.tick()

    def answer(self, intent='none', offer=''):
        """The bridge answers every pending request (npc_talk with intent and offer)."""
        out = ''
        asked = []
        for r in self.server.talk.pending.values():
            asked.append(r)
            body = {'version': 2, 'kind': 'npc_reply', 'id': r.id, 'world': r.world, 'run': r.run, 'npc': r.npc,
                    'order': r.order, 'revision': r.revision, 'text': 'Noted.', 'intent': 'none', 'offer': ''}
            if r.kind == 'npc_talk':
                body['intent'], body['offer'] = intent, offer
            if r.kind == 'npc_enrich':
                body['background'] = 'A Knox survivor.'
            out += f"resp={r.id}\npayload={protocol.encode(body).hex()}\n"
        (self.sim.path / 'responses.txt').write_text(out + 'end\n', encoding='utf-8')
        self.tick(3)
        return asked

    def pending(self, kind):
        return [r for r in self.server.talk.pending.values() if r.kind == kind]

    def fiche(self, lk_id):
        return self.server.find(lk_id)

    def contacts(self, name='alice'):
        self.sim.command(name, 'snapshot')
        return list(self.sim.clients[name].g.CoreAI.notebookClient.snapshot.contacts.values())

    def accepted_supply(self, reward_count=None):
        """A supply mission of the leader offered by speech, accepted from the notebook (button Accept)."""
        self.say('Salut')
        self.answer()
        self.sim.acquaint('alice')
        req = self.speak_and_get('Tu as du travail ?')
        offers = list(req.offers.keys())
        self.assertTrue(offers, 'no offer')
        self.answer('offer', offers[0])
        m = self.sim.mission()
        self.assertEqual(m.state, 'offer')
        if reward_count is not None:
            m.rewardCount = reward_count
        self.sim.request_mission('alice', 'accept')
        self.assertEqual((m.state, m.unit), ('active', 'value'))
        m.quantity = 4  # two items of value 2 each
        return m

    def speak_and_get(self, text):
        before = {r.id for r in talk_requests(self.g)}
        self.say(text)
        reqs = [r for r in talk_requests(self.g) if r.id not in before]
        self.assertEqual(len(reqs), 1, self.client.lastError)
        return reqs[0]

    def two_items(self, m):
        kind = next(iter(m.accepted.keys()))
        return self.sim.items('alice', kind, kind)

    def missions_page(self):
        self.c.rt.execute("getScriptManager = function() return {FindItem = function(_, t) "
                          "return {getDisplayName = function() return 'item ' .. t end} end} end")
        window = open_notebook(self.c)
        window.changeTab(window, 'Missions')
        window.update(window)
        self.sim.command('alice', 'snapshot')
        window.refresh(window)
        return window

    # ---------------------------------------------------------------- one speech path

    def test_a_chat_sentence_goes_to_the_nearest_npc_and_comes_back_as_a_bubble(self):
        req = self.speak_and_get('Bonjour')
        leader = self.fiche(self.g.LK_LEADER)
        self.assertEqual((req.kind, req.npc, req.character), ('npc_talk', leader.id, self.alice))
        self.assertEqual(req.context.stage, 'stranger')
        self.assertIsNotNone(req.context.group)
        protocol.unpack_request({'id': req.id, 'kind': req.kind, 'payload': protocol.encode(convert(req)).hex()})
        self.answer()
        self.assertEqual(list(self.leader_copy.bubbles.values()), ['Noted.'])
        contact = self.server.store.data.characters[self.alice].contacts[leader.id]
        self.assertEqual([h.text for h in contact.history.values()], ['Bonjour', 'Noted.'])
        self.assertEqual(contact.exchanges, 1)

    def test_the_menu_talk_speaks_to_its_npc_whoever_stands_nearer(self):
        self.assertTrue(self.menu(self.g.LK_MATE, 'Salut'))
        reqs = talk_requests(self.g)
        mate = self.fiche(self.g.LK_MATE)
        self.assertEqual([r.npc for r in reqs], [mate.id])
        self.assertEqual(self.client.snapshot.selected, mate.id)
        self.assertIn('Salut', list(self.c.g.SAID_CHAT.values()), 'sentence of the menu said aloud')
        self.answer()
        self.assertEqual(list(self.mate_copy.bubbles.values()), ['Noted.'])
        self.assertEqual(len(talk_requests(self.g)), 0)

    def test_nobody_near_is_silent_in_the_chat_and_refused_by_the_menu(self):
        self.g.PLAYERS.alice.x = 500
        self.say('Bonjour')
        self.assertEqual(talk_requests(self.g), [])
        self.assertIsNone(self.client.lastError)
        self.menu(self.g.LK_LEADER, 'Bonjour')
        self.assertEqual(talk_requests(self.g), [])
        self.assertEqual(self.client.lastError, 'Range')

    # ---------------------------------------------------------------- contacts

    def test_the_npc_is_listed_in_contacts_with_its_relation_page(self):
        self.say('Bonjour')
        self.answer()
        leader = self.fiche(self.g.LK_LEADER)
        rows = [r for r in self.contacts() if r.id == leader.id]
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0].name, rows[0].page), (leader.name, 'livingknox'))
        self.assertIn(rows[0].relation.level, ('hostile', 'wary', 'cautious', 'favorable', 'trusting'))
        window = open_notebook(self.c)
        self.assertEqual(window.tab, 'Contacts')
        self.assertIn('IGUI_LK_RelTitle', window.detail.text)
        self.assertIn('Bonjour', window.detail.text)
        # Another character far away heard nothing: no contact.
        self.sim.add_client('bob')
        self.g.PLAYERS.bob.x = 500
        self.assertEqual(self.contacts('bob'), [])

    def test_an_npc_known_by_a_personal_relation_only_is_a_contact(self):
        """Decision 2 of the design: the NPCs a character knows by a personal relation stay in its contacts."""
        mate = self.g.LK_MATE
        self.rt.execute(f'assert(LivingKnox.Hostility.record(LK_GROUP, "{self.alice}", "gift", {{witnessed = true}}))'
                        f' local _, b = LivingKnox.API.relationOffer("{mate}", "{self.alice}") '
                        f'assert(LivingKnox.API.relationApply("{mate}", "{self.alice}", b, "up", "f1"))')
        contacts = self.contacts()
        fiche = self.fiche(mate)
        self.assertIsNotNone(fiche)
        rows = [r for r in contacts if r.id == fiche.id]
        self.assertEqual(len(rows), 1, [r.name for r in contacts])
        self.assertEqual(rows[0].page, 'livingknox')
        self.assertIsNotNone(rows[0].relation.level)

    # ---------------------------------------------------------------- missions

    def test_a_mission_offered_by_speech_is_accepted_delivered_and_claimed_from_the_notebook(self):
        m = self.accepted_supply()
        self.assertEqual(self.client.lastError, None)
        self.sim.confirm('alice', self.sim.quote('alice', self.two_items(m)))
        self.assertEqual(m.state, 'success')
        self.sim.request_mission('alice', 'claim')
        self.assertEqual(m.claimedBy, self.alice)
        got = [it.kind for it in self.g.PLAYERS.alice.inv['items'].values()]
        self.assertEqual(got.count(m.rewardType), m.rewardCount, got)

    def test_a_delivery_far_from_the_requester_is_refused_for_range(self):
        m = self.accepted_supply()
        ids = self.two_items(m)
        self.g.PLAYERS.alice.x = 500
        self.sim.request_mission('alice', 'prepare_delivery', items=ids)
        self.assertEqual(self.client.lastError, 'Range')
        self.assertEqual(m.delivered, 0)

    def fixture_mission(self):
        """A successful mission of the leader for alice made as the in-game suite lk.missions makes it: created from
        the offers of the leader, accepted and closed in success by the authority, no sentence said to the NPC (the
        bench leader offers a supply only: the claim path is the same for every kind)."""
        return self.rt.eval('''function(id, character)
            local M = require 'CoreAI/CA_Missions'
            local P = require 'CoreAI/CA_NPCProvider'
            local Server = CoreAI.notebookServer
            local data = Server.store.data
            local npc = Server.ensure(id)
            local m
            for offerId, terms in pairs(M.offers(npc, P.npc(id), P.objects()[id], character)) do
                if m == nil and type(terms) == 'table' then m = M.create(data, npc, character, offerId, terms) end
            end
            M.accept(data, m, character, 'RST')
            M.finish(data, m, 'success')
            data.characters[character].knownMissions[m.id] = true
            return m
        end''')(self.g.LK_LEADER, self.alice)

    def test_a_refused_lot_claim_is_logged_on_the_server_with_its_reason(self):
        """MP run 20261115-163137 (lk.missions): a claim next to the requester of an NPC that is not a contact of the
        character was refused (State) and nothing on the server said so."""
        m = self.fixture_mission()
        self.assertEqual(m.state, 'success')
        self.sim.command('alice', 'claim', mission=m.id, revision=m.revision)
        self.assertEqual((self.client.lastError, m.claimedBy), ('State', ''))
        refused = [line for line in lua_list(self.g.LOGS) if 'gesture claim refused' in line]
        self.assertEqual(len(refused), 1, lua_list(self.g.LOGS)[-5:])
        self.assertIn(self.alice, refused[0])
        self.assertIn(m.id, refused[0])
        self.assertIn('State', refused[0])
        self.assertIn('not a contact', refused[0])

    def test_the_lot_is_claimed_once_the_player_has_selected_the_requester(self):
        """What a player always does before a mission of an NPC (lk.missions in game: select, then claim)."""
        m = self.fixture_mission()
        self.sim.command('alice', 'select', incarnation=self.g.LK_LEADER)
        self.sim.command('alice', 'claim', mission=m.id, revision=m.revision)
        self.assertEqual(self.client.lastError, None)
        self.assertEqual(m.claimedBy, self.alice)

    def test_a_lot_created_by_the_group_is_announced_and_claimed(self):
        """E18-T33: no announced lot (rewardCount 0): the notebook names the lot of the group and offers the claim."""
        m = self.accepted_supply(reward_count=0)
        self.sim.confirm('alice', self.sim.quote('alice', self.two_items(m)))
        self.assertEqual(m.state, 'success')
        window = self.missions_page()
        row = self.client.snapshot.missions[1]
        self.assertIsNotNone(row.rewardTable)
        self.assertIn('IGUI_CA_RewardLot|', window.detail.text)
        self.assertTrue(window.claim.isVisible(window.claim))
        window.claim.onclick(window)
        self.assertEqual((m.claimedBy, m.createdLot), (self.alice, row.rewardTable))

    # ---------------------------------------------------------------- the NPCs speak up with this host

    def storm(self, npc):
        """The NPC noticed a storm (observations of Living Knox, E18-T27)."""
        obs = self.rt.eval('LivingKnox.Observations')
        key, why = obs.record(npc, self.rt.table_from(
            {'fact': 'weather', 'subject': 'storm', 'day': obs.today(), 'place': 'everywhere'}))
        self.assertIsNotNone(key, why)
        return key

    def test_an_npc_speaks_up_on_its_own(self):
        self.rt.execute("require 'LivingKnox/LK_Speech'")  # proximity speech channel (loaded in the game)
        npc = self.server.talk.ensure(self.g.LK_LEADER)
        self.storm(npc.id)
        self.answer()  # one pass: LK_Talk.turns opens the initiative
        asked = self.pending('npc_initiative')
        self.assertEqual(len(asked), 1, [r.kind for r in self.server.talk.pending.values()])
        self.assertEqual(asked[0].npc, npc.id)
        initiatives = self.rt.eval("require('LivingKnox/LK_Initiatives')")
        said = initiatives.stats.said
        self.answer()
        self.assertEqual(initiatives.stats.said, said + 1)
        self.assertEqual(self.pending('npc_initiative'), [])

    def test_two_npcs_tell_each_other_what_they_saw(self):
        self.rt.execute("require 'LivingKnox/LK_Speech'")
        teller = self.server.talk.ensure(self.g.LK_LEADER)
        partner = self.server.talk.ensure(self.g.LK_MATE)
        self.rt.eval("require('LivingKnox/LK_Initiatives')").bridge.down = False
        key = self.storm(teller.id)
        for _ in range(4):
            self.answer()
            if self.pending('npc_converse'):
                break
        self.assertTrue(self.pending('npc_converse'), 'no conversation line asked')
        obs = self.rt.eval('LivingKnox.Observations')
        for _ in range(4):
            self.answer()
        heard = [o.source for o in obs.list(partner.id).values() if o.key == key]
        self.assertEqual(heard, ['heard_from:' + teller.id])

    def test_two_members_chatter_at_their_home(self):
        self.rt.execute("require 'LivingKnox/LK_Speech'")
        self.rt.execute('assert(LivingKnox.Groups.setHome(LK_GROUP, 13, 10, 0))')
        self.rt.execute("require('LivingKnox/LK_Chatter').draw = function(n) return n end")
        self.server.talk.ensure(self.g.LK_LEADER)
        self.server.talk.ensure(self.g.LK_MATE)
        conversations = self.rt.eval("require('LivingKnox/LK_Conversations')")
        chatter = self.rt.eval("require('LivingKnox/LK_Chatter')")
        said = conversations.stats.said
        for _ in range(3):
            self.answer()
            if self.pending('npc_converse'):
                break
        asked = self.pending('npc_converse')
        self.assertTrue(asked, 'no chatter line asked')
        topic = asked[0].context.topic
        self.assertIsNotNone(topic, 'conversation without a topic')
        self.assertEqual(chatter.stats.opened, 1)
        turns = chatter.TURNS[topic.subject]
        ended = conversations.stats.ended
        for _ in range(turns * 6):
            self.answer()
            if conversations.stats.ended > ended:
                break
        self.assertEqual(conversations.stats.said, said + turns)

    # ---------------------------------------------------------------- persistence and identity

    def test_acquaintance_survives_a_restart(self):
        self.say('Bonjour')
        self.answer()
        lk_id = self.g.LK_LEADER
        leader = self.fiche(lk_id)
        self.assertTrue(self.server.store.save())
        world = self.server.store.data.world
        again = self.world(new_world=False)
        self.assertEqual(again.state().world, world)
        self.assertEqual(again.state().characters[self.alice].contacts[leader.id].exchanges, 1)
        self.assertEqual(again.state().npcs[leader.id].incarnation, lk_id)

    def test_a_lost_hello_is_sent_again_by_the_client_poll(self):
        """E18-T27 (MP campaign of 2026-11-07, "listeners 0"): a hello that arrived before the server player existed is
        lost; the notebook client greets again until the notebook server answers, so the player hears the NPCs."""
        remote = self.g.PLAYERS.alice
        self.server.bound[remote] = None
        self.client.world, self.client.run = None, None
        self.sim.clock.offset += 31000
        self.c.g.fire('OnTick')
        self.assertEqual(self.server.bound[remote], self.alice)
        self.assertIsNotNone(self.client.world)


if __name__ == '__main__':
    unittest.main(verbosity=2)
