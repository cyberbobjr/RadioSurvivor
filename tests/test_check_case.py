"""Tests hors jeu du contrôle de casse (LK13-T05) : tools/check_case.py.

    python RadioSurvivor/tests/test_check_case.py

Arborescences factices (dossier vanilla et mods) : un mod propre passe ; chaque règle (layout, vanilla-dir,
anim-state, collision, vanilla-file, require, media-ref, mod-info, translation, sandbox) détecte son erreur ; le code
de sortie vaut 1 en cas d'erreur. Le contrôle des mods réels contre le jeu installé est SKIP si le jeu est absent.
"""
from __future__ import annotations

import io
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_case as cc  # noqa: E402

HAS_VANILLA = cc.DEFAULT_VANILLA.is_dir()

VANILLA_FILES = [
    'AnimSets/zombie/idle/default.xml',
    'actiongroups/zombie/idle/to_walk.xml',
    'lua/client/ISUI/ISButton.lua',
    'lua/shared/Translate/EN/UI.json',
    'lua/shared/Translate/EN/Sandbox.json',
    'lua/shared/Translate/FR/UI.json',
    'lua/shared/Translate/DE/UI.json',
    'textures/Item_Radio.png',
    'scripts/items.txt',
]

SANDBOX = """VERSION = 1,
option Demo.Enabled
{
    type = boolean,
    default = true,
    page = Demo,
    translation = Demo_Enabled,
}
"""


def write(path: Path, text: str = '') -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='rs_case_'))
        self.vanilla_dir = self.tmp / 'vanilla' / 'media'
        for rel in VANILLA_FILES:
            write(self.vanilla_dir / rel, '{}' if rel.endswith('.json') else '')
        self.vanilla = cc.load_vanilla(self.vanilla_dir)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def clean_mod(self, name: str = 'demo') -> Path:
        mod = self.tmp / 'mods' / name
        write(mod / '42.21' / 'mod.info', f'id={name}\nposter=poster.png\n')
        write(mod / '42.21' / 'poster.png')
        write(mod / 'common' / '.keep')
        media = mod / 'common' / 'media'
        write(media / 'AnimSets' / 'zombie' / 'idle' / 'demo_idle.xml')
        write(media / 'textures' / 'Demo' / 'Paper.png')
        vmedia = mod / '42.21' / 'media'
        write(vmedia / 'lua' / 'shared' / 'Demo' / 'Core.lua', 'Demo = {}\n')
        write(vmedia / 'lua' / 'client' / 'Demo' / 'UI.lua',
              'require "Demo/Core"\nrequire(\'ISUI/ISButton\')\n'
              '-- require "Demo/core" in a comment is ignored, so is media/Textures/Nothing.png\n'
              'local t = getTexture("media/textures/Demo/Paper.png")\n'
              "local u = getTexture('media/textures/Demo/' .. 'Paper' .. '.png')\n"
              'local o = getSandboxOptions():getOptionByName("Demo.Enabled")\n'
              'local v = SandboxVars.Demo.Enabled\n')
        write(vmedia / 'lua' / 'shared' / 'Translate' / 'EN' / 'Sandbox.json',
              '{"Sandbox_Demo": "Demo", "Sandbox_Demo_Enabled": "Enabled"}')
        write(vmedia / 'lua' / 'shared' / 'Translate' / 'FR' / 'UI.json', '{}')
        write(vmedia / 'sandbox-options.txt', SANDBOX)
        write(vmedia / 'scripts' / 'demo_items.txt',
              'module Demo { item Thing { Icon = Radio, WorldStaticModel = Thing, } }\n')
        return mod

    def problems(self, mod: Path, deps: list[Path] | None = None) -> list[cc.Problem]:
        return cc.check_mod(mod, deps or [], self.vanilla)

    def rules(self, mod: Path, deps: list[Path] | None = None) -> dict[str, list[str]]:
        out: dict[str, list[str]] = {}
        for p in self.problems(mod, deps):
            out.setdefault(p.rule, []).append(str(p))
        return out


class CleanTest(Fixture):
    def test_clean_mod_passes(self):
        mod = self.clean_mod()
        self.assertEqual([str(p) for p in self.problems(mod)], [])

    def test_dependency_require_resolves(self):
        main = self.clean_mod()
        dev = self.tmp / 'mods' / 'devmod'
        write(dev / '42.21' / 'mod.info', 'id=devmod\nrequire=\\demo\n')
        write(dev / '42.21' / 'media' / 'lua' / 'shared' / 'Dev' / 'T.lua', 'require "Demo/Core"\n')
        self.assertEqual([str(p) for p in self.problems(dev, [main])], [])


