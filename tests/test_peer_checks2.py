"""Banc hors jeu des étapes du second client ajoutées pour E01-T16 : RST_PeerChecks2.lua (carnet.claim, rst.run,
carnet.contact, map.zones), RST_PeerChecksLK2.lua (lk.contact, lk.track, lk.probe, rst.shot, corpse.drag,
lk.trade.window) et les nouvelles clés de RST_PeerChecks.squareKeys (floor, sprite, light).

    python RadioSurvivor/tests/test_peer_checks2.py

Chaque gestionnaire tourne dans une machine lupa cliente (doublures de test_rst.py et test_rst_steps.py) ; rst.run
passe par le vrai RST_Server.lua d'un serveur simulé (compte « user » refusé, admin « busy » pendant un passage). Ne
prouve rien sur le Java du jeu (paquets, rôles, actions chronométrées, carte) : la campagne MP réelle reste nécessaire.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rst import CLIENT_GAME, LUA, SERVER_FILE, Machine, Network  # noqa: E402
from test_rst_steps import PEER_GAME  # noqa: E402

STEPS_FILE = LUA / 'shared' / 'RST' / 'RST_Steps.lua'
PEER_FILE = LUA / 'shared' / 'RST' / 'RST_PeerChecks.lua'
RADIO_FILE = LUA / 'shared' / 'RST' / 'RST_PeerChecksRadio.lua'
PC2_FILE = LUA / 'shared' / 'RST' / 'RST_PeerChecks2.lua'
LK2_FILE = LUA / 'shared' / 'RST' / 'RST_PeerChecksLK2.lua'

RS_GAME = PEER_GAME + r"""
package.loaded["RadioSurvivor/RS_Config"] = { VERSION = 2, MODULE = "RS_Carnet" }
getText = function(key, arg)
    if key == "IGUI_RS_RetrieveFound" then return "Card found (" .. tostring(arg) .. ")" end
    return key
