"""Tests hors jeu de la mêlée (LK06-T02) et du tir (LK06-T03) des PNJ Living Knox : server/LivingKnox/LK_Combat.lua
(autorité), server/LivingKnox/LK_Ammo.lua (munitions), client/LivingKnox/LK_CombatClient.lua (machine qui simule le
corps, son et éclair des tirs), branchement dans LK_Decisions.lua. Doublures du tir : RANGED_DOUBLES.

    python RadioSurvivor/tests/test_lk_combat.py

Banc tests/harness.py (serveur dédié et deux clients, ou solo), pile des corps, consignes, rapports et armes (banc
ReleaseBase de test_lk_reports.py), complétée des doublures ci-dessous, qui reproduisent le Java 42.21.0 relevé et NE
PROUVENT PAS l'API réelle :
- HandWeapon:getMaxRange() (HandWeapon.java:808, MaxRange du script : BareHands 1,1, batte 1,25, couteau 0,9) ;
- IsoPlayer:getBodyDamage():DamageFromWeapon(arme, partie) (BodyDamage.java:1014) : appels comptés par joueur ;
- sendDamage(joueur) (LuaManager.java:3743-3748) : sans effet hors serveur, comptée sur le serveur.
Mesures : touches acceptées et dommages appliqués comptés côté serveur ; frappes minutées chez le propriétaire.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_reports import ReleaseBase  # noqa: E402
from test_lk_materialize import MatBase  # noqa: E402
from test_lk_decisions import DECIDERS  # noqa: E402

COMBAT = 'server/LivingKnox/LK_Combat.lua'
COMBAT_CLIENT = 'client/LivingKnox/LK_CombatClient.lua'
AMMO = 'server/LivingKnox/LK_Ammo.lua'
MOD_FILES = [LUA / COMBAT, LUA / COMBAT_CLIENT, LUA / AMMO]
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKMelee.lua'
RANGED_SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKRanged.lua'
C = 'LivingKnox.Combat'

COMBAT_DOUBLES = r'''
local H = HARNESS
local P = H.classes.IsoPlayer
local W = H.classes.HandWeapon
RANGES = { ['Base.BareHands'] = 1.1, ['Base.BaseballBat'] = 1.25, ['Base.KitchenKnife'] = 0.9, ['Base.HandAxe'] = 1.2,
    ['Base.Pistol'] = 15, ['Base.Shotgun'] = 20 }
ITEMS['Base.BareHands'] = { cls = W }
function W:getMaxRange() return RANGES[self.t] or 1 end
DAMAGES = {}
local BD = H.class('BodyDamage')
function BD:DamageFromWeapon(w, part)
    H.num(part, 'DamageFromWeapon')
    if not instanceof(w, 'HandWeapon') then error('No implementation found for DamageFromWeapon', 2) end
    local name = self.owner:getUsername()
    local list = DAMAGES[name]
    if list == nil then list = {}; DAMAGES[name] = list end
    list[#list + 1] = w:getFullType()
end
function P:getBodyDamage()
    local bd = rawget(self, 'bd')
    if not bd then bd = setmetatable({ owner = self }, BD); self.bd = bd end
    return bd
end
SENT_DAMAGE = {}
sendDamage = function(p)
    if not isServer() then return end
    SENT_DAMAGE[#SENT_DAMAGE + 1] = p:getUsername()
end
function BD:getHealth() return 100 end
function P:isGodMod() return self.god == true end
function P:setGodMod(b) if type(b) ~= 'boolean' then error('No implementation found for setGodMod', 2) end self.god = b end
function DAMAGE_COUNT(name) return #(DAMAGES[name] or {}) end
-- LK06-T11 : sons des armes de mêlée, valeurs des scripts vanilla (weapon.txt : SwingSound, HitSound lu par
-- getZombieHitSound, HitFloorSound ; champ absent = défaut de Item.java:133, 495-496 : BaseballBatSwing,
-- BaseballBatHit, BatOnFloor). Base.BareHands n'a pas de SwingSound. Base.TestNoFloor : arme de test sans
-- HitFloorSound ; Base.TestSilent : HitSound = null (Item.java:1968-1972).
MELEE_SCRIPTS = {
    ['Base.BareHands'] = { swing = 'BaseballBatSwing', hit = 'BareHandsHit', floor = 'BareHandsHit' },
    ['Base.BaseballBat'] = { swing = 'BaseballBatSwing', hit = 'BaseballBatHit', floor = 'BaseballBatHit' },
    ['Base.KitchenKnife'] = { swing = 'KitchenKnifeSwing', hit = 'KitchenKnifeHit', floor = 'KitchenKnifeHit' },
    ['Base.HandAxe'] = { swing = 'HandAxeSwing', hit = 'HandAxeHit', floor = 'HandAxeHit' },
    ['Base.TestNoFloor'] = { swing = 'TestNoFloorSwing', hit = 'TestNoFloorHit', floor = 'BatOnFloor' },
    ['Base.TestSilent'] = { swing = 'TestSilentSwing', hit = nil, floor = 'BatOnFloor' },
    -- LK06-T13 : constat en jeu (machette du PNJ, marteau du joueur), weapon.txt (MaxRange 1,23 et 1,1).
    ['Base.Machete'] = { swing = 'MacheteSwing', hit = 'MacheteHit', floor = 'MacheteHit' },
    ['Base.Hammer'] = { swing = 'HammerSwing', hit = 'HammerHit', floor = 'HammerHit' },
}
RANGES['Base.Machete'], RANGES['Base.Hammer'] = 1.23, 1.1
local function likeBat()   -- même emplacement d'accroche et prise que la batte (doublures de test_lk_equipment.py)
    local e = {}
    for k, v in pairs(ITEMS['Base.BaseballBat'] or {}) do e[k] = v end
    e.cls = W
    return e
end
ITEMS['Base.TestNoFloor'] = likeBat()
ITEMS['Base.TestSilent'] = likeBat()
ITEMS['Base.Machete'] = ITEMS['Base.Machete'] or likeBat()
ITEMS['Base.Hammer'] = ITEMS['Base.Hammer'] or likeBat()
local function melee(self)
    return MELEE_SCRIPTS[self.t] or error('not a melee weapon double: ' .. tostring(self.t), 3)
end
function W:getSwingSound()   -- arme à feu (RANGED_DOUBLES chargé avant ou après) : son du tir
    local f = rawget(_G, 'FIREARMS') and FIREARMS[self.t]
    if f then return f.sound end
    return melee(self).swing
end
function W:getZombieHitSound() return melee(self).hit end
function W:getHitFloorSound() return melee(self).floor end
-- Émetteur d'un corps (CharacterSoundEmitter, J/characters/CharacterSoundEmitter.java:190-201, 327-331) :
-- playSoundImpl(String, IsoObject) seule surcharge à deux arguments, stopSoundByName(String). Sons de mêlée relevés
-- dans MELEE_PLAYED (élan, impact), arrêts dans MELEE_STOPPED ; les autres (coups de feu) dans SHOT_SOUNDS.
MELEE_NAMES = { AttackShove = true, AttackStomp = true }
for _, m in pairs(MELEE_SCRIPTS) do
    MELEE_NAMES[m.swing] = true
    if m.hit then MELEE_NAMES[m.hit] = true end
    MELEE_NAMES[m.floor] = true
end
SHOT_SOUNDS, MELEE_PLAYED, MELEE_STOPPED = {}, {}, {}
BODY_EMITTER = {}
BODY_EMITTER.__index = BODY_EMITTER
function BODY_EMITTER:playSoundImpl(...)
    local n = select('#', ...)
    local name, obj = ...
    if n ~= 2 or type(name) ~= 'string' then error('No implementation found for playSoundImpl', 2) end
    if obj ~= nil and type(obj) ~= 'table' then error('playSoundImpl: IsoObject expected', 2) end
    if MELEE_NAMES[name] then
        MELEE_PLAYED[#MELEE_PLAYED + 1] = { via = 'body', name = name, zid = self.zid }
    else
        SHOT_SOUNDS[#SHOT_SOUNDS + 1] = { via = 'body', name = name }
    end
    return 7
end
function BODY_EMITTER:stopSoundByName(...)
    local n = select('#', ...)
    local name = ...
    if n ~= 1 or type(name) ~= 'string' then error('No implementation found for stopSoundByName', 2) end
    MELEE_STOPPED[#MELEE_STOPPED + 1] = name
    local playing = rawget(self, 'playing')
    if playing then playing[name] = nil end
    return 0
end
-- LK06-T13 : lecture en cours (FMODSoundEmitter.isPlaying(String), J/fmod/fmod/FMODSoundEmitter.java:603-614). Le
-- moteur ne fait plus avancer l'émetteur d'un zombie mort (IsoDeadBody.java:358-361) : la doublure ne termine donc
-- jamais un son d'elle-même ; seul stopSoundByName l'arrête (pire cas, celui d'un son qui boucle).
function BODY_EMITTER:isPlaying(...)
    local n = select('#', ...)
    local name = ...
    if n ~= 1 or (type(name) ~= 'string' and type(name) ~= 'number') then
        error('No implementation found for isPlaying', 2)
    end
    local playing = rawget(self, 'playing')
    return playing ~= nil and playing[name] == true
end
local basePlay = BODY_EMITTER.playSoundImpl
function BODY_EMITTER:playSoundImpl(...)
    local r = basePlay(self, ...)
    local name = ...
    local playing = rawget(self, 'playing')
    if playing == nil then playing = {}; self.playing = playing end
    playing[name] = true
    return r
end
function H.classes.IsoZombie:getEmitter()
    local e = rawget(self, 'shotEmitter')
    if e == nil then e = setmetatable({ zid = rawget(self, 'onlineID') }, BODY_EMITTER); self.shotEmitter = e end
    return e
end
function MELEE_NAMES_PLAYED()
    local out = {}
    for _, e in ipairs(MELEE_PLAYED) do out[#out + 1] = e.via .. ':' .. e.name end
    return out
end
'''


# ======================================================================== tir (LK06-T03)

# Doublures du tir, fidèles au Java 42.21.0 relevé (NE PROUVENT PAS l'API réelle) :
# - HandWeapon : getAmmoType():getItemKey() (AmmoType.java:47-49), getMagazineType (nil pour un fusil à pompe),
#   getMaxAmmo, getAmmoPerShoot, getSoundRadius, getSoundVolume, getSwingSound, getHitChance,
#   getAimingPerkHitChanceModifier, getMinSightRange, getMaxSightRange (scripts weapon.txt : Pistol, Shotgun) ;
# - objets de munitions : cartouche (un objet par cartouche), chargeur (getCurrentAmmoCount, setCurrentAmmoCount) ;
# - inventaire d'un zombie (ItemContainer : getItems, AddItem, DoRemoveItem) ;
# - LosUtil.lineClear (résultat nommé, LosUtil.java:648-653 ; LOS_RESULT imposé par le test, entiers exigés) ;
# - addSound (entiers exigés, LuaManager.java:9239), getSandboxOptions():getOptionByName(...):getValue(),
#   IsoGridSquare:isOutside ;
# - clients : CharacterSoundEmitter.playSoundImpl(String, IsoObject), émetteur libre playSoundImpl(String, boolean,
#   IsoObject), IsoLightSource.new(x, y, z, r, g, b, rayon, vie) (entiers pour x, y, z, rayon, vie),
#   IsoCell:addLamppost, GameTime:getNight.
RANGED_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Item = C.InventoryItem
local W = C.HandWeapon
FIREARMS = {
    ['Base.Pistol'] = { round = 'Base.Bullets9mm', mag = 'Base.9mmClip', max = 15, per = 1, radius = 100, volume = 30,
        sound = 'M9Shoot', hit = 50, aimMod = 4, minS = 2, maxS = 6 },
    ['Base.Shotgun'] = { round = 'Base.ShotgunShells', max = 5, per = 1, radius = 200, volume = 200,
        sound = 'JS2000ShotgunShoot', hit = 65, aimMod = 4, minS = 3, maxS = 8 },
}
RANGES['Base.Shotgun'] = 12
ITEMS['Base.Bullets9mm'] = { cls = Item }
ITEMS['Base.ShotgunShells'] = { cls = Item }
ITEMS['Base.9mmClip'] = { cls = Item }
local AT = H.class('AmmoType')
function AT:getItemKey() return self.key end
local function gun(self) return FIREARMS[self.t] or error('not a firearm double: ' .. tostring(self.t), 3) end
function W:getAmmoType() local f = FIREARMS[self.t] return f and setmetatable({ key = f.round }, AT) or nil end
function W:getMagazineType() return gun(self).mag end
function W:getMaxAmmo() return gun(self).max end
function W:getAmmoPerShoot() return gun(self).per end
function W:getSoundRadius() return gun(self).radius end
function W:getSoundVolume() return gun(self).volume end
local meleeSwing = W.getSwingSound   -- LK06-T11 : armes de mêlée (COMBAT_DOUBLES)
function W:getSwingSound()
    if FIREARMS[self.t] then return FIREARMS[self.t].sound end
    return meleeSwing(self)
end
function W:getHitChance() return gun(self).hit end
function W:getAimingPerkHitChanceModifier() return gun(self).aimMod end
function W:getMinSightRange() return gun(self).minS end
function W:getMaxSightRange() return gun(self).maxS end
function Item:getCurrentAmmoCount() return rawget(self, 'ammo') or 0 end
function Item:setCurrentAmmoCount(n) H.num(n, 'setCurrentAmmoCount') self.ammo = math.floor(n) end
ITEM_COUNT = 0
local baseInstance = instanceItem
instanceItem = function(t)
    local it = baseInstance(t)
    if it ~= nil then ITEM_COUNT = ITEM_COUNT + 1 end
    return it
end
local Inv = C.ItemContainer or H.class('ItemContainer')
if Inv.getItems == nil then
    function Inv:getItems() return self.items end
    function Inv:AddItem(it)
        if it.container ~= nil then it.container:DoRemoveItem(it) end
        it.container = self
        self.items:add(it)
        return it
    end
    function Inv:DoRemoveItem(it) H.listRemove(self.items, it); it.container = nil end
end
local Z = C.IsoZombie
if Z.getInventory == nil then
    function Z:getInventory()
        local inv = rawget(self, 'inv')
        if inv == nil then inv = setmetatable({ items = H.list() }, Inv); self.inv = inv end
        return inv
    end
end
function COUNT_ITEMS(zb, t)
    local n, rounds = 0, 0
    for _, it in ipairs(zb:getInventory():getItems().items) do
        if it:getFullType() == t then n = n + 1; rounds = rounds + it:getCurrentAmmoCount() end
    end
    return n, rounds
end
LOS_RESULT = 'Clear'
LOS_CALLS = 0
LosUtil = { lineClear = function(cell, x0, y0, z0, x1, y1, z1, ignoreDoors)
    for _, v in ipairs({ x0, y0, z0, x1, y1, z1 }) do
        H.num(v, 'LosUtil.lineClear')
        if v ~= math.floor(v) then error('LosUtil.lineClear: int expected, got ' .. v, 2) end
    end
    if type(ignoreDoors) ~= 'boolean' then error('No implementation found for LosUtil.lineClear', 2) end
    LOS_CALLS = LOS_CALLS + 1
    return setmetatable({}, { __tostring = function() return LOS_RESULT end })
end }
NOISES = {}
addSound = function(src, x, y, z, r, v)
    for _, n in ipairs({ x, y, z, r, v }) do
        H.num(n, 'addSound')
        if n ~= math.floor(n) then error('addSound: int expected, got ' .. tostring(n), 2) end
    end
    NOISES[#NOISES + 1] = { x = x, y = y, z = z, r = r, v = v }
end
NOISE_MULT = 1
getSandboxOptions = function()
    return { getOptionByName = function(self, name)
        if name ~= 'FirearmNoiseMultiplier' then return nil end
        return { getValue = function() return NOISE_MULT end }
    end }
end
INSIDE = false
function C.IsoGridSquare:isOutside() return not INSIDE end
-- Clients et solo : son et éclair joués (émetteur du corps : BODY_EMITTER de COMBAT_DOUBLES).
SHOT_SOUNDS, LIGHTS = {}, {}
local Free = {}
Free.__index = Free
function Free:playSoundImpl(...)
    local n = select('#', ...)
    local name, a = ...
    if n ~= 3 or type(name) ~= 'string' or type(a) ~= 'boolean' then
        error('No implementation found for playSoundImpl', 2)
    end
    local list = MELEE_NAMES[name] and MELEE_PLAYED or SHOT_SOUNDS
    list[#list + 1] = { via = 'free', name = name, x = self.x, y = self.y, z = self.z }
    return 8
end
local prevWorld = getWorld
getWorld = function()
    local w = prevWorld ~= nil and prevWorld() or {}
    w.getFreeEmitter = function(self, x, y, z) return setmetatable({ x = x, y = y, z = z }, Free) end
    return w
end
local LS = H.class('IsoLightSource')
IsoLightSource = { new = function(x, y, z, r, g, b, radius, life)
    for _, v in ipairs({ x, y, z, radius, life }) do
        H.num(v, 'IsoLightSource.new')
        if v ~= math.floor(v) then error('IsoLightSource.new: int expected, got ' .. tostring(v), 2) end
    end
    for _, v in ipairs({ r, g, b }) do H.num(v, 'IsoLightSource.new') end
    return setmetatable({ x = x, y = y, z = z, r = r, g = g, b = b, radius = radius, life = life }, LS)
end }
local cellClass = getmetatable(getCell())
cellClass.addLamppost = function(self, light)
    if not instanceof(light, 'IsoLightSource') then error('No implementation found for addLamppost', 2) end
    LIGHTS[#LIGHTS + 1] = light
end
NIGHT = 0
getmetatable(getGameTime()).getNight = function() return NIGHT end
'''


class CombatBase(ReleaseBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, COMBAT_DOUBLES)
            h.load(m, RANGED_DOUBLES)
            h.load(m, COMBAT)
            if m != 'server':
                h.load(m, COMBAT_CLIENT)
        return h

    def c(self, code, m=None):
        return self.ev(f'{C}.' + code, m)

    def why(self, reason):
        return self.c(f'stats.why["{reason}"] or 0')

    def damages(self, name='A'):
        return self.ev(f'DAMAGE_COUNT("{name}")')

    def steps(self, ticks, until=None):
        """ticks images : marche de la copie qui simule, position recopiée, réseau livré."""
        for _ in range(ticks):
            self.walk(self.npc_zid, 1)
            if until and until():
                return True
        return False


class MultiplayerCombatTests(CombatBase):
    def ready(self, owner='A', player_at=(106.5, 102.5)):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for cl in ('A', 'B'):
            self.h.eval(cl, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)
        self.h.move_player('A', *player_at)
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.npc_zid = zid
        return zid

    def forge(self, sender='A', gap_ms=0, **kw):
        """Touche envoyée au serveur au nom de sender (ordre courant, cible A). Rend vrai si appliquée."""
        self.h.advance_ms(gap_ms)
        self.n = getattr(self, 'n', 100) + 1
        args = {'id': 'lk-1', 'c': self.c('orders["lk-1"].c'), 'n': self.n, 'u': 'A', 'x': 0, 'y': 0, 'z': 0}
        args.update(kw)
        before = self.c('stats.applied')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'combatHit', self.h.player('server', sender), args)
        return self.c('stats.applied') == before + 1

    def engaged_in_reach(self):
        """PNJ engagé contre A, déjà à portée : phase de frappe, geste reçu par le propriétaire."""
        zid = self.ready('A', player_at=(103.5, 102.5))
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        self.assertEqual(self.c('orders["lk-1"].phase'), 'strike')
        self.relayed()
        self.h.load('A', 'LivingKnox.CombatView.tick = function() end')   # touches forgées seules (aucun minutage)
        return zid

    def test_approach_then_strikes_reported_by_the_owner_and_applied_once_each(self):
        zid = self.ready('A')
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        # Hors de portée : course vers la case du joueur.
        e = self.ev('LivingKnox.Directives.get("lk-1")')
        self.assertEqual((e.op, e.x, e.y, e.g), ('move', 106, 102, 'run'))
        self.assertEqual(self.c('orders["lk-1"].phase'), 'approach')
        self.assertAlmostEqual(self.c('orders["lk-1"].reach'), 1.1 + 0.5)
        self.assertIs(self.c('orders["lk-1"].bare'), True)
        self.h.pump()
        # Le corps arrive à portée : regard vers le joueur, geste de frappe chez les deux clients.
        self.assertTrue(self.steps(400, until=lambda: self.c('orders["lk-1"].phase') == 'strike'))
        self.relayed()
        for cl in ('A', 'B'):
            self.assertEqual(self.h.eval(cl, 'LivingKnox.Anim.gestureOf("lk-1")'), 'strike')
            self.assertEqual(self.h.eval(cl, 'LivingKnox.CombatView.remote.d["lk-1"].u'), 'A')
        self.assertEqual(self.ev('LivingKnox.Directives.get("lk-1").op'), 'face')
        # Six secondes de frappes : une touche par boucle du clip, rapportée par le seul propriétaire.
        start = self.h.real_ms
        sent = []
        for _ in range(int(6000 / self.h.tick_ms)):
            self.h.tick(1)
            sent += [m for m in self.h.pending() if m['command'] == 'combatHit']
            self.h.pump()
        seconds = (self.h.real_ms - start) / 1000
        self.assertEqual({m['from'] for m in sent}, {'A'})
        applied = self.c('stats.applied')
        strike_ms = self.ev('LivingKnox.Config.COMBAT.STRIKE_MS')
        self.assertGreaterEqual(applied, int(seconds * 1000 / strike_ms) - 1)
        self.assertLessEqual(applied, int(seconds * 1000 / strike_ms) + 1)
        self.assertEqual(len(sent), applied)
        self.assertEqual(self.damages('A'), applied)                     # dommages une fois par touche
        self.assertEqual(lua_list(self.ev('SENT_DAMAGE')), ['A'] * applied)
        self.assertEqual(self.damages('B'), 0)
        self.assertEqual(self.c('stats.refused'), 0)
        self.assertEqual(self.ev('DAMAGES.A[1]'), 'Base.BareHands')
        hits = [line for line in self.lk() if 'npc lk-1 hit A with bare hands' in line]
        self.assertEqual(len(hits), applied)
        # Joueur hors de portée : plus aucune touche rapportée ni appliquée ; le PNJ repart vers lui.
        self.h.move_player('A', 112.5, 102.5)
        before = self.c('stats.applied')
        reported = self.h.eval('A', 'LivingKnox.CombatView.stats.reported')
        for _ in range(60):
            self.h.tick(1)
            self.h.pump()
        self.assertEqual(self.c('stats.applied'), before)
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.stats.reported'), reported)
        self.assertEqual(self.c('orders["lk-1"].phase'), 'approach')
        self.assertEqual(self.ev('LivingKnox.Directives.get("lk-1").x'), 112)
        self.assertEqual(self.h.errors('server'), [])

    def test_no_hit_out_of_reach_is_accepted(self):
        self.engaged_in_reach()
        self.assertTrue(self.forge())
        # Joueur éloigné sur les copies du serveur : refus, même si le propriétaire prétend le contraire.
        self.h.move_player('A', 110.5, 102.5)
        self.assertFalse(self.forge(gap_ms=2000))
        self.assertEqual(self.why('out of reach'), 1)
        # Autre niveau.
        self.h.move_player('A', 103.5, 102.5, 1)
        self.assertFalse(self.forge(gap_ms=2000))
        self.assertGreaterEqual(self.why('other level') + self.why('not striking'), 1)
        self.assertEqual(self.damages('A'), 1)
        warns = [line for line in self.lk() if 'melee hit of npc lk-1 reported by A refused: out of reach' in line]
        self.assertTrue(warns and 'WARN' in warns[0], warns)

    def test_each_hit_applied_once_and_cadence_enforced(self):
        self.engaged_in_reach()
        self.assertTrue(self.forge(n=1))
        self.assertFalse(self.forge(n=1))                                # même rapport livré deux fois
        self.assertEqual(self.c('stats.duplicates'), 1)
        self.assertFalse(self.forge(n=2, gap_ms=100))                    # plus vite que la boucle du clip
        self.assertEqual(self.why('too fast'), 1)
        self.assertFalse(self.forge(n=2, gap_ms=1300))                   # rapport refusé : jamais rejoué
        self.assertTrue(self.forge(n=3))
        self.assertFalse(self.forge(n=2, gap_ms=1300))                   # plus ancien que le dernier : ignoré
        self.assertEqual(self.damages('A'), 2)
        self.assertEqual(lua_list(self.ev('SENT_DAMAGE')), ['A', 'A'])
        self.assertEqual(self.c('orders["lk-1"].hits'), 2)

    def test_only_the_owner_reports_and_a_previous_owner_is_ignored(self):
        self.engaged_in_reach()
        self.assertFalse(self.forge('B', gap_ms=2000))
        self.assertEqual(self.why('not the owner'), 1)
        self.h.set_owner(self.npc_zid, 'B')
        self.h.tick(1)                                                   # remise : changement vu par le serveur
        self.h.pump()
        self.assertFalse(self.forge('A', gap_ms=2000))
        self.assertEqual(self.why('previous owner'), 1)
        self.assertTrue(self.forge('B', gap_ms=2000))
        self.assertEqual(self.damages('A'), 1)

    def test_stale_order_wrong_target_and_dead_target(self):
        self.engaged_in_reach()
        self.assertFalse(self.forge(c=0))
        self.assertEqual(self.c('stats.stale'), 1)
        self.assertFalse(self.forge(u='B', gap_ms=2000))
        self.assertEqual(self.why('wrong target'), 1)
        self.h.kill_player('A')
        self.assertFalse(self.forge(gap_ms=2000))
        self.assertEqual(self.why('target dead'), 1)
        self.h.advance_ms(300)
        self.h.tick(1)                                                   # passage : fin de l'engagement
        self.assertIsNone(self.c('get("lk-1")'))
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')
        self.h.pump()
        for cl in ('A', 'B'):
            self.assertIsNone(self.h.eval(cl, 'LivingKnox.CombatView.remote.d["lk-1"]'))
        self.assertEqual(self.damages('A'), 0)
        self.assertTrue(any('melee #1 against A ended after 0 hit(s): target dead' in line for line in self.lk()))

    def test_order_sent_to_near_clients_only_and_again_after_a_reconnection(self):
        self.ready('A', player_at=(103.5, 102.5))
        self.h.move_player('B', 400, 400)
        self.c('engage("lk-1", "A")')
        self.h.advance_ms(300)
        self.h.tick(1)
        msgs = [m for m in self.h.pending() if m['command'] == 'combatState']
        self.assertEqual([m['to'] for m in msgs], ['A'])
        self.assertEqual(sorted(msgs[0]['args']['d']['lk-1']), ['c', 'im', 'iv', 'k', 'm', 'r', 'rc', 'sw', 'u'])
        self.h.pump()
        self.h.advance_ms(300)
        self.h.tick(1)
        self.assertEqual([m for m in self.h.pending() if m['command'] == 'combatState'], [])   # rien sans changement
        self.h.load('A', 'LivingKnox.CombatView.reset()')
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'guardHello', self.h.player('server', 'A'), {'v': 1})
        self.h.advance_ms(300)
        self.h.tick(1)
        self.h.pump()
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.remote.d["lk-1"].c'), 1)
        # Envoi plus ancien livré en retard : ignoré.
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'combatState', {'d': {'lk-1': {'r': 0, 'gone': True}}})
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.stats.older'), 1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.remote.d["lk-1"].c'), 1)

    def test_firearm_holder_strikes_bare_handed_and_a_bat_gives_its_reach(self):
        self.ready('A', player_at=(103.5, 102.5))
        self.assertIs(self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun")'), True)
        self.c('engage("lk-1", "A")')
        self.assertEqual(self.c('get("lk-1").t'), 'Base.BareHands')
        self.c('disengage("lk-1", "test")')
        self.assertIs(self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")'), True)
        self.assertEqual(self.c('engage("lk-1", "A")'), 2)
        self.assertEqual(self.c('get("lk-1").t'), 'Base.BaseballBat')
        self.assertAlmostEqual(self.c('get("lk-1").reach'), 1.25 + 0.5)

    def test_clients_never_decide(self):
        self.ready('A')
        self.assertIsNone(self.h.eval('A', f'{C}.engage'))   # client MP arrêté à la garde
        self.assertIsNotNone(self.h.eval('A', f'{C}.CMD_HIT'))


class SoloCombatTests(CombatBase):
    mode = 'solo'

    def test_solo_strikes_without_messages(self):
        zid = self.npc()
        self.npc_zid = zid
        self.h.move_player('A', 103.5, 102.5)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        self.assertEqual(self.c('orders["lk-1"].phase'), 'strike')
        for _ in range(int(4000 / self.h.tick_ms)):
            self.h.tick(1)
        applied = self.c('stats.applied')
        self.assertGreaterEqual(applied, 2)
        self.assertEqual(self.damages('A'), applied)
        self.assertEqual(lua_list(self.ev('SENT_DAMAGE')), [])         # sendDamage sans effet hors serveur
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.c('stats.refused'), 0)

    def run_suite(self):
        self.init()
        # LK06-T13 : mort décidée par l'autorité (LK_Health), drapeaux relevés dans test_lk_health.py (HEALTH_DOUBLES).
        self.h.load('solo', 'local Z = HARNESS.classes.IsoZombie '
                            'function Z:isInvulnerable() return self.invulnerable == true end '
                            'function Z:setInvulnerable(b) assert(type(b) == "boolean") self.invulnerable = b end '
                            'function Z:isFakeDead() return self.fakeDead == true end '
                            'function Z:setFakeDead(b) assert(type(b) == "boolean") self.fakeDead = b end')
        self.h.load('solo', 'server/LivingKnox/LK_Health.lua')
        self.h.load('solo', 'shared/RST/suites/RST_LKMelee.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.melee", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.melee')
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.melee", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(8000):
            self.h.tick()
            self.h.load('solo', 'for id in pairs(HARNESS.zombies) do STEP(id, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertTrue(report.ok, results)
        return results

    def test_suite_lk_melee_passes_on_the_doubles(self):
        results = self.run_suite()
        self.assertEqual(len(results), 2, results)
        self.assertEqual([r[1] for r in results], ['PASS', 'PASS'], results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKM] measure')]
        self.assertTrue(any('hits applied' in line for line in measures), measures)
        death = [line for line in measures if 'death during a swing' in line]   # LK06-T13
        self.assertEqual(len(death), 1, measures)
        self.assertIn('stopped at the death 1', death[0])
        self.assertIn('swings played 0, impacts played 0', death[0])


# Groupe de test qui tire le premier (hostilité 90) : combattants (fight, defend) et ouvriers.
BRAWLERS = r'''
if not LivingKnox.GroupTypes.isKnown("brawlers") then
    assert(LivingKnox.GroupTypes.register({
        format = 1, id = "brawlers", nameKey = "IGUI_LK_GroupType_raiders", size = { min = 1, max = 12 },
        hostility = 90, home = "building", morale = 60, needs = { food = 50, medical = 50, ammo = 50 },
        roles = { fighter = { weight = 1, behaviours = { "guard", "defend", "fight" } },
                  worker = { weight = 1, behaviours = { "chores", "cook" } } },
        profiles = {
            { id = "thug", role = "fighter", weight = 1, weapons = { "Base.BaseballBat" }, looks = { "manFairBeard" } },
            { id = "cook", role = "worker", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
        },
    }))
end
function SEE_PLAYER(id, name, x, y, d)
    PERCEPTION[id] = { ms = 0, age = 0, stale = false, nz = 0, seen = 1, heard = 0, z = {}, n = {},
        p = { { u = name, x = x, y = y, z = 0, s = true, h = false, d = d } } }
end
'''


class DecisionCombatTests(MatBase):
    """Pile complète : groupe « brawlers » matérialisé, perception injectée, cascade de LK_Decisions."""

    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, COMBAT_DOUBLES)
            h.load(m, COMBAT)
            if m != 'server':
                h.load(m, COMBAT_CLIENT)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, DECIDERS)
        h.load(srv, BRAWLERS)
        return h

    def mk(self):
        code = ('local G = LivingKnox.Groups local g = assert(G.create({ type = "brawlers", name = "Gang", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) '
                'assert(G.addMember(g.id, { role = "fighter", profile = "thug", female = false, day = 1 })) '
                'assert(G.addMember(g.id, { role = "worker", profile = "cook", female = false, day = 1 })) '
                'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        gid = self.run_lua(code)
        self.run_lua('LivingKnox.Decisions.state.lastPass = 1e18')
        self.h.move_player('A', 100, 100)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == 2:
                break
        self.assertEqual(len(self.bodies(gid)), 2)
        self.run_lua('LivingKnox.Decisions.reset()')
        return gid

    def dpass(self, n=1):
        # LK13-T11 : les membres d'un passage sont évalués un par image (MEMBERS_PER_FRAME) : quatre images.
        for _ in range(n):
            self.h.advance_ms(1000)
            self.h.tick(4)

    def test_hostile_group_fighter_engages_the_seen_player_worker_does_not(self):
        gid = self.mk()
        fighter = self.ev(f'MEMBER_NPC("{gid}", "m-1")')
        worker = self.ev(f'MEMBER_NPC("{gid}", "m-2")')
        for npc in (fighter, worker):
            x, y = self.run_lua(f'local z = LivingKnox.Bodies.find("{npc}") return z:getX(), z:getY()')
            self.h.move_player('A', x + 4, y)
            self.run_lua(f'SEE_PLAYER("{npc}", "A", {int(x) + 4}, {int(y)}, 4)')
        self.h.move_player('A', 100, 100)
        self.dpass(3)
        st = self.run_lua(f'local s = LivingKnox.Decisions.get("{fighter}") return s.rule, s.b, s.why')
        self.assertEqual(st[:2], ('threat', 'fight'))
        self.assertIn('attack player A', st[2])
        self.assertIn('(hostile)', st[2])
        self.assertEqual(self.ev(f'{C}.get("{fighter}").u'), 'A')
        self.assertEqual(self.ev(f'{C}.get("{fighter}").source'), 'decisions')
        self.assertEqual(self.ev(f'{C}.get("{fighter}").t'), 'Base.BaseballBat')
        self.assertIsNone(self.ev(f'{C}.get("{worker}")'))
        self.assertNotEqual(self.run_lua(f'return LivingKnox.Decisions.get("{worker}").b'), 'fight')
        # Combat issu de la cascade : ses consignes ne sont pas « externes » pour le cadre.
        self.assertEqual(self.ev('LivingKnox.Decisions.stats.external'), 0)
        # Joueur perdu de vue : autre comportement, fin de la mêlée.
        self.run_lua('PERCEPTION = {}')
        self.h.advance(2)
        self.dpass(3)
        self.assertNotEqual(self.run_lua(f'return LivingKnox.Decisions.get("{fighter}").b'), 'fight')
        self.assertIsNone(self.ev(f'{C}.get("{fighter}")'))
        self.assertTrue(any('ended after 0 hit(s): decision changed' in line for line in self.lk()), self.lk())
        self.assertEqual(self.h.errors(self.srv), [])


PISTOL = 'Base.Pistol'


class RangedBase(CombatBase):
    def am(self, code, m=None):
        return self.ev('LivingKnox.Ammo.' + code, m)

    def armed(self, gun=PISTOL, rounds=0, mags=0):
        self.assertIs(self.ev(f'LivingKnox.Equipment.setWeapon("lk-1", "{gun}")'), True)
        if rounds or mags:
            per_mag = self.ev(f'FIREARMS["{gun}"].mag and FIREARMS["{gun}"].max or 0')
            self.assertEqual(self.am(f'give("lk-1", "{gun}", {rounds}, {mags})'), rounds + mags * per_mag)

    def body_items(self, t):
        return list(self.run_lua(f'return COUNT_ITEMS(LivingKnox.Bodies.find("lk-1"), "{t}")'))

    def reload(self, code):
        return list(self.run_lua(f'return LivingKnox.Ammo.reload({code})'))

    def loaded(self, gun=PISTOL):
        return self.am(f'loaded(LivingKnox.Bodies.find("lk-1"), "{gun}")')


class AmmoTests(RangedBase):
    """LK_Ammo seul, sur l'autorité (serveur dédié)."""

    def setUp(self):
        super().setUp()
        self.npc()

    def test_magazine_swap_keeps_the_items_and_loose_rounds_fill_the_weapon(self):
        self.armed(rounds=4, mags=2)
        z = 'LivingKnox.Bodies.find("lk-1")'
        self.assertEqual(self.am(f'available({z}, "{PISTOL}")'), 34)
        self.assertEqual(self.am(f'plan({z}, "{PISTOL}")'), 'magazine')
        created = self.ev('ITEM_COUNT')
        self.assertEqual(self.reload(f'"lk-1", {z}, "{PISTOL}"'), [15, 'magazine'])
        self.assertEqual(self.ev('ITEM_COUNT'), created)                 # échange : aucun objet créé
        self.assertEqual(self.body_items('Base.9mmClip'), [2, 15])       # un chargeur plein, un vide
        for _ in range(15):
            self.assertIs(self.am(f'consume({z}, "{PISTOL}")'), True)
        self.assertIs(self.am(f'consume({z}, "{PISTOL}")'), False)      # arme vide : aucun tir
        self.assertEqual(self.am('stats.empty'), 1)
        self.assertEqual(self.reload(f'"lk-1", {z}, "{PISTOL}"'), [15, 'magazine'])
        self.assertEqual(self.body_items('Base.9mmClip'), [2, 0])        # chargeurs vides gardés
        for _ in range(15):
            self.am(f'consume({z}, "{PISTOL}")')
        self.assertEqual(self.am(f'plan({z}, "{PISTOL}")'), 'rounds')
        self.assertEqual(self.reload(f'"lk-1", {z}, "{PISTOL}"'), [4, 'rounds'])
        self.assertEqual(self.body_items('Base.Bullets9mm'), [0, 0])     # cartouches retirées de l'inventaire
        for _ in range(4):
            self.am(f'consume({z}, "{PISTOL}")')
        self.assertIsNone(self.am(f'plan({z}, "{PISTOL}")'))
        self.assertEqual(self.am(f'available({z}, "{PISTOL}")'), 0)
        self.assertEqual(self.ev(f'{z}:getModData().LKAmmo.n'), 0)       # état gardé dans les ModData du corps

    def test_shotgun_without_magazine_loads_up_to_its_capacity(self):
        self.armed('Base.Shotgun', rounds=7, mags=3)                     # chargeurs ignorés : aucun pour cette arme
        z = 'LivingKnox.Bodies.find("lk-1")'
        self.assertEqual(self.body_items('Base.ShotgunShells'), [7, 0])
        self.assertEqual(self.reload(f'"lk-1", {z}, "Base.Shotgun"'), [5, 'rounds'])
        self.assertEqual(self.body_items('Base.ShotgunShells'), [2, 0])
        self.assertIsNone(self.am(f'plan({z}, "Base.Shotgun")'))         # arme pleine
        self.assertEqual(self.loaded(PISTOL), 0)                         # autre arme : rien dedans

    def test_bad_types_and_clients(self):
        self.assertEqual(list(self.run_lua('return LivingKnox.Ammo.spec("Base.BaseballBat")')),
                         [None, 'Base.BaseballBat is not a firearm'])
        self.assertEqual(self.am(f'available(LivingKnox.Bodies.find("lk-1"), "Base.BaseballBat")'), 0)
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Ammo'))           # client MP : module arrêté


