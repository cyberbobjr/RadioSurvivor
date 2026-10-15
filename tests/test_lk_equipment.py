"""Tests hors jeu de l'arme visible des corps de PNJ Living Knox (LK02-T06) : LK_Equipment.lua.

    python RadioSurvivor/tests/test_lk_equipment.py

Banc tests/harness.py et doublures de tests/test_lk_bodies.py, test_lk_guard.py et test_lk_anim.py, complétées ici.
Les doublures reproduisent le Java et le Lua vanilla 42.21.0 relevés ; elles NE PROUVENT PAS l'API réelle, seulement
la logique du mod :
- objets : instanceItem (LuaManager.java:4669-4677, nil pour un type inconnu), HandWeapon, getAttachmentType,
  isTwoHandWeapon, isRequiresEquippedBothHands, getSwingAnim, isRanged ; catalogue repris de
  media/scripts/generated/items/weapon.txt (Shotgun Rifle / deux mains, Pistol Holster, BaseballBat Shovel / deux
  mains, HandAxe Hammer, KitchenKnife Knife Stab) ;
- objets accrochés : setAttachedItem / getAttachedItem (IsoGameCharacter.java:3178-3206), emplacement contrôlé par le
  groupe Human (AttachedItems.checkValid, AttachedLocations.lua) ; aucun paquet pour un zombie ;
- mains : setPrimaryHandItem / setSecondaryHandItem (IsoGameCharacter.java:2986-3024, 3361-3375) : rien si inchangé,
  OnEquipPrimary / OnEquipSecondary déclenchés pour tout personnage, puis variable Weapon d'après
  WeaponType.getWeaponType(chr, main1, main2) (WeaponType.java:75-108 : firearm / 2handed seulement si les deux mains
  tiennent le même objet) ; SUR LE SERVEUR, l'objet en main d'un zombie lève une exception (envoi Equip typé joueur,
  base zombies-as-npc-bodies.md) : la doublure échoue aussitôt ;
- abonné vanilla de la pêche (media/lua/client/Fishing/FishingHandler.lua:15-38) chargé sur les clients et en solo
  seulement, inscrit par référence ; handleFishing appelle getPlayerNum / getUsername, absents d'un zombie ;
  isLocal (IsoGameCharacter.java:13594, NetworkComponent.java:19) : vrai en solo, vrai chez le client propriétaire ;
- sendAttachedItem (LuaManager.java:9719-9724) : serveur seulement ; RECEIVE_ATTACHED reproduit
  GameCharacterAttachedItemPacket.processClient (objet rechargé = nouvel objet, posé sur le zombie de cet onlineId) :
  un client sans copie à l'envoi ne reçoit rien ;
- getAnimationDebug : nœud choisi parmi ceux de tools/anim_table.json (état idle, toutes conditions vraies, plus
  grand nombre de conditions), pour faire tourner la suite lk.equipment sur les doublures.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list, LUA, DEV_LUA, ROOT  # noqa: E402
from test_lk_anim import AnimBase  # noqa: E402
from harness import HarnessError  # noqa: E402

EQUIPMENT = 'shared/LivingKnox/LK_Equipment.lua'
MOD_FILES = [LUA / EQUIPMENT, LUA / 'shared' / 'LivingKnox' / 'LK_Identity.lua']
DEV_FILES = [DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKEquipment.lua',
             DEV_LUA / 'client' / 'RST' / 'RST_LKBodiesClient.lua',
             DEV_LUA / 'server' / 'RST' / 'RST_LKBodiesServer.lua']


def idle_nodes_lua() -> str:
    table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
    out = []
    for node in table['nodes']:
        if 'idle' not in node['states']:
            continue
        conds = ', '.join('{ %s, %s }' % (json.dumps(c[0]), json.dumps(c[2])) for c in node['conditions']
                          if c[1] == 'STRING')
        out.append('{ name = %s, conds = { %s } }' % (json.dumps(node['name']), conds))
    return '{ ' + ', '.join(out) + ' }'


EQUIP_DOUBLES = r'''
local H = HARNESS
local MODE = H.mode
local C = H.classes
local Z = C.IsoZombie
EQUIP_CALLS = {}
local function ecall(s) EQUIP_CALLS[#EQUIP_CALLS + 1] = s end
local function name(item) if item == nil then return 'nil' end return item.t end
isMultiplayer = function() return MODE ~= 'solo' end

local Item = H.class('InventoryItem')
local Weapon = H.class('HandWeapon', Item)
function Item:getFullType() return self.t end
function Item:getAttachmentType() return self.at end
function Item:isTwoHandWeapon() return self.two == true end
function Item:isRequiresEquippedBothHands() return self.both == true end
function Item:getSwingAnim() return self.swing or 'Rifle' end  -- Item.java:162
-- ModData d'un objet (InventoryItem.java:414-423) : table créée au premier getModData, hasModData = table non vide.
function Item:getModData()
    local md = rawget(self, '__modData')
    if not md then md = {}; self.__modData = md end
    return md
end
function Item:hasModData()
    local md = rawget(self, '__modData')
    if md == nil then return false end
    for _ in pairs(md) do return true end
    return false
end
function Weapon:isRanged() return self.ranged == true end
ITEMS = {
    ['Base.Shotgun'] = { cls = Weapon, at = 'Rifle', two = true, both = true, ranged = true },
    ['Base.Pistol'] = { cls = Weapon, at = 'Holster', ranged = true, swing = 'Handgun' },
    ['Base.BaseballBat'] = { cls = Weapon, at = 'Shovel', two = true, swing = 'Bat' },
    ['Base.HandAxe'] = { cls = Weapon, at = 'Hammer', swing = 'Bat' },
    ['Base.KitchenKnife'] = { cls = Weapon, at = 'Knife', swing = 'Stab' },
    ['Base.Plank'] = { cls = Weapon, swing = 'Bat' },  -- arme sans AttachmentType (doublure)
    ['Base.Apple'] = { cls = Item },
}
-- Scripts d'objets (ScriptManager.getAllItems, Item.getModuleName/getFullName/isRanged) : une arme à feu d'un mod
-- d'armes simulée par un module autre que Base qui rend le pistolet vanilla (LK02-T13) ; compteur d'erreurs Lua
-- (LuaManager.java:6437-6445).
local ScriptItem = {}
ScriptItem.__index = ScriptItem
function ScriptItem:getModuleName() return self.m end
function ScriptItem:getFullName() return self.n end
function ScriptItem:isRanged() return self.r end
SCRIPT_ITEMS = { setmetatable({ m = "Base", n = "Base.Shotgun", r = true }, ScriptItem),
    setmetatable({ m = "TestGuns", n = "Base.Pistol", r = true }, ScriptItem) }
getScriptManager = function()
    return { getAllItems = function()
        return { size = function() return #SCRIPT_ITEMS end, get = function(_, i) return SCRIPT_ITEMS[i + 1] end }
    end }
end
LUA_ERRORS = {}
getLuaDebuggerErrorCount = function() return #LUA_ERRORS end
getLuaDebuggerErrors = function()
    return { size = function() return #LUA_ERRORS end, get = function(_, i) return LUA_ERRORS[i + 1] end }
end
CREATED = 0
instanceItem = function(t)
    if type(t) ~= 'string' then error('No implementation found for instanceItem with argument ' .. tostring(t), 2) end
    local d = ITEMS[t]
    if not d then return nil end
    CREATED = CREATED + 1
    return setmetatable({ __id = 'item' .. CREATED, t = t, at = d.at, two = d.two, both = d.both, ranged = d.ranged,
        swing = d.swing }, d.cls)
end

local HUMAN = {}
for _, l in ipairs({ 'Rifle On Back', 'Big Weapon On Back', 'Blade On Back', 'Shovel Back', 'Racket On Back',
    'Pan On Back', 'Saucepan Back', 'Guitar', 'Guitar Acoustic', 'Holster Right', 'Holster Left', 'Belt Left Upside',
    'Belt Left', 'Belt Right', 'Belt Rotated Left', 'Nightstick Left', 'Belt Left Screwdriver', 'Wrench Left',
    'MeatCleaver Belt Left' }) do HUMAN[l] = true end
local function slots(self)
    local a = rawget(self, 'att')
    if not a then a = {}; self.att = a end
    return a
end
local function check(loc)
    if type(loc) ~= 'string' then error('No implementation found for setAttachedItem', 3) end
    if not HUMAN[loc] then error('RuntimeException: invalid location ' .. loc, 3) end
end
function Z:getAttachedItem(loc) check(loc) return slots(self)[loc] end
function Z:setAttachedItem(loc, item)
    check(loc)
    ecall('setAttachedItem:' .. loc .. ':' .. name(item))
    slots(self)[loc] = item
end

local function weaponVar(z)  -- WeaponType.getWeaponType(chr, inv1, inv2)
    local a, b = rawget(z, 'primary'), rawget(z, 'secondary')
    if not instanceof(a, 'HandWeapon') then return '' end
    if a:getSwingAnim() == 'Stab' then return 'knife' end
    if not a:isRanged() then
        if a == b and a:isTwoHandWeapon() then return '2handed' end
        return '1handed'
    end
    if a == b and a:isTwoHandWeapon() then return 'firearm' end
    return 'handgun'
end
function Z:getPrimaryHandItem() return rawget(self, 'primary') end
function Z:getSecondaryHandItem() return rawget(self, 'secondary') end
local function hand(self, field, event, item)
    if rawget(self, field) == item then return end
    if MODE == 'server' then error('ClassCastException: IsoZombie cannot be cast to IsoPlayer (Equip packet)', 3) end
    ecall(field .. ':' .. name(item))
    self[field] = item
    triggerEvent(event, self, item)
    self:setVariable('Weapon', weaponVar(self))
end
function Z:setPrimaryHandItem(item) hand(self, 'primary', 'OnEquipPrimary', item) end
function Z:setSecondaryHandItem(item) hand(self, 'secondary', 'OnEquipSecondary', item) end
function Z:isLocal() return MODE == 'solo' or not self:isRemoteZombie() end
function Z:getActionStateName() return 'idle' end

-- getAnimationDebug : nœud de l'état idle (tools/anim_table.json), sinon nœud vanilla.
local NODES = __NODES__
function Z:getAnimationDebug()
    local node = 'ZombieIdle'
    if self:getVariableBoolean('LKActor') then
        local best = -1
        for _, n in ipairs(NODES) do
            local ok = true
            for _, c in ipairs(n.conds) do
                if string.lower(self:getVariableString(c[1])) ~= string.lower(c[2]) then ok = false end
            end
            if ok and #n.conds > best then best, node = #n.conds, n.name end
        end
    end
    return 'zombie\nGameState: ZombieIdleState\nLayer: 0\nState: zombie/idle\n  Node: ' .. node
        .. '\n  AnimTrack:\nVariables:\n'
end

ATTACH_SENT = {}
sendAttachedItem = function(chr, loc, item)
    check(loc)
    if MODE ~= 'server' then return end
    ATTACH_SENT[#ATTACH_SENT + 1] = { o = chr:getOnlineID(), l = loc, t = item and item.t or nil }
end
-- GameCharacterAttachedItemPacket.processClient : objet relu (nouvel objet) et posé sur le zombie de cet onlineId.
function RECEIVE_ATTACHED(o, loc, t)
    local zb = H.zombies[o]
    if zb == nil then return false end
    local item = nil
    if t then item = instanceItem(t) end
    slots(zb)[loc] = item
    return true
end
function WSTATE(zb, loc)
    if zb == nil then return 'nil' end
    local p, s = rawget(zb, 'primary'), rawget(zb, 'secondary')
    local a = loc and slots(zb)[loc] or nil
    local same = (p ~= nil and p == s) and ' same' or ''
    return 'hand=' .. name(p) .. ' second=' .. name(s) .. same .. ' slot=' .. name(a) .. ' Weapon='
        .. zb:getVariableString('Weapon')
end
'''.replace('__NODES__', idle_nodes_lua())

# media/lua/client/Fishing/FishingHandler.lua:1-38 (42.21), chargé après media/lua/shared.
FISHING = r'''
Fishing = Fishing or {}
Fishing.ManagerInstances = {}
Fishing.Handler = {}
FISHING = { calls = 0, players = 0 }
function Fishing.Handler.onEquipPrimary(player, inventoryItem)
    if player:isLocal() then
        Fishing.Handler.handleFishing(player, inventoryItem)
    end
end
Events.OnEquipPrimary.Add(Fishing.Handler.onEquipPrimary)
function Fishing.Handler.handleFishing(player, primaryHandItem)
    FISHING.calls = FISHING.calls + 1
    local playerIndex = isMultiplayer() and player:getUsername() or player:getPlayerNum()
    FISHING.players = FISHING.players + 1
    return playerIndex
end
VANILLA_HANDLE = Fishing.Handler.handleFishing
'''

# Abonnés OnEquipPrimary / OnEquipSecondary relevés en LK02-T13 (docs/conception/equipement.md, « Abonnés d'autres
# mods »). Doublures de COMPORTEMENT, pas des copies :
# - cadre d'armes à feu de la liste de l'utilisateur (fichiers shared, deux abonnés inscrits sur les deux événements) :
#   le personnage n'est testé que contre nil ; seule l'arme est lue et modifiée (ModData, statistiques, sprite) si
#   c'est une arme à distance enregistrée dans le cadre ;
# - vanilla media/lua/client/RadioCom/ISRadioWindow.lua:407-414 : compare au joueur local (getPlayer), rien pour un
#   zombie ;
# - ASSUMES_PLAYER (non inscrit par défaut) : abonné hypothétique d'un mod ajouté plus tard qui suppose un IsoPlayer.
OTHER_SUBSCRIBERS = r'''
local Item = HARNESS.classes.InventoryItem
function Item:getModData()
    local md = rawget(self, '__modData')
    if not md then md = {}; self.__modData = md end
    return md
end
GUNWORKS = { calls = 0, touched = 0, chars = {} }
GUNWORKS_REGISTERED = { ['Base.Shotgun'] = true, ['Base.Pistol'] = true }
local function gunworksOnEquip(chr, weapon)
    GUNWORKS.calls = GUNWORKS.calls + 1
    if not chr or not weapon then return end
    if instanceof(weapon, 'HandWeapon') and weapon:isRanged() and GUNWORKS_REGISTERED[weapon:getFullType()] then
        weapon:getModData().gwRestored = (weapon:getModData().gwRestored or 0) + 1
        GUNWORKS.touched = GUNWORKS.touched + 1
    end
end
Events.OnEquipPrimary.Add(gunworksOnEquip)
Events.OnEquipSecondary.Add(gunworksOnEquip)
local function gunworksCheckStates(chr, weapon)
    if not chr or not weapon then return end
    if instanceof(weapon, 'HandWeapon') and weapon:isRanged() and GUNWORKS_REGISTERED[weapon:getFullType()] then
        weapon:getModData().gwStates = true
    end
end
Events.OnEquipPrimary.Add(gunworksCheckStates)
Events.OnEquipSecondary.Add(gunworksCheckStates)
function ASSUMES_PLAYER(chr, item)
    return chr:getPlayerNum()
end
'''

RADIO_WINDOW = r'''
RADIO_WINDOW = { calls = 0, activated = 0 }
local function radioOnEquip(player, item)
    RADIO_WINDOW.calls = RADIO_WINDOW.calls + 1
    if player == getPlayer() and instanceof(item, 'Radio') then RADIO_WINDOW.activated = RADIO_WINDOW.activated + 1 end
end
Events.OnEquipPrimary.Add(radioOnEquip)
Events.OnEquipSecondary.Add(radioOnEquip)
'''


class EquipBase(AnimBase):
    fishing = True

    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, EQUIP_DOUBLES)
            h.load(m, EQUIPMENT)
            if m != 'server' and self.fishing:
                h.load(m, FISHING)
        return h

    def eq(self, code, m=None):
        return self.ev('LivingKnox.Equipment.' + code, m)

    def weapon(self, item, npc='lk-1', m=None):
        arg = 'nil' if item is None else f'"{item}"'
        return lua_list(self.ev(f'{{ LivingKnox.Equipment.setWeapon("{npc}", {arg}) }}', m))

    def ws(self, m, zid, loc=None):
        arg = 'nil' if loc is None else f'"{loc}"'
        return self.h.eval(m, f'WSTATE(HARNESS.zombies[{zid}], {arg})')

    def ecalls(self, m):
        return lua_list(self.h.eval(m, 'EQUIP_CALLS'))

    def reset_calls(self, m):
        self.h.load(m, 'EQUIP_CALLS = {}')

    def gesture(self, g):
        self.assertIs(self.ev(f'LivingKnox.Anim.setGesture("lk-1", "{g}")'), True)
        if self.mode == 'mp':   # relais des gestes (LK03-T05) : envoi après la fenêtre de regroupement
            window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
            self.h.tick(int(window // self.h.tick_ms) + 2)


class SoloEquipmentTests(EquipBase):
    mode = 'solo'

    def test_attached_at_rest_in_hand_for_gestures_and_attached_again(self):
        zid = self.npc()
        self.assertEqual(self.weapon('Base.Shotgun'), [True])
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].weapon'), 'Base.Shotgun')
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Rifle On Back'),
                         'hand=nil second=nil slot=Base.Shotgun Weapon=')
        self.gesture('aim')
        self.apply()
        # Arme à deux mains : même objet dans les deux mains, sinon WeaponType rendrait handgun.
        self.assertEqual(self.ws('solo', zid, 'Rifle On Back'),
                         'hand=Base.Shotgun second=Base.Shotgun same slot=nil Weapon=firearm')
        self.assertIn('Node: LKActorAimRifle', self.h.eval('solo', f'HARNESS.zombies[{zid}]:getAnimationDebug()'))
        # Fishing : un appel pour le corps, ignoré par la garde ; aucune erreur (banc strict).
        self.assertEqual(self.eq('stats.skipped'), 1)
        self.assertEqual(self.h.eval('solo', 'FISHING.players'), 0)
        self.reset_calls('solo')
        self.apply(5)
        self.gesture('guard')  # toujours en main : rien de reposé
        self.apply(3)
        self.assertEqual(self.ecalls('solo'), [])
        self.gesture('idle')
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Rifle On Back'), 'hand=nil second=nil slot=Base.Shotgun Weapon=')
        self.assertEqual(self.ecalls('solo'), ['secondary:nil', 'primary:nil',
                                               'setAttachedItem:Rifle On Back:Base.Shotgun'])
        self.assertEqual(self.eq('stats.skipped'), 2)  # setPrimaryHandItem(nil) déclenche aussi l'événement
        self.assertEqual(self.h.errors('solo'), [])

    def test_each_weapon_kind_gets_its_slot_and_weapon_variable(self):
        zid = self.npc()
        cases = [('Base.Pistol', 'Holster Right', 'aim', 'hand=Base.Pistol second=nil slot=nil Weapon=handgun'),
                 ('Base.BaseballBat', 'Shovel Back', 'guard',
                  'hand=Base.BaseballBat second=Base.BaseballBat same slot=nil Weapon=2handed'),
                 ('Base.HandAxe', 'Belt Left', 'strike', 'hand=Base.HandAxe second=nil slot=nil Weapon=1handed'),
                 ('Base.KitchenKnife', 'Belt Left Upside', 'guard',
                  'hand=Base.KitchenKnife second=nil slot=nil Weapon=knife')]
        previous = None
        for item, slot, gesture, held in cases:
            self.gesture('idle')
            self.assertEqual(self.weapon(item), [True])
            self.apply()
            self.assertEqual(self.ws('solo', zid, slot), f'hand=nil second=nil slot={item} Weapon=')
            if previous:  # ancienne arme retirée de son emplacement
                self.assertIn('slot=nil', self.ws('solo', zid, previous))
            self.gesture(gesture)
            self.apply()
            self.assertEqual(self.ws('solo', zid, slot), held)
            previous = slot
        # Changement d'arme pendant un geste : l'ancienne quitte la main, la nouvelle y entre.
        self.assertEqual(self.weapon('Base.Pistol'), [True])
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Holster Right'), 'hand=Base.Pistol second=nil slot=nil Weapon=handgun')
        self.assertIn('slot=nil', self.ws('solo', zid, 'Belt Left Upside'))
        # Retrait : rien ne reste, ni en main ni accroché.
        self.assertEqual(self.weapon('none'), [True])
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Holster Right'), 'hand=nil second=nil slot=nil Weapon=')
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"].weapon'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_invalid_requests_refused_and_registry_untouched(self):
        self.npc()
        for item, why in (('Base.Nope', 'unknown item Base.Nope'), ('Base.Apple', 'Base.Apple is not a weapon'),
                          ('Base.Plank', 'Base.Plank has no known attachment slot (AttachmentType nil)'),
                          ('Pistol', 'bad item type Pistol')):
            self.assertEqual(self.weapon(item), [False, why])
        self.assertEqual(self.weapon('Base.Pistol', npc='lk-9'), [False, 'unknown npc lk-9'])
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"].weapon'))
        self.assertEqual(self.h.pending(), [])

    def test_stale_object_cleaned_and_recreated_body_reequipped(self):
        zid = self.npc()
        self.weapon('Base.Pistol')
        self.gesture('aim')
        self.apply()
        # Corps qui n'est plus le corps courant (vivant) : ce que nous avons posé est retiré.
        self.run_lua('LivingKnox.Bodies.bound["lk-1"] = nil')
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Holster Right'), 'hand=nil second=nil slot=nil Weapon=')
        self.assertIsNone(self.eq('shown["lk-1"]'))
        # Corps relié de nouveau (sondage) : arme reposée en main.
        self.run_lua(f'LivingKnox.Bodies.bound["lk-1"] = HARNESS.zombies[{zid}]')
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Holster Right'), 'hand=Base.Pistol second=nil slot=nil Weapon=handgun')

    def test_registry_field_optional_validated_and_reread(self):
        self.npc()
        I = 'LivingKnox.Identity'
        # Registre sans arme (écrit avant LK02-T06) : valide, schéma inchangé.
        self.assertEqual(self.ev(f'{I}.SCHEMA'), 2)
        self.assertIsNotNone(self.ev(f'{I}.validate(LivingKnox.Store.data())'))
        self.weapon('Base.HandAxe')
        self.ev('LivingKnox.Store.init(false)')  # relecture du fichier
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].weapon'), 'Base.HandAxe')
        bad = lua_list(self.ev(f'{{ {I}.validate({{ schema = 2, nextId = 2, npcs = {{ ["lk-1"] = (function() '
                               f'local n = {{}} for k, v in pairs(LivingKnox.Store.data().npcs["lk-1"]) do n[k] = v '
                               f'end n.weapon = 12 return n end)() }} }}) }}'))
        self.assertEqual(bad[1:], ['npc lk-1: bad weapon type', 'invalid'])

    def test_fishing_double_fails_on_a_body_and_the_guard_skips_only_non_players(self):
        zid = self.npc()
        z = f'HARNESS.zombies[{zid}]'
        # Doublure fidèle : sans garde, l'abonné vanilla échoue sur un zombie (objet posé quand même).
        self.h.load('solo', f'{z}:setPrimaryHandItem(instanceItem("Base.Pistol"))')
        errors = self.h.errors('solo')
        self.assertEqual(len(errors), 1)
        self.assertIn('OnEquipPrimary', errors[0])
        self.assertIn('getPlayerNum', errors[0])
        self.assertIn('hand=Base.Pistol', self.ws('solo', zid))
        self.h._mark()
        self.assertIs(self.eq('guardEquipEvent()'), True)
        self.assertIs(self.eq('guardEquipEvent()'), True)
        self.h.load('solo', f'{z}:setPrimaryHandItem(nil)')
        self.assertEqual(len(self.h.errors('solo')), 1)  # aucune nouvelle erreur
        self.assertEqual(self.eq('stats.skipped'), 1)
        # Un joueur passe à l'original sans changement.
        self.assertEqual(self.h.eval('solo', 'Fishing.Handler.handleFishing(getPlayer(), nil)'), 0)
        self.assertEqual(self.h.eval('solo', 'FISHING.players'), 1)
        # Rechargement du module : une seule enveloppe, autour de l'original vanilla.
        self.h.load('solo', EQUIPMENT)
        self.assertIs(self.eq('guardEquipEvent()'), True)
        self.assertIs(self.h.eval('solo', 'rawequal(LivingKnox.Equipment.hooks.fishingOriginal, VANILLA_HANDLE)'),
                      True)
        self.assertIs(self.h.eval('solo', 'rawequal(Fishing.Handler.handleFishing, '
                                          'LivingKnox.Equipment.hooks.fishingWrapper)'), True)

    def test_dev_command_and_suite_on_the_doubles(self):
        zid = self.npc()
        self.h.load('solo', 'server/RST/RST_LKBodiesServer.lua')
        self.h.load('solo', 'client/RST/RST_LKBodiesClient.lua')
        self.assertIs(self.h.eval('solo', 'LKB.weapon(1, "Base.Pistol")'), True)
        self.assertIs(self.h.eval('solo', 'LKB.weapon(1, "Base.Nope")'), False)
        self.assertIs(self.h.eval('solo', 'LKB.list()'), True)
        self.apply()
        self.assertIs(self.h.eval('solo', 'LKB.anim(1)'), True)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKB]')]
        self.assertIn('[LKB] weapon lk-1 -> Base.Pistol (body bound)', lines)
        self.assertIn('[LKB] weapon refused: unknown item Base.Nope', lines)
        self.assertTrue(any(line.startswith('[LKB] lk-1 ') and line.endswith(' weapon=Base.Pistol') for line in lines))
        self.assertIn('[LKB] lk-1 weapon Base.Pistol at Holster Right; hand= second= slot=Base.Pistol Weapon=',
                      lines)
        self.assertIs(self.h.eval('solo', 'LKB.weapon(1, "none")'), True)
        self.run_lua(f'LivingKnox.Bodies.despawn("lk-1", true); HARNESS.zombies[{zid}] = nil')
        # Suite lk.equipment sur les doublures : corps debout dès sa création.
        self.run_lua('local raw = LivingKnox.Bodies.createBody\n'
                     'LivingKnox.Bodies.createBody = function(...) local z, why = raw(...) '
                     'if z then z.onFloor = false end return z, why end')
        self.h.fire('solo', 'OnInitGlobalModData', True)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.equipment", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.equipment')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])   # E01-T19: also run by the MP server
        self.assertEqual(listed.count, 3)
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.equipment", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(3000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 3, results)
        self.assertTrue(report.ok, results)
        measures = [line for line in self.h.logs('solo') if line.startswith('[LKW] measure')]
        self.assertIn('[LKW] measure Base.Shotgun aim: hand=Base.Shotgun second=Base.Shotgun slot= Weapon=firearm; '
                      'actor=true gesture=aim action=idle state=idle nodes=LKActorAimRifle anims=', measures)
        self.assertTrue(any('OnEquipPrimary events for the npc 4, fishing handler calls skipped 4' in line
                            for line in measures), measures)
        self.assertIn('[LKW] measure weapons mod firearm: Base.Pistol at Holster Right', measures)
        self.assertEqual(sum('Lua errors during the cases: 0' in line for line in measures), 3, measures)
        self.assertEqual(self.ev('#LivingKnox.Bodies.list()'), 0)
        self.assertEqual(self.h.eval('solo', '(function() local n = 0 for _ in pairs(LivingKnox.Equipment.reported) '
                                             'do n = n + 1 end return n end)()'), 0)


class MultiplayerEquipmentTests(EquipBase):
    def mirror(self, zid, machines=('A', 'B'), owner='server'):
        srv = self.h.zombie('server', zid)
        for c in machines:
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        srv.owner = owner
        self.h.owners[zid] = owner

    def ready(self, owner='server'):
        zid = self.npc()
        self.mirror(zid, owner=owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def sent(self):
        out = lua_list(self.h.eval('server', 'ATTACH_SENT'))
        self.h.load('server', 'ATTACH_SENT = {}')
        return [(e.o, e.l, e.t) for e in out]

    def deliver(self, sent, machines=('A', 'B')):
        """Paquet GameCharacterAttachedItem livré aux clients proches : rend les clients qui l'ont appliqué."""
        got = []
        for o, loc, t in sent:
            for c in machines:
                arg = 'nil' if t is None else f'"{t}"'
                if self.h.eval(c, f'RECEIVE_ATTACHED({o}, "{loc}", {arg})'):
                    got.append(c)
        return got

    def states(self):
        return [m for m in self.h.pending() if m['command'] == 'equipState']

    def test_server_attaches_sends_and_publishes_clients_hold_it_for_gestures(self):
        zid = self.ready()
        self.assertEqual(self.weapon('Base.Shotgun'), [True])
        # Serveur : accroché sur sa copie, envoyé, table publiée ; jamais en main.
        self.assertEqual(self.ws('server', zid, 'Rifle On Back'), 'hand=nil second=nil slot=Base.Shotgun Weapon=')
        self.assertEqual(self.sent(), [(zid, 'Rifle On Back', 'Base.Shotgun')])
        msgs = self.states()
        self.assertEqual(sorted(m['to'] for m in msgs), ['A', 'B'])
        self.assertEqual(msgs[0]['args'], {'rev': 1, 'w': {'lk-1': {'t': 'Base.Shotgun', 'l': 'Rifle On Back',
                                                                    'h': True}}})
        self.assertEqual(self.deliver([(zid, 'Rifle On Back', 'Base.Shotgun')]), ['A', 'B'])
        self.h.pump()
        for c in ('A', 'B'):
            self.reset_calls(c)
        self.apply(3)
        for c in ('A', 'B'):
            self.assertEqual(self.ecalls(c), [])  # objet reçu du serveur : déjà juste
            self.assertEqual(self.ws(c, zid, 'Rifle On Back'), 'hand=nil second=nil slot=Base.Shotgun Weapon=')
        self.gesture('aim')
        self.h.pump()
        self.apply()
        for c in ('A', 'B'):
            self.assertEqual(self.ws(c, zid, 'Rifle On Back'),
                             'hand=Base.Shotgun second=Base.Shotgun same slot=nil Weapon=firearm')
            # Zombie simulé par le serveur : isLocal faux chez les clients, la pêche n'est pas appelée.
            self.assertEqual(self.eq('stats.skipped', c), 0)
        self.slow(3)
        self.assertEqual(self.sent(), [])  # rien de renvoyé tant que rien ne change
        self.assertEqual(self.states(), [])
        self.assertEqual(self.ws('server', zid, 'Rifle On Back'), 'hand=nil second=nil slot=Base.Shotgun Weapon=')
        self.assertFalse(any(x.startswith(('primary', 'secondary')) for x in self.ecalls('server')))
        self.gesture('idle')
        self.h.pump()
        self.apply()
        for c in ('A', 'B'):
            self.assertEqual(self.ws(c, zid, 'Rifle On Back'), 'hand=nil second=nil slot=Base.Shotgun Weapon=')

    def test_late_client_recreated_copy_and_hello_get_the_weapon(self):
        zid = self.npc()
        self.mirror(zid, machines=('A',))
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.weapon('Base.Pistol')
        self.assertEqual(self.deliver(self.sent()), ['A'])  # B n'a pas encore de copie : rien reçu
        self.h.pump()
        self.mirror(zid, machines=('B',))  # B arrive : copie sans objet accroché
        self.assertEqual(self.ws('B', zid, 'Holster Right'), 'hand=nil second=nil slot=nil Weapon=')
        self.reset_calls('B')
        self.slow()
        self.assertEqual(self.ws('B', zid, 'Holster Right'), 'hand=nil second=nil slot=Base.Pistol Weapon=')
        self.assertEqual(self.ecalls('B'), ['setAttachedItem:Holster Right:Base.Pistol'])
        # Copie recréée chez A (5 s sans paquet) : nouvel objet sans arme, reprise au passage suivant.
        self.h.machine('A').H.removeZombie(zid)
        self.mirror(zid, machines=('A',))
        self.gesture('aim')
        self.h.pump()
        self.slow()
        self.assertEqual(self.ws('A', zid, 'Holster Right'), 'hand=Base.Pistol second=nil slot=nil Weapon=handgun')
        # Client qui (ré)entre en partie : guardHello -> table des armes renvoyée à lui seul.
        self.h.load('B', 'LivingKnox.ZombieGuard.roster = { rev = -1, count = 0, byId = {}, byOnline = {} }\n'
                         'LivingKnox.ZombieGuard.cache = {}\nLivingKnox.ZombieGuard.state.hello = 0\n'
                         'LivingKnox.Equipment.remote = { rev = -1, w = {} }')
        self.h.tick(self.ev('LivingKnox.ZombieGuard.APPLY_EVERY'))
        self.h.pump(limit=1)
        answers = self.states()
        self.assertEqual([m['to'] for m in answers], ['B'])
        self.assertEqual(answers[0]['args']['w'], {'lk-1': {'t': 'Base.Pistol', 'l': 'Holster Right', 'h': False}})
        self.h.pump()
        self.slow()
        self.assertEqual(self.ws('B', zid, 'Holster Right'), 'hand=Base.Pistol second=nil slot=nil Weapon=handgun')

    def test_chunk_return_resends_and_weapon_change_clears_the_old_slot(self):
        zid = self.ready()
        self.weapon('Base.Shotgun')
        self.sent()
        self.h.pump()
        # Retour de chunk côté serveur : même objet, nouvel onlineID ; renvoi à cet onlineID.
        self.run_lua('UNLOAD(90, 120, 90, 120)')
        self.run_lua('RELOAD()')
        new = self.ev('LivingKnox.Bodies.bound["lk-1"]:getOnlineID()')
        self.slow()
        self.assertEqual(self.sent(), [(new, 'Rifle On Back', 'Base.Shotgun')])
        # Arme changée : ancien emplacement vidé (et envoyé vide), nouvelle arme accrochée.
        self.weapon('Base.BaseballBat')
        self.assertEqual(self.sent(), [(new, 'Rifle On Back', None), (new, 'Shovel Back', 'Base.BaseballBat')])
        self.assertEqual(self.ws('server', new, 'Rifle On Back'), 'hand=nil second=nil slot=nil Weapon=')
        self.assertEqual(self.ws('server', new, 'Shovel Back'), 'hand=nil second=nil slot=Base.BaseballBat Weapon=')
        self.weapon(None)
        self.assertEqual(self.sent(), [(new, 'Shovel Back', None)])
        self.assertEqual(self.states()[-1]['args'].get('w'), {})  # table vide (reçue nil par le client)

    def test_owner_client_skips_the_fishing_handler_and_older_tables_are_ignored(self):
        zid = self.ready(owner='A')
        self.weapon('Base.HandAxe')
        self.h.pump()
        self.gesture('strike')
        self.h.pump()
        self.apply()
        # Client propriétaire : isLocal vrai, la pêche est appelée pour le corps, ignorée par la garde.
        self.assertEqual(self.ws('A', zid, 'Belt Left'), 'hand=Base.HandAxe second=nil slot=nil Weapon=1handed')
        self.assertEqual(self.eq('stats.skipped', 'A'), 1)
        self.assertEqual(self.h.eval('A', 'FISHING.calls'), 0)  # l'original n'est jamais atteint pour le corps
        self.assertEqual(self.h.errors('A'), [])
        rev = self.h.eval('A', 'LivingKnox.Equipment.remote.rev')
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'equipState', {'rev': 0, 'w': {}})
        self.assertEqual(self.h.eval('A', 'LivingKnox.Equipment.remote.rev'), rev)
        self.h.fire('A', 'OnServerCommand', 'LivingKnox', 'equipState',
                    {'rev': rev + 5, 'w': {'lk-1': {'t': 'bad type', 'l': 'Belt Left'}}})
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Equipment.remote.w["lk-1"]'))
        self.apply()
        self.assertEqual(self.ws('A', zid, 'Belt Left'), 'hand=nil second=nil slot=nil Weapon=')
        # Un client n'est pas l'autorité.
        self.assertEqual(self.weapon('Base.Pistol', m='A'), [False, 'not the authority (MP client)'])

    def test_server_hand_item_would_fail(self):
        zid = self.ready()
        with self.assertRaises(Exception):
            self.h.load('server', f'HARNESS.zombies[{zid}]:setPrimaryHandItem(instanceItem("Base.Pistol"))')


