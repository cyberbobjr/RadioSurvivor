"""Tests hors jeu des portes et fenêtres sur le trajet des PNJ Living Knox (LK04-T02, LK04-T03, LK04-T07) :
LK_Obstacles.lua (autorité),
Directives.abort (LK_Directives.lua), attente devant une porte et arrêt sur consigne close (LK_Executor.lua).

    python RadioSurvivor/tests/test_lk_obstacles.py

Banc tests/harness.py (serveur dédié et deux clients, ou solo), doublures de test_lk_directives.py complétées ici.
Les doublures reproduisent le Java 42.21.0 relevé ; elles NE PROUVENT PAS l'API réelle, seulement la logique :
- portes IsoDoor et IsoThumpable : IsOpen, ToggleDoorSilent (bascule état seulement, refusée si barricadée,
  IsoDoor.java:1652-1666, IsoThumpable.java:1227-1240), ToggleDoor(personnage) qui bascule puis lève la NPE d'un
  non-joueur (IsoDoor.java:1292-1435 ; compté pour vérifier qu'il n'est jamais appelé), setLockedByKey(v, doSync)
  (pose aussi locked, synchronise seulement hors serveur, IsoDoor.java:1782-1797), checkKeyId, isBarricaded ;
- sync() : état absolu (ouvert, locked, lockedByKey) envoyé par le serveur à tous les clients, par un client au
  serveur qui le relaie aux autres (IsoObject.java:988-1008, IsoDoor.java:1508-1645, GameServer.java:2770-2791) ;
  rien en solo ; livré par le banc (relay_doors) ;
- IsoGridSquare:getDoorTo (bord commun de deux cases voisines, IsoGridSquare.java:3065-3111), getBuildingDef,
  getWorld():getMetaGrid():getBuildingAt(x, y, z) (IsoMetaGrid.java:271), BuildingDef:getIDString/getX/getX2... ;
- collision : la copie qui simule le corps s'arrête contre une porte fermée ou barricadée de SA copie (bPathfind et
  bMoving effacés, IsoZombie.java:1075-1091).
Fenêtres, clôtures, escaliers (LK04-T03, WINDOW_DOUBLES) :
- IsoWindow (IsOpen, isDestroyed, isLocked, isPermaLocked, isBarricaded, getIndoorSquare) et ToggleWindow(chr) :
  refus si inamovible, détruite ou barricadée, verrou ignoré, bascule, alarme sauf pour un zombie, synchronisation
  (IsoWindow.java:701-731) ; cadre IsoWindowFrame et fenêtre construite IsoThumpable (isBarricaded) ; getWindowTo,
  getWindowFrameTo, getWindowThumpableTo (IsoGridSquare.java:3131-3172, 3228-3236), TreatAsSolidFloor ;
- marche STEP_W : fenêtre fermée ou barricadée = arrêt ; fenêtre ouverte ou cassée, cadre, fenêtre construite,
  clôture basse = état climbwindow / climbfence (getActionStateName) pendant CLIMB_TICKS images, bPathfind effacé
  (PathFindState.exit) puis chemin repris de l'autre côté (ClimbThroughWindowState.java:243-262,
  ClimbOverFenceState.java:229-263) ; escalier = changement de niveau sur les cases STAIRS ; orientation du corps
  (getDirectionAngle) prise vers la case visée et recopiée sur les autres machines.
LK04-T08 : ToggleWindow refuse tout autre nombre d'arguments que 1 (Kahlua LuaJavaInvoker.java:71-80, 117-124) ;
porte basse fermée (portail, isHoppable / isTallHoppable) enjambée, jamais un arrêt (IsoZombie.java:1075, 3051-3058) ;
LANE_DOUBLES (murs WALLS, isBlockedTo, isDoorTo, isWindowTo, isHoppableTo) pour la recherche de site de lk.traversal.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import LUA, DEV_LUA, lua_list  # noqa: E402
from test_lk_directives import DirectiveBase  # noqa: E402

OBSTACLES = 'server/LivingKnox/LK_Obstacles.lua'
TRAVERSAL_SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKTraversal.lua'
TYPES = ('shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
         'shared/LivingKnox/Data/LK_Type_settlers.lua')

DOOR_DOUBLES = r'''
local H = HARNESS
local Sq = H.classes.IsoGridSquare
local Obj = H.classes.IsoObject
DOORS, BUILDINGS = {}, {}
TOGGLES, ENGINE_TOGGLES, RECALCS, CHANGED, APPLIED = 0, 0, 0, 0, 0
SYNCS = {}
local Def = H.class('BuildingDef')
function Def:getIDString() return self.id end
function Def:getID() return self.id end
function Def:getX() return self.x1 end
function Def:getY() return self.y1 end
function Def:getX2() return self.x2 end
function Def:getY2() return self.y2 end
function Def:getKeyId() return self.keyId or 77 end
local function defAt(x, y)
    for _, b in ipairs(BUILDINGS) do
        if x >= b.x1 and x < b.x2 and y >= b.y1 and y < b.y2 then return setmetatable(b, Def) end
    end
    return nil
end
function Sq:getBuildingDef() return defAt(self.x, self.y) end
function Sq:RecalcAllWithNeighbours(b) RECALCS = RECALCS + 1 end
function Sq:setSquareChanged() CHANGED = CHANGED + 1 end
local grid = { getBuildingAt = function(_, x, y, z)
    H.num(x, 'getBuildingAt'); H.num(y, 'getBuildingAt'); H.num(z, 'getBuildingAt')
    return defAt(x, y)
end }
local baseWorld = getWorld
getWorld = function()
    local w = baseWorld and baseWorld() or {}
    w.getMetaGrid = function() return grid end
    return w
end
local function key(x, y, z, kind) return x .. ',' .. y .. ',' .. z .. ',' .. kind end
-- IsoGridSquare.java:3065-3111 : porte du bord commun, quelle que soit la case qui la porte ; diagonale : nil.
function Sq:getDoorTo(nb)
    if nb == nil or nb == self or nb.z ~= self.z then return nil end
    local dx, dy = nb.x - self.x, nb.y - self.y
    local d
    if dx == 1 and dy == 0 then d = DOORS[key(nb.x, nb.y, self.z, 'W')]
    elseif dx == -1 and dy == 0 then d = DOORS[key(self.x, self.y, self.z, 'W')]
    elseif dx == 0 and dy == 1 then d = DOORS[key(nb.x, nb.y, self.z, 'N')]
    elseif dx == 0 and dy == -1 then d = DOORS[key(self.x, self.y, self.z, 'N')] end
    if d ~= nil and d.removed then return nil end
    return d
end
local Door = H.class('IsoDoor', Obj)
local Thump = H.class('IsoThumpable', Obj)
IsoDoor = Door
function Door.getDoubleDoorIndex(o) return o.double and 1 or -1 end
-- Porte de garage (LK04-T17) : panneaux d'index 1 à 3 alignés le long du mur (garage = true : panneau seul, index 1).
-- IsoDoor.java:2739-2878 : précédent à x - 1 (bord nord) ou y + 1 (bord ouest), d'index au plus égal ; suivant à
-- x + 1 ou y - 1, d'index au moins égal ; premier : remonte les précédents jusqu'à l'index 1.
local function gIndex(o) if o == nil or not o.garage then return -1 end return o.garage == true and 1 or o.garage end
function Door.getGarageDoorIndex(o) return gIndex(o) end
local function gNeighbour(o, sign)
    local i = gIndex(o)
    if i == -1 then return nil end
    local x, y = o.x, o.y
    if o.north then x = x + sign else y = y - sign end
    local n = DOORS[key(x, y, o.z, o.north and 'N' or 'W')]
    if n == nil or n.removed or gIndex(n) == -1 then return nil end
    if (sign < 0 and gIndex(n) > i) or (sign > 0 and gIndex(n) < i) then return nil end
    return n
end
function Door.getGarageDoorPrev(o) if gIndex(o) == 1 then return nil end return gNeighbour(o, -1) end
function Door.getGarageDoorNext(o) if gIndex(o) == 3 then return nil end return gNeighbour(o, 1) end
function Door.getGarageDoorFirst(o)
    if gIndex(o) == -1 then return nil end
    local p = o
    while gIndex(p) ~= 1 do
        local q = Door.getGarageDoorPrev(p)
        if q == nil then return o end
        p = q
    end
    return p
end
-- IsoGridSquare.java:7968-7970 : drapeau exterior ; doublure : self.outside, sinon case hors de tout bâtiment de
-- BUILDINGS. Pièce (getRoom) : celle du banc (self.room, nil partout).
function Sq:isOutside()
    if self.outside ~= nil then return self.outside end
    return defAt(self.x, self.y) == nil
end
local function bool(v, what)
    if type(v) ~= 'boolean' then error('No implementation found for ' .. what .. ' with argument ' .. tostring(v), 3) end
    return v
end
local M = {}
function M:IsOpen() return self.open == true end
function M:isLocked() return self.locked == true end
function M:isLockedByKey() return self.lockedByKey == true end
function M:setIsLocked(b) self.locked = bool(b, 'setIsLocked') end
function M:setLockedByKey(v, doSync)
    bool(v, 'setLockedByKey')
    local changed = v ~= (self.lockedByKey == true)
    self.lockedByKey = v
    self.locked = v
    if not isServer() and changed and doSync ~= false then self:sync() end
end
function M:ToggleDoorSilent()
    if self:isBarricaded() then return end
    self.open = not self.open
    TOGGLES = TOGGLES + 1
end
function M:ToggleDoor(chr)
    ENGINE_TOGGLES = ENGINE_TOGGLES + 1
    self:ToggleDoorSilent()
    if not instanceof(chr, 'IsoPlayer') then error('NullPointerException: player.isLocalPlayer()', 2) end
end
function M:isBarricaded() return self.barricaded == true end
function M:isObstructed() return self.obstructed == true end
function M:isDestroyed() return self.destroyed == true end
function M:getObjectIndex() return self.removed and -1 or 0 end
function M:getKeyId() return self.keyId or -1 end
-- IsoDoor.java:1979-2002 : keyId propre, sinon celui du bâtiment quand un seul des deux côtés (case de la porte, case
-- opposée : ouest pour "W", nord pour "N") est dans un bâtiment ; -1 sinon (porte intérieure ou hors bâtiment).
function M:checkKeyId()
    if (self.keyId or -1) ~= -1 then return self.keyId end
    local a = defAt(self.x, self.y)
    local b = self.north and defAt(self.x, self.y - 1) or defAt(self.x - 1, self.y)
    if a == nil and b ~= nil then self.keyId = b:getKeyId() elseif a ~= nil and b == nil then self.keyId = a:getKeyId()
    elseif a ~= nil and self.props ~= nil and self.props.forceLocked then self.keyId = a:getKeyId() end
    if self.locked and not self.lockedByKey and (self.keyId or -1) ~= -1 then self.lockedByKey = true end
    return self.keyId or -1
end
function M:isLockedByPadlock() return self.padlock == true end
-- IsoDoor.java:1722, IsoThumpable.java:345 ; propriétés du sprite (doublure : self.props, ex. { forceLocked = true }).
function M:getNorth() return self.north == true end
function M:getProperties()
    local props = self.props
    return { has = function(_, k) return props ~= nil and props[k] == true end }
end
-- IsoDoor.java:1244-1253, IsoThumpable.java:1551-1560 : porte basse (portail de clôture) enjambable si fermée ;
-- IsoObject.java:3337 : haute si le sprite porte TallHoppable (doublure : self.tall).
function M:isHoppable() return self.hoppable == true and self.open ~= true end
function M:isTallHoppable() return self.tall == true end
-- IsoObject.java:988-1008 : client -> serveur, serveur -> clients, solo : rien.
function M:sync()
    if not isServer() and not isClient() then return end
    SYNCS[#SYNCS + 1] = { key = self.key, open = self.open == true, locked = self.locked == true,
        lockedByKey = self.lockedByKey == true }
end
for name, f in pairs(M) do Door[name] = f; Thump[name] = f end
Door.isLockedByPadlock = nil
function NEW_DOOR(x, y, z, kind, cls, fields)
    local sq = H.square(x, y, z)
    local d = setmetatable({ key = key(x, y, z, kind), north = kind == 'N', open = false }, cls == 'thump' and Thump or Door)
    for k, v in pairs(fields or {}) do d[k] = v end
    d.square, d.x, d.y, d.z = sq, x, y, z
    sq.objects:add(d)
    DOORS[d.key] = d
    return d
end
-- Réception d'un SyncIsoObject (IsoDoor.java:1561-1600) : état absolu appliqué.
function APPLY_DOOR(k, open, locked, lockedByKey)
    local d = DOORS[k]
    if d == nil then return end
    if d.open ~= open then APPLIED = APPLIED + 1 end
    d.open, d.locked, d.lockedByKey = open, locked, lockedByKey
end
function DOOR_STATE(k)
    local d = DOORS[k]
    return tostring(d.open == true) .. ' ' .. tostring(d.locked == true) .. ' ' .. tostring(d.lockedByKey == true)
end
-- Pas de marche avec collision : la copie qui simule s'arrête contre une porte fermée ou barricadée de sa copie.
function STEP_D(zid, speed)
    local zb = H.zombies[zid]
    if zb == nil then return 'none' end
    local ox, oy = zb.x, zb.y
    local r = STEP(zid, speed)
    local a = H.square(ox, oy, zb.z)
    local b = H.square(zb.x, zb.y, zb.z)
    if a ~= b then
        local mid = H.square(b.x, a.y, zb.z)
        local door = a:getDoorTo(mid) or (mid ~= b and mid:getDoorTo(b)) or nil
        -- Porte basse fermée : jamais un arrêt (IsoZombie.java:1075, collideWith l'exclut), enjambée (STEP_W).
        local low = door ~= nil and door:isHoppable() and not door:isTallHoppable()
        if door ~= nil and (not door.open or door.barricaded) and not low then
            H.place(zb, ox, oy, zb.z)
            zb:setVariable('bPathfind', false)
            zb.moving = false
            return 'door'
        end
    end
    return r
end
'''

KEY_DOUBLES = r'''
-- Clés et inventaires (LK04-T12) : ItemContainer (getItems, AddItem, DoRemoveItem, haveThisKeyId : objets Key et
-- porte-clés, ItemContainer.java:444-470, 1979-2004, 3052-3064), Key (setKeyId : -1 tiré au hasard, Key.java),
-- instanceItem("Base.Key1") ; inventaire d'un personnage (IsoGameCharacter.getInventory) ; DoZombieInventory vide
-- l'inventaire d'un zombie ordinaire, jamais celui d'un joueur réanimé (IsoZombie.java:3129-3137) ; le cadavre prend
-- l'inventaire du mort (IsoDeadBody.java:327-332) et le joueur réanimé celui du cadavre (IsoDeadBody.java:1850-1853).
local H = HARNESS
local C = H.classes
local Inv = H.class('ItemContainer')
local Key = H.class('Key')
local Ring = H.class('InventoryContainer')
function Inv:getItems() return self.items end
function Inv:AddItem(it)
    if it == nil then return nil end
    if it.container ~= nil then it.container:DoRemoveItem(it) end
    it.container = self
    self.items:add(it)
    return it
end
function Inv:DoRemoveItem(it) H.listRemove(self.items, it); it.container = nil end
function Inv:removeAllItems() for _, it in ipairs(self.items.items) do it.container = nil end self.items = H.list() end
function Inv:haveThisKeyId(id)
    H.num(id, 'haveThisKeyId')
    for _, it in ipairs(self.items.items) do
        if instanceof(it, 'Key') then
            if it.keyId == math.floor(id) then return it end
        elseif instanceof(it, 'InventoryContainer') then
            local k = it.inv:haveThisKeyId(id)
            if k ~= nil then return k end
        end
    end
    return nil
end
function NEW_CONTAINER() return setmetatable({ items = H.list() }, Inv) end
for _, cls in ipairs({ Key, Ring }) do
    cls.getModData = C.IsoObject.getModData
    cls.hasModData = C.IsoObject.hasModData
    cls.getFullType = function(self) return self.fullType end
end
function Key:getKeyId() return self.keyId end
KEY_DRAW = 4242
function Key:setKeyId(id)
    H.num(id, 'setKeyId')
    if id == -1 then id = KEY_DRAW end
    self.keyId = math.floor(id)
end
local Z = C.IsoZombie
function Z:getInventory()
    local inv = rawget(self, 'inv')
    if inv == nil then inv = NEW_CONTAINER(); self.inv = inv end
    return inv
end
function Z:setInventory(inv) self.inv = inv end
local baseDZI = Z.DoZombieInventory
function Z:DoZombieInventory()
    if self.reanimated then return end
    self:getInventory():removeAllItems()
    if baseDZI then return baseDZI(self) end
end
local Body = C.IsoDeadBody
function Body:getContainer() return self.inv end
local baseCreate = C.IsoGridSquare.createCorpse
function C.IsoGridSquare:createCorpse(arg)
    local inv = type(arg) == 'table' and arg:getInventory() or nil
    local body = baseCreate(self, arg)
    if body ~= nil and inv ~= nil then
        body.inv = inv
        arg.inv = NEW_CONTAINER()
    end
    return body
end
local baseReanimate = Body.reanimate
function Body:reanimate()
    local inv = self.inv or NEW_CONTAINER()
    local zb = baseReanimate(self)
    if zb ~= nil then
        zb.inv = inv
        self.inv = nil
    end
    return zb
end
local baseItem = instanceItem
instanceItem = function(t)
    if t == 'Base.Key1' then return setmetatable({ fullType = t, keyId = -1 }, Key) end
    if t == 'Base.KeyRing' then return setmetatable({ fullType = t, inv = NEW_CONTAINER() }, Ring) end
    return baseItem and baseItem(t) or nil
end
-- Clés posées par Living Knox sur le corps zb : "keyId,keyId..." (ordre de l'inventaire).
function KEYS_ON(zb)
    local out = {}
    local inv = zb.inv or (zb.getInventory and zb:getInventory())
    if inv == nil then return '' end
    for _, it in ipairs(inv.items.items) do
        if instanceof(it, 'Key') then out[#out + 1] = tostring(it.keyId) end
    end
    return table.concat(out, ',')
end
'''

WINDOW_DOUBLES = r'''
local H = HARNESS
local Sq = H.classes.IsoGridSquare
local Obj = H.classes.IsoObject
WINDOWS, FENCES, STAIRS = {}, {}, {}
WTOGGLES, SMASHES, ALARMS = 0, 0, 0
TOGGLED_BY, CLIMBS = {}, {}
CLIMB_TICKS = 30
local function key(x, y, z, kind) return x .. ',' .. y .. ',' .. z .. ',' .. kind end
local function edgeKey(a, b)
    if b.z ~= a.z then return nil end
    local dx, dy = b.x - a.x, b.y - a.y
    if dx == 1 and dy == 0 then return key(b.x, b.y, a.z, 'W') end
    if dx == -1 and dy == 0 then return key(a.x, a.y, a.z, 'W') end
    if dx == 0 and dy == 1 then return key(b.x, b.y, a.z, 'N') end
    if dx == 0 and dy == -1 then return key(a.x, a.y, a.z, 'N') end
    return nil
end
EDGE_KEY = edgeKey
local Win = H.class('IsoWindow', Obj)
local Frame = H.class('IsoWindowFrame', Obj)
local Built = H.classes.IsoThumpable   -- classe des doublures de portes (isBarricaded lit self.barricaded)
local function find(sq, nb, cls)
    local k = nb and edgeKey(sq, nb)
    local w = k and WINDOWS[k]
    if w ~= nil and getmetatable(w) == cls then return w end
    return nil
end
-- IsoGridSquare.java:3131-3172, 3228-3236 : objet du bord commun, quelle que soit la case qui le porte.
function Sq:getWindowTo(nb) return find(self, nb, Win) end
function Sq:getWindowFrameTo(nb) return find(self, nb, Frame) end
function Sq:getWindowThumpableTo(nb) return find(self, nb, Built) end
-- IsoGridSquare.java:6541-6548 : sol solide, escalier ou pente (doublure : self.noFloor = vrai pour le vide).
function Sq:TreatAsSolidFloor() return self.noFloor ~= true end
function Win:IsOpen() return self.open == true end
function Win:isDestroyed() return self.destroyed == true end
function Win:isLocked() return self.locked == true end
function Win:isPermaLocked() return self.permaLocked == true end
function Win:getIndoorSquare() return self.square end
function Win:smashWindow() SMASHES = SMASHES + 1; self.destroyed = true end
function Win:getObjectIndex() return self.removed and -1 or 0 end
-- IsoWindow.java:701-731 : refus si inamovible, détruite ou barricadée ; verrou ignoré ; bascule ; alarme sauf pour
-- un zombie (option TriggerHouseAlarm fausse) ; recalcul et synchronisation par le moteur.
function Win:isInvincible() return self.invincible == true end
function Win:isSmashed() return self.destroyed == true end
function Win:setSmashed(b) self.destroyed = b; self.glassRemoved = false end
function Win:setGlassRemoved(b) self.glassRemoved = b end
function Win:setIsLocked(b) self.locked = b end
function Win:sync() end
function Sq:RecalcProperties() end
-- Une seule surcharge ToggleWindow(IsoGameCharacter) : Kahlua refuse tout autre nombre d'arguments
-- (MethodArguments.assertValid : "expected 1 argument, got 2").
function Win:ToggleWindow(...)
    local n = select('#', ...)
    if n ~= 1 then error('expected 1 argument, got ' .. n, 2) end
    local chr = ...
    if self.permaLocked or self.destroyed or (chr ~= nil and self.barricaded) then return end
    WTOGGLES = WTOGGLES + 1
    TOGGLED_BY[#TOGGLED_BY + 1] = chr == nil and 'nil' or (instanceof(chr, 'IsoZombie') and 'zombie' or 'other')
    self.locked = false
    self.open = not self.open
    if self.open and not instanceof(chr, 'IsoZombie') then ALARMS = ALARMS + 1 end
    if isServer() or isClient() then
        SYNCS[#SYNCS + 1] = { key = self.key, win = true, open = self.open == true, destroyed = self.destroyed == true }
    end
end
for _, cls in ipairs({ Win, Frame }) do
    cls.isBarricaded = function(self) return self.barricaded == true end
end
function NEW_WINDOW(x, y, z, kind, cls, fields)
    local sq = H.square(x, y, z)
    local mt = cls == 'frame' and Frame or (cls == 'built' and Built or Win)
    local w = setmetatable({ key = key(x, y, z, kind), north = kind == 'N', open = false }, mt)
    for k, v in pairs(fields or {}) do w[k] = v end
    w.square, w.x, w.y, w.z = sq, x, y, z
    sq.objects:add(w)
    WINDOWS[w.key] = w
    return w
end
function APPLY_WINDOW(k, open, destroyed)
    local w = WINDOWS[k]
    if w ~= nil then w.open, w.destroyed = open, destroyed end
end
function WINDOW_STATE(k)
    local w = WINDOWS[k]
    return tostring(w.open == true) .. ' ' .. tostring(w.destroyed == true)
end
local function blocks(w)
    if w.barricaded then return true end
    return getmetatable(w) == Win and not w.open and not w.destroyed
end
-- Pas de marche avec franchissements : fenêtre fermée ou barricadée = arrêt (IsoZombie.java:1075-1091) ; fenêtre
-- franchissable ou clôture basse = état climbwindow / climbfence pendant CLIMB_TICKS images (bPathfind effacé par
-- PathFindState.exit), puis corps de l'autre côté et chemin repris (ClimbThroughWindowState.java:243-262) ; escalier
-- (STAIRS[x .. ',' .. y]) : niveau du corps porté au niveau visé en le traversant.
function STEP_W(zid, speed)
    local zb = H.zombies[zid]
    if zb == nil then return 'none' end
    -- CLIMB_RECOVER (LK04-T17) : images d'immobilité après une escalade, avant la reprise du chemin (en jeu, 934 ms
    -- mesurées par lk.traversal le 2026-10-12).
    if (zb.recover or 0) > 0 then
        zb.recover = zb.recover - 1
        return 'recovering'
    end
    if zb.climb ~= nil then
        zb.climb.n = zb.climb.n - 1
        if zb.climb.n > 0 then return 'climbing' end
        local c = zb.climb
        zb.climb, zb.actionState = nil, nil
        H.place(zb, c.x, c.y, zb.z)
        CLIMBS[#CLIMBS + 1] = c.kind .. ' ' .. c.key
        zb.recover = CLIMB_RECOVER or 0
        zb:setVariable('bPathfind', true)
        zb.moving = false
        return 'climbed'
    end
    -- Orientation prise vers la case visée en marche seulement : un corps arrêté (ni bPathfind ni bMoving) garde la
    -- sienne (celle que pose setDirectionAngle, LK04-T13).
    if zb.goal ~= nil and (zb:getVariableBoolean('bPathfind') or zb.moving) then
        zb.angle = math.deg(math.atan2(zb.goal.y + 0.5 - zb.y, zb.goal.x + 0.5 - zb.x))
    end
    local ox, oy = zb.x, zb.y
    local r = STEP_D(zid, speed)
    if r == 'door' then return r end
    local a, b = H.square(ox, oy, zb.z), H.square(zb.x, zb.y, zb.z)
    local k = a ~= b and edgeKey(a, b) or nil
    local w = k and WINDOWS[k]
    local gate = k and DOORS[k]
    -- Clôture basse, ou porte basse fermée (portail) enjambée, verrouillée ou non (IsoZombie.java:3051-3058).
    -- Mur sur le même bord (WALLS) : drapeau de clôture retiré de la case, aucune enjambée (IsoMovingObject.java:
    -- 1565-1582 lit le drapeau de case ; IsoGridSquare.java:6233-6236).
    local fence = k and ((FENCES[k] and not (WALLS ~= nil and WALLS[k]))
        or (gate ~= nil and gate:isHoppable() and not gate:isTallHoppable()))
    if w ~= nil or fence then
        H.place(zb, ox, oy, zb.z)
        if w ~= nil and blocks(w) then
            zb:setVariable('bPathfind', false)
            zb.moving = false
            return 'window'
        end
        local kind = w ~= nil and 'climbwindow' or 'climbfence'
        zb.climb = { n = CLIMB_TICKS, x = b.x + 0.5, y = b.y + 0.5, kind = kind, key = k }
        -- CLIMB_LAND_EARLY (LK04-T17) : glissement du moteur arrêté à l'entrée de la case d'en face, corps immobile
        -- là jusqu'à la fin du clip (base, zombies-as-npc-bodies.md).
        if CLIMB_LAND_EARLY then H.place(zb, b.x + 0.5, b.y + 0.5, zb.z) end
        zb.actionState = kind
        zb:setVariable('bPathfind', false)
        zb.moving = false
        return 'climb'
    end
    local s = STAIRS[b.x .. ',' .. b.y]
    if s ~= nil and zb.goal ~= nil and zb.goal.z ~= zb.z and s == zb.goal.z then H.place(zb, zb.x, zb.y, s) end
    return r
end
'''

LANE_DOUBLES = r'''
-- Bords d'une case pour la recherche de site de la suite lk.traversal (LK04-T08) : murs (WALLS[clé de bord]),
-- IsoGridSquare.isWallTo / isBlockedTo / isDoorTo / isWindowTo / isHoppableTo / getHoppableTo
-- (IsoGridSquare.java:721-735, 927-939, 1043-1049 : bord commun, quelle que soit la case qui le porte).
local H = HARNESS
local Sq = H.classes.IsoGridSquare
WALLS = {}
local function k(a, b) return b ~= nil and EDGE_KEY(a, b) or nil end
function Sq:HasStairs() return STAIRS[self.x .. ',' .. self.y] ~= nil end
function Sq:isWallTo(nb) local e = k(self, nb); return e ~= nil and WALLS[e] == true end
function Sq:isDoorTo(nb) return self:getDoorTo(nb) ~= nil end
function Sq:isWindowTo(nb) local e = k(self, nb); return e ~= nil and WINDOWS[e] ~= nil end
function Sq:isBlockedTo(nb)
    if self:isWallTo(nb) then return true end
    local d = self:getDoorTo(nb)
    return d ~= nil and d.barricaded == true
end
function Sq:getHoppableTo(nb)
    local e = k(self, nb)
    if e == nil then return nil end
    if FENCES[e] then return { fence = e } end
    local d = DOORS[e]
    if d ~= nil and d:isHoppable() then return d end
    return nil
end
function Sq:isHoppableTo(nb) return self:getHoppableTo(nb) ~= nil end
-- Drapeaux de la case (IsoGridSquare.has(IsoFlagType), :2105) : HoppableW / HoppableN du bord ouest / nord de la case,
-- posés par une clôture basse ou un portail fermé (HoppableW -> collideW + canPathW, IsoWorld.java:883-887) et RETIRÉS
-- par RecalcProperties quand un autre objet du même bord pose collideW/N sans Hoppable (mur : WALLS ;
-- IsoGridSquare.java:6144-6179, 6233-6236), alors que l'objet enjambable reste (isHoppableTo vrai).
IsoFlagType = IsoFlagType or {}
IsoFlagType.HoppableW = IsoFlagType.HoppableW or 'HoppableW'
IsoFlagType.HoppableN = IsoFlagType.HoppableN or 'HoppableN'
function Sq:has(flag)
    local kind = (flag == IsoFlagType.HoppableW and 'W') or (flag == IsoFlagType.HoppableN and 'N') or nil
    if kind == nil then return false end
    local e = self.x .. ',' .. self.y .. ',' .. self.z .. ',' .. kind
    if WALLS[e] then return false end
    if FENCES[e] then return true end
    local d = DOORS[e]
    return d ~= nil and d:isHoppable() == true
end
-- IsoGridSquare.java:2352 : arbre sur la case (doublure : self.tree) ; case d'arbre impraticable pour isFree.
function Sq:HasTree() return self.tree == true end
-- IsoGridSquare.java:2382-2384 : buisson ou haie sur la case (doublure : self.bush) ; case libre pour isFree.
function Sq:hasBush() return self.bush == true end
-- IsoGridSquare.java:2886-2892 : drapeaux solid / solidtrans (doublures : self.solid, self.solidTrans ; une case
-- solidtrans est aussi impraticable pour isFree, poser blocked = true) ; IsoGridSquare.java:3077-3079, 3139-3145 :
-- fenêtre, fenêtre construite ou cadre (clôture basse ou cadre) sur l'un des quatre bords de la case.
function Sq:isSolid() return self.solid == true end
function Sq:isSolidTrans() return self.solidTrans == true end
local function sides(sq)
    local x, y, z = sq.x, sq.y, sq.z
    return { x .. ',' .. y .. ',' .. z .. ',N', x .. ',' .. y .. ',' .. z .. ',W',
        x .. ',' .. (y + 1) .. ',' .. z .. ',N', (x + 1) .. ',' .. y .. ',' .. z .. ',W' }
end
function Sq:isAdjacentToWindow()
    for _, e in ipairs(sides(self)) do if WINDOWS[e] ~= nil then return true end end
    return false
end
function Sq:isAdjacentToHoppable()
    for _, e in ipairs(sides(self)) do
        if FENCES[e] then return true end
        local d = DOORS[e]
        if d ~= nil and d:isHoppable() then return true end
    end
    return false
end
'''

DOOR = (106, 102, 0, 'W')             # bord ouest de la case (106, 102) : entre (105, 102) et (106, 102)
DOOR_KEY = '106,102,0,W'
HOUSE = {'id': 'B1', 'x1': 106, 'y1': 100, 'x2': 112, 'y2': 105}   # cible (111, 102) dedans, porte extérieure


class ObstacleBase(DirectiveBase):
    def make(self, root=None):
        h = super().make(root)
        names = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in names:
            for path in TYPES:
                h.load(m, path)
            h.load(m, DOOR_DOUBLES)
            h.load(m, KEY_DOUBLES)
            h.load(m, WINDOW_DOUBLES)
            h.load(m, LANE_DOUBLES)
            h.load(m, OBSTACLES)
        return h

    @property
    def machines(self):
        return ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']

    def o(self, code, m=None):
        return self.ev('LivingKnox.Obstacles.' + code, m)

    def door(self, cls='door', x=DOOR[0], y=DOOR[1], z=DOOR[2], kind=DOOR[3], **fields):
        lua = ', '.join(f'{k} = {str(v).lower() if isinstance(v, bool) else v}' for k, v in fields.items())
        for m in self.machines:
            self.h.load(m, f'NEW_DOOR({x}, {y}, {z}, "{kind}", "{cls}", {{ {lua} }})')

    def wall(self, x=DOOR[0], ys=range(90, 126), skip=(DOOR[1],)):
        """Mur le long du bord ouest de x, percé en skip (la porte) : une porte est dans un mur. Sans lui, une porte
        refusée seule au milieu du terrain est contournée par le détour de LK04-T14."""
        keys = [f'{x},{y},0,W' for y in ys if y not in skip]
        for m in self.machines:
            self.h.load(m, '; '.join(f'WALLS["{k}"] = true' for k in keys))

    def building(self, b=HOUSE):
        for m in self.machines:
            self.h.load(m, 'BUILDINGS[#BUILDINGS + 1] = { id = "%s", x1 = %d, y1 = %d, x2 = %d, y2 = %d, keyId = %s }'
                        % (b['id'], b['x1'], b['y1'], b['x2'], b['y2'], b.get('keyId', 'nil')))

    def group(self, member=True, home=(108, 101, 0), npc='lk-1', name='Home'):
        gid = self.run_lua(f'local g = LivingKnox.Groups.create({{ type = "settlers", name = "{name}", '
                           f'home = {{ x = {home[0]}, y = {home[1]}, z = {home[2]} }} }}) return g.id')
        if member:
            self.assertIsNotNone(self.run_lua(f'return LivingKnox.Groups.addMember("{gid}", '
                                              f'{{ role = "worker", npc = "{npc}" }})'))
        self.run_lua('LivingKnox.Obstacles.refreshHomes(true)')
        return gid

    def state(self, m, k=DOOR_KEY):
        return self.h.eval(m, f'DOOR_STATE("{k}")')

    def relay_doors(self):
        """Livre les SyncIsoObject : serveur -> clients ; client -> serveur puis autres clients. Rend leur nombre."""
        if self.mode == 'solo':
            return 0
        n = 0
        for src in ('server', 'A', 'B'):
            syncs = self.h.eval(src, 'SYNCS')
            items = [syncs[i] for i in range(1, len(syncs) + 1)]
            self.h.load(src, 'SYNCS = {}')
            for s in items:
                n += 1
                SENT.append((src, s.key))
                for dst in ('server', 'A', 'B'):
                    if dst == src:
                        continue
                    if s.win:
                        self.h.eval(dst, f'APPLY_WINDOW("{s.key}", {str(s.open).lower()}, '
                                         f'{str(s.destroyed).lower()})')
                    else:
                        self.h.eval(dst, f'APPLY_DOOR("{s.key}", {str(s.open).lower()}, {str(s.locked).lower()}, '
                                         f'{str(s.lockedByKey).lower()})')
        return n

    def walk_d(self, zid, ticks, speed=0.05, until=None, check=None):
        for _ in range(ticks):
            self.h.tick(1)
            m = self.sim(zid)
            self.h.eval(m, f'STEP_D({zid}, {speed})')
            zb = self.h.zombie(m, zid)
            if self.mode == 'mp':
                self.h.move_zombie(zid, zb.x, zb.y)
                self.relay_doors()
                self.h.pump()
            if check:
                check()
            if until and until():
                break

    def counters(self, m):
        return self.h.eval(m, 'TOGGLES'), self.h.eval(m, 'ENGINE_TOGGLES')

    def start(self, owner='A'):
        if self.mode == 'solo':
            self.init()
            npc_id, body = self.spawn()
            return body.onlineID
        return self.ready(owner)

    def move(self):
        return self.d('moveTo("lk-1", 111, 102, 0)')

    # Fenêtres, clôtures, escaliers (LK04-T03) ---------------------------------------------------------------
    def window(self, cls='window', x=DOOR[0], y=DOOR[1], z=DOOR[2], kind=DOOR[3], **fields):
        lua = ', '.join(f'{k} = {str(v).lower() if isinstance(v, bool) else v}' for k, v in fields.items())
        for m in self.machines:
            self.h.load(m, f'NEW_WINDOW({x}, {y}, {z}, "{kind}", "{cls}", {{ {lua} }})')

    def fence(self, x=DOOR[0], y=DOOR[1], z=DOOR[2], kind=DOOR[3]):
        for m in self.machines:
            self.h.load(m, f'FENCES["{x},{y},{z},{kind}"] = true')

    def wstate(self, m, k=DOOR_KEY):
        return self.h.eval(m, f'WINDOW_STATE("{k}")')

    def walk_w(self, zid, ticks, speed=0.05, until=None, check=None):
        """Comme walk_d, avec fenêtres, clôtures et escaliers (STEP_W) ; position, niveau et orientation de la copie
        qui simule recopiés sur les autres machines (paquet zombie)."""
        for _ in range(ticks):
            self.h.tick(1)
            m = self.sim(zid)
            self.h.eval(m, f'STEP_W({zid}, {speed})')
            zb = self.h.zombie(m, zid)
            if self.mode == 'mp':
                self.h.move_zombie(zid, zb.x, zb.y, zb.z)
                for o in self.machines:
                    if o != m:
                        self.h.load(o, f'HARNESS.zombies[{zid}].angle = {zb.angle or 0}')
                self.relay_doors()
                self.h.pump()
            if check:
                check()
            if until and until():
                break

    def wcount(self, m):
        return self.h.eval(m, 'WTOGGLES'), self.h.eval(m, 'SMASHES')

    def climbs(self, m):
        return lua_list(self.h.eval(m, 'CLIMBS'))

    def friendly_group(self, member=True, gtype='settlers', home=(300, 300, 0), name='Friends'):
        gid = self.run_lua(f'local g = LivingKnox.Groups.create({{ type = "{gtype}", name = "{name}", '
                           f'home = {{ x = {home[0]}, y = {home[1]}, z = {home[2]} }} }}) return g.id')
        if member:
            self.assertIsNotNone(self.run_lua(f'return LivingKnox.Groups.addMember("{gid}", '
                                              f'{{ role = "fighter", npc = "lk-1" }})'))
        self.run_lua('LivingKnox.Obstacles.refreshHomes(true)')
        return gid


SENT: list = []


class MultiplayerDoorTests(ObstacleBase):
    def setUp(self):
        super().setUp()
        SENT.clear()

    def mirror(self, zid, owner, machines=('A', 'B')):
        srv = self.h.zombie('server', zid)
        for c in machines:
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)

    def ready(self, owner='A'):
        zid = self.npc()
        self.mirror(zid, owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def same_everywhere(self):
        self.assertEqual(self.state('A'), self.state('server'))
        self.assertEqual(self.state('B'), self.state('server'))

    def test_member_opens_its_locked_home_door_once_passes_and_locks_it_behind(self):
        self.building()
        self.door(locked=True, lockedByKey=True, keyId=77)
        zid = self.start('A')
        self.group(member=True)
        self.assertEqual(self.move(), 1)
        self.h.pump()
        states = []

        def check():
            # Après livraison : les deux clients voient l'état du serveur.
            self.same_everywhere()
            states.append(self.state('server'))
        self.walk_d(zid, 600, until=self.done(), check=check)
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_d(zid, 30, check=check)
        # Ouverte (déverrouillée) puis refermée et reverrouillée : deux bascules, sur le serveur seulement.
        self.assertEqual(self.counters('server'), (2, 0))
        for c in ('A', 'B'):
            self.assertEqual(self.counters(c), (0, 0))
            self.assertEqual(self.h.eval(c, 'APPLIED'), 2)
        self.assertEqual([src for src, _ in SENT], ['server', 'server'])
        seq = [s for i, s in enumerate(states) if i == 0 or s != states[i - 1]]
        self.assertEqual(seq, ['false true true', 'true false false', 'false true true'])
        self.assertEqual(self.state('A'), 'false true true')
        self.assertEqual(self.o('stats.opened'), 1)
        self.assertEqual(self.o('stats.closed'), 1)
        self.assertEqual(self.o('stats.unlocked'), 1)
        self.assertEqual(self.o('stats.locked'), 1)
        self.assertGreaterEqual(self.h.eval('server', 'RECALCS'), 2)
        self.assertGreaterEqual(self.h.eval('server', 'CHANGED'), 2)
        lines = self.lk()
        self.assertTrue(any('door 106,102,0,W opened and unlocked (member of grp-1)' in s for s in lines), lines)
        self.assertTrue(any('door 106,102,0,W closed behind npc lk-1 and locked' in s for s in lines), lines)
        self.assertEqual(self.d('stats.rejected'), 0)

    def test_non_member_is_refused_and_stopped_at_the_door(self):
        self.wall()
        self.building()
        self.door(locked=True, lockedByKey=True, keyId=77)
        zid = self.start('A')
        self.group(member=False)
        self.move()
        self.h.pump()
        self.walk_d(zid, 400, until=self.done())
        self.assertIs(self.entry('done'), True)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.entry('by'), 'server')
        self.walk_d(zid, 20)
        zb = self.h.zombie('A', zid)
        self.assertLess(zb.x, 106)              # jamais passé
        self.assertIs(zb.moving, False)
        self.assertIs(self.h.eval('A', f'HARNESS.zombies[{zid}]:getVariableBoolean("bPathfind")'), False)
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.runs["lk-1"].phase'), 'failed')
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.counters(m), (0, 0))
            self.assertEqual(self.state(m), 'false true true')
        self.assertEqual(SENT, [])
        lines = self.lk()
        self.assertTrue(any('refused at the door 106,102,0,W: door of the home of grp-1 (not a member)' in s
                            for s in lines), lines)
        self.assertEqual(self.o('stats.refused'), 1)

    def test_member_of_another_group_is_refused_even_unlocked(self):
        self.wall()
        self.building()
        self.door()
        zid = self.start('A')
        self.group(member=False)
        self.group(member=True, home=(300, 300, 0), name='Other')   # lk-1 dans un autre groupe
        self.move()
        self.h.pump()
        self.walk_d(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.counters('server'), (0, 0))
        self.assertEqual(self.state('B'), 'false false false')

    def test_barricaded_door_is_refused(self):
        self.wall()
        self.door(barricaded=True)
        zid = self.start('A')
        self.move()
        self.h.pump()
        self.walk_d(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertLess(self.h.zombie('A', zid).x, 106)
        self.assertEqual(SENT, [])
        self.assertTrue(any('refused at the door 106,102,0,W: barricaded door' in s for s in self.lk()), self.lk())

    def test_ordinary_door_opened_and_closed_but_not_locked_locked_one_refused(self):
        self.wall()
        self.door()
        zid = self.start('A')
        self.move()
        self.h.pump()
        self.walk_d(zid, 600, until=self.done(), check=self.same_everywhere)
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_d(zid, 30, check=self.same_everywhere)
        self.assertEqual(self.state('B'), 'false false false')
        self.assertEqual(self.counters('server'), (2, 0))
        self.assertEqual(self.counters('A'), (0, 0))
        # Porte verrouillée hors foyer : refusée (aucune clé).
        self.h.load('server', 'DOORS["106,102,0,W"].locked = true')
        self.d('moveTo("lk-1", 102, 102, 0)')
        self.h.pump()
        self.walk_d(zid, 400, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(any('locked door (no key)' in s for s in self.lk()), self.lk())

    def test_door_kept_open_while_its_squares_are_occupied(self):
        self.door()
        zid = self.start('A')
        self.move()
        self.h.pump()
        self.walk_d(zid, 60)                      # porte ouverte devant le corps
        self.assertEqual(self.state('server'), 'true false false')
        self.h.move_player('B', 105.5, 102.5, 0)  # B dans l'encadrement
        self.walk_d(zid, 600, until=self.done())
        self.walk_d(zid, 30)
        self.assertEqual(self.state('server'), 'true false false')
        self.assertGreater(self.o('stats.busy'), 0)
        self.h.move_player('B', 96, 108, 0)
        self.walk_d(zid, 10)
        self.assertEqual(self.state('A'), 'false false false')
        self.assertEqual(self.counters('server'), (2, 0))

    def test_owner_change_mid_crossing_never_toggles_twice(self):
        self.building()
        self.door(locked=True, lockedByKey=True)
        zid = self.start('A')
        self.group(member=True)
        self.move()
        self.h.pump()
        self.walk_d(zid, 45)                      # porte ouverte, corps pas encore passé
        self.assertEqual(self.state('B'), 'true false false')
        self.h.set_owner(zid, 'B')
        self.walk_d(zid, 800, until=self.done(), check=self.same_everywhere)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('by'), 'B')
        self.walk_d(zid, 30)
        self.assertEqual(self.counters('server'), (2, 0))
        for c in ('A', 'B'):
            self.assertEqual(self.counters(c), (0, 0))
        self.assertEqual(self.state('A'), 'false true true')

    def test_home_exterior_doors_secured_interior_ones_left(self):
        self.building()
        self.door()                                                    # extérieure, ouverte à clé : verrouillée
        self.door(x=108, y=102, kind='W')                              # intérieure : laissée
        self.door(x=107, y=105, kind='N', open=True)                   # extérieure ouverte : plus tard (LK04-T10)
        self.npc()
        self.group(member=True)
        self.h.tick(self.o('PASS_EVERY'))
        self.relay_doors()
        self.assertEqual(self.state('B'), 'false true true')
        self.assertEqual(self.h.eval('B', 'DOOR_STATE("108,102,0,W")'), 'false false false')
        self.assertEqual(self.h.eval('B', 'DOOR_STATE("107,105,0,N")'), 'true false false')
        self.assertEqual(self.h.eval('server', 'DOORS["106,102,0,W"].keyId'), 77)   # clé du bâtiment
        self.assertEqual(self.o('stats.secured'), 1)
        self.assertEqual(self.counters('server'), (0, 0))

    def test_client_loads_the_file_and_does_nothing(self):
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Obstacles'))


class SoloDoorTests(ObstacleBase):
    mode = 'solo'

    def test_solo_member_crosses_and_locks_behind_without_network(self):
        self.building()
        self.door(locked=True, lockedByKey=True)
        zid = self.start()
        self.group(member=True)
        self.move()
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_d(zid, 30)
        self.assertEqual(self.state('solo'), 'false true true')
        self.assertEqual(self.counters('solo'), (2, 0))
        self.assertEqual(self.h.pending(), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_solo_body_waits_at_a_closed_door_without_spending_retries(self):
        # Porte fermée vue trop tard (passages de l'autorité coupés) : le corps s'arrête contre elle et attend.
        self.door()
        zid = self.start()
        self.run_lua('LivingKnox.Obstacles.PASS_EVERY = 100000')
        self.move()
        self.walk_d(zid, 120)
        zb = self.h.zombie('solo', zid)
        self.assertLess(zb.x, 106)
        self.assertEqual(self.ev('LivingKnox.Executor.stats.retries'), 0)
        self.assertIs(self.entry('done'), False)
        self.run_lua('LivingKnox.Obstacles.PASS_EVERY = 5')
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertGreaterEqual(self.ev('LivingKnox.Executor.stats.doorResumed'), 1)

    def test_set_door_fixes_the_state_and_double_doors_are_refused(self):
        self.door()
        self.init()
        d = 'DOORS["106,102,0,W"]'
        self.assertIs(self.o(f'setDoor({d}, true)'), True)
        self.assertIs(self.o(f'setDoor({d}, true)'), False)        # déjà ouverte : rien
        self.assertIs(self.o(f'setDoor({d}, false, false)'), True)
        self.assertIs(self.o(f'setDoor({d}, false, false)'), False)
        self.assertEqual(self.h.eval('solo', 'TOGGLES'), 2)
        self.door(x=110, y=110, double=True)
        self.assertEqual(self.run_lua('return LivingKnox.Obstacles.decide("lk-1", DOORS["110,110,0,W"])')[1],
                         'double door not handled')
        self.door(x=112, y=110, cls='thump', padlock=True)
        self.assertEqual(self.run_lua('return LivingKnox.Obstacles.decide("lk-1", DOORS["112,110,0,W"])')[1],
                         'padlocked door')


class MultiplayerTraversalTests(ObstacleBase):
    """Fenêtres (LK04-T03) : serveur dédié, A simule le corps, B regarde."""

    def setUp(self):
        super().setUp()
        SENT.clear()

    def ready(self, owner='A'):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def closed_behind(self, gtype='settlers', name='Friends'):
        """Fenêtre fermée devant lk-1 (groupe gtype) : ouverte puis refermée par le serveur. Rend les états vus."""
        self.window()
        zid = self.start('A')
        self.friendly_group(gtype=gtype, name=name)
        self.move()
        self.h.pump()
        states = []

        def check():
            # Après livraison : A et B voient l'état du serveur.
            self.assertEqual(self.wstate('A'), self.wstate('server'))
            self.assertEqual(self.wstate('B'), self.wstate('server'))
            states.append(self.wstate('server'))
        self.walk_w(zid, 900, until=self.done(), check=check)
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_w(zid, 60, check=check)
        return zid, [st for i, st in enumerate(states) if i == 0 or st != states[i - 1]]

    def assert_opened_and_closed_once(self, zid, seq):
        # Deux bascules (ouverte puis refermée), toutes deux sur le serveur avec le corps (zombie : pas d'alarme) ;
        # aucun bris ; état fermé vu par A et B.
        self.assertEqual(seq, ['false false', 'true false', 'false false'])
        self.assertEqual(self.wcount('server'), (2, 0))
        for c in ('A', 'B'):
            self.assertEqual(self.wcount(c), (0, 0))
            self.assertEqual(self.wstate(c), 'false false')
        self.assertEqual(lua_list(self.h.eval('server', 'TOGGLED_BY')), ['zombie', 'zombie'])
        self.assertEqual(self.h.eval('server', 'ALARMS'), 0)
        self.assertEqual([src for src, _ in SENT], ['server', 'server'])
        self.assertEqual(self.climbs('A'), ['climbwindow ' + DOOR_KEY])
        self.assertGreater(self.h.zombie('A', zid).x, 107)
        self.assertEqual(self.o('stats.windowsOpened'), 1)
        self.assertEqual(self.o('stats.windowsClosed'), 1)
        self.assertEqual(self.o('stats.windowToggles'), 2)
        self.assertEqual(self.o('stats.windowsGivenUp'), 0)
        self.assertTrue(any('window 106,102,0,W closed behind npc lk-1' in s for s in self.lk()), self.lk())

    def test_member_has_a_closed_window_opened_once_climbs_it_and_it_is_closed_behind(self):
        zid, seq = self.closed_behind()
        self.assert_opened_and_closed_once(zid, seq)
        ex = 'LivingKnox.Executor.stats'
        # LK04-T13 : chemin repris à la fin du geste d'ouverture (fenêtre ouverte pendant le geste).
        self.assertGreaterEqual(self.h.eval('A', f'{ex}.actResumed'), 1)
        self.assertEqual(self.h.eval('A', f'{ex}.crossings'), 1)
        self.assertGreater(self.h.eval('A', f'{ex}.crossMs'), 0)
        self.assertEqual(self.h.eval('A', f'{ex}.failed'), 0)
        self.assertTrue(any('window 106,102,0,W opened (group grp-1)' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('A'), [])
        self.assertEqual(self.h.errors('server'), [])

    def test_raider_opens_a_closed_window_never_breaks_it_and_closes_it_behind(self):
        zid, seq = self.closed_behind(gtype='raiders', name='Raiders')
        self.assert_opened_and_closed_once(zid, seq)
        self.assertEqual(self.o('stats.windowsRefused'), 0)

    def test_window_kept_open_while_its_squares_are_occupied_never_closed_from_afar(self):
        # LK04-T18 : occupée quand le corps vient de l'enjamber, la fenêtre n'est pas refermée ; le corps poursuit sa
        # route et, une fois loin (au-delà d'ACT_REACH), elle n'est plus refermée de là-bas, même libérée (l'ancienne
        # règle la fermait à distance).
        self.window()
        zid = self.start('A')
        self.friendly_group()
        self.move()
        self.h.pump()
        self.walk_w(zid, 200, until=lambda: self.wstate('server') == 'true false')
        self.assertEqual(self.wstate('server'), 'true false')
        self.h.move_player('B', 105.5, 102.5, 0)   # B sur la case de départ, devant la fenêtre
        self.walk_w(zid, 900, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_w(zid, 30)
        self.assertEqual(self.wstate('server'), 'true false')
        self.assertGreater(self.o('stats.windowsBusy'), 0)
        self.h.move_player('B', 96, 108, 0)
        self.walk_w(zid, 30)
        self.assertEqual(self.wstate('B'), 'true false')
        self.assertEqual(self.wcount('server'), (1, 0))
        self.assertEqual(self.o('stats.windowsClosed'), 0)
        self.assertIsNone(self.ev('LivingKnox.Obstacles.lastClose'))

    def test_window_left_open_with_a_warning_when_still_occupied_after_the_delay(self):
        self.window()
        zid = self.start('A')
        self.friendly_group()
        self.run_lua('LivingKnox.Obstacles.GIVE_UP_MS = 3000')
        self.move()
        self.h.pump()
        self.walk_w(zid, 200, until=lambda: self.wstate('server') == 'true false')
        self.h.move_player('B', 105.5, 102.5, 0)
        self.walk_w(zid, 900, until=self.done())
        self.walk_w(zid, 300)
        self.h.move_player('B', 96, 108, 0)
        self.walk_w(zid, 30)
        self.assertEqual(self.wstate('B'), 'true false')     # laissée ouverte, plus suivie
        self.assertEqual(self.wcount('server'), (1, 0))
        self.assertEqual(self.o('stats.windowsGivenUp'), 1)
        self.assertTrue(any('window 106,102,0,W left open' in s for s in self.lk()), self.lk())

    def test_window_closed_by_someone_else_is_no_longer_touched(self):
        self.window()
        zid = self.start('A')
        self.friendly_group()
        self.move()
        self.h.pump()
        self.walk_w(zid, 200, until=lambda: self.wstate('server') == 'true false')
        self.assertEqual(self.o('stats.windowsOpened'), 1)
        # Refermée par un joueur sur le serveur avant le passage, puis rouverte par un autre (fenêtre « à lui ») : le
        # module ne la suit plus et ne la referme pas.
        self.run_lua('WINDOWS["106,102,0,W"].open = false')
        self.run_lua('LivingKnox.Obstacles.closeWindowsPass({}, getTimestampMs())')
        self.assertEqual(self.ev('LivingKnox.Obstacles.openWins["106,102,0,W"]'), None)
        self.run_lua('WINDOWS["106,102,0,W"].open = true')
        self.walk_w(zid, 900, until=self.done())
        self.walk_w(zid, 60)
        self.assertEqual(self.wstate('server'), 'true false')
        self.assertEqual(self.o('stats.windowsClosed'), 0)

    def test_barricaded_window_refused_even_for_a_friendly_member(self):
        self.window(barricaded=True)
        zid = self.start('A')
        self.friendly_group()
        self.move()
        self.h.pump()
        self.walk_w(zid, 500, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.wcount('server'), (0, 0))
        self.assertTrue(any('barricaded window' in s for s in self.lk()), self.lk())

    def test_open_window_is_climbed_without_any_toggle(self):
        self.window(open=True)
        zid = self.start('A')
        self.move()
        self.h.pump()
        self.walk_w(zid, 900, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('A'), ['climbwindow ' + DOOR_KEY])
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.wcount(m), (0, 0))
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.stats.retries'), 0)


class SoloTraversalTests(ObstacleBase):
    mode = 'solo'

    def trip(self, ticks=900):
        zid = self.start()
        self.move()
        self.walk_w(zid, ticks, until=self.done())
        return zid

    def test_broken_window_empty_frame_and_low_fence_are_crossed_by_the_engine_alone(self):
        cases = [('window', {'destroyed': True}, 'climbwindow'), ('frame', {}, 'climbwindow'),
                 ('built', {}, 'climbwindow'), (None, {}, 'climbfence')]
        for cls, fields, kind in cases:
            with self.subTest(cls=cls):
                self.setUp()
                try:
                    if cls is None:
                        self.fence()
                    else:
                        self.window(cls, **fields)
                    self.trip()
                    self.assertEqual(self.entry('s'), 'arrived')
                    self.assertEqual(self.climbs('solo'), [kind + ' ' + DOOR_KEY])
                    self.assertEqual(self.wcount('solo'), (0, 0))
                    st = 'LivingKnox.Executor.stats'
                    self.assertEqual(self.ev(f'{st}.retries'), 0)          # pas d'essai pendant l'escalade
                    self.assertEqual(self.ev(f'{st}.crossings'), 1)
                    # Durée mesurée : CLIMB_TICKS images de 16 ms au moins.
                    self.assertGreaterEqual(self.ev(f'{st}.crossMs'), 30 * 16)
                    self.assertEqual(self.h.errors('solo'), [])
                finally:
                    self.tearDown()

    def test_stop_during_a_fence_crossing_holds_after_the_climb(self):
        # Campagne MP du 2026-10-15 (lk.executor) : arret pendant l'enjambee d'une cloture ; le moteur remet bPathFind
        # a la sortie de l'escalade et le corps reprenait seul son chemin jusqu'a la destination.
        self.fence()
        zid = self.start()
        self.move()
        self.walk_w(zid, 900, until=lambda: self.h.zombie('solo', zid).climb is not None)
        self.assertIsNotNone(self.h.zombie('solo', zid).climb, 'the body never climbed the fence')
        self.assertIsNotNone(self.d('stop("lk-1")'))
        self.walk_w(zid, 300)
        zb = self.h.zombie('solo', zid)
        self.assertIsNone(zb.climb)
        self.assertEqual(self.climbs('solo'), ['climbfence ' + DOOR_KEY])
        self.assertLess(zb.x, 107.5, 'the body walked on after the stop')
        self.assertEqual(self.entry('s'), 'stopped')
        self.assertEqual(self.ev('LivingKnox.Executor.stats.haltedAfterCrossing'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_stairs_change_the_level_without_any_obstacle_action(self):
        for x in (107, 108):
            self.run_lua(f'STAIRS["{x},102"] = 1')
        zid = self.start()
        self.assertEqual(self.d('moveTo("lk-1", 111, 102, 1)'), 1)
        self.walk_w(zid, 900, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.h.zombie('solo', zid).z, 1)
        self.assertEqual(self.o('stats.refused'), 0)
        self.assertEqual(self.o('stats.windowToggles'), 0)
        self.assertEqual(self.ev('LivingKnox.Executor.stats.retries'), 0)

    def test_window_decisions(self):
        self.init()
        self.building()
        self.window()                                            # 106,102 W : maison B1 à l'est
        self.window(x=104, y=110, kind='W', locked=True)
        self.window(x=104, y=112, kind='W', permaLocked=True)
        self.window(x=104, y=114, kind='W')
        self.window('frame', x=104, y=116, kind='W', barricaded=True)
        self.window('built', x=104, y=118, kind='W', barricaded=True)
        self.window(x=104, y=120, kind='W')
        self.run_lua('HARNESS.square(104, 114, 0).noFloor = true')
        self.friendly_group()

        def decide(x, y, far=None):
            far = far or (x, y)
            return self.run_lua(
                f'local w, k = LivingKnox.Obstacles.windowOf(HARNESS.square({x - 1}, {y}, 0), '
                f'HARNESS.square({x}, {y}, 0)) '
                f'return LivingKnox.Obstacles.decideWindow("lk-1", w, k, HARNESS.square({x - 1}, {y}, 0), '
                f'HARNESS.square({x}, {y}, 0), HARNESS.square({far[0]}, {far[1]}, 0))')

        self.assertEqual(decide(106, 102), 'open')
        self.assertEqual(decide(104, 110)[1], 'locked window')
        self.assertEqual(decide(104, 112)[1], 'window that cannot be opened')
        self.assertEqual(decide(104, 114)[1], 'window over a drop')
        self.assertEqual(decide(104, 116)[1], 'barricaded window')
        self.assertEqual(decide(104, 118)[1], 'barricaded window')
        # Maison à alarme : refus seulement si l'option l'armerait.
        self.run_lua('BUILDINGS[1].alarmed = true; HARNESS.classes.BuildingDef.isAlarmed = '
                     'function(self) return self.alarmed == true end')
        self.assertEqual(decide(106, 102), 'open')
        self.run_lua('SandboxVars = { ZombieLore = { TriggerHouseAlarm = true } }')
        self.assertEqual(decide(106, 102)[1], 'window of an alarmed house')
        self.run_lua('SandboxVars = nil')
        # Foyer d'un autre groupe : refusé ; PNJ sans groupe : refusé.
        self.group(member=False, name='Owners')
        self.assertEqual(decide(106, 102)[1], 'window of the home of grp-2 (not a member)')
        self.assertEqual(decide(104, 120), 'open')                  # hors de tout foyer
        # Tout PNJ ouvre (LK04-T07) : pillard ou sans groupe compris.
        self.run_lua('LivingKnox.Groups.get(LivingKnox.Groups.findNpc("lk-1")).type = "raiders"')
        self.assertEqual(decide(104, 120), 'open')
        self.run_lua('LivingKnox.Groups.findNpc = function() return nil end')
        self.assertEqual(decide(104, 120), 'open')
        # Fenêtre verrouillée du foyer du PNJ : refusée (il passe par la porte).
        self.window(x=108, y=103, kind='W', locked=True)          # intérieure, dans B1
        self.run_lua('LivingKnox.Groups.findNpc = function() return "grp-2" end')
        self.assertEqual(decide(108, 103)[1], 'locked window')

    def test_window_beside_the_body_not_faced_is_left_alone(self):
        self.window()
        self.run_lua('LivingKnox.Obstacles.WINDOW_GESTURE = false')   # bascule immédiate (geste : WindowGestureTests)
        zid = self.start()
        self.friendly_group()
        self.run_lua(f'HARNESS.place(HARNESS.zombies[{zid}], 105.6, 102.5, 0); HARNESS.zombies[{zid}].angle = 90')
        self.move()
        self.run_lua('LivingKnox.Obstacles.track = {}')
        self.assertIs(self.run_lua(f'return LivingKnox.Obstacles.checkWindows("lk-1", '
                                   f'LivingKnox.Directives.entries["lk-1"], HARNESS.zombies[{zid}], 5000)'), False)
        self.run_lua(f'HARNESS.zombies[{zid}].angle = 0')
        self.assertIs(self.run_lua(f'return LivingKnox.Obstacles.checkWindows("lk-1", '
                                   f'LivingKnox.Directives.entries["lk-1"], HARNESS.zombies[{zid}], 5000)'), True)
        self.assertEqual(self.wstate('solo'), 'true false')
        self.assertEqual(self.wcount('solo'), (1, 0))
        # Déjà ouverte : rien de plus (une seule bascule).
        self.assertIs(self.run_lua(f'return LivingKnox.Obstacles.checkWindows("lk-1", '
                                   f'LivingKnox.Directives.entries["lk-1"], HARNESS.zombies[{zid}], 5000)'), False)
        self.assertEqual(self.wcount('solo'), (1, 0))


class TraversalFixTests(ObstacleBase):
    """LK04-T08 : défauts de lk.traversal constatés en jeu le 2026-10-11 (20261011-134445-solo.txt)."""
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', LANE_DOUBLES)
        h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        return h

    def trip(self, ticks=900):
        zid = self.start()
        self.move()
        self.walk_w(zid, ticks, until=self.done())
        return zid

    def site(self, pick, px=100, py=102):
        return self.run_lua(
            f'local p = {{ getX = function() return {px} end, getY = function() return {py} end, '
            f'getZ = function() return 0 end }} '
            f'local s = RST.LKTraversal.findSite(p, RST.LKTraversal.{pick}) '
            f'return s and s.e.key, s and (s.start:getX() .. "," .. s.start:getY())')

    # Fenêtre ouverte : ERROR « expected 1 argument, got 2 » (Bodies.find rend deux valeurs, toutes passées à
    # ToggleWindow quand l'appel est le dernier argument).
    def test_suite_toggles_a_window_with_the_body_only(self):
        self.init()
        self.spawn()
        self.window()
        res = self.run_lua('return pcall(RST.LKTraversal.setOpen, WINDOWS["106,102,0,W"], "lk-1", true)')
        ok = res[0] if isinstance(res, tuple) else res
        self.assertIs(ok, True, res)
        self.assertEqual(self.wstate('solo'), 'true false')
        self.assertEqual(lua_list(self.h.eval('solo', 'TOGGLED_BY')), ['zombie'])

    # Fenêtres cassée, fermée, verrouillée : le corps posé derrière un mur (case de départ non reliée, apparition
    # décalée) passait par une autre fenêtre ; le site doit offrir une voie droite reliée jusqu'à l'obstacle.
    def test_site_lane_is_connected_and_spawnable(self):
        self.init()
        self.window()                                     # la plus proche, mais mur entre (103,102) et (104,102)
        self.run_lua('WALLS["104,102,0,W"] = true')
        self.window(x=106, y=108)                         # voie libre
        self.assertEqual(self.site('pickWindow'), ('106,108,0,W', '103,108'))
        # Case de départ où un corps n'apparaîtrait pas (Bodies.freeSquare faux) : site écarté.
        self.run_lua('local f = LivingKnox.Bodies.freeSquare; LivingKnox.Bodies.freeSquare = function(sq) '
                     'if sq:getX() == 103 and sq:getY() == 108 then return false end return f(sq) end')
        self.assertIsNone(self.site('pickWindow')[0])
        # Porte, fenêtre ou clôture sur la voie (hors de l'obstacle) : écartée aussi.
        self.run_lua('WALLS["104,102,0,W"] = nil')
        self.window(x=108, y=102)                         # entre (107,102) et (108,102), côté arrivée
        self.assertIsNone(self.site('pickWindow')[0])

    def test_site_crossing_is_measured_on_the_obstacle_edge(self):
        self.init()
        self.window()
        self.run_lua('E = RST.LKTraversal.findSite({ getX = function() return 100 end, getY = function() return 102 '
                     'end, getZ = function() return 0 end }, RST.LKTraversal.pickWindow).e')
        cross = 'return RST.LKTraversal.crossed(E, {}, {}, {}, {})'
        self.assertIs(self.run_lua(cross.format(105.6, 102.5, 106.3, 102.5)), True)
        self.assertIs(self.run_lua(cross.format(105.6, 104.5, 106.3, 104.5)), False)   # deux cases à côté
        self.assertIs(self.run_lua(cross.format(105.2, 102.5, 105.8, 102.5)), False)   # pas encore passé

    # Clôture basse : le site trouvé était un portail (porte basse) verrouillé ; l'autorité refusait la consigne
    # pendant que le moteur l'enjambait.
    def test_locked_low_gate_is_climbed_and_never_refused(self):
        self.door(hoppable=True, locked=True)
        self.run_lua('CLIMB_TICKS = 250')                 # 4 s d'escalade, comme en jeu
        self.trip(1500)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), ['climbfence ' + DOOR_KEY])
        self.assertEqual(self.o('stats.refused'), 0)
        self.assertEqual(self.counters('solo'), (0, 0))
        self.assertEqual(self.state('solo'), 'false true false')
        self.assertEqual(self.h.errors('solo'), [])

    def test_executor_does_not_wait_at_a_closed_low_gate(self):
        self.door(hoppable=True)
        zid = self.start()
        self.run_lua(f'HARNESS.place(HARNESS.zombies[{zid}], 105.5, 102.5, 0)')
        self.assertIsNone(self.ev(f'LivingKnox.Executor.closedDoorNext(HARNESS.zombies[{zid}])'))
        self.run_lua('DOORS["106,102,0,W"].hoppable = false')
        self.assertIsNotNone(self.ev(f'LivingKnox.Executor.closedDoorNext(HARNESS.zombies[{zid}])'))

    def test_fence_site_skips_gates(self):
        self.init()
        self.door(hoppable=True)                          # portail, le plus proche
        self.fence(x=106, y=108)
        self.assertEqual(self.site('pickFence')[0], '106,108,0,W')

    # Fenêtre cassée : jamais basculée par l'autorité (ni compteur ni appel).
    def test_broken_window_is_never_toggled_by_the_authority(self):
        self.window(destroyed=True)
        zid = self.start()
        self.assertIs(self.o(f'setWindow(WINDOWS["{DOOR_KEY}"], true, HARNESS.zombies[{zid}])'), False)
        self.assertIs(self.o(f'setWindow(WINDOWS["{DOOR_KEY}"], false, nil)'), False)
        self.assertEqual(self.o('stats.windowToggles'), 0)
        self.assertEqual(self.wcount('solo'), (0, 0))
        self.move()
        self.walk_w(zid, 900, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.o('stats.windowToggles'), 0)

    # Fenêtre verrouillée : refus noté avec son bord (la suite vérifie que c'est bien la fenêtre du site).
    def test_locked_window_refusal_names_its_edge(self):
        self.window(locked=True)
        zid = self.start()
        self.friendly_group()
        self.move()
        self.walk_w(zid, 900, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.o('lastRefused.key'), DOOR_KEY)
        self.assertEqual(self.o('lastRefused.what'), 'window')
        self.assertEqual(self.o('lastRefused.id'), 'lk-1')
        self.assertEqual(self.o('lastRefused.why'), 'locked window')
        self.assertEqual(self.wcount('solo'), (0, 0))
        self.assertEqual(self.wstate('solo'), 'false false')


class DoorFirstTests(ObstacleBase):
    """LK04-T09 : porte d'abord. Mur (ou clôture basse) le long du bord ouest de x = 106, de y = 90 à 125, percé d'une
    fenêtre ou d'une clôture en (106, 102) sur la ligne droite départ (102, 102) -> destination (111, 102) ; porte ou
    portail ailleurs sur la même ligne. Les doublures de marche ignorent les murs : seul le guidage par points de
    passage fait passer le corps par la porte."""
    mode = 'solo'

    def line(self, fence=False, skip=()):
        for y in range(90, 126):
            if y in skip:
                continue
            table = 'FENCES' if fence else 'WALLS'
            self.run_lua(f'{table}["106,{y},0,W"] = true')

    def trip(self, ticks=1500):
        zid = self.start()
        self.move()
        self.walk_w(zid, ticks, until=self.done())
        return zid

    def steps(self):
        w = self.entry('w')
        return [] if w is None else [(w[i].x, w[i].y) for i in range(1, len(w) + 1)]

    def test_open_door_next_to_an_open_window_is_used(self):
        self.line(skip=(102, 105))
        self.window(open=True)
        self.door(y=105, open=True)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        steps = self.steps()
        self.assertTrue(any(x == 105 for x, _ in steps) and any(x >= 106 for x, _ in steps), steps)
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.wstate('solo'), 'true false')
        self.assertEqual(self.o('stats.routedByDoor'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_plant_next_to_the_door_exit_keeps_the_door_route(self):
        # Campagne solo du 2026-10-15 (runs/20261015-122214-c3211ee9c847) : plante sur la case voisine de la sortie de
        # la porte : tout le trajet par la porte était écarté (« door route dropped »), PNJ bloqués contre la fenêtre.
        self.line(skip=(102, 105))
        self.window(open=True)
        self.door(y=105, open=True)
        self.run_lua('getCell():getGridSquare(107, 104, 0).plant = true')
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        steps = self.steps()
        self.assertTrue(any(x == 105 for x, _ in steps) and any(x >= 106 for x, _ in steps), steps)
        self.assertEqual(self.climbs('solo'), [])
        self.assertFalse(any('door route dropped' in line for line in self.lk()), self.lk())

    def test_plant_on_a_square_of_the_door_route_drops_it(self):
        # Plante SUR une case du trajet par la porte : le potager prime (LK04-T06), le trajet par la porte est écarté.
        self.line(skip=(102, 105))
        self.window(open=True)
        self.door(y=105, open=True)
        self.run_lua('getCell():getGridSquare(106, 105, 0).plant = true')
        self.start()
        self.move()
        self.assertEqual(self.steps(), [])
        self.assertTrue(any('door route dropped' in line for line in self.lk()), self.lk())

    def test_closed_gate_is_opened_instead_of_climbing_the_fence(self):
        self.line(fence=True, skip=(105,))
        self.door(y=105, hoppable=True)
        zid = self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.o('stats.opened'), 1)
        self.walk_w(zid, 60)
        self.assertEqual(self.counters('solo'), (2, 0))             # ouvert puis refermé, jamais ToggleDoor(corps)
        self.assertEqual(self.state('solo', '106,105,0,W'), 'false false false')
        self.assertEqual(self.h.errors('solo'), [])

    def test_window_is_the_last_resort_without_a_door(self):
        self.line(skip=(102,))
        self.window(open=True)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.steps(), [])
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])
        self.assertEqual(self.o('stats.routedByDoor'), 0)

    def test_door_beyond_the_detour_limit_is_not_used(self):
        self.line(skip=(102, 120))
        self.window(open=True)
        self.door(y=120, open=True)                     # 18 cases plus loin : détour d'environ 36 cases > 20
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.steps(), [])
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])

    def test_locked_door_without_key_is_not_a_way(self):
        self.line(skip=(102, 105))
        self.window(open=True)
        self.door(y=105, locked=True)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.steps(), [])
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])
        self.assertEqual(self.counters('solo'), (0, 0))

    def test_locked_gate_of_a_stranger_is_climbed(self):
        # LK04-T08 inchangé : portail verrouillé (aucune clé) = clôture, enjambé, jamais refusé.
        self.line(fence=True, skip=(102,))
        self.door(hoppable=True, locked=True)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.steps(), [])
        self.assertEqual(self.climbs('solo'), ['climbfence ' + DOOR_KEY])
        self.assertEqual(self.o('stats.refused'), 0)

    def test_rule_can_be_switched_off(self):
        self.line(skip=(102, 105))
        self.window(open=True)
        self.door(y=105, open=True)
        self.run_lua('LivingKnox.Obstacles.DOORS_FIRST = false')
        self.trip()
        self.assertEqual(self.steps(), [])
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])

    def test_gate_is_opened_before_the_step_in_front_of_it_is_reached(self):
        # Le point « case avant le portail » est atteint à une case près : le portail doit être ouvert avant (étape
        # suivante prise en compte), sinon un corps qui court l'atteindrait fermé et l'enjamberait.
        self.line(fence=True, skip=(105,))
        self.door(y=105, hoppable=True)
        self.trip()
        logs = self.h.logs('solo')
        steps = self.steps()
        k = steps.index((105, 105)) + 1                       # point « case avant le portail »
        opened = next(i for i, line in enumerate(logs) if 'door 106,105,0,W opened' in line)
        reached = next(i for i, line in enumerate(logs) if f'step {k}/{len(steps) + 1} reached' in line)
        self.assertLess(opened, reached)

    def test_suite_door_site_is_a_window_routed_through_a_door(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        self.init()
        self.line(skip=(102, 105))
        self.window()
        self.door(y=105)
        res = self.run_lua('local s = RST.LKTraversal.findDoorSite({ getX = function() return 100 end, getY = function() '
                           'return 102 end, getZ = function() return 0 end }) '
                           'return s and s.e.key, s and s.doorEdges[1].key, s and s.start:getX() .. "," .. s.start:getY()')
        self.assertEqual(res, ('106,102,0,W', '106,105,0,W', '103,102'))
        # Sans porte : aucun site.
        self.run_lua('DOORS["106,105,0,W"].removed = true; WALLS["106,105,0,W"] = true')
        res = self.run_lua('return RST.LKTraversal.findDoorSite({ getX = function() return 100 end, getY = function() '
                           'return 102 end, getZ = function() return 0 end }) == nil')
        self.assertIs(res, True)

    def test_route_search_is_bounded(self):
        self.line(skip=(102, 105))
        self.window(open=True)
        self.door(y=105, open=True)
        self.init()
        self.run_lua('LivingKnox.Obstacles.ROUTE_MAX_NODES = 5')
        res = self.run_lua('local w, info = LivingKnox.Obstacles.planDoorRoute("lk-1", 102.5, 102.5, 111, 102, 0) '
                           'return #w, info.reason')
        self.assertEqual(res[0], 0)
        self.assertIn('more than 5 squares', res[1])
        self.run_lua('LivingKnox.Obstacles.ROUTE_MAX_NODES = 4000')
        res = self.run_lua('local w, info = LivingKnox.Obstacles.planDoorRoute("lk-1", 102.5, 102.5, 111, 102, 0) '
                           'local s = {} for i = 1, #w do s[i] = w[i].x .. "," .. w[i].y end '
                           'return table.concat(s, " "), info.climbs, info.npcClimbs, info.doors')
        # Cases avant et après la porte, jalons rapprochés avant et après (LK04-T09, 3e correction).
        self.assertEqual(res, ('104,104 105,105 107,105 109,104', 1, 0, 1))


class DoorFirstRejoinTests(ObstacleBase):
    """LK04-T09 (essai solo du 2026-10-11, partie rstest-1011) : porte d'abord, mais le chemin natif reprend la fenêtre
    APRÈS la porte. Maison (murs) x 100..109, y 95..104 ; corps dedans en (105, 103), cible dehors en (105, 107) au
    sud ; fenêtre ouverte au milieu du mur sud (bord 105,105,0,N) ; porte ouverte dans le mur ouest (bord
    100,101,0,W) ; muret d'une case prolongeant le mur sud vers l'ouest (bord 99,105,0,N). Depuis la case après la
    porte, le plus court chemin d'un zombie revient par la porte et ressort par la fenêtre : la suite des points de
    passage doit l'en empêcher (chaque tronçon parcouru « comme un zombie » ne franchit aucune fenêtre)."""
    mode = 'solo'
    START, TARGET = (105.5, 103.5), (105, 107)

    def house(self):
        walls = [f'100,{y},0,W' for y in range(95, 105) if y != 101]
        walls += [f'110,{y},0,W' for y in range(95, 105)]
        walls += [f'{x},95,0,N' for x in range(100, 110)]
        walls += [f'{x},105,0,N' for x in range(99, 110) if x != 105]
        for m in self.machines:
            self.h.load(m, '; '.join(f'WALLS["{k}"] = true' for k in walls))
        self.window(x=105, y=105, kind='N', open=True)
        self.door(x=100, y=101, kind='W', open=True)
        self.init()

    def plan(self):
        res = self.run_lua(
            'local w, info = LivingKnox.Obstacles.planDoorRoute("lk-1", %s, %s, %d, %d, 0) '
            'local s = {} for i = 1, #w do s[#s + 1] = w[i].x .. "," .. w[i].y end '
            'return table.concat(s, " "), info.reason, info.doors or 0'
            % (self.START[0], self.START[1], self.TARGET[0], self.TARGET[1]))
        pts = [tuple(int(v) for v in p.split(',')) for p in res[0].split()] if res[0] else []
        return pts, res[1], res[2]

    def zombie_climbs(self, a, b):
        """Franchissements (fenêtre, clôture) du chemin d'un zombie de la case a à la case b, et franchissements de
        porte."""
        return self.run_lua(
            'local r = LivingKnox.Obstacles.findRoute("lk-1", %d + 0.5, %d + 0.5, %d, %d, 0, "zombie") '
            'if r == nil then return -1, -1 end local c, d = 0, 0 '
            'for _, p in ipairs(r) do if p.cross == "climb" then c = c + 1 elseif p.cross == "door" then d = d + 1 end end '
            'return c, d' % (a[0], a[1], b[0], b[1]))

    def test_vanilla_path_after_the_door_would_take_the_window_back(self):
        # Constat du banc : sans points au-delà de la porte, le corps sorti par la porte y revient.
        self.house()
        self.assertEqual(self.zombie_climbs((98, 101), self.TARGET), (1, 1))
        self.assertEqual(self.zombie_climbs((105, 103), self.TARGET)[0], 1)

    def test_every_leg_of_the_plan_avoids_the_window(self):
        self.house()
        pts, reason, doors = self.plan()
        self.assertEqual(doors, 1, reason)
        self.assertTrue(pts, reason)
        i = pts.index((100, 101))                             # case avant la porte (dedans)
        self.assertTrue(all(x <= 99 or y >= 105 for x, y in pts[i + 1:]), pts)   # les suivants dehors
        legs = [(int(self.START[0]), int(self.START[1]))] + pts + [self.TARGET]
        for a, b in zip(legs, legs[1:]):
            self.assertEqual(self.zombie_climbs(a, b)[0], 0, f'leg {a} -> {b} of {pts}')
        extra = self.run_lua('local _, info = LivingKnox.Obstacles.planDoorRoute("lk-1", 105.5, 103.5, 105, 107, 0) '
                             'return info.extra, info.unsafe, info.blind')
        self.assertGreaterEqual(extra[0], 1)
        self.assertIsNone(extra[1])
        self.assertEqual(extra[2], 0)
        self.assertIn('clear lines', reason)
        self.assertEqual(self.h.errors('solo'), [])

    def test_body_walks_out_through_the_door_and_round_the_house(self):
        # Trajet complet au banc (les doublures de marche ignorent les murs, pas la fenêtre) : étapes de la consigne =
        # points planifiés, arrivée, aucune escalade.
        self.house()
        pts, _, _ = self.plan()
        _, body = self.spawn(x=105, y=103)
        zid = body.onlineID
        self.d('moveTo("lk-1", 105, 107, 0)')
        self.walk_w(zid, 2000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        w = self.entry('w')
        self.assertEqual([(w[i].x, w[i].y) for i in range(1, len(w) + 1)], pts)
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_steps_are_bounded(self):
        # Au-delà de ROUTE_MAX_POINTS jalons : seules les cases des portes restent, raison donnée.
        self.house()
        self.run_lua('LivingKnox.Obstacles.ROUTE_MAX_POINTS = 2')
        pts, reason, doors = self.plan()
        self.assertEqual(doors, 1)
        self.assertIn('legs may still cross: more than 2 steps, door steps only', reason)
        self.assertEqual(pts, [(100, 101)])


class DoorFirstCounterTests(ObstacleBase):
    """LK04-T09, 3e correction (essais solo du 2026-10-11 21:27 et 21:42, rstest-1011 : corps sorti par la porte
    10694,9381 W, puis chemin natif par la fenêtre verrouillée 10693,9387 N, au-dessus du comptoir 10693,9386). Le
    chemin vanilla tient pour praticable une case « solidtrans » qui borde une fenêtre (J/pathfind/Square.java:60-62) ;
    isFree(false) la dit pleine, et le modèle « zombie » de l'A* Lua ne voyait pas ce raccourci. Maison (murs)
    x 100..109, y 95..104 ; corps dedans en (107, 103), cible dehors en (104, 108) ; porte ouverte dans le mur ouest
    (bord 100,101,0,W) ; fenêtre ouverte A au mur sud (bord 107,105,0,N, le chemin « zombie » la prend) ; fenêtre
    ouverte B au mur sud (bord 102,105,0,N) au-dessus d'un comptoir (case 102,104 : blocked + solidTrans). La doublure
    de marche va en ligne droite (murs ignorés) et escalade toute fenêtre croisée, comme le chemin natif coupe par la
    fenêtre B : avant la correction, le tronçon 100,101 -> 103,108 la croisait."""
    mode = 'solo'
    START, TARGET = (107, 103), (104, 108)

    def house(self, counter=True):
        walls = [f'100,{y},0,W' for y in range(95, 105) if y != 101]
        walls += [f'110,{y},0,W' for y in range(95, 105)]
        walls += [f'{x},95,0,N' for x in range(100, 110)]
        walls += [f'{x},105,0,N' for x in range(100, 110) if x not in (102, 107)]
        self.h.load('solo', '; '.join(f'WALLS["{k}"] = true' for k in walls))
        self.window(x=107, y=105, kind='N', open=True)
        self.window(x=102, y=105, kind='N', open=True)
        if counter:
            self.h.load('solo', 'local s = getCell():getGridSquare(102, 104, 0) s.blocked = true s.solidTrans = true')
        self.door(x=100, y=101, kind='W', open=True)
        self.init()

    def route(self, a, b, mode):
        res = self.run_lua(
            'local r = LivingKnox.Obstacles.findRoute("lk-1", %d + 0.5, %d + 0.5, %d, %d, 0, "%s") '
            'if r == nil then return "" end local s = {} '
            'for _, p in ipairs(r) do s[#s + 1] = p.x .. "," .. p.y .. "," .. tostring(p.cross) end '
            'return table.concat(s, " ")' % (a[0], a[1], b[0], b[1], mode))
        return [(int(x), int(y), c) for x, y, c in (p.split(',') for p in res.split())]

    def plan(self):
        res = self.run_lua(
            'local w, info = LivingKnox.Obstacles.planDoorRoute("lk-1", %d.5, %d.5, %d, %d, 0) '
            'local s = {} for i = 1, #w do s[#s + 1] = w[i].x .. "," .. w[i].y end '
            'return table.concat(s, " "), info.reason, info.doors or 0, info.blind or 0'
            % (self.START[0], self.START[1], self.TARGET[0], self.TARGET[1]))
        pts = [tuple(int(v) for v in p.split(',')) for p in res[0].split()] if res[0] else []
        return pts, res[1], res[2], res[3]

    def test_zombie_model_climbs_over_a_counter_under_a_window(self):
        # Modèle « zombie » : la case du comptoir sous la fenêtre B est praticable (chemin natif) ; pas pour un PNJ.
        self.house()
        self.assertEqual(self.ev('LivingKnox.Obstacles.squareKind(getCell():getGridSquare(102, 104, 0))'), 3)
        z = self.route((102, 103), (102, 106), 'zombie')
        self.assertIn((102, 104, 'nil'), z)
        self.assertEqual(sum(1 for p in z if p[2] == 'climb'), 1)
        self.assertNotIn((102, 104), [(x, y) for x, y, _ in self.route((102, 103), (102, 106), 'npc')])
        # Comptoir loin de toute fenêtre : plein pour les deux modèles.
        self.h.load('solo', 'local s = getCell():getGridSquare(104, 102, 0) s.blocked = true s.solidTrans = true')
        self.assertEqual(self.ev('LivingKnox.Obstacles.squareKind(getCell():getGridSquare(104, 102, 0))'), 0)

    def test_every_leg_is_a_short_clear_line(self):
        self.house()
        pts, reason, doors, blind = self.plan()
        self.assertEqual(doors, 1, reason)
        self.assertIn((100, 101), pts)
        self.assertEqual(blind, 0, reason)
        step = self.o('ROUTE_STEP')
        legs = [(self.START[0] + 0.5, self.START[1] + 0.5)] + [(x + 0.5, y + 0.5) for x, y in pts] \
            + [(self.TARGET[0] + 0.5, self.TARGET[1] + 0.5)]
        for a, b in zip(legs, legs[1:]):
            self.assertLessEqual(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5, step + 1e-9, f'{a} -> {b} of {pts}')
            self.assertIs(self.ev('LivingKnox.Obstacles.lineClear("lk-1", %s, %s, %s, %s, 0)' % (a + b)), True,
                          f'{a} -> {b} of {pts}')

    def test_body_takes_the_door_and_never_cuts_through_the_window_over_the_counter(self):
        # Trajet complet : la doublure de marche coupe en ligne droite par toute fenêtre croisée (chemin natif).
        self.house()
        pts, _, _, _ = self.plan()
        _, body = self.spawn(x=self.START[0], y=self.START[1])
        zid = body.onlineID
        self.d('moveTo("lk-1", %d, %d, 0)' % self.TARGET)
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        w = self.entry('w')
        self.assertEqual([(w[i].x, w[i].y) for i in range(1, len(w) + 1)], pts)
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.h.errors('solo'), [])


