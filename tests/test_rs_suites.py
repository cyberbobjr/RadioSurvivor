"""Tests hors jeu des suites RST de batman_RadioSurvivor : rs.env, rs.codec, rs.missions (E01-T08), rs.voices et
rs.voices.world (E05-T06, sur le serveur simulé de tests/test_personas_server.py : six fiches livrées, chaînes,
routage réel de RadioSurvivor_Server.lua), rs.radiomodule (E06-T02, interface simulée de tests/test_radio_module.py).

    python RadioSurvivor/tests/test_rs_suites.py

Charge le vrai `RST.lua`, les vrais fichiers de suites et les vrais modules du mod principal (`RS_Codec`,
`RS_Config`, `RS_Missions`, `RS_Reputation`) dans `lupa.lua51` (`next` retiré comme dans Kahlua), avec des doublures
minimales de l'API Java, puis exécute les suites par le moteur RST (`RST.runSync`). Ne prouve pas l'API Java du jeu :
l'exécution en jeu (serveur dédié de test, solo) reste nécessaire. Sous lupa les chaînes sont des octets UTF-8, en
Kahlua des unités UTF-16 : voir l'en-tête de `RS_Codec.lua` (suite).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
MOD_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
SUITES = TESTS_LUA / 'shared' / 'RST' / 'suites'
SUITE_FILES = {name: SUITES / f'{name}.lua' for name in ('RS_Env', 'RS_Codec', 'RS_Missions', 'RS_Identity',
                                                       'RS_Voices', 'RS_RadioModule')}


def env_ref(token: str, rel_end: str) -> str:
    """file:line cited by rs.env for token in the file ending with rel_end (kept in step by test_env_references...)."""
    text = SUITE_FILES['RS_Env'].read_text(encoding='utf-8')
    m = re.search(r'\{ "' + re.escape(token) + r'",[^}]*?"([\w/]+' + re.escape(rel_end) + r':\d+)" \}', text)
    assert m, f'{token}: no reference to {rel_end} in RS_Env.lua'
    return 'media/lua/' + m.group(1)

PRELUDE = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
CLOCK = 5000000
getTimestampMs = function() return CLOCK end
SIDE = "solo"
isServer = function() return SIDE == "server" end
isClient = function() return SIDE == "client" end
"""

# Doublures de l'API Java pour rs.env : présentes avec la forme que le mod et la suite utilisent.
JAVA_DOUBLES = r"""
local function fn() return function() end end
local function javaList(items)
    return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
end
VERSION = "42.21.0 abcdef"
MOD_IDS = { "batman_CharacterReputation", "batman_RadioSurvivor", "batman_RadioSurvivorTests" }
getCore = function() return { getVersion = function() return VERSION end } end
getActivatedMods = function() return javaList(MOD_IDS) end
for _, name in ipairs({ "getSandboxOptions", "getPlayer", "sendServerCommand", "getOnlinePlayers", "addSound",
    "getFileReader", "getFileWriter", "getModFileReader", "listFilesInModDirectory",
    "listFilesInZomboidLuaDirectory", "ZombRand", "getGameTime", "getZomboidRadio", "sendRemoveItemFromContainer",
    "sendAddItemToContainer", "getSpecificPlayer", "sendClientCommand", "processSayMessage", "checkPlayerCanUseChat",
    "getText", "getTextOrNull", "getTextManager", "getTexture", "getScriptManager", "instanceof", "getCell",
    "getClimateManager" }) do
    _G[name] = fn()
end
detectBadWords = function(text) return false end
getServerOptions = function()
    return { getOption = function(_, k) return "s,r,a" end, getInteger = function(_, k) return 0 end }
end
getWorld = function()
    return { getGameMode = function() return "Multiplayer" end, getWorld = function() return "rstest_smoke" end }
end
DynamicRadioChannel = { new = fn() }
ChannelCategory = { Amateur = "Amateur" }
RadioBroadCast = { new = fn() }
RadioLine = { new = fn() }
BatmanRadioSupport = { canTransmitWith = fn() }
instanceItem = fn()
ItemPickerJava = { Parse = fn() }
Translator = { getLanguage = fn(), loadFiles = fn() }
UIFont = { Medium = "Medium" }
Keyboard = { KEY_G = 34 }
ISTimedActionQueue = { add = function() end }
ISRadioAction = { new = function() end }
MapItem = { getSingleton = function() end }
UIWorldMap = { new = function() end }
WorldMapVisited = { getInstance = function() end }
WorldMapVisitedServer = { getInstance = function() end }
CONTAINERS = 0
function newContainer(label)
    CONTAINERS = CONTAINERS + 1
    return {
        label = label,
        getItemWithIDRecursiv = function(self, id) return nil end,
        getItemWithID = function(self, id) return nil end,
        getCapacityWeight = function(self) return 1.5 end,
        getEffectiveCapacity = function(self, chr) EFFECTIVE_FOR = chr; return 15 end,
        AddItem = fn(), Remove = fn(),
    }
end
ItemContainer = { new = function() return newContainer("new") end }
"""


