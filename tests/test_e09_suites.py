"""Banc hors jeu des tests en jeu E09-T04, E09-T05, E09-T06 et E10-T02 (rs.relation, rs.factions.accord,
rs.factions.incident, rs.carnet.leader) et de leurs aides d'autorité (RST_PeerChecksE09.lua).

    python RadioSurvivor/tests/test_e09_suites.py

Chaque suite est jouée par le VRAI moteur RST (RST.lua, RST_Steps.lua, RST_Fixtures.lua, RST_PeerChecks.lua,
RST_RSHelpers.lua, RST_LKGroupFixture.lua) en solo et sur un serveur dédié simulé avec deux clients (machines lupa,
`next` retiré comme dans Kahlua, réseau en file livré au tick suivant ; doublures Java de tests/test_rs_mp_suites.py).
Réels ici : RS_State, RS_Config, RS_Codec, RS_Relations, RS_Observations, RS_Factions (accords et incidents, doublure
de Faction de tests/test_factions.py), RS_Incidents, LK_Core. Doublures : moteur Living Knox réduit (groupes, corps,
attitude et faits, choix de cible réduit aux règles incident / couvert), serveur du carnet réduit à ce que lisent les
tests (hello, select, talk avec contexte relation / collectif / accord, file de requêtes, lecture du fichier de
réponses par RS_Transport.readNpc, application des réponses : change_relation, negotiate avec revalidation du chef et
de la composition, décision d'incident par RS_Incidents.reply), client du carnet réduit (send, talk, attente).
Les réponses du modèle sont celles que les tests déposent eux-mêmes (E9.intercept) : aucun pont.
Chaque test passe sur les doublures et échoue sur un défaut injecté (DEFECT) qui contredit son critère. Ce banc ne
prouve ni l'API Java ni le vrai serveur du carnet (test_carnet, test_relations, test_agreements, test_incidents) :
l'exécution en jeu (campagnes solo et MP à deux clients) reste nécessaire.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rs_mp_suites import Machine, Report, to_py  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEV = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SUITES = DEV / 'shared' / 'RST' / 'suites'
SUITE_FILES = [SUITES / f'{n}.lua' for n in ('RS_Relation', 'RS_FactionsAccord', 'RS_FactionsIncident', 'RS_CarnetLK')]

AUTHORITY = r'''
DEFECT = DEFECT or {}
C = require "RadioSurvivor/RS_Config"
S = require "RadioSurvivor/RS_State"
assert(S.init(true))
RS_RadioServer = { bench = true }
for _, p in pairs(PLAYERS) do
    p.god = false
    function p:isGodMod() return self.god end
    function p:setGodMod(b) self.god = b end
end
if LOCAL_PLAYER then
    LOCAL_PLAYER.god = false
    function LOCAL_PLAYER:isGodMod() return self.god end
    function LOCAL_PLAYER:setGodMod(b) self.god = b end
end
-- Melee weapon of the incident tests (instanceItem of the radio doubles knows radios only).
local radioItem = instanceItem
instanceItem = function(fullType)
    if fullType == "Base.BaseballBat" then
        return { classes = CLASSES("HandWeapon", "InventoryItem"), fullType = fullType,
            getFullType = function(self) return self.fullType end }
    end
    return radioItem(fullType)
end
-- fx.move of RST_Fixtures: the server copy follows at once (the game sends the position back).
local baseSend = sendServerCommand
sendServerCommand = function(...)
    local a, b, c, d = ...
    if type(a) == "table" and b == "RST" and c == "fx.move" and type(d) == "table" then
        a.x, a.y, a.z = d.x, d.y, d.z
    end
    return baseSend(...)
end

-- Living Knox reduced: groups, bodies (embodied at once near the home), facts and attitude, target rule.
require "LivingKnox/LK_Core"
local LK = LivingKnox
LK.Config = { isEnabled = function() return true end }
BODIES, GROUPS, LKNPCS = {}, {}, {}
local npcSeq, groupSeq = 0, 0
DAY = 5
local function body(id, x, y, z)
    local b = { classes = CLASSES("IsoZombie", "IsoGameCharacter"), id = id, x = x + 0.5, y = y + 0.5, z = z }
    function b:getX() return self.x end
    function b:getY() return self.y end
    function b:getZ() return self.z end
    function b:isDead() return false end
    function b:isOnFloor() return false end
    function b:getSquare() return CELL:getGridSquare(self.x, self.y, self.z) end
    return b
end
local function groupOf(npc)
    for gid, g in pairs(GROUPS) do
        for mid, m in pairs(g.members) do if m.npc == npc then return gid, mid end end
    end
end
LK.Groups = {
    ensure = function() return true end,
    today = function() return DAY end,
    create = function(spec)
        groupSeq = groupSeq + 1
        local g = { id = "grp-" .. groupSeq, members = {}, n = 0, home = spec.home, name = spec.name }
        GROUPS[g.id] = g
        return { id = g.id }
    end,
    addMember = function(gid, spec)
        local g = GROUPS[gid]
        g.n = g.n + 1
        local mid = "m-" .. g.n
        npcSeq = npcSeq + 1
        local id = "lk-" .. npcSeq
        LKNPCS[id] = true
        BODIES[id] = body(id, g.home.x + g.n, g.home.y + 1, g.home.z)
        g.members[mid] = { npc = id, alive = true }
        return mid
    end,
    setLeader = function(gid, mid)
        local g = GROUPS[gid]
        if not g or not g.members[mid] or not g.members[mid].alive then return nil, "bad member" end
        g.leader = mid
        return true
    end,
    markDead = function(gid, mid)
        local g = GROUPS[gid]
        g.members[mid].alive = false
        if g.leader == mid then g.leader = nil end
        return true
    end,
    get = function(gid) return GROUPS[gid] end,
    findNpc = function(npc) return groupOf(npc) end,
    remove = function(gid)
        local g = GROUPS[gid]
        for _, m in pairs(g and g.members or {}) do BODIES[m.npc] = nil end
        GROUPS[gid] = nil
    end,
}
LK.API = { composition = function(gid)
    local g = GROUPS[gid]
    if not g then return nil, "unknown group" end
    local living = {}
    for mid, m in pairs(g.members) do if m.alive then living[#living + 1] = mid end end
    table.sort(living)
    local leader = g.leader and g.members[g.leader].alive and g.leader or nil
    return { group = gid, leader = leader, leaderNpc = leader and g.members[leader].npc or nil, alive = #living,
        members = living, key = (leader or "-") .. "|" .. table.concat(living, ",") }
end }
LK.Homes = { skip = function() end }
LK.Senses = { perceived = function() return { p = {} } end }
LK.Directives = { forget = function() end }
LK.Decisions = { aims = function() return { seq = 1, members = {} } end }
LK.Bodies = {
    find = function(id) return BODIES[id] end,
    despawn = function(id) BODIES[id] = nil; return true end,
    onHitZombie = function(b, player, _, weapon)
        local gid = groupOf(b.id)
        if gid and weapon then
            LK.publish("memberHit", { group = gid, npc = b.id, player = player, category = "melee", ms = getTimestampMs() })
        end
    end,
}
local SIGNS = { gift = 1, theft = -1, hit = -1 }
local PAIRS, factSeq = {}, 0
LK.Hostility = {
    state = { data = { groups = PAIRS } },
    save = function() return true end,
    record = function(gid, key, fact, opts)
        if not GROUPS[gid] or SIGNS[fact] == nil then return nil, "bad fact" end
        PAIRS[gid] = PAIRS[gid] or {}
        local p = PAIRS[gid][key] or { facts = {} }
        PAIRS[gid][key] = p
        factSeq = factSeq + 1
        p.facts[#p.facts + 1] = { n = factSeq, fact = fact, sign = SIGNS[fact], day = DAY }
        return { level = "cautious" }
    end,
    get = function() return { level = "cautious" } end,
    debugPair = function(gid, key) return PAIRS[gid] and PAIRS[gid][key] end,
    keyOf = function(p) return Server.bound[p] end,
    isCovered = function(gid, key, npc) return LK.Hooks.covered(gid, key, npc) end,
    chooseTarget = function(gid, npc, cands)
        local list = {}
        for _, c in ipairs(cands) do
            if c.key and LK.Hooks.incident(gid, c.key, npc) then
                list[#list + 1] = { u = c.u, key = c.key, d = c.d, action = "attack", reason = "incident" }
            end
        end
        table.sort(list, function(a, b) return a.d < b.d end)
        return { target = list[1], list = list }
    end,
}

-- Notebook provider over these bodies (RS_NPCProvider interface used by RS_Relations, RS_Incidents, the suites).
local function dist(a, b)
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end
P = {
    active = function() return { name = "livingknox" } end,
    available = function() return true end,
    objects = function() local out = {} for id, b in pairs(BODIES) do out[id] = b end return out end,
    id = function(b) return b.id end,
    npc = function(id)
        if not LKNPCS[id] then return nil end
        return { signature = "lk:" .. id, name = "Npc " .. id, group = groupOf(id) or "" }
    end,
    relation = function(id, character)
        local gid = groupOf(id)
        if not gid then return nil end
        local pair = PAIRS[gid] and PAIRS[gid][character]
        local facts = {}
        for _, f in ipairs(pair and pair.facts or {}) do
            facts[#facts + 1] = { key = "att:" .. gid .. ":" .. f.n, fact = f.fact, sign = f.sign, day = f.day }
        end
        return { attitude = { level = "cautious", trend = "stable" }, facts = facts }
    end,
    context = function() return { member = true } end,
    near = function(a, b, range) return a ~= nil and b ~= nil and dist(a, b) <= range end,
    hears = function(a, b, range) return a ~= nil and b ~= nil and dist(a, b) <= range end,
}
package.loaded["RadioSurvivor/RS_NPCProvider"] = P
package.loaded["RadioSurvivor/RS_Transport"] = { readNpc = function() return BRIDGE end }
BRIDGE = nil

F = require "RadioSurvivor/RS_Factions"
Rel = require "RadioSurvivor/RS_Relations"
F.installHook()

-- Notebook server reduced (RS_Carnet_Server.lua: hello, select, talk with context, pending, reply, incidents).
Server = { store = S, bound = {}, selected = {}, objects = {}, pending = {}, refusals = {}, collectives = {},
    relations = {}, times = {}, initiatives = { bridge = { down = false, probeAt = 0 } } }
RS_CarnetServer = Server
local function players()
    if isServer() then local out = {} for i, n in ipairs(ONLINE) do out[i] = PLAYERS[n] end return out end
    return { getPlayer() }
end
local function send(player, command, args)
    args = args or {}
    if isServer() then sendServerCommand(player, C.MODULE, command, args)
    elseif RS_CarnetClient then RS_CarnetClient.receive(command, args) end
end
function Server.find(id) for _, npc in pairs(S.data.npcs) do if npc.incarnation == id then return npc end end end
function Server.ensure(id)
    if not P.npc(id) then return nil end
    local npc = Server.find(id)
    if not npc then
        npc = { id = S.uid("npc"), incarnation = id, alive = true, revision = 1, order = 0, name = "Npc " .. id,
            enrichState = "idle" }
        S.data.npcs[npc.id] = npc
    end
    return npc
end
function Server.collectiveBinding(npc)
    local gid = groupOf(npc.incarnation)
    local c = gid and LK.API.composition(gid)
    if not c then return nil end
    local leaderName = c.leaderNpc and ("Npc " .. c.leaderNpc) or ""
    return { ref = gid, key = c.key, leader = c.leaderNpc == npc.incarnation, leaderName = leaderName }
end
function Server.collectiveCheck(binding, npc)
    if type(binding) ~= "table" then return false, "collective intention without a group binding" end
    if DEFECT.noCollectiveCheck then return true end
    local now = Server.collectiveBinding(npc)
    if not now or now.ref ~= binding.ref then return false, "NPC no longer in the group" end
    if not now.leader then return false, "NPC no longer the group leader" end
    if now.key ~= binding.key then return false, "group composition changed" end
    return true
end
function Server.enqueue(npc, kind, character, text, language, context, offers)
    npc.order = npc.order + 1
    local req = { version = 2, kind = kind, id = "run-" .. npc.order .. "-" .. npc.id, world = "w", run = "run",
        npc = npc.id, character = character, order = npc.order, revision = npc.revision, text = text,
        sent = getTimestampMs(), context = context, offers = offers or {} }
    Server.pending[#Server.pending + 1] = req
    return req
end
function Server.syncTransport() return true end
Server.incidents = require "RadioSurvivor/RS_Incidents"
local function contactOf(cid, npc)
    local record = S.data.characters[cid]
    record.contacts[npc.id] = record.contacts[npc.id] or { history = {}, exchanges = 0 }
    return record.contacts[npc.id]
end
local function scan()
    local objects = {}
    for id, b in pairs(BODIES) do
        local npc = Server.find(id)
        if npc then objects[npc.id] = b end
    end
    Server.objects = objects
end
function Server.command(module, command, player, args)
    if module ~= C.MODULE or not player then return end
    args = args or {}
    if command == "hello" then
        local cid = "character-" .. player:getUsername()
        S.data.characters[cid] = S.data.characters[cid] or { id = cid, contacts = {}, knownMissions = {},
            owner = F.keyOf(player), name = player:getUsername() }
        Server.bound[player] = cid
        send(player, "identity", { character = cid })
        return
    end
    local cid = Server.bound[player]
    if not cid then return send(player, "error", { reason = "Identity" }) end
    scan()
    -- WALKED: the body walked out of sight once between the check of the suite and the command (refused, the selection
    -- cleared, as RS_Carnet_Server select / talk do).
    if WALKED and WALKED[command] then
        WALKED[command] = nil
        Server.selected[cid] = nil
        return send(player, "error", { reason = "Range" })
    end
    if command == "select" then
        local npc = Server.ensure(args.incarnation)
        if npc and Server.objects[npc.id] and P.near(player, Server.objects[npc.id], 6) then
            contactOf(cid, npc)
            Server.selected[cid] = npc.id
            send(player, "snapshot", {})
        else send(player, "error", { reason = "Range" }) end
    elseif command == "talk" then
        local npc = S.data.npcs[Server.selected[cid] or ""]
        if not npc then return send(player, "error", { reason = "Range" }) end
        local contact = contactOf(cid, npc)
        local stage = (contact.exchanges or 0) >= C.ACQUAINT_EXCHANGES and "acquainted" or "stranger"
        local relation, relBinding = Rel.offer(npc, cid)
        local context = { relation = relation, stage = stage }
        local group = Server.collectiveBinding(npc)
        local negotiation, signer = nil, nil
        if group and stage == "acquainted" then
            context.collective = group.leader and { speaker = "leader" }
                or { speaker = "member", leaderName = group.leaderName }
            if group.leader or DEFECT.memberNegotiates then
                negotiation = F.negotiation(player, group.ref)
                -- DEFECT.anyMember: a player without mandate is offered the terms of a team owner, who signs.
                if negotiation == nil and DEFECT.anyMember then
                    for _, q in ipairs(players()) do
                        if negotiation == nil then negotiation = F.negotiation(q, group.ref); signer = q end
                    end
                end
                if negotiation then
                    context.negotiation = { role = negotiation.role, terms = negotiation.terms,
                        revision = negotiation.revision }
                end
            end
        end
        local req = Server.enqueue(npc, "npc_talk", cid, args.text, "EN", context, {})
        if group and negotiation then
            Server.collectives[req.id] = { ref = group.ref, key = group.key, team = negotiation.team,
                revision = negotiation.revision, signer = signer }
        end
        if relBinding then Server.relations[req.id] = relBinding end
        send(player, "queued", { id = req.id })
    end
end
Events.OnClientCommand.Add(Server.command)

local function playerOf(cid)
    for _, p in ipairs(players()) do if Server.bound[p] == cid then return p end end
end
local function reply(req, result)
    local npc = S.data.npcs[req.npc]
    if type(result) ~= "table" or result.kind ~= "npc_reply" or result.id ~= req.id then return false, "not an npc_reply" end
    if result.revision ~= req.revision or result.order ~= req.order then return false, "field differs" end
    if req.kind == "npc_incident" then
        if DEFECT.lateIncidentAccepted then
            local b = Server.incidents.bindings[req.id]
            local inc = b and F.incident(b.incident)
            if inc then b.revision = inc.revision end
        end
        return Server.incidents.reply(Server, req, result, npc)
    end
    if req.kind ~= "npc_talk" then return true end
    if result.intent == "change_relation" and not DEFECT.relationIgnored then
        Rel.apply(npc, req.character, Server.relations[req.id], result.dir, result.fact)
    end
    if result.intent == "negotiate" then
        local neg = req.context.negotiation
        local binding = Server.collectives[req.id]
        local ok = type(neg) == "table" and neg.terms[result.offer] ~= nil
        if ok then ok = Server.collectiveCheck(binding, npc) end
        if ok then
            local expect = { team = binding.team, revision = binding.revision }
            if DEFECT.freshRevision then
                local a = F.agreementOf(binding.ref, binding.team)
                expect.revision = a and a.revision or 0
            end
            F.conclude(binding.signer or playerOf(req.character), binding.ref, result.offer, expect,
                { character = req.character })
        end
    end
    local contact = contactOf(req.character, npc)
    contact.history[#contact.history + 1] = { id = req.id, text = result.text }
    local speaker = playerOf(req.character)
    if speaker then send(speaker, "speech", { id = req.id }) end
    return true
end
local nextIncident = 0
Events.OnTickEvenPaused.Add(function()
    scan()
    if DEFECT.bridgeAlwaysUp then Server.initiatives.bridge.down = false end
    local T = require "RadioSurvivor/RS_Transport"
    local responses = T.readNpc() or {}
    local kept, used = {}, {}
    for _, req in ipairs(Server.pending) do
        local result = nil
        if not used[req.npc] then
            used[req.npc] = true   -- one request per fiche and pass, the oldest first (RS_Carnet_Server poll)
            result = responses[req.id]
        end
        if result then
            local ok, why = reply(req, result)
            if not ok then
                Server.refusals[#Server.refusals + 1] = { id = req.id, kind = req.kind, reason = tostring(why),
                    at = getTimestampMs() }
                local p = playerOf(req.character)
                if p then send(p, "error", { reason = "NoAnswer" }) end
            end
            Server.collectives[req.id], Server.relations[req.id] = nil, nil
        else
            kept[#kept + 1] = req
        end
    end
    Server.pending = kept
    local now = getTimestampMs()
    if now >= nextIncident then
        Server.incidents.tick(Server, now)
        nextIncident = now + 1000
    end
end)
'''

CLIENT_SIDE = r'''
SendCommandToServer = function() end   -- /teleportto of RST_Fixtures: the server copy already moved (AUTHORITY)
RS_CarnetClient = { waiting = false }
local CC = RS_CarnetClient
function CC.send(command, args) sendClientCommand(getPlayer(), "RS_Carnet", command, args or {}) end
function CC.isWaiting() return CC.waiting end
function CC.talk(text)
    CC.waiting, CC.lastTalkAt = true, getTimestampMs()
    CC.send("talk", { text = text })
    return true
end
function CC.receive(command, args)
    if command == "identity" then CC.character = args.character
    elseif command == "speech" then CC.waiting = false
    elseif command == "error" then CC.lastError, CC.waiting = args.reason, false end
end
if isClient() then
    Events.OnServerCommand.Add(function(m, c, a) if m == "RS_Carnet" then CC.receive(c, a or {}) end end)
end
'''

HELPERS = [DEV / 'shared' / 'RST' / n for n in ('RST_Steps.lua', 'RST_Fixtures.lua', 'RST_PeerChecks.lua',
                                                'RST_PeerChecksRadio.lua', 'RST_LKHelpers.lua',
                                                'RST_LKGroupFixture.lua', 'RST_RSHelpers.lua',
                                                'RST_PeerChecksE09.lua')]


class Net:
    """Serveur dédié et deux clients (ou solo) ; commandes en file, livrées au tick suivant."""

    def __init__(self, root: Path, users=('rs_mp1', 'rs_mp2'), solo=False, defects=(), walls=False, walked=False):
        from test_rs_mp_suites import Net as BaseNet
        self.root, self.queue, self.solo = root, [], solo
        self.server = Machine(self, 'solo' if solo else 'server', 'solo' if solo else 'server')
        self.clients = {}
        self.server.lua('DEFECT = {' + ', '.join(f'{d} = true' for d in defects) + '}')
        if solo:
            self.server.lua('LOCAL_PLAYER = makePlayer("player", 1000.5, 1000.5, 0)')
        else:
            for u in users:
                self.server.lua(f'makePlayer("{u}", 1000.5, 1000.5, 0); login("{u}")')
                c = Machine(self, u, 'client')
                c.lua(f'LOCAL_PLAYER = makePlayer("{u}", 1000.5, 1000.5, 0)')
                self.clients[u] = c
        self.server.lua(AUTHORITY)
        if walls:
            self.server.lua(WALLS)
        if walked:
            self.server.lua('WALKED = { select = true, talk = true }')
        for m in self.machines():
            m.lua(CLIENT_SIDE)
            m.lua('require "RST/RST"')
            for f in HELPERS:
                m.load(f)
            for f in SUITE_FILES:
                m.load(f)
        self.pump = BaseNet.pump.__get__(self)
        self.send = BaseNet.send.__get__(self)
        for _ in range(3):
            self.tick()

    def machines(self):
        return [self.server, *self.clients.values()]

    def tick(self, dt=100):
        self.pump()
        for m in self.machines():
            m.g.CLOCK = m.g.CLOCK + dt
        self.server.g.fire('OnTickEvenPaused')
        self.server.g.fire('OnTick')
        for c in self.clients.values():
            c.g.fire('OnTick')
        self.pump()

    def run(self, suite, test, requester='rs_mp1', limit=20000, dt=100):
        s = self.server
        player = 'LOCAL_PLAYER' if self.solo else f'PLAYERS["{requester}"]'
        side = 'solo' if self.solo else 'server'
        s.lua(f'REPORT = nil; assert(RST.start({{ suite = "{suite}", test = "{test}", tags = {{ "server", "world" }} }}, '
              f'{{ ctx = {{ side = "{side}", player = {player} }}, onDone = function(r) REPORT = r end }}))')
        for _ in range(limit):
            if not s.lua('return RST.running()'):
                return Report(s.g.REPORT)
            self.tick(dt)
        raise AssertionError('run not over: ' + suite)


class Bench(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-e09-suites-')
        self.root = Path(self.tmp.name)
        self.count = 0

    def tearDown(self):
        self.tmp.cleanup()

    def play(self, suite, test, **kw):
        self.count += 1
        net = Net(self.root / f'run{self.count}', **kw)
        return net, net.run(suite, test)

    def status(self, report, test_part):
        return report.status(test_part)

    def assert_pass(self, report, test_part):
        got = report.status(test_part)
        self.assertEqual(got[0], 'PASS', f'{test_part}: {got}')

    def assert_fail(self, report, test_part, message=None):
        got = report.status(test_part)
        self.assertEqual(got[0], 'FAIL', f'{test_part}: {got}')
        if message is not None:
            self.assertIn(message, got[1] or '')


# Murs de la maison simulés pour E9.sight : un mur entre chaque rangée ; la ligne de vue (LosUtil.lineClear, lue aussi
# par Provider.near comme IsoGameCharacter.CanSee) n'est dégagée, et la réponse entendue (Provider.hears), que sur une
# même rangée ; cases libres (doublures HasStairs, getMovingObjects, getRoom).
WALLS = r'''
LosUtil = { lineClear = function(_, _, ay, _, _, by)
    if math.floor(ay) ~= math.floor(by) then return "Blocked" end
    return "Clear"
end }
local baseSquare = CELL.getGridSquare
function CELL:getGridSquare(x, y, z)
    local sq = baseSquare(self, x, y, z)
    if sq ~= nil and sq.HasStairs == nil then
        function sq:HasStairs() return false end
        function sq:getMovingObjects() return JList({}) end
        function sq:getRoom() return nil end
    end
    return sq
end
local baseNear = P.near
P.near = function(a, b, range)
    if not baseNear(a, b, range) then return false end
    return tostring(LosUtil.lineClear(CELL, a:getX(), a:getY(), a:getZ(), b:getX(), b:getY(), b:getZ(), false))
        ~= "Blocked"
end
local baseHears = P.hears
P.hears = function(a, b, range)
    return baseHears(a, b, range) and math.floor(a:getY()) == math.floor(b:getY())
end
'''


class RelationTests(Bench):
    """rs.relation : aide puis trahison = deux changements par le vrai chemin de réponse ; deux PNJ qui diffèrent."""
    T = 'help then betrayal'

    def test_solo_pass(self):
        _, rep = self.play('rs.relation', self.T, solo=True)
        self.assert_pass(rep, self.T)

    def test_mp_pass(self):
        _, rep = self.play('rs.relation', self.T)
        self.assert_pass(rep, self.T)

    def test_detects_a_change_not_applied(self):
        _, rep = self.play('rs.relation', self.T, solo=True, defects=('relationIgnored',))
        self.assert_fail(rep, self.T, 'help: one level above the group')

    def test_bridge_reader_restored(self):
        net, rep = self.play('rs.relation', self.T, solo=True)
        self.assert_pass(rep, self.T)
        self.assertTrue(net.server.lua('local T = require "RadioSurvivor/RS_Transport"; return T.readNpc() == BRIDGE'))


class AccordTests(Bench):
    """rs.factions.accord : deux conclusions sur une révision ; deux négociateurs simultanés ; membre sans mandat."""
    TWO_REV = 'two conclusions on one revision'
    TWO_NEG = 'two negotiators at once'

    def test_two_conclusions_solo_pass(self):
        _, rep = self.play('rs.factions.accord', self.TWO_REV, solo=True)
        self.assert_pass(rep, self.TWO_REV)

    def test_two_negotiators_mp_pass(self):
        _, rep = self.play('rs.factions.accord', self.TWO_NEG)
        self.assert_pass(rep, self.TWO_NEG)

    def test_two_negotiators_skip_in_solo(self):
        _, rep = self.play('rs.factions.accord', self.TWO_NEG, solo=True)
        got = rep.status(self.TWO_NEG)
        self.assertEqual(got[0], 'SKIP')
        self.assertIn('solo', got[1])

    def test_two_negotiators_skip_with_one_client(self):
        _, rep = self.play('rs.factions.accord', self.TWO_NEG, users=('rs_mp1',))
        got = rep.status(self.TWO_NEG)
        self.assertEqual(got[0], 'SKIP')
        self.assertIn('one client online', got[1])

    def test_detects_a_conclusion_on_a_fresh_revision(self):
        _, rep = self.play('rs.factions.accord', self.TWO_NEG, defects=('freshRevision',))
        self.assert_fail(rep, self.TWO_NEG, 'one conclusion applied')

    def test_two_negotiators_out_of_sight_mp_pass(self):
        """Corps hors de vue du second client : E9.sight le place à côté avant la sélection (campagne 2026-10-15)."""
        _, rep = self.play('rs.factions.accord', self.TWO_NEG, walls=True)
        self.assert_pass(rep, self.TWO_NEG)
        self.assertTrue(any('moved next to' in n for k, ns in rep.notes.items() if self.TWO_NEG in k for n in ns))

    def test_detects_an_offer_to_a_member_without_mandate(self):
        _, rep = self.play('rs.factions.accord', self.TWO_NEG, defects=('anyMember',))
        self.assert_fail(rep, self.TWO_NEG, 'agreement offered to a member without mandate')


class IncidentTests(Bench):
    """rs.factions.incident : critères de l'ADR B10."""
    ONE = 'B10: close aggressions'
    TWO = 'B10 two players'

    def test_one_player_solo_pass(self):
        _, rep = self.play('rs.factions.incident', self.ONE, solo=True)
        self.assert_pass(rep, self.ONE)

    def test_one_player_mp_pass(self):
        _, rep = self.play('rs.factions.incident', self.ONE)
        self.assert_pass(rep, self.ONE)

    def test_detects_a_late_reply_accepted(self):
        _, rep = self.play('rs.factions.incident', self.ONE, solo=True, defects=('lateIncidentAccepted',))
        self.assert_fail(rep, self.ONE, 'late reply of the leader')

    def test_detects_a_decision_asked_while_the_bridge_is_down(self):
        _, rep = self.play('rs.factions.incident', self.ONE, solo=True, defects=('bridgeAlwaysUp',))
        self.assert_fail(rep, self.ONE, 'decision asked while the bridge is down')

    def test_two_players_mp_pass(self):
        _, rep = self.play('rs.factions.incident', self.TWO)
        self.assert_pass(rep, self.TWO)

    def test_two_players_skip_in_solo(self):
        _, rep = self.play('rs.factions.incident', self.TWO, solo=True)
        self.assertEqual(rep.status(self.TWO)[0], 'SKIP')


