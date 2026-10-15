"""Tests hors jeu de la production de nourriture des groupes Living Knox (LK05-T11) : server/LivingKnox/LK_Food.lua
(lieu de cueillette lu dans la métagrille, tirages des tables de cueillette vanilla, création au dépôt), branché dans
LK_Expeditions.lua (expédition de genre « forage » : départ, cueillette tour par tour, dépôt, bascule et retour hors
écran), l'arrosage du potager (tâche « water » de LK_Upkeep.lua, eau prise par LK_Stock.drawFluid, récipient vidé
ôté de la référence par LK_Stock.untrack), la récolte du potager (tâche « harvest » de LK_Upkeep.lua, comme
SFarmingSystem:harvest sans joueur), la pêche (expédition de genre « fish » à l'aube et au crépuscule, tables du filet
vanilla Fishing.fishNet / fishNetWithBait) et la suite en jeu lk.forage (dev/.../RST_LKForage.lua).

    python RadioSurvivor/tests/test_lk_food.py

Bancs :
- logique (pile solo des expéditions de test_lk_expeditions.py) : poids des catégories et des objets comme
  forageSystem.processEntries (zone x mois x météo x jour), nombre comme forageServer rollCount, flux reproductible,
  rien hors nourriture, zones de cueillette retenues, lieu hors bâtiment, fonctions d'apparition et poison ;
- pile complète solo et serveur dédié + deux clients (groupe « deciders », caisse PANTRY garnie pour que la nourriture
  manque le plus, zone DeepForest à 12 cases du foyer) ; pile de l'entretien (test_lk_upkeep.py) pour l'arrosage.
Le vrai forageSystem.lua vanilla est chargé quand il est installé (formules getMonthMulti, getWeatherMulti,
getTimeOfDayBonus, getTimeOfDay du jeu) ; sinon ces quatre formules sont recopiées (M/shared/Foraging/forageSystem.lua
:1939-2003). Doublures relevées dans le Java et le Lua 42.21.0 : IsoMetaGrid.getZonesIntersecting (zones de la
métagrille, J/iso/IsoMetaGrid.java), Zone getType/getX/getY/getWidth/getHeight, Item.getDisplayCategory
(J/scripting/objects/Item.java:528), ClimateManager getPrecipitationIntensity, getSnowStrength, getSeason (aube,
crépuscule), PuddlesManager.getPuddlesSize, Food.getPoisonPower ; système de cultures SFarmingSystem (plow,
getLuaObjectAt, removePlant) et SPlantGlobalObject (seed, isAlive, water(nil, doses) : +10 par dose, plafond 100,
M/server/Farming/SPlantGlobalObject.lua:501-518). Elles NE PROUVENT PAS l'API réelle : seulement la logique (aucun
objet hors des tables, produits rangés au foyer et dans la référence, même résultat à l'écran et hors écran, eau du
stock retirée exactement, arrosage unique, rien chez un client). Le vrai jeu se vérifie en jeu (suite lk.forage).
"""
from __future__ import annotations

import os
import re
import sys
import unittest
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_lk_bodies import lua_list  # noqa: E402
from test_lk_expeditions import ExpeditionStack  # noqa: E402
from test_lk_upkeep import UpkeepStack  # noqa: E402

F = 'LivingKnox.Food'
EX = 'LivingKnox.Expeditions'
D = 'LivingKnox.Decisions'
ST = 'LivingKnox.Stock'
U = 'LivingKnox.Upkeep'
R = 'LivingKnox.Routines'
ROOT = Path(__file__).resolve().parents[1]
MODULE = 'server/LivingKnox/LK_Food.lua'
MODULE_FILE = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua' / MODULE
SUITE = 'shared/RST/suites/RST_LKForage.lua'
SUITE_FILE = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / SUITE
VANILLA_FORAGE = pz_paths.media_dir() / \
    'lua' / 'shared' / 'Foraging' / 'forageSystem.lua'

# Formules de forageSystem.lua:1939-2003 (banc sans le Lua vanilla installé).
FORAGE_FORMULAS = r'''
forageSystem = {}
function forageSystem.getMonthMulti(d, m)
    if not d then return 0 end
    return d.validMonths[m or (getGameTime():getMonth() + 1)] or 0
end
function forageSystem.getTimeOfDay()
    local season = getClimateManager():getSeason()
    local t = getGameTime():getTimeOfDay()
    if t < season:getDawn() or t > season:getDusk() then return "isNight" end
    return "isDay"
end
function forageSystem.getTimeOfDayBonus(d, isDay)
    if not d then return 1 end
    if isDay then return (100 + d.dayChance) / 100 end
    return (100 + d.nightChance) / 100
end
function forageSystem.getWeatherMulti(d, rain, puddle, snow)
    if not d then return 1 end
    return (100 + d.rainChance * rain + d.hasRainedChance * puddle + d.snowChance * snow) / 100
end
function forageSystem.isValidMonth(d, m) return d.validMonths[m] end
'''

