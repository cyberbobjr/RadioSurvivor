"""E25-T03: shared places of the voice workshop (bridge/atelier/places.js, ADR lieux communs D02, D05, D06, D07).

    python RadioSurvivor/tests/radiosurvivor/test_atelier_places.py

The pure module of the Places tab runs in node (skipped when node is missing):
- the shipped _places.txt reads as points (a zone when area= is written) and writes back unchanged;
- places made by the page (a point, a zone from two corners and a floor, a point turned into a zone) are accepted by
  the bridge reader with the rules of the game (persona_store.parse_places_lines, same messages as RS_Persona.lua);
- where a voice names a place (marks=, target=, drops=, points=, landing=, cache_place=) is read from a registry, so the
  tab says which voices use a place and refuses to delete it; a distance (near, far, very_far) is no place;
- the lists of a voice offer every place or the points only (dead drop, meeting point, route, cache: D05);
- light checks of a place said in words (no name, no square, zone too big, name too long).
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
sys.path.insert(0, str(ROOT / 'bridge'))
from test_atelier_ui import NODE, SHIPPED, node_prelude, run_node, shipped_sheets  # noqa: E402
import persona_store  # noqa: E402

PLACES_FILE = SHIPPED / '_places.txt'


def prelude() -> str:
    return node_prelude()   # imports places.js as `places`


@unittest.skipUnless(NODE, 'node is not installed')
class AtelierPlacesTests(unittest.TestCase):
    def test_shipped_places_read_and_write_back_unchanged(self):
        got = run_node(prelude() + f"""
const text = sheet.normalizeText(fs.readFileSync({json.dumps(str(PLACES_FILE))}, 'utf8'));
const model = places.parsePlaces(text);
const all = places.list(model);
console.log(JSON.stringify({{ same: places.serialize(model) === text, ids: all.map((p) => p.id),
  first: all.map(({{ section, ...p }}) => p)[1], kinds: [...new Set(all.map((p) => p.kind))] }}));
""")
        self.assertTrue(got['same'])
        self.assertEqual(got['ids'], list(persona_store.load_places(PLACES_FILE)))
        self.assertEqual(got['first'], {'id': 'checkpoint', 'label': 'Relay station', 'kind': 'point',
                                        'at': {'x': '4827', 'y': '6277', 'z': '0'}, 'z': '0',
                                        'area': {'x1': '', 'y1': '', 'x2': '', 'y2': ''}})
        self.assertEqual(got['kinds'], ['point'])

    def test_places_made_by_the_page_are_accepted_by_the_reader(self):
        got = run_node(prelude() + """
const model = places.newPlacesFile(catalog.sheet.format);
const mill = places.addPlace(model, { label: 'Old mill', kind: 'point', at: { x: '10600', y: '9300', z: '0' } });
const town = places.addPlace(model, { label: 'Old mill', kind: 'zone', z: '0',
  area: { x1: '10700', y1: '9500', x2: '10500', y2: '9300' } });
const shed = places.addPlace(model, { label: 'Shed', kind: 'point', at: { x: '1', y: '2', z: '1' } });
places.setPlace(shed, { kind: 'zone', area: { x1: '5', y1: '5', x2: '9', y2: '7' }, z: '1' });
const taken = places.addPlace(model, { label: 'Near' });
console.log(JSON.stringify({ text: places.serialize(model), ids: [mill.id, town.id, shed.id, taken.id],
  kinds: places.list(model).map((p) => p.kind), area: places.find(model, town.id).area }));
""")
        self.assertEqual(got['ids'], ['old_mill', 'old_mill_2', 'shed', 'near_2'],
                         'ids made from the names, unique, never a distance (near, far, very_far)')
        self.assertEqual(got['kinds'], ['point', 'zone', 'zone', 'point'])
        self.assertEqual(got['area'], {'x1': '10500', 'y1': '9300', 'x2': '10700', 'y2': '9500'})
        text = got['text']
        self.assertTrue(text.startswith('format=1\n'))
        self.assertIn('[place old_mill_2]\nlabel=Old mill\narea=10500,9300,10700,9500,0\n', text)
        self.assertIn('[place shed]\nlabel=Shed\narea=5,5,9,7,1\n', text)
        self.assertNotIn('at=1,2,1', text, 'a point turned into a zone loses its square')
        complete = text.replace('[place near_2]\nlabel=Near', '[place near_2]\nlabel=Near\nat=3,4,0')
        read = persona_store.parse_places_lines(persona_store.split_lines(complete))
        self.assertEqual(list(read), got['ids'])
        self.assertEqual(read['old_mill_2'].area, (10500, 9300, 10700, 9500))

    def test_voices_using_a_place_and_the_choices_of_a_list(self):
        sheets = {p.stem: str(p) for p in shipped_sheets()}
        got = run_node(prelude() + f"""
