"""Suites en jeu rs.mission.clear, rs.mission.clearcount (E11-T04) et rs.observations (E08-T07, scène de mort à
ligne de vue garantie, gabarit de mission fourni) sur des bancs lupa.

- rs.mission.clear / rs.mission.clearcount : vrai moteur RST sur la machine serveur du banc du carnet
  (tests/test_mission_clear.py : métagrille, zombies et joueurs doublés) ; plus aucun SKIP faute de bâtiment
  peuplé (tirage sans densité minimale), FAIL sans bâtiment ; deux participants (alice, bob) : même k / N, tué hors
  du cercle ou après l'objectif non compté ; défauts injectés détectés.
- rs.observations : banc de tests/test_rs_mp_suites.py (serveur + deux clients) ; LosUtil doublé (murs par cases) :
  cases par défaut sans vue, recherche d'autres cases, FAIL si aucune ; création de mission refusée sans conditions
  d'offre (moteur à approvisionnements) : le gabarit fourni par la suite passe.
Doublures seulement : aucune API Java n'est prouvée ici (campagne MP).
python RadioSurvivor/tests/test_obs_clear_suites.py
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import test_mission_clear as tmc
import test_rs_mp_suites as mp
from test_carnet import TESTS_SHARED
from test_protocol import lua_list

CLEAR_SUITE = TESTS_SHARED / 'RST' / 'suites' / 'RS_MissionClear.lua'

# Doubles of the world for the clear suites (from tests/test_mission_clear.py, in-game suite test), plus loaded
# squares (outside the circle), online players and RST.Steps on the server.
CLEAR_DOUBLES = r"""
local relay = sendServerCommand
sendServerCommand = function(p, module, command, args)
    if module == 'RST' then p.x, p.y, p.z = args.x, args.y, args.z; return end
    return relay(p, module, command, args)
end
local grid = getWorld():getMetaGrid()
getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
    getWorld = function() return 'rstest-clear' end, getMetaGrid = function() return grid end} end
local baseCell = getCell
LOADED = LOADED == nil and true or LOADED
getCell = function()
    local cell = baseCell()
    if cell then
        cell.getGridSquare = function(_, x, y, z)
            if not LOADED then return nil end
            return {getX = function() return x end, getY = function() return y end, getZ = function() return z end,
                getStaticMovingObjects = function() return list({}) end}
        end
    end
    return cell
