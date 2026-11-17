"""Recipe search of the bridge (E27-T03, ADR recettes-radio D01): bridge/recipe_search.py.

    python RadioSurvivor/tests/radiosurvivor/test_recipe_search.py

search(recipes, keywords) scores each recipe of the index by the English keywords the model gave: words of the id
(CamelCase and underscores split), of the name, of the output item types (module stripped) and of the output names,
case-insensitive, simple English plural tolerated; best first, ties by id, at most MAX_RESULTS.
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
import recipe_search  # noqa: E402
from recipe_index import RecipeIndex  # noqa: E402


def item(full_type: str, name: str = '') -> dict:
    return {'item': full_type, 'name': name or full_type.split('.')[-1]}


def recipe(rid: str, job: str = 'tailoring', outputs=(), name: str = '', **extra) -> dict:
    return {'id': rid, 'name': name or rid, 'category': 'Cat', 'job': job, 'inputs': [],
            'outputs': [{'items': list(choices), 'count': 1} for choices in outputs], 'skills': [], 'learn': False,
            'learned_from': [], 'mod': '', **extra}


def ids(found: list[dict]) -> list[str]:
    return [r['id'] for r in found]


class WordsTests(unittest.TestCase):
    def test_camel_case_underscores_and_module(self):
        self.assertEqual(recipe_search.words('MakeTVStand'), ['make', 'tv', 'stand'])
        self.assertEqual(recipe_search.words('Make_Sheet_Rope'), ['make', 'sheet', 'rope'])
        self.assertEqual(recipe_search.item_words('Base.SheetRope'), ['sheet', 'rope'])

    def test_simple_english_plural(self):
        for plural, single in (('bandages', 'bandage'), ('batteries', 'battery'), ('boxes', 'box'),
                               ('glasses', 'glass'), ('ropes', 'rope'), ('glass', 'glass'), ('gas', 'gas')):
            self.assertEqual(recipe_search.singular(plural), single, plural)


class SearchTests(unittest.TestCase):
    def test_match_by_id_words(self):
        recipes = [recipe('MakeSheetRope'), recipe('MakeStew', job='cooking')]
        self.assertEqual(ids(recipe_search.search(recipes, ['sheet rope'])), ['MakeSheetRope'])

    def test_match_by_output_type_when_id_and_name_say_nothing(self):
        # Name in the server language (French): the item type, English, still matches.
        recipes = [recipe('Craft01', name='Corde en draps', outputs=[[item('Base.SheetRope', 'Corde en draps')]]),
                   recipe('Craft02', outputs=[[item('Base.Thread')]])]
        self.assertEqual(ids(recipe_search.search(recipes, ['rope'])), ['Craft01'])

    def test_match_by_output_name(self):
        recipes = [recipe('Craft01', outputs=[[item('Base.Item42', 'Leather Strips')]])]
        self.assertEqual(ids(recipe_search.search(recipes, ['leather strip'])), ['Craft01'])

    def test_any_alternative_of_an_output_line_matches(self):
        recipes = [recipe('Craft01', outputs=[[item('Base.Plank'), item('Base.Bandage')]])]
        self.assertEqual(ids(recipe_search.search(recipes, ['bandages'])), ['Craft01'])

    def test_case_insensitive(self):
        recipes = [recipe('MakeSheetRope')]
        self.assertEqual(ids(recipe_search.search(recipes, ['SHEET Rope'])), ['MakeSheetRope'])

    def test_no_match(self):
        recipes = [recipe('MakeSheetRope'), recipe('MakeStew', job='cooking')]
        self.assertEqual(recipe_search.search(recipes, ['airplane']), [])
        self.assertEqual(recipe_search.search(recipes, []), [])
        self.assertEqual(recipe_search.search([], ['rope']), [])

    def test_ranking_best_first_ties_by_id_at_most_five(self):
        recipes = [recipe(f'Rope{n}Thing', outputs=[[item('Base.Thing')]]) for n in (7, 3, 5, 1, 2, 6, 4)]
        recipes.append(recipe('Craft09', outputs=[[item('Base.SheetRope')]]))   # output match: best
        found = ids(recipe_search.search(recipes, ['rope']))
        self.assertEqual(found, ['Craft09', 'Rope1Thing', 'Rope2Thing', 'Rope3Thing', 'Rope4Thing'])
        self.assertEqual(len(found), recipe_search.MAX_RESULTS)
        self.assertEqual(ids(recipe_search.search(list(reversed(recipes)), ['rope'])), found)

    def test_a_phrase_counts_only_when_all_its_words_match(self):
        # Real-model trial: a bandage question gave ["bandage", "ripped sheets"]; "sheets" alone must not pull in the
        # sheet rope.
        recipes = [recipe('MakeSheetRope', name='Corde en draps', outputs=[[item('Base.SheetRope')]]),
                   recipe('Rope1Thing', outputs=[[item('Base.Thing')]])]
        self.assertEqual(recipe_search.search(recipes, ['bandage', 'ripped sheets']), [])
        self.assertEqual(ids(recipe_search.search(recipes, ['sheet rope'])), ['MakeSheetRope'])
        self.assertEqual(ids(recipe_search.search(recipes, ['sheet rope', 'ripped sheets'])), ['MakeSheetRope'])

    def test_score_sums_the_fully_matched_phrases(self):
        recipes = [recipe('MakeSheetRope', outputs=[[item('Base.SheetRope')]]),
                   recipe('Craft02', outputs=[[item('Base.Rope')]])]
        self.assertEqual(recipe_search.score(recipes[0], [['sheet', 'rope'], ['rope']]), 9)
        self.assertEqual(recipe_search.score(recipes[1], [['sheet', 'rope'], ['rope']]), 3)
        self.assertEqual(ids(recipe_search.search(recipes, ['sheet rope', 'rope'])), ['MakeSheetRope', 'Craft02'])

    def test_output_match_outranks_id_match(self):
        recipes = [recipe('RopeFromSheet', outputs=[[item('Base.Thread')]]),
                   recipe('Craft01', outputs=[[item('Base.Rope')]])]
        self.assertEqual(ids(recipe_search.search(recipes, ['rope'])), ['Craft01', 'RopeFromSheet'])

    def test_jobs_filter_through_the_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'recipes.json').write_text(json.dumps({'format': 1, 'written': 1, 'recipes': [
                recipe('MakeBandage', job='medical', outputs=[[item('Base.Bandage')]]),
                recipe('MakeSheetRope', outputs=[[item('Base.SheetRope')]])]}), encoding='utf-8')
            index = RecipeIndex(Path(tmp), log=lambda _: None)
            self.assertEqual(recipe_search.search(index.for_jobs(['tailoring']), ['bandage']), [])
            self.assertEqual(ids(recipe_search.search(index.for_jobs(['medical']), ['bandage'])), ['MakeBandage'])


if __name__ == '__main__':
    unittest.main()
