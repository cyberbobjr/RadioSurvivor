"""E22-T03: page of the voice workshop (bridge/atelier, ADR atelier-voix D03, D05).

    python RadioSurvivor/tests/test_atelier_ui.py

The pure ES modules of the page run in node (skipped when node is missing):
- sheet.js reads and writes back every shipped sheet unchanged (comments, blank lines, unknown keys, order);
- a voice built from scratch with the assistant's model operations (voice.js: head, marks, a deliver mission with
  dead drops, a barricade mission after it, objectives in a zone and far from the player with a building kind, a reward
  pool with its cache place) over shared places made by places.js (E25-T03) is accepted by the REAL game reader
  (RS_Persona.lua in lupa, loader of tools/gen_atelier_catalog.py with every mission template) and by the bridge reader;
- checks.js finds the expected message keys on a broken sheet and nothing on the shipped sheets (read with the shipped
  shared places);
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
            f"import * as places from '{module_url('places.js')}';\n"
            f"import {{ createCatalog }} from '{module_url('catalog.js')}';\n"
            f"const catalog = createCatalog(JSON.parse(fs.readFileSync({json.dumps(str(ATELIER / 'catalog.json'))}, 'utf8')));\n")


def shipped_sheets() -> list[Path]:
    return sorted(p for p in SHIPPED.glob('*.txt') if not p.name.startswith('_'))


def game_reads(text: str, voice_id: str, places: str | None = None):
    """Sheet `text` saved as <voice_id>.txt next to the shared places `places` (_places.txt; None: the shipped one)
    and read by the real RS_Persona.readFile with the server rules and every mission template of the mod: Lua table, or
    (None, reason)."""
    import gen_atelier_catalog as gen
    from test_personas import LuaReader
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        (folder / f'{voice_id}.txt').write_bytes(text.encode('utf-8'))
        (folder / '_places.txt').write_bytes(places.encode('utf-8') if places is not None
                                             else (SHIPPED / '_places.txt').read_bytes())
        lua = gen.load_mod()
        lua.rt.globals().getFileReader = lambda name, create: (
            LuaReader(folder / name) if (folder / name).is_file() else None)
        lua.folder = folder     # the shared places of this folder (LuaPersona.places)
        result = lua.read(f'{voice_id}.txt')
        return result if isinstance(result, tuple) else ('OK', lua.canonical(result))


def bridge_reads(text: str, voice_id: str, places: str):
    import persona_store
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / f'{voice_id}.txt'
        path.write_bytes(text.encode('utf-8'))
        (Path(tmp) / '_places.txt').write_bytes(places.encode('utf-8'))
        return persona_store.load_file(path)


BUILD_SCRIPT = node_prelude() + r"""
const model = voice.newVoice({ id: 'bench_voice', name: 'Bench Voice', radio: catalog.radioLevels()[0].id,
  format: catalog.sheet.format });
sheet.setDescription(model, 'A voice built by the bench, step by step');
sheet.setValue(model.head, 'listen', '07:00-10:00,22:00-02:00');
sheet.setValue(model.head, 'actions', 'say,start_mission,mark_map');
const shared = places.newPlacesFile(catalog.sheet.format);
const mill = places.addPlace(shared, { label: 'Old mill', kind: 'point', at: { x: '10600', y: '9300', z: '0' } });
const drop = places.addPlace(shared, { label: 'Dumpster behind the mill', kind: 'point', at: { x: '10610', y: '9305', z: '0' } });
const town = places.addPlace(shared, { label: 'Mill town', kind: 'zone', z: '0',
  area: { x1: '10800', y1: '9500', x2: '10500', y2: '9200' } });
voice.setMarks(model, [mill.id, town.id]);
const deliver = voice.addMission(model, 'deliver', { items: 'medical', quantity: '2-4', drops: drop.id,
  story: 'Leave some bandages by the dumpster.' });
