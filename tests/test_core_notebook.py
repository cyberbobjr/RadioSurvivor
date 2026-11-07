"""Notebook of the core mod batman_RadioSurvivorCore (E18-T24; missions journal of E18-T06 merged into it).

    python RadioSurvivor/tests/test_core_notebook.py

Bench of the interface (ISUI doubles of the notebook bench) on a dedicated server and two clients (harness.py).
Core mod alone (no RadioSurvivor module loaded, as with Living Knox alone): the notebook opens without any item from
the sidebar button and the controller wheel; its Missions tab lists the open missions of the player's character (offer,
active, to report) in the RC_MissionList order and states, refreshes while it is shown, a mission done leaves it;
up / down move the selection, B closes. Tabs by mod: a tab exists only when its mods are active (getActivatedMods):
RadioSurvivor alone has no Team tab, Living Knox alone no Radio tab and loads no RadioSurvivor module, both show the five
tabs of before. With RadioSurvivor (notebook bench): its Missions tab lists the same missions as the core list. Every
IGUI_RC_ key used exists in every shipped language.
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402
from test_carnet import NOTEBOOK_UI, Simulation, open_notebook, convert  # noqa: E402
from test_protocol import lua_list  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CORE_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivorCore' / '42.21' / 'media' / 'lua'
RS_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
NOTEBOOK = CORE_LUA / 'client' / 'RadioSurvivorCore' / 'RC_Notebook.lua'
TRANSLATE = CORE_LUA / 'shared' / 'Translate'

CLIENT_UI = r"""
UIFont = UIFont or {}
TEXTS = {}
getText = function(key, ...)
    local args = {...}
    if not TEXTS[key] then  -- untranslated: the key, then its arguments
        for i = 1, #args do key = key .. '|' .. tostring(args[i]) end
        return key
    end
    local s = TEXTS[key]
    for i = 1, #args do s = string.gsub(s, '%%' .. i, tostring(args[i])) end
    return s
end
-- Keys shipped by the core mod and Living Knox (SHIPPED, set by the bench): getTextOrNull is nil for any other key.
SHIPPED = SHIPPED or {}
getTextOrNull = function(key, ...) if SHIPPED[key] then return getText(key, ...) end return nil end
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


def shipped_keys():
    keys = set()
    for mod in ('batman_RadioSurvivorCore', 'batman_LivingKnox'):
        path = ROOT / 'Contents' / 'mods' / mod / '42.21' / 'media' / 'lua' / 'shared' / 'Translate' / 'EN' / 'IG_UI.json'
        keys |= set(json.loads(path.read_text(encoding='utf-8')))
    return sorted(keys)


def active_mods(*ids):
    """getActivatedMods double (Java list of the loaded ids, LuaManager.java:6065)."""
    body = ', '.join(f'"{i}"' for i in ids)
    return ('getActivatedMods = function() local l = {%s} return {size = function() return #l end, '
            'get = function(_, i) return l[i + 1] end} end' % body)


def tab_names(machine):
    return machine.rt.eval('(function() local out = {} for _, b in ipairs(RadioSurvivorCore.notebook.window.tabs) do '
                           'out[#out + 1] = b.rsTab.name end return table.concat(out, ",") end)()')


def lua_rows(machine):
    return machine.rt.eval('(function() local out = {} local w = RadioSurvivorCore.notebook.window '
                           'for _, it in ipairs(w and w.list.items or {}) do '
                           'out[#out + 1] = it.text .. " (" .. RC_UI_Notebook.rowSecondLine(it.item, w:spec()) .. ")" end '
                           'return table.concat(out, "|") end)()')


