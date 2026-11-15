"""CA_GroupFacts (batman_CoreAI, E21-T06 slice 14): the public facts of the human groups of an NPC engine, read by
the other mods without naming that engine. Lua 5.1 (lupa) with a double of isClient. NOT an in-game validation.

    GroupFacts.on(kind, fn) -> boolean     kinds member_died, group_gone, group_created; unknown kind refused
    GroupFacts.emit(kind, fact) -> n       calls every listener of the kind in subscription order, returns how many

    python RadioSurvivor/tests/test_core_group_facts.py
"""
from __future__ import annotations

import unittest
from pathlib import Path

import lupa.lua51 as lua

CORE_LUA = Path(__file__).resolve().parents[1] / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'
SOURCE = CORE_LUA / 'server' / 'CoreAI' / 'CA_GroupFacts.lua'


class GroupFactsTests(unittest.TestCase):
    def setUp(self):
        self.rt = lua.LuaRuntime(unpack_returned_tuples=True)
        self.rt.execute('isClient = function() return false end; SEEN = {}')
        self.g = self.rt.globals()
        self.F = self.rt.execute(SOURCE.read_text(encoding='utf-8'))

    def seen(self):
        return [tuple(r.values()) for r in self.g.SEEN.values()]

    def listen(self, tag, kind):
        fn = self.rt.eval(f'function(f) SEEN[#SEEN + 1] = {{ "{tag}", f.group }} end')
        return self.F.on(kind, fn)

    def test_kinds(self):
        self.assertEqual(sorted(self.F.KINDS.keys()), ['group_created', 'group_gone', 'member_died'])

    def test_every_listener_of_the_kind_in_order(self):
        self.assertTrue(self.listen('a', 'member_died'))
        self.assertTrue(self.listen('b', 'member_died'))
        self.assertTrue(self.listen('c', 'group_gone'))
        fact = self.rt.table_from({'id': 'grp-1', 'group': 'Mill Folk', 'role': 'medic'})
        self.assertEqual(self.F.emit('member_died', fact), 2)
        self.assertEqual(self.seen(), [('a', 'Mill Folk'), ('b', 'Mill Folk')])
        self.assertEqual(self.F.emit('group_gone', self.rt.table_from({'id': 'grp-1', 'group': 'Mill Folk'})), 1)
        self.assertEqual(self.seen()[-1], ('c', 'Mill Folk'))
        self.assertEqual(self.F.emit('group_created', self.rt.table_from({'id': 'grp-2'})), 0)

    def test_unknown_kind_or_bad_arguments_ignored(self):
        self.assertFalse(self.listen('x', 'rumour'))
        self.assertFalse(self.F.on('member_died', 'not a function'))
        self.assertEqual(self.F.emit('rumour', self.rt.table_from({})), 0)
        self.listen('a', 'group_gone')
        self.assertEqual(self.F.emit('group_gone', 'not a table'), 0)
        self.assertEqual(self.seen(), [])


if __name__ == '__main__':
    unittest.main()