UNLOAD_DOUBLES = r'''
-- Zone chargée : getGridSquare rend nil pour les cases de UNLOADED (clé "x,y,z").
UNLOADED = {}
local C = getmetatable(getCell())
local base = C.getGridSquare
C.getGridSquare = function(self, x, y, z)
    if UNLOADED[x .. ',' .. y .. ',' .. z] then return nil end
    return base(self, x, y, z)
end
'''

HOME_SQ = '108,101,0'


class HomeShutTests(ObstacleBase):
    """LK04-T10 : portes extérieures ouvertes du foyer fermées et verrouillées à l'arrivée (solo)."""
    mode = 'solo'

    def wait_ms(self, ms):
        """ms puis deux passages : arrivée notée au premier passage, fermeture à un passage suivant."""
        self.h.tick(ms // self.h.tick_ms + 2 * self.o('PASS_EVERY') + 1)

    def arrive(self):
        """Foyer, porte extérieure ouverte (DOOR) et porte intérieure ouverte ; groupe créé = arrivée."""
        self.building()
        self.door(open=True)                                  # extérieure, ouverte
        self.door(x=108, y=102, kind='W', open=True)          # intérieure, ouverte
        zid = self.start()
        self.group(member=True)
        return zid

    def no_arrival(self):
        return self.ev('(function() for _ in pairs(LivingKnox.Obstacles.arrivals) do return false end '
                       'return true end)()')

    def test_open_exterior_door_closed_and_locked_interior_left(self):
        self.arrive()
        self.h.tick(self.o('PASS_EVERY'))
        self.assertEqual(self.state('solo'), 'true false false')              # pas avant SHUT_DELAY_MS
        self.wait_ms(self.o('SHUT_DELAY_MS'))
        self.assertEqual(self.state('solo'), 'false true true')
        self.assertEqual(self.h.eval('solo', 'DOOR_STATE("108,102,0,W")'), 'true false false')
        self.assertEqual(self.h.eval('solo', f'DOORS["{DOOR_KEY}"].keyId'), 77)  # clé du bâtiment
        self.assertEqual(self.o('stats.shut'), 1)
        self.assertEqual(self.counters('solo'), (1, 0))                      # une bascule, jamais ToggleDoor
        self.assertTrue(any('closed and locked' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('solo'), [])

    def test_occupied_door_is_retried_then_closed(self):
        self.arrive()
        self.h.move_player('A', 105.5, 102.5, 0)               # joueur dans l'encadrement
        self.wait_ms(self.o('SHUT_DELAY_MS') + 2 * self.o('SHUT_RETRY_MS'))
        self.assertEqual(self.state('solo'), 'true false false')
        self.assertGreaterEqual(self.o('stats.shutBusy'), 2)
        self.h.move_player('A', 96, 108, 0)
        self.wait_ms(self.o('SHUT_RETRY_MS'))
        self.assertEqual(self.state('solo'), 'false true true')
        self.assertEqual(self.counters('solo'), (1, 0))

    def test_door_reopened_by_a_player_stays_open_until_the_next_arrival(self):
        self.arrive()
        self.wait_ms(self.o('SHUT_DELAY_MS'))
        self.assertEqual(self.state('solo'), 'false true true')
        self.run_lua(f'local d = DOORS["{DOOR_KEY}"] d.open, d.locked, d.lockedByKey = true, false, false')
        self.wait_ms(self.o('SECURE_EVERY_MS') + self.o('SHUT_GIVE_UP_MS'))
        self.assertEqual(self.state('solo'), 'true false false')               # aucune bataille
        self.assertEqual(self.o('stats.shut'), 1)
        self.run_lua(UNLOAD_DOUBLES + f'UNLOADED["{HOME_SQ}"] = true')           # joueur parti : foyer déchargé
        self.wait_ms(1000)
        self.assertIs(self.no_arrival(), True)
        self.run_lua(f'UNLOADED["{HOME_SQ}"] = nil')                            # nouvelle arrivée
        self.wait_ms(self.o('SHUT_DELAY_MS'))
        self.assertEqual(self.state('solo'), 'false true true')
        self.assertEqual(self.o('stats.shut'), 2)

    def test_door_on_the_path_of_a_member_is_left_until_it_passed(self):
        zid = self.arrive()
        self.run_lua('LivingKnox.Obstacles.SHUT_DELAY_MS = 3600000')
        self.move()
        self.walk_d(zid, 400, until=lambda: self.h.zombie('solo', zid).x >= 104.6)
        self.assertGreaterEqual(self.h.zombie('solo', zid).x, 104.6)       # à moins de 1,5 case de la porte
        self.run_lua('for _, a in pairs(LivingKnox.Obstacles.arrivals) do a.due = 0 end')
        self.walk_d(zid, self.o('PASS_EVERY'))
        self.assertEqual(self.state('solo'), 'true false false')           # sur son trajet : laissée
        self.assertGreaterEqual(self.o('stats.shutBusy'), 1)
        self.walk_d(zid, 1200, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.wait_ms(self.o('SHUT_RETRY_MS'))
        self.assertEqual(self.state('solo'), 'false true true')
        self.assertEqual(self.counters('solo'), (1, 0))

    def test_barricaded_destroyed_double_doors_are_never_closed(self):
        self.building()
        self.door(open=True, barricaded=True)
        self.door(x=107, y=105, kind='N', open=True, double=True)
        self.door(x=109, y=105, kind='N', open=True, destroyed=True)
        self.start()
        self.group(member=True)
        self.wait_ms(self.o('SHUT_DELAY_MS'))
        self.assertEqual(self.state('solo'), 'true false false')
        self.assertEqual(self.h.eval('solo', 'DOOR_STATE("107,105,0,N")'), 'true false false')
        self.assertEqual(self.h.eval('solo', 'DOOR_STATE("109,105,0,N")'), 'true false false')
        self.assertEqual(self.o('stats.shutRefused'), 3)
        self.assertEqual(self.counters('solo'), (0, 0))

    def test_door_still_occupied_is_given_up(self):
        self.arrive()
        self.h.move_player('A', 106.5, 102.5, 0)
        self.wait_ms(self.o('SHUT_GIVE_UP_MS') + self.o('SHUT_RETRY_MS'))
        self.assertEqual(self.o('stats.shutGivenUp'), 1)
        self.h.move_player('A', 96, 108, 0)
        self.wait_ms(self.o('SECURE_EVERY_MS'))
        self.assertEqual(self.state('solo'), 'true false false')
        self.assertTrue(any('left open' in s for s in self.lk()), self.lk())


class MultiplayerHomeShutTests(ObstacleBase):
    def test_server_closes_and_locks_once_clients_see_it(self):
        self.building()
        self.door(open=True)
        self.npc()
        self.group(member=True)
        self.h.tick(self.o('SHUT_DELAY_MS') // self.h.tick_ms + 2 * self.o('PASS_EVERY') + 1)
        self.relay_doors()
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.state(m), 'false true true', m)
        self.assertEqual(self.counters('server'), (1, 0))
        for c in ('A', 'B'):
            self.assertEqual(self.counters(c), (0, 0))
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Obstacles'))


class TraversalSuiteTests(ObstacleBase):
    mode = 'solo'

    def test_dev_suite_lists_with_world_tags(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.traversal", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.traversal')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertEqual(listed.count, 18)   # LK04-T15, LK04-T16 ; LK04-T17 : porte verrouillée ouverte de l'intérieur ;
        #                                      LK04-T19 : porte intérieure reverrouillée ou non ; LK04-T20 : PNJ enfermé


class TraversalFix1011Tests(ObstacleBase):
    """Défauts de lk.traversal constatés en jeu le 2026-10-11 à 14:58 (20261011-145803-solo.txt) : corps posé au coin
    de sa case de départ (clôture basse SKIP), site « porte d'abord » choisi avec la fenêtre fermée et verrouillée puis
    essayé fenêtre ouverte, maison du foyer à deux portes extérieures ouvertes."""
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        return h

    def run_suite_test(self, name, ticks=2000):
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.traversal", tags = "world", test = "%s" }, '
                                          '{ ctx = { player = getPlayer() } }))' % name), True)
        for _ in range(ticks):
            self.h.tick()
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        return [(r.test, r.status, r.message) for r in lua_list(report.results)]

    # Clôture basse : corps relevé au coin (10693.0, 10245.0) de sa case de départ, écart latéral de 0,5 : SKIP à tort.
    def test_body_on_a_corner_of_its_start_square_is_on_the_lane(self):
        self.init()
        self.fence()
        site = ('RST.LKTraversal.findSite({ getX = function() return 100 end, getY = function() return 102 end, '
                'getZ = function() return 0 end }, RST.LKTraversal.pickFence)')
        self.run_lua(f'SITE = {site}')
        on = 'return (RST.LKTraversal.onLane(SITE, {}, {}, 0))'
        self.assertEqual(self.run_lua(f'local s = {site} return s.e.key, s.start:getX() .. "," .. s.start:getY()'),
                         (DOOR_KEY, '103,102'))
        self.assertIs(self.run_lua(on.format(103.0, 102.0)), True)       # coin nord-ouest de la case de départ
        self.assertIs(self.run_lua(on.format(103.5, 102.5)), True)
        self.assertIs(self.run_lua(on.format(104.99, 102.99)), True)     # case suivante de la voie
        self.assertIs(self.run_lua(on.format(103.5, 103.0)), False)      # case voisine, hors de la voie
        self.assertIs(self.run_lua(on.format(102.9, 102.5)), False)      # derrière le départ
        self.assertIs(self.run_lua(on.format(105.5, 102.5)), False)      # contre l'obstacle
        self.assertIs(self.run_lua('return (RST.LKTraversal.onLane(SITE, 103.5, 102.5, 1))'), False)

    # Porte d'abord : fenêtre fermée et verrouillée au choix du site (infranchissable pour l'itinéraire du PNJ, d'où la
    # porte), puis ouverte par le test : la porte, trop loin (détour > ROUTE_PENALTY), n'était plus préférée.
    def test_door_site_is_probed_with_its_window_open(self):
        line = DoorFirstTests.line
        line(self, skip=(102, 114))
        self.init()
        self.window(locked=True)
        self.door(y=114)                                   # détour d'environ 27 cases (> 5 + 20) fenêtre ouverte
        probe = ('return RST.LKTraversal.findDoorSite({ getX = function() return 100 end, getY = function() '
                 'return 102 end, getZ = function() return 0 end }) == nil')
        self.assertIs(self.run_lua(probe), True)
        self.assertEqual(self.wstate('solo'), 'false false')
        self.assertIs(self.h.eval('solo', f'WINDOWS["{DOOR_KEY}"]:isLocked()'), True)   # verrou rendu
        # Porte proche : site retenu, et l'autorité guide encore par la porte une fois la fenêtre ouverte.
        self.run_lua('WALLS["106,105,0,W"] = nil')
        self.door(y=105)
        res = self.run_lua('local s = RST.LKTraversal.findDoorSite({ getX = function() return 100 end, getY = function() '
                           'return 102 end, getZ = function() return 0 end }) return s and s.doorEdges[1].key')
        self.assertEqual(res, '106,105,0,W')
        self.assertIs(self.h.eval('solo', f'WINDOWS["{DOOR_KEY}"]:isLocked()'), True)

    # Foyer : la maison avait une seconde porte extérieure ouverte, fermée aussi (stats.shut + 2) : le test doit
    # vérifier SA porte, sans supposer qu'elle est la seule ; les autres portes de la maison sont rendues.
    def test_home_door_suite_test_with_two_open_exterior_doors(self):
        self.building()
        self.door()                                        # porte du test (la plus proche du joueur, 100,100)
        self.door(x=109, y=105, kind='N', open=True)       # seconde porte extérieure ouverte
        self.init()
        results = self.run_suite_test('open exterior door of a home')
        self.assertEqual(len(results), 1, results)
        self.assertEqual(results[0][1], 'PASS', results)
        self.assertEqual(self.o('stats.shut'), 2)
        self.assertEqual(self.state('solo'), 'false false false')                       # rendue (fermée au départ)
        self.assertEqual(self.h.eval('solo', 'DOOR_STATE("109,105,0,N")'), 'true false false')   # rendue ouverte

    # Essai en jeu du 2026-10-11 23:58 (20261011-215800-solo.txt) : porte 10745,9528,0,W juste à côté de la fenêtre
    # 10745,9529,0,W ; corps passé par la porte (aucun climbwindow) mais mesuré à travers le bord de la fenêtre près
    # du coin. Site ambigu écarté (porte à moins de DOOR_GAP = 2 cases de la fenêtre).
    def test_door_site_next_to_its_window_is_left_out(self):
        probe = ('local s = RST.LKTraversal.findDoorSite({ getX = function() return 100 end, getY = function() '
                 'return 102 end, getZ = function() return 0 end }) return s and s.doorEdges[1].key')
        DoorFirstTests.line(self, skip=(102, 103))
        self.init()
        self.window()
        self.door(y=103)                                   # milieux des bords à 1 case : ambigu
        self.assertIsNone(self.run_lua(probe))
        self.run_lua('DOORS["106,103,0,W"].removed = true; WALLS["106,103,0,W"] = true; WALLS["106,104,0,W"] = nil')
        self.door(y=104)                                   # à 2 cases : retenu
        self.assertEqual(self.run_lua(probe), '106,104,0,W')

    def test_window_crossing_by_position_is_checked_on_a_server_only(self):
        src = TRAVERSAL_SUITE.read_text(encoding='utf-8')
        test = src[src.index('local function doorFirstTest('):]
        test = test[:test.index('RST.suite(')]
        self.assertIn('doorFirstTest(findDoorSite', src)
        self.assertIn('doorFirstTest(findExitSite', src)
        self.assertRegex(test, r'if isServer\(\) then\s+t3:ok\(not info\.through\[site\.e\.key\]')
        self.assertIn('if not isServer() then t3:ok(info.seen.climbwindow ~= true', test)


HOME9 ={'id': 'B9', 'x1': 300, 'y1': 300, 'x2': 306, 'y2': 306, 'keyId': 99}


class KeyTests(ObstacleBase):
    """LK04-T12 : clé vanilla du foyer dans l'inventaire du corps, seule à ouvrir une porte verrouillée (solo)."""
    mode = 'solo'

    def keys(self, npc='lk-1'):
        return self.ev(f'KEYS_ON((LivingKnox.Bodies.find("{npc}")))')

    def wait_keys(self):
        self.h.tick(self.o('KEYS_EVERY_MS') // self.h.tick_ms + 2 * self.o('PASS_EVERY') + 1)

    def test_member_carries_one_key_of_its_home_and_every_new_body_gets_its_own(self):
        self.building()
        self.init()
        self.group(member=True)                               # foyer (108, 101) dans B1 : clé 77
        npc_id, _ = self.spawn()
        self.assertEqual(npc_id, 'lk-1')
        self.assertEqual(self.keys(), '77')                   # posée à la liaison du corps
        self.assertEqual(self.ev('(LivingKnox.Bodies.find("lk-1")):getInventory():getItems():get(0):getModData()'
                                 '.LKHomeKey'), 'B1')
        self.wait_keys()
        self.assertEqual(self.keys(), '77')                   # relevé périodique : aucun doublon
        self.run_lua('LivingKnox.Bodies.bound["lk-1"] = nil LivingKnox.Bodies.scanAll()')   # corps relié
        self.assertEqual(self.ev('LivingKnox.Bodies.bound["lk-1"] ~= nil'), True)
        self.assertEqual(self.keys(), '77')
        self.run_lua('LivingKnox.Bodies.despawn("lk-1", false)')                 # rendu à la simulation
        self.assertIsNotNone(self.run_lua('return (LivingKnox.Bodies.embody("lk-1", 102, 102, 0))'))
        self.assertEqual(self.keys(), '77')                   # nouveau corps, sa propre clé
        self.assertEqual(self.o('stats.keysGiven'), 2)
        self.assertEqual(self.h.errors('solo'), [])

    def test_body_without_group_or_home_building_carries_no_key(self):
        self.init()
        self.spawn()
        self.group(member=True)                               # foyer (108, 101) hors de tout bâtiment
        self.wait_keys()
        self.assertEqual(self.keys(), '')
        self.assertEqual(self.h.errors('solo'), [])

    def test_key_follows_a_home_change_and_is_removed_without_home(self):
        self.building()
        self.building(HOME9)
        self.init()
        gid = self.group(member=True)
        self.spawn()
        self.assertEqual(self.keys(), '77')
        self.run_lua(f'LivingKnox.Groups.setHome("{gid}", 301, 301, 0)')
        self.wait_keys()
        self.assertEqual(self.keys(), '99')                   # ancienne clé retirée, nouvelle posée
        self.run_lua(f'LivingKnox.Groups.setHome("{gid}")')
        self.wait_keys()
        self.assertEqual(self.keys(), '')
        lines = self.lk()
        self.assertTrue(any('key 99 of its home building B9 given (1 key(s) of a former home removed)' in s
                            for s in lines), lines)
        self.assertTrue(any('1 key(s) of a former home removed (no home)' in s for s in lines), lines)

    def test_unmarked_key_is_never_touched(self):
        self.building()
        self.building(HOME9)
        self.init()
        gid = self.group(member=True)
        self.spawn()
        self.run_lua('local k = instanceItem("Base.Key1") k:setKeyId(5); '
                     '(LivingKnox.Bodies.find("lk-1")):getInventory():AddItem(k)')
        self.run_lua(f'LivingKnox.Groups.setHome("{gid}", 301, 301, 0)')
        self.wait_keys()
        self.assertEqual(self.keys(), '5,99')

    def test_locked_door_of_another_building_is_refused_with_the_home_key(self):
        self.wall()
        self.building(dict(HOUSE, keyId=88))                  # bâtiment de la porte : aucun foyer
        self.building(HOME9)
        self.door(locked=True, lockedByKey=True)
        zid = self.start()
        self.group(member=True, home=(301, 301, 0))           # clé 99
        self.move()
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.ev('LivingKnox.Obstacles.lastRefused.why'), 'locked door (no key)')
        self.assertEqual(self.keys(), '99')
        self.assertEqual(self.state('solo'), 'false true true')
        self.assertEqual(self.ev(f'DOORS["{DOOR_KEY}"].keyId'), 88)          # clé du bâtiment de la porte
        self.assertEqual(self.counters('solo'), (0, 0))

    def test_key_in_a_key_ring_opens_the_door(self):
        self.building()
        self.door(locked=True, lockedByKey=True)
        zid = self.start()
        self.run_lua('local r = instanceItem("Base.KeyRing") local k = instanceItem("Base.Key1") k:setKeyId(77) '
                     'r.inv:AddItem(k); (LivingKnox.Bodies.find("lk-1")):getInventory():AddItem(r)')
        self.move()
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')          # sans groupe : ouverte par la clé du porte-clés
        self.walk_d(zid, 30)
        self.assertEqual(self.state('solo'), 'false true true')

    def test_unlocked_door_opens_without_key_and_is_not_locked_behind(self):
        self.building()
        self.door()
        zid = self.start()
        self.move()
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_d(zid, 30)
        self.assertEqual(self.state('solo'), 'false false false')
        self.assertEqual(self.keys(), '')

    def test_key_is_on_the_corpse(self):
        self.building()
        self.init()
        self.group(member=True)
        self.spawn()
        # IsoZombie.onKilled : DoZombieInventory (rien pour un joueur réanimé), OnZombieDead, puis DoDeath et le
        # cadavre qui prend l'inventaire du mort (IsoDeadBody.java:327-332).
        self.run_lua('local z = LivingKnox.Bodies.find("lk-1") z:DoZombieInventory() z:Kill(nil) '
                     'CORPSE = getCell():getGridSquare(math.floor(z:getX()), math.floor(z:getY()), 0):createCorpse(z)')
        self.assertEqual(self.ev('KEYS_ON(CORPSE)'), '77')
        self.assertEqual(self.ev('CORPSE:getContainer():haveThisKeyId(77) ~= nil'), True)
        self.assertEqual(self.ev('LivingKnox.Store.data().npcs["lk-1"].state'), 'dead')

    def test_ordinary_zombie_inventory_is_emptied_by_DoZombieInventory(self):
        # Doublure fidèle : une clé posée sur un zombie ordinaire AVANT DoZombieInventory serait perdue
        # (IsoZombie.java:3137) ; le module la pose sur le joueur réanimé, après reanimate.
        self.init()
        self.run_lua('local z = NEW_ZOMBIE(120.5, 120.5, 0, false) local k = instanceItem("Base.Key1") k:setKeyId(7) '
                     'z:getInventory():AddItem(k) z:DoZombieInventory() ZB = z')
        self.assertEqual(self.ev('KEYS_ON(ZB)'), '')


class MultiplayerKeyTests(ObstacleBase):
    """LK04-T12 en MP : clé sur la copie du serveur seulement ; refus sans clé ; porte non reverrouillée si la clé est
    perdue en chemin."""

    def setUp(self):
        super().setUp()
        SENT.clear()

    def ready(self, owner='A'):
        zid = self.npc()
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "{owner}")')
        self.h.set_owner(zid, owner)
        for _ in range(2):
            self.slow()
            self.h.pump()
        return zid

    def server_keys(self):
        return self.ev('KEYS_ON((LivingKnox.Bodies.find("lk-1")))')

    def test_member_without_its_key_is_refused_and_the_key_is_not_given_back(self):
        self.wall()
        self.building()
        self.door(locked=True, lockedByKey=True)
        zid = self.start('A')
        self.group(member=True)
        self.o('giveKey("lk-1", (LivingKnox.Bodies.find("lk-1")))')
        self.assertEqual(self.server_keys(), '77')
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, f'KEYS_ON(HARNESS.zombies[{zid}])'), '')   # copies des clients
        self.assertEqual(self.o('removeKeys((LivingKnox.Bodies.find("lk-1")))'), 1)
        self.move()
        self.h.pump()
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(any('refused at the door 106,102,0,W: locked door (no key)' in s for s in self.lk()),
                        self.lk())
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.state(m), 'false true true')
            self.assertEqual(self.counters(m), (0, 0))
        self.h.tick(self.o('KEYS_EVERY_MS') // self.h.tick_ms + 10)
        self.assertEqual(self.server_keys(), '')            # une clé perdue ne revient pas sur ce corps

    def test_key_lost_after_the_opening_door_closed_behind_but_not_locked(self):
        self.building()
        self.door(locked=True, lockedByKey=True)
        zid = self.start('A')
        self.group(member=True)
        self.move()
        self.h.pump()
        self.walk_d(zid, 600, until=lambda: self.state('server') == 'true false false')
        self.assertEqual(self.server_keys(), '77')
        self.o('removeKeys((LivingKnox.Bodies.find("lk-1")))')
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_d(zid, 30)
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.state(m), 'false false false')
        self.assertEqual(self.counters('server'), (2, 0))
        self.assertTrue(any('npc lk-1 lost its key, left unlocked' in s for s in self.lk()), self.lk())


