"""Fiches des voix côté serveur (E05-T02) : RS_Personas.lua et RadioSurvivor_Server.lua dans lupa.

    python RadioSurvivor/tests/test_personas_server.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) avec des doublures de l'API Java : dossier
Zomboid/Lua simulé dans un dossier temporaire (`getFileReader` UTF-8 comme le jeu, `getFileWriter`,
`listFilesInZomboidLuaDirectory`), dossier du mod réel (`listFilesInModDirectory`, `getModFileReader`), gestionnaire
de chaînes qui refuse une fréquence prise (`AddChannel`, `RemoveChannel`, `getRadioChannel`).
Couvre : fiches livrées valides (seul exemplaire, dans le mod : E05-T10), installation, migration unique de
l'ancienne option sandbox, rechargement à chaud (fréquence, état), conflits, fiche invalide qui garde l'ancienne version, fichier
retiré ou vidé, fréquence prise par une autre chaîne, heures d'écoute, le serveur de Walt (voix silencieuse,
fréquence non servie, appel spontané) et le routage par voix (E05-T03 : voice= de la demande, fréquences publiques
des voix active et silent, radio haut de gamme exigée, fréquence hors de portée de la radio, budget de la voix) et
le tirage des fréquences (E05-T07 : deux mondes neufs, redémarrage, monde recréé sous le même nom, collisions avec
l'alerte d'urgence, une autre chaîne ou une autre voix, plage modifiée à chaud, fichier de tirage abîmé), et la mise à
jour des fiches installées non modifiées (E05-T11 : empreintes, fiche modifiée gardée, installation antérieure reconnue
par une version livrée connue, fiche inconnue intacte, fichier d'empreintes abîmé), et l'émission depuis une radio posée
ou une autoradio (E06-T03 : micro à portée et même étage, place dans le véhicule, canal connu du serveur, ancien client).
Les cas d'E05-T02 et E05-T03 raisonnent sur une fréquence connue : Walt y reçoit sa fréquence d'exemple fixe 145.0
(WALT_FIXED) ; DeliveredVoicesServerTests et DrawTests utilisent les vraies fiches à plages.
Ne prouve pas l'API Java réelle : suite en jeu rs.personas.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
import beltradio_lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21'
LUA = MOD / 'media/lua'
BUNDLED = MOD / 'personas'
BOM_BYTES = bytes([0xEF, 0xBB, 0xBF])
PERSONAS_LUA = LUA / 'server/RadioSurvivor/RS_Personas.lua'
sys.path.insert(0, str(ROOT / 'bridge'))
import persona_store as store  # noqa: E402

# Fiche livrée de Walt avec sa fréquence d'exemple fixe à la place de sa plage de tirage (E05-T07).
WALT_FIXED = re.sub(rb'(?m)^frequency_range=.*$', b'frequencies=145.0', (BUNDLED / 'walt.txt').read_bytes())

STUBS = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
SIDE = "solo"
isClient = function() return SIDE == "client" end
isServer = function() return SIDE == "server" end
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
-- ZombRand(n) : 0 à n - 1, suite de Park-Miller reproductible depuis SEED (un monde = une graine).
SEED = 1
ZombRand = function(n) SEED = (SEED * 16807) % 2147483647 return SEED % n end
WORLD = "rstest_a"
getWorld = function() return { getWorld = function() return WORLD end,
    getGameMode = function() return "Multiplayer" end } end
GT_MODDATA = {}
getGameTime = function() return { getModData = function() return GT_MODDATA end } end
ENABLED = true
LEGACY = nil
getSandboxOptions = function() return {
    getOptionByName = function(_, name)
        if name == "RadioSurvivor.Enabled" then return { getValue = function() return ENABLED end } end
        if name == "RadioSurvivor.Frequency" and LEGACY ~= nil then
            return { getValue = function() return LEGACY end }
        end
        return nil
    end } end
SandboxVars = { RadioSurvivor = { Enabled = true, PlayerCooldown = 10, MaxPerHour = 60, SpontaneousCalls = true } }
function JLIST(t) return { size = function() return #t end, get = function(_, i) return t[i + 1] end } end

-- Gestionnaire de chaînes : fréquence -> chaîne ; AddChannel refuse une fréquence prise (sans overwrite).
-- Noms de chaînes de ZomboidRadio (envoyés aux clients à la connexion) : posés par AddChannel (addChannelName),
-- retirés par removeChannelName (ZomboidRadio.java:136-160).
ADDED, REMOVED, NAMES_REMOVED, CHANNEL_NAMES = 0, {}, {}, {}
MANAGER = { byFreq = {} }
function MANAGER:AddChannel(ch, overwrite)
    if overwrite or self.byFreq[ch.freq] == nil then
        ADDED = ADDED + 1 self.byFreq[ch.freq] = ch CHANNEL_NAMES[ch.freq] = ch.name
    end
end
function MANAGER:RemoveChannel(freq) self.byFreq[freq] = nil REMOVED[#REMOVED + 1] = freq end
function MANAGER:getRadioChannel(uuid)
    for _, ch in pairs(self.byFreq) do if ch.uuid == uuid then return ch end end
    return nil
end
-- RadioScriptManager.getChannelsList : ArrayList des chaînes (copiée à chaque appel côté Java).
function MANAGER:getChannelsList()
    local list = {}
    for _, ch in pairs(self.byFreq) do list[#list + 1] = ch end
    return JLIST(list)
end
function newChannel(name, freq, cat, uuid)
    local ch = { name = name, freq = freq, uuid = uuid, aired = {} }
    function ch:getAiringBroadcast() return self.airing end
    function ch:GetFrequency() return self.freq end
    function ch:getGUID() return self.uuid end
    function ch:GetName() return self.name end
    function ch:setAiringBroadcast(bc) self.airing = bc self.aired[#self.aired + 1] = bc.lines end
    return ch
end
DynamicRadioChannel = { new = function(name, freq, cat, uuid) return newChannel(name, freq, cat, uuid) end }
ChannelCategory = { Amateur = "Amateur" }
getZomboidRadio = function() return {
    getScriptManager = function() return MANAGER end,
    removeChannelName = function(_, f) NAMES_REMOVED[#NAMES_REMOVED + 1] = f CHANNEL_NAMES[f] = nil end,
    getChannelName = function(_, f) return CHANNEL_NAMES[f] end } end
TO_CLIENTS = {}
sendServerCommand = function(...) local a = { ... } TO_CLIENTS[#TO_CLIENTS + 1] = a end
function freqs()
    local out = {}
    for f in pairs(MANAGER.byFreq) do out[#out + 1] = f end
    table.sort(out)
    return out
end
"""


