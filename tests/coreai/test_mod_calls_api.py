"""Appels du Lua des mods conformes à l'API 42.22 (E19-T02, ADR banc mimétique D02).

    python tests/coreai/test_mod_calls_api.py                   # contrôle, résumé chiffré
    python tests/coreai/test_mod_calls_api.py --write-baseline  # retire de tests/commun/fixtures/mod-calls-api-baseline.txt les
                                                         # écarts résolus (la crée si absente ; n'ajoute jamais)

Fichiers contrôlés : les .lua de Contents/mods/*/42.21/media/lua, Contents/mods/*/common et
dev/batman_*Tests. Analyse lexicale Lua d'abord (tools/pz_api.lua_tokens : commentaires, chaînes,
crochets longs, échappements), puis :
    appel de méthode  expr:nom(  expr:nom"..."  expr:nom{  -> nom connu de l'union : méthodes publiques de toutes les
        classes exposées (héritage compris), fonctions du Lua vanilla (dernier segment), méthodes de valeurs de la
        bibliothèque Kahlua (string, coroutine : lues dans les sources Kahlua et stdlib.lua), méthodes définies par
        les mods (function X:nom, function X.nom, X.nom = ..., champ nom = function d'une table littérale) ;
    appel global  nom(  (ni champ a.nom, ni méthode, ni mot-clé, ni nom local du fichier : local, paramètre, variable
        de boucle, approximation par fichier) -> nom connu des @LuaMethod globales, des fonctions globales du Lua
        vanilla, de la bibliothèque de base Kahlua réellement présente (next en est absent) ou des globales des mods.
Limite : un contrôle par union ignore le type du receveur ; un nom valable sur une autre classe passe.

Liste de référence (cliquet) : tests/commun/fixtures/mod-calls-api-baseline.txt, une ligne « chemin::genre::nom » par écart
examiné ; un écart nouveau fait échouer le banc, une ligne qui n'est plus un écart aussi. Sans les sources de
référence (PZ_SOURCE_DIR) ni stdlib.lua du jeu, le contrôle est sauté ; les tests de l'analyse tournent toujours.
"""
from __future__ import annotations

import sys
import unittest
from dataclasses import dataclass, field
from pathlib import Path

TESTS = Path(__file__).resolve().parents[1]   # tests/ (E26)
ROOT = TESTS.parent
sys.path.insert(0, str(ROOT / 'tools'))
import pz_api  # noqa: E402
from pz_api import LuaToken, lua_function_header, lua_tokens  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from test_doubles_api import compare, read_baseline  # noqa: E402  (cliquet commun aux bancs d'API)

BASELINE = TESTS / 'commun' / 'fixtures' / 'mod-calls-api-baseline.txt'
SOURCE_GLOBS = ('Contents/mods/*/42.21/media/lua/**/*.lua', 'Contents/mods/*/common/**/*.lua',
                'dev/batman_*Tests/**/*.lua')   # E21-T07: the three test mods
METHOD, GLOBAL = 'méthode', 'globale'
CALL_OPENERS = ('(', '{')
BLOCK_OPENERS = ('function', 'if', 'do', 'repeat')
BLOCK_CLOSERS = ('end', 'until')
BASELINE_HEADER = """\
# Appels du Lua des mods inconnus de l'API 42.22 (E19-T02, tests/coreai/test_mod_calls_api.py).
# Une ligne « chemin::genre::nom » par écart examiné (genre : méthode ou globale). Cette liste ne peut que DIMINUER :
# un écart nouveau fait échouer le banc, une ligne qui n'est plus un écart aussi. Corriger l'appel, puis retirer la
# ligne : python tests/coreai/test_mod_calls_api.py --write-baseline (n'ajoute jamais d'écart).
"""


# --- Relevé d'un fichier Lua ------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Call:
    name: str
    line: int


@dataclass
class FileScan:
    method_calls: list[Call] = field(default_factory=list)
    global_calls: list[Call] = field(default_factory=list)   # noms locaux du fichier déjà écartés
    locals: set[str] = field(default_factory=set)
    defined_globals: set[str] = field(default_factory=set)
    defined_methods: set[str] = field(default_factory=set)


def _text(tokens: list[LuaToken], i: int) -> str:
    return tokens[i].text if 0 <= i < len(tokens) else ''


