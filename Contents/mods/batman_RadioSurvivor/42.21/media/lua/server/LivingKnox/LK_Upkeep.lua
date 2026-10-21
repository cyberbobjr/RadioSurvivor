-- Living Knox : entretien du foyer par ses membres (LK05-T10). Fiche : docs/annexes/conception/entretien.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Tâches (liste fermée JOBS, ordre = priorité), relevées dans la zone du foyer (LK_Homes : RADIUS cases autour de la
-- case du foyer, niveau du foyer, zone entièrement chargée : Homes.ready) au plus une fois toutes les SCAN_MINUTES
-- minutes de jeu par groupe :
--   refuel : générateur (IsoGenerator) DU GROUPE (LK05-T19 : marque ModData LK_Homes.GEN_TAG = identifiant du groupe,
--            posée à l'aménagement du foyer sur les générateurs déjà dans le bâtiment ; jamais un générateur sans
--            marque ou marqué par un autre groupe, donc jamais celui d'un joueur) de la zone, carburant < REFUEL_BELOW
--            litres (sur getMaxFuel = 10,
--            J/iso/objects/IsoGenerator.java:436-456), avec un récipient d'essence (fluide principal Fluid.Petrol) dans
--            les conteneurs du foyer. Effet comme ISAddFuel:complete (M/shared/TimedActions/ISAddFuel.lua:52-63) :
--            prise = min(litres du récipient, place libre), récipient vidé d'autant, setFuel (synchronisé par le Java
--            sur un serveur, :448-456). Un récipient par tâche.
--   repair : générateur du groupe arrêté (le vanilla refuse un générateur en marche : ISFixGenerator.lua:6-11) en état <
--            REPAIR_BELOW, avec une pièce REPAIR_PART (Base.ElectronicsScrap) au foyer : une pièce retirée, état +
--            REPAIR_STEP (ISFixGenerator:complete, :62-77 : +4 + Électricité/2, compétence 0 ici), setCondition
--            synchronisé (:503-511).
--   water  : (LK05-T11, fiche docs/annexes/conception/nourriture.md) plante cultivée de la zone (système vanilla SFarmingSystem,
--            serveur et solo seulement) vivante dont le niveau d'eau est sous le besoin de son stade, hors pluie
--            (I4.5), avec de l'eau dans un récipient du foyer (eau croupie d'abord, eau potable si le stock n'en
--            manque pas). Effet comme la commande vanilla « water » (plant:water(nil, doses), +10 par dose,
--            M/server/Farming/farmingCommands.lua:100-107) : doses = jusqu'au besoin + WATER_MARGIN, dose de
--            farmingFluidContainerMillilitresPerUse (200 ml) retirée du récipient (Stock.drawFluid) ; récipient vidé
--            ôté de la référence du stock (Stock.untrack). Le membre se tient sur la case libre la plus proche (jamais
--            à côté d'une plante : LK04-T06), tourné vers elle.
--   harvest: (LK05-T11, décision du 2026-10-15) plante cultivée de la zone mûre (SPlantGlobalObject:canHarvest :
--            vivante et hasVegetable), avec un conteneur au foyer. Effet comme SFarmingSystem:harvest
--            (M/server/Farming/SFarmingSystem.lua:333-382), qui exige un joueur : nombre de légumes par la fonction
--            vanilla getVegetablesNumber (M/server/Farming/farming_vegetableconf.lua:17-75 : santé, ravageurs, bonus ;
--            Agriculture HARVEST_LEVEL prêtée), props.vegetableName et props.produceExtra x ce nombre, graines
--            (hasSeed : max(floor(nombre x seedPerVeg), 1) de props.seedName) ajoutés au conteneur de dépôt du foyer
--            (conteneur posé par LK_Homes, sinon le premier ; AddItems puis sendAddItemsToContainer sur un serveur) ;
--            produits classés ajoutés à la référence du stock ; puis hasVegetable et hasSeed faux, repousse
--            (props.growBack : nbOfGrow, engrais à 0, growPlant, sprite, saveData) ou plante récoltée (harvestThis,
--            sauvegardée par deadPlant). Ni bonheur ni ennui (fleurs : statistiques du joueur seulement).
--   clean  : case du bâtiment du foyer tachée de sang (IsoGridSquare.haveBlood, J/iso/IsoGridSquare.java:4657-4675 :
--            faux si l'option bloodDecals vaut 0), avec un produit (Fluid.Bleach ou Fluid.CleaningLiquid, au moins
--            ZomboidGlobals.CleanBloodBleachAmount) et un outil (tag CleanStains, non cassé) au foyer. Effet comme
--            ISCleanBlood:complete : produit diminué de CleanBloodBleachAmount, removeBlood(false, false) (taches des
--            murs de la case et du sol à une case autour ; paquet RemoveBlood aux clients proches sur un serveur,
--            :4818-4840), removeGrime (sprites transmis). L'outil reste.
--   glass  : verre brisé (IsoBrokenGlass) sur une case du bâtiment du foyer : retiré comme le ramassage vanilla
--            (triggerEvent OnObjectAboutToBeRemoved puis transmitRemoveItemFromSquare,
--            M/shared/Moveables/ISMoveableSpriteProps.lua:1481-1491 ; retrait envoyé aux clients sur un serveur,
--            J/iso/IsoGridSquare.java:5076-5098). « Déchets » = verre brisé : seul débris vanilla avec un objet de case.
-- Exécution : un membre dont la cascade choisit « chore » (LK_Decisions, de jour, au foyer) prend la première tâche
--   ouverte qu'aucun autre membre ne tient (Routines.apply -> Upkeep.run) ; il va à une case libre voisine de l'objet
--   (Routines.exec.placeBeside, même règle que les corvées), se tourne vers lui, fait le geste GESTURE pendant
--   WORK_MINUTES minutes de jeu, puis l'effet est appliqué UNE fois : phase « done » posée avant l'effet, état et
--   matériaux relus au moment de l'effet (objet parti, déjà plein, plus de produit : rien n'est fait). Tâche finie ou
--   abandonnée : elle n'est plus proposée avant le relevé suivant (DONE_MINUTES). Interrompue (menace, autre consigne,
--   corps retiré) avant l'effet : rien n'est fait, la tâche est libérée (Routines.leave).
-- Lumières : à chaque minute de jeu, de LIGHT_FROM à LIGHT_TO (heure du jour), un membre incarné qui entre dans une
--   pièce du bâtiment de son foyer (pièce différente de la précédente, ou première vue dans le noir) allume ses
--   interrupteurs éteints que le courant permet d'allumer (IsoLightSwitch.canSwitchLight : ampoule et réseau ou
--   générateur, J/iso/objects/IsoLightSwitch.java:392-447 ; setActive(true) : toutes les lumières de la pièce, paquet
--   SyncIsoObject aux clients proches, sauvegardé, :449-476, 482-530, 582-630). Lampes sur pile écartées (aucun
--   courant consommé de la pièce). Aucune extinction (reste).
-- Morts portés à une tombe : non fait (cadavre unique LK07-T04 absent ; tombe vanilla = trou creusé à la pelle et
--   cadavre porté par un personnage joueur, ISBuryCorpse.lua) : voir la fiche.
-- Mémoire (tâches relevées, prises, faites, pièces vues) : non sauvegardée, recalculée.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"
require "LivingKnox/LK_Stock"
require "LivingKnox/LK_Routines"