class RuleTest(Fixture):
    def test_layout_media_and_common(self):
        mod = self.clean_mod()
        (mod / '42.21' / 'media').rename(mod / '42.21' / 'Media')
        (mod / 'common').rename(mod / 'Common')
        found = self.rules(mod)
        self.assertTrue(any('Media' in p for p in found.get('layout', [])), found)
        self.assertTrue(any('Common' in p for p in found.get('layout', [])), found)

    def test_vanilla_dir_and_anim_state(self):
        mod = self.clean_mod()
        anims = mod / 'common' / 'media' / 'AnimSets'
        (anims / 'zombie' / 'idle').rename(anims / 'zombie' / 'Idle')
        write(mod / 'common' / 'media' / 'actiongroups' / 'zombie' / 'newstate' / 'to_idle.xml')
        write(mod / 'common' / 'media' / 'Scripts' / 'x.txt')  # common/media/scripts absent: Windows keeps the case
        found = self.rules(mod)
        self.assertTrue(any('AnimSets/zombie/Idle' in p and 'AnimSets/zombie/idle' in p
                            for p in found.get('vanilla-dir', [])), found)
        self.assertTrue(any('media/Scripts' in p for p in found.get('vanilla-dir', [])), found)
        states = found.get('anim-state', [])
        self.assertTrue(any('zombie/Idle' in p for p in states), found)
        self.assertTrue(any('actiongroups/zombie/newstate' in p for p in states), found)

    def test_collision_inside_mod_and_with_dependency(self):
        mod = self.clean_mod()
        write(mod / '42.21' / 'media' / 'textures' / 'Demo' / 'paper.png')
        found = self.rules(mod)
        self.assertTrue(any('Paper.png' in p and 'paper.png' in p for p in found.get('collision', [])), found)
        dev = self.tmp / 'mods' / 'devmod'
        write(dev / '42.21' / 'mod.info', 'id=devmod\n')
        write(dev / '42.21' / 'media' / 'lua' / 'shared' / 'demo' / 'core.lua')
        found = self.rules(dev, [mod])
        self.assertTrue(any('same path as a file of demo' in p for p in found.get('collision', [])), found)

    def test_vanilla_file_replacement(self):
        mod = self.clean_mod()
        write(mod / '42.21' / 'media' / 'lua' / 'client' / 'ISUI' / 'ISButton.lua')
        write(mod / '42.21' / 'media' / 'textures' / 'item_radio.png')
        found = self.rules(mod).get('vanilla-file', [])
        self.assertTrue(any('ISUI/ISButton.lua' in p and 'replaces' in p for p in found), found)
        self.assertTrue(any('item_radio.png' in p and 'Item_Radio.png' in p for p in found), found)
        # A translation file at the vanilla path is merged, not replaced: no error (clean mod has FR/UI.json).
        self.assertFalse(any('Translate' in p for p in found), found)

    def test_require_case_and_missing(self):
        mod = self.clean_mod()
        write(mod / '42.21' / 'media' / 'lua' / 'server' / 'Demo' / 'S.lua',
              'require "demo/core"\nrequire "ISUI/isbutton"\nrequire "Demo/Missing"\n')
        found = self.rules(mod).get('require', [])
        self.assertTrue(any('"demo/core"' in p and 'require "Demo/Core"' in p for p in found), found)
        self.assertTrue(any('"ISUI/isbutton"' in p and 'ISUI/ISButton' in p for p in found), found)
        self.assertTrue(any('"Demo/Missing" not found' in p for p in found), found)
        self.assertEqual(len(found), 3, found)

    def test_media_reference_in_lua_and_scripts(self):
        mod = self.clean_mod()
        write(mod / '42.21' / 'media' / 'lua' / 'client' / 'Demo' / 'Bad.lua',
              'getTexture("media/textures/demo/Paper.png")\n'
              "getTexture('media/textures/demo/' .. name)\n")
        write(mod / '42.21' / 'media' / 'scripts' / 'bad.txt',
              'module Demo { item A { Icon = radio, } }\nsound S { clip { file = media/sound/Missing.ogg, } }\n')
        found = self.rules(mod).get('media-ref', [])
        self.assertTrue(any('Bad.lua:1' in p and 'media/textures/Demo/Paper.png' in p for p in found), found)
        self.assertTrue(any('Bad.lua:2' in p and 'media/textures/Demo' in p for p in found), found)
        self.assertTrue(any('Icon = radio' in p and 'Item_Radio.png' in p for p in found), found)
        self.assertTrue(any('Missing.ogg' in p and 'not found' in p for p in found), found)

    def test_mod_info_poster(self):
        mod = self.clean_mod()
        (mod / '42.21' / 'poster.png').rename(mod / '42.21' / 'Poster.png')
        found = self.rules(mod).get('mod-info', [])
        self.assertTrue(any('poster=poster.png' in p and 'Poster.png' in p for p in found), found)

    def test_translation_language_and_file(self):
        mod = self.clean_mod()
        tr = mod / '42.21' / 'media' / 'lua' / 'shared' / 'Translate'
        write(tr / 'de' / 'IG_UI.json', '{}')  # not 'fr': FR exists and Windows would reuse it
        write(tr / 'EN' / 'ui.json', '{}')
        write(tr / 'EN' / 'Notes.json', '{}')
        found = self.rules(mod)
        tr_found = found.get('translation', [])
        self.assertTrue(any('"de" unknown' in p and 'DE' in p for p in tr_found), found)
        self.assertTrue(any('ui.json' in p and 'expected: UI.json' in p for p in tr_found), found)
        self.assertTrue(any('Notes.json' in p for p in tr_found), found)
        self.assertTrue(any('Translate/de' in p for p in found.get('vanilla-dir', [])), found)

    def test_sandbox_keys_and_lua_names(self):
        mod = self.clean_mod()
        vmedia = mod / '42.21' / 'media'
        write(vmedia / 'lua' / 'shared' / 'Translate' / 'EN' / 'Sandbox.json',
              '{"Sandbox_demo": "Demo", "Sandbox_Demo_Enabled": "Enabled"}')
        write(vmedia / 'lua' / 'shared' / 'Translate' / 'FR' / 'Sandbox.json', '{"Sandbox_Demo_enabled": "Actif"}')
        write(vmedia / 'lua' / 'shared' / 'Demo' / 'Opt.lua',
              'local a = SandboxVars.Demo.enabled\nlocal b = SandboxVars.demo\n'
              'local c = getOptionByName("demo.Enabled")\nlocal d = "DEMO."\n')
        found = self.rules(mod).get('sandbox', [])
        self.assertTrue(any('Sandbox_Demo spelled with another case' in p for p in found), found)
        self.assertTrue(any('FR/Sandbox.json' in p and 'Sandbox_Demo_enabled' in p for p in found), found)
        self.assertTrue(any('SandboxVars.Demo.enabled' in p for p in found), found)
        self.assertTrue(any('SandboxVars.demo' in p for p in found), found)
        self.assertTrue(any('"demo.Enabled"' in p for p in found), found)
        self.assertTrue(any('"DEMO."' in p for p in found), found)

    def test_main_exit_codes(self):
        mod = self.clean_mod()
        args = ['--vanilla', str(self.vanilla_dir), '--mod', str(mod)]
        with redirect_stdout(io.StringIO()) as out:
            self.assertEqual(cc.main(args), 0)
        self.assertIn('OK', out.getvalue())
        write(mod / '42.21' / 'media' / 'lua' / 'shared' / 'Demo' / 'X.lua', 'require "demo/core"\n')
        with redirect_stdout(io.StringIO()) as out:
            self.assertEqual(cc.main(args), 1)
        self.assertIn('ERROR [require]', out.getvalue())
        with redirect_stdout(io.StringIO()):
            self.assertEqual(cc.main(['--vanilla', str(self.tmp / 'absent')]), 2)


