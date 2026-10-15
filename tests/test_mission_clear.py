"""Gabarit « nettoyer » (E11-T04, RS_MissionClear.lua) sur le banc du carnet : vrai Lua serveur et client, pont
absent, doublures de la métagrille (densité des en-têtes de lot), des zombies et des joueurs.

Doublures seulement (aucune API Java prouvée ici) : IsoMetaGrid.getChunkDataFromTile rend un métachunk dont
getUnadjustedZombieIntensity vaut RS_CLEAR.intensity (0..255) ; un zombie du banc porte sa position, sa ModData,
getAttackedBy et isOnFire ; tuer = OnHitZombie (sauf mort sans coup) puis OnZombieDead sur le serveur, comme
IsoZombie.Hit -> die() -> Kill -> onKilled (IsoZombie.java:1109-1112, IsoGameCharacter.java:5836-5844).
python RadioSurvivor/tests/test_mission_clear.py
"""
from __future__ import annotations

import tempfile
import unittest
import unittest.mock
from pathlib import Path

from test_carnet import (MAP_DOUBLE, NOTEBOOK_UI, SCOUT_GRID, TESTS_SHARED, ReportCases, Simulation, convert,
                         report_turn)
from test_protocol import lua_list
import npc_protocol as protocol

# Density of the lot headers and zombie doubles of the server machine (installed after the Simulation is built).
# House 5002 of SCOUT_GRID: 100..110 x 10..20, z 0 -> counting circle centred on (105, 15), radius 30.
SOLO_TEST = ('solo: melee, firearm and car kills counted, burnt zombie not, report and claim in the notebook')

CLEAR_WORLD = r"""
RS_CLEAR = {intensity = 128, reads = 0}
function SCOUT_GRID:getChunkDataFromTile(x, y)
    RS_CLEAR.reads = RS_CLEAR.reads + 1
    return {getUnadjustedZombieIntensity = function() return RS_CLEAR.intensity end}
end
for _, p in pairs(PLAYERS) do p.getVehicle = function(self) return self.vehicle end end
local seq = 0
function zombieAt(x, y)
    seq = seq + 1
    local z = {id = 'zombie' .. seq, x = x, y = y, md = nil, attacker = nil, fire = false, dead = false}
    function z:getX() return self.x end
    function z:getY() return self.y end
    function z:getZ() return 0 end
    function z:hasModData() return self.md ~= nil end
    function z:getModData() self.md = self.md or {}; return self.md end
    function z:getAttackedBy() return self.attacker end
    function z:isOnFire() return self.fire end
    function z:isDead() return self.dead end
    return z
end
-- Lethal hit of a player (weapon or nil), or a death without hit (hit = false).
function killZombie(z, player, hit)
    if hit ~= false and player then fire('OnHitZombie', z, player, nil, item('Base.BaseballBat')) end
    z.attacker = player
    z.dead = true
    fire('OnZombieDead', z)
end
"""