# Tables de cueillette doublées (structure de forageSystem.generateLootTable, :1216-1260) : DeepForest et FarmLand
# (baies et cailloux), TownZone (cailloux) ; baies de mai à septembre, cailloux toute l'année.
FOOD_DOUBLES = r'''
local H = HARNESS
local C = H.classes
local fs = forageSystem
local function months(a, b) local t = {} for m = a, b do t[m] = 1 end return t end
local function def(o)
    for _, k in ipairs({ 'rainChance', 'hasRainedChance', 'snowChance', 'dayChance', 'nightChance' }) do
        o[k] = o[k] or 0
    end
    return o
end
SPAWN = { calls = 0, level = nil }
local function seedSpawn(ch, inv, d, items)   -- comme doWildCropSpawn : graines ajoutées à la liste rendue
    SPAWN.calls = SPAWN.calls + 1
    SPAWN.level = ch:getPerkLevel(Perks.FromString('PlantScavenging'))
    items:add(instanceItem('Base.WildSeed'))
    return items
end
local function poisonSpawn(ch, inv, d, items)  -- comme doPoisonItemSpawn, toujours empoisonné ici
    for i = 0, items:size() - 1 do items:get(i):setPoisonPower(5) end
    return items
end
FORAGE_CATS = {
    Berries = def({ name = 'Berries', zones = { DeepForest = 10, FarmLand = 5 }, validMonths = months(4, 10) }),
    Stones = def({ name = 'Stones', zones = { DeepForest = 10, FarmLand = 15, TownZone = 10 }, validMonths = months(1, 12) }),
}
FORAGE_ITEMS = {
    ['Base.BerryBlack'] = def({ type = 'Base.BerryBlack', zones = { DeepForest = 20, FarmLand = 20 }, minCount = 1,
        maxCount = 3, validMonths = months(5, 9), rainChance = -50, categories = { 'Berries' }, spawnFuncs = { seedSpawn } }),
    ['Base.BerryBlue'] = def({ type = 'Base.BerryBlue', zones = { DeepForest = 2 }, minCount = 1, maxCount = 1,
        validMonths = months(5, 9), categories = { 'Berries' }, spawnFuncs = { poisonSpawn } }),
    ['Base.Stone'] = def({ type = 'Base.Stone', zones = { DeepForest = 10, FarmLand = 10, TownZone = 10 }, minCount = 1,
        maxCount = 1, validMonths = months(1, 12), categories = { 'Stones' } }),
}
fs.zoneDefs = { DeepForest = { name = 'DeepForest' }, FarmLand = { name = 'FarmLand' }, TownZone = { name = 'TownZone' } }
fs.itemDefs = FORAGE_ITEMS
fs.catDefs = FORAGE_CATS
fs.seedTable = { ['Base.BerryBlack'] = { type = 'Base.WildSeed', chance = 100, amount = 1 } }
fs.lootTable = {}
for zone in pairs(fs.zoneDefs) do
    local lt = { categories = {}, definition = fs.zoneDefs[zone] }
    for name, cd in pairs(FORAGE_CATS) do lt.categories[name] = { items = {}, definition = cd } end
    for t, d in pairs(FORAGE_ITEMS) do
        if d.zones[zone] then lt.categories[d.categories[1]].items[t] = { definition = d } end
    end
    fs.lootTable[zone] = lt
end
Perks = Perks or {}
if Perks.FromString == nil then Perks.FromString = function(s) return s end end
-- Scripts des objets (Item.getDisplayCategory).
local Script = H.class('Item')
function Script:getDisplayCategory() return self.cat end
SCRIPTS = { ['Base.BerryBlack'] = 'Food', ['Base.BerryBlue'] = 'Food', ['Base.Stone'] = 'Material',
    ['Base.WildSeed'] = 'Gardening' }
ScriptManager = { instance = {} }
function ScriptManager.instance:getItem(t)
    if SCRIPTS[t] == nil then return nil end
    return setmetatable({ cat = SCRIPTS[t] }, Script)
end
-- Objets créés : nourriture (Food, poison), graines.
local FoodCls = C.Food
function FoodCls:getPoisonPower() return self.poison or 0 end
function FoodCls:setPoisonPower(p) self.poison = p end
MADE = 0
local prevMake = instanceItem
instanceItem = function(t)
    if t == 'Base.BerryBlack' or t == 'Base.BerryBlue' then
        MADE = MADE + 1
        INSTANCED = (INSTANCED or 0) + 1
        return MEAL_ITEM(t)
    end
    if t == 'Base.WildSeed' or t == 'Base.Stone' then
        MADE = MADE + 1
        INSTANCED = (INSTANCED or 0) + 1
        return MEAL_ITEM(t, { cat = SCRIPTS[t] })
    end
    return prevMake(t)
end
-- Climat : pluie (précipitations), neige, flaques ; aube 6 h, crépuscule 20 h.
WEATHER = { precip = 0, snow = 0, puddle = 0, dawn = 6, dusk = 20 }
local CM = C.ClimateManager or H.class('ClimateManager')
function CM:getPrecipitationIntensity() return WEATHER.precip end
function CM:getSnowStrength() return WEATHER.snow end
local Season = H.class('ClimateSeason')
function Season:getDawn() return WEATHER.dawn end
function Season:getDusk() return WEATHER.dusk end
function CM:getSeason() return setmetatable({}, Season) end
if getClimateManager == nil then getClimateManager = function() return setmetatable({}, CM) end end
local PM = H.class('PuddlesManager')
function PM:getPuddlesSize() return WEATHER.puddle end
getPuddlesManager = function() return setmetatable({}, PM) end
-- Zones de la métagrille (IsoMetaGrid.getZonesIntersecting : rectangles qui croisent la requête).
local Zone = H.class('Zone')
function Zone:getType() return self.type end
function Zone:getX() return self.x end
function Zone:getY() return self.y end
function Zone:getWidth() return self.w end
function Zone:getHeight() return self.h end
ZONES = {}
function FORAGE_ZONE(t, x, y, w, h) ZONES[#ZONES + 1] = setmetatable({ type = t, x = x, y = y, w = w, h = h }, Zone) end
local MG = C.IsoMetaGrid or H.class('IsoMetaGrid')
function MG:getZonesIntersecting(x, y, z, w, h)
    if type(x) ~= 'number' or type(h) ~= 'number' then error('No implementation found for getZonesIntersecting', 2) end
    local out = H.list()
    for _, zn in ipairs(ZONES) do
        if zn.x < x + w and zn.x + zn.w > x and zn.y < y + h and zn.y + zn.h > y then out:add(zn) end
    end
    return out
end
local Sq = C.IsoGridSquare
if rawget(Sq, 'isWaterSquare') == nil then function Sq:isWaterSquare() return self.water == true end end
-- Tirages k = 1..r de la cueillette n (mêmes conditions) : types dans l'ordre, au plus cap.
function PREDICT(gid, n, r, zone, cap)
    local c = LivingKnox.Food.conditions()
    local out = {}
    for k = 1, r do
        if #out >= cap then break end
        for _, e in ipairs((LivingKnox.Food.round(gid, n, k, zone, c, cap - #out))) do out[#out + 1] = e.t end
    end
    return out
end
'''

# Caisse PANTRY complétée : tout est au niveau visé sauf la nourriture, retirée (4 membres : visée 12, aucune).
FOOD_PANTRY = r'''
local keep = {}
for _, it in ipairs(PANTRY.container.items.items) do
    if it.cat ~= 'Food' then keep[#keep + 1] = it end
end
PANTRY.container.items.items = keep
local extra = {}
for _ = 1, 2 do extra[#extra + 1] = MEAL_ITEM('Base.Bullets9mmBox', { cat = 'Ammo' }) end
for _ = 1, 4 do extra[#extra + 1] = MEAL_ITEM('Base.NailsBox', { cat = 'Material' }) end
for _ = 1, 12 do extra[#extra + 1] = MEAL_ITEM('Base.WaterBottle') end
for _ = 1, 4 do extra[#extra + 1] = MEAL_ITEM('Base.Bandage', { cat = 'FirstAid' }) end
for _, it in ipairs(extra) do PANTRY.container:AddItem(it) end
FORAGE_ZONE('TownZone', 100, 100, 40, 40)
FORAGE_ZONE('DeepForest', 118, 122, 16, 16)
'''

# Système de cultures doublé (M/server/Farming/SFarmingSystem.lua, SPlantGlobalObject.lua).
FARM_DOUBLES = r'''
local H = HARNESS
local Sq = H.classes.IsoGridSquare
if rawget(Sq, 'isWaterSquare') == nil then function Sq:isWaterSquare() return self.water == true end end
PLANTS = {}
FARM = { watered = 0 }
local Plant = {}
Plant.__index = Plant
function Plant:isAlive()
    return self.state ~= 'destroyed' and self.state ~= 'dead' and self.state ~= 'rotten' and self.state ~= 'harvested'
end
function Plant:seed(t, skill)
    self.state, self.typeOfSeed, self.waterNeeded, self.waterNeededMax = 'seeded', t, 70, 100
end
function Plant:saveData() end
function Plant:water(source, uses)
    if source ~= nil or type(uses) ~= 'number' then error('bad water arguments', 2) end
    for _ = 1, uses do
        if self.waterLvl < 100 then self.waterLvl = math.min(100, self.waterLvl + 10) end
    end
    FARM.watered = FARM.watered + 1
end
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
SFarmingSystem = { instance = {} }
function SFarmingSystem.instance:getLuaObjectAt(x, y, z) return PLANTS[key(x, y, z)] end
function SFarmingSystem.instance:plow(sq)
    local p = setmetatable({ state = 'plow', waterLvl = 0, waterNeeded = 0, x = sq.x, y = sq.y, z = sq.z }, Plant)
    PLANTS[key(sq.x, sq.y, sq.z)] = p
    sq.plant = p
    return p
end
function SFarmingSystem.instance:removePlant(p)
    PLANTS[key(p.x, p.y, p.z)] = nil
    H.square(p.x, p.y, p.z).plant = nil
end
function FARM_PLANT(x, y, level, need)
    local p = SFarmingSystem.instance:plow(H.square(x, y, 0))
    p:seed('Carrots', 0)
    p.waterLvl, p.waterNeeded = level, need or 70
    return p
end
'''


def load_forage(h, machine):
    """Charge le forageSystem.lua vanilla (si installé) ou ses formules, puis les tables doublées."""
    h.load(machine, 'LuaEventManager.AddEvent("OnLoadedMapZones") LuaEventManager.AddEvent("OnItemFound")')
    if VANILLA_FORAGE.is_file():
        h.load(machine, VANILLA_FORAGE.read_text(encoding='utf-8-sig'))
    else:
        h.load(machine, FORAGE_FORMULAS)
    h.load(machine, FOOD_DOUBLES)


class FoodStack(ExpeditionStack):
    """Pile des expéditions + LK_Food, tables de cueillette doublées, caisse garnie hors nourriture, forêt proche."""

    def make(self, root=None):
        h = super().make(root)
        machines = ['solo'] if self.mode == 'solo' else ['server', 'A', 'B']
        for m in machines:
            h.load(m, MODULE)
        srv = 'solo' if self.mode == 'solo' else 'server'
        load_forage(h, srv)
        h.load(srv, FOOD_PANTRY)
        return h

    def draws(self, n=20, zone='DeepForest', gid='grp-1', trip=1):
        return self.run_lua(f'local c = {F}.conditions() local out = {{}} for k = 1, {n} do '
                            f'local list, text = {F}.round("{gid}", {trip}, k, "{zone}", c, 8) out[k] = text end '
                            'return table.concat(out, "|")')


