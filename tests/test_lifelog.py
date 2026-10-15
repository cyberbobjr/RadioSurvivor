"""Relevé de vie du personnage (E15-T01) : banc hors jeu, vrai Lua du mod sous lupa (Lua 5.1, API du jeu simulée).

    python RadioSurvivor/tests/test_lifelog.py

- IdentityTests : aucun relevé sans identité du carnet (joueur non lié, personnage d'un autre compte, personnage
  retiré) ; relevé retiré quand son personnage disparaît sans mort vue.
- SampleTests : zombies tués, heures de survie, métier (identifiant, jamais un texte traduit), villes traversées
  (centre d'une ville vanilla, carte vanilla chargée seulement, première visite seulement), dernières phrases radio
  (lignes « dit » seulement, sans fréquence), missions closes notées une fois, sondage espacé (POLL_MS).
- BoundTests : listes bornées (villes, phrases, missions, secours, relevés figés) et taille encodée RSV2 sous MAX_BYTES ;
  persistance par RS_State après redémarrage.
- DeathTests : à la mort, dernier sondage, missions ouvertes notées « open », relevé figé puis libéré (E15-T03) ;
  indépendant de l'ordre des abonnés à OnCharacterDeath ; solo.
- SuiteTests : la suite en jeu rs.lifelog (dev/batman_RadioSurvivorTests, moteur RST) passe sur ce banc.
- CarnetIntegrationTests : vrai RS_Carnet_Server (simulation de tests/test_carnet.py), chargé AVANT le relevé : son
  abonné à OnCharacterDeath passe le premier et efface la liaison, l'identité en ModData et l'historique radio.
Simulation, PAS validation en jeu.
"""
from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from harness import Harness, ROOT
from test_carnet import Simulation, convert

SETUP = r'''
getWorld = function() return { getGameMode = function() return 'Multiplayer' end,
    getWorld = function() return 'bench' end } end
ZombRand = function(a, b) return a end
SandboxVars = { RadioSurvivor = { Enabled = true } }
S = require 'RadioSurvivor/RS_State'
Log = require 'RadioSurvivor/RS_RadioLog'
Codec = require 'RadioSurvivor/RS_Codec'
assert(S.init(NEW_WORLD ~= false))
RS_CarnetServer = { bound = {} }
-- getLotDirectories (LuaManager) : ArrayList<String> des dossiers de carte chargés.
LOTS = { 'Muldraugh, KY' }
getLotDirectories = function()
    return { size = function() return #LOTS end, get = function(_, i) return LOTS[i + 1] end }
end
LifeLog = require 'RadioSurvivor/RS_LifeLog'
-- Doublures des méthodes Java lues par le relevé (copie serveur du joueur) : IsoGameCharacter.getZombieKills,
-- IsoPlayer.getHoursSurvived, SurvivorDesc.getCharacterProfession():getName() (CharacterProfession.java:46).
function stats(p)
    p.kills, p.hours, p.prof = 0, 0, 'doctor'
    p.getZombieKills = function(self) return self.kills end
    p.getHoursSurvived = function(self) return self.hours end
    p.getDescriptor = function(self)
        return { getCharacterProfession = function()
            if not self.prof then return nil end
            return { getName = function() return self.prof end }
        end }
    end
    return p
end
function bind(username, cid, owner)
    local p = stats(HARNESS.players[username])
    if not S.data.characters[cid] then
        S.data.characters[cid] = { id = cid, owner = owner or username, slot = 0, name = username, contacts = {},
            knownMissions = {} }
    end
    RS_CarnetServer.bound[p] = cid
    p:getModData().RS_CarnetCharacter = cid
    return p
end
function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
FROZEN = {}
LifeLog.onFrozen = function(cid, log, character) FROZEN[#FROZEN + 1] = cid .. ':' .. character:getUsername() end
'''


def py(value):
    return convert(value) if value is not None and hasattr(value, 'items') else value


def values(table):
    """Liste Lua (table 1..n) convertie en liste Python."""
    if not table:
        return []
    return [table[k] for k in sorted(table)]


