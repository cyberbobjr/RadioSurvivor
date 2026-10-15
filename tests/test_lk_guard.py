"""Tests hors jeu de la neutralisation des corps de PNJ Living Knox (LK02-T04) : LK_ZombieGuard.lua.

    python RadioSurvivor/tests/test_lk_guard.py

Banc tests/harness.py et doublures de tests/test_lk_bodies.py (création B réelle par LivingKnox.Bodies), complétées
ici. Les doublures reproduisent le Java 42.21.0 relevé ; elles NE PROUVENT PAS l'API réelle, seulement la logique :
- drapeaux de IsoZombie : setUseless(boolean), setNoTeeth(boolean) (IsoZombie.java:3971, 4542), setTarget
  (IsoZombie.java:4457), setEatBodyTarget(cible, force) à deux arguments (IsoZombie.java:4136 ; la surcharge à trois
  arguments exige un nombre), setThumpTarget (IsoMovingObject.java:411) ; un booléen manquant ou d'un autre type =
  « No implementation found » ;
- voix : SurvivorDesc propre à chaque zombie (IsoGameCharacter.java:2839), préfixe MaleZombie / FemaleZombie,
  getVoiceSoundName = préfixe + "Sprinter" (speedType 1) + "Voice" + A/B/C (IsoZombie.java:2888-2898) ; émetteur
  propre au zombie : isPlaying(String) compare le nom du GameSound joué, stopSoundByName(String) n'arrête qu'un son
  connu des scripts et ignore un nom inconnu (fmod/fmod/FMODSoundEmitter.java:166-186, 603-614) ; voix lancée par
  ZombieVocalsManager (VOCALS ci-dessous) seulement si le nom existe (playSoundImpl rend 0 sinon,
  FMODSoundEmitter.java:484-490) ; hurtSound = préfixe + "Hurt" à la création, getHurtSound/setHurtSound(String)
  (IsoGameCharacter.java:2950-2956) ; IsoZombie.playHurtSound ne joue rien (pose l'état Hit de la voix,
  IsoZombie.java:3473-3476) ; setFemaleEtc remet le préfixe vanilla et hurtSound (IsoZombie.java:3732-3747) ;
- réseau : seul le drapeau joueur réanimé arrive au client (NetworkZombieVariables.java:10-64) ; ni ModData ni
  noTeeth ni voix ; une copie client recréée est un nouvel objet au même onlineId ; un retour de chunk côté serveur
  donne un nouvel onlineId (ReanimatedPlayers.java:39-66) ;
- propriétaire : isRemoteZombie / getOwner du banc (NetworkZombieComponent.java:23).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import Base, lua_list, LUA, DEV_LUA  # noqa: E402

GUARD = 'shared/LivingKnox/LK_ZombieGuard.lua'
MOD_FILES = [LUA / GUARD]
DEV_FILES = [DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKGuard.lua',
             DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKPain.lua']

GUARD_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Z = C.IsoZombie
STOPPED, BROKEN_DESC = {}, false
local function bool(v, what)
    if type(v) ~= 'boolean' then error('No implementation found for ' .. what .. ' with argument ' .. tostring(v), 3) end
    return v
end
function Z:setUseless(b) self.useless = bool(b, 'setUseless') end
function Z:isUseless() return self.useless == true end
function Z:setNoTeeth(b) self.noTeeth = bool(b, 'setNoTeeth') end
function Z:isNoTeeth() return self.noTeeth == true end
function Z:getTarget() return self.target end
function Z:setTarget(t) self.target = t end
function Z:getEatBodyTarget() return self.eat end
function Z:setEatBodyTarget(t, force, speed)
    if speed ~= nil then H.num(speed, 'setEatBodyTarget') end
    bool(force, 'setEatBodyTarget')
    self.eat = t
end
function Z:getThumpTarget() return self.thump end
function Z:setThumpTarget(t) self.thump = t end
function Z:isMoving() return self.moving == true end
local Desc = H.class('SurvivorDesc')
function Desc:getVoicePrefix() return self.prefix end
function Desc:setVoicePrefix(p)
    if type(p) ~= 'string' then error('No implementation found for setVoicePrefix', 2) end
    self.prefix = p
end
function Z:getDescriptor()
    if BROKEN_DESC then error('RuntimeException: descriptor', 2) end
    local d = rawget(self, 'desc')
    if not d then
        d = setmetatable({ prefix = self.female and 'FemaleZombie' or 'MaleZombie' }, Desc)
        self.desc = d
    end
    return d
end
local LETTERS = { 'A', 'B', 'C' }
function Z:getVoiceSoundName()
    return self:getDescriptor():getVoicePrefix() .. (self.speedType == 1 and 'Sprinter' or '') .. 'Voice'
        .. LETTERS[self.voiceChoice or 1]
end
function Z:getHurtSound()
    if self.hurt == nil then self.hurt = self:getDescriptor():getVoicePrefix() .. 'Hurt' end
    return self.hurt
end
function Z:setHurtSound(name)
    if type(name) ~= 'string' then error('No implementation found for setHurtSound', 2) end
    self.hurt = name
end
-- IsoZombie.playHurtSound : aucun son, état Hit de l'événement de voix (IsoZombie.java:3473-3476).
function Z:playHurtSound()
    self.zombieState = 'Hit'
    return 0
end
-- Remise du préfixe vanilla (IsoZombie.java:3732-3747 ; appelée par PersistentOutfits, useDescriptor, etc.).
function Z:setFemaleEtc(female)
    self.female = female
    self:getDescriptor():setVoicePrefix(female and 'FemaleZombie' or 'MaleZombie')
    self.hurt = self:getDescriptor():getVoicePrefix() .. 'Hurt'
end
-- Sons connus des scripts (sounds_zombie_voice_*.txt) ; un nom inconnu n'est jamais joué ni arrêté.
KNOWN_SOUNDS = {}
for _, g in ipairs({ 'Male', 'Female' }) do
    for _, v in ipairs({ 'VoiceA', 'VoiceB', 'VoiceC', 'SprinterVoiceA', 'SprinterVoiceB' }) do
        KNOWN_SOUNDS[g .. 'Zombie' .. v] = true
    end
end
local Emitter = H.class('CharacterSoundEmitter')
function Emitter:isPlaying(name)
    if type(name) ~= 'string' then error('No implementation found for isPlaying', 2) end
    return self.playing[name] == true
end
function Emitter:stopSoundByName(name)
    if type(name) ~= 'string' then error('No implementation found for stopSoundByName', 2) end
    if KNOWN_SOUNDS[name] and self.playing[name] then
        self.playing[name] = nil
        STOPPED[#STOPPED + 1] = name
    end
    return 0
end
function Z:getEmitter()
    local e = rawget(self, 'emitter')
    if not e then
        e = setmetatable({ owner = self, playing = {} }, Emitter)
        self.emitter = e
    end
    return e
end
-- ZombieVocalsManager.playSound : la voix du zombie si aucune n'est en cours (ZombieVocalsManager.java:171-191).
function VOCALS(zb)
    local e = zb:getEmitter()
    for name in pairs(e.playing) do
        if KNOWN_SOUNDS[name] then return name end
    end
    local name = zb:getVoiceSoundName()
    if KNOWN_SOUNDS[name] then
        e.playing[name] = true
        return name
    end
    return nil
end
function PLAYING(zb)
    local out = {}
    for name in pairs(zb:getEmitter().playing) do out[#out + 1] = name end
    table.sort(out)
    return table.concat(out, ',')
end

-- Copie locale (client) d'un zombie du serveur : drapeau joueur réanimé seulement, ni ModData ni voix.
function MIRROR(id, x, y, z, owner)
    local zb = H.spawnZombie(id, x, y, z, owner)
    zb.reanimated = true
    return zb
end
-- Copie reçue par le réseau (NetworkZombieSimulator.parseZombie, NetworkZombieSimulator.java:176-188, 219) :
-- createZombieOutsideWorld pose l'identifiant de tenue persistante du paquet (VirtualZombieManager.java:265-271),
-- puis createRealZombieAlways déclenche OnZombieCreate AVANT d'ajouter le zombie à la liste
-- (VirtualZombieManager.java:207-210) ; onlineId (-1 jusque-là) et drapeaux (joueur réanimé,
-- NetworkZombieVariables.java:40) ne sont posés qu'ensuite. Le gestionnaire de voix peut passer dans la même image,
-- avant OnTick (IngameState.java:1543, CollisionManager.java:297, OnTick en 1681).
function NET_CREATE(id, x, y, z, owner, outfitId, reanimated, female)
    local zb = setmetatable({ __id = id, onlineID = -1, owner = owner, outfitId = outfitId, female = female == true },
        Z)
    H.trigger('OnZombieCreate', zb)
    H.place(zb, x, y, z)
    H.zombieList:add(zb)
    zb.onlineID = id
    H.zombies[id] = zb
    zb.reanimated = reanimated == true
    return zb
end
function STATE(zb)
    if zb == nil then return 'nil' end
    return 'useless=' .. tostring(zb.useless == true) .. ' noTeeth=' .. tostring(zb.noTeeth == true)
        .. ' target=' .. tostring(zb.target ~= nil) .. ' eat=' .. tostring(zb.eat ~= nil)
        .. ' thump=' .. tostring(zb.thump ~= nil) .. ' voice=' .. tostring(zb.desc and zb.desc.prefix or 'default')
end
'''

SILENT = 'LKSilentZombie'
REST = 'useless=true noTeeth=true target=false eat=false thump=false voice=' + SILENT


class GuardBase(Base):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, GUARD_DOUBLES)
            h.load(m, GUARD)
        return h

    def guard(self, m=None):
        return self.ev('LivingKnox.ZombieGuard', m)

    def slow(self, n=1):
        self.h.tick(n * self.ev('LivingKnox.ZombieGuard.SLOW_EVERY'))

    def state(self, m, zid):
        return self.h.eval(m, f'STATE(HARNESS.zombies[{zid}])')

    def npc(self, x=102, y=102):
        """PNJ créé par Bodies.spawn sur l'autorité ; rend son onlineID."""
        self.init()
        npc_id, body = self.spawn(x, y)
        self.assertEqual(npc_id, 'lk-1')
        return body.onlineID

    def bother(self, m, zid):
        """Comportements de zombie posés par le moteur sur la copie de la machine m."""
        self.h.load(m, f'local zb = HARNESS.zombies[{zid}]; zb.target = HARNESS.players.A; zb.eat = {{}}; '
                       f'zb.thump = {{}}; zb.useless = false')


