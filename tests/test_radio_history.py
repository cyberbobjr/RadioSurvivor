"""Historique radio du carnet (E06-T04) : banc hors jeu, vrai Lua du mod sous lupa (Lua 5.1, API du jeu simulée).

    python RadioSurvivor/tests/test_radio_history.py

- LogTests : stockage de l'autorité (server/RadioSurvivor/RS_RadioLog.lua) dans l'état privé : 40 lignes par fréquence,
  8 fréquences par personnage (la moins récemment active oubliée), types dit / répondu / entendu, parasites ignorés,
  persistance par RS_State (relecture après redémarrage).
- TransportTests : harnais MP tests/harness.py (serveur dédié et deux clients, copie réseau des arguments) : chaque
  client ne reçoit que l'historique de son personnage ; une ligne « entendu » n'est admise que si elle a été diffusée
  sur cette fréquence ; aucune fréquence non réglée par le client n'apparaît ; sondage des fréquences borné.
- MapMarkTests (E07-T08) : un mark_map accepté (vrai RS_MapMarks jugé par RS_Actions) inscrit une ligne « mark »
  (libellé seul) sur la fréquence de la réponse, pour le seul personnage de l'appelant.
- RevealTests (E07-T05) : de même, un reveal_area accepté inscrit une ligne « reveal » (« Quartier révélé »).
- HistoryClientTests : copie client (client/RadioSurvivor/RS_RadioHistory.lua) : voyant, changement de personnage,
  tri par activité, refus et réglage par l'action vanilla ISRadioAction « SetChannel ».
- IntegrationTests : vrai RadioSurvivor_Server + RS_Carnet_Server (simulation de tests/test_carnet.py) : phrase,
  réponse de Walt relue par le pont simulé, ligne entendue par un autre joueur, redémarrage, mort du personnage,
  onglet Radio du carnet (dont la ligne « Mission reçue » d'une voix, E11-T08 : type de lieu traduit par le carnet).
Simulation, PAS validation en jeu.
"""
from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from harness import Harness
from test_carnet import Simulation, NOTEBOOK_UI, convert
from test_protocol import lua_list

SERVER_SETUP = r'''
getWorld = function() return { getGameMode = function() return 'Multiplayer' end,
    getWorld = function() return 'bench' end } end
ZombRand = function(a, b) return a end
SandboxVars = { RadioSurvivor = { Enabled = true } }
S = require 'RadioSurvivor/RS_State'
Log = require 'RadioSurvivor/RS_RadioLog'
Const = require 'RadioSurvivor/RadioSurvivor_Const'
assert(S.init(NEW_WORLD ~= false))
RS_CarnetServer = { bound = {} }
function bind(username, cid)
    local p = HARNESS.players[username]
    if not S.data.characters[cid] then
        S.data.characters[cid] = { id = cid, owner = username, slot = 0, name = username, contacts = {},
            knownMissions = {} }
    end
    RS_CarnetServer.bound[p] = cid
    return p
end
-- Même aiguillage que RadioSurvivor_Server.lua (onClientCommand), couvert pour de vrai par IntegrationTests.
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Const.MODULE then return end
    if command == Const.CMD.HEARD then Log.heard(player, args)
    elseif command == Const.CMD.HISTORY then Log.sendAll(player) end
end)
'''

CLIENT_SETUP = r'''
getText = function(k, ...) local t = { k } for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end
    return table.concat(t, '|') end
HALOS = {}
HaloTextHelper = { addBadText = function(p, t) HALOS[#HALOS + 1] = 'bad:' .. t end,
    addGoodText = function(p, t) HALOS[#HALOS + 1] = 'good:' .. t end }
Const = require 'RadioSurvivor/RadioSurvivor_Const'
History = require 'RadioSurvivor/RS_RadioHistory'
Events.OnServerCommand.Add(function(module, command, args)
    if module == Const.MODULE then History.receive(command, args) end
end)
function texts(khz)
    local out = {}
    for _, l in ipairs(History.lines(khz)) do out[#out + 1] = l.kind .. ':' .. l.text end
    return out
end
'''


def py(value):
    return convert(value) if value is not None and hasattr(value, 'items') else value


class Bench(unittest.TestCase):
    def setUp(self):
        self.h = Harness(mode='mp', clients=('A', 'B'))
        self.h.server.g.NEW_WORLD = True
        self.h.load('server', SERVER_SETUP)
        for c in ('A', 'B'):
            self.h.load(c, CLIENT_SETUP)
        self.h.load('server', "bind('A', 'char-a'); bind('B', 'char-b')")

    def tearDown(self):
        self.h.close()

    def server(self, code):
        return self.h.load('server', code)

    def texts(self, client, khz):
        return lua_list(self.h.eval(client, f'texts({khz})'))

    def record(self, cid):
        return py(self.h.eval('server', f'S.data.characters["{cid}"].radio'))


class LogTests(Bench):
    def test_lines_bounded_to_forty_per_frequency(self):
        self.server("for i = 1, 45 do Log.add('char-a', 145000, 'said', 'line ' .. i) end")
        radio = self.record('char-a')
        lines = radio['frequencies'][1]['lines']
        self.assertEqual(len(lines), 40)
        self.assertEqual(lines[1]['text'], 'line 6')
        self.assertEqual(lines[40]['text'], 'line 45')
        self.assertEqual(lines[40]['seq'], 45)

    def test_frequencies_bounded_least_recent_forgotten(self):
        self.server("for i = 1, 8 do Log.add('char-a', 140000 + i * 200, 'heard', 'f' .. i) end")
        # The first frequency becomes the most recent: the second one is forgotten for the ninth.
        self.server("Log.add('char-a', 140200, 'said', 'again'); Log.add('char-a', 150000, 'said', 'ninth')")
        khz = sorted(f['khz'] for f in self.record('char-a')['frequencies'].values())
        self.assertEqual(len(khz), 8)
        self.assertIn(140200, khz)
        self.assertNotIn(140400, khz)
        self.assertIn(150000, khz)

    def test_kinds_text_and_frequency_checked(self):
        self.assertIsNone(self.h.eval('server', "Log.add('char-a', 145000, 'secret', 'x')"))
        self.assertIsNone(self.h.eval('server', "Log.add('char-a', 145000.5, 'said', 'x')"))
        self.assertIsNone(self.h.eval('server', "Log.add('char-a', 50, 'said', 'x')"))
        self.assertIsNone(self.h.eval('server', "Log.add('char-a', 145000, 'reply', '<bzzt>')"))
        self.assertIsNone(self.h.eval('server', "Log.add('nobody', 145000, 'said', 'x')"))
        line = py(self.h.eval('server', "Log.add('char-a', 145000, 'reply', '<RGB:1,0,0> Walt [here]\\n' .. string.rep('a', 300))"))
        self.assertEqual(line['kind'], 'reply')
        self.assertNotIn('<', line['text'])
        self.assertNotIn('[', line['text'])
        self.assertEqual(len(line['text']), 200)
        self.assertRegex(line['when'], r'^\d\d/\d\d \d\d:\d\d$')

    def test_broadcast_types_reply_for_caller_only_and_skips_static(self):
        self.server("Log.broadcast(145000, { '<bzzt>', 'Walt here.', 'Over.' }, 'char-a')")
        self.h.pump()
        self.assertEqual(self.texts('A', 145000), ['reply:Walt here.', 'reply:Over.'])
        self.assertEqual(self.texts('B', 145000), [])
        self.assertIsNone(self.record('char-b'))

    def test_history_survives_restart(self):
        self.server("Log.spoken(HARNESS.players.A, 145000, 'Anyone?'); Log.broadcast(145000, { 'Walt here.' }, 'char-a')")
        self.assertTrue(self.h.eval('server', 'S.save()'))
        root = self.h.file_root('server')
        restart = Harness(mode='mp', clients=('A', 'B'))
        try:
            shutil.copytree(root, restart.file_root('server'), dirs_exist_ok=True)
            restart.server.g.NEW_WORLD = False
            restart.load('server', SERVER_SETUP)
            restart.load('A', CLIENT_SETUP)
            restart.load('server', "bind('A', 'char-a')")
            lines = py(restart.eval('server', 'S.data.characters["char-a"].radio.frequencies[1].lines'))
            self.assertEqual([(l['kind'], l['text']) for l in lines.values()],
                             [('said', 'Anyone?'), ('reply', 'Walt here.')])
            restart.load('A', 'History.request()')
            restart.pump()
            self.assertEqual(lua_list(restart.eval('A', 'texts(145000)')), ['said:Anyone?', 'reply:Walt here.'])
        finally:
            restart.close()