class PureFoodTests(FoodStack):
    mode = 'solo'

    def test_draw_follows_the_vanilla_weights_and_is_reproducible(self):
        code = f'''local function freq(n)
            local rnd = LivingKnox.Simulation.stream(7, 3, 11, {F}.SALT)
            local c = {F}.conditions()
            local seen, counts = {{}}, {{}}
            for _ = 1, n do
                local t, cat, k = {F}.draw("DeepForest", c, rnd)
                seen[t] = (seen[t] or 0) + 1
                if t == "Base.BerryBlack" then counts[k] = (counts[k] or 0) + 1 end
            end
            return seen, counts
        end
        local a = freq(4000)
        local b = freq(4000)
        local same = true
        for t, n in pairs(a) do if b[t] ~= n then same = false end end
        local _, counts = freq(4000)
        WEATHER.precip = 1
        local rain = freq(4000)
        WEATHER.precip = 0
        return same, a["Base.Stone"], a["Base.BerryBlack"], a["Base.BerryBlue"], counts[1], counts[2], counts[3],
            rain["Base.BerryBlack"], rain["Base.BerryBlue"]'''
        same, stone, black, blue, c1, c2, c3, rblack, rblue = self.run_lua(code)
        self.assertTrue(same)                                                 # même flux, mêmes tirages
        # Catégories 10 / 10 ; dans les baies 20 / 2 (sans pluie) ; nombre ZombRand(1, 3) + 1 = 2 ou 3.
        self.assertAlmostEqual(stone / 4000, 0.5, delta=0.03)
        self.assertAlmostEqual(black / (black + blue), 20 / 22, delta=0.02)
        self.assertEqual(c1, None)
        self.assertAlmostEqual(c2 / (c2 + c3), 0.5, delta=0.05)
        # Pluie : baies noires 20 x (100 - 50) / 100 = 10 contre 2.
        self.assertAlmostEqual(rblack / (rblack + rblue), 10 / 12, delta=0.03)

    def test_out_of_season_or_outside_the_tables_nothing_is_found(self):
        self.h.date = self.h.date.replace(month=1)                           # janvier : pas de baies
        self.h._push_clock()
        self.assertEqual(self.ev(f'{F}.conditions().month'), 1)
        self.assertEqual(self.ev(f'{F}.yield("DeepForest", {F}.conditions())'), 0)
        self.assertEqual(set(self.draws().split('|')), {'Base.Stone left (Stones)'})
        self.assertEqual(self.draws(zone='Water'), '|'.join(['nothing'] * 20))   # zone sans table
        self.h.date = self.h.date.replace(month=7)
        self.h._push_clock()
        self.assertAlmostEqual(self.ev(f'{F}.yield("DeepForest", {F}.conditions())'), 0.5, places=6)
        self.assertAlmostEqual(self.ev(f'{F}.yield("FarmLand", {F}.conditions())'), 0.25, places=6)

    def test_round_keeps_only_food_from_the_tables_and_is_bounded(self):
        out = self.run_lua(f'''local c = {F}.conditions()
            local all, food = 0, 0
            for k = 1, 60 do
                local list = {F}.round("grp-1", 4, k, "DeepForest", c, 2)
                assert(#list <= 2)
                for _, e in ipairs(list) do
                    all = all + 1
                    assert(e.c == "food" and e.a == true and e.f == true)
                    assert(FORAGE_ITEMS[e.t] ~= nil and SCRIPTS[e.t] == "Food")
                end
            end
            return all''')
        self.assertGreater(out, 20)
        self.assertEqual(self.draws(), self.draws())                         # même tirage k : même résultat
        self.assertNotEqual(self.draws(trip=1), self.draws(trip=2))          # autre cueillette : autre flux

    def test_nearest_foraging_zone_and_an_outdoor_free_place(self):
        zones = self.run_lua(f'local out = {{}} for _, z in ipairs({F}.zonesNear(110, 110, 40)) do '
                             'out[#out + 1] = z.type .. ":" .. z.d .. ":" .. z.px .. "," .. z.py end '
                             'return table.concat(out, " ")')
        self.assertEqual(zones, 'DeepForest:12:118,122')                      # TownZone jamais retenue
        t = self.ev(f'(function() local g = {{ home = {{ x = 110, y = 110, z = 0 }} }} return {F}.pickTarget("grp-1", g) end)()')
        self.assertEqual((t.x, t.y, t.z, t.b, t.room, t.label, t.d), (118, 122, 0, 'forage', 'DeepForest',
                                                                       'forage DeepForest 118,122', 12))
        # Case du coin occupée : la plus proche case libre hors bâtiment de la zone.
        self.run_lua('HARNESS.square(118, 122, 0).blocked = true')
        t = self.ev(f'(function() local g = {{ home = {{ x = 110, y = 110, z = 0 }} }} return {F}.pickTarget("grp-1", g) end)()')
        self.assertEqual((t.x, t.y), (119, 122))
        # Hiver : trop peu de nourriture dans la zone.
        self.h.date = self.h.date.replace(month=12)
        self.h._push_clock()
        r = self.run_lua(f'local g = {{ home = {{ x = 110, y = 110, z = 0 }} }} return {F}.pickTarget("grp-1", g)')
        self.assertIsNone(r[0] if isinstance(r, tuple) else r)
        self.assertTrue(r[1].startswith('too little to forage now in 1 zone(s) (month 12'), r)
        self.assertTrue(self.ev(f'{F}.wanted({{ {{ c = "food", m = 3 }}, {{ c = "water", m = 1 }} }})'))
        self.assertFalse(self.ev(f'{F}.wanted({{ {{ c = "water", m = 3 }}, {{ c = "food", m = 1 }} }})'))

    def test_make_runs_the_vanilla_spawn_functions_and_throws_poisoned_food_away(self):
        n, t1, t2, bad = self.run_lua(f'local list, bad = {F}.make("Base.BerryBlack") '
                                      'return #list, list[1].t, list[2].t, bad')
        self.assertEqual((n, t1, t2, bad), (2, 'Base.BerryBlack', 'Base.WildSeed', 0))
        self.assertEqual((self.ev('SPAWN.calls'), self.ev('SPAWN.level')), (1, 3))   # cueilleur de niveau 3
        n, bad = self.run_lua(f'local list, bad = {F}.make("Base.BerryBlue") return #list, bad')
        self.assertEqual((n, bad), (0, 1))
        self.assertEqual(self.h.errors('solo'), [])

    def test_vanilla_foraging_source_is_used_when_installed(self):
        if not VANILLA_FORAGE.is_file():
            self.skipTest(f'vanilla {VANILLA_FORAGE} missing')
        self.assertEqual(self.ev('forageSystem.monthBonus'), 50)               # champ du fichier vanilla
        self.assertEqual(self.ev(f'{F}.conditions().day'), True)

    def test_module_source_is_kahlua_safe(self):
        raw = MODULE_FILE.read_bytes().decode('utf-8')
        code = re.sub(r'--[^\n]*', '', raw)
        self.assertTrue(all(ord(ch) < 128 for ch in code), 'non ASCII character outside comments')
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bbit32\b', r'[^.]\.\.\.[^.]', r'<<|>>'):
            self.assertIsNone(re.search(pattern, code), pattern)