class SuiteHarness(unittest.TestCase):
    """Moteur RST, suites et modules réels du mod dans lupa."""

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None  # absent de Kahlua
        self.lua(PRELUDE)
        paths = [TESTS_LUA / 'shared', MOD_LUA / 'shared', MOD_LUA / 'server']
        self.lua('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')
        self.lua('require "RST/RST"')

    def lua(self, code):
        return self.rt.execute(code)

    def load_suite(self, name):
        self.lua(f'dofile([[{SUITE_FILES[name].as_posix()}]])')

    def run_filter(self, flt, ctx='nil'):
        return self.lua(f'REPORT = RST.runSync({flt}, {ctx}) return REPORT')

    def results(self):
        return {r.test: (r.status, r.message) for _, r in self.g.REPORT.results.items()}

    def assert_all(self, status, suite_report):
        bad = {k: v for k, v in self.results().items() if v[0] != status}
        self.assertEqual(bad, {}, f'tests not {status}')
        self.assertGreater(suite_report.total, 0)


class CodecSuiteTests(SuiteHarness):

    def test_all_pass_on_real_module(self):
        self.load_suite('RS_Codec')
        rep = self.run_filter('"rs.codec"')
        self.assert_all('PASS', rep)
        self.assertTrue(rep.ok)
        self.assertEqual(rep.total, 15)
        # La limite modifiée par la suite est restaurée.
        self.assertEqual(self.lua('return require("RadioSurvivor/RS_Codec").MAX_BYTES'), 4194304)

    def test_suite_detects_a_broken_codec(self):
        self.load_suite('RS_Codec')
        self.lua('local C = require "RadioSurvivor/RS_Codec"; C.hex = function(s) return "zz" end')
        self.run_filter('"rs.codec"')
        st, msg = self.results()['hex and unhex on ASCII']
        self.assertEqual(st, 'FAIL')
        self.assertIn('zz', msg)


class MissionsSuiteTests(SuiteHarness):

    def test_all_pass_in_solo(self):
        self.load_suite('RS_Missions')
        rep = self.run_filter('"rs.missions"')
        self.assert_all('PASS', rep)
        self.assertEqual(rep.total, 14)
        # Aucune ModData ni état persistant : le module n'a rien écrit hors de l'état des tests.
        self.assertIsNone(self.g.ModData)

    def test_all_pass_on_a_server(self):
        self.lua('SIDE = "server"')
        self.load_suite('RS_Missions')
        self.assert_all('PASS', self.run_filter('"rs.missions"'))

    def test_skipped_on_an_mp_client(self):
        self.lua('SIDE = "client"')
        self.load_suite('RS_Missions')
        rep = self.run_filter('{ suite = "rs.missions", tags = "server" }')
        self.assert_all('SKIP', rep)
        self.assertIn('MP client', self.results()['module exports'][1])

    def test_suite_detects_a_broken_expiry(self):
        self.load_suite('RS_Missions')
        self.lua('local M = require "RadioSurvivor/RS_Missions"; local old = M.advance;'
                 'M.advance = function(state, ms) return old(state, ms * 2) end')
        self.run_filter('"rs.missions"')
        self.assertEqual(self.results()['offer expires after OFFER_TTL_MS and starts the cooldown'][0], 'FAIL')


