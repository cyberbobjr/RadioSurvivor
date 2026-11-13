"""Doublures du banc conformes à l'API Java du jeu (E19-T01, ADR banc mimétique D01).

    python tests/test_doubles_api.py                   # contrôle, résumé chiffré
    python tests/test_doubles_api.py --write-baseline  # retire de tests/fixtures/doubles-api-baseline.txt les
                                                       # écarts résolus (la crée si absente ; n'ajoute jamais)

Relève, dans les chaînes Lua de tests/harness.py et de tous les tests/*.py, les méthodes que les doublures de classes
Java définissent, et refuse celles qui n'existent pas dans la classe Java (héritage compris, tools/pz_api.py lu sur
les sources de référence 42.22 du poste). Formes relevées (portée : un fichier Python, dans l'ordre du source) :
    local X = class('Nom'[, Parent]) / H.class('Nom') / HARNESS.class('Nom')     X lié à Nom
    local X = C.Nom / H.classes.Nom / C['Nom']        (C lié à H.classes)          X lié à Nom
    local A, B = C.Nom1, C.Nom2 ; local X = Y          (Y déjà lié)                 alias
    local o = setmetatable({...}, X) ; HARNESS.spawnZombie(...), HARNESS.players.A, getPlayer()...   instances
    function X:m(  function X.m(  X.m = function  X.m = X.autre  function C.Nom:m(  C.Nom.m = function
    Nom = { m = function ... }  function Nom.m(       (table globale ou fonction statique d'une classe exposée)
Un nom de classe terminé par « Double » ou absent des classes exposées est une aide de test : rapporté, non contrôlé.
Fonctions globales doublées par le harnais (colonne 0 de ses chaînes Lua : function nom(, nom = function, alias)
contrôlées contre les @LuaMethod globales, les fonctions du Lua vanilla et la bibliothèque de base Lua.

Liste de référence (cliquet) : tests/fixtures/doubles-api-baseline.txt, une ligne « Classe.methode » ou
« global.nom » par écart existant ; un écart nouveau fait échouer le banc, une ligne qui n'est plus un écart aussi.
Sans les sources de référence (PZ_SOURCE_DIR), le contrôle est sauté ; les tests du relevé tournent toujours.
"""
from __future__ import annotations

import ast
import re
import sys
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent
sys.path.insert(0, str(ROOT / 'tools'))
import pz_api  # noqa: E402

BASELINE = TESTS / 'fixtures' / 'doubles-api-baseline.txt'
HARNESS_FILE = TESTS / 'harness.py'
EXCLUDED = {'test_doubles_api.py', 'test_pz_api.py'}  # doublures fabriquées et extraits Java de ces bancs
HELPER_SUFFIX = 'Double'
BASELINE_HEADER = """\
# Écarts entre les doublures du banc et l'API Java 42.22 (E19-T01, tests/test_doubles_api.py).
# Une ligne par méthode de doublure absente de sa classe Java (Classe.methode) ou fonction globale doublée
# inconnue du jeu (global.nom). Cette liste ne peut que DIMINUER : un écart nouveau fait échouer le banc, une
# ligne qui n'est plus un écart aussi. Corriger la doublure (renommer, supprimer, ou suffixe Double pour une aide
# de test), puis retirer la ligne : python tests/test_doubles_api.py --write-baseline (n'ajoute jamais d'écart).
"""
# Bibliothèque de base Lua 5.1 / Kahlua (BaseLib), hors API du jeu.
LUA_BASE_FUNCTIONS = frozenset(
    'assert collectgarbage dofile error gcinfo getfenv getmetatable ipairs load loadfile loadstring module next '
    'pairs pcall print rawequal rawget rawlen rawset require select setfenv setmetatable tonumber tostring type '
    'unpack xpcall'.split())


# --- Relevé des doublures ---------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Chunk:
    """Une chaîne du source Python (code Lua embarqué), avec sa première ligne."""
    file: str
    line: int
    text: str


