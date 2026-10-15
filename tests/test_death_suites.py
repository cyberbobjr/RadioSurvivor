"""Banc hors jeu de la vraie mort du client 2 (E00-T02, E03-T04, E15-T02) : suite rs.death (RS_Death.lua), étapes
client de RST_PeerChecksDeath.lua (death.prepare, death.corpse, death.after) et reprise après la mort par le pilote
RST_AutoClient.lua (bouton Respawn de l'écran de mort, création du personnage en jeu).

    python RadioSurvivor/tests/test_death_suites.py

Le VRAI moteur RST (RST.lua, RST_Steps.lua, RST_Fixtures.lua, RST_PeerChecksRadio.lua, RST_PeerChecks2.lua) et le
vrai pilote tournent sur un serveur dédié simulé et deux clients (une machine lupa chacun, `next` retiré comme dans
Kahlua, réseau en file livré au tick suivant). Doublures : joueurs (mode dieu, mort serveur `die()` qui déclenche
OnCharacterDeath AVANT de créer le cadavre, qui prend le même conteneur ; paquet de mort vers le client avec
l'inventaire du cadavre ; ExtraInfo du client appliqué au serveur), écran de mort et création de personnage en jeu
(ISPostDeathUI, CoopCharacterCreation : nouvel IsoPlayer, OnCreatePlayer puis hello), serveur du carnet réduit à
identity / hello / characterDeath avec les MÊMES règles que RS_Carnet_Server.lua (propriétaire, retraite, liaison).
Chaque critère est contredit par un défaut injecté (DEFECTS) que la suite doit faire échouer. Ce banc ne prouve ni le
Java (paquets PlayerDeath et ExtraInfo, écran de mort) ni le vrai serveur du carnet (test_carnet.py) : la campagne MP
à deux clients reste nécessaire.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
DEV = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
RST_DIR = DEV / 'shared' / 'RST'
SUITE = RST_DIR / 'suites' / 'RS_Death.lua'
PEER = RST_DIR / 'RST_PeerChecksDeath.lua'
DRIVER = DEV / 'client' / 'RST' / 'RST_AutoClient.lua'
LOADED = ['RST_Steps.lua', 'RST_Fixtures.lua', 'RST_PeerChecksRadio.lua', 'RST_PeerChecks2.lua',
          'RST_PeerChecksDeath.lua']

JAVA = r'''
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
getTimestamp = function() return math.floor(CLOCK / 1000) end
isServer = function() return ROLE == "server" end
isClient = function() return ROLE == "client" end
isDebugEnabled = function() return true end
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
getWorld = function() return { getWorld = function() return "rstest_death" end,
    getGameMode = function() return "Multiplayer" end } end
getCore = function() return { getVersion = function() return "42.21.0 bench" end } end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    e.Remove = function(f) for i, g in ipairs(e.list) do if g == f then table.remove(e.list, i) return end end end
    rawset(t, k, e) return e end })
function fire(name, ...) local copy = {} for i, f in ipairs(Events[name].list) do copy[i] = f end
    for _, f in ipairs(copy) do f(...) end end
getFileWriter = function(name, create, append)
    local full = FILE_ROOT .. "/" .. name
    mkdirs(full)
    local f = assert(io.open(full, append and "a" or "w"))
    return { write = function(self, s) f:write(s) end, writeln = function(self, s) f:write(s, "\n") end,
        close = function(self) f:close() end }
end
getFileReader = function(name)
    local f = io.open(FILE_ROOT .. "/" .. name, "r")
    if not f then return nil end
    return { readLine = function(self) return f:read("*l") end, close = function(self) f:close() end }
end
getText = function(k) return k end
function JList(items)
    local l = { items = items or {} }
    function l:size() return #self.items end
    function l:get(i) return self.items[i + 1] end
    function l:add(v) self.items[#self.items + 1] = v return true end
    function l:remove(v) for i, x in ipairs(self.items) do if x == v then table.remove(self.items, i) return true end end
        return false end
    function l:contains(v) for _, x in ipairs(self.items) do if x == v then return true end end return false end
    return l
end
function CLASSES(...) local c = {} for _, n in ipairs({ ... }) do c[n] = true end return c end
instanceof = function(o, c) return type(o) == "table" and type(o.classes) == "table" and o.classes[c] == true end
local squares = {}
CELL = {}
function CELL:getGridSquare(x, y, z)
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    if math.abs(x - 1000) > 60 or math.abs(y - 1000) > 60 then return nil end
    local key = x .. "," .. y .. "," .. z
    local sq = squares[key]
    if sq == nil then
        sq = { x = x, y = y, z = z, statics = JList({}) }
        function sq:getX() return self.x end
        function sq:getY() return self.y end
        function sq:getZ() return self.z end
        function sq:getStaticMovingObjects() return self.statics end
        function sq:removeCorpse(b, remote) self.statics:remove(b); b.square = nil
            if isServer() and not remote then PY_SEND("bcast", "removeCorpse", { x = b.x, y = b.y, z = b.z }) end end
        squares[key] = sq
    end
    return sq
end
getCell = function() return CELL end
ITEM_ID = 0
function newItem(fullType)
    ITEM_ID = ITEM_ID + 1
    local it = { id = ITEM_ID, fullType = fullType, name = fullType, md = nil }
    function it:getFullType() return self.fullType end
    function it:getName() return self.name end
    function it:setName(n) self.name = n end
    function it:setCustomName(b) self.custom = b end
    function it:hasModData() return self.md ~= nil end
    function it:getModData() self.md = self.md or {} return self.md end
    return it
end
instanceItem = function(t) return newItem(t) end
function newContainer()
    local c = { items = JList({}) }
    function c:getItems() return self.items end
    function c:AddItem(it) self.items:add(it); it.container = self; return it end
    function c:contains(it) return self.items:contains(it) end
    return c
end
function newCorpse(x, y, z, inv, isPlayer)
    local b = { classes = CLASSES("IsoDeadBody", "IsoMovingObject"), x = x, y = y, z = z, inv = inv, player = isPlayer }
    function b:getX() return self.x + 0.5 end
    function b:getY() return self.y + 0.5 end
    function b:getContainer() return self.inv end
    function b:isPlayer() return self.player end
    function b:getSquare() return self.square end
    local sq = CELL:getGridSquare(x, y, z)
    sq.statics:add(b); b.square = sq
    return b
end
PLAYERS, ONLINE = {}, {}
function makePlayer(user, x, y, z)
    local p = { classes = CLASSES("IsoPlayer", "IsoGameCharacter", "IsoMovingObject"), user = user, x = x, y = y,
        z = z, md = {}, inv = newContainer(), god = true, dead = false, forename = "Bob" .. ITEM_ID }
    ITEM_ID = ITEM_ID + 1
    function p:getUsername() return self.user end
    function p:getPlayerNum() return 0 end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:isDead() return self.dead end
    function p:isOnFire() return false end
    function p:getVehicle() return nil end
    function p:isGodMod() return self.god end
    function p:setGodMod(b) if not self.dead and (b == false or GOD_ALLOWED) then self.god = b end end
    function p:getModData() return self.md end
    function p:getInventory() return self.inv end
    function p:getCurrentSquare() return CELL:getGridSquare(self.x, self.y, self.z) end
    function p:getDescriptor() local s = self return { getForename = function() return s.forename end,
        getSurname = function() return "Test" end } end
    function p:die()
        if self.dead then return end
        self.dead = true
        fire("OnCharacterDeath", self)                    -- before the corpse (IsoGameCharacter.die)
        local inv = self.inv
        if not DEFECT.noCorpseItems then
            self.corpse = newCorpse(math.floor(self.x), math.floor(self.y), math.floor(self.z), inv, true)
        else
            self.corpse = newCorpse(math.floor(self.x), math.floor(self.y), math.floor(self.z), newContainer(), true)
        end
        self.inv = newContainer()
        local items = {}
        for _, it in ipairs(self.corpse.inv.items.items) do
            items[#items + 1] = { t = it.fullType, name = it.name, mark = it.md and it.md.rsLastPagesWitness or nil }
        end
        -- PlayerDeath packet to every connection in range (GameServer.sendCharacterDeath).
        PY_SEND("bcast", "death", { user = self.user, x = math.floor(self.x), y = math.floor(self.y),
            z = math.floor(self.z), items = items })
    end
    PLAYERS[user] = p
    return p
end
GOD_ALLOWED = true
getOnlinePlayers = function() return JList(ONLINE) end
'''

SERVER = r'''
DEFECT = DEFECT or {}
for _, u in ipairs(USERS) do ONLINE[#ONLINE + 1] = makePlayer(u, 1000.5, 1000.5, 0) end
sendServerCommand = function(player, module, command, args) PY_SEND("s2c", player:getUsername(), module, command, args) end
-- Zombie double: a character that is not an IsoPlayer.
addZombiesInOutfit = function(x, y, z, n)
    local zed = { classes = CLASSES("IsoZombie", "IsoGameCharacter"), md = {} }
    function zed:getModData() return self.md end
    function zed:getUsername() return nil end
    function zed:removeFromWorld() self.removed = true end
    function zed:removeFromSquare() end
    function zed:isDead() return false end
    return JList({ zed })
end
-- Packets of the clients.
function SERVER_PACKET(kind, sender, args)
    if kind == "extra" then
        local p
        for _, o in ipairs(ONLINE) do if o.user == sender and not o.dead then p = o end end
        if p and not DEFECT.godKept then p:setGodMod(args.god) end
    elseif kind == "respawn" then
        local old = PLAYERS[sender]
        local p = makePlayer(sender, old.x + (DEFECT.farSpawn and 0 or 0), old.y, old.z)
        p.god = false
        ONLINE[#ONLINE + 1] = p
    end
end

-- Notebook server double: identity(), hello and characterDeath with the rules of RS_Carnet_Server.lua.
package.loaded["RadioSurvivor/RS_Config"] = { VERSION = 2, MODULE = "RS_Carnet", OFFER_TTL_MS = 3600000,
    Missions = { deliver = { id = "first_aid_v1", titleKey = "IGUI_RS_FirstAid", quantity = 6, durationMs = 7200000,
        accepted = { ["Base.Bandage"] = true }, rewardType = "Base.Bullets9mm", rewardCount = 20 } } }
KEY = "RS_CarnetCharacter"
DATA = { world = "w1", characters = {}, missions = {}, npcs = {} }
-- Living Knox test NPC (LivingKnox.API.testSpawnNpc) seen by the provider (RS_NPCProvider) at once.
NPCS, NPC_SEQ = {}, 0
LivingKnox = { API = {
    testSpawnNpc = function(x, y, z) NPC_SEQ = NPC_SEQ + 1 local id = "lk-" .. NPC_SEQ
        NPCS[id] = { id = id, x = x, y = y, z = z } return id end,
    testRemoveNpc = function(id) if not NPCS[id] then return false, "unknown" end NPCS[id] = nil return true end } }
package.loaded["RadioSurvivor/RS_NPCProvider"] = { active = function() return { name = "livingknox" } end,
    available = function() return true end, objects = function() return NPCS end, id = function(b) return b.id end }
-- RS_Missions.accept with the rules of RS_Missions.lua.
package.loaded["RadioSurvivor/RS_Missions"] = { accept = function(state, m, character, name)
    if not m or not m.invited[character] or m.transaction or (m.state ~= "offer" and m.state ~= "active") then
        return false end
    if m.participants[character] then return true end
    if m.state == "offer" then m.state = "active" end
    m.participants[character] = { name = name }
    m.revision = m.revision + 1
    return true end }
SAVES, SEQ = 0, 0
RS_CarnetServer = { store = { data = DATA, run = "r1", save = function() SAVES = SAVES + 1 return true end },
    bound = {} }
local Server = RS_CarnetServer
function Server.ensure(id)
    if not NPCS[id] then return nil end
    for _, f in pairs(DATA.npcs) do if f.incarnation == id then return f end end
    local f = { id = "npc-" .. id, incarnation = id, name = "Test " .. id, alive = true, revision = 1 }
    DATA.npcs[f.id] = f
    return f
end
local function ownerOf(p) return p:getUsername() end
local function usable(id, owner)
    local r = type(id) == "string" and DATA.characters[id] or nil
    return r and r.owner == owner and (DEFECT.reclaim or not r.retired)
end
local function send(p, command, args) args.world, args.run = DATA.world, "r1"; sendServerCommand(p, "RS_Carnet", command, args) end
local function identity(player, claimed)
    if Server.bound[player] then send(player, "identity", { character = Server.bound[player] }) return end
    local owner = ownerOf(player)
    local stored = player:getModData()[KEY]
    if usable(stored, owner) then claimed = stored
    elseif not usable(claimed, owner) then
        SEQ = SEQ + 1
        claimed = "char-" .. SEQ
        local known = {}
        if DEFECT.resume then
            for _, r in pairs(DATA.characters) do
                if r.owner == owner and r.retired then for k in pairs(r.knownMissions) do known[k] = true end end
            end
        end
        DATA.characters[claimed] = { id = claimed, owner = owner, slot = 0, contacts = {}, knownMissions = known }
    end
    player:getModData()[KEY] = claimed
    Server.bound[player] = claimed
    send(player, "identity", { character = claimed })
end
function Server.command(module, command, player, args)
    if module ~= "RS_Carnet" or not player then return end
    if type(args) ~= "table" then args = {} end
    if player:isDead() then return end
    if command == "hello" then identity(player, args.character) end
end
function Server.characterDeath(chr)
    if not DEFECT.zombieRetires and not instanceof(chr, "IsoPlayer") then return end
    local md = chr:getModData()
    local id = Server.bound[chr] or md[KEY]
    local record = type(id) == "string" and DATA.characters[id] or nil
    if not record or record.retired then return end
    if not DEFECT.zombieRetires and record.owner ~= ownerOf(chr) then return end
    if not DEFECT.noRetire then record.retired = true end
    if DEFECT.closeMissions then
        for _, m in pairs(DATA.missions) do if m.participants[id] then m.state = "cancelled" end end
    end
    if not DEFECT.keepBinding then md[KEY] = nil; Server.bound[chr] = nil end
end
Events.OnClientCommand.Add(Server.command)
Events.OnCharacterDeath.Add(Server.characterDeath)
'''

CLIENT = r'''
package.loaded["RadioSurvivor/RS_Config"] = { VERSION = 2, MODULE = "RS_Carnet" }
LOCAL_PLAYER = makePlayer(USER, 1000.5, 1000.5, 0)
getPlayer = function() return LOCAL_PLAYER end
getSpecificPlayer = function() return LOCAL_PLAYER end
sendClientCommand = function(player, module, command, args) PY_SEND("c2s", module, command, args) end
sendPlayerExtraInfo = function(p) PY_SEND("pkt", "extra", { god = p.god }) end
sendServerCommand = function() error("sendServerCommand on a client") end
-- Notebook client double (RS_Client): hello at game start and at OnCreatePlayer(0); identity kept.
RS_CarnetClient = { character = nil }
local CC = RS_CarnetClient
function CC.send(command, args) sendClientCommand(getPlayer(), "RS_Carnet", command, args or {}) end
function CC.receive(command, args) if command == "identity" then CC.character = args.character end end
function CC.hello() CC.send("hello", { v = 2, character = getPlayer():getModData()[KEY] }) end
KEY = "RS_CarnetCharacter"
Events.OnServerCommand.Add(function(m, c, a) if m == "RS_Carnet" then CC.receive(c, a or {}) end end)
Events.OnCreatePlayer.Add(function(num) if num == 0 then CC.hello() end end)
-- Death packet (PlayerDeath): the client copy dies, its corpse holds the inventory of the server corpse.
function onDeathPacket(a)
    local mine = a.user == USER
    if mine then LOCAL_PLAYER.dead = true end
    if not (DEFECT.clientNoCorpse and not mine) then
        local inv = newContainer()
        for _, e in ipairs(a.items or {}) do
            local it = newItem(e.t)
            it.name = e.name
            if e.mark then it:getModData().rsLastPagesWitness = e.mark end
            inv:AddItem(it)
        end
        newCorpse(a.x, a.y, a.z, inv, true)
    end
    if not mine then return end
    fire("OnPlayerDeath", LOCAL_PLAYER)
    if not DEFECT.noPostDeath then ISPostDeathUI.instance[0] = POST end
end
function CLIENT_PACKET(kind, args)
    if kind == "death" then onDeathPacket(args) end
    if kind == "removeCorpse" then
        local sq = CELL:getGridSquare(args.x, args.y, args.z)
        for _, b in ipairs(sq.statics.items) do sq.statics:remove(b) break end
    end
end
-- Post-death screen and in-game character creation (ISPostDeathUI, CoopCharacterCreation).
local function panel(onNext)
    local pnl = { visible = false }
    function pnl:getIsVisible() return self.visible end
    function pnl:onOptionMouseDown(b) if b.internal == "NEXT" then onNext(self) end end
    return pnl
end
ISPostDeathUI = { instance = {} }
CoopCharacterCreation = {}
POST = {}
function POST:onRespawn()
    local w = {}
    w.mapSpawnSelect = panel(function() end)
    function w.mapSpawnSelect:clickNext() self.visible = false; w.charCreationProfession.visible = true end
    w.charCreationMain = panel(function(pnl)
        pnl.visible = false
        CoopCharacterCreation.instance = nil
        ISPostDeathUI.instance[0] = nil
        LOCAL_PLAYER = makePlayer(USER, 1000.5, 1000.5, 0)
        LOCAL_PLAYER.god = false
        PY_SEND("pkt", "respawn", {})
        fire("OnCreatePlayer", 0)
    end)
    w.charCreationProfession = panel(function(pnl) pnl.visible = false; w.charCreationMain.visible = true end)
    if SPAWN_CHOICE then w.mapSpawnSelect.visible = true else w.charCreationProfession.visible = true end
    CoopCharacterCreation.instance = w
end
'''


def to_py(value):
    if lupa.lua_type(value) == 'table':
        out = {}
        for k, v in value.items():
            if isinstance(k, (str, int, float)) and not isinstance(k, bool):
                conv = to_py(v)
                if conv is not None:
                    out[k] = conv
        return out
    if isinstance(value, (str, int, float, bool)):
        return value
    return None


class Machine:
    def __init__(self, net, name, role, defects):
        self.net, self.name, self.role = net, name, role
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.g = self.rt.globals()
        g.next = None  # absent de Kahlua
        root = net.root / name
        root.mkdir(parents=True, exist_ok=True)
        g.ROLE, g.FILE_ROOT, g.USER = role, root.as_posix(), name
        g.mkdirs = lambda full: Path(full).parent.mkdir(parents=True, exist_ok=True)
        paths = [DEV / 'shared'] + ([DEV / 'client'] if role == 'client' else [])
        self.rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')
        g.PY_SEND = lambda kind, *a: net.send(name, kind, *a)
        self.rt.execute('DEFECT = {' + ', '.join(f'{d} = true' for d in defects) + '}')
        self.rt.execute(JAVA)

    def lua(self, code):
        return self.rt.execute(code)

    def table(self, data):
        if isinstance(data, dict):
            return self.rt.table_from({k: self.table(v) for k, v in data.items()})
        if isinstance(data, list):
            return self.rt.table_from([self.table(v) for v in data])
        return data


class Net:
    def __init__(self, root, users=('rs_mp1', 'rs_mp2'), defects=(), spawn_choice=False):
        self.root, self.queue = root, []
        self.server = Machine(self, 'server', 'server', defects)
        self.server.g.USERS = self.server.table(list(users))
        self.server.lua(SERVER)
        self.clients = {}
        for u in users:
            c = Machine(self, u, 'client', defects)
            c.g.SPAWN_CHOICE = spawn_choice
            c.lua(CLIENT)
            self.clients[u] = c
        for m in self.machines():
            m.lua('require "RST/RST"')
            for f in LOADED:
                m.lua(f'dofile([[{(RST_DIR / f).as_posix()}]])')
            m.lua(f'dofile([[{SUITE.as_posix()}]])')
        for c in self.clients.values():
            c.lua(f'dofile([[{DRIVER.as_posix()}]])')
            c.lua('RST.AutoClient._cmdRead = true; RST.AutoClient._cmd = { mp = true, peer = true, token = "tok" }; '
                  'RST.AutoClient.status("idle", "connected, nothing to run")')
            c.lua('RS_CarnetClient.hello()')
        for _ in range(3):
            self.tick()

    def machines(self):
        return [self.server, *self.clients.values()]

    def send(self, sender, kind, *a):
        self.queue.append((sender, kind, [to_py(x) if lupa.lua_type(x) == 'table' else x for x in a]))

    def pump(self):
        while self.queue:
            sender, kind, a = self.queue.pop(0)
            s = self.server
            if kind == 'c2s':
                module, command, args = a
                player = s.lua(f'for i = #ONLINE, 1, -1 do local p = ONLINE[i] if p.user == "{sender}" and not p.dead '
                               f'then return p end end return PLAYERS["{sender}"]')
                s.g.fire('OnClientCommand', module, command, player, s.table(args or {}))
            elif kind == 's2c':
                user, module, command, args = a
                c = self.clients.get(user)
                if c is not None:
                    c.g.fire('OnServerCommand', module, command, c.table(args or {}))
            elif kind == 'pkt':
                packet, args = a
                s.g.SERVER_PACKET(packet, sender, s.table(args or {}))
            elif kind == 'bcast':
                packet, args = a
                for c in self.clients.values():
                    c.g.CLIENT_PACKET(packet, c.table(args or {}))

    def tick(self, dt=100):
        self.pump()
        for m in self.machines():
            m.g.CLOCK = m.g.CLOCK + dt
        self.server.g.fire('OnTickEvenPaused')
        self.server.g.fire('OnTick')
        for c in self.clients.values():
            c.g.fire('OnTickEvenPaused')
            c.g.fire('OnTick')
        self.pump()

    def run(self, suite='rs.death', requester='rs_mp1', limit=8000):
        s = self.server
        s.lua(f'REPORT = nil; assert(RST.start({{ suite = "{suite}", tags = {{ "server", "world" }} }}, '
              f'{{ ctx = {{ side = "server", player = PLAYERS["{requester}"] }}, onDone = function(r) REPORT = r end }}))')
        for _ in range(limit):
            if not s.lua('return RST.running()'):
                rep = s.g.REPORT
                return {r.test: (r.status, r.message, [n for _, n in (r.notes or {}).items()])
                        for _, r in rep.results.items()}
            self.tick()
        raise AssertionError('run not over')


DEATH = 'client 2 dies'
NEWCHAR = 'new character'


def pick(results, part):
    hits = [v for k, v in results.items() if part in k]
    assert len(hits) == 1, (part, results)
    return hits[0]


class Bench(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-death-')
        self.n = 0

    def tearDown(self):
        self.tmp.cleanup()

    def net(self, **kw):
        self.n += 1
        return Net(Path(self.tmp.name) / f'run{self.n}', **kw)

    def status(self, res, part, expected, message=None):
        st, msg, _ = pick(res, part)
        self.assertEqual(st, expected, f'{part}: {st} {msg}')
        if message is not None:
            self.assertIn(message, msg or '')


class DeathSuiteTests(Bench):
    def test_two_clients_pass(self):
        net = self.net()
        res = net.run()
        self.status(res, DEATH, 'PASS')
        self.status(res, NEWCHAR, 'PASS')
        s = net.server
        # Old identity retired, new one of the same account bound, extra claim record removed, corpse removed.
        self.assertTrue(s.lua('return DATA.characters["char-2"].retired'))
        self.assertEqual(s.lua('local n = 0 for _ in pairs(DATA.characters) do n = n + 1 end return n'), 3)
        self.assertEqual(s.lua('return RS_CarnetServer.bound[ONLINE[3]]'), 'char-3')
        self.assertEqual(s.lua('return CELL:getGridSquare(1000, 1000, 0):getStaticMovingObjects():size()'), 0)
        self.assertEqual(net.clients['rs_mp2'].lua('return CELL:getGridSquare(1000, 1000, 0)'
                                                   ':getStaticMovingObjects():size()'), 0)
        # God mode given back to the new character (client and server), marked mission gone.
        self.assertTrue(net.clients['rs_mp2'].lua('return LOCAL_PLAYER.god'))
        self.assertTrue(s.lua('return ONLINE[3].god'))
        self.assertFalse(s.lua('for _, r in pairs(DATA.characters) do for k in pairs(r.knownMissions) do '
                               'if string.find(k, "rst%-death") then return true end end end return false'))
        # E00-T02: the shared mission went on for the requester, then was removed with its test NPC.
        self.assertEqual(s.lua('local n = 0 for _ in pairs(DATA.missions) do n = n + 1 end return n'), 0)
        self.assertEqual(s.lua('local n = 0 for _ in pairs(NPCS) do n = n + 1 end return n'), 0)
        self.assertTrue(any('shared mission' in n and 'after the death of rs_mp2: active' in n
                            for n in pick(res, DEATH)[2]), pick(res, DEATH)[2])
        notes = ' '.join(pick(res, NEWCHAR)[2])
        self.assertIn('char-2 (dead) -> char-3', notes)
        # Respawn lines of the driver keep the state "idle".
        status = net.root / 'rs_mp2' / 'batman_RadioSurvivor' / 'tests' / 'autoclient-status.txt'
        self.assertTrue(status.exists(), status)
        lines = status.read_text(encoding='utf-8').splitlines()
        self.assertTrue(any('tok idle respawn: new character' in line for line in lines), lines)
        self.assertTrue(all(line.split(' ')[1] == 'idle' for line in lines), lines)

    def test_spawn_choice_screen_is_passed(self):
        res = self.net(spawn_choice=True).run()
        self.status(res, NEWCHAR, 'PASS')

    def test_one_client_skips(self):
        res = self.net(users=('rs_mp1',)).run()
        self.status(res, DEATH, 'SKIP', 'no second client')
        self.status(res, NEWCHAR, 'SKIP', 'no second client')

    def test_detects_identity_not_retired(self):
        res = self.net(defects=('noRetire',)).run()
        self.status(res, DEATH, 'FAIL', 'not retired')

    def test_detects_binding_kept(self):
        res = self.net(defects=('keepBinding',)).run()
        self.status(res, DEATH, 'FAIL', 'old IsoPlayer still bound')

    def test_detects_zombie_retiring(self):
        res = self.net(defects=('zombieRetires',)).run()
        self.status(res, DEATH, 'FAIL', 'zombie carrying')

    def test_detects_paper_lost_in_corpse(self):
        res = self.net(defects=('noCorpseItems',)).run()
        self.status(res, DEATH, 'FAIL', 'no corpse of rs_mp2 holding the witness paper')

    def test_detects_paper_missing_on_requester_client(self):
        res = self.net(defects=('clientNoCorpse',)).run()
        self.status(res, DEATH, 'FAIL', "step 'death.corpse' FAIL")

    def test_detects_god_mode_kept(self):
        res = self.net(defects=('godKept',)).run()
        self.status(res, DEATH, 'FAIL', 'still in god mode on the server')

    def test_detects_old_identity_reclaimed(self):
        res = self.net(defects=('reclaim',)).run()
        self.status(res, NEWCHAR, 'FAIL', 'claimed again')

    def test_detects_old_missions_resumed(self):
        res = self.net(defects=('resume',)).run()
        self.status(res, NEWCHAR, 'FAIL', 'knows the old marked mission')

    def test_detects_shared_mission_closed_by_the_death(self):
        res = self.net(defects=('closeMissions',)).run()
        self.status(res, DEATH, 'FAIL', 'state of the shared mission')

    def test_detects_no_respawn(self):
        net = self.net(defects=('noPostDeath',))
        net.server.lua('RST.DeathSuite.RESPAWN_MS = 20000')
        res = net.run()
        self.status(res, DEATH, 'PASS')
        self.status(res, NEWCHAR, 'FAIL', 'no living new character')


class SourceTests(unittest.TestCase):
    def test_ascii_and_english(self):
        for path in (SUITE, PEER):
            text = path.read_text(encoding='utf-8')
            self.assertTrue(text.isascii(), path)


if __name__ == '__main__':
    unittest.main()
