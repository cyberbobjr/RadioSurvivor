"""Tests hors jeu du potager du jardinier de Living Knox (LK15-T04, T05, T06 ; ADR registre des routines D07, D08,
Q01) : tâches « dig » (creuser un sillon, Jobs/LK_Job_Dig.lua), « sow » (semer, Jobs/LK_Job_Sow.lua) et « seeds »
(graines reçues, Jobs/LK_Job_SeedSupply.lua), aides de domaine de LK_Garden.lua, moteur LK_Upkeep.lua (durée propre à
une tâche : champ générique duration), et la suite en jeu lk.garden (dev/.../RST_LKGarden.lua).

    python tests/test_lk_garden.py

Bancs : pile de l'entretien et du potager (test_lk_food.WaterStack : groupe « deciders » dans la maison HOUSE
105..115, caisse PANTRY en 112,112, système de cultures doublé) ; solo et serveur dédié + deux clients.
Doublures relevées dans les sources vanilla 42.22 (E:/pz-source-42.22, lecture seule) :
- SFarmingSystem:plow (M/server/Farming/SFarmingSystem.lua:508-536) refusé sur une case qui porte déjà un objet du
  système (J/globalObjects/GlobalObjectSystem.java:40-48 : « already an object at ») ; removeTallGrass
  (SFarmingSystem.lua:562-574) ; ce que fait ISPlowAction:complete (M/shared/Farming/TimedActions/ISPlowAction.lua
  :110-124 : herbes hautes, herbe du sol, plante morte retirée, puis plow) ;
- conditions du menu ISFarmingMenu.canDigHereSquare (M/client/Farming/ISUI/ISFarmingMenu.lua:514-534 : ni tombe, ni
  plante vivante ou sillon, rez-de-chaussée, case libre, sol « dirt » de ISShovelGroundCursor.GetDirtGravelSand,
  M/server/BuildingObjects/ISShovelGroundCursor.lua:97-132) ; outil predicateDigPlow (ISFarmingMenu.lua:20-22 : non
  cassé, tag DigPlow, J/scripting/objects/ItemTag.java:115) ; durée mains nues doublée (ISPlowAction.lua:132-144) ;
- IsoGridSquare.hasGrave (J/iso/IsoGridSquare.java:9693), isOutside (:7968), getFloor (:4002), checkHaveGrass
  (:8914), removeGrass (:8953, envoi aux clients par le Java) ; IsoPropertyType.GRASS_FLOOR (ISPlowAction.lua:113) ;
- définitions vanilla des quatre légumes (M/server/Farming/farming_vegetableconf_vegetables.lua : choux :93-114,
  carottes :129-141, pommes de terre :463-471, tomates :757-770 ; graines = seedTypes ou { seedName },
  ISFarmingMenu.lua:1138) ; mois = getGameTime():getMonth() + 1 (SPlantGlobalObject.lua:162-173) ; graines
  DisplayCategory Gardening (M/scripts/generated/items/normal.txt:5214-5466), hors catégories du stock ;
- ItemContainer.AddItems(type, n) et sendAddItemsToContainer (comme la récolte, test_lk_food.HARVEST_DOUBLES).
Elles NE PROUVENT PAS l'API réelle : seulement la logique (sillon une fois, plafond, cases refusées, graine retirée une
fois, rien hors saison, dépôt une fois par fenêtre, référence du stock cohérente, rien chez un client). Le vrai jeu se
vérifie en jeu (suite lk.garden, campagnes solo et MP).
Classes « vanilla réel » (E19-T04 : VanillaGardenTests, MultiplayerVanillaGardenTests, SuiteVanillaRunTests) : les
mêmes tâches sur le VRAI Lua vanilla du potager (test_lk_vanilla_farming.py), sans doublure du système de cultures.
Écarts des anciennes doublures relevés : besoin en eau du semis (70 fixe et plafond 100 -> waterNeeded de la
définition, aucun plafond ; puis waterLvl de la définition aux stades suivants), retrait d'une plante par
l'événement OnObjectAboutToBeRemoved du Java (absent des doublures de transmitRemoveItemFromSquare), nom vanilla
Base.Strewberrie (doublure : Base.Strawberrie), terre d'une plante morte illisible en solo (miroir client,
ISShovelGroundCursor.GetDirtGravelSand), recreusée par un serveur dédié.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phase_sweep import WORLDS, other_groups, sweep  # noqa: E402
from harness import lua_src  # noqa: E402
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_food import WEATHER_DOUBLES, WaterStack  # noqa: E402
from test_lk_upkeep import UpkeepStack, upkeep_files  # noqa: E402
from test_lk_vanilla_farming import load_vanilla_farming  # noqa: E402

U = 'LivingKnox.Upkeep'
R = 'LivingKnox.Routines'
ST = 'LivingKnox.Stock'
GD = 'LivingKnox.Garden'
ROOT = Path(__file__).resolve().parents[1]
GARDEN = 'server/LivingKnox/LK_Garden.lua'
JOBS = ['server/LivingKnox/Jobs/LK_Job_Dig.lua', 'server/LivingKnox/Jobs/LK_Job_Sow.lua',
        'server/LivingKnox/Jobs/LK_Job_SeedSupply.lua']
SUITE = 'shared/RST/suites/RST_LKGarden.lua'
from harness import tests_lua  # noqa: E402  (E21-T07: media/lua of the test mods)
SUITE_FILE = tests_lua('lk') / SUITE

# Doublures du système de cultures et du sol (anciennes doublures ; la classe « vanilla réel » charge le vrai Lua à la
# place : test_lk_vanilla_farming.py).
GARDEN_FARM_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local Sq = C.IsoGridSquare
-- Définitions vanilla (farming_vegetableconf_vegetables.lua, champs lus par le potager).
farming_vegetableconf = farming_vegetableconf or { props = {} }
local P = farming_vegetableconf.props
P.Carrots = P.Carrots or {}
P.Carrots.seedName, P.Carrots.sowMonth = 'Base.CarrotSeed', { 2, 3, 4, 5, 6, 7 }
P.Cabbages = { seedName = 'Base.CabbageSeed', sowMonth = { 2, 3, 4, 5, 6, 7 } }
P.Potatoes = { seedName = 'Base.PotatoSeed', seedTypes = { 'Base.PotatoSeed', 'Base.Potato' }, sowMonth = { 2, 3, 4 } }
P.Tomato = { seedName = 'Base.Tomato', seedTypes = { 'Base.TomatoSeed' }, sowMonth = { 4, 5, 6 } }
-- Système de cultures : plow refusé sur une case déjà prise (GlobalObjectSystem.newObject), herbes hautes.
local sys = SFarmingSystem.instance
local plow = sys.plow
function sys:plow(sq)
    if getmetatable(sq) ~= Sq then error('No implementation found for plow', 2) end
    if self:getLuaObjectAt(sq.x, sq.y, sq.z) ~= nil then
        error('already an object at ' .. sq.x .. ',' .. sq.y .. ',' .. sq.z, 2)
    end
    GARDEN.plowed = GARDEN.plowed + 1
    return plow(self, sq)
end
function sys:removeTallGrass(sq)
    if getmetatable(sq) ~= Sq then error('No implementation found for removeTallGrass', 2) end
    if sq.tall then
        sq.tall = nil
        GARDEN.tall = GARDEN.tall + 1
    end
end
-- Cases : tombe, dehors (hors des rectangles BUILDINGS et sans toit), sol, herbe, nature du sol.
function Sq:hasGrave() return self.grave == true end
function Sq:isOutside()
    if self.roof then return false end
    for _, b in ipairs(BUILDINGS or {}) do
        if self.x >= b[1] and self.x <= b[3] and self.y >= b[2] and self.y <= b[4] then return false end
    end
    return true
end
local Props = H.class('PropertyContainer')
function Props:has(p)
    if type(p) ~= 'table' or p.name == nil then error('No implementation found for has', 2) end
    return self.flags[p.name] == true
end
local Floor = H.class('IsoObject_Floor', C.IsoObject)
function Floor:getProperties() return setmetatable({ flags = self.flags }, Props) end
function Sq:getFloor() return rawget(self, 'floor') end
function Sq:checkHaveGrass() return self.grass == true end
function Sq:removeGrass()
    if self.grass then
        self.grass = false
        GARDEN.grass = GARDEN.grass + 1
        return true
    end
    return false
end
IsoPropertyType = IsoPropertyType or {}
IsoPropertyType.GRASS_FLOOR = { name = 'GrassFloor' }
ISShovelGroundCursor = { GetDirtGravelSand = function(sq)
    if getmetatable(sq) ~= Sq then error('No implementation found for GetDirtGravelSand', 2) end
    if sq.ground ~= nil then return sq.ground, rawget(sq, 'floor') end
    return nil
end }
-- Case de terre (herbe et herbes hautes facultatives).
function DIRT(x, y, o)
    o = o or {}
    local sq = H.square(x, y, 0)
    sq.ground = o.ground or 'dirt'
    if o.grass then
        sq.floor = setmetatable({ flags = { GrassFloor = true } }, Floor)
        sq.grass = true
    end
    sq.tall = o.tall
    return sq
end
'''

# Graines, conteneurs et jardinier (communs aux deux piles du potager).
GARDEN_STOCK_DOUBLES = r'''
local H = HARNESS
local C = H.classes
GARDEN = { plowed = 0, tall = 0, grass = 0, sent = 0 }
ItemTag.DIG_PLOW = { name = 'DigPlow' }
-- Graines (DisplayCategory Gardening) ; tout le reste, nourriture.
local Ctr = C.ItemContainer
function SEED(t) return MEAL_ITEM(t, { cat = 'Gardening' }) end
function Ctr:AddItems(t, n)
    if type(t) ~= 'string' or type(n) ~= 'number' then error('No implementation found for AddItems', 2) end
    local list = H.list()
    for _ = 1, n do
        local it = string.find(t, 'Seed', 1, true) and SEED(t) or MEAL_ITEM(t)
        self.items:add(it)
        list:add(it)
    end
    return list
end
sendAddItemsToContainer = function(c, list)
    if getmetatable(c) ~= Ctr or type(list) ~= 'table' then error('No implementation found for sendAddItemsToContainer', 2) end
    if isServer() then GARDEN.sent = GARDEN.sent + list:size() end
end
function PANTRY_COUNT(t)
    local n = 0
    for _, it in ipairs(PANTRY.container.items.items) do if it.t == t then n = n + 1 end end
    return n
end
function GARDENER()
    local def = LivingKnox.GroupTypes.peek('deciders')
    local b = def.roles.worker.behaviours
    for _, v in ipairs(b) do if v == 'garden' then return end end
    b[#b + 1] = 'garden'
end
'''


class GardenStack(WaterStack):
    """Pile de l'entretien et du potager (WaterStack) + doublures du potager ; la graine du stock et le mois sont posés
    par chaque test (juillet par défaut : carottes et choux de saison)."""

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, GARDEN_STOCK_DOUBLES)
        h.load(srv, GARDEN_FARM_DOUBLES)
        return h

    def mk(self):
        gid = super().mk()
        self.set_month(7)
        self.run_lua(f'{GD}.reset()')
        return gid

    def set_month(self, month):
        self.h.date = self.h.date.replace(month=month, day=min(self.h.date.day, 28))
        self.h._push_clock()

    def settle(self, n=30):
        for _ in range(n):
            self.dpass(1)
            self.h.advance(1)

    def plant(self, x, y):
        return self.run_lua(f'local p = {GD}.plantAt({x}, {y}, 0) if p == nil then return nil end '
                            'return p.state, p.typeOfSeed')

    def journal_of(self, gid, kind):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == kind]


class PureGardenTests(GardenStack):
    mode = 'solo'

    def test_job_order_puts_the_plants_first_then_seeds_sowing_and_digging(self):
        # Campagne MP du 2026-11-13 (lk.upkeep, runs/20261113-150840-parallel-3, shard3) : sachet de graines et sillon
        # creuse a mains nues pris avant le verre et le sang, scene d'entretien non finie en 300 s. Les taches qui
        # creent le potager passent apres l'entretien du foyer ; le jardinier les prend d'abord (prefer).
        self.assertEqual(lua_list(self.ev(f'{U}.JOBS')),
                         ['refuel', 'repair', 'harvest', 'water', 'clean', 'glass', 'seeds', 'sow', 'dig'])
        for kind in ('seeds', 'sow', 'dig'):
            self.assertEqual(self.ev(f'{U}.specs.{kind}.prefer'), 'garden', kind)
        jobs = ('{ { kind = "dig", key = "dig 1", x = 1, y = 1, z = 0 }, { kind = "sow", key = "sow 2", x = 2, y = 2, '
                'z = 0 }, { kind = "water", key = "water 3", x = 3, y = 3, z = 0 }, { kind = "refuel", key = "refuel 4", '
                'x = 4, y = 4, z = 0 } }')
        self.run_lua(f'{U}.state.scans["g"] = {{ minute = 100, jobs = {jobs} }}')
        got = [self.ev(f'({U}.claim("g", {{}}, "lk-{i}", 100, {{ garden = true }})).key') for i in range(3)]
        self.assertEqual(got, ['dig 1', 'sow 2', 'water 3'])    # liste du relevé déjà triée ; préférées d'abord
        self.assertEqual(self.ev(f'({U}.claim("g", {{}}, "lk-9", 100, {{ chores = true }})).key'), 'refuel 4')

    def test_vanilla_quantities_of_the_garden(self):
        cfg = self.ev(f'{GD}.CFG')
        self.assertEqual((cfg.MAX_PLOTS, cfg.SEED_LOW, cfg.SEED_DAYS, cfg.SEED_PACKET), (6, 2, 7, 5))
        self.assertEqual(lua_list(self.ev(f'{GD}.SEED_VARIETIES')), ['Carrots', 'Potatoes', 'Cabbages', 'Tomato'])
        self.assertEqual(self.ev(f'{GD}.DIG_PLOW'), 'DIG_PLOW')

    def test_sowable_seeds_follow_sow_month_and_are_never_food(self):
        def sowable(t, month, food=False):
            mk = f'MEAL_ITEM("{t}")' if food else f'SEED("{t}")'
            return self.ev(f'{GD}.sowable({mk}, {month})')
        self.assertEqual(sowable('Base.CarrotSeed', 7), 'Carrots')
        self.assertIsNone(sowable('Base.CarrotSeed', 1))                       # janvier : hors saison
        self.assertEqual(sowable('Base.TomatoSeed', 5), 'Tomato')              # seedTypes, pas seedName
        self.assertIsNone(sowable('Base.Tomato', 5, food=True))                # le légume n'est pas une graine
        self.assertEqual(sowable('Base.PotatoSeed', 3), 'Potatoes')
        self.assertIsNone(sowable('Base.Potato', 3, food=True))                # seedTypes, mais nourriture : jamais
        self.assertIsNone(sowable('Base.Nails', 3))

    def test_seed_variety_is_drawn_among_the_season_and_reproducible(self):
        draws = [self.ev(f'({GD}.seedVariety({day}, 7) or {{}}).seed') for day in range(1, 36)]
        self.assertEqual(set(draws), {'Base.CarrotSeed', 'Base.CabbageSeed'})  # juillet : carottes et choux
        self.assertEqual(draws, [self.ev(f'({GD}.seedVariety({day}, 7) or {{}}).seed') for day in range(1, 36)])
        self.assertEqual(len(set(draws[:7])), 1)                               # une variété par fenêtre de 7 jours
        self.assertEqual(self.ev(f'({GD}.seedVariety(3, 4)).seed') in
                         ('Base.CarrotSeed', 'Base.PotatoSeed', 'Base.CabbageSeed', 'Base.TomatoSeed'), True)
        self.assertIsNone(self.ev(f'{GD}.seedVariety(3, 1)'))                  # janvier : rien de saison
        self.assertIsNone(self.ev(f'{GD}.seedVariety(3, 9)'))                  # septembre : rien non plus


class DigTests(GardenStack):
    mode = 'solo'

    def test_furrow_dug_once_on_free_outdoor_dirt_with_tall_grass_removed(self):
        gid = self.mk()
        self.run_lua('SHOVEL = UPK_ITEM("Base.Shovel", { tags = { DigPlow = true } }) PANTRY.container:AddItem(SHOVEL) '
                     'DIRT(106, 118, { grass = true, tall = true }) DIRT(108, 118)')
        self.assertEqual(self.jobs(gid), ['dig 106,118,0'])                    # un sillon à la fois
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('dug') >= 1), (self.stat('dug'), self.jobs(gid), self.lk()[-8:]))
        self.assertEqual(self.plant(106, 118), ('plow', None))
        self.assertEqual((self.ev('GARDEN.plowed'), self.ev('GARDEN.tall'), self.ev('GARDEN.grass')), (1, 1, 1))
        self.assertTrue(self.ev('PANTRY.container:containsID(SHOVEL.id)'))    # l'outil reste au stock
        # Sillon vide sans graine : on n'en creuse pas d'autre.
        self.settle(40)
        self.assertEqual((self.stat('dug'), self.ev('GARDEN.plowed')), (1, 1))
        self.assertIsNone(self.plant(108, 118))
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), [])
        self.assertTrue(any('furrow dug at 106,118 with Base.Shovel' in line for line in self.lk()), self.lk()[-8:])
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        self.assertEqual(self.h.errors('solo'), [])

    def test_test_group_furrows_removed_with_the_group_during_a_test_run(self):
        # Campagnes du 2026-11-13 : les sillons creusés par les groupes de test (potager LK15) restaient dans le monde
        # et faussaient les suites suivantes (lk.forage arrose une autre plante, lk.upkeep : place décalée hors du
        # foyer, lk.garden sauté : « an empty furrow already waits »). Mod de test : RST_GardenHygiene.
        gid = self.mk()
        self.h.load('solo', 'require "RST/RST"')
        self.h.load('solo', 'require "RST/RST_GardenHygiene"')
        self.run_lua('RST.running = function() return true end assert(RST.GardenHygiene.install()) '
                     'assert(not RST.GardenHygiene.install()) '                            # une seule enveloppe
                     'SHOVEL = UPK_ITEM("Base.Shovel", { tags = { DigPlow = true } }) PANTRY.container:AddItem(SHOVEL) '
                     'DIRT(106, 118)')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('dug') >= 1), self.lk()[-8:])
        self.assertEqual(self.plant(106, 118), ('plow', None))
        self.run_lua(f'LivingKnox.Groups.remove("{gid}")')
        self.assertIsNone(self.plant(106, 118))
        self.assertEqual(self.ev('#RST.GardenHygiene.dug'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_test_group_seed_packet_removed_with_the_group_during_a_test_run(self):
        # Campagnes du 2026-11-14 : lk.garden sauté (« the home already holds 5 sowable seed(s) ») : le sachet reçu
        # par un groupe de test d'une suite précédente restait dans le dépôt du foyer commun aux suites.
        gid = self.mk()
        self.run_lua('GARDENER()')
        self.h.load('solo', 'require "RST/RST"')
        self.h.load('solo', 'require "RST/RST_GardenHygiene"')
        self.run_lua('RST.running = function() return true end assert(RST.GardenHygiene.install())')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('seedPackets') >= 1), (self.jobs(gid), self.lk()[-8:]))
        day = self.ev('LivingKnox.Groups.today()')
        want = self.ev(f'{GD}.seedVariety({day}, 7).seed')
        self.assertEqual(self.ev(f'PANTRY_COUNT("{want}")'), 5)
        self.run_lua(f'LivingKnox.Groups.remove("{gid}")')
        self.assertEqual(self.ev(f'PANTRY_COUNT("{want}")'), 0)
        self.assertEqual(self.ev('#RST.GardenHygiene.seeds'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_bare_hands_take_twice_as_long_and_a_broken_tool_does_not_count(self):
        gid = self.mk()
        job = '{ kind = "dig", key = "dig 106,118,0", x = 106, y = 118, z = 0 }'
        base = self.ev(f'{GD}.CFG.DIG_MINUTES')
        self.assertEqual(self.ev(f'{U}.specs.dig.duration({job}, "{gid}")'), 2 * base)
        self.run_lua('SHOVEL = UPK_ITEM("Base.Shovel", { tags = { DigPlow = true }, broken = true }) '
                     'PANTRY.container:AddItem(SHOVEL)')
        self.assertEqual(self.ev(f'{U}.specs.dig.duration({job}, "{gid}")'), 2 * base)
        self.run_lua('SHOVEL.broken = false')
        self.assertEqual(self.ev(f'{U}.specs.dig.duration({job}, "{gid}")'), base)

    def test_engine_waits_the_duration_of_the_job(self):
        gid = self.mk()
        self.run_lua('DIRT(106, 118)')
        self.jump_to(11)
        holder = lambda: self.run_lua(  # noqa: E731
            f'for id, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.phase == "work" then '
            'return m.minutes end end return nil')
        self.assertTrue(self.work(lambda: holder() is not None))
        self.assertEqual(holder(), 2 * self.ev(f'{GD}.CFG.DIG_MINUTES'))       # mains nues
        self.assertTrue(self.work(lambda: self.stat('dug') >= 1))
        self.assertEqual(self.plant(106, 118), ('plow', None))
        self.assertTrue(any('furrow dug at 106,118 with bare hands' in line for line in self.lk()), self.lk()[-8:])
        self.assertEqual(self.h.errors('solo'), [])

    def test_squares_refused_outside_the_vanilla_conditions(self):
        gid = self.mk()
        self.run_lua('DIRT(106, 118).grave = true '            # tombe
                     'DIRT(108, 112) '                          # dans la maison
                     'DIRT(107, 118).roof = true '              # sous un toit (dehors du bâtiment, pas à l'air libre)
                     'DIRT(108, 118).blocked = true '           # case occupée (isFree faux)
                     'DIRT(109, 118, { ground = "gravel" }) '   # gravier
                     'DIRT(125, 110) '                          # hors de la zone du foyer
                     'DIRT(110, 118) FARM_PLANT(110, 118, 50, 40)')   # plante vivante
        self.assertEqual(self.jobs(gid), [])
        self.assertFalse(self.run_lua(f'local s = HARNESS.square(106, 119, 1) s.ground = "dirt" '
                                      f'return ({GD}.canDig(s))'))             # pas au rez-de-chaussée (niveau 1)
        self.assertTrue(self.run_lua(f'return ({GD}.canDig(DIRT(106, 119)))'))   # la même case au niveau 0
        self.run_lua(f'{U}.reset() HARNESS.square(106, 119, 0).ground = nil')
        # Plante morte : la case se creuse de nouveau (plante retirée d'abord, comme ISPlowAction:complete).
        self.run_lua('local dead = SFarmingSystem.instance:getLuaObjectAt(110, 118, 0) dead.state = "dead"')
        self.assertEqual(self.jobs(gid), ['dig 110,118,0'])
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('dug') >= 1), (self.stat('dug'), self.lk()[-8:]))
        self.assertEqual(self.plant(110, 118), ('plow', None))
        self.assertEqual(self.ev('GARDEN.plowed'), 2)                          # FARM_PLANT, puis le sillon
        self.assertEqual(self.h.errors('solo'), [])

    def test_at_most_max_plots_per_home(self):
        gid = self.mk()
        self.run_lua('for i = 0, 5 do FARM_PLANT(100 + i, 120, 50, 40) end DIRT(106, 118)')
        self.assertEqual(self.jobs(gid), [])                                   # 6 plantes : plafond atteint
        self.run_lua(f'SFarmingSystem.instance:getLuaObjectAt(105, 120, 0).state = "harvested" {U}.reset()')
        self.assertEqual(self.jobs(gid), ['dig 106,118,0'])                    # 5 vivantes : un sillon de plus
        # Plafond relu au moment de l'effet : une sixième plante apparue entre-temps, rien n'est creusé.
        self.run_lua('FARM_PLANT(119, 119, 50, 40)')
        sq = 'HARNESS.square(106, 118, 0)'
        self.assertIsNone(self.ev(f'({U}.specs.dig.apply({{ kind = "dig", key = "k", x = 106, y = 118, z = 0 }}, '
                                  f'"{gid}", "m-2", {sq}))'))
        self.assertIsNone(self.plant(106, 118))
        self.assertEqual(self.h.errors('solo'), [])


class SowTests(GardenStack):
    mode = 'solo'

    def test_one_seed_sown_in_an_empty_furrow_and_taken_from_the_stock(self):
        gid = self.mk()
        self.run_lua('SFarmingSystem.instance:plow(HARNESS.square(106, 118, 0)) '
                     'S1 = SEED("Base.CarrotSeed") S2 = SEED("Base.CarrotSeed") '
                     'PANTRY.container:AddItem(S1) PANTRY.container:AddItem(S2) DIRT(108, 118)')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertIsNotNone(r)
        self.assertEqual(self.jobs(gid), ['sow 106,118,0'])                    # un sillon vide attend : pas de creusage
        removed = self.ev('MEAL_COUNT.removed')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('sown') >= 1), (self.stat('sown'), self.jobs(gid), self.lk()[-8:]))
        self.assertEqual(self.plant(106, 118), ('seeded', 'Carrots'))
        self.assertEqual(self.ev('PANTRY_COUNT("Base.CarrotSeed")'), 1)       # une graine en moins
        self.assertEqual(self.ev('MEAL_COUNT.removed'), removed + 1)
        self.assertFalse(self.ev('PANTRY.container:containsID(S1.id)'))
        up = self.journal_of(gid, 'upkeep')
        self.assertEqual(len(up), 1, up)
        self.assertTrue(up[0].startswith('Carrots sown at 106,118 (Base.CarrotSeed'), up)
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, r.added, len(lua_list(r.thefts))), (0, 0, 0, 0))
        self.assertEqual(self.h.errors('solo'), [])

    def test_nothing_sown_out_of_season_nor_from_food(self):
        gid = self.mk()
        self.run_lua('SFarmingSystem.instance:plow(HARNESS.square(106, 118, 0)) '
                     'PANTRY.container:AddItem(SEED("Base.TomatoSeed")) PANTRY.container:AddItem(MEAL_ITEM("Base.Potato"))')
        self.assertEqual(self.jobs(gid), [])                                   # juillet : tomate hors saison
        self.set_month(5)
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), ['sow 106,118,0'])                    # mai : tomate de saison
        self.set_month(3)
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), [])                                   # mars : pomme de terre (nourriture) jamais
        # Saison relue au moment de l'effet.
        self.assertIsNone(self.ev(f'({U}.specs.sow.apply({{ kind = "sow", key = "k", x = 106, y = 118, z = 0 }}, '
                                  f'"{gid}", "m-2", HARNESS.square(106, 118, 0)))'))
        self.assertEqual(self.plant(106, 118), ('plow', None))
        self.assertEqual(self.ev('PANTRY_COUNT("Base.TomatoSeed")'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_a_furrow_already_sown_is_left(self):
        gid = self.mk()
        self.run_lua('FARM_PLANT(106, 118, 50, 40) PANTRY.container:AddItem(SEED("Base.CarrotSeed"))')
        self.assertEqual(self.jobs(gid), [])
        self.assertEqual(self.h.errors('solo'), [])


class SeedSupplyTests(GardenStack):
    mode = 'solo'

    def test_seeds_received_once_per_window_by_a_group_with_a_gardener(self):
        gid = self.mk()
        self.run_lua('GARDENER()')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertIsNotNone(r)
        ref = sorted(lua_list(self.ev(f'REF_IDS("{gid}")')))
        self.assertEqual(self.jobs(gid), ['seeds 112,112,0'])
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('seedPackets') >= 1), (self.jobs(gid), self.lk()[-8:]))
        day = self.ev('LivingKnox.Groups.today()')
        want = self.ev(f'{GD}.seedVariety({day}, 7).seed')
        self.assertEqual(self.ev(f'PANTRY_COUNT("{want}")'), 5)                # un sachet : 5 graines d'une variété
        self.assertEqual(self.stat('seedsReceived'), 5)
        self.assertEqual(self.ev(f'{GD}.state.seedDay["{gid}"]'), day)
        up = self.journal_of(gid, 'upkeep')
        self.assertTrue(any(t.startswith(f'5 {want} received into ') for t in up), up)
        # Référence du stock cohérente : graines hors catégories, ni ajoutées, ni perdues, ni volées.
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, r.added, len(lua_list(r.thefts))), (0, 0, 0, 0))
        self.assertEqual(sorted(lua_list(self.ev(f'REF_IDS("{gid}")'))), ref)
        # Graines parties (semées) avant la fin de la fenêtre : rien de plus.
        self.run_lua('local keep = {} for _, it in ipairs(PANTRY.container.items.items) do '
                     'if not string.find(it.t, "Seed", 1, true) then keep[#keep + 1] = it end end '
                     f'PANTRY.container.items.items = keep {U}.reset()')
        self.settle(30)
        self.assertEqual(self.stat('seedPackets'), 1)
        self.assertEqual(self.jobs(gid), [])
        # Fenêtre de SEED_DAYS jours passée : un nouveau sachet est proposé.
        self.h.age_minutes += 7 * 24 * 60
        self.h._push_clock()
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), ['seeds 112,112,0'])
        self.assertEqual(self.h.errors('solo'), [])

    def test_nothing_without_a_gardener(self):
        gid = self.mk()
        self.assertEqual(self.jobs(gid), [])                                   # « deciders » : aucun rôle « garden »
        self.run_lua('GARDENER()')
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), ['seeds 112,112,0'])
        # Le jardinier mort : plus rien.
        self.update(gid, 'g.members["m-2"].alive = false')
        self.run_lua(f'{U}.reset()')
        self.assertIsNone(self.ev(f'{U}.specs.seeds.survey("{gid}", LivingKnox.Groups.get("{gid}"), '
                                  f'{U}.area("{gid}", LivingKnox.Groups.get("{gid}")))'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_nothing_at_or_above_the_threshold_and_nothing_in_winter(self):
        gid = self.mk()
        self.run_lua('GARDENER() PANTRY.container:AddItem(SEED("Base.CarrotSeed")) '
                     'PANTRY.container:AddItem(SEED("Base.CabbageSeed"))')
        self.assertEqual(self.jobs(gid), [])                                   # 2 graines semables : assez
        self.run_lua('HARNESS.listRemove(PANTRY.container.items, PANTRY.container.items.items[#PANTRY.container.items.items]) '
                     'for i = 1, 3 do PANTRY.container:AddItem(SEED("Base.TomatoSeed")) end')
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), ['seeds 112,112,0'])                  # 1 semable (tomates hors saison)
        self.set_month(1)
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), [])                                   # janvier : aucune variété de saison
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerGardenTests(GardenStack):
    """Serveur dédié + deux clients : graines reçues, semées et sillon creusé par le serveur, envois faits une fois ;
    rien chez un client."""

    mode = 'mp'

    def test_server_receives_sows_and_digs_once(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Garden'))
        self.run_lua('GARDENER() DIRT(106, 118)')
        self.jump_to(11)
        for _ in range(400):
            self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.place then '
                         'HARNESS.place(LivingKnox.Bodies.find(id), m.place.x + 0.5, m.place.y + 0.5, 0) '
                         'local e = LivingKnox.Directives.entries[id] if e and e.op == "face" and not e.done then '
                         'e.done, e.s = true, "faced" LivingKnox.Directives.sync(id, true) end end end')
            self.dpass(1)
            self.h.advance(1)
            if self.stat('sown') >= 1:
                break
        self.assertEqual((self.stat('seedPackets'), self.stat('dug'), self.stat('sown')), (1, 1, 1))
        self.assertEqual(self.ev('GARDEN.sent'), 5)                            # le sachet, un envoi
        self.assertEqual(self.ev('MEAL_COUNT.sent'), 1)                        # la graine semée, un envoi
        self.assertEqual(self.plant(106, 118)[0], 'seeded')
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class SuiteRunTests(GardenStack):
    mode = 'solo'

    def run_suite(self, start=(9, 0)):
        from test_lk_materialize import PLAYER_MOVES
        self.h.load('solo', PLAYER_MOVES)
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end '
                     'for x = 101, 104 do DIRT(x, 118, { grass = true }) end '
                     # IsoPlayer.setGodMod / isGodMod (suites voisines : RST_LKDeathSwing.lua:47-49).
                     'local P = HARNESS.classes.IsoPlayer function P:isGodMod() return self.god == true end '
                     'function P:setGodMod(b) if type(b) ~= "boolean" then '
                     'error("No implementation found for setGodMod", 2) end self.god = b end')
        self.set_month(7)
        self.h.move_player('A', 110, 110)
        if start is not None:
            self.h.jump_to(*start)
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.garden", tags = "world" }, '
                                          '{ ctx = { player = getPlayer() } }))'), True)
        for i in range(12000):
            self.h.tick()
            self.run_lua('STEP_ALL(0.1) for _, z in pairs(HARNESS.zombies) do z.onFloor = false end')
            if not self.h.eval('solo', 'RST.running()'):
                break
            self.h.advance_ms(100)
            if i % 10 == 9:
                self.h.advance(1)
        report = self.h.eval('solo', 'RST.last()')
        results = [(r.test, r.status, r.message) for r in lua_list(report.results)]
        self.assertEqual(len(results), 1, results)
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKG' in x or 'ERROR' in x][-20:]))
        return self.h.logs('solo')

    def test_suite_lk_garden_passes_on_the_doubles(self, start=(9, 0)):
        logs = self.run_suite(start=start)
        self.assertTrue(any('[LKG] measure done: 1 packet(s) of 5 seed(s), 1 furrow(s) dug, 1 seed(s) sown' in line
                            for line in logs), [x for x in logs if 'LKG' in x][-10:])
        self.assertEqual(self.run_lua('local n = 0 for _ in pairs(PLANTS) do n = n + 1 end return n'), 0)  # nettoyé
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), other_groups(self))
        self.assertEqual(self.run_lua('local n = 0 for _, it in ipairs(PANTRY.container.items.items) do '
                                      'if string.find(it.t, "Seed", 1, true) then n = n + 1 end end return n'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_lk_garden_passes_under_the_phase_sweep(self):
        """E19-T05 : changement d'heure, de jour, nuit et aube à des instants différents de la scène."""
        sweep(self, lambda phase: self.test_suite_lk_garden_passes_on_the_doubles(start=None), worlds=WORLDS)

    def test_suite_is_listed_with_its_tags(self):
        self.h.load('solo', SUITE)
        listed = lua_list(self.h.eval('solo', 'RST.list({ suite = "lk.garden", tags = "world" }, true)'))
        self.assertEqual([e.name for e in listed], ['lk.garden'])
        self.assertEqual(lua_list(listed[0].tags), ['world', 'server'])
        self.assertIsNone(listed[0].error)