class NotebookCoreOnlyTests(unittest.TestCase):
    """The core mod alone on the clients (Living Knox alone ships no notebook page of its own yet)."""

    def setUp(self):
        self.h = Harness(mode='mp')
        s = self.h.machine('server')
        s.rt.execute(SIGNAL_SMOKE)
        s.rt.execute(SERVER)
        s.g.BOUND[self.h.player('server', 'A')] = 'cA'
        s.g.BOUND[self.h.player('server', 'B')] = 'cB'
        for name in ('A', 'B'):
            c = self.h.machine(name)
            c.rt.execute('SHIPPED = {' + ', '.join(f'["{k}"] = true' for k in shipped_keys()) + '}')
            c.rt.execute(CLIENT_UI)
            c.rt.execute(NOTEBOOK_UI)
            c.rt.execute(SIDEBAR)
            c.rt.execute(active_mods('batman_SignalSmoke', 'batman_RadioSurvivorCore', 'batman_LivingKnox'))
            c.rt.execute('require("RadioSurvivorCore/RC_Notebook")')

    def tearDown(self):
        self.h.close()

    def sev(self, code):
        return self.h.eval('server', '(function() ' + code + ' end)()')

    def cev(self, name, code):
        return self.h.eval(name, '(function() ' + code + ' end)()')

    def open(self, name='A'):
        self.cev(name, 'local w = RC_UI_Notebook.toggle(0, false) w:changeTab("Missions") w:update()')
        self.h.pump(); self.h.pump()

    def test_tabs_without_radiosurvivor(self):
        self.open('A')
        self.assertEqual(tab_names(self.h.machine('A')), 'Contacts,Missions,Reputation')
        self.cev('A', 'RadioSurvivorCore.notebook.window:changeTab("Reputation")')
        self.assertIn('IGUI_RC_ReputationUnavailable', self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text'))
        self.cev('A', 'RadioSurvivorCore.notebook.window:changeTab("Contacts")')
        self.assertIn('IGUI_RC_Empty_Contacts', self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text'))
        self.assertIsNone(self.cev('A', 'return RadioSurvivorCore.notebook.window:changeTab("Radio")'))
        self.assertEqual(self.cev('A', 'return RadioSurvivorCore.notebook.window.tab'), 'Contacts')

    def test_open_missions_listed_in_list_order_and_states(self):
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
        detail = self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text')
        self.assertIn('IGUI_RC_Requester', detail)

    def test_mission_done_leaves_the_list_at_the_next_refresh(self):
        self.sev('local M = require("RadioSurvivorCore/RC_Missions") '
                 'local b = newMission("lk:2", "cA") M.accept(STATE, b, "cA", "Alice") b.ready = true MID = b.id')
        self.open('A')
        self.assertIn('toReport', lua_rows(self.h.machine('A')))
        ok = self.sev('local M = require("RadioSurvivorCore/RC_Missions") '
                      'return tostring(M.spoken(STORE, STATE.missions[MID], nil, "cA"))')
        self.assertEqual(ok, 'true')
        self.h.advance_ms(3500)
        self.cev('A', 'RadioSurvivorCore.notebook.window:update()')
        self.h.pump(); self.h.pump()
        self.assertEqual(lua_rows(self.h.machine('A')), '')
        detail = self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text')
        self.assertIn('IGUI_RC_JournalEmpty', detail)

    def test_claim_button_of_a_success_near_the_requester(self):
        """E18-T29: a success with a lot left is listed "to claim"; its button sends the gesture to the authority, which
        asks the giver (near, claim) and answers the list again."""
        self.sev('local M = require("RadioSurvivorCore/RC_Missions") CLAIMS = {} '
                 'M.registerDonor("lknpc", {find = function(state, id) return GIVERS[id] end, '
                 'near = function() return true end, '
                 'claim = function(store, m, player, character) CLAIMS[#CLAIMS + 1] = character '
                 'm.claimedBy, m.claimedName = character, "Alice" m.revision = m.revision + 1 return true end}) '
                 'local b = newMission("lk:2", "cA") M.accept(STATE, b, "cA", "Alice") b.ready = true '
                 'M.spoken(STORE, b, nil, "cA")')
        self.open('A')
        self.assertEqual(lua_rows(self.h.machine('A')), 'IGUI_RC_TestProbe - Abe (IGUI_RC_State_toClaim)')
        out = self.cev('A', 'local w = RadioSurvivorCore.notebook.window '
                            'return tostring(w.journalClaim:isVisible()) .. tostring(w.journalDeliver:isVisible())')
        self.assertEqual(out, 'truefalse')
        self.cev('A', 'local w = RadioSurvivorCore.notebook.window w.journalClaim.onclick(w)')
        self.h.pump(); self.h.pump()
        self.assertEqual(self.sev('return table.concat(CLAIMS, ",")'), 'cA')
        self.assertEqual(lua_rows(self.h.machine('A')), '')

    def test_sidebar_button_opens_the_notebook(self):
        out = self.cev('A', 'local p = ISEquippedItem:new() p:initialise() ISEquippedItem.instance = p '
                            'local had = p.rcNotebook ~= nil '
                            'p.rcNotebook.onclick(p) local opened = RadioSurvivorCore.notebook.window:isVisible() '
                            'p.rcNotebook.onclick(p) local closed = not RadioSurvivorCore.notebook.window:isVisible() '
                            'return tostring(had) .. tostring(opened) .. tostring(closed) .. "|" .. p.rcNotebook.tooltip')
        self.assertEqual(out, 'truetruetrue|IGUI_RC_NotebookHint')

    def test_controller_wheel_selection_and_close(self):
        self.sev('local M = require("RadioSurvivorCore/RC_Missions") newMission("lk:1", "cA") newMission("lk:2", "cA")')
        out = self.cev('A', 'ISDPadWheels.onDisplayRight({player = 0}) local s = SLICES[1] '
                            's.fn(s.a1, s.a2) return tostring(WHEEL_SHOWN) .. "|" .. s.text .. "|" '
                            '.. tostring(JOYPAD_FOCUS[0] == RadioSurvivorCore.notebook.window)')
        self.assertEqual(out, '0|IGUI_RC_Notebook|true')
        self.cev('A', 'local w = RadioSurvivorCore.notebook.window w:changeTab("Missions") w:update()')
        self.h.pump(); self.h.pump()
        out = self.cev('A', 'local w = RadioSurvivorCore.notebook.window local a = w.selectedId '
                            'w:onJoypadDirDown() local b = w.selectedId w:onJoypadDirUp() local c = w.selectedId '
                            'w:onJoypadDown(Joypad.BButton) '
                            'return table.concat({a, b, c, tostring(w:isVisible()), tostring(JOYPAD_FOCUS[0])}, "|")')
        self.assertEqual(out, 'lk:1-probe1|lk:2-probe1|lk:1-probe1|false|nil')

    def test_reputation_page_reads_the_core_reputation(self):
        """E18-T25: Living Knox alone, the Reputation page shows the core reputation and the acts in words; the act of
        Living Knox has its text once its notebook part is loaded, the act of RadioSurvivor (absent) a generic word."""
        self.sev('local R = require("RadioSurvivorCore/RC_Reputation") R.useData({reputation = {}, outcomes = {}}) '
                 'R.setLiveness(function() return nil end) '
                 'R.record(nil, "e1", "cA", "mission.success", nil, {}, {"Ruth"}) '
                 'R.record(nil, "e2", "cA", "npc.memberKilled", nil, {}) '
                 'R.record(nil, "e3", "cA", "trade.cheated", nil, {})')
        self.cev('A', 'local w = RC_UI_Notebook.toggle(0, false) w:changeTab("Reputation")')
        self.h.pump(); self.h.pump()
        text = self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text')
        self.assertIn('IGUI_RC_RepLevelLine', text)
        self.assertIn('IGUI_RC_RepReason_MissionSuccess', text)
        self.assertIn('IGUI_RC_RepReason_bad', text)  # Living Knox and RadioSurvivor acts: not their texts yet
        self.assertNotIn('IGUI_LK_RepReason_MemberKilled', text)
        self.assertNotIn('IGUI_RS_', text)
        self.h.machine('A').load((ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'client'
                                  / 'LivingKnox' / 'LK_NotebookPages.lua').read_text(encoding='utf-8'))
        self.h.advance_ms(3500)
        self.cev('A', 'RadioSurvivorCore.notebook.window:update()')
        self.h.pump(); self.h.pump()
        text = self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text')
        self.assertIn('IGUI_LK_RepReason_MemberKilled', text)
        self.assertNotIn('IGUI_RS_', text)
        self.assertIsNone(re.search(r'\d', re.sub(r'<[^>]*>', '', text)), text)
        self.sev('require("RadioSurvivorCore/RC_Reputation").setLiveness(nil)')

    def test_mission_of_a_giver_not_active_is_hidden_and_frozen(self):
        """E18-T25: a mission whose giver's mod is not active is hidden from the list, keeps its delay, is never failed
        nor pruned, and comes back as it was when the mod is active again."""
        self.sev('local M = require("RadioSurvivorCore/RC_Missions") PRESENT = true '
                 'M.registerDonor("gone", {find = function(state, id) return GIVERS[id] end, '
                 'present = function() return PRESENT end}) '
                 'local m = newMission("lk:1", "cA") m.donor = "gone" M.accept(STATE, m, "cA", "Alice") MID = m.id')
        self.open('A')
        self.assertIn('Ruth', lua_rows(self.h.machine('A')))
        out = self.sev('local M = require("RadioSurvivorCore/RC_Missions") PRESENT = false '
                       'local m = STATE.missions[MID] local before = m.remainingMs '
                       'M.advance(STATE, 10 * 600000) M.prune(STATE, getTimestampMs() + 10 * 86400000) '
                       'return table.concat({m.state, tostring(m.remainingMs == before), '
                       'tostring(STATE.missions[MID] ~= nil), tostring(M.present(m))}, "|")')
        self.assertEqual(out, 'active|true|true|false')
        self.h.advance_ms(3500)
        self.cev('A', 'RadioSurvivorCore.notebook.window:update()')
        self.h.pump(); self.h.pump()
        self.assertEqual(lua_rows(self.h.machine('A')), '')
        self.sev('PRESENT = true')
        self.h.advance_ms(3500)
        self.cev('A', 'RadioSurvivorCore.notebook.window:update()')
        self.h.pump(); self.h.pump()
        self.assertIn('Ruth', lua_rows(self.h.machine('A')))

    def test_contacts_given_by_a_mod_with_its_page_and_history(self):
        """E18-T26: Contacts lists what the registered sources give (command "contacts"), with the exchanges of the
        core history; the page of the source (Living Knox: relation panel) is drawn by that mod's notebook part."""
        self.sev('local H = require("RadioSurvivorCore/RC_History") H.data = {schema = 1, characters = {}} '
                 'H.append("cA", "lk:lk-1", {id = "h1", author = "Ann", text = "Hi"}) '
                 'require("RadioSurvivorCore/RC_Contacts").registerSource("lk", {list = function(c) '
                 'if c ~= "cA" then return {} end '
                 'return {{id = "lk:lk-1", name = "Ruth", alive = true, groupName = "Farm", '
                 'relation = {level = "favorable", trend = "up", group = "cautious", today = 3, facts = {}}}} end})')
        self.cev('A', 'local w = RC_UI_Notebook.toggle(0, false) w:changeTab("Contacts")')
        self.h.pump(); self.h.pump()
        self.assertEqual(lua_rows(self.h.machine('A')), 'Ruth (IGUI_RC_Contact)')
        text = self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text')
        self.assertIn('IGUI_RC_Group|Farm', text)
        self.assertIn('Ann : Hi', text)
        self.assertNotIn('IGUI_LK_', text)  # Living Knox's page not loaded: no relation section
        self.cev('A', 'require("LivingKnox/LK_NotebookPages") RadioSurvivorCore.notebook.window:refresh()')
        text = self.cev('A', 'return RadioSurvivorCore.notebook.window.detail.text')
        self.assertIn('IGUI_LK_RelTitle', text)
        self.assertIn('IGUI_LK_RelLevel|IGUI_LK_RelLevel_favorable|IGUI_LK_RelTrend_up', text)
        self.assertIn('IGUI_LK_RelGroup|IGUI_LK_RelLevel_cautious', text)
        self.assertEqual(self.cev('B', 'local w = RC_UI_Notebook.toggle(0, false) w:changeTab("Contacts") '
                                       'return #RadioSurvivorCore.notebook.contactRows'), 0)
        self.h.pump(); self.h.pump()
        self.assertEqual(lua_rows(self.h.machine('B')), '')

    def test_requests_are_rate_limited_on_the_server(self):
        for _ in range(12):
            self.cev('A', 'RadioSurvivorCore.notebook.journal.request()')
        self.h.pump()
        sent = [m for m in self.h.pending() if m.get('command') == 'missions']
        self.assertLessEqual(len(sent), 4)

    def test_no_radiosurvivor_module(self):
        self.open('A')
        for name in ('server', 'A'):
            loaded = self.h.eval(name, '(function() local out = {} for k in pairs(package.loaded) do '
                                       'if string.find(k, "^RadioSurvivor/") or string.find(k, "^LivingKnox/") then '
                                       'out[#out + 1] = k end end return table.concat(out, ",") end)()')
            self.assertEqual(loaded, '', name)


class TabsByModTests(unittest.TestCase):
    """RadioSurvivor's pages loaded (notebook bench), tabs shown by the active mods."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rc-notebook-')

    def tearDown(self):
        self.tmp.cleanup()

    def notebook(self, *mods):
        sim = Simulation(Path(self.tmp.name) / 'nb')
        sim.add_client('alice'); sim.select('alice')
        c = sim.clients['alice']
        if mods:
            c.rt.execute(active_mods(*mods))
        return sim, open_notebook(c)

    def test_radiosurvivor_alone_has_no_team_tab(self):
        sim, _ = self.notebook('batman_SignalSmoke', 'batman_BeltRadio', 'batman_RadioSurvivorCore',
                               'batman_RadioSurvivor')
        self.assertEqual(tab_names(sim.clients['alice']), 'Radio,Contacts,Missions,Reputation')

    def test_both_mods_show_the_five_tabs(self):
        sim, window = self.notebook('batman_SignalSmoke', 'batman_BeltRadio', 'batman_RadioSurvivorCore',
                                    'batman_LivingKnox', 'batman_RadioSurvivor')
        self.assertEqual(tab_names(sim.clients['alice']), 'Radio,Contacts,Missions,Reputation,Team')
        labels = sim.clients['alice'].rt.eval('(function() local out = {} for _, b in ipairs(RadioSurvivorCore.notebook'
                                              '.window.tabs) do out[#out + 1] = b.rsLabel end '
                                              'return table.concat(out, ",") end)()')
        self.assertEqual(labels, 'IGUI_RS_Radio,IGUI_RC_Contacts,IGUI_RC_Missions,IGUI_RC_Reputation,IGUI_LK_Team')  # E18-T20: Living Knox's tab
        self.assertEqual(window.tab, 'Contacts')
        self.assertTrue(sim.clients['alice'].rt.eval('RS_CarnetClient.window == RadioSurvivorCore.notebook.window'))

    def test_one_sidebar_button(self):
        sim, _ = self.notebook()
        c = sim.clients['alice']
        panel = c.rt.eval("(function() local p = ISEquippedItem:new(0, 0, 48, 300) p.playerNum = 0 "
                          "p.shrinkWrap = function() end ISEquippedItem.initialise(p) return p end)()")
        self.assertIsNotNone(panel.rcNotebook)
        self.assertIsNone(panel.rsCarnet)
        self.assertIsNone(panel.rcJournal)
        self.assertEqual(panel.rcNotebook.tooltip, 'IGUI_RC_NotebookHint <LINE> IGUI_RS_SelectHint')

    def test_missions_tab_lists_the_core_rows(self):
        sim, window = self.notebook()
        npc = next(iter(sim.state().npcs.values()))
        cid = sim.character('alice')
        missions = sim.server.rt.eval("require('RadioSurvivorCore/RC_Missions')")
        missions.create(sim.state(), npc, cid, 'first_aid_v1')
        journal = sim.server.rt.eval("require('RadioSurvivorCore/RC_MissionJournal')")
        c = sim.clients['alice']
        c.rt.execute("getScriptManager = function() return {FindItem = function(_, t) "
                     "return {getDisplayName = function() return t end} end} end")
        sim.command('alice', 'snapshot')
        window.changeTab(window, 'Missions')
        notebook_rows = [convert(r) for r in lua_list(c.g.RS_CarnetClient.snapshot.missions)]
        rows = [convert(r) for r in lua_list(journal.rows(cid))]
        self.assertEqual([(r['id'], r['state'], r['requester']) for r in rows],
                         [(r['id'], r['state'], r['requester']) for r in notebook_rows])
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(lua_list(window.list['items'])), 1)


class TranslationTests(unittest.TestCase):
    def test_every_key_in_every_shipped_language(self):
        used = set()
        for path in (CORE_LUA / 'client').rglob('*.lua'):
            used |= {'IGUI_RC_' + k for k in re.findall(r"tr\(['\"]([A-Za-z_]+)", path.read_text(encoding='utf-8'))
                     if not k.endswith('_')}
        used |= {f'IGUI_RC_State_{s}' for s in ('offer', 'active', 'toReport')}
        used |= {f'IGUI_RC_{t}' for t in ('Contacts', 'Missions', 'Reputation')}
        used |= {'IGUI_RC_Empty_Contacts'}
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