class TransportTests(Bench):
    def messages_to(self, client):
        return [m for m in self.h.pending() if m['to'] == client]

    def test_each_client_receives_only_its_own_history(self):
        self.server("Log.spoken(HARNESS.players.A, 145000, 'Alice calling'); "
                    "Log.broadcast(145000, { '<bzzt>', 'Walt answers Alice.' }, 'char-a')")
        to_b = self.messages_to('B')
        self.assertEqual(to_b, [], 'B received something of A')
        self.h.pump()
        # B heard the answer on his radio (OnDeviceText): reported, checked, recorded as heard.
        self.h.load('B', "History.report(145000, 'Walt answers Alice.')")
        self.h.pump()
        self.assertEqual(self.texts('B', 145000), ['heard:Walt answers Alice.'])
        self.assertEqual(self.texts('A', 145000), ['said:Alice calling', 'reply:Walt answers Alice.'])
        # Full history requests: each client gets its own character only.
        self.h.load('A', 'History.request()')
        self.h.load('B', 'History.request()')
        while self.h.queue:
            for msg in self.h.pending():
                if msg['to'] == 'B':
                    self.assertNotIn('char-a', repr(msg['args']))
                    self.assertNotIn('Alice calling', repr(msg['args']))
            self.h.pump(limit=1)
        self.assertEqual(self.h.eval('B', 'History.character'), 'char-b')
        self.assertEqual(self.texts('B', 145000), ['heard:Walt answers Alice.'])
        self.assertEqual(self.texts('A', 145000), ['said:Alice calling', 'reply:Walt answers Alice.'])

    def test_heard_needs_a_line_aired_on_that_frequency(self):
        self.server("Log.broadcast(145000, { 'Darlene on the air.' }, nil)")
        # Wrong text, wrong frequency, then the right one (once only: a second report is ignored).
        self.h.load('B', "History.report(145000, 'made up'); History.report(146000, 'Darlene on the air.')")
        self.h.load('B', "History.report(145000, 'Darlene on the air.'); History.report(145000, 'Darlene on the air.')")
        self.h.pump()
        self.assertEqual(self.texts('B', 145000), ['heard:Darlene on the air.'])
        self.assertEqual(self.texts('B', 146000), [])
        self.assertIsNone(self.record('char-a'))
        frequencies = self.record('char-b')['frequencies']
        self.assertEqual([f['khz'] for f in frequencies.values()], [145000])

    def test_old_aired_line_refused(self):
        self.server("Log.broadcast(145000, { 'Old call.' }, nil)")
        self.h.advance_ms(self.h.eval('server', 'Log.AIRED_MS') + 1000)
        self.h.load('B', "History.report(145000, 'Old call.')")
        self.h.pump()
        self.assertEqual(self.texts('B', 145000), [])

    def test_speaker_and_caller_never_get_their_own_lines_twice(self):
        self.server("Log.spoken(HARNESS.players.A, 145000, 'Alice calling'); "
                    "Log.broadcast(145000, { 'Walt answers.' }, 'char-a')")
        self.h.load('A', "History.report(145000, 'Alice calling'); History.report(145000, 'Walt answers.')")
        self.h.load('B', "History.report(145000, 'Alice calling')")
        self.h.pump()
        self.assertEqual(self.texts('A', 145000), ['said:Alice calling', 'reply:Walt answers.'])
        self.assertEqual(self.texts('B', 145000), ['heard:Alice calling'])

    def test_probing_frequencies_is_bounded(self):
        # A modified client cannot test every frequency for a fixed call text: four distinct frequencies per window.
        self.server("for i = 0, 5 do Log.broadcast(130000 + i * 200, { 'Call on ' .. i }, nil) end")
        self.h.load('B', "for i = 0, 5 do History.report(130000 + i * 200, 'Call on ' .. i) end")
        self.h.pump()
        heard = [k for k in range(130000, 131200, 200) if self.texts('B', k)]
        self.assertEqual(heard, [130000, 130200, 130400, 130600])
        self.h.advance_ms(self.h.eval('server', 'Log.REPORT_WINDOW_MS') + 1)
        self.server("Log.broadcast(131000, { 'Later call' }, nil)")
        self.h.load('B', "History.report(131000, 'Later call')")
        self.h.pump()
        self.assertEqual(self.texts('B', 131000), ['heard:Later call'])

    def test_unbound_player_gets_nothing(self):
        self.server("RS_CarnetServer.bound[HARNESS.players.B] = nil")
        self.server("Log.broadcast(145000, { 'Walt.' }, nil)")
        self.h.load('B', "History.report(145000, 'Walt.'); History.request()")
        self.h.pump()
        self.assertEqual(self.messages_to('B'), [])
        self.assertEqual(self.texts('B', 145000), [])

    def test_empty_history_reaches_the_client_as_nil_args(self):
        self.h.load('B', "History.receive(Const.CMD.HISTORY_ADD, { character = 'char-b', khz = 145000, last = 1, "
                         "line = { kind = 'said', text = 'stale', when = '', seq = 1 } })")
        self.h.load('B', 'History.request()')
        self.h.pump()
        # The server sends {character} only: the frequency list (empty) is dropped by the network copy.
        self.assertEqual(self.texts('B', 145000), [])
        self.assertEqual(self.h.eval('B', '#History.frequencies'), 0)


MAP_SETUP = r'''
Actions = require 'RadioSurvivor/RS_Actions'
MapMarks = require 'RadioSurvivor/RS_MapMarks'
SHEET = { id = 'mapper', actions = { 'say', 'mark_map' }, budgets = {},
    places = { { id = 'mill', x = 10600, y = 9300, z = 0, label = 'Old mill' } } }
function markFor(username, cid, khz)
    local p = HARNESS.players[username]
    local d = Actions.decide(SHEET, username, { { type = 'mark_map', place = 'mill' } }, getTimestampMs(),
        { player = p, khz = khz, cid = cid, day = '1993-07-12' })
    return d[1].reason
end
'''