class SoloForageTests(FoodStack):
    mode = 'solo'

    def test_foragers_go_to_the_forest_when_food_lacks_most(self):
        gid = self.mk()
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        t = self.trip(gid)
        self.assertEqual((t.kind, t.k, t.r, t.cap), ('forage', 0, 6, 8))
        self.assertEqual(lua_list(t.team), ['m-3', 'm-4'])
        self.assertEqual([(w.c, w.m) for w in lua_list(t.want)], [('food', 12)])
        self.assertEqual((t.target.b, t.target.room, t.target.x, t.target.y), ('forage', 'DeepForest', 118, 122))
        self.assertEqual((t.target.zone.x, t.target.zone.w), (118, 16))
        self.assertEqual(self.journal(gid, 'expedition'),
                         ['trip 1 to forage DeepForest 118,122 (12 squares): m-3 m-4 for food 12'])
        self.assertEqual(self.h.errors('solo'), [])

    def test_foraging_trip_brings_vanilla_food_home_like_the_offscreen_draws(self):
        gid = self.mk()
        expected = lua_list(self.ev(f'PREDICT("{gid}", 1, 6, "DeepForest", 8)'))
        pantry = self.ids('BOX_IDS(PANTRY)')
        self.assertTrue(self.run_until(lambda: self.phase(gid) == 'search', seconds=80), self.phase(gid))
        kneel = (f'return LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "m-3")) == "kneel" '
                 f'or LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "m-4")) == "kneel"')
        self.assertTrue(self.run_until(lambda: self.run_lua(kneel), seconds=10))
        self.assertTrue(self.run_until(lambda: self.phase(gid) == 'back', seconds=120), self.phase(gid))
        t = self.trip(gid)
        self.assertEqual([e.t for e in lua_list(t.carry)], expected)         # tirages k = 1..r, même flux
        self.assertTrue(all(e.a and e.f for e in lua_list(t.carry)))
        self.assertEqual(self.ev('MADE'), 0)                                   # rien créé avant le dépôt
        self.assertTrue(self.run_until(lambda: self.trip(gid) is None, seconds=80), self.phase(gid))
        new = [i for i in self.ids('BOX_IDS(PANTRY)') if i not in pantry]
        types = self.run_lua('local out = {} for _, it in ipairs(PANTRY.container.items.items) do '
                             'out[it.id] = it.t end return out')
        made = sorted(types[i] for i in new)
        berries = [x for x in expected if x == 'Base.BerryBlack']
        blues = [x for x in expected if x == 'Base.BerryBlue']
        self.assertEqual(made, sorted(berries + ['Base.WildSeed'] * len(berries)))   # baie + graine ; bleues jetées
        self.assertEqual(self.ev('MADE'), len(expected) + len(berries))
        ref = self.ids(f'REF_IDS("{gid}")')
        food_ids = [i for i in new if types[i] == 'Base.BerryBlack']
        for i in food_ids:
            self.assertIn(i, ref)
        for i in new:
            if types[i] == 'Base.WildSeed':
                self.assertNotIn(i, ref)                                       # graines : hors catégories
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, r.added, len(lua_list(r.thefts))), (0, 0, 0, 0))
        self.assertTrue(berries, expected)                                     # le flux de ce banc en trouve
        back = self.journal(gid, 'return')
        text = f'trip 1 back from forage DeepForest 118,122: 2 back, food +{len(berries)}'
        if blues:
            text += f', {len(blues)} poisoned thrown away'
        self.assertEqual(back, [text])
        s = self.ev(f'LivingKnox.Groups.get("{gid}").trips')
        self.assertEqual(lua_list(s.seen), [])                                 # une zone n'est pas un bâtiment fouillé
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 0)                     # rien pris dans un conteneur
        self.assertEqual(self.h.errors('solo'), [])

    def test_offscreen_foraging_draws_the_same_food(self):
        gid = self.mk()
        expected = lua_list(self.ev(f'PREDICT("{gid}", 1, 6, "DeepForest", 8)'))
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        self.run_lua('LivingKnox.Simulation.onEveryHours()')
        self.h.move_player('A', 400, 400)
        for m in ('m-3', 'm-4'):
            self.assertTrue(self.run_lua(f'return LivingKnox.Bodies.release("{self.npc_of(gid, m)}", "test")'))
        t = self.trip(gid)
        self.assertEqual((t.phase, t['from'], t.k), ('away', 'out', 0))
        self.h.move_player('A', 100, 100)
        self.h.advance(4 * 60)
        self.run_lua('LivingKnox.Simulation.onEveryHours()')
        t = self.trip(gid)
        if t is not None:
            self.assertEqual(t.phase, 'deliver')
            self.assertEqual([e.t for e in lua_list(t.carry)], expected)     # même résultat qu'à l'écran
        for _ in range(3):
            self.h.advance(1)
        self.assertIsNone(self.trip(gid))
        black, blue = expected.count('Base.BerryBlack'), expected.count('Base.BerryBlue')
        text = f'trip 1 back from forage DeepForest 118,122: 2 back, ' + (f'food +{black}' if black else 'nothing found')
        if blue:
            text += f', {blue} poisoned thrown away'
        self.assertEqual(self.journal(gid, 'return'), [text])
        g = self.ev(f'LivingKnox.Groups.get("{gid}")')
        self.assertTrue(all(m.alive for m in g.members.values()))
        self.assertEqual(self.h.errors('solo'), [])

    def test_no_forest_near_home_sends_the_team_to_a_building(self):
        self.run_lua('ZONES = {}')
        gid = self.mk()
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        t = self.trip(gid)
        self.assertIsNone(t.kind)
        self.assertEqual(t.target.b, '9')                                      # expédition de LK05-T05
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerForageTests(FoodStack):
    """Serveur dédié + deux clients : cueillette décidée et rangée par le serveur, mêmes consignes chez A et B."""

    mode = 'mp'

    def view(self, gid, mid):
        window = self.ev('LivingKnox.Config.RELAY.WINDOW_MS')
        self.h.tick(int(window // self.h.tick_ms) + 2)
        self.h.pump()
        npc = self.npc_of(gid, mid)
        out = {}
        for c in ('A', 'B'):
            out[c] = self.h.eval(c, f'(function() local e = LivingKnox.Executor.remote.d["{npc}"] '
                                    'return e and (e.op .. ":" .. tostring(e.x) .. "," .. tostring(e.y) .. ":" '
                                    '.. tostring(e.v)) or "none" end)()')
        return out

    def settle(self, gid, mids):
        for mid in mids:
            self.run_lua(f'local npc = MEMBER_NPC("{gid}", "{mid}") local e = LivingKnox.Directives.entries[npc] '
                         'if e and not e.done then if e.op == "move" then '
                         f'HARNESS.place(MAT_BODY("{gid}", "{mid}"), e.x + 0.5, e.y + 0.5, e.z) end '
                         'if e.op == "face" then e.done, e.s = true, "faced" LivingKnox.Directives.sync(npc, true) '
                         'end end')

    def test_both_clients_see_the_same_foraging_trip_and_the_server_stores_the_food(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Food'))
        seen = []
        for _ in range(300):
            self.settle(gid, ('m-3', 'm-4'))
            self.dpass(1)
            self.h.advance(1)
            for mid in ('m-3', 'm-4'):
                v = self.view(gid, mid)
                self.assertEqual(v['A'], v['B'])
                seen.append((self.phase(gid), v['A']))
            if self.journal(gid, 'return'):
                break
        back = self.journal(gid, 'return')
        self.assertEqual(len(back), 1, seen[-4:])
        self.assertTrue(back[0].startswith('trip 1 back from forage DeepForest 118,122: 2 back'), back)
        self.assertTrue(any(p == 'out' and v.startswith('move:11') for p, v in seen), seen[:6])
        made, poisoned = self.ev('MADE'), self.ev(f'{F}.stats.poisoned')
        self.assertGreater(made, 0)
        self.assertEqual(len(lua_list(self.ev('ADDED'))), made - poisoned)   # un envoi par objet rangé
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


# Tables du filet vanilla (M/shared/Fishing/fishing_properties.lua:693-706) et lac doublé : zone Water de la
# métagrille 100..107 x 124..131 (cases d'eau, non praticables) ; scripts des prises (grenouille : DisplayCategory
# « Frog », M/scripts/generated/items/normal.txt:9342).
FISH_DOUBLES = r'''
local H = HARNESS
Fishing = { fishes = {},
    fishNet = { 'Base.BaitFish', 'Base.Frog', 'Base.Mussels', 'Base.Seaweed', 'Base.Crayfish', 'Base.Tadpole' },
    fishNetWithBait = { 'Base.BaitFish', 'Base.Tadpole', 'Base.Crayfish', 'Base.BlueCatfish', 'Base.ChannelCatfish',
        'Base.FlatheadCatfish' } }
FISHY = {}
for _, list in ipairs({ Fishing.fishNet, Fishing.fishNetWithBait }) do
    for _, t in ipairs(list) do FISHY[t] = true SCRIPTS[t] = 'Food' end
end
SCRIPTS['Base.Frog'] = 'Frog'
local prevMake = instanceItem
instanceItem = function(t)
    if FISHY[t] then
        MADE = MADE + 1
        if SCRIPTS[t] ~= 'Food' then return MEAL_ITEM(t, { cat = SCRIPTS[t] }) end
        return MEAL_ITEM(t)
    end
    return prevMake(t)
end
function FISH_WATER(x1, y1, x2, y2, on)
    for x = x1, x2 do
        for y = y1, y2 do
            local sq = H.square(x, y, 0)
            sq.water = on ~= false
            sq.blocked = on ~= false
        end
    end
end
FORAGE_ZONE('Water', 100, 124, 8, 8)
FISH_WATER(100, 124, 107, 131)
-- Tirages k = 1..r de la sortie de pêche n : types dans l'ordre, au plus cap.
function PREDICT_FISH(gid, n, r, cap)
    local out = {}
    for k = 1, r do
        if #out >= cap then break end
        for _, e in ipairs((LivingKnox.Food.fishRound(gid, n, k, cap - #out))) do out[#out + 1] = e.t end
    end
    return out
end
'''


class FishStack(FoodStack):
    """Pile de la cueillette + tables du filet vanilla et un lac à 14 cases du foyer."""

    def make(self, root=None):
        h = super().make(root)
        h.load('solo' if self.mode == 'solo' else 'server', FISH_DOUBLES)
        return h

    def shore_ok(self, x, y):
        return self.run_lua(f'local sq = HARNESS.square({x}, {y}, 0) if sq.water then return false end '
                            f'for _, d in ipairs({{ {{0,-1}}, {{1,0}}, {{0,1}}, {{-1,0}} }}) do '
                            f'if HARNESS.square({x} + d[1], {y} + d[2], 0).water then return true end end '
                            'return false')


class PureFishTests(FishStack):
    mode = 'solo'

    def test_fishing_hours_are_dawn_and_dusk(self):
        hours = [h for h in range(24) if self.ev(f'{F}.fishHour({h})')]
        self.assertEqual(hours, [5, 6, 18, 19])
        self.assertEqual(lua_list(self.ev(f'{F}.FISH_HOURS')), [5, 18])
        self.assertEqual([h for h in range(24) if self.ev(f'{EX}.dayHour({h})')], list(range(7, 16)))

    def test_fish_drawn_only_from_the_vanilla_net_tables_and_reproducible(self):
        code = f'''local rnd = LivingKnox.Simulation.stream(7, 3, 11, {F}.FISH_SALT)
            local seen, none, net, bait = {{}}, 0, 0, 0
            for _ = 1, 4000 do
                local t, which = {F}.fishDraw(rnd)
                if t == nil then none = none + 1 else
                    seen[t] = (seen[t] or 0) + 1
                    if which == "net" then net = net + 1 else bait = bait + 1 end
                end
            end
            local types = {{}}
            for t in pairs(seen) do
                assert(FISHY[t], t)
                types[#types + 1] = t
            end
            table.sort(types)
            return none, net, bait, table.concat(types, " ")'''
        none, net, bait, types = self.run_lua(code)
        self.assertAlmostEqual(none / 4000, 0.5, delta=0.03)                  # FISH_CHANCE
        self.assertAlmostEqual(net / (net + bait), 0.5, delta=0.04)            # FISH_BAIT
        self.assertEqual(types.split(' '), sorted(set(self.ev('Fishing.fishNet').values())
                                                  | set(self.ev('Fishing.fishNetWithBait').values())))
        a = self.run_lua(f'local o = {{}} for k = 1, 30 do local l, t = {F}.fishRound("grp-1", 2, k, 8) o[k] = t end '
                         'return table.concat(o, "|")')
        b = self.run_lua(f'local o = {{}} for k = 1, 30 do local l, t = {F}.fishRound("grp-1", 2, k, 8) o[k] = t end '
                         'return table.concat(o, "|")')
        self.assertEqual(a, b)                                                 # même tirage k : même prise
        frogs, foods = self.run_lua(f'''local frogs, foods = 0, 0
            for k = 1, 400 do
                local list, text = {F}.fishRound("grp-1", 3, k, 8)
                if text:find("Base.Frog", 1, true) then
                    frogs = frogs + 1
                    assert(#list == 0)
                end
                for _, e in ipairs(list) do
                    assert(e.c == "food" and e.a == true and e.f == true and FISHY[e.t] and e.t ~= "Base.Frog")
                    foods = foods + 1
                end
                assert(#({F}.fishRound("grp-1", 3, k, 0)) == 0)                -- plus de place : rien
            end
            return frogs, foods''')
        self.assertGreater(frogs, 0)                                           # grenouille vivante laissée
        self.assertGreater(foods, 100)

    def test_shore_next_to_the_nearest_water_or_a_loaded_water_square(self):
        t = self.ev(f'(function() return {F}.fishTarget("grp-1", {{ home = {{ x = 110, y = 110, z = 0 }} }}) end)()')
        self.assertEqual((t.b, t.room, t.z), ('fish', 'Water', 0))
        self.assertTrue(self.shore_ok(t.x, t.y), (t.x, t.y))
        self.assertLessEqual(max(abs(t.x - 107), abs(t.y - 124)), 1)          # près du point d'eau le plus proche
        self.assertEqual(t.label, f'fish {t.x},{t.y}')
        # Sans zone Water connue (cellule jamais inscrite) : case d'eau chargée la plus proche.
        self.run_lua('local keep = {} for _, z in ipairs(ZONES) do if z.type ~= "Water" then keep[#keep + 1] = z end end '
                     'ZONES = keep')
        t2 = self.ev(f'(function() return {F}.fishTarget("grp-1", {{ home = {{ x = 110, y = 110, z = 0 }} }}) end)()')
        self.assertTrue(self.shore_ok(t2.x, t2.y), (t2.x, t2.y))
        # Plus d'eau : aucune pêche.
        self.run_lua('FISH_WATER(100, 124, 107, 131, false)')
        r = self.run_lua(f'return {F}.fishTarget("grp-1", {{ home = {{ x = 110, y = 110, z = 0 }} }})')
        self.assertEqual(r, (None, 'no water within 40 squares'))
        self.assertEqual(self.h.errors('solo'), [])


class SoloFishTests(FishStack):
    mode = 'solo'

    def test_no_trip_at_night_and_no_building_trip_at_dawn(self):
        gid = self.mk()
        self.run_lua(f'LivingKnox.Groups.update(function(d) local g = d.groups["{gid}"] g.objective = "supply" '
                     'g.members["m-3"].duty, g.members["m-4"].duty = "forager", "forager" return true, true end)')
        self.jump_to(4)
        self.assertEqual(self.run_lua(f'return {EX}.tryDepart("{gid}", {D}.currentMinute())'), (None, 'hour of day 4'))
        self.jump_to(5)
        self.run_lua('FISH_WATER(100, 124, 107, 131, false) ZONES = {}')
        r = self.run_lua(f'return {EX}.tryDepart("{gid}", {D}.currentMinute())')
        self.assertEqual(r, (None, 'hour of day 5 (no fishing: no water within 40 squares)'))
        self.assertIsNone(self.trip(gid))
        self.assertEqual(self.h.errors('solo'), [])

    def test_fishers_leave_at_dawn_face_the_water_and_bring_vanilla_fish_home(self):
        gid = self.mk()
        self.jump_to(5)
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        t = self.trip(gid)
        self.assertEqual((t.kind, t.k, t.r, t.cap), ('fish', 0, 8, 8))
        self.assertEqual(lua_list(t.team), ['m-3', 'm-4'])
        self.assertEqual([(w.c, w.m) for w in lua_list(t.want)], [('food', 12)])
        self.assertEqual((t.target.b, t.target.room), ('fish', 'Water'))
        self.assertTrue(self.shore_ok(t.target.x, t.target.y))
        self.assertEqual(self.journal(gid, 'expedition'),
                         [f'trip 1 to fish {t.target.x},{t.target.y} ({max(abs(t.target.x - 110), abs(t.target.y - 110))} squares): '
                          'm-3 m-4 for food 12'])
        expected = lua_list(self.ev(f'PREDICT_FISH("{gid}", 1, 8, 8)'))
        pantry = self.ids('BOX_IDS(PANTRY)')
        self.assertTrue(self.run_until(lambda: self.phase(gid) == 'search', seconds=80), self.phase(gid))
        faced = (f'local m = {EX}.memberState(MEMBER_NPC("{gid}", "m-3")) '
                 f'local k = LivingKnox.Anim.gestureOf(MEMBER_NPC("{gid}", "m-3")) == "kneel" '
                 'return m ~= nil and m.faced == true and m.spot.a ~= nil and k')
        self.assertTrue(self.run_until(lambda: self.run_lua(faced), seconds=20))
        for mid in ('m-3', 'm-4'):
            sp = self.ev(f'{EX}.memberState(MEMBER_NPC("{gid}", "{mid}")).spot')
            self.assertTrue(self.shore_ok(sp.x, sp.y), (mid, sp.x, sp.y))
        self.assertTrue(self.run_until(lambda: self.phase(gid) == 'back', seconds=200), self.phase(gid))
        t = self.trip(gid)
        self.assertEqual([e.t for e in lua_list(t.carry)], expected)         # tirages k = 1..r, même flux
        self.assertTrue(all(e.a and e.f for e in lua_list(t.carry)))
        self.assertEqual(self.ev('MADE'), 0)                                   # rien créé avant le dépôt
        self.assertTrue(self.run_until(lambda: self.trip(gid) is None, seconds=80), self.phase(gid))
        new = [i for i in self.ids('BOX_IDS(PANTRY)') if i not in pantry]
        types = self.run_lua('local out = {} for _, it in ipairs(PANTRY.container.items.items) do '
                             'out[it.id] = it.t end return out')
        self.assertEqual(sorted(types[i] for i in new), sorted(expected))
        self.assertTrue(expected)                                              # le flux de ce banc prend du poisson
        self.assertTrue(all(self.ev(f'FISHY["{x}"]') for x in expected))
        ref = self.ids(f'REF_IDS("{gid}")')
        for i in new:
            self.assertIn(i, ref)
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, r.added, len(lua_list(r.thefts))), (0, 0, 0, 0))
        self.assertEqual(self.journal(gid, 'return'),
                         [f'trip 1 back from fish {t.target.x},{t.target.y}: 2 back, food +{len(expected)}'])
        self.assertEqual(lua_list(self.ev(f'LivingKnox.Groups.get("{gid}").trips').seen), [])
        self.assertEqual(self.ev('MEAL_COUNT.removed'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_offscreen_fishing_draws_the_same_catch(self):
        gid = self.mk()
        self.jump_to(5)
        expected = lua_list(self.ev(f'PREDICT_FISH("{gid}", 1, 8, 8)'))
        self.assertTrue(self.run_until(lambda: self.trip(gid) is not None, seconds=20))
        self.run_lua('LivingKnox.Simulation.onEveryHours()')
        self.h.move_player('A', 400, 400)
        for m in ('m-3', 'm-4'):
            self.assertTrue(self.run_lua(f'return LivingKnox.Bodies.release("{self.npc_of(gid, m)}", "test")'))
        t = self.trip(gid)
        self.assertEqual((t.phase, t['from'], t.k, t.kind), ('away', 'out', 0, 'fish'))
        self.h.move_player('A', 100, 100)
        self.h.advance(4 * 60)
        self.run_lua('LivingKnox.Simulation.onEveryHours()')
        t = self.trip(gid)
        if t is not None:
            self.assertEqual(t.phase, 'deliver')
            self.assertEqual([e.t for e in lua_list(t.carry)], expected)     # même résultat qu'à l'écran
        for _ in range(3):
            self.h.advance(1)
        self.assertIsNone(self.trip(gid))
        self.assertEqual(len(self.journal(gid, 'return')), 1)
        self.assertTrue(self.journal(gid, 'return')[0].endswith(f'2 back, food +{len(expected)}'))
        self.assertEqual(self.h.errors('solo'), [])


class MultiplayerFishTests(FishStack):
    """Serveur dédié + deux clients : pêche décidée, tirée et rangée par le serveur, mêmes consignes chez A et B."""

    mode = 'mp'
    view = MultiplayerForageTests.view
    settle = MultiplayerForageTests.settle

    def test_both_clients_see_the_same_fishing_trip_and_the_server_stores_the_catch(self):
        gid = self.mk()
        self.jump_to(5)
        expected = lua_list(self.ev(f'PREDICT_FISH("{gid}", 1, 8, 8)'))
        for _ in range(300):
            self.settle(gid, ('m-3', 'm-4'))
            self.dpass(1)
            self.h.advance(1)
            for mid in ('m-3', 'm-4'):
                v = self.view(gid, mid)
                self.assertEqual(v['A'], v['B'])
            if self.journal(gid, 'return'):
                break
        back = self.journal(gid, 'return')
        self.assertEqual(len(back), 1)
        self.assertTrue(back[0].startswith('trip 1 back from fish '), back)
        self.assertTrue(back[0].endswith(f': 2 back, food +{len(expected)}'), (back, expected))
        self.assertEqual(self.ev('MADE'), len(expected))
        self.assertEqual(len(lua_list(self.ev('ADDED'))), len(expected))     # un envoi par prise rangée
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Food'))
            self.assertEqual(self.h.errors(c), [])


class WaterStack(UpkeepStack):
    """Pile de l'entretien + système de cultures doublé et climat (pluie)."""

    def ids(self, expr):
        return sorted(lua_list(self.ev(expr)))

    def make(self, root=None):
        h = super().make(root)
        srv = 'solo' if self.mode == 'solo' else 'server'
        h.load(srv, FARM_DOUBLES)
        h.load(srv, 'WEATHER = { precip = 0 } local CM = HARNESS.classes.ClimateManager or HARNESS.class("ClimateManager") '
                    'function CM:getPrecipitationIntensity() return WEATHER.precip end '
                    'if getClimateManager == nil then getClimateManager = function() return setmetatable({}, CM) end end '
                    'ZomboidGlobals.farmingFluidContainerMillilitresPerUse = 200')
        return h


class SoloWateringTests(WaterStack):
    mode = 'solo'

    def test_thirsty_plant_watered_once_with_tainted_water_of_the_stock_never_in_the_rain(self):
        gid = self.mk()
        # Eau croupie de la caisse PANTRY (1 l) ; eau potable WATER (1 l).
        self.run_lua('PLANT = FARM_PLANT(106, 118, 0, 40) for _, it in ipairs(PANTRY.container.items.items) do '
                     'if it.fc and it.fc.fluid == Fluid.TaintedWater then TAINTED = it end end')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertIsNotNone(r)
        self.assertIn(self.ev('TAINTED.id'), self.ids(f'REF_IDS("{gid}")'))   # eau croupie : catégorie eau
        self.assertEqual(self.jobs(gid), ['water 106,118,0'])
        self.assertEqual(self.ev(f'{U}.waterUses(PLANT)'), 5)                  # visée 40 + 10 : 5 doses
        self.run_lua('WEATHER.precip = 0.4')
        self.run_lua(f'{U}.reset()')
        self.assertEqual(self.jobs(gid), [])                                   # sous la pluie : rien
        self.run_lua('WEATHER.precip = 0')
        self.run_lua(f'{U}.reset()')
        drink = self.ev('WATER.fc.amount')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('watered') >= 1), (self.stat('watered'), self.jobs(gid)))
        self.assertEqual(self.ev('PLANT.waterLvl'), 50)
        self.assertAlmostEqual(self.ev('TAINTED.fc.amount'), 0.0, places=6)   # 5 doses de 0,2 l
        self.assertAlmostEqual(self.ev('WATER.fc.amount'), drink, places=6)   # eau potable intacte
        self.assertEqual(self.ev('FARM.watered'), 1)
        self.assertNotIn(self.ev('TAINTED.id'), self.ids(f'REF_IDS("{gid}")'))  # bouteille vidée : non suivie
        self.assertTrue(self.ev('PANTRY.container:containsID(TAINTED.id)'))     # gardée dans la caisse
        # Jamais deux fois ; la relecture du stock ne voit ni perte ni vol.
        for _ in range(30):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual((self.stat('watered'), self.ev('FARM.watered')), (1, 1))
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, len(lua_list(r.thefts))), (0, 0, 0))
        # Plante de nouveau assoiffée et réserve d'eau potable trop basse : l'eau potable est gardée.
        self.run_lua(f'PLANT.waterLvl = 0 {U}.reset()')
        self.assertEqual(self.jobs(gid), [])
        self.assertEqual(self.h.errors('solo'), [])

    def test_plants_outside_the_home_or_not_thirsty_are_left(self):
        gid = self.mk()
        self.run_lua('FARM_PLANT(125, 110, 0, 40) FARM_PLANT(106, 118, 60, 40) '
                     'local dead = FARM_PLANT(107, 118, 0, 40) dead.state = "destroyed"')
        self.assertEqual(self.jobs(gid), [])
        self.assertEqual(self.h.errors('solo'), [])