class LeaderTests(Bench):
    """rs.carnet.leader : membre non chef, réponse après une mort ou une succession."""
    T = 'a member never concludes'

    def test_solo_pass(self):
        _, rep = self.play('rs.carnet.leader', self.T, solo=True)
        self.assert_pass(rep, self.T)

    def test_mp_pass(self):
        _, rep = self.play('rs.carnet.leader', self.T)
        self.assert_pass(rep, self.T)

    def test_mp_out_of_sight_pass(self):
        """Membre et chef hors de vue : E9.sight rapproche le joueur à chaque sélection (campagne 2026-10-15)."""
        _, rep = self.play('rs.carnet.leader', self.T, walls=True)
        self.assert_pass(rep, self.T)
        moved = [n for k, ns in rep.notes.items() if self.T in k for n in ns if 'moved next to' in n]
        self.assertGreaterEqual(len(moved), 1, moved)

    def test_mp_body_walked_away_pass(self):
        """Corps parti entre la vérification et la commande : sélection et phrase refusées une fois, refaites."""
        _, rep = self.play('rs.carnet.leader', self.T, walked=True)
        self.assert_pass(rep, self.T)
        notes = [n for k, ns in rep.notes.items() if self.T in k for n in ns]
        self.assertTrue(any('tried again' in n for n in notes), notes)
        self.assertTrue(any('said again' in n for n in notes), notes)

    def test_detects_no_revalidation(self):
        _, rep = self.play('rs.carnet.leader', self.T, solo=True, defects=('noCollectiveCheck',))
        self.assert_fail(rep, self.T)

    def test_detects_a_member_offered_the_agreement(self):
        _, rep = self.play('rs.carnet.leader', self.T, solo=True, defects=('memberNegotiates',))
        self.assert_fail(rep, self.T, 'agreement offered to a member')


