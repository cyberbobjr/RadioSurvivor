"""Notebook views of the mission templates in the core mod batman_CoreAI (E21-T03, slice 2).

    python RadioSurvivor/tests/test_core_mission_views.py

CA_MissionViews (client/CoreAI/CA_MissionViews.lua) and every view of client/CoreAI/MissionViews/, loaded with the core
mod alone on package.path, as the game loads them (sorted by name):
- one view per template, the deliver view also for a row without a template name or with an unknown one;
- the generic lines of a view are written with the core keys IGUI_CA_<key>, shipped in every language of the core mod;
- giver presentations (registerGiver(kind, {remote, sections, reportLine})): a giver kind without registration is a
  giver in person (remote false, no section); a registered giver replaces the lines of a template at its section point
  (scout, retrieve_id) or adds lines there (deliver items, item), the rest of the view unchanged.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CORE_LUA = ROOT / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'
VIEWS_DIR = CORE_LUA / 'client' / 'CoreAI' / 'MissionViews'
REGISTRY = CORE_LUA / 'client' / 'CoreAI' / 'CA_MissionViews.lua'
TRANSLATE = CORE_LUA / 'shared' / 'Translate'
TEMPLATES = ('barricade', 'clear', 'deliver', 'item', 'recover', 'relay', 'retrieve_id', 'route', 'scout', 'signal',
             'watch')

PRELUDE = r"""
getText = function(key, ...)
    local args = { ... }
    for i = 1, #args do key = key .. '|' .. tostring(args[i]) end
    return key
end
CTX = { tr = function(key) return 'NB_' .. key end, itemName = function(t) return 'item ' .. tostring(t) end,
    placeName = function(k) return tostring(k) end, clueText = function() return nil end }