# ===================================================================== vanilla réel (E19-T04, ADR banc mimétique D03)

# Aides de la pile « vanilla réel » : terre réelle (FARM_DIRT), tombe de cimetière, plante labourée et semée par le vrai
# Lua (SFarmingSystem:plow, SPlantGlobalObject:seed), croissance vanilla (growPlant) jusqu'à la récolte.
VANILLA_GARDEN = r'''
local H = HARNESS
DIRT = FARM_DIRT
function GRAVE(x, y)
    local sq = H.square(x, y, 0)
    if sq:getFloor() == nil then FARM_DIRT(x, y) end
    H.addObject(x, y, 0, setmetatable({ sprite = FARM_SPRITE('location_community_cemetary_01_0') }, H.classes.IsoObject))
    return sq
end
function FARM_PLANT(x, y, level, kind)
    local sq = H.square(x, y, 0)
    if sq:getFloor() == nil then FARM_DIRT(x, y) end
    SFarmingSystem.instance:plow(sq)
    local p = SFarmingSystem.instance:getLuaObjectAt(x, y, 0)
    p:seed(kind or 'Carrots', 0)
    p.waterLvl = level
    p:saveData()
    return p
end
function RIPEN(p)
    for _ = 1, 20 do
        if p.hasVegetable then break end
        p.waterLvl = 100
        SFarmingSystem.instance:growPlant(p, nil, true)
    end
    p.health = 60
    p:saveData()
    return p
end
function PLANT_COUNT() return SFarmingSystem.instance:getLuaObjectCount() end
'''