def _is_call_open(tokens: list[LuaToken], i: int) -> bool:
    """Le jeton i ouvre les arguments d'un appel : (, { ou une chaîne."""
    return 0 <= i < len(tokens) and (tokens[i].text in CALL_OPENERS or tokens[i].kind == 'string')


def _string_key(token: LuaToken) -> str | None:
    """Clé identifiant d'une chaîne courte ("nom" -> nom), None sinon."""
    value = token.text[1:-1] if token.text[:1] in '\'"' and len(token.text) >= 2 else ''
    return value if value.isidentifier() else None


def _parameters(tokens: list[LuaToken], paren: int) -> set[str]:
    names, j = set(), paren + 1
    while j < len(tokens) and tokens[j].text != ')':
        if tokens[j].kind == 'name':
            names.add(tokens[j].text)
        j += 1
    return names


def declared_locals(tokens: list[LuaToken]) -> set[str]:
    """Noms locaux du fichier : local a, b / local function f / paramètres (self des méthodes) / variables de for."""
    names: set[str] = set()
    for i, tok in enumerate(tokens):
        if tok.text == 'local':
            j = i + 1 + (_text(tokens, i + 1) == 'function')
            while j < len(tokens) and tokens[j].kind == 'name':
                names.add(tokens[j].text)
                if _text(tokens, j + 1) != ',':
                    break
                j += 2
        elif tok.text == 'function':
            parts, sep, paren = lua_function_header(tokens, i)
            names |= _parameters(tokens, paren) | ({'self'} if sep == ':' else set())
        elif tok.text == 'for':
            j = i + 1
            while j < len(tokens) and tokens[j].kind == 'name':
                names.add(tokens[j].text)
                if _text(tokens, j + 1) != ',':
                    break
                j += 2
    return names


def _assigned_names(tokens: list[LuaToken], eq: int) -> list[str]:
    """Noms nus de la liste a, b = ... qui finit avant eq ([] si la cible est un champ, un index ou un local)."""
    names, j = [], eq - 1
    while j >= 0 and tokens[j].kind == 'name':
        if _text(tokens, j - 1) in ('.', ':'):
            return []
        names.append(tokens[j].text)
        if _text(tokens, j - 1) != ',':
            break
        j -= 2
    return [] if _text(tokens, j - 1) == 'local' else names


def _field_target(tokens: list[LuaToken], eq: int) -> str | None:
    """Champ affecté avant eq : x.nom = / x["nom"] = / nom = (dans une table) ; None sinon."""
    before = tokens[eq - 1] if eq else None
    if before is None:
        return None
    if before.kind == 'name':
        return before.text
    if before.text == ']' and eq >= 3 and tokens[eq - 2].kind == 'string' and tokens[eq - 3].text == '[':
        return _string_key(tokens[eq - 2])
    return None


def _holds_function(tokens: list[LuaToken], value: int) -> bool:
    """La valeur affectée peut être une fonction : function ... ou un nom (alias M.f = f, X.m = Y.n)."""
    return value < len(tokens) and (tokens[value].text == 'function' or tokens[value].kind == 'name')


def defined_names(tokens: list[LuaToken]) -> tuple[set[str], set[str]]:
    """(globales affectées ou définies, méthodes et champs-fonctions définis) ; contexte suivi par une pile de blocs
    et de crochets pour distinguer une instruction d'un champ de table littérale."""
    globals_, methods, stack = set(), set(), []
    for i, tok in enumerate(tokens):
        text = tok.text
        if tok.kind == 'keyword' and text in BLOCK_OPENERS:
            stack.append(text)
            if text == 'function' and _text(tokens, i - 1) != 'local':
                parts = lua_function_header(tokens, i)[0]
                if len(parts) == 1:
                    globals_.add(parts[0])
                elif parts:
                    methods.add(parts[-1])
        elif tok.kind == 'keyword' and text in BLOCK_CLOSERS:
            if stack:
                stack.pop()
        elif tok.kind == 'op' and text in '([{':
            stack.append(text)
        elif tok.kind == 'op' and text in ')]}':
            if stack:
                stack.pop()
        elif text == '=' and tok.kind == 'op':
            in_table = bool(stack) and stack[-1] == '{'
            target = _field_target(tokens, i)
            is_field = in_table or _text(tokens, i - 2) == '.' or _text(tokens, i - 1) == ']'
            if is_field and target and _holds_function(tokens, i + 1):
                methods.add(target)
            elif not in_table and not (stack and stack[-1] in '(['):
                globals_.update(_assigned_names(tokens, i))
    return globals_, methods