class EnvSuiteTests(SuiteHarness):

    def setUp(self):
        super().setUp()
        self.lua(JAVA_DOUBLES)
        self.load_suite('RS_Env')

    def test_all_pass_in_solo_with_doubles(self):
        rep = self.run_filter('"rs.env"')
        self.assert_all('PASS', rep)
        self.assertEqual(rep.total, 7)

    def test_missing_global_is_an_explicit_fail(self):
        self.lua('detectBadWords = nil')
        rep = self.run_filter('"rs.env"')
        res = self.results()
        self.assertEqual(res['Java globals of the server files'],
                         ('FAIL', 'missing Java global detectBadWords '
                                  f'(used by {env_ref("detectBadWords", "RS_Carnet_Server.lua")})'))
        self.assertEqual((rep.fail, rep['pass']), (1, 6))

    def test_several_missing_globals_listed_together(self):
        self.lua('instanceItem = nil; RadioLine = {}')
        self.run_filter('"rs.env"')
        st, msg = self.results()['Java globals of the server files']
        self.assertEqual(st, 'FAIL')
        self.assertIn('missing Java global RadioLine.new '
                      f'(used by {env_ref("RadioLine.new", "RadioSurvivor_Server.lua")})', msg)
        self.assertIn('missing Java global instanceItem '
                      f'(used by {env_ref("instanceItem", "RS_Missions.lua")})', msg)

    def test_missing_client_global(self):
        self.lua('checkPlayerCanUseChat = nil')
        self.run_filter('"rs.env"')
        self.assertEqual(self.results()['Java globals of the client files'][0], 'FAIL')
        self.assertIn('checkPlayerCanUseChat', self.results()['Java globals of the client files'][1])

    def test_server_side_skips_client_and_uses_new_container(self):
        self.lua('SIDE = "server"; checkPlayerCanUseChat = nil')
        rep = self.run_filter('"rs.env"')
        res = self.results()
        self.assertEqual(res['Java globals of the client files'][0], 'SKIP')
        self.assertIn('server side', res['Java globals of the client files'][1])
        self.assertEqual(res['ItemContainer methods used by the missions'][0], 'PASS')
        self.assertEqual(self.g.CONTAINERS, 1)
        self.assertTrue(rep.ok)

    def test_client_side_skips_server_groups(self):
        self.lua('SIDE = "client"; detectBadWords = nil; ItemContainer = nil')
        rep = self.run_filter('"rs.env"')
        res = self.results()
        for name in ('Java globals of the server files', 'ItemContainer methods used by the missions',
                     'world and server option methods used by the server files'):
            self.assertEqual(res[name][0], 'SKIP', name)
            self.assertIn('client side', res[name][1])
        self.assertTrue(rep.ok)

    def test_player_inventory_preferred(self):
        self.lua('PLAYER = { inv = newContainer("player") }'
                 'function PLAYER:getInventory() return self.inv end')
        self.assertTrue(self.run_filter('"rs.env"', '{ player = PLAYER }').ok)
        self.assertEqual(self.g.CONTAINERS, 1)  # celui du joueur, aucun ItemContainer.new
        self.assertTrue(self.lua('return EFFECTIVE_FOR == PLAYER'))

    def test_missing_method_is_an_explicit_fail(self):
        self.lua('local new = newContainer; newContainer = function(l) local c = new(l); c.AddItem = nil; return c end')
        self.run_filter('"rs.env"')
        st, msg = self.results()['ItemContainer methods used by the missions']
        self.assertEqual(st, 'FAIL')
        self.assertIn('missing method ItemContainer:AddItem (used by '
                      f'{env_ref("AddItem", "RS_Missions.lua")})',
                      msg)

    def test_no_container_at_all_is_skip(self):
        self.lua('ItemContainer = nil')
        self.run_filter('"rs.env"')
        self.assertEqual(self.results()['ItemContainer methods used by the missions'][0], 'SKIP')

    def test_version(self):
        for version, status in (('42.21.0 abc', 'PASS'), ('42.21', 'PASS'), ('42.20.4 x', 'FAIL'),
                                ('42.210.0', 'FAIL'), ('41.78.16', 'FAIL')):
            self.lua(f'VERSION = "{version}"')
            self.run_filter('"rs.env"')
            self.assertEqual(self.results()['game version is 42.21'][0], status, version)

    def test_mod_id_with_or_without_backslash(self):
        self.lua(r'MOD_IDS = { "\\batman_RadioSurvivor" }')
        self.run_filter('"rs.env"')
        self.assertEqual(self.results()['batman_RadioSurvivor is active'][0], 'PASS')
        self.lua('MOD_IDS = { "batman_RadioSurvivorTests", "batman_RadioSurvivor_old" }')
        self.run_filter('"rs.env"')
        st, msg = self.results()['batman_RadioSurvivor is active']
        self.assertEqual(st, 'FAIL')
        self.assertIn('batman_RadioSurvivorTests;batman_RadioSurvivor_old', msg)


# Serveur simulé des fiches (E05-T02 à E05-T11) : réutilisé tel quel pour rs.voices.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_personas_server as tps  # noqa: E402

# Radios créées par instanceItem (bornes et IsHighTier du script vanilla, media/scripts/generated/items/radio.txt)
# et triggerEvent synchrone vers les abonnés Lua (LuaManager.GlobalObject.triggerEvent, 42.21.0).
VOICES_STUBS = r"""
RADIO_SCRIPTS = { ["Base.WalkieTalkie1"] = { 75000, 150000, false }, ["Base.WalkieTalkie5"] = { 200, 1000000, true } }
NEXT_ITEM_ID = 100
instanceItem = function(fullType)
    local spec = RADIO_SCRIPTS[fullType]
    if not spec then return nil end
    NEXT_ITEM_ID = NEXT_ITEM_ID + 1
    local id = NEXT_ITEM_ID
    -- Objet neuf : talkie portatif éteint, sans pile (lu par BatmanRadioSupport.canTransmitWith).
    local data = { getIsTwoWay = function() return true end, getIsHighTier = function() return spec[3] end,
        getMinChannelRange = function() return spec[1] end, getMaxChannelRange = function() return spec[2] end,
        getIsPortable = function() return true end, getIsTelevision = function() return false end,
        isNoTransmit = function() return false end, getIsTurnedOn = function() return false end,
        getIsBatteryPowered = function() return true end, getHasBattery = function() return false end,
        getPower = function() return 0 end, getMicIsMuted = function() return false end }
    return { isRadio = true, getID = function() return id end, getDeviceData = function() return data end,
        getDisplayName = function() return fullType end }
end
triggerEvent = function(name, ...) fire(name, ...) end
getPlayer = function() return PLAYER end
"""


