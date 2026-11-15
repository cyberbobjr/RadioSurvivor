"""Living Knox in its own mod batman_LivingKnox (E18-T07, ADR adr-separation-mods.md).

    python tests/test_lk_mod.py

Offline bench: Build 42 metadata (requires the core mod, incompatible with Bandits and Project A-Life), the NPC
engine (Lua, lkactor_* AnimSets, LivingKnox sandbox page, IGUI_LK_ / Sandbox_LivingKnox_ keys) in batman_LivingKnox.
E21-T08: this bench reads Living Knox files only (launch order of every mod: tests/test_core_mod.py).
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODS = ROOT / 'Contents' / 'mods'
LK = MODS / 'batman_LivingKnox'
LK_ID = 'batman_LivingKnox'
CORE_ID = 'batman_CoreAI'


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

    def test_engine_files_in_living_knox(self):
        for side in ('client', 'server', 'shared'):
            self.assertTrue((LK / '42.21' / 'media' / 'lua' / side / 'LivingKnox').is_dir(), side)
        self.assertGreater(len(list((LK / 'common' / 'media' / 'AnimSets').rglob('lkactor_*.xml'))), 40)
        self.assertEqual(set(option_pages(LK)), {'LivingKnox'})

    def test_translations_split_by_prefix(self):
        for lang in ('EN', 'FR'):
            lk = translate_keys(LK, lang)
            self.assertTrue(lk, lang)
            self.assertFalse({k for k in lk if not k.startswith(('IGUI_LK_', 'Sandbox_LivingKnox'))}, lang)
        self.assertEqual(translate_keys(LK, 'EN'), translate_keys(LK, 'FR'))

    def test_no_non_ascii_literal(self):
        # Kahlua lexer: no non-ASCII byte inside a string literal (comments may hold French text).
        for path in (LK / '42.21' / 'media' / 'lua').rglob('*.lua'):
            for n, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                code = line.split('--', 1)[0]
                self.assertTrue(all(ord(c) < 128 for c in code), f'{path.name}:{n}')


if __name__ == '__main__':
    unittest.main()