local Upkeep = LivingKnox.Upkeep or {}
LivingKnox.Upkeep = Upkeep

Upkeep.JOBS = { "refuel", "repair", "harvest", "water", "clean", "glass" }
Upkeep.GESTURE = { refuel = "kneel", repair = "rummage", harvest = "kneel", water = "kneel", clean = "kneel",
    glass = "rummage" }
Upkeep.PETROL = { "Petrol" }
Upkeep.CLEANERS = { "Bleach", "CleaningLiquid" }
-- Arrosage (LK05-T11) : eau croupie d'abord (le vanilla l'accepte : ISFarmingMenu.getWaterUsesInteger), eau potable
-- seulement si le stock n'en manque pas.
Upkeep.WATER_FIRST = { "TaintedWater" }
Upkeep.WATER_DRINK = { "Water" }

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche).
Upkeep.CFG = Upkeep.CFG or {
    REFUEL_BELOW = 5,          -- litres de carburant (sur 10) sous lesquels le générateur est rempli
    REPAIR_BELOW = 60,         -- état (0..100) sous lequel un générateur arrêté est réparé
    REPAIR_STEP = 4,           -- état gagné par pièce (ISFixGenerator, compétence 0)
    REPAIR_PART = "Base.ElectronicsScrap",
    CLEAN_AMOUNT = 0.24999,    -- produit par case nettoyée si ZomboidGlobals.CleanBloodBleachAmount manque
    WORK_MINUTES = { refuel = 3, repair = 5, harvest = 3, water = 2, clean = 3, glass = 2 },
    WATER_PER_USE = 0.2,       -- litres par dose si ZomboidGlobals.farmingFluidContainerMillilitresPerUse manque
    WATER_STEP = 10,           -- niveau d'eau d'une plante par dose (SPlantGlobalObject:water)
    WATER_MARGIN = 10,         -- niveau visé = besoin de la plante + marge (borné par waterNeededMax et 100)
    SCAN_MINUTES = 10,         -- relevé des tâches d'un groupe au plus toutes les 10 minutes de jeu
    DONE_MINUTES = 10,         -- tâche faite ou abandonnée : plus proposée pendant 10 minutes de jeu
    MAX_JOBS = 8,              -- tâches retenues par relevé
    LIGHT_FROM = 19,           -- heure du jour à partir de laquelle une pièce est éclairée en y entrant
    LIGHT_TO = 7,              -- heure du jour à laquelle cela cesse
    HARVEST_LEVEL = 3,         -- niveau d'Agriculture prêté à getVegetablesNumber (LK05-T11)
}

