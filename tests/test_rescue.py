"""Choix du bâtiment de secours (E12-T01) : RS_Rescue.lua et la suite en jeu rs.rescue.pick dans lupa.

    python RadioSurvivor/tests/test_rescue.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) et vrai moteur RST, avec des doublures fidèles de la
métagrille 42.21 : IsoMetaGrid (getBuildings, isValidSquare, getCellData, getZonesAt, getBuildingAt(x, y, z) par les
pièces, getBuildingAt(x, y) et getBuildingsIntersecting comptés comme appels lents), IsoMetaCell
(getBuildingsIntersecting sans doublon, comme IsoMetaChunk), BuildingDef (getRooms, emprise à fin exclusive,
getArea, niveaux, isBasement = première pièce sous 0, isUserDefined, getIDString, isFullyStreamedIn), RoomDef et
RoomRect, SafeHouse, joueurs (solo et serveur), ArrayList, getLotDirectories, Events.LoadChunk.
Toute lecture de case (getCell, getGridSquare, getChunk) pendant un choix est comptée : le choix doit n'en faire
aucune. Couvre : bâtiment habitable par ses pièces, refus (joueur, refuge, point évité, construction de joueur,
sous-sol, trop petit, eau, hors carte, déjà pris), essais bornés, graine reproductible, indices sans chiffres
(type, taille, étages, sous-sol, repères et directions, rue habitée ou isolée, ville seulement sur la carte vanilla),
client MP sans module, et la suite rs.rescue.pick (succès, puis détection d'un choix trop proche ou qui charge).
Ne prouve pas l'API Java réelle : suite en jeu rs.rescue.pick (docs/rescue.md).
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
MOD_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
MODULE = MOD_LUA / 'server' / 'RadioSurvivor' / 'RS_Rescue.lua'
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RS_Rescue.lua'

DOUBLES = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
SIDE = "solo"
isServer = function() return SIDE == "server" end
isClient = function() return SIDE == "client" end
COUNT = { get = 0, cell = 0, square = 0, slow = 0 }

function JList(items)
    local l = { items = items or {} }
    function l:size() return #self.items end
    function l:get(i)
        local v = self.items[i + 1]
        if v == nil then error("IndexOutOfBoundsException " .. tostring(i)) end
        return v
    end
    function l:add(v) self.items[#self.items + 1] = v return true end
    function l:contains(v) for _, x in ipairs(self.items) do if x == v then return true end end return false end
    return l
end
ArrayList = { new = function() return JList({}) end }

local function rect(x, y, w, h)
    return { getX = function() return x end, getY = function() return y end,
             getX2 = function() return x + w end, getY2 = function() return y + h end, x = x, y = y, w = w, h = h }
end

-- Room("bedroom", x, y, w, h, z)
function Room(name, x, y, w, h, z)
    local r = { name = name, z = z or 0, rects = JList({ rect(x, y, w, h) }) }
    function r:getName() return self.name end
    function r:getZ() return self.z end
    function r:getArea() local a = 0 for _, q in ipairs(self.rects.items) do a = a + q.w * q.h end return a end
    function r:getRects() return self.rects end
    return r
end

BUILDINGS = {}
NEXT_ID = 1000
-- Building({ rooms }, { userDefined = true })
function Building(rooms, opts)
    opts = opts or {}
    NEXT_ID = NEXT_ID + 1
    local b = { id = NEXT_ID, rooms = JList(rooms), userDefined = opts.userDefined == true }
    local x1, y1, x2, y2 = 1e9, 1e9, -1e9, -1e9
    for _, r in ipairs(rooms) do
        for _, q in ipairs(r.rects.items) do
            x1, y1 = math.min(x1, q.x), math.min(y1, q.y)
            x2, y2 = math.max(x2, q.x + q.w), math.max(y2, q.y + q.h)
        end
    end
    b.x1, b.y1, b.x2, b.y2 = x1, y1, x2, y2
    function b:getRooms() return self.rooms end
    function b:getX() return self.x1 end
    function b:getY() return self.y1 end
    function b:getX2() return self.x2 end
    function b:getY2() return self.y2 end
    function b:getArea() local a = 0 for _, r in ipairs(self.rooms.items) do a = a + r:getArea() end return a end
    function b:getMinLevel() local m = 100 for _, r in ipairs(self.rooms.items) do m = math.min(m, r.z) end return m end
    function b:getMaxLevel() local m = -100 for _, r in ipairs(self.rooms.items) do m = math.max(m, r.z) end return m end
    function b:isBasement() return #self.rooms.items > 0 and self.rooms.items[1].z < 0 end
    function b:isUserDefined() return self.userDefined end
    function b:getIDString() return tostring(self.id) end
    function b:isFullyStreamedIn() return STREAMED[self.id] == true end
    BUILDINGS[#BUILDINGS + 1] = b
    return b
end
STREAMED = {}

local function intersects(b, x, y, w, h)
    return b.x1 < x + w and x < b.x2 and b.y1 < y + h and y < b.y2
end

MAP_W, MAP_H = 16384, 16384
MISSING_CELLS = {}
ZONES = {}
local CELLS = {}
local function metaCell(cx, cy)
    local key = cx .. "," .. cy
    if CELLS[key] then return CELLS[key] end
    local c = { cx = cx, cy = cy }
    -- IsoMetaCell:getBuildingsIntersecting: buildings of this cell's chunks crossing the rectangle, no duplicate.
    function c:getBuildingsIntersecting(x, y, w, h, result)
        local cx1, cy1 = self.cx * 256, self.cy * 256
        local ix1, iy1 = math.max(x, cx1), math.max(y, cy1)
        local ix2, iy2 = math.min(x + w, cx1 + 256), math.min(y + h, cy1 + 256)
        if ix1 >= ix2 or iy1 >= iy2 then return end
        for _, b in ipairs(BUILDINGS) do
            if intersects(b, ix1, iy1, ix2 - ix1, iy2 - iy1) and not result:contains(b) then result:add(b) end
        end
    end
    CELLS[key] = c
    return c
end

GRID = {}
function GRID:getBuildings() return BUILDING_LIST end
function GRID:isValidSquare(x, y) return x >= 0 and y >= 0 and x < MAP_W and y < MAP_H end
function GRID:getCellData(cx, cy)
    if cx < 0 or cy < 0 or cx * 256 >= MAP_W or cy * 256 >= MAP_H or MISSING_CELLS[cx .. "," .. cy] then return nil end
    return metaCell(cx, cy)
end
function GRID:getZonesAt(x, y, z)
    local out = {}
    for _, zn in ipairs(ZONES) do
        if x >= zn.x and x < zn.x + zn.w and y >= zn.y and y < zn.y + zn.h then
            out[#out + 1] = { getType = function() return zn.type end }
        end
    end
    return JList(out)
end
function GRID:getBuildingAt(x, y, z)
    if z == nil then COUNT.slow = COUNT.slow + 1 end -- (x, y): loop over every building of the map
    for _, b in ipairs(BUILDINGS) do
        for _, r in ipairs(b.rooms.items) do
            for _, q in ipairs(r.rects.items) do
                if (z == nil or r.z == z) and x >= q.x and x < q.x + q.w and y >= q.y and y < q.y + q.h then return b end
            end
        end
    end
    return nil
end
function GRID:getBuildingsIntersecting() COUNT.slow = COUNT.slow + 1 end
function GRID:getRoomsIntersecting() COUNT.slow = COUNT.slow + 1 end

function finalize()
    -- getBuildings() hands out a counting view of the Java list.
    local inner = JList(BUILDINGS)
    BUILDING_LIST = { size = function() return inner:size() end,
                      get = function(_, i) COUNT.get = COUNT.get + 1 return inner:get(i) end }
end
finalize()
getWorld = function() return { getMetaGrid = function() return GRID end, getWorld = function() return "rstest-solo" end } end

-- Squares: readable only in the chunks around the players (LOADED); every read is counted.
LOADED_HALF = 12
local function loadedChunk(wx, wy)
    for _, p in ipairs(PLAYERS) do
        local pwx, pwy = math.floor(p.x / 8), math.floor(p.y / 8)
        if math.abs(wx - pwx) <= LOADED_HALF and math.abs(wy - pwy) <= LOADED_HALF then return true end
    end
    return false
end
CELL = {}
function CELL:getGridSquare(x, y, z)
    COUNT.square = COUNT.square + 1
    if loadedChunk(math.floor(x / 8), math.floor(y / 8)) then return { getX = function() return x end } end
    return nil
end
function CELL:getChunk() COUNT.square = COUNT.square + 1 end
getCell = function() COUNT.cell = COUNT.cell + 1 return CELL end

PLAYERS = {}
function Player(x, y)
    local p = { x = x, y = y }
    function p:getX() return self.x + 0.5 end
    function p:getY() return self.y + 0.5 end
    PLAYERS[#PLAYERS + 1] = p
    return p
end
getNumActivePlayers = function() return #PLAYERS end
getSpecificPlayer = function(i) return PLAYERS[i + 1] end
getOnlinePlayers = function() return JList(PLAYERS) end

SAFEHOUSES = {}
SafeHouse = { getSafehouseList = function()
    local out = {}
    for _, s in ipairs(SAFEHOUSES) do
        out[#out + 1] = { getX = function() return s.x end, getY = function() return s.y end,
                          getW = function() return s.w end, getH = function() return s.h end }
    end
    return JList(out)
end }

LOT_DIRS = { "Muldraugh, KY" }
getLotDirectories = function() return JList(LOT_DIRS) end

math.randomseed(7)
ZombRand = function(n) return math.random(0, n - 1) end

Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    e.Remove = function(f) for i = #e.list, 1, -1 do if e.list[i] == f then table.remove(e.list, i) end end end
    rawset(t, k, e) return e end })
function fire(name, ...) for _, f in ipairs(Events[name].list) do f(...) end end
function fakeChunk(x, y)
    return { getGridSquare = function(_, cx, cy, cz)
        return { getX = function() return x + cx end, getY = function() return y + cy end } end }
end
"""

