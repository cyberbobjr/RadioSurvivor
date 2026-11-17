"""Type de mission `watch` (E20-T14, ADR D10) : rester à un point d'observation, le lieu `target` de la fiche d'une
voix, une durée en heures de jeu (absence courte tolérée, longue = remise à zéro), puis compte rendu à la radio ; les
faits vus pendant le guet (hélicoptère vanilla entendu, groupe de morts proche) sont racontés au modèle de la voix.

    python RadioSurvivor/tests/radiosurvivor/test_mission_watch.py

Vrai RadioSurvivor_Server, vrai CA_NotebookServer (gabarit CA_MissionWatch et ses sources de faits inscrits au
chargement), vrai RS_MissionVoice (départ et compte rendu d'une voix), vrai RS_MissionTarget (lieu target), vrai
RS_Persona (lecture de la fiche), vrai client du carnet ; doublures fidèles au Java 42.22 relevé (WATCH_WORLD). Preuve
de la logique Lua, pas de l'API Java réelle ni du réseau : la suite en jeu rs.voicewatch le confirme sur un serveur
dédié.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
import test_carnet as carnet_helpers
from test_carnet import MAP_DOUBLE, NOTEBOOK_UI, bridge_module, convert
from test_mission_barricade import sheet_double
from test_personas import LuaPersona
from test_persona_sections import BASE, PLACES, PROMPT
import npc_protocol as protocol

# Doublures du monde, fidèles au Java 42.22 (E:\pz-source-42.22\java\zombie, relevé du 2026-11-15) :
# - Horloge de jeu : GameTime.getWorldAgeHours (GameTime.java:824-827, nuits * 24 + heures depuis 7:00) est la
#   doublure WORLD_AGE_HOURS du banc (test_protocol.py) : elle ne bouge pas quand le jeu est en pause et avance plus vite
#   en vitesse x2/x3 ; l'horloge réelle (getTimestampMs) bouge à part.
# - Hélicoptère vanilla : pendant un passage, Helicopter.update appelle, sur l'autorité seulement (le client MP ne fait
#   que le son, Helicopter.java:105-109), WorldSoundManager.addSound(null, x, y, 0, 500, 500) à la position de l'appareil
#   (Helicopter.java:217-218), qui déclenche OnWorldSound(x, y, z, radius, volume, source) (WorldSoundManager.java:480).
#   Les autres sons sans source à l'étage 0 ont un rayon de 600 ou 5000 (AmbientStreamManager.java:463-468, 502-504).
# - Zombies chargés du serveur : IsoCell.getZombieList (ArrayList, depuis 0), IsoZombie getX/getY/getZ.
WATCH_WORLD = r'''
-- The game clock stops here (paused) and moves only when a test moves it; vanilla day of 90 real minutes, so that the
-- delay of the mission (play ms) follows the game hours of the tests.
WORLD_AGE_HOURS, MINUTES_PER_DAY = getGameTime():getWorldAgeHours(), 90
-- Test classes named after their Java class (checked by tests/coreai/test_doubles_api.py).
local function class(name)
    local c = {__javaName = name}
    c.__index = c
    return c
end
local Zombie = class('IsoZombie')
function Zombie:getX() return self.x end
function Zombie:getY() return self.y end
function Zombie:getZ() return self.z end
function Zombie:isReanimatedPlayer() return self.reanimated end
-- No NPC engine in this bench: the server cell holds only the dead of each test.
for i = #ZOMBIES, 1, -1 do ZOMBIES[i] = nil end
-- n zombies of the server cell around x, y (reanimated: bodies of an NPC engine, reanimated players).
function zombiesAt(n, x, y, reanimated)
    for i = 1, n do
        ZOMBIES[#ZOMBIES + 1] = setmetatable({x = x + i % 4, y = y + math.floor(i / 4), z = 0,
            reanimated = reanimated == true}, Zombie)
    end
end
-- A world sound without source on the ground level, as WorldSound.init fires it.
function worldSound(x, y, radius, volume)
    fire('OnWorldSound', x, y, 0, radius, volume, nil)
end
'''

# Lieu commun (E25-T01) de la fiche d'une voix qui donne la mission watch : le château d'eau (target=post), table
# id -> lieu comme sheet.places.
SHEET_PLACES = {'post': {'id': 'post', 'x': 60, 'y': 60, 'z': 0, 'label': 'Water tower'}}
POST = (60, 60)
FACT_SOURCES = ('CA_WatchHelicopter', 'CA_WatchHorde')
HELICOPTER = (500, 500)   # rayon et volume du son de l'hélicoptère vanilla (Helicopter.java:218)


class WatchMissionTests(unittest.TestCase):
    setUp, tearDown = carnet_helpers.VoiceMissionTests.setUp, carnet_helpers.VoiceMissionTests.tearDown
    voice_sim = carnet_helpers.VoiceMissionTests.voice_sim

    def world(self, name):
        sim = self.voice_sim(name)
        rt = sim.server.rt
        rt.execute(WATCH_WORLD)
        # The game loads every server file of the mod: the set-up of the target place registers itself (no require).
        rt.eval("require('RadioSurvivor/RS_MissionTarget')")
        # Same for the fact sources of the watches (server/CoreAI/WatchFacts/).
        for source in FACT_SOURCES:
            rt.eval(f"require('CoreAI/WatchFacts/{source}')")
        return sim, rt.eval("require('RadioSurvivor/RS_MissionVoice')"), rt.eval("require('CoreAI/CA_NotebookStore')")

    def sheet(self, sim, section):
        return sheet_double(sim.server.rt, SHEET_PLACES, section, 'watch', 'watch')

    def start(self, sim, voice, store, sheet):
        return voice.start(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000, 'watch')

    def stand(self, sim, x, y, who='alice'):
        p = sim.server.g.PLAYERS[who]
        p.x, p.y = x, y

    def poll(self, sim, store, real_ms=5000, who=('alice',)):
        """Server poll of the engine (CA_Missions.observe) with the server copies of the players, after real_ms."""
        sim.clock.offset += real_ms
        rt = sim.server.rt
        present = rt.table_from([rt.table_from({'player': sim.server.g.PLAYERS[name],
                                                'character': sim.character(name)}) for name in who])
        return rt.eval("require('CoreAI/CA_Missions')").observe(store.data, present, store)

    def advance(self, sim, store, hours, steps=1, **kw):
        """The game clock moves `hours` game hours in `steps` equal steps, one engine poll after each."""
        for _ in range(steps):
            sim.server.g.WORLD_AGE_HOURS = sim.server.g.WORLD_AGE_HOURS + hours / steps
            self.poll(sim, store, **kw)

    def report(self, sim, voice, store, sheet):
        return voice.report(store, sheet, sim.character('alice'), sim.server.g.PLAYERS.alice, 160000)

    def ready(self, sim, m):
        return sim.server.rt.eval("require('CoreAI/CA_Missions')").reportReady(m)

    def started(self, name, params=None):
        sim, voice, store = self.world(name)
        sheet = self.sheet(sim, {'target': 'post', 'params': params or {}})
        m = self.start(sim, voice, store, sheet)
        self.assertFalse(isinstance(m, tuple), str(m))
        return sim, voice, store, sheet, m

    def watching(self, name, params=None):
        """Started, alice at the post, first reading taken."""
        sim, voice, store, sheet, m = self.started(name, params)
        self.stand(sim, *POST)
        self.poll(sim, store)
        return sim, voice, store, sheet, m

    def test_mission_is_given_by_a_voice_at_the_target_place(self):
        sim, voice, store, sheet, m = self.started('watch-start')
        self.assertEqual((m.template, m.donor, m.report, m.state), ('watch', 'voice', 'radio', 'active'))
        self.assertEqual((m.place, m.hours, m.watched, m.spot.x, m.spot.y), ('Water tower', 2, 0, 60, 60))
        self.assertFalse(self.ready(sim, m))
        self.assertEqual(self.report(sim, voice, store, sheet), (None, 'not_done'))

    def test_hours_of_the_section(self):
        sim, voice, store, sheet, m = self.started('watch-hours', {'hours': 5})
        self.assertEqual(m.hours, 5)

    def test_duration_counts_game_time_and_stops_while_paused(self):
        sim, voice, store, sheet, m = self.watching('watch-time')
        for _ in range(20):                     # ten real minutes, game paused: the world age does not move
            self.poll(sim, store, real_ms=30000)
        self.assertEqual(m.watched, 0)
        self.advance(sim, store, 1.75, steps=7)
        self.assertAlmostEqual(m.watched, 1.75)
        self.assertFalse(self.ready(sim, m))
        self.advance(sim, store, 0.25)
        self.assertTrue(self.ready(sim, m))

    def test_faster_game_speed_ends_the_watch_sooner(self):
        # 100 real seconds; at normal speed one game hour lasts 225 real s (day of 90 minutes, GameTime.java:867).
        results = {}
        for speed in (1, 3):
            sim, voice, store, sheet, m = self.watching(f'watch-speed-{speed}', {'hours': 1})
            self.advance(sim, store, 100 * speed / 225, steps=100, real_ms=1000)
            results[speed] = self.ready(sim, m)
        self.assertEqual(results, {1: False, 3: True})

    def test_short_absence_is_tolerated_and_not_counted(self):
        sim, voice, store, sheet, m = self.watching('watch-short')
        self.advance(sim, store, 1, steps=4)
        self.stand(sim, 80, 60)                 # 20 tiles away, out of the watch radius
        self.advance(sim, store, 5 / 60, steps=5)
        self.assertAlmostEqual(m.watched, 1)
        self.stand(sim, 63, 58)                 # back within the radius
        self.poll(sim, store)
        self.advance(sim, store, 0.5, steps=2)
        self.assertAlmostEqual(m.watched, 1.5)
        self.assertEqual(m.breaks, 0)

    def test_long_absence_resets_the_watch(self):
        sim, voice, store, sheet, m = self.watching('watch-long')
        self.advance(sim, store, 1.5, steps=6)
        self.stand(sim, 80, 60)
        self.advance(sim, store, 15 / 60, steps=6)
        self.assertEqual((m.watched, m.breaks), (0, 1))
        self.stand(sim, *POST)
        self.poll(sim, store)                   # the watch starts again from this reading
        self.advance(sim, store, 1.5, steps=6)
        self.assertAlmostEqual(m.watched, 1.5)
        self.assertFalse(self.ready(sim, m))
        self.advance(sim, store, 0.5, steps=2)
        self.assertTrue(self.ready(sim, m))

    def test_time_nobody_read_at_the_spot_is_a_long_absence(self):
        # Every participant disconnected (no reading at all) while the world goes on: the watch starts again.
        sim, voice, store, sheet, m = self.watching('watch-gap')
        self.advance(sim, store, 1, steps=4)
        sim.server.g.WORLD_AGE_HOURS = sim.server.g.WORLD_AGE_HOURS + 3
        self.poll(sim, store)
        self.assertEqual((m.watched, m.breaks), (0, 1))

    def test_another_participant_at_the_spot_keeps_the_watch(self):
        sim, voice, store, sheet, m = self.watching('watch-two')
        alice, bob = sim.character('alice'), sim.character('bob')
        m.participants[bob] = sim.server.rt.table_from({'name': 'Bob'})
        self.stand(sim, 10, 10, who='bob')      # bob is far away, alice keeps watch
        for order in (('bob', 'alice'), ('alice', 'bob')):
            self.advance(sim, store, 0.5, steps=2, who=order)
        self.assertAlmostEqual(m.watched, 1)
        self.assertEqual(m.breaks, 0)
        self.assertTrue(alice != bob)

    def test_finished_watch_stays_finished_and_report_is_accepted(self):
        sim, voice, store, sheet, m = self.watching('watch-report')
        self.advance(sim, store, 2, steps=8)
        self.assertTrue(self.ready(sim, m))
        self.stand(sim, 200, 200)
        self.advance(sim, store, 1, steps=4)
        self.assertTrue(self.ready(sim, m))
        self.assertEqual(self.report(sim, voice, store, sheet).id, m.id)
        self.assertEqual(m.state, 'success')

    def test_helicopter_and_horde_are_recorded_during_the_watch(self):
        sim, voice, store, sheet, m = self.watching('watch-facts')
        g = sim.server.g
        g.worldSound(400, 60, *HELICOPTER)      # 340 tiles away: heard
        self.poll(sim, store)
        self.assertTrue(m.facts.helicopter)
        g.zombiesAt(12, 70, 66)                 # a dozen dead within 30 tiles
        self.poll(sim, store)
        self.assertTrue(m.facts.horde)

    def test_other_sounds_far_flights_few_dead_and_times_outside_the_watch_are_not_facts(self):
        sim, voice, store, sheet, m = self.started('watch-nofacts')
        g = sim.server.g
        g.worldSound(60, 60, *HELICOPTER)       # before anyone stands at the spot
        g.zombiesAt(20, 62, 62)
        self.stand(sim, 80, 60)
        self.poll(sim, store)
        self.assertIsNone(m.facts.helicopter)
        self.assertIsNone(m.facts.horde)
        sim2, _, store2, _, m2 = self.watching('watch-nofacts-2')
        g2 = sim2.server.g
        g2.worldSound(60, 60, 600, 600)         # ambient sound (AmbientStreamManager.java:468)
        g2.worldSound(1200, 60, *HELICOPTER)    # helicopter too far
        g2.zombiesAt(5, 62, 62)                 # a few dead only
        g2.zombiesAt(20, 120, 60)               # a horde far away
        g2.zombiesAt(20, 58, 58, True)          # bodies of an NPC engine (reanimated players): people
        self.poll(sim2, store2)
        self.assertIsNone(m2.facts.helicopter)
        self.assertIsNone(m2.facts.horde)

    def test_start_refused_with_bad_hours(self):
        for section, why in (({'target': 'post', 'params': {'hours': 0}}, 'bad_hours'),
                             ({'target': 'post', 'params': {'hours': 99}}, 'bad_hours')):
            with self.subTest(section=section):
                sim, voice, store = self.world('watch-refused-' + why + str(len(section)))
                self.assertEqual(self.start(sim, voice, store, self.sheet(sim, section)), (None, why))
                self.assertEqual([m for m in sim.state().missions.values() if m.donor == 'voice'], [])

    def test_npc_fiches_are_never_offered_a_watch(self):
        sim, _, _ = self.world('watch-npc')
        offer = sim.server.rt.eval("""(function()
            local c = require('CoreAI/CA_MissionConfig').Missions.watch
            return require('CoreAI/CA_MissionWatch').offer(c, {id = 'npc1', incarnation = 1}, {}, nil)
        end)()""")
        self.assertIsNone(offer)

    def test_notebook_page_and_map_circle(self):
        sim, voice, store, sheet, m = self.started('watch-page')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load_notebook()
        maps = c.rt.eval("require('CoreAI/CA_MapZones')")
        maps.resetForTests(); maps.resetZonesForTests()
        sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
        drawn = [convert(s) for s in carnet_helpers.lua_list(c.rt.eval('mapSymbols()'))]
        self.assertEqual([s['text'] for s in drawn if s['kind'] == 'text'], ['IGUI_CA_MapZoneWatch|Custom'])
        self.assertEqual([(s['x'], s['y']) for s in drawn if s['kind'] == 'texture'], [POST])
        c.g.CoreAI.notebook.toggle()
        window = c.g.CoreAI.notebookClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        for key in ('IGUI_CA_WatchPlace|Water tower', 'IGUI_CA_WatchMapZone', 'IGUI_CA_WatchProgress|0|2',
                    'IGUI_CA_WatchRule|6|10', 'IGUI_CA_WatchReport'):
            self.assertIn(key, text)
        self.assertNotIn('IGUI_CA_WatchDone', text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a watch mission')
        self.stand(sim, *POST)
        self.poll(sim, store)
        self.advance(sim, store, 2, steps=8)
        sim.command('alice', 'snapshot', world=c.g.CoreAI.notebookClient.world, run=c.g.CoreAI.notebookClient.run)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_CA_WatchProgress|120|2', window.detail.text)
        self.assertIn('IGUI_CA_WatchDone', window.detail.text)


# E20-T02: fields of mission= (RS_MissionVoice.context); per-template facts come as job and facts only.
GENERIC_FIELDS = {'kind', 'state', 'turn', 'place', 'clues', 'remainingMs', 'toReport', 'reward', 'job', 'facts'}


class WatchBriefTests(unittest.TestCase):
    setUp, tearDown = WatchMissionTests.setUp, WatchMissionTests.tearDown
    voice_sim, world, sheet = WatchMissionTests.voice_sim, WatchMissionTests.world, WatchMissionTests.sheet
    start, stand, poll, advance = (WatchMissionTests.start, WatchMissionTests.stand, WatchMissionTests.poll,
                                   WatchMissionTests.advance)
    started, watching = WatchMissionTests.started, WatchMissionTests.watching

    def told(self, voice, ctx):
        field = voice.field(ctx)
        self.assertLessEqual(set(protocol.decode(bytes.fromhex(field))), GENERIC_FIELDS)
        mission = bridge_module.mission_context({'mission': field}, SimpleNamespace(marks=[]))
        return mission, bridge_module.mission_prompt(mission, 'Caller')

    def test_job_and_verified_facts_told_to_the_voice(self):
        sim, voice, store, sheet, m = self.watching('watch-brief')
        mission, prompt = self.told(voice, voice.context(m, 'not_yet'))
        self.assertEqual((mission['kind'], mission['place']), ('watch', 'Water tower'))
        self.assertIn('Keep watch', mission['job'])
        self.assertIn('Water tower', mission['job'])
        self.assertIn('Time watched at the spot (checked by the server): 0 of 120 game minutes.', prompt)
        self.assertNotIn('During the watch', prompt)
        self.assertIn('never add report_mission', prompt)
        sim.server.g.worldSound(100, 60, *HELICOPTER)
        sim.server.g.zombiesAt(15, 50, 50)
        self.advance(sim, store, 2, steps=8)
        heard = voice.heard(sheet, sim.server.g.PLAYERS.alice, sim.character('alice'), 160000, store)
        self.assertEqual((heard.turn, heard.toReport), ('report_due', True))
        _, prompt = self.told(voice, heard)
        self.assertIn('Time watched at the spot (checked by the server): 120 of 120 game minutes.', prompt)
        self.assertIn('During the watch: a helicopter flew over.', prompt)
        self.assertIn('During the watch: a large group of the dead moved nearby.', prompt)
        for coordinate in ('60', '100', '50'):
            self.assertNotIn(coordinate + ',', prompt)


class WatchSheetTests(unittest.TestCase):
    """The sheet reader accepts a watch section with a target place and the parameter hours (kind count), with the
    real RS_Persona and the template registered as at game load."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.tmp.name)
        (cls.folder / '_places.txt').write_text(PLACES, encoding='utf-8')   # E25-T01: shared places of the cases
        cls.lua = LuaPersona(cls.folder)
        cls.lua.rt.eval('require("CoreAI/CA_MissionWatch")')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, body: str):
        (self.folder / 'case.txt').write_bytes((BASE + '[mission m]\n' + body + PROMPT).encode('utf-8'))
        return self.lua.read('case.txt')

    def test_valid_section(self):
        p = self.read('type=watch\ntarget=clinic\nhours=3\n')
        self.assertFalse(isinstance(p, tuple), p)
        m = p.missions[1]
        self.assertEqual((m.type, m.target.kind, m.target.id, m.params['hours']), ('watch', 'place', 'clinic', 3))

    def test_refusals(self):
        for body, why in (
                ('type=watch\ntarget=clinic\nhours=long\n',
                 "line 8: bad count 'long' (whole number from 0 to 999999)"),
                ('type=watch\ntarget=clinic\ncount=2\n', "line 8: unknown key 'count' for mission type 'watch'")):
            with self.subTest(body=body):
                self.assertEqual(self.read(body), (None, why))


if __name__ == '__main__':
    unittest.main()
