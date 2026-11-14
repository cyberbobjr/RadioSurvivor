"""Banc hors jeu de la suite en jeu rs.actions.share (E07-T10 : fréquence d'une autre voix donnée exceptionnellement,
RS_ShareFrequency.lua).

    python tests/test_rs_share_suite.py

La suite est jouée par le VRAI moteur RST (RST.lua, RST_Steps.lua, RST_PeerChecksRadio.lua, RST_PeerChecksVoices.lua)
sur le serveur dédié simulé de tests/test_carnet.py (Simulation) avec deux clients : vrai RadioSurvivor_Server, vrais
RS_Actions, RS_MissionVoice (exécuteur share_frequency), RS_VoiceBonds, RS_RadioLog, RS_Personas (Walt et Darlene
installés et servis), vrai RC_Reputation, vrai RS_Carnet_Server, vrai RS_RadioHistory sur chaque client. Doublure
propre à ce banc : le mode debug (isDebugEnabled, exigé par RC_Reputation.testSetLevel). Chaque critère est contredit
par un défaut injecté que la suite doit faire échouer : partage sans lien, voix livrée aussi au second client, voix
absente de la copie du client demandeur, voix déjà connue redonnée. Ce banc ne prouve ni l'API Java ni le réseau réel : la campagne MP à deux clients reste
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
from test_carnet import Simulation, TESTS_SHARED  # noqa: E402
from test_protocol import MOD  # noqa: E402

SUITE = TESTS_SHARED / 'RST' / 'suites' / 'RS_ShareFrequency.lua'
NAME = 'rs.actions.share'
BOND = 'a voice presents another voice after several exchanges, and not before (E07-T10)'
GOOD = 'a good reputation is a bond, no exchange needed (E07-T10)'

# Python callables are userdata for type(): the globals RST tests with type(x) == "function" become Lua functions.
RST_LOAD = f'''
local player, writer = getPlayer, getFileWriter
if player ~= nil then getPlayer = function() return player() end end
getFileWriter = function(...) return writer(...) end
local base = getWorld
getWorld = function() local w = base() w.getWorld = function() return "rstest-share" end return w end
isDebugEnabled = function() return true end
package.path = [[{TESTS_SHARED.as_posix()}/?.lua;]] .. package.path
require "RST/RST"
RST.clock = function() return getTimestampMs() end
dofile([[{SUITE.as_posix()}]])
'''


class ShareSuiteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_share_suite_'))
        self.it = radio_history.IntegrationTests()
        sim = self.sim = Simulation(self.tmp / 'mp')
        (sim.path / 'personas').mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MOD / 'personas/darlene.txt', sim.path / 'personas/darlene.txt')
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        sim.server.g.WORLD_AGE_HOURS = 30
        self.alice = self.it.client(sim, 'alice')
        self.bob = self.it.client(sim, 'bob')
        self.server = sim.server
        for machine in (self.server, self.alice, self.bob):
            machine.rt.execute(RST_LOAD)

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

    def snapshot(self):
        """Radio histories, bonds and last share day of both characters, reputation of alice, clock of the bonds."""
        out = {}
        for name in ('alice', 'bob'):
            cid = self.sim.character(name)
            radio = self.server.rt.eval('function(cid) return RST.radioOf(cid) end')(cid)
            rec = self.sim.state().characters[cid]
            out[name] = (radio_history.convert(radio) if radio is not None else None,
                         radio_history.convert(rec.voiceBonds) if rec.voiceBonds is not None else None,
                         rec.lastShareDay)
        out['rep'] = self.server.rt.eval(
            "function(cid) local R = require('RadioSurvivorCore/RC_Reputation'); R.ensure(); "
            "return R.scoreOf(cid) end")(self.sim.character('alice'))
        out['today'] = self.server.rt.eval("require('RadioSurvivorCore/RC_Reputation').today()")
        out['counters'] = self.server.rt.eval(
            "function() local n = 0 for id in pairs(require('RadioSurvivor/RS_State').data.actionCounters or {}) do "
            "if string.find(id, 'rstest_share_', 1, true) then n = n + 1 end end return n end")()
        return out

    def test_suite_passes_and_puts_everything_back(self):
        self.alice.rt.execute("Talk.send(getPlayer(), getPlayer().radio, 'Walt?')")
        self.it.answer(self.sim, 'Walt here.')
        before = self.snapshot()
        results = self.run_suite()
        self.assertEqual({k: v[0] for k, v in results.items()}, {BOND: 'PASS', GOOD: 'PASS'}, results)
        self.assertEqual(self.snapshot(), before, 'state not put back')
        self.assertEqual(self.alice.rt.eval('History.sorted()[1].voice.id'), 'walt', 'client copy not sent again')

    def test_fails_when_a_voice_shares_without_a_bond(self):
        # Defect: the bond is never checked.
        self.server.rt.execute("require('RadioSurvivor/RS_VoiceBonds').allowed = function() return true end")
        status, message = self.run_suite('several exchanges')[BOND]
        self.assertEqual(status, 'FAIL')
        self.assertIn('share without any exchange', message)

    def test_fails_when_the_voice_leaks_to_the_second_client(self):
        # Defect: the shared voice is also written for every other bound character.
        self.server.rt.execute("""
            local Log = require('RadioSurvivor/RS_RadioLog')
            local add = Log.add
            Log.add = function(cid, khz, kind, text, voice)
                local line = add(cid, khz, kind, text, voice)
                if kind == 'reply' and voice ~= nil then
                    for _, other in pairs(RS_CarnetServer.bound) do
                        if other ~= cid then add(other, khz, kind, text, voice) end
                    end
                end
                return line
            end""")
        status, message = self.run_suite('several exchanges')[BOND]
        self.assertEqual(status, 'FAIL')
        self.assertIn('client bob', message)

    def test_fails_when_the_requester_client_does_not_receive_the_voice(self):
        # Defect: the history sent to the clients drops the voice (Log.voiceInfo always nil).
        self.server.rt.execute("require('RadioSurvivor/RS_RadioLog').voiceInfo = function() return nil end")
        status, message = self.run_suite('several exchanges')[BOND]
        self.assertEqual(status, 'FAIL')
        self.assertIn('requester: voice of the shared frequency in the Radio tab', message)

    def test_fails_when_a_known_voice_is_given_again(self):
        # Defect: the notebook is never asked whether the voice is already known.
        self.server.rt.execute("require('RadioSurvivor/RS_RadioLog').knowsVoice = function() return false end")
        status, message = self.run_suite('several exchanges')[BOND]
        self.assertEqual(status, 'FAIL')
        self.assertIn('target already known', message)


if __name__ == '__main__':
    unittest.main()
