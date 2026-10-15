"""Tests hors jeu des corps de PNJ Living Knox (LK02-T02) : registre, persistance, création, liaison, doublons, orphelins.

    python RadioSurvivor/tests/test_lk_bodies.py

Banc tests/harness.py (serveur dédié + deux clients, ou solo). Les doublures ci-dessous reproduisent le Java 42.21.0
relevé (références en commentaire) ; elles NE PROUVENT PAS l'API réelle, seulement la logique du mod :
- création (chemin B) : addZombiesInOutfit (LuaManager.java:8355-8445 : liste vide sur une case non chargée),
  DoZombieInventory, square:createCorpse(zombie) (IsoGridSquare.java:10109-10124 : le zombie quitte le monde, le
  cadavre copie ModData et visuel, IsoDeadBody.java:378), body:reanimate() (IsoDeadBody.java:1832-1946 : nouveau
  zombie isReanimatedPlayer, ModData copiées, cadavre retiré) ;
- retrait : removeFromWorld d'un joueur réanimé vivant = mis de côté (VirtualZombieManager.java:677-684,
  ReanimatedPlayers.java:68-114) ; mort (isDead = santé <= 0, IsoGameCharacter.java:4645) = retiré pour de bon ;
- déchargement d'une zone : un joueur réanimé est mis de côté (même objet, ModData gardées), un zombie ordinaire
  recyclé (ModData vidées) ; rechargement : le même objet revient dans la liste des zombies avec un nouvel onlineID
  sur le serveur (ReanimatedPlayers.java:39-66), sans OnZombieCreate ;
- redémarrage : nouveau banc sur le même dossier de fichiers (registre relu) ; les joueurs réanimés vivants (dans le
  monde ou mis de côté) sont « sauvegardés » puis recréés (reanimated.bin, ReanimatedPlayers.java:116-196) avec
  leurs ModData, `useless` non conservé ;
- hasModData = table non vide (IsoObject.java:1137-1139).
"""
from __future__ import annotations

import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness, LUA  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEV_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/LK_Appearance.lua', 'shared/LivingKnox/LK_Identity.lua')
MOD_FILES = [LUA / p for p in SHARED[3:]] + [LUA / 'server' / 'LivingKnox' / n
                                              for n in ('LK_Store.lua', 'LK_Bodies.lua', 'LK_Server.lua')]
