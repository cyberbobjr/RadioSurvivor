"""Radio des groupes équipés (E08-T06) : vrai RadioSurvivor_Server, vrai RS_Carnet_Server, vrai moteur Living Knox
(registres, API, corps), vrai fournisseur RS_LivingKnox.lua, deux clients avec le vrai client radio ; lupa, Lua 5.1.

    python tests/test_group_radio.py

Couvre : types de groupe au format 2 (homeRadio, profil radio) ; seul un groupe équipé devient une voix (fiche
engendrée, fréquence tirée dans sa plage, mémorisée pour la partie, sans conflit avec les autres voix) ; un appel sur
sa fréquence devient une demande npc_talk du chef dans la file du carnet (mêmes quotas que la proximité, aucune offre),
la réplique part sur la chaîne de la voix, l'appelant la garde dans son carnet ; une offre ou décision par radio est
refusée ; groupe décimé ou disparu : plus de voix ni de réponse ; aucune coordonnée dans la chaîne, le contexte ni les
répliques (suite de 4 chiffres masquée) ; pont muet : parasites et NoAnswer. Doublures du jeu : ne prouve pas l'API Java.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

from test_carnet import LK_WORLD, Simulation, convert
from test_protocol import ROOT, lua_list

sys.path.insert(0, str(ROOT / 'bridge'))
import npc_protocol as protocol  # noqa: E402
import radio_bridge as bridge_module  # noqa: E402

LOW, HIGH = 75000, 149800


class GroupRadioTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-group-radio-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def world(self, name='radio'):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server = self.g.RS_CarnetServer
        self.personas = self.rt.eval("require('RadioSurvivor/RS_Personas')")
        self.radio = self.rt.eval("require('RadioSurvivor/RS_GroupRadio')")
        self.sent = []
        deliver = self.g.sendServerCommand
        self.g.sendServerCommand = lambda *call: (self.sent.append(call), deliver(*call))[1]
        for user in ('alice', 'bob'):
            c = sim.add_client(user)
            c.rt.execute("Talk = require('RadioSurvivor/RS_RadioTalk'); "
                         "local Const = require('RadioSurvivor/RadioSurvivor_Const'); "
                         "Events.OnServerCommand.Add(function(m, cmd, a) if m == Const.MODULE then "
                         "Talk.handle(cmd, a or {}) end end); "
                         "local d = getPlayer().radio.device; function d:getPower() return 1 end")
        self.step()
        return sim

    def step(self, ms=1001):
        self.sim.clock.offset += ms
        self.sim.tick()  # OnTickEvenPaused: notebook poll, generated voices (no OnTick: the engine needs a cell)

    def khz(self, voice='grp_1'):
        served = lua_list(self.personas.served(voice))
        return served[0] if served else None

    def tune(self, user, khz):
        self.sim.clients[user].rt.eval(f'function() getPlayer().radio.device.channel = {khz} end')()
        self.g.PLAYERS[user].radio.device.channel = khz

    def talk(self, user, text, khz=None):
        khz = khz or self.khz()
        self.tune(user, khz)
        self.sim.clock.offset += 11000
        self.assertTrue(self.sim.clients[user].rt.eval(f"Talk.send(getPlayer(), getPlayer().radio, {json.dumps(text)})"))

    def radio_requests(self):
        return [r for r in lua_list(self.server.pending) if self.radio.owns(r.id)]

    def respond(self, req, text='We hear you. Stay safe out there.', intent='none', offer=''):
        body = {'version': 2, 'kind': 'npc_reply', 'id': req.id, 'world': req.world, 'run': req.run, 'npc': req.npc,
                'order': req.order, 'revision': req.revision, 'text': text, 'intent': intent, 'offer': offer}
        (self.sim.path / 'responses.txt').write_text(f"resp={req.id}\npayload={protocol.encode(body).hex()}\nend\n",
                                                     encoding='utf-8')
        self.step()
        self.step()

    def broadcasts(self):
        return [lua_list(b) for b in lua_list(self.g.BROADCASTS)]

    def commands(self, user, command):
        return [c for c in self.sent if len(c) == 4 and c[0].username == user and c[2] == command]

    # ------------------------------------------------------------------------------------------------ tests

    def test_group_types_format_two(self):
        sim = self.world('types')
        gt = self.rt.eval('LivingKnox.GroupTypes')
        settlers = gt.get('settlers')
        self.assertEqual((settlers.format, settlers.homeRadio), (2, True))
        # E08-T10 (decision of 2026-10-14): raiders hold a station at their camp too; neutrals stay without radio.
        raiders = gt.get('raiders')
        self.assertEqual((raiders.format, raiders.homeRadio), (2, True))
        self.assertIsNone(gt.get('neutrals').homeRadio)
        self.assertEqual(gt.get('neutrals').format, 1, 'format 1 files must stay readable')
        ok = self.rt.eval('''function()
            return LivingKnox.GroupTypes.register({ format = 2, id = "radiomen", nameKey = "K", size = { min = 1, max = 2 },
                hostility = 5, home = "forest", morale = 50, needs = { food = 1, medical = 1, ammo = 1 },
                roles = { scout = { weight = 1, behaviours = { "scout" } } },
                profiles = { { id = "op", role = "scout", weight = 1, radio = true } } })
        end''')()
        self.assertTrue(ok)
        self.assertTrue(self.rt.eval('LivingKnox.GroupTypes.get("radiomen").profiles[1].radio'))
        del sim

    def test_only_an_equipped_group_is_a_voice_with_a_drawn_frequency(self):
        self.world('voice')
        ids = lua_list(self.personas.ids())
        self.assertIn('grp_1', ids, 'settlers with a home station are not a voice')
        self.assertNotIn('grp_2', ids, 'raiders without a camp (no home, so no station) became a voice')
        khz = self.khz()
        self.assertTrue(LOW <= khz <= HIGH and khz % 200 == 0, khz)
        others = [k for v in ids if v != 'grp_1' for k in lua_list(self.personas.frequencies(v))]
        self.assertFalse([k for k in others if abs(k - khz) < 1000], 'too close to another voice')
        sheet = self.personas.get('grp_1')
        self.assertEqual((sheet.group, sheet.call_one_in, sheet.state), (self.g.LK_GROUP, 0, 'active'))
        # Drawn once for the game, remembered in the frequencies file of the game.
        memory = [p for p in (self.sim.path).rglob('frequencies-*.txt')]
        self.assertTrue(memory and any(f'grp_1 75000-149800 {khz}' in p.read_text() for p in memory))
        # No position anywhere in the channel nor the sheet: the channel id only names the voice.
        channel = self.personas.state().channels[khz]
        self.assertEqual(channel.id, 'grp_1')
        self.assertNotIn('10637', channel.uuid)
        self.assertNotIn('9412', channel.uuid)
        self.assertNotIn('10637', json.dumps(convert(sheet)))
        self.assertNotIn('9412', json.dumps(convert(sheet)))
        # A profile radio carried even away: a group of radio operators without home is a voice too.
        self.rt.execute('''
            LivingKnox.GroupTypes.register({ format = 2, id = "radiomen", nameKey = "K", size = { min = 1, max = 2 },
                hostility = 5, home = "forest", morale = 50, needs = { food = 1, medical = 1, ammo = 1 },
                roles = { scout = { weight = 1, behaviours = { "scout" } } },
                profiles = { { id = "op", role = "scout", weight = 1, radio = true } } })
            local g = assert(LivingKnox.Groups.create({ type = "radiomen", name = "Static", day = 3 }))
            LK_OPS = g.id
            LK_OP = lkNpc(20, g.id, 'scout')
            for _, m in pairs(LivingKnox.Groups.state.data.groups[g.id].members) do m.profile = 'op' end
        ''')
        self.step(31000)
        self.assertIn('grp_3', lua_list(self.personas.ids()))

    def test_call_goes_through_the_notebook_queue_and_airs_on_the_group_channel(self):
        self.world('call')
        alice = self.sim.character('alice')
        khz = self.khz()
        self.talk('alice', 'Anyone on this channel?')
        [req] = self.radio_requests()
        leader = self.server.find(self.g.LK_LEADER)
        self.assertEqual((req.kind, req.npc, req.character, req.text), ('npc_talk', leader.id, alice,
                                                                     'Anyone on this channel?'))
        self.assertEqual(convert(req.offers), {}, 'an offer was sent over the radio')
        ctx = convert(req.context)
        self.assertIn('radio', ctx)
        self.assertEqual(ctx['stage'], 'stranger')
        self.assertNotIn('group', ctx['group'], 'group name told to a stranger')
        text = json.dumps(convert(req), ensure_ascii=False)
        self.assertNotRegex(text, r'(?<![0-9])10637(?![0-9])')
        self.assertNotRegex(text, r'(?<![0-9])9412(?![0-9])')
        self.assertEqual(len(lua_list(self.server.times)), 1, 'call outside the common cap')
        # Nothing was sent to the radio bridge for this voice.
        parsed = bridge_module.parse_requests((self.sim.path / 'requests.txt').read_text(encoding='utf-8'))
        self.assertFalse([r for r in parsed[1] if r.get('voice') == 'grp_1'])
        # The payload written for the bridge is a valid npc_talk.
        [record] = [r for r in parsed[1] if r['id'] == req.id]
        value = protocol.unpack_request(record)
        self.assertEqual((value['kind'], value['channel']), ('npc_talk', 'say'))
        # Waiting: a second phrase is refused while the first one is unanswered.
        self.talk('alice', 'Hello?')
        self.assertEqual(len(self.radio_requests()), 1)
        before = len(self.broadcasts())
        self.respond(req, 'We hear you. Our camp is at 10637, 9412, come by.')
        aired = self.broadcasts()[before:]
        self.assertEqual(len(aired), 1, aired)
        self.assertEqual(aired[0][0], '<bzzt>')
        said = ' '.join(aired[0][1:])
        self.assertNotIn('10637', said)
        self.assertNotIn('9412', said)
        self.assertIn('We hear you.', said)
        self.assertTrue(self.commands('alice', 'done'), 'caller never told the answer is on the air')
        history = lua_list(self.sim.state().characters[alice].contacts[leader.id].history)
        self.assertEqual([(h.author, h.text[:12]) for h in history[-2:]],
                         [(self.sim.state().characters[alice].name, 'Anyone on th'), (leader.name, 'We hear you.')])
        self.assertNotIn('10637', history[-1].text)
        self.assertFalse(self.radio_requests())
        self.assertFalse([r for r in lua_list(self.server.pending) if r.kind == 'npc_talk'])
        del khz

    def test_decision_over_the_radio_refused(self):
        self.world('decide')
        self.talk('alice', 'Need any help?')
        [req] = self.radio_requests()
        before = len(self.broadcasts())
        self.respond(req, 'Bring us food.', intent='offer', offer='deliver_food')
        self.assertFalse(self.sim.state().missions and list(self.sim.state().missions.values()))
        aired = self.broadcasts()[before:]
        self.assertEqual(aired, [['<fzzt>', '<szzt>']], 'refused reply must give static only')
        rejected = self.commands('alice', 'rejected')
        self.assertTrue(rejected and convert(rejected[-1][3])['reason'] == 'NoAnswer')

    def test_decimated_or_gone_group_no_longer_answers(self):
        self.world('gone')
        khz = self.khz()
        self.assertTrue(khz)
        # Every member dead, then the group gone: no voice, no channel, silence on its frequency.
        self.rt.execute('''
            local G = LivingKnox.Groups
            local g = G.state.data.groups[LK_GROUP]
            for _, m in pairs(g.members) do m.alive = false end
            g.leader = nil
            G.applyGone(g, "wiped", 3, 72, 72)
        ''')
        self.step(31000)
        self.assertNotIn('grp_1', lua_list(self.personas.ids()))
        self.assertIsNone(self.personas.voiceAt(khz))
        self.talk('alice', 'Hello? Anyone left?', khz)
        self.assertFalse(self.radio_requests())
        self.assertFalse([r for r in lua_list(self.server.pending) if r.kind == 'npc_talk'])

    def test_everybody_away_from_the_home_station_no_answer(self):
        self.world('away')
        self.assertIn('grp_1', lua_list(self.personas.ids()))
        self.rt.execute('''
            local g = LivingKnox.Groups.state.data.groups[LK_GROUP]
            local team = {}
            for mid, m in pairs(g.members) do if m.alive then team[#team + 1] = mid end end
            g.expedition = { place = "town", team = team, departed = 1, returns = 99999 }
        ''')
        self.step(31000)
        self.assertNotIn('grp_1', lua_list(self.personas.ids()))

    def test_no_bridge_static_and_no_answer(self):
        self.world('mute')
        self.talk('alice', 'Come in?')
        [req] = self.radio_requests()
        before = len(self.broadcasts())
        self.sim.clock.offset += 200000
        self.step(); self.step()
        self.assertFalse(self.radio_requests())
        self.assertIn(['<fzzt>', '<szzt>'], self.broadcasts()[before:])
        self.assertTrue(self.commands('alice', 'rejected'))
        del req

    # E08-T10: raiders equipped like settlers (station at their camp), neutrals without radio, settlers unchanged.
    RAIDERS_CAMP = r'''
        local G = LivingKnox.Groups
        local r = assert(G.create({type = 'raiders', name = 'Wolves', home = {x = 11201, y = 8803, z = 0}, day = 3}))
        LK_CAMP = r.id
        LK_CAMP_BOSS = lkNpc(22, r.id, 'fighter', {leader = true})
        LK_CAMP_MATE = lkNpc(24, r.id, 'scout')
        local n = assert(G.create({type = 'neutrals', name = 'Drifters', home = {x = 11301, y = 8903, z = 0}, day = 3}))
        LK_NEUTRALS = n.id
        lkNpc(26, n.id, 'worker', {leader = true})
    '''

    def raiders_world(self, name):
        self.world(name)
        self.rt.execute(self.RAIDERS_CAMP)
        self.step(31000)
        return self.radio.voiceId(self.g.LK_CAMP), self.radio.voiceId(self.g.LK_NEUTRALS)

    def test_raiders_camp_is_a_voice_neutrals_are_none_settlers_unchanged(self):
        camp, neutrals = self.raiders_world('raiders')
        ids = lua_list(self.personas.ids())
        self.assertIn(camp, ids, 'raiders with a camp station are not a voice')
        self.assertNotIn(neutrals, ids, 'neutrals became a voice')
        self.assertIn('grp_1', ids, 'settlers lost their voice')
        khz = self.khz(camp)
        self.assertTrue(LOW <= khz <= HIGH and khz % 200 == 0, khz)
        self.assertFalse([k for v in ids if v != camp for k in lua_list(self.personas.frequencies(v))
                          if abs(k - khz) < 1000], 'too close to another voice')
        sheet = self.personas.get(camp)
        self.assertEqual((sheet.group, sheet.call_one_in, sheet.state), (self.g.LK_CAMP, 0, 'active'))
        channel = self.personas.state().channels[khz]
        self.assertEqual(channel.id, camp)
        for coord in ('11201', '8803'):
            self.assertNotIn(coord, channel.uuid)
            self.assertNotIn(coord, json.dumps(convert(sheet)))
        entry = [e for e in lua_list(self.rt.eval('require("RadioSurvivor/RS_NPCProvider").radios()'))
                 if e.ref == self.g.LK_CAMP]
        self.assertEqual(len(entry), 1)
        self.assertEqual(entry[0].speaker, self.g.LK_CAMP_BOSS, 'the raider leader does not answer')

    def test_raiders_answer_by_radio_without_place_then_silence_when_wiped(self):
        camp, _ = self.raiders_world('raiders-call')
        khz = self.khz(camp)
        self.talk('bob', 'Who is on this channel?', khz)
        [req] = self.radio_requests()
        boss = self.server.find(self.g.LK_CAMP_BOSS)
        self.assertEqual((req.kind, req.npc, req.text), ('npc_talk', boss.id, 'Who is on this channel?'))
        self.assertEqual(convert(req.offers), {}, 'an offer was sent over the radio')
        ctx = convert(req.context)
        self.assertIn('radio', ctx)
        self.assertEqual(ctx['stage'], 'stranger')
        text = json.dumps(convert(req), ensure_ascii=False)
        self.assertNotRegex(text, r'(?<![0-9])11201(?![0-9])')
        self.assertNotRegex(text, r'(?<![0-9])8803(?![0-9])')
        before = len(self.broadcasts())
        self.respond(req, 'Stay off this channel. Our camp is at 11201, 8803 and we see you.')
        aired = self.broadcasts()[before:]
        self.assertEqual(len(aired), 1, aired)
        said = ' '.join(aired[0][1:])
        self.assertNotIn('11201', said)
        self.assertNotIn('8803', said)
        self.assertIn('Stay off this channel.', said)
        # Wiped out: no voice, silence on its frequency.
        self.rt.execute('''
            local G = LivingKnox.Groups
            local g = G.state.data.groups[LK_CAMP]
            for _, m in pairs(g.members) do m.alive = false end
            g.leader = nil
            G.applyGone(g, "wiped", 3, 72, 72)
        ''')
        self.step(31000)
        self.assertNotIn(camp, lua_list(self.personas.ids()))
        self.assertIsNone(self.personas.voiceAt(khz))
        self.sim.clock.offset += 200000
        self.talk('bob', 'Anyone left?', khz)
        self.assertFalse(self.radio_requests())

    def test_raiders_decision_refused_then_silence_when_dispersed(self):
        camp, _ = self.raiders_world('raiders-gone')
        khz = self.khz(camp)
        # A decision over the radio is refused for raiders too: static only, NoAnswer.
        self.talk('bob', 'Want to trade?', khz)
        [req] = self.radio_requests()
        before = len(self.broadcasts())
        self.respond(req, 'Bring us food.', intent='offer', offer='deliver_food')
        self.assertFalse(self.sim.state().missions and list(self.sim.state().missions.values()))
        self.assertEqual(self.broadcasts()[before:], [['<fzzt>', '<szzt>']])
        rejected = self.commands('bob', 'rejected')
        self.assertTrue(rejected and convert(rejected[-1][3])['reason'] == 'NoAnswer')
        # Dispersed: no voice, nothing on its frequency.
        self.rt.execute('local G = LivingKnox.Groups; G.applyGone(G.state.data.groups[LK_CAMP], "dispersed", 3, 72, 72)')
        self.step(31000)
        self.assertNotIn(camp, lua_list(self.personas.ids()))
        self.assertIsNone(self.personas.voiceAt(khz))

    def test_suite_raiders_camp_is_a_voice_neutrals_none(self):
        # In-game test of rs.groupradio (E08-T10) run here on the simulated server: groups created and removed.
        self.world('suite')
        from test_carnet import TESTS_SHARED
        self.rt.execute(f'package.path = [[{TESTS_SHARED.as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('require "RST/RST"; RST.clock = function() return getTimestampMs() end')
        self.rt.execute('local base = getWorld; getWorld = function() local w = base() '
                        'if type(w) == "table" then w.getWorld = function() return "rstest-groupradio" end end '
                        'return w end')
        self.rt.execute(f'dofile([[{(TESTS_SHARED / "RST" / "suites" / "RS_GroupRadio.lua").as_posix()}]])')
        before = sorted(lua_list(self.personas.ids()))
        groups = len(lua_list(self.rt.eval('LivingKnox.Groups.list()')))
        report = self.rt.execute('return RST.runSync({ suite = "rs.groupradio", tags = "world", '
                                 'test = "a raiders camp is a voice" }, '
                                 '{ player = PLAYERS.alice })')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(sorted(lua_list(self.personas.ids())), before, 'test voices left behind')
        self.assertEqual(len(lua_list(self.rt.eval('LivingKnox.Groups.list()'))), groups, 'test groups left behind')

    def test_redact_and_lines(self):
        self.world('pure')
        self.assertEqual(self.radio.redact('at 10637,9412 since 1993 or 12'), 'at ...,... since ... or 12')
        long = 'word ' * 80
        lines = lua_list(self.radio.lines(long))
        self.assertTrue(all(len(x) <= 140 for x in lines))
        self.assertLessEqual(len(lines), 7)
        self.assertEqual(lua_list(self.radio.lines('a <b> c')), ['a b c'])


if __name__ == '__main__':
    unittest.main()
