"""E22-T03: page of the voice workshop (bridge/atelier, ADR atelier-voix D03, D05).

    python RadioSurvivor/tests/test_atelier_ui.py

The pure ES modules of the page run in node (skipped when node is missing):
- sheet.js reads and writes back every shipped sheet unchanged (comments, blank lines, unknown keys, order);
- a voice built from scratch with the assistant's model operations (voice.js: head, two places, a deliver mission
  with dead drops, a barricade mission after it, a reward pool) is accepted by the REAL game reader (RS_Persona.lua in
  lupa, loader of tools/gen_atelier_catalog.py with every mission template) and by the bridge reader;
- checks.js finds the expected message keys on a broken sheet and nothing on the shipped sheets;
- every i18n key the scripts use exists in i18n/fr.json and i18n/en.json, which hold the same keys.
The browser smoke test (Playwright) is tools/atelier_smoke.py, outside the suite.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATELIER = ROOT / 'bridge' / 'atelier'
SHIPPED = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/personas'
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT / 'bridge'))
NODE = shutil.which('node')
KEY_LITERAL = re.compile(r"""['"]([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)['"]""")
NOT_KEYS = re.compile(r'\.(js|json|txt|html|css)$')


def module_url(name: str) -> str:
    return (ATELIER / name).as_uri()


def run_node(script: str) -> object:
    """Runs an ES module script in node and returns the JSON it prints."""
    done = subprocess.run([NODE, '--input-type=module', '-e', script], capture_output=True, text=True,
                          encoding='utf-8', timeout=60)
    if done.returncode != 0:
        raise AssertionError(f'node failed ({done.returncode}): {done.stderr.strip()}')
    return json.loads(done.stdout)


def node_prelude() -> str:
    return (f"import fs from 'node:fs';\n"
            f"import * as sheet from '{module_url('sheet.js')}';\n"
            f"import * as voice from '{module_url('voice.js')}';\n"
            f"import {{ check }} from '{module_url('checks.js')}';\n"
            f"import {{ createCatalog }} from '{module_url('catalog.js')}';\n"
            f"const catalog = createCatalog(JSON.parse(fs.readFileSync({json.dumps(str(ATELIER / 'catalog.json'))}, 'utf8')));\n")


def shipped_sheets() -> list[Path]:
    return sorted(p for p in SHIPPED.glob('*.txt') if not p.name.startswith('_'))


def game_reads(text: str, voice_id: str):
    """Sheet `text` saved as <voice_id>.txt and read by the real RS_Persona.readFile with the server rules and every
    mission template of the mod: Lua table, or (None, reason)."""
    import gen_atelier_catalog as gen
    from test_personas import LuaReader
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        (folder / f'{voice_id}.txt').write_bytes(text.encode('utf-8'))
        lua = gen.load_mod()
        lua.rt.globals().getFileReader = lambda name, create: (
            LuaReader(folder / name) if (folder / name).is_file() else None)
        result = lua.read(f'{voice_id}.txt')
        return result if isinstance(result, tuple) else ('OK', lua.canonical(result))


def bridge_reads(text: str, voice_id: str):
    import persona_store
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / f'{voice_id}.txt'
        path.write_bytes(text.encode('utf-8'))
        return persona_store.load_file(path)