DEV_FILES = [DEV_LUA / 'server' / 'RST' / 'RST_LKBodiesServer.lua', DEV_LUA / 'client' / 'RST' / 'RST_LKBodiesClient.lua',
             DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKBodies.lua', DEV_LUA / 'shared' / 'RST' / 'suites' / 'RS_Killer.lua']

DOUBLES = r'''
local H = HARNESS
local MODE, NAME = H.mode, H.name
local C = H.classes
CALLS, PARKED, NEXT_ID, UNLOADED = {}, {}, (MODE == 'client') and 5000 or 1000, {}
WORLD_NAME, GAME_MODE, ADMINS, SCANNED = 'rstest_banc', 'Multiplayer', { A = true }, 0
local function call(s) CALLS[#CALLS + 1] = s end

getWorld = function()
    return { getWorld = function() return WORLD_NAME end, getGameMode = function() return GAME_MODE end }
end
Capability = { DebugConsole = 'DebugConsole' }
checkPermissions = function() return true end
C.IsoPlayer.getRole = function(self)
    local name = self.username
    return { hasCapability = function() return ADMINS[name] == true end }
end

C.ArrayList.clear = function(self) self.items = {} end
function C.IsoObject:hasModData()  -- IsoObject.java:1137-1139 : table non vide
    local md = rawget(self, '__modData')
    if not md then return false end
    for _ in pairs(md) do return true end
    return false
end

-- Zone non chargée : rectangles {x1, y1, x2, y2} (bornes incluses), getGridSquare rend nil.
local function unloaded(x, y)
    for _, a in ipairs(UNLOADED) do
        if x >= a[1] and x <= a[2] and y >= a[3] and y <= a[4] then return true end
    end
    return false
end
local rawGet = C.IsoCell.getGridSquare
C.IsoCell.getGridSquare = function(self, x, y, z)
    local sq = rawGet(self, x, y, z)
    if unloaded(sq.x, sq.y) then return nil end
    return sq
end
C.IsoGridSquare.getStaticMovingObjects = function(self)
    local l = rawget(self, 'statics')
    if not l then l = H.list(); self.statics = l end
    return l
end
-- Plantes cultivées et feux de camp (IsoGridSquare.java:9713-9776) : objets des systèmes de GlobalObject "farming"
-- et "campfire". hasFarmingPlant : CGlobalObjects sur un client MP, SGlobalObjects ailleurs (vrai partout, plante
-- détruite comprise) ; getCampfire et hasLitCampfire passent par SGlobalObjects seulement : nil / faux sur un client
-- MP (SCampfireSystem.lua:1 et SGlobalObjectSystem.lua:1 ne s'y chargent pas). Doublure : square.plant (table
-- { state = "seeded" } ou vrai), square.campfire (table { isLit = booléen } ou vrai = allumé).
function C.IsoGridSquare:hasFarmingPlant() return self.plant ~= nil and self.plant ~= false end
function C.IsoGridSquare:getCampfire()
    if MODE == 'client' or self.campfire == nil or self.campfire == false then return nil end
    return self.campfire
end
function C.IsoGridSquare:hasLitCampfire()
    local c = self:getCampfire()
    if c == nil then return false end
    return c == true or c.isLit == true
end

local Z = C.IsoZombie
-- Apparence (LK02-T03). BloodBodyPartType : 17 parties + MAX (BloodBodyPartType.java:14-32).
BloodBodyPartType = { MAX = { index = function() return 17 end } }
-- ImmutableColor.new(r, g, b, a) : surcharge float retenue (Math.min(x, 1), ImmutableColor.java:74-79) ;
-- getRedInt = (int)(r x 255) (ImmutableColor.java:187-209).
local Color = H.class('ImmutableColor')
function Color:getRedInt() return math.floor(self.r * 255) end
function Color:getGreenInt() return math.floor(self.g * 255) end
function Color:getBlueInt() return math.floor(self.b * 255) end
ImmutableColor = { new = function(r, g, b, a)
    H.num(r, 'ImmutableColor.new'); H.num(g, 'ImmutableColor.new'); H.num(b, 'ImmutableColor.new')
    H.num(a, 'ImmutableColor.new')
    return setmetatable({ r = math.min(r, 1), g = math.min(g, 1), b = math.min(b, 1), a = math.min(a, 1) }, Color)
end }
local function isColor(c) return getmetatable(c) == Color end

-- HumanVisual (HumanVisual.java) : peau, coupe, barbe, couleurs, sang, saleté, plaies (bodyVisuals).
local HV = H.class('HumanVisual')
function HV:setSkinTextureName(n) if type(n) ~= 'string' then error('No implementation found', 2) end self.skin = n end
function HV:getSkinTexture() return self.skin or (self.female and 'F_ZedBody01_level1' or 'M_ZedBody01_level1') end
function HV:setHairModel(n) if type(n) ~= 'string' then error('No implementation found', 2) end self.hair = n end
function HV:getHairModel() return self.hair end
function HV:setBeardModel(n) if type(n) ~= 'string' then error('No implementation found', 2) end self.beard = n end
function HV:getBeardModel() if self.female then return nil end return self.beard end  -- HumanVisual.java:263-270
for _, f in ipairs({ 'HairColor', 'BeardColor', 'NaturalHairColor', 'NaturalBeardColor' }) do
    HV['set' .. f] = function(self, c) if not isColor(c) then error('No implementation found', 2) end self[f] = c end
    HV['get' .. f] = function(self) return self[f] end
end
function HV:removeBlood() self.blood = false end
function HV:removeDirt() self.dirt = false end
function HV:getBodyVisuals() return self.body end
function HV:getTotalBlood() return self.blood and 3 or 0 end
local function newHV(female)
    return setmetatable({ female = female, blood = true, dirt = true, hair = 'Mullet', beard = 'LongScruffy',
        body = H.list({ 'ZedDmg' }) }, HV)
end
local function copyHV(hv)
    local c = setmetatable({}, HV)
    for k, v in pairs(hv) do c[k] = v end
    c.body = H.list({})
    for i, v in ipairs(hv.body.items) do c.body.items[i] = v end
    return c
end

-- ItemVisual (ItemVisual.java:501-645) : trous, pièces, sang et saleté par partie (index 0..16).
local IV = H.class('ItemVisual')
local function part(i, what)
    H.num(i, what)
    if i < 0 or i >= 17 then error('ArrayIndexOutOfBoundsException: Index ' .. i .. ' out of bounds for length 17', 3) end
    return math.floor(i)
end
function IV:getItemType() return self.type end
-- Visuels concrets (LK02-T12, ItemVisual.java:46-213) : constructeur, champs posés et relus, valeurs tirables fixées
-- par pickUninitializedValues ; un type listé dans MISSING_ITEMS n'a plus de script (mod retiré).
MISSING_ITEMS = {}
ItemVisual = { new = function()
    return setmetatable({ blood = 0, dirt = 0, holes = {}, patches = {} }, IV)
end }
function IV:setItemType(t)
    if type(t) ~= 'string' or not string.find(t, '.', 1, true) then error('No implementation found', 2) end
    self.type = t
end
function IV:getScriptItem() if self.type == nil or MISSING_ITEMS[self.type] then return nil end return { type = self.type } end
function IV:getClothingItem() if self:getScriptItem() == nil then return nil end return { ci = self.type } end
function IV:setClothingItemName(n) self.item = n end
function IV:getClothingItemName() return self.item end
function IV:setAlternateModelName(n) self.alt = n end
function IV:getAlternateModelName() return self.alt end
function IV:setTint(c) self.tint = c end
function IV:getTint() return self.tint end
function IV:setHue(h) H.num(h, 'setHue'); self.hue = math.max(-1, math.min(1, h)) end
function IV:getHue() return self.hue or math.huge end
function IV:setBaseTexture(i) H.num(i, 'setBaseTexture'); self.base = i end
function IV:getBaseTexture() return self.base or -1 end
function IV:setTextureChoice(i) H.num(i, 'setTextureChoice'); self.choice = i end
function IV:getTextureChoice() return self.choice or -1 end
function IV:setDecal(d) self.decal = d end
function IV:getDecal(ci) if ci == nil then error('NullPointerException', 2) end return self.decal end
PICKED = 0
function IV:pickUninitializedValues(ci)  -- tirage OutfitRNG non reproductible : valeurs flottantes
    if ci == nil then return end
    if self.tint == nil then PICKED = PICKED + 1; self.tint = ImmutableColor.new(0.123456, 0.654321, 0.5, 1) end
    if self.hue == nil then self.hue = 0 end
end
function IV:removeBlood() self.blood = 0 end
function IV:removeDirt() self.dirt = 0 end
function IV:removeHole(i) self.holes[part(i, 'removeHole') + 1] = nil end
function IV:removePatch(i) self.patches[part(i, 'removePatch') + 1] = nil end
function IV:getHolesNumber() local n = 0 for _ in pairs(self.holes) do n = n + 1 end return n end
function IV:getBasicPatchesNumber() local n = 0 for _ in pairs(self.patches) do n = n + 1 end return n end
function IV:getTotalBlood() return self.blood end
function IV:getTotalDirt() return self.dirt end  -- doublure seulement : la somme des getDirt(partie)
-- Habillage d'un zombie par son identifiant de tenue : sang, saleté, trous (addRandomBloodDirtHolesEtc). Le résultat
-- dépend de l'index de la tenue ET de la variante (graine), comme le tirage OutfitRNG vanilla : un décalage d'index
-- (OUTFIT_SHIFT) donne d'autres objets et d'autres teintes pour la même variante. La teinte du t-shirt reste à
-- tirer (pickUninitializedValues), comme celle d'un vêtement par défaut (HumanVisual.dressInOutfit).
local function dirtyItems(id)
    local raw = id < 0 and id + 2147483648 or id
    local variant, index = (raw % 65536) % 32768, math.floor(raw / 65536)
    local out = H.list()
    for i, t in ipairs({ 'Base.Tshirt', 'Base.Trousers', 'Base.Shoes' }) do
        local iv = setmetatable({ type = t .. '@' .. tostring(index) .. '#' .. tostring(variant), blood = 2, dirt = 1,
            holes = { [i] = true, [9] = true }, patches = { [3] = true }, item = t .. 'Item' }, IV)
        if i > 1 then
            iv.tint = ImmutableColor.new(((index * 7 + variant) % 256) / 255, (i * 40) / 255, 0.5, 1)
            iv.hue, iv.base, iv.choice = ((variant % 200) - 100) / 100, i - 1, (index + variant) % 3
        end
        if i == 3 then iv.decal = 'Decal' .. tostring(index) end
        out:add(iv)
    end
    return out
end
local function copyItems(list)
    local out = H.list()
    for _, iv in ipairs(list.items) do
        local c = setmetatable({}, IV)
        for k, v in pairs(iv) do c[k] = v end
        c.holes, c.patches = {}, {}
        for k, v in pairs(iv.holes) do c.holes[k] = v end
        for k, v in pairs(iv.patches) do c.patches[k] = v end
        out:add(c)
    end
    return out
end

-- Identifiant de tenue persistante (PersistentOutfits.java:142-160) : bit 31 femme, tenue << 16, variante 1..500.
OUTFIT_DRAW, OUTFIT_SHIFT = 0, 0
-- OUTFIT_SHIFT : tenues ajoutées avant celle-ci par un mod (index décalé, PersistentOutfits.initOutfitList).
local function pickOutfit(outfit, female)
    OUTFIT_DRAW = OUTFIT_DRAW % 500 + 1
    local index = 10 + OUTFIT_SHIFT + (tonumber(string.match(outfit or '', '(%d+)$') or '0') or 0)
    return (female and -2147483648 or 0) + index * 65536 + OUTFIT_DRAW
end

local function visual(z)
    local hv = rawget(z, 'hv')
    if hv then return hv end
    hv = newHV(z.female == true)
    z.hv = hv
    return hv
end
function Z:getHumanVisual() return visual(self) end
-- Avant DoZombieInventory : la liste vivante des visuels (IsoZombie.java:3834-3846) ; joueur réanimé : visuels des
-- objets portés.
function Z:getItemVisuals()
    local l = rawget(self, 'ivs')
    if not l then l = dirtyItems(self.outfitId or 1); self.ivs = l end
    return l
end
function Z:getPersistentOutfitID() return self.outfitId or 0 end
function Z:dressInPersistentOutfitID(id)  -- IsoZombie.java:3904-3915 : visuel effacé, tenue rejouée
    H.num(id, 'dressInPersistentOutfitID')
    call('dress:' .. string.format('%.0f', id))
    self.outfitId = id
    self.female = id < 0
    self.hv = newHV(self.female)
    self.ivs = dirtyItems(id)
    self.attached = 1
end
function Z:clearAttachedItems() call('clearAttachedItems'); self.attached = 0 end
function Z:getAttachedItems() return H.list(self.attached == 1 and { 'Base.KitchenKnife' } or {}) end
function Z:isDead() return self.dead == true or (rawget(self, 'health') or 1) <= 0 end
function Z:setHealth(h) H.num(h, 'setHealth'); self.health = h; call('setHealth:' .. h .. ':' .. self.onlineID) end
function Z:getHealth() return rawget(self, 'health') or 1 end  -- IsoGameCharacter.java:2898
function Z:setUseless(b) self.useless = b end
function Z:isUseless() return self.useless == true end
function Z:isReanimatedPlayer() SCANNED = SCANNED + 1; return self.reanimated == true end
function Z:isReanimatedForGrappleOnly() return self.grappleOnly == true end  -- IsoZombie.java:1544 (cadavre traîné)
function Z:isFemale() return self.female == true end
function Z:DoZombieInventory()  -- objets portés créés depuis les visuels (WornItems.java:143-160)
    call('DoZombieInventory:' .. self.onlineID)
    self.worn = copyItems(self:getItemVisuals())
end
function Z:getWornItems() return rawget(self, 'worn') or H.list() end  -- objets portés (taille seulement ici)
-- VirtualZombieManager.RemoveZombie : un joueur réanimé vivant est mis de côté (même objet), sinon retiré.
function Z:removeFromWorld()
    call('removeFromWorld:' .. self.onlineID)
    if self.reanimated then RELEASE_DESCRIPTOR(self) end
    if self.reanimated and not self:isDead() then PARKED[#PARKED + 1] = self end
    H.removeZombie(self.onlineID)
end
function Z:removeFromSquare()
    call('removeFromSquare')
    if self.square then H.listRemove(self.square.movingObjects, self) end
end

local function newZombie(x, y, z)
    local id = NEXT_ID
    NEXT_ID = NEXT_ID + 1
    return H.spawnZombie(id, x, y, z, (MODE == 'client') and NAME or 'server')
end
function NEW_ZOMBIE(x, y, z, reanimated, md)
    local zb = newZombie(x, y, z)
    zb.reanimated = reanimated
    for k, v in pairs(md or {}) do zb:getModData()[k] = v end
    return zb
end

addZombiesInOutfit = function(x, y, z, n, outfit, femaleChance)
    H.num(x, 'addZombiesInOutfit'); H.num(y, 'addZombiesInOutfit'); H.num(z, 'addZombiesInOutfit')
    H.num(n, 'addZombiesInOutfit'); H.num(femaleChance, 'addZombiesInOutfit')
    call('addZombiesInOutfit:' .. tostring(outfit) .. ':' .. femaleChance)
    local out = H.list()
    if getCell():getGridSquare(x, y, z) == nil then return out end
    for _ = 1, n do
        local zb = newZombie(x + 0.5, y + 0.5, z)
        zb.female = femaleChance >= 100
        zb.outfitId = pickOutfit(outfit, zb.female)
        zb.attached = 1  -- arme plantée possible (PersistentOutfits.java:279)
        out:add(zb)
    end
    return out
end

-- Descripteur partagé d'un joueur réanimé (SharedDescriptors.java:44-117) : premier emplacement libre, identifiant
-- de tenue = bit 31 femme + index de la tenue "ReanimatedPlayer" << 16 + emplacement + 1 ; emplacement rendu quand
-- le corps quitte le monde (ReanimatedPlayers.java:99), nouveau descripteur à son retour (ReanimatedPlayers.java:63).
REANIMATED_OUTFIT, DESC_SLOTS = 98, {}
function TAKE_DESCRIPTOR(zb)
    local i = 0
    while DESC_SLOTS[i] do i = i + 1 end
    DESC_SLOTS[i] = zb
    zb.descSlot = i
    zb.outfitId = (zb.female and -2147483648 or 0) + REANIMATED_OUTFIT * 65536 + i + 1
end
function RELEASE_DESCRIPTOR(zb)
    if zb.descSlot ~= nil and DESC_SLOTS[zb.descSlot] == zb then DESC_SLOTS[zb.descSlot] = nil end
    zb.descSlot = nil
end

local Body = H.class('IsoDeadBody', C.IsoMovingObject)
function Body:getSquare() return self.square end
FAIL_REANIMATE = false
function Body:reanimate()
    call('reanimate')
    if FAIL_REANIMATE then return nil end
    local zb = newZombie(self.x, self.y, self.z)
    zb.reanimated, zb.female, zb.onFloor = true, self.female, true
    -- IsoDeadBody.java:1875-1880, 1930-1937 : au sol, fallOnFront du cadavre, ActionContext passé à onground
    -- (bOnFloor) et ZombieOnGroundState.enter (non collidable, ZombieOnGroundState.java:37-67).
    zb.fallOnFront, zb.actionState, zb.collidable = self.fallOnFront == true, 'onground', false
    zb.aiState = ZombieOnGroundState.instance()
    TAKE_DESCRIPTOR(zb)
    zb.hv = copyHV(self.visual)  -- HumanVisual.copyFrom (IsoDeadBody.java:1854)
    zb.ivs = copyItems(self.worn)  -- objets portés copiés (IsoDeadBody.java:1855) ; visuels = ceux des objets
    zb.attached = self.attached
    for k, v in pairs(self:getModData()) do zb:getModData()[k] = v end
    if self.square then H.listRemove(self.square:getStaticMovingObjects(), self) end
    self.square = nil
    return zb
end
function C.IsoGridSquare:createCorpse(arg)
    if type(arg) == 'boolean' then call('createCorpse:boolean') return nil end
    call('createCorpse:zombie:' .. arg.onlineID)
    -- baseVisual.copyFrom, objets portés et accrochés repris (IsoDeadBody.java:323-333)
    local body = setmetatable({ x = self.x + 0.5, y = self.y + 0.5, z = self.z, square = self, female = arg.female,
        visual = copyHV(arg:getHumanVisual()), worn = copyItems(arg.worn or H.list()), attached = arg.attached },
        Body)
    for k, v in pairs(arg:getModData()) do body:getModData()[k] = v end  -- copie (IsoDeadBody.java:378)
    arg:removeFromWorld()
    self:getStaticMovingObjects():add(body)
    return body
end
function C.IsoGridSquare:removeCorpse(body, remote)
    call('removeCorpse:' .. tostring(remote))
    H.listRemove(self:getStaticMovingObjects(), body)
    body.square = nil
end

-- Déchargement d'une zone : joueurs réanimés vivants mis de côté, zombies ordinaires recyclés (ModData vidées).
function UNLOAD(x1, x2, y1, y2)
    UNLOADED[#UNLOADED + 1] = { x1, x2, y1, y2 }
    local snapshot = {}
    for i, zb in ipairs(H.zombieList.items) do snapshot[i] = zb end
    for _, zb in ipairs(snapshot) do
        if zb.x >= x1 and zb.x <= x2 + 1 and zb.y >= y1 and zb.y <= y2 + 1 then
            if zb.reanimated then RELEASE_DESCRIPTOR(zb) end
            if zb.reanimated and not zb:isDead() then PARKED[#PARKED + 1] = zb else zb.__modData = nil end
            H.removeZombie(zb.onlineID)
        end
    end
end
-- Rechargement : zones chargées, objets mis de côté remis en monde (nouvel onlineID sur le serveur).
function RELOAD()
    UNLOADED = {}
    local parked = PARKED
    PARKED = {}
    for _, zb in ipairs(parked) do
        zb.onlineID = NEXT_ID
        NEXT_ID = NEXT_ID + 1
        H.zombies[zb.onlineID] = zb
        H.zombieList:add(zb)
        H.place(zb, zb.x, zb.y, zb.z)
        TAKE_DESCRIPTOR(zb)
    end
end
-- reanimated.bin : joueurs réanimés vivants, dans le monde ou mis de côté (ReanimatedPlayers.java:116-147).
function SAVE_REANIMATED()
    local out = {}
    local function add(zb)
        local md = {}
        for k, v in pairs(zb:getModData()) do md[k] = v end
        out[#out + 1] = { x = zb.x, y = zb.y, z = zb.z, female = zb.female == true, md = md }
    end
    for _, zb in ipairs(H.zombieList.items) do if zb.reanimated and not zb:isDead() then add(zb) end end
    for _, zb in ipairs(PARKED) do if not zb:isDead() then add(zb) end end
    return out
end
function LOAD_REANIMATED(list)
    for _, e in ipairs(list) do
        local zb = NEW_ZOMBIE(e.x, e.y, e.z, true, e.md)
        zb.female = e.female
    end
end
-- Mort et tueur (E04-T06). HandWeapon : isRanged (HandWeapon.java:823), isExplosive = catégorie d'affichage
-- "Explosives" (HandWeapon.java:1360), getFullType (InventoryItem.java:1513).
local HW = H.class('HandWeapon')
function HW:isRanged() return self.ranged == true end
function HW:isExplosive() return self.explosive == true end
function HW:getFullType() return self.fullType end
WEAPONS = { ['Base.BaseballBat'] = {}, ['Base.Pistol'] = { ranged = true }, ['Base.PipeBomb'] = { explosive = true } }
instanceItem = function(t)
    local w = WEAPONS[t]
    if w == nil then return nil end
    return setmetatable({ fullType = t, ranged = w.ranged, explosive = w.explosive }, HW)
end
-- Véhicule : getDriver (BaseVehicle.java:7782) ; le personnage le porte dans self.vehicle (getVehicle).
local Vehicle = H.class('BaseVehicle')
function Vehicle:getDriver() return self.driver end
function VEHICLE(driver, ...)
    local v = setmetatable({ driver = driver }, Vehicle)
    if driver then driver.vehicle = v end
    for _, p in ipairs({ ... }) do p.vehicle = v end
    return v
end
function Z:getAttackedBy() return self.attackedBy end
function Z:setAttackedBy(k) self.attackedBy = k end
function Z:isOnFire() return self.onFire == true end
function Z:SetOnFire() self.onFire = true end
-- Kill(killer) / Kill(weapon, killer) (IsoGameCharacter.java:13451-13474) : setAttackedBy(killer), santé nulle, puis
-- onKilled une seule fois -> OnZombieDead(zombie) (IsoZombie.java:4599-4609).
function Z:Kill(a, b)
    local killer = a
    if instanceof(a, 'HandWeapon') then killer = b end
    self.attackedBy = killer
    self.health = 0
    if not self.killDone then
        self.killDone = true
        H.trigger('OnZombieDead', self)
    end
end
-- die() (IsoGameCharacter.java:13478-13486) : Kill(getAttackedBy()) si onKilled n'a pas encore eu lieu.
function Z:die() if not self.killDone then self:Kill(self.attackedBy) end end
-- Hit (IsoZombie.java:1098-1124 -> IsoGameCharacter.java:5704-5741, 5826-5845) : arme ou attaquant nil = rien ;
-- OnHitZombie(zombie, attaquant, partie, arme) AVANT les dégâts ; setAttackedBy(attaquant) ; coup mortel : serveur
-- die(), solo Kill(arme, attaquant), client MP rien (le serveur décide).
function Z:Hit(weapon, wielder, damage, ignoreDamage, modDelta)
    H.num(damage, 'Hit'); H.num(modDelta, 'Hit')
    if wielder == nil then error('NullPointerException: wielder.isCriticalHit()', 2) end
    H.trigger('OnHitZombie', self, wielder, 'Torso_Upper', weapon)
    if weapon == nil then return 0 end
    self.attackedBy = wielder
    if not ignoreDamage then self.health = (rawget(self, 'health') or 1) - damage * modDelta end
    if self:isDead() and not self.killDone then
        if MODE == 'server' then self:die() elseif MODE == 'solo' then self:Kill(weapon, wielder) end
    end
    return damage
end
-- Paquet de zombie du client propriétaire (NetworkZombiePacker.java:100-101, 230) : santé posée, die() si nulle.
function CLIENT_HEALTH(zb, h)
    zb.health = h
    if zb:isDead() then zb:die() end
end
-- Dégâts de véhicule sur le serveur (Hit.java:63, VehicleHitField.java:60-70) : setAttackedBy(conducteur), dégâts,
-- aucun OnHitZombie ni Kill (la mort vient ensuite du paquet du propriétaire).
function VEHICLE_HIT(zb, driver, damage)
    zb.attackedBy = driver
    zb.health = (rawget(zb, 'health') or 1) - damage
end
-- Chute (IsoZombie.java:2579) : setAttackedBy(null) puis dégâts.
function FALL(zb, damage)
    zb.attackedBy = nil
    zb.health = (rawget(zb, 'health') or 1) - damage
end
-- Brûlure à chaque mise à jour (IsoGameCharacter.java:6044-6066) : dégâts, setAttackedBy(null), et à la mort un
-- premier OnZombieDead direct ; die() suit (ZombieOnGroundState) : second OnZombieDead par Kill(getAttackedBy()).
BURN_DAMAGE = 0.02
local rawUpdate = H.updateZombies
H.updateZombies = function()
    local snapshot = {}
    for i, zb in ipairs(H.zombieList.items) do snapshot[i] = zb end
    for _, zb in ipairs(snapshot) do
        if zb.onFire and not zb:isDead() then
            zb.health = (rawget(zb, 'health') or 1) - BURN_DAMAGE
            zb.attackedBy = nil
            if zb:isDead() then
                H.trigger('OnZombieDead', zb)
                zb:die()
            end
        end
    end
    rawUpdate()
end
function TAGGED(id)
    local n = 0
    for _, zb in ipairs(H.zombieList.items) do
        if not zb:isDead() and zb:hasModData() and zb:getModData().lkNpcId == id then n = n + 1 end
    end
    return n
end
'''


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Base(unittest.TestCase):
    mode = 'mp'
    debug = True

    def setUp(self):
        self.h = self.make()

    def tearDown(self):
        self.h.close()

    def make(self, root=None):
        h = Harness(mode=self.mode, clients=getattr(self, 'clients', ('A', 'B')), debug=self.debug, root=root,
                    lua_roots=[DEV_LUA])
        names = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in names:
            h.load(m, DOUBLES)
            for path in SHARED:
                h.load(m, path)
            if m != 'server':
                h.load(m, 'client/LivingKnox/LK_Client.lua')
            # Toute machine charge media/lua/server (client MP compris) : le fichier lui-même s'y arrête ou refuse.
            for path in ('server/LivingKnox/LK_Store.lua', 'server/LivingKnox/LK_Bodies.lua',
                         'server/LivingKnox/LK_Server.lua'):
                h.load(m, path)
        h.move_player('A', 100, 100, 0)
        return h

    @property
    def srv(self):
        return 'solo' if self.mode == 'solo' else 'server'

    def init(self, new_world=False, h=None):
        (h or self.h).fire(self.srv, 'OnInitGlobalModData', new_world)

    def ev(self, code, m=None):
        return self.h.eval(m or self.srv, code)

    def run_lua(self, code, m=None):
        return self.h.load(m or self.srv, code)

    def spawn(self, x=102, y=102, z=0, profile='{}'):
        # LK13-T10 : chaque création du banc est faite dans sa propre image ; écriture différée de fin d'image ici.
        out = self.run_lua(f'return LivingKnox.Bodies.spawn({profile}, {x}, {y}, {z})')
        self.run_lua('LivingKnox.Store.onTick()')
        return out

    def calls(self, m=None):
        return lua_list(self.h.eval(m or self.srv, 'CALLS'))

    def lk(self, m=None):
        return [line for line in self.h.logs(m or self.srv) if line.startswith('[LivingKnox]')]

    def registry_files(self, h=None):
        folder = (h or self.h).file_root(self.srv) / 'batman_RadioSurvivor' / 'livingknox'
        return sorted(folder.glob('registry-*.txt')) if folder.exists() else []

    def same(self, a, b):
        g = self.h.server.g
        g.SAME_A, g.SAME_B = a, b
        return self.ev('rawequal(SAME_A, SAME_B)')

    def scan_ticks(self, slices=1):
        self.h.tick(slices * self.ev('LivingKnox.Bodies.SCAN_EVERY'))


class CreationTests(Base):
    def test_spawn_reanimates_a_tagged_clean_body_and_saves_the_registry(self):
        self.init()
        npc_id, body = self.spawn(profile='{ look = "manFairBeard" }')
        self.assertEqual(npc_id, 'lk-1')
        variant = self.ev('LivingKnox.Store.data().npcs["lk-1"].profile.variant')
        calls = [c for c in self.calls() if not c.startswith('removeFromSquare')]
        self.assertEqual(calls, ['addZombiesInOutfit:Generic01:0', f'dress:{11 * 65536 + variant}', 'clearAttachedItems',
                                 'DoZombieInventory:1000', 'createCorpse:zombie:1000', 'removeFromWorld:1000',
                                 'reanimate'])
        self.assertTrue(body.reanimated)
        md = self.ev('getCell():getZombieList():get(0):getModData()')
        self.assertEqual((md.lkNpcId, md.lkNpcGen), ('lk-1', 1))
        self.assertIs(body.useless, True)
        self.assertEqual(body.hv.skin, 'MaleBody01')  # préréglage clean avant le cadavre
        self.assertEqual(self.ev('getCell():getZombieList():get(0):getHumanVisual():getBodyVisuals():size()'), 0)
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 1)  # zombie temporaire parti
        self.assertEqual(self.ev('getCell():getGridSquare(102, 102, 0):getStaticMovingObjects():size()'), 0)
        self.assertEqual(self.ev('#PARKED'), 0)
        self.assertEqual(self.ev('(LivingKnox.Bodies.find("lk-1")) == getCell():getZombieList():get(0)'), True)
        npc = self.ev('LivingKnox.Store.data().npcs["lk-1"]')
        self.assertEqual((npc.state, npc.generation, npc.profile.outfit, npc.profile.female), ('embodied', 1, 'Generic01', False))
        self.assertEqual((npc.want.x, npc.want.y, npc.want.z), (102, 102, 0))
        files = self.registry_files()
        self.assertEqual(len(files), 1)
        self.assertRegex(files[0].read_text(encoding='utf-8'), r'^LKREG1=1\n[0-9a-f]+\n\d+\nend\n$')
        self.assertTrue(any('INFO npc lk-1 embodied (generation 1) at 102,102,0' in line for line in self.lk()))

    def test_female_profile_and_validation(self):
        self.init()
        npc_id, body = self.spawn(profile='{ female = true, outfit = "Generic03" }')
        self.assertEqual(npc_id, 'lk-1')
        self.assertIn('addZombiesInOutfit:Generic03:100', self.calls())
        self.assertRegex(body.hv.skin, r'^FemaleBody0[1-5]$')
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].profile.outfit'), 'Generic03')
        for bad in ('{ outfit = "Police" }', '{ female = "yes" }', '{ preset = "zombie" }', '{ hat = 1 }'):
            npc_id, why = self.spawn(profile=bad)
            self.assertIsNone(npc_id, bad)
            self.assertIsInstance(why, str)
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 2)

    def test_unloaded_square_is_refused_and_creates_nothing(self):
        self.init()
        self.run_lua('UNLOAD(90, 120, 90, 120)')
        npc_id, why = self.spawn()
        self.assertIsNone(npc_id)
        self.assertEqual(why, 'square 102,102,0 is not loaded')
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 1)

    def test_failed_reanimation_leaves_no_corpse_and_no_npc(self):
        self.init()
        self.run_lua('FAIL_REANIMATE = true')
        npc_id, why = self.spawn()
        self.assertIsNone(npc_id)
        self.assertEqual(why, 'reanimate returned nil')
        self.assertIn('removeCorpse:false', self.calls())
        self.assertEqual(self.ev('getCell():getGridSquare(102, 102, 0):getStaticMovingObjects():size()'), 0)
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 0)
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"]'))
        self.run_lua('FAIL_REANIMATE = false')
        self.assertEqual(self.spawn()[0], 'lk-2')  # numéro consommé, jamais réattribué

    def test_temporary_zombie_gone_before_the_call_returns_and_body_descriptor(self):
        """LK03-T06 : zombie temporaire créé puis retiré dans le même appel (jamais présent à un envoi réseau,
        NetworkZombiePacker.postupdate après le Lua) ; corps = joueur réanimé à descripteur partagé, dont
        l'identifiant de tenue change au retour de chunk (SharedDescriptors.java:44-96, ReanimatedPlayers.java:63)."""
        self.init()
        _, body = self.spawn()
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 1)
        self.assertIsNone(self.ev('HARNESS.zombies[1000]'))
        first = body.outfitId
        self.assertEqual(first, 98 * 65536 + 1)
        self.run_lua('UNLOAD(90, 120, 90, 120)')
        self.assertEqual(self.ev('next == nil and DESC_SLOTS[0] == nil'), True)  # emplacement rendu au départ
        _, other = self.spawn(110, 130)                                           # repris par un autre corps
        self.assertEqual(other.outfitId, first)
        self.run_lua('RELOAD()')
        self.assertEqual(body.outfitId, 98 * 65536 + 2)                          # nouveau descripteur au retour

    def test_disabled_guard_creates_nothing_and_leaves_bodies_alone(self):
        self.init()
        self.run_lua('NEW_ZOMBIE(110, 110, 0, true, { lkNpcId = "lk-7", lkNpcGen = 1 })')
        self.run_lua('SandboxVars = { LivingKnox = { Enabled = false } }')
        npc_id, why = self.spawn()
        self.assertIsNone(npc_id)
        self.assertEqual(why, 'Living Knox is disabled (sandbox)')
        self.scan_ticks(3)
        self.assertEqual(self.ev('TAGGED("lk-7")'), 1)  # orphelin laissé tant que le moteur est coupé
        self.assertEqual([c for c in self.calls() if c.startswith('addZombiesInOutfit')], [])
        self.run_lua('SandboxVars = nil')
        self.scan_ticks(1)
        self.assertEqual(self.ev('TAGGED("lk-7")'), 0)

    def test_mp_client_creates_nothing(self):
        self.init()
        for c in ('A', 'B'):
            npc_id, why = self.h.load(c, 'return LivingKnox.Bodies.spawn({}, 102, 102, 0)')
            self.assertIsNone(npc_id, c)
            self.assertEqual(why, 'not the authority (MP client)')
            self.assertEqual(self.h.eval(c, '(LivingKnox.Bodies.despawn("lk-1"))'), False)
            self.assertEqual(self.calls(c), [])
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Server'))
            self.h.fire(c, 'OnInitGlobalModData', False)  # aucun abonné côté client
            self.assertFalse((self.h.file_root(c) / 'batman_RadioSurvivor').exists(), c)
        self.h.tick(40)
        for c in ('A', 'B'):
            self.assertEqual(self.calls(c), [], c)


