"""Repère de carte gardé après une reconnexion du client demandeur (E07-T04, base rs.actions.map de la campagne
mp-persist) : rs.actions.map.before puis rs.actions.map.after-reconnect sur un serveur dédié et un client doublés.

    python RadioSurvivor/tests/test_map_persist.py

Le serveur joue les vraies suites de RS_MapActions.lua avec le vrai RST_Steps.lua, le vrai RST_Persist.lua et le
vrai RST_ViewSteps.lua côté client (étape map.symbols) ; la décision mark_map, la fiche de voix et les symboles de la
carte du client sont des doublures. La reconnexion est simulée : nouvel état Lua du client, nouvel objet MapItem,
symboles privés recopiés comme les relit MapItem.LoadWorldMap (map_symbols.bin du cache du client). Ne prouve rien
sur le Java du jeu : la campagne MP réelle (autoclient.py --phases reconnect2,reconnect,restart) reste nécessaire.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rst import LUA, ROOT, Machine, SERVER_GAME, to_py  # noqa: E402
from test_rst_steps import STEPS_FILE, VIEW_FILE, VIEW_GAME, StepsNetwork  # noqa: E402

SUITE_FILE = LUA / 'shared' / 'RST' / 'suites' / 'RS_MapActions.lua'
CORE_SHARED = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivorCore' / '42.21' / 'media' / 'lua' / 'shared'

# Server side: the voice sheet parser and the mark_map decision as doubles. The decision sends the place to the
# caller, as RS_MapMarks.give does (Const.toClient -> sendServerCommand to that player only).
MAP_SERVER = r"""
package.path = [[""" + CORE_SHARED.as_posix() + r"""/?.lua;]] .. package.path
DECISIONS = {}
package.loaded["RadioSurvivor/RS_State"] = { data = { actionCounters = {} }, dirty = false }
package.loaded["RadioSurvivor/RS_MapMarks"] = {}
package.loaded["RadioSurvivor/RS_Persona"] = {
    parseLines = function(lines, id) return { id = id, lines = lines } end,
}
package.loaded["RadioSurvivor/RS_Actions"] = {
    decide = function(sheet, mode, actions, now, ctx)
        -- [place <id>] sections of the sheet (E20-T03): at=x,y,z and label=.
        local wanted = actions[1] and actions[1].place
        local places, current = {}, nil
        for _, line in ipairs(sheet.lines) do
            local id = string.match(line, "^%[place (%S+)%]$")
            if id then current = {}; places[id] = current end
            local x, y = string.match(line, "^at=(%d+),(%d+),%d+$")
            if x and current then current.x, current.y = tonumber(x), tonumber(y) end
            local label = string.match(line, "^label=(.*)$")
            if label and current then current.label = label end
        end
        local p = wanted and places[wanted]
        if p then
            DECISIONS[#DECISIONS + 1] = wanted
            sendServerCommand(ctx.player, "RSTMapDouble", "mark", { x = p.x, y = p.y, label = p.label })
            return { { reason = "ok" } }
        end
        return { { reason = "bad_params" } }
    end,
}
"""

# Client side: RS_MapActions.mark adds the icon and the label when they are missing (real rule: "present"
# otherwise); MapItem.getSingleton() is the map object of this session (a new one after a reconnection).
MAP_CLIENT = r"""
local MapActionsDouble = package.loaded["RadioSurvivor/RS_MapActions"]
MapActionsDouble.mark = function(x, y, label)
    for _, s in ipairs(SYMBOLS) do
        if s.x == math.floor(x) + 0.5 and s.y == math.floor(y) + 0.5 then return "present" end
    end
    marked(math.floor(x), math.floor(y), label)
    return "added"
end
MAP_ITEM_DOUBLE = setmetatable({}, { __tostring = function() return "MapItem@" .. tostring(MAP_SESSION) end })
MapItem = { getSingleton = function() return MAP_ITEM_DOUBLE end }
Events.OnServerCommand.Add(function(module, command, args)
    if module == "RSTMapDouble" and command == "mark" and not DROP_MARKS then
        MapActionsDouble.mark(args.x, args.y, args.label)
    end
end)
"""


class MapNetwork(StepsNetwork):
    """Dedicated server running RS_MapActions.lua and requester clients that own the map (RST_ViewSteps.lua)."""

    def __init__(self, root: Path):
        super().__init__(root)
        self.server.lua(MAP_SERVER)
        self.server.lua(f'dofile([[{SUITE_FILE.as_posix()}]])')
        self.sessions = 0

    def add_client(self, name, role='admin', handlers=True, symbols=None):
        self.sessions += 1
        c = Machine(self.root / f'{name}-{self.sessions}', VIEW_GAME, [STEPS_FILE, VIEW_FILE])
        c.lua(f'PLAYER.name = "{name}"; MAP_SESSION = {self.sessions}; '
              'sendClientCommand = function(p, m, cmd, a) PY_CLIENT_SEND(p.name, m, cmd, a) end')
        c.lua(MAP_CLIENT)
        for s in symbols or []:
            c.lua('SYMBOLS[#SYMBOLS + 1] = ' + lua_table(s))
        c.g.PY_CLIENT_SEND = lambda user, m, cmd, a: self.queue.append(('to_server', user, m, cmd, to_py(a)))
        self.server.lua(f'login("{name}", "{role}")')
        self.clients[name] = c
        return c

    def symbols(self, name):
        table = to_py(self.clients[name].lua('return SYMBOLS')) or {}
        return [table[i] for i in sorted(table)]

    def reconnect(self, name, symbols):
        """The client quits (its map saved to map_symbols.bin) and joins again in a new process, symbols read back."""
        self.server.lua(f'logout("{name}")')
        del self.clients[name]
        return self.add_client(name, symbols=symbols)


def lua_table(d):
    parts = []
    for k, v in d.items():
        parts.append(f'{k} = ' + (f'"{v}"' if isinstance(v, str) else repr(v)))
    return '{ ' + ', '.join(parts) + ' }'


def outcome(report):
    return [(r.status, r.message) for _, r in report.results.items()]


class MapMarkReconnectTests(unittest.TestCase):
    """rs.actions.map.before then .after-reconnect: the mark of the requester survives its reconnection, once."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.net = MapNetwork(Path(self.tmp.name))
        self.net.add_client('alice')

    def tearDown(self):
        self.tmp.cleanup()

    def run_named(self, name):
        return outcome(self.net.run(f'{{ suite = "{name}" }}'))

    def before(self):
        self.assertEqual(self.run_named('rs.actions.map.before'), [('PASS', None)])
        return self.net.symbols('alice')

    def test_before_marks_the_requester_map_through_the_executor(self):
        symbols = self.before()
        self.assertEqual(self.net.server.lua('return DECISIONS[1]'), 'rstest_spot')
        self.assertEqual(sorted((s['kind'], s['x'], s['y']) for s in symbols),
                         [('icon', 10612.5, 9318.5), ('text', 10612.5, 9318.5)])
        self.assertTrue(self.net.server.lua('return (RST.Persist.read("map-mark-persist.txt", "RSMAPMARK1")) ~= nil'))

    def test_mark_kept_after_the_reconnection_then_removed(self):
        symbols = self.before()
        client = self.net.reconnect('alice', symbols)
        self.assertEqual(self.run_named('rs.actions.map.after-reconnect'), [('PASS', None)])
        self.assertEqual(client.lua('return #SYMBOLS'), 0)   # removed at the end of the check
        self.assertIn('already used', self.net.server.lua(
            'return select(2, RST.Persist.read("map-mark-persist.txt", "RSMAPMARK1"))'))

    def test_mark_lost_by_the_reconnection_fails(self):
        self.before()
        self.net.reconnect('alice', [])
        (status, message), = self.run_named('rs.actions.map.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('0 icon(s) Target and 0 text(s) at 10612,9318', message)

    def test_mark_doubled_by_the_reconnection_fails(self):
        symbols = self.before()
        client = self.net.reconnect('alice', symbols + symbols)
        (status, message), = self.run_named('rs.actions.map.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('2 icon(s) Target and 2 text(s) at 10612,9318', message)
        self.assertEqual(client.lua('return #SYMBOLS'), 0)   # removed all the same

    def test_same_map_session_fails(self):
        symbols = self.before()
        client = self.net.reconnect('alice', symbols)
        client.lua('MAP_SESSION = 1')   # the client never really left: same MapItem as the before step
        (status, message), = self.run_named('rs.actions.map.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('same MapItem', message)

    def test_mark_not_drawn_by_the_requester_fails_the_before_step(self):
        self.net.clients['alice'].lua('DROP_MARKS = true')   # mark command lost: nothing drawn
        (status, message), = self.run_named('rs.actions.map.before')
        self.assertEqual(status, 'FAIL')
        self.assertIn('0 icon(s) Target', message)
        self.assertIsNone(self.net.server.lua('return (RST.Persist.read("map-mark-persist.txt", "RSMAPMARK1"))'))

    def test_without_the_before_step_fails(self):
        (status, message), = self.run_named('rs.actions.map.after-reconnect')
        self.assertEqual(status, 'FAIL')
        self.assertIn('run the .before suite first', message)

    def test_solo_after_reconnect_is_an_explicit_skip(self):
        s = self.net.server
        s.lua('isServer = function() return false end; isClient = function() return false end; REPORT = nil; '
              'assert(RST.start({ suite = "rs.actions.map.after-reconnect" }, { attach = false, '
              'onDone = function(r) REPORT = r end }))')
        for _ in range(50):
            if not s.lua('return RST.step()'):
                break
        (status, message), = outcome(s.g.REPORT)
        self.assertEqual(status, 'SKIP')
        self.assertIn('phased MP run only', message)


if __name__ == '__main__':
    unittest.main()
