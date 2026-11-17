"""Analyse Java de tools/pz_api.py sur de petits extraits écrits pour ce banc (E19-T01) : aucune source du jeu.

    python tests/coreai/test_pz_api.py
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import pz_api  # noqa: E402
from pz_api import Arity, JavaApi, parse_java  # noqa: E402

SAMPLE = '''
/*
 * Header comment with a fake method: public void notAMethod() {
 */
package demo.world;

import demo.base.Thing;
import java.util.ArrayList;
import java.util.*;

@SuppressWarnings(value="unchecked")
public final class Crate<T extends Comparable<T>>
extends Thing
implements Openable, Comparable<Crate<T>> {
    public static final String NAME = "a { brace";   // field, not a method
    private static final char OPEN = '{';
    protected int hidden() { return 0; }
    private void secret() {}
    public Crate() {}
    public Crate(int size, String label) {}

    @Deprecated
    public synchronized <K, V extends java.util.List<K>> java.util.Map<K, V> index(
            java.util.Map<String, java.util.List<K>> source,
            final int depth) throws IllegalStateException {
        Runnable r = new Runnable() {
            public void run() { }
        };
        if (depth > 0) { return null; }
        return null;
    }

    public static Crate<String> of(String ... items) { return null; }
    public final int[] sizes() { return new int[]{1, 2}; }
    public void fill(int count) {}
    public void fill(String item, int count) {}
    public int compareTo(Crate<T> other) { return 0; }

    public static class Lid {
        public boolean isOpen() { return false; }
    }

    public enum Kind {
        WOOD("w") { public String tag() { return "x"; } },
        METAL("m");
        private Kind(String code) {}
        public String code() { return ""; }
    }

    public interface Seal {
        void apply(int force);
        default boolean holds() { return true; }
        static Seal none() { return null; }
        private void helper() {}
    }

    public record Label(String text, int size) implements Comparable<Label> {
        public int compareTo(Label o) { return 0; }
    }
}
'''


def methods(decl):
    out = {}
    for m in decl.methods:
        if m.public:
            out.setdefault(m.name, set()).add(m.arity)
    return out


class ParseJavaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.jf = parse_java(SAMPLE)

    def test_package_imports_and_types(self):
        self.assertEqual(self.jf.package, 'demo.world')
        self.assertEqual(self.jf.imports, {'Thing': 'demo.base.Thing', 'ArrayList': 'java.util.ArrayList'})
        self.assertEqual(self.jf.wildcards, ['java.util'])
        self.assertEqual(set(self.jf.types), {'Crate', 'Crate.Lid', 'Crate.Kind', 'Crate.Seal', 'Crate.Label'})
        self.assertEqual(self.jf.types['Crate'].supers, ['Thing', 'Openable', 'Comparable'])

    def test_public_methods_of_a_class(self):
        table = methods(self.jf.types['Crate'])
        self.assertEqual(table, {
            'new': {Arity(0), Arity(2)},
            'index': {Arity(2)},                       # generics, annotations, final, throws, two lines
            'of': {Arity(1, varargs=True)},            # varargs
            'sizes': {Arity(0)},
            'fill': {Arity(1), Arity(2)},              # overloads
            'compareTo': {Arity(1)},
        })
        self.assertNotIn('run', table)                 # anonymous class body
        self.assertNotIn('notAMethod', table)          # comment

    def test_nested_enum_interface_and_record(self):
        self.assertEqual(methods(self.jf.types['Crate.Lid']), {'isOpen': {Arity(0)}, 'new': {Arity(0)}})
        self.assertEqual(methods(self.jf.types['Crate.Kind']), {'code': {Arity(0)}})   # private constructor
        seal = methods(self.jf.types['Crate.Seal'])
        self.assertEqual(seal, {'apply': {Arity(1)}, 'holds': {Arity(0)}, 'none': {Arity(0)}})
        self.assertEqual(methods(self.jf.types['Crate.Label']),
                         {'text': {Arity(0)}, 'size': {Arity(0)}, 'compareTo': {Arity(1)}})

    def test_arity_accepts(self):
        self.assertTrue(Arity(2).accepts(2))
        self.assertFalse(Arity(2).accepts(1))
        self.assertTrue(Arity(2, varargs=True).accepts(1))
        self.assertTrue(Arity(2, varargs=True).accepts(5))
        self.assertFalse(Arity(2, varargs=True).accepts(0))
        self.assertTrue(pz_api.accepts({Arity(0), Arity(2)}, 2))


class BlankJavaTest(unittest.TestCase):
    def test_comments_and_literals(self):
        java = 'a("x\\"{", \'}\'); // f() {\nb(); /* { */ c("""\n{\n"""); d("open\ne();'
        self.assertEqual(pz_api.blank_java(java), 'a("", \'\'); \nb();   c(""); d(""e();')


class LuaLexerTest(unittest.TestCase):
    def test_tokens(self):
        lua = 'a:b("x:y()") -- c:d()\n--[=[ e:f() ]=] g[[h:i()]] j = \'k\\\'l\' .. 0x1F\n'
        self.assertEqual([(t.kind, t.text, t.line) for t in pz_api.lua_tokens(lua)], [
            ('name', 'a', 1), ('op', ':', 1), ('name', 'b', 1), ('op', '(', 1), ('string', '"x:y()"', 1),
            ('op', ')', 1), ('name', 'g', 2), ('string', '[[h:i()]]', 2), ('name', 'j', 2), ('op', '=', 2),
            ('string', "'k\\'l'", 2), ('op', '..', 2), ('number', '0x1F', 2)])

    def test_function_header(self):
        toks = pz_api.lua_tokens('function A.b:c(x) end function f(y) end local g = function(z) end')
        heads = [pz_api.lua_function_header(toks, i) for i, t in enumerate(toks) if t.text == 'function']
        self.assertEqual([(parts, sep, toks[paren].text) for parts, sep, paren in heads],
                         [(['A', 'b', 'c'], ':', '('), (['f'], '', '('), ([], '', '(')])

    def test_keywords_and_columns(self):
        toks = pz_api.lua_tokens('local function f() end\n  return nil')
        self.assertEqual([t.kind for t in toks], ['keyword', 'keyword', 'name', 'op', 'op', 'keyword', 'keyword',
                                                  'keyword'])
        self.assertEqual((toks[-1].line, toks[-1].col), (2, 9))


class KahluaLibraryTest(unittest.TestCase):
    """Bibliothèque de base Kahlua relevée sur de petits extraits écrits pour ce banc."""

    def test_platform_libraries(self):
        self.assertEqual(pz_api.platform_libraries('MathLib.register(this, env);\nBaseLib.register(env);'),
                         ['MathLib', 'BaseLib'])

    def test_object_library_and_environment_literals(self):
        java = '''public final class RandomLib {
    private static final String[] names = new String[2];
    public static void register(Platform platform, KahluaTable environment) {
        KahluaTable t = platform.newTable();
        for (int i = 0; i < 2; ++i) { t.rawset(names[i], (Object)functions[i]); }
        t.rawset("__index", (Object)t);
        environment.rawset("newrandom", (Object)NEWRANDOM_FUN); }
    static { RandomLib.names[0] = "random"; RandomLib.names[1] = "seed"; } }'''
        lib = pz_api.parse_kahlua_lib(java)
        self.assertEqual((lib.globals, lib.value_methods, lib.value_tables),
                         ({'newrandom'}, {'random', 'seed'}, frozenset()))

    def test_plain_table_library_is_not_a_value_library(self):
        java = '''class OsLib { private static final String[] funcnames = new String[1];
    public static void register(Platform platform, KahluaTable env) { KahluaTable os = platform.newTable();
        for (int i = 0; i < 1; ++i) { os.rawset(funcnames[i], (Object)funcs[i]); }
        env.rawset("os", (Object)os); }
    static { OsLib.funcnames[0] = "time"; } }'''
        self.assertEqual(pz_api.parse_kahlua_lib(java), pz_api.KahluaLib(frozenset({'os'})))

    def test_stdlib_lua(self):
        lua = '''function assert(c, ...) end
--[[ function ipairs(t) end ]]
ipairs = table.ipairs
do
    local function helper() end
    function table.sort(t, comp) end
end
function string.len(s)
    local n = 1
    max = n
end
'''
        lib = pz_api.parse_stdlib_lua(lua, frozenset({'string'}))
        self.assertEqual((lib.globals, lib.value_methods), ({'assert', 'ipairs'}, {'len'}))

    def test_split_vanilla_names(self):
        globals_, methods = pz_api.split_vanilla_names({'ISFoo.new', 'ISBar:render', 'luautils', 'A.b.c'})
        self.assertEqual(globals_, {'luautils'})
        self.assertEqual(methods, {'new', 'render', 'luautils', 'c'})


class InheritanceTest(unittest.TestCase):
    """Résolution des classes mères (paquet, import, joker, imbriquée, JDK) sur une petite arborescence."""

    FILES = {
        'java/demo/base/Thing.java': '''package demo.base;
public abstract class Thing implements demo.base.Named {
    public int getX() { return 0; }
    public static Thing make() { return null; }
    protected void internal() {}
}''',
        'java/demo/base/Named.java': '''package demo.base;
public interface Named { String getName(); default boolean hasName() { return true; }
    static Named anonymous() { return null; } }''',
        'java/demo/world/Openable.java': '''package demo.world;
public interface Openable { void open(); }''',
        'java/demo/world/Crate.java': SAMPLE,
        'java/demo/world/Shelf.java': '''package demo.world;
import java.util.ArrayList;
public class Shelf extends ArrayList<Crate> { public void tidy() {} }''',
        'java/demo/other/Box.java': '''package demo.other;
import demo.world.*;
public class Box extends Crate.Lid { public void tape(int n, int m) {} }''',
        'java/demo/Registry.java': '''package demo;
public class Registry { public static class Writer { public void write(String s) {} } }''',
        # Exposition déléguée (absente de l'index) : LuaManager -> Atlas.setExposed -> Pin.setExposed.
        'java/zombie/Lua/LuaManager.java': '''package zombie.Lua;
import demo.map.Atlas;
public final class LuaManager { public static class Exposer {
    void exposeAll() { this.setExposed(Integer.class); Atlas.setExposed(this); }
    public void setExposed(Class<?> c) {} } }''',
        'java/demo/map/Atlas.java': '''package demo.map;
public class Atlas { public void zoomTo(int level) {}
    public static class Layer { public void hide() {} }
    public static void setExposed(LuaManager.Exposer exposer) {
        exposer.setExposed(Atlas.class); exposer.setExposed(Atlas.Layer.class); Pin.setExposed(exposer); } }''',
        'java/demo/map/Pin.java': '''package demo.map;
public class Pin { public void drop() {}
    public static void setExposed(LuaManager.Exposer exposer) { exposer.setExposed(Pin.class); } }''',
        # Plate-forme Kahlua : bibliothèques enregistrées par setupEnvironment.
        'java/se/krka/kahlua/j2se/J2SEPlatform.java': '''package se.krka.kahlua.j2se;
import se.krka.kahlua.stdlib.BaseLib;
import se.krka.kahlua.stdlib.StringLib;
public class J2SEPlatform { public void setupEnvironment(KahluaTable env) {
    BaseLib.register(env); StringLib.register(this, env); } }''',
        'java/se/krka/kahlua/stdlib/BaseLib.java': '''package se.krka.kahlua.stdlib;
public final class BaseLib { private static final String[] names = new String[2];
    public static void register(KahluaTable environment) {
        for (int i = 0; i < 2; ++i) { environment.rawset(names[i], (Object)functions[i]); } }
    static { BaseLib.names[0] = "pcall"; BaseLib.names[1] = "type"; } }''',
        'java/se/krka/kahlua/stdlib/StringLib.java': '''package se.krka.kahlua.stdlib;
public final class StringLib { private static final String[] names = new String[]{"sub", "find"};
    public static synchronized void register(Platform platform, KahluaTable env) {
        KahluaTable string = platform.newTable();
        for (int i = 0; i < 2; ++i) { string.rawset(names[i], (Object)functions[i]); }
        string.rawset("__index", (Object)string);
        env.rawset("string", (Object)string); } }''',
    }
    INDEX = ('# exposed\n'
             'demo.world.Crate\tCrate\tjava/demo/world/Crate.java\n'
             'demo.world.Shelf\tShelf\tjava/demo/world/Shelf.java\n'
             'demo.other.Box\tBox\tjava/demo/other/Box.java\n'
             'demo.Writer\tWriter\t?\n'
             'java.util.ArrayList\tArrayList\t?\n')

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix='pz_api_'))
        for rel, text in cls.FILES.items():
            path = cls.tmp / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
        (cls.tmp / pz_api.EXPOSED_INDEX).write_text(cls.INDEX, encoding='utf-8')
        (cls.tmp / pz_api.METHODS_INDEX).write_text(
            '# h\ngetWorld\tglobal\tx:1\tsig\nisOpen\tmethod\tx:2\tsig\n', encoding='utf-8')
        (cls.tmp / pz_api.EVENTS_INDEX).write_text('# h\nOnTick\tjava\t\nOnCustom\tlua\t\n', encoding='utf-8')
        (cls.tmp / pz_api.VANILLA_INDEX).write_text('# h\nISFoo.new\tself\tm.lua:1\n', encoding='utf-8')
        cls.api = JavaApi(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_superclass_by_import_and_interfaces_by_package(self):
        crate = self.api.class_methods('Crate')
        for name in ('getX', 'make', 'getName', 'hasName', 'open', 'index', 'toString', 'equals'):
            self.assertIn(name, crate)
        self.assertNotIn('internal', crate)           # protected
        self.assertNotIn('anonymous', crate)          # static interface method: not inherited
        self.assertEqual(crate['new'], {Arity(0), Arity(2)})  # own constructors only

    def test_static_methods_inherited_without_constructors(self):
        crate = self.api.class_static_methods('Crate')
        self.assertEqual(crate['make'], {Arity(0)})        # public static of the superclass Thing
        self.assertNotIn('getX', crate)                    # instance method
        self.assertNotIn('anonymous', crate)               # static interface method: not inherited
        self.assertEqual(crate['new'], {Arity(0), Arity(2)})
        self.assertEqual(self.api.class_static_methods('Box')['new'], {Arity(0)})
        self.assertIn('new', self.api.class_static_methods('ArrayList'))
        self.assertIsNone(self.api.class_static_methods('Inconnue'))

    def test_nested_superclass_through_wildcard_import(self):
        box = self.api.class_methods('Box')
        self.assertIn('isOpen', box)
        self.assertEqual(box['tape'], {Arity(2)})
        self.assertEqual(box['new'], {Arity(0)})     # implicit constructor, not the parent's

    def test_jdk_superclass_and_exposed_jdk_class(self):
        shelf = self.api.class_methods('Shelf')
        for name in ('tidy', 'size', 'get', 'add', 'isEmpty', 'iterator', 'hashCode'):
            self.assertIn(name, shelf)
        self.assertEqual(shelf['new'], {Arity(0)})
        array = self.api.class_methods('ArrayList')
        self.assertEqual(array['add'], {Arity(1), Arity(2)})
        self.assertIn('new', array)

    def test_nested_class_found_in_package_folder(self):
        self.assertEqual(self.api.class_methods('Writer')['write'], {Arity(1)})

    def test_unknown_class_and_indexes(self):
        self.assertIsNone(self.api.class_methods('Nothing'))
        self.assertEqual(self.api.global_functions(), {'getWorld'})
        self.assertEqual(self.api.events(), {'OnTick', 'OnCustom'})
        self.assertEqual(self.api.vanilla_lua_functions(), {'ISFoo.new'})

    def test_delegated_exposure_is_followed(self):
        rows = self.api.delegated_exposed()
        self.assertEqual([r[:2] for r in rows], [('demo.map.Atlas', 'Atlas'), ('demo.map.Atlas.Layer', 'Layer'),
                                                 ('demo.map.Pin', 'Pin')])
        self.assertNotIn('Integer', self.api.exposed())      # exposition directe de LuaManager : l'index la porte
        self.assertIn('zoomTo', self.api.class_methods('Atlas'))
        self.assertEqual(self.api.class_methods('Layer')['hide'], {Arity(0)})

    def test_exposed_method_names_is_the_union(self):
        names = self.api.exposed_method_names()
        for name in ('tidy', 'tape', 'getX', 'drop', 'hide', 'write', 'toString'):
            self.assertIn(name, names)
        self.assertNotIn('internal', names)

    def test_kahlua_java_library(self):
        lib = self.api.kahlua_java_library()
        self.assertEqual(lib.globals, {'pcall', 'type', 'string'})
        self.assertEqual(lib.value_methods, {'sub', 'find'})
        self.assertEqual(lib.value_tables, {'string'})

    def test_available_follows_the_environment(self):
        saved = os.environ.get('PZ_SOURCE_DIR')
        try:
            os.environ['PZ_SOURCE_DIR'] = str(self.tmp)
            self.assertTrue(pz_api.available())
            os.environ['PZ_SOURCE_DIR'] = str(self.tmp / 'absent')
            self.assertFalse(pz_api.available())
            self.assertIn('PZ_SOURCE_DIR', pz_api.missing())
        finally:
            if saved is None:
                os.environ.pop('PZ_SOURCE_DIR', None)
            else:
                os.environ['PZ_SOURCE_DIR'] = saved


if __name__ == '__main__':
    unittest.main(verbosity=1)
