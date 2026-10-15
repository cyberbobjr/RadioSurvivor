"""Auto-tests du banc hors jeu Living Knox (tests/harness.py).

    python RadioSurvivor/tests/test_harness.py

Vérifie le banc lui-même (machines, événements, réseau, propriétaires de zombies, horloges, fichiers, solo),
pas le mod ni l'API Java réelle.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, HarnessError, LuaError  # noqa: E402


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Base(unittest.TestCase):
    mode = 'mp'

    def setUp(self):
        self.h = Harness(mode=self.mode)

    def tearDown(self):
        self.h.close()


class MachinesTests(Base):
    def test_isolation(self):
        self.h.load('server', 'SECRET = 42')
        self.assertEqual(self.h.eval('server', 'SECRET'), 42)
        self.assertIsNone(self.h.eval('A', 'SECRET'))
        self.assertIsNone(self.h.eval('B', 'SECRET'))
        self.h.load('A', 'getPlayer():getModData().x = 1')
        self.assertIsNone(self.h.eval('server', 'getPlayerByOnlineID(0):getModData().x'))

    def test_kahlua_globals(self):
        for m in ('server', 'A', 'B'):
            self.assertIsNone(self.h.eval(m, 'next'))
            self.assertIsNone(self.h.eval(m, 'python'))
            self.assertIs(self.h.eval(m, 'isDebugEnabled()'), False)
            self.assertTrue(self.h.eval(m, 'pairs({}) ~= nil'))
        self.assertEqual(self.h.load('server', 'return isServer(), isClient()'), (True, False))
        self.assertEqual(self.h.load('A', 'return isServer(), isClient()'), (False, True))
        with Harness(debug=True) as h:
            self.assertIs(h.eval('B', 'isDebugEnabled()'), True)

    def test_players(self):
        self.assertIsNone(self.h.eval('server', 'getPlayer()'))
        self.assertEqual(self.h.eval('A', 'getPlayer():getUsername()'), 'A')
        self.assertEqual(self.h.eval('B', 'getPlayer():getOnlineID()'), 1)
        self.assertEqual(self.h.eval('server', 'getOnlinePlayers():size()'), 2)
        self.assertIs(self.h.eval('A', 'getPlayerFromUsername("B"):isLocalPlayer()'), False)
        self.assertIsNone(self.h.eval('server', 'getPlayerFromUsername("B")'))
        self.h.move_player('A', 10.5, 20.2, 0)
        self.assertEqual(self.h.load('B', 'local p = getPlayerByOnlineID(0); return p:getSquare():getX(), p:getY()'),
                         (10, 20.2))
        self.assertFalse(self.h.eval('server', 'getPlayerByOnlineID(0):isDead()'))
        self.h.load('server', 'DEAD = {}; Events.OnCharacterDeath.Add(function(c) DEAD[#DEAD + 1] = c:getUsername() end)')
        self.h.kill_player('A')
        self.assertEqual(lua_list(self.h.eval('server', 'DEAD')), ['A'])
        self.assertTrue(self.h.eval('B', 'getPlayerByOnlineID(0):isDead()'))

    def test_load_mod_file_and_require(self):
        codec = self.h.load('server', 'shared/RadioSurvivor/RS_Codec.lua')
        self.assertIsNotNone(codec)
        self.assertEqual(self.h.eval('A', 'type(require("RadioSurvivor/RS_Codec"))'), 'table')
        # Le client MP charge aussi media/lua/server (GameLoadingState.java:153) ; le dédié n'exécute pas client/.
        self.assertTrue(self.h.eval('A', '(pcall(require, "RadioSurvivor/RS_State"))'))
        self.assertFalse(self.h.eval('server', '(pcall(require, "RadioSurvivor/RS_Notebook"))'))
        with self.assertRaises(FileNotFoundError):
            self.h.load('server', 'shared/absent.lua')
        with self.assertRaises(LuaError):
            self.h.load('server', 'error("boom")')

    def test_java_doubles_fail_like_java(self):
        with self.assertRaises(LuaError):
            self.h.eval('server', 'getCell():getGridSquare(nil, 1, 0)')
        with self.assertRaises(LuaError):
            self.h.eval('server', 'getCell():getZombieList():get(0)')
        self.assertEqual(self.h.load('server', 'local s = getCell():getGridSquare(3.7, -0.5, 0); return s:getX(), s:getY()'),
                         (3, -1))
        self.assertIs(self.h.eval('server', 'getCell():getGridSquare(1, 1, 0) == getCell():getGridSquare(1.2, 1.9, 0)'),
                      True)
        self.assertEqual(self.h.eval('server', 'getCell():getGridSquare(0, 0, 0):getObjects():size()'), 0)


class EventsTests(Base):
    def test_unknown_event_is_nil_and_addevent(self):
        self.assertIsNone(self.h.eval('server', 'Events.LKUnknownEvent'))
        self.h.load('server', 'LuaEventManager.AddEvent("LKCustom"); N = 0; Events.LKCustom.Add(function(a) N = N + a end)')
        self.h.load('server', 'triggerEvent("LKCustom", 3)')
        self.assertEqual(self.h.eval('server', 'N'), 3)

    def test_add_without_dedup_and_remove_from_callback(self):
        self.h.load('server', '''
            CALLS = {}
            local function f() CALLS[#CALLS + 1] = "f" end
            local function g() CALLS[#CALLS + 1] = "g"; Events.OnTick.Remove(g) end
            local function k() CALLS[#CALLS + 1] = "k" end
            Events.OnTick.Add(f); Events.OnTick.Add(f); Events.OnTick.Add(g); Events.OnTick.Add(k)
        ''')
        self.h.fire('server', 'OnTick', 0)
        self.h.fire('server', 'OnTick', 1)
        self.assertEqual(lua_list(self.h.eval('server', 'CALLS')), ['f', 'f', 'g', 'k', 'f', 'f', 'k'])

    def test_callback_error_isolated_and_strict(self):
        self.h.load('A', 'OK = 0; Events.OnTick.Add(function() error("bad") end); Events.OnTick.Add(function() OK = OK + 1 end)')
        with self.assertRaises(HarnessError):
            self.h.tick()
        self.assertEqual(self.h.eval('A', 'OK'), 1)
        self.assertEqual(len(self.h.errors('A')), 1)
        self.h.strict = False
        self.h.tick()
        self.assertEqual(self.h.eval('A', 'OK'), 2)
        self.assertTrue(any('bad' in line for line in self.h.logs('A')))

    def test_tick_order_and_pause(self):
        self.h.spawn_zombie(7, 1, 1, 0)
        self.h.load('server', '''
            ORDER = {}
            Events.OnTickEvenPaused.Add(function(n) ORDER[#ORDER + 1] = "paused" .. n end)
            Events.OnZombieUpdate.Add(function(z) ORDER[#ORDER + 1] = "z" .. z:getOnlineID() end)
            Events.OnTick.Add(function(n) ORDER[#ORDER + 1] = "tick" .. n end)
        ''')
        self.h.tick(2)
        self.assertEqual(lua_list(self.h.eval('server', 'ORDER')), ['paused0', 'z7', 'tick1', 'paused1', 'z7', 'tick2'])
        self.h.set_paused('server')
        self.h.load('server', 'ORDER = {}')
        self.h.tick()
        self.assertEqual(lua_list(self.h.eval('server', 'ORDER')), ['paused2'])


class NetworkTests(Base):
    RECEIVERS = '''
        GOT = {}
        Events.OnClientCommand.Add(function(module, command, player, args)
            GOT[#GOT + 1] = {module = module, command = command, player = player:getUsername(), args = args} end)
        Events.OnServerCommand.Add(function(module, command, args)
            GOT[#GOT + 1] = {module = module, command = command, args = args} end)
    '''

    def setUp(self):
        super().setUp()
        for m in ('server', 'A', 'B'):
            self.h.load(m, self.RECEIVERS)

    def got(self, m):
        return lua_list(self.h.eval(m, 'GOT'))

    def test_client_to_server_copy_and_filter(self):
        self.h.spawn_zombie(5, 0, 0, 0)
        self.h.load('A', '''
            SENT = {n = 1, s = "x", ok = false, f = print, z = getCell():getZombieList():get(0), [true] = 1,
                    nested = {list = {10, 20}, deep = {k = "v", g = print}}}
            sendClientCommand("LK", "hello", SENT)
        ''')
        self.assertEqual(self.got('server'), [])  # rien avant pump()
        self.assertEqual(self.h.pump(), 1)
        msg = self.got('server')[0]
        self.assertEqual((msg['module'], msg['command'], msg['player']), ('LK', 'hello', 'A'))
        args = msg['args']
        self.assertEqual(sorted(args.keys()), ['n', 'nested', 'ok', 's'])
        self.assertIs(args['ok'], False)
        self.assertEqual(lua_list(args['nested']['list']), [10, 20])
        self.assertEqual(list(args['nested']['deep'].keys()), ['k'])
        logs = self.h.logs('A')
        self.assertTrue(any("can't save key,value=f," in line for line in logs))
        self.assertTrue(any("can't save key,value=z," in line for line in logs))
        # La table reçue est une copie : la modifier ne change pas l'émetteur.
        self.h.load('server', 'GOT[1].args.nested.list[1] = 99')
        self.assertEqual(self.h.eval('A', 'SENT.nested.list[1]'), 10)

    def test_empty_args_become_nil(self):
        self.h.load('A', 'sendClientCommand("LK", "empty", {}); sendClientCommand("LK", "none")')
        self.h.load('server', 'sendServerCommand("LK", "empty", {})')
        self.h.pump()
        self.assertEqual([m['args'] for m in self.got('server')], [None, None])
        self.assertIsNone(self.got('A')[0]['args'])

    def test_player_argument_rules(self):
        self.h.load('A', 'sendClientCommand(getPlayer(), "LK", "mine", {a = 1})')
        self.h.load('A', 'sendClientCommand(getPlayerByOnlineID(1), "LK", "other", {a = 1})')  # joueur distant
        self.h.pump()
        self.assertEqual([m['command'] for m in self.got('server')], ['mine'])
        with self.assertRaises(LuaError):
            self.h.load('server', 'sendClientCommand("LK", "x", {})')
        # Forme à joueur sur le serveur : déclenchement immédiat, même table.
        self.h.load('server', 'T = {a = 1}; sendClientCommand(getPlayerByOnlineID(1), "LK", "local", T)')
        last = self.got('server')[-1]
        self.assertEqual((last['command'], last['player']), ('local', 'B'))
        self.assertTrue(self.h.eval('server', 'GOT[#GOT].args == T'))

    def test_server_to_client_targeted_and_broadcast(self):
        self.h.load('server', 'sendServerCommand(getPlayerByOnlineID(1), "LK", "toB", {v = 1})')
        self.h.load('server', 'sendServerCommand("LK", "all", {v = 2})')
        self.h.load('A', 'sendServerCommand("LK", "fromClient", {v = 3})')  # sans effet sur un client
        self.assertEqual(len(self.h.pending()), 3)
        self.h.pump()
        self.assertEqual([m['command'] for m in self.got('A')], ['all'])
        self.assertEqual([m['command'] for m in self.got('B')], ['toB', 'all'])
        self.assertEqual(self.got('server'), [])

    def test_unordered_delivery(self):
        self.h.load('A', 'for i = 1, 6 do sendClientCommand("LK", "n" .. i, {i = i}) end')
        self.h.pump(order='lifo')
        self.assertEqual([m['args']['i'] for m in self.got('server')], [6, 5, 4, 3, 2, 1])
        self.h.load('server', 'GOT = {}')
        self.h.load('A', 'for i = 1, 6 do sendClientCommand("LK", "n" .. i, {i = i}) end')
        self.h.pump(order='random')
        order = [m['args']['i'] for m in self.got('server')]
        self.assertEqual(sorted(order), [1, 2, 3, 4, 5, 6])
        self.assertNotEqual(order, [1, 2, 3, 4, 5, 6])

    def test_pump_limit_and_reply_chain(self):
        self.h.load('server', '''Events.OnClientCommand.Add(function(module, command, player, args)
            if command == "ping" then sendServerCommand(player, "LK", "pong", args) end end)''')
        self.h.load('A', 'sendClientCommand("LK", "ping", {k = 1}); sendClientCommand("LK", "ping", {k = 2})')
        self.assertEqual(self.h.pump(limit=1), 1)
        self.assertEqual(len(self.h.pending()), 2)  # le second ping et le premier pong
        self.h.pump()
        self.assertEqual([m['args']['k'] for m in self.got('A')], [1, 2])

    def test_cyclic_table_refused(self):
        with self.assertRaises(LuaError):
            self.h.load('A', 'local t = {}; t.self = t; sendClientCommand("LK", "cyc", {t = t})')


class OwnershipTests(Base):
    SCRIPT = '''
        RAN = {}
        -- Simulé ici : client = not isRemoteZombie() ; serveur = getOwner() == nil (isRemoteZombie() y est VRAI pour
        -- ses propres zombies : NetworkZombieComponent.java:23, isRemote() = authOwner == null).
        local function simulatedHere(z)
            if isClient() then return not z:isRemoteZombie() end
            return z:getOwner() == nil
        end
        Events.OnZombieUpdate.Add(function(z)
            if not simulatedHere(z) then return end
            RAN[#RAN + 1] = z:getOnlineID()
            z:getModData().steps = (z:getModData().steps or 0) + 1
        end)
    '''

    def ran(self, m):
        return lua_list(self.h.eval(m, 'RAN'))

    def reset(self):
        for m in ('server', 'A', 'B'):
            self.h.load(m, 'RAN = {}')

    def test_owner_runs_and_transfer(self):
        for m in ('server', 'A', 'B'):
            self.h.load(m, self.SCRIPT)
        self.h.spawn_zombie(101, 10, 10, 0, owner='A')
        self.h.spawn_zombie(102, 12, 10, 0, owner='server')
        self.h.tick(3)
        self.assertEqual(self.ran('A'), [101, 101, 101])
        self.assertEqual(self.ran('B'), [])
        self.assertEqual(self.ran('server'), [102, 102, 102])
        # Java 42.21.0 : isRemoteZombie() = authOwner == null (NetworkZombieComponent.java:23). Sur le serveur, 101
        # (possédé par A) n'est pas distant et a une connexion propriétaire ; 102, simulé par le serveur, est distant.
        zl = 'getCell():getZombieList():get(%d)'
        self.assertIs(self.h.eval('server', f'{zl % 0}:isRemoteZombie()'), False)
        self.assertEqual(self.h.eval('server', f'{zl % 0}:getOwnerPlayer():getUsername()'), 'A')
        self.assertIsNotNone(self.h.eval('server', f'{zl % 0}:getOwner()'))
        self.assertIs(self.h.eval('server', f'{zl % 1}:isRemoteZombie()'), True)
        self.assertIsNone(self.h.eval('server', f'{zl % 1}:getOwner()'))
        self.assertIs(self.h.eval('A', f'{zl % 0}:isRemoteZombie()'), False)
        self.assertIs(self.h.eval('B', f'{zl % 0}:isRemoteZombie()'), True)
        self.assertIs(self.h.eval('A', f'{zl % 1}:isRemoteZombie()'), True)
        self.h.set_owner(101, 'B')
        self.reset()
        self.h.tick(2)
        self.assertEqual(self.ran('A'), [])
        self.assertEqual(self.ran('B'), [101, 101])
        # ModData propres à chaque machine : jamais synchronisées par le banc.
        self.assertEqual(self.h.zombie('A', 101).getModData(self.h.zombie('A', 101)).steps, 3)
        self.assertEqual(self.h.zombie('B', 101).getModData(self.h.zombie('B', 101)).steps, 2)
        self.h.set_owner(101, 'server')
        self.reset()
        self.h.tick()
        self.assertEqual(self.ran('server'), [101, 102])
        with self.assertRaises(ValueError):
            self.h.set_owner(101, 'C')

    def test_move_and_kill(self):
        self.h.spawn_zombie(9, 1, 1, 0, owner='A')
        self.h.move_zombie(9, 4.5, 6.5)
        self.assertEqual(self.h.load('B', 'local z = getCell():getZombieList():get(0); return z:getSquare():getX(), z:getY()'),
                         (4, 6.5))
        self.assertEqual(self.h.eval('B', 'getCell():getGridSquare(4, 6, 0):getMovingObjects():size()'), 1)
        self.assertEqual(self.h.eval('B', 'getCell():getGridSquare(1, 1, 0):getMovingObjects():size()'), 0)
        self.h.load('server', 'DEAD = 0; Events.OnCharacterDeath.Add(function(c) if c:isDead() and instanceof(c, "IsoZombie") then DEAD = DEAD + 1 end end)')
        self.h.kill_zombie(9)
        self.assertEqual(self.h.eval('server', 'DEAD'), 1)
        self.assertEqual(self.h.eval('A', 'getCell():getZombieList():size()'), 0)


class ClockTests(Base):
    def test_real_clock_and_server_time(self):
        t0 = self.h.eval('A', 'getTimestampMs()')
        s0 = self.h.eval('server', 'GameTime.getServerTimeMills()')
        self.h.advance_ms(1500)
        self.assertEqual(self.h.eval('A', 'getTimestampMs()') - t0, 1500)
        self.assertEqual(self.h.eval('server', 'GameTime.getServerTimeMills()') - s0, 1500)
        self.assertEqual(self.h.eval('A', 'GameTime.getServerTimeMills()'), s0 + 1500)
        self.h.set_clock_synced('B', False)
        self.assertEqual(self.h.eval('B', 'GameTime.getServerTimeMills()'), 0)
        self.h.tick(10)
        self.assertEqual(self.h.eval('A', 'getTimestampMs()') - t0, 1500 + 10 * self.h.tick_ms)

    def test_game_clock_and_every_minute(self):
        for m in ('server', 'A', 'B'):
            self.h.load(m, 'M, T = 0, 0; Events.EveryOneMinute.Add(function() M = M + 1 end); '
                           'Events.EveryTenMinutes.Add(function() T = T + 1 end)')
        self.assertEqual(self.h.load('server', 'local g = getGameTime(); return g:getYear(), g:getMonth(), g:getDay(), g:getHour(), g:getMinutes()'),
                         (1993, 6, 8, 9, 0))
        self.assertEqual(self.h.eval('server', 'getGameTime():getWorldAgeHours()'), 2)
        self.h.advance(25)
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.h.load(m, 'return M, T'), (25, 2))
        self.assertEqual(self.h.load('A', 'return getGameTime():getHour(), getGameTime():getMinutes()'), (9, 25))
        self.h.advance(15 * 60)  # jusqu'à 00:25 le lendemain
        self.assertEqual(self.h.load('A', 'local g = getGameTime(); return g:getDay(), g:getHour(), g:getMinutes()'),
                         (9, 0, 25))
        self.assertAlmostEqual(self.h.eval('A', 'getGameTime():getWorldAgeHours()'), 2 + (25 + 900) / 60)


class FileTests(Base):
    def test_files_per_machine_and_rules(self):
        self.h.load('server', '''
            local w = getFileWriter("LivingKnox/state.txt", true, false)
            w:writeln("one"); w:write("two"); w:close()
        ''')
        self.assertEqual((self.h.file_root('server') / 'LivingKnox/state.txt').read_text(encoding='utf-8'), 'one\ntwo')
        self.assertEqual(self.h.load('server', '''
            local r = getFileReader("LivingKnox/state.txt", false)
            local a, b, c = r:readLine(), r:readLine(), r:readLine(); r:close(); return a, b, c'''), ('one', 'two', None))
        self.assertIsNone(self.h.eval('A', 'getFileReader("LivingKnox/state.txt", false)'))
        self.assertFalse((self.h.file_root('A') / 'LivingKnox').exists())
        # Extensions et chemins refusés comme le jeu ; le lecteur ne filtre pas l'extension.
        for name in ('x.lua', 'x.TXT', 'x', '../x.txt', 'a/../x.json'):
            self.assertIsNone(self.h.eval('A', f'getFileWriter("{name}", true, false)'), name)
        self.assertIsNone(self.h.eval('A', 'getFileReader("../x.txt", true)'))
        self.assertIsNotNone(self.h.eval('A', 'getFileReader("data.lua", true)'))
        for ext in ('ini', 'cfg', 'txt', 'log', 'json'):
            self.assertIsNotNone(self.h.eval('B', f'getFileWriter("f.{ext}", true, false)'), ext)

    def test_append_and_truncate(self):
        self.h.load('A', 'local w = getFileWriter("log.log", true, false); w:writeln("a"); w:close()')
        self.h.load('A', 'local w = getFileWriter("log.log", true, true); w:writeln("b"); w:close()')
        self.assertEqual(self.h.load('A', '''local r = getFileReader("log.log", false)
            return r:readLine(), r:readLine(), r:readLine()'''), ('a', 'b', None))
        self.h.load('A', 'W = getFileWriter("log.log", true, false)')  # tronqué dès l'ouverture
        self.assertEqual((self.h.file_root('A') / 'log.log').read_text(encoding='utf-8'), '')
        with self.assertRaises(LuaError):
            self.h.load('A', 'W:write(nil)')


class SoloTests(Base):
    mode = 'solo'

    def test_solo_machine(self):
        h = self.h
        self.assertIs(h.server, h.clients['A'])
        self.assertEqual(h.load('solo', 'return isServer(), isClient()'), (False, False))
        self.assertEqual(h.eval('A', 'getOnlinePlayers():size()'), 0)
        self.assertIsNone(h.eval('A', 'getPlayerByOnlineID(0)'))
        self.assertEqual(h.eval('A', 'getPlayer():getUsername()'), 'A')
        self.assertEqual(h.eval('A', 'GameTime.getServerTimeMills()'), 0)
        h.spawn_zombie(3, 1, 1, 0, owner='B')
        # Solo : aucun setOwner, donc authOwner == null et isRemoteZombie() toujours vrai
        # (NetworkZombieComponent.java:23 ; seuls NetworkZombieSimulator.becomeLocal et le serveur posent un propriétaire).
        self.assertIs(h.eval('A', 'getCell():getZombieList():get(0):isRemoteZombie()'), True)
        self.assertIsNone(h.eval('A', 'getCell():getZombieList():get(0):getOwner()'))

    def test_solo_commands(self):
        h = self.h
        h.load('A', '''
            GOT, SC = {}, 0
            Events.OnClientCommand.Add(function(m, c, p, a) GOT[#GOT + 1] = {c = c, p = p:getUsername(), a = a} end)
            Events.OnServerCommand.Add(function() SC = SC + 1 end)
            SENT = {v = {1}}
            sendClientCommand("LK", "now", SENT)
            sendServerCommand("LK", "never", {x = 1})
        ''')
        self.assertEqual(h.pending(), [])
        self.assertEqual(h.load('A', 'return #GOT, GOT[1].c, GOT[1].p, SC'), (1, 'now', 'A', 0))
        self.assertFalse(h.eval('A', 'GOT[1].a == SENT'))
        h.load('A', 'GOT[1].a.v[1] = 5')
        self.assertEqual(h.eval('A', 'SENT.v[1]'), 1)


if __name__ == '__main__':
    unittest.main(verbosity=1)
