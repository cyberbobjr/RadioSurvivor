"""Link with the Python bridge in the core mod batman_RadioSurvivorCore (E18-T04).

    python RadioSurvivor/tests/test_core_bridge.py

Decision of 2026-11-05 (plan E18): ONE exchange queue for both mods, separate caps (each mod counts its own requests).
- one copy of the transport (RC_Transport: requests and responses files) and of the bridge heartbeat (RC_Bridge),
  in the core mod; no RadioSurvivor/RS_Transport left;
- a mod registers its kinds of requests as lanes of the queue (RadioSurvivor: radio, npc, acks, lastPages, in this
  order, RS_BridgeLanes); the requests file of the moved code is byte for byte the file of the old code
  (fixtures/e18-t04/requests.txt, written by the old RS_Transport from fixtures/e18-t04/requests.lua);
- a lane of another mod goes in the same file, after the lanes registered before it, and is read back by the bridge;
- answers of every lane are read by one reader (RC_Transport.readResponses);
- heartbeat: RadioSurvivor_Const reads the state of the bridge through the core (same file, same delays).
"""
from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bridge'))
import npc_protocol  # noqa: E402
import radio_bridge  # noqa: E402

MODS = ROOT / 'Contents' / 'mods'
CORE_LUA = MODS / 'batman_RadioSurvivorCore' / '42.21' / 'media' / 'lua'
RS_LUA = MODS / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
FIX = Path(__file__).resolve().parent / 'fixtures' / 'e18-t04'
REQUESTS = 'batman_RadioSurvivorCore/requests.txt'
RESPONSES = 'batman_RadioSurvivorCore/responses.txt'

STUBS = r'''
isClient = function() return false end
isServer = function() return true end
NOW = 1790000000000
getTimestampMs = function() return NOW end
FILES = {}
getFileWriter = function(name) local buf = {} return { write = function(_, t) buf[#buf + 1] = t end,
    close = function() FILES[name] = table.concat(buf) end } end
getFileReader = function(name)
    local text = FILES[name]
    if text == nil then return nil end
    local lines, i = {}, 0
    for l in string.gmatch(text, "([^\n]*)\n") do lines[#lines + 1] = l end
    return { readLine = function() i = i + 1 return lines[i] end, close = function() end }
end
'''


def runtime():
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    paths = [CORE_LUA / 'shared', RS_LUA / 'shared', RS_LUA / 'server']
    rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')
    rt.execute(STUBS)
    return rt


class LayoutTests(unittest.TestCase):
    def test_one_copy_in_the_core(self):
        for name in ('RC_Transport', 'RC_Bridge'):
            self.assertTrue((CORE_LUA / 'shared' / 'RadioSurvivorCore' / f'{name}.lua').is_file(), name)
        self.assertEqual(list(MODS.rglob('RS_Transport.lua')), [])

    def test_no_require_of_the_old_transport(self):
        old = re.compile(r'RadioSurvivor/RS_' + 'Transport')
        hits = []
        for top in ('Contents', 'dev', 'tests', 'tools'):
            for path in (ROOT / top).rglob('*'):
                if (path.suffix in ('.lua', '.py') and path.is_file() and 'runs' not in path.parts
                        and path.resolve() != Path(__file__).resolve()):
                    if old.search(path.read_text(encoding='utf-8', errors='replace')):
                        hits.append(str(path.relative_to(ROOT)))
        self.assertEqual(hits, [])


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        # Lanes npc and acks: registered by LK_Talk (E18-T17), same orders (tests/test_lk_talk.py).
        self.T = self.rt.eval('(function() local T = require("RadioSurvivor/RS_BridgeLanes"); T.register("npc", {order = 20}); T.register("acks", {order = 30}); return T end)()')
        self.rt.globals().TRANSPORT = self.T

    def test_requests_file_byte_for_byte_as_the_old_code(self):
        self.rt.execute((FIX / 'requests.lua').read_text(encoding='utf-8'))
        written = self.rt.eval(f'FILES["{REQUESTS}"]')
        self.assertEqual(written.encode('utf-8'), (FIX / 'requests.txt').read_bytes())

    def test_lanes_of_radiosurvivor_in_order(self):
        self.assertEqual([self.T.order[i] for i in range(1, len(self.T.order) + 1)],
                         ['radio', 'npc', 'acks', 'lastPages'])

    def test_a_lane_of_another_mod_shares_the_file(self):
        self.rt.execute('local T = TRANSPORT; T.register("lkTalk", { order = 50 }); '
                        'T.npc = { { version = 2, kind = "npc_talk", id = "rs-1", npc = "npc-1", text = "a" } }; '
                        'T.lkTalk = { { version = 2, kind = "npc_talk", id = "lk-1", npc = "lk-7", text = "b" } }; '
                        'T.session = "s"; assert(T.write())')
        text = self.rt.eval(f'FILES["{REQUESTS}"]')
        ids = re.findall(r'^req=(.*)$', text, re.M)
        self.assertEqual(ids, ['rs-1', 'lk-1'])
        session, requests = radio_bridge.parse_requests(text)   # the real reader of the bridge
        self.assertEqual((session, [r['id'] for r in requests]), ('s', ['rs-1', 'lk-1']))
        self.assertEqual(npc_protocol.decode(bytes.fromhex(requests[1]['payload']))['npc'], 'lk-7')
        # Registering again keeps the place and the requests of the lane.
        self.rt.execute('TRANSPORT.register("lkTalk", { order = 5 })')
        self.assertEqual(self.T.order[len(self.T.order)], 'lkTalk')

    def test_one_reader_for_the_answers_of_every_lane(self):
        codec = self.rt.eval('require("RadioSurvivorCore/RC_Codec")')
        lines = []
        for rid in ('rs-1', 'lk-1'):
            payload = self.rt.eval(f'function(c) return c.hexBytes(c.encodeBytes({{ id = "{rid}", text = "ok" }})) end')(codec)
            lines += [f'resp={rid}', f'payload={payload}']
        self.rt.globals().FILES[RESPONSES] = '\n'.join(lines + ['end']) + '\n'
        answers = self.rt.eval('TRANSPORT.readResponses()')
        self.assertEqual(sorted(answers.keys()), ['lk-1', 'rs-1'])
        self.rt.globals().FILES[RESPONSES] = 'resp=rs-1\n'   # incomplete file: nothing read
        self.assertIsNone(self.rt.eval('TRANSPORT.readResponses()'))