class BindingTests(Base):
    def test_round_trip_out_of_the_loaded_area_keeps_the_binding(self):
        self.init()
        self.spawn()
        before = self.ev('(LivingKnox.Bodies.find("lk-1"))')
        self.run_lua('UNLOAD(96, 200, 96, 200)')
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.find("lk-1")'), (None, 'embodied'))
        self.assertEqual(self.ev('#PARKED'), 1)
        self.scan_ticks(2)
        self.run_lua('RELOAD()')
        self.scan_ticks(1)
        found, how = self.run_lua('return LivingKnox.Bodies.find("lk-1")')
        self.assertEqual(how, 'bound')
        self.assertTrue(self.same(found, before))  # même objet Java, nouvel onlineID
        self.assertNotEqual(found.onlineID, 1001)
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)

    def test_rebinding_when_the_cached_object_is_gone(self):
        self.init()
        self.spawn()
        self.run_lua('LivingKnox.Bodies.bound["lk-1"] = nil')
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.find("lk-1")')[1], 'embodied')
        self.run_lua('getCell():getZombieList():get(0):setUseless(false)')
        self.scan_ticks(1)
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.find("lk-1")')[1], 'bound')
        self.assertIs(self.ev('getCell():getZombieList():get(0)').useless, True)  # useless réappliqué
        self.assertTrue(any('npc lk-1 bound to its body (generation 1)' in line for line in self.lk()))

    def test_restart_rereads_the_registry_and_rebinds_bodies_from_reanimated_bin(self):
        self.init()
        self.spawn(102, 102)
        self.spawn(104, 102)
        self.run_lua('UNLOAD(103, 200, 90, 200)')  # lk-2 mis de côté au moment de la sauvegarde
        entries = [{'x': e.x, 'y': e.y, 'z': e.z, 'female': e.female, 'md': dict(e.md.items())}
                   for e in lua_list(self.ev('SAVE_REANIMATED()'))]
        self.assertEqual(len(entries), 2)
        root = self.h.root
        self.h._tmp = None  # le dossier de fichiers survit au « redémarrage »
        self.h.close()
        self.h = self.make(root=root)
        try:
            self.init()
            self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 3)
            self.assertEqual(self.run_lua('return LivingKnox.Bodies.find("lk-1")'), (None, 'embodied'))
            # corps relus de reanimated.bin, remis en monde au chargement de leur chunk
            self.h.server.g.LOAD_REANIMATED(self.h.server.to_lua(entries))
            self.scan_ticks(1)
            for npc_id in ('lk-1', 'lk-2'):
                z, how = self.run_lua(f'return LivingKnox.Bodies.find("{npc_id}")')
                self.assertEqual(how, 'bound', npc_id)
                self.assertIs(z.useless, True, npc_id)
                self.assertEqual(self.ev(f'TAGGED("{npc_id}")'), 1)
            self.assertEqual(self.spawn(106, 106)[0], 'lk-3')  # identifiant jamais réutilisé
        finally:
            shutil.rmtree(root, ignore_errors=True)