end
CLEAR_SPAWNED = {}
COUNT_OUTSIDE = false
addZombiesInOutfit = function(x, y, z, n, outfit, female)
    local out = {}
    for i = 1, n do
        local zz = zombieAt(x, y)
        function zz:Hit(weapon, wielder, damage)
            fire('OnHitZombie', self, wielder, nil, weapon)
            if damage >= 1 then self.attacker, self.dead = wielder, true; fire('OnZombieDead', self) end
        end
        function zz:Kill(killer) self.attacker, self.dead = killer, true; fire('OnZombieDead', self) end
        function zz:removeFromWorld() self.removed = true end
        function zz:removeFromSquare() end
        out[i] = zz
        CLEAR_SPAWNED[#CLEAR_SPAWNED + 1] = zz
    end
    return list(out)
end
ONLINE = { 'alice' }
getOnlinePlayers = function()
    local out = {}
    for _, name in ipairs(ONLINE) do out[#out + 1] = PLAYERS[name] end
    return list(out)
end
for name, p in pairs(PLAYERS) do
    p.getUsername = function(self) return self.username or name end
    p.god = false
    p.isGodMod = function(self) return self.god end
    p.setGodMod = function(self, v) self.god = v end
end
require 'RST/RST'
require 'RST/RST_Fixtures'
RST.Fixtures.WAIT_LOADED = false
"""

# Defects of RS_MissionClear injected after the suite is loaded (the suite must FAIL on each).
CLEAR_DEFECTS = {
    # A kill outside the circle is counted (inside ignored).
    'outside': r'''
        local C = require 'RadioSurvivor/RS_MissionClear'
        local count = C.count
        C.count = function(state, z, resolve)
            local saved = {}
            for _, m in pairs(state.missions) do saved[m] = m.mapZone; m.mapZone = {x = z:getX(), y = z:getY(), r = 1} end
            local res = count(state, z, resolve)
            for m, zone in pairs(saved) do m.mapZone = zone end
            return res
        end''',
    # Kills of the second participant credited to the first one.
    'oneTally': r'''
        local C = require 'RadioSurvivor/RS_MissionClear'
        local count = C.count
        C.count = function(state, z, resolve)
            return count(state, z, function(p) local c = resolve(p); if c == 'char2' then return 'char1' end; return c end)
        end''',
    # A kill after the target is still counted.
    'afterTarget': r'''
        local C = require 'RadioSurvivor/RS_MissionClear'
        C.reportReady = function() return false end''',
}


class ClearSuiteTests(unittest.TestCase):
    """rs.mission.clear et rs.mission.clearcount exécutées par le vrai moteur RST sur le serveur simulé."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-clearsuite-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_suite(self, name, setup='', defect=None):
        bench = tmc.ClearMissionTests()
        bench.path = self.path
        sim, npc, record, missions = bench.clear_sim('suite')
        rt = sim.server.rt
        rt.execute(f'package.path = [[{TESTS_SHARED.as_posix()}/?.lua;]] .. package.path')
        rt.execute(setup)
        rt.execute(CLEAR_DOUBLES)
        rt.execute(CLEAR_SUITE.read_text(encoding='utf-8'))
        if defect:
            rt.execute(CLEAR_DEFECTS[defect])
        alice = sim.server.g.PLAYERS.alice
        self.assertTrue(rt.eval(f'function(p) return RST.start("{name}", '
                                '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(600):
            if not rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        notes = []
        for r in report.results.values():
            if r.notes:
                notes.extend(lua_list(r.notes))
        return sim, results, notes

    def status(self, results):
        # rs.mission.clear: its solo test (real notebook, player actions) is skipped on this server machine.
        results = dict(results)
        solo = results.pop(tmc.SOLO_TEST, None)
        if solo is not None:
            self.assertEqual(solo[0], 'SKIP')
        [(status, message)] = results.values()
        return status, message or ''

    def test_clear_dense_site_passes(self):
        _, results, notes = self.run_suite('rs.mission.clear')
        self.assertEqual(self.status(results), ('PASS', ''))
        self.assertTrue(any('drawn building (draw 1)' in n for n in notes), notes)

    def test_clear_quiet_town_is_no_skip(self):
        # Every building under minDensity (the old SKIP): drawn again without minimum density, PASS.
        _, results, notes = self.run_suite('rs.mission.clear', 'RS_CLEAR.intensity = 0')
        self.assertEqual(self.status(results), ('PASS', ''))
        self.assertTrue(any('without minimum density' in n for n in notes), notes)

    def test_clear_without_building_fails(self):
        _, results, _ = self.run_suite(
            'rs.mission.clear', "require('RadioSurvivor/RS_MissionClear').site = function() return nil end")
        status, message = self.status(results)
        self.assertEqual(status, 'FAIL')
        self.assertIn('no building at all', message)

    def test_clearcount_skips_without_second_client(self):
        _, results, _ = self.run_suite('rs.mission.clearcount')
        status, message = self.status(results)
        self.assertEqual(status, 'SKIP')
        self.assertIn('no second client online', message)

    def two(self, defect=None, setup=''):
        """rs.mission.clearcount with bob online (second client, char2)."""
        original = CLEAR_DOUBLES
        try:
            globals()['CLEAR_DOUBLES'] = original.replace("ONLINE = { 'alice' }", "ONLINE = { 'alice', 'bob' }")
            return self.run_suite('rs.mission.clearcount', setup, defect)
        finally:
            globals()['CLEAR_DOUBLES'] = original

    def test_clearcount_pass_with_two_clients(self):
        sim, results, notes = self.two()
        self.assertEqual(self.status(results), ('PASS', ''))
        spawned = list(lua_list(sim.server.g.CLEAR_SPAWNED))
        self.assertEqual(len(spawned), 4)
        self.assertTrue(all(z.dead for z in spawned))
        self.assertTrue(any('zombie outside at' in n for n in notes), notes)

    def test_clearcount_detects_kill_outside_counted(self):
        _, results, _ = self.two('outside')
        status, message = self.status(results)
        self.assertEqual(status, 'FAIL')
        self.assertIn('outside the circle', message)

    def test_clearcount_detects_parts_merged(self):
        _, results, _ = self.two('oneTally')
        self.assertEqual(self.status(results)[0], 'FAIL')

    def test_clearcount_detects_count_after_target(self):
        _, results, _ = self.two('afterTarget')
        self.assertEqual(self.status(results)[0], 'FAIL')

    def test_clearcount_no_square_outside_fails(self):
        _, results, _ = self.two(setup='LOADED = false')
        status, message = self.status(results)
        self.assertEqual(status, 'FAIL')
        self.assertIn('no loaded square just outside the circle', message)


# LosUtil double for the observation bench: walls listed by square ("x,y"); a line is Blocked when one of its squares
# after the start (target included) is a wall, or when it enters or leaves the SHADOW box (squares seen from nowhere
# else, and seeing nothing else).
LOS_DOUBLE = r"""
WALLS = {}
LOS_CALLS = 0
SHADOW = nil
local function wall(x, y) return WALLS[math.floor(x) .. "," .. math.floor(y)] == true end
local function shaded(x, y)
    return SHADOW ~= nil and x >= SHADOW[1] and x <= SHADOW[3] and y >= SHADOW[2] and y <= SHADOW[4]
end
LosUtil = { lineClear = function(cell, x0, y0, z0, x1, y1, z1, doors)
    LOS_CALLS = LOS_CALLS + 1
    if (x0 ~= x1 or y0 ~= y1) and (shaded(x0, y0) or shaded(x1, y1)) then return "Blocked" end
    local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
    for i = 1, n do
        local x = x0 + math.floor((x1 - x0) * i / n + 0.5)
        local y = y0 + math.floor((y1 - y0) * i / n + 0.5)
        if wall(x, y) then return "Blocked" end
    end
    return "Clear"
end }
local get = CELL.getGridSquare
function CELL:getGridSquare(x, y, z)
    local sq = get(self, x, y, z)
    if sq ~= nil then
        function sq:isFree() return not wall(self.x, self.y) end
    end
    return sq
end
-- Bodies see as LosUtil does (CanSee = lineClear ~= Blocked).
local spawn = LivingKnox.API.testSpawnNpc
LivingKnox.API.testSpawnNpc = function(x, y, z)
    if wall(x, y) then return nil, "square not free" end
    local id, why = spawn(x, y, z)
    if id ~= nil then
        local b = LivingKnox.Bodies.find(id)
        function b:CanSee(o)
            return LosUtil.lineClear(nil, math.floor(self.x), math.floor(self.y), 0, math.floor(o.x), math.floor(o.y), 0,
                false) ~= "Blocked"
        end
    end
    return id, why
end
"""


class ObservationSceneTests(mp.Bench):
    """rs.observations : cases de la scène de mort choisies avec une ligne de vue ; gabarit de mission fourni."""

    def run_obs(self, lua='', solo=False):
        net = self.net(solo=solo)
        net.server.lua(LOS_DOUBLE + lua)
        return net.run('rs.observations')

    def death(self, rep):
        return rep.results[next(k for k in rep.results if k.startswith('group_death: the members'))]

    def death_notes(self, rep):
        return ' '.join(rep.notes.get(next(k for k in rep.results if k.startswith('group_death: the members')), []))

    def test_default_spots_kept_when_they_see(self):
        rep = self.run_obs()
        self.assertEqual({v[0] for v in rep.results.values()}, {'PASS'}, rep.results)
        self.assertIn('death scene: default spots', self.death_notes(rep))
        self.assertIn('witnesses expected: A, B', self.death_notes(rep))

    def test_wall_between_default_spots_moves_the_scene(self):
        # The default squares of A, B, D (1002..1003, 1000..1001 around the requester at 1000, 1000) see nothing.
        rep = self.run_obs('SHADOW = { 1001, 999, 1004, 1002 }')
        self.assertEqual(self.death(rep)[0], 'PASS', rep.results)
        notes = self.death_notes(rep)
        self.assertIn('searched spots', notes)
        self.assertIn('witnesses expected: A, B', notes)

    def test_no_square_with_a_line_of_sight_fails(self):
        # Walls everywhere but the requester's square: no scene, FAIL (never a SKIP).
        rep = self.run_obs('setmetatable(WALLS, { __index = function(_, k) return k ~= "1000,1000" end })')
        status, message = self.death(rep)
        self.assertEqual(status, 'FAIL')
        self.assertIn('group_death scene', message)

    def test_witness_blind_at_the_kill_fails(self):
        # Squares chosen with a line of sight, then A and B blind at the kill: FAIL (the old suite skipped).
        rep = self.run_obs(r'''
            local spawn = LivingKnox.API.testSpawnNpc
            LivingKnox.API.testSpawnNpc = function(x, y, z)
                local id, why = spawn(x, y, z)
                if id ~= nil then LivingKnox.Bodies.find(id).CanSee = function() return false end end
                return id, why
            end''')
        status, message = self.death(rep)
        self.assertEqual(status, 'FAIL')
        self.assertIn('neither A nor B sees D at the kill', message)

    def test_mission_done_with_supply_engine(self):
        # A mission engine that creates a deliver mission of an NPC fiche only with offer terms (engine supplies).
        rep = self.run_obs(r'''
            local create = M.create
            M.create = function(state, npc, cid, offerId, terms)
                if type(terms) ~= "table" or terms.kind ~= "supply" or offerId == nil then return nil end
                return create(state, npc, cid)
            end''')
        name = next(k for k in rep.results if k.startswith('mission_done'))
        self.assertEqual(rep.results[name][0], 'PASS', rep.results[name])

    def test_mission_refused_is_a_fail(self):
        rep = self.run_obs('M.create = function() return nil end')
        name = next(k for k in rep.results if k.startswith('mission_done'))
        status, message = rep.results[name]
        self.assertEqual(status, 'FAIL')
        self.assertIn('test mission of A not created', message)


if __name__ == '__main__':
    unittest.main(verbosity=2)