# Carte de test : joueur en (100, 100) ; ville fictive au loin ; Muldraugh sur ses coordonnées vanilla.
WORLD = r"""
PLAYER = Player(100, 100)
function House(x, y, extra, z)
    local rooms = { Room("bedroom", x, y, 4, 4, z or 0), Room("kitchen", x + 4, y, 4, 4, z or 0),
                    Room("livingroom", x, y + 4, 8, 4, z or 0) }
    for _, r in ipairs(extra or {}) do rooms[#rooms + 1] = r end
    return Building(rooms)
end
NEAR_HOUSE = House(110, 110)                           -- 10 squares from the player
SAFE_HOUSE = House(3000, 3000)                         -- inside a safehouse
SAFEHOUSES[1] = { x = 2998, y = 2998, w = 14, h = 14 }
FAR_HOUSE = House(5000, 5000, { Room("bedroom", 5000, 5000, 4, 4, 1) })      -- two storeys
GAS = Building({ Room("gasstore", 4998, 4990, 10, 8), Room("bathroom", 5008, 4990, 2, 2) })  -- north, 2 squares
CHURCH = Building({ Room("church", 5060, 5004, 12, 12) })                   -- east, a short walk
NEIGHBOUR = House(5000, 5030)
SHED = Building({ Room("shed", 6000, 6000, 3, 3) })
USER_HOUSE = Building({ Room("bedroom", 7000, 7000, 6, 6), Room("kitchen", 7006, 7000, 6, 6) }, { userDefined = true })
CELLAR = Building({ Room("bedroom", 7100, 7100, 6, 6, -1), Room("kitchen", 7106, 7100, 6, 6, -1) })
TINY = Building({ Room("bedroom", 7200, 7200, 2, 2), Room("kitchen", 7202, 7200, 2, 2) })
WET = House(7300, 7300)
ZONES[1] = { x = 7296, y = 7296, w = 32, h = 32, type = "Water" }
LONELY = House(9000, 4100, { Room("bedroom", 9000, 4100, 4, 4, -1) })       -- basement, no neighbour
MULDRAUGH = House(10754, 9926)
NO_CELL = House(12300, 12300)
MISSING_CELLS[math.floor(12304 / 256) .. "," .. math.floor(12304 / 256)] = true
SCHOOL = Building({ Room("classroom", 4000, 8000, 10, 10), Room("hall", 4010, 8000, 6, 10) })
FARM = Building({ Room("bedroom", 4400, 8000, 5, 5), Room("kitchen", 4405, 8000, 5, 5), Room("barn", 4420, 8000, 12, 12) })
FLATS = Building({ Room("bedroom", 4800, 8000, 4, 4), Room("bedroom", 4804, 8000, 4, 4), Room("bedroom", 4808, 8000, 4, 4),
                   Room("bedroom", 4812, 8000, 4, 4), Room("kitchen", 4800, 8004, 4, 4), Room("kitchen", 4804, 8004, 4, 4) })
GARAGE_HOUSE = House(5200, 8000, { Room("garagestorage", 5208, 8000, 6, 6) })
finalize()
"""


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class RescueHarness(unittest.TestCase):

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None  # absent de Kahlua
        self.rt.execute(DOUBLES)
        paths = [TESTS_LUA / 'shared', MOD_LUA / 'shared', MOD_LUA / 'server']
        self.rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')

    def world(self, extra: str = ''):
        self.rt.execute(WORLD + extra)
        self.R = self.rt.eval('require("RadioSurvivor/RS_Rescue")')

    def ev(self, code):
        if code.lstrip().startswith(('return', 'local', 'require')):
            return self.rt.execute(code)
        return self.rt.eval(code)

    def pick(self, opts='{}'):
        return self.rt.execute(f'local s, r = require("RadioSurvivor/RS_Rescue").pick({opts}) return s, r')

    def check(self, name, opts='{}'):
        return self.rt.execute('local R = require("RadioSurvivor/RS_Rescue")'
                               f' local s, r = R.check({name}, R.knownBases({opts}), {opts}, GRID) return s, r')

    def counts(self):
        return {k: self.g.COUNT[k] for k in ('get', 'cell', 'square', 'slow')}


