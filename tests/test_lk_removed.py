"""A game played with RadioSurvivor and Living Knox, then reopened without Living Knox (golden rule of 2026-11-06).

    python RadioSurvivor/tests/test_lk_removed.py

Real notebook server and client (RS_Carnet_Server, RS_Client), real Living Knox engine in the first session (registries,
API, LK_PersonalRelation, provider RS_LivingKnox.lua), same save folder for every session. Second session: Living Knox
is not on the module path (as when the player unticks it): the notebook must start, keep its character, show its
contacts (the fiche of a Living Knox NPC stays, without relation level), refuse to talk to an NPC that no longer
exists, and run its ticks and daily purge without a Lua error. E18-T25: the mission of a Living Knox NPC is hidden
(snapshot and core list), frozen and never failed while Living Knox is unticked, and listed again as it was after. Third session: Living Knox ticked again, its relation
is still there (its own file was never touched). Doubles only: proves neither the Java API nor the network.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_carnet import Simulation, LK_WORLD, convert  # noqa: E402
from test_protocol import Game, start_bridge, pump  # noqa: E402


class LivingKnoxRemovedTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-lk-removed-')
        self.path = Path(self.tmp.name) / 'game'
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        Game.WITH_LK = True
        self.tmp.cleanup()

    def errors(self, sim):
        lines = []
        for machine in [sim.server] + list(sim.clients.values()):
            logs = machine.g.LOGS
            lines += [logs[i] for i in range(1, len(logs) + 1) if 'ERROR' in str(logs[i]) or 'rror' in str(logs[i])]
        return lines

    def played_with_both(self):
        sim = Simulation(self.path, living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        g, rt = sim.server.g, sim.server.rt
        leader = g.LK_LEADER
        g.LivingKnox.Bodies.bound[leader].x = 12
        sim.command('alice', 'select', incarnation=leader)
        sim.acquaint('alice')
        fiche = g.RS_CarnetServer.ensure(leader)
        cid = sim.character('alice')
        self.assertIsNotNone(rt.eval('LivingKnox.Hostility').record(g.LK_GROUP, cid, 'gift',
                                                                   rt.table_from({'witnessed': True})))
        R = rt.eval("require('RadioSurvivor/RS_Relations')")
        _, binding = R.offer(fiche, cid)
        view, _ = R.apply(fiche, cid, binding, 'up', 'f1')
        self.assertIsNotNone(view)
        level = view.level
        # A mission of this NPC in progress (supply offer drawn from the real food need, accepted, one delivery).
        self.process = start_bridge(sim.path)
        sim.say('alice', '/say Bonjour, avez-vous besoin de quelque chose ?')
        self.assertTrue(pump(lambda: len(list(sim.state().missions.keys())) == 1, [sim.tick]), 'no mission offer')
        sim.request_mission('alice', 'accept')
        m = sim.mission()
        self.assertEqual(m.state, 'active')
        sim.confirm('alice', sim.quote('alice', sim.items('alice', *(['Base.TinnedBeans'] * 5))))
        self.assertEqual(m.delivered, 10)
        self.process.terminate()
        self.process.communicate(timeout=10)
        self.process = None
        self.mission_id = m.id
        sim.command('alice', 'snapshot')
        rt.execute("require('RadioSurvivor/RS_State').dirty = true require('RadioSurvivor/RS_State').save() "
                   "LivingKnox.Store.flush() LivingKnox.Groups.flush() LivingKnox.Hostility.save()")
        return sim, leader, fiche.id, cid, level

    def test_living_knox_removed_then_added_back(self):
        first, leader, fiche_id, cid, level = self.played_with_both()
        self.assertEqual(self.errors(first), [])
        # Second session: Living Knox unticked (not on the module path), same save.
        first.clock.stop(600000)
        Game.WITH_LK = False
        try:
            alone = Simulation(self.path, first.clock, saved_players=first.saved(), provider=False)
            alone.add_client('alice')
        finally:
            Game.WITH_LK = True
        srv = alone.server
        self.assertEqual(srv.rt.eval('(function() local n = 0 for k in pairs(package.loaded) do '
                                     'if string.find(k, "LivingKnox") then n = n + 1 end end return n end)()'), 0)
        self.assertIsNone(srv.g.LivingKnox)
        self.assertEqual(alone.character('alice'), cid, 'same character after Living Knox was removed')
        # Notebook: the contact stays, without relation level, and the panel builds without error.
        alone.command('alice', 'snapshot')
        contacts = alone.clients['alice'].g.RS_CarnetClient.snapshot.contacts
        [row] = [c for c in contacts.values() if c.id == fiche_id]
        rel = convert(row.relation) or {}
        self.assertIsNone(rel.get('level'))
        self.assertIsNone(srv.rt.eval("require('RadioSurvivor/RS_Relations')").view(
            alone.state().npcs[fiche_id], cid))
        # Talking to the NPC that no longer exists: refused cleanly, nothing sent to the bridge.
        alone.command('alice', 'select', incarnation=leader)
        alone.command('alice', 'talk', channel='say', text='Tu es encore la ?', language='FR')
        for _ in range(30):
            alone.tick()
        srv.g.fire('EveryHours')
        srv.g.fire('EveryDays')
        alone.say('alice', 'Bonjour')
        # E18-T25: the mission of a Living Knox NPC is hidden while Living Knox is unticked, never failed nor erased:
        # no row in the notebook nor in the core list, its delay frozen, delivery and abandon refused without effect.
        m = alone.state().missions[self.mission_id]
        self.assertIsNotNone(m)
        remaining, revision = m.remainingMs, m.revision
        alone.command('alice', 'snapshot')
        self.assertFalse(any(v.id == self.mission_id for v in
                             alone.clients['alice'].g.RS_CarnetClient.snapshot.missions.values()))
        journal = srv.rt.eval("require('RadioSurvivorCore/RC_MissionJournal')")
        self.assertEqual(len(list(journal.rows(cid).values())), 0)
        quote = alone.quote('alice', alone.items('alice', *(['Base.TinnedBeans'] * 5)))
        if quote:
            alone.confirm('alice', quote)
        self.assertEqual(m.delivered, 10, 'delivery to a group that no longer exists')
        self.refused = alone.clients['alice'].g.RS_CarnetClient.lastError
        alone.request_mission('alice', 'abandon')
        for _ in range(30):
            alone.tick()
        srv.g.fire('EveryDays')
        self.assertEqual((m.state, m.remainingMs, m.revision), ('active', remaining, revision),
                         'mission failed, abandoned or timed while Living Knox was unticked')
        self.assertEqual(self.errors(alone), [])
        srv.rt.execute("require('RadioSurvivor/RS_State').dirty = true require('RadioSurvivor/RS_State').save()")
        # Third session: Living Knox ticked again, its relation is still there.
        alone.clock.stop(600000)
        back = Simulation(self.path, alone.clock, saved_players=alone.saved(), living_knox=True)
        back.add_client('alice')
        fiche = back.state().npcs[fiche_id]
        self.assertIsNotNone(fiche)
        view = back.server.rt.eval("require('RadioSurvivor/RS_Relations')").view(fiche, cid)
        self.assertEqual(view.level, level, 'relation kept by Living Knox while it was removed')
        # E18-T25: the mission is listed again as it was.
        back.command('alice', 'snapshot')
        rows = [v for v in back.clients['alice'].g.RS_CarnetClient.snapshot.missions.values() if v.id == self.mission_id]
        self.assertEqual(len(rows), 1, 'mission of the Living Knox NPC found again')
        self.assertEqual((rows[0].state, rows[0].delivered), ('active', 10))
        self.assertEqual(self.errors(back), [])


if __name__ == '__main__':
    unittest.main()
