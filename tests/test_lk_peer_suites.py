"""Banc hors jeu des suites Living Knox à deux clients (classe « c » de l'audit du 2026-10-15) :
lk.ownerreports (LK03-T02), lk.handover (LK03-T03), lk.relay (LK03-T05), lk.spawnclean (LK03-T06),
lk.deathswing (LK06-T13), et des étapes client de RST_PeerChecksLK.lua.

    python RadioSurvivor/tests/test_lk_peer_suites.py

Un serveur dédié et deux clients (rs_mp1 demandeur, rs_mp2 second client), chacun dans sa machine lupa (doublures de
test_rst.py : réseau en file, tables copiées comme TableNetworkUtils), ou un solo. Les suites tournent sur le serveur
(RST.start, ticks de 100 ms) et posent leurs étapes aux clients par le vrai RST_Steps.lua. Doublures des modules
Living Knox, sauf lk.ownerreports qui charge le VRAI LK_Reports.lua (avec LK_Core, LK_Config, LK_Log) : le rapport
forgé part du client par la commande réseau « bodyReport ». Chaque suite passe sur des doublures correctes et échoue
sur un défaut injecté (rapport accepté d'un non-propriétaire, téléport accepté, reprise lente, relais lent ou sans
portée, zombie fantôme, gémissement, son de mêlée qui continue après la mort).
Ne prouve rien sur le Java du jeu (propriété réelle des zombies, paquets, émetteurs FMOD) : la campagne MP réelle
reste nécessaire.
"""
from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rst import CLIENT_GAME, LUA as DEV_LUA, ROOT, SERVER_GAME, Machine, to_py  # noqa: E402

MOD_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
STEPS_FILE = DEV_LUA / 'shared' / 'RST' / 'RST_Steps.lua'
PEER_FILE = DEV_LUA / 'shared' / 'RST' / 'RST_PeerChecksLK.lua'
SUITES = DEV_LUA / 'shared' / 'RST' / 'suites'
SUITE_FILES = {
    'lk.ownerreports': SUITES / 'RST_LKOwnerReports.lua',
    'lk.handover': SUITES / 'RST_LKHandover.lua',
    'lk.relay': SUITES / 'RST_LKRelay.lua',
    'lk.spawnclean': SUITES / 'RST_LKSpawnClean.lua',
    'lk.deathswing': SUITES / 'RST_LKDeathSwing.lua',
}
REQUESTER, PEER = 'rs_mp1', 'rs_mp2'

# ------------------------------------------------------------------------------------------------ doublures communes

WORLD = r"""
local function event()
    local e = { handlers = {} }
    e.Add = function(f) e.handlers[#e.handlers + 1] = f end
    e.Remove = function(f)
        for i, h in ipairs(e.handlers) do if h == f then table.remove(e.handlers, i) return end end
    end
    e.fire = function(...) local copy = {} for i, h in ipairs(e.handlers) do copy[i] = h end
        for _, h in ipairs(copy) do h(...) end end
    return e
end
Events.OnZombieDead = Events.OnZombieDead or event()
function JLIST(items) return { size = function() return #items end, get = function(_, i) return items[i + 1] end } end
instanceItem = function(ft) return { getFullType = function() return ft end } end
GameTime = { getServerTimeMills = function() return CLOCK end }
ZLIST = {}
UNLOADED = false
local Zm = {}
Zm.__index = Zm
function newZombie(o, x, y, z, prefix)
    return setmetatable({ o = o, x = x, y = y, z = z or 0, dead = false, floor = false,
        prefix = prefix or "LKSilentZombie", sounds = {} }, Zm)
end
function Zm:getX() return self.x end
function Zm:getY() return self.y end
function Zm:getZ() return self.z end
function Zm:getOnlineID() return self.o end
-- IsoZombie.isReanimatedPlayer / getPersistentOutfitID (every IsoZombie has both): npc copy = reanimated player.
function Zm:isReanimatedPlayer() return self.reanimated == true end
function Zm:getPersistentOutfitID() return self.outfit or 0 end
function Zm:isDead() return self.dead end
function Zm:isOnFloor() return self.floor end
function Zm:getDirectionAngle() return 0 end
function Zm:getDescriptor() local s = self return { getVoicePrefix = function() return s.prefix end } end
function Zm:getEmitter()
    local s = self
    return { isPlaying = function(_, name) return (s.sounds[name] or 0) > 0 end,
        stopSoundByName = function(_, name) s.sounds[name] = nil end }
end
function Zm:getCurrentSquare() return square(math.floor(self.x), math.floor(self.y), self.z) end
function Zm:getOwner() return self.owner end
function Zm:getOwnerPlayer() return self.owner and PLAYERS and PLAYERS[self.owner] or nil end
function addZ(zb) ZLIST[#ZLIST + 1] = zb end
function removeZ(zb) for i, v in ipairs(ZLIST) do if v == zb then table.remove(ZLIST, i) return end end end
function tickSounds()
    for _, zb in ipairs(ZLIST) do
        for k, n in pairs(zb.sounds) do if n <= 1 then zb.sounds[k] = nil else zb.sounds[k] = n - 1 end end
    end
end
local squares = {}
function square(x, y, z)
    local k = x .. "," .. y .. "," .. z
    if squares[k] == nil then
        squares[k] = { getX = function() return x end, getY = function() return y end, getZ = function() return z end,
            getBuildingDef = function() return nil end }   -- outdoors (lk.handover waits for the body out of a building)
    end
    return squares[k]
end
getCell = function()
    return { getZombieList = function() return JLIST(ZLIST) end,
        getGridSquare = function(_, x, y, z) if UNLOADED then return nil end return square(x, y, z) end }
end
function dist(x1, y1, x2, y2) return math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)) end
"""