def calls(tokens: list[LuaToken]) -> tuple[list[Call], list[Call]]:
    """(appels de méthode expr:nom(..., appels de nom nu nom(...) hors définitions de fonction)."""
    methods, plain = [], []
    for i, tok in enumerate(tokens):
        if tok.kind != 'name' or not _is_call_open(tokens, i + 1):
            continue
        before = _text(tokens, i - 1)
        if before == ':':
            if not _in_function_header(tokens, i):
                methods.append(Call(tok.text, tok.line))
        elif before not in ('.', 'function'):
            plain.append(Call(tok.text, tok.line))
    return methods, plain


def _in_function_header(tokens: list[LuaToken], i: int) -> bool:
    """Le nom en i termine l'en-tête function a.b:c( (chaîne de noms remontant jusqu'au mot-clé function)."""
    j = i - 1
    while j >= 1 and tokens[j].text in ('.', ':') and tokens[j - 1].kind == 'name':
        j -= 2
    return _text(tokens, j) == 'function'


def scan_lua(text: str) -> FileScan:
    tokens = lua_tokens(text)
    local_names = declared_locals(tokens)
    globals_, methods = defined_names(tokens)
    method_calls, plain = calls(tokens)
    return FileScan(method_calls, [c for c in plain if c.name not in local_names], local_names,
                    globals_ - local_names, methods)


def mod_lua_files(root: Path = ROOT) -> list[Path]:
    return sorted({p for pattern in SOURCE_GLOBS for p in root.glob(pattern)})


# --- Contrôle -----------------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Known:
    methods: frozenset[str]
    globals: frozenset[str]


@dataclass(frozen=True)
class Gap:
    path: str
    line: int
    name: str
    kind: str

    @property
    def key(self) -> str:
        return f'{self.path}::{self.kind}::{self.name}'

    def __str__(self) -> str:
        return f'{self.path}:{self.line}  {self.name}  ({self.kind})'


@dataclass
class Report:
    files: int = 0
    method_calls: int = 0
    global_calls: int = 0
    gaps: list[Gap] = field(default_factory=list)

    def gap_keys(self) -> dict[str, list[Gap]]:
        keys: dict[str, list[Gap]] = {}
        for gap in self.gaps:
            keys.setdefault(gap.key, []).append(gap)
        return keys


def game_knowledge() -> Known:
    """Noms connus du jeu 42.22 (sources de référence et stdlib.lua)."""
    library = pz_api.lua_library()
    return Known(pz_api.exposed_method_names() | pz_api.vanilla_lua_methods() | library.value_methods,
                 pz_api.global_functions() | pz_api.vanilla_lua_globals() | library.globals)


def with_mod_definitions(known: Known, scans) -> Known:
    """Ajoute les méthodes et globales définies par les fichiers relevés (mis en commun : les mods se requièrent)."""
    methods, globals_ = set(known.methods), set(known.globals)
    for scan in scans:
        methods |= scan.defined_methods
        globals_ |= scan.defined_globals
    return Known(frozenset(methods), frozenset(globals_))


def check(scans: dict[str, FileScan], known: Known) -> Report:
    report = Report(files=len(scans))
    for path, scan in scans.items():
        report.method_calls += len(scan.method_calls)
        report.global_calls += len(scan.global_calls)
        report.gaps += [Gap(path, c.line, c.name, METHOD) for c in scan.method_calls if c.name not in known.methods]
        report.gaps += [Gap(path, c.line, c.name, GLOBAL) for c in scan.global_calls if c.name not in known.globals]
    return report


def scan_files(paths: list[Path], root: Path = ROOT) -> dict[str, FileScan]:
    return {p.relative_to(root).as_posix(): scan_lua(p.read_text(encoding='utf-8', errors='replace')) for p in paths}


def check_snippet(lua: str, game: Known) -> Report:
    """Contrôle d'un extrait Lua seul (ses propres définitions comprises), pour les tests du contrôle."""
    scans = {'essai.lua': scan_lua(lua)}
    return check(scans, with_mod_definitions(game, scans.values()))


def run_check() -> Report:
    scans = scan_files(mod_lua_files())
    return check(scans, with_mod_definitions(game_knowledge(), scans.values()))


def write_baseline(keys, path: Path = BASELINE):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(BASELINE_HEADER + ''.join(f'{k}\n' for k in sorted(keys)), encoding='utf-8', newline='\n')