class HomeKeyholderTests(ObstacleBase):
    """LK04-T12 : verrouiller une porte du foyer (arrivée, securePass) suppose un membre porteur de la clé au foyer."""
    mode = 'solo'

    def wait_ms(self, ms):
        self.h.tick(ms // self.h.tick_ms + 2 * self.o('PASS_EVERY') + 1)

    def test_door_closed_but_not_locked_until_a_member_with_the_key_is_home(self):
        self.building()
        self.door(open=True)
        self.start()
        gid = self.group(member=False)                        # aucun membre : personne n'a la clé
        self.wait_ms(self.o('SHUT_DELAY_MS'))
        self.assertEqual(self.state('solo'), 'false false false')          # fermée, pas verrouillée
        self.assertEqual(self.o('stats.shutUnlocked'), 1)
        self.assertTrue(any('1 left unlocked: no member with the key at home' in s for s in self.lk()), self.lk())
        self.wait_ms(self.o('SECURE_EVERY_MS'))
        self.assertEqual(self.state('solo'), 'false false false')
        self.assertGreaterEqual(self.o('stats.secureKeyless'), 1)
        self.assertIsNotNone(self.run_lua(f'return LivingKnox.Groups.addMember("{gid}", '
                                          '{ role = "worker", npc = "lk-1" })'))
        self.run_lua('LivingKnox.Obstacles.refreshHomes(true)')
        self.wait_ms(self.o('SECURE_EVERY_MS'))
        self.assertEqual(self.state('solo'), 'false true true')            # porteur au foyer : verrouillée
        self.assertEqual(self.keys(), '77')

    def test_member_far_from_home_does_not_lock(self):
        self.building()
        self.door(open=True)
        zid = self.start()
        self.run_lua(f'HARNESS.place(HARNESS.zombies[{zid}], 140.5, 140.5, 0)')   # à plus de 20 cases du foyer
        self.group(member=True)
        self.wait_ms(self.o('SHUT_DELAY_MS'))
        self.assertEqual(self.state('solo'), 'false false false')
        self.assertEqual(self.keys(), '77')

    def keys(self):
        return self.ev('KEYS_ON((LivingKnox.Bodies.find("lk-1")))')


class KeySuiteTests(ObstacleBase):
    """Suite en jeu lk.traversal, tests de clé (LK04-T12), jouée sur le banc : corps relevé et pas de marche STEP_D
    à chaque image (le banc ne relève ni ne fait marcher un corps de lui-même)."""
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        return h

    def run_walking(self, name, ticks=6000):
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.traversal", tags = "world", test = "%s" }, '
                                          '{ ctx = { player = getPlayer() } }))' % name), True)
        for _ in range(ticks):
            self.h.tick()
            self.h.load('solo', 'local z = LivingKnox.Bodies.find("lk-1") '
                                'if z then z.onFloor = false; STEP_D(z.onlineID, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        return [(r.test, r.status, r.message) for r in lua_list(report.results)]

    def test_suite_locked_home_door_with_the_key(self):
        self.building()
        self.door()
        self.init()
        results = self.run_walking("locked home door: opened with the settler's key, locked behind")
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.state('solo'), 'false false false')        # porte rendue (fermée, non verrouillée)
        self.assertEqual(self.o('stats.opened'), 1)

    def test_suite_locked_home_door_without_the_key(self):
        self.building()
        self.door()
        self.init()
        results = self.run_walking('locked home door: refused without the key')
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.state('solo'), 'false false false')
        self.assertEqual(self.o('stats.opened'), 0)

    def test_suite_locked_home_door_opened_from_inside_without_the_key(self):
        # LK04-T17 : porte du mur est (112, 102) W, voie partant de la maison (côté ouest = dedans).
        self.building()
        self.door(x=112)
        self.init()
        results = self.run_walking('locked home door: opened from inside without the key')
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.state('solo', '112,102,0,W'), 'false false false')
        self.assertEqual(self.o('stats.opened'), 1)
        self.assertIn(self.o('stats.refused'), (None, 0))
        # Porte ouest seule (voie partant de dehors) : pas de site, SKIP.
        self.run_lua('DOORS["112,102,0,W"].removed = true')
        self.door()
        results = self.run_walking('locked home door: opened from inside without the key')
        self.assertEqual([r[1] for r in results], ['SKIP'], results)

    def interior_site(self):
        # LK04-T19 : porte intérieure (109, 102) W de la maison, sans clé propre ; voie 107 -> 111.
        self.building()
        self.wall(x=109, skip=(102,))
        self.door(x=109)
        self.init()

    def test_suite_locked_interior_home_door_relocked_with_the_home_key(self):
        self.interior_site()
        results = self.run_walking('locked interior home door: opened from inside, relocked with the home key')
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.state('solo', '109,102,0,W'), 'false false false')   # porte rendue
        self.assertEqual(self.o('stats.opened'), 1)
        self.assertEqual(self.o('stats.locked'), 2)                                # pose du test, puis reverrou
        self.assertTrue(any('door 109,102,0,W closed behind npc lk-1 and locked' in s for s in self.lk()), self.lk())

    def test_suite_locked_interior_home_door_left_unlocked_without_the_home_key(self):
        self.interior_site()
        results = self.run_walking('locked interior home door: opened from inside, left unlocked without the home '
                                   'key')
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.state('solo', '109,102,0,W'), 'false false false')
        self.assertEqual(self.o('stats.locked'), 1)                                # pose du test seulement

    def test_suite_interior_door_site_skips_exterior_and_keyed_doors(self):
        self.building()
        self.door()                                          # extérieure (clé du bâtiment)
        self.door(x=109, keyId=55)                           # intérieure à serrure propre
        self.init()
        results = self.run_walking('locked interior home door: opened from inside, relocked with the home key')
        self.assertEqual([r[1] for r in results], ['SKIP'], results)


