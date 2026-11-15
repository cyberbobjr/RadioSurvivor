"""Darlene veut rentrer à sa clinique (E20-T10, ADR D09) : la vraie fiche livrée, sa chaîne de missions et son état.

    python RadioSurvivor/tests/test_darlene_chain.py

Vrai RadioSurvivor_Server, vrai RS_Carnet_Server, vraie fiche `personas/darlene.txt` du mod (copiée avec les autres
fiches livrées et le catalogue des catégories dans le dossier de travail du banc). Doublures : la métagrille du banc
carnet (SCOUT_GRID) avec le bâtiment de la clinique de West Point aux coordonnées de la carte 42.22 (bâtiment 43 du
lotheader 46_26 : x 11854-11888, y 6857-6886, relevé par .claude/tools/lotheader_parser.py) et
IsoMetaGrid.getBuildingAt(x, y, z) (IsoMetaGrid.java:271-280 : le bâtiment de la pièce de la case). Les réussites et
les échecs passent par la clôture du moteur commun (RC_Missions.finish), comme dans tests/test_mission_chain.py ; la
suite en jeu rs.voicedarlene joue les vrais objectifs sur la vraie carte.
Preuve de la logique Lua avec la vraie fiche, pas de l'API Java ni du réseau.
"""
from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

import test_carnet as carnet_helpers
from test_carnet import Simulation, SCOUT_GRID, bridge_module, convert
from test_mission_clear import CLEAR_WORLD
from test_mission_chain import lua_jobs
import npc_protocol as protocol

ROOT = Path(__file__).resolve().parents[1]
PERSONAS = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'personas'
KHZ = 120000

# Bâtiment 43 de la carte 42.22 (galerie marchande dont la clinique occupe x 11879-11888) et getBuildingAt par pièce.
CLINIC_WORLD = r'''
CLINIC = scoutHouse(43, 11854, 6857, 35, 30)
SCOUT_GRID.getBuildingAt = function(_, x, y, z)
    if z == nil then error('getBuildingAt(x, y) reads the bounds only: use the room variant (x, y, z)') end
    for _, b in ipairs(SCOUT_BUILDINGS) do
        if x >= b.x1 and x < b.x2 and y >= b.y1 and y < b.y2 then return b end
    end
    return nil
end
-- IsoCell.getGridSquare(x, y, z) (IsoCell.java:2801): nil for a square that is not loaded (the clinic is far from
-- the players of the bench): dead drops and barricades wait for their first reading.
local cell = getCell()
if cell.getGridSquare == nil then function cell:getGridSquare() return nil end end
getCell = function() return cell end
'''


class DarleneChainTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-darlene-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def sim(self, name):
        sim = Simulation(self.path / name, provider=False)
        rt = sim.server.rt
        rt.execute(SCOUT_GRID)
        work = sim.path / 'personas'
        work.mkdir(parents=True, exist_ok=True)
        for f in PERSONAS.glob('*.txt'):
            shutil.copyfile(f, work / f.name)
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        rt.execute(CLEAR_WORLD)
        rt.execute(CLINIC_WORLD)
        # The game loads every server file of the mod: the set-up of the target place registers itself.
        rt.eval("require('RadioSurvivor/RS_MissionTarget')")
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        for user in ('alice', 'bob'):
            sim.add_client(user)
        self.voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        self.engine = rt.eval("require('RadioSurvivorCore/RC_Missions')")
        self.store = rt.eval("require('RadioSurvivor/RS_State')")
        self.api = sim.server.g.RadioSurvivor.API
        return sim

    def sheet(self, sim):
        return sim.server.rt.eval("require('RadioSurvivor/RS_Personas').get('darlene')")

    def start(self, sim, user, name):
        sim.clock.offset += 1800001  # M01 delay between two missions of the same voice (play time)
        return self.voice.start(self.store, self.sheet(sim), sim.character(user), sim.server.g.PLAYERS[user], KHZ,
                                name)

    def started(self, sim, user, name):
        m = self.start(sim, user, name)
        self.assertFalse(isinstance(m, tuple), f'{name}: {m}')
        self.assertEqual(m.section, name)
        return m

    def close(self, sim, m, result):
        self.assertTrue(self.engine.finish(sim.state(), m, result))
        self.assertTrue(self.store.save())

    def jobs(self, sim, user):
        field = self.voice.field(self.voice.jobs(self.sheet(sim), sim.character(user), sim.server.g.PLAYERS[user]))
        return [job['name'] for job in lua_jobs(convert(protocol.decode(bytes.fromhex(field))))]

    def test_shipped_sheet_loads_with_its_chain_and_places(self):
        sim = self.sim('darlene-sheet')
        sheet = self.sheet(sim)
        self.assertIsNotNone(sheet, 'darlene.txt refused by the server reader')
        self.assertEqual(sheet.location, 'none', 'she no longer claims a fixed place on the map')
        missions = [sheet.missions[i] for i in sorted(sheet.missions)]
        self.assertEqual([(m.id, m.type, m.after) for m in missions],
                         [('scout_clinic', 'scout', None), ('clear_clinic', 'clear', 'scout_clinic'),
                          ('secure_clinic', 'barricade', 'clear_clinic'), ('meds', 'deliver', 'secure_clinic')])
        self.assertEqual([m.target for m in missions], ['clinic', 'clinic', 'clinic', None])
        self.assertEqual([m.sets_state for m in missions], [None, None, None, 'returned'])
        self.assertTrue(all(m.story for m in missions), 'every section tells her reason')
        places = {p.id: p for p in (sheet.places[i] for i in sorted(sheet.places))}
        self.assertEqual((places['clinic'].x, places['clinic'].y, places['clinic'].z), (11880, 6878, 0))
        meds = missions[3]
        self.assertEqual([meds.drops[i] for i in sorted(meds.drops)], ['drop_dumpsters', 'drop_bookstore'])
        self.assertEqual(meds.params['items'], 'medical')

    def test_chain_offered_in_order_up_to_the_story_state_returned(self):
        sim = self.sim('darlene-chain')
        self.assertIsNone(self.api.voiceStoryState('darlene'))
        self.assertEqual(self.jobs(sim, 'alice'), ['scout_clinic'])
        for locked in ('clear_clinic', 'secure_clinic', 'meds', 'deliver', 'barricade'):
            self.assertEqual(self.start(sim, 'alice', locked), (None, 'locked'), locked)
        # 1. Look at the clinic: the building of her place, not one drawn around the caller.
        scout = self.started(sim, 'alice', 'scout_clinic')
        self.assertEqual((scout.template, scout.place), ('scout', 'West Point clinic'))
        self.assertEqual((scout.zone.x1, scout.zone.y1), (11854 - 2, 6857 - 2))
        self.close(sim, scout, 'success')
        self.assertEqual(self.jobs(sim, 'alice'), ['scout_clinic', 'clear_clinic'])
        self.assertEqual(self.jobs(sim, 'bob'), ['scout_clinic'], 'per character')
        # 2. Clear around the clinic: the counting circle is centred on the clinic building.
        clear = self.started(sim, 'alice', 'clear_clinic')
        self.assertEqual((clear.template, clear.place), ('clear', 'West Point clinic'))
        self.assertEqual((clear.mapZone.x, clear.mapZone.y), ((11854 + 11889) // 2, (6857 + 6887) // 2))
        self.assertGreaterEqual(clear.target, 1)
        self.close(sim, clear, 'success')
        self.assertEqual(self.jobs(sim, 'alice'), ['scout_clinic', 'clear_clinic', 'secure_clinic'])
        # 3. Barricade the clinic: the building of the target place, count of the sheet.
        secure = self.started(sim, 'alice', 'secure_clinic')
        self.assertEqual((secure.template, secure.place, secure.count), ('barricade', 'West Point clinic', 4))
        self.assertEqual((secure.site.x1, secure.site.y1, secure.site.x2, secure.site.y2), (11854, 6857, 11889, 6887))
        self.close(sim, secure, 'success')
        self.assertEqual(self.jobs(sim, 'alice'), ['scout_clinic', 'clear_clinic', 'secure_clinic', 'meds'])
        self.assertIsNone(self.api.voiceStoryState('darlene'), 'no state before the last mission')
        # 4. Medicine at one of the two dead drops near the clinic; its success sets the story state.
        meds = self.started(sim, 'alice', 'meds')
        self.assertEqual(meds.template, 'deliver')
        self.assertEqual([(d.id, d.x, d.y) for d in (meds.drops[i] for i in sorted(meds.drops))],
                         [('drop_dumpsters', 11874, 6870), ('drop_bookstore', 11894, 6870)])
        self.assertEqual(meds.setsState, 'returned')
        self.close(sim, meds, 'success')
        self.assertEqual(self.api.voiceStoryState('darlene'), 'returned')
        self.assertEqual(sim.state().voiceStory.darlene, 'returned')

    def test_failure_of_a_step_locks_the_next_one_again(self):
        sim = self.sim('darlene-failed')
        self.close(sim, self.started(sim, 'alice', 'scout_clinic'), 'success')
        self.close(sim, self.started(sim, 'alice', 'clear_clinic'), 'failed')
        self.assertEqual(self.jobs(sim, 'alice'), ['scout_clinic', 'clear_clinic'])
        self.assertEqual(self.start(sim, 'alice', 'secure_clinic'), (None, 'locked'))

    def test_story_state_told_to_the_model_once_returned(self):
        sim = self.sim('darlene-story')
        for name in ('scout_clinic', 'clear_clinic', 'secure_clinic', 'meds'):
            self.close(sim, self.started(sim, 'alice', name), 'success')
        self.assertIn('returned', bridge_module.story_prompt(self.api.voiceStoryState('darlene')))
        prompt = self.sheet(sim).prompt
        self.assertIn('returned', prompt, 'her prompt tells what the state means')

    def test_no_code_names_her(self):
        names = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'Contents').rglob('*.lua')
                       if 'darlene' in p.read_text(encoding='utf-8', errors='replace').lower())
        # Before E20-T10: discovery notes (loot lists and corpse notes), the fingerprints of the shipped sheet, an
        # example in a comment of the rescue module and the list of the notes. Never a mission or chain of hers.
        self.assertEqual([n.replace('\\', '/') for n in names], [
            'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_NotesServer.lua',
            'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_Personas.lua',
            'Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_Rescue.lua',
            'Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/RadioSurvivor/RS_Notes.lua'])


