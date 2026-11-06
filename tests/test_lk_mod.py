"""Living Knox in its own mod batman_LivingKnox (E18-T07, ADR adr-separation-mods.md).

    python RadioSurvivor/tests/test_lk_mod.py

Offline bench: Build 42 metadata (requires the core mod, incompatible with Bandits and Project A-Life), the NPC
engine (Lua, lkactor_* AnimSets, LivingKnox sandbox page, IGUI_LK_ / Sandbox_LivingKnox_ keys) lives only in
batman_LivingKnox, every test launcher loads core, Living Knox then RadioSurvivor, and the Living Knox Lua files
require no RadioSurvivor module but RS_Rescue (site geometry, removed by E18-T08).
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents' / 'mods'
LK = MODS / 'batman_LivingKnox'
RS = MODS / 'batman_RadioSurvivor'
LK_ID = 'batman_LivingKnox'
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


def translate_keys(mod, lang):
    keys = set()
    folder = mod / '42.21' / 'media' / 'lua' / 'shared' / 'Translate' / lang
    for path in folder.glob('*.json') if folder.is_dir() else []:
        keys |= set(json.loads(path.read_text(encoding='utf-8')))
    return keys


def option_pages(mod):
    path = mod / '42.21' / 'media' / 'sandbox-options.txt'
    if not path.exists():
        return []
    return re.findall(r'^option\s+(\w+)\.', path.read_text(encoding='utf-8'), re.M)


class LivingKnoxModTests(unittest.TestCase):
    def test_layout_and_metadata(self):
        self.assertTrue((LK / 'common').is_dir(), 'common/ is required by Build 42')
        info = mod_info(LK / '42.21' / 'mod.info')
        self.assertEqual(info.get('id'), LK_ID)
        self.assertTrue(info.get('name', '').startswith('batman_'))
        self.assertEqual(info.get('versionMin'), '42.21')
        self.assertTrue(re.fullmatch(r'\d+\.\d+\.\d+', info.get('modversion', '')))
        self.assertEqual(listed(info.get('require', '')), [CORE_ID])
        self.assertEqual(listed(info.get('incompatible', '')), ['Bandits2', 'ProjectALifeNPCs'])

    def test_radiosurvivor_metadata(self):
        info = mod_info(RS / '42.21' / 'mod.info')
        self.assertNotIn('incompatible', info, 'taken over by Living Knox')
        # Transition until E18-T09 (provider adapter carried by Living Knox): RadioSurvivor still needs the engine.
        self.assertIn(LK_ID, listed(info.get('require', '')))

    def test_engine_files_only_in_living_knox(self):
        for side in ('client', 'server', 'shared'):
            self.assertFalse((RS / '42.21' / 'media' / 'lua' / side / 'LivingKnox').exists(), side)
            self.assertTrue((LK / '42.21' / 'media' / 'lua' / side / 'LivingKnox').is_dir(), side)
        self.assertEqual(list(RS.rglob('lkactor_*.xml')), [])
        self.assertGreater(len(list((LK / 'common' / 'media' / 'AnimSets').rglob('lkactor_*.xml'))), 40)
        self.assertNotIn('LivingKnox', option_pages(RS))
        self.assertEqual(set(option_pages(LK)), {'LivingKnox'})

    def test_translations_split_by_prefix(self):
        for lang in ('EN', 'FR'):
            rs, lk = translate_keys(RS, lang), translate_keys(LK, lang)
            self.assertFalse({k for k in rs if k.startswith(('IGUI_LK_', 'Sandbox_LivingKnox'))}, lang)
            self.assertTrue(lk, lang)
            self.assertFalse({k for k in lk if not k.startswith(('IGUI_LK_', 'Sandbox_LivingKnox'))}, lang)
        self.assertEqual(translate_keys(LK, 'EN'), translate_keys(LK, 'FR'))

    def test_launchers_load_core_living_knox_then_radiosurvivor(self):
        text = (ROOT / 'tools' / 'autoclient' / 'autoclient.py').read_text(encoding='utf-8')
        ids = re.findall(r"^\s*\('(\w+)',", text[text.index('MODS = ['):text.index('IGNORE =')], re.M)
        self.assertLess(ids.index(CORE_ID), ids.index(LK_ID))
        self.assertLess(ids.index(LK_ID), ids.index('batman_RadioSurvivor'))
        conf = json.loads(re.sub(r'^\s*//.*$', '', (ROOT / 'autotest.json').read_text(encoding='utf-8'), flags=re.M))
        paths = [m.get('path', '') for m in conf['mods']]
        self.assertLess(paths.index('Contents/mods/' + CORE_ID), paths.index('Contents/mods/' + LK_ID))
        self.assertLess(paths.index('Contents/mods/' + LK_ID), paths.index('Contents/mods/batman_RadioSurvivor'))
        smoke = (ROOT / 'tests' / 'run_dedicated_smoke.ps1').read_text(encoding='utf-8')
        mods_line = re.search(r'^Mods=(.*)$', smoke, re.M).group(1).split(';')
        self.assertLess(mods_line.index('\\' + LK_ID), mods_line.index('\\batman_RadioSurvivor'))
        self.assertIn('Contents/mods/' + LK_ID, smoke)

    def test_no_radiosurvivor_module_required(self):
        bad = []
        for path in (LK / '42.21' / 'media' / 'lua').rglob('*.lua'):
            for m in re.finditer(r'require\s*\(?\s*["\'](RadioSurvivor/[\w/]+)', path.read_text(encoding='utf-8')):
                bad.append(f'{path.name}: {m.group(1)}')
        # E18-T07: only RS_Rescue is left (site geometry), removed by E18-T08.
        self.assertEqual(sorted(set(b.split(': ')[1] for b in bad)), ['RadioSurvivor/RS_Rescue'])

    def test_no_non_ascii_literal(self):
        # Kahlua lexer: no non-ASCII byte inside a string literal (comments may hold French text).
        for path in (LK / '42.21' / 'media' / 'lua').rglob('*.lua'):
            for n, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                code = line.split('--', 1)[0]
                self.assertTrue(all(ord(c) < 128 for c in code), f'{path.name}:{n}')


if __name__ == '__main__':
    unittest.main()