class ChoiceTests(RescueHarness):

    def setUp(self):
        super().setUp()
        self.world()

    def test_classification_by_room_names(self):
        kinds = {name: self.ev(f'local r = require("RadioSurvivor/RS_Rescue").classify({name}) return r and r.kind')
                 for name in ('FAR_HOUSE', 'CHURCH', 'SCHOOL', 'FARM', 'FLATS', 'GARAGE_HOUSE', 'SHED', 'GAS')}
        self.assertEqual(kinds, {'FAR_HOUSE': 'house', 'CHURCH': 'church', 'SCHOOL': 'school', 'FARM': 'farmhouse',
                                 'FLATS': 'apartments', 'GARAGE_HOUSE': 'house_garage', 'SHED': None, 'GAS': None})

    def test_each_refusal_has_its_reason(self):
        expected = {'NEAR_HOUSE': 'near a known base', 'SAFE_HOUSE': 'near a known base', 'SHED': 'not habitable',
                    'USER_HOUSE': 'player-built', 'CELLAR': 'no ground room', 'TINY': 'too small', 'WET': 'water',
                    'NO_CELL': 'outside the map'}
        for name, reason in expected.items():
            with self.subTest(name):
                site, why = self.check(name)
                self.assertIsNone(site)
                self.assertEqual(why, reason)
        site, why = self.check('FAR_HOUSE')
        self.assertIsNotNone(site, why)
        self.assertEqual((site.kind, site.z), ('house', 0))
        # Point au centre d'une pièce principale (salon ou cuisine) du bâtiment, niveau 0.
        self.assertEqual(self.ev(f'return GRID:getBuildingAt({site.x}, {site.y}, {site.z}) == FAR_HOUSE'), True)
        self.assertEqual(site.key, 'b' + self.ev('return FAR_HOUSE:getIDString()'))
        excluded, why = self.check('FAR_HOUSE', '{ exclude = { ["' + site.key + '"] = true } }')
        self.assertEqual((excluded, why), (None, 'excluded'))
        avoided, why = self.check('FAR_HOUSE', '{ avoid = { { x = 5100, y = 5100 } } }')
        self.assertEqual((avoided, why), (None, 'near a known base'))
        rect, why = self.check('FAR_HOUSE', '{ avoid = { { x1 = 4000, y1 = 4000, x2 = 4500, y2 = 4500 } } }')
        self.assertIsNotNone(rect, why)  # rectangle évité à plus de 600 cases (écart d'emprise)

    def test_picks_are_valid_and_far_from_bases(self):
        for seed in range(1, 41):
            with self.subTest(seed=seed):
                site, why = self.pick(f'{{ seed = {seed} }}')
                self.assertIsNotNone(site, why)
                self.assertNotIn(site.key, (self.ev('return "b" .. NEAR_HOUSE:getIDString()'),
                                            self.ev('return "b" .. SAFE_HOUSE:getIDString()')))
                self.assertIn(site.kind, ('house', 'church', 'school', 'farmhouse', 'apartments', 'house_garage'))
                b = site.bounds
                gap_player = max(0, b.x1 - 101, 100 - b.x2), max(0, b.y1 - 101, 100 - b.y2)
                self.assertGreaterEqual((gap_player[0] ** 2 + gap_player[1] ** 2) ** 0.5, 600)
                self.assertLessEqual(site.attempts, 300)

    def test_no_square_read_and_no_slow_scan_while_picking(self):
        for seed in range(1, 21):
            self.pick(f'{{ seed = {seed} }}')
        self.pick()
        c = self.counts()
        self.assertEqual((c['cell'], c['square'], c['slow']), (0, 0, 0))
        self.assertIsNone(self.g.ModData)

    def test_draws_are_bounded(self):
        self.g.COUNT.get = 0
        site, why = self.pick('{ seed = 3, minDistance = 1000000 }')
        self.assertIsNone(site)
        self.assertEqual(self.g.COUNT.get, 300)
        self.assertTrue(why.startswith('no suitable building after 300 draw(s): '), why)
        self.assertIn('near a known base', why)
        self.g.COUNT.get = 0
        site, why = self.pick('{ seed = 3, maxAttempts = 5, minDistance = 1000000 }')
        self.assertEqual(self.g.COUNT.get, 5)
        self.assertIn('[RadioSurvivor] rescue: no suitable building after 5 draw(s)', lua_list(self.g.LOGS)[-1])

    def test_seed_is_reproducible(self):
        keys = [self.pick(f'{{ seed = {s}, noClues = true }}')[0].key for s in range(1, 31)]
        again = [self.pick(f'{{ seed = {s}, noClues = true }}')[0].key for s in range(1, 31)]
        self.assertEqual(keys, again)
        self.assertGreater(len(set(keys)), 3)
        self.assertEqual(self.pick('{ seed = "team-alpha" }')[0].key, self.pick('{ seed = "team-alpha" }')[0].key)
        # Sans graine : ZombRand.
        self.assertIsNotNone(self.pick()[0])

    def test_empty_metagrid_and_missing_grid(self):
        self.rt.execute('BUILDINGS = {}; finalize()')
        self.assertEqual(self.pick(), (None, 'no building in the metagrid'))
        self.rt.execute('getWorld = function() return { getMetaGrid = function() return nil end } end')
        self.assertEqual(self.pick(), (None, 'no metagrid'))

    def test_server_uses_online_players(self):
        self.g.SIDE = 'server'
        bases = self.ev('return require("RadioSurvivor/RS_Rescue").knownBases({})')
        sources = sorted(bases[i].source for i in range(1, len(bases) + 1))
        self.assertEqual(sources, ['player', 'safehouse'])