class Writer:
    def __init__(self, path: Path):
        self.path, self.parts = path, []

    def write(self, s):
        self.parts.append(s)

    def close(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_bytes(''.join(self.parts).encode('utf-8'))


class Reader:
    """getFileReader / getModFileReader : UTF-8, octets invalides en U+FFFD, BOM gardé, lignes de readLine."""

    def __init__(self, path: Path):
        self.lines = store.split_lines(path.read_bytes().decode('utf-8', errors='replace'))

    def readLine(self):  # noqa: N802 (nom Java)
        return self.lines.pop(0) if self.lines else None

    def close(self):
        pass


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Harness(unittest.TestCase):
    """Un dossier Zomboid/Lua temporaire, le dossier du mod (réel ou copie), une machine Lua."""

    mod_dir = MOD
    # Fiches livrées visibles par le serveur simulé : Walt seul par défaut (les cas ci-dessous raisonnent sur ses
    # fréquences) ; None = le vrai dossier du mod avec toutes ses fiches (DeliveredVoicesServerTests).
    bundled: tuple[str, ...] | None = ('walt.txt',)

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs-personas-'))
        if self.mod_dir is MOD and self.bundled is not None:
            self.mod_dir = self.tmp / 'mod'
            (self.mod_dir / 'personas').mkdir(parents=True)
            for name in self.bundled:
                target = self.mod_dir / 'personas' / name
                if name == 'walt.txt':
                    target.write_bytes(WALT_FIXED)
                else:
                    shutil.copyfile(BUNDLED / name, target)
        self.lua_dir = self.tmp / 'Lua'
        self.dir = self.lua_dir / 'batman_RadioSurvivor' / 'personas'
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.g = self.rt.globals()
        g.next = None  # absent de Kahlua
        self.rt.execute(STUBS)
        g.getFileReader = lambda name, create: self.reader(self.lua_dir / name)
        g.getFileWriter = lambda name, create, append: (
            Writer(self.lua_dir / name) if name.rsplit('.', 1)[-1] in ('ini', 'cfg', 'txt', 'log', 'json') else None)
        g.listFilesInZomboidLuaDirectory = lambda d: self.jlist(self.lua_dir / d)
        g.listFilesInModDirectory = lambda mod, d: self.jlist(self.mod_dir / d) if mod == 'batman_RadioSurvivor' else None
        g.getModFileReader = lambda mod, name, create: (
            self.reader(self.mod_dir / name) if mod == 'batman_RadioSurvivor' else None)
        paths = ';'.join((LUA / side).as_posix() + '/?.lua' for side in ('shared', 'server'))
        self.rt.execute(f'package.path = [[{paths};]] .. package.path')
        # Mod requis Belt Walkie-Talkie (batman_BeltRadio) : vraie partie partagée, chargée aussi par un serveur dédié
        # (BatmanRadioSupport.canTransmitWith, contrôle de la radio d'une phrase). SKIP si le dépôt est absent.
        if beltradio_lib.missing():
            self.skipTest(beltradio_lib.missing())
        self.rt.execute(f'package.path = [[{beltradio_lib.lua_path(("shared",))};]] .. package.path')
        self.rt.execute(beltradio_lib.SUPPORT_REQUIRE)
        self.P = self.rt.eval('require("RadioSurvivor/RS_Personas")')
        self.Const = self.rt.eval('require("RadioSurvivor/RadioSurvivor_Const")')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    @staticmethod
    def reader(path: Path):
        return Reader(path) if path.is_file() else None

    def jlist(self, folder: Path):
        names = sorted(f.name for f in folder.iterdir() if f.is_file()) if folder.is_dir() else []
        return self.g.JLIST(self.rt.table_from(names))

    # Aides
    def write(self, name: str, text: str | bytes):
        self.dir.mkdir(parents=True, exist_ok=True)
        (self.dir / name).write_bytes(text.encode('utf-8') if isinstance(text, str) else text)

    def sheet(self, vid: str, freqs: str = '145.0', extra: str = '') -> str:
        return f'format=1\nid={vid}\nname={vid.title()}\nfrequencies={freqs}\n{extra}[prompt]\nYou are {vid}.\n'

    def load_world(self, new_game=None):
        return self.rt.eval('function(P, n) return P.onLoadRadioScripts(MANAGER, n) end')(self.P, new_game)

    def new_manager(self):
        self.rt.execute('local old = MANAGER; MANAGER = { byFreq = {} };'
                        'for k, v in pairs(old) do if type(v) == "function" then MANAGER[k] = v end end')

    def after(self, ms: int):
        self.g.CLOCK = self.g.CLOCK + ms
        self.P.tick(self.g.CLOCK)

    def logs(self) -> list[str]:
        return lua_list(self.g.LOGS)

    def logs_with(self, text: str) -> list[str]:
        return [line for line in self.logs() if text in line]

    def freqs(self) -> list[int]:
        return [int(f) for f in lua_list(self.g.freqs())]

    def served(self, vid: str) -> list[int]:
        return [int(f) for f in lua_list(self.P.served(vid))]

    def talk(self) -> list[int]:
        # Fréquences tenues par les voix, côté autorité seulement (E05-T08 : plus annoncées aux clients).
        return [int(f) for f in lua_list(self.P.heldFrequencies())]


class BundledSheetTests(unittest.TestCase):

    def test_delivered_sheets_are_valid(self):
        # E05-T04 : les six voix, rien d'autre dans le dossier ; chacune valide (lecteur Python, mêmes règles que
        # RS_Persona.lua : tests/test_personas.py), UTF-8 sans BOM.
        bundled = sorted(p.name for p in BUNDLED.iterdir() if p.is_file())
        self.assertEqual(bundled, sorted(f'{vid}.txt' for vid in DeliveredVoicesServerTests.VOICES))
        for name in bundled:
            with self.subTest(name):
                raw = (BUNDLED / name).read_bytes()
                self.assertFalse(raw.startswith(BOM_BYTES), name)
                self.assertEqual(store.parse_bytes(raw, name[:-4]).id, name[:-4])

    def test_single_copy_of_the_sheets(self):
        # E05-T10 : plus de copie dans bridge/ (ni bridge/personas/, ni le prompt de secours bridge/persona.txt).
        self.assertFalse((ROOT / 'bridge/personas').exists())
        self.assertFalse((ROOT / 'bridge/persona.txt').exists())
        names = {f'{vid}.txt' for vid in DeliveredVoicesServerTests.VOICES}
        copies = sorted(p for p in ROOT.rglob('*.txt') if p.name in names and '.git' not in p.parts)
        self.assertEqual(copies, sorted(BUNDLED / name for name in names))

    def test_bundled_folder_outside_media(self):
        # Hors de media/ : le jeu n'indexe ni ne résout ce dossier comme une ressource.
        self.assertEqual(BUNDLED.parent, MOD)

    def test_lua_code_is_ascii_and_kahlua_safe(self):
        for path in (PERSONAS_LUA, LUA / 'server/RadioSurvivor_Server.lua'):
            for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                code = line.split('--', 1)[0]
                self.assertTrue(code.isascii(), f'{path.name}:{number} non ASCII outside a comment')
                self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(|\bgoto\b|loadstring', code),
                                  f'{path.name}:{number}')


class InstallTests(Harness):

    def test_first_load_installs_walt_and_creates_its_channel(self):
        self.assertTrue(self.load_world())
        self.assertEqual((self.dir / 'walt.txt').read_bytes(), WALT_FIXED)
        self.assertEqual(self.freqs(), [145000])
        self.assertEqual(self.served('walt'), [145000])
        self.assertEqual([int(f) for f in lua_list(self.g.NAMES_REMOVED)], [145000])
        self.assertEqual(self.talk(), [145000])
        self.assertEqual(len(self.logs_with('installed the bundled sheet')), 1)
        # Sans option sandbox lisible : une note pour l'admin, la fiche livrée telle quelle.
        self.assertEqual(len(self.logs_with('cannot be read any more')), 1)
        walt = self.P.get('walt')
        self.assertEqual((walt.state, walt.call_one_in, walt.call_text), ('active', 3, 'IGUI_RadioSurvivor_Call'))

    def test_admin_sheet_never_overwritten(self):
        admin = self.sheet('walt', '150.0')
        self.write('walt.txt', admin)
        self.load_world()
        self.load_world()  # second chargement du monde
        self.assertEqual((self.dir / 'walt.txt').read_text(encoding='utf-8'), admin)
        self.assertEqual(self.freqs(), [150000])
        self.assertEqual(self.logs_with('installed'), [])

    def test_invalid_admin_sheet_not_overwritten_either(self):
        self.write('walt.txt', 'broken\n')
        self.load_world()
        self.assertEqual((self.dir / 'walt.txt').read_text(encoding='utf-8'), 'broken\n')
        self.assertEqual(self.freqs(), [])
        self.assertEqual(len(self.logs_with('walt.txt refused, line 1: expected key=value or [prompt]')), 1)

    def test_no_network_broadcast_at_world_load_on_a_server(self):
        # Serveur dédié : OnLoadRadioScripts précède le démarrage du réseau ; sendServerCommand y lève une NPE
        # (GameServer.udpEngine nul, relevé au serveur dédié de test du 2026-10-09).
        self.g.SIDE = 'server'
        self.rt.execute('sendServerCommand = function() error("NPE udpEngine") end')
        self.assertTrue(self.load_world())
        self.assertEqual(self.talk(), [145000])
        self.assertEqual(self.freqs(), [145000])

    def test_disabled_does_nothing(self):
        self.g.ENABLED = False
        self.assertFalse(self.load_world())
        self.assertFalse(self.dir.exists())
        self.assertEqual(self.freqs(), [])

    def test_migration_copies_a_non_default_sandbox_value_once(self):
        self.g.LEGACY = 150.0
        self.load_world()
        lines = (self.dir / 'walt.txt').read_text(encoding='utf-8').splitlines()
        self.assertIn('frequencies=150.0', lines)
        self.assertNotIn('frequencies=145.0', lines)
        # Seule la ligne frequencies change.
        source = WALT_FIXED.decode('utf-8').splitlines()
        self.assertEqual([a for a, b in zip(lines, source) if a != b], ['frequencies=150.0'])
        self.assertEqual(self.freqs(), [150000])
        self.assertEqual(len(self.logs_with('migrated the sandbox frequency 150.0 MHz')), 1)
        # Ensuite seule la fiche compte : une autre valeur sandbox ne la touche plus.
        self.g.LEGACY = 160.0
        self.load_world()
        self.after(31000)
        self.assertIn('frequencies=150.0', (self.dir / 'walt.txt').read_text(encoding='utf-8').splitlines())
        self.assertEqual(len(self.logs_with('migrated')), 1)

    def test_migration_rounds_to_the_radio_step(self):
        self.g.LEGACY = 150.1
        self.load_world()
        self.assertIn('frequencies=150.2', (self.dir / 'walt.txt').read_text(encoding='utf-8').splitlines())

    def test_default_sandbox_value_keeps_the_delivered_sheet(self):
        self.g.LEGACY = 145.0
        self.load_world()
        self.assertEqual((self.dir / 'walt.txt').read_bytes(), WALT_FIXED)
        self.assertEqual(self.logs_with('migrated') + self.logs_with('cannot be read'), [])

    def test_legacy_value_from_sandbox_vars(self):
        self.rt.execute('SandboxVars.RadioSurvivor.Frequency = 99.0')
        self.assertEqual(self.P.legacyFrequency(), 99000)
        self.rt.execute('SandboxVars.RadioSurvivor.Frequency = nil')
        self.assertIsNone(self.P.legacyFrequency())


class FallbackTests(Harness):
    """Dossier du mod sans fiches livrées : erreur journalisée, essai de walt.txt quand même."""

    def setUp(self):
        self.mod_dir = Path(tempfile.mkdtemp(prefix='rs-mod-'))
        super().setUp()

    def tearDown(self):
        super().tearDown()
        shutil.rmtree(self.mod_dir, ignore_errors=True)

    def test_missing_bundled_folder(self):
        self.load_world()
        self.assertEqual(len(self.logs_with('no bundled persona sheet')), 1)
        self.assertEqual(len(self.logs_with('cannot read the bundled sheet personas/walt.txt')), 1)
        self.assertFalse((self.dir / 'walt.txt').exists())


class ReloadTests(Harness):

    def setUp(self):
        super().setUp()
        self.load_world()
        self.walt = (self.dir / 'walt.txt').read_text(encoding='utf-8')

    def edit_walt(self, old: str, new: str):
        self.assertIn(old, self.walt)
        self.walt = self.walt.replace(old, new)
        self.write('walt.txt', self.walt)

    def test_frequency_changed_while_running(self):
        self.edit_walt('frequencies=145.0', 'frequencies=150.0')
        self.after(29000)
        self.assertEqual(self.freqs(), [145000], 'reloaded before RELOAD_MS')
        self.after(1000)
        self.assertEqual(self.freqs(), [150000])
        self.assertEqual([int(f) for f in lua_list(self.g.REMOVED)], [145000])
        self.assertEqual(self.served('walt'), [150000])
        self.assertEqual(self.talk(), [150000])
        # E05-T08 : aucun envoi aux clients quand les fréquences changent (plus de liste annoncée).
        self.g.SIDE = 'server'
        self.edit_walt('frequencies=150.0', 'frequencies=150.0, 152.0')
        self.after(30000)
        self.assertEqual(self.freqs(), [150000, 152000])
        self.assertEqual(lua_list(self.g.TO_CLIENTS), [])

    def test_unchanged_file_is_not_parsed_again(self):
        before = len(self.logs())
        self.after(30000)
        self.after(30000)
        self.assertEqual(len(self.logs()), before)
        self.assertEqual(self.g.ADDED, 1)

    def test_states(self):
        self.edit_walt('state=active', 'state=silent')
        self.after(30000)
        self.assertEqual(self.P.get('walt').state, 'silent')
        self.assertEqual(self.freqs(), [145000], 'a silent voice keeps listening')
        self.assertEqual(self.talk(), [145000])
        self.edit_walt('state=silent', 'state=gone')
        self.after(30000)
        self.assertEqual(self.freqs(), [])
        self.assertEqual(self.talk(), [])
        self.assertEqual(self.P.get('walt').state, 'gone')
        self.edit_walt('state=gone', 'state=dead')
        self.after(30000)
        self.assertEqual(self.freqs(), [])
        self.edit_walt('state=dead', 'state=active')
        self.after(30000)
        self.assertEqual(self.freqs(), [145000])

    def test_invalid_edit_keeps_the_last_valid_version(self):
        self.edit_walt('frequencies=145.0', 'frequencies=145.1')
        self.after(30000)
        line = self.walt.splitlines().index('frequencies=145.1') + 1
        errors = self.logs_with('walt.txt refused')
        self.assertEqual(len(errors), 1)
        self.assertIn(f'line {line}: frequency 145.1 is not on the 0.2 MHz step of the radios', errors[0])
        self.assertIn('the previous valid version stays in service', errors[0])
        self.assertEqual(self.freqs(), [145000])
        self.assertEqual(self.P.get('walt').frequencies[1], 145000)
        self.after(30000)
        self.assertEqual(len(self.logs_with('walt.txt refused')), 1, 'same error logged again')
        self.edit_walt('frequencies=145.1', 'frequencies=146.0')
        self.after(30000)
        self.assertEqual(self.freqs(), [146000])

    def test_removed_and_emptied_files(self):
        self.write('zed.txt', self.sheet('zed', '160.0'))
        self.after(30000)
        self.assertEqual(self.freqs(), [145000, 160000])
        (self.dir / 'zed.txt').unlink()
        self.after(30000)
        self.assertEqual(self.freqs(), [145000])
        self.assertIsNone(self.P.get('zed'))
        self.write('walt.txt', b'')  # Lua ne peut rien supprimer : un fichier vidé retire la voix
        self.after(30000)
        self.assertEqual(self.freqs(), [])
        self.assertEqual(len(self.logs_with("voice 'walt' removed (empty file)")), 1)
        self.assertEqual(self.logs_with('walt.txt refused'), [])
        # Le fichier existe encore : la fiche livrée n'est pas recopiée au chargement suivant.
        self.load_world()
        self.assertEqual((self.dir / 'walt.txt').read_bytes(), b'')

    def test_other_files_ignored_and_bad_names_refused(self):
        self.write('notes.md', 'hello')
        self.write('walt.txt.bak', self.sheet('walt', '170.0'))
        self.write('Bob.txt', self.sheet('bob', '170.0'))
        self.after(30000)
        self.assertEqual(self.freqs(), [145000])
        self.assertEqual(len(self.logs_with("Bob.txt refused, line 2: id 'bob' does not match the file name")), 1)

    def test_frequency_conflict_oldest_sheet_keeps_it(self):
        self.write('abe.txt', self.sheet('abe', '145.0, 152.0'))  # avant walt dans l'ordre alphabétique
        self.after(30000)
        self.assertEqual(self.freqs(), [145000, 152000])
        self.assertEqual(self.P.voiceAt(145000), 'walt')
        self.assertEqual(self.served('abe'), [152000])
        warnings = self.logs_with("frequency 145.0 of voice 'abe' refused, already used by voice 'walt'")
        self.assertEqual(len(warnings), 1)
        self.after(30000)
        self.assertEqual(len(self.logs_with('of voice \'abe\' refused')), 1, 'conflict logged again')
        # Walt quitte la fréquence : abe la reçoit à la relecture.
        self.edit_walt('frequencies=145.0', 'frequencies=150.0')
        self.after(30000)
        self.assertEqual(self.P.voiceAt(145000), 'abe')
        self.assertEqual(self.served('abe'), [145000, 152000])
        self.assertEqual(self.freqs(), [145000, 150000, 152000])

    def test_conflict_at_first_load_alphabetical(self):
        self.write('zed.txt', self.sheet('zed', '145.0'))
        self.write('abe.txt', self.sheet('abe', '145.0'))
        self.new_manager()  # nouveau monde : nouveau gestionnaire de chaînes
        self.load_world()
        self.assertEqual(self.P.voiceAt(145000), 'abe')
        self.assertEqual(self.served('walt'), [])
        # Fréquences publiques de toutes les voix servies (E05-T03) : celle d'abe, Walt n'en a plus.
        self.assertEqual(self.talk(), [145000])

    def test_conflict_inside_one_reload_is_logged_with_the_owner(self):
        self.write('zed.txt', self.sheet('zed', '150.0'))
        self.write('yan.txt', self.sheet('yan', '150.0'))
        self.after(30000)
        self.assertEqual(self.P.voiceAt(150000), 'yan')
        self.assertEqual(len(self.logs_with("frequency 150.0 of voice 'zed' refused, already used by voice 'yan'")), 1)

    def test_frequency_taken_by_another_channel(self):
        self.rt.execute('MANAGER.byFreq[150000] = newChannel("Vanilla", 150000, "Radio", "vanilla-150")')
        self.edit_walt('frequencies=145.0', 'frequencies=150.0')
        self.after(30000)
        self.assertEqual(self.served('walt'), [])
        self.assertEqual(self.talk(), [])
        self.assertEqual(self.rt.eval('MANAGER.byFreq[150000].uuid'), 'vanilla-150')
        self.assertEqual(len(self.logs_with('already used by another radio channel')), 1)
        self.after(30000)
        self.assertEqual(len(self.logs_with('already used by another radio channel')), 1)
        self.rt.execute('MANAGER.byFreq[150000] = nil')
        self.after(30000)
        self.assertEqual(self.served('walt'), [150000])
        self.assertEqual(self.talk(), [150000])

    def test_lua_reload_adopts_existing_channels(self):
        self.rt.execute('package.loaded["RadioSurvivor/RS_Personas"] = nil')
        self.P = self.rt.eval('require("RadioSurvivor/RS_Personas")')
        added = self.g.ADDED
        self.after(0)
        self.assertEqual(self.g.ADDED, added, 'channel created twice')
        self.assertEqual(self.served('walt'), [145000])
        self.assertIsNotNone(self.P.channel(145000))

    def test_new_world_forgets_previous_channels(self):
        self.new_manager()
        self.load_world()
        self.assertEqual(self.freqs(), [145000])


def fingerprint(raw: bytes) -> str:
    """Empreinte d'une fiche comme RS_Personas.fingerprint : Adler-32 décimal des lignes de readLine jointes par \\n."""
    return str(zlib.adler32('\n'.join(store.split_lines(raw.decode('utf-8', errors='replace'))).encode('utf-8')))


def git_versions(name: str) -> dict[str, bytes]:
    """Versions livrées de personas/<name> dans l'historique git (commit -> octets) ; {} sans git."""
    path = f'Contents/mods/batman_RadioSurvivor/42.21/personas/{name}'
    try:
        commits = subprocess.run(['git', 'log', '--format=%h', '--', path], cwd=ROOT, capture_output=True,
                                 text=True, check=True).stdout.split()
        return {c: subprocess.run(['git', 'show', f'{c}:{path}'], cwd=ROOT, capture_output=True,
                                  check=True).stdout for c in commits}
    except (OSError, subprocess.CalledProcessError):
        return {}


def git_file(commit: str, name: str) -> bytes | None:
    """personas/<name> tel que livré au commit donné (avant E05-T07 : 24832ea), ou None sans git."""
    path = f'Contents/mods/batman_RadioSurvivor/42.21/personas/{name}'
    try:
        return subprocess.run(['git', 'show', f'{commit}:{path}'], cwd=ROOT, capture_output=True,
                              check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


class FingerprintTests(Harness):
    """E05-T11 : mise à jour des fiches installées non modifiées (empreintes), fiches de l'admin intactes."""

    bundled = ('walt.txt', 'gus.txt')

    @property
    def record_path(self) -> Path:
        return self.lua_dir / 'batman_RadioSurvivor' / 'personas-fingerprints.txt'

    def record(self) -> str:
        return self.record_path.read_text(encoding='utf-8')

    def deliver(self, name: str, raw: bytes):
        """Nouvelle version livrée par le mod (mise à jour du mod entre deux chargements du monde)."""
        (self.mod_dir / 'personas' / name).write_bytes(raw)

    def delivered(self, name: str) -> bytes:
        return (self.mod_dir / 'personas' / name).read_bytes()

    def installed(self, name: str) -> bytes:
        return (self.dir / name).read_bytes()

    def test_initial_copy_records_the_fingerprints(self):
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), WALT_FIXED)
        self.assertEqual(self.record(), f'RSFP1\ngus.txt {fingerprint(self.delivered("gus.txt"))}\n'
                                        f'walt.txt {fingerprint(WALT_FIXED)}\n')
        # Le fichier d'empreintes est hors du dossier des fiches : jamais lu comme une voix.
        self.assertEqual(self.record_path.parent, self.dir.parent)
        self.assertEqual(self.logs_with('refused'), [])
        # Second chargement sans changement : rien de réécrit, aucun journal de mise à jour.
        before = self.record_path.stat().st_mtime_ns
        self.load_world()
        self.assertEqual(self.record_path.stat().st_mtime_ns, before)
        self.assertEqual(self.logs_with('updated to the delivered version') + self.logs_with('modified by'), [])

    def test_lua_and_python_fingerprints_agree(self):
        lines = ['# Hélène, café', 'format=1', '', 'texte']
        self.assertEqual(self.P.fingerprint(self.rt.table_from(lines)),
                         fingerprint('\r\n'.join(lines).encode('utf-8') + b'\r\n'))

    def test_unmodified_sheet_is_updated(self):
        self.load_world()
        new = WALT_FIXED.replace(b'listen=always', b'listen=06:00-22:00')
        self.deliver('walt.txt', new)
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), new)
        self.assertEqual(len(self.logs_with("INFO: voice 'walt' updated to the delivered version")), 1)
        self.assertIn(f'walt.txt {fingerprint(new)}\n', self.record())
        self.assertEqual(len(lua_list(self.P.get('walt').listen)), 1)
        # Encore une version : la copie mise à jour est reconnue à son tour.
        newer = new.replace(b'listen=06:00-22:00', b'listen=07:00-22:00')
        self.deliver('walt.txt', newer)
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), newer)

    def test_modified_sheet_is_kept(self):
        self.load_world()
        admin = WALT_FIXED.replace(b'frequencies=145.0', b'frequencies=150.0')
        self.write('walt.txt', admin)
        record = self.record()
        self.deliver('walt.txt', WALT_FIXED.replace(b'listen=always', b'listen=06:00-22:00'))
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), admin)
        self.assertEqual(len(self.logs_with("WARNING: voice 'walt' modified by the admin, delivered version not"
                                            ' applied')), 1)
        self.assertEqual(self.record(), record)
        self.assertEqual(self.served('walt'), [150000])
        # Une fiche vidée (voix retirée par l'admin) est une modification : jamais recopiée.
        self.write('walt.txt', b'')
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), b'')

    def test_previous_install_recognised_by_an_old_delivered_version(self):
        # Installation d'avant E05-T11 (aucun fichier d'empreintes), fiche Walt de 24832ea (fréquence fixe 145.0) :
        # reconnue comme non modifiée, remplacée par la version livrée.
        old = git_file('24832ea', 'walt.txt')
        if old is None:
            self.skipTest('git history not available')
        self.assertIn(fingerprint(old), lua_list(self.P.KNOWN_DELIVERED.walt))
        self.write('walt.txt', old)
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), WALT_FIXED)
        self.assertEqual(len(self.logs_with("voice 'walt' updated to the delivered version")), 1)
        self.assertIn(f'walt.txt {fingerprint(WALT_FIXED)}\n', self.record())
        # La même fiche retouchée par l'admin n'est reconnue par aucune version livrée : gardée.
        self.write('walt.txt', old.replace(b'call_one_in=3', b'call_one_in=5'))
        self.record_path.write_bytes(b'')  # fichier vidé par l'admin : comme absent
        self.load_world()
        self.assertIn(b'call_one_in=5', self.installed('walt.txt'))
        self.assertEqual(len(self.logs_with("voice 'walt' modified by the admin")), 1)

    def test_unknown_admin_sheet_is_never_touched(self):
        admin = self.sheet('abe', '160.0')
        self.write('abe.txt', admin)
        self.load_world()
        self.assertEqual((self.dir / 'abe.txt').read_text(encoding='utf-8'), admin)
        self.assertNotIn('abe.txt', self.record())
        self.assertEqual([line for line in self.logs_with("'abe'") if 'updated' in line or 'modified' in line], [])

    def test_damaged_fingerprint_file_replaces_nothing(self):
        self.load_world()
        self.record_path.write_text('RSFP1\nwalt.txt not-a-number\n', encoding='utf-8')
        (self.dir / 'gus.txt').unlink()
        new = WALT_FIXED.replace(b'listen=always', b'listen=06:00-22:00')
        self.deliver('walt.txt', new)
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), WALT_FIXED, 'unmodified sheet replaced despite a damaged file')
        self.assertEqual(self.installed('gus.txt'), self.delivered('gus.txt'), 'absent sheet not copied')
        self.assertEqual(self.record(), 'RSFP1\nwalt.txt not-a-number\n', 'damaged file rewritten')
        self.assertEqual(len(self.logs_with('personas-fingerprints.txt is damaged (line 2: walt.txt not-a-number)')),
                         1)
        self.assertEqual(len(self.logs_with("voice 'walt' differs from its delivered version, kept")), 1)
        self.assertEqual(self.logs_with('updated to the delivered version'), [])
        # En-tête inconnu : abîmé aussi.
        self.record_path.write_text('walt.txt 1\n', encoding='utf-8')
        self.load_world()
        self.assertEqual(self.installed('walt.txt'), WALT_FIXED)
        self.assertEqual(len(self.logs_with('is damaged (line 1: expected RSFP1)')), 1)

    def test_migrated_walt_is_never_replaced(self):
        self.g.LEGACY = 150.0
        self.load_world()
        self.assertNotIn('walt.txt', self.record())
        self.deliver('walt.txt', WALT_FIXED.replace(b'listen=always', b'listen=06:00-22:00'))
        self.load_world()
        self.assertIn('frequencies=150.0', self.installed('walt.txt').decode('utf-8').splitlines())
        self.assertEqual(len(self.logs_with("voice 'walt' modified by the admin")), 1)