# Récolte doublée (M/server/Farming/SFarmingSystem.lua:333-382, SPlantGlobalObject.lua:695-766,
# farming_vegetableconf_vegetables.lua:117-142) : définitions vanilla des carottes et d'une plante qui repousse,
# getVegetablesNumber doublé (arguments relevés), ItemContainer.AddItems(type, n) (ItemContainer.java:372-380),
# sendAddItemsToContainer (LuaManager.java:9713) ; graines hors catégories du stock (DisplayCategory Gardening).
HARVEST_DOUBLES = r'''
local H = HARNESS
local C = H.classes
farming_vegetableconf = { props = {
    Carrots = { minVeg = 3, maxVeg = 6, minVegAutorized = 10, maxVegAutorized = 15, vegetableName = 'Base.Carrots',
        seedName = 'Base.CarrotSeed' },
    Strawberryplant = { minVeg = 2, maxVeg = 4, minVegAutorized = 6, maxVegAutorized = 8,
        vegetableName = 'Base.Strawberrie', seedName = 'Base.StrawberrySeed', growBack = 2, seedPerVeg = 0.25 },
} }
function farming_vegetableconf.getSpriteName(p) return 'vegetation_farming_' .. tostring(p.nbOfGrow) end
VEG = { calls = 0, n = 4 }
function getVegetablesNumber(min, max, minA, maxA, plant, skill)
    VEG.calls = VEG.calls + 1
    VEG.args = table.concat({ min, max, minA, maxA, tostring(skill) }, ',')
    return VEG.n
end
FARM.grown = 0
function SFarmingSystem.instance:growPlant(p, nextGrowing, update)
    if nextGrowing ~= nil or update ~= true then error('bad growPlant arguments', 2) end
    FARM.grown = FARM.grown + 1
end
local Plant = getmetatable(FARM_PLANT(400, 400, 0, 40))
SFarmingSystem.instance:removePlant(SFarmingSystem.instance:getLuaObjectAt(400, 400, 0))
function Plant:harvestThis() self.state, self.hasVegetable, self.saved = 'harvested', false, (self.saved or 0) + 1 end
function Plant:setSpriteName(s) self.sprite = s end
function Plant:saveData() self.saved = (self.saved or 0) + 1 end
function RIPE_PLANT(x, y, kind, seeds)
    local p = FARM_PLANT(x, y, 80, 40)
    p.typeOfSeed = kind or 'Carrots'
    p.hasVegetable, p.hasSeed, p.health, p.aphidLvl, p.slugsLvl, p.nbOfGrow = true, seeds == true, 60, 0, 0, 6
    return p
end
local SEEDS = { ['Base.CarrotSeed'] = true, ['Base.StrawberrySeed'] = true }
local Ctr = C.ItemContainer
function Ctr:AddItems(t, n)
    if type(t) ~= 'string' or type(n) ~= 'number' then error('No implementation found for AddItems', 2) end
    local list = H.list()
    for _ = 1, n do
        local it = SEEDS[t] and MEAL_ITEM(t, { cat = 'Gardening' }) or MEAL_ITEM(t)
        self.items:add(it)
        list:add(it)
    end
    return list
end
HARVEST_SENT = 0
sendAddItemsToContainer = function(c, list)
    if getmetatable(c) ~= Ctr or type(list) ~= 'table' then error('No implementation found for sendAddItemsToContainer', 2) end
    if isServer() then HARVEST_SENT = HARVEST_SENT + list:size() end
end
'''


