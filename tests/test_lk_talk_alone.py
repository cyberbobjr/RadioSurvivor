"""Parole d'un PNJ avec Living Knox seul (E18-T18).

    python tests/test_lk_talk_alone.py

Banc lupa (Lua 5.1) sur le vrai moteur Living Knox (registres, API, corps, histoires), le vrai `LK_Talk.lua`, le vrai
`LK_TalkAlone.lua` et le vrai moteur des missions du commun, RadioSurvivor absent de la liste des mods : une phrase dite
près d'un PNJ part au pont avec le contexte du PNJ, la réponse revient en bulle et dans l'historique du commun ; le PNJ
connu propose une mission, acceptée par la parole, listée au journal du commun ; E18-T29 : les objets se livrent et le lot
se réclame par les gestes du journal du commun (commande « mission »), à côté du demandeur ; relecture après un
redémarrage. E18-T27 : un PNJ prend la parole de lui-même sur une observation récente et deux PNJ proches se racontent
ce qu'ils ont vu, sans RadioSurvivor.
Doublures : le faux pont du banc écrit la réponse ; ne prouve ni le réseau ni Java.
"""
from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

from test_carnet import (Clock, Game, LK_SERVER_LOAD, LK_SERVER_STUBS, LK_WORLD, STUBS, convert, protocol)

ROOT = Path(__file__).resolve().parents[1]
LK = ROOT / 'Contents/mods/batman_LivingKnox/42.21/media/lua'

MODS = r'''
getActivatedMods = function()
    local l = {'batman_RadioSurvivorCore', '\\batman_LivingKnox'}
    return {size = function() return #l end, get = function(_, i) return l[i + 1] end}
end
'''


class World:
    def __init__(self, path: Path, clock: Clock, new_world: bool):
        self.path, self.clock = path, clock
        path.mkdir(parents=True, exist_ok=True)
        self.server = Game('server', path, clock)
        self.g, self.rt = self.server.g, self.server.rt
        self.g.getTimestampMs = lambda: int(clock())
        self.rt.execute(STUBS)
        self.rt.execute(MODS)
        self.g.getWorld = lambda: self.rt.eval(
            "{getGameMode=function() return 'Multiplayer' end, getWorld=function() return 'alone' end}")
        self.rt.execute(LK_SERVER_STUBS)
        self.rt.execute(LK_SERVER_LOAD)
        self.sent = []
        self.g.sendServerCommand = lambda *call: self.sent.append(call)
        self.server.load('server/RadioSurvivorCore/RC_HistoryEvents.lua')
        self.g.fire('OnInitGlobalModData', new_world)
        self.alone = self.rt.eval('LivingKnox.TalkAlone')
        self.talk = self.rt.eval('LivingKnox.Talk')

    def player(self, name):
        p = self.g.enhance(self.g.makePlayer(name))
        p.isPlayer = True
        self.g.PLAYERS_ONLINE = None
        identity = self.rt.eval("require('RadioSurvivorCore/RC_Identity')")
        bound = identity.bind(p, None)
        return p, bound[0] if isinstance(bound, tuple) else bound

    def commands(self, name):
        return [c for c in self.sent if len(c) == 4 and c[2] == name]

    def say(self, player, text, **args):
        self.clock.offset += 11000
        table = self.rt.table_from({'text': text, 'channel': 'say', 'language': 'FR', **args})
        out = self.alone.say(player, table)
        return out[0] if isinstance(out, tuple) else out

    def answer(self, intent='none', offer=''):
        """Le faux pont répond à toutes les demandes en attente."""
        out, asked = '', []
        for r in self.talk.pending.values():
            asked.append(r)
            body = {'version': 2, 'kind': 'npc_reply', 'id': r.id, 'world': r.world, 'run': r.run, 'npc': r.npc,
                    'order': r.order, 'revision': r.revision, 'text': 'Noted.', 'intent': 'none', 'offer': ''}
            if r.kind == 'npc_talk':
                body['intent'], body['offer'] = intent, offer
            if r.kind == 'npc_enrich':
                body['background'] = 'A Knox survivor.'
            out += f"resp={r.id}\npayload={protocol.encode(body).hex()}\n"
        (self.path / 'responses.txt').write_text(out + 'end\n', encoding='utf-8')
        for _ in range(3):
            self.clock.offset += 1001
            self.rt.eval('function(a, n) a.pass(n) end')(self.alone, int(self.clock()))
        return asked


class AloneTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lk-alone-')
        self.path = Path(self.tmp.name) / 'w'
        self.clock = Clock()
        self.w = World(self.path, self.clock, True)
        self.w.rt.execute(LK_WORLD)
        self.p, self.character = self.w.player('rs_mp1')
        self.p.x = 13

    def tearDown(self):
        self.tmp.cleanup()

    def test_started_without_any_radiosurvivor_module(self):
        self.assertTrue(self.w.alone.started)
        self.assertIsNone(self.w.rt.eval('RS_LivingKnox'))
        loaded = self.w.rt.eval('(function() local o = {} for k in pairs(package.loaded) do o[#o + 1] = k end '
                                'return table.concat(o, ";") end)()')
        self.assertEqual([m for m in loaded.split(';') if m.startswith('RadioSurvivor/') and 'RS_LivingKnox' not in m], [])

    def test_a_sentence_goes_to_the_bridge_and_comes_back_as_a_bubble(self):
        req = self.w.say(self.p, 'Bonjour')
        self.assertIsNotNone(req, self.w.sent)
        self.assertEqual(req.kind, 'npc_talk')
        self.assertEqual(req.character, self.character)
        self.assertEqual(req.context.stage, 'stranger')
        self.assertIsNotNone(req.context.group)
        protocol.unpack_request({'id': req.id, 'kind': req.kind, 'payload': protocol.encode(convert(req)).hex()})
        self.w.answer()
        said = self.w.commands('talkSpeech')
        self.assertEqual(len(said), 1)
        self.assertEqual(said[0][3].text, 'Noted.')
        history = self.w.rt.eval("require('RadioSurvivorCore/RC_History')").find(self.character, 'lk:' + req.npc)
        self.assertEqual([h.author != 'x' and h.text for h in history.values()], ['Bonjour', 'Noted.'])

    def test_nobody_near_is_silent_in_the_chat_and_refused_by_the_menu(self):
        self.p.x = 500
        self.assertIsNone(self.w.say(self.p, 'Bonjour', chat=True))
        self.assertEqual(self.w.commands('talkRefused'), [])
        self.assertIsNone(self.w.say(self.p, 'Bonjour'))
        self.assertEqual(self.w.commands('talkRefused')[0][3].reason, 'Range')

    def test_an_acquainted_npc_offers_a_mission_taken_by_speech(self):
        npc = self.w.g.LK_LEADER
        for _ in range(4):
            self.w.say(self.p, 'Salut', npc=npc)
            self.w.answer()
        req = self.w.say(self.p, 'Tu as du travail ?', npc=npc)
        self.assertEqual(req.context.stage, 'acquainted')
        offers = list(req.offers.keys())
        self.assertTrue(offers, 'no offer')
        self.w.answer('offer', offers[0])
        self.assertEqual(len(self.w.commands('talkOffer')), 1)
        rows = self.w.rt.eval("require('RadioSurvivorCore/RC_MissionJournal')").rows(self.character)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[1].state, 'offer')
        accept = self.w.say(self.p, "D'accord", npc=npc)
        self.assertIsNotNone(accept.context.acceptable)
        self.w.answer('accept')
        rows = self.w.rt.eval("require('RadioSurvivorCore/RC_MissionJournal')").rows(self.character)
        self.assertEqual(rows[1].state, 'active')

    def accepted_supply(self):
        npc = self.w.g.LK_LEADER
        for _ in range(4):
            self.w.say(self.p, 'Salut', npc=npc)
            self.w.answer()
        req = self.w.say(self.p, 'Tu as du travail ?', npc=npc)
        self.w.answer('offer', list(req.offers.keys())[0])
        self.w.say(self.p, "D'accord", npc=npc)
        self.w.answer('accept')
        store = self.w.rt.eval("require('RadioSurvivorCore/RC_MissionStore')")
        m = list(store.data.missions.values())[0]
        self.assertEqual((m.state, m.unit), ('active', 'value'))
        return m

    def gesture(self, m, action, **args):
        journal = self.w.rt.eval("require('RadioSurvivorCore/RC_MissionJournal')")
        table = self.w.rt.table_from({'action': action, 'mission': m.id, 'revision': m.revision, **args})
        self.w.sent.clear()
        journal.onClientCommand('RadioSurvivorCore', 'mission', self.p, table)
        errors = [c[3].reason for c in self.w.sent if c[2] == 'error']
        rows = [c[3].missions for c in self.w.sent if c[2] == 'missions']
        return errors, rows[-1] if rows else None

    def test_items_are_handed_over_and_the_lot_claimed_from_the_journal(self):
        m = self.accepted_supply()
        m.quantity = 4  # two cans of value 2 each
        kind = next(iter(m.accepted.keys()))
        ids = []
        for _ in range(2):
            it = self.w.g.item(kind)
            self.p.inv.AddItem(self.p.inv, it)
            ids.append(it.id)
        self.p.x = 500
        errors, _ = self.gesture(m, 'deliver', items=self.w.rt.table_from(ids))
        self.assertEqual(errors, ['Range'])
        self.p.x = 13
        errors, rows = self.gesture(m, 'deliver', items=self.w.rt.table_from(ids))
        self.assertEqual(errors, [])
        self.assertEqual(m.state, 'success')
        self.assertEqual(rows[1].toClaim, True)
        errors, rows = self.gesture(m, 'claim')
        self.assertEqual(errors, [])
        self.assertEqual(m.claimedBy, self.character)
        # Engine supply lot paid at completion: the common lot (2 x Antibiotics) reaches the inventory.
        got = list(self.w.rt.eval('function(inv) local o = {} for _, it in ipairs(inv.items) do '
                                  'o[#o + 1] = it:getFullType() end return o end')(self.p.inv).values())
        self.assertEqual(got.count(m.rewardType), m.rewardCount, got)
        self.assertEqual(len(rows), 0)
        errors, _ = self.gesture(m, 'claim')
        self.assertEqual(errors, ['State'])

    def test_without_surplus_nor_announced_lot_the_group_lot_is_created(self):
        """E18-T33 : ni surplus ni lot annoncé : lot créé selon le type du groupe, annoncé par le carnet, donné une fois."""
        m = self.accepted_supply()
        m.quantity = 4
        m.rewardCount = 0
        kind = next(iter(m.accepted.keys()))
        ids = []
        for _ in range(2):
            it = self.w.g.item(kind)
            self.p.inv.AddItem(self.p.inv, it)
            ids.append(it.id)
        self.p.x = 13
        errors, rows = self.gesture(m, 'deliver', items=self.w.rt.table_from(ids))
        self.assertEqual(errors, [])
        self.assertEqual(rows[1].toClaim, True)
        cfg = self.w.rt.eval("require('RadioSurvivorCore/RC_MissionConfig')")
        group = self.w.rt.eval('function(id) local G = LivingKnox.Groups; return G.get(G.findNpc(id)) end')(m.npc)
        name = cfg.NPC_REWARD_TABLES[group.type] or 'food'
        self.assertEqual(rows[1].rewardTable, name)
        # Le banc ne charge pas le stock des foyers (LivingKnox.Stock) : aucun surplus.
        self.assertIsNone(self.w.rt.eval('LivingKnox.Stock'))
        errors, rows = self.gesture(m, 'claim')
        self.assertEqual(errors, [])
        self.assertEqual((m.claimedBy, m.createdLot), (self.character, name))
        got = list(self.w.rt.eval('function(inv) local o = {} for _, it in ipairs(inv.items) do '
                                  'o[#o + 1] = it:getFullType() end return o end')(self.p.inv).values())
        for entry in cfg.Caches.tables[name].values():
            self.assertEqual(got.count(entry[1]), entry[2], got)
        errors, _ = self.gesture(m, 'claim')
        self.assertEqual(errors, ['State'])

    def test_a_radiosurvivor_giver_is_refused_by_the_journal(self):
        m = self.accepted_supply()
        m.donor = 'voice'
        errors, _ = self.gesture(m, 'claim')
        self.assertEqual(errors, ['State'])

    def storm(self, npc):
        """Le PNJ a remarqué un orage (journal des observations de Living Knox, E18-T27)."""
        obs = self.w.rt.eval('LivingKnox.Observations')
        key, why = obs.record(npc, self.w.rt.table_from(
            {'fact': 'weather', 'subject': 'storm', 'day': obs.today(), 'place': 'everywhere'}))
        self.assertIsNotNone(key, why)
        return key

    def pending(self, kind):
        return [r for r in self.w.talk.pending.values() if r.kind == kind]

    def test_an_npc_speaks_up_on_its_own_without_radiosurvivor(self):
        """E18-T27 : une observation récente d'un PNJ entendu ouvre une initiative, dite en bulle."""
        self.w.rt.execute("require 'LivingKnox/LK_Speech'")  # proximity speech channel (loaded in the game)
        npc = self.w.g.LK_LEADER
        self.w.talk.ensure(npc)
        self.storm(npc)
        self.w.answer()  # one pass: LK_Talk.turns opens the initiative
        asked = self.pending('npc_initiative')
        self.assertEqual(len(asked), 1, [r.kind for r in self.w.talk.pending.values()])
        self.assertEqual(asked[0].npc, npc)
        self.assertIsNotNone(asked[0].event)
        initiatives = self.w.rt.eval("require('LivingKnox/LK_Initiatives')")
        said = initiatives.stats.said
        self.w.answer()
        # Said by the proximity speech channel of the NPC (Provider.say, LK11-T04), as with RadioSurvivor.
        self.assertEqual(initiatives.stats.said, said + 1)
        self.assertEqual(self.pending('npc_initiative'), [])

    def test_two_npcs_tell_each_other_what_they_saw(self):
        """E18-T27 : deux PNJ proches devant le joueur ; le voisin apprend le récit après la première réplique."""
        self.w.rt.execute("require 'LivingKnox/LK_Speech'")
        teller, partner = self.w.g.LK_LEADER, self.w.g.LK_MATE
        self.w.talk.ensure(teller)
        self.w.talk.ensure(partner)
        initiatives = self.w.rt.eval("require('LivingKnox/LK_Initiatives')")
        initiatives.bridge.down = False
        key = self.storm(teller)
        # The initiative of the teller goes first (same observation); its reply frees the teller.
        for _ in range(4):
            self.w.answer()
            if self.pending('npc_converse'):
                break
        conv = self.pending('npc_converse')
        self.assertTrue(conv, 'no conversation line asked')
        obs = self.w.rt.eval('LivingKnox.Observations')
        for _ in range(4):
            self.w.answer()
        heard = [o.source for o in obs.list(partner).values() if o.key == key]
        self.assertEqual(heard, ['heard_from:' + teller])

    def test_a_player_who_never_spoke_is_bound_and_hears_initiatives(self):
        """E18-T27 (campagne MP du 2026-11-07, « listeners 0 ») : le hello du client arrivé avant son joueur serveur est
        perdu ; chaque passage lie les joueurs vivants sans identité."""
        identity = self.w.rt.eval("require('RadioSurvivorCore/RC_Identity')")
        identity.bound[self.p] = None
        self.assertIsNone(identity.bound[self.p])
        self.w.answer()
        self.assertEqual(identity.bound[self.p], self.character)

    def test_speakers_and_acquaintance_survive_a_restart(self):
        req = self.w.say(self.p, 'Bonjour')
        self.w.answer()
        npc = req.npc
        self.assertTrue(self.w.talk.save())
        world = self.w.talk.data.world
        again = World(self.path, self.clock, False)
        self.assertEqual(again.talk.data.world, world)
        self.assertEqual(again.talk.data.contacts[self.character][npc].exchanges, 1)
        self.assertEqual(again.talk.data.speakers[npc].id, npc)