class NoFishingTests(EquipBase):
    mode = 'solo'
    fishing = False

    def test_without_the_vanilla_handler_the_guard_is_absent_and_equipping_works(self):
        zid = self.npc()
        self.assertIs(self.eq('guardEquipEvent()'), False)
        self.weapon('Base.Pistol')
        self.gesture('aim')
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Holster Right'), 'hand=Base.Pistol second=nil slot=nil Weapon=handgun')


class OtherSubscribersBase(EquipBase):
    """Abonnés OnEquip* des autres mods (LK02-T13) chargés après le mod, comme un mod plus bas dans la liste."""

    def make(self, root=None):
        h = super().make(root)
        for m in (['solo'] if self.mode == 'solo' else ['server', 'A', 'B']):
            h.load(m, OTHER_SUBSCRIBERS)
            if m != 'server':
                h.load(m, RADIO_WINDOW)
        return h

    def held(self, m, zid):
        return self.h.eval(m, f'HARNESS.zombies[{zid}]:getPrimaryHandItem()')


class SoloOtherSubscribersTests(OtherSubscribersBase):
    mode = 'solo'

    def test_listed_subscribers_only_touch_the_weapon_and_raise_nothing(self):
        zid = self.npc()
        self.weapon('Base.Shotgun')
        self.apply()
        self.gesture('aim')
        self.apply()
        self.assertEqual(self.ws('solo', zid, 'Rifle On Back'),
                         'hand=Base.Shotgun second=Base.Shotgun same slot=nil Weapon=firearm')
        # Deux mains : OnEquipPrimary puis OnEquipSecondary, chacun reçu par le cadre d'armes et la radio.
        self.assertEqual(self.h.eval('solo', 'GUNWORKS.calls'), 2)
        self.assertEqual(self.h.eval('solo', 'RADIO_WINDOW.calls'), 2)
        self.assertEqual(self.h.eval('solo', 'RADIO_WINDOW.activated'), 0)
        # Effet limité à l'objet que nous avons posé : état de l'arme restauré (comme pour un joueur).
        self.assertEqual(self.h.eval('solo', f'HARNESS.zombies[{zid}]:getPrimaryHandItem():getModData().gwRestored'),
                         2)
        self.assertIs(self.h.eval('solo', f'HARNESS.zombies[{zid}]:getPrimaryHandItem():getModData().gwStates'), True)
        self.gesture('idle')
        self.apply()
        # Mains vidées : abonnés appelés avec nil, rien fait.
        self.assertEqual(self.h.eval('solo', 'GUNWORKS.calls'), 4)
        self.assertEqual(self.h.eval('solo', 'GUNWORKS.touched'), 2)
        self.assertEqual(self.ws('solo', zid, 'Rifle On Back'), 'hand=nil second=nil slot=Base.Shotgun Weapon=')
        # Arme de mêlée ou non enregistrée : rien touché.
        self.weapon('Base.HandAxe')
        self.gesture('strike')
        self.apply()
        self.assertEqual(self.h.eval('solo', 'GUNWORKS.touched'), 2)
        self.assertEqual(self.h.errors('solo'), [])

    def test_limit_a_later_mod_assuming_a_player_fails_once_per_pose_and_display_holds(self):
        """Limite documentée : un abonné inconnu qui suppose un joueur n'est pas neutralisé. L'erreur est isolée
        (Event.java:52-62), une par pose ou retrait, jamais par passage ; l'affichage reste juste."""
        self.h.strict = False
        zid = self.npc()
        self.h.load('solo', 'Events.OnEquipPrimary.Add(ASSUMES_PLAYER)')
        self.weapon('Base.Pistol')
        self.apply()
        self.gesture('aim')
        self.apply(5)
        self.assertEqual(self.ws('solo', zid, 'Holster Right'), 'hand=Base.Pistol second=nil slot=nil Weapon=handgun')
        errors = self.h.errors('solo')
        self.assertEqual(len(errors), 1)
        self.assertIn('OnEquipPrimary', errors[0])
        self.assertIn('getPlayerNum', errors[0])
        self.gesture('idle')
        self.apply(5)
        self.assertEqual(self.ws('solo', zid, 'Holster Right'), 'hand=nil second=nil slot=Base.Pistol Weapon=')
        self.assertEqual(len(self.h.errors('solo')), 2)
        self.assertEqual(self.h.eval('solo', '(function() local n = 0 for _ in pairs(LivingKnox.Equipment.reported) '
                                             'do n = n + 1 end return n end)()'), 0)  # rien d'échoué de notre côté