class DuplicateAndOrphanTests(Base):
    def raw(self, npc_id, gen, x=103, y=103):
        return self.run_lua(f'return LivingKnox.Bodies.createBody(getCell():getGridSquare({x}, {y}, 0), '
                            f'LivingKnox.Identity.normalizeProfile({{}}), "{npc_id}", {gen})')

    def test_duplicate_of_the_current_generation_is_removed_and_the_bound_body_kept(self):
        self.init()
        _, body = self.spawn()
        dup = self.raw('lk-1', 1)
        self.assertEqual(self.ev('TAGGED("lk-1")'), 2)
        self.scan_ticks(1)
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)
        self.assertTrue(self.same(self.ev('(LivingKnox.Bodies.find("lk-1"))'), body))
        calls = self.calls()
        self.assertLess(calls.index(f'setHealth:0:{dup.onlineID}'), calls.index(f'removeFromWorld:{dup.onlineID}'))
        self.assertEqual(self.ev('#PARKED'), 0)  # tué avant retrait : pas mis de côté
        self.assertTrue(any('duplicate of lk-1 generation 1' in line for line in self.lk()))

    def test_parked_duplicate_returning_after_a_rebind_is_removed(self):
        self.init()
        _, body = self.spawn()
        self.run_lua('UNLOAD(96, 200, 96, 200)')
        dup = self.raw('lk-1', 1, 50, 50)  # même étiquette ailleurs pendant que l'original est hors zone
        self.scan_ticks(1)
        self.assertTrue(self.same(self.ev('(LivingKnox.Bodies.find("lk-1"))'), dup))
        self.run_lua('RELOAD()')
        self.scan_ticks(1)
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)
        self.assertTrue(self.same(self.ev('(LivingKnox.Bodies.find("lk-1"))'), dup))
        self.assertTrue(body.health is not None and body.health <= 0)

    def test_orphans_are_removed_and_other_zombies_untouched(self):
        self.init()
        self.spawn()
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (True, 1))
        _ = self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].generation'), 2)
        self.raw('lk-1', 1)                                    # génération périmée
        self.raw('lk-1', 3, 104, 104)                          # génération inconnue (en avance)
        self.raw('lk-99', 1, 105, 105)                         # identifiant inconnu
        self.spawn(106, 106)
        self.run_lua('LivingKnox.Bodies.despawn("lk-2")')
        self.raw('lk-2', 1, 107, 107)                          # PNJ virtuel : aucun corps attendu
        self.run_lua('NEW_ZOMBIE(108, 108, 0, true, {})')      # vrai joueur réanimé, sans étiquette
        self.run_lua('NEW_ZOMBIE(109, 109, 0, false, { lkNpcId = "lk-1", lkNpcGen = 1 })')  # zombie ordinaire
        self.run_lua('NEW_ZOMBIE(110, 110, 0, true, { lkNpcId = "lk-1", lkNpcGen = "x" })')  # étiquette malformée
        self.scan_ticks(1)
        self.assertEqual(self.ev('TAGGED("lk-1")'), 3)  # corps courant, zombie ordinaire, étiquette malformée
        self.assertEqual(self.ev('TAGGED("lk-99")'), 0)
        self.assertEqual(self.ev('TAGGED("lk-2")'), 0)
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 4)
        lines = '\n'.join(self.lk())
        for reason in ('orphan lk-1 generation 1: stale', 'orphan lk-1 generation 3: ahead', 'orphan lk-99 generation 1: unknown',
                       'orphan lk-2 generation 1: notEmbodied'):
            self.assertIn(reason, lines)

    def test_death_of_the_current_body_marks_the_npc_dead(self):
        self.init()
        self.spawn()
        self.run_lua('local z = (LivingKnox.Bodies.find("lk-1")); z.dead = true; HARNESS.trigger("OnZombieDead", z)')
        npc = self.ev('LivingKnox.Store.data().npcs["lk-1"]')
        self.assertEqual(npc.state, 'dead')
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.find("lk-1")'), (None, 'dead'))
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.embody("lk-1", 102, 102, 0)')[1], 'npc lk-1 is dead')


    def test_death_of_a_group_member_is_published_with_its_body(self):
        """E08-T07 : fait memberDied (corps présent) pour un membre de groupe ; un PNJ sans groupe ne publie rien."""
        self.init()
        self.spawn()
        self.spawn(104, 104)
        self.run_lua('''
            PUB = {}
            LivingKnox.listen("memberDied", "test", function(i) PUB[#PUB + 1] = i end)
            LivingKnox.Groups = { today = function() return 4 end,
                findNpc = function(id) if id == "lk-1" then return "grp-1", "m-2" end end }
            local z = (LivingKnox.Bodies.find("lk-1")); z.dead = true; HARNESS.trigger("OnZombieDead", z)
            BODY1 = z
            local z2 = (LivingKnox.Bodies.find("lk-2")); z2.dead = true; HARNESS.trigger("OnZombieDead", z2)
            LivingKnox.Groups = nil
        ''')
        self.assertEqual(self.ev('#PUB'), 1)
        info = self.ev('PUB[1]')
        self.assertEqual((info.group, info.member, info.npc, info.day, info.offscreen), ('grp-1', 'm-2', 'lk-1', 4, False))
        self.assertTrue(self.ev('rawequal(PUB[1].body, BODY1)'))
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-2"].state'), 'dead')