voice.addMission(model, 'barricade', { target: mill.id, count: '4', after: deliver.id, story: 'Board up the mill.' });
voice.addMission(model, 'scout', { target: town.id, building: 'house', story: 'Look around the mill town.' });
voice.addMission(model, 'clear', { target: 'far', building: 'church', story: 'Clear a church far away.' });
voice.setPool(model, [{ kind: 'cache', param: 'medical', weight: '2' }, { kind: 'lesson', param: 'Doctor', weight: '1' },
  { kind: 'stashmap', param: '', weight: '1' }]);
voice.setCachePlace(model, drop.id);
const text = sheet.serialize(model);
console.log(JSON.stringify({ text, places: places.serialize(shared),
  checks: check(model, catalog, 'bench_voice', places.list(shared)),
  again: sheet.serialize(sheet.parse(text)) === text, marks: voice.marks(model),
  missions: voice.missions(model).map((m) => m.id) }));
"""

BROKEN_SHEET = """format=1
id=broken
frequency=145.1
radio=sometimes
listen=07:00-07:00
colour=red
marks=ghost

[mission m1]
type=teleport

[mission m2]
type=barricade
count=-1
after=ghost
target=mill
building=house

[mission m3]
type=deliver
items=snacks
quantity=4-2

[mission m4]
type=route
points=mill

[mission m5]
type=retrieve
drops=town
target=nowhere

[rewards]
pool=cache:nothing:1, lesson:Juggling:1, frequency:0, gold:1

[prompt]
"""

# Shared places of the broken sheet: a point and a zone.
BROKEN_PLACES = 'format=1\n[place mill]\nat=1,2,0\nlabel=Mill\n[place town]\narea=1,1,9,9,0\nlabel=Town\n'

BROKEN_EXPECTED = {
    ('check.missing_key', 'name'), ('check.radio_and_frequency', None), ('check.bad_frequency', None),
    ('check.bad_choice', 'radio'),
    ('check.bad_hours', None), ('check.unknown_key', 'colour'), ('check.unknown_place', 'marks'),
    ('check.unknown_type', None), ('check.bad_count', 'count'), ('check.building_needs_zone', None),
    ('check.unknown_mission', None), ('check.needs_drop', None), ('check.unknown_category', 'items'),
    ('check.bad_range', 'quantity'), ('check.too_few_places', 'points'), ('check.place_is_zone', 'drops'),
    ('check.unknown_place', 'target'), ('check.unknown_category', 'cache'), ('check.needs_cache_place', None),
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
const shared = places.list(places.parsePlaces(fs.readFileSync({json.dumps(str(SHIPPED / '_places.txt'))}, 'utf8')));
for (const path of {json.dumps([str(p) for p in sheets])}) {{
  const text = sheet.normalizeText(fs.readFileSync(path, 'utf8'));
  const model = sheet.parse(text);
  out[path] = {{ same: sheet.serialize(model) === text, sections: model.sections.length,
    prompt: sheet.promptText(model).length, checks: check(model, catalog, path.replace(/^.*[\\\\/]|\\.txt$/g, ''), shared) }};
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
        self.assertEqual(built['marks'], ['old_mill', 'mill_town'])
        self.assertEqual(built['missions'], ['deliver', 'barricade', 'scout', 'clear'])
        text = built['text']
        self.assertIn('[mission barricade]\ntype=barricade\ntarget=old_mill\ncount=4\nafter=deliver', text)
        self.assertIn('[mission clear]\ntype=clear\ntarget=far\nbuilding=church', text)
        self.assertIn('\nmarks=old_mill,mill_town\n', text)
        self.assertIn('[rewards]\npool=cache:medical:2, lesson:Doctor:1, stashmap:1\ncache_place=dumpster_behind_the_mill',
                      text)
        self.assertTrue(text.startswith('# A voice built by the bench, step by step\nformat=1\nid=bench_voice\n'))
        self.assertIn('\nradio=any_talkie\n', text)   # E24-T01: default radio, everybody hears it
        status, detail = game_reads(text, 'bench_voice', built['places'])
        self.assertEqual(status, 'OK', f'game reader refused the built sheet: {detail}\n{text}\n{built["places"]}')
        sheet = bridge_reads(text, 'bench_voice', built['places'])
        self.assertEqual((sheet.id, sheet.name), ('bench_voice', 'Bench Voice'))
        self.assertEqual([p.id for p in sheet.marks], ['old_mill', 'mill_town'])

    def test_checks_give_the_expected_message_keys(self):
        script = node_prelude() + f"""
