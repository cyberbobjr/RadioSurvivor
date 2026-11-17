"""RS_State / CA_Codec under Lua 5.1 (lupa): codec bounds (C18), write retry (C19), fast hex and checksum (C20), the
RadioSurvivor file holding the data of the voices only (E21-T04; the notebook store and the purge of dead characters
are the core mod's: tests/coreai/test_core_notebook_store.py). Simulated file API, NOT an in-game validation.

    python RadioSurvivor/tests/radiosurvivor/test_rs_state.py
"""
from __future__ import annotations

import unittest
from pathlib import Path

import lupa.lua51 as lua

LUA = Path(__file__).resolve().parents[2] / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
LK_LUA = Path(__file__).resolve().parents[2] / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua'  # moteur des PNJ (E18)
CORE_LUA = Path(__file__).resolve().parents[2] / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'  # mod commun (E18)

BOOT = r'''
FILES, WRITE_FAIL, CORRUPT_WRITE, PRINTS, DAY = {}, false, false, {}, 10
local loaders = ...
isClient = function() return false end
getTimestampMs = function() return 1000 end
ZombRand = function(a) return a end
print = function(s) PRINTS[#PRINTS + 1] = tostring(s) end
getWorld = function() return {getGameMode = function() return setmetatable({}, {__tostring = function() return 'Multiplayer' end}) end, getWorld = function() return 'w' end} end
getFileWriter = function(path)
    if WRITE_FAIL then return nil end
    local buf = {}
    return {write = function(_, s) buf[#buf + 1] = s end,
        close = function() FILES[path] = CORRUPT_WRITE and 'garbage\n' or table.concat(buf) end}
end
getFileReader = function(path)
    local text = FILES[path]
    if not text then return nil end
    local lines = {}
    for l in text:gmatch('([^\n]*)\n') do lines[#lines + 1] = l end
    local i = 0
    return {readLine = function() i = i + 1; return lines[i] end, close = function() end}
end
-- CA_Reputation (E18-T22): reputation entries live in the core mod's state, Rep.data.reputation[cid].
REP_DATA = {}
package.preload['CoreAI/CA_Reputation'] = function() return {today = function() return DAY end, data = REP_DATA} end
for name, src in pairs(loaders) do
    if package.preload[name] == nil then  -- the doubles above win
        package.preload[name] = function() return assert(loadstring(src, name))() end
    end
end
'''


def runtime():
    rt = lua.LuaRuntime(unpack_returned_tuples=True)
    # Every module of the three mods (E18: RS_State and its providers require the core and the NPC engine).
    sources = {}
    for root in (LK_LUA, CORE_LUA, LUA):
        for side in ('shared', 'server'):
            for f in (root / side).rglob('*.lua'):
                sources[f.relative_to(root / side).with_suffix('').as_posix()] = f.read_text(encoding='utf-8')
    loaders = rt.table_from(sources)
    rt.execute(BOOT, loaders)
    return rt


class CodecBoundsTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.C = self.rt.eval("require('CoreAI/CA_Codec')")

    def test_encoder_refuses_what_the_decoder_refuses(self):
        ok, why = self.rt.execute('''
            local C = require('CoreAI/CA_Codec')
            C.MAX_NODES = 50
            local t = {}
            for i = 1, 30 do t[i] = i end           -- 1 + 60 nodes
            local ok, err = pcall(C.encodeBytes, t)
            return ok, tostring(err)
        ''')
        self.assertFalse(ok)
        self.assertIn('complexity', why)
        # Exactly at the limit: encoded and decoded.
        self.assertTrue(self.rt.execute('''
            local C = require('CoreAI/CA_Codec')
            C.MAX_NODES = 61
            local t = {}
            for i = 1, 30 do t[i] = i end
            return C.decodeBytes(C.encodeBytes(t)) ~= nil and C.lastNodes == 61
        '''))
        # Same counting with cached keys (the same key in several tables) and with the decoder.
        self.assertTrue(self.rt.execute('''
            local C = require('CoreAI/CA_Codec')
            C.MAX_NODES = 200000
            local t = {}
            for i = 1, 20 do t['k' .. i] = {name = 'x', id = i} end
            local body = C.encodeBytes(t)
            local n = C.lastNodes
            C.MAX_NODES = n
            local fits = C.decodeBytes(body) ~= nil
            C.MAX_NODES = n - 1
            return fits and C.decodeBytes(body) == nil and not pcall(C.encodeBytes, t)
        '''))
        for snippet in ('local t = {} for i = 1, 10001 do t[i] = true end return t',
                        'return {x = 0/0}', 'return {x = 1/0}',
                        'local t = {} local c = t for i = 1, 13 do c[1] = {} c = c[1] end return t'):
            value = self.rt.execute(snippet)
            ok = self.rt.eval('function(v) return (pcall(require("CoreAI/CA_Codec").encodeBytes, v)) end')(value)
            self.assertFalse(ok, snippet)

    def test_fast_hex_and_checksum_match_the_historical_ones(self):
        same = self.rt.execute(r'''
            local C = require('CoreAI/CA_Codec')
            local function oldSum(s)
                local a, b = 1, 0
                for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end
                return string.format('%.0f', b * 65536 + a)
            end
            local parts = {}
            for i = 0, 255 do parts[#parts + 1] = string.char(i) end
            local all = table.concat(parts)
            local big = string.rep(all, 70) .. 'tail'
            for _, s in ipairs({'', 'a', all, big, string.rep('\255', 9001)}) do
                if C.checksumBytes(s) ~= oldSum(s) then return 'sum ' .. #s end
                if C.hexOfBytes(s) ~= C.hexBytes(s) then return 'hex ' .. #s end
                if C.unhexBytes(C.hexOfBytes(s)) ~= s then return 'unhex ' .. #s end
            end
            if C.unhexBytes('0') ~= nil or C.unhexBytes('zz') ~= nil or C.unhexBytes('AB') ~= nil then return 'refusal' end
            return 'ok'
        ''')
        self.assertEqual(same, 'ok')


class StateTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.S = self.rt.eval("require('RadioSurvivor/RS_State')")
        self.g = self.rt.globals()

    def files(self):
        return {k: v for k, v in self.g.FILES.items()}

    def test_failed_write_is_retried_not_blocked(self):
        S = self.S
        self.assertTrue(S.init(False))
        S.data.note = 'first'
        self.assertTrue(S.save())
        good = self.files()
        self.g.WRITE_FAIL = True
        S.data.note = 'second'
        self.assertFalse(S.save())
        self.assertFalse(S.blocked, 'transient write error blocked the notebook')
        self.assertTrue(S.dirty)
        self.assertEqual(S.failures, 1)
        self.assertFalse(S.save())
        self.assertEqual(self.files(), good, 'a failed save changed the files')
        self.g.CORRUPT_WRITE, self.g.WRITE_FAIL = True, False
        self.assertFalse(S.save(), 'unreadable write accepted')
        self.assertFalse(S.blocked)
        self.g.CORRUPT_WRITE = False
        gen = S.generation
        self.assertTrue(S.save())
        self.assertEqual(S.generation, gen + 1)
        self.assertEqual(S.failures, 0)
        self.assertFalse(S.dirty)
        self.assertTrue(any('recovered' in p for p in self.g.PRINTS.values()))
        # Restart: the last good generation is read back.
        rt2 = runtime()
        for k, v in self.files().items(): rt2.globals().FILES[k] = v
        S2 = rt2.eval("require('RadioSurvivor/RS_State')")
        self.assertTrue(S2.init(False))
        self.assertEqual(S2.data.note, 'second')

    def test_schema_upgrade_and_newer_schema_blocked(self):
        S = self.S
        self.assertTrue(S.init(False))
        # A v2 file read after a (test) move to v3.
        self.rt.execute('''
            local S = require('RadioSurvivor/RS_State')
            S.SCHEMA = 3
            S.MIGRATIONS[2] = function(data) data.migratedField = true end
        ''')
        self.assertTrue(S.init(False))
        self.assertEqual(S.data.schema, 3)
        self.assertTrue(S.data.migratedField)
        self.rt.execute("require('RadioSurvivor/RS_State').SCHEMA = 2")
        self.assertFalse(S.init(False), 'newer schema read by older code')
        self.assertTrue(S.blocked)


class VoiceStateTests(unittest.TestCase):
    """E21-T04: the RadioSurvivor file holds the data of the voices only; the characters, fiches and bindings are the
    notebook store's (CA_NotebookStore, batman_CoreAI file), saved with it (RS_State is one of its companions)."""

    def setUp(self):
        self.rt = runtime()
        self.g = self.rt.globals()

    def decoded(self, prefix):
        """Content and header of the last slot written among the files of this prefix."""
        slots = [text.split('\n') for path, text in self.g.FILES.items() if path.startswith(prefix)]
        if not slots:
            return None, None
        lines = max(slots, key=lambda ls: int(ls[0].split('=')[1]))
        return self.rt.eval("function(h) local C = require('CoreAI/CA_Codec') "
                            "return C.decodeBytes(C.unhexBytes(h)) end")(lines[1]), lines[0]

    def test_rs_file_holds_no_characters(self):
        self.rt.execute('''
            local S = require('RadioSurvivor/RS_State')
            local Store = require('CoreAI/CA_NotebookStore')
            assert(Store.init(false))
            assert(S.data and not S.blocked)
            Store.data.characters.c1 = {id = 'c1', owner = 'a', name = 'A', contacts = {}, knownMissions = {}}
            Store.data.npcs.n1 = {id = 'n1', name = 'Ruth'}
            S.data.voiceStory = {walt = 'returned'}
            assert(S.save())
        ''')
        data, header = self.decoded('batman_RadioSurvivor/state-')
        self.assertTrue(str(header).startswith('RSSTATE2='), header)
        self.assertEqual(data.schema, 2)
        self.assertEqual(data.voiceStory.walt, 'returned')
        for key in ('characters', 'npcs', 'bindings', 'missions', 'world', 'uidCounter'):
            self.assertIsNone(data[key], key)
        notebook, _ = self.decoded('batman_CoreAI/notebook-')
        self.assertEqual(notebook.characters.c1.name, 'A')
        self.assertIsNone(notebook.voiceStory)


if __name__ == '__main__':
    unittest.main()
