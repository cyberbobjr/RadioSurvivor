-- Living Knox : domaine du potager du foyer (LK15-T01, ADR D02) : arrosage (Jobs/LK_Job_Water.lua) et récolte
-- (Jobs/LK_Job_Harvest.lua) de plantes du système de cultures vanilla (SFarmingSystem, serveur et solo seulement).
-- Fiche : docs/annexes/conception/entretien.md (LK05-T11 : arrosage et récolte). Autorité seulement.
if isClient() then return end

require "LivingKnox/LK_Upkeep"

local Garden = LivingKnox.Garden or {}
LivingKnox.Garden = Garden

-- Réglages du potager (valeurs de départ propres au mod, raisons dans la fiche).
Garden.CFG = Garden.CFG or {
    WATER_PER_USE = 0.2,       -- litres par dose si ZomboidGlobals.farmingFluidContainerMillilitresPerUse manque
    WATER_STEP = 10,           -- niveau d'eau d'une plante par dose (SPlantGlobalObject:water)
    WATER_MARGIN = 10,         -- niveau visé = besoin de la plante + marge (borné par waterNeededMax et 100)
    HARVEST_LEVEL = 3,         -- niveau d'Agriculture prêté à getVegetablesNumber (LK05-T11)
}
-- Arrosage (LK05-T11) : eau croupie d'abord (le vanilla l'accepte : ISFarmingMenu.getWaterUsesInteger), eau potable
-- seulement si le stock n'en manque pas.
Garden.WATER_FIRST = { "TaintedWater" }
Garden.WATER_DRINK = { "Water" }

local function cfg() return Garden.CFG end
local function Groups() return LivingKnox.Groups end
local function Homes() return LivingKnox.Homes end
local function Stock() return LivingKnox.Stock end

-- ================================================================ système de cultures

-- Système de cultures vanilla (serveur et solo seulement : M/server/Farming/SFarmingSystem.lua), ou nil.
function Garden.farming()
    local s = SFarmingSystem
    return type(s) == "table" and s.instance or nil
end

local function plantAt(x, y, z)
    local sys = Garden.farming()
    if sys == nil then return nil end
    return sys:getLuaObjectAt(x, y, z)
end
Garden.plantAt = plantAt

-- Vrai s'il pleut (I4.5 : pas d'arrosage sous la pluie).
function Garden.raining()
    local cm = getClimateManager and getClimateManager() or nil
    return cm ~= nil and (cm:getPrecipitationIntensity() or 0) > 0
end

-- ================================================================ arrosage (LK05-T11)

function Garden.waterPerUse()
    local g = ZomboidGlobals
    if type(g) == "table" and type(g.farmingFluidContainerMillilitresPerUse) == "number" then
        return g.farmingFluidContainerMillilitresPerUse / 1000
    end
    return cfg().WATER_PER_USE
end

-- Doses d'eau à verser sur la plante plant (SPlantGlobalObject, table Lua du système de cultures), 0 si elle n'a pas
-- soif : vivante, semée, niveau d'eau sous son besoin du stade (waterNeeded, farming_vegetableconf.calcWater : la
-- croissance ralentit en dessous) ; niveau visé = besoin + WATER_MARGIN, borné par waterNeededMax et 100.
function Garden.waterUses(plant)
    if type(plant) ~= "table" or type(plant.isAlive) ~= "function" or not plant:isAlive() then return 0 end
    if plant.state == "plow" or type(plant.waterLvl) ~= "number" or type(plant.waterNeeded) ~= "number" then return 0 end
    if plant.waterNeeded <= 0 or plant.waterLvl >= plant.waterNeeded then return 0 end
    local target = math.min(100, plant.waterNeeded + cfg().WATER_MARGIN)
    if type(plant.waterNeededMax) == "number" and plant.waterNeededMax > plant.waterNeeded then
        target = math.min(target, plant.waterNeededMax)
    end
    return math.max(1, math.ceil((target - plant.waterLvl) / cfg().WATER_STEP))
end

