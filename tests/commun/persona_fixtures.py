"""Voice sheet fixtures (E26, moved from tests/radiosurvivor/test_personas.py): sheet texts and places (HEAD, FULL, place...), the
canonical form of a sheet read by bridge/persona_store.py and by RS_Persona.lua, and the module list of the server
rules. Shared by the RadioSurvivor tests and the Kahlua bench (tests/coreai/test_kahlua.py)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
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
PLACES_HEAD = 'format=1\n'
# E27-T02 : fin du message d'un métier inconnu de [help] (métiers de RS_RecipeJobs, triés).
JOBS_HINT = ('(expected carpentry, cooking, electrical, farming, makeshift, mechanics, medical, pottery, smithing, '
             'tailoring, weapons)')


def place(ident: str, at: str = '1,2,0', label: str = 'Place', area: str | None = None) -> str:
    """One [place] section of three lines of the shared file _places.txt (E25-T01): a point (at=) or a zone (area=)."""
    where = f'area={area}' if area is not None else f'at={at}'
    return f'[place {ident}]\n{where}\nlabel={label}\n'


# Shared places of the voice cases, written as _places.txt next to case.txt: two points, a zone, then p0 to p12.
PLACES = (PLACES_HEAD + place('mill', '10600,9300,0', 'Vieux moulin')
          + place('west_point_2', '11900,6900,-1', 'Pharmacie  de West Point')
          + place('town', label='Old town', area='100,200,50,150,0')
          + ''.join(place(f'p{i}') for i in range(13)))


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
    # Sections (E20-T03, ADR D04) : [mission], [rewards], [category], [trade] et [note] passées par le pont (le serveur
    # les valide : tests/radiosurvivor/test_persona_sections.py). E25-T01 : plus de [place] dans une fiche ; la tête nomme les repères
    # de la voix (marks=, 12 au plus) parmi les lieux communs _places.txt, lus par les deux lecteurs.
    ('marks', HEAD + 'marks=mill,town\n' + PROMPT, None),
    ('marks with spaces', HEAD + 'marks= west_point_2 , mill \n' + PROMPT, None),
    ('unknown mark', HEAD + 'marks=mill,ghost\n' + PROMPT, (5, "unknown place 'ghost'")),
    ('duplicate mark', HEAD + 'marks=mill,town,mill\n' + PROMPT, (5, "duplicate marks entry 'mill'")),
    ('bad mark', HEAD + 'marks=Mill\n' + PROMPT, (5, "bad marks entry 'Mill'")),
    ('empty mark entry', HEAD + 'marks=mill,\n' + PROMPT, (5, "bad marks entry ''")),
    ('twelve marks', HEAD + 'marks=' + ','.join(f'p{i}' for i in range(12)) + '\n' + PROMPT, None),
    ('thirteen marks', HEAD + 'marks=' + ','.join(f'p{i}' for i in range(13)) + '\n' + PROMPT,
     (5, 'too many marks (12 at most)')),
    ('place section in a voice', HEAD + place('mill') + PROMPT,
     (5, "unknown section 'place' (expected mission, rewards, category, trade, note, help or prompt)")),
    ('mission section without id', HEAD + '[mission]\ntype=scout\n' + PROMPT,
     (5, 'section [mission] needs an id, e.g. [mission meds]')),
    ('rewards section with an id', HEAD + '[rewards main]\npool=frequency:1\n' + PROMPT,
     (5, 'section [rewards] takes no id')),
    ('unknown section', HEAD + '[shop gus]\nstock=food\n' + PROMPT,
     (5, "unknown section 'shop' (expected mission, rewards, category, trade, note, help or prompt)")),
    ('mission id upper case', HEAD + '[mission Meds]\ntype=scout\n' + PROMPT,
     (5, "bad mission id 'Meds' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('duplicate mission section', HEAD + '[mission a]\ntype=scout\n[mission a]\ntype=clear\n' + PROMPT,
     (7, "duplicate mission 'a' (first set on line 5)")),
    ('duplicate rewards section', HEAD + '[rewards]\npool=frequency:1\n[rewards]\npool=stashmap:1\n' + PROMPT,
     (7, 'duplicate section [rewards] (first set on line 5)')),
    ('sections read by the server only', HEAD + 'marks=mill\n'
     + '[mission meds]\ntype=deliver\nitems=medical\nquantity=2-4\ndrops=mill,west_point_2\n'
     + '[mission look]\ntype=scout\ntarget=town\nbuilding=church\n'
     + '[category snacks]\nitem=Base.Crisps:1-2\n[rewards]\npool=cache:snacks:2, frequency:1\ncache_place=mill\n'
     + PROMPT, None),
    # E27-T02 : [help], lue par les deux lecteurs (métiers de RS_RecipeJobs, palier, délai), lignes 5 et suivantes.
    ('help', HEAD + '[help]\njobs=cooking, medical\nfrom=good\ndelay=half_day\n' + PROMPT, None),
    ('help defaults', HEAD + '[help]\njobs=farming\n' + PROMPT, None),
    ('help every level and delay', HEAD + '[help]\njobs=makeshift\nfrom=all\ndelay=day\n' + PROMPT, None),
    ('help without jobs', HEAD + '[help]\nfrom=all\n' + PROMPT, (5, "missing key 'jobs' in [help]")),
    ('help without jobs before a section', HEAD + '[help]\ndelay=hour\n[rewards]\npool=stashmap:1\n' + PROMPT,
     (5, "missing key 'jobs' in [help]")),
    ('help unknown job', HEAD + '[help]\njobs=cooking,baking\n' + PROMPT, (6, f"unknown job 'baking' {JOBS_HINT}")),
    ('help empty job entry', HEAD + '[help]\njobs=cooking,\n' + PROMPT, (6, f"unknown job '' {JOBS_HINT}")),
    ('help duplicate job', HEAD + '[help]\njobs=cooking, cooking\n' + PROMPT, (6, "duplicate job 'cooking'")),
    ('help unknown level', HEAD + '[help]\njobs=cooking\nfrom=friends\n' + PROMPT,
     (7, "bad from 'friends' (expected all, neutral, good)")),
    ('help unknown delay', HEAD + '[help]\njobs=cooking\ndelay=week\n' + PROMPT,
     (7, "bad delay 'week' (expected now, hour, half_day, day)")),
    ('help unknown key', HEAD + '[help]\njobs=cooking\ncolour=red\n' + PROMPT, (7, "unknown key 'colour' in [help]")),
    ('help duplicate key', HEAD + '[help]\njobs=cooking\njobs=medical\n' + PROMPT,
     (7, "duplicate key 'jobs' in [help] (first set on line 6)")),
    ('help empty value', HEAD + '[help]\njobs=cooking\nfrom=\n' + PROMPT, (7, "empty value for key 'from'")),
    ('help bad key', HEAD + '[help]\nJobs=cooking\n' + PROMPT, (6, "bad key 'Jobs'")),
    ('help line without equal sign', HEAD + '[help]\ncooking\n' + PROMPT, (6, 'expected key=value or [prompt]')),
    ('help with an id', HEAD + '[help cook]\njobs=cooking\n' + PROMPT, (5, 'section [help] takes no id')),
    ('help twice', HEAD + '[help]\njobs=cooking\n[help]\njobs=medical\n' + PROMPT,
     (7, 'duplicate section [help] (first set on line 5)')),
]

# E25-T01 : fichier commun des lieux _places.txt, lu par les deux lecteurs (mêmes règles, mêmes messages). Un point
# (at=) ou une zone (area=, deux coins dans n'importe quel ordre, côtés de 1 à 1500 cases), un libellé de 48 octets
# UTF-8 au plus ; 500 lieux au plus ; near, far et very_far sont des distances, jamais des identifiants de lieu.
PLACE = place('mill', '10600,9300,0', 'Old mill')                  # lignes 2 à 4 après PLACES_HEAD
BAD_AREA = "(x1,y1,x2,y2,z whole numbers, sides 1 to 1500)"
PLACES_CASES: list[tuple[str, str | bytes, tuple[int, str] | None]] = [
    ('point', PLACES_HEAD + PLACE, None),
    ('zone', PLACES_HEAD + place('town', area='100,200,50,150,0'), None),
    ('zone of one tile', PLACES_HEAD + place('spot', area='5,5,5,5,-1'), None),
    ('zone of 1500 tiles', PLACES_HEAD + place('county', area='0,10,1499,1508,0'), None),
    ('no place', PLACES_HEAD, None),
    ('comments and blank lines', '# shared places\n\nformat=1\n\n# the mill\n' + PLACE + '\n', None),
    ('crlf', (PLACES_HEAD + PLACE).replace('\n', '\r\n'), None),
    ('label of 48 bytes', PLACES_HEAD + place('a', label='é' * 24), None),
    ('label of 4-byte characters', PLACES_HEAD + place('a', label='\U0001F4FB' * 12), None),
    ('spaces around', PLACES_HEAD + ' [ place   west_point_2 ] \n at = 11900,6900,-1 \nlabel= \t Pharmacie \n', None),
    ('bom', '﻿' + PLACES_HEAD + PLACE, (1, 'file starts with a byte order mark (save it as UTF-8 without BOM)')),
    ('invalid utf-8', PLACES_HEAD.encode() + b'[place mill]\nat=1,2,0\nlabel=caf\xe9\n', (4, 'invalid UTF-8 (save the file as UTF-8)')),
    ('missing format', PLACE, (1, "missing key 'format'")),
    ('missing format without place', '# nothing\n', (1, "missing key 'format'")),
    ('empty file', '', (1, "missing key 'format'")),
    ('format 2', 'format=2\n' + PLACE, (1, "unsupported format '2' (expected 1)")),
    ('unknown head key', PLACES_HEAD + 'colour=red\n' + PLACE, (2, "unknown key 'colour'")),
    ('duplicate format', PLACES_HEAD + 'format=1\n', (2, "duplicate key 'format' (first set on line 1)")),
    ('head line without equal sign', PLACES_HEAD + 'mill\n', (2, 'expected key=value or [place <id>]')),
    ('other section', PLACES_HEAD + '[category a]\nitem=Base.A:1\n', (2, "unknown section 'category' (expected place)")),
    ('section without id', PLACES_HEAD + PLACE.replace('[place mill]', '[place]'),
     (2, 'section [place] needs an id, e.g. [place mill]')),
    ('place id upper case', PLACES_HEAD + PLACE.replace('[place mill]', '[place Mill]'),
     (2, "bad place id 'Mill' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id with accent', PLACES_HEAD + PLACE.replace('[place mill]', '[place moulïn]'),
     (2, "bad place id 'moulïn' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id too long', PLACES_HEAD + PLACE.replace('[place mill]', '[place ' + 'm' * 33 + ']'),
     (2, "bad place id '" + 'm' * 33 + "' (a to z, 0 to 9 and _, 32 characters at most)")),
    ('place id with a space', PLACES_HEAD + PLACE.replace('[place mill]', '[place old mill]'),
     (2, "bad place id 'old mill' (a to z, 0 to 9 and _, 32 characters at most)")),
    *((f'place id {d}', PLACES_HEAD + PLACE.replace('[place mill]', f'[place {d}]'),
       (2, f"place id '{d}' is reserved (near, far and very_far are distances)")) for d in ('near', 'far', 'very_far')),
    ('place without at or area', PLACES_HEAD + '[place mill]\nlabel=Old mill\n',
     (2, "missing key 'at' or 'area' in [place mill]")),
    ('place without label', PLACES_HEAD + '[place mill]\nat=1,2,0\n', (2, "missing key 'label' in [place mill]")),
    ('place with at and area', PLACES_HEAD + PLACE + 'area=1,2,3,4,0\n', (5, "place 'mill' has both at and area")),
    ('place with area and at', PLACES_HEAD + place('town', area='1,2,3,4,0') + 'at=1,2,0\n',
     (5, "place 'town' has both at and area")),
    ('place coords with two numbers', PLACES_HEAD + PLACE.replace('10600,9300,0', '10600,9300'),
     (3, "bad place coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)")),
    ('place coords z out of range', PLACES_HEAD + PLACE.replace('10600,9300,0', '1,2,-33'),
     (3, "bad place coords '1,2,-33' (x,y,z whole numbers, z from -32 to 31)")),
    ('place coords too large', PLACES_HEAD + PLACE.replace('10600,9300,0', '1234567,2,0'),
     (3, "bad place coords '1234567,2,0' (x,y,z whole numbers, z from -32 to 31)")),
    ('zone side too long', PLACES_HEAD + place('t', area='0,0,1500,10,0'), (3, f"bad place area '0,0,1500,10,0' {BAD_AREA}")),
    ('zone height too long', PLACES_HEAD + place('t', area='10,1600,20,100,0'),
     (3, f"bad place area '10,1600,20,100,0' {BAD_AREA}")),
    ('zone with four numbers', PLACES_HEAD + place('t', area='1,2,3,4'), (3, f"bad place area '1,2,3,4' {BAD_AREA}")),
    ('zone z out of range', PLACES_HEAD + place('t', area='1,2,3,4,32'), (3, f"bad place area '1,2,3,4,32' {BAD_AREA}")),
    ('zone coords too large', PLACES_HEAD + place('t', area='1234567,2,3,4,0'),
     (3, f"bad place area '1234567,2,3,4,0' {BAD_AREA}")),
    ('label too long', PLACES_HEAD + place('a', label='é' * 24 + 'x'),
     (4, "place label of 'a' too long (48 bytes of UTF-8 at most)")),
    ('label too long in 4-byte characters', PLACES_HEAD + place('a', label='\U0001F4FB' * 12 + 'x'),
     (4, "place label of 'a' too long (48 bytes of UTF-8 at most)")),
    ('unknown place key', PLACES_HEAD + PLACE + 'colour=red\n', (5, "unknown key 'colour' in [place mill]")),
    ('duplicate place key', PLACES_HEAD + PLACE + 'at=1,2,0\n', (5, "duplicate key 'at' in [place mill] (first set on line 3)")),
    ('empty place value', PLACES_HEAD + PLACE.replace('label=Old mill', 'label='), (4, "empty value for key 'label'")),
    ('place line without equal sign', PLACES_HEAD + PLACE + 'Old mill\n', (5, 'expected key=value or [place <id>]')),
    ('duplicate place', PLACES_HEAD + PLACE + PLACE.replace('10600,9300,0', '3,4,0'),
     (5, "duplicate place 'mill' (first set on line 2)")),
    ('500 places', PLACES_HEAD + ''.join(place(f'p{i}') for i in range(500)), None),
    ('501 places', PLACES_HEAD + ''.join(place(f'p{i}') for i in range(501)), (1502, 'too many places (500 at most)')),
]

# Résumé canonique d'une fiche, identique en Python et en Lua (comparaison des deux lecteurs).
# E24-T01 : le pont garde la radio écrite (None avec frequency=) ; le serveur déduit celle d'une fréquence fixe.
# E27-T02 : [help] en dernier, « métiers/palier/délai » ou « - » sans section.
# Pas de commentaire dans LUA_CANONICAL : tests/coreai/test_kahlua.py le met sur une seule ligne.
LUA_PLACE = r'''
local function place(l)
    local where = l.area and (tostring(l.area.x1) .. "," .. tostring(l.area.y1) .. "," .. tostring(l.area.x2) .. ","
        .. tostring(l.area.y2)) or (tostring(l.x) .. "," .. tostring(l.y))
    return l.id .. "@" .. (l.area and "area " or "") .. where .. "," .. tostring(l.z) .. "@" .. l.label
end
'''
LUA_CANONICAL = LUA_PLACE + r'''
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
        join(p.marks, ";", function(l) return place(l) end), join(p.actions, ","),
        tostring(p.budget), table.concat(budgets, ","), tostring(p.call_one_in), p.call_text, p.call, p.state, p.prompt,
        join(p.shares, ","),
        p.help and (join(p.help.jobs, ",") .. "/" .. p.help.from .. "/" .. p.help.delay) or "-" }, "|")
end
'''


def place_canonical(q: store.Place) -> str:
    """Place as LUA_CANONICAL writes it: id@x,y,z@label, or id@area x1,y1,x2,y2,z@label for a zone."""
    where = f'area {",".join(str(v) for v in q.area)}' if q.area else f'{q.x},{q.y}'
    return f'{q.id}@{where},{q.z}@{q.label}'


# Résumé canonique du fichier commun des lieux (E25-T01), identique en Python et en Lua : lieux triés par identifiant.
LUA_PLACES_CANONICAL = LUA_PLACE + r'''
return function(places)
    local ids = {}
    for id in pairs(places) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = place(places[id]) end
    return table.concat(out, ";")
end
'''


def places_canonical(places: dict[str, store.Place]) -> str:
    return ';'.join(place_canonical(places[i]) for i in sorted(places))


def canonical(p: store.Persona) -> str:
    coords = ','.join(str(v) for v in p.coords) if p.coords else '-'
    return '|'.join([p.format, p.id, p.name, p.language, str(p.frequency) if p.frequency is not None else '-',
                     p.radio or '-',
                     ','.join(f'{a}-{b}' for a, b in p.listen), p.location, coords,
                     ';'.join(place_canonical(q) for q in p.marks), ','.join(p.actions),
                     str(p.budget),
                     ','.join(f'{k}={v}' for k, v in sorted(p.budgets.items())), str(p.call_one_in), p.call_text, p.call,
                     p.state, p.prompt, ','.join(p.shares),
                     f"{','.join(p.help.jobs)}/{p.help.from_}/{p.help.delay}" if p.help else '-'])


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