class VoicesSuiteTests(tps.ServerHarness):
    """rs.voices et rs.voices.world exécutées par le vrai moteur RST (asynchrone, horloge simulée) sur les six fiches
    livrées, 21:05 heure du jeu : Walt (toujours) et le Night Owl (19:00-22:00) écoutent, Darlene, Cody et Gus non,
    Whitaker est silencieuse."""

    bundled = None
    WORLD_TESTS = ('phrase on each voice frequency reaches the bridge with its voice, silence elsewhere',
                   'ordinary radio refused by a high_tier voice, high-tier radio answered',
                   'installed sheet changed during the game, reloaded without touching its channels, restored')

    def setUp(self):
        super().setUp()
        self.rt.execute(VOICES_STUBS)
        self.rt.execute(f'package.path = [[{(TESTS_LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE_FILES["RS_Voices"].as_posix()}]])')
        self.rt.execute('ORIGINAL_TO_CLIENT = require("RadioSurvivor/RadioSurvivor_Const").toClient')

    def run_suite(self, flt):
        self.assertTrue(self.rt.eval(f'RST.start({flt}, {{ attach = false, ctx = {{}} }})'))
        for _ in range(3000):
            if not self.rt.eval('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 500
            self.g.fire('OnTickEvenPaused')
            self.g.fire('OnTick')
        report = self.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def notes(self, report) -> str:
        out = []
        for r in report.results.values():
            if r.notes is not None:
                out.extend(tps.lua_list(r.notes))
        return '\n'.join(out)

    def requests(self) -> str:
        path = self.lua_dir / 'batman_RadioSurvivor' / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def assert_clean(self, probe=True):
        if probe:
            self.assertEqual((self.dir / 'rstest_voices.txt').read_bytes(), b'')
        self.assertIsNone(self.P.get('rstest_voices'))
        self.assertEqual((self.dir / 'walt.txt').read_bytes(), (tps.BUNDLED / 'walt.txt').read_bytes())
        self.assertEqual(self.P.get('walt').name, 'Walt Hensley')
        self.assertEqual((self.lua_dir / 'batman_RadioSurvivor' / 'rstest_voices_backup_walt.txt').read_bytes(), b'')
        self.assertTrue(self.rt.eval('require("RadioSurvivor/RadioSurvivor_Const").toClient == ORIGINAL_TO_CLIENT'))
        self.assertNotIn('req=', self.requests())  # toutes les demandes de la suite ont reçu leur réponse

    def test_prefix_runs_both_suites(self):
        report, results = self.run_suite('"rs.voices"')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 8)  # filtre "rs.voices" : rs.voices et rs.voices.world (préfixe pointé)

    def test_read_only_suite_changes_nothing(self):
        before = {f.name: f.read_bytes() for f in self.dir.iterdir()}
        report, results = self.run_suite('{ suite = "rs.voices", tags = "server", exclude = "world" }')
        self.assertEqual(report.total, 5)
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual({f.name: f.read_bytes() for f in self.dir.iterdir()}, before)
        self.assertEqual(self.requests(), '')
        notes = self.notes(report)
        for expected in ('walt (active) on 130.0 MHz', 'nightowl (active) on 88.0, 109.0 MHz',
                         'whitaker silent on 75.0 MHz', 'cody: active, radio any, listen 22:00-03:00',
                         '7 voice frequencies'):
            self.assertIn(expected, notes)

    def test_world_suite_on_a_server(self):
        report, results = self.run_suite('"rs.voices.world"')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 3)
        self.assert_clean()
        # Réponse simulée diffusée en parasites sur la fréquence de Walt.
        aired = tps.lua_list(self.P.channel(self.served('walt')[0]).aired)
        self.assertEqual([tps.lua_list(lines) for lines in aired][:1], [['<bzzt>', '<fzzt>']])
        notes = self.notes(report)
        for expected in ('walt on 130.0 MHz: active, listen always (listening now) -> request',
                         'nightowl on 88.0 MHz: active, listen 19:00-22:00 (listening now) -> request',
                         'darlene on 115.0 MHz: active, listen 07:00-10:00,16:00-19:00 (not listening now) -> silence',
                         'whitaker on 75.0 MHz: silent', 'probe radio=high_tier on 149.2 MHz', 'free frequency 199.8 MHz -> silence',
                         'walt.txt reloaded'):
            self.assertIn(expected, notes)

    def test_generated_group_voice_has_no_sheet_file(self):
        # Voix de groupe engendrée (RS_GroupRadio, Personas.setGenerated) : aucune fiche par conception (campagne MP du
        # 2026-10-15 : « grp_1.txt missing or empty », puis requête attendue au pont alors qu'elle passe par le carnet).
        self.rt.execute('GRP_MAP = { grp_1 = { group = "grp-1", lines = { "format=1", "id=grp_1", "name=Group radio",'
                        '"language=en", "frequency_range=75.0-149.8", "radio=any", "listen=always", "location=none",'
                        '"actions=say", "budget=0", "call_one_in=0", "state=active", "[prompt]", "Group voice." } } }')
        # RS_GroupRadio.refresh (appelé par son tick) : un groupe équipé d'un poste, celui de GRP_MAP (sans Living Knox
        # dans ce banc, le vrai refresh retirerait la voix).
        self.rt.execute('local P = require("RadioSurvivor/RS_Personas"); local G = require("RadioSurvivor/RS_GroupRadio");'
                        'G.refresh = function() if P.setGenerated(GRP_MAP) then P.reload() end end;'
                        'assert(P.setGenerated(GRP_MAP)); P.reload()')
        self.assertTrue(self.P.get('grp_1').generated)
        report, results = self.run_suite('"rs.voices"')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        notes = self.notes(report)
        self.assertIn('grp_1: generated group voice, active (no sheet file by design)', notes)
        self.assertIn('generated group voice -> silence for a caller without a notebook character', notes)
        self.assertNotIn('voice=grp_1', self.requests())

    def test_world_suite_in_solo_waits_the_cooldown(self):
        self.g.SIDE = 'solo'
        start = self.g.CLOCK
        report, results = self.run_suite('"rs.voices.world"')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assert_clean()
        # Trois demandes (Walt, Night Owl, sonde haut de gamme) : au moins trois délais PlayerCooldown de 10 s.
        self.assertGreater(self.g.CLOCK - start, 30000)

    def test_interrupted_run_restored_by_the_next_one(self):
        backup = self.lua_dir / 'batman_RadioSurvivor' / 'rstest_voices_backup_walt.txt'
        backup.write_bytes((self.dir / 'walt.txt').read_bytes())
        self.write('walt.txt', (self.dir / 'walt.txt').read_text(encoding='utf-8').replace(
            'name=Walt Hensley', 'name=Walt Hensley RST'))
        report, results = self.run_suite('{ suite = "rs.voices.world", test = "installed sheet" }')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertIn('sheet walt.txt restored from the backup of an interrupted run', self.notes(report))
        self.assert_clean(probe=False)

    def test_world_suite_refused_outside_a_test_save(self):
        self.rt.execute('getWorld = function() return { getWorld = function() return "MyWorld" end,'
                        'getGameMode = function() return "Multiplayer" end } end')
        _, results = self.run_suite('"rs.voices.world"')
        self.assertTrue(all(v[0] == 'SKIP' for v in results.values()), results)
        self.assertFalse((self.dir / 'rstest_voices.txt').exists())
        self.assertEqual(self.requests(), '')

    def test_skipped_on_an_mp_client(self):
        self.g.SIDE = 'client'
        _, results = self.run_suite('{ suite = "rs.voices", tags = { "server", "world" } }')
        self.assertTrue(all(v[0] == 'SKIP' for v in results.values()), results)

    def test_detects_a_request_routed_to_the_wrong_voice(self):
        self.rt.execute('local P = require("RadioSurvivor/RS_Personas"); local old = P.voiceAt;'
                        'P.voiceAt = function(khz) if old(khz) == "nightowl" then return "walt" end return old(khz) end')
        _, results = self.run_suite('"rs.voices.world"')
        st, msg = results[self.WORLD_TESTS[0]]
        self.assertEqual(st, 'FAIL')
        # Fréquence du Night Owl attribuée à Walt, qui ne la sert pas : silence là où une demande était attendue.
        self.assertIn('voice nightowl: answers to the caller (request expected)', msg)

    def test_detects_a_low_tier_radio_answered(self):
        # La suite lit IsHighTier = false sur son talkie ordinaire, le serveur lit ensuite true : la phrase obtient
        # une demande, ce que la suite doit refuser.
        self.rt.execute('local old = instanceItem; instanceItem = function(ft) local r = old(ft)'
                        ' if ft == "Base.WalkieTalkie1" then local d = r.getDeviceData(); local n = 0;'
                        ' d.getIsHighTier = function() n = n + 1 return n > 1 end end return r end')
        _, results = self.run_suite('"rs.voices.world"')
        st, msg = results[self.WORLD_TESTS[1]]
        self.assertEqual(st, 'FAIL')
        self.assertIn('Base.WalkieTalkie1 on a high_tier voice', msg)
        self.assertEqual((self.dir / 'rstest_voices.txt').read_bytes(), b'')

    def test_detects_a_published_channel_name(self):
        self.rt.execute('local f = require("RadioSurvivor/RS_Personas").served("gus")[1];'
                        'CHANNEL_NAMES[f] = "Radio Survivor"')
        _, results = self.run_suite('{ suite = "rs.voices", tags = "server", exclude = "world" }')
        self.assertEqual(results['no voice channel name listed for the clients'][0], 'FAIL')

    def test_server_callers_unique_across_tests(self):
        # MP run of 2026-10-14 (E01-T15): callers numbered per test reused "rstest_voices_1" in the next test,
        # within PlayerCooldown on a real server ("rejected:Cooldown"). One name per phrase for the whole run.
        self.g.SIDE = 'server'
        self.rt.execute('CALLERS = {}; local old = triggerEvent; triggerEvent = function(name, a, b, p, ...)'
                        ' if name == "OnClientCommand" and type(p) == "table" then'
                        ' CALLERS[#CALLERS + 1] = p:getUsername() end return old(name, a, b, p, ...) end')
        self.run_suite('"rs.voices.world"')
        callers = list(self.rt.eval('CALLERS').values())
        self.assertGreater(len(callers), 3)
        self.assertEqual(len(callers), len(set(callers)), callers)

    def test_detects_a_reload_that_ignores_changes(self):
        self.rt.execute('local P = require("RadioSurvivor/RS_Personas"); P.tick = function() end')
        _, results = self.run_suite('"rs.voices.world"')
        st, msg = results[self.WORLD_TESTS[2]]
        self.assertEqual(st, 'FAIL')
        self.assertIn('not picked up by the periodic reload', msg)
        self.assertEqual((self.dir / 'walt.txt').read_bytes(), (tps.BUNDLED / 'walt.txt').read_bytes())


