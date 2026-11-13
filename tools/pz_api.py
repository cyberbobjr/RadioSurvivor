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
    vanilla_lua_globals()        their global names (no '.' or ':'), vanilla_lua_methods() their last segments
    exposed_method_names()       union of the public method names of every exposed class (E19-T02)
    lua_library()                Kahlua base library really present: global functions and methods callable with ':'
                                 on a value (string, coroutine...), read from the Kahlua sources and the game's
                                 stdlib.lua (reference sources first, then the game folder of tools/pz_paths.py)
    lua_tokens(text)             Lua lexer (comments dropped, strings kept as one token); lua_function_header()

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
LUA_MANAGER = 'zombie.Lua.LuaManager'                             # its Exposer delegates part of setExposed
RE_CLASS_EXPOSE = re.compile(r'\.setExposed\(\s*([A-Z][\w.]*)\.class\s*\)')
RE_DELEGATED_EXPOSE = re.compile(r'\b([A-Z][\w.]*)\.setExposed\(\s*\w+\s*\)')
KAHLUA_PLATFORM ='java/se/krka/kahlua/j2se/J2SEPlatform.java'   # setupEnvironment: libraries of every Lua state
STDLIB_LUA = 'stdlib.lua'                                         # loaded by setupEnvironment from the game folder


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

# Line comment (dropped), block comment (one space), text block and string / char literal (emptied; an unterminated
# literal stops at the end of its line, which it swallows).
RE_JAVA_BLANKED = re.compile(r'//[^\n]*|/\*[\s\S]*?(?:\*/|\Z)|"""[\s\S]*?(?:"""|\Z)'
                             r'|(["\'])(?:\\[\s\S]|(?!\1)[^\\\n])*(?:\1|\n)?')


def _blanked(m: re.Match) -> str:
    token = m.group(0)
    if token.startswith('//'):
        return ''
    if token.startswith('/*'):
        return ' '
    if token.startswith('"""'):
        return '""'
    return m.group(1) * 2


def blank_java(text: str) -> str:
    """Text with comments removed and string / char literals emptied, so braces and parentheses can be counted."""
    return RE_JAVA_BLANKED.sub(_blanked, text)


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
        """Simple name -> [(full name, decompiled file or '?')] of the classes exposed to Lua: the index, plus the
        classes exposed through a delegated setExposed(exposer) that the index misses (UIWorldMap and its family)."""
        if self._exposed is None:
            self._exposed = {}
            rows = [(row[0], row[1], row[2]) for row in self._rows(EXPOSED_INDEX) if len(row) >= 3]
            known = {full for full, _, _ in rows}
            rows += [row for row in self.delegated_exposed() if row[0] not in known]
            for full, simple, path in rows:
                self._exposed.setdefault(simple, []).append((full, path))
        return self._exposed

    def delegated_exposed(self) -> list[tuple[str, str, str]]:
        """(full name, simple name, decompiled file) of the classes exposed by the static setExposed(exposer) methods
        that LuaManager's Exposer calls (X.setExposed(this)), followed recursively."""
        start = self.locate(LUA_MANAGER)
        if start is None:
            return []
        found, seen, todo = [], {start}, [start]
        while todo:
            ref = todo.pop()
            code = blank_java(ref.path.read_text(encoding='utf-8', errors='replace'))
            for name in RE_CLASS_EXPOSE.findall(code) if ref != start else ():  # LuaManager's own: the index
                target = self.resolve(name, ref)
                if target is not None and target.path is not None:
                    found.append(self._row(target))
            for name in RE_DELEGATED_EXPOSE.findall(code):
                target = self.resolve(name, ref)
                if target is not None and target.path is not None and target not in seen:
                    seen.add(target)
                    todo.append(target)
        return sorted(set(found))

    def _row(self, ref: TypeRef) -> tuple[str, str, str]:
        package = self._file(ref.path).package
        full = (package + '.' if package else '') + ref.name
        return full, ref.name.rsplit('.', 1)[-1], ref.path.relative_to(self.root).as_posix()

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

    def exposed_method_names(self) -> set[str]:
        """Union of the public method names of every exposed class (inherited ones included)."""
        names: set[str] = set()
        for simple in self.exposed():
            names.update(self.class_methods(simple) or ())
        return names

    # Kahlua base library -------------------------------------------------------------------------------------------
    def kahlua_java_library(self) -> KahluaLib:
        """Library the Kahlua platform registers in every Lua state (J2SEPlatform.setupEnvironment), from Java."""
        platform = self.root / KAHLUA_PLATFORM
        imports = self._file(platform).imports
        found = KahluaLib()
        for simple in platform_libraries(platform.read_text(encoding='utf-8', errors='replace')):
            ref = self.locate(imports.get(simple, simple))
            if ref is not None:
                found = found.merge(parse_kahlua_lib(ref.path.read_text(encoding='utf-8', errors='replace')))
        return found