Upkeep.state = Upkeep.state or { scans = {}, claims = {}, done = {}, rooms = {} }
Upkeep.stats = Upkeep.stats or { scans = 0, started = 0, applied = 0, skipped = 0, refuels = 0, repairs = 0,
    cleaned = 0, glass = 0, lights = 0 }
Upkeep.stats.watered = Upkeep.stats.watered or 0   -- LK05-T11 : plantes arrosées
Upkeep.stats.harvested = Upkeep.stats.harvested or 0   -- LK05-T11 : plantes récoltées
Upkeep.stats.produce = Upkeep.stats.produce or 0       -- objets récoltés (légumes, extras, graines)

local function log() return LivingKnox.Log end
local function cfg() return Upkeep.CFG end
local function Groups() return LivingKnox.Groups end
local function Homes() return LivingKnox.Homes end
local function Stock() return LivingKnox.Stock end
local function R() return LivingKnox.Routines end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function cleanAmount()
    local g = ZomboidGlobals
    if type(g) == "table" and type(g.CleanBloodBleachAmount) == "number" then return g.CleanBloodBleachAmount end
    return cfg().CLEAN_AMOUNT
end

-- ================================================================ matériaux (lecture)

local function isPart(it) return it:getFullType() == cfg().REPAIR_PART end

local function isCleanTool(it)
    if ItemTag == nil or ItemTag.CLEAN_STAINS == nil then return false end
    return it:hasTag(ItemTag.CLEAN_STAINS) and not it:isBroken()
end

-- ================================================================ arrosage (LK05-T11)

local function waterPerUse()
    local g = ZomboidGlobals
    if type(g) == "table" and type(g.farmingFluidContainerMillilitresPerUse) == "number" then
        return g.farmingFluidContainerMillilitresPerUse / 1000
    end
    return cfg().WATER_PER_USE
end

-- Système de cultures vanilla (serveur et solo seulement : M/server/Farming/SFarmingSystem.lua), ou nil.
local function farming()
    local s = SFarmingSystem
    return type(s) == "table" and s.instance or nil
end

-- Vrai s'il pleut (I4.5 : pas d'arrosage sous la pluie).
function Upkeep.raining()
    local cm = getClimateManager and getClimateManager() or nil
    return cm ~= nil and (cm:getPrecipitationIntensity() or 0) > 0
end

-- Doses d'eau à verser sur la plante plant (SPlantGlobalObject, table Lua du système de cultures), 0 si elle n'a pas
-- soif : vivante, semée, niveau d'eau sous son besoin du stade (waterNeeded, farming_vegetableconf.calcWater : la
-- croissance ralentit en dessous) ; niveau visé = besoin + WATER_MARGIN, borné par waterNeededMax et 100.
function Upkeep.waterUses(plant)
    if type(plant) ~= "table" or type(plant.isAlive) ~= "function" or not plant:isAlive() then return 0 end
    if plant.state == "plow" or type(plant.waterLvl) ~= "number" or type(plant.waterNeeded) ~= "number" then return 0 end
    if plant.waterNeeded <= 0 or plant.waterLvl >= plant.waterNeeded then return 0 end
    local target = math.min(100, plant.waterNeeded + cfg().WATER_MARGIN)
    if type(plant.waterNeededMax) == "number" and plant.waterNeededMax > plant.waterNeeded then
        target = math.min(target, plant.waterNeededMax)
    end
    return math.max(1, math.ceil((target - plant.waterLvl) / cfg().WATER_STEP))
end

