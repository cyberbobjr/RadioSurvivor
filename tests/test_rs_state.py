"""RS_State / RS_Codec / RS_StatePurge under Lua 5.1 (lupa): codec bounds (C18), write retry (C19), purge of dead
characters (C17), fast hex and checksum (C20). Simulated file API, NOT an in-game validation.

    python RadioSurvivor/tests/test_rs_state.py
"""
from __future__ import annotations

import unittest
from pathlib import Path

import lupa.lua51 as lua

LUA = Path(__file__).resolve().parents[1] / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'

BOOT = r'''
FILES, WRITE_FAIL, CORRUPT_WRITE, PRINTS, DAY = {}, false, false, {}, 10
local loaders = ...
isClient = function() return false end
getTimestampMs = function() return 1000 end
ZombRand = function(a) return a end
print = function(s) PRINTS[#PRINTS + 1] = tostring(s) end
getWorld = function() return {getGameMode = function() return 'Multiplayer' end, getWorld = function() return 'w' end} end
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
package.preload['RadioSurvivor/RS_Reputation'] = function() return {today = function() return DAY end} end
package.preload['RadioSurvivor/RS_LifeLog'] = function() return {get = function(cid) return LIFELOG and LIFELOG[cid] end} end
for name, src in pairs(loaders) do
    package.preload[name] = function() return assert(loadstring(src, name))() end
end
'''


def runtime():
    rt = lua.LuaRuntime(unpack_returned_tuples=True)
    loaders = rt.table_from({
        'RadioSurvivor/RS_Codec': (LUA / 'shared/RadioSurvivor/RS_Codec.lua').read_text(encoding='utf-8'),
        'RadioSurvivor/RS_State': (LUA / 'server/RadioSurvivor/RS_State.lua').read_text(encoding='utf-8'),
        'RadioSurvivor/RS_StatePurge': (LUA / 'server/RadioSurvivor/RS_StatePurge.lua').read_text(encoding='utf-8'),
    })
    rt.execute(BOOT, loaders)
    return rt


class CodecBoundsTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.C = self.rt.eval("require('RadioSurvivor/RS_Codec')")

    def test_encoder_refuses_what_the_decoder_refuses(self):
        ok, why = self.rt.execute('''
            local C = require('RadioSurvivor/RS_Codec')
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
            local C = require('RadioSurvivor/RS_Codec')
            C.MAX_NODES = 61
            local t = {}
            for i = 1, 30 do t[i] = i end
            return C.decodeBytes(C.encodeBytes(t)) ~= nil and C.lastNodes == 61
        '''))
        # Same counting with cached keys (the same key in several tables) and with the decoder.
        self.assertTrue(self.rt.execute('''
            local C = require('RadioSurvivor/RS_Codec')
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
            ok = self.rt.eval('function(v) return (pcall(require("RadioSurvivor/RS_Codec").encodeBytes, v)) end')(value)
            self.assertFalse(ok, snippet)

    def test_fast_hex_and_checksum_match_the_historical_ones(self):
        same = self.rt.execute(r'''
            local C = require('RadioSurvivor/RS_Codec')
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

    def test_over_the_bounds_never_writes_an_unreadable_file(self):
        S = self.S
        self.assertTrue(S.init(False))
        good = self.files()
        C = self.rt.eval("require('RadioSurvivor/RS_Codec')")
        C.MAX_NODES = 200
        self.rt.execute('''
            local S = require('RadioSurvivor/RS_State')
            S.data.characters.alive = {id = 'alive', owner = 'a', name = 'A', contacts = {}, knownMissions = {}}
            local hist = {}
            for i = 1, 60 do hist[i] = {text = 'line'} end
            S.data.characters.dead = {id = 'dead', owner = 'b', name = 'B', retired = true,
                contacts = {npc1 = {history = hist}}, knownMissions = {}}
        ''')
        # Reducer: the dead character is stripped, the state fits again.
        self.assertTrue(S.save())
        self.assertEqual(len(list(S.data.characters.dead.contacts.keys())), 0)
        self.assertIsNotNone(S.data.characters.alive)
        # Still too big with living data only: refused, nothing written, not blocked.
        self.rt.execute('''
            local S = require('RadioSurvivor/RS_State')
            local hist = {}
            for i = 1, 100 do hist[i] = {text = 'line'} end
            S.data.characters.alive.contacts.npc1 = {history = hist}
        ''')
        before = self.files()
        self.assertFalse(S.save())
        self.assertFalse(S.blocked)
        self.assertEqual(self.files(), before)
        self.assertEqual(len(list(S.data.characters.alive.contacts.npc1.history.keys())), 100, 'living data reduced')
        self.assertNotEqual(good, before)

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


class PurgeTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.P = self.rt.eval("require('RadioSurvivor/RS_StatePurge')")
        self.data = self.rt.execute('''
            return {characters = {
                alive = {id = 'alive', contacts = {n1 = {history = {}}}, knownMissions = {m1 = true}},
                dead = {id = 'dead', retired = true, contacts = {n1 = {history = {}}}, knownMissions = {m1 = true}},
                busy = {id = 'busy', retired = true, contacts = {}, knownMissions = {}},
            }, missions = {m1 = {participants = {busy = true}, invited = {}}}}
        ''')

    def test_dated_then_stripped_then_dropped(self):
        P, d = self.P, self.data
        self.assertTrue(P.run(d, 10))
        self.assertEqual(d.characters.dead.retiredDay, 10)
        self.assertIsNotNone(d.characters.dead.contacts.n1, 'stripped before STRIP_DAYS')
        self.assertTrue(P.run(d, 17))
        self.assertIsNone(d.characters.dead.contacts.n1)
        self.assertIsNotNone(d.characters.dead)
        self.assertFalse(P.run(d, 20))
        self.assertTrue(P.run(d, 40))
        self.assertIsNone(d.characters.dead)
        self.assertIsNotNone(d.characters.busy, 'character of an open mission dropped')
        self.assertIsNotNone(d.characters.alive.contacts.n1)
        self.assertTrue(d.characters.alive.knownMissions.m1)
        d.missions.m1 = None
        self.assertTrue(P.run(d, 40))
        self.assertIsNone(d.characters.busy)

    def test_frozen_life_log_and_reputation_keep_the_record(self):
        P, d = self.P, self.data
        self.rt.execute("LIFELOG = {dead = {dead = true}}")
        P.run(d, 1)
        P.run(d, 100)
        self.assertIsNotNone(d.characters.dead, 'record of a pending last pages dropped')
        self.rt.execute("LIFELOG = nil")
        d.reputation = self.rt.table_from({'dead': self.rt.table_from({})})
        P.run(d, 100)
        self.assertIsNotNone(d.characters.dead)
        d.reputation = None
        P.run(d, 100)
        self.assertIsNone(d.characters.dead)

    def test_daily_pass_from_save(self):
        self.rt.execute('''
            local S = require('RadioSurvivor/RS_State')
            assert(S.init(false))
            S.data.characters.dead = {id = 'dead', retired = true, retiredDay = 1, contacts = {x = {}}, knownMissions = {}}
        ''')
        S = self.rt.eval("require('RadioSurvivor/RS_State')")
        self.assertTrue(S.save())
        self.assertIsNone(S.data.characters.dead.stripped, 'second pass on the same game day')
        self.rt.globals().DAY = 11
        self.assertTrue(S.save())
        self.assertTrue(S.data.characters.dead.stripped)   # 10 days after the death
        self.rt.globals().DAY = 50
        self.assertTrue(S.save())
        self.assertIsNone(S.data.characters.dead)

    def test_batch_limit(self):
        P = self.P
        d = self.rt.execute('''
            local c = {}
            for i = 1, 120 do c['d' .. i] = {retired = true, retiredDay = 0, contacts = {x = {}}, knownMissions = {}} end
            return {characters = c, missions = {}}
        ''')
        P.run(d, 10)
        stripped = sum(1 for _k, r in d.characters.items() if r.stripped)
        self.assertEqual(stripped, P.BATCH)


if __name__ == '__main__':
    unittest.main()
