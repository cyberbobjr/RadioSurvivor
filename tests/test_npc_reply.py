"""E07-T09, E17-T09: structured NPC reply of the model read robustly, and a spoken yes accepting an open offer.

    python RadioSurvivor/tests/test_npc_reply.py

In-game run of 2026-10-13 (rs.npctalk, solo, deepseek-flash): the answer to "do you need help?" was cut by
max_tokens (775 reasoning tokens of 800) inside its text, after a "type": "json_object" key copied by the model; the
raw JSON was said to the player. The spoken yes to the open offer was then answered without intent accept: the
acquaintance rule of the prompt ("no mission to offer now: return intent none") contradicted the open-offer rule.
Bridge functions (no network), call_llm with simulated HTTP answers, and the real Lua server with the offline bridge
doubles of tests/test_carnet.py. No real model, no Java API: not an in-game validation.
"""
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

from test_protocol import ROOT
from test_carnet import Simulation, convert, count, talk_requests

sys.path.insert(0, str(ROOT / 'bridge'))
import npc_protocol as protocol  # noqa: E402
import radio_bridge as bridge_module  # noqa: E402

# Exact answer stored in the NPC journal on 2026-10-13 (npc_e555...json, assistant turn of the "help" sentence).
OBSERVED = '{"type": "json_object", "text": "Oui, j\'ai du travail. Il faut reconnaître une'


def talk_request(**context):
    return {'version': 2, 'kind': 'npc_talk', 'id': 'run-a-1-npc-a', 'world': 'w', 'run': 'run-a', 'npc': 'npc-a',
            'character': 'character-a', 'order': 1, 'revision': 1, 'channel': 'say', 'language': 'FR',
            'text': "D'accord, je m'en occupe.", 'personality': {}, 'context': dict(context),
            'offers': {}}


class ReplyParsingTests(unittest.TestCase):
    def test_observed_cut_reply_is_never_said(self):
        req = talk_request(stage='acquainted')
        with self.assertRaises(ValueError) as err:
            protocol.model_reply(req, OBSERVED)
        self.assertEqual(str(err.exception), 'unreadable JSON reply')
        # Same answer in a code block or after prose: still refused, never shown as speech.
        for raw in ('```json\n' + OBSERVED, 'Voici : ' + OBSERVED, '{"text": "Oui, il y a \\"un truc"'):
            with self.assertRaises(ValueError):
                protocol.model_reply(req, raw)

    def test_parasitic_key_keeps_the_intent(self):
        req = dict(talk_request(stage='acquainted'), offers={'scout_v1': {'durationMs': 7200000, 'rewardCount': 20}})
        raw = ('{"type": "json_object", "text": "Oui, j\'ai du travail : va voir la maison.", "intent": "offer", '
               '"offer": "scout_v1"}')
        reply, reason = protocol.model_reply(req, raw)
        self.assertEqual((reply['text'], reply['intent'], reply['offer'], reason),
                         ("Oui, j'ai du travail : va voir la maison.", 'offer', 'scout_v1', ''))
        self.assertNotIn('type', reply)

    def test_nested_fenced_and_surrounded_objects(self):
        req = dict(talk_request(stage='acquainted'), offers={'scout_v1': {'durationMs': 7200000, 'rewardCount': 20}})
        inner = '{"text": "Va voir la maison.", "intent": "offer", "offer": "scout_v1"}'
        for raw in ('{"type": "json_object", "response": ' + inner + '}',
                    '{"text": ' + inner + '}',
                    '```json\n' + inner + '\n```',
                    'Bien sûr. ' + inner + ' Voilà.',
                    '[' + inner + ']'):
            reply, reason = protocol.model_reply(req, raw)
            self.assertEqual((reply['text'], reply['intent'], reply['offer'], reason),
                             ('Va voir la maison.', 'offer', 'scout_v1', ''), raw)

    def test_plain_prose_stays_speech_json_without_text_never(self):
        req = talk_request(stage='acquainted')
        reply, reason = protocol.model_reply(req, 'Bien, je compte sur toi.')
        self.assertEqual((reply['text'], reply['intent'], reason), ('Bien, je compte sur toi.', 'none', ''))
        with self.assertRaises(ValueError):
            protocol.model_reply(req, 'Voici : {"say": "Bien."}')

    def test_accept_naming_the_offer_is_the_acceptance(self):
        req = talk_request(stage='acquainted', acceptable={'mission': 'npc-a-scout1', 'revision': 1})
        for offer in ('npc-a-scout1', 'scout_v1', ''):
            raw = json.dumps({'type': 'json_object', 'text': 'Bien.', 'intent': 'accept', 'offer': offer})
            reply, reason = protocol.model_reply(req, raw)
            self.assertEqual((reply['intent'], reply['offer'], reason), ('accept', '', ''), offer)
        # Without an open offer: no acceptance, speech only.
        reply, reason = protocol.model_reply(talk_request(stage='acquainted'),
                                             '{"text": "Bien.", "intent": "accept", "offer": "scout_v1"}')
        self.assertEqual((reply['intent'], reason), ('none', 'inadmissible offer'))


