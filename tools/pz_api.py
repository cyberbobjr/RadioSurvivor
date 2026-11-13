"""Project Zomboid API exposed to Lua, read from the 42.22 reference sources of this machine (E19-T01, ADR D01).

The reference sources (decompiled Java, vanilla Lua, indexes) are private and never enter this public repository:
this module reads them on the fly and keeps its tables in process memory only.

    PZ_SOURCE_DIR   root of the reference sources (default E:\\pz-source-42.22), holding java/ and the indexes
                    index-lua-exposed-classes.txt, index-lua-methods.txt, index-lua-events.txt,
                    index-vanilla-lua-functions.txt

    available()                  True when the sources are present (callers skip otherwise)
    class_methods('IsoZombie')   {method name: {Arity}} of the public methods, inherited ones included;
                                 None when the class is not exposed to Lua or its source is unknown
    global_functions()           names of the global @LuaMethod functions (getPlayer, sendClientCommand...)
    events()                     names of the Lua events (declared by Java or triggered by vanilla Lua)
    vanilla_lua_functions()      names of the non-local functions defined by vanilla Lua (ISTimedActionQueue.add...)

Java analysis: regular expressions over the CFR output once comments and literals are blanked, one type body at a
time (annotations, generics, modifiers, multi-line headers, varargs). Superclasses and interfaces are resolved through
nested types, imports, the package and wildcard imports; a supertype outside java/ (JDK) uses the hand-written
JDK_METHODS table. Standard library only.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import NamedTuple

DEFAULT_SOURCE_DIR = r'E:\pz-source-42.22'
EXPOSED_INDEX = 'index-lua-exposed-classes.txt'
METHODS_INDEX = 'index-lua-methods.txt'
EVENTS_INDEX = 'index-lua-events.txt'
VANILLA_INDEX = 'index-vanilla-lua-functions.txt'


class Arity(NamedTuple):
    """Parameter count of one overload; varargs: at least `params - 1` arguments."""
    params: int
    varargs: bool = False

    def accepts(self, count: int) -> bool:
        return count >= self.params - 1 if self.varargs else count == self.params


def accepts(arities, count: int) -> bool:
    """True when one overload of the set accepts `count` arguments."""
    return any(a.accepts(count) for a in arities)


def _a(*counts) -> set[Arity]:
    return {Arity(c) for c in counts}


# java.lang.Object, inherited by every class and interface.
OBJECT_METHODS = {'toString': _a(0), 'equals': _a(1), 'hashCode': _a(0), 'getClass': _a(0), 'notify': _a(0),
                  'notifyAll': _a(0), 'wait': _a(0, 1, 2)}
# java.lang.Enum, inherited by every enum.
ENUM_METHODS = {'name': _a(0), 'ordinal': _a(0), 'compareTo': _a(1), 'getDeclaringClass': _a(0),
                'values': _a(0), 'valueOf': _a(1, 2), 'describeConstable': _a(0)}

_COLLECTION = {'size': _a(0), 'isEmpty': _a(0), 'contains': _a(1), 'iterator': _a(0), 'toArray': _a(0, 1),
               'add': _a(1), 'remove': _a(1), 'containsAll': _a(1), 'addAll': _a(1), 'removeAll': _a(1),
               'retainAll': _a(1), 'clear': _a(0), 'stream': _a(0), 'forEach': _a(1), 'removeIf': _a(1)}
_LIST = {**_COLLECTION, 'get': _a(1), 'set': _a(2), 'add': _a(1, 2), 'addAll': _a(1, 2), 'indexOf': _a(1),
         'lastIndexOf': _a(1), 'subList': _a(2), 'sort': _a(1), 'listIterator': _a(0, 1), 'replaceAll': _a(1),
         'getFirst': _a(0), 'getLast': _a(0), 'removeFirst': _a(0), 'removeLast': _a(0), 'addFirst': _a(1),
         'addLast': _a(1), 'reversed': _a(0)}
_DEQUE = {'push': _a(1), 'pop': _a(0), 'peek': _a(0), 'poll': _a(0), 'offer': _a(1), 'peekFirst': _a(0),
          'peekLast': _a(0), 'pollFirst': _a(0), 'pollLast': _a(0), 'offerFirst': _a(1), 'offerLast': _a(1),
          'element': _a(0), 'descendingIterator': _a(0)}
_MAP = {'size': _a(0), 'isEmpty': _a(0), 'containsKey': _a(1), 'containsValue': _a(1), 'get': _a(1),
        'put': _a(2), 'remove': _a(1, 2), 'putAll': _a(1), 'clear': _a(0), 'keySet': _a(0), 'values': _a(0),
        'entrySet': _a(0), 'getOrDefault': _a(2), 'putIfAbsent': _a(2), 'forEach': _a(1), 'replace': _a(2, 3),
        'computeIfAbsent': _a(2), 'computeIfPresent': _a(2), 'compute': _a(2), 'merge': _a(3)}
_ITERATOR = {'hasNext': _a(0), 'next': _a(0), 'remove': _a(0), 'forEachRemaining': _a(1)}
_ENTRY = {'getKey': _a(0), 'getValue': _a(0), 'setValue': _a(1)}

# Usual JDK methods called from Lua on the JDK classes that are exposed or that game classes extend. Written by hand
# from the public JDK API (not read from the game). Keys: simple class names.
JDK_METHODS = {
    'Object': {},
    'Iterable': {'iterator': _a(0), 'forEach': _a(1)},
    'Collection': _COLLECTION,
    'AbstractCollection': _COLLECTION,
    'List': _LIST, 'AbstractList': _LIST, 'ArrayList': {**_LIST, 'ensureCapacity': _a(1), 'trimToSize': _a(0)},
    'Vector': {**_LIST, 'elementAt': _a(1), 'firstElement': _a(0), 'lastElement': _a(0), 'addElement': _a(1)},
    'Stack': {**_LIST, 'push': _a(1), 'pop': _a(0), 'peek': _a(0), 'empty': _a(0), 'search': _a(1),
              'elementAt': _a(1), 'firstElement': _a(0), 'lastElement': _a(0)},
    'LinkedList': {**_LIST, **_DEQUE},
    'Deque': {**_COLLECTION, **_DEQUE}, 'Queue': {**_COLLECTION, **_DEQUE}, 'ArrayDeque': {**_COLLECTION, **_DEQUE},
    'Set': _COLLECTION, 'AbstractSet': _COLLECTION, 'HashSet': _COLLECTION, 'LinkedHashSet': _COLLECTION,
    'TreeSet': {**_COLLECTION, 'first': _a(0), 'last': _a(0)},
    'Map': _MAP, 'AbstractMap': _MAP, 'HashMap': _MAP, 'LinkedHashMap': _MAP, 'TreeMap': _MAP, 'EnumMap': _MAP,
    'Hashtable': _MAP,
    'Entry': _ENTRY,
    'Iterator': _ITERATOR,
    'Comparable': {'compareTo': _a(1)},
    'Runnable': {'run': _a(0)},
    'Cloneable': {}, 'Serializable': {},
    'BufferedReader': {'readLine': _a(0), 'read': _a(0, 3), 'ready': _a(0), 'close': _a(0), 'skip': _a(1)},
    'BufferedWriter': {'write': _a(1, 3), 'newLine': _a(0), 'flush': _a(0), 'close': _a(0)},
    'DataInputStream': {'readInt': _a(0), 'readFloat': _a(0), 'readByte': _a(0), 'readBoolean': _a(0),
                        'readLong': _a(0), 'readShort': _a(0), 'readDouble': _a(0), 'readUTF': _a(0),
                        'close': _a(0)},
    'DataOutputStream': {'writeInt': _a(1), 'writeFloat': _a(1), 'writeByte': _a(1), 'writeBoolean': _a(1),
                         'writeLong': _a(1), 'writeShort': _a(1), 'writeDouble': _a(1), 'writeUTF': _a(1),
                         'flush': _a(0), 'close': _a(0)},
    'Locale': {'getLanguage': _a(0), 'getCountry': _a(0), 'getDisplayName': _a(0, 1)},
    'SimpleDateFormat': {'format': _a(1), 'parse': _a(1)},
    'Thread': {'run': _a(0), 'start': _a(0), 'interrupt': _a(0), 'getName': _a(0), 'isAlive': _a(0)},
}

# Public constructors of the concrete JDK classes above (Lua: ArrayList.new()).
JDK_CONSTRUCTORS = {'ArrayList': _a(0, 1), 'LinkedList': _a(0, 1), 'Vector': _a(0, 1, 2), 'Stack': _a(0),
                    'ArrayDeque': _a(0, 1), 'HashSet': _a(0, 1, 2), 'LinkedHashSet': _a(0, 1, 2), 'TreeSet': _a(0, 1),
                    'HashMap': _a(0, 1, 2), 'LinkedHashMap': _a(0, 1, 2, 3), 'TreeMap': _a(0, 1),
                    'EnumMap': _a(1), 'Hashtable': _a(0, 1, 2), 'Locale': _a(1, 2, 3),
                    'SimpleDateFormat': _a(0, 1, 2), 'Thread': _a(0, 1, 2)}

_JDK_SUPERS = {'ArrayList': ['List'], 'LinkedList': ['List'], 'Vector': ['List'], 'Stack': ['Vector'],
               'HashMap': ['Map'], 'LinkedHashMap': ['HashMap'], 'TreeMap': ['Map'], 'EnumMap': ['Map'],
               'HashSet': ['Set'], 'LinkedHashSet': ['HashSet'], 'TreeSet': ['Set'],
               'List': ['Collection'], 'Set': ['Collection'], 'Queue': ['Collection'], 'Deque': ['Queue'],
               'Collection': ['Iterable'], 'AbstractList': ['List'], 'AbstractSet': ['Set'],
               'AbstractCollection': ['Collection'], 'AbstractMap': ['Map'], 'ArrayDeque': ['Deque']}

MODIFIERS = {'public', 'protected', 'private', 'static', 'final', 'synchronized', 'abstract', 'native', 'default',
             'strictfp', 'transient', 'volatile', 'sealed', 'non-sealed'}
_NOT_A_TYPE = MODIFIERS | {'new', 'return', 'throw', 'else', 'case', 'goto', 'assert', 'package', 'import'}


# --- Java analysis ---------------------------------------------------------------------------------------------------

def blank_java(text: str) -> str:
    """Text with comments removed and string / char literals emptied, so braces and parentheses can be counted."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
            out.append(' ')
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            i = n if j < 0 else j + 3
            out.append('""')
        elif c in '"\'':
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            i = j + 1
            out.append(c + c)
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def strip_generics(text: str) -> str:
    """Remove every <...> group, innermost first (Map<String, List<X>> -> Map)."""
    previous = None
    while previous != text:
        previous, text = text, re.sub(r'<[^<>]*>', '', text)
    return text