class MultiplayerOtherSubscribersTests(OtherSubscribersBase):
    def test_every_client_runs_the_shared_subscribers_without_error_server_never_does(self):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.weapon('Base.Pistol')
        self.h.pump()
        self.gesture('aim')
        self.h.pump()
        self.apply()
        for c in ('A', 'B'):  # propriétaire ou non : l'événement est déclenché sur chaque copie qui tient l'arme
            self.assertEqual(self.ws(c, zid, 'Holster Right'), 'hand=Base.Pistol second=nil slot=nil Weapon=handgun')
            self.assertEqual(self.h.eval(c, 'GUNWORKS.touched'), 1)
            self.assertEqual(self.h.eval(c, 'RADIO_WINDOW.activated'), 0)
            self.assertEqual(self.h.errors(c), [])
        self.assertEqual(self.h.eval('server', 'GUNWORKS.calls'), 0)  # jamais d'objet en main sur le serveur


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

    def test_hand_items_never_set_by_the_server_and_only_the_fishing_handler_wrapped(self):
        code = (LUA / EQUIPMENT).read_text(encoding='utf-8')
        code = re.sub(r'--[^\n]*', '', code)
        # setPrimaryHandItem seulement dans equip / unequip, appelés par la passe d'affichage (jamais sur le serveur).
        self.assertEqual(len(re.findall(r'setPrimaryHandItem', code)), 2)
        self.assertIn('if isServer() then\n        if slow then', code)
        self.assertEqual(re.findall(r'\bF\.(\w+) = ', code), ['handleFishing'])  # affectation seulement
        self.assertNotIn('Events.OnEquipPrimary', code)

    def test_slots_are_vanilla_human_locations(self):
        locations = pz_paths.media_dir() / 'lua/shared/NPCs/AttachedLocations.lua'
        code = (LUA / EQUIPMENT).read_text(encoding='utf-8')
        block = re.search(r'Equipment\.LOCATIONS = \{(.*?)\n\}', code, flags=re.S).group(1)
        slots = set(re.findall(r'= "([^"]+)"', block))
        self.assertTrue(slots)
        if not locations.exists():
            self.skipTest('vanilla AttachedLocations.lua not installed')
        human = locations.read_text(encoding='utf-8', errors='replace').split('getGroup("Human")', 1)[1]
        declared = set(re.findall(r'^group:getOrCreateLocation\("([^"]+)"\)', human, flags=re.M))
        self.assertEqual(slots - declared, set())


if __name__ == '__main__':
    unittest.main()