class RangedMultiplayerTests(RangedBase, MultiplayerCombatTests):
    def run_ms(self, ms, sent=None):
        """ms de jeu : images, pas de marche de la copie du propriétaire recopié sur les autres, messages relevés."""
        zid = self.npc_zid
        for _ in range(int(ms / self.h.tick_ms)):
            self.h.tick(1)
            owner = self.h.owners.get(zid, 'server')
            self.h.eval(owner, f'STEP({zid}, 0.05)')
            zb = self.h.zombie(owner, zid)
            self.h.move_zombie(zid, zb.x, zb.y)
            if sent is not None:
                sent += [m for m in self.h.pending() if m['command'] in ('combatHit', 'combatShot')]
            self.h.pump()

    def shot_lines(self):
        return [line for line in self.lk() if 'shot at A with' in line]

    def test_reload_then_one_shot_per_round_and_never_without_ammo(self):
        self.ready('A')
        self.armed(rounds=3)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        self.assertEqual(self.c('get("lk-1").m'), 'ranged')
        self.assertEqual(self.c('get("lk-1").t'), PISTOL)
        self.assertEqual(self.c('get("lk-1").reach'), 15)
        # Arme vide : rechargement sur place, regard vers la cible, geste chez les deux clients.
        self.assertEqual(self.c('orders["lk-1"].phase'), 'reload')
        self.assertEqual(self.ev('LivingKnox.Directives.get("lk-1").op'), 'face')
        self.relayed()
        for cl in ('A', 'B'):
            self.assertEqual(self.h.eval(cl, 'LivingKnox.Anim.gestureOf("lk-1")'), 'reload')
            self.assertEqual(self.h.eval(cl, 'LivingKnox.CombatView.remote.d["lk-1"].m'), 'ranged')
        sent = []
        self.run_ms(3700, sent)
        self.assertEqual(self.c('orders["lk-1"].phase'), 'reload')       # deux boucles pour des cartouches libres
        self.run_ms(14000, sent)
        # Trois cartouches : trois tirs acceptés, jamais plus ; puis mêlée à mains nues contre la même cible.
        self.assertEqual(self.c('stats.shots'), 3)
        self.assertEqual(self.c('stats.reloads'), 1)
        self.assertEqual(self.c('stats.outOfAmmo'), 1)
        self.assertEqual(self.c('get("lk-1").m'), 'melee')
        self.assertEqual(self.c('get("lk-1").t'), 'Base.BareHands')
        self.assertEqual(self.c('get("lk-1").c'), 2)
        self.assertEqual(self.body_items('Base.Bullets9mm'), [0, 0])
        self.assertEqual(self.loaded(), 0)
        reports = [m for m in sent if m['command'] == 'combatHit']
        self.assertEqual({m['from'] for m in reports}, {'A'})            # rapportés par le seul propriétaire
        hits = self.c('stats.hits')
        self.assertEqual(hits + self.c('stats.misses'), 3)
        self.assertEqual(self.damages('A'), self.c('stats.applied'))
        self.assertEqual(lua_list(self.ev('SENT_DAMAGE')).count('A'), self.c('stats.applied'))
        self.assertEqual(self.ev('DAMAGES.A and DAMAGES.A[1]'), PISTOL if hits else None)
        # Bruit pour les zombies : un par tir, rayon SoundRadius (dehors), volume SoundVolume.
        noises = lua_list(self.ev('NOISES'))
        self.assertEqual([(n.r, n.v) for n in noises], [(100, 30)] * 3)
        # Son et éclair : chaque client proche reçoit chaque tir une fois et le joue une fois.
        self.assertEqual(self.c('stats.shotMessages'), 6)                # 3 tirs x 2 clients proches
        for cl in ('A', 'B'):
            self.assertEqual(self.h.eval(cl, 'LivingKnox.CombatView.stats.shotsReceived'), 3)
            self.assertEqual(self.h.eval(cl, 'LivingKnox.CombatView.stats.shotsPlayed'), 3)
            self.assertEqual([s.name for s in lua_list(self.h.eval(cl, 'SHOT_SOUNDS'))], ['M9Shoot'] * 3)
            self.assertEqual(len(lua_list(self.h.eval(cl, 'LIGHTS'))), 3)
            light = self.h.eval(cl, 'LIGHTS[1]')
            self.assertEqual((light.radius, light.life), (18, 6))
            self.assertAlmostEqual(light.r, 0.16)                        # jour : i = 0,2
        self.assertEqual(self.h.eval('server', '#SHOT_SOUNDS + #LIGHTS'), 0)   # le serveur ne joue rien
        # Touches décidées par le serveur seul : tirage reproductible comparé à la chance.
        lines = self.shot_lines()
        self.assertEqual(len(lines), 3)
        for k, line in enumerate(lines, 1):
            m = re.search(r'chance (\d+), roll (\d+): (hit|missed)', line)
            self.assertEqual(int(m.group(2)), self.c(f'roll("lk-1", 1, {k})'))
            self.assertEqual(m.group(3), 'hit' if int(m.group(2)) <= int(m.group(1)) else 'missed')
        self.assertEqual(self.h.errors('server'), [])

    def ranged_in_position(self, rounds=1):
        """PNJ armé et rechargé, en phase de tir contre A (touches forgées seules, aucun minutage)."""
        self.ready('A')
        self.armed(rounds=rounds)
        self.h.load('A', 'LivingKnox.CombatView.tick = function() end')
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        for _ in range(3):
            self.h.advance_ms(4000)
            self.c('step("lk-1")')
        self.assertEqual(self.c('orders["lk-1"].phase'), 'shoot')
        self.assertEqual(self.loaded(), rounds)

    def test_forged_shot_without_ammo_is_refused_and_has_no_effect(self):
        self.ranged_in_position(rounds=1)
        self.assertTrue(self.forge() or self.c('stats.misses') == 1)
        self.assertEqual(self.c('stats.shots'), 1)
        noises = len(lua_list(self.ev('NOISES')))
        # Arme vide, avant le passage suivant : un rapport de plus est refusé, sans bruit, son ni dommage.
        self.assertFalse(self.forge(gap_ms=1300))
        self.assertEqual(self.why('no ammo'), 1)
        self.assertEqual(self.c('stats.shots'), 1)
        self.assertEqual(len(lua_list(self.ev('NOISES'))), noises)
        self.assertEqual(len([m for m in self.h.pending() if m['command'] == 'combatShot']), 2)   # A et B, une fois
        self.assertEqual(self.damages('A'), self.c('stats.hits'))
        self.assertTrue(any('shot of npc lk-1 reported by A refused: no ammo' in line for line in self.lk()))

    def test_blocked_line_of_fire_refused_and_npc_moves(self):
        self.ranged_in_position(rounds=2)
        self.run_lua('LOS_RESULT = "Blocked"')
        self.assertFalse(self.forge())
        self.assertEqual(self.why('no line of fire'), 1)
        self.assertEqual(self.loaded(), 2)                               # aucune cartouche retirée
        self.run_lua('LOS_RESULT = "ClearThroughClosedDoor"')            # porte vitrée fermée : pas de tir (LK06-T08)
        self.c('step("lk-1")')
        self.assertEqual(self.c('orders["lk-1"].phase'), 'approach')
        self.assertEqual(self.ev('LivingKnox.Directives.get("lk-1").op'), 'move')
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'run')
        self.run_lua('LOS_RESULT = "ClearThroughOpenDoor"')
        self.c('step("lk-1")')
        self.assertEqual(self.c('orders["lk-1"].phase'), 'aim')

    def test_out_of_range_and_cadence_and_owner_checks(self):
        self.ranged_in_position(rounds=3)
        self.h.move_player('A', 102.5, 120.5)                            # 18 cases : hors de portée (15 + 1)
        self.assertFalse(self.forge())
        self.assertEqual(self.why('out of reach'), 1)
        self.h.move_player('A', 106.5, 102.5)
        self.assertFalse(self.forge('B', gap_ms=2000))
        self.assertEqual(self.why('not the owner'), 1)
        self.assertTrue(self.forge(gap_ms=2000) or self.c('stats.misses') == 1)
        self.assertFalse(self.forge(gap_ms=100))
        self.assertEqual(self.why('too fast'), 1)
        self.assertEqual(self.c('stats.shots'), 1)
        self.assertEqual(self.loaded(), 2)

    def test_noise_inside_and_duplicate_shot_played_once(self):
        self.ranged_in_position(rounds=2)
        self.run_lua('INSIDE = true; NOISE_MULT = 2')
        self.forge()
        self.assertEqual([(n.r, n.v) for n in lua_list(self.ev('NOISES'))], [(100, 30)])   # 100 x 2 x 0,5
        shots = [m for m in self.h.pending() if m['command'] == 'combatShot']
        self.h.pump()
        args = shots[0]['args']
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'combatShot', args)   # même tir livré deux fois
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.stats.shotsPlayed'), 1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.stats.shotsDuplicate'), 1)
        self.assertEqual(len(lua_list(self.h.eval('A', 'SHOT_SOUNDS'))), 1)
        self.assertEqual(len(lua_list(self.h.eval('A', 'LIGHTS'))), 1)
        # Corps inconnu du client : émetteur libre à la position du tir.
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'combatShot',
                    {'s': {'k': 'x-1', 'npc': 'lk-9', 'o': 9, 'x': 50.5, 'y': 60.5, 'z': 0, 'snd': 'M9Shoot'}})
        self.assertEqual(lua_list(self.h.eval('B', 'SHOT_SOUNDS'))[-1].via, 'free')
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'combatShot',
                    {'s': {'k': 'x-2', 'npc': 'lk-9', 'x': 50.5, 'y': 60.5, 'z': 0, 'snd': 'bad sound'}})
        self.assertEqual(self.h.eval('B', 'LivingKnox.CombatView.stats.shotsRefused'), 1)

    def test_firearm_without_ammo_stays_melee(self):
        self.ready('A', player_at=(103.5, 102.5))
        self.armed()
        self.c('engage("lk-1", "A")')
        self.assertEqual(self.c('get("lk-1").m'), 'melee')
        self.assertEqual(self.c('get("lk-1").t'), 'Base.BareHands')

    # Tests de mêlée hérités : non rejoués ici.
    test_approach_then_strikes_reported_by_the_owner_and_applied_once_each = None
    test_no_hit_out_of_reach_is_accepted = None
    test_each_hit_applied_once_and_cadence_enforced = None
    test_only_the_owner_reports_and_a_previous_owner_is_ignored = None
    test_stale_order_wrong_target_and_dead_target = None
    test_order_sent_to_near_clients_only_and_again_after_a_reconnection = None
    test_firearm_holder_strikes_bare_handed_and_a_bat_gives_its_reach = None
    test_clients_never_decide = None


