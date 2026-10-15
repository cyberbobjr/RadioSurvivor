"""Réputation interne côté serveur (E04-T07, E04-T08, E04-T09, E04-T12) : RS_Reputation.lua seul (lupa, Lua 5.1,
`next` retiré comme dans Kahlua), puis dans le vrai serveur du carnet (doublures de tests/test_carnet.py, deux
clients).

    python tests/test_reputation.py

Couvre : barème (+5, −5, −50, −10), bornes −100..+100, seuils ±20 (quatre réussites de neutre à bonne, quatre
échecs à mauvaise), plafond de gain de +10 par jour de jeu (surplus noté sans effet), pertes jamais plafonnées, acte
grave non effacé le même jour, tendance sur trois actes, liste fermée d'actions, personnage inconnu ou mort sans
effet, idempotence par eventId (rejeu, rechargement de l'état par RS_Codec, redémarrage du serveur simulé, double
événement de mort), mission de groupe (même montant pour chaque participant, joueur hors ligne compris), sanction du
seul tueur participant (E04-T07), membre de groupe tué par un non-participant (npc.memberKilled), aucune commande
client qui écrit, projection sans chiffre et réservée au personnage, purge (30 jours, personnage mort après 7 jours).
E04 seconde partie : dernier changement de niveau (avertissement Q9), contexte public du LLM (niveau et dernier acte,
E04-T10) relu et borné par le pont, offres simples seulement pour une mauvaise réputation (E04-T05), marge du passeur
par niveau (E04-T11, aussi tests/test_rs_trade.py), réglage de test réservé aux parties rstest en debug (E04-T14), vue
administrateur en lecture seule (Q17), onglet Réputation du carnet (E04-T04) et instantané poussé seulement s'il a
changé (E00-T04).
Doublures : ne prouve ni l'API Java réelle ni l'attribution réelle du tueur (suite en jeu rs.reputation, E04-T14).
"""
from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua'

UNIT_STUBS = r'''
next = nil
isClient = function() return false end
isServer = function() return true end
CLOCK = {hours = 0}
getGameTime = function() return {getWorldAgeHours = function() return CLOCK.hours end} end
getTimestampMs = function() return 0 end
ZombRand = function(a, b) return a end
LOGS = {}
print = function(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, ' ') end
'''


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def py(value):
    """Lua table -> dict (keys as given), recursively."""
    if lupa.lua_type(value) == 'table':
        return {k: py(v) for k, v in value.items()}
    return value


