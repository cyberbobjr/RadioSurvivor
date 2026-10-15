"""Banc hors jeu des étapes nommées serveur <-> clients (E01-T16) : RST_Steps.lua et RST_PeerChecks.lua ; étapes
de vue du client demandeur (RST_ViewSteps.lua) et groupe de test Living Knox (RST_LKGroupFixture.lua), E01-T19.

    python RadioSurvivor/tests/test_rst_steps.py

Un serveur dédié et deux ou trois clients, chacun dans sa machine lupa (doublures de test_rst.py : réseau en file,
tables copiées comme TableNetworkUtils, commandes non ordonnées seulement par la file) ; un passage RST asynchrone sur
le serveur pose des étapes, les clients y répondent à leurs ticks. Solo : une seule machine, même chemin sans réseau.
Ne prouve rien sur le Java du jeu (paquets réels, rôles, /setaccesslevel) : la campagne MP réelle reste nécessaire.
"""
from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rst import CLIENT_GAME, LUA, SERVER_GAME, Machine, to_py  # noqa: E402

STEPS_FILE = LUA / 'shared' / 'RST' / 'RST_Steps.lua'
PEER_FILE = LUA / 'shared' / 'RST' / 'RST_PeerChecks.lua'

# Server suites asking steps (t.ctx.player = requester alice).
SERVER_SUITES = r"""
RST.suite("x.steps", { tags = { "server" } }, function(s)
    s.test("echo others", function(t)
        RST.Steps.ask(t, "echo", { v = 3, list = { "a", "b" } }, { timeoutMs = 2000 }, function(t2, res)
            RESULT = res
            t2:eq(3, res.by.bob.data.v, "data of bob")
        end)
    end)
end)
RST.suite("x.requester", { tags = { "server" } }, function(s)
    s.test("echo requester", function(t)
        RST.Steps.ask(t, "echo", { v = 5 }, { target = "requester", timeoutMs = 2000 }, function(t2, res)
            RESULT = res
            t2:eq(5, res.by.alice.data.v, "data of alice")
        end)
    end)
end)
RST.suite("x.poll", { tags = { "server" } }, function(s)
    s.test("slow answer", function(t)
        RST.Steps.ask(t, "slow", { after = 3 }, { timeoutMs = 5000 }, function(t2, res) RESULT = res end)
    end)
    s.test("never ready", function(t)
        RST.Steps.ask(t, "never", {}, { timeoutMs = 1000 })
    end)
end)
RST.suite("x.other", { tags = { "server" } }, function(s)
    s.test("unknown step", function(t) RST.Steps.ask(t, "nope", {}, { timeoutMs = 1000 }) end)
    s.test("skip noted", function(t) RST.Steps.ask(t, "skipme", {}, { timeoutMs = 1000 }) end)
    s.test("assert off", function(t)
        RST.Steps.ask(t, "failing", {}, { timeoutMs = 1000, assert = false }, function(t2, res)
            t2:eq("FAIL", res.by.bob.status, "status read by the suite")
        end)
    end)
end)
"""

CLIENT_HANDLERS = r"""
RST.Steps.on("echo", function(args) return RST.Steps.pass("echo " .. tostring(args.v), { v = args.v,
    n = #(args.list or {}) }) end)
RST.Steps.on("slow", function(args)
    local calls = 0
    return function(ctx)
        calls = calls + 1
        if calls >= args.after then return RST.Steps.pass("after " .. calls .. " call(s)") end
        return nil
    end
end)
RST.Steps.on("never", function()
    return function(ctx)
        if ctx.final then return RST.Steps.fail("still nothing at the deadline") end
        return nil
    end
end)
RST.Steps.on("skipme", function() return RST.Steps.skip("square not loaded here") end)
RST.Steps.on("failing", function() return RST.Steps.fail("wrong") end)
"""

CLIENT_EXTRA = r"""
getPlayer = function() return PLAYER end
"""


class StepsNetwork:
    """A dedicated server and clients; commands queued and copied as the network does."""

    def __init__(self, root: Path):
        self.root = root
        self.queue = []
        self.server = Machine(root / 'server', SERVER_GAME, [STEPS_FILE, SERVER_SUITES])
        self.server.g.PY_SERVER_SEND = lambda user, m, c, a: self.queue.append(('to_client', user, m, c, to_py(a)))
        self.clients = {}
        self.clock = 1000
        self.mute = set()   # clients whose commands are lost

    def add_client(self, name, role='admin', handlers=True):
        c = Machine(self.root / name, CLIENT_GAME + CLIENT_EXTRA, [STEPS_FILE])
        c.lua(f'PLAYER = {{ name = "{name}" }}; function PLAYER:getUsername() return self.name end')
        if handlers:
            c.lua(CLIENT_HANDLERS)
        c.g.PY_CLIENT_SEND = lambda user, m, cmd, a: (None if user in self.mute else
                                                      self.queue.append(('to_server', user, m, cmd, to_py(a))))
        self.server.lua(f'login("{name}", "{role}")')
        self.clients[name] = c
        return c

    def pump(self):
        while self.queue:
            kind, user, module, command, args = self.queue.pop(0)
            if kind == 'to_server':
                if self.server.lua(f'return CONNECTIONS["{user}"] ~= nil'):
                    player = self.server.lua(f'return PLAYERS["{user}"]')
                    self.server.g.Events.OnClientCommand.fire(module, command, player, self.server.table(args))
            elif user in self.clients:
                c = self.clients[user]
                c.g.Events.OnServerCommand.fire(module, command, c.table(args))

    def tick(self, dt=100):
        self.pump()
        for m in [self.server, *self.clients.values()]:
            m.g.CLOCK = self.clock
        self.server.g.Events.OnTickEvenPaused.fire()
        for c in self.clients.values():
            c.g.Events.OnTick.fire()
        self.clock += dt
        self.pump()

    def run(self, flt, requester='alice', limit=400):
        s = self.server
        s.lua(f'REPORT = nil; RESULT = nil; assert(RST.start({flt}, {{ ctx = {{ side = "server", '
              f'player = PLAYERS["{requester}"] }}, onDone = function(r) REPORT = r end }}))')
        for _ in range(limit):
            if not s.lua('return RST.running()'):
                return s.g.REPORT
            self.tick()
        raise AssertionError('server run not over')


def results(report):
    return {r.test: (r.status, r.message) for _, r in report.results.items()}