class ClueTests(RescueHarness):

    def setUp(self):
        super().setUp()
        self.world()

    def clues(self, name):
        return lua_list(self.ev(f'return require("RadioSurvivor/RS_Rescue").clues({name}, GRID)'))

    def test_description_landmarks_and_street(self):
        clues = self.clues('FAR_HOUSE')
        self.assertEqual(clues[0], 'The shelter is a two-storey house.')
        self.assertIn('There is a gas station right next to it, to the north.', clues)
        self.assertIn('There is a church a short walk to the east.', clues)
        self.assertIn('There are a few other houses around it.', clues)
        self.assertIn('It is out in the country, some way from Riverside.', clues)
        for clue in clues:
            self.assertIsNone(re.search(r'\d', clue), clue)

    def test_clue_data_for_the_notebook(self):
        """E11-T09: the same clues as translatable data (key + codes or town name), same order, no number."""
        lines, data = self.ev('local l, d = require("RadioSurvivor/RS_Rescue").clueData(FAR_HOUSE, GRID) return l, d')
        lines = lua_list(lines)
        data = [(d.key, tuple(lua_list(d.args))) for d in lua_list(data)]
        self.assertEqual(lines, self.clues('FAR_HOUSE'))
        self.assertEqual(len(data), len(lines))
        self.assertEqual(data[0], ('Kind', ('house', 'medium', 'two')))
        self.assertIn(('LandmarkNext', ('gas', 'north')), data)
        self.assertIn(('Landmark', ('church', 'short', 'east')), data)
        self.assertIn(('FewHouses', ()), data)
        self.assertIn(('TownCountry', ('Riverside',)), data)
        self.assertFalse(any(re.search(r'\d', str(v)) for _, args in data for v in args))
        lonely = [d.key for d in lua_list(self.ev(
            'local _, d = require("RadioSurvivor/RS_Rescue").clueData(LONELY, GRID) return d'))]
        for key in ('Basement', 'NoLandmark', 'Isolated', 'TownFar'):
            self.assertIn(key, lonely)

    def test_lonely_building_with_basement(self):
        clues = self.clues('LONELY')
        self.assertIn('It has a basement.', clues)
        self.assertIn('There is no shop or public building nearby.', clues)
        self.assertIn('It is out in the countryside, far from any town.', clues)
        self.assertIn('It stands on its own, with no other house close by.', clues)

    def test_town_only_on_the_vanilla_map(self):
        self.assertIn('It is in Muldraugh.', self.clues('MULDRAUGH'))
        self.rt.execute('LOT_DIRS = { "SomeModMap" }')
        self.assertFalse(any('Muldraugh' in c for c in self.clues('MULDRAUGH')))
        self.rt.execute('getLotDirectories = function() error("RuntimeException") end')
        self.assertFalse(any('town' in c or 'Muldraugh' in c for c in self.clues('MULDRAUGH')))

    def test_kinds_in_description(self):
        self.assertEqual(self.clues('CHURCH')[0], 'The shelter is a single-storey church.')
        self.assertEqual(self.clues('FLATS')[0], 'The shelter is a single-storey apartment building.')
        self.assertEqual(self.clues('GARAGE_HOUSE')[0], 'The shelter is a large single-storey house with a garage.'
                         if self.ev('return GARAGE_HOUSE:getArea()') >= 200
                         else 'The shelter is a single-storey house with a garage.')

    def test_neighbours_query_only_the_covered_cells(self):
        self.ev('require("RadioSurvivor/RS_Rescue").clues(FAR_HOUSE, GRID)')
        self.assertEqual(self.counts()['slow'], 0)
        self.assertEqual(self.counts()['square'], 0)

    def test_direction_words(self):
        d = lambda x, y: self.ev(f'return require("RadioSurvivor/RS_Rescue").direction(0, 0, {x}, {y})')
        self.assertEqual([d(0, -10), d(0, 10), d(10, 0), d(-10, 0), d(10, -10), d(-10, 10)],
                         ['north', 'south', 'east', 'west', 'north-east', 'south-west'])