class Unit(unittest.TestCase):
    """RS_Reputation alone, real RS_Config, RS_State and RS_Codec."""

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.rt.execute(UNIT_STUBS)
        roots = ';'.join(f'{(LUA / side).as_posix()}/?.lua' for side in ('server', 'shared'))
        self.rt.execute(f'package.path = [[{roots};]] .. package.path')
        self.R = self.rt.eval("require('RadioSurvivor/RS_Reputation')")
        self.S = self.rt.eval("require('RadioSurvivor/RS_State')")
        self.state = self.rt.eval("{characters = {alice = {id = 'alice'}, bob = {id = 'bob'}, "
                                  "dead = {id = 'dead', retired = true}}, outcomes = {}}")
        self.S.data = self.state
        self.n = 0

    def day(self, day):
        self.g.CLOCK.hours = (day - 1) * 24 + 1

    def rec(self, action, who='alice', event=None):
        self.n += 1
        return self.R.record(self.state, event or f'e{self.n}', who, action, None, None, None)

    def score(self, who='alice'):
        return self.R.scoreOf(who)

    def test_four_successes_lead_from_neutral_to_good_over_two_days(self):
        self.day(1)
        self.assertEqual(self.R.level('alice'), 'neutral')
        self.rec('mission.success'); self.rec('mission.success')
        self.assertEqual((self.score(), self.R.level('alice')), (10, 'neutral'))
        # Third success the same game day: capped, recorded with no effect.
        o = self.rec('mission.success')
        self.assertEqual((o.rep, o.appliedDelta, o.proposedDelta, self.score()), ('capped', 0, 5, 10))
        self.assertTrue(self.R.reasons('alice', 1)[1].capped)
        self.day(2)
        self.rec('mission.success'); self.rec('mission.success')
        self.assertEqual((self.score(), self.R.level('alice'), self.R.trend('alice')), (20, 'good', 'up'))

    def test_four_failures_lead_to_bad_and_losses_are_never_capped(self):
        self.day(1)
        for action in ('mission.failed', 'mission.abandoned', 'trade.cheated', 'mission.failed'):
            self.assertEqual(self.rec(action).rep, 'applied')
        self.assertEqual((self.score(), self.R.level('alice'), self.R.trend('alice')), (-20, 'bad', 'down'))

    def test_bounds(self):
        self.day(1)
        for _ in range(3):
            self.rec('npc.requesterKilled')
        self.assertEqual(self.score(), -100)
        o = self.rec('npc.memberKilled')
        self.assertEqual((o.appliedDelta, o.before, o.after), (0, -100, -100))
        for d in range(2, 45):
            self.day(d); self.rec('mission.success'); self.rec('mission.success')
        self.assertEqual(self.score(), 100)

    def test_serious_act_not_erased_the_same_day(self):
        self.day(3)
        self.rec('npc.requesterKilled')
        self.assertEqual(self.R.level('alice'), 'bad')
        for _ in range(4):
            self.rec('mission.success')
        self.assertEqual((self.score(), self.R.level('alice')), (-40, 'bad'))

    def test_trend_on_the_last_three_acts_and_five_reasons(self):
        self.day(1)
        self.rec('mission.failed'); self.rec('mission.failed')
        self.assertEqual(self.R.trend('alice'), 'down')
        self.rec('mission.success'); self.rec('mission.success')
        self.assertEqual(self.R.trend('alice'), 'up')   # last three: -, +, +
        self.rec('mission.failed')
        self.assertEqual(self.R.trend('alice'), 'up')   # +, +, -
        self.rec('mission.failed')
        self.assertEqual(self.R.trend('alice'), 'down')  # +, -, -
        reasons = [py(r) for r in lua_list(self.R.reasons('alice'))]
        self.assertEqual(len(reasons), 5)
        self.assertEqual(reasons[0]['reasonKey'], 'IGUI_RS_RepReason_MissionFailed')
        self.assertEqual(reasons[0]['sign'], -1)
        self.assertEqual(len(lua_list(self.R.reasons('alice', 2))), 2)

    def test_closed_list_unknown_or_dead_character(self):
        self.day(1)
        self.assertEqual(self.R.record(self.state, 'x1', 'alice', 'chat.insult', -50, None, None), (None, 'action'))
        self.assertIsNone(self.state.outcomes['x1'])
        self.assertEqual(self.rec('mission.success', who='nobody').rep, 'no_character')
        self.assertEqual(self.rec('mission.success', who='dead').rep, 'retired')
        self.assertIsNone(self.R.level('dead'))
        self.assertIsNone(self.R.level('nobody'))
        self.assertTrue(self.state.reputation is None or self.state.reputation['nobody'] is None)
        # Legacy delta argument never changes the amount of the closed list.
        o = self.R.record(self.state, 'x2', 'alice', 'mission.failed', -99, None, None)
        self.assertEqual((o.proposedDelta, o.appliedDelta), (-5, -5))

    def test_event_counted_once_even_after_reload(self):
        self.day(1)
        o = self.rec('mission.success', event='m1-alice-result')
        again, dup = self.R.record(self.state, 'm1-alice-result', 'alice', 'mission.success', 5, None, None)
        self.assertEqual(dup, 'duplicate')
        self.assertTrue(self.rt.eval('rawequal')(again, o))
        self.assertEqual((self.score(), self.state.reputation['alice'].revision), (5, 1))
        # Restart: the private state goes through the real codec of RS_State.save / read.
        codec = self.rt.eval("require('RadioSurvivor/RS_Codec')")
        reloaded = codec.decodeBytes(codec.encodeBytes(self.state))
        self.S.data = reloaded
        _, dup = self.R.record(reloaded, 'm1-alice-result', 'alice', 'mission.success', 5, None, None)
        self.assertEqual(dup, 'duplicate')
        self.assertEqual(self.R.scoreOf('alice', reloaded), 5)
        self.assertEqual(self.R.level('alice', reloaded), 'neutral')

    def test_projection_has_no_number_and_one_character(self):
        self.day(1)
        self.R.record(self.state, 'r1', 'alice', 'npc.requesterKilled', None, {'npc': 'npc-1'},
                      self.rt.table_from(['Real Bandit', 'x' * 80, 'third']))
        p = py(self.R.projection('alice'))
        self.assertEqual((p['available'], p['level'], p['trend']), (True, 'bad', 'down'))
        self.assertNotIn('score', p)
        reason = p['reasons'][1]
        self.assertEqual(set(reason), {'action', 'reasonKey', 'reasonArgs', 'sign', 'day'})
        self.assertEqual((reason['day'], p['today']), (1, 1))
        self.assertEqual(p['change'], {'from': 'neutral', 'to': 'bad', 'day': 1, 'n': 1})
        self.assertEqual(reason['reasonArgs'], {1: 'Real Bandit', 2: 'x' * 48})
        self.assertEqual(py(self.R.projection('bob'))['reasons'], {})
        self.assertFalse(self.R.projection('dead').available)
        self.assertFalse(self.R.projection(None).available)

    def test_last_change_of_level_is_kept(self):
        self.day(1)
        self.assertIsNone(self.R.change('alice'))
        for _ in range(3):
            self.rec('mission.failed')
        self.assertIsNone(self.R.change('alice'), 'no change of level yet')
        self.rec('mission.failed')
        self.assertEqual(py(self.R.change('alice')), {'from': 'neutral', 'to': 'bad', 'day': 1, 'n': 4})
        self.day(2)
        self.rec('mission.success')
        self.assertEqual(py(self.R.change('alice')), {'from': 'bad', 'to': 'neutral', 'day': 2, 'n': 5})
        self.assertIsNone(self.R.change('dead'))

    def test_public_context_level_and_last_act_only(self):
        self.day(1)
        self.assertEqual(py(self.R.publicContext('bob')), {'level': 'neutral'})
        self.R.record(self.state, 'p1', 'alice', 'mission.success', None, {'secret': 'x'},
                      self.rt.table_from(['Real Bandit']))
        ctx = py(self.R.publicContext('alice'))
        self.assertEqual(ctx, {'level': 'neutral', 'last': {'act': 'mission.success', 'about': 'Real Bandit'}})
        self.R.record(self.state, 'p2', 'alice', 'npc.memberKilled', None, None, None)
        self.assertEqual(py(self.R.publicContext('alice'))['last'], {'act': 'npc.memberKilled'})
        self.assertIsNone(self.R.publicContext('dead'))
        self.assertIsNone(self.R.publicContext('nobody'))

    def test_offers_and_margin_by_level(self):
        allowed = self.R.offerAllowed
        for template in ('deliver', 'signal', 'scout', 'clear'):
            self.assertTrue(allowed('bad', template, None), template)
        for template in ('retrieve_id', 'recover'):
            self.assertFalse(allowed('bad', template, None), template)
            self.assertTrue(allowed('neutral', template, None), template)
            self.assertTrue(allowed('good', template, None), template)
            self.assertTrue(allowed(None, template, None), 'a character without notebook identity is neutral')
        supply = self.rt.table_from({'kind': 'supply'})
        self.assertFalse(allowed('bad', 'deliver', supply), 'group supply mission')
        self.assertTrue(allowed('neutral', 'deliver', supply))
        self.assertEqual([self.R.margin(lv) for lv in ('good', 'neutral', 'bad', None)], [0.10, 0.25, 0.40, 0.25])

    def test_test_setter_needs_a_test_save_in_debug_mode(self):
        self.day(1)
        self.assertEqual(self.R.testSetLevel(self.state, 'alice', 'bad'), (False, 'test API unavailable'))
        self.rt.execute('LivingKnox = {API = {testAllowed = function() return TEST_OK, "save is not a test save" end}}')
        self.g.TEST_OK = False
        self.assertEqual(self.R.testSetLevel(self.state, 'alice', 'bad'), (False, 'save is not a test save'))
        self.assertEqual(self.R.level('alice'), 'neutral')
        self.g.TEST_OK = True
        self.assertTrue(self.R.testSetLevel(self.state, 'alice', 'bad'))
        self.assertEqual(self.R.level('alice'), 'bad')
        self.assertEqual(self.R.testSetLevel(self.state, 'alice', 'great'), (False, 'unknown level'))
        self.assertEqual(self.R.testSetLevel(self.state, 'dead', 'good'), (False, 'retired'))
        self.assertTrue(self.R.testSetLevel(self.state, 'alice', 'good'))
        self.assertEqual(self.R.level('alice'), 'good')
        self.assertEqual(len(list(self.state.outcomes.values())), 0, 'the test setter writes no outcome')

    def test_purge_outcomes_and_dead_characters(self):
        self.day(1)
        self.rec('mission.success', event='old')
        self.rec('mission.success', who='bob', event='bob1')
        self.state.outcomes['legacy'] = self.rt.table_from({'id': 'legacy', 'character': 'alice'})
        self.assertTrue(self.R.prune(self.state, 5))
        self.assertEqual(self.state.outcomes['legacy'].day, 5)   # older than E04-T08: purge clock starts now
        self.state.characters['bob'].retired = True
        self.R.retire(self.state, 'bob')
        self.R.prune(self.state, 7)
        self.assertIsNotNone(self.state.reputation['bob'])
        self.R.prune(self.state, 8)  # retired on day 1, purged 7 days later with its outcomes
        self.assertIsNone(self.state.reputation['bob'])
        self.assertIsNone(self.state.outcomes['bob1'])
        self.assertIsNotNone(self.state.outcomes['old'])
        self.R.prune(self.state, 31)
        self.assertIsNone(self.state.outcomes['old'])
        self.assertIsNotNone(self.state.outcomes['legacy'])
        self.assertEqual(self.score(), 5, 'the score survives the purge of its outcomes')
        self.assertFalse(self.R.prune(self.state, 31))


