"""Tests hors jeu de la mort unique et du cadavre des PNJ Living Knox (LK07-T04) : LK_Health.kill (chemin unique),
LK_Bodies.deathCause / examine / layDown / onZombieDead (fait "npcDied"), causes "zombie" et "bleeding".

    python RadioSurvivor/tests/test_lk_death.py

Banc de tests/test_lk_health.py (serveur dédié et deux clients, ou solo), complété des doublures ci-dessous, qui
reproduisent le Java 42.21.0 relevé et NE PROUVENT PAS l'API réelle :
- die() hors client (IsoGameCharacter.java:13478-13499) : Kill(getAttackedBy()) si onKilled n'a pas eu lieu, puis
  becomeCorpse une seule fois (13536-13541) ; en solo, le zombie tué par Kill devient cadavre à sa mise à jour
  suivante (état ZombieOnGroundState -> die(), ZombieOnGroundState.java:73-78) ;
- cadavre (IsoDeadBody.java:252-400) : ModData copiées (étiquette comprise), faux mort hérité du zombie, tueur =
  getAttackedBy, zombie retiré du monde ;
- cadavre traîné (IsoDeadBody.java:1817-1831) : reanimate() + isReanimatedForGrappleOnly, remis en cadavre par die()
  au lâcher (ZombieOnGroundState.java:80-91) ; cadavre faux mort relevé (1636-1653, 1894-1897) : zombie ordinaire
  (pas un joueur réanimé), ModData copiées.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_lk_health as th  # noqa: E402
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402

SUITE = 'shared/RST/suites/RST_LKDeath.lua'
SUITE_FILE = DEV_LUA / SUITE

DEATH_DOUBLES = r'''
local H = HARNESS
local MODE = H.mode
local C = H.classes
local Z = C.IsoZombie
local Body = C.IsoDeadBody
CORPSES = {}
function Body:isFakeDead() return self.fakeDead == true end
function Body:getKilledBy() return self.killedBy end
function Body:getWornItems() return self.worn end
-- reanimate : objets portés repris par le zombie (IsoDeadBody.java:1855).
local rawReanimate = Body.reanimate
function Body:reanimate()
    local worn = self.worn
    local zb = rawReanimate(self)
    if zb ~= nil then zb.worn = worn end
    return zb
end
local function becomeCorpse(zb)
    if rawget(zb, 'corpse') then return zb.corpse end
    local sq = zb.square
    local fake, killer = zb:isFakeDead(), zb.attackedBy
    local body = sq:createCorpse(zb)
    body.fakeDead, body.killedBy = fake, killer
    zb.corpse = body
    CORPSES[#CORPSES + 1] = body
    return body
end
function Z:die()
    if not self.killDone then self:Kill(self.attackedBy) end
    if MODE ~= 'client' then becomeCorpse(self) end
end
-- Solo : un zombie tué par Kill devient cadavre à sa mise à jour suivante.
local rawUpdate = H.updateZombies
H.updateZombies = function()
    rawUpdate()
    if MODE ~= 'solo' then return end
    local snapshot = {}
    for i, zb in ipairs(H.zombieList.items) do snapshot[i] = zb end
    for _, zb in ipairs(snapshot) do
        if zb.killDone and zb:isDead() and not rawget(zb, 'corpse') then becomeCorpse(zb) end
    end
end
-- Cadavre traîné par un joueur, puis lâché.
function DRAG(body)
    local zb = body:reanimate()
    zb.grappleOnly = true
    return zb
end
function LET_GO(zb) zb:die() end
-- Cadavre faux mort qui se relève : zombie ordinaire, faux mort.
function RISE(body)
    local zb = body:reanimate()
    zb.reanimated = false
    RELEASE_DESCRIPTOR(zb)
    zb.fakeDead = true
    return zb
end
function TAGGED_CORPSES(id)
    local n = 0
    for _, b in ipairs(CORPSES) do
        if b.square ~= nil and LivingKnox.Identity.readTag(b:getModData()) == id then n = n + 1 end
    end
    return n
end
function TAGGED_ALIVE(id)
    local n = 0
    for _, zb in ipairs(HARNESS.zombieList.items) do
        if not zb:isDead() and zb:hasModData() and LivingKnox.Identity.readTag(zb:getModData()) == id then n = n + 1 end
    end
    return n
end
LAST_CORPSE = function() return CORPSES[#CORPSES] end
'''

# LK07-T10 : cadavres en reseau (Java 42.21.0) : identifiant d'objet "DeadBody-<n>" (ObjectID.java:77-79, lu par
# tostring : classe non exposee, KahluaUtil.java:268-319), identique chez le client (DeadCharacterPacket.java:146-150,
# AddCorpseToMapPacket.java:62-63) ; paquet de mort ignore sans copie vivante du zombie (DeadCharacterPacket.java:90-92) ;
# sendCorpse a tous (GameServer.java:1852-1866), objet neuf ajoute meme si le client a deja ce cadavre
# (AddCorpseToMapPacket.java:89-97) ; retrait par identifiant d'objet (RemoveCorpseFromMapPacket.java:58-60, 75-80) ;
# removeFromSquare garde le champ square (IsoObject.java:4252-4257) ; addCorpse(body, true) sans paquet sur le serveur
# (IsoGridSquare.java:2639-2655). Doublures : le transport des paquets est fait par le banc (deliver_*).
NET_DOUBLES = r'''
local H = HARNESS
local MODE = H.mode
local C = H.classes
local Body = C.IsoDeadBody
local OID = {}
OID.__tostring = function(o) return 'DeadBody-' .. o.n end
function Body:getObjectID() return setmetatable({ n = self.oid or -1 }, OID) end
function Body:getCharacterOnlineID() return self.charId or -1 end
-- IsoDeadBody.setCharacterOnlineID(short) : Kahlua ne convertit pas un nombre Lua en short (campagne MP 2026-10-15).
function Body:setCharacterOnlineID(v) error("expected argument of type short, got Double") end
function Body:setSquare(sq) self.square = sq end
NEXT_OID, NEW_CORPSES, NET_REMOVED, NET_SENT = 500, {}, {}, {}
local rawCreate = C.IsoGridSquare.createCorpse
function C.IsoGridSquare:createCorpse(arg)
    local body = rawCreate(self, arg)
    if body ~= nil and type(arg) ~= 'boolean' then
        NEXT_OID = NEXT_OID + 1
        body.oid, body.charId = NEXT_OID, arg.onlineID
        NEW_CORPSES[#NEW_CORPSES + 1] = { oid = body.oid, cid = arg.onlineID, x = self.x, y = self.y, z = self.z }
    end
    return body
end
local rawRemove = C.IsoGridSquare.removeCorpse
function C.IsoGridSquare:removeCorpse(body, remote)
    local sq = body.square
    rawRemove(self, body, remote)
    body.square = sq          -- removeFromSquare garde le champ square
    if MODE == 'server' and remote == false then
        NET_REMOVED[#NET_REMOVED + 1] = { oid = body.oid, cid = body:getCharacterOnlineID() }
    end
end
function C.IsoGridSquare:addCorpse(body, remote)
    if not self:getStaticMovingObjects():contains(body) then self:getStaticMovingObjects():add(body) end
    body.square = self
end
sendCorpse = function(body)
    if MODE ~= 'server' then return end
    local sq = body:getSquare()
    if sq == nil then return end
    NET_SENT[#NET_SENT + 1] = { oid = body.oid, cid = body:getCharacterOnlineID(), x = sq.x, y = sq.y, z = sq.z }
end
function TAKE(name)
    local out = _G[name]
    _G[name] = {}
    return out
end
-- Client : paquet de mort (copie vivante exigee), ajout et retrait d'un cadavre par le reseau.
local function addHere(oid, cid, x, y, z)
    local sq = H.square(x, y, z)
    local body = setmetatable({ x = x + 0.5, y = y + 0.5, z = z, square = sq, oid = oid, charId = cid }, Body)
    sq:getStaticMovingObjects():add(body)
    return body
end
function NET_DEATH(cid, oid, x, y, z)
    local zb = H.zombies[cid]
    if zb == nil or zb:isDead() then return false end
    H.removeZombie(cid)
    addHere(oid, cid, x, y, z)
    return true
end
function NET_ADD(oid, cid, x, y, z) addHere(oid, cid, x, y, z) end
function NET_REMOVE(oid)
    for x = 90, 115 do for y = 90, 115 do
        local list = H.square(x, y, 0):getStaticMovingObjects()
        for _, o in ipairs(list.items) do
            if o.oid == oid then H.listRemove(list, o) return true end
        end
    end end
    return false
end
function CORPSES_HERE(oid)
    local n = 0
    for x = 90, 115 do for y = 90, 115 do
        for _, o in ipairs(H.square(x, y, 0):getStaticMovingObjects().items) do
            if instanceof(o, 'IsoDeadBody') and (oid == nil or o.oid == oid) then n = n + 1 end
        end
    end end
    return n
end
'''

LISTEN = r'''
FACTS, MEMBER_FACTS = {}, {}
LivingKnox.listen("npcDied", "test", function(i) FACTS[#FACTS + 1] = i end)
'''


class DeathBase(th.HealthBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, DEATH_DOUBLES)
        h.load('solo' if self.mode == 'solo' else 'server', LISTEN)
        return h

    def facts(self):
        return self.ev('#FACTS')

    def death(self):
        d = self.ev('LivingKnox.Store.data().npcs["lk-1"].death')
        return d.cause, d.killer, d.weapon


class MultiplayerDeathTests(DeathBase):
    def ready(self, owner='server'):
        return th.MultiplayerHealthTests.ready(self, owner)

    def kill_by_player(self, zid):
        hits = 0
        while not self.h.eval('server', f'HARNESS.zombies[{zid}] == nil or HARNESS.zombies[{zid}]:isDead()') \
                and hits < 20:
            self.hit(zid, 100.0)
            hits += 1
        self.assertLess(hits, 20)

    def test_player_kill_one_death_one_tagged_corpse_and_one_fact(self):
        zid = self.ready('A')
        self.kill_by_player(zid)
        for _ in range(3):   # coups sur le corps mort : ignorés
            self.h.eval('server', f'HARNESS.zombies[{zid}] and PLAYER_HIT("A", {zid}, "Base.BaseballBat", 10.0)')
        self.assertEqual(self.h.eval('server', 'DEATHS'), 1)
        self.assertEqual(self.hl('stats.deaths'), 1)
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        self.assertEqual(self.ev('TAGGED_ALIVE("lk-1")'), 0)
        self.assertIs(self.ev('LAST_CORPSE():isFakeDead()'), False)
        self.assertEqual(self.facts(), 1)
        self.assertEqual((self.ev('FACTS[1].npc'), self.ev('FACTS[1].cause'), self.ev('FACTS[1].killer'),
                          self.ev('FACTS[1].weapon')), ('lk-1', 'melee', 'A', 'Base.BaseballBat'))
        self.assertEqual((self.ev('FACTS[1].x'), self.ev('FACTS[1].y')), (102, 102))
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Bodies.find("lk-1") }')), [None, 'dead'])
        self.assertEqual(self.h.errors('server'), [])

    def test_bleeding_death_cause_bleeding_without_the_old_attacker(self):
        zid = self.ready('server')
        self.hit(zid, 3.0)                        # blessure d'un joueur : saigne, attaquant A posé sur le corps
        self.assertGreater(self.hl('bleeding("lk-1")'), 0)
        self.run_lua('local n = LivingKnox.Store.data().npcs["lk-1"]; n.hp = 0.01; n.bleed = 0.6')
        self.hl('bleedPass(1000)')
        self.hl('bleedPass(1001)')
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.death(), ('bleeding', None, None))
        self.assertIsNone(self.ev('LAST_CORPSE():getKilledBy()'))
        self.assertEqual(self.hl('stats.bleedDeaths'), 1)
        self.assertEqual((self.facts(), self.ev('FACTS[1].cause')), (1, 'bleeding'))
        self.assertIsNone(self.hl('causeOf("lk-1")'))

    def test_vanilla_zombie_kill_cause_zombie(self):
        zid = self.ready('server')
        self.run_lua(f'VZ = NEW_ZOMBIE(103.5, 102.5, 0, false); '
                     f'LivingKnox.Health.applyHit("lk-1", HARNESS.zombies[{zid}], 50, "zombie bite", VZ, nil)')
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.death(), ('zombie', None, None))
        self.assertIs(self.ev('rawequal(LAST_CORPSE():getKilledBy(), VZ)'), True)
        self.assertEqual(self.ev('FACTS[1].cause'), 'zombie')

    def test_direct_kill_once_and_parked_body_never_killed(self):
        zid = self.ready('server')
        # Corps mis de côté (chunk déchargé) : ni mort par saignement ni mort directe.
        self.run_lua('local n = LivingKnox.Store.data().npcs["lk-1"]; n.hp = 0.01; n.bleed = 0.6; '
                     'UNLOAD(90, 115, 90, 115)')
        self.hl('bleedPass(2000)')
        self.hl('bleedPass(2001)')
        res = lua_list(self.ev('{ LivingKnox.Health.kill("lk-1") }'))
        self.assertEqual(res, [False, 'body not in the world'])
        self.assertEqual(self.npc_field('state'), 'embodied')
        self.assertEqual(self.npc_field('hp'), 0.01)
        self.run_lua('RELOAD()')
        # Appel direct (chemin unique) : une seule mort, la seconde refusée.
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Health.kill("lk-1") }')), [True])
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Health.kill("lk-1") }')), [False, 'npc not embodied'])
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.hl('stats.deaths'), 1)
        self.assertEqual(self.facts(), 1)
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        del zid

    def test_dragged_corpse_is_left_alone_and_no_second_death(self):
        zid = self.ready('A')
        self.kill_by_player(zid)
        self.run_lua('DRAGGED = DRAG(LAST_CORPSE())')
        self.assertEqual(self.ev('TAGGED_ALIVE("lk-1")'), 1)
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('DRAGGED:isDead()'), False)
        self.assertTrue(self.ev('HARNESS.zombieList:contains(DRAGGED)'))
        self.assertFalse(any('body removed' in line for line in self.lk()), self.lk())
        self.run_lua('LET_GO(DRAGGED)')
        self.assertEqual(self.h.eval('server', 'DEATHS'), 2)      # mort vanilla du zombie temporaire
        self.assertEqual(self.hl('stats.deaths'), 1)
        self.assertEqual(self.facts(), 1)
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        self.assertEqual(self.ev('TAGGED_ALIVE("lk-1")'), 0)
        self.assertEqual(self.death(), ('melee', 'A', 'Base.BaseballBat'))
        self.assertEqual(len([line for line in self.lk() if 'npc lk-1 died' in line]), 1)

    def test_risen_corpse_is_laid_down_and_never_an_npc_again(self):
        zid = self.ready('A')
        self.kill_by_player(zid)
        self.run_lua('RISEN = RISE(LAST_CORPSE())')
        self.assertEqual(self.ev('TAGGED_ALIVE("lk-1")'), 1)
        # Serveur MP (LK07-T09) : remis à terre au balayage qui suit RISEN_DELAY_MS, le temps que les clients reçoivent
        # sa copie (elle retire chez eux l'ancien cadavre ; sans elle, le nouveau cadavre ne leur parvient pas).
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('RISEN:isDead()'), False)
        self.assertEqual(self.ev('LivingKnox.Bodies.stats.laidDown'), 0)
        self.h.advance_ms(1900)
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('RISEN:isDead()'), False)
        self.h.advance_ms(100)
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('RISEN:isDead()'), True)
        self.assertEqual(self.ev('TAGGED_ALIVE("lk-1")'), 0)
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        self.assertIs(self.ev('LAST_CORPSE():isFakeDead()'), False)
        self.assertEqual(self.ev('LivingKnox.Bodies.stats.laidDown'), 1)
        self.assertTrue(any('WARN npc lk-1 is dead but its corpse rose again (fake dead corpse)' in line
                            for line in self.lk()), self.lk())
        # Joueur réanimé étiqueté d'un PNJ mort (réanimation par un autre mod) : remis à terre aussi.
        self.run_lua('AGAIN = LAST_CORPSE():reanimate()')
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('AGAIN:isDead()'), False)
        self.h.advance_ms(2000)
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('AGAIN:isDead()'), True)
        self.assertEqual(self.ev('LivingKnox.Bodies.stats.laidDown'), 2)
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        self.assertEqual(self.hl('stats.deaths'), 1)
        self.assertEqual(self.facts(), 1)
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.ev('LivingKnox.Bodies.embody("lk-1", 102, 102, 0)'), (None, 'npc lk-1 is dead'))

    def test_dead_registry_with_new_causes_is_reread(self):
        zid = self.ready('server')
        self.run_lua(f'VZ = NEW_ZOMBIE(103.5, 102.5, 0, false); '
                     f'LivingKnox.Health.applyHit("lk-1", HARNESS.zombies[{zid}], 50, "zombie bite", VZ, nil)')
        for cause in ('zombie', 'bleeding'):
            self.assertIs(self.ev(f'(LivingKnox.Identity.validDeath({{ cause = "{cause}" }}))'), True)
        ok = self.run_lua('return (LivingKnox.Identity.validate(LivingKnox.Store.data())) ~= nil')
        self.assertIs(ok, True)


class CorpseResendTests(MultiplayerDeathTests):
    """LK07-T10 : cadavre renvoyé à un client MP qui n'a pas reçu le paquet de mort (copie absente), sans doublon."""

    def make(self, root=None):
        h = super().make(root)
        for m in ('server', 'A', 'B'):
            h.load(m, NET_DOUBLES)
            h.load(m, 'server/LivingKnox/LK_Death.lua')
            if m != 'server':
                h.load(m, 'client/LivingKnox/LK_DeathClient.lua')
        h.move_player('B', 104, 103, 0)
        return h

    def d(self, code):
        return self.ev('LivingKnox.Death.' + code)

    def deliver_deaths(self):
        """Paquet de mort : cadavre chez chaque client qui a la copie vivante du zombie mort."""
        for e in lua_list(self.ev('TAKE("NEW_CORPSES")')):
            for c in ('A', 'B'):
                self.h.eval(c, f'NET_DEATH({e.cid}, {e.oid}, {e.x}, {e.y}, {e.z})')

    def deliver_net(self, to=('A', 'B')):
        """RemoveCorpseFromMap puis AddCorpseToMap du serveur vers les clients to (autres : perdus)."""
        removed = [(e.oid, e.cid) for e in lua_list(self.ev('TAKE("NET_REMOVED")'))]
        sent = [(e.oid, e.cid, e.x, e.y, e.z) for e in lua_list(self.ev('TAKE("NET_SENT")'))]
        for c in to:
            for oid, _ in removed:
                self.h.eval(c, f'NET_REMOVE({oid})')
            for oid, cid, x, y, z in sent:
                self.h.eval(c, f'NET_ADD({oid}, {cid}, {x}, {y}, {z})')
        return removed, sent

    def counts(self):
        return {c: self.h.eval(c, 'CORPSES_HERE()') for c in ('A', 'B')}

    def step(self, ms):
        """ms d'horloge réelle, un passage de LK_Death (abonné OnTick), puis le réseau Lua."""
        self.h.advance_ms(ms)
        self.h.tick(self.d('EVERY'))
        self.h.pump()

    def die(self, copies=('A', 'B')):
        zid = self.ready('A')
        for c in ('A', 'B'):
            if c not in copies:
                self.h.eval(c, f'HARNESS.removeZombie({zid})')   # copie retirée « stale » ou jamais reçue
        self.kill_by_player(zid)
        self.deliver_deaths()
        return zid

    def test_client_without_copy_gets_the_corpse_once_and_the_other_no_duplicate(self):
        self.die(copies=('A',))
        self.assertEqual(self.counts(), {'A': 1, 'B': 0})
        oid = self.ev('LAST_CORPSE().oid')
        self.assertEqual(self.d('stats.tracked'), 1)
        self.step(6000)                                   # avant CHECK_DELAY_MS : aucune demande
        self.assertEqual(self.d('stats.asked'), 0)
        self.assertEqual(self.h.pending(), [])
        self.step(1000)                                   # demande aux deux joueurs proches ; B répond « manquant »
        self.assertEqual(self.d('stats.asked'), 1)
        self.assertEqual((self.d('stats.missing'), self.d('pending["lk-1"].phase')), (1, 'missing'))
        self.assertEqual(self.h.eval('A', 'LivingKnox.DeathView.stats.present'), 1)
        self.assertEqual(self.h.eval('B', 'LivingKnox.DeathView.stats.missing'), 1)
        cid = self.ev('LAST_CORPSE():getCharacterOnlineID()')
        self.step(500)                                    # retrait d'abord (identifiant de personnage du cadavre)
        removed, sent = self.deliver_net()
        self.assertEqual(removed, [(oid, cid)])
        self.assertEqual(sent, [])
        self.assertEqual(self.counts(), {'A': 0, 'B': 0})
        # Hors de sa case sur le serveur pendant RESEND_GAP_MS.
        self.assertEqual(self.ev('getCell():getGridSquare(102, 102, 0):getStaticMovingObjects():size()'), 0)
        self.step(500)
        self.assertEqual(self.deliver_net(), ([], []))
        self.step(500)                                    # remise et envoi à tous
        removed, sent = self.deliver_net()
        self.assertEqual([(s[0], s[2], s[3]) for s in sent], [(oid, 102, 102)])
        self.assertEqual(self.counts(), {'A': 1, 'B': 1})
        self.assertEqual(self.h.eval('B', f'CORPSES_HERE({oid})'), 1)
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        self.assertEqual(self.ev('LAST_CORPSE():getCharacterOnlineID()'), sent[0][1])
        self.assertNotEqual(sent[0][1], -1)
        self.assertEqual(self.d('stats.resent'), 1)
        self.assertTrue(any('corpse resent to the clients near 102,102,0 (missing on B, resend 1)' in line
                            for line in self.lk()), self.lk())
        # Vérification : nouvelle demande, tous l'ont, entrée close.
        self.step(3000)
        self.assertEqual(self.d('stats.asked'), 2)
        self.assertEqual(self.d('stats.missing'), 1)
        self.step(5000)
        self.assertEqual((self.d('stats.clean'), self.d('pass()')), (1, 0))
        self.assertEqual(self.counts(), {'A': 1, 'B': 1})
        self.assertEqual(self.h.errors('server'), [])

    def test_every_client_with_its_copy_nothing_resent(self):
        self.die()
        self.assertEqual(self.counts(), {'A': 1, 'B': 1})
        self.step(7000)
        self.assertEqual((self.d('stats.asked'), self.d('stats.missing')), (1, 0))
        self.step(5000)
        self.assertEqual((self.d('stats.clean'), self.d('stats.resent')), (1, 0))
        self.assertEqual(self.deliver_net(), ([], []))
        self.assertEqual(self.counts(), {'A': 1, 'B': 1})

    def test_reports_out_of_time_far_or_forged_are_refused(self):
        self.die(copies=('A',))
        self.h.eval('B', 'sendClientCommand("LivingKnox", "corpseMissing", { id = "lk-1" })')   # avant la demande
        self.h.eval('B', 'sendClientCommand("LivingKnox", "corpseMissing", { id = 5 })')
        self.h.pump()
        self.assertEqual(self.d('stats.refused'), 1)       # identifiant non textuel : ignoré sans compte
        self.h.move_player('B', 300, 300, 0)              # loin : ni demandé, ni écouté
        self.step(7000)
        self.assertEqual(self.h.eval('B', 'LivingKnox.DeathView.stats.checks'), 0)
        self.h.eval('B', 'sendClientCommand("LivingKnox", "corpseMissing", { id = "lk-1" })')
        self.h.pump()
        self.assertEqual((self.d('stats.refused'), self.d('stats.missing')), (2, 0))
        self.step(5000)                                   # fenêtre close : rien renvoyé
        self.assertEqual((self.d('stats.clean'), self.d('stats.resent')), (1, 0))
        self.h.move_player('B', 104, 103, 0)
        self.h.eval('B', 'sendClientCommand("LivingKnox", "corpseMissing", { id = "lk-1" })')
        self.h.pump()
        self.assertEqual(self.d('stats.refused'), 3)
        self.assertEqual(self.deliver_net(), ([], []))

    def test_resends_are_bounded_when_the_client_never_gets_it(self):
        self.die(copies=('A',))
        self.step(7000)
        for n in (1, 2):
            self.step(500)
            self.step(1000)
            self.deliver_net(to=('A',))                   # B perd le cadavre renvoyé
            self.assertEqual(self.d('stats.resent'), n)
            self.step(3000)
        self.assertEqual(self.d('stats.missing'), 3)
        self.assertEqual(self.d('stats.stillMissing'), 1)
        self.assertIsNone(self.d('pending["lk-1"]'))
        self.assertTrue(any('WARN npc lk-1: corpse still missing on B after 2 resend(s)' in line
                            for line in self.lk()), self.lk())
        self.assertEqual(self.counts(), {'A': 1, 'B': 0})
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)

    def test_corpse_taken_away_before_the_check_is_dropped(self):
        self.die(copies=('A',))
        self.run_lua('DRAGGED = DRAG(LAST_CORPSE())')
        self.step(7000)
        self.assertEqual((self.d('stats.gone'), self.d('stats.asked')), (1, 0))
        self.assertEqual(self.h.pending(), [])

    def test_nobody_near_nothing_asked(self):
        self.die(copies=('A',))
        self.h.move_player('A', 300, 300, 0)
        self.h.move_player('B', 300, 300, 0)
        self.step(7000)
        self.assertEqual((self.d('stats.nobody'), self.d('stats.asked')), (1, 0))

    def test_laid_down_corpse_is_tracked_again(self):
        self.die()
        self.step(7000)
        self.step(5000)
        self.run_lua('RISEN = RISE(LAST_CORPSE())')
        self.ev('LivingKnox.Bodies.scanAll()')
        self.h.advance_ms(2000)
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('RISEN:isDead()'), True)
        self.assertEqual(self.d('stats.tracked'), 2)
        self.assertEqual(self.d('pending["lk-1"].why'), 'laid down')

    def test_client_check_unloaded_square_and_count_fallback(self):
        self.run_lua('UNLOADED[#UNLOADED + 1] = { 200, 210, 200, 210 }', 'B')
        self.assertEqual(self.h.eval('B', 'LivingKnox.DeathView.check({ id = "lk-1", o = "DeadBody-9", x = 205, '
                                          'y = 205, z = 0 })'), 'unloaded')
        self.h.eval('B', 'NET_ADD(77, 3, 102, 102, 0)')
        self.assertEqual(self.h.eval('B', 'LivingKnox.DeathView.check({ id = "lk-1", n = 1, x = 102, y = 102, '
                                          'z = 0 })'), 'present')
        self.assertEqual(self.h.eval('B', 'LivingKnox.DeathView.check({ id = "lk-1", n = 2, x = 102, y = 102, '
                                          'z = 0 })'), 'missing')
        self.assertEqual(self.h.eval('B', 'LivingKnox.DeathView.check({ id = "lk-1", o = "DeadBody-77", x = 103, '
                                          'y = 101, z = 0 })'), 'present')
        self.assertEqual([m['command'] for m in self.h.pending()], ['corpseMissing'])


