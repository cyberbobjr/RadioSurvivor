"""Doublures fidèles de la métagrille 42.21 partagées par les bancs des sites (E12-T01, E21-T08 : sorties de
tests/radiosurvivor/test_rescue.py pour que les bancs de Living Knox les lisent sans le banc de RadioSurvivor).

DOUBLES : IsoMetaGrid (getBuildings, isValidSquare, getCellData, getZonesAt, getBuildingAt(x, y, z) par les pièces,
getBuildingAt(x, y) et getBuildingsIntersecting comptés comme appels lents), IsoMetaCell (getBuildingsIntersecting
sans doublon, chaque lecture d'une cellule comptée : COUNT.cellReads, E25-T02), BuildingDef, RoomDef et RoomRect, SafeHouse, joueurs (solo et serveur), ArrayList, getLotDirectories,
Events.LoadChunk ; toute lecture de case (getCell, getGridSquare, getChunk) est comptée. WORLD : la carte de test.
"""
from __future__ import annotations

DOUBLES = r"""
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
SIDE = "solo"
isServer = function() return SIDE == "server" end
isClient = function() return SIDE == "client" end
COUNT = { get = 0, cell = 0, square = 0, slow = 0, cellReads = 0 }

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
        COUNT.cellReads = COUNT.cellReads + 1
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
