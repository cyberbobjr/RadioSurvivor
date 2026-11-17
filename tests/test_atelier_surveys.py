"""E22-T08 (ADR atelier-voix D08): places recorded in game, as the voice workshop reads them.

    python RadioSurvivor/tests/test_atelier_surveys.py

- bridge/place_surveys.py reads the survey file the game writes (server/RadioSurvivor/RS_PlaceSurvey.lua): records
  newest first, comments, blank and malformed lines skipped, missing file, file rewritten by the game, oversized file
  read from its end, at most 200 records;
- GET /api/surveys of bridge/atelier_server.py serves them (empty list without a survey source) and never writes;
- radio_bridge.main puts the survey file next to the voice sheets' folder (Zomboid/Lua/batman_RadioSurvivor);
- bridge/atelier/surveys.js (node, skipped without it) suggests the name of a shared place from a record (E25-T03: the
  Places tab).
The format shared with the game is checked against the real Lua writer in tests/test_rs_place_survey.py.
"""
from __future__ import annotations

import http.client
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bridge'))
import atelier_server as atelier  # noqa: E402
import place_surveys  # noqa: E402
import radio_bridge as rb  # noqa: E402

ATELIER = ROOT / 'bridge' / 'atelier'
NODE = shutil.which('node')
HEADER = '# RadioSurvivor places recorded for the voice workshop, one per line (tab-separated key=value)\n'
DUMPSTER = ('time=2026-11-15 10:00:00\tgame=1993-07-09 08:30\tby=Kate Smith\tat=10610,9305,0\t'
            'containers=bin:trash_01_0;crate:location_shop_01_8')
KITCHEN = ('time=2026-11-15 10:05:00\tgame=1993-07-09 08:41\tby=Kate Smith\tat=10600,9300,1\troom=kitchen\t'
           'building=10590,9290,10620,9310')


class SurveyFileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / place_surveys.FILE_NAME
        self.surveys = place_surveys.SurveyFile(self.path)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text: str) -> None:
        self.path.write_bytes(text.encode('utf-8'))

    def test_records_newest_first(self):
        self.write(HEADER + DUMPSTER + '\n' + KITCHEN + '\n')
        records = self.surveys.records()
        self.assertEqual([r['at'] for r in records], [{'x': 10600, 'y': 9300, 'z': 1}, {'x': 10610, 'y': 9305, 'z': 0}])
        kitchen, dumpster = records
        self.assertEqual(kitchen, {'at': {'x': 10600, 'y': 9300, 'z': 1}, 'time': '2026-11-15 10:05:00',
                                   'game': '1993-07-09 08:41', 'by': 'Kate Smith', 'room': 'kitchen',
                                   'building': {'x1': 10590, 'y1': 9290, 'x2': 10620, 'y2': 9310}, 'containers': []})
        self.assertIsNone(dumpster['room'])
        self.assertIsNone(dumpster['building'])
        self.assertEqual(dumpster['containers'], [{'type': 'bin', 'sprite': 'trash_01_0'},
                                                  {'type': 'crate', 'sprite': 'location_shop_01_8'}])

    def test_missing_file_gives_no_record(self):
        self.assertFalse(self.surveys.found)
        self.assertEqual(self.surveys.records(), [])

    def test_malformed_lines_skipped(self):
        self.write(HEADER + '\n' + 'garbage\n' + 'at=1,2\n' + 'at=a,b,c\tby=x\n' + DUMPSTER + '\r\n'
                   + 'by=no square\n' + 'at=5,6,0\tbuilding=1,2,3\n')
        records = self.surveys.records()
        self.assertEqual([r['at'] for r in records], [{'x': 5, 'y': 6, 'z': 0}, {'x': 10610, 'y': 9305, 'z': 0}])
        self.assertIsNone(records[0]['building'])       # three numbers only: no building
        self.assertEqual(records[1]['by'], 'Kate Smith')

    def test_rewritten_file_read_anew(self):
        self.write(HEADER + DUMPSTER + '\n')
        self.assertEqual(len(self.surveys.records()), 1)
        self.write(HEADER + KITCHEN + '\n')                     # the game rewrites the whole file on each record
        self.assertEqual([r['room'] for r in self.surveys.records()], ['kitchen'])

    def test_at_most_200_records_and_oversized_file_read_from_its_end(self):
        lines = [f'time=t{i}\tat={i},{i},0' for i in range(260)]
        self.write(HEADER + '\n'.join(lines) + '\n')
        records = self.surveys.records()
        self.assertEqual(len(records), place_surveys.MAX_RECORDS)
        self.assertEqual(records[0]['at']['x'], 259)
        self.assertEqual(records[-1]['at']['x'], 60)
        big = 'x' * 1000
        lines = [f'time=t{i}\tat={i},{i},0\tby={big}' for i in range(800)]
        self.write(HEADER + '\n'.join(lines) + '\n')
        records = self.surveys.records()
        self.assertEqual(records[0]['at']['x'], 799)
        self.assertLessEqual(len(records), place_surveys.MAX_RECORDS)
        self.assertTrue(all(r['by'] == big for r in records), 'a line cut by the start of the read was kept')

    def test_invalid_utf8_tolerated(self):
        self.path.write_bytes(HEADER.encode() + b'time=x\tby=Ren\xe9\tat=1,2,0\n')
        self.assertEqual(self.surveys.records()[0]['at'], {'x': 1, 'y': 2, 'z': 0})


class SurveyRouteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.working = base / 'Lua' / 'batman_RadioSurvivor' / 'personas'
        self.working.mkdir(parents=True)
        self.file = self.working.parent / place_surveys.FILE_NAME
        self.file.write_text(HEADER + DUMPSTER + '\n' + KITCHEN + '\n', encoding='utf-8')
        self.before = self.file.read_bytes()
        store = atelier.VoiceStore(self.working, base / 'shipped')
        self.live = atelier.Live(surveys=place_surveys.SurveyFile(self.file))
        self.server = atelier.bind(store, 0, ATELIER, None, lambda m: None, live=self.live)
        atelier.start(self.server)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.assertEqual(self.file.read_bytes(), self.before, 'the workshop never writes the survey file')
        self.tmp.cleanup()

    def get(self, path: str):
        conn = http.client.HTTPConnection(atelier.HOST, self.server.server_address[1], timeout=10)
        conn.request('GET', path)
        resp = conn.getresponse()
        payload = json.loads(resp.read())
        conn.close()
        return resp.status, payload

    def test_records_served_newest_first(self):
        status, payload = self.get('/api/surveys')
        self.assertEqual(status, 200)
        self.assertTrue(payload['ok'])
        self.assertTrue(payload['surveysFound'])
        self.assertEqual(Path(payload['surveysFile']), self.file)
        self.assertEqual([r['room'] for r in payload['records']], ['kitchen', None])
        self.assertEqual(payload['records'][1]['containers'][0], {'type': 'bin', 'sprite': 'trash_01_0'})

    def test_file_appearing_later_is_read(self):
        self.file.unlink()
        status, payload = self.get('/api/surveys')
        self.assertEqual((status, payload['records'], payload['surveysFound']), (200, [], False))
        self.file.write_bytes(self.before)
        self.assertEqual(len(self.get('/api/surveys')[1]['records']), 2)

    def test_without_survey_source(self):
        self.live.surveys = None
        status, payload = self.get('/api/surveys')
        self.assertEqual((status, payload['ok'], payload['records'], payload['surveysFile']), (200, True, [], None))

    def test_only_get(self):
        conn = http.client.HTTPConnection(atelier.HOST, self.server.server_address[1], timeout=10)
        conn.request('POST', '/api/surveys', body=b'{}', headers={'Content-Type': 'application/json'})
        resp = conn.getresponse()
        resp.read()
        conn.close()
        self.assertEqual(resp.status, 404)


class CompositionTests(unittest.TestCase):
    def test_survey_file_next_to_the_voice_sheets(self):
        lua = Path('Zomboid') / 'Lua'
        exchange = lua / rb.DEFAULT_EXCHANGE.name
        self.assertEqual(rb.personas_folder(exchange).parent / place_surveys.FILE_NAME,
                         lua / 'batman_RadioSurvivor' / 'workshop-places.txt')
        source = (ROOT / 'bridge' / 'radio_bridge.py').read_text(encoding='utf-8')
        self.assertIn('surveys=place_surveys.SurveyFile(personas_folder(args.exchange).parent / '
                      'place_surveys.FILE_NAME)', source)


@unittest.skipUnless(NODE, 'node is missing')
class SuggestionTests(unittest.TestCase):
    def suggest(self, records: list[dict]) -> list[dict]:
        t = {k: v for k, v in json.loads((ATELIER / 'i18n' / 'en.json').read_text(encoding='utf-8')).items()
             if k.startswith('surveys.')}
        script = (f"import {{ suggestedLabel, cutBytes }} from '{(ATELIER / 'surveys.js').as_uri()}';\n"
                  f"const strings = {json.dumps(t)};\n"
                  "const t = (k) => strings[k] ?? k;\n"
                  f"const records = {json.dumps(records)};\n"
                  "console.log(JSON.stringify(records.map((r) => ({ label: suggestedLabel(r, t),"
                  " bytes: new TextEncoder().encode(suggestedLabel(r, t)).length }))));")
        done = subprocess.run([NODE, '--input-type=module', '-e', script], capture_output=True, text=True,
                              encoding='utf-8', timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def test_label_from_what_was_recorded(self):
        base = {'at': {'x': 1, 'y': 2, 'z': 0}, 'room': None, 'building': None, 'containers': []}
        out = self.suggest([
            {**base, 'containers': [{'type': 'bin', 'sprite': 'trash_01_0'}]},
            {**base, 'containers': [{'type': 'fridge', 'sprite': 's'}], 'room': 'kitchen',
             'building': {'x1': 0, 'y1': 0, 'x2': 5, 'y2': 5}},
            {**base, 'room': 'living_room', 'building': {'x1': 0, 'y1': 0, 'x2': 5, 'y2': 5}},
            {**base, 'building': {'x1': 0, 'y1': 0, 'x2': 5, 'y2': 5}},
            base,
            {**base, 'containers': [{'type': 'é' * 40, 'sprite': 's'}]},
        ])
        self.assertEqual([o['label'] for o in out[:5]], ['Bin', 'Fridge - Kitchen', 'Living room', 'Building',
                                                         'Outdoor spot'])
        self.assertEqual(out[5]['bytes'], 48)          # cut to the 48 bytes of label=, never inside a character


if __name__ == '__main__':
    unittest.main()
