"""Potager vanilla réel au banc (E19-T04, ADR banc mimétique D03) : le vrai Lua du système de cultures du jeu installé
(SFarmingSystem, SPlantGlobalObject, définitions des légumes, commandes, curseurs de la pelle et du désherbage) chargé
au-dessus des seules doublures Java qu'il touche, et sa pile réutilisée par les bancs du potager (test_lk_garden.py)
et la suite lk.upkeep jouée au banc (test_lk_upkeep.py).

    python tests/livingknox/test_lk_vanilla_farming.py

Fichiers vanilla chargés (VANILLA_FARMING, ordre du jeu : shared puis server, chemins triés sans casse,
LuaManager.java:1195-1198 ; require marqués chargés) : lus dans l'installation du jeu (tools/pz_paths.py) ou, à défaut,
les sources de référence 42.22 ; jamais copiés dans le dépôt (dépôt public). Banc sauté sans eux (VANILLA_MISSING).
Ce qui n'est PAS le vrai Lua (stand-in, écrit ici et dit) :
- ISBuildingObject : seule sa ligne de classe (ISBaseObject:derive), car son require tire l'interface du joueur
  (TimedActions/ISInventoryTransferUtil -> client/ISInventoryTransferAction -> ISInventoryPage) ; ses deux dérivés
  chargés n'en utilisent aucune méthode (ISShovelGroundCursor.GetDirtGravelSand, ISRemovePlantCursor:getRemovableObject
  appelé sur la classe) ;
- CFarmingSystem en solo : miroir client lu par ISShovelGroundCursor.GetDirtGravelSand hors serveur ; ici la plante
  du serveur à la même case (en solo, SGlobalObjectNetwork recopie chaque objet chez le client).
Doublures Java (strictes, contrôlées contre l'API 42.22, références J = java/zombie, 42.22) :
- objets globaux : harness.GLOBAL_OBJECTS (SGlobalObjects, SGlobalObjectSystem, SGlobalObject, refus du Java) ;
- IsoObject.new(case, tuile, nom) (J/iso/IsoObject.java:339-346), getSprite, getSpriteName (:2269-2274), getName,
  setName (:2261-2267), setSpriteFromName (:2012-2015 : le champ spriteName ne change pas), getProperties (:3153-3158),
  getType (:2076-2081), isGrave (:5979-5984), getAttachedAnimSprite, setSpecialTooltip, transmitModData,
  transmitCompleteItemToClients, sendObjectChange (envois du serveur comptés dans FARM_JAVA) ; IsoSprite getName,
  getProperties ; IsoSpriteInstance.getParentSprite ; PropertyContainer.has(IsoFlagType | IsoPropertyType | String)
  (J/core/properties/PropertyContainer.java:84-190) ;
- IsoGridSquare : isOutside (drapeau exterior : hors des rectangles BUILDINGS et sans toit), getFloor (:4002-4009,
  solidfloor), HasTree, setHasFlies, AddTileObject (:4994-5010, sans événement), getNextNonItemObjectIndex (:8099-8106),
  checkHaveGrass (:8914-8930), removeGrass (:8953-8983 : surcouche blends_natural_01_87, herbes canBeRemoved retirées),
  hasGrave (:9693-9700), transmitRemoveItemFromSquare (:5073-5100 -> RemoveTileObject :4878-4925 :
  OnObjectAboutToBeRemoved, retrait, OnTileRemoved ; -1 si l'objet n'est pas là) ;
- GameTime.getModData ; SandboxOptions.getOptionByName (valeurs par défaut de J/SandboxOptions.java:140, 224-228) et
  getValue ; SandboxVars.PlantResilience = 3 ; ClimateManager getSeasonName, getPrecipitationIntensity ;
  RainManager.isRaining (J/iso/objects/RainManager.java:220 -> ClimateManager.isRaining :575 : précipitations > 0) ;
  IsoWorld.getWeather (« sunny » par défaut, J/iso/IsoWorld.java:346) ; Core.getDebug (faux) ; getText (rend la clé,
  comme Translator sans traduction).
Le vrai Lua ne reproduit au banc ni la croissance réelle au fil des jours de jeu (EveryTenMinutes tourne, mais les
bancs durent quelques heures de jeu), ni les maladies tirées au hasard sur des semaines, ni la pluie et la météo
(précipitations et saison posées par le banc), ni le miroir client CFarmingSystem d'un client MP, ni la sauvegarde
gos_farming.bin.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'commun'))  # tests/commun (E26)
import bench_paths  # noqa: E402,F401  (tests/commun and tests/coreai on sys.path)
from harness import GLOBAL_OBJECTS, Harness, HarnessError, LuaError, VANILLA_MISSING, vanilla_lua_dir  # noqa: E402

# Ordre du jeu (LuaManager.java:1195-1198) : shared puis server, chemins complets triés sans casse.
VANILLA_SHARED = ['shared/ISBaseObject.lua', 'shared/luautils.lua']
VANILLA_FARMING = [
    'server/BuildingObjects/ISRemovePlantCursor.lua',
    'server/BuildingObjects/ISShovelGroundCursor.lua',
    'server/Farming/farming_vegetableconf.lua',
    'server/Farming/farming_vegetableconf_herbs.lua',
    'server/Farming/farming_vegetableconf_herbs_sprites.lua',
    'server/Farming/farming_vegetableconf_vegetables.lua',
    'server/Farming/farming_vegetableconf_vegetables_sprites.lua',
    'server/Farming/farmingCommands.lua',
    'server/Farming/SFarmingSystem.lua',
    'server/Farming/SPlantGlobalObject.lua',
    'server/Map/SGlobalObject.lua',
    'server/Map/SGlobalObjectSystem.lua',
    'server/Seasons/season.lua',
]

# Stand-in Lua de ISBuildingObject (ligne 4 du fichier vanilla seulement, voir l'en-tête).
BUILDING_OBJECT_STANDIN = r'''
ISBuildingObject = ISBuildingObject or ISBaseObject:derive("ISBuildingObject")
package.loaded["BuildingObjects/ISBuildingObject"] = true
'''

# Stand-in Lua du miroir client en solo (voir l'en-tête) ; jamais sur un serveur dédié (GetDirtGravelSand ne le lit pas).
CLIENT_MIRROR_STANDIN = r'''
if not isServer() and CFarmingSystem == nil then
    CFarmingSystem = { instance = SFarmingSystem.instance }
end
'''

FARMING_JAVA = r'''
local H = HARNESS
local C = H.classes
local Sq = C.IsoGridSquare
local Obj = C.IsoObject
FARM_JAVA = { modData = 0, complete = 0, changes = 0, grassRemoved = 0, removed = 0 }

-- Énumérations (valeurs comparées par identité, comme les enums Java exposés).
IsoFlagType = IsoFlagType or {}
for _, n in ipairs({ 'solidfloor', 'exterior', 'canBeRemoved', 'vegitation', 'canBeCut' }) do
    IsoFlagType[n] = IsoFlagType[n] or n
end
IsoPropertyType = IsoPropertyType or {}
IsoPropertyType.GRASS_FLOOR = { name = 'grassFloor' }    -- IsoPropertyType.java:241
IsoPropertyType.CUSTOM_NAME = { name = 'CustomName' }
IsoObjectType = IsoObjectType or {}
IsoObjectType.tree = IsoObjectType.tree or { name = 'tree' }
IsoObjectType.MAX = IsoObjectType.MAX or { name = 'MAX' }
IsoObjectChange = IsoObjectChange or { NAME = { name = 'NAME' }, SPRITE = { name = 'SPRITE' } }

-- Propriétés et sprites (IsoSpriteManager.getSprite : sprite créé au premier nom demandé, sans propriété).
local Props = H.class('PropertyContainer')
function Props:has(p)
    if type(p) == 'table' and p.name ~= nil then return self.flags[p.name] == true end
    if type(p) == 'string' then return self.flags[p] == true end
    error('No implementation found for PropertyContainer:has with argument ' .. tostring(p), 2)
end
function Props:get(p)
    local name = type(p) == 'table' and p.name or p
    local v = self.values[name]
    return v
end
local Sprite = H.class('IsoSprite')
function Sprite:getName() return self.spriteName end
function Sprite:getProperties() return self.props end
local Instance = H.class('IsoSpriteInstance')
function Instance:getParentSprite() return self.parent end
local sprites = {}
-- FARM_SPRITE(nom, { drapeaux }, { valeurs }) : sprite du gestionnaire (créé une fois par nom).
function FARM_SPRITE(name, flags, values, tileType)
    local s = sprites[name]
    if s == nil then
        s = setmetatable({ spriteName = name, props = setmetatable({ flags = {}, values = {} }, Props),
            tileType = tileType }, Sprite)
        sprites[name] = s
    end
    for _, f in ipairs(flags or {}) do s.props.flags[f] = true end
    for k, v in pairs(values or {}) do s.props.values[k] = v end
    return s
end

-- IsoObject (J/iso/IsoObject.java).
function C.IsoObject.new(sq, tile, name)
    if not instanceof(sq, 'IsoGridSquare') or type(tile) ~= 'string' then
        error('harness: IsoObject.new(IsoGridSquare, String, String) only', 2)
    end
    return setmetatable({ sprite = FARM_SPRITE(tile), spriteName = tile, objName = name, square = sq }, Obj)
end
IsoObject = IsoObject or C.IsoObject
function Obj:getSprite() return rawget(self, 'sprite') end
function Obj:getSpriteName()
    local s = rawget(self, 'spriteName')
    if s == nil and self:getSprite() ~= nil then return self:getSprite():getName() end
    return s
end
function Obj:getName() return rawget(self, 'objName') end
function Obj:setName(n) self.objName = n end
function Obj:setSpriteFromName(n)
    if type(n) ~= 'string' then error('No implementation found for setSpriteFromName', 2) end
    self.sprite = FARM_SPRITE(n)
end
function Obj:getProperties()
    local s = self:getSprite()
    return s ~= nil and s:getProperties() or nil
end
function Obj:getType()
    local s = self:getSprite()
    return s ~= nil and (s.tileType or IsoObjectType.MAX) or IsoObjectType.MAX
end
function Obj:isGrave()
    local s = self:getSprite()
    if s == nil then return false end
    local cn = s:getProperties():get(IsoPropertyType.CUSTOM_NAME)
    if cn ~= nil and (string.find(cn, 'Grave', 1, true) or string.find(cn, 'grave', 1, true)) then return true end
    return s:getName() ~= nil and string.find(s:getName(), 'cemetary', 1, true) ~= nil
end
function Obj:getAttachedAnimSprite() return rawget(self, 'attached') end
function Obj:setSpecialTooltip(b) self.specialTooltip = b end
function Obj:transmitModData() if isServer() then FARM_JAVA.modData = FARM_JAVA.modData + 1 end end
function Obj:transmitCompleteItemToClients() if isServer() then FARM_JAVA.complete = FARM_JAVA.complete + 1 end end
function Obj:sendObjectChange(change)
    if type(change) ~= 'table' then error('No implementation found for sendObjectChange', 2) end
    if isServer() then FARM_JAVA.changes = FARM_JAVA.changes + 1 end
end

-- Cases.
function Sq:isOutside()
    if rawget(self, 'roof') then return false end
    for _, b in ipairs(BUILDINGS or {}) do
        if self.x >= b[1] and self.x <= b[3] and self.y >= b[2] and self.y <= b[4] then return false end
    end
    return true
end
function Sq:getFloor()
    for _, o in ipairs(self.objects.items) do
        local s = o:getSprite()
        if s ~= nil and s:getProperties():has(IsoFlagType.solidfloor) then return o end
    end
    return nil
end
function Sq:HasTree() return rawget(self, 'tree') == true end
function Sq:setHasFlies(b) self.flies = b end
function Sq:AddTileObject(o, index)
    if o == nil then return end
    o.square, o.x, o.y, o.z = self, self.x, self.y, self.z
    local items = self.objects.items
    if index ~= nil and index >= 0 and index <= #items then table.insert(items, index + 1, o)
    else items[#items + 1] = o end
end
function Sq:getNextNonItemObjectIndex(i)
    H.num(i, 'getNextNonItemObjectIndex')
    for k = i, self.objects:size() - 1 do
        if not instanceof(self.objects:get(k), 'IsoWorldInventoryObject') then return k end
    end
    return -1
end
function Sq:checkHaveGrass()
    local floor = self:getFloor()
    if floor == nil then return false end
    if floor:getSprite() ~= nil and not floor:getProperties():has(IsoPropertyType.GRASS_FLOOR) then return false end
    local att = floor:getAttachedAnimSprite()
    if att ~= nil then
        for _, inst in ipairs(att.items) do
            if inst:getParentSprite():getName() == 'blends_natural_01_87' then return false end
        end
    end
    return true
end
function Sq:removeGrass()
    local floor = self:getFloor()
    if floor == nil or not floor:getSprite():getProperties():has('grassFloor') or not self:checkHaveGrass() then
        return false
    end
    floor.attached = rawget(floor, 'attached') or H.list()
    floor.attached:add(setmetatable({ parent = FARM_SPRITE('blends_natural_01_87') }, Instance))
    local i = 1
    while i <= #self.objects.items do
        local o = self.objects.items[i]
        local s = o:getSprite()
        if s ~= nil and s:getProperties():has(IsoFlagType.canBeRemoved) then table.remove(self.objects.items, i)
        else i = i + 1 end
    end
    FARM_JAVA.grassRemoved = FARM_JAVA.grassRemoved + 1
    return true
end
function Sq:hasGrave()
    for _, o in ipairs(self.objects.items) do if o:isGrave() then return true end end
    return false
end
-- RemoveTileObject (IsoGridSquare.java:4878-4925) : OnObjectAboutToBeRemoved, que l'abonné ne doit pas retirer
-- l'objet, retrait, OnTileRemoved. La doublure déjà posée par le banc (compteurs) fait le retrait.
local remove = Sq.transmitRemoveItemFromSquare
function Sq:transmitRemoveItemFromSquare(o)
    if o == nil or not self.objects:contains(o) then return -1 end
    H.trigger('OnObjectAboutToBeRemoved', o)
    if not self.objects:contains(o) then
        error('IllegalArgumentException: OnObjectAboutToBeRemoved not allowed to remove the object', 2)
    end
    local index = self.objects:indexOf(o)
    if remove ~= nil then remove(self, o) else H.listRemove(self.objects, o) end
    if self.objects:contains(o) then H.listRemove(self.objects, o) end
    FARM_JAVA.removed = FARM_JAVA.removed + 1
    H.trigger('OnTileRemoved', o)
    return index
end

-- Horloge, réglages, climat, monde.
function C.GameTime:getModData()
    local md = rawget(self, 'md')
    if md == nil then md = {} self.md = md end
    return md
end
FARM_SANDBOX = { PlantGrowingSeasons = true, KillInsideCrops = true, FarmingSpeedNew = 1.0, FarmingAmountNew = 1.0,
    PlaceDirtAboveground = false }
local BoolOpt = H.class('BooleanSandboxOption')
function BoolOpt:getValue() return FARM_SANDBOX[self.optName] end
local DoubleOpt = H.class('DoubleSandboxOption')
function DoubleOpt:getValue() return FARM_SANDBOX[self.optName] end
local Sandbox = H.class('SandboxOptions')
function Sandbox:getOptionByName(name)
    if type(name) ~= 'string' then error('No implementation found for getOptionByName', 2) end
    local v = FARM_SANDBOX[name]
    if v == nil then return nil end
    return setmetatable({ optName = name }, type(v) == 'boolean' and BoolOpt or DoubleOpt)
end
local sandbox = setmetatable({}, Sandbox)
getSandboxOptions = function() return sandbox end
SandboxVars = SandboxVars or {}
if SandboxVars.PlantResilience == nil then SandboxVars.PlantResilience = 3 end
FARM_CLIMATE = { season = 'Summer', precip = nil }
local CM = C.ClimateManager or H.class('ClimateManager')
function CM:getSeasonName() return FARM_CLIMATE.season end
if CM.getPrecipitationIntensity == nil then
    function CM:getPrecipitationIntensity() return FARM_CLIMATE.precip or 0 end
end
if getClimateManager == nil then getClimateManager = function() return setmetatable({}, CM) end end
local Rain = H.class('RainManager')
function Rain.isRaining() return getClimateManager():getPrecipitationIntensity() > 0 end
RainManager = Rain
FARM_WEATHER = 'sunny'
local baseWorld = getWorld
local function weather() return FARM_WEATHER end
-- Monde du banc gardé tel quel (table simple : le mod teste la présence de méthodes comme getFrameNo) + getWeather.
getWorld = function()
    local fields = {}
    if baseWorld ~= nil then for k, v in pairs(baseWorld()) do fields[k] = v end end
    if fields.getWeather == nil then fields.getWeather = weather end
    return fields
end
local Core = H.class('Core')
function Core:getDebug() return false end
local core = setmetatable({}, Core)
getCore = function() return core end
getText = getText or function(key) return key end

-- Sol (ISShovelGroundCursor.GetDirtGravelSand : terre = blends_natural_01_* hors sable et argile, ou
-- floors_exterior_natural*). FARM_DIRT(x, y, { grass = vrai, tall = vrai, ground = 'dirt'|'gravel'|'sand'|'street' }).
local GROUND = { dirt = 'blends_natural_01_64', grass = 'blends_natural_01_16', gravel = 'floors_exterior_natural_01_13',
    sand = 'blends_natural_01_0', street = 'blends_street_01_0' }
function FARM_DIRT(x, y, o)
    o = o or {}
    local sq = H.square(x, y, 0)
    local name = GROUND[o.ground or (o.grass and 'grass' or 'dirt')]
    local flags = { IsoFlagType.solidfloor }
    if o.grass then flags[2] = 'grassFloor' end
    H.addObject(x, y, 0, setmetatable({ sprite = FARM_SPRITE(name, flags) }, Obj))
    if o.tall then
        H.addObject(x, y, 0, setmetatable({ sprite = FARM_SPRITE('e_newgrass_1_48',
            { IsoFlagType.canBeRemoved, IsoFlagType.vegitation }) }, Obj))
    end
    return sq
end
'''


def load_vanilla_farming(h, machine):
    """Pile du potager vanilla sur la machine d'autorité (serveur dédié ou solo) : objets globaux et doublures Java,
    fichiers vanilla dans l'ordre du jeu, puis OnSGlobalObjectSystemInit (SGlobalObjects.initSystems, au chargement de
    la partie) qui crée SFarmingSystem.instance. Lève unittest.SkipTest sans le jeu."""
    if vanilla_lua_dir() is None:
        raise unittest.SkipTest(VANILLA_MISSING)
    h.load(machine, GLOBAL_OBJECTS)
    h.load(machine, FARMING_JAVA)
    h.load_vanilla(machine, *VANILLA_SHARED)
    h.load(machine, BUILDING_OBJECT_STANDIN)
    h.load_vanilla(machine, *VANILLA_FARMING)
    h.fire(machine, 'OnSGlobalObjectSystemInit')
    h.load(machine, CLIENT_MIRROR_STANDIN)
    return h


@unittest.skipIf(vanilla_lua_dir() is None, VANILLA_MISSING)
class VanillaFarmingTests(unittest.TestCase):
    """Vrai Lua vanilla du potager sur les seules doublures Java (« vanilla réel »)."""

    def setUp(self):
        self.h = Harness(with_rs=False, mode='solo')
        self.addCleanup(self.h.close)
        load_vanilla_farming(self.h, 'solo')

    def run_lua(self, code):
        return self.h.load('solo', code)

    def ev(self, expr):
        return self.h.eval('solo', expr)

    def test_vanilla_files_load_and_the_system_is_created_at_game_start(self):
        self.assertEqual(self.ev('SFarmingSystem.instance.systemName'), 'farming')
        self.assertEqual(self.ev('SGlobalObjects.getSystemCount()'), 1)
        self.assertEqual(self.ev('SFarmingSystem.instance.hoursElapsed'), 0)
        carrots = self.ev('farming_vegetableconf.props.Carrots')
        self.assertEqual((carrots.seedName, carrots.waterNeeded), ('Base.CarrotSeed', 70))
        self.assertEqual(self.ev('type(getVegetablesNumber)'), 'function')
        self.assertEqual(self.ev('type(SFarmingSystemCommands.seed)'), 'function')
        self.assertEqual(self.ev('type(ISShovelGroundCursor.GetDirtGravelSand)'), 'function')
        # Un fichier ne tourne qu'une fois (LuaManager.RunLuaInternal) : rechargé, l'instance reste.
        self.run_lua('FIRST = SFarmingSystem.instance')
        self.h.load_vanilla('solo', 'server/Farming/SFarmingSystem.lua')
        self.assertTrue(self.ev('SFarmingSystem.instance == FIRST'))
        self.assertEqual(self.h.errors('solo'), [])

    def test_java_refuses_a_second_object_on_a_square_and_foreign_objects(self):
        self.run_lua('FARM_DIRT(10, 10) SFarmingSystem.instance:plow(HARNESS.square(10, 10, 0))')
        with self.assertRaisesRegex(LuaError, 'already an object at 10,10,0'):
            self.run_lua('SFarmingSystem.instance:plow(HARNESS.square(10, 10, 0))')
        with self.assertRaisesRegex(LuaError, 'object not in this system'):
            self.run_lua('local other = SGlobalObjects.registerSystem("campfire") '
                         'other:removeObject(SFarmingSystem.instance.system:getObjectAt(10, 10, 0))')
        with self.assertRaisesRegex(LuaError, 'object is null'):
            self.run_lua('SFarmingSystem.instance.system:removeObject(nil)')
        with self.assertRaisesRegex(LuaError, 'expected string'):
            self.run_lua('SFarmingSystem.instance.system:setObjectModDataKeys({ 3 })')
        with self.assertRaisesRegex(LuaError, 'system with that name already exists'):
            self.run_lua('SGlobalObjects.newSystem("farming")')
        with self.assertRaisesRegex(LuaError, 'expected 3 arguments, got 2'):
            self.run_lua('SFarmingSystem.instance.system:newObject(1, 2)')

    def test_plow_seed_water_harvest_and_remove_on_the_vanilla_lua(self):
        self.run_lua('SQ = FARM_DIRT(10, 10) SFarmingSystem.instance:plow(SQ) P = SFarmingSystem.instance:getLuaObjectAt(10, 10, 0)')
        self.assertTrue(self.ev('SQ:hasFarmingPlant()'))
        self.assertEqual((self.ev('P.state'), self.ev('P.waterLvl'), self.ev('P.waterNeeded')), ('plow', 0, 0))
        self.assertEqual(self.ev('P:getIsoObject():getSpriteName()'), 'vegetation_farming_01_1')
        self.assertEqual(self.ev('P:getIsoObject():getModData().state'), 'plow')
        self.assertEqual(self.ev('SQ:getModData().plowDay ~= nil'), True)
        # Semis : besoin en eau de la définition (70 pour les carottes), aucun plafond (waterNeededMax nil).
        self.run_lua('P:seed("Carrots", 0)')
        self.assertEqual((self.ev('P.state'), self.ev('P.typeOfSeed'), self.ev('P.nbOfGrow')), ('seeded', 'Carrots', 1))
        self.assertEqual((self.ev('P.waterNeeded'), self.ev('P.waterNeededMax')), (70, None))
        self.assertIsNotNone(self.ev('P.nextGrowing'))
        self.run_lua('P:water(nil, 3)')
        self.assertEqual(self.ev('P.waterLvl'), 30)
        self.assertEqual(self.ev('P:getIsoObject():getModData().waterLvl'), 30)   # saveData
        # Récolte vanilla par la commande du joueur absente : la plante mûre passe « harvested » (harvestThis).
        self.run_lua('P.hasVegetable = true P:harvestThis()')
        self.assertEqual((self.ev('P.state'), self.ev('P:isAlive()')), ('harvested', False))
        # removePlant : retrait de l'objet du monde, dont l'événement retire l'objet global (SGlobalObjectSystem).
        self.run_lua('SFarmingSystem.instance:removePlant(P)')
        self.assertFalse(self.ev('SQ:hasFarmingPlant()'))
        self.assertEqual(self.ev('SFarmingSystem.instance:getLuaObjectCount()'), 0)
        self.assertEqual(self.ev('P.state'), None)                         # table de l'objet vidée (Reset)
        self.run_lua('SFarmingSystem.instance:plow(SQ)')                   # la case se relaboure
        self.assertEqual(self.ev('SFarmingSystem.instance:getLuaObjectCount()'), 1)
        self.assertEqual(self.h.errors('solo'), [])

    def test_shovel_cursor_reads_the_ground_like_the_game(self):
        self.run_lua('FARM_DIRT(1, 1) FARM_DIRT(2, 1, { grass = true }) FARM_DIRT(3, 1, { ground = "gravel" }) '
                     'FARM_DIRT(4, 1, { ground = "sand" }) FARM_DIRT(5, 1, { ground = "street" })')
        kinds = [self.ev(f'(ISShovelGroundCursor.GetDirtGravelSand(HARNESS.square({x}, 1, 0)))') for x in range(1, 7)]
        self.assertEqual(kinds, ['dirt', 'dirt', 'gravel', 'sand', None, None])
        # Solo : la terre d'une case qui porte une plante (miroir client) n'est plus de la terre.
        self.run_lua('SFarmingSystem.instance:plow(HARNESS.square(1, 1, 0))')
        self.assertIsNone(self.ev('(ISShovelGroundCursor.GetDirtGravelSand(HARNESS.square(1, 1, 0)))'))

    def test_ten_minute_updates_run_for_two_days_without_error(self):
        self.run_lua('SQ = FARM_DIRT(10, 10) SFarmingSystem.instance:plow(SQ) '
                     'P = SFarmingSystem.instance:getLuaObjectAt(10, 10, 0) P:seed("Carrots", 0) P:water(nil, 7)')
        self.h.advance(48 * 60)
        self.assertEqual(self.ev('SFarmingSystem.instance.hoursElapsed'), 48)
        self.assertEqual(self.ev('P.state'), 'seeded')
        self.assertLess(self.ev('P.waterLvl'), 70)                         # l'eau baisse toutes les 5 heures
        self.assertGreater(self.ev('GLOBAL_OBJECTS_SENT.command'), 0)       # hoursElapsed envoyé aux clients
        self.assertEqual(self.h.errors('solo'), [])


class VanillaPathTests(unittest.TestCase):
    def test_missing_game_skips_with_a_clear_message(self):
        import harness
        saved = harness.vanilla_lua_dir
        harness.vanilla_lua_dir = lambda: None
        try:
            with Harness(with_rs=False, mode='solo') as h:
                with self.assertRaises(unittest.SkipTest) as cm:
                    h.load_vanilla('solo', 'shared/ISBaseObject.lua')
                self.assertIn('PZ_STEAM_LIBRARY', str(cm.exception))
        finally:
            harness.vanilla_lua_dir = saved

    def test_vanilla_path_must_name_a_side(self):
        with Harness(with_rs=False, mode='solo') as h:
            if vanilla_lua_dir() is None:
                self.skipTest(VANILLA_MISSING)
            with self.assertRaises(HarnessError):
                h.load_vanilla('solo', 'Farming/SFarmingSystem.lua')


if __name__ == '__main__':
    unittest.main(verbosity=1)