class RefusedDoorDetourTests(ObstacleBase):
    """LK04-T14 (essai solo du 2026-10-11 22:30, 20261011-202959-solo.txt) : le chemin natif d'un PNJ vers une clôture
    basse a pris la porte de garage fermée voisine (10747,9537,0,W), refusée par l'autorité (« garage door not
    handled ») : consigne échouée. Clôture basse le long du bord ouest de x = 106 (y 90..125) ; porte de garage
    fermée dans cette ligne. La doublure de marche va en ligne droite (chemin natif) : seuls les points de passage
    l'écartent de la porte. Depuis LK04-T17, une porte de garage s'ouvre (tous ses panneaux) : une porte double, toujours
    refusée, tient ici le rôle de la porte refusée."""
    mode = 'solo'

    def line(self, fence=True, skip=()):
        table = 'FENCES' if fence else 'WALLS'
        keys = [f'106,{y},0,W' for y in range(90, 126) if y not in skip]
        self.run_lua('; '.join(f'{table}["{k}"] = true' for k in keys))

    def trip(self, ticks=1500):
        zid = self.start()
        self.move()
        self.walk_w(zid, ticks, until=self.done())
        return zid

    def steps(self):
        w = self.entry('w')
        return [] if w is None else [(w[i].x, w[i].y) for i in range(1, len(w) + 1)]

    def plan(self, x0=102.5, y0=102.5):
        return self.run_lua(
            'local w, info = LivingKnox.Obstacles.planDoorRoute("lk-1", %s, %s, 111, 102, 0) '
            'local s = {} for i = 1, #w do s[i] = w[i].x .. "," .. w[i].y end '
            'local r = info.refused and info.refused[1] '
            'return table.concat(s, " "), info.reason, r and r.key, r and r.why' % (x0, y0))

    def garage_on_the_line(self):
        self.line(skip=(102,))
        self.door(double=True)                            # 106,102,0,W, sur la ligne droite

    def test_before_the_garage_door_on_the_native_path_fails_the_move(self):
        # Constat reproduit (détour coupé) : le corps va droit à la porte de garage, refusée : échec.
        self.garage_on_the_line()
        self.run_lua('LivingKnox.Obstacles.AVOID_REFUSED = false')
        self.trip()
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(any('refused at the door 106,102,0,W: double door not handled' in s for s in self.lk()),
                        self.lk())
        self.assertEqual(self.climbs('solo'), [])

    def test_after_the_body_goes_over_the_fence_around_the_garage_door(self):
        self.garage_on_the_line()
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        steps = self.steps()
        self.assertTrue(steps, self.lk())
        climbs = self.climbs('solo')
        self.assertEqual(len(climbs), 1, climbs)
        self.assertTrue(climbs[0].startswith('climbfence 106,') and climbs[0] != 'climbfence ' + DOOR_KEY, climbs)
        self.assertEqual(self.counters('solo'), (0, 0))                 # porte jamais touchée
        self.assertEqual(self.state('solo'), 'false false false')
        self.assertEqual(self.o('stats.refused'), 0)
        lines = self.lk()
        self.assertTrue(any('around the refused door(s) 106,102,0,W (double door not handled)' in s for s in lines),
                        lines)
        self.assertEqual(self.h.errors('solo'), [])

    def test_detour_also_with_the_door_first_rule_off(self):
        self.garage_on_the_line()
        self.run_lua('LivingKnox.Obstacles.DOORS_FIRST = false')
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertTrue(self.steps())
        self.assertEqual(self.counters('solo'), (0, 0))
        self.assertEqual(self.o('stats.refused'), 0)

    def test_garage_door_next_to_the_fence_at_almost_the_same_length(self):
        # Cas de l'essai : le modèle « zombie » prend la clôture (léger bonus d'escalade), mais le chemin natif peut
        # prendre la porte de garage voisine pour moins de ROUTE_REFUSED_SLACK case de plus : guidage quand même.
        self.line(fence=False, skip=(101, 102))
        self.fence()                                      # 106,102,0,W sur la ligne droite
        self.door(y=101, double=True)                     # porte de garage juste à côté
        self.init()
        pts, reason, key, why = self.plan(102.0, 102.0)
        self.assertTrue(pts, reason)
        self.assertEqual((key, why), ('106,101,0,W', 'double door not handled'))
        self.assertIn('around the refused door(s) 106,101,0,W', reason)
        legs = [(102.0, 102.0)] + [(int(p.split(',')[0]) + 0.5, int(p.split(',')[1]) + 0.5) for p in pts.split()] \
            + [(111.5, 102.5)]
        for a, b in zip(legs, legs[1:]):      # aucun tronçon ne longe la porte de garage en ligne dégagée par elle
            self.assertIs(self.ev('LivingKnox.Obstacles.lineClear("lk-1", %s, %s, %s, %s, 0)' % (a + b)) or
                          abs(a[0] - b[0]) <= 1.01, True, f'{a} -> {b} of {pts}')
        # Porte loin de la ligne (détour bien plus long que ROUTE_REFUSED_SLACK) : aucun guidage.
        self.run_lua('DOORS["106,101,0,W"].removed = true; WALLS["106,101,0,W"] = true; WALLS["106,98,0,W"] = nil')
        self.door(y=98, double=True)
        pts, reason, key, _ = self.plan(102.0, 102.0)
        self.assertEqual(pts, '', reason)
        self.assertIsNone(key)
        # Porte ordinaire fermée (que le PNJ ouvre) : rien de refusé, aucun guidage de ce fait.
        self.run_lua('DOORS["106,98,0,W"].double = false')
        pts, reason, key, _ = self.plan(102.0, 102.0)
        self.assertIsNone(key, reason)

    def test_no_way_around_keeps_the_failure_with_a_clear_reason(self):
        self.line(fence=False, skip=(102,))
        self.door(double=True)
        self.init()
        pts, reason, key, _ = self.plan()
        self.assertEqual(pts, '')
        self.assertEqual(key, '106,102,0,W')
        self.assertIn('no way around the refused door(s) 106,102,0,W (double door not handled): npc route: '
                      'no route in the loaded squares', reason)
        self.assertTrue(any('WARN' in s and 'no way around the refused door(s)' in s for s in self.lk()), self.lk())
        self.trip()
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(any('double door not handled' in s for s in self.lk()), self.lk())

    def test_other_refused_doors_are_avoided_too(self):
        for fields in ({'double': True}, {'locked': True}, {'barricaded': True}):
            with self.subTest(fields=fields):
                self.tearDown()
                self.setUp()
                self.line(skip=(102,))
                self.door(**fields)
                self.trip()
                self.assertEqual(self.entry('s'), 'arrived', self.lk())
                self.assertEqual(self.o('stats.refused'), 0)
                self.assertEqual(len(self.climbs('solo')), 1)

    def test_suite_fence_sites_skip_doors_and_the_detour_site_needs_a_refused_door(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        self.init()
        self.fence()                                      # 106,102,0,W, voie libre
        self.door(y=101, double=True)                     # porte de garage à côté de la voie
        p = ('{ getX = function() return 100 end, getY = function() return 102 end, '
             'getZ = function() return 0 end }')
        site = ('local s = RST.LKTraversal.findSite(%s, %s) return s and s.e.key' % (p, '%s'))
        T = 'RST.LKTraversal.'
        self.assertEqual(self.run_lua(site % (T + 'pickFence')), '106,102,0,W')
        self.assertIsNone(self.run_lua(site % (T + 'rawPick(' + T + 'pickFence)')))
        self.assertEqual(self.run_lua(site % (T + 'pickFenceByRefusedDoor')), '106,102,0,W')
        # Porte ordinaire (ouvrable) : site écarté des franchissements ; site de détour depuis la campagne solo du
        # 2026-10-15 (décor : le test ferme la porte simple et y cloue une planche, refuseDoorNextTo).
        self.run_lua('DOORS["106,101,0,W"].double = false')
        self.assertIsNone(self.run_lua(site % (T + 'rawPick(' + T + 'pickFence)')))
        self.assertEqual(self.run_lua(site % (T + 'pickFenceByRefusedDoor')), '106,102,0,W')
        # Sans porte : site de franchissement retenu.
        self.run_lua('DOORS["106,101,0,W"].removed = true')
        self.assertEqual(self.run_lua(site % (T + 'rawPick(' + T + 'pickFence)')), '106,102,0,W')
        # Campagne solo du 2026-10-15 : plante à une case de la voie (zone HAZARD_AVOID) : le déplacement contourne le
        # potager (Directives.planDetour) et passe à côté de la clôture : site écarté.
        self.run_lua('getCell():getGridSquare(105, 103, 0).plant = true')
        self.assertIsNone(self.run_lua(site % (T + 'rawPick(' + T + 'pickFence)')))
        self.run_lua('getCell():getGridSquare(105, 103, 0).plant = nil')
        self.assertEqual(self.run_lua(site % (T + 'rawPick(' + T + 'pickFence)')), '106,102,0,W')

    def test_suite_detour_test_passes_on_the_bench(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        self.line(skip=(102, 101))
        self.fence()
        self.door(y=101, double=True)
        self.init()
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.traversal", tags = "world", test = '
                                          '"refused door next to a low fence: around it, never through it" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for _ in range(8000):
            self.h.tick()
            self.h.load('solo', 'local z = LivingKnox.Bodies.find("lk-1") '
                                'if z then z.onFloor = false; STEP_W(z.onlineID, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.state('solo', '106,101,0,W'), 'false false false')


FAKE_DECISIONS = r'''
-- Cadre de décision réduit (LK_Decisions.lua) : au passage d'un membre dont la consigne "move" est close, il émet sa
-- propre consigne (garde : regard), comme la consigne face #26 du pillard de l'essai du 2026-10-11 23:08. Le passage
-- est un abonné OnTick inscrit AVANT la suite RST : il tourne dans la même image que l'arrivée, avant la lecture du
-- test (ordre de l'essai). memberPass appelle LivingKnox.Decisions.evaluate par la table, comme l'original.
LivingKnox.Decisions = LivingKnox.Decisions or {}
FAKE_FACES = 0
LivingKnox.Decisions.evaluate = function(gid, g, mid, m, body)
    local D = LivingKnox.Directives
    local e = D.get(m.npc)
    if e ~= nil and e.done and e.op == D.OP_MOVE then
        if D.face(m.npc, "S") ~= nil then FAKE_FACES = FAKE_FACES + 1 end
    end
end
Events.OnTick.Add(function()
    local data = LivingKnox.Groups.state.data
    if data == nil then return end
    for gid, g in pairs(data.groups) do
        for mid, m in pairs(g.members) do
            local body = m.npc and LivingKnox.Bodies.find(m.npc)
            if body ~= nil then LivingKnox.Decisions.evaluate(gid, g, mid, m, body) end
        end
    end
end)
'''


class Traversal2308Tests(ObstacleBase):
    """Défauts de lk.traversal constatés en jeu le 2026-10-11 à 23:08 (20261011-210835-solo.txt, console.txt, partie
    rstest-1011, jeu démarré avec le commit 62810f5), tuiles vanilla relues (Muldraugh, KY, lotheader_parser.py) :
    1. « porte refusée à côté d'une clôture » : le bord 10747,9538,0,W porte un mur (walls_interior_house_02_48,
       WallW) ET un comptoir enjambable (location_restaurant_pileocrepe_01_56, HoppableW) ; isHoppableTo (objets) est
       vrai, mais le drapeau de case HoppableW est retiré par RecalcProperties : pour le chemin natif et l'enjambée,
       c'est un mur ; le module y posait un tronçon d'une case et le corps allait à la porte de garage ;
    2. escalier : case du bas 10746,9531 dehors, derrière le mur du hall ; fenêtre fermée 10747,9532,0,W ouverte par
       l'autorité, table furniture_tables_high_01_15 (solidtrans) de l'autre côté : issue « obstacle », corps au sol ;
    3. fenêtre fermée (pillards) : consigne face #26 du cadre de décision émise dans l'image de l'arrivée ;
    4. porte d'abord : haie f_bushes_1 le long de x = 10753 (coût natif 5 par case), tronçon 10753,9549 -> 10753,9553
       jugé dégagé ; le chemin natif est passé par la fenêtre 10751,9550,0,N."""
    mode = 'solo'

    def suite(self):
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')

    def walls(self, keys):
        self.run_lua('; '.join(f'WALLS["{k}"] = true' for k in keys))

    def plan(self, x0, y0, tx, ty):
        res = self.run_lua(
            'local w, info = LivingKnox.Obstacles.planDoorRoute("lk-1", %s, %s, %d, %d, 0) '
            'local s = {} for i = 1, #w do s[i] = w[i].x .. "," .. w[i].y end '
            'return table.concat(s, " "), info.reason, info.doors or 0' % (x0, y0, tx, ty))
        pts = [tuple(int(v) for v in p.split(',')) for p in res[0].split()] if res[0] else []
        return pts, res[1], res[2]

    def sq(self, x, y, z=0):
        return f'getCell():getGridSquare({x}, {y}, {z})'

    # 1. Mur et comptoir enjambable sur le même bord : un mur pour le moteur, pas une clôture.
    def test_hoppable_object_on_a_wall_is_a_wall(self):
        self.init()
        self.walls(['106,102,0,W'])
        self.fence()                                       # 106,102,0,W : objet enjambable sur le mur
        self.fence(y=104)                                  # vraie clôture basse
        a, b = self.sq(105, 102), self.sq(106, 102)
        self.assertIs(self.ev(f'{a}:isHoppableTo({b})'), True)
        self.assertIs(self.ev(f'LivingKnox.Obstacles.isFenceTo({a}, {b})'), False)
        self.assertIs(self.ev(f'LivingKnox.Obstacles.isFenceTo({b}, {a})'), False)
        for p, q in ((self.sq(105, 104), self.sq(106, 104)), (self.sq(106, 104), self.sq(105, 104))):
            self.assertIs(self.ev(f'LivingKnox.Obstacles.isFenceTo({p}, {q})'), True)
        # Itinéraires : le bord est un mur (aucun pas « climb » par lui).
        r = self.run_lua('local r = LivingKnox.Obstacles.findRoute("lk-1", 105.5, 102.5, 106, 102, 0, "zombie") '
                         'local s = {} for _, p in ipairs(r) do s[#s + 1] = p.x .. "," .. p.y .. "," '
                         '.. tostring(p.cross) end return table.concat(s, " ")')
        self.assertNotIn('106,102,climb', r)
        self.assertGreater(len(r.split()), 2, r)

    def test_route_never_plans_a_step_over_the_hoppable_wall(self):
        # Cas de l'essai : ligne de murs x = 106, porte de garage fermée 106,101,0,W, comptoir enjambable sur le mur
        # 106,102,0,W, sur la ligne droite. Avant : « around the refused door(s) 106,101,0,W ... through 0 door(s) and
        # 1 window or fence crossing(s) », pas d'une case par le mur. Après : aucun contournement dans la zone.
        self.walls([f'106,{y},0,W' for y in range(90, 126) if y != 101])
        self.fence()
        self.door(y=101, double=True)
        self.init()
        pts, reason, _ = self.plan(102.0, 102.0, 111, 102)
        self.assertNotIn((106, 102), pts, reason)
        self.assertEqual(pts, [], reason)
        self.assertIn('no way around the refused door(s) 106,101,0,W (double door not handled)', reason)

    def test_suite_fence_sites_skip_a_hoppable_object_on_a_wall(self):
        self.suite()
        self.init()
        self.walls(['106,102,0,W'])
        self.fence()
        self.door(y=101, double=True)
        p = ('{ getX = function() return 100 end, getY = function() return 102 end, '
             'getZ = function() return 0 end }')
        site = 'local s = RST.LKTraversal.findSite(%s, RST.LKTraversal.%s) return s and s.e.key'
        self.assertIsNone(self.run_lua(site % (p, 'pickFence')))
        self.assertIsNone(self.run_lua(site % (p, 'pickFenceByRefusedDoor')))
        self.run_lua('WALLS["106,102,0,W"] = nil')            # vraie clôture : site retenu
        self.assertEqual(self.run_lua(site % (p, 'pickFenceByRefusedDoor')), DOOR_KEY)

    # 2. Fenêtre au-dessus d'un meuble bas : chute du corps (issue « obstacle » des nœuds zombie).
    def furniture(self, x=106, y=102):
        self.run_lua(f'local s = {self.sq(x, y)} s.blocked = true s.solidTrans = true')

    def test_closed_window_over_furniture_is_refused_at_contact(self):
        self.window()                                      # fermée, 106,102,0,W
        self.furniture()                                   # table de l'autre côté (case 106,102)
        zid = self.start()
        self.run_lua('LivingKnox.Obstacles.AVOID_REFUSED = false')   # le refus lui-même
        self.move()
        self.walk_w(zid, 1500, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.o('lastRefused.why'), 'window over furniture')
        self.assertEqual(self.o('lastRefused.key'), DOOR_KEY)
        self.assertEqual(self.wcount('solo'), (0, 0))      # jamais ouverte, jamais brisée
        self.assertEqual(self.climbs('solo'), [])
        # Décision : sur le vide toujours en tête ; un meuble de SON côté ne compte pas (la case d'arrivée seule).
        w = f'WINDOWS["{DOOR_KEY}"]'
        self.assertEqual(self.run_lua(f'return LivingKnox.Obstacles.decideWindow("lk-1", {w}, "window", '
                                      f'{self.sq(105, 102)}, {self.sq(106, 102)}, {self.sq(105, 102)})'), 'open')

    def test_window_over_furniture_is_avoided_by_the_detour(self):
        # Mur x = 106 percé d'une fenêtre OUVERTE (106,102,0,W, table derrière) et d'une porte ouverte (106,98,0,W) ;
        # règle porte d'abord coupée (comme une montée d'escalier, hors de son champ) : avant, le corps passait par
        # la fenêtre ; après, la fenêtre est un franchissement refusé dans ce sens et le détour passe par la porte.
        self.walls([f'106,{y},0,W' for y in range(90, 126) if y not in (98, 102)])
        self.window(open=True)
        self.furniture()
        self.door(y=98, open=True)
        zid = self.start()
        self.run_lua('LivingKnox.Obstacles.DOORS_FIRST = false')
        self.move()
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived', self.lk())
        self.assertEqual(self.climbs('solo'), [])
        self.assertTrue(any('around the refused door(s) or window(s) 106,102,0,W (window over furniture)' in s
                            for s in self.lk()), self.lk())
        self.assertEqual(self.o('stats.refused'), 0)
        # Dans l'autre sens (meuble au départ), la fenêtre reste un passage ordinaire du modèle « zombie ».
        r = self.run_lua('local r = LivingKnox.Obstacles.findRoute("lk-1", 106.5, 103.5, 104, 102, 0, "zombie") '
                         'local n = 0 for _, p in ipairs(r) do if p.cross == "refused" then n = n + 1 end end '
                         'return n')
        self.assertEqual(r, 0)

    def test_suite_stairs_bottom_is_joined_to_the_stairs(self):
        # Escalier en 110,102 (montée vers le niveau 1) ; mur x = 109 (bord ouest) : la case 107,102, la plus proche à
        # 3 cases, est derrière lui (case du bas de l'essai, dehors). Le bas retenu doit être relié à l'escalier.
        self.suite()
        self.init()
        self.run_lua('STAIRS["110,102"] = 1')
        self.walls([f'109,{y},0,W' for y in range(95, 111)])
        res = self.run_lua(
            'local p = { getX = function() return 110 end, getY = function() return 102 end, '
            'getZ = function() return 0 end } '
            'local s, b, t = RST.LKTraversal.stairsEnds(p) '
            'return s:getX() .. "," .. s:getY(), b and (b:getX() .. "," .. b:getY()), '
            't and (t:getX() .. "," .. t:getY() .. "," .. t:getZ())')
        self.assertEqual(res[0], '110,102')
        bx, by = (int(v) for v in res[1].split(','))
        self.assertGreaterEqual(bx, 109, res)               # du côté de l'escalier
        self.assertEqual(abs(bx - 110) + abs(by - 102), 3, res)
        self.assertEqual(res[2], '109,102,1')
        # Escalier enfermé (murs tout autour) : aucun bas, SKIP motivé par le test.
        self.walls(['110,102,0,W', '111,102,0,W', '110,102,0,N', '110,103,0,N'])
        b = self.run_lua('local p = { getX = function() return 110 end, getY = function() return 102 end, '
                         'getZ = function() return 0 end } local _, b = RST.LKTraversal.stairsEnds(p) '
                         'return b == nil')
        self.assertIs(b, True)

    # 3. Cadre de décision du groupe : le PNJ de test en est écarté, la consigne lue est celle du test.
    def test_suite_raider_closed_window_reads_its_own_move(self):
        self.h.load('solo', FAKE_DECISIONS)
        self.suite()
        self.window()
        self.init()
        name = 'closed window: opened by a raider, closed behind, never broken'
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.traversal", tags = "world", test = "%s" }, '
                                          '{ ctx = { player = getPlayer() } }))' % name), True)
        for _ in range(8000):
            self.h.tick()
            self.h.load('solo', 'local z = LivingKnox.Bodies.find("lk-1") '
                                'if z then z.onFloor = false; STEP_W(z.onlineID, 0.05) end')
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.h.eval('solo', 'FAKE_FACES'), 0)
        self.assertIs(self.h.eval('solo', 'LivingKnox.Decisions.evaluate ~= nil'), True)

    # 4. Haie : coût natif des buissons ; aucun tronçon ne traverse une case de buisson avant son bout.
    def hedge_house(self):
        """Maison x 100..103, y 105..112 ; fenêtre ouverte au mur nord (bord 102,105,0,N) ; porte ouverte dans le mur
        est (bord 104,111,0,W) ; haie (buissons) sur les cases 104,105 à 104,109, dehors le long du mur est (comme
        x = 10753 en jeu) ; colonne x = 105 libre. Départ 102,102 dehors au nord, cible 102,107 dedans."""
        walls = [f'{x},105,0,N' for x in range(100, 104) if x != 102]
        walls += [f'{x},113,0,N' for x in range(100, 104)]
        walls += [f'100,{y},0,W' for y in range(105, 113)]
        walls += [f'104,{y},0,W' for y in range(105, 113) if y != 111]
        self.walls(walls)
        self.window(x=102, y=105, kind='N', open=True)
        self.door(x=104, y=111, kind='W', open=True)
        self.run_lua('; '.join(f'{self.sq(104, y)}.bush = true' for y in range(105, 110)))
        self.init()

    @staticmethod
    def squares_on(a, b):
        """Cases traversées par le segment a -> b (centres), échantillonné tous les 0,1 case, dans l'ordre."""
        n = max(1, int((((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5) * 10 + 0.999))
        out = []
        for i in range(n + 1):
            s = (int((a[0] + (b[0] - a[0]) * i / n) // 1), int((a[1] + (b[1] - a[1]) * i / n) // 1))
            if not out or out[-1] != s:
                out.append(s)
        return out

    def test_hedge_square_costs_like_the_native_path(self):
        self.hedge_house()
        self.assertEqual(self.ev(f'LivingKnox.Obstacles.squareKind({self.sq(104, 106)})'), 2)
        self.assertEqual(self.ev(f'LivingKnox.Obstacles.squareKind({self.sq(105, 106)})'), 1)
        clear = 'LivingKnox.Obstacles.lineClear("lk-1", %s, %s, %s, %s, 0)'
        self.assertIs(self.ev(clear % (104.5, 104.5, 104.5, 108.5)), False)   # buissons avant le bout
        self.assertIs(self.ev(clear % (104.5, 104.5, 104.5, 105.5)), True)    # buisson au bout seulement
        self.assertIs(self.ev(clear % (105.5, 104.5, 105.5, 109.5)), True)

    def test_door_route_never_walks_a_leg_through_the_hedge(self):
        self.hedge_house()
        pts, reason, doors = self.plan(102.5, 102.5, 102, 107)
        self.assertEqual(doors, 1, reason)
        self.assertIn((104, 111), pts, reason)              # case après la porte (dehors) ou avant
        legs = [(102.5, 102.5)] + [(x + 0.5, y + 0.5) for x, y in pts] + [(102.5, 107.5)]
        bush = {(104, y) for y in range(105, 110)}
        for a, b in zip(legs, legs[1:]):
            inner = self.squares_on(a, b)[1:-1]
            self.assertFalse(bush & set(inner), f'leg {a} -> {b} of {pts} goes through the hedge ({reason})')
        self.assertEqual(self.h.errors('solo'), [])


EXIT_HOUSE = {'id': 'B7', 'x1': 106, 'y1': 90, 'x2': 120, 'y2': 126}   # murs sur les quatre côtés (enclose)


class ExitByDoorTests(ObstacleBase):
    """LK04-T15 (décision de l'utilisateur du 2026-10-11) : dans une maison, pour sortir, priorité aux portes. Maison
    EXIT_HOUSE fermée de murs, fenêtre ouverte (106, 102) W sur la ligne droite départ (108, 102) dedans -> destination
    (102, 102) dehors ; porte en (106, 120) W : détour d'environ 36 cases (> ROUTE_PENALTY), hors de la boîte de
    recherche habituelle (ROUTE_MARGIN). Les doublures de marche ignorent les murs : seul le guidage fait passer le corps
    par la porte."""
    mode = 'solo'

    def enclose(self, skip=('106,102,0,W', '106,120,0,W')):
        b = EXIT_HOUSE
        keys = [f"{b['x1']},{y},0,W" for y in range(b['y1'], b['y2'])]
        keys += [f"{b['x2']},{y},0,W" for y in range(b['y1'], b['y2'])]
        keys += [f"{x},{b['y1']},0,N" for x in range(b['x1'], b['x2'])]
        keys += [f"{x},{b['y2']},0,N" for x in range(b['x1'], b['x2'])]
        self.run_lua('; '.join(f'WALLS["{k}"] = true' for k in keys if k not in skip))

    def house(self, door=True, **door_fields):
        self.building(EXIT_HOUSE)
        self.enclose(skip=('106,102,0,W',) + (('106,120,0,W',) if door else ()))
        self.window(open=True)
        if door:
            self.door(y=120, **(door_fields or {'open': True}))

    def trip(self, start=(108, 102), target=(102, 102), ticks=3000):
        self.init()
        _, body = self.spawn(x=start[0], y=start[1])
        zid = body.onlineID
        self.d(f'moveTo("lk-1", {target[0]}, {target[1]}, 0)')
        self.walk_w(zid, ticks, until=self.done())
        return zid

    def steps(self):
        w = self.entry('w')
        return [] if w is None else [(w[i].x, w[i].y) for i in range(1, len(w) + 1)]

    def test_far_door_is_used_to_leave_the_house(self):
        self.house()
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        steps = self.steps()
        self.assertIn((106, 120), steps)                      # case avant la porte (dedans), puis après
        self.assertIn((105, 120), steps)
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.wstate('solo'), 'true false')
        self.assertTrue(any('out of building B7 through 1 door(s) whatever the detour' in s
                            for s in self.h.logs('solo')), self.h.logs('solo'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_door_step_next_to_a_window_is_tight(self):
        # Campagne solo du 2026-10-15 (porte 11360,6977 W, fenêtre fermée 11360,6978 W juste à côté) : le point de la
        # porte, atteint à ARRIVE (1 case) près, laissait le corps devant la fenêtre ; le chemin natif vers le point
        # suivant la prenait. Les points de porte voisins d'une fenêtre sont "serrés" (STEP_TIGHT) et le restent sur le
        # réseau (wire).
        self.house()
        self.window(y=121)                                    # fenêtre fermée juste au sud de la porte
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        w = self.entry('w')
        tight = {(w[i].x, w[i].y): w[i].t for i in range(1, len(w) + 1)}
        self.assertIs(tight.get((106, 120)), True, tight)
        self.assertIsNone(tight.get((108, 106)), tight)       # point ordinaire, loin de la fenêtre
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_tight_step_distance_is_scaled(self):
        self.init()
        D = 'LivingKnox.Directives.'
        e = '{ z = 0, x = 20, y = 20, w = { { x = 10, y = 10, t = true }, { x = 12, y = 10 } } }'
        self.assertAlmostEqual(self.ev(f'{D}distToStep({e}, 1, 10.5, 10.9, 0)'), 0.4 * 1.0 / 0.5)
        self.assertAlmostEqual(self.ev(f'{D}distToStep({e}, 2, 12.5, 10.9, 0)'), 0.4)
        self.assertAlmostEqual(self.ev(f'{D}distToStep({e}, 3, 20.5, 20.9, 0)'), 0.4)

    def test_closed_door_is_opened_to_leave_the_house(self):
        self.house(open=False)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), [])
        self.assertGreaterEqual(self.o('stats.opened'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_door_locked_without_key_is_opened_from_inside_to_leave(self):
        # LK04-T17 : un joueur dans la maison ouvre sans clé une porte verrouillée (canBeOpenFromInside) ; le PNJ aussi.
        self.house(locked=True)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), [])
        self.assertIn((105, 120), self.steps())
        self.assertEqual(self.o('stats.unlocked'), 1)
        self.assertEqual(self.state('solo', '106,120,0,W'), 'false false false')   # refermée, pas reverrouillée
        self.assertEqual(self.h.errors('solo'), [])

    def test_window_without_any_door(self):
        self.house(door=False)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.steps(), [])
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])
        self.assertTrue(any('no usable door out of building B7 in the loaded squares' in s
                            for s in self.h.logs('solo')), self.h.logs('solo'))

    def test_window_when_the_only_door_is_locked_without_key(self):
        # Porte blindée (forceLocked) : seule porte qu'un joueur dedans n'ouvre pas sans clé (LK04-T17,
        # IsoDoor.java:1266-1268).
        self.house(locked=True)
        self.run_lua('DOORS["106,120,0,W"].props = { forceLocked = true }')
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])
        self.assertEqual(self.counters('solo'), (0, 0))
        self.assertTrue(any('no usable door out of building B7' in s for s in self.h.logs('solo')))

    def test_fleeing_keeps_the_shortest_way(self):
        self.house()
        self.run_lua('local D = LivingKnox.Decisions or {}; LivingKnox.Decisions = D; D.state = D.state or {}; '
                     'D.state.members = D.state.members or {}; D.state.members["lk-1"] = { b = "flee" }')
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.steps(), [])
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])

    def test_far_door_is_used_to_enter_the_house(self):
        self.house()
        self.trip(start=(102, 102), target=(108, 102))
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertIn((105, 120), self.steps())
        self.assertEqual(self.climbs('solo'), [])
        self.assertTrue(any('into building B7 through 1 door(s)' in s for s in self.h.logs('solo')))

    def test_rule_switch_and_same_building_trip(self):
        self.house()
        self.init()
        self.spawn(x=108, y=102)
        plan = ('local w, info = LivingKnox.Obstacles.planDoorRoute("lk-1", 108.5, 102.5, %d, %d, 0) '
                'return #w, tostring(info.exitUsed), info.reason')
        n, used, reason = self.run_lua(plan % (102, 102))
        self.assertGreater(n, 0)
        self.assertEqual(used, 'true')
        self.run_lua('LivingKnox.Obstacles.EXIT_BY_DOOR = false')
        n, used, reason = self.run_lua(plan % (102, 102))
        self.assertEqual(n, 0)                            # règle habituelle : porte au-delà de ROUTE_PENALTY
        self.assertIn('within 20 squares of detour', reason)
        self.run_lua('LivingKnox.Obstacles.EXIT_BY_DOOR = true')
        self.assertIsNone(self.o('exitOf(108.5, 102.5, 115, 110, 0)'))   # même bâtiment
        self.assertIsNone(self.o('exitOf(100.5, 102.5, 102, 110, 0)'))   # dehors tous les deux

    def test_suite_exit_site(self):
        # Site de lk.traversal (LK04-T15) : fenêtre de maison dont la voie (ici entrante) n'est guidée par la porte que par la règle.
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        probe = ('local s = RST.LKTraversal.findExitSite({ getX = function() return 110 end, getY = function() '
                 'return 102 end, getZ = function() return 0 end }) '
                 'return s and s.e.key, s and s.doorEdges[1].key, s and s.start:getX() .. "," .. s.start:getY()')
        self.house(open=False)
        self.init()
        self.assertEqual(self.run_lua(probe), ('106,102,0,W', '106,120,0,W', '103,102'))   # voie entrante
        self.assertEqual(self.wstate('solo'), 'true false')                   # fenêtre rendue (ouverte)
        # Porte proche (dans la limite habituelle) : la règle ne change rien, aucun site.
        self.run_lua('WALLS["106,105,0,W"] = nil')
        self.door(y=105)
        self.assertIsNone(self.run_lua(probe)[0])


