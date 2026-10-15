"""Tests hors jeu des murs et palissades posés par les PNJ Living Knox (LK14-T04) : server/LivingKnox/LK_Fortify.lua
(Fortify.buildStep, placeStructure, entityInfo, healthOf ; Fortify.run pour un chantier du pourtour), branché dans
LK_Routines.lua (comportement « chore » d'un membre de poste « builder »), matériaux pris par LK_Stock.lua (findItem,
takeItem, check), et la suite en jeu lk.walls (dev/.../RST_LKWalls.lua).

    python RadioSurvivor/tests/test_lk_walls.py

Banc : pile de test_lk_barricade.py (groupe « deciders » dans la maison HOUSE 105..115, foyer 110,110, vrais LK_Homes
et LK_Stock, foyer aménagé sans pose par LivingKnox.Homes.skip, ouvrier m-2 au poste « builder ») sans les deux
fenêtres : seule la porte d'entrée sud (110,116) reste, le plan ne contient donc que le pourtour (murs en bois à
2 cases du bâtiment, rectangle 103..117, brèche de 3 segments au sud en face de l'entrée).
Doublures ajoutées, relevées dans le Java et le Lua vanilla 42.21.0 :
- IsoThumpable.new(cell, sq, sprite, north, table) (J/iso/objects/IsoThumpable.java:395-416 ; table nil admise :
  buildUtil.addCorner), getProperties() selon les propriétés de tuile (M/newtiledefinitions.tiles.txt : cadre
  carpentry_02_100/101 HoppableW/N, mur walls_exterior_wooden_01_44/45 WallW/N, palissade carpentry_02_80/81
  TallHoppableW/N + WallW/N, poteau _27 WallSE), getName, getNorth, isCorner, santé, transmitCompleteItemToClients
  (compté sur le serveur seulement, IsoObject.java:4265-4272) ;
- buildUtil.setInfo (setters de M/lua/server/BuildingObjects/ISBuildUtil.lua:362-393, booléens exigés) et
  buildUtil.addCorner (:86-99 : poteau neuf posé, recalculé, transmis) ;
- SpriteConfigManager.getObjectInfoFromSprite (J/entity/components/spriteconfig/SpriteConfigManager.java:86-90) :
  fiche d'entité (nom, script SpriteConfig : santé, skillBaseHealth, bonus, son de bris, poteau, isThumpable défaut
  vrai, SpriteConfigScript.java:34 ; recette : niveaux requis) des scripts M/scripts/generated/entities/walls ;
- GameEntityFactory.CreateIsoObjectEntity ; getSandboxOptions():getOptionByName("ConstructionBonusPoints") ;
- IsoGridSquare : AddSpecialObject(obj, index), getSpecialObjects, transmitRemoveItemFromSquare (serveur : retrait
  transmis, IsoGridSquare.java:5072-5099), RecalcAllWithNeighbours, getWallFull (WallN/WallW seulement,
  IsoGridSquare.java:3873-3880).
Elles NE PROUVENT PAS l'API réelle ni le rendu : seulement la logique (étapes cadre puis mur, matériaux retirés une
seule fois, boîte de clous ouverte une fois, brèche et entrée libres, aucun segment hors du plan, poteau d'angle unique,
transmissions faites par le serveur seul).
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_barricade import BARRICADE_DOUBLES, FORTIFY, F, R, ST  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_meals import MealStack  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SUITE = 'shared/RST/suites/RST_LKWalls.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE

WALL_DOUBLES = r'''
local H = HARNESS
local C = H.classes
IsoFlagType = IsoFlagType or {}
for _, k in ipairs({ 'solid', 'solidtrans', 'doorN', 'doorW', 'WallN', 'WallNTrans', 'WallW', 'WallWTrans', 'WallNW',
    'HoppableN', 'HoppableW', 'TallHoppableN', 'TallHoppableW', 'solidfloor', 'WallSE' }) do
    IsoFlagType[k] = IsoFlagType[k] or k
end
IsoPropertyType = IsoPropertyType or {}
IsoPropertyType.BLOCKS_PLACEMENT = IsoPropertyType.BLOCKS_PLACEMENT or 'BlocksPlacement'
-- Propriétés des tuiles vanilla (newtiledefinitions.tiles.txt).
TILE_PROPS = {
    carpentry_02_100 = { HoppableW = true }, carpentry_02_101 = { HoppableN = true },
    walls_exterior_wooden_01_44 = { WallW = true }, walls_exterior_wooden_01_45 = { WallN = true },
    carpentry_02_80 = { TallHoppableW = true, WallW = true }, carpentry_02_81 = { TallHoppableN = true, WallN = true },
    walls_exterior_wooden_01_27 = { WallSE = true },
}
local Props = H.class('PropertyContainer')
function Props:has(f)
    if f == nil then error('No implementation found for has', 2) end
    return self.p[f] == true
end
WALL = { sent = 0, removed = 0, recalc = 0, entities = 0 }
WALL_SENT = {}
local T = C.IsoThumpable or H.class('IsoThumpable', C.IsoObject)
IsoThumpable = { new = function(cell, sq, sprite, north, tbl)
    if type(sprite) ~= 'string' or type(north) ~= 'boolean' or (tbl ~= nil and type(tbl) ~= 'table') then
        error('No implementation found for IsoThumpable.new', 2)
    end
    if TILE_PROPS[sprite] == nil then error('unknown sprite ' .. sprite, 2) end
    return setmetatable({ sprite = sprite, north = north, tbl = tbl, square = sq, health = 500, maxHealth = 500 }, T)
end }
function T:getSprite() return { getName = function() return self.sprite end } end
function T:getProperties() return setmetatable({ p = TILE_PROPS[self.sprite] }, Props) end
function T:getNorth() return self.north == true end
function T:getName() return self.name end
function T:setName(n) self.name = n end
function T:isCorner() return self.corner == true end
function T:setCorner(b) self.corner = b end
function T:setCanBarricade(b) self.canBarricade = b end
function T:setCanBePlastered(b) self.canBePlastered = b end
function T:isBarricadeAllowed() return false end
function T:getMaxHealth() return self.maxHealth end
function T:setMaxHealth(h) if type(h) ~= 'number' then error('No implementation found for setMaxHealth', 2) end self.maxHealth = h end
function T:getHealth() return self.health end
function T:setHealth(h)
    if self.placed then error('setHealth after the object is placed (sync)', 2) end
    self.health = h
end
function T:setBreakSound(s) self.breakSound = s end
function T:setExplored(b) self.explored = b end
function T:transmitCompleteItemToClients()
    if isServer() then
        WALL.sent = WALL.sent + 1
        WALL_SENT[#WALL_SENT + 1] = 'new ' .. tostring(self.name or 'corner') .. ' ' .. self.x .. ',' .. self.y
            .. (self.north and 'N' or 'W')
    end
end
-- buildUtil (ISBuildUtil.lua:362-393, 86-99).
local BOOLS = { 'canPassThrough', 'canBarricade', 'isContainer', 'isDoor', 'isDoorFrame', 'blockAllTheSquare',
    'dismantable', 'canBePlastered', 'hoppable', 'isThumpable', 'isFloor' }
buildUtil.setInfo = function(o, item)
    for _, k in ipairs(BOOLS) do
        if type(item[k]) ~= 'boolean' then error('No implementation found for set ' .. k .. ' (' .. tostring(item[k]) .. ')', 2) end
        o[k] = item[k]
    end
    if type(item.thumpDmg) ~= 'number' or type(item.crossSpeed) ~= 'number' or type(item.name) ~= 'string' then
        error('bad setInfo item', 2)
    end
    o.thumpDmg, o.crossSpeed, o.name, o.md = item.thumpDmg, item.crossSpeed, item.name, item.modData
end
buildUtil.addCorner = function(x, y, z, thumpable, item)
    if item.corner ~= nil then
        local sq = getCell():getGridSquare(x, y, z)
        local corner = IsoThumpable.new(getCell(), sq, item.corner, false, nil)
        corner:setCorner(true)
        corner:setCanBarricade(false)
        corner:setCanBePlastered(true)
        sq:AddSpecialObject(corner)
        sq:RecalcAllWithNeighbours(true)
        corner:transmitCompleteItemToClients()
    end
end
-- Fiches d'entité (scripts M/scripts/generated/entities/walls).
local function info(name, health, skill, level, breakSound, corner)
    local script = { getHealth = function() return health end, getSkillBaseHealth = function() return skill end,
        getBonusHealth = function() return 0 end, getBreakSound = function() return breakSound end,
        getCornerSprite = function() return corner end, getIsThumpable = function() return true end,
        getParent = function() return { entity = name } end }
    local skills = level > 0 and { { getPerk = function() return 'Woodwork' end, getLevel = function() return level end } }
        or {}
    local recipe = { getRequiredSkillCount = function() return #skills end,
        getRequiredSkill = function(_, i) return skills[i + 1] end }
    return { getName = function() return name end, getScript = function() return script end,
        getRecipe = function() return { getCraftRecipe = function() return recipe end } end }
end
local CORNER = 'walls_exterior_wooden_01_27'
local FRAME = info('WoodenWallFrame', 50, 20, 2, nil, CORNER)
local WALLI = info('WoodenWallLvl1', 450, 20, 2, 'ZombieThumpWoodCollapse', CORNER)
local LOGW = info('LogWall', 500, 50, 0, nil, nil)
INFOS = { carpentry_02_100 = FRAME, carpentry_02_101 = FRAME, walls_exterior_wooden_01_44 = WALLI,
    walls_exterior_wooden_01_45 = WALLI, carpentry_02_80 = LOGW, carpentry_02_81 = LOGW }
SpriteConfigManager = { getObjectInfoFromSprite = function(s)
    if type(s) ~= 'string' then error('No implementation found for getObjectInfoFromSprite', 2) end
    return INFOS[s]
end }
GameEntityFactory = { CreateIsoObjectEntity = function(o, script, first)
    if type(script) ~= 'table' or first ~= true then error('No implementation found for CreateIsoObjectEntity', 2) end
    o.entity = script.entity
    WALL.entities = WALL.entities + 1
end }
BONUS = 3
getSandboxOptions = function() return { getOptionByName = function(_, n)
    if n == 'ConstructionBonusPoints' then return { getValue = function() return BONUS end } end
    return nil
end } end
-- Cases.
local Sq = C.IsoGridSquare
function Sq:AddSpecialObject(o, index)
    o.square, o.x, o.y, o.z = self, self.x, self.y, self.z
    o.special, o.placed = true, true
    if index ~= nil and index >= 0 then
        table.insert(self.objects.items, index + 1, o)
    else
        self.objects:add(o)
    end
end
function Sq:getSpecialObjects()
    local out = H.list()
    for _, o in ipairs(self.objects.items) do if o.special then out:add(o) end end
    return out
end
function Sq:transmitRemoveItemFromSquare(o)
    for i, v in ipairs(self.objects.items) do
        if v == o then
            table.remove(self.objects.items, i)
            if isServer() then
                WALL.removed = WALL.removed + 1
                WALL_SENT[#WALL_SENT + 1] = 'remove ' .. tostring(o.name) .. ' ' .. self.x .. ',' .. self.y
            end
            return i - 1
        end
    end
    return -1
end
function Sq:RecalcAllWithNeighbours(b)
    if b ~= true then error('No implementation found for RecalcAllWithNeighbours', 2) end
    WALL.recalc = WALL.recalc + 1
end
function Sq:getWallFull()
    for _, o in ipairs(self.objects.items) do
        local p = o.sprite ~= nil and TILE_PROPS[o.sprite] or nil
        if p ~= nil and (p.WallN or p.WallW) then return true end
    end
    return false
end
-- Bords fermés par un ouvrage (mur, palissade : WallN/W, non enjambable bas) : isBlockedTo de la case.
local blocked = Sq.isBlockedTo
function Sq:isBlockedTo(o)
    local a, b = self, o
    if b.x > a.x or b.y > a.y then a, b = b, a end   -- a porte le bord (case sud ou est)
    local north = a.y ~= b.y
    for _, obj in ipairs(a.objects.items) do
        local p = obj.sprite ~= nil and TILE_PROPS[obj.sprite] or nil
        if p ~= nil and obj.north == north and (p.WallN or p.WallW) then return true end
    end
    return blocked(self, o)
end
-- Matériaux.
function SHOP(t, n)
    for _ = 1, n do PANTRY.container:AddItem(BAR_ITEM(t)) end
end
-- Ouvrage du pourtour sur le bord (x, y, face) : nom, ou nil.
function EDGE(x, y, north)
    for _, o in ipairs(HARNESS.square(x, y, 0).objects.items) do
        if o.name ~= nil and o.north == north and not o.corner then return o end
    end
    return nil
end
function CORNERS(x, y)
    local n = 0
    for _, o in ipairs(HARNESS.square(x, y, 0).objects.items) do if o.corner then n = n + 1 end end
    return n
end
'''

# Entrée seule (porte sud) ; caisse de la cuisine : marteau.
WORKSHOP = r'''
ENTRY = OPENING('door', 110, 116, true)
HAMMER_IT = BAR_ITEM('Base.Hammer')
PANTRY.container:AddItem(HAMMER_IT)
'''


class WallStack(MealStack):
    """Pile des repas + LK_Fortify, doublures des barricades et des murs ; maison sans autre ouverture que l'entrée."""

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            h.load(m, FORTIFY)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, BARRICADE_DOUBLES)
        h.load(srv, WALL_DOUBLES)
        h.load(srv, WORKSHOP)
        return h

    def mk(self, builder=True, shop=None):
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end')
        for t, n in (shop or {}).items():
            self.run_lua(f'SHOP("{t}", {n})')
        gid = super().mk()
        self.run_lua(f'{F}.reset() for k in pairs({F}.stats) do {F}.stats[k] = 0 end')
        if builder:
            self.run_lua('BUILDERS["m-2"] = true')
        return gid

    def stat(self, name):
        return self.ev(f'{F}.stats.{name}')

    def count(self, t):
        return self.ev(f'COUNT(PANTRY, "{t}")')

    def edge(self, x, y, north):
        return self.run_lua(f'local o = EDGE({x}, {y}, {str(north).lower()}) if o == nil then return nil end '
                            'return o.name, o.health, o.maxHealth, o.entity, o.canPassThrough, o.hoppable')

    def outer(self, gid):
        plan = self.ev(f'{F}.plan("{gid}", {{ force = true }})')
        return [s for s in plan.sites.values() if s.tier == 'outer'], plan

    def idle(self, n=30):
        for _ in range(n):
            self.dpass(1, walk=1.0)
            self.h.advance(1)

    def site(self, gid, sid):
        return f'(function() for _, s in ipairs({F}.plan("{gid}").sites) do if s.id == "{sid}" then return s end end end)()'


