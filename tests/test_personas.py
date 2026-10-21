"""Fiches des voix radio (E05-T01) : bridge/persona_store.py et RS_Persona.lua sur les mêmes fichiers.

    python RadioSurvivor/tests/test_personas.py

Chaque cas est écrit dans un dossier temporaire, puis lu par le lecteur Python (`load_file`) et par le vrai Lua du
mod dans lupa (`RS_Persona.readFile`), avec un `getFileReader` simulé comme celui du jeu : UTF-8, octets invalides
remplacés par U+FFFD, BOM conservé, lignes découpées comme `BufferedReader.readLine`. Les deux lecteurs doivent
accepter les mêmes fiches avec le même contenu, et refuser les autres avec le même message et la même ligne.
Vérifie aussi que la fiche livrée `walt.txt` (dossier `personas` du mod) décrit le Walt actuel (prompt, fréquence,
appel spontané).
La lecture dans la VM Kahlua réelle (accents, BOM, UTF-8 invalide) est dans tests/test_kahlua.py.
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

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua'
PERSONA_LUA = LUA / 'server/RadioSurvivor/RS_Persona.lua'
# Fiches livrées : seul exemplaire du dépôt, dans le mod (E05-T10).
WALT = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/personas/walt.txt'
sys.path.insert(0, str(ROOT / 'bridge'))
import persona_store as store  # noqa: E402

HEAD = 'format=1\nid=case\nname=Case\nfrequencies=145.0\n'
RANGE_HEAD = 'format=1\nid=case\nname=Case\nfrequency_range=140.0-150.0\n'
BAD_RANGE = '(two frequencies in MHz, lowest first, e.g. 140.0-150.0)'
PROMPT = '[prompt]\nYou are a test voice.\n'

FULL = ('# fiche complète\n'
        'format=1\n'
        ' id = case \n'
        'name=Hélène Dupré\n'
        'language=fr\n'
        'frequencies=7.2, 145.0 ,999.8\n'
        'radio=high_tier\n'
        'listen=22:00-06:00,12:30-13:00\n'
        'location=fixed\n'
        'coords=10600,9300,-1\n'
        'knows=Le pont de Muldraugh est tombé.\n'
        'knows=Les patrouilles passent à l’aube.\n'
        'ignores=Ce qui se passe en Ohio.\n'
        'secret=Elle a laissé son frère à West Point.\n'
        'place=mill 10600,9300,0 Vieux moulin\n'
        'place = west_point_2  11900,6900,-1 \t Pharmacie  de West Point \n'
        'actions=say, signal,mark_map\n'
        'budget=12\n'
        'budget.signal=2\n'
        'budget.say=0\n'
        'call_one_in=4\n'
        'call_text=IGUI_Test_Call\n'
        'state=silent\n'
        '\n'
        '[prompt]\n'
        '\n'
        'Tu es Hélène, infirmière.\n'
        '  Ligne indentée, avec = et # gardés.\n'
        '\n'
        'Dernière ligne 📻.\n'
        '\n')

# (nom, contenu, ligne et raison attendues ; None = fiche valide). Le fichier s'appelle case.txt.
CASES: list[tuple[str, str | bytes, tuple[int, str] | None]] = [
    ('minimal', HEAD + PROMPT, None),
    ('mission reward permissions', HEAD + 'cache_table=medical\nshares=gus,cody\nteaches=Doctor\nmissions=scout,deliver,retrieve,clear,signal\nrewards=cache,frequency,stashmap,lesson\nactions=say,share_frequency\n' + PROMPT, None),
    ('bad cache_table', HEAD + 'cache_table=weapon\n' + PROMPT, (5, "bad cache_table 'weapon' (expected medical, ammo, tools, food, radio)")),
    ('bad teaches', HEAD + 'teaches=Carpentry\n' + PROMPT, (5, "bad teaches 'Carpentry' (expected Doctor, Aiming, Reloading, Woodwork, Mechanics, Electricity, MetalWelding, Cooking, Farming, Fishing, Trapping, PlantScavenging)")),
    ('bad shares', HEAD + 'shares=Gus\n' + PROMPT, (5, "bad shares entry 'Gus'")),
    ('duplicate shares', HEAD + 'shares=gus,gus\n' + PROMPT, (5, "duplicate shares entry 'gus'")),
    ('empty shares entry', HEAD + 'shares=gus,\n' + PROMPT, (5, "bad shares entry ''")),
    ('bad missions', HEAD + 'missions=recover\n' + PROMPT, (5, "bad missions entry 'recover'")),
    ('duplicate missions', HEAD + 'missions=scout,scout\n' + PROMPT, (5, "duplicate missions entry 'scout'")),
    ('empty missions entry', HEAD + 'missions=scout,\n' + PROMPT, (5, "bad missions entry ''")),
    ('bad rewards', HEAD + 'rewards=gold\n' + PROMPT, (5, "bad rewards entry 'gold'")),
    ('duplicate rewards', HEAD + 'rewards=cache,cache\n' + PROMPT, (5, "duplicate rewards entry 'cache'")),
    ('empty rewards entry', HEAD + 'rewards=cache,\n' + PROMPT, (5, "bad rewards entry ''")),

    ('full', FULL, None),
    ('crlf', (HEAD + PROMPT).replace('\n', '\r\n'), None),
    ('lone cr', (HEAD + PROMPT).replace('\n', '\r'), None),
    ('no final newline', HEAD + PROMPT.rstrip('\n'), None),
    ('bom', '\ufeff' + HEAD + PROMPT,
     (1, 'file starts with a byte order mark (save it as UTF-8 without BOM)')),
    ('invalid utf-8 in a value', HEAD.encode() + b'knows=caf\xe9\n' + PROMPT.encode(),
     (5, 'invalid UTF-8 (save the file as UTF-8)')),
    ('invalid utf-8 in the prompt', (HEAD + PROMPT).encode() + b'\xff\xfe\n',
     (7, 'invalid UTF-8 (save the file as UTF-8)')),
    ('no equal sign', HEAD + 'radio high_tier\n' + PROMPT, (5, 'expected key=value or [prompt]')),
    ('bad key', HEAD + 'Radio=any\n' + PROMPT, (5, "bad key 'Radio'")),
    ('unknown key', HEAD + 'colour=red\n' + PROMPT, (5, "unknown key 'colour'")),
    ('unknown budget action', HEAD + 'budget.fly=1\n' + PROMPT, (5, "unknown action 'fly' in key 'budget.fly'")),
    ('duplicate key', HEAD + 'name=Other\n' + PROMPT, (5, "duplicate key 'name' (first set on line 3)")),
    ('empty value', HEAD + 'radio=\n' + PROMPT, (5, "empty value for key 'radio'")),
    ('format', HEAD.replace('format=1', 'format=2') + PROMPT, (1, "unsupported format '2' (expected 1)")),
    ('bad id', HEAD.replace('id=case', 'id=Case') + PROMPT,
     (2, "bad id 'Case' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")),
    ('id too long', HEAD.replace('id=case', 'id=' + 'a' * 33) + PROMPT,
     (2, "bad id '" + 'a' * 33 + "' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")),
    ('id with accent', HEAD.replace('id=case', 'id=cas\u00e9') + PROMPT,
     (2, "bad id 'cas\u00e9' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")),
    ('bad language', HEAD + 'language=eng\n' + PROMPT, (5, "bad language 'eng' (two lowercase letters, e.g. en)")),
    ('frequency without decimal', HEAD.replace('145.0', '145') + PROMPT,
     (4, "bad frequency '145' (MHz with one decimal, e.g. 145.0)")),
    ('frequency with a comma', HEAD.replace('145.0', '145,0') + PROMPT,
     (4, "bad frequency '145' (MHz with one decimal, e.g. 145.0)")),
    ('frequency out of range', HEAD.replace('145.0', '0.8') + PROMPT,
     (4, 'frequency 0.8 out of range (1.0 to 999.8 MHz)')),
    ('frequency off step', HEAD.replace('145.0', '145.1') + PROMPT,
     (4, 'frequency 145.1 is not on the 0.2 MHz step of the radios')),
    ('duplicate frequency', HEAD.replace('145.0', '145.0,7.2,145.0') + PROMPT, (4, 'duplicate frequency 145.0')),
    ('bad radio', HEAD + 'radio=ham\n' + PROMPT, (5, "bad radio 'ham' (expected any, high_tier)")),
    ('bad listening hours', HEAD + 'listen=20:00-06:00,24:00-01:00\n' + PROMPT,
     (5, "bad listening hours '24:00-01:00' (always, or HH:MM-HH:MM ranges separated by commas)")),
    ('listening hours without zero', HEAD + 'listen=8:00-12:00\n' + PROMPT,
     (5, "bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM ranges separated by commas)")),
    ('empty listening range', HEAD + 'listen=06:00-06:00\n' + PROMPT, (5, "empty listening range '06:00-06:00'")),
    ('bad location', HEAD + 'location=mobile\n' + PROMPT,
     (5, "bad location 'mobile' (expected none, fixed, rescue)")),
    ('bad coords', HEAD + 'location=fixed\ncoords=10600,9300\n' + PROMPT,
     (6, "bad coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)")),
    ('coords z out of range', HEAD + 'location=fixed\ncoords=1,2,32\n' + PROMPT,
     (6, "bad coords '1,2,32' (x,y,z whole numbers, z from -32 to 31)")),
    ('unknown action', HEAD + 'actions=say,fly\n' + PROMPT, (5, "unknown action 'fly'")),
    ('duplicate action', HEAD + 'actions=say,say\n' + PROMPT, (5, "duplicate action 'say'")),
    ('bad budget', HEAD + 'budget=-1\n' + PROMPT, (5, "bad budget '-1' (whole number from 0 to 999999)")),
    ('bad action budget', HEAD + 'budget.say=1.5\n' + PROMPT,
     (5, "bad budget.say '1.5' (whole number from 0 to 999999)")),
    ('call_one_in too large', HEAD + 'call_one_in=1001\n' + PROMPT,
     (5, "bad call_one_in '1001' (whole number from 0 to 1000)")),
    ('bad call_text', HEAD + 'call_text=IGUI Call\n' + PROMPT,
     (5, "bad call_text 'IGUI Call' (translation key: A to Z, a to z, 0 to 9 and _)")),
    ('bad state', HEAD + 'state=asleep\n' + PROMPT, (5, "bad state 'asleep' (expected active, silent, gone, dead)")),
    ('missing separator', HEAD + 'You are a test voice.\n', (5, 'expected key=value or [prompt]')),
    ('missing separator at the end', HEAD, (4, 'missing [prompt] line before the prompt text')),
    ('empty file', '', (1, 'missing [prompt] line before the prompt text')),
    ('empty prompt', HEAD + '[prompt]\n \n\t\n', (5, 'empty prompt text after [prompt]')),
    ('missing frequencies', 'format=1\nid=case\nname=Case\n' + PROMPT,
     (4, "missing key 'frequencies' or 'frequency_range'")),
    # Plages de tirage (E05-T07).
    ('range', RANGE_HEAD + PROMPT, None),
    ('two ranges with spaces', RANGE_HEAD.replace('140.0-150.0', '88.0-107.8 , 109.0 - 114.8') + PROMPT, None),
    ('range over all the bounds', RANGE_HEAD.replace('140.0-150.0', '1.0-999.8') + PROMPT, None),
    ('range without dash', RANGE_HEAD.replace('140.0-150.0', '145.0') + PROMPT,
     (4, f"bad frequency range '145.0' {BAD_RANGE}")),
    ('range with two dashes', RANGE_HEAD.replace('140.0-150.0', '1.0-2.0-3.0') + PROMPT,
     (4, f"bad frequency range '1.0-2.0-3.0' {BAD_RANGE}")),
    ('range reversed', RANGE_HEAD.replace('140.0-150.0', '150.0-140.0') + PROMPT,
     (4, f"bad frequency range '150.0-140.0' {BAD_RANGE}")),
    ('range of one frequency', RANGE_HEAD.replace('140.0-150.0', '140.0-140.0') + PROMPT,
     (4, f"bad frequency range '140.0-140.0' {BAD_RANGE}")),
    ('range with an empty part', RANGE_HEAD.replace('140.0-150.0', '140.0-150.0,') + PROMPT,
     (4, f"bad frequency range '' {BAD_RANGE}")),
    ('range bound without decimal', RANGE_HEAD.replace('140.0-150.0', '140-150.0') + PROMPT,
     (4, "bad frequency '140' (MHz with one decimal, e.g. 145.0)")),
    ('range bound off step', RANGE_HEAD.replace('140.0-150.0', '140.0-150.1') + PROMPT,
     (4, 'frequency 150.1 is not on the 0.2 MHz step of the radios')),
    ('range bound out of range', RANGE_HEAD.replace('140.0-150.0', '0.8-2.0') + PROMPT,
     (4, 'frequency 0.8 out of range (1.0 to 999.8 MHz)')),
    ('overlapping ranges', RANGE_HEAD.replace('140.0-150.0', '100.0-110.0,109.0-120.0') + PROMPT,
     (4, "frequency range '109.0-120.0' overlaps another range of the sheet")),
    ('touching ranges', RANGE_HEAD.replace('140.0-150.0', '100.0-110.0,110.0-120.0') + PROMPT,
     (4, "frequency range '110.0-120.0' overlaps another range of the sheet")),
    ('fixed frequencies and range', HEAD + 'frequency_range=140.0-150.0\n' + PROMPT,
     (5, 'frequencies and frequency_range cannot be used together (fixed frequencies or ranges to draw from)')),
    ('range and fixed frequencies', RANGE_HEAD + 'frequencies=145.0\n' + PROMPT,
     (5, 'frequencies and frequency_range cannot be used together (fixed frequencies or ranges to draw from)')),
    ('duplicate range key', RANGE_HEAD + 'frequency_range=1.0-2.0\n' + PROMPT,
     (5, "duplicate key 'frequency_range' (first set on line 4)")),
    ('missing format', 'id=case\nname=Case\nfrequencies=145.0\n' + PROMPT, (4, "missing key 'format'")),
    ('id does not match the file', HEAD.replace('id=case', 'id=other') + PROMPT,
     (2, "id 'other' does not match the file name 'case.txt'")),
    ('fixed without coords', HEAD + 'location=fixed\n' + PROMPT, (5, 'location fixed needs a coords line')),
    ('coords without fixed', HEAD + 'location=rescue\ncoords=1,2,0\n' + PROMPT,
     (6, 'coords is only allowed with location=fixed')),
    ('coords and default location', HEAD + 'coords=1,2,0\n' + PROMPT, (5, 'coords is only allowed with location=fixed')),
    ('call without text', HEAD + 'call_one_in=3\n' + PROMPT, (5, 'call_one_in needs a call_text line')),
    ('budget of a forbidden action', HEAD + 'actions=say\nbudget.signal=1\n' + PROMPT,
     (6, "budget.signal set but action 'signal' is not in actions")),
    ('budget of say by default', HEAD + 'budget.say=5\n' + PROMPT, None),
    # Lieux connus (E07-T04) : place=<id> <x>,<y>,<z> <libellé>, 12 au plus, libellé de 48 octets UTF-8 au plus.
    ('place', HEAD + 'place=mill 10600,9300,0 Old mill\n' + PROMPT, None),
    ('place label of 48 bytes', HEAD + 'place=a 1,2,0 ' + 'é' * 24 + '\n' + PROMPT, None),
    ('place label of 4-byte characters', HEAD + 'place=a 1,2,0 ' + '\U0001F4FB' * 12 + '\n' + PROMPT, None),
    ('place without label', HEAD + 'place=mill 10600,9300,0\n' + PROMPT,
     (5, "bad place 'mill 10600,9300,0' (id x,y,z label, e.g. mill 10600,9300,0 Old mill)")),
    ('place without coords', HEAD + 'place=mill\n' + PROMPT,
     (5, "bad place 'mill' (id x,y,z label, e.g. mill 10600,9300,0 Old mill)")),
    ('place id upper case', HEAD + 'place=Mill 1,2,0 Old mill\n' + PROMPT,
     (5, "bad place id 'Mill' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id with accent', HEAD + 'place=moulïn 1,2,0 Old mill\n' + PROMPT,
     (5, "bad place id 'moulïn' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id too long', HEAD + 'place=' + 'm' * 33 + ' 1,2,0 Old mill\n' + PROMPT,
     (5, "bad place id '" + 'm' * 33 + "' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place coords with two numbers', HEAD + 'place=mill 10600,9300 Old mill\n' + PROMPT,
     (5, "bad place coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)")),
    ('place coords z out of range', HEAD + 'place=mill 1,2,-33 Old mill\n' + PROMPT,
     (5, "bad place coords '1,2,-33' (x,y,z whole numbers, z from -32 to 31)")),
    ('place coords too large', HEAD + 'place=mill 1234567,2,0 Old mill\n' + PROMPT,
     (5, "bad place coords '1234567,2,0' (x,y,z whole numbers, z from -32 to 31)")),
    ('place label too long', HEAD + 'place=a 1,2,0 ' + 'é' * 24 + 'x\n' + PROMPT,
     (5, "place label of 'a' too long (48 bytes of UTF-8 at most)")),
    ('place label too long in 4-byte characters', HEAD + 'place=a 1,2,0 ' + '\U0001F4FB' * 12 + 'x\n' + PROMPT,
     (5, "place label of 'a' too long (48 bytes of UTF-8 at most)")),
    ('duplicate place', HEAD + 'place=mill 1,2,0 Old mill\nplace=mill 3,4,0 Other mill\n' + PROMPT,
     (6, "duplicate place 'mill' (first set on line 5)")),
    ('twelve places', HEAD + ''.join(f'place=p{i} {i},1,0 Place {i}\n' for i in range(12)) + PROMPT, None),
    ('thirteen places', HEAD + ''.join(f'place=p{i} {i},1,0 Place {i}\n' for i in range(13)) + PROMPT,
     (17, 'too many places (12 at most)')),
]

# Résumé canonique d'une fiche, identique en Python et en Lua (comparaison des deux lecteurs).
LUA_CANONICAL = r'''
return function(p)
    local function join(list, sep, f)
        local out = {}
        for _, v in ipairs(list) do out[#out + 1] = f and f(v) or tostring(v) end
        return table.concat(out, sep)
    end
    local keys = {}
    for k in pairs(p.budgets) do keys[#keys + 1] = k end
    table.sort(keys)
    local budgets = {}
    for _, k in ipairs(keys) do budgets[#budgets + 1] = k .. "=" .. tostring(p.budgets[k]) end
    return table.concat({ p.format, p.id, p.name, p.language, join(p.frequencies, ","),
        join(p.frequency_ranges, ",", function(r) return tostring(r.low) .. "-" .. tostring(r.high) end), p.radio,
        join(p.listen, ",", function(r) return tostring(r.from) .. "-" .. tostring(r.to) end), p.location,
        p.coords and (tostring(p.coords.x) .. "," .. tostring(p.coords.y) .. "," .. tostring(p.coords.z)) or "-",
        join(p.knows, ";"), join(p.ignores, ";"), join(p.secrets, ";"),
        join(p.places, ";", function(l) return l.id .. "@" .. tostring(l.x) .. "," .. tostring(l.y) .. ","
            .. tostring(l.z) .. "@" .. l.label end), join(p.actions, ","), tostring(p.budget),
        table.concat(budgets, ","), tostring(p.call_one_in), p.call_text, p.state, p.prompt, p.cache_table, join(p.shares, ","), p.teaches,
        join(p.missions, ","), join(p.rewards, ",") }, "|")
end
'''


def canonical(p: store.Persona) -> str:
    coords = ','.join(str(v) for v in p.coords) if p.coords else '-'
    return '|'.join([p.format, p.id, p.name, p.language, ','.join(map(str, p.frequencies)),
                     ','.join(f'{a}-{b}' for a, b in p.frequency_ranges), p.radio,
                     ','.join(f'{a}-{b}' for a, b in p.listen), p.location, coords, ';'.join(p.knows),
                     ';'.join(p.ignores), ';'.join(p.secrets),
                     ';'.join(f'{q.id}@{q.x},{q.y},{q.z}@{q.label}' for q in p.places), ','.join(p.actions),
                     str(p.budget),
                     ','.join(f'{k}={v}' for k, v in sorted(p.budgets.items())), str(p.call_one_in), p.call_text,
                     p.state, p.prompt, p.cache_table, ','.join(p.shares), p.teaches,
                     ','.join(p.missions), ','.join(p.rewards)])


def raw_bytes(content: str | bytes) -> bytes:
    return content if isinstance(content, bytes) else content.encode('utf-8')


def python_result(path: Path) -> str:
    try:
        return 'OK ' + canonical(store.load_file(path))
    except store.PersonaError as exc:
        return 'ERR ' + str(exc)


class LuaReader:
    """getFileReader of the game: UTF-8 with U+FFFD for invalid bytes, BOM kept, BufferedReader line splitting."""

    def __init__(self, path: Path):
        self.lines = store.split_lines(path.read_bytes().decode('utf-8', errors='replace'))

    def readLine(self):  # noqa: N802 (Java name)
        return self.lines.pop(0) if self.lines else None

    def close(self):
        pass


class LuaPersona:
    def __init__(self, folder: Path):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.rt.globals()
        g.next = None  # absent de Kahlua
        g.isClient = lambda: False
        g.getFileReader = lambda name, create: (LuaReader(folder / name) if (folder / name).is_file() else None)
        self.module = self.rt.execute(PERSONA_LUA.read_text(encoding='utf-8'))
        self.canonical = self.rt.execute(LUA_CANONICAL)

    def result(self, name: str) -> str:
        result = self.module.readFile(name)
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

    def write_case(self, content: str | bytes) -> Path:
        path = self.folder / 'case.txt'
        path.write_bytes(raw_bytes(content))
        return path

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
                         ('case', 'Hélène Dupré', 'fr', 'high_tier', 'fixed', 'silent'))
        self.assertEqual(p.frequencies, [7200, 145000, 999800])
        self.assertEqual(p.listen, [(22 * 60, 6 * 60), (12 * 60 + 30, 13 * 60)])
        self.assertEqual(p.coords, (10600, 9300, -1))
        self.assertEqual(p.knows, ['Le pont de Muldraugh est tombé.', 'Les patrouilles passent à l’aube.'])
        self.assertEqual(p.ignores, ['Ce qui se passe en Ohio.'])
        self.assertEqual(p.secrets, ['Elle a laissé son frère à West Point.'])
        self.assertEqual(p.places, [store.Place('mill', 10600, 9300, 0, 'Vieux moulin'),
                                    store.Place('west_point_2', 11900, 6900, -1, 'Pharmacie  de West Point')])
        self.assertEqual(p.actions, ['say', 'signal', 'mark_map'])
        self.assertEqual((p.budget, p.budgets), (12, {'signal': 2, 'say': 0}))
        self.assertEqual((p.call_one_in, p.call_text), (4, 'IGUI_Test_Call'))
        self.assertEqual(p.prompt, 'Tu es Hélène, infirmière.\n  Ligne indentée, avec = et # gardés.\n\n'
                                   'Dernière ligne 📻.')

    def test_defaults(self):
        p = store.load_file(self.write_case(HEAD + PROMPT))
        self.assertEqual((p.language, p.radio, p.listen, p.location, p.coords, p.actions, p.budget, p.budgets,
                          p.call_one_in, p.call_text, p.state, p.places),
                         ('en', 'any', [], 'none', None, ['say'], 0, {}, 0, '', 'active', []))

    def test_missing_file(self):
        self.assertEqual(self.lua.module.readFile('absent.txt'), (None, 'cannot read absent.txt'))
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
                         ('walt', 'Walt Hensley', 'en', 'any', [], 'none', None, 'active'))
        self.assertEqual((w.actions, w.budget, w.budgets), (['say', 'share_frequency'], 0, {}))  # E07-T10
        self.assertEqual((w.knows, w.ignores, w.secrets), ([], [], []))

    def test_frequency_comes_from_the_sheet(self):
        # E05-T02 : la fiche fait foi ; l'option sandbox RadioSurvivor.Frequency est retirée (fichier et textes).
        # E05-T07 : fréquence tirée dans sa plage à chaque nouvelle partie (145.0 n'est plus qu'un exemple).
        self.assertEqual((self.walt.frequencies, self.walt.frequency_ranges), ([], [(130000, 149800)]))
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


# Chaînes fixes vanilla 42.21 en kHz (media/radio/RadioData.xml) : 10 chaînes TV, puis Hitz FM 89,4, Civilian Radio
# 91,2, LBMW 93,2, USR 94,2, militaire 95,0, NNR 98,0, KnoxTalk 101,2, Unknown Frequency 107,6. L'alerte d'urgence
# (AEBS) tire la sienne au hasard dans 88-108 MHz. Le serveur ne tire jamais une fréquence occupée (E05-T07,
# tests/test_personas_server.py) : seule la plage FM du chroniqueur recoupe ces chaînes.
VANILLA_KHZ = {200, 201, *range(203, 211), 89400, 91200, 93200, 94200, 95000, 98000, 101200, 107600}
AEBS_KHZ = range(88000, 108001)
VOICES = {'walt', 'darlene', 'cody', 'whitaker', 'nightowl', 'gus'}

# Bornes de réglage des radios vanilla 42.21 (media/scripts/generated/items/radio.txt, MinChannel et MaxChannel,
# bornes incluses comme radioReaches de RadioSurvivor_Server.lua) ; vrai = émettrice (TwoWay). Les autoradios
# standard reprennent la plage FM, les radios HAM de véhicule celles de HamRadio1/HamRadio2.
RADIOS = {
    'WalkieTalkie1': (75000, 150000, True), 'WalkieTalkieMakeShift': (75000, 150000, True),
    'WalkieTalkie2': (50000, 200000, True), 'WalkieTalkie3': (25000, 300000, True),
    'WalkieTalkie4': (10000, 500000, True), 'WalkieTalkie5': (200, 1000000, True),
    'ManPackRadio': (200, 1000000, True), 'HamRadio1': (10000, 500000, True),
    'HamRadioMakeShift': (10000, 500000, True), 'HamRadio2': (200, 1000000, True),
    'RadioBlack': (88000, 108000, False), 'RadioRed': (88000, 108000, False), 'RadioMakeShift': (88000, 108000, False),
    'CDplayer': (88000, 108000, False), 'TvBlack': (200, 1000000, False), 'TvAntique': (200, 1000000, False),
    'TvWideScreen': (200, 1000000, False),
}
ALL_TALKIES_HAM = {'WalkieTalkie1', 'WalkieTalkieMakeShift', 'WalkieTalkie2', 'WalkieTalkie3', 'WalkieTalkie4',
                   'WalkieTalkie5', 'ManPackRadio', 'HamRadio1', 'HamRadioMakeShift', 'HamRadio2'}
FM_RADIOS = {'RadioBlack', 'RadioRed', 'RadioMakeShift', 'CDplayer'}


def radios_reaching(khz: int) -> tuple[frozenset[str], frozenset[str]]:
    """(radios qui peuvent parler sur khz, radios qui l'entendent seulement)."""
    talk = frozenset(n for n, (low, high, two_way) in RADIOS.items() if two_way and low <= khz <= high)
    hear = frozenset(n for n, (low, high, two_way) in RADIOS.items() if not two_way and low <= khz <= high)
    return talk, hear


class DeliveredVoicesTests(unittest.TestCase):
    """E05-T04 et E05-T07 : les six fiches livrées sont valides des deux côtés ; plages de tirage."""

    # Décision E05-T07 du 2026-10-09 : plage de chaque voix, fréquence fixe d'E05-T04 gardée comme exemple (les
    # radios qui la joignent sont celles de toute la plage).
    RANGES = {
        'walt': ([(130000, 149800)], [145000]),
        'darlene': ([(115000, 129800)], [115600]),
        'cody': ([(10000, 24800)], [17400]),
        'whitaker': ([(75000, 87800)], [81400]),
        'nightowl': ([(88000, 107800), (109000, 114800)], [106200, 112400]),
        'gus': ([(150200, 199800)], [156600]),
    }

    @classmethod
    def setUpClass(cls):
        cls.sheets = {p.stem: store.load_file(p) for p in sorted(WALT.parent.glob('*.txt'))}

    def test_the_six_voices_are_delivered(self):
        self.assertEqual(set(self.sheets), VOICES)

    def test_valid_in_python_and_lua(self):
        lua = LuaPersona(WALT.parent)
        for vid, sheet in self.sheets.items():
            with self.subTest(vid):
                self.assertEqual(lua.result(f'{vid}.txt'), 'OK ' + canonical(sheet))
                self.assertFalse((WALT.parent / f'{vid}.txt').read_bytes().startswith(b'\xef\xbb\xbf'))

    def test_every_voice_draws_its_frequencies(self):
        # Toutes les voix, Walt compris (décision du 2026-10-09) : aucune fréquence fixe livrée.
        for vid, sheet in self.sheets.items():
            with self.subTest(vid):
                self.assertEqual(sheet.frequencies, [])
                self.assertEqual(sheet.frequency_ranges, self.RANGES[vid][0])

    def test_ranges_are_disjoint_and_wide(self):
        ranges = sorted(r for s in self.sheets.values() for r in s.frequency_ranges)
        for (_, high), (low, _) in zip(ranges, ranges[1:]):
            self.assertLess(high, low, ranges)
        for low, high in ranges:
            self.assertGreaterEqual((high - low) // 200 + 1, 30, (low, high))  # au moins 30 fréquences

    def test_ranges_keep_the_radios_that_reach_the_voice(self):
        # Chaque fréquence de la plage est jointe (parler) et entendue par exactement les mêmes radios que la
        # fréquence d'exemple d'E05-T04 (document de travail E05-T04, section 1).
        for vid, (ranges, examples) in self.RANGES.items():
            for (low, high), example in zip(ranges, examples):
                expected = radios_reaching(example)
                with self.subTest(vid=vid, example=example):
                    self.assertTrue(low <= example <= high)
                    for khz in range(low, high + 1, 200):
                        self.assertEqual(radios_reaching(khz), expected, khz)

    def test_radios_named_by_the_decision(self):
        walkie = {'WalkieTalkie2', 'WalkieTalkie3', 'WalkieTalkie4', 'WalkieTalkie5', 'ManPackRadio', 'HamRadio1',
                  'HamRadioMakeShift', 'HamRadio2'}
        shortwave = {'WalkieTalkie4', 'WalkieTalkie5', 'ManPackRadio', 'HamRadio1', 'HamRadioMakeShift', 'HamRadio2'}
        expected = {
            'walt': [(ALL_TALKIES_HAM, set())], 'darlene': [(ALL_TALKIES_HAM, set())],
            'whitaker': [(ALL_TALKIES_HAM, set())], 'cody': [(shortwave, set())], 'gus': [(walkie, set())],
            'nightowl': [(ALL_TALKIES_HAM, FM_RADIOS), (ALL_TALKIES_HAM, set())],
        }
        for vid, sides in expected.items():
            for (low, _), (talk, hear) in zip(self.RANGES[vid][0], sides):
                with self.subTest(vid=vid, low=low):
                    got_talk, got_hear = radios_reaching(low)
                    self.assertEqual(set(got_talk), talk)
                    self.assertEqual(set(got_hear) - {'TvBlack', 'TvAntique', 'TvWideScreen'}, hear)

    def test_no_range_on_reserved_frequencies(self):
        for vid, sheet in self.sheets.items():
            for low, high in sheet.frequency_ranges:
                with self.subTest(vid=vid, low=low):
                    self.assertFalse(low <= 108000 <= high)  # Opération Artemis, 108,0 par défaut
                    in_aebs = low <= AEBS_KHZ[-1] and high >= AEBS_KHZ[0]
                    self.assertEqual(in_aebs, (vid, low) == ('nightowl', 88000))
                    if not in_aebs:
                        self.assertEqual({k for k in VANILLA_KHZ if low <= k <= high}, set())

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
        # Décision E05-T04 du 2026-10-09 (docs/annexes/plans/E05-voix-reseau-radio.md), fréquences : E05-T07.
        expected = {
            'darlene': ([(420, 600), (960, 1140)], 'fixed', (11880, 6878, 0), 'active'),
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
                                 ('en', 'any', actions, self.CALLS[vid], 0, {}))
                if vid in ('darlene', 'cody'):
                    self.assertEqual(s.cache_table, 'medical' if vid == 'darlene' else 'ammo')
                    self.assertEqual(s.teaches, 'Doctor' if vid == 'darlene' else 'Aiming')
                    self.assertEqual(s.missions, list(store.MISSION_TEMPLATES))
                    self.assertEqual(s.rewards, list(store.REWARDS))
                    self.assertTrue(s.places and s.shares)
                self.assertTrue(s.knows and s.ignores and s.secrets)
                self.assertIn('Answer in the same language the caller uses.', s.prompt)


if __name__ == '__main__':
    unittest.main(verbosity=1)