# --- Lua lexer -------------------------------------------------------------------------------------------------------

LUA_KEYWORDS = frozenset('and break do else elseif end false for function if in local nil not or repeat return then '
                         'true until while'.split())


class LuaToken(NamedTuple):
    kind: str     # 'name', 'keyword', 'string', 'number', 'op'
    text: str     # a string token keeps its quotes or long brackets
    line: int     # 1-based
    col: int      # 0-based


RE_LUA_TOKEN = re.compile(r'''
    (?P<space>\s+)
  | (?P<comment>--\[(?P<ceq>=*)\[[\s\S]*?(?:\](?P=ceq)\]|\Z)|--[^\n]*)
  | (?P<string>\[(?P<seq>=*)\[[\s\S]*?(?:\](?P=seq)\]|\Z)
        |"(?:\\[\s\S]|[^"\\\n])*"?|'(?:\\[\s\S]|[^'\\\n])*'?)
  | (?P<number>0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|::|[\s\S])
''', re.X)


def lua_tokens(text: str) -> list[LuaToken]:
    """Tokens of a Lua source; comments and blanks dropped, escapes and long brackets honoured."""
    tokens, line, line_start, last = [], 1, 0, 0
    for m in RE_LUA_TOKEN.finditer(text):
        start = m.start()
        newlines = text.count('\n', last, start)
        if newlines:
            line += newlines
            line_start = text.rfind('\n', last, start) + 1
        last = start
        kind = m.lastgroup if m.lastgroup not in ('ceq', 'seq') else ('comment' if m.group('comment') else 'string')
        if kind in ('space', 'comment'):
            continue
        if kind == 'name' and m.group(0) in LUA_KEYWORDS:
            kind = 'keyword'
        tokens.append(LuaToken(kind, m.group(0), line, start - line_start))
    return tokens


# --- Kahlua base library ---------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class KahluaLib:
    """Base library of a Lua state: global names, methods callable with ':' on a value (string, coroutine, random
    object) and the global tables whose functions are such methods ('string', 'coroutine')."""
    globals: frozenset[str] = frozenset()
    value_methods: frozenset[str] = frozenset()
    value_tables: frozenset[str] = frozenset()

    def merge(self, other: KahluaLib) -> KahluaLib:
        return KahluaLib(self.globals | other.globals, self.value_methods | other.value_methods,
                         self.value_tables | other.value_tables)


RE_PLATFORM_REGISTER = re.compile(r'\b([A-Z]\w*)\.register\(')
RE_NAMES_ITEM = re.compile(r'\b(\w*names)\[\d+\]\s*=\s*"(\w+)"')
RE_NAMES_ARRAY = re.compile(r'\b(\w*names)\s*=\s*new\s+String\[\]\s*\{([^}]*)\}')
RE_REGISTER_HEADER = re.compile(r'\bstatic\s+(?:\w+\s+)*void\s+register\s*\(([^)]*)\)')
RE_LOOP_RAWSET = re.compile(r'\b(\w+)\.rawset\(\s*(\w*names)\[\w+\]')
RE_LITERAL_RAWSET = re.compile(r'\b(\w+)\.rawset\(\s*"(\w+)"\s*,\s*\(Object\)\s*(\w+)')


def platform_libraries(text: str) -> list[str]:
    """Simple class names whose register() the platform calls (J2SEPlatform.setupEnvironment)."""
    return RE_PLATFORM_REGISTER.findall(text)


def _kahlua_name_arrays(text: str) -> dict[str, set[str]]:
    arrays: dict[str, set[str]] = {}
    for array, name in RE_NAMES_ITEM.findall(text):
        arrays.setdefault(array, set()).add(name)
    for array, items in RE_NAMES_ARRAY.findall(text):
        arrays.setdefault(array, set()).update(re.findall(r'"(\w+)"', items))
    return arrays