def _matching_brace(text: str, start: int) -> int:
    """Index of the brace closing the one at `start` (len(text) when unbalanced)."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return i
    return len(text)


def _top_level(text: str, start: int, end: int) -> str:
    """Body text between start and end with every nested {...} block reduced to '{}'."""
    out, depth = [], 0
    for i in range(start, end):
        c = text[i]
        if c == '{':
            if depth == 0:
                out.append('{')
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                out.append('}')
        elif depth == 0:
            out.append(c)
    return ''.join(out)


@dataclass(frozen=True)
class Method:
    name: str
    arity: Arity
    static: bool
    public: bool


@dataclass
class TypeDecl:
    """One class, interface, enum or record of a Java file; `name` is the dotted path inside the file (Outer.Inner)."""
    name: str
    kind: str
    supers: list[str]
    methods: list[Method] = field(default_factory=list)
    start: int = 0
    end: int = 0


@dataclass
class JavaFile:
    package: str
    imports: dict[str, str]           # simple name -> full name
    wildcards: list[str]              # import a.b.* -> 'a.b'
    types: dict[str, TypeDecl]        # dotted path in the file -> declaration


RE_PACKAGE = re.compile(r'^\s*package\s+([\w.]+)\s*;', re.M)
RE_IMPORT = re.compile(r'^\s*import\s+(static\s+)?([\w.]+)(\.\*)?\s*;', re.M)
RE_TYPE = re.compile(r'(?<![.\w@])(class|interface|enum|record)\s+(\w+)')
RE_ANNOTATION = re.compile(r'@(?!interface\b)[\w.]+(?:\s*\([^()]*\))?')
RE_METHOD = re.compile(r'^((?:[\w-]+\s+)*?)([\w.$]+(?:\s*\[\s*\])*)\s+(\w+)\s*\(([^()]*)\)'
                       r'(?:\s*\[\s*\])*\s*(?:throws\s+[\w.,\s]+)?$')
RE_CONSTRUCTOR = re.compile(r'^((?:[\w-]+\s+)*?)(\w+)\s*\(([^()]*)\)\s*(?:throws\s+[\w.,\s]+)?$')


def _split_params(params: str) -> list[str]:
    return [p for p in (x.strip() for x in params.split(',')) if p]


def _arity(params: str) -> Arity:
    parts = _split_params(params)
    return Arity(len(parts), bool(parts) and '...' in parts[-1])


def parse_method(segment: str, kind: str, type_name: str = '') -> Method | None:
    """Method declared by one member header (text before its '{' or ';'), or None (field, block). A constructor of
    `type_name` is the static method `new`, as Kahlua exposes it (ArrayList.new())."""
    if '=' in re.sub(r'\([^()]*\)', '', segment):
        return None  # field initializer
    header = ' '.join(strip_generics(RE_ANNOTATION.sub(' ', segment)).split())
    m = RE_CONSTRUCTOR.match(header)
    if m and m.group(2) == type_name and all(word in MODIFIERS for word in m.group(1).split()):
        return Method('new', _arity(m.group(3)), True, 'public' in m.group(1).split())
    m = RE_METHOD.match(header)
    if not m:
        return None
    modifiers, rtype, name, params = m.group(1).split(), m.group(2), m.group(3), m.group(4)
    if any(word not in MODIFIERS for word in modifiers) or rtype in _NOT_A_TYPE or name in _NOT_A_TYPE:
        return None
    public = 'public' in modifiers or (kind == 'interface' and 'private' not in modifiers)
    return Method(name, _arity(params), 'static' in modifiers, public)


def _parse_supers(header: str) -> list[str]:
    header = strip_generics(re.sub(r'\([^()]*\)', ' ', header))  # record components
    header = re.split(r'\bpermits\b', header)[0]
    supers = []
    for keyword in ('extends', 'implements'):
        m = re.search(r'\b' + keyword + r'\b(.*?)(?=\b(?:extends|implements)\b|$)', header, re.S)
        if m:
            supers += [s.strip() for s in m.group(1).split(',') if s.strip()]
    return supers


def _record_accessors(header: str) -> list[Method]:
    m = re.match(r'\s*\(([^()]*)\)', strip_generics(header))
    if not m:
        return []
    names = [p.split()[-1] for p in _split_params(RE_ANNOTATION.sub(' ', m.group(1)))]
    return [Method(n, Arity(0), False, True) for n in names]


def parse_java(text: str) -> JavaFile:
    """Package, imports and types (with their public and non-public methods) of one Java source text."""
    code = blank_java(text)
    package = RE_PACKAGE.search(code)
    imports, wildcards = {}, []
    for m in RE_IMPORT.finditer(code):
        if m.group(1):
            continue
        if m.group(3):
            wildcards.append(m.group(2))
        else:
            imports[m.group(2).rsplit('.', 1)[-1]] = m.group(2)
    found = []
    for m in RE_TYPE.finditer(code):
        if m.group(1) == 'record' and not re.match(r'\s*(?:<[^{;]*?>)?\s*\(', code[m.end():]):
            continue  # 'record' used as an identifier
        brace = code.find('{', m.end())
        semicolon = code.find(';', code.find(')', m.end()) if m.group(1) == 'record' else m.end())
        if brace < 0 or 0 <= semicolon < brace:
            continue
        header = code[m.end():brace]
        end = _matching_brace(code, brace)
        decl = TypeDecl(m.group(2), m.group(1), _parse_supers(header), start=brace, end=end)
        if decl.kind == 'record':
            decl.methods += _record_accessors(header)
        found.append(decl)
    types = {}
    for decl in found:  # dotted path: enclosing types are those whose body contains this one
        outers = [o.name for o in found if o.start < decl.start and decl.end <= o.end and o is not decl]
        body = _top_level(code, decl.start + 1, decl.end)
        decl.methods += [meth for meth in (parse_method(seg, decl.kind, decl.name) for seg in re.split(r'[;{}]', body))
                         if meth]
        if decl.kind == 'class' and not any(meth.name == 'new' for meth in decl.methods):
            decl.methods.append(Method('new', Arity(0), True, True))  # implicit default constructor
        decl.name = '.'.join(outers + [decl.name])
        types[decl.name] = decl
    return JavaFile(package.group(1) if package else '', imports, wildcards, types)


# --- Type resolution and inheritance ---------------------------------------------------------------------------------

class TypeRef(NamedTuple):
    path: Path | None      # Java file, None for a JDK type
    name: str              # dotted path inside the file, or the JDK simple name


class JavaApi:
    """API table over one reference-source root; every file is parsed once."""

    def __init__(self, root: Path):
        self.root = Path(root)
        self.java = self.root / 'java'
        self._files: dict[Path, JavaFile] = {}
        self._methods: dict[TypeRef, dict[str, set[Arity]]] = {}
        self._exposed: dict[str, list[tuple[str, str]]] | None = None

    # Reference indexes -----------------------------------------------------------------------------------------
    def _rows(self, index: str) -> list[list[str]]:
        path = self.root / index
        return [line.split('\t') for line in path.read_text(encoding='utf-8', errors='replace').splitlines()
                if line and not line.startswith('#')]

    def exposed(self) -> dict[str, list[tuple[str, str]]]:
        """Simple name -> [(full name, decompiled file or '?')] of the classes exposed to Lua."""
        if self._exposed is None:
            self._exposed = {}
            for row in self._rows(EXPOSED_INDEX):
                if len(row) >= 3:
                    self._exposed.setdefault(row[1], []).append((row[0], row[2]))
        return self._exposed

    def global_functions(self) -> set[str]:
        return {row[0] for row in self._rows(METHODS_INDEX) if len(row) > 1 and row[1] == 'global'}

    def events(self) -> set[str]:
        return {row[0] for row in self._rows(EVENTS_INDEX) if row}

    def vanilla_lua_functions(self) -> set[str]:
        return {row[0] for row in self._rows(VANILLA_INDEX) if row}

    # Files -------------------------------------------------------------------------------------------------------
    def _file(self, path: Path) -> JavaFile:
        if path not in self._files:
            self._files[path] = parse_java(path.read_text(encoding='utf-8', errors='replace'))
        return self._files[path]

    def locate(self, full: str) -> TypeRef | None:
        """Java file and nested path of a full class name (zombie.iso.RoomDef.RoomRect), searching the package
        folder when the outer class is not where its name says (zombie.Lua.GlobalObject -> LuaManager.java)."""
        parts = full.split('.')
        for cut in range(len(parts), 0, -1):
            path = self.java.joinpath(*parts[:cut - 1], parts[cut - 1] + '.java')
            if path.is_file():
                nested = '.'.join(parts[cut - 1:])
                if nested in self._file(path).types:
                    return TypeRef(path, nested)
        for cut in range(len(parts) - 1, 0, -1):
            folder = self.java.joinpath(*parts[:cut])
            if not folder.is_dir():
                continue
            suffix = '.'.join(parts[cut:])
            for path in sorted(folder.glob('*.java')):
                names = self._file(path).types
                hit = next((n for n in names if n == suffix or n.endswith('.' + suffix)), None)
                if hit:
                    return TypeRef(path, hit)
        return None

    def resolve(self, ref: str, context: TypeRef) -> TypeRef | None:
        """Type named `ref` in an extends / implements clause of `context`; None when unknown."""
        ref = strip_generics(ref).strip()
        jfile = self._file(context.path)
        head, _, tail = ref.partition('.')
        scope = context.name.split('.')
        for depth in range(len(scope), -1, -1):  # nested types, innermost scope first
            candidate = '.'.join(scope[:depth] + [ref])
            if candidate in jfile.types:
                return TypeRef(context.path, candidate)
        if ref[0].islower() and '.' in ref:
            return self.locate(ref)
        bases = []
        if head in jfile.imports:
            bases.append(jfile.imports[head])
        bases.append((jfile.package + '.' if jfile.package else '') + head)
        bases += [w + '.' + head for w in jfile.wildcards]
        for base in bases:
            found = self.locate(base + ('.' + tail if tail else ''))
            if found:
                return found
        simple = ref.rsplit('.', 1)[-1]
        return TypeRef(None, simple) if simple in JDK_METHODS else None

    # Methods -------------------------------------------------------------------------------------------------------
    def type_methods(self, ref: TypeRef, inherited_only: bool = False) -> dict[str, set[Arity]]:
        """Public methods of a type, inherited ones included; with inherited_only, what a subtype inherits
        (constructors `new` and static interface methods are not inherited)."""
        if ref not in self._methods:
            self._methods[ref] = {}  # cycle guard
            self._methods[ref] = self._collect(ref)
        methods = self._methods[ref]
        if not inherited_only:
            return methods
        dropped = {'new'}
        if ref.path is not None:
            decl = self._file(ref.path).types[ref.name]
            if decl.kind == 'interface':
                dropped |= {m.name for m in decl.methods if m.static and m.public}
        return {k: v for k, v in methods.items() if k not in dropped}

    def _collect(self, ref: TypeRef) -> dict[str, set[Arity]]:
        out: dict[str, set[Arity]] = {}

        def merge(table):
            for name, arities in table.items():
                out.setdefault(name, set()).update(arities)

        merge(OBJECT_METHODS)
        if ref.path is None:  # JDK type
            merge(JDK_METHODS.get(ref.name, {}))
            for parent in _JDK_SUPERS.get(ref.name, []):
                merge(self.type_methods(TypeRef(None, parent), inherited_only=True))
            if ref.name in JDK_CONSTRUCTORS:
                merge({'new': JDK_CONSTRUCTORS[ref.name]})
            return out
        decl = self._file(ref.path).types[ref.name]
        if decl.kind == 'enum':
            merge(ENUM_METHODS)
        for parent in decl.supers:
            found = self.resolve(parent, ref)
            if found:
                merge(self.type_methods(found, inherited_only=True))
        for meth in decl.methods:
            if meth.public:
                out.setdefault(meth.name, set()).add(meth.arity)
        return out

    def declared_methods(self, full: str) -> set[str] | None:
        """Names of the public methods declared by the class itself (no inheritance); None when not found."""
        ref = self.locate(full)
        if ref is None:
            return None
        return {m.name for m in self._file(ref.path).types[ref.name].methods if m.public}

    def class_ref(self, simple: str) -> list[TypeRef]:
        """Source of an exposed class: top-level classes of that name first; JDK table for an external class."""
        rows = self.exposed().get(simple, [])
        if not rows:
            return []
        top = [r for r in rows if r[1] != '?' and Path(r[1]).stem == simple] or rows
        refs = []
        for full, _file in top:
            found = self.locate(full)
            if found:
                refs.append(found)
            elif simple in JDK_METHODS:
                refs.append(TypeRef(None, simple))
        return refs

    def class_methods(self, simple: str) -> dict[str, set[Arity]] | None:
        """Method name -> arities of an exposed class (union over same-named classes); None when not checkable."""
        refs = self.class_ref(simple)
        if not refs:
            return None
        out: dict[str, set[Arity]] = {}
        for ref in refs:
            for name, arities in self.type_methods(ref).items():
                out.setdefault(name, set()).update(arities)
        return out


# --- Module interface (one table per process) ------------------------------------------------------------------------

def source_dir() -> Path:
    return Path(os.environ.get('PZ_SOURCE_DIR') or DEFAULT_SOURCE_DIR)


def missing() -> str | None:
    """What is missing for the API table, or None when everything is there."""
    root = source_dir()
    for needed in ('java', EXPOSED_INDEX, METHODS_INDEX, EVENTS_INDEX, VANILLA_INDEX):
        if not (root / needed).exists():
            return f'{needed} not found in the reference sources {root} (set PZ_SOURCE_DIR)'
    return None


def available() -> bool:
    return missing() is None


@lru_cache(maxsize=None)
def _api(root: str) -> JavaApi:
    return JavaApi(Path(root))


def api() -> JavaApi:
    return _api(str(source_dir()))


@lru_cache(maxsize=None)
def class_methods(simple_name: str) -> dict[str, set[Arity]] | None:
    return api().class_methods(simple_name)


@lru_cache(maxsize=None)
def global_functions() -> frozenset[str]:
    return frozenset(api().global_functions())


@lru_cache(maxsize=None)
def events() -> frozenset[str]:
    return frozenset(api().events())


@lru_cache(maxsize=None)
def vanilla_lua_functions() -> frozenset[str]:
    return frozenset(api().vanilla_lua_functions())


if __name__ == '__main__':
    import sys
    if not available():
        print('pz_api: ' + missing())
        sys.exit(2)
    for name in sys.argv[1:] or ['IsoZombie']:
        table = class_methods(name)
        print(f'{name}: {"not exposed" if table is None else f"{len(table)} public methods"}')