class Server(unittest.TestCase):
    """RS_Reputation inside the notebook server (test_carnet.Simulation, fake provider, two clients)."""

    def setUp(self):
        from test_carnet import Simulation  # noqa: PLC0415 (bridge modules imported on demand)
        self.Simulation = Simulation
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-rep-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, name='rep', clients=('alice', 'bob')):
        sim = self.Simulation(self.path / name)
        for c in clients:
            sim.add_client(c)
        sim.select(clients[0])
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.R = self.rt.eval("require('RadioSurvivor/RS_Reputation')")
        self.M = self.rt.eval("require('RadioSurvivor/RS_Missions')")
        self.npc = next(iter(sim.state().npcs.values()))
        return sim

    def active_mission(self, *names):
        sim = self.sim
        m = self.M.create(sim.state(), self.npc, sim.character(names[0]))
        m.state = 'active'
        for name in names:
            m.participants[sim.character(name)] = self.rt.table_from({'name': name})
        return m

    def kill(self, killer=None, cause='melee'):
        self.sim.zombie.dead = True
        P = self.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        args = self.rt.table_from({'cause': cause, 'killer': killer}) if killer else None
        P.emit('death', 2001, self.sim.zombie, args)

    def rep(self, name):
        return self.R.scoreOf(self.sim.character(name)), self.R.level(self.sim.character(name))

    def test_group_mission_same_amount_offline_participant_and_restart(self):
        sim = self.world('group')
        m = self.active_mission('alice', 'bob')
        bob = sim.character('bob')
        # Bob disconnects before the end: his fact is applied to his character anyway.
        del sim.server.g.PLAYERS['bob']
        sim.clock.offset += 1001; sim.tick()
        self.assertTrue(self.M.finish(sim.state(), m, 'success'))
        sim.server.g.RS_CarnetServer.store.save()
        self.assertEqual(self.rep('alice'), (5, 'neutral'))
        self.assertEqual(self.R.scoreOf(bob), 5)
        alice_o = sim.state().outcomes[m.id + '-' + sim.character('alice') + '-result']
        bob_o = sim.state().outcomes[m.id + '-' + bob + '-result']
        self.assertEqual((alice_o.appliedDelta, bob_o.appliedDelta), (5, 5))
        self.assertEqual(self.R.reasons(bob)[1].reasonArgs[1], 'Real Bandit')
        self.assertFalse(self.M.finish(sim.state(), m, 'success'), 'second finish')
        # Restart of the server: same scores, a replayed fact is a duplicate.
        restart = self.Simulation(sim.path, sim.clock, saved_players=sim.saved())
        R2 = restart.server.rt.eval("require('RadioSurvivor/RS_Reputation')")
        self.assertEqual((R2.scoreOf(sim.character('alice')), R2.scoreOf(bob)), (5, 5))
        state = restart.state()
        _, dup = R2.record(state, m.id + '-' + bob + '-result', bob, 'mission.success', 5, None, None)
        self.assertEqual(dup, 'duplicate')
        self.assertEqual(R2.scoreOf(bob), 5)

    def test_requester_killer_alone_once_team_mates_spared(self):
        sim = self.world('killer')
        m = self.active_mission('alice', 'bob')
        self.kill('alice')
        self.assertEqual(m.state, 'cancelled_dead')
        self.assertEqual(self.rep('alice'), (-50, 'bad'))
        self.assertEqual(self.rep('bob'), (0, 'neutral'), 'team mate punished')
        o = sim.state().outcomes[self.npc.id + '-killed-' + sim.character('alice')]
        self.assertEqual((o.action, o.appliedDelta, o.proof.mission), ('npc.requesterKilled', -50, m.id))
        self.assertEqual(self.npc.deathAttribution, 'player')
        # Double death event (second OnZombieDead, replay): no second sanction, and the Living Knox fact of the
        # same death does not add npc.memberKilled.
        self.kill('alice')
        sim.server.g.RS_CarnetServer.npcDied(self.rt.table_from(
            {'npc': 2001, 'generation': 1, 'group': 'g1', 'killer': 'alice', 'cause': 'melee'}))
        self.assertEqual(self.rep('alice'), (-50, 'bad'))
        self.assertEqual(len([o for o in sim.state().outcomes.values() if o.character == sim.character('alice')]), 1)

    def test_non_participant_killer_is_a_member_kill(self):
        sim = self.world('member', clients=('alice', 'bob', 'carol'))
        self.active_mission('alice', 'bob')
        self.kill('carol')
        self.assertEqual(self.rep('carol'), (0, 'neutral'), 'requester rule applied to a non-participant')
        info = self.rt.table_from({'npc': 2001, 'generation': 1, 'group': 'g1', 'killer': 'carol', 'cause': 'melee'})
        server = sim.server.g.RS_CarnetServer
        server.npcDied(info)
        server.npcDied(info)
        self.assertEqual(self.rep('carol'), (-10, 'neutral'))
        self.assertEqual((self.rep('alice'), self.rep('bob')), ((0, 'neutral'), (0, 'neutral')))
        # Not a group member, or no attributed killer: nothing.
        server.npcDied(self.rt.table_from({'npc': 2001, 'generation': 2, 'killer': 'carol'}))
        server.npcDied(self.rt.table_from({'npc': 2001, 'generation': 3, 'group': 'g1'}))
        server.npcDied(self.rt.table_from({'npc': 2001, 'generation': 4, 'group': 'g1', 'killer': 'mallory'}))
        self.assertEqual(self.rep('carol'), (-10, 'neutral'))

    def test_unattributed_death_no_sanction(self):
        sim = self.world('fire')
        self.active_mission('alice')
        self.kill(None)
        self.assertEqual(self.rep('alice'), (0, 'neutral'))
        self.assertEqual(self.npc.deathAttribution, 'unavailable_server_evidence')
        self.assertEqual(len(list(sim.state().outcomes.values())), 0)

    def test_no_client_can_write_and_projection_is_private(self):
        sim = self.world('clients')
        self.active_mission('alice')
        m = next(iter(sim.state().missions.values()))
        self.M.finish(sim.state(), m, 'failed')
        before = py(sim.state().reputation)
        outcomes = len(list(sim.state().outcomes.values()))
        for command in ('reputation', 'record', 'rep_record', 'set_reputation'):
            sim.command('bob', command, character=sim.character('bob'), action='mission.success', delta=100,
                        reasonKey='IGUI_RS_RepReason_MissionSuccess', eventId='forged')
        self.assertEqual(py(sim.state().reputation), before)
        self.assertEqual(len(list(sim.state().outcomes.values())), outcomes)
        sim.command('alice', 'snapshot'); sim.command('bob', 'snapshot')
        a = py(sim.clients['alice'].g.RS_CarnetClient.snapshot.reputation)
        b = py(sim.clients['bob'].g.RS_CarnetClient.snapshot.reputation)
        self.assertEqual((a['available'], a['level'], a['trend']), (True, 'neutral', 'down'))
        self.assertEqual(a['reasons'][1]['reasonKey'], 'IGUI_RS_RepReason_MissionFailed')
        self.assertNotIn('score', a)
        self.assertEqual((b['available'], b['level'], b['trend']), (True, 'neutral', 'stable'))
        self.assertIn(b.get('reasons'), (None, {}), 'reasons of another character leaked')

    def test_living_knox_fact_npc_died_reaches_the_reputation(self):
        """Real Living Knox engine and provider: the keyed listener is linked by the notebook tick; the fact npcDied
        of a group member killed by alice costs her npc.memberKilled once (LK_Relations.playerByName then
        LK_Hostility.keyOf)."""
        from test_carnet import LK_WORLD  # noqa: PLC0415
        sim = self.Simulation(self.path / 'lk', living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        sim.clock.offset += 1001; sim.tick()
        rt = sim.server.rt
        self.assertTrue(sim.server.g.RS_CarnetServer.reputationLinked)
        info = rt.table_from({'npc': 'lk-npc-9', 'generation': 1, 'group': sim.server.g.LK_GROUP, 'killer': 'alice',
                              'cause': 'melee'})
        publish = rt.eval('LivingKnox.publish')
        publish('npcDied', info)
        publish('npcDied', info)
        R = rt.eval("require('RadioSurvivor/RS_Reputation')")
        alice = sim.character('alice')
        self.assertEqual((R.scoreOf(alice), R.level(alice), R.trend(alice)), (-10, 'neutral', 'down'))
        self.assertEqual(R.reasons(alice)[1].reasonKey, 'IGUI_RS_RepReason_MemberKilled')


class Effects(unittest.TestCase):
    """E04 second part inside the notebook server (offers, LLM context, snapshots, admin view, notebook tab)."""
    setUp, tearDown, world, rep = Server.setUp, Server.tearDown, Server.world, Server.rep

    def bad(self, name):
        sim = self.sim
        for i in range(4):
            self.R.record(sim.state(), f'bad-{name}-{i}', sim.character(name), 'mission.failed', None, None,
                          self.rt.table_from(['Real Bandit']))
        self.assertEqual(self.R.level(sim.character(name)), 'bad')

    def test_bad_reputation_keeps_simple_offers_only(self):
        sim = self.world('offers')
        self.rt.execute("""
            local M = require 'RadioSurvivor/RS_Missions'
            local function fake(kind)
                return {idPrefix = 'f', offer = function() return {kind = kind} end, create = function() end}
            end
            M.register('recover', fake('recover')); M.register('signal', fake('signal'))
            FAKE_RECORD = {hostile = false}
        """)
        npc = self.rt.table_from({'id': 'npc-x'})

        def catalog(name):
            c = self.M.offers(npc, self.g.FAKE_RECORD, None, sim.character(name))
            return set(c.keys())

        recover = self.g.require('RadioSurvivor/RS_Config').Missions.recover.id
        signal = self.g.require('RadioSurvivor/RS_Config').Missions.signal.id
        self.assertTrue({recover, signal} <= catalog('alice'))
        self.bad('alice')
        offers = catalog('alice')
        self.assertIn(signal, offers, 'a bad reputation still gets a simple mission')
        self.assertNotIn(recover, offers)
        self.assertIn(recover, catalog('bob'), 'neutral keeps the sensitive missions')

    def test_npc_talk_carries_level_and_last_public_act(self):
        from test_carnet import convert, talk_requests  # noqa: PLC0415
        import npc_protocol as protocol  # noqa: PLC0415
        sim = self.world('context')
        self.bad('alice')
        sim.command('alice', 'talk', channel='say', text='Hello', language='EN')
        req = convert(talk_requests(sim.server.g)[0])
        self.assertEqual(req['context']['reputation'],
                         {'level': 'bad', 'last': {'act': 'mission.failed', 'about': 'Real Bandit'}})
        self.assertNotIn('score', str(req['context']['reputation']))
        cleaned = protocol.reputation_context(req['context']['reputation'])
        self.assertEqual(cleaned, req['context']['reputation'])
        req['context']['reputation'] = cleaned
        system = protocol.prompt(req, [])[0]['content']
        self.assertIn('Reputation of this character among the survivors of the area, as you heard it: bad', system)
        self.assertIn('failed a mission for Real Bandit', system)
        self.assertIn('never claim that anything you say changes it', system)
        # Old servers sent a word: the bridge drops it; a malformed act is dropped, the level kept.
        self.assertIsNone(protocol.reputation_context('unavailable'))
        self.assertEqual(protocol.reputation_context({'level': 'good', 'last': {'act': 'praise', 'about': 'x'}}),
                         {'level': 'good'})
        self.assertIsNone(protocol.reputation_context({'level': 'excellent'}))

    def test_pushed_snapshot_only_when_changed(self):
        sim = self.world('push')
        received = []
        client = sim.clients['alice'].g.RS_CarnetClient
        base = client.receive

        def counting(command, args):
            if command == 'snapshot':
                received.append(args)
            return base(command, args)
        client.receive = counting
        server = sim.server.g.RS_CarnetServer
        sim.command('alice', 'snapshot')
        self.assertEqual(len(received), 1, 'an answer to a request is always sent')
        server.publish(); server.publish()
        self.assertEqual(len(received), 1, 'an unchanged snapshot was pushed again')
        self.bad('alice')
        server.publish()
        self.assertEqual(len(received), 2, 'a changed snapshot must be pushed')
        self.assertEqual(received[-1].reputation.level, 'bad')
        sim.command('alice', 'snapshot')
        self.assertEqual(len(received), 3)

    def test_admin_view_read_only_and_checked_on_the_server(self):
        sim = self.world('admin')
        answers = []
        client = sim.clients['bob'].g.RS_CarnetClient
        base = client.receive

        def capture(command, args):
            if command == 'rep_admin':
                answers.append(py(args))
            return base(command, args)
        client.receive = capture
        self.bad('alice')
        self.rt.execute('RS_FreqDebug = {isAllowed = function(p) return ADMIN_OK == true, "missing capability" end}')
        sim.command('bob', 'rep_admin')
        self.assertEqual({k: answers[-1][k] for k in ('ok', 'err')}, {'ok': False, 'err': 'denied'})
        self.assertNotIn('characters', answers[-1])
        self.g.ADMIN_OK = True
        before = py(sim.state().reputation)
        sim.command('bob', 'rep_admin')
        view = answers[-1]
        self.assertTrue(view['ok'])
        names = {c['name']: c for c in view['characters'].values()}
        self.assertEqual(names['alice Doe']['level'], 'bad')
        self.assertNotIn('score', str(view))
        self.assertEqual(py(sim.state().reputation), before, 'the admin view wrote something')

    def test_notebook_tab_and_warning_on_level_change(self):
        from test_carnet import NOTEBOOK_UI  # noqa: PLC0415
        sim = self.world('tab')
        c = sim.clients['alice']
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end\n"
                     "getText = function(k, ...) local t = { k } for i = 1, select('#', ...) do "
                     "t[#t + 1] = tostring(select(i, ...)) end return table.concat(t, '|') end\n"
                     "getTextOrNull = getText\n"
                     "HALOS = {}\n"
                     "HaloTextHelper.addGoodText = function(p, t) HALOS[#HALOS + 1] = 'good:' .. t end\n"
                     "HaloTextHelper.addBadText = function(p, t) HALOS[#HALOS + 1] = 'bad:' .. t end")
        c.load('client/RS_Carnet_Client.lua')
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        sim.command('alice', 'snapshot')
        window.changeTab(window, 'Reputation')
        text = window.detail.text
        self.assertIn('IGUI_RS_RepLevelLine|IGUI_RS_RepLevel_neutral <LINE> <LINE> IGUI_RS_RepTrendLine|IGUI_RS_RepTrend_stable', text)
        self.assertIn('IGUI_RS_RepNoActs', text)
        self.assertIn('IGUI_RS_PersonalTrustSeparate', text)
        for gone in ('NotApplied', 'Event_', 'ReputationUnavailable'):
            self.assertNotIn(gone, text)
        self.assertEqual(len(list(c.g.HALOS.values())), 0, 'no warning without a change')
        self.bad('alice')
        sim.server.g.RS_CarnetServer.publish()
        text = window.detail.text
        self.assertIn('IGUI_RS_RepLevelLine|IGUI_RS_RepLevel_bad <LINE> <LINE> IGUI_RS_RepTrendLine|IGUI_RS_RepTrend_down', text)
        self.assertIn('IGUI_RS_RepChanged|IGUI_RS_RelWhen_today|IGUI_RS_RepLevel_neutral|IGUI_RS_RepLevel_bad', text)
        self.assertIn('- IGUI_RS_RepAct|IGUI_RS_RelWhen_today|IGUI_RS_RepReason_MissionFailed|Real Bandit', text)
        self.assertIsNone(re.search(r'\d', re.sub(r'<[^>]*>', '', text)), 'a number is shown: ' + text)
        self.assertEqual(lua_list(c.g.HALOS), ['bad:IGUI_RS_RepWarn|IGUI_RS_RepLevel_bad'])
        # Same change seen again (poll): no second warning.
        sim.command('alice', 'snapshot')
        self.assertEqual(len(lua_list(c.g.HALOS)), 1)
        # A reconnection only sets the reference: no warning for a change made before it.
        c.g.RS_CarnetClient.repChangeSeen = None
        sim.command('alice', 'snapshot')
        self.assertEqual(len(lua_list(c.g.HALOS)), 1)


