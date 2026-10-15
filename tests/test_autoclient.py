"""Banc hors jeu du lanceur client automatique (E01-T14) : tools/autoclient/autoclient.py et RST_AutoClient.lua.

    python RadioSurvivor/tests/test_autoclient.py

Le pilote Lua est chargÃ© dans lupa.lua51 avec le vrai moteur RST, des doublures d'Ã©vÃ©nements, de fichiers et du menu
(MainScreen.continueLatestSave, quitToDesktop, takeScreenshot). Simulation seulement : le chargement rÃ©el de la partie,
le clic postÃ© Ã  la fenÃªtre et la sortie du jeu se valident par une exÃ©cution rÃ©elle (docs/tests-en-jeu.md).
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import time
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
DRIVER = LUA / 'client' / 'RST' / 'RST_AutoClient.lua'
SELFTEST = LUA / 'shared' / 'RST' / 'suites' / 'RST_SelfTest.lua'
sys.path.insert(0, str(ROOT / 'tools' / 'autoclient'))
import autoclient  # noqa: E402

FAKES = r"""
CLOCK = 1000
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
getTimestampMs = function() return CLOCK end
local function fakeEvent()
    local e = { handlers = {}, adds = 0 }
    e.Add = function(f) e.adds = e.adds + 1; e.handlers[#e.handlers + 1] = f end
    e.Remove = function(f)
        for i, h in ipairs(e.handlers) do if h == f then table.remove(e.handlers, i); return end end
    end
    e.fire = function(...) local copy = {} for i, h in ipairs(e.handlers) do copy[i] = h end
        for _, h in ipairs(copy) do h(...) end end
    return e
end
Events = { OnTick = fakeEvent(), OnTickEvenPaused = fakeEvent(), OnFETick = fakeEvent(), OnMainMenuEnter = fakeEvent(),
    OnGameStart = fakeEvent(), OnServerCommand = fakeEvent(), OnConnected = fakeEvent() }
isDebugEnabled = function() return true end
QUITS = 0
getCore = function() return { getVersion = function() return "42.21.0 test" end,
    quitToDesktop = function() QUITS = QUITS + 1 end } end
getActivatedMods = function() return { size = function() return 0 end, get = function() return nil end } end
getWorld = function() return { getWorld = function() return "rstest-auto" end } end
BREAK = true
UIManager = { isShowLuaDebuggerOnError = function() return BREAK end,
    setShowLuaDebuggerOnError = function(v) BREAK = v end }
getPlayer = function() return { name = "p0" } end
SHOTS = {}
takeScreenshot = function(name) SHOTS[#SHOTS + 1] = name end
LOADS = {}
MainScreen = { continueLatestSave = function(mode, save) LOADS[#LOADS + 1] = mode .. "/" .. save end }
getFileWriter = function(name, createIfNull, append)
    local full = FILE_ROOT .. "/" .. name
    mkdirs(full)
    local f = assert(io.open(full, append and "a" or "w"))
    return { writeln = function(self, line) f:write(line, "\n") end, close = function(self) f:close() end }
end
getFileReader = function(name, createIfNull)
    local f = io.open(FILE_ROOT .. "/" .. name, "r")
    if not f then return nil end
    return { readLine = function(self) return f:read("*l") end, close = function(self) f:close() end }
end
"""

COMMAND = 'token=abc123\nsave=rstest-auto\nmode=Sandbox\nsuite=rst.selftest\nstartDelaySec=2\n'


class Driver:
    """One Lua state (the game resets Lua between the menu and the game when the mod lists differ)."""

    def __init__(self, root: Path, connect_failed: bool = False):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.g.FILE_ROOT = root.as_posix()
        self.g.mkdirs = lambda full: Path(full).parent.mkdir(parents=True, exist_ok=True)
        self.rt.execute(FAKES)
        if connect_failed:
            self.rt.execute('do local e = { handlers = {} } e.Add = function(f) e.handlers[#e.handlers + 1] = f end '
                            'e.Remove = function() end e.fire = function(...) for _, h in ipairs(e.handlers) do h(...) '
                            'end end Events.OnConnectFailed = e end')
        self.rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;{(LUA / "client").as_posix()}/?.lua;]]'
                        ' .. package.path')
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SELFTEST.as_posix()}]])')
        self.rt.execute(f'dofile([[{DRIVER.as_posix()}]])')

    def lua(self, code):
        return self.rt.execute(code)

    def fire(self, event, times=1, dt=500):
        for _ in range(times):
            self.lua(f'Events.{event}.fire(); CLOCK = CLOCK + {dt}')


class DriverTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.tests = self.root / 'batman_RadioSurvivor' / 'tests'

    def tearDown(self):
        self.tmp.cleanup()

    def write_command(self, text=COMMAND):
        self.tests.mkdir(parents=True, exist_ok=True)
        (self.tests / 'autoclient.txt').write_text(text, encoding='utf-8')

    def status(self):
        p = self.tests / 'autoclient-status.txt'
        return p.read_text(encoding='utf-8').splitlines() if p.exists() else []

    def result(self):
        p = self.tests / 'autoclient-result.txt'
        return p.read_text(encoding='utf-8').splitlines() if p.exists() else []

    def test_without_command_nothing_happens(self):
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        d.lua('MainScreen.instance = {}')
        d.fire('OnFETick', 10)
        d.fire('OnGameStart')
        d.fire('OnTick', 10)
        self.assertEqual(d.lua('return #LOADS + QUITS + #Events.OnFETick.handlers + #Events.OnTick.handlers'), 0)
        self.assertFalse(self.tests.exists())
        self.assertTrue(d.lua('return BREAK'))

    def test_full_sequence_menu_load_run_result_quit(self):
        self.write_command()
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        self.assertFalse(d.lua('return BREAK'))
        d.fire('OnFETick', 3)  # no MainScreen.instance yet
        self.assertEqual(d.lua('return #LOADS'), 0)
        d.lua('MainScreen.instance = {}')
        d.fire('OnFETick', 3)  # delay of 3 s counted from the first tick with the menu
        self.assertEqual(d.lua('return #LOADS'), 0)
        d.fire('OnFETick', 6)
        self.assertEqual(d.lua('return LOADS[1]'), 'Sandbox/rstest-auto')
        self.assertEqual(d.lua('return #LOADS'), 1)
        self.assertEqual([line.split(' ')[1] for line in self.status()], ['menu', 'load'])
        self.assertEqual(autoclient.last_state('\n'.join(self.status()), 'abc123')[0], 'load')
        # the game starts in the same Lua state (no reset)
        d.fire('OnGameStart')
        d.fire('OnTick', 3)
        self.assertEqual(d.lua('return RST.running()'), False)  # startDelaySec=2
        d.fire('OnTick', 2)
        self.assertEqual(d.lua('return RST.running()'), True)
        for _ in range(200):
            if not d.lua('return RST.running()'):
                break
            d.fire('OnTick', 1, dt=100)
        d.fire('OnTick', 1)
        lines = self.result()
        self.assertTrue(autoclient.result_complete('\n'.join(lines)))
        self.assertRegex(lines[0], r'^RST-RESULT ok=(true|false) total=\d+ ')
        self.assertIn('report=batman_RadioSurvivor/tests/', lines[0])
        self.assertEqual(d.lua('return QUITS'), 0)
        d.fire('OnTickEvenPaused', 6)
        self.assertEqual(d.lua('return SHOTS[1]'), 'autoclient-abc123.png')
        self.assertEqual(d.lua('return QUITS'), 1)
        self.assertEqual([line.split(' ')[1] for line in self.status()], ['menu', 'load', 'ingame', 'run', 'done', 'quit'])

    def test_lua_reset_does_not_load_twice_and_menu_after_game_quits(self):
        self.write_command()
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        d.lua('MainScreen.instance = {}')
        d.fire('OnFETick', 10)
        self.assertEqual(d.lua('return #LOADS'), 1)
        d2 = Driver(self.root)  # new Lua state after ResetLua: OnMainMenuEnter fires again
        d2.fire('OnMainMenuEnter')
        d2.lua('MainScreen.instance = {}')
        d2.fire('OnFETick', 10)
        self.assertEqual(d2.lua('return #LOADS + QUITS'), 0)
        d2.fire('OnGameStart')
        self.assertEqual(self.status()[-1].split(' ')[1], 'ingame')
        d3 = Driver(self.root)  # back at the menu after the game: quit, never load again
        d3.fire('OnMainMenuEnter')
        self.assertEqual(d3.lua('return QUITS'), 1)
        self.assertEqual(d3.lua('return #LOADS'), 0)

    def test_save_refused_by_menu_writes_error_and_quits(self):
        self.write_command()
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        d.lua('MainScreen.instance = {}')
        d.fire('OnFETick', 10)
        d.lua('MainScreen.instance.checkSavefileModal = {}')
        d.fire('OnFETick')
        self.assertEqual(d.lua('return QUITS'), 1)
        self.assertIn('reason=the main menu refused the save', self.result()[0])
        self.assertEqual(autoclient.result_code(self.result()[0]), 2)

    def test_invalid_command_writes_reason(self):
        self.write_command('token=abc\nsave=rstest-auto\ncampaign=solo-rs\nsuite=rs.env\n')
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        self.assertIn('reason=autoclient.txt refused: exactly one of campaign= and suite=', self.result()[0])
        self.assertEqual(d.lua('return #LOADS + QUITS'), 0)

    def test_parse_tags_and_exclude(self):
        d = Driver(self.root)
        d.lua('C = RST.AutoClient.parse({ "token=a", "save=s", "suite=rs.npctalk", "tags=world", "exclude=" })')
        self.assertEqual(d.lua('return C.tags[1] .. #C.tags .. #C.exclude'), 'world10')
        d.lua('C = RST.AutoClient.parse({ "token=a", "save=s", "suite=rs.env" })')
        self.assertEqual(d.lua('return tostring(C.tags) .. tostring(C.exclude)'), 'nilnil')
        d.lua('C, W = RST.AutoClient.parse({ "token=a", "save=s", "campaign=solo-rs", "tags=world" })')
        self.assertEqual(d.lua('return W'), 'tags= and exclude= need suite=')

    def test_world_suite_runs_with_tags(self):
        self.write_command('token=abc\nsave=rstest-auto\nsuite=rst.selftest\ntags=nosuchtag\nstartDelaySec=0\n'
                           'screenshot=false\n')
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        d.lua('MainScreen.instance = {}')
        d.fire('OnFETick', 10)
        d.fire('OnGameStart')
        for _ in range(50):
            d.fire('OnTick', 1, dt=100)
        d.fire('OnTickEvenPaused', 4)
        self.assertIn('reason=no test selected', self.result()[0])  # the tags filter reached RST.run

    def test_unknown_campaign_fails_cleanly_in_game(self):
        self.write_command('token=abc\nsave=rstest-auto\ncampaign=nope\nstartDelaySec=0\nscreenshot=false\n')
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        d.lua('MainScreen.instance = {}')
        d.fire('OnFETick', 10)
        d.fire('OnGameStart')
        d.fire('OnTick', 2)
        d.fire('OnTickEvenPaused', 4)
        self.assertIn('reason=run not started (campaign nope)', self.result()[0])
        self.assertEqual(d.lua('return QUITS'), 1)
        self.assertEqual(d.lua('return #SHOTS'), 0)

    # ------------------------------------------------------------ multiplayer (E01-T15), simulated

    MP_COMMAND = ('token=mp1\nconnect=127.0.0.1:17391\nuser=rs_mp1\npassword=pw\ncontrol=true\n'
                  'serverSuite=rs.identity\nstartDelaySec=0\nscreenshot=false\n')

    def mp_menu(self, d):
        d.lua('''
            CONNECTS = {}
            PRESSED = {}
            local function panel(name, visible)
                return { visible = visible, getIsVisible = function(self) return self.visible end,
                    onOptionMouseDown = function(self, button) PRESSED[#PRESSED + 1] = name .. ":" .. button.internal end }
            end
            ConnectToServer = { instance = { connect = function(self, prev, srv, user, pwd, ip, lip, port, spwd, relay,
                hash, auth) CONNECTS[#CONNECTS + 1] = table.concat({ user, pwd, ip, port, tostring(hash), tostring(auth) }, "|")
                end } }
            MainScreen.instance = { bottomPanel = {}, charCreationProfession = panel("profession", false),
                charCreationMain = panel("main", false) }
            MODE = "Multiplayer"
            getWorld = function() return { getWorld = function() return "127.0.0.1_17391_x" end,
                getGameMode = function() return MODE end } end
            isClient = function() return true end
            SENT = {}
            sendClientCommand = function(p, module, command, args) SENT[#SENT + 1] = { module = module,
                command = command, args = args } end
        ''')

    def control(self, *words):
        (self.tests / 'autoclient-control.txt').write_text('\n'.join(words) + '\n', encoding='utf-8')

    def states(self):
        return [line.split(' ')[1] for line in self.status()]

    def test_mp_connect_create_run_server_report_quit(self):
        self.write_command(self.MP_COMMAND)
        d = Driver(self.root)
        d.fire('OnMainMenuEnter')
        self.mp_menu(d)
        d.fire('OnFETick', 10)
        self.assertEqual(d.lua('return CONNECTS[1]'), 'rs_mp1|pw|127.0.0.1|17391|true|1')
        self.assertEqual(d.lua('return #LOADS'), 0)
        self.assertEqual(self.states(), ['menu', 'connect'])
        # Lua reset of the connection: new state, character creation shown by vanilla OnConnected
        d2 = Driver(self.root)
        self.mp_menu(d2)
        d2.fire('OnMainMenuEnter')
        d2.fire('OnFETick', 3)
        self.assertEqual(d2.lua('return #PRESSED'), 0)
        d2.lua('MainScreen.instance.charCreationProfession.visible = true')
        d2.fire('OnFETick', 1)
        self.assertEqual(d2.lua('return PRESSED[1]'), 'profession:NEXT')
        d2.fire('OnFETick', 5)
        self.assertEqual(d2.lua('return PRESSED[2]'), 'main:NEXT')
        self.assertEqual(d2.lua('return #PRESSED'), 2)
        self.assertEqual(self.states()[-2:], ['create', 'load'])
        d2.fire('OnGameStart')
        d2.fire('OnTick', 5)
        self.assertEqual(d2.lua('return #SENT'), 0)  # waits for "go"
        self.control('go')
        d2.fire('OnTick', 3)
        self.assertEqual(d2.lua('return SENT[1].command .. " " .. SENT[1].args.filter.suite[1]'), 'run rs.identity')
        sid = d2.lua('return SENT[1].args.id')
        d2.lua(f'Events.OnServerCommand.fire("RST", "report", {{ id = {sid}, ok = true, total = 2, pass = 2, fail = 0,'
               ' error = 0, skip = 0, empty = 0, durationMs = 40, summary = "RST OK: 2/2", file = "x-server.txt",'
               ' written = true, failures = {} })')
        d2.lua(f'Events.OnServerCommand.fire("RST", "started", {{ id = {sid}, total = 2 }})')  # late: ignored
        d2.fire('OnTick', 2)
        first = self.result()[0]
        self.assertTrue(first.startswith('RST-RESULT ok=true total=2 pass=2'), first)
        self.assertIn('serverReport=x-server.txt', first)
        self.assertEqual(autoclient.result_code(first), 0)
        self.assertIn('SERVER RST OK: 2/2', self.result())
        d2.fire('OnTick', 3)
        self.assertEqual(d2.lua('return QUITS'), 0)  # waits for "quit"
        self.control('go', 'quit')
        d2.fire('OnTick', 3)
        d2.fire('OnTickEvenPaused', 4)
        self.assertEqual(d2.lua('return QUITS'), 1)
        self.assertEqual(self.states()[-4:], ['go', 'server', 'done', 'quit'])

    def test_mp_server_denied_is_reported(self):
        self.write_command(self.MP_COMMAND.replace('control=true\n', ''))
        d = Driver(self.root)
        self.mp_menu(d)
        self.status_line('connect')
        self.status_line('load')
        d.fire('OnGameStart')
        d.fire('OnTick', 2)
        sid = d.lua('return SENT[1].args.id')
        d.lua(f'Events.OnServerCommand.fire("RST", "denied", {{ id = {sid}, reason = "permission denied" }})')
        d.fire('OnTick', 2)
        d.fire('OnTickEvenPaused', 4)
        self.assertIn('reason=server run denied: permission denied', self.result()[0])
        self.assertEqual(autoclient.result_code(self.result()[0]), 2)
        self.assertEqual(d.lua('return QUITS'), 1)

    def status_line(self, state):
        self.tests.mkdir(parents=True, exist_ok=True)
        with open(self.tests / 'autoclient-status.txt', 'a', encoding='utf-8') as f:
            f.write(f'mp1 {state} test\n')

    def test_mp_idle_client_and_campaign_filter(self):
        self.write_command('token=mp1\nconnect=127.0.0.1:17391\nuser=rs_mp2\ncontrol=true\nstartDelaySec=0\n')
        d = Driver(self.root)
        self.mp_menu(d)
        self.status_line('connect')
        self.status_line('load')
        d.fire('OnGameStart')
        d.fire('OnTick', 2)
        self.assertEqual(self.states()[-1], 'ingame')
        self.control('go')
        d.fire('OnTick', 3)
        self.assertEqual(self.states()[-1], 'idle')
        self.assertEqual(self.result(), [])
        self.control('go', 'quit')
        d.fire('OnTick', 3)
        d.fire('OnTickEvenPaused', 4)
        self.assertEqual(d.lua('return QUITS'), 1)
        d.lua('RST.CAMPAIGNS = { mp = { "a", "b" } }')
        d.lua('F = RST.AutoClient.serverFilter({ serverCampaign = "mp" })')
        self.assertEqual(d.lua('return table.concat(F.suite, ",") .. "/" .. F.exclude[1]'), 'a,b/manual')
        d.lua('F, W = RST.AutoClient.serverFilter({ serverCampaign = "nope" })')
        self.assertIn('unknown or empty campaign', d.lua('return W'))

    def test_mp_peer_client_writes_the_result_of_its_steps_on_quit(self):
        # E01-T16: the second client answers steps; on "quit" it writes its result from RST.Steps.
        self.write_command('token=mp1\nconnect=127.0.0.1:17391\nuser=rs_mp2\ncontrol=true\npeer=true\n'
                           'startDelaySec=0\n')
        d = Driver(self.root)
        self.mp_menu(d)
        self.status_line('connect')
        self.status_line('load')
        d.fire('OnGameStart')
        self.control('go')
        d.fire('OnTick', 3)
        self.assertEqual(self.states()[-1], 'idle')
        d.lua('RST.Steps.records = { { seq = 1, step = "world.keys", status = "PASS", message = "1 square(s)", ms = 4 },'
              ' { seq = 2, step = "lk.look", status = "SKIP", message = "not loaded", ms = 9 } }')
        self.assertEqual(self.result(), [])
        self.control('go', 'quit')
        d.fire('OnTick', 3)
        d.fire('OnTickEvenPaused', 4)
        res = self.result()
        self.assertEqual(res[0], 'RST-RESULT ok=true total=2 pass=1 fail=0 error=0 skip=1 empty=0 durationMs=0')
        self.assertEqual(res[1], 'STEP PASS  world.keys #1 1 square(s)')
        self.assertEqual(res[-1], 'RST-END')
        self.assertEqual(autoclient.result_code(res[0]), 0)
        self.assertEqual(d.lua('return QUITS'), 1)
        d.lua('RST.Steps.records = { { seq = 3, step = "rst.request", status = "FAIL", message = "no reply", ms = 1 } }')
        first = d.lua('return (RST.AutoClient.peerResult())')
        self.assertTrue(first.startswith('RST-RESULT ok=false total=1 pass=0 fail=1'))
        self.assertEqual(autoclient.result_code(first), 1)

    def test_mp_connect_failed_and_lost_connection(self):
        self.write_command(self.MP_COMMAND)
        d = Driver(self.root, connect_failed=True)
        d.fire('OnMainMenuEnter')
        self.mp_menu(d)
        d.fire('OnFETick', 10)
        d.lua('Events.OnConnectFailed.fire("Server is full", nil)')
        self.assertIn('reason=connection refused: Server is full', self.result()[0])
        self.assertEqual(d.lua('return QUITS'), 1)
        # connection lost: the reset state comes back to the plain menu (no Multiplayer mode, no creation)
        (self.tests / 'autoclient-result.txt').unlink()
        (self.tests / 'autoclient-status.txt').write_text('mp1 connect x\n', encoding='utf-8')
        d2 = Driver(self.root)
        self.mp_menu(d2)
        d2.lua('MODE = "Sandbox"')
        d2.fire('OnMainMenuEnter')
        d2.fire('OnFETick', 50)  # 25 s on the plain menu without character creation
        self.assertIn('reason=connection lost', self.result()[0])
        self.assertEqual(d2.lua('return QUITS'), 1)

    def test_mp_parse_errors(self):
        d = Driver(self.root)
        cases = {
            'connect=127.0.0.1\nuser=a': 'connect= must be host:port',
            'connect=h:1': 'user= is needed with connect=',
            'connect=h:1\nuser=a\ncampaign=x\nsuite=y': 'at most one of campaign= and suite=',
            'connect=h:1\nuser=a\nserverSuite=x\nserverCampaign=y': 'at most one of serverCampaign= and serverSuite=',
            'save=s\nsuite=x\nserverSuite=y': 'server runs need connect=',
            'connect=h:1\nuser=a\nserverTags=world': 'serverTags= and serverExclude= need serverSuite=',
            'save=s\nsuite=x\npeer=true': 'peer= needs connect=',
            'connect=h:1\nuser=a\npeer=true\nserverSuite=x': 'peer=true is for a client without run (no suite nor campaign)',
        }
        for body, why in cases.items():
            lines = ', '.join('"' + x + '"' for x in ('token=t\n' + body).split('\n'))
            d.lua(f'C, W = RST.AutoClient.parse({{ {lines} }})')
            self.assertEqual(d.lua('return W'), why, body)
        d.lua('C = RST.AutoClient.parse({ "token=t", "connect=h:17", "user=u" })')
        self.assertEqual(d.lua('return tostring(C.idle) .. C.host .. C.port .. C.password'), 'trueh17')

    def test_no_next_no_goto_in_driver(self):
        code = re.sub(r'--\[\[.*?\]\]', '', DRIVER.read_text(encoding='utf-8'), flags=re.S)
        code = re.sub(r'--[^\n]*', '', code)
        self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code))
        self.assertIsNone(re.search(r'\bgoto\b|coroutine', code))
        self.assertTrue(all(ord(c) < 128 for c in code))


class LauncherTests(unittest.TestCase):

    def test_mods_txt_format(self):
        text = autoclient.mods_txt(['A', 'b c'])
        self.assertIn('mods\n{\n    mod = A,\n    mod = b c,\n}', text)
        self.assertTrue(text.startswith('VERSION = 1,'))

    def test_patch_options_replaces_and_adds(self):
        out = autoclient.patch_options('version=8\nfullScreen=true\nwidth=2560\nlanguage=FR\n')
        self.assertIn('fullScreen=false', out)
        self.assertIn('width=1280', out)
        self.assertIn('language=FR', out)
        self.assertIn('borderless=false', out)
        self.assertIn('height=720', out)
        self.assertEqual(out.count('width='), 1)

    def test_command_text(self):
        text = autoclient.command_text('ab12', 'rstest-x', 'Sandbox', None, ['rs.env', 'rst.guard'], 5, True, False)
        self.assertIn('suite=rs.env,rst.guard\n', text)
        self.assertIn('screenshot=false', text)
        with self.assertRaises(ValueError):
            autoclient.command_text('ab12', 's', 'Sandbox', 'solo-rs', ['x'], 5, True, True)
        with self.assertRaises(ValueError):
            autoclient.command_text('a-b', 's', 'Sandbox', 'solo-rs', None, 5, True, True)
        text = autoclient.command_text('ab12', 's', 'Sandbox', None, ['rs.npctalk'], 5, True, True, 'world', '')
        self.assertIn('tags=world\nexclude=\n', text)
        self.assertNotIn('tags=', autoclient.command_text('ab12', 's', 'Sandbox', None, ['x'], 5, True, True))
        with self.assertRaises(ValueError):
            autoclient.command_text('ab12', 's', 'Sandbox', 'solo-rs', None, 5, True, True, 'world')

    def test_last_state_and_result(self):
        status = 'abc menu x\nzzz load y\nabc load Sandbox/s\n'
        self.assertEqual(autoclient.last_state(status, 'abc'), ('load', 'Sandbox/s'))
        self.assertEqual(autoclient.last_state('', 'abc'), (None, ''))
        self.assertFalse(autoclient.result_complete('RST-RESULT ok=true total=1\n'))
        self.assertTrue(autoclient.result_complete('RST-RESULT ok=true total=1\nRST-END\n'))
        self.assertEqual(autoclient.result_code('RST-RESULT ok=true total=2 pass=2'), 0)
        self.assertEqual(autoclient.result_code('RST-RESULT ok=false total=2 pass=1 fail=1'), 1)
        self.assertEqual(autoclient.result_code('RST-RESULT ok=false total=0 reason=no test selected'), 1)
        self.assertEqual(autoclient.result_code('RST-RESULT ok=false total=0 reason=run not started'), 2)

    def test_java_command_from_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            game = Path(tmp)
            (game / 'ProjectZomboid64.json').write_text(json.dumps({
                'mainClass': 'zombie/gameStates/MainScreenState', 'classpath': ['.', 'projectzomboid.jar'],
                'windows': {'10.0.17134': {'vmArgs': ['-XX:+UseZGC']}, '6.1': {'vmArgs': ['-XX:+UseG1GC']}},
                'vmArgs': ['-Xmx3g', '-Dzomboid.steam=1']}), encoding='utf-8')
            cmd = autoclient.java_command(game, Path(r'C:\cache'))
        self.assertTrue(cmd[0].endswith('java.exe'))
        self.assertIn('-XX:+UseZGC', cmd)
        self.assertNotIn('-XX:+UseG1GC', cmd)
        self.assertNotIn('-Dzomboid.steam=1', cmd)
        self.assertIn('-Dzomboid.steam=0', cmd)
        i = cmd.index('-cp')
        self.assertEqual(cmd[i + 1:i + 3], ['.;projectzomboid.jar', 'zombie.gameStates.MainScreenState'])
        self.assertEqual(cmd[-4:], [r'-cachedir=C:\cache', '-debug', '-nosound', '-nosteam'])

    def test_latest_test_save(self):
        with tempfile.TemporaryDirectory() as tmp:
            saves = Path(tmp)
            self.assertIsNone(autoclient.latest_test_save(saves))
            for name in ('rstest-a', 'other', 'rstest-b'):
                (saves / name).mkdir()
                (saves / name / 'map_ver.bin').write_bytes(b'x')
            self.assertIn(autoclient.latest_test_save(saves), ('rstest-a', 'rstest-b'))

    def test_mod_sources_exist(self):
        for mod_id, src in autoclient.MODS:
            self.assertTrue(any((src / v / 'mod.info').exists() for v in ('42.21', '42', 'common', '.')), mod_id)


class MPLauncherTests(unittest.TestCase):
    """Multiplayer helpers of the launcher (E01-T15) and the client orchestration with simulated processes."""

    def test_mp_command_text(self):
        text = autoclient.mp_command_text('ab1', '127.0.0.1:17391', 'rs_mp1', 'pw12', suites=['rs.env'],
                                          server_suites=['lk.melee'], server_tags='world', start_delay=3)
        for part in ('connect=127.0.0.1:17391\n', 'user=rs_mp1\n', 'password=pw12\n', 'control=true\n',
                     'suite=rs.env\n', 'serverSuite=lk.melee\n', 'serverTags=world\n', 'startDelaySec=3\n'):
            self.assertIn(part, text)
        idle = autoclient.mp_command_text('ab2', 'h:1', 'rs_mp2', 'pw')
        self.assertNotIn('suite=', idle.lower().replace('serversuite', ''))
        self.assertIn('serverTimeoutSec=3600', idle)
        bad = [dict(campaign='mp', suites=['x']), dict(server_campaign='mp', server_suites=['x']),
               dict(tags='world'), dict(server_tags='world')]
        for kw in bad:
            with self.assertRaises(ValueError):
                autoclient.mp_command_text('ab', 'h:1', 'u', 'p', **kw)
        for connect, user in (('h', 'u'), ('h:1', 'a b'), ('h:1', 'a\nb')):
            with self.assertRaises(ValueError):
                autoclient.mp_command_text('ab', connect, user, 'p')

    def test_server_ini_and_commands(self):
        ini = autoclient.mp_server_ini(['TooltipLib', 'batman_RadioSurvivor'])
        for part in ('Mods=\\TooltipLib;\\batman_RadioSurvivor\n', 'SpawnPoint=10656,10137,0\n', 'Open=true\n',
                     'DefaultPort=17391\n', 'PauseEmpty=true\n', 'WorkshopItems=\n', 'AntiCheatPermission=4\n'):
            self.assertIn(part, ini)
        self.assertTrue(autoclient.MP_SERVER_NAME.lower().startswith('rstest'))
        sandbox = autoclient.mp_server_sandbox()
        self.assertIn('PopulationStartMultiplier = 0.0,', sandbox)
        self.assertIn('PopulationPeakMultiplier = 0.0,', sandbox)
        self.assertNotIn('Zombies = 6', sandbox)   # getZombiesDisabled : addZombiesInOutfit refuse hors debug
        self.assertIn('VERSION = 6,', sandbox)
        self.assertIsNone(autoclient.mp_server_sandbox(ambient_zombies=True))
        cmd = autoclient.server_java_command(Path('G'), Path(r'C:\c'), 'rs_mp1', 'pw', '2g')
        self.assertIn('zombie.network.GameServer', cmd)
        self.assertEqual(cmd[cmd.index('-servername') + 1], 'rstest_mp')
        self.assertIn('-nosteam', cmd)
        self.assertIn('-Xmx2g', cmd)
        self.assertEqual(autoclient.with_xmx(['j', '-Xmx16g', '-cp', 'x', 'M'], '4096m'),
                         ['j', '-Xmx4096m', '-cp', 'x', 'M'])
        self.assertEqual(autoclient.account_commands(['rs_mp2'], 'pw'),
                         ['adduser rs_mp2 pw', 'setaccesslevel rs_mp2 admin'])
        self.assertEqual(autoclient.account_commands([], 'pw'), [])
        self.assertEqual(autoclient.xmx_mb('4g'), 4096)
        self.assertEqual(autoclient.xmx_mb('3072m'), 3072)
        with self.assertRaises(ValueError):
            autoclient.xmx_mb('lots')
        self.assertTrue(autoclient.server_ready('x\nLOG  : Network ... server is listening on port 17391\n'))
        self.assertFalse(autoclient.server_ready('loading world'))

    def test_mp_peer_command(self):
        peer = autoclient.mp_command_text('ab2', 'h:1', 'rs_mp2', 'pw', peer=True)
        self.assertIn('peer=true\n', peer)
        self.assertNotIn('peer=', autoclient.mp_command_text('ab2', 'h:1', 'rs_mp2', 'pw'))
        with self.assertRaises(ValueError):
            autoclient.mp_command_text('ab', 'h:1', 'u', 'p', server_suites=['x'], peer=True)

    def test_mp_code(self):
        ok = 'RST-RESULT ok=true total=2 pass=2'
        self.assertEqual(autoclient.mp_code([('run', ok), ('peer', 'RST-RESULT ok=true total=0 pass=0')]), (0, ''))
        self.assertEqual(autoclient.mp_code([('run', ok), ('peer', None)]),
                         (2, 'client 2: no complete result of its steps'))
        self.assertEqual(autoclient.mp_code([('run', ok), ('peer', 'RST-RESULT ok=false total=3 fail=1')])[0], 1)
        self.assertEqual(autoclient.mp_code([('run', ok), ('idle', None)]), (0, ''))
        self.assertEqual(autoclient.mp_code([('run', None), ('idle', None)])[0], 2)
        self.assertEqual(autoclient.mp_code([('run', 'RST-RESULT ok=false total=2 fail=1')])[0], 1)

    def test_orchestration_with_simulated_clients(self):
        class FakeProc:
            def __init__(self):
                self.returncode = None
                self.pid = 0

            def poll(self):
                return self.returncode

        class FakeClient(autoclient.MPClient):
            """Writes the states a real driver would write: in game at start, result or idle on "go"."""
            starts = []

            def start(self, cmd):
                FakeClient.starts.append((self.index, [c.state for c in clients]))
                self.proc = FakeProc()
                self.status_file.parent.mkdir(parents=True, exist_ok=True)
                self.status_file.write_text(f'{self.token} ingame x\n', encoding='utf-8')

            def control(self, words):
                super().control(words)
                if 'quit' in words:
                    if self.role == 'peer':
                        self.result_file.write_text('RST-RESULT ok=true total=4 pass=4\nRST-END\n', encoding='utf-8')
                    self.proc.returncode = 0
                elif 'go' in words:
                    with open(self.status_file, 'a', encoding='utf-8') as f:
                        f.write(f'{self.token} {"done" if self.role == "run" else "idle"} x\n')
                    if self.role == 'run':
                        self.result_file.write_text('RST-RESULT ok=true total=3 pass=3\nRST-END\n', encoding='utf-8')

        class Server:
            def __init__(self):
                import io
                self.stdin = io.BytesIO()

            def poll(self):
                return None

        class Args:
            timeout, menu_timeout, godmode = 60, 60, True

        server = Server()
        with tempfile.TemporaryDirectory() as tmp:
            clients = [FakeClient(1, Path(tmp) / 'c1', 'tok1', 'rs_mp1', 'run'),
                       FakeClient(2, Path(tmp) / 'c2', 'tok2', 'rs_mp2', 'peer')]
            code, why = autoclient.run_mp_clients(clients, [['c1'], ['c2']], server, None, time.monotonic(), Args())
            self.assertEqual((code, why), (0, ''))
            self.assertEqual(server.stdin.getvalue().decode('utf-8'),
                             'godmodeplayer rs_mp1 -true\ngodmodeplayer rs_mp2 -true\n')
            # client 2 was started only once client 1 was in game; both got "go" then "quit"
            self.assertEqual(FakeClient.starts[1][0], 2)
            self.assertEqual(FakeClient.starts[1][1][0], 'ingame')
            for c in clients:
                self.assertEqual(c.control_file.read_text(encoding='utf-8'), 'go\nquit\n')
            self.assertEqual(clients[1].result_first(), 'RST-RESULT ok=true total=4 pass=4')

    def test_orchestration_fails_when_a_client_exits_without_result(self):
        class FakeProc:
            returncode, pid = 1, 0

            def poll(self):
                return 1

        class DeadClient(autoclient.MPClient):
            def start(self, cmd):
                self.proc = FakeProc()

        class Server:
            def poll(self):
                return None

        class Args:
            timeout, menu_timeout = 60, 60

        with tempfile.TemporaryDirectory() as tmp:
            clients = [DeadClient(1, Path(tmp) / 'c1', 'tok1', 'rs_mp1', 'run')]
            code, why = autoclient.run_mp_clients(clients, [['c1']], Server(), None, time.monotonic(), Args())
        self.assertEqual(code, 2)
        self.assertIn('exited (code 1)', why)


class PhaseTests(unittest.TestCase):
    """Reconnection and restart steps of the MP launcher (E01-T17): plan, commands, driver, orchestration."""

    DECLARED = {'rs.identity', 'rs.identity.before', 'rs.identity.after-reconnect', 'rs.identity.after-restart',
                'lk.homes', 'lk.homes.before', 'lk.homes.after-restart', 'x.before'}

    def test_phase_plan_runs_checks_then_a_fresh_snapshot(self):
        steps = autoclient.phase_plan(['rs.identity', 'lk.homes'], ['reconnect', 'restart'], self.DECLARED)
        self.assertEqual(steps, [
            [['rs.identity.before', 'lk.homes.before']],
            [['rs.identity.after-reconnect'], ['rs.identity.before']],   # homes: nothing after a reconnection
            [['rs.identity.after-restart', 'lk.homes.after-restart']],   # last step: no snapshot again
        ])
        self.assertEqual(autoclient.phase_plan(['lk.homes'], ['reconnect', 'restart'], self.DECLARED)[1], [])
        self.assertEqual(autoclient.phase_plan(['rs.identity'], ['restart'], self.DECLARED),
                         [[['rs.identity.before']], [['rs.identity.after-restart']]])

    def test_phase_plan_refuses_unusable_plans(self):
        for bases, phases, why in ((['nope'], ['restart'], 'no suite nope.before'),
                                   (['x'], ['restart'], 'none of x.after-restart'),
                                   (['lk.homes'], ['reconnect'], 'none of lk.homes.after-reconnect'),
                                   (['rs.identity'], ['reboot'], 'unknown phase'),
                                   (['rs.identity'], [], 'no phase'), ([], ['restart'], 'no base')):
            with self.assertRaises(ValueError) as ctx:
                autoclient.phase_plan(bases, phases, self.DECLARED)
            self.assertIn(why, str(ctx.exception))

    def test_mp_persist_campaign_is_playable(self):
        # Bases come from the real campaign (other agents add some): invariants of the plan, not a fixed list.
        lua = autoclient.CAMPAIGN_FILE.read_text(encoding='utf-8')
        bases = autoclient.campaign_suites(lua, 'mp-persist')
        self.assertEqual(len(bases), len(set(bases)), bases)
        for known in ('rs.identity', 'lk.walls', 'rs.radiotab', 'rst.disconnect', 'lk.rejoin'):
            self.assertIn(known, bases)
        self.assertEqual('lk.rejoin', bases[-1])   # its before step moves the requester away
        declared = autoclient.declared_suite_names(autoclient.CAMPAIGN_FILE.parents[2])
        phases = ['reconnect2', 'reconnect', 'restart']
        stages = ['after-' + a for a in phases]
        for base in bases:
            self.assertIn(base + '.before', declared)
            self.assertTrue(any(f'{base}.{st}' in declared for st in stages), base)
        steps = autoclient.phase_plan(bases, phases, declared)
        self.assertEqual(len(steps), len(phases) + 1)
        away = [b for b in bases if f'{b}.after-reconnect2' in declared]
        near = [b for b in bases if b not in away]
        # Step 0: every snapshot, campaign order, those checked after reconnect2 in a last, separate run.
        self.assertEqual(steps[0], [[b + '.before' for b in near], [b + '.before' for b in away]])
        self.assertEqual(steps[0][-1][-1], 'lk.rejoin.before')   # run 20261015-043927: walls placed far away otherwise
        self.assertIn('rst.disconnect.before', steps[0][-1])
        for k, stage in enumerate(stages, start=1):
            checked = [b for b in bases if f'{b}.{stage}' in declared]
            if checked:
                self.assertEqual(steps[k][0], [f'{b}.{stage}' for b in checked])
            again = [b for b in checked if any(f'{b}.{st}' in declared for st in stages[k:])]
            self.assertEqual(sum(len(r) for r in steps[k][1 if checked else 0:]), len(again), (k, steps[k]))
        self.assertEqual(steps[1][0][-1], 'lk.rejoin.after-reconnect2')   # reconnect2: lk.rejoin last
        self.assertEqual(steps[3], [[f'{b}.after-restart' for b in bases if f'{b}.after-restart' in declared]])
        # Each suite of the plan in step order: before first, then the after-* of the actions in phase order.
        seen = {}
        for k, step in enumerate(steps):
            for run in step:
                for name in run:
                    seen.setdefault(name.rsplit('.', 1)[0] if not name.endswith('.before') else name[:-7], []).append(
                        (k, name))
        for base in bases:
            order = seen[base]
            self.assertEqual(order[0], (0, base + '.before'), base)
            self.assertGreater(len(order), 1, base)
        suites = declared_suites()
        for run in (r for step in steps for r in step):
            for name in run:
                self.assertIn('manual', suites[name], name)          # opt-in: never in a plain campaign
                self.assertTrue(suites[name] & {'server', 'world'}, name)
        self.assertFalse(autoclient.needs_bridge(None, [n for st in steps for r in st for n in r]))

    def test_command_with_successive_server_runs(self):
        text = autoclient.mp_command_text('ab1p1', 'h:1', 'rs_mp1', 'pw', server_runs=[['a.after-reconnect'],
                                          ['a.before', 'b.before']], server_tags='server,shared,world',
                                          server_exclude='')
        self.assertIn('serverSuite=a.after-reconnect;a.before,b.before\n', text)
        self.assertIn('serverTags=server,shared,world\nserverExclude=\n', text)
        for bad in ([], [[]], [['a;b']], [['a b']]):
            with self.assertRaises(ValueError):
                autoclient.mp_command_text('ab', 'h:1', 'u', 'p', server_runs=bad)
        with self.assertRaises(ValueError):
            autoclient.mp_command_text('ab', 'h:1', 'u', 'p', server_runs=[['a']], server_suites=['b'])
        self.assertEqual(autoclient.phase_token('ab', 2, 0), 'abc2')
        self.assertEqual(autoclient.phase_token('ab', 2, 3), 'abc2p3')
        self.assertEqual(autoclient.admin_commands(['rs_mp2']), ['setaccesslevel rs_mp2 admin'])

    def test_archive_and_next_client_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            c = autoclient.MPClient(2, Path(tmp), 'abc2', 'rs_mp2', 'peer')
            c.result_file.parent.mkdir(parents=True)
            c.result_file.write_text('RST-RESULT ok=true total=1\nRST-END\n', encoding='utf-8')
            (Path(tmp) / 'console.txt').write_text('log', encoding='utf-8')
            c.stdout_log.write_text('out', encoding='utf-8')
            c.control(['go', 'quit'])
            c.state, c.godmode_sent = 'idle', True
            autoclient.next_client_process(c, 1, 'abc2p1', 'token=abc2p1\n', 'peer')
            tests = Path(tmp) / autoclient.TESTS_DIR
            self.assertFalse(c.result_file.exists())
            self.assertEqual((tests / 'p0-autoclient-result.txt').read_text(encoding='utf-8')[:10], 'RST-RESULT')
            self.assertTrue((tests / 'p0-console.txt').exists())
            self.assertTrue((tests / 'p0-client-stdout.log.txt').exists())
            self.assertEqual(c.control_file.read_bytes(), b'')
            self.assertEqual((tests / 'autoclient.txt').read_text(encoding='utf-8'), 'token=abc2p1\n')
            self.assertEqual((c.token, c.state, c.godmode_sent, c.proc), ('abc2p1', None, False, None))
            self.assertEqual(c.stdout_log.name, 'client-stdout-p1.log')

    def test_orchestration_reconnect_then_restart(self):
        import io

        class FakeProc:
            def __init__(self):
                self.returncode, self.pid = None, 0
                self.stdin = io.BytesIO()

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                if self.returncode is None:
                    self.returncode = 0
                return self.returncode

        events = []

        class FakeClient(autoclient.MPClient):
            def start(self, cmd):
                command = (self.cache / autoclient.TESTS_DIR / 'autoclient.txt').read_text(encoding='utf-8')
                m = re.search(r'serverSuite=(.*)', command)
                events.append(('start', self.index, self.token, m.group(1) if m else ''))
                self.proc = FakeProc()
                self.status_file.parent.mkdir(parents=True, exist_ok=True)
                with open(self.status_file, 'a', encoding='utf-8') as f:
                    f.write(f'{self.token} ingame x\n')

            def control(self, words):
                super().control(words)
                if 'quit' in words:
                    if self.role == 'peer':
                        self.result_file.write_text('RST-RESULT ok=true total=0 pass=0\nRST-END\n', encoding='utf-8')
                    self.proc.returncode = 0
                elif 'go' in words:
                    with open(self.status_file, 'a', encoding='utf-8') as f:
                        f.write(f'{self.token} {"done" if self.role == "run" else "idle"} x\n')
                    if self.role == 'run':
                        self.result_file.write_text('RST-RESULT ok=true total=2 pass=2\nRST-END\n', encoding='utf-8')

        class FakeServer(autoclient.ServerHandle):
            def launch(self, timeout):
                self.launches += 1
                self.proc = FakeProc()
                events.append(('server', self.launches))

        class Args:
            timeout, menu_timeout, godmode, quit_timeout, server_timeout, restart_pause = 60, 60, True, 5, 5, 0

        phases = ['reconnect', 'restart']
        steps = autoclient.phase_plan(['rs.identity', 'lk.homes'], phases, self.DECLARED)
        with tempfile.TemporaryDirectory() as tmp:
            clients = [FakeClient(i, Path(tmp) / f'c{i}', f'tokc{i}', f'rs_mp{i}', 'run' if i == 1 else 'peer')
                       for i in (1, 2)]

            def command_of(i, step):
                ctoken = autoclient.phase_token('tok', i, step)
                if i == 1 and steps[step]:
                    return autoclient.mp_command_text(ctoken, 'h:1', f'rs_mp{i}', 'pw', server_runs=steps[step]), \
                        'run', ctoken
                return autoclient.mp_command_text(ctoken, 'h:1', f'rs_mp{i}', 'pw', peer=True), 'peer', ctoken
            for c in clients:
                (c.cache / autoclient.TESTS_DIR).mkdir(parents=True)
                (c.cache / autoclient.TESTS_DIR / 'autoclient.txt').write_text(command_of(c.index, 0)[0],
                                                                                encoding='utf-8')
            (Path(tmp) / 'srv').mkdir()
            srv = FakeServer(['java'], Path(tmp) / 'srv')
            srv.launch(5)
            first_server = srv.proc
            code, why = autoclient.run_phases(clients, [['c1'], ['c2']], srv, None, time.monotonic(), Args(), steps,
                                              phases, command_of)
            self.assertEqual((code, why), (0, ''))
            starts = [e for e in events if e[0] == 'start']
            self.assertEqual([(e[1], e[2]) for e in starts], [(1, 'tokc1'), (2, 'tokc2'), (1, 'tokc1p1'),
                                                             (2, 'tokc2p1'), (1, 'tokc1p2'), (2, 'tokc2p2')])
            self.assertEqual([e[3] for e in starts if e[1] == 1], [
                'rs.identity.before,lk.homes.before', 'rs.identity.after-reconnect;rs.identity.before',
                'rs.identity.after-restart,lk.homes.after-restart'])
            # one relaunch of the server, after the clients of step 1 quit; "quit" on the console of the first one
            relaunch = events.index(('server', 2))
            self.assertEqual(events[relaunch + 1][:3], ('start', 1, 'tokc1p2'))
            self.assertEqual(events[relaunch - 1][:3], ('start', 2, 'tokc2p1'))
            self.assertIn(b'quit\n', first_server.stdin.getvalue())
            self.assertIn(b'setaccesslevel rs_mp2 admin\n', srv.proc.stdin.getvalue())
            tests = clients[0].cache / autoclient.TESTS_DIR
            for k in (0, 1):
                self.assertTrue((tests / f'p{k}-autoclient-result.txt').exists())
            self.assertTrue(clients[0].result_file.exists())   # result of the last step, collected as usual

    def test_orchestration_stops_when_the_restart_is_not_clean(self):
        class Proc:
            returncode, pid = None, 0

            def poll(self):
                return self.returncode

        class Srv:
            cache = Path('.')
            proc = Proc()

        def fake_run(clients, ccmds, server, bridge, started, args, keep=(), quit_wait=None):
            return 1, 'client 1: RST-RESULT ok=false'
        saved_run, saved_stop = autoclient.run_mp_clients, autoclient.stop_server
        autoclient.run_mp_clients = fake_run
        autoclient.stop_server = lambda proc, timeout: 'server still running 5 s after "quit": killed'
        try:
            class Args:
                quit_timeout, server_timeout = 5, 5
            code, why = autoclient.run_phases([], [], Srv(), None, 0.0, Args(), [[['a.before']], [['a.after-restart']]],
                                              ['restart'], None)
        finally:
            autoclient.run_mp_clients, autoclient.stop_server = saved_run, saved_stop
        self.assertEqual(code, 2)
        self.assertIn('step 0 (before): client 1', why)
        self.assertIn('restart: server still running', why)

    def test_driver_successive_server_runs_and_existing_character(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tests = root / 'batman_RadioSurvivor' / 'tests'
            tests.mkdir(parents=True)
            (tests / 'autoclient.txt').write_text(
                'token=mp1p1\nconnect=127.0.0.1:17391\nuser=rs_mp1\npassword=pw\ncontrol=true\n'
                'serverSuite=rs.identity.after-reconnect;rs.identity.before,lk.homes.before\n'
                'serverTags=server,shared,world\nserverExclude=\nstartDelaySec=0\nscreenshot=false\n', encoding='utf-8')
            d = Driver(root)
            d.lua('C = RST.AutoClient.parse({ "token=t", "connect=h:1", "user=u", "serverSuite=a;b,c" })')
            self.assertEqual(d.lua('return #C.serverRuns .. C.serverRuns[2][2] .. C.serverSuites[1]'), '2ca')
            d.lua('C, W = RST.AutoClient.parse({ "token=t", "connect=h:1", "user=u", "serverSuite=a;;b" })')
            self.assertIn('empty run', d.lua('return W'))
            DriverTests.mp_menu(None, d)
            # reconnection: Lua reset of the connection, an existing character, no creation screen
            (tests / 'autoclient-status.txt').write_text('mp1p1 menu x\nmp1p1 connect x\n', encoding='utf-8')
            d.lua('checkSavePlayerExists = function() return true end')
            d.fire('OnMainMenuEnter')
            d.fire('OnConnected')
            last = (tests / 'autoclient-status.txt').read_text(encoding='utf-8').splitlines()[-1]
            self.assertEqual(last.split(' ')[1], 'load')
            self.assertEqual(d.lua('return #Events.OnFETick.handlers'), 0)
            d.fire('OnConnected')   # once only
            self.assertEqual((tests / 'autoclient-status.txt').read_text(encoding='utf-8').count(' load '), 1)
            d.fire('OnGameStart')
            (tests / 'autoclient-control.txt').write_text('go\n', encoding='utf-8')
            d.fire('OnTick', 3)
            self.assertEqual(d.lua('return table.concat(SENT[1].args.filter.suite, ",")'), 'rs.identity.after-reconnect')
            self.assertEqual(d.lua('return table.concat(SENT[1].args.filter.tags, ",")'), 'server,shared,world')
            sid = d.lua('return SENT[1].args.id')
            d.lua(f'Events.OnServerCommand.fire("RST", "report", {{ id = {sid}, ok = true, total = 4, pass = 4, '
                  'fail = 0, error = 0, skip = 0, empty = 0, durationMs = 10, summary = "RST OK: 4/4", '
                  'file = "a-server.txt", written = true, failures = {} })')
            d.fire('OnTick', 2)
            self.assertEqual(d.lua('return #SENT'), 2)   # second run asked once the first report is in
            self.assertEqual(d.lua('return table.concat(SENT[2].args.filter.suite, ",")'),
                             'rs.identity.before,lk.homes.before')
            self.assertFalse((tests / 'autoclient-result.txt').exists())
            sid2 = d.lua('return SENT[2].args.id')
            d.lua(f'Events.OnServerCommand.fire("RST", "report", {{ id = {sid2}, ok = false, total = 2, pass = 1, '
                  'fail = 1, error = 0, skip = 0, empty = 0, durationMs = 5, summary = "RST FAIL: 1/2", '
                  'file = "b-server.txt", written = true, failures = { "FAIL lk.homes.before" } })')
            d.fire('OnTick', 2)
            res = (tests / 'autoclient-result.txt').read_text(encoding='utf-8').splitlines()
            self.assertTrue(res[0].startswith('RST-RESULT ok=false total=6 pass=5 fail=1'), res[0])
            self.assertIn('serverReport=a-server.txt,b-server.txt', res[0])
            self.assertEqual(res[1:4], ['SERVER RST OK: 4/4', 'SERVER RST FAIL: 1/2', 'SERVER FAIL lk.homes.before'])
            self.assertEqual(autoclient.result_code(res[0]), 1)

    def test_driver_new_account_ignores_on_connected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tests = root / 'batman_RadioSurvivor' / 'tests'
            tests.mkdir(parents=True)
            (tests / 'autoclient.txt').write_text('token=mp1\nconnect=h:1\nuser=u\ncontrol=true\n', encoding='utf-8')
            (tests / 'autoclient-status.txt').write_text('mp1 connect x\n', encoding='utf-8')
            d = Driver(root)
            DriverTests.mp_menu(None, d)
            d.lua('checkSavePlayerExists = function() return false end')
            d.fire('OnMainMenuEnter')
            d.fire('OnConnected')
            self.assertNotIn(' load ', (tests / 'autoclient-status.txt').read_text(encoding='utf-8'))
            self.assertEqual(d.lua('return #Events.OnFETick.handlers'), 1)   # waits for the creation screen


class Reconnect2Tests(unittest.TestCase):
    """Action reconnect2 of the phased MP run (E01-T17): client 2 alone reconnects, client 1 stays connected and
    gets the next command by "reload" (launcher and RST_AutoClient.lua)."""

    DECLARED = {'lk.rejoin.before', 'lk.rejoin.after-reconnect2', 'lk.walls.before', 'lk.walls.after-reconnect',
                'lk.walls.after-restart'}

    def test_stage_plan_and_kept_clients(self):
        self.assertEqual(autoclient.stage_of('reconnect2'), 'after-reconnect2')
        self.assertEqual(autoclient.kept_clients('reconnect2'), (1,))
        self.assertEqual((autoclient.kept_clients('reconnect'), autoclient.kept_clients('restart'),
                          autoclient.kept_clients(None)), ((), (), ()))
        steps = autoclient.phase_plan(['lk.rejoin', 'lk.walls'], ['reconnect2', 'reconnect', 'restart'],
                                      self.DECLARED)
        self.assertEqual(steps, [
            [['lk.walls.before'], ['lk.rejoin.before']],            # rejoin moves the requester away: last
            [['lk.rejoin.after-reconnect2']],                       # walls: nothing after reconnect2
            [['lk.walls.after-reconnect'], ['lk.walls.before']],    # fresh snapshot before the restart
            [['lk.walls.after-restart']],
        ])
        with self.assertRaises(ValueError):
            autoclient.phase_plan(['lk.walls'], ['reconnect2'], self.DECLARED)

    def test_reconnect2_needs_two_clients(self):
        code = autoclient.main(['--mp', '--clients', '1', '--phases', 'reconnect2', '--server-suite', 'lk.rejoin',
                                '--dry-run'])
        self.assertEqual(code, 2)

    def test_orchestration_keeps_client_1_connected(self):
        import io

        class FakeProc:
            def __init__(self):
                self.returncode, self.pid = None, 0
                self.stdin = io.BytesIO()

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                if self.returncode is None:
                    self.returncode = 0
                return self.returncode

        events = []

        class FakeClient(autoclient.MPClient):
            def start(self, cmd):
                events.append(('start', self.index, self.token))
                self.proc = FakeProc()
                self.status_file.parent.mkdir(parents=True, exist_ok=True)
                with open(self.status_file, 'a', encoding='utf-8') as f:
                    f.write(f'{self.token} ingame x\n')

            def control(self, words):
                super().control(words)
                events.append(('control', self.index, tuple(words)))
                if 'reload' in words:   # RST_AutoClient: new command read, "ingame" for the new token
                    command = (self.cache / autoclient.TESTS_DIR / 'autoclient.txt').read_text(encoding='utf-8')
                    token = re.search(r'token=(\w+)', command).group(1)
                    with open(self.status_file, 'a', encoding='utf-8') as f:
                        f.write(f'{token} ingame reload\n')
                elif 'quit' in words:
                    if self.role == 'peer':
                        self.result_file.write_text('RST-RESULT ok=true total=0 pass=0\nRST-END\n', encoding='utf-8')
                    self.proc.returncode = 0
                elif 'go' in words and not self.result_file.exists():
                    with open(self.status_file, 'a', encoding='utf-8') as f:
                        f.write(f'{self.token} {"done" if self.role == "run" else "idle"} x\n')
                    if self.role == 'run':
                        self.result_file.write_text('RST-RESULT ok=true total=1 pass=1\nRST-END\n', encoding='utf-8')

        class FakeServer(autoclient.ServerHandle):
            def launch(self, timeout):
                self.launches += 1
                self.proc = FakeProc()
                events.append(('server', self.launches))

        class Args:
            timeout, menu_timeout, godmode, quit_timeout, server_timeout, restart_pause = 60, 60, False, 5, 5, 0

        phases = ['reconnect2', 'restart']
        declared = self.DECLARED | {'lk.rejoin.after-restart'}
        steps = autoclient.phase_plan(['lk.rejoin'], phases, declared)
        with tempfile.TemporaryDirectory() as tmp:
            clients = [FakeClient(i, Path(tmp) / f'c{i}', f'tokc{i}', f'rs_mp{i}', 'run' if i == 1 else 'peer')
                       for i in (1, 2)]

            def command_of(i, step):
                ctoken = autoclient.phase_token('tok', i, step)
                if i == 1 and steps[step]:
                    return autoclient.mp_command_text(ctoken, 'h:1', f'rs_mp{i}', 'pw', server_runs=steps[step]), \
                        'run', ctoken
                return autoclient.mp_command_text(ctoken, 'h:1', f'rs_mp{i}', 'pw', peer=True), 'peer', ctoken
            for c in clients:
                (c.cache / autoclient.TESTS_DIR).mkdir(parents=True)
                (c.cache / autoclient.TESTS_DIR / 'autoclient.txt').write_text(command_of(c.index, 0)[0],
                                                                                encoding='utf-8')
            (Path(tmp) / 'srv').mkdir()
            srv = FakeServer(['java'], Path(tmp) / 'srv')
            srv.launch(5)
            code, why = autoclient.run_phases(clients, [['c1'], ['c2']], srv, None, time.monotonic(), Args(), steps,
                                              phases, command_of)
            self.assertEqual((code, why), (0, ''))
            starts = [(e[1], e[2]) for e in events if e[0] == 'start']
            # client 1 started once for steps 0 and 1 (kept), again after the restart; client 2 at every step
            self.assertEqual(starts, [(1, 'tokc1'), (2, 'tokc2'), (2, 'tokc2p1'), (1, 'tokc1p2'), (2, 'tokc2p2')])
            controls1 = [e[2] for e in events if e[0] == 'control' and e[1] == 1]
            self.assertEqual(controls1[:3], [('go',), ('go',), ('reload',)])   # step 0 ends without "quit"
            self.assertIn(('go', 'quit'), controls1[3:])                      # step 1 ends before the restart
            controls2 = [e[2] for e in events if e[0] == 'control' and e[1] == 2]
            self.assertEqual(controls2[1], ('go', 'quit'))
            tests1 = clients[0].cache / autoclient.TESTS_DIR
            self.assertTrue((tests1 / 'p0-autoclient-result.txt').exists())
            self.assertTrue((tests1 / 'p1-autoclient-result.txt').exists())
            self.assertEqual(sum(1 for e in events if e[0] == 'server'), 2)

    def test_driver_reload_starts_the_new_command_on_the_same_connection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tests = root / 'batman_RadioSurvivor' / 'tests'
            tests.mkdir(parents=True)
            base = ('connect=127.0.0.1:17391\nuser=rs_mp1\npassword=pw\ncontrol=true\nserverTags=server,shared,world\n'
                    'serverExclude=\nstartDelaySec=0\nscreenshot=false\n')
            (tests / 'autoclient.txt').write_text('token=mp1\nserverSuite=lk.rejoin.before\n' + base, encoding='utf-8')
            (tests / 'autoclient-status.txt').write_text('mp1 connect x\nmp1 load x\n', encoding='utf-8')
            d = Driver(root)
            DriverTests.mp_menu(None, d)
            d.fire('OnGameStart')

            def control(*words):
                (tests / 'autoclient-control.txt').write_text('\n'.join(words) + '\n', encoding='utf-8')
                d.lua('CLOCK = CLOCK + 2000')

            def report(n):
                sid = d.lua(f'return SENT[{n}].args.id')
                d.lua(f'Events.OnServerCommand.fire("RST", "report", {{ id = {sid}, ok = true, total = 1, pass = 1, '
                      'fail = 0, error = 0, skip = 0, empty = 0, durationMs = 5, summary = "RST OK: 1/1", '
                      f'file = "s{n}.txt", written = true, failures = {{}} }})')
            control('go')
            d.fire('OnTick', 3)
            self.assertEqual(d.lua('return SENT[1].args.filter.suite[1]'), 'lk.rejoin.before')
            report(1)
            d.fire('OnTick', 2)
            self.assertTrue((tests / 'autoclient-result.txt').read_text(encoding='utf-8').startswith(
                'RST-RESULT ok=true total=1'))
            control('go')                 # end of the step without "quit": the client stays
            d.fire('OnTick', 3)
            self.assertEqual(d.lua('return QUITS'), 0)
            control('reload')             # same token: nothing new
            d.fire('OnTick', 3)
            self.assertEqual(d.lua('return #SENT'), 1)
            (tests / 'autoclient-result.txt').unlink()
            (tests / 'autoclient.txt').write_text('token=mp1p1\nserverSuite=lk.rejoin.after-reconnect2\n' + base,
                                                  encoding='utf-8')
            control('reload')
            d.fire('OnTick', 3)
            self.assertEqual(autoclient.last_state((tests / 'autoclient-status.txt').read_text(encoding='utf-8'),
                                                   'mp1p1')[0], 'ingame')
            self.assertEqual(d.lua('return #SENT'), 1)   # waits for "go"
            control('go')
            d.fire('OnTick', 3)
            self.assertEqual(d.lua('return SENT[2].args.filter.suite[1]'), 'lk.rejoin.after-reconnect2')
            report(2)
            d.fire('OnTick', 2)
            res = (tests / 'autoclient-result.txt').read_text(encoding='utf-8').splitlines()
            self.assertTrue(res[0].startswith('RST-RESULT ok=true total=1 '), res[0])   # first run forgotten
            self.assertIn('serverReport=s2.txt', res[0])
            control('go', 'quit')
            d.fire('OnTick', 3)
            d.fire('OnTickEvenPaused', 6)
            self.assertEqual(d.lua('return QUITS'), 1)

    def test_driver_reload_refuses_an_invalid_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tests = root / 'batman_RadioSurvivor' / 'tests'
            tests.mkdir(parents=True)
            (tests / 'autoclient.txt').write_text('token=mp1\nconnect=h:1\nuser=u\ncontrol=true\npeer=true\n'
                                                  'screenshot=false\nstartDelaySec=0\n', encoding='utf-8')
            (tests / 'autoclient-status.txt').write_text('mp1 connect x\nmp1 load x\n', encoding='utf-8')
            d = Driver(root)
            DriverTests.mp_menu(None, d)
            d.fire('OnGameStart')
            (tests / 'autoclient-control.txt').write_text('go\n', encoding='utf-8')
            d.fire('OnTick', 3)
            (tests / 'autoclient.txt').write_text('token=mp1p1\nconnect=h:1\n', encoding='utf-8')   # no user=
            (tests / 'autoclient-control.txt').write_text('reload\n', encoding='utf-8')
            d.lua('CLOCK = CLOCK + 2000')
            d.fire('OnTick', 2)
            res = (tests / 'autoclient-result.txt').read_text(encoding='utf-8').splitlines()[0]
            self.assertIn('reason=reload refused', res)
            d.fire('OnTickEvenPaused', 6)
            self.assertEqual(d.lua('return QUITS'), 1)


class HomesPersistCodecTests(unittest.TestCase):
    """Snapshot of lk.homes.before / after-restart (E01-T17), encoded and decoded by the suite itself."""

    def test_round_trip_and_refusals(self):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        rt.globals().next = None
        rt.execute(f'package.path = [[{(LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        rt.execute('print = function() end; require "RST/RST"')
        rt.execute(f'dofile([[{(LUA / "shared" / "RST" / "suites" / "RST_LKHomes.lua").as_posix()}]])')
        lines = rt.execute('return table.concat(RST.LKHomesPersist.encode({ gid = "g12", home = { x = 10, y = -3, '
                           'z = 0 }, counts = { lamp = 1, bed = 6, crate = 1 } }), "|")')
        self.assertEqual(lines, 'LKHOMES1|gid=g12|home=10,-3,0|kind=bed:6|kind=crate:1|kind=lamp:1|end')
        rt.execute('S = RST.LKHomesPersist.decode({ "LKHOMES1", "gid=g12", "home=10,-3,0", "kind=bed:6", '
                   '"kind=lamp:1", "end" })')
        self.assertEqual(rt.execute('return S.gid .. S.home.y .. S.total .. S.counts.bed'), 'g12-376')
        for bad in ('{}', '{ "LKHOMES1", "gid=g", "end" }', '{ "LKHOMES1", "gid=g", "home=1,2,3", "x", "end" }',
                    '{ "consumed" }'):
            self.assertIsNone(rt.execute(f'return (RST.LKHomesPersist.decode({bad}))'), bad)
        names = [s for s in declared_suites() if s.startswith('lk.homes')]
        self.assertEqual(sorted(names), ['lk.homes', 'lk.homes.after-restart', 'lk.homes.before'])


FAKE_BRIDGE = r"""
import sys, time
mode = sys.argv[1]
if mode == 'fail':
    print('Missing configuration: OPENAI_KEY', flush=True)
    sys.exit(1)
if mode == 'ready':
    time.sleep(0.3)
    print('12:00:00 Bridge ready, model m, directory x', flush=True)
time.sleep(120)
"""


class NoEnvRead:
    """Fails the test if anything opens a file named .env while active (the tool must never read bridge/.env)."""

    def __enter__(self):
        import builtins
        import io
        self.saved = (builtins.open, io.open, Path.read_text, Path.read_bytes)

        def guard(original):
            def wrapper(file, *a, **k):
                if Path(str(file)).name == '.env':
                    raise AssertionError(f'.env opened: {file}')
                return original(file, *a, **k)
            return wrapper
        builtins.open = guard(self.saved[0])
        io.open = guard(self.saved[1])
        Path.read_text = guard(self.saved[2])
        Path.read_bytes = guard(self.saved[3])
        return self

    def __exit__(self, *exc):
        import builtins
        import io
        builtins.open, io.open, Path.read_text, Path.read_bytes = self.saved


class BridgeTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.script = self.dir / 'fake_bridge.py'
        self.script.write_text(FAKE_BRIDGE, encoding='utf-8')
        (self.dir / '.env').write_text('OPENAI_KEY=must-never-be-read\n', encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def test_needs_bridge_by_suite_and_campaign(self):
        lua = autoclient.CAMPAIGN_FILE.read_text(encoding='utf-8')
        self.assertTrue(autoclient.needs_bridge(None, ['rs.npctalk']))
        self.assertTrue(autoclient.needs_bridge(None, ['rs.radiomodule.world']))
        self.assertTrue(autoclient.needs_bridge(None, ['rs']))
        self.assertFalse(autoclient.needs_bridge(None, ['rs.env', 'rst.guard', 'rs.relationx']))
        self.assertTrue(autoclient.needs_bridge('solo-rs', None, lua))
        self.assertFalse(autoclient.needs_bridge('solo-lk', None, lua))
        self.assertTrue(autoclient.needs_bridge('solo', None, lua))
        self.assertTrue(autoclient.needs_bridge('unknown-campaign', None, lua))
        self.assertIn('rs.npctalk', autoclient.campaign_suites(lua, 'solo-rs'))
        self.assertNotIn('E01-T06', autoclient.campaign_suites(lua, 'solo-rs'))
        # E01-T16: the four notebook suites run in MP through the requester client, bridge on the server
        mp = autoclient.campaign_suites(lua, 'mp')
        for name in ('rs.npctalk', 'rs.relation', 'rs.conversations', 'rs.initiatives'):
            self.assertIn(name, mp)
        self.assertTrue(autoclient.needs_bridge('mp', None, lua))

    def test_bridge_command_uses_cache_exchange_and_no_env_option(self):
        ex = Path(r'C:\cache\Lua\batman_RadioSurvivor')
        cmd = autoclient.bridge_command('py', autoclient.BRIDGE_SCRIPT, ex)
        self.assertEqual(cmd[cmd.index('--exchange') + 1], str(ex))
        self.assertNotIn('--env', cmd)
        self.assertFalse(any('.env' in c for c in cmd))
        self.assertNotIn('--offline', cmd)
        self.assertEqual(autoclient.bridge_command('py', autoclient.BRIDGE_SCRIPT, ex, True)[-1], '--offline')
        self.assertTrue(autoclient.BRIDGE_SCRIPT.exists())

    def run_fake(self, mode, timeout=20):
        log_path = self.dir / 'bridge.log'
        with NoEnvRead():
            proc = autoclient.start_bridge([sys.executable, str(self.script), mode], log_path, self.dir)
            try:
                ok, why = autoclient.wait_bridge_ready(proc, log_path, timeout, poll=0.05)
            finally:
                autoclient.stop_bridge(proc)
        return proc, ok, why

    def test_ready_then_stopped(self):
        proc, ok, why = self.run_fake('ready')
        self.assertTrue(ok, why)
        self.assertIsNotNone(proc.poll())

    def test_bridge_exits_before_ready(self):
        proc, ok, why = self.run_fake('fail')
        self.assertFalse(ok)
        self.assertIn('exited (code 1)', why)

    def test_silent_bridge_times_out_and_is_stopped(self):
        proc, ok, why = self.run_fake('silent', timeout=1)
        self.assertFalse(ok)
        self.assertIn('no "Bridge ready"', why)
        self.assertIsNotNone(proc.poll())

    def test_stop_bridge_is_idempotent(self):
        autoclient.stop_bridge(None)
        proc, _, _ = self.run_fake('ready')
        autoclient.stop_bridge(proc)

    def test_store_bridge_log_redacts_credentials(self):
        src = self.dir / 'raw.log'
        src.write_text('API key: configured (hidden)\nModel: m\n', encoding='utf-8')
        with NoEnvRead():
            self.assertEqual(autoclient.store_bridge_log(src, self.dir / 'out'), 0)
        self.assertIn('configured (hidden)', (self.dir / 'out' / 'bridge.log').read_text(encoding='utf-8'))
        src.write_text('x sk-or-v1-abcdefghijklmnopqrstuvwxyz y\nAuthorization: Bearer abcdefghijkl\n',
                       encoding='utf-8')
        with NoEnvRead():
            self.assertGreaterEqual(autoclient.store_bridge_log(src, self.dir / 'out'), 2)
        stored = (self.dir / 'out' / 'bridge.log').read_text(encoding='utf-8')
        self.assertNotIn('abcdefghijklmnop', stored)
        self.assertIn('[REDACTED]', stored)
        self.assertEqual(autoclient.redact_secrets('a literal-value-123 b', ['literal-value-123'])[1], 1)
        self.assertEqual(autoclient.store_bridge_log(self.dir / 'absent.log', self.dir / 'out2'), 0)

    def test_tool_source_never_opens_env(self):
        code = Path(autoclient.__file__).read_text(encoding='utf-8')
        self.assertIsNone(re.search(r"""['"]\.env['"]|DEFAULT_ENV|--env""", code))


SUITES_DIR = LUA / 'shared' / 'RST' / 'suites'


def declared_suites() -> dict[str, set[str]]:
    """Name -> tags of every RST.suite declared by the development mod (RST.suite("name", { tags = { ... } }))."""
    out = {}
    for path in SUITES_DIR.glob('*.lua'):
        text = path.read_text(encoding='utf-8')
        for m in re.finditer(r'RST\.suite\(\s*"([^"]+)"\s*,\s*\{\s*tags\s*=\s*\{([^}]*)\}', text):
            out[m.group(1)] = set(re.findall(r'"([^"]+)"', m.group(2))) | (
                {'manual'} if 'EXPLICIT_TAG' in m.group(2) else set())
    return out


def selected(entry: str, suites: dict[str, set[str]]) -> list[str]:
    """Suites an entry of a campaign selects (same rule as RST.select: equal, or "<entry>." prefix; an opt-in suite,
    tag "manual" or "selfcheck", only by its exact name)."""
    return sorted(n for n in suites if n == entry or (n.startswith(entry + '.')
                                                      and not suites[n] & {'manual', 'selfcheck'}))


def on_server(tags: set[str]) -> bool:
    """Effective filter of RST_Server.lua for a campaign: tags server/shared, exclude client and manual."""
    return bool(tags & {'server', 'shared'}) and not tags & {'client', 'manual'}


class CampaignContentTests(unittest.TestCase):
    """Lists of RST_Campaign.lua (E01-T19): every entry selects real suites, the MP lists only suites the server
    keeps, the clock-moving suite last."""

    @classmethod
    def setUpClass(cls):
        cls.lua = autoclient.CAMPAIGN_FILE.read_text(encoding='utf-8')
        cls.suites = declared_suites()

    def campaign(self, name):
        names = autoclient.campaign_suites(self.lua, name)
        self.assertIsNotNone(names, name)
        return names

    def test_every_entry_selects_a_declared_suite(self):
        self.assertGreater(len(self.suites), 100)
        for name in ('solo-lk', 'solo-rs', 'solo-retry', 'mp', 'mp-ambient'):
            names = self.campaign(name)
            self.assertEqual(len(names), len(set(names)), f'{name}: duplicate entry')
            for entry in names:
                self.assertTrue(selected(entry, self.suites), f'{name}: {entry} selects no suite')

    def test_mp_entries_run_on_the_server(self):
        for name in ('mp', 'mp-ambient'):
            for entry in self.campaign(name):
                kept = [s for s in selected(entry, self.suites) if on_server(self.suites[s])]
                self.assertTrue(kept, f'{name}: {entry} selects no suite the server runs '
                                      f'({ {s: sorted(self.suites[s]) for s in selected(entry, self.suites)} })')

    def test_mp_holds_the_suites_of_e01_t19_and_the_routines_last(self):
        mp = self.campaign('mp')
        for entry in ('rs.mission', 'rs.factions.accord', 'rs.factions.incident', 'rs.trade_exchange',
                      'rs.trade_run', 'rs.groupradio', 'rs.actions.map', 'rs.actions.reveal', 'lk.traversal',
                      'lk.force', 'lk.stuck', 'lk.expedition', 'lk.meals', 'lk.forage', 'lk.repair', 'lk.milestone1',
                      'lk.essai', 'lk.equipment', 'lk.ranged', 'lk.speech', 'lk.routines'):
            self.assertIn(entry, mp)
        self.assertEqual(mp[-1], 'lk.routines')
        # "rs.missions" never selects the templates (singular): "rs.mission" does
        self.assertNotIn('rs.mission.clear', selected('rs.missions', self.suites))
        # (at least these templates; later ones, e.g. rs.mission.zones, are selected the same way)
        self.assertLessEqual({'rs.mission.clear', 'rs.mission.recover', 'rs.mission.retrieve', 'rs.mission.signal'},
                             set(selected('rs.mission', self.suites)))
        self.assertNotIn('rs.mission.nosignal', self.suites)   # 2026-10-15: Signal Smoke is a required mod
        for suite in ('rs.groupradio', 'rs.trade_run', 'lk.equipment', 'lk.ranged', 'lk.speech', 'rs.actions.map',
                      'rs.actions.reveal', 'rs.mission.signal'):
            self.assertTrue(on_server(self.suites[suite]), suite)

    def test_solo_lists_and_ambient_campaign(self):
        solo = self.campaign('solo')
        for entry in ('rs.initiatives', 'rs.conversations', 'rs.rescue', 'rs.groupradio', 'lk.revenge',
                      'lk.traversal', 'lk.upkeep'):
            self.assertIn(entry, solo)
        self.assertFalse(autoclient.needs_bridge('solo-lk', None, self.lua))
        ambient = self.campaign('mp-ambient')
        self.assertEqual(sorted(ambient), sorted(['lk.load', 'lk.zombies', 'lk.alert', 'lk.defense', 'rs.identity',
                                                  'rs.facts']))
        self.assertFalse(autoclient.needs_bridge('mp-ambient', None, self.lua))
        self.assertIn('"mp-ambient"', self.lua.split('function RST.campaigns()', 1)[1])


class LoadAndSignalSmokeTests(unittest.TestCase):
    """LK13-T02 (up to 4 clients, load campaign) and E11-T07 / E11-T13 (Signal Smoke in the campaign mods)."""

    def test_signal_smoke_always_in_the_mods_before_radio_survivor(self):
        ids = [m for m, _ in autoclient.selected_mods()]
        self.assertIn('batman_SignalSmoke', ids)
        self.assertLess(ids.index('batman_SignalSmoke'), ids.index('batman_RadioSurvivor'))
        src = dict(autoclient.MODS)['batman_SignalSmoke']
        self.assertEqual(src, ROOT.parent / 'SignalSmoke' / 'Contents' / 'mods' / 'batman_SignalSmoke')
        self.assertNotIn('108600', str(src))   # local repository, never the Steam Workshop copy
        self.assertFalse(hasattr(autoclient, 'OPTIONAL_MODS'))   # required mod: never left out
        # The id copied is the one Signal Smoke declares and RadioSurvivor requires (mod.info require=).
        info = (src / '42.21' / 'mod.info').read_text(encoding='utf-8')
        self.assertIn('id=batman_SignalSmoke', info.splitlines())
        rs_info = (ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'mod.info').read_text(
            encoding='utf-8')
        self.assertIn('require=\\batman_BeltRadio,\\batman_SignalSmoke', rs_info.splitlines())
        import contextlib
        import io
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):   # option removed
            autoclient.main(['--no-signal-smoke', '--dry-run'])
        ini = autoclient.mp_server_ini(ids)
        self.assertIn('\\batman_SignalSmoke;\\batman_RadioSurvivor', ini)

    def test_copy_uses_the_selected_mods(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp) / 'a', Path(tmp) / 'b'
            for d in (a, b):
                (d / '42.21').mkdir(parents=True)
                (d / '42.21' / 'mod.info').write_text('id=x\n', encoding='utf-8')
            cache = Path(tmp) / 'cache'
            autoclient.build_server_cache(cache, 'ini\n', mods=[('modA', a)])
            self.assertEqual(sorted(p.name for p in (cache / 'mods').iterdir()), ['modA'])

    def test_server_sandbox_group_count(self):
        both = autoclient.mp_server_sandbox(group_count=5)
        self.assertIn('PopulationStartMultiplier = 0.0,', both)
        self.assertIn('LivingKnox = {\n        GroupCount = 5,\n    },', both)
        self.assertTrue(both.rstrip().endswith('}'))
        only = autoclient.mp_server_sandbox(ambient_zombies=True, group_count=3)
        self.assertNotIn('ZombieConfig', only)
        self.assertIn('GroupCount = 3,', only)
        self.assertNotIn('LivingKnox', autoclient.mp_server_sandbox())
        self.assertIsNone(autoclient.mp_server_sandbox(ambient_zombies=True))
        for bad in (2, 6):
            with self.assertRaises(ValueError):
                autoclient.mp_server_sandbox(group_count=bad)
        # The option exists with these bounds in the mod (sandbox-options.txt).
        opts = (ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/sandbox-options.txt').read_text(encoding='utf-8')
        block = opts.split('option LivingKnox.GroupCount', 1)[1].split('}', 1)[0]
        self.assertIn('min = 3,', block)
        self.assertIn('max = 5,', block)
        # Lua syntax of the written file (a sandbox file with a syntax error is ignored by the server).
        import lupa.lua51 as lupa_mod
        rt = lupa_mod.LuaRuntime()
        rt.execute(both)
        self.assertEqual(rt.eval('SandboxVars.LivingKnox.GroupCount'), 5)
        self.assertEqual(rt.eval('SandboxVars.ZombieConfig.PopulationPeakMultiplier'), 0)

    def test_memory_estimate(self):
        self.assertEqual(autoclient.memory_need_mb(4, '4096m', '3072m'), (19456, 19456 + 4 * 1536 + 768))
        self.assertEqual(autoclient.memory_need_mb(1, '4g', '3g'), (7168, 7168 + 1536 + 768))
        with self.assertRaises(ValueError):
            autoclient.memory_need_mb(2, 'big', '3g')

    def test_clients_one_to_four(self):
        import contextlib
        import io
        with contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()):
            for bad in ('0', '5'):
                with self.assertRaises(SystemExit):
                    autoclient.main(['--mp', '--clients', bad, '--server-suite', 'x', '--dry-run'])
            # --clients, --group-count and --load are MP options.
            self.assertEqual(autoclient.main(['--suite', 'rs.env', '--clients', '2', '--dry-run']), 2)
            self.assertEqual(autoclient.main(['--suite', 'rs.env', '--load', '--dry-run']), 2)

    def test_load_preset(self):
        import argparse
        base = dict(load=True, clients=None, group_count=None, phases=None, server_suite=None, server_campaign=None,
                    server_tags=None)
        args = argparse.Namespace(**base)
        self.assertIsNone(autoclient.apply_load_preset(args, ''))
        self.assertEqual((args.clients, args.group_count, args.server_campaign, args.server_suite, args.server_tags),
                         (4, 5, None, 'lk.load', 'server'))
        args = argparse.Namespace(**base)
        autoclient.apply_load_preset(args, 'RST.CAMPAIGNS["mp-load"] = {\n    "lk.load",\n}\n')
        self.assertEqual((args.server_campaign, args.server_suite, args.server_tags), ('mp-load', None, None))
        # Explicit options win.
        args = argparse.Namespace(**dict(base, clients=2, group_count=3, server_suite='lk.load,rs.facts'))
        autoclient.apply_load_preset(args, '')
        self.assertEqual((args.clients, args.group_count, args.server_suite, args.server_tags),
                         (2, 3, 'lk.load,rs.facts', None))
        self.assertIsNotNone(autoclient.apply_load_preset(argparse.Namespace(**dict(base, phases='restart')), ''))
        plain = argparse.Namespace(**dict(base, load=False))
        autoclient.apply_load_preset(plain, '')
        self.assertEqual((plain.clients, plain.group_count, plain.server_suite), (1, None, None))

    def test_load_dry_run_prepares_four_peer_clients_and_five_groups(self):
        import contextlib
        import io
        from unittest import mock
        made = []

        def fake_copy(mods_dir, mods=autoclient.MODS):
            made.append((mods_dir, [m for m, _ in mods]))
            mods_dir.mkdir(parents=True, exist_ok=True)

        out = io.StringIO()
        with mock.patch.object(autoclient, 'copy_mods', fake_copy), contextlib.redirect_stdout(out):
            code = autoclient.main(['--mp', '--load', '--dry-run'])
        text = out.getvalue()
        self.assertEqual(code, 0, text)
        caches = [Path(line.split('=', 1)[1].split(' ', 1)[0]) for line in text.splitlines()
                  if '_CACHE=' in line]
        try:
            self.assertEqual(len(caches), 5, text)   # server + 4 clients
            self.assertIn('4 client(s) x 4096m', text)
            self.assertIn('LivingKnox = { GroupCount = 5, }', text)
            for i in (2, 3, 4):
                self.assertIn(f'(account rs_mp{i}, peer)', text)
                command = (caches[i] / autoclient.TESTS_DIR / 'autoclient.txt').read_text(encoding='utf-8')
                self.assertIn('peer=true', command)
            first = (caches[1] / autoclient.TESTS_DIR / 'autoclient.txt').read_text(encoding='utf-8')
            self.assertIn('user=rs_mp1', first)
            if 'RST.CAMPAIGNS["mp-load"]' in autoclient.read_text(autoclient.CAMPAIGN_FILE):
                self.assertIn('serverCampaign=mp-load', first)
            else:
                self.assertIn('serverSuite=lk.load', first)
                self.assertIn('serverTags=server', first)
            sandbox = (caches[0] / 'Server' / 'rstest_mp_SandboxVars.lua').read_text(encoding='utf-8')
            self.assertIn('GroupCount = 5,', sandbox)
            self.assertIn('MaxPlayers=4', (caches[0] / 'Server' / 'rstest_mp.ini').read_text(encoding='utf-8'))
            self.assertTrue(all('batman_SignalSmoke' in ids for _, ids in made), made)
            self.assertEqual(len(made), 5)
        finally:
            import shutil
            for c in caches:
                shutil.rmtree(c, ignore_errors=True)


class ParallelRunTests(unittest.TestCase):
    """Parallel launches: run slots (dead owner freed, other runs' processes not foreign), ports per slot, shards,
    fake LLM service, campaign_parallel.py (commands, merge)."""

    def test_slots_taken_released_and_freed_when_the_owner_is_dead(self):
        import json as js
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            a = autoclient.acquire_slot(2, d)
            b = autoclient.acquire_slot(2, d)
            self.assertEqual((a.index, b.index), (0, 1))
            self.assertIsNone(autoclient.acquire_slot(2, d), 'third run got a slot')
            a.add_child(4242)
            self.assertEqual(js.loads(a.path.read_text(encoding='utf-8'))['children'], [4242])
            self.assertIn(4242, autoclient.tool_pids(d))
            a.release()
            self.assertEqual(autoclient.acquire_slot(2, d).index, 0)
            # A run killed abruptly: its tool pid is dead, the slot is taken back; its children no longer excluded.
            (d / 'slot-1.json').write_text(js.dumps({'tool': 999999, 'children': [77]}), encoding='utf-8')
            self.assertNotIn(77, autoclient.tool_pids(d))
            self.assertEqual(autoclient.acquire_slot(2, d).index, 1)

    def test_pid_alive(self):
        import os
        self.assertTrue(autoclient.pid_alive(os.getpid()))
        self.assertFalse(autoclient.pid_alive(999999))
        self.assertFalse(autoclient.pid_alive(-1))

    def test_foreign_game_blocks_but_not_the_processes_of_other_runs(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(autoclient, 'game_processes', return_value=[('java.exe', 11), ('java.exe', 12)]):
            d = Path(tmp)
            other = autoclient.acquire_slot(3, d)
            other.add_child(11)
            other.add_child(12)
            slot, why = autoclient.wait_for_slot(3, 0, d, poll=0)
            self.assertIsNotNone(slot, why)
            self.assertEqual(slot.index, 1)
            autoclient.release_slot()
            with mock.patch.object(autoclient, 'game_processes', return_value=[('ProjectZomboid64.exe', 13)]):
                slot, why = autoclient.wait_for_slot(3, 0, d, poll=0)
            self.assertIsNone(slot)
            self.assertIn('ProjectZomboid64.exe (pid 13)', why)
            self.assertEqual(sorted(p.name for p in d.glob('slot-*.json')), ['slot-0.json'], 'slot kept after refusal')

    def test_ports_per_slot(self):
        self.assertEqual(autoclient.mp_ports(0, check=lambda p: True), (17391, 17392))
        self.assertEqual(autoclient.mp_ports(2, check=lambda p: True), (17411, 17412))
        taken = {17391, 17402}
        self.assertEqual(autoclient.mp_ports(0, check=lambda p: p not in taken), (17411, 17412))
        self.assertEqual(autoclient.mp_ports(5, 18000, check=lambda p: True), (18000, 18001))
        with self.assertRaises(ValueError):
            autoclient.mp_ports(0, 18000, check=lambda p: p != 18001)
        ini = autoclient.mp_server_ini(['A'], 17411, 17412)
        self.assertIn('DefaultPort=17411\n', ini)
        self.assertIn('UDPPort=17412\n', ini)

    def test_shards_cover_every_entry_once_and_are_stable(self):
        entries = ['rs.env', 'rs.codec', 'lk.load', 'lk.melee', 'rs.mission', 'lk.routines', 'lk.walls']
        for n in (1, 2, 3):
            parts = [autoclient.shard_entries(entries, k, n) for k in range(1, n + 1)]
            self.assertEqual(sorted(e for p in parts for e in p), sorted(entries))
            for p in parts:   # campaign order kept inside a shard (lk.routines stays last of its shard)
                self.assertEqual(p, [e for e in entries if e in p])
            self.assertEqual(parts, [autoclient.shard_entries(entries, k, n) for k in range(1, n + 1)])
        # Durations known: the long entries spread first.
        durations = {'lk.melee.a': 600000, 'lk.walls': 500000, 'lk.routines': 400000, 'lk.load': 300000,
                     'rs.mission.clear': 100000, 'rs.mission.signal': 50000, 'rs.codec': 100000, 'rs.env': 1000}
        parts = [autoclient.shard_entries(entries, k, 2, durations) for k in (1, 2)]
        self.assertNotEqual('lk.melee' in parts[0], 'lk.walls' in parts[0], 'the two longest entries together')
        self.assertEqual(autoclient.entry_duration('rs.mission', durations), 150000)
        self.assertEqual(autoclient.parse_shard('2/3'), (2, 3))
        for bad in ('0/3', '4/3', 'x', ''):
            with self.assertRaises(ValueError):
                autoclient.parse_shard(bad)

    def test_report_durations(self):
        with tempfile.TemporaryDirectory() as tmp:
            runs = Path(tmp)
            (runs / 'r1' / 'server').mkdir(parents=True)
            (runs / 'r1' / 'server' / 'x-server.txt').write_text(
                'RST report (x)\n\nPASS   lk.alert :: a (29393 ms)\n       note: n\nFAIL   lk.alert :: b (607 ms)\n'
                'SKIP   rs.env :: c (0 ms)\n', encoding='utf-8')
            (runs / 'r1' / 'server' / 'Logs-x.txt').write_text('PASS   lk.alert :: a (5 ms)\n', encoding='utf-8')
            self.assertEqual(autoclient.report_durations(runs), {'lk.alert': 30000, 'rs.env': 0})

    def test_apply_shard(self):
        import argparse
        lua = ('RST.CAMPAIGNS["mp"] = {\n    "rs.env",\n    "rs.codec",\n    "lk.load",\n}\n'
               'RST.CAMPAIGNS["mp-persist"] = {\n    "rs.identity",\n}\n')
        empty = Path(tempfile.mkdtemp())
        base = dict(campaign=None, suite=None, tags=None, exclude=None, server_campaign='mp', server_suite=None,
                    server_tags=None, server_exclude=None, phases=None, shard='1/2')
        args = argparse.Namespace(**base)
        self.assertIsNone(autoclient.apply_shard(args, lua, empty))
        other = argparse.Namespace(**dict(base, shard='2/2'))
        autoclient.apply_shard(other, lua, empty)
        self.assertEqual(sorted(args.server_suite.split(',') + other.server_suite.split(',')),
                         ['lk.load', 'rs.codec', 'rs.env'])
        self.assertEqual((args.server_campaign, args.server_exclude, args.server_tags), (None, 'manual', None))
        solo = argparse.Namespace(**dict(base, server_campaign=None, campaign='mp'))
        self.assertIsNone(autoclient.apply_shard(solo, lua, empty))
        self.assertEqual((solo.campaign, solo.exclude), (None, ''))
        for change in (dict(phases='restart'), dict(server_campaign='mp-persist'), dict(server_campaign='nope'),
                       dict(campaign='mp'), dict(shard='3/2'), dict(shard='9/9')):
            self.assertIsNotNone(autoclient.apply_shard(argparse.Namespace(**dict(base, **change)), lua, empty),
                                 change)

    def test_mp_dry_run_with_shard_and_port_base(self):
        import contextlib
        import io
        from unittest import mock
        out = io.StringIO()
        with mock.patch.object(autoclient, 'copy_mods', lambda d, mods=None: d.mkdir(parents=True, exist_ok=True)), \
                contextlib.redirect_stdout(out):
            code = autoclient.main(['--mp', '--server-campaign', 'mp', '--shard', '1/3', '--port-base', '18100',
                                    '--dry-run', '--bridge', 'off'])
        text = out.getvalue()
        caches = [Path(line.split('=', 1)[1].split(' ', 1)[0]) for line in text.splitlines() if '_CACHE=' in line]
        try:
            self.assertEqual(code, 0, text)
            self.assertIn('server ports 18100/18101', text)
            self.assertIn('shard 1/3 of campaign mp', text)
            command = (caches[1] / autoclient.TESTS_DIR / 'autoclient.txt').read_text(encoding='utf-8')
            self.assertIn('connect=127.0.0.1:18100', command)
            self.assertIn('serverExclude=manual', command)
            self.assertNotIn('serverCampaign', command)
            self.assertIn('DefaultPort=18100', (caches[0] / 'Server' / 'rstest_mp.ini').read_text(encoding='utf-8'))
        finally:
            import shutil
            for c in caches:
                shutil.rmtree(c, ignore_errors=True)

    def test_fake_llm_service_and_bridge_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            fake = d / 'fake_llm.py'   # minimal stand-in honouring the contract of tools/fake_llm/fake_llm.py
            fake.write_text('import sys, time\nport = sys.argv[sys.argv.index("--port") + 1]\n'
                            'print("FAKE LLM READY port=" + port, flush=True)\ntime.sleep(60)\n', encoding='utf-8')
            from unittest import mock
            with mock.patch.object(autoclient, 'FAKE_LLM_SCRIPT', fake):
                service = autoclient.LLMService('fake', d)
                env = service.start(15)
                try:
                    self.assertEqual(env, {'OPENAI_BASE_URL': f'http://127.0.0.1:{service.port}/v1',
                                           'OPENAI_MODEL': 'fake', 'OPENAI_KEY': 'fake'})
                    self.assertTrue(service.proc.poll() is None)
                finally:
                    service.stop(d / 'run')
                self.assertIsNotNone(service.proc.poll())
                self.assertIn('FAKE LLM READY', (d / 'run' / 'fake_llm.log').read_text(encoding='utf-8'))
            self.assertEqual(autoclient.LLMService('real', d).start(1), {})
            with mock.patch.object(autoclient, 'FAKE_LLM_SCRIPT', d / 'missing.py'):
                with self.assertRaises(RuntimeError):
                    autoclient.LLMService('fake', d).start(1)
            # The bridge gets the variables (its environment wins over its .env, radio_bridge.load_config).
            probe = d / 'probe.py'
            probe.write_text('import os\nprint(os.environ.get("OPENAI_BASE_URL"), os.environ.get("OPENAI_MODEL"))\n',
                             encoding='utf-8')
            proc = autoclient.start_bridge([sys.executable, str(probe)], d / 'b.log', d,
                                           autoclient.fake_llm_env(4321))
            proc.wait(timeout=30)
            self.assertIn('http://127.0.0.1:4321/v1 fake', (d / 'b.log').read_text(encoding='utf-8'))
        src = (ROOT / 'bridge' / 'radio_bridge.py').read_text(encoding='utf-8')
        self.assertIn('os.environ.get(key) or values.get(key', src)

    def test_real_fake_llm_answers_the_bridge_call(self):
        """With tools/fake_llm/fake_llm.py present: the service starts it and the bridge's model call gets a text."""
        if not autoclient.FAKE_LLM_SCRIPT.exists():
            self.skipTest('tools/fake_llm/fake_llm.py not written yet')
        sys.path.insert(0, str(ROOT / 'bridge'))
        import radio_bridge as rb
        with tempfile.TemporaryDirectory() as tmp:
            service = autoclient.LLMService('fake', Path(tmp))
            env = service.start(30)
            saved = rb.TOKEN_USAGE
            rb.TOKEN_USAGE = None
            try:
                text = rb.call_llm(env, [{'role': 'user', 'content': 'Hello Walt'}])
            finally:
                rb.TOKEN_USAGE = saved
                service.stop()
            self.assertTrue(text.strip())

    def test_campaign_parallel_commands_and_merge(self):
        import campaign_parallel as cp
        cmd = cp.shard_command('py', ['--mp', '--server-campaign', 'mp'], 2, 3, Path('o/shard2'), 3)
        self.assertEqual(cmd[-4:], ['--shard', '2/3', '--out', str(Path('o/shard2'))])
        self.assertIn('--max-parallel', cmd)
        for bad in (['--server-campaign', 'mp', '--shard', '1/2'], ['--server-campaign', 'mp', '--phases', 'restart'],
                    ['--server-suite', 'rs.env']):
            with self.assertRaises(ValueError):
                cp.shard_command('py', bad, 1, 2, Path('o'), 2)
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            for k, (first, report) in enumerate((('RST-RESULT ok=true total=3 pass=2 fail=0 error=0 skip=1', ''),
                                                 ('RST-RESULT ok=false total=4 pass=3 fail=1 error=0 skip=0',
                                                  'FAIL   lk.melee :: hit (12 ms)\n')), 1):
                (parent / f'shard{k}' / 'client1').mkdir(parents=True)
                (parent / f'shard{k}' / 'client1' / 'autoclient-result.txt').write_text(first + '\nRST-END\n',
                                                                                         encoding='utf-8')
                (parent / f'shard{k}' / 'server').mkdir()
                (parent / f'shard{k}' / 'server' / 'r-server.txt').write_text('RST report (x)\n\n' + report,
                                                                               encoding='utf-8')
            text, totals = cp.merge(parent, {1: 0, 2: 1})
            self.assertEqual(totals, {'total': 7, 'pass': 5, 'fail': 1, 'error': 0, 'skip': 1})
            self.assertIn('FAIL   lk.melee :: hit (12 ms)', text)
            self.assertIn('shard 2: exit code 1', text)

    def test_campaign_parallel_frozen_copy_commands(self):
        import campaign_parallel as cp
        wt_ac = Path('wt') / 'tools' / 'autoclient' / 'autoclient.py'
        cmd = cp.shard_command('py', ['--mp', '--server-campaign', 'mp'], 1, 2, Path('o/shard1'), 2, wt_ac)
        self.assertEqual(cmd[2], str(wt_ac))
        # one launch from the copy: phases allowed, --out set by the tool
        cmd = cp.single_command('py', ['--mp', '--phases', 'reconnect2', '--server-campaign', 'mp-persist'],
                                Path('o/run'), wt_ac)
        self.assertEqual(cmd[2:], [str(wt_ac), '--mp', '--phases', 'reconnect2', '--server-campaign', 'mp-persist',
                                   '--out', str(Path('o/run'))])
        for bad in (['--out', 'x'], ['--shard=1/2']):
            with self.assertRaises(ValueError):
                cp.single_command('py', bad, Path('o'), wt_ac)
        env = cp.copy_env(Path('W'), Path('R'))
        self.assertEqual((env['RS_WORKSHOP_DIR'], env['RS_AUTOCLIENT_RUNS']), ('W', 'R'))
        self.assertEqual(cp.WORKSHOP, ROOT.parent)
        self.assertIsNone(cp.real_model_warning(['--llm', 'fake']))
        self.assertIsNone(cp.real_model_warning(['--bridge=off']))
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            self.assertEqual(cp.worktree_dir('a' * 40, base).name, 'rs-worktree-' + 'a' * 12)
            (base / ('rs-worktree-' + 'a' * 12)).mkdir()
            self.assertEqual(cp.worktree_dir('a' * 40, base).name, 'rs-worktree-' + 'a' * 12 + '-2')
            self.assertIn('not removed', cp.remove_worktree(base / 'other'))   # never a folder of someone else
            ac = base / 'autoclient.py'
            ac.write_text("WORKSHOP_DEV = ROOT.parent\n", encoding='utf-8')
            self.assertFalse(cp.copy_supported(ac))           # commit before --commit: refused
            self.assertTrue(cp.copy_supported(Path(autoclient.__file__)))
        with self.assertRaises(ValueError):
            cp.resolve_commit('no-such-ref-xyz')
        with self.assertRaises(ValueError):
            cp.resolve_commit('--help')
        self.assertEqual(len(cp.resolve_commit('HEAD')), 40)
        # --shards or --commit needed; dry run: nothing created
        self.assertEqual(cp.main(['--', '--mp']), 2)
        before = sorted(Path(tempfile.gettempdir()).glob('rs-worktree-*'))
        self.assertEqual(cp.main(['--commit', 'HEAD', '--dry-run', '--', '--mp', '--clients', '2', '--phases',
                                  'reconnect2', '--server-campaign', 'mp-persist', '--llm', 'fake']), 0)
        self.assertEqual(sorted(Path(tempfile.gettempdir()).glob('rs-worktree-*')), before)

    def test_campaign_parallel_worktree_add_and_remove_on_a_scratch_repo(self):
        import subprocess
        import campaign_parallel as cp
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / 'repo'
            repo.mkdir()
            run = lambda *a: subprocess.run(['git', '-C', str(repo), *a], capture_output=True, text=True,  # noqa
                                            check=True)
            run('init', '-q')
            (repo / 'f.txt').write_text('v1', encoding='utf-8')
            run('add', 'f.txt')
            run('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'v1')
            sha = cp.resolve_commit('HEAD', repo)
            (repo / 'f.txt').write_text('work in progress', encoding='utf-8')   # main checkout left untouched
            with self.assertRaises(RuntimeError):
                cp.add_worktree(sha, repo / 'rs-worktree-inside', repo)
            wt = cp.worktree_dir(sha, Path(tmp))
            cp.add_worktree(sha, wt, repo)
            self.assertEqual((wt / 'f.txt').read_text(encoding='utf-8'), 'v1')
            (wt / 'scratch.pyc').write_bytes(b'x')                            # untracked file: --force
            self.assertIn('removed', cp.remove_worktree(wt, repo))
            self.assertFalse(wt.exists())
            self.assertEqual((repo / 'f.txt').read_text(encoding='utf-8'), 'work in progress')
            self.assertNotIn(str(wt.name), run('worktree', 'list').stdout)


class FrozenCopyAndRespawnTests(unittest.TestCase):
    """Launch from a frozen copy (RS_WORKSHOP_DIR, RS_AUTOCLIENT_RUNS), godmode again after a respawn, wait for the
    server line of rst.disconnect before the reconnect2 "quit"."""

    def test_workshop_and_runs_from_the_environment(self):
        import os
        import subprocess
        code = ('import sys; sys.path.insert(0, sys.argv[1]); import autoclient as a; '
                'print(a.WORKSHOP_DEV); print(a.RUNS); print(dict(a.MODS)["batman_BeltRadio"])')
        here = str(Path(autoclient.__file__).parent)
        env = dict(os.environ, RS_WORKSHOP_DIR=r'C:\W', RS_AUTOCLIENT_RUNS=r'C:\R')
        out = subprocess.run([sys.executable, '-c', code, here], capture_output=True, text=True, env=env,
                             check=True).stdout.splitlines()
        self.assertEqual(out[:2], [r'C:\W', r'C:\R'])
        self.assertEqual(out[2], str(Path(r'C:\W') / 'BeltRadio' / 'Contents' / 'mods' / 'batman_BeltRadio'))
        env.pop('RS_WORKSHOP_DIR')
        env.pop('RS_AUTOCLIENT_RUNS')
        out = subprocess.run([sys.executable, '-c', code, here], capture_output=True, text=True, env=env,
                             check=True).stdout.splitlines()
        self.assertEqual(out[0], str(ROOT.parent))
        self.assertEqual(out[1], str(Path(autoclient.__file__).parent / 'runs'))

    def test_missing_mod_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'a').mkdir()
            self.assertEqual(autoclient.missing_mod_sources([('A', Path(tmp) / 'a'), ('B', Path(tmp) / 'b')]),
                             [f'B ({Path(tmp) / "b"})'])
        self.assertEqual(autoclient.missing_mod_sources([('x', ROOT)]), [])

    def test_respawn_count(self):
        text = ('t1 idle connected\n'
                't1 idle respawn: local player died; Respawn in 4 s\n'
                't1 idle respawn: new character Ann Lee in game\n'
                't0 idle respawn: new character Old One in game\n'
                't1 idle respawn: FAILED in phase create after 120 s\n'
                't1 idle respawn: new character Bo Ray in game\n')
        self.assertEqual(autoclient.respawn_count(text, 't1'), 2)
        self.assertEqual(autoclient.respawn_count(text, 't0'), 1)
        self.assertEqual(autoclient.respawn_count(text, 't9'), 0)

    def test_quit_wait_line(self):
        runs = [['rs.identity.before'], ['rst.disconnect.before', 'lk.rejoin.before']]
        self.assertEqual(autoclient.quit_wait_line(runs, 'reconnect2', ['rs_mp2']),
                         "run started by account 'rs_mp2'")
        self.assertIsNone(autoclient.quit_wait_line(runs, 'restart', ['rs_mp1', 'rs_mp2']))
        self.assertIsNone(autoclient.quit_wait_line(runs, None, []))
        self.assertIsNone(autoclient.quit_wait_line([['lk.rejoin.before']], 'reconnect2', ['rs_mp2']))
        # the exact line of RST_Server.lua
        server = (LUA / 'server' / 'RST' / 'RST_Server.lua').read_text(encoding='utf-8')
        self.assertIn('log("run started by account \'" .. name .. "\'")', server)

    def _clients(self, tmp, respawn_after_go=False, server_line=None, server_log=None):
        class FakeProc:
            def __init__(self):
                self.returncode, self.pid = None, 0

            def poll(self):
                return self.returncode

        class FakeClient(autoclient.MPClient):
            def start(self, cmd):
                self.proc = FakeProc()
                self.status_file.parent.mkdir(parents=True, exist_ok=True)
                self.status_file.write_text(f'{self.token} ingame x\n', encoding='utf-8')

            def control(self, words):
                super().control(words)
                if 'quit' in words:
                    if self.role == 'peer':
                        self.result_file.write_text('RST-RESULT ok=true total=1 pass=1\nRST-END\n', encoding='utf-8')
                    self.proc.returncode = 0
                elif 'go' in words:
                    with open(self.status_file, 'a', encoding='utf-8') as f:
                        if self.role == 'peer' and respawn_after_go:
                            f.write(f'{self.token} idle respawn: local player died; Respawn in 4 s\n')
                            f.write(f'{self.token} idle respawn: new character Ann Lee in game\n')
                        else:
                            f.write(f'{self.token} {"done" if self.role == "run" else "idle"} x\n')
                    if self.role == 'run':
                        if server_line:
                            with open(server_log, 'a', encoding='utf-8') as f:
                                f.write(server_line + '\n')
                        self.result_file.write_text('RST-RESULT ok=true total=1 pass=1\nRST-END\n', encoding='utf-8')

        return [FakeClient(1, Path(tmp) / 'c1', 'tok1', 'rs_mp1', 'run'),
                FakeClient(2, Path(tmp) / 'c2', 'tok2', 'rs_mp2', 'peer')]

    class Server:
        def __init__(self):
            import io
            self.stdin = io.BytesIO()

        def poll(self):
            return None

    class Args:
        timeout, menu_timeout, godmode, quit_timeout = 60, 60, True, 5

    def test_godmode_again_after_a_respawn(self):
        server = self.Server()
        with tempfile.TemporaryDirectory() as tmp:
            clients = self._clients(tmp, respawn_after_go=True)
            code, why = autoclient.run_mp_clients(clients, [['c1'], ['c2']], server, None, time.monotonic(),
                                                  self.Args())
        self.assertEqual((code, why), (0, ''))
        self.assertEqual(server.stdin.getvalue().decode('utf-8'),
                         'godmodeplayer rs_mp1 -true\ngodmodeplayer rs_mp2 -true\ngodmodeplayer rs_mp2 -true\n')
        server = self.Server()

        class Mortal(self.Args):
            godmode = False
        with tempfile.TemporaryDirectory() as tmp:
            clients = self._clients(tmp, respawn_after_go=True)
            autoclient.run_mp_clients(clients, [['c1'], ['c2']], server, None, time.monotonic(), Mortal())
        self.assertEqual(server.stdin.getvalue(), b'')   # --no-godmode: never, not even after a respawn

    def test_respawn_load_screen_is_clicked(self):
        with tempfile.TemporaryDirectory() as tmp:
            c = autoclient.MPClient(2, Path(tmp), 'tok2', 'rs_mp2', 'peer')
            c.status_file.parent.mkdir(parents=True)
            c.status_file.write_text('tok2 idle x\ntok2 load respawn: back\n', encoding='utf-8')
            c.poll_state()
            self.assertEqual(c.state, 'load')
            clicked = []
            saved = autoclient.find_window, autoclient.post_click
            autoclient.find_window, autoclient.post_click = (lambda pid: 7), clicked.append

            class P:
                pid = 1
            c.proc = P()
            try:
                c.click_if_loading(10.0)
            finally:
                autoclient.find_window, autoclient.post_click = saved
            self.assertEqual(clicked, [7])

    def test_quit_waits_for_the_server_line(self):
        saved = autoclient.QUIT_WAIT_S
        autoclient.QUIT_WAIT_S = 1.0
        try:
            for line, seen in (("run started by account 'rs_mp2'", True), (None, False)):
                with tempfile.TemporaryDirectory() as tmp:
                    log = Path(tmp) / 'server-stdout.log'
                    log.write_text("[RST] run started by account 'rs_mp2'\n", encoding='utf-8')  # before: ignored
                    offset = len(log.read_text(encoding='utf-8'))
                    clients = self._clients(tmp, server_line=line and '[RST] ' + line, server_log=log)
                    t0 = time.monotonic()
                    code, _ = autoclient.run_mp_clients(clients, [['c1'], ['c2']], self.Server(), None,
                                                        time.monotonic(), self.Args(), keep=(1,),
                                                        quit_wait=(log, offset, "run started by account 'rs_mp2'"))
                    waited = time.monotonic() - t0
                    self.assertEqual(code, 0)
                    self.assertEqual(clients[1].control_file.read_text(encoding='utf-8'), 'go\nquit\n')
                    self.assertEqual(clients[0].control_file.read_text(encoding='utf-8'), 'go\n')
                    if seen:
                        self.assertLess(waited, 1.0)
                    else:
                        self.assertGreaterEqual(waited, 1.0)   # gave up after QUIT_WAIT_S, "quit" anyway
        finally:
            autoclient.QUIT_WAIT_S = saved



class ModswapAndLoadTests(unittest.TestCase):
    """Phase modswap (LK02-T12: lk.appearance across a restart with the clothes mod added), --load timeout and
    --load-phase-ms (LK13-T02)."""

    def test_modswap_plan(self):
        declared = autoclient.declared_suite_names(autoclient.CAMPAIGN_FILE.parents[2])
        self.assertIn('lk.appearance', declared)
        self.assertEqual(autoclient.phase_plan(['lk.appearance'], ['modswap'], declared),
                         [[['lk.appearance']], [['lk.appearance']]])
        for phases, why in ((['modswap', 'restart'], 'alone'), (['modswap'], 'no suite nope')):
            with self.assertRaises(ValueError) as ctx:
                autoclient.phase_plan(['nope'] if why.startswith('no') else ['lk.appearance'], phases, declared)
            self.assertIn(why, str(ctx.exception))
        self.assertTrue(autoclient.MODSWAP_MOD[1].is_dir())
        self.assertIn('id=' + autoclient.MODSWAP_MOD[0],
                      (autoclient.MODSWAP_MOD[1] / 'common' / 'mod.info').read_text(encoding='utf-8')
                      if (autoclient.MODSWAP_MOD[1] / 'common' / 'mod.info').exists()
                      else (autoclient.MODSWAP_MOD[1] / '42.21' / 'mod.info').read_text(encoding='utf-8'))
        suite = (SUITES_DIR / 'RST_LKAppearance.lua').read_text(encoding='utf-8')
        self.assertIn(autoclient.MODSWAP_MOD[0], suite)

    def test_ini_and_caches_get_the_mod(self):
        ini = autoclient.mp_server_ini(['A', 'B'])
        once = autoclient.ini_with_mod(ini, 'C')
        self.assertIn('Mods=\\A;\\B;\\C\n', once)
        self.assertEqual(autoclient.ini_with_mod(once, 'C'), once)
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / 'src'
            (src / 'common').mkdir(parents=True)
            (src / 'common' / 'mod.info').write_text('id=C', encoding='utf-8')
            server, client = Path(tmp) / 'server', Path(tmp) / 'client'
            (server / 'Server').mkdir(parents=True)
            (server / 'Server' / 'rstest_mp.ini').write_text(ini, encoding='utf-8')
            (client / 'mods').mkdir(parents=True)
            ids = autoclient.add_mod_to_caches(server, [client], ['A', 'B'], ('C', src))
            self.assertEqual(ids, ['A', 'B', 'C'])
            for cache in (server, client):
                self.assertTrue((cache / 'mods' / 'C' / 'common' / 'mod.info').exists())
            self.assertIn('Mods=\\A;\\B;\\C', (server / 'Server' / 'rstest_mp.ini').read_text(encoding='utf-8'))
            self.assertEqual((client / 'mods' / 'default.txt').read_text(encoding='utf-8'),
                             autoclient.mods_txt(['A', 'B', 'C']))
            autoclient.add_mod_to_caches(server, [client], ['A', 'B'], ('C', src))   # again: no error, no duplicate
            self.assertEqual((server / 'Server' / 'rstest_mp.ini').read_text(encoding='utf-8').count('\\C'), 1)

    def test_modswap_restarts_the_server_with_the_mod(self):
        events = []

        class Proc:
            returncode = 0

        class Srv:
            def __init__(self, cache):
                self.cache, self.proc, self.log_path = cache, Proc(), cache / 'server-stdout.log'

            def launch(self, timeout):
                events.append(('launch', 'batman_RadioSurvivorTestClothes' in
                               (self.cache / 'Server' / 'rstest_mp.ini').read_text(encoding='utf-8')))

        def fake_run(clients, ccmds, server, bridge, started, args, keep=(), quit_wait=None):
            events.append(('run', [c.token for c in clients]))
            return 0, ''
        saved = autoclient.run_mp_clients, autoclient.stop_server, autoclient.copy_mods
        autoclient.run_mp_clients = fake_run
        autoclient.stop_server = lambda proc, timeout: events.append(('stop',)) or 'server stopped'
        autoclient.copy_mods = lambda mods_dir, mods=None: mods_dir.joinpath(mods[0][0]).mkdir(parents=True)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                server = Path(tmp) / 'server'
                (server / 'Server').mkdir(parents=True)
                (server / 'Server' / 'rstest_mp.ini').write_text(autoclient.mp_server_ini(['A']), encoding='utf-8')
                c = autoclient.MPClient(1, Path(tmp) / 'c1', 'tok', 'rs_mp1', 'run')
                (c.cache / 'mods').mkdir(parents=True)

                class Args:
                    quit_timeout, server_timeout, restart_pause = 5, 5, 0
                code, why = autoclient.run_phases(
                    [c], [['c1']], Srv(server), None, 0.0, Args(), [[['lk.appearance']], [['lk.appearance']]],
                    ['modswap'], lambda i, k: ('cmd', 'run', f'tok-p{k}'), ['A'])
                self.assertEqual((code, why), (0, ''))
                self.assertEqual(events, [('run', ['tok']), ('stop',), ('launch', True), ('run', ['tok-p1'])])
                self.assertIn('batman_RadioSurvivorTestClothes', (c.cache / 'mods' / 'default.txt').read_text(
                    encoding='utf-8'))
        finally:
            autoclient.run_mp_clients, autoclient.stop_server, autoclient.copy_mods = saved

    def test_launch_globals(self):
        text = autoclient.launch_globals_lua({'RST_LK_LOADMP_PHASE_MS': 60000})
        self.assertIn('\nRST_LK_LOADMP_PHASE_MS = 60000\n', text)
        for bad in ({'bad name': 1}, {'X': '1; os.exit()'}):
            with self.assertRaises(ValueError):
                autoclient.launch_globals_lua(bad)
        suite = (SUITES_DIR / 'RST_LKLoadMP.lua').read_text(encoding='utf-8')
        self.assertIn('tonumber(' + autoclient.LOAD_PHASE_GLOBAL + ')', suite)
        self.assertTrue((ROOT / 'dev' / autoclient.LAUNCH_GLOBALS_FILE.parent).is_dir())

    def _dry(self, argv):
        import contextlib
        import io
        from unittest import mock

        def fake_copy(mods_dir, mods=autoclient.MODS):
            mods_dir.mkdir(parents=True, exist_ok=True)
        out = io.StringIO()
        with mock.patch.object(autoclient, 'copy_mods', fake_copy), contextlib.redirect_stdout(out):
            code = autoclient.main(argv)
        text = out.getvalue()
        caches = [Path(line.split('=', 1)[1].split(' ', 1)[0]) for line in text.splitlines() if '_CACHE=' in line]
        return code, text, caches

    def test_load_phase_ms_written_in_every_cache(self):
        code, text, caches = self._dry(['--mp', '--load', '--load-phase-ms', '60000', '--dry-run'])
        try:
            self.assertEqual(code, 0, text)
            self.assertEqual(len(caches), 5)
            for cache in caches:
                lua = (cache / 'mods' / autoclient.LAUNCH_GLOBALS_FILE).read_text(encoding='utf-8')
                self.assertIn('RST_LK_LOADMP_PHASE_MS = 60000', lua)
            first = (caches[1] / autoclient.TESTS_DIR / 'autoclient.txt').read_text(encoding='utf-8')
            self.assertIn('serverCampaign=mp-load', first)
            self.assertIn('serverTimeoutSec=3600', first)
        finally:
            import shutil
            for c in caches:
                shutil.rmtree(c, ignore_errors=True)
        self.assertEqual(self._dry(['--mp', '--load', '--load-phase-ms', '1000', '--dry-run'])[0], 2)
        self.assertEqual(autoclient.main(['--suite', 'x', '--load-phase-ms', '60000']), 2)


if __name__ == '__main__':
    unittest.main(verbosity=1)