class ClientTests(RescueHarness):

    def test_not_loaded_on_an_mp_client(self):
        self.g.SIDE = 'client'
        self.world()
        self.assertNotIsInstance(self.R, type(self.rt.table()))
        self.assertFalse(self.ev('return type(require("RadioSurvivor/RS_Rescue")) == "table"'))


class SuiteTests(RescueHarness):

    def setUp(self):
        super().setUp()
        self.world()
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE.as_posix()}]])')

    def run_suite(self):
        self.assertTrue(self.ev('RST.start("rs.rescue.pick", { attach = false, ctx = { player = PLAYER } })'))
        for _ in range(500):
            if not self.ev('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 100
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        notes = []
        for r in report.results.values():
            if r.notes is not None:
                notes.extend(lua_list(r.notes))
        return report, results, notes

    def test_suite_passes(self):
        report, results, notes = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 6)
        sites = [n for n in notes if n.startswith('site seed=')]
        self.assertEqual(len(sites), 5)
        self.assertTrue(all('clues: The shelter is' in n for n in sites), sites)
        self.assertTrue(any(n.startswith('readable chunk centres around the player: ') and ' 0 before' not in n
                            for n in notes), notes)
        self.assertEqual(lua_list(self.g.Events.LoadChunk.list), [])  # listener removed

    def test_suite_detects_a_site_near_the_player(self):
        self.rt.execute('local R = require "RadioSurvivor/RS_Rescue";'
                        'R.pick = function() local s = R.check(NEAR_HOUSE, {}, {}, GRID); s.attempts = 1;'
                        ' s.clues = R.clues(NEAR_HOUSE, GRID); return s end')
        _, results, _ = self.run_suite()
        self.assertEqual(results['seeded picks are habitable, far from the bases, with clues and reproducible'][0],
                         'FAIL')

    def test_suite_detects_a_pick_that_loads_a_chunk(self):
        self.rt.execute('local R = require "RadioSurvivor/RS_Rescue"; local old = R.pick;'
                        'R.pick = function(o) local s, r = old(o); if s then fire("LoadChunk", fakeChunk(s.x, s.y)) end;'
                        ' return s, r end')
        _, results, _ = self.run_suite()
        status, message = results['no chunk is loaded by the picks (LoadChunk, readable squares, streaming)']
        self.assertEqual(status, 'FAIL')
        self.assertIn('LoadChunk fired during the synchronous picks', message)

    def test_suite_detects_a_loaded_site(self):
        self.rt.execute('for _, b in ipairs(BUILDINGS) do STREAMED[b.id] = true end')
        _, results, _ = self.run_suite()
        self.assertEqual(results['no chunk is loaded by the picks (LoadChunk, readable squares, streaming)'][0], 'FAIL')