class PureWallTests(WallStack):
    mode = 'solo'

    def test_plan_is_only_the_ring_with_a_south_gap(self):
        gid = self.mk()
        sites, plan = self.outer(gid)
        self.assertEqual(len(plan.sites), len(sites))                          # aucune ouverture à barricader
        self.assertEqual(sites[0].id, 'wall:103,103,0N')
        self.assertEqual((sites[0].inside.x, sites[0].inside.y, sites[0].outside.x, sites[0].outside.y),
                         (103, 103, 103, 102))
        east = next(s for s in sites if s.side == 'E')
        self.assertEqual((east.inside.x, east.outside.x), (117, 118))           # côté est : case intérieure à l'ouest
        gaps = sorted((g.x, g.y) for g in plan.gaps.values())
        self.assertEqual(gaps, [(109, 118), (110, 118), (111, 118)])           # brèche en face de l'entrée
        self.assertEqual(self.h.errors('solo'), [])

    def test_ring_gestures_are_existing_nodes(self):
        import json
        table = json.loads((ROOT / 'tools' / 'anim_table.json').read_text(encoding='utf-8'))
        for kind in ('wall', 'palisade'):
            g = self.ev(f'{F}.CFG.RING_GESTURES.{kind}')
            self.assertIn(g, table['gestures'])
            self.assertTrue(self.ev(f'{R}.GESTURES["{g}"]'))                   # remis debout par Routines.leave