class KnownDeliveredTests(Harness):
    """KNOWN_DELIVERED connaît toutes les versions livrées : l'actuelle et celles de l'historique git."""

    def test_current_and_past_versions_are_known(self):
        known = {vid: set(lua_list(self.P.KNOWN_DELIVERED[vid])) for vid in DeliveredVoicesServerTests.VOICES}
        self.assertEqual(set(lua_list(self.rt.eval('function(t) local k = {} for n in pairs(t) do k[#k + 1] = n end '
                                                   'return k end')(self.P.KNOWN_DELIVERED))),
                         set(DeliveredVoicesServerTests.VOICES))
        for vid in DeliveredVoicesServerTests.VOICES:
            with self.subTest(vid):
                self.assertIn(fingerprint((BUNDLED / f'{vid}.txt').read_bytes()), known[vid],
                              f'add the fingerprint of the new delivered {vid}.txt to RS_Personas.KNOWN_DELIVERED')
                for commit, raw in git_versions(f'{vid}.txt').items():
                    self.assertIn(fingerprint(raw), known[vid], f'{vid}.txt of {commit}')
        if not git_versions('walt.txt'):
            self.skipTest('git history not available (current versions checked)')


class PreviousInstallTests(Harness):
    """Accepté si (E05-T11) : une installation d'avant E05-T07 (six fiches à fréquences fixes de 24832ea, sans
    fichier d'empreintes) reçoit les fiches à plages ; une fiche modifiée par l'admin est gardée."""

    bundled = None

    def test_fixed_frequency_install_receives_the_ranges(self):
        old = {vid: git_file('24832ea', f'{vid}.txt') for vid in DeliveredVoicesServerTests.VOICES}
        if None in old.values():
            self.skipTest('git history not available')
        for vid, raw in old.items():
            self.write(f'{vid}.txt', raw)
        admin = old['gus'].replace(b'\ncall_one_in=', b'\n# admin note\ncall_one_in=')
        self.assertNotEqual(admin, old['gus'])
        self.write('gus.txt', admin)
        self.load_world(True)
        for vid in DeliveredVoicesServerTests.VOICES:
            with self.subTest(vid):
                if vid == 'gus':
                    self.assertEqual(self.installed_bytes(vid), admin)
                else:
                    self.assertEqual(self.installed_bytes(vid), (BUNDLED / f'{vid}.txt').read_bytes())
                    self.assertEqual(lua_list(self.P.get(vid).frequencies), [])
        self.assertEqual(len(self.logs_with('updated to the delivered version')), 5)
        self.assertEqual(len(self.logs_with("voice 'gus' modified by the admin")), 1)
        self.assertEqual(self.logs_with('refused') + self.logs_with('ERROR'), [])

    def installed_bytes(self, vid: str) -> bytes:
        return (self.dir / f'{vid}.txt').read_bytes()


