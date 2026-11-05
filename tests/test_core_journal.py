"""Mission journal of the core mod batman_RadioSurvivorCore (E18-T06).

    python RadioSurvivor/tests/test_core_journal.py

Bench of the interface (ISUI doubles of the notebook bench) on a dedicated server and two clients (harness.py), the
core mod alone (no RadioSurvivor module loaded): the journal lists the open missions of the player's character (offer,
active, to report) in the notebook order and states, refreshes while it is open, a mission done leaves it; the sidebar
button opens it, a host (RadioSurvivor's notebook) removes the button and is opened instead; controller: wheel
slice, up / down, B closes. With RadioSurvivor (notebook bench): the notebook registers itself as host and its
Missions tab lists the same rows. Every IGUI_RC_ key used exists in every shipped language.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402
import tempfile  # noqa: E402
from test_carnet import NOTEBOOK_UI, Simulation, open_notebook, convert  # noqa: E402
from test_protocol import lua_list  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CORE_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivorCore' / '42.21' / 'media' / 'lua'
RS_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
VIEW = CORE_LUA / 'client' / 'RadioSurvivorCore' / 'RC_MissionJournalView.lua'
TRANSLATE = CORE_LUA / 'shared' / 'Translate'

CLIENT_UI = r"""
UIFont = UIFont or {}
TEXTS = {}
getText = function(key, ...)
    local s = TEXTS[key] or key
    local args = {...}
    for i = 1, #args do s = string.gsub(s, '%%' .. i, tostring(args[i])) end
    return s