class LexerTest(unittest.TestCase):
    def test_comments_and_long_strings(self):
        code, strings = cc.lua_strings('a = "x\\"y" -- "c"\n--[[ "d" ]] b = [[e]] .. \'f\'\n')
        self.assertEqual([s[0] for s in strings], ['x"y', 'e', 'f'])
        self.assertNotIn('"c"', code)
        self.assertNotIn('"d"', code)


@unittest.skipUnless(HAS_VANILLA, 'vanilla media folder absent')
class RepositoryTest(unittest.TestCase):
    def test_published_and_dev_mods(self):
        # Mods requis batman_BeltRadio et batman_SignalSmoke (dépôts voisins) : dépendances des deux mods.
        for dep in (cc.BELT_MOD, cc.SIGNAL_MOD):
            if not dep.is_dir():
                self.skipTest(f'required mod absent: {dep}')
        deps = [cc.BELT_MOD, cc.SIGNAL_MOD]
        vanilla = cc.load_vanilla(cc.DEFAULT_VANILLA)
        self.assertEqual([str(p) for p in cc.check_mod(cc.MAIN_MOD, deps, vanilla)], [])
        self.assertEqual([str(p) for p in cc.check_mod(cc.DEV_MOD, [cc.MAIN_MOD] + deps, vanilla)], [])
        # Sans Belt Walkie-Talkie, le require du récepteur commun n'est pas résolu.
        problems = [str(p) for p in cc.check_mod(cc.MAIN_MOD, [cc.SIGNAL_MOD], vanilla)]
        self.assertEqual(len(problems), 1, problems)
        self.assertIn('require "BatmanRadio/BatmanRadio_Core" not found', problems[0])
        # Sans Signal Smoke, ses trois require (mission signal, secours, passeur) ne sont pas résolus.
        problems = [str(p) for p in cc.check_mod(cc.MAIN_MOD, [cc.BELT_MOD], vanilla)]
        self.assertEqual(len(problems), 3, problems)
        self.assertTrue(all('require "SignalSmoke/SignalSmoke" not found' in p for p in problems), problems)


if __name__ == '__main__':
    unittest.main()