class ListeningTests(Harness):

    def listening(self, listen: str, minute: int) -> bool:
        sheet = store.parse_lines(self.sheet('case', extra=f'listen={listen}\n').splitlines(), 'case')
        table = self.rt.table_from({'listen': self.rt.table_from(
            [self.rt.table_from({'from': a, 'to': b}) for a, b in sheet.listen])})
        return bool(self.P.isListening(table, minute))

    def test_ranges(self):
        cases = [('06:00-12:00', 359, False), ('06:00-12:00', 360, True), ('06:00-12:00', 719, True),
                 ('06:00-12:00', 720, False), ('22:00-06:00', 1320, True), ('22:00-06:00', 1439, True),
                 ('22:00-06:00', 0, True), ('22:00-06:00', 359, True), ('22:00-06:00', 360, False),
                 ('22:00-06:00', 1319, False), ('06:00-07:00,20:00-21:00', 1230, True),
                 ('06:00-07:00,20:00-21:00', 600, False)]
        for listen, minute, expected in cases:
            with self.subTest(listen=listen, minute=minute):
                self.assertEqual(self.listening(listen, minute), expected)

    def test_always(self):
        self.assertTrue(self.P.isListening(self.rt.table_from({'listen': self.rt.table_from([])}), 0))


SERVER_STUBS = r"""
getText = function(k, a) return k .. (a and ("|" .. tostring(a)) or "") end
-- Traductions (E05-T05) : MISSING[k] = clé absente tant que Translator.loadFiles n'a pas été appelé (serveur MP,
-- traductions des mods lues avant les mods) ; ABSENT[k] = clé qui n'existe nulle part.
MISSING, ABSENT, RELOADS, LANG = {}, {}, 0, "EN"
getTextOrNull = function(k) if MISSING[k] or ABSENT[k] then return nil end return k end
Translator = { loadFiles = function() RELOADS = RELOADS + 1 MISSING = {} end,
    getLanguage = function() return { name = function() return LANG end } end }
RAND = {}
ZombRand = function(a, b) RAND[#RAND + 1] = a if b then return a end return 0 end
HOUR = 21
getGameTime = function() return {
    getYear = function() return 1993 end, getMonth = function() return 6 end, getDay = function() return 11 end,
    getHour = function() return HOUR end, getMinutes = function() return 5 end,
    getModData = function() return GT_MODDATA end } end
getWorld = function() return { getWorld = function() return "rstest" end,
    getGameMode = function() return "Multiplayer" end } end
RadioLine = { new = function(t) return t end }
RadioBroadCast = { new = function(id) local b = { id = id, lines = {} }
    b.AddRadioLine = function(self, l) table.insert(self.lines, l) end return b end }
instanceof = function(o, c) return type(o) == "table" and o.isRadio == true and c == "Radio" end
SENT = {}
sendServerCommand = function(...) local a = { ... }
    if #a == 4 then SENT[#SENT + 1] = a[3] .. (a[4].reason and (":" .. a[4].reason) or "") end end
HIGH_TIER, MAX_CHANNEL = false, 1000000
-- Talkie en main (DeviceData tel que le serveur le connaît ; canTransmitWith de Belt Walkie-Talkie).
local device = { getIsTwoWay = function() return true end, getIsHighTier = function() return HIGH_TIER end,
    getIsPortable = function() return true end, getIsTelevision = function() return false end,
    isNoTransmit = function() return false end, getIsTurnedOn = function() return true end,
    getIsBatteryPowered = function() return false end, getMicIsMuted = function() return false end,
    getMinChannelRange = function() return 200 end, getMaxChannelRange = function() return MAX_CHANNEL end }
RADIO = { isRadio = true, getDeviceData = function() return device end, getID = function() return 7 end,
    getDisplayName = function() return "Walkie" end }
PLAYER = { getPrimaryHandItem = function() return RADIO end, getSecondaryHandItem = function() return nil end,
    isAttachedItem = function() return false end,
    getClothingItem_Back = function() return nil end, getUsername = function() return "alice" end,
    getInventory = function() return nil end,
    getHoursSurvived = function() return 10 end,
    getDescriptor = function() return { getForename = function() return "A" end,
        getSurname = function() return "B" end } end }
getOnlinePlayers = function() return { size = function() return 1 end, get = function() return PLAYER end } end
function say(channel)
    SENT = {}
    for _, f in ipairs(Events.OnClientCommand.list) do
        f("RadioSurvivor", "talk", PLAYER, { text = "hello", itemId = 7, channel = channel })
    end
    return SENT
end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    rawset(t, k, e) return e end })
function fire(name, ...) for _, f in ipairs(Events[name].list) do f(...) end end
"""


class ServerHarness(Harness):
    """RadioSurvivor_Server.lua chargé sur un serveur MP simulé."""

    def setUp(self):
        super().setUp()
        self.g.SIDE = 'server'
        self.rt.execute(SERVER_STUBS)
        self.rt.execute((LUA / 'server/RadioSurvivor_Server.lua').read_text(encoding='utf-8'))
        self.g.fire('OnLoadRadioScripts', self.g.MANAGER, True)


class DeliveredVoicesServerTests(ServerHarness):
    """E05-T04 : les six fiches réellement livrées, installées et servies par le serveur (21:05, heure du jeu).
    E05-T07 : fréquences tirées dans leurs plages ; ZombRand de SERVER_STUBS rend 0, donc la plus basse libre de
    chaque plage, voix tirées dans leur ordre de chargement (alphabétique), à 1.0 MHz au moins les unes des autres."""

    bundled = None
    VOICES = {'walt': [130000], 'darlene': [115000], 'cody': [10000], 'whitaker': [75000],
              'nightowl': [88000, 109000], 'gus': [150200]}

    def requests(self) -> str:
        path = self.lua_dir / 'batman_RadioSurvivor' / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def test_six_sheets_installed_with_one_channel_per_frequency(self):
        for vid, khz in self.VOICES.items():
            with self.subTest(vid):
                self.assertEqual((self.dir / f'{vid}.txt').read_bytes(), (BUNDLED / f'{vid}.txt').read_bytes())
                self.assertEqual(self.served(vid), khz)
        everything = sorted(f for khz in self.VOICES.values() for f in khz)
        self.assertEqual(self.freqs(), everything)
        self.assertEqual(sorted(int(f) for f in lua_list(self.g.NAMES_REMOVED)), everything)
        self.assertEqual(self.talk()[0], 130000)  # Walt d'abord
        self.assertEqual(sorted(self.talk()), everything)  # whitaker (silent) compris
        self.assertEqual(self.P.get('whitaker').state, 'silent')
        self.assertEqual(len(self.logs_with('installed the bundled sheet')), len(self.VOICES))
        self.assertEqual(self.logs_with('refused') + self.logs_with('ERROR'), [])

    def test_routing_to_the_new_voices(self):
        for khz, vid in ((75000, 'whitaker'), (115000, 'darlene')):  # silencieuse ; hors des gardes
            with self.subTest(vid):
                self.assertEqual(lua_list(self.g.say(khz)), ['accepted', 'done'])
                self.assertNotIn(f'voice={vid}', self.requests())
        self.assertEqual(lua_list(self.g.say(109000)), ['accepted'])  # Night Owl écoute 19:00-22:00
        self.assertIn('voice=nightowl', self.requests())
        # Le pont reçoit l'identifiant de voix, jamais la fréquence tirée.
        self.assertNotIn('109000', self.requests())
        self.assertNotIn('109.0', self.requests())