class SoloHarvestTests(WaterStack):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', HARVEST_DOUBLES)
        return h

    def pantry_types(self, before):
        types = self.run_lua('local out = {} for _, it in ipairs(PANTRY.container.items.items) do '
                             'out[it.id] = it.t end return out')
        return sorted(types[i] for i in self.ids('BOX_IDS(PANTRY)') if i not in before)

    def test_ripe_plant_harvested_once_into_the_home_stock_even_in_the_rain(self):
        gid = self.mk()
        self.run_lua('PLANT = RIPE_PLANT(106, 118, "Carrots", true) WEATHER.precip = 0.5')
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertIsNotNone(r)
        self.assertEqual(self.jobs(gid), ['harvest 106,118,0'])                # mûre : récolte, pas d'arrosage
        before = self.ids('BOX_IDS(PANTRY)')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('harvested') >= 1), (self.stat('harvested'), self.jobs(gid)))
        self.assertEqual(self.ev('VEG.args'), '3,6,10,15,3')                   # définition vanilla, Agriculture 3
        new = self.pantry_types(before)
        self.assertEqual(new, ['Base.CarrotSeed'] * 2 + ['Base.Carrots'] * 4)   # 4 légumes, max(floor(4 x 0,5), 1)
        self.assertEqual((self.ev('PLANT.state'), self.ev('PLANT.hasVegetable'), self.ev('PLANT.hasSeed')),
                         ('harvested', False, False))
        self.assertEqual(self.stat('produce'), 6)
        ref = self.ids(f'REF_IDS("{gid}")')
        types = self.run_lua('local out = {} for _, it in ipairs(PANTRY.container.items.items) do '
                             'out[it.id] = it.t end return out')
        for i in self.ids('BOX_IDS(PANTRY)'):
            if i not in before:
                if types[i] == 'Base.Carrots':
                    self.assertIn(i, ref)                                      # légumes : nourriture suivie
                else:
                    self.assertNotIn(i, ref)                                   # graines : hors catégories
        for _ in range(30):
            self.dpass(1)
            self.h.advance(1)
        self.assertEqual((self.stat('harvested'), self.ev('VEG.calls')), (1, 1))   # jamais deux fois
        r = self.ev(f'({ST}.check("{gid}", {{ force = true }}))')
        self.assertEqual((r.missing, r.lost, r.added, len(lua_list(r.thefts))), (0, 0, 0, 0))
        up = self.journal_of(gid, 'upkeep')
        self.assertEqual(len(up), 1)
        self.assertTrue(up[0].startswith('plant at 106,118 harvested: 4 vegetable(s), 6 item(s) into '), up)
        self.assertEqual(self.h.errors('solo'), [])

    def test_plant_that_grows_back_is_kept_and_unripe_or_dead_plants_are_left(self):
        gid = self.mk()
        self.run_lua('GREEN = RIPE_PLANT(107, 118) GREEN.hasVegetable = false GREEN.waterLvl = 90 '
                     'DEAD = RIPE_PLANT(108, 118) DEAD.state = "dead" RIPE_PLANT(125, 110)')
        self.assertEqual(self.jobs(gid), [])                                   # pas mûre, morte, hors du foyer
        self.run_lua(f'BERRY = RIPE_PLANT(106, 118, "Strawberryplant", false) VEG.n = 3 {U}.reset()')
        self.assertEqual(self.jobs(gid), ['harvest 106,118,0'])
        before = self.ids('BOX_IDS(PANTRY)')
        self.jump_to(11)
        self.assertTrue(self.work(lambda: self.stat('harvested') >= 1), self.jobs(gid))
        self.assertEqual(self.pantry_types(before), ['Base.Strawberrie'] * 3)  # sans graines (hasSeed faux)
        self.assertEqual((self.ev('BERRY.state'), self.ev('BERRY.hasVegetable'), self.ev('BERRY.nbOfGrow'),
                          self.ev('BERRY.fertilizer'), self.ev('BERRY.sprite'), self.ev('FARM.grown')),
                         ('seeded', False, 2, 0, 'vegetation_farming_2', 1))     # repousse au stade 2
        self.assertEqual(self.h.errors('solo'), [])

    def journal_of(self, gid, kind):
        return [e.text for e in self.ev(f'LivingKnox.Groups.get("{gid}").log').values() if e.kind == kind]


