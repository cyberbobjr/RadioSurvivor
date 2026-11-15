"""Mission zones on the world map in the core mod batman_CoreAI (E21-T03, slice 3).

    python RadioSurvivor/tests/test_core_map_zones.py

CA_MapZones (client/CoreAI/CA_MapZones.lua), loaded with the core mod alone on package.path, over the world map
symbols double of the notebook bench (MAP_DOUBLE: WorldMapSymbolsV2 reached through a hidden UIWorldMap):
- one ring and one label per circle of the active missions of the snapshot the player takes part in (search area,
  depot, drop points, several circles of the template), labels IGUI_CA_MapZone<style>, Anon without a name;
- drawn once per session, a zone symbol that no longer matches a mission is removed, other symbols are kept;
- no world map: nothing drawn (no_map); not loaded on a dedicated server;
- every label key of a style declared by a core template (mapStyle) and of the depot is shipped in every language.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

from test_carnet import MAP_DOUBLE

ROOT = Path(__file__).resolve().parents[1]
CORE_LUA = ROOT / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'
TRANSLATE = CORE_LUA / 'shared' / 'Translate'


class Base(unittest.TestCase):
    server = False

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        path = ';'.join(f'{(CORE_LUA / side).as_posix()}/?.lua' for side in ('client', 'shared'))
        self.lua.execute('package.path = ...; package.cpath = ""', path)
        self.lua.execute(f'isServer = function() return {"true" if self.server else "false"} end')
        self.lua.execute(MAP_DOUBLE)
        self.zones = self.lua.eval('require("CoreAI/CA_MapZones")')

    def missions(self, *rows):
        t = self.lua.table_from
        return t([t({k: (t(v) if isinstance(v, dict) else
                         t([t(x) for x in v]) if isinstance(v, list) else v) for k, v in row.items()})
                  for row in rows])

    def symbols(self):
        return [dict(s.items()) for s in self.lua.eval('mapSymbols()').values()]

    def texts(self):
        return sorted(s['text'] for s in self.symbols() if s['kind'] == 'text')


ACTIVE = {'id': 7, 'state': 'active', 'engaged': True, 'requester': 'Ann', 'mapStyle': 'Clear',
          'mapZone': {'x': 100, 'y': 200, 'r': 20}}


class DrawingTests(Base):
    def test_ring_and_label_of_a_search_area(self):
        result = self.zones.zones(self.missions(ACTIVE))
        self.assertEqual((result.added, result.removed), (2, 0))
        ring, label = self.symbols()
        self.assertEqual((ring['kind'], ring['id'], ring['x'], ring['y']), ('texture', 'Circle', 100, 200))
        self.assertAlmostEqual(ring['scale'], 2 * 20 / self.zones.ZONE_RING)
        self.assertAlmostEqual(ring['a'], 0.8, delta=0.01)
        self.assertEqual((label['text'], label['x'], label['y']), ('IGUI_CA_MapZoneClear|Ann', 100, 180))
        self.assertAlmostEqual(label['scale'], self.zones.SCALE)

    def test_depot_drops_and_template_circles(self):
        row = dict(ACTIVE, mapStyle='Route', requester='',
                   depotZone={'x': 10, 'y': 10, 'r': 5},
                   dropZones=[{'x': 30, 'y': 30, 'r': 4, 'label': 'Mill'}],
                   mapZones=[{'x': 50, 'y': 50, 'r': 6, 'label': 'Bridge'}])
        self.zones.zones(self.missions(row))
        self.assertEqual(self.texts(), ['IGUI_CA_MapZoneDepotAnon', 'IGUI_CA_MapZoneDepot|Mill',
                                        'IGUI_CA_MapZoneRouteAnon', 'IGUI_CA_MapZoneRoute|Bridge'])

    def test_only_active_missions_the_player_takes_part_in(self):
        self.zones.zones(self.missions(dict(ACTIVE, state='offer'), dict(ACTIVE, id=8, engaged=False)))
        self.assertEqual(self.symbols(), [])

    def test_once_per_session_and_removed_when_the_mission_ends(self):
        self.lua.execute('addPlayerSymbol("Target", 5, 5)')
        self.zones.zones(self.missions(ACTIVE))
        again = self.zones.zones(self.missions(ACTIVE))
        self.assertEqual((again.added, again.removed), (0, 0))
        self.lua.execute('table.remove(MAP_SYMBOLS, 3)')  # the player erased the label
        self.assertEqual(self.zones.zones(self.missions(ACTIVE)).added, 0)
        self.zones.resetZonesForTests()  # new session: drawn again
        self.assertEqual(self.zones.zones(self.missions(ACTIVE)).added, 1)
        ended = self.zones.zones(self.missions())
        self.assertEqual((ended.added, ended.removed), (0, 2))
        self.assertEqual([(s['kind'], s['id']) for s in self.symbols()], [('texture', 'Target')])

    def test_no_world_map(self):
        self.lua.execute('MapItem = nil')
        self.zones.resetForTests()
        self.assertEqual(self.zones.zones(self.missions(ACTIVE)), (None, 'no_map'))


class ServerTests(Base):
    server = True

    def test_not_loaded_on_a_dedicated_server(self):
        self.assertFalse(self.lua.eval('type(require("CoreAI/CA_MapZones")) == "table"'))


class TranslationTests(unittest.TestCase):
    def test_label_keys_of_every_core_style_are_shipped(self):
        code = '\n'.join(p.read_text(encoding='utf-8') for p in (CORE_LUA / 'server' / 'CoreAI').glob('*.lua'))
        styles = set(re.findall(r"mapStyle = '([A-Za-z]+)'", code)) | {'Depot'}
        self.assertGreaterEqual(len(styles), 8)
        for lang in ('EN', 'FR'):
            shipped = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8-sig'))
            for style in sorted(styles):
                for key in (f'IGUI_CA_MapZone{style}', f'IGUI_CA_MapZone{style}Anon'):
                    self.assertIn(key, shipped, lang)


if __name__ == '__main__':
    unittest.main(verbosity=1)
