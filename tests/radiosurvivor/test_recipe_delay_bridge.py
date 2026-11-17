"""Recipe search with a delay, on the bridge side (E27-T04, ADR recettes-radio D04, D07): bridge/recipe_delay.py and
radio_bridge.voice_turn / answer.

    python RadioSurvivor/tests/radiosurvivor/test_recipe_delay_bridge.py

A voice whose [help] has delay= hour, half_day or day searches when asked but does not give the recipe: the second call
asks the voice to say it must look through its notes and to ask the caller to call back; the ids found go back to the
server as "searched" (not delivered). The server stores them and sends them back with every later request of that
caller to that voice (field recipe=, with ready = the game time has come). Not ready: the voice is still looking, no
facts. Ready: the recipes are given as facts in the first call and returned as delivered ("recipes", even empty).
Delay now: E27-T03 unchanged (tests/radiosurvivor/test_recipe_help_bridge.py). Fake model only: no network, no LLM.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
sys.path.insert(0, str(bench_paths.ROOT / 'bridge'))
import npc_protocol as npc  # noqa: E402
import radio_bridge as rb  # noqa: E402
import recipe_delay  # noqa: E402
from recipe_index import RecipeIndex  # noqa: E402
from test_recipe_help_bridge import HELPER_SHEET, RECIPES, FakeModel, reputation  # noqa: E402

LOGS: list[str] = []
rb.log = LOGS.append


def pending(ids, ready, keywords=('sheet rope',)) -> str:
    """Field recipe= as the server writes it (hex RSV2 of {ids, ready, keywords})."""
    return npc.encode({'ids': list(ids), 'ready': ready, 'keywords': list(keywords)}).hex()


class RecipeDelayBridgeTests(unittest.TestCase):
    def setUp(self):
        LOGS.clear()
        self.tmp = tempfile.TemporaryDirectory()
        exchange = Path(self.tmp.name)
        personas = exchange / 'personas'
        personas.mkdir()
        (personas / 'martha.txt').write_text(HELPER_SHEET.format(from_line='from=neutral\ndelay=hour'),
                                             encoding='utf-8')
        (exchange / 'recipes.json').write_text(json.dumps({'format': 1, 'written': 1, 'recipes': RECIPES}),
                                               encoding='utf-8')
        self.voices = rb.Voices(personas)
        self.index = RecipeIndex(exchange, log=lambda _: None)
        self.conversations = rb.Conversations(exchange)
        self.saved_llm = rb.call_llm

    def tearDown(self):
        rb.call_llm = self.saved_llm
        self.tmp.cleanup()

    def ask(self, text: str, *answers: str, field: str | None = None, level: str = 'good'):
        model = FakeModel(*answers)
        rb.call_llm = model
        req = {'id': '7-2', 'caller': 'kate', 'name': 'Kate', 'date': '1993-07-12 21:40', 'days': '3.5',
               'radio': 'Walkie', 'text': text, 'voice': 'martha', 'reputation': reputation(level)}
        if field is not None:
            req['recipe'] = field
        return rb.answer({}, self.conversations, 's', req, self.voices, self.index), model

    @staticmethod
    def search_reply(*keywords: str) -> str:
        return json.dumps({'say': 'Let me look.', 'actions': [], 'recipe_search': list(keywords)})

    # --- first question: searched, not delivered ----------------------------------------------------------------

    def test_delayed_voice_asks_to_call_back_without_the_recipe(self):
        result, model = self.ask('Comment je fais une corde avec des draps ?', self.search_reply('sheet rope'),
                                 'Je dois fouiller mes notes, rappelle dans une heure.')
        self.assertEqual(len(model.calls), 2)
        messages, json_mode = model.calls[1]
        self.assertFalse(json_mode)
        callback = messages[-1]['content']
        self.assertIn('call you back in about an hour', callback)
        self.assertIn('language the caller used', callback)
        for fact in ('Corde en draps', 'Draps déchirés', 'Aiguille', 'Tailoring level'):
            self.assertNotIn(fact, callback)
        self.assertEqual(result, {'version': 2, 'kind': 'radio_reply', 'id': '7-2',
                                  'say': ['Je dois fouiller mes notes, rappelle dans une heure.'], 'actions': [],
                                  'searched': {'ids': ['MakeSheetRope'], 'keywords': ['sheet rope']}})

    def test_delayed_search_that_finds_nothing_is_still_returned_as_searched(self):
        result, _ = self.ask('Un avion ?', self.search_reply('airplane'), 'Rappelle demain.')
        self.assertEqual(result['searched'], {'ids': [], 'keywords': ['airplane']})
        self.assertNotIn('recipes', result)

    def test_delay_words_come_from_the_table(self):
        self.assertEqual(recipe_delay.DELAY_WORDS, {'hour': 'about an hour', 'half_day': 'about half a day',
                                                    'day': 'about a day'})

    # --- call back too early: still looking --------------------------------------------------------------------

    def test_recall_not_ready_says_not_yet_without_facts(self):
        result, model = self.ask('Alors, la corde ?', json.dumps({'say': 'Pas encore, rappelle plus tard.'}),
                                 field=pending(['MakeSheetRope'], False))
        self.assertEqual(len(model.calls), 1)
        system = model.calls[0][0][0]['content']
        self.assertIn('not found it yet', system)
        self.assertIn('call back later', system)
        self.assertNotIn('Corde en draps', system)
        self.assertEqual(result, ['Pas encore, rappelle plus tard.'])

    def test_recall_not_ready_repeating_the_same_search_is_not_a_new_search(self):
        result, model = self.ask('Alors, la corde ?', self.search_reply('sheet rope'), 'Toujours en train de chercher.',
                                 field=pending(['MakeSheetRope'], False))
        self.assertEqual(len(model.calls), 2)
        second = model.calls[1][0][-1]['content']
        self.assertIn('not found it yet', second)
        self.assertNotIn('Corde en draps', second)
        self.assertEqual(result, ['Toujours en train de chercher.'])

    def test_new_question_while_waiting_replaces_the_search(self):
        result, _ = self.ask('Et une soupe ?', self.search_reply('soup'), 'Rappelle dans une heure.',
                             field=pending(['MakeSheetRope'], False))
        self.assertEqual(result['searched'], {'ids': ['CookPotOfSoup'], 'keywords': ['soup']})

    # --- call back on time: the answer -------------------------------------------------------------------------

    def test_recall_ready_gives_the_facts_and_returns_them_delivered(self):
        result, model = self.ask('Alors, la corde ?',
                                 json.dumps({'say': 'Deux draps déchirés et une aiguille.', 'actions': []}),
                                 field=pending(['MakeSheetRope'], True))
        self.assertEqual(len(model.calls), 1)
        system = model.calls[0][0][0]['content']
        self.assertIn('called back', system)
        self.assertIn('2 x Draps déchirés or Bandes de jean', system)
        self.assertIn('never invent', system)
        self.assertNotIn('"recipe_search"', system)
        self.assertEqual(result['recipes'], ['MakeSheetRope'])
        self.assertEqual(result['say'], ['Deux draps déchirés et une aiguille.'])
        self.assertNotIn('searched', result)

    def test_recall_ready_with_nothing_found_says_so_and_delivers_nothing(self):
        result, model = self.ask('Alors ?', json.dumps({'say': 'Rien trouvé.'}), field=pending([], True, ['airplane']))
        system = model.calls[0][0][0]['content']
        self.assertIn('found nothing', system)
        self.assertEqual(result['recipes'], [])

    def test_ids_unknown_to_the_index_or_the_jobs_are_not_delivered(self):
        result, model = self.ask('Alors ?', json.dumps({'say': 'Voila.'}),
                                 field=pending(['MakeBandage', 'Nope', 'CookPotOfSoup'], True))
        self.assertNotIn('Make Bandage', model.calls[0][0][0]['content'])
        self.assertEqual(result['recipes'], ['CookPotOfSoup'])

    # --- bounds ------------------------------------------------------------------------------------------------

    def test_unreadable_field_is_ignored_and_logged(self):
        for bad in ('zz', npc.encode({'ids': 3, 'ready': True}).hex(), npc.encode({'ready': 'yes', 'ids': []}).hex()):
            LOGS.clear()
            result, model = self.ask('?', json.dumps({'say': 'Hm.'}), field=bad)
            self.assertNotIn('called back', model.calls[0][0][0]['content'])
            self.assertEqual(result, ['Hm.'])
            self.assertTrue(any('recipe search state ignored' in line for line in LOGS), LOGS)

    def test_caller_below_the_level_gets_no_delivery(self):
        result, model = self.ask('Alors ?', json.dumps({'say': 'Non.'}), field=pending(['MakeSheetRope'], True),
                                 level='bad')
        self.assertNotIn('Corde en draps', model.calls[0][0][0]['content'])
        self.assertEqual(result, ['Non.'])


if __name__ == '__main__':
    unittest.main()
