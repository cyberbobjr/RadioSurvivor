"""Tests hors jeu de LK06-T04 (PNJ contre zombies vanilla, dans les deux sens) : server/LivingKnox/LK_Zombies.lua
(autorité), client/LivingKnox/LK_ZombiesClient.lua (client qui simule le zombie), branchement dans LK_Combat.lua
(cible zombie), LK_CombatClient.lua (cible retrouvée par son identifiant réseau) et LK_Decisions.lua (« fight zombie »).

    python RadioSurvivor/tests/test_lk_zombies.py

Banc tests/harness.py (serveur dédié et deux clients, ou solo), pile de test_lk_combat.py (corps, consignes, rapports,
armes, mêlée, tir) complétée de LK_Health.lua et des doublures ci-dessous, qui reproduisent le Java 42.21.0 relevé et
NE PROUVENT PAS l'API réelle :
- IsoZombie : setInvulnerable / isInvulnerable (drapeau local, IsoGameCharacter.java:11069-11075), isFakeDead ;
  santé d'un zombie vanilla (getHealth / setHealth), mort : serveur die() -> Kill(getAttackedBy()) -> OnZombieDead,
  solo Kill(arme, tueur) (IsoGameCharacter.java:13451-13496, doublures de test_lk_bodies.py) ;
- paquet du client propriétaire : santé de sa copie posée sur le serveur, die() si nulle (NetworkZombiePacker.java:
  100-101, 230 ; CLIENT_HEALTH de test_lk_bodies.py) ;
- HandWeapon : getMinDamage / getMaxDamage / isMelee (HandWeapon.java:787, 839 ; scripts weapon.txt : BareHands
  0,2-0,4, BaseballBat 0,8-1,1) ;
- addSound(source, x, y, z, rayon, volume) (LuaManager.java:9240, entiers ; doublure de test_lk_combat.py, source
  relevée ici) ; LosUtil.lineClear (LOS_RESULT imposé).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_combat import CombatBase  # noqa: E402

ZOMBIES = 'server/LivingKnox/LK_Zombies.lua'
ZOMBIES_CLIENT = 'client/LivingKnox/LK_ZombiesClient.lua'
HEALTH = 'server/LivingKnox/LK_Health.lua'
HEALTH_CLIENT = 'client/LivingKnox/LK_HealthClient.lua'
MOD_FILES = [LUA / ZOMBIES, LUA / ZOMBIES_CLIENT]
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKZombies.lua'
Z = 'LivingKnox.Zombies'

ZOMBIE_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Zc = C.IsoZombie
local W = C.HandWeapon
local function bool(v, what)
    if type(v) ~= 'boolean' then error('No implementation found for ' .. what .. ' with argument ' .. tostring(v), 3) end
    return v
end
function Zc:isInvulnerable() return self.invulnerable == true end
function Zc:setInvulnerable(b) self.invulnerable = bool(b, 'setInvulnerable') end
function Zc:isFakeDead() return self.fakeDead == true end
function Zc:setFakeDead(b) self.fakeDead = bool(b, 'setFakeDead') end
function Zc:isCrawling() return self.crawling == true end
DAMAGE_STATS = { ['Base.BareHands'] = { 0.2, 0.4 }, ['Base.BaseballBat'] = { 0.8, 1.1 }, ['Base.Pistol'] = { 0.6, 1.0 },
    ['Base.KitchenKnife'] = { 0.4, 0.7 } }
function W:getMinDamage() return (DAMAGE_STATS[self.t] or { 0, 0 })[1] end
function W:getMaxDamage() return (DAMAGE_STATS[self.t] or { 0, 0 })[2] end
function W:isMelee() return not self:isRanged() end
-- Bruits : source relevée (addSound de test_lk_combat.py, entiers exigés).
local rawAddSound = addSound
addSound = function(src, x, y, z, r, v)
    rawAddSound(src, x, y, z, r, v)
    NOISES[#NOISES].src = src
end
-- Mort d'un zombie vue sur cette machine (OnZombieDead).
ZOMBIE_DEATHS = {}
Events.OnZombieDead.Add(function(zb) ZOMBIE_DEATHS[#ZOMBIE_DEATHS + 1] = zb.onlineID end)
-- Zombie vanilla : santé posée sur cette machine.
function VANILLA(zid, health) local zb = H.zombies[zid]; zb.health = health; return zb end
'''


class ZombieBase(CombatBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, ZOMBIE_DOUBLES)
            h.load(m, HEALTH)
            h.load(m, ZOMBIES)
            if m != 'server':
                h.load(m, HEALTH_CLIENT)
                h.load(m, ZOMBIES_CLIENT)
        return h

    def z(self, code, m=None):
        return self.ev(f'{Z}.' + code, m)

    def zstat(self, name, m=None):
        return self.ev(f'{Z}.stats.{name} or 0', m)

    def body_xy(self):
        b = self.h.zombie(self.srv, self.npc_zid)
        return b.x, b.y

    def vanilla(self, zid, dx, dy, owner='server', health=2.0):
        """Zombie vanilla à (corps + dx, dy) sur toutes les machines, santé health partout."""
        x, y = self.body_xy()
        self.h.spawn_zombie(zid, x + dx, y + dy, 0, owner=owner if self.mode == 'mp' else 'server')
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            self.h.eval(m, f'VANILLA({zid}, {health}) ~= nil')
        return zid

    def health(self, zid, m=None):
        return self.h.eval(m or self.srv, f'HARNESS.zombies[{zid}]:getHealth()')

    def ref(self):
        return self.ev('LivingKnox.Health.reference("lk-1")')

    def seconds(self, s, owner_packets=()):
        """s secondes d'images ; réseau livré ; paquets de santé des clients propriétaires de owner_packets."""
        for _ in range(int(s * 1000 / self.h.tick_ms)):
            self.h.tick(1)
            if self.mode == 'mp':
                self.h.pump()
                for zid in owner_packets:
                    self.owner_packet(zid)

    def owner_packet(self, zid):
        """Paquet de zombie du client propriétaire : santé de sa copie posée sur le serveur (die() si nulle)."""
        owner = self.h.owners.get(zid)
        if owner in (None, 'server'):
            return
        srv = self.h.zombie('server', zid)
        if srv is None or srv.killDone:
            return
        h = self.health(zid, owner)
        self.h.eval('server', f'(function() CLIENT_HEALTH(HARNESS.zombies[{zid}], {h}) return true end)()')


