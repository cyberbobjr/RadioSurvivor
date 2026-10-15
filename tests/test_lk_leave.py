"""Départ individuel (`leave_group`) d'un PNJ incarné (E10-T04).

    python tests/test_lk_leave.py

Banc lupa (Lua 5.1, `next` retiré comme dans Kahlua) : vrai serveur du carnet (`RS_Carnet_Server.lua`), vrais
`RS_Factions.lua` et fournisseur `RS_LivingKnox.lua`, moteur Living Knox réel (registre des groupes, `LK_API`,
population) et vrai pont hors ligne (`RS_OFFLINE_INTENT=leave_group`, drapeau du banc qui tient lieu d'un modèle qui
décide de partir, jamais tiré des mots du joueur). Doublures : `LivingKnox.Sites.pick` (site fixe loin du foyer : la
recherche réelle est prouvée par test_lk_sites.py) et, pour le départ physique, `LivingKnox.Directives.moveTo` (la
consigne réelle est prouvée par test_lk_directives.py). Ne prouve ni l'API Java ni le réseau.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from test_carnet import Simulation, LK_WORLD, convert, count, talk_requests, protocol
from test_protocol import start_bridge, pump, lua_list
from test_lk_materialize import MatBase

# Type « loners » (fichier de données livré) chargé comme le jeu le fait pour media/lua/shared ; site et consigne
# remplacés par des doublures qui notent leurs appels.
LEAVE_DOUBLES = r'''
require 'LivingKnox/Data/LK_Type_loners'
SITE_CALLS, MOVES = {}, {}
LivingKnox.Sites.pick = function(groupType, opts)
    SITE_CALLS[#SITE_CALLS + 1] = {type = groupType, seed = opts and opts.seed, near = opts and opts.near}
    if SITE_FAIL then return nil, 'no building' end
    return {x = 11200, y = 9412, z = 0, key = 'b77', kind = 'building'}
end
LivingKnox.Directives = LivingKnox.Directives or {}
LivingKnox.Directives.moveTo = function(id, x, y, z, gesture)
    MOVES[#MOVES + 1] = {id = id, x = math.floor(x), y = math.floor(y), z = z, g = gesture}
    if MOVE_FAIL then return nil, 'target square is not loaded' end
    return #MOVES
end
'''


class LeaveGroupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-leave-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, name, intent='leave_group'):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.server.rt.execute(LEAVE_DOUBLES)
        sim.add_client('alice')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.G = self.rt.eval('LivingKnox.Groups')
        self.api = self.rt.eval('LivingKnox.API')
        self.F = self.rt.eval("require('RadioSurvivor/RS_Factions')")
        for npc in (self.g.LK_LEADER, self.g.LK_MATE):
            self.g.LivingKnox.Bodies.bound[npc].x = 12
        self.process = start_bridge(sim.path, intent)
        return sim

    def talk(self, npc, text, before_reply=None, acquaint=True):
        sim = self.sim
        sim.command('alice', 'select', incarnation=npc)
        if acquaint:
            sim.acquaint('alice')
        self.server.lastTalk[sim.character('alice')] = None
        sim.command('alice', 'talk', channel='say', text=text, language='FR')
        [req] = talk_requests(self.g)
        rid = req.id
        bound = convert(self.server.collectives[rid]) if self.server.collectives[rid] else None
        if before_reply:
            before_reply()
        self.assertTrue(pump(lambda: not any(r.id == rid for r in self.server.pending.values()), [sim.tick]),
                        'no reply: ' + text)
        out = convert(req)
        out['bound'] = bound
        return out

    def group_of(self, npc):
        gid, mid = self.G.findNpc(npc)
        return gid, mid, self.G.get(gid)

    def log(self, gid, kind):
        return [e.text for e in lua_list(self.G.get(gid).log) if e.kind == kind]

    def logs(self):
        return [self.g.LOGS[i] for i in range(1, len(self.g.LOGS) + 1)]

    def test_member_leaves_alone_fiche_and_memories_kept(self):
        sim = self.world('member')
        old = self.g.LK_GROUP
        mate_mid = self.group_of(self.g.LK_MATE)[1]
        before = self.api.composition(old)
        req = self.talk(self.g.LK_MATE, 'Tu devrais partir, ton chef ne vous mène nulle part.')
        # Offered to an acquainted character, bound to the group and its composition.
        self.assertEqual(req['context']['leave'], {'alone': True})
        self.assertEqual({k: req['bound'][k] for k in ('ref', 'key')}, {'ref': old, 'key': before.key})
        self.assertIn('Leaving your group', protocol.prompt(req, [])[0]['content'])
        # One transition: the member left the old group, a loner group of one member linked to the same NPC.
        gid, mid, g = self.group_of(self.g.LK_MATE)
        self.assertNotEqual(gid, old)
        self.assertEqual((g.type, g.name, g.leader, mid, self.G.livingCount(g)), ('loners', g.name, mid, 'm-1', 1))
        self.assertEqual((g.home.x, g.home.y, g.home.z), (11200, 9412, 0))
        self.assertEqual(convert(g.members[mid])['role'], 'fighter')
        self.assertEqual(self.log(gid, 'separated'), [old])
        o = self.G.get(old)
        self.assertIsNone(o.members[mate_mid])
        self.assertEqual(self.log(old, 'left'), [mate_mid])
        self.assertEqual(o.leader, self.group_of(self.g.LK_LEADER)[1], 'leader changed by a member departure')
        # The loner group is named after the NPC (name kept), never drawn by the population.
        fiche = self.server.find(self.g.LK_MATE)
        self.assertEqual(g.name, fiche.name)
        self.assertEqual(self.g.RS_LivingKnox.npc(self.g.LK_MATE).name, fiche.name)
        weights = self.rt.eval('LivingKnox.Population.typeWeights(LivingKnox.Config.population())')
        self.assertNotIn('loners', [w.id for w in lua_list(weights)])
        # Site far from the old home (Sites.pick with the loners type), physical departure toward it.
        self.assertEqual([(c.type, c.seed) for c in lua_list(self.g.SITE_CALLS)], [('loners', 'leave/' + self.g.LK_MATE)])
        # E10-T05: ring around the old home (LivingKnox.Config.LEAVE), widened by LK_Sites before the whole map.
        [call] = lua_list(self.g.SITE_CALLS)
        cfg = self.rt.eval('LivingKnox.Config.LEAVE')
        self.assertEqual((cfg.HOME_MIN, cfg.HOME_MAX), (400, 1200))
        self.assertEqual(convert(call.near), {'x': 10637, 'y': 9412, 'min': 400, 'max': 1200})
        [move] = lua_list(self.g.MOVES)
        self.assertEqual((move.id, move.g, move.z), (self.g.LK_MATE, 'walk', 0))
        self.assertGreater(move.x, 12, 'walk not toward the new home')
        # Fiche, contact and history unchanged (keys by fiche); group of the fiche follows.
        self.assertEqual(self.server.find(self.g.LK_MATE).id, fiche.id)
        contact = sim.state().characters[sim.character('alice')].contacts[fiche.id]
        self.assertTrue(any(h.author == fiche.name for h in lua_list(contact.history)))
        self.assertEqual((fiche.clan, fiche.groupName), (gid, g.name))
        self.assertTrue(any('left group ' + old + ' for ' + gid in line for line in self.logs()))
        # The client sees the same state (snapshot pushed after the reply): new group name, never a raw id.
        snap = sim.clients['alice'].g.RS_CarnetClient.snapshot
        [seen] = [c for c in snap.contacts.values() if c.id == fiche.id]
        self.assertEqual((seen.groupName, seen.clan), (g.name, None))
        # Written at once: survives a restart of the registry, nothing dropped.
        self.assertFalse(self.G.isDirty())
        self.rt.execute('assert(LivingKnox.Groups.init(false))')
        self.assertEqual(self.G.state.dropped, 0)
        self.assertEqual(self.G.findNpc(self.g.LK_MATE), (gid, 'm-1'))
        self.assertIsNone(self.G.get(old).members[mate_mid])
        # The loner may not leave again (alone); a later talk is not bound to a departure.
        req = self.talk(self.g.LK_MATE, 'Et maintenant ?')
        self.assertNotIn('leave', req['context'])
        self.assertEqual(self.G.findNpc(self.g.LK_MATE)[0], gid)

    def test_leader_leaves_immediate_succession(self):
        self.world('leader')
        old = self.g.LK_GROUP
        mate = self.group_of(self.g.LK_MATE)[1]
        self.talk(self.g.LK_LEADER, 'Vos gens ne vous suivent plus.')
        gid = self.group_of(self.g.LK_LEADER)[0]
        self.assertEqual(self.G.get(gid).type, 'loners')
        o = self.G.get(old)
        self.assertEqual(o.leader, mate, 'no immediate succession')
        self.assertEqual(self.log(old, 'leader')[-1], mate)
        self.assertEqual(self.api.composition(old).alive, 1)

    def test_late_reply_on_an_older_composition_rejected(self):
        sim = self.world('late')
        old = self.g.LK_GROUP
        client = sim.clients['alice'].g.RS_CarnetClient
        # An arrival between the request and the reply: the departure is refused before any effect.
        self.talk(self.g.LK_MATE, 'Pars avec moi.',
                  lambda: self.rt.execute(f'assert(LivingKnox.Groups.addMember("{old}", {{role = "worker"}}))'))
        self.assertEqual(self.G.findNpc(self.g.LK_MATE)[0], old)
        self.assertEqual(client.lastError, 'NoAnswer')
        self.assertEqual(count(self.g.MOVES), 0)
        self.assertTrue(any('group composition changed' in line for line in self.logs()))
        # Current composition: applied once.
        self.talk(self.g.LK_MATE, 'Pars avec moi.')
        self.assertNotEqual(self.G.findNpc(self.g.LK_MATE)[0], old)
        self.assertEqual(count(self.g.SITE_CALLS), 1)

    def test_no_site_or_no_walk(self):
        self.world('nosite')
        old = self.g.LK_GROUP
        # No home for the loner: nothing changes (one transition or none).
        self.g.SITE_FAIL = True
        self.talk(self.g.LK_MATE, 'Pars.')
        self.assertEqual(self.G.findNpc(self.g.LK_MATE)[0], old)
        self.assertTrue(any('no home for the loner' in line for line in self.logs()))
        # The walk fails: the social departure stays.
        self.g.SITE_FAIL, self.g.MOVE_FAIL = False, True
        self.talk(self.g.LK_MATE, 'Pars.')
        self.assertNotEqual(self.G.findNpc(self.g.LK_MATE)[0], old)
        self.assertEqual(count(self.g.MOVES), len(lua_list(self.rt.eval('RS_LivingKnox.WALK_STEPS'))))
        self.assertTrue(any('walk away failed: target square is not loaded' in line for line in self.logs()))

    def test_truces_kept_without_renegotiation(self):
        sim = self.world('truce')
        old = self.g.LK_GROUP
        alice = self.g.PLAYERS['alice']
        cid = sim.character('alice')
        neg = self.F.negotiation(alice, old)
        ok, why, a = self.F.conclude(alice, old, 'truce', self.rt.table_from({'team': neg.team, 'revision': 0}))
        self.assertTrue(ok, why)
        self.talk(self.g.LK_MATE, 'Pars.')
        gid = self.group_of(self.g.LK_MATE)[0]
        # The NPC who left stays covered toward alice's team in its new group; another NPC of that group would not be.
        self.assertTrue(self.F.covered(gid, cid, self.g.LK_MATE))
        self.assertFalse(self.F.covered(gid, cid, self.g.LK_RAIDER))
        self.assertTrue(self.F.covered(old, cid, self.g.LK_LEADER), 'old group agreement lost')
        [t] = [convert(x) for x in lua_list(self.F.trucesOf(self.g.LK_MATE))]
        self.assertEqual((t['team'], t['kind'], t['group'], t['agreement']), (neg.team, 'truce', old, a.id))
        # Through the engine hook used by the choice of target.
        self.assertTrue(self.rt.eval('LivingKnox.Hostility.isCovered')(gid, cid, self.g.LK_MATE))
        # An agreement concluded with the old group after the departure does not cover the loner.
        self.assertTrue(self.F.cancelAgreement(old, neg.team))
        self.assertTrue(self.F.covered(gid, cid, self.g.LK_MATE), 'personal truce lost with the old agreement')

    def test_not_offered_to_a_stranger_nor_alone(self):
        self.world('stranger')
        req = self.talk(self.g.LK_MATE, 'Bonjour.', acquaint=False)
        self.assertNotIn('leave', req['context'])
        self.assertEqual(self.G.findNpc(self.g.LK_MATE)[0], self.g.LK_GROUP)
        # Last living member of a group: may not leave (nothing to leave).
        self.rt.execute(f'assert(LivingKnox.Groups.markDead("{self.g.LK_GROUP}", '
                        f'select(2, LivingKnox.Groups.findNpc(LK_LEADER))))')
        req = self.talk(self.g.LK_MATE, 'Bonjour.')
        self.assertNotIn('leave', req['context'])
        self.assertEqual(self.G.findNpc(self.g.LK_MATE)[0], self.g.LK_GROUP)

    def test_home_options_ring_around_the_old_home(self):
        # E10-T05: ring around the old home, values read from LivingKnox.Config.LEAVE at each departure.
        self.world('opts')
        options = self.rt.eval('RS_LivingKnox.homeOptions')
        o = convert(options('npc-9', self.G.get(self.g.LK_GROUP)))
        self.assertEqual(o, {'seed': 'leave/npc-9', 'near': {'x': 10637, 'y': 9412, 'min': 400, 'max': 1200}})
        self.rt.execute('LivingKnox.Config.LEAVE = {HOME_MIN = 150, HOME_MAX = 600}')
        o = convert(options('npc-9', self.G.get(self.g.LK_GROUP)))
        self.assertEqual(o['near'], {'x': 10637, 'y': 9412, 'min': 150, 'max': 600})
        # A group without home: the usual draw over the whole map.
        self.assertEqual(convert(options('npc-9', self.rt.table())), {'seed': 'leave/npc-9'})

    def test_loner_never_relieved_nor_drawn(self):
        self.world('relief')
        self.talk(self.g.LK_MATE, 'Pars.')
        gid = self.group_of(self.g.LK_MATE)[0]
        mid = self.group_of(self.g.LK_MATE)[1]
        self.rt.execute(f'assert(LivingKnox.Groups.markDead("{gid}", "{mid}"))')
        due = self.rt.eval(f'''(function()
            local P, d = LivingKnox.Population, LivingKnox.Groups.state.data
            local marked = P.markGone(d, 100, LivingKnox.Config.population())
            local out = {{}}
            for _, x in ipairs(marked) do out[#out + 1] = x end
            out[#out + 1] = '|'
            for _, x in ipairs(P.dueReliefs(d, 1e9)) do out[#out + 1] = x end
            return out
        end)()''')
        self.assertEqual(lua_list(due), [gid, '|'], 'a dead loner calls a relief group')


class LeaveSuiteListing(MatBase):
    """Suite en jeu `lk.leave` chargée par le vrai moteur RST (listage seulement : elle demande le jeu)."""
    mode = 'solo'

    def test_dev_suite_lists_with_world_tags(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKLeave.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.leave", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.leave')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)


class LeaveContractTests(unittest.TestCase):
    BASE = {'kind': 'npc_talk', 'id': 'r-1-npc-1', 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'order': 1, 'revision': 1,
            'language': 'EN', 'character': 'c-1', 'personality': {'loyalty': 'wavering'}, 'offers': {}, 'text': 'Hi',
            'context': {'stage': 'acquainted', 'leave': {'alone': True}}}

    def test_leave_group_only_when_offered(self):
        req = dict(self.BASE)
        self.assertEqual(protocol.bounded_reply(req, {'text': 'Bye.', 'intent': 'leave_group'})['intent'], 'leave_group')
        with self.assertRaises(ValueError):
            protocol.bounded_reply(req, {'text': 'Bye.', 'intent': 'leave_group', 'offer': 'x'})
        no = dict(req, context={'stage': 'acquainted'})
        reply, why = protocol.model_reply(no, '{"text": "Bye.", "intent": "leave_group"}')
        self.assertEqual((reply['intent'], why), ('none', 'no group to leave'))
        self.assertNotIn('Leaving your group', protocol.prompt(no, [])[0]['content'])
        member = dict(req, kind='npc_member', character='group')
        reply, why = protocol.model_reply(member, '{"text": "Bye.", "intent": "leave_group"}')
        self.assertEqual(reply['intent'], 'none')
        # Offline bench flag only; never from the player's words.
        self.assertEqual(protocol.offline(req, 'leave_group')['intent'], 'leave_group')
        self.assertEqual(protocol.offline(req, '')['intent'], 'none')
        self.assertEqual(protocol.offline(no, 'leave_group')['intent'], 'none')


if __name__ == '__main__':
    unittest.main(verbosity=2)
