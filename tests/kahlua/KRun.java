import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.io.StringReader;
import java.util.ArrayList;

import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.expose.LuaJavaClassExposer;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;

/*
 * Kahlua bench of RadioSurvivor (tests/test_kahlua.py): runs Lua in the Kahlua VM of projectzomboid.jar, outside
 * the game, the way the game reads and calls it. Development tool only (no game state, no LuaManager).
 *
 * Run from a folder holding the game's stdlib.lua (J2SEPlatform.newEnvironment loads it from the current folder):
 *   java -cp "projectzomboid.jar;<dir of KRun.class>" KRun <action> ...
 * Actions, in order:
 *   load:NAME=PATH      compiles PATH (read as UTF-8, like the game: LuaCompiler.loadis) and runs it under
 *                       pcall; a returned value is stored in LOADED[NAME] (the Lua prelude defines require on it).
 *   eval:CODE           compiles and runs CODE; returned strings are printed.
 *   ticks:MAX:FN        calls the global function FN from Java, one KahluaThread.pcall per call (like an event
 *                       handler of the game), until it returns false / nil or MAX calls were made.
 * Errors are printed as "KRUN-ERROR <where>: <message>". The class java.util.ArrayList is exposed as the global
 * ArrayList (ArrayList.new(), list:get(i)...), with the game's number converter, so a Lua test can make a real
 * Java method throw (IndexOutOfBoundsException). As in the game (UIManager.defaultthread is this thread), such an
 * exception is caught and logged by MethodCaller.logException: the call returns nothing and Lua goes on.
 */
public class KRun {
    static KahluaThread thread;
    static KahluaTable env;

    public static void main(String[] args) throws Exception {
        J2SEPlatform platform = J2SEPlatform.getInstance();
        env = platform.newEnvironment();
        thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        // As in the game: MethodCaller.logException reports a Java exception through this thread.
        zombie.ui.UIManager.defaultthread = thread;
        KahluaConverterManager manager = new KahluaConverterManager();
        zombie.Lua.KahluaNumberConverter.install(manager);
        LuaJavaClassExposer exposer = new LuaJavaClassExposer(manager, platform, env) {
            @Override
            public boolean shouldExpose(Class<?> clazz) {
                return clazz == ArrayList.class;
            }
        };
        exposer.exposeLikeJavaRecursively(ArrayList.class, env);
        KahluaTable loaded = platform.newTable();
        env.rawset("LOADED", loaded);
        for (String arg : args) {
            if (arg.startsWith("load:")) {
                String spec = arg.substring(5);
                int eq = spec.indexOf('=');
                String name = spec.substring(0, eq);
                String path = spec.substring(eq + 1);
                Object[] r;
                try (Reader rd = new InputStreamReader(new FileInputStream(path), "UTF-8")) {
                    r = run(LuaCompiler.loadis(rd, name, env), "load " + name);
                }
                if (r != null) loaded.rawset(name, r.length > 1 && r[1] != null ? r[1] : Boolean.TRUE);
            } else if (arg.startsWith("eval:")) {
                Object[] r = run(LuaCompiler.loadis(new StringReader(arg.substring(5)), "eval", env), "eval");
                if (r != null) {
                    for (int k = 1; k < r.length; ++k) if (r[k] instanceof String) System.out.println(r[k]);
                }
            } else if (arg.startsWith("ticks:")) {
                String spec = arg.substring(6);
                int colon = spec.indexOf(':');
                int max = Integer.parseInt(spec.substring(0, colon));
                String fn = spec.substring(colon + 1);
                int n = 0;
                while (n < max) {
                    ++n;
                    Object[] r = thread.pcall(env.rawget(fn), new Object[0]);
                    if (r.length == 0 || r[0] != Boolean.TRUE) {
                        System.out.println("KRUN-ERROR tick " + n + ": " + (r.length > 1 ? r[1] : "?"));
                        break;
                    }
                    if (r.length < 2 || r[1] == null || r[1] == Boolean.FALSE) break;
                }
                System.out.println("KRUN-TICKS " + n);
            } else {
                System.out.println("KRUN-ERROR unknown action: " + arg);
            }
        }
        System.out.flush();
    }

    static Object[] run(LuaClosure closure, String where) {
        Object[] r = thread.pcall(closure, new Object[0]);
        if (r.length == 0 || r[0] != Boolean.TRUE) {
            System.out.println("KRUN-ERROR " + where + ": " + (r.length > 1 ? r[1] : "?"));
            return null;
        }
        return r;
    }
}