class MapMarkTests(Bench):
    """E07-T08 : un repère accepté (mark_map, RS_MapMarks) devient une ligne « mark » de l'historique radio de l'appelant,
    sur la fréquence de la réponse, pour son seul personnage ; libellé seul, aucune coordonnée."""

    def setUp(self):
        super().setUp()
        self.server(MAP_SETUP)

    def test_mark_line_for_the_caller_only_on_that_frequency(self):
        self.assertEqual(self.h.eval('server', "markFor('A', 'char-a', 145000)"), 'ok')
        self.h.pump()
        self.assertEqual(self.texts('A', 145000), ['mark:Old mill'])
        self.assertEqual(self.texts('A', 146000), [])
        self.assertEqual(self.texts('B', 145000), [])
        self.assertIsNone(self.record('char-b'))
        radio = self.record('char-a')
        self.assertEqual([f['khz'] for f in radio['frequencies'].values()], [145000])
        line = radio['frequencies'][1]['lines'][1]
        self.assertEqual((line['kind'], line['text']), ('mark', 'Old mill'))
        self.assertNotIn('10600', repr(radio))
        self.assertNotIn('9300', repr(radio))
        # Another character of the same player (new notebook character): the line is not his.
        self.server("bind('A', 'char-a2')")
        self.h.load('A', 'History.request()')
        self.h.pump()
        self.assertEqual(self.h.eval('A', 'History.character'), 'char-a2')
        self.assertEqual(self.texts('A', 145000), [])
        self.assertIsNone(self.record('char-a2'))

    def test_no_notebook_character_marks_without_history(self):
        self.assertEqual(self.h.eval('server', "markFor('B', nil, 145000)"), 'ok')
        self.h.pump()
        self.assertIsNone(self.record('char-b'))
        self.assertEqual(self.texts('B', 145000), [])


REVEAL_SETUP = r'''
Actions = require 'RadioSurvivor/RS_Actions'
MapMarks = require 'RadioSurvivor/RS_MapMarks'
REVEALER = { id = 'revealer', actions = { 'say', 'reveal_area' }, budgets = {},
    places = { { id = 'mill', x = 10600, y = 9300, z = 0, label = 'Old mill' } } }
function revealFor(username, cid, khz)
    local p = HARNESS.players[username]
    local d = Actions.decide(REVEALER, username, { { type = 'reveal_area', place = 'mill' } }, getTimestampMs(),
        { player = p, khz = khz, cid = cid, day = '1993-07-12' })
    return d[1].reason
end
'''


class RevealTests(Bench):
    """E07-T05 : un quartier révélé (reveal_area, RS_MapMarks) devient une ligne « reveal » de l'historique radio de
    l'appelant (« Quartier révélé : <libellé> »), sur la fréquence de la réponse, pour son seul personnage ; libellé
    seul, aucune coordonnée."""

    def setUp(self):
        super().setUp()
        self.server(REVEAL_SETUP)

    def test_reveal_line_for_the_caller_only_on_that_frequency(self):
        self.assertEqual(self.h.eval('server', "revealFor('A', 'char-a', 145000)"), 'ok')
        self.h.pump()
        self.assertEqual(self.texts('A', 145000), ['reveal:Old mill'])
        self.assertEqual(self.texts('A', 146000), [])
        self.assertEqual(self.texts('B', 145000), [])
        self.assertIsNone(self.record('char-b'))
        radio = self.record('char-a')
        line = radio['frequencies'][1]['lines'][1]
        self.assertEqual((line['kind'], line['text']), ('reveal', 'Old mill'))
        for secret in ('10600', '9300', '10528', '9216'):
            self.assertNotIn(secret, repr(radio))

    def test_no_notebook_character_reveals_without_history(self):
        self.assertEqual(self.h.eval('server', "revealFor('B', nil, 145000)"), 'ok')
        self.h.pump()
        self.assertIsNone(self.record('char-b'))
        self.assertEqual(self.texts('B', 145000), [])


class HistoryClientTests(Bench):
    def add(self, client, khz, seq, text='x', character='char-b'):
        self.h.load(client, f"History.receive(Const.CMD.HISTORY_ADD, {{ character = '{character}', khz = {khz}, "
                            f"last = {seq}, line = {{ kind = 'heard', text = '{text}', when = '07/09 09:00', seq = {seq} }} }})")

    def test_unread_unless_viewing_the_radio_tab(self):
        self.add('B', 145000, 1)
        self.assertTrue(self.h.eval('B', 'History.unread'))
        self.h.load('B', 'History.markRead(); History.isViewing = function() return true end')
        self.add('B', 145000, 2)
        self.assertFalse(self.h.eval('B', 'History.unread'))
        # Duplicate push (same seq) is not added twice.
        self.add('B', 145000, 2)
        self.assertEqual(len(self.texts('B', 145000)), 2)

    def test_other_character_data_is_cleared(self):
        self.add('B', 145000, 1, character='char-old')
        self.add('B', 146000, 1, character='char-b')
        self.assertEqual(self.texts('B', 145000), [])
        self.assertEqual(self.texts('B', 146000), ['heard:x'])

    def test_sorted_by_recent_activity(self):
        self.add('B', 145000, 1)
        self.add('B', 146000, 2)
        self.add('B', 145000, 3)
        rows = py(self.h.eval('B', 'History.sorted()'))
        self.assertEqual([r['khz'] for r in rows.values()], [145000, 146000])
        self.assertEqual(rows[1]['when'], '07/09 09:00')

    def radio(self, client, **state):
        fields = {'on': 'true', 'power': 1, 'channel': 145000, 'low': 200, 'high': 1000000}
        fields.update({k: str(v).lower() if isinstance(v, bool) else v for k, v in state.items()})
        self.h.load(client, f'''
            local data = {{ on = {fields['on']}, power = {fields['power']}, channel = {fields['channel']},
                low = {fields['low']}, high = {fields['high']} }}
            function data:getIsTurnedOn() return self.on end
            function data:getPower() return self.power end
            function data:getChannel() return self.channel end
            function data:getMinChannelRange() return self.low end
            function data:getMaxChannelRange() return self.high end
            RADIO = {{ data = data, getDeviceData = function(self) return self.data end }}
            local p = getSpecificPlayer(0)
            p.getEquipedRadio = function() return RADIO end
            QUEUED = {{}}
            ISTimedActionQueue = {{ add = function(a) QUEUED[#QUEUED + 1] = a end }}
            ISRadioAction = {{ new = function(self, mode, character, device, khz)
                return {{ mode = mode, character = character, device = device, khz = khz }} end }}
        ''')

    def tune(self, client, khz):
        self.h.load(client, 'HALOS = {}')
        return self.h.eval(client, f'History.tune({khz})'), lua_list(self.h.eval(client, 'HALOS'))

    def test_tune_uses_the_vanilla_set_channel_action(self):
        self.radio('B')
        self.assertEqual(self.tune('B', 146200), (True, []))
        self.assertEqual(self.h.eval('B', 'QUEUED[1].mode'), 'SetChannel')
        self.assertEqual(self.h.eval('B', 'QUEUED[1].khz'), 146200)
        self.assertTrue(self.h.eval('B', 'QUEUED[1].device == RADIO'))
        self.assertTrue(self.h.eval('B', 'QUEUED[1].character == getSpecificPlayer(0)'))

    def test_tune_refusals(self):
        self.h.load('B', 'getSpecificPlayer(0).getEquipedRadio = function() return nil end')
        self.assertEqual(self.tune('B', 145000), (False, ['bad:IGUI_RS_RadioNoEquipped']))
        self.radio('B', on=False)
        self.assertEqual(self.tune('B', 146000), (False, ['bad:IGUI_RadioSurvivor_Off']))
        self.radio('B', power=0)
        self.assertEqual(self.tune('B', 146000), (False, ['bad:IGUI_RS_RadioNoPower']))
        self.radio('B', low=136000, high=174000)
        self.assertEqual(self.tune('B', 100000), (False, ['bad:IGUI_RS_RadioOutOfRange|100.0|136.0|174.0']))
        self.radio('B')
        self.assertEqual(self.tune('B', 145000), (False, ['good:IGUI_RS_RadioAlreadyTuned|145.0']))
        self.assertEqual(self.h.eval('B', '#QUEUED'), 0)


