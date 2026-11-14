"""Registre des types de mission (E20-T01, ADR D02) : un faux gabarit inscrit par le banc, avec ses déclarations
(voiceName 'fake', handover false, mapStyle 'Fake') et sa vue du carnet, est donné par une voix, projeté, affiché au
carnet et sur la carte sans aucune modification de RS_MissionVoice, du carnet ni de la carte.

    python RadioSurvivor/tests/test_mission_registry.py

Banc lupa du carnet (vrai RadioSurvivor_Server, vrai RS_Carnet_Server, vrai client du carnet) : preuve de la logique
Lua, pas de l'API Java ni du réseau réel.
"""
from __future__ import annotations

import unittest

import test_carnet as carnet_helpers
from test_carnet import MAP_DOUBLE, NOTEBOOK_UI, convert
from test_mission_clear import CLEAR_WORLD
from test_protocol import lua_list

# Faux gabarit du banc : une place fixe, une zone sur la carte, aucun compte rendu.
FAKE_TEMPLATE = r'''
local M = require 'RadioSurvivorCore/RC_Missions'
require('RadioSurvivorCore/RC_MissionConfig').Missions.fake = {id = 'fake_v1', titleKey = 'IGUI_RS_FakeTitle',
    durationMs = 3600000, rewardType = '', rewardCount = 0}
local Fake = {idPrefix = 'fake', voiceName = 'fake', handover = false, mapStyle = 'Fake'}
function Fake.offer(entry, npc, record, body, character) return {x = 100, y = 10} end
function Fake.create(m, entry, npc, terms) m.mapZone = {x = terms.x, y = terms.y, r = 6} end
function Fake.project(m, p)
    p.template, p.fakeLine = 'fake', 'here'
    if p.engaged then p.mapZone = {x = m.mapZone.x, y = m.mapZone.y, r = m.mapZone.r} end
end
function Fake.context(m, ctx) ctx.kind = 'fake' end
M.register('fake', Fake)
'''

# Fausse vue du carnet : une seule ligne propre au gabarit.
FAKE_VIEW = r'''
require('RadioSurvivor/RS_MissionViews').register('fake', {showsPlace = false,
    detail = function(row, line, ctx) line(ctx.tr('FakeDetail', row.fakeLine)) end})
'''


class MissionRegistryTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def start_fake(self, name):
        sim = self.voice_sim(name)
        rt = sim.server.rt
        rt.execute(CLEAR_WORLD)
        rt.execute(FAKE_TEMPLATE)
        voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        sheet = rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from(['fake'])})
        store = rt.eval("require('RadioSurvivor/RS_State')")
        m = voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, 'fake')
        return sim, voice, m

    def test_fake_template_is_given_by_a_voice_and_projected_with_its_declarations(self):
        sim, voice, m = self.start_fake('registry-voice')
        self.assertFalse(isinstance(m, tuple), str(m))
        self.assertEqual((m.template, m.donor, m.report, m.state), ('fake', 'voice', 'radio', 'active'))
        self.assertTrue(voice.allowed('fake'))
        engine = sim.server.rt.eval("require('RadioSurvivorCore/RC_Missions')")
        self.assertIn('fake', list(lua_list(engine.voiceNames())))
        self.assertEqual(engine.voiceTemplate('fake')[0], 'fake')
        p = convert(engine.projection(m, sim.character('alice')))
        self.assertEqual((p['handover'], p['mapStyle']), (False, 'Fake'))

    def test_a_name_listed_by_the_sheet_but_not_registered_is_refused(self):
        sim = self.voice_sim('registry-unknown')
        rt = sim.server.rt
        voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        sheet = rt.table_from({'id': 'custom', 'name': 'Custom', 'missions': rt.table_from(['nothing'])})
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
        c.load('client/RS_Carnet_Client.lua')
        c.rt.execute(FAKE_VIEW)
        maps = c.rt.eval("require('RadioSurvivor/RS_MapActions')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        drawn = [convert(s) for s in lua_list(c.rt.eval('mapSymbols()'))]
        self.assertEqual([s['text'] for s in drawn if s['kind'] == 'text'], ['IGUI_RS_MapZoneFake|Custom'])
        c.g.RS_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        self.assertIn('IGUI_RS_FakeDetail|here', text)
        # Common lines kept, deliver lines absent: the fake template declares no hand-over.
        self.assertIn('IGUI_RS_Time', text)
        for key in ('IGUI_RS_Progress', 'IGUI_RS_NoRefund', 'IGUI_RS_ScoutPlace'):
            self.assertNotIn(key, text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a fake mission')


if __name__ == '__main__':
    unittest.main()
