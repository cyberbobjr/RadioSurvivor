-- Living Knox : production de nourriture par la cueillette et la pêche, tirées des tables vanilla (LK05-T11).
-- Fiche : docs/annexes/conception/nourriture.md. Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Ce module ne mène aucun corps : une cueillette est une expédition de LK_Expeditions de genre « forage » (même
-- départ, même équipe, même trajet, même dépôt, même bascule hors écran). Il fournit :
--   - le lieu (Food.pickTarget) : zone de cueillette vanilla (types de forageSystem.zoneDefs, M/shared/Foraging/
--     forageZones.lua) de la liste FORAGE_ZONES (forêts de la biomemap et zones agricoles, jamais TownZone, Nav,
--     ForagingNav ni TrailerPark) la plus proche du foyer, lue dans la métagrille sans rien charger
--     (IsoMetaGrid.getZonesIntersecting : cellules couvertes seulement, base world-placement.md), à MAX_DIST cases
--     au plus ; point visé = case chargée, libre et hors bâtiment de la zone, la plus proche du foyer ;
--   - le tirage (Food.draw) : même calcul que forageSystem.pickRandomItemType (M/shared/Foraging/forageSystem.lua
--     :1127-1199) sur forageSystem.lootTable : catégorie puis objet, poids = chance de la zone x mois
--     (getMonthMulti) x météo (getWeatherMulti : pluie, flaques, neige) x jour ou nuit (getTimeOfDayBonus) ; nombre
--     comme forageServer rollCount (M/server/Foraging/forageServer.lua:74-82). Différences voulues : clés triées et
--     flux de tirages reproductible (LivingKnox.Simulation.stream, sel SALT) au lieu de pairs et ZombRandFloat. Un
--     tirage qui tombe sur un objet hors nourriture (DisplayCategory du script différente de « Food ») ne rapporte
--     rien : le PNJ laisse ce qu'il ne mange pas. Aucun objet hors des tables vanilla ;
--   - la création au dépôt (Food.make) : instanceItem du type tiré puis fonctions d'apparition vanilla de sa
--     définition (spawnFuncs : taille et âge de la nourriture sauvage, graines, poison), comme
--     forageServer.buildItems (:452-462), avec un cueilleur de niveau FORAGE_LEVEL ; un objet empoisonné est jeté.
--   - la pêche (LK05-T11, décision du 2026-10-15 ; expédition de genre « fish » à l'aube et au crépuscule,
--     Food.fishHour) : lieu (Food.fishTarget : rive libre près de l'eau la plus proche du foyer, zones Water de la
--     métagrille ou cases d'eau chargées) et tirages (Food.fishRound) dans les tables du filet vanilla
--     (Fishing.fishNet, Fishing.fishNetWithBait), flux reproductible propre (sel FISH_SALT) ; prise créée au dépôt par
--     instanceItem du type tiré (Food.make, sans fonction d'apparition). Jamais Fish:getFishByLure (joueur requis,
--     vitesse du jeu remise à 1).
-- Reproductible : tirage k de la cueillette n du groupe = flux (graine de la partie, numéro du groupe, n, k) ; mêmes
-- conditions (zone, mois, jour, météo arrondie au dixième) -> mêmes objets, que la cueillette se fasse à l'écran
-- (tour par tour, LK_Expeditions) ou hors écran (tours restants au retour abstrait, LK_Simulation).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Simulation"

local Food = LivingKnox.Food or {}
LivingKnox.Food = Food

Food.KIND = "forage"          -- genre d'expédition (LK_Expeditions, champ kind)
Food.TARGET = "forage"        -- champ b du lieu visé d'une cueillette (pas un bâtiment)
Food.SALT = 15485863          -- sel du flux des tirages (distinct des flux de LK_Simulation)
-- Zones de cueillette retenues : forêts de la biomemap (M/server/metazones/BiomeMapConfig.lua) et zones agricoles,
-- seulement si forageSystem.zoneDefs les définit.
Food.FORAGE_ZONES = {
    DeepForest = true, PHForest = true, PRForest = true, FarmForest = true, FarmMixForest = true, BirchForest = true,
    BirchMixForest = true, OrganicForest = true, Forest = true, Vegitation = true, FarmLand = true, Farm = true,
}

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche ; à recalibrer en jeu).
Food.CFG = Food.CFG or {
    MAX_DIST = 40,          -- cases entre le foyer et la zone (écart au rectangle ; consigne move : 60 au plus)
    MAX_ZONES = 64,         -- zones examinées au plus par départ
    MAX_CANDIDATES = 6,     -- zones essayées (case chargée et libre) par départ
    SPOT_RADIUS = 6,        -- cases autour du point le plus proche du foyer : case libre cherchée
    ROUNDS = 3,             -- tirages par membre de l'équipe et par cueillette
    ROUND_MINUTES = 15,     -- minutes de jeu de cueillette par tirage
    FORAGE_LEVEL = 3,       -- niveau de Cueillette prêté aux fonctions d'apparition vanilla
    MIN_YIELD = 0.25,       -- part des tirages qui rapportent de la nourriture sous laquelle on ne cueille pas
    -- Pêche (LK05-T11, décision du 2026-10-15) :
    FISH_SPAN = 2,          -- heures de chaque fenêtre de départ (FISH_HOURS)
    FISH_ROUNDS = 4,        -- tirages par membre de l'équipe et par sortie de pêche
    FISH_MINUTES = 10,      -- minutes de jeu de pêche par tirage (4 tirages tiennent dans SEARCH_MINUTES)
    FISH_CHANCE = 0.5,      -- chance qu'un tirage (FISH_MINUTES minutes de pêche) prenne quelque chose
    FISH_BAIT = 0.5,        -- part des prises tirées de la table du filet appâté (Fishing.fishNetWithBait)
    SHORE_RADIUS = 10,      -- cases autour du point d'eau le plus proche du foyer : rive libre cherchée
    WATER_STEP = 2,         -- pas du relevé des cases d'eau chargées (repli sans zone Water connue)
}

