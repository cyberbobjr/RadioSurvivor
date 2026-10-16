"""Réconfort social (E05-T15) : server/RadioSurvivor/RS_Comfort.lua et ses branchements ; lupa, Lua 5.1.

    python RadioSurvivor/tests/test_comfort.py

Couvre :
- le module seul : baisse d'ennui et de tristesse par réponse (options ComfortBoredom, ComfortSadness), écoute d'une
  conversation (ComfortListen, une fois par conversation et par personnage), plafond ComfortPerHour par personnage et
  par heure de jeu (remis à l'heure suivante), options à 0, jauges déjà à zéro (rien compté, ni synchro ni halo),
  personnage changé depuis la phrase, joueur mort, synchro syncPlayerStats sur un serveur seulement (masques
  SyncPlayerStatsPacket, repli sur les rangs de CharacterStat.ORDERED_STATS), commande comfort au client ;
- le vrai RadioSurvivor_Server.lua (serveur simulé de test_personas_server.py) : réponse de Walt à l'antenne =
  réconfort de l'appelant ; demande restée sans réponse (NoAnswer), appel spontané, joueur déconnecté : rien ;
- le halo du vrai client RS_RadioTalk.lua (flèche vers le bas, une ligne par stat baissée).
Les branchements de la radio des groupes (E08-T06) et des conversations (E08-T04) sont couverts dans
test_group_radio.py et test_conversations.py. Doublures du jeu : ne prouve pas l'API Java (suite rs.env en jeu).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_personas_server as tps  # noqa: E402

LUA = tps.LUA
lua_list = tps.lua_list

MODULE_STUBS = r'''
SIDE = "server"
isClient = function() return SIDE == "client" end
isServer = function() return SIDE == "server" end
LOGS = {}
print = function(...) LOGS[#LOGS + 1] = table.concat({ ... }, " ") end
HOURS = 10.5
getGameTime = function() return { getWorldAgeHours = function() return HOURS end } end
SandboxVars = { RadioSurvivor = {} }
CharacterStat = { BOREDOM = "Boredom", UNHAPPINESS = "Unhappiness" }
-- 1 << rang dans CharacterStat.ORDERED_STATS (SyncPlayerStatsPacket.java:28) : BOREDOM 1, UNHAPPINESS 20.
SyncPlayerStatsPacket = { getBitMaskForStat = function(stat)
    if stat == "Boredom" then return 2 end
    if stat == "Unhappiness" then return 1048576 end
    return 0 end }
SYNCED, SENT = {}, {}
syncPlayerStats = function(p, mask) SYNCED[#SYNCED + 1] = { name = p.name, mask = mask } end
sendServerCommand = function(p, module, command, args)
    SENT[#SENT + 1] = { name = p.name, module = module, command = command, boredom = args.boredom,
        sadness = args.sadness } end
function makePlayer(name, boredom, sadness)
    local p = { name = name, dead = false, values = { Boredom = boredom or 50, Unhappiness = sadness or 50 } }
    local stats = { owner = p }
    function stats:get(k) return p.values[k] or 0 end
    function stats:set(k, v) local old = self:get(k) v = math.max(0, math.min(100, v)) p.values[k] = v
        return v ~= old end
    function stats:add(k, n) return self:set(k, self:get(k) + n) end
    function stats:remove(k, n) return self:add(k, -n) end
    p.getStats = function() return stats end
    p.isDead = function(self) return self.dead end
    p.getUsername = function(self) return self.name end
    return p
end
'''


class ComfortModuleTests(unittest.TestCase):
    """Le module seul, sur une autorité simulée (serveur MP par défaut)."""

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None
        self.rt.execute(MODULE_STUBS)
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        self.C = self.rt.eval('require("RadioSurvivor/RS_Comfort")')
        self.alice = self.g.makePlayer('alice')

    def option(self, name, value):
        self.g.SandboxVars.RadioSurvivor[name] = value

    def values(self, p):
        return p['values']['Boredom'], p['values']['Unhappiness']

    def sent(self):
        return [(s.name, s.command, s.boredom, s.sadness) for s in lua_list(self.g.SENT)]

    def test_an_answer_eases_boredom_and_unhappiness_synced_and_told(self):
        self.assertTrue(self.C.answered(self.alice, 'c1', 'c1'))
        self.assertEqual(self.values(self.alice), (47, 49))
        self.assertEqual([(s.name, s.mask) for s in lua_list(self.g.SYNCED)], [('alice', 2 + 1048576)])
        self.assertEqual(self.sent(), [('alice', 'comfort', 3, 1)])

    def test_cap_per_character_and_game_hour(self):
        for _ in range(5):
            self.assertTrue(self.C.answered(self.alice, 'c1', 'c1'))
        self.assertFalse(self.C.answered(self.alice, 'c1', 'c1'))
        self.assertEqual(self.values(self.alice), (35, 45))
        self.assertEqual(self.C.stats.capped, 1)
        # Another character is not capped by alice.
        bob = self.g.makePlayer('bob')
        self.assertTrue(self.C.answered(bob, 'c2', 'c2'))
        # Next game hour: the cap is reset.
        self.g.HOURS = 11.0
        self.assertTrue(self.C.answered(self.alice, 'c1', 'c1'))
        self.assertEqual(self.values(self.alice), (32, 44))

    def test_overheard_once_per_conversation_boredom_only(self):
        seen = self.rt.eval('{}')
        self.assertTrue(self.C.overheard(self.alice, 'c1', seen))
        self.assertFalse(self.C.overheard(self.alice, 'c1', seen))
        self.assertEqual(self.values(self.alice), (49, 50))
        self.assertEqual(self.sent(), [('alice', 'comfort', 1, 0)])
        self.assertEqual([s.mask for s in lua_list(self.g.SYNCED)], [2])
        # A new conversation comforts again, within the same hourly cap as the answers.
        self.assertTrue(self.C.overheard(self.alice, 'c1', self.rt.eval('{}')))
        for _ in range(3):
            self.C.answered(self.alice, 'c1', 'c1')
        self.assertFalse(self.C.overheard(self.alice, 'c1', self.rt.eval('{}')), 'cap shared by every effect')

    def test_options_at_zero_turn_each_effect_off(self):
        self.option('ComfortSadness', 0)
        self.C.answered(self.alice, 'c1', 'c1')
        self.assertEqual(self.values(self.alice), (47, 50))
        self.assertEqual(self.sent(), [('alice', 'comfort', 3, 0)])
        self.option('ComfortBoredom', 0)
        self.assertFalse(self.C.answered(self.alice, 'c1', 'c1'))
        self.option('ComfortListen', 0)
        self.assertFalse(self.C.overheard(self.alice, 'c1', self.rt.eval('{}')))
        self.option('ComfortBoredom', 3)
        self.option('ComfortPerHour', 0)
        self.assertFalse(self.C.answered(self.alice, 'c1', 'c1'))
        self.assertEqual(self.values(self.alice), (47, 50))
        self.assertEqual(len(lua_list(self.g.SYNCED)), 1)

    def test_bad_option_values_fall_back_to_the_defaults(self):
        self.option('ComfortBoredom', -4)
        self.option('ComfortSadness', 'x')
        self.C.answered(self.alice, 'c1', 'c1')
        self.assertEqual(self.values(self.alice), (47, 49))

    def test_nothing_to_ease_counts_nothing(self):
        calm = self.g.makePlayer('calm', 0, 0)
        for _ in range(6):
            self.assertFalse(self.C.answered(calm, 'c3', 'c3'))
        self.assertEqual((lua_list(self.g.SYNCED), self.sent()), ([], []))
        # The cap was not used up: the first real effect still goes through.
        calm['values']['Boredom'] = 10
        self.assertTrue(self.C.answered(calm, 'c3', 'c3'))
        self.assertEqual(self.sent(), [('calm', 'comfort', 3, 0)])

    def test_other_character_or_dead_player_gets_nothing(self):
        self.assertFalse(self.C.answered(self.alice, 'c1', 'c9'))
        self.assertFalse(self.C.answered(self.alice, 'c1', None))
        self.alice.dead = True
        self.assertFalse(self.C.answered(self.alice, 'c1', 'c1'))
        self.assertFalse(self.C.answered(None, 'c1', 'c1'))
        self.assertEqual(self.values(self.alice), (50, 50))

    def test_solo_changes_the_stats_without_sync_and_calls_the_client_directly(self):
        self.g.SIDE = 'solo'
        got = []
        const = self.rt.eval('require("RadioSurvivor/RadioSurvivor_Const")')
        const.clientHandler = lambda command, args: got.append((command, args.boredom, args.sadness))
        self.assertTrue(self.C.answered(self.alice, None, None))
        self.assertEqual(self.values(self.alice), (47, 49))
        self.assertEqual(lua_list(self.g.SYNCED), [])
        self.assertEqual(got, [('comfort', 3, 1)])

    def test_mask_fallback_without_the_packet_class(self):
        self.g.SyncPlayerStatsPacket = None
        self.C.answered(self.alice, 'c1', 'c1')
        self.assertEqual([s.mask for s in lua_list(self.g.SYNCED)], [2 + 1048576])

    def test_fallback_masks_match_the_42_21_stat_order(self):
        java = Path('E:/pz-decompiled/42.21.0/java/zombie/characters/CharacterStat.java')
        if not java.is_file():
            self.skipTest('decompiled sources absent')
        order = re.search(r'ORDERED_STATS = new CharacterStat\[\]\{([^}]*)\}', java.read_text(encoding='utf-8'))
        names = [n.strip() for n in order.group(1).split(',')]
        self.assertEqual((1 << names.index('BOREDOM'), 1 << names.index('UNHAPPINESS')), (2, 1048576))


class ComfortServerTests(tps.ServerHarness):
    """Vrai RadioSurvivor_Server.lua : Walt répond à alice (145.0, fiche d'exemple)."""

    def setUp(self):
        super().setUp()
        self.stats = self.g.PLAYER.stats
        self.stats['values']['Boredom'] = 40
        self.stats['values']['Unhappiness'] = 40

    def requests(self) -> str:
        path = self.lua_dir / 'batman_RadioSurvivor' / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def values(self):
        return self.stats['values']['Boredom'], self.stats['values']['Unhappiness']

    def answer(self, lines=('Walt here. I hear you.',)):
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        req = re.findall(r'(?m)^req=(.*)$', self.requests())[-1]
        out = self.lua_dir / 'batman_RadioSurvivor' / 'responses.txt'
        out.write_text(f'resp={req}\n' + ''.join(f'line={x}\n' for x in lines) + 'end\n', encoding='utf-8')
        self.g.SENT = self.rt.eval('{}')
        self.g.CLOCK = self.g.CLOCK + 1000
        self.g.fire('OnTick')

    def test_answer_on_the_air_comforts_the_caller(self):
        self.answer()
        self.assertEqual(self.values(), (37, 39))
        self.assertIn('comfort', lua_list(self.g.SENT))
        self.assertEqual([s.mask for s in lua_list(self.g.SYNCED)], [2 + 1048576])

    def test_no_answer_spontaneous_call_or_gone_player_comfort_nothing(self):
        # Request left without an answer: static, NoAnswer, no comfort.
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        self.g.CLOCK = self.g.CLOCK + 10 ** 7
        self.g.fire('OnTick')
        self.assertEqual(self.values(), (40, 40))
        # Spontaneous call of the voice: nobody called, nobody is comforted.
        self.P.channel(145000).airing = None
        self.g.fire('EveryHours')
        call = re.findall(r'(?m)^req=(.*-call)$', self.requests())
        self.assertTrue(call, 'no spontaneous call requested')
        out = self.lua_dir / 'batman_RadioSurvivor' / 'responses.txt'
        out.write_text(f'resp={call[-1]}\nline=Anyone listening?\nend\n', encoding='utf-8')
        self.g.CLOCK = self.g.CLOCK + 1000
        self.g.fire('OnTick')
        self.assertIn('Anyone listening?', [x for a in lua_list(self.P.channel(145000).aired) for x in lua_list(a)])
        self.assertEqual(self.values(), (40, 40))
        self.assertEqual(lua_list(self.g.SYNCED), [])

    def test_caller_disconnected_before_the_answer_airs(self):
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        req = re.findall(r'(?m)^req=(.*)$', self.requests())[-1]
        self.rt.execute('getOnlinePlayers = function() return { size = function() return 0 end } end')
        out = self.lua_dir / 'batman_RadioSurvivor' / 'responses.txt'
        out.write_text(f'resp={req}\nline=Walt here.\nend\n', encoding='utf-8')
        self.g.CLOCK = self.g.CLOCK + 1000
        self.g.fire('OnTick')
        self.assertEqual(self.values(), (40, 40))
        self.assertEqual(lua_list(self.g.SYNCED), [])


class ComfortHaloTests(unittest.TestCase):
    """Vrai client RS_RadioTalk.lua : commande comfort -> halo vanilla à flèche vers le bas."""

    def test_halo_per_eased_stat(self):
        import tempfile
        import test_protocol as tp
        tmp = tempfile.TemporaryDirectory(prefix='rs-comfort-')
        self.addCleanup(tmp.cleanup)
        client = tp.Game('client', Path(tmp.name), lambda: 0)
        client.load('shared/RadioSurvivor/RadioSurvivor_Const.lua')
        player = client.g.makePlayer('alice')
        client.g.getPlayer = lambda: player
        talk = client.rt.eval('require("RadioSurvivor/RS_RadioTalk")')
        talk.handle('comfort', client.rt.table_from({'boredom': 3, 'sadness': 1}))
        talk.handle('comfort', client.rt.table_from({'boredom': 1, 'sadness': 0}))
        self.assertEqual(lua_list(player.halos), ['IGUI_HaloNote_Boredom:down', 'IGUI_HaloNote_Unhappiness:down',
                                                  'IGUI_HaloNote_Boredom:down'])


if __name__ == '__main__':
    unittest.main()