-- Fluides permis pour arroser (ordre de préférence) : eau croupie, plus l'eau potable si le stock du groupe n'en manque
-- pas.
function Garden.waterSources(gid)
    local list = { Garden.WATER_FIRST }
    local a = Stock().needs(gid)
    local short = false
    for _, nd in ipairs(a ~= nil and a.needs or {}) do
        if nd.c == "water" then short = true end
    end
    if not short then list[#list + 1] = Garden.WATER_DRINK end
    return list
end

-- Premier récipient d'eau du foyer contenant au moins least litres : (récipient, fluides), ou nil.
function Garden.findWater(gid, least)
    for _, fluids in ipairs(Garden.waterSources(gid)) do
        local f = Stock().findFluid(gid, fluids, least)
        if f ~= nil then return f, fluids end
    end
    return nil
end

-- ================================================================ récolte (LK05-T11)

local function vegConf(plant)
    local conf = farming_vegetableconf
    if type(conf) ~= "table" or type(conf.props) ~= "table" or type(plant) ~= "table" then return nil end
    local props = conf.props[plant.typeOfSeed]
    return type(props) == "table" and props or nil
end

-- Vrai si la plante plant (SPlantGlobalObject) est mûre (SPlantGlobalObject:canHarvest : vivante et hasVegetable) et
-- que sa définition vanilla est connue.
function Garden.ripe(plant)
    if type(plant) ~= "table" or type(plant.isAlive) ~= "function" or not plant:isAlive() then return false end
    return plant.hasVegetable == true and vegConf(plant) ~= nil
end

-- Conteneur de dépôt du foyer (comme le dépôt d'une expédition : conteneur posé par LK_Homes, sinon le premier dans
-- l'ordre des clés) : { key, container, ... }, ou nil et une raison.
function Garden.depotOf(gid, home)
    local style, def = Homes().ready(home)
    if style == nil then return nil, def end
    local list, why = Stock().containers(gid, home, style, def ~= nil and def:getIDString() or nil)
    if list == nil then return nil, why end
    for _, ct in ipairs(list) do
        if ct.owned then return ct end
    end
    if #list > 0 then return list[1] end
    return nil, "no container at home"
end

-- Ajoute n objets de type t au conteneur de dépôt (AddItems puis envoi aux clients sur un serveur, comme
-- SFarmingSystem:harvest). Rend la liste Java des objets ajoutés, ou nil.
local function addProduce(depot, t, n)
    if type(t) ~= "string" or n < 1 then return nil end
    local list = depot.container:AddItems(t, n)
    if list ~= nil and isServer() then sendAddItemsToContainer(depot.container, list) end
    return list
end

-- Produits classés (catégorie du stock) ajoutés à la référence du stock du groupe (comme le dépôt d'une expédition).
local function track(gid, refs)
    if #refs == 0 then return end
    Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not Stock().validRef(live.stock, live.home) then
            return false, false
        end
        local have = {}
        for _, e in ipairs(live.stock.items) do have[e.i] = true end
        local added = false
        for _, r in ipairs(refs) do
            if not have[r.i] and #live.stock.items < Stock().MAX_ITEMS then
                live.stock.items[#live.stock.items + 1] = r
                added = true
            end
        end
        return added, added
    end)
end

-- Récolte de la plante plant (mûre) pour le groupe gid dans le conteneur de dépôt depot, comme
-- SFarmingSystem:harvest sans joueur. Rend le nombre de légumes, le nombre d'objets ajoutés et leurs types.
-- Effet (M/server/Farming/SFarmingSystem.lua:333-382) : nombre par getVegetablesNumber (farming_vegetableconf.lua:17-75),
-- légume et extra, graines (hasSeed), puis repousse (growBack) ou plante récoltée (harvestThis, sauvegardée).
function Garden.harvestPlant(plant, gid, depot)
    local props = vegConf(plant)
    local n = getVegetablesNumber(props.minVeg, props.maxVeg, props.minVegAutorized, props.maxVegAutorized, plant,
        cfg().HARVEST_LEVEL)
    n = math.max(0, math.floor(tonumber(n) or 0))
    local lists = {}
    lists[#lists + 1] = addProduce(depot, props.vegetableName, n)
    lists[#lists + 1] = addProduce(depot, props.produceExtra, n)
    if plant.hasSeed then
        lists[#lists + 1] = addProduce(depot, props.seedName, math.max(math.floor(n * (props.seedPerVeg or 0.5)), 1))
    end
    plant.hasVegetable = false
    plant.hasSeed = false
    if props.growBack then
        plant.nbOfGrow = props.growBack
        plant.fertilizer = 0
        Garden.farming():growPlant(plant, nil, true)
        local sprite = farming_vegetableconf.getSpriteName(plant)
        if sprite then plant:setSpriteName(sprite) end
        plant:saveData()
    else
        plant:harvestThis()   -- état « harvested », sauvegardé par deadPlant
    end
    local refs, types, count = {}, {}, 0
    for _, list in ipairs(lists) do
        for i = 0, list:size() - 1 do
            local it = list:get(i)
            if it ~= nil then
                count = count + 1
                types[#types + 1] = it:getFullType()
                local cat = Stock().categoryOf(it)
                if cat ~= nil then refs[#refs + 1] = { i = it:getID(), t = it:getFullType(), c = cat, k = depot.key } end
            end
        end
    end
    track(gid, refs)
    return n, count, types
end

-- Place d'un membre pour arroser ou récolter la plante de la tâche job : jamais à côté (un corps de zombie détruit la
-- plante de sa case, LK04-T06) ; case libre la plus proche (LK_Bodies.findFreeSquare : ni plante ni feu sur elle ni
-- autour), tournée vers la plante.
function Garden.placeNear(job)
    local B = LivingKnox.Bodies
    local sq = B ~= nil and B.findFreeSquare(job.x, job.y, job.z) or nil
    if sq == nil then return nil end
    local px, py = sq:getX(), sq:getY()
    local D = LivingKnox.Decisions
    local a = D ~= nil and D.angleTo ~= nil and D.angleTo(job.x - px, job.y - py) or nil
    return { x = px, y = py, z = job.z, a = a, ox = job.x, oy = job.y }
end

return Garden