Food.stats = Food.stats or { draws = 0, found = 0, ignored = 0, made = 0, poisoned = 0, failed = 0 }
Food.stats.fishDraws = Food.stats.fishDraws or 0   -- LK05-T11 : tirages de pêche
Food.stats.caught = Food.stats.caught or 0          -- prises gardées (nourriture)

-- Pêche (LK05-T11) : genre d'expédition, lieu, fenêtres de départ (heure du jour où commence chaque fenêtre de
-- FISH_SPAN heures : aube, crépuscule), sel du flux des tirages.
Food.FISH_KIND = "fish"
Food.FISH_TARGET = "fish"
Food.FISH_ROOM = "Water"
Food.FISH_HOURS = { 5, 18 }
Food.FISH_SALT = 32452843

local function log() return LivingKnox.Log end
local function cfg() return Food.CFG end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do
        if type(k) == "string" then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

local function tenth(v)
    if type(v) ~= "number" or v ~= v then return 0 end
    return math.floor(v * 10 + 0.5) / 10
end

-- Système de cueillette vanilla prêt (tables générées par forageSystem.init, OnLoadedMapZones), ou nil.
function Food.vanilla()
    local fs = forageSystem
    if type(fs) ~= "table" or type(fs.lootTable) ~= "table" or type(fs.zoneDefs) ~= "table" then return nil end
    return fs
end

