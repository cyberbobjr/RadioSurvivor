"""Journal des faits du serveur (E14-T01) : RS_Facts.lua dans le vrai serveur du carnet (lupa, Lua 5.1, `next` retirÃ©
comme dans Kahlua), deux clients.

    python tests/test_facts.py

Couvre : liste fermÃ©e de sortes et de champs, bornes (par sorte et par jour, total, noms), aucune coordonnÃ©e
(lieu arrondi Ã  la ville par RS_Rescue.town, chaÃ®ne Ã  trois chiffres refusÃ©e), morts de joueurs (OnCharacterDeath :
joueurs seuls, une fois), missions closes (chaÃ®nÃ©es aprÃ¨s les observations, annulations ignorÃ©es), coupures du rÃ©seau
et de l'eau, dÃ©but d'un Ã©pisode mÃ©tÃ©o, faits publics de Living Knox, Ã©tat privÃ© (RS_State, survit au redÃ©marrage),
lecture et purge par le bulletin, expiration sans bulletin, faits en attente avant le chargement de l'Ã©tat.
Doublures du jeu de tests/test_carnet.py et tests/test_observations.py : ne prouve ni l'API Java rÃ©elle ni le
dÃ©clenchement rÃ©el de EveryHours ou d'OnCharacterDeath par le Java.
"""
from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, convert
from test_observations import GAME_CLOCK, WORLD_STUBS
from test_protocol import ROOT, lua_list

# Vanilla map loaded (RS_Rescue.town reads getLotDirectories); water shut-off (SandboxOptions.getWaterShutModifier,
# GameTime.getWorldAgeDaysSinceBegin, SandboxOptions.java:368, IsoObject.java:2544); Living Knox public API reduced to
# getGroup(...).name.
FACT_STUBS = r'''
getLotDirectories = function() return list({'Muldraugh, KY'}) end
WATER_SHUT, WORLD_DAYS = 14, 2
local worldOptions = getSandboxOptions
getSandboxOptions = function()
    local options = worldOptions()
    options.getWaterShutModifier = function() return WATER_SHUT end
    return options
end
local clockTime = getGameTime
getGameTime = function()
    local gt = clockTime()
    gt.getWorldAgeDaysSinceBegin = function() return WORLD_DAYS end
    return gt
end
LivingKnox = {API = {getGroup = function(id) return {name = 'The Millers of ' .. id} end}}
'''

MULDRAUGH = (10754, 9926)


def res(value):
    """(n, reason) of a Lua call that returns n alone on success."""
    return value if isinstance(value, tuple) else (value, None)


class FactsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-facts-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, name='facts', hours=48):
        sim = Simulation(self.path / name)
        sim.server.rt.execute(GAME_CLOCK)
        sim.server.rt.execute(WORLD_STUBS)
        sim.server.rt.execute(FACT_STUBS)
        sim.server.g.WORLD_HOURS = hours
        sim.add_client('alice')
        sim.add_client('bob')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.facts = self.rt.eval("require('RadioSurvivor/RS_Facts')")
        return sim

    def t(self, value):
        """Deep copy of a Python value into a Lua table (lists 1-based), as a caller would build it."""
        if isinstance(value, dict):
            return self.rt.table_from({k: self.t(v) for k, v in value.items()})
        if isinstance(value, list):
            return self.rt.table_from([self.t(v) for v in value])
        return value

    def listed(self, since=0):
        return [convert(f) for f in lua_list(self.facts.list(since).facts)]

    def kinds(self):
        return [f['kind'] for f in self.listed()]

    def hour(self, n=1):
        for _ in range(n):
            self.g.WORLD_HOURS += 1
            self.g.fire('EveryHours')

    def assert_no_coordinates(self, facts=None):
        """Only n, day and hour are numbers; no string carries three digits in a row; no field x, y or z."""
        def walk(value, path):
            if isinstance(value, dict):
                for k, v in value.items():
                    self.assertNotIn(k, ('x', 'y', 'z'), path)
                    walk(v, f'{path}.{k}')
            elif isinstance(value, (int, float)) and not isinstance(value, bool):
                self.assertIn(path.split('.')[-1], ('n', 'day', 'hour'), path)
            elif isinstance(value, str):
                self.assertIsNone(re.search(r'\d{3}', value), path)
        for f in facts if facts is not None else self.listed():
            walk(f, f['kind'])

    # ---------------------------------------------------------------------------------------------- pure core

    def test_closed_list_bounds_and_no_coordinates(self):
        self.world()
        F = self.facts
        book = F.newBook()
        add = lambda kind, fields=None, day=3, hour=12, key=None: res(F.add(book, kind, self.t(fields or {}), day, hour, key))
        self.assertEqual(add('rumour'), (None, 'kind'))
        self.assertEqual(add('death', {'name': 'Ann', 'x': 10754}), (None, 'field x'))
        # A place that carries anything else than its key and town is dropped from the fact.
        n0 = add('death', {'name': 'Ann', 'place': {'key': 'TownIn', 'town': 'Muldraugh', 'x': 1}}, key='ann')[0]
        self.assertNotIn('place', convert(lua_list(F.read(book, n0 - 1))[0]))
        F.drop(book, n0)
        # A name that carries a coordinate is dropped (and a death without a name is refused).
        self.assertEqual(add('death', {'name': 'Ann 10754,9926'}), (None, 'missing name'))
        self.assertEqual(add('death', {'name': 'Ann'}, day=0), (None, 'day'))
        self.assertEqual(add('death', {'name': 'Ann'}, hour=24), (None, 'hour'))
        n = add('death', {'name': '  Ann <b>Lee</b>\n' + 'y' * 80, 'place': {'key': 'TownIn', 'town': 'Atlantis'}})[0]
        fact = convert(lua_list(F.read(book, 0))[-1])
        self.assertEqual(fact['n'], n)
        self.assertLessEqual(len(fact['name']), F.MAX_CHARS)
        self.assertNotIn('<', fact['name'])
        self.assertNotIn('place', fact, 'unknown town kept')
        self.assertEqual(add('mission', {'result': 'success', 'participants': ['P%d' % i for i in range(12)]})[1], None)
        self.assertEqual(len(convert(lua_list(F.read(book, n))[0])['participants']), F.MAX_NAMES)
        # One fact per key while it is kept; a cap per kind and day.
        self.assertEqual(add('weather', {'weather': 'storm'}, key='w')[1], None)
        self.assertEqual(add('weather', {'weather': 'storm'}, key='w'), (None, 'duplicate'))
        for _ in range(int(F.CAPS.weather) - 1):
            add('weather', {'weather': 'blizzard'})
        self.assertEqual(add('weather', {'weather': 'storm'}), (None, 'cap'))
        self.assertIsNotNone(add('weather', {'weather': 'storm'}, day=4)[0])
        self.assert_no_coordinates([convert(f) for f in lua_list(F.read(book, 0))])

    def test_total_bound_keeps_the_deaths(self):
        self.world()
        F = self.facts
        book = F.newBook()
        first = res(F.add(book, 'death', self.t({'name': 'First Dead'}), 1, 8, None))[0]
        day = 1
        while int(book.next) <= int(F.MAX_FACTS) + 5:
            if res(F.add(book, 'passage', self.t({'event': 'crossing'}), day, 9, None))[0] is None:
                day += 1
        items = [convert(f) for f in lua_list(F.read(book, 0))]
        self.assertEqual(len(items), F.MAX_FACTS)
        self.assertEqual(items[0]['n'], first, 'the oldest death was evicted before older non-deaths')
        self.assertEqual(items[1]['n'], 7, 'the oldest non-death facts go first')

    # ---------------------------------------------------------------------------------------------- sources

    def test_player_deaths_once_with_a_rounded_place_in_the_private_state(self):
        self.world()
        alice = self.g.PLAYERS.alice
        alice.x, alice.y = MULDRAUGH
        self.g.fire('OnCharacterDeath', self.sim.zombie)  # zombies also raise OnCharacterDeath
        self.assertEqual(self.listed(), [])
        alice.dead = True
        self.g.fire('OnCharacterDeath', alice)
        self.g.fire('OnCharacterDeath', alice)
        deaths = self.listed()
        self.assertEqual(deaths, [{'n': 1, 'kind': 'death', 'day': 3, 'hour': 7, 'name': 'alice Doe',
                                   'place': {'key': 'TownIn', 'town': 'Muldraugh'}}])
        bob = self.g.PLAYERS.bob
        bob.x, bob.y = 10, 10
        self.g.fire('OnCharacterDeath', bob)
        self.assertEqual(self.listed(1)[0]['place'], {'key': 'TownFar'})
        self.assert_no_coordinates()
        # Private state of the notebook (server file), not a global ModData; survives a restart.
        self.assertEqual(int(self.sim.state().facts.next), 3)
        self.g.fire('OnSave')
        restart = Simulation(self.sim.path, self.sim.clock, saved_players=self.sim.saved())
        self.assertEqual([convert(f)['name'] for f in lua_list(restart.state().facts.list)], ['alice Doe', 'bob Doe'])

    def test_closed_missions_after_the_observation_listener(self):
        self.world()
        sim = self.sim
        alice, bob = sim.character('alice'), sim.character('bob')
        fid = self.g.RS_CarnetServer.ensure(2001).id
        state = sim.state()
        M = self.rt.eval("require('RadioSurvivor/RS_Missions')")
        Obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        z = self.sim.zombie
        z.x, z.y = MULDRAUGH
        sim.tick()
        m = M.create(state, state.npcs[fid], alice, None)
        self.assertTrue(M.accept(state, m, alice, 'Alice'))
        m.invited[bob] = True
        self.assertTrue(M.accept(state, m, bob, 'Bob'))
        self.assertTrue(M.finish(state, m, 'success'))
        facts = self.listed()
        self.assertEqual(len(facts), 1)
        f = facts[0]
        self.assertEqual((f['kind'], f['template'], f['result'], f['requester']),
                         ('mission', 'deliver', 'success', 'Real Bandit'))
        self.assertEqual(f['participants'], {1: 'Alice', 2: 'Bob'})
        self.assertEqual(f['place'], {'key': 'TownIn', 'town': 'Muldraugh'})
        # The observation listener of the notebook still runs (chained, not replaced).
        self.assertEqual(len([o for o in lua_list(Obs.list(fid)) if o.fact == 'mission_done']), 2)
        # A cancellation is not news; a failure is.
        for result in ('cancelled_dead', 'failed'):
            m2 = M.create(state, state.npcs[fid], alice, None)
            M.accept(state, m2, alice, 'Alice')
            M.finish(state, m2, result)
        self.assertEqual([f['result'] for f in self.listed()], ['success', 'failed'])
        # A listener set later (notebook reloaded) is wrapped again at the next poll, without a second fact.
        self.rt.execute("require('RadioSurvivor/RS_Missions').onFinished = "
                        "require('RadioSurvivor/RS_ObservationTriggers').missionFinished")
        self.hour()
        m3 = M.create(state, state.npcs[fid], alice, None)
        M.accept(state, m3, alice, 'Alice')
        M.finish(state, m3, 'abandoned')
        self.assertEqual([f['result'] for f in self.listed()], ['success', 'failed', 'abandoned'])
        self.assert_no_coordinates()

    def test_power_water_and_weather_on_transitions_only(self):
        self.world()
        self.hour(2)
        self.assertEqual(self.listed(), [])
        self.g.GRID = False
        self.g.WORLD_DAYS = 14
        self.hour()
        self.assertEqual(self.kinds(), ['power_cut', 'water_cut'])
        self.hour(3)
        self.assertEqual(self.kinds(), ['power_cut', 'water_cut'])
        # Restored by an admin, then cut again: a new cut.
        # One cut of each a day at most; restored by an admin, then cut again the next day: a new cut.
        self.g.GRID = True
        self.hour()
        self.g.GRID = False
        self.hour()
        self.assertEqual(self.kinds(), ['power_cut', 'water_cut'])
        self.g.GRID = True
        self.hour(24)
        self.g.GRID = False
        self.hour()
        self.assertEqual(self.kinds(), ['power_cut', 'water_cut', 'power_cut'], )
        # A storm over several hours is one fact; a blizzard after it is another.
        self.g.CLIMATE.running, self.g.CLIMATE.thunder = True, True
        self.hour(3)
        self.g.CLIMATE.thunder, self.g.CLIMATE.blizzard = False, True
        self.hour(2)
        self.g.CLIMATE.running = False
        self.hour()
        self.assertEqual([f.get('weather') for f in self.listed() if f['kind'] == 'weather'], ['storm', 'blizzard'])
        # Nothing while the hour does not advance (empty server in pause: no EveryHours).
        before = len(self.listed())
        self.g.CLIMATE.running, self.g.CLIMATE.tropical = True, True
        for _ in range(5):
            self.sim.tick()
        self.assertEqual(len(self.listed()), before)

    def test_no_cut_without_a_grid_seen_first(self):
        self.world()
        self.g.GRID = False
        self.g.WORLD_DAYS = 20
        self.hour(3)
        self.assertEqual(self.listed(), [])

    def test_living_knox_public_events(self):
        self.world()
        self.g.fire('OnLivingKnoxMemberDied', self.t({'group': 'grp-1', 'member': 'm-2', 'role': 'fighter',
            'offscreen': False, 'cause': 'firearm', 'byPlayer': True, 'area': {'x': 10750, 'y': 9950, 'size': 100},
            'groupAlive': 3, 'day': 3}))
        self.g.fire('OnLivingKnoxMemberDied', self.t({'group': 'grp-1', 'member': 'm-2', 'offscreen': True, 'day': 3}))
        self.g.fire('OnLivingKnoxGroupGone', self.t({'group': 'grp-1', 'reason': 'dead', 'total': 4, 'day': 3}))
        for i in range(5):
            self.g.fire('OnLivingKnoxGroupCreated', self.t({'group': 'grp-%d' % (i + 2), 'type': 'settlers',
                'typeNameKey': 'IGUI_LK_Type_settlers', 'name': 'Group %s' % 'ABCDE'[i], 'alive': 4, 'day': 3}))
        facts = self.listed()
        self.assertEqual(facts[0], {'n': 1, 'kind': 'group_death', 'day': 3, 'hour': 7, 'group': 'The Millers of grp-1',
                                    'role': 'fighter', 'cause': 'firearm', 'byPlayer': True, 'offscreen': False,
                                    'place': {'key': 'TownIn', 'town': 'Muldraugh'}})
        self.assertEqual(facts[1]['kind'], 'group_gone')
        self.assertEqual([f['group'] for f in facts[2:]], ['Group A', 'Group B', 'Group C'], 'cap of new groups a day')
        self.assert_no_coordinates()

    # ---------------------------------------------------------------------------------------------- reading

    def test_bulletin_reads_then_purges_and_expiry_without_bulletin(self):
        self.world()
        F = self.facts
        alice = self.g.PLAYERS.alice
        alice.dead = True
        self.g.fire('OnCharacterDeath', alice)
        F.record('passage', self.t({'event': 'crossing', 'place': {'key': 'TownOutskirts', 'town': 'West Point'}}))
        read = F.list()
        self.assertEqual((read.day, read.next, len(read.facts)), (3, 3, 2))
        self.assertEqual(F.placeText(read.facts[2].place), 'on the outskirts of West Point')
        # The bulletin is aired: it purges what it read; a fact recorded later stays for the next one.
        F.record('rescue', self.t({'result': 'in_time', 'participants': ['Alice']}))
        self.assertEqual(F.purge(read.next - 1), 2)
        self.assertEqual(self.kinds(), ['rescue'])
        self.assertEqual(int(self.sim.state().facts.next), 4)
        # Without a bulletin: the facts of a day are dropped at the start of the day after the next one.
        self.g.WORLD_HOURS = 3 * 24 - 1   # last hour of day 3
        self.hour()                       # day 4
        self.assertEqual(self.kinds(), ['rescue'])
        self.g.WORLD_HOURS = 4 * 24 - 1
        self.hour()                       # day 5
        self.assertEqual(self.kinds(), [])

    def test_pending_until_the_state_is_loaded(self):
        self.world()
        self.rt.execute("local S = require('RadioSurvivor/RS_State'); SAVED_DATA = S.data; S.data = nil")
        self.assertEqual(self.facts.record('weather', self.t({'weather': 'storm'})), (None, 'pending'))
        self.assertEqual(self.facts.record('weather', self.t({'x': 1})), (None, 'field x'))
        self.rt.execute("require('RadioSurvivor/RS_State').data = SAVED_DATA")
        self.assertEqual(self.kinds(), ['weather'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
