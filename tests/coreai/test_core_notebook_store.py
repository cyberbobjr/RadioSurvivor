"""CA_NotebookStore / CA_NotebookPurge (batman_CoreAI, E21-T04 slice 10) under Lua 5.1 (lupa): private state of the
notebook (characters, NPC fiches, bindings) in its own two-slot file batman_CoreAI/notebook-<hex>-<0|1>.txt (header
CANOTEBOOK1), the missions and exchange histories in their own files of the core mod, never in the notebook file; codec
bounds (C18), write retry (C19), purge of dead characters (C17) with the keepers of the mods (onPurge), companion
states of the mods saved after the notebook. Simulated file API, NOT an in-game validation. CoreAI files only.

    python RadioSurvivor/tests/coreai/test_core_notebook_store.py
"""
from __future__ import annotations

import unittest
from pathlib import Path

import lupa.lua51 as lua

CORE_LUA = Path(__file__).resolve().parents[2] / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'

BOOT = r'''
FILES, WRITE_FAIL, CORRUPT_WRITE, PRINTS, DAY, WRITES = {}, false, false, {}, 10, {}
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
        close = function()
            FILES[path] = CORRUPT_WRITE and 'garbage\n' or table.concat(buf)
            WRITES[#WRITES + 1] = path
        end}
end
getFileReader = function(path)
    local text = FILES[path]
    if not text then return nil end
    local lines = {}
    for l in text:gmatch('([^\n]*)\n') do lines[#lines + 1] = l end
    local i = 0
    return {readLine = function() i = i + 1; return lines[i] end, close = function() end}
end
REP_DATA = {}
package.preload['CoreAI/CA_Reputation'] = function() return {today = function() return DAY end, data = REP_DATA} end
for name, src in pairs(loaders) do
    if package.preload[name] == nil then
        package.preload[name] = function() return assert(loadstring(src, name))() end
    end
end
-- Decoded content of a slot file (nil when absent or unreadable).
function decoded(path)
    local text = FILES[path]
    if not text then return nil end
    local lines = {}
    for l in text:gmatch('([^\n]*)\n') do lines[#lines + 1] = l end
    local C = require('CoreAI/CA_Codec')
    local body = C.unhexBytes(lines[2] or '')
    return body and C.decodeBytes(body), lines[1]
end
'''


def runtime():
    rt = lua.LuaRuntime(unpack_returned_tuples=True)
    sources = {}
    for side in ('shared', 'server'):
        for f in (CORE_LUA / side).rglob('*.lua'):
            sources[f.relative_to(CORE_LUA / side).with_suffix('').as_posix()] = f.read_text(encoding='utf-8')
    rt.execute(BOOT, rt.table_from(sources))
    return rt