class DrawTests(Harness):
    """E05-T07 : tirage des fréquences dans les plages, mémoire de la partie, collisions."""

    bundled = None
    RANGES = {'walt': [(130000, 149800)], 'darlene': [(115000, 129800)], 'cody': [(10000, 24800)],
              'whitaker': [(75000, 87800)], 'nightowl': [(88000, 107800), (109000, 114800)],
              'gus': [(150200, 199800)]}
    AEBS = 'EMRG-711984'

    def start(self, new_game, seed=1, world='rstest_a', aebs=None):
        """Chargement d'un monde : nouveau gestionnaire, chaînes vanilla fixes, AEBS de la partie (comme
        ISDynamicRadio.lua, abonné avant le mod : chaîne créée et fréquence dans la ModData de GameTime)."""
        self.new_manager()
        self.g.SEED, self.g.WORLD = seed, world
        self.rt.execute('GT_MODDATA = {}')
        for khz in (89400, 91200, 93200, 94200, 95000, 98000, 101200, 107600):
            self.rt.execute(f'MANAGER.byFreq[{khz}] = newChannel("Vanilla", {khz}, "Radio", "vanilla-{khz}")')
        if aebs is not None:
            self.rt.execute(f'MANAGER.byFreq[{aebs}] = newChannel("Automated Emergency Broadcast System", {aebs}, '
                            f'"Emergency", "{self.AEBS}")')
            self.rt.execute(f'GT_MODDATA.dynamicRadio = {{ {{ name = "Automated Emergency Broadcast System", '
                            f'freq = {aebs}, uuid = "{self.AEBS}" }} }}')
        self.load_world(new_game)
        return self.all_served()

    def all_served(self) -> dict[str, list[int]]:
        return {vid: self.served(vid) for vid in self.RANGES}

    def memory_files(self) -> list[Path]:
        return sorted((self.lua_dir / 'batman_RadioSurvivor').glob('frequencies-*.txt'))

    def check_draw(self, served: dict[str, list[int]], aebs=None):
        everything = []
        for vid, ranges in self.RANGES.items():
            with self.subTest(vid):
                self.assertEqual(len(served[vid]), len(ranges), served)
                for khz, (low, high) in zip(served[vid], ranges):
                    self.assertTrue(low <= khz <= high and khz % 200 == 0, (vid, khz))
            everything += [(khz, vid) for khz in served[vid]]
        everything.sort()
        for (a, va), (b, vb) in zip(everything, everything[1:]):
            self.assertGreaterEqual(b - a, 1000, f'{va} {a} and {vb} {b} closer than 1.0 MHz')
        taken = {89400, 91200, 93200, 94200, 95000, 98000, 101200, 107600, aebs}
        self.assertEqual({khz for khz, _ in everything} & taken, set())
        self.assertEqual(self.freqs(), sorted([khz for khz, _ in everything] + sorted(taken - {None})))

    def test_two_new_worlds_draw_different_frequencies(self):
        first = self.start(True, seed=11, aebs=98600)
        self.check_draw(first, aebs=98600)
        self.assertEqual(len(self.logs_with(' drew ')), 7)
        self.assertEqual(len(self.logs_with('(new game)')), 7)
        second = self.start(True, seed=977, world='rstest_b', aebs=101800)
        self.check_draw(second, aebs=101800)
        self.assertNotEqual(first, second)
        self.assertEqual(len(self.memory_files()), 2)  # un fichier par partie
        self.assertEqual(self.logs_with('ERROR') + self.logs_with('WARNING'), [])

    def test_restart_keeps_the_frequencies(self):
        first = self.start(True, seed=5, aebs=99000)
        memory = self.memory_files()[0]
        text = memory.read_text(encoding='utf-8')
        lines = text.splitlines()
        self.assertEqual(lines[0], 'RSFREQ1')
        self.assertEqual(len(lines), 8)  # six voix, deux plages pour le chroniqueur
        self.assertIn(f"walt 130000-149800 {first['walt'][0]}", lines)
        drawn = len(self.logs_with(' drew '))
        again = self.start(False, seed=4242, aebs=99000)  # autre graine : rien n'est tiré
        self.assertEqual(again, first)
        self.assertEqual(len(self.logs_with(' drew ')), drawn)
        self.assertEqual(memory.read_text(encoding='utf-8'), text)

    def test_world_recreated_under_the_same_name_draws_again(self):
        # Fichier de la partie qui survit à l'effacement du monde (base multiplayer.md) : ignoré si le monde est neuf.
        first = self.start(True, seed=5)
        second = self.start(True, seed=6)
        self.assertNotEqual(first, second)
        self.assertEqual(len(self.memory_files()), 1)
        self.assertIn(f"walt 130000-149800 {second['walt'][0]}",
                      self.memory_files()[0].read_text(encoding='utf-8').splitlines())
        self.assertEqual(self.start(False, seed=7), second)

    def test_old_game_without_memory_draws_once(self):
        # Partie créée avant E05-T07 : aucun fichier de tirage, monde non neuf.
        first = self.start(False, seed=3)
        self.check_draw(first)
        self.assertEqual(len(self.logs_with('no drawn frequencies remembered for this game yet')), 1)
        self.assertEqual(len(self.logs_with('(no frequency remembered for this range)')), 7)
        self.assertEqual(self.start(False, seed=8), first)

    def test_aebs_is_never_drawn(self):
        # Plage étroite qui contient l'AEBS : sur 40 mondes neufs, jamais la fréquence de l'AEBS.
        self.write('abe.txt', self.sheet('abe', extra='').replace('frequencies=145.0', 'frequency_range=100.0-101.0'))
        for seed in range(1, 41):
            with self.subTest(seed=seed):
                served = self.start(True, seed=seed, aebs=100400)
                self.assertNotEqual(self.served('abe'), [100400])
                self.assertEqual(len(self.served('abe')), 1)
                self.assertEqual(self.rt.eval(f'MANAGER.byFreq[100400].uuid'), self.AEBS)
                self.assertTrue(served)

    def test_aebs_only_in_the_mod_data(self):
        # Ordre inverse des abonnés (AEBS pas encore créée) : la ModData de GameTime suffit à l'éviter.
        self.write('abe.txt', self.sheet('abe').replace('frequencies=145.0', 'frequency_range=100.0-100.2'))
        self.start(True, aebs=100000)
        self.rt.execute('MANAGER.byFreq[100000] = nil')
        self.new_manager()
        self.rt.execute('GT_MODDATA = { dynamicRadio = { { name = "AEBS", freq = 100000, uuid = "EMRG-711984" } } }')
        self.load_world(True)
        self.assertEqual(self.served('abe'), [100200])

    def test_remembered_frequency_taken_at_load_is_drawn_again(self):
        first = self.start(True, seed=21)
        walt = first['walt'][0]
        # Au chargement suivant, une autre chaîne (AEBS, autre mod) occupe la fréquence mémorisée de Walt.
        self.new_manager()
        self.rt.execute(f'MANAGER.byFreq[{walt}] = newChannel("Other mod", {walt}, "Radio", "other-{walt}")')
        self.g.SEED = 22
        self.load_world(False)
        now = self.all_served()
        self.assertNotEqual(now['walt'], [walt])
        self.assertTrue(130000 <= now['walt'][0] <= 149800)
        self.assertEqual({k: v for k, v in now.items() if k != 'walt'}, {k: v for k, v in first.items() if k != 'walt'})
        logs = self.logs_with(f"voice 'walt' drew")
        self.assertIn(f"({walt / 1000:.1f} taken by the radio channel 'Other mod')", logs[-1])
        self.assertIn(f"walt 130000-149800 {now['walt'][0]}",
                      self.memory_files()[0].read_text(encoding='utf-8').splitlines())

    def test_voices_never_closer_than_the_gap(self):
        for vid in ('abe', 'bea', 'cid'):
            self.write(f'{vid}.txt', self.sheet(vid).replace('frequencies=145.0', 'frequency_range=100.0-104.0'))
        for seed in range(1, 31):
            with self.subTest(seed=seed):
                served = self.start(True, seed=seed)
                every = sorted(k for v in list(self.RANGES) + ['abe', 'bea', 'cid'] for k in self.served(v))
                self.assertEqual(len(every), 10)
                self.assertTrue(all(b - a >= 1000 for a, b in zip(every, every[1:])), every)
                self.assertEqual(len(served['nightowl']), 2)
                got = sorted(self.served(v)[0] for v in ('abe', 'bea', 'cid'))
                self.assertTrue(all(100000 <= k <= 104000 for k in got), got)
                self.assertTrue(got[1] - got[0] >= 1000 and got[2] - got[1] >= 1000, got)

    def test_remembered_voices_too_close_the_later_one_moves(self):
        self.write('abe.txt', self.sheet('abe').replace('frequencies=145.0', 'frequency_range=100.0-110.0'))
        self.write('zed.txt', self.sheet('zed').replace('frequencies=145.0', 'frequency_range=100.0-110.0'))
        self.start(True)
        memory = self.memory_files()[0]
        lines = [line for line in memory.read_text(encoding='utf-8').splitlines()
                 if not line.startswith(('abe ', 'zed '))]
        memory.write_text('\n'.join(lines + ['abe 100000-110000 105000', 'zed 100000-110000 105400']) + '\n',
                          encoding='utf-8')
        self.start(False, seed=9)
        self.assertEqual(self.served('abe'), [105000])
        self.assertGreaterEqual(abs(self.served('zed')[0] - 105000), 1000)
        self.assertEqual(len(self.logs_with("(105.4 too close to 105.0 of voice 'abe')")), 1)

    def test_fixed_frequency_of_another_voice_wins_over_a_draw(self):
        first = self.start(True, seed=2)
        walt = first['walt'][0]
        self.write('abe.txt', self.sheet('abe', f'{walt / 1000:.1f}'))
        self.after(30000)
        self.assertEqual(self.P.voiceAt(walt), 'abe')
        self.assertNotEqual(self.served('walt'), [walt])
        self.assertGreaterEqual(abs(self.served('walt')[0] - walt), 1000)

    def test_no_free_frequency_left(self):
        self.write('abe.txt', self.sheet('abe').replace('frequencies=145.0', 'frequency_range=100.0-100.2'))
        self.new_manager()
        self.rt.execute('MANAGER.byFreq[100000] = newChannel("A", 100000, "Radio", "a")')
        self.rt.execute('MANAGER.byFreq[100200] = newChannel("B", 100200, "Radio", "b")')
        self.load_world(True)
        self.assertEqual(self.served('abe'), [])
        self.assertEqual(len(self.logs_with("ERROR: voice 'abe': no free frequency left in 100.0-100.2")), 1)
        self.assertEqual(len(self.served('walt')), 1)

    def test_range_changed_while_running_draws_this_voice_only(self):
        first = self.start(True, seed=31)
        text = (self.dir / 'gus.txt').read_text(encoding='utf-8')
        self.write('gus.txt', text.replace('frequency_range=150.2-199.8', 'frequency_range=160.0-170.0'))
        self.after(30000)
        now = self.all_served()
        self.assertTrue(160000 <= now['gus'][0] <= 170000)
        self.assertEqual({k: v for k, v in now.items() if k != 'gus'}, {k: v for k, v in first.items() if k != 'gus'})
        self.assertEqual(len(self.logs_with("voice 'gus' drew")), 2)
        lines = self.memory_files()[0].read_text(encoding='utf-8').splitlines()
        self.assertIn(f"gus 160000-170000 {now['gus'][0]}", lines)
        self.assertFalse(any(line.startswith('gus 150200-199800') for line in lines))
        # Une seule des deux plages du chroniqueur changée : seule elle est tirée de nouveau.
        text = (self.dir / 'nightowl.txt').read_text(encoding='utf-8')
        self.write('nightowl.txt', text.replace('109.0-114.8', '109.0-113.8'))
        self.after(30000)
        self.assertEqual(self.served('nightowl')[0], first['nightowl'][0])
        self.assertTrue(109000 <= self.served('nightowl')[1] <= 113800)

    def test_fixed_frequency_sheet_drops_its_draw(self):
        self.start(True, seed=4)
        text = (self.dir / 'walt.txt').read_text(encoding='utf-8')
        self.write('walt.txt', text.replace('frequency_range=130.0-149.8', 'frequencies=145.0'))
        self.after(30000)
        self.assertEqual(self.served('walt'), [145000])
        lines = self.memory_files()[0].read_text(encoding='utf-8').splitlines()
        self.assertFalse(any(line.startswith('walt ') for line in lines))

    def test_damaged_memory_lines_are_ignored(self):
        first = self.start(True, seed=12)
        memory = self.memory_files()[0]
        lines = memory.read_text(encoding='utf-8').splitlines()
        lines = ['garbage' if line.startswith('cody ') else line for line in lines]
        lines = [line.replace(f" {first['walt'][0]}", ' 160000') if line.startswith('walt ') else line for line in lines]
        memory.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        now = self.start(False, seed=13)
        self.assertEqual(len([w for w in self.logs_with('WARNING') if 'frequencies-' in w and 'ignored' in w]), 2)
        self.assertTrue(10000 <= now['cody'][0] <= 24800)
        self.assertTrue(130000 <= now['walt'][0] <= 149800)
        self.assertEqual(now['gus'], first['gus'])

    def test_lua_reload_reads_the_memory(self):
        first = self.start(True, seed=17)
        added = self.g.ADDED
        self.rt.execute('package.loaded["RadioSurvivor/RS_Personas"] = nil')
        self.P = self.rt.eval('require("RadioSurvivor/RS_Personas")')
        self.g.SEED = 99
        self.after(0)
        self.assertEqual(self.all_served(), first)
        self.assertEqual(self.g.ADDED, added, 'channel created twice')

    def test_memory_file_is_per_game_and_server_side(self):
        self.start(True, seed=1, world='rstest_a')
        self.g.WORLD = 'rstest_b'
        names = [f.name for f in self.memory_files()]
        hexa = 'Multiplayer/rstest_a'.encode().hex()
        self.assertEqual(names, [f'frequencies-{hexa}.txt'])
        # Jamais de ModData globale ni d'envoi aux clients pour la mémoire du tirage.
        self.assertIsNone(self.rt.eval('GT_MODDATA.batman_RadioSurvivor'))