class SoloWallTests(WallStack):
    mode = 'solo'

    def test_builder_raises_two_wall_segments_with_the_exact_stock(self):
        gid = self.mk(shop={'Base.Plank': 8, 'Base.NailsBox': 1})
        avail = self.ev(f'{F}.available("{gid}")')
        self.assertEqual((avail['Base.Plank'], avail['Base.Nails']), (8, 100))
        self.jump_to(11)
        self.assertTrue(self.run_until(lambda: self.stat('finished') >= 2, seconds=200),
                        (self.stat('stages'), self.lk()[-10:]))
        # Deux segments du côté nord : cadre remplacé par le mur, santé 450 + 2 x 20, entité, mur plein.
        for x in (103, 104):
            self.assertEqual(self.edge(x, 103, True),
                             ('WoodenWallLvl1', 490, 490, 'WoodenWallLvl1', False, False))
        self.assertIsNone(self.edge(105, 103, True))
        # Stock : 8 planches et 12 clous retirés, boîte ouverte une fois, marteau gardé.
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.count('Base.NailsBox')), (0, 88, 0))
        self.assertTrue(self.ev('PANTRY.container:containsID(HAMMER_IT.id)'))
        self.assertEqual((self.stat('stages'), self.stat('boxes'), self.stat('started')), (4, 1, 2))
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        # Solo : aucune transmission ; 4 objets posés (2 cadres, 2 murs), cadres retirés localement.
        self.assertEqual((self.ev('WALL.sent'), self.ev('WALL.removed'), self.ev('WALL.entities')), (0, 0, 4))
        self.assertEqual(self.ev('BAR.construction'), 4)
        # Plan : les deux segments faits, l'entrée sans planche, plus rien de faisable.
        sites, plan = self.outer(gid)
        done = [s.id for s in sites if s.done]
        self.assertEqual(done, ['wall:103,103,0N', 'wall:104,103,0N'])
        self.assertFalse(self.ev(f'{F}.hasWork("{gid}")'))
        self.idle(30)
        self.assertEqual(self.stat('stages'), 4)
        self.assertEqual(self.h.errors('solo'), [])

    def test_existing_frame_needs_only_the_wall_stage(self):
        gid = self.mk(shop={'Base.Plank': 2, 'Base.Nails': 4})
        info = 'INFOS.carpentry_02_101'
        self.run_lua(f'FRAME0 = {F}.placeStructure(HARNESS.square(103, 103, 0), true, {info}, "carpentry_02_101", nil)')
        self.assertEqual(self.edge(103, 103, True), ('WoodenWallFrame', 90, 90, 'WoodenWallFrame', True, True))
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        site = self.ev(self.site(gid, 'wall:103,103,0N'))
        self.assertEqual((site.have, site.steps), (1, 2))
        text, n = self.run_lua(f'return {F}.buildStep({self.site(gid, "wall:103,103,0N")}, "{gid}", "m-2")')
        self.assertEqual(n, 2, text)
        self.assertEqual(self.edge(103, 103, True)[0], 'WoodenWallLvl1')
        self.assertEqual(self.run_lua('local n = 0 for _, o in ipairs(HARNESS.square(103, 103, 0).objects.items) do '
                                      'if o.name == "WoodenWallFrame" then n = n + 1 end end return n'), 0)
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (0, 0))
        self.assertEqual(self.run_lua(f'return {F}.buildStep({self.site(gid, "wall:103,103,0N")}, "{gid}", "m-2")'),
                         (None, 'already done'))
        # Bord dans le rectangle mais hors du pourtour (dans la maison) : refusé.
        self.assertEqual(self.run_lua(f'return {F}.buildStep({{ id = "wall:107,107,0N", kind = "wall", x = 107, '
                                      f'y = 107, z = 0, north = true }}, "{gid}", "m-2")'), (None, 'not in the plan'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_build_step_rechecks_before_taking(self):
        gid = self.mk(shop={'Base.Plank': 3, 'Base.Nails': 1})
        step = f'{F}.buildStep(%s, "{gid}", "m-2")'
        gap = '{ id = "wall:110,118,0N", kind = "wall", x = 110, y = 118, z = 0, north = true }'
        self.assertEqual(self.run_lua('return ' + step % gap), (None, 'gap'))
        far = '{ id = "wall:130,103,0N", kind = "wall", x = 130, y = 103, z = 0, north = true }'
        self.assertEqual(self.run_lua('return ' + step % far), (None, 'outside the home'))
        first = self.site(gid, 'wall:103,103,0N')
        self.assertEqual(self.run_lua('return ' + step % first), (None, 'no nails'))   # 1 clou, 2 requis, sans boîte
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, HAMMER_IT)')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual(self.run_lua('return ' + step % first), (None, 'no hammer'))
        # Rien de pris par ces refus, rien posé.
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails'), self.stat('stages')), (3, 1, 0))
        self.assertIsNone(self.edge(103, 103, True))
        self.assertEqual(self.h.errors('solo'), [])

    def test_corner_post_is_added_once(self):
        gid = self.mk()
        place = f'{F}.placeStructure(HARNESS.square(%d, %d, 0), %s, INFOS.%s, "%s", %s)'
        # Coin sud-est du pourtour : mur est (118,117 W) puis mur sud (117,118 N) : poteau en (118,118).
        self.run_lua(place % (118, 117, 'false', 'carpentry_02_100', 'carpentry_02_100', 'nil'))
        self.assertEqual(self.ev('CORNERS(118, 118)'), 0)
        self.run_lua('S_FRAME = ' + place % (117, 118, 'true', 'carpentry_02_101', 'carpentry_02_101', 'nil'))
        self.assertEqual(self.ev('CORNERS(118, 118)'), 1)
        # Le mur posé sur le cadre ne double pas le poteau (vanilla en ajouterait un second).
        self.run_lua(place % (117, 118, 'true', 'walls_exterior_wooden_01_45', 'walls_exterior_wooden_01_45',
                              'S_FRAME'))
        self.assertEqual(self.ev('CORNERS(118, 118)'), 1)
        self.assertEqual(self.stat('corners'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_palisade_takes_logs_and_ties_without_tool(self):
        gid = self.mk(shop={'Base.Log': 4, 'Base.Rope': 2, 'Base.Twine': 3})
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, HAMMER_IT)')
        self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        # Plan d'un camp : même relevé, pourtour en palissade (plan injecté en mémoire comme Fortify.plan le garde).
        self.run_lua(f'local s = assert({F}.survey("{gid}")) s.ringKind = "palisade" '
                     f'{F}.state.plans["{gid}"] = {{ plan = {F}.build(s), ms = getTimestampMs() }}')
        site = self.site(gid, 'palisade:103,103,0N')
        self.assertEqual(self.ev(f'{site}.steps'), 1)
        text, n = self.run_lua(f'return {F}.buildStep({site}, "{gid}", "m-2")')
        self.assertEqual(n, 1, text)
        self.assertEqual(self.edge(103, 103, True), ('LogWall', 500, 500, 'LogWall', False, True))
        self.assertEqual((self.count('Base.Log'), self.count('Base.Rope') + self.count('Base.Twine')), (0, 1))
        self.assertEqual(self.ev('CORNERS(104, 103)') + self.stat('corners'), 0)   # aucun poteau de palissade
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerWallTests(WallStack):
    """Serveur dédié + deux clients : ouvrages posés et transmis par le serveur seul."""

    mode = 'mp'

    def test_server_builds_and_sends_each_stage_once(self):
        gid = self.mk(shop={'Base.Plank': 4, 'Base.NailsBox': 1})
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Fortify'))
        self.jump_to(11)
        for _ in range(200):
            # Banc MP : corps tenus par le serveur ; arrivée posée à la place, regard rapporté fini.
            self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "fortify" and m.place then '
                         'HARNESS.place(LivingKnox.Bodies.find(id), m.place.x + 0.5, m.place.y + 0.5, 0) '
                         'local e = LivingKnox.Directives.entries[id] if e and e.op == "face" and not e.done then '
                         'e.done, e.s = true, "faced" LivingKnox.Directives.sync(id, true) end end end')
            self.dpass(1)
            self.h.advance(1)
            if self.stat('finished') >= 1:
                break
        self.assertEqual(self.stat('stages'), 2, self.lk()[-10:])
        sent = lua_list(self.ev('WALL_SENT'))
        self.assertEqual(sent, ['new WoodenWallFrame 103,103N', 'remove WoodenWallFrame 103,103',
                                'new WoodenWallLvl1 103,103N'])
        self.assertEqual(self.ev('BAR.addedSent'), 100)                         # clous de la boîte, une fois
        self.assertEqual((self.count('Base.Plank'), self.count('Base.Nails')), (0, 94))
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class SuiteListTests(WallStack):
    mode = 'solo'

    def test_suite_is_listed_with_its_tags(self):
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', TIME_OF_DAY)
        self.h.load('solo', SUITE)
        listed = lua_list(self.h.eval('solo', 'RST.list({ suite = "lk.walls", tags = "world" }, true)'))
        self.assertEqual([e.name for e in listed], ['lk.walls'])
        self.assertEqual(lua_list(listed[0].tags), ['world', 'server'])
        self.assertIsNone(listed[0].error)


class SuiteTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn('RST.suite("lk.walls", { tags = { "world", "server" }', code)
        self.assertIn('Homes.skip(', code)


if __name__ == '__main__':
    unittest.main(verbosity=1)