class KillerTests(Base):
    """E04-T06 : cause de la mort et tueur probable, établis sur l'autorité (LivingKnox.Bodies.deathCause). Doublures
    du chemin Java 42.21.0 : Hit (OnHitZombie avant les dégâts, setAttackedBy, coup mortel -> die/Kill), santé
    envoyée par le client propriétaire (die() sur le serveur), véhicule (setAttackedBy du conducteur, sans
    OnHitZombie), chute et feu (setAttackedBy(null), double OnZombieDead du feu). Références dans DOUBLES."""

    def setUp(self):
        super().setUp()
        self.init()
        self.id_, _ = self.spawn()
        self.run_lua('DIED = {}; LivingKnox.Bodies.onDied = function(id, z, c) DIED[#DIED + 1] = { id = id, c = c } end')

    def body(self):
        return self.run_lua(f'return (LivingKnox.Bodies.find("{self.id_}"))')

    def hit(self, user, weapon, damage, npc=None):
        self.run_lua(f'local z = (LivingKnox.Bodies.find("{npc or self.id_}")); '
                     f'z:Hit(instanceItem("{weapon}"), HARNESS.players["{user}"], {damage}, false, 1.0)')

    def death(self, npc=None):
        d = self.ev(f'LivingKnox.Store.data().npcs["{npc or self.id_}"].death')
        return None if d is None else {k: d[k] for k in ('cause', 'killer', 'weapon', 'burning')}

    def state(self):
        return self.ev(f'LivingKnox.Store.data().npcs["{self.id_}"].state')

    def died(self):
        return [(c.id, c.c.cause, c.c.killer) for c in lua_list(self.ev('DIED'))]

    def test_lethal_melee_hit_is_attributed_to_the_player_with_the_weapon(self):
        self.hit('A', 'Base.BaseballBat', 0.4)
        self.assertEqual(self.state(), 'embodied')
        self.hit('A', 'Base.BaseballBat', 2)
        self.assertEqual(self.state(), 'dead')
        self.assertEqual(self.death(), {'cause': 'melee', 'killer': 'A', 'weapon': 'Base.BaseballBat', 'burning': None})
        self.assertEqual(self.died(), [(self.id_, 'melee', 'A')])
        self.assertTrue(any('died (generation 1): cause melee, killer A, weapon Base.BaseballBat' in line
                            for line in self.lk()))
        self.assertIsNone(self.ev(f'LivingKnox.Bodies.lastHits["{self.id_}"]'))

    def test_firearm_and_explosive(self):
        self.hit('A', 'Base.Pistol', 5)
        self.assertEqual(self.death(), {'cause': 'firearm', 'killer': 'A', 'weapon': 'Base.Pistol', 'burning': None})
        npc2, _ = self.spawn(104, 104)
        self.hit('B', 'Base.PipeBomb', 5, npc2)
        self.assertEqual(self.death(npc2), {'cause': 'fire', 'killer': 'B', 'weapon': 'Base.PipeBomb', 'burning': None})

    def test_last_lethal_hitter_wins(self):
        self.hit('A', 'Base.BaseballBat', 0.5)
        self.hit('B', 'Base.BaseballBat', 2)
        self.assertEqual(self.death()['killer'], 'B')

    def test_trap_without_thrower_and_fall_are_not_attributed(self):
        # Piège à minuterie : attaquant = faux zombie (IsoTrap.java:784) ; OnHitZombie l'ignore.
        self.run_lua(f'local z = (LivingKnox.Bodies.find("{self.id_}")); '
                     'z:Hit(instanceItem("Base.PipeBomb"), NEW_ZOMBIE(0, 0, 0, false), 5, false, 1.0)')
        self.assertEqual(self.death(), {'cause': 'other', 'killer': None, 'weapon': None, 'burning': None})
        npc2, _ = self.spawn(104, 104)
        self.run_lua(f'local z = (LivingKnox.Bodies.find("{npc2}")); FALL(z, 5); z:die()')
        self.assertEqual(self.death(npc2), {'cause': 'unknown', 'killer': None, 'weapon': None, 'burning': None})

    def test_owner_reported_death_needs_a_recent_hit_of_the_same_player(self):
        # Coup sans effet puis santé nulle envoyée par le client propriétaire : getAttackedBy est encore le joueur.
        self.hit('A', 'Base.BaseballBat', 0.1)
        self.h.advance_ms(4000)
        self.run_lua(f'CLIENT_HEALTH((LivingKnox.Bodies.find("{self.id_}")), 0)')
        self.assertEqual(self.death()['cause'], 'melee')
        self.assertEqual(self.death()['killer'], 'A')
        npc2, _ = self.spawn(104, 104)
        self.hit('A', 'Base.BaseballBat', 0.1, npc2)
        self.h.advance_ms(self.ev('LivingKnox.Bodies.HIT_WINDOW_MS') + 1)
        self.run_lua(f'CLIENT_HEALTH((LivingKnox.Bodies.find("{npc2}")), 0)')
        self.assertEqual(self.death(npc2), {'cause': 'other', 'killer': None, 'weapon': None, 'burning': None})

    def test_vehicle_driver_is_attributed_a_passenger_is_not(self):
        self.run_lua(f'local z = (LivingKnox.Bodies.find("{self.id_}")); local a = HARNESS.players["A"]; '
                     'VEHICLE(a); VEHICLE_HIT(z, a, 5); CLIENT_HEALTH(z, 0)')
        self.assertEqual(self.death(), {'cause': 'vehicle', 'killer': 'A', 'weapon': None, 'burning': None})
        npc2, _ = self.spawn(104, 104)
        # B passager, A au volant : un attaquant passager n'est pas retenu.
        self.run_lua(f'local z = (LivingKnox.Bodies.find("{npc2}")); local a, b = HARNESS.players["A"], '
                     'HARNESS.players["B"]; VEHICLE(a, b); VEHICLE_HIT(z, b, 5); CLIENT_HEALTH(z, 0)')
        self.assertEqual(self.death(npc2), {'cause': 'other', 'killer': None, 'weapon': None, 'burning': None})

    def test_fire_kills_once_without_a_killer_even_after_a_hit(self):
        self.hit('A', 'Base.BaseballBat', 0.1)
        self.h.advance_ms(6000)
        self.run_lua(f'(LivingKnox.Bodies.find("{self.id_}")):SetOnFire()')
        for _ in range(60):
            self.h.tick()
            if self.state() == 'dead':
                break
        self.assertEqual(self.death(), {'cause': 'fire', 'killer': None, 'weapon': None, 'burning': True})
        self.assertEqual(self.died(), [(self.id_, 'fire', None)])
        self.assertEqual(sum(f'npc {self.id_} died' in line for line in self.lk()), 1)

    def test_burning_body_killed_by_a_hit_keeps_the_hitter_and_the_burning_flag(self):
        self.run_lua(f'(LivingKnox.Bodies.find("{self.id_}")):SetOnFire()')
        self.hit('A', 'Base.BaseballBat', 5)
        self.assertEqual(self.death(), {'cause': 'melee', 'killer': 'A', 'weapon': 'Base.BaseballBat',
                                        'burning': True})

    def test_hits_on_other_zombies_and_on_clients_are_ignored(self):
        self.run_lua('local v = NEW_ZOMBIE(110, 110, 0, false); '
                     'v:Hit(instanceItem("Base.BaseballBat"), HARNESS.players["A"], 0.1, false, 1.0)')
        n = self.run_lua('local c = 0; for _ in pairs(LivingKnox.Bodies.lastHits) do c = c + 1 end; return c')
        self.assertEqual(n, 0)
        # Client MP : copie du corps, coup local : rien n'est relevé ni écrit.
        self.h.load('A', f'local z = NEW_ZOMBIE(102, 102, 0, true, {{ lkNpcId = "{self.id_}", lkNpcGen = 1 }}); '
                         'z:Hit(instanceItem("Base.BaseballBat"), HARNESS.localPlayer, 5, false, 1.0); '
                         'HARNESS.trigger("OnZombieDead", z)')
        self.assertIsNone(self.h.eval('A', f'LivingKnox.Bodies.lastHits["{self.id_}"]'))
        self.assertEqual(self.state(), 'embodied')
        self.assertEqual([line for line in self.lk('A') if 'died' in line], [])

    def test_listener_error_is_logged_and_the_death_kept(self):
        self.run_lua('LivingKnox.Bodies.onDied = function() error("boom") end')
        self.hit('A', 'Base.BaseballBat', 5)
        self.assertEqual(self.state(), 'dead')
        self.assertTrue(any('death listener failed' in line for line in self.lk()))

    def test_death_survives_a_restart_and_a_bad_death_is_refused(self):
        self.hit('A', 'Base.Pistol', 5)
        root = self.h.root
        self.h._tmp = None  # le dossier de fichiers survit au « redémarrage »
        self.h.close()
        self.h = self.make(root=root)
        self.init()
        d = self.ev(f'LivingKnox.Store.data().npcs["{self.id_}"].death')
        self.assertEqual((d.cause, d.killer, d.weapon), ('firearm', 'A', 'Base.Pistol'))
        for bad in ('{ cause = "poison" }', '{ cause = "melee", killer = "" }', '{ cause = "melee", weapon = "bat" }',
                    '{ cause = "fire", burning = false }', '"melee"'):
            self.assertFalse(self.run_lua(f'return (LivingKnox.Identity.validDeath({bad}))'), bad)
        why = self.run_lua(f'local d = LivingKnox.Store.data(); d.npcs["{self.id_}"].death = {{ cause = "poison" }}; '
                           'local _, w = LivingKnox.Identity.validate(d); return w')
        self.assertIn('bad death cause', why)


    def test_suite_rs_killer_passes_on_the_doubles(self):
        if self.mode != 'solo':
            return
        self.run_lua('LivingKnox.Bodies.onDied = nil')
        self.h.load('solo', 'shared/RST/suites/RS_Killer.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "rs.killer", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'rs.killer')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertEqual(listed.count, 5)
        self.assertIsNone(listed.error)
        # Les corps réanimés des doublures restent couchés : debout dès l'image suivante.
        self.run_lua('Events.OnTick.Add(function() for _, zb in ipairs(HARNESS.zombieList.items) do '
                     'zb.onFloor = false end end)')
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "rs.killer", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(3000):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 5, results)
        self.assertTrue(report.ok, results)
        self.assertIsNone(self.ev('LivingKnox.Bodies.onDied'))  # écouteur rendu
        self.assertEqual(self.ev('#LivingKnox.Bodies.list()'), 1)  # seul le PNJ du setUp reste
        measures = [line for line in self.h.logs('solo') if line.startswith('[RSK] measure')]
        self.assertTrue(any('stale: cause other, killer nil' in line for line in measures), measures)