def notes(report, test):
    for _, r in report.results.items():
        if r.test == test and r.notes:
            return [n for _, n in r.notes.items()]
    return []


class StepsTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.net = StepsNetwork(Path(self.tmp.name))
        self.alice = self.net.add_client('alice')
        self.bob = self.net.add_client('bob', 'user')

    def tearDown(self):
        self.tmp.cleanup()

    def test_others_answer_and_requester_is_not_asked(self):
        rep = self.net.run('"x.steps"')
        self.assertEqual(results(rep)['echo others'], ('PASS', None))
        res = self.net.server.g.RESULT
        self.assertEqual([e.user for _, e in res.list.items()], ['bob'])
        self.assertEqual(res.by.bob.data.n, 2)  # nested table copied through the network
        self.assertEqual(self.alice.lua('return #RST.Steps.records'), 0)
        self.assertEqual(self.bob.lua('return RST.Steps.records[1].status .. " " .. RST.Steps.records[1].step'),
                         'PASS echo')
        self.assertIn('client bob: echo: echo 3', notes(rep, 'echo others'))
        files = sorted((self.net.root / 'bob' / 'batman_RadioSurvivor' / 'tests').glob('*-steps.txt'))
        self.assertEqual(len(files), 1)
        text = files[0].read_text(encoding='utf-8').splitlines()
        self.assertEqual(text[0], 'RST steps answered by bob (client)')
        self.assertRegex(text[1], r'^PASS  echo #1 \(\d+ ms\) echo 3$')
        self.assertEqual(text[-1], 'OK - 1 step(s): 1 pass, 0 fail, 0 error, 0 skip')

    def test_requester_target(self):
        rep = self.net.run('"x.requester"')
        self.assertEqual(results(rep)['echo requester'], ('PASS', None))
        self.assertEqual(self.bob.lua('return #RST.Steps.records'), 0)
        self.assertEqual(self.alice.lua('return #RST.Steps.records'), 1)

    def test_missed_step_fails_with_the_client_and_the_step(self):
        self.net.mute.add('bob')
        rep = self.net.run('"x.steps"')
        status, msg = results(rep)['echo others']
        self.assertEqual(status, 'FAIL')
        self.assertTrue(msg.startswith("client bob missed step 'echo' within 2000 ms"), msg)

    def test_poll_until_ready_and_final_diagnostic(self):
        rep = self.net.run('"x.poll"')
        r = results(rep)
        self.assertEqual(r['slow answer'], ('PASS', None))
        self.assertEqual(r['never ready'][0], 'FAIL')
        self.assertTrue(r['never ready'][1].startswith("client bob: step 'never' FAIL: still nothing at the deadline"))
        # the OnTick listener of the polls is removed once no handler polls any more
        self.net.tick()
        self.assertEqual(self.bob.lua('return #Events.OnTick.handlers'), 0)

    def test_unknown_step_skip_and_assert_off(self):
        rep = self.net.run('"x.other"')
        r = results(rep)
        self.assertEqual(r['unknown step'][0], 'FAIL')
        self.assertIn("step 'nope' ERROR: unknown step 'nope' on this client", r['unknown step'][1])
        self.assertEqual(r['skip noted'], ('PASS', None))
        self.assertIn("client bob: step 'skipme' skipped: square not loaded here", notes(rep, 'skip noted'))
        self.assertEqual(r['assert off'], ('PASS', None))
        self.assertEqual(self.bob.lua('local s = RST.Steps.summary() return s.total .. s.pass .. s.fail .. s.error '
                                      '.. s.skip .. tostring(s.ok)'), '30111false')

    def test_answer_from_an_account_not_asked_is_ignored(self):
        carol = self.net.add_client('carol')
        self.net.server.lua('RST.suite("x.forge", { tags = { "server" } }, function(s) s.test("forged", function(t) '
                            'RST.Steps.ask(t, "echo", { v = 1, list = {} }, { target = { "bob" }, timeoutMs = 1000 }) '
                            'end) end)')
        self.net.mute.add('bob')
        s = self.net.server
        s.lua('assert(RST.start("x.forge", { ctx = { side = "server", player = PLAYERS["alice"] }, '
              'onDone = function(r) REPORT = r end }))')
        self.net.pump()
        carol.lua('sendClientCommand(PLAYER, "RSTStep", "answer", { seq = RST_SEQ or 1, step = "echo", '
                  'status = "PASS" })')
        for _ in range(60):
            if not s.lua('return RST.running()'):
                break
            self.net.tick()
        self.assertEqual(results(s.g.REPORT)['forged'][0], 'FAIL')
        self.assertTrue(s.lua('return logged("answer of carol to step echo #1 ignored")'))

    def test_no_other_client_notes_and_goes_on(self):
        self.net.server.lua('logout("bob")')
        rep = self.net.run('"x.steps"')
        status, msg = results(rep)['echo others']
        self.assertEqual(status, 'ERROR')   # after() reads res.by.bob (absent): the suite decides what it needs
        self.assertIn("no others client online: step 'echo' not checked", notes(rep, 'echo others'))


SOLO_GAME = r"""
isServer = function() return false end
isClient = function() return false end
PLAYER = { name = "" }
function PLAYER:getUsername() return self.name end
getPlayer = function() return PLAYER end
"""


SOLO_SUITES = r"""
RST.suite("y.solo", { tags = { "server" } }, function(s)
    s.test("slow requester", function(t)
        RST.Steps.ask(t, "slow", { after = 3 }, { target = "requester", timeoutMs = 5000 }, function(t2, res)
            t2:eq("PASS", res.by["local"].status, "answer of the local player")
        end)
    end)
    s.test("never requester", function(t)
        RST.Steps.ask(t, "never", {}, { target = "requester", timeoutMs = 1000 })
    end)
    s.test("others: nobody in solo", function(t)
        RST.Steps.ask(t, "echo", {}, {}, function(t2, res) t2:eq(true, res.none, "no target") end)
    end)
    s.test("others required", function(t)
        RST.Steps.ask(t, "echo", {}, { none = "skip" })
    end)
end)
"""