class PromptTests(unittest.TestCase):
    def test_open_offer_rule_not_contradicted(self):
        # An open offer means no catalog (RS_Missions.offers returns {} while npc.mission is set).
        req = talk_request(stage='acquainted', acceptable={'mission': 'npc-a-scout1', 'revision': 1},
                           mission={'state': 'offer'})
        system = protocol.prompt(req, [])[0]['content']
        self.assertIn('Return intent accept, offer empty, only if their latest sentence clearly agrees', system)
        self.assertIn('read it in their notebook', system)
        self.assertIn('You make no new offer now', system)
        self.assertNotIn('no mission or job to offer now: return intent none', system)
        # Without an open offer, the acquaintance rules are unchanged.
        system = protocol.prompt(talk_request(stage='acquainted'), [])[0]['content']
        self.assertIn('You have no mission or job to offer now: return intent none, offer empty.', system)
        self.assertIn('with these keys and no other', system)


class Resp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class CutAnswerTests(unittest.TestCase):
    def test_cut_answer_logged_not_retried_and_cap_is_16000(self):
        sent, script = [], [
            {'content': OBSERVED, 'finish_reason': 'length'},
        ]

        def urlopen(request, timeout=60):
            sent.append(json.loads(request.data.decode('utf-8')))
            step = script.pop(0)
            return Resp(json.dumps({'choices': [{'message': {'content': step['content']},
                                                 'finish_reason': step['finish_reason']}]}).encode('utf-8'))

        config = {'OPENAI_KEY': 'k-test', 'OPENAI_BASE_URL': 'http://llm.invalid/v1', 'OPENAI_MODEL': 'cut-model'}
        saved = bridge_module.urllib.request.urlopen
        bridge_module.urllib.request.urlopen = urlopen
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                raw = bridge_module.call_llm(config, [{'role': 'user', 'content': 'x'}], 'NPC', json_mode=True)
        finally:
            bridge_module.urllib.request.urlopen = saved
        self.assertEqual(raw, OBSERVED)          # the reader refuses it afterwards (never shown)
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0]['max_tokens'], 16000)
        self.assertEqual(sent[0]['response_format'], {'type': 'json_object'})
        self.assertIn('cut by the token limit', out.getvalue())
        self.assertNotIn('k-test', out.getvalue())


class ServerTests(unittest.TestCase):
    """Real Lua server: a reply read by model_reply from a model answer with a parasitic key accepts the open offer
    (offer created by RS_Missions.create, the path of an offer made by the model); a raw JSON text is refused."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-npcreply-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def answer(self, sim, req, reply):
        bridge_module.write_responses(sim.path / 'responses.txt', {req['id']: reply})
        sim.clock.offset += 1100
        sim.tick()

    def talk(self, sim, text):
        sim.server.g.RS_CarnetServer.lastTalk[sim.character('alice')] = None
        sim.command('alice', 'talk', channel='say', text=text, language='FR')
        [req] = talk_requests(sim.server.g)
        return convert(req)

    def test_spoken_yes_with_parasitic_key_accepts_the_open_offer(self):
        sim = Simulation(self.path / 'accept')
        sim.add_client('alice')
        sim.select('alice')
        sim.acquaint('alice')
        npc = next(iter(sim.state().npcs.values()))
        m = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')").create(sim.state(), npc, sim.character('alice'))
        self.assertEqual(m.state, 'offer')
        req = self.talk(sim, "D'accord, je m'en occupe.")
        self.assertEqual(req['context']['acceptable'], {'mission': m.id, 'revision': m.revision})
        self.assertEqual(req['offers'], {})
        raw = json.dumps({'type': 'json_object', 'text': 'Bien, je compte sur toi.', 'intent': 'accept',
                          'offer': m.id})
        reply, reason = protocol.model_reply(req, raw)
        self.assertEqual((reply['intent'], reason), ('accept', ''))
        self.answer(sim, req, reply)
        self.assertEqual(m.state, 'active')
        self.assertEqual(count(m.participants), 1)

    def test_raw_json_text_refused_by_the_server(self):
        sim = Simulation(self.path / 'raw')
        c = sim.add_client('alice')
        sim.select('alice')
        req = self.talk(sim, 'Salut !')
        body = protocol.offline(req)
        body['text'] = OBSERVED
        self.answer(sim, req, body)
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'NoAnswer')
        contact = next(iter(sim.state().characters[sim.character('alice')].contacts.values()), None)
        history = convert(contact.history) if contact is not None and contact.history is not None else {}
        self.assertNotIn('json_object', json.dumps(history, ensure_ascii=False))


if __name__ == '__main__':
    unittest.main()