class MultiplayerZombieTests(ZombieBase):
    def ready(self, owner='A'):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for cl in ('A', 'B'):
            self.h.eval(cl, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)
        self.h.move_player('A', srv.x + 8, srv.y)
        self.h.move_player('B', srv.x + 9, srv.y)
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.npc_zid = zid
        return zid

    def test_npc_kills_a_zombie_simulated_by_another_client_once(self):
        self.ready('A')                                              # corps du PNJ simulé par A
        self.assertIs(self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")'), True)
        zid = self.vanilla(5001, 1.0, 0, owner='B')                  # zombie simulé par B
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 1)
        o = self.c('get("lk-1")')
        self.assertEqual((o.k, o.u, o.zo, o.t, o.phase), ('zombie', 'z:5001', 5001, 'Base.BaseballBat', 'strike'))
        self.relayed()
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.remote.d["lk-1"].zo'), zid)
        healths = []
        for _ in range(40):
            self.seconds(0.5, owner_packets=(zid,))
            healths.append(self.health(zid))
            if self.h.zombie('server', zid).killDone:
                break
        srv = self.h.zombie('server', zid)
        self.assertTrue(srv.killDone)                                # mort décidée par le serveur
        hits = self.zstat('hits')
        self.assertEqual(self.zstat('kills'), 1)
        self.assertEqual(lua_list(self.ev('ZOMBIE_DEATHS')), [zid])  # une seule mort
        self.assertEqual(self.c('stats.applied'), hits)              # chaque touche appliquée une fois
        self.assertEqual(self.c('stats.refused'), 0)
        # Coups non mortels : remis au seul client qui simule le zombie, abaissé une fois chez lui.
        self.assertEqual(self.zstat('hurtMessages'), hits - 1)
        self.assertEqual(self.h.eval('B', 'LivingKnox.ZombiesView.stats.applied'), hits - 1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombiesView.stats.received'), 0)
        self.assertEqual(sorted(healths, reverse=True), healths)    # santé du serveur jamais remontée
        # Dégâts = formule vanilla rejouée (aucune double application) : somme des coups non mortels.
        dealt = sum(self.z(f'damageOf("lk-1", {{ c = 1 }}, instanceItem("Base.BaseballBat"), {k})')
                    for k in range(1, hits))
        self.assertAlmostEqual(self.health(zid, 'B'), max(2.0 - dealt, 0.01), places=6)
        lines = [line for line in self.lk() if 'killed zombie z:5001' in line]
        self.assertEqual(len(lines), 1, self.lk())
        self.assertIs(self.ev(f'rawequal(HARNESS.zombies[{zid}].attackedBy, HARNESS.zombies[{self.npc_zid}])'), True)
        # Passage suivant : cible morte, fin de l'engagement, geste rendu.
        self.h.advance_ms(300)
        self.h.tick(1)
        self.assertIsNone(self.c('get("lk-1")'))
        self.assertTrue(any('melee #1 against zombie z:5001 ended after' in line and 'target dead' in line
                            for line in self.lk()), self.lk())
        self.assertEqual(self.h.errors('server'), [])

    def test_zombie_missing_on_the_body_owner_is_still_hit_through_the_authority(self):
        # LK05-T18 (campagne MP du 2026-10-15, camp) : zombie simulé par B et absent de la cellule de A, qui simule le
        # corps (copie distante retirée après 5 s sans paquet) : avant, aucun coup rapporté, PNJ tués sans riposte.
        # Touches rapportées quand même (nf), jugées par le serveur sur ses copies ; zombie tué, rien refusé.
        self.ready('A')
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        zid = self.vanilla(5011, 1.0, 0, owner='B')
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 1)
        self.relayed()
        self.h.eval('A', f'(function() HARNESS.removeZombie({zid}) return true end)()')
        self.assertIsNone(self.h.eval('A', f'LivingKnox.CombatView.zombieByOnlineId({zid})'))
        for _ in range(40):
            self.seconds(0.5)
            if self.h.zombie('server', zid).killDone:
                break
        self.assertTrue(self.h.zombie('server', zid).killDone)
        self.assertGreaterEqual(self.c('stats.blindReports or 0'), 1)
        self.assertGreaterEqual(self.h.eval('A', 'LivingKnox.CombatView.stats.blind or 0'), 1)
        self.assertEqual(self.c('stats.refused'), 0)
        self.assertTrue(any('target not seen there' in line for line in self.lk()), self.lk())
        self.assertTrue(any('missed here: target not found, reported to the authority' in line
                            for line in self.h.logs('A')), self.h.logs('A'))
        self.assertEqual(self.h.errors('server'), [])
        self.assertEqual(self.h.errors('A'), [])

    def test_lure_radius_on_a_server_assumes_the_poorest_random_hearing(self):
        # LK06-T11 (campagne MP du 2026-10-15) : option Ouïe au hasard (5 : normale ou faible) tirée par chaque machine :
        # copie du serveur normale (1,0), copie du client propriétaire faible (0,45), sourde au bruit d'attrait.
        self.ready('A')
        zid = self.vanilla(7111, 6, 0, owner='A')
        self.h.load('server', 'getWorldSoundManager = function() return { getHearingMultiplier = function() '
                              'return 1.0 end } end')
        r_normal = self.z(f'lureRadius(HARNESS.zombies[{zid}], LivingKnox.Bodies.find("lk-1"))', 'server')
        self.assertAlmostEqual(self.z(f'hearingOf(HARNESS.zombies[{zid}])', 'server'), 1.0)
        for opt in (4, 5):
            self.h.load('server', f'SandboxVars = SandboxVars or {{}}; SandboxVars.ZombieLore = {{ Hearing = {opt} }}')
            self.assertAlmostEqual(self.z(f'hearingOf(HARNESS.zombies[{zid}])', 'server'), 0.45, msg=opt)
        r_poor = self.z(f'lureRadius(HARNESS.zombies[{zid}], LivingKnox.Bodies.find("lk-1"))', 'server')
        self.assertGreaterEqual(r_poor, r_normal * 2)
        # Distance au bord du rayon pour une ouïe faible : attrait vanilla > 0 (d² < (r x 0,45)²).
        self.assertGreater((r_poor * 0.45) ** 2, 6 ** 2)
        self.h.load('server', 'SandboxVars.ZombieLore = { Hearing = 2 }')
        self.assertAlmostEqual(self.z(f'hearingOf(HARNESS.zombies[{zid}])', 'server'), 1.0)

    def test_blind_hit_far_on_the_server_copies_is_refused_without_warning(self):
        # LK05-T18 : un rapport nf est jugé comme les autres : zombie loin sur les copies du serveur = refusé (INFO).
        self.ready('A')
        zid = self.vanilla(5012, 1.0, 0, owner='B')
        self.c(f'engage("lk-1", HARNESS.zombies[{zid}])')
        self.relayed()
        self.h.load('A', 'LivingKnox.CombatView.tick = function() end')
        x, y = self.body_xy()
        self.h.move_zombie(zid, x + 6, y)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'combatHit', self.h.player('server', 'A'),
                    {'id': 'lk-1', 'c': 1, 'n': 1, 'u': f'z:{zid}', 'x': 0, 'y': 0, 'z': 0, 'nf': True})
        self.assertEqual(self.why('out of reach') + self.why('not striking'), 1)
        self.assertEqual(self.zstat('hits'), 0)
        refused = [line for line in self.lk() if 'refused' in line and 'lk-1' in line]
        self.assertTrue(refused, self.lk())
        self.assertFalse(any('WARN' in line for line in refused), refused)

    def test_hit_on_a_zombie_out_of_reach_or_forged_is_refused(self):
        self.ready('A')
        zid = self.vanilla(5002, 1.0, 0, owner='server')
        self.c(f'engage("lk-1", HARNESS.zombies[{zid}])')
        self.relayed()
        self.h.load('A', 'LivingKnox.CombatView.tick = function() end')
        args = {'id': 'lk-1', 'c': 1, 'n': 1, 'u': 'z:5002', 'x': 0, 'y': 0, 'z': 0}
        fire = lambda who, **kw: self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'combatHit',  # noqa: E731
                                             self.h.player('server', who), dict(args, **kw))
        fire('B')                                                     # pas le propriétaire du corps
        self.assertEqual(self.why('not the owner'), 1)
        fire('A', n=2, u='z:9999')
        self.assertEqual(self.why('wrong target'), 1)
        x, y = self.body_xy()
        self.h.move_zombie(zid, x + 6, y)                             # zombie éloigné sur les copies du serveur
        fire('A', n=3)
        self.assertEqual(self.why('out of reach') + self.why('not striking'), 1)
        self.assertEqual(self.zstat('hits'), 0)
        self.assertAlmostEqual(self.health(zid), 2.0)

    def test_despawned_body_copy_removed_on_every_client(self):
        # Campagne MP du 2026-10-15 : corps retiré par le serveur, copie fantôme debout 83 s chez son propriétaire.
        zid = self.ready('A')
        z2 = self.vanilla(5009, 30.0, 0, owner='B')
        # Identifiant réattribué loin de la position annoncée : rien retiré ; message mal formé refusé.
        srv = self.h.zombie('server', z2)
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'bodyGone', {'o': z2, 'x': srv.x - 20, 'y': srv.y, 'z': 0})
        self.assertEqual(self.h.eval('B', 'LivingKnox.ZombiesView.stats.goneFar'), 1)
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'bodyGone', {'o': z2})
        self.assertEqual(self.h.eval('B', 'LivingKnox.ZombiesView.stats.goneRefused'), 1)
        self.assertIsNotNone(self.h.eval('B', f'LivingKnox.ZombiesView.zombieByOnlineId({z2})'))
        self.assertEqual(self.ev('select(2, LivingKnox.Bodies.despawn("lk-1", true))'), 1)
        self.h.pump()
        self.assertEqual(self.zstat('goneSent'), 1)
        for cl in ('A', 'B'):
            self.assertEqual(self.h.eval(cl, 'LivingKnox.ZombiesView.stats.goneRemoved'), 1, cl)
            self.assertIs(self.h.eval(cl, f'LivingKnox.ZombiesView.zombieByOnlineId({zid})'), None, cl)

    def test_server_simulated_zombie_hurt_on_the_server_only(self):
        self.ready('A')
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        zid = self.vanilla(5003, 1.0, 0, owner='server', health=5.0)
        self.c(f'engage("lk-1", HARNESS.zombies[{zid}])')
        self.relayed()
        self.seconds(3)
        self.assertGreaterEqual(self.zstat('hits'), 2)
        self.assertEqual(self.zstat('hurtMessages'), 0)               # aucun client ne simule ce zombie
        self.assertLess(self.health(zid), 5.0)
        self.assertAlmostEqual(self.health(zid, 'B'), 5.0)

    def test_hurt_message_applies_only_on_the_simulating_client_with_a_floor(self):
        self.ready('A')
        zid = self.vanilla(5004, 1.0, 0, owner='B', health=0.5)
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'zombieHurt', {'o': zid, 'd': 0.2})
        self.assertEqual(self.h.eval('A', 'LivingKnox.ZombiesView.stats.remote'), 1)
        self.assertAlmostEqual(self.health(zid, 'A'), 0.5)
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'zombieHurt', {'o': zid, 'd': 0.2})
        self.assertAlmostEqual(self.health(zid, 'B'), 0.3)
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'zombieHurt', {'o': zid, 'd': 5})
        self.assertAlmostEqual(self.health(zid, 'B'), 0.01)           # la mort reste au serveur
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'zombieHurt', {'o': zid, 'd': 'x'})
        self.assertEqual(self.h.eval('B', 'LivingKnox.ZombiesView.stats.refused'), 1)

    def horde(self):
        """Trois zombies vanilla au contact du corps (deux clients et le serveur les simulent)."""
        self.ready('A')
        for zid, dx, dy, owner in ((6001, 0.8, 0, 'A'), (6002, 0, 0.9, 'B'), (6003, -0.7, 0.3, 'server')):
            self.vanilla(zid, dx, dy, owner=owner)

    def test_horde_kills_the_npc_once_with_the_same_outcome_everywhere(self):
        self.horde()
        hp0 = self.ref()
        self.assertIsNotNone(hp0)
        self.seconds(0.9)
        self.assertEqual(self.zstat('attacks'), 0)                   # élan : première attaque après WINDUP_MS
        for _ in range(60):
            self.seconds(1)
            if self.ev('LivingKnox.Health.stats.deaths') > 0:
                break
        self.assertEqual(self.ev('LivingKnox.Health.stats.deaths'), 1)   # mort décidée une fois
        self.assertEqual(self.zstat('deaths'), 1)
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].state'), 'dead')
        body = self.h.zombie('server', self.npc_zid)
        self.assertIn(body.attackedBy.onlineID, (6001, 6002, 6003))
        attacks = self.zstat('attacks')
        self.assertEqual(attacks, sum(self.zstat(k) for k in ('avoided', 'scratch', 'laceration', 'bite')))
        self.assertGreater(self.zstat('bite') + self.zstat('laceration') + self.zstat('scratch'), 0)
        # Les clients proches ont reçu la même santé de référence (nulle) : même issue partout.
        self.h.advance_ms(600)
        self.h.tick(1)
        self.h.pump()
        for cl in ('A', 'B'):
            self.assertEqual(self.h.eval(cl, 'LivingKnox.HealthView.get("lk-1").hp'), 0)
        wounds = [line for line in self.lk() if 'by zombie z:600' in line]
        self.assertEqual(len(wounds), attacks - self.zstat('avoided'))
        # Plus aucune attaque une fois la mort décidée.
        self.seconds(3)
        self.assertEqual(self.zstat('attacks'), attacks)
        self.assertEqual(self.h.errors('server'), [])

    def test_outcomes_are_reproducible(self):
        def run():
            self.horde()
            self.seconds(12)
            out = [line.split('] ', 1)[-1] for line in self.lk() if 'by zombie z:' in line]
            return out, self.ref()
        first, hp1 = run()
        self.h.close()
        self.h = self.make()
        second, hp2 = run()
        self.assertTrue(first)
        self.assertEqual(first, second)
        self.assertEqual(hp1, hp2)
        # Tirage pur : même PNJ, même zombie, même attaque -> même issue ; plus d'attaquants -> plus de morsures.
        self.assertEqual(self.z('outcome("lk-1", 6001, 3, 1)'), self.z('outcome("lk-1", 6001, 3, 1)'))
        alone = [self.z(f'outcome("lk-7", 77, {n}, 1)') for n in range(1, 201)]
        crowd = [self.z(f'outcome("lk-7", 77, {n}, 3)') for n in range(1, 201)]
        self.assertGreater(crowd.count('bite'), alone.count('bite'))
        self.assertGreater(alone.count('avoided'), crowd.count('avoided'))

    def test_contact_reach_windup_and_who_attacks(self):
        self.ready('A')
        zid = self.vanilla(7001, 1.5, 0)                             # hors d'allonge
        self.seconds(3)
        self.assertEqual(self.zstat('attacks'), 0)
        x, y = self.body_xy()
        self.h.eval('server', f'(function() HARNESS.zombies[{zid}].crawling = true return true end)()')
        self.h.move_zombie(zid, x + 1.2, y)                           # rampant : allonge 1,3
        self.seconds(1.2)
        self.assertEqual(self.zstat('attacks'), 1)
        self.h.move_zombie(zid, x + 3, y)                             # contact rompu : élan remis à zéro
        self.seconds(1)
        self.h.eval('server', f'(function() HARNESS.zombies[{zid}].crawling = false; '
                              f'HARNESS.zombies[{zid}].onFloor = true return true end)()')
        self.h.move_zombie(zid, x + 0.8, y)                           # renversé, pas rampant : n'attaque pas
        self.seconds(3)
        self.assertEqual(self.zstat('attacks'), 1)
        self.h.eval('server', f'(function() HARNESS.zombies[{zid}].onFloor = false; '
                              f'HARNESS.zombies[{zid}].useless = true return true end)()')
        self.seconds(3)                                               # corps d'un autre moteur : rien
        self.assertEqual(self.zstat('attacks'), 1)
        self.h.eval('server', f'(function() HARNESS.zombies[{zid}].useless = false; '
                              f'HARNESS.zombies[{zid}].fakeDead = true return true end)()')
        self.seconds(3)
        self.assertEqual(self.zstat('attacks'), 1)
        self.h.eval('server', f'(function() HARNESS.zombies[{zid}].fakeDead = false return true end)()')
        self.seconds(0.9)
        self.assertEqual(self.zstat('attacks'), 1)                    # nouvel élan
        self.seconds(0.6)
        self.assertEqual(self.zstat('attacks'), 2)
        self.seconds(2)
        self.assertEqual(self.zstat('attacks'), 3)                    # une attaque toutes les ATTACK_MS

    def test_lure_noise_when_a_zombie_sees_the_npc(self):
        self.ready('A')
        self.vanilla(7101, 6, 0)
        self.run_lua('NOISES = {}')
        self.seconds(0.5)
        noises = self.ev('NOISES')
        self.assertEqual(len(lua_list(noises)), 1)
        n = noises[1]
        x, y = self.body_xy()
        # LK06-T08 : rayon calculé pour que ce zombie l'entende (dehors tous deux : 6,5 x 1,25 + 1 -> 10), source nil
        # (une source zombie est ignorée par le moteur, WorldSoundManager.java:259-261).
        self.assertEqual((n.x, n.y, n.r, n.v), (int(x), int(y), 10, 20))
        self.assertIs(self.ev('NOISES[1].src == nil'), True)
        self.seconds(2)
        self.assertEqual(len(lua_list(self.ev('NOISES'))), 1)          # au plus une par LURE_MS
        self.seconds(1.2)
        self.assertEqual(len(lua_list(self.ev('NOISES'))), 2)
        self.run_lua('NOISES = {} LOS_RESULT = "Blocked"')
        self.seconds(4)
        self.assertEqual(lua_list(self.ev('NOISES')), [])              # aucun zombie ne le voit

    def test_target_for_a_combatant_is_the_nearest_visible_vanilla_zombie(self):
        self.ready('A')
        self.vanilla(7201, 4, 0)
        self.vanilla(7202, 2, 0)
        self.vanilla(7203, 1, 1)
        self.h.eval('server', '(function() HARNESS.zombies[7203].fakeDead = true return true end)()')
        t = self.ev('LivingKnox.Combat.targetFor("g", "lk-1", nil, {})')
        self.assertEqual((t.kind, t.u, round(t.d, 3)), ('zombie', 'z:7202', 2.0))
        self.assertIs(self.ev('rawequal(LivingKnox.Combat.targetFor("g", "lk-1", nil, {}).zombie, '
                              'HARNESS.zombies[7202])'), True)
        self.h.move_zombie(7202, 120, 120)
        self.h.move_zombie(7201, *self.body_xy())
        self.h.move_zombie(7201, self.body_xy()[0] + 11, self.body_xy()[1])   # au-delà de DEFEND_RANGE (10)
        self.assertIsNone(self.ev('LivingKnox.Combat.targetFor("g", "lk-1", nil, {})'))
        # Un autre corps de PNJ n'est jamais une cible.
        self.assertIsNone(self.ev(f'{Z}.targetFor("lk-1")'))
        self.assertIs(self.ev(f'({Z}.isVanilla(HARNESS.zombies[{self.npc_zid}]))'), False)
        # Cascade : la cible zombie donne « fight » au combattant, raison écrite.
        st = self.ev('LivingKnox.Decisions.decide({ id = "lk-1", allowed = { guard = true, defend = true }, combatant = true, '
                     'x = 0, y = 0, z = 0, minute = 0, target = { kind = "zombie", u = "z:7", d = 2 } })')
        self.assertEqual((st.b, st.key), ('fight', 'z:7'))
        self.assertIn('fight zombie z:7 at 2.0', st.why)

    def test_clients_never_decide(self):
        self.ready('A')
        self.assertIsNone(self.h.eval('A', f'{Z}.pass'))
        self.assertIsNotNone(self.h.eval('A', f'{Z}.CMD_HURT'))

    def test_engage_distance_read_from_the_sandbox_option(self):
        # LK05-T14 / LK06-T14 : option du rôle (PNJ hors groupe : ZombieEngageFighter ; repli DEFEND_RANGE = 10),
        # jamais au-delà de ZombieAlertDistance.
        self.ready('A')
        self.vanilla(7201, 11, 0)
        self.assertIsNone(self.ev(f'{Z}.targetFor("lk-1")'))
        self.h.load('server', 'LK_OPTS = { ["LivingKnox.ZombieEngageFighter"] = 12 } local prev = getSandboxOptions '
                              'getSandboxOptions = function() return { getOptionByName = function(_, n) '
                              'local v = LK_OPTS[n] if v ~= nil then return { getValue = function() return v end } end '
                              'local p = prev and prev() return p and p:getOptionByName(n) end } end')
        self.assertEqual(self.ev(f'{Z}.targetFor("lk-1").u'), 'z:7201')
        self.h.load('server', 'LK_OPTS["LivingKnox.ZombieAlertDistance"] = 5')
        self.assertEqual(self.ev(f'{Z}.engageRange()'), 5)
        self.assertIsNone(self.ev(f'{Z}.targetFor("lk-1")'))