OTHER_HOUSE = {'id': 'B9', 'x1': 90, 'y1': 96, 'x2': 100, 'y2': 110}   # à l'ouest de EXIT_HOUSE


class ExitLooseTests(ObstacleBase):
    """LK04-T16 (essai solo du 2026-10-12, console.txt, PNJ lk-36) : dans la cuisine de son foyer, un PNJ part en
    expédition vers une chambre d'un autre bâtiment, derrière une porte intérieure verrouillée sans clé (10981,9672,0,N,
    « locked door (no key) ») : l'itinéraire "exit" n'en trouvait aucun (« exit route: no route in the loaded squares »),
    l'itinéraire "npc" non plus, et le chemin natif gardé sortait par la fenêtre de la cuisine (10999,9696,0,N), la
    porte du foyer, ouverte, à quelques cases. Ici : foyer EXIT_HOUSE (B7), fenêtre ouverte (106, 102) W, porte ouverte
    (106, 108) W ; maison OTHER_HOUSE (B9) fermée de murs, porte d'entrée (100, 104) W, mur intérieur le long de x = 96
    percé d'une porte verrouillée (96, 102) W ; destination (93, 102) derrière elle."""
    mode = 'solo'
    enclose = ExitByDoorTests.enclose
    trip = ExitByDoorTests.trip
    steps = ExitByDoorTests.steps

    def other(self, entry=True, window=False):
        b = OTHER_HOUSE
        keys = [f"{b['x1']},{y},0,W" for y in range(b['y1'], b['y2'])]
        keys += [f"{b['x2']},{y},0,W" for y in range(b['y1'], b['y2'])]
        keys += [f"{x},{b['y1']},0,N" for x in range(b['x1'], b['x2'])]
        keys += [f"{x},{b['y2']},0,N" for x in range(b['x1'], b['x2'])]
        skip = {'100,104,0,W'}
        self.run_lua('; '.join(f'WALLS["{k}"] = true' for k in keys if k not in skip))
        self.building(OTHER_HOUSE)
        if entry:
            self.door(x=100, y=104, open=True)
        if window:
            self.window(x=100, y=104, open=True)

    def kitchen(self, door_y=108):
        self.building(EXIT_HOUSE)
        self.enclose(skip=('106,102,0,W', f'106,{door_y},0,W'))
        self.window(open=True)
        self.door(y=door_y, open=True)

    def bedroom(self, armoured=True):
        # LK04-T17 : une porte intérieure verrouillée s'ouvre sans clé de l'intérieur (IsoDoor.java:1266-1268) ;
        # seule une porte blindée (forceLocked) retient un PNJ qui l'aborde depuis une pièce.
        self.run_lua('; '.join(f'WALLS["96,{y},0,W"] = true' for y in range(96, 110) if y != 102))
        self.door(x=96, y=102, locked=True)
        if armoured:
            self.run_lua('DOORS["96,102,0,W"].props = { forceLocked = true }')

    def test_destination_behind_a_locked_door_out_through_the_near_door(self):
        self.kitchen()
        self.other()
        self.bedroom()
        self.trip(target=(93, 102))
        self.assertEqual(self.entry('s'), 'failed')                    # refus au contact de la porte verrouillée
        steps = self.steps()
        self.assertIn((106, 108), steps)                                # porte du foyer, dedans puis dehors
        after = steps[steps.index((106, 108)) + 1]
        self.assertLess(after[0], 106, steps)
        self.assertEqual(self.climbs('solo'), [])                       # fenêtre de la cuisine jamais prise
        self.assertEqual(self.wstate('solo'), 'true false')
        logs = self.h.logs('solo')
        self.assertTrue(any('out of building B7 and into building B9 through 2 door(s) whatever the detour' in s
                            and 'the destination being beyond the refused door(s) 96,102,0,W (locked door (no key))'
                            in s for s in logs), logs)
        self.assertTrue(any('refused at the door 96,102,0,W: locked door (no key)' in s for s in self.lk()), self.lk())
        self.assertFalse(any('no usable door out of building B7' in s for s in logs), logs)
        self.assertEqual(self.h.errors('solo'), [])

    def test_destination_behind_an_interior_locked_door_reached_from_inside(self):
        # LK04-T17 : porte de chambre verrouillée, ordinaire : un joueur dans la maison l'ouvre sans clé.
        self.kitchen()
        self.other()
        self.bedroom(armoured=False)
        self.trip(target=(93, 102))
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), [])
        self.assertTrue(any('door 96,102,0,W opened and unlocked from inside' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('solo'), [])

    def test_destination_reachable_only_through_a_window_out_through_the_far_door(self):
        # Porte du foyer au-delà de ROUTE_PENALTY ; maison voisine sans porte, fenêtre ouverte : la porte pour sortir
        # du foyer, la fenêtre seulement pour entrer (une escalade de moins que le chemin natif).
        self.kitchen(door_y=120)
        self.other(entry=False, window=True)
        self.trip(target=(97, 104))
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertIn((106, 120), self.steps())
        self.assertEqual(self.climbs('solo'), ['climbwindow 100,104,0,W'])
        self.assertTrue(any('out of building B7 and into building B9 through 1 door(s) whatever the detour, instead '
                            'of 2 window or fence crossing(s)' in s for s in self.h.logs('solo')), self.h.logs('solo'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_door_next_to_the_start_still_guided(self):
        # Corps sur la case de la porte (106, 104) W, fenêtre (106, 103) W juste au nord, destination dehors juste
        # derrière la fenêtre : chemin natif par la fenêtre (1,7 contre 2) ; points de porte à moins de ROUTE_GAP du
        # départ et de la destination : avant LK04-T16, consigne sans point (« door next to the start or the
        # destination ») et sortie par la fenêtre.
        self.building(EXIT_HOUSE)
        self.enclose(skip=('106,103,0,W', '106,104,0,W'))
        self.window(y=103, open=True)
        self.door(y=104, open=True)
        self.trip(start=(106, 104), target=(105, 103))
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.steps(), [(105, 104)])
        self.assertEqual(self.climbs('solo'), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_usable_door_at_all_window_as_a_last_resort(self):
        # Foyer sans porte utilisable (verrouillée sans clé) et destination derrière la porte verrouillée : fenêtre.
        self.kitchen()
        self.run_lua('local d = DOORS["106,108,0,W"]; d.open = false; d.locked = true; '
                     'd.props = { forceLocked = true }')
        self.other()
        self.bedroom()
        self.trip(target=(93, 102))
        self.assertEqual(self.climbs('solo')[:1], ['climbwindow ' + DOOR_KEY])
        self.assertTrue(any('no usable door out of building B7 and into building B9' in s
                            for s in self.h.logs('solo')), self.h.logs('solo'))

    def trapped_house(self, door_fields=None, barricade_y=110):
        """LK04-T20 (campagne MP du 2026-10-15, lk-7 sans groupe apparu dans le foyer de grp-5) : foyer EXIT_HOUSE (B7)
        d'un groupe dont lk-1 n'est pas membre, départ (108, 102), destination (100, 114) dehors ; porte (106, 108) W
        fermée (refusée : foyer d'un autre groupe) ; fenêtre barricadée (106, 110) W, la plus courte pour le chemin
        natif ; fenêtre fermée et verrouillée (106, 114) W."""
        self.building(EXIT_HOUSE)
        self.enclose(skip=(f'106,{barricade_y},0,W', '106,108,0,W', '106,114,0,W'))
        self.window(y=barricade_y, barricaded=True)
        self.window(y=114, locked=True)
        self.door(y=108, **(door_fields or {}))
        self.init()
        return self.group(member=False, home=(110, 110, 0), name='Owners')

    def test_trapped_in_the_home_of_another_group_out_through_the_locked_window(self):
        # Porte blindée et verrouillée (forceLocked : jamais ouverte sans clé, même de l'intérieur).
        gid = self.trapped_house(door_fields={'locked': True, 'props': '{ forceLocked = true }'})
        _, body = self.spawn(x=108, y=102)
        zid = body.onlineID
        self.d('moveTo("lk-1", 100, 114, 0)')
        self.assertIs(self.entry('lr'), True)
        steps = self.steps()
        self.assertIn((106, 114), steps, steps)                       # case avant la fenêtre verrouillée (dedans)
        i = steps.index((106, 114))
        self.assertEqual(steps[i + 1], (104, 114), steps)             # puis deux cases après (dehors), rien entre
        logs = self.h.logs('solo')
        self.assertEqual(self.ev(f'LivingKnox.Obstacles.doorRefusal("lk-1", DOORS["106,108,0,W"], getCell():'
                                 f'getGridSquare(105, 108, 0), getCell():getGridSquare(106, 108, 0))'),
                         f'door of the home of {gid} (not a member)')
        self.assertFalse(any('exit route: no route in the loaded squares' in s for s in logs), logs)
        self.assertTrue(any('split into' in s and '(last resort out of building B7 through 1 window or fence '
                            'crossing(s) and 0 door(s)' in s for s in logs), logs)
        self.assertFalse(any('keeps the vanilla path' in s for s in logs), logs)
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), ['climbwindow 106,114,0,W'])   # fenêtre barricadée jamais prise
        self.assertTrue(any('openwindow gesture at the window 106,114,0,W' in s for s in self.lk()), self.lk())
        self.assertTrue(any('window 106,114,0,W opened' in s for s in self.lk()), self.lk())
        self.assertEqual(self.wstate('solo', '106,110,0,W'), 'false false')   # barricadée : jamais touchée
        self.assertIs(self.ev('WINDOWS["106,114,0,W"].locked'), False)   # verrou levé par ToggleWindow
        self.assertEqual(self.state('solo', '106,108,0,W'), 'false true true')   # porte blindée jamais touchée
        self.assertEqual(self.h.errors('solo'), [])

    def test_trapped_behind_a_barricaded_window_on_the_native_path(self):
        # Cas de lk-7 : chemin natif par la fenêtre barricadée (106, 113) W, toutes les sorties refusées (itinéraire
        # "exit-loose" sans aucune porte passée) ; avant LK04-T20, journal trompeur « exit route: no route in the
        # loaded squares » et consigne sans point (« keeps the vanilla path over 1 window or fence crossing(s) »).
        # Départ (110, 114) : la marche des doublures ignore les murs, l'approche de la fenêtre (106, 114) W se fait
        # dans l'axe.
        self.trapped_house(barricade_y=113, door_fields={'locked': True, 'props': '{ forceLocked = true }'})
        _, body = self.spawn(x=110, y=114)
        zid = body.onlineID
        self.d('moveTo("lk-1", 102, 112, 0)')
        self.assertIs(self.entry('lr'), True)
        steps = self.steps()
        self.assertIn((106, 114), steps, steps)
        self.assertEqual(steps[steps.index((106, 114)) + 1], (104, 114), steps)   # deux cases au-delà, dehors
        logs = self.h.logs('solo')
        self.assertTrue(any('no usable door out of building B7' in s and 'every way out is refused: door(s) or '
                            'window(s) 106,114,0,W (locked window)' in s for s in logs), logs)
        self.assertFalse(any('exit route: no route in the loaded squares' in s for s in logs), logs)
        self.assertFalse(any('keeps the vanilla path' in s for s in logs), logs)
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), ['climbwindow 106,114,0,W'])
        self.assertEqual(self.wstate('solo', '106,113,0,W'), 'false false')
        self.assertEqual(self.h.errors('solo'), [])

    def test_trapped_decisions_need_the_last_resort_and_the_inside(self):
        # Sans dernier recours (e.lr), refus inchangés ; depuis dehors, fenêtre verrouillée et foyer toujours refusés.
        self.trapped_house()
        self.spawn(x=108, y=102)
        q = ('local O = LivingKnox.Obstacles local c = getCell() '
             'local a, b = c:getGridSquare(105, 114, 0), c:getGridSquare(106, 114, 0) '
             'local w = WINDOWS["106,114,0,W"] '
             'local r1, w1 = O.decideWindow("lk-1", w, "window", a, b, a) '
             'local r2, w2 = O.decideWindow("lk-1", w, "window", a, b, a, true, b) '
             'local r3, w3 = O.decideWindow("lk-1", w, "window", a, b, b, true, a) '
             'local da, db = c:getGridSquare(105, 108, 0), c:getGridSquare(106, 108, 0) '
             'local d = DOORS["106,108,0,W"] '
             'local r4, w4 = O.decide("lk-1", d, da, db, nil, db) '
             'local r5 = O.decide("lk-1", d, da, db, nil, db, true) '
             'local r6, w6 = O.decide("lk-1", d, da, db, nil, da, true) '
             'local bw = WINDOWS["106,110,0,W"] '
             'local r7, w7 = O.decideWindow("lk-1", bw, "window", c:getGridSquare(105, 110, 0), '
             'c:getGridSquare(106, 110, 0), c:getGridSquare(105, 110, 0), true, c:getGridSquare(106, 110, 0)) '
             'return tostring(r1) .. "|" .. tostring(w1) .. "|" .. tostring(r2) .. "|" .. tostring(r3) .. "|" '
             '.. tostring(w3) .. "|" .. tostring(r4) .. "|" .. tostring(r5) .. "|" .. tostring(r6) .. "|" '
             '.. tostring(w7)')
        r = self.run_lua(q).split('|')
        self.assertEqual(r[0:2], ['nil', 'locked window'])           # sans dernier recours
        self.assertEqual(r[2], 'open')                                # dernier recours, de l'intérieur
        self.assertEqual(r[3:5], ['nil', 'locked window'])           # dernier recours, depuis dehors
        self.assertEqual(r[5], 'nil')                                 # porte du foyer, sans dernier recours
        self.assertEqual(r[6], 'open')                                # dernier recours, depuis le foyer
        self.assertEqual(r[7], 'nil')                                 # dernier recours, depuis dehors : refusée
        self.assertEqual(r[8], 'barricaded window')                   # barricade toujours refusée

    def test_trapped_out_through_the_door_of_the_home_when_no_window_opens(self):
        # Fenêtre verrouillée inamovible : la porte du foyer, abordée de l'intérieur, est la seule issue.
        self.trapped_house()
        self.run_lua('WINDOWS["106,114,0,W"].permaLocked = true')
        _, body = self.spawn(x=108, y=102)
        zid = body.onlineID
        self.d('moveTo("lk-1", 102, 102, 0)')
        self.assertIs(self.entry('lr'), True)
        steps = self.steps()
        self.assertIn((106, 108), steps)                              # case avant la porte (dedans), puis dehors
        self.assertLess(steps[steps.index((106, 108)) + 1][0], 106, steps)
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), [])
        self.assertTrue(any('door 106,108,0,W opened' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_trapped_route_keeps_the_vanilla_path_with_a_warning(self):
        # Porte barricadée, fenêtre inamovible : aucun itinéraire de dernier recours ; avertissement, aucun e.lr.
        self.trapped_house(door_fields={'barricaded': True})
        self.run_lua('WINDOWS["106,114,0,W"].permaLocked = true')
        self.spawn(x=108, y=102)
        self.d('moveTo("lk-1", 102, 102, 0)')
        self.assertIsNone(self.entry('lr'))
        self.assertEqual(self.steps(), [])
        logs = self.h.logs('solo')
        self.assertTrue(any('WARN' in s and 'no way around the refused door(s) 106,108,0,W (barricaded door)' in s
                            and 'trapped route: no route' in s for s in logs), logs)

    def test_suite_loose_exit_site(self):
        # Site de lk.traversal (LK04-T16) : voie de la fenêtre prise à rebours (départ dans le foyer), porte d'un autre
        # bâtiment à verrouiller par le test, itinéraire de l'autorité par la porte du foyer jusqu'à elle.
        self.h.load('solo', 'shared/RST/suites/RST_LKTraversal.lua')
        self.kitchen()
        self.other()
        self.bedroom()
        self.init()
        probe = ('local s = RST.LKTraversal.findLooseExitSite({ getX = function() return 110 end, getY = function() '
                 'return 102 end, getZ = function() return 0 end }) '
                 'return s and s.e.key, s and s.lockKey, s and s.doorEdges[1].key, '
                 's and s.start:getX() .. "," .. s.start:getY(), s and s.dest:getX() .. "," .. s.dest:getY()')
        self.assertEqual(self.run_lua(probe), ('106,102,0,W', '100,104,0,W', '106,108,0,W', '108,102', '99,104'))
        self.assertEqual(self.state('solo', '100,104,0,W'), 'true false false')   # porte rendue telle quelle


class MultiplayerTrappedTests(ObstacleBase):
    """LK04-T20 en MP (serveur dédié, A simule le corps, B regarde) : itinéraire de dernier recours calculé par le
    serveur, points de passage envoyés ; e.lr reste sur le serveur (les décisions au contact y sont prises)."""
    mode = 'mp'
    enclose = ExitByDoorTests.enclose
    steps = ExitByDoorTests.steps
    trapped_house = ExitLooseTests.trapped_house

    def setUp(self):
        super().setUp()
        SENT.clear()

    def test_server_guides_the_owner_out_through_the_locked_window(self):
        self.trapped_house(barricade_y=113, door_fields={'locked': True, 'props': '{ forceLocked = true }'})
        _, body = self.spawn(x=110, y=114)
        zid = body.onlineID
        srv = self.h.zombie('server', zid)
        for c in ('A', 'B'):
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        self.h.pump()
        self.d('moveTo("lk-1", 102, 112, 0)')
        self.h.pump()
        self.assertIs(self.entry('lr'), True)
        self.assertIsNone(self.h.eval('A', 'LivingKnox.Executor.remote.d["lk-1"].lr'))   # jamais envoyé
        self.assertEqual(self.h.eval('A', '#LivingKnox.Executor.remote.d["lk-1"].w'), len(self.steps()))
        self.walk_w(zid, 3000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('A'), ['climbwindow 106,114,0,W'])
        self.assertEqual(self.wcount('A'), (0, 0))                               # bascules sur le serveur seulement
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.wstate(m, '106,114,0,W'), 'false false', m)  # ouverte puis refermée derrière
            self.assertEqual(self.wstate(m, '106,113,0,W'), 'false false', m)
        self.assertEqual(self.h.errors('server'), [])


class SourceTests(unittest.TestCase):
    def test_kahlua_safe_sources_and_english_logs(self):
        for path in (LUA / OBSTACLES, LUA / 'client/LivingKnox/LK_Executor.lua',
                     LUA / 'server/LivingKnox/LK_Directives.lua', TRAVERSAL_SUITE):
            src = path.read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in src.splitlines())
            self.assertTrue(code.isascii(), path)
            self.assertNotRegex(code, r'\bnext\s*\(|\bgoto\b|\bcoroutine\.|\bbit32\b', path)
        src = (LUA / OBSTACLES).read_text(encoding='utf-8')
        for msg in re.findall(r'log\(\)\.\w+\("([^"]*)"', src):
            self.assertTrue(msg.isascii() and re.match(r'^[a-z%]', msg), msg)


