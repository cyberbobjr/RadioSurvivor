"""Banc hors jeu du mod commun batman_CoreAI (E18-T01, ADR adr-separation-mods.md, D03) : métadonnées
Build 42, exigé par RadioSurvivor, chargé avant lui par tous les lanceurs de test, module de base en Lua."""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents' / 'mods'
CORE = MODS / 'batman_CoreAI'
CORE_ID = 'batman_CoreAI'
LAUNCH_ORDER = [CORE_ID, 'batman_LivingKnox', 'batman_RadioSurvivor', 'batman_CoreAITests',
                'batman_LivingKnoxTests', 'batman_RadioSurvivorTests']


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
        # E18-T05 (user decision of 2026-11-05): the mission template "signal" needs Signal Smoke, nothing else.
        self.assertEqual(listed(info.get('require', '')), ['batman_SignalSmoke'])
        self.assertTrue(re.fullmatch(r'\d+\.\d+\.\d+', info.get('modversion', '')))

    def test_radiosurvivor_requires_the_core_mod(self):
        info = mod_info(MODS / 'batman_RadioSurvivor' / '42.21' / 'mod.info')
        self.assertIn(CORE_ID, listed(info.get('require', '')))

    def test_launchers_load_the_mods_then_their_test_mods(self):
        # E18-T07, E21-T07: core, Living Knox, RadioSurvivor, then the test mods in the same order (each test mod
        # requires its mod and the core test mod) in autoclient.py, autotest.json and the dedicated smoke script.
        def ours(ids):
            return [i for i in ids if i in LAUNCH_ORDER]
        text = (ROOT / 'tools' / 'autoclient' / 'autoclient.py').read_text(encoding='utf-8')
        ids = re.findall(r"^\s*\('(\w+)',", text[text.index('MODS = ['):text.index('IGNORE =')], re.M)
        self.assertEqual(ours(ids), LAUNCH_ORDER)
        conf = json.loads(re.sub(r'^\s*//.*$', '', (ROOT / 'autotest.json').read_text(encoding='utf-8'), flags=re.M))
        self.assertEqual(ours([m.get('path', '').rsplit('/', 1)[-1] for m in conf['mods']]), LAUNCH_ORDER)
        smoke = (ROOT / 'tests' / 'run_dedicated_smoke.ps1').read_text(encoding='utf-8')
        mods_line = re.search(r'^Mods=(.*)$', smoke, re.M).group(1).split(';')
        self.assertEqual(ours([m.lstrip('\\') for m in mods_line]), LAUNCH_ORDER)
        self.assertIn("Contents/mods/" + CORE_ID, smoke)

    def test_test_mods_require_their_mod_and_the_core_test_mod(self):
        # E21-T07 (ADR adr-coreai-separation.md D06): one development test mod per mod of the item.
        expected = {'batman_CoreAITests': [CORE_ID],
                    'batman_LivingKnoxTests': ['batman_CoreAITests', 'batman_LivingKnox'],
                    'batman_RadioSurvivorTests': ['batman_CoreAITests', 'batman_RadioSurvivor']}
        for mod_id, require in expected.items():
            folder = ROOT / 'dev' / mod_id
            self.assertTrue((folder / 'common').is_dir(), f'{mod_id}: common/ is required by Build 42')
            info = mod_info(folder / '42.21' / 'mod.info')
            self.assertEqual(info.get('id'), mod_id)
            self.assertEqual(listed(info.get('require', '')), require, mod_id)

    def test_core_module_loads_alone(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        src = CORE / '42.21' / 'media' / 'lua' / 'shared' / 'CoreAI' / 'CA_Core.lua'
        core = lua.execute(src.read_text(encoding='utf-8'))
        self.assertEqual(lua.eval('CoreAI.MOD_ID'), CORE_ID)
        self.assertEqual(core.MOD_ID, CORE_ID)
        self.assertIsInstance(lua.eval('CoreAI.VERSION'), int)
        for p in src.parent.rglob('*.lua'):
            raw = p.read_bytes()
            self.assertTrue(all(b < 128 for b in raw), f'{p.name}: non-ASCII byte (Kahlua lexer)')


if __name__ == '__main__':
    unittest.main(verbosity=1)