def summary(report: Report, baseline: set[str]) -> str:
    return (f'mod-calls-api: {report.files} fichiers, {report.method_calls} appels de méthode contrôlés, '
            f'{report.global_calls} appels globaux contrôlés, {len(report.gaps)} écarts '
            f'({len(report.gap_keys())} clés), {len(baseline)} écarts en liste de référence')


def skip_reason() -> str | None:
    return pz_api.lua_library_missing()


# --- Bancs ------------------------------------------------------------------------------------------------------

class LexerTest(unittest.TestCase):
    """Analyse lexicale Lua (sans les sources du jeu)."""

    def test_comments_and_strings_hide_calls(self):
        lua = ('-- a:commentee()\n--[==[ b:longue() ]] c:encore() ]==]\nlocal s = "d:chaine(\\"x\\")" .. \'e:f()\'\n'
               'local l = [[ g:longue() ]] .. [=[ h:x() ]] ]=]\nreel:appel()\n')
        scan = scan_lua(lua)
        self.assertEqual([(c.name, c.line) for c in scan.method_calls], [('appel', 5)])
        self.assertEqual(scan.global_calls, [])

    def test_tokens_keep_lines_and_columns(self):
        toks = lua_tokens('x = 1\n  --[[\n]] y:z"s"\n')
        self.assertEqual([(t.kind, t.text, t.line, t.col) for t in toks],
                         [('name', 'x', 1, 0), ('op', '=', 1, 2), ('number', '1', 1, 4), ('name', 'y', 3, 3),
                          ('op', ':', 3, 4), ('name', 'z', 3, 5), ('string', '"s"', 3, 6)])

    def test_numbers_and_concat(self):
        self.assertEqual([t.text for t in lua_tokens('a=1 .. 2 b=0x1F c=1.5e-3 d=...')],
                         ['a', '=', '1', '..', '2', 'b', '=', '0x1F', 'c', '=', '1.5e-3', 'd', '=', '...'])


class ScanTest(unittest.TestCase):
    """Relevé des appels, des noms locaux et des définitions (sans les sources du jeu)."""

    LUA = '''
local M = {}
local helper = function(a, b) return a end
function M.util(x) return helper(x) end
function M:obj(y) self:obj2(y) end
M.alias = M.util
M["quoted"] = function() end
local T = { champ = function() end, data = 1, [ "cle" ] = function() end }
Globale = {}
function definieGlobale() end
autre, encore = 1, 2
for i, v in ipairs(t) do print(i, v) end
x:methode(1):suite{1}
require "Foo"
Events.OnTick.Add(fn)
function rien() local interne = 1; interne = 2 end
'''

    def setUp(self):
        self.scan = scan_lua(self.LUA)

    def test_calls(self):
        self.assertEqual([c.name for c in self.scan.method_calls], ['obj2', 'methode', 'suite'])
        self.assertEqual([c.name for c in self.scan.global_calls], ['ipairs', 'print', 'require'])

    def test_locals(self):
        self.assertTrue({'M', 'helper', 'a', 'b', 'x', 'y', 'self', 'T', 'i', 'v', 'interne'} <= self.scan.locals)

    def test_definitions(self):
        self.assertEqual(self.scan.defined_methods, {'util', 'obj', 'alias', 'quoted', 'champ', 'cle'})
        self.assertEqual(self.scan.defined_globals, {'Globale', 'definieGlobale', 'autre', 'encore', 'rien'})

    def test_table_fields_inside_nested_function_are_statements(self):
        scan = scan_lua('local t = { f = function() g = 1 end, h = 2 }\n')
        self.assertEqual((scan.defined_methods, scan.defined_globals), ({'f'}, {'g'}))

    def test_ratchet_keys(self):
        gap = Gap('Contents/x.lua', 12, 'Is', METHOD)
        self.assertEqual((gap.key, str(gap)), ('Contents/x.lua::méthode::Is', 'Contents/x.lua:12  Is  (méthode)'))