const model = sheet.parse({json.dumps(BROKEN_SHEET)});
const shared = places.list(places.parsePlaces({json.dumps(BROKEN_PLACES)}));
console.log(JSON.stringify(check(model, catalog, 'broken', shared)));
"""
        found = run_node(script)
        keys = {(c['key'], c['args'].get('name')) for c in found}
        expected_names = {(k, n) for k, n in BROKEN_EXPECTED if n is not None}
        expected_keys = {k for k, _ in BROKEN_EXPECTED}
        self.assertEqual({k for k, _ in keys}, expected_keys)
        self.assertLessEqual(expected_names, keys)
        self.assertTrue(all(c['where']['block'] for c in found))

    def test_radio_levels_and_the_radio_a_fixed_frequency_needs(self):
        """E24-T01: the five radio levels of the mod, weakest first; the radio a fixed frequency needs is the weakest
        level that tunes it, as RS_RadioLevels.levelOf."""
        script = node_prelude() + """
console.log(JSON.stringify({ ids: catalog.radioLevels().map((l) => l.id), bounds: catalog.frequencyBounds(),
  levels: [145000, 75000, 150200, 49800, 300200, 7200, 1000000, 1000200, 0].map(catalog.levelOf) }));
"""
        got = run_node(script)
        self.assertEqual(got['ids'], ['any_talkie', 'good_talkie', 'pro_talkie', 'tactical', 'military'])
        self.assertEqual(got['bounds'], {'min': 200, 'max': 1000000, 'step': 200})
        self.assertEqual(got['levels'], ['any_talkie', 'any_talkie', 'good_talkie', 'pro_talkie', 'tactical',
                                         'military', 'military', None, None])

    def test_radio_or_one_fixed_frequency_checked(self):
        """E24-T01: exactly one of radio= and frequency=; a fixed frequency on the grid of every radio, never the
        fixed frequency of another voice."""
        script = node_prelude() + """
const other = createCatalog({ ...catalog.data, voices: { ...catalog.data.voices,
  zed: { name: 'Zed Taken', frequencyKhz: 152000, radio: 'good_talkie', arrival: null } } });
const head = (lines) => 'format=1\\nid=case\\nname=Case\\n' + lines + '\\n[prompt]\\nHi.\\n';
const keys = (text, cat = catalog) => check(sheet.parse(text), cat, 'case')
  .filter((c) => c.where.block === 'head').map((c) => [c.key, c.args.name ?? c.args.value ?? null]);
console.log(JSON.stringify({
  radio: keys(head('radio=pro_talkie')), fixed: keys(head('frequency=1000.0')), none: keys(head('language=en')),
  both: keys(head('radio=military\\nfrequency=7.2')), grid: keys(head('frequency=145.1')),
  high: keys(head('frequency=1000.2')), low: keys(head('frequency=0.0')), text: keys(head('frequency=abc')),
  taken: keys(head('frequency=152.0'), other), self: check(sheet.parse(head('frequency=152.0')), other, 'zed')
    .filter((c) => c.where.block === 'head').map((c) => c.key),
}));
"""
        got = run_node(script)
        self.assertEqual((got['radio'], got['fixed']), ([], []))
        self.assertEqual(got['none'], [['check.no_frequency', None]])
        self.assertEqual(got['both'], [['check.radio_and_frequency', None]])
        for case, value in (('grid', '145.1'), ('high', '1000.2'), ('low', '0.0'), ('text', 'abc')):
            with self.subTest(case):
                self.assertEqual(got[case], [['check.bad_frequency', value]])
        self.assertEqual(got['taken'], [['check.frequency_taken', 'Zed Taken']])
        self.assertEqual(got['self'], [], 'the voice being edited never collides with itself')

    def test_values_and_helpers_keep_their_shape(self):
        script = node_prelude() + f"""