class ServerTests(ServerHarness):
    """RadioSurvivor_Server.lua : Walt lu depuis sa fiche."""

    def set_walt(self, old: str, new: str):
        text = (self.dir / 'walt.txt').read_text(encoding='utf-8')
        self.assertIn(old, text)
        self.write('walt.txt', text.replace(old, new))
        self.g.CLOCK = self.g.CLOCK + 30000
        self.g.fire('OnTickEvenPaused')

    def requests(self) -> str:
        path = self.lua_dir / 'batman_RadioSurvivor' / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def test_active_walt_answers_on_his_frequency(self):
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        self.assertIn('text=hello', self.requests())

    def test_frequency_not_served(self):
        # E05-T08 : sur une fréquence sans voix, la phrase part et personne ne répond ; aucun indice, rien au pont.
        self.assertEqual(lua_list(self.g.say(150000)), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())

    def test_client_without_channel_gets_silence(self):
        # Plus de repli sur la fréquence de Walt (E05-T08) : sans fréquence, personne ne répond.
        self.assertEqual(lua_list(self.g.say(None)), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())

    def test_silent_walt_hears_but_never_answers(self):
        self.set_walt('state=active', 'state=silent')
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())

    def test_gone_walt(self):
        self.set_walt('state=active', 'state=gone')
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())

    def test_outside_listening_hours(self):
        self.set_walt('listen=always', 'listen=06:00-12:00')
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted', 'done'])
        self.g.HOUR = 7
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])

    def test_frequency_change_moves_the_conversation(self):
        self.set_walt('frequencies=145.0', 'frequencies=150.0')
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted', 'done'])
        self.assertEqual(lua_list(self.g.say(150000)), ['accepted'])

    def call(self):
        """Heure de jeu, puis pont muet au-delà de CALL_TIMEOUT_MS : (tirages de chance, diffusions de Walt)."""
        self.g.RAND = self.rt.table_from([])
        self.g.fire('EveryHours')
        self.g.CLOCK = self.g.CLOCK + 31000
        self.g.fire('OnTick')
        channel = self.P.channel(self.P.served('walt')[1]) if self.served('walt') else None
        aired = lua_list(channel.aired) if channel is not None else []
        # ZombRand(100000, 999999) : identifiant de la demande, pas un tirage de chance.
        return [int(n) for n in lua_list(self.g.RAND) if n != 100000], [lua_list(lines) for lines in aired]

    def test_spontaneous_call_from_the_sheet(self):
        self.g.RAND = self.rt.table_from([])
        self.g.fire('EveryHours')
        # Demande au pont (kind=radio_call) : voix, date et langue, jamais la fréquence ; rien à l'antenne tant que le
        # pont peut répondre.
        text = self.requests()
        self.assertIn('kind=radio_call\nvoice=walt\ndate=1993-07-12 21:05\nlanguage=EN\n', text)
        for secret in ('khz', '145.0', '145000'):
            self.assertNotIn(secret, text)
        self.assertEqual(lua_list(self.P.channel(145000).aired), [])
        rand, aired = self.call()
        self.assertEqual(rand, [])  # appel déjà en attente pour Walt : pas de second tirage
        self.assertEqual(aired, [['<fzzt>', 'IGUI_RadioSurvivor_Call|145.0', '<szzt>']])
        self.assertEqual(int(self.g.RELOADS), 0)
        self.assertNotIn('kind=radio_call', self.requests())

    def call_language(self) -> str:
        """Langue de la demande d'appel spontané écrite au pont à la prochaine heure de jeu."""
        self.g.RAND = self.rt.table_from([])
        self.g.fire('EveryHours')
        found = re.findall(r'kind=radio_call\nvoice=walt\ndate=[^\n]*\nlanguage=([A-Z]+)\n', self.requests())
        self.assertEqual(len(found), 1, self.requests())
        return found[0]

    def test_call_language_option(self):
        """E05-T12 : option CallLanguage. Défaut (1) ou valeur inconnue : langue de l'autorité ; 2 = EN, 3 = FR, pour
        tous les joueurs, quelle que soit la langue du serveur."""
        for i, (option, server, expected) in enumerate(((None, 'EN', 'EN'), (1, 'EN', 'EN'), (1, 'FR', 'FR'),
                                                        (3, 'EN', 'FR'), (2, 'FR', 'EN'), (9, 'DE', 'DE'))):
            with self.subTest(option=option, server=server):
                if i:  # partie neuve : l'appel précédent de Walt est encore en attente
                    self.tearDown()
                    del self.mod_dir  # copie des fiches refaite par setUp
                    self.setUp()
                self.g.LANG = server
                self.rt.execute('SandboxVars.RadioSurvivor.CallLanguage = ' + ('nil' if option is None else str(option)))
                self.assertEqual(self.call_language(), expected)

    def test_call_language_leaves_player_answers_alone(self):
        """E05-T12 : une phrase de joueur ne porte aucune langue imposée (la voix répond dans celle de l'appelant)."""
        self.rt.execute('SandboxVars.RadioSurvivor.CallLanguage = 3')
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        text = self.requests()
        self.assertIn('text=hello', text)
        self.assertNotIn('language=', text)
        self.assertNotIn('kind=radio_call', text)

    def test_spontaneous_call_settings(self):
        self.set_walt('call_one_in=3', 'call_one_in=0')
        self.assertEqual(self.call(), ([], []))
        self.set_walt('call_one_in=0', 'call_one_in=7')
        self.set_walt('call_text=IGUI_RadioSurvivor_Call', 'call_text=IGUI_Other_Call')
        self.set_walt('frequencies=145.0', 'frequencies=150.0')
        rand, aired = self.call()
        self.assertEqual(rand, [7])
        self.assertEqual(aired, [['<fzzt>', 'IGUI_Other_Call|150.0', '<szzt>']])

    def test_bridge_text_of_the_call(self):
        """Texte écrit par le pont (LLM simulé) ; parasites seuls ou réponse vide : texte fixe de la fiche."""
        out = self.lua_dir / 'batman_RadioSurvivor' / 'responses.txt'
        for lines, expected in ((['Anyone listening? Walt here. Over.'], ['Anyone listening? Walt here. Over.']),
                                (['<fzzt>'], ['IGUI_RadioSurvivor_Call|145.0']),
                                ([], ['IGUI_RadioSurvivor_Call|145.0']),
                                (['One.', 'Two.', 'Three.', 'Four.'], ['One.', 'Two.', 'Three.'])):
            with self.subTest(lines=lines):
                self.P.channel(145000).airing = None
                self.g.fire('EveryHours')
                req = re.findall(r'(?m)^req=(.*-call)$', self.requests())[-1]
                out.write_text(f'resp={req}\n' + ''.join(f'line={x}\n' for x in lines) + 'end\n', encoding='utf-8')
                self.g.CLOCK = self.g.CLOCK + 1000
                self.g.fire('OnTick')
                self.assertEqual(lua_list(lua_list(self.P.channel(145000).aired)[-1]), ['<fzzt>'] + expected + ['<szzt>'])

    def test_call_text_on_a_server_reloads_the_mod_translations_once(self):
        # Serveur MP : traductions des mods absentes (getText rendrait la clé brute) ; rechargées une fois.
        self.rt.execute('MISSING = { IGUI_RadioSurvivor_Call = true }')
        _, aired = self.call()
        self.assertEqual(aired, [['<fzzt>', 'IGUI_RadioSurvivor_Call|145.0', '<szzt>']])
        self.assertEqual(int(self.g.RELOADS), 1)
        self.P.channel(145000).airing = None
        self.call()
        self.assertEqual(int(self.g.RELOADS), 1)
        self.assertEqual(len(self.logs_with('mod translations reloaded on the server')), 1)

    def test_unknown_call_text_skips_the_call(self):
        self.rt.execute('ABSENT = { IGUI_RadioSurvivor_Call = true }')
        self.assertEqual(self.call()[1], [])
        self.assertEqual(self.call()[1], [])
        self.assertEqual(int(self.g.RELOADS), 1)
        self.assertEqual(len(self.logs_with("no translation for call_text 'IGUI_RadioSurvivor_Call'")), 1)

    def test_call_dropped_when_the_hours_end_before_the_text(self):
        self.set_walt('listen=always', 'listen=20:00-22:00')
        self.g.fire('EveryHours')
        self.assertIn('kind=radio_call', self.requests())
        self.g.HOUR = 22
        self.g.CLOCK = self.g.CLOCK + 31000
        self.g.fire('OnTick')
        self.assertEqual(lua_list(self.P.channel(145000).aired), [])
        self.assertEqual(len(self.logs_with("call of voice 'walt' dropped")), 1)

    def test_no_call_while_someone_talks_to_the_voice(self):
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        self.assertEqual(self.call(), ([], []))

    def test_call_counts_in_the_global_cap(self):
        self.rt.execute('SandboxVars.RadioSurvivor.MaxPerHour = 1')
        self.g.fire('EveryHours')
        self.assertIn('kind=radio_call', self.requests())
        self.g.CLOCK = self.g.CLOCK + 31000
        self.g.fire('OnTick')
        self.P.channel(145000).airing = None
        self.assertEqual(lua_list(self.g.say(145000)), ['rejected:Busy'])
        self.assertEqual(self.call()[1], [['<fzzt>', 'IGUI_RadioSurvivor_Call|145.0', '<szzt>']])  # le premier

    def test_no_spontaneous_call_when_silent_or_out_of_hours(self):
        self.set_walt('state=active', 'state=silent')
        self.assertEqual(self.call(), ([], []))
        self.set_walt('state=silent', 'state=active')
        self.set_walt('listen=always', 'listen=06:00-12:00')
        self.assertEqual(self.call(), ([], []))

    def test_routing_by_frequency_names_the_voice(self):
        self.write('abe.txt', self.sheet('abe', '152.0'))
        self.after(30000)
        self.assertEqual(self.talk(), [145000, 152000])
        self.assertEqual(lua_list(self.g.say(152000)), ['accepted'])
        self.assertIn('voice=abe', self.requests())
        self.assertNotIn('voice=walt', self.requests())

    def test_walt_request_names_walt(self):
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        self.assertIn('caller=alice\nvoice=walt\nname=A B\n', self.requests())

    def test_silent_voice_frequencies_are_public(self):
        self.write('abe.txt', self.sheet('abe', '152.0', 'state=silent\n'))
        self.write('cid.txt', self.sheet('cid', '154.0', 'state=gone\n'))
        self.after(30000)
        self.assertEqual(self.talk(), [145000, 152000])
        self.assertEqual(lua_list(self.g.say(152000)), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())

    def test_high_tier_voice_needs_a_high_tier_radio(self):
        self.write('abe.txt', self.sheet('abe', '152.0', 'radio=high_tier\n'))
        self.after(30000)
        self.assertEqual(lua_list(self.g.say(152000)), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())
        self.g.HIGH_TIER = True
        self.assertEqual(lua_list(self.g.say(152000)), ['accepted'])
        self.assertIn('voice=abe', self.requests())

    def test_frequency_out_of_the_radio_range(self):
        # Hors de portée de la radio ou fréquence non entière : silence, comme une fréquence sans voix (E05-T08).
        self.g.MAX_CHANNEL = 144000
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted', 'done'])
        self.assertEqual(lua_list(self.g.say(145000.5)), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())

    def test_voice_budget_on_top_of_the_global_cap(self):
        self.write('abe.txt', self.sheet('abe', '152.0', 'budget=1\n'))
        self.after(30000)
        self.assertEqual(lua_list(self.g.say(152000)), ['accepted'])
        # Délai entre deux messages écoulé, demande précédente encore en attente : refus Waiting, pas Busy.
        self.g.CLOCK = self.g.CLOCK + 11000
        self.assertEqual(lua_list(self.g.say(152000)), ['rejected:Waiting'])
        # Demande précédente abandonnée (pont absent) : le budget de la voix reste consommé pour l'heure ; budget
        # épuisé = la voix se tait (E05-T08 : un refus « Busy » trahirait une voix sur la fréquence).
        self.g.CLOCK = self.g.CLOCK + 91000
        self.g.fire('OnTick')
        self.assertEqual(lua_list(self.g.say(152000)), ['accepted', 'done'])
        self.assertEqual(self.requests().count('voice=abe'), 0)
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        self.g.CLOCK = self.g.CLOCK + 3600000
        self.g.fire('OnTick')
        self.assertEqual(lua_list(self.g.say(152000)), ['accepted'])

    def test_frequency_request_from_a_client_is_ignored(self):
        # E05-T08 : plus de liste des fréquences ; la demande d'un client antérieur reste sans réponse.
        self.rt.execute('SENT = {}')
        self.g.fire('OnClientCommand', 'RadioSurvivor', 'frequencies', self.g.PLAYER, self.rt.table_from({}))
        self.assertEqual(lua_list(self.g.SENT), [])
        self.assertEqual(self.logs_with('ERROR'), [])

    def test_refusals_never_depend_on_the_frequency(self):
        # E05-T08 : attente, délai et plafond global sont jugés avant la fréquence, pareil avec ou sans voix.
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])
        self.assertEqual(lua_list(self.g.say(145000)), ['rejected:Waiting'])
        self.assertEqual(lua_list(self.g.say(150000)), ['rejected:Waiting'])
        self.g.CLOCK = self.g.CLOCK + 91000
        self.g.fire('OnTick')  # demande abandonnée (pont absent)
        self.rt.execute('SandboxVars.RadioSurvivor.PlayerCooldown = 200')
        self.assertEqual(lua_list(self.g.say(145000)), ['rejected:Cooldown'])
        self.assertEqual(lua_list(self.g.say(150000)), ['rejected:Cooldown'])
        self.rt.execute('SandboxVars.RadioSurvivor.PlayerCooldown = 0; SandboxVars.RadioSurvivor.MaxPerHour = 1')
        self.assertEqual(lua_list(self.g.say(145000)), ['rejected:Busy'])
        self.assertEqual(lua_list(self.g.say(150000)), ['rejected:Busy'])

    def test_spam_limit_per_player_on_every_frequency(self):
        # Limite du serveur : SPAM_MAX phrases par SPAM_WINDOW_MS, voix ou non ; fenêtre glissante.
        limit = int(self.Const.SPAM_MAX)
        for _ in range(limit):
            self.assertEqual(lua_list(self.g.say(150000)), ['accepted', 'done'])
        self.assertEqual(lua_list(self.g.say(150000)), ['rejected:Spam'])
        self.assertEqual(lua_list(self.g.say(145000)), ['rejected:Spam'])
        self.assertNotIn('req=', self.requests())
        self.g.CLOCK = self.g.CLOCK + int(self.Const.SPAM_WINDOW_MS)
        self.assertEqual(lua_list(self.g.say(145000)), ['accepted'])