class SoloDeathTests(DeathBase):
    mode = 'solo'

    def test_solo_kill_one_corpse_after_the_update_and_one_fact(self):
        zid = self.npc()
        while not self.h.eval('solo', f'HARNESS.zombies[{zid}] == nil or HARNESS.zombies[{zid}]:isDead()'):
            self.hit(zid, 100.0)
        self.h.tick(2)
        self.assertEqual(self.h.eval('solo', 'DEATHS'), 1)
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        self.assertEqual((self.facts(), self.ev('FACTS[1].cause'), self.ev('FACTS[1].killer')), (1, 'melee', 'A'))
        self.run_lua('DRAGGED = DRAG(LAST_CORPSE())')
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIs(self.ev('DRAGGED:isDead()'), False)
        self.run_lua('LET_GO(DRAGGED)')
        self.assertEqual(self.ev('TAGGED_CORPSES("lk-1")'), 1)
        self.assertEqual(self.facts(), 1)

    def test_suite_lk_death_passes_on_the_doubles(self):
        self.init()
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.death", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.death')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.death", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(6000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(50)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 4, results)
        self.assertTrue(report.ok, results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKD] measure')]
        self.assertTrue(any('laid down +1' in line for line in measures), measures)
        self.assertTrue(any('nocopy: corpses 1, deaths +1, tracked +0' in line for line in measures), measures)


class SourceTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)

    def test_mod_sources_are_kahlua_safe(self):
        for rel in ('server/LivingKnox/LK_Health.lua', 'server/LivingKnox/LK_Bodies.lua',
                    'server/LivingKnox/LK_Death.lua', 'client/LivingKnox/LK_DeathClient.lua',
                    'shared/LivingKnox/LK_Identity.lua'):
            raw = (LUA / rel).read_bytes()
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('utf-8'), flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), rel)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.'):
                self.assertIsNone(re.search(pattern, code), (rel, pattern))


if __name__ == '__main__':
    unittest.main()
