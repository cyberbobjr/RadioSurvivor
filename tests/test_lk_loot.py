"""Tests hors jeu du butin réel du cadavre des PNJ Living Knox (LK07-T05) : server/LivingKnox/LK_Loot.lua (autorité),
LK_Ammo.setLoaded / addReserve / unload, branchement dans LK_Bodies.onZombieDead.

    python RadioSurvivor/tests/test_lk_loot.py

Banc tests/harness.py (serveur dédié et deux clients, ou solo), pile des corps, rapports, armes et groupes (banc
ReleaseBase de test_lk_reports.py), santé et mort (test_lk_health.py, test_lk_death.py), munitions (RANGED_DOUBLES de
test_lk_combat.py), complétée des doublures ci-dessous, qui reproduisent le Java 42.21.0 relevé et NE PROUVENT PAS
l'API réelle :
- cadavre (IsoDeadBody.java:323-335) : conteneur = inventaire du mort, inventaire neuf pour le zombie ; objets
  accrochés repris ; setAttachedItems (565-585) n'ajoute au conteneur un objet accroché absent qu'en solo (jamais sur
  un serveur) ; objets en main jamais repris ;
- reanimate (IsoDeadBody.java:1850-1858) : le zombie reprend le conteneur et les objets accrochés du cadavre ;
- contenu reçu par chaque client (IsoDeadBody.writeInventory, 2345-2376) : objets du conteneur, objets accrochés
  présents dans le conteneur seulement (indexOf, -1 sinon : perdu à la relecture, 793) ;
- OnCreate du script appelé par instanceItem (InventoryItem.initialiseItem, 4022-4027), aucun en vanilla pour les
  armes et chargeurs du banc (LK07-T07 : crochet de remplacement d'un autre mod reproduit par hook_creation).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_reports import ReleaseBase  # noqa: E402
from test_lk_health import HEALTH, HEALTH_CLIENT, HEALTH_DOUBLES  # noqa: E402
from test_lk_death import DEATH_DOUBLES  # noqa: E402
from test_lk_combat import RANGED_DOUBLES, AMMO  # noqa: E402

LOOT = 'server/LivingKnox/LK_Loot.lua'
SUITE = 'shared/RST/suites/RST_LKLoot.lua'
SUITE_FILE = DEV_LUA / SUITE
L = 'LivingKnox.Loot'

LOOT_DOUBLES = r'''
local H = HARNESS
local MODE = H.mode
local C = H.classes
local Z = C.IsoZombie
local Item = C.InventoryItem
local W = C.HandWeapon
function W:isExplosive() return false end
STATS['Base.Shotgun'] = { max = 2, range = 20, crit = 2 }
for _, t in ipairs({ 'Base.Notepad', 'Base.Pencil', 'Base.Lighter', 'Base.Bandage', 'Base.Chocolate', 'Base.Map',
    'Base.HandTorch', 'Base.GranolaBar', 'Base.AlcoholWipes', 'Base.Tweezers', 'Base.Nails', 'Base.Screwdriver',
    'Base.DuctTape', 'Base.Matches' }) do ITEMS[t] = { cls = Item } end
local prevInstance = instanceItem
instanceItem = function(t)
    local it = prevInstance(t)
    if it ~= nil then it.fullType = it.t end   -- doublures de santé : HandWeapon lu par fullType
    return it
end
-- LK07-T07 : OnCreate du script de l'objet, appelé par instanceItem avec l'objet (Item.InstanceItem ->
-- InventoryItem.initialiseItem, InventoryItem.java:4022-4027 ; Item.getLuaCreate, Item.java:3907-3908). Aucun OnCreate
-- vanilla pour Base.Pistol (weapon.txt:10996-11077) ni Base.9mmClip (normal.txt:13796-13808) : ON_CREATE[t] = nom
-- d'une fonction globale posée par un autre mod (ScriptItem.setLuaCreate).
ON_CREATE = {}
local instanceNoCreate = instanceItem
instanceItem = function(t)
    local it = instanceNoCreate(t)
    local name = ON_CREATE[t]
    if it ~= nil and name ~= nil and type(_G[name]) == 'function' then _G[name](it) end
    return it
end
local ScriptItem = H.class('ScriptItemDouble')
function ScriptItem:getLuaCreate() return ON_CREATE[self.t] end
function ScriptItem:setLuaCreate(name) ON_CREATE[self.t] = name end   -- Item.setLuaCreate (RST_GunSwap.lua)
local Scripts = H.class('ScriptManagerDouble')
function Scripts:FindItem(t) return setmetatable({ t = t }, ScriptItem) end
local SCRIPTS = setmetatable({}, Scripts)
getScriptManager = function() return SCRIPTS end
local function holds(inv, it)
    for _, v in ipairs(inv:getItems().items) do if v == it then return true end end
    return false
end
-- Cadavre : conteneur et objets accrochés du mort (IsoDeadBody.java:323-335, 565-585).
local Body = C.IsoDeadBody
local rawCreate = C.IsoGridSquare.createCorpse
function C.IsoGridSquare:createCorpse(arg)
    if type(arg) == 'boolean' then return rawCreate(self, arg) end
    local inv = arg:getInventory()
    local att = {}
    for loc, it in pairs(rawget(arg, 'att') or {}) do att[loc] = it end
    local body = rawCreate(self, arg)
    body.container, body.att = inv, att
    rawset(inv, 'parent', body)                       -- ItemContainer.getParent : le cadavre
    arg.inv, arg.att = nil, nil                       -- setInventory(new ItemContainer), clearAttachedItems
    if MODE == 'solo' then
        for _, it in pairs(att) do if not holds(inv, it) then inv:AddItem(it) end end
    end
    return body
end
function Body:getContainer() return self.container end
-- Objets au sol d'une case (IsoGridSquare.getWorldObjects) : rien n'est posé au sol dans ces doublures.
if C.IsoGridSquare.getWorldObjects == nil then
    function C.IsoGridSquare:getWorldObjects() return H.list() end
end
local AttachedView = H.class('AttachedItems')
function AttachedView:getItem(loc) return self.slots[loc] end
function AttachedView:getLocation(it)
    for loc, v in pairs(self.slots) do if v == it then return loc end end
    return nil
end
function AttachedView:setItem(loc, it) self.slots[loc] = it end
if C.ItemContainer.getParent == nil then
    function C.ItemContainer:getParent() return rawget(self, 'parent') end
end
-- Arme du mod de test (RST_TestGuns.txt) : copie du pistolet vanilla (RST_GunSwap.lua, LK07-T07).
ITEMS['RSTGuns.TestPistol'] = ITEMS['Base.Pistol']
if C.InventoryItem.getContainer == nil then
    function C.InventoryItem:getContainer() return rawget(self, 'container') end
end
function Body:getAttachedItems() return setmetatable({ slots = self.att or {} }, AttachedView) end
-- ItemContainer:contains(objet) (ItemContainer.java) : inventaires de joueur (table) et de zombie (liste).
function C.ItemContainer:contains(it)
    local arr = self.items.items or self.items
    for _, v in ipairs(arr) do if v == it then return true end end
    return false
end
local rawReanimate = Body.reanimate
function Body:reanimate()
    local inv, att = self.container, self.att
    local zb = rawReanimate(self)
    if zb ~= nil then
        zb.inv, zb.att = inv, att                      -- IsoDeadBody.java:1850-1858
        self.container, self.att = nil, nil
    end
    return zb
end
-- Contenu reçu par chaque client (writeInventory) : objets du conteneur triés (type, cartouches d'un chargeur), puis
-- emplacements accrochés dont l'objet est dans le conteneur.
function CORPSE_CONTENT(body)
    local out = {}
    for _, it in ipairs(body.container:getItems().items) do
        local n = rawget(it, 'ammo')
        out[#out + 1] = it:getFullType() .. (n and ('#' .. n) or '')
    end
    table.sort(out)
    local slots = {}
    for loc, it in pairs(body.att or {}) do
        if holds(body.container, it) then slots[#slots + 1] = '@' .. loc .. '=' .. it:getFullType() end
    end
    table.sort(slots)
    for _, s in ipairs(slots) do out[#out + 1] = s end
    return table.concat(out, ',')
end
function INV_CONTENT(zb)
    local out = {}
    for _, it in ipairs(zb:getInventory():getItems().items) do
        local n = rawget(it, 'ammo')
        out[#out + 1] = it:getFullType() .. (n and ('#' .. n) or '')
    end
    table.sort(out)
    return table.concat(out, ',')
end
'''


class LootBase(ReleaseBase):
    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, HEALTH_DOUBLES)
            h.load(m, HEALTH)
            if m != 'server':
                h.load(m, HEALTH_CLIENT)
            h.load(m, DEATH_DOUBLES)
            h.load(m, 'RANGES = RANGES or {}')
            h.load(m, RANGED_DOUBLES)
            h.load(m, LOOT_DOUBLES)
            h.load(m, AMMO)
            h.load(m, LOOT)
        return h

    def lo(self, code, m=None):
        return self.ev(f'{L}.' + code, m)

    def body(self):
        return f'LivingKnox.Bodies.bound["lk-1"]'

    def armed(self, weapon, group_role=None, ammo=None):
        """PNJ lk-1 incarné, arme du registre, membre d'un groupe settlers (rôle) ; un passage de butin."""
        zid = self.npc()
        if group_role:
            gid, mid = self.run_lua('local G = LivingKnox.Groups '
                                    'local g = assert(G.create({ type = "settlers", name = "Mill", day = 1 })) '
                                    f'return g.id, assert(G.addMember(g.id, {{ role = "{group_role}", npc = "lk-1", '
                                    'day = 1 }))')
            if ammo is not None:
                self.run_lua(f'assert(LivingKnox.Groups.setNeed("{gid}", "ammo", {ammo}))')
        if weapon:
            self.assertEqual(lua_list(self.ev(f'{{ LivingKnox.Equipment.setWeapon("lk-1", "{weapon}") }}')), [True])
        self.h.advance_ms(self.ev('LivingKnox.Config.LOOT.EVERY_MS'))
        self.h.tick(1)
        return zid

    def kill(self):
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Health.kill("lk-1") }')), [True])
        self.h.tick(2)
        return self.ev('LAST_CORPSE()')

    def content(self):
        return self.ev('CORPSE_CONTENT(LAST_CORPSE())')

    def inv(self):
        return self.ev(f'INV_CONTENT({self.body()})')


