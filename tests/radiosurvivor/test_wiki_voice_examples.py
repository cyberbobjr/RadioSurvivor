"""E22-T16: the example voices of the wiki page 14 stay true (docs/wiki/fr/14-exemples-de-voix.md,
docs/wiki/en/14-voice-examples.md).

    python RadioSurvivor/tests/radiosurvivor/test_wiki_voice_examples.py

Every fenced block marked ```persona of both pages is a whole sheet, as the voice workshop writes it. The one block
marked ```places of each page holds the [place] sections the examples name (E25-T04), added after the shipped shared
places (personas/_places.txt), as the "Places" tab of the workshop adds them: both readers accept the joined file. Each
sheet is:
- read by the REAL game reader (RS_Persona.lua in lupa, loader of tools/gen_atelier_catalog.py with every mission
  template, reward kind and arrival mode of the mod) with the weights of the game's item scripts (catalog.json, the
  same weights RS_ItemWeights reads in game) instead of the weights of the shipped sheets only, and by the bridge
  reader (bridge/persona_store.py);
- written back unchanged by the workshop's own sheet model, with nothing to flag by its light checks over the same
  shared places (node, skipped when node is missing);
- a voice of its own (E24-T01): the radio it needs (radio=) or one fixed frequency (frequency=) that no shipped voice
  and no other example holds, and an id no shipped voice has;
- a trader whose every good has a sale value in the trade scale (CoreAI/CA_TradeValues.lua): a good without one is
  accepted by the reader but every offer that names it is refused (RS_Trade evaluate, "not_in_stock").
Both pages give the same voices, in the same order, with the same voice ids, kinds of sections and English
personality text.
`example_sheets(lang)`, `shared_places(lang)` and `GameReader` are also used by tools/atelier_doc_shots.py to load the examples it
photographs.
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
sys.path.insert(0, str(ROOT / 'bridge'))
from test_atelier_ui import NODE, bridge_reads, node_prelude, run_node  # noqa: E402
from test_personas import LuaReader  # noqa: E402

PAGES = {'fr': ROOT / 'docs/wiki/fr/14-exemples-de-voix.md', 'en': ROOT / 'docs/wiki/en/14-voice-examples.md'}
CATALOG = ROOT / 'bridge/atelier/catalog.json'
SHIPPED = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/personas'
EXAMPLES = 4
FENCE = re.compile(r'^```persona\n(.*?)^```$', re.MULTILINE | re.DOTALL)
PLACES_FENCE = re.compile(r'^```places\n(.*?)^```$', re.MULTILINE | re.DOTALL)


def example_sheets(lang: str) -> list[tuple[str, str]]:
    """(voice id, sheet text) of every ```persona block of the page of `lang`, in page order."""
    text = PAGES[lang].read_text(encoding='utf-8')
    out = []
    for block in FENCE.findall(text):
        match = re.search(r'^id=([a-z0-9_]+)$', block, re.MULTILINE)
        out.append((match.group(1) if match else '', block))
    return out


def shared_places(lang: str) -> str:
    """The shipped shared places followed by the one ```places block of the page of `lang` (the places its examples
    name), as one _places.txt."""
    blocks = PLACES_FENCE.findall(PAGES[lang].read_text(encoding='utf-8'))
    assert len(blocks) == 1, f'{lang}: {len(blocks)} ```places blocks (one expected)'
    return (SHIPPED / '_places.txt').read_text(encoding='utf-8').rstrip('\n') + '\n\n' + blocks[0]


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

    def read(self, text: str, voice_id: str, places: str):
        """('OK', Lua table) or (None, reason); `places`: the shared places file next to the sheet."""
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / f'{voice_id}.txt').write_bytes(text.encode('utf-8'))
            (folder / '_places.txt').write_bytes(places.encode('utf-8'))
            self.lua.rt.globals().getFileReader = lambda name, create: (
                LuaReader(folder / name) if (folder / name).is_file() else None)
            self.lua.folder = folder        # the shared places of this folder (LuaPersona.places)
            result = self.lua.read(f'{voice_id}.txt')
            return result if isinstance(result, tuple) else ('OK', result)

    def sale_value(self, full_type: str) -> float:
        return self.values.sellValue(full_type)


def head_value(text: str, key: str) -> str | None:
    match = re.search(rf'^{key}=(.+)$', text, re.MULTILINE)
    return match.group(1).strip() if match else None


def shipped_fixed() -> dict[str, int]:
    """Voice id -> fixed frequency (kHz) of the shipped voices that have one (catalog.json, read from the mod)."""
    return {vid: v['frequencyKhz'] for vid, v in catalog()['voices'].items() if v.get('frequencyKhz') is not None}


def shape(text: str) -> tuple[list[str], str]:
    """Kinds of the sections and personality text of a sheet: what both languages share (the ids of the places, lots
    and categories are made by the workshop from names written in the page's language)."""
    head, _, prompt = text.partition('\n[prompt]\n')
    return re.findall(r'^\[([a-z]+)[^\]]*\]$', head, re.MULTILINE), prompt


class WikiVoiceExamplesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sheets = {lang: example_sheets(lang) for lang in PAGES}
        cls.places = {lang: shared_places(lang) for lang in PAGES}
        cls.reader = GameReader()

    def test_the_example_places_join_the_shipped_ones(self):
        import persona_store
        for lang, text in self.places.items():
            with self.subTest(lang=lang):
                lines = persona_store.split_lines(text)
                persona_store.parse_places_lines(lines)
                read = self.reader.lua.module.parsePlaces(self.reader.lua.rt.table_from(lines))
                self.assertFalse(isinstance(read, tuple), f'{lang}: the game reader refuses the places: {read}')

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
                    status, detail = self.reader.read(text, voice_id, self.places[lang])
                    self.assertEqual(status, 'OK', f'{lang} {voice_id}: the game reader refuses: {detail}')
                    sheet = bridge_reads(text, voice_id, self.places[lang])
                    self.assertEqual(sheet.id, voice_id)

    def test_every_good_of_a_trader_can_be_sold(self):
        for lang, sheets in self.sheets.items():
            for voice_id, text in sheets:
                for full_type in re.findall(r'^item=([A-Za-z0-9_.]+):', text.partition('\n[trade]\n')[2]
                                            .split('\n[', 1)[0], re.MULTILINE):
                    with self.subTest(lang=lang, voice=voice_id, item=full_type):
                        self.assertGreater(self.reader.sale_value(full_type), 0,
                                           f'{full_type} has no sale value: the trader can never sell it')

    def test_examples_never_collide_on_a_frequency(self):
        shipped = {p.stem for p in SHIPPED.glob('*.txt') if not p.name.startswith('_')}
        levels = catalog()['header']['choices']['radio']
        for lang, sheets in self.sheets.items():
            taken = {khz: vid for vid, khz in shipped_fixed().items()}
            for voice_id, text in sheets:
                with self.subTest(lang=lang, voice=voice_id):
                    radio, fixed = head_value(text, 'radio'), head_value(text, 'frequency')
                    self.assertTrue((radio is None) != (fixed is None), f'{voice_id}: radio= or frequency=, one of them')
                    if radio is not None:
                        self.assertIn(radio, levels)
                    else:
                        khz = round(float(fixed) * 1000)
                        self.assertNotIn(khz, taken, f'{voice_id} {fixed} MHz is the frequency of {taken.get(khz)}')
                        taken[khz] = voice_id
                    self.assertNotIn(voice_id, shipped, f'{voice_id}: id of a shipped voice')
        self.assertTrue(any(head_value(t, 'frequency') for _, t in self.sheets['fr']), 'one example shows a fixed frequency')

    @unittest.skipUnless(NODE, 'node is not installed')
    def test_the_workshop_keeps_them_and_flags_nothing(self):
        texts = {f'{lang}/{voice_id}': text for lang, sheets in self.sheets.items() for voice_id, text in sheets}
        with tempfile.TemporaryDirectory() as tmp:     # the shared places as files: too long for a command line
            files = {}
            for lang, text in self.places.items():
                files[lang] = str(Path(tmp) / f'{lang}_places.txt')
                Path(files[lang]).write_bytes(text.encode('utf-8'))
            result = run_node(node_prelude() + f"""
const shared = {{}};
for (const [lang, path] of Object.entries({json.dumps(files)})) {{
  shared[lang] = places.list(places.parsePlaces(fs.readFileSync(path, 'utf8')));
}}
const out = {{}};
for (const [key, text] of Object.entries({json.dumps(texts)})) {{
  const model = sheet.parse(text);
  const [lang, id] = key.split('/');
  out[key] = {{ same: sheet.serialize(model) === text, checks: check(model, catalog, id, shared[lang]) }};
}}
console.log(JSON.stringify(out));
""")
        for key, entry in result.items():
            with self.subTest(key):
                self.assertTrue(entry['same'], f'{key}: the workshop would rewrite the sheet')
                self.assertEqual(entry['checks'], [], f'{key}: the workshop flags points')


if __name__ == '__main__':
    unittest.main(verbosity=1)
