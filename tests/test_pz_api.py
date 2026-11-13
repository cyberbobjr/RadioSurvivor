"""Analyse Java de tools/pz_api.py sur de petits extraits écrits pour ce banc (E19-T01) : aucune source du jeu.

    python tests/test_pz_api.py
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
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