class IntegrationTests(unittest.TestCase):
    """Vrai RadioSurvivor_Server et vrai RS_Carnet_Server (identité, état privé), réseau de tests/test_carnet.py."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_radio_history_'))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def simulation(self, path, **kwargs):
        sim = Simulation(path, **kwargs)
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        return sim

    def client(self, sim, name):
        c = sim.add_client(name)
        # getText with every argument (the shared stub keeps only the first one).
        c.rt.execute("getText = function(k, ...) local t = { k } for i = 1, select('#', ...) do "
                     "t[#t + 1] = tostring(select(i, ...)) end return table.concat(t, '|') end")
        c.rt.execute("Talk = require('RadioSurvivor/RS_RadioTalk'); History = Talk.History; "
                     "local Const = require('RadioSurvivor/RadioSurvivor_Const'); "
                     "Events.OnServerCommand.Add(function(m, cmd, a) if m == Const.MODULE then Talk.handle(cmd, a or {}) end end); "
                     "local d = getPlayer().radio.device; function d:getPower() return 1 end; "
                     "function texts(khz) local out = {} for _, l in ipairs(History.lines(khz)) do "
                     "out[#out + 1] = l.kind .. ':' .. l.text end return out end")
        return c

    def texts(self, c, khz=145000):
        return lua_list(c.rt.eval(f'texts({khz})'))

    def answer(self, sim, text):
        requests = (sim.path / 'requests.txt').read_text(encoding='utf-8').splitlines()
        req = [l[4:] for l in requests if l.startswith('req=')][-1]
        (sim.path / 'responses.txt').write_text(f'resp={req}\nline={text}\nend\n', encoding='utf-8')
        sim.clock.offset += 1000
        sim.server.g.fire('OnTick')

    def test_said_reply_heard_restart_and_death(self):
        sim = self.simulation(self.tmp / 'mp')
        alice, bob = self.client(sim, 'alice'), self.client(sim, 'bob')
        self.assertTrue(alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Walt, are you there?')"))
        self.assertEqual(self.texts(alice), ['said:Walt, are you there?'])
        self.assertEqual(self.texts(bob), [])
        self.answer(sim, 'Walt here, loud and clear.')
        self.assertEqual(self.texts(alice), ['said:Walt, are you there?', 'reply:Walt here, loud and clear.'])
        # Bob's radio receives the broadcast line (and the static first): heard, checked by the server.
        bob.rt.execute("local r = getPlayer().radio; Talk.onDeviceText('g', '', -1, -1, -1, '<bzzt>', r); "
                       "Talk.onDeviceText('g', '', -1, -1, -1, 'Walt here, loud and clear.', r); "
                       "Talk.onDeviceText('g', '', -1, -1, -1, 'invented line', r)")
        self.assertEqual(self.texts(bob), ['heard:Walt here, loud and clear.'])
        # Alice's own radio also receives the answer: never recorded twice.
        alice.rt.execute("Talk.onDeviceText('g', '', -1, -1, -1, 'Walt here, loud and clear.', getPlayer().radio)")
        self.assertEqual(len(self.texts(alice)), 2)
        state = sim.state()
        alice_id, bob_id = sim.character('alice'), sim.character('bob')
        self.assertNotEqual(alice_id, bob_id)
        self.assertEqual(state.characters[bob_id].radio.frequencies[1].lines[1].kind, 'heard')
        self.assertTrue(alice.rt.eval('History.unread'))
        self.assertTrue(sim.server.g.RS_CarnetServer.store.save())

        restart = self.simulation(self.tmp / 'mp', saved_players=sim.saved())
        alice2 = self.client(restart, 'alice')
        self.assertEqual(restart.character('alice'), alice_id)
        self.assertEqual(self.texts(alice2), [])
        alice2.rt.execute('History.request()')
        self.assertEqual(self.texts(alice2), ['said:Walt, are you there?', 'reply:Walt here, loud and clear.'])

        restart.server.g.RS_CarnetServer.characterDeath(restart.server.g.PLAYERS['alice'])
        self.assertIsNone(restart.state().characters[alice_id].radio)

    def test_silence_on_a_frequency_without_voice_is_still_said(self):
        sim = self.simulation(self.tmp / 'silence')
        alice = self.client(sim, 'alice')
        alice.rt.execute('getPlayer().radio.device.channel = 151200')
        sim.server.g.PLAYERS['alice'].radio.device.channel = 151200
        self.assertTrue(alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Hello?')"))
        self.assertEqual(self.texts(alice, 151200), ['said:Hello?'])
        self.assertFalse((sim.path / 'requests.txt').read_text(encoding='utf-8').count('req='))

    def test_radio_tab_reread_on_opening_and_tune(self):
        sim = self.simulation(self.tmp / 'tab')
        alice = self.client(sim, 'alice')
        alice.rt.execute(NOTEBOOK_UI)
        alice.rt.execute("ISTimedActionQueue = { add = function(a) QUEUED = a end }; "
                         "ISRadioAction = { new = function(self, mode, p, radio, khz) return { mode = mode, khz = khz } end }")
        alice.load('client/RS_Carnet_Client.lua')
        notebook = alice.g.RS_UI_Notebook
        # Answer received with the notebook never opened: indicator on, lines read again at opening.
        alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Walt?')")
        self.answer(sim, 'Still here.')
        self.assertTrue(alice.rt.eval('History.unread'))
        alice.rt.execute('History.resetForTests(); History.unread = true')
        notebook.toggle()
        window = alice.g.RS_CarnetClient.window
        self.assertEqual(self.texts(alice), ['said:Walt?', 'reply:Still here.'])
        self.assertTrue(alice.rt.eval('History.unread'), 'read on the Contacts tab')
        window.changeTab(window, 'Radio')
        self.assertFalse(alice.rt.eval('History.unread'))
        self.assertEqual(window.row.khz, 145000)
        self.assertIn('<RGB:0.12,0.23,0.37> IGUI_RS_Radio_said', window.detail.text)
        self.assertIn('<RGB:0.17,0.16,0.15> IGUI_RS_Radio_reply', window.detail.text)
        self.assertIn('Still here.', window.detail.text)
        # Map mark received (E07-T08): its own line kind, brick red, label only.
        log = sim.server.g.require('RadioSurvivor/RS_RadioLog')
        self.assertIsNotNone(log.add(sim.character('alice'), 145000, 'mark', 'Old mill'))
        window.changeTab(window, 'Radio')
        self.assertEqual(self.texts(alice), ['said:Walt?', 'reply:Still here.', 'mark:Old mill'])
        self.assertIn('<RGB:0.70,0.18,0.08> IGUI_RS_Radio_mark', window.detail.text)
        # Area revealed (E07-T05): its own line kind, same brick red, label only.
        self.assertIsNotNone(log.add(sim.character('alice'), 145000, 'reveal', 'Old mill'))
        window.changeTab(window, 'Radio')
        self.assertEqual(self.texts(alice), ['said:Walt?', 'reply:Still here.', 'mark:Old mill', 'reveal:Old mill'])
        self.assertIn('<RGB:0.70,0.18,0.08> IGUI_RS_Radio_reveal', window.detail.text)
        # Mission received from a voice (E11-T08): kind of place stored, translated by the notebook, brick red.
        self.assertIsNotNone(log.add(sim.character('alice'), 145000, 'mission', 'house_garage'))
        window.changeTab(window, 'Radio')
        self.assertEqual(self.texts(alice)[-1], 'mission:house_garage')
        self.assertRegex(window.detail.text,
                         r'<RGB:0\.70,0\.18,0\.08> IGUI_RS_Radio_mission\|[^|]+\|IGUI_RS_Place_house_garage')
        self.assertTrue(window.tune.isVisible(window.tune))
        # Already on the frequency: nothing queued; another frequency: the vanilla action.
        window.tune.onclick(window)
        self.assertIsNone(alice.g.QUEUED)
        window.row.khz = 146400
        window.tune.onclick(window)
        self.assertEqual((alice.g.QUEUED.mode, alice.g.QUEUED.khz), ('SetChannel', 146400))
        window.prerender(window)
        for tab in ('Contacts', 'Missions', 'Reputation', 'Radio'):
            window.changeTab(window, tab)
            self.assertTrue(window.detail.text.startswith('<RGB:'), tab)

    # Paper notebook (E06-T06) -----------------------------------------------------------------------------------

    def notebook(self, sim, name='alice', textures=False):
        c = self.client(sim, name)
        c.rt.execute(NOTEBOOK_UI)
        c.g.FAKE_TEXTURES = textures
        c.rt.execute("ISTimedActionQueue = { add = function(a) QUEUED = a end }; "
                     "ISRadioAction = { new = function(self, mode, p, radio, khz) return { mode = mode, khz = khz } end }")
        c.load('client/RS_Carnet_Client.lua')
        return c

    @staticmethod
    def heard_on(sim, name, khz, text):
        """A line kept by the authority for this character (RS_RadioLog.add), pushed to its client (HISTORY_ADD)."""
        log = sim.server.rt.eval("require('RadioSurvivor/RS_RadioLog')")
        return log.add(sim.character(name), khz, 'heard', text)

    @staticmethod
    def draws(c, kind=None, element=None):
        """Recorded draw calls (NOTEBOOK_UI), filtered by kind and by element (compared in Lua: rawequal)."""
        same = c.rt.eval('function(a, b) return rawequal(a, b) end')
        return [d for d in c.g.DRAWS.values()
                if (kind is None or d.kind == kind) and (element is None or same(d.element, element))]

    @staticmethod
    def unread(c):
        return {r['khz']: r['unread'] for r in py(c.rt.eval('History.sorted()')).values()}

    def orange_dots(self, c, element):
        return [d for d in self.draws(c, 'rect', element) if list(d.args.values())[-3:] == [0.71, 0.325, 0.11]]

    def test_radio_tab_selection_unread_dot_and_say_line(self):
        sim = self.simulation(self.tmp / 'paper')
        alice = self.notebook(sim)
        alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Walt?')")
        self.answer(sim, 'Still here.')
        self.heard_on(sim, 'alice', 146400, 'Anyone on 146.4?')
        self.assertEqual(self.unread(alice), {145000: True, 146400: True}, 'lines nobody read: dots')
        alice.g.RS_UI_Notebook.toggle()
        window = alice.g.RS_CarnetClient.window
        window.changeTab(window, 'Radio')
        # Most recent frequency first and selected: read; the other one keeps its dot (orange, next to its label).
        self.assertEqual(window.row.khz, 146400)
        self.assertFalse(alice.rt.eval('History.unread'))
        self.assertEqual(self.unread(alice), {145000: True, 146400: False})
        items = {item.item.khz: item for item in window.list['items'].values()}
        self.assertFalse(items[146400].item.unread)
        self.assertTrue(items[145000].item.unread)
        alice.g.DRAWS = alice.rt.table()
        window.list.doDrawItem(window.list, 0, items[145000])
        self.assertEqual(len(self.orange_dots(alice, window.list)), 1, 'unread dot not drawn')
        alice.g.DRAWS = alice.rt.table()
        window.list.doDrawItem(window.list, 0, items[146400])
        self.assertEqual(self.orange_dots(alice, window.list), [])
        # A new line on the frequency being read: no dot, no global indicator.
        self.heard_on(sim, 'alice', 146400, 'Anyone, again?')
        self.assertFalse(self.unread(alice)[146400])
        self.assertFalse(alice.rt.eval('History.unread'))
        # Selecting the other frequency puts its dot out; the radio is on it (no hint).
        items = {item.item.khz: item for item in window.list['items'].values()}
        window.list.onmousedown(window, items[145000].item)
        self.assertEqual(window.row.khz, 145000)
        self.assertFalse(self.unread(alice)[145000])
        self.assertIn('Still here.', window.detail.text)
        window.update(window)
        self.assertEqual(window.say.javaObject.placeholder, 'IGUI_RadioSurvivor_Talk|145.0')
        # On 146.4, while the radio stays on 145.0: hint shown, placeholder on the radio's frequency.
        window.list.onmousedown(window, items[146400].item)
        self.assertIn('Anyone on 146.4?', window.detail.text)
        sim.clock.offset += 60000
        window.update(window)
        self.assertEqual(window.say.javaObject.placeholder, 'IGUI_RadioSurvivor_Talk|145.0')
        self.assertEqual(window.sayStatus, 'IGUI_RS_RadioTunedElsewhere|145.0|146.4')
        self.assertFalse(window.sayProblem)
        # Say line: Enter sends through Talk.send (same command as the radio window), clears it, gives focus back.
        window.list.onmousedown(window, items[145000].item)
        self.assertEqual(window.row.khz, 145000)
        window.say.focus(window.say)
        window.say.setText(window.say, '  Walt, it is me.  ')
        window.say.onCommandEntered(window.say)
        self.assertEqual(self.texts(alice)[-1], 'said:Walt, it is me.')
        self.assertEqual(window.say.getText(window.say), '')
        self.assertFalse(window.say.isFocused(window.say))
        # Waiting for the answer: greyed with the reason, button disabled.
        window.update(window)
        self.assertFalse(window.say.isEditable(window.say))
        self.assertFalse(window.sendRadio.enable)
        self.assertEqual(window.sayStatus, 'IGUI_RadioSurvivor_Reject_Waiting')
        self.assertTrue(window.sayProblem)
        self.answer(sim, 'Copy.')
        window.update(window)
        self.assertEqual(window.sayStatus, 'IGUI_RadioSurvivor_Reject_Spam')
        self.assertFalse(window.say.isEditable(window.say))
        sim.clock.offset += 60000
        window.update(window)
        self.assertTrue(window.say.isEditable(window.say))
        self.assertTrue(window.sendRadio.enable)
        self.assertIsNone(window.sayStatus)
        # Transmit button: same path; an empty line sends nothing.
        before = len(self.texts(alice))
        window.sendRadio.onclick(window)
        self.assertEqual(len(self.texts(alice)), before)
        # Escape, tab change and closing give the keyboard back.
        window.say.focus(window.say)
        window.say.onOtherKey(window.say, 1)
        self.assertFalse(window.say.isFocused(window.say))
        window.say.focus(window.say)
        window.changeTab(window, 'Contacts')
        self.assertFalse(window.say.isFocused(window.say))
        self.assertFalse(window.say.isVisible(window.say))
        window.changeTab(window, 'Radio')
        window.say.focus(window.say)
        alice.g.RS_UI_Notebook.toggle()
        self.assertFalse(window.say.isFocused(window.say))

    def test_radio_without_a_radio_sends_nothing_and_says_why(self):
        sim = self.simulation(self.tmp / 'noradio')
        alice = self.notebook(sim)
        alice.rt.execute("getPlayer().inHand = false")
        alice.g.RS_UI_Notebook.toggle()
        window = alice.g.RS_CarnetClient.window
        window.changeTab(window, 'Radio')
        window.update(window)
        self.assertEqual(window.sayStatus, 'IGUI_RadioSurvivor_Reject_NoRadio')
        self.assertTrue(window.say.isEditable(window.say))
        window.say.setText(window.say, 'Hello?')
        window.sendRadio.onclick(window)
        self.assertEqual(self.texts(alice), [])
        self.assertEqual(window.say.getText(window.say), 'Hello?', 'refused text kept')

    def test_paper_drawing_with_and_without_textures_never_overflows(self):
        for textures in (False, True):
            sim = self.simulation(self.tmp / f'draw{textures}')
            alice = self.notebook(sim, textures=textures)
            alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Walt?')")
            self.answer(sim, 'Still here.')
            self.heard_on(sim, 'alice', 146400, 'Anyone?')
            alice.g.RS_UI_Notebook.toggle()
            window = alice.g.RS_CarnetClient.window
            # Smallest window: every label measured (7 px per character in the double) stays on its page.
            window.setWidth(window, window.minimumWidth)
            window.setHeight(window, window.minimumHeight)
            for tab in window.tabs.values():
                tab.onclick(window)
                name = tab.rsTab.name
                self.assertEqual(window.tab, name)
                alice.g.DRAWS = alice.rt.table()
                window.prerender(window)
                window.render(window)
                for t in window.tabs.values():
                    t.prerender(t)
                for item in window.list['items'].values():
                    window.list.doDrawItem(window.list, 0, item)
                geo = window.geo
                self.assertGreaterEqual(len(self.draws(alice, 'text', window)), 2, name)
                self.assertTrue(self.draws(alice, 'text', window.list) or name != 'Radio', name)
                for d in self.draws(alice, 'text', window):
                    args = list(d.args.values())
                    self.assertLessEqual(args[1] + len(args[0]) * 7, geo.paperRight, (name, args[0]))
                for d in self.draws(alice, 'text', window.list):
                    args = list(d.args.values())
                    self.assertLessEqual(args[1] + len(args[0]) * 7, window.list.width, (name, args[0]))
                for t in window.tabs.values():
                    self.assertGreaterEqual(t.height, 18 + 14, 'bookmark smaller than a button')
                    self.assertEqual(t.x + t.width, window.width)
                    self.assertLessEqual(t.rsOver + 8 + len(t.rsLabel) * 7, t.width, t.rsLabel)
                self.assertGreaterEqual(window.detail.width, 200, name)
                if name == 'Radio':
                    self.assertGreaterEqual(window.tune.y, window.list.y + window.list.height)
                    self.assertLessEqual(window.say.x + window.say.width, window.sendRadio.x)
                    self.assertLessEqual(window.sendRadio.x + window.sendRadio.width, geo.paperRight)
                tiled = self.draws(alice, 'tiled', window)
                self.assertEqual(len(tiled), 2 if textures else 0, 'paper and binding tiled only when present')
            mine = [a for a in alice.g.TEXTURES_ASKED.values() if 'RadioSurvivor' in a]
            self.assertEqual(len(mine), 5)
            self.assertTrue(all('/RS_Notebook_' in a for a in mine), mine)

    def check_scrolling_and_widths(self, c, window, label):
        """One frame (Java update, then render), then: no vanilla scroll bar, texts inside what the player sees, the
        thin paper bar on the right edge only when the content does not fit."""
        c.g.DRAWS = c.rt.table()
        c.g.FRAME(window)
        c.g.FRAME(window)
        for name in ('list', 'detail'):
            e = window[name]
            if not e.isVisible(e):
                continue
            bar = c.g.VANILLA_BAR(e)
            if bar is not None:
                j = bar.javaObject
                self.assertGreaterEqual(j.x + j.width, e.width - 1, (label, name, 'vanilla bar inside the panel', j.x))
            self.assertIsNone(bar, (label, name, 'vanilla scroll bar shown'))
            thin = window.scrollBar(window, e)
            overflow = e.getScrollHeight(e) > e.height + 1
            self.assertEqual(thin is not None, overflow, (label, name))
            if thin is not None:
                self.assertEqual(thin.x + thin.w, e.x + e.width, (label, name))
                self.assertGreaterEqual(thin.thumbY, e.y)
                self.assertLessEqual(thin.thumbY + thin.thumbH, e.y + e.height)
        right = c.g.VISIBLE_RIGHT(window.list)
        for d in self.draws(c, 'text', window.list):
            args = list(d.args.values())
            self.assertLessEqual(args[1] + len(args[0]) * 7, right, (label, 'list text cut', args[0]))
        detail = window.detail
        right = c.g.VISIBLE_RIGHT(detail)
        thin = window.scrollBar(window, detail)
        if thin is not None:
            right = min(right, thin.x - detail.x)
        self.assertTrue(len(detail.lines) > 0, label)
        for text in detail.lines.values():
            self.assertLessEqual(detail.marginLeft + len(text) * 7, right, (label, 'detail text cut', text))

    def test_scroll_bars_text_widths_and_npc_notice_by_tab(self):
        # Solo test 2026-10-09 (E06-T06): vanilla scroll bars in the middle of the frequency list and of the
        # conversation, "140.8 MH" cut, no-NPC notice at the top of the Radio conversation.
        sim = self.simulation(self.tmp / 'scroll', provider=False)
        alice = self.notebook(sim)
        # Eight frequencies at most are kept (test_frequencies_bounded_least_recent_forgotten).
        for i in range(8):
            self.heard_on(sim, 'alice', 140800 + i * 200, f'Line {i} on this frequency, long enough to wrap on paper.')
        for i in range(30):
            self.heard_on(sim, 'alice', 140800, f'Conversation line {i}: anyone hearing this, please answer me now.')
        alice.g.RS_UI_Notebook.toggle()
        window = alice.g.RS_CarnetClient.window
        window.setHeight(window, window.minimumHeight)
        window.changeTab(window, 'Radio')
        self.assertNotIn('IGUI_RS_NoNPCProvider', window.detail.text, 'NPC notice on the Radio tab')
        self.check_scrolling_and_widths(alice, window, 'Radio')
        self.assertIsNotNone(window.scrollBar(window, window.list), 'eight frequencies fit?')
        self.assertIsNotNone(window.scrollBar(window, window.detail), 'thirty lines fit?')
        # The frequency label of a row is never cut: measured column.
        items = list(window.list['items'].values())
        self.assertLessEqual(10 + len(items[0].text) * 7 + 9 + 6, window.list.width)
        for tab in ('Contacts', 'Missions', 'Reputation', 'Radio'):
            window.changeTab(window, tab)
            if tab == 'Contacts':
                self.assertIn('IGUI_RS_NoNPCProvider', window.detail.text)
            self.check_scrolling_and_widths(alice, window, tab)
        # Window resized (ISResizeWidget): smallest, then larger; layout and wrapping follow the new width.
        for w, h in ((window.minimumWidth, window.minimumHeight), (1400, 900), (window.minimumWidth, 700)):
            window.setWidth(window, w)
            window.setHeight(window, h)
            for tab in ('Radio', 'Contacts', 'Reputation'):
                window.changeTab(window, tab)
                self.check_scrolling_and_widths(alice, window, f'{tab} {w}x{h}')


# Solo machine (isClient() and isServer() false): client and server files in one Lua state, as the game loads them
# (shared, client, then server). sendClientCommand follows zombie/spnetwork/SinglePlayerClient.java:120-140: the
# packet is queued (SinglePlayerServer.addIncoming, MainLoopNetData) and OnClientCommand fires at the next
# SinglePlayerServer.update (:138-170, :197-222) with nil for an empty table (`args2 != null && !args2.isEmpty()`).
# sendServerCommand does nothing in solo: the mod calls the client handlers directly.
SOLO_NET = r'''
SOLO_QUEUE = {}
local function copy(t)
    local out, empty = {}, true
    for k, v in pairs(t) do
        local kt, vt = type(k), type(v)
        if kt == 'string' or kt == 'number' then
            if vt == 'table' then out[k] = copy(v) or {} ; empty = false
            elseif vt == 'string' or vt == 'number' or vt == 'boolean' then out[k] = v; empty = false end
        end
    end
    if empty then return nil end
    return out
end
sendClientCommand = function(player, module, command, args)
    SOLO_QUEUE[#SOLO_QUEUE + 1] = { player = player, module = module, command = command,
        args = type(args) == 'table' and copy(args) or nil }
end
function flushNet()
    while #SOLO_QUEUE > 0 do
        local batch = SOLO_QUEUE
        SOLO_QUEUE = {}
        for _, m in ipairs(batch) do fire('OnClientCommand', m.module, m.command, m.player, m.args) end
    end
end
'''



class VoiceKnownTests(unittest.TestCase):
    """E06-T07 : le carnet connaît la voix d'une fréquence (nom, heures d'écoute) après un contact, une note lue ou une
    fréquence donnée, jamais après une phrase restée sans réponse. Vrai RadioSurvivor_Server (Walt, 145.0, à toute
    heure) et vrai client RS_RadioHistory."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_voice_known_'))
        self.it = IntegrationTests()
        self.sim = self.it.simulation(self.tmp / 'mp')
        self.alice = self.it.client(self.sim, 'alice')
        self.bob = self.it.client(self.sim, 'bob')
        self.walt = self.sim.server.rt.eval("require('RadioSurvivor/RS_Personas').get('walt')")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def voice(self, c, khz=145000):
        rows = [convert(r) for r in lua_list(c.rt.eval('History.sorted()'))]
        row = [r for r in rows if r['khz'] == khz]
        return row[0].get('voice') if row else 'absent'

    def test_reply_makes_the_voice_known_with_its_hours(self):
        self.assertTrue(self.alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Walt?')"))
        self.assertIsNone(self.voice(self.alice), 'voice told before any answer')
        self.it.answer(self.sim, 'Walt here.')
        self.assertEqual(self.voice(self.alice), {'id': 'walt', 'name': self.walt.name, 'hours': {}})
        self.assertIsNone(self.alice.rt.eval("History.hoursText(History.sorted()[1].voice)"))
        # Hours from the sheet, sent again with the whole history (re-read on opening).
        self.sim.server.rt.execute("require('RadioSurvivor/RS_Personas').get('walt').listen = "
                                   "{ { from = 1140, to = 1320 }, { from = 1380, to = 180 } }")
        self.alice.rt.execute('History.request()')
        self.assertEqual(self.alice.rt.eval("History.hoursText(History.sorted()[1].voice)"),
                         '19:00-22:00, 23:00-03:00')
        # Kept by the private state (restart).
        cid = self.sim.character('alice')
        self.assertEqual(self.sim.state().characters[cid].radio.frequencies[1].voice, 'walt')

    def test_heard_voice_line_tells_the_voice_a_player_line_does_not(self):
        self.assertTrue(self.alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Anyone here?')"))
        self.bob.rt.execute("Talk.onDeviceText('g', '', -1, -1, -1, 'Anyone here?', getPlayer().radio)")
        self.assertIsNone(self.voice(self.bob), 'a player phrase told the voice')
        self.it.answer(self.sim, 'Walt here, I hear you.')
        self.bob.rt.execute("Talk.onDeviceText('g', '', -1, -1, -1, 'Walt here, I hear you.', getPlayer().radio)")
        self.assertEqual(self.voice(self.bob)['id'], 'walt')

    def test_silence_never_tells_a_voice(self):
        self.alice.rt.execute('getPlayer().radio.device.channel = 151200')
        self.sim.server.g.PLAYERS['alice'].radio.device.channel = 151200
        self.assertTrue(self.alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Hello?')"))
        self.assertIsNone(self.voice(self.alice, 151200))

    def note(self, khz=145000, voice='walt', item_id=7001):
        """A frequency note in alice's inventory on the server (ModData written by the authority)."""
        self.sim.server.rt.execute(f"""
            local it = item('RadioSurvivor.NoteWalt', {item_id})
            it.md = {{ RadioSurvivorNote = {{ voice = '{voice}', khz = {khz} }} }}
            it.hasModData = function(self) return true end
            it.getModData = function(self) return self.md end
            PLAYERS.alice:getInventory():AddItem(it)""")

    def read(self, item_id=7001):
        self.alice.rt.execute(f"sendClientCommand(getPlayer(), 'RadioSurvivor', 'note_read', {{ itemId = {item_id} }})")

    def test_note_read_writes_the_voice_once_and_is_checked(self):
        self.read()
        self.assertEqual(self.voice(self.alice), 'absent', 'note outside the inventory accepted')
        self.note(voice='darlene')
        self.read()
        self.assertEqual(self.voice(self.alice), 'absent', 'note of another voice accepted')
        self.note(item_id=7002)
        self.read(7002)
        self.assertEqual(self.voice(self.alice)['id'], 'walt')
        self.assertEqual(self.it.texts(self.alice), ['note:walt'])
        self.read(7002)
        self.assertEqual(self.it.texts(self.alice), ['note:walt'], 'note line written twice')
        self.assertEqual(self.voice(self.bob), 'absent')

    def test_reader_tells_the_server_when_a_note_opens(self):
        sent = []
        self.alice.g.sendClientCommand = lambda p, module, command, args: sent.append((module, command,
                                                                                       convert(args)))
        self.alice.rt.execute("""
            ISReadABook = { displayPrintMedia = function(self) SHOWN = self.item.md.printMedia.text end,
                startLoadingPrintMediaTextures = function() end }
            package.loaded['TimedActions/ISReadABook'] = true
            require 'RadioSurvivor/RS_NotesReader'
            local function note(khz)
                local md = { printMedia = { id = 'RadioSurvivor_NoteWalt', title = 't', info = 'i', text = 'x' },
                    RadioSurvivorNote = { voice = 'walt', khz = khz } }
                return { md = md, hasModData = function() return true end, getModData = function(s) return s.md end,
                    getID = function() return 4242 end }
            end
            ISReadABook.displayPrintMedia({ item = note(145000), character = getPlayer() })
            ISReadABook.displayPrintMedia({ item = note(nil), character = getPlayer() })""")
        self.assertEqual(sent, [('RadioSurvivor', 'note_read', {'itemId': 4242})])

    def test_notebook_shows_the_voice_and_its_hours(self):
        self.sim.server.rt.execute("require('RadioSurvivor/RS_Personas').get('walt').listen = "
                                   "{ { from = 1140, to = 1320 } }")
        alice = self.it.notebook(self.sim, 'carol')
        # getTextOrNull of the game: nil for a missing key (the shared stub returns the key).
        alice.rt.execute("getTextOrNull = function(k) if k == 'IGUI_RS_Voice_walt' then return 'Walt' end end")
        self.assertTrue(alice.rt.eval("Talk.send(getPlayer(), getPlayer().radio, 'Walt?')"))
        self.it.answer(self.sim, 'Walt here.')
        alice.g.RS_UI_Notebook.toggle()
        window = alice.g.RS_CarnetClient.window
        window.changeTab(window, 'Radio')
        self.assertEqual(window.row.khz, 145000)
        self.assertIn('IGUI_RS_RadioVoice|Walt|IGUI_RS_RadioHours|19:00-22:00', window.detail.text)
        self.assertEqual(alice.g.RS_UI_Notebook.rowSecondLine(window.row), 'Walt')
        # A frequency without a known voice keeps its last line, and no voice line on its page.
        self.it.heard_on(self.sim, 'carol', 146400, 'Anyone?')
        window.changeTab(window, 'Radio')
        self.assertEqual(window.row.khz, 146400)
        self.assertNotIn('IGUI_RS_RadioVoice', window.detail.text)
        self.assertEqual(alice.g.RS_UI_Notebook.rowSecondLine(window.row), 'IGUI_RS_RadioLast|' + window.row.when)

class SoloScenarioTests(unittest.TestCase):
    """Real solo session (reported 2026-10-09, save rstest-solo): no NPC provider, notebook never opened, talk with
    Walt, spontaneous call, then notebook opened, then reload. The Radio tab must show the conversation."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_radio_solo_'))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def boot(self, new_world, saved_md=None):
        from test_carnet import STUBS
        from test_protocol import Game, Clock
        self.clock = getattr(self, 'clock', None) or Clock()
        game = Game('solo', self.tmp, self.clock)
        g = game.g
        game.rt.execute(STUBS)
        game.rt.execute(SOLO_NET)
        g.getWorld = lambda: game.rt.eval("{getGameMode=function() return 'Sandbox' end, "
                                          "getWorld=function() return 'rstest-solo' end}")
        # Only the single-argument draw decides a spontaneous call (ZombRand(call_one_in) == 0).
        game.rt.execute("ZombRand = function(a, b) if b then return a end return 0 end")
        player = g.enhance(g.makePlayer('kate'))
        player.isPlayer = True
        for k, v in (saved_md or {}).items():
            player.md[k] = v
        g.getPlayer = lambda: player
        g.getSpecificPlayer = lambda n: player
        game.rt.execute("getText = function(k, ...) local t = { k } for i = 1, select('#', ...) do "
                        "t[#t + 1] = tostring(select(i, ...)) end return table.concat(t, '|') end")
        game.rt.execute("local d = getPlayer().radio.device; function d:getPower() return 1 end")
        # Game load order: client files, then server files (the solo game loads both).
        game.load('client/RadioSurvivor/RS_Client.lua', 'client/RadioSurvivor_Client.lua',
                  'server/RS_Carnet_Server.lua', 'server/RadioSurvivor_Server.lua')
        game.rt.execute("Talk = require('RadioSurvivor/RS_RadioTalk'); History = Talk.History; "
                        "function texts(khz) local out = {} for _, l in ipairs(History.lines(khz)) do "
                        "out[#out + 1] = l.kind .. ':' .. l.text end return out end")
        g.fire('OnLoadRadioScripts', g.MANAGER, new_world)
        g.fire('OnInitGlobalModData', new_world)
        g.fire('OnGameStart')
        self.game, self.g, self.player = game, g, player
        self.frame()
        return game

    def frame(self, n=1):
        for _ in range(n):
            self.g.fire('OnTickEvenPaused')
            self.g.fire('OnTick')
            self.g.flushNet()

    def characters(self):
        return convert(self.g.RS_CarnetServer.store.data.characters)

    def texts(self, khz=145000):
        return lua_list(self.g.texts(khz))

    def answer(self, text):
        requests = (self.tmp / 'requests.txt').read_text(encoding='utf-8').splitlines()
        req = [l[4:] for l in requests if l.startswith('req=')][-1]
        (self.tmp / 'responses.txt').write_text(f'resp={req}\nline={text}\nend\n', encoding='utf-8')
        self.clock.offset += 1000
        self.frame()

    def test_history_without_provider_notebook_opened_late_and_reload(self):
        self.boot(True)
        self.assertEqual(self.game.rt.eval("require('RadioSurvivor/RS_NPCProvider').active().name"), 'none')
        # The first hello has no stored character, no world and no run: it must still bind a notebook character.
        characters = self.characters()
        self.assertEqual(len(characters), 1, 'no notebook character after the first hello (empty args -> nil)')
        cid = next(iter(characters))
        self.assertEqual(self.player.md.RS_CarnetCharacter, cid)

        # Notebook never opened: talk with Walt, he answers.
        self.assertTrue(self.g.Talk.send(self.player, self.player.radio, 'Walt, are you there?'))
        self.frame()
        self.answer('Walt here.')
        self.assertEqual(self.texts(), ['said:Walt, are you there?', 'reply:Walt here.'])
        self.assertTrue(self.g.History.unread, 'orange indicator off')

        # Spontaneous call of Walt, received by the radio (OnDeviceText): heard.
        self.g.finishAiring()
        self.g.fire('EveryHours')
        self.clock.offset += 31000
        self.frame()
        call = lua_list(self.g.BROADCASTS[len(self.g.BROADCASTS)])
        for line in call:
            self.g.Talk.onDeviceText('g', '', -1, -1, -1, line, self.player.radio)
        self.frame()
        heard = [t for t in self.texts() if t.startswith('heard:')]
        self.assertEqual(len(heard), 1, self.texts())

        # Notebook opened afterwards: Radio tab shows the conversation, indicator cleared when read.
        self.game.rt.execute(NOTEBOOK_UI)
        self.game.load('client/RS_Carnet_Client.lua')
        self.g.RS_UI_Notebook.toggle()
        self.frame()
        window = self.g.RS_CarnetClient.window
        window.changeTab(window, 'Radio')
        self.assertFalse(self.g.History.unread)
        self.assertEqual(window.row.khz, 145000)
        self.assertIn('Walt here.', window.detail.text)
        self.assertNotIn('IGUI_RS_Empty_Radio', window.detail.text)
        expected = self.texts()
        self.assertTrue(self.g.RS_CarnetServer.store.save())

        # Reload: same character (player modData saved with the player), history read again.
        saved = {'RS_CarnetCharacter': self.player.md.RS_CarnetCharacter}
        self.boot(False, saved)
        self.assertEqual(list(self.characters()), [cid])
        self.assertEqual(self.g.RS_CarnetClient.character, cid)
        self.g.History.request()
        self.frame()
        self.assertEqual(self.texts(), expected)

    def test_belt_radio_refused_in_solo_hand_radio_talks(self):
        # Décision 4 de Belt Walkie-Talkie : talkie à la ceinture (accroché, ni en main ni sur le dos) : option
        # « Parler sur … » proposée mais grisée (« prenez le talkie en main »), rien d'envoyé. Rangé dans
        # l'inventaire ou dans un sac : aucune option. Repris en main : phrase acceptée, réponse de Walt dans
        # l'historique.
        self.boot(True)
        self.game.rt.execute("local p = getPlayer(); p.inHand = false; p.radio.id = 4242; p.radio.container = p.inv; "
                             "p.inv.items[#p.inv.items + 1] = p.radio; p.attached = p.radio")
        self.assertIsNone(self.g.getPlayer().getEquipedRadio(self.player))
        self.assertEqual(self.g.talk(self.player, 'Walt, belt radio.'), 'grisee')
        self.assertEqual(self.g.TALK_TOOLTIP, 'IGUI_RadioSurvivor_NotEquipped')
        self.frame()
        self.assertNotIn('Walt, belt radio.', self.requests())
        self.game.rt.execute("getPlayer().attached = nil")
        self.assertEqual(self.g.talk(self.player, 'From the pocket.'), "pas d'option")
        self.game.rt.execute("getPlayer().radio.container = { bag = true }")
        self.assertEqual(self.g.talk(self.player, 'From the bag.'), "pas d'option")
        self.game.rt.execute("local p = getPlayer(); p.radio.container = p.inv; p.inHand = true")
        self.assertEqual(self.g.talk(self.player, 'Walt, hand radio.'), 'ok')
        self.frame()
        self.assertEqual(lua_list(self.player.halos), [])
        self.assertIn('Walt, hand radio.', self.requests())
        self.answer('Copy, hand.')
        self.assertEqual(self.texts(), ['said:Walt, hand radio.', 'reply:Copy, hand.'])

    def requests(self) -> str:
        path = self.tmp / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''


if __name__ == '__main__':
    unittest.main(verbosity=1)