# rs.radiomodule (E06-T02) : vrais RS_RadioTalk et RS_RadioModule sur l'interface simulée de test_radio_module.py,
# plus des objets radio de instanceItem (Radio, DeviceData) et la fenêtre réelle d'ISRadioWindow.activate.
import test_radio_module as trm  # noqa: E402

RADIO_ITEMS = r"""
TWO_WAY_TYPES = { ["Base.WalkieTalkie1"] = true, ["Base.WalkieTalkie2"] = true, ["Base.WalkieTalkie3"] = true,
    ["Base.WalkieTalkie4"] = true, ["Base.WalkieTalkie5"] = true, ["Base.WalkieTalkieMakeShift"] = true,
    ["Base.ManPackRadio"] = true, ["Base.HamRadio1"] = true, ["Base.HamRadio2"] = true }
instanceItem = function(fullType)
    local isRadio = TWO_WAY_TYPES[fullType] or fullType == "Base.RadioBlack" or fullType == "Base.RadioRed"
    if not isRadio then return nil end
    local data = newData(TWO_WAY_TYPES[fullType] == true, false, true)
    function data:setTurnedOnRaw(b) self.on = b end
    function data:setMicIsMuted(b) self.muted = b end
    function data:getDeviceName() return fullType end
    return newDevice("Radio", data)
end
getCore = function() return { getOptionFontSizeReal = function() return 1 end } end
"""