class MultiplayerLootTests(LootBase):
    def test_built_once_from_the_group_ammo_level_and_the_role(self):
        self.armed('Base.Pistol', 'worker', ammo=60)
        self.assertEqual(self.lo('stats.built'), 1)
        # Niveau 60 : 9 cartouches sur 15 dans l'arme, 1 chargeur plein (2 x 0,6 arrondi), poches d'un ouvrier.
        self.assertEqual(self.ev(f'LivingKnox.Ammo.loaded({self.body()}, "Base.Pistol")'), 9)
        self.assertEqual(self.inv(), 'Base.9mmClip#15,Base.Nails,Base.Nails,Base.Nails,Base.Nails,Base.Nails,'
                                     'Base.Screwdriver')
        before = self.inv()
        for _ in range(3):
            self.h.advance_ms(2000)
            self.h.tick(1)
        self.assertEqual(lua_list(self.ev(f'{{ {L}.build("lk-1", {self.body()}) }}')), [False, 'already built'])
        self.assertEqual(self.lo('stats.built'), 1)
        self.assertEqual(self.inv(), before)
        self.assertTrue(any('npc lk-1 loot built: Base.Pistol: 9 loaded, 1 magazine(s), 0 loose round(s) (ammo '
                            'level 60); 6 pocket item(s) of a worker' in line for line in self.lk()), self.lk())
        # Corps relu de reanimated.bin : marque gardée, jamais rempli de nouveau.
        self.run_lua('SAVED = SAVE_REANIMATED(); local z = LivingKnox.Bodies.bound["lk-1"]; '
                     'z:removeFromWorld(); LivingKnox.Bodies.bound["lk-1"] = nil; LOAD_REANIMATED(SAVED)')
        self.ev('LivingKnox.Bodies.scanAll()')
        self.assertIsNotNone(self.ev(self.body()))
        self.h.advance_ms(2000)
        self.h.tick(1)
        self.assertEqual(self.lo('stats.built'), 1)

    def test_server_corpse_keeps_the_weapon_attached_and_in_its_container(self):
        self.armed('Base.Pistol', 'worker', ammo=60)
        self.h.tick(15)                                       # passage du serveur : pistolet accroché sur sa copie
        self.assertEqual(self.ev(f'{self.body()}:getAttachedItem("Holster Right"):getFullType()'), 'Base.Pistol')
        self.kill()
        self.assertEqual(self.content(), 'Base.9mmClip#15,Base.9mmClip#9,Base.Nails,Base.Nails,Base.Nails,'
                                         'Base.Nails,Base.Nails,Base.Pistol,Base.Screwdriver,'
                                         '@Holster Right=Base.Pistol')
        self.assertEqual((self.lo('stats.weaponsKept'), self.lo('stats.weaponsCreated'), self.lo('stats.unloaded')),
                         (1, 0, 9))
        self.assertIsNone(self.ev('LAST_CORPSE():getModData().LKAmmo'))
        self.assertIs(self.ev('LAST_CORPSE():getModData().LKLootDead'), True)
        self.assertEqual(self.h.errors('server'), [])

    def test_without_the_loot_module_the_attached_weapon_never_reaches_the_clients(self):
        """Témoin du fait du moteur : un objet accroché absent du conteneur est perdu sur un serveur."""
        self.armed('Base.Pistol')
        self.h.tick(15)
        self.run_lua('LivingKnox.Loot.onDeath = function() return false end')
        self.kill()
        self.assertNotIn('Base.Pistol', self.content())

    def test_weapon_created_and_loot_built_at_death_before_any_pass(self):
        self.npc()
        self.run_lua('LivingKnox.Equipment.setWeapon("lk-1", "Base.Shotgun")')
        self.run_lua(f'{self.body()}:setAttachedItem("Rifle On Back", nil)')   # objet accroché pas encore posé
        self.assertEqual(self.lo('stats.built'), 0)
        self.kill()
        # Sans groupe : niveau 50, fusil à pompe de 5 : 3 dans l'arme, 6 cartouches libres de réserve.
        self.assertEqual(self.content(), ','.join(['Base.Shotgun'] + ['Base.ShotgunShells'] * 9)
                         + ',@Rifle On Back=Base.Shotgun')
        self.assertEqual((self.lo('stats.built'), self.lo('stats.weaponsCreated')), (1, 1))

    def test_dragged_corpse_dropped_no_duplicate(self):
        self.armed('Base.Pistol', 'medic', ammo=100)
        self.h.tick(15)
        self.kill()
        first = self.content()
        self.run_lua('DRAGGED = DRAG(LAST_CORPSE())')
        self.ev('LivingKnox.Bodies.scanAll()')
        self.h.advance_ms(2000)
        self.h.tick(1)
        self.run_lua('LET_GO(DRAGGED)')
        self.assertEqual(self.content(), first)
        self.assertEqual((self.lo('stats.deaths'), self.lo('stats.built')), (1, 1))
        self.assertEqual(first.count('Base.Pistol'), 2)       # un objet, plus son emplacement accroché

    def test_new_incarnation_gets_its_own_loot(self):
        self.armed('Base.Pistol', 'scout', ammo=0)
        self.assertEqual(self.inv(), 'Base.GranolaBar,Base.HandTorch,Base.Map')   # niveau 0 : aucune munition
        self.assertEqual(self.ev(f'LivingKnox.Ammo.loaded({self.body()}, "Base.Pistol")'), 0)
        self.assertEqual(lua_list(self.ev('{ LivingKnox.Bodies.release("lk-1", "test") }'))[0], True)
        self.assertIsNotNone(self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)'))
        self.h.advance_ms(2000)
        self.h.tick(1)
        self.assertEqual(self.lo('stats.built'), 2)
        self.assertEqual(self.inv(), 'Base.GranolaBar,Base.HandTorch,Base.Map')

    def test_mission_items_point_checked(self):
        self.run_lua('LivingKnox.Loot.missionItems = function(id, info) MISSION_INFO = info return { '
                     '{ t = "Base.Notepad", n = 9 }, { t = "bad type", n = 1 }, { t = "Base.Nothing", n = 2 }, '
                     '{ t = "Base.Lighter" } } end')
        self.armed(None, 'deputy')
        self.assertEqual(self.inv(), ','.join(['Base.Lighter', 'Base.Notepad'] + ['Base.Notepad'] * 5
                                              + ['Base.Pencil']))
        self.assertEqual(self.ev('MISSION_INFO.role'), 'deputy')
        self.assertEqual(self.lo('stats.missions'), 5)
        lines = self.lk()
        self.assertTrue(any('loot item type bad type refused' in line for line in lines), lines)
        self.assertTrue(any('loot item Base.Nothing is unknown to the game' in line for line in lines), lines)

    def test_clients_stop_at_the_guard(self):
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Loot'))