class HitChanceTests(RangedBase):
    """Chance de toucher portée de CombatManager.calculateHitChanceData (constantes CombatConfigKey par défaut)."""
    mode = 'solo'

    @staticmethod
    def vanilla(hit, aim_mod, min_s, max_s, d, aim=3):
        chance = min(hit, 95) + aim_mod * aim
        pb = 3.5
        sightless = 0.0
        if d > pb:
            sightless = (pb - d) * (15 + (pb - d) * -0.7)
        elif d < pb:
            sightless = (pb - d) / pb * 40
        lo, hi = min_s * (1 - aim / 30), max_s * (1 + aim / 30)
        if d < lo:
            sights = (d - lo) * (4 + (d - lo) * -0.3) if d > pb else 0.0
        elif d > hi:
            sights = -((d - hi) * (4 + (d - hi) * 0.3))
        else:
            import math
            sights = 15 * math.exp(-((d - (lo + (hi - lo) * 0.5)) ** 2) / (2 * ((hi - lo) / 7)) ** 2)
        return max(5, min(100, int(chance + max(sightless, sights))))

    def test_hit_chance_matches_the_vanilla_formula_and_roll_is_reproducible(self):
        self.init()
        for gun, f in ((PISTOL, (50, 4, 2, 6)), ('Base.Shotgun', (65, 4, 3, 8))):
            for d in (0.5, 2, 3.5, 4.2, 5, 8, 10, 15, 20):
                got = self.run_lua(f'return LivingKnox.Combat.hitChance(instanceItem("{gun}"), {d})')
                self.assertEqual(got, self.vanilla(*f, d), (gun, d))
        self.assertEqual(self.c('hitChance(instanceItem("Base.Pistol"), 1)'), 90)    # bout portant : 62 + 28,6
        self.assertEqual(self.c('hitChance(instanceItem("Base.Pistol"), 40)'), 5)    # plancher
        rolls = [self.c(f'roll("lk-1", 1, {k})') for k in range(1, 200)]
        self.assertTrue(all(0 <= r <= 99 for r in rolls))
        self.assertGreater(len(set(rolls)), 60)                          # répartis
        self.assertEqual(rolls[:5], [self.c(f'roll("lk-1", 1, {k})') for k in range(1, 6)])   # reproductibles
        self.assertNotEqual(rolls[:5], [self.c(f'roll("lk-2", 1, {k})') for k in range(1, 6)])