class VanillaGardenStack(GardenStack):
    """Pile de l'entretien + potager sur le VRAI Lua vanilla (« vanilla réel », test_lk_vanilla_farming.py) : aucune
    doublure du système de cultures ; graines, conteneurs et jardinier doublés comme dans GardenStack."""

    def make(self, root=None):
        h = UpkeepStack.make(self, root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, WEATHER_DOUBLES)
        load_vanilla_farming(h, srv)
        h.load(srv, GARDEN_STOCK_DOUBLES)
        h.load(srv, VANILLA_GARDEN)
        return h

    def plant(self, x, y):
        return self.run_lua(f'local p = {GD}.plantAt({x}, {y}, 0) if p == nil then return nil end '
                            'return p.state, p.typeOfSeed ~= "none" and p.typeOfSeed or nil')


class VanillaGardenTests(VanillaGardenStack):
    """Arrosage, récolte, sillon et semis du mod rejoués sur le vrai Lua vanilla (« vanilla réel »)."""

    mode = 'solo'

    def test_thirsty_plant_watered_with_the_vanilla_water_need(self):
        gid = self.mk()
        # Vrai semis : besoin du premier stade = waterNeeded de la définition (carottes 70), pas de plafond.
        self.run_lua('PLANT = FARM_PLANT(106, 118, 0) for _, it in ipairs(PANTRY.container.items.items) do '
                     'if it.fc and it.fc.fluid == Fluid.TaintedWater then TAINTED = it end end')
        self.assertEqual((self.ev('PLANT.waterNeeded'), self.ev('PLANT.waterNeededMax')), (70, None))
        self.assertIsNotNone(self.ev(f'({ST}.check("{gid}", {{ force = true }}))'))
        self.assertEqual(self.jobs(gid), ['water 106,118,0'])
        self.assertEqual(self.ev(f'{GD}.waterUses(PLANT)'), 8)                 # visée 70 + 10 : 8 doses
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('watered') >= 1), (self.stat('watered'), self.jobs(gid)))
        self.assertEqual(self.ev('PLANT.waterLvl'), 50)                        # 1 l d'eau croupie : 5 doses
        self.assertEqual(self.ev('PLANT:getIsoObject():getModData().waterLvl'), 50)   # sauvegardé sur l'objet
        self.assertEqual(self.ev('PLANT.lastWaterHour'), self.ev('SFarmingSystem.instance.hoursElapsed'))
        self.assertAlmostEqual(self.ev('TAINTED.fc.amount'), 0.0, places=6)
        self.settle(30)
        self.assertEqual(self.stat('watered'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_ripe_plants_harvested_with_the_vanilla_yield_and_regrowth(self):
        gid = self.mk()
        self.run_lua('CARROT = RIPEN(FARM_PLANT(106, 118, 80)) BERRY = RIPEN(FARM_PLANT(108, 118, 80, "Strawberryplant"))')
        self.assertTrue(self.ev('CARROT.hasVegetable and BERRY.hasVegetable'))
        self.assertEqual(sorted(self.jobs(gid)), ['harvest 106,118,0', 'harvest 108,118,0'])
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('harvested') >= 2), (self.stat('harvested'), self.lk()[-8:]))
        self.assertEqual(self.ev('CARROT.state'), 'harvested')                # harvestThis vanilla
        self.assertEqual(self.ev('CARROT:getIsoObject():getModData().state'), 'harvested')
        self.assertGreaterEqual(self.ev('PANTRY_COUNT("Base.Carrots")'), 1)    # getVegetablesNumber vanilla
        self.assertEqual(self.ev('BERRY.state'), 'seeded')                    # growBack : la plante repousse
        self.assertEqual(self.ev('BERRY.nbOfGrow'), 3)                         # growBack 2, puis growPlant
        self.assertFalse(self.ev('BERRY.hasVegetable'))
        self.assertGreaterEqual(self.ev('PANTRY_COUNT("Base.Strewberrie")'), 1)  # nom vanilla (ancienne doublure :
        #                                                                        Base.Strawberrie)
        self.settle(30)
        self.assertEqual(self.stat('harvested'), 2)
        self.assertEqual(self.h.errors('solo'), [])

    def test_ripe_plant_at_the_edge_of_the_home_is_harvested_from_inside(self):
        # LK15-T07 : plante mûre sur le bord nord de la zone (10 cases du foyer 110,110). La case libre la plus proche
        # (LK_Bodies.findFreeSquare) est au nord, à 12 cases : le membre n'y serait plus « au foyer » (HOME_RADIUS 10),
        # quitterait sa routine et la récolte serait reprise en boucle. La place est cherchée dans le rayon du foyer.
        gid = self.mk()
        self.run_lua('CARROT = RIPEN(FARM_PLANT(110, 100, 80))')
        self.assertEqual(self.jobs(gid), ['harvest 110,100,0'])
        home = f'LivingKnox.Groups.get("{gid}").home'
        place = self.run_lua(f'local p = {GD}.placeNear({{ kind = "harvest", x = 110, y = 100, z = 0 }}, {home}) '
                             'return p.x, p.y')
        self.assertTrue(self.ev(f'{U}.atHome({home}, {place[0]}, {place[1]}, 0)'), place)
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('harvested') >= 1), (self.stat('harvested'), self.lk()[-8:]))
        self.assertEqual(self.ev('CARROT.state'), 'harvested')
        self.assertEqual(self.stat('started'), 1)                              # prise une fois, jamais quittée
        self.assertEqual(self.h.errors('solo'), [])

    def test_furrow_dug_once_on_real_dirt_with_the_grass_removed(self):
        gid = self.mk()
        self.run_lua('SHOVEL = UPK_ITEM("Base.Shovel", { tags = { DigPlow = true } }) PANTRY.container:AddItem(SHOVEL) '
                     'DIRT(106, 118, { grass = true, tall = true }) DIRT(108, 118)')
        self.assertEqual(self.jobs(gid), ['dig 106,118,0'])
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('dug') >= 1), (self.stat('dug'), self.jobs(gid), self.lk()[-8:]))
        self.assertEqual(self.plant(106, 118), ('plow', None))
        self.assertEqual(self.ev('HARNESS.square(106, 118, 0):getObjects():size()'), 2)   # sol + sillon, herbe ôtée
        self.assertEqual(self.ev('FARM_JAVA.grassRemoved'), 1)
        self.assertEqual(self.ev('HARNESS.square(106, 118, 0):checkHaveGrass()'), False)
        self.settle(40)
        self.assertEqual((self.stat('dug'), self.ev('PLANT_COUNT()')), (1, 1))   # un sillon vide attend sa graine
        self.assertEqual(self.h.errors('solo'), [])

    def test_squares_refused_on_the_vanilla_ground_reader(self):
        gid = self.mk()
        self.run_lua('GRAVE(106, 118) DIRT(108, 112) DIRT(107, 118).roof = true DIRT(108, 118).blocked = true '
                     'DIRT(109, 118, { ground = "gravel" }) DIRT(125, 110) FARM_PLANT(110, 118, 100) '
                     'DEAD = FARM_PLANT(111, 118, 50) DEAD:killThis()')
        self.assertEqual(self.ev('DEAD.state'), 'dead')
        # Solo : la terre d'une plante morte reste lue sous la plante du miroir client (GetDirtGravelSand), comme le
        # menu vanilla ; le serveur dédié la recreuse (MultiplayerVanillaGardenTests).
        self.assertEqual(self.jobs(gid), [])
        self.assertEqual(self.run_lua(f'return select(2, {GD}.canDig(HARNESS.square(111, 118, 0)))'), 'not dirt')
        self.assertTrue(self.run_lua(f'return ({GD}.canDig(DIRT(106, 119)))'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_one_seed_sown_with_the_vanilla_seed(self):
        gid = self.mk()
        self.run_lua('DIRT(106, 118) SFarmingSystem.instance:plow(HARNESS.square(106, 118, 0)) '
                     'S1 = SEED("Base.CarrotSeed") PANTRY.container:AddItem(S1) DIRT(108, 118)')
        self.assertIsNotNone(self.ev(f'({ST}.check("{gid}", {{ force = true }}))'))
        self.assertEqual(self.jobs(gid), ['sow 106,118,0'])
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('sown') >= 1), (self.stat('sown'), self.jobs(gid), self.lk()[-8:]))
        self.assertEqual(self.plant(106, 118), ('seeded', 'Carrots'))
        self.assertEqual(self.ev(f'{GD}.plantAt(106, 118, 0).waterNeeded'), 70)
        self.assertEqual(self.ev(f'{GD}.plantAt(106, 118, 0):getIsoObject():getModData().state'), 'seeded')
        self.assertEqual(self.ev('PANTRY_COUNT("Base.CarrotSeed")'), 0)
        # Juste semée : la plante a soif (niveau 0 sous 70) ; l'arrosage suit.
        self.assertTrue(self.work(lambda: self.stat('watered') >= 1), (self.stat('watered'), self.jobs(gid)))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerVanillaGardenTests(VanillaGardenStack):
    """Serveur dédié + deux clients sur le vrai Lua vanilla (« vanilla réel ») : graines, sillon et semis par le
    serveur, recreusage d'une plante morte ; objets envoyés aux clients une fois."""

    mode = 'mp'

    def test_server_receives_digs_sows_and_redigs_a_dead_plant(self):
        gid = self.mk()
        self.run_lua('GARDENER() DIRT(106, 118)')
        sent = self.ev('GLOBAL_OBJECTS_SENT.add')
        self.jump_to(11)
        for _ in range(400):
            self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.place then '
                         'HARNESS.place(LivingKnox.Bodies.find(id), m.place.x + 0.5, m.place.y + 0.5, 0) '
                         'local e = LivingKnox.Directives.entries[id] if e and e.op == "face" and not e.done then '
                         'e.done, e.s = true, "faced" LivingKnox.Directives.sync(id, true) end end end')
            self.dpass(1)
            self.h.advance(1)
            if self.stat('sown') >= 1:
                break
        self.assertEqual((self.stat('seedPackets'), self.stat('dug'), self.stat('sown')), (1, 1, 1))
        self.assertEqual(self.plant(106, 118), ('seeded', 'Carrots'))
        self.assertEqual(self.ev('GLOBAL_OBJECTS_SENT.add') - sent, 1)         # le sillon, un envoi
        self.assertEqual(self.ev('FARM_JAVA.complete'), 1)                     # son objet du monde, un envoi
        # Plante morte : le serveur dédié la recreuse (GetDirtGravelSand ne lit pas le miroir client), retrait par
        # l'événement OnObjectAboutToBeRemoved du Java puis nouveau sillon.
        self.run_lua('DEAD = FARM_PLANT(110, 118, 50) DEAD:killThis()')
        self.assertEqual(self.ev(f'({U}.specs.dig.apply({{ kind = "dig", key = "k", x = 110, y = 118, z = 0 }}, '
                                 f'"{gid}", "m-2", HARNESS.square(110, 118, 0)))'), 'furrow dug at 110,118 with bare hands')
        self.assertEqual(self.plant(110, 118), ('plow', None))
        self.assertEqual(self.ev('GLOBAL_OBJECTS_SENT.remove'), 1)             # la plante morte
        self.assertEqual(self.ev('HARNESS.square(110, 118, 0):getObjects():size()'), 2)   # sol + nouveau sillon
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'SFarmingSystem'))
            self.assertEqual(self.h.errors(c), [])