class WindowGestureBase(ObstacleBase):
    """LK04-T13 : geste du joueur devant une fenêtre fermée (ouverture) puis derrière le corps (fermeture), bascule à
    l'instant du clip, corps arrêté et tourné vers la fenêtre pendant le geste."""

    def timeline(self, zid, ticks=900, watch=('solo',)):
        """Marche jusqu'à l'arrivée puis 200 images ; relève à chaque image l'heure, l'état de la fenêtre sur
        l'autorité, le geste affiché sur chaque machine regardée, la position et l'orientation du corps."""
        auth = 'solo' if self.mode == 'solo' else 'server'
        rows = []

        def check():
            zb = self.h.zombie(self.sim(zid), zid)
            rows.append({'t': self.h.eval(auth, 'getTimestampMs()'), 'w': self.wstate(auth),
                         'x': zb.x, 'y': zb.y, 'a': zb.angle,
                         'g': {m: self.h.eval(m, f'ANIMVARS(HARNESS.zombies[{zid}])') for m in watch}})
        self.walk_w(zid, ticks, until=self.done(), check=check)
        self.walk_w(zid, 200, check=check)
        return rows

    @staticmethod
    def span(rows, m, gesture):
        """Images où la machine m affiche le geste : (première, dernière) ou None."""
        idx = [i for i, r in enumerate(rows) if r['g'][m].endswith('gesture=' + gesture)]
        return (idx[0], idx[-1]) if idx else None

    @staticmethod
    def changed(rows, state):
        """Première image où la fenêtre est dans l'état state après avoir été dans un autre."""
        for i in range(1, len(rows)):
            if rows[i]['w'] == state and rows[i - 1]['w'] != state:
                return i
        return None

    def slack(self):
        """Écart toléré sur l'instant de la bascule : un passage de l'autorité et un passage d'affichage."""
        return (self.o('PASS_EVERY') + self.ev('LivingKnox.Anim.APPLY_EVERY')) * self.h.tick_ms


class WindowGestureTests(WindowGestureBase):
    mode = 'solo'

    def test_open_gesture_then_window_opened_mid_clip_and_closed_behind_with_its_gesture(self):
        self.window()
        zid = self.start()
        self.friendly_group()
        self.move()
        rows = self.timeline(zid)
        self.assertEqual(self.entry('s'), 'arrived')
        op, cl = self.span(rows, 'solo', 'openwindow'), self.span(rows, 'solo', 'closewindow')
        self.assertIsNotNone(op, 'no open gesture shown')
        self.assertIsNotNone(cl, 'no close gesture shown')
        self.assertLess(op[1], cl[0])
        # Ouverture : pendant le geste, à OPEN_TOGGLE_MS de son début (un passage et un affichage près).
        opened = self.changed(rows, 'true false')
        self.assertTrue(op[0] < opened <= op[1], (op, opened))
        dt = rows[opened]['t'] - rows[op[0]]['t']
        self.assertLessEqual(abs(dt - self.o('OPEN_TOGGLE_MS')), self.slack(), dt)
        # Corps arrêté et tourné vers la fenêtre (à l'ouest du bord : vers l'est, 0) pendant tout le geste.
        still = rows[op[0] + 1:op[1] + 1]
        self.assertEqual({(r['x'], r['y']) for r in still}, {(rows[op[0]]['x'], rows[op[0]]['y'])})
        self.assertTrue(all(abs(r['a']) < 1 for r in still), [r['a'] for r in still][:5])
        # Escalade après le geste seulement.
        climbed = next(i for i, r in enumerate(rows) if r['x'] > 106.6)
        self.assertGreater(climbed, op[1])
        # Fermeture : geste derrière le corps, tourné vers l'ouest (180), fenêtre fermée à CLOSE_TOGGLE_MS.
        closed = self.changed(rows, 'false false')
        self.assertTrue(cl[0] < closed <= cl[1], (cl, closed))
        dt = rows[closed]['t'] - rows[cl[0]]['t']
        self.assertLessEqual(abs(dt - self.o('CLOSE_TOGGLE_MS')), self.slack(), dt)
        behind = rows[cl[0] + 1:cl[1] + 1]
        self.assertEqual(len({(r['x'], r['y']) for r in behind}), 1)
        self.assertTrue(all(abs(r['a'] - 180) < 1 for r in behind), [r['a'] for r in behind][:8])
        self.assertTrue(all(r['x'] > 106 for r in behind))
        self.assertLessEqual(abs(rows[cl[0]]['x'] - 106), self.o('ACT_REACH'))
        # Deux bascules, avec le corps ; une seule ouverture et une seule fermeture ; reprise après chaque geste.
        self.assertEqual(self.wcount('solo'), (2, 0))
        self.assertEqual(lua_list(self.h.eval('solo', 'TOGGLED_BY')), ['zombie', 'zombie'])
        self.assertEqual(self.o('stats.windowGestures'), 2)
        self.assertEqual(self.o('stats.windowsOpened'), 1)
        self.assertEqual(self.o('stats.windowsClosed'), 1)
        self.assertEqual(self.ev('LivingKnox.Executor.stats.actResumed'), 2)
        self.assertEqual(self.ev('LivingKnox.Executor.stats.failed'), 0)
        self.assertEqual(self.ev('LivingKnox.Anim.shownOf("lk-1")'), self.ev('LivingKnox.Anim.gestureOf("lk-1")'))
        logs = self.lk()
        self.assertTrue(any('openwindow gesture at the window 106,102,0,W' in s for s in logs), logs)
        self.assertTrue(any('closewindow gesture at the window 106,102,0,W' in s for s in logs), logs)
        self.assertTrue(any('window 106,102,0,W closed behind npc lk-1' in s for s in logs), logs)
        self.assertEqual(self.h.errors('solo'), [])

    def test_phase_variable_cleared_at_every_gesture_change(self):
        zid = self.start()
        every = self.ev('LivingKnox.Anim.APPLY_EVERY')
        zb = f'HARNESS.zombies[{zid}]'
        self.run_lua('LivingKnox.Anim.startAct("lk-1", "openwindow", 1750, 0)')
        self.h.tick(every)
        self.assertEqual(self.h.eval('solo', f'ANIMVARS({zb})'), 'actor=true gesture=openwindow')
        self.run_lua(f'{zb}:setVariable("LKActPhase", true)')       # événement SetVariable du premier clip
        self.h.tick(every)
        self.assertIs(self.ev(f'{zb}:getVariableBoolean("LKActPhase")'), True)   # même geste : gardée
        self.run_lua('LivingKnox.Anim.startAct("lk-1", "closewindow", 2080, 180)')
        self.h.tick(every)
        self.assertIs(self.ev(f'{zb}:getVariableBoolean("LKActPhase")'), False)  # autre geste : premier clip
        self.run_lua(f'{zb}:setVariable("LKActPhase", true)')
        self.h.tick(2080 // self.h.tick_ms + 2 * every)
        self.assertEqual(self.h.eval('solo', f'ANIMVARS({zb})'), 'actor=true gesture=idle')   # échu : geste voulu
        self.assertIs(self.ev(f'{zb}:getVariableBoolean("LKActPhase")'), False)
        self.assertIsNone(self.ev('(LivingKnox.Anim.actOf("lk-1"))'))
        # Gestes ponctuels réservés à startAct ; nom, durée et angle contrôlés.
        self.assertEqual(self.run_lua('return LivingKnox.Anim.setGesture("lk-1", "openwindow")')[1],
                         'unknown gesture openwindow')
        self.assertEqual(self.run_lua('return LivingKnox.Anim.startAct("lk-1", "dance", 1000)')[1], 'unknown act dance')
        self.assertIs(self.run_lua('return LivingKnox.Anim.startAct("lk-1", "openwindow", 0)')[0], False)
        self.assertIs(self.run_lua('return LivingKnox.Anim.startAct("lk-1", "openwindow", 100, "east")')[0], False)

    def test_gesture_stopped_when_someone_else_opens_the_window_first(self):
        self.window()
        zid = self.start()
        self.friendly_group()
        self.move()
        self.walk_w(zid, 300, until=lambda: self.ev('(LivingKnox.Anim.actOf("lk-1"))') is not None)
        self.assertEqual(self.ev('(LivingKnox.Anim.actOf("lk-1"))'), 'openwindow')
        self.run_lua('WINDOWS["106,102,0,W"].open = true')            # un joueur l'ouvre pendant le geste
        self.walk_w(zid, self.o('PASS_EVERY') + 1)
        self.assertIsNone(self.ev('(LivingKnox.Anim.actOf("lk-1"))'))
        self.assertEqual(self.o('stats.windowGesturesStopped'), 1)
        self.assertTrue(any('stopped: window already open' in s for s in self.lk()), self.lk())
        self.walk_w(zid, 900, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.wcount('solo'), (0, 0))                 # ouverte par un autre : jamais refermée
        self.assertEqual(self.o('stats.windowsClosed'), 0)

    def test_gesture_switched_off_toggles_at_once(self):
        self.window()
        self.run_lua('LivingKnox.Obstacles.WINDOW_GESTURE = false')
        zid = self.start()
        self.friendly_group()
        self.move()
        self.walk_w(zid, 900, until=self.done())
        self.walk_w(zid, 60)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.wcount('solo'), (2, 0))
        self.assertEqual(self.ev('LivingKnox.Anim.stats.acts'), 0)

    def test_door_is_opened_and_closed_without_any_gesture(self):
        """Le joueur vanilla ouvre une porte sans animation (ISOpenCloseDoor, durée 0) : aucun geste, marche fluide."""
        self.door()
        zid = self.start()
        self.move()
        self.walk_d(zid, 900, until=self.done())
        self.walk_d(zid, 60)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.counters('solo'), (2, 0))
        self.assertEqual(self.ev('LivingKnox.Anim.stats.acts'), 0)
        self.assertIsNone(self.ev('LivingKnox.Executor.stats.actPauses'))


