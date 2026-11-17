"""Suites en jeu rs.memorial.animals (E14-T04) et ca.missions.unclaimed (E16-T10) exécutées par le vrai moteur RST
sur le serveur du carnet simulé (lupa, mêmes doublures que tests/radiosurvivor/test_bulletin.py et tests/radiosurvivor/test_memorial.py).

    python tests/radiosurvivor/test_rs_e14_e16_suites.py

Couvre : les deux suites passent sur le banc ; chacune échoue sur un défaut injecté dans le vrai module :
- rs.memorial.animals : un animal tué consigné comme une mort (RS_Facts.characterDeath sans le contrôle isAnimal) ;
  la phrase des morts donnée au pont qui refuse les noms (ancienne consigne « do not name them ») ;
- ca.missions.unclaimed : un lot réussi non réclamé perdu avant 7 jours de jeu (rétention ramenée à 5 jours).
Doublures du jeu : animal (IsoAnimal, AnimalDefinitions, addAnimal) réduit à ce que la suite appelle. Ne prouve pas
l'API Java : les suites en jeu restent la preuve (campagnes solo-rs et mp).
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
import test_bulletin as tb
from bench_game import lua_list

from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
TESTS_LUA = tests_lua() / 'shared'
SUITES = TESTS_LUA / 'RST/suites'

# Animal of the game reduced to what rs.memorial.animals calls (Java references in the comments). Helper classes of
# the bench (suffix Double): instanceof answers for the Java class and its parents listed in __kinds.
ANIMAL_DOUBLES = r'''
local function class(name, kinds)
    local c = { __javaName = name, __kinds = kinds }
    c.__index = c
    return c
end
local ANIMAL_KINDS = { IsoAnimal = true, IsoPlayer = true, IsoGameCharacter = true, IsoMovingObject = true }
local Animal = class('IsoAnimalDouble', ANIMAL_KINDS)   -- IsoAnimal.java:136 extends IsoPlayer
local Desc = class('SurvivorDescDouble', { SurvivorDesc = true })
local Breed = class('AnimalBreedDouble', { AnimalBreed = true })
local Def = class('AnimalDefinitionsDouble', { AnimalDefinitions = true })
ANIMALS = { spawned = 0, removed = 0, alive = {} }
-- Default names of a descriptor, kept by an animal (SurvivorDesc.java:50, 54).
function Desc:getForename() return 'None' end
function Desc:getSurname() return 'None' end
function Breed:getName() return self.name end
function Def:getAnimalType() return self.animalType end
function Def:getBreedByName(name) return self.breeds[name] end   -- AnimalDefinitions.java:675
local HEN = setmetatable({ animalType = 'hen',
    breeds = { rhodeisland = setmetatable({ name = 'rhodeisland' }, Breed) } }, Def)
AnimalDefinitions = { getDef = function(animalType) return animalType == 'hen' and HEN or nil end }  -- :691
-- LuaManager.java:3013-3020: new IsoAnimal(cell, x, y, z, type, breed), not yet in the world.
addAnimal = function(cell, x, y, z, animalType, breed)
    ANIMALS.spawned = ANIMALS.spawned + 1
    return setmetatable({ x = x, y = y, z = z, health = 1, md = {}, desc = setmetatable({}, Desc) }, Animal)
end
function Animal:addToWorld() ANIMALS.alive[self] = true end
function Animal:remove() ANIMALS.alive[self] = nil; ANIMALS.removed = ANIMALS.removed + 1 end   -- IsoAnimal.java:3091
function Animal:isExistInTheWorld() return ANIMALS.alive[self] == true end
function Animal:isAnimal() return true end                        -- IsoGameCharacter.java:13989
function Animal:getDescriptor() return self.desc end
function Animal:getModData() return self.md end
function Animal:getUsername() return nil end
function Animal:getX() return self.x end
function Animal:getY() return self.y end
function Animal:getZ() return self.z end
-- IsoGameCharacter.Kill (13697): health 0, onKilled -> IsoPlayer.onKilled (7771) -> DoDeath (1839) ->
-- IsoAnimal.OnDeath raises OnCharacterDeath (IsoAnimal.java:1068).
function Animal:Kill(killer)
    self.health = 0
    fire('OnCharacterDeath', self)
end
local baseInstanceof = instanceof
instanceof = function(o, c)
    local mt = type(o) == 'table' and getmetatable(o) or nil
    if type(mt) == 'table' and type(rawget(mt, '__kinds')) == 'table' then return mt.__kinds[c] == true end
    return baseInstanceof(o, c)
end
'''

# Injected defects (the suites must fail on each).
ANIMAL_RECORDED = r'''
local real = RS_Facts.characterDeath
RS_Facts.characterDeath = function(c)
    if instanceof(c, 'IsoAnimal') then RS_Facts.record('death', { name = 'None None' }, 'death|animal') return end
    real(c)
end
'''
NAMES_REFUSED = r'''
RS_Facts.deathsText = function(count)
    if type(count) ~= 'number' or count < 1 then return nil end
    return count .. ' survivors died since the last bulletin; do not name them.'
end
'''
LOT_DROPPED_EARLY = "require('CoreAI/CA_MissionConfig').UNCLAIMED_RETENTION_HOURS = 120"

Base = type('Base', (unittest.TestCase,),
            {k: v for k, v in tb.BulletinTests.__dict__.items() if not k.startswith('test_')})


class SuiteBench(Base):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-e14-e16-')
        self.path = Path(self.tmp.name)

    def start(self, defect=''):
        sim = tb.Simulation(self.path / 'rst', world='rstest_e14_e16')
        self.boot(sim)
        sim.server.g.WORLD_HOURS = 50
        sim.add_client('alice')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.rt.execute(f'package.path = [[{TESTS_LUA.as_posix()}/?.lua;]] .. package.path')
        # getWorld is a Python function of the Simulation: wrapped in Lua for the world guard of RST (rstest*).
        self.rt.execute('local base = getWorld; getWorld = function() return base() end')
        self.rt.execute(ANIMAL_DOUBLES)
        for name in ('RS_MemorialAnimals.lua', 'CA_MissionUnclaimed.lua'):
            self.rt.execute((SUITES / name).read_text(encoding='utf-8'))
        if defect:
            self.rt.execute(defect)

    def run_suite(self, name):
        RST = self.g.RST
        ctx = self.rt.table_from({'player': self.g.PLAYERS.alice})
        self.assertTrue(RST.start(name, self.rt.table_from({'attach': False, 'ctx': ctx})))
        for _ in range(200):
            if not RST.running():
                break
            RST.step()
            self.sim.clock.offset += 1000
            self.g.fire('OnTick')
        self.assertFalse(RST.running())
        report = RST.last()
        return {r.test: (r.status, r.message) for r in lua_list(report.results)}

    def fact_rows(self):
        return [tb.convert(f) for f in lua_list(self.facts.list(0).facts)]

    def not_passed(self, results):
        return {k: v for k, v in results.items() if v[0] != 'PASS'}


class MemorialAnimalsTests(SuiteBench):
    def test_suite_passes_and_restores_the_fact_log(self):
        self.start()
        before = self.fact_rows()
        results = self.run_suite('rs.memorial.animals')
        self.assertEqual(len(results), 2, results)
        self.assertEqual(self.not_passed(results), {})
        self.assertEqual(self.fact_rows(), before, 'fact log not restored')
        self.assertEqual((self.g.ANIMALS.spawned, self.g.ANIMALS.removed), (1, 1), 'animal not removed')
        self.assertIsNone(self.facts.flight, 'bulletin left in flight')
        self.assertEqual(self.aired(), [], 'a test bulletin was aired')
        self.assertEqual(self.requests(), [], 'a test bulletin reached the bridge')

    def test_fails_when_a_killed_animal_is_recorded(self):
        self.start(ANIMAL_RECORDED)
        failed = self.not_passed(self.run_suite('rs.memorial.animals'))
        self.assertEqual(list(failed), ['a killed animal adds no death and no memorial name (E14-T04)'], failed)
        self.assertIn('added a fact', next(iter(failed.values()))[1])

    def test_fails_when_the_voice_is_told_to_refuse_the_names(self):
        self.start(NAMES_REFUSED)
        failed = self.not_passed(self.run_suite('rs.memorial.animals'))
        self.assertEqual(list(failed), ['bulletin announces the memorial names without refusing them (E14-T04)'],
                         failed)


class UnclaimedLotTests(SuiteBench):
    def test_suite_passes_and_restores_state(self):
        self.start()
        before = self.fact_rows()
        alice = self.g.PLAYERS.alice
        items = len(lua_list(alice.inv['items']))
        results = self.run_suite('ca.missions.unclaimed')
        self.assertEqual(len(results), 2, results)
        self.assertEqual(self.not_passed(results), {})
        self.assertEqual(self.fact_rows(), before, 'mission fact left in the fact log')
        self.assertEqual(len(lua_list(alice.inv['items'])), items, 'claimed reward left in the inventory')
        self.assertEqual(self.g.WORLD_HOURS, 50, 'world age changed')
        clock = self.rt.eval("require('CoreAI/CA_GameClock')")
        self.assertEqual(clock.hours(), 50, 'game clock of the engine left shifted')

    def test_fails_when_the_lot_is_gone_after_six_game_days(self):
        self.start(LOT_DROPPED_EARLY)
        failed = self.not_passed(self.run_suite('ca.missions.unclaimed'))
        self.assertIn('lot kept 6 game days, then claimed into the real inventory (E16-T10)', failed)
        self.assertIn('6 game days', failed['lot kept 6 game days, then claimed into the real inventory (E16-T10)'][1])


if __name__ == '__main__':
    unittest.main(verbosity=2)