class RadioModuleSuiteTests(SuiteHarness):

    def setUp(self):
        super().setUp()
        self.lua(f'package.path = [[{(MOD_LUA / "client").as_posix()}/?.lua;]] .. package.path')
        self.lua(trm.STUBS)
        self.lua(RADIO_ITEMS)
        # Traductions EN réelles (clé inconnue rendue telle quelle, %1 remplacé comme Translator).
        en = json.loads((MOD_LUA / 'shared' / 'Translate' / 'EN' / 'IG_UI.json').read_text(encoding='utf-8-sig'))
        self.g.LANG = self.rt.table_from(en)
        self.lua('getText = function(key, a) local v = LANG[key] or key; if a ~= nil then v = string.gsub(v, "%%1", '
                 'tostring(a)) end return v end')
        self.lua('require "RadioSurvivor/RS_RadioModule"')
        self.load_suite('RS_RadioModule')

    def test_memory_suite_passes_and_world_suite_needs_a_test_save(self):
        rep = self.run_filter('"rs.radiomodule"')
        results = self.results()
        self.assertEqual(rep.total, 7)
        world = 'held walkie-talkie: real window shows, hides and releases'
        self.assertEqual(results.pop(world)[0], 'SKIP')
        send = 'Enter sends to Walt, keyboard released, answer in the two last lines (solo, bridge)'
        self.assertEqual(results.pop(send)[0], 'SKIP')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(len(results), 5)

    def test_detects_a_module_shown_on_a_receiver(self):
        self.lua('local T = require("RadioSurvivor/RS_RadioTalk"); T.moduleShown = function(d) return d ~= nil end')
        self.run_filter('{ suite = "rs.radiomodule", exclude = "world" }')
        status, message = self.results()['two-way radios show it, receivers do not']
        self.assertEqual(status, 'FAIL')
        self.assertIn('Base.RadioBlack: module shown on a receiver', message)

    def test_detects_a_focus_kept_after_close(self):
        self.lua('RS_RadioModule.clear = function(self) RWMPanel.clear(self) end')
        self.run_filter('{ suite = "rs.radiomodule", exclude = "world" }')
        status, message = self.results()['closing the window releases the keyboard']
        self.assertEqual(status, 'FAIL')
        self.assertIn('still focused', message)

    def test_skipped_on_a_server(self):
        self.lua('isServer = function() return true end')
        self.run_filter('"rs.radiomodule"')
        self.assertTrue(all(v[0] == 'SKIP' for v in self.results().values()), self.results())