-- Conditions du moment : { month (1..12), day (vrai de l'aube au crépuscule, forageSystem.getTimeOfDay), rain,
-- puddle, snow (0..1, au dixième) }.
function Food.conditions()
    local fs = Food.vanilla()
    local gt = getGameTime()
    local cm = getClimateManager and getClimateManager() or nil
    local pm = getPuddlesManager and getPuddlesManager() or nil
    local c = { month = gt ~= nil and gt:getMonth() + 1 or 1, day = true, rain = 0, puddle = 0, snow = 0 }
    if fs ~= nil and fs.getTimeOfDay ~= nil then c.day = fs.getTimeOfDay() == "isDay" end
    if cm ~= nil then
        c.rain = tenth(cm:getPrecipitationIntensity())
        c.snow = tenth(cm:getSnowStrength())
    end
    if pm ~= nil then c.puddle = tenth(pm:getPuddlesSize()) end
    return c
end

-- Texte court des conditions (journal).
function Food.conditionText(c)
    return string.format("month %d %s rain %.1f puddles %.1f snow %.1f", c.month, c.day and "day" or "night", c.rain,
        c.puddle, c.snow)
end

-- Poids d'une définition (catégorie ou objet) dans la zone, comme forageSystem.processEntries.
local function weight(fs, def, zone, c)
    if type(def) ~= "table" or type(def.zones) ~= "table" then return 0 end
    local z = def.zones[zone]
    if type(z) ~= "number" or z <= 0 then return 0 end
    local w = z * fs.getMonthMulti(def, c.month) * fs.getWeatherMulti(def, c.rain, c.puddle, c.snow)
        * fs.getTimeOfDayBonus(def, c.day)
    if type(w) ~= "number" or w ~= w or w <= 0 then return 0 end
    return w
end

local function pickWeighted(entries, total, rnd)
    local roll = rnd() * total
    for _, e in ipairs(entries) do
        if roll <= e.cum then return e end
    end
    return entries[#entries]
end

local foodCache = {}

-- Vrai si le type d'objet est de la nourriture (DisplayCategory « Food » du script, comme LK_Stock).
function Food.isFood(itemType)
    local v = foodCache[itemType]
    if v ~= nil then return v end
    local sm = ScriptManager ~= nil and ScriptManager.instance or nil
    local script = sm ~= nil and sm:getItem(itemType) or nil
    v = script ~= nil and script:getDisplayCategory() == "Food" or false
    foodCache[itemType] = v
    return v
end

-- Un tirage de cueillette dans la zone zone (type de zone vanilla) aux conditions c, avec le flux rnd. Rend le type
-- d'objet, la catégorie de cueillette et le nombre d'objets, ou nil (rien trouvé).
function Food.draw(zone, c, rnd)
    local fs = Food.vanilla()
    local lt = fs ~= nil and fs.lootTable[zone] or nil
    if type(lt) ~= "table" or type(lt.categories) ~= "table" then return nil end
    local cats, total = {}, 0
    for _, name in ipairs(sortedKeys(lt.categories)) do
        local w = weight(fs, lt.categories[name].definition, zone, c)
        if w > 0 then
            total = total + w
            cats[#cats + 1] = { name = name, cum = total }
        end
    end
    if total <= 0 then return nil end
    local cat = pickWeighted(cats, total, rnd).name
    local items, itotal = {}, 0
    local list = lt.categories[cat].items or {}
    for _, t in ipairs(sortedKeys(list)) do
        local w = weight(fs, list[t].definition, zone, c)
        if w > 0 then
            itotal = itotal + w
            items[#items + 1] = { name = t, cum = itotal }
        end
    end
    if itotal <= 0 then return nil end
    local t = pickWeighted(items, itotal, rnd).name
    local def = fs.itemDefs ~= nil and fs.itemDefs[t] or list[t].definition
    local lo, hi = 1, 1
    if type(def) == "table" then lo, hi = def.minCount or 1, def.maxCount or def.minCount or 1 end
    local n = lo
    if hi > lo then n = lo + 1 + math.floor(rnd() * (hi - lo)) end   -- ZombRand(min, max) + 1
    return t, cat, math.max(1, math.min(n, hi))
end

-- Part des tirages qui rapportent de la nourriture dans la zone aux conditions c (0..1), ou 0 sans tables.
function Food.yield(zone, c)
    local fs = Food.vanilla()
    local lt = fs ~= nil and fs.lootTable[zone] or nil
    if type(lt) ~= "table" or type(lt.categories) ~= "table" then return 0 end
    local total, food = 0, 0
    for _, name in ipairs(sortedKeys(lt.categories)) do
        local entry = lt.categories[name]
        local w = weight(fs, entry.definition, zone, c)
        if w > 0 then
            total = total + w
            local it, fw = 0, 0
            for _, t in ipairs(sortedKeys(entry.items)) do
                local iw = weight(fs, entry.items[t].definition, zone, c)
                it = it + iw
                if iw > 0 and Food.isFood(t) then fw = fw + iw end
            end
            if it > 0 then food = food + w * fw / it end
        end
    end
    if total <= 0 then return 0 end
    return food / total
end

-- Flux du tirage k de la cueillette n du groupe gid.
function Food.stream(gid, n, k)
    local Si = LivingKnox.Simulation
    return Si.stream(Si.baseSeed(), LivingKnox.Groups.idNumber(gid) or 0, n * 97 + k, Food.SALT)
end

-- Tirage k de la cueillette n du groupe gid dans la zone zone aux conditions c, au plus room objets : entrées du
-- registre { t, c = "food", a = true, f = true } (objets créés au dépôt), et un texte. Rien hors nourriture.
function Food.round(gid, n, k, zone, c, room)
    Food.stats.draws = Food.stats.draws + 1
    local ok, t, cat, count = pcall(Food.draw, zone, c, Food.stream(gid, n, k))
    if not ok then
        Food.stats.failed = Food.stats.failed + 1
        log().warn("forage: group %s trip %d draw %d failed: %s", gid, n, k, tostring(t))
        return {}, "draw failed"
    end
    if t == nil then return {}, "nothing" end
    if not Food.isFood(t) then
        Food.stats.ignored = Food.stats.ignored + 1
        return {}, t .. " left (" .. tostring(cat) .. ")"
    end
    local out = {}
    for _ = 1, math.min(count, math.max(0, room or count)) do
        out[#out + 1] = { t = t, c = "food", a = true, f = true }
    end
    Food.stats.found = Food.stats.found + #out
    return out, t .. " x" .. #out .. " (" .. tostring(cat) .. ")"
end

-- ================================================================ lieu (métagrille, sans charger)

local function gapTo(x, y, z)
    local dx, dy = 0, 0
    if x < z.x then dx = z.x - x elseif x > z.x + z.w - 1 then dx = x - (z.x + z.w - 1) end
    if y < z.y then dy = z.y - y elseif y > z.y + z.h - 1 then dy = y - (z.y + z.h - 1) end
    return math.max(dx, dy)
end

local function clamp(v, lo, hi) return math.max(lo, math.min(v, hi)) end

-- Zones de la métagrille à r cases au plus de (x, y) dont le type passe accept(type) : { { type, x, y, w, h, d, px,
-- py (point de la zone le plus proche) } }, triées par distance, type et position.
local function zonesOf(x, y, r, accept)
    local world = getWorld and getWorld() or nil
    local grid = world ~= nil and world.getMetaGrid ~= nil and world:getMetaGrid() or nil
    if grid == nil then return {} end
    local list = grid:getZonesIntersecting(math.max(0, x - r), math.max(0, y - r), 0, 2 * r + 1, 2 * r + 1)
    local out, seen = {}, {}
    if list == nil then return out end
    for i = 0, list:size() - 1 do
        local zn = list:get(i)
        local t = zn ~= nil and zn:getType() or nil
        if t ~= nil and accept(t) then
            local e = { type = t, x = zn:getX(), y = zn:getY(), w = zn:getWidth(), h = zn:getHeight() }
            local key = t .. e.x .. "," .. e.y .. "," .. e.w .. "," .. e.h
            if not seen[key] and e.w > 0 and e.h > 0 then
                seen[key] = true
                e.d = gapTo(x, y, e)
                e.px, e.py = clamp(x, e.x, e.x + e.w - 1), clamp(y, e.y, e.y + e.h - 1)
                if e.d <= r then out[#out + 1] = e end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        if a.type ~= b.type then return a.type < b.type end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return out
end

-- Zones de cueillette à r cases au plus de (x, y) (zonesOf : types FORAGE_ZONES définis par forageSystem.zoneDefs).
function Food.zonesNear(x, y, r)
    local fs = Food.vanilla()
    if fs == nil then return {} end
    return zonesOf(x, y, r, function(t) return Food.FORAGE_ZONES[t] == true and fs.zoneDefs[t] ~= nil end)
end

-- Case chargée, libre (LK_Bodies.freeSquare : ni plante ni feu de camp autour) et hors bâtiment de la zone zn, la
-- plus proche de (px, py), la rank-ième ; ou nil.
function Food.spotIn(zn, px, py, z, radius, rank)
    local B = LivingKnox.Bodies
    local cell = getCell()
    if cell == nil then return nil end
    local n = 0
    for r = 0, radius do
        for _, d in ipairs(B.ring(r)) do
            local x, y = px + d[1], py + d[2]
            if gapTo(x, y, zn) == 0 then
                local sq = cell:getGridSquare(x, y, z)
                if sq ~= nil and sq:getBuildingDef() == nil and not sq:HasStairs() and B.freeSquare(sq) then
                    n = n + 1
                    if n >= (rank or 1) then return sq end
                end
            end
        end
    end
    return nil
end

-- Vrai si les manques want ({ { c, m } }, ordre du manque) appellent une cueillette : la nourriture manque le plus.
function Food.wanted(want)
    return type(want) == "table" and want[1] ~= nil and want[1].c == "food" and (want[1].m or 0) > 0
end

-- Lieu d'une cueillette pour le groupe (registre vivant g) : { x, y, z, b = TARGET, room = type de zone, label, d,
-- score, zone }, ou nil et une raison. Zone de cueillette la plus proche où au moins MIN_YIELD des tirages
-- rapportent de la nourriture aux conditions du moment (mois, jour, météo : la saison décide).
function Food.pickTarget(gid, g)
    if Food.vanilla() == nil then return nil, "vanilla foraging tables not ready" end
    local home = g.home
    if type(home) ~= "table" then return nil, "no home" end
    local c = Food.conditions()
    local zones = Food.zonesNear(home.x, home.y, cfg().MAX_DIST)
    if #zones == 0 then return nil, "no foraging zone within " .. cfg().MAX_DIST .. " squares" end
    local tried, barren = 0, 0
    for i, zn in ipairs(zones) do
        if i > cfg().MAX_ZONES or tried >= cfg().MAX_CANDIDATES then break end
        local y = Food.yield(zn.type, c)
        if y < cfg().MIN_YIELD then
            barren = barren + 1
        else
            tried = tried + 1
            local sq = Food.spotIn(zn, zn.px, zn.py, 0, cfg().SPOT_RADIUS, 1)
            if sq ~= nil then
                local x, yy = sq:getX(), sq:getY()
                return { x = x, y = yy, z = 0, b = Food.TARGET, room = zn.type,
                    label = string.format("forage %s %d,%d", zn.type, x, yy), d = zn.d, score = y, zone = zn }
            end
        end
    end
    if tried == 0 then
        return nil, "too little to forage now in " .. barren .. " zone(s) (" .. Food.conditionText(c) .. ")"
    end
    return nil, "no loaded free square in the " .. tried .. " nearest foraging zone(s)"
end

-- ================================================================ pêche (LK05-T11)
-- Aucun tirage vanilla de pêche n'est utilisable sans joueur (Fish:getFishByLure lit le personnage, la canne, le
-- mini-jeu du client et remet la vitesse du jeu à 1 : base food-production.md). La pêche d'un groupe reprend les
-- TABLES du filet vanilla (M/shared/Fishing/fishing_properties.lua:693-706 : Fishing.fishNet, Fishing.fishNetWithBait ;
-- objet tiré uniformément dans la table comme fishingNet.checkTrap, M/server/Fishing/BuildingObjects/FishingNet.lua
-- :103-150) avec un flux reproductible propre ; l'objet est créé au dépôt par instanceItem du type tiré (OnCreate
-- vanilla du script : Fishing.onCreateFish donne sa taille au poisson). Rien hors nourriture (grenouille vivante :
-- DisplayCategory « Frog », laissée).

-- Vrai si l'heure du jour hod (0..23) est dans une fenêtre de pêche (FISH_HOURS, FISH_SPAN heures chacune).
function Food.fishHour(hod)
    if type(hod) ~= "number" then return false end
    for _, h in ipairs(Food.FISH_HOURS) do
        if (hod - h) % 24 < cfg().FISH_SPAN then return true end
    end
    return false
end

-- Tables du filet vanilla prêtes (Fishing, partagé : chargé aussi sur un serveur dédié), ou nil.
function Food.fishTables()
    local f = Fishing
    if type(f) ~= "table" or type(f.fishNet) ~= "table" or #f.fishNet == 0 then return nil end
    return f
end

-- Un tirage de pêche avec le flux rnd : type pris et table (« net » ou « bait »), ou nil (rien pris). Trois nombres
-- du flux toujours consommés (prise, table, objet).
function Food.fishDraw(rnd)
    local f = Food.fishTables()
    if f == nil then return nil end
    local hit, which, pick = rnd(), rnd(), rnd()
    if hit >= cfg().FISH_CHANCE then return nil end
    local list, name = f.fishNet, "net"
    if which < cfg().FISH_BAIT and type(f.fishNetWithBait) == "table" and #f.fishNetWithBait > 0 then
        list, name = f.fishNetWithBait, "bait"
    end
    return list[math.min(#list, math.floor(pick * #list) + 1)], name
end

-- Flux du tirage k de la sortie de pêche n du groupe gid.
function Food.fishStream(gid, n, k)
    local Si = LivingKnox.Simulation
    return Si.stream(Si.baseSeed(), LivingKnox.Groups.idNumber(gid) or 0, n * 97 + k, Food.FISH_SALT)
end

-- Tirage k de la sortie de pêche n du groupe gid : entrées du registre { t, c = "food", a = true, f = true } (objet
-- créé au dépôt ; aucune si room vaut 0), et un texte. Rien hors nourriture.
function Food.fishRound(gid, n, k, room)
    Food.stats.fishDraws = Food.stats.fishDraws + 1
    local ok, t, which = pcall(Food.fishDraw, Food.fishStream(gid, n, k))
    if not ok then
        Food.stats.failed = Food.stats.failed + 1
        log().warn("fishing: group %s trip %d draw %d failed: %s", gid, n, k, tostring(t))
        return {}, "draw failed"
    end
    if t == nil then return {}, "nothing" end
    if not Food.isFood(t) or (room ~= nil and room <= 0) then
        Food.stats.ignored = Food.stats.ignored + 1
        return {}, t .. " left (" .. tostring(which) .. ")"
    end
    Food.stats.caught = Food.stats.caught + 1
    return { { t = t, c = "food", a = true, f = true } }, t .. " (" .. tostring(which) .. ")"
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local SIDES = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

-- Case d'eau voisine (par un côté) de la case sq : x, y, ou nil.
local function waterBeside(cell, sq)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for _, d in ipairs(SIDES) do
        local q = cell:getGridSquare(x + d[1], y + d[2], z)
        if q ~= nil and q:isWaterSquare() then return x + d[1], y + d[2] end
    end
    return nil
end

-- Rive libre, la rank-ième la plus proche de (px, py), à radius cases au plus : case chargée, sèche, hors bâtiment,
-- libre (LK_Bodies.freeSquare), à côté d'une case d'eau. Rend la case et la case d'eau voisine (x, y), ou nil.
function Food.shoreSpot(px, py, z, radius, rank)
    local B = LivingKnox.Bodies
    local cell = getCell()
    if cell == nil or B == nil then return nil end
    local n = 0
    for r = 0, radius do
        for _, d in ipairs(B.ring(r)) do
            local sq = cell:getGridSquare(px + d[1], py + d[2], z)
            if sq ~= nil and not sq:isWaterSquare() and sq:getBuildingDef() == nil and not sq:HasStairs()
                and B.freeSquare(sq) then
                local wx, wy = waterBeside(cell, sq)
                if wx ~= nil then
                    n = n + 1
                    if n >= (rank or 1) then return sq, wx, wy end
                end
            end
        end
    end
    return nil
end

-- Points d'eau à r cases au plus de (x, y) : zones Water de la métagrille (inscrites au premier chargement d'un
-- chunk de leur cellule, au grain du chunk : base world-placement.md), sinon la case d'eau chargée la plus proche
-- (relevé au pas WATER_STEP). Liste { { px, py, d } } triée par distance.
function Food.waterNear(x, y, r)
    local out = {}
    for _, zn in ipairs(zonesOf(x, y, r, function(t) return t == Food.FISH_ROOM end)) do
        out[#out + 1] = { px = zn.px, py = zn.py, d = zn.d }
    end
    if #out > 0 then return out end
    local cell = getCell()
    if cell == nil then return out end
    local best
    local step = math.max(1, cfg().WATER_STEP)
    for dy = -r, r, step do
        for dx = -r, r, step do
            local sq = cell:getGridSquare(x + dx, y + dy, 0)
            if sq ~= nil and sq:isWaterSquare() then
                local d = cheb(x, y, x + dx, y + dy)
                if best == nil or d < best.d then best = { px = x + dx, py = y + dy, d = d } end
            end
        end
    end
    if best ~= nil then out[1] = best end
    return out
end

-- Lieu d'une sortie de pêche pour le groupe (registre vivant g) : { x, y, z, b = FISH_TARGET, room = FISH_ROOM,
-- label, d, score }, ou nil et une raison. Rive libre près du point d'eau le plus proche du foyer (MAX_DIST cases).
function Food.fishTarget(gid, g)
    if Food.fishTables() == nil then return nil, "vanilla fishing tables not ready" end
    local home = type(g) == "table" and g.home or nil
    if type(home) ~= "table" then return nil, "no home" end
    local points = Food.waterNear(home.x, home.y, cfg().MAX_DIST)
    if #points == 0 then return nil, "no water within " .. cfg().MAX_DIST .. " squares" end
    for i, p in ipairs(points) do
        if i > cfg().MAX_CANDIDATES then break end
        local sq = Food.shoreSpot(p.px, p.py, 0, cfg().SHORE_RADIUS, 1)
        if sq ~= nil then
            local sx, sy = sq:getX(), sq:getY()
            return { x = sx, y = sy, z = 0, b = Food.FISH_TARGET, room = Food.FISH_ROOM,
                label = string.format("fish %d,%d", sx, sy), d = cheb(home.x, home.y, sx, sy), score = 1 }
        end
    end
    return nil, "no loaded free shore near the " .. math.min(#points, cfg().MAX_CANDIDATES)
        .. " nearest water area(s)"
end

-- ================================================================ création au dépôt

-- Cueilleur prêté aux fonctions d'apparition vanilla (forageSystem.getPerkLevel lit getPerkLevel ; aucune autre
-- méthode d'un personnage n'est lue par les spawnFuncs des définitions vanilla 42.21).
local GATHERER = {}
function GATHERER.getPerkLevel() return cfg().FORAGE_LEVEL end
function GATHERER.getInventory() return nil end

-- Objets d'une entrée de cueillette de type t : liste d'objets (le type tiré, plus les graines éventuelles), objets
-- empoisonnés jetés. Rend la liste et le nombre jetés.
function Food.make(t)
    local item = instanceItem(t)
    if item == nil then return {}, 0 end
    local fs = Food.vanilla()
    local def = fs ~= nil and fs.itemDefs ~= nil and fs.itemDefs[t] or nil
    local list = ArrayList.new()
    list:add(item)
    if type(def) == "table" and type(def.spawnFuncs) == "table" then
        for _, fn in ipairs(def.spawnFuncs) do
            if type(fn) == "function" then
                local ok, res = pcall(fn, GATHERER, nil, def, list)
                if ok and res ~= nil then
                    list = res
                elseif not ok then
                    Food.stats.failed = Food.stats.failed + 1
                    log().warn("forage: spawn function of %s failed: %s", t, tostring(res))
                end
            end
        end
    end
    local out, poisoned = {}, 0
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if it ~= nil then
            if it.getPoisonPower ~= nil and (it:getPoisonPower() or 0) > 0 then
                poisoned = poisoned + 1
            else
                out[#out + 1] = it
            end
        end
    end
    Food.stats.made = Food.stats.made + #out
    Food.stats.poisoned = Food.stats.poisoned + poisoned
    return out, poisoned
end

return Food
