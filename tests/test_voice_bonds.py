"""Fréquence d'une autre voix donnée exceptionnellement (E07-T10) : server/RadioSurvivor/RS_VoiceBonds.lua et l'action
share_frequency (RS_MissionVoice) jugée par le vrai RS_Actions ; lupa, Lua 5.1.

    python RadioSurvivor/tests/test_voice_bonds.py

Vrai RadioSurvivor_Server et vrai RS_Carnet_Server (simulation de tests/test_carnet.py), Walt (145.0, shares=darlene,
nightowl) et Darlene installés. Couvre : refus sans lien (moins de 4 réponses ou un seul jour de jeu), lien par les
réponses réellement diffusées ou par une bonne réputation ; une voix encore inconnue du carnet seulement, inscrite avec
sa voix (E06-T07) ; une fois par 7 jours de jeu pour une voix et un personnage, une fois par 3 jours pour un
personnage ; rien à présenter quand toutes les voix de shares sont connues. Doublures du jeu : ne prouve pas l'API Java.
"""
from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, convert
from test_radio_history import IntegrationTests
from test_protocol import MOD, lua_list

SHARE = [{'type': 'share_frequency'}]


class VoiceBondsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_voice_bonds_'))
        sim = self.sim = Simulation(self.tmp / 'bonds')
        (sim.path / 'personas').mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MOD / 'personas/darlene.txt', sim.path / 'personas/darlene.txt')
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        self.alice = sim.add_client('alice')
        self.rt, self.g = sim.server.rt, sim.server.g
        self.g.WORLD_AGE_HOURS = 30
        self.P = self.rt.eval("require('RadioSurvivor/RS_Personas')")
        self.B = self.rt.eval("require('RadioSurvivor/RS_VoiceBonds')")
        self.A = self.rt.eval("require('RadioSurvivor/RS_Actions')")
        self.Log = self.rt.eval("require('RadioSurvivor/RS_RadioLog')")
        self.cid = sim.character('alice')
        self.now = 10 ** 9
        self.assertTrue(self.P.served('darlene')[1], 'darlene not served on the bench')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def day(self, n):
        self.g.WORLD_AGE_HOURS = (n - 1) * 24 + 6

    def share(self, voice='walt'):
        self.now += 120000  # past the per-voice cooldown of RS_Actions
        ctx = self.rt.table_from({'player': self.g.PLAYERS['alice'], 'cid': self.cid, 'khz': 145000})
        decisions = self.A.decide(self.P.get(voice), 'alice', self.rt.table_from([self.rt.table_from(a) for a in SHARE]),
                                  self.now, ctx)
        d = decisions[1]
        return d.accepted, d.reason

    def good(self):
        """Good reputation of alice (RS_Config.Reputation.goodAt = 20), written in the private state."""
        self.rt.execute(f"local S = require('RadioSurvivor/RS_State'); S.data.reputation = S.data.reputation or {{}}; "
                        f"S.data.reputation['{self.cid}'] = {{ score = 30, revision = 1, trend = 'stable', signs = {{}}, "
                        f"reasons = {{}}, gainDay = -1, gainSum = 0 }}")
        self.assertEqual(self.rt.eval(f"require('RadioSurvivor/RS_Reputation').level('{self.cid}')"), 'good')

    def answers(self, n, voice='walt'):
        for _ in range(n):
            self.assertTrue(self.B.answered(self.cid, voice))

    def knows(self, voice):
        return self.Log.knowsVoice(self.cid, voice)

    def test_no_bond_no_share(self):
        self.assertEqual(self.share(), (False, 'not_trusted'))
        self.day(1)
        self.answers(6)
        self.assertEqual(self.share(), (False, 'not_trusted'), 'one game day is not a bond')
        self.assertFalse(self.knows('darlene'))

    def test_bond_shares_an_unknown_voice_once_then_waits(self):
        self.day(1)
        self.answers(2)
        self.day(2)
        self.answers(2)
        self.assertEqual(self.share(), (True, 'ok'))
        self.assertTrue(self.knows('darlene'))
        khz = self.P.served('darlene')[1]
        record = self.sim.state().characters[self.cid]
        f = [f for f in lua_list(record.radio.frequencies) if f.khz == khz][0]
        self.assertEqual((f.voice, lua_list(f.lines)[-1].kind), ('darlene', 'reply'))
        self.assertIn('Darlene', lua_list(f.lines)[-1].text)
        # Same voice: once in 7 game days; any voice: once in 3 game days.
        self.day(4)
        self.assertEqual(self.share(), (False, 'voice_too_soon'))
        self.answers(4, 'darlene')
        self.day(3)
        self.answers(1, 'darlene')
        ok, why = self.B.allowed(self.cid, 'darlene')
        self.assertEqual((ok, why), (False, 'too_soon'))
        self.day(9)
        # Darlene shares gus then cody: none is installed on the bench, nothing new to give.
        self.assertEqual(self.share('darlene'), (False, 'nothing_new'))
        # Walt again after 7 days: darlene known, nightowl not installed.
        self.assertEqual(self.share(), (False, 'nothing_new'))

    def test_good_reputation_is_a_bond(self):
        self.good()
        self.day(1)
        self.assertEqual(self.share(), (True, 'ok'))

    def test_a_voice_already_known_is_never_shared(self):
        khz = self.P.served('darlene')[1]
        self.Log.add(self.cid, khz, 'reply', 'Darlene here.', 'darlene')
        self.good()
        self.assertEqual(self.share(), (False, 'nothing_new'))

    def test_answers_on_the_air_count(self):
        it = IntegrationTests()
        sim = it.simulation(self.tmp / 'air')
        alice = it.client(sim, 'alice')
        for n in (1, 2):
            sim.server.g.WORLD_AGE_HOURS = (n - 1) * 24 + 6
            sim.clock.offset += 20000
            self.assertTrue(alice.rt.eval(f"Talk.send(getPlayer(), getPlayer().radio, 'Walt? {n}')"))
            it.answer(sim, f'Walt here {n}.')
        bond = convert(sim.state().characters[sim.character('alice')].voiceBonds['walt'])
        self.assertEqual((bond['answers'], bond['days']), (2, 2))

if __name__ == '__main__':
    unittest.main()
