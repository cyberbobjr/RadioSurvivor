"""Banc hors jeu de la suite en jeu rs.notebook.voices (E06-T07 : voix et heures d'écoute d'une fréquence connue dans
l'onglet Radio du carnet) et de ses étapes client (RST_PeerChecksVoices.lua).

    python tests/test_rs_notebook_voices_suite.py

La suite est jouée par le VRAI moteur RST (RST.lua, RST_Steps.lua, RST_PeerChecksRadio.lua, RST_PeerChecksVoices.lua)
sur le serveur dédié simulé de tests/test_carnet.py (Simulation) avec deux clients : vrai RadioSurvivor_Server (commandes
talk et note_read, RS_RadioLog, RS_Personas : Walt sur sa fréquence d'exemple), vrai RS_Carnet_Server, vrai
RS_RadioHistory sur chaque client et vraie fenêtre du carnet (RS_Notebook, doublures d'interface NOTEBOOK_UI) sur le
client demandeur. Doublures propres à ce banc : la radio tenue (RST.RSHelpers.radioInHand rend le talkie déjà en main
de la doublure de joueur) et le don d'objet (RST.Fixtures.giveItem crée la note et appelle le vrai OnCreate des notes,
RadioSurvivorNotes.onCreate, comme Item.InstanceItem du jeu). Chaque critère est contredit par un défaut injecté que la
suite doit faire échouer. Ce banc ne prouve ni l'API Java ni le réseau réel : la campagne MP à deux clients reste
nécessaire.
"""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_radio_history as radio_history  # noqa: E402
from test_carnet import NOTEBOOK_UI, TESTS_SHARED  # noqa: E402,F401

SUITE = TESTS_SHARED / 'RST' / 'suites' / 'RS_NotebookVoices.lua'
NAME = 'rs.notebook.voices'
SILENCE = 'a sentence left without answer does not make the voice known (E06-T07)'
NOTE = "a note read shows voice and hours in the reader's Radio tab only (E06-T07)"

# Python callables are userdata for type(): the globals RST tests with type(x) == "function" become Lua functions.
RST_LOAD = f'''
local player, writer = getPlayer, getFileWriter
if player ~= nil then getPlayer = function() return player() end end
getFileWriter = function(...) return writer(...) end
local base = getWorld
getWorld = function() local w = base() w.getWorld = function() return "rstest-voices" end return w end
package.path = [[{TESTS_SHARED.as_posix()}/?.lua;]] .. package.path
require "RST/RST"
RST.clock = function() return getTimestampMs() end
dofile([[{SUITE.as_posix()}]])
'''

# Fixture doubles of the server machine: the walkie-talkie already held by the player double, tuned to khz; the note
# created by item() of test_carnet.py with its ModData, filled by the real OnCreate of the notes.
SERVER_FIXTURES = r'''
RST.RSHelpers.radioInHand = function(t, p, fullType, khz)
    p.radio.device.channel = khz
    return p.radio, p.radio.device
end
local NoteItemDouble = {
    getType = function(self) return string.match(self.kind, "%.(.+)$") end,
    hasModData = function(self) return true end,
    getModData = function(self) return self.md end,
}
RST.Fixtures.giveItem = function(t, p, fullType)
    local it = item(fullType)
    it.md = {}
    setmetatable(it, { __index = NoteItemDouble })
    RadioSurvivorNotes.onCreate(it)
    local inv = p:getInventory()
    inv:AddItem(it)
    t:defer(function() inv:Remove(it) end, "giveItem " .. fullType)
    return { it }
end
'''


class NotebookVoicesSuiteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_notebook_voices_'))
        self.it = radio_history.IntegrationTests()
        self.sim = self.it.simulation(self.tmp / 'mp')
        self.alice = self.it.notebook(self.sim, 'alice')
        self.bob = self.it.client(self.sim, 'bob')
        self.server = self.sim.server
        # The real frequency provider of the notes (authority): loot tables of the game reduced to empty lists.
        self.server.rt.execute('ProceduralDistributions = { list = {} }; VehicleDistributions = {}; '
                               'package.preload["Items/ProceduralDistributions"] = function() return true end; '
                               'package.preload["Vehicles/VehicleDistributions"] = function() return true end; '
                               'require "RadioSurvivor/RS_NotesServer"')
        for machine in (self.server, self.alice, self.bob):
            machine.rt.execute(RST_LOAD)
        self.server.rt.execute(SERVER_FIXTURES)
        self.server.g.HOUR = 12   # game time 12:05: Walt's test window 14:05-16:05 is ahead

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def frame(self):
        self.sim.clock.offset += 100
        self.sim.tick()
        for c in (self.alice, self.bob):
            c.g.fire('OnTick')

    def run_suite(self, test=None):
        start = self.server.rt.eval('function(p, test) return RST.start({ suite = "' + NAME + '", test = test }, '
                                    '{ ctx = { player = p } }) end')
        self.assertIs(start(self.server.g.PLAYERS.alice, test), True)
        for _ in range(3000):
            if not self.server.rt.eval('RST.running()'):
                break
            self.frame()
        report = self.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return {r.test: (r.status, r.message) for r in report.results.values()}

    def history(self, name):
        cid = self.sim.character(name)
        radio = self.server.rt.eval('function(cid) return RST.radioOf(cid) end')(cid)
        return radio_history.convert(radio) if radio is not None else None

    def test_suite_passes_and_puts_everything_back(self):
        self.alice.rt.execute("Talk.send(getPlayer(), getPlayer().radio, 'Walt?')")
        self.it.answer(self.sim, 'Walt here.')
        self.sim.clock.offset += 60000   # talk cooldown of alice over
        before = {name: self.history(name) for name in ('alice', 'bob')}
        listen = self.server.rt.eval("#require('RadioSurvivor/RS_Personas').get('walt').listen")
        results = self.run_suite()
        self.assertEqual({k: v[0] for k, v in results.items()}, {SILENCE: 'PASS', NOTE: 'PASS'}, results)
        self.assertEqual({name: self.history(name) for name in ('alice', 'bob')}, before, 'radio histories changed')
        self.assertEqual(self.server.rt.eval("#require('RadioSurvivor/RS_Personas').get('walt').listen"), listen)
        self.assertEqual(self.alice.rt.eval('History.sorted()[1].voice.id'), 'walt', 'client copy not sent again')
        self.assertFalse(self.alice.rt.eval('RS_CarnetClient.window and RS_CarnetClient.window:isVisible()'),
                         'notebook window left open')

    def test_fails_when_the_reader_client_does_not_receive_the_voice(self):
        # Defect: the history sent to the client drops the voice (Log.voiceInfo always nil).
        self.server.rt.execute("require('RadioSurvivor/RS_RadioLog').voiceInfo = function() return nil end")
        status, message = self.run_suite('note read')[NOTE]
        self.assertEqual(status, 'FAIL')
        self.assertIn('requester: voice of the frequency in the Radio tab', message)

    def test_fails_when_the_voice_leaks_to_the_second_client(self):
        # Defect: the note read also writes the voice for every other bound character.
        self.server.rt.execute("""
            local Log = require('RadioSurvivor/RS_RadioLog')
            local read = Log.noteRead
            Log.noteRead = function(player, args)
                local line = read(player, args)
                local me = Log.characterOf(player)
                for _, cid in pairs(RS_CarnetServer.bound) do
                    if cid ~= me then Log.add(cid, 145000, 'note', 'walt', 'walt') end
                end
                return line
            end""")
        status, message = self.run_suite('note read')[NOTE]
        self.assertEqual(status, 'FAIL')
        self.assertIn('client bob', message)

    def test_fails_when_a_sentence_without_answer_tells_the_voice(self):
        # Defect: a sentence said on a voice frequency marks the voice (Log.spoken as if it were a contact).
        self.server.rt.execute("""
            local Log = require('RadioSurvivor/RS_RadioLog')
            Log.spoken = function(player, khz, text)
                local cid = Log.characterOf(player)
                if cid then Log.add(cid, khz, 'said', text, 'walt') end
            end""")
        status, message = self.run_suite('without answer')[SILENCE]
        self.assertEqual(status, 'FAIL')
        self.assertIn('voice known on the server after a sentence without answer', message)

    def test_fails_when_the_page_does_not_show_the_hours(self):
        # Defect: the Radio page of the client loses the hours line (History.hoursText always nil on the page).
        self.alice.rt.execute("""
            local Notebook = require('RadioSurvivorCore/RC_Notebook')
            local showRadio = Notebook.showRadio
            Notebook.showRadio = function(self, row, text)
                local voice = row.voice
                row.voice = nil
                showRadio(self, row, text)
                row.voice = voice
            end""")
        status, message = self.run_suite('note read')[NOTE]
        self.assertEqual(status, 'FAIL')
        self.assertIn('requester: hours missing on the page', message)


if __name__ == '__main__':
    unittest.main()
