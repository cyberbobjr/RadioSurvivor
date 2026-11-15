"""Tests hors jeu du socle des registres Living Knox (LK16-T01, ADR remise en ordre SOLID D02) :
shared/LivingKnox/LK_Registry.lua (LivingKnox.Registry.new).

    python tests/test_lk_registry.py

Vrai Lua du mod sous lupa (Lua 5.1, `next` retiré comme dans Kahlua). Inscription, tri par order puis clé,
remplacement d'une inscription de même clé (rechargement), refus par validate avec un message qui nomme le registre,
lecture par clé, liste stable, adoption de tables publiques existantes.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from lupa.lua51 import LuaError, LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LK_SHARED = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'shared'


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Registry(unittest.TestCase):
    def setUp(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        self.rt.globals().next = None   # absent de Kahlua
        self.rt.execute(f'package.path = [[{LK_SHARED.as_posix()}/?.lua;]]; package.cpath = ""')
        self.rt.execute('require "LivingKnox/LK_Registry"')

    def run_lua(self, code):
        return self.rt.execute(code)

    def ids(self, reg='R', key='id'):
        return lua_list(self.run_lua(f'local out = {{}} for i, s in ipairs({reg}:list()) do out[i] = s.{key} end '
                                     'return out'))

    def test_sorted_by_order_then_key(self):
        self.run_lua('R = LivingKnox.Registry.new("Test.register", { sort = true })\n'
                     'R:register({ id = "b", order = 20 }) R:register({ id = "c", order = 10 })\n'
                     'R:register({ id = "a", order = 20 }) R:register({ id = "d", order = 5 })')
        self.assertEqual(self.ids(), ['d', 'c', 'a', 'b'])

    def test_register_returns_the_spec_and_get_reads_it(self):
        same = self.run_lua('R = LivingKnox.Registry.new("Test.register", {})\n'
                            'local s = { id = "x", order = 1 } return rawequal(R:register(s), s)')
        self.assertTrue(same)
        self.assertEqual(self.run_lua('return R:get("x").order'), 1)
        self.assertIsNone(self.run_lua('return R:get("missing")'))

    def test_same_key_replaces_the_old_entry(self):
        self.run_lua('R = LivingKnox.Registry.new("Test.register", {})\n'
                     'R:register({ id = "a", order = 10, v = 1 }) R:register({ id = "b", order = 20 })\n'
                     'R:register({ id = "a", order = 30, v = 2 })')
        self.assertEqual(self.ids(), ['b', 'a'])
        self.assertEqual(self.run_lua('return R:get("a").v'), 2)
        self.assertEqual(self.run_lua('return #R:list()'), 2)

    def test_custom_key(self):
        self.run_lua('R = LivingKnox.Registry.new("Test.register", { key = "kind" })\n'
                     'R:register({ kind = "z", order = 1 }) R:register({ kind = "y", order = 1 })')
        self.assertEqual(self.ids(key='kind'), ['y', 'z'])
        self.assertEqual(self.run_lua('return R:get("z").kind'), 'z')

    def test_validate_refusal_names_the_registry_and_keeps_the_others(self):
        self.run_lua('R = LivingKnox.Registry.new("LivingKnox.Test.registerThing", { validate = function(s)\n'
                     '  if type(s) ~= "table" or type(s.order) ~= "number" then return false, "spec needs order" end\n'
                     '  return true end })\n'
                     'R:register({ id = "ok", order = 1 })')
        ok, err = self.run_lua('return pcall(function() R:register({ id = "bad" }) end)')
        self.assertFalse(ok)
        self.assertIn('LivingKnox.Test.registerThing: spec needs order', err)
        self.assertEqual(self.ids(), ['ok'])
        self.assertIsNone(self.run_lua('return R:get("bad")'))

    def test_error_points_at_the_caller_level_given(self):
        # Niveau 2 : l'appelant de la fonction publique qui enveloppe register (comme error(msg, 2) dans celle-ci).
        err = self.rt.execute('R = LivingKnox.Registry.new("Test.wrap", { validate = function() return false, '
                              '"nope" end })\n'
                              'local function wrapper(s) return R:register(s, 2) end\n'
                              'local ok, e = pcall(function() wrapper({ id = "x" }) end) return e', name='=bench')
        self.assertTrue(err.startswith('bench:'), err)
        self.assertIn('Test.wrap: nope', err)

    def test_missing_key_is_refused(self):
        self.run_lua('R = LivingKnox.Registry.new("Test.register", {})')
        ok, err = self.run_lua('return pcall(function() R:register({ order = 1 }) end)')
        self.assertFalse(ok)
        self.assertIn('Test.register: spec needs id', err)
        with self.assertRaises(LuaError):
            self.run_lua('R:register("nope")')

    def test_try_returns_nil_and_reason_without_raising(self):
        res = self.run_lua('R = LivingKnox.Registry.new("Test.register", { sort = false, validate = function(s)\n'
                           '  if R:get(s.id) ~= nil then return false, "identifier already registered" end\n'
                           '  return true end })\n'
                           'R:try({ id = "a" }) return R:try({ id = "a" })')
        self.assertEqual(res, (None, 'identifier already registered'))
        self.assertEqual(self.ids(), ['a'])

    def test_unsorted_keeps_registration_order(self):
        self.run_lua('R = LivingKnox.Registry.new("Test.register", { sort = false })\n'
                     'R:register({ id = "b" }) R:register({ id = "a" }) R:register({ id = "c" })')
        self.assertEqual(self.ids(), ['b', 'a', 'c'])

    def test_adopts_existing_public_tables(self):
        # Rechargement d'un module : ses tables publiques gardent leur identité, le nouveau registre les reprend.
        self.run_lua('LIST, BY = {}, {}\n'
                     'local R1 = LivingKnox.Registry.new("Test.register", { items = LIST, byKey = BY })\n'
                     'R1:register({ id = "a", order = 2 }) R1:register({ id = "b", order = 1 })\n'
                     'R = LivingKnox.Registry.new("Test.register", { items = LIST, byKey = BY })\n'
                     'R:register({ id = "a", order = 0, v = 2 })')
        self.assertTrue(self.run_lua('return rawequal(R:list(), LIST)'))
        self.assertEqual(self.ids(), ['a', 'b'])
        self.assertEqual(self.run_lua('return BY.a.v'), 2)
        self.assertEqual(self.run_lua('return #LIST'), 2)

    def test_stable_list_without_next(self):
        self.run_lua('R = LivingKnox.Registry.new("Test.register", {})\n'
                     'for i = 1, 30 do R:register({ id = "k" .. string.format("%02d", 31 - i), order = 1 }) end')
        self.assertEqual(self.ids(), [f'k{i:02d}' for i in range(1, 31)])
        self.assertIsNone(self.rt.globals().next)


if __name__ == '__main__':
    unittest.main()