@dataclass(frozen=True)
class Double:
    cls: str
    method: str
    where: str
    static: bool = False  # table globale ou fonction Nom.m d'un nom jamais lié : contrôlée seulement si exposée


@dataclass(frozen=True)
class GlobalDouble:
    name: str
    where: str


@dataclass(frozen=True)
class Binding:
    kind: str       # 'class' (classe ou instance) / 'classes' (H.classes) / 'static' (table globale Nom = {...})
    name: str = ''


@dataclass
class Scan:
    methods: list[Double] = field(default_factory=list)
    dynamic: list[str] = field(default_factory=list)   # X['m' .. f] = function, class(nom_variable) : non relevés


def lua_chunks(path: Path) -> list[Chunk]:
    """Chaînes littérales du fichier Python, dans l'ordre du source."""
    source = path.read_text(encoding='utf-8')
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return [Chunk(path.name, 1, source)]
    nodes = [n for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
    nodes.sort(key=lambda n: (n.lineno, n.col_offset))
    return [Chunk(path.name, n.lineno, n.value) for n in nodes]


def strip_lua_comments(text: str) -> str:
    """Commentaires Lua blanchis (sauts de ligne gardés pour les numéros de ligne)."""
    def blank(m):
        return re.sub(r'[^\n]', ' ', m.group(0))
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', blank, text, flags=re.S)
    return re.sub(r'--[^\n]*', blank, text)


def _close(text: str, i: int) -> int:
    """Indice qui ferme le crochet ouvert en i (chaînes Lua sautées) ; len(text) si non fermé."""
    pairs = {'(': ')', '[': ']', '{': '}'}
    stack = []
    while i < len(text):
        c = text[i]
        if c in '\'"':
            j = i + 1
            while j < len(text) and text[j] not in (c, '\n'):
                j += 2 if text[j] == '\\' else 1
            i = j
        elif c in pairs:
            stack.append(pairs[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack:
                return i
        i += 1
    return len(text)


def leading_term(text: str) -> str:
    """Premier terme d'une expression Lua : "C.X or H.class('X')" -> 'C.X' ; appels et index compris."""
    i = 0
    while i < len(text):
        c = text[i]
        if c.isalnum() or c in '_.:':
            i += 1
        elif c in '([' or (c == '{' and i == 0):
            i = _close(text, i) + 1
        else:
            break
    return text[:i]


def leading_terms(text: str, count: int) -> list[str]:
    terms = []
    for _ in range(count):
        text = text.lstrip()
        term = leading_term(text)
        terms.append(term)
        text = text[len(term):].lstrip()
        if not text.startswith(','):
            break
        text = text[1:]
    return terms


def _split_args(text: str) -> list[str]:
    args, depth, start = [], 0, 0
    for i, c in enumerate(text):
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            args.append(text[start:i])
            start = i + 1
    return args + [text[start:]]


# Instances renvoyées par le harnais (factories) : terme entier -> classe Java.
INSTANCE_FACTORIES = [
    (r'(?:\w+\.)*spawnZombie\(.*\)', 'IsoZombie'),
    (r'\w+\.zombies\[.*\]', 'IsoZombie'),
    (r'\w+\.players(?:\.\w+|\[.*\])', 'IsoPlayer'),
    (r'\w+\.localPlayer', 'IsoPlayer'),
    (r'(?:\w+\.)*addPlayer\(.*\)', 'IsoPlayer'),
    (r'(?:getPlayer\(\)|getSpecificPlayer\(.*\)|getPlayerByOnlineID\(.*\))', 'IsoPlayer'),
    (r'(?:\w+\.)*square\(.*\)', 'IsoGridSquare'),
    (r'getCell\(\):(?:getGridSquare|getOrCreateGridSquare)\(.*\)', 'IsoGridSquare'),
    (r'getCell\(\)', 'IsoCell'),
    (r'getGameTime\(\)', 'GameTime'),
    (r'(?:\w+\.)*list\(.*\)', 'ArrayList'),
]

RE_EVENT = re.compile(r'''
    (?P<deffunc>\bfunction\s+(?P<fr>[A-Za-z_][\w.]*)[:.](?P<fm>[A-Za-z_]\w*)\s*\()
  | (?P<bracket>(?<![\w.:])(?P<br>[A-Za-z_][\w.]*)\[[^\]\n]+\]\s*=\s*function\b)
  | (?P<defassign>(?<![\w.:])(?P<ar>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.(?P<am>[A-Za-z_]\w*)\s*=(?!=)(?=(?P<arhs>[^\n]*)))
  | (?P<assign>(?<![\w.:])(?P<local>local\s+)?(?P<names>[A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*=(?!=)
        (?=(?P<rhs>[^\n]*)))
''', re.X)
RE_CLASS_MARKER = re.compile(r'\b(?:classes|CLASSES)\(\s*[\'"](\w+)[\'"]|\b_class\s*=\s*[\'"](\w+)[\'"]')
RE_DYNAMIC_CLASS =re.compile(r'(?<!function )(?<![\w])(?:\w+\.)?class\(\s*(?![\'")])')
RE_TABLE_FIELD = re.compile(r'(?:^|[,;])\s*(?:([A-Za-z_]\w*)|\[[^\]]*\])\s*=[ \t]*(function\b)?')


class DoubleScanner:
    """Relève les méthodes de doublures d'un fichier (liaisons de variables suivies dans l'ordre du source)."""

    def __init__(self):
        self.vars: dict[str, Binding | None] = {}
        self.defined: set[tuple[str, str]] = set()
        self.scan = Scan()

    def run(self, chunks: list[Chunk]) -> Scan:
        for chunk in chunks:
            self._chunk(chunk)
        return self.scan

    # Évaluation des termes -----------------------------------------------------------------------------------
    def evaluate(self, term: str) -> Binding | None:
        term = term.strip()
        bound = self.vars.get
        m = re.fullmatch(r'(\w+)\.classes\.(\w+)', term)
        if m:
            return Binding('class', m.group(2))
        if re.fullmatch(r'\w+\.classes', term):
            return Binding('classes')
        m = re.fullmatch(r'(\w+)\.(\w+)', term) or re.fullmatch(r'(\w+)\[\s*[\'"](\w+)[\'"]\s*\]', term)
        if m and bound(m.group(1)) == Binding('classes'):
            return Binding('class', m.group(2))
        if re.fullmatch(r'[A-Za-z_]\w*', term):
            return bound(term)
        m = re.fullmatch(r'(?:[\w.]*\.)?class\(\s*[\'"](\w+)[\'"].*\)', term, re.S)
        if m:
            return Binding('class', m.group(1))
        m = re.fullmatch(r'setmetatable\((.*)\)', term, re.S)
        if m:
            args = _split_args(m.group(1))
            return self.evaluate(leading_term(args[-1].strip())) if len(args) == 2 else None
        if term.startswith('{'):  # objet imité marqué pour instanceof : { classes = classes("IsoRadio", ...) }
            m = RE_CLASS_MARKER.search(term)
            return Binding('class', m.group(1) or m.group(2)) if m else None
        for pattern, cls in INSTANCE_FACTORIES:
            if re.fullmatch(pattern, term, re.S):
                return Binding('class', cls)
        return None

    def _class_of(self, receiver: str) -> str | None:
        b = self.evaluate(receiver)
        return b.name if b and b.kind == 'class' else None

    # Événements du source --------------------------------------------------------------------------------------
    def _chunk(self, chunk: Chunk):
        text = strip_lua_comments(chunk.text)

        def where(pos):
            return f'{chunk.file}:{chunk.line + text.count(chr(10), 0, pos)}'

        for m in RE_DYNAMIC_CLASS.finditer(text):
            self.scan.dynamic.append(where(m.start()) + ' class(<variable>)')
        for m in RE_EVENT.finditer(text):
            if m['deffunc']:
                self._define(m['fr'], m['fm'], where(m.start()))
            elif m['bracket']:
                if self._class_of(m['br']):
                    self.scan.dynamic.append(where(m.start()) + f' {m["br"]}[...] = function')
            elif m['defassign']:
                rhs = m['arhs'].strip()
                if rhs.startswith('function') or self._is_method_alias(leading_term(rhs)):
                    self._define(m['ar'], m['am'], where(m.start()))
            else:
                self._assign(m, text, where)

    def _is_method_alias(self, term: str) -> bool:
        """X.m = Y.n : alias d'une méthode Y.n déjà doublée dans ce fichier (pas une donnée p.attached = p.radio)."""
        parts = re.fullmatch(r'(.+)[.:](\w+)', term)
        return bool(parts) and (self._class_of(parts.group(1)), parts.group(2)) in self.defined

    def _define(self, receiver: str, method: str, where: str):
        if method.startswith('__'):
            return  # métaméthodes et champs du harnais (__index, __javaName)
        b = self.evaluate(receiver)
        if b and b.kind in ('class', 'static'):
            self._record(Double(b.name, method, where, static=b.kind == 'static'))
        elif re.fullmatch(r'[A-Za-z_]\w*', receiver) and receiver not in self.vars:
            self._record(Double(receiver, method, where, static=True))

    def _record(self, double: Double):
        self.defined.add((double.cls, double.method))
        self.scan.methods.append(double)

    def _assign(self, m: re.Match, text: str, where: Callable[[int], str]):
        names = [n.strip() for n in m['names'].split(',')]
        rhs = m['rhs']
        if len(names) == 1 and not m['local'] and rhs.lstrip().startswith('{'):
            self._static_table(names[0], text, m.start('rhs') + rhs.index('{'), where)
            return
        terms = leading_terms(rhs, len(names))
        for i, name in enumerate(names):
            self.vars[name] = self.evaluate(terms[i]) if i < len(terms) and terms[i] else None

    def _static_table(self, name: str, text: str, brace: int, where: Callable[[int], str]):
        """Nom = { m = function ... } : fonctions statiques doublées d'une éventuelle classe exposée Nom. Une table
        qui porte aussi des données (Server = { talk = {...}, find = function }) imite un module du mod : ignorée."""
        end = _close(text, brace)
        depth, keep = 0, []
        for c in text[brace + 1:end]:  # premier niveau de la table seulement
            if c in '([{':
                depth += 1
            elif c in ')]}':
                depth -= 1
            keep.append(c if depth == 0 and c not in ')]}' else ' ')
        fields = list(RE_TABLE_FIELD.finditer(''.join(keep)))
        if any(not f.group(1) or not f.group(2) for f in fields):
            self.vars[name] = None  # module imité, pas une classe Java
            return
        self.vars[name] = Binding('static', name)
        for f in fields:
            self._record(Double(name, f.group(1), where(brace + 1 + f.start(1)), static=True))


def scan_file(path: Path) -> Scan:
    return DoubleScanner().run(lua_chunks(path))


RE_GLOBAL_DEF = re.compile(r'^(?:function\s+([A-Za-z_]\w*)\s*\(|([A-Za-z_]\w*)\s*=\s*function\b'
                           r'|([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$)', re.M)


def scan_globals(chunks: list[Chunk]) -> list[GlobalDouble]:
    """Fonctions globales définies en colonne 0 des chaînes Lua (function nom(, nom = function, nom = autre)."""
    found: list[GlobalDouble] = []
    for chunk in chunks:
        text = strip_lua_comments(chunk.text)
        for m in RE_GLOBAL_DEF.finditer(text):
            where = f'{chunk.file}:{chunk.line + text.count(chr(10), 0, m.start())}'
            name = m.group(1) or m.group(2)
            if not name and m.group(4) in {g.name for g in found}:
                name = m.group(3)  # alias d'une doublure déjà relevée (getDebug = isDebugEnabled)
            if name:
                found.append(GlobalDouble(name, where))
    return found


def test_files() -> list[Path]:
    return sorted(p for p in TESTS.glob('*.py') if p.name not in EXCLUDED)


# --- Contrôle contre l'API --------------------------------------------------------------------------------------

@dataclass
class Report:
    checked: dict[str, set[str]] = field(default_factory=dict)       # classe -> méthodes contrôlées
    helpers: dict[str, set[str]] = field(default_factory=dict)       # aide de test -> méthodes
    gaps: dict[str, list[str]] = field(default_factory=dict)         # 'Classe.m' / 'global.nom' -> lieux
    globals_checked: set[str] = field(default_factory=set)
    dynamic: list[str] = field(default_factory=list)


def check(doubles: list[Double], globals_: list[GlobalDouble], methods_of: Callable[[str], dict | None],
          known_globals: Callable[[str], bool]) -> Report:
    report = Report()
    for d in doubles:
        table = None if d.cls.endswith(HELPER_SUFFIX) else methods_of(d.cls)
        if table is None:
            if not d.static:
                report.helpers.setdefault(d.cls, set()).add(d.method)
            continue
        report.checked.setdefault(d.cls, set()).add(d.method)
        if d.method not in table:
            report.gaps.setdefault(f'{d.cls}.{d.method}', []).append(d.where)
    for g in globals_:
        report.globals_checked.add(g.name)
        if not known_globals(g.name):
            report.gaps.setdefault(f'global.{g.name}', []).append(g.where)
    return report


def known_global(name: str) -> bool:
    return (name in LUA_BASE_FUNCTIONS or name in pz_api.global_functions()
            or name in pz_api.vanilla_lua_functions())


def run_check() -> Report:
    doubles, dynamic = [], []
    for path in test_files():
        scan = scan_file(path)
        doubles += scan.methods
        dynamic += scan.dynamic
    report = check(doubles, scan_globals(lua_chunks(HARNESS_FILE)), pz_api.class_methods, known_global)
    report.dynamic = dynamic
    return report


def read_baseline(path: Path = BASELINE) -> set[str]:
    if not path.exists():
        return set()
    return {line.strip() for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip() and not line.startswith('#')}


def write_baseline(gaps, path: Path = BASELINE):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(BASELINE_HEADER + ''.join(f'{g}\n' for g in sorted(gaps)), encoding='utf-8', newline='\n')


def compare(gaps, baseline: set[str]) -> tuple[list[str], list[str]]:
    """(écarts nouveaux, lignes de la liste qui ne sont plus des écarts)."""
    return sorted(set(gaps) - baseline), sorted(baseline - set(gaps))


def summary(report: Report, baseline: set[str]) -> str:
    methods = sum(len(m) for m in report.checked.values())
    helpers = sum(len(m) for m in report.helpers.values())
    return (f'doubles-api: {len(report.checked)} classes contrôlées, {methods} méthodes contrôlées, '
            f'{len(report.globals_checked)} fonctions globales contrôlées, {len(report.gaps)} écarts '
            f'({len(baseline)} en liste de référence), {helpers} méthodes d\'aides de test '
            f'({len(report.helpers)} classes), {len(report.dynamic)} formes dynamiques non relevées')


# --- Bancs ------------------------------------------------------------------------------------------------------

def _scan_lua(lua: str) -> Scan:
    return DoubleScanner().run([Chunk('essai.py', 1, lua)])


class ScannerTest(unittest.TestCase):
    """Relevé des formes de doublures (sans les sources du jeu)."""

    def pairs(self, lua):
        return {(d.cls, d.method, d.static) for d in _scan_lua(lua).methods}

    def test_class_forms(self):
        lua = '''
local H = HARNESS
local C = H.classes
local Item = H.class('InventoryItem')
function Item:getType() end
function Item.getName(self) end
Item.getCount = function(self) return 1 end
Item.getFullType = Item.getType
local Lit = H.class('Literature', Item)
function Lit:getPageCount() end
function C.IsoGridSquare:getX() end
C.IsoPlayer.getRole = function(self) end
function HARNESS.classes.IsoZombie:isDead() end
local Z, W = C.IsoZombie, C.HandWeapon
function Z:getOwner() end
function W:getAmmoType() end
local Bar = C.IsoBarricade or H.class('IsoBarricade', C.IsoObject)
function Bar:getHealth() end
local GRID = setmetatable({}, H.class('IsoMetaGrid'))
function GRID:getCellData() end
'''
        self.assertEqual(self.pairs(lua), {
            ('InventoryItem', 'getType', False), ('InventoryItem', 'getName', False),
            ('InventoryItem', 'getCount', False), ('InventoryItem', 'getFullType', False),
            ('Literature', 'getPageCount', False), ('IsoGridSquare', 'getX', False), ('IsoPlayer', 'getRole', False),
            ('IsoZombie', 'isDead', False), ('IsoZombie', 'getOwner', False), ('HandWeapon', 'getAmmoType', False),
            ('IsoBarricade', 'getHealth', False), ('IsoMetaGrid', 'getCellData', False)})

    def test_harness_engine_forms_and_instances(self):
        lua = '''
local IsoObject = class('IsoObject')
function IsoObject:getModData() end
IsoObject.__index = IsoObject
local p = HARNESS.players.A; function p:getUsername() end
local zb = HARNESS.spawnZombie(1, 2, 3, 0, 'server')
function zb:isDead() end
local sq = getCell():getGridSquare(1, 2, 0)
sq.getRoom = function() end
local r = { classes = classes("IsoRadio", "IsoObject"), device = newDevice() }
function r:getDeviceData() end
local it = { id = 1, _class = 'InventoryItem' }
function it:getID() end
'''
        self.assertEqual(self.pairs(lua), {('IsoObject', 'getModData', False), ('IsoPlayer', 'getUsername', False),
                                           ('IsoZombie', 'isDead', False), ('IsoGridSquare', 'getRoom', False),
                                           ('IsoRadio', 'getDeviceData', False), ('InventoryItem', 'getID', False)})

    def test_static_tables_and_static_functions(self):
        lua = '''
GameTime = {
    getInstance = function() return 1 end,
    getServerTimeMills = function()
        local t = { inner = function() end }
        return 0
    end,
}
function ZombieIdleState.instance() end
local LK = {}
function LK.helper() end
'''
        self.assertEqual(self.pairs(lua), {('GameTime', 'getInstance', True), ('GameTime', 'getServerTimeMills', True),
                                           ('ZombieIdleState', 'instance', True)})

    def test_rebinding_comments_and_data_fields(self):
        lua = '''
local C = H.classes
local Z = C.IsoZombie
-- function Z:commentee() end
Z.speed = 2
local Z = { }
function Z:plusUneClasse() end
local C = require('LK_Stock')
local X = C.decodeBytes(raw)
function X:rien() end
'''
        self.assertEqual(self.pairs(lua), set())

    def test_dynamic_forms_are_reported(self):
        scan = _scan_lua('''
local HV = H.class('HumanVisual')
HV['set' .. f] = function(self, c) end
local cls = C[name] or H.class(name, C.IsoObject)
''')
        self.assertEqual(len(scan.dynamic), 2)

    def test_globals_at_column_zero(self):
        found = scan_globals([Chunk('h.py', 10, '''
isClient = function() return false end
function getWorld() end
getDebug = isClient
next = nil
    local inner = function() end
''')])
        self.assertEqual([(g.name, g.where) for g in found],
                         [('isClient', 'h.py:11'), ('getWorld', 'h.py:12'), ('getDebug', 'h.py:13')])

    def test_ratchet_compare(self):
        new, stale = compare({'IsoZombie.a': [], 'IsoZombie.b': []}, {'IsoZombie.b', 'IsoZombie.c'})
        self.assertEqual((new, stale), (['IsoZombie.a'], ['IsoZombie.c']))

    def test_check_classifies_helpers(self):
        tables = {'IsoZombie': {'isDead': set()}}
        report = check([Double('IsoZombie', 'isDead', 'f:1'), Double('IsoZombie', 'invente', 'f:2'),
                        Double('ObjetDouble', 'x', 'f:3'), Double('Inconnue', 'y', 'f:4'),
                        Double('LK', 'z', 'f:5', static=True)],
                       [GlobalDouble('getPlayer', 'h:1'), GlobalDouble('inventee', 'h:2')],
                       tables.get, lambda n: n == 'getPlayer')
        self.assertEqual(report.gaps, {'IsoZombie.invente': ['f:2'], 'global.inventee': ['h:2']})
        self.assertEqual(report.helpers, {'ObjetDouble': {'x'}, 'Inconnue': {'y'}})


@unittest.skipUnless(pz_api.available(), 'sources de référence absentes : ' + (pz_api.missing() or ''))
class DoublesApiTest(unittest.TestCase):
    """Doublures du banc contre l'API Java 42.22 (sources de référence du poste)."""

    @classmethod
    def setUpClass(cls):
        cls.report = run_check()
        cls.baseline = read_baseline()
        print('\n' + summary(cls.report, cls.baseline), flush=True)
        print('doubles-api: aides de test (non contrôlées) : '
              + ', '.join(f'{c} ({len(m)})' for c, m in sorted(cls.report.helpers.items())), flush=True)

    def test_no_new_gap(self):
        new, _ = compare(self.report.gaps, self.baseline)
        detail = '\n'.join(f'  {g}  ({", ".join(self.report.gaps[g][:3])})' for g in new)
        self.assertFalse(new, 'méthode(s) de doublure absente(s) de l\'API Java 42.22 (corriger la doublure, ou '
                              'suffixe Double pour une aide de test) :\n' + detail)

    def test_baseline_has_no_stale_entry(self):
        _, stale = compare(self.report.gaps, self.baseline)
        self.assertFalse(stale, 'liste de référence à nettoyer (plus des écarts), lancer --write-baseline : '
                         + ', '.join(stale))

    def test_invented_method_is_reported(self):
        scan = _scan_lua('local C = HARNESS.classes\nfunction C.IsoZombie:methodeQuiNexistePas() end\n')
        report = check(scan.methods, [], pz_api.class_methods, known_global)
        self.assertEqual(list(report.gaps), ['IsoZombie.methodeQuiNexistePas'])

    def test_inherited_method_is_accepted(self):
        # getBodyDamage : déclarée par IsoGameCharacter, pas par IsoZombie (vérifié ci-dessous dans les sources).
        self.assertNotIn('getBodyDamage', pz_api.api().declared_methods('zombie.characters.IsoZombie'))
        self.assertIn('getBodyDamage', pz_api.api().declared_methods('zombie.characters.IsoGameCharacter'))
        scan = _scan_lua('local Z = HARNESS.classes.IsoZombie\nfunction Z:getBodyDamage() end\n')
        report = check(scan.methods, [], pz_api.class_methods, known_global)
        self.assertEqual(report.gaps, {})
        self.assertEqual(report.checked, {'IsoZombie': {'getBodyDamage'}})

    def test_invented_global_is_reported(self):
        found = scan_globals([Chunk('h.py', 1, 'getPlayer = function() end\nglobaleInventee = function() end\n')])
        report = check([], found, pz_api.class_methods, known_global)
        self.assertEqual(list(report.gaps), ['global.globaleInventee'])


def main(argv: list[str]) -> int:
    if '--write-baseline' in argv:
        if not pz_api.available():
            print('doubles-api: ' + pz_api.missing())
            return 2
        report = run_check()
        # Cliquet : une liste existante ne fait que perdre ses lignes résolues ; un écart nouveau n'y entre pas.
        new = compare(report.gaps, read_baseline())[0] if BASELINE.exists() else []
        kept = sorted(set(report.gaps) - set(new))
        write_baseline(kept)
        print(f'doubles-api: {len(kept)} écarts écrits dans {BASELINE.relative_to(ROOT).as_posix()}')
        print(summary(report, read_baseline()))
        if new:
            print('doubles-api: écarts nouveaux NON ajoutés (corriger la doublure) : ' + ', '.join(new))
            return 1
        return 0
    unittest.main(argv=[argv[0]] + [a for a in argv[1:]], verbosity=1)
    return 0


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.exit(main(sys.argv))