class Bench(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = Harness(mode=self.mode, clients=('A', 'B'))
        self.h.server.g.NEW_WORLD = True
        self.h.load('server', SETUP)

    def tearDown(self):
        self.h.close()

    def lua(self, code):
        return self.h.load('server', code)

    def ev(self, expr):
        return self.h.eval('server', expr)

    def log(self, cid):
        return py(self.ev(f'LifeLog.get("{cid}")'))

    def poll(self):
        return self.ev('LifeLog.poll()')


class IdentityTests(Bench):
    def test_no_log_without_notebook_identity(self):
        self.lua("bind('A', 'char-a'); stats(HARNESS.players.B)")
        self.poll()
        self.assertEqual(self.ev('count(S.data.lifelogs.logs)'), 1)
        self.assertIsNotNone(self.log('char-a'))
        # A binding to a character of another account, or to a retired one, gives no log either.
        self.lua("bind('B', 'char-x', 'mallory'); S.data.characters['char-a'].retired = true")
        self.poll()
        self.assertEqual(self.ev('count(S.data.lifelogs.logs)'), 0)
        self.assertIsNone(self.log('char-x'))
        self.assertIsNone(self.log('char-a'), 'live log of a retired character kept')

    def test_log_dropped_when_character_disappears(self):
        self.lua("bind('A', 'char-a')")
        self.poll()
        self.lua("S.data.characters['char-a'] = nil")
        self.poll()
        self.assertIsNone(self.log('char-a'))

    def test_dead_player_not_sampled(self):
        self.lua("bind('A', 'char-a'); HARNESS.players.A.dead = true")
        self.poll()
        self.assertIsNone(self.log('char-a'))

    def test_rescue_needs_a_live_log(self):
        self.assertFalse(self.ev("LifeLog.rescue('char-a', 'saved', 'church')"))
        self.lua("bind('A', 'char-a')")
        self.poll()
        self.assertFalse(self.ev("LifeLog.rescue('char-a', 'won', 'church')"))
        self.assertTrue(self.ev("LifeLog.rescue('char-a', 'saved', 'church')"))
        self.assertTrue(self.ev("LifeLog.rescue('char-a', 'missed', 'farmhouse')"))
        log = self.log('char-a')
        self.assertEqual([(r['outcome'], r['label']) for r in values(log['rescues'])],
                         [('saved', 'church'), ('missed', 'farmhouse')])
        self.assertEqual((log['totals']['saved'], log['totals']['missed']), (1, 1))


class SampleTests(Bench):
    def setUp(self):
        super().setUp()
        self.lua("bind('A', 'char-a')")

    def test_kills_hours_profession(self):
        self.lua("local p = HARNESS.players.A; p.kills, p.hours, p.prof = 37, 52.47, 'policeofficer'")
        self.assertTrue(self.poll())
        log = self.log('char-a')
        self.assertEqual((log['kills'], log['hours'], log['profession']), (37, 52.4, 'policeofficer'))
        self.assertEqual(log['name'], 'A')
        self.assertFalse(log['dead'])
        # Unchanged values: nothing to save. A new hour is a change.
        self.assertFalse(self.poll())
        self.lua("HARNESS.players.A.hours = 52.9")
        self.assertFalse(self.poll())
        self.lua("HARNESS.players.A.hours = 53.1")
        self.assertTrue(self.poll())
        self.lua("HARNESS.players.A.prof = nil")
        self.poll()
        self.assertEqual(self.log('char-a')['profession'], '')

    def test_towns_first_visit_in_order_and_vanilla_map_only(self):
        self.h.move_player('A', 10754, 9926)        # Muldraugh centre
        self.poll()
        self.h.move_player('A', 10754 + 400, 9926)  # still within half the radius (900)
        self.poll()
        self.h.move_player('A', 10754 + 600, 9926)  # outskirts: not "in" the town
        self.poll()
        self.h.move_player('A', 11654, 6864)        # West Point
        self.poll()
        self.h.move_player('A', 10754, 9926)        # back to Muldraugh: no second entry
        self.poll()
        towns = values(self.log('char-a')['towns'])
        self.assertEqual([t['name'] for t in towns], ['Muldraugh', 'West Point'])
        self.assertNotIn('x', towns[0])
        self.assertRegex(towns[0]['when'], r'^\d\d/\d\d \d\d:\d\d$')
        # Another map: the vanilla towns are not looked for.
        self.lua("LOTS = { 'OtherMap' }; LifeLog.resetForTests(); S.data.lifelogs = nil")
        self.h.move_player('A', 11654, 6864)
        self.poll()
        self.assertEqual(values(self.log('char-a')['towns']), [])

    def test_last_said_phrases_without_frequency(self):
        self.lua("for i = 1, 6 do Log.add('char-a', 145000, 'said', 'first ' .. i) end; "
                 "Log.add('char-a', 145000, 'reply', 'Walt here.'); Log.add('char-a', 145000, 'heard', 'Other one.'); "
                 "for i = 1, 4 do Log.add('char-a', 147200, 'said', 'second ' .. i) end")
        self.poll()
        phrases = values(self.log('char-a')['phrases'])
        self.assertEqual([p['text'] for p in phrases],
                         ['first 3', 'first 4', 'first 5', 'first 6', 'second 1', 'second 2', 'second 3', 'second 4'])
        self.assertEqual(sorted(phrases[0]), ['text', 'when'])
        self.assertNotIn('145000', repr(self.log('char-a')))
        self.assertNotIn('147200', repr(self.log('char-a')))
        self.assertFalse(self.poll(), 'same phrases rewritten')

    def test_closed_missions_noted_once(self):
        self.lua(r'''
        S.data.npcs['npc-1'] = { id = 'npc-1', name = 'Marla' }
        S.data.missions['m1'] = { id = 'm1', npc = 'npc-1', template = 'deliver', state = 'success',
            participants = { ['char-a'] = true } }
        S.data.missions['m2'] = { id = 'm2', npc = 'voice:walt:char-a', template = 'scout', state = 'failed',
            requesterName = 'Walt', placeKind = 'church', participants = { ['char-a'] = true } }
        S.data.missions['m3'] = { id = 'm3', npc = 'npc-1', template = 'scout', state = 'active',
            participants = { ['char-a'] = true } }
        S.data.missions['m4'] = { id = 'm4', npc = 'npc-1', template = 'deliver', state = 'success',
            participants = { ['char-b'] = true } }
        S.data.missions['m5'] = { id = 'm5', npc = 'npc-1', template = 'deliver', state = 'cancelled_dead',
            participants = { ['char-a'] = true } }
        ''')
        self.poll()
        log = self.log('char-a')
        entries = sorted((m['template'], m['result'], m['requester'], m['place']) for m in values(log['missions']))
        self.assertEqual(entries, [('deliver', 'cancelled_dead', 'Marla', ''), ('deliver', 'success', 'Marla', ''),
                                   ('scout', 'failed', 'Walt', 'church')])
        self.assertEqual((log['totals']['success'], log['totals']['failed'], log['totals']['cancelled']), (1, 1, 1))
        self.assertFalse(self.poll())
        self.assertEqual(len(values(self.log('char-a')['missions'])), 3)
        # The active mission closes later; a pruned mission id is forgotten.
        self.lua("S.data.missions['m3'].state = 'success'; S.data.missions['m1'] = nil")
        self.assertTrue(self.poll())
        log = self.log('char-a')
        self.assertEqual(len(values(log['missions'])), 4)
        self.assertNotIn('m1', log['noted'])
        self.assertIn('m3', log['noted'])

    def test_poll_is_spaced(self):
        self.lua("HARNESS.players.A.kills = 1")
        self.h.tick(1)  # OnTickEvenPaused: first poll
        self.assertEqual(self.log('char-a')['kills'], 1)
        self.lua("HARNESS.players.A.kills = 2")
        self.h.advance_ms(self.ev('LifeLog.POLL_MS') - 1)
        self.lua("LifeLog.tick(); LifeLog.tick()")
        self.assertEqual(self.log('char-a')['kills'], 1)
        self.h.advance_ms(1)
        self.lua("LifeLog.tick()")
        self.assertEqual(self.log('char-a')['kills'], 2)

    def test_storage_blocked_or_absent_records_nothing(self):
        self.lua("S.blocked = true")
        self.assertFalse(self.poll())
        self.lua("S.blocked = false")
        self.assertIsNone(self.ev('S.data.lifelogs'))


class BoundTests(Bench):
    def setUp(self):
        super().setUp()
        self.lua("bind('A', 'char-a')")

    def test_lists_and_encoded_size_bounded(self):
        self.lua(r'''
        local long = string.rep('n', 500)
        S.data.characters['char-a'].name = long
        for i = 1, 30 do
            S.data.missions['m' .. i] = { id = 'm' .. i, npc = 'v' .. i, template = 'scout', state = 'success',
                requesterName = long .. i, placeKind = long, participants = { ['char-a'] = true } }
        end
        for i = 1, 60 do Log.add('char-a', 140000 + (i % 8) * 200, 'said', string.rep('p', 300) .. i) end
        ''')
        self.lua("S.data.lifelogs = nil; LifeLog.poll()")
        self.lua("for i = 1, 20 do LifeLog.rescue('char-a', 'saved', string.rep('r', 500)) end")
        towns = "{ {10754, 9926}, {11654, 6864}, {13077, 2238}, {13447, 5278}, {6450, 5430}, {2056, 6070}, " \
                "{634, 9746}, {2427, 14185}, {3589, 10952}, {10130, 12801}, {7253, 8279}, {8159, 11661} }"
        self.lua(f"for _, t in ipairs({towns}) do HARNESS.players.A.x, HARNESS.players.A.y = t[1], t[2]; "
                 "LifeLog.poll() end")
        log = self.log('char-a')
        self.assertEqual(len(values(log['towns'])), 12)
        self.assertEqual(len(values(log['phrases'])), self.ev('LifeLog.MAX_PHRASES'))
        self.assertTrue(all(len(p['text']) <= 200 for p in values(log['phrases'])))
        self.assertEqual(len(values(log['missions'])), self.ev('LifeLog.MAX_MISSIONS'))
        self.assertEqual(log['totals']['success'], 30)
        self.assertEqual(len(values(log['rescues'])), self.ev('LifeLog.MAX_RESCUES'))
        self.assertEqual(log['totals']['saved'], 20)
        self.assertEqual(len(log['name']), self.ev('LifeLog.MAX_LABEL'))
        size = self.ev("#Codec.encodeBytes(LifeLog.get('char-a'))")
        self.assertLessEqual(size, self.ev('LifeLog.MAX_BYTES'))
        # Death adds the open missions: still bounded.
        self.lua("for i = 1, 30 do S.data.missions['o' .. i] = { id = 'o' .. i, npc = 'v', template = 'scout', "
                 "state = 'active', requesterName = string.rep('o', 500), placeKind = string.rep('k', 500), "
                 "participants = { ['char-a'] = true } } end")
        self.h.kill_player('A')
        log = self.log('char-a')
        self.assertEqual(len(values(log['open'])), self.ev('LifeLog.MAX_OPEN'))
        self.assertLessEqual(self.ev("#Codec.encodeBytes(LifeLog.get('char-a'))"), self.ev('LifeLog.MAX_BYTES'))

    def test_frozen_logs_bounded_oldest_dropped(self):
        self.lua(r'''
        for i = 1, 10 do
            local cid = 'dead-' .. i
            S.data.characters[cid] = { id = cid, owner = 'A', slot = 0, name = 'A', contacts = {}, knownMissions = {} }
            RS_CarnetServer.bound = { [HARNESS.players.A] = cid }
            HARNESS.players.A.dead = false
            LifeLog.poll()
            HARNESS.players.A.dead = true
            LifeLog.characterDeath(HARNESS.players.A)
        end
        ''')
        frozen = values(py(self.ev('LifeLog.frozen()')))
        self.assertEqual(frozen, ['dead-%d' % i for i in range(3, 11)])
        self.assertEqual(self.ev('count(S.data.lifelogs.logs)'), 8)

    def test_log_survives_restart(self):
        self.lua("HARNESS.players.A.kills = 12")
        self.h.move_player('A', 6450, 5430)
        self.poll()
        self.assertTrue(self.ev('S.save()'))
        root = self.h.file_root('server')
        restart = Harness(mode='mp', clients=('A', 'B'))
        try:
            shutil.copytree(root, restart.file_root('server'), dirs_exist_ok=True)
            restart.server.g.NEW_WORLD = False
            restart.load('server', SETUP)
            log = py(restart.eval('server', "LifeLog.get('char-a')"))
            self.assertEqual(log['kills'], 12)
            self.assertEqual([t['name'] for t in values(log['towns'])], ['Riverside'])
        finally:
            restart.close()


class DeathTests(Bench):
    def setUp(self):
        super().setUp()
        self.lua("bind('A', 'char-a'); bind('B', 'char-b')")

    def test_death_freezes_with_last_sample_and_open_missions(self):
        self.poll()
        self.lua(r'''
        local p = HARNESS.players.A
        p.kills, p.hours = 41, 100.25
        Log.add('char-a', 145000, 'said', 'If anyone hears this, the church is safe.')
        S.data.missions['m1'] = { id = 'm1', npc = 'v', template = 'scout', state = 'active', requesterName = 'Walt',
            placeKind = 'church', participants = { ['char-a'] = true } }
        ''')
        self.h.move_player('A', 8159, 11661)  # Rosewood
        self.h.kill_player('A')
        log = self.log('char-a')
        self.assertTrue(log['dead'])
        self.assertEqual((log['kills'], log['hours']), (41, 100.2))
        self.assertEqual([t['name'] for t in values(log['towns'])], ['Rosewood'])
        self.assertEqual([p['text'] for p in values(log['phrases'])], ['If anyone hears this, the church is safe.'])
        self.assertEqual([(m['result'], m['requester'], m['place']) for m in values(log['open'])],
                         [('open', 'Walt', 'church')])
        self.assertEqual(values(log['missions']), [], 'an open mission noted as closed')
        self.assertRegex(log['deathWhen'], r'^\d\d/\d\d \d\d:\d\d$')
        self.assertEqual(values(py(self.ev('FROZEN'))), ['char-a:A'])
        self.assertFalse(self.ev('S.dirty'), 'frozen log not saved at the death')
        # Frozen: later polls, missions and rescues change nothing; the other character is untouched.
        self.lua("HARNESS.players.A.kills = 99; S.data.missions['m1'].state = 'success'")
        self.poll()
        self.assertFalse(self.ev("LifeLog.rescue('char-a', 'saved', 'x')"))
        log = self.log('char-a')
        self.assertEqual(log['kills'], 41)
        self.assertEqual(values(log['missions']), [])
        self.assertFalse(self.log('char-b')['dead'])
        # A second death event of the same body freezes nothing twice.
        self.lua("LifeLog.characterDeath(HARNESS.players.A)")
        self.assertEqual(values(py(self.ev('FROZEN'))), ['char-a:A'])
        self.assertEqual(values(py(self.ev('LifeLog.frozen()'))), ['char-a'])
        self.assertTrue(self.ev("LifeLog.release('char-a')"))
        self.assertIsNone(self.log('char-a'))
        self.assertFalse(self.ev("LifeLog.release('char-b')"), 'a live log released')

    def test_death_found_after_another_subscriber_cleared_the_identity(self):
        # As RS_Carnet_Server.characterDeath when it runs first: binding, modData identity and radio history gone.
        self.lua("Log.add('char-a', 145000, 'said', 'Last words.')")
        self.poll()
        self.lua(r'''
        local p = HARNESS.players.A
        RS_CarnetServer.bound[p] = nil
        p:getModData().RS_CarnetCharacter = nil
        S.data.characters['char-a'].retired = true
        S.data.characters['char-a'].radio = nil
        p.kills = 5
        p.dead = true
        LifeLog.characterDeath(p)
        ''')
        log = self.log('char-a')
        self.assertTrue(log['dead'])
        self.assertEqual(log['kills'], 5)
        self.assertEqual([p['text'] for p in values(log['phrases'])], ['Last words.'])
        self.poll()
        self.assertIsNotNone(self.log('char-a'), 'frozen log of a retired character dropped')

    def test_other_account_or_zombie_freezes_nothing(self):
        self.poll()
        self.h.spawn_zombie(1001, 5, 5)
        self.h.kill_zombie(1001)
        self.lua("local p = HARNESS.players.B; p:getModData().RS_CarnetCharacter = 'char-a'; "
                 "RS_CarnetServer.bound[p] = nil; LifeLog.characterDeath(p)")
        self.assertFalse(self.log('char-a')['dead'])
        self.assertEqual(values(py(self.ev('FROZEN'))), [])


class SoloTests(Bench):
    mode = 'solo'

    def test_solo_character(self):
        # The account name of a solo player is not its owner key ('solo', as RS_Carnet_Server.ownerOf).
        self.lua("bind('A', 'char-x', 'A')")
        self.poll()
        self.assertIsNone(self.log('char-x'))
        self.lua("RS_CarnetServer.bound = {}; bind('A', 'char-s', 'solo'); HARNESS.players.A.kills = 3")
        self.poll()
        self.assertEqual(self.log('char-s')['kills'], 3)
        self.h.kill_player('A')
        self.assertTrue(self.log('char-s')['dead'])


DEV_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'


class SuiteTests(unittest.TestCase):
    """Suite en jeu rs.lifelog exécutée par le vrai moteur RST sur le serveur simulé (doublures, pas l'API réelle)."""

    def test_suite_passes(self):
        h = Harness(mode='mp', clients=('A', 'B'), lua_roots=[DEV_LUA])
        try:
            h.server.g.NEW_WORLD = True
            h.load('server', SETUP)
            h.load('server', "bind('A', 'char-a'); HARNESS.players.A.kills = 4; HARNESS.players.A.hours = 12")
            h.move_player('A', 10754, 9926)
            h.load('server', 'shared/RST/suites/RS_LifeLog.lua')
            report = h.eval('server', 'RST.runSync("rs.lifelog", { player = HARNESS.players.A })')
            results = {r.test: (r.status, r.message) for r in report.results.values()}
            self.assertEqual(len(results), 5)
            self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
            self.assertEqual(py(h.eval('server', "LifeLog.get('char-a')"))['towns'][1]['name'], 'Muldraugh')
        finally:
            h.close()


class CarnetIntegrationTests(unittest.TestCase):
    """Vrai RS_Carnet_Server chargé avant le relevé : son abonné à OnCharacterDeath passe le premier."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_lifelog_'))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_identity_from_the_notebook_and_death_after_the_carnet(self):
        sim = Simulation(self.tmp / 'mp')
        sim.server.load('server/RadioSurvivor/RS_LifeLog.lua')
        g = sim.server.g
        sim.add_client('alice')
        cid = sim.character('alice')
        self.assertTrue(cid)
        sim.server.rt.execute(r'''
        local p = PLAYERS.alice
        p.kills = 9
        p.getZombieKills = function(self) return self.kills end
        p.getDescriptor = function() return { getForename = function() return 'alice' end,
            getSurname = function() return 'Doe' end,
            getCharacterProfession = function() return { getName = function() return 'carpenter' end } end } end
        ''')
        g.require('RadioSurvivor/RS_RadioLog').add(cid, 145000, 'said', 'Alice to anyone.')
        LifeLog = g.require('RadioSurvivor/RS_LifeLog')
        LifeLog.poll()
        log = LifeLog.get(cid)
        self.assertEqual((log.kills, log.hours, log.profession), (9, 80, 'carpenter'))
        self.assertEqual(log.name, 'alice Doe')
        # Death: the carnet retires the identity first (binding, modData, radio history), the log still freezes.
        g.PLAYERS.alice.dead = True
        g.fire('OnCharacterDeath', g.PLAYERS.alice)
        state = sim.state()
        self.assertTrue(state.characters[cid].retired)
        self.assertIsNone(state.characters[cid].radio)
        log = LifeLog.get(cid)
        self.assertTrue(log.dead)
        self.assertEqual(log.phrases[1].text, 'Alice to anyone.')
        self.assertEqual(list(LifeLog.frozen().values()), [cid])


if __name__ == '__main__':
    unittest.main()
