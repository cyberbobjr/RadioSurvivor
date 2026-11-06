"""Data folder of Living Knox and take-over of a game from before the split (E18-T10).

    python RadioSurvivor/tests/test_lk_takeover.py

Registries of Living Knox (NPCs "registry", groups "groups", attitudes "attitudes") live under
Zomboid/Lua/batman_LivingKnox/. A game created before the split (files under batman_RadioSurvivor/livingknox/) is
taken over once: the slot files are copied byte for byte, the old folder stays in place, one console line in English;
never again once the new files exist; never for a new world. Bench tests/harness.py (solo authority), real
LK_Store, LK_Bodies, LK_Groups and LK_Hostility; the old layout is written by the same code with the old folder.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import Base  # noqa: E402

OLD = 'batman_RadioSurvivor/livingknox/'
NAMES = ('registry', 'groups', 'attitudes')


class TakeOverTests(Base):
    mode = 'solo'
    debug = False

    def setUp(self):
        super().setUp()
        for path in ('server/LivingKnox/LK_Groups.lua', 'server/LivingKnox/LK_Hostility.lua'):
            self.h.load('solo', path)

    def init_all(self, new_world):
        self.init(new_world)
        self.run_lua(f'assert(LivingKnox.Groups.init({str(new_world).lower()}))')
        self.run_lua(f'assert(LivingKnox.Hostility.init({str(new_world).lower()}))')

    def files(self, folder):
        root = self.h.file_root('solo') / folder
        return {p.name: p.read_bytes() for p in sorted(root.glob('*.txt'))} if root.exists() else {}

    def old_game(self):
        """A game of the old layout: same code, old folder."""
        self.run_lua(f'LivingKnox.Store.DIR = "{OLD}"')
        self.init_all(True)
        self.spawn()
        self.run_lua('LivingKnox.Store.flush()')
        old = self.files(OLD)
        self.assertEqual(sorted({n.split('-')[0] for n in old}), sorted(NAMES))
        self.run_lua('LivingKnox.Store.DIR = "batman_LivingKnox/"')
        return old

    def test_new_folder_by_default(self):
        self.assertEqual(self.ev('LivingKnox.Store.DIR'), 'batman_LivingKnox/')
        self.assertEqual(self.ev('LivingKnox.Store.LEGACY_DIR'), OLD)

    def test_game_from_before_the_split_taken_over_once(self):
        old = self.old_game()
        self.init_all(False)
        new = self.files('batman_LivingKnox')
        self.assertEqual(new, old)                                   # byte for byte, every slot of every registry
        self.assertEqual(self.files(OLD), old)                       # old folder left in place
        self.assertIsNotNone(self.ev('LivingKnox.Store.data().npcs["lk-1"]'))
        lines = [l for l in self.lk() if 'taken over' in l]
        self.assertEqual(len(lines), 3, lines)
        self.assertIn('Zomboid/Lua/batman_RadioSurvivor/livingknox/', lines[0])
        # A new NPC written in the new folder is never replaced by the old files at the next start.
        self.spawn(x=104)
        self.run_lua('LivingKnox.Store.flush()')
        self.init_all(False)
        self.assertIsNotNone(self.ev('LivingKnox.Store.data().npcs["lk-2"]'))
        self.assertEqual(len([l for l in self.lk() if 'taken over' in l]), 3)

    def test_new_world_takes_nothing_over(self):
        self.old_game()
        self.init_all(True)
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"]'))
        self.assertEqual([l for l in self.lk() if 'taken over' in l], [])


if __name__ == '__main__':
    unittest.main()