PLAYERS_SERVER = r"""
function mkplayer(name, role, x, y)
    local p = login(name, role)
    p.x, p.y, p.z, p.god = x, y, 0, false
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:isGodMod() return self.god end
    function p:setGodMod(v) self.god = v end
    return p
end
"""

SOLO_PLAYER = r"""
isServer = function() return false end
isClient = function() return false end
PLAYER = { name = "", x = 100, y = 100, z = 0, god = false }
function PLAYER:getUsername() return self.name end
function PLAYER:getX() return self.x end
function PLAYER:getY() return self.y end
function PLAYER:getZ() return self.z end
function PLAYER:isGodMod() return self.god end
function PLAYER:setGodMod(v) self.god = v end
getPlayer = function() return PLAYER end
"""

CLIENT_PLAYER = r"""
getPlayer = function() return PLAYER end
"""

# RST_Fixtures doubled: immediate moves (the real fixture waits for the arrival and the squares), undo by t:defer.
FIXTURES = r"""
package.loaded["RST/RST_Fixtures"] = true
RST.Fixtures = { moves = {} }
local F = RST.Fixtures
function F.player(t) return t.ctx.player end
local function put(pl, x, y, z)
    pl.x, pl.y, pl.z = x, y, z
    if ON_MOVE then ON_MOVE(pl) end
end
function F.movePlayer(t, pl, x, y, z, suite)
    local ox, oy, oz = pl.x, pl.y, pl.z
    put(pl, x, y, z)
    F.moves[#F.moves + 1] = tostring(pl:getUsername()) .. ">" .. x .. "," .. y
    t:defer(function() put(pl, ox, oy, oz) end, "player back")
    if suite then return suite(t) end
end
function F.movePlayers(t, pl, x, y, z, suite)
    local dx, dy = x - pl.x, y - pl.y
    local all = {}
    for _, name in ipairs(ONLINE or {}) do all[#all + 1] = PLAYERS[name] end
    if #all == 0 then all = { pl } end
    for _, q in ipairs(all) do
        local ox, oy, oz = q.x, q.y, q.z
        put(q, q.x + dx, q.y + dy, q.z)
        t:defer(function() put(q, ox, oy, oz) end, "player back")
    end
    if suite then return suite(t) end
end
"""

# Living Knox core of the doubled sides: authority test of the real modules, Log of the real module format.
LK_BASE = r"""
LivingKnox = LivingKnox or {}
LivingKnox.TAG = "[LivingKnox]"
function LivingKnox.isAuthority() return not isClient() end
LivingKnox.Log = { format = function(msg, ...) if select("#", ...) > 0 then return string.format(msg, ...) end
    return tostring(msg) end }
function LivingKnox.Log.warn(msg, ...) print("[LivingKnox] WARN " .. LivingKnox.Log.format(msg, ...)) end
function LivingKnox.Log.info(msg, ...) print("[LivingKnox] INFO " .. LivingKnox.Log.format(msg, ...)) end
LivingKnox.Config = { BODIES = { RELEASE_DELAY_MS = 300000 } }
"""

# Body of npc lk-1 on the authority (server copy, or the only body in solo) and its directives.
BODY_SERVER = r"""
local LK = LivingKnox
OWNER = OWNER   -- account owning the body (server), nil = the server simulates it
LK.Bodies = { bound = {}, spawned = 0 }
function LK.Bodies.spawn(profile, x, y, z)
    LK.Bodies.spawned = LK.Bodies.spawned + 1
    BODY = newZombie(77, x + 0.5, y + 0.5, z, "LKSilentZombie")
    BODY.owner = OWNER
    addZ(BODY)
    LK.Bodies.bound["lk-1"] = BODY
    if PY_SPAWN then PY_SPAWN(x, y, z) end
    return "lk-1", BODY
end
function LK.Bodies.find(id)
    if id ~= "lk-1" or BODY == nil or BODY.gone then return nil, "unknown" end
    if UNLOADED then return nil, "embodied" end
    return BODY, "embodied"
end
function LK.Bodies.despawn(id)
    if BODY ~= nil and not BODY.gone then
        BODY.gone = true
        removeZ(BODY)
        LK.Bodies.bound["lk-1"] = nil
        if PY_DESPAWN then PY_DESPAWN() end
    end
end
function LK.Bodies.findFreeSquare(x, y, z) return square(x, y, z) end
LK.Directives = LK.Directives or {}
local D = LK.Directives
D.entries = D.entries or {}
D.state = D.state or { lease = 0 }
D.stats = D.stats or { issued = 0, resumed = 0 }
D.accepted = D.accepted or {}
function D.senderName(p) if p == nil then return "?" end return tostring(p:getUsername()) end
function D.isOwner(z, p) if not isServer() then return true end return p ~= nil and z:getOwnerPlayer() == p end
function D.isPreviousOwner() return false end
function D.ownerName(z) if z:getOwner() == nil then return "server" end return D.senderName(z:getOwnerPlayer()) end
function D.forget(id) D.entries[id] = nil end
function D.dist(x1, y1, x2, y2) return dist(x1, y1, x2, y2) end
function D.get(id) return D.entries[id] end
-- Directives.stepTarget (LK_Directives.lua): waypoint k of e.w, else the destination.
function D.stepTarget(e, k)
    if type(e.w) == "table" and type(k) == "number" and k >= 1 and k <= #e.w then return e.w[k].x, e.w[k].y, e.z end
    return e.x, e.y, e.z
end
"""