def parse_kahlua_lib(text: str) -> KahluaLib:
    """Names one Kahlua library class registers: its name arrays stored in the environment (globals) or in a table
    that is its own __index (methods on values), plus the literal names it stores in the environment."""
    header = RE_REGISTER_HEADER.search(text)
    if not header:
        return KahluaLib()
    env = {p.split()[-1] for p in header.group(1).split(',') if p.split()[:1] == ['KahluaTable']}
    arrays = _kahlua_name_arrays(text)
    literal = RE_LITERAL_RAWSET.findall(text)
    self_indexed = {table for table, key, value in literal if key == '__index' and value == table}
    globals_, methods = set(), set()
    for table, array in RE_LOOP_RAWSET.findall(text):
        if table in env:
            globals_ |= arrays.get(array, set())
        elif table in self_indexed:
            methods |= arrays.get(array, set())
    env_literals = [(key, value) for table, key, value in literal if table in env]
    return KahluaLib(frozenset(globals_ | {key for key, _ in env_literals}), frozenset(methods),
                     frozenset(key for key, value in env_literals if value in self_indexed))


def lua_function_header(tokens: list[LuaToken], i: int) -> tuple[list[str], str, int]:
    """Header of the function whose keyword is at i: (names a.b.c, last separator '.' or ':' ('' for a single name),
    index of the opening parenthesis). Anonymous function: ([], '', index of the parenthesis)."""
    parts, sep, j = [], '', i + 1
    while j < len(tokens) and tokens[j].kind == 'name':
        parts.append(tokens[j].text)
        if j + 1 < len(tokens) and tokens[j + 1].text in ('.', ':'):
            sep = tokens[j + 1].text
            j += 2
        else:
            j += 1
            break
    return parts, sep if len(parts) > 1 else '', j


def parse_stdlib_lua(text: str, value_tables: frozenset[str]) -> KahluaLib:
    """Definitions of Kahlua's stdlib.lua: global functions (function f(, f = ... at column 0) and methods added to a
    value table (function string.len()."""
    tokens = lua_tokens(text)
    globals_, methods = set(), set()
    for i, tok in enumerate(tokens):
        previous = tokens[i - 1].text if i else ''
        if tok.text == 'function' and previous != 'local':
            parts, sep, _ = lua_function_header(tokens, i)
            if len(parts) == 1:
                globals_.add(parts[0])
            elif len(parts) == 2 and sep == '.' and parts[0] in value_tables:
                methods.add(parts[1])
        elif (tok.kind == 'name' and tok.col == 0 and i + 1 < len(tokens) and tokens[i + 1].text == '='
              and previous != 'local'):
            globals_.add(tok.text)
    return KahluaLib(frozenset(globals_), frozenset(methods))


def split_vanilla_names(names) -> tuple[frozenset[str], frozenset[str]]:
    """(global names, method names) of vanilla Lua function names: 'f' is global (or a table field), the last segment
    of 'A.b' / 'A:b' is a method; a field function is also callable with ':'."""
    globals_ = frozenset(n for n in names if not re.search(r'[.:]', n))
    methods = frozenset(re.split(r'[.:]', n)[-1] for n in names)
    return globals_, methods


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


def vanilla_lua_globals() -> frozenset[str]:
    return split_vanilla_names(vanilla_lua_functions())[0]


def vanilla_lua_methods() -> frozenset[str]:
    return split_vanilla_names(vanilla_lua_functions())[1]


@lru_cache(maxsize=None)
def exposed_method_names() -> frozenset[str]:
    return frozenset(api().exposed_method_names())


def stdlib_lua_path() -> Path | None:
    """Kahlua's stdlib.lua: in the reference sources if copied there, else in the game folder; None when absent."""
    import pz_paths  # same folder; imported here so the Java table needs no game installation
    for candidate in (source_dir() / STDLIB_LUA, pz_paths.game_dir() / STDLIB_LUA):
        if candidate.is_file():
            return candidate
    return None


def lua_library_missing() -> str | None:
    """What is missing for lua_library(), or None."""
    if missing():
        return missing()
    if not (source_dir() / KAHLUA_PLATFORM).is_file():
        return f'{KAHLUA_PLATFORM} not found in the reference sources {source_dir()}'
    if stdlib_lua_path() is None:
        return f'{STDLIB_LUA} not found in the reference sources nor in the game folder (set PZ_DIR)'
    return None


@lru_cache(maxsize=None)
def lua_library() -> KahluaLib:
    """Kahlua base library of every Lua state of the game: Java libraries, then stdlib.lua over them."""
    java = api().kahlua_java_library()
    stdlib = parse_stdlib_lua(stdlib_lua_path().read_text(encoding='utf-8', errors='replace'), java.value_tables)
    return java.merge(stdlib)


if __name__ == '__main__':
    import sys
    if not available():
        print('pz_api: ' + missing())
        sys.exit(2)
    for name in sys.argv[1:] or ['IsoZombie']:
        table = class_methods(name)
        print(f'{name}: {"not exposed" if table is None else f"{len(table)} public methods"}')
