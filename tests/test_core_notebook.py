"""Notebook of the core mod batman_CoreAI (E18-T24; missions journal of E18-T06 merged into it).

    python RadioSurvivor/tests/test_core_notebook.py

Bench of the interface (ISUI doubles of the notebook bench) on a dedicated server and two clients (harness.py).
Core mod alone (no RadioSurvivor module loaded, as with Living Knox alone): the notebook opens without any item from
the sidebar button and the controller wheel; its Missions tab lists the open missions of the player's character (offer,
active, to report) in the CA_MissionList order and states, refreshes while it is shown, a mission done leaves it;
up / down move the selection, B closes. Tabs by mod: a tab exists only when its mods are active (getActivatedMods):
RadioSurvivor alone has no Team tab, Living Knox alone no Radio tab and loads no RadioSurvivor module, both show the five
tabs of before. With RadioSurvivor (notebook bench): its Missions tab lists the same missions as the core list. Every
IGUI_CA_ key used exists in every shipped language.
"""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, core_notebook_files  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402
from test_carnet import NOTEBOOK_UI, Simulation, open_notebook, convert  # noqa: E402
from test_protocol import lua_list  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CORE_LUA = ROOT / 'Contents' / 'mods' / 'batman_CoreAI' / '42.21' / 'media' / 'lua'
RS_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
NOTEBOOK = CORE_LUA / 'client' / 'CoreAI' / 'CA_Notebook.lua'
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
local M = require('CoreAI/CA_Missions')
local MC = require('CoreAI/CA_MissionConfig')
MC.Missions.probe = {id = 'probe_v1', titleKey = 'IGUI_CA_TestProbe', durationMs = 600000, rewardType = 'Base.Nails',
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
M.registerDonor('lknpc', {find = function(state, id) return GIVERS[id] end})
-- E21-T04: the notebook server of the core mod (no NPC provider registered, as with Living Knox alone today).
getWorld = function() return {getGameMode = function() return setmetatable({}, {__tostring = function() return 'Multiplayer' end}) end,
    getWorld = function() return 'core-notebook' end} end
SERVER = require('CoreAI/CA_NotebookServer')
STORE = SERVER.store
function newMission(giver, character)
    local m = M.create(STORE.data, GIVERS[giver], character, 'probe_v1', {durationMs = 600000})
    m.donor = 'lknpc'
    return m
end
"""


def shipped_keys():
    keys = set()
    for mod in ('batman_CoreAI', 'batman_LivingKnox'):
        path = ROOT / 'Contents' / 'mods' / mod / '42.21' / 'media' / 'lua' / 'shared' / 'Translate' / 'EN' / 'IG_UI.json'
        keys |= set(json.loads(path.read_text(encoding='utf-8')))
    return sorted(keys)


def active_mods(*ids):
    """getActivatedMods double (Java list of the loaded ids, LuaManager.java:6065)."""
    body = ', '.join(f'"{i}"' for i in ids)
    return ('getActivatedMods = function() local l = {%s} return {size = function() return #l end, '
            'get = function(_, i) return l[i + 1] end} end' % body)


def tab_names(machine):
    return machine.rt.eval('(function() local out = {} for _, b in ipairs(CoreAI.notebook.window.tabs) do '
                           'out[#out + 1] = b.rsTab.name end return table.concat(out, ",") end)()')


def lua_rows(machine):
    return machine.rt.eval('(function() local out = {} local w = CoreAI.notebook.window '
                           'for _, it in ipairs(w and w.list.items or {}) do '
                           'out[#out + 1] = it.text .. " (" .. CA_UI_Notebook.rowSecondLine(it.item, w:spec()) .. ")" end '
                           'return table.concat(out, "|") end)()')


class NotebookCoreOnlyTests(unittest.TestCase):
    """The core mod alone (no RadioSurvivor module, as with Living Knox alone): E21-T04, the notebook server of the core
    mod answers and each common tab reads its snapshot."""

    def setUp(self):
        self.h = Harness(mode='mp')
        s = self.h.machine('server')
        s.rt.execute(SIGNAL_SMOKE)
        s.rt.execute(SERVER)
        for name in ('A', 'B'):   # SurvivorDesc of the server copy of each player (name of the notebook character)
            s.rt.execute(f'HARNESS.players["{name}"].getDescriptor = function() return {{getForename = function() '
                         f'return "{name}" end, getSurname = function() return "Doe" end}} end '
                         f'HARNESS.players["{name}"].CanSee = function() return true end')
        self.h.fire('server', 'OnInitGlobalModData', False)
        self.cid = {}
        for name in ('A', 'B'):
            c = self.h.machine(name)
            c.rt.execute('SHIPPED = {' + ', '.join(f'["{k}"] = true' for k in shipped_keys()) + '}')
            c.rt.execute(CLIENT_UI)
            c.rt.execute(NOTEBOOK_UI)
            c.rt.execute(SIDEBAR)
            c.rt.execute(active_mods('batman_SignalSmoke', 'batman_CoreAI', 'batman_LivingKnox'))
            c.rt.execute('require("CoreAI/CA_Notebook") require("CoreAI/CA_NotebookClient") '
                         'require("CoreAI/CA_NotebookContacts") require("CoreAI/CA_NotebookMissions") '
                         'require("CoreAI/CA_NotebookReputation")')
            c.rt.execute('CoreAI.notebookClient.hello()')
            self.h.pump(); self.h.pump()
            self.cid[name] = c.rt.eval('CoreAI.notebookClient.character')
            self.assertIsNotNone(self.cid[name], 'hello of ' + name + ' not answered by the core server')

    def tearDown(self):
        self.h.close()

    def sev(self, code):
        return self.h.eval('server', '(function() ' + code + ' end)()')

    def cev(self, name, code):
        return self.h.eval(name, '(function() ' + code + ' end)()')

    def refresh(self, name='A'):
        self.cev(name, 'CoreAI.notebookClient.send("snapshot")')
        self.h.pump(); self.h.pump()
        self.cev(name, 'local w = CoreAI.notebook.window if w then w:refresh() end')

    def open(self, name='A', tab='Missions'):
        self.cev(name, f'local w = CA_UI_Notebook.toggle(0, false) w:changeTab("{tab}") w:update()')
        self.refresh(name)

    def mission(self, giver, name):
        return self.sev(f'return newMission("{giver}", "{self.cid[name]}").id')

    def accept(self, mid, name='A', ready=True):
        cid = self.cid[name]
        self.sev(f'local M = require("CoreAI/CA_Missions") local m = STORE.data.missions["{mid}"] '
                 f'M.accept(STORE.data, m, "{cid}", "Alice") m.ready = {"true" if ready else "false"}')

    def test_tabs_without_radiosurvivor(self):
        self.open('A', 'Contacts')
        self.assertEqual(tab_names(self.h.machine('A')), 'Contacts,Missions,Reputation')
        self.cev('A', 'CoreAI.notebook.window:changeTab("Reputation")')
        self.assertIn('IGUI_CA_Rep', self.cev('A', 'return CoreAI.notebook.window.detail.text'))
        self.cev('A', 'CoreAI.notebook.window:changeTab("Contacts")')
        self.assertIn('IGUI_CA_NoContactsSelect', self.cev('A', 'return CoreAI.notebook.window.detail.text'))
        self.assertIsNone(self.cev('A', 'return CoreAI.notebook.window:changeTab("Radio")'))
        self.assertEqual(self.cev('A', 'return CoreAI.notebook.window.tab'), 'Contacts')

    def test_open_missions_listed_in_list_order_and_states(self):
        self.mission('lk:1', 'A')                    # offer to A
        self.accept(self.mission('lk:2', 'A'))       # active, objective met: to report
        self.mission('lk:3', 'B')                    # another character's offer
        self.open('A')
        rows = lua_rows(self.h.machine('A')).split('|')
        self.assertEqual([r.split(' (')[0] for r in rows], ['IGUI_CA_TestProbe - Ruth', 'IGUI_CA_TestProbe - Abe'])
        self.assertEqual(self.cev('A', 'local s = CoreAI.notebookClient.snapshot.missions '
                                       'return s[1].state .. "|" .. s[2].state .. "|" .. tostring(s[2].toReport)'),
                         'offer|active|true')
        self.open('B')   # only its own offer, never A's missions
        rows = lua_rows(self.h.machine('B')).split('|')
        self.assertEqual([r.split(' (')[0] for r in rows], ['IGUI_CA_TestProbe - Cy'])
        self.open('A')
        detail = self.cev('A', 'return CoreAI.notebook.window.detail.text')
        self.assertIn('IGUI_CA_Requester', detail)

    def test_mission_done_leaves_the_list_at_the_next_refresh(self):
        mid = self.mission('lk:2', 'A')
        self.accept(mid)
        self.open('A')
        before = lua_rows(self.h.machine('A'))
        self.assertIn('Abe', before)
        ok = self.sev(f'local M = require("CoreAI/CA_Missions") '
                      f'return tostring(M.spoken(STORE, STORE.data.missions["{mid}"], nil, "{self.cid["A"]}"))')
        self.assertEqual(ok, 'true')
        self.refresh('A')
        self.assertNotEqual(lua_rows(self.h.machine('A')), before)
        self.assertEqual(self.cev('A', 'return CoreAI.notebookClient.snapshot.missions[1].state'), 'success')

    def test_claim_button_of_a_success_near_the_requester(self):
        """E18-T29: a success with a lot shows its claim button; the gesture goes to the notebook server, which asks the
        giver (near, claim)."""
        self.sev('local M = require("CoreAI/CA_Missions") CLAIMS = {} '
                 'M.registerDonor("lknpc", {find = function(state, id) return GIVERS[id] end, '
                 'near = function() return true end, '
                 'claim = function(store, m, player, character) CLAIMS[#CLAIMS + 1] = character '
                 'm.claimedBy, m.claimedName = character, "Alice" m.revision = m.revision + 1 return true end})')
        mid = self.mission('lk:2', 'A')
        self.accept(mid)
        self.sev(f'require("CoreAI/CA_Missions").spoken(STORE, STORE.data.missions["{mid}"], nil, "{self.cid["A"]}")')
        self.open('A')
        out = self.cev('A', 'local w = CoreAI.notebook.window '
                            'return tostring(w.claim:isVisible()) .. tostring(w.deliver:isVisible())')
        self.assertEqual(out, 'truefalse')
        self.cev('A', 'local w = CoreAI.notebook.window w.claim.onclick(w)')
        self.h.pump(); self.h.pump()
        self.assertEqual(self.sev('return table.concat(CLAIMS, ",")'), self.cid['A'])
        self.assertEqual(self.sev(f'return STORE.data.missions["{mid}"].claimedBy'), self.cid['A'])

    def test_created_lot_announced_by_the_notebook(self):
        """E18-T33: a mission that announces no lot carries the lot its giver creates (projected rewardTable)."""
        self.sev('local M = require("CoreAI/CA_Missions") '
                 'M.registerDonor("lknpc", {find = function(state, id) return GIVERS[id] end, '
                 'lot = function(m) return "tools" end})')
        mid = self.mission('lk:2', 'A')
        self.sev(f'STORE.data.missions["{mid}"].rewardCount = 0')
        self.open('A')
        self.assertEqual(self.cev('A', 'return CoreAI.notebookClient.snapshot.missions[1].rewardTable'), 'tools')
        text = self.cev('A', 'return CoreAI.notebookMissions.lotText("tools")')
        self.assertEqual(text, '1 × item Base.Hammer, 1 × item Base.Screwdriver, 10 × item Base.Nails')

    def test_sidebar_button_opens_the_notebook(self):
        out = self.cev('A', 'local p = ISEquippedItem:new() p:initialise() ISEquippedItem.instance = p '
                            'local had = p.rcNotebook ~= nil '
                            'p.rcNotebook.onclick(p) local opened = CoreAI.notebook.window:isVisible() '
                            'p.rcNotebook.onclick(p) local closed = not CoreAI.notebook.window:isVisible() '
                            'return tostring(had) .. tostring(opened) .. tostring(closed) .. "|" .. p.rcNotebook.tooltip')
        self.assertEqual(out, 'truetruetrue|IGUI_CA_NotebookHint')

    def test_controller_wheel_selection_and_close(self):
        first, second = self.mission('lk:1', 'A'), self.mission('lk:2', 'A')
        out = self.cev('A', 'ISDPadWheels.onDisplayRight({player = 0}) local s = SLICES[1] '
                            's.fn(s.a1, s.a2) return tostring(WHEEL_SHOWN) .. "|" .. s.text .. "|" '
                            '.. tostring(JOYPAD_FOCUS[0] == CoreAI.notebook.window)')
        self.assertEqual(out, '0|IGUI_CA_Notebook|true')
        self.cev('A', 'local w = CoreAI.notebook.window w:changeTab("Missions") w:update()')
        self.refresh('A')
        out = self.cev('A', 'local w = CoreAI.notebook.window local a = w.selectedId '
                            'w:onJoypadDirDown() local b = w.selectedId w:onJoypadDirUp() local c = w.selectedId '
                            'w:onJoypadDown(Joypad.BButton) '
                            'return table.concat({a, b, c, tostring(w:isVisible()), tostring(JOYPAD_FOCUS[0])}, "|")')
        self.assertEqual(out, '|'.join([first, second, first, 'false', 'nil']))

    def test_reputation_page_reads_the_core_reputation(self):
        """E18-T25: Living Knox alone, the Reputation page shows the core reputation and the acts in words; the act of
        Living Knox has its text once its notebook part is loaded, the act of RadioSurvivor (absent) a generic word."""
        cid = self.cid['A']
        self.sev('local R = require("CoreAI/CA_Reputation") R.useData({reputation = {}, outcomes = {}}) '
                 'R.setLiveness(function() return nil end) '
                 f'R.record(nil, "e1", "{cid}", "mission.success", nil, {{}}, {{"Ruth"}}) '
                 f'R.record(nil, "e2", "{cid}", "npc.memberKilled", nil, {{}}) '
                 f'R.record(nil, "e3", "{cid}", "trade.cheated", nil, {{}})')
        self.open('A', 'Reputation')
        text = self.cev('A', 'return CoreAI.notebook.window.detail.text')
        self.assertIn('IGUI_CA_RepLevelLine', text)
        self.assertIn('IGUI_CA_RepReason_MissionSuccess', text)
        self.assertIn('IGUI_CA_RepReason_bad', text)  # Living Knox and RadioSurvivor acts: not their texts yet
        self.assertNotIn('IGUI_LK_RepReason_MemberKilled', text)
        self.assertNotIn('IGUI_RS_', text)
        self.h.machine('A').load((ROOT / 'Contents' / 'mods' / 'batman_LivingKnox' / '42.21' / 'media' / 'lua' / 'client'
                                  / 'LivingKnox' / 'LK_NotebookPages.lua').read_text(encoding='utf-8'))
        self.refresh('A')
        text = self.cev('A', 'return CoreAI.notebook.window.detail.text')
        self.assertIn('IGUI_LK_RepReason_MemberKilled', text)
        self.assertNotIn('IGUI_RS_', text)
        self.assertIsNone(re.search(r'\d', re.sub(r'<[^>]*>', '', text)), text)
        self.sev('require("CoreAI/CA_Reputation").setLiveness(nil)')

    def test_mission_of_a_giver_not_active_is_hidden_and_frozen(self):
        """E18-T25: a mission whose giver's mod is not active is hidden from the list, keeps its delay, is never failed
        nor pruned, and comes back as it was when the mod is active again."""
        cid = self.cid['A']
        mid = self.sev('local M = require("CoreAI/CA_Missions") PRESENT = true '
                       'M.registerDonor("gone", {find = function(state, id) return GIVERS[id] end, '
                       'present = function() return PRESENT end}) '
                       f'local m = newMission("lk:1", "{cid}") m.donor = "gone" M.accept(STORE.data, m, "{cid}", "Alice") '
                       'return m.id')
        self.open('A')
        self.assertIn('Ruth', lua_rows(self.h.machine('A')))
        out = self.sev('local M = require("CoreAI/CA_Missions") PRESENT = false '
                       f'local m = STORE.data.missions["{mid}"] local before = m.remainingMs '
                       'M.advance(STORE.data, 10 * 600000) M.prune(STORE.data, getTimestampMs() + 10 * 86400000) '
                       'return table.concat({m.state, tostring(m.remainingMs == before), '
                       f'tostring(STORE.data.missions["{mid}"] ~= nil), tostring(M.present(m))}}, "|")')
        self.assertEqual(out, 'active|true|true|false')
        self.refresh('A')
        self.assertEqual(lua_rows(self.h.machine('A')), '')
        self.sev('PRESENT = true')
        self.refresh('A')
        self.assertIn('Ruth', lua_rows(self.h.machine('A')))

    def test_contacts_given_by_a_mod_with_its_page_and_history(self):
        """E18-T26: Contacts lists what the registered sources give (snapshot of the notebook server), with the exchanges
        of the core history; the page of the source (Living Knox: relation panel) is drawn by that mod's notebook part."""
        cid = self.cid['A']
        self.sev('local H = require("CoreAI/CA_History") '
                 f'H.append("{cid}", "lk:lk-1", {{id = "h1", author = "Ann", text = "Hi"}}) '
                 'require("CoreAI/CA_Contacts").registerSource("lk", {list = function(c) '
                 f'if c ~= "{cid}" then return {{}} end '
                 'return {{id = "lk:lk-1", name = "Ruth", alive = true, groupName = "Farm", page = "livingknox", '
                 'relation = {level = "favorable", trend = "up", group = "cautious", today = 3, facts = {}}}} end})')
        self.open('A', 'Contacts')
        self.assertEqual(lua_rows(self.h.machine('A')), 'Ruth (IGUI_CA_Contact)')
        text = self.cev('A', 'return CoreAI.notebook.window.detail.text')
        self.assertIn('IGUI_CA_Group|Farm', text)
        self.assertIn('Ann : Hi', text)
        self.assertNotIn('IGUI_LK_', text)  # Living Knox's page not loaded: no relation section
        self.cev('A', 'require("LivingKnox/LK_NotebookPages") CoreAI.notebook.window:refresh()')
        text = self.cev('A', 'return CoreAI.notebook.window.detail.text')
        self.assertIn('IGUI_LK_RelTitle', text)
        self.assertIn('IGUI_LK_RelLevel|IGUI_LK_RelLevel_favorable|IGUI_LK_RelTrend_up', text)
        self.assertIn('IGUI_LK_RelGroup|IGUI_LK_RelLevel_cautious', text)
        self.open('B', 'Contacts')
        self.assertEqual(lua_rows(self.h.machine('B')), '')

    def test_requests_are_rate_limited_on_the_server(self):
        for _ in range(12):
            self.cev('A', 'CoreAI.notebookClient.send("snapshot")')
        self.h.pump()
        sent = [m for m in self.h.pending() if m.get('command') == 'snapshot']
        self.assertLessEqual(len(sent), 6)

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
        sim, _ = self.notebook('batman_SignalSmoke', 'batman_BeltRadio', 'batman_CoreAI',
                               'batman_RadioSurvivor')
        self.assertEqual(tab_names(sim.clients['alice']), 'Radio,Contacts,Missions,Reputation')

    def test_both_mods_show_the_five_tabs(self):
        sim, window = self.notebook('batman_SignalSmoke', 'batman_BeltRadio', 'batman_CoreAI',
                                    'batman_LivingKnox', 'batman_RadioSurvivor')
        self.assertEqual(tab_names(sim.clients['alice']), 'Radio,Contacts,Missions,Reputation,Team')
        labels = sim.clients['alice'].rt.eval('(function() local out = {} for _, b in ipairs(CoreAI.notebook'
                                              '.window.tabs) do out[#out + 1] = b.rsLabel end '
                                              'return table.concat(out, ",") end)()')
        self.assertEqual(labels, 'IGUI_RS_Radio,IGUI_CA_Contacts,IGUI_CA_Missions,IGUI_CA_Reputation,IGUI_LK_Team')  # E18-T20: Living Knox's tab
        self.assertEqual(window.tab, 'Contacts')
        self.assertTrue(sim.clients['alice'].rt.eval('CoreAI.notebookClient.window == CoreAI.notebook.window'))

    def test_one_sidebar_button(self):
        sim, _ = self.notebook()
        c = sim.clients['alice']
        panel = c.rt.eval("(function() local p = ISEquippedItem:new(0, 0, 48, 300) p.playerNum = 0 "
                          "p.shrinkWrap = function() end ISEquippedItem.initialise(p) return p end)()")
        self.assertIsNotNone(panel.rcNotebook)
        self.assertIsNone(panel.rsCarnet)
        self.assertIsNone(panel.rcJournal)
        self.assertEqual(panel.rcNotebook.tooltip, 'IGUI_CA_NotebookHint <LINE> IGUI_RS_SelectHint')

    def test_missions_tab_lists_the_core_rows(self):
        sim, window = self.notebook()
        npc = next(iter(sim.state().npcs.values()))
        cid = sim.character('alice')
        missions = sim.server.rt.eval("require('CoreAI/CA_Missions')")
        missions.create(sim.state(), npc, cid, 'first_aid_v1')
        journal = sim.server.rt.eval("require('CoreAI/CA_MissionJournal')")
        c = sim.clients['alice']
        c.rt.execute("getScriptManager = function() return {FindItem = function(_, t) "
                     "return {getDisplayName = function() return t end} end} end")
        sim.command('alice', 'snapshot')
        window.changeTab(window, 'Missions')
        notebook_rows = [convert(r) for r in lua_list(c.g.CoreAI.notebookClient.snapshot.missions)]
        rows = [convert(r) for r in lua_list(journal.rows(cid))]
        self.assertEqual([(r['id'], r['state'], r['requester']) for r in rows],
                         [(r['id'], r['state'], r['requester']) for r in notebook_rows])
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(lua_list(window.list['items'])), 1)