function RENDER(template, row)
    local out = {}
    require('CoreAI/CA_MissionViews').get(template).detail(row, function(text) out[#out + 1] = text end, CTX)
    return out
end
"""

REMOTE_GIVER = r"""
require('CoreAI/CA_MissionViews').registerGiver('remote', {
    remote = true,
    reportLine = function(row) return 'report to ' .. row.requester end,
    sections = {
        scout = function(row, line) line('remote scout ' .. tostring(row.zoneReached)) end,
        retrieve_id = function(row, line) line('remote card') end,
        deliver = function(row, line) line('remote drops') end,
        item = function(row, line, ctx) line('remote drops of ' .. ctx.itemName(row.itemType)) end,
    }})
"""


def view_files():
    return sorted(VIEWS_DIR.glob('*.lua'), key=lambda p: p.name.lower())


class Base(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        path = ';'.join(f'{(CORE_LUA / side).as_posix()}/?.lua' for side in ('client', 'shared'))
        self.lua.execute('package.path = ...; package.cpath = ""', path)
        self.lua.execute(PRELUDE)
        for view in view_files():
            self.lua.execute(view.read_text(encoding='utf-8'))
        self.views = self.lua.eval('require("CoreAI/CA_MissionViews")')

    def render(self, template, **row):
        return list(self.lua.eval('RENDER')(template, self.lua.table_from(row)).values())


class RegistryTests(Base):
    def test_one_view_file_per_template(self):
        self.assertEqual(sorted(p.stem for p in view_files()),
                         sorted('CA_View_' + ''.join(w.capitalize() for w in t.split('_')) for t in TEMPLATES))
        for template in TEMPLATES:
            self.assertIsNotNone(self.views.get(template), template)

    def test_deliver_is_the_default_view(self):
        deliver = self.views.get('deliver')
        self.assertTrue(self.lua.eval('rawequal')(self.views.get(None), deliver))
        self.assertTrue(self.lua.eval('rawequal')(self.views.get('unknown'), deliver))

    def test_unregistered_giver_is_in_person(self):
        giver = self.views.giver('npc')
        self.assertFalse(giver.remote)
        self.assertIsNone(giver.reportLine)
        self.assertFalse(self.views.giver(None).remote)

    def test_registered_giver(self):
        self.lua.execute(REMOTE_GIVER)
        giver = self.views.giver('remote')
        self.assertTrue(giver.remote)
        self.assertEqual(giver.reportLine(self.lua.table_from({'requester': 'Ann'})), 'report to Ann')


class GenericLinesTests(Base):
    def test_scout_in_person(self):
        self.assertEqual(self.render('scout', mapZone=True, zoneReached=True, reachedBy='Ann'),
                         ['IGUI_CA_ScoutReached|Ann', 'IGUI_CA_ScoutReport'])
        self.assertEqual(self.render('scout', donor='npc', mapZone=True),
                         ['IGUI_CA_ScoutMapZone', 'IGUI_CA_ScoutNotReached', 'IGUI_CA_ScoutReport'])

    def test_retrieve_in_person(self):
        self.assertEqual(self.render('retrieve_id', person='Bob', found=True, foundBy='Ann'),
                         ['IGUI_CA_RetrievePerson|Bob', 'IGUI_CA_RetrieveFound|Ann', 'IGUI_CA_RetrieveReport'])

    def test_deliver_items_and_supply(self):
        accepted = self.lua.table_from({'Base.Nails': True})
        self.assertEqual(self.render('deliver', delivered=1, quantity=3, accepted=accepted),
                         ['IGUI_CA_Progress|1|3', 'IGUI_CA_AcceptedItems|item Base.Nails', 'IGUI_CA_OneUnit'])
        self.assertEqual(self.render('deliver', unit='value', delivered=2, quantity=9, accepted=accepted,
                                     values=self.lua.table_from({'Base.Nails': 4})),
                         ['IGUI_CA_SupplyProgress|2|9', 'IGUI_CA_AcceptedItems|item Base.Nails (4)',
                          'IGUI_CA_SupplyValues'])

    def test_recover_and_signal_words(self):
        self.assertEqual(self.render('recover', cache='food', found=False),
                         ['IGUI_CA_RecoverCache|IGUI_CA_Cache_food', 'IGUI_CA_RecoverNotFound', 'IGUI_CA_RecoverReport'])
        self.assertEqual(self.render('signal', color='red', hour=22, windowHours=4, lit=False)[:2],
                         ['IGUI_CA_SignalColor|IGUI_CA_SignalColor_red', 'IGUI_CA_SignalHour|22|2'])


class GiverSectionTests(Base):
    def setUp(self):
        super().setUp()
        self.lua.execute(REMOTE_GIVER)

    def test_sections_replace_the_lines_of_the_section_point(self):
        self.assertEqual(self.render('scout', donor='remote', mapZone=True, zoneReached=False),
                         ['IGUI_CA_ScoutMapZone', 'remote scout false'])
        self.assertEqual(self.render('retrieve_id', donor='remote', found=False),
                         ['IGUI_CA_RetrieveNotFound', 'remote card'])

    def test_sections_add_lines_at_the_section_point(self):
        accepted = self.lua.table_from({'Base.Nails': True})
        self.assertEqual(self.render('deliver', donor='remote', delivered=0, quantity=1, accepted=accepted),
                         ['IGUI_CA_Progress|0|1', 'remote drops', 'IGUI_CA_AcceptedItems|item Base.Nails',
                          'IGUI_CA_OneUnit'])
        self.assertEqual(self.render('item', donor='remote', itemType='Base.Locket', place='Mill', found=False),
                         ['IGUI_CA_ItemWhat|item Base.Locket', 'IGUI_CA_ItemPlace|Mill', 'IGUI_CA_ItemNotFound',
                          'IGUI_CA_ItemDropIt', 'remote drops of item Base.Locket', 'IGUI_CA_ItemOnlyThis',
                          'IGUI_CA_ItemReport'])

    def test_a_template_without_section_keeps_its_lines(self):
        self.assertEqual(self.render('relay', donor='remote', place='Tower', minZ=2, relayed=True),
                         ['IGUI_CA_RelayPlace|Tower', 'IGUI_CA_RelayLevel|2', 'IGUI_CA_RelayOn', 'IGUI_CA_RelayRule',
                          'IGUI_CA_RelayReport'])


class TranslationTests(unittest.TestCase):
    def test_every_core_key_of_the_views_is_shipped(self):
        code = '\n'.join(p.read_text(encoding='utf-8') for p in [REGISTRY, *view_files()])
        # Every capitalised literal of the views is a key word (template names are lower case).
        keys = {'IGUI_CA_' + k for k in re.findall(r"'([A-Z][A-Za-z_]*[A-Za-z])'", code)}
        prefixes = ['IGUI_CA_' + k for k in re.findall(r"'([A-Z][A-Za-z]*_)' \.\.", code)]
        self.assertGreater(len(keys), 50)
        self.assertEqual(sorted(prefixes), ['IGUI_CA_Cache_', 'IGUI_CA_SignalColor_'])
        for lang in ('EN', 'FR'):
            shipped = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8-sig'))
            self.assertEqual(sorted(keys - set(shipped)), [], lang)
            for prefix in prefixes:
                self.assertTrue(any(k.startswith(prefix) for k in shipped), f'{lang}: {prefix}')


if __name__ == '__main__':
    unittest.main(verbosity=1)
