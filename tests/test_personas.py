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
MOD = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21'
LUA = MOD / 'media/lua'
CORE_LUA = ROOT / 'Contents/mods/batman_CoreAI/42.21/media/lua'
PERSONA_LUA = LUA / 'server/RadioSurvivor/RS_Persona.lua'
LUA_PATH = ';'.join(f'{(root / side).as_posix()}/?.lua' for root in (CORE_LUA, LUA) for side in ('shared', 'server'))
# Gabarits de mission qui s'inscrivent dans CA_Missions (deliver est déclaré par CA_Missions même).
TEMPLATE_MODULES = ('CoreAI/CA_MissionScout', 'CoreAI/CA_MissionClear',
                    'CoreAI/CA_MissionRetrieve', 'CoreAI/CA_MissionSignal',
                    'CoreAI/CA_MissionBarricade')  # E20-T10: secure_clinic of darlene.txt
# Natures de récompense qui s'inscrivent dans RS_Rewards (E20-T04 : un fichier par nature, server/RadioSurvivor/Rewards/).
REWARD_KIND_MODULES = tuple(f'RadioSurvivor/Rewards/{p.stem}' for p in sorted(
    (LUA / 'server/RadioSurvivor/Rewards').glob('*.lua'), key=lambda p: p.name.lower()))
# Modes d'arrivée des marchands qui s'inscrivent dans RS_TradeArrivals (E20-T07 : un fichier par mode,
# server/RadioSurvivor/TradeArrivals/).
ARRIVAL_MODULES = tuple(f'RadioSurvivor/TradeArrivals/{p.stem}' for p in sorted(
    (LUA / 'server/RadioSurvivor/TradeArrivals').glob('*.lua'), key=lambda p: p.name.lower()))
# Modules chargés par le jeu avant la lecture des fiches : leurs inscriptions forment les règles du lecteur.
RULE_MODULES = TEMPLATE_MODULES + REWARD_KIND_MODULES + ARRIVAL_MODULES
# Doublures minimales du jeu pour charger ces modules (côté autorité, solo).
RULES_STUBS = '''
isClient = function() return false end
isServer = function() return false end
Events = setmetatable({}, {__index = function(t, k) local e = {Add = function() end, Remove = function() end}
    rawset(t, k, e) return e end})
'''
# Fiches livrées : seul exemplaire du dépôt, dans le mod (E05-T10).
WALT = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/personas/walt.txt'
sys.path.insert(0, str(ROOT / 'bridge'))
import persona_store as store  # noqa: E402
from signalsmoke_double import SIGNAL_SMOKE  # noqa: E402
from itemweights_double import ITEM_WEIGHTS  # noqa: E402

# E24-T01 : radio=<niveau> (fréquence libre tirée à chaque partie dans la zone du niveau) ou frequency= (une fréquence
# fixe), l'une des deux exactement.
BASE = 'format=1\nid=case\nname=Case\n'
HEAD = BASE + 'radio=any_talkie\n'
FIXED_HEAD = BASE + 'frequency=145.0\n'
BOTH = 'radio and frequency cannot be used together (a radio level to draw a free frequency, or one fixed frequency)'
LEVELS = ('any_talkie', 'good_talkie', 'pro_talkie', 'tactical', 'military')
PROMPT = '[prompt]\nYou are a test voice.\n'
PLACE = '[place mill]\nat=10600,9300,0\nlabel=Old mill\nuse=mark\n'


def place(ident: str, at: str = '1,2,0', label: str = 'Place', use: str = 'mark') -> str:
    """One [place] section of four lines."""
    return f'[place {ident}]\nat={at}\nlabel={label}\nuse={use}\n'


