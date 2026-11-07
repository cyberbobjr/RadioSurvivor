"""Mods needed by each in-game suite (E18-T14): the same campaigns run with RadioSurvivor alone, Living Knox alone and
both mods; a suite whose mods are not all active is SKIP (RST.modsRefusal).

    python RadioSurvivor/tests/test_suite_mods.py

A suite needs the mods of RST.suiteMods: opts.mods when declared, else "lk" for lk.*, "rs" for rs.*, nothing (core
mod only) for the others. This bench reads every suite file and checks that what a suite uses is covered: a
Living Knox module, its helpers or an NPC of the provider needs "lk"; a RadioSurvivor module, its helpers or the
notebook needs "rs". Guarded optional uses (the suite also runs without the mod) are listed in OPTIONAL.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUITES = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / 'shared' / 'RST' / 'suites'

LK_USE = re.compile(r'spawnNpc|npcReady|LivingKnox[./]|RST\.LKHelpers|RST_LKHelpers|LKGroupFixture|LKProbe|RS_LivingKnox'
                    r'|"livingknox"|NPC_PROVIDER')
RS_USE = re.compile(r'RadioSurvivor/(?!tests\b)|\bRS_(?!LivingKnox\b)[A-Z]\w+|RST\.RSHelpers|RST_RSHelpers|RadioSurvivor_')
DECL = re.compile(r'RST\.suite\(\s*"([\w.]+)"\s*,\s*(\{[^\n]*?\}\s*,|function)')
# Optional uses: the suite checks the mod first (if RS_LivingKnox ~= nil then ... end) and runs without it.
OPTIONAL = {'lk.debugview': {'rs'}, 'lk.npcsheet': {'rs'}, 'rc.notebook': {'rs'},
            'rs.factions.mandate': {'lk'}}  # E18-T15: agreements test skipped without Living Knox


def strip_comments(text):
    text = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
    return re.sub(r'--[^\n]*', '', text)


def default_mods(name):
    if name.startswith('lk.'):
        return {'lk'}
    if name.startswith('rs.'):
        return {'rs'}
    return set()


def suites():
    """name -> (declared mods or None, file name, needs inferred from the file)."""
    out = {}
    for path in sorted(SUITES.glob('*.lua')):
        raw = path.read_text(encoding='utf-8')
        code = strip_comments(raw)
        needs = ({'lk'} if LK_USE.search(code) else set()) | ({'rs'} if RS_USE.search(code) else set())
        for m in DECL.finditer(code):
            opts = m.group(2)
            declared = None
            mm = re.search(r'mods\s*=\s*\{([^}]*)\}', opts)
            if mm:
                declared = set(re.findall(r'"(\w+)"', mm.group(1)))
            out[m.group(1)] = (declared, path.name, needs)
    return out


class SuiteModsTests(unittest.TestCase):
    def test_every_suite_declares_the_mods_it_uses(self):
        found = suites()
        self.assertGreater(len(found), 140)
        missing = []
        for name, (declared, fname, needs) in sorted(found.items()):
            have = declared if declared is not None else default_mods(name)
            lacking = needs - have - OPTIONAL.get(name, set())
            if lacking:
                missing.append(f'{name} ({fname}): needs {sorted(lacking)}')
        self.assertEqual(missing, [])

    def test_declared_mods_are_known_short_names(self):
        for name, (declared, fname, _) in suites().items():
            if declared is not None:
                self.assertTrue(declared and declared <= {'lk', 'rs'}, f'{name} ({fname}): {declared}')
                self.assertNotEqual(declared, default_mods(name), f'{name}: same as the default, drop it')


if __name__ == '__main__':
    unittest.main()