end
-- Notebook client double: send records, receive keeps snapshot and character.
RS_CarnetClient = { snapshot = { contacts = {}, missions = {} }, world = "w1", run = "r1", character = "c-own" }
function RS_CarnetClient.send(command, args) SENT[#SENT + 1] = { module = "RS_Carnet", command = command, args = args } end
function RS_CarnetClient.receive(command, args)
    if command == "snapshot" then RS_CarnetClient.snapshot = args end
end
-- World map double (RS_MapActions): symbols with world position, colour, kind.
SYMBOLS = {}
local function symbol(kind, id, x, y, c)
    return { kind = kind, id = id, x = x, y = y, c = c,
        getWorldX = function(s) return s.x end, getWorldY = function(s) return s.y end,
        getAlpha = function(s) return s.c.a end, getRed = function(s) return s.c.r end,
        getGreen = function(s) return s.c.g end, getBlue = function(s) return s.c.b end,
        isTexture = function(s) return s.kind == "tex" end, isText = function(s) return s.kind == "text" end,
        getSymbolID = function(s) return s.id end }
end
ZONE_COLOR = { r = 0.85, g = 0.40, b = 0.05, a = 0.8 }
function zone(x, y, r)
    SYMBOLS[#SYMBOLS + 1] = symbol("tex", "Circle", x, y, ZONE_COLOR)
    SYMBOLS[#SYMBOLS + 1] = symbol("text", nil, x, y - r, ZONE_COLOR)
end
API = { getSymbolCount = function() return #SYMBOLS end, getSymbolByIndex = function(_, i) return SYMBOLS[i + 1] end }
package.loaded["RadioSurvivor/RS_MapActions"] = { ZONE_ICON = "Circle", ZONE_COLOR = ZONE_COLOR,
    ZONE_COLOR_TOLERANCE = 0.02, symbolsAPI = function() return API end }
"""

LK_GAME = PEER_GAME + r"""
PLAYER.x, PLAYER.y, PLAYER.z, PLAYER.health = 10, 12, 0, 100
function PLAYER:getX() return self.x end
function PLAYER:getY() return self.y end
function PLAYER:getBodyDamage() local s = self return { getOverallBodyHealth = function() return s.health end } end
PLAYER.dragging, PLAYER.letGo = false, 0
function PLAYER:isDraggingCorpse() return self.dragging end
function PLAYER:setDoGrappleLetGo() self.letGo = self.letGo + 1; self.dragging = false end
function PLAYER:getPrimaryHandItem() return nil end
function PLAYER:getSecondaryHandItem() return nil end
local function body(x, y)
    return { x = x, y = y, z = 0, target = nil, state = "idle", getX = function(s) return s.x end,
        getY = function(s) return s.y end, getZ = function(s) return s.z end, getTarget = function(s) return s.target end,
        getEatBodyTarget = function() return nil end, getCurrentStateName = function(s) return s.state end,
        getSquare = function() return { getObjects = function() return { size = function() return 1 end,
            get = function() return { tag = "floor" } end } end } end }
end
BODIES = { ["lk-1"] = body(10, 10) }
LivingKnox = { Anim = { knownBodies = function() return BODIES end } }
QUEUE = {}
ISTimedActionQueue = { add = function(a) QUEUE[#QUEUE + 1] = a end }
ISGrabCorpseAction = { new = function(_, p, b) return { kind = "grab", body = b } end }
ISPathFindAction = { pathToGrabCorpse = function(_, p, b) return { kind = "path", body = b } end }
CORPSE = { isCorpse = true }
CELL = { getGridSquare = function(_, x, y, z)
    if x == 5 and y == 5 then
        return { getStaticMovingObjects = function() return { size = function() return 1 end,
            get = function() return CORPSE end } end }
    end
    return { getStaticMovingObjects = function() return nil end }
end }
getCell = function() return CELL end
instanceof = function(o, cls) return cls == "IsoDeadBody" and o == CORPSE end
SHOTS = {}
takeScreenshot = function(name) SHOTS[#SHOTS + 1] = name end
-- Trade view double: open asks the offer (answered on the next pump), propose answers per TRADE_OK.
TRADE_OK = true
getText = function(key) if key == "IGUI_LK_Trade_Menu" then return "Trade" end return key end
LivingKnox.TradeView = { state = { n = 0 } }
local V = LivingKnox.TradeView
function V.fill(num, ctx, objs) ctx:addOption("Trade", "lk-1", V.open) end
function V.open(npc) V.state.npc = npc; V.state.n = V.state.n + 1; V.state.pending = V.state.n; V.state.give = {};
    V.state.take = {}; OPENED = npc end
function V.toggle(side, id) V.state[side][id] = true end
function V.propose() V.state.n = V.state.n + 1; V.state.pending = V.state.n; PROPOSED = V.state.n; return V.state.n end
function V.receive(reply) V.state.pending = nil; if reply.offer then V.state.offer = reply.offer end; return true end
function answerOffer() V.receive({ op = "open", n = V.state.pending, offer = { give = { { t = "Base.Battery", i = 1 },
    { t = "Base.Battery", i = 2 }, { t = "Base.Nails", i = 3 } }, take = { { t = "Base.TinnedBeans", i = 77 } } } }) end
function answerProposal() V.receive({ op = "propose", n = PROPOSED, ok = TRADE_OK, reason = TRADE_OK and "done" or "gone",
    line = "x" }) end
"""


class Base(unittest.TestCase):
    GAME = RS_GAME
    FILES = [STEPS_FILE, RADIO_FILE, PC2_FILE]

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.m = Machine(Path(self.tmp.name) / 'c', self.GAME, self.FILES)
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


class RsStepTests(Base):

    def test_claim_returns_the_identity_answered(self):
        self.assertIsNone(self.start('carnet.claim', '{ character = "c-other" }'))
        sent = self.m.lua('return SENT[#SENT]')
        self.assertEqual((sent.command, sent.args.character), ('hello', 'c-other'))
        self.m.lua('Events.OnServerCommand.fire("RS_Carnet", "identity", { character = "c-own" })')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual(a.data.character, 'c-own')
        self.assertIsNone(self.start('carnet.claim', '{ character = "c-other" }'))
        self.assertEqual(self.tick(2000).status, 'FAIL')

    def test_contact_waits_for_the_group_name(self):
        self.assertIsNone(self.start('carnet.contact', '{ id = "npc-1", groupName = "Jane" }'))
        self.assertEqual(self.m.lua('return SENT[#SENT].command'), 'snapshot')
        self.m.lua('RS_CarnetClient.snapshot = { contacts = { { id = "npc-1", name = "Jane Doe", groupName = "RST leave" } } }')
        self.assertIsNone(self.tick())
        self.m.lua('RS_CarnetClient.snapshot.contacts[1].groupName = "Jane"')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertIsNone(self.start('carnet.contact', '{ id = "npc-1", groupName = "Other" }'))
        a = self.tick(2000)
        self.assertEqual(a.status, 'FAIL')
        self.assertIn("group 'Jane'", a.message)

    def test_zones_present_with_line_then_absent(self):
        args = ('{ mission = "m1", rings = { { x = 100, y = 200, r = 30 } }, expect = "present", '
                'line = { key = "IGUI_RS_RetrieveFound", arg = "Tester" } }')
        self.assertIsNone(self.start('map.zones', args))
        self.m.lua('RS_CarnetClient.snapshot = { missions = { { id = "m1", state = "active" } } }')
        self.assertIsNone(self.tick())          # row received, no ring drawn yet
        self.m.lua('zone(100, 200, 30)')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual(a.data.line, 'Card found (Tester)')
        # a second ring at the same place is a duplicate: FAIL
        self.m.lua('zone(100, 200, 30)')
        self.assertIsNone(self.start('map.zones', '{ mission = "m1", rings = { { x = 100, y = 200, r = 30 } } }'))
        self.assertEqual(self.tick(2000).status, 'FAIL')
        # closed: still drawn -> FAIL, removed -> PASS
        self.m.lua('RS_CarnetClient.snapshot = { missions = { { id = "m1", state = "success" } } }')
        self.assertIsNone(self.start('map.zones', '{ mission = "m1", rings = { { x = 100, y = 200, r = 30 } }, '
                                                  'expect = "absent" }'))
        self.m.lua('SYMBOLS = {}')
        self.assertEqual(self.tick().status, 'PASS')
        a = self.start('map.zones', '{ mission = "m1", rings = {}, line = { key = "IGUI_RS_Missing" } }')
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('not translated', a.message)


class RunLaterTests(Base):
    """rst.run.later (E01-T05): armed at once, request retried while the server answers busy, stopped by started."""

    def later(self, dt):
        self.m.g.CLOCK = self.m.g.CLOCK + dt
        self.m.lua('RST.PeerChecks2.laterTick()')

    def runs(self):
        return self.m.lua('local n = 0 for _, e in ipairs(SENT) do if e.module == "RST" then n = n + 1 end end '
                          'return n')

    def reply(self, command):
        self.m.lua('local id = SENT[#SENT].args.id; '
                   f'Events.OnServerCommand.fire("RST", "{command}", {{ id = id, reason = "x" }})')

    def test_retries_while_busy_then_stops_when_started(self):
        a = self.start('rst.run.later', '{ filter = { suite = "rst.disconnect.slow", tags = { "manual" } }, '
                                        'everyMs = 500 }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.later(500)
        self.assertEqual(self.runs(), 1)
        self.assertEqual(self.m.lua('return SENT[#SENT].args.filter.suite'), 'rst.disconnect.slow')
        self.later(100)
        self.assertEqual(self.runs(), 1)            # waits for the answer to the attempt in flight
        self.reply('busy')
        self.later(500)
        self.assertEqual(self.runs(), 2)            # busy: tried again
        self.reply('started')
        self.later(500)
        self.later(500)
        self.assertEqual(self.runs(), 2)            # started: no more request
        self.assertTrue(self.m.lua('return RST.PeerChecks2.later.done'))
        self.assertIn('started', self.m.lua('return RST.PeerChecks2.later.outcome'))

    def test_gives_up_after_max_ms(self):
        self.start('rst.run.later', '{ filter = { suite = "x" }, everyMs = 500, maxMs = 2000 }')
        for _ in range(10):
            self.later(500)
            self.reply('busy')
        self.assertIn('gave up', self.m.lua('return RST.PeerChecks2.later.outcome'))
        n = self.runs()
        self.later(500)
        self.assertEqual(self.runs(), n)

    def test_without_filter_fails(self):
        self.assertEqual(self.start('rst.run.later', '{}').status, 'FAIL')


AUTH_T = r"""
RESULT = {}
function newT()
    local t = { asserts = {}, defers = {}, notes = {}, ctx = { player = { getUsername = function() return "rs_mp1" end } } }
    function t:ok(v, msg) self.asserts[#self.asserts + 1] = { v = v and true or false, msg = msg }
        if not v then error({ rst = "fail", msg = msg }) end end
    function t:skip(why) error({ rst = "skip", msg = why }) end
    function t:note(text) self.notes[#self.notes + 1] = text end
    function t:defer(fn, label) self.defers[#self.defers + 1] = { fn = fn, label = label } end
    return t
end
function outcome(t, fn)
    local ok, err = pcall(fn)
    if ok then return "go" end
    if type(err) == "table" then return err.rst .. ": " .. tostring(err.msg) end
    return "error: " .. tostring(err)
end
function online(names)
    local players = {}
    for _, n in ipairs(names) do players[#players + 1] = { getUsername = function() return n end } end
    getOnlinePlayers = function() return { size = function() return #players end,
        get = function(_, i) return players[i + 1] end } end
end
"""


class AuthorityHelperTests(Base):
    """PC2.unchecked and PC2.checkZones on the authority: FAIL on a server with a second client, SKIP in solo, no
    mark left on the test object (2026-10-15)."""

    def setUp(self):
        super().setUp()
        self.m.lua(AUTH_T)

    def side(self, server):
        v = 'true' if server else 'false'
        self.m.lua(f'isServer = function() return {v} end; isClient = function() return false end')

    def test_unchecked_fails_on_a_server_with_a_second_client(self):
        self.side(True)
        self.m.lua('online({ "rs_mp1", "rs_mp2" })')
        out = self.m.lua('local t = newT() return outcome(t, function() RST.PeerChecks2.unchecked(t, "no peer") end)')
        self.assertTrue(out.startswith('fail: no peer'), out)

    def test_unchecked_skips_in_solo_and_with_one_client(self):
        self.side(False)
        out = self.m.lua('local t = newT() return outcome(t, function() RST.PeerChecks2.unchecked(t, "no peer") end)')
        self.assertEqual(out, 'skip: no peer')
        self.side(True)
        self.m.lua('online({ "rs_mp1" })')
        out = self.m.lua('local t = newT() return outcome(t, function() RST.PeerChecks2.unchecked(t, "no peer") end)')
        self.assertEqual(out, 'skip: no peer')

    def test_check_zones_without_notebook_state(self):
        self.m.lua('RS_CarnetServer = nil')
        self.side(True)
        self.m.lua('online({ "rs_mp1", "rs_mp2" })')
        out = self.m.lua('local t = newT() return outcome(t, function() '
                         'RST.PeerChecks2.checkZones(t, { id = "m" }, {}, "present", nil) end)')
        self.assertTrue(out.startswith('fail: notebook server state not ready'), out)
        self.side(False)
        out = self.m.lua('local t = newT() return outcome(t, function() '
                         'RST.PeerChecks2.checkZones(t, { id = "m" }, {}, "present", nil) end)')
        self.assertTrue(out.startswith('skip: notebook server state not ready'), out)

    def test_check_zones_registers_one_restore_and_leaves_no_mark_on_t(self):
        self.side(False)
        self.m.lua('PUBLISHED = 0; RS_CarnetServer = { store = { data = { world = "w" }, run = "r" }, '
                   'publish = function() PUBLISHED = PUBLISHED + 1 end }')
        self.m.lua('ASKED = 0; RST.Steps.ask = function(t, step, args, opts, after) ASKED = ASKED + 1 end')
        self.m.lua('T = newT(); for i = 1, 3 do RST.PeerChecks2.checkZones(T, { id = "m" }, {}, "present", nil) end')
        self.assertEqual(self.m.lua('return #T.defers'), 1)
        self.assertEqual(self.m.lua('return ASKED'), 3)
        fields = self.m.lua('local n = {} for k in pairs(T) do n[#n + 1] = tostring(k) end table.sort(n) '
                            'return table.concat(n, ",")')
        self.assertEqual(fields, 'asserts,ctx,defer,defers,note,notes,ok,skip')
        self.m.lua('T.defers[1].fn(T)')
        self.assertEqual(self.m.lua('return PUBLISHED'), 1)
        self.assertIsNone(self.m.lua('return RST.PeerChecks2.restoring[T]'))


class RstRunTests(unittest.TestCase):
    """rst.run through the real RST_Server.lua: user denied, admin busy while a run is in progress."""

    def test_user_denied_and_admin_busy(self):
        with tempfile.TemporaryDirectory() as tmp:
            net = Network(Path(tmp))
            alice = net.add_client('alice', 'admin')
            bob = net.add_client('bob', 'user')
            for c in (alice, bob):
                c.lua(f'dofile([[{STEPS_FILE.as_posix()}]]); dofile([[{RADIO_FILE.as_posix()}]]); '
                      f'dofile([[{PC2_FILE.as_posix()}]])')
                c.lua('getPlayer = function() return PLAYER end')
            self.assertTrue(net.server.lua('local _, f = pcall(function() end) return RST.Server ~= nil'))

            def ask(c):
                c.lua('ANSWER = nil; RST.Steps.start(1, "rst.run", { filter = { suite = "x.server" } }, 2000, '
                      'function(r) ANSWER = r end)')
                for _ in range(10):
                    net.tick()
                    c.g.CLOCK = net.clock
                    c.lua('RST.Steps.tick()')
                    if c.g.ANSWER is not None:
                        return c.g.ANSWER
                return None

            a = ask(bob)
            self.assertEqual((a.status, a.data.command), ('PASS', 'denied'), a.message)
            net.server.lua('RST.suite("x.slow", { tags = { "server" } }, function(s) s.test("slow", function(t) '
                           't:sleep(100000, function() end) end) end)')
            net.server.lua('assert(RST.start("x.slow", { ctx = { side = "server" } }))')
            a = ask(alice)
            self.assertEqual((a.status, a.data.command), ('PASS', 'busy'), a.message)
            self.assertEqual(net.server.lua('return RAN.server'), None)


class LkStepTests(Base):
    GAME = LK_GAME
    FILES = [STEPS_FILE, LK2_FILE]

    def test_contact_samples_until_the_end(self):
        self.assertIsNone(self.start('lk.contact', '{ npc = "lk-1", ms = 500, maxDist = 4 }', ms=2000))
        for _ in range(6):
            a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.m.lua('BODIES["lk-1"].target = PLAYER')
        self.assertIsNone(self.start('lk.contact', '{ npc = "lk-1", ms = 300 }', ms=2000))
        for _ in range(4):
            a = self.tick()
        self.assertEqual(a.status, 'FAIL')
        self.assertRegex(a.message, r'target [1-9]')

    def test_track_crossing_and_arrival(self):
        # edge between x = 11 and x = 12 (b square 12, normal +x)
        self.assertEqual(self.start('lk.track', '{ phase = "begin", key = "k", npc = "lk-1", '
                                    'edge = { bx = 12, by = 10, nx = 1, ny = 0 } }').status, 'PASS')
        for x in (10.5, 11.5, 12.4, 13.5):
            self.m.lua(f'BODIES["lk-1"].x = {x}; BODIES["lk-1"].y = 10.5')
            self.m.lua('RST.PeerChecksLK2.tick()')
        a = self.start('lk.track', '{ phase = "end", key = "k", target = { x = 13.5, y = 10.5, z = 0 }, tol = 1.5, '
                                   'cross = true }')
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertTrue(a.data.crossed)
        # around the obstacle (lateral 4 squares): not through it
        self.start('lk.track', '{ phase = "begin", key = "k2", npc = "lk-1", edge = { bx = 12, by = 10, nx = 1, ny = 0 } }')
        for x, y in ((10.5, 14.5), (12.5, 14.5), (13.5, 10.5)):
            self.m.lua(f'BODIES["lk-1"].x = {x}; BODIES["lk-1"].y = {y}')
            self.m.lua('RST.PeerChecksLK2.tick()')
        a = self.start('lk.track', '{ phase = "end", key = "k2", target = { x = 13.5, y = 10.5, z = 0 }, tol = 1.5, '
                                   'cross = true }')
        self.assertEqual(a.status, 'FAIL')
        self.assertIn('not seen going through', a.message)

    def test_shot_after_settle(self):
        self.assertIsNone(self.start('rst.shot', '{ name = "lk-milestone1-spawn", settleMs = 200 }'))
        a = self.tick(300)
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual(self.m.lua('return SHOTS[1]'), 'lk-milestone1-spawn-rs_mp1.png')

    def test_corpse_drag_grab_hold_release(self):
        self.assertIsNone(self.start('corpse.drag', '{ x = 5, y = 5, z = 0, r = 1, holdMs = 300 }', ms=5000))
        # vanilla order (ISWorldObjectContextMenu.lua:1493-1500): walk next to the corpse, then grab it
        self.assertEqual(self.m.lua('return QUEUE[1].kind'), 'path')
        self.assertEqual(self.m.lua('return QUEUE[2].kind'), 'grab')
        self.m.lua('PLAYER.dragging = true')
        self.assertIsNone(self.tick())
        self.assertIsNone(self.tick(400))     # let go
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual(self.m.lua('return PLAYER.letGo'), 1)
        a = self.start('corpse.drag', '{ x = 50, y = 50, z = 0, r = 1 }')
        self.assertEqual(a.status, 'FAIL')

    def test_trade_window_menu_offer_and_proposal(self):
        self.assertIsNone(self.start('lk.trade.window', '{ npc = "lk-1", give = "Base.Battery", take = 77 }', ms=3000))
        self.assertEqual(self.m.lua('return OPENED'), 'lk-1')
        self.m.lua('answerOffer()')
        self.assertIsNone(self.tick())
        self.assertEqual(self.m.lua('return LivingKnox.TradeView.state.give[1] and LivingKnox.TradeView.state.give[2] '
                                    'and LivingKnox.TradeView.state.take[77]'), True)
        self.m.lua('answerProposal()')
        a = self.tick()
        self.assertEqual(a.status, 'PASS', a.message)
        self.assertEqual((a.data.ok, a.data.reason), (True, 'done'))
        # item not offered here: FAIL
        self.start('lk.trade.window', '{ npc = "lk-1", give = "Base.Battery", take = 5 }', ms=3000)
        self.m.lua('answerOffer()')
        a = self.tick()
        self.assertEqual(a.status, 'FAIL')


SQ_GAME = PEER_GAME + r"""
local function list(items) return { size = function() return #items end, get = function(_, i) return items[i + 1] end } end
local function obj(cls, sprite, extra)
    local o = extra or {}
    o.cls = cls
    o.getSprite = function() return { getName = function() return sprite end } end
    o.getContainerCount = function() return 0 end
    return o
end
LAMP = obj("IsoLightSwitch", "lighting_indoor_01_0", { on = true })
function LAMP:isActivated() return self.on end
OBJECTS = { obj("IsoObject", "floors_01_0"), obj("IsoObject", "camping_01_0"), LAMP }
FLOOR = { { getItem = function() return item("Base.Pistol") end } }
SQ = { getStaticMovingObjects = function() return list({}) end, getObjects = function() return list(OBJECTS) end,
    getWorldObjects = function() return list(FLOOR) end }
getCell = function() return { getGridSquare = function() return SQ end } end
instanceof = function(o, cls) return type(o) == "table" and o.cls == cls end
"""


class SquareKeyTests(unittest.TestCase):

    def test_floor_sprite_and_light_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            m = Machine(Path(tmp) / 'c', SQ_GAME, [STEPS_FILE, PEER_FILE])
            keys = m.lua('local k = RST.PeerChecks.squareKeys(1, 1, 0, { floor = true, light = true, '
                         'sprite = { "camping_01_0" } }) return table.concat(k, "|")')
            self.assertEqual(keys, 'floor Base.Pistol|light lighting_indoor_01_0 on=true|sprite camping_01_0')
            m.lua('LAMP.on = false')
            self.assertIn('on=false', m.lua('return table.concat(RST.PeerChecks.squareKeys(1, 1, 0, { light = true }), "|")'))


class SourceTests(unittest.TestCase):

    def test_kahlua_rules(self):
        for f in (PC2_FILE, LK2_FILE):
            src = f.read_text(encoding='utf-8')
            code = src[src.index(']]') + 2:]          # after the header comment
            self.assertNotRegex(code, r'goto', f.name)
            self.assertNotRegex(code, r'(?<![\w.])next\(', f.name)
            self.assertTrue(all(b < 128 for b in f.read_bytes()), f'non ASCII byte in {f.name}')


if __name__ == '__main__':
    unittest.main()