class RunTests(RescueHarness):
    """E12-T02 : réserves en heures de jeu (délai en jours), décompte seulement avec un joueur connecté, sans
    rattrapage, un secours actif par équipe (RS_Factions), état privé, points d'appel des issues."""

    RUN_DOUBLES = r"""
    AGE = 100.0
    getGameTime = function() return { getWorldAgeHours = function() return AGE end } end
    FACTS = {}
    RS_Facts = { record = function(kind, fields, key) FACTS[#FACTS + 1] = { kind = kind, fields = fields, key = key } end }
    OUTCOMES = {}
    STATE = require("RadioSurvivor/RS_State")
    STATE.data = { schema = 2, world = "w" }
    R = require("RadioSurvivor/RS_Rescue")
    R.onOutcome = function(rescue, result) OUTCOMES[#OUTCOMES + 1] = { id = rescue.id, result = result } end
    function poll() return R.poll(true) end
    """

    def setUp(self):
        super().setUp()
        self.world()
        self.rt.execute(self.RUN_DOUBLES)

    def start(self, team='"fac-a"', opts='{ seed = 5 }'):
        return self.rt.execute(f'local id, r, x = R.startForTeam({team}, {opts}) return id, r, x')

    def test_start_is_saved_in_the_private_state_with_reserves(self):
        rid, rec, _ = self.start(opts='{ seed = 5, days = 3, requester = "Darlene" }')
        self.assertEqual(rid, 'rsc-1')
        self.assertEqual((rec.team, rec.state, rec.reserves, rec.daysLeft, rec.hoursLeft),
                         ('fac-a', 'active', 72, 3, 72))
        self.assertEqual(rec.requester, 'Darlene')
        self.assertTrue(len(lua_list(rec.clues)) >= 2)
        self.assertEqual(len(lua_list(rec.clueData)), len(lua_list(rec.clues)))
        self.assertEqual(self.ev('return STATE.data.rescues.active["fac-a"]'), 'rsc-1')
        self.assertEqual(self.ev('return STATE.data.rescues.rescues["rsc-1"].site.key'), rec.site.key)
        self.assertTrue(self.ev('return STATE.dirty'))
        self.assertEqual(self.ev('return R.activeFor("fac-a").id'), 'rsc-1')
        self.assertIn('[RadioSurvivor] rescue: rsc-1 started for team fac-a', lua_list(self.g.LOGS)[-1])

    def test_days_are_bounded(self):
        self.assertEqual(self.start('"fac-a"', '{ days = 0 }')[1].days, 1)
        self.assertEqual(self.start('"fac-b"', '{ days = 99 }')[1].reserves, 240)
        self.assertEqual(self.start('"fac-c"', '{}')[1].days, 3)

    # E12-T06 : option sandbox RadioSurvivor.RescueDays. Doublure de getSandboxOptions():getOptionByName(nom) fidèle
    # à SandboxOptions.java : nil pour une option inconnue, sinon un objet dont getValue() rend un nombre (integer).
    OPTION = r"""
    JAVA_OPTIONS = {}
    getSandboxOptions = function()
        return { getOptionByName = function(_, name)
            if JAVA_OPTIONS[name] == nil then return nil end
            return { getValue = function() return JAVA_OPTIONS[name] end }
        end }
    end
    """

    def test_rescue_days_option_sets_a_new_rescue(self):
        self.rt.execute(self.OPTION)
        self.rt.execute('JAVA_OPTIONS["RadioSurvivor.RescueDays"] = 5')
        rec = self.start('"fac-a"', '{ seed = 5 }')[1]
        self.assertEqual((rec.days, rec.reserves, rec.daysLeft), (5, 120, 5))
        # opts.days explicite (bancs, suites en jeu) l'emporte sur l'option.
        self.assertEqual(self.start('"fac-b"', '{ days = 2 }')[1].days, 2)

    def test_rescue_days_option_absent_or_out_of_bounds_gives_three(self):
        self.assertIsNone(self.ev('getSandboxOptions'))
        self.assertEqual(self.start('"fac-a"', '{}')[1].days, 3)          # no Java options, no SandboxVars
        self.rt.execute(self.OPTION)
        teams = iter(f'"fac-{c}"' for c in 'bcdefgh')
        for bad in ('0', '11', '2.5', '-3', '"x"', '0/0'):
            with self.subTest(value=bad):
                self.rt.execute(f'JAVA_OPTIONS["RadioSurvivor.RescueDays"] = {bad}')
                self.assertEqual(self.start(next(teams), '{}')[1].days, 3)
        self.assertEqual(self.ev('return require("RadioSurvivor/RadioSurvivor_Const").rescueDays()'), 3)

    def test_rescue_days_option_falls_back_on_sandbox_vars(self):
        self.rt.execute('SandboxVars = { RadioSurvivor = { RescueDays = 7 } }')
        self.assertEqual(self.start('"fac-a"', '{}')[1].days, 7)
        self.rt.execute('SandboxVars.RadioSurvivor.RescueDays = 10')
        self.assertEqual(self.start('"fac-b"', '{}')[1].days, 10)

    def test_running_rescue_keeps_its_reserves_when_the_option_changes(self):
        self.rt.execute(self.OPTION)
        self.rt.execute('JAVA_OPTIONS["RadioSurvivor.RescueDays"] = 2')
        self.start()
        self.rt.execute('JAVA_OPTIONS["RadioSurvivor.RescueDays"] = 9')
        self.ev('poll()')
        self.g.AGE = 104.0
        self.ev('poll()')
        rec = self.ev('return R.get("rsc-1")')
        self.assertEqual((rec.days, rec.reserves), (2, 44))
        self.assertEqual(self.start('"fac-b"', '{}')[1].days, 9)        # next rescue reads the new value

    def test_one_active_rescue_per_team_and_distinct_buildings(self):
        first = self.start('"fac-a"')
        refused = self.start('"fac-a"', '{ seed = 9 }')
        self.assertEqual(refused, (None, 'team_busy', 'rsc-1'))
        self.assertIn('refused a second rescue for team fac-a: rsc-1 is still running', lua_list(self.g.LOGS)[-1])
        second = self.start('"fac-b"')  # same seed: the building of fac-a is excluded
        self.assertEqual(second[0], 'rsc-2')
        self.assertNotEqual(first[1].site.key, second[1].site.key)
        self.assertEqual(self.start('""'), (None, 'bad_team', None))
        self.rt.execute('STATE.data = nil')
        self.assertEqual(self.start('"fac-z"')[:2], (None, 'state'))

    def test_solo_player_forms_a_personal_team(self):
        rid, rec = self.rt.execute('local id, r = R.start(PLAYER, { seed = 2 }) return id, r')
        self.assertEqual(rec.team, self.ev('return R.teamOf(PLAYER)'))
        self.assertTrue(rec.team.startswith('fac-'))
        self.assertEqual(self.rt.execute('local id, r, x = R.start(PLAYER, { seed = 3 }) return id, r, x'),
                         (None, 'team_busy', rid))

    def test_faction_members_share_one_rescue_two_teams_two_rescues(self):
        self.g.SIDE = 'server'
        self.rt.execute(r"""
        PLAYERS = {}
        A = Player(100, 100); A.getUsername = function() return "alice" end
        B = Player(120, 100); B.getUsername = function() return "bob" end
        C = Player(140, 100); C.getUsername = function() return "carol" end
        local f = { getOwner = function() return "alice" end, getName = function() return "Wolves" end,
            getPlayers = function() return JList({ "bob" }) end,
            isOwner = function(_, n) return n == "alice" end,
            isMember = function(_, n) return n == "alice" or n == "bob" end }
        Faction = { getFactions = function() return JList({ f }) end }
        require("RadioSurvivor/RS_Factions").reset()
        """)
        ida = self.rt.execute('local id = R.start(A, { seed = 4 }) return id')
        self.assertIsNotNone(ida)
        self.assertEqual(self.ev('return R.teamOf(A)'), self.ev('return R.teamOf(B)'))
        self.assertEqual(self.rt.execute('local id, r, x = R.start(B, { seed = 6 }) return id, r, x'),
                         (None, 'team_busy', ida))
        idc, recc = self.rt.execute('local id, r = R.start(C, { seed = 4 }) return id, r')
        self.assertIsNotNone(idc)
        self.assertNotEqual(self.ev('return R.teamOf(A)'), self.ev('return R.teamOf(C)'))
        self.assertNotEqual(self.ev(f'return R.get("{ida}").site.key'), recc.site.key)

    def test_reserves_drop_only_while_a_player_is_connected(self):
        self.g.SIDE = 'server'
        self.start()
        self.assertFalse(self.ev('poll()'))      # first poll of the session: reference only
        self.g.AGE = 105.0
        self.assertTrue(self.ev('poll()'))
        self.assertEqual(self.ev('return R.get("rsc-1").reserves'), 67)
        self.rt.execute('PLAYERS = {}')          # empty server, time keeps running (no PauseEmpty)
        self.g.AGE = 130.0
        self.assertFalse(self.ev('poll()'))
        self.assertEqual(self.ev('return R.get("rsc-1").reserves'), 67)
        self.rt.execute('Player(100, 100)')      # a player comes back: no catch-up of the empty hours
        self.g.AGE = 132.5
        self.ev('poll()')
        rec = self.ev('return R.get("rsc-1")')
        self.assertEqual((rec.reserves, rec.hoursLeft, rec.daysLeft, rec.consumed), (64.5, 64, 3, 7.5))

    def test_solo_counts_the_local_player(self):
        self.start()
        self.ev('poll()')
        self.g.AGE = 102.0
        self.ev('poll()')
        self.assertEqual(self.ev('return R.get("rsc-1").reserves'), 70)
        self.rt.execute('PLAYERS = {}')
        self.g.AGE = 110.0
        self.ev('poll()')
        self.assertEqual(self.ev('return R.get("rsc-1").reserves'), 70)

    def test_poll_spacing_and_every_hours(self):
        self.start()
        self.ev('R.poll(false)')
        self.g.AGE = 101.0
        self.assertFalse(self.ev('R.poll(false)'))     # within POLL_MS
        self.g.CLOCK = self.g.CLOCK + 1000
        self.ev('R.poll(false)')
        self.assertEqual(self.ev('return R.get("rsc-1").reserves'), 71)
        self.g.AGE = 104.0
        self.rt.execute('fire("EveryHours")')           # subscribed once, forced poll
        self.assertEqual(self.ev('return R.get("rsc-1").reserves'), 68)
        self.assertEqual(len(lua_list(self.g.Events.EveryHours.list)), 1)
        self.assertEqual(len(lua_list(self.g.Events.OnTickEvenPaused.list)), 1)
        self.g.AGE = 90.0                                # older world (restored save): nothing removed
        self.ev('poll()')
        self.g.AGE = 91.0
        self.ev('poll()')
        self.assertEqual(self.ev('return R.get("rsc-1").reserves'), 67)

    def test_reserves_at_zero_close_the_rescue_too_late(self):
        self.start(opts='{ seed = 5, days = 1, requester = "Darlene" }')
        self.ev('poll()')
        self.g.AGE = 130.0
        self.assertTrue(self.ev('poll()'))
        rec = self.ev('return R.get("rsc-1")')
        self.assertEqual((rec.state, rec.reserves, rec.scene, rec.daysLeft), ('missed', 0, 'pending', 0))
        self.assertIsNone(self.ev('return R.activeFor("fac-a")'))
        self.assertEqual([(o.id, o.result) for o in lua_list(self.g.OUTCOMES)], [('rsc-1', 'missed')])
        facts = lua_list(self.g.FACTS)
        self.assertEqual(len(facts), 1)
        self.assertEqual((facts[0].kind, facts[0].fields.result, facts[0].fields.requester, facts[0].key),
                         ('rescue', 'missed', 'Darlene', 'rescue|rsc-1'))
        self.assertEqual([r.id for r in lua_list(self.ev('return R.pendingScenes()'))], ['rsc-1'])
        self.assertTrue(self.ev('return R.scenePlaced("rsc-1")'))
        self.assertFalse(self.ev('return R.scenePlaced("rsc-1")'))
        self.assertEqual(self.start(opts='{ seed = 5 }')[0], 'rsc-2')  # the team may be called again

    def test_delivery_and_outcome_entry_points(self):
        self.start(opts='{ days = 2 }')
        self.assertEqual(self.ev('return R.addReserves("rsc-1", 30)'), 78)
        self.assertEqual(self.ev('return R.addReserves("rsc-1", 1000)'), 240)
        self.assertEqual(self.rt.execute('return R.addReserves("rsc-1", -1)'), (None, 'bad_amount'))
        self.assertEqual(self.rt.execute('return R.finish("rsc-1", "won")'), (None, 'bad_result'))
        out = self.rt.execute('return R.finish("rsc-1", "saved", { participants = { "Kate Smith" } })')
        self.assertEqual((out.state, out.scene), ('saved', 'pending'))
        fact = lua_list(self.g.FACTS)[0]
        self.assertEqual((fact.fields.result, lua_list(fact.fields.participants)), ('saved', ['Kate Smith']))
        self.assertEqual(self.rt.execute('return R.addReserves("rsc-1", 5)'), (None, 'not_active'))
        self.assertEqual(self.rt.execute('return R.finish("rsc-1", "missed")'), (None, 'not_active'))
        self.start('"fac-b"')
        out = self.rt.execute('return R.finish("rsc-2", "abandoned")')
        self.assertEqual((out.state, out.scene), ('abandoned', None))
        self.assertEqual(len(lua_list(self.g.FACTS)), 1)   # no fact for an abandoned call

    def test_closed_rescues_are_bounded_pending_scenes_last(self):
        self.rt.execute('R.RUN.MAX_CLOSED = 2')
        for i, result in enumerate(('saved', 'abandoned', 'abandoned', 'missed'), start=1):
            self.start(f'"fac-{i}"', f'{{ seed = {i} }}')
            self.rt.execute(f'R.finish("rsc-{i}", "{result}")')
        self.assertEqual([r.id for r in lua_list(self.ev('return R.list()'))], ['rsc-1', 'rsc-4'])

    def run_run_suite(self):
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE.as_posix()}]])')
        self.assertTrue(self.ev('RST.start("rs.rescue.run", { attach = false, ctx = { player = PLAYER } })'))
        for _ in range(500):
            if not self.ev('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 100
            self.g.AGE = self.g.AGE + 0.01
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_run_suite_passes_and_leaves_the_state_alone(self):
        self.rt.execute(RunSuiteOptionTests.OPTION)   # E12-T06 : option RescueDays enregistrée (doublure Java)
        report, results = self.run_run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 6)
        self.assertIsNone(self.ev('return STATE.data.rescues'))
        self.assertEqual(len(lua_list(self.g.FACTS)), 0)

    def test_run_suite_detects_reserves_dropping_on_an_empty_server(self):
        self.g.SIDE = 'server'
        self.rt.execute('PLAYERS = {}; R.connected = function() return false end;'
                        ' local consume = R.consume; R.poll = function() return consume(0.5) end')
        _, results = self.run_run_suite()
        self.assertEqual(results['reserves drop with the world age only while a player is connected'][0], 'FAIL')

    def test_work_store_leaves_the_private_state_alone(self):
        self.rt.execute('R.useStore(R.newStore()); STATE.dirty = false')
        self.start()
        self.rt.execute('R.finish("rsc-1", "missed")')
        self.assertFalse(self.ev('return STATE.dirty'))
        self.assertIsNone(self.ev('return STATE.data.rescues'))
        self.assertEqual(len(lua_list(self.g.FACTS)), 0)
        self.rt.execute('R.useStore(nil)')
        self.assertIsNone(self.ev('return R.get("rsc-1")'))