class RangedSoloTests(RangedBase):
    mode = 'solo'

    def test_solo_shoots_without_messages_and_plays_each_shot_once(self):
        zid = self.npc()
        self.npc_zid = zid
        self.h.move_player('A', 106.5, 102.5)
        self.armed(mags=1)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        for _ in range(int(9000 / self.h.tick_ms)):
            self.h.tick(1)
        shots = self.c('stats.shots')
        self.assertGreaterEqual(shots, 5)
        self.assertEqual(self.ev('LivingKnox.CombatView.stats.shotsPlayed'), shots)
        self.assertEqual(len(lua_list(self.ev('SHOT_SOUNDS'))), shots)
        self.assertEqual(len(lua_list(self.ev('LIGHTS'))), shots)
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(lua_list(self.ev('SENT_DAMAGE')), [])
        self.assertEqual(self.loaded(), 15 - shots)
        self.assertEqual(self.body_items('Base.9mmClip'), [1, 0])        # chargeur vide échangé
        self.assertEqual(self.c('stats.refused'), 0)

    def test_suite_lk_ranged_passes_on_the_doubles(self):
        self.init()
        self.h.load('solo', 'shared/RST/suites/RST_LKRanged.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.ranged", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.ranged')
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.ranged", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(8000):
            self.h.tick()
            self.h.load('solo', 'for id in pairs(HARNESS.zombies) do STEP(id, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertTrue(report.ok, results)
        self.assertEqual(len(results), 1, results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKR] measure')]
        self.assertTrue(any('played here: 3' in line for line in measures), measures)


# ======================================================================== sons de la mêlée (LK06-T11)

class MeleeSoundBase(CombatBase):
    """Sons d'un coup de mêlée : élan joué localement au début de chaque boucle du geste de frappe, impact envoyé par
    l'autorité pour chaque touche acceptée (combatMelee), joué une fois par client proche. Doublures : MELEE_SCRIPTS,
    BODY_EMITTER (COMBAT_DOUBLES)."""

    def played(self, m):
        return lua_list(self.h.eval(m, 'MELEE_NAMES_PLAYED()'))

    def names(self, m):
        return [x.split(':', 1)[1] for x in self.played(m)]


class MeleeSoundMultiplayerTests(MeleeSoundBase):
    def ready(self, weapon=None, b_at=(102.5, 104.5)):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for cl in ('A', 'B'):
            self.h.eval(cl, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.move_player('A', 103.5, 102.5)
        self.h.move_player('B', *b_at)
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.npc_zid = zid
        if weapon:
            self.assertIs(self.ev(f'LivingKnox.Equipment.setWeapon("lk-1", "{weapon}")'), True)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        self.assertEqual(self.c('orders["lk-1"].phase'), 'strike')
        self.relayed()
        return zid

    def forge(self, gap_ms=0, **kw):
        """Touche du propriétaire A envoyée au serveur ; messages combatMelee en attente (non livrés)."""
        self.h.advance_ms(gap_ms)
        self.n = getattr(self, 'n', 100) + 1
        args = {'id': 'lk-1', 'c': self.c('orders["lk-1"].c'), 'n': self.n, 'u': 'A', 'x': 0, 'y': 0, 'z': 0}
        args.update(kw)
        self.h.fire('server', 'OnClientCommand', 'LivingKnox', 'combatHit', self.h.player('server', 'A'), args)
        return [m for m in self.h.pending() if m['command'] == 'combatMelee']

    def silenced(self):
        for cl in ('A', 'B'):   # touches forgées seules : aucun minutage ni élan local
            self.h.load(cl, 'LivingKnox.CombatView.tick = function() end')

    def test_accepted_hit_sends_the_weapon_impact_once_to_each_near_client(self):
        self.ready('Base.BaseballBat')
        self.silenced()
        msgs = self.forge()
        self.assertEqual(self.c('stats.applied'), 1)
        self.assertEqual(sorted(m['to'] for m in msgs), ['A', 'B'])
        e = msgs[0]['args']['m']
        self.assertEqual((e['npc'], e['sw'], e['hit']), ('lk-1', 'BaseballBatSwing', 'BaseballBatHit'))
        self.h.pump()
        for cl in ('A', 'B'):
            self.assertEqual(self.names(cl), ['BaseballBatHit'], cl)
            self.assertEqual(self.h.eval(cl, 'LivingKnox.CombatView.stats.meleeImpacts'), 1)
        self.assertEqual(self.played('A'), ['body:BaseballBatHit'])            # copie du corps du propriétaire
        self.assertEqual(lua_list(self.h.eval('A', 'MELEE_STOPPED')), ['BaseballBatSwing'])   # élan arrêté
        self.assertEqual(self.played('server'), [])                             # le serveur ne joue rien
        self.assertEqual(lua_list(self.ev('NOISES')), [])                       # aucun bruit pour les zombies
        # Livraison répétée : ignorée.
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'combatMelee', {'m': e})
        self.assertEqual(self.names('A'), ['BaseballBatHit'])
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.stats.meleeDuplicate'), 1)
        # Touche refusée (hors de portée) : aucun impact.
        self.h.move_player('A', 110.5, 102.5)
        self.assertEqual(self.forge(gap_ms=2000), [])
        self.assertEqual(self.why('out of reach'), 1)
        # Client lointain : rien ; client proche : un impact par touche.
        self.h.move_player('A', 103.5, 102.5)
        self.h.move_player('B', 400, 400)
        msgs = self.forge(gap_ms=2000)
        self.assertEqual([m['to'] for m in msgs], ['A'])
        self.h.pump()
        self.assertEqual(self.names('A'), ['BaseballBatHit'] * 2)
        self.assertEqual(self.names('B'), ['BaseballBatHit'])
        self.assertEqual(self.h.errors('server') + self.h.errors('A') + self.h.errors('B'), [])

    def test_bare_hands_stomp_and_silent_weapon(self):
        self.ready()
        self.silenced()
        self.assertIs(self.c('get("lk-1").bare'), True)
        self.assertEqual(self.c('get("lk-1").sw'), 'AttackShove')
        e = self.forge()[0]['args']['m']
        self.assertEqual((e['sw'], e['hit']), ('AttackShove', 'BareHandsHit'))
        # Piétinement (geste "stomp" d'un coup au sol) : élan AttackStomp, impact HitFloorSound de Base.BareHands.
        self.ev('LivingKnox.Anim.setGesture("lk-1", "stomp")')
        e = self.forge(gap_ms=2000)[-1]['args']['m']
        self.assertEqual((e['sw'], e['hit']), ('AttackStomp', 'BareHandsHit'))
        # Arme sans HitSound : touche appliquée, aucun impact envoyé.
        self.c('disengage("lk-1", "test")')
        self.assertIs(self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.TestSilent")'), True)
        self.assertEqual(self.c('engage("lk-1", "A")'), 2)
        before = len([m for m in self.h.pending() if m['command'] == 'combatMelee'])
        applied = self.c('stats.applied')
        after = len(self.forge(gap_ms=2000))
        self.assertEqual(self.c('stats.applied'), applied + 1)
        self.assertEqual(after, before)
        self.assertEqual(self.c('stats.meleeSilent'), 1)

    def test_names_follow_the_weapon_script_like_the_vanilla(self):
        self.ready()
        rows = self.ev('(function() local C = LivingKnox.Combat local out = {} '
                       'for _, t in ipairs({ "Base.BaseballBat", "Base.KitchenKnife", "Base.BareHands", '
                       '"Base.TestNoFloor", "Base.TestSilent" }) do local w = instanceItem(t) '
                       'out[#out + 1] = table.concat({ t, tostring(C.swingSound(w, false)), '
                       'tostring(C.impactSound(w, "strike")), tostring(C.impactSound(w, "strikefloor")) }, "|") '
                       'end return table.concat(out, ";") end)()')
        self.assertEqual(rows.split(';'), [
            'Base.BaseballBat|BaseballBatSwing|BaseballBatHit|BaseballBatHit',
            'Base.KitchenKnife|KitchenKnifeSwing|KitchenKnifeHit|KitchenKnifeHit',
            'Base.BareHands|BaseballBatSwing|BareHandsHit|BareHandsHit',
            'Base.TestNoFloor|TestNoFloorSwing|TestNoFloorHit|BatOnFloor',
            'Base.TestSilent|TestSilentSwing|nil|BatOnFloor'])
        self.assertEqual(self.c('swingSound(nil, true)'), 'AttackShove')
        # Entrées invalides refusées par le client.
        self.assertIs(self.h.eval('A', 'LivingKnox.CombatView.onMelee({ k = "x", hit = "a b", x = 1, y = 1, z = 0 })'),
                      False)
        self.assertIs(self.h.eval('A', 'LivingKnox.CombatView.onMelee({ k = "x", hit = "Hit", sw = 3, x = 1, y = 1, '
                                       'z = 0 })'), False)
        self.assertEqual(self.h.eval('A', 'LivingKnox.CombatView.stats.meleeRefused'), 2)

    def test_strikes_swing_each_loop_and_hit_once_per_accepted_hit_on_near_clients(self):
        self.ready('Base.BaseballBat')
        start = self.h.real_ms
        for _ in range(int(6000 / self.h.tick_ms)):
            self.h.tick(1)
            self.h.pump()
        seconds = (self.h.real_ms - start) / 1000
        applied = self.c('stats.applied')
        strike_ms = self.ev('LivingKnox.Config.COMBAT.STRIKE_MS')
        loops = seconds * 1000 / strike_ms
        self.assertGreaterEqual(applied, int(loops) - 1)
        for cl in ('A', 'B'):
            names = self.names(cl)
            swings = names.count('BaseballBatSwing')
            self.assertEqual(names.count('BaseballBatHit'), applied, cl)       # un impact par touche acceptée
            self.assertGreaterEqual(swings, int(loops), cl)                     # un élan par boucle du clip
            self.assertLessEqual(swings, int(loops) + 2, cl)
            self.assertEqual(names[0], 'BaseballBatSwing', cl)                  # élan puis impact
            self.assertEqual(set(names), {'BaseballBatSwing', 'BaseballBatHit'}, cl)
        self.assertEqual(self.played('server'), [])
        self.assertEqual(self.h.errors('server') + self.h.errors('A') + self.h.errors('B'), [])


class MeleeSoundSoloTests(MeleeSoundBase):
    mode = 'solo'

    def test_solo_swing_then_impact_by_direct_calls(self):
        zid = self.npc()
        self.npc_zid = zid
        self.h.move_player('A', 103.5, 102.5)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)          # mains nues
        for _ in range(int(4000 / self.h.tick_ms)):
            self.h.tick(1)
        applied = self.c('stats.applied')
        self.assertGreaterEqual(applied, 2)
        names = self.names('solo')
        self.assertEqual(names[0], 'AttackShove')
        self.assertEqual(names.count('BareHandsHit'), applied)
        self.assertGreaterEqual(names.count('AttackShove'), applied)
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.ev('LivingKnox.CombatView.lastMelee.hit'), 'BareHandsHit')
        self.assertEqual(self.h.errors('solo'), [])


