"""Sites des foyers de groupes (LK08-T03) : LK_Sites.lua et la suite en jeu lk.sites dans lupa.

    python RadioSurvivor/tests/test_lk_sites.py

Vrai Lua du mod (Lua 5.1, `next` retiré comme dans Kahlua) : LK_Core, LK_Config, LK_Log, types de groupes livrés
(LK_GroupTypes et Data/LK_Type_*.lua), vrai registre LK_Groups (fichiers getFileReader / getFileWriter en mémoire),
RS_Rescue et vrai moteur RST. Doublures de la métagrille 42.21 reprises de tests/test_rescue.py (IsoMetaGrid,
IsoMetaCell:getBuildingsIntersecting, BuildingDef, RoomDef, SafeHouse, joueurs, cases comptées), complétées ici
d'après le Java décompilé : IsoMetaGrid:getMinX/getMaxX/getMinY/getMaxY (bornes en cellules),
IsoMetaGrid:getZonesIntersecting (cellules de x / 256 à (x + w) / 256, résultat partagé) et
IsoMetaCell:getZonesIntersecting (zones des métachunks existants qui croisent le rectangle, sans doublon, aucune
création), Zone (getType, getX, getY, getWidth, getHeight), RoomDef:isExplored. Les zones de la biomemap n'existent
que pour les cellules « approchées » de la carte de test (comme ZoneGenerator.genForaging au premier chargement d'un
chunk de la cellule) ; les routes (Nav) existent partout.
Toute lecture de case (getCell, getGridSquare) pendant un choix est comptée et doit rester à zéro.
Ne prouve pas l'API Java réelle : suite en jeu lk.sites (docs/conception/sites.md).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rescue import DOUBLES, WORLD  # noqa: E402  (doublures fidèles de la métagrille, E12-T01)

ROOT = Path(__file__).resolve().parents[1]
MOD_LUA = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
TESTS_LUA = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
MODULE = MOD_LUA / 'server' / 'LivingKnox' / 'LK_Sites.lua'
SUITE = TESTS_LUA / 'shared' / 'RST' / 'suites' / 'RST_LKSites.lua'
SHARED = ['LivingKnox/LK_Core', 'LivingKnox/LK_Config', 'LivingKnox/LK_Log', 'LivingKnox/LK_GroupTypes',
          'LivingKnox/Data/LK_Type_neutrals', 'LivingKnox/Data/LK_Type_raiders', 'LivingKnox/Data/LK_Type_settlers']

# Compléments des doublures de test_rescue.py (avant la carte : Room est enveloppée).
EXTRA = r"""
COUNT.zones = 0
local baseRoom = Room
function Room(...)
    local r = baseRoom(...)
    r.explored = false
    function r:isExplored() return self.explored end
    return r
end

-- Zone Java : un objet stable par entrée de ZONES (contains() de la liste se fait par identité).
local ZONE_OBJ = {}
local function zoneObject(zn)
    if ZONE_OBJ[zn] then return ZONE_OBJ[zn] end
    local o = { getType = function() return zn.type end, getX = function() return zn.x end,
                getY = function() return zn.y end, getWidth = function() return zn.w end,
                getHeight = function() return zn.h end }
    ZONE_OBJ[zn] = o
    return o
end
local function overlaps(zn, x, y, w, h)
    return zn.x < x + w and x < zn.x + zn.w and zn.y < y + h and y < zn.y + zn.h
end

-- IsoMetaGrid : bornes en cellules (minX..maxX inclus).
function GRID:getMinX() return 0 end
function GRID:getMinY() return 0 end
function GRID:getMaxX() return MAP_W / 256 - 1 end
function GRID:getMaxY() return MAP_H / 256 - 1 end

-- IsoMetaCell:getZonesIntersecting : zones des métachunks de la cellule qui croisent le rectangle, sans doublon.
local baseCellData = GRID.getCellData
function GRID:getCellData(cx, cy)
    local c = baseCellData(self, cx, cy)
    if c and not c.getZonesIntersecting then
        function c:getZonesIntersecting(x, y, z, w, h, result)
            COUNT.zones = COUNT.zones + 1
            local cx1, cy1 = self.cx * 256, self.cy * 256
            local ix1, iy1 = math.max(x, cx1), math.max(y, cy1)
            local ix2, iy2 = math.min(x + w, cx1 + 256), math.min(y + h, cy1 + 256)
            if ix1 >= ix2 or iy1 >= iy2 then return end
            for _, zn in ipairs(ZONES) do
                if (zn.z or 0) == z and overlaps(zn, ix1, iy1, ix2 - ix1, iy2 - iy1) then
                    local o = zoneObject(zn)
                    if not result:contains(o) then result:add(o) end
                end
            end
        end
    end
    return c
end
-- IsoMetaGrid:getZonesIntersecting (IsoMetaGrid.java:227-235).
function GRID:getZonesIntersecting(x, y, z, w, h, result)
    result = result or ArrayList.new()
    for yy = math.floor(y / 256), math.floor((y + h) / 256) do
        for xx = math.floor(x / 256), math.floor((x + w) / 256) do
            local c = self:getCellData(xx, yy)
            if c then c:getZonesIntersecting(x, y, z, w, h, result) end
        end
    end
    return result
end