class SourceTests(unittest.TestCase):

    def test_kahlua_constraints(self):
        for path in SUITE_FILES.values():
            code = re.sub(r'--\[\[.*?\]\]', '', path.read_text(encoding='utf-8'), flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code), path.name)
            self.assertIsNone(re.search(r'\bgoto\b|debug\.traceback|%q|coroutine\.wrap', code), path.name)
            self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', code.replace('~=', '')), path.name)

    def test_no_bandits_dependency(self):
        for path in SUITE_FILES.values():
            code = re.sub(r'--\[\[.*?\]\]', '', path.read_text(encoding='utf-8'), flags=re.S)
            self.assertIsNone(re.search(r'RS_Bandits|GetBanditClusterData|BanditUtils|BanditServer|Bandits2', code),
                              path.name)

    def test_env_references_point_at_real_uses(self):
        """Chaque « file:line » de rs.env cite une ligne du mod qui contient bien le nom vérifié."""
        src = SUITE_FILES['RS_Env'].read_text(encoding='utf-8')
        refs = re.findall(r'\{ "([\w.]+)", (?:"\w+", )?"((?:client|server|shared)/[\w/]+\.lua):(\d+)" \}', src)
        self.assertGreater(len(refs), 35)
        for name, rel, line in refs:
            path = MOD_LUA / rel
            self.assertTrue(path.is_file(), rel)
            self.assertNotEqual(path.name, 'RS_Bandits.lua')
            text = path.read_text(encoding='utf-8').splitlines()[int(line) - 1]
            token = name.split('.')[0] if name[0].isupper() else name
            self.assertIn(token, text, f'{name} absent de {rel}:{line}')


# E08-T11 : recherche bornée des emplacements de PNJ des suites rs.conversations et rs.initiatives
# (RST.RSHelpers.heardSquares / pairSquares). Doublures : grille de cases libres, bâtiment déclaré par case
# (getBuilding/getRoom), LosUtil.lineClear bloqué par un mur vertical (côté ouest de la colonne WALL_X) ou par une paire
# orientée déclarée (lineClear n'est pas symétrique, perception.md), Provider.hears et RS_Config réels.
SPOT_DOUBLES = r"""
package.loaded["RST/RST_Fixtures"] = true
package.loaded["RST/RST_PeerChecks"] = true
CharacterTrait = { DEAF = "DEAF" }
UIFont = UIFont or { Medium = "Medium" }
LINECLEAR = 0
WALL_X, WALL_Y0, WALL_Y1 = nil, nil, nil
ONE_WAY = {}          -- ["x0,y0>x1,y1"] = true : bloqué dans ce sens seulement
BUSY = {}             -- ["x,y"] = true : case non libre (Bodies.freeSquare faux)
INSIDE = {}           -- ["x,y"] = true : case dans le bâtiment B, pièce r
local building, room = { "B" }, { "r" }
local squares = {}
local function key(x, y) return x .. "," .. y end
local function square(x, y, z)
    local k = key(x, y) .. "," .. z
    if squares[k] == nil then
        squares[k] = {
            getX = function() return x end, getY = function() return y end, getZ = function() return z end,
            getBuilding = function() return INSIDE[key(x, y)] and building or nil end,
            getRoom = function() return INSIDE[key(x, y)] and room or nil end,
        }
    end
    return squares[k]
end
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        if x ~= math.floor(x) or y ~= math.floor(y) then error("getGridSquare: int expected") end
        return square(x, y, z)
    end }
end
LosUtil = { lineClear = function(cell, x0, y0, z0, x1, y1, z1, ignoreDoors)
    if type(ignoreDoors) ~= "boolean" then error("No implementation found for LosUtil.lineClear") end
    for _, v in ipairs({ x0, y0, z0, x1, y1, z1 }) do
        if v ~= math.floor(v) then error("LosUtil.lineClear: int expected, got " .. v) end
    end
    LINECLEAR = LINECLEAR + 1
    if ONE_WAY[key(x0, y0) .. ">" .. key(x1, y1)] then return "Blocked" end
    if WALL_X and (x0 < WALL_X) ~= (x1 < WALL_X) then
        local lo, hi = math.min(y0, y1), math.max(y0, y1)
        if hi >= WALL_Y0 and lo <= WALL_Y1 then return "Blocked" end
    end
    return "Clear"
end }
LivingKnox = { Bodies = { freeSquare = function(sq) return sq ~= nil and not BUSY[key(sq:getX(), sq:getY())] end } }
PX, PY = 100, 100
PLAYER = {
    getX = function() return PX + 0.5 end, getY = function() return PY + 0.5 end, getZ = function() return 0 end,
    getSquare = function() return square(PX, PY, 0) end,
    isDead = function() return false end, isAsleep = function() return false end,
    hasTrait = function() return false end,
}
require "RST/RST_RSHelpers"
R = RST.RSHelpers
function squaresOf(list)
    local out = {}
    for i, sq in ipairs(list) do out[i] = { sq:getX(), sq:getY() } end
    return out
end
function pairsOf(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = { e.a:getX(), e.a:getY(), e.b:getX(), e.b:getY() } end
    return out
end
"""


