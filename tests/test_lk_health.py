"""Tests hors jeu de la santé de référence Living Knox (LK07-T02) : LK_Health.lua (autorité), LK_HealthClient.lua.

    python RadioSurvivor/tests/test_lk_health.py

Banc tests/harness.py (serveur dédié et deux clients, ou solo), pile de test_lk_reports.py (corps, garde, consignes,
rapports) complétée des doublures ci-dessous, qui reproduisent le Java 42.21.0 relevé et NE PROUVENT PAS l'API réelle :
- setInvulnerable / isInvulnerable (drapeau GOD_MODE local, IsoGameCharacter.java:11069-11075) : setHealth(0) ignoré
  (IsoGameCharacter.java:2903-2908), aucun dégât vanilla (CombatManager.java:1097-1110), feu éteint (6036-6039) ;
  Kill : santé à 0 sauf invulnérable, onKilled une seule fois -> OnZombieDead (IsoGameCharacter.java:13463-13474) ;
- Hit (IsoZombie.java:1098-1125 -> IsoGameCharacter.java:5704-5743) : coups répétés comptés (mêlée), poussée sans
  visée au sol = sans dégâts, OnHitZombie puis OnWeaponHitCharacter(attaquant, cible, arme, dégâts) AVANT les dégâts,
  dégâts x 0,15 en mêlée (CombatManager.java:3237-3242) ; coup reçu du réseau par le serveur : PLAYER_HIT ;
- arme : getMaxDamage, getMaxRange, isMelee, getCriticalDamageMultiplier (HandWeapon.java:787, 812, 2335, 1837) ;
  joueur : isDoShove, isAimAtFloor, isCriticalHit, getWeaponLevel, getInventory():contains(objet, true).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_reports import ReportBase  # noqa: E402

HEALTH = 'server/LivingKnox/LK_Health.lua'
HEALTH_CLIENT = 'client/LivingKnox/LK_HealthClient.lua'
MOD_FILES = [LUA / HEALTH, LUA / HEALTH_CLIENT]
DEV_FILES = [DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKHealth.lua',
             DEV_LUA / 'shared' / 'RST' / 'suites' / 'RS_Killer.lua']

HEALTH_DOUBLES = r'''
local H = HARNESS
local MODE = H.mode
local C = H.classes
local Z = C.IsoZombie
local P = C.IsoPlayer
local function bool(v, what)
    if type(v) ~= 'boolean' then error('No implementation found for ' .. what .. ' with argument ' .. tostring(v), 3) end
    return v
end
function Z:isInvulnerable() return self.invulnerable == true end
function Z:setInvulnerable(b) self.invulnerable = bool(b, 'setInvulnerable') end
function Z:setHealth(h)
    H.num(h, 'setHealth')
    if h == 0 and self.invulnerable then return end
    self.health = h
end
function Z:getHitTime() return self.hitTime or 0 end
function Z:isFakeDead() return self.fakeDead == true end
function Z:setFakeDead(b) self.fakeDead = bool(b, 'setFakeDead') end
DEATHS = 0
function Z:Kill(a, b)
    local killer = a
    if instanceof(a, 'HandWeapon') then killer = b end
    self.attackedBy = killer
    if not self.invulnerable then self.health = 0 end
    if not self.killDone then
        self.killDone = true
        DEATHS = DEATHS + 1
        H.trigger('OnZombieDead', self)
    end
end
function Z:die() if not self.killDone then self:Kill(self.attackedBy) end end
function Z:Hit(weapon, wielder, damage, ignoreDamage, modDelta, remote)
    H.num(damage, 'Hit'); H.num(modDelta, 'Hit')
    if wielder == nil or weapon == nil then return 0 end
    if weapon:isMelee() and not ignoreDamage then self.hitTime = (self.hitTime or 0) + 1 end
    if instanceof(wielder, 'IsoPlayer') and wielder.doShove and not wielder.aimFloor then ignoreDamage = true end
    H.trigger('OnHitZombie', self, wielder, 'Torso_Upper', weapon)
    H.trigger('OnWeaponHitCharacter', wielder, self, weapon, damage)
    if self:isDead() then return 0 end
    self.attackedBy = wielder
    if not ignoreDamage and not self.invulnerable then
        self.health = self:getHealth() - damage * (weapon:isMelee() and 0.15 or 1)
    end
    if self:isDead() and not self.killDone then
        if MODE == 'server' then self:die() elseif MODE == 'solo' then self:Kill(weapon, wielder) end
    end
    return damage
end
-- Brûlure : un corps invulnérable est éteint aussitôt (IsoGameCharacter.java:6036-6039).
local rawUpdate = H.updateZombies
H.updateZombies = function()
    for _, zb in ipairs(H.zombieList.items) do if zb.invulnerable then zb.onFire = false end end
    rawUpdate()
end
-- Arme (valeurs relevées dans les scripts vanilla, arrondies).
local HW = C.HandWeapon
STATS = { ['Base.BaseballBat'] = { max = 1.5, range = 1.25, crit = 3 }, ['Base.Pistol'] = { max = 1.8, range = 15, crit = 4 },
    ['Base.PipeBomb'] = { max = 0, range = 0, crit = 0 }, ['Base.HuntingKnife'] = { max = 0.8, range = 0.9, crit = 5 } }
WEAPONS['Base.HuntingKnife'] = {}
function HW:isMelee() return not self.ranged and not self.explosive end
function HW:getMaxDamage() return STATS[self.fullType].max end
function HW:getMaxRange(owner) return STATS[self.fullType].range end
function HW:getCriticalDamageMultiplier() return STATS[self.fullType].crit end
-- Joueur.
function P:isDoShove() return self.doShove == true end
function P:isAimAtFloor() return self.aimFloor == true end
function P:setAimAtFloor(b) self.aimFloor = b end  -- IsoGameCharacter.java:11904
function P:isCriticalHit() return self.crit == true end
function P:getWeaponLevel() return self.weaponLevel or 0 end
local Inv = H.class('ItemContainer')
function Inv:contains(item, deep) for _, v in ipairs(self.items) do if v == item then return true end end return false end
function P:getInventory()
    local inv = rawget(self, 'inv')
    if not inv then inv = setmetatable({ items = {} }, Inv); self.inv = inv end
    return inv
end
-- Coup d'un joueur reçu par le serveur (PlayerHitZombie : Hit(..., bRemote = true), WeaponHit.java:79).
function PLAYER_HIT(name, zid, wtype, damage)
    local zb = H.zombies[zid]
    local w = instanceItem(wtype)
    LAST_WEAPON = w
    return zb:Hit(w, H.players[name], damage, false, 1.0, MODE == 'server')
end
'''


class HealthBase(ReportBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, HEALTH_DOUBLES)
            h.load(m, HEALTH)
            if m != 'server':
                h.load(m, HEALTH_CLIENT)
        return h

    def hl(self, code, m=None):
        return self.ev('LivingKnox.Health.' + code, m)

    def ref(self):
        return self.hl('reference("lk-1")')

    def hit(self, zid, damage, wtype='Base.BaseballBat', who='A', gap_ms=300):
        self.h.advance_ms(gap_ms)
        self.h.eval(self.srv, f'PLAYER_HIT("{who}", {zid}, "{wtype}", {damage})')
        return self.ref()

    def why(self, reason):
        return self.hl(f'stats.why["{reason}"] or 0')

    def npc_field(self, field):
        return self.ev(f'LivingKnox.Store.data().npcs["lk-1"].{field}')


class MultiplayerHealthTests(HealthBase):
    def ready(self, owner='A'):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)
        self.h.move_player('A', 101, 102, 0)   # à portée de batte du PNJ (102,5 ; 102,5)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def views(self):
        return {c: self.h.eval(c, 'LivingKnox.HealthView.get("lk-1") and LivingKnox.HealthView.get("lk-1").hp')
                for c in ('A', 'B')}

    def sync(self):
        self.h.advance_ms(self.ev('LivingKnox.Config.HEALTH.SEND_MS'))
        self.h.tick(1)
        self.h.pump()

    def test_every_copy_invulnerable_and_reference_initialized(self):
        zid = self.ready('A')
        for m in ('server', 'A', 'B'):
            self.assertIs(self.h.eval(m, f'HARNESS.zombies[{zid}]:isInvulnerable()'), True, m)
        self.assertEqual(self.ref(), 2)
        self.assertEqual(self.npc_field('hp'), 2)
        self.assertEqual(self.npc_field('hpMax'), 2)
        self.sync()
        self.assertEqual(self.views(), {'A': 2, 'B': 2})
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Health.judge'))   # client MP arrêté à la garde

    def test_player_hit_lowers_the_reference_seen_alike_by_two_clients(self):
        zid = self.ready('A')
        self.sync()
        hp = self.hit(zid, 3.0)
        self.assertAlmostEqual(hp, 2 - 3.0 * 0.15, places=3)
        self.assertEqual(self.h.eval('server', f'HARNESS.zombies[{zid}]:getHealth()'), 2)   # vanilla inerte
        self.assertEqual(self.npc_field('wounds[1].p'), 'Torso_Upper')
        self.sync()
        self.assertEqual(self.views(), {'A': hp, 'B': hp})
        msgs = [m for m in self.h.logs('server') if 'npcHealth' in m]
        self.assertEqual(msgs, [])
        # Rapports d'état du propriétaire : santé vanilla constante, jamais refusée.
        self.walk(zid, 80)
        self.h.pump()
        self.assertEqual(self.r('stats.why["health rose without a known heal"] or 0'), 0)
        # Pas de nouvel envoi sans changement.
        before = self.hl('stats.messages')
        self.sync()
        self.assertEqual(self.hl('stats.messages'), before)

    def test_forged_or_impossible_hits_are_refused(self):
        zid = self.ready('A')
        self.h.move_player('A', 120, 100, 0)
        self.assertEqual(self.hit(zid, 1.0), 2)
        self.assertEqual(self.why('out of reach'), 1)
        self.h.move_player('A', 101, 102, 3)
        self.assertEqual(self.hit(zid, 1.0), 2)
        self.assertEqual(self.why('other level'), 1)
        self.h.move_player('A', 101, 102, 0)
        self.run_lua('HARNESS.players.A.vehicle = {}')
        self.assertEqual(self.hit(zid, 1.0), 2)
        self.assertEqual(self.why('melee from a vehicle'), 1)
        self.run_lua('HARNESS.players.A.vehicle = nil; HARNESS.players.A.dead = true')
        self.assertEqual(self.hit(zid, 1.0), 2)
        self.assertEqual(self.why('attacker is dead'), 1)
        self.run_lua('HARNESS.players.A.dead = false')
        # Bombe encore dans l'inventaire du joueur : coup forgé.
        self.run_lua('local w = instanceItem("Base.PipeBomb"); HARNESS.players.A:getInventory().items = { w }; '
                     f'HARNESS.zombies[{zid}]:Hit(w, HARNESS.players.A, 5, false, 1.0, true)')
        self.assertEqual(self.why("explosive still in the attacker's inventory"), 1)
        self.assertEqual(self.ref(), 2)
        # Cadence : BURST coups d'avance, puis refus.
        results = [self.hit(zid, 0.1, gap_ms=0) for _ in range(8)]
        self.assertEqual(self.why('too many hits'), 8 - self.ev('LivingKnox.Config.HEALTH.BURST'))
        self.assertLess(results[-1], 2)
        warns = [line for line in self.lk() if 'hit on npc lk-1 by A refused' in line]
        self.assertTrue(any('WARN' in w and 'out of reach' in w for w in warns), warns)
        self.assertEqual(self.h.errors('server'), [])

    def test_coup_de_grace_above_the_weapon_maximum_kills_in_one_hit(self):
        # LK07-T06 (décision du 2026-10-11) : la valeur du client est crue, sans plafond tiré de l'arme.
        zid = self.ready('A')
        self.run_lua('LivingKnox.Store.data().npcs["lk-1"].hp = 30; LivingKnox.Store.data().npcs["lk-1"].hpMax = 30')
        self.assertIsNone(self.hl('cap'))
        # Hors de portée : même un coup énorme reste refusé.
        self.h.move_player('A', 120, 100, 0)
        self.assertEqual(self.hit(zid, 900, 'Base.HuntingKnife'), 30)
        self.assertEqual(self.why('out of reach'), 1)
        # À portée : coup de grâce au couteau (x 1000 chez l'attaquant), bien au-delà du maximum de l'arme (0,8).
        self.h.move_player('A', 101, 102, 0)
        self.run_lua('HARNESS.players.A.aimFloor = true')
        self.h.advance_ms(300)
        self.h.eval(self.srv, f'PLAYER_HIT("A", {zid}, "Base.HuntingKnife", 900)')
        self.assertTrue(self.h.eval('server', f'HARNESS.zombies[{zid}]:isDead()'))
        self.assertEqual(self.h.eval('server', 'DEATHS'), 1)
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.npc_field('hp'), 0)
        self.assertEqual(self.npc_field('wounds[1].d'), 30)          # blessure bornée par la santé restante
        self.assertEqual(self.npc_field('death.weapon'), 'Base.HuntingKnife')
        self.assertFalse(any('weapon cap' in line for line in self.lk()), self.lk())
        self.assertEqual(self.h.errors('server'), [])

    def test_invalid_damage_values_are_refused(self):
        zid = self.ready('A')
        for value in ('0/0', '1/0', '-1/0', '-0.5', '1e12', '"5"', 'nil', '{}'):
            self.h.advance_ms(300)
            res = self.ev(f'(function() local a, b = LivingKnox.Health.judge("lk-1", HARNESS.zombies[{zid}], '
                          f'HARNESS.players.A, instanceItem("Base.BaseballBat"), {value}); '
                          'return tostring(a) .. "|" .. tostring(b) end)()')
            self.assertEqual(res, 'nil|bad damage', value)
        self.assertEqual(self.why('bad damage'), 8)
        self.assertEqual(self.ref(), 2)
        # Valeur nulle : acceptée, sans dégâts.
        self.assertEqual(self.ev(f'LivingKnox.Health.judge("lk-1", HARNESS.zombies[{zid}], HARNESS.players.A, '
                                 'instanceItem("Base.BaseballBat"), 0)'), 0)

    def test_shove_does_no_damage(self):
        zid = self.ready('A')
        self.run_lua('HARNESS.players.A.doShove = true')
        self.assertEqual(self.hit(zid, 2.0), 2)
        self.assertEqual(self.hl('stats.shoves'), 1)

    def test_no_rise_without_a_heal_even_after_owner_changes(self):
        zid = self.ready('A')
        hp = self.hit(zid, 4.0)
        for owner in ('B', 'A', 'server', 'B'):
            self.h.set_owner(zid, owner)
            self.slow()
            self.h.pump()
            self.walk(zid, 30)
            self.assertEqual(self.ref(), hp, owner)
        self.assertAlmostEqual(self.hl('noteHeal("lk-1", 0.2)'), hp + 0.2, places=6)
        self.assertEqual(self.hl('noteHeal("lk-1", 50)'), 2)            # jamais au-delà de la santé de naissance
        self.assertIsNone(self.hl('noteHeal("lk-1", -1)'))
        self.assertEqual(self.hl('stats.heals'), 2)

    def test_single_death_decided_by_the_server(self):
        zid = self.ready('A')
        self.sync()
        hits = 0
        while not self.h.eval('server', f'HARNESS.zombies[{zid}]:isDead()') and hits < 20:
            self.hit(zid, 10.0)
            hits += 1
        self.assertLess(hits, 20)
        for _ in range(3):
            self.h.eval('server', f'PLAYER_HIT("A", {zid}, "Base.BaseballBat", 10.0)')   # corps mort : ignoré
        self.assertEqual(self.h.eval('server', 'DEATHS'), 1)
        self.assertEqual(self.hl('stats.deaths'), 1)
        self.assertEqual(self.hl('stats.engineDeaths'), 0)
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.npc_field('hp'), 0)
        self.assertEqual(self.npc_field('death.killer'), 'A')
        self.assertEqual(len([line for line in self.lk() if 'npc lk-1 died' in line]), 1)
        self.assertTrue(any('death decided by the authority' in line for line in self.lk()), self.lk())
        self.h.pump()
        self.assertEqual(self.views(), {'A': 0, 'B': 0})
        self.assertEqual(self.h.errors('server'), [])

    def test_engine_death_is_reported_and_completed_once(self):
        zid = self.ready('A')
        self.run_lua(f'local zb = HARNESS.zombies[{zid}]; zb:Kill(HARNESS.players.A)')
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.h.eval('server', f'HARNESS.zombies[{zid}]:getHealth()'), 0)
        self.assertIs(self.h.eval('server', f'HARNESS.zombies[{zid}]:isInvulnerable()'), False)
        self.assertEqual(self.hl('stats.engineDeaths'), 1)
        self.assertTrue(any('WARN npc lk-1 died without a decision of the authority' in line for line in self.lk()))

    def test_release_keeps_the_reference_and_rebinding_keeps_it(self):
        zid = self.ready('server')
        hp = self.hit(zid, 4.0)
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Bodies.release("lk-1", "test") }'))[0], True)
        self.assertEqual(self.npc_field('hp'), hp)
        self.assertEqual(self.npc_field('state'), 'virtual')
        body = self.ev('LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')
        self.assertIsNotNone(body)
        self.assertEqual(self.ref(), hp)                              # aucune remontée au retour
        self.assertIs(body.invulnerable, True)

    def test_reconnecting_client_gets_the_health_again(self):
        zid = self.ready('A')
        self.hit(zid, 3.0)
        self.sync()
        self.h.load('B', 'LivingKnox.HealthView.view = {}')
        self.sync()
        self.assertIsNone(self.views()['B'])
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'guardHello', self.h.player('server', 'B'), {'v': 1})
        self.sync()
        self.assertAlmostEqual(self.views()['B'], 2 - 0.45, places=3)


class SoloHealthTests(HealthBase):
    mode = 'solo'

    def test_solo_hit_estimate_and_death_once(self):
        zid = self.npc()
        self.assertIs(self.h.eval('solo', f'HARNESS.zombies[{zid}]:isInvulnerable()'), True)
        hp = self.hit(zid, 1.0, who='A')
        self.assertAlmostEqual(hp, 2 - 1.0 * 1.5 * 0.3 * 0.15, places=3)   # x NON_PLAYER x niveau 0, puis x 0,15
        self.run_lua('HARNESS.players.A.weaponLevel = 10')
        hp2 = self.hit(zid, 1.0)
        self.assertAlmostEqual(hp - hp2, 1.0 * 1.5 * 1.3 * 0.15, places=2)
        # Solo : ni portée ni cadence contrôlées (aucun client à soupçonner).
        self.h.move_player('A', 150, 150, 0)
        self.assertLess(self.hit(zid, 1.0, gap_ms=0), hp2)
        while not self.h.eval('solo', f'HARNESS.zombies[{zid}]:isDead()'):
            self.hit(zid, 100.0)
        self.assertEqual(self.h.eval('solo', 'DEATHS'), 1)
        self.assertEqual(self.hl('stats.deaths'), 1)
        self.assertEqual(self.npc_field('state'), 'dead')
        self.assertEqual(self.ev('LivingKnox.HealthView.get("lk-1").hp'), 0)

    def run_suite(self, name, count, setup=''):
        self.init()
        self.h.load('solo', f'shared/RST/suites/{"RST_LKHealth" if name == "lk.health" else "RS_Killer"}.lua')
        listed = self.h.eval('solo', f'RST.list({{ suite = "{name}", tags = "world" }}, true)[1]')
        self.assertEqual(listed.name, name)
        self.assertEqual(listed.count, count)
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)' + setup)
        self.assertIs(self.h.load('solo', f'return (RST.start({{ suite = "{name}", tags = "world" }}, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(6000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), count, results)
        self.assertTrue(report.ok, results)
        return results

    def test_suite_lk_health_passes_on_the_doubles(self):
        self.run_suite('lk.health', 3)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKH] measure')]
        self.assertTrue(any('deaths +1, engine deaths +0, listener calls 1' in line for line in measures), measures)

    def test_suite_rs_killer_passes_with_the_reference_health(self):
        self.run_suite('rs.killer', 5)
        measures = [line for line in self.h.logs('solo') if line.startswith('[RSK] measure')]
        self.assertTrue(any('fire with reference health: on fire false, npc embodied' in line for line in measures),
                        measures)


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

    def test_no_global_moddata_and_no_broadcast(self):
        code = (LUA / HEALTH).read_text(encoding='utf-8')
        self.assertNotIn('ModData.', code)
        # Envoi ciblé seulement (sendServerCommand(joueur, ...)), jamais à tous.
        for m in re.finditer(r'sendServerCommand\(([^,]+),', code):
            self.assertNotIn('Health.MODULE', m.group(1))


if __name__ == '__main__':
    unittest.main()