class LKNet:
    """Serveur dédié et clients (ou solo) ; commandes en file copiées comme le réseau ; actions différées par tick."""

    def __init__(self, root: Path, solo=False, clients=(REQUESTER, PEER)):
        self.root, self.solo, self.queue, self.later, self.clock, self.n = root, solo, [], [], 1000, 0
        self.clients = {}
        if solo:
            self.server = Machine(root / 'solo', SOLO_PLAYER, [WORLD, STEPS_FILE, PEER_FILE, FIXTURES, LK_BASE])
        else:
            self.server = Machine(root / 'server', SERVER_GAME + PLAYERS_SERVER,
                                  [WORLD, STEPS_FILE, PEER_FILE, FIXTURES, LK_BASE])
            self.server.g.PY_SERVER_SEND = lambda user, m, c, a: self.queue.append(('to_client', user, m, c, to_py(a)))
            for i, name in enumerate(clients):
                self.add_client(name, 100, 100 + 2 * i)

    def add_client(self, name, x, y):
        c = Machine(self.root / name, CLIENT_GAME + CLIENT_PLAYER, [WORLD, STEPS_FILE, PEER_FILE])
        c.lua(f'PLAYER = {{ name = "{name}" }}; function PLAYER:getUsername() return self.name end')
        c.g.PY_CLIENT_SEND = lambda user, m, cmd, a: self.queue.append(('to_server', user, m, cmd, to_py(a)))
        self.server.lua(f'mkplayer("{name}", "admin", {x}, {y})')
        self.clients[name] = c
        return c

    def machines(self):
        return [self.server, *self.clients.values()]

    def each_client(self, code):
        for c in self.clients.values():
            c.lua(code)

    def after(self, ticks, fn):
        self.later.append((self.n + ticks, fn))

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
        self.n += 1
        due = [fn for n, fn in self.later if n <= self.n]
        self.later = [(n, fn) for n, fn in self.later if n > self.n]
        for fn in due:
            fn()
        self.pump()
        for m in self.machines():
            m.g.CLOCK = self.clock
        s = self.server
        s.lua('if SIM then SIM() end')
        if not self.solo:
            s.g.Events.OnTickEvenPaused.fire()
        s.g.Events.OnTick.fire()
        for c in self.clients.values():
            c.lua('if SIM then SIM() end')
            c.g.Events.OnTick.fire()
        self.clock += dt
        self.pump()

    def run(self, flt, limit=6000):
        s = self.server
        player = 'getPlayer()' if self.solo else f'PLAYERS["{REQUESTER}"]'
        side = 'solo' if self.solo else 'server'
        s.lua(f'REPORT = nil; assert(RST.start({flt}, {{ ctx = {{ side = "{side}", player = {player} }}, '
              f'onDone = function(r) REPORT = r end }}))')
        for _ in range(limit):
            if not s.lua('return RST.running()'):
                return s.g.REPORT
            self.tick()
        raise AssertionError('run not over')


def results(report):
    return {r.test: (r.status, r.message) for _, r in report.results.items()}


def measures(machine, prefix):
    return [line for _, line in machine.g.LOGS.items() if line.startswith(prefix + ' measure ')]


class Base(unittest.TestCase):
    SUITE = ''

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def net(self, solo=False, clients=(REQUESTER, PEER), server_code='', client_code='', after_load=''):
        net = LKNet(Path(self.tmp.name) / ('solo' if solo else 'mp'), solo=solo, clients=clients)
        net.server.lua(server_code)
        for c in net.clients.values():
            c.lua(client_code)
        net.server.lua(f'dofile([[{SUITE_FILES[self.SUITE].as_posix()}]])')
        net.server.lua(after_load)
        return net

    def statuses(self, report):
        return {k: v[0] for k, v in results(report).items()}


# ------------------------------------------------------------------------------------------------ lk.ownerreports

REPORTS_SERVER = r"""
package.path = [[{mod}/shared/?.lua;{mod}/server/?.lua;]] .. package.path
LivingKnox = nil
package.loaded["LivingKnox/LK_Bodies"] = true
package.loaded["LivingKnox/LK_Directives"] = true
package.loaded["LivingKnox/LK_ZombieGuard"] = true
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
LivingKnox.ZombieGuard = { CMD_HELLO = "guardHello" }
OWNER = "{owner}"
""" + BODY_SERVER + r"""
require "LivingKnox/LK_Reports"
LEGIT_N, LEGIT_MS = 0, 0
-- The owner's executor: one state report per second at the body position (direct call: the bench has no executor).
function SIM()
    if BODY == nil or BODY.gone or CLOCK - LEGIT_MS < 1000 then return end
    LEGIT_MS, LEGIT_N = CLOCK, LEGIT_N + 1
    local p = isServer() and PLAYERS[OWNER] or getPlayer()
    LivingKnox.Reports.onReport(p, { id = "lk-1", l = 0, n = LEGIT_N, x = BODY.x, y = BODY.y, z = BODY.z, a = 0,
        act = "idle", hp = 1.5, pose = "stand", t = 0 })
end
"""


