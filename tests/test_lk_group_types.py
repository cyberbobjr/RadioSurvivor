"""Tests hors jeu des types de groupes Living Knox en données (LK08-T02) : LK_GroupTypes.lua et Data/LK_Type_*.lua.

    python RadioSurvivor/tests/test_lk_group_types.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo). Les fichiers de données sont chargés comme le jeu les
exécute (balayage de media/lua/shared, LuaManager.LoadDirBase) : un par un, chacun tirant le registre par require.
Un type supplémentaire est écrit dans un dossier media/lua temporaire (autre mod) : il s'ajoute sans aucun code.
Contrôle statique : armes vanilla admises relevées dans media/scripts 42.21, avec un AttachmentType connu de
LK_Equipment ; clés de traduction des noms présentes en anglais et en français.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LUA, Harness  # noqa: E402

SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua')
DATA = ('shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
        'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'
VANILLA_SCRIPTS = pz_paths.media_dir() / 'scripts'
TRANSLATE = LUA / 'shared' / 'Translate'

WORLD = r'''
getWorld = function()
    return { getWorld = function() return 'rstest_types' end, getGameMode = function() return 'Multiplayer' end }
end
'''

# Type supplémentaire livré par « un autre mod » : un seul fichier de données, aucun code.
NOMADS = r'''-- Another mod: one data file, no code.
require "LivingKnox/LK_GroupTypes"
if LivingKnox and LivingKnox.GroupTypes then
    LivingKnox.GroupTypes.register({
        format = 1, id = "nomads", nameKey = "IGUI_OtherMod_Nomads", size = { min = 3, max = 5 }, hostility = 30,
        home = "forest", morale = 55, needs = { food = 30, medical = 40, ammo = 20 },
        roles = { scout = { weight = 3, behaviours = { "scout", "forage" } },
                  worker = { weight = 1, behaviours = { "chores", "fish" } } },
        profiles = { { id = "walker", role = "scout", weight = 5, female = true, looks = { "womanTanBob" },
                       weapons = { "Base.Machete", "OtherMod.Spear" } },
                     { id = "angler", role = "worker", weight = 2, outfits = { "Generic04" } } },
    })
end
'''

# Définition valide de référence (Lua) : chaque cas invalide en change un champ.
GOOD = '''{ format = 1, id = "test_%s", nameKey = "IGUI_T", size = { min = 2, max = 4 }, hostility = 5,
    home = "building", morale = 50, needs = { food = 1, medical = 2, ammo = 3 },
    roles = { fighter = { weight = 2, behaviours = { "guard" } } },
    profiles = { { id = "p", role = "fighter", weight = 1 } } }'''

INVALID = {
    'd.colour = "red"': 'unknown field colour',
    'd.format = 3': 'unknown format 3 (this version reads 1 to 2)',
    # E08-T06: transmitter fields exist in format 2 only; booleans only.
    'd.homeRadio = true': 'unknown field homeRadio',
    'd.profiles[1].radio = true': 'profile p: unknown field radio',
    'd.format = 2; d.homeRadio = 1': 'homeRadio must be a boolean',
    'd.format = 2; d.profiles[1].radio = "yes"': 'profile p: radio must be a boolean',
    'd.id = "Bad-Id"': 'bad id',
    'd.nameKey = "no spaces allowed"': 'bad nameKey',
    'd.size = { min = 5, max = 4 }': 'size must be { min, max } integers with 1 <= min <= max <= 32',
    'd.size = { min = 1, max = 33 }': 'size must be { min, max } integers with 1 <= min <= max <= 32',
    'd.hostility = 101': 'hostility must be an integer from 0 to 100',
    'd.home = "boat"': 'home must be building or forest',
    'd.morale = 2.5': 'morale must be an integer from 0 to 100',
    'd.needs.water = 4': 'unknown need water',
    'd.needs.ammo = nil': 'need ammo must be 0..100',
    'd.roles.king = { weight = 1, behaviours = { "guard" } }': 'unknown role king',
    'd.roles.fighter.weight = 0': 'role fighter: weight must be an integer from 1 to 100',
    'd.roles.fighter.behaviours = { "guard", "dance" }': 'role fighter behaviours entry 2: unknown dance',
    'd.roles.fighter.behaviours = { "guard", "guard" }': 'role fighter behaviours entry 2: duplicate guard',
    'd.roles.fighter.behaviours = {}': 'role fighter behaviours is not a list of 1 to 16',
    'd.roles.scout = { weight = 1, behaviours = { "scout" } }': 'role scout has no profile',
    'd.roles = {}': 'roles is empty',
    'd.profiles = {}': 'profiles is not a list of 1 to 32',
    'd.profiles[1].role = "medic"': 'profile p: role medic is not a role of this type',
    'd.profiles[1].weight = 1001': 'profile p: weight must be an integer from 1 to 1000',
    'd.profiles[1].hat = true': 'profile p: unknown field hat',
    'd.profiles[2] = { id = "p", role = "fighter", weight = 1 }': 'duplicate profile p',
    'd.profiles[1].looks = { "manFairBeard", "nobody" }': 'profile p looks entry 2: unknown nobody',
    'd.profiles[1].female = true; d.profiles[1].looks = { "manFairBeard" }':
        'profile p looks entry 1: look manFairBeard does not match female',
    'd.profiles[1].outfits = { "Bandit" }': 'profile p outfits entry 1: unknown Bandit',
    'd.profiles[1].weapons = { "Base.Spoon" }': 'profile p weapons entry 1: vanilla weapon not allowed Base.Spoon',
    'd.profiles[1].weapons = { "Axe" }': 'profile p weapons entry 1: bad item type Axe',
    'd.profiles[1].traits = { { id = "smoker", chance = 0 } }':
        'profile p trait 1: chance must be an integer from 1 to 100',
    'd.profiles[1].traits = { { id = "pyromaniac", chance = 5 } }': 'profile p trait 1: unknown trait pyromaniac',
    'd.profiles[1].max = 3': 'profiles cannot fill size.max (3 < 4)',
    'd = "settlers"': 'definition is not a table',
}


def lua_files_ascii(path: Path) -> list[str]:
    """Lignes de code (hors commentaires) contenant un caractère non ASCII (lexeur Kahlua : U+FFFD)."""
    bad = []
    for n, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        code = line.split('--', 1)[0]
        if any(ord(c) > 127 for c in code):
            bad.append(f'{path.name}:{n}')
    return bad


class Base(unittest.TestCase):
    mode = 'mp'
    extra_root: Path | None = None

    def setUp(self):
        self.h = Harness(mode=self.mode, lua_roots=[self.extra_root] if self.extra_root else ())
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        self.machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')

    def tearDown(self):
        self.h.close()

    def boot(self, extra=(), before=()):
        """Ordre du jeu : fichiers shared (données comprises) sur chaque machine, puis server."""
        for m in self.machines:
            self.h.load(m, WORLD)
            for path in before:
                self.h.load(m, path)
            for path in SHARED + DATA + tuple(extra):
                self.h.load(m, path)
            self.h.load(m, SERVER)

    def ev(self, code, m=None):
        return self.h.eval(m or self.srv, code)

    def run_lua(self, code, m=None):
        return self.h.load(m or self.srv, code)

    def ids(self, m=None):
        return list(self.ev('LivingKnox.GroupTypes.ids()', m).values())

    def lk_errors(self, m=None):
        return [line for line in self.h.logs(m or self.srv) if line.startswith('[LivingKnox] ERROR')]


class BuiltinTypes(Base):
    def test_three_types_registered_everywhere(self):
        self.boot()
        for m in self.machines:
            self.assertEqual(self.ids(m), ['neutrals', 'raiders', 'settlers'], m)
            self.assertEqual(self.lk_errors(m), [], m)
            self.assertEqual(self.ev('#LivingKnox.GroupTypes.refused()', m), 0)
            self.assertEqual(self.h.errors(m), [])

    def test_values_of_the_shipped_types(self):
        self.boot()
        rows = {}
        for tid in ('settlers', 'raiders', 'neutrals'):
            t = self.ev(f'LivingKnox.GroupTypes.get("{tid}")')
            rows[tid] = (t.size.min, t.size.max, t.hostility, t.home, t.nameKey, sorted(t.roles.keys()))
            for p in t.profiles.values():
                for w in (p.weapons or {}).values():
                    self.assertTrue(w.startswith('Base.'), w)
        self.assertEqual(rows['settlers'], (4, 8, 10, 'building', 'IGUI_LK_GroupType_settlers',
                                            ['deputy', 'fighter', 'medic', 'scout', 'worker']))
        self.assertEqual(rows['raiders'], (4, 8, 90, 'forest', 'IGUI_LK_GroupType_raiders',
                                           ['breaker', 'deputy', 'fighter', 'scout', 'worker']))
        self.assertEqual(rows['neutrals'], (4, 6, 45, 'building', 'IGUI_LK_GroupType_neutrals',
                                            ['deputy', 'fighter', 'medic', 'scout', 'worker']))
        # Rôles et comportements I1.2 / I6.9 : le casseur peut forcer une barricade, l'éclaireur explore.
        self.assertIn('breach', list(self.ev('LivingKnox.GroupTypes.get("raiders").roles.breaker.behaviours')
                                     .values()))
        self.assertIn('scout', list(self.ev('LivingKnox.GroupTypes.get("settlers").roles.scout.behaviours')
                                    .values()))
        # Lecture = copie.
        self.run_lua('LivingKnox.GroupTypes.get("raiders").hostility = 0')
        self.assertEqual(self.ev('LivingKnox.GroupTypes.get("raiders").hostility'), 90)

    def test_groups_accept_registered_types_only(self):
        self.boot()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        for tid in ('settlers', 'raiders', 'neutrals'):
            self.assertEqual(self.ev(f'LivingKnox.Groups.create({{ type = "{tid}", name = "G" }}).type'), tid)
        self.assertEqual(self.run_lua('return LivingKnox.Groups.create({ type = "nomads", name = "N" })'),
                         (None, 'unknown type nomads'))
        g = self.ev('LivingKnox.Groups.list()[3]')
        self.assertEqual(self.run_lua(f'return LivingKnox.Groups.addMember("{g}", {{ role = "breaker" }})'), 'm-1')

    def test_constants_match_the_group_registry(self):
        self.boot()
        self.assertEqual(self.ev('LivingKnox.GroupTypes.SIZE_MAX'), self.ev('LivingKnox.Groups.MAX_MEMBERS'))
        self.assertEqual(list(self.ev('LivingKnox.GroupTypes.NEEDS').values()),
                         list(self.ev('LivingKnox.Groups.NEEDS').values()))
        # Rôles LK08-T01 gardés dans le même ordre (succession des groupes relus inchangée), rôles nouveaux en fin.
        roles = list(self.ev('LivingKnox.Config.GROUP_ROLES').values())
        self.assertEqual(roles[:5], ['deputy', 'fighter', 'scout', 'medic', 'worker'])
        self.assertEqual(roles[5:], ['breaker'])
        self.assertIsNone(self.ev('LivingKnox.Config.GROUP_TYPES'))


class NewTypeWithoutCode(Base):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.mkdtemp(prefix='lk_types_')
        cls.extra_root = Path(cls._tmp)
        folder = cls.extra_root / 'shared' / 'OtherMod'
        folder.mkdir(parents=True)
        (folder / 'OtherMod_LKNomads.lua').write_text(NOMADS, encoding='utf-8')

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls._tmp, True)

    def check_nomads(self):
        for m in self.machines:
            self.assertEqual(self.ids(m), ['neutrals', 'nomads', 'raiders', 'settlers'], m)
            self.assertEqual(self.lk_errors(m), [], m)
        t = self.ev('LivingKnox.GroupTypes.get("nomads")')
        self.assertEqual((t.size.min, t.size.max, t.home, t.profiles[1].female), (3, 5, 'forest', True))
        self.assertEqual(list(t.profiles[1].weapons.values()), ['Base.Machete', 'OtherMod.Spear'])
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        g = self.ev('LivingKnox.Groups.create({ type = "nomads", name = "Drifters" })')
        self.assertEqual((g.id, g.type), ('grp-1', 'nomads'))

    def test_extra_data_file_loaded_after_ours(self):
        self.boot(extra=('shared/OtherMod/OtherMod_LKNomads.lua',))
        self.check_nomads()

    def test_extra_data_file_loaded_before_ours(self):
        # Mod placé avant le nôtre : son fichier tire le registre par require, nos types suivent.
        self.boot(before=('shared/OtherMod/OtherMod_LKNomads.lua',))
        self.check_nomads()

    def test_groups_of_a_type_kept_after_restart(self):
        self.boot(extra=('shared/OtherMod/OtherMod_LKNomads.lua',))
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.ev('LivingKnox.Groups.create({ type = "nomads", name = "Drifters" })')
        self.ev('LivingKnox.Groups.flush()')   # LK13-T06 : une écriture par image (deux images ici)
        self.ev('LivingKnox.Groups.create({ type = "settlers", name = "Mill" })')
        self.ev('LivingKnox.Groups.flush()')
        root = self.h.root
        self.h._tmp = None
        self.h.close()
        self.addCleanup(shutil.rmtree, root, True)
        # Redémarrage sans le mod qui livrait « nomads » : son groupe est écarté et journalisé, l'autre est gardé.
        self.h = Harness(mode=self.mode, root=root)
        self.boot()
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual(list(self.ev('LivingKnox.Groups.list()').values()), ['grp-2'])
        self.assertIn('[LivingKnox] ERROR group grp-1 dropped at load (file #2): unknown type nomads',
                      self.lk_errors())


class Validation(Base):
    def test_invalid_definitions_refused_others_kept(self):
        self.boot()
        for i, (change, why) in enumerate(INVALID.items()):
            code = f'local d = {GOOD % i}; {change}; return LivingKnox.GroupTypes.register(d)'
            self.assertEqual(self.run_lua(code), (None, why), change)
        self.assertEqual(self.ids(), ['neutrals', 'raiders', 'settlers'])
        self.assertEqual(self.ev('#LivingKnox.GroupTypes.refused()'), len(INVALID))
        errors = self.lk_errors()
        self.assertEqual(len(errors), len(INVALID))
        self.assertEqual(errors[0], '[LivingKnox] ERROR group type test_0 refused: unknown field colour')
        self.assertTrue(errors[-1].startswith('[LivingKnox] ERROR group type ? refused: '), errors[-1])
        # La référence elle-même est valide, et un mod d'armes est admis par sa forme.
        ok = self.run_lua(f'local d = {GOOD % "ok"}; d.profiles[1].weapons = {{ "Mod_X.Gun", "Base.Axe" }}; '
                          'return LivingKnox.GroupTypes.register(d)')
        self.assertEqual(ok, True)
        self.assertEqual(self.h.errors(self.srv), [])

    def test_bad_data_file_does_not_break_the_others(self):
        self.boot(extra=())
        code = ('require "LivingKnox/LK_GroupTypes"\n'
                'LivingKnox.GroupTypes.register({ format = 1, id = "ghosts", nameKey = "K", size = { min = 1, max = 2 },'
                ' hostility = 0, home = "cave", morale = 0, needs = { food = 0, medical = 0, ammo = 0 }, roles = {},'
                ' profiles = {} })\n')
        self.run_lua(code)
        self.assertEqual(self.ids(), ['neutrals', 'raiders', 'settlers'])
        self.assertEqual(self.lk_errors(), ['[LivingKnox] ERROR group type ghosts refused: home must be building or '
                                            'forest'])

    def test_duplicate_identifier_refused(self):
        self.boot()
        self.run_lua('return LivingKnox.GroupTypes.get("raiders")')
        result = self.run_lua('local d = LivingKnox.GroupTypes.get("raiders"); d.hostility = 0; '
                              'return LivingKnox.GroupTypes.register(d)')
        self.assertEqual(result, (None, 'identifier already registered'))
        self.assertEqual(self.ev('LivingKnox.GroupTypes.get("raiders").hostility'), 90)
        self.assertEqual(self.lk_errors(), ['[LivingKnox] ERROR group type raiders refused: identifier already '
                                            'registered'])


class SoloTypes(Base):
    mode = 'solo'

    def test_solo_registers_the_three_types(self):
        self.boot()
        self.assertEqual(self.ids(), ['neutrals', 'raiders', 'settlers'])
        self.h.fire(self.srv, 'OnInitGlobalModData', True)
        self.assertEqual(self.ev('LivingKnox.Groups.create({ type = "raiders", name = "Crows" }).id'), 'grp-1')


class StaticChecks(unittest.TestCase):
    def registry_text(self):
        return (LUA / 'shared' / 'LivingKnox' / 'LK_GroupTypes.lua').read_text(encoding='utf-8')

    def test_vanilla_weapons_exist_with_a_known_attachment(self):
        if not VANILLA_SCRIPTS.is_dir():
            self.skipTest(f'vanilla scripts missing: {VANILLA_SCRIPTS}')
        block = re.search(r'GroupTypes\.VANILLA_WEAPONS = \{(.*?)\n\}', self.registry_text(), re.S).group(1)
        weapons = re.findall(r'\["Base\.(\w+)"\] = true', block)
        self.assertGreaterEqual(len(weapons), 20)
        equipment = (LUA / 'shared' / 'LivingKnox' / 'LK_Equipment.lua').read_text(encoding='utf-8')
        locations = re.search(r'Equipment\.LOCATIONS = \{(.*?)\n\}', equipment, re.S).group(1)
        known = set(re.findall(r'(\w+) = "', locations))
        items = {}
        for path in VANILLA_SCRIPTS.rglob('*.txt'):
            text = path.read_text(encoding='utf-8', errors='replace')
            for m in re.finditer(r'^\s*item\s+(\w+)\s*\{(.*?)^\s*\}', text, re.S | re.M):
                items.setdefault(m.group(1), m.group(2))
        for name in weapons:
            self.assertIn(name, items, f'Base.{name} not found in the vanilla scripts')
            body = items[name]
            self.assertRegex(body, r'ItemType\s*=\s*base:weapon', name)
            attach = re.search(r'AttachmentType\s*=\s*(\w+)', body)
            self.assertIsNotNone(attach, name)
            self.assertIn(attach.group(1), known, f'Base.{name}: AttachmentType {attach.group(1)}')
        # Les fichiers livrés n'emploient que des armes admises (contrôlé aussi par register).
        for rel in DATA:
            for w in re.findall(r'"(Base\.\w+)"', (LUA / rel).read_text(encoding='utf-8')):
                self.assertIn(w.split('.', 1)[1], weapons, f'{rel}: {w}')

    def test_name_keys_translated_in_english_and_french(self):
        for rel in DATA:
            key = re.search(r'nameKey = "(\w+)"', (LUA / rel).read_text(encoding='utf-8')).group(1)
            for lang in ('EN', 'FR'):
                table = json.loads((TRANSLATE / lang / 'IG_UI.json').read_text(encoding='utf-8'))
                self.assertIn(key, table, f'{lang}: {key}')
                self.assertTrue(table[key].strip())

    def test_code_and_data_are_ascii(self):
        files = [LUA / 'shared' / 'LivingKnox' / 'LK_GroupTypes.lua'] + [LUA / rel for rel in DATA]
        bad = [line for f in files for line in lua_files_ascii(f)]
        self.assertEqual(bad, [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
