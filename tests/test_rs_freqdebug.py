"""Bouton de debug des fréquences de la partie (E05-T14) : autorité server/RadioSurvivor/RS_FreqDebug.lua et fenêtre
client/RadioSurvivor/RS_FreqDebugView.lua.

    python RadioSurvivor/tests/test_rs_freqdebug.py

Serveur simulé de tests/test_personas_server.py (ServerHarness : les six fiches livrées, fréquences tirées, vraies
chaînes du module, vrai RadioSurvivor_Server.lua) et, pour le MP, un client lupa séparé relié par sendClientCommand /
sendServerCommand (tables recopiées par Python, comme le réseau) :
- refus sans donnée d'un non-autorisé (client MP sans la capacité, solo sans le mode debug, connexion perdue : le rôle
  tranche), refus journalisés et bornés ;
- réponse fidèle à RS_Personas (ordre de chargement, fréquences tirées, servies, plages, radio, heures d'écoute, état,
  chroniqueur du bulletin E14-T02) et qui suit une relecture des fiches (conflit : fréquence non servie) ;
- aucun envoi sans requête, aucune requête fenêtre fermée, réponse arrivée après la fermeture ignorée ;
- même règle de droits que LK_Admin.isAllowed pour une opération de debug (deux modules chargés côte à côte) ;
- cellules du tableau, bouton du panneau debug vanilla (doublure ISDebugMenu), constantes et traductions EN/FR ;
- suite en jeu rs.freqdebug jouée par le vrai moteur RST sur le serveur simulé.
Doublures de droits : checkPermissions et getRole():hasCapability lisent une table ADMINS. Elles ne prouvent pas l'API
réelle (suite en jeu rs.freqdebug, protocole de docs/annexes/tests/tests-en-jeu.md).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_personas_server as tps  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LUA = tps.LUA
SERVER_FILE = LUA / 'server' / 'RadioSurvivor' / 'RS_FreqDebug.lua'
VIEW_FILE = LUA / 'client' / 'RadioSurvivor' / 'RS_FreqDebugView.lua'
LK_ADMIN_FILE = LUA / 'server' / 'LivingKnox' / 'LK_Admin.lua'
TRANSLATE = LUA / 'shared' / 'Translate'
TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SUITE_FILE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_FreqDebug.lua'
lua_list = tps.lua_list

# Fréquences tirées des six fiches livrées sur le serveur simulé (ZombRand rend 0 : la plus basse libre de chaque
# plage), dans l'ordre de chargement des fiches (alphabétique au premier chargement).
VOICES = {'cody': [10000], 'darlene': [115000], 'gus': [150200], 'nightowl': [88000, 109000], 'walt': [130000],
          'whitaker': [75000]}

RIGHTS = r'''
Capability = { PopmanManage = "cap:PopmanManage", AddItem = "cap:AddItem" }
ADMINS = {}
LOST_CONNECTION = false
DBG = false
isDebugEnabled = function() return DBG end
checkPermissions = function(player, cap)
    if LOST_CONNECTION then return true end   -- LuaManager.java:2916-2919 : connexion introuvable -> vrai
    return cap == Capability.PopmanManage and ADMINS[player:getUsername()] == true
end
function MKPLAYER(name)
    local p = { getUsername = function() return name end }
    p.getRole = function() return { hasCapability = function(_, c)
        return c == Capability.PopmanManage and ADMINS[name] == true end } end
    return p
end
'''

SERVER_EXTRA = RIGHTS + r'''
FULL = {}
sendServerCommand = function(p, m, c, a) FULL[#FULL + 1] = { player = p, module = m, command = c, args = a } end
RS_Facts = { CHRONICLER = "nightowl", chronicleHour = function() return 20 end }
ALICE, BOB = MKPLAYER("alice"), MKPLAYER("bob")
ADMINS.alice = true
'''

# Doublure du panneau debug vanilla (M/client/DebugUIs/DebugMenu/ISDebugMenu.lua:16-66) : setupButtons ajoute ses
# boutons, les trie, puis « Fermer ».
DEBUG_MENU = r'''
ISDebugMenu = {}
function ISDebugMenu:addButtonInfo(title, fn, tab) self.buttons = self.buttons or {}
    local info = { title = title, func = fn, tab = tab } table.insert(self.buttons, info) return info end
function ISDebugMenu:setupButtons()
    self:addButtonInfo("General", function() end, "MAIN")
    self:addButtonInfo("Cheats", function() end, "MAIN")
    table.sort(self.buttons, function(a, b) return a.title < b.title end)
    self:addButtonInfo("Close", nil, "MAIN")
end
function DEBUG_MENU_TITLES()
    local m = setmetatable({ buttons = {} }, { __index = ISDebugMenu })
    m:setupButtons()
    local out = {}
    for i, b in ipairs(m.buttons) do out[i] = b.title end
    return out, m
end
'''

CLIENT_STUBS = RIGHTS + DEBUG_MENU + r'''
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
SIDE = "client"
isClient = function() return SIDE == "client" end
isServer = function() return SIDE == "server" end
getText = function(k, ...) local t = { k } for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    return table.concat(t, "|") end
getTextOrNull = function(k) return nil end
ME = MKPLAYER("carol")
getSpecificPlayer = function() return ME end
OUT = {}
sendClientCommand = function(p, m, c, a) OUT[#OUT + 1] = { module = m, command = c, args = a } end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    rawset(t, k, e) return e end })
function fire(name, ...) for _, f in ipairs(Events[name].list) do f(...) end end
'''

V = 'RS_FreqDebugView'


def to_py(v):
    """Table Lua (lupa) -> dict / list Python, récursivement (copie « réseau »)."""
    if lupa.lua_type(v) != 'table':
        return v
    keys = list(v.keys())
    if not keys:
        return []
    if all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(v[i]) for i in range(1, len(keys) + 1)]
    return {k: to_py(v[k]) for k in keys}


def to_lua(rt, v):
    if isinstance(v, dict):
        return rt.table_from({k: to_lua(rt, x) for k, x in v.items()})
    if isinstance(v, list):
        return rt.table_from([to_lua(rt, x) for x in v])
    return v


class ClientMachine:
    """Client lupa : Const partagé, fenêtre RS_FreqDebugView.lua (sans ISCollapsableWindow : pas de fenêtre réelle)."""

    def __init__(self, side='client'):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.rt.execute(CLIENT_STUBS)
        self.g.SIDE = side
        paths = ';'.join((LUA / s).as_posix() + '/?.lua' for s in ('shared', 'client'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        self.load_view()

    def load_view(self):
        self.rt.execute(f'dofile([[{VIEW_FILE.as_posix()}]])')

    def ev(self, code):
        return self.rt.eval(code)

    def run(self, code):
        return self.rt.execute(code)

    def take_out(self):
        out = [to_py(x) for x in lua_list(self.g.OUT)]
        self.run('OUT = {}')
        return out


class ServerBase(tps.ServerHarness):
    bundled = None

    def setUp(self):
        super().setUp()
        self.rt.execute(SERVER_EXTRA)
        self.F = self.rt.eval('require("RadioSurvivor/RS_FreqDebug")')

    def full(self):
        return [to_py(x) for x in lua_list(self.g.FULL)]

    def req(self, who, op='frequencies', n=1):
        return self.rt.eval(f'function(p) return RS_FreqDebug.request(p, {{ op = "{op}", n = {n} }}) end')(
            self.g[who] if who else None)

    def deliver_to_server(self, player, sent):
        self.g.fire('OnClientCommand', sent['module'], sent['command'], self.g[player], to_lua(self.rt, sent['args']))


class AuthorityTests(ServerBase):

    def test_non_admin_client_is_refused_without_data_and_the_refusal_logged_once(self):
        self.g.fire('OnClientCommand', 'RadioSurvivorDebug', 'freqRequest', self.g.BOB,
                    self.rt.table_from({'op': 'frequencies', 'n': 4}))
        sent = self.full()
        self.assertEqual(len(sent), 1)
        self.assertEqual((sent[0]['module'], sent[0]['command']), ('RadioSurvivorDebug', 'freqReply'))
        self.assertTrue(self.rt.eval('FULL[1].player == BOB'))                       # au seul demandeur
        self.assertEqual(sent[0]['args'], {'n': 4, 'op': 'frequencies', 'ok': False, 'err': 'denied'})
        self.assertEqual(len(self.logs_with('request refused for bob (missing capability PopmanManage)')), 1)
        # Second refus dans la minute : tu ; le suivant, une minute plus tard, compte le refus tu.
        self.req('BOB')
        self.assertEqual(len(self.logs_with('request refused for bob')), 1)
        self.g.CLOCK = self.g.CLOCK + 60000
        self.req('BOB')
        self.assertEqual(len(self.logs_with('1 more refusal(s) not logged')), 1)

    def test_admin_gets_every_voice_faithful_to_the_personas(self):
        added, removed = self.g.ADDED, len(lua_list(self.g.REMOVED))
        self.g.fire('OnClientCommand', 'RadioSurvivorDebug', 'freqRequest', self.g.ALICE,
                    self.rt.table_from({'op': 'frequencies', 'n': 7}))
        sent = self.full()
        self.assertEqual(len(sent), 1)
        self.assertTrue(self.rt.eval('FULL[1].player == ALICE'))
        r = sent[0]['args']
        self.assertEqual((r['ok'], r['n'], r['op'], r['enabled']), (True, 7, 'frequencies', True))
        voices = r['voices']
        self.assertEqual([v['id'] for v in voices], lua_list(self.P.ids()))
        self.assertEqual([v['id'] for v in voices], list(VOICES))
        for v in voices:
            with self.subTest(v['id']):
                self.assertEqual(v['frequencies'], VOICES[v['id']])
                self.assertEqual(v['served'], self.served(v['id']))
                sheet = self.P.get(v['id'])
                self.assertEqual((v['name'], v['state'], v['radio'], v['language']),
                                 (sheet.name, sheet.state, sheet.radio, sheet.language))
                ranges = [(x['low'], x['high']) for x in v['ranges']]
                self.assertEqual(ranges, tps.DrawTests.RANGES[v['id']])
                self.assertIs(v['fixed'], False)
                self.assertIs(v['chronicler'], v['id'] == 'nightowl')
                self.assertIs(v['holds'], True)
        by_id = {v['id']: v for v in voices}
        self.assertEqual(by_id['whitaker']['state'], 'silent')
        self.assertEqual(by_id['nightowl']['listen'], [{'from': 19 * 60, 'to': 22 * 60}])
        self.assertEqual(by_id['walt']['listen'], [])                                 # always
        self.assertEqual(by_id['darlene']['listen'], [{'from': 420, 'to': 600}, {'from': 960, 'to': 1140}])
        self.assertEqual(r['others'], [{'kind': 'bulletin', 'voice': 'nightowl', 'khz': 88000, 'hour': 20}])
        # Rien d'autre que des valeurs simples (aucun objet Java, aucune fonction) dans la réponse.
        self.assertNotIn('function', json.dumps(r))
        # Lecture seule : aucune chaîne créée ni retirée.
        self.assertEqual((self.g.ADDED, len(lua_list(self.g.REMOVED))), (added, removed))

    def test_view_follows_a_reload_with_a_conflicting_sheet(self):
        # Deux fiches de l'admin à la même fréquence fixe : la première chargée la sert, l'autre la garde sans chaîne.
        # Une fréquence fixe sur la fréquence tirée de Walt : Walt est tiré de nouveau (RS_Personas.resolveFrequencies).
        self.write('zprobe.txt', self.sheet('zprobe', '145.0, 130.0'))
        self.write('zprobe2.txt', self.sheet('zprobe2', '145.0'))
        self.after(self.P.RELOAD_MS)
        r = to_py(self.req('ALICE'))
        by_id = {v['id']: v for v in r['voices']}
        self.assertEqual((by_id['zprobe']['frequencies'], by_id['zprobe']['served'], by_id['zprobe']['fixed']),
                         ([145000, 130000], [145000, 130000], True))
        self.assertEqual(by_id['zprobe']['ranges'], [])
        self.assertEqual((by_id['zprobe2']['frequencies'], by_id['zprobe2']['served']), ([145000], []))
        walt = by_id['walt']
        self.assertNotEqual(walt['frequencies'], [130000])
        self.assertEqual(walt['frequencies'], self.served('walt'))
        self.assertEqual(walt['served'], walt['frequencies'])
        # Chroniqueur parti (gone) : bulletin sans fréquence, plus de chaîne.
        text = (tps.BUNDLED / 'nightowl.txt').read_text(encoding='utf-8').replace('state=active', 'state=gone')
        self.write('nightowl.txt', text)
        self.after(self.P.RELOAD_MS)
        r = to_py(self.req('ALICE'))
        owl = [v for v in r['voices'] if v['id'] == 'nightowl'][0]
        self.assertEqual((owl['state'], owl['served'], owl['holds']), ('gone', [], False))
        self.assertEqual(r['others'][0].get('khz'), None)

    def test_connection_lost_role_decides_unknown_op_and_missing_capability(self):
        self.g.LOST_CONNECTION = True
        self.assertEqual(self.req('BOB').err, 'denied')
        self.assertIs(self.req('ALICE').ok, True)
        self.rt.execute('BOB.getRole = function() return nil end')
        self.assertEqual(self.req('BOB').err, 'denied')
        self.g.LOST_CONNECTION = False
        r = to_py(self.req('ALICE', op='list'))
        self.assertEqual(r, {'n': 1, 'op': 'list', 'ok': False, 'err': 'unknown request'})
        self.assertEqual(to_py(self.req(None)), {'n': 1, 'op': 'frequencies', 'ok': False, 'err': 'denied'})
        self.rt.execute('Capability = nil')
        self.assertEqual(self.req('ALICE').err, 'denied')
        self.assertTrue(self.logs_with('capability PopmanManage unknown'))

    def test_nothing_sent_without_a_request_and_other_commands_ignored(self):
        for _ in range(5):
            self.after(self.P.RELOAD_MS)
            self.g.fire('OnTick')
        self.g.fire('OnClientCommand', 'RadioSurvivorDebug', 'other', self.g.ALICE, self.rt.table_from({}))
        self.g.fire('OnClientCommand', 'LivingKnox', 'freqRequest', self.g.ALICE, self.rt.table_from({}))
        self.assertEqual([s for s in self.full() if s['module'] == 'RadioSurvivorDebug'], [])

    def test_solo_requires_the_debug_mode_and_never_uses_the_network(self):
        self.g.SIDE = 'solo'
        self.assertEqual(self.req('ALICE').err, 'denied')
        self.assertTrue(self.logs_with('request refused for alice (debug mode off (solo))'))
        self.g.DBG = True
        r = to_py(self.req('BOB'))                                  # solo : le joueur local, sans rôle
        self.assertEqual(len(r['voices']), 6)
        self.assertEqual(self.full(), [])

    def test_reloading_the_file_keeps_one_subscription(self):
        before = len(lua_list(self.g.Events.OnClientCommand.list))
        self.rt.execute(f'dofile([[{SERVER_FILE.as_posix()}]])')
        self.assertEqual(len(lua_list(self.g.Events.OnClientCommand.list)), before)
        self.g.fire('OnClientCommand', 'RadioSurvivorDebug', 'freqRequest', self.g.ALICE,
                    self.rt.table_from({'op': 'frequencies', 'n': 2}))
        self.assertEqual(len(self.full()), 1)


class RuleTests(unittest.TestCase):
    """Même règle que LK_Admin.isAllowed pour une opération de debug : les deux modules chargés dans une machine."""

    def test_same_decision_as_the_living_knox_debug_tools(self):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        rt.globals().next = None
        rt.execute('SIDE = "solo" isClient = function() return SIDE == "client" end '
                   'isServer = function() return SIDE == "server" end print = function() end '
                   'getTimestampMs = function() return 0 end LivingKnox = { subscribe = function() end } '
                   'for _, m in ipairs({ "LivingKnox/LK_Core", "LivingKnox/LK_Config", "LivingKnox/LK_Log", '
                   '"LivingKnox/LK_Groups", "LivingKnox/LK_Population", "LivingKnox/LK_Journal", "LivingKnox/LK_Load", '
                   '"LivingKnox/LK_Activity" }) do package.loaded[m] = true end '
                   'package.loaded["RadioSurvivor/RadioSurvivor_Const"] = { log = function() end } '
                   'package.loaded["RadioSurvivor/RS_Personas"] = {}')
        rt.execute(RIGHTS)
        rt.execute(f'dofile([[{LK_ADMIN_FILE.as_posix()}]]) dofile([[{SERVER_FILE.as_posix()}]])')
        rt.execute('ADMINS.boss = true BOSS, PEON = MKPLAYER("boss"), MKPLAYER("peon") '
                   'NOROLE = MKPLAYER("boss") NOROLE.getRole = function() return nil end SAVED_CAP = Capability')
        cases = 0
        for side in ('solo', 'server', 'client'):
            for dbg in ('true', 'false'):
                for lost in ('true', 'false'):
                    for cap in ('SAVED_CAP', 'nil'):
                        for who in ('BOSS', 'PEON', 'NOROLE', 'nil'):
                            rt.execute(f'SIDE = "{side}" DBG = {dbg} LOST_CONNECTION = {lost} Capability = {cap}')
                            lk = rt.eval(f'(LivingKnox.Admin.isAllowed({who}, "activity"))')
                            rs = rt.eval(f'(RS_FreqDebug.isAllowed({who}))')
                            self.assertEqual(lk, rs, (side, dbg, lost, cap, who))
                            cases += 1
        self.assertEqual(cases, 96)


class ClientTests(ServerBase):
    """Fenêtre sur un client MP relié au serveur simulé (tables recopiées comme par le réseau)."""

    def setUp(self):
        super().setUp()
        self.c = ClientMachine()

    def pump(self, player):
        """Commandes du client vers le serveur, réponses du serveur vers le client. Rend le nombre de requêtes."""
        sent = self.c.take_out()
        for s in sent:
            self.deliver_to_server(player, s)
        for reply in self.full():
            if reply['module'] == 'RadioSurvivorDebug':
                self.c.g.fire('OnServerCommand', reply['module'], reply['command'], to_lua(self.c.rt, reply['args']))
        self.rt.execute('FULL = {}')
        return len(sent)

    def open(self):
        self.c.run(f'{V}.state.window = {{}}')

    def test_no_request_while_closed_one_per_open_or_refresh(self):
        self.assertIsNone(self.c.ev(f'{V}.send()'))
        self.assertEqual(self.c.take_out(), [])
        self.open()
        self.assertEqual(self.c.ev(f'{V}.send()'), 1)
        out = self.c.take_out()
        self.assertEqual(out, [{'module': 'RadioSurvivorDebug', 'command': 'freqRequest',
                                'args': {'op': 'frequencies', 'n': 1}}])

    def test_non_admin_window_shows_a_refusal_without_data(self):
        self.assertFalse(self.c.ev(f'{V}.canUse()'))
        self.open()
        self.c.ev(f'{V}.send()')
        self.assertEqual(self.pump('BOB'), 1)
        self.assertEqual(self.c.ev(f'{V}.state.status'), 'IGUI_RS_FreqDebug_Denied')
        self.assertIsNone(self.c.ev(f'{V}.state.data'))
        self.assertEqual(to_py(self.c.ev(f'{V}.stats')), {'sent': 1, 'received': 1, 'stale': 0, 'refused': 1})

    def test_admin_window_receives_the_voices_and_builds_the_cells(self):
        self.c.g.ADMINS.carol = True
        self.assertTrue(self.c.ev(f'{V}.canUse()'))
        self.open()
        self.c.ev(f'{V}.send()')
        self.pump('ALICE')
        self.assertIsNone(self.c.ev(f'{V}.state.status'))
        voices = lua_list(self.c.ev(f'{V}.state.data.voices'))
        self.assertEqual([v.id for v in voices], list(VOICES))
        owl = self.c.ev(f'(function() for _, v in ipairs({V}.state.data.voices) do '
                        f'if v.id == "nightowl" then return {V}.voiceCells(v) end end end)()')
        self.assertEqual(to_py(owl), {'id': 'nightowl', 'name': 'Lyle Ferrand', 'state': 'active',
                                      'freqs': '88.0, 109.0', 'ranges': '88.0-107.8, 109.0-114.8',
                                      'radio': 'any', 'listen': '19:00-22:00',
                                      'role': 'IGUI_RS_FreqDebug_Chronicler'})
        walt = to_py(self.c.ev(f'{V}.voiceCells({V}.state.data.voices[5])'))
        self.assertEqual((walt['id'], walt['listen'], walt['role'], walt['freqs']),
                         ('walt', 'IGUI_RS_FreqDebug_Always', '-', '130.0'))
        other = to_py(self.c.ev(f'{V}.otherCells({V}.state.data.others[1])'))
        self.assertEqual(other, {'what': 'bulletin', 'voice': 'nightowl', 'freq': '88.0',
                                 'when': 'IGUI_RS_FreqDebug_Daily|20:00'})
        self.assertEqual(self.c.ev(f'{V}.voiceSort({V}.state.data.voices[4], "freqs")'), 88000)

    def test_reply_after_closing_or_stale_is_ignored(self):
        self.c.g.ADMINS.carol = True
        self.open()
        self.c.ev(f'{V}.send()')
        self.c.run(f'{V}.closed({V}.state.window)')
        self.pump('ALICE')
        self.assertIsNone(self.c.ev(f'{V}.state.data'))
        self.assertEqual(self.c.ev(f'{V}.stats.stale'), 1)
        # Réponse d'une requête périmée (n ancien) : ignorée.
        self.open()
        self.c.ev(f'{V}.send()')
        self.c.ev(f'{V}.send()')
        self.pump('ALICE')
        self.assertEqual(self.c.ev(f'{V}.stats.stale'), 2)
        self.assertEqual(len(lua_list(self.c.ev(f'{V}.state.data.voices'))), 6)
        # Fermée : plus aucune requête.
        self.c.run(f'{V}.closed({V}.state.window)')
        self.assertIsNone(self.c.ev(f'{V}.send()'))
        self.assertEqual(self.c.take_out(), [])

    def test_unserved_frequency_marked_and_fixed_sheet(self):
        cells = to_py(self.c.ev(f'{V}.voiceCells({{ id = "x", name = "X", state = "gone", frequencies = {{ 145000 }}, '
                                'served = {}, ranges = {}, radio = "high_tier", listen = { { from = 1320, to = 360 } } })'))
        self.assertEqual(cells['freqs'], 'IGUI_RS_FreqDebug_NotServed|145.0')
        self.assertEqual((cells['ranges'], cells['listen'], cells['radio']),
                         ('IGUI_RS_FreqDebug_Fixed', '22:00-06:00', 'high_tier'))
        off = to_py(self.c.ev(f'{V}.otherCells({{ kind = "bulletin", voice = "nightowl" }})'))
        self.assertEqual((off['freq'], off['when']), ('IGUI_RS_FreqDebug_OffAir', '-'))


class MenuTests(unittest.TestCase):

    def test_debug_menu_button_only_with_the_right_and_others_kept(self):
        c = ClientMachine()
        self.assertEqual(lua_list(c.ev('(DEBUG_MENU_TITLES())')), ['Cheats', 'General', 'Close'])
        c.g.ADMINS.carol = True
        titles = lua_list(c.ev('(DEBUG_MENU_TITLES())'))
        self.assertEqual(titles, ['Cheats', 'General', 'IGUI_RS_FreqDebug_Button', 'Close'])   # trié, avant « Fermer »
        self.assertEqual(c.ev('(select(2, DEBUG_MENU_TITLES())).buttons[3].tab'), 'MAIN')
        c.load_view()                                     # rechargement : un seul bouton, une seule inscription
        self.assertEqual(lua_list(c.ev('(DEBUG_MENU_TITLES())')).count('IGUI_RS_FreqDebug_Button'), 1)
        self.assertEqual(len(lua_list(c.g.Events.OnServerCommand.list)), 1)

    def test_solo_button_needs_the_debug_mode(self):
        c = ClientMachine(side='solo')
        self.assertNotIn('IGUI_RS_FreqDebug_Button', lua_list(c.ev('(DEBUG_MENU_TITLES())')))
        c.g.DBG = True
        self.assertIn('IGUI_RS_FreqDebug_Button', lua_list(c.ev('(DEBUG_MENU_TITLES())')))
        self.assertEqual(len(lua_list(c.g.Events.OnServerCommand.list)), 0)   # solo : réponse directe


class SoloWindowTests(ServerBase):
    """Solo : autorité et fenêtre dans la même machine, appel direct de RS_FreqDebug.request."""

    def setUp(self):
        super().setUp()
        self.g.SIDE = 'solo'
        self.rt.execute('getSpecificPlayer = function() return ALICE end '
                        'getText = function(k, ...) return k end sendClientCommand = function() SENT_CLIENT = true end')
        self.rt.execute(f'dofile([[{VIEW_FILE.as_posix()}]])')

    def test_solo_window_without_then_with_the_debug_mode(self):
        self.rt.execute(f'{V}.state.window = {{}}')
        self.rt.eval(f'{V}.send()')
        self.assertEqual(self.rt.eval(f'{V}.state.status'), 'IGUI_RS_FreqDebug_Denied')
        self.assertIsNone(self.rt.eval(f'{V}.state.data'))
        self.g.DBG = True
        self.rt.eval(f'{V}.send()')
        self.assertIsNone(self.rt.eval(f'{V}.state.status'))
        self.assertEqual([v.id for v in lua_list(self.rt.eval(f'{V}.state.data.voices'))], list(VOICES))
        self.assertIsNone(self.g.SENT_CLIENT)
        self.assertEqual(self.full(), [])


class SuiteTests(ServerBase):
    """Suite en jeu rs.freqdebug jouée par le vrai moteur RST sur le serveur simulé."""

    def setUp(self):
        super().setUp()
        self.rt.execute(f'package.path = [[{(TESTS_LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE_FILE.as_posix()}]])')

    def run_suite(self):
        rep = self.rt.eval('RST.runSync({ suite = "rs.freqdebug" }, { player = ALICE })')
        return rep, {r.test: (r.status, r.message) for r in rep.results.values()}

    def test_suite_passes_on_the_simulated_server(self):
        rep, res = self.run_suite()
        self.assertEqual(len(res), 4, res)
        # E01-T16: the real "user" client needs a dedicated server and a second client (SKIP here)
        self.assertEqual(res.pop('a real client with the user role is refused without data (E01-T16)')[0], 'SKIP')
        self.assertTrue(rep.ok, res)
        self.assertEqual({v[0] for v in res.values()}, {'PASS'})

    def test_suite_passes_in_solo_with_the_window_cells(self):
        self.g.SIDE = 'solo'
        self.g.DBG = True
        self.rt.execute('getSpecificPlayer = function() return ALICE end getText = function(k) return k end')
        self.rt.execute(f'dofile([[{VIEW_FILE.as_posix()}]])')
        rep, res = self.run_suite()
        self.assertTrue(rep.ok, res)

    def test_suite_detects_an_unfaithful_answer(self):
        self.rt.execute('local base = RS_FreqDebug.view RS_FreqDebug.view = function() local v = base() '
                        'table.remove(v.voices[1].served) return v end')
        rep, res = self.run_suite()
        self.assertFalse(rep.ok)
        self.assertEqual(res['answer faithful to the voices of the game'][0], 'FAIL')

    def test_suite_skips_the_answer_for_a_player_without_the_right(self):
        rep = self.rt.eval('RST.runSync({ suite = "rs.freqdebug" }, { player = BOB })')
        res = {r.test: r.status for r in rep.results.values()}
        self.assertEqual(res['answer faithful to the voices of the game'], 'SKIP')


class StaticTests(unittest.TestCase):

    def test_constants_shared_by_the_authority_and_the_window(self):
        server = SERVER_FILE.read_text(encoding='utf-8')
        view = VIEW_FILE.read_text(encoding='utf-8')
        for name in ('MODULE', 'CMD_REQUEST', 'CMD_REPLY', 'CAPABILITY', 'OP'):
            a = re.search(rf'^FreqDebug\.{name} = "([^"]+)"', server, re.M).group(1)
            b = re.search(rf'^FreqView\.{name} = "([^"]+)"', view, re.M).group(1)
            self.assertEqual(a, b, name)
        lk = LK_ADMIN_FILE.read_text(encoding='utf-8')
        self.assertEqual(re.search(r'^Admin\.CAPABILITY = "([^"]+)"', lk, re.M).group(1), 'PopmanManage')
        # Constantes avant la garde du client MP.
        self.assertLess(server.index('FreqDebug.OP ='), server.index('if isClient() then return FreqDebug end'))

    def test_sources_are_ascii_and_kahlua_safe(self):
        for path in (SERVER_FILE, VIEW_FILE, SUITE_FILE):
            raw = path.read_text(encoding='utf-8')
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw, flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII code in {path.name}')
            for pattern in (r'(?<![.:\w])next\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b', r'loadstring'):
                self.assertIsNone(re.search(pattern, code), (path.name, pattern))
        self.assertTrue(all(b < 128 for b in SUITE_FILE.read_bytes()), 'non ASCII byte in the suite')

    def test_translations_en_fr_cover_every_key_without_a_bare_percent(self):
        view = VIEW_FILE.read_text(encoding='utf-8')
        used = {k for k in re.findall(r'\btr\("(\w+)"', view) if not k.endswith('_')}
        cols = view[view.index('FreqView.VOICE_COLUMNS = {'):view.index('-- Cellules d\'une voix v')]
        used |= {f'Col_{k}' for k in re.findall(r'key = "(\w+)"', cols)}
        used |= {f'State_{s}' for s in ('active', 'silent', 'gone', 'dead')}
        used |= {'Radio_any', 'Radio_high_tier', 'Kind_bulletin'}
        self.assertEqual(len([k for k in used if k.startswith('Col_')]), 12)
        for lang in ('EN', 'FR'):
            data = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
            for key in used:
                self.assertIn(f'IGUI_RS_FreqDebug_{key}', data, lang)
            for k, v in data.items():
                if k.startswith('IGUI_RS_FreqDebug_'):
                    self.assertNotIn('%', re.sub(r'%\d', '', v), k)
        en = json.loads((TRANSLATE / 'EN' / 'IG_UI.json').read_text(encoding='utf-8'))
        fr = json.loads((TRANSLATE / 'FR' / 'IG_UI.json').read_text(encoding='utf-8'))
        self.assertEqual({k for k in en if 'FreqDebug' in k}, {k for k in fr if 'FreqDebug' in k})


if __name__ == '__main__':
    unittest.main(verbosity=1)
