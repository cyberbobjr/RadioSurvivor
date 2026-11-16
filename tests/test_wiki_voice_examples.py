"""E22-T16: the example voices of the wiki page 14 stay true (docs/wiki/fr/14-exemples-de-voix.md,
docs/wiki/en/14-voice-examples.md).

    python RadioSurvivor/tests/test_wiki_voice_examples.py

Every fenced block marked ```persona of both pages is a whole sheet, as the voice workshop writes it. Each one is:
- read by the REAL game reader (RS_Persona.lua in lupa, loader of tools/gen_atelier_catalog.py with every mission
  template, reward kind and arrival mode of the mod) with the weights of the game's item scripts (catalog.json, the
  same weights RS_ItemWeights reads in game) instead of the weights of the shipped sheets only, and by the bridge
  reader (bridge/persona_store.py);
- written back unchanged by the workshop's own sheet model, with nothing to flag by its light checks (node, skipped
  when node is missing);
- a voice of its own: a band no shipped voice and no other example uses;
- a trader whose every good has a sale value in the trade scale (CoreAI/CA_TradeValues.lua): a good without one is
  accepted by the reader but every offer that names it is refused (RS_Trade evaluate, "not_in_stock").
Both pages give the same voices, in the same order, with the same voice ids, kinds of sections and English
personality text.
`example_sheets(lang)` and `GameReader` are also used by tools/atelier_doc_shots.py to load the examples it
photographs.
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'bridge'))
from test_atelier_ui import NODE, bridge_reads, node_prelude, run_node  # noqa: E402
from test_personas import LuaReader  # noqa: E402

PAGES = {'fr': ROOT / 'docs/wiki/fr/14-exemples-de-voix.md', 'en': ROOT / 'docs/wiki/en/14-voice-examples.md'}
CATALOG = ROOT / 'bridge/atelier/catalog.json'
SHIPPED = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/personas'
EXAMPLES = 4
FENCE = re.compile(r'^```persona\n(.*?)^```$', re.MULTILINE | re.DOTALL)


def example_sheets(lang: str) -> list[tuple[str, str]]:
    """(voice id, sheet text) of every ```persona block of the page of `lang`, in page order."""
    text = PAGES[lang].read_text(encoding='utf-8')
    out = []
    for block in FENCE.findall(text):
        match = re.search(r'^id=([a-z0-9_]+)$', block, re.MULTILINE)
        out.append((match.group(1) if match else '', block))
    return out


def catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding='utf-8'))


def game_weights_lua() -> str:
    """RS_ItemWeights fed with the weight of every item of the game (catalog.json, read from the item scripts)."""
    pairs = ', '.join(f'["{t}"] = {e["kg"]!r}' for t, e in sorted(catalog()['items'].items())
                      if isinstance(e.get('kg'), (int, float)))
    return f'require("RadioSurvivor/RS_ItemWeights").use({{{pairs}}})'


class GameReader:
    """The real RS_Persona.readFile with the server rules, every mission template and the game's item weights."""

    def __init__(self):
        import gen_atelier_catalog as gen
        self.lua = gen.load_mod()
        self.lua.rt.execute(game_weights_lua())
        self.values = self.lua.rt.eval('require("CoreAI/CA_TradeValues")')

    def read(self, text: str, voice_id: str):
        """('OK', Lua table) or (None, reason)."""
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / f'{voice_id}.txt').write_bytes(text.encode('utf-8'))
            self.lua.rt.globals().getFileReader = lambda name, create: (
                LuaReader(folder / name) if (folder / name).is_file() else None)
            result = self.lua.read(f'{voice_id}.txt')
            return result if isinstance(result, tuple) else ('OK', result)

    def sale_value(self, full_type: str) -> float:
        return self.values.sellValue(full_type)


def bands(text: str) -> list[tuple[float, float]]:
    match = re.search(r'^frequency_range=(.+)$', text, re.MULTILINE)
    out = []
    for part in (match.group(1).split(',') if match else []):
        low, high = part.split('-')
        out.append((float(low), float(high)))
    return out


def shipped_bands() -> dict[str, list[tuple[float, float]]]:
    return {p.stem: bands(p.read_text(encoding='utf-8')) for p in SHIPPED.glob('*.txt') if not p.name.startswith('_')}


def overlap(a: tuple[float, float], b: tuple[float, float]) -> bool:
    return a[0] <= b[1] and b[0] <= a[1]


def shape(text: str) -> tuple[list[str], str]:
    """Kinds of the sections and personality text of a sheet: what both languages share (the ids of the places, lots
    and categories are made by the workshop from names written in the page's language)."""
    head, _, prompt = text.partition('\n[prompt]\n')
    return re.findall(r'^\[([a-z]+)[^\]]*\]$', head, re.MULTILINE), prompt


class WikiVoiceExamplesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sheets = {lang: example_sheets(lang) for lang in PAGES}
        cls.reader = GameReader()

    def test_both_pages_give_the_same_voices(self):
        fr, en = self.sheets['fr'], self.sheets['en']
        self.assertEqual(len(fr), EXAMPLES)
        self.assertEqual([i for i, _ in fr], [i for i, _ in en])
        for (voice_id, fr_text), (_, en_text) in zip(fr, en):
            with self.subTest(voice_id):
                self.assertEqual(shape(fr_text), shape(en_text), f'{voice_id}: sections or personality differ')

    def test_every_example_is_accepted_by_the_game_and_the_bridge(self):
        for lang, sheets in self.sheets.items():
            for voice_id, text in sheets:
                with self.subTest(lang=lang, voice=voice_id):
                    status, detail = self.reader.read(text, voice_id)
                    self.assertEqual(status, 'OK', f'{lang} {voice_id}: the game reader refuses: {detail}')
                    sheet = bridge_reads(text, voice_id)
                    self.assertEqual(sheet.id, voice_id)

    def test_every_good_of_a_trader_can_be_sold(self):
        for lang, sheets in self.sheets.items():
            for voice_id, text in sheets:
                for full_type in re.findall(r'^item=([A-Za-z0-9_.]+):', text.partition('\n[trade]\n')[2]
                                            .split('\n[', 1)[0], re.MULTILINE):
                    with self.subTest(lang=lang, voice=voice_id, item=full_type):
                        self.assertGreater(self.reader.sale_value(full_type), 0,
                                           f'{full_type} has no sale value: the trader can never sell it')

    def test_examples_use_free_bands(self):
        taken = shipped_bands()
        seen: dict[str, list[tuple[float, float]]] = {}
        for voice_id, text in self.sheets['fr']:
            mine = bands(text)
            self.assertTrue(mine, f'{voice_id}: no frequency_range')
            for other, theirs in {**taken, **seen}.items():
                with self.subTest(voice=voice_id, other=other):
                    self.assertFalse(any(overlap(a, b) for a in mine for b in theirs),
                                     f'{voice_id} {mine} crosses {other} {theirs}')
            self.assertNotIn(voice_id, taken, f'{voice_id}: id of a shipped voice')
            seen[voice_id] = mine

    @unittest.skipUnless(NODE, 'node is not installed')
    def test_the_workshop_keeps_them_and_flags_nothing(self):
        texts = {f'{lang}/{voice_id}': text for lang, sheets in self.sheets.items() for voice_id, text in sheets}
        script = node_prelude() + f"""
const out = {{}};
for (const [key, text] of Object.entries({json.dumps(texts)})) {{
  const model = sheet.parse(text);
  out[key] = {{ same: sheet.serialize(model) === text, checks: check(model, catalog, key.split('/')[1]) }};
}}
console.log(JSON.stringify(out));
"""
        result = run_node(script)
        for key, entry in result.items():
            with self.subTest(key):
                self.assertTrue(entry['same'], f'{key}: the workshop would rewrite the sheet')
                self.assertEqual(entry['checks'], [], f'{key}: the workshop flags points')


if __name__ == '__main__':
    unittest.main(verbosity=1)