class SpontaneousCallTests(ServerHarness):
    """E05-T05 : appels spontanés des six voix livrées, sur une longue simulation (pont absent : texte fixe).
    ZombRand reproductible (Park-Miller) ; heures de jeu pleines (minute 05 des stubs)."""

    bundled = None

    def setUp(self):
        super().setUp()
        self.rt.execute('''
            SEED = 7
            ZombRand = function(a, b)
                SEED = (SEED * 16807) % 2147483647
                if b then return a + SEED % (b - a) end
                return SEED % a
            end''')
        self.sheets = {vid: store.load_file(BUNDLED / f'{vid}.txt') for vid in DeliveredVoicesServerTests.VOICES}

    def requests(self) -> str:
        path = self.lua_dir / 'batman_RadioSurvivor' / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def listening(self, vid: str, hour: int) -> bool:
        minute = hour * 60 + 5
        ranges = self.sheets[vid].listen
        return not ranges or any((a <= minute < b) if a < b else (minute >= a or minute < b) for a, b in ranges)

    def simulate(self, days: int, talk_every: int = 0):
        """Heures de jeu successives (31 s réelles chacune) ; un joueur parle à Walt toutes les talk_every heures.
        Rend [(numéro de l'heure simulée, heure du jeu, voix)] des appels diffusés et l'instant de chaque demande acceptée (appels et réponses)."""
        calls, seen = [], {}
        hours = 0
        for _ in range(days):
            for hour in range(24):
                hours += 1
                self.g.HOUR = hour
                if talk_every and hours % talk_every == 0:
                    self.g.say(self.served('walt')[0])
                self.g.fire('EveryHours')
                for req in re.findall(r'(?m)^req=(.*)$', self.requests()):
                    seen.setdefault(req, int(self.g.CLOCK))
                for _ in range(2):
                    self.g.CLOCK = self.g.CLOCK + 15500
                    self.g.fire('OnTick')
                for khz, ch in self.P.state().channels.items():
                    channel = self.P.channel(khz)
                    if channel is not None and channel.airing is not None:
                        lines = lua_list(channel.airing.lines)
                        if any('_Call' in str(line) for line in lines):
                            calls.append((hours, hour, ch.id))
                        channel.airing = None
        return calls, sorted(seen.values())

    def test_calls_only_in_listening_hours_and_never_from_quiet_voices(self):
        calls, _ = self.simulate(days=30)
        voices = {vid for _, _, vid in calls}
        self.assertEqual(voices, {'walt', 'darlene', 'cody', 'gus'})
        for _, hour, vid in calls:
            self.assertTrue(self.listening(vid, hour), (hour, vid))
        # Une voix au plus par heure de jeu.
        slots = [n for n, _, _ in calls]
        self.assertEqual(len(slots), len(set(slots)))

    def test_silent_voice_never_calls(self):
        sheet = (self.dir / 'walt.txt').read_text(encoding='utf-8')
        self.write('walt.txt', sheet.replace('state=active', 'state=silent').replace('call_one_in=3', 'call_one_in=1'))
        self.after(30000)
        calls, _ = self.simulate(days=5)
        voices = {vid for _, _, vid in calls}
        self.assertTrue(voices and not voices & {'walt', 'whitaker', 'nightowl'}, voices)

    def test_option_off_means_no_call(self):
        self.rt.execute('SandboxVars.RadioSurvivor.SpontaneousCalls = false')
        self.assertEqual(self.simulate(days=3)[0], [])
        self.assertNotIn('radio_call', self.requests())

    def test_global_cap_never_exceeded(self):
        """Plafond MaxPerHour (heure réelle glissante) commun aux appels et aux réponses, jamais dépassé, alors que
        voix et joueur en demandent davantage (Walt appelle à chaque heure)."""
        self.rt.execute('SandboxVars.RadioSurvivor.MaxPerHour = 12')
        for vid in ('walt', 'darlene', 'cody', 'gus'):
            text = (self.dir / f'{vid}.txt').read_text(encoding='utf-8')
            self.write(f'{vid}.txt', re.sub(r'(?m)^call_one_in=.*$', 'call_one_in=1', text))
        self.after(30000)
        calls, times = self.simulate(days=10, talk_every=3)
        self.assertGreater(len(calls), 12)
        self.assertGreater(len(times), 24)
        for i, start in enumerate(times):
            window = [t for t in times[i:] if t - start < 3600000]
            self.assertLessEqual(len(window), 12, start)
        # Le plafond est atteint (sinon le test ne prouverait rien).
        self.assertTrue(any(len([t for t in times[i:] if t - s < 3600000]) == 12 for i, s in enumerate(times)))


DEV_LUA = ROOT / 'dev/batman_RadioSurvivorTests/42.21/media/lua'


class InGameSuiteTests(ServerHarness):
    """Suite en jeu rs.personas exécutée par le vrai moteur RST (asynchrone, horloge simulée)."""

    def run_suite(self):
        self.rt.execute(f'package.path = [[{(DEV_LUA / "shared").as_posix()}/?.lua;]] .. package.path')
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{(DEV_LUA / "shared/RST/suites/RS_Personas.lua").as_posix()}]])')
        self.assertTrue(self.rt.eval('RST.start("rs.personas", { attach = false, ctx = {} })'))
        for _ in range(400):
            if not self.rt.eval('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 500
            self.g.fire('OnTickEvenPaused')  # serveur dédié vide en pause : seul événement de tick
        report = self.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes(self):
        report, results = self.run_suite()
        # Réception par une radio tenue en main : solo seulement (le banc simule un serveur dédié).
        solo = 'channel created after loading reaches a radio held in hand (solo)'
        self.assertEqual(results.pop(solo)[0], 'SKIP')
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 6)
        # Nettoyage : fiche vidée (Lua ne supprime rien), voix et chaîne retirées, Walt intact.
        self.assertEqual((self.dir / 'rstest_probe.txt').read_bytes(), b'')
        self.assertIsNone(self.P.get('rstest_probe'))
        self.assertEqual(self.freqs(), [145000])
        self.assertEqual((self.dir / 'walt.txt').read_bytes(), WALT_FIXED)

    def test_suite_refused_outside_a_test_save(self):
        self.rt.execute('getWorld = function() return { getWorld = function() return "MyWorld" end } end')
        report, results = self.run_suite()
        self.assertTrue(all(v[0] == 'SKIP' for v in results.values()), results)
        self.assertFalse((self.dir / 'rstest_probe.txt').exists())

    def test_suite_detects_a_reload_that_keeps_old_channels(self):
        self.rt.execute('local m = MANAGER; m.RemoveChannel = function() end')
        _, results = self.run_suite()
        self.assertEqual(results['new sheet picked up by the periodic reload, then frequency and state changed'][0],
                         'FAIL')


