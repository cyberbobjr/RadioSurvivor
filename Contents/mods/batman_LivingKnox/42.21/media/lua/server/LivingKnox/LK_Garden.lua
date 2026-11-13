-- Living Knox : domaine du potager du foyer (LK15-T01, ADR D02) : arrosage (Jobs/LK_Job_Water.lua), récolte
-- (Jobs/LK_Job_Harvest.lua), sillon (Jobs/LK_Job_Dig.lua, LK15-T04), semis (Jobs/LK_Job_Sow.lua, LK15-T05) et graines
-- reçues (Jobs/LK_Job_SeedSupply.lua, LK15-T06) avec le système de cultures vanilla (SFarmingSystem, serveur et solo
-- seulement). Fiche : docs/annexes/conception/entretien.md (potager). Autorité seulement.
-- M = media/lua vanilla 42.22 ; J = Java 42.22 (zombie/...).
if isClient() then return end

require "LivingKnox/LK_Upkeep"

local Garden = LivingKnox.Garden or {}
LivingKnox.Garden = Garden

-- Réglages du potager (valeurs de départ propres au mod, raisons dans la fiche ; Q01 de l'ADR pour MAX_PLOTS et SEED_*).
Garden.CFG = Garden.CFG or {
    WATER_PER_USE = 0.2,       -- litres par dose si ZomboidGlobals.farmingFluidContainerMillilitresPerUse manque
    WATER_STEP = 10,           -- niveau d'eau d'une plante par dose (SPlantGlobalObject:water)
    WATER_MARGIN = 10,         -- niveau visé = besoin de la plante + marge (borné par waterNeededMax et 100)
    HARVEST_LEVEL = 3,         -- niveau d'Agriculture prêté à getVegetablesNumber (LK05-T11)
    MAX_PLOTS = 6,             -- LK15-T04 : sillons et plantes vivantes au plus dans la zone du foyer
    DIG_MINUTES = 3,           -- LK15-T04 : minutes de jeu pour creuser avec un outil ; mains nues : le double
    SOW_MINUTES = 2,           -- LK15-T05 : minutes de jeu pour semer une graine
    SEED_LOW = 2,              -- LK15-T06 : graines semables du stock sous lesquelles un sachet arrive
    SEED_DAYS = 7,             -- LK15-T06 : au plus un sachet tous les 7 jours de jeu par groupe
    SEED_PACKET = 5,           -- LK15-T06 : graines d'un sachet (Base.<Légume>BagSeed2, recipes_farming.txt:111-127)
    SEED_MINUTES = 2,          -- LK15-T06 : minutes de jeu pour ranger le sachet
}
-- LK15-T04 : outil de labour accepté par le menu vanilla (predicateDigPlow, M/client/Farming/ISUI/ISFarmingMenu.lua
-- :20-22 : objet non cassé portant le tag ItemTag.DIG_PLOW, base:digplow, J/scripting/objects/ItemTag.java:115 :
-- pelles, truelles, binettes, pioches...). Nom du champ de ItemTag.
Garden.DIG_PLOW = "DIG_PLOW"
-- LK15-T06 : variétés des sachets reçus (clés de farming_vegetableconf.props), tirées parmi celles de saison.
Garden.SEED_VARIETIES = { "Carrots", "Potatoes", "Cabbages", "Tomato" }

-- Mémoire (non sauvegardée, comme le reste de l'entretien : ADR, Conséquences) : jour du dernier sachet par groupe.
Garden.state = Garden.state or { seedDay = {} }

function Garden.reset()
    Garden.state = { seedDay = {} }
end
-- Arrosage (LK05-T11) : eau croupie d'abord (le vanilla l'accepte : ISFarmingMenu.getWaterUsesInteger), eau potable
-- seulement si le stock n'en manque pas.
Garden.WATER_FIRST = { "TaintedWater" }
Garden.WATER_DRINK = { "Water" }

local function cfg() return Garden.CFG end
local function Groups() return LivingKnox.Groups end
local function Homes() return LivingKnox.Homes end
local function Stock() return LivingKnox.Stock end
local function Upkeep() return LivingKnox.Upkeep end

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

-- Objets de la liste Java list ajoutés au dépôt depot : types dans types, objets classés (catégorie du stock) dans refs
-- ({ i, t, c, k }, à suivre par track). Rend le nombre d'objets.
local function collect(list, depot, refs, types)
    local count = 0
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if it ~= nil then
            count = count + 1
            types[#types + 1] = it:getFullType()
            local cat = Stock().categoryOf(it)
            if cat ~= nil then refs[#refs + 1] = { i = it:getID(), t = it:getFullType(), c = cat, k = depot.key } end
        end
    end
    return count
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
    local refs, types = {}, {}
    local count = 0
    for _, list in ipairs(lists) do count = count + collect(list, depot, refs, types) end
    track(gid, refs)
    return n, count, types
end

-- Case libre (LK_Bodies.freeSquare) la plus proche de (x, y, z), à FREE_RADIUS cases au plus, où un membre reste « au
-- foyer » home (Upkeep.atHome, LK15-T07) ; même ordre que LK_Bodies.findFreeSquare (anneau, puis distance, puis y et
-- x), qui ne connaît pas le foyer. Rend la case, ou nil.
local function freeSquareAtHome(B, x, y, z, home)
    local cell = getCell()
    for r = 0, B.FREE_RADIUS do
        local best, bestD = nil, nil
        for dy = -r, r do
            for dx = -r, r do
                local d = dx * dx + dy * dy
                if math.max(math.abs(dx), math.abs(dy)) == r and (bestD == nil or d < bestD)
                    and Upkeep().atHome(home, x + dx, y + dy, z) then
                    local sq = cell:getGridSquare(x + dx, y + dy, z)
                    if B.freeSquare(sq) then best, bestD = sq, d end
                end
            end
        end
        if best ~= nil then return best end
    end
    return nil
end

-- Place d'un membre pour arroser, récolter ou semer la plante de la tâche job : jamais à côté (un corps de zombie
-- détruit la plante de sa case, LK04-T06) ; case libre la plus proche (LK_Bodies.findFreeSquare : ni plante ni feu sur
-- elle ni autour), restée au foyer home quand il est donné (LK15-T07 : plante au bord de la zone), tournée vers la
-- plante.
function Garden.placeNear(job, home)
    local B = LivingKnox.Bodies
    if B == nil then return nil end
    local sq
    if home ~= nil then
        sq = freeSquareAtHome(B, job.x, job.y, job.z, home)
    else
        sq = B.findFreeSquare(job.x, job.y, job.z)
    end
    if sq == nil then return nil end
    local px, py = sq:getX(), sq:getY()
    local D = LivingKnox.Decisions
    local a = D ~= nil and D.angleTo ~= nil and D.angleTo(job.x - px, job.y - py) or nil
    return { x = px, y = py, z = job.z, a = a, ox = job.x, oy = job.y }
end

-- ================================================================ sillon (LK15-T04)

-- Vrai si la plante plant occupe sa case pour le menu vanilla : sillon (état « plow ») ou plante vivante ; une plante
-- morte, récoltée ou détruite ne compte pas (ISFarmingMenu.canDigHereSquare, M/client/Farming/ISUI/ISFarmingMenu.lua
-- :518-524).
local function holds(plant)
    if type(plant) ~= "table" then return false end
    if plant.state == "plow" then return true end
    return type(plant.isAlive) == "function" and plant:isAlive() == true
end

-- Vrai si la case sq se creuse comme le permet le menu vanilla (ISFarmingMenu.canDigHereSquare, ISFarmingMenu.lua
-- :514-534) : ni tombe, ni sillon ni plante vivante, rez-de-chaussée (le réglage PlaceDirtAboveground n'est pas suivi :
-- ADR D07), case libre (isFree(false)), sol de terre (ISShovelGroundCursor.GetDirtGravelSand = "dirt",
-- M/server/BuildingObjects/ISShovelGroundCursor.lua:97-132 ; absent : rien ne se creuse). Rend vrai, ou faux et une
-- raison.
function Garden.canDig(sq)
    local cursor = ISShovelGroundCursor
    if type(cursor) ~= "table" or type(cursor.GetDirtGravelSand) ~= "function" then return false, "no ground reader" end
    if sq == nil then return false, "no square" end
    if sq:getZ() ~= 0 then return false, "not on the ground floor" end
    if sq:hasGrave() then return false, "grave" end
    if holds(plantAt(sq:getX(), sq:getY(), sq:getZ())) then return false, "plant" end
    if not sq:isFree(false) then return false, "not free" end
    if cursor.GetDirtGravelSand(sq) ~= "dirt" then return false, "not dirt" end
    return true
end

-- Potager de la zone area (Upkeep.area) : nombre de cases tenues (sillons et plantes vivantes) et liste des sillons
-- vides { x, y } (état « plow »), dans l'ordre de la zone.
function Garden.plots(area)
    local n, empty = 0, {}
    for _, e in ipairs(area.squares) do
        if e.sq:hasFarmingPlant() then
            local plant = plantAt(e.x, e.y, area.z)
            if holds(plant) then
                n = n + 1
                if plant.state == "plow" then empty[#empty + 1] = { x = e.x, y = e.y } end
            end
        end
    end
    return n, empty
end

-- Première case de la zone où creuser un sillon : hors du bâtiment du foyer, à l'air libre (isOutside), creusable
-- (Garden.canDig), la case entière « au foyer » (Upkeep.atHome, LK15-T07) : ses voisines côté foyer, où se tenir pour la
-- creuser puis la soigner (Garden.placeNear), le restent aussi ; { x, y }, ou nil.
function Garden.digSpot(area)
    for _, e in ipairs(area.squares) do
        if not e.inside and Upkeep().atHome(area.home, e.x, e.y, area.z) and Garden.canDig(e.sq)
            and e.sq:isOutside() then
            return { x = e.x, y = e.y }
        end
    end
    return nil
end

-- Outil de labour du stock du groupe gid (Garden.DIG_PLOW, non cassé) : { key, i, t, ... }, ou nil.
function Garden.digTool(gid)
    local tag = ItemTag ~= nil and ItemTag[Garden.DIG_PLOW] or nil
    if tag == nil then return nil end
    return (Stock().findItem(gid, function(it) return not it:isBroken() and it:hasTag(tag) end))
end

-- Creuse un sillon sur la case sq comme ISPlowAction:complete sans joueur (M/shared/Farming/TimedActions/
-- ISPlowAction.lua:110-124) : herbes hautes retirées (SFarmingSystem:removeTallGrass, envoi par
-- transmitRemoveItemFromSquare, M/server/Farming/SFarmingSystem.lua:562-574), herbe du sol retirée (removeGrass, envoi
-- par le Java, J/iso/IsoGridSquare.java:8953-8983), plante morte de la case retirée, puis SFarmingSystem:plow (objet
-- transmis aux clients par SPlantGlobalObject:addObject, SFarmingSystem.lua:508-536, SPlantGlobalObject.lua:208-217).
function Garden.dig(sq)
    local sys = Garden.farming()
    sys:removeTallGrass(sq)
    local floor = sq:getFloor()
    if floor ~= nil and IsoPropertyType ~= nil and floor:getProperties():has(IsoPropertyType.GRASS_FLOOR)
        and sq:checkHaveGrass() == true then
        sq:removeGrass()
    end
    local dead = plantAt(sq:getX(), sq:getY(), sq:getZ())
    if dead ~= nil then sys:removePlant(dead) end
    sys:plow(sq)
end

-- ================================================================ graines et semis (LK15-T05)

-- Mois de jeu courant 1..12 (getGameTime():getMonth() + 1, comme SPlantGlobalObject:isSowMonth,
-- M/server/Farming/SPlantGlobalObject.lua:162-173), ou nil sans horloge.
function Garden.month()
    local gt = getGameTime and getGameTime() or nil
    if gt == nil then return nil end
    return gt:getMonth() + 1
end

local function contains(list, v)
    for _, x in ipairs(type(list) == "table" and list or {}) do
        if x == v then return true end
    end
    return false
end

-- Graines d'une définition vanilla : seedTypes, sinon { seedName } (ISFarmingMenu.lua:1138).
local function seedTypesOf(props)
    if type(props.seedTypes) == "table" then return props.seedTypes end
    return { props.seedName }
end

-- Vrai si la variété typeOfSeed se sème au mois month (sowMonth de sa définition vanilla ; sans sowMonth : jamais).
function Garden.inSeason(typeOfSeed, month)
    local conf = farming_vegetableconf
    local props = type(conf) == "table" and type(conf.props) == "table" and conf.props[typeOfSeed] or nil
    return type(props) == "table" and month ~= nil and contains(props.sowMonth, month)
end

-- Graines semables au mois month : { [type complet de graine] = variété } d'après farming_vegetableconf.props
-- (variétés prises dans l'ordre de leurs clés : une graine commune à deux variétés va toujours à la même).
local function seedIndex(month)
    local conf = farming_vegetableconf
    local out = {}
    if month == nil or type(conf) ~= "table" or type(conf.props) ~= "table" then return out end
    local keys = {}
    for k, v in pairs(conf.props) do
        if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local props = conf.props[k]
        if contains(props.sowMonth, month) then
            for _, t in ipairs(seedTypesOf(props)) do
                if type(t) == "string" and out[t] == nil then out[t] = k end
            end
        end
    end
    return out
end

-- Variété que l'objet item permet de semer d'après l'index index (seedIndex) : jamais un objet de nourriture (pomme
-- de terre, tomate : le groupe ne sème pas ses vivres). Rend la variété, ou nil.
local function sowableIn(item, index)
    if item == nil or instanceof(item, "Food") then return nil end
    return index[item:getFullType()]
end

-- Variété (clé de farming_vegetableconf.props) que l'objet item permet de semer au mois month : son type est une
-- graine de la définition (seedTypes ou seedName), la variété est de saison, l'objet n'est pas de la nourriture. Rend
-- la variété, ou nil.
function Garden.sowable(item, month)
    return sowableIn(item, seedIndex(month))
end

-- Nombre de graines semables au mois month dans les conteneurs du foyer du groupe gid, ou nil et une raison.
function Garden.seedCount(gid, month)
    local containers, why = Stock().homeContainers(gid)
    if containers == nil then return nil, why end
    local index = seedIndex(month)
    local n = 0
    for _, ct in ipairs(containers) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            if sowableIn(items:get(j), index) ~= nil then n = n + 1 end
        end
    end
    return n
end

-- Première graine semable au mois month du foyer : { key, i, t, ... }, ou nil.
function Garden.findSeed(gid, month)
    local index = seedIndex(month)
    return (Stock().findItem(gid, function(it) return sowableIn(it, index) ~= nil end))
end

-- Prend UNE graine semable au mois month dans le foyer (LK_Stock.takeItem : retirée du conteneur, envoyée aux clients
-- sur un serveur, ôtée de la référence du stock dans la même écriture si elle y était suivie). Rend { i, t, k } et la
-- variété, ou nil et une raison.
function Garden.takeSeed(gid, month, who, use)
    local index = seedIndex(month)
    local taken, item = Stock().takeItem(gid, function(it) return sowableIn(it, index) ~= nil end, who, use)
    if taken == nil then return nil, item end
    return taken, sowableIn(item, index)
end

-- ================================================================ graines reçues (LK15-T06)

-- Vrai si le groupe g a un jardinier : un membre vivant dont le rôle porte le comportement « garden »
-- (LivingKnox.Decisions.allowedOf, comme la préférence prefer = "garden" du moteur des tâches).
function Garden.hasGardener(g)
    local D = LivingKnox.Decisions
    if type(g) ~= "table" or type(g.members) ~= "table" or D == nil or D.allowedOf == nil then return false end
    for _, m in pairs(g.members) do
        if type(m) == "table" and m.alive and D.allowedOf(g.type, m.role).garden == true then return true end
    end
    return false
end

-- Variété du sachet du jour day (jour de jeu, 1 = premier) au mois month : parmi les SEED_VARIETIES de saison (ordre de
-- la liste), une par fenêtre de SEED_DAYS jours, à tour de rôle (reproductible, sans hasard). Rend { typeOfSeed, seed }
-- (seed = première graine de la définition vanilla), ou nil (aucune variété de saison).
function Garden.seedVariety(day, month)
    local conf = farming_vegetableconf
    if type(conf) ~= "table" or type(conf.props) ~= "table" then return nil end
    local list = {}
    for _, k in ipairs(Garden.SEED_VARIETIES) do
        local props = conf.props[k]
        if type(props) == "table" and Garden.inSeason(k, month) and seedTypesOf(props)[1] ~= nil then
            list[#list + 1] = { typeOfSeed = k, seed = seedTypesOf(props)[1] }
        end
    end
    if #list == 0 then return nil end
    local window = math.floor((math.max(1, day) - 1) / cfg().SEED_DAYS)
    return list[window % #list + 1]
end

-- Sachet dû au groupe gid (g : registre) le jour day au mois month : jardinier présent, aucun sachet depuis SEED_DAYS
-- jours, variété de saison, moins de SEED_LOW graines semables au foyer. Rend { typeOfSeed, seed, n }, ou nil et une
-- raison.
function Garden.seedOffer(gid, g, day, month)
    if not Garden.hasGardener(g) then return nil, "no gardener" end
    local last = Garden.state.seedDay[gid]
    if last ~= nil and day >= last and day - last < cfg().SEED_DAYS then return nil, "seeds received recently" end
    local v = Garden.seedVariety(day, month)
    if v == nil then return nil, "nothing to sow this month" end
    local have, why = Garden.seedCount(gid, month)
    if have == nil then return nil, why end
    if have >= cfg().SEED_LOW then return nil, "enough seeds" end
    return { typeOfSeed = v.typeOfSeed, seed = v.seed, n = cfg().SEED_PACKET }
end

-- Range le sachet offer (Garden.seedOffer) dans le dépôt depot du groupe gid le jour day : graines ajoutées au conteneur
-- (et aux clients sur un serveur, comme la récolte), objets classés ajoutés à la référence du stock (les graines,
-- DisplayCategory Gardening, ne le sont pas : la relecture Stock.check les ignore), jour retenu. Rend le nombre de
-- graines rangées.
function Garden.receiveSeeds(gid, depot, offer, day)
    local list = addProduce(depot, offer.seed, offer.n)
    local refs, types = {}, {}
    local count = list ~= nil and collect(list, depot, refs, types) or 0
    track(gid, refs)
    Garden.state.seedDay[gid] = day
    return count
end

return Garden