class MultiplayerTests(GuardBase):
    def mirror(self, zid, owner='server', machines=('A', 'B')):
        srv = self.h.zombie('server', zid)
        for c in machines:
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        srv.owner = owner
        self.h.owners[zid] = owner

    def roster_messages(self):
        return [m for m in self.h.pending() if m['module'] == 'LivingKnox' and m['command'] == 'guardRoster']

    def ready(self, owner='server'):
        """PNJ créé, copies chez A et B, listes livrées, copies retrouvées."""
        zid = self.npc()
        self.mirror(zid, owner)
        self.slow()
        self.h.pump()
        self.slow()
        self.h.pump()
        return zid

    def test_server_simulated_body_rest_flags_roster_and_client_voices(self):
        zid = self.npc()
        self.h.spawn_zombie(2000, 103, 102, 0)  # zombie vanilla voisin, partout
        for m in ('server', 'A', 'B'):
            self.bother(m, 2000)
        self.bother('server', zid)
        self.slow()
        srv = self.state('server', zid)
        self.assertEqual(srv, 'useless=true noTeeth=true target=false eat=false thump=false voice=default')
        rosters = self.roster_messages()
        self.assertEqual(sorted(m['to'] for m in rosters), ['A', 'B'])
        outfit = self.ev(f'HARNESS.zombies[{zid}]:getPersistentOutfitID()')
        self.assertEqual(outfit, 98 * 65536 + 1)  # descripteur partagé, emplacement 0
        self.assertEqual(rosters[0]['args'], {'rev': 1, 'bodies': {1: {'o': zid, 'p': outfit, 'id': 'lk-1',
                                                                          't': False}}})
        hellos = [m for m in self.h.pending() if m['command'] == 'guardHello']
        self.assertEqual(sorted(m['from'] for m in hellos), ['A', 'B'])
        self.h.pump()
        self.mirror(zid)  # copies créées après la liste : retrouvées par le sondage
        for c in ('A', 'B'):
            self.bother(c, zid)
            self.assertEqual(self.h.eval(c, f'VOCALS(HARNESS.zombies[{zid}])'), 'MaleZombieVoiceA')  # gémit déjà
        self.slow()
        for c in ('A', 'B'):
            # Pas simulateur : noTeeth et voix seulement ; useless, cible, repas laissés au propriétaire.
            self.assertEqual(self.state(c, zid), 'useless=false noTeeth=true target=true eat=true thump=true voice='
                             + SILENT)
            self.assertIn('MaleZombieVoiceA', lua_list(self.h.eval(c, 'STOPPED')))
            self.assertEqual(self.h.eval(c, f'PLAYING(HARNESS.zombies[{zid}])'), '')
            self.assertEqual(self.h.eval(c, f'HARNESS.zombies[{zid}]:getHurtSound()'), SILENT + 'Hurt')
            self.assertIsNone(self.h.eval(c, f'rawget(HARNESS.zombies[{zid}], "__modData")'))
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.state(m, 2000), 'useless=false noTeeth=false target=true eat=true thump=true '
                                                  'voice=default', m)
        self.assertEqual(self.h.eval('server', f'HARNESS.zombies[{zid}]:getHurtSound()'), 'MaleZombieHurt')
        self.assertEqual(self.h.pending(), [])  # liste inchangée : rien de renvoyé

    def test_owner_client_applies_rest_flags_and_a_transferred_owner_reapplies(self):
        zid = self.ready(owner='A')
        self.bother('A', zid)
        self.bother('B', zid)
        self.bother('server', zid)
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual(self.state('A', zid), REST)
        self.assertEqual(self.state('B', zid), 'useless=false noTeeth=true target=true eat=true thump=true voice='
                         + SILENT)
        # Serveur : un client possède le corps -> noTeeth seulement, le reste vient du propriétaire.
        self.assertEqual(self.state('server', zid), 'useless=false noTeeth=true target=true eat=true thump=true '
                                                    'voice=default')
        self.h.set_owner(zid, 'B')
        self.bother('A', zid)
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual(self.state('B', zid), REST)
        self.assertIn('target=true', self.state('A', zid))
        self.h.set_owner(zid, 'server')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual(self.state('server', zid),
                         'useless=true noTeeth=true target=false eat=false thump=false voice=default')

    def test_travel_flag_never_lifts_useless(self):
        # LK06-T10 : un corps non useless réagit aux bruits (IsoZombie.RespondToSound, IsoZombie.java:1309) ; le
        # drapeau de trajet reste publié (champ t) mais le simulateur garde useless pendant tout le trajet.
        zid = self.ready(owner='A')
        self.assertIs(self.ev('LivingKnox.ZombieGuard.setTravelling("lk-1", true)'), True)
        self.assertIs(self.h.eval('A', 'LivingKnox.ZombieGuard.setTravelling("lk-1", true)'), False)  # client
        self.slow()
        self.assertEqual(self.roster_messages()[0]['args']['bodies'][1]['t'], True)
        self.h.pump()
        self.bother('A', zid)
        self.slow()
        self.assertIs(self.h.eval('A', 'LivingKnox.ZombieGuard.isTravelling("lk-1")'), True)
        self.assertEqual(self.state('A', zid), REST)
        self.ev('LivingKnox.ZombieGuard.setTravelling("lk-1", false)')
        self.slow()
        self.h.pump()
        self.slow()
        self.assertEqual(self.state('A', zid), REST)

    def test_chunk_return_on_the_server_and_client_recreation_are_reapplied(self):
        zid = self.ready()
        rev = self.h.eval('A', 'LivingKnox.ZombieGuard.roster.rev')
        # Retour de chunk côté serveur : même objet, nouvel onlineID ; les clients le recréent sous ce numéro.
        self.run_lua('UNLOAD(90, 120, 90, 120)')
        self.run_lua('RELOAD()')
        new = self.ev('LivingKnox.Bodies.bound["lk-1"]:getOnlineID()')
        self.assertNotEqual(new, zid)
        for c in ('A', 'B'):
            self.h.machine(c).H.removeZombie(zid)
        self.mirror(new)
        self.slow()
        self.assertEqual(self.roster_messages()[0]['args']['bodies'][1]['o'], new)
        self.h.pump()
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.roster.rev'), rev + 1)
        self.slow()
        for c in ('A', 'B'):
            self.assertIn('voice=' + SILENT, self.state(c, new))
        # Copie client recréée après 5 s sans paquet : nouvel objet, même onlineID.
        self.h.machine('A').H.removeZombie(new)
        self.mirror(new, machines=('A',))
        self.assertIn('voice=default', self.state('A', new))
        self.slow()
        self.assertIn('voice=' + SILENT, self.state('A', new))

    def test_untagged_and_unknown_zombies_are_never_touched(self):
        zid = self.ready()
        # Joueur réanimé sans étiquette (vrai joueur mort) sur le serveur et chez les clients.
        self.h.spawn_zombie(3000, 104, 104, 0)
        for m in ('server', 'A', 'B'):
            self.h.eval(m, 'rawset(HARNESS.zombies[3000], "reanimated", true)')
            self.bother(m, 3000)
        # Chez A : zombie ordinaire qui porte l'onlineID du PNJ (copie du PNJ absente ici).
        self.h.machine('A').H.removeZombie(zid)
        self.h.machine('A').H.spawnZombie(zid, 110, 110, 0, 'A')
        self.bother('A', zid)
        self.slow(3)
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.state(m, 3000), 'useless=false noTeeth=false target=true eat=true thump=true '
                                                  'voice=default', m)
        self.assertEqual(self.state('A', zid), 'useless=false noTeeth=false target=true eat=true thump=true '
                                               'voice=default')

    def test_hello_answered_to_the_requester_only_and_older_rosters_ignored(self):
        zid = self.ready()
        self.h.load('B', 'LivingKnox.ZombieGuard.roster = { rev = -1, count = 0, byId = {}, byOnline = {} }\n'
                         'LivingKnox.ZombieGuard.cache = {}\nLivingKnox.ZombieGuard.state.hello = 0')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        hellos = [m for m in self.h.pending() if m['command'] == 'guardHello']
        self.assertEqual([m['from'] for m in hellos], ['B'])
        self.h.pump(limit=1)
        answers = self.roster_messages()
        self.assertEqual([m['to'] for m in answers], ['B'])
        self.h.pump()
        self.assertEqual(self.h.eval('B', 'LivingKnox.ZombieGuard.roster.byId["lk-1"].o'), zid)
        # Liste plus ancienne livrée après une plus récente (RELIABLE non ordonné) : ignorée.
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'guardRoster', {'rev': 0})
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.roster.byId["lk-1"].o'), zid)
        # Liste vide plus récente (table vide reçue nil) : corps oublié, copie plus touchée.
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'guardRoster', {'rev': 99})
        self.assertIsNone(self.h.eval('A', 'LivingKnox.ZombieGuard.cache["lk-1"]'))

    def test_bounded_cost_on_the_client(self):
        for i in range(500):
            self.h.machine('A').H.spawnZombie(5000 + i, 150 + i % 20, 150 + i // 20, 0, 'server')
        self.slow(2)
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.stats.scanned'), 0)  # liste vide : aucun sondage
        zid = self.ready()
        budget = self.ev('LivingKnox.ZombieGuard.SCAN_BUDGET')
        self.h.load('A', 'LivingKnox.ZombieGuard.stats.scanned = 0')
        self.slow()
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.stats.scanned'), budget)
        self.slow(10)  # au plus un tour de liste en ceil(502 / budget) tranches : la copie est retrouvée
        self.assertIn('voice=' + SILENT, self.state('A', zid))
        self.assertEqual(self.h.errors('A'), [])



    def test_lit_campfire_reported_by_the_server_only(self):
        """LK04-T06 : hasLitCampfire passe par les systèmes de GlobalObject du serveur (IsoGridSquare.java:9740-9757) ;
        un client MP qui simule le corps ne voit jamais le feu, mais voit la plante (CGlobalObjects)."""
        zid = self.ready('server')
        self.h.load('server', f'local z = HARNESS.zombies[{zid}]; z.moving = true; '
                              f'z.square.campfire = {{ isLit = true }}')
        self.slow(2)
        warns = [line for line in self.lk() if 'lit campfire' in line]
        self.assertEqual(len(warns), 1, self.lk())
        self.assertIn('WARN npc lk-1 is on a lit campfire at 102,102,0', warns[0])
        self.h.set_owner(zid, 'A')   # A simule désormais sa copie (la même, retrouvée par la garde)
        self.h.load('A', f'local z = HARNESS.zombies[{zid}]; z.moving = true; z.square.campfire = {{ isLit = true }}')
        self.slow(2)
        self.assertEqual([line for line in self.lk('A') if 'lit campfire' in line], [])
        self.h.load('A', f'HARNESS.zombies[{zid}].square.plant = {{ state = "seeded" }}')
        self.slow(2)
        self.assertEqual(len([line for line in self.lk('A') if 'farming plant' in line]), 1, self.lk('A'))

class AppearanceTests(GuardBase):
    """LK03-T06 : apparition propre chez les clients MP (zombie temporaire jamais envoyé, copie muette dès sa
    création, livraison non ordonnée, client arrivé après, liste périmée)."""

    def roster_messages(self):
        return [m for m in self.h.pending() if m['module'] == 'LivingKnox' and m['command'] == 'guardRoster']

    def body(self):
        """PNJ créé sur le serveur ; rend (onlineID, identifiant de tenue persistante) du corps."""
        zid = self.npc()
        return zid, self.ev(f'HARNESS.zombies[{zid}]:getPersistentOutfitID()')

    def net_create(self, m, zid, outfit, reanimated=True, owner='server'):
        self.h.eval(m, f'NET_CREATE({zid}, 102, 102, 0, "{owner}", {outfit}, {str(reanimated).lower()})')

    def vocals(self, m, zid):
        return self.h.eval(m, f'VOCALS(HARNESS.zombies[{zid}])')

    def playing(self, m, zid):
        return self.h.eval(m, f'PLAYING(HARNESS.zombies[{zid}])')

    def voice(self, m, zid):
        return self.h.eval(m, f'HARNESS.zombies[{zid}]:getDescriptor():getVoicePrefix()')

    def test_temporary_zombie_never_present_when_the_server_sends_zombies(self):
        """NetworkZombiePacker.postupdate (ServerMap.java:548) part après le Lua de l'image et n'envoie que les zombies
        de la liste : relevé de la liste du serveur à la fin de chaque image (abonné OnTick inscrit en dernier)."""
        self.run_lua('SENT = {}\nEvents.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'SENT[zb.onlineID] = true end end)')
        self.init()
        npc_id, body = self.spawn()
        self.assertEqual(npc_id, 'lk-1')
        calls = [c.split(':')[0] if c.startswith('addZombiesInOutfit') else c for c in self.calls()]
        self.assertLess(calls.index('addZombiesInOutfit'), calls.index('removeFromWorld:1000'))
        self.assertLess(calls.index('removeFromWorld:1000'), calls.index('reanimate'))
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 1)  # dès le retour de spawn
        # La liste des corps part dans le même appel, avant tout envoi de zombies.
        rosters = self.roster_messages()
        self.assertEqual(sorted(m['to'] for m in rosters), ['A', 'B'])
        self.assertEqual(rosters[0]['args']['bodies'][1]['o'], body.onlineID)
        self.h.tick(3)
        self.assertIsNone(self.ev('SENT[1000]'))      # zombie temporaire : jamais dans la liste à l'envoi
        self.assertIs(self.ev(f'SENT[{body.onlineID}]'), True)

    def test_copy_silent_from_its_creation_when_the_roster_comes_first(self):
        zid, outfit = self.body()
        self.h.pump()
        self.net_create('A', zid, outfit)
        # Même image, avant OnTick : le gestionnaire de voix ne trouve aucun son au nom muet.
        self.assertEqual(self.voice('A', zid), SILENT)
        self.assertIsNone(self.vocals('A', zid))
        self.assertEqual(self.playing('A', zid), '')
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.stats.preSilenced'), 1)
        self.h.tick(1)
        self.assertIs(self.h.eval('A', f'LivingKnox.ZombieGuard.cache["lk-1"] == HARNESS.zombies[{zid}]'), True)
        self.assertIn('noTeeth=true', self.state('A', zid))
        # Habillage par le descripteur partagé (setFemaleEtc remet le préfixe) : recoupé à l'image suivante.
        self.h.load('A', f'HARNESS.zombies[{zid}]:setFemaleEtc(false)')
        self.h.tick(1)
        self.assertEqual(self.voice('A', zid), SILENT)
        self.assertIsNone(self.vocals('A', zid))
        # Passé FRESH_MS, la reprise revient au rythme normal (APPLY_EVERY images).
        self.h.advance_ms(self.ev('LivingKnox.ZombieGuard.FRESH_MS') + 1)
        self.h.tick(1)
        self.assertIsNone(self.h.eval('A', 'LivingKnox.ZombieGuard.recent["lk-1"]'))
        self.assertEqual(self.h.errors('A'), [])

    def test_copy_born_before_the_roster_is_silenced_on_reception(self):
        """Livraison non ordonnée : la copie peut naître avant la liste ; elle est rendue muette (voix arrêtée) au
        moment même où la liste arrive, sans attendre le sondage borné."""
        zid, outfit = self.body()
        for c in ('A', 'B'):
            self.net_create(c, zid, outfit)
            self.assertEqual(self.vocals(c, zid), 'MaleZombieVoiceA')  # rien ne la désignait encore
        self.h.tick(1)
        self.assertEqual(self.playing('A', zid), 'MaleZombieVoiceA')
        self.h.pump(order='lifo')
        for c in ('A', 'B'):
            self.assertEqual(self.voice(c, zid), SILENT, c)
            self.assertEqual(self.playing(c, zid), '', c)
            self.assertEqual(self.h.eval(c, 'LivingKnox.ZombieGuard.stats.adopted'), 1)
            self.assertEqual(self.h.eval(c, 'LivingKnox.ZombieGuard.stats.scanned'), 0)  # sans sondage

    def test_late_client_copies_silenced_at_the_roster_answer(self):
        zid, outfit = self.body()
        self.h.pump()
        # B arrive : liste oubliée, copie recréée pendant son entrée en partie, avant toute liste.
        self.h.load('B', 'LivingKnox.ZombieGuard.roster = { rev = -1, count = 0, byId = {}, byOnline = {} }\n'
                         'LivingKnox.ZombieGuard.cache = {}\nLivingKnox.ZombieGuard.state.hello = 0\n'
                         f'HARNESS.removeZombie({zid})')
        self.net_create('B', zid, outfit)
        self.assertEqual(self.vocals('B', zid), 'MaleZombieVoiceA')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual([m['from'] for m in self.h.pending() if m['command'] == 'guardHello'], ['B'])
        self.h.pump()
        self.assertEqual(self.voice('B', zid), SILENT)
        self.assertEqual(self.playing('B', zid), '')

    def test_stale_roster_outfit_match_is_given_its_voice_back(self):
        """Un descripteur rendu puis repris par un vrai joueur réanimé avant la liste suivante : la copie est rendue
        muette dans OnZombieCreate (même identifiant de tenue), puis sa voix lui est rendue à l'image suivante
        (onlineId absent de la liste)."""
        zid, outfit = self.body()
        self.h.pump()
        self.net_create('A', 7777, outfit)
        self.assertEqual(self.voice('A', 7777), SILENT)
        self.h.tick(1)
        # Joueur réanimé d'un corps connu sans entrée à son onlineId : gardé muet HOLD_MS en attendant une liste
        # (retour de chunk, livraison non ordonnée), puis sa voix lui est rendue.
        self.assertEqual(self.voice('A', 7777), SILENT)
        self.h.advance_ms(self.ev('LivingKnox.ZombieGuard.HOLD_MS') + 1)
        self.h.tick(1)
        self.assertEqual(self.voice('A', 7777), 'MaleZombie')
        self.assertIsNone(self.h.eval('A', 'LivingKnox.ZombieGuard.held[HARNESS.zombies[7777]]'))
        self.assertEqual(self.h.eval('A', 'HARNESS.zombies[7777]:getHurtSound()'), 'MaleZombieHurt')
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.stats.restored'), 1)
        self.assertIsNone(self.h.eval('A', 'LivingKnox.ZombieGuard.cache["lk-1"]'))
        # Zombie ordinaire au même onlineId que le PNJ mais sans le drapeau joueur réanimé : jamais adopté.
        self.net_create('B', zid, 12 * 65536 + 3, reanimated=False)
        self.h.tick(1)
        self.assertEqual(self.voice('B', zid), 'MaleZombie')
        self.assertIsNone(self.h.eval('B', 'LivingKnox.ZombieGuard.cache["lk-1"]'))

    def test_chunk_return_publishes_at_once_with_the_new_identifiers(self):
        zid, outfit = self.body()
        self.h.pump()
        self.run_lua('UNLOAD(90, 120, 90, 120)')
        self.run_lua('RELOAD()')
        self.assertEqual(self.roster_messages(), [])
        self.scan_ticks()  # liaison par le balayage : liste publiée dans la même image
        new = self.ev('LivingKnox.Bodies.bound["lk-1"]:getOnlineID()')
        args = self.roster_messages()[0]['args']['bodies'][1]
        self.assertEqual((args['o'], args['p']), (new, self.ev(f'HARNESS.zombies[{new}]:getPersistentOutfitID()')))
        self.h.pump()
        self.h.load('A', f'HARNESS.removeZombie({zid})')
        self.net_create('A', new, args['p'])
        self.assertEqual(self.voice('A', new), SILENT)
        self.assertIsNone(self.vocals('A', new))

    def test_chunk_return_copy_born_before_the_new_roster_stays_silent(self):
        """Campagne MP du 2026-10-15 (lk.spawnclean) : corps sorti de la liste avec son chunk, copie recréée à son
        retour AVANT la nouvelle liste. Son identifiant de tenue est retenu (Guard.gone) : muette dès sa création,
        gardée muette jusqu'à l'adoption à la réception de la liste, jamais de préfixe vanilla entre-temps."""
        zid, outfit = self.body()
        self.h.pump()
        self.run_lua('UNLOAD(90, 120, 90, 120)')
        self.scan_ticks()
        self.h.pump()
        self.h.load('A', f'HARNESS.removeZombie({zid})')
        self.assertIsNone(self.h.eval('A', 'LivingKnox.ZombieGuard.roster.byId["lk-1"]'))
        self.assertIsNotNone(self.h.eval('A', f'LivingKnox.ZombieGuard.gone[{outfit}]'))
        self.run_lua('RELOAD()')
        self.scan_ticks()
        new = self.ev('LivingKnox.Bodies.bound["lk-1"]:getOnlineID()')
        p = self.ev(f'HARNESS.zombies[{new}]:getPersistentOutfitID()')
        self.net_create('A', new, p)   # paquet de zombie avant la commande Lua de la liste
        self.assertEqual(self.voice('A', new), SILENT)
        self.assertIsNone(self.vocals('A', new))
        self.h.tick(2)
        self.assertEqual(self.voice('A', new), SILENT)
        self.assertEqual(self.playing('A', new), '')
        self.h.pump()
        self.assertIs(self.h.eval('A', f'LivingKnox.ZombieGuard.cache["lk-1"] == HARNESS.zombies[{new}]'), True)
        self.assertIsNone(self.h.eval('A', f'LivingKnox.ZombieGuard.held[HARNESS.zombies[{new}]]'))
        self.assertIsNone(self.h.eval('A', f'LivingKnox.ZombieGuard.gone[{p}]'))
        self.h.advance_ms(self.ev('LivingKnox.ZombieGuard.HOLD_MS') + 1)
        self.h.tick(1)
        self.assertEqual(self.voice('A', new), SILENT)
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.stats.restored'), 0)
        self.assertEqual(self.h.errors('A'), [])

    def test_born_and_seen_tables_stay_bounded(self):
        zid, outfit = self.body()
        self.h.pump()
        for i in range(40):
            self.net_create('A', 6000 + i, 12 * 65536 + 1 + i, reanimated=False)
        self.h.tick(1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.seenCount'), 40)
        self.assertEqual(self.h.eval('A', '#LivingKnox.ZombieGuard.born'), 0)
        self.h.advance_ms(self.ev('LivingKnox.ZombieGuard.SEEN_MS') + 1)
        self.slow()
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombieGuard.seenCount'), 0)
        for i in range(40):  # zombies ordinaires : aucun changement de voix
            self.assertEqual(self.voice('A', 6000 + i), 'MaleZombie')


class SoloGuardTests(GuardBase):
    mode = 'solo'

    def test_silent_from_creation(self):
        """LK03-T06 : la garde est posée dans Bodies.spawn, avant la première image."""
        zid = self.npc()
        self.assertEqual(self.state('solo', zid), REST)
        self.assertIsNone(self.ev(f'VOCALS(HARNESS.zombies[{zid}])'))
        self.assertEqual(self.h.pending(), [])

    def test_solo_applies_everything_and_leaves_the_vanilla_neighbour(self):
        zid = self.npc()
        self.h.spawn_zombie(2000, 103, 102, 0)
        self.bother('solo', 2000)
        self.bother('solo', zid)
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual(self.state('solo', zid), REST)
        self.assertEqual(self.state('solo', 2000), 'useless=false noTeeth=false target=true eat=true thump=true '
                                                   'voice=default')
        self.assertEqual(self.h.pending(), [])
        # Idempotent : un second passage ne change rien.
        before = self.ev('LivingKnox.ZombieGuard.stats.actions')
        self.slow()
        self.assertEqual(self.ev('LivingKnox.ZombieGuard.stats.actions'), before)

    def test_pain_cry_voice_started_before_the_guard_is_stopped_whatever_its_name(self):
        """LK06-T06 : le cri de douleur est l'état Hit de la voix en cours ; une voix vanilla lancée sous un préfixe
        remis par le moteur (ici en sprinteur, puis vitesse changée : getVoiceSoundName ne la nomme plus) est arrêtée
        par son nom. Depuis LK03-T06, le corps est muet dès sa création (voir test_silent_from_creation)."""
        zid = self.npc()
        self.h.spawn_zombie(2000, 104, 102, 0)
        self.run_lua(f'local z = HARNESS.zombies[{zid}]; z:getDescriptor():setVoicePrefix("MaleZombie"); '
                     f'z.speedType = 1; z.voiceChoice = 2; VOCALS(z); '
                     f'z.speedType = 2; VOCALS(HARNESS.zombies[2000])')
        self.assertEqual(self.ev(f'PLAYING(HARNESS.zombies[{zid}])'), 'MaleZombieSprinterVoiceB')
        self.assertEqual(self.ev(f'HARNESS.zombies[{zid}]:getVoiceSoundName()'), 'MaleZombieVoiceB')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual(self.ev(f'PLAYING(HARNESS.zombies[{zid}])'), '')
        self.assertEqual(self.ev('LivingKnox.ZombieGuard.stats.voicesStopped'), 1)
        self.assertEqual(self.ev(f'HARNESS.zombies[{zid}]:getHurtSound()'), SILENT + 'Hurt')
        # Frappé ensuite : playHurtSound ne joue rien et le gestionnaire de voix ne trouve aucun son à ce nom.
        self.run_lua(f'local z = HARNESS.zombies[{zid}]; z:playHurtSound(); VOCALS(z)')
        self.assertEqual(self.ev(f'PLAYING(HARNESS.zombies[{zid}])'), '')
        self.assertEqual(self.ev(f'HARNESS.zombies[{zid}].zombieState'), 'Hit')
        # Le zombie vanilla voisin garde sa voix et son son de blessure.
        self.assertEqual(self.ev('PLAYING(HARNESS.zombies[2000])'), 'MaleZombieVoiceA')
        self.assertEqual(self.ev('HARNESS.zombies[2000]:getHurtSound()'), 'MaleZombieHurt')
        before = self.ev('LivingKnox.ZombieGuard.stats.actions')
        self.slow()
        self.assertEqual(self.ev('LivingKnox.ZombieGuard.stats.actions'), before)  # idempotent

    def test_prefix_reset_by_the_engine_is_cut_again_and_the_slow_pass_sweeps(self):
        zid = self.npc()
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        # setFemaleEtc (habillage, descripteur partagé) remet FemaleZombie ; la voix repart avant le passage.
        self.run_lua(f'local z = HARNESS.zombies[{zid}]; z:setFemaleEtc(true); VOCALS(z)')
        self.assertEqual(self.ev(f'PLAYING(HARNESS.zombies[{zid}])'), 'FemaleZombieVoiceA')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual(self.state('solo', zid), REST)
        self.assertEqual(self.ev(f'PLAYING(HARNESS.zombies[{zid}])'), '')
        self.assertEqual(self.ev(f'HARNESS.zombies[{zid}]:getHurtSound()'), SILENT + 'Hurt')
        # Voix vanilla encore jouée alors que le préfixe est déjà muet : seul le passage lent la cherche.
        self.run_lua(f'HARNESS.zombies[{zid}]:getEmitter().playing.MaleZombieVoiceC = true')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.assertEqual(self.ev(f'PLAYING(HARNESS.zombies[{zid}])'), 'MaleZombieVoiceC')
        self.slow()
        self.assertEqual(self.ev(f'PLAYING(HARNESS.zombies[{zid}])'), '')
        self.assertEqual(self.ev('LivingKnox.ZombieGuard.stats.voicesStopped'), 2)
        self.assertEqual(self.h.errors('solo'), [])

    def test_hazards_logged_once_and_voice_failure_logged_once(self):
        zid = self.npc()
        self.run_lua(f'HARNESS.zombies[{zid}].square.plant = true')
        self.slow(3)
        warns = [line for line in self.lk() if 'farming plant' in line]
        self.assertEqual(len(warns), 1, warns)
        self.assertIn('WARN npc lk-1 is on a farming plant at 102,102,0', warns[0])
        self.run_lua(f'HARNESS.zombies[{zid}].desc = nil; BROKEN_DESC = true')
        self.slow(3)
        errors = [line for line in self.lk() if 'voice cut failed' in line]
        self.assertEqual(len(errors), 1, errors)
        self.assertIs(self.ev('LivingKnox.ZombieGuard.voiceBroken'), True)
        self.assertIn('useless=true noTeeth=true', self.state('solo', zid))  # le reste continue

    def test_dev_suite_lists_with_world_tags(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKGuard.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.guard", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.guard')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.h.load('solo', 'shared/RST/suites/RST_LKPain.lua')
        pain = self.h.eval('solo', 'RST.list({ suite = "lk.pain", tags = "world" }, true)[1]')
        self.assertEqual(pain.name, 'lk.pain')
        self.assertEqual(lua_list(pain.tags), ['world'])
        self.assertIsNone(pain.error)


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        for path in MOD_FILES + DEV_FILES:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')
        for path in DEV_FILES:
            self.assertTrue(all(b < 128 for b in path.read_bytes()), f'{path.name}: non ASCII byte')

    def test_guard_never_reads_a_zombie_without_the_engine_marker(self):
        code = (LUA / GUARD).read_text(encoding='utf-8')
        self.assertIn('isReanimatedPlayer()', code)
        self.assertNotIn('getModData', code)  # l'autorité passe par Bodies.bound, le client par la liste du serveur


if __name__ == '__main__':
    unittest.main()