-- Fichiers du registre des groupes en mémoire (getFileWriter tronque à l'ouverture, readLine sans fin de ligne).
FILES = {}
getFileWriter = function(path, create, append)
    local buf = {}
    return { write = function(_, s) buf[#buf + 1] = s end,
             close = function() FILES[path] = table.concat(buf) end }
end
getFileReader = function(path, create)
    local text = FILES[path]
    if text == nil then return nil end
    local lines = {}
    for line in string.gmatch(text, "([^\n]*)\n") do lines[#lines + 1] = line end
    local i = 0
    return { readLine = function() i = i + 1 return lines[i] end, close = function() end }
end
getGameTime = function() return { getWorldAgeHours = function() return 0 end } end
getWorld = function()
    return { getMetaGrid = function() return GRID end, getWorld = function() return "rstest-sites" end,
             getGameMode = function() return "Sandbox" end }
end
"""

# Cellules approchées : zones de la biomemap (rectangles au grain du chunk), plus routes et bâtiments.
FORESTS = r"""
-- Cellule (30, 10) : forêt profonde avec un étang au coin nord-ouest et une route au sud.
ZONES[#ZONES + 1] = { x = 7680, y = 2560, w = 256, h = 224, type = "DeepForest" }
ZONES[#ZONES + 1] = { x = 7680, y = 2784, w = 256, h = 32, type = "TownZone" }
ZONES[#ZONES + 1] = { x = 7680, y = 2560, w = 32, h = 32, type = "Water" }
ZONES[#ZONES + 1] = { x = 7680, y = 2800, w = 256, h = 4, type = "Nav" }
-- Cellule (40, 40) : forêt de pins avec une cabane au milieu.
ZONES[#ZONES + 1] = { x = 10240, y = 10240, w = 256, h = 256, type = "PHForest" }
CABIN = Building({ Room("bedroom", 10360, 10360, 4, 4), Room("kitchen", 10364, 10360, 4, 4) })
-- Cellule (12, 50) : moitié bouleaux, moitié champs.
ZONES[#ZONES + 1] = { x = 3072, y = 12800, w = 128, h = 256, type = "BirchForest" }
ZONES[#ZONES + 1] = { x = 3200, y = 12800, w = 128, h = 256, type = "FarmLand" }
-- Cellule du joueur (0, 0) : forêt trop proche de la base.
ZONES[#ZONES + 1] = { x = 0, y = 0, w = 256, h = 256, type = "DeepForest" }
-- Cellule (50, 10) : rive argileuse (zone "Forest") jamais retenue.
ZONES[#ZONES + 1] = { x = 12800, y = 2560, w = 256, h = 256, type = "Forest" }
-- Route qui traverse une cellule jamais approchée (streets.xml : partout).
ZONES[#ZONES + 1] = { x = 1000, y = 9000, w = 3000, h = 6, type = "Nav" }
finalize()
"""


# Carte réaliste sans forêt connue (LK08-T08) : constat en jeu du 2026-10-10 (300 tirages : 45 % de bâtiments non
# habitables, 8 % sans pièce au sol, aucun bâtiment habitable sans voisin à 100 cases). Villes denses (îlots de 48 cases,
# quatre lots de 22 cases, voisins à 8 cases environ) avec maisons, commerces, stations-service, entrepôts, garages,
# immeubles, églises et sous-sols seuls ; campagne : fermes (maison, grange et abri à 20 cases) et chapelets de maisons
# et de dépôts le long des routes (voisins à 30-90 cases). Aucun bâtiment n'atteint 100 cases d'isolement. Tirage
# Park-Miller fixe (reproductible). TOWN_ONLY : villes seules (isolement toujours sous 30 cases).
# Index des bâtiments par cellule : IsoMetaCell:getBuildingsIntersecting ne lit que les bâtiments de sa cellule.
REALISTIC = r"""
PLAYER = Player(100, 100)
local s = 4242
local function rnd(n) s = (s * 16807) % 2147483647 return s % n end
local function house(x, y, extra)
    local rooms = { Room("bedroom", x, y, 4, 4), Room("kitchen", x + 4, y, 4, 4), Room("livingroom", x, y + 4, 8, 4) }
    for _, r in ipairs(extra or {}) do rooms[#rooms + 1] = r end
    return Building(rooms)
end
local SHOPS = { "grocery", "clothingstore", "bar", "bookstore", "office", "restaurant", "pharmacy" }
local function lot(x, y)
    local k = rnd(100)
    if k < 45 then house(x, y)
    elseif k < 55 then house(x, y, { Room("garagestorage", x + 8, y, 6, 6) })
    elseif k < 72 then Building({ Room(SHOPS[rnd(#SHOPS) + 1], x, y, 12, 10) })
    elseif k < 77 then Building({ Room("gasstore", x, y, 10, 8), Room("bathroom", x + 10, y, 2, 2) })
    elseif k < 82 then Building({ Room("warehouse", x, y, 14, 14) })
    elseif k < 86 then Building({ Room("mechanic", x, y, 12, 10) })
    elseif k < 94 then Building({ Room("bedroom", x, y, 6, 6, -1), Room("kitchen", x + 6, y, 6, 6, -1) })
    elseif k < 97 then
        Building({ Room("bedroom", x, y, 4, 4), Room("bedroom", x + 4, y, 4, 4), Room("bedroom", x + 8, y, 4, 4),
                   Room("bedroom", x + 12, y, 4, 4), Room("kitchen", x, y + 4, 4, 4), Room("kitchen", x + 4, y + 4, 4, 4) })
    else Building({ Room("church", x, y, 12, 12) }) end
end
local function town(x0, y0, blocks)
    for by = 0, blocks - 1 do
        for bx = 0, blocks - 1 do
            local x, y = x0 + bx * 48, y0 + by * 48
            lot(x + 2, y + 2) lot(x + 24, y + 2) lot(x + 2, y + 24) lot(x + 24, y + 24)
        end
    end
end
town(2000, 2000, 8) town(8000, 3000, 8) town(5000, 9000, 8) town(12000, 12000, 6)
if not TOWN_ONLY then
    -- Fermes : maison, grange à 22 cases, abri de 3 x 3 (trop petit) ; une ferme tous les 150 à 230 cases.
    for _, y in ipairs({ 4500, 7200, 11000 }) do
        local x = 600
        while x < 15000 do
            house(x, y)
            Building({ Room("barn", x + 30, y, 12, 16) })
            Building({ Room("shed", x, y + 20, 3, 3) })
            x = x + 150 + rnd(80)
        end
    end
    -- Routes de campagne : maisons et dépôts tous les 38 à 97 cases (écart réel de 30 à 89 cases).
    for _, y in ipairs({ 6000, 6400, 13500 }) do
        local x = 700
        while x < 15000 do
            if rnd(10) < 2 then Building({ Room("storageunit", x, y, 8, 8) }) else house(x, y) end
            x = x + 38 + rnd(60)
        end
    end
end
finalize()
BUCKETS = {}
function indexBuilding(b)
    for cy = math.floor(b.y1 / 256), math.floor((b.y2 - 1) / 256) do
        for cx = math.floor(b.x1 / 256), math.floor((b.x2 - 1) / 256) do
            local key = cx .. "," .. cy
            BUCKETS[key] = BUCKETS[key] or {}
            table.insert(BUCKETS[key], b)
        end
    end
end
for _, b in ipairs(BUILDINGS) do indexBuilding(b) end
local prevCellData = GRID.getCellData
function GRID:getCellData(cx, cy)
    local c = prevCellData(self, cx, cy)
    if c and not c.bucketed then
        c.bucketed = true
        function c:getBuildingsIntersecting(x, y, w, h, result)
            local cx1, cy1 = self.cx * 256, self.cy * 256
            local ix1, iy1 = math.max(x, cx1), math.max(y, cy1)
            local ix2, iy2 = math.min(x + w, cx1 + 256), math.min(y + h, cy1 + 256)
            if ix1 >= ix2 or iy1 >= iy2 then return end
            for _, b in ipairs(BUCKETS[self.cx .. "," .. self.cy] or {}) do
                if b.x1 < ix2 and ix1 < b.x2 and b.y1 < iy2 and iy1 < b.y2 and not result:contains(b) then
                    result:add(b)
                end
            end
        end
    end
    return c
end
"""

SUITE_SEEDS = (11, 23, 37, 41, 59)
LAIR_KINDS = {'warehouse', 'barn', 'garage', 'gasstation', 'workshop'}


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class SitesHarness(unittest.TestCase):
    forests = True

    def setUp(self):
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.rt.globals()
        self.g.next = None  # absent de Kahlua
        self.rt.execute(DOUBLES)
        self.rt.execute(EXTRA)
        paths = [TESTS_LUA / 'shared', MOD_LUA / 'shared', MOD_LUA / 'server']
        self.rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')

    def world(self, forests: bool = True, realistic: bool = False, town_only: bool = False):
        if realistic:
            self.g.TOWN_ONLY = town_only
            self.rt.execute(REALISTIC)
        else:
            self.rt.execute(WORLD + (FORESTS if forests else ''))
        for name in SHARED:
            self.rt.execute(f'require "{name}"')
        self.rt.execute('require "LivingKnox/LK_Groups"; LivingKnox.Groups.init(true)')
        self.rt.execute('require "LivingKnox/LK_Sites"')
        self.reset_counts()

    def reset_counts(self):
        self.rt.execute('COUNT.get, COUNT.cell, COUNT.square, COUNT.slow, COUNT.zones = 0, 0, 0, 0, 0')

    def ev(self, code):
        if code.lstrip().startswith(('return', 'local', 'require')):
            return self.rt.execute(code)
        return self.rt.eval(code)

    def pick(self, gtype, opts='{}'):
        return self.rt.execute(f'local s, r = LivingKnox.Sites.pick("{gtype}", {opts}) return s, r')

    def counts(self):
        return {k: self.g.COUNT[k] for k in ('get', 'cell', 'square', 'slow', 'zones')}

    def buildings(self):
        bs = self.g.BUILDINGS
        return [(bs[i].x1, bs[i].y1, bs[i].x2, bs[i].y2, bs[i].id) for i in range(1, len(bs) + 1)]

    def zones(self, kind=None):
        zs = self.g.ZONES
        out = [(zs[i].x, zs[i].y, zs[i].w, zs[i].h, zs[i].type) for i in range(1, len(zs) + 1)]
        return [z for z in out if kind is None or z[4] == kind]


def gap(a, b) -> float:
    """Écart entre deux rectangles (x1, y1, x2, y2) à fin exclusive, comme RS_Rescue.gap."""
    gx = max(0, b[0] - a[2], a[0] - b[2])
    gy = max(0, b[1] - a[3], a[1] - b[3])
    return (gx * gx + gy * gy) ** 0.5


PLAYER = (100, 100, 101, 101)


class BuildingTests(SitesHarness):

    def setUp(self):
        super().setUp()
        self.world()

    def test_settlers_and_neutrals_get_wanted_habitable_buildings(self):
        for gtype in ('settlers', 'neutrals'):
            wanted = lua_list(self.ev(f'return LivingKnox.Sites.KINDS_BY_TYPE.{gtype}'))
            for seed in range(1, 31):
                with self.subTest(gtype=gtype, seed=seed):
                    site, why = self.pick(gtype, f'{{ seed = {seed} }}')
                    self.assertIsNotNone(site, why)
                    self.assertEqual((site.kind, site.groupType), ('building', gtype))
                    self.assertIn(site.buildingKind, wanted)
                    self.assertIsNone(site.fallback)
                    self.assertTrue(site.key.startswith('b'))
                    b = site.bounds
                    self.assertGreaterEqual(gap((b.x1, b.y1, b.x2, b.y2), PLAYER), 600)
                    self.assertEqual(self.ev(f'return GRID:getBuildingAt({site.x}, {site.y}, {site.z}):getIDString()'),
                                     site.buildingId)
                    self.assertLessEqual(site.attempts, 300)

    def test_kind_filter_by_type_and_override(self):
        # Église admise pour les colons, pas l'école pour les neutres ; kinds remplace la liste du type.
        ctx = 'LivingKnox.Sites.context("{t}", {o}, GRID)'
        check = 'local s, r = LivingKnox.Sites.checkBuilding({b}, ' + ctx + ', false) return s and s.buildingKind, r'
        self.assertEqual(self.ev(check.format(b='SCHOOL', t='settlers', o='{}')), ('school', None))
        self.assertEqual(self.ev(check.format(b='SCHOOL', t='neutrals', o='{}')), (None, 'kind not wanted'))
        self.assertEqual(self.ev(check.format(b='SCHOOL', t='neutrals', o='{ kinds = { "school" } }')),
                         ('school', None))
        # Un type sans liste admet tout bâtiment habitable.
        self.assertEqual(self.ev(check.format(b='SCHOOL', t='raiders', o='{}')), ('school', None))

    def test_explored_building_is_never_picked_i8_2(self):
        explored = self.rt.execute('FAR_HOUSE.rooms.items[2].explored = true return "b" .. FAR_HOUSE:getIDString()')
        keys = {self.pick('settlers', f'{{ seed = {s} }}')[0].key for s in range(1, 61)}
        self.assertNotIn(explored, keys)
        site, why = self.ev('local s, r = LivingKnox.Sites.checkBuilding(FAR_HOUSE,'
                            ' LivingKnox.Sites.context("settlers", {}, GRID), false) return s, r')
        self.assertEqual((site, why), (None, 'explored by a player'))
        site, why = self.ev('local s, r = LivingKnox.Sites.checkBuilding(FAR_HOUSE,'
                            ' LivingKnox.Sites.context("settlers", { allowExplored = true }, GRID), false) return s, r')
        self.assertIsNotNone(site, why)

    def test_other_group_homes_are_avoided(self):
        first, _ = self.pick('settlers', '{ seed = 4 }')
        gid = self.ev('local g = LivingKnox.Groups.create({ type = "settlers", name = "Hill folk" }) return g.id')
        self.assertTrue(self.ev(f'return LivingKnox.Groups.setHome("{gid}", {first.x}, {first.y}, {first.z})'))
        homes = self.ev('return LivingKnox.Sites.groupHomes({})')
        self.assertEqual([(h.x1, h.y1, h.source) for h in lua_list(homes)], [(first.x, first.y, gid)])
        for seed in range(1, 41):
            with self.subTest(seed=seed):
                site, why = self.pick('neutrals', f'{{ seed = {seed} }}')
                self.assertIsNotNone(site, why)
                b = site.bounds
                self.assertGreaterEqual(gap((b.x1, b.y1, b.x2, b.y2), (first.x, first.y, first.x + 1, first.y + 1)),
                                        400)
                self.assertGreaterEqual(site.groupDistance, 400)
        # Le groupe à reloger ignore son propre foyer ; homes ajoute des foyers prévus.
        self.assertEqual(lua_list(self.ev(f'return LivingKnox.Sites.groupHomes({{ ignoreGroup = "{gid}" }})')), [])
        self.assertEqual(len(lua_list(self.ev(
            f'return LivingKnox.Sites.groupHomes({{ ignoreGroup = "{gid}", homes = {{ {{ x = 1, y = 2 }} }} }})'))), 1)
        site, why = self.ev('local s, r = LivingKnox.Sites.checkBuilding(FAR_HOUSE,'
                            ' LivingKnox.Sites.context("settlers", { groupDistance = 100000, allowExplored = true },'
                            ' GRID), false) return s, r')
        self.assertEqual((site, why), (None, 'near another group home'))

    def test_draws_are_bounded_and_reason_given(self):
        site, why = self.pick('settlers', '{ seed = 3, baseDistance = 1000000 }')
        self.assertIsNone(site)
        self.assertEqual(self.g.COUNT.get, 300)
        self.assertTrue(why.startswith('no suitable building after 300 draw(s): '), why)
        self.assertIn('near a known base', why)
        self.reset_counts()
        self.pick('settlers', '{ seed = 3, maxAttempts = 7, baseDistance = 1000000 }')
        self.assertEqual(self.g.COUNT.get, 7)
        self.assertIn('[LivingKnox] WARN sites: no site for settlers: no suitable building after 7 draw(s)',
                      lua_list(self.g.LOGS)[-1])

    def test_bad_type_and_style(self):
        self.assertEqual(self.pick('nomads'), (None, 'unknown group type nomads'))
        self.assertEqual(self.pick('settlers', '{ home = "cave" }'), (None, 'bad home style cave'))
        self.assertEqual(self.ev('return LivingKnox.Sites.homeStyle("raiders")'), 'forest')
        self.rt.execute('getWorld = function() return { getMetaGrid = function() return nil end } end')
        self.assertEqual(self.pick('settlers'), (None, 'no metagrid'))


class ClearingTests(SitesHarness):

    def setUp(self):
        super().setUp()
        self.world()

    def assert_valid_clearing(self, site):
        r = site.radius
        x, y = site.x, site.y
        square = (x - r, y - r, x + r + 1, y + r + 1)
        self.assertEqual((site.kind, site.z, site.source), ('clearing', 0, 'metagrid'))
        self.assertEqual(site.key, f'c{x}_{y}')
        self.assertGreaterEqual(gap((x, y, x + 1, y + 1), PLAYER), 600)
        for zx, zy, zw, zh, _ in self.zones('Water'):
            self.assertGreater(gap(square, (zx, zy, zx + zw, zy + zh)), 0, 'water inside the camp square')
        for zx, zy, zw, zh, _ in self.zones('Nav'):
            self.assertGreater(gap((x - 40, y - 40, x + 41, y + 41), (zx, zy, zx + zw, zy + zh)), 0, 'road nearby')
        for bx1, by1, bx2, by2, _ in self.buildings():
            self.assertGreater(gap((x - 60, y - 60, x + 61, y + 61), (bx1, by1, bx2, by2)), 0, 'building nearby')
        forest = [z for z in self.zones() if z[4] in ('DeepForest', 'PHForest', 'BirchForest')]
        for px in (x - r, x, x + r):
            for py in (y - r, y, y + r):
                self.assertTrue(any(zx <= px < zx + zw and zy <= py < zy + zh for zx, zy, zw, zh, _ in forest),
                                (px, py))
        self.assertIn(site.zone, ('DeepForest', 'PHForest', 'BirchForest'))

    def test_raiders_get_varied_forest_clearings(self):
        sites = []
        for seed in range(1, 41):
            with self.subTest(seed=seed):
                site, why = self.pick('raiders', f'{{ seed = {seed} }}')
                self.assertIsNotNone(site, why)
                self.assertIsNone(site.fallback)
                self.assert_valid_clearing(site)
                self.assertEqual(site.forestZones, 4)  # rive "Forest" écartée
                sites.append(site)
        self.assertGreater(len({s.key for s in sites}), 30)
        self.assertEqual({s.zone for s in sites}, {'DeepForest', 'PHForest', 'BirchForest'})

    def test_each_clearing_refusal_has_its_reason(self):
        ctx = 'LivingKnox.Sites.context("raiders", {o}, GRID)'
        cases = {
            (100, 120, '{}'): 'near a known base',
            (7700, 2580, '{}'): 'water',
            (7800, 2780, '{}'): 'forest edge',
            (7800, 2770, '{}'): 'near a road',
            (10370, 10400, '{}'): 'near a building',
            (12900, 2600, '{}'): 'forest edge',     # rive argileuse "Forest"
            (6000, 6000, '{}'): 'forest edge',      # cellule jamais approchée : aucune zone connue
            (12304, 12304, '{}'): 'outside the map',
            (7800, 2650, '{ exclude = { c7800_2650 = true } }'): 'excluded',
            (7800, 2650, '{ homes = { { x = 7900, y = 2700 } } }'): 'near another group home',
        }
        for (x, y, opts), reason in cases.items():
            with self.subTest(x=x, y=y):
                site, why = self.ev(f'local s, r = LivingKnox.Sites.checkClearing({x}, {y}, '
                                    + ctx.format(o=opts) + ') return s, r')
                self.assertIsNone(site)
                self.assertEqual(why, reason)
        site, why = self.ev('local s, r = LivingKnox.Sites.checkClearing(7800, 2650, ' + ctx.format(o='{}')
                            + ') return s, r')
        self.assertIsNotNone(site, why)
        self.assertEqual(site.zone, 'DeepForest')

    def test_forest_zone_scan(self):
        found = self.ev('return LivingKnox.Sites.forestZones(GRID)')
        self.assertEqual(found.scanned, 64 * 64)
        self.assertEqual(found.cells, 64 * 64 - 1)  # une cellule manquante (MISSING_CELLS)
        self.assertEqual(found.known, 6)            # 5 cellules approchées + la zone Water de test_rescue (WET)
        self.assertFalse(found.truncated)
        self.assertEqual(sorted(z.type for z in lua_list(found.zones)),
                         ['BirchForest', 'DeepForest', 'DeepForest', 'PHForest'])
        # biome_map_config du jeu relu quand il existe.
        self.rt.execute('biome_map_config = { { pixel = 7, zone = "Marsh" } };'
                        ' ZONES[#ZONES + 1] = { x = 15360, y = 15360, w = 8, h = 8, type = "Marsh" }')
        self.assertEqual(self.ev('return LivingKnox.Sites.forestZones(GRID).known'), 7)
        self.rt.execute('LivingKnox.Sites.CONFIG.MAX_CELLS = 10')
        found = self.ev('return LivingKnox.Sites.forestZones(GRID)')
        self.assertEqual((found.scanned, found.truncated), (10, True))
        site, why = self.pick('raiders', '{ seed = 1, noFallback = true }')
        self.assertIsNone(site)
        self.assertIn('scan truncated', why)

    def test_other_homes_and_bases_keep_camps_away(self):
        first, _ = self.pick('raiders', '{ seed = 5 }')
        for seed in range(1, 31):
            with self.subTest(seed=seed):
                site, why = self.pick('raiders', f'{{ seed = {seed}, homes = {{ {{ x = {first.x}, y = {first.y} }} }},'
                                                 ' avoid = { { x = 7800, y = 2600 } } }')
                self.assertIsNotNone(site, why)
                self.assertGreaterEqual(gap((site.x, site.y, site.x + 1, site.y + 1),
                                            (first.x, first.y, first.x + 1, first.y + 1)), 400)
                self.assertGreaterEqual(gap((site.x, site.y, site.x + 1, site.y + 1), (7800, 2600, 7801, 2601)), 600)

    def test_clearing_draws_are_bounded(self):
        site, why = self.pick('raiders', '{ seed = 2, baseDistance = 1000000, noFallback = true }')
        self.assertIsNone(site)
        self.assertTrue(why.startswith('no suitable clearing after 300 draw(s) in 4 forest zone(s) ('), why)
        self.assertIn('near a known base 300', why)


class FallbackTests(SitesHarness):

    def setUp(self):
        super().setUp()
        self.world(forests=False)

    def test_no_known_forest_falls_back_to_an_isolated_building(self):
        for seed in range(1, 31):
            with self.subTest(seed=seed):
                site, why = self.pick('raiders', f'{{ seed = {seed} }}')
                self.assertIsNotNone(site, why)
                self.assertEqual((site.kind, site.fallback), ('building', 'isolated-building'))
                self.assertTrue(site.fallbackReason.startswith('no forest zone known in the metagrid ('),
                                site.fallbackReason)
                b = site.bounds
                own = (b.x1, b.y1, b.x2, b.y2)
                # Carte clairsemée : un bâtiment sans voisin à 100 cases est trouvé dans le premier tiers des tirages.
                self.assertEqual((site.isolation, site.isolationTier), (100, 100))
                self.assertLessEqual(site.attempts, 100)
                for bx1, by1, bx2, by2, bid in self.buildings():
                    if str(bid) != site.buildingId:
                        self.assertGreaterEqual(gap(own, (bx1, by1, bx2, by2)), 100)
                self.assertGreaterEqual(gap(own, PLAYER), 600)
        self.assertTrue(any('fallback to an isolated building' in line for line in lua_list(self.g.LOGS)))

    def test_no_fallback_option(self):
        site, why = self.pick('raiders', '{ seed = 1, noFallback = true }')
        self.assertIsNone(site)
        self.assertEqual(why, 'no forest zone known in the metagrid (4095 cell(s), 1 known)')  # zone Water de WET

    def test_both_fail(self):
        site, why = self.pick('raiders', '{ seed = 1, baseDistance = 1000000 }')
        self.assertIsNone(site)
        self.assertIn('; fallback: no suitable isolated building after 300 draw(s): ', why)
        self.assertIn('near a known base', why)


def nearest_gap(own, others) -> int:
    """Isolement attendu : écart au plus proche autre bâtiment, plafonné à ISOLATION_RADIUS (100), tronqué."""
    best = 100.0
    for o in others:
        best = min(best, gap(own, o))
    return int(best)


def tier_of(isolation: int) -> int:
    return max([t for t in (100, 60, 30) if isolation >= t], default=0)


class RealisticFallbackTests(SitesHarness):
    """Repli des pillards sur une carte réaliste sans forêt connue (LK08-T08)."""

    def setUp(self):
        super().setUp()
        self.world(realistic=True)

    def others(self, site):
        return [(x1, y1, x2, y2) for x1, y1, x2, y2, bid in self.buildings() if str(bid) != site.buildingId]

    def assert_valid_fallback(self, site):
        b = site.bounds
        own = (b.x1, b.y1, b.x2, b.y2)
        self.assertEqual((site.kind, site.fallback, site.groupType), ('building', 'isolated-building', 'raiders'))
        self.assertGreaterEqual(gap(own, PLAYER), 600)
        self.assertEqual(site.isolation, nearest_gap(own, self.others(site)))
        self.assertEqual(site.isolationTier, tier_of(site.isolation))
        self.assertLessEqual(site.attempts, 300)
        self.assertGreaterEqual(site.candidates, 1)
        # Rendu au palier de son dernier tirage, ou meilleur candidat après tous les tirages.
        tier_now = self.ev(f'return LivingKnox.Sites.tierAt({site.attempts}, 300)')
        self.assertTrue(site.isolation >= tier_now or site.attempts == 300, (site.isolation, site.attempts))
        if site.lair:
            self.assertIn(site.buildingKind, LAIR_KINDS)
        else:
            self.assertNotIn(site.buildingKind, LAIR_KINDS)
        self.assertEqual(self.ev(f'return GRID:getBuildingAt({site.x}, {site.y}, {site.z}):getIDString()'),
                         site.buildingId)

    def test_map_is_as_dense_as_observed(self):
        # Aucun bâtiment de la carte n'a 100 cases d'isolement : l'ancien repli échouait toujours ici.
        rects = [(x1, y1, x2, y2) for x1, y1, x2, y2, _ in self.buildings()]
        self.assertGreater(len(rects), 1500)
        far = [r for r in rects if gap(r, PLAYER) >= 600]
        sample = far[::25]
        self.assertTrue(all(nearest_gap(r, [o for o in rects if o is not r]) < 100 for r in sample))

    def test_raiders_get_a_home_for_every_suite_seed(self):
        seeds = list(SUITE_SEEDS) + [s + 1000 for s in SUITE_SEEDS] + list(range(1, 31))
        sites = []
        for seed in seeds:
            with self.subTest(seed=seed):
                site, why = self.pick('raiders', f'{{ seed = {seed} }}')
                self.assertIsNotNone(site, why)
                self.assertTrue(site.fallbackReason.startswith('no forest zone known in the metagrid ('))
                self.assert_valid_fallback(site)
                again, _ = self.pick('raiders', f'{{ seed = {seed} }}')
                self.assertEqual((again.key, again.attempts, again.isolation), (site.key, site.attempts, site.isolation))
                sites.append(site)
        self.assertGreater(len({s.key for s in sites}), 10)
        # Campagne réaliste : aucun bâtiment à 100 cases, un voisin à 60 cases ou plus trouvé au deuxième tiers.
        self.assertTrue(all(s.isolationTier == 60 and 100 < s.attempts <= 200 for s in sites),
                        [(s.isolation, s.attempts) for s in sites])
        self.assertTrue(any('fallback to an isolated building' in line and 'isolation ' in line
                            for line in lua_list(self.g.LOGS)))

    def test_other_homes_and_suite_reference_seed(self):
        # Contrat de la suite : un second foyer à 400 cases du premier pour la graine de référence.
        first, why = self.pick('raiders', f'{{ seed = {SUITE_SEEDS[0]} }}')
        self.assertIsNotNone(first, why)
        homes = []
        for seed in SUITE_SEEDS:
            site, why = self.pick('raiders', '{ seed = %d, homes = { %s } }'
                                  % (seed, ', '.join(f'{{ x = {h.x}, y = {h.y} }}' for h in homes)))
            self.assertIsNotNone(site, why)
            for h in homes:
                b = site.bounds
                self.assertGreaterEqual(gap((b.x1, b.y1, b.x2, b.y2), (h.x, h.y, h.x + 1, h.y + 1)), 400)
            homes.append(site)

    def test_tiers_are_spread_over_the_draws(self):
        tiers = [self.ev(f'return LivingKnox.Sites.tierAt({a}, 300)') for a in (1, 100, 101, 200, 201, 300)]
        self.assertEqual(tiers, [100, 100, 60, 60, 30, 30])
        self.assertEqual(self.ev('return LivingKnox.Sites.tierAt(7, 7)'), 30)
        self.assertEqual(self.ev('return LivingKnox.Sites.tierAt(1, 7)'), 100)

    def test_stops_at_the_first_tier_reached(self):
        # Huit dépôts sans voisin à 100 cases ajoutés à la carte : trouvés dès le premier tiers des tirages.
        self.rt.execute('LONES = {} for i = 0, 7 do local b = Building({ Room("warehouse", 1000 + i * 1800, 14800, 16, 16) })'
                        ' indexBuilding(b) LONES["b" .. b:getIDString()] = true end finalize()')
        lones = self.g.LONES
        hits = 0
        for seed in range(1, 41):
            site, why = self.pick('raiders', f'{{ seed = {seed} }}')
            self.assertIsNotNone(site, why)
            self.assert_valid_fallback(site)
            if lones[site.key]:
                hits += 1
                self.assertEqual((site.isolation, site.isolationTier, site.lair), (100, 100, True))
                self.assertLessEqual(site.attempts, 100)
            else:
                self.assertLess(site.isolation, 100)
                self.assertGreater(site.attempts, 100)  # palier de 100 jamais atteint par un autre
        self.assertGreater(hits, 0)

    def test_best_candidate_is_kept_when_no_tier_is_reached(self):
        self.rt.execute(
            'SEEN = {} local S = LivingKnox.Sites local old = S.checkBuilding'
            ' S.checkBuilding = function(b, ctx, fb) local s, r = old(b, ctx, fb)'
            ' if s and fb then SEEN[#SEEN + 1] = { key = s.key, isolation = s.isolation } end return s, r end')
        for seed in SUITE_SEEDS:
            with self.subTest(seed=seed):
                self.rt.execute('for i = #SEEN, 1, -1 do SEEN[i] = nil end')
                site, why = self.pick('raiders', f'{{ seed = {seed}, maxAttempts = 20 }}')
                self.assertIsNotNone(site, why)
                cands = [(c.key, c.isolation) for c in lua_list(self.g.SEEN)]
                best = max(i for _, i in cands)
                first_best = next(k for k, i in cands if i == best)
                # Rendu tôt (palier atteint) ou après les 20 tirages : toujours le premier des meilleurs vus.
                self.assertEqual((site.key, site.isolation), (first_best, best))
                self.assertEqual(site.candidates, len(cands))
                self.assertTrue(site.attempts == 20
                                or site.isolation >= self.ev(f'return LivingKnox.Sites.tierAt({site.attempts}, 20)'))

    def test_lairs_admitted_for_raiders_only(self):
        self.rt.execute(
            'BARN = Building({ Room("barn", 9500, 14800, 12, 16) })'
            ' SMALL_SHED = Building({ Room("shed", 9600, 14800, 4, 4), Room("office", 9604, 14800, 3, 3) })'
            ' SHOP = Building({ Room("grocery", 9700, 14800, 12, 10) }) finalize()')
        check = ('local s, r = LivingKnox.Sites.checkBuilding({b}, LivingKnox.Sites.context("{t}", {{}}, GRID), {fb})'
                 ' return s and s.buildingKind, r, s and s.lair, s and s.x, s and s.y')
        kind, why, lair, x, y = self.ev(check.format(b='BARN', t='raiders', fb='true'))
        self.assertEqual((kind, why, lair), ('barn', None, True))
        self.assertTrue(9500 <= x < 9512 and 14800 <= y < 14816)  # point dans la grange
        self.assertEqual(self.ev(check.format(b='SMALL_SHED', t='raiders', fb='true'))[:2],
                         (None, 'lair room too small'))
        self.assertEqual(self.ev(check.format(b='SHOP', t='raiders', fb='true'))[:2],
                         (None, 'neither habitable nor a lair'))
        # Colons, neutres et choix principal : jamais de repaire.
        for t, fb in (('settlers', 'false'), ('neutrals', 'false'), ('raiders', 'false'), ('settlers', 'true')):
            self.assertEqual(self.ev(check.format(b='BARN', t=t, fb=fb))[:2], (None, 'not habitable'), (t, fb))
        # Repli d'un type sans repaire : habitable seulement.
        self.rt.execute('LivingKnox.Sites.LAIR_TYPES.raiders = nil')
        self.assertEqual(self.ev(check.format(b='BARN', t='raiders', fb='true'))[:2], (None, 'not habitable'))

    def test_building_groups_unchanged(self):
        for gtype in ('settlers', 'neutrals'):
            for seed in SUITE_SEEDS:
                site, why = self.pick(gtype, f'{{ seed = {seed} }}')
                self.assertIsNotNone(site, why)
                self.assertIsNone(site.fallback)
                self.assertIsNone(site.isolation)
                self.assertNotIn(site.buildingKind, LAIR_KINDS)

    def test_no_square_read_no_slow_scan(self):
        for seed in SUITE_SEEDS:
            self.pick('raiders', f'{{ seed = {seed} }}')
        c = self.counts()
        self.assertEqual((c['cell'], c['square'], c['slow']), (0, 0, 0))
        self.assertLessEqual(c['get'], 5 * 300)


class TownOnlyFallbackTests(SitesHarness):
    """Villes seules : aucun palier atteint, le meilleur candidat des 300 tirages est rendu."""

    def setUp(self):
        super().setUp()
        self.world(realistic=True, town_only=True)

    def test_best_candidate_after_every_draw(self):
        for seed in SUITE_SEEDS:
            with self.subTest(seed=seed):
                site, why = self.pick('raiders', f'{{ seed = {seed} }}')
                self.assertIsNotNone(site, why)
                self.assertEqual((site.attempts, site.isolationTier), (300, 0))
                self.assertLess(site.isolation, 30)
                self.assertGreater(site.candidates, 50)

    def test_fails_only_when_no_building_keeps_the_distances(self):
        site, why = self.pick('raiders', '{ seed = 11, avoid = { { x = 8000, y = 8000 } }, baseDistance = 20000 }')
        self.assertIsNone(site)
        self.assertIn('; fallback: no suitable isolated building after 300 draw(s): near a known base', why)
        self.assertIn('[LivingKnox] WARN sites: no site for raiders: ', lua_list(self.g.LOGS)[-1])


class NoLoadingTests(SitesHarness):

    def setUp(self):
        super().setUp()
        self.world()

    def test_no_square_read_no_slow_scan_no_write(self):
        for seed in range(1, 21):
            for gtype in ('settlers', 'neutrals', 'raiders'):
                self.pick(gtype, f'{{ seed = {seed} }}')
        self.pick('raiders')
        c = self.counts()
        self.assertEqual((c['cell'], c['square'], c['slow']), (0, 0, 0))
        self.assertGreater(c['zones'], 0)
        self.assertIsNone(self.g.ModData)
        # Seule écriture : celle de Groups.init(true) du banc (aucune par les choix).
        self.assertEqual(len(list(self.g.FILES.keys())), 1)

    def test_seed_is_reproducible(self):
        for gtype in ('settlers', 'raiders'):
            keys = [self.pick(gtype, f'{{ seed = {s} }}')[0].key for s in range(1, 21)]
            again = [self.pick(gtype, f'{{ seed = {s} }}')[0].key for s in range(1, 21)]
            self.assertEqual(keys, again)
            self.assertGreater(len(set(keys)), 3)
        self.assertEqual(self.pick('raiders', '{ seed = "camp-a" }')[0].key,
                         self.pick('raiders', '{ seed = "camp-a" }')[0].key)
        self.assertIsNotNone(self.pick('settlers')[0])  # sans graine : ZombRand

    def test_site_is_plain_data(self):
        for gtype in ('settlers', 'raiders'):
            site, _ = self.pick(gtype, '{ seed = 9 }')
            bad = self.ev('local s = LivingKnox.Sites.pick("' + gtype + '", { seed = 9 })'
                          ' local function plain(v) local t = type(v) if t == "table" then'
                          ' for k, x in pairs(v) do if not plain(k) or not plain(x) then return false end end'
                          ' return true end return t == "string" or t == "number" or t == "boolean" end'
                          ' return plain(s)')
            self.assertTrue(bad, gtype)


class ClientTests(SitesHarness):

    def test_not_loaded_on_an_mp_client(self):
        self.g.SIDE = 'client'
        self.rt.execute(WORLD)
        for name in SHARED:
            self.rt.execute(f'require "{name}"')
        self.rt.execute('require "LivingKnox/LK_Sites"')
        self.assertIsNone(self.ev('return LivingKnox.Sites'))


class SuiteTests(SitesHarness):

    def setUp(self):
        super().setUp()
        self.world()
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE.as_posix()}]])')

    def run_suite(self):
        self.assertTrue(self.ev('RST.start("lk.sites", { attach = false, ctx = { player = PLAYER } })'))
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
        sites = [n for n in notes if n.startswith('site type=')]
        self.assertEqual(len(sites), 15)
        self.assertTrue(any(' clearing ' in n for n in sites), sites)
        self.assertTrue(any(n.startswith('cells with data ') and 'forest zones 4 ' in n for n in notes), notes)
        self.assertEqual(lua_list(self.g.Events.LoadChunk.list), [])  # listener removed

    def test_suite_detects_a_site_near_the_player(self):
        self.rt.execute('local S = LivingKnox.Sites; local old = S.pick;'
                        'S.pick = function(t, o) local s, r = old(t, o); if s and s.kind == "clearing" then'
                        ' s.x, s.y, s.key = 120, 120, "c120_120" end; return s, r end')
        _, results, _ = self.run_suite()
        status, message = results['seeded picks per group type are valid, far from bases and homes, varied and '
                                  'reproducible']
        self.assertEqual(status, 'FAIL')

    def test_suite_detects_a_pick_that_loads_a_chunk(self):
        self.rt.execute('local S = LivingKnox.Sites; local old = S.pick;'
                        'S.pick = function(t, o) local s, r = old(t, o); if s then fire("LoadChunk", fakeChunk(s.x, s.y))'
                        ' end; return s, r end')
        _, results, _ = self.run_suite()
        status, message = results['no chunk is loaded by the picks (LoadChunk, readable squares, streaming)']
        self.assertEqual(status, 'FAIL')
        self.assertIn('LoadChunk fired during the synchronous picks', message)

    def test_suite_detects_a_loaded_site(self):
        self.rt.execute('for _, b in ipairs(BUILDINGS) do STREAMED[b.id] = true end')
        _, results, _ = self.run_suite()
        self.assertEqual(results['no chunk is loaded by the picks (LoadChunk, readable squares, streaming)'][0], 'FAIL')


class RealisticSuiteTests(SuiteTests):
    """Suite lk.sites sur la carte réaliste sans forêt connue (constat en jeu du 2026-10-10 : 3 FAIL)."""

    def setUp(self):
        SitesHarness.setUp(self)
        self.world(realistic=True)
        self.rt.execute('require "RST/RST"')
        self.rt.execute(f'dofile([[{SUITE.as_posix()}]])')

    def test_suite_passes(self):
        report, results, notes = self.run_suite()
        self.assertEqual({k: v for k, v in results.items() if v[0] != 'PASS'}, {})
        self.assertEqual(report.total, 6)
        sites = [n for n in notes if n.startswith('site type=')]
        self.assertEqual(len(sites), 15)
        raiders = [n for n in sites if n.startswith('site type=raiders ')]
        self.assertEqual(len(raiders), 5)
        self.assertTrue(all('FALLBACK isolated-building isolation ' in n and ' tier 60 ' in n for n in raiders),
                        raiders)
        self.assertTrue(any(n.startswith('no forest zone known') for n in notes), notes)

    def test_suite_detects_a_site_near_the_player(self):
        # Sans clairière ici : un foyer de repli déplacé près du joueur doit faire échouer la suite.
        self.rt.execute('local S = LivingKnox.Sites; local old = S.pick;'
                        'S.pick = function(t, o) local s, r = old(t, o); if s and s.fallback then'
                        ' s.x, s.y, s.bounds = 120, 120, { x1 = 118, y1 = 118, x2 = 126, y2 = 126 } end; return s, r end')
        _, results, _ = self.run_suite()
        status, _ = results['seeded picks per group type are valid, far from bases and homes, varied and reproducible']
        self.assertEqual(status, 'FAIL')

    def test_suite_detects_a_wrong_isolation(self):
        self.rt.execute('local S = LivingKnox.Sites; local old = S.pick;'
                        'S.pick = function(t, o) local s, r = old(t, o); if s and s.fallback then'
                        ' s.isolation = s.isolation + 1 end; return s, r end')
        _, results, _ = self.run_suite()
        status, message = results['seeded picks per group type are valid, far from bases and homes, varied and '
                                  'reproducible']
        self.assertEqual(status, 'FAIL')
        self.assertIn('isolation measured again', message)


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

    def test_module_never_loads_nor_writes(self):
        body = '\n'.join(line.split('--')[0] for line in MODULE.read_text(encoding='utf-8').splitlines())
        for forbidden in ('getGridSquare', 'LoadChunk', 'getChunk', 'getCell(', 'getZonesAt', 'ModData',
                          'sendServerCommand', 'sendClientCommand', 'getFileWriter', 'setHome', 'getBuildingAt'):
            self.assertNotIn(forbidden, body)
        self.assertTrue(body.lstrip().startswith('if isClient() then return end'))


if __name__ == '__main__':
    unittest.main(verbosity=1)
