"""Observations personnelles des PNJ (E08-T02) : RS_Observations.lua dans le vrai serveur du carnet (lupa, Lua 5.1, `next`
retiré comme dans Kahlua) et le vrai pont (npc_protocol : champ observations=, prompt).

    python tests/test_observations.py

Couvre : validation (liste fermée de faits, sujet, jour, lieu sans coordonnée exacte, source), bornes (observations
par PNJ, chaîne, PNJ suivis), une même observation transmise deux fois stockée une fois avec sa chaîne, aucune boucle
(un PNJ ne réapprend pas ce qu'il a transmis, même après éviction), chaîne pleine non retransmise, observation directe
qui remplace un ouï-dire, purge à la mort et au retrait d'une fiche, persistance dans l'état privé RS_State (aucune
ModData globale), champ joint à la demande npc_talk (absent sans observation et pour npc_enrich), relu par le pont et
présenté comme souvenirs non vérifiés ; prompt inchangé sans observation.
Doublures du jeu de tests/test_carnet.py : ne prouve pas l'API Java réelle.
E08-T07 (TriggerTests) : déclencheurs du carnet et de Living Knox. E08-T08 (WorldTriggerTests) : orage, coupure du
réseau électrique et passage de l'hélicoptère vanilla (signature de son de monde), doublures de ClimateManager et
SandboxOptions.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from test_carnet import LK_WORLD, Simulation, convert, count
from test_protocol import LUA, ROOT, lua_list

sys.path.insert(0, str(ROOT / 'bridge'))
import npc_protocol as protocol  # noqa: E402
import radio_bridge as bridge_module  # noqa: E402

SOURCE = LUA / 'server/RadioSurvivor/RS_Observations.lua'


class ObservationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-obs-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, name='game', npcs=1):
        """Serveur du carnet, alice liée ; fiches créées comme au contact (Server.ensure) pour npcs corps."""
        sim = Simulation(self.path / name)
        sim.add_client('alice')
        self.sim, self.g = sim, sim.server.g
        self.obs = sim.server.rt.eval("require('RadioSurvivor/RS_Observations')")
        self.cfg = sim.server.rt.eval("require('RadioSurvivor/RS_Config')").Observations
        ids = [sim.server.g.RS_CarnetServer.ensure(2001).id]
        for i in range(1, npcs):
            sim.server.g.spawn(3000 + i, 'Survivor %d' % i, False, 'k%d' % i)
            ids.append(sim.server.g.RS_CarnetServer.ensure(3000 + i).id)
        return ids

    def t(self, value):
        return self.sim.server.rt.table_from(value)

    def record(self, npc, fact='assault_seen', subject='character-1', day=3, place='Gas station', **extra):
        key, reason = self.obs.record(npc, self.t(dict(fact=fact, subject=subject, day=day, place=place, **extra)))
        return key, reason

    def listed(self, npc):
        return [convert(o) for o in lua_list(self.obs.list(npc))]

    def chain(self, npc, key):
        for o in self.listed(npc):
            if o['key'] == key:
                return lua_chain(o['chain'])
        return None

    def test_closed_list_and_validation(self):
        a, = self.world()
        self.assertEqual(list(lua_list(self.cfg.facts)), list(protocol.OBS_FACTS))
        self.assertEqual((self.cfg.maxPerNpc, self.cfg.maxChain), (protocol.OBS_MAX, protocol.OBS_MAX_CHAIN))
        self.assertEqual(self.record('npc-unknown'), (None, 'fiche'))
        self.assertEqual(self.record(a, fact='rumour'), (None, 'fact'))
        self.assertEqual(self.record(a, subject='bad id!'), (None, 'subject'))
        self.assertEqual(self.record(a, subject='x' * 49), (None, 'subject'))
        self.assertEqual(self.record(a, day=-1), (None, 'day'))
        self.assertEqual(self.record(a, day=2.5), (None, 'day'))
        # Aucune coordonnée exacte : trois chiffres de suite refusés, la maille approximative est admise.
        self.assertEqual(self.record(a, place='10234,9876'), (None, 'place'))
        self.assertEqual(self.record(a, place=' <> '), (None, 'place'))
        self.assertEqual(self.obs.area(10234, 9876), 'area-39-38')
        self.assertEqual(self.record(a, place=self.obs.area(10234, 9876))[1], 'ok')
        self.assertEqual(self.record(a, source='heard_from:' + a), (None, 'source'))
        self.assertEqual(self.record(a, source='overheard'), (None, 'source'))
        self.assertEqual(self.record(a, x=1), (None, 'bad_obs'))
        key, reason = self.record(a, place='  Gas   <b>station</b>  ' + 'y' * 40)
        self.assertEqual(reason, 'ok')
        place = self.listed(a)[-1]['place']
        self.assertLessEqual(len(place), self.cfg.placeChars)
        self.assertNotIn('<', place)
        self.assertEqual(key, 'assault_seen|character-1|3|' + place.lower())

    def test_bounds_per_npc_and_duplicates(self):
        a, = self.world()
        first, reason = self.record(a, place='Gas station')
        self.assertEqual(reason, 'ok')
        self.assertIsNotNone(self.sim.state().observations, 'not in the private state')
        # Même fait, sujet, jour et lieu (casse, espaces) : stockée une fois.
        self.assertEqual(self.record(a, place='GAS  station'), (first, 'duplicate'))
        self.assertEqual(len(self.listed(a)), 1)
        for day in range(4, 4 + self.cfg.maxPerNpc + 1):
            self.assertEqual(self.record(a, fact='weather', subject='storm', day=day, place='Riverside')[1], 'ok')
        items = self.listed(a)
        self.assertEqual(len(items), self.cfg.maxPerNpc)
        self.assertNotIn(first, [o['key'] for o in items], 'oldest observation kept')
        self.assertEqual(items[0]['day'], 5)
        self.assertEqual(items[-1]['day'], 4 + self.cfg.maxPerNpc)

    def test_transmitted_twice_stored_once_with_chain_and_no_loop(self):
        a, b, c, d, e, x = self.world(npcs=6)
        key, _ = self.record(a)
        self.assertEqual(self.obs.transmit(a, b, key), (key, 'ok'))
        self.assertEqual(self.chain(b, key), ['seen', 'heard_from:' + a])
        # Deuxième récit du même PNJ, puis d'un autre témoin : une seule entrée, chaîne d'origine conservée.
        self.assertEqual(self.obs.transmit(a, b, key), (key, 'duplicate'))
        self.assertEqual(self.record(x)[1], 'ok')
        self.assertEqual(self.obs.transmit(x, b, key), (key, 'duplicate'))
        self.assertEqual(len(self.listed(b)), 1)
        self.assertEqual(self.chain(b, key), ['seen', 'heard_from:' + a])
        self.assertEqual(self.listed(b)[0]['source'], 'heard_from:' + a)
        # Retour au premier : refusé, même après l'éviction de son entrée (aucun réapprentissage de soi).
        self.assertEqual(self.obs.transmit(b, a, key), (None, 'loop'))
        for day in range(10, 10 + self.cfg.maxPerNpc):
            self.record(a, fact='helicopter', subject='sky', day=day, place='March Ridge')
        self.assertNotIn(key, [o['key'] for o in self.listed(a)])
        self.assertEqual(self.obs.transmit(b, a, key), (None, 'loop'))
        self.assertNotIn(key, [o['key'] for o in self.listed(a)])
        # Chaîne bornée : 4 éléments au plus, une chaîne pleine n'est plus racontée.
        self.assertEqual(self.obs.transmit(b, c, key), (key, 'ok'))
        self.assertEqual(self.obs.transmit(c, d, key), (key, 'ok'))
        self.assertEqual(self.chain(d, key), ['seen', 'heard_from:' + a, 'heard_from:' + b, 'heard_from:' + c])
        self.assertEqual(self.obs.transmit(d, e, key), (None, 'chain'))
        self.assertEqual(self.obs.transmit(d, b, key), (None, 'loop'))
        self.assertEqual(self.listed(e), [])
        self.assertEqual(self.obs.transmit(c, c, key), (None, 'self'))
        self.assertEqual(self.obs.transmit(c, e, 'nope'), (None, 'unknown'))
        # Le destinataire voit lui-même la scène : l'observation directe remplace le ouï-dire, sans doublon.
        self.assertEqual(self.record(d), (key, 'upgraded'))
        self.assertEqual(self.chain(d, key), ['seen'])
        self.assertEqual(len(self.listed(d)), 1)

    def test_tracked_npcs_bounded_and_purged(self):
        ids = self.world(npcs=4)
        saved = self.cfg.maxNpcs
        self.cfg.maxNpcs = 3
        try:
            for npc in ids:
                self.assertEqual(self.record(npc)[1], 'ok')
        finally:
            self.cfg.maxNpcs = saved
        self.assertEqual(count(self.sim.state().observations.npcs), 3)
        self.assertEqual(self.listed(ids[0]), [], 'least recently updated NPC kept')
        # Mort d'une fiche (événement du fournisseur) : son journal est oublié, ce qu'elle a raconté reste.
        key, _ = self.record(ids[1], fact='power_cut', subject='grid', day=7, place='Muldraugh')
        self.assertEqual(self.obs.transmit(ids[1], ids[2], key)[1], 'ok')
        body = [z for z in lua_list(self.g.ZOMBIES) if z.id == 3001][0]
        body.dead = True
        self.g.fire('OnZombieDead', body)
        self.assertIsNone(self.sim.state().observations.npcs[ids[1]])
        self.assertEqual(self.listed(ids[1]), [])
        self.assertIn(key, [o['key'] for o in self.listed(ids[2])])
        # Fiche retirée par le carnet (non contactée, sans corps) : journal purgé au passage du prune.
        self.g.ZOMBIES = self.sim.server.rt.table()
        self.sim.clock.offset += 3600001 + 60001
        self.sim.tick()
        self.assertIsNone(self.sim.state().npcs[ids[2]])
        self.assertEqual(count(self.sim.state().observations.npcs), 0)

    def test_private_state_persistence(self):
        a, = self.world('persist')
        key, _ = self.record(a, fact='mission_done', subject='first_aid_v1', day=2, place='Rosewood')
        self.assertTrue(self.sim.server.g.RS_CarnetServer.store.dirty)
        self.sim.server.g.fire('OnSave')
        restart = Simulation(self.sim.path, self.sim.clock, saved_players=self.sim.saved())
        obs = restart.server.rt.eval("require('RadioSurvivor/RS_Observations')")
        self.assertEqual([o.key for o in lua_list(obs.list(a))], [key])
        code = [line for line in SOURCE.read_text(encoding='utf-8').splitlines() if not line.lstrip().startswith('--')]
        source = '\n'.join(code)
        for forbidden in ('ModData', 'sendServerCommand', 'transmitModData'):
            self.assertNotIn(forbidden, source)

    def test_request_field_and_bridge_prompt(self):
        a, b = self.world('request', npcs=2)
        alice = self.sim.character('alice')
        self.sim.state().characters[alice].name = 'Alice Doe'
        self.sim.select('alice')
        self.sim.say('alice', '/say Bonjour')
        first = self.sim.server.g.RS_CarnetServer.pending[1]
        self.assertIsNone(first.observations, 'empty field sent')
        key, _ = self.record(b, fact='player_return', subject=alice, day=4, place='Gas station')
        self.assertEqual(self.obs.transmit(b, a, key)[1], 'ok')
        self.record(a, fact='helicopter', subject='sky', day=5, place=self.obs.area(10234, 9876))
        self.sim.server.g.RS_CarnetServer.pending = self.sim.server.rt.table()
        self.sim.clock.offset += 11000  # after the talk cooldown (server and client)
        self.sim.say('alice', '/say Du nouveau ?')
        req = self.sim.server.g.RS_CarnetServer.pending[1]
        self.assertEqual(req.kind, 'npc_talk')
        field = [convert(o) for o in lua_list(req.observations)]
        self.assertEqual(field, [
            {'fact': 'player_return', 'subject': alice, 'day': 4, 'place': 'Gas station', 'source': 'heard',
             'hops': 1, 'who': 'Alice Doe', 'teller': 'Survivor 1'},
            {'fact': 'helicopter', 'subject': 'sky', 'day': 5, 'place': 'area-39-38', 'source': 'seen', 'hops': 0},
        ])
        # Relu par le pont depuis le vrai fichier d'échange (RSV2), puis présenté comme souvenirs non vérifiés.
        session, records = bridge_module.read_requests(self.sim.path / 'requests.txt')
        unpacked = [protocol.unpack_request(r) for r in records if r.get('id') == req.id][0]
        self.assertEqual(unpacked['observations'], field)
        system = protocol.prompt(unpacked, [])[0]['content']
        section = protocol.observations_prompt(unpacked)
        self.assertTrue(system.endswith(section) and section)
        self.assertIn('unverified memories', section)
        self.assertIn('never proof that anything happened', section)
        self.assertIn('- day 4, Gas station: a known player came back; subject %s (Alice Doe); told by Survivor 1.'
                      % alice, section)
        self.assertIn('- day 5, area-39-38: a helicopter passing over; subject sky; you saw it yourself.', section)
        self.assertNotIn('npc-', section)
        self.assertNotIn('10234', section)
        self.assertNotIn('observations', system.split('Authoritative context: ', 1)[1].split('Your own', 1)[0])
        # Sans observation : prompt identique à celui d'avant E08-T02.
        bare = dict(unpacked)
        del bare['observations']
        self.assertEqual(protocol.prompt(bare, [])[0]['content'], system[:-len(section)])
        # Enrichissement : jamais d'observations.
        npc = self.sim.state().npcs[a]
        npc.enrichState = 'needed'
        self.sim.server.g.RS_CarnetServer.pending = self.sim.server.rt.table()
        self.sim.clock.offset += 5001
        self.sim.tick()
        enrich = [r for r in self.sim.server.g.RS_CarnetServer.pending.values() if r.kind == 'npc_enrich']
        self.assertTrue(enrich)
        self.assertIsNone(enrich[0].observations)

    def test_bridge_rejects_out_of_contract_field(self):
        base = {'fact': 'weather', 'subject': 'storm', 'day': 1, 'place': 'Riverside', 'source': 'seen', 'hops': 0}
        self.assertEqual(protocol.observations({1: base}), [base])
        bad = [
            {},
            {i: base for i in range(1, protocol.OBS_MAX + 2)},
            {2: base},
            {1: dict(base, fact='rumour')},
            {1: dict(base, subject='npc id')},
            {1: dict(base, day=-1)},
            {1: dict(base, place='12345,6789')},
            {1: dict(base, source='heard')},
            {1: dict(base, hops=1)},
            {1: dict(base, teller='Paul')},
            {1: dict(base, source='heard', hops=protocol.OBS_MAX_CHAIN + 1, teller='Paul')},
            {1: dict(base, x=1)},
        ]
        for field in bad:
            with self.assertRaises(ValueError, msg=field):
                protocol.observations(field)
        heard = dict(base, source='heard', hops=2, teller='Paul <b>')
        self.assertEqual(protocol.observations({1: heard})[0]['teller'], 'Paul b')
        self.assertIn('told by Paul b, retold 2 times.',
                      protocol.observations_prompt({'observations': protocol.observations({1: heard})}))


# Game clock of the server (GameTime.getWorldAgeHours, IsoWorld age in hours) for the E08-T07 triggers; the protocol
# stubs have no world age (the triggers then record nothing, as without a clock).
GAME_CLOCK = r'''
WORLD_HOURS = 0
local baseGameTime = getGameTime
getGameTime = function()
    local gt = baseGameTime()
    gt.getWorldAgeHours = function() return WORLD_HOURS end
    return gt
end
function BODY(id) for _, z in ipairs(ZOMBIES) do if z.id == id then return z end end end
'''


class TriggerTests(unittest.TestCase):
    """E08-T07 : déclencheurs du carnet (retour d'un personnage connu, mission réussie) et de Living Knox (mort d'un
    membre, agression vue) sur le vrai serveur du carnet, deux clients ; Living Knox réduit à son espace de noms
    (LK_Core : listen/publish) et au faux fournisseur conforme de test_carnet (groupe par PNJ). Les publications du
    moteur lui-même sont couvertes dans test_lk_core, test_lk_groups, test_lk_bodies et test_lk_hostility."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-trig-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, name='triggers'):
        sim = Simulation(self.path / name)
        sim.server.rt.execute(GAME_CLOCK)
        sim.server.g.WORLD_HOURS = 48
        sim.server.load('shared/LivingKnox/LK_Core.lua')
        sim.add_client('alice')
        sim.add_client('bob')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        self.g.NPCS[2001].group = 'grp-1'
        self.fid = self.server.ensure(2001).id
        self.tick()
        return sim

    def tick(self):
        self.sim.clock.offset += 1001
        self.sim.tick()

    def npc(self, nid, group='grp-1', x=12, fiche=True, visible=True):
        z = self.g.spawn(nid, 'Survivor %d' % nid, False, 'k%d' % nid)
        z.x, z.visible = x, visible
        self.g.NPCS[nid].group = group
        return self.server.ensure(nid).id if fiche else None

    def listed(self, fid):
        return [{k: o[k] for k in ('fact', 'subject', 'day', 'place', 'source')}
                for o in (convert(o) for o in lua_list(self.obs.list(fid)))]

    def facts(self, fid, fact):
        return [o for o in self.listed(fid) if o['fact'] == fact]

    def publish(self, name, lua_info):
        self.rt.execute(f'LivingKnox.publish("{name}", {lua_info})')

    def assert_no_coordinates(self):
        for fid in self.sim.state().observations.npcs.keys():
            for o in self.listed(fid):
                self.assertRegex(o['place'], r'^(area-\d{1,2}-\d{1,2}|unknown place)$')

    def test_player_return_once_per_known_character_after_a_day(self):
        self.world()
        alice, bob = self.sim.character('alice'), self.sim.character('bob')
        self.sim.select('alice')  # alice becomes known to the fiche; bob, also in range, never talked to it
        far = self.npc(3001, x=300)
        self.rt.execute(f'RS_CarnetServer.store.data.characters["{alice}"].contacts["{far}"] = '
                        '{history = {}, note = "", trust = "Unassessed", trend = "Stable"}')
        fiches = count(self.sim.state().npcs)
        self.tick()
        contact = self.sim.state().characters[alice].contacts[self.fid]
        self.assertEqual(contact.nearHour, 48)
        self.assertEqual(self.listed(self.fid), [], 'the first meeting is not a return')
        alice_body = self.g.PLAYERS['alice']

        def away_then_back(hours):
            alice_body.x = 500
            self.tick()
            self.g.WORLD_HOURS += hours
            self.tick()
            alice_body.x = 10
            self.tick()
            self.tick()

        away_then_back(23)  # less than a game day out of hearing range: no return
        self.assertEqual(self.listed(self.fid), [])
        self.assertEqual(contact.nearHour, 71)
        away_then_back(24)
        self.assertEqual(self.listed(self.fid), [
            {'fact': 'player_return', 'subject': alice, 'day': 4, 'place': 'area-0-0', 'source': 'seen'}])
        # Staying in range does not repeat it; bob (in range, unknown to the fiche) and the far fiche never see it.
        for _ in range(30):  # the poll runs every second: in range, the last hour follows the clock
            self.g.WORLD_HOURS += 1
            self.tick()
        self.assertEqual(len(self.listed(self.fid)), 1)
        self.assertIsNone(self.sim.state().characters[bob].contacts[self.fid])
        self.assertEqual(self.listed(far), [])
        # Reconnection after more than a day: one more return, on the new day.
        del self.g.PLAYERS['alice']
        self.tick()
        self.assertNotIn(alice, list(self.server.bound.values()))
        self.g.WORLD_HOURS += 26
        self.sim.add_client('alice')
        self.assertEqual(self.sim.character('alice'), alice)
        self.tick()
        self.tick()
        self.assertEqual([(o['fact'], o['day']) for o in self.listed(self.fid)],
                         [('player_return', 4), ('player_return', 7)])
        self.assertEqual(count(self.sim.state().npcs), fiches, 'a trigger created a fiche')
        self.assert_no_coordinates()

    def test_mission_done_at_the_requester_for_each_participant(self):
        self.world()
        sim = self.sim
        alice, bob = sim.character('alice'), sim.character('bob')
        sim.select('alice')
        other = self.npc(3001)
        state = sim.state()
        M = self.rt.eval("require('RadioSurvivor/RS_Missions')")
        m = M.create(state, state.npcs[self.fid], alice, None)
        state.characters[alice].knownMissions[m.id] = True
        sim.request_mission('alice', 'accept')
        sim.request_mission('alice', 'invite', character=bob)
        sim.request_mission('bob', 'accept')
        self.assertEqual(self.listed(self.fid), [])
        sim.confirm('alice', sim.quote('alice', sim.items('alice', *(['Base.Bandage'] * 6))))
        self.assertEqual(sim.mission().state, 'success')
        done = self.facts(self.fid, 'mission_done')
        self.assertEqual(sorted(o['subject'] for o in done), sorted([alice, bob]))
        self.assertEqual({(o['day'], o['place'], o['source']) for o in done}, {(3, 'area-0-0', 'seen')})
        self.assertEqual(self.listed(other), [])
        # A failed mission is not "done"; a radio voice requester has no fiche (nothing recorded, nothing created).
        m2 = M.create(state, state.npcs[self.fid], alice, None)
        self.assertTrue(M.accept(state, m2, alice, 'Alice'))
        self.assertTrue(M.finish(state, m2, 'failed'))
        self.assertEqual(len(self.facts(self.fid, 'mission_done')), 2)
        fiches = count(state.npcs)
        self.rt.execute(f'require("RadioSurvivor/RS_ObservationTriggers").missionFinished(RS_CarnetServer.store.data, '
                        f'{{npc = "voice:walt:{alice}", participants = {{["{alice}"] = {{name = "Alice"}}}}}}, "success")')
        self.assertEqual(count(state.npcs), fiches)
        self.assertIsNone(state.observations.npcs[f'voice:walt:{alice}'])

    def test_group_death_in_sight_of_group_members_only(self):
        self.world()
        near = self.npc(3001)                       # same group, in sight
        far = self.npc(3002, x=200)                 # same group, too far
        stranger = self.npc(3003, group='grp-2')    # other group, in sight
        blind = self.npc(3004, visible=False)       # same group, no line of sight
        self.npc(3005, fiche=False)                 # same group, never contacted: no fiche
        dead = self.npc(3010)
        fiches = count(self.sim.state().npcs)
        self.tick()  # bodies mapped to their fiches
        self.rt.execute('local z = BODY(3010); z.dead = true')
        info = ('{group = "grp-1", member = "m-9", npc = 3010, day = 5, offscreen = false, body = BODY(3010)}')
        self.publish('memberDied', info)
        self.publish('memberDied', info)  # same fact published twice: stored once per witness
        expected = [{'fact': 'group_death', 'subject': dead, 'day': 5, 'place': 'area-0-0', 'source': 'seen'}]
        self.assertEqual(self.listed(near), expected)
        self.assertEqual(self.listed(self.fid), expected)
        for fid in (far, stranger, blind, dead):
            self.assertEqual(self.listed(fid), [], fid)
        self.assertEqual(count(self.sim.state().npcs), fiches)
        # The notebook name of the dead fiche reaches the prompt field; never an NPC id.
        field = [convert(o) for o in lua_list(self.obs.field(near))]
        self.assertEqual(field[0]['who'], 'Survivor 3010')
        self.assert_no_coordinates()

    def test_offscreen_group_death_at_the_home_members(self):
        self.world()
        home_a, home_b = self.npc(3001), self.npc(3002, x=900)
        absent = self.npc(3003)
        fiches = count(self.sim.state().npcs)
        self.tick()
        self.publish('memberDied', '{group = "grp-1", member = "m-4", day = 6, offscreen = true, '
                                   'witnesses = {3001, 3002, 9999}, x = 10234, y = 9876}')
        expected = [{'fact': 'group_death', 'subject': 'grp-1-m-4', 'day': 6, 'place': 'area-39-38', 'source': 'seen'}]
        self.assertEqual(self.listed(home_a), expected)
        self.assertEqual(self.listed(home_b), expected)
        self.assertEqual(self.listed(absent), [])
        self.assertEqual(self.listed(self.fid), [])
        self.assertEqual(count(self.sim.state().npcs), fiches, 'witness 9999 got a fiche')
        # Group without a home: a place label without coordinates.
        self.publish('memberDied', '{group = "grp-1", member = "m-5", day = 6, offscreen = true, witnesses = {3001}}')
        self.assertEqual(self.facts(home_a, 'group_death')[-1]['place'], 'unknown place')
        self.assert_no_coordinates()

    def test_assault_seen_by_the_named_witnesses(self):
        self.world()
        alice = self.sim.character('alice')
        seen_a, seen_b = self.npc(3001), self.npc(3003, group='grp-2', x=40)
        other = self.npc(3002)
        self.tick()
        info = f'{{group = "grp-1", player = "{alice}", fact = "shot", day = 7, witnesses = {{3001, 3003, 9999}}}}'
        self.publish('assaultSeen', info)
        self.publish('assaultSeen', info)
        # One place for every witness (first loaded witness body), so that the key is shared when it is retold.
        expected = [{'fact': 'assault_seen', 'subject': alice, 'day': 7, 'place': 'area-0-0', 'source': 'seen'}]
        self.assertEqual(self.listed(seen_a), expected)
        self.assertEqual(self.listed(seen_b), expected)
        self.assertEqual(self.listed(other), [])
        self.assertEqual(self.listed(self.fid), [])
        key = 'assault_seen|%s|7|area-0-0' % alice
        self.assertEqual(self.obs.transmit(seen_a, seen_b, key), (key, 'duplicate'))
        self.assertEqual(len(self.listed(seen_b)), 1)
        # Not an assault, or no named witness: nothing.
        self.publish('assaultSeen', f'{{group = "grp-1", player = "{alice}", fact = "theft", day = 8, '
                                    'witnesses = {3002}}')
        self.publish('assaultSeen', f'{{group = "grp-1", player = "{alice}", fact = "kill", day = 8}}')
        self.assertEqual(self.listed(other), [])
        # Scene position given by the engine wins over the witness bodies.
        self.publish('assaultSeen', f'{{group = "grp-1", player = "{alice}", fact = "kill", day = 8, '
                                    'witnesses = {3002}, x = 10234, y = 9876}')
        self.assertEqual(self.listed(other)[0]['place'], 'area-39-38')
        self.assert_no_coordinates()

    def test_living_knox_npcs_with_the_real_engine(self):
        """E17-T03 : fiches de PNJ Living Knox (fournisseur RS_LivingKnox, identifiant lk-<n>, groupe grp-<n>) et faits
        publiés par le vrai moteur : agression vue (LK_Hostility.record avec témoins) et mort hors écran
        (LK_Groups.markDead : témoins = membres présents au foyer, lieu = maille du foyer)."""
        sim = Simulation(self.path / 'lk', living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        alice = sim.character('alice')
        server = self.g.RS_CarnetServer
        mate = server.ensure(self.g.LK_MATE).id
        raider = server.ensure(self.g.LK_RAIDER).id
        self.assertEqual(sim.state().npcs[mate].clan, self.g.LK_GROUP)
        self.tick()
        self.rt.execute(f'assert(LivingKnox.Hostility.record(LK_GROUP, "{alice}", "hit", '
                        '{witnessed = true, witnesses = {LK_MATE}, x = 10234, y = 9876}))')
        self.assertEqual(self.listed(mate), [
            {'fact': 'assault_seen', 'subject': alice, 'day': 3, 'place': 'area-39-38', 'source': 'seen'}])
        self.assertEqual(self.listed(raider), [])
        # Leader dead off screen (no fiche): its group mate at home remembers it, at the area of the home.
        self.rt.execute('local gid, mid = LivingKnox.Groups.findNpc(LK_LEADER); '
                        'assert(LivingKnox.Groups.markDead(gid, mid, 3))')
        self.assertEqual(self.facts(mate, 'group_death'), [
            {'fact': 'group_death', 'subject': self.g.LK_GROUP + '-m-1', 'day': 3, 'place': 'area-41-36',
             'source': 'seen'}])
        self.assertEqual(self.listed(raider), [])
        self.assert_no_coordinates()

    def test_engine_facts_before_the_namespace_and_listener_errors(self):
        """Living Knox loaded after the notebook: subscribed at the next poll; a broken fact never stops the
        engine (pcall of LK_Core.publish)."""
        sim = Simulation(self.path / 'late')
        sim.server.rt.execute(GAME_CLOCK)
        trig = sim.server.rt.eval("require('RadioSurvivor/RS_ObservationTriggers')")
        self.assertFalse(trig.linked)
        sim.server.load('shared/LivingKnox/LK_Core.lua')
        sim.clock.offset += 1001
        sim.tick()
        self.assertTrue(trig.linked)
        self.assertEqual(sim.server.rt.eval('#LivingKnox.listeners.memberDied'), 1)
        sim.server.rt.execute('LivingKnox.publish("memberDied", "bad")')
        sim.server.rt.execute('LivingKnox.publish("assaultSeen", {fact = "hit", witnesses = 3})')
        self.assertEqual(count(sim.state().observations.npcs) if sim.state().observations else 0, 0)


# E08-T08 doubles of the Java world (signatures checked in the decompiled 42.21.0 Java): ClimateManager
# (getIsThunderStorming = running period and (thunder storm or tropical storm), ClimateManager.java:653-655; WeatherPeriod
# flags), SandboxOptions.doesPowerGridExist (SandboxOptions.java:1226-1231), optional provider presence.
WORLD_STUBS = r'''
CLIMATE = {running = false, thunder = false, tropical = false, blizzard = false}
local period = {
    isRunning = function() return CLIMATE.running end,
    isThunderStorm = function() return CLIMATE.thunder end,
    isTropicalStorm = function() return CLIMATE.tropical end,
    isBlizzard = function() return CLIMATE.blizzard end,
}
getClimateManager = function() return {
    getWeatherPeriod = function() return period end,
    getIsThunderStorming = function() return CLIMATE.running and (CLIMATE.thunder or CLIMATE.tropical) end,
} end
GRID = true
local baseOptions = getSandboxOptions
getSandboxOptions = function()
    local options = baseOptions and baseOptions() or {}
    options.doesPowerGridExist = function() return GRID end
    -- SandboxOptions.getOptionByName: nil for an unknown option (Living Knox then reads SandboxVars).
    options.getOptionByName = options.getOptionByName or function() return nil end
    return options
end
PRESENCE = {}
if FAKE_PROVIDER then FAKE_PROVIDER.presence = function(id) return PRESENCE[id] end end
function UNLOAD(id)
    for i, z in ipairs(ZOMBIES) do if z.id == id then table.remove(ZOMBIES, i); return end end
end
'''


class WorldTriggerTests(unittest.TestCase):
    """E08-T08 : déclencheurs du monde (orage, coupure du réseau, passage de l'hélicoptère vanilla) sur le vrai serveur
    du carnet ; météo et réseau par des doublures de ClimateManager / SandboxOptions, hélicoptère par sa signature de
    son de monde (OnWorldSound). Ne prouve pas le déclenchement réel de EveryHours ni d'OnWorldSound par le Java."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-world-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, name='world'):
        sim = Simulation(self.path / name)
        sim.server.rt.execute(GAME_CLOCK)
        sim.server.rt.execute(WORLD_STUBS)
        sim.server.g.WORLD_HOURS = 47
        sim.add_client('alice')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        self.cfg = self.rt.eval("require('RadioSurvivor/RS_Config')").Observations
        self.fid = self.server.ensure(2001).id
        self.tick()
        return sim

    def tick(self):
        self.sim.clock.offset += 1001
        self.sim.tick()

    def npc(self, nid, x=12, loaded=True):
        z = self.g.spawn(nid, 'Survivor %d' % nid, False, 'k%d' % nid)
        z.x = x
        fid = self.server.ensure(nid).id
        if not loaded:
            self.g.UNLOAD(nid)
        self.tick()
        return fid

    def hour(self, n=1):
        for _ in range(n):
            self.g.WORLD_HOURS += 1
            self.g.fire('EveryHours')

    def listed(self, fid, fact=None):
        return [{k: o[k] for k in ('fact', 'subject', 'day', 'place', 'source')}
                for o in (convert(o) for o in lua_list(self.obs.list(fid))) if fact is None or o['fact'] == fact]

    def sound(self, x, y, z=0, radius=500, volume=500, source=None):
        self.sim.clock.offset += self.cfg.helicopterEveryMs + 1
        self.g.fire('OnWorldSound', x, y, z, radius, volume, source)

    def test_storm_once_per_present_fiche_and_never_while_paused(self):
        self.world()
        other = self.npc(3001)
        away = self.npc(3002, loaded=False)
        self.g.PRESENCE[3002] = self.rt.table_from({'away': True})
        fiches = count(self.sim.state().npcs)
        self.g.CLIMATE.running, self.g.CLIMATE.thunder = True, True
        # Empty server in pause: the hour never changes, EveryHours never fires, the notebook poll records nothing.
        for _ in range(5):
            self.tick()
        self.assertEqual(self.listed(self.fid), [])
        # A storm across midnight: it starts at hour 47 (day 2) and goes on at hours 48 to 50 (day 3).
        self.g.WORLD_HOURS = 46
        self.hour(4)  # 47 (day 2), 48, 49, 50 (day 3)
        storm = [{'fact': 'weather', 'subject': 'storm', 'day': 2, 'place': 'everywhere', 'source': 'seen'}]
        self.assertEqual(self.listed(self.fid), storm)
        self.assertEqual(self.listed(other), storm)
        self.assertEqual(self.listed(away), [], 'a member on an expedition saw the storm at home')
        # Back from the expedition while the storm goes on: the same episode, the same key.
        self.g.PRESENCE[3002] = self.rt.table_from({'away': False})
        self.hour()
        self.assertEqual(self.listed(away), storm)
        key = 'weather|storm|2|everywhere'
        self.assertEqual(self.obs.transmit(self.fid, other, key), (key, 'duplicate'))
        # End of the period, then a tropical storm and a blizzard: one observation per episode.
        self.g.CLIMATE.running = False
        self.hour()
        self.g.CLIMATE.running, self.g.CLIMATE.tropical = True, True
        self.hour(2)
        self.g.CLIMATE.thunder = self.g.CLIMATE.tropical = False
        self.g.CLIMATE.blizzard = True
        self.hour(2)
        self.g.CLIMATE.running = False
        self.hour()
        self.assertEqual([(o['subject'], o['day']) for o in self.listed(self.fid)],
                         [('storm', 2), ('tropical_storm', 3), ('blizzard', 3)])
        self.assertEqual(count(self.sim.state().npcs), fiches, 'a trigger created a fiche')

    def test_power_cut_once_when_the_grid_goes_down(self):
        self.world()
        other = self.npc(3001)
        self.hour(2)
        self.assertEqual(self.listed(self.fid), [])
        self.g.GRID = False
        self.hour()
        cut = [{'fact': 'power_cut', 'subject': 'power', 'day': 3, 'place': 'everywhere', 'source': 'seen'}]
        self.assertEqual(self.listed(self.fid), cut)
        self.assertEqual(self.listed(other), cut)
        # Power restored by an admin then cut again, days later: still one cut.
        self.g.GRID = True
        self.hour(30)
        self.g.GRID = False
        self.hour()
        self.assertEqual(self.listed(self.fid), cut)
        self.assertEqual(self.listed(other), cut)
        # The episode state lives in the private state and survives a restart.
        self.g.fire('OnSave')
        restart = Simulation(self.sim.path, self.sim.clock, saved_players=self.sim.saved())
        self.assertEqual(restart.state().worldEvents.powerCut, 3)

    def test_no_power_cut_without_a_grid_seen_first(self):
        self.world()
        self.g.GRID = False
        self.hour(3)
        self.assertEqual(self.listed(self.fid), [])
        self.assertIsNone(self.sim.state().worldEvents.powerCut)

    def test_helicopter_heard_from_its_world_sound(self):
        self.world()
        far = self.npc(3001, x=900)                     # loaded body 888 tiles away from the first sound
        home = self.npc(3002, loaded=False)             # no body, home in range
        self.g.PRESENCE[3002] = self.rt.table_from({'away': False, 'x': 300, 'y': 10})
        unknown = self.npc(3003, loaded=False)          # no body, home unknown: cannot have heard it
        away = self.npc(3004, loaded=False)             # home in range, on an expedition
        self.g.PRESENCE[3004] = self.rt.table_from({'away': True, 'x': 20, 'y': 10})
        fiches = count(self.sim.state().npcs)
        # Other world sounds: a player (source), another radius or volume, another floor.
        self.sound(12, 10, source=self.g.PLAYERS['alice'])
        self.sound(12, 10, radius=600, volume=600)
        self.sound(12, 10, radius=500, volume=20)
        self.sound(12, 10, z=1)
        self.assertEqual(count(self.sim.state().observations.npcs) if self.sim.state().observations else 0, 0)
        self.sound(12, 10)
        heard = [{'fact': 'helicopter', 'subject': 'helicopter', 'day': 2, 'place': 'area-0-0', 'source': 'seen'}]
        self.assertEqual(self.listed(self.fid), heard)
        self.assertEqual(self.listed(home), heard)
        for fid in (far, unknown, away):
            self.assertEqual(self.listed(fid), [], fid)
        # Same passage, later sounds: one observation per fiche; the far body hears it when it flies over it
        # (same key: day and area of the first sound). A sound inside the throttle delay is not handled.
        self.g.fire('OnWorldSound', 880, 10, 0, 500, 500, None)
        self.assertEqual(self.listed(far), [])
        self.sound(880, 10)
        self.assertEqual(self.listed(far), heard)
        self.g.WORLD_HOURS += 1
        self.sound(500, 10)
        self.assertEqual(len(self.listed(self.fid)), 1)
        self.assertEqual(len(self.listed(far)), 1)
        # Next passage, more than helicopterGapHours later: a new episode, at the area of its first sound.
        self.g.WORLD_HOURS += self.cfg.helicopterGapHours + 1
        self.sound(900, 10)
        self.assertEqual(self.listed(far)[-1], dict(heard[0], day=3, place='area-3-0'))
        self.assertEqual(len(self.listed(self.fid)), 1, 'out of range of the second passage')
        self.assertEqual(count(self.sim.state().npcs), fiches, 'a trigger created a fiche')
        for fid in self.sim.state().observations.npcs.keys():
            for o in self.listed(fid):
                self.assertRegex(o['place'], r'^(area-\d{1,2}-\d{1,2}|everywhere)$')

    def test_living_knox_presence_and_expedition(self):
        """Vrai fournisseur RS_LivingKnox : presence = équipe d'expédition et foyer du groupe (mémoire serveur)."""
        sim = Simulation(self.path / 'lk', living_knox=True)
        sim.server.rt.execute(GAME_CLOCK)
        sim.server.rt.execute(WORLD_STUBS)
        sim.server.rt.execute(LK_WORLD)
        sim.server.g.WORLD_HOURS = 60
        sim.add_client('alice')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        self.cfg = self.rt.eval("require('RadioSurvivor/RS_Config')").Observations
        server = self.g.RS_CarnetServer
        mate = server.ensure(self.g.LK_MATE).id
        loner = server.ensure(self.g.LK_LONER).id
        P = self.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        self.assertEqual(convert(P.presence(self.g.LK_MATE)), {'away': False, 'x': 10637, 'y': 9412})
        self.assertEqual(convert(P.presence(self.g.LK_LONER)), {'away': False})
        # Bodies out of the cell: the home of the group decides who hears the helicopter.
        self.g.ZOMBIES = self.rt.table()
        self.tick()
        self.sound(10600, 9400)
        heard = [{'fact': 'helicopter', 'subject': 'helicopter', 'day': 3, 'place': 'area-41-36', 'source': 'seen'}]
        self.assertEqual(self.listed(mate), heard)
        self.assertEqual(self.listed(loner), [], 'no home, no body: cannot have heard it')
        # The mate leaves on an expedition: a storm at home is not its observation.
        self.rt.execute('local G = LivingKnox.Groups; local _, mid = G.findNpc(LK_MATE); '
                        'G.state.data.groups[LK_GROUP].expedition = {place = "store", team = {mid}, departed = 60, '
                        'returns = 70}')
        self.assertTrue(P.presence(self.g.LK_MATE).away)
        self.g.CLIMATE.running, self.g.CLIMATE.thunder = True, True
        self.hour()
        self.assertEqual(self.listed(mate, 'weather'), [])
        self.assertEqual(self.listed(loner, 'weather'),
                         [{'fact': 'weather', 'subject': 'storm', 'day': 3, 'place': 'everywhere', 'source': 'seen'}])


def lua_chain(value):
    if isinstance(value, dict):
        return [value[i] for i in range(1, len(value) + 1)]
    return list(value or [])


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