# ======================================================================== sons et mort du corps (LK06-T13)

class DeathSoundBase(MeleeSoundBase):
    """Constat en jeu du 2026-10-13 : un PNJ tué pendant sa frappe, le son de mêlée continue sur le corps tombé. Le
    moteur n'arrête ni ne fait plus avancer l'émetteur d'un zombie mort (IsoDeadBody.java:358-361) : la doublure
    BODY_EMITTER ne termine jamais un son d'elle-même. Attendu : sons lancés sur le corps arrêtés à sa mort, aucun son
    de mêlée ensuite (élan rejoué ou impact reçu en retard), rien ne change pour un coup normal."""

    def body(self, m):
        return f'HARNESS.zombies[{self.npc_zid}]'

    def playing(self, m, name):
        return self.h.eval(m, f'{self.body(m)}:getEmitter():isPlaying("{name}")')

    def stopped(self, m):
        return lua_list(self.h.eval(m, 'MELEE_STOPPED'))

    def count_played(self, m):
        return len(self.played(m)) + len(lua_list(self.h.eval(m, 'SHOT_SOUNDS')))


class DeathSoundSoloTests(DeathSoundBase):
    mode = 'solo'

    def engage(self):
        zid = self.npc()
        self.npc_zid = zid
        self.h.move_player('A', 103.5, 102.5)
        self.assertIs(self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")'), True)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        return zid

    def until_swing(self, limit_ms=4000):
        """Images jusqu'au prochain élan joué (son encore en cours)."""
        start = len(self.names('solo'))
        for _ in range(int(limit_ms / self.h.tick_ms)):
            self.h.tick(1)
            names = self.names('solo')[start:]
            if 'BaseballBatSwing' in names:
                return
        self.fail('no swing played')

    def kill(self):
        # Chemin de Health.kill en solo (coup mortel du joueur) : Kill(arme, tueur) -> OnZombieDead (IsoZombie.java:
        # 4599-4610). LK_Health n'est pas chargé par ce banc.
        self.run_lua(f'{self.body("solo")}:Kill(instanceItem("Base.Hammer"), getPlayer())')
        self.assertIs(self.h.eval('solo', f'{self.body("solo")}:isDead()'), True)

    def test_death_during_a_swing_stops_it_and_no_melee_sound_follows(self):
        self.engage()
        self.until_swing()
        self.assertIs(self.playing('solo', 'BaseballBatSwing'), True)
        stopped0 = len(self.stopped('solo'))
        played0 = self.count_played('solo')
        self.kill()
        # À l'instant de la mort (OnZombieDead) : élan en cours arrêté sur l'émetteur du corps.
        self.assertIn('BaseballBatSwing', self.stopped('solo')[stopped0:])
        self.assertIs(self.playing('solo', 'BaseballBatSwing'), False)
        self.assertEqual(self.ev('LivingKnox.CombatView.stats.bodySoundsStopped'), 1)
        # Quelques secondes : aucun son de mêlée joué ni rejoué, rien ne joue plus sur le corps.
        for _ in range(int(4000 / self.h.tick_ms)):
            self.h.tick(1)
        self.assertEqual(self.count_played('solo'), played0)
        for name in ('BaseballBatSwing', 'BaseballBatHit'):
            self.assertIs(self.playing('solo', name), False, name)
        # Impact reçu en retard pour ce corps mort : joué nulle part (ni corps ni émetteur libre).
        self.assertIs(self.ev('LivingKnox.CombatView.onMelee({ k = "late", npc = "lk-1", x = 102, y = 102, z = 0, '
                              'sw = "BaseballBatSwing", hit = "BaseballBatHit" })'), False)
        self.assertEqual(self.count_played('solo'), played0)
        self.assertEqual(self.ev('LivingKnox.CombatView.stats.meleeNoBody'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_normal_strikes_unchanged_and_nothing_stopped(self):
        self.engage()
        for _ in range(int(4000 / self.h.tick_ms)):
            self.h.tick(1)
        applied = self.c('stats.applied')
        self.assertGreaterEqual(applied, 2)
        names = self.names('solo')
        self.assertEqual(names.count('BaseballBatHit'), applied)
        self.assertGreaterEqual(names.count('BaseballBatSwing'), applied)
        # Seuls les arrêts vanilla de l'élan à l'impact ; aucun arrêt de fin de vie.
        self.assertEqual(set(self.stopped('solo')), {'BaseballBatSwing'})
        self.assertEqual(len(self.stopped('solo')), applied)
        self.assertEqual(self.ev('LivingKnox.CombatView.stats.bodySoundsStopped'), 0)
        # Ordre fini, corps vivant : la note est oubliée sans rien arrêter.
        self.c('disengage("lk-1", "test")')
        for _ in range(int(7000 / self.h.tick_ms)):
            self.h.tick(1)
        self.assertEqual(self.ev('LivingKnox.CombatView.stats.bodySoundsStopped'), 0)
        self.assertIsNone(self.ev('LivingKnox.CombatView.bodySounds["lk-1"]'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_body_on_the_floor_never_swings(self):
        self.engage()
        self.run_lua(f'{self.body("solo")}.onFloor = true')
        played0 = self.count_played('solo')
        for _ in range(int(3000 / self.h.tick_ms)):
            self.h.tick(1)
        self.assertEqual([n for n in self.names('solo')[played0:] if n == 'BaseballBatSwing'], [])
        self.assertEqual(self.h.errors('solo'), [])


class DeathSoundMultiplayerTests(DeathSoundBase):
    def ready(self):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for cl in ('A', 'B'):
            self.h.eval(cl, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.move_player('A', 103.5, 102.5)
        self.h.move_player('B', 102.5, 104.5)
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.npc_zid = zid
        self.assertIs(self.ev('LivingKnox.Equipment.setWeapon("lk-1", "Base.BaseballBat")'), True)
        self.assertEqual(self.c('engage("lk-1", "A")'), 1)
        self.relayed()
        return zid

    def client_death(self, cl):
        """Mort de la copie du client (DeadZombiePacket : die() de la copie, OnZombieDead sur ce client), AVANT la
        fin de l'ordre de mêlée reçue du serveur (commandes non ordonnées)."""
        self.h.load(cl, f'{self.body(cl)}.health = 0; {self.body(cl)}:die()')

    def test_client_copy_dies_with_the_order_still_known(self):
        self.ready()
        # B voit la frappe : élan joué sur sa copie.
        for _ in range(int(3000 / self.h.tick_ms)):
            self.h.tick(1)
            if self.playing('B', 'BaseballBatSwing'):
                break
        self.assertIs(self.playing('B', 'BaseballBatSwing'), True)
        self.assertIsNotNone(self.h.eval('B', 'LivingKnox.CombatView.orders()["lk-1"]'))
        # Coup de feu reçu sur le même corps (son du tir noté lui aussi).
        self.assertIs(self.h.eval('B', 'LivingKnox.CombatView.onShot({ k = "s1", npc = "lk-1", x = 102, y = 102, '
                                       'z = 0, snd = "M9Shoot" })'), True)
        self.assertEqual(lua_list(self.h.eval('B', 'SHOT_SOUNDS'))[-1].via, 'body')
        played0 = self.count_played('B')
        stopped0 = len(self.stopped('B'))
        self.client_death('B')
        self.assertEqual(set(self.stopped('B')[stopped0:]), {'BaseballBatSwing', 'M9Shoot'})
        self.assertIs(self.playing('B', 'BaseballBatSwing'), False)
        self.assertIs(self.playing('B', 'M9Shoot'), False)
        # Ordre toujours connu de B (fin non reçue) : aucun élan rejoué sur la copie morte.
        self.assertIsNotNone(self.h.eval('B', 'LivingKnox.CombatView.orders()["lk-1"]'))
        for _ in range(int(3000 / self.h.tick_ms)):
            self.h.tick(1)
        self.assertEqual(self.count_played('B'), played0)
        # Impact envoyé avant la mort, reçu après : joué nulle part.
        self.h.fire('B', 'OnServerCommand', 'LivingKnox', 'combatMelee',
                    {'m': {'k': 'late', 'npc': 'lk-1', 'x': 102, 'y': 102, 'z': 0, 'sw': 'BaseballBatSwing',
                           'hit': 'BaseballBatHit'}})
        self.assertEqual(self.count_played('B'), played0)
        self.assertEqual(self.h.eval('B', 'LivingKnox.CombatView.stats.meleeNoBody'), 1)
        self.assertEqual(self.h.errors('B'), [])


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        files = MOD_FILES + [SUITE, RANGED_SUITE, LUA / 'server' / 'LivingKnox' / 'LK_Decisions.lua']
        for path in files:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b'):
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')
        for suite in (SUITE, RANGED_SUITE):
            self.assertTrue(all(b < 128 for b in suite.read_bytes()), f'{suite.name}: non ASCII byte')

    def test_no_global_moddata_and_no_broadcast(self):
        for path in MOD_FILES:
            code = path.read_text(encoding='utf-8')
            self.assertNotIn('ModData.', code)
            self.assertNotIn('sendServerCommand(Combat.MODULE', code)   # toujours un joueur destinataire


# Groupe de test qui ne tire pas le premier (hostilité 10) : combattant à la batte et ouvrier (LK06-T05).
KEEPERS = r'''
if not LivingKnox.GroupTypes.isKnown("keepers") then
    assert(LivingKnox.GroupTypes.register({
        format = 1, id = "keepers", nameKey = "IGUI_LK_GroupType_settlers", size = { min = 1, max = 12 },
        hostility = 10, home = "building", morale = 60, needs = { food = 50, medical = 50, ammo = 50 },
        roles = { fighter = { weight = 1, behaviours = { "guard", "defend", "fight" } },
                  worker = { weight = 1, behaviours = { "chores", "cook" } } },
        profiles = {
            { id = "thug", role = "fighter", weight = 1, weapons = { "Base.BaseballBat" }, looks = { "manFairBeard" } },
            { id = "cook", role = "worker", weight = 1, outfits = { "Generic02" }, weapons = { "Base.KitchenKnife" } },
        },
    }))
end
'''


class DefenceStackTests(DecisionCombatTests):
    """LK06-T05 sur la pile complète (serveur dédié + deux clients) : appel à l'aide après un coup reçu, renfort des
    combattants, reddition d'un non-combattant et groupe qui épargne le joueur, reddition rompue, retraite d'un
    combattant blessé qui passe sa cible. Le coup est celui que LK_Health accepte (Decisions.noteHit, appelé par
    Health.applyHit) ; la santé vient de la blessure du registre (LK_Health non chargé sur ce banc)."""

    De = 'LivingKnox.Decisions'
    test_hostile_group_fighter_engages_the_seen_player_worker_does_not = None   # déjà jouée par la classe mère

    def make(self, root=None):
        h = super().make(root)
        h.load('solo' if self.mode == 'solo' else 'server', KEEPERS)
        return h

    def mk_crew(self, gtype, crew):
        code = (f'local G = LivingKnox.Groups local g = assert(G.create({{ type = "{gtype}", name = "Crew", day = 1, '
                'home = { x = 110, y = 110, z = 0 } })) ')
        for role, profile in crew:
            code += f'assert(G.addMember(g.id, {{ role = "{role}", profile = "{profile}", female = false, day = 1 }})) '
        gid = self.run_lua(code + 'assert(G.setLeader(g.id, "m-1", 1)) return g.id')
        self.run_lua(f'{self.De}.state.lastPass = 1e18')
        self.h.move_player('A', 100, 100)
        for _ in range(8):
            self.passes(1)
            if len(self.bodies(gid)) == len(crew):
                break
        self.assertEqual(len(self.bodies(gid)), len(crew))
        self.run_lua(f'{self.De}.reset()')
        return gid

    def npc_of(self, gid, mid):
        return self.ev(f'MEMBER_NPC("{gid}", "{mid}")')

    def place(self, npc, x, y):
        self.run_lua(f'HARNESS.place(LivingKnox.Bodies.find("{npc}"), {x}, {y}, 0)')

    def hit_by(self, npc, name='A'):
        return self.run_lua(f'return {self.De}.noteHit("{npc}", LivingKnox.Bodies.find("{npc}"), '
                            f'LivingKnox.Combat.playerByName("{name}"))')

    def st(self, npc):
        return self.run_lua(f'local s = {self.De}.get("{npc}") if s == nil then return nil end return s.rule, s.b, '
                            's.why')

    def test_hit_calls_for_help_fighter_defends_then_surrender_spares_the_player(self):
        gid = self.mk_crew('keepers', [('fighter', 'thug'), ('worker', 'cook')])
        fighter, worker = self.npc_of(gid, 'm-1'), self.npc_of(gid, 'm-2')
        self.place(fighter, 104.5, 104.5)
        self.place(worker, 106.5, 104.5)
        self.h.move_player('A', 110.5, 104.5)
        self.run_lua(f'SEE_PLAYER("{worker}", "A", 110, 104, 4)')
        self.dpass(2)
        self.assertNotEqual(self.st(fighter)[1], 'fight')   # colons : aucun tir sans provocation (LK06-T01)
        # Coup du joueur sur l'ouvrier, encore en bonne santé : appel à l'aide (alerte, cri), le combattant défend.
        raised = self.ev('LivingKnox.Alert.stats.raised')
        self.assertTrue(self.hit_by(worker))
        self.assertEqual(self.ev(f'{self.De}.stats.helpCalls'), 1)
        # Alerte déjà levée pour un intrus (le joueur vu) : le coup la rend plus grave (« escalated »), d'où un cri.
        self.assertEqual(self.ev('LivingKnox.Alert.stats.raised'), raised)
        self.assertEqual(self.ev('LivingKnox.Alert.stats.escalated'), 1)
        self.assertEqual(self.ev(f'LivingKnox.Alert.get("{gid}").kind'), 'hostile')
        self.assertTrue(any('calls for help against player A' in line for line in self.lk()), self.lk())
        self.dpass(2)
        rule, b, why = self.st(fighter)
        self.assertEqual((rule, b), ('threat', 'fight'))
        self.assertIn('attack player A', why)
        self.assertIn('(help)', why)
        self.assertEqual(self.ev(f'{C}.get("{fighter}").u'), 'A')
        self.assertNotEqual(self.st(worker)[1], 'surrender')
        # Blessé sous 60 % puis frappé encore : il se rend (arrêt, regard, mains levées) ; le groupe épargne le joueur.
        self.update(gid, 'g.members["m-2"].wound = 50')
        self.assertTrue(self.hit_by(worker))
        self.dpass(3)
        rule, b, why = self.st(worker)
        self.assertEqual((rule, b), ('threat', 'surrender'))
        self.assertIn('hit by A', why)
        self.assertEqual(self.ev(f'LivingKnox.Anim.gestureOf("{worker}")'), 'surrender')
        self.assertEqual(self.ev(f'{self.De}.spared("{gid}", "A", {self.De}.currentMinute())'), True)
        self.assertNotEqual(self.st(fighter)[1], 'fight')
        self.assertIsNone(self.ev(f'{C}.get("{fighter}")'))
        self.assertTrue(any(f'{worker} ({gid} m-2) surrenders to A' in line for line in self.lk()), self.lk())
        # Le joueur frappe encore : reddition rompue, plus de reddition à ce joueur, le combattant défend de nouveau.
        self.assertTrue(self.hit_by(worker))
        self.assertEqual(self.ev(f'{self.De}.stats.surrenderBroken'), 1)
        self.dpass(3)
        self.assertNotEqual(self.st(worker)[1], 'surrender')
        self.assertNotEqual(self.ev(f'LivingKnox.Anim.gestureOf("{worker}")'), 'surrender')
        self.assertEqual(self.st(fighter)[1], 'fight')
        self.assertEqual(self.ev(f'{C}.get("{fighter}").u'), 'A')
        # Aide expirée (3 minutes) et joueur jamais vu par le combattant : fin du combat.
        self.h.advance(4)
        self.dpass(3)
        self.assertNotEqual(self.st(fighter)[1], 'fight')
        self.assertEqual(self.h.errors(self.srv), [])
        for c in (() if self.mode == 'solo' else ('A', 'B')):
            self.assertEqual(self.h.errors(c), [])

    def test_wounded_fighter_retreats_home_and_hands_over_its_target(self):
        gid = self.mk_crew('brawlers', [('fighter', 'thug'), ('fighter', 'thug'), ('worker', 'cook')])
        first, second = self.npc_of(gid, 'm-1'), self.npc_of(gid, 'm-2')
        self.place(first, 92.5, 110.5)                     # à 17 cases du foyer (110, 110)
        self.place(second, 96.5, 110.5)
        self.h.move_player('A', 88.5, 110.5)
        self.run_lua(f'SEE_PLAYER("{first}", "A", 88, 110, 4)')
        self.dpass(2)
        self.assertEqual(self.st(first)[1], 'fight')
        self.assertNotEqual(self.st(second)[1], 'fight')   # ne voit pas le joueur
        # Blessure à 70 (santé 30 % < 35 %) : retraite au foyer en courant, mêlée finie, cible passée au second.
        self.update(gid, 'g.members["m-1"].wound = 70')
        self.dpass(2)
        rule, b, why = self.st(first)
        self.assertEqual((rule, b), ('threat', 'retreat'))
        self.assertIn('health 30% < 35%, back home', why)
        self.assertIsNone(self.ev(f'{C}.get("{first}")'))
        op, gait, x = self.run_lua(f'local e = DIRECTIVE("{gid}", "m-1") return e.op, e.g, e.x')
        self.assertEqual((op, gait), ('move', 'run'))
        self.assertGreater(x, 100)                         # vers le foyer, à l'est
        self.assertEqual(self.ev(f'{self.De}.stats.retreats'), 1)
        self.assertTrue(any('calls for help against player A' in line and '(retreat)' in line for line in self.lk()),
                        self.lk())
        self.dpass(2)
        self.assertEqual(self.st(second)[1], 'fight')
        self.assertIn('(help)', self.st(second)[2])
        # Moral du groupe bas (20) : blessure 55 (santé 45 %) suffit au second pour se retirer.
        self.update(gid, 'g.morale = 20 g.members["m-2"].wound = 55')
        self.dpass(2)
        rule, b, why = self.st(second)
        self.assertEqual(b, 'retreat')
        self.assertIn('group morale 20', why)
        self.assertEqual(self.h.errors(self.srv), [])

    def test_health_hook_and_sources(self):
        health = (LUA / 'server' / 'LivingKnox' / 'LK_Health.lua').read_text(encoding='utf-8')
        self.assertIn('De.noteHit(id, z, wielder)', health)
        # Un client MP n'a pas de cadre de décision : aucun coup noté chez lui.
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Decisions'))


class SoloDefenceStackTests(DefenceStackTests):
    mode = 'solo'

    test_health_hook_and_sources = None

    def test_suite_lk_retreat_is_listed_and_ascii(self):
        suite = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKRetreat.lua'
        self.assertTrue(all(b < 128 for b in suite.read_bytes()), 'non ASCII byte in the suite')
        self.h.load('solo', 'shared/RST/suites/RST_LKRetreat.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.retreat", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.retreat')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)


def _retreat_suite_base():
    """Banc de la suite lk.alert (maison, perception, horloge ; import tardif), complété du combat et de la santé."""
    import test_lk_alert as tla
    return tla.SuiteTests


class RetreatSuiteTests(_retreat_suite_base()):
    test_suite_lk_alert_passes_on_the_doubles = None   # jouée par test_lk_alert.py

    def make(self, root=None):
        from test_lk_zombies import HEALTH, HEALTH_CLIENT, ZOMBIE_DOUBLES
        h = super().make(root)
        from test_lk_contest import SPEECH_DOUBLE   # LK06-T12 : répliques de reddition notées (auditeur fictif)
        for f in (COMBAT_DOUBLES, RANGED_DOUBLES, ZOMBIE_DOUBLES, HEALTH, COMBAT, COMBAT_CLIENT, HEALTH_CLIENT,
                  SPEECH_DOUBLE):
            h.load('solo', f)
        return h

    def test_suite_lk_retreat_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.h.move_player('A', 110, 110)
        self.h.load('solo', 'shared/RST/suites/RST_LKRetreat.lua')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.retreat", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(4000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            # Une minute de jeu toutes les 25 images (2,9 s : 2,5 s en jeu par défaut). LK13-T11 : membres d'un passage
            # évalués sur des images successives ; à 20 images (2,3 s), la reddition « hors de vue » du doublé (joueur non
            # perçu, SURRENDER.LINGER = 2 minutes) finissait avant le contrôle à 5 s de la suite.
            if i % 25 == 24:
                self.h.advance(1)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKT' in x][-20:]))
        logs = self.h.logs('solo')
        for text in ('[LKT] measure help: fighter', '[LKT] measure surrender:', '[LKT] measure broken surrender:',
                     '[LKT] measure retreat: fighter', '[LKT] measure surrender line: 1 said, 0 betrayal line(s), '
                     'gesture surrender', '[LKT] measure betrayal: 1 line(s), gesture'):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)   # groupe de test retiré
        self.assertEqual(self.h.errors('solo'), [])


if __name__ == '__main__':
    unittest.main()