class HeartbeatTests(unittest.TestCase):
    def setUp(self):
        self.rt = runtime()
        self.B = self.rt.eval('require("RadioSurvivorCore/RC_Bridge")')
        self.C = self.rt.eval('require("RadioSurvivor/RadioSurvivor_Const")')

    def test_constants_read_from_the_core(self):
        for k in ('REQUESTS_FILE', 'RESPONSES_FILE', 'BRIDGE_ALIVE_FILE', 'BRIDGE_TIMEOUT_MS', 'NO_BRIDGE_TIMEOUT_MS',
                  'ALIVE_STALE_MS', 'ALIVE_READ_MS', 'BRIDGE_REPLY_MS'):
            self.assertEqual(self.C[k], self.B[k], k)
        self.assertEqual(self.B.REQUESTS_FILE, REQUESTS)

    def test_alive_and_wait_follow_the_heartbeat(self):
        self.assertFalse(self.rt.eval('require("RadioSurvivorCore/RC_Bridge").alive(nil, true)'))
        self.assertEqual(self.C.waitMs(90000), 90000)
        self.rt.globals().FILES[self.B.BRIDGE_ALIVE_FILE] = 'alive=1790000000000\n'
        self.assertTrue(self.B.alive(None, True))
        self.assertTrue(self.C.bridgeAlive(None, True))
        self.assertEqual(self.C.waitMs(90000), self.B.BRIDGE_TIMEOUT_MS)
        self.rt.globals().NOW = 1790000000000 + self.B.ALIVE_STALE_MS + 1000
        self.assertFalse(self.C.bridgeAlive(None, True))
        self.C.refreshTimeout()
        self.assertEqual(self.C.TIMEOUT_MS, self.B.NO_BRIDGE_TIMEOUT_MS)


class ExchangeFolderTests(unittest.TestCase):
    """E18-T12: one exchange folder, of the core mod, for every mounting; the voices stay with RadioSurvivor."""

    def test_default_folder_and_voice_sheets(self):
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
        import radio_bridge as rb
        self.assertEqual(rb.DEFAULT_EXCHANGE.name, 'batman_RadioSurvivorCore')
        lua = Path('Zomboid') / 'Lua'
        self.assertEqual(rb.personas_folder(lua / 'batman_RadioSurvivorCore'), lua / 'batman_RadioSurvivor' / 'personas')
        self.assertEqual(rb.personas_folder(Path('other')), Path('other') / 'personas')

    def test_nothing_is_created_for_a_mod_that_is_absent(self):
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
        import radio_bridge as rb
        with tempfile.TemporaryDirectory() as tmp:
            exchange = Path(tmp) / 'Lua' / 'batman_RadioSurvivorCore'
            exchange.mkdir(parents=True)
            rb.Bridge({'OFFLINE': '1', 'OPENAI_MODEL': 'offline'}, exchange)
            self.assertFalse((Path(tmp) / 'Lua' / 'batman_RadioSurvivor').exists())


if __name__ == '__main__':
    unittest.main()