@unittest.skipIf(skip_reason(), 'sources de référence absentes : ' + (skip_reason() or ''))
class ModCallsApiTest(unittest.TestCase):
    """Lua des mods contre l'API 42.22 (sources de référence du poste et stdlib.lua du jeu)."""

    @classmethod
    def setUpClass(cls):
        cls.game = game_knowledge()
        cls.report = run_check()
        cls.baseline = read_baseline(BASELINE)
        print('\n' + summary(cls.report, cls.baseline), flush=True)

    def gaps(self, lua: str) -> list[tuple[str, str]]:
        return [(g.name, g.kind) for g in check_snippet(lua, self.game).gaps]

    def test_no_new_gap(self):
        keys = self.report.gap_keys()
        new, _ = compare(keys, self.baseline)
        detail = '\n'.join(f'  {gap}' for key in new for gap in keys[key][:3])
        self.assertFalse(new, 'appel(s) inconnu(s) de l\'API 42.22 (corriger l\'appel) :\n' + detail)

    def test_baseline_has_no_stale_entry(self):
        _, stale = compare(self.report.gap_keys(), self.baseline)
        self.assertFalse(stale, 'liste de référence à nettoyer (plus des écarts), lancer --write-baseline : '
                         + ', '.join(stale))

    def test_removed_method_is_reported(self):
        # IsoGameCharacter:dropHeldItems retirée en 42.22 (api-diff) : plus aucune classe exposée ne la porte.
        self.assertNotIn('dropHeldItems', pz_api.exposed_method_names())
        self.assertIn('dropHeldItemsServer', pz_api.class_methods('IsoGameCharacter'))
        self.assertEqual(self.gaps('obj:dropHeldItems(1, 2, 3, true, false)\n'), [('dropHeldItems', METHOD)])

    def test_square_is_is_reported_since_no_class_has_it(self):
        # IsoGridSquare:Is remplacée par has : le nom Is n'existe sur aucune classe exposée ni dans le Lua vanilla,
        # l'union le refuse donc. Un nom retiré d'une classe mais présent sur une autre passerait (limite connue).
        self.assertIn('has', pz_api.class_methods('IsoGridSquare'))
        self.assertNotIn('Is', pz_api.exposed_method_names() | pz_api.vanilla_lua_methods())
        self.assertEqual(self.gaps('local sq = getCell():getGridSquare(1, 2, 0)\nif sq:Is(x) then end\n'),
                         [('Is', METHOD)])

    def test_calls_in_comments_and_strings_are_ignored(self):
        self.assertEqual(self.gaps('-- obj:dropHeldItems()\nlocal s = "next(t)" .. [[ sq:Is(x) ]]\n'), [])

    def test_next_is_absent_from_kahlua(self):
        self.assertNotIn('next', pz_api.lua_library().globals)
        self.assertEqual(self.gaps('local t = {}\nif next(t) == nil then print(1) end\n'), [('next', GLOBAL)])

    def test_string_methods_follow_kahlua(self):
        self.assertEqual(self.gaps('local s = ("a"):rep(2):len()\nlocal u = s:gmatch("x")\n'), [])
        # string.gfind (Lua 5.0) absente de Kahlua et de toute classe ; string.dump, absente aussi de Kahlua, passe
        # pourtant : le Lua vanilla définit une fonction de ce nom (limite de l'union).
        self.assertNotIn('gfind', pz_api.lua_library().value_methods)
        self.assertEqual(self.gaps('local s = ("a"):gfind("x")\n'), [('gfind', METHOD)])

    def test_method_defined_by_the_mod_is_accepted(self):
        lua = 'local Radio = {}\nfunction Radio:syntoniserFrequence(f) end\nRadio:syntoniserFrequence(91)\n'
        self.assertEqual(self.gaps(lua), [])
        self.assertEqual(self.gaps('Radio:syntoniserFrequence(91)\n'), [('syntoniserFrequence', METHOD)])


def main(argv: list[str]) -> int:
    if '--write-baseline' in argv:
        if skip_reason():
            print('mod-calls-api: ' + skip_reason())
            return 2
        report = run_check()
        keys = report.gap_keys()
        # Cliquet : une liste existante ne fait que perdre ses lignes résolues ; un écart nouveau n'y entre pas.
        new = compare(keys, read_baseline(BASELINE))[0] if BASELINE.exists() else []
        kept = sorted(set(keys) - set(new))
        write_baseline(kept)
        print(f'mod-calls-api: {len(kept)} écarts écrits dans {BASELINE.relative_to(ROOT).as_posix()}')
        print(summary(report, read_baseline(BASELINE)))
        for key in new:
            print('mod-calls-api: écart nouveau NON ajouté : ' + ', '.join(str(g) for g in keys[key][:3]))
        return 1 if new else 0
    unittest.main(argv=[argv[0]] + argv[1:], verbosity=1)
    return 0


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.exit(main(sys.argv))