import * as values from '{module_url('values.js')}';
console.log(JSON.stringify({{
  mhz: ['0.2', '145.0', '1000.0', '145', '145.0.1', '10000.0'].map(values.mhzToKhz), label: values.khzToMhz(1000000),
  hours: values.parseHours('07:00-10:00,22:00-02:00'),
  always: values.formatHours([]), pool: values.parsePool('cache:medical:1, frequency:1'),
  poolText: values.formatPool([{{ kind: 'lesson', param: 'Doctor', weight: '2' }}, {{ kind: 'stashmap', param: '', weight: '' }}]),
  range: values.formatRange({{ min: '3', max: '3' }}), slug: voice.slug('Dumpster behind the café!', 'place'),
}}));
"""
        got = run_node(script)
        self.assertEqual(got['mhz'], [200, 145000, 1000000, 145000, None, None])
        self.assertEqual(got['label'], '1000.0')
        self.assertEqual(got['hours'], [['07:00', '10:00'], ['22:00', '02:00']])
        self.assertEqual(got['always'], 'always')
        self.assertEqual(got['pool'], [{'kind': 'cache', 'param': 'medical', 'weight': '1'},
                                       {'kind': 'frequency', 'param': '', 'weight': '1'}])
        self.assertEqual(got['poolText'], 'lesson:Doctor:2, stashmap:1')
        self.assertEqual(got['range'], '3')
        self.assertEqual(got['slug'], 'dumpster_behind_the_cafe')

    def test_a_map_position_pasted_gives_the_square(self):
        """User 2026-11-16: the position copied on zomboidmap.com ("7966, 11751") fills x and y, a third number the
        floor; one number alone (a plain paste into one field) or a decimal is not a position."""
        script = node_prelude() + f"""
import {{ parseSquare }} from '{module_url('values.js')}';
console.log(JSON.stringify(['7966, 11751', '7966, 11751, 1', '7966;11751', ' 7966  11751 ', 'x: 7966 y: 11751',
  '7966', '', null, '7966.5, 11751', '1, 2, 3, 4', 'abc'].map(parseSquare)));
"""
        got = run_node(script)
        self.assertEqual(got[:5], [{'x': '7966', 'y': '11751'}, {'x': '7966', 'y': '11751', 'z': '1'},
                                   {'x': '7966', 'y': '11751'}, {'x': '7966', 'y': '11751'},
                                   {'x': '7966', 'y': '11751'}])
        self.assertEqual(got[5:], [None] * 6)

    def test_details_sent_with_a_suggestion_fit_the_server(self):
        """E24-T04: the details of a "Suggest" are flat strings the server takes (16 keys at most, keys [a-z_], values
        cut at 600 characters, empty ones left out); a shared place (E25-T03) says in words whether it is a spot or an
        area, its square or its corners only when known, and the voices that use it."""
        script = node_prelude() + f"""