class SoloTests(unittest.TestCase):

    def test_solo_runs_the_handler_locally_with_the_same_polling(self):
        with tempfile.TemporaryDirectory() as tmp:
            m = Machine(Path(tmp) / 'solo', SOLO_GAME, [STEPS_FILE, CLIENT_HANDLERS, SOLO_SUITES])
            m.lua('assert(RST.start("y.solo", { ctx = { side = "solo" }, onDone = function(r) REPORT = r end }))')
            for _ in range(200):
                if not m.lua('return RST.running()'):
                    break
                m.g.CLOCK = m.g.CLOCK + 100
                m.g.Events.OnTick.fire()
            r = results(m.g.REPORT)
            self.assertEqual(r['slow requester'], ('PASS', None))
            self.assertEqual(r['never requester'][0], 'FAIL')
            self.assertTrue(r['never requester'][1].startswith("client local: step 'never' FAIL: still nothing"))
            self.assertEqual(r['others: nobody in solo'], ('PASS', None))
            self.assertIn("no others client online: step 'echo' not checked", notes(m.g.REPORT,
                                                                                  'others: nobody in solo'))
            self.assertEqual(r['others required'][0], 'SKIP')
            self.assertEqual(m.lua('return #RST.Steps.records'), 2)
            files = sorted((Path(tmp) / 'solo' / 'batman_RadioSurvivor' / 'tests').glob('*-steps.txt'))
            self.assertEqual(files[0].read_text(encoding='utf-8').splitlines()[0],
                             'RST steps answered by local (solo)')


PEER_GAME = r"""
isServer = function() return false end
isClient = function() return true end
PLAYER = { name = "rs_mp1" }
function PLAYER:getUsername() return self.name end
getPlayer = function() return PLAYER end
SENT, COMMANDS = {}, {}
sendClientCommand = function(p, module, command, args) SENT[#SENT + 1] = { module = module, command = command,
    args = args } end
SendCommandToServer = function(text) COMMANDS[#COMMANDS + 1] = text end
local function list(items) return { size = function() return #items end, get = function(_, i) return items[i + 1] end } end
function item(ft) return { getFullType = function() return ft end } end
function container(items) return { getItems = function() return list(items) end } end
"""