class Base(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.g = self.rt.globals()
        self.S = self.rt.eval("require('CoreAI/CA_NotebookStore')")
        self.base = self.rt.eval("require('CoreAI/CA_SlotFile').worldBase('batman_CoreAI/', 'notebook')")

    def files(self):
        return {k: v for k, v in self.g.FILES.items()}

    def slot(self, n):
        return self.base + '-' + str(n) + '.txt'


class InitTests(Base):
    def test_first_start_creates_the_notebook_file(self):
        S = self.S
        self.assertTrue(S.init(False))
        self.assertFalse(S.blocked)
        self.assertEqual(S.data.schema, 1)
        self.assertTrue(str(S.data.world).startswith('world-'))
        for key in ('characters', 'npcs', 'bindings', 'missions'):
            self.assertIsNotNone(S.data[key], key)
        self.assertTrue(str(S.run).startswith('run-'))
        data, header = self.rt.eval('decoded')(self.slot(1))
        self.assertEqual(header, 'CANOTEBOOK1=1')
        self.assertEqual(data.world, S.data.world)
        # The missions are the table of the mission store of the core mod (same table in memory).
        self.assertTrue(self.rt.eval("require('CoreAI/CA_NotebookStore').data.missions == "
                                     "require('CoreAI/CA_MissionStore').data.missions"))

    def test_restart_reads_the_saved_world_and_a_new_world_starts_empty(self):
        S = self.S
        self.assertTrue(S.init(False))
        world = S.data.world
        self.rt.execute("require('CoreAI/CA_NotebookStore').data.characters.c1 = "
                        "{id = 'c1', owner = 'a', name = 'A', contacts = {}, knownMissions = {}}")
        self.assertTrue(S.save())
        self.assertTrue(S.init(False))
        self.assertEqual(S.data.world, world)
        self.assertEqual(S.data.characters.c1.name, 'A')
        self.assertTrue(S.init(True))
        self.assertNotEqual(S.data.world, world)
        self.assertIsNone(S.data.characters.c1)

    def test_unreadable_slots_and_newer_schema_block_the_store(self):
        S = self.S
        self.assertTrue(S.init(False))
        self.assertTrue(S.save())
        for n in (0, 1):
            self.g.FILES[self.slot(n)] = 'garbage\nzz\n1\nend\n'
        kept = self.files()
        self.assertFalse(S.init(False))
        self.assertTrue(S.blocked)
        self.assertFalse(S.save())
        self.assertEqual(self.files(), kept, 'a blocked store wrote its files')
        self.assertTrue(any('STORAGE BLOCKED' in p for p in self.g.PRINTS.values()))
        # A newer schema is never read by older code.
        rt2 = runtime()
        S2 = rt2.eval("require('CoreAI/CA_NotebookStore')")
        self.assertTrue(S2.init(False))
        rt2.execute("local S = require('CoreAI/CA_NotebookStore') S.data.schema = 9 assert(S.save())")
        self.assertFalse(S2.init(False))
        self.assertTrue(S2.blocked)

    def test_two_slots_written_in_turn_and_the_last_one_read(self):
        S = self.S
        self.assertTrue(S.init(False))   # write 1 -> slot 1
        self.rt.execute("require('CoreAI/CA_NotebookStore').data.note = 'second'")
        self.assertTrue(S.save())        # write 2 -> slot 0
        self.assertEqual(self.rt.eval('decoded')(self.slot(0))[1], 'CANOTEBOOK1=2')
        self.assertEqual(self.rt.eval('decoded')(self.slot(1))[1], 'CANOTEBOOK1=1')
        self.rt.execute("require('CoreAI/CA_NotebookStore').data.note = 'third'")
        self.assertTrue(S.save())        # write 3 -> slot 1
        rt2 = runtime()
        for k, v in self.files().items():
            rt2.globals().FILES[k] = v
        S2 = rt2.eval("require('CoreAI/CA_NotebookStore')")
        self.assertTrue(S2.init(False))
        self.assertEqual(S2.data.note, 'third')
        # One slot unreadable: the other one is read.
        self.g.FILES[self.slot(1)] = 'garbage\n'
        rt3 = runtime()
        for k, v in self.files().items():
            rt3.globals().FILES[k] = v
        S3 = rt3.eval("require('CoreAI/CA_NotebookStore')")
        self.assertTrue(S3.init(False))
        self.assertEqual(S3.data.note, 'second')

    def test_missions_and_histories_never_inside_the_notebook_file(self):
        S = self.S
        self.assertTrue(S.init(False))
        self.rt.execute('''
            local S = require('CoreAI/CA_NotebookStore')
            local H = require('CoreAI/CA_History')
            S.data.missions.m1 = {id = 'm1', npc = 'n1', state = 'active', participants = {c1 = true}, invited = {}}
            S.data.npcs.n1 = {id = 'n1', name = 'Ruth'}
            S.data.characters.c1 = {id = 'c1', owner = 'a', name = 'A', knownMissions = {m1 = true},
                contacts = {n1 = {note = '', history = H.lines('c1', 'n1')}}}
            local k = S.data.characters.c1.contacts.n1
            k.history[#k.history + 1] = {id = 'h1', author = 'Ruth', text = 'Hello'}
        ''')
        self.assertTrue(S.save())
        data = self.rt.eval('decoded')(self.slot(0))[0]
        self.assertIsNone(data.missions)
        self.assertIsNone(data.characters.c1.contacts.n1.history)
        self.assertEqual(data.npcs.n1.name, 'Ruth')
        # Still in memory, and in their own files of the core mod.
        self.assertEqual(S.data.missions.m1.state, 'active')
        self.assertEqual(S.data.characters.c1.contacts.n1.history[1].text, 'Hello')
        names = list(self.g.FILES.keys())
        self.assertTrue(any(n.startswith('batman_CoreAI/missions-') for n in names), names)
        self.assertTrue(any(n.startswith('batman_CoreAI/history-') for n in names), names)
        # Restart: the history of the contact is the core history again.
        rt2 = runtime()
        for k, v in self.files().items():
            rt2.globals().FILES[k] = v
        S2 = rt2.eval("require('CoreAI/CA_NotebookStore')")
        self.assertTrue(S2.init(False))
        self.assertEqual(S2.data.characters.c1.contacts.n1.history[1].text, 'Hello')
        self.assertEqual(S2.data.missions.m1.state, 'active')

    def test_save_order_missions_history_notebook_then_companions(self):
        self.rt.execute('''
            local S = require('CoreAI/CA_NotebookStore')
            COMPANION = {loaded = nil, saved = 0, dirty = false}
            S.addCompanion({
                init = function(newWorld) COMPANION.loaded = newWorld; return true end,
                save = function() COMPANION.saved = COMPANION.saved + 1; WRITES[#WRITES + 1] = 'companion'; return true end,
                dirty = function() return COMPANION.dirty end})
        ''')
        S = self.S
        self.assertTrue(S.init(False))
        self.assertFalse(self.g.COMPANION.loaded)
        self.g.WRITES = self.rt.eval('{}')
        self.assertTrue(S.save())
        order = [w.split('/')[-1].split('-')[0] for w in self.g.WRITES.values()]
        self.assertEqual(order, ['missions', 'history', 'notebook', 'companion'])
        self.assertFalse(S.needsSave())
        self.g.COMPANION.dirty = True
        self.assertTrue(S.needsSave())
        # A companion registered after the start is loaded at once with the same world start.
        self.rt.execute('''
            LATE = nil
            require('CoreAI/CA_NotebookStore').addCompanion({init = function(newWorld) LATE = newWorld; return true end,
                save = function() return true end, dirty = function() return false end})
        ''')
        self.assertFalse(self.g.LATE)
        # A companion that cannot read its state blocks the store (one storage, as before the split).
        self.rt.execute("require('CoreAI/CA_NotebookStore').addCompanion({init = function() return false end, "
                        "save = function() return true end, dirty = function() return false end})")
        self.assertFalse(S.init(False))
        self.assertTrue(S.blocked)

    def test_uid_counts_in_the_state(self):
        S = self.S
        self.assertTrue(S.init(False))
        before = S.data.uidCounter
        a, b = S.uid('quote'), S.uid('quote')
        self.assertNotEqual(a, b)
        self.assertTrue(a.startswith('quote-'))
        self.assertEqual(S.data.uidCounter, before + 2)


class WriteTests(Base):
    def test_failed_write_is_retried_not_blocked(self):
        S = self.S
        self.assertTrue(S.init(False))
        self.rt.execute("require('CoreAI/CA_NotebookStore').data.note = 'first'")
        self.assertTrue(S.save())
        good = self.files()
        self.g.WRITE_FAIL = True
        self.rt.execute("require('CoreAI/CA_NotebookStore').data.note = 'second'")
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
        self.assertTrue(S.save())
        self.assertEqual(S.failures, 0)
        self.assertFalse(S.dirty)
        self.assertTrue(any('recovered' in p for p in self.g.PRINTS.values()))
        rt2 = runtime()
        for k, v in self.files().items():
            rt2.globals().FILES[k] = v
        S2 = rt2.eval("require('CoreAI/CA_NotebookStore')")
        self.assertTrue(S2.init(False))
        self.assertEqual(S2.data.note, 'second')

    def test_over_the_bounds_never_writes_an_unreadable_file(self):
        S = self.S
        self.assertTrue(S.init(False))
        good = self.files()
        C = self.rt.eval("require('CoreAI/CA_Codec')")
        C.MAX_NODES = 200
        self.rt.execute('''
            local S = require('CoreAI/CA_NotebookStore')
            S.data.characters.alive = {id = 'alive', owner = 'a', name = 'A', contacts = {}, knownMissions = {}}
            local missions = {}
            for i = 1, 300 do missions['m' .. i] = true end
            S.data.characters.dead = {id = 'dead', owner = 'b', name = 'B', retired = true,
                contacts = {npc1 = {}}, knownMissions = missions}
        ''')
        # Purge forced once: the dead character is stripped, the state fits again.
        self.assertTrue(S.save())
        self.assertEqual(len(list(S.data.characters.dead.contacts.keys())), 0)
        self.assertEqual(len(list(S.data.characters.dead.knownMissions.keys())), 0)
        self.assertIsNotNone(S.data.characters.alive)
        self.rt.execute('''
            local S = require('CoreAI/CA_NotebookStore')
            local missions = {}
            for i = 1, 300 do missions['m' .. i] = true end
            S.data.characters.alive.knownMissions = missions
        ''')
        before = self.files()
        self.assertFalse(S.save())
        self.assertFalse(S.blocked)
        self.assertEqual(self.files(), before)
        self.assertEqual(len(list(S.data.characters.alive.knownMissions.keys())), 300, 'living data reduced')
        self.assertNotEqual(good, before)


class PurgeTests(Base):
    def setUp(self):
        super().setUp()
        self.P = self.rt.eval("require('CoreAI/CA_NotebookPurge')")
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

    def test_a_keeper_of_a_mod_and_the_reputation_keep_the_record(self):
        P, d = self.P, self.data
        self.rt.execute("KEEP = {dead = true}")
        keepers = self.rt.execute("return {function(cid) return KEEP[cid] == true end}")
        P.run(d, 1, False, keepers)
        P.run(d, 100, False, keepers)
        self.assertIsNotNone(d.characters.dead, 'record kept by a mod dropped')
        self.rt.execute("KEEP = {}")
        self.rt.execute("REP_DATA.reputation = {dead = {}}")
        P.run(d, 100, False, keepers)
        self.assertIsNotNone(d.characters.dead)
        self.rt.execute("REP_DATA.reputation = nil")
        P.run(d, 100, False, keepers)
        self.assertIsNone(d.characters.dead)

    def test_store_keepers_registered_by_on_purge(self):
        self.rt.execute('''
            local S = require('CoreAI/CA_NotebookStore')
            assert(S.init(false))
            S.onPurge(function(cid) return cid == 'dead' end)
            S.data.characters.dead = {id = 'dead', retired = true, retiredDay = 1, stripped = true, contacts = {},
                knownMissions = {}}
        ''')
        self.g.DAY = 60
        self.assertTrue(self.S.save())
        self.assertIsNotNone(self.S.data.characters.dead)

    def test_daily_pass_from_save(self):
        self.rt.execute('''
            local S = require('CoreAI/CA_NotebookStore')
            assert(S.init(false))
            S.data.characters.dead = {id = 'dead', retired = true, retiredDay = 1, contacts = {x = {}}, knownMissions = {}}
        ''')
        S = self.S
        self.assertTrue(S.save())
        self.assertIsNone(S.data.characters.dead.stripped, 'second pass on the same game day')
        self.g.DAY = 11
        self.assertTrue(S.save())
        self.assertTrue(S.data.characters.dead.stripped)
        self.g.DAY = 50
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