class MultiplayerHarvestTests(WaterStack):
    """Serveur dédié + deux clients : récolte faite par le serveur, produits envoyés une fois, rien chez un client."""

    mode = 'mp'

    def make(self, root=None):
        h = super().make(root)
        h.load('server', HARVEST_DOUBLES)
        return h

    def test_server_harvests_once_and_sends_the_produce(self):
        gid = self.mk()
        for c in ('A', 'B'):
            self.assertIsNone(self.h.eval(c, 'LivingKnox.Upkeep'))
        self.run_lua('PLANT = RIPE_PLANT(106, 118, "Carrots", true)')
        self.jump_to(11)
        for _ in range(150):
            self.run_lua(f'for id, m in pairs({R}.state.npcs) do if m.kind == "upkeep" and m.place then '
                         'HARNESS.place(LivingKnox.Bodies.find(id), m.place.x + 0.5, m.place.y + 0.5, 0) '
                         'local e = LivingKnox.Directives.entries[id] if e and e.op == "face" and not e.done then '
                         'e.done, e.s = true, "faced" LivingKnox.Directives.sync(id, true) end end end')
            self.dpass(1)
            self.h.advance(1)
            if self.stat('harvested') >= 1:
                break
        self.assertEqual(self.stat('harvested'), 1)
        self.assertEqual(self.ev('HARVEST_SENT'), 6)                           # 4 carottes + 2 graines, un envoi
        self.assertEqual(self.ev('PLANT.state'), 'harvested')
        self.assertEqual(self.h.errors('server'), [])
        for c in ('A', 'B'):
            self.assertEqual(self.h.errors(c), [])


