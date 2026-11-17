"""Fiches des voix radio (E05-T01) : bridge/persona_store.py et RS_Persona.lua sur les mêmes fichiers.

    python RadioSurvivor/tests/radiosurvivor/test_personas.py

Chaque cas est écrit dans un dossier temporaire, puis lu par le lecteur Python (`load_file`) et par le vrai Lua du
mod dans lupa (`RS_Persona.readFile`), avec un `getFileReader` simulé comme celui du jeu : UTF-8, octets invalides
remplacés par U+FFFD, BOM conservé, lignes découpées comme `BufferedReader.readLine`. Les deux lecteurs doivent
accepter les mêmes fiches avec le même contenu, et refuser les autres avec le même message et la même ligne.
Vérifie aussi que la fiche livrée `walt.txt` (dossier `personas` du mod) décrit le Walt actuel (prompt, fréquence,
appel spontané).
La lecture dans la VM Kahlua réelle (accents, BOM, UTF-8 invalide) est dans tests/coreai/test_kahlua.py.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from persona_fixtures import (  # noqa: E402  (tests/commun, E26)
    ROOT,
    MOD,
    LUA,
    PERSONA_LUA,
    LUA_PATH,
    RULE_MODULES,
    RULES_STUBS,
    WALT,
    store,
    SIGNAL_SMOKE,
    ITEM_WEIGHTS,
    HEAD,
    FIXED_HEAD,
    LEVELS,
    PROMPT,
    PLACES,
    FULL,
    CASES,
    PLACES_CASES,
    LUA_CANONICAL,
    LUA_PLACES_CANONICAL,
    places_canonical,
    canonical,
    lua_items,
    raw_bytes,
    python_result,
)


class LuaReader:
    """getFileReader of the game: UTF-8 with U+FFFD for invalid bytes, BOM kept, BufferedReader line splitting."""

    def __init__(self, path: Path):
        self.lines = store.split_lines(path.read_bytes().decode('utf-8', errors='replace'))

    def readLine(self):  # noqa: N802 (Java name)
        return self.lines.pop(0) if self.lines else None

    def close(self):
        pass


class LuaPersona:
    """Vrai RS_Persona avec les vraies règles du serveur (E20-T03) : registre des gabarits de mission du mod commun
    (gabarits inscrits comme au chargement du jeu, qui lit tous les fichiers serveur avant les fiches), natures de
    récompense de RS_Rewards et catalogue de catégories livré (personas/_categories.txt), assemblés par
    RS_Personas.rules()."""

    def __init__(self, folder: Path):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.rt.globals()
        g.next = None  # absent de Kahlua
        self.rt.execute(RULES_STUBS)
        self.rt.execute(SIGNAL_SMOKE)  # mod requis, chargé par le gabarit signal
        g.getFileReader = lambda name, create: (LuaReader(folder / name) if (folder / name).is_file() else None)
        g.getModFileReader = lambda mod, name, create: (
            LuaReader(MOD / name) if mod == 'batman_RadioSurvivor' and (MOD / name).is_file() else None)
        self.rt.execute(f'package.path = [[{LUA_PATH};]] .. package.path')
        self.rt.execute(ITEM_WEIGHTS)  # E22-T12 : poids des objets du troc, à la place des scripts du jeu
        for module in RULE_MODULES:
            self.rt.eval(f'require("{module}")')
        self.module = self.rt.eval('require("RadioSurvivor/RS_Persona")')
        self.rules = self.rt.eval('require("RadioSurvivor/RS_Personas")').rules()
        self.canonical = self.rt.execute(LUA_CANONICAL)
        self.places_canonical = self.rt.execute(LUA_PLACES_CANONICAL)
        self.folder = folder

    def places(self, name: str = '_places.txt'):
        """Fichier commun des lieux lu par le serveur (E25-T01) : table id -> lieu, ou (None, raison)."""
        path = self.folder / name
        if not path.is_file():
            return self.rt.table()
        return self.module.parsePlaces(self.rt.table_from(LuaReader(path).lines))

    def read(self, name: str):
        """Fiche lue par le serveur avec les lieux communs du même dossier (_places.txt, comme le pont) : table Lua, ou
        (None, raison)."""
        places = self.places()
        self.rules.places = places if not isinstance(places, tuple) else self.rt.table()
        return self.module.readFile(name, self.rules)

    def result(self, name: str) -> str:
        result = self.read(name)
        if isinstance(result, tuple):  # nil, reason
            return 'ERR ' + result[1]
        return 'OK ' + self.canonical(result)


class PersonaFormatTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.folder = Path(cls.tmp.name)
        cls.lua = LuaPersona(cls.folder)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        (self.folder / '_places.txt').write_bytes(PLACES.encode('utf-8'))

    def write_case(self, content: str | bytes) -> Path:
        path = self.folder / 'case.txt'
        path.write_bytes(raw_bytes(content))
        return path

    def places_result(self, content: str | bytes) -> tuple[str, str]:
        """Fichier commun des lieux lu par les deux lecteurs : résumé canonique (OK) ou message (ERR)."""
        path = self.folder / '_places.txt'
        path.write_bytes(raw_bytes(content))
        try:
            py = 'OK ' + places_canonical(store.load_places(path))
        except store.PersonaError as exc:
            py = 'ERR ' + str(exc)
        lua = self.lua.places()
        return py, ('ERR ' + lua[1]) if isinstance(lua, tuple) else 'OK ' + self.lua.places_canonical(lua)

    def test_places_same_result_in_python_and_lua(self):
        self.assertEqual(len({name for name, _, _ in PLACES_CASES}), len(PLACES_CASES))
        for name, content, expected in PLACES_CASES:
            with self.subTest(name):
                py, lua = self.places_result(content)
                if expected is None:
                    self.assertTrue(py.startswith('OK '), py)
                else:
                    self.assertEqual(py, f'ERR line {expected[0]}: {expected[1]}')
                self.assertEqual(lua, py)

    def test_places_content(self):
        places = store.load_places(self.folder / '_places.txt')
        self.assertEqual(places['mill'], store.Place('mill', 'Vieux moulin', 0, x=10600, y=9300))
        # Zone : coins rangés du plus petit au plus grand, quel que soit leur ordre dans le fichier.
        self.assertEqual(places['town'], store.Place('town', 'Old town', 0, area=(50, 150, 100, 200)))
        self.assertTrue(places['town'].is_zone and not places['mill'].is_zone)
        lua = self.lua.places()
        town = lua['town']
        self.assertEqual((town.area.x1, town.area.y1, town.area.x2, town.area.y2, town.z, town.x), (50, 150, 100, 200, 0, None))
        self.assertEqual((lua.mill.x, lua.mill.y, lua.mill.z, lua.mill.area), (10600, 9300, 0, None))

    def test_marks_in_the_order_of_the_sheet(self):
        p = store.load_file(self.write_case(HEAD + 'actions=say,mark_map\nmarks=town, mill\n' + PROMPT))
        self.assertEqual([q.id for q in p.marks], ['town', 'mill'])
        sheet = self.lua.read('case.txt')
        self.assertEqual([q.id for q in lua_items(sheet.marks)], ['town', 'mill'])
        # Le pont lit les lieux communs du dossier de la fiche ; sans fichier, aucun lieu n'existe.
        (self.folder / '_places.txt').unlink()
        with self.assertRaises(store.PersonaError) as ctx:
            store.load_file(self.folder / 'case.txt')
        self.assertEqual((ctx.exception.line, ctx.exception.reason), (6, "unknown place 'town'"))
        self.assertEqual(store.load_file(self.folder / 'case.txt', places={'town': store.Place('town', 'T', 0, x=1, y=2),
                                                                            'mill': store.Place('mill', 'M', 0, x=3, y=4)})
                         .marks[1].label, 'M')

    def test_cases_same_result_in_python_and_lua(self):
        self.assertEqual(len({name for name, _, _ in CASES}), len(CASES))
        for name, content, expected in CASES:
            with self.subTest(name):
                path = self.write_case(content)
                py = python_result(path)
                if expected is None:
                    self.assertTrue(py.startswith('OK '), py)
                else:
                    self.assertEqual(py, f'ERR line {expected[0]}: {expected[1]}')
                    with self.assertRaises(store.PersonaError) as ctx:
                        store.load_file(path)
                    self.assertEqual((ctx.exception.line, ctx.exception.reason), expected)
                self.assertEqual(self.lua.result('case.txt'), py)

    def test_full_sheet_content(self):
        p = store.load_file(self.write_case(FULL))
        self.assertEqual((p.id, p.name, p.language, p.radio, p.location, p.state),
                         ('case', 'Hélène Dupré', 'fr', None, 'fixed', 'silent'))
        self.assertEqual(p.frequency, 7200)
        self.assertEqual(p.listen, [(22 * 60, 6 * 60), (12 * 60 + 30, 13 * 60)])
        self.assertEqual(p.coords, (10600, 9300, -1))
        self.assertEqual(p.actions, ['say', 'signal', 'mark_map'])
        self.assertEqual((p.budget, p.budgets), (12, {'signal': 2, 'say': 0}))
        self.assertEqual((p.call_one_in, p.call_text), (4, 'IGUI_Test_Call'))
        self.assertEqual(p.prompt, 'Tu es Hélène, infirmière.\n  Ligne indentée, avec = et # gardés.\n\n'
                                   'Dernière ligne 📻.')

    def test_defaults(self):
        p = store.load_file(self.write_case(HEAD + PROMPT))
        self.assertEqual((p.language, p.radio, p.listen, p.location, p.coords, p.actions, p.budget, p.budgets,
                          p.call_one_in, p.call_text, p.state, p.marks),
                         ('en', 'any_talkie', [], 'none', None, ['say'], 0, {}, 0, '', 'active', []))
        self.assertIsNone(p.frequency)

    def test_server_derives_the_radio_of_a_fixed_frequency(self):
        # E24-T01 : radio nécessaire d'une fréquence fixe = niveau le plus faible qui la capte (RS_RadioLevels.levelOf).
        for mhz, level in (('145.0', 'any_talkie'), ('150.2', 'good_talkie'), ('25.0', 'pro_talkie'),
                           ('300.2', 'tactical'), ('7.2', 'military'), ('1000.0', 'military')):
            with self.subTest(mhz):
                self.write_case(FIXED_HEAD.replace('145.0', mhz) + PROMPT)
                sheet = self.lua.read('case.txt')
                self.assertEqual((sheet.frequency, sheet.radio), (round(float(mhz) * 1000), level))
        self.write_case(HEAD.replace('any_talkie', 'tactical') + PROMPT)
        sheet = self.lua.read('case.txt')
        self.assertEqual((sheet.frequency, sheet.radio), (None, 'tactical'))

    def test_missing_file(self):
        self.assertEqual(self.lua.read('absent.txt'), (None, 'cannot read absent.txt'))
        with self.assertRaises(OSError):
            store.load_file(self.folder / 'absent.txt')

    def test_lua_file_is_ascii(self):
        # Lexeur Kahlua : un littéral non ASCII devient U+FFFD (base kahlua-lua.md) ; hors commentaires, rien.
        for number, line in enumerate(PERSONA_LUA.read_text(encoding='utf-8').splitlines(), 1):
            code = line.split('--', 1)[0]
            self.assertTrue(code.isascii(), f'RS_Persona.lua:{number} non ASCII outside a comment')
            self.assertNotIn('loadstring', code, f'RS_Persona.lua:{number}')


class WaltSheetTests(unittest.TestCase):
    """La fiche livrée walt.txt décrit exactement le Walt actuel du mod (sans en changer le comportement)."""

    @classmethod
    def setUpClass(cls):
        cls.walt = store.load_file(WALT)

    def test_valid_in_python_and_lua(self):
        lua = LuaPersona(WALT.parent)
        self.assertEqual(lua.result('walt.txt'), 'OK ' + canonical(self.walt))

    def test_utf8_without_bom(self):
        raw = WALT.read_bytes()
        self.assertFalse(raw.startswith(b'\xef\xbb\xbf'))
        raw.decode('utf-8')

    def test_prompt_is_the_current_persona(self):
        # Texte de l'ancien prompt de secours bridge/persona.txt (retiré en E05-T10), inchangé depuis E05-T03 : son
        # empreinte SHA-256 tient lieu de copie.
        self.assertTrue(self.walt.prompt.startswith('You are Walt Hensley, 54, a retired power-line worker'))
        self.assertEqual(hashlib.sha256(self.walt.prompt.encode('utf-8')).hexdigest(),
                         '981dd3cb9d3358d092cdf77a37a9f075e8d42fa54aaff41f46f4af9245b785c6')

    def test_identity_and_rules(self):
        w = self.walt
        self.assertEqual((w.id, w.name, w.language, w.radio, w.listen, w.location, w.coords, w.state),
                         ('walt', 'Walt Hensley', 'en', 'any_talkie', [], 'none', None, 'active'))
        self.assertEqual((w.actions, w.budget, w.budgets), (['say', 'share_frequency'], 0, {}))  # E07-T10

    def test_frequency_comes_from_the_sheet(self):
        # E05-T02 : la fiche fait foi ; l'option sandbox RadioSurvivor.Frequency est retirée (fichier et textes).
        # E24-T01 : fréquence libre tirée à chaque nouvelle partie dans la zone du talkie le plus simple.
        self.assertEqual((self.walt.frequency, self.walt.radio), (None, 'any_talkie'))
        const = (LUA / 'shared/RadioSurvivor/RadioSurvivor_Const.lua').read_text(encoding='utf-8')
        self.assertNotRegex(const, r'\n\s*Frequency = ')
        options = (ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/sandbox-options.txt')
        self.assertNotIn('RadioSurvivor.Frequency', options.read_text(encoding='utf-8'))
        for lang in ('EN', 'FR'):
            sandbox = json.loads((LUA / f'shared/Translate/{lang}/Sandbox.json').read_text(encoding='utf-8'))
            self.assertNotIn('Sandbox_RadioSurvivor_Frequency', sandbox)

    def test_spontaneous_call(self):
        self.assertEqual((self.walt.call_one_in, self.walt.call_text), (3, 'IGUI_RadioSurvivor_Call'))
        server = (LUA / 'server/RadioSurvivor_Server.lua').read_text(encoding='utf-8')
        # E05-T05 : appel de chaque voix, une chance sur call_one_in ; texte fixe composé sur l'autorité.
        self.assertIn('ZombRand(sheet.call_one_in) == 0', server)
        self.assertIn('getText(key, Const.frequencyLabel(khz))', server)
        self.assertIn('Translator.loadFiles()', server)
        en = json.loads((LUA / 'shared/Translate/EN/IG_UI.json').read_text(encoding='utf-8'))
        self.assertIn('%1', en['IGUI_RadioSurvivor_Call'])


VOICES = {'walt', 'darlene', 'cody', 'whitaker', 'nightowl', 'gus',
          # E20-T11 : un marchand par ville vanilla.
          'wanda', 'lamar', 'delphine', 'hollis', 'loretta', 'virgil', 'boone', 'odessa', 'ezra', 'maxine'}


class DeliveredVoicesTests(unittest.TestCase):
    """E05-T04, E20-T11 et E24-T01 : les fiches livrées sont valides des deux côtés ; radio de chaque voix."""

    # E24-T01 (2026-11-16) : radio nécessaire de chaque voix, reprise de sa bande d'E05-T07 / E20-T11 (le poste le
    # plus faible qui captait toute la bande).
    LEVELS = {
        'walt': 'any_talkie', 'darlene': 'any_talkie', 'whitaker': 'any_talkie', 'nightowl': 'any_talkie',
        'gus': 'good_talkie', 'delphine': 'good_talkie', 'cody': 'tactical',
        'wanda': 'pro_talkie', 'lamar': 'pro_talkie', 'hollis': 'pro_talkie', 'loretta': 'pro_talkie',
        'virgil': 'pro_talkie', 'boone': 'pro_talkie', 'odessa': 'pro_talkie', 'ezra': 'pro_talkie',
        'maxine': 'pro_talkie',
    }

    @classmethod
    def setUpClass(cls):
        # Un fichier commençant par « _ » n'est pas une voix (catalogue _categories.txt, E20-T03).
        cls.sheets = {p.stem: store.load_file(p) for p in sorted(WALT.parent.glob('*.txt'))
                      if not p.name.startswith('_')}

    def test_the_six_voices_are_delivered(self):
        self.assertEqual(set(self.sheets), VOICES)

    def test_shared_places_valid_in_python_and_lua(self):
        # E25-T01 : les 15 lieux des voix livrées (11 rendez-vous de marchand, le relais de Cody, la clinique de
        # Darlene et ses deux planques), tous des points, dans le fichier commun livré.
        places = store.load_places(WALT.parent / '_places.txt')
        self.assertEqual(len(places), 15)
        self.assertFalse(any(q.is_zone for q in places.values()))
        lua = LuaPersona(WALT.parent)
        self.assertEqual(lua.places_canonical(lua.places()), places_canonical(places))

    def test_valid_in_python_and_lua(self):
        lua = LuaPersona(WALT.parent)
        for vid, sheet in self.sheets.items():
            with self.subTest(vid):
                self.assertEqual(lua.result(f'{vid}.txt'), 'OK ' + canonical(sheet))
                self.assertFalse((WALT.parent / f'{vid}.txt').read_bytes().startswith(b'\xef\xbb\xbf'))

    def test_every_voice_draws_its_frequency_for_its_radio(self):
        # Toutes les voix, Walt compris : aucune fréquence fixe livrée, une radio nécessaire par voix.
        for vid, sheet in self.sheets.items():
            with self.subTest(vid):
                self.assertEqual((sheet.frequency, sheet.radio), (None, self.LEVELS[vid]))

    # Appels spontanés (E05-T05, valeurs du contrat) : une chance sur N par heure de jeu ; 0 = jamais.
    CALLS = {'darlene': 6, 'cody': 6, 'gus': 8, 'nightowl': 0, 'whitaker': 0}

    def test_call_texts_in_every_language(self):
        """Chaque voix appelante a sa clé call_text, traduite dans toutes les langues livrées, avec %1 (fréquence) ;
        Darlene n'invite jamais à la clinique."""
        languages = sorted(d.name for d in (LUA / 'shared/Translate').iterdir() if d.is_dir())
        self.assertEqual(languages, ['EN', 'FR'])
        texts = {lang: json.loads((LUA / f'shared/Translate/{lang}/IG_UI.json').read_text(encoding='utf-8'))
                 for lang in languages}
        for vid, every in self.CALLS.items():
            s = self.sheets[vid]
            with self.subTest(vid):
                self.assertEqual(s.call_one_in, every)
                if every == 0:
                    continue
                self.assertEqual(s.call_text, f'IGUI_RadioSurvivor_Call_{vid.title()}')
                for lang in languages:
                    self.assertEqual(texts[lang][s.call_text].count('%1'), 1, (lang, s.call_text))
                    if vid == 'darlene':
                        self.assertNotRegex(texts[lang][s.call_text].lower(), 'clinic|clinique|come|venez')

    def test_decided_values(self):
        # Décision E05-T04 du 2026-10-09 (docs/annexes/plans-termines/E05-voix-reseau-radio.md), fréquences : E05-T07.
        # E20-T10 (décision du 2026-11-14, ADR D09) : Darlene a quitté sa clinique et se cache ailleurs, hors carte.
        expected = {
            'darlene': ([(420, 600), (960, 1140)], 'none', None, 'active'),
            'cody': ([(1320, 180)], 'none', None, 'active'),
            'whitaker': ([(360, 1260)], 'rescue', None, 'silent'),
            'nightowl': ([(1140, 1320)], 'none', None, 'active'),
            'gus': ([(180, 360)], 'none', None, 'active'),
        }
        for vid, (listen, location, coords, state) in expected.items():
            s = self.sheets[vid]
            with self.subTest(vid):
                self.assertEqual(([tuple(r) for r in s.listen], s.location,
                                  tuple(s.coords) if s.coords else None, s.state),
                                 (listen, location, coords, state))
                # Appels spontanés par voix : E05-T05 (CALLS) ; actions autres que say : E07 ; pas de budget propre.
                # E13-T03 : Gus propose des offres (propose_trade). E11-T13 : Darlene et Cody donnent des missions
                # de reconnaissance (start_mission ; report_mission implicite), pas Night Owl ni les Whitaker.
                # E07-T10 : Walt et Gus peuvent aussi présenter une autre voix (share_frequency, exceptionnel).
                actions = {'gus': ['say', 'propose_trade', 'share_frequency'], 'walt': ['say', 'share_frequency'],
                           'darlene': ['say', 'start_mission', 'share_frequency'],
                           'cody': ['say', 'start_mission', 'share_frequency']}.get(vid, ['say'])
                self.assertEqual((s.language, s.radio, s.actions, s.call_one_in, s.budget, s.budgets),
                                 ('en', self.LEVELS[vid], actions, self.CALLS[vid], 0, {}))
                if vid in ('darlene', 'cody'):
                    # Missions, récompenses et catégories : lues par le serveur seul (tests/radiosurvivor/test_persona_sections.py).
                    self.assertTrue(s.marks and s.shares)
                self.assertIn('Answer in the same language the caller uses.', s.prompt)


if __name__ == '__main__':
    unittest.main(verbosity=1)
