"""Relation personnelle d'un PNJ envers un personnage, intention `change_relation` (E09-T04).

    python tests/test_relations.py

Banc lupa (Lua 5.1, `next` retiré comme dans Kahlua) : vrai serveur du carnet (`RS_Carnet_Server.lua`), vrai
`RS_Relations.lua`, moteur Living Knox réel (registres, `LK_Hostility`, API, fournisseur `RS_LivingKnox.lua`) et vrai
pont hors ligne (`RS_OFFLINE_INTENT=relation[...]`, drapeau du banc qui tient lieu d'un modèle qui cite un fait, jamais
tiré des mots du joueur). Doublures seulement : ne prouve ni l'API Java ni le réseau.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, LK_WORLD, convert, talk_requests, protocol
from test_protocol import start_bridge, pump, lua_list

LEVELS = ['hostile', 'wary', 'cautious', 'favorable', 'trusting']


def shifted(level, gap):
    return LEVELS[max(0, min(4, LEVELS.index(level) + gap))]


class RelationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-relations-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        self.stop()
        self.tmp.cleanup()

    def stop(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
            self.process = None

    def world(self, name, intent='relation', clients=('alice', 'bob')):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        for c in clients:
            sim.add_client(c)
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.R = self.rt.eval("require('RadioSurvivor/RS_Relations')")
        self.H = self.rt.eval('LivingKnox.Hostility')
        for npc in (self.g.LK_LEADER, self.g.LK_MATE):
            self.g.LivingKnox.Bodies.bound[npc].x = 12
        if intent is not None:
            self.process = start_bridge(sim.path, intent)
        return sim

    def cid(self, name):
        return self.sim.character(name)

    def fiche(self, npc):
        return self.server.ensure(npc)

    def fact(self, name, fact):
        """Real attitude fact of the group toward this character, seen by a member (LK_Hostility.record)."""
        res = self.H.record(self.g.LK_GROUP, self.cid(name), fact, self.rt.table_from({'witnessed': True}))
        self.assertIsNotNone(res, fact)

    def request(self, name, npc, text):
        self.sim.command(name, 'select', incarnation=npc)
        self.sim.acquaint(name)
        self.server.lastTalk[self.cid(name)] = None
        self.sim.command(name, 'talk', channel='say', text=text, language='FR')

    def say(self, name, npc, text, before_reply=None):
        """One sentence of name to this NPC; returns the request (Python copy) once handled."""
        self.request(name, npc, text)
        [req] = [r for r in talk_requests(self.g) if r.character == self.cid(name)]
        rid = req.id
        if before_reply:
            before_reply()
        self.assertTrue(pump(lambda: not any(r.id == rid for r in self.server.pending.values()), [self.sim.tick]),
                        'no reply: ' + text)
        return convert(req)

    def view(self, name, npc):
        v = self.R.view(self.fiche(npc), self.cid(name))
        return (v.level, v.trend, v.group)

    def pair(self, name, npc):
        p = self.R.debugPair(self.fiche(npc).id, self.cid(name))
        return convert(p) if p else None

    def group_level(self, name):
        return self.rt.eval('LivingKnox.API').attitude(self.g.LK_GROUP, self.cid(name)).level

    def logs(self):
        return [self.g.LOGS[i] for i in range(1, len(self.g.LOGS) + 1)]

    SAID = "Je n'oublierai pas ce que tu as fait."   # offline bridge line of a change_relation (FR)

    def spoken(self, name, npc):
        """Lines of this NPC said to the character of name (contact history, filled only for an accepted reply)."""
        fiche = self.fiche(npc)
        known = self.sim.state().characters[self.cid(name)].contacts[fiche.id]
        return [h.text for h in known.history.values() if h.author == fiche.name] if known else []

    def offer(self, name, npc):
        context, binding = self.R.offer(self.fiche(npc), self.cid(name))
        return convert(context), binding

    def apply(self, name, npc, binding, direction, fact_id):
        return self.R.apply(self.fiche(npc), self.cid(name), binding, direction, fact_id)

    def test_help_then_betrayal_two_changes(self):
        """« Une aide puis une trahison motivent deux changements » (bout en bout, pont hors ligne)."""
        self.world('help-betrayal')
        leader = self.g.LK_LEADER
        start = self.group_level('alice')
        self.assertEqual(start, 'favorable', 'settlers start favorable')
        # Help: a gift seen by the group. The request offers it as a citable fact (short id, nature, no key).
        self.fact('alice', 'gift')
        req = self.say('alice', leader, 'Tu te souviens du sac de riz que je vous ai laissé ?')
        rel = req['context']['relation']
        self.assertEqual((rel['level'], rel['group']), ('favorable', 'favorable'))
        self.assertEqual([(f['id'], f['fact'], f['nature'], f['source']) for f in rel['facts'].values()],
                         [('f1', 'gift', 'good', 'group')])
        self.assertNotIn('trust', req['context'], 'former trust field replaced by the relation')
        self.assertNotIn('att:', str(req), 'fact key sent to the bridge')
        self.assertIn('Your personal relation with this character: favorable', protocol.prompt(req, [])[0]['content'])
        self.assertEqual(self.view('alice', leader), ('trusting', 'up', 'favorable'), 'one level above the group')
        self.assertTrue(any('relation of ' in line and ' up (att:' + self.g.LK_GROUP + ':1): trusting' in line
                            for line in self.logs()), self.logs())
        # Betrayal: a hit seen by the group. The used gift is no longer offered; the hit is cited, the relation drops.
        self.fact('alice', 'hit')
        req = self.say('alice', leader, 'Désolé pour le coup de tout à l\'heure.')
        facts = [(f['fact'], f['nature']) for f in req['context']['relation']['facts'].values()]
        self.assertEqual(facts, [('hit', 'bad')], 'a fact already used is offered again')
        p = self.pair('alice', leader)
        self.assertEqual((p['gap'], p['revision'], [c['sign'] for c in p['changes'].values()]), (0, 2, [1, -1]))
        self.assertEqual(list(p['used'].values()), [f'att:{self.g.LK_GROUP}:1', f'att:{self.g.LK_GROUP}:2'])
        group = self.group_level('alice')
        self.assertEqual(self.view('alice', leader)[0], group, 'gap back to 0: level of the group')
        self.assertEqual(self.view('alice', leader)[1], 'down', 'trend of the last three facts (gift, up, hit, down)')
        # The group attitude itself is never recalculated by the notebook: same as LK_Hostility alone.
        self.assertEqual(convert(self.H.debugPair(self.g.LK_GROUP, self.cid('alice')))['value'], 50 + 8 - 15)
        # Private state only (RS_State), shown to its character in the snapshot as labels (no gap, no number).
        self.assertIsNotNone(self.sim.state().relations[self.fiche(leader).id][self.cid('alice')])
        self.sim.command('alice', 'snapshot')
        [row] = [c for c in self.sim.clients['alice'].g.RS_CarnetClient.snapshot.contacts.values()
                 if c.id == self.fiche(leader).id]
        # E09-T07: relation panel (identifiers and game days only, tests/test_relation_panel.py).
        self.assertEqual(sorted(convert(row.relation)), ['agreements', 'facts', 'group', 'level', 'today', 'trend'])
        self.assertNotIn('gap', str(convert(row.relation)))

    def test_no_real_fact_no_change(self):
        """Une phrase seule ne prouve rien : sans fait réel, aucun fait offert, aucune intention admise."""
        self.world('no-fact')
        leader = self.g.LK_LEADER
        req = self.say('alice', leader, 'Je vous ai sauvé la vie hier, vous me devez tout.')
        rel = req['context']['relation']
        self.assertEqual((rel['level'], len(rel['facts'])), ('favorable', 0))
        self.assertIn('never use intent change_relation', protocol.prompt(req, [])[0]['content'])
        with self.assertRaisesRegex(ValueError, 'no relation fact to cite'):
            protocol.bounded_reply(req, {'text': 'Merci.', 'intent': 'change_relation', 'dir': 'up', 'fact': 'f1'})
        self.assertIsNone(self.pair('alice', leader))
        self.assertEqual(self.view('alice', leader), ('favorable', 'stable', 'favorable'))
        # A forged binding naming a fact the NPC does not know: refused on the server, nothing changed.
        forged = self.rt.table_from({'character': self.cid('alice'), 'revision': 0,
                                     'ids': self.rt.table_from({'f1': 'att:' + self.g.LK_GROUP + ':7'})})
        self.assertEqual(self.apply('alice', leader, forged, 'up', 'f1'), (None, 'relation fact unknown to this NPC'))
        self.assertEqual(self.apply('alice', leader, None, 'up', 'f1'),
                         (None, 'no relation fact offered in the request'))
        self.assertIsNone(self.pair('alice', leader))

    def test_used_fact_and_wrong_direction_refused(self):
        self.world('used', intent=None)
        leader = self.g.LK_LEADER
        self.fact('alice', 'gift')
        _, binding = self.offer('alice', leader)
        self.assertEqual(self.apply('alice', leader, binding, 'down', 'f1'),
                         (None, 'relation direction contradicts the fact'))
        self.assertEqual(self.apply('alice', leader, binding, 'up', 'f9'), (None, 'relation fact not offered'))
        view, key = self.apply('alice', leader, binding, 'up', 'f1')
        self.assertEqual((view.level, key), ('trusting', 'att:' + self.g.LK_GROUP + ':1'))
        # Same fact again, with an up-to-date revision: already used.
        binding.revision = 1
        self.assertEqual(self.apply('alice', leader, binding, 'up', 'f1'), (None, 'relation fact already used'))
        self.assertEqual(self.pair('alice', leader)['revision'], 1)

    def test_stale_revision_refused(self):
        """Aucune transition sur une révision périmée : relation changée entre la demande et la réponse, fiche aussi."""
        self.world('stale')
        leader = self.g.LK_LEADER
        self.fact('alice', 'gift')
        self.fact('alice', 'heal')

        def change_meanwhile():
            _, binding = self.offer('alice', leader)
            self.assertIsNotNone(self.apply('alice', leader, binding, 'up', 'f1')[0])

        self.say('alice', leader, 'Merci pour tout.', change_meanwhile)
        # E09-T08: only the change is ignored; the line of the NPC is still said.
        self.assertTrue(any('ignored, reply kept: relation revision changed' in line for line in self.logs()),
                        self.logs())
        self.assertIsNone(self.sim.clients['alice'].g.RS_CarnetClient.lastError)
        self.assertEqual(self.spoken('alice', leader), [self.SAID])
        p = self.pair('alice', leader)
        self.assertEqual((p['gap'], p['revision']), (1, 1), 'only the change made meanwhile')
        # Fiche revision changed while the model answers (NPC died and came back, E17): the whole reply is still
        # refused before any effect (every server check of the request is stale, not only the relation).
        self.fact('alice', 'hit')
        fiche = self.fiche(leader)
        self.say('alice', leader, 'Pardon.', lambda: setattr(fiche, 'revision', fiche.revision + 1))
        self.assertTrue(any('refused: NPC revision changed' in line for line in self.logs()), self.logs())
        self.assertEqual(self.sim.clients['alice'].g.RS_CarnetClient.lastError, 'NoAnswer')
        self.assertEqual(self.spoken('alice', leader), [self.SAID])
        self.assertEqual(self.pair('alice', leader)['revision'], 1)

    def binding(self):
        """Server binding of the only pending talk (Server.relations[request id]), or None."""
        [(rid, b)] = [(r.id, self.server.relations[r.id]) for r in self.server.pending.values()
                      if r.kind == 'npc_talk']
        return rid, b

    def refused_change(self, name, npc, reason, meanwhile):
        """One sentence whose change_relation is refused by the server for reason: the reply is said, the relation
        stays as it was right after meanwhile (the state changed while the model answered), the refusal is logged."""
        state = {}

        def hook():
            meanwhile()
            state['pair'] = self.pair(name, npc)

        before = self.spoken(name, npc)
        req = self.say(name, npc, 'Tu te souviens ?', hook)
        self.assertEqual(req['context']['relation']['facts'] != {}, True, 'a fact offered to cite')
        line = (f'relation change of {self.fiche(npc).id} toward {self.cid(name)} in {req["id"]} ignored, reply kept: '
                + reason)
        self.assertIn(line, [x.partition('[RS_Carnet] ')[2] for x in self.logs()], self.logs())
        self.assertFalse(any(req['id'] + ' refused' in x for x in self.logs()), 'whole reply refused')
        self.assertIsNone(self.sim.clients[name].g.RS_CarnetClient.lastError, 'the player sees NoAnswer')
        self.assertEqual(self.spoken(name, npc), before + [self.SAID], 'reply of the NPC not said')
        self.assertEqual(self.pair(name, npc), state['pair'], 'relation changed by a refused change')

    def test_refused_change_keeps_the_reply(self):
        """E09-T08 : chaque motif de refus du serveur garde la réplique et laisse la relation inchangée."""
        self.world('refused', intent='relation:up')
        leader = self.g.LK_LEADER
        group = self.g.LK_GROUP
        for f in ('gift', 'heal', 'hit'):
            self.fact('alice', f)

        def drop_binding():
            rid, _ = self.binding()
            self.server.relations[rid] = None

        def empty_ids():
            self.binding()[1].ids = self.rt.table_from({})

        def forged_unknown():
            b = self.binding()[1]
            for k in list(b.ids.keys()):
                b.ids[k] = f'att:{group}:7'

        def opposite_nature():
            b = self.binding()[1]
            bad_key = b.ids['f3']   # hit; relation:up cites f2 (heal, the last good fact offered)
            for k in list(b.ids.keys()):
                b.ids[k] = bad_key

        self.refused_change('alice', leader, 'no relation fact offered in the request', drop_binding)
        self.refused_change('alice', leader, 'relation fact not offered', empty_ids)
        self.refused_change('alice', leader, 'relation fact unknown to this NPC', forged_unknown)
        self.refused_change('alice', leader, 'relation direction contradicts the fact', opposite_nature)
        self.assertIsNone(self.pair('alice', leader), 'four refusals, no change')

        def used_meanwhile():
            # The cited fact (heal) is used by another change while the model answers; the binding is brought up to
            # date so that only "already used" remains.
            _, b = self.binding()
            _, fresh = self.offer('alice', leader)
            [fid] = [k for k, v in fresh.ids.items() if v == b.ids['f2']]   # the cited fact (heal)
            self.assertIsNotNone(self.apply('alice', leader, fresh, 'up', fid)[0])
            b.revision = self.pair('alice', leader)['revision']

        self.refused_change('alice', leader, 'relation fact already used', used_meanwhile)
        self.assertEqual(self.pair('alice', leader)['gap'], 1, 'only the change made meanwhile')

        # bob: another good fact raises the gap to +1 while the model answers; the cited fact meets the bound.
        for f in ('gift', 'heal'):
            self.fact('bob', f)

        def bound_meanwhile():
            _, b = self.binding()
            _, fresh = self.offer('bob', leader)
            [fid] = [k for k, v in fresh.ids.items() if v == b.ids['f1']]   # gift, not the cited heal (f2)
            self.assertIsNotNone(self.apply('bob', leader, fresh, 'up', fid)[0])
            b.revision = self.pair('bob', leader)['revision']

        self.refused_change('bob', leader, 'relation gap at its bound', bound_meanwhile)
        self.assertEqual(self.pair('bob', leader)['gap'], 1)

    def test_valid_change_applied_with_its_reply(self):
        """E09-T08 : un changement valide reste appliqué, avec la réplique."""
        self.world('valid', intent='relation:up')
        leader = self.g.LK_LEADER
        self.fact('alice', 'gift')
        req = self.say('alice', leader, 'Le riz vous a servi ?')
        self.assertEqual(self.spoken('alice', leader), [self.SAID])
        self.assertIsNone(self.sim.clients['alice'].g.RS_CarnetClient.lastError)
        self.assertEqual((self.pair('alice', leader)['gap'], self.view('alice', leader)[0]), (1, 'trusting'))
        self.assertFalse(any('ignored' in x for x in self.logs()), self.logs())
        self.assertTrue(any(f'relation of {self.fiche(leader).id} toward {self.cid("alice")} up' in x
                            for x in self.logs()), (req['id'], self.logs()))

    def test_two_npcs_of_a_group_differ(self):
        """Deux PNJ d'un même groupe diffèrent selon la réponse : le chef cite l'aide, le second n'en dit rien."""
        self.world('two-npcs')
        self.fact('alice', 'gift')
        self.say('alice', self.g.LK_LEADER, 'Le riz vous a servi ?')
        self.stop()
        self.process = start_bridge(self.sim.path, '')
        req = self.say('alice', self.g.LK_MATE, 'Le riz vous a servi ?')
        self.assertEqual([f['fact'] for f in req['context']['relation']['facts'].values()], ['gift'],
                         'the same group fact is citable by the other member')
        self.assertEqual(self.view('alice', self.g.LK_LEADER)[0], 'trusting')
        self.assertEqual(self.view('alice', self.g.LK_MATE)[0], 'favorable')
        # bob, same group, no fact: both members see him at the group level.
        self.assertEqual(self.view('bob', self.g.LK_LEADER)[0], self.group_level('bob'))

    def test_gap_bounded_to_one_level(self):
        self.world('bound', intent=None)
        leader = self.g.LK_LEADER
        for f in ('gift', 'heal'):
            self.fact('alice', f)
        _, binding = self.offer('alice', leader)
        self.assertIsNotNone(self.apply('alice', leader, binding, 'up', 'f2')[0])
        # At +1: no good fact offered any more; a forged up is refused at the bound.
        context, binding = self.offer('alice', leader)
        self.assertEqual(context['facts'], {})
        self.assertIsNone(binding)
        forged = self.rt.table_from({'character': self.cid('alice'), 'revision': 1,
                                     'ids': self.rt.table_from({'f1': 'att:' + self.g.LK_GROUP + ':1'})})
        self.assertEqual(self.apply('alice', leader, forged, 'up', 'f1'), (None, 'relation gap at its bound'))
        # Three betrayals: +1 -> 0 -> -1, then the bound (no bad fact offered).
        for f in ('theft', 'hit', 'shot'):
            self.fact('alice', f)
        for expected in (0, -1):
            context, binding = self.offer('alice', leader)
            last = max(context['facts'].values(), key=lambda f: f['id'])
            self.assertEqual(last['nature'], 'bad')
            self.assertIsNotNone(self.apply('alice', leader, binding, 'down', last['id'])[0])
            self.assertEqual(self.pair('alice', leader)['gap'], expected)
        context, _ = self.offer('alice', leader)
        self.assertEqual([f['nature'] for f in context['facts'].values()], [])
        level, _, group = self.view('alice', leader)
        self.assertEqual(level, shifted(group, -1))

    def test_observation_and_closed_mission_are_citable(self):
        self.world('sources', intent=None)
        leader = self.g.LK_LEADER
        fiche = self.fiche(leader)
        self.sim.command('alice', 'select', incarnation=leader)
        obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        cid = self.cid('alice')
        for source in ('seen', 'heard_from:npc-x'):
            obs.record(fiche.id, self.rt.table_from({'fact': 'assault_seen', 'subject': cid, 'day': 4,
                                                     'place': 'area-1-1' if source == 'seen' else 'area-2-2',
                                                     'source': source}))
        obs.record(fiche.id, self.rt.table_from({'fact': 'player_return', 'subject': cid, 'day': 5, 'place': 'x'}))
        self.rt.execute(f'''RS_CarnetServer.store.data.missions["mis-1"] = {{id = "mis-1", npc = "{fiche.id}",
            state = "success", template = "scout", closedAt = 10, participants = {{["{cid}"] = {{name = "A"}}}},
            invited = {{}}}}
            RS_CarnetServer.store.data.missions["mis-2"] = {{id = "mis-2", npc = "{fiche.id}", state = "failed",
            closedAt = 20, participants = {{}}, invited = {{}}}}''')
        context, binding = self.offer('alice', leader)
        facts = [(f['fact'], f['nature'], f['source']) for f in context['facts'].values()]
        # Heard observation, neutral comeback and a mission without the character: never citable.
        self.assertEqual(facts, [('assault_seen', 'bad', 'seen'), ('mission_success', 'good', 'mission')])
        self.assertEqual(context['facts'][2]['kind'], 'scout')
        view, key = self.apply('alice', leader, binding, 'up', 'f2')
        self.assertEqual(key, 'mis:mis-1')
        # The observation forgotten since the offer: the fact is unknown to the NPC now.
        context, binding = self.offer('alice', leader)
        obs.forget(fiche.id)
        self.assertEqual(self.apply('alice', leader, binding, 'down', 'f1'),
                         (None, 'relation fact unknown to this NPC'))

    def test_prune_with_the_fiche_and_the_character(self):
        self.world('prune', intent=None)
        leader = self.g.LK_LEADER
        self.fact('alice', 'gift')
        _, binding = self.offer('alice', leader)
        self.apply('alice', leader, binding, 'up', 'f1')
        self.assertTrue(self.R.prune() is False)
        self.g.RS_CarnetServer.characterDeath(self.g.PLAYERS['alice'])
        self.assertTrue(self.R.prune())
        self.assertIsNone(self.pair('alice', leader))


if __name__ == '__main__':
    unittest.main()
