"""Exchange history with NPCs kept by the core mod (E18-T11, user decision of 2026-11-05).

    python RadioSurvivor/tests/test_core_history.py

RC_History (core mod, authority): one private file Zomboid/Lua/batman_RadioSurvivorCore/history-<world>-<0|1>.txt
(RC_SlotFile, header RCHISTORY1), lines per character and per interlocutor, bounded like before (MAX_HISTORY). The
notebook state (RS_State) no longer writes them: each contact's history is the table of the core mod (same table in
memory, so every existing writer is unchanged).
"""
from __future__ import annotations

import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, CORE_LUA  # noqa: E402

WORLD = ("getWorld = function() return {getGameMode = function() return setmetatable({}, {__tostring = function() return 'Multiplayer' end}) end, "
         "getWorld = function() return 'e18t11' end} end")
WORLD_HEX = '4d756c7469706c617965722f653138743131'


class Base(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp')
        self.root = self.h.file_root('server')
        self.h.machine('server').rt.execute(WORLD)

    def tearDown(self):
        self.h.close()

    def ev(self, code):
        return self.h.eval('server', '(function() ' + code + ' end)()')

    def texts(self, character, peer):
        return self.ev(f'local H = require("RadioSurvivorCore/RC_History") local out = {{}} '
                       f'for _, l in ipairs(H.lines("{character}", "{peer}")) do out[#out + 1] = l.author .. ": " .. l.text end '
                       'return table.concat(out, "|")')

    def state_text(self):
        """Decoded notebook state of the newest slot, as one string (to look for history lines)."""
        return self.ev('local S = require("RadioSurvivor/RS_State") local C = require("RadioSurvivorCore/RC_Codec") '
                       'local best for slot = 0, 1 do local r = S._read(S.path .. "-" .. slot .. ".txt") '
                       'if r and (not best or r.generation > best.generation) then best = r end end '
                       'local out = {} local function walk(v) if type(v) == "table" then for k, x in pairs(v) do '
                       'out[#out + 1] = tostring(k) walk(x) end else out[#out + 1] = tostring(v) end end '
                       'walk(best.data) return table.concat(out, " ")')


class ModuleTests(unittest.TestCase):
    def test_module_in_the_core_and_ascii(self):
        path = CORE_LUA / 'server' / 'RadioSurvivorCore' / 'RC_History.lua'
        self.assertTrue(path.is_file())
        self.assertTrue(path.read_bytes().isascii())


class StateTests(Base):
    def seed(self):
        self.ev('local S = require("RadioSurvivor/RS_State") assert(S.init(true)) '
                'S.data.characters["c-ann"] = {contacts = {["lk:lk-1"] = {}, ["lk:lk-2"] = {}}} '
                'S.data.characters["c-bob"] = {contacts = {["lk:lk-1"] = {}}} '
                'local H = require("RadioSurvivorCore/RC_History") '
                'for c, peer in pairs({["c-ann"] = "lk:lk-1", ["c-bob"] = "lk:lk-1"}) do '
                'H.append(c, peer, {id = "1", author = "Ruth", text = "Again you."}, 40) end '
                'H.append("c-ann", "lk:lk-2", {id = "2", author = "Ruth", text = "Hello."}, 40) '
                'assert(S.save())')

    def test_lines_stay_in_the_core_file_after_a_restart(self):
        self.seed()
        self.ev('package.loaded["RadioSurvivor/RS_State"] = nil local S = require("RadioSurvivor/RS_State") '
                'assert(S.init(false))')
        self.assertEqual(self.texts('c-bob', 'lk:lk-1').count('Again you.'), 1)
        self.assertNotIn('Again you.', self.state_text())

    def test_dropped_contact_and_character_are_forgotten(self):
        self.seed()
        self.ev('local S = require("RadioSurvivor/RS_State") '
                'S.data.characters["c-bob"] = nil S.data.characters["c-ann"].contacts["lk:lk-2"] = nil assert(S.save())')
        self.assertTrue(self.ev('local H = require("RadioSurvivorCore/RC_History") '
                                'return H.find("c-bob", "lk:lk-1") == nil and H.find("c-ann", "lk:lk-2") == nil '
                                'and H.find("c-ann", "lk:lk-1") ~= nil'))

    def test_new_world_starts_empty(self):
        self.seed()
        self.assertTrue(self.ev('return require("RadioSurvivor/RS_State").init(true)'))
        self.assertEqual(self.texts('c-ann', 'lk:lk-1'), '')


class BoundsTests(Base):
    def test_append_keeps_the_last_lines(self):
        self.ev('local S = require("RadioSurvivor/RS_State") assert(S.init(true))')
        out = self.ev('local H = require("RadioSurvivorCore/RC_History") '
                      'for i = 1, 5 do H.append("c", "p", {id = tostring(i), author = "a", text = "t" .. i}, 3) end '
                      'local t = {} for _, l in ipairs(H.lines("c", "p")) do t[#t + 1] = l.text end '
                      'return table.concat(t, ",") .. "|" .. H.MAX')
        self.assertEqual(out, 't3,t4,t5|40')


if __name__ == '__main__':
    unittest.main()