FULL = ('# fiche complète\n'
        'format=1\n'
        ' id = case \n'
        'name=Hélène Dupré\n'
        'language=fr\n'
        'frequency= 7.2 \n'
        'listen=22:00-06:00,12:30-13:00\n'
        'location=fixed\n'
        'coords=10600,9300,-1\n'
        'actions=say, signal,mark_map\n'
        'budget=12\n'
        'budget.signal=2\n'
        'budget.say=0\n'
        'call_one_in=4\n'
        'call_text=IGUI_Test_Call\n'
        'state=silent\n'
        '\n'
        '[place mill]\n'
        'at=10600,9300,0\n'
        'label=Vieux moulin\n'
        'use=mark\n'
        '# lieu à deux usages\n'
        ' [ place   west_point_2 ] \n'
        ' at = 11900,6900,-1 \n'
        'label= \t Pharmacie  de West Point \n'
        'use=drop, mark\n'
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
    ('shares', HEAD + 'shares=gus,cody\nactions=say,share_frequency\n' + PROMPT, None),
    ('bad shares', HEAD + 'shares=Gus\n' + PROMPT, (5, "bad shares entry 'Gus'")),
    ('duplicate shares', HEAD + 'shares=gus,gus\n' + PROMPT, (5, "duplicate shares entry 'gus'")),
    ('empty shares entry', HEAD + 'shares=gus,\n' + PROMPT, (5, "bad shares entry ''")),

    ('full', FULL, None),
    ('crlf', (HEAD + PROMPT).replace('\n', '\r\n'), None),
    ('lone cr', (HEAD + PROMPT).replace('\n', '\r'), None),
    ('no final newline', HEAD + PROMPT.rstrip('\n'), None),
    ('bom', '\ufeff' + HEAD + PROMPT,
     (1, 'file starts with a byte order mark (save it as UTF-8 without BOM)')),
    ('invalid utf-8 in a value', HEAD.encode() + b'language=caf\xe9\n' + PROMPT.encode(),
     (5, 'invalid UTF-8 (save the file as UTF-8)')),
    ('invalid utf-8 in the prompt', (HEAD + PROMPT).encode() + b'\xff\xfe\n',
     (7, 'invalid UTF-8 (save the file as UTF-8)')),
    ('no equal sign', HEAD + 'location none\n' + PROMPT, (5, 'expected key=value or [prompt]')),
    ('bad key', HEAD + 'Radio=any\n' + PROMPT, (5, "bad key 'Radio'")),
    ('unknown key', HEAD + 'colour=red\n' + PROMPT, (5, "unknown key 'colour'")),
    ('unknown budget action', HEAD + 'budget.fly=1\n' + PROMPT, (5, "unknown action 'fly' in key 'budget.fly'")),
    ('duplicate key', HEAD + 'name=Other\n' + PROMPT, (5, "duplicate key 'name' (first set on line 3)")),
    ('empty value', HEAD + 'location=\n' + PROMPT, (5, "empty value for key 'location'")),
    ('format', HEAD.replace('format=1', 'format=2') + PROMPT, (1, "unsupported format '2' (expected 1)")),
    ('bad id', HEAD.replace('id=case', 'id=Case') + PROMPT,
     (2, "bad id 'Case' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")),
    ('id too long', HEAD.replace('id=case', 'id=' + 'a' * 33) + PROMPT,
     (2, "bad id '" + 'a' * 33 + "' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")),
    ('id with accent', HEAD.replace('id=case', 'id=cas\u00e9') + PROMPT,
     (2, "bad id 'cas\u00e9' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")),
    ('bad language', HEAD + 'language=eng\n' + PROMPT, (5, "bad language 'eng' (two lowercase letters, e.g. en)")),
    *((f'radio {level}', BASE + f'radio={level}\n' + PROMPT, None) for level in LEVELS),
    ('fixed frequency', FIXED_HEAD + PROMPT, None),
    ('lowest fixed frequency', FIXED_HEAD.replace('145.0', '0.2') + PROMPT, None),
    ('highest fixed frequency', FIXED_HEAD.replace('145.0', '1000.0') + PROMPT, None),
    ('frequency without decimal', FIXED_HEAD.replace('145.0', '145') + PROMPT,
     (4, "bad frequency '145' (MHz with one decimal, e.g. 145.0)")),
    ('frequency with a comma', FIXED_HEAD.replace('145.0', '145,0') + PROMPT,
     (4, "bad frequency '145,0' (MHz with one decimal, e.g. 145.0)")),
    ('two frequencies', FIXED_HEAD.replace('145.0', '145.0,7.2') + PROMPT,
     (4, "bad frequency '145.0,7.2' (MHz with one decimal, e.g. 145.0)")),
    ('frequency below the radios', FIXED_HEAD.replace('145.0', '0.0') + PROMPT,
     (4, 'frequency 0.0 out of range (0.2 to 1000.0 MHz)')),
    ('frequency above the radios', FIXED_HEAD.replace('145.0', '1000.2') + PROMPT,
     (4, 'frequency 1000.2 out of range (0.2 to 1000.0 MHz)')),
    ('frequency off step', FIXED_HEAD.replace('145.0', '145.1') + PROMPT,
     (4, 'frequency 145.1 is not on the 0.2 MHz step of the radios')),
    ('bad radio', BASE + 'radio=ham\n' + PROMPT,
     (4, "bad radio 'ham' (expected any_talkie, good_talkie, pro_talkie, tactical, military)")),
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
    ('neither radio nor frequency', BASE + PROMPT, (4, "missing key 'radio' or 'frequency'")),
    ('radio and frequency', HEAD + 'frequency=145.0\n' + PROMPT, (5, BOTH)),
    ('frequency and radio', FIXED_HEAD + 'radio=military\n' + PROMPT, (5, BOTH)),
    ('duplicate frequency key', FIXED_HEAD + 'frequency=7.2\n' + PROMPT,
     (5, "duplicate key 'frequency' (first set on line 4)")),
    ('missing format', 'id=case\nname=Case\nradio=any_talkie\n' + PROMPT, (4, "missing key 'format'")),
    ('id does not match the file', HEAD.replace('id=case', 'id=other') + PROMPT,
     (2, "id 'other' does not match the file name 'case.txt'")),
    ('fixed without coords', HEAD + 'location=fixed\n' + PROMPT, (5, 'location fixed needs a coords line')),
    ('coords without fixed', HEAD + 'location=rescue\ncoords=1,2,0\n' + PROMPT,
     (6, 'coords is only allowed with location=fixed')),
    ('coords and default location', HEAD + 'coords=1,2,0\n' + PROMPT, (5, 'coords is only allowed with location=fixed')),
    ('call without text', HEAD + 'call_one_in=3\n' + PROMPT, (5, 'call_one_in needs a call or call_text line')),
    # E22-T07 : appel écrit dans la fiche (call=), à la place de la clé call_text.
    ('call written in the sheet', HEAD + 'call_one_in=3\ncall=Anyone out there? Mae on %1, over.\n' + PROMPT, None),
    ('call of 200 bytes', HEAD + 'call=' + 'é' * 100 + '\n' + PROMPT, None),
    ('call too long', HEAD + 'call=' + 'é' * 100 + 'a\n' + PROMPT, (5, 'call too long (200 bytes of UTF-8 at most)')),
    ('call with a tag', HEAD + 'call=Hello <fzzt>\n' + PROMPT,
     (5, "bad call 'Hello <fzzt>' (no <, > or ^; % only in %1, the frequency)")),
    ('call with a percent', HEAD + 'call=100% sure on %1\n' + PROMPT,
     (5, "bad call '100% sure on %1' (no <, > or ^; % only in %1, the frequency)")),
    ('call and call_text', HEAD + 'call_text=IGUI_Call\ncall=Hello\n' + PROMPT,
     (6, 'call and call_text cannot be used together (text written in the sheet or translation key)')),
    ('duplicate call', HEAD + 'call=Hello\ncall=Bye\n' + PROMPT, (6, "duplicate key 'call' (first set on line 5)")),
    ('budget of a forbidden action', HEAD + 'actions=say\nbudget.signal=1\n' + PROMPT,
     (6, "budget.signal set but action 'signal' is not in actions")),
    ('budget of say by default', HEAD + 'budget.say=5\n' + PROMPT, None),
    # Sections (E20-T03, ADR D04) : [place <id>] lu par les deux lecteurs ; [mission], [rewards] et [category] passés
    # par le pont (le serveur les valide : tests/test_persona_sections.py). Lieux : 12 au plus, libellé de 48 octets
    # UTF-8 au plus.
    ('place', HEAD + PLACE + PROMPT, None),
    ('place with every use', HEAD + PLACE.replace('use=mark', 'use=mark,target,drop,landing') + PROMPT, None),
    ('place label of 48 bytes', HEAD + place('a', label='é' * 24) + PROMPT, None),
    ('place label of 4-byte characters', HEAD + place('a', label='\U0001F4FB' * 12) + PROMPT, None),
    ('place without at', HEAD + '[place mill]\nlabel=Old mill\nuse=mark\n' + PROMPT,
     (5, "missing key 'at' in [place mill]")),
    ('place without label', HEAD + '[place mill]\nat=1,2,0\nuse=mark\n' + PROMPT,
     (5, "missing key 'label' in [place mill]")),
    ('place without use', HEAD + '[place mill]\nat=1,2,0\nlabel=Old mill\n' + PROMPT,
     (5, "missing key 'use' in [place mill]")),
    ('place id upper case', HEAD + PLACE.replace('[place mill]', '[place Mill]') + PROMPT,
     (5, "bad place id 'Mill' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id with accent', HEAD + PLACE.replace('[place mill]', '[place moulïn]') + PROMPT,
     (5, "bad place id 'moulïn' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id too long', HEAD + PLACE.replace('[place mill]', '[place ' + 'm' * 33 + ']') + PROMPT,
     (5, "bad place id '" + 'm' * 33 + "' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id with a space', HEAD + PLACE.replace('[place mill]', '[place old mill]') + PROMPT,
     (5, "bad place id 'old mill' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('section without id', HEAD + PLACE.replace('[place mill]', '[place]') + PROMPT,
     (5, 'section [place] needs an id, e.g. [place mill]')),
    ('mission section without id', HEAD + '[mission]\ntype=scout\n' + PROMPT,
     (5, 'section [mission] needs an id, e.g. [mission meds]')),
    ('rewards section with an id', HEAD + '[rewards main]\npool=frequency:1\n' + PROMPT,
     (5, 'section [rewards] takes no id')),
    ('unknown section', HEAD + '[shop gus]\nstock=food\n' + PROMPT,
     (5, "unknown section 'shop' (expected place, mission, rewards, category, trade, note or prompt)")),
    ('place coords with two numbers', HEAD + PLACE.replace('10600,9300,0', '10600,9300') + PROMPT,
     (6, "bad place coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)")),
    ('place coords z out of range', HEAD + PLACE.replace('10600,9300,0', '1,2,-33') + PROMPT,
     (6, "bad place coords '1,2,-33' (x,y,z whole numbers, z from -32 to 31)")),
    ('place coords too large', HEAD + PLACE.replace('10600,9300,0', '1234567,2,0') + PROMPT,
     (6, "bad place coords '1234567,2,0' (x,y,z whole numbers, z from -32 to 31)")),
    ('place label too long', HEAD + place('a', label='é' * 24 + 'x') + PROMPT,
     (7, "place label of 'a' too long (48 bytes of UTF-8 at most)")),
    ('place label too long in 4-byte characters', HEAD + place('a', label='\U0001F4FB' * 12 + 'x') + PROMPT,
     (7, "place label of 'a' too long (48 bytes of UTF-8 at most)")),
    ('bad use', HEAD + PLACE.replace('use=mark', 'use=mark,hide') + PROMPT,
     (8, "bad use entry 'hide' (expected mark, target, drop, landing)")),
    ('duplicate use', HEAD + PLACE.replace('use=mark', 'use=mark,mark') + PROMPT, (8, "duplicate use entry 'mark'")),
    ('empty use entry', HEAD + PLACE.replace('use=mark', 'use=mark,') + PROMPT,
     (8, "bad use entry '' (expected mark, target, drop, landing)")),
    ('unknown place key', HEAD + PLACE + 'colour=red\n' + PROMPT, (9, "unknown key 'colour' in [place mill]")),
    ('head key after a section', HEAD + PLACE + 'location=none\n' + PROMPT,
     (9, "unknown key 'location' in [place mill]")),
    ('duplicate place key', HEAD + PLACE + 'at=1,2,0\n' + PROMPT,
     (9, "duplicate key 'at' in [place mill] (first set on line 6)")),
    ('empty place value', HEAD + PLACE.replace('label=Old mill', 'label=') + PROMPT,
     (7, "empty value for key 'label'")),
    ('place line without equal sign', HEAD + PLACE + 'Old mill\n' + PROMPT, (9, 'expected key=value or [prompt]')),
    ('duplicate place', HEAD + PLACE + PLACE.replace('10600,9300,0', '3,4,0') + PROMPT,
     (9, "duplicate place 'mill' (first set on line 5)")),
    ('twelve places', HEAD + ''.join(place(f'p{i}') for i in range(12)) + PROMPT, None),
    ('thirteen places', HEAD + ''.join(place(f'p{i}') for i in range(13)) + PROMPT,
     (53, 'too many places (12 at most)')),
    ('duplicate mission section', HEAD + '[mission a]\ntype=scout\n[mission a]\ntype=clear\n' + PROMPT,
     (7, "duplicate mission 'a' (first set on line 5)")),
    ('duplicate rewards section', HEAD + '[rewards]\npool=frequency:1\n[rewards]\npool=stashmap:1\n' + PROMPT,
     (7, 'duplicate section [rewards] (first set on line 5)')),
    ('sections read by the server only', HEAD + PLACE.replace('use=mark', 'use=drop')
     + '[mission meds]\ntype=deliver\nitems=medical\nquantity=2-4\ndrops=any\n'
     + '[category snacks]\nitem=Base.Crisps:1-2\n[rewards]\npool=cache:snacks:2, frequency:1\n' + PROMPT, None),
]

# Résumé canonique d'une fiche, identique en Python et en Lua (comparaison des deux lecteurs).
# E24-T01 : le pont garde la radio écrite (None avec frequency=) ; le serveur déduit celle d'une fréquence fixe.
# Pas de commentaire dans LUA_CANONICAL : tests/test_kahlua.py le met sur une seule ligne.
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
    return table.concat({ p.format, p.id, p.name, p.language, p.frequency and tostring(p.frequency) or "-",
        p.frequency and "-" or p.radio,
        join(p.listen, ",", function(r) return tostring(r.from) .. "-" .. tostring(r.to) end), p.location,
        p.coords and (tostring(p.coords.x) .. "," .. tostring(p.coords.y) .. "," .. tostring(p.coords.z)) or "-",
        join(p.places, ";", function(l) return l.id .. "@" .. tostring(l.x) .. "," .. tostring(l.y) .. ","
            .. tostring(l.z) .. "@" .. l.label .. "@" .. join(l.uses, ",") end), join(p.actions, ","),
        tostring(p.budget), table.concat(budgets, ","), tostring(p.call_one_in), p.call_text, p.call, p.state, p.prompt,
        join(p.shares, ",") }, "|")
end
'''


def canonical(p: store.Persona) -> str:
    coords = ','.join(str(v) for v in p.coords) if p.coords else '-'
    return '|'.join([p.format, p.id, p.name, p.language, str(p.frequency) if p.frequency is not None else '-',
                     p.radio or '-',
                     ','.join(f'{a}-{b}' for a, b in p.listen), p.location, coords,
                     ';'.join(f'{q.id}@{q.x},{q.y},{q.z}@{q.label}@{",".join(q.uses)}' for q in p.places), ','.join(p.actions),
                     str(p.budget),
                     ','.join(f'{k}={v}' for k, v in sorted(p.budgets.items())), str(p.call_one_in), p.call_text, p.call,
                     p.state, p.prompt, ','.join(p.shares)])


def lua_items(t) -> list:
    """Liste Python des éléments d'un tableau Lua (indices 1..n), [] pour nil."""
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


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

    def read(self, name: str):
        """Fiche lue par le serveur : table Lua, ou (None, raison)."""
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
                         ('case', 'Hélène Dupré', 'fr', None, 'fixed', 'silent'))
        self.assertEqual(p.frequency, 7200)
        self.assertEqual(p.listen, [(22 * 60, 6 * 60), (12 * 60 + 30, 13 * 60)])
        self.assertEqual(p.coords, (10600, 9300, -1))
        self.assertEqual(p.places, [store.Place('mill', 10600, 9300, 0, 'Vieux moulin', ('mark',)),
                                    store.Place('west_point_2', 11900, 6900, -1, 'Pharmacie  de West Point',
                                                ('drop', 'mark'))])
        self.assertEqual([q.id for q in p.places_for('mark')], ['mill', 'west_point_2'])
        self.assertEqual([q.id for q in p.places_for('drop')], ['west_point_2'])
        self.assertEqual(p.actions, ['say', 'signal', 'mark_map'])
        self.assertEqual((p.budget, p.budgets), (12, {'signal': 2, 'say': 0}))
        self.assertEqual((p.call_one_in, p.call_text), (4, 'IGUI_Test_Call'))
        self.assertEqual(p.prompt, 'Tu es Hélène, infirmière.\n  Ligne indentée, avec = et # gardés.\n\n'
                                   'Dernière ligne 📻.')

    def test_defaults(self):
        p = store.load_file(self.write_case(HEAD + PROMPT))
        self.assertEqual((p.language, p.radio, p.listen, p.location, p.coords, p.actions, p.budget, p.budgets,
                          p.call_one_in, p.call_text, p.state, p.places),
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
                    # Missions, récompenses et catégories : lues par le serveur seul (tests/test_persona_sections.py).
                    self.assertTrue(s.places and s.shares)
                self.assertIn('Answer in the same language the caller uses.', s.prompt)


if __name__ == '__main__':
    unittest.main(verbosity=1)