const shared = places.parsePlaces(fs.readFileSync({json.dumps(str(PLACES_FILE))}, 'utf8'));
places.addPlace(shared, {{ label: 'Downtown', kind: 'zone', z: '0', area: {{ x1: '1', y1: '1', x2: '50', y2: '50' }} }});
const voices = Object.entries({json.dumps(sheets)}).map(([id, path]) => ({{ id, name: id,
  model: sheet.parse(fs.readFileSync(path, 'utf8')) }}));
const scout = sheet.parse('format=1\\nid=s\\nname=Sam\\nmarks=downtown\\n\\n[mission a]\\ntype=scout\\ntarget=far\\n'
  + '\\n[mission b]\\ntype=route\\npoints=clinic,checkpoint\\n\\n[prompt]\\nHi.\\n');
voices.push({{ id: 's', name: 'Sam', model: scout }});
const used = (id) => places.usedBy(id, voices, catalog).map((v) => v.name);
const refs = places.references(scout, catalog).map((r) => [r.id, r.block, r.key, r.points]);
console.log(JSON.stringify({{ checkpoint: used('checkpoint'), clinic: used('clinic'), dumpsters: used('drop_dumpsters'),
  downtown: used('downtown'), nobody: used('ekron_mailbox'),
  far: used('far'), refs,
  points: places.choices(shared, {{ points: true }}).map((c) => c.value).includes('downtown'),
  all: places.choices(shared).find((c) => c.value === 'downtown') }}));
""")
        self.assertEqual(got['checkpoint'], ['cody', 'Sam'])
        self.assertEqual(got['clinic'], ['darlene', 'Sam'])
        self.assertEqual(got['dumpsters'], ['darlene'])
        self.assertEqual(got['downtown'], ['Sam'])
        self.assertEqual(len(got['nobody']), 1, 'a meeting point of one trader')
        self.assertEqual(got['far'], [], 'a distance is no place')
        self.assertEqual(got['refs'], [['downtown', 'head', 'marks', False], ['clinic', 'mission', 'points', True],
                                       ['checkpoint', 'mission', 'points', True]])
        self.assertFalse(got['points'], 'a zone is never offered where a point is needed')
        self.assertEqual(got['all'], {'value': 'downtown', 'label': 'Downtown', 'kind': 'zone'})

    def test_light_checks_of_a_place(self):
        got = run_node(prelude() + """
const model = places.newPlacesFile('1');
const add = (values) => places.find(model, places.addPlace(model, values).id);
const cases = [
  add({ label: 'Fine', kind: 'point', at: { x: '1', y: '2', z: '0' } }),
  add({ label: '', kind: 'point', at: { x: '1', y: '2', z: '0' } }),
  add({ label: 'No square', kind: 'point', at: { x: '', y: '2', z: '0' } }),
  add({ label: 'Huge', kind: 'zone', z: '0', area: { x1: '0', y1: '0', x2: '1500', y2: '10' } }),
  add({ label: 'Half zone', kind: 'zone', z: '0', area: { x1: '0', y1: '0', x2: '', y2: '10' } }),
  add({ label: 'é'.repeat(25), kind: 'point', at: { x: '1', y: '2', z: '0' } }),
];
console.log(JSON.stringify(cases.map((p) => places.problems(p, catalog))));
""")
        self.assertEqual(got, [[], ['places.check.no_name'], ['places.check.no_square'], ['places.check.zone_too_big'],
                               ['places.check.no_square'], ['places.check.name_too_long']])


if __name__ == '__main__':
    unittest.main()
