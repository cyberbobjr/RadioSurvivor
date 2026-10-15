"""Tests hors jeu de l'aménagement des foyers Living Knox (LK08-T04) : server/LivingKnox/LK_Homes.lua et la suite en
jeu lk.homes (dev/.../RST_LKHomes.lua) dans le banc.

    python RadioSurvivor/tests/test_lk_homes.py

Banc tests/harness.py (solo, ou serveur dédié + deux clients) avec le vrai registre des groupes (LK_Groups, fichiers
en mémoire). Doublures relevées dans le Java et le Lua vanilla 42.21.0 :
- bâtiments = rectangles BUILDINGS (IsoGridSquare.getBuildingDef / getRoom par la pièce, J/iso/IsoGridSquare.java
  :7805-7816 ; BuildingDef.getIDString, isFullyStreamedIn, getRooms ; RoomDef.isExplored) ;
- cases : isFree(false) = sol sans meuble plein ni arbre (IsoGridSquare.java:2894-2915, doublure blocked recalculée
  d'après les objets solides), HasStairs, isWaterSquare (:9581), hasBush (:2382), getWorldObjects ; zone non chargée à
  partir de UNLOADED_X (getGridSquare rend nil) ;
- fenêtres et portes de bord (getWindowTo / getDoorTo, :3107-3172) : IsoWindow posée sur la case dont le bord N ou W
  est l'ouverture, getOppositeSquare, IsOpen, isBarricaded ; IsoBarricade.AddBarricadeToObject(obj, addOpposite)
  (J/iso/objects/IsoBarricade.java:739-764 : case de l'objet ou case opposée, barricade existante rendue), addPlank,
  getNumPlanks, transmitCompleteItemToClients compté sur le serveur ;
- sprites (newtiledefinitions.tiles.txt) et ISMoveableSpriteProps (M/shared/Moveables/ISMoveableSpriteProps.lua :
  new, isMoveable, isMultiSprite, getSpriteGridInfo :1088-1176 avec l'ancrage décalé de sa position dans la grille,
  instanceItem :215-244, placeMoveableInternal :2075-2560 : objet ajouté, ModData de l'objet d'inventaire recopiée,
  lampe IsoLightSwitch réglée par getCustomSettingsFromItem avec une source de lumière éteinte, transmission sur le
  serveur seulement) ;
- SCampfireSystem.instance (M/server/Camping/SCampfireSystem.lua:62-85 : addCampfire refuse une case qui a un feu,
  addFuel, lightFire sans combustible refusé, getLuaObjectOnSquare, removeCampfire).
Elles NE PROUVENT PAS l'API réelle, seulement la logique : suite en jeu lk.homes.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEV_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
SUITE = DEV_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKHomes.lua'

SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'
MODULE = 'server/LivingKnox/LK_Homes.lua'
HM = 'LivingKnox.Homes'

DOUBLES = r'''
WORLD_NAME, GAME_MODE = 'rstest_homes', 'Multiplayer'
getWorld = function()
    return { getWorld = function() return WORLD_NAME end, getGameMode = function() return GAME_MODE end }
end
local H = HARNESS
local C = H.classes
IsoFlagType = IsoFlagType or {}
IsoFlagType.bed = IsoFlagType.bed or "bed"
COUNT = { transmit = 0, placed = 0, removed = 0, planks = 0 }

-- Bâtiments ----------------------------------------------------------------------------------------------------------
BUILDINGS, STREAMED, EXPLORED = {}, {}, {}
local Def = H.class('BuildingDef')
function Def:getIDString() return tostring(self.id) end
function Def:isFullyStreamedIn() return STREAMED[self.id] ~= false end
local Room = H.class('RoomDef')
function Room:isExplored() return EXPLORED[self.id] == true end
function Def:getRooms() return H.list({ setmetatable({ id = self.id }, Room) }) end
local function buildingAt(x, y)
    for _, b in ipairs(BUILDINGS) do
        if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then return b end
    end
    return nil
end
local Sq = C.IsoGridSquare
function Sq:getBuildingDef()
    local b = buildingAt(self.x, self.y)
    return b and setmetatable({ id = b[5] }, Def) or nil
end
function Sq:getRoom() return buildingAt(self.x, self.y) and { id = 1 } or nil end
function Sq:HasStairs() return self.stairs == true end
function Sq:isWaterSquare() return self.water == true end
function Sq:hasBush() return self.bush == true end
function Sq:getWorldObjects() return rawget(self, 'worldObjects') or H.list() end

-- Objets à sprite ----------------------------------------------------------------------------------------------------
local Props = H.class('PropertyContainer')
function Props:has(flag)
    if flag == IsoFlagType.bed then return self.bed == true end
    if type(flag) ~= 'string' then error('No implementation found for PropertyContainer.has', 2) end
    -- PropertyContainer.has(String) : propriété présente, quelle que soit sa valeur (MoveType, container...).
    local v = rawget(self, flag)
    return v ~= nil and v ~= false
end
function Props:get(name) return rawget(self, name) end
local Sprite = H.class('IsoSprite')
function Sprite:getName() return self.name end
function Sprite:getProperties() return self.props end
SPRITES = {}
local function def(name, props, grid)
    SPRITES[name] = setmetatable({ name = name, props = setmetatable(props, Props), grid = grid }, Sprite)
end
local tentE = { w = 1, h = 2, at = { ['0,0'] = 'camping_01_1', ['0,1'] = 'camping_01_0' } }
local tentS = { w = 2, h = 1, at = { ['0,0'] = 'camping_01_2', ['1,0'] = 'camping_01_3' } }
local bag = { w = 2, h = 1, at = { ['0,0'] = 'camping_02_16', ['1,0'] = 'camping_02_17' } }
def('lighting_indoor_03_4', { IsMoveAble = true, lightswitch = true })
def('carpentry_01_16', { IsMoveAble = true, solidtrans = true, container = 'crate' })
def('camping_02_16', { IsMoveAble = true, bed = true, BedType = 'badBed', customItem = 'Base.SleepingBag_Green' }, bag)
def('camping_02_17', { IsMoveAble = true, bed = true, BedType = 'badBed', customItem = 'Base.SleepingBag_Green' }, bag)
for _, n in ipairs({ 'camping_01_0', 'camping_01_1', 'camping_01_2', 'camping_01_3' }) do
    def(n, { IsMoveAble = true, bed = true, BedType = 'badBed', solidtrans = true,
             customItem = 'Base.CampingTentKit2' }, (n == 'camping_01_0' or n == 'camping_01_1') and tentE or tentS)
end
def('furniture_bedding_01_1', { IsMoveAble = true, bed = true, BedType = 'goodBed', solidtrans = true })
def('chair', { IsMoveAble = true })
-- 42.21 : sols, tapis, rideaux, appliques murales ramassables (IsMoveAble) avec un MoveType autre que "Object".
def('floors_interior_tilesandwood_01_13', { IsMoveAble = true, MoveType = 'FloorTile' })
def('floors_rugs_01_6', { IsMoveAble = true, MoveType = 'FloorRug' })
def('fixtures_windows_curtains_02_29', { IsMoveAble = true, MoveType = 'WindowObject' })
def('lighting_indoor_01_58', { IsMoveAble = true, MoveType = 'WallObject' })
def('table_object', { IsMoveAble = true, MoveType = 'Object' })
getSprite = function(name) return SPRITES[name] end
function C.IsoObject:getSprite() return rawget(self, 'sprite') end
function C.IsoObject:getProperties()
    local s = rawget(self, 'sprite')
    return s and s.props or nil
end
-- Case impraticable : arbre (tree) ou objet plein (solid / solidtrans).
local function refresh(sq)
    local blocked = sq.tree == true
    for _, o in ipairs(sq.objects.items) do
        local p = o.getProperties and o:getProperties()
        if p and (rawget(p, 'solid') or rawget(p, 'solidtrans')) then blocked = true end
    end
    sq.blocked = blocked
end
REFRESH = refresh
function PUT(x, y, name)
    local o = setmetatable({ sprite = SPRITES[name] }, C.IsoObject)
    H.addObject(x, y, 0, o)
    refresh(H.square(x, y, 0))
    return o
end
function TREE(x, y) local sq = H.square(x, y, 0) sq.tree = true refresh(sq) end
function Sq:transmitRemoveItemFromSquare(o)
    if not H.listRemove(self.objects, o) then return -1 end
    COUNT.removed = COUNT.removed + 1
    refresh(self)
    return 0
end
local Cell = getmetatable(getCell())
local get = Cell.getGridSquare
UNLOADED_X = nil
function Cell:getGridSquare(x, y, z)
    if UNLOADED_X ~= nil and x >= UNLOADED_X then return nil end
    return get(self, x, y, z)
end

-- Fenêtres, portes, barricades ---------------------------------------------------------------------------------------
EDGES = {}
local Window = H.class('IsoWindow', C.IsoObject)
local Door = H.class('IsoDoor', C.IsoObject)
local function ekey(x, y, x2, y2) return x .. ',' .. y .. '|' .. x2 .. ',' .. y2 end
-- Ouverture du bord (x, y) - (x2, y2) : objet posé sur la case dont c'est le bord nord ou ouest.
local function edgeObject(cls, x, y, x2, y2, fields)
    local ox, oy, north
    if x2 == x then
        north = true
        oy = math.max(y, y2) ox = x
    else
        north = false
        ox = math.max(x, x2) oy = y
    end
    local o = setmetatable(fields or {}, cls)
    o.north = north
    H.addObject(ox, oy, 0, o)
    o.opposite = north and H.square(ox, oy - 1, 0) or H.square(ox - 1, oy, 0)
    EDGES[ekey(x, y, x2, y2)] = o
    EDGES[ekey(x2, y2, x, y)] = o
    return o
end
function ADD_WINDOW(x, y, x2, y2, open) return edgeObject(Window, x, y, x2, y2, { open = open == true, barr = {} }) end
function ADD_DOOR(x, y, x2, y2) return edgeObject(Door, x, y, x2, y2) end
function Sq:getWindowTo(nb)
    local o = nb and EDGES[ekey(self.x, self.y, nb.x, nb.y)]
    return getmetatable(o) == Window and o or nil
end
function Sq:getDoorTo(nb)
    local o = nb and EDGES[ekey(self.x, self.y, nb.x, nb.y)]
    return getmetatable(o) == Door and o or nil
end
function Window:IsOpen() return self.open end
function Window:getNorth() return self.north end
function Window:getOppositeSquare() return self.opposite end
function Window:getBarricadeOnSameSquare() return self.barr.own end
function Window:getBarricadeOnOppositeSquare() return self.barr.opp end
function Window:isBarricaded()
    for _, b in pairs(self.barr) do
        if b.planks > 0 then return true end
    end
    return false
end
local Barricade = H.class('IsoBarricade', C.IsoObject)
function Barricade:addPlank(chr, plank)
    if select('#', chr, plank) ~= 2 then error('expected addPlank(chr, plank)', 2) end
    if self.planks < 4 then self.planks = self.planks + 1 COUNT.planks = COUNT.planks + 1 end
end
function Barricade:getNumPlanks() return self.planks end
function Barricade:isMetal() return false end
function Barricade:isMetalBar() return false end
function Barricade:transmitCompleteItemToClients()
    if not isServer() then error('transmitCompleteItemToClients called off the server', 2) end
    COUNT.transmit = COUNT.transmit + 1
end
IsoBarricade = {}
function IsoBarricade.AddBarricadeToObject(w, addOpposite)
    if type(addOpposite) ~= 'boolean' then error('No implementation found for AddBarricadeToObject', 2) end
    local side = addOpposite and 'opp' or 'own'
    if w.barr[side] then return w.barr[side] end
    local sq = addOpposite and w.opposite or w.square
    local b = setmetatable({ planks = 0, side = side }, Barricade)
    H.addObject(sq.x, sq.y, sq.z, b)
    w.barr[side] = b
    return b
end

-- Objets d'inventaire et pose des meubles --------------------------------------------------------------------------
local Item = H.class('InventoryItem')
local Moveable = H.class('Moveable', Item)
function Item:getModData() local md = rawget(self, 'md') if not md then md = {} self.md = md end return md end
function Moveable:setLightUseBattery(v) self.useBattery = v end
function Moveable:setLightHasBattery(v) self.hasBattery = v end
function Moveable:setLightPower(v) self.power = v end
local Light = H.class('IsoLightSwitch', C.IsoObject)
function Light:getUseBattery() return self.useBattery == true end
function Light:getHasBattery() return self.hasBattery == true end
function Light:getPower() return self.power or 0 end
function Light:isActivated() return self.activated == true end
function Light:switchLight(on) self.sourceActive = on end
ISMoveableSpriteProps = {}
local PropsMeta = { __index = ISMoveableSpriteProps }
function ISMoveableSpriteProps.new(sprite)
    if type(sprite) == 'string' then sprite = getSprite(sprite) end
    local s = setmetatable({}, PropsMeta)
    if sprite == nil then return s end
    s.sprite, s.spriteName = sprite, sprite.name
    s.isMoveable = sprite.props.IsMoveAble == true
    s.customItem = sprite.props.customItem
    s.isMultiSprite = sprite.grid ~= nil
    return s
end
function ISMoveableSpriteProps:getSpriteGridInfo(sq, getWorld)
    local g = self.sprite.grid
    local px, py
    for k, n in pairs(g.at) do
        if n == self.spriteName then
            local a, b = string.match(k, '(%d+),(%d+)')
            px, py = tonumber(a), tonumber(b)
        end
    end
    local out = {}
    for x = 0, g.w - 1 do
        for y = 0, g.h - 1 do
            out[#out + 1] = { square = getCell():getGridSquare(sq.x - px + x, sq.y - py + y, sq.z),
                              sprite = getSprite(g.at[x .. ',' .. y]), x = x, y = y }
        end
    end
    return out
end
function ISMoveableSpriteProps:instanceItem(name)
    if not self.isMoveable then return nil end
    local it = setmetatable({ type = self.customItem or ('Moveables.' .. self.spriteName), worldSprite = name }, Moveable)
    return it
end
function ISMoveableSpriteProps:placeMoveableInternal(chr, sq, item, name)
    if chr ~= nil then error('character given', 2) end
    local spr = getSprite(name)
    local o
    if spr.props.lightswitch then
        -- addLightSourceFromSprite avant getCustomSettingsFromItem : source éteinte (IsoLightSwitch.java:104-116).
        o = setmetatable({ sprite = spr, activated = true, sourceActive = false, useBattery = item.useBattery,
                           hasBattery = item.hasBattery, power = item.power }, Light)
    else
        o = setmetatable({ sprite = spr }, C.IsoObject)
    end
    if spr.props.container then o.container = { type = spr.props.container } end
    for k, v in pairs(item:getModData()) do o:getModData()[k] = v end
    H.addObject(sq.x, sq.y, sq.z, o)
    refresh(sq)
    COUNT.placed = COUNT.placed + 1
    if isServer() then COUNT.transmit = COUNT.transmit + 1 end
end

-- Feux de camp (système global serveur) ----------------------------------------------------------------------------
local Fires = {}
SCampfireSystem = { instance = { fires = Fires } }
local function fkey(sq) return sq.x .. ',' .. sq.y .. ',' .. sq.z end
function SCampfireSystem.instance:addCampfire(sq)
    if Fires[fkey(sq)] then return nil end
    local o = H.addObject(sq.x, sq.y, sq.z, setmetatable({}, C.IsoObject))
    local lo = { fuelAmt = 0, isLit = false, square = sq, obj = o }
    function lo:addFuel(n) self.fuelAmt = self.fuelAmt + n end
    function lo:lightFire() if self.isLit or self.fuelAmt <= 0 then return end self.isLit = true end
    function lo:getIsoObject() return self.obj end
    Fires[fkey(sq)] = lo
    return lo
end
function SCampfireSystem.instance:getLuaObjectOnSquare(sq) return Fires[fkey(sq)] end
function SCampfireSystem.instance:removeCampfire(lo)
    if not lo then return end
    H.listRemove(lo.square.objects, lo.obj)
    Fires[fkey(lo.square)] = nil
end
FIRES = Fires

-- Aides des tests ----------------------------------------------------------------------------------------------------
function TAGGED(gid)
    local out = {}
    for y = 60, 260 do
        for x = 60, 260 do
            local sq = getCell():getGridSquare(x, y, 0)
            if sq then
                for _, o in ipairs(sq.objects.items) do
                    if o:hasModData() and o:getModData().LKHome == gid then
                        out[#out + 1] = { x = x, y = y, kind = o:getModData().LKHomeKind,
                                          sprite = o.sprite and o.sprite.name or 'barricade', o = o }
                    end
                end
            end
        end
    end
    return out
end
'''

# Maison de test : bâtiment 100..110 x 100..108 (id 7), porte à l'ouest, fenêtres nord (101 et 106), est (y 104),
# sud ouverte (104), un lit double existant (106,107)-(107,107).
HOUSE = r'''
BUILDINGS = { { 100, 100, 110, 108, 7 } }
ADD_DOOR(100, 104, 99, 104)
WIN_N1 = ADD_WINDOW(101, 100, 101, 99)
WIN_N2 = ADD_WINDOW(106, 100, 106, 99)
WIN_E = ADD_WINDOW(110, 104, 111, 104)
WIN_S = ADD_WINDOW(104, 108, 104, 109, true)
PUT(106, 107, 'furniture_bedding_01_1')
PUT(107, 107, 'furniture_bedding_01_1')
PUT(103, 101, 'chair')
'''


class Base(unittest.TestCase):
    mode = 'solo'

    def setUp(self):
        self.h = Harness(mode=self.mode, lua_roots=[DEV_LUA])
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            self.h.load(m, DOUBLES)
            for path in SHARED:
                self.h.load(m, path)
            self.h.load(m, SERVER)
            self.h.load(m, MODULE)
        self.h.fire(self.srv, 'OnInitGlobalModData', False)

    def tearDown(self):
        self.h.close()

    def ev(self, code, m=None):
        return self.h.eval(m or self.srv, code)

    def run_lua(self, code, m=None):
        return self.h.load(m or self.srv, code)

    def lk(self):
        return [line for line in self.h.logs(self.srv) if line.startswith('[LivingKnox]')]

    def group(self, gtype='settlers', home=(103, 104, 0), members=4, name='Mill'):
        roles = ['worker', 'fighter', 'medic', 'scout', 'worker', 'fighter', 'deputy', 'worker']
        code = (f'local G = LivingKnox.Groups local g = assert(G.create({{ type = "{gtype}", name = "{name}", day = 1, '
                f'home = {{ x = {home[0]}, y = {home[1]}, z = {home[2]} }} }})) ')
        for i in range(members):
            code += f'assert(G.addMember(g.id, {{ role = "{roles[i]}", day = 1 }})) '
        return self.run_lua(code + 'return g.id')

    def tagged(self, gid):
        t = self.ev(f'TAGGED("{gid}")')
        return [(e.x, e.y, e.kind, e.sprite) for e in t.values()]

    def mark(self, gid):
        return self.ev(f'LivingKnox.Groups.get("{gid}").furnish')

    def placed_kinds(self, gid):
        m = self.mark(gid)
        out = {}
        for p in m.placed.values():
            out[p.k] = out.get(p.k, 0) + 1
        return out

    def scan(self, reason='minute'):
        self.h.advance_ms(20000)
        return self.ev(f'{HM}.scan("{reason}")')


class PureTests(Base):
    def test_valid_mark(self):
        home = '{ x = 5, y = 6, z = 0 }'
        ok = (f'{HM}.validMark({{ v = 1, hx = 5, hy = 6, hz = 0, style = "camp", state = "done", '
              f'placed = {{ {{ k = "tent", x = 1, y = 2, z = 0 }} }} }}, {home})')
        self.assertTrue(self.ev(f'({ok})'))
        for bad in ('nil', '{}', '{ v = 2, hx = 5, hy = 6, hz = 0, style = "camp", state = "done" }',
                    '{ v = 1, hx = 5, hy = 7, hz = 0, style = "camp", state = "done" }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, style = "tower", state = "done" }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, style = "camp", state = "maybe" }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, style = "camp", state = "done", placed = { { k = "gun", x = 1, y = 1, z = 0 } } }',
                    '{ v = 1, hx = 5, hy = 6, hz = 0, style = "camp", state = "done", placed = { { k = "tent", x = 1.5, y = 1, z = 0 } } }'):
            with self.subTest(bad=bad):
                self.assertFalse(self.ev(f'({HM}.validMark({bad}, {home}))'))

    def test_clear_square_rules(self):
        self.run_lua('TREE(50, 50) local s = getCell():getGridSquare(51, 50, 0) s.water = true '
                     'getCell():getGridSquare(52, 50, 0).bush = true getCell():getGridSquare(53, 50, 0).stairs = true '
                     'PUT(54, 50, "chair") getCell():getGridSquare(55, 50, 0).worldObjects = HARNESS.list({ {} })')
        got = [self.ev(f'{HM}.clearSquare(getCell():getGridSquare({x}, 50, 0))') for x in range(50, 57)]
        self.assertEqual(got, [False, False, False, False, False, False, True])

    def test_pickable_floor_rug_curtain_and_wall_lamp_do_not_occupy_a_square(self):
        # Constaté en jeu le 2026-10-12 : en 42.21 le parquet, les tapis, les rideaux et les appliques portent
        # IsMoveAble ; toute la maison paraissait occupée (ni lampe, ni couchage, ni caisse).
        self.run_lua('PUT(60, 50, "floors_interior_tilesandwood_01_13") PUT(60, 50, "floors_rugs_01_6") '
                     'PUT(60, 50, "fixtures_windows_curtains_02_29") PUT(60, 50, "lighting_indoor_01_58") '
                     'PUT(61, 50, "floors_interior_tilesandwood_01_13") PUT(61, 50, "table_object")')
        self.assertTrue(self.ev(f'{HM}.clearSquare(getCell():getGridSquare(60, 50, 0))'))
        self.assertFalse(self.ev(f'{HM}.clearSquare(getCell():getGridSquare(61, 50, 0))'))

    def test_not_loaded_on_an_mp_client_module_absent(self):
        # Le fichier commence par « if isClient() then return end » : vérifié dans MultiplayerTests.
        self.assertIsNotNone(self.ev(HM))


class BuildingTests(Base):
    def setUp(self):
        super().setUp()
        self.run_lua(HOUSE)

    def test_building_is_furnished_once_with_vanilla_objects(self):
        gid = self.group()
        self.assertEqual(self.scan('chunk'), 1)
        m = self.mark(gid)
        self.assertEqual((m.state, m.style, m.hx, m.hy, m.hz, m.v), ('done', 'building', 103, 104, 0, 1))
        self.assertEqual(self.placed_kinds(gid), {'barricade': 2, 'lamp': 1, 'bed': 3, 'crate': 1})
        # Fenêtres les plus éloignées du foyer, fermées : est (110,104) et nord (106,100) ; côté extérieur.
        self.assertEqual(self.ev('WIN_E.barr.own and WIN_E.barr.own.planks'), 2)
        self.assertIsNone(self.ev('WIN_E.barr.opp'))
        # Nord : à égalité d'écart (4), la plus au nord-ouest d'abord (101) ; posée sur la case extérieure (101,99).
        self.assertEqual(self.ev('WIN_N1.barr.opp and WIN_N1.barr.opp.planks'), 2)
        self.assertIsNone(self.ev('WIN_N1.barr.own'))
        self.assertEqual(self.ev('WIN_E.barr.own.square.x'), 111)
        self.assertEqual(self.ev('WIN_N1.barr.opp.square.y'), 99)
        self.assertFalse(self.ev('WIN_N2:isBarricaded()'))
        self.assertFalse(self.ev('WIN_S:isBarricaded()'))   # ouverte : laissée
        tagged = self.tagged(gid)
        sprites = sorted(t[3] for t in tagged)
        self.assertEqual(sprites, sorted(['barricade', 'barricade', 'lighting_indoor_03_4', 'carpentry_01_16']
                                         + ['camping_02_16', 'camping_02_17'] * 3))
        # Lampe sur pile, allumée.
        lamp = self.run_lua('for _, t in ipairs(TAGGED("%s")) do if t.kind == "lamp" then '
                            'return t.o:getUseBattery(), t.o:getHasBattery(), t.o:getPower(), t.o:isActivated(), '
                            't.o.sourceActive, t.x, t.y end end' % gid)
        self.assertEqual(lamp[:5], (True, True, 1.0, True, True))
        # Rien sur la case du foyer ni autour, ni contre une porte ou une fenêtre ; meubles dans le bâtiment.
        for x, y, kind, _ in tagged:
            if kind == 'barricade':
                continue
            self.assertTrue(100 <= x <= 110 and 100 <= y <= 108, (x, y, kind))
            self.assertGreater(max(abs(x - 103), abs(y - 104)), 1, (x, y, kind))
            self.assertNotIn((x, y), [(100, 104), (101, 100), (106, 100), (110, 104), (104, 108)], kind)
        # Sacs de couchage : les deux cases voisines en x.
        beds = sorted((x, y) for x, y, k, s in tagged if s == 'camping_02_16')
        for x, y in beds:
            self.assertIn((x + 1, y, 'bed', 'camping_02_17'), tagged)
        self.assertEqual(self.ev('COUNT.transmit'), 0)   # solo : rien à transmettre
        self.assertTrue(any('homes: group grp-1 home 103,104,0 furnished (building, 4 member(s)): 2 barricade, '
                            '1 lamp, 3 bed, 1 crate' in line for line in self.lk()), self.lk())
        # Nouveaux chargements et minutes : rien de plus.
        before = len(tagged)
        for _ in range(3):
            self.scan('chunk')
            self.h.advance(2)
        self.assertEqual(len(self.tagged(gid)), before)
        self.assertEqual(self.ev('COUNT.placed'), 8)   # cases de meubles : lampe, 3 sacs de 2 cases, caisse

    def test_generators_of_the_building_become_the_group_s_once(self):
        """LK05-T19 : a l'amenagement, generateur du batiment sans marque = celui du groupe ; hors du batiment, deja
        marque par un autre groupe, ou pose apres l'amenagement (celui d'un joueur) : jamais marque."""
        self.run_lua('local Gen = HARNESS.class("IsoGenerator", HARNESS.classes.IsoObject) '
                     'IN_GEN = HARNESS.addObject(109, 102, 0, setmetatable({}, Gen)) '
                     'OUT_GEN = HARNESS.addObject(112, 104, 0, setmetatable({}, Gen)) '
                     'OTHER_GEN = HARNESS.addObject(109, 106, 0, setmetatable({}, Gen)) '
                     'OTHER_GEN:getModData().LKGenerator = "grp-other" GEN_CLASS = Gen')
        gid = self.group()
        self.assertEqual(self.scan('chunk'), 1)
        self.assertTrue(self.ev(f'{HM}.groupGenerator(IN_GEN, "{gid}")'))
        self.assertFalse(self.ev('OUT_GEN:hasModData()'))
        self.assertEqual(self.ev('OTHER_GEN:getModData().LKGenerator'), 'grp-other')
        self.assertTrue(any(f'homes: group {gid} home 103,104,0: 1 generator(s) of the building marked' in line
                            for line in self.lk()), self.lk())
        self.assertEqual(self.mark(gid).state, 'done')
        # Pose apres coup (generateur d'un joueur) : plus aucun marquage, meme apres un redemarrage.
        self.run_lua('LATE_GEN = HARNESS.addObject(108, 101, 0, setmetatable({}, GEN_CLASS))')
        self.run_lua(f'{HM}.reset() LivingKnox.Groups.state.data = nil')
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        for _ in range(3):
            self.scan('chunk')
            self.h.advance(2)
        self.assertFalse(self.ev('LATE_GEN:hasModData()'))

    def test_existing_beds_are_counted(self):
        gid = self.group(members=2)
        self.scan()
        self.assertEqual(self.placed_kinds(gid).get('bed'), 1)   # 2 membres, 1 lit déjà là

    def test_restart_does_not_furnish_again(self):
        gid = self.group()
        self.scan()
        n = len(self.tagged(gid))
        # Redémarrage : mémoire perdue, registre relu du fichier.
        self.run_lua(f'{HM}.reset() LivingKnox.Groups.state.data = nil')
        self.h.fire(self.srv, 'OnInitGlobalModData', False)
        self.assertEqual(self.mark(gid).state, 'done')
        self.scan('chunk')
        self.h.advance(3)
        self.assertEqual(len(self.tagged(gid)), n)
        self.assertEqual(self.ev(f'{HM}.check("{gid}", {{ force = true }})'), 'done')

    def test_interrupted_placing_mark_is_never_redone(self):
        gid = self.group()
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].furnish = {{ v = 1, hx = 103, '
                     f'hy = 104, hz = 0, style = "building", day = 1, state = "placing", placed = {{}} }} '
                     f'return true end))')
        self.assertEqual(self.scan(), 0)   # marque valide : le foyer n'est pas en attente
        self.assertEqual(self.ev(f'({HM}.check("{gid}", {{ force = true }}))'), 'done')
        self.assertEqual(self.tagged(gid), [])
        self.assertTrue(any('left half furnished' in line for line in self.lk()))

    def test_lost_mark_is_restored_from_the_tagged_objects(self):
        gid = self.group()
        self.scan()
        n = len(self.tagged(gid))
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].furnish = nil return true end)) '
                     f'{HM}.reset()')
        self.scan()
        self.assertEqual(len(self.tagged(gid)), n)
        m = self.mark(gid)
        self.assertEqual(m.state, 'done')
        self.assertEqual(len(m.placed), n)
        self.assertTrue(any('but no mark: mark restored' in line for line in self.lk()))

    def test_waits_for_the_loaded_area_and_the_building_story(self):
        gid = self.group()
        self.run_lua('UNLOADED_X = 105')
        self.assertEqual(self.scan(), 0)
        self.assertIsNone(self.mark(gid))
        self.run_lua('UNLOADED_X = 200 STREAMED[7] = false')
        self.assertEqual(self.scan(), 0)
        self.assertIsNone(self.ev(f'({HM}.check("{gid}", {{ force = true }}))'))
        self.assertEqual(self.run_lua(f'return select(2, {HM}.check("{gid}", {{ force = true }}))'),
                         'building not fully streamed in')
        self.run_lua('EXPLORED[7] = true')
        # Essai trop tôt : attente RETRY_MS.
        self.assertEqual(self.run_lua(f'return select(2, {HM}.check("{gid}"))'), 'retry later')
        self.assertEqual(self.scan(), 1)
        self.assertEqual(self.mark(gid).state, 'done')

    def test_home_moved_furnishes_the_new_home_and_keeps_the_old(self):
        gid = self.group()
        self.scan()
        old = len(self.tagged(gid))
        self.run_lua(f'assert(LivingKnox.Groups.setHome("{gid}", 180, 180, 0))')
        self.scan()
        m = self.mark(gid)
        self.assertEqual((m.hx, m.hy, m.style), (180, 180, 'camp'))
        self.assertGreater(len(self.tagged(gid)), old)

    def test_clear_removes_everything_placed(self):
        gid = self.group()
        self.scan()
        self.assertGreater(len(self.tagged(gid)), 0)
        n = self.ev(f'{HM}.clear("{gid}")')
        self.assertEqual(n, 8 + 2)
        self.assertEqual(self.tagged(gid), [])
        self.assertIsNone(self.mark(gid))

    def test_barricade_mark_is_on_the_window_and_survives_a_restart(self):
        # IsoBarricade.save n'écrit pas la ModData : la marque est sur la fenêtre (sauvegardée), côté noté.
        gid = self.group()
        self.scan()
        self.assertFalse(self.ev('WIN_E.barr.own:hasModData() and WIN_E.barr.own:getModData().LKHome ~= nil'))
        self.assertEqual(self.ev('WIN_E:getModData().LKHome'), gid)
        self.assertEqual(self.ev('WIN_E:getModData().LKHomeSide'), 'same')
        self.assertEqual(self.ev('WIN_N1:getModData().LKHomeSide'), 'opposite')
        # Redémarrage : ModData des barricades vidée ; marques des fenêtres gardées.
        self.run_lua('WIN_E.barr.own.__modData = nil WIN_N1.barr.opp.__modData = nil')
        self.assertEqual(sum(1 for t in self.tagged(gid) if t[2] == 'barricade'), 2)
        self.assertEqual(self.ev(f'{HM}.clear("{gid}")'), 8 + 2)
        on_square = ('local b = %s; for _, o in ipairs(b.square.objects.items) do if o == b then return true end end '
                     'return false')
        self.assertFalse(self.run_lua(on_square % 'WIN_E.barr.own'))
        self.assertFalse(self.run_lua(on_square % 'WIN_N1.barr.opp'))
        self.assertIsNone(self.ev('WIN_E:getModData().LKHome'))
        self.assertIsNone(self.ev('WIN_N1:getModData().LKHomeSide'))
        self.assertEqual(self.tagged(gid), [])

    def test_disabled_engine_does_nothing(self):
        gid = self.group()
        self.run_lua('SandboxVars = { LivingKnox = { Enabled = false } }')
        self.assertEqual(self.scan(), 0)
        self.assertIsNone(self.mark(gid))

    def test_routines_survey_is_redone(self):
        gid = self.group()
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].posts = {{ v = 1 }} return true end))')
        self.scan()
        self.assertIsNone(self.ev(f'LivingKnox.Groups.get("{gid}").posts'))


class CampTests(Base):
    def test_camp_gets_a_lit_fire_and_tents(self):
        self.run_lua('TREE(200, 200) TREE(203, 200) TREE(200, 197)')
        gid = self.group('raiders', home=(200, 200, 0), members=5, name='Crows')
        self.assertEqual(self.scan(), 1)
        m = self.mark(gid)
        self.assertEqual((m.style, m.state), ('camp', 'done'))
        self.assertEqual(self.placed_kinds(gid), {'fire': 1, 'tent': 3})
        fire = [p for p in m.placed.values() if p.k == 'fire'][0]
        self.assertNotEqual((fire.x, fire.y), (200, 200))   # arbre sur la case du foyer
        self.assertLessEqual(max(abs(fire.x - 200), abs(fire.y - 200)), 2)
        lo = self.ev(f'FIRES["{fire.x},{fire.y},0"]')
        self.assertEqual((lo.isLit, lo.fuelAmt), (True, 120))
        tagged = self.tagged(gid)
        self.assertEqual([(x, y) for x, y, kind, _ in tagged if kind == 'fire'], [(fire.x, fire.y)])   # feu marqué
        tents = [e for e in tagged if e[2] != 'fire']
        self.assertEqual(len(tents), 6)   # 3 tentes de deux cases
        for x, y, kind, sprite in tents:
            self.assertEqual(kind, 'tent')
            self.assertNotIn((x, y), [(200, 200), (203, 200), (200, 197)])
        self.assertTrue(any('furnished (camp, 5 member(s)): 1 fire, 3 tent' in line for line in self.lk()), self.lk())
        # Le feu de camp est retiré par clear.
        self.assertEqual(self.ev(f'{HM}.clear("{gid}")'), 7)
        self.assertIsNone(self.ev(f'FIRES["{fire.x},{fire.y},0"]'))

    def test_campfire_removed_after_a_lost_mark(self):
        # Constaté en jeu le 2026-10-12 : marque perdue puis rétablie d'après les objets marqués, le feu (alors sans
        # marque) n'était plus dans la liste et restait après clear ; un feu resté bloque le camp suivant.
        gid = self.group('raiders', home=(200, 200, 0), members=2, name='Crows')
        self.assertEqual(self.scan(), 1)
        fire = [p for p in self.mark(gid).placed.values() if p.k == 'fire'][0]
        self.run_lua(f'assert(LivingKnox.Groups.update(function(d) d.groups["{gid}"].furnish = nil return true, true end)) '
                     f'{HM}.reset()')
        restored = self.ev(f'{HM}.check("{gid}", {{ force = true }})')
        self.assertEqual(restored.state, 'done')
        self.assertIn('fire', [p.k for p in self.mark(gid).placed.values()])
        self.ev(f'{HM}.clear("{gid}")')
        self.assertIsNone(self.ev(f'FIRES["{fire.x},{fire.y},0"]'))

    def test_existing_campfire_is_not_doubled(self):
        gid = self.group('raiders', home=(200, 200, 0), members=2, name='Crows')
        self.run_lua('SCampfireSystem.instance:addCampfire(getCell():getGridSquare(200, 200, 0))')
        self.scan()
        kinds = self.placed_kinds(gid)
        self.assertEqual(kinds.get('tent'), 1)
        fire = [p for p in self.mark(gid).placed.values() if p.k == 'fire']
        self.assertTrue(all((p.x, p.y) != (200, 200) for p in fire))


class MultiplayerTests(Base):
    mode = 'mp'

    def test_server_transmits_every_object_and_clients_have_no_module(self):
        self.run_lua(HOUSE)
        gid = self.group()
        self.assertEqual(self.scan(), 1)
        # 8 cases de meubles + 2 barricades, chacune transmise une fois.
        self.assertEqual(self.ev('COUNT.transmit'), 10)
        self.assertEqual(len(self.tagged(gid)), 10)
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, HM))


class SuiteTests(Base):
    """La suite en jeu lk.homes passe dans le banc (joueur debout dans la maison de test)."""

    def run_suite(self):
        self.run_lua(HOUSE)
        self.run_lua('require "RST/RST"')
        self.h.load(self.srv, 'shared/RST/suites/RST_LKHomes.lua')
        self.run_lua('local p = setmetatable({ x = 103, y = 104, z = 0 }, HARNESS.classes.IsoPlayer) '
                     'p.square = getCell():getGridSquare(103, 104, 0) PLAYER = p')
        self.assertTrue(self.ev('RST.start({ suite = "lk.homes", tags = "world" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(400):
            if not self.ev('RST.step()'):
                break
            self.h.advance_ms(100)
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_cleans_up(self):
        report, results = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 2)
        self.assertEqual(self.ev('#TAGGED("grp-1") + #TAGGED("grp-2")'), 0)
        self.assertEqual(len(list(self.ev('LivingKnox.Groups.list()').values())), 0)

    def test_suite_detects_a_duplicate(self):
        # Garde retirée : la marque perdue fait reposer les objets, la suite doit échouer.
        self.run_lua(f'{HM}.findTagged = function() return {{}} end')
        _, results = self.run_suite()
        self.assertEqual(results['building home furnished once with vanilla objects, no duplicate'][0], 'FAIL')


if __name__ == '__main__':
    unittest.main()
