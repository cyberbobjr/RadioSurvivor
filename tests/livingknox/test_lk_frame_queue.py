"""Tests hors jeu de la file d'attente partagée de Living Knox (LK20-T05, ADR simplification D05) :
shared/LivingKnox/LK_FrameQueue.lua (LivingKnox.FrameQueue.new).

    python tests/livingknox/test_lk_frame_queue.py

Vrai Lua du mod sous lupa (Lua 5.1, `next` retiré comme dans Kahlua), registre des groupes remplacé par une doublure
qui note ses appels (hold, release, flush). Enfilage sans doublon, départ à l'image suivante (marque « fresh »), une
étape de travail par image, écriture du registre retenue pendant la file puis faite dans une image à elle, file vidée
tout de suite (finish), fin annoncée par l'étape elle-même (close), remise à zéro, reprise d'un état existant.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
LK_SHARED = ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'shared'

GROUPS = r'''
CALLS = {}
local function note(s) CALLS[#CALLS + 1] = s end
DIRTY, HELD = true, false
LivingKnox = LivingKnox or {}
LivingKnox.Groups = {
    hold = function(key, frames) note("hold " .. key .. " " .. frames) end,
    release = function(key) note("release " .. key) end,
    isDirty = function() return DIRTY end,
    isHeld = function() return HELD end,
    flush = function() note("flush") end,
}
DONE = {}
'''


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class FrameQueue(unittest.TestCase):
    def setUp(self):
        self.rt = LuaRuntime(unpack_returned_tuples=True)
        self.rt.globals().next = None   # absent de Kahlua
        self.rt.execute(f'package.path = [[{LK_SHARED.as_posix()}/?.lua;]]; package.cpath = ""')
        self.rt.execute(GROUPS)
        self.rt.execute('require "LivingKnox/LK_FrameQueue"')

    def run_lua(self, code):
        return self.rt.execute(code)

    def calls(self):
        return lua_list(self.run_lua('return CALLS'))

    def done(self):
        return lua_list(self.run_lua('return DONE'))

    def one_per_frame(self, margin=3, frames=None):
        extra = f', frames = {frames}' if frames else ''
        self.run_lua(f'Q = LivingKnox.FrameQueue.new({{ hold = "test", margin = {margin}{extra}, step = function(q)\n'
                     '    local item = q.list[q.head]\n'
                     '    q.head = q.head + 1\n'
                     '    q.queued[item] = nil\n'
                     '    DONE[#DONE + 1] = item\n'
                     '    return true, item ~= "b"\n'
                     'end })')

    def test_require_returns_the_module(self):
        self.assertTrue(self.run_lua('return require("LivingKnox/LK_FrameQueue") == LivingKnox.FrameQueue'))

    def test_push_without_duplicate_key(self):
        self.one_per_frame()
        self.assertTrue(self.run_lua('return Q:push("a", "a")'))
        self.assertFalse(self.run_lua('return Q:push("a", "a")'))
        self.assertTrue(self.run_lua('return Q:push("b")'))
        self.assertTrue(self.run_lua('return Q:push("b")'))   # sans clé : pas de contrôle de doublon
        self.assertEqual(self.run_lua('return Q:count()'), 3)
        self.assertTrue(self.run_lua('return Q.queued.a == "a"'))

    def test_start_marks_fresh_and_holds_the_registry(self):
        self.one_per_frame(margin=3, frames=2)
        self.run_lua('Q:start()')
        self.assertFalse(self.run_lua('return Q.fresh or Q.write'))   # file vide : rien
        self.assertEqual(self.calls(), [])
        self.run_lua('Q:push("a", "a") Q:push("c", "c") Q:start()')
        self.assertTrue(self.run_lua('return Q.fresh and Q.write'))
        self.assertEqual(self.calls(), ['hold test 7'])               # 2 images x 2 entrées + 3

    def test_one_step_per_frame_from_the_next_frame_then_write_in_its_own_frame(self):
        self.one_per_frame()
        self.run_lua('Q:push("a", "a") Q:push("b", "b") Q:start()')
        self.assertFalse(self.run_lua('return Q:frame()'))             # image de l'enfilage : rien
        self.assertEqual(self.done(), [])
        self.run_lua('Q:frameStart()')
        self.assertTrue(self.run_lua('return Q:frame()'))              # résultat de l'étape
        self.assertEqual(self.done(), ['a'])
        self.assertFalse(self.run_lua('return Q:frame()'))             # étape faite, résultat faux
        self.assertEqual(self.done(), ['a', 'b'])
        self.assertTrue(self.run_lua('return Q:pending() == false and Q.write'))
        self.assertEqual(self.calls(), ['hold test 5'])
        self.assertFalse(self.run_lua('return Q:frame()'))             # image à elle : écriture
        self.assertEqual(self.calls(), ['hold test 5', 'release test', 'flush'])
        self.assertFalse(self.run_lua('return Q.write'))
        self.assertFalse(self.run_lua('return Q:frame()'))
        self.assertEqual(len(self.calls()), 3)

    def test_no_flush_while_another_hold_remains_or_registry_clean(self):
        self.one_per_frame()
        self.run_lua('HELD = true Q:push("a") Q:start() Q:frameStart() Q:frame() Q:frame()')
        self.assertEqual(self.calls(), ['hold test 4', 'release test'])
        self.run_lua('HELD, DIRTY, CALLS = false, false, {} Q:push("a") Q:start() Q:frameStart() Q:frame() Q:frame()')
        self.assertEqual(self.calls(), ['hold test 4', 'release test'])

    def test_unspent_step_closes_in_the_same_frame(self):
        self.run_lua('Q = LivingKnox.FrameQueue.new({ hold = "test", margin = 0, step = function(q)\n'
                     '    q.head = #q.list + 1\n'
                     '    return false, false\n'
                     'end })\n'
                     'Q:push("a") Q:start() Q:frameStart()')
        self.assertFalse(self.run_lua('return Q:frame()'))
        self.assertEqual(self.calls(), ['hold test 1', 'release test', 'flush'])

    def test_finish_drains_counts_and_releases_without_flush(self):
        self.one_per_frame()
        self.run_lua('Q:push("a", "a") Q:push("b", "b") Q:push("c", "c") Q:start()')
        self.assertEqual(self.run_lua('return Q:finish()'), 2)       # résultats vrais : a et c
        self.assertEqual(self.done(), ['a', 'b', 'c'])
        self.assertFalse(self.run_lua('return Q.fresh or Q.write or Q:pending()'))
        self.assertEqual(self.calls(), ['hold test 6', 'release test'])
        self.assertEqual(self.run_lua('return Q:finish()'), 0)

    def test_step_can_close_the_queue_itself(self):
        self.run_lua('Q = LivingKnox.FrameQueue.new({ hold = "test", margin = 0, step = function(q, all)\n'
                     '    q.head = #q.list + 1\n'
                     '    q:close(not all)\n'
                     '    return true\n'
                     'end })\n'
                     'Q:push("a") Q:start() Q:frameStart() Q:frame()')
        self.assertEqual(self.calls(), ['hold test 1', 'release test', 'flush'])
        self.run_lua('Q:frame()')                                      # déjà écrit : rien de plus
        self.assertEqual(len(self.calls()), 3)

    def test_hold_again_with_the_remaining_entries(self):
        self.one_per_frame(margin=3)
        self.run_lua('Q:push("a") Q:push("b") Q.head = 2 Q:hold()')
        self.assertEqual(self.calls(), ['hold test 4'])

    def test_push_after_a_drained_queue_starts_a_new_list(self):
        self.one_per_frame()
        self.run_lua('Q:push("a", "a") Q:finish() Q:push("b", "b")')
        self.assertEqual(lua_list(self.run_lua('return Q.list')), ['b'])
        self.assertEqual(self.run_lua('return Q.head'), 1)

    def test_clear_forgets_everything_and_releases(self):
        self.one_per_frame()
        self.run_lua('Q:push("a", "a") Q:start() Q:clear()')
        self.assertFalse(self.run_lua('return Q.fresh or Q.write or Q:pending() or Q.queued.a ~= nil'))
        self.assertEqual(self.calls(), ['hold test 4', 'release test'])

    def test_clear_without_group_registry(self):
        self.one_per_frame()
        self.run_lua('LivingKnox.Groups = nil Q:push("a") Q:clear()')
        self.assertFalse(self.run_lua('return Q:pending()'))

    def test_existing_state_is_kept(self):
        self.run_lua('OLD = { list = { "x" }, head = 1, queued = { x = true }, fresh = true, write = true }\n'
                     'Q = LivingKnox.FrameQueue.new({ hold = "test", step = function() return true end }, OLD)')
        self.assertTrue(self.run_lua('return Q == OLD and Q:pending() and Q.fresh and Q.queued.x'))


if __name__ == '__main__':
    unittest.main()
