"""Registre des types de mission (E20-T01, ADR D02) : un faux gabarit inscrit par le banc, avec ses déclarations
(voiceName 'fake', handover false, mapStyle 'Fake') et sa vue du carnet, est donné par une voix, projeté, affiché au
carnet et sur la carte sans aucune modification de RS_MissionVoice, du carnet ni de la carte. E20-T02 (ADR D03) : le
même faux gabarit se décrit à la voix (voiceText, voiceBrief) ; cité par la fiche (section [mission] de type fake,
E20-T03), il est proposé au
modèle par le champ jobs= de la demande, admis par la validation de start_mission du pont et sa mission racontée (objectif
et faits composés par le serveur), sans aucune modification de bridge/.

    python RadioSurvivor/tests/test_mission_registry.py

Banc lupa du carnet (vrai RadioSurvivor_Server, vrai RS_Carnet_Server, vrai client du carnet) : preuve de la logique
Lua, pas de l'API Java ni du réseau réel.
"""
from __future__ import annotations

import json
import unittest

import test_carnet as carnet_helpers
from test_carnet import MAP_DOUBLE, NOTEBOOK_UI, VOICE_SHEET, bridge_module, convert, protocol
from test_mission_clear import CLEAR_WORLD
from test_protocol import lua_list

# Faux gabarit du banc : une place fixe, une zone sur la carte, aucun compte rendu.
FAKE_TEMPLATE = r'''
local M = require 'CoreAI/CA_Missions'
require('CoreAI/CA_MissionConfig').Missions.fake = {id = 'fake_v1', titleKey = 'IGUI_RS_FakeTitle',
    durationMs = 3600000, rewardType = '', rewardCount = 0}
local Fake = {idPrefix = 'fake', voiceName = 'fake', handover = false, mapStyle = 'Fake',
    voiceText = 'check the old water tower'}
function Fake.offer(entry, npc, record, body, character) return {x = 100, y = 10} end
function Fake.create(m, entry, npc, terms)
    m.mapZone, m.place, m.checked = {x = terms.x, y = terms.y, r = 6}, 'water tower', 0
end
function Fake.voiceBrief(m)
    return {job = 'Climb the water tower and count the crows on it, then report to you on this frequency.',
        facts = {'Crows counted by the server: ' .. m.checked .. ' of 3.'}}
end
function Fake.project(m, p)
    p.template, p.fakeLine = 'fake', 'here'
    if p.engaged then p.mapZone = {x = m.mapZone.x, y = m.mapZone.y, r = m.mapZone.r} end
end
function Fake.context(m, ctx) ctx.kind = 'fake' end
M.register('fake', Fake)
'''

# Fausse vue du carnet : une seule ligne propre au gabarit.
FAKE_VIEW = r'''
require('CoreAI/CA_MissionViews').register('fake', {showsPlace = false,
    detail = function(row, line, ctx) line(ctx.tr('FakeDetail', row.fakeLine)) end})
'''


# Voix du banc qui donne le faux gabarit (section [mission] de la fiche, E20-T03).
FAKE_SHEET = VOICE_SHEET.replace('[prompt]\n', '[mission tower]\ntype=fake\n[prompt]\n')


class MissionRegistryTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim
    talk, respond = carnet_helpers.VoiceMissionTests.talk, carnet_helpers.VoiceMissionTests.respond

    def start_fake(self, name):
        sim = self.voice_sim(name)
        rt = sim.server.rt
        rt.execute(CLEAR_WORLD)
        rt.execute(FAKE_TEMPLATE)
        voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        sheet = rt.table_from({'id': 'custom', 'name': 'Custom',
                               'missions': rt.table_from([rt.table_from({'id': 'tower', 'type': 'fake'})])})
        store = rt.eval("require('RadioSurvivor/RS_State')")
        m = voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, 'fake')
        return sim, voice, m

    def test_fake_template_is_given_by_a_voice_and_projected_with_its_declarations(self):
        sim, voice, m = self.start_fake('registry-voice')
        self.assertFalse(isinstance(m, tuple), str(m))
        self.assertEqual((m.template, m.donor, m.report, m.state), ('fake', 'voice', 'radio', 'active'))
        self.assertTrue(voice.allowed('fake'))
        engine = sim.server.rt.eval("require('CoreAI/CA_Missions')")
        self.assertIn('fake', list(lua_list(engine.voiceNames())))
        self.assertEqual(engine.voiceTemplate('fake')[0], 'fake')
        p = convert(engine.projection(m, sim.character('alice')))
        self.assertEqual((p['handover'], p['mapStyle']), (False, 'Fake'))

    def test_a_name_listed_by_the_sheet_but_not_registered_is_refused(self):
        sim = self.voice_sim('registry-unknown')
        rt = sim.server.rt
        voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        sheet = rt.table_from({'id': 'custom', 'name': 'Custom',
                               'missions': rt.table_from([rt.table_from({'id': 'job', 'type': 'nothing'})])})
        store = rt.eval("require('RadioSurvivor/RS_State')")
        self.assertFalse(voice.allowed('nothing'))
        self.assertEqual(voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000,
                                     'nothing'), (None, 'bad_template'))

    def test_fake_view_draws_the_notebook_page_and_the_map_label_follows_the_style(self):
        sim, _, m = self.start_fake('registry-page')
        self.assertFalse(isinstance(m, tuple), str(m))
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load_notebook()
        c.rt.execute(FAKE_VIEW)
        maps = c.rt.eval("require('CoreAI/CA_MapZones')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
        drawn = [convert(s) for s in lua_list(c.rt.eval('mapSymbols()'))]
        self.assertEqual([s['text'] for s in drawn if s['kind'] == 'text'], ['IGUI_CA_MapZoneFake|Custom'])
        c.g.CoreAI.notebook.toggle()
        window = c.g.CoreAI.notebookClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        self.assertIn('IGUI_CA_FakeDetail|here', text)
        # Common lines kept, deliver lines absent: the fake template declares no hand-over.
        self.assertIn('IGUI_CA_Time', text)
        for key in ('IGUI_CA_Progress', 'IGUI_CA_NoRefund', 'IGUI_CA_ScoutPlace'):
            self.assertNotIn(key, text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a fake mission')


    def answer(self, sim, req, reply):
        """The real bridge answers this request (model replaced by `reply`); returns (system prompt, result)."""
        seen = []
        saved = bridge_module.call_llm
        try:
            bridge_module.call_llm = lambda config, messages, speaker='Walt', **_: seen.append(messages) or reply
            voices = bridge_module.Voices(sim.path / 'personas')
            result = bridge_module.answer({}, bridge_module.Conversations(sim.path), 's', req, voices)
        finally:
            bridge_module.call_llm = saved
        return seen[-1][0]['content'], result

    def test_fake_template_is_offered_to_the_model_and_its_job_told_without_bridge_change(self):
        sim = self.voice_sim('registry-bridge')
        rt = sim.server.rt
        rt.execute(CLEAR_WORLD)
        rt.execute(FAKE_TEMPLATE)
        # The sheet cites the fake type: read once the template is registered (in game, every file loads before the
        # sheets), here by the reload of a changed sheet. Not a word of the reader nor of the bridge changes.
        (sim.path / 'personas' / 'scouter.txt').write_text(FAKE_SHEET, encoding='utf-8')
        self.assertTrue(rt.eval("require('RadioSurvivor/RS_Personas').reload()"))
        sheet = rt.eval("require('RadioSurvivor/RS_Personas').get('scouter')")
        self.assertEqual([(m.id, m.type) for m in lua_list(sheet.missions)], [('tower', 'fake')])
        req = self.talk(sim, 'alice', 'Got any work for me?')
        # The server tells the bridge the jobs this voice may give, named by their section (E20-T08) and described
        # by their template.
        jobs = convert(protocol.decode(bytes.fromhex(req['jobs'])))
        self.assertEqual([jobs['jobs'][i] for i in sorted(jobs['jobs'])],
                         [{'name': 'tower', 'text': 'check the old water tower'}])
        order = rt.eval("require('CoreAI/CA_MissionConfig').Caches.order")
        self.assertEqual([jobs['caches'][i] for i in sorted(jobs['caches'])], list(lua_list(order)))
        start = json.dumps({'say': 'Go check the tower.', 'actions': [{'type': 'start_mission', 'template': 'tower'}]})
        system, result = self.answer(sim, req, start)
        self.assertIn('tower: check the old water tower', system)
        self.assertIn('{"type": "start_mission", "template": "tower"}', system)
        self.assertEqual(result['actions'], [{'type': 'start_mission', 'template': 'tower'}])
        # The server starts the fake mission, then the briefing tells its job and facts to the voice.
        self.respond(sim, req, result['actions'], 'Go check the tower.')
        [m] = [m for m in sim.state().missions.values() if m.donor == 'voice']
        self.assertEqual((m.template, m.section, m.state), ('fake', 'tower', 'active'))
        parsed = bridge_module.parse_requests((sim.path / 'requests.txt').read_text(encoding='utf-8'))
        [brief] = [r for r in parsed[1] if r['id'].endswith('-brief')]
        system, _ = self.answer(sim, brief, json.dumps({'say': 'Listen.', 'actions': []}))
        self.assertIn('- The job: Climb the water tower and count the crows on it, then report to you on this '
                      'frequency.', system)
        self.assertIn('- Crows counted by the server: 0 of 3.', system)
        self.assertIn('Tell them NOW where to go', system)


if __name__ == '__main__':
    unittest.main()