class SourceTests(unittest.TestCase):
    def test_commands_are_the_same_on_both_sides(self):
        server = (LK / 'server/LivingKnox/LK_TalkAlone.lua').read_text(encoding='utf-8')
        client = (LK / 'client/LivingKnox/LK_TalkView.lua').read_text(encoding='utf-8')
        for name in ('MODULE', 'CMD_SAY', 'CMD_REFUSED', 'CMD_SPEECH', 'CMD_OFFER'):
            a = re.search(r'Alone\.%s = "(\w+)"' % name, server).group(1)
            b = re.search(r'View\.%s = "(\w+)"' % name, client).group(1)
            self.assertEqual(a, b, name)

    def test_no_radiosurvivor_module_is_required(self):
        for path in (LK / 'server/LivingKnox/LK_TalkAlone.lua', LK / 'client/LivingKnox/LK_TalkView.lua',
                     LK / 'server/LivingKnox/LK_Observations.lua', LK / 'server/LivingKnox/LK_ObservationTriggers.lua',
                     LK / 'server/LivingKnox/LK_MissionRewards.lua'):
            text = path.read_text(encoding='utf-8')
            self.assertEqual(re.findall(r'''require\s*\(?\s*['"]RadioSurvivor/[^'"]+''', text), [], path.name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
