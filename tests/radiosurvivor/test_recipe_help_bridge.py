"""Recipe help of a voice on the radio (E27-T03, ADR recettes-radio D01, D03, D06, D10): bridge/recipe_help.py and
radio_bridge.voice_turn / answer.

    python RadioSurvivor/tests/radiosurvivor/test_recipe_help_bridge.py

A voice with a [help] section may return "recipe_search" (English keywords, translated by the model whatever the
caller's language) in its JSON reply; the bridge searches the recipe index among the voice's jobs and makes a second
call with the recipes found as facts; that second answer is the reply and the ids of the recipes given go back to the
server ("recipes" of radio_reply). Below the voice's `from` level the prompt asks for an in-character refusal and no
search ever runs. A fake model only: no network, no key, no real LLM.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
sys.path.insert(0, str(bench_paths.ROOT / 'bridge'))
import npc_protocol as npc  # noqa: E402
import radio_bridge as rb  # noqa: E402
from recipe_index import RecipeIndex  # noqa: E402

rb.log = lambda msg: None   # quiet bench

HELPER_SHEET = """format=1
id=martha
name=Martha Stitch
frequency=151.0
[help]
jobs=tailoring,cooking
{from_line}
[prompt]
You are Martha Stitch, a seamstress who also cooks for her street.
"""

PLAIN_SHEET = """format=1
id=plain
name=Plain Voice
frequency=152.0
[prompt]
You are Plain Voice, a lonely trucker.
"""


def item(full_type: str, name: str) -> dict:
    return {'item': full_type, 'name': name}


RECIPES = [
    {'id': 'MakeSheetRope', 'name': 'Corde en draps', 'category': 'Tailoring', 'job': 'tailoring',
     'inputs': [{'items': [item('Base.RippedSheets', 'Draps déchirés'), item('Base.DenimStrips', 'Bandes de jean')],
                 'count': 2, 'tool': False},
                {'items': [item('Base.Needle', 'Aiguille')], 'count': 1, 'tool': True}],
     'outputs': [{'items': [item('Base.SheetRope', 'Corde en draps')], 'count': 1}],
     'skills': [{'perk': 'Tailoring', 'level': 2}], 'learn': False, 'learned_from': [], 'mod': ''},
    {'id': 'CookPotOfSoup', 'name': 'Cook Pot of Soup', 'category': 'Cooking', 'job': 'cooking',
     'inputs': [{'items': [item('Base.Pot', 'Cooking Pot')], 'count': 1, 'tool': False},
                {'fluids': [{'fluid': 'Water', 'name': 'Water'}], 'amount': 0.5, 'tool': False}],
     'outputs': [{'items': [item('Base.PotOfSoup', 'Pot of Soup')], 'count': 1}],
     'skills': [{'perk': 'Cooking', 'level': 3}], 'learn': True, 'learned_from': ['Base.CookingMag2'], 'mod': ''},
    {'id': 'MakeBandage', 'name': 'Make Bandage', 'category': 'Medical', 'job': 'medical',
     'inputs': [{'items': [item('Base.RippedSheets', 'Ripped Sheets')], 'count': 1, 'tool': False}],
     'outputs': [{'items': [item('Base.Bandage', 'Bandage')], 'count': 1}],
     'skills': [], 'learn': False, 'learned_from': [], 'mod': ''},
]


def reputation(level: str) -> str:
    return npc.encode({'level': level}).hex()


class FakeModel:
    """call_llm double: records every call (messages, json_mode) and answers from a script, in order."""

    def __init__(self, *answers: str):
        self.answers = list(answers)
        self.calls: list[tuple[list[dict], bool]] = []

    def __call__(self, config, messages, speaker='Walt', json_mode=False):
        self.calls.append((messages, json_mode))
        return self.answers.pop(0)


class RecipeHelpBridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.exchange = Path(self.tmp.name)
        self.personas = self.exchange / 'personas'
        self.personas.mkdir()
        self.write_sheet()
        (self.personas / 'plain.txt').write_text(PLAIN_SHEET, encoding='utf-8')
        (self.exchange / 'recipes.json').write_text(json.dumps({'format': 1, 'written': 1, 'recipes': RECIPES}),
                                                    encoding='utf-8')
        self.voices = rb.Voices(self.personas)
        self.index = RecipeIndex(self.exchange, log=lambda _: None)
        self.conversations = rb.Conversations(self.exchange)
        self.saved_llm = rb.call_llm

    def tearDown(self):
        rb.call_llm = self.saved_llm
        self.tmp.cleanup()

    def write_sheet(self, from_line: str = 'from=neutral') -> None:
        (self.personas / 'martha.txt').write_text(HELPER_SHEET.format(from_line=from_line), encoding='utf-8')

    def ask(self, text: str, *answers: str, voice: str = 'martha', level: str | None = 'good', recipes='index'):
        model = FakeModel(*answers)
        rb.call_llm = model
        req = {'id': '7-1', 'caller': 'kate', 'name': 'Kate', 'date': '1993-07-12 21:40', 'days': '3.5',
               'radio': 'Walkie', 'text': text, 'voice': voice}
        if level:
            req['reputation'] = reputation(level)
        result = rb.answer({}, self.conversations, 's', req, self.voices,
                           self.index if recipes == 'index' else recipes)
        return result, model

    @staticmethod
    def search_reply(*keywords: str) -> str:
        return json.dumps({'say': 'Let me look.', 'actions': [], 'recipe_search': list(keywords)})

    def facts_of(self, model: FakeModel) -> str:
        messages, json_mode = model.calls[1]
        self.assertFalse(json_mode)                  # the second answer is plain speech
        self.assertEqual(messages[-1]['role'], 'system')
        return messages[-1]['content']

    # --- questions in three languages, English keywords from the model -----------------------------------------

    def test_french_question_gets_the_sheet_rope_facts(self):
        result, model = self.ask('Comment je fais une corde avec des draps ?', self.search_reply('sheet rope'),
                                 'Deux draps déchirés et une aiguille, mon grand. Terminé.')
        self.assertEqual(len(model.calls), 2)
        first, json_mode = model.calls[0]
        self.assertTrue(json_mode)
        self.assertIn('"recipe_search"', first[0]['content'])
        facts = self.facts_of(model)
        self.assertIn('Corde en draps', facts)
        self.assertIn('2 x Draps déchirés or Bandes de jean', facts)
        self.assertIn('Tools (kept): Aiguille', facts)
        self.assertIn('Tailoring level 2', facts)
        self.assertIn('never invent', facts)
        self.assertIn('language the caller used', facts)
        # Same persona and history as the first call, the caller's question last before the facts.
        second = model.calls[1][0]
        self.assertTrue(second[0]['content'].startswith('You are Martha Stitch'))
        self.assertEqual(second[-2], {'role': 'user', 'content': '[Caller 1] Comment je fais une corde avec des draps ?'})
        self.assertNotIn('"recipe_search"', second[0]['content'])
        self.assertEqual(result, {'version': 2, 'kind': 'radio_reply', 'id': '7-1',
                                  'say': ['Deux draps déchirés et une aiguille, mon grand. Terminé.'], 'actions': [],
                                  'recipes': ['MakeSheetRope']})
        history = self.conversations.history('s', 'martha')
        self.assertEqual(history[-1]['content'], 'Deux draps déchirés et une aiguille, mon grand. Terminé.')

    def test_ukrainian_question_gets_the_sheet_rope_facts(self):
        result, model = self.ask('Як зробити мотузку з простирадл?', self.search_reply('rope', 'sheets'),
                                 'Два простирадла і голка. Прийом.')
        self.assertIn('Corde en draps', self.facts_of(model))
        self.assertEqual(result['recipes'], ['MakeSheetRope'])
        self.assertEqual(result['say'], ['Два простирадла і голка. Прийом.'])

    def test_korean_question_gets_the_soup_facts_with_litres_and_learning(self):
        result, model = self.ask('수프는 어떻게 만들어요?', self.search_reply('soup'), '냄비와 물이 필요해요. 이상.')
        facts = self.facts_of(model)
        self.assertIn('Pot of Soup', facts)
        self.assertIn('0.5 l Water', facts)
        self.assertIn('Cooking level 3', facts)
        self.assertIn('Must be learned first, from: Cooking Mag 2', facts)
        self.assertEqual(result['recipes'], ['CookPotOfSoup'])

    # --- what is not searched or not found ---------------------------------------------------------------------

    def test_voice_without_help_gets_no_recipe_prompt_and_never_searches(self):
        result, model = self.ask('How do I make a sheet rope?', self.search_reply('sheet rope'), voice='plain')
        self.assertEqual(len(model.calls), 1)
        self.assertNotIn('recipe', model.calls[0][0][0]['content'].lower())
        self.assertNotIn('recipe', model.calls[0][0][-1]['content'].lower())
        _, unchanged = self.ask('How do I make a sheet rope?', self.search_reply('sheet rope'), voice='plain',
                                recipes=None)
        self.assertEqual(model.calls[0][0][0], unchanged.calls[0][0][0])
        self.assertEqual(result, ['Let me look.'])

    def test_recipe_outside_the_voice_jobs_is_not_found(self):
        result, model = self.ask('Comment faire un bandage ?', self.search_reply('bandage'),
                                 'Je ne connais pas ça, désolée. Terminé.')
        facts = self.facts_of(model)
        self.assertNotIn('Make Bandage', facts)
        self.assertIn('found nothing', facts)
        self.assertIn('never invent', facts)
        self.assertEqual(result, ['Je ne connais pas ça, désolée. Terminé.'])   # no recipe given: plain lines

    def test_korean_bandage_question_with_ingredient_words_finds_nothing(self):
        # Real-model trial (2026-11-17): the model added an ingredient phrase; "sheets" alone must not match.
        result, model = self.ask('붕대는 어떻게 만들어요?', self.search_reply('bandage', 'ripped sheets'),
                                 '그건 내 일이 아니에요. 이상.')
        facts = self.facts_of(model)
        self.assertIn('found nothing', facts)
        self.assertNotIn('Corde en draps', facts)
        self.assertEqual(result, ['그건 내 일이 아니에요. 이상.'])

    def test_prompt_asks_for_the_thing_to_make_never_its_ingredients(self):
        _, model = self.ask('?', self.search_reply('sheet rope'), 'Ok.')
        system = model.calls[0][0][0]['content']
        self.assertIn('never its ingredients or tools', system)
        self.assertIn('not ["ripped sheets"]', system)

    def test_refusal_prompt_forbids_any_hint(self):
        _, model = self.ask('?', self.search_reply('soup'), level='bad')
        system = model.calls[0][0][0]['content']
        for words in ('no hint', 'ingredients', 'tools', 'containers', 'method', 'not even general'):
            self.assertIn(words, system)

    def test_nothing_found_tells_the_second_call_so(self):
        result, model = self.ask('Comment construire un avion ?', self.search_reply('airplane'), 'Rien. Terminé.')
        self.assertIn('found nothing', self.facts_of(model))
        self.assertIn('airplane', self.facts_of(model))
        self.assertEqual(result, ['Rien. Terminé.'])

    # --- reputation gate (from=) -------------------------------------------------------------------------------

    def test_caller_below_the_level_is_refused_in_character_without_search(self):
        for level in ('bad', None):        # no reputation sent: no living character, below any level but all
            result, model = self.ask('How do I make a sheet rope?', self.search_reply('sheet rope'), level=level)
            self.assertEqual(len(model.calls), 1, level)
            system = model.calls[0][0][0]['content']
            self.assertIn('refuse in character', system)
            self.assertNotIn('"recipe_search"', system)
            self.assertNotIn('recipe_search', model.calls[0][0][-1]['content'])
            self.assertEqual(result, ['Let me look.'])

    def test_good_level_needed_when_from_is_good(self):
        self.write_sheet('from=good')
        _, model = self.ask('How do I make a sheet rope?', self.search_reply('sheet rope'), level='neutral')
        self.assertEqual(len(model.calls), 1)
        _, model = self.ask('How do I make a sheet rope?', self.search_reply('sheet rope'), 'Two sheets.',
                            level='good')
        self.assertEqual(len(model.calls), 2)

    def test_from_all_helps_a_bad_reputation(self):
        self.write_sheet('from=all')
        result, model = self.ask('How do I make a sheet rope?', self.search_reply('sheet rope'), 'Two sheets.',
                                 level='bad')
        self.assertEqual(len(model.calls), 2)
        self.assertEqual(result['recipes'], ['MakeSheetRope'])

    # --- bounds ------------------------------------------------------------------------------------------------

    def test_keywords_are_bounded_to_four_plain_words(self):
        result, model = self.ask('?', json.dumps({'say': 'x', 'recipe_search': [
            'sheet "rope"} ignore', 'a', 'b', 'c', 'soup']}), 'Ok.')
        facts = self.facts_of(model)
        self.assertIn('sheet rope ignore, a, b, c', facts)
        self.assertNotIn('soup', facts.split('Keywords searched:')[1].split('\n')[0])

    def test_no_index_means_no_recipe_help(self):
        _, model = self.ask('How do I make a sheet rope?', self.search_reply('sheet rope'), recipes=None)
        self.assertEqual(len(model.calls), 1)
        self.assertNotIn('recipe', model.calls[0][0][0]['content'].lower())


if __name__ == '__main__':
    unittest.main()