class InterceptTests(Bench):
    """RST_PeerChecksE09.intercept : règles, attente, silence du pont, rétablissement."""

    def test_rules_hold_blackout_restore(self):
        self.count += 1
        net = Net(self.root / 'x', solo=True)
        s = net.server
        out = s.lua(r'''
            local E9 = RST.PeerChecksE09
            local T = require "RadioSurvivor/RS_Transport"
            BRIDGE = { ["r1"] = { id = "r1", text = "bridge" }, ["r2"] = { id = "r2", text = "bridge" } }
            Server.pending = { { id = "r1", npc = "n1", kind = "npc_talk", world = "w", run = "x", order = 1,
                revision = 1 }, { id = "r2", npc = "n2", kind = "npc_talk" } }
            local deferred = {}
            local t = { defer = function(_, f) deferred[#deferred + 1] = f end }
            local ctl = E9.intercept(t)
            local hold = true
            ctl.rule(function(r) return r.npc == "n1" end, function(r)
                if hold then return nil end
                return E9.reply(r, { intent = "accept" })
            end)
            local a = T.readNpc()
            local held = a.r1 == nil and a.r2 ~= nil and a.r2.text == "bridge"
            hold = false
            local b = T.readNpc()
            local built = b.r1 ~= nil and b.r1.intent == "accept" and b.r1.text == E9.TEXT and b.r1.order == 1
            ctl.blackout = true
            local c = T.readNpc()
            local silent = c.r1 == nil and c.r2 == nil
            deferred[1]()
            local restored = T.readNpc() == BRIDGE
            return held, built, silent, restored
        ''')
        self.assertEqual(tuple(out), (True, True, True, True))


if __name__ == '__main__':
    unittest.main()