class ClearMissionTests(unittest.TestCase):
    """Décompte serveur des zombies tués dans le cercle par les participants, une seule fois chacun ; feu, coup ancien,
    non-participant, hors zone et corps de PNJ non comptés ; réussite au N-ième par le moteur commun."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-clear-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, sim):
        sim.server.rt.execute(SCOUT_GRID)
        sim.server.g.scoutHouse(5001, 20, 12, 8, 8)    # too close to the requester
        sim.server.g.scoutHouse(5002, 100, 10, 10, 10)  # reachable
        sim.server.rt.execute(CLEAR_WORLD)
        sim.server.rt.eval("require('RadioSurvivor/RS_MissionClear')").resetForTests()

    def clear_sim(self, name='clear'):
        sim = Simulation(self.path / name)
        sim.add_client('alice'); sim.add_client('bob')
        self.world(sim)
        sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        record = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')").npc(2001)
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        return sim, npc, record, missions

    def catalog(self, sim, npc, record):
        return convert(sim.server.g.RS_CarnetServer.offerCatalogFor(npc, record))

    def active(self, name='clear', bob=False):
        sim, npc, record, missions = self.clear_sim(name)
        self.assertIn('clear_v1', self.catalog(sim, npc, record))
        m = missions.create(sim.state(), npc, sim.character('alice'), 'clear_v1')
        sim.request_mission('alice', 'accept')
        self.assertEqual(m.state, 'active')
        if bob:
            char = sim.character('bob')
            m.invited[char] = True
            sim.state().characters[char].knownMissions[m.id] = True
            sim.request_mission('bob', 'accept')
            self.assertIsNotNone(m.participants[char])
        return sim, npc, m, missions

    def kill(self, sim, who, x=105, y=15, hit=True, after_ms=0):
        g = sim.server.g
        z = g.zombieAt(x, y)
        player = g.PLAYERS[who] if who else None
        if hit and player is not None:
            g.fire('OnHitZombie', z, player, None, g.item('Base.BaseballBat'))
        sim.clock.offset += after_ms
        z.attacker = player
        z.dead = True
        g.fire('OnZombieDead', z)
        return z

    def row(self, sim, name):
        rows = [convert(r) for r in lua_list(sim.clients[name].g.RS_CarnetClient.snapshot.missions)]
        [row] = [r for r in rows if r['template'] == 'clear']
        return row

    def test_offer_names_a_place_and_a_bounded_target_from_the_density(self):
        sim, npc, record, missions = self.clear_sim('offer')
        g = sim.server.g
        catalog = self.catalog(sim, npc, record)
        self.assertEqual(sorted(catalog), ['clear_v1', 'first_aid_v1', 'scout_v1', 'signal_v1'])  # signal_v1: required mod Signal Smoke (bench double), same places as scout
        offer = catalog['clear_v1']
        self.assertEqual(set(offer), {'kind', 'place', 'clues', 'kills', 'report', 'durationMs', 'rewardType',
                                      'rewardCount'})
        self.assertEqual((offer['kind'], offer['place'], offer['report'], offer['kills']),
                         ('clear', 'house', 'in_person', 25))
        self.assertEqual((offer['durationMs'], offer['rewardType'], offer['rewardCount']), (7200000, 'Base.Bullets9mm', 20))
        clues = [offer['clues'][i] for i in sorted(offer['clues'])]
        self.assertTrue(clues and clues[0].startswith('The place is '), clues)
        self.assertFalse(any(ch.isdigit() for line in clues for ch in line), 'a clue carries a number')
        self.assertEqual(self.catalog(sim, npc, record)['clear_v1'], offer, 'the kept place changed')
        clear = sim.server.rt.eval("require('RadioSurvivor/RS_MissionClear')")
        c = sim.server.rt.eval("require('RadioSurvivor/RS_Config').Missions.clear")
        # Target from the density: bounds, sandbox multiplier, uniform distribution, no zombie at all.
        self.assertEqual([clear.target(c, d) for d in (0.04, 0.25, 0.5, 3.0)], [8, 16, 25, 25])
        zone = sim.server.rt.table_from({'x': 105, 'y': 15, 'r': 30})
        grid = g.SCOUT_GRID
        g.RS_CLEAR.intensity = 64
        self.assertAlmostEqual(clear.density(grid, zone), 64 / 255)
        g.SandboxVars.ZombieConfig = sim.server.rt.table_from({'PopulationMultiplier': 2.0})
        self.assertAlmostEqual(clear.density(grid, zone), 128 / 255)
        g.RS_CLEAR.intensity = 0
        g.SandboxVars.Distribution = 2
        self.assertAlmostEqual(clear.density(grid, zone), 256 / 255)
        g.SandboxVars.Distribution = 1
        g.SandboxVars.Zombies = 6
        self.assertEqual(clear.density(grid, zone), 0)
        # Too few zombies around the place, a radio voice donor, a metagrid without density: no clear offer.
        g.SandboxVars.Zombies = 4
        g.SandboxVars.ZombieConfig = None
        g.RS_CLEAR.intensity = 5
        clear.resetForTests()
        self.assertIsNone(clear.offer(c, npc, None, g.PLAYERS.alice))
        g.RS_CLEAR.intensity = 128
        clear.resetForTests()
        donor = sim.server.rt.table_from({'id': 'voice:walt:c1', 'missionCount': 0})
        self.assertIsNone(clear.offer(c, donor, None, g.PLAYERS.alice))
        self.assertTrue(sim.server.rt.eval("require('RadioSurvivor/RS_MissionVoice')").TEMPLATES['clear'])
        g.SCOUT_GRID.getChunkDataFromTile = None
        self.assertNotIn('clear_v1', self.catalog(sim, npc, record))

    def test_mission_circle_on_the_map_and_no_coordinate_to_the_bridge(self):
        sim, npc, m, missions = self.active('create')
        self.assertEqual((m.id, m.template, m.offer, m.place, m.target, m.kills), (npc.id + '-clear1', 'clear',
                                                                                 'clear_v1', 'house', 25, 0))
        self.assertEqual(convert(m.mapZone), {'x': 105, 'y': 15, 'r': 30})
        context = convert(missions.context(m))
        self.assertEqual((context['kind'], context['kills'], context['target'], context['report'], context['toReport']),
                         ('clear', 0, 25, 'in_person', False))
        for key in ('mapZone', 'tally', 'siteKey', 'x', 'y'):
            self.assertNotIn(key, context)
        row = self.row(sim, 'alice')
        self.assertEqual((row['kills'], row['target'], row['mapZone']), (0, 25, {'x': 105, 'y': 15, 'r': 30}))
        self.assertNotIn('siteKey', row)
        # A forged delivery finds nothing to accept.
        [bandage] = sim.items('alice', 'Base.Bandage')
        sim.request_mission('alice', 'prepare_delivery', items=[bandage])
        self.assertIsNone(sim.server.g.RS_CarnetServer.quotes[sim.character('alice')])
        self.assertEqual(sim.clients['alice'].g.RS_CarnetClient.lastError, 'Items')

    def test_two_participants_share_one_count_without_double_count(self):
        sim, npc, m, missions = self.active('shared', bob=True)
        g = sim.server.g
        alice, bob = sim.character('alice'), sim.character('bob')
        z1 = self.kill(sim, 'alice')
        self.kill(sim, 'bob', x=120, y=30)
        self.kill(sim, 'alice', x=80, y=5)
        self.assertEqual(m.kills, 3)
        self.assertEqual((m.tally[alice], m.tally[bob]), (2, 1))
        self.assertEqual(z1.md.RS_ClearCounted, m.id)
        # The same zombie dies again (fire, dragged corpse): no second count.
        z1.attacker = g.PLAYERS.alice
        g.fire('OnHitZombie', z1, g.PLAYERS.alice, None, g.item('Base.BaseballBat'))
        g.fire('OnZombieDead', z1)
        self.assertEqual(m.kills, 3)
        # Both notebooks show the same shared count and the same parts.
        for name in ('alice', 'bob'):
            row = self.row(sim, name)
            self.assertEqual((row['kills'], row['target']), (3, 25))
            self.assertEqual(row['tally'], {1: {'name': 'alice Doe', 'count': 2}, 2: {'name': 'bob Doe', 'count': 1}})

    def test_kills_not_counted(self):
        sim, npc, m, missions = self.active('ignored')
        g = sim.server.g
        self.kill(sim, 'bob')                       # not a participant
        self.kill(sim, 'alice', x=140, y=15)        # outside the circle (35 tiles from its centre)
        self.kill(sim, 'alice', after_ms=5001)      # last hit too old (owner client reported the death)
        self.kill(sim, 'alice', hit=False)          # attacker without any hit
        self.kill(sim, None)                        # no attacker (fall, Kill(nil), timed trap)
        burning = g.zombieAt(105, 15)               # fire: attacker reset at each burn, two death events
        burning.fire = True
        g.fire('OnZombieDead', burning)
        g.fire('OnZombieDead', burning)
        npc_body = g.spawn(3001, 'Other Bandit', False, 'k3001')  # NPC body of the provider
        npc_body.x, npc_body.y = 105, 15
        npc_body.getAttackedBy = lambda self: g.PLAYERS.alice
        npc_body.hasModData = lambda self: True
        npc_body.isOnFire = lambda self: False
        g.fire('OnHitZombie', npc_body, g.PLAYERS.alice, None, g.item('Base.BaseballBat'))
        g.fire('OnZombieDead', npc_body)
        sim.server.rt.execute("LivingKnox = {Identity = {readTag = function(md) return md.lkNpcId, md.lkNpcGen end}}")
        tagged = g.zombieAt(105, 15)                # body tagged by Living Knox (old generation)
        tagged.getModData(tagged).lkNpcId, tagged.md.lkNpcGen = 'lk-7', 1
        tagged.attacker = g.PLAYERS.alice
        g.fire('OnHitZombie', tagged, g.PLAYERS.alice, None, g.item('Base.BaseballBat'))
        g.fire('OnZombieDead', tagged)
        self.assertEqual((m.kills, m.state), (0, 'active'))
        # Run over by the participant at the wheel: counted without any hit event.
        g.PLAYERS.alice.vehicle = sim.server.rt.eval('function(p) return {getDriver = function() return p end} end')(
            g.PLAYERS.alice)
        self.kill(sim, 'alice', hit=False)
        self.assertEqual(m.kills, 1)

    def test_target_then_report_no_more_count_and_saved_count(self):
        sim, npc, m, missions = self.active('success')
        g = sim.server.g
        m.target = 3
        self.kill(sim, 'alice')
        self.kill(sim, 'alice')
        g.fire('OnSave')
        restart = Simulation(self.path / 'success', sim.clock, saved_players=sim.saved())
        self.world(restart)
        restart.add_client('alice')
        old = restart.mission()
        self.assertEqual((old.template, old.kills, old.target, old.state), ('clear', 2, 3, 'active'))
        restart.server.rt.execute(CLEAR_WORLD)
        z = restart.server.g.zombieAt(100, 20)
        restart.server.g.fire('OnHitZombie', z, restart.server.g.PLAYERS.alice, None, restart.server.g.item('Base.Axe'))
        z.attacker, z.dead = restart.server.g.PLAYERS.alice, True
        restart.server.g.fire('OnZombieDead', z)
        # E11-T13: the target reached is no success yet: the mission waits for its report and counts no more.
        self.assertEqual((old.kills, old.state), (3, 'active'))
        z2 = restart.server.g.zombieAt(100, 20)
        restart.server.g.fire('OnHitZombie', z2, restart.server.g.PLAYERS.alice, None, restart.server.g.item('Base.Axe'))
        z2.attacker = restart.server.g.PLAYERS.alice
        restart.server.g.fire('OnZombieDead', z2)
        self.assertEqual(old.kills, 3)
        self.assertIsNone(z2.md, 'a zombie after the target was marked')
        report_turn(restart, 'alice', 'The place is clear.', 'report_done')
        self.assertEqual(old.state, 'success')
        char = restart.character('alice')
        outcome = restart.state().outcomes[old.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        self.assertIsNone(restart.state().npcs[old.npc].mission)
        row = convert(restart.clients['alice'].g.RS_CarnetClient.snapshot.missions[1])
        self.assertNotIn('mapZone', row)

    def test_expiry_closes_the_mission(self):
        sim, npc, m, missions = self.active('expiry')
        self.kill(sim, 'alice')
        sim.clock.offset += 7200001; sim.tick()
        self.assertEqual((m.state, m.kills), ('failed', 1))
        self.kill(sim, 'alice')
        self.assertEqual(m.kills, 1)

    def test_notebook_page_and_area_label(self):
        sim, npc, m, missions = self.active('notebook')
        c = sim.clients['alice']
        c.rt.execute(MAP_DOUBLE)
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load('client/RS_Carnet_Client.lua')
        maps = c.rt.eval("require('RadioSurvivor/RS_MapActions')")
        maps.resetForTests(); maps.resetZonesForTests()
        self.kill(sim, 'alice')
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        texts = [convert(s)['text'] for s in lua_list(c.rt.eval('mapSymbols()')) if convert(s)['kind'] == 'text']
        self.assertEqual(texts, ['IGUI_RS_MapZoneClear|Real Bandit'])
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        label = c.rt.eval('RS_CarnetClient.window.list.items[1].text')
        self.assertTrue(label.startswith('IGUI_RS_Clear - '), label)
        for key in ('IGUI_RS_ScoutPlace', 'IGUI_RS_ScoutClues', 'IGUI_RS_ClearMapZone', 'IGUI_RS_ClearProgress|1',
                    'IGUI_RS_ClearBy|alice Doe', 'IGUI_RS_ClearRule', 'IGUI_RS_ClearReport'):
            self.assertIn(key, window.detail.text)
        for key in ('IGUI_RS_Progress', 'IGUI_RS_ScoutReport', 'IGUI_RS_NoRefund'):
            self.assertNotIn(key, window.detail.text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button for a clear mission')

    def test_offline_bridge_tells_the_offer(self):
        req = {'kind': 'npc_talk', 'language': 'EN', 'offers': {'clear_v1': {
            'kind': 'clear', 'place': 'house', 'clues': ['The place is a house.'], 'kills': 16, 'report': 'none',
            'durationMs': 7200000, 'rewardType': 'Base.Bullets9mm', 'rewardCount': 20}},
            'context': {}, 'character': 'c1', 'text': 'Work?', 'id': 'r1'}
        with unittest.mock.patch.object(protocol, 'bounded_reply', lambda r, reply: reply):
            reply = protocol.offline(req, intent='')
            self.assertEqual((reply['intent'], reply['offer']), ('offer', 'clear_v1'))
            self.assertIn('16', reply['text'])
            self.assertIn('120 minutes', reply['text'])
            req['language'] = 'FR'
            self.assertIn('Abattez-en 16', protocol.offline(req, intent='')['text'])

    def test_in_game_suite_on_the_simulated_server(self):
        """rs.mission.clear (dev mod) run by the real RST engine on the server machine; the server move of
        RST_Fixtures is played directly on the server copy of the player; addZombiesInOutfit, IsoZombie.Hit and Kill
        are doubles that fire the server events in the order of the game."""
        sim, npc, record, missions = self.clear_sim('suite')
        shared = (TESTS_SHARED.as_posix() + '/?.lua')
        sim.server.rt.execute(f'package.path = [[{shared};]] .. package.path')
        sim.server.rt.execute("""
            local relay = sendServerCommand
            sendServerCommand = function(p, module, command, args)
                if module == 'RST' then p.x, p.y, p.z = args.x, args.y, args.z; return end
                return relay(p, module, command, args)
            end
            local grid = getWorld():getMetaGrid()
            getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
                getWorld = function() return 'rstest-clear' end, getMetaGrid = function() return grid end} end
            local baseCell = getCell
            getCell = function()
                local cell = baseCell()
                if cell then cell.getGridSquare = function() return nil end end
                return cell
            end
            CLEAR_SPAWNED = {}
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
            local p = PLAYERS.alice
            p.god = false
            p.isGodMod = function(self) return self.god end
            p.setGodMod = function(self, v) self.god = v end
            require 'RST/RST'
            require 'RST/RST_Fixtures'
            RST.Fixtures.WAIT_LOADED = false   -- no square in this double: the move does not wait for them
        """)
        sim.server.rt.execute((TESTS_SHARED / 'RST' / 'suites' / 'RS_MissionClear.lua').read_text(encoding='utf-8'))
        alice = sim.server.g.PLAYERS.alice
        self.assertTrue(sim.server.rt.eval('function(p) return RST.start("rs.mission.clear", '
                                           '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(400):
            if not sim.server.rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        # The solo test of the player's own actions (real notebook) is skipped on a server machine.
        solo = results.pop(SOLO_TEST)
        self.assertEqual(solo[0], 'SKIP')
        self.assertIn('solo only', solo[1])
        self.assertEqual(results, {'kills of a participant in the circle counted once, an unattributed death ignored, '
                                   'report after the target': ('PASS', None)})
        self.assertEqual((alice.x, alice.y), (10, 10), 'the fixture did not move the player back')
        self.assertFalse(alice.god, 'god mode not restored')
        spawned = list(lua_list(sim.server.g.CLEAR_SPAWNED))
        self.assertEqual([z.dead for z in spawned], [True, True, True])
        # The notebook state never saw a clear mission of the suite.
        self.assertEqual([m for m in sim.state().missions.values() if m.template == 'clear'], [])


class ClearReportTests(ReportCases, unittest.TestCase):
    """E11-T13 : compte rendu au PNJ demandeur d'une mission « nettoyer » (cas communs de ReportCases)."""

    setUp, tearDown, world, clear_sim, catalog = (ClearMissionTests.setUp, ClearMissionTests.tearDown,
                                                  ClearMissionTests.world, ClearMissionTests.clear_sim,
                                                  ClearMissionTests.catalog)

    def active(self, name):
        sim, npc, m, missions = ClearMissionTests.active(self, name)
        return sim, npc, m, missions

    def fulfil(self, sim, m):
        m.target = 1
        ClearMissionTests.kill(self, sim, 'alice')
        self.assertEqual(m.kills, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