class KillerSoloTests(KillerTests):
    """Même règle en solo (Kill(arme, attaquant) au coup mortel, IsoGameCharacter.java:5843-5844)."""
    mode = 'solo'

    # Doublures multijoueur (client propriétaire, second joueur, client MP) : sans objet en solo.
    test_owner_reported_death_needs_a_recent_hit_of_the_same_player = None
    test_vehicle_driver_is_attributed_a_passenger_is_not = None
    test_hits_on_other_zombies_and_on_clients_are_ignored = None
    test_last_lethal_hitter_wins = None
    test_firearm_and_explosive = None


class FreeSquareTests(Base):
    """LK02-T11 : un corps naît couché et ne se relève pas tant qu'un personnage debout est sur sa case ou une voisine
    (IsoGameCharacter.isBeingSteppedOn, IsoGameCharacter.java:10240-10258 ; ZombieOnGroundState.java:107-111).
    Doublures : getMovingObjects (liste vivante de la case), isOnFloor (IsoMovingObject.java:2038), getVehicle,
    isFree(false) (IsoGridSquare.java:2894-2915 : self.blocked = impraticable). Le corps réanimé naît couché
    (onFloor = vrai, IsoDeadBody.reanimate) ; LK02-T14 le remet debout aussitôt, la règle reste pour une remise
    debout impossible et pour les copies des clients MP (LK_Stand.lua)."""

    def last(self, npc_id):
        p = self.ev(f'LivingKnox.Store.data().npcs["{npc_id}"].last')
        return (p.x, p.y, p.z)

    def want(self, npc_id):
        p = self.ev(f'LivingKnox.Store.data().npcs["{npc_id}"].want')
        return (p.x, p.y, p.z)

    def standing_near(self, x, y):
        """Personnages debout sur la case (x, y) ou une voisine, hors corps eux-mêmes (joueurs réanimés)."""
        return self.ev(f'(function() local n = 0 for dy = -1, 1 do for dx = -1, 1 do '
                       f'local l = getCell():getGridSquare({x} + dx, {y} + dy, 0):getMovingObjects() '
                       f'for i = 0, l:size() - 1 do local o = l:get(i) '
                       f'if not o:isOnFloor() and o:getVehicle() == nil and not rawget(o, "reanimated") then '
                       f'n = n + 1 end end end end return n end)()')

    def test_two_npcs_on_the_same_square_get_distinct_squares_away_from_standing_characters(self):
        self.init()
        self.run_lua('NEW_ZOMBIE(130.5, 130.5, 0, false)')  # zombie ordinaire debout sur la case voulue
        first, _ = self.spawn(130, 130)
        second, _ = self.spawn(130, 130)
        self.assertEqual((first, second), ('lk-1', 'lk-2'))
        a, b = self.last('lk-1'), self.last('lk-2')
        self.assertEqual(self.want('lk-1'), (130, 130, 0))  # position demandée gardée
        self.assertEqual(self.want('lk-2'), (130, 130, 0))
        self.assertNotEqual(a, b)
        self.assertGreaterEqual(max(abs(a[0] - 130), abs(a[1] - 130)), 2, a)  # loin du zombie debout
        self.assertLessEqual(max(abs(a[0] - 130), abs(a[1] - 130)), 2, a)  # la plus proche
        self.assertGreaterEqual(max(abs(a[0] - b[0]), abs(a[1] - b[1])), 2, (a, b))  # le premier se relèvera
        self.assertGreaterEqual(max(abs(b[0] - 130), abs(b[1] - 130)), 2, b)
        for x, y, _ in (a, b):
            self.assertEqual(self.standing_near(x, y), 0, (x, y))
        lines = '\n'.join(self.lk())
        self.assertIn(f'npc lk-1 embodied (generation 1) at {a[0]},{a[1]},0 (wanted 130,130,0)', lines)

    def test_standing_player_and_blocked_square_are_avoided(self):
        self.init()
        self.h.move_player('A', 120, 120, 0)
        self.run_lua('getCell():getGridSquare(122, 120, 0).blocked = true')  # mur ou meuble plein
        npc_id, _ = self.spawn(121, 120)
        self.assertEqual(npc_id, 'lk-1')
        x, y, _ = self.last('lk-1')
        self.assertGreaterEqual(max(abs(x - 120), abs(y - 120)), 2)
        self.assertNotEqual((x, y), (122, 120))
        self.assertEqual(self.want('lk-1'), (121, 120, 0))

    def test_plants_and_campfires_are_avoided_at_creation(self):
        """LK04-T06 : ni sur une plante cultivée ou un feu de camp (allumé ou non), ni à côté (HAZARD_AVOID)."""
        self.init()
        self.run_lua('getCell():getGridSquare(170, 170, 0).plant = { state = "seeded" }')
        self.run_lua('getCell():getGridSquare(172, 169, 0).campfire = { isLit = false }')
        npc_id, _ = self.spawn(170, 170)
        self.assertEqual(npc_id, 'lk-1')
        x, y, _ = self.last('lk-1')
        self.assertGreaterEqual(max(abs(x - 170), abs(y - 170)), 2, (x, y))
        self.assertGreaterEqual(max(abs(x - 172), abs(y - 169)), 2, (x, y))
        self.assertLessEqual(max(abs(x - 170), abs(y - 170)), 2, (x, y))   # la plus proche
        self.assertEqual(self.want('lk-1'), (170, 170, 0))
        self.assertEqual(self.ev('(LivingKnox.Bodies.hazardNear(171, 170, 0, 1))'), 'farming plant')
        self.assertEqual(self.ev('(select(2, LivingKnox.Bodies.hazardNear(173, 169, 0, 1)))'), 172)
        self.assertIsNone(self.ev('LivingKnox.Bodies.hazardNear(175, 175, 0, 1)'))

    def test_campfire_unseen_on_an_mp_client(self):
        """getCampfire / hasLitCampfire : SGlobalObjects seulement (IsoGridSquare.java:9740-9765)."""
        self.h.load('A', 'getCell():getGridSquare(10, 10, 0).campfire = { isLit = true }; '
                         'getCell():getGridSquare(11, 10, 0).plant = true')
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Bodies.hazardOn(getCell():getGridSquare(10, 10, 0))'))
        self.assertEqual(self.h.eval('A', 'LivingKnox.Bodies.hazardOn(getCell():getGridSquare(11, 10, 0))'),
                         'farming plant')

    def test_lying_or_driving_character_does_not_prevent(self):
        self.init()
        self.run_lua('local z = NEW_ZOMBIE(140.5, 140.5, 0, false); z.onFloor = true')  # zombie couché, sans étiquette
        self.run_lua('local z = NEW_ZOMBIE(141.5, 140.5, 0, false); z.vehicle = {}')     # personnage en véhicule
        self.spawn(140, 140)
        self.assertEqual(self.last('lk-1'), (140, 140, 0))

    def test_embody_also_moves_to_a_free_square(self):
        self.init()
        self.spawn(150, 150)
        self.run_lua('LivingKnox.Bodies.despawn("lk-1")')
        self.run_lua('NEW_ZOMBIE(150.5, 151.5, 0, false)')
        z = self.run_lua('return LivingKnox.Bodies.embody("lk-1", 150, 150, 0)')
        self.assertIsNotNone(z)
        x, y, _ = self.last('lk-1')
        self.assertGreaterEqual(max(abs(x - 150), abs(y - 151)), 2)
        self.assertEqual(self.want('lk-1'), (150, 150, 0))

    def test_refused_when_every_square_is_next_to_a_standing_character(self):
        self.init()
        radius = self.ev('LivingKnox.Bodies.FREE_RADIUS')
        span = radius + 2
        self.run_lua(f'for x = 160 - {span}, 160 + {span}, 3 do for y = 160 - {span}, 160 + {span}, 3 do '
                     f'NEW_ZOMBIE(x + 0.5, y + 0.5, 0, false) end end')
        before = self.calls()
        npc_id, why = self.spawn(160, 160)
        self.assertIsNone(npc_id)
        self.assertEqual(why, f'no free square within {radius} of 160,160,0 '
                              '(loaded, walkable, no standing character, farming plant or campfire on it or next to it)')
        self.assertEqual(self.calls(), before)  # rien créé
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 1)  # aucun numéro consommé
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"]'))