import {{ forAi, placeDetails, suggestDetails }} from '{module_url('ai.js')}';
const many = Object.fromEntries(Array.from({{ length: 20 }}, (_, i) => ['k_' + String.fromCharCode(97 + i), 'v']));
const t = (key) => ({{ 'places.kind.point': 'A spot', 'places.kind.zone': 'An area' }})[key] ?? key;
console.log(JSON.stringify({{
  cleaned: suggestDetails({{ mission_number: 2, empty: '', none: null, 'Bad-Key': 'x', long: 'a'.repeat(700) }}),
  count: Object.keys(suggestDetails(many)).length,
  place: suggestDetails(placeDetails(t, {{ kind: 'point', at: {{ x: '7966', y: '11751', z: '' }} }}, ['Cody', 'Darlene'])),
  zone: suggestDetails(placeDetails(t, {{ kind: 'zone', area: {{ x1: '1', y1: '2', x2: '30', y2: '40' }}, z: '1' }}, [])),
  noSquare: suggestDetails(placeDetails(t, {{ kind: 'point', at: {{ x: '', y: '', z: '0' }} }}, [])),
  line: forAi('Tune in %1 tonight'),
}}));
"""
        got = run_node(script)
        self.assertEqual(got['cleaned'], {'mission_number': '2', 'long': 'a' * 600})
        self.assertEqual(got['count'], 16)
        self.assertEqual(got['place'], {'where': 'A spot', 'map_square': '7966,11751,0', 'used_by': 'Cody, Darlene'})
        self.assertEqual(got['zone'], {'where': 'An area', 'map_area': '1,2 - 30,40, floor 1'})
        self.assertEqual(got['noSquare'], {'where': 'A spot'})
        self.assertEqual(got['line'], 'Tune in {frequency} tonight')

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
        sheet_text = ('format=1\nid=seller\nname=Seller\nfrequency=145.0\n\n[trade]\nitem=Base.Axe:1\n'
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

    ACCEPT_SHEET = ('format=1\nid=buyer\nname=Buyer\nfrequency=145.0\n\n[trade]\nitem=Base.Battery:1\n'
                    'accept=cash\naccept=Base.Axe\naccept=kit\naccept=ghost\naccept=Base.Battery\naccept=goods\n\n'
                    '[category kit]\nitem=Base.Axe:1\n\n[category goods]\nitem=Base.Axe:1\nitem=Base.Battery:2\n\n'
                    '[prompt]\nA trader.\n')

    def test_accepted_categories_count_their_sellable_items(self):
        """E23-T06: a category is accepted as payment only for its items with a trade value: the shared ones and the
        sheet's own [category] sections, each with its sellable items (the accept editor offers those with one)."""
        script = node_prelude() + f"""
import {{ categoryIds, acceptChoices }} from '{module_url('categories.js')}';
const model = sheet.parse({json.dumps(self.ACCEPT_SHEET)});
const choices = acceptChoices(model, catalog);
console.log(JSON.stringify({{ ids: categoryIds(model, catalog), choices: Object.fromEntries(choices.map((c) => [c.id,
  {{ own: c.own, sellable: c.sellable }}])), shared: catalog.categoryItems('cash'), none: catalog.categoryItems('kit') }}));
"""
        got = run_node(script)
        self.assertEqual(got['ids'][-2:], ['kit', 'goods'], 'the shared categories, then the own ones')
        self.assertIn('cash', got['ids'])
        self.assertEqual(got['choices']['kit'], {'own': True, 'sellable': []})
        self.assertEqual(got['choices']['goods'], {'own': True, 'sellable': ['Base.Battery']})
        self.assertFalse(got['choices']['cash']['own'])
        self.assertIn('Base.MoneyBundle', got['choices']['cash']['sellable'])
        self.assertLessEqual(set(got['choices']['cash']['sellable']), set(got['shared']))
        self.assertIsNone(got['none'], 'an own category is not a shared one')

    def test_check_flags_what_the_voice_cannot_accept(self):
        """E23-T06: an accepted item without a trade value, a category without one, an unknown category; a trade without
        accept= is said in plain words (not the raw key)."""
        no_accept = self.ACCEPT_SHEET.replace('accept=', '#accept=')
        script = node_prelude() + f"""
const keys = (text) => check(sheet.parse(text), catalog, 'buyer').filter((c) => c.where.field === 'accept')
  .map((c) => [c.key, c.args.value ?? c.args.name ?? null, c.where.field]);
console.log(JSON.stringify({{ bad: keys({json.dumps(self.ACCEPT_SHEET)}), none: keys({json.dumps(no_accept)}) }}));
"""
        got = run_node(script)
        self.assertEqual(got['bad'], [['check.accept_not_sellable', 'Base.Axe', 'accept'],
                                      ['check.accept_no_value', 'kit', 'accept'],
                                      ['check.accept_unknown_category', 'ghost', 'accept']])
        self.assertIn(['check.no_accept', 'accept', 'accept'], got['none'])
        self.assertNotIn('check.missing_key', [k for k, _, _ in got['none']])


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

    def test_master_list_selects_the_next_entry_after_a_removal(self):
        """User 2026-11-17: the master/detail tabs (Voices, Places) select the entry after the one removed, the one
        before it when it was the last, nothing when the list is empty."""
        script = (f"import {{ selectionAfter }} from '{module_url('masterdetail.js')}';\n"
                  "console.log(JSON.stringify([selectionAfter(['a', 'b', 'c'], 'b'), selectionAfter(['a', 'b', 'c'], 'c'),"
                  " selectionAfter(['a'], 'a'), selectionAfter([], 'x'), selectionAfter(['a', 'b'], 'x')]));\n")
        self.assertEqual(run_node(script), ['c', 'b', None, None, None])

    def test_map_link_opens_the_build_42_map_on_the_square(self):
        """The link next to x/y/z opens zomboidmap.com (Build 42) centred on the square: the site reads
        #zoom/x/y/f<floor> from its address. Without a usable x and y it opens the whole map."""
        cases = [['10600', '9300', '0'], [' 8159.4 ', '11661', ''], ['10600', '9300', '1.5'], ['', '9300', '0'],
                 ['abc', '9300', '0'], ['-3', '9300', '0'], [None, None, None]]
        script = (f"import {{ mapUrl, MAP_SITE }} from '{module_url('maplink.js')}';\n"
                  f"const cases = {json.dumps(cases)};\n"
                  "console.log(JSON.stringify({ site: MAP_SITE, urls: cases.map(([x, y, z]) => mapUrl(x, y, z)) }));\n")
        got = run_node(script)
        self.assertEqual(got['site'], 'https://zomboidmap.com/')
        self.assertEqual(got['urls'], ['https://zomboidmap.com/#11/10600/9300/f0', 'https://zomboidmap.com/#11/8159/11661',
                                       'https://zomboidmap.com/#11/10600/9300', None, None, None, None])