class SoloZombieTests(ZombieBase):
    mode = 'solo'

    def ready(self):
        self.npc_zid = self.npc()
        return self.npc_zid

    def test_solo_kill_without_messages_and_serial_keys(self):
        self.ready()
        self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")')
        zid = self.vanilla(8001, 1.0, 0)
        self.run_lua(f'HARNESS.zombies[{zid}].onlineID = -1')        # solo : identifiant réseau -1
        self.assertEqual(self.z(f'keyOf(HARNESS.zombies[{zid}])'), 'z@100001')
        self.assertEqual(self.c(f'engage("lk-1", HARNESS.zombies[{zid}])'), 1)
        for _ in range(30):
            self.seconds(0.5)
            if self.h.zombie('solo', zid).killDone:
                break
        self.assertTrue(self.h.zombie('solo', zid).killDone)
        self.assertEqual(self.zstat('kills'), 1)
        self.assertEqual(lua_list(self.ev('ZOMBIE_DEATHS')), [-1])
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.zstat('hurtMessages'), 0)

    def test_solo_zombie_kills_the_npc(self):
        self.ready()
        self.vanilla(8101, 0.8, 0)
        for _ in range(120):
            self.seconds(1)
            if self.ev('LivingKnox.Health.stats.deaths') > 0:
                break
        self.assertEqual(self.ev('LivingKnox.Health.stats.deaths'), 1)
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].state'), 'dead')

    def run_suite(self):
        self.init()
        self.h.load('solo', 'shared/RST/suites/RST_LKZombies.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.zombies", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.zombies')
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.zombies", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(12000):
            self.h.tick()
            self.h.load('solo', 'for id in pairs(HARNESS.zombies) do STEP(id, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertTrue(report.ok, (results, self.h.logs('solo')[-40:]))
        return results

    def test_suite_lk_zombies_passes_on_the_doubles(self):
        self.run_lua('''
            local n = 9000
            addZombiesInOutfit = function(x, y, z, count, outfit, female)
                n = n + 1
                local zb = HARNESS.spawnZombie(n, x + 0.5, y + 0.5, z, "server")
                zb.health = 2
                return HARNESS.list({ zb })
            end
            local Zc = HARNESS.classes.IsoZombie
            if Zc.removeFromSquare == nil then function Zc:removeFromSquare() end end
        ''')
        results = self.run_suite()
        self.assertEqual(len(results), 1, results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKZ] measure')]
        self.assertTrue(any('zombies killed' in line for line in measures), measures)


class SourceTests(unittest.TestCase):
    def test_sources_are_kahlua_compatible(self):
        for path in MOD_FILES + [SUITE]:
            text = path.read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in text.splitlines())
            for bad in ('goto ', 'coroutine.', ' next(', 'string.format("%q'):
                self.assertNotIn(bad, code, f'{path.name}: {bad}')
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non-ASCII outside comments')


if __name__ == '__main__':
    unittest.main()
