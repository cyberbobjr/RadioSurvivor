"""Accords de faction avec un groupe Living Knox : trêve et alliance (E09-T05).

    python tests/test_agreements.py

Deux bancs lupa (Lua 5.1, `next` retiré comme dans Kahlua) :
- `AgreementCarnetTests` : vrai serveur du carnet (`RS_Carnet_Server.lua`), vrais `RS_Factions.lua`, moteur Living Knox
  réel (registres, `LK_Hostility`, `LK_Decisions`) et vrai pont hors ligne (`RS_OFFLINE_INTENT=negotiate[:<kind>]`,
  drapeau du banc qui tient lieu d'un modèle d'accord, jamais tiré des mots du joueur) ; doublure fidèle de la faction
  vanilla de `tests/test_factions.py`. Le passage de décision d'un membre est rejoué par son état
  (`Decisions.state.members`) et `Decisions.markEvaluated` : la cascade complète est prouvée par le second banc.
- `AgreementDecisionTests` : pile complète de `LK_Decisions` et `LK_Combat` (banc `DecisionCombatTests` de
  `tests/test_lk_combat.py`) : un combattant engagé contre un joueur cesse à son passage de décision suivant quand le
  crochet `covered` le couvre, et `Decisions.aims` le constate.
Doublures seulement : ne prouve ni l'API Java ni le réseau.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, LK_WORLD, convert, count, talk_requests, protocol
from test_factions import FACTION_DOUBLE
from test_protocol import start_bridge, pump, lua_list
import test_lk_combat


class AgreementCarnetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-agreements-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, name, intent='negotiate', clients=('alice', 'bob', 'carol')):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(FACTION_DOUBLE)
        sim.server.rt.execute(LK_WORLD)
        for c in clients:
            sim.add_client(c)
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.F = self.rt.eval("require('RadioSurvivor/RS_Factions')")
        self.H = self.rt.eval('LivingKnox.Hostility')
        self.D = self.rt.eval('LivingKnox.Decisions')
        for npc in (self.g.LK_LEADER, self.g.LK_MATE):
            self.g.LivingKnox.Bodies.bound[npc].x = 12
        # Faction "North": alice owner, bob and carol members.
        self.rt.execute('NORTH = FACTION_CREATE("North", "alice", {"bob", "carol"})')
        self.poll()
        self.process = start_bridge(sim.path, intent)
        return sim

    def poll(self):
        """One notebook check (1 s) after the faction poll delay (2 s): factions read again, applications polled."""
        self.sim.clock.offset += 2100
        self.sim.tick()

    def cid(self, name):
        return self.sim.character(name)

    def team(self):
        return self.F.idOf(self.g.PLAYERS['alice'])

    def agreement(self):
        a = self.F.agreementOf(self.g.LK_GROUP, self.team())
        return convert(a) if a else None

    def say(self, name, npc, text, before_reply=None):
        """One sentence of name to this NPC (selected, acquainted); returns the request once handled."""
        sim = self.sim
        self.request(name, npc, text)
        [req] = [r for r in talk_requests(self.g) if r.character == self.cid(name)]
        rid = req.id
        if before_reply:
            before_reply()
        self.assertTrue(pump(lambda: not any(r.id == rid for r in self.server.pending.values()), [sim.tick]),
                        'no reply: ' + text)
        return convert(req)

    def request(self, name, npc, text):
        sim = self.sim
        sim.command(name, 'select', incarnation=npc)
        sim.acquaint(name)
        self.server.lastTalk[self.cid(name)] = None
        sim.command(name, 'talk', channel='say', text=text, language='FR')

    def halos(self, name):
        return [h for h in lua_list(self.sim.clients[name].g.PLAYERS[name].halos) if 'Agreement' in h]

    def logs(self):
        return [self.g.LOGS[i] for i in range(1, len(self.g.LOGS) + 1)]

    def spoken(self, name):
        """Lines of the leader said to the character of name (contact history, filled only for an accepted reply)."""
        fiche = self.server.ensure(self.g.LK_LEADER)
        known = self.sim.state().characters[self.cid(name)].contacts[fiche.id]
        return [h.text for h in lua_list(known.history) if h.author == fiche.name] if known else []

    def kept(self, name, reason, before):
        """E09-T09: the agreement proposed by the model was refused by the server: the line of the leader is said
        (history of name grows by one, no NoAnswer), only the agreement is ignored and logged with its reason."""
        fiche = self.server.ensure(self.g.LK_LEADER)
        prefix = f'agreement of {fiche.id} toward {self.cid(name)} in '
        self.assertTrue(any(prefix in x and x.endswith('ignored, reply kept: ' + reason) for x in self.logs()),
                        self.logs())
        self.assertIsNone(self.sim.clients[name].g.RS_CarnetClient.lastError, 'the player sees NoAnswer')
        self.assertEqual(len(self.spoken(name)), before + 1, 'reply of the leader not said')

    def fighting(self, npc, account):
        """State of the member left by a decision of the cascade: fight against this player (key "p<account>")."""
        self.rt.execute(f'LivingKnox.Decisions.state.members["{npc}"] = {{ b = "fight", p = 1, rule = "threat", '
                        f'key = "p{account}", why = "attack player {account}", start = 0, untilMin = 999999 }}')
        self.D.markEvaluated(npc)

    def decided(self, npc, behaviour='home', key='routine'):
        """Next decision of the member: the cascade (covered player, no target) chose another behaviour."""
        self.rt.execute(f'LivingKnox.Decisions.state.members["{npc}"] = {{ b = "{behaviour}", p = 8, '
                        f'rule = "routine", key = "{key}", why = "routine", start = 0, untilMin = 999999 }}')
        self.D.markEvaluated(npc)

    def target(self, npc, name):
        res = self.H.chooseTarget(self.g.LK_GROUP, npc, self.rt.table_from(
            [self.rt.table_from({'u': name, 'key': self.cid(name), 'd': 2})]))
        t = res.target
        return (t.action, t.reason) if t else None

    def test_truce_during_combat_applied_before_announcement(self):
        sim = self.world('combat')
        gid, mate = self.g.LK_GROUP, self.g.LK_MATE
        # bob hit a member: the group defends itself against him (provocation), a fighter is engaged.
        self.H.record(gid, self.cid('bob'), 'hit', self.rt.table_from({'attributable': True}))
        self.assertTrue(self.H.provoked(gid, self.cid('bob')))
        attitude = convert(self.H.debugPair(gid, self.cid('bob')))
        self.assertEqual(self.target(mate, 'bob'), ('attack', 'provoked'))
        self.fighting(mate, 'bob')
        # alice, owner of North, talks to the leader: fixed terms offered by the server, bound to her team.
        req = self.say('alice', self.g.LK_LEADER, 'Faisons une trêve entre nos deux groupes.')
        neg = req['context']['negotiation']
        self.assertEqual((neg['role'], neg['teamName'], neg['personal'], neg['current']), ('owner', 'North', False, 'none'))
        self.assertEqual(sorted(neg['terms']), ['alliance', 'truce'])
        self.assertEqual(neg['terms']['truce'], {'kind': 'truce', 'scope': {'group': 'all_members',
                                                                            'team': 'current_members'}})
        self.assertNotIn('team', neg, 'team id sent to the bridge')
        system = protocol.prompt(req, [])[0]['content']
        self.assertIn('Agreement offer', system)
        self.assertIn('never say it is already in force', system)
        a = self.agreement()
        self.assertEqual((a['kind'], a['state'], a['revision'], a['group'], a['team']),
                         ('truce', 'pending', 1, gid, self.team()))
        self.assertEqual((a['signed']['account'], a['signed']['role'], a['signed']['character']),
                         ('alice', 'owner', self.cid('alice')))
        # Inscribed in the registry consulted by the target choice: bob is covered at once (never a target).
        self.assertTrue(self.F.covered(gid, self.cid('bob')))
        self.assertTrue(self.rt.eval("rawequal(LivingKnox.Hooks.covered, require('RadioSurvivor/RS_Factions').covered)"))
        self.assertIsNone(self.target(mate, 'bob'))
        # ... but nothing is announced while a member still fights bob or has not decided again.
        for _ in range(3):
            self.poll()
        self.assertEqual(self.agreement()['state'], 'pending')
        self.D.markEvaluated(mate)  # decided again but still aiming at bob (e.g. an engagement of the API)
        self.poll()
        self.assertEqual(self.agreement()['state'], 'pending')
        for name in ('alice', 'bob', 'carol'):
            self.assertEqual(self.halos(name), [], name)
        # Next decision: the cascade dropped bob (covered). Application confirmed, then announced to the team.
        self.decided(mate)
        self.poll()
        a = self.agreement()
        self.assertEqual(a['state'], 'applicable')
        name = self.server.ensure(self.g.LK_LEADER).groupName
        self.assertTrue(name)
        for player in ('alice', 'bob', 'carol'):
            self.assertEqual(self.halos(player), [f'IGUI_RS_Agreement_truce|{name}'], player)
        self.poll()
        self.assertEqual(self.halos('alice'), [f'IGUI_RS_Agreement_truce|{name}'], 'announced twice')
        # A truce never changes the attitude (ADR B08): same pair, still provoked without the hook.
        self.assertEqual(convert(self.H.debugPair(gid, self.cid('bob'))), attitude)
        self.assertTrue(self.H.provoked(gid, self.cid('bob')))
        self.assertTrue(any('agreement agr-1 (truce) between ' + gid in line and 'applicable' in line
                            for line in self.logs()))
        # Private state only: saved in the notebook state, never in a global ModData.
        saved = self.server.store.data.factions.agreements[gid + '|' + self.team()]
        self.assertEqual(saved.state, 'applicable')
        self.assertEqual(count(self.sim.state().npcs[self.server.find(self.g.LK_LEADER).id].agreements), 0)

    def test_member_without_mandate_or_ordinary_npc_do_not_conclude(self):
        self.world('mandate')
        gid = self.g.LK_GROUP
        # bob, member without a mandate: no offer, the bench model cannot negotiate, nothing concluded.
        req = self.say('bob', self.g.LK_LEADER, 'Je parle pour tout le monde : trêve !')
        self.assertNotIn('negotiation', req['context'])
        self.assertNotIn('Agreement offer', protocol.prompt(req, [])[0]['content'])
        self.assertIsNone(self.agreement())
        with self.assertRaisesRegex(ValueError, 'inadmissible agreement'):
            protocol.bounded_reply(req, {'text': 'Ok.', 'intent': 'negotiate', 'offer': 'truce'})
        # alice, owner, talking to an ordinary member: no offer either (the leader decides for the group).
        req = self.say('alice', self.g.LK_MATE, 'Faisons une trêve.')
        self.assertNotIn('negotiation', req['context'])
        self.assertEqual(req['context']['collective']['speaker'], 'member')
        self.assertIsNone(self.agreement())
        # bob designated, then the mandate withdrawn while the model answers: refused at the conclusion.
        self.sim.command('alice', 'mandate', action='grant', member='bob')
        before = len(self.spoken('bob'))
        req = self.say('bob', self.g.LK_LEADER, 'Trêve ?',
                       lambda: self.sim.command('alice', 'mandate', action='revoke', member='bob'))
        self.assertEqual(req['context']['negotiation']['role'], 'negotiator')
        self.assertIsNone(self.agreement())
        # E09-T09: the reply of the leader is kept and said, without the agreement.
        self.kept('bob', 'no mandate', before)
        # A succession between the request and the reply: the former leader no longer concludes.
        mate = self.G().findNpc(self.g.LK_MATE)[1]
        before = len(self.spoken('alice'))
        self.say('alice', self.g.LK_LEADER, 'Trêve ?',
                 lambda: self.rt.execute(f'assert(LivingKnox.Groups.setLeader("{gid}", "{mate}"))'))
        self.assertIsNone(self.agreement())
        self.kept('alice', 'NPC no longer the group leader', before)
        # A negotiator still designated concludes for the faction.
        leader = self.G().findNpc(self.g.LK_LEADER)[1]
        self.rt.execute(f'assert(LivingKnox.Groups.setLeader("{gid}", "{leader}"))')
        self.sim.command('alice', 'mandate', action='grant', member='bob')
        self.say('bob', self.g.LK_LEADER, 'Trêve ?')
        a = self.agreement()
        self.assertEqual((a['kind'], a['signed']['account'], a['signed']['role']), ('truce', 'bob', 'negotiator'))

    def G(self):
        return self.rt.eval('LivingKnox.Groups')

    def test_two_incompatible_conclusions_only_one_applied(self):
        self.world('race', 'negotiate:alliance')
        self.sim.command('alice', 'mandate', action='grant', member='bob')
        # Both requests are built on revision 0 before any reply (the bridge answers one NPC turn at a time).
        self.request('alice', self.g.LK_LEADER, 'Alliance ?')
        self.request('bob', self.g.LK_LEADER, 'Alliance ?')
        reqs = talk_requests(self.g)
        self.assertEqual(len(reqs), 2)
        self.assertEqual([r.context.negotiation.current for r in reqs], ['none', 'none'])
        self.assertTrue(pump(lambda: count(self.server.pending) == 0, [self.sim.tick]), 'no replies')
        a = self.agreement()
        self.assertEqual((a['kind'], a['revision'], a['signed']['account']), ('alliance', 1, 'alice'))
        # E09-T09: bob hears the leader's line to him (after the one to alice, heard too); only his agreement is
        # ignored.
        self.kept('bob', 'agreement revision changed', 1)
        # The next offer starts from the alliance: nothing above it is offered any more.
        self.assertEqual(self.F.negotiation(self.g.PLAYERS['alice'], self.g.LK_GROUP), (None, 'nothing_to_offer'))

    def test_scope_follows_the_current_members_of_the_faction(self):
        self.world('scope', clients=('alice', 'bob', 'carol', 'dave'))
        gid = self.g.LK_GROUP
        self.say('alice', self.g.LK_LEADER, 'Trêve ?')
        team = self.team()
        self.assertTrue(self.F.covered(gid, self.cid('carol')))
        self.assertFalse(self.F.covered(gid, self.cid('dave')), 'player outside the faction covered')
        self.assertFalse(self.F.covered('grp-2', self.cid('carol')), 'another group bound')
        # carol leaves, dave joins, the faction is renamed: read again by the poll, same team id.
        self.rt.execute('FACTION_REMOVE(NORTH, "carol"); NORTH:addPlayer("dave"); FACTION_RENAME(NORTH, "Nord")')
        self.poll()
        self.assertEqual(self.team(), team)
        self.assertFalse(self.F.covered(gid, self.cid('carol')))
        self.assertTrue(self.F.covered(gid, self.cid('dave')))
        # Unknown character or malformed key: not covered, nothing created.
        self.assertFalse(self.F.covered(gid, 'char-404'))
        self.assertFalse(self.F.covered(gid, None))

    def test_solo_personal_team(self):
        """Solo (no faction): the player is the owner of a personal team and concludes for it."""
        sim = Simulation(self.path / 'solo', living_knox=True)
        sim.server.g.isServer = lambda: False
        sim.server.rt.execute(LK_WORLD)
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.F = self.rt.eval("require('RadioSurvivor/RS_Factions')")
        self.rt.execute('PLAYERS.solo = enhance(makePlayer("solo")); PLAYERS.solo.isPlayer = true')
        p = self.g.PLAYERS['solo']
        self.rt.execute('RS_CarnetServer.store.data.characters["char-s"] = {id = "char-s", owner = "solo", slot = 0, '
                        'name = "S", contacts = {}, knownMissions = {}}')
        neg = self.F.negotiation(p, self.g.LK_GROUP)
        self.assertEqual((neg.role, neg.personal, neg.revision), ('owner', True, 0))
        ok, why, a = self.F.conclude(p, self.g.LK_GROUP, 'truce', self.rt.table_from({'team': neg.team, 'revision': 0}))
        self.assertTrue(ok, why)
        self.assertTrue(self.F.covered(self.g.LK_GROUP, 'char-s'))
        # A solo target is named by the player's username: still the solo team.
        self.assertEqual(self.rt.eval(f'(function() local d = RS_CarnetServer.store.data.factions '
                                      f'return d.personal.solo end)()'), neg.team)

    def test_bridge_contract_for_negotiate(self):
        base = {'kind': 'npc_talk', 'id': 'r-1-npc-1', 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'order': 1,
                'revision': 1, 'language': 'EN', 'character': 'c-1', 'personality': {}, 'offers': {}, 'text': 'Ok',
                'context': {'stage': 'acquainted'}}
        self.assertEqual(protocol.negotiable(base), [])
        self.assertEqual(protocol.negotiation_prompt(base), '')
        terms = {'truce': {'kind': 'truce'}, 'alliance': {'kind': 'alliance'}, 'peace': {'kind': 'peace'}}
        req = dict(base, context={'negotiation': {'role': 'owner', 'current': 'none', 'terms': terms}})
        self.assertEqual(protocol.negotiable(req), ['truce', 'alliance'])
        self.assertIn('(truce, alliance)', protocol.prompt(req, [])[0]['content'])
        reply = protocol.bounded_reply(req, {'text': 'Deal.', 'intent': 'negotiate', 'offer': 'alliance'})
        self.assertEqual((reply['intent'], reply['offer']), ('negotiate', 'alliance'))
        for bad in ('peace', '', 'Truce'):
            with self.assertRaisesRegex(ValueError, 'inadmissible agreement'):
                protocol.bounded_reply(req, {'text': 'Deal.', 'intent': 'negotiate', 'offer': bad})
        with self.assertRaisesRegex(ValueError, 'inadmissible agreement'):
            protocol.bounded_reply(dict(req, kind='npc_enrich'), {'text': 'x', 'intent': 'negotiate', 'offer': 'truce'})
        # A model reply outside the contract keeps the speech only, without effect.
        out, why = protocol.model_reply(base, '{"text": "Truce!", "intent": "negotiate", "offer": "truce"}')
        self.assertEqual((out['intent'], out['offer'], why), ('none', '', 'inadmissible agreement'))
        # Offline bench flag only: never the player's words.
        self.assertEqual(protocol.offline(req, 'negotiate')['offer'], 'truce')
        self.assertEqual(protocol.offline(req, 'negotiate:alliance')['offer'], 'alliance')
        self.assertEqual(protocol.offline(req, '')['intent'], 'none')
        self.assertEqual(protocol.offline(base, 'negotiate')['intent'], 'none')


class AgreementDecisionTests(test_lk_combat.DecisionCombatTests):
    """Pile de décision réelle (LK_Decisions, LK_Combat, LK_Hostility) : un combattant d'un groupe hostile engagé
    contre le joueur A le lâche au passage de décision suivant quand le crochet covered le couvre ; Decisions.aims
    rend le numéro d'évaluation et la cible, comme RS_Factions les lit."""
    # Inherited test of the bench: run by tests/test_lk_combat.py, not again here.
    test_hostile_group_fighter_engages_the_seen_player_worker_does_not = None

    def test_covered_player_dropped_at_the_next_decision_and_seen_by_aims(self):
        gid = self.mk()
        fighter = self.ev(f'MEMBER_NPC("{gid}", "m-1")')
        # Notebook identity of the players (LK_Hostility.keyOf) and a covered hook driven by the bench.
        self.run_lua('RS_CarnetServer = { bound = setmetatable({}, { __index = function(_, p) '
                     'return "char-" .. p:getUsername() end }) } '
                     'COVER = false; LivingKnox.Hooks = { covered = function() return COVER end }')
        x, y = self.run_lua(f'local z = LivingKnox.Bodies.find("{fighter}") return z:getX(), z:getY()')
        self.h.move_player('A', x + 4, y)
        self.run_lua(f'SEE_PLAYER("{fighter}", "A", {int(x) + 4}, {int(y)}, 4)')
        self.h.move_player('A', 100, 100)
        self.dpass(3)
        self.assertEqual(self.ev(f'LivingKnox.Combat.get("{fighter}").u'), 'A')
        view = self.run_lua(f'local v = LivingKnox.Decisions.aims("{gid}") local m = v.members[1] '
                            'return v.seq, m.npc, m.eval, m.active, m.u, #v.members')
        seq, npc, ev, active, aimed, n = view
        self.assertEqual((npc, active, aimed, n), (fighter, True, 'A', 2))
        self.assertLessEqual(ev, seq)
        # The truce is inscribed: the fighter drops A at its next decision; aims sees it after the mark.
        self.run_lua('COVER = true')
        self.dpass(3)
        self.assertNotEqual(self.run_lua(f'return LivingKnox.Decisions.get("{fighter}").b'), 'fight')
        self.assertIsNone(self.ev(f'LivingKnox.Combat.get("{fighter}")'))
        after = self.run_lua(f'local v = LivingKnox.Decisions.aims("{gid}") local m = v.members[1] '
                             'return m.eval, m.u')
        self.assertGreater(after[0], seq)
        self.assertIsNone(after[1])
        self.assertIsNone(self.ev('LivingKnox.Decisions.aims("grp-404")'))
        self.assertEqual(self.h.errors(self.srv), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