DASHBOARD_PRELUDE = node_prelude() + f"""
import * as dash from '{module_url('dashboard.js')}';
import {{ createI18n }} from '{module_url('i18n.js')}';
const strings = (lang) => createI18n(lang, JSON.parse(fs.readFileSync({json.dumps(str(ATELIER / 'i18n'))} + '/' + lang + '.json', 'utf8')));
const voiceOf = (head, sections = '') => dash.summarize({{ id: 'case', name: 'Entry Name' }},
  sheet.parse('format=1\\nid=case\\n' + head + '\\n' + sections + '\\n[prompt]\\nHi.\\n'), catalog);
"""


class AtelierDashboardTests(unittest.TestCase):
    """E24-T05: the pure functions of the dashboard (dashboard.js) over the page's own readers."""

    def test_listening_hours_as_ranges_and_words(self):
        script = DASHBOARD_PRELUDE + """
const fr = strings('fr'), en = strings('en');
const cases = ['07:00-10:00,16:00-19:00', '23:00-03:00', '19:30-22:00', 'always', null, '22:00-02:00,05:00-07:00'];
console.log(JSON.stringify({ ranges: cases.map(dash.listenRanges), fr: cases.map((c) => dash.hoursText(fr, c)),
  en: cases.slice(0, 3).map((c) => dash.hoursText(en, c)), count: cases.map(dash.listenHours) }));
"""
        got = run_node(script)
        self.assertEqual(got['ranges'], [[[7, 10], [16, 19]], [[23, 24], [0, 3]], [[19.5, 22]], [[0, 24]], [[0, 24]],
                                         [[22, 24], [0, 2], [5, 7]]])
        self.assertEqual(got['fr'], ['7 h–10 h · 16 h–19 h', '23 h–3 h', '19 h 30–22 h', 'jour et nuit', 'jour et nuit',
                                     '22 h–2 h · 5 h–7 h'])
        self.assertEqual(got['en'], ['7:00–10:00 · 16:00–19:00', '23:00–3:00', '19:30–22:00'])
        self.assertEqual(got['count'], [6, 4, 2.5, 24, 24, 6])

    def test_hours_with_no_voice_but_the_always_ones(self):
        """Hours of the day when only "day and night" voices listen; silent voices do not fill a gap."""
        script = DASHBOARD_PRELUDE + """
const rows = [voiceOf('radio=any_talkie\\nlisten=always'), voiceOf('radio=any_talkie\\nlisten=22:00-02:00'),
  voiceOf('radio=any_talkie\\nlisten=06:00-12:00'), voiceOf('radio=any_talkie\\nlisten=12:00-20:00\\nstate=silent')];
console.log(JSON.stringify({ gap: dash.gapHours(rows), none: dash.gapHours([]), all: dash.gapHours(rows.slice(0, 1)) }));
"""
        got = run_node(script)
        self.assertEqual(got['gap'], 24 - 4 - 6)
        self.assertEqual((got['none'], got['all']), (24, 24))

    def test_what_a_voice_offers(self):
        script = DASHBOARD_PRELUDE + """
const offers = (v) => dash.interactions(v).map((k) => k.id);
const talker = voiceOf('radio=any_talkie\\nactions=say');
const giver = voiceOf('radio=any_talkie\\nactions=say,start_mission,share_frequency\\ncall_one_in=6',
  '[mission a]\\ntype=scout\\n[mission b]\\ntype=clear');
const trader = voiceOf('radio=pro_talkie\\nactions=say,propose_trade', '[trade]\\narrival=boat');
const section = voiceOf('radio=pro_talkie\\nactions=say', '[trade]\\narrival=road');
const rescue = voiceOf('radio=any_talkie\\nlocation=rescue\\ncall_one_in=0\\nstate=silent');
const fr = strings('fr');
console.log(JSON.stringify({ talker: offers(talker), giver: offers(giver), trader: offers(trader),
  section: offers(section), rescue: offers(rescue), missions: giver.missions, arrival: [trader.arrival, section.arrival],
  tags: dash.interactions(giver).concat(dash.interactions(trader)).map((k) => dash.tagText(fr, k, k.id === 'trade' ? trader : giver)),
  state: [rescue.state, rescue.active, talker.active], name: [talker.name, voiceOf('name=Sheet Name').name] }));
"""
        got = run_node(script)
        self.assertEqual(got['talker'], ['talk'])
        self.assertEqual(got['giver'], ['talk', 'missions', 'share', 'calls'])
        self.assertEqual(got['trader'], ['talk', 'trade'])
        self.assertEqual(got['section'], ['talk', 'trade'], 'a [trade] section alone makes a trader')
        self.assertEqual(got['rescue'], ['talk', 'rescue'])
        self.assertEqual(got['missions'], 2)
        self.assertEqual(got['arrival'], ['boat', 'road'])
        self.assertIn('2 missions', got['tags'])
        self.assertIn('Troc en bateau', ' '.join(got['tags']))
        self.assertEqual(got['state'], ['silent', False, True])
        self.assertEqual(got['name'], ['Entry Name', 'Sheet Name'])

    def test_radio_level_of_a_voice(self):
        """radio= as written; a fixed frequency gets the radio it needs, as the badge of the step "where"."""
        script = DASHBOARD_PRELUDE + """
const levels = ['radio=good_talkie', 'frequency=145.0', 'frequency=320.0', 'frequency=0.2', 'frequency=145.1',
  'frequency=abc'].map((line) => voiceOf(line).level);
console.log(JSON.stringify({ levels, rank: ['any_talkie', 'military', null].map((l) => dash.levelRank(catalog, l)) }));
"""
        got = run_node(script)
        self.assertEqual(got['levels'], ['good_talkie', 'any_talkie', 'tactical', 'military', None, None])
        self.assertEqual(got['rank'], [1, 5, 0])

    def test_tiles_filters_and_sort(self):
        script = DASHBOARD_PRELUDE + """
const rows = [voiceOf('name=Zed\\nradio=any_talkie\\nlisten=always\\nactions=say,share_frequency\\ncall_one_in=3'),
  voiceOf('name=Abe\\nradio=pro_talkie\\nlisten=10:00-12:00\\nactions=say,propose_trade', '[trade]\\narrival=cache'),
  voiceOf('name=Moe\\nradio=good_talkie\\nlisten=08:00-09:00\\nactions=say,start_mission', '[mission m]\\ntype=scout'),
  voiceOf('name=Kim\\nradio=any_talkie\\nlisten=06:00-21:00\\nlocation=rescue\\nstate=silent')];
const names = (list) => list.map((v) => v.name);
console.log(JSON.stringify({ tiles: dash.tiles(rows, catalog),
  trade: names(dash.filterRows(rows, { kind: 'trade', level: null })),
  simple: names(dash.filterRows(rows, { kind: null, level: 'any_talkie' })),
  both: names(dash.filterRows(rows, { kind: 'rescue', level: 'pro_talkie' })),
  byName: names(dash.sortRows(rows, 'name', 1, catalog)), byNameDown: names(dash.sortRows(rows, 'name', -1, catalog)),
  byRadio: names(dash.sortRows(rows, 'radio', 1, catalog)), byHours: names(dash.sortRows(rows, 'hours', 1, catalog)),
  byKinds: names(dash.sortRows(rows, 'kinds', 1, catalog)) }));
"""
        got = run_node(script)
        self.assertEqual(got['tiles'], {'voices': 4, 'traders': 1, 'missions': 1, 'simple': 2, 'gap': 21, 'silent': 1})
        self.assertEqual(got['trade'], ['Abe'])
        self.assertEqual(got['simple'], ['Zed', 'Kim'])
        self.assertEqual(got['both'], [])
        self.assertEqual(got['byName'], ['Abe', 'Kim', 'Moe', 'Zed'])
        self.assertEqual(got['byNameDown'], ['Zed', 'Moe', 'Kim', 'Abe'])
        self.assertEqual(got['byRadio'], ['Zed', 'Kim', 'Moe', 'Abe'])
        self.assertEqual(got['byHours'], ['Zed', 'Kim', 'Abe', 'Moe'])
        self.assertEqual(got['byKinds'], ['Zed', 'Abe', 'Kim', 'Moe'], 'most things to do first, then by name')


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

    def test_every_radio_level_has_its_card_and_help(self):
        """E24-T01: a card per radio level of the catalogue (emoji, plain name, who hears it) and its help topic."""
        levels = [level['id'] for level in json.loads((ATELIER / 'catalog.json').read_text(encoding='utf-8'))['radioLevels']]
        self.assertEqual(len(levels), 5)
        for lang in ('fr', 'en'):
            strings = self.strings(lang)
            for level in levels:
                with self.subTest(lang=lang, level=level):
                    for key in (f'radio.{level}.icon', f'radio.{level}.name', f'radio.{level}.who',
                                f'help.head.radio.{level}.what'):
                        self.assertIn(key, strings)

    def test_server_codes_are_translated(self):
        server = (ROOT / 'bridge' / 'atelier_server.py').read_text(encoding='utf-8')
        codes = set(re.findall(r"(?:AtelierError\(\d+, |Done\()'([a-z_]+)'", server))
        self.assertGreater(len(codes), 10)
        for lang in ('fr', 'en'):
            with self.subTest(lang):
                self.assertEqual(sorted(f'code.{c}' for c in codes if f'code.{c}' not in self.strings(lang)), [])


if __name__ == '__main__':
    unittest.main()