-- Eau permise pour arroser : eau croupie, plus l'eau potable si le stock du groupe n'en manque pas.
local function waterSources(gid)
    local list = { Upkeep.WATER_FIRST }
    local a = Stock().needs(gid)
    local short = false
    for _, nd in ipairs(a ~= nil and a.needs or {}) do
        if nd.c == "water" then short = true end
    end
    if not short then list[#list + 1] = Upkeep.WATER_DRINK end
    return list
end

local function findWater(gid, least)
    for _, fluids in ipairs(waterSources(gid)) do
        local f = Stock().findFluid(gid, fluids, least)
        if f ~= nil then return f, fluids end
    end
    return nil
end

local function plantAt(x, y, z)
    local sys = farming()
    if sys == nil then return nil end
    return sys:getLuaObjectAt(x, y, z)
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
function Upkeep.ripe(plant)
    if type(plant) ~= "table" or type(plant.isAlive) ~= "function" or not plant:isAlive() then return false end
    return plant.hasVegetable == true and vegConf(plant) ~= nil
end

-- Conteneur de dépôt du foyer (comme le dépôt d'une expédition : conteneur posé par LK_Homes, sinon le premier dans
-- l'ordre des clés) : { key, container, ... }, ou nil et une raison.
local function depotOf(gid, home)
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
function Upkeep.harvestPlant(plant, gid, depot)
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
        farming():growPlant(plant, nil, true)
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

-- ================================================================ relevé des tâches

-- Générateur du groupe gid sur la case sq (LK05-T19 : marque LK_Homes.GEN_TAG), ou nil.
local function generatorOn(sq, gid)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if Homes().groupGenerator(o, gid) then return o end
    end
    return nil
end

-- Tâches ouvertes du foyer du groupe g (registre ou copie) : liste { kind, key, x, y, z, bid } dans l'ordre de JOBS
-- puis des cases (y, x), MAX_JOBS au plus, la première de chaque sorte gardée (Upkeep.capJobs) ; ou nil et une
-- raison (zone non chargée, pas de foyer).
function Upkeep.jobs(gid, g)
    if type(g) ~= "table" or type(g.home) ~= "table" then return nil, "no home" end
    local home = g.home
    local style, def = Homes().ready(home)
    if style == nil then return nil, def end
    local bid = def ~= nil and def:getIDString() or nil
    local cell = getCell()
    local Rd = Homes().CFG.RADIUS
    local gens, blood, glass, plants, ripe = {}, {}, {}, {}, {}
    local dry = farming() ~= nil and not Upkeep.raining()   -- LK05-T11 : arrosage, jamais sous la pluie
    for dy = -Rd, Rd do
        for dx = -Rd, Rd do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, home.z)
            if sq ~= nil then
                -- Générateur : une case de marge pour que la place à côté reste dans la zone du foyer.
                if math.max(math.abs(dx), math.abs(dy)) < Rd then
                    local gen = generatorOn(sq, gid)
                    if gen ~= nil then gens[#gens + 1] = { x = x, y = y, gen = gen } end
                end
                if farming() ~= nil and sq:hasFarmingPlant() then
                    local plant = plantAt(x, y, home.z)
                    if Upkeep.ripe(plant) then
                        ripe[#ripe + 1] = { x = x, y = y }   -- LK05-T11 : récolte, même sous la pluie
                    elseif dry and Upkeep.waterUses(plant) > 0 then
                        plants[#plants + 1] = { x = x, y = y }
                    end
                end
                if style == "building" and Homes().buildingId(sq) == bid then
                    if sq:haveBlood() then blood[#blood + 1] = { x = x, y = y } end
                    if sq:getBrokenGlass() ~= nil then glass[#glass + 1] = { x = x, y = y } end
                end
            end
        end
    end
    local S = Stock()
    local out = {}
    local function add(kind, x, y, b)
        out[#out + 1] = { kind = kind, key = string.format("%s %d,%d,%d", kind, x, y, home.z), x = x, y = y, z = home.z,
            bid = b }
    end
    if #gens > 0 then
        local petrol = S.findFluid(gid, Upkeep.PETROL, 0)
        local part = S.findItem(gid, isPart)
        for _, e in ipairs(gens) do
            if petrol ~= nil and e.gen:getFuel() < cfg().REFUEL_BELOW then add("refuel", e.x, e.y, nil) end
        end
        for _, e in ipairs(gens) do
            if part ~= nil and not e.gen:isActivated() and e.gen:getCondition() < cfg().REPAIR_BELOW then
                add("repair", e.x, e.y, nil)
            end
        end
    end
    if #ripe > 0 and type(getVegetablesNumber) == "function" and depotOf(gid, home) ~= nil then
        for _, e in ipairs(ripe) do add("harvest", e.x, e.y, nil) end
    end
    if #plants > 0 and findWater(gid, waterPerUse()) ~= nil then
        for _, e in ipairs(plants) do add("water", e.x, e.y, nil) end
    end
    if #blood > 0 and S.findFluid(gid, Upkeep.CLEANERS, cleanAmount()) ~= nil and S.findItem(gid, isCleanTool) ~= nil then
        for _, e in ipairs(blood) do add("clean", e.x, e.y, bid) end
    end
    for _, e in ipairs(glass) do add("glass", e.x, e.y, bid) end
    return Upkeep.capJobs(out, cfg().MAX_JOBS)
end

-- Au plus max tâches, dans l'ordre donné, la première de chaque sorte toujours gardée : une maison tachée de sang
-- partout (combats précédents) remplissait les MAX_JOBS places de « clean » et le verre n'était jamais proposé
-- (campagne MP du 2026-10-14, lk.upkeep : trois taches lavées en 5 min, verre jamais ramassé).
function Upkeep.capJobs(list, max)
    if #list <= max then return list end
    local keep, kinds, n = {}, {}, 0
    for i, j in ipairs(list) do
        if not kinds[j.kind] then
            kinds[j.kind] = true
            keep[i] = true
            n = n + 1
        end
    end
    for i = 1, #list do
        if n >= max then break end
        if not keep[i] then
            keep[i] = true
            n = n + 1
        end
    end
    local out = {}
    for i, j in ipairs(list) do
        if keep[i] then out[#out + 1] = j end
    end
    return out
end

local function claimKey(gid, key) return tostring(gid) .. "|" .. key end

-- Tâches du groupe (relevé gardé SCAN_MINUTES minutes de jeu), ou liste vide.
local function cached(gid, g, minute)
    local st = Upkeep.state
    local s = st.scans[gid]
    if s ~= nil and minute >= s.minute and minute - s.minute < cfg().SCAN_MINUTES then return s.jobs end
    local jobs, why = Upkeep.jobs(gid, g)
    st.scans[gid] = { minute = minute, jobs = jobs or {} }
    Upkeep.stats.scans = Upkeep.stats.scans + 1
    if jobs == nil then
        log().debug("group %s: upkeep survey postponed: %s", tostring(gid), tostring(why))
    elseif #jobs > 0 then
        log().debug("group %s: %d upkeep job(s) open", tostring(gid), #jobs)
    end
    return jobs or {}
end

-- Première tâche ouverte du groupe que personne d'autre ne tient (et pas faite récemment), prise par id. Rend la tâche
-- (copie), ou nil.
function Upkeep.claim(gid, g, id, minute)
    local st = Upkeep.state
    for _, job in ipairs(cached(gid, g, minute)) do
        local k = claimKey(gid, job.key)
        local holder = st.claims[k]
        local doneUntil = st.done[k]
        if (holder == nil or holder == id) and (doneUntil == nil or minute >= doneUntil) then
            st.claims[k] = id
            return { kind = job.kind, key = job.key, x = job.x, y = job.y, z = job.z, bid = job.bid }
        end
    end
    return nil
end

-- Tâche du membre libérée (fin, abandon, interruption).
function Upkeep.release(id, m)
    if type(m) ~= "table" or type(m.job) ~= "table" then return end
    local k = claimKey(m.gid, m.job.key)
    if Upkeep.state.claims[k] == id then Upkeep.state.claims[k] = nil end
end

-- ================================================================ effets (autorité, une fois)

local function squareOf(job)
    local cell = getCell()
    return cell ~= nil and cell:getGridSquare(job.x, job.y, job.z) or nil
end

-- Applique la tâche job pour le groupe gid (who : texte du journal). État et matériaux relus maintenant. Rend un texte
-- (fait), ou nil et une raison (rien fait).
function Upkeep.apply(job, gid, who)
    local sq = squareOf(job)
    if sq == nil then return nil, "square not loaded" end
    local S = Stock()
    if job.kind == "refuel" or job.kind == "repair" then
        local gen = generatorOn(sq, gid)
        if gen == nil then return nil, "generator of the group gone" end
        if job.kind == "refuel" then
            local before = gen:getFuel()
            local room = gen:getMaxFuel() - before
            if room <= 0 then return nil, "generator full" end
            local got, why = S.drawFluid(gid, Upkeep.PETROL, room, 0, who, "generator " .. job.key)
            if got == nil then return nil, "no petrol: " .. tostring(why) end
            gen:setFuel(before + got.amount)
            Upkeep.stats.refuels = Upkeep.stats.refuels + 1
            return string.format("generator at %d,%d refuelled %.2f -> %.2f l (%s)", job.x, job.y, before,
                gen:getFuel(), got.t)
        end
        if gen:isActivated() then return nil, "generator running" end
        local cond = gen:getCondition()
        if cond >= 100 then return nil, "generator in good condition" end
        local got, why = S.takeItem(gid, isPart, who, "generator " .. job.key)
        if got == nil then return nil, "no part: " .. tostring(why) end
        gen:setCondition(cond + cfg().REPAIR_STEP)
        Upkeep.stats.repairs = Upkeep.stats.repairs + 1
        return string.format("generator at %d,%d repaired %d -> %d (%s)", job.x, job.y, cond, gen:getCondition(), got.t)
    end
    if job.kind == "water" then
        -- Comme la commande vanilla « water » (M/server/Farming/farmingCommands.lua:100-107 : plant:water(nil, doses),
        -- +10 par dose, heure d'arrosage notée, sauvegardé) et ISWaterPlantAction:useItemOneUnit (dose =
        -- farmingFluidContainerMillilitresPerUse, M/shared/defines.lua:52, retirée du récipient).
        if Upkeep.raining() then return nil, "raining" end
        local plant = plantAt(job.x, job.y, job.z)
        local uses = Upkeep.waterUses(plant)
        if uses <= 0 then return nil, "plant gone or not thirsty" end
        local per = waterPerUse()
        local src, fluids = findWater(gid, per)
        if src == nil then return nil, "no water" end
        uses = math.min(uses, math.floor(src.amount / per + 1e-6))
        if uses <= 0 then return nil, "not enough water" end
        local got, why = S.drawFluid(gid, fluids, uses * per, per, who, "plant " .. job.key)
        if got == nil then return nil, "no water: " .. tostring(why) end
        uses = math.floor(got.amount / per + 1e-6)
        local before = plant.waterLvl
        if uses > 0 then plant:water(nil, uses) end
        if got.left < 1e-6 then S.untrack(gid, got.i) end   -- récipient vidé : plus de l'eau
        Upkeep.stats.watered = (Upkeep.stats.watered or 0) + 1
        return string.format("plant at %d,%d watered %d -> %d (%d dose(s), %.2f l of %s from %s)", job.x, job.y,
            before, plant.waterLvl, uses, got.amount, got.fluid, got.t)
    end
    if job.kind == "harvest" then
        local plant = plantAt(job.x, job.y, job.z)
        if not Upkeep.ripe(plant) then return nil, "plant gone or not ripe" end
        local g = Groups().get(gid)
        if g == nil or type(g.home) ~= "table" then return nil, "no home" end
        local depot, why = depotOf(gid, g.home)
        if depot == nil then return nil, "no container: " .. tostring(why) end
        local n, count, types = Upkeep.harvestPlant(plant, gid, depot)
        Upkeep.stats.harvested = (Upkeep.stats.harvested or 0) + 1
        Upkeep.stats.produce = (Upkeep.stats.produce or 0) + count
        return string.format("plant at %d,%d harvested: %d vegetable(s), %d item(s) into %s%s", job.x, job.y, n, count,
            depot.key, #types > 0 and (" (" .. table.concat(types, " ") .. ")") or "")
    end
    if job.kind == "clean" then
        if not sq:haveBlood() then return nil, "no blood left" end
        if S.findItem(gid, isCleanTool) == nil then return nil, "no cleaning tool" end
        local amount = cleanAmount()
        local got, why = S.drawFluid(gid, Upkeep.CLEANERS, amount, amount, who, "blood " .. job.key)
        if got == nil then return nil, "no cleaning product: " .. tostring(why) end
        sq:removeBlood(false, false)
        sq:removeGrime()
        Upkeep.stats.cleaned = Upkeep.stats.cleaned + 1
        return string.format("blood cleaned at %d,%d (%.3f l of %s)", job.x, job.y, got.amount, got.fluid)
    end
    if job.kind == "glass" then
        local glass = sq:getBrokenGlass()
        if glass == nil then return nil, "no broken glass left" end
        triggerEvent("OnObjectAboutToBeRemoved", glass)
        sq:transmitRemoveItemFromSquare(glass)
        Upkeep.stats.glass = Upkeep.stats.glass + 1
        return string.format("broken glass removed at %d,%d", job.x, job.y)
    end
    return nil, "unknown job " .. tostring(job.kind)
end

-- ================================================================ exécution (membre en corvée)

local function finish(id, m, minute, text, why)
    m.phase = "done"
    local st = Upkeep.state
    st.done[claimKey(m.gid, m.job.key)] = minute + cfg().DONE_MINUTES
    Upkeep.release(id, m)
    if text ~= nil then
        Upkeep.stats.applied = Upkeep.stats.applied + 1
        log().info("npc %s (%s %s): upkeep %s", tostring(id), tostring(m.gid), tostring(m.mid), text)
        if m.job.kind == "refuel" or m.job.kind == "repair" or m.job.kind == "harvest" then
            local G = Groups()
            G.update(function(data)
                local g = data.groups[m.gid]
                if g == nil then return false, false end
                G.appendLog(g, "upkeep", string.sub(text, 1, G.TEXT_MAX), G.today())
                return true, true
            end)
        end
    else
        Upkeep.stats.skipped = Upkeep.stats.skipped + 1
        log().debug("npc %s: upkeep %s not done: %s", tostring(id), m.job.key, tostring(why))
    end
end

-- Place du membre pour la tâche : case libre voisine de l'objet (règle des corvées), sinon la case de l'objet si elle
-- est praticable (tache de sang, verre), sans regard.
local function placeFor(job)
    local cell = getCell()
    if cell == nil then return nil end
    local X = R().exec
    if job.kind == "water" or job.kind == "harvest" then
        -- Plante : jamais à côté (un corps de zombie détruit la plante de sa case, LK04-T06) ; case libre la plus proche
        -- (LK_Bodies.findFreeSquare : ni plante ni feu sur elle ni autour), tournée vers la plante.
        local B = LivingKnox.Bodies
        local sq = B ~= nil and B.findFreeSquare(job.x, job.y, job.z) or nil
        if sq == nil then return nil end
        local px, py = sq:getX(), sq:getY()
        local D = LivingKnox.Decisions
        local a = D ~= nil and D.angleTo ~= nil and D.angleTo(job.x - px, job.y - py) or nil
        return { x = px, y = py, z = job.z, a = a, ox = job.x, oy = job.y }
    end
    local p = X.placeBeside(cell, job.x, job.y, job.z, job.bid, {})
    if p ~= nil then return p end
    if job.kind == "clean" or job.kind == "glass" then
        local sq = cell:getGridSquare(job.x, job.y, job.z)
        if X.standable(sq) then return { x = job.x, y = job.y, z = job.z } end
    end
    return nil
end

local function step(id, ctx, m)
    local X = R().exec
    local e = X.entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) and (m.phase == "go" or m.phase == "face") then
        -- Une autre consigne est passée (suite de test, autre module) : retour à la place.
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
        m.phase = "go"
    end
    if m.phase == "place" then
        local p = placeFor(m.job)
        if p == nil then return finish(id, m, ctx.minute, nil, "no free square beside " .. m.job.key) end
        m.place, m.phase = p, "go"
    end
    if m.phase == "go" then
        local res = X.goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
        if res == "moving" then return end
        if res == "failed" then return finish(id, m, ctx.minute, nil, "cannot reach " .. m.job.key) end
        m.phase = "face"
    end
    if m.phase == "face" then
        if m.place.a ~= nil then
            if m.faceV == nil then
                X.faceTo(id, m, m.place.a)
                return
            end
            e = X.entryOf(id)
            if e == nil or e.v ~= m.faceV or not e.done then return end
        end
        X.sitDown(id, m, Upkeep.GESTURE[m.job.kind])
        m.since, m.phase = ctx.minute, "work"
        return
    end
    if m.phase == "work" then
        local A = LivingKnox.Anim
        local gesture = Upkeep.GESTURE[m.job.kind]
        if A ~= nil and A.gestureOf(id) ~= gesture then X.sitDown(id, m, gesture) end
        if ctx.minute - m.since < (cfg().WORK_MINUTES[m.job.kind] or 3) then return end
        m.phase = "done"   -- avant l'effet : jamais deux fois, même si le Java lève une erreur
        local ok, text, why = pcall(Upkeep.apply, m.job, m.gid, m.mid)
        if not ok then
            log().error("npc %s: upkeep %s failed: %s", tostring(id), m.job.key, tostring(text))
            text, why = nil, "error"
        end
        finish(id, m, ctx.minute, text, why)
    end
end

-- Membre en corvée (comportement « chore ») : poursuit sa tâche d'entretien ou en prend une. Rend vrai si le membre
-- est occupé par l'entretien (la corvée visible attend), faux sinon.
function Upkeep.run(id, st, ctx, g)
    if ctx.gid == nil or type(g) ~= "table" or type(g.home) ~= "table" then return false end
    local mem = R().state.npcs
    local m = mem[id]
    if m ~= nil and m.kind == "upkeep" then
        if m.phase == "done" then return false end
        step(id, ctx, m)
        return true
    end
    local job = Upkeep.claim(ctx.gid, g, id, ctx.minute)
    if job == nil then return false end
    if m ~= nil then R().leave(id) end   -- corvée visible en cours : debout d'abord
    m = { key = "upkeep " .. job.key, kind = "upkeep", job = job, gid = ctx.gid, mid = ctx.mid, phase = "place",
        fails = 0 }
    mem[id] = m
    Upkeep.stats.started = Upkeep.stats.started + 1
    log().debug("npc %s: upkeep %s (%s)", tostring(id), job.key, tostring(st.why or st.b))
    step(id, ctx, m)
    return true
end

-- ================================================================ lumières

local function hourOfDay()
    local gt = getGameTime()
    local h = gt ~= nil and gt:getWorldAgeHours() or 0
    return (math.floor(h) + 7) % 24
end

-- Vrai si l'heure du jour hod est dans la plage éclairée (LIGHT_FROM .. LIGHT_TO, à cheval sur minuit).
function Upkeep.dark(hod)
    local from, to = cfg().LIGHT_FROM, cfg().LIGHT_TO
    if from > to then return hod >= from or hod < to end
    return hod >= from and hod < to
end

-- Allume les interrupteurs éteints de la pièce room que le courant permet d'allumer (lampes sur pile écartées). Rend
-- le nombre d'interrupteurs allumés.
function Upkeep.lightRoom(room)
    local list = room ~= nil and room:getLightSwitches() or nil
    if list == nil then return 0 end
    local n = 0
    for i = 0, list:size() - 1 do
        local ls = list:get(i)
        if ls ~= nil and not ls:isActivated() and not (ls:getCanBeModified() and ls:getUseBattery())
            and ls:canSwitchLight() then
            if ls:setActive(true) then n = n + 1 end
        end
    end
    return n
end

local function lightGroup(gid, g, cell)
    local home = g.home
    local style, def = Homes().ready(home)
    if style ~= "building" or def == nil then return 0 end
    local bid = def:getIDString()
    local rooms = Upkeep.state.rooms
    local B = LivingKnox.Bodies
    local n = 0
    local mids = {}
    for mid in pairs(g.members) do mids[#mids + 1] = mid end
    table.sort(mids)
    for _, mid in ipairs(mids) do
        local m = g.members[mid]
        local z = m.alive and m.npc ~= nil and B ~= nil and B.find(m.npc) or nil
        local room
        if z ~= nil and math.floor(z:getZ()) == home.z
            and cheb(z:getX(), z:getY(), home.x + 0.5, home.y + 0.5) <= Homes().CFG.RADIUS then
            local sq = cell:getGridSquare(math.floor(z:getX()), math.floor(z:getY()), home.z)
            if sq ~= nil and Homes().buildingId(sq) == bid then room = sq:getRoom() end
        end
        if m.npc ~= nil then
            if room ~= nil and rooms[m.npc] ~= room then
                local lit = Upkeep.lightRoom(room)
                if lit > 0 then
                    n = n + lit
                    log().info("npc %s (%s %s): %d light switch(es) turned on entering a room of the home", m.npc,
                        tostring(gid), mid, lit)
                end
            end
            rooms[m.npc] = room
        end
    end
    return n
end

-- Passage des lumières (chaque minute de jeu). Rend le nombre d'interrupteurs allumés.
function Upkeep.lights()
    local Config = LivingKnox.Config
    if Config and Config.isEnabled and not Config.isEnabled() then return 0 end
    if not Upkeep.dark(hourOfDay()) then
        Upkeep.state.rooms = {}   -- au jour : la prochaine soirée compte comme une entrée
        return 0
    end
    local cell = getCell()
    if cell == nil then return 0 end
    local G = Groups()
    local n = 0
    for _, gid in ipairs(G.list()) do
        local g = G.get(gid)
        if g ~= nil and type(g.home) == "table" and cell:getGridSquare(g.home.x, g.home.y, g.home.z) ~= nil then
            local ok, lit = pcall(lightGroup, gid, g, cell)
            if not ok then
                log().error("group %s: lights failed: %s", tostring(gid), tostring(lit))
            else
                n = n + lit
            end
        end
    end
    Upkeep.stats.lights = Upkeep.stats.lights + n
    return n
end

function Upkeep.reset()
    Upkeep.state = { scans = {}, claims = {}, done = {}, rooms = {} }
end

LivingKnox.subscribe("EveryOneMinute", "Upkeep.onEveryOneMinute", function() Upkeep.lights() end)

return Upkeep