BUILD_SCRIPT = node_prelude() + r"""
const model = voice.newVoice({ id: 'bench_voice', name: 'Bench Voice', band: [270000, 279800], format: catalog.sheet.format });
sheet.setDescription(model, 'A voice built by the bench, step by step');
sheet.setValue(model.head, 'listen', '07:00-10:00,22:00-02:00');
sheet.setValue(model.head, 'actions', 'say,start_mission');
const mill = voice.addPlace(model, { label: 'Old mill', at: { x: '10600', y: '9300', z: '0' }, uses: ['mark', 'target'] });
const drop = voice.addPlace(model, { label: 'Dumpster behind the mill', at: { x: '10610', y: '9305', z: '0' }, uses: ['drop'] });
const deliver = voice.addMission(model, 'deliver', { items: 'medical', quantity: '2-4', drops: drop.id,
  story: 'Leave some bandages by the dumpster.' });
voice.addMission(model, 'barricade', { target: mill.id, count: '4', after: deliver.id, story: 'Board up the mill.' });
voice.setPool(model, [{ kind: 'cache', param: 'medical', weight: '2' }, { kind: 'lesson', param: 'Doctor', weight: '1' },
  { kind: 'stashmap', param: '', weight: '1' }]);
const text = sheet.serialize(model);
console.log(JSON.stringify({ text, checks: check(model, catalog, 'bench_voice'),
  again: sheet.serialize(sheet.parse(text)) === text, places: voice.places(model).map((p) => p.id),
  missions: voice.missions(model).map((m) => m.id) }));
"""

BROKEN_SHEET = """format=1
id=broken
frequency_range=115.0-120.0
radio=sometimes
listen=07:00-07:00
colour=red

[place mill]
at=1,2
label=Mill
use=target

[mission m1]
type=teleport

[mission m2]
type=barricade
count=-1
after=ghost

[mission m3]
type=deliver
items=snacks
quantity=4-2

[mission m4]
type=route
points=mill

[rewards]
pool=cache:nothing:1, lesson:Juggling:1, frequency:0, gold:1

[prompt]
"""

BROKEN_EXPECTED = {
    ('check.missing_key', 'name'), ('check.band_overlap', 'Darlene Pruitt'), ('check.bad_choice', 'radio'),
    ('check.bad_hours', None), ('check.unknown_key', 'colour'), ('check.bad_at', None),
    ('check.unknown_type', None), ('check.needs_target', None), ('check.bad_count', 'count'),
    ('check.unknown_mission', None), ('check.needs_drop', None), ('check.unknown_category', 'items'),
    ('check.bad_range', 'quantity'), ('check.too_few_places', 'points'), ('check.unknown_category', 'cache'),
    ('check.unknown_skill', 'lesson'), ('check.bad_weight', 'frequency'), ('check.unknown_reward', None),
    ('check.no_prompt', None),
}