class WindowCloseBehindTests(WindowGestureBase):
    """LK04-T18 (essai en jeu du 2026-10-13, lk.traversal) : la fenêtre était refermée quand le corps était déjà à 2 ou
    3 cases (CLOSE_DIST au moins, geste lancé en marche ou à l'arrivée). Le PNJ referme comme un joueur : arrêté sur la
    case voisine côté arrivée juste après l'enjambée, tourné vers la fenêtre, bascule à l'instant du clip, puis même
    consigne reprise. Ces tests échouent sur l'ancien code (fermeture à 1,5 case au moins, sans contrôle à la bascule)."""
    mode = 'solo'

    def act(self, npc='lk-1'):
        return self.ev(f'(LivingKnox.Anim.actOf("{npc}"))')

    def last_close(self):
        lc = self.ev('LivingKnox.Obstacles.lastClose')
        self.assertIsNotNone(lc, 'no window closed by the authority')
        return {k: lc[k] for k in ('key', 'id', 'd', 'gesture', 'facing')}

    def until_close_act(self, zid):
        self.walk_w(zid, 900, until=lambda: self.act() == 'closewindow')
        self.assertEqual(self.act(), 'closewindow')

    def test_closed_right_after_the_climb_body_stopped_next_to_it_facing_it_then_same_move_resumes(self):
        self.window()
        zid = self.start()
        self.friendly_group()
        v = self.move()
        rows = self.timeline(zid)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('v'), v)                          # même consigne, jamais remplacée
        cl = self.span(rows, 'solo', 'closewindow')
        self.assertIsNotNone(cl, 'no close gesture shown')
        closed = self.changed(rows, 'false false')
        self.assertTrue(cl[0] < closed <= cl[1], (cl, closed))
        at = rows[closed]
        # Côté arrivée, sur la case voisine de la fenêtre (bord x = 106), arrêté depuis le début du geste, tourné vers
        # elle (ouest, 180) ; bascule à CLOSE_TOGGLE_MS du début du geste.
        self.assertGreater(at['x'], 106)
        self.assertLessEqual(at['x'] - 106, 1.0, at)
        self.assertEqual({(r['x'], r['y']) for r in rows[cl[0] + 1:closed + 1]}, {(at['x'], at['y'])})
        self.assertTrue(all(abs(r['a'] - 180) < 1 for r in rows[cl[0] + 1:closed + 1]))
        dt = at['t'] - rows[cl[0]]['t']
        self.assertLessEqual(abs(dt - self.o('CLOSE_TOGGLE_MS')), self.slack(), dt)
        # Geste lancé dès la fin de l'escalade (passage avancé à l'image suivante).
        self.assertLessEqual(rows[cl[0]]['x'] - 106, 1.0)
        self.assertGreaterEqual(self.o('stats.landings'), 1)
        lc = self.last_close()
        self.assertEqual((lc['key'], lc['id'], lc['gesture'], lc['facing']), (DOOR_KEY, 'lk-1', True, True))
        self.assertLessEqual(lc['d'], 1.0)
        # Reprise du trajet après le geste : le corps repart de là et arrive (fermeture AVANT l'arrivée).
        self.assertGreater(max(r['x'] for r in rows[closed:]), 110.5)
        self.assertEqual(self.ev('LivingKnox.Executor.stats.actResumed'), 2)
        self.assertEqual(self.ev('LivingKnox.Executor.stats.failed'), 0)
        self.assertEqual(self.wcount('solo'), (2, 0))
        self.assertTrue(any('window 106,102,0,W closed behind npc lk-1 (body 0.' in s for s in self.lk()), self.lk())

    def test_toggle_waits_until_the_body_is_stopped(self):
        """Corps qui bouge encore pendant le geste (exécutant en retard, relais MP) : aucune bascule tant qu'il bouge,
        puis fermeture une fois arrêté devant la fenêtre."""
        self.window()
        zid = self.start()
        self.friendly_group()
        self.move()
        self.until_close_act(zid)
        n = int((self.o('CLOSE_GESTURE_MS') + 200) // self.h.tick_ms)
        for i in range(n):                                            # piétine sur la case d'arrivée
            self.h.tick(1)
            self.h.eval('solo', f'HARNESS.place(HARNESS.zombies[{zid}], {106.6 if i % 2 else 106.9}, 102.5, 0)')
        self.assertEqual(self.wstate('solo'), 'true false')
        self.assertGreater(self.o('stats.windowCloseWaits') or 0, 0)
        self.assertEqual(self.o('stats.windowsClosed'), 0)
        self.walk_w(zid, 900, until=self.done())                      # arrêté : nouveau geste, fermée
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.wstate('solo'), 'false false')
        lc = self.last_close()
        self.assertLessEqual(lc['d'], self.o('ACT_REACH'))
        self.assertTrue(lc['facing'])
        self.assertEqual(self.wcount('solo'), (2, 0))

    def test_window_occupied_during_the_gesture_is_closed_once_free(self):
        self.window()
        zid = self.start()
        self.friendly_group()
        self.move()
        self.until_close_act(zid)
        player = list(self.h.clients)[0]
        self.h.move_player(player, 105.5, 102.5, 0)                   # quelqu'un devant la fenêtre, côté départ
        self.walk_w(zid, int((self.o('CLOSE_TOGGLE_MS') + 200) // self.h.tick_ms))
        self.assertEqual(self.wstate('solo'), 'true false')
        self.assertGreater(self.o('stats.windowsBusy'), 0)
        self.assertEqual(self.act(), 'closewindow')                   # le corps attend, geste en cours
        self.h.move_player(player, 96, 108, 0)
        self.walk_w(zid, 2 * self.o('PASS_EVERY'))
        self.assertEqual(self.wstate('solo'), 'false false')
        lc = self.last_close()
        self.assertLessEqual(lc['d'], 1.0)
        self.walk_w(zid, 900, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.wcount('solo'), (2, 0))

    def test_follower_on_the_path_keeps_it_open_and_closes_it_after_its_own_climb(self):
        self.window()
        z1 = self.start()
        self.friendly_group()
        # lk-2 deux cases derrière : sa consigne part à l'ouverture ; quand lk-1 retombe de l'autre côté, lk-2 est à
        # DETECT case de la fenêtre et la franchit ensuite (dernier passant).
        _, b2 = self.spawn(x=101, y=102)
        z2 = b2.onlineID
        self.move()
        sent = False
        for _ in range(1500):
            self.h.tick(1)
            for z in (z1, z2):
                self.h.eval('solo', f'STEP_W({z}, 0.05)')
            if not sent and self.wstate('solo') == 'true false':
                self.assertIsNotNone(self.d('moveTo("lk-2", 111, 102, 0)'))
                sent = True
            if (self.ev('LivingKnox.Directives.entries["lk-2"] ~= nil and '
                        'LivingKnox.Directives.entries["lk-2"].done') is True and self.done()()):
                break
        self.assertTrue(sent)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.entry('s', 'lk-2'), 'arrived')
        logs = self.lk()
        self.assertFalse(any('npc lk-1: closewindow gesture' in s for s in logs), logs)
        self.assertTrue(any('npc lk-2: closewindow gesture' in s for s in logs), logs)
        lc = self.last_close()
        self.assertEqual((lc['id'], lc['gesture'], lc['facing']), ('lk-2', True, True))
        self.assertLessEqual(lc['d'], 1.0)
        self.assertEqual(self.wstate('solo'), 'false false')
        self.assertEqual(self.wcount('solo'), (2, 0))
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY] * 2)


class MultiplayerWindowGestureTests(WindowGestureBase):
    """Serveur dédié, A simule le corps, B regarde : le geste passe par le relais (geste affiché g et angle fa), la
    fenêtre par la synchronisation du serveur."""

    def setUp(self):
        super().setUp()
        SENT.clear()

    ready = MultiplayerTraversalTests.ready

    def relayed(self):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()

    def test_both_clients_see_the_gestures_and_the_owner_stops_and_turns(self):
        self.window()
        zid = self.start('A')
        self.friendly_group()
        self.move()
        self.h.pump()
        rows = self.timeline(zid, watch=('A', 'B'))
        self.assertEqual(self.entry('s'), 'arrived')
        for c in ('A', 'B'):
            self.assertIsNotNone(self.span(rows, c, 'openwindow'), c)
            self.assertIsNotNone(self.span(rows, c, 'closewindow'), c)
            self.assertEqual(self.wcount(c), (0, 0))                  # bascules sur le serveur seulement
            self.assertEqual(self.wstate(c), 'false false')
        self.assertEqual(self.wcount('server'), (2, 0))
        self.assertEqual(lua_list(self.h.eval('server', 'TOGGLED_BY')), ['zombie', 'zombie'])
        # A (propriétaire) arrête le corps pendant chaque geste et le tourne vers la fenêtre.
        op, cl = self.span(rows, 'A', 'openwindow'), self.span(rows, 'A', 'closewindow')
        still = rows[op[0] + 1:op[1] + 1]
        self.assertEqual(len({(r['x'], r['y']) for r in still}), 1)
        # LK04-T18 : arrêté jusqu'à la bascule (le chemin reprend ensuite, avant l'arrivée : la fin du geste affichée
        # chez A suit d'un passage d'affichage la reprise du chemin).
        closed = self.changed(rows, 'false false')
        self.assertTrue(cl[0] < closed <= cl[1], (cl, closed))
        behind = rows[cl[0] + 1:closed + 1]
        self.assertEqual(len({(r['x'], r['y']) for r in behind}), 1)
        self.assertLessEqual(rows[closed]['x'] - 106, 1.0)
        self.assertTrue(all(abs(r['a'] - 180) < 1 for r in behind), [r['a'] for r in behind][:16])
        # La fenêtre s'ouvre pendant le geste d'ouverture affiché chez A.
        opened = self.changed(rows, 'true false')
        self.assertTrue(op[0] < opened <= op[1], (op, opened))
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.stats.actResumed'), 2)
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.stats.failed'), 0)
        self.assertIsNone(self.h.eval('B', 'LivingKnox.Executor.stats.actPauses'))   # B ne simule pas
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.h.errors(m), [], m)

    def test_relayed_entry_carries_the_angle_of_the_act_only(self):
        self.ready('A')
        self.run_lua('LivingKnox.Anim.startAct("lk-1", "closewindow", 2080, 180)')
        self.relayed()
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, '(LivingKnox.Anim.actOf("lk-1"))'), 'closewindow')
            self.assertEqual(self.h.eval(c, 'LivingKnox.Anim.remote.a["lk-1"]'), 180)
        self.assertEqual(self.ev('LivingKnox.Anim.gestureOf("lk-1")'), 'idle')   # geste voulu inchangé
        self.h.tick(2080 // self.h.tick_ms + 2 * self.ev('LivingKnox.Anim.APPLY_EVERY'))
        self.relayed()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, '(LivingKnox.Anim.actOf("lk-1"))'))
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Anim.remote.a["lk-1"]'))


# ---------------------------------------------------------------- passage bloqué (LK04-T04)

FORCE_SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKForce.lua'

FORCE_DOUBLES = r'''
-- Passage bloqué (LK04-T04). Doublures fidèles au Java 42.21.0 relevé (elles ne prouvent pas l'API réelle) :
-- - IsoBarricade (J/iso/objects/IsoBarricade.java) : 4 planches à 1000 PV, planche extérieure = indice le plus haut,
--   métal ; Damage(amount) use la planche extérieure ou le métal et envoie sync() sur le serveur (:459-501) ;
--   WeaponHit(owner, weapon) : rien sur un client, dégâts DoorDamage x 5 (100 sans arme), barricade retirée pour tous
--   à la dernière planche (transmitRemoveItemFromSquare, :416-457) ; sendObjectChange(STATE) : serveur seulement
--   (loadChange redessine la barricade chez le client, :646-656 ; sync ne la redessine pas : champ sprite) ;
--   GetBarricadeForCharacter / OppositeCharacter (:719-737) : personnage à l'ouest (ou au nord) de la case de l'objet
--   -> barricade de la case opposée (côté a), sinon celle de la case de l'objet (côté b) ; AddBarricadeToObject(obj,
--   addOpposite) (:739-764), addPlank(chr, plank) (planche neuve : 1000, :90-108) ;
-- - IsoDoor:WeaponHit (J/iso/objects/IsoDoor.java:1056-1176) : rien sur un client ; barricade du côté du personnage
--   puis d'en face ; sinon porte ouverte ou détruite : rien ; NullPointerException sans arme ; dégâts
--   DoorDamage x 2 x 0,5 (force 0 d'un zombie), coup fort DoorDamage x 6 x 0,5 quand Rand.Next(10) = 0 (DOOR_RAND,
--   jamais par défaut) ; sync() sur le serveur ; PV <= 0 : destroy() (porte retirée pour tous, :1178-1210) ;
-- - HandWeapon (getDoorDamage, isRanged ; valeurs de media/scripts/generated/items/weapon.txt), instanceItem ;
-- - arme d'un PNJ : LivingKnox.Equipment.wantedOf (WEAPON_OF) et setWeapon (suite en jeu).
local H = HARNESS
local C = H.classes
local Obj = C.IsoObject
local Sq = C.IsoGridSquare
IsoObjectChange = IsoObjectChange or { STATE = 'STATE' }
BARS, REMOVED = {}, {}
BAR_HITS, DOOR_HITS, STATE_CHANGES, HIT_EVENTS = 0, 0, 0, 0
WEAPON_OF = {}
DOOR_RAND = function() return 1 end
local Bar = C.IsoBarricade or H.class('IsoBarricade', Obj)
IsoBarricade = Bar
local W = C.HandWeapon or H.class('HandWeapon')
local DOOR_DAMAGE = { ['Base.Sledgehammer'] = 40, ['Base.Axe'] = 35, ['Base.Crowbar'] = 8, ['Base.BaseballBat'] = 5,
    ['Base.BareHands'] = 0, ['Base.Shotgun'] = 0 }
local RANGED = { ['Base.Shotgun'] = true }
function W:getDoorDamage() return self.doorDamage end
function W:isRanged() return self.ranged == true end
function W:getFullType() return self.fullType end
local baseItem = instanceItem
instanceItem = function(t)
    if DOOR_DAMAGE[t] ~= nil then
        return setmetatable({ fullType = t, doorDamage = DOOR_DAMAGE[t], ranged = RANGED[t] }, W)
    end
    return baseItem and baseItem(t) or nil
end
LivingKnox.Equipment = LivingKnox.Equipment or {}
LivingKnox.Equipment.wantedOf = function(id)
    local t = WEAPON_OF[id]
    return t and { t = t } or nil
end
LivingKnox.Equipment.setWeapon = function(id, t)
    WEAPON_OF[id] = t ~= 'none' and t or nil
    return true
end
function REFRESH_BARS(o)
    local b = o.bars
    o.barricaded = (b ~= nil and (b.a ~= nil or b.b ~= nil)) or nil
end
local function attach(o, side, b)
    o.bars = o.bars or {}
    o.bars[side] = b
    REFRESH_BARS(o)
    BARS[o.key .. ':' .. side] = b
end
-- Barricade du côté side ("a" : case ouest ou nord du bord, "b" : case de l'objet) de l'objet de clé k.
function NEW_BARRICADE(k, side, planks, metal)
    local o = DOORS[k] or WINDOWS[k]
    local b = setmetatable({ obj = o, side = side, planks = {}, metal = metal or 0, key = k, square = o.square }, Bar)
    for i = 1, planks or 0 do b.planks[i] = 1000 end
    b.sprite = planks or 0
    attach(o, side, b)
    return b
end
function Bar:getNumPlanks()
    local n = 0
    for i = 1, 4 do if (self.planks[i] or 0) > 0 then n = n + 1 end end
    return n
end
function Bar:isDestroyed() return (self.metal or 0) <= 0 and self:getNumPlanks() <= 0 end
function Bar:isMetal() return (self.metal or 0) > 0 end
function Bar:getSquare() return (not self.removed) and self.square or nil end
function Bar:getObjectIndex() return self.removed and -1 or 0 end
function Bar:addPlank(chr, plank)
    for i = 1, 4 do
        if (self.planks[i] or 0) <= 0 then self.planks[i] = 1000; break end
    end
    self.sprite = self:getNumPlanks()
end
function Bar:transmitCompleteItemToClients() end
function Bar:Damage(amount)
    if (self.metal or 0) > 0 then
        self.metal = math.max(0, self.metal - amount)
    else
        for i = 4, 1, -1 do
            if (self.planks[i] or 0) > 0 then
                self.planks[i] = self.planks[i] - amount
                if self.planks[i] <= 0 then self.planks[i] = 0; self.sprite = self:getNumPlanks() end
                break
            end
        end
    end
    if isServer() then SYNCS[#SYNCS + 1] = { key = self.key, bar = self.side, n = self:getNumPlanks() } end
end
local function removeBar(b)
    b.removed = true
    if b.obj.bars ~= nil and b.obj.bars[b.side] == b then b.obj.bars[b.side] = nil end
    REFRESH_BARS(b.obj)
end
function Bar:WeaponHit(owner, weapon)
    if self:isDestroyed() then return end
    if isClient() then return end
    HIT_EVENTS = HIT_EVENTS + 1
    BAR_HITS = BAR_HITS + 1
    if weapon ~= nil then self:Damage(weapon:getDoorDamage() * 5) else self:Damage(100) end
    if self:isDestroyed() then
        removeBar(self)
        if isServer() then SYNCS[#SYNCS + 1] = { key = self.key, bar = self.side, n = 0, gone = true } end
    end
end
function Bar:sendObjectChange(change)
    if change ~= IsoObjectChange.STATE then error('unexpected change ' .. tostring(change), 2) end
    if not isServer() then return end
    STATE_CHANGES = STATE_CHANGES + 1
    SYNCS[#SYNCS + 1] = { key = self.key, bar = self.side, n = self:getNumPlanks(), state = true }
end
function Bar.AddBarricadeToObject(o, addOpposite)
    local side = addOpposite and 'a' or 'b'
    if o.bars ~= nil and o.bars[side] ~= nil then return o.bars[side] end
    return NEW_BARRICADE(o.key, side, 0)
end
local baseRemove = Sq.RemoveTileObject
function Sq:RemoveTileObject(o)
    if getmetatable(o) == Bar then return removeBar(o) end
    if baseRemove then return baseRemove(self, o) end
end
function Sq:transmitRemoveItemFromSquare(o) return self:RemoveTileObject(o) end
-- Réception (client) : sync (PV des planches, aucun redessin) ; STATE (redessin) ; retrait.
function APPLY_BAR(k, side, n, state, gone)
    local b = BARS[k .. ':' .. side]
    if b == nil or b.removed then return end
    if gone then return removeBar(b) end
    for i = 1, 4 do b.planks[i] = (i <= n) and 1000 or 0 end
    if state then b.sprite = n end
end
local function forChr(o, chr, same)
    local west = chr ~= nil and ((o.north and chr:getY() < o.y) or ((not o.north) and chr:getX() < o.x))
    local side = west and 'a' or 'b'
    if not same then side = (side == 'a') and 'b' or 'a' end
    return o.bars ~= nil and o.bars[side] or nil
end
for _, cls in ipairs({ C.IsoDoor, C.IsoThumpable, C.IsoWindow, C.IsoWindowFrame }) do
    cls.getBarricadeForCharacter = function(self, chr) return forChr(self, chr, true) end
    cls.getBarricadeOppositeCharacter = function(self, chr) return forChr(self, chr, false) end
end
local Door = C.IsoDoor
function Door:getHealth() return self.health or 500 end
function Door:WeaponHit(owner, weapon)
    if isClient() then return end
    local t = self:getBarricadeForCharacter(owner) or self:getBarricadeOppositeCharacter(owner)
    if t == nil and (self.destroyed or self.open) then return end
    if t ~= nil then return t:WeaponHit(owner, weapon) end
    HIT_EVENTS = HIT_EVENTS + 1
    if weapon == nil then error('NullPointerException: weapon.getDoorDamage()', 2) end
    DOOR_HITS = DOOR_HITS + 1
    local mod = 0.5
    self.health = self:getHealth() - math.floor(weapon:getDoorDamage() * 2 * mod)
    if DOOR_RAND() == 0 then self.health = self.health - math.floor(weapon:getDoorDamage() * 6 * mod) end
    if isServer() then SYNCS[#SYNCS + 1] = { key = self.key, health = self.health } end
    if self.health <= 0 then self:destroy() end
end
function Door:destroy()
    self.destroyed, self.removed = true, true
    REMOVED[#REMOVED + 1] = self.key
    if isServer() then SYNCS[#SYNCS + 1] = { key = self.key, gone = true } end
end
function APPLY_GONE(k)
    local d = DOORS[k]
    if d ~= nil then d.destroyed, d.removed = true, true end
end
function APPLY_HEALTH(k, h)
    local d = DOORS[k]
    if d ~= nil then d.health = h end
end
'''


class ForceBase(ObstacleBase):
    """LK04-T04 : porte (106, 102) W dans un mur (aucun détour), corps parti de (102, 102) vers (111, 102)."""

    def make(self, root=None):
        h = super().make(root)
        for m in self.machines:
            h.load(m, FORCE_DOUBLES)
        return h

    def relay_doors(self):
        """Comme ObstacleBase.relay_doors, avec les barricades (PV, redessin, retrait), la santé et le retrait d'une
        porte."""
        if self.mode == 'solo':
            return 0
        n = 0
        for src in ('server', 'A', 'B'):
            syncs = self.h.eval(src, 'SYNCS')
            items = [syncs[i] for i in range(1, len(syncs) + 1)]
            self.h.load(src, 'SYNCS = {}')
            for s in items:
                n += 1
                SENT.append((src, s.key))
                for dst in ('server', 'A', 'B'):
                    if dst == src:
                        continue
                    if s.bar:
                        self.h.eval(dst, f'APPLY_BAR("{s.key}", "{s.bar}", {s.n}, {str(bool(s.state)).lower()}, '
                                         f'{str(bool(s.gone)).lower()})')
                    elif s.gone:
                        self.h.eval(dst, f'APPLY_GONE("{s.key}")')
                    elif s.health is not None:
                        self.h.eval(dst, f'APPLY_HEALTH("{s.key}", {s.health})')
                    elif s.win:
                        self.h.eval(dst, f'APPLY_WINDOW("{s.key}", {str(s.open).lower()}, '
                                         f'{str(s.destroyed).lower()})')
                    else:
                        self.h.eval(dst, f'APPLY_DOOR("{s.key}", {str(s.open).lower()}, {str(s.locked).lower()}, '
                                         f'{str(s.lockedByKey).lower()})')
        return n

    def weapon(self, t='Base.Sledgehammer', npc='lk-1'):
        for m in self.machines:
            self.h.load(m, f'WEAPON_OF["{npc}"] = "{t}"')

    def bar(self, side='a', planks=2, key=DOOR_KEY):
        for m in self.machines:
            self.h.load(m, f'NEW_BARRICADE("{key}", "{side}", {planks})')

    def planks(self, m=None, side='a', key=DOOR_KEY):
        return self.h.eval(m or self.srv, f'(function() local b = BARS["{key}:{side}"] '
                                          f'if b == nil or b.removed then return 0 end return b:getNumPlanks() end)()')

    def g(self, name, m=None):
        return self.h.eval(m or self.srv, name)

    def setup(self, gtype='raiders', weapon='Base.Sledgehammer', planks=2, owner='A', **door):
        self.door(**door)
        self.wall()
        zid = self.start(owner)
        self.friendly_group(gtype=gtype, name=gtype.capitalize())
        if weapon:
            self.weapon(weapon)
        if planks:
            self.bar(planks=planks)
        return zid

    def trip(self, zid, ticks=4000, check=None):
        """move vers (111, 102), marche jusqu'à la fin de la consigne ; rend la durée (ms d'horloge du banc) et les
        gestes affichés vus sur la copie qui simule."""
        seen = set()
        t0 = self.ev('getTimestampMs()')
        self.move()
        if self.mode == 'mp':
            self.h.pump()

        def look():
            m = self.sim(zid)
            seen.add(self.h.eval(m, f'ANIMVARS(HARNESS.zombies[{zid}])').split('gesture=')[-1])
            act = self.ev('(LivingKnox.Anim.actOf("lk-1"))')
            if act:
                seen.add('act:' + act)
            if check:
                check()
        self.walk_w(zid, ticks, until=self.done(), check=look)
        ms = self.ev('getTimestampMs()') - t0
        self.walk_w(zid, 120)
        return ms, seen