class SuiteRunTests(FoodStack):
    mode = 'solo'

    def run_suite(self, test, before=None):
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        if before:
            self.run_lua(before)
        self.h.move_player('A', 110, 110)
        self.jump_to(9)
        self.h.load('solo', SUITE)
        listed = self.h.eval('solo', 'RST.list({ suite = "lk.forage", tags = "world" }, true)[1]')
        self.assertEqual(listed.name, 'lk.forage')
        self.assertEqual(lua_list(listed.tags), ['world', 'server'])
        self.assertIsNone(listed.error)
        self.assertIs(self.h.load('solo', f'return (RST.start({{ suite = "lk.forage", test = "{test}", '
                                          'tags = "world" }, { ctx = { player = getPlayer() } }))'), True)
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
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKF2' in x or 'ERROR' in x][-20:]))
        return self.h.logs('solo')

    def test_suite_draws_pass_on_the_doubles(self):
        logs = self.run_suite('draws are reproducible and come from the vanilla tables')
        self.assertTrue(any('[LKF2] measure draws: zone DeepForest at ' in line for line in logs))
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_foraging_trip_passes_on_the_doubles(self):
        logs = self.run_suite('foragers gather vanilla food near home and store it')
        for text in ('[LKF2] measure departure: trip 1 to forage DeepForest ', '[LKF2] measure reached: ',
                     '[LKF2] measure foraged: 6 draw(s)', '[LKF2] measure home: '):
            self.assertTrue(any(text in line for line in logs), text)
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_foraging_trip_keeps_ordinary_zombies_away(self):
        # Campagne solo du 2026-10-15 : des zombies arrivés un à un à la maison de la suite tenaient le groupe en
        # alerte ; les cueilleurs montaient la garde, retour sur « search time over » sans aucun tirage.
        logs = self.run_suite('foragers gather vanilla food near home and store it',
                              'local Z = HARNESS.classes.IsoZombie '
                              'function Z:removeFromWorld() HARNESS.removeZombie(self.onlineID) end '
                              'function Z:removeFromSquare() end '
                              'STRAY = HARNESS.spawnZombie(9001, 125, 112, 0)')
        self.assertIsNone(self.ev('HARNESS.zombies[9001]'))
        self.assertTrue(any('[LKF2] measure foraged: 6 draw(s)' in line for line in logs))
        self.assertTrue(any('ordinary zombie(s) kept away from the home during the test' in line for line in logs))
        self.assertEqual(self.h.errors('solo'), [])


class SuiteWaterRunTests(WaterStack):
    mode = 'solo'

    def test_suite_watering_passes_on_the_doubles(self):
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end '
                     'local keep = {} for _, it in ipairs(PANTRY.container.items.items) do '
                     'if not (it.fc and it.fc.fluid == Fluid.TaintedWater) then keep[#keep + 1] = it end end '
                     'PANTRY.container.items.items = keep '
                     'local FC = HARNESS.classes.FluidContainer '
                     'function FC:Empty() self.fluid, self.amount = nil, 0 end '
                     'function FC:addFluid(f, a) self.fluid, self.amount = f, a end '
                     'local mk = instanceItem '
                     'instanceItem = function(t) if t == "Base.WaterBottle" then return MEAL_ITEM(t) end return mk(t) end')
        self.h.move_player('A', 110, 110)
        self.jump_to(9)
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.forage", test = "a thirsty plant of the '
                                          'home is watered from the stock", tags = "world" }, '
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
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKF2' in x or 'ERROR' in x][-20:]))
        logs = self.h.logs('solo')
        self.assertTrue(any('[LKF2] measure watered: level 0 -> ' in line for line in logs))
        self.assertEqual(self.run_lua('local n = 0 for _ in pairs(PLANTS) do n = n + 1 end return n'), 0)   # plante retirée
        self.assertEqual(self.h.errors('solo'), [])


class SuiteHarvestRunTests(WaterStack):
    mode = 'solo'

    def make(self, root=None):
        h = super().make(root)
        h.load('solo', HARVEST_DOUBLES)
        return h

    def run_harvest_suite(self, before=None):
        from test_lk_materialize import PLAYER_MOVES
        from test_lk_routines import TIME_OF_DAY
        self.h.load('solo', PLAYER_MOVES)
        self.h.load('solo', TIME_OF_DAY)
        self.run_lua('for _, it in ipairs(BEANS) do HARNESS.listRemove(PANTRY.container.items, it) end')
        if before:
            self.run_lua(before)
        self.h.move_player('A', 110, 110)
        self.jump_to(9)
        self.h.load('solo', SUITE)
        self.assertIs(self.h.load('solo', 'return (RST.start({ suite = "lk.forage", test = "a ripe plant of the '
                                          'home is harvested and its produce stored", tags = "world" }, '
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
        self.assertTrue(report.ok, (results, [x for x in self.h.logs('solo') if 'LKF2' in x or 'ERROR' in x][-20:]))
        return self.h.logs('solo')

    def test_suite_harvest_passes_on_the_doubles(self):
        logs = self.run_harvest_suite()
        self.assertTrue(any('[LKF2] measure harvested: 1 harvest(s), 4 produce item(s) stored' in line for line in logs))
        self.assertEqual(self.run_lua('local n = 0 for _ in pairs(PLANTS) do n = n + 1 end return n'), 0)   # plante retirée
        self.assertEqual(self.h.errors('solo'), [])

    def test_suite_harvest_waits_for_its_own_plant(self):
        # Campagne solo du 2026-10-15 : une autre plante mûre du jardin (lavande) récoltée d'abord comptait comme
        # LA récolte, la carotte de la suite était encore mûre (« no produce of the plant in the home containers »).
        logs = self.run_harvest_suite('OTHER = RIPE_PLANT(108, 104, "Strawberryplant", false)')
        self.assertFalse(self.ev('OTHER.hasVegetable'))                          # récoltée aussi (repousse)
        self.assertTrue(any('[LKF2] measure harvested: 2 harvest(s), 4 produce item(s) stored' in line
                            for line in logs), [x for x in logs if 'harvest' in x])
        self.assertEqual(self.h.errors('solo'), [])


class SuiteFishRunTests(FishStack):
    mode = 'solo'

    def test_suite_fishing_trip_passes_on_the_doubles(self):
        self.run_lua('IsoFlagType = IsoFlagType or {} IsoFlagType.water = IsoFlagType.water or "water" '
                     'local Sq = HARNESS.classes.IsoGridSquare '
                     'function Sq:Is(f) if f ~= IsoFlagType.water then error("No implementation found for Is", 2) end '
                     'return self.water == true end')
        logs = SuiteRunTests.run_suite(self, 'fishers bring vanilla fish home at dawn')
        self.assertTrue(any('[LKF2] measure fishing: ' in line and 'vanilla fish item(s) stored' in line
                            for line in logs))
        self.assertEqual(self.ev('#LivingKnox.Groups.list()'), 0)
        self.assertEqual(self.h.errors('solo'), [])


class SuiteTests(unittest.TestCase):
    def test_suite_source_is_ascii_and_kahlua_safe(self):
        raw = SUITE_FILE.read_bytes()
        self.assertTrue(all(b < 128 for b in raw), 'non ASCII byte in the suite')
        code = re.sub(r'--[^\n]*', '', re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S))
        for pattern in (r'\bnext\s*\(', r'\bgoto\b', r'\bcoroutine\.', r'\bunpack\b'):
            self.assertIsNone(re.search(pattern, code), pattern)
        self.assertIn('RST.suite("lk.forage"', code)
        self.assertIn('"world"', code)


if __name__ == '__main__':
    unittest.main(verbosity=1)