class PeerCheckTests(unittest.TestCase):
    """Handlers of RST_PeerChecks.lua that need no world: access level, tool request, items key."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = Machine(Path(self.tmp.name) / 'c', PEER_GAME, [STEPS_FILE, PEER_FILE])

    def tearDown(self):
        self.tmp.cleanup()

    def start(self, step, args):
        self.m.lua(f'ANSWER = nil; RST.Steps.start(1, "{step}", {args}, 1000, function(r) ANSWER = r end)')
        return self.m.g.ANSWER

    def test_items_key_sorted_with_counts(self):
        key = self.m.lua('return RST.PeerChecks.itemsKey(container({ item("Base.B"), item("Base.A"), '
                         'item("Base.B") }))')
        self.assertEqual(key, 'Base.A,Base.B*2')
        self.assertEqual(self.m.lua('return RST.PeerChecks.itemsKey(nil)'), '')

    def test_access_level_only_for_test_accounts_and_never_itself(self):
        a = self.start('rst.access', '{ user = "rs_mp2", level = "user" }')
        self.assertEqual(a.status, 'PASS')
        self.assertEqual(self.m.lua('return COMMANDS[1]'), '/setaccesslevel rs_mp2 user')
        for args, why in (('{ user = "bob", level = "user" }', 'not a test account'),
                          ('{ user = "rs_mp2", level = "admin;quit" }', "level 'admin;quit'"),
                          ('{ user = "rs_mp1", level = "user" }', 'never changes its own level')):
            a = self.start('rst.access', args)
            self.assertEqual(a.status, 'FAIL', args)
            self.assertIn(why, a.message)
        self.assertEqual(self.m.lua('return #COMMANDS'), 1)

    def test_request_of_a_tool_returns_its_reply_by_number(self):
        a = self.start('rst.request', '{ module = "LivingKnox", command = "adminRequest", '
                                      'args = { op = "list", n = 701 } }')
        self.assertIsNone(a)   # waits for the reply
        self.assertEqual(self.m.lua('return SENT[1].module .. "/" .. SENT[1].command .. "/" .. SENT[1].args.n'),
                         'LivingKnox/adminRequest/701')
        self.m.lua('Events.OnServerCommand.fire("LivingKnox", "adminReply", { n = 700, ok = true })')  # another one
        self.m.lua('RST.Steps.tick()')
        self.assertIsNone(self.m.g.ANSWER)
        self.m.lua('Events.OnServerCommand.fire("LivingKnox", "adminReply", { n = 701, op = "list", ok = false, '
                   'err = "denied" })')
        self.m.lua('RST.Steps.tick()')
        a = self.m.g.ANSWER
        self.assertEqual(a.status, 'PASS')
        self.assertEqual((a.data.ok, a.data.err, a.data.n), (False, 'denied', 701))
        a = self.start('rst.request', '{ module = "RadioSurvivor", command = "talk", args = { n = 1 } }')
        self.assertEqual(a.status, 'FAIL')

    ZOMBIES = r'''
ZOMBIES = {}
local function colour(r, g, b)
    return { getRedInt = function() return r end, getGreenInt = function() return g end,
        getBlueInt = function() return b end }
end
-- Copy of a body: random look of a new IsoZombie until dressInPersistentOutfitID (shared descriptor) is applied.
function COPY(online, outfit)
    local z = { online = online, outfit = outfit, init = false, look = { "M_ZedBody01_level1", "Spike", "", 1, 2, 3 } }
    function z:getOnlineID() return self.online end
    function z:getPersistentOutfitID() return self.outfit end
    function z:isDead() return false end
    function z:isReanimatedPlayer() return true end
    function z:getSharedDescriptor() return self.init and {} or nil end
    function z:isPersistentOutfitInit() return self.init end
    function z:dressInPersistentOutfitID(id)
        DRESSED = (DRESSED or 0) + 1
        self.init, self.look = true, { "MaleBody01", "Short", "Full", 111, 87, 60 }
    end
    function z:getHumanVisual()
        local l = self.look
        return { getSkinTexture = function() return l[1] end, getHairModel = function() return l[2] end,
            getBeardModel = function() return l[3] end, getHairColor = function() return colour(l[4], l[5], l[6]) end }
    end
    ZOMBIES[#ZOMBIES + 1] = z
    return z
end
getCell = function()
    return { getZombieList = function() return { size = function() return #ZOMBIES end,
        get = function(_, i) return ZOMBIES[i + 1] end } end }
end
'''

    def test_present_waits_for_the_copy_of_each_body(self):
        self.m.lua(self.ZOMBIES)
        self.assertIsNone(self.start('lk.present', '{ bodies = { { o = 7, p = 39911425 } } }'))
        self.m.lua('COPY(7, 39911425); RST.Steps.tick()')
        a = self.m.g.ANSWER
        self.assertEqual(a.status, 'PASS')
        self.assertIn('1 body(ies) present', a.message)

    def test_look_dresses_a_copy_not_drawn_yet_as_the_renderer_does(self):
        self.m.lua(self.ZOMBIES)
        self.m.lua('COPY(7, 39911425)')
        a = self.start('lk.look', '{ bodies = { { o = 7, p = 39911425, sig = "MaleBody01 Short Full 111,87,60 " } } }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertIn('1 not drawn yet here', a.message)
        self.assertEqual(self.m.g.DRESSED, 1)
        # Already dressed (drawn): compared as it is, never dressed again.
        a = self.start('lk.look', '{ bodies = { { o = 7, p = 39911425, sig = "MaleBody01 Short Full 111,87,60 " } } }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertNotIn('not drawn', a.message)
        self.assertEqual(self.m.g.DRESSED, 1)

    def test_no_next_no_goto_no_suspension_in_sources(self):
        for path in (STEPS_FILE, PEER_FILE):
            code = re.sub(r'--\[\[.*?\]\]', '', path.read_text(encoding='utf-8'), flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code), path.name)
            self.assertIsNone(re.search(r'\bgoto\b|coroutine', code), path.name)
            self.assertTrue(all(ord(ch) < 128 for ch in code), path.name)


# ---------------------------------------------------------------------------------------------------- E01-T19

VIEW_FILE = LUA / 'shared' / 'RST' / 'RST_ViewSteps.lua'
GROUP_FILE = LUA / 'shared' / 'RST' / 'RST_LKGroupFixture.lua'

# Client of an MP game (requester): world map, radio history, npc bodies and views as doubles of the shape the
# handlers read (WorldMapVisited.isKnown / clearKnownInSquares, RS_MapActions symbols API, RS_RadioHistory.lines).
VIEW_GAME = PEER_GAME + r"""
local function event()
    local e = { handlers = {} }
    e.Add = function(f) e.handlers[#e.handlers + 1] = f end
    e.Remove = function(f) for i, h in ipairs(e.handlers) do if h == f then table.remove(e.handlers, i) return end end end
    e.fire = function(...) for _, h in ipairs(e.handlers) do h(...) end end
    return e
end
Events.OnEquipPrimary = event()
KNOWN, CLEARED = {}, {}
VISITED = {
    isKnown = function(self, x, y) return KNOWN[math.floor(x / 32) .. "," .. math.floor(y / 32)] == true end,
    clearKnownInSquares = function(self, x1, y1, x2, y2)
        CLEARED[#CLEARED + 1] = x1 .. "," .. y1 .. "," .. x2 .. "," .. y2
        KNOWN[math.floor(x1 / 32) .. "," .. math.floor(y1 / 32)] = nil
    end,
}
WorldMapVisited = { getInstance = function() return VISITED end }
SYMBOLS = {}   -- { x, y, kind = "icon" | "text", id, text }
local function symbol(s)
    return { getWorldX = function() return s.x end, getWorldY = function() return s.y end,
        isTexture = function() return s.kind == "icon" end, isText = function() return s.kind == "text" end,
        getSymbolID = function() return s.id end, getTranslatedText = function() return s.text end }
end
API = {
    getSymbolCount = function() return #SYMBOLS end,
    getSymbolByIndex = function(self, i) return symbol(SYMBOLS[i + 1]) end,
    removeSymbolByIndex = function(self, i) table.remove(SYMBOLS, i + 1) end,
}
package.loaded["RadioSurvivor/RS_MapActions"] = {
    ICON = "Target", EPSILON = 0.01,
    symbolsAPI = function() return API end,
    mark = function(x, y, label)
        for _, s in ipairs(SYMBOLS) do
            if s.x == math.floor(x) + 0.5 and s.y == math.floor(y) + 0.5 then return "present" end
        end
        return "added"
    end,
}
function marked(x, y, label)
    SYMBOLS[#SYMBOLS + 1] = { x = x + 0.5, y = y + 0.5, kind = "icon", id = "Target" }
    SYMBOLS[#SYMBOLS + 1] = { x = x + 0.5, y = y + 0.5, kind = "text", text = label }
end
CharacterTrait = { ILLITERATE = "illiterate" }
function PLAYER:hasTrait(t) return false end
HIST = {}
package.loaded["RadioSurvivor/RS_RadioHistory"] = { character = "c1",
    lines = function(khz) return HIST[khz] or {} end }
getText = function(key, a, b)
    if key == "IGUI_RS_Radio_mark" then return "[" .. tostring(a) .. "] Mark: " .. tostring(b) end
    if key == "IGUI_LK_Say_greet_1" then return "Hello there." end
    return key
end
BODY = { name = "body of lk-1" }
-- IsoGameCharacter.isLocal: true in solo and on the owner client of a zombie, false on the other MP clients.
function BODY:isLocal() return BODY_LOCAL ~= false end
SPEECH = { seen = {}, bubbles = {}, stats = { drawn = 0, shown = 1 }, lastDraw = nil }
function SPEECH.receive(e)
    if SPEECH.seen[e.id] then return false end
    SPEECH.stats.shown = SPEECH.stats.shown + 1
    return true
end
SKIPPED, ERRORS = 0, 0
LivingKnox = {
    Anim = { knownBodies = function() return { ["lk-1"] = BODY } end },
    Equipment = { stats = { skipped = 0 } },
    SpeechView = SPEECH,
    SpeechData = { KEY_PREFIX = "IGUI_LK_Say_" },
    CombatView = { stats = { shotsPlayed = 4, shotsDuplicate = 0, flashes = 4 } },
}
Fishing = { Handler = {} }
getLuaDebuggerErrorCount = function() return ERRORS end
getCore = function() return { getScreenWidth = function() return 1920 end,
    getScreenHeight = function() return 1080 end } end
"""


class ViewStepTests(unittest.TestCase):
    """Handlers of RST_ViewSteps.lua (E01-T19) run by the requester client of an MP game."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = Machine(Path(self.tmp.name) / 'c', VIEW_GAME, [STEPS_FILE, VIEW_FILE])
        self.m.g.CLOCK = 10000

    def tearDown(self):
        self.tmp.cleanup()

    def start(self, step, args, ms=1000):
        self.m.lua(f'ANSWER = nil; RST.Steps.start(1, "{step}", {args}, {ms}, function(r) ANSWER = r end)')
        return self.m.g.ANSWER

    def tick(self, dt=100):
        self.m.g.CLOCK = self.m.g.CLOCK + dt
        self.m.lua('RST.Steps.tick()')
        return self.m.g.ANSWER

    def test_map_known_reads_waits_and_clears(self):
        self.m.lua('KNOWN["10,20"] = true')
        a = self.start('map.known', '{ blocks = { { 10, 20 }, { 11, 20 } } }')
        self.assertEqual((a.status, a.data.known), ('PASS', '10'))
        self.assertIsNone(self.start('map.known', '{ blocks = { { 10, 20 }, { 11, 20 } }, expect = "11", '
                                                  'clear = { { 11, 20 } } }'))
        self.assertEqual(self.m.lua('return #CLEARED'), 0)       # nothing cleared while it waits
        self.m.lua('KNOWN["11,20"] = true')
        a = self.tick()
        self.assertEqual(a.status, 'PASS')
        self.assertEqual(self.m.lua('return CLEARED[1]'), '352,640,383,671')
        self.assertFalse(self.m.lua('return KNOWN["11,20"] == true'))
        # never as expected: FAIL at the deadline with what was read, blocks cleared all the same
        self.assertIsNone(self.start('map.known', '{ blocks = { { 10, 20 } }, expect = "0", clear = { { 10, 20 } } }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('known blocks 1, 0 expected', a.message)
        self.assertEqual(self.m.lua('return #CLEARED'), 2)

    def test_map_symbols_counts_label_second_mark_and_removes(self):
        self.m.lua('marked(100, 200, "RST map test")')
        a = self.start('map.symbols', '{ x = 100, y = 200, label = "RST map test", icons = 1, texts = 1, '
                                      'markAgain = true, remove = true }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertIn('second mark: present', a.message)
        self.assertEqual(self.m.lua('return #SYMBOLS'), 0)
        # wrong label: FAIL, symbols removed anyway
        self.m.lua('marked(100, 200, "other")')
        a = self.start('map.symbols', '{ x = 100, y = 200, label = "RST map test", icons = 1, texts = 1, '
                                      'remove = true }')
        self.assertEqual(a.status, 'FAIL')
        self.assertIn("label 'other'", a.message)
        self.assertEqual(self.m.lua('return #SYMBOLS'), 0)
        # nothing expected: waits settleMs before the PASS, FAIL at the deadline if a symbol is there
        self.assertIsNone(self.start('map.symbols', '{ x = 5, y = 5, icons = 0, texts = 0, settleMs = 500 }'))
        self.assertEqual(self.tick(600).status, 'PASS')
        self.m.lua('marked(5, 5, "x")')
        self.assertIsNone(self.start('map.symbols', '{ x = 5, y = 5, icons = 0, texts = 0, remove = true }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('1 icon(s) Target and 1 text(s) at 5,5', a.message)

    def test_radio_history_line_once_translated_without_coordinates(self):
        args = ('{ khz = 199800, other = 200000, kind = "mark", label = "RST map test", cid = "c1", x = 10612, '
                'key = "IGUI_RS_Radio_mark" }')
        self.assertIsNone(self.start('radio.history', args))
        self.m.lua('HIST[199800] = { { kind = "mark", text = "RST map test", when = "D1 08:00" } }')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertIn('Mark: RST map test', a.message)
        self.m.lua('HIST[200000] = { { kind = "mark", text = "RST map test", when = "D1 08:00" } }')
        a = self.start('radio.history', args)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('another frequency', a.message)
        self.m.lua('HIST[200000] = nil; HIST[199800][1].text = "RST map test"; '
                   'package.loaded["RadioSurvivor/RS_RadioHistory"].character = "c2"')
        self.assertIsNone(self.start('radio.history', args))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('character of the client history c2, c1 expected', a.message)

    def test_weapon_count_events_fishing_and_errors(self):
        self.assertEqual(self.start('lk.weapon.count', '{ npc = "lk-1", phase = "begin", key = "k1" }').status,
                         'PASS')
        self.m.lua('Events.OnEquipPrimary.fire(BODY); Events.OnEquipPrimary.fire({}); '
                   'Events.OnEquipPrimary.fire(BODY); LivingKnox.Equipment.stats.skipped = 2')
        a = self.start('lk.weapon.count', '{ npc = "lk-1", phase = "end", key = "k1" }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual((a.data.events, a.data.skipped, a.data.errors), (2, 2, 0))
        self.assertEqual(self.m.lua('return #Events.OnEquipPrimary.handlers'), 0)
        # fishing calls not skipped, then a Lua error during the cases
        self.start('lk.weapon.count', '{ npc = "lk-1", phase = "begin", key = "k2" }')
        self.m.lua('Events.OnEquipPrimary.fire(BODY)')
        a = self.start('lk.weapon.count', '{ npc = "lk-1", phase = "end", key = "k2" }')
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('fishing handler calls not skipped', a.message)
        self.m.lua('getLuaDebuggerErrors = function() return { size = function() return 1 end, '
                   'get = function() return "boom\\nstack" end } end')
        self.start('lk.weapon.count', '{ npc = "lk-1", phase = "begin", key = "k3" }')
        self.m.lua('Events.OnEquipPrimary.fire(BODY); LivingKnox.Equipment.stats.skipped = 3; ERRORS = 1')
        a = self.start('lk.weapon.count', '{ npc = "lk-1", phase = "end", key = "k3" }')
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('Lua errors while the npc took its weapons in hand', a.message)
        self.assertIn('(boom)', a.message)
        self.assertEqual(self.start('lk.weapon.count', '{ npc = "lk-1", phase = "end", key = "nope" }').status,
                         'FAIL')
        # MP 2026-10-15: on a client that does not own the body the vanilla handler never calls handleFishing
        # (onEquipPrimary: player:isLocal()), so nothing is skipped there.
        self.m.lua('ERRORS = 0; BODY_LOCAL = false')
        self.start('lk.weapon.count', '{ npc = "lk-1", phase = "begin", key = "k4" }')
        self.m.lua('Events.OnEquipPrimary.fire(BODY); Events.OnEquipPrimary.fire(BODY)')
        a = self.start('lk.weapon.count', '{ npc = "lk-1", phase = "end", key = "k4" }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual((a.data.events, a.data.localEvents, a.data.skipped), (2, 0, 0))
        self.m.lua('BODY_LOCAL = nil')
        # MP 2026-10-15 (7 calls skipped for 4 events of the npc): another npc body owned here equips too; its call
        # is skipped by the same guard and counted among the local non-players.
        self.start('lk.weapon.count', '{ npc = "lk-1", phase = "begin", key = "k5" }')
        self.m.lua('local other = { isLocal = function() return true end } '
                   'Events.OnEquipPrimary.fire(BODY); Events.OnEquipPrimary.fire(other); '
                   'LivingKnox.Equipment.stats.skipped = LivingKnox.Equipment.stats.skipped + 2')
        a = self.start('lk.weapon.count', '{ npc = "lk-1", phase = "end", key = "k5" }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual((a.data.events, a.data.localEvents, a.data.allLocal, a.data.skipped), (1, 1, 2, 2))

    def test_speech_bubble_translated_here_drawn_once_and_repeat_refused(self):
        self.assertIsNone(self.start('lk.speech.bubble', '{ npc = "lk-1", id = "s1", line = "greet_1", again = true }'))
        self.m.lua('SPEECH.seen.s1 = true; SPEECH.bubbles = { { z = BODY, text = "Hello there." } }')
        self.assertIsNone(self.tick())   # shown but not drawn yet
        self.m.lua('SPEECH.stats.drawn = 1; SPEECH.lastDraw = { npc = "lk-1", text = "Hello there.", x = 960, y = 400 }')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertIn("'Hello there.' drawn at 960,400; repeated delivery refused", a.message)
        # a second bubble of the same text, then a bubble drawn off screen
        self.m.lua('SPEECH.bubbles[2] = { z = BODY, text = "Hello there." }')
        self.assertIsNone(self.start('lk.speech.bubble', '{ npc = "lk-1", id = "s1", text = "Hello there." }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn("2 bubble(s) of the body", a.message)
        self.m.lua('SPEECH.bubbles[2] = nil')
        self.assertIsNone(self.start('lk.speech.bubble', '{ npc = "lk-1", id = "s1", text = "Hello there." }'))
        self.m.lua('SPEECH.stats.drawn = 2; SPEECH.lastDraw = { npc = "lk-1", text = "Hello there.", x = -5, y = 400 }')
        a = self.tick()
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('bubble drawn off screen: -5,400', a.message)

    def test_combat_view_counts_the_shots_played_here(self):
        self.assertEqual(self.start('lk.combat.view', '{ phase = "begin", key = "r1" }').status, 'PASS')
        self.m.lua('local s = LivingKnox.CombatView.stats; s.shotsPlayed = s.shotsPlayed + 3; s.flashes = 7')
        a = self.start('lk.combat.view', '{ phase = "end", key = "r1", shots = 3 }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual((a.data.shotsPlayed, a.data.flashes), (3, 3))
        self.start('lk.combat.view', '{ phase = "begin", key = "r2" }')
        self.m.lua('local s = LivingKnox.CombatView.stats; s.shotsPlayed = s.shotsPlayed + 4; s.shotsDuplicate = 1')
        a = self.start('lk.combat.view', '{ phase = "end", key = "r2", shots = 3 }')
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('3 expected', a.message)

    def test_weapon_state_waits_for_the_display(self):
        self.m.lua('RST.LKEquipment = { state = function(z, slot) return STATE end, '
                   'describe = function(s) return "hand=" .. s.hand .. " slot=" .. s.slot end }; '
                   'RST.LKAnims = { info = function() return { nodes = { "LKActorAimHandgun" } } end, '
                   'describe = function() return "nodes" end }; '
                   'STATE = { hand = "", second = "", slot = "Base.Pistol", weapon = "" }')
        args = '{ npc = "lk-1", slot = "Holster Right", item = "Base.Pistol", mode = "hand", weapon = "handgun", ' \
               'node = "LKActorAimHandgun", label = "aim" }'
        self.assertIsNone(self.start('lk.weapon.state', args))
        self.m.lua('STATE = { hand = "Base.Pistol", second = "", slot = "", weapon = "handgun" }')
        self.assertEqual(self.tick().status, 'PASS')
        a = self.start('lk.weapon.state', args.replace('"hand"', '"rest"'))
        self.assertIsNone(a)
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('Base.Pistol aim: item at Holster Right', a.message)
        self.m.lua('STATE = { hand = "", second = "", slot = "", weapon = "" }')
        self.assertEqual(self.start('lk.weapon.state', '{ npc = "lk-1", slot = "x", item = "y", mode = "none" }'
                                    ).status, 'PASS')

    def test_sources_follow_kahlua_rules(self):
        for path in (VIEW_FILE, GROUP_FILE):
            code = re.sub(r'--\[\[.*?\]\]', '', path.read_text(encoding='utf-8'), flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code), path.name)
            self.assertIsNone(re.search(r'\bgoto\b|coroutine', code), path.name)
            self.assertTrue(all(ord(ch) < 128 for ch in code), path.name)


# Solo game with Living Knox doubles: groups in memory, bodies that appear when materialize() is called.
GROUP_GAME = SOLO_GAME + r"""
SQUARE = { getX = function() return 10656 end, getY = function() return 10137 end, getZ = function() return 0 end }
function PLAYER:getCurrentSquare() return SQUARE end
ENABLED, OBJECTS, BODIES, DESPAWNED, FORGOT, CREATED, REFRESHED = true, {}, {}, {}, {}, 0, 0
GROUPS, NPCS = {}, 0
local G = {}
function G.ensure() return true end
function G.today() return 1 end
function G.create(spec)
    CREATED = CREATED + 1
    local id = "grp-" .. (100 + CREATED)
    GROUPS[id] = { id = id, type = spec.type, name = spec.name, home = spec.home, members = {}, n = 0 }
    return GROUPS[id]
end
function G.addMember(gid, spec)
    local g = GROUPS[gid]
    g.n = g.n + 1
    NPCS = NPCS + 1
    local mid = "m-" .. g.n
    g.members[mid] = { role = spec.role, npc = "lk-" .. (500 + NPCS) }
    return mid
end
function G.setLeader(gid, mid) GROUPS[gid].leader = mid return true end
function G.get(gid) return GROUPS[gid] end
function G.remove(gid) GROUPS[gid] = nil return true end
function G.findNpc(npc)
    for gid, g in pairs(GROUPS) do
        for mid, m in pairs(g.members) do if m.npc == npc then return gid, mid end end
    end
    return nil
end
local function standingBody(id)
    return { id = id, isOnFloor = function() return false end }
end
LivingKnox = {
    Config = { isEnabled = function() return ENABLED end },
    Groups = G,
    Senses = { perceived = function(id) return { p = { { u = "player0" } } } end },
    Bodies = { find = function(id) return BODIES[id] end,
        despawn = function(id) DESPAWNED[#DESPAWNED + 1] = id; OBJECTS[id] = nil; BODIES[id] = nil; return true end },
    Directives = { forget = function(id) FORGOT[#FORGOT + 1] = id end },
    Homes = { skip = function(gid) GROUPS[gid].skipped = true end },
}
function materialize()
    for _, g in pairs(GROUPS) do
        for _, m in pairs(g.members) do OBJECTS[m.npc] = standingBody(m.npc); BODIES[m.npc] = OBJECTS[m.npc] end
    end
end
package.loaded["RadioSurvivor/RS_NPCProvider"] = { objects = function() return OBJECTS end }
package.loaded["RadioSurvivor/RS_GroupRadio"] = { refresh = function() REFRESHED = REFRESHED + 1 end }
"""

GROUP_SUITES = r"""
RST.suite("z.group", { tags = { "server" }, testTimeoutMs = 120000 }, function(s)
    s.test("group near the player", function(t)
        RST.LKGroup.ensure(t, nil, function(t2, gid, npc, created)
            GOT = { gid = gid, npc = npc, created = created,
                perceived = #LivingKnox.Senses.perceived(npc).p }
            t2:ok(gid ~= nil, "no group")
        end, READY and { ready = READY } or nil)
    end)
end)
"""


class GroupFixtureTests(unittest.TestCase):
    """RST_LKGroupFixture.lua (E01-T19): a Living Knox group near the player instead of a SKIP."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = Machine(Path(self.tmp.name) / 'solo', GROUP_GAME, [STEPS_FILE, GROUP_FILE, GROUP_SUITES])

    def tearDown(self):
        self.tmp.cleanup()

    def run_suite(self, materialize_at=None, limit=1500):
        m = self.m
        m.lua('GOT = nil; assert(RST.start("z.group", { ctx = { side = "solo" }, onDone = function(r) REPORT = r end }))')
        for i in range(limit):
            if not m.lua('return RST.running()'):
                return results(m.g.REPORT)
            if materialize_at is not None and i == materialize_at:
                m.lua('materialize()')
            m.g.CLOCK = m.g.CLOCK + 100
            m.g.Events.OnTick.fire()
        raise AssertionError('run not over')

    def test_group_already_loaded_is_used_as_it_is(self):
        self.m.lua('GROUPS["grp-1"] = { id = "grp-1", members = { ["m-1"] = { npc = "lk-1" } } }; '
                   'OBJECTS["lk-1"] = { isOnFloor = function() return false end }')
        r = self.run_suite()
        self.assertEqual(r['group near the player'], ('PASS', None))
        self.assertEqual((self.m.g.GOT.gid, self.m.g.GOT.npc, self.m.g.GOT.created), ('grp-1', 'lk-1', False))
        self.assertEqual(self.m.g.CREATED, 0)
        self.assertIsNotNone(self.m.lua('return GROUPS["grp-1"]'))

    def test_fixture_group_created_awaited_used_and_removed(self):
        r = self.run_suite(materialize_at=20)
        self.assertEqual(r['group near the player'], ('PASS', None))
        got = self.m.g.GOT
        self.assertEqual((got.gid, got.npc, got.created), ('grp-101', 'lk-501', True))
        self.assertEqual(got.perceived, 0)                      # players hidden from the fixture group
        self.assertIsNone(self.m.lua('return GROUPS["grp-101"]'))
        self.assertEqual(self.m.lua('return table.concat(DESPAWNED, ",")'), 'lk-501,lk-502')
        self.assertEqual(self.m.lua('return table.concat(FORGOT, ",")'), 'lk-501,lk-502')
        self.assertEqual(self.m.lua('return #LivingKnox.Senses.perceived("lk-501").p'), 1)   # restored
        self.assertGreaterEqual(self.m.g.REFRESHED, 2)        # voice of the group added, then gone

    def test_bodies_never_up_fail_and_cleanup_runs(self):
        self.m.lua('RST.LKGroup.BODIES_MS = 1000')
        status, msg = self.run_suite()['group near the player']
        self.assertEqual(status, 'FAIL')
        self.assertIn('bodies of the fixture group grp-101 not loaded and standing near the player', msg)
        self.assertIsNone(self.m.lua('return GROUPS["grp-101"]'))
        self.assertIsNone(self.m.g.GOT)

    def test_outside_a_world_run_the_former_skip_is_kept(self):
        self.m.lua('getWorld = function() return { getWorld = function() return "mysave" end } end')
        status, msg = self.run_suite()['group near the player']
        self.assertEqual(status, 'SKIP')
        self.assertIn('go next to a group and run again', msg)
        self.assertEqual(self.m.g.CREATED, 0)

    def test_ready_condition_creates_a_group_even_with_one_loaded(self):
        self.m.lua('GROUPS["grp-1"] = { id = "grp-1", members = { ["m-1"] = { npc = "lk-1" } } }; '
                   'OBJECTS["lk-1"] = { isOnFloor = function() return false end }; '
                   'READY = function() return CREATED > 0 and OBJECTS["lk-501"] ~= nil end')
        r = self.run_suite(materialize_at=5)
        self.assertEqual(r['group near the player'], ('PASS', None))
        self.assertEqual((self.m.g.GOT.gid, self.m.g.GOT.created), ('grp-101', True))

    def test_mp_client_and_disabled_engine_skip(self):
        self.m.lua('ENABLED = false')
        self.assertEqual(self.run_suite()['group near the player'][0], 'SKIP')
        self.m.lua('ENABLED = true; isClient = function() return true end')
        status, msg = self.run_suite()['group near the player']
        self.assertEqual(status, 'SKIP')
        self.assertIn('authority', msg)


# ---------------------------------------------------------------------------------------------------- E01-T16 (H)

H_FILE = LUA / 'shared' / 'RST' / 'RST_PeerChecksH.lua'

# Second client of an MP game: health view, alert view, body copies (position, direction), squares of the upkeep.
H_GAME = PEER_GAME + r"""
local function body(x, y, z, a)
    return { x = x, y = y, z = z, a = a, getX = function(self) return self.x end, getY = function(self) return self.y end,
        getZ = function(self) return self.z end, getDirectionAngle = function(self) return self.a end }
end
BODIES = { ["lk-1"] = body(10.5, 10.5, 0, 0), ["lk-2"] = body(20.5, 10.5, 0, 180) }
HEALTH = {}
ALERT = { VOICES = { VoiceMaleShoutHey = true }, stats = { received = 2, duplicate = 0, refused = 0, played = 2 },
    last = nil }
LivingKnox = {
    Anim = { knownBodies = function() return BODIES end },
    HealthView = { get = function(id) return HEALTH[id] end },
    AlertView = ALERT,
}
SQUARES = {}
function square(x, y, z, gen)
    local sq = { gen = gen, glass = false, blood = false }
    function sq:getGenerator() return self.gen end
    function sq:getBrokenGlass() if self.glass then return {} end return nil end
    function sq:haveBlood() return self.blood end
    SQUARES[x .. "," .. y .. "," .. z] = sq
    return sq
end
function generator(fuel, cond)
    return { fuel = fuel, cond = cond, getFuel = function(self) return self.fuel end,
        getCondition = function(self) return self.cond end }
end
CELL = { getGridSquare = function(self, x, y, z) return SQUARES[x .. "," .. y .. "," .. z] end }
getCell = function() return CELL end
instanceof = function() return false end
"""


class HStepTests(unittest.TestCase):
    """Handlers of RST_PeerChecksH.lua (E01-T16): what the second client sees (LK05-T08/T09/T10, LK07-T02)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = Machine(Path(self.tmp.name) / 'c', H_GAME, [STEPS_FILE, H_FILE])
        self.m.g.CLOCK = 10000

    def tearDown(self):
        self.tmp.cleanup()

    def start(self, step, args, ms=1000):
        self.m.lua(f'ANSWER = nil; RST.Steps.start(1, "{step}", {args}, {ms}, function(r) ANSWER = r end)')
        return self.m.g.ANSWER

    def tick(self, dt=100):
        self.m.g.CLOCK = self.m.g.CLOCK + dt
        self.m.lua('RST.Steps.tick()')
        return self.m.g.ANSWER

    def test_health_view_waits_for_the_copy_then_compares(self):
        self.assertIsNone(self.start('lk.health.view', '{ npc = "lk-1", hp = 80, max = 100, tol = 1 }'))
        self.m.lua('HEALTH["lk-1"] = { hp = 79.5, max = 100, wounds = 1 }')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.m.lua('HEALTH["lk-1"] = { hp = 90, max = 100, wounds = 0 }')
        self.assertIsNone(self.start('lk.health.view', '{ npc = "lk-1", hp = 80, max = 100, tol = 1 }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('health here 90/100, authority 80/100', a.message)
        # MP 2026-10-15: the copy is rounded (max 1.981 for 1.981295 on the authority)
        self.m.lua('HEALTH["lk-1"] = { hp = 1.828, max = 1.981, wounds = 1 }')
        a = self.start('lk.health.view', '{ npc = "lk-1", hp = 1.83, max = 1.981295108795166, tol = 0.01 }') or self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.m.lua('HEALTH["lk-1"] = { hp = 1.83, max = 2.5, wounds = 1 }')
        self.assertIsNone(self.start('lk.health.view', '{ npc = "lk-1", hp = 1.83, max = 1.981295108795166, tol = 0.01 }'))
        self.assertEqual(self.tick(2000).status, 'FAIL')

    def test_alert_view_counts_new_cries_played_once(self):
        self.assertEqual(self.start('lk.alert.view', '{ phase = "begin", key = "k" }').status, 'PASS')
        self.assertIsNone(self.start('lk.alert.view', '{ phase = "end", key = "k", cries = 1 }'))
        self.m.lua('ALERT.stats.received = 3; ALERT.stats.played = 3; ALERT.last = { s = "VoiceMaleShoutHey" }')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        # a cry received but never played: FAIL at the deadline
        self.start('lk.alert.view', '{ phase = "begin", key = "k2" }')
        self.m.lua('ALERT.stats.received = 4')
        self.assertIsNone(self.start('lk.alert.view', '{ phase = "end", key = "k2", cries = 1 }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('voices played 0', a.message)
        a = self.start('lk.alert.view', '{ phase = "end", key = "missing", cries = 0 }')
        self.assertEqual(a.status, 'FAIL')

    def test_facing_and_positions(self):
        # lk-1 at 10.5 looks toward +x (0 deg), lk-2 at 20.5 looks toward -x (180 deg): both face x = 15
        a = self.start('lk.facing', '{ bodies = { { npc = "lk-1", x = 15, y = 10 }, { npc = "lk-2", x = 15, y = 10 } },'
                                    ' maxDeg = 30 }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertIsNone(self.start('lk.facing', '{ bodies = { { npc = "lk-1", x = 5, y = 10 } }, maxDeg = 30 }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('lk-1 180 deg', a.message)
        a = self.start('lk.positions', '{ bodies = { { npc = "lk-1", x = 11, y = 11, z = 0 } }, tol = 2 }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertIsNone(self.start('lk.positions', '{ bodies = { { npc = "lk-3", x = 11, y = 11, z = 0 } }, '
                                                     'tol = 2 }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('lk-3 no copy', a.message)

    def test_world_upkeep(self):
        self.m.lua('G = generator(6, 54); square(1, 1, 0, G); S2 = square(2, 1, 0, nil)')
        args = '{ gens = { { x = 1, y = 1, z = 0, fuel = 6, cond = 54 } }, clean = { { x = 2, y = 1, z = 0 } } }'
        self.assertEqual(self.start('world.upkeep', args).status, 'PASS')
        self.m.lua('S2.blood = true; G.fuel = 2')
        self.assertIsNone(self.start('world.upkeep', args))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('fuel 2.00', a.message)
        self.assertIn('blood at 2,1', a.message)
        a = self.start('world.upkeep', '{ gens = { { x = 9, y = 9, z = 0, fuel = 1, cond = 1 } } }')
        self.assertEqual(a.status, 'SKIP')


if __name__ == '__main__':
    unittest.main()