class SpotsTests(SuiteHarness):
    def setUp(self):
        super().setUp()
        self.lua(SPOT_DOUBLES)

    def heard(self, r='nil'):
        return [tuple(v.values()) for v in self.lua(f'return squaresOf(R.heardSquares(PLAYER, {r}))').values()]

    def pairs(self, rng=4, mx='nil'):
        return [tuple(v.values()) for v in self.lua(f'return pairsOf(R.pairSquares(PLAYER, {rng}, {mx}))').values()]

    def test_heard_squares_free_not_next_to_player_nearest_first(self):
        self.lua('BUSY["102,100"] = true')
        heard = self.heard(3)
        self.assertNotIn((102, 100), heard)
        self.assertTrue(all(max(abs(x - 100), abs(y - 100)) in (2, 3) for x, y in heard))
        self.assertEqual(len(heard), 7 * 7 - 3 * 3 - 1)
        dist = [(x - 100) ** 2 + (y - 100) ** 2 for x, y in heard]
        self.assertEqual(dist, sorted(dist))

    def test_player_inside_hears_only_the_building(self):
        """Joueur dans une maison : une case dehors n'est pas entendue (Provider.hears : bâtiment d'un seul côté)."""
        self.lua('for x = 97, 103 do for y = 97, 103 do INSIDE[x .. "," .. y] = true end end')
        heard = self.heard(6)
        self.assertTrue(heard)
        self.assertTrue(all(97 <= x <= 103 and 97 <= y <= 103 for x, y in heard), heard)

    def test_pairs_never_across_a_wall_nor_next_to_each_other(self):
        self.lua('WALL_X, WALL_Y0, WALL_Y1 = 102, 0, 200')
        pairs = self.pairs(4)
        self.assertEqual(len(pairs), 4)
        for ax, ay, bx, by in pairs:
            self.assertEqual(ax < 102, bx < 102, (ax, ay, bx, by))
            self.assertGreaterEqual(max(abs(ax - bx), abs(ay - by)), 2)
            self.assertLessEqual((ax - bx) ** 2 + (ay - by) ** 2, 16)
        self.assertEqual(len({(ax, ay) for ax, ay, _, _ in pairs}), 4, 'one pair per teller square')

    def test_one_way_sight_is_refused(self):
        """CanSee n'est pas symétrique : un sens bloqué suffit à écarter la paire."""
        first = self.pairs(4, 1)[0]
        ax, ay, bx, by = first
        self.lua(f'ONE_WAY["{bx},{by}>{ax},{ay}"] = true')
        self.assertNotEqual(self.pairs(4, 1)[0], first)

    def test_no_pair_when_everything_is_walled(self):
        self.lua('for x = 90, 110 do for y = 90, 110 do if x ~= 100 or y ~= 100 then BUSY[x .. "," .. y] = true end end end')
        self.assertEqual(self.pairs(4), [])
        self.assertEqual(self.heard(6), [])

    def test_search_is_bounded(self):
        """Pire cas (aucune paire) : au plus (2r + 1)^2 cases a, (2 portée + 1)^2 cases b, deux lignes chacune."""
        self.lua('WALL_X, WALL_Y0, WALL_Y1 = 0, 0, 0 ONE_WAY = setmetatable({}, { __index = function() return true end })')
        self.assertEqual(self.pairs(4), [])
        calls = self.g.LINECLEAR
        self.assertGreater(calls, 0)
        self.assertLessEqual(calls, 13 * 13 * 9 * 9 * 2)


if __name__ == '__main__':
    unittest.main(verbosity=1)