class SuiteVanillaRunTests(VanillaGardenStack):
    """Suite lk.garden jouée sur le vrai Lua vanilla (« vanilla réel »)."""

    mode = 'solo'
    run_suite = SuiteRunTests.run_suite

    def test_suite_lk_garden_passes_on_the_vanilla_lua(self):
        logs = self.run_suite()
        self.assertTrue(any('[LKG] measure done: 1 packet(s) of 5 seed(s), 1 furrow(s) dug, 1 seed(s) sown' in line
                            for line in logs), [x for x in logs if 'LKG' in x][-10:])
        self.assertEqual(self.ev('PLANT_COUNT()'), 0)                          # nettoyé par la suite
        self.assertEqual(self.h.errors('solo'), [])


class SourceTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn('RST.suite("lk.garden"', code)

    def test_module_sources_are_kahlua_safe(self):
        self.assertTrue(set(JOBS) <= set(upkeep_files()), upkeep_files())     # chargées avec le dossier Jobs/
        for rel in [GARDEN] + JOBS:
            raw = lua_src(rel).read_text(encoding='utf-8')
            code = '\n'.join(line.split('--', 1)[0] for line in raw.splitlines())
            self.assertTrue(all(ord(ch) < 128 for ch in code), f'non ASCII character in the code of {rel}')
            for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b', r'math\.random'):
                self.assertIsNone(re.search(pattern, code), (rel, pattern))
            self.assertIn('if isClient() then return end', code, rel)


if __name__ == '__main__':
    unittest.main(verbosity=1)