class CoreClientRoundTripTests(unittest.TestCase):
    """E21-T03: the notebook client and the three common pages of the core mod alone on the client (no RadioSurvivor
    client file), a fake NPC provider and the notebook server of the authority, on the network module CoreAI."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rc-notebook-rt-')

    def tearDown(self):
        self.tmp.cleanup()

    def test_hello_snapshot_talk_and_quote(self):
        sim = Simulation(Path(self.tmp.name) / 'rt')
        c = sim.add_client('alice')
        client = c.g.CoreAI.notebookClient
        self.assertIsNotNone(client.world, 'hello not answered with the session')
        self.assertEqual(client.character, sim.character('alice'))
        sim.select('alice')
        self.assertEqual([r.name for r in lua_list(client.snapshot.contacts)], ['Real Bandit'])
        c.rt.execute("Translator = {getLanguage = function() return {name = function() return 'EN' end} end}")
        self.assertTrue(client.talk('Hello there', True))
        self.assertTrue(any(r.kind == 'npc_talk' for r in sim.server.g.CoreAI.notebookServer.talk.pending.values()))
        npc = next(iter(sim.state().npcs.values()))
        sim.server.rt.eval("require('CoreAI/CA_Missions')").create(sim.state(), npc, client.character,
                                                                   'first_aid_v1')
        sim.request_mission('alice', 'accept')
        window = open_core_notebook(c)
        window.changeTab(window, 'Missions')
        ids = sim.items('alice', 'Base.Bandage', 'Base.Bandage')
        delivery = c.rt.eval("require('CoreAI/CA_NotebookMissions')").newDelivery(window.row)
        delivery.instantiate(delivery)
        for item_id in ids:
            delivery.chosen[item_id] = True
        delivery.prepare.onclick(delivery)
        dialog = c.g.UI_ROOTS[len(c.g.UI_ROOTS)]
        self.assertTrue(str(dialog.text).startswith('IGUI_CA_ConfirmDelivery'), dialog.text)
        dialog.onclick(None, c.rt.eval("{internal = 'YES'}"))
        self.assertEqual(sim.mission().delivered, 2)

    def test_three_tabs_render_from_the_snapshot(self):
        sim = Simulation(Path(self.tmp.name) / 'tabs')
        c = sim.add_client('alice')
        sim.select('alice')
        window = open_core_notebook(c)
        self.assertEqual(tab_names(c), 'Contacts,Missions,Reputation')
        self.assertIn('Real Bandit', window.detail.text)
        self.assertTrue(window.talk.isVisible(window.talk))
        npc = next(iter(sim.state().npcs.values()))
        sim.server.rt.eval("require('CoreAI/CA_Missions')").create(sim.state(), npc, sim.character('alice'),
                                                                   'first_aid_v1')
        sim.command('alice', 'snapshot')
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_CA_Requester|Real Bandit', window.detail.text)
        self.assertTrue(window.accept.isVisible(window.accept))
        window.changeTab(window, 'Reputation')
        self.assertIn('IGUI_CA_RepLevelLine', window.detail.text)


def open_core_notebook(c):
    """Notebook of the core mod opened on a client that holds only the core notebook files."""
    c.rt.execute(NOTEBOOK_UI)
    c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
    c.load(*core_notebook_files())
    c.g.CoreAI.notebook.toggle()
    return c.g.CoreAI.notebook.window


class TranslationTests(unittest.TestCase):
    def test_every_key_in_every_shipped_language(self):
        used = set()
        for path in (CORE_LUA / 'client').rglob('*.lua'):
            used |= {'IGUI_CA_' + k for k in re.findall(r"tr\(['\"]([A-Za-z_]+)", path.read_text(encoding='utf-8'))
                     if not k.endswith('_')}
        used |= {f'IGUI_CA_State_{s}' for s in ('offer', 'active', 'toReport')}
        used |= {f'IGUI_CA_{t}' for t in ('Contacts', 'Missions', 'Reputation')}
        used |= {'IGUI_CA_Empty_Contacts'}
        langs = sorted(p.name for p in (RS_LUA / 'shared' / 'Translate').iterdir() if p.is_dir())
        keys = {}
        for lang in langs:
            data = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            self.assertTrue(all(k.startswith('IGUI_CA_') for k in data), lang)
            keys[lang] = set(data)
        for lang in langs:
            self.assertEqual(keys[lang], keys['EN'], lang)
            self.assertFalse(used - keys[lang], (lang, sorted(used - keys[lang])))


if __name__ == '__main__':
    unittest.main()