end
getScriptManager = function() return {FindItem = function(_, t) return {getDisplayName = function() return 'item ' .. t end} end} end
Joypad = {BButton = 1, AButton = 0, DPadRight = 13}
JOYPAD_FOCUS = {}
JoypadState = {players = {}}
setJoypadFocus = function(n, e) JOYPAD_FOCUS[n] = e; JoypadState.players[n + 1] = {focus = e} end
SLICES = {}
RADIAL = {javaObject = {}}
function RADIAL:addSlice(text, tex, fn, a1, a2) SLICES[#SLICES + 1] = {text = text, fn = fn, a1 = a1, a2 = a2} end
getPlayerRadialMenu = function() return RADIAL end
ISDPadWheels = {onDisplayRight = function(joypadData) WHEEL_SHOWN = joypadData.player end}
package.preload["ISUI/ISDPadWheels"] = function() return true end
"""

SIDEBAR = r"""
local Element = getmetatable(ISButton)
ISEquippedItem = Element:derive('ISEquippedItem')
function ISEquippedItem:new() local o = Element.new(self, 0, 0, 48, 300); o.playerNum = 0; return o end
function ISEquippedItem:initialise() Element.initialise(self) end
function ISEquippedItem:shrinkWrap() end
"""

SERVER = r"""
local M = require('RadioSurvivorCore/RC_Missions')
local MC = require('RadioSurvivorCore/RC_MissionConfig')
MC.Missions.probe = {id = 'probe_v1', titleKey = 'IGUI_RC_TestProbe', durationMs = 600000, rewardType = 'Base.Nails',
    rewardCount = 3}
M.register('probe', {idPrefix = 'probe', reportBySpeech = true,
    offer = function(c) return {durationMs = c.durationMs} end,
    create = function(m) m.ready = false end,
    check = function(m, player, payload) if payload == 'speech' and m.ready then return {} end return nil, 'State' end,
    prepare = function() return {kind = 'probe'} end,
    apply = function() end,
    progress = function() return 1, true end,
    reportReady = function(m) return m.ready == true end,
    project = function() end, context = function() end})
GIVERS = {['lk:1'] = {id = 'lk:1', name = 'Ruth'}, ['lk:2'] = {id = 'lk:2', name = 'Abe'}, ['lk:3'] = {id = 'lk:3', name = 'Cy'}}
STATE = {missions = {}}
STORE = {data = STATE, save = function() return true end}
M.registerDonor('lknpc', {find = function(state, id) return GIVERS[id] end})
M.useStore(STORE)
BOUND = {}
M.setBinding(function() return BOUND end)
function newMission(giver, character)
    local m = M.create(STATE, GIVERS[giver], character, 'probe_v1', {durationMs = 600000})
    m.donor = 'lknpc'
    return m
end
require('RadioSurvivorCore/RC_MissionJournal')
"""


def lua_rows(machine):
    rt = machine.rt
    return rt.eval('(function() local out = {} local w = RadioSurvivorCore.missionJournal.window '
                   'for _, it in ipairs(w and w.list.items or {}) do out[#out + 1] = it.text end '
                   'return table.concat(out, "|") end)()')


class JournalCoreOnlyTests(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp')
        s = self.h.machine('server')
        s.rt.execute(SIGNAL_SMOKE)
        s.rt.execute(SERVER)
        s.g.BOUND[self.h.player('server', 'A')] = 'cA'
        s.g.BOUND[self.h.player('server', 'B')] = 'cB'
        for name in ('A', 'B'):
            c = self.h.machine(name)
            c.rt.execute(CLIENT_UI)
            c.rt.execute(NOTEBOOK_UI)
            c.rt.execute(SIDEBAR)
            c.load(VIEW.read_text(encoding='utf-8'))

    def tearDown(self):
        self.h.close()

    def sev(self, code):
        return self.h.eval('server', '(function() ' + code + ' end)()')

    def cev(self, name, code):
        return self.h.eval(name, '(function() ' + code + ' end)()')

    def open(self, name='A'):
        self.cev(name, 'RadioSurvivorCore.missionJournal.toggle(0, false)')
        self.h.pump(); self.h.pump()

    def test_open_missions_listed_in_notebook_order_and_states(self):
        self.sev('local M = require("RadioSurvivorCore/RC_Missions") '
                 'local a = newMission("lk:1", "cA") '                       # offer to A
                 'local b = newMission("lk:2", "cA") M.accept(STATE, b, "cA", "Alice") '   # active
                 'b.ready = true '                                           # objective met: to report
                 'newMission("lk:3", "cB") ')                                # another character's offer
        self.open('A')
        self.assertEqual(lua_rows(self.h.machine('A')),
                         'IGUI_RC_TestProbe - Ruth (IGUI_RC_State_offer)|IGUI_RC_TestProbe - Abe (IGUI_RC_State_toReport)')
        self.open('B')   # only its own offer, never A's missions
        self.assertEqual(lua_rows(self.h.machine('B')), 'IGUI_RC_TestProbe - Cy (IGUI_RC_State_offer)')

    def test_mission_done_leaves_the_journal_at_the_next_refresh(self):
        self.sev('local M = require("RadioSurvivorCore/RC_Missions") '
                 'local b = newMission("lk:2", "cA") M.accept(STATE, b, "cA", "Alice") b.ready = true MID = b.id')
        self.open('A')
        self.assertIn('toReport', lua_rows(self.h.machine('A')))
        ok = self.sev('local M = require("RadioSurvivorCore/RC_Missions") '
                      'return tostring(M.spoken(STORE, STATE.missions[MID], nil, "cA"))')
        self.assertEqual(ok, 'true')
        self.h.advance_ms(3500)
        self.cev('A', 'RadioSurvivorCore.missionJournal.window:update()')
        self.h.pump(); self.h.pump()
        self.assertEqual(lua_rows(self.h.machine('A')), '')
        detail = self.cev('A', 'return RadioSurvivorCore.missionJournal.window.text.text')
        self.assertIn('IGUI_RC_JournalEmpty', detail)

    def test_sidebar_button_and_host(self):
        out = self.cev('A', 'local p = ISEquippedItem:new() p:initialise() ISEquippedItem.instance = p '
                            'local had = p.rcJournal ~= nil '
                            'p.rcJournal.onclick(p) local opened = RadioSurvivorCore.missionJournal.window:isVisible() '
                            'OPENED = nil RadioSurvivorCore.missionJournal.setHost(function(n) OPENED = n end) '
                            'local gone = p.rcJournal == nil '
                            'RadioSurvivorCore.missionJournal.toggle(0, false) '
                            'return tostring(had) .. tostring(opened) .. tostring(gone) .. tostring(OPENED)')
        self.assertEqual(out, 'truetruetrue0')

    def test_controller_wheel_selection_and_close(self):
        self.sev('local M = require("RadioSurvivorCore/RC_Missions") newMission("lk:1", "cA") newMission("lk:2", "cA")')
        out = self.cev('A', 'ISDPadWheels.onDisplayRight({player = 0}) local s = SLICES[1] '
                            's.fn(s.a1, s.a2) return tostring(WHEEL_SHOWN) .. "|" .. s.text .. "|" '
                            '.. tostring(JOYPAD_FOCUS[0] == RadioSurvivorCore.missionJournal.window)')
        self.assertEqual(out, '0|IGUI_RC_JournalButton|true')
        self.h.pump(); self.h.pump()
        out = self.cev('A', 'local w = RadioSurvivorCore.missionJournal.window local a = w.selectedId '
                            'w:onJoypadDirDown() local b = w.selectedId w:onJoypadDirUp() local c = w.selectedId '
                            'w:onJoypadDown(Joypad.BButton) '
                            'return table.concat({a, b, c, tostring(w:isVisible()), tostring(JOYPAD_FOCUS[0])}, "|")')
        self.assertEqual(out, 'lk:1-probe1|lk:2-probe1|lk:1-probe1|false|nil')

    def test_requests_are_rate_limited_on_the_server(self):
        for _ in range(12):
            self.cev('A', 'RadioSurvivorCore.missionJournal.request()')
        self.h.pump()
        sent = [m for m in self.h.pending() if m.get('command') == 'missions']
        self.assertLessEqual(len(sent), 4)

    def test_no_radiosurvivor_module(self):
        for name in ('server', 'A'):
            loaded = self.h.eval(name, '(function() local out = {} for k in pairs(package.loaded) do '
                                       'if string.find(k, "^RadioSurvivor/") or string.find(k, "^LivingKnox/") then '
                                       'out[#out + 1] = k end end return table.concat(out, ",") end)()')
            self.assertEqual(loaded, '', name)


class JournalWithRadioSurvivorTests(unittest.TestCase):
    """Notebook bench (RadioSurvivor and the core mod): the notebook hosts the journal, same rows in both."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rc-journal-')

    def tearDown(self):
        self.tmp.cleanup()

    def test_notebook_hosts_the_journal_with_the_same_rows(self):
        sim = Simulation(Path(self.tmp.name) / 'journal')
        sim.add_client('alice'); sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        cid = sim.character('alice')
        missions = sim.server.rt.eval("require('RadioSurvivorCore/RC_Missions')")
        missions.create(sim.state(), npc, cid, 'first_aid_v1')
        journal = sim.server.rt.eval("require('RadioSurvivorCore/RC_MissionJournal')")
        c = sim.clients['alice']
        window = open_notebook(c)
        c.rt.execute("getScriptManager = function() return {FindItem = function(_, t) "
                     "return {getDisplayName = function() return t end} end} end")
        sim.command('alice', 'snapshot')
        notebook_rows = [convert(r) for r in lua_list(c.g.RS_CarnetClient.snapshot.missions)]
        rows = [convert(r) for r in lua_list(journal.rows(cid))]
        self.assertEqual([(r['id'], r['state'], r['requester']) for r in rows],
                         [(r['id'], r['state'], r['requester']) for r in notebook_rows])
        self.assertEqual(len(rows), 1)
        view = c.g.RadioSurvivorCore.missionJournal
        self.assertIsNotNone(view.host, 'the notebook is the host of the journal')
        # the journal (button or wheel) opens the notebook on its Missions tab
        window.changeTab(window, 'Contacts')
        view.toggle(0, True)
        self.assertEqual((window.tab, window.isVisible(window)), ('Missions', True))
        panel = c.rt.eval("(function() local p = ISEquippedItem:new(0, 0, 48, 300) p.playerNum = 0 p.shrinkWrap = function() end "
                          "ISEquippedItem.initialise(p) return p end)()")
        self.assertIsNone(panel.rcJournal, 'no journal button next to the notebook')


class TranslationTests(unittest.TestCase):
    def test_every_key_in_every_shipped_language(self):
        used = set()
        for path in (CORE_LUA / 'client').rglob('*.lua'):
            used |= {'IGUI_RC_' + k for k in re.findall(r'tr\("([A-Za-z_]+)', path.read_text(encoding='utf-8'))
                     if not k.endswith('_')}
        used |= {f'IGUI_RC_State_{s}' for s in ('offer', 'active', 'toReport')}
        langs = sorted(p.name for p in (RS_LUA / 'shared' / 'Translate').iterdir() if p.is_dir())
        keys = {}
        for lang in langs:
            data = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            self.assertTrue(all(k.startswith('IGUI_RC_') for k in data), lang)
            keys[lang] = set(data)
        for lang in langs:
            self.assertEqual(keys[lang], keys['EN'], lang)
            self.assertFalse(used - keys[lang], (lang, sorted(used - keys[lang])))


if __name__ == '__main__':
    unittest.main()