class ForceTests(ForceBase):
    mode = 'solo'

    def test_policy_by_group_type(self):
        self.start()
        self.assertEqual(self.o('blockedPolicy("lk-1")'), 'detour')            # sans groupe
        gid = self.friendly_group(gtype='settlers')
        self.assertEqual(self.o('blockedPolicy("lk-1")'), 'detour')            # colons (10)
        for gtype, want in (('neutrals', 'wait'), ('raiders', 'force')):
            self.run_lua(f'LivingKnox.Groups.state.data.groups["{gid}"].type = "{gtype}"')
            self.assertEqual(self.o('blockedPolicy("lk-1")'), want, gtype)
        self.run_lua('LivingKnox.Obstacles.BLOCKED_RULES = false')
        self.assertEqual(self.o('blockedPolicy("lk-1")'), 'detour')

    def test_raider_breaks_the_barricade_plank_by_plank_then_the_door_is_opened_and_closed_behind(self):
        zid = self.setup()
        ms, seen = self.trip(zid)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertIn('act:force', seen)
        self.assertIn('strike', seen)                                           # clip de frappe affiché
        # 2 planches de 1000 PV, Sledgehammer DoorDamage 40 x 5 = 200 par coup : 5 coups par planche.
        self.assertEqual(self.g('BAR_HITS'), 10)
        self.assertEqual(self.g('DOOR_HITS'), 0)
        self.assertEqual(self.o('stats.planksBroken'), 2)
        self.assertEqual(self.o('stats.barricadesBroken'), 1)
        self.assertEqual(self.o('stats.forced'), 1)
        self.assertEqual(self.o('stats.forceHits'), 10)
        self.assertEqual(self.o('stats.refused'), 0)
        self.assertEqual(self.planks(), 0)
        self.assertIs(self.ev('DOORS["106,102,0,W"]:isBarricaded()'), False)
        self.assertEqual(self.counters('solo'), (2, 0))                        # ouverte puis refermée, sans ToggleDoor
        self.assertEqual(self.state('solo'), 'false false false')
        self.assertEqual(self.g('STATE_CHANGES'), 0)                            # solo : aucun envoi
        # Un coup par boucle du clip : au moins 10 boucles de STRIKE_MS (premier coup à IMPACT_MS).
        self.assertGreaterEqual(ms, 9 * self.o('STRIKE_MS') + self.o('IMPACT_MS'))
        self.assertEqual(self.ev('LivingKnox.Executor.stats.failed'), 0)
        self.assertIsNone(self.ev('(LivingKnox.Anim.actOf("lk-1"))'))
        logs = self.lk()
        self.assertTrue(any('forcing the door 106,102,0,W (barricaded door) with Base.Sledgehammer' in s
                            for s in logs), logs)
        self.assertTrue(any('barricade on the door 106,102,0,W broken' in s for s in logs), logs)
        self.assertEqual(self.h.errors('solo'), [])

    def test_raider_breaks_a_locked_door_without_the_key(self):
        zid = self.setup(planks=0, locked=True, lockedByKey=True, keyId=77)
        _, seen = self.trip(zid)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertIn('act:force', seen)
        # Porte de 500 PV, 40 x 2 x 0,5 = 40 par coup (force 0 d'un zombie) : 13 coups.
        self.assertEqual(self.g('DOOR_HITS'), 13)
        self.assertEqual(lua_list(self.g('REMOVED')), [DOOR_KEY])
        self.assertEqual(self.o('stats.doorsBroken'), 1)
        self.assertEqual(self.o('stats.forced'), 1)
        self.assertEqual(self.o('stats.refused'), 0)
        self.assertEqual(self.counters('solo'), (0, 0))                        # jamais ouverte : cassée
        self.assertTrue(any('door 106,102,0,W broken' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('solo'), [])

    def test_settler_is_refused_at_once_and_breaks_nothing(self):
        zid = self.setup(gtype='settlers')
        ms, seen = self.trip(zid)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.o('lastRefused.why'), 'barricaded door')
        self.assertLess(ms, self.o('WAIT_MS') / 2)
        self.assertNotIn('act:wait', seen)
        self.assertNotIn('act:force', seen)
        self.assertEqual((self.g('BAR_HITS'), self.planks()), (0, 2))

    def test_neutral_waits_then_is_refused(self):
        zid = self.setup(gtype='neutrals')
        ms, seen = self.trip(zid)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertIn('act:wait', seen)
        self.assertNotIn('act:force', seen)
        self.assertGreaterEqual(ms, self.o('WAIT_MS'))
        self.assertEqual(self.o('lastRefused.why'), 'barricaded door (waited 15000 ms)')
        self.assertEqual((self.g('BAR_HITS'), self.planks()), (0, 2))
        self.assertEqual(self.o('stats.waitedOut'), 1)
        # L'exécutant n'a pas échoué de lui-même pendant l'attente (geste ponctuel : corps gardé arrêté).
        self.assertEqual(self.ev('LivingKnox.Executor.stats.failed'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_neutral_goes_on_when_the_door_is_unlocked_during_the_wait(self):
        zid = self.setup(gtype='neutrals', planks=0, locked=True, lockedByKey=True, keyId=77)
        self.move()
        self.walk_w(zid, 2000, until=lambda: self.ev('(LivingKnox.Anim.actOf("lk-1"))') == 'wait')
        self.assertEqual(self.ev('(LivingKnox.Anim.actOf("lk-1"))'), 'wait')
        self.run_lua('DOORS["106,102,0,W"].locked = false; DOORS["106,102,0,W"].lockedByKey = false')   # un joueur
        self.walk_w(zid, 2000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.o('stats.waitResumed'), 1)
        self.assertEqual(self.o('stats.refused'), 0)
        self.assertEqual(self.o('stats.opened'), 1)

    def test_friendly_home_never_forced_without_an_order_then_forced_with_it(self):
        self.building()
        self.door()
        self.wall()
        zid = self.start()
        self.group(member=False, name='Owners')                                 # colons : foyer B1, amis des joueurs
        self.friendly_group(gtype='raiders', name='Raiders')
        self.weapon()
        self.bar(planks=1)
        _, seen = self.trip(zid)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertNotIn('act:force', seen)
        self.assertEqual(self.o('stats.forceRefused'), 1)
        self.assertEqual((self.g('BAR_HITS'), self.planks()), (0, 1))
        self.assertTrue(any('not forced: home of grp-1, a group friendly to the players (no order to force it)' in s
                            for s in self.lk()), self.lk())
        # Consigne explicite pour le "move" suivant : barricade brisée, porte non verrouillée du foyer ouverte.
        self.move()
        self.assertIs(self.o('orderForce("lk-1")'), True)
        self.walk_w(zid, 4000, until=self.done())
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.planks(), 0)
        self.assertEqual(self.o('stats.forced'), 1)
        self.assertTrue(any('door 106,102,0,W of the home of grp-1 opened by force' in s for s in self.lk()),
                        self.lk())
        self.walk_w(zid, 60)
        self.assertEqual(self.o('forceOrders["lk-1"]'), None)                  # consigne close : ordre oublié

    def test_home_of_a_hostile_group_is_forced_without_an_order(self):
        self.building()
        self.door(locked=True, lockedByKey=True, keyId=77)
        self.wall()
        zid = self.start()
        self.run_lua('local g = LivingKnox.Groups.create({ type = "raiders", name = "Camp", '
                     'home = { x = 108, y = 101, z = 0 } }) LivingKnox.Obstacles.refreshHomes(true)')
        self.friendly_group(gtype='raiders', name='Raiders')
        self.weapon()
        self.trip(zid)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.o('stats.doorsBroken'), 1)

    def test_raider_without_a_weapon_able_to_damage_a_door_is_refused(self):
        for weapon in ('Base.BareHands', 'Base.Shotgun', None):
            with self.subTest(weapon=weapon):
                self.tearDown()
                self.setUp()
                zid = self.setup(weapon=weapon)
                self.trip(zid)
                self.assertEqual(self.entry('s'), 'failed')
                self.assertEqual(self.o('stats.forceRefused'), 1)
                self.assertEqual(self.g('BAR_HITS'), 0)
                self.assertTrue(any('not forced: no weapon able to damage a door' in s for s in self.lk()))

    def test_forcing_stops_when_another_directive_replaces_the_move(self):
        zid = self.setup(planks=4)
        self.move()
        self.walk_w(zid, 3000, until=lambda: self.g('BAR_HITS') >= 2)
        self.assertEqual(self.ev('(LivingKnox.Anim.actOf("lk-1"))'), 'force')
        self.d('stop("lk-1")')                                                  # cadre de décision, combat...
        self.walk_w(zid, 400)
        hits = self.g('BAR_HITS')
        self.walk_w(zid, 400)
        self.assertEqual(self.g('BAR_HITS'), hits)
        self.assertIsNone(self.ev('(LivingKnox.Anim.actOf("lk-1"))'))
        self.assertIsNone(self.o('forcing["lk-1"]'))
        self.assertEqual(self.o('stats.refused'), 0)
        self.assertTrue(any('ended after' in s and 'move no longer running' in s for s in self.lk()), self.lk())

    def test_forcing_given_up_after_its_time(self):
        zid = self.setup(weapon='Base.BaseballBat')                             # 25 par coup : 40 coups par planche
        self.run_lua('LivingKnox.Obstacles.FORCE_GIVE_UP_MS = 5000')
        self.trip(zid)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(self.o('lastRefused.why').startswith('barricaded door (forcing given up after '),
                        self.o('lastRefused.why'))
        self.assertEqual(self.o('stats.forceGivenUp'), 1)
        self.assertEqual(self.planks(), 2)
        self.assertGreater(self.g('BAR_HITS'), 0)

    def test_barricaded_window_forced_then_opened_and_crossed_never_smashed(self):
        self.window()
        self.wall()
        zid = self.start()
        self.friendly_group(gtype='raiders', name='Raiders')
        self.weapon()
        self.bar(planks=1)
        _, seen = self.trip(zid)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertIn('act:force', seen)
        self.assertEqual(self.o('stats.planksBroken'), 1)
        self.assertEqual(self.g('BAR_HITS'), 5)
        self.assertEqual(self.wcount('solo'), (2, 0))                           # ouverte puis refermée, jamais brisée
        self.assertEqual(self.climbs('solo'), ['climbwindow ' + DOOR_KEY])
        self.assertEqual(self.h.errors('solo'), [])

    def test_rules_switched_off_raider_refused_at_once(self):
        zid = self.setup()
        self.run_lua('LivingKnox.Obstacles.BLOCKED_RULES = false')
        self.trip(zid)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.o('lastRefused.why'), 'barricaded door')
        self.assertEqual(self.g('BAR_HITS'), 0)


class MultiplayerForceTests(ForceBase):
    """Serveur dédié, A simule le corps, B regarde : coups appliqués par le serveur seul, planches retirées et porte
    ouverte vues par A et B (sync, STATE, retrait), geste de frappe affiché chez les deux clients."""

    def setUp(self):
        super().setUp()
        SENT.clear()

    ready = MultiplayerTraversalTests.ready

    def test_raider_forces_the_barricade_effects_seen_by_both_clients(self):
        zid = self.setup(owner='A')
        gestures = {'A': set(), 'B': set()}

        def check():
            for c in ('A', 'B'):
                gestures[c].add(self.h.eval(c, f'ANIMVARS(HARNESS.zombies[{zid}])').split('gesture=')[-1])
        self.trip(zid, check=check)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.g('BAR_HITS', 'server'), 10)
        for c in ('A', 'B'):
            self.assertEqual(self.g('BAR_HITS', c), 0, c)                       # aucun coup sur un client
            self.assertIn('strike', gestures[c], c)
            self.assertEqual(self.planks(c), 0, c)                              # barricade retirée chez lui
            self.assertIs(self.h.eval(c, 'DOORS["106,102,0,W"]:isBarricaded()'), False, c)
            self.assertEqual(self.state(c), self.state('server'), c)
            self.assertEqual(self.counters(c), (0, 0), c)
        # Première planche brisée (barricade restante) : STATE envoyé pour la redessiner ; seconde : barricade retirée.
        self.assertEqual(self.g('STATE_CHANGES', 'server'), 1)
        self.assertEqual(self.h.eval('A', 'LivingKnox.Executor.stats.failed'), 0)
        self.assertIsNone(self.h.eval('B', 'LivingKnox.Executor.stats.actPauses'))
        for m in ('server', 'A', 'B'):
            self.assertEqual(self.h.errors(m), [], m)

    def test_sprite_of_a_broken_plank_redrawn_on_the_clients(self):
        zid = self.setup(owner='A', planks=3)
        self.move()
        self.h.pump()
        self.walk_w(zid, 3000, until=lambda: self.planks('server') == 2)
        self.walk_w(zid, 5)
        for c in ('A', 'B'):
            self.assertEqual(self.h.eval(c, 'BARS["106,102,0,W:a"].sprite'), 2, c)

    def test_door_broken_on_the_server_removed_on_both_clients(self):
        zid = self.setup(owner='A', planks=0, locked=True, lockedByKey=True, keyId=77)
        self.trip(zid)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.g('DOOR_HITS', 'server'), 13)
        for c in ('A', 'B'):
            self.assertEqual(self.g('DOOR_HITS', c), 0, c)
            self.assertIs(self.h.eval(c, 'DOORS["106,102,0,W"].removed'), True, c)


class ForceSuiteTests(ForceBase):
    """Suite en jeu lk.force (LK04-T04) jouée sur le banc : corps relevé et pas de marche STEP_D à chaque image."""
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', 'shared/RST/suites/RST_LKForce.lua')
        return h

    def run_walking(self, name, ticks=8000):
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.force", tags = "world", test = "%s" }, '
                                          '{ ctx = { player = getPlayer() } }))' % name), True)
        for _ in range(ticks):
            self.h.tick()
            self.h.load('solo', 'for _, z in pairs(LivingKnox.Bodies.bound) do '
                                'z.onFloor = false; STEP_D(z.onlineID, 0.05) end')   # PNJ de chaque test
            if not self.h.eval('solo', 'RST.running()'):
                break
        report = self.h.eval('solo', 'RST.last()')
        return [(r.test, r.status, r.message) for r in lua_list(report.results)]

    def test_suite_lists_with_world_tags_and_is_ascii(self):
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.force", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.force')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertEqual(listed.count, 6)
        src = FORCE_SUITE.read_text(encoding='utf-8')
        code = '\n'.join(line.split('--', 1)[0] for line in src.splitlines())
        self.assertTrue(code.isascii())
        self.assertNotRegex(code, r'\bnext\s*\(|\bgoto\b|\bcoroutine\.|\bbit32\b')

    def test_suite_raider_forces_a_barricaded_door(self):
        self.building()
        self.door()
        self.init()
        results = self.run_walking('barricaded door: forced by a raider, plank broken, then opened')
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.state('solo'), 'false false false')                # porte rendue
        self.assertEqual(self.o('stats.planksBroken'), 1)

    def test_suite_neutral_waits_then_is_refused(self):
        self.building()
        self.door()
        self.init()
        results = self.run_walking('barricaded door: a neutral waits, then is refused')
        self.assertEqual([r[1] for r in results], ['PASS'], results)
        self.assertEqual(self.planks(), 0)                                      # barricade retirée par la suite

    def test_suite_friendly_home_with_and_without_order(self):
        self.building()
        self.door()
        self.init()
        for name in ('barricaded home door of settlers: not forced by a raider without an order',
                     'barricaded home door of settlers: forced by a raider with an explicit order'):
            results = self.run_walking(name)
            self.assertEqual([r[1] for r in results], ['PASS'], (name, results))


class InsideDoorTests(ObstacleBase):
    """LK04-T17 (essai solo du 2026-10-12, lk.walls, grp-52) : le bâtisseur lk-73, né dans son foyer avec la clé du
    bâtiment (91822195), est refusé deux fois à la porte 10664,9551,0,N (« locked door (no key) ») et n'atteint jamais
    son chantier dehors ; la clé du bâtiment ouvrait pourtant la porte extérieure 10661,9547,0,N (lk-75) : porte
    intérieure verrouillée, keyId -1 (IsoDoor.checkKeyId, IsoDoor.java:1979-2002). Règle vanilla d'un joueur : de
    l'intérieur (case non extérieure, dans la pièce d'un côté), une porte verrouillée s'ouvre sans clé, sauf porte
    blindée forceLocked (canBeOpenFromInside, IsoDoor.java:1266-1268, 1280-1282, 1343-1346). Maison HOUSE (B1, clé 77,
    x 106..111) ; porte intérieure (109, 102) W ; porte extérieure (106, 102) W. Portes de garage : tous les panneaux
    (IsoDoor.toggleGarageDoor, :2906-2932). lk.traversal du 2026-10-12 : porte refusée LONGEANT la voie après une
    clôture basse, consigne refusée à la fin de l'escalade ; destination juste derrière une porte verrouillée
    « atteinte » à travers elle (Directives.ARRIVE)."""
    mode = 'solo'

    def trip(self, start=(107, 102), target=(111, 102), ticks=900, walk='d'):
        _, body = self.spawn(x=start[0], y=start[1])
        zid = body.onlineID
        self.d(f'moveTo("lk-1", {target[0]}, {target[1]}, 0)')
        (self.walk_w if walk == 'w' else self.walk_d)(zid, ticks, until=self.done())
        (self.walk_w if walk == 'w' else self.walk_d)(zid, 40)
        return zid

    def test_member_opens_a_locked_interior_door_of_its_home_without_key_id(self):
        self.building()
        self.wall(x=109, skip=(102,))
        self.door(x=109, locked=True)
        self.init()
        self.group(member=True)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.ev('KEYS_ON((LivingKnox.Bodies.find("lk-1")))'), '77')   # clé du bâtiment
        self.assertEqual(self.h.eval('solo', 'DOORS["109,102,0,W"].keyId'), None)     # porte intérieure : -1
        # LK04-T19 : refermée et reverrouillée derrière lui avec la clé de son foyer.
        self.assertEqual(self.state('solo', '109,102,0,W'), 'false true true')
        self.assertIn(self.o('stats.refused'), (None, 0))
        self.assertTrue(any('door 109,102,0,W opened and unlocked (member of grp-1) from inside (to be relocked '
                            'with its home key 77)' in s for s in self.lk()), self.lk())
        self.assertTrue(any('door 109,102,0,W closed behind npc lk-1 and locked' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('solo'), [])

    # LK04-T19 (décision de l'utilisateur du 2026-10-14) : porte du foyer ouverte de l'intérieur sans sa clé,
    # reverrouillée derrière le PNJ seulement s'il porte la clé du foyer et que la porte n'a pas d'autre clé.
    def interior(self, **fields):
        self.wall(x=109, skip=(102,))
        self.door(x=109, locked=True, **fields)

    def test_member_without_its_home_key_leaves_the_interior_door_unlocked(self):
        self.building()
        self.interior()
        self.init()
        self.group(member=True)
        _, body = self.spawn(x=107, y=102)
        self.assertEqual(self.o('removeKeys((LivingKnox.Bodies.find("lk-1")))'), 1)   # clé perdue (non rendue)
        self.d('moveTo("lk-1", 111, 102, 0)')
        self.walk_d(body.onlineID, 900, until=self.done())
        self.walk_d(body.onlineID, 40)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.ev('KEYS_ON((LivingKnox.Bodies.find("lk-1")))'), '')
        self.assertEqual(self.state('solo', '109,102,0,W'), 'false false false')     # refermée, non reverrouillée
        self.assertTrue(any('door 109,102,0,W opened and unlocked (member of grp-1) from inside' in s
                            and 'relocked' not in s for s in self.lk()), self.lk())
        self.assertIn(self.o('stats.locked'), (None, 0))
        self.assertEqual(self.h.errors('solo'), [])

    def test_home_door_with_its_own_other_key_is_left_unlocked(self):
        self.building()
        self.interior(lockedByKey=True, keyId=55)          # serrure propre : la clé du foyer (77) ne la ferme pas
        self.init()
        self.group(member=True)
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.ev('KEYS_ON((LivingKnox.Bodies.find("lk-1")))'), '77')
        self.assertEqual(self.state('solo', '109,102,0,W'), 'false false false')
        self.assertEqual(self.h.errors('solo'), [])

    def test_locked_door_of_another_building_opened_from_inside_stays_unlocked(self):
        self.building()                                     # B1 : bâtiment de la porte, foyer de personne
        self.building(HOME9)                                # foyer du groupe : B9, clé 99
        self.interior()
        self.init()
        self.group(member=True, home=(301, 301, 0))
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.ev('KEYS_ON((LivingKnox.Bodies.find("lk-1")))'), '99')
        self.assertEqual(self.state('solo', '109,102,0,W'), 'false false false')     # inchangée : déverrouillée
        self.assertTrue(any('door 109,102,0,W opened and unlocked from inside' in s for s in self.lk()), self.lk())
        self.assertEqual(self.h.errors('solo'), [])

    def test_member_who_lost_its_key_before_closing_leaves_it_unlocked(self):
        self.building()
        self.interior()
        self.init()
        self.group(member=True)
        _, body = self.spawn(x=107, y=102)
        zid = body.onlineID
        self.d('moveTo("lk-1", 111, 102, 0)')
        lost = []

        def check():
            if not lost and self.state('solo', '109,102,0,W').startswith('true'):
                lost.append(self.o('removeKeys((LivingKnox.Bodies.find("lk-1")))'))
        self.walk_d(zid, 900, until=self.done(), check=check)
        self.walk_d(zid, 40)
        self.assertEqual(lost, [1])
        self.assertEqual(self.state('solo', '109,102,0,W'), 'false false false')
        self.assertTrue(any('door 109,102,0,W: npc lk-1 lost its key, left unlocked' in s for s in self.lk()),
                        self.lk())

    def test_locked_exterior_door_opened_from_inside_never_from_outside_without_key(self):
        self.building()
        self.wall()
        self.door(locked=True, lockedByKey=True, keyId=77)
        self.init()
        self.trip(start=(108, 102), target=(102, 102))                   # aucun groupe, aucune clé : sortie
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.state('solo'), 'false false false')
        self.run_lua('local d = DOORS["106,102,0,W"]; d.locked = true; d.lockedByKey = true')
        self.d('moveTo("lk-1", 108, 102, 0)')                             # retour, de dehors
        zid = self.ev('(LivingKnox.Bodies.find("lk-1")):getOnlineID()')
        self.walk_d(zid, 600, until=self.done())
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(any('refused at the door 106,102,0,W: locked door (no key)' in s for s in self.lk()),
                        self.lk())
        self.assertEqual(self.state('solo'), 'false true true')

    def test_armoured_door_is_not_opened_from_inside(self):
        self.building()
        self.wall(x=109, skip=(102,))
        self.door(x=109, locked=True)
        self.run_lua('DOORS["109,102,0,W"].props = { forceLocked = true }')   # clé du bâtiment (checkKeyId)
        self.init()
        self.trip()                                                           # aucun groupe, aucune clé
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(any('refused at the door 109,102,0,W: locked door (no key)' in s for s in self.lk()),
                        self.lk())

    def test_built_door_locked_is_opened_from_any_square_not_outside(self):
        # IsoThumpable.java:1100-1114, 1136-1153 : le verrou ne retient que sur une case extérieure.
        self.building()
        self.wall(x=109, skip=(102,))
        self.door(x=109, cls='thump', locked=True, lockedByKey=True, keyId=5)
        self.init()
        self.trip()
        self.assertEqual(self.entry('s'), 'arrived')

    def test_route_crosses_a_locked_exterior_door_only_from_inside(self):
        self.building()
        self.wall()
        self.door(locked=True, lockedByKey=True, keyId=77)
        self.init()
        self.spawn(x=108, y=102)
        refusal = 'return LivingKnox.Obstacles.doorRefusal("lk-1", DOORS["106,102,0,W"], %s, %s, %s)'
        a, b = 'getCell():getGridSquare(105, 102, 0)', 'getCell():getGridSquare(106, 102, 0)'
        self.assertIsNone(self.run_lua(refusal % (a, b, b)))                     # abordée de l'intérieur
        self.assertEqual(self.run_lua(refusal % (a, b, a)), 'locked door (no key)')   # de dehors

    def test_destination_right_behind_a_locked_door_is_not_reached_through_it(self):
        # lk.traversal du 2026-10-12 : corps devant la porte, à 1,0 case du centre de la case visée : « arrivé ».
        self.building()
        self.wall()
        self.door(locked=True, lockedByKey=True, keyId=77)
        self.init()
        self.trip(start=(102, 102), target=(106, 102), ticks=600)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertTrue(any('refused at the door 106,102,0,W: locked door (no key)' in s for s in self.lk()),
                        self.lk())
        self.assertIs(self.ev('LivingKnox.Executor.behindClosedDoor((LivingKnox.Bodies.find("lk-1")), 106, 102, 0)'),
                      True)

    def garage(self, **fields):
        # Panneaux (106, 103) index 1, (106, 102) index 2, (106, 101) index 3 (bord ouest : suivant à y - 1).
        for y, i in ((103, 1), (102, 2), (101, 3)):
            self.door(y=y, garage=i, **fields)
        self.wall(skip=(101, 102, 103))

    def panels(self):
        return [self.state('solo', f'106,{y},0,W') for y in (101, 102, 103)]

    def test_garage_door_all_panels_opened_with_the_key_then_closed_and_locked(self):
        self.building()
        self.garage(locked=True, lockedByKey=True, keyId=77)
        self.init()
        self.group(member=True)
        opened = []
        _, body = self.spawn(x=102, y=102)
        zid = body.onlineID
        self.d('moveTo("lk-1", 109, 102, 0)')

        def check():
            if self.panels()[1].startswith('true'):
                opened.append(self.panels())
        self.walk_d(zid, 900, until=self.done(), check=check)
        self.walk_d(zid, 40)
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertTrue(opened, self.lk())
        self.assertEqual(opened[0], ['true false false'] * 3)                     # tous les panneaux d'un coup
        self.assertEqual(self.panels(), ['false true true'] * 3)                  # refermés et reverrouillés
        self.assertEqual(self.o('stats.opened'), 1)
        self.assertEqual(self.o('stats.unlocked'), 1)
        self.assertEqual(self.o('stats.locked'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_garage_door_without_key_refused_from_outside(self):
        self.building()
        self.garage(locked=True, lockedByKey=True, keyId=77)
        self.init()
        self.trip(start=(102, 102), target=(109, 102), ticks=600)
        self.assertEqual(self.entry('s'), 'failed')
        self.assertEqual(self.panels(), ['false true true'] * 3)
        self.assertTrue(any('locked door (no key)' in s for s in self.lk()), self.lk())

    def test_open_garage_door_of_a_home_closed_on_arrival(self):
        self.building()
        self.garage(open=True)
        self.start()
        self.group(member=True)
        self.h.tick(self.o('SHUT_DELAY_MS') // self.h.tick_ms + 3 * self.o('PASS_EVERY') + 1)
        self.assertEqual(self.panels(), ['false true true'] * 3)
        self.assertEqual(self.o('stats.shut'), 1)       # les trois panneaux d'un coup
        self.assertFalse(any('garage door not handled' in s for s in self.lk()), self.lk())
        self.assertEqual(self.o('shutRefusal(DOORS["106,102,0,W"])'), None)

    def test_refused_door_along_the_lane_after_a_fence_is_not_a_refusal(self):
        # lk.traversal du 2026-10-12 (« refused door next to a low fence ») : clôture basse x = 106, porte refusée
        # (double) sur le bord nord de (106, 103), le long de la voie y = 102 ; le corps reste à l'entrée de la case
        # d'en face pendant le clip de l'escalade (CLIMB_LAND_EARLY, 1,6 s).
        self.run_lua('; '.join(f'FENCES["106,{y},0,W"] = true' for y in range(90, 126)))
        self.door(y=103, kind='N', double=True)
        self.run_lua('CLIMB_LAND_EARLY = true; CLIMB_TICKS = 94; CLIMB_RECOVER = 58')   # 1,5 s puis 0,93 s
        self.init()
        self.trip(start=(102, 102), target=(110, 102), ticks=1500, walk='w')
        self.assertEqual(self.entry('s'), 'arrived')
        self.assertEqual(self.climbs('solo'), ['climbfence 106,102,0,W'])
        self.assertIn(self.o('stats.refused'), (None, 0))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerInsideDoorTests(ObstacleBase):
    """LK04-T19 en MP : la porte intérieure du foyer, ouverte de l'intérieur sans sa clé par un membre porteur de la
    clé du foyer, est refermée et reverrouillée par le serveur seul ; les deux clients voient l'état verrouillé."""
    def setUp(self):
        super().setUp()
        SENT.clear()

    def test_server_relocks_the_interior_home_door_and_clients_see_it_locked(self):
        self.building()
        self.wall(x=109, skip=(102,))
        self.door(x=109, locked=True)
        zid = self.npc(x=107, y=102)
        for c in ('A', 'B'):
            srv = self.h.zombie('server', zid)
            self.h.eval(c, f'MIRROR({zid}, {srv.x}, {srv.y}, {srv.z}, "A")')
        self.h.set_owner(zid, 'A')
        for _ in range(2):
            self.slow()
            self.h.pump()
        self.group(member=True)
        self.d('moveTo("lk-1", 111, 102, 0)')
        self.h.pump()
        key = '109,102,0,W'
        states = []

        def check():
            self.assertEqual(self.state('A', key), self.state('server', key))
            self.assertEqual(self.state('B', key), self.state('server', key))
            states.append(self.state('server', key))
        self.walk_d(zid, 900, until=self.done(), check=check)
        self.assertEqual(self.entry('s'), 'arrived')
        self.walk_d(zid, 40, check=check)
        seq = [s for i, s in enumerate(states) if i == 0 or s != states[i - 1]]
        self.assertEqual(seq[-2:], ['true false false', 'false true true'])
        for c in ('A', 'B'):
            self.assertEqual(self.state(c, key), 'false true true')
            self.assertEqual(self.counters(c), (0, 0))             # aucune bascule chez un client
        self.assertEqual({src for src, _ in SENT}, {'server'})
        self.assertEqual(self.o('stats.locked'), 1)


if __name__ == '__main__':
    unittest.main()