class VoiceField(unittest.TestCase):
    """E04-T10: field reputation= of a radio voice request, read by the bridge (radio_bridge.reputation_field) and put
    in the prompt of the voice; malformed or absent field: no section (prompt unchanged)."""

    def test_reputation_field_of_a_voice_request(self):
        sys.path.insert(0, str(ROOT / 'bridge'))
        import npc_protocol as npc  # noqa: PLC0415
        import radio_bridge as rb  # noqa: PLC0415
        raw = npc.encode({'level': 'good', 'last': {'act': 'rescue.success'}}).hex()
        value = rb.reputation_field({'id': 'r1', 'reputation': raw})
        self.assertEqual(value, {'level': 'good', 'last': {'act': 'rescue.success'}})
        text = rb.reputation_prompt(value, 'Caller 1')
        self.assertTrue(text.startswith('\nReputation of Caller 1 among the survivors'), text)
        self.assertIn('rescued a survivor', text)
        self.assertIsNone(rb.reputation_field({'id': 'r2'}))
        self.assertIsNone(rb.reputation_field({'id': 'r3', 'reputation': 'zz'}))
        self.assertIsNone(rb.reputation_field({'id': 'r4', 'reputation': npc.encode({'score': 40}).hex()}))
        self.assertEqual(rb.reputation_prompt(None, 'Caller 1'), '')


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    unittest.main(verbosity=1)