@unittest.skipUnless(NODE, 'node is not installed')
class AtelierPureModulesTests(unittest.TestCase):
    def test_shipped_sheets_round_trip_unchanged(self):
        sheets = shipped_sheets()
        self.assertEqual(len(sheets), 16)
        script = node_prelude() + f"""
const out = {{}};
for (const path of {json.dumps([str(p) for p in sheets])}) {{
  const text = sheet.normalizeText(fs.readFileSync(path, 'utf8'));
  const model = sheet.parse(text);
  out[path] = {{ same: sheet.serialize(model) === text, sections: model.sections.length,
    prompt: sheet.promptText(model).length, checks: check(model, catalog, path.replace(/^.*[\\\\/]|\\.txt$/g, '')) }};
}}
console.log(JSON.stringify(out));
"""
        result = run_node(script)
        for path in sheets:
            with self.subTest(path.name):
                entry = result[str(path)]
                self.assertTrue(entry['same'], f'{path.name}: serialize(parse(text)) differs from the text')
                self.assertGreater(entry['prompt'], 0)
                self.assertEqual(entry['checks'], [], f'{path.name}: light checks on a shipped sheet')

    def test_voice_built_from_scratch_is_accepted_by_the_game_reader(self):
        built = run_node(BUILD_SCRIPT)
        self.assertEqual(built['checks'], [])
        self.assertTrue(built['again'])
        self.assertEqual(built['places'], ['old_mill', 'dumpster_behind_the_mill'])
        self.assertEqual(built['missions'], ['deliver', 'barricade'])
        text = built['text']
        self.assertIn('[mission barricade]\ntype=barricade\ntarget=old_mill\ncount=4\nafter=deliver', text)
        self.assertTrue(text.startswith('# A voice built by the bench, step by step\nformat=1\nid=bench_voice\n'))
        status, detail = game_reads(text, 'bench_voice')
        self.assertEqual(status, 'OK', f'game reader refused the built sheet: {detail}\n{text}')
        sheet = bridge_reads(text, 'bench_voice')
        self.assertEqual((sheet.id, sheet.name), ('bench_voice', 'Bench Voice'))

    def test_checks_give_the_expected_message_keys(self):
        script = node_prelude() + f"""
const model = sheet.parse({json.dumps(BROKEN_SHEET)});
console.log(JSON.stringify(check(model, catalog, 'broken')));
"""
        found = run_node(script)
        keys = {(c['key'], c['args'].get('name')) for c in found}
        expected_names = {(k, n) for k, n in BROKEN_EXPECTED if n is not None}
        expected_keys = {k for k, _ in BROKEN_EXPECTED}
        self.assertEqual({k for k, _ in keys}, expected_keys)
        self.assertLessEqual(expected_names, keys)
        self.assertTrue(all(c['where']['block'] for c in found))

    def test_values_and_helpers_keep_their_shape(self):
        script = node_prelude() + f"""
import * as values from '{module_url('values.js')}';
console.log(JSON.stringify({{
  bands: values.parseBands('115.0-129.8, 88.0-107.8'), back: values.formatBands([[115000, 129800]]),
  free: values.freeBand([[1000, 50000]]), hours: values.parseHours('07:00-10:00,22:00-02:00'),
  always: values.formatHours([]), pool: values.parsePool('cache:medical:1, frequency:1'),
  poolText: values.formatPool([{{ kind: 'lesson', param: 'Doctor', weight: '2' }}, {{ kind: 'stashmap', param: '', weight: '' }}]),
  range: values.formatRange({{ min: '3', max: '3' }}), slug: voice.slug('Dumpster behind the café!', 'place'),
}}));
"""
        got = run_node(script)
        self.assertEqual(got['bands'], [[115000, 129800], [88000, 107800]])
        self.assertEqual(got['back'], '115.0-129.8')
        self.assertEqual(got['free'], [50200, 60000])
        self.assertEqual(got['hours'], [['07:00', '10:00'], ['22:00', '02:00']])
        self.assertEqual(got['always'], 'always')
        self.assertEqual(got['pool'], [{'kind': 'cache', 'param': 'medical', 'weight': '1'},
                                       {'kind': 'frequency', 'param': '', 'weight': '1'}])
        self.assertEqual(got['poolText'], 'lesson:Doctor:2, stashmap:1')
        self.assertEqual(got['range'], '3')
        self.assertEqual(got['slug'], 'dumpster_behind_the_cafe')

    def test_chances_stock_lines_and_mission_weights(self):
        """Rarely/Normally/Often are 1/2/4, other weights stay custom; stock lines carry no weight (E22-T12)."""
        script = node_prelude() + f"""
import * as values from '{module_url('values.js')}';
const model = sheet.parse('format=1\\nid=w\\nname=W\\n\\n[mission a]\\ntype=clear\\n\\n[mission b]\\ntype=clear\\n');
const [a, b] = voice.missions(model);
const before = [voice.missionWeight(model, a), voice.missionWeight(model, b)];
voice.setMissionWeight(model, a, '4');
console.log(JSON.stringify({{
  levels: ['1', '2', '4', '3', '0.5', ''].map(values.chanceLevel),
  stock: values.parseStockItem('Base.Whiskey:alcohol:1.7'), stockText: values.formatStockItem({{ type: 'Base.Battery', amount: '2-6' }}),
  emptyStock: values.formatStockItem({{ type: ' ', amount: '2' }}), group: values.groupName('alcohol:2-5:3'),
  loot: values.parseLootList('BarCounterLiquor:0.5'), lootText: values.formatLootList({{ list: 'GloveBox', weight: '' }}),
  before, after: [sheet.value(a, 'weight'), sheet.value(b, 'weight')],
}}));
"""
        got = run_node(script)
        self.assertEqual(got['levels'], ['rare', 'normal', 'often', None, None, None])
        self.assertEqual(got['stock'], {'type': 'Base.Whiskey', 'amount': 'alcohol'})
        self.assertEqual(got['stockText'], 'Base.Battery:2-6')
        self.assertEqual(got['emptyStock'], '')
        self.assertEqual(got['group'], 'alcohol')
        self.assertEqual(got['loot'], {'list': 'BarCounterLiquor', 'weight': '0.5'})
        self.assertEqual(got['lootText'], 'GloveBox:2')
        self.assertEqual(got['before'], ['2', '2'], 'no weight anywhere: every mission is "normal"')
        self.assertEqual(got['after'], ['4', '2'], 'the other mission keeps the "normal" chance it showed')

    def test_lots_margin_meeting_hours_and_note_bytes(self):
        """Values of the [trade] and [note] forms written back in the sheet's syntax (no format typed by the user)."""
        script = node_prelude() + f"""
import * as values from '{module_url('values.js')}';
console.log(JSON.stringify({{
  group: values.parseGroup('seeds:3-8:4'), groupText: values.formatGroup({{ name: 'seeds', total: '3-8', kinds: '' }}),
  noName: values.formatGroup({{ name: ' ', total: '2' }}), margin: values.parseMargin('0.10-0.50'),
  marginText: values.formatMargin({{ min: '15', max: '40' }}), halfMargin: values.formatMargin({{ min: '15', max: '' }}),
  hours: values.parseTimeRange('23:00-01:00'), hoursText: values.formatTimeRange(['02:00', '']),
  bytes: [values.utf8Bytes('Mae %1'), values.utf8Bytes('é')],
}}));
"""
        got = run_node(script)
        self.assertEqual(got['group'], {'name': 'seeds', 'total': '3-8', 'kinds': '4'})
        self.assertEqual(got['groupText'], 'seeds:3-8')
        self.assertEqual(got['noName'], '')
        self.assertEqual(got['margin'], {'min': '10', 'max': '50'})
        self.assertEqual(got['marginText'], '0.15-0.40')
        self.assertEqual(got['halfMargin'], '', 'an incomplete margin writes no line: the game default applies')
        self.assertEqual(got['hours'], ['23:00', '01:00'])
        self.assertEqual(got['hoursText'], '')
        self.assertEqual(got['bytes'], [6, 2], 'the game counts the bytes of UTF-8')

    def test_item_search_by_name_in_the_page_language(self):
        """catalog.items (every item of the game): a name typed in French or English finds the Module.Type."""
        script = node_prelude() + """
const index = catalog.itemIndex();
const first = (q, lang) => index.search(q, lang).map((r) => r.type);
console.log(JSON.stringify({
  size: index.size, pansement: first('pansement', 'fr'), bandageFr: first('bandage', 'fr'),
  bandageEn: first('Bandage', 'en'), accents: first('medaillon', 'fr').slice(0, 3), type: first('Base.Bandage', 'en')[0],
  bandage: index.get('Base.Bandage', 'fr'), unknown: index.get('Nope.Nothing', 'fr'), empty: index.search('  ', 'fr'),
  many: index.search('a', 'en').length,
}));
"""
        got = run_node(script)
        self.assertGreater(got['size'], 1000)
        self.assertEqual(got['pansement'][0], 'Base.Bandaid', 'French name "Pansement" first')
        self.assertIn('Base.AdhesiveBandageBox', got['pansement'])
        self.assertEqual(got['bandageFr'][0], 'Base.Bandage')
        self.assertEqual(got['bandageEn'][0], 'Base.Bandage')
        self.assertIn('Base.Locket', got['accents'], 'accents ignored: "medaillon" finds "Médaillon"')
        self.assertEqual(got['type'], 'Base.Bandage')
        self.assertEqual(got['bandage'], {'type': 'Base.Bandage', 'name': 'Bandage', 'kg': 0.1, 'cat': 'FirstAid',
                                          'catName': 'Premiers secours'})
        self.assertIsNone(got['unknown'])
        self.assertEqual(got['empty'], [])
        self.assertEqual(got['many'], 12)


    def test_item_browser_filters_by_category_in_the_page_language(self):
        """Item browser (user 2026-11-15): the game's categories named in the page's language, a category listed whole
        by name, a search within a category, the count of matches beyond the shown ones."""
        script = node_prelude() + """
const index = catalog.itemIndex();
const cats = index.categories('fr');
const food = index.find('', 'fr', { category: 'Food', limit: 5 });
const whisky = index.find('whisky', 'fr', { category: 'Food' });
const all = index.find('', 'en', { limit: 200 });
console.log(JSON.stringify({
  food: cats.find((c) => c.value === 'Food'), labels: cats.map((c) => c.label),
  sortedLabels: [...cats.map((c) => c.label)].sort((a, b) => a.localeCompare(b, 'fr')),
  foodTotal: food.total, foodShown: food.items.length, foodCats: [...new Set(food.items.map((i) => i.cat))],
  foodNames: food.items.map((i) => i.name),
  whisky: whisky.items[0], whiskyOutside: index.find('whisky', 'fr', { category: 'Tool' }).total,
  allShown: all.items.length, allTotal: all.total,
}));
"""
        got = run_node(script)
        self.assertEqual(got['food'], {'value': 'Food', 'label': 'Nourriture'})
        self.assertEqual(got['labels'], got['sortedLabels'], 'categories sorted by their name in the page language')
        self.assertGreater(got['foodTotal'], 100)
        self.assertEqual((got['foodShown'], got['foodCats']), (5, ['Food']))
        folded = lambda n: ''.join(c for c in unicodedata.normalize('NFD', n) if not unicodedata.combining(c)).lower()
        self.assertEqual(got['foodNames'], sorted(got['foodNames'], key=folded), 'by name, accents and case ignored')
        self.assertEqual(got['whisky'], {'type': 'Base.Whiskey', 'name': 'Bouteille de whisky', 'kg': 1.7,
                                         'cat': 'Food', 'catName': 'Nourriture'})
        self.assertEqual(got['whiskyOutside'], 0)
        self.assertEqual(got['allShown'], 200)
        self.assertGreater(got['allTotal'], 1000)

    def test_trader_stock_offers_only_sellable_items(self):
        """E22-T17: the trade only sells items with a sale value (catalog.sellable): the trader's stock searches them
        only, every other item list keeps all the items of the game."""
        script = node_prelude() + """
const all = catalog.itemIndex();
const sell = catalog.sellableItemIndex();
console.log(JSON.stringify({
  sizes: [all.size, sell.size], allAxe: all.get('Base.Axe', 'en')?.type ?? null, sellAxe: sell.get('Base.Axe', 'en'),
  battery: sell.get('Base.Battery', 'fr')?.name ?? null, axeSearch: sell.search('Axe', 'en').map((r) => r.type),
  whisky: sell.search('whisky', 'fr')[0]?.type ?? null, food: sell.find('', 'fr', { category: 'Food' }).total,
  isAxe: catalog.isSellable('Base.Axe'), isBattery: catalog.isSellable('Base.Battery'),
}));
"""
        got = run_node(script)
        self.assertEqual(got['allAxe'], 'Base.Axe')
        self.assertIsNone(got['sellAxe'])
        self.assertNotIn('Base.Axe', got['axeSearch'])
        self.assertEqual((got['battery'], got['whisky']), ('Pile', 'Base.Whiskey'))
        self.assertGreater(got['food'], 5)
        self.assertLess(got['sizes'][1], got['sizes'][0] // 10)
        self.assertEqual((got['isAxe'], got['isBattery']), (False, True))

    def test_check_flags_a_stock_item_the_trader_cannot_sell(self):
        sheet_text = ('format=1\nid=seller\nname=Seller\nfrequencies=145.0\n\n[trade]\nitem=Base.Axe:1\n'
                      'item=Base.Battery:2-4\nitem=Mine.Gadget:1\n\n[category kit]\nitem=Base.Axe:1\n\n'
                      '[prompt]\nA trader.\n')
        script = node_prelude() + f"""
const model = sheet.parse({json.dumps(sheet_text)});
console.log(JSON.stringify(check(model, catalog, 'seller').filter((c) => c.key === 'check.not_sellable')));
"""
        found = run_node(script)
        self.assertEqual([(c['args']['value'], c['where']) for c in found], [
            ('Base.Axe', {'block': 'trade', 'id': None, 'field': 'item'}),
            ('Mine.Gadget', {'block': 'trade', 'id': None, 'field': 'item'}),
        ], 'only the [trade] stock: an own category keeps every item')


    def test_voice_status_of_the_server_entries(self):
        """A copy the game wrote from an older version of the mod (server `outdated`) has its own state, not "from the
        mod": the game replaces it at the next world load (E22-T17)."""
        entries = {
            'custom': {'custom': True}, 'delivered': {'delivered': True},
            'modified': {'delivered': True, 'modified': True}, 'removed': {'delivered': True, 'removed': True},
            'outdated': {'delivered': True, 'outdated': True},
        }
        script = (f"import {{ voiceStatus, STATUSES }} from '{module_url('voicelist.js')}';\n"
                  f"const entries = {json.dumps(entries)};\n"
                  "console.log(JSON.stringify({ got: Object.fromEntries(Object.entries(entries)"
                  ".map(([k, e]) => [k, voiceStatus(e)])), statuses: STATUSES }));\n")
        got = run_node(script)
        self.assertEqual(got['got'], {k: k for k in entries})
        self.assertIn('outdated', got['statuses'])


class AtelierStringsTests(unittest.TestCase):
    @staticmethod
    def strings(lang: str) -> dict:
        return json.loads((ATELIER / 'i18n' / f'{lang}.json').read_text(encoding='utf-8'))

    @staticmethod
    def used_keys() -> set[str]:
        keys = set()
        scripts = sorted(ATELIER.rglob('*.js'))
        for path in scripts:
            text = path.read_text(encoding='utf-8')
            keys |= {k for k in KEY_LITERAL.findall(text) if not NOT_KEYS.search(k)}
            if path.parent.name == 'steps':
                keys |= {f'step.{m}' for m in re.findall(r"^\s*id: '([a-z_]+)'", text, re.M)}
        app = (ATELIER / 'app.js').read_text(encoding='utf-8')
        keys |= {f'editor.{m}' for m in re.findall(r"label: '([a-z_]+)'", app)}
        statuses = re.search(r'STATUSES = \[([^\]]+)\]', (ATELIER / 'voicelist.js').read_text(encoding='utf-8'))
        for status in re.findall(r"'([a-z_]+)'", statuses.group(1)):
            keys |= {f'status.{status}', f'status.{status}.help'}
        return keys

    def test_french_and_english_hold_the_same_keys(self):
        fr, en = self.strings('fr'), self.strings('en')
        self.assertEqual(sorted(set(fr) - set(en)), [])
        self.assertEqual(sorted(set(en) - set(fr)), [])
        self.assertTrue(all(isinstance(v, str) and v.strip() for v in [*fr.values(), *en.values()]))

    def test_every_key_used_by_the_scripts_exists_in_both_languages(self):
        keys = self.used_keys()
        self.assertGreater(len(keys), 100)
        for lang in ('fr', 'en'):
            with self.subTest(lang):
                strings = self.strings(lang)
                # A literal may be the prefix of a family ('choice.state' + '.' + value): some key must extend it.
                missing = [k for k in keys if k not in strings and not any(s.startswith(k + '.') for s in strings)]
                self.assertEqual(sorted(missing), [])

    def test_server_codes_are_translated(self):
        server = (ROOT / 'bridge' / 'atelier_server.py').read_text(encoding='utf-8')
        codes = set(re.findall(r"(?:AtelierError\(\d+, |Done\()'([a-z_]+)'", server))
        self.assertGreater(len(codes), 10)
        for lang in ('fr', 'en'):
            with self.subTest(lang):
                self.assertEqual(sorted(f'code.{c}' for c in codes if f'code.{c}' not in self.strings(lang)), [])


if __name__ == '__main__':
    unittest.main()
