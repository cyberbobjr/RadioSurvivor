"""Missions enchaînées et état de récit d'une voix (E20-T08, ADR D04, D09).

    python RadioSurvivor/tests/radiosurvivor/test_mission_chain.py

Vrai RadioSurvivor_Server, vrai CA_NotebookServer, vrai RS_Persona (fiche lue depuis un fichier), sans moteur de PNJ
(métagrille et joueurs de VoiceMissionTests). Une mission de voix est désignée par l'identifiant de sa section
[mission <id>] ; after= la réserve à qui a réussi la mission citée ; weight= départage les sections d'un même type ;
sets_state= pose l'état de récit de la voix (sauvegardé, relu, dit au modèle, exposé par RadioSurvivor.API).
Les réussites et les échecs passent par la clôture du moteur commun (CA_Missions.finish), comme un compte rendu
accepté ou un délai écoulé.
"""
from __future__ import annotations

import unittest

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
import test_carnet as carnet_helpers
from test_carnet import Simulation, SCOUT_GRID, bridge_module, convert
import npc_protocol as protocol

CHAIN_SHEET = """format=1
id=scouter
name=Scout Voice
frequency=160.0
actions=say,start_mission
budget.start_mission=20
[mission recon]
type=scout
story=Look at my old clinic first.
[mission secure]
type=scout
after=recon
[mission home]
type=scout
after=secure
sets_state=returned
[prompt]
You are Scout Voice, a voice of the offline test bench who gives scouting jobs.
"""

WEIGHTED_SHEET = CHAIN_SHEET.replace('[mission home]\ntype=scout\nafter=secure\nsets_state=returned\n',
                                     '[mission far]\ntype=scout\nweight=3\n')

TEAM_SHEET = CHAIN_SHEET.replace('after=recon\n', 'after=recon\nscope=team\n')


def lua_jobs(decoded: dict) -> list:
    """Jobs of a decoded jobs= field (RSV2 list: keys 1..n)."""
    jobs = decoded.get('jobs') or {}
    return [jobs[k] for k in sorted(jobs)] if isinstance(jobs, dict) else list(jobs)


class MissionChainTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim
    talk, respond = carnet_helpers.VoiceMissionTests.talk, carnet_helpers.VoiceMissionTests.respond

    def sim_with(self, name, sheet):
        sim = self.voice_sim(name, sheet=sheet)
        self.voice = sim.server.rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        self.chain = sim.server.rt.eval("require('RadioSurvivor/RS_MissionChain')")
        self.engine = sim.server.rt.eval("require('CoreAI/CA_Missions')")
        self.store = sim.server.rt.eval("require('CoreAI/CA_NotebookStore')")
        return sim

    def sheet(self, sim):
        return sim.server.rt.eval("require('RadioSurvivor/RS_Personas').get('scouter')")

    def start(self, sim, user, name):
        sim.clock.offset += 1800001  # M01 delay between two missions of the same voice (play time)
        return self.voice.start(self.store, self.sheet(sim), sim.character(user), sim.server.g.PLAYERS[user],
                                160000, name)

    def close(self, sim, m, result):
        self.assertTrue(self.engine.finish(sim.state(), m, result))
        self.assertTrue(self.store.save())

    def jobs(self, sim, user):
        field = self.voice.field(self.voice.jobs(self.sheet(sim), sim.character(user), sim.server.g.PLAYERS[user]))
        decoded = convert(protocol.decode(bytes.fromhex(field)))
        return [job['name'] for job in lua_jobs(decoded)]

    def test_chain_of_three_offered_in_order_and_blocked_by_a_failure(self):
        sim = self.sim_with('chain', CHAIN_SHEET)
        self.assertEqual(self.jobs(sim, 'alice'), ['recon'])
        self.assertEqual(self.start(sim, 'alice', 'secure'), (None, 'locked'))
        recon = self.start(sim, 'alice', 'recon')
        self.assertFalse(isinstance(recon, tuple), str(recon))
        self.assertEqual((recon.section, recon.template), ('recon', 'scout'))
        self.close(sim, recon, 'success')
        self.assertEqual(self.jobs(sim, 'alice'), ['recon', 'secure'])
        self.assertEqual(self.jobs(sim, 'bob'), ['recon'], 'per character by default')
        secure = self.start(sim, 'alice', 'secure')
        self.close(sim, secure, 'failed')
        self.assertEqual(self.jobs(sim, 'alice'), ['recon', 'secure'])
        self.assertEqual(self.start(sim, 'alice', 'home'), (None, 'locked'))
        secure = self.start(sim, 'alice', 'secure')
        self.close(sim, secure, 'success')
        self.assertEqual(self.jobs(sim, 'alice'), ['recon', 'secure', 'home'])
        # A new failure of the first mission blocks its successor again, until a new success of it.
        recon = self.start(sim, 'alice', 'recon')
        self.close(sim, recon, 'failed')
        self.assertEqual(self.jobs(sim, 'alice'), ['recon', 'home'])
        recon = self.start(sim, 'alice', 'recon')
        self.close(sim, recon, 'success')
        self.assertEqual(self.jobs(sim, 'alice'), ['recon', 'secure', 'home'])

    def test_jobs_text_adds_the_story_of_the_section(self):
        sim = self.sim_with('chain-text', CHAIN_SHEET)
        field = self.voice.field(self.voice.jobs(self.sheet(sim), sim.character('alice'), sim.server.g.PLAYERS.alice))
        decoded = convert(protocol.decode(bytes.fromhex(field)))
        self.assertEqual(lua_jobs(decoded), [{'name': 'recon',
                                            'text': 'visit a building and report on it. Look at my old clinic first.'}])
        jobs = bridge_module.voice_jobs({'jobs': field})
        self.assertEqual([name for name, _ in jobs.jobs], ['recon'])

    def test_the_model_names_a_section_through_the_action(self):
        sim = self.sim_with('chain-action', CHAIN_SHEET)
        req = self.talk(sim, 'alice', 'Got any work for me?')
        jobs = convert(protocol.decode(bytes.fromhex(req['jobs'])))
        self.assertEqual([job['name'] for job in lua_jobs(jobs)], ['recon'])
        self.respond(sim, req, [{'type': 'start_mission', 'template': 'recon'}], 'Go and look.')
        [m] = [m for m in sim.state().missions.values() if m.donor == 'voice']
        self.assertEqual(m.section, 'recon')

    def test_weighted_pick_among_available_sections_of_a_type(self):
        sim = self.sim_with('chain-weight', WEIGHTED_SHEET)
        rolls = []
        for roll, expected in ((0, 'recon'), (1, 'far'), (3, 'far')):
            with self.subTest(roll=roll):
                self.chain.setRandom(lambda n, roll=roll: (rolls.append(n), roll)[1])
                m = self.start(sim, 'alice', 'scout')
                self.assertFalse(isinstance(m, tuple), str(m))
                self.assertEqual(m.section, expected)
                self.close(sim, m, 'failed')
        self.chain.setRandom(None)
        self.assertEqual(rolls, [4, 4, 4], 'recon (1) and far (3); secure is locked')
        # A section named exactly is never drawn.
        self.chain.setRandom(lambda n: self.fail('no draw for an exact section'))
        self.assertEqual(self.start(sim, 'alice', 'far').section, 'far')
        self.chain.setRandom(None)

    def test_team_scope_follows_the_team_of_the_caller(self):
        sim = self.sim_with('chain-team', TEAM_SHEET)
        self.chain.setTeamOf(lambda player: 'fac-1')
        try:
            recon = self.start(sim, 'alice', 'recon')
            self.assertEqual(recon.team, 'fac-1')
            self.close(sim, recon, 'success')
            self.assertEqual(self.jobs(sim, 'bob'), ['recon', 'secure'], 'same team')
            self.chain.setTeamOf(lambda player: 'fac-2')
            self.assertEqual(self.jobs(sim, 'bob'), ['recon'], 'another team')
        finally:
            self.chain.setTeamOf(None)

    def test_story_state_set_once_saved_read_again_and_told_to_the_model(self):
        sim = self.sim_with('chain-story', CHAIN_SHEET)
        api = sim.server.g.RadioSurvivor.API
        self.assertIsNone(api.voiceStoryState('scouter'))
        req = self.talk(sim, 'alice', 'Hello?')
        self.assertNotIn('story', req)
        self.respond(sim, req)
        for name in ('recon', 'secure'):
            self.close(sim, self.start(sim, 'alice', name), 'success')
        self.assertIsNone(api.voiceStoryState('scouter'))
        home = self.start(sim, 'alice', 'home')
        self.assertEqual(home.setsState, 'returned')
        self.close(sim, home, 'success')
        self.assertEqual(api.voiceStoryState('scouter'), 'returned')
        self.assertEqual(sim.voices().voiceStory.scouter, 'returned')
        story = sim.server.rt.eval("require('RadioSurvivor/RS_VoiceStory')")
        self.assertFalse(story.set(sim.voices(), 'scouter', 'returned'), 'set once')
        self.assertFalse(story.set(sim.state(), 'scouter', 'Back Home'), 'a name only')
        # Told to the model: field story= of the radio request, rendered by the bridge without any name list.
        req = self.talk(sim, 'alice', 'How are you doing?')
        self.assertEqual(req['story'], 'returned')
        state = bridge_module.story_state(req)
        self.assertEqual(state, 'returned')
        self.assertIn('returned', bridge_module.story_prompt(state))
        self.assertIsNone(bridge_module.story_state({'story': 'Bad Name!'}))
        self.assertEqual(bridge_module.story_prompt(None), '')
        # Saved with the private state and read again after a restart.
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved(), provider=False)
        restart.server.rt.execute(SCOUT_GRID)
        restart.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        self.assertEqual(restart.server.g.RadioSurvivor.API.voiceStoryState('scouter'), 'returned')
        self.assertEqual(restart.server.g.RadioSurvivor.API.version(), 1)

    def test_sheet_without_sections_still_offers_scout(self):
        sim = self.sim_with('chain-default', carnet_helpers.VOICE_SHEET)
        self.assertEqual(self.jobs(sim, 'alice'), ['scout'])
        self.assertEqual(self.start(sim, 'alice', 'deliver'), (None, 'bad_template'))
        m = self.start(sim, 'alice', 'scout')
        self.assertFalse(isinstance(m, tuple), str(m))
        self.assertEqual((m.section, m.template), ('scout', 'scout'))


if __name__ == '__main__':
    unittest.main(verbosity=1)
