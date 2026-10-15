"""Tests hors jeu de l'essai comparatif LK02-T10 (corps A = zombie ordinaire, B = joueur réanimé).

    python RadioSurvivor/tests/test_lk_essai.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo) sur le code du mod de développement
(dev/batman_RadioSurvivorTests : RST_LKEssai*.lua et la suite lk.essai). Les doublures ci-dessous reproduisent le
Java 42.21.0 relevé (références en commentaire), mais le banc NE PROUVE PAS l'API réelle : il vérifie le routage
des commandes, les refus (debug, sauvegarde rstest*, capacité), l'autorité (un client ne crée rien en MP), le côté
d'application de chaque réglage, l'exécution de la marche par le seul propriétaire, le nettoyage et le journal
anglais. Seul l'essai en jeu mesure le comportement des corps.

Propriétaire : isRemoteZombie(), getOwner() et getOwnerPlayer() viennent du banc (harness.py), fidèle au Java :
isRemoteZombie() = « aucune connexion propriétaire » (NetworkZombieComponent.java:23) ; client = faux pour le zombie
qu'il possède (NetworkZombieSimulator.java:124-129), serveur = vrai pour un zombie qu'il simule lui-même, faux pour un
zombie possédé par un client ; solo = toujours vrai.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEV_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
FILES = [
    DEV_LUA / 'shared' / 'RST' / 'RST_LKEssai.lua',
    DEV_LUA / 'server' / 'RST' / 'RST_LKEssaiServer.lua',
    DEV_LUA / 'client' / 'RST' / 'RST_LKEssaiClient.lua',
    DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKEssaiSuite.lua',
]

DOUBLES = r'''
local H = HARNESS
local MODE, NAME = H.mode, H.name
local C = H.classes
CALLS, PARKED, SERVER_HAND, NEXT_ID = {}, {}, 0, (MODE == 'server' or MODE == 'solo') and 1000 or 5000
WORLD_NAME, ADMINS, UNLOADED = 'rstest_banc', { A = true }, {}
local function call(s) CALLS[#CALLS + 1] = s end

C.ArrayList.clear = function(self) self.items = {} end
local function removeFrom(list, o) return H.listRemove(list, o) end

-- Sauvegarde et droits (RST.worldGuard ; RST.Server.allowed : checkPermissions + rôle).
getWorld = function() return { getWorld = function() return WORLD_NAME end } end
Capability = { DebugConsole = 'DebugConsole' }
checkPermissions = function(player, cap) return true end   -- vrai hors serveur MP ; le rôle tranche
C.IsoPlayer.getRole = function(self)
    local name = self.username
    return { hasCapability = function(_, cap) return ADMINS[name] == true end }
end
C.IsoPlayer.getZ = function(self) return self.z end

-- Case non chargée : getGridSquare rend nil (IsoCell.getGridSquare).
local rawGet = C.IsoCell.getGridSquare
C.IsoCell.getGridSquare = function(self, x, y, z)
    local sq = rawGet(self, x, y, z)
    if UNLOADED[sq.x .. ',' .. sq.y .. ',' .. sq.z] then return nil end
    return sq
end
C.IsoGridSquare.getStaticMovingObjects = function(self)
    local l = rawget(self, 'statics')
    if not l then l = H.list(); self.statics = l end
    return l
end

instanceItem = function(t)  -- LuaManager.java:4669-4680 ; nil pour un type inconnu
    if type(t) ~= 'string' or not string.find(t, '^%w+%.%w+$') then return nil end
    return { getFullType = function() return t end }
end
sendAttachedItem = function(ch, loc, item)  -- LuaManager.java:9719-9724 : sans effet hors serveur
    call('sendAttachedItem:' .. MODE .. ':' .. loc)
end

local Z = C.IsoZombie

local function visual(z)
    local hv = rawget(z, 'hv')
    if hv then return hv end
    local body = H.list()
    hv = { skin = nil, blood = true, body = body }
    function hv:setSkinTextureName(n) if type(n) ~= 'string' then error('No implementation found', 2) end self.skin = n end
    function hv:getSkinTexture() return self.skin or 'M_ZedBody01_level1' end
    function hv:removeBlood() self.blood = false end
    function hv:removeDirt() self.dirt = false end
    function hv:getBodyVisuals() return self.body end
    z.hv = hv
    return hv
end
function Z:getHumanVisual() return visual(self) end
function Z:getItemVisuals()
    local l = rawget(self, 'ivs')
    if not l then
        l = H.list({ { removeBlood = function() end, removeDirt = function() end } })
        self.ivs = l
    end
    return l
end
function Z:getDescriptor()
    local d = rawget(self, 'desc')
    if not d then
        d = { prefix = 'MaleZombie' }
        function d:getVoicePrefix() return self.prefix end
        function d:setVoicePrefix(p) self.prefix = p end
        self.desc = d
    end
    return d
end
function Z:getVoiceSoundName() return self:getDescriptor().prefix .. 'VoiceA' end   -- IsoZombie.java:2888-2898
function Z:getEmitter()
    return { stopSoundByName = function(_, n) call('stopSoundByName:' .. n) return 0 end }
end
function Z:isDead() return self.dead == true or (rawget(self, 'health') or 1) <= 0 end
function Z:setHealth(h) H.num(h, 'setHealth'); self.health = h; call('setHealth:' .. h .. ':' .. self.onlineID) end
function Z:setUseless(b) self.useless = b end
function Z:isUseless() return self.useless == true end
function Z:setNoTeeth(b) self.noTeeth = b end
function Z:isNoTeeth() return self.noTeeth == true end
function Z:setTarget(t) self.target = t end
function Z:getTarget() return rawget(self, 'target') end
function Z:getPersistentOutfitID() return rawget(self, 'outfitId') or 0 end
function Z:isReanimatedPlayer() return self.reanimated == true end
function Z:isFemale() return self.female == true end
function Z:isOnFloor() return self.onFloor == true end
function Z:isPersistentOutfitInit() return true end
function Z:getCurrentStateName() return rawget(self, 'state') or 'idle' end
function Z:getRealState() return 'idle' end
function Z:resetModel() call('resetModel:' .. self.onlineID) end
function Z:DoZombieInventory() call('DoZombieInventory:' .. self.onlineID) end
function Z:setReanimatedForGrappleOnly(b) self.grapple = b end
function Z:isReanimatedForGrappleOnly() return self.grapple == true end
function Z:setPrimaryHandItem(item)
    call('setPrimaryHandItem:' .. (item and item:getFullType() or 'nil'))
    if MODE == 'server' then SERVER_HAND = SERVER_HAND + 1 end  -- IsoGameCharacter.java:3015 puis 7998-8001
end
function Z:setAttachedItem(loc, item) call('setAttachedItem:' .. loc .. ':' .. (item and item:getFullType() or 'nil')) end
function Z:pathToLocation(x, y, z)
    H.num(x, 'pathToLocation'); H.num(y, 'pathToLocation'); H.num(z, 'pathToLocation')
    call('pathToLocation:' .. x .. ',' .. y .. ',' .. z)
    self.state = 'walktoward'
end
function Z:setVariable(k, v) call('setVariable:' .. k .. '=' .. tostring(v)) end
function Z:setMoving(b) call('setMoving:' .. tostring(b)) end
-- VirtualZombieManager.RemoveZombie : un joueur réanimé vivant est mis de côté puis revient avec son chunk.
function Z:removeFromWorld()
    call('removeFromWorld:' .. self.onlineID)
    if self.reanimated and not self:isDead() then PARKED[#PARKED + 1] = self.onlineID end
    H.removeZombie(self.onlineID)
end
function Z:removeFromSquare() call('removeFromSquare:' .. self.onlineID) end

local function newZombie(x, y, z)
    local id = NEXT_ID
    NEXT_ID = NEXT_ID + 1
    local owner = (MODE == 'client') and NAME or 'server'
    return H.spawnZombie(id, x, y, z, owner)
end

-- LuaManager.java:8355-8445 : liste vide si la case n'est pas chargée.
addZombiesInOutfit = function(x, y, z, n, outfit, femaleChance)
    H.num(x, 'addZombiesInOutfit'); H.num(y, 'addZombiesInOutfit'); H.num(z, 'addZombiesInOutfit'); H.num(n, 'addZombiesInOutfit')
    call('addZombiesInOutfit:' .. tostring(outfit))
    local out = H.list()
    if getCell():getGridSquare(x, y, z) == nil then return out end
    for _ = 1, n do
        local zb = newZombie(x + 0.5, y + 0.5, z)
        zb.outfitId = 1179648 + zb.onlineID
        out:add(zb)
    end
    return out
end

local Body = H.class('IsoDeadBody', C.IsoMovingObject)
function Body:getSquare() return self.square end
-- IsoDeadBody.java:1832-1946 : nouveau zombie, ModData copiées, joueur réanimé (non faux mort), corps retiré.
function Body:reanimate()
    call('reanimate')
    local sq = self.square
    local zb = newZombie(self.x, self.y, self.z)
    zb.reanimated, zb.onFloor, zb.outfitId, zb.female = true, true, 65536 + zb.onlineID, self.female
    zb:getHumanVisual().skin = self.skin  -- HumanVisual.copyFrom (IsoDeadBody.java:1854)
    for k, v in pairs(self:getModData()) do zb:getModData()[k] = v end
    if sq then removeFrom(sq:getStaticMovingObjects(), self) end
    self.square = nil
    return zb
end
-- IsoGridSquare.java:10100-10124 : createCorpse(boolean) passe par VirtualZombieManager.choices, vide hors
-- génération (VirtualZombieManager.java:252-254) : nil ; createCorpse(zombie) : le zombie quitte le monde.
function C.IsoGridSquare:createCorpse(arg)
    if type(arg) == 'boolean' then call('createCorpse:boolean') return nil end
    call('createCorpse:zombie:' .. arg.onlineID)
    local body = setmetatable({ x = self.x + 0.5, y = self.y + 0.5, z = self.z, square = self, female = arg.female,
        skin = arg:getHumanVisual().skin }, Body)  -- baseVisual.copyFrom (IsoDeadBody.java:323-327)
    for k, v in pairs(arg:getModData()) do body:getModData()[k] = v end
    arg:removeFromWorld()
    self:getStaticMovingObjects():add(body)
    return body
end
function C.IsoGridSquare:removeCorpse(body, remote)  -- IsoGridSquare.java:2600-2620
    call('removeCorpse:' .. tostring(remote))
    removeFrom(self:getStaticMovingObjects(), body)
    body.square = nil
end
'''


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Base(unittest.TestCase):
    mode = 'mp'
    debug = True

    def setUp(self):
        self.h = Harness(mode=self.mode, debug=self.debug, lua_roots=[DEV_LUA])
        names = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in names:
            self.h.load(m, DOUBLES)
        if self.mode == 'solo':
            self.h.load('solo', 'client/RST/RST_LKEssaiClient.lua')
            self.h.load('solo', 'server/RST/RST_Server.lua')
            self.h.load('solo', 'server/RST/RST_LKEssaiServer.lua')
            self.h.move_player('A', 100, 100, 0)
        else:
            self.h.load('server', 'server/RST/RST_Server.lua')
            self.h.load('server', 'server/RST/RST_LKEssaiServer.lua')
            for c in ('A', 'B'):
                self.h.load(c, 'client/RST/RST_LKEssaiClient.lua')
                self.h.load(c, 'server/RST/RST_LKEssaiServer.lua')  # le client MP charge aussi server/
            self.h.move_player('A', 100, 100, 0)
            self.h.move_player('B', 104, 100, 0)

    def tearDown(self):
        self.h.close()

    def calls(self, m):
        return lua_list(self.h.eval(m, 'CALLS'))

    def lke(self, m):
        return [line for line in self.h.logs(m) if '[LKE]' in line]

    def mirror(self):
        """Zombies du serveur recréés sur les clients (même onlineID et propriétaire), comme ZombiePacket."""
        srv = self.h.server.H.zombies
        for zid in list(srv.keys()):
            src = srv[zid]
            for c in ('A', 'B'):
                m = self.h.clients[c]
                if m.H.zombies[zid] is None:
                    zb = m.H.spawnZombie(zid, src.x, src.y, src.z, src.owner)
                    zb.reanimated, zb.outfitId, zb.female = src.reanimated, src.outfitId, src.female
            self.h.owners[zid] = src.owner

    def request(self, m, code):
        return self.h.load(m, 'return ' + code)


class MultiplayerTests(Base):
    def test_client_request_is_routed_and_client_creates_nothing(self):
        self.assertIs(self.request('A', 'LKE.spawn("A")'), True)
        pending = self.h.pending()
        self.assertEqual(len(pending), 1)
        self.assertEqual((pending[0]['to'], pending[0]['module'], pending[0]['command']), ('server', 'LKE', 'cmd'))
        self.assertEqual(pending[0]['args']['op'], 'spawn')
        self.h.pump()
        self.assertIn('addZombiesInOutfit:Generic01', self.calls('server'))
        for c in ('A', 'B'):
            created = [x for x in self.calls(c) if x.startswith(('addZombiesInOutfit', 'createCorpse', 'reanimate'))]
            self.assertEqual(created, [], c)
        self.assertTrue(any('spawned LKE-1 kind A' in line for line in self.lke('server')))
        self.assertTrue(any(line.startswith('[LKE] server: [LKE] spawned LKE-1') for line in self.lke('A')))
        self.assertFalse(any('server: ' in line for line in self.lke('B')))  # réponse au seul demandeur
        self.assertEqual(self.h.eval('B', 'LKE.Client.remote["LKE-1"].kind'), 'A')
        self.assertEqual(self.h.eval('server', 'getCell():getZombieList():get(0):getModData().lkEssaiId'), 'LKE-1')

    def test_refused_by_server_without_capability(self):
        self.assertIs(self.request('B', 'LKE.spawn("A")'), True)
        self.h.pump()
        self.assertNotIn('addZombiesInOutfit:Generic01', self.calls('server'))
        self.assertTrue(any('refused: permission denied' in line for line in self.lke('B')))

    def test_refused_by_server_outside_a_test_save(self):
        self.h.load('server', 'WORLD_NAME = "servertest"')
        self.request('A', 'LKE.spawn("B")')
        self.h.pump()
        self.assertEqual(self.calls('server'), [])
        self.assertTrue(any("is not a test save" in line for line in self.lke('A')))

    def test_unloaded_square_refused(self):
        self.h.load('server', 'UNLOADED["102,100,0"] = true')
        self.request('A', 'LKE.spawn("A")')
        self.h.pump()
        self.assertEqual(self.h.eval('server', 'getCell():getZombieList():size()'), 0)
        self.assertTrue(any('spawn refused: square 102,100,0 is not loaded' in line for line in self.lke('A')))

    def test_local_refusals_send_nothing(self):
        self.assertIs(self.request('A', '(LKE.set(1, "fly", true))'), False)
        self.assertIs(self.request('A', '(LKE.walk(1, 2, 0, "run"))'), False)
        self.assertIs(self.request('A', '(LKE.set(1, "hand", "hammer"))'), False)
        self.assertEqual(self.h.pending(), [])

    def test_spawn_b_reanimates_a_dressed_corpse(self):
        self.request('A', 'LKE.spawn("B")')
        self.h.pump()
        calls = [c for c in self.calls('server') if not c.startswith('removeFromSquare')]
        self.assertEqual(calls, ['addZombiesInOutfit:Generic01', 'DoZombieInventory:1000', 'createCorpse:zombie:1000',
                                 'removeFromWorld:1000', 'reanimate'])
        self.assertEqual(self.h.eval('server', 'LKE.Server.entry(1).zombie:isReanimatedPlayer()'), True)
        self.assertEqual(self.h.eval('server', 'LKE.Server.entry(1).zombie:getModData().lkEssaiId'), 'LKE-1')
        self.assertEqual(self.h.eval('server', '#LKE.Server.taggedCorpses(LKE.Server.entry(1))'), 0)
        self.assertEqual(self.h.eval('server', 'PARKED[1]'), None)  # zombie temporaire recyclé, pas mis de côté
        self.assertTrue(any('server removed 1 zombie(s)' in line for line in self.lke('B')))

    def test_settings_applied_on_the_right_side(self):
        self.request('A', 'LKE.spawn("A")')
        self.h.pump()
        self.mirror()
        for code in ('LKE.set(1, "useless", true)', 'LKE.set(1, "noTeeth", true)', 'LKE.set(1, "hand", "Base.Hammer")',
                     'LKE.set(1, "attached", "Base.Shotgun")', 'LKE.set(1, "skin", "human")',
                     'LKE.set(1, "voice", "prefix")'):
            self.assertIs(self.request('A', code), True)
        self.h.pump()
        self.h.tick(2)
        for m in ('server', 'A', 'B'):
            z = self.h.zombie(m, 1000)
            self.assertIs(z.useless, True, m)
            self.assertIs(z.noTeeth, True, m)
            self.assertEqual(z.hv.skin, 'MaleBody01', m)
            self.assertEqual(z.desc.prefix, 'LKESilent', m)
        self.assertEqual(self.h.eval('server', 'SERVER_HAND'), 0)
        for c in ('A', 'B'):
            self.assertIn('setPrimaryHandItem:Base.Hammer', self.calls(c))
            self.assertIn('resetModel:1000', self.calls(c))
            self.assertIn('stopSoundByName:MaleZombieVoiceA', self.calls(c))
            self.assertFalse(any(x.startswith(('setAttachedItem', 'sendAttachedItem')) for x in self.calls(c)), c)
        self.assertIn('setAttachedItem:Rifle On Back:Base.Shotgun', self.calls('server'))
        self.assertIn('sendAttachedItem:server:Rifle On Back', self.calls('server'))
        self.assertNotIn('resetModel:1000', self.calls('server'))
        # une seule application par objet et valeur, même après d'autres ticks
        self.h.tick(20)
        self.assertEqual(self.calls('A').count('setPrimaryHandItem:Base.Hammer'), 1)

    def test_skin_reapplied_on_a_recreated_client_copy(self):
        self.request('A', 'LKE.spawn("A", "clean")')
        self.h.pump()
        self.mirror()
        self.h.tick(1)
        self.assertEqual(self.h.zombie('B', 1000).hv.skin, 'MaleBody01')
        self.h.clients['B'].H.removeZombie(1000)  # copie périmée retirée (IsoZombie.java:2716-2722)
        self.mirror()                               # recréée au paquet suivant : nouvel objet
        self.h.tick(10)
        self.assertEqual(self.h.zombie('B', 1000).hv.skin, 'MaleBody01')
        self.assertEqual(self.calls('B').count('resetModel:1000'), 2)

    def test_server_hand_only_on_the_server(self):
        self.request('A', 'LKE.spawn("A")')
        self.h.pump()
        self.mirror()
        self.request('A', 'LKE.set(1, "serverHand", "Base.Hammer")')
        self.h.pump()
        self.h.tick(2)
        self.assertEqual(self.h.eval('server', 'SERVER_HAND'), 1)
        for c in ('A', 'B'):
            self.assertNotIn('setPrimaryHandItem:Base.Hammer', self.calls(c))

    def test_walk_executed_by_the_owner_only(self):
        self.request('A', 'LKE.spawn("A")')
        self.h.pump()
        self.mirror()
        self.h.set_owner(1000, 'A')
        self.request('A', 'LKE.walk(1, 6, 0, "pathfind")')
        self.h.pump()
        self.h.tick(2)
        self.h.pump()
        walk = [c for c in self.calls('A') if c.startswith(('pathToLocation', 'setVariable', 'setMoving'))]
        self.assertEqual(walk, ['pathToLocation:108,100,0', 'setVariable:bPathfind=true', 'setMoving:false'])
        for m in ('server', 'B'):
            self.assertFalse(any(c.startswith('pathToLocation') for c in self.calls(m)), m)
        self.assertIs(self.h.zombie('A', 1000).useless, True)  # mode pathfind : useless
        self.assertTrue(any('client A reports: walk #1 pathfind' in line for line in self.lke('server')))
        # simulé par le serveur : le serveur exécute, aucun client
        self.h.set_owner(1000, 'server')
        self.request('A', 'LKE.walk(1, 0, 3, "plain")')
        self.h.pump()
        self.h.tick(2)
        self.assertIn('pathToLocation:102,103,0', self.calls('server'))
        self.assertEqual(sum(c.startswith('pathToLocation') for c in self.calls('A')), 1)
        self.assertIs(self.h.zombie('server', 1000).useless, False)

    def test_clear_removes_bodies_corpses_and_client_copies(self):
        self.request('A', 'LKE.spawn("A")')
        self.request('A', 'LKE.spawn("B")')
        self.h.pump()
        self.mirror()
        self.assertEqual(self.h.eval('server', 'getCell():getZombieList():size()'), 2)
        self.request('A', 'LKE.clear()')
        self.h.pump()
        calls = self.calls('server')
        self.assertLess(calls.index('setHealth:0:1002'), calls.index('removeFromWorld:1002'))  # B non mis de côté
        self.assertEqual(self.h.eval('server', 'PARKED[1]'), None)
        self.assertEqual(self.h.eval('server', 'getCell():getZombieList():size()'), 0)
        self.assertEqual(self.h.eval('server', '#LKE.Server.order'), 0)
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'getCell():getZombieList():size()'), 0, c)
            self.assertEqual(self.h.eval(c, '(function() local n = 0 for _ in pairs(LKE.Client.remote) do n = n + 1 end return n end)()'), 0)

    def test_corpse_left_by_a_failed_reanimation_is_removed(self):
        self.h.load('server', 'C_REAN = HARNESS.classes.IsoDeadBody.reanimate; '
                              'HARNESS.classes.IsoDeadBody.reanimate = function() return nil end')
        self.request('A', 'LKE.spawn("B")')
        self.h.pump()
        self.assertEqual(self.h.eval('server', '#LKE.Server.taggedCorpses(LKE.Server.entry(1))'), 1)
        self.assertTrue(any('WARNING: LKE-1: reanimate returned nil' in line for line in self.lke('server')))
        self.request('A', 'LKE.clear(1)')
        self.h.pump()
        self.assertIn('removeCorpse:false', self.calls('server'))
        self.assertEqual(self.h.eval('server', 'getCell():getGridSquare(102, 102, 0):getStaticMovingObjects():size()'), 0)

    def test_log_lines_are_english_ascii_and_written_to_a_file(self):
        self.request('A', 'LKE.spawn("A")')
        self.request('A', 'LKE.spawn("B", "clean")')
        self.request('A', 'LKE.list()')
        self.h.pump()
        self.request('A', 'LKE.here()')
        self.request('A', 'LKE.walk(2, 3, 0, "notarget")')
        self.request('A', 'LKE.clear()')
        self.h.pump()
        for m in ('server', 'A', 'B'):
            for line in self.lke(m):
                self.assertRegex(line, r'^\[LKE\] [\x20-\x7e]*$', m)
        log = self.h.file_root('server') / 'batman_RadioSurvivor' / 'tests' / 'lke-essai.log'
        self.assertTrue(log.exists())
        self.assertIn('spawned LKE-1 kind A', log.read_text(encoding='utf-8'))


class NoDebugTests(Base):
    debug = False

    def test_client_refuses_without_debug(self):
        self.assertIs(self.request('A', '(LKE.spawn("A"))'), False)
        self.assertEqual(self.h.pending(), [])
        self.assertTrue(any('refused: debug mode is off' in line for line in self.lke('A')))


class SoloTests(Base):
    mode = 'solo'

    def test_full_cycle_in_solo(self):
        self.assertIs(self.request('solo', 'LKE.spawn("A")'), True)
        self.assertIs(self.request('solo', 'LKE.spawn("B", "clean")'), True)
        self.assertEqual(self.h.eval('solo', 'getCell():getZombieList():size()'), 2)
        self.assertEqual(self.h.eval('solo', 'LKE.Server.entry(2).zombie.hv.skin'), 'MaleBody01')
        self.assertIs(self.request('solo', 'LKE.set(1, "hand", "Base.Hammer")'), True)
        self.assertIs(self.request('solo', 'LKE.walk("LKE-2", 2, 0, "uselessline")'), True)
        self.assertIn('setPrimaryHandItem:Base.Hammer', self.calls('solo'))
        self.assertIn('pathToLocation:104,102,0', self.calls('solo'))  # solo : exécutée tout de suite
        self.assertIs(self.request('solo', 'LKE.list()'), True)
        self.assertTrue(any('LKE-2 kind B found=object' in line for line in self.lke('solo')))
        self.assertIs(self.request('solo', 'LKE.clear()'), True)
        self.assertEqual(self.h.eval('solo', 'getCell():getZombieList():size()'), 0)
        self.assertEqual(self.h.eval('solo', 'PARKED[1]'), None)
        self.assertEqual(self.h.pending(), [])

    def test_solo_refuses_outside_a_test_save(self):
        self.h.load('solo', 'WORLD_NAME = "Muldraugh"')
        self.assertIs(self.request('solo', '(LKE.spawn("A"))'), False)
        self.assertEqual(self.calls('solo'), [])
        self.assertTrue(any("is not a test save" in line for line in self.lke('solo')))

    def test_suite_creation_and_clear_tests_pass_on_the_doubles(self):
        """Seuls les tests sans marche ni minuterie longue : le banc ne simule pas le déplacement."""
        self.h.load('solo', 'shared/RST/suites/RST_LKEssaiSuite.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.essai", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.essai')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertEqual(listed.count, 7)                   # base B, contact, round trip, clear
        self.assertIsNone(listed.error)
        # Base A (abandoned on 2026-10-09) in a suite of its own, never selected by "lk.essai" (MP campaign).
        names = [r.name for r in lua_list(self.h.eval('solo', 'RST.list({ suite = "lk.essai", tags = "world" }, true)'))]
        self.assertEqual(names, ['lk.essai'])
        listed_a = self.h.eval('solo', 'RST.list({ suite = "lk.essai_a", tags = "world" }, true)[1]')
        self.assertEqual(listed_a.name, 'lk.essai_a')
        self.assertEqual(listed_a.count, 5)
        for suite, pattern in (('lk.essai', '^B: [od]'), ('lk.essai_a', '^A: [od]'), ('lk.essai', '^clear')):
            self.assertIs(self.h.load('solo', f'return (RST.start({{ suite = "{suite}", tags = "world", '
                                              f'test = "{pattern}" }}, {{ ctx = {{ player = getPlayer() }} }}))'), True)
            for _ in range(200):
                self.h.tick()
                if not self.h.eval('solo', 'RST.running()'):
                    break
            report = self.h.eval('solo', 'RST.last()')
            results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
            self.assertTrue(report.ok, results)
        self.assertEqual(self.h.eval('solo', 'getCell():getZombieList():size()'), 0)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources(self):
        for path in FILES:
            raw = path.read_bytes()
            self.assertTrue(all(b < 128 for b in raw), f'{path.name}: non ASCII byte')
            text = raw.decode('ascii')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bstring\.format\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code), f'{path.name}: {pattern}')
            for line in re.findall(r'(?:log|print)\(\s*"([^"]*)"', code):
                self.assertRegex(line, r'^[\x20-\x7e]*$')

    def test_lua_files_live_in_the_dev_mod_only(self):
        published = ROOT / 'Contents'
        self.assertEqual([p for p in published.rglob('*LKEssai*')], [])


if __name__ == '__main__':
    unittest.main()
