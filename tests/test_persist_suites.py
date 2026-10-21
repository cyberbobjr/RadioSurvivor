"""Suites de persistance en jeu de la campagne MP par étapes (E01-T17, autoclient.py --mp --phases) : bases
rs.mission.recover, rs.rescue.missed, lk.leave, lk.walls, rs.radiotab (before / after-reconnect / after-restart) et
lk.rejoin (before / after-reconnect2), leur fichier d'instantané (RST_Persist.lua) et la campagne mp-persist.

    python RadioSurvivor/tests/test_persist_suites.py

Doublures seulement : la reconnexion et le redémarrage réels ne se prouvent que par la campagne MP automatique
(docs/annexes/tests/tests-en-jeu.md, « Reconnexion et redémarrage du serveur »). rs.mission.recover.before / .after-restart sont
joués par le vrai moteur RST sur le banc de tests/test_mission_recover.py (redémarrage simulé : mémoire de RS_Caches
remise à zéro, sacs au sol gardés), y compris un sac en double injecté qui doit faire échouer l'étape after-restart.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'autoclient'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import autoclient  # noqa: E402

LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SUITES = LUA / 'shared' / 'RST' / 'suites'
MOD_SHARED = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / 'shared'
FILES = {
    'RS_MissionRecoverPersist.lua': {'rs.mission.recover.before': 'restart', 'rs.mission.recover.after-restart': None},
    'RS_RescuePersist.lua': {'rs.rescue.missed.before': None, 'rs.rescue.missed.after-restart': None},
    'RST_LKLeavePersist.lua': {'lk.leave.before': None, 'lk.leave.after-restart': None},
    'RST_LKWallsPersist.lua': {'lk.walls.before': None, 'lk.walls.after-reconnect': None,
                               'lk.walls.after-restart': None},
    'RST_LKRejoin.lua': {'lk.rejoin.before': None, 'lk.rejoin.after-reconnect2': None},
    'RS_RadioPersist.lua': {'rs.radiotab.before': None, 'rs.radiotab.after-reconnect': None},
    'RST_RstDisconnect.lua': {'rst.disconnect.before': None, 'rst.disconnect.slow': None,
                              'rst.disconnect.after-reconnect2': None},
}

FILE_DOUBLES = r"""
FILES = {}
getFileWriter = function(name, createIfNull, append)
    local lines = {}
    if append and FILES[name] then lines = FILES[name] end
    FILES[name] = lines
    return { writeln = function(self, line) lines[#lines + 1] = line end, close = function(self) end }
end
getFileReader = function(name, createIfNull)
    local lines = FILES[name]
    if lines == nil then return nil end
    local i = 0
    return { readLine = function(self) i = i + 1; return lines[i] end, close = function(self) end }
end
"""


def engine() -> lupa.LuaRuntime:
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.globals().next = None
    rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;{MOD_SHARED.as_posix()}/?.lua;]] .. package.path')
    rt.execute('print = function() end')
    rt.execute(FILE_DOUBLES)
    rt.execute('require "RST/RST"')
    return rt


class ListingTests(unittest.TestCase):
    """Every persistence step is declared, opt-in ("manual"), on the authority, and loads in the RST engine."""

    def test_suites_load_and_are_manual(self):
        rt = engine()
        rt.execute('isServer = function() return true end; isClient = function() return false end')
        for name in FILES:
            rt.execute(f'dofile([[{(SUITES / name).as_posix()}]])')
        listed = rt.eval('(function() local out = {} for _, s in ipairs(RST.list({ tags = "manual" }, true)) do '
                         'out[s.name] = table.concat(s.tags, ",") end return out end)()')
        for name, suites in FILES.items():
            for suite in suites:
                self.assertIn(suite, listed, f'{name}: {suite}')
                tags = set(listed[suite].split(','))
                self.assertIn('manual', tags, suite)
                self.assertIn('server', tags, suite)
                if name != 'RST_RstDisconnect.lua':   # rst.disconnect touches no world: "server" and "manual" only
                    self.assertIn('world', tags, suite)
        # never selected by a prefix: the plain base keeps its own suites only
        plain = rt.eval('(function() local out = {} for _, s in ipairs(RST.list({ suite = "lk.walls", tags = '
                        '"world" }, true)) do out[#out + 1] = s.name end return table.concat(out, ",") end)()')
        self.assertEqual(plain, '')   # RST_LKWalls.lua (the plain suite) is not loaded here

    def test_mp_persist_campaign_plan(self):
        lua = autoclient.CAMPAIGN_FILE.read_text(encoding='utf-8')
        bases = autoclient.campaign_suites(lua, 'mp-persist')
        for base in ('rs.identity', 'lk.homes', 'lk.leave', 'rs.mission.recover', 'rs.rescue.missed', 'lk.walls',
                     'rs.radiotab', 'rst.disconnect', 'lk.rejoin'):
            self.assertIn(base, bases)
        self.assertEqual(bases[-1], 'lk.rejoin')   # its before step moves the requester away: last of step 0
        declared = autoclient.declared_suite_names(autoclient.CAMPAIGN_FILE.parents[2])
        steps = autoclient.phase_plan(bases, ['reconnect2', 'reconnect', 'restart'], declared)
        # RST runs the suites of one run in their declaration order, not in the order of the list: lk.rejoin.before
        # needs its own last run (run 20261015-043927: it ran before lk.walls.before, whose wall went 100 squares north).
        self.assertEqual(steps[0][-1], ['rst.disconnect.before', 'lk.rejoin.before'])
        self.assertNotIn('lk.rejoin.before', steps[0][0])
        self.assertEqual(steps[1], [['rst.disconnect.after-reconnect2', 'lk.rejoin.after-reconnect2']])
        self.assertIn('rs.radiotab.before', steps[0][0])   # at the players' place, before lk.rejoin moves them
        self.assertEqual(steps[2], [['rs.identity.after-reconnect', 'lk.walls.after-reconnect',
                                     'rs.radiotab.after-reconnect'],
                                    ['rs.identity.before', 'lk.walls.before']])
        self.assertEqual(sorted(steps[3][0]), sorted(['rs.identity.after-restart', 'lk.homes.after-restart',
                                                      'lk.leave.after-restart', 'rs.mission.recover.after-restart',
                                                      'rs.rescue.missed.after-restart', 'lk.walls.after-restart',
                                                      'rs.reputation.after-restart']))
        self.assertFalse(autoclient.needs_bridge(None, [n for st in steps for r in st for n in r]))


class PersistFileTests(unittest.TestCase):
    """RST_Persist: snapshot written with RS_Codec, read back, refused when absent, corrupt, foreign or consumed."""

    def setUp(self):
        self.rt = engine()
        self.rt.execute('require "RST/RST_Persist"')

    def test_round_trip(self):
        self.rt.execute('OK, WHY = RST.Persist.write("x.txt", "HDR1", { id = "g-1", n = 3, at = { x = 10, y = -2 }, '
                        'list = { "a", "b" }, flag = true })')
        self.assertTrue(self.rt.eval('OK'))
        self.assertEqual(self.rt.eval('#FILES[RST.FILE_DIR .. "x.txt"]'), 4)
        self.rt.execute('D = RST.Persist.read("x.txt", "HDR1")')
        self.assertEqual(self.rt.eval('D.id .. D.n .. D.at.y .. D.list[2] .. tostring(D.flag)'), 'g-13-2btrue')

    def test_refusals(self):
        self.assertIn('run the .before suite', self.rt.eval('select(2, RST.Persist.read("none.txt", "HDR1"))'))
        self.rt.execute('RST.Persist.write("x.txt", "HDR1", { a = 1 })')
        self.assertIn('incomplete', self.rt.eval('select(2, RST.Persist.read("x.txt", "OTHER"))'))
        self.rt.execute('local l = FILES[RST.FILE_DIR .. "x.txt"]; l[3] = "0"')
        self.assertIn('corrupt', self.rt.eval('select(2, RST.Persist.read("x.txt", "HDR1"))'))
        self.rt.execute('RST.Persist.write("x.txt", "HDR1", { a = 1 }); RST.Persist.consume("x.txt")')
        self.assertIn('already used', self.rt.eval('select(2, RST.Persist.read("x.txt", "HDR1"))'))
        self.assertFalse(self.rt.eval('(RST.Persist.write("x.txt", "HDR1", 5))'))


class RecoverPersistTests(unittest.TestCase):
    """rs.mission.recover.before then .after-restart on the recover bench (simulated restart: RS_Caches memory reset,
    floor items kept)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-recover-persist-')

    def tearDown(self):
        self.tmp.cleanup()

    def bench(self):
        import test_mission_recover as tmr
        case = tmr.RecoverMissionTests()
        case.path = Path(self.tmp.name)
        sim, _, _, _ = case.recover_sim('persist')
        rt = sim.server.rt
        rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        rt.execute(FILE_DOUBLES)
        rt.execute("""
            local grid = getWorld():getMetaGrid()
            getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
                getWorld = function() return 'rstest-recover' end, getMetaGrid = function() return grid end} end
            require 'RST/RST'
            require 'RST/RST_Persist'
        """)
        rt.execute(f'dofile([[{(SUITES / "RS_MissionRecoverPersist.lua").as_posix()}]])')
        sim.server.g.loadArea(90, 0, 130, 40)
        alice = sim.server.g.PLAYERS.alice
        alice.x, alice.y, alice.z = 104.5, 14.5, 0
        return sim, alice

    def run_suite(self, sim, alice, name):
        start = sim.server.rt.eval(f'function(p) return RST.start("{name}", {{ attach = false, ctx = {{ player = p }} '
                                   '}) end')
        self.assertTrue(start(alice))
        for _ in range(400):
            if not sim.server.rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, f'{name}: run not finished')
        return {r.test: (r.status, r.message) for r in report.results.values()}

    def bags(self, sim):
        return sim.server.rt.eval('(function() local n = 0 for _, it in ipairs(RECOVER.placed) do '
                                  'if it.md and it.md.RS_Cache then n = n + 1 end end return n end)()')

    def test_before_then_after_restart(self):
        sim, alice = self.bench()
        before = self.run_suite(sim, alice, 'rs.mission.recover.before')
        self.assertEqual(list(before.values()), [('PASS', None)], before)
        self.assertEqual(self.bags(sim), 1)
        sim.server.rt.eval("require('RadioSurvivor/RS_Caches')").resetForTests()   # restart: memory lost
        after = self.run_suite(sim, alice, 'rs.mission.recover.after-restart')
        self.assertEqual(list(after.values()), [('PASS', None)], after)
        self.assertEqual(self.bags(sim), 1)   # nothing placed by the restart, the adoption or the checks
        self.assertIn('already used', sim.server.rt.eval('select(2, RST.Persist.read(RST.RecoverPersist.FILE, '
                                                         'RST.RecoverPersist.HEADER))'))

    def test_a_second_bag_fails_the_after_step(self):
        sim, alice = self.bench()
        self.run_suite(sim, alice, 'rs.mission.recover.before')
        sim.server.rt.execute("""
            local snap = RST.Persist.read(RST.RecoverPersist.FILE, RST.RecoverPersist.HEADER)
            local Caches = require 'RadioSurvivor/RS_Caches'
            local twin = Caches.make(snap.rec)
            getCell():getGridSquare(snap.rec.at.x, snap.rec.at.y, snap.rec.at.z):AddWorldInventoryItem(twin, 0.5, 0.5, 0, true)
        """)
        after = self.run_suite(sim, alice, 'rs.mission.recover.after-restart')
        status, message = next(iter(after.values()))
        self.assertEqual(status, 'FAIL', after)
        self.assertIn('marked bags after the restart', message)

    def test_the_after_step_without_snapshot_fails(self):
        sim, alice = self.bench()
        after = self.run_suite(sim, alice, 'rs.mission.recover.after-restart')
        status, message = next(iter(after.values()))
        self.assertEqual(status, 'FAIL')
        self.assertIn('run the .before suite', message)



RADIOTAB_DOUBLES = r"""
isServer = function() return true end
isClient = function() return false end
getWorld = function() return { getWorld = function() return 'rstest-radiotab' end,
    getGameMode = function() return 'Multiplayer' end } end
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
ZombRand = function(a, b) return a end
instanceof = function() return false end
STORE = { data = { characters = { ["c-a"] = {}, ["c-b"] = {} } }, dirty = false }
package.loaded["RadioSurvivor/RS_State"] = STORE
package.loaded["RadioSurvivor/RadioSurvivor_Const"] = { CMD = { HISTORY = "history" },
    isEnabled = function() return true end }
package.loaded["RadioSurvivor/RS_Personas"] = { voiceAt = function() return nil end,
    channel = function() return nil end }
local function player(name)
    local p = { name = name, hand = nil }
    function p:getUsername() return self.name end
    function p:getX() return 10 end
    function p:getY() return 10 end
    function p:getZ() return 0 end
    function p:getPrimaryHandItem() return self.hand end
    function p:setPrimaryHandItem(it) self.hand = it end
    return p
end
PA, PB = player("rs_mp1"), player("rs_mp2")
ONLINE = { PA, PB }
getOnlinePlayers = function() return { size = function() return #ONLINE end,
    get = function(_, i) return ONLINE[i + 1] end } end
BOUND = { [PA] = "c-a", [PB] = "c-b" }
RS_CarnetServer = { store = STORE, bound = BOUND }
RS_RadioServer = {}
require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
NEXT_ID = 0
RST.Fixtures.giveItem = function(t, p, ft)
    NEXT_ID = NEXT_ID + 1
    local data = { khz = 0 }
    function data:setHasBattery() end
    function data:setPower() end
    function data:setTurnedOnRaw() end
    function data:setMicIsMuted() end
    function data:setChannelRaw(k) self.khz = k end
    local item = { id = NEXT_ID, data = data, owner = p }
    function item:getID() return self.id end
    function item:getDeviceData() return self.data end
    return { item }
end
-- Radio history kept by the server double: the speaker says, every other player tuned there hears.
local function addLine(cid, khz, kind, text)
    local rec = STORE.data.characters[cid]
    rec.radio = rec.radio or { frequencies = {} }
    local f
    for _, x in ipairs(rec.radio.frequencies) do if x.khz == khz then f = x end end
    if f == nil then f = { khz = khz, lines = {} }; rec.radio.frequencies[#rec.radio.frequencies + 1] = f end
    f.lines[#f.lines + 1] = { kind = kind, text = text }
end
local function byName(n) for _, p in ipairs(ONLINE) do if p.name == n then return p end end end
CHARACTER_SEEN = {}  -- account -> character named by the history commands (a leak sets another one)
RST.Steps.ask = function(t, step, args, opts, after)
    local res = { list = {}, by = {} }
    local targets = type(opts.target) == "table" and opts.target or {}
    for _, name in ipairs(targets) do
        local p = byName(name)
        local cid = BOUND[p]
        local e = { user = name, status = "PASS" }
        if step == "rs.talk" then
            local khz = args.args.channel
            addLine(cid, khz, "said", args.args.text)
            for _, o in ipairs(ONLINE) do
                if o ~= p and o.hand and o.hand.data.khz == khz then addLine(BOUND[o], khz, "heard", args.args.text) end
            end
            e.data = { command = "accepted" }
        elseif step == "rs.history" then
            local found = {}
            for _, text in ipairs(args.texts or {}) do found[text] = {} end
            local rec = STORE.data.characters[cid] or {}
            for _, f in ipairs(rec.radio and rec.radio.frequencies or {}) do
                for _, l in ipairs(f.lines) do
                    if found[l.text] then table.insert(found[l.text], f.khz .. ":" .. l.kind) end
                end
            end
            e.data = { character = cid, characters = { CHARACTER_SEEN[name] or cid }, found = found }
        end
        res.list[#res.list + 1] = e
        res.by[name] = e
    end
    return after(t, res)
end
"""


class RadioTabPersistTests(unittest.TestCase):
    """rs.radiotab.before then .after-reconnect (E06-T05) on doubles: the radio command and the Radio tab of each
    client are simulated by a fake RST.Steps.ask over a server history double (RS_State)."""

    def setUp(self):
        self.rt = engine()
        self.rt.execute(RADIOTAB_DOUBLES)
        self.rt.execute(f'dofile([[{(SUITES / "RS_RadioPersist.lua").as_posix()}]])')

    def run_named(self, name):
        self.assertTrue(self.rt.eval(f'RST.start("{name}", {{ attach = false, ctx = {{ player = PA }} }})'))
        for _ in range(1000):
            if not self.rt.eval('RST.step()'):
                break
            self.rt.execute('CLOCK = CLOCK + 100')
        self.assertFalse(self.rt.eval('RST.running()'), f'{name}: run not finished')
        report = self.rt.eval('RST.last()')
        return list((r.status, r.message) for r in report.results.values())

    def lines(self, cid):
        return self.rt.eval(f'(function() local out = {{}} local r = STORE.data.characters["{cid}"].radio '
                            'for _, f in ipairs(r and r.frequencies or {}) do for _, l in ipairs(f.lines) do '
                            'out[#out + 1] = f.khz .. ":" .. l.kind end end table.sort(out) '
                            'return table.concat(out, ",") end)()')

    def test_before_then_after_reconnect(self):
        self.assertEqual(self.run_named('rs.radiotab.before'), [('PASS', None)])
        self.assertEqual(self.lines('c-a'), '91400:heard,91400:said')
        self.assertEqual(self.lines('c-b'), '91400:heard,91400:said,91600:said')
        self.assertEqual(self.run_named('rs.radiotab.after-reconnect'), [('PASS', None)])
        self.assertEqual(self.lines('c-a'), '')   # test lines removed at the end
        self.assertIn('already used', self.rt.eval('select(2, RST.Persist.read(RST.RadioPersist.FILE, '
                                                   'RST.RadioPersist.HEADER))'))

    def test_a_line_lost_by_the_reconnection_fails(self):
        self.run_named('rs.radiotab.before')
        self.rt.execute('table.remove(STORE.data.characters["c-b"].radio.frequencies[2].lines, 1)')
        (status, message), = self.run_named('rs.radiotab.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('after the reconnection', message)

    def test_another_character_after_the_reconnection_fails(self):
        self.run_named('rs.radiotab.before')
        self.rt.execute('BOUND[PB] = "c-a"')
        (status, message), = self.run_named('rs.radiotab.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('rs_mp2', message)

    def test_history_command_of_another_character_fails(self):
        self.run_named('rs.radiotab.before')
        self.rt.execute('CHARACTER_SEEN.rs_mp1 = "c-b"')
        (status, message), = self.run_named('rs.radiotab.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('another character', message)

    def test_private_line_of_the_other_player_fails_the_snapshot(self):
        self.rt.execute('local ask = RST.Steps.ask; RST.Steps.ask = function(t, step, args, opts, after) '
                        'if step == "rs.talk" and args.args.channel == 91600 then '
                        'PA.hand.data.khz = 91600 end return ask(t, step, args, opts, after) end')
        (status, message), = self.run_named('rs.radiotab.before')
        self.assertEqual(status, 'FAIL')
        self.assertIn('line of the other player', message)

    def test_not_bound_after_the_reconnection_fails_by_delay(self):
        self.run_named('rs.radiotab.before')
        self.rt.execute('BOUND[PB] = nil')
        (status, message), = self.run_named('rs.radiotab.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('not back and bound', message)

    def test_solo_is_an_explicit_skip(self):
        self.rt.execute('isServer = function() return false end')
        (status, message), = self.run_named('rs.radiotab.before')
        self.assertEqual(status, 'SKIP')
        self.assertIn('phased MP run only', message)


DISCONNECT_DOUBLES = r"""
isServer = function() return true end
isClient = function() return false end
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
local function player(name)
    local p = { name = name }
    function p:getUsername() return self.name end
    return p
end
PA, PB = player("rs_mp1"), player("rs_mp2")
ONLINE = { PA, PB }
getOnlinePlayers = function() return { size = function() return #ONLINE end,
    get = function(_, i) return ONLINE[i + 1] end } end
require "RST/RST"
require "RST/RST_Steps"
ARMED = {}
RST.Steps.ask = function(t, step, args, opts, after)
    local res = { list = {}, by = {} }
    for _, name in ipairs(opts.target) do
        ARMED[#ARMED + 1] = { user = name, step = step, filter = args.filter }
        local e = { user = name, status = "PASS" }
        res.list[#res.list + 1] = e
        res.by[name] = e
    end
    return after(t, res)
end
"""


class RstDisconnectTests(unittest.TestCase):
    """rst.disconnect.before, the run of client 2 (rst.disconnect.slow) cut by its disconnection, then
    .after-reconnect2 (E01-T05), on doubles: online list, fake RST.Steps.ask, RST.Server.lastResult set as S.finish
    does."""

    def setUp(self):
        self.rt = engine()
        self.rt.execute(DISCONNECT_DOUBLES)
        self.rt.execute(f'dofile([[{(SUITES / "RST_RstDisconnect.lua").as_posix()}]])')

    def run_named(self, name, who='PA', each=None, steps=2500):
        self.assertTrue(self.rt.eval(f'RST.start("{name}", {{ attach = false, ctx = {{ player = {who} }} }})'))
        for i in range(steps):
            if not self.rt.eval('RST.step()'):
                break
            self.rt.execute('CLOCK = CLOCK + 100')
            if each:
                each(i)
        self.assertFalse(self.rt.eval('RST.running()'), f'{name}: run not finished')
        return [(r.status, r.message) for r in self.rt.eval('RST.last()').results.values()]

    def cut_run(self, leave=True):
        def each(i):
            if leave and i == 5:
                self.rt.execute('ONLINE = { PA }')
        out = self.run_named('rst.disconnect.slow', 'PB', each)
        self.rt.execute('ONLINE = { PA, PB }; RST.Server = { lastResult = { report = RST.last(), written = true, '
                        'file = "batman_RadioSurvivor/tests/x-server.txt" } }')
        return out

    def test_before_cut_run_then_after_reconnect2(self):
        self.assertEqual(self.run_named('rst.disconnect.before'), [('PASS', None)])
        self.assertEqual(self.rt.eval('ARMED[1].user'), 'rs_mp2')
        self.assertEqual(self.rt.eval('ARMED[1].filter.suite'), 'rst.disconnect.slow')
        self.assertEqual([s for s, _ in self.cut_run()], ['PASS'])
        self.assertEqual(self.run_named('rst.disconnect.after-reconnect2'), [('PASS', None)])
        self.assertIn('already used', self.rt.eval('select(2, RST.Persist.read(RST.RstDisconnect.FILE, '
                                                   'RST.RstDisconnect.HEADER))'))

    def test_run_never_started_fails_after(self):
        self.run_named('rst.disconnect.before')
        self.rt.execute('RST.Server = { lastResult = { report = RST.last(), written = true } }')
        (status, message), = self.run_named('rst.disconnect.after-reconnect2')
        self.assertEqual(status, 'FAIL')
        self.assertIn('never started its run', message)

    def test_requester_that_never_leaves_fails_the_cut_run_and_after(self):
        self.run_named('rst.disconnect.before')
        (status, message), = self.cut_run(leave=False)
        self.assertEqual(status, 'FAIL')
        self.assertIn('never left', message)
        (status, message), = self.run_named('rst.disconnect.after-reconnect2')
        self.assertEqual(status, 'FAIL')
        self.assertIn('did not see it leave', message)

    def test_last_result_of_another_run_fails(self):
        self.run_named('rst.disconnect.before')
        self.cut_run()
        self.run_named('rst.disconnect.before')   # snapshot rewritten, then a later run replaces the last result
        self.rt.execute('local s = RST.Persist.read(RST.RstDisconnect.FILE, RST.RstDisconnect.HEADER); '
                        's.started, s.offline = true, true; '
                        'RST.Persist.write(RST.RstDisconnect.FILE, RST.RstDisconnect.HEADER, s); '
                        'RST.Server = { lastResult = { report = RST.last(), written = true } }')
        (status, message), = self.run_named('rst.disconnect.after-reconnect2')
        self.assertEqual(status, 'FAIL')
        self.assertIn('not the run of client', message)

    def test_cut_run_requested_by_another_account_fails(self):
        self.run_named('rst.disconnect.before')
        (status, message), = self.run_named('rst.disconnect.slow', 'PA')
        self.assertEqual(status, 'FAIL')
        self.assertIn('requester of this run', message)

    def test_solo_and_single_client_are_explicit_skips(self):
        self.rt.execute('ONLINE = { PA }')
        (status, message), = self.run_named('rst.disconnect.before')
        self.assertEqual((status, message), ('SKIP', 'no second client online (--clients 2)'))
        self.rt.execute('isServer = function() return false end')
        (status, message), = self.run_named('rst.disconnect.after-reconnect2')
        self.assertEqual(status, 'SKIP')
        self.assertIn('phased MP run', message)


def rescue_harness():
    import test_rescue_lost as trl

    class RescuePersistTests(trl.LostHarness):
        """rs.rescue.missed.before then .after-restart on the doubles of tests/test_rescue_lost.py (requester in the
        building; simulated restart: work store dropped, RS_RescueLost memory reset, zombies kept in the world)."""

        def run_named(self, name):
            self.rt.execute(trl.SuiteTests.SUITE_DOUBLES)
            self.rt.execute(FILE_DOUBLES.replace('FILES = {}', 'FILES = FILES or {}'))
            self.rt.execute("""
                local w = getWorld()
                local grid = w and w:getMetaGrid()
                getWorld = function() return { getMetaGrid = function() return grid end,
                    getWorld = function() return 'rstest-persist' end } end
                require 'RST/RST'
            """)
            self.rt.execute(f'dofile([[{(SUITES / "RS_RescuePersist.lua").as_posix()}]])')
            self.assertTrue(self.ev(f'RST.start("{name}", {{ attach = false, ctx = {{ player = ME }} }})'))
            for _ in range(600):
                if not self.ev('RST.step()'):
                    break
                self.g.CLOCK = self.g.CLOCK + 100
            report = self.ev('RST.last()')
            self.assertIsNotNone(report, 'run not finished')
            return {r.test: (r.status, r.message) for r in report.results.values()}

        def living(self):
            return [z for z in self.zombies() if not z.dead and not z.removed]

        def test_before_then_after_restart(self):
            before = self.run_named('rs.rescue.missed.before')
            self.assertEqual(list(before.values()), [('PASS', None)], before)
            n = len(self.living())
            self.assertGreaterEqual(n, 2)
            self.assertIsNone(self.ev('return STATE.data.rescues'))      # work store only: private state untouched
            self.rt.execute("require('RadioSurvivor/RS_RescueLost').resetForTests()")
            after = self.run_named('rs.rescue.missed.after-restart')
            self.assertEqual(list(after.values()), [('PASS', None)], after)
            self.assertEqual(self.living(), [])                            # removed at the end
            self.assertEqual(len(self.zombies()), n)                       # nothing placed by the after step

        def test_survivors_killed_before_the_restart_count_as_their_corpses(self):
            # Campagne MP du 2026-10-15 : les PNJ Living Knox des autres étapes, installés dans la même maison, ont
            # tué les deux zombies avant le redémarrage ; leurs cadavres marqués restent (cahier compris).
            self.run_named('rs.rescue.missed.before')
            n = len(self.living())
            for z in self.living():
                z.die(z)
            self.assertEqual(self.living(), [])
            self.rt.execute("require('RadioSurvivor/RS_RescueLost').resetForTests()")
            after = self.run_named('rs.rescue.missed.after-restart')
            self.assertEqual(list(after.values()), [('PASS', None)], after)
            self.assertEqual(len(self.zombies()), n)                       # nothing placed again
            self.assertEqual(self.corpses(), [])                           # marked corpses removed at the end

        def test_a_lost_notebook_fails_the_after_step(self):
            self.run_named('rs.rescue.missed.before')
            for z in self.living():
                z.inv.items = self.rt.eval('{}')
            after = self.run_named('rs.rescue.missed.after-restart')
            status, message = next(iter(after.values()))
            self.assertEqual(status, 'FAIL', after)
            self.assertIn('last pages after the restart', message)

    return RescuePersistTests


RescuePersistTests = rescue_harness()

if __name__ == '__main__':
    unittest.main(verbosity=1)