class RunSuiteOptionTests(RescueHarness):
    """E12-T06 : test « RescueDays option » de la suite en jeu rs.rescue.run contre les doublures. Doublure de
    l'option fidèle à IntegerConfigOption : getValue() rend un nombre, setValue(n) hors min..max est ignoré."""

    OPTION = r"""
    JAVA_OPTIONS = { ["RadioSurvivor.RescueDays"] = { v = 3, min = 1, max = 10 } }
    getSandboxOptions = function()
        return { getOptionByName = function(_, name)
            local o = JAVA_OPTIONS[name]
            if o == nil then return nil end
            return { getValue = function() return o.v end,
                     setValue = function(_, n) if n >= o.min and n <= o.max then o.v = n end end }
        end }
    end
    """
    TEST = 'a new rescue takes its delay from the RescueDays option'

    def setUp(self):
        super().setUp()
        self.world()
        self.rt.execute(RunTests.RUN_DOUBLES)
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE.as_posix()}]])')

    def run_suite(self):
        self.assertTrue(self.ev('RST.start({ suite = "rs.rescue.run", test = "RescueDays" }, '
                                '{ attach = false, ctx = { player = PLAYER } })'))
        for _ in range(500):
            if not self.ev('RST.step()'):
                break
            self.g.CLOCK = self.g.CLOCK + 100
        report = self.ev('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        return report, {r.test: (r.status, r.message) for r in report.results.values()}

    def test_suite_passes_and_restores_the_option(self):
        self.rt.execute(self.OPTION)
        report, results = self.run_suite()
        self.assertEqual(results[self.TEST][0], 'PASS', results[self.TEST][1])
        self.assertEqual(report.total, 1)
        self.assertEqual(self.g.JAVA_OPTIONS['RadioSurvivor.RescueDays'].v, 3)
        self.assertIsNone(self.ev('return STATE.data.rescues'))   # work store only

    def test_suite_fails_without_the_option(self):
        _, results = self.run_suite()
        self.assertEqual(results[self.TEST][0], 'FAIL')
        self.assertIn('option RadioSurvivor.RescueDays not registered', results[self.TEST][1])

    def test_suite_detects_a_constant_delay(self):
        self.rt.execute(self.OPTION)
        self.rt.execute('require("RadioSurvivor/RadioSurvivor_Const").rescueDays = function() return 3 end')
        _, results = self.run_suite()
        self.assertEqual(results[self.TEST][0], 'FAIL')


class SourceTests(unittest.TestCase):

    def test_kahlua_constraints(self):
        for path in (MODULE, SUITE):
            code = path.read_text(encoding='utf-8')
            body = re.sub(r'--\[\[.*?\]\]', '', code, flags=re.S)
            body = '\n'.join(line.split('--')[0] for line in body.splitlines())
            with self.subTest(path.name):
                self.assertTrue(all(ord(ch) < 128 for ch in body), 'non-ASCII outside comments')
                self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', body))
                self.assertIsNone(re.search(r'\bgoto\b|coroutine\.|debug\.traceback|%q', body))
                self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', body.replace('~=', '')))

    def test_rescue_days_option_and_translations(self):
        # E12-T06 : entier 1..10, défaut 3, page RadioSurvivor ; = Const.RESCUE_DAYS_MIN / MAX et DEFAULTS.RescueDays.
        import json
        opts = (MOD_LUA.parent / 'sandbox-options.txt').read_text(encoding='utf-8')
        self.assertRegex(opts, r'option RadioSurvivor\.RescueDays\n\{\n\ttype = integer,\n\tmin = 1,\n\tmax = 10,\n'
                               r'\tdefault = 3,\n\tpage = RadioSurvivor,\n\ttranslation = RadioSurvivor_RescueDays,\n\}')
        const = (MOD_LUA / 'shared' / 'RadioSurvivor' / 'RadioSurvivor_Const.lua').read_text(encoding='utf-8')
        self.assertIn('RescueDays = 3,', const)
        self.assertIn('Const.RESCUE_DAYS_MIN, Const.RESCUE_DAYS_MAX = 1, 10', const)
        for lang in ('EN', 'FR'):
            sb = json.loads((MOD_LUA / 'shared' / 'Translate' / lang / 'Sandbox.json').read_text(encoding='utf-8'))
            for k in ('RescueDays', 'RescueDays_tooltip'):
                with self.subTest(lang=lang, key=k):
                    self.assertTrue(sb['Sandbox_RadioSurvivor_' + k].strip())
                    sb['Sandbox_RadioSurvivor_' + k].encode('latin-1')

    def test_module_never_loads_nor_writes(self):
        body = re.sub(r'--\[\[.*?\]\]', '', MODULE.read_text(encoding='utf-8'), flags=re.S)
        body = '\n'.join(line.split('--')[0] for line in body.splitlines())
        for forbidden in ('getGridSquare', 'LoadChunk', 'getChunk', 'getCell(', 'ModData', 'sendServerCommand',
                          'sendClientCommand', 'getFileWriter'):
            self.assertNotIn(forbidden, body)
        self.assertTrue(body.lstrip().startswith('if isClient() then return end'))


if __name__ == '__main__':
    unittest.main(verbosity=1)
