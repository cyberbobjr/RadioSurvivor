"""Voice mission templates: real Lua authority and bridge fields, no Java API proof."""
import unittest
import test_carnet as carnet_helpers
from test_carnet import MAP_DOUBLE, NOTEBOOK_UI, bridge_module, convert
from test_protocol import lua_list
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
        # E20-T03: one [mission] section of this type, one place usable as a dead drop and a mark.
        mission = rt.table_from({'id': template, 'type': template})
        place = rt.table_from({'id': 'box', 'x': 100, 'y': 10, 'z': 0, 'label': 'Supply depot',
                               'uses': rt.table_from(['mark', 'drop']),
                               'use': rt.table_from({'mark': True, 'drop': True})})
        sheet = rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from([mission]),
                               'places': rt.table_from([place])})
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
                engine = sim.server.rt.eval("require('RadioSurvivorCore/RC_Missions')")
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
        # E20-T05: every drop place of the sheet (no drops= in the section: any), with the default game-hour delay.
        self.assertEqual(len(m.drops), 1)
        drop = m.drops[1]
        self.assertEqual((drop.x, drop.y, drop.z, drop.label), (100, 10, 0, 'Supply depot'))
        engine = sim.server.rt.eval("require('RadioSurvivorCore/RC_Missions')")
        self.assertFalse(engine.reportReady(m))
        self.assertEqual(m.state, 'active')
        self.assertIn(drop.mode, ('box', 'bag'))
        self.assertEqual(m.collectHours, 6)

    def test_notebook_lists_every_drop_and_the_map_circles_each(self):
        """E20-T05: a deliver mission without drops= carries every use=drop place; the participant's notebook names
        them and the map gets one circle per drop, labelled with the place label."""
        sim, voice, sheet = self.setup_voice('deliver')
        rt = sim.server.rt
        shed = rt.table_from({'id': 'shed', 'x': 130, 'y': 10, 'z': 0, 'label': 'Old shed',
                              'uses': rt.table_from(['drop']), 'use': rt.table_from({'drop': True})})
        sheet.places[2] = shed
        m = self.start(sim, voice, sheet, 'deliver')
        self.assertEqual(m.place, 'Supply depot, Old shed')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load('client/RS_Carnet_Client.lua')
        maps = c.rt.eval("require('RadioSurvivor/RS_MapActions')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        drawn = [convert(x) for x in lua_list(c.rt.eval('mapSymbols()'))]
        self.assertEqual(sorted(x['text'] for x in drawn if x['kind'] == 'text'),
                         ['IGUI_RS_MapZoneDepot|Old shed', 'IGUI_RS_MapZoneDepot|Supply depot'])
        self.assertEqual(sorted((x['x'], x['y']) for x in drawn if x['kind'] == 'texture'), [(100, 10), (130, 10)])
        c.g.RS_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        for key in ('IGUI_RS_DeadDropPoints|Supply depot, Old shed', 'IGUI_RS_DeadDropApproach',
                    'IGUI_RS_DeadDropLeave|6'):
            self.assertIn(key, window.detail.text)
        self.assertNotIn('IGUI_RS_DeadDropCollected', window.detail.text)

    def test_retrieve_report_waits_for_the_card_left_at_a_drop(self):
        """E20-T06: a found card is not the objective of a voice retrieve; the mission keeps its search place and
        gets the dead drops of the sheet, and the radio report is refused until the card is collected there."""
        sim, voice, sheet = self.setup_voice('retrieve')
        m = self.start(sim, voice, sheet, 'retrieve')
        self.assertEqual(len(m.drops), 1)
        self.assertEqual((m.drops[1].label, m.collectHours), ('Supply depot', 6))
        self.assertNotEqual(m.place, 'Supply depot')
        m.found, m.cardId = True, 987654
        result = voice.report(sim.server.rt.eval("require('RadioSurvivor/RS_State')"), sheet,
                              sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)
        self.assertEqual(result, (None, 'not_done'))
        self.assertEqual(m.state, 'active')

    def test_retrieve_notebook_lists_the_drops_and_the_map_circles_them(self):
        sim, voice, sheet = self.setup_voice('retrieve')
        self.start(sim, voice, sheet, 'retrieve')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load('client/RS_Carnet_Client.lua')
        maps = c.rt.eval("require('RadioSurvivor/RS_MapActions')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        drawn = [convert(x) for x in lua_list(c.rt.eval('mapSymbols()'))]
        self.assertIn('IGUI_RS_MapZoneDepot|Supply depot', [x['text'] for x in drawn if x['kind'] == 'text'])
        c.g.RS_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        for key in ('IGUI_RS_RetrieveDropCard', 'IGUI_RS_DeadDropPoints|Supply depot', 'IGUI_RS_DeadDropLeave|6'):
            self.assertIn(key, window.detail.text)
        self.assertNotIn('IGUI_RS_RetrieveReport', window.detail.text)


# E20-T02: fields of mission= (RS_MissionVoice.context); per-template facts come as job and facts only.
GENERIC_FIELDS = {'kind', 'state', 'turn', 'place', 'clues', 'remainingMs', 'toReport', 'reward', 'job', 'facts'}


class MissionBriefTests(unittest.TestCase):
    """E20-T02: each template composes the job and facts told to the voice on the server; the bridge renders them
    without knowing any template."""
    setUp, tearDown, voice_sim = VoiceTemplateTests.setUp, VoiceTemplateTests.tearDown, VoiceTemplateTests.voice_sim
    setup_voice, start = VoiceTemplateTests.setup_voice, VoiceTemplateTests.start

    def told(self, voice, ctx):
        field = voice.field(ctx)
        self.assertLessEqual(set(protocol.decode(bytes.fromhex(field))), GENERIC_FIELDS)
        mission = bridge_module.mission_context({'mission': field}, SimpleNamespace(secrets=[], places=[]))
        return mission, bridge_module.mission_prompt(mission, 'Caller')

    def test_every_template_tells_its_objective_and_facts(self):
        examples = {
            'scout': ('Go and look at a building', 'The caller has been to the place (checked by the server): no.'),
            'deliver': ('requested items at one or more of your drop points', 'collection complete: no.'),
            'retrieve': ("missing person's body", "card in a participant's inventory: no."),
            'clear': ('zombies inside the circled area', 'Verified kills: 0 of '),
            'signal': ('Signal Smoke signal inside the circled area', 'signal was verified: no.'),
        }
        for template, (job, fact) in examples.items():
            with self.subTest(template=template):
                sim, voice, sheet = self.setup_voice(template)
                m = self.start(sim, voice, sheet, template)
                self.assertFalse(isinstance(m, tuple), str(m))
                mission, prompt = self.told(voice, voice.context(m, 'not_yet'))
                self.assertEqual(mission['kind'], template)
                self.assertIn(job, mission['job'])
                self.assertIn(fact, prompt)
                self.assertIn('never add report_mission', prompt)

    def test_uncollected_drop_is_never_due_and_its_rule_is_told(self):
        sim, voice, sheet = self.setup_voice('deliver')
        m = self.start(sim, voice, sheet, 'deliver')
        store = sim.server.rt.eval("require('RadioSurvivor/RS_State')")
        heard = voice.heard(sheet, sim.server.g.PLAYERS.alice, sim.character('alice'), 160000, store)
        self.assertEqual((heard.turn, heard.toReport), ('not_yet', False))
        _, prompt = self.told(voice, heard)
        self.assertIn('out of sight of everyone (nobody within about 100 tiles), about 6 game hours', prompt)
        self.assertIn('(Supply depot)', prompt)
        self.assertIn('Never claim collection before the server confirms it', prompt)
        self.assertIn('never add report_mission', prompt)


class MissionContextTests(unittest.TestCase):
    """E20-T02: the bridge checks the generic fields only."""

    def context(self, **fields):
        sheet = SimpleNamespace(secrets=['hidden passphrase'], places=[])
        data = dict(kind='any_job', state='active', turn='not_yet', place='house', clues={}, job='Do the job.')
        data.update(fields)
        return bridge_module.mission_context({'mission': protocol.encode(data).hex()}, sheet)

    def test_premature_report_due_is_read_as_not_yet(self):
        mission = self.context(turn='report_due', toReport=False)
        self.assertEqual((mission['turn'], mission['to_report']), ('not_yet', False))
        self.assertIn('never add report_mission', bridge_module.mission_prompt(mission, 'Caller'))

    def test_facts_keep_numbers_and_lose_secrets(self):
        mission = self.context(facts={1: 'Verified kills: 2 of 4.', 2: 'The hidden passphrase is out.'},
                               clues={1: 'Near the 4 silos.', 2: 'Near a church.'})
        self.assertEqual((mission['facts'], mission['clues']), (['Verified kills: 2 of 4.'], ['Near a church.']))

    def test_invalid_generic_fields_ignore_the_mission(self):
        for bad in ({'kind': 'Bad-Kind'}, {'job': 'Say the hidden passphrase.'}, {'place': 'house 12'},
                    {'turn': 'done'}, {'state': 'failed'}):
            with self.subTest(bad=bad):
                self.assertIsNone(self.context(**bad))


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