class SoloLootTests(LootBase):
    mode = 'solo'

    def test_weapon_in_hand_at_death_kept_once_and_attached(self):
        self.armed('Base.Pistol', 'worker', ammo=60)
        self.run_lua('LivingKnox.Anim.setGesture("lk-1", "aim")')
        self.h.tick(6)
        self.assertEqual(self.ev(f'{self.body()}:getPrimaryHandItem():getFullType()'), 'Base.Pistol')
        self.assertIsNone(self.ev(f'{self.body()}:getAttachedItem("Holster Right")'))
        self.kill()
        # Même contenu que le cadavre serveur (test_server_corpse_keeps_the_weapon_attached_and_in_its_container).
        self.assertEqual(self.content(), 'Base.9mmClip#15,Base.9mmClip#9,Base.Nails,Base.Nails,Base.Nails,'
                                         'Base.Nails,Base.Nails,Base.Pistol,Base.Screwdriver,'
                                         '@Holster Right=Base.Pistol')
        self.assertEqual(self.lo('stats.weaponsKept'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_attached_weapon_not_doubled_by_the_solo_corpse(self):
        self.armed('Base.HandAxe', 'breaker')
        self.h.tick(6)
        self.assertEqual(self.ev(f'{self.body()}:getAttachedItem("Belt Left"):getFullType()'), 'Base.HandAxe')
        self.kill()
        self.assertEqual(self.content(), 'Base.DuctTape,Base.HandAxe,Base.Matches,@Belt Left=Base.HandAxe')

    def hook_creation(self, switches=False):
        """LK07-T07 : crochet de création d'un autre mod, tel que relevé en lecture seule dans le mod d'armes actif
        lors du constat en jeu (OnCreate posé sur les armes à feu et chargeurs vanilla par une option sandbox active
        par défaut) : l'objet créé est noté, puis remplacé (AddItem du nouveau, DoRemoveItem de l'ancien) à un OnTick
        suivant, dès qu'il est dans un conteneur qui n'est l'inventaire d'aucun zombie (cadavre compris). switches : le
        remplacement suit, comme le mod relevé, ses interrupteurs SandboxVars.MarzGuns lus à la création de l'objet
        (et l'arme de remplacement est une arme à feu)."""
        if switches:
            self.run_lua('SandboxVars = SandboxVars or {} SandboxVars.MarzGuns = { VanillaWeaponReplacement = true, '
                         'VanillaAmmoReplacement = true, VanillaAttachmentReplacement = true }')
        self.run_lua(r'''
local C = HARNESS.classes
for _, t in ipairs({ 'Base.ModPistol', 'Base.ModClip' }) do ITEMS[t] = { cls = C.InventoryItem } end
MOD_TYPES = { ['Base.Pistol'] = 'Base.ModPistol', ['Base.9mmClip'] = 'Base.ModClip' }
MOD_PENDING, MOD_SWAPPED = {}, 0
function MOD_REPLACE(it)
    local v = SandboxVars and SandboxVars.MarzGuns
    if v ~= nil and not v.VanillaWeaponReplacement then return end   -- interrupteur lu à la création
    MOD_PENDING[#MOD_PENDING + 1] = it
end
if SandboxVars and SandboxVars.MarzGuns then ITEMS['Base.ModPistol'] = ITEMS['Base.Pistol'] end
ON_CREATE['Base.Pistol'], ON_CREATE['Base.9mmClip'] = 'MOD_REPLACE', 'MOD_REPLACE'
local function zombieInventory(ct)
    for _, zb in ipairs(HARNESS.zombieList.items) do if rawget(zb, 'inv') == ct then return true end end
    return false
end
Events.OnTick.Add(function()
    local keep = {}
    for _, it in ipairs(MOD_PENDING) do
        local ct = rawget(it, 'container')
        if ct ~= nil and not zombieInventory(ct) then
            ct:AddItem(instanceItem(MOD_TYPES[it:getFullType()]))
            ct:DoRemoveItem(it)
            MOD_SWAPPED = MOD_SWAPPED + 1
        else
            keep[#keep + 1] = it
        end
    end
    MOD_PENDING = keep
end)''')

    def test_creation_hook_of_another_mod_swaps_the_death_loot_in_the_corpse(self):
        """Reproduit le constat en jeu du 2026-10-12 : journal « weapon Base.Pistol (created) … 15 item(s) in the
        corpse », mais ni pistolet ni chargeur dans le cadavre, poches présentes. Sans le crochet (tests ci-dessus),
        même chemin de mort : tout y est."""
        self.hook_creation()
        self.armed('Base.Pistol', 'medic', ammo=50)
        corpse = self.kill()
        self.assertIsNotNone(corpse)
        self.assertTrue(any('death loot: weapon Base.Pistol' in line for line in self.lk()), self.lk())
        self.h.tick(2)
        content = self.content()
        self.assertNotIn('Base.Pistol', content)
        self.assertNotIn('Base.9mmClip', content)
        self.assertEqual(content.count('Base.Bandage'), 2)
        self.assertIn('Base.ModPistol', content)
        self.assertEqual(content.count('Base.ModClip'), 2)            # chargeur de réserve et chargeur engagé
        self.assertEqual(self.ev('MOD_SWAPPED'), 3)

    def run_suite(self, count=3, nmeasures=2):
        self.init()
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.loot", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.loot')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.loot", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(6000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(50)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), count, results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKL] measure')]
        self.assertEqual(len(measures), nmeasures, measures)
        return report, results, measures

    def test_suite_lk_loot_passes_on_the_doubles(self):
        # 2026-10-15 : sans mod d'armes installé, le remplacement du mod de test (RST_GunSwap.lua) joue son rôle.
        report, results, measures = self.run_suite(nmeasures=5)
        self.assertTrue(report.ok, results)
        self.assertEqual([r[1] for r in results], ['PASS', 'PASS', 'PASS'], results)
        swap = [m for m in measures if 'test swap:' in m][0]
        self.assertIn('swapped 1', swap)
        self.assertIn('pistols left 0, swapped guns 1', swap)
        self.assertIsNone(self.ev('ON_CREATE["Base.Pistol"]'))      # crochet retiré après le test
        death = [m for m in measures if 'measure death' in m][0]
        self.assertIn('creation hooks none', death)
        self.assertIn('corpse content: Base.9mmClip x2, Base.AlcoholWipes x1, Base.Bandage x2, Base.Pistol x1, '
                      'Base.Tweezers x1', death)

    def test_suite_skips_the_death_check_when_creation_is_hooked(self):
        """LK07-T07 : avec le crochet de création d'un autre mod, la mesure nomme le crochet et le contenu réel du
        cadavre, et le test de mort est SKIP (au lieu d'un FAIL trompeur)."""
        self.hook_creation()
        report, results, measures = self.run_suite(nmeasures=5)
        self.assertTrue(report.ok, results)
        self.assertEqual(results[0][1], 'PASS', results)
        self.assertEqual(results[1][1], 'SKIP', results)
        self.assertEqual(self.ev('ON_CREATE["Base.Pistol"]'), 'MOD_REPLACE')   # crochet du mod rendu après le test
        self.assertIn('Base.Pistol=MOD_REPLACE Base.9mmClip=MOD_REPLACE', results[1][2])
        death = [m for m in measures if 'measure death' in m][0]
        self.assertIn('pistols in the corpse 0', death)
        self.assertIn('creation hooks Base.Pistol=MOD_REPLACE Base.9mmClip=MOD_REPLACE', death)
        self.assertIn('Base.ModPistol x1', death)

    def test_suite_turns_the_known_swap_off_for_the_death_check_and_checks_it_on(self):
        """LK07-T07 : interrupteurs du mod d'armes connu coupés pour le test de mort (le butin vanilla reste), puis
        remis : avec le remplacement actif, le cadavre garde une arme à feu (celle du mod)."""
        self.hook_creation(switches=True)
        report, results, measures = self.run_suite(nmeasures=4)
        self.assertTrue(report.ok, results)
        self.assertEqual([r[1] for r in results], ['PASS', 'PASS', 'PASS'], results)
        self.assertTrue(any('swap switches on: switched off for the test' in m for m in measures), measures)
        death = [m for m in measures if 'measure death' in m][0]
        self.assertIn('pistols in the corpse 1', death)
        swap = [m for m in measures if 'swap on:' in m][0]
        self.assertIn('firearms in the corpse 1', swap)
        self.assertIn('Base.ModPistol x1', swap)
        self.assertIs(self.ev('SandboxVars.MarzGuns.VanillaWeaponReplacement'), True)


class SourceTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)

    def test_mod_sources_are_kahlua_safe(self):
        for rel in (LOOT, AMMO, 'server/LivingKnox/LK_Bodies.lua'):
            raw = (LUA / rel).read_bytes()
            code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('utf-8'), flags=re.S))
            self.assertTrue(all(ord(ch) < 128 for ch in code), rel)
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.'):
                self.assertIsNone(re.search(pattern, code), (rel, pattern))

    def test_pocket_items_are_vanilla_items(self):
        """Chaque objet de poche existe dans les scripts vanilla installés (lecture seule)."""
        scripts = pz_paths.media_dir() / 'scripts/generated/items'
        if not scripts.exists():
            self.skipTest('vanilla scripts not installed')
        text = '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in scripts.glob('*.txt'))
        code = (LUA / LOOT).read_text(encoding='utf-8')
        types = set(re.findall(r't = "Base\.(\w+)"', code))
        self.assertGreater(len(types), 10)
        for t in sorted(types):
            self.assertRegex(text, r'(?m)^\s*item ' + t + r'\s*$', t)


if __name__ == '__main__':
    unittest.main()
