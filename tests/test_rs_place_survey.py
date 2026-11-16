"""E22-T08 (ADR atelier-voix D08): "Voice workshop: record this place" in game, under Lua 5.1 (lupa).

    python RadioSurvivor/tests/test_rs_place_survey.py

Authority server/RadioSurvivor/RS_PlaceSurvey.lua and menu client/RadioSurvivor/RS_PlaceSurveyMenu.lua, with the real
CA_AdminAccess and doubles of the engine (isClient/isServer, Capability, checkPermissions, IsoPlayer:getRole, squares,
objects and containers, rooms and BuildingDef, getFileReader/getFileWriter over a Python dict, HaloTextHelper,
ISContextMenu:addOption, send*Command):
- menu gate: shown in solo with debug mode only; on an MP client only when the role holds PopmanManage; controller probe (test=true) gives
  ISWorldObjectContextMenu.setTest() without an option; no square, no option;
- the option sends only {op, n, x, y, z} in MP; in solo it calls the authority and shows a halo (good or bad);
- authority: non-admin MP refused "denied" without data and without writing; bad coordinates and unloaded square
  refused; the record line holds the real time, game date, character name, square, room, building bounds and the
  containers read by the authority (never from the client), tabs and separators cleaned;
- file bounded to the last 200 records, header kept, nothing else written; the line is read back by
  bridge/place_surveys.py (shared format);
- constants of the menu equal those of the authority, translations EN/FR present.
Doubles do not prove the real API: in-game suite rs.placesurvey (dev/batman_RadioSurvivorTests).
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
CORE_LUA = ROOT / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'
SERVER_FILE = LUA / 'server' / 'RadioSurvivor' / 'RS_PlaceSurvey.lua'
MENU_FILE = LUA / 'client' / 'RadioSurvivor' / 'RS_PlaceSurveyMenu.lua'
TRANSLATE = LUA / 'shared' / 'Translate'
sys.path.insert(0, str(ROOT / 'bridge'))
import place_surveys  # noqa: E402

BOOT = r'''
MODE = "solo"                -- solo, client, server
isClient = function() return MODE == "client" end
isServer = function() return MODE == "server" end
isDebugEnabled = function() return false end
Capability = { PopmanManage = "cap:PopmanManage" }
ADMINS = {}
checkPermissions = function(player, cap) return cap == Capability.PopmanManage and ADMINS[player:getUsername()] == true end
function MKPLAYER(name, forename, surname)
    local p = { getUsername = function() return name end }
    p.getRole = function() return { hasCapability = function(_, c)
        return c == Capability.PopmanManage and ADMINS[name] == true end } end
    p.getDescriptor = function() return { getForename = function() return forename end,
        getSurname = function() return surname end } end
    return p
end
LOGS = {}
package.loaded["RadioSurvivor/RadioSurvivor_Const"] = { log = function(m) LOGS[#LOGS + 1] = m end }
NOW = 0
getTimestampMs = function() return NOW end
getGameTime = function() return { getYear = function() return 1993 end, getMonth = function() return 6 end,
    getDay = function() return 8 end, getHour = function() return 8 end, getMinutes = function() return 5 end } end

-- files (Zomboid/Lua relative paths)
FILES, WRITES = {}, 0
getFileReader = function(path, create)
    local text = FILES[path]
    if text == nil then return nil end
    local lines, i = {}, 0
    for line in string.gmatch(text, "([^\n]*)\n") do lines[#lines + 1] = line end
    return { readLine = function() i = i + 1 return lines[i] end, close = function() end }
end
getFileWriter = function(path, create, append)
    WRITES = WRITES + 1
    local buf = append and (FILES[path] or "") or ""
    return { write = function(_, s) buf = buf .. s end, close = function() FILES[path] = buf end }
end

-- world
local function list(items) return { size = function() return #items end, get = function(_, i) return items[i + 1] end } end
function MKOBJECT(sprite, containers)
    local o = {}
    o.getSprite = function() return sprite and { getName = function() return sprite end } or nil end
    o.getContainerCount = function() return #containers end
    o.getContainerByIndex = function(_, k) local t = containers[k + 1]
        return t and { getType = function() return t end } or nil end
    return o
end
SQUARES = {}
function MKSQUARE(x, y, z, objects, room, def)
    local sq = { x = x, y = y, z = z }
    sq.getX = function() return x end
    sq.getY = function() return y end
    sq.getZ = function() return z end
    sq.getObjects = function() return list(objects or {}) end
    sq.getRoom = function() return room and { getName = function() return room end } or nil end
    sq.getBuilding = function() return def and { getDef = function() return {
        getX = function() return def[1] end, getY = function() return def[2] end,
        getX2 = function() return def[3] end, getY2 = function() return def[4] end } end } or nil end
    SQUARES[x .. "," .. y .. "," .. z] = sq
    return sq
end
getCell = function() return { getGridSquare = function(_, x, y, z) return SQUARES[x .. "," .. y .. "," .. z] end } end

-- network and UI
SENT, REPLIES, HALOS = {}, {}, {}
sendClientCommand = function(p, m, c, a) SENT[#SENT + 1] = { module = m, command = c, args = a } end
sendServerCommand = function(p, m, c, a) REPLIES[#REPLIES + 1] = { player = p, module = m, command = c, args = a } end
HaloTextHelper = {
    addGoodText = function(p, text) HALOS[#HALOS + 1] = "good:" .. text end,
    addBadText = function(p, text) HALOS[#HALOS + 1] = "bad:" .. text end,
}
getText = function(k) return k end
TESTED = 0
ISWorldObjectContextMenu = { setTest = function() TESTED = TESTED + 1 return true end }
function MKCONTEXT()
    local c = { options = {} }
    -- ISContextMenu is a Lua class of the game, not a Java class: a plain field, no HARNESS.fake.
    c.addOption = function(self, name, target, fn, a, b, d)
        self.options[#self.options + 1] = { name = name, target = target, fn = fn, args = { a, b, d } }
    end
    return c
end
LOCAL = nil
getSpecificPlayer = function() return LOCAL end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    rawset(t, k, e) return e end })
'''


def to_py(v):
    if lupa.lua_type(v) != 'table':
        return v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [to_py(v[i]) for i in range(1, len(keys) + 1)]
    return {k: to_py(v[k]) for k in keys}


class Bench:
    def __init__(self, mode: str):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.rt.execute(f'package.path = [[{(CORE_LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        self.rt.execute(BOOT)
        self.g = self.rt.globals()
        self.g.MODE = mode
        self.survey = self.load(SERVER_FILE)
        self.menu = self.load(MENU_FILE)

    def load(self, path: Path):
        return self.rt.execute(path.read_text(encoding='utf-8'))

    def file(self) -> str | None:
        return self.g.FILES[self.survey.FILE]

    def records(self) -> list[str]:
        text = self.file() or ''
        return [line for line in text.split('\n') if line and not line.startswith('#')]


class AuthorityTests(unittest.TestCase):
    def setUp(self):
        self.b = Bench('server')
        g = self.b.g
        g.ADMINS.alice = True
        self.alice = g.MKPLAYER('alice', 'Kate', 'Smith')
        self.bob = g.MKPLAYER('bob', 'Bob', 'Lane')
        dumpster = g.MKOBJECT('trash_01_0', self.b.rt.table('bin'))
        crate = g.MKOBJECT('loc;ation:01', self.b.rt.table('cra\tte'))
        g.MKSQUARE(10610, 9305, 0, self.b.rt.table(dumpster, crate))
        g.MKSQUARE(10600, 9300, 1, self.b.rt.table(), 'kitchen', self.b.rt.table(10590, 9290, 10620, 9310))

    def request(self, player, **args):
        reply = self.b.survey.request(player, self.b.rt.table_from(args))
        return to_py(reply)

    def test_non_admin_refused_without_data_or_write(self):
        reply = self.request(self.bob, op='place', n=4, x=10610, y=9305, z=0)
        self.assertEqual(reply, {'n': 4, 'op': 'place', 'ok': False, 'err': 'denied'})
        self.assertEqual(self.b.g.WRITES, 0)
        self.assertIsNone(self.b.file())
        self.assertIn('WARNING: request refused for bob', self.b.g.LOGS[1])
        for _ in range(3):
            self.request(self.bob, op='place', n=5, x=1, y=1, z=0)
        self.assertEqual(len(self.b.g.LOGS), 1, 'refusals logged at most once a minute')
        self.b.g.NOW = 61000
        self.request(self.bob, op='place', n=6, x=1, y=1, z=0)
        self.assertIn('3 more refusal(s) not logged', self.b.g.LOGS[2])
        self.assertEqual(self.b.survey.stats.refused, 5)
        self.assertEqual(self.request(None, op='place', n=1, x=1, y=1, z=0)['err'], 'denied')

    def test_bad_coordinates_refused(self):
        for args in ({'x': 1.5, 'y': 1, 'z': 0}, {'x': -1, 'y': 1, 'z': 0}, {'x': 1000000, 'y': 1, 'z': 0},
                     {'x': 1, 'y': 1, 'z': 32}, {'x': 1, 'y': 1, 'z': -33}, {'x': '1', 'y': 1, 'z': 0},
                     {'y': 1, 'z': 0}):
            with self.subTest(args):
                self.assertEqual(self.request(self.alice, op='place', n=2, **args),
                                 {'n': 2, 'op': 'place', 'ok': False, 'err': 'bad_coords'})
        self.assertEqual(self.request(self.alice, op='other', n=2, x=10610, y=9305, z=0)['err'], 'bad_coords')
        self.assertEqual(self.request(self.alice, op='place', n=3, x=5, y=5, z=0),
                         {'n': 3, 'op': 'place', 'ok': False, 'err': 'not_loaded'})
        self.assertEqual(self.b.g.WRITES, 0)

    def test_record_line_read_by_the_authority(self):
        reply = self.request(self.alice, op='place', n=7, x=10610, y=9305, z=0, room='lie', containers='fake')
        self.assertEqual(reply, {'n': 7, 'op': 'place', 'ok': True})
        reply = self.request(self.alice, op='place', n=8, x=10600, y=9300, z=1)
        self.assertTrue(reply['ok'])
        text = self.b.file()
        self.assertTrue(text.startswith(self.b.survey.HEADER + '\n'))
        dumpster, kitchen = self.b.records()
        fields = dict(part.split('=', 1) for part in dumpster.split('\t'))
        self.assertRegex(fields.pop('time'), r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$')
        self.assertEqual(fields, {'game': '1993-07-09 08:05', 'by': 'Kate Smith', 'at': '10610,9305,0',
                                  'containers': 'bin:trash_01_0;cra te:loc_ation_01'})
        self.assertEqual(kitchen.split('\t')[3:], ['at=10600,9300,1', 'room=kitchen', 'building=10590,9290,10620,9310'])
        self.assertIn('place 10610,9305,0 recorded by Kate Smith', self.b.g.LOGS[1])
        # the bridge reads the same lines (shared format)
        records = [place_surveys.parse_line(line) for line in text.split('\n')]
        records = [r for r in records if r]
        self.assertEqual(records[0]['containers'], [{'type': 'bin', 'sprite': 'trash_01_0'},
                                                    {'type': 'cra te', 'sprite': 'loc_ation_01'}])
        self.assertEqual(records[1]['building'], {'x1': 10590, 'y1': 9290, 'x2': 10620, 'y2': 9310})
        self.assertEqual(records[1]['by'], 'Kate Smith')

    def test_file_bounded_to_the_last_200_records(self):
        g = self.b.g
        for i in range(205):
            self.assertTrue(self.request(self.alice, op='place', n=i, x=10610, y=9305, z=0)['ok'])
            if i == 102:
                g.MKSQUARE(10600, 9300, 0)
        lines = self.b.records()
        self.assertEqual(len(lines), self.b.survey.MAX_RECORDS)
        self.assertEqual(self.b.file().count('#'), 1, 'one header')
        self.assertEqual(list(g.FILES.keys()), [self.b.survey.FILE], 'nothing else written')
        self.assertEqual(self.b.survey.FILE, 'batman_RadioSurvivor/workshop-places.txt')

    def test_name_cleaned_and_account_fallback(self):
        g = self.b.g
        g.ADMINS.carol = True
        odd = g.MKPLAYER('carol', 'Jo\tey', 'Mc\nKay')
        self.assertTrue(self.request(odd, op='place', n=1, x=10610, y=9305, z=0)['ok'])
        self.assertIn('\tby=Jo ey Mc Kay\t', self.b.records()[0])
        nameless = g.MKPLAYER('carol', '', '')
        self.assertEqual(self.b.survey.recorder(nameless), 'carol')

    def test_client_command_answers_the_requester_only(self):
        g = self.b.g
        self.b.survey.onClientCommand('RadioSurvivorSurvey', 'surveyPlace', self.alice,
                                      self.b.rt.table_from({'op': 'place', 'n': 9, 'x': 10610, 'y': 9305, 'z': 0}))
        self.b.survey.onClientCommand('Other', 'surveyPlace', self.alice, self.b.rt.table_from({'n': 1}))
        replies = to_py(g.REPLIES)
        self.assertEqual(len(replies), 1)
        self.assertEqual((replies[0]['module'], replies[0]['command'], replies[0]['args']),
                         ('RadioSurvivorSurvey', 'surveyReply', {'n': 9, 'op': 'place', 'ok': True}))


class MenuTests(unittest.TestCase):
    def bench(self, mode: str, admin: bool, debug: bool = False):
        b = Bench(mode)
        g = b.g
        if debug:
            b.rt.execute('isDebugEnabled = function() return true end')
        if admin:
            g.ADMINS.alice = True
        g.LOCAL = g.MKPLAYER('alice', 'Kate', 'Smith')
        b.rt.execute('local sq = MKSQUARE(10610, 9305, 0, { MKOBJECT("trash_01_0", { "bin" }) }) '
                     'WORLD = { getSquare = function() return sq end }')
        return b

    def fill(self, b, test=False):
        context = b.g.MKCONTEXT()
        result = b.menu.onFill(0, context, b.rt.table(b.g.WORLD), test)
        return to_py(context.options) or [], result, context

    def test_shown_in_solo_debug_only(self):
        # User decision 2026-11-16: the option is a debug tool in solo (debug mode), admin only in MP.
        self.assertEqual(self.fill(self.bench('solo', admin=False))[0], [])
        b = self.bench('solo', admin=False, debug=True)
        options, _, context = self.fill(b)
        self.assertEqual([o['name'] for o in options], ['IGUI_RS_Survey_Menu'])
        self.assertEqual(options[0]['args'], [10610, 9305, 0])

    def test_mp_client_admin_only(self):
        self.assertEqual(len(self.fill(self.bench('client', admin=True))[0]), 1)
        self.assertEqual(self.fill(self.bench('client', admin=False))[0], [])

    def test_controller_probe_and_no_square(self):
        b = self.bench('solo', admin=False, debug=True)
        options, result, _ = self.fill(b, test=True)
        self.assertEqual((options, result, b.g.TESTED), ([], True, 1))
        context = b.g.MKCONTEXT()
        b.menu.onFill(0, context, b.rt.table(), False)
        self.assertEqual(to_py(context.options) or [], [])

    def test_mp_option_sends_the_square_only(self):
        b = self.bench('client', admin=True)
        _, _, context = self.fill(b)
        option = context.options[1]
        option.fn(option.target, 10610, 9305, 0)
        sent = to_py(b.g.SENT)
        self.assertEqual(sent, [{'module': 'RadioSurvivorSurvey', 'command': 'surveyPlace',
                                 'args': {'op': 'place', 'n': 1, 'x': 10610, 'y': 9305, 'z': 0}}])
        self.assertEqual(to_py(b.g.HALOS) or [], [])
        b.menu.onServerCommand('RadioSurvivorSurvey', 'surveyReply', b.rt.table_from({'n': 1, 'ok': False,
                                                                                      'err': 'denied'}))
        b.menu.onServerCommand('Other', 'surveyReply', b.rt.table_from({'n': 1, 'ok': True}))
        self.assertEqual(to_py(b.g.HALOS), ['bad:IGUI_RS_Survey_Refused'])

    def test_solo_option_records_through_the_authority(self):
        b = self.bench('solo', admin=False, debug=True)
        _, _, context = self.fill(b)
        option = context.options[1]
        option.fn(option.target, 10610, 9305, 0)
        self.assertEqual(to_py(b.g.HALOS), ['good:IGUI_RS_Survey_Done'])
        self.assertIn('at=10610,9305,0', b.records()[0])
        self.assertEqual(to_py(b.g.SENT) or [], [])
        option.fn(option.target, 1, 1, 0)                     # not loaded: refused, bad halo
        self.assertEqual(to_py(b.g.HALOS)[-1], 'bad:IGUI_RS_Survey_Refused')

    def test_subscriptions(self):
        b = self.bench('client', admin=True)
        events = b.g.Events
        self.assertEqual(len(events.OnFillWorldObjectContextMenu.list), 1)
        self.assertEqual(len(events.OnServerCommand.list), 1)
        self.assertEqual(len(events.OnClientCommand.list), 0, 'no authority on an MP client')
        b.load(MENU_FILE)
        self.assertEqual(len(events.OnFillWorldObjectContextMenu.list), 1, 'read again: no second subscription')
        server = Bench('server')
        self.assertEqual(len(server.g.Events.OnClientCommand.list), 1)
        self.assertEqual(len(server.g.Events.OnFillWorldObjectContextMenu.list), 0, 'no menu on the server')


class ContractTests(unittest.TestCase):
    def test_menu_constants_equal_the_authority(self):
        b = Bench('solo')
        for name in ('MODULE', 'CMD_REQUEST', 'CMD_REPLY', 'OP'):
            self.assertEqual(b.menu[name], b.survey[name], name)
        self.assertEqual(b.survey.MAX_RECORDS, place_surveys.MAX_RECORDS)
        self.assertEqual(b.survey.FILE.split('/')[-1], place_surveys.FILE_NAME)

    def test_translations(self):
        for lang in ('EN', 'FR'):
            table = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for key in ('IGUI_RS_Survey_Menu', 'IGUI_RS_Survey_Done', 'IGUI_RS_Survey_Refused'):
                self.assertTrue(table.get(key, '').strip(), f'{lang} {key}')

    def test_ascii_only(self):
        for path in (SERVER_FILE, MENU_FILE):
            path.read_bytes().decode('ascii')


if __name__ == '__main__':
    unittest.main()