class DespawnTests(Base):
    def test_despawn_then_forget(self):
        self.init()
        self.spawn()
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (True, 1))
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 0)
        self.assertEqual(self.ev('#PARKED'), 0)
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].state'), 'virtual')
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1", true)'), (True, 0))
        self.assertIsNone(self.ev('LivingKnox.Store.data().npcs["lk-1"]'))
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (False, 'unknown npc lk-1'))
        self.assertEqual(self.spawn()[0], 'lk-2')
        listed = lua_list(self.ev('LivingKnox.Bodies.list()'))
        self.assertEqual([(e.id, e.generation, e.state, e.inWorld) for e in listed], [('lk-2', 1, 'embodied', True)])

    def test_despawn_of_a_body_out_of_the_loaded_area(self):
        self.init()
        self.spawn()
        self.run_lua('UNLOAD(96, 200, 96, 200)')
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.despawn("lk-1")'), (True, 0))
        self.run_lua('RELOAD()')
        self.scan_ticks(1)
        self.assertEqual(self.ev('TAGGED("lk-1")'), 0)  # retiré comme orphelin à son retour


class StoreTests(Base):
    def write_slot(self, slot, seq, data_lua):
        self.run_lua(f'''
            local Codec = require "RadioSurvivor/RS_Codec"
            local body = Codec.encodeBytes({data_lua})
            local w = getFileWriter(LivingKnox.Store.state.path .. "-{slot}.txt", true, false)
            w:write("LKREG1={seq}\\n" .. Codec.hexBytes(body) .. "\\n" .. Codec.checksumBytes(body) .. "\\nend\\n")
            w:close()''')

    def test_unknown_schema_is_refused_and_nothing_is_touched(self):
        self.init()
        self.write_slot(0, 5, '{ schema = 3, nextId = 4, npcs = {} }')
        before = self.registry_files()[0].read_text(encoding='utf-8')
        self.run_lua('NEW_ZOMBIE(110, 110, 0, true, { lkNpcId = "lk-1", lkNpcGen = 1 })')
        self.init()
        self.assertEqual(self.ev('(LivingKnox.Store.isBlocked())'), True)
        npc_id, why = self.spawn()
        self.assertIsNone(npc_id)
        self.assertIn('registry unavailable: unknown registry schema 3', why)
        self.scan_ticks(2)
        self.assertEqual(self.ev('TAGGED("lk-1")'), 1)  # rien retiré sans registre
        self.assertEqual(self.registry_files()[0].read_text(encoding='utf-8'), before)
        self.assertTrue(any('ERROR registry BLOCKED: unknown registry schema 3' in line for line in self.lk()))

    def test_newest_valid_slot_wins_and_a_corrupt_slot_is_skipped(self):
        self.init()
        self.spawn()   # emplacement 1 (#1)
        self.spawn(104, 102)  # emplacement 0 (#2)
        files = self.registry_files()
        self.assertEqual(len(files), 2)
        slot0 = [f for f in files if f.name.endswith('-0.txt')][0]
        slot0.write_text(slot0.read_text(encoding='utf-8').replace('end\n', 'en'), encoding='utf-8')
        self.init()
        self.assertEqual(self.ev('LivingKnox.Store.isReady()'), True)
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 2)  # repli sur #1
        self.assertEqual(self.ev('LivingKnox.Store.state.seq'), 1)

    def test_both_slots_unreadable_block_the_registry(self):
        self.init()
        self.spawn()
        self.spawn(104, 102)
        for f in self.registry_files():
            f.write_text('garbage\n', encoding='utf-8')
        self.init()
        self.assertEqual(self.ev('(LivingKnox.Store.isBlocked())'), True)
        self.assertEqual(self.run_lua('return LivingKnox.Bodies.spawn({}, 102, 102, 0)')[0], None)

    def test_invalid_structure_blocks(self):
        self.init()
        self.write_slot(0, 9, '{ schema = 2, nextId = 2, npcs = { ["lk-5"] = { id = "lk-5" } } }')
        self.init()
        blocked, why = self.run_lua('return LivingKnox.Store.isBlocked()')
        self.assertTrue(blocked)
        self.assertIn('bad npc identifier lk-5', why)

    def test_new_world_starts_empty_and_writes_after_the_old_files(self):
        self.init()
        self.spawn()
        self.spawn(104, 102)
        self.init(new_world=True)
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 1)
        self.assertEqual(self.ev('LivingKnox.Store.state.seq'), 3)
        self.init()
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 1)  # l'état neuf gagne au rechargement

    def test_lazy_init_after_a_lua_reset_and_positions_saved_on_save(self):
        self.spawn()  # aucun OnInitGlobalModData : rattrapage par canAct
        self.assertEqual(self.ev('LivingKnox.Store.isReady()'), True)
        self.assertEqual(self.ev('LivingKnox.Store.data().nextId'), 2)
        body = self.ev('(LivingKnox.Bodies.find("lk-1"))')
        self.h.server.g.HARNESS.place(body, 110, 102, 0)
        self.scan_ticks(1)
        self.assertEqual(self.ev('LivingKnox.Store.state.dirty'), True)
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].last.x'), 110)
        self.h.fire(self.srv, 'OnSave')
        self.assertEqual(self.ev('LivingKnox.Store.state.dirty'), False)