class AimedScoutClearTests(unittest.TestCase):
    """scout and clear with target= (E20-T10): the building of the place of the sheet, whatever the caller's
    position; without target=, the building is still drawn around the caller (E11-T03, E11-T04)."""
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    SHEET = """format=1
id=scouter
name=Scout Voice
frequencies=160.0
actions=say,start_mission
budget.start_mission=20
[place home]
at=3005,3005,0
label=Old home
use=target
[place field]
at=3500,3500,0
label=Empty field
use=target
[mission look]
type=scout
target=home
[mission sweep]
type=clear
target=home
[mission nowhere]
type=scout
target=field
[mission around]
type=scout
[prompt]
You are Scout Voice, a voice of the offline test bench.
"""

    def world(self, name):
        sim = self.voice_sim(name, sheet=self.SHEET)
        rt = sim.server.rt
        rt.execute(CLEAR_WORLD)
        rt.execute(CLINIC_WORLD.replace('scoutHouse(43, 11854, 6857, 35, 30)', 'scoutHouse(77, 3000, 3000, 12, 10)'))
        self.voice = rt.eval("require('RadioSurvivor/RS_MissionVoice')")
        self.store = rt.eval("require('RadioSurvivor/RS_State')")
        return sim

    def start(self, sim, name):
        sim.clock.offset += 1800001
        sheet = sim.server.rt.eval("require('RadioSurvivor/RS_Personas').get('scouter')")
        return self.voice.start(self.store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, name)

    def test_scout_and_clear_aim_at_the_target_far_from_the_caller(self):
        sim = self.world('aimed')
        look = self.start(sim, 'look')
        self.assertFalse(isinstance(look, tuple), str(look))
        self.assertEqual((look.place, look.siteKey), ('Old home', 'b77'))
        self.assertTrue(look.clues and look.clueData, 'clues of the aimed building')
        self.engine_finish(sim, look)
        sweep = self.start(sim, 'sweep')
        self.assertFalse(isinstance(sweep, tuple), str(sweep))
        self.assertEqual((sweep.place, sweep.mapZone.x, sweep.mapZone.y), ('Old home', 3006, 3005))

    def engine_finish(self, sim, m):
        self.assertTrue(sim.server.rt.eval("require('RadioSurvivorCore/RC_Missions')").finish(sim.state(), m,
                                                                                             'failed'))

    def test_target_without_building_gives_no_mission_and_no_draw_replaces_it(self):
        sim = self.world('aimed-nowhere')
        self.assertEqual(self.start(sim, 'nowhere'), (None, 'no_place'))

    def test_section_without_target_still_draws_around_the_caller(self):
        sim = self.world('aimed-around')
        m = self.start(sim, 'around')
        self.assertFalse(isinstance(m, tuple), str(m))
        self.assertEqual(m.siteKey, 'b5002')


if __name__ == '__main__':
    unittest.main(verbosity=1)
