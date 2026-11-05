"""Banc hors jeu du mod commun batman_RadioSurvivorCore (E18-T01, ADR adr-separation-mods.md, D03) : métadonnées
Build 42, exigé par RadioSurvivor, chargé avant lui par tous les lanceurs de test, module de base en Lua."""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents' / 'mods'
CORE = MODS / 'batman_RadioSurvivorCore'
CORE_ID = 'batman_RadioSurvivorCore'


def mod_info(path):
    out = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip()
    return out


def listed(value):
    return [v.strip().lstrip('\\') for v in value.split(',') if v.strip()]


class CoreModTests(unittest.TestCase):
    def test_core_mod_layout_and_metadata(self):
        self.assertTrue((CORE / 'common').is_dir(), 'common/ is required by Build 42')
        info = mod_info(CORE / '42.21' / 'mod.info')
        self.assertEqual(info.get('id'), CORE_ID)
        self.assertTrue(info.get('name', '').startswith('batman_'))
        self.assertEqual(info.get('versionMin'), '42.21')
        self.assertNotIn('require', info, 'the core mod requires no other mod (E18 decisions)')
        self.assertTrue(re.fullmatch(r'\d+\.\d+\.\d+', info.get('modversion', '')))

    def test_radiosurvivor_requires_the_core_mod(self):
        info = mod_info(MODS / 'batman_RadioSurvivor' / '42.21' / 'mod.info')
        self.assertIn(CORE_ID, listed(info.get('require', '')))

    def test_launchers_load_the_core_mod_before_radiosurvivor(self):
        text = (ROOT / 'tools' / 'autoclient' / 'autoclient.py').read_text(encoding='utf-8')
        ids = re.findall(r"^\s*\('(\w+)',", text[text.index('MODS = ['):text.index('IGNORE =')], re.M)
        self.assertLess(ids.index(CORE_ID), ids.index('batman_RadioSurvivor'))
        conf = json.loads(re.sub(r'^\s*//.*$', '', (ROOT / 'autotest.json').read_text(encoding='utf-8'), flags=re.M))
        paths = [m.get('path', '') for m in conf['mods']]
        self.assertLess(paths.index('Contents/mods/' + CORE_ID), paths.index('Contents/mods/batman_RadioSurvivor'))
        smoke = (ROOT / 'tests' / 'run_dedicated_smoke.ps1').read_text(encoding='utf-8')
        mods_line = re.search(r'^Mods=(.*)$', smoke, re.M).group(1).split(';')
        self.assertLess(mods_line.index('\\' + CORE_ID), mods_line.index('\\batman_RadioSurvivor'))
        self.assertIn("Contents/mods/" + CORE_ID, smoke)

    def test_core_module_loads_alone(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        src = CORE / '42.21' / 'media' / 'lua' / 'shared' / 'RadioSurvivorCore' / 'RC_Core.lua'
        core = lua.execute(src.read_text(encoding='utf-8'))
        self.assertEqual(lua.eval('RadioSurvivorCore.MOD_ID'), CORE_ID)
        self.assertEqual(core.MOD_ID, CORE_ID)
        self.assertIsInstance(lua.eval('RadioSurvivorCore.VERSION'), int)
        for p in src.parent.rglob('*.lua'):
            raw = p.read_bytes()
            self.assertTrue(all(b < 128 for b in raw), f'{p.name}: non-ASCII byte (Kahlua lexer)')


if __name__ == '__main__':
    unittest.main(verbosity=1)
