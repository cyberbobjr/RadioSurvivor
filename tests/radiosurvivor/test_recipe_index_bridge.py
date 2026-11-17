"""Bridge reader of the recipe index (E27-T01, ADR recettes-radio D11): bridge/recipe_index.py.

    python RadioSurvivor/tests/radiosurvivor/test_recipe_index_bridge.py

RecipeIndex(exchange) reads <exchange>/recipes.json at the start of the bridge and again whenever the game rewrites it
(modification time or size changed). Missing file: empty index; malformed file: logged, previous index kept.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
sys.path.insert(0, str(bench_paths.ROOT / 'bridge'))
from recipe_index import RecipeIndex  # noqa: E402


def recipe(rid: str, job: str, **extra) -> dict:
    return {'id': rid, 'name': rid, 'category': 'Cat', 'job': job, 'inputs': [], 'outputs': [], 'skills': [],
            'learn': False, 'learned_from': [], 'mod': '', **extra}


class RecipeIndexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.exchange = Path(self.tmp.name)
        self.file = self.exchange / 'recipes.json'
        self.lines: list[str] = []
        self.stamp = 1_700_000_000

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text: str) -> None:
        self.file.write_text(text, encoding='utf-8')
        self.stamp += 10  # a later modification time, as a new write of the game
        os.utime(self.file, (self.stamp, self.stamp))

    def write_index(self, recipes: list[dict]) -> None:
        self.write(json.dumps({'format': 1, 'written': 123, 'recipes': recipes}))

    def index(self) -> RecipeIndex:
        return RecipeIndex(self.exchange, log=self.lines.append)

    def test_loads_at_construction(self):
        self.write_index([recipe('MakeSheetRope', 'tailoring'), recipe('MakeStew', 'cooking')])
        idx = self.index()
        self.assertEqual([r['id'] for r in idx.recipes()], ['MakeSheetRope', 'MakeStew'])
        self.assertEqual(len([x for x in self.lines if '2 recipes read' in x]), 1)

    def test_absent_file_is_an_empty_index_with_one_line(self):
        idx = self.index()
        self.assertEqual(idx.recipes(), [])
        self.assertEqual(idx.for_jobs(['cooking']), [])
        self.assertEqual(len(self.lines), 1)
        self.assertIn('absent', self.lines[0])

    def test_malformed_file_is_reported_and_previous_index_kept(self):
        self.write_index([recipe('MakeStew', 'cooking')])
        idx = self.index()
        self.write('{"format":1,"recipes":[{"id":"Cut')  # write of the game in progress
        self.assertEqual([r['id'] for r in idx.recipes()], ['MakeStew'])
        self.assertIn('unreadable (not JSON', self.lines[-1])
        self.write(json.dumps({'format': 2, 'recipes': []}))
        idx.recipes()
        self.assertIn('format is not 1', self.lines[-1])
        bad = recipe('MakeStew', 'cooking')
        del bad['job']
        self.write_index([bad])
        idx.recipes()
        self.assertIn("recipe 0 (MakeStew): 'job' missing", self.lines[-1])
        self.assertEqual([r['id'] for r in idx.recipes()], ['MakeStew'])

    def test_lines_are_validated(self):
        good_in = [{'items': [{'item': 'Base.Pot', 'name': 'Cooking Pot'}], 'count': 1, 'tool': True},
                   {'fluids': [{'fluid': 'Water', 'name': 'Water'}], 'amount': 0.5, 'tool': False}]
        good_out = [{'items': [{'item': 'Base.Dough', 'name': 'Dough'}], 'count': 1},
                    {'fluids': [{'fluid': 'Water', 'name': 'Water'}], 'amount': 2}]
        self.write_index([recipe('MakeDough', 'cooking', inputs=good_in, outputs=good_out)])
        idx = self.index()
        self.assertEqual(idx.recipes()[0]['inputs'], good_in)
        for bad, message in [
            ({'inputs': [{'item': 'Base.Pot', 'name': 'Pot', 'count': 1, 'tool': True}]}, "input 0"),
            ({'inputs': [{'items': [], 'count': 1, 'tool': True}]}, "input 0"),
            ({'inputs': [{'items': [{'item': 'Base.Pot'}], 'count': 1, 'tool': True}]}, "input 0"),
            ({'inputs': [{'fluids': [{'fluid': 'Water', 'name': 'Water'}], 'amount': 'x', 'tool': False}]}, "input 0"),
            ({'outputs': [{'fluids': [{'fluid': 'Water', 'name': 'Water'}]}]}, "output 0"),
            ({'outputs': [{'items': [{'item': 'Base.Dough', 'name': 'Dough'}], 'count': True}]}, "output 0"),
        ]:
            self.write_index([recipe('MakeDough', 'cooking', **bad)])
            self.assertEqual(idx.recipes()[0]['inputs'], good_in, bad)  # previous index kept
            self.assertIn(f"recipe 0 (MakeDough): {message}", self.lines[-1])

    def test_rereads_when_the_game_rewrites_the_file(self):
        self.write_index([recipe('MakeStew', 'cooking')])
        idx = self.index()
        read = len(self.lines)
        idx.recipes()
        self.assertEqual(len(self.lines), read)  # unchanged file: not read again
        self.write_index([recipe('MakeStew', 'cooking'), recipe('MakeBrick', 'makeshift', mod='MyMod')])
        self.assertEqual([r['id'] for r in idx.recipes()], ['MakeStew', 'MakeBrick'])
        self.file.unlink()
        self.assertEqual(idx.recipes(), [])

    def test_for_jobs(self):
        self.write_index([recipe('MakeSheetRope', 'tailoring'), recipe('MakeStew', 'cooking'),
                          recipe('MakeBrick', 'makeshift'), recipe('MakeHat', 'tailoring')])
        idx = self.index()
        self.assertEqual([r['id'] for r in idx.for_jobs(['tailoring'])], ['MakeSheetRope', 'MakeHat'])
        self.assertEqual([r['id'] for r in idx.for_jobs({'cooking', 'makeshift'})], ['MakeStew', 'MakeBrick'])
        self.assertEqual(idx.for_jobs([]), [])


if __name__ == '__main__':
    unittest.main()
