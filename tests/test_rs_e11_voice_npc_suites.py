"""In-game suite of E11-T17 run on the bench doubles (red on injected defects, green on the real code).

    python tests/test_rs_e11_voice_npc_suites.py

- rs.missions.voicetemplates (dev/.../suites/RS_MissionRadio.lua): the voice simulation of tests/test_carnet.py
  (VoiceMissionTests: real RadioSurvivor_Server and RS_Carnet_Server, scout metagrid), the clear density double of
  tests/test_mission_clear.py and the Signal Smoke double; zombies spawned by an addZombiesInOutfit double that fires
  OnHitZombie and OnZombieDead in the order of the game. The real RST engine runs the suite on the server machine.

Doubles only: nothing here proves the Java API (zombie hits, Signal Smoke); the campaigns do.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_carnet  # noqa: E402  (VoiceMissionTests reused without running its tests here)
from test_carnet import TESTS_SHARED  # noqa: E402
from test_mission_clear import CLEAR_WORLD  # noqa: E402

VOICE_SUITE = 'rs.missions.voicetemplates'
VOICE_TESTS = {
    'deliver': 'deliver: created for the caller only, drop at the voice\'s place, no report before collection',
    'retrieve': 'retrieve: created for the caller only as retrieve_id, no report without the card',
    'clear': 'clear: kill of the caller counted, report on the voice\'s frequency only, no reward doubled',
    'signal': 'signal: asked colour counted, report on the voice\'s frequency only, no reward doubled',
}

# Server machine of the voice simulation: RST moves played on the server copy, no cell square (moves and spawns do
# not wait for squares), zombies of addZombiesInOutfit with the hit and death order of the game.
VOICE_WORLD = r"""
local relay = sendServerCommand
sendServerCommand = function(p, module, command, args)
    if module == 'RST' then p.x, p.y, p.z = args.x, args.y, args.z; return end
    return relay(p, module, command, args)
end
local grid = getWorld():getMetaGrid()
getWorld = function() return {getGameMode = function() return setmetatable({}, {__tostring = function() return 'Multiplayer' end}) end,
    getWorld = function() return 'rstest-voicetemplates' end, getMetaGrid = function() return grid end} end
RandomizedWorldBase = RandomizedWorldBase or {}
local cell = getCell()
cell.getGridSquare = function() return nil end
getCell = function() return cell end
VoiceZombieDouble = {}
VoiceZombieDouble.Hit = function(self, weapon, wielder, damage)
    fire('OnHitZombie', self, wielder, nil, weapon)
    if damage >= 1 then self.attacker, self.dead = wielder, true; fire('OnZombieDead', self) end
end
VoiceZombieDouble.removeFromWorld = function(self) self.removed = true end
VoiceZombieDouble.removeFromSquare = function(self) end
VOICE_SPAWNED = {}
addZombiesInOutfit = function(x, y, z, n, outfit, female)
    local out = {}
    for i = 1, n do
        out[i] = setmetatable(zombieAt(x, y), {__index = VoiceZombieDouble})
        VOICE_SPAWNED[#VOICE_SPAWNED + 1] = out[i]
    end
    return list(out)
end
local p = PLAYERS.alice
p.god = false
p.isGodMod = function(self) return self.god end
p.setGodMod = function(self, v) self.god = v end
require 'RST/RST'
require 'RST/RST_Fixtures'
RST.Fixtures.WAIT_LOADED = false
"""


class VoiceTemplateSuiteTests(unittest.TestCase):
    """rs.missions.voicetemplates on the voice simulation (one caller online: char2 has no client)."""

    setUp = test_carnet.VoiceMissionTests.setUp
    tearDown = test_carnet.VoiceMissionTests.tearDown
    voice_sim = test_carnet.VoiceMissionTests.voice_sim

    def run_suite(self, defect=''):
        sim = self.voice_sim('suite')
        rt = sim.server.rt
        rt.execute(f'package.path = [[{TESTS_SHARED.as_posix()}/?.lua;]] .. package.path')
        rt.execute(CLEAR_WORLD)
        rt.execute(VOICE_WORLD)
        rt.execute((TESTS_SHARED / 'RST' / 'suites' / 'RS_MissionRadio.lua').read_text(encoding='utf-8'))
        if defect:
            rt.execute(defect)
        alice = sim.server.g.PLAYERS.alice
        self.assertTrue(rt.eval(f'function(p) return RST.start("{VOICE_SUITE}", '
                                '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(400):
            if not rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return sim, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_every_template_passes_and_cleans_up(self):
        sim, results = self.run_suite()
        self.assertEqual(results, {name: ('PASS', None) for name in VOICE_TESTS.values()})
        g = sim.server.g
        self.assertFalse(g.PLAYERS.alice.god, 'god mode not restored')
        spawned = list(g.VOICE_SPAWNED.values())
        self.assertEqual([z.dead for z in spawned], [True])
        # The notebook state never saw a mission of the suite.
        self.assertEqual([m for m in sim.state().missions.values() if m.donor == 'voice'], [])

    def test_report_on_another_frequency_accepted_fails(self):
        # Injected defect: the open mission of a caller is found whatever voice (frequency) is called.
        _, results = self.run_suite("""
            local V = require 'RadioSurvivor/RS_MissionVoice'
            local open = V.open
            V.open = function(state, voice, cid)
                local found = open(state, voice, cid)
                if found or type(state) ~= 'table' or type(state.missions) ~= 'table' then return found end
                for _, m in pairs(state.missions) do
                    if m.donor == 'voice' and m.state == 'active' and m.participants[cid] then return m end
                end
                return nil
            end""")
        for template in ('clear', 'signal'):
            status, message = results[VOICE_TESTS[template]]
            self.assertEqual(status, 'FAIL', template)
            self.assertIn('another', message, template)

    def test_second_report_rewarded_twice_fails(self):
        # Injected defect: a succeeded voice mission stays open, so a second report closes it again.
        _, results = self.run_suite("""
            local V = require 'RadioSurvivor/RS_MissionVoice'
            local report, done = V.report, {}
            V.report = function(store, sheet, cid, player, khz)
                local m = done[sheet.id .. ':' .. cid]
                if m then
                    store.data.outcomes[m.id .. '-' .. cid .. '-again'] = { action = 'mission.success' }
                    return m
                end
                local closed, why = report(store, sheet, cid, player, khz)
                if closed then done[sheet.id .. ':' .. cid] = closed end
                return closed, why
            end""")
        for template in ('clear', 'signal'):
            self.assertEqual(results[VOICE_TESTS[template]][0], 'FAIL', template)

    def test_mission_given_to_another_caller_fails(self):
        # Injected defect: every character of the state is engaged in the mission of a caller.
        _, results = self.run_suite("""
            local V = require 'RadioSurvivor/RS_MissionVoice'
            local start = V.start
            V.start = function(store, sheet, cid, player, khz, template)
                local m, why = start(store, sheet, cid, player, khz, template)
                if m then
                    for other, record in pairs(store.data.characters) do
                        if other ~= cid then m.participants[other] = { name = record.name } end
                    end
                end
                return m, why
            end""")
        for name in VOICE_TESTS.values():
            self.assertEqual(results[name][0], 'FAIL', name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