class OwnerReportsSuiteTests(Base):
    SUITE = 'lk.ownerreports'

    def make(self, solo=False, defect=''):
        code = REPORTS_SERVER.replace('{mod}', MOD_LUA.as_posix()).replace('{owner}', '' if solo else REQUESTER)
        if solo:
            code = code.replace('OWNER = ""', 'OWNER = nil')
        return self.net(solo=solo, server_code=code, after_load=defect)

    def test_forged_reports_sent_by_the_clients_are_refused_and_logged(self):
        net = self.make()
        rep = net.run('{ suite = "lk.ownerreports", tags = "world" }')
        self.assertEqual(self.statuses(rep), {
            'report of a client that does not simulate the body: refused, logged, state unchanged': 'PASS',
            'owner report with a teleport, then a health rise: refused, no teleport': 'PASS'}, results(rep))
        st = net.server.g.LivingKnox.Reports.stats
        self.assertGreaterEqual(st.why['not the owner'], 1)
        self.assertGreaterEqual(st.why['far from the body'], 1)
        self.assertGreaterEqual(st.why['health rose without a known heal'], 1)
        lines = measures(net.server, '[LKO]')
        self.assertTrue(any('not the owner from rs_mp2' in line for line in lines), lines)
        self.assertTrue(any('far from the body from rs_mp1' in line for line in lines), lines)
        # The reports really travelled from the clients: each sent one through its step.
        self.assertEqual(net.clients[PEER].lua('return RST.Steps.records[1].step'), 'lk.report.forge')
        self.assertEqual(net.clients[REQUESTER].lua('return #RST.Steps.records'), 2)

    def test_non_owner_accepted_is_caught(self):
        net = self.make(defect='LivingKnox.Directives.isOwner = function() return true end')
        rep = net.run('{ suite = "lk.ownerreports", tags = "world", test = "does not simulate" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('report not refused "not the owner"', msg)

    def test_teleport_accepted_is_caught(self):
        net = self.make(defect='LivingKnox.Config.REPORTS.MAX_GAP = 1e9; LivingKnox.Config.REPORTS.MAX_SPEED = 1e9')
        rep = net.run('{ suite = "lk.ownerreports", tags = "world", test = "teleport" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertTrue('forged report accepted' in msg or 'not refused "far from the body"' in msg, msg)

    def test_refusal_not_suspect_is_caught(self):
        # Teleport refused as an expected network race (INFO line, not counted as suspect): caught.
        net = self.make(defect='LivingKnox.Reports.SUSPECT["far from the body"] = nil')
        rep = net.run('{ suite = "lk.ownerreports", tags = "world", test = "teleport" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('refusal not counted as suspect', msg)

    def test_solo_owner_part_by_direct_call_non_owner_skipped(self):
        net = self.make(solo=True)
        rep = net.run('{ suite = "lk.ownerreports", tags = "world" }')
        r = results(rep)
        self.assertEqual(r['owner report with a teleport, then a health rise: refused, no teleport'], ('PASS', None))
        status, msg = r['report of a client that does not simulate the body: refused, logged, state unchanged']
        self.assertEqual(status, 'SKIP')
        self.assertIn('two clients', msg)

    def test_single_client_skips_the_non_owner_part(self):
        code = REPORTS_SERVER.replace('{mod}', MOD_LUA.as_posix()).replace('{owner}', REQUESTER)
        net = self.net(clients=(REQUESTER,), server_code=code)
        rep = net.run('{ suite = "lk.ownerreports", tags = "world", test = "does not simulate" }')
        self.assertEqual(list(results(rep).values())[0][0], 'SKIP')


# ------------------------------------------------------------------------------------------------ lk.handover

HANDOVER_SERVER = BODY_SERVER + r"""
local LK = LivingKnox
local D = LK.Directives
LK.Reports = { rejectedOf = function() return SUSPECT or 0, SUSPECT or 0 end, get = function() return nil end }
RESUME_MS = RESUME_MS or 300
SPEED = 0.8
LAST_CHANGE, HAND, REPORT_MS = -100000, nil, 0
function D.moveTo(id, x, y, z, g)
    D.stats.issued = D.stats.issued + 1
    D.entries[id] = { v = D.stats.issued, op = "move", s = "moving", done = false, tx = x }
    return D.stats.issued
end
local function nearest()
    local best, bd = nil, nil
    for _, name in ipairs(ONLINE) do
        local p = PLAYERS[name]
        local d = dist(p.x, p.y, BODY.x, BODY.y)
        if bd == nil or d < bd then best, bd = name, d end
    end
    return best, bd
end
-- Engine: nearest player owns the body (hysteresis 1.618, 2 s between two changes); the new executor reports after
-- RESUME_MS; the body walks east while an executor runs it; one execution report per second.
function SIM()
    if BODY == nil or BODY.gone then return end
    local best, bd = nearest()
    if BODY.owner == nil then
        BODY.owner = best
    elseif best ~= BODY.owner and CLOCK - LAST_CHANGE >= 2000 then
        local cur = PLAYERS[BODY.owner]
        if bd * 1.618 < dist(cur.x, cur.y, BODY.x, BODY.y) then
            BODY.owner, LAST_CHANGE, HAND = best, CLOCK, { ms = CLOCK }
        end
    end
    local e = D.entries["lk-1"]
    if e == nil or e.done then return end
    if HAND ~= nil then
        if CLOCK - HAND.ms < RESUME_MS then return end
        D.stats.resumed = D.stats.resumed + 1
        D.stats.resumeLast = CLOCK - HAND.ms
        D.stats.resumeMax = math.max(D.stats.resumeMax or 0, D.stats.resumeLast)
        HAND = nil
    end
    BODY.x = BODY.x + SPEED * 0.1
    if BODY.x >= e.tx then e.s, e.done = "arrived", true end
    if CLOCK - REPORT_MS >= 1000 or e.done then
        REPORT_MS = CLOCK
        D.accepted["lk-1"] = { x = BODY.x, y = BODY.y, ms = CLOCK }
    end
end
"""


class HandoverSuiteTests(Base):
    SUITE = 'lk.handover'

    def test_two_transfers_resumed_quickly_pass(self):
        net = self.net(server_code=HANDOVER_SERVER)
        rep = net.run('{ suite = "lk.handover", tags = "world" }')
        self.assertEqual(list(self.statuses(rep).values()), ['PASS'], results(rep))
        line = measures(net.server, '[LKH]')[-1]
        self.assertRegex(line, r'trip arrived #1 \(issued \+1\): owner changes 3 \(server>rs_mp1 rs_mp1>rs_mp2 '
                               r'rs_mp2>rs_mp1\), resumptions 2 \(300, 300 ms; server max 300\), progress gaps '
                               r'around the changes \w+, 300, 300 ms \(climbs or gestures 0\), suspect refusals 0')
        # Players back at their places (undo of the moves).
        self.assertEqual((net.server.lua(f'return PLAYERS["{REQUESTER}"].x'), net.server.lua(f'return PLAYERS["{PEER}"].y')),
                         (100, 102))

    def test_slow_resumption_is_caught(self):
        net = self.net(server_code='RESUME_MS = 2500\n' + HANDOVER_SERVER)
        rep = net.run('{ suite = "lk.handover", tags = "world" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('resumed 2500 ms after the owner change', msg)

    def test_suspect_refusals_are_caught(self):
        net = self.net(server_code=HANDOVER_SERVER)
        net.server.lua('local f = SIM; SIM = function() f(); if BODY and BODY.x > 110 then SUSPECT = 1 end end')
        rep = net.run('{ suite = "lk.handover", tags = "world" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('suspect state reports refused during the trip', msg)

    def test_solo_and_single_client_skip(self):
        net = self.net(solo=True, server_code=HANDOVER_SERVER)
        self.assertEqual(list(self.statuses(net.run('"lk.handover"')).values()), ['SKIP'])
        net = self.net(clients=(REQUESTER,), server_code=HANDOVER_SERVER)
        self.assertEqual(list(self.statuses(net.run('"lk.handover"')).values()), ['SKIP'])


# ------------------------------------------------------------------------------------------------ lk.relay

RELAY_SERVER = BODY_SERVER + r"""
local LK = LivingKnox
EXTRA_TICKS = EXTRA_TICKS or 0
ALL_CLIENTS = ALL_CLIENTS or false
LK.Anim = { wanted = {} }
function LK.Anim.setGesture(id, g) LK.Anim.wanted[id] = g; DIRTY = 1 + EXTRA_TICKS return true end
LK.Relay = { near = {}, sent = {}, stats = { byClient = {}, lastDelay = 0, maxDelay = 0 } }
local RL = LK.Relay
local R = 0
local function send(name, entry)
    R = R + 1
    entry.r = R
    sendServerCommand(PLAYERS[name], "LivingKnox", "animState", { d = { ["lk-1"] = entry } })
    local c = RL.stats.byClient[name] or { msgs = 0, bytes = 0 }
    c.msgs = c.msgs + 1
    RL.stats.byClient[name] = c
end
-- Relay: recipients within 100 squares of the body (all of them with ALL_CLIENTS), { gone } to a client that left,
-- the wanted gesture published DIRTY ticks after it was set.
function SIM()
    if BODY == nil or BODY.gone then return end
    local near = {}
    for _, name in ipairs(ONLINE) do
        local p = PLAYERS[name]
        if ALL_CLIENTS or (math.abs(p.x - BODY.x) <= 100 and math.abs(p.y - BODY.y) <= 100) then near[name] = p end
    end
    RL.near["lk-1"] = near
    for name, s in pairs(RL.sent) do
        if s["lk-1"] and near[name] == nil then
            send(name, { gone = true })
            s["lk-1"] = nil
        end
    end
    if DIRTY == nil then return end
    DIRTY = DIRTY - 1
    if DIRTY > 0 then return end
    DIRTY = nil
    for name in pairs(near) do
        send(name, { g = LK.Anim.wanted["lk-1"] or "idle" })
        RL.sent[name] = RL.sent[name] or {}
        RL.sent[name]["lk-1"] = true
    end
end
"""

RELAY_CLIENT = r"""
LivingKnox = { Anim = { remote = { g = {} } } }
function LivingKnox.Anim.gestureOf(id) return LivingKnox.Anim.remote.g[id] or "idle" end
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "LivingKnox" or command ~= "animState" then return end
    for id, e in pairs(args.d) do
        if e.gone or e.g == "idle" then LivingKnox.Anim.remote.g[id] = nil else LivingKnox.Anim.remote.g[id] = e.g end
    end
end)
"""


class RelaySuiteTests(Base):
    SUITE = 'lk.relay'

    def test_delay_and_range_pass(self):
        net = self.net(server_code=RELAY_SERVER, client_code=RELAY_CLIENT)
        rep = net.run('{ suite = "lk.relay", tags = "world" }')
        self.assertEqual(set(self.statuses(rep).values()), {'PASS'}, results(rep))
        lines = measures(net.server, '[LKR]')
        self.assertRegex(lines[0], r'gesture delays at rs_mp2: crouch 200, sit 200, idle 200 ms \(max 200\)')
        self.assertRegex(lines[1], r'out of range \(160 squares\): messages to rs_mp2 \+0, to rs_mp1 \(near\) \+1')

    def test_slow_relay_is_caught(self):
        net = self.net(server_code='EXTRA_TICKS = 3\n' + RELAY_SERVER, client_code=RELAY_CLIENT)
        rep = net.run('{ suite = "lk.relay", tags = "world", test = "300 ms" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('gesture seen 500 ms after it was set', msg)

    def test_relay_without_range_is_caught(self):
        net = self.net(server_code='ALL_CLIENTS = true\n' + RELAY_SERVER, client_code=RELAY_CLIENT)
        rep = net.run('{ suite = "lk.relay", tags = "world", test = "out of range" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('still a relay recipient', msg)

    def test_solo_skips(self):
        net = self.net(solo=True, server_code=RELAY_SERVER)
        self.assertEqual(set(self.statuses(net.run('"lk.relay"')).values()), {'SKIP'})


# ------------------------------------------------------------------------------------------------ lk.spawnclean

SPAWN_SERVER = BODY_SERVER + r"""
ON_MOVE = function()
    if BODY == nil or BODY.gone then return end
    local far = true
    for _, name in ipairs(ONLINE or {}) do
        local p = PLAYERS[name]
        if dist(p.x, p.y, BODY.x, BODY.y) < 150 then far = false end
    end
    if not ONLINE then far = dist(getPlayer().x, getPlayer().y, BODY.x, BODY.y) >= 150 end
    if far and not UNLOADED then
        UNLOADED = true
        if PY_UNLOAD then PY_UNLOAD() end
    elseif not far and UNLOADED then
        UNLOADED = false
        if PY_RELOAD then PY_RELOAD() end
    end
end
"""

SPAWN_CLIENT = r"""
LivingKnox = LivingKnox or {}
LivingKnox.ZombieGuard = { SILENT_VOICE = "LKSilentZombie", ZOMBIE_VOICES = { "MaleZombieVoiceA", "FemaleZombieVoiceA" },
    stats = { voicesStopped = 0, preSilenced = 0, adopted = 0, restored = 0 } }
LivingKnox.Anim = LivingKnox.Anim or {}
function LivingKnox.Anim.knownBodies()
    local out = {}
    if LivingKnox.isAuthority and LivingKnox.isAuthority() then
        if BODY and not BODY.gone and not BODY.dead and not UNLOADED then out["lk-1"] = BODY end
        return out
    end
    if COPY and not COPY.dead then out["lk-1"] = COPY end
    return out
end
-- A copy appears (MOAN: vanilla prefix and a voice for 3 ticks, then muted by the guard).
function APPEAR(x, y, z, moan)
    COPY = newZombie(77, x + 0.5, y + 0.5, z, moan and "MaleZombieVoiceA" or "LKSilentZombie")
    COPY.reanimated, COPY.outfit = true, 1234
    if moan then COPY.sounds.MaleZombieVoiceA = 30 end
    addZ(COPY)
    LivingKnox.ZombieGuard.stats.preSilenced = LivingKnox.ZombieGuard.stats.preSilenced + 1
end
function MUTE()
    if COPY.prefix ~= "LKSilentZombie" then
        COPY.prefix = "LKSilentZombie"
        COPY.sounds = {}
        LivingKnox.ZombieGuard.stats.voicesStopped = LivingKnox.ZombieGuard.stats.voicesStopped + 1
    end
end
-- Ghost of the npc body: an ordinary zombie dressed as the npc (same persistent outfit id).
function GHOST(x, y, z) G0 = newZombie(99, x + 0.5, y + 0.5, z, "MaleZombieVoiceA"); G0.outfit = 1234; addZ(G0) end
-- Ambient zombie of the reloaded chunk: ordinary zombie in an outfit of its own.
function AMBIENT(x, y, z) A0 = newZombie(98, x + 1.5, y + 0.5, z, "MaleZombieVoiceA"); A0.outfit = 555; addZ(A0) end
function UNGHOST() if G0 then removeZ(G0); G0 = nil end end
function LEAVE() if COPY then removeZ(COPY); COPY = nil end end
"""


class SpawnCleanSuiteTests(Base):
    SUITE = 'lk.spawnclean'

    def make(self, solo=False, ghost=False, moan=False, ghost_on_return=False, ambient_on_return=False):
        net = self.net(solo=solo, server_code=SPAWN_SERVER + ('\n' + SPAWN_CLIENT if solo else ''),
                       client_code=SPAWN_CLIENT)
        state = {'spawn': None}

        def appear_all(x, y, z):
            if net.server.lua('return UNLOADED'):   # everybody left before the copy reached the clients
                return
            machines = [net.server] if solo else list(net.clients.values())
            for m in machines:
                if solo:
                    if ghost:
                        m.lua(f'GHOST({x}, {y}, {z})')
                        net.after(3, lambda m=m: m.lua('UNGHOST()'))
                    continue
                m.lua(f'APPEAR({x}, {y}, {z}, {"true" if moan else "false"})')
                if moan:
                    net.after(3, lambda m=m: m.lua('MUTE()'))
                if ghost:
                    m.lua(f'GHOST({x}, {y}, {z})')
                    net.after(3, lambda m=m: m.lua('UNGHOST()'))

        def on_spawn(x, y, z):
            state['spawn'] = (x, y, z)
            net.after(1, lambda: appear_all(x, y, z))

        def on_unload():
            for c in net.clients.values():
                c.lua('LEAVE()')

        def on_reload():
            x, y, z = (int(v) for v in net.server.lua('return math.floor(BODY.x), math.floor(BODY.y), BODY.z'))
            if ghost_on_return:
                for c in net.clients.values():
                    net.after(1, lambda c=c: c.lua(f'GHOST({x}, {y}, {z})'))
            if ambient_on_return:
                for c in net.clients.values():
                    net.after(1, lambda c=c: c.lua(f'AMBIENT({x}, {y}, {z})'))
            net.after(2, lambda: [c.lua(f'APPEAR({x}, {y}, {z}, false)') for c in net.clients.values()])

        net.server.g.PY_SPAWN = on_spawn
        net.server.g.PY_UNLOAD = on_unload
        net.server.g.PY_RELOAD = on_reload
        net.server.g.PY_DESPAWN = lambda: net.after(1, on_unload)
        return net

    def test_clean_appearance_and_chunk_return_pass(self):
        net = self.make()
        rep = net.run('{ suite = "lk.spawnclean", tags = "world" }')
        self.assertEqual(set(self.statuses(rep).values()), {'PASS'}, results(rep))
        lines = measures(net.server, '[LKA]')
        self.assertEqual(len(lines), 4, lines)   # two tests x two clients
        self.assertTrue(all('most 1 at once, other zombies 0, voice ticks 0, vanilla prefix ticks 0' in line
                            for line in lines), lines)

    def test_ghost_zombie_is_caught(self):
        net = self.make(ghost=True)
        rep = net.run('{ suite = "lk.spawnclean", tags = "world", test = "npc appears" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('second zombie seen near the npc', msg)

    def test_moan_is_caught(self):
        net = self.make(moan=True)
        rep = net.run('{ suite = "lk.spawnclean", tags = "world", test = "npc appears" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('zombie voice played by the npc copy', msg)

    def test_ghost_at_chunk_return_is_caught(self):
        net = self.make(ghost_on_return=True)
        rep = net.run('{ suite = "lk.spawnclean", tags = "world", test = "chunk return" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('second zombie seen near the npc', msg)

    def test_ambient_zombie_at_chunk_return_is_not_a_ghost(self):
        # MP campaign of 2026-10-15: a zombie of the reloaded chunk walked near the npc (other outfit, not a
        # reanimated player): noted as ambient, not a ghost.
        net = self.make(ambient_on_return=True)
        rep = net.run('{ suite = "lk.spawnclean", tags = "world", test = "chunk return" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'PASS', msg)
        net = self.make(ambient_on_return=True, ghost_on_return=True)
        rep = net.run('{ suite = "lk.spawnclean", tags = "world", test = "chunk return" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('second zombie seen near the npc', msg)
        self.assertIn('ambient zombies 1', msg)

    def test_solo_runs_on_the_only_machine(self):
        net = self.make(solo=True)
        rep = net.run('{ suite = "lk.spawnclean", tags = "world", test = "npc appears" }')
        self.assertEqual(list(self.statuses(rep).values()), ['PASS'], results(rep))
        net = self.make(solo=True, ghost=True)
        rep = net.run('{ suite = "lk.spawnclean", tags = "world", test = "npc appears" }')
        self.assertEqual(list(self.statuses(rep).values()), ['FAIL'], results(rep))


# ------------------------------------------------------------------------------------------------ lk.deathswing

DEATH_SERVER = BODY_SERVER + r"""
local LK = LivingKnox
LK.Equipment = { setWeapon = function() return true end }
LK.Combat = {}
function LK.Combat.engage(id, name) ORDER = { c = 1, sw = "MacheteSwing", t = name }; if PY_ENGAGE then PY_ENGAGE() end
    return 1 end
function LK.Combat.get(id) return ORDER end
function LK.Combat.impactSound() return "MacheteHit" end
function LK.Combat.disengage() ORDER = nil end
LK.Health = {}
function LK.Health.kill(id, z, wielder, weapon)
    if BODY == nil or BODY.dead then return false, "no body" end
    BODY.dead = true
    if PY_KILL then PY_KILL() end
    return true
end
"""

DEATH_CLIENT = r"""
LivingKnox = LivingKnox or {}
LivingKnox.Anim = LivingKnox.Anim or {}
function LivingKnox.Anim.knownBodies()
    local out = {}
    local zb = COPY
    if LivingKnox.isAuthority and LivingKnox.isAuthority() then zb = BODY end
    if zb and not zb.dead then out["lk-1"] = zb end
    return out
end
local V = { stats = { meleeSwings = 0, meleeImpacts = 0, bodySoundsStopped = 0 } }
LivingKnox.CombatView = V
SWING_TICKS = SWING_TICKS or 6
NEXT = 0
local function body() if LivingKnox.isAuthority and LivingKnox.isAuthority() then return BODY end return COPY end
-- Swing at the start of each loop of the strike clip while the body is alive (AFTER_DEATH: also when dead);
-- swing stopped at OnZombieDead (unless NO_STOP).
function VIEW_TICK()
    tickSounds()
    local zb = body()
    if not ENGAGED or zb == nil or CLOCK < NEXT then return end
    if zb.dead and not AFTER_DEATH then return end
    zb.sounds.MacheteSwing = SWING_TICKS
    V.stats.meleeSwings = V.stats.meleeSwings + 1
    NEXT = CLOCK + 1250
end
Events.OnZombieDead.Add(function(zb)
    if NO_STOP or zb ~= body() then return end
    if zb.sounds.MacheteSwing then
        zb.sounds.MacheteSwing = nil
        V.stats.bodySoundsStopped = V.stats.bodySoundsStopped + 1
    end
end)
"""


class DeathSwingSuiteTests(Base):
    SUITE = 'lk.deathswing'

    def make(self, solo=False, defect=''):
        client = DEATH_CLIENT + '\n' + defect
        net = self.net(solo=solo, server_code=DEATH_SERVER + ('\n' + client if solo else ''), client_code=client)
        machines = [net.server] if solo else list(net.clients.values())
        for m in machines:
            m.lua('local f = SIM; SIM = function() if f then f() end VIEW_TICK() end')

        def on_spawn(x, y, z):
            if not solo:
                net.after(1, lambda: [c.lua(f'COPY = newZombie(77, {x} + 0.5, {y} + 0.5, {z}); addZ(COPY)')
                                      for c in net.clients.values()])

        def on_engage():
            for m in machines:
                net.after(1, lambda m=m: m.lua('ENGAGED = true'))

        def on_kill():
            if solo:
                net.server.lua('Events.OnZombieDead.fire(BODY)')
                return
            net.after(1, lambda: [c.lua('COPY.dead = true; Events.OnZombieDead.fire(COPY)')
                                  for c in net.clients.values()])

        net.server.g.PY_SPAWN = on_spawn
        net.server.g.PY_ENGAGE = on_engage
        net.server.g.PY_KILL = on_kill
        return net

    def test_silence_after_the_death_passes(self):
        net = self.make()
        rep = net.run('{ suite = "lk.deathswing", tags = "world" }')
        self.assertEqual(list(self.statuses(rep).values()), ['PASS'], results(rep))
        line = measures(net.server, '[LKD]')[-1]
        self.assertIn('at rs_mp2', line)
        self.assertIn('swing playing at the death true, body sounds stopped 1', line)
        self.assertIn('swings 0, impacts 0; dead copy plays swing false, impact false', line)
        self.assertEqual(net.clients[REQUESTER].lua('return #RST.Steps.records'), 0)   # the second client listens

    def test_looping_swing_on_the_dead_body_is_caught(self):
        net = self.make(defect='NO_STOP = true; SWING_TICKS = 1000')
        rep = net.run('{ suite = "lk.deathswing", tags = "world" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('melee sound still playing on the dead copy', msg)

    def test_swing_played_after_the_death_is_caught(self):
        net = self.make(defect='AFTER_DEATH = true')
        rep = net.run('{ suite = "lk.deathswing", tags = "world" }')
        status, msg = list(results(rep).values())[0]
        self.assertEqual(status, 'FAIL')
        self.assertIn('melee sound played after the death', msg)

    def test_solo_listener_is_the_local_player(self):
        net = self.make(solo=True)
        rep = net.run('{ suite = "lk.deathswing", tags = "world" }')
        self.assertEqual(list(self.statuses(rep).values()), ['PASS'], results(rep))
        net = self.make(solo=True, defect='NO_STOP = true; SWING_TICKS = 1000')
        rep = net.run('{ suite = "lk.deathswing", tags = "world" }')
        self.assertEqual(list(self.statuses(rep).values()), ['FAIL'], results(rep))

    def test_single_client_skips(self):
        net = self.net(clients=(REQUESTER,), server_code=DEATH_SERVER)
        self.assertEqual(list(self.statuses(net.run('"lk.deathswing"')).values()), ['SKIP'])


# ------------------------------------------------------------------------------------------------ sources

class SourceTests(unittest.TestCase):
    def test_kahlua_safe_english_sources(self):
        for path in [PEER_FILE, *SUITE_FILES.values()]:
            text = path.read_text(encoding='utf-8')
            self.assertTrue(all(ord(ch) < 128 for ch in text), f'{path.name}: non ASCII character')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code), path.name)
            self.assertIsNone(re.search(r'\bgoto\b|coroutine|debug\.traceback|%q', code), path.name)
            self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', code.replace('~=', '')), path.name)

    def test_suites_tagged_world_and_server(self):
        for name, path in SUITE_FILES.items():
            text = path.read_text(encoding='utf-8')
            self.assertIn(f'RST.suite("{name}", {{ tags = {{ "world", "server" }}', text, name)


if __name__ == '__main__':
    unittest.main()
