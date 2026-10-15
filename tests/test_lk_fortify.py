"""Tests hors jeu du plan de fortification des foyers Living Knox (LK14-T02) : server/LivingKnox/LK_Fortify.lua et son
branchement dans le cadre de décision (LK_Decisions : fortificationOf, fortifyWorkOf, scoreObjectives).

    python RadioSurvivor/tests/test_lk_fortify.py

Banc tests/harness.py (solo, ou serveur + deux clients) avec le vrai registre des groupes (LK_Groups) et LK_Homes
(Homes.ready). Doublures relevées dans le Java et les scripts vanilla 42.21.0 :
- bâtiments = rectangles BUILDINGS { x1, y1, x2, y2 (inclus), id, niveau max } (BuildingDef.getX/getY, getX2/getY2 à
  fin exclusive, getMaxLevel, getIDString, isFullyStreamedIn, getRooms ; IsoGridSquare.getBuildingDef par la pièce) ;
- ouvertures posées sur la case dont elles sont le bord nord ou ouest (getNorth) : IsoDoor, IsoWindow,
  IsoWindowFrame, IsoThumpable ; interface BarricadeAble (J/iso/objects/interfaces/BarricadeAble.java) :
  isBarricadeAllowed (porte double ou de garage : faux, IsoDoor.java:1699-1701 ; cadre qui porte une fenêtre : faux,
  IsoWindowFrame.java:104-106), getBarricadeOnSameSquare / getBarricadeOnOppositeSquare ; IsoBarricade getNumPlanks,
  isMetal, isMetalBar ;
- ouvrages : IsoThumpable nommé (getName = nom de l'entité : WoodenWallFrame, WoodenWallLvl1, LogWall) ;
- cases : isFree(false), isWaterSquare, HasStairs, isBlockedTo (bords fermés CLOSED) ; zone non chargée à partir de
  UNLOADED_X ;
- stock : doublure de LivingKnox.Stock (reference : objets { i, t, c } ; findItem(gid, pred)) et ItemTag.HAMMER,
  InventoryItem.hasTag(ItemTag) (api-42-21.md).
Elles NE PROUVENT PAS l'API réelle, seulement la logique (cible hors jeu ; la pose est LK14-T03/T04).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Harness  # noqa: E402

SHARED = ('shared/LivingKnox/LK_Core.lua', 'shared/LivingKnox/LK_Config.lua', 'shared/LivingKnox/LK_Log.lua',
          'shared/LivingKnox/Data/LK_Type_neutrals.lua', 'shared/LivingKnox/Data/LK_Type_raiders.lua',
          'shared/LivingKnox/Data/LK_Type_settlers.lua')
SERVER = 'server/LivingKnox/LK_Server.lua'
HOMES = 'server/LivingKnox/LK_Homes.lua'
MODULE = 'server/LivingKnox/LK_Fortify.lua'
FT = 'LivingKnox.Fortify'

DOUBLES = r'''
WORLD_NAME, GAME_MODE = 'rstest_fortify', 'Multiplayer'
getWorld = function()
    return { getWorld = function() return WORLD_NAME end, getGameMode = function() return GAME_MODE end }
end
local H = HARNESS
local C = H.classes

-- Bâtiments ----------------------------------------------------------------------------------------------------------
BUILDINGS = {}
local Def = H.class('BuildingDef')
function Def:getIDString() return tostring(self.b[5]) end
function Def:isFullyStreamedIn() return true end
function Def:getRooms() return H.list({}) end
function Def:getX() return self.b[1] end
function Def:getY() return self.b[2] end
function Def:getX2() return self.b[3] + 1 end
function Def:getY2() return self.b[4] + 1 end
function Def:getMaxLevel() return self.b[6] or 0 end
local function buildingAt(x, y, z)
    for _, b in ipairs(BUILDINGS) do
        if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] and z >= 0 and z <= (b[6] or 0) then return b end
    end
    return nil
end
local Sq = C.IsoGridSquare
function Sq:getBuildingDef()
    local b = buildingAt(self.x, self.y, self.z)
    return b and setmetatable({ b = b }, Def) or nil
end
function Sq:getRoom() return buildingAt(self.x, self.y, self.z) and { id = 1 } or nil end
function Sq:HasStairs() return self.stairs == true end
function Sq:isWaterSquare() return self.water == true end
function Sq:hasBush() return false end
function Sq:getWorldObjects() return H.list() end
CLOSED = {}
function Sq:isBlockedTo(o)
    return CLOSED[self.x .. ',' .. self.y .. '|' .. o.x .. ',' .. o.y] == true
        or CLOSED[o.x .. ',' .. o.y .. '|' .. self.x .. ',' .. self.y] == true
end
local Cell = getmetatable(getCell())
local get = Cell.getGridSquare
UNLOADED_X = nil
function Cell:getGridSquare(x, y, z)
    if UNLOADED_X ~= nil and x >= UNLOADED_X then return nil end
    return get(self, x, y, z)
end
function TREE(x, y) H.square(x, y, 0).blocked = true end

-- Ouvertures et barricades -------------------------------------------------------------------------------------------
local Barricade = H.class('IsoBarricade', C.IsoObject)
function Barricade:getNumPlanks() return self.planks end
function Barricade:isMetal() return self.metal == true end
function Barricade:isMetalBar() return false end
function Barricade:getThumpCondition() return self.cond or 1 end   -- LK14-T06 : planche extérieure
local function edgeClass(name)
    local cls = H.class(name, C.IsoObject)
    function cls:getNorth() return self.north end
    function cls:isBarricadeAllowed() return self.allowed ~= false end
    function cls:getBarricadeOnSameSquare() return self.own end
    function cls:getBarricadeOnOppositeSquare() return self.opp end
    function cls:getName() return self.name end
    function cls:IsOpen() return self.open == true end   -- LK14-T05 : porte ouverte écartée du relevé hors écran
    return cls
end
local Door, Window, Frame = edgeClass('IsoDoor'), edgeClass('IsoWindow'), edgeClass('IsoWindowFrame')
local Thump = edgeClass('IsoThumpable')
function Thump:isDoor() return self.door == true end
function Thump:getHealth() return self.health or 100 end   -- LK14-T06 : santé des ouvrages
function Thump:getMaxHealth() return self.maxHealth or 100 end
local CLASSES = { door = Door, window = Window, frame = Frame, thump = Thump }
-- Objet de bord sur la case (x, y, z), face nord (north) ou ouest.
function EDGE(cls, x, y, z, north, fields)
    local o = setmetatable(fields or {}, CLASSES[cls])
    o.north = north
    H.addObject(x, y, z, o)
    return o
end
function BARR(o, side, planks, metal)
    o[side] = setmetatable({ planks = planks, metal = metal == true }, Barricade)
    return o[side]
end

-- Stock du foyer (doublure de LivingKnox.Stock) ----------------------------------------------------------------------
ItemTag = { HAMMER = { name = 'base:hammer' } }
local Item = H.class('InventoryItem')
function Item:hasTag(tag)
    if type(tag) ~= 'table' then error('No implementation found for InventoryItem.hasTag', 2) end
    return self.tag == tag
end
STOCK_ITEMS, TOOLS = {}, {}
function STOCK(list)
    STOCK_ITEMS = {}
    for _, e in ipairs(list) do
        for _ = 1, e[2] do STOCK_ITEMS[#STOCK_ITEMS + 1] = { i = #STOCK_ITEMS + 1, t = e[1], c = 'materials' } end
    end
end
function HAMMER(on) TOOLS = on and { setmetatable({ tag = ItemTag.HAMMER }, Item) } or {} end
STUB_STOCK = {
    reference = function(gid) return { items = STOCK_ITEMS } end,
    findItem = function(gid, pred)
        for _, it in ipairs(TOOLS) do
            if pred(it) then return { t = 'Base.Hammer' }, it end
        end
        return nil, 'none'
    end,
}
'''

# Maison de test : bâtiment 7 (100..110 x 100..108, un étage), foyer (103, 104, 0). Une ligne Lua par objet : l'ordre
# d'insertion est inversé dans le test de reproductibilité.
HOUSE = [
    'BUILDINGS[#BUILDINGS + 1] = { 100, 100, 110, 108, 7, 1 }',
    'BUILDINGS[#BUILDINGS + 1] = { 120, 100, 125, 105, 8, 0 }',            # voisin : jamais dans le plan
    'ENTRY = EDGE("door", 100, 104, 0, false)',                             # porte ouest : entrée (la plus proche)
    'BACK = EDGE("door", 111, 106, 0, false)',                              # porte est (côté dehors porte l'objet)
    'WN1 = EDGE("window", 101, 100, 0, true)',
    'WN2 = EDGE("window", 106, 100, 0, true)',
    'WE = EDGE("window", 111, 104, 0, false)',
    'FRAME = EDGE("frame", 104, 109, 0, true)',                             # cadre vide au sud
    'EDGE("frame", 101, 100, 0, true, { allowed = false })',                # cadre de la fenêtre WN1 : ignoré
    'GARAGE = EDGE("door", 108, 109, 0, true, { allowed = false })',        # porte de garage : non barricadable
    'WS = EDGE("window", 102, 109, 0, true) BARR(WS, "own", 2)',            # 2 planches déjà posées dehors
    'WM = EDGE("window", 100, 102, 0, false) BARR(WM, "opp", 1, true)',     # tôle : faite
    'UP = EDGE("window", 101, 100, 1, true)',                               # étage
    'EDGE("window", 120, 102, 0, false)',                                   # fenêtre du voisin
    'EDGE("thump", 98, 101, 0, false, { name = "WoodenWallFrame" })',       # cadre de mur déjà posé (côté ouest)
    'TREE(105, 98)',                                                        # arbre sur le pourtour nord
]


class Base(unittest.TestCase):
    mode = 'solo'
    stub_stock = True

    def setUp(self):
        self.h = Harness(mode=self.mode)
        self.srv = 'solo' if self.mode == 'solo' else 'server'
        machines = ('solo',) if self.mode == 'solo' else ('server', 'A', 'B')
        for m in machines:
            self.h.load(m, DOUBLES)
            for path in SHARED:
                self.h.load(m, path)
            self.h.load(m, SERVER)
            self.h.load(m, HOMES)
            self.h.load(m, MODULE)
        if self.stub_stock:
            self.run_lua('LivingKnox.Stock = STUB_STOCK')
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

    def sites(self, gid):
        """Chantiers du plan : liste de tuples (rang, id, tier, have, steps)."""
        plan = self.ev(f'{FT}.plan("{gid}", {{ force = true }})')
        self.assertIsNotNone(plan)
        return [(s.rank, s.id, s.tier, s.have, s.steps) for s in plan.sites.values()]

    def duty(self, gid, mids):
        lua = 'LivingKnox.Groups.update(function(data) local g = data.groups["%s"] ' % gid
        for mid in mids:
            lua += 'g.members["%s"].duty = "builder" ' % mid
        self.run_lua(lua + 'return true, true end)')


class BuildingTests(Base):
    def setUp(self):
        super().setUp()
        self.run_lua('\n'.join(HOUSE))
        self.gid = self.group()

    def test_priority_order_and_entry_left_free(self):
        sites = self.sites(self.gid)
        ground = [s[1] for s in sites if s[2] == 'ground']
        self.assertEqual(ground, [
            'barricade:104,109,0N',   # cadre vide d'abord
            'barricade:111,104,0W',   # fenêtres : la plus éloignée du foyer d'abord
            'barricade:101,100,0N', 'barricade:106,100,0N', 'barricade:102,109,0N',
            'barricade:100,102,0W',   # tôle : faite, gardée dans le plan
            'barricade:111,106,0W',   # porte de derrière en dernier
        ])
        self.assertEqual([s[1] for s in sites if s[2] == 'upper'], ['barricade:101,100,1N'])
        self.assertEqual([s[0] for s in sites], list(range(1, len(sites) + 1)))
        tiers = [s[2] for s in sites]
        self.assertEqual(tiers, sorted(tiers, key=['ground', 'upper', 'outer'].index))
        plan = self.ev(f'{FT}.plan("{self.gid}")')
        self.assertEqual((plan.entry.x, plan.entry.y, plan.entry.north), (100, 104, False))
        ids = [s[1] for s in sites]
        self.assertNotIn('barricade:100,104,0W', ids)            # entrée libre
        self.assertNotIn('barricade:108,109,0N', ids)            # porte de garage
        self.assertEqual([(k.x, k.y, k.why) for k in plan.skipped.values() if k.why == 'not barricadable'],
                         [(108, 109, 'not barricadable')])

    def test_materials_tools_and_time(self):
        plan = self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        by = {s.id: s for s in plan.sites.values()}
        frame = by['barricade:104,109,0N']
        self.assertEqual((frame.opening, frame.have, frame.steps, frame.time, frame.done, frame.entity),
                         ('frame', 0, 4, 800, False, 'BarricadePlanks'))
        self.assertFalse(frame.opp)                      # cadre porté par la case extérieure (104,109)
        self.assertEqual((frame.outside.x, frame.outside.y, frame.inside.x, frame.inside.y), (104, 109, 104, 108))
        mats = [(list(r.types.values()), r.n) for r in frame.materials.values()]
        self.assertEqual(mats, [(['Base.Plank'], 4), (['Base.Nails'], 4)])
        self.assertEqual(list(frame.tools.values()), ['HAMMER'])
        ws = by['barricade:102,109,0N']
        self.assertEqual((ws.have, ws.time, [r.n for r in ws.materials.values()]), (2, 400, [2, 2]))
        wn1 = by['barricade:101,100,0N']
        self.assertTrue(wn1.opp)                         # objet sur la case intérieure : barricade en face
        wm = by['barricade:100,102,0W']
        self.assertEqual((wm.done, wm.have, wm.time, len(list(wm.materials.values()))), (True, 4, 0, 0))
        up = by['barricade:101,100,1N']
        self.assertEqual((up.steps, up.time), (2, 400))
        # Pourtour : murs en bois (cadre + mur), le cadre déjà posé ne demande que le mur.
        wall = by['wall:98,100,0W']
        self.assertEqual((wall.have, wall.steps, wall.time, [r.n for r in wall.materials.values()]),
                         (0, 2, 400, [4, 6]))
        self.assertEqual(list(wall.entity.values()), ['WoodenWallFrame', 'WoodenWallLvl1'])
        built = by['wall:98,101,0W']
        self.assertEqual((built.have, built.time, [r.n for r in built.materials.values()]), (1, 200, [2, 4]))

    def test_ring_gap_and_skipped_segments(self):
        plan = self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        outer = [s for s in plan.sites.values() if s.tier == 'outer']
        # Rectangle 98..112 x 98..110 : 15 + 13 + 15 + 13 = 56 segments, 3 laissés en brèche, 1 sous un arbre.
        self.assertEqual(len(outer), 52)
        self.assertTrue(all(s.kind == 'wall' for s in outer))
        self.assertEqual(sorted((g.x, g.y, g.north) for g in plan.gaps.values()),
                         [(98, 103, False), (98, 104, False), (98, 105, False)])   # en face de l'entrée ouest
        self.assertIn((105, 98, 'ground'), [(k.x, k.y, k.why) for k in plan.skipped.values()])
        self.assertEqual((plan.bounds.x1, plan.bounds.y1, plan.bounds.x2, plan.bounds.y2), (97, 97, 113, 111))

    def test_no_site_outside_the_home(self):
        plan = self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        b = plan.bounds
        for s in plan.sites.values():
            with self.subTest(site=s.id):
                self.assertTrue(b.x1 <= s.x <= b.x2 and b.y1 <= s.y <= b.y2)
                self.assertTrue(b.x1 <= s.outside.x <= b.x2 and b.y1 <= s.outside.y <= b.y2)
                if s.kind == 'barricade':
                    inside = self.ev(f'getCell():getGridSquare({s.inside.x}, {s.inside.y}, {s.z}):getBuildingDef()'
                                     ':getIDString()')
                    self.assertEqual(inside, '7')
                    self.assertIsNone(self.ev(f'getCell():getGridSquare({s.outside.x}, {s.outside.y}, {s.z})'
                                              ':getBuildingDef()'))
                else:
                    self.assertIsNone(self.ev(f'getCell():getGridSquare({s.x}, {s.y}, 0):getBuildingDef()'))
        self.assertFalse(any(s.x >= 120 for s in plan.sites.values()))   # bâtiment voisin

    def test_level_weighted_by_tier(self):
        # Rez-de-chaussée 6/28 étapes, étage 0/2, pourtour 1/104 : 100 x (3 x 6/28 + 2 x 1/104) / 6 = 11.
        self.assertEqual(self.ev(f'{FT}.levelOf("{self.gid}")'), 11)
        self.assertEqual(self.ev('LivingKnox.Decisions.fortificationOf("%s")' % self.gid), 11)
        # Toutes les ouvertures en tôle : 100 x (3 + 1 + 2 x 1/104) / 6 = 67.
        self.run_lua('for _, o in ipairs({ BACK, WN1, WN2, WE, FRAME, WS, UP }) do BARR(o, "own", 1, true) end')
        self.assertEqual(self.ev(f'{FT}.plan("{self.gid}", {{ force = true }}).level'), 67)
        self.assertEqual(self.ev(f'{FT}.levelOfSites({{}})'), 100)

    def test_plan_is_reproducible(self):
        first = self.sites(self.gid)
        key = self.ev(f'{FT}.plan("{self.gid}").key')
        self.assertEqual(self.sites(self.gid), first)
        self.assertEqual(self.ev(f'{FT}.plan("{self.gid}", {{ force = true }}).key'), key)
        # Même monde construit dans l'ordre inverse, dans un autre banc : même plan.
        other = Base('run')
        other.setUp()
        try:
            other.run_lua('\n'.join(reversed(HOUSE)))
            gid = other.group()
            self.assertEqual(other.sites(gid), first)
            self.assertEqual(other.ev(f'{FT}.plan("{gid}").key'), key)
        finally:
            other.tearDown()

    def test_plan_logged_once_and_follows_world_changes(self):
        self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        lines = [ln for ln in self.lk() if 'fortify: group grp-1 plan (building)' in ln]
        self.assertEqual(len(lines), 1, self.lk())
        self.assertIn('60 site(s), 59 to do (ground 6, upper 1, outer 52), 3 gap(s), 2 skipped, level 11', lines[0])
        self.run_lua('BARR(FRAME, "own", 4)')
        self.assertEqual(self.ev(f'{FT}.plan("{self.gid}", {{ force = true }}).todo'), 58)
        self.assertEqual(len([ln for ln in self.lk() if 'fortify: group grp-1 plan' in ln]), 2)

    def test_unloaded_area_keeps_last_plan(self):
        self.run_lua('UNLOADED_X = 113')
        plan = self.ev(f'({FT}.plan("{self.gid}", {{ force = true }}))')
        self.assertIsNone(plan)
        self.assertIsNone(self.ev(f'{FT}.levelOf("{self.gid}")'))
        self.assertIsNone(self.ev(f'{FT}.hasWork("{self.gid}")'))
        self.assertIsNone(self.ev('LivingKnox.Decisions.fortificationOf("%s")' % self.gid))
        self.run_lua('UNLOADED_X = nil')
        self.assertEqual(self.ev(f'{FT}.levelOf("{self.gid}")'), 11)
        self.run_lua('UNLOADED_X = 113')
        stale = self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        self.assertTrue(stale.stale)
        self.assertEqual(stale.level, 11)

    def test_large_building_has_no_outer_ring(self):
        self.run_lua(f'{FT}.CFG.MAX_OUTER = 40')
        plan = self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        self.assertEqual(len([s for s in plan.sites.values() if s.tier == 'outer']), 0)
        self.assertEqual(plan.outerSkipped, 'ring of 56 segment(s) over 40')
        self.run_lua(f'{FT}.CFG.MAX_OUTER = 96')

    def test_feasible_sites_reserve_materials_in_order(self):
        self.run_lua('STOCK({ { "Base.Plank", 6 }, { "Base.NailsBox", 1 } }) HAMMER(true)')
        got = [s.id for s in self.ev(f'{FT}.feasible("{self.gid}")').values()]
        # Cadre vide (4 planches), puis seule la fenêtre à 2 planches tient dans les 2 restantes.
        self.assertEqual(got, ['barricade:104,109,0N', 'barricade:102,109,0N'])
        self.assertTrue(self.ev(f'{FT}.hasWork("{self.gid}")'))
        self.run_lua('HAMMER(false)')
        self.assertEqual(len(list(self.ev(f'{FT}.feasible("{self.gid}")').values())), 0)
        self.assertFalse(self.ev(f'{FT}.hasWork("{self.gid}")'))
        self.run_lua('HAMMER(true) STOCK({ { "Base.Plank", 6 } })')   # pas de clous
        self.assertFalse(self.ev(f'{FT}.hasWork("{self.gid}")'))

    def test_builders_get_distinct_sites(self):
        self.run_lua('STOCK({ { "Base.Plank", 6 }, { "Base.Nails", 10 } }) HAMMER(true)')
        mids = [m for m in self.ev(f'LivingKnox.Groups.get("{self.gid}").members').keys()]
        mids.sort(key=lambda m: int(m.split('-')[1]))
        self.assertEqual(self.ev(f'select(2, {FT}.siteFor("{self.gid}", "{mids[0]}"))'), 'not a builder')
        self.duty(self.gid, mids[:3])
        first = self.ev(f'{FT}.siteFor("{self.gid}", "{mids[0]}")')
        second = self.ev(f'{FT}.siteFor("{self.gid}", "{mids[1]}")')
        self.assertEqual((first.id, second.id), ('barricade:104,109,0N', 'barricade:102,109,0N'))
        self.assertEqual(self.ev(f'select(2, {FT}.siteFor("{self.gid}", "{mids[2]}"))'), 'nothing feasible')


class CampTests(Base):
    def setUp(self):
        super().setUp()
        self.gid = self.group('raiders', home=(200, 200, 0), members=3, name='Crows')

    def test_camp_gets_a_log_palisade_with_a_south_gap(self):
        plan = self.ev(f'{FT}.plan("{self.gid}", {{ force = true }})')
        self.assertEqual(plan.style, 'camp')
        self.assertIsNone(plan.entry)
        sites = list(plan.sites.values())
        self.assertEqual(len(sites), 57)   # 15 x 4 segments, 3 en brèche
        self.assertTrue(all(s.kind == 'palisade' and s.tier == 'outer' for s in sites))
        self.assertEqual(sorted((g.x, g.y, g.north) for g in plan.gaps.values()),
                         [(199, 208, True), (200, 208, True), (201, 208, True)])
        s = sites[0]
        self.assertEqual((s.entity, s.time, len(list(s.tools.values()))), ('LogWall', 200, 0))
        mats = [(list(r.types.values()), r.n) for r in s.materials.values()]
        self.assertEqual(mats, [(['Base.Log'], 4), (['Base.RippedSheets', 'Base.RippedSheetsDirty', 'Base.Twine',
                                                     'Base.Rope', 'Base.SheetRope'], 4)])
        self.assertEqual(plan.level, 0)
        # Liens de plusieurs sortes : un seul chantier faisable avec 8 rondins et 4 liens, sans outil.
        self.run_lua('STOCK({ { "Base.Log", 8 }, { "Base.Rope", 2 }, { "Base.Twine", 2 } })')
        self.assertEqual([x.id for x in self.ev(f'{FT}.feasible("{self.gid}")').values()], [sites[0].id])


class DecisionTests(Base):
    def score(self, extra):
        base = ('{ gidNumber = 1, day = 1, night = false, needs = { food = 80, water = 80, medical = 80, ammo = 80 }, '
                'rest = 80, worstWound = 0, hostility = 0, traits = {}, fortification = 40, ' + extra + ' }')
        return self.ev(f'LivingKnox.Decisions.scoreObjectives({base}).scores.fortify')

    def test_fortify_score_follows_stock_and_threats(self):
        self.run_lua('LivingKnox.Decisions.CFG.JITTER = 0')
        self.assertEqual(self.score('threats = 0'), 30)                       # inconnu : comme avant
        self.assertEqual(self.score('threats = 0, fortWork = false'), 0)      # rien de faisable
        self.assertEqual(self.score('threats = 3, fortWork = false'), 0)
        self.assertEqual(self.score('threats = 3, fortWork = true'), 45)      # 30 + 3 x 5
        self.assertEqual(self.score('threats = 9, fortWork = true'), 50)      # plafond 20
        self.assertEqual(self.score('threats = 3'), 30)                       # sans plan : pas de bonus

    def test_group_input_reads_level_and_work(self):
        self.run_lua('\n'.join(HOUSE))
        gid = self.group()
        self.run_lua('STOCK({ { "Base.Plank", 4 }, { "Base.Nails", 4 } }) HAMMER(true)')
        gin = self.ev(f'LivingKnox.Decisions.groupInput("{gid}", LivingKnox.Groups.get("{gid}"), 30)')
        self.assertEqual((gin.fortification, gin.fortWork), (11, True))
        self.run_lua('STOCK({})')
        gin = self.ev(f'LivingKnox.Decisions.groupInput("{gid}", LivingKnox.Groups.get("{gid}"), 30)')
        self.assertEqual(gin.fortWork, False)


class MultiplayerTests(Base):
    mode = 'mp'

    def test_server_only(self):
        self.run_lua('\n'.join(HOUSE))
        gid = self.group()
        self.assertEqual(self.ev(f'{FT}.levelOf("{gid}")'), 11)
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, FT))
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Fortification'))


if __name__ == '__main__':
    unittest.main()