class ScanCostTests(Base):
    def test_one_slice_examines_at_most_the_budget(self):
        self.init()
        self.spawn()
        self.run_lua('for i = 1, 500 do NEW_ZOMBIE(150 + i % 20, 150 + math.floor(i / 20), 0, false) end')
        budget = self.ev('LivingKnox.Bodies.SCAN_BUDGET')
        every = self.ev('LivingKnox.Bodies.SCAN_EVERY')
        self.run_lua('SCANNED = 0')
        self.h.tick(every - 1)
        self.assertEqual(self.ev('SCANNED'), 0)
        self.h.tick(1)
        self.assertEqual(self.ev('SCANNED'), budget)
        self.run_lua('SCANNED = 0')
        slices = (501 + budget - 1) // budget
        self.h.tick(every * slices)
        self.assertEqual(self.ev('SCANNED'), budget * slices)
        self.assertGreaterEqual(self.ev('LivingKnox.Bodies.scanState.sweeps'), 1)


class SoloTests(Base):
    mode = 'solo'

    def test_solo_cycle_and_dev_console(self):
        self.h.load('solo', 'server/RST/RST_Server.lua')
        self.h.load('solo', 'server/RST/RST_LKBodiesServer.lua')
        self.h.load('solo', 'client/RST/RST_LKBodiesClient.lua')
        self.h.fire('solo', 'OnInitGlobalModData', True)
        self.assertIs(self.ev('LKB.spawn()'), True)
        self.assertIs(self.ev('LKB.spawn(1, 0, true)'), True)
        self.assertIs(self.ev('LKB.list()'), True)
        lines = [line for line in self.h.logs('solo') if line.startswith('[LKB]')]
        self.assertIn('[LKB] spawned lk-1 at 102,102,0', lines)
        # joueur debout en 100,100 voisin de la case voulue : case libre la plus proche (LK02-T11)
        self.assertIn('[LKB] spawned lk-2 at 102,100,0 (wanted 101,100,0)', lines)
        self.assertTrue(any(line.startswith('[LKB] lk-2 gen=1 state=embodied inWorld=true female=true') for line in lines))
        self.assertIs(self.ev('LKB.despawn(1)'), True)
        self.assertIs(self.ev('LKB.scan()'), True)
        self.assertIs(self.ev('LKB.clear()'), True)
        self.assertEqual(self.ev('getCell():getZombieList():size()'), 0)
        self.assertEqual(self.ev('#LivingKnox.Bodies.list()'), 0)
        self.assertEqual(self.h.pending(), [])
        self.run_lua('WORLD_NAME = "Muldraugh"')
        self.assertIs(self.ev('LKB.spawn()'), False)
        self.assertTrue(any('is not a test save' in line for line in self.h.logs('solo')))

    def test_suite_without_the_round_trip_passes_on_the_doubles(self):
        self.h.fire('solo', 'OnInitGlobalModData', True)
        self.h.load('solo', 'shared/RST/suites/RST_LKBodies.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.bodies", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.bodies')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertEqual(listed.count, 7)
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.bodies", tags = "world", '
                                          'test = "^[sdf]" }, { ctx = { player = getPlayer() } }))'), True)
        for _ in range(200):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 4, results)
        self.assertTrue(report.ok, results)
        self.assertEqual(self.h.eval('solo', 'getCell():getZombieList():size()'), 0)
        self.assertEqual(self.h.eval('solo', '#LivingKnox.Bodies.list()'), 0)


class MultiplayerConsoleTests(Base):
    def setUp(self):
        super().setUp()
        self.h.load('server', 'server/RST/RST_Server.lua')
        self.h.load('server', 'server/RST/RST_LKBodiesServer.lua')
        for c in ('A', 'B'):
            self.h.load(c, 'client/RST/RST_LKBodiesClient.lua')
            self.h.load(c, 'server/RST/RST_LKBodiesServer.lua')
        self.init()

    def test_request_routed_to_the_server_and_refused_without_capability(self):
        self.assertIs(self.h.eval('A', 'LKB.spawn()'), True)
        self.assertIs(self.h.eval('B', 'LKB.spawn()'), True)
        self.h.pump()
        self.assertEqual(self.ev('#LivingKnox.Bodies.list()'), 1)
        self.assertIn('[LKB] server: [LKB] spawned lk-1 at 102,102,0', self.h.logs('A'))
        self.assertTrue(any('refused: permission denied' in line for line in self.h.logs('B')))
        self.assertEqual([c for c in self.calls('A') if c.startswith('addZombies')], [])


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        for path in MOD_FILES + DEV_FILES:
            text = path.read_text(encoding='utf-8')
            code = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'{path.name}: non ASCII character in code')
            patterns = [r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'\bunpack\b']
            if path in MOD_FILES:
                patterns.append(r'getPlayer\(\)')  # aucune hypothèse de joueur local côté autorité
            for pattern in patterns:
                self.assertIsNone(re.search(pattern, code, flags=re.M), f'{path.name}: {pattern}')
        for path in DEV_FILES:
            self.assertTrue(all(b < 128 for b in path.read_bytes()), f'{path.name}: non ASCII byte')

    def test_no_global_moddata_and_no_player_command_in_the_mod(self):
        for path in MOD_FILES:
            code = path.read_text(encoding='utf-8')
            for pattern in (r'ModData\.(getOrCreate|add|get)\b', r'OnClientCommand', r'sendServerCommand'):
                self.assertIsNone(re.search(pattern, code), f'{path.name}: {pattern}')


if __name__ == '__main__':
    unittest.main()