WORLD_STUBS = r"""
-- E06-T03 : radios du monde côté serveur. instanceof selon le champ class des doublures (IsoWaveSignal...).
local radioInstanceof = instanceof
instanceof = function(o, c)
    if type(o) == "table" and o.class ~= nil then return o.class == c end
    return radioInstanceof(o, c)
end
-- DeviceData tel que le serveur le connaît : allumage et canal appliqués depuis les paquets d'état ; émettrice,
-- bornes, haut de gamme et portée du micro sauvegardés avec l'objet.
function newData(khz)
    local d = { on = true, twoWay = true, khz = khz or 145000, minCh = 200, maxCh = 1000000, highTier = false,
        micRange = 5, name = "Ham Radio" }
    function d:getIsTwoWay() return self.twoWay end
    function d:getIsTurnedOn() return self.on end
    function d:getChannel() return self.khz end
    function d:getMinChannelRange() return self.minCh end
    function d:getMaxChannelRange() return self.maxCh end
    function d:getIsHighTier() return self.highTier end
    function d:getMicRange() return self.micRange end
    function d:getDeviceName() return self.name end
    return d
end
SQUARES = {}
function square(x, y, z)
    local k = x .. "," .. y .. "," .. z
    local sq = SQUARES[k]
    if sq then return sq end
    sq = { x = x, y = y, z = z, list = {} }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getObjects()
        local list = self.list
        return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
    end
    SQUARES[k] = sq
    return sq
end
-- Pose un objet sur la case ; rend l'objet et son index.
function place(x, y, z, class, data)
    local sq = square(x, y, z)
    local o = { class = class or "IsoObject", data = data, sq = sq }
    function o:getDeviceData() return self.data end
    function o:getSquare() return self.sq end
    sq.list[#sq.list + 1] = o
    return o, #sq.list - 1
end
getCell = function() return { getGridSquare = function(_, x, y, z) return SQUARES[x .. "," .. y .. "," .. z] end } end
-- Véhicule : places occupées, BaseVehicle.getSeat (-1 hors du véhicule), pièces par identifiant.
function newVehicle(id, data)
    local part = { class = "VehiclePart", data = data }
    function part:getDeviceData() return self.data end
    local v = { id = id, seats = {}, parts = { Radio = part } }
    function v:getId() return self.id end
    function v:getSeat(chr) return self.seats[chr] or -1 end
    function v:getPartById(name) return self.parts[name] end
    return v
end
PLAYER.x, PLAYER.y, PLAYER.z, PLAYER.vehicle = 100.5, 200.5, 0, nil
PLAYER.getX = function(self) return self.x end
PLAYER.getY = function(self) return self.y end
PLAYER.getZ = function(self) return self.z end
PLAYER.getVehicle = function(self) return self.vehicle end
function talkWith(args)
    SENT = {}
    args.text = args.text or "hello"
    for _, f in ipairs(Events.OnClientCommand.list) do f("RadioSurvivor", "talk", PLAYER, args) end
    return SENT
end
"""


class WorldRadioServerTests(ServerHarness):
    """E06-T03 : émission depuis une radio posée (IsoWaveSignal) ou une autoradio (VehiclePart), contrôlée par le
    serveur. Joueur en 100.5, 200.5, 0 ; Walt sur 145.0 ; un talkie reste en main (RADIO) : il ne doit jamais servir
    de repli pour une phrase qui désigne un autre appareil."""

    def setUp(self):
        super().setUp()
        self.rt.execute(WORLD_STUBS)

    def requests(self) -> str:
        path = self.lua_dir / 'batman_RadioSurvivor' / 'requests.txt'
        return path.read_text(encoding='utf-8') if path.exists() else ''

    def world(self, x=102, y=200, z=0, khz=145000, before=0):
        """Radio posée (après `before` autres objets de la case) ; rend (données, index)."""
        self.rt.execute(f'for i = 1, {before} do place({x}, {y}, {z}) end')
        data, index = self.rt.execute(f'local d = newData({khz}); local _, i = place({x}, {y}, {z}, "IsoWaveSignal", d);'
                                      ' return d, i')
        return data, int(index)

    def say_world(self, x=102, y=200, z=0, index=0, channel=145000):
        args = {'source': 'world', 'x': x, 'y': y, 'z': z, 'index': index}
        if channel is not None:
            args['channel'] = channel
        return lua_list(self.g.talkWith(self.rt.table_from(args)))

    def test_world_radio_in_range_answers(self):
        self.world()
        self.assertEqual(self.say_world(), ['accepted'])
        self.assertIn('voice=walt', self.requests())
        self.assertIn('radio=Ham Radio', self.requests())

    def test_world_radio_too_far_or_on_another_floor(self):
        # Distance entière < MicRange (5), comme ZomboidRadio.java:519 : 4 cases passent, 5 non.
        self.world(x=104)
        self.assertEqual(self.say_world(x=104), ['accepted'])
        self.g.CLOCK = self.g.CLOCK + 200000
        self.g.fire('OnTick')
        self.world(x=105)
        self.assertEqual(self.say_world(x=105), ['rejected:TooFar'])
        self.world(z=1)
        self.assertEqual(self.say_world(z=1), ['rejected:TooFar'])
        self.assertNotIn('req=', self.requests())

    def test_mic_range_of_the_device(self):
        data, _ = self.world(x=108)
        self.assertEqual(self.say_world(x=108), ['rejected:TooFar'])
        data.micRange = 10
        self.assertEqual(self.say_world(x=108), ['accepted'])

    def test_world_radio_not_found(self):
        self.assertEqual(self.say_world(), ['rejected:NoRadio'])          # case absente
        self.rt.execute('place(102, 200, 0)')
        self.assertEqual(self.say_world(), ['rejected:NoRadio'])          # aucune radio sur la case
        self.assertEqual(lua_list(self.g.talkWith(self.rt.table_from({'source': 'world', 'x': 'a'}))),
                         ['rejected:NoRadio'])
        self.assertEqual(lua_list(self.g.talkWith(self.rt.table_from({'source': 'other'}))), ['rejected:NoRadio'])

    def test_stale_index_falls_back_on_the_only_radio(self):
        _, index = self.world(before=2)
        self.assertEqual(index, 2)
        self.assertEqual(self.say_world(index=0), ['accepted'])

    def test_stale_index_with_two_radios_is_refused(self):
        self.world(before=1)
        self.world()
        self.assertEqual(self.say_world(index=0), ['rejected:NoRadio'])
        self.assertEqual(self.say_world(index=2), ['accepted'])

    def test_receiver_and_off_radio(self):
        data, _ = self.world()
        data.twoWay = False
        self.assertEqual(self.say_world(), ['rejected:NoRadio'])
        data.twoWay = True
        data.on = False
        self.assertEqual(self.say_world(), ['rejected:Off'])

    def test_refusals_come_before_the_frequency(self):
        # Ordre d'E05-T08 : même refus sur une fréquence avec ou sans voix.
        data, _ = self.world(x=110)
        self.assertEqual(self.say_world(x=110), ['rejected:TooFar'])
        data.khz = 150000
        self.assertEqual(self.say_world(x=110, channel=150000), ['rejected:TooFar'])

    def test_server_channel_wins(self):
        data, _ = self.world()
        # Client sans fréquence : canal connu du serveur.
        self.assertEqual(self.say_world(channel=None), ['accepted'])
        self.g.CLOCK = self.g.CLOCK + 200000
        self.g.fire('OnTick')
        # Fréquence annoncée différente du canal du serveur (réglage pas encore arrivé, client modifié) : silence.
        data.khz = 150000
        self.assertEqual(self.say_world(channel=145000), ['accepted', 'done'])
        self.assertEqual(self.requests().count('req='), 0)

    def test_channel_out_of_the_radio_bounds_is_silence(self):
        data, _ = self.world()
        data.maxCh = 144000
        self.assertEqual(self.say_world(), ['accepted', 'done'])
        self.assertNotIn('req=', self.requests())

    def test_high_tier_voice_judged_on_the_world_radio(self):
        self.write('abe.txt', self.sheet('abe', '152.0', 'radio=high_tier\n'))
        self.after(30000)
        data, _ = self.world(khz=152000)
        self.g.HIGH_TIER = True  # talkie en main haut de gamme : sans effet sur la radio posée
        self.assertEqual(self.say_world(channel=152000), ['accepted', 'done'])
        data.highTier = True
        self.assertEqual(self.say_world(channel=152000), ['accepted'])
        self.assertIn('voice=abe', self.requests())

    # Autoradio ------------------------------------------------------------------------------------------

    def car(self, seat=0, two_way=True, on=True, vid=17):
        data, vehicle = self.rt.execute(f'local d = newData(145000); d.twoWay = {str(two_way).lower()}; '
                                        f'd.on = {str(on).lower()}; local v = newVehicle({vid}, d); return d, v')
        if seat is not None:
            vehicle.seats[self.g.PLAYER] = seat
            self.g.PLAYER.vehicle = vehicle
        return data, vehicle

    def say_car(self, vid=17, part='Radio', channel=145000):
        return lua_list(self.g.talkWith(self.rt.table_from(
            {'source': 'vehicle', 'vehicleId': vid, 'part': part, 'channel': channel})))

    def test_driver_and_passenger_answer(self):
        for seat in (0, 1, 3):
            with self.subTest(seat=seat):
                self.car(seat=seat)
                self.assertEqual(self.say_car(), ['accepted'])
                self.g.CLOCK = self.g.CLOCK + 200000
                self.g.fire('OnTick')
        self.assertEqual(self.requests().count('voice=walt'), 0)  # demandes abandonnées : file vidée

    def test_outside_the_vehicle_is_refused(self):
        _, vehicle = self.car(seat=None)
        self.assertEqual(self.say_car(), ['rejected:NotInVehicle'])
        # Dans le véhicule mais compté hors des places (getSeat = -1) : refusé.
        self.g.PLAYER.vehicle = vehicle
        self.assertEqual(self.say_car(), ['rejected:NotInVehicle'])
        # Assis dans un autre véhicule que celui annoncé.
        self.car(seat=1, vid=18)
        self.assertEqual(self.say_car(vid=17), ['rejected:NotInVehicle'])

    def test_receiver_car_radio_or_missing_part(self):
        self.car(two_way=False)
        self.assertEqual(self.say_car(), ['rejected:NoRadio'])
        self.car()
        self.assertEqual(self.say_car(part='GloveBox'), ['rejected:NoRadio'])
        self.car(on=False)
        self.assertEqual(self.say_car(), ['rejected:Off'])

    def test_car_radio_uses_the_server_channel(self):
        data, _ = self.car()
        data.khz = 150000
        self.assertEqual(self.say_car(channel=145000), ['accepted', 'done'])
        self.assertEqual(self.say_car(channel=150000), ['accepted', 'done'])  # fréquence sans voix
        data.khz = 145000
        self.assertEqual(self.say_car(channel=None), ['accepted'])

    def test_old_client_without_the_new_fields(self):
        # Client antérieur à E06-T03 : { text, itemId, channel } ; même comportement qu'avant (radio en main).
        self.world(x=150)
        self.assertEqual(lua_list(self.g.talkWith(self.rt.table_from({'itemId': 7, 'channel': 145000}))),
                         ['accepted'])
        self.assertIn('radio=Walkie', self.requests())
        self.g.CLOCK = self.g.CLOCK + 200000
        self.g.fire('OnTick')
        self.assertEqual(lua_list(self.g.talkWith(self.rt.table_from({'itemId': 8, 'channel': 145000}))),
                         ['rejected:NoRadio'])


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    unittest.main(verbosity=1)
