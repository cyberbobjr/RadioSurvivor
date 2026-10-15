"""Voice mission templates: real Lua authority and bridge fields, no Java API proof."""
import unittest
import test_carnet as carnet_helpers
from test_carnet import bridge_module
from test_mission_clear import CLEAR_WORLD
import npc_protocol as protocol
from types import SimpleNamespace


class VoiceTemplateTests(unittest.TestCase):
    setUp, tearDown, voice_sim = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown, carnet_helpers.VoiceMissionTests.voice_sim

    def setup_voice(self, template):
        sim = self.voice_sim(template)
        rt = sim.server.rt
        rt.execute("RandomizedWorldBase = RandomizedWorldBase or {}; local cell = getCell(); "
                   "cell.getGridSquare = function() return nil end; getCell = function() return cell end")
        rt.execute(CLEAR_WORLD)
        voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        sheet = rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from([template]),
                               'places': rt.table_from([rt.table_from({'id': 'box', 'x': 100, 'y': 10, 'z': 0,
                                                                        'label': 'Supply depot'})])})
        return sim, voice, sheet

    def start(self, sim, voice, sheet, template):
        return voice.start(sim.server.rt.eval("require('RadioSurvivor/RS_State')"), sheet,
                           sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, template)

    def test_each_permitted_template_is_created_and_waits_for_radio_report(self):
        for template in ('scout', 'deliver', 'retrieve', 'clear', 'signal'):
            with self.subTest(template=template):
                sim, voice, sheet = self.setup_voice(template)
                m = self.start(sim, voice, sheet, template)
                self.assertFalse(isinstance(m, tuple), str(m))
                self.assertEqual(m.report, 'radio')
                self.assertEqual(m.template, 'retrieve_id' if template == 'retrieve' else template)
                engine = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
                self.assertFalse(engine.reportReady(m))
                refused = voice.report(sim.server.rt.eval("require('RadioSurvivor/RS_State')"), sheet,
                                       sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)
                self.assertEqual(refused, (None, 'not_done'))

    def test_sheet_whitelist_cannot_be_bypassed(self):
        sim, voice, sheet = self.setup_voice('scout')
        self.assertEqual(self.start(sim, voice, sheet, 'clear'), (None, 'bad_template'))

    def test_delivery_targets_sheet_place_and_requires_collection(self):
        sim, voice, sheet = self.setup_voice('deliver')
        m = self.start(sim, voice, sheet, 'deliver')
        self.assertEqual((m.deposit.x, m.deposit.y, m.deposit.z), (100, 10, 0))
        engine = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        self.assertFalse(engine.reportReady(m))
        self.assertEqual(m.state, 'active')
        self.assertIn(m.deposit.mode, ('box', 'bag'))

    def test_retrieve_requires_actual_card_even_after_found(self):
        sim, voice, sheet = self.setup_voice('retrieve')
        m = self.start(sim, voice, sheet, 'retrieve')
        m.found, m.cardId = True, 987654
        result = voice.report(sim.server.rt.eval("require('RadioSurvivor/RS_State')"), sheet,
                              sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)
        self.assertEqual(result, (None, 'refused'))
        self.assertEqual(m.state, 'active')


class MissionContextTests(unittest.TestCase):
    def context(self, kind, **fields):
        sheet = SimpleNamespace(secrets=['hidden passphrase'], places=[])
        data = dict(kind=kind, state='active', turn='not_yet', place='house', clues={}, report='radio')
        data.update(fields)
        return bridge_module.mission_context({'mission': protocol.encode(data).hex()}, sheet)

    def test_every_template_has_an_explicit_objective_and_private_fields_are_removed(self):
        examples = {
            'scout': ({}, 'look at a building'),
            'deliver': ({'quantity': 3, 'delivered': 0, 'accepted': {'Base.Bandage': True},
                         'depositMode': 'bag'}, 'bag hidden on the ground'),
            'retrieve_id': ({'found': False}, "missing person's body"),
            'clear': ({'kills': 2, 'target': 4}, 'Verified kills: 2 of 4'),
            'signal': ({'color': 'red', 'hour': 22, 'windowHours': 3, 'lit': False}, 'red Signal Smoke'),
        }
        for kind, (fields, expected) in examples.items():
            with self.subTest(kind=kind):
                mission = self.context(kind, cardId=456, x=10600, frequency=160000, **fields)
                self.assertEqual(mission['kind'], kind)
                for key in ('cardId', 'x', 'frequency'):
                    self.assertNotIn(key, mission)
                prompt = bridge_module.mission_prompt(mission, 'Caller')
                self.assertIn(expected, prompt)
                self.assertIn('never add report_mission', prompt)
                self.assertNotIn('10600', prompt)

    def test_uncollected_drop_can_never_be_reported_even_with_premature_turn(self):
        mission = self.context('deliver', quantity=3, delivered=0, depositMode='box',
                               depositCollected=False, toReport=True, turn='report_due',
                               collectionRule='invented unsafe rule')
        self.assertFalse(mission['to_report'])
        self.assertEqual(mission['turn'], 'not_yet')
        prompt = bridge_module.mission_prompt(mission, 'Caller')
        self.assertIn('forty tiles away for ten seconds', prompt)
        self.assertNotIn('invented unsafe rule', prompt)
        self.assertIn('never add report_mission', prompt)

    def test_collected_drop_report_and_bounded_fields(self):
        mission = self.context('deliver', quantity=3, delivered=3, depositCollected=True,
                               depositMode='invented', toReport=True, turn='report_due',
                               accepted={'Base.Bandage': True, 'hidden passphrase': True,
                                         'Base.Water': False, 'bad;code': True})
        self.assertEqual(mission['accepted'], ['Base.Bandage'])
        self.assertEqual(mission['deposit_mode'], 'box')
        self.assertIn('you only wait for their report', bridge_module.mission_prompt(mission, 'Caller'))
        signal = self.context('signal', hour=999999, windowHours=-1, color='hidden passphrase')
        self.assertEqual((signal['hour'], signal['window_hours'], signal['color']), (0, 0, 'unknown'))


class FakeMissionActionTests(unittest.TestCase):
    def test_markers_are_deterministic_and_respect_template_whitelist(self):
        import importlib.util
        from pathlib import Path
        path = Path(__file__).resolve().parents[1] / 'tools/fake_llm/fake_llm.py'
        spec = importlib.util.spec_from_file_location('rs_fake_voice_templates', path)
        fake = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fake)
        system = ('Allowed action types: start_mission, share_frequency. At most 3 actions. '
                  'Allowed mission templates: scout, deliver, retrieve, clear, signal.')
        for kind in ('scout', 'deliver', 'retrieve', 'clear', 'signal'):
            a = fake.radio_json(system, '[mission:' + kind + ']')
            self.assertEqual(a['actions'], [{'type': 'start_mission', 'template': kind}])
            self.assertEqual(a, fake.radio_json(system, '[mission:' + kind + ']'))
        self.assertEqual(fake.radio_json(system, '[share_frequency]')['actions'], [{'type': 'share_frequency'}])
        self.assertEqual(fake.radio_json(system.replace('scout, deliver, retrieve, clear, signal', 'scout'),
                                        '[mission:clear]')['actions'], [])
        self.assertEqual(fake.radio_json('', '[share_frequency]')['actions'], [])


if __name__ == '__main__':
    unittest.main()
