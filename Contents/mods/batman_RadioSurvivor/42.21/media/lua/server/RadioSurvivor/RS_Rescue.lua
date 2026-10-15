if isClient() then return end
--[[
Survivants à secourir (E12-T01) : choix du bâtiment par la métagrille, sans charger aucune case, et indices
descriptifs sans coordonnées. Autorité seulement (serveur dédié ou solo). Détails : docs/rescue.md.

    local Rescue = require "RadioSurvivor/RS_Rescue"
    local site, reason = Rescue.pick({ seed = 42, minDistance = 600, avoid = { { x = 100, y = 200 } } })
    -- site = { x, y, z, buildingId, key, kind, label, bounds = { x1, y1, x2, y2 }, attempts, clues = { ... } }

Tirage : un index au hasard dans getWorld():getMetaGrid():getBuildings() (tous les BuildingDef de la carte après
fusion des dossiers), au plus CONFIG.MAX_ATTEMPTS fois ; chaque essai lit seulement le BuildingDef et ses RoomDef
(noms, niveaux, rectangles), la zone de la métagrille au point choisi et les bases connues : aucun getGridSquare,
LoadChunk, getChunk ni getBuildingAt(x, y) (qui parcourt toute la liste). Graine (opts.seed, nombre ou chaîne) :
tirage Park-Miller reproductible pour une même carte et les mêmes mods ; sans graine, ZombRand.

Habitable : premier type de Rescue.KINDS dont les pièces correspondent (église, école, poste de police, caserne,
hôpital, clinique, motel, ferme, immeuble, maison avec garage, maison) ; ni bâtiment de joueur (isUserDefined), ni
sous-sol seul, ni surface sous CONFIG.MIN_AREA.
Base connue : refuges vanilla (SafeHouse.getSafehouseList), position des joueurs connectés (serveur) ou locaux
(solo), points ou rectangles donnés par l'appelant (opts.avoid). Ne couvre pas : joueurs hors ligne, constructions
sans refuge déclaré, véhicules garés, cachettes. Distance = écart entre le rectangle du bâtiment et la base.
Terre ferme : un bâtiment de carte est posé sur des cases de sol ; le point retenu est le centre d'un rectangle de
pièce, et une zone « Water » de la métagrille à ce point (cellules déjà approchées seulement) écarte le bâtiment.

Indices (Rescue.clues) : en anglais, destinés au prompt du pont, sans aucun chiffre : type, taille et étages du
bâtiment, repères voisins tirés des bâtiments proches de la métagrille (IsoMetaCell:getBuildingsIntersecting des
seules cellules utiles) avec une direction et une distance en mots, ville la plus proche si la carte vanilla est
chargée (getLotDirectories, centres des annotations vanilla). Rien n'est envoyé au pont ici, rien n'est écrit en
ModData. Le site rendu ne contient que des valeurs simples (sérialisables), jamais d'objet Java.
Seul l'ASCII est utilisé dans les chaînes (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).

Secours en cours (E12-T02) : réserves, délai et équipe, dans l'état privé (RS_State : S.data.rescues, fichier
serveur, jamais en ModData globale). Le délai annoncé en jours de jeu EST la réserve : reserves (heures de jeu,
flottant) = jours x 24 au départ (jours : opts.days, sinon l'option sandbox RescueDays, E12-T06) ; une livraison
(E12-T03, Rescue.addReserves) la fait remonter ; à zéro, l'issue est « missed » (trop tard). Décompte : à chaque
sondage (POLL_MS réelles, OnTickEvenPaused, et chaque EveryHours),
l'écart de getWorldAgeHours depuis le sondage précédent est retiré des réserves actives seulement si au moins un
joueur est connecté (getOnlinePlayers sur un serveur, joueurs locaux en solo) ; sinon le temps passe sans rien
retirer et n'est jamais rattrapé (serveur vide sans PauseEmpty). Le premier sondage d'une session ne retire rien.
Équipe : RS_Factions.idOf (faction vanilla ou joueur seul, E09-T03) ; un seul secours actif par équipe (refus
« team_busy »), bâtiments distincts entre les secours actifs ou dont la scène reste à poser.
    local id, why = Rescue.start(player, { days = 3, requester = "Darlene" })   -- ou startForTeam(teamId, opts)
    Rescue.activeFor(teamId) / Rescue.get(id) / Rescue.list()  -> copies (daysLeft, hoursLeft)
    Rescue.addReserves(id, hours)                 -- E12-T03 : dépôt réel constaté par l'appelant
    Rescue.noteApproach(id, info)                 -- E12-T03 : approche d'un membre de l'équipe (RS_RescueVisit)
Livraison sur place et approche (E12-T03) : RS_RescueVisit.lua (lectures de cases, hors de ce fichier qui n'en fait
aucune) ; opts.site de startForTeam impose un site déjà examiné (suites en jeu).
    Rescue.finish(id, "saved" | "missed" | "abandoned", { participants = { noms } })   -- E12-T04 / T05
    Rescue.onOutcome = function(rescue, result) end                -- écouteur unique facultatif (copie)
    Rescue.pendingScenes() / Rescue.scenePlaced(id)                 -- scènes « à temps » / « trop tard »
Fait du jour (RS_Facts, global RS_Facts s'il est chargé) : 'rescue' { result, requester, participants, place
arrondie à la ville } à l'issue saved ou missed.
Issue « à temps » (E12-T04) : RS_RescueVisit note les aidants après un dépôt réel (Rescue.noteHelpers : rec.helped,
rec.helpers = { name, caller, cid }) et clôt « saved » quand plus aucun membre n'est près du bâtiment ; les noms des
aidants deviennent les participants par défaut. Rescue.sceneHook(rec, result) (RS_RescueScene, enregistrement
interne : le secours réel, pas une copie) prépare la scène à l'issue saved ou missed. Rescue.isWorkStore() : magasin
de travail actif (suites en jeu).
Issue « trop tard » (E12-T05) : au départ, rec.survivors (Rescue.drawSurvivors : 2 ou 3 tenues vanilla distinctes de
Rescue.OUTFITS, le premier est le demandeur) et rec.looks (Rescue.looks : phrases anglaises que la voix dira) ; à
l'issue missed, RS_RescueLost (enveloppe de Rescue.sceneHook) en fait des zombies en tenue (E12-T07), le
demandeur porte les dernières pages.
]]
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local S = require "RadioSurvivor/RS_State"
local Factions = require "RadioSurvivor/RS_Factions"

local Rescue = {}

Rescue.CONFIG = {
    MIN_DISTANCE = 600,      -- cases entre le bâtiment et toute base connue (zone chargée : 79 cases au plus)
    MAX_ATTEMPTS = 300,      -- tirages par appel
    MIN_AREA = 20,           -- surface totale des pièces (cases, tous niveaux)
    LANDMARK_RADIUS = 160,   -- cases autour du bâtiment pour les repères voisins
    MAX_LANDMARKS = 3,
    VANILLA_MAP = "Muldraugh, KY",
}

-- Types de bâtiment habitable, premier qui convient. all : toutes ces pièces ; any : au moins une ; min : nombre
-- minimal de pièces d'un nom. main : pièces préférées pour le point du site.
Rescue.KINDS = {
    { kind = "church", label = "church", any = { "church" }, main = { "church" } },
    { kind = "school", label = "school", any = { "classroom", "elementaryclassroom" }, main = { "classroom" } },
    { kind = "police", label = "police station", any = { "policestorage" } },
    { kind = "firestation", label = "fire station", any = { "firestorage" } },
    { kind = "hospital", label = "hospital", any = { "hospitalroom" }, main = { "hospitalroom" } },
    { kind = "clinic", label = "medical clinic", any = { "medical", "medicalstorage" }, main = { "medical" } },
    { kind = "motel", label = "motel", any = { "motelroom", "motelroomoccupied" }, main = { "motelroom" } },
    { kind = "farmhouse", label = "farmhouse", all = { "bedroom" }, any = { "barn", "farmstorage" },
      main = { "livingroom", "kitchen" } },
    { kind = "apartments", label = "apartment building", min = { bedroom = 4, kitchen = 2 },
      main = { "livingroom", "kitchen" } },
    { kind = "house_garage", label = "house with a garage", all = { "bedroom", "garagestorage" },
      main = { "livingroom", "kitchen" } },
    { kind = "house", label = "house", all = { "bedroom" }, any = { "kitchen", "livingroom" },
      main = { "livingroom", "kitchen" } },
}

-- Repères voisins : premier type qui convient (any seulement).
Rescue.LANDMARKS = {
    { kind = "gas", label = "a gas station", any = { "gasstore", "fossoil" } },
    { kind = "grocery", label = "a grocery store",
      any = { "grocery", "gigamart", "conveniencestore", "cornerstore", "generalstore" } },
    { kind = "church", label = "a church", any = { "church" } },
    { kind = "school", label = "a school", any = { "classroom", "elementaryclassroom" } },
    { kind = "police", label = "a police station", any = { "policestorage" } },
    { kind = "firestation", label = "a fire station", any = { "firestorage" } },
    { kind = "hospital", label = "a hospital", any = { "hospitalroom" } },
    { kind = "pharmacy", label = "a pharmacy", any = { "pharmacy" } },
    { kind = "clinic", label = "a medical clinic", any = { "medical", "medicalstorage" } },
    { kind = "motel", label = "a motel", any = { "motelroom", "motelroomoccupied" } },
    { kind = "gunstore", label = "a gun store", any = { "gunstore" } },
    { kind = "bar", label = "a bar", any = { "bar" } },
    { kind = "restaurant", label = "a restaurant", any = { "spiffo_dining", "pizzawhirled" } },
    { kind = "liquor", label = "a liquor store", any = { "liquorstore" } },
    { kind = "hardware", label = "a hardware store", any = { "toolstore" } },
    { kind = "mechanic", label = "a car repair shop", any = { "mechanic" } },
    { kind = "post", label = "a post office", any = { "post" } },
    { kind = "library", label = "a library", any = { "library" } },
    { kind = "theatre", label = "a movie theater", any = { "theatre" } },
    { kind = "bakery", label = "a bakery", any = { "bakery" } },
    { kind = "clothing", label = "a clothing store", any = { "clothingstore", "departmentstore" } },
    { kind = "bookstore", label = "a bookstore", any = { "bookstore" } },
    { kind = "gym", label = "a gym", any = { "gym" } },
    { kind = "daycare", label = "a daycare", any = { "daycare" } },
    { kind = "warehouse", label = "a warehouse", any = { "warehouse" } },
    { kind = "barn", label = "a barn", any = { "barn" } },
}

-- Villes de la carte vanilla : centre des annotations (media/maps/Muldraugh, KY/worldmap-annotations.lua, base
-- knox-geography.md) et rayon approximatif en cases. N'est utilisé que si la carte vanilla est chargée.
Rescue.TOWNS = {
    { name = "Louisville", x = 13077, y = 2238, r = 2200 },
    { name = "Valley Station", x = 13447, y = 5278, r = 900 },
    { name = "West Point", x = 11654, y = 6864, r = 900 },
    { name = "Muldraugh", x = 10754, y = 9926, r = 900 },
    { name = "Riverside", x = 6450, y = 5430, r = 800 },
    { name = "Brandenburg", x = 2056, y = 6070, r = 800 },
    { name = "Ekron", x = 634, y = 9746, r = 600 },
    { name = "Irvington", x = 2427, y = 14185, r = 800 },
    { name = "Echo Creek", x = 3589, y = 10952, r = 600 },
    { name = "March Ridge", x = 10130, y = 12801, r = 700 },
    { name = "Fallas Lake", x = 7253, y = 8279, r = 600 },
    { name = "Rosewood", x = 8159, y = 11661, r = 700 },
}

local CELL = 256

local function log(msg)
    Const.log("rescue: " .. msg)
end

local function metaGrid()
    local world = getWorld and getWorld()
    return world and world:getMetaGrid()
end

-- Tirage : draw(n) -> entier de 0 à n - 1. Graine : Park-Miller (quotients sous 2^31, aucun opérateur binaire).
local PM = 2147483647
local function seedNumber(seed)
    if type(seed) == "number" then return math.floor(math.abs(seed)) % PM end
    local h = 7
    local s = tostring(seed)
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % PM end
    return h
end

local function drawer(seed)
    if seed == nil then
        return function(n) return ZombRand(n) end
    end
    local x = (seedNumber(seed) * 7919 + 104729) % PM
    if x == 0 then x = 1 end
    local function draw(n)
        x = (x * 48271) % PM
        x = (x + (x % 65521) * 31337) % PM
        if x == 0 then x = 1 end
        return math.floor(x / PM * n)
    end
    for _ = 1, 6 do draw(1) end
    return draw
end
-- Exposé pour les autres choix de lieu sans chargement (LivingKnox/LK_Sites, LK08-T03) ; même tirage.
Rescue.drawer = drawer

-- Pièces d'un bâtiment : nombre par nom (minuscules), surface totale, niveaux.
local function roomCounts(b)
    local counts = {}
    local rooms = b:getRooms()
    for i = 0, rooms:size() - 1 do
        local name = rooms:get(i):getName()
        if name then
            name = string.lower(name)
            counts[name] = (counts[name] or 0) + 1
        end
    end
    return counts, rooms
end

local function matches(rule, counts)
    if rule.all then
        for _, name in ipairs(rule.all) do
            if not counts[name] then return false end
        end
    end
    if rule.any then
        local found = false
        for _, name in ipairs(rule.any) do
            if counts[name] then found = true break end
        end
        if not found then return false end
    end
    if rule.min then
        for name, n in pairs(rule.min) do
            if (counts[name] or 0) < n then return false end
        end
    end
    return true
end

local function firstRule(rules, counts)
    for _, rule in ipairs(rules) do
        if matches(rule, counts) then return rule end
    end
    return nil
end

-- Type habitable d'un BuildingDef (règle de Rescue.KINDS), ou nil.
function Rescue.classify(b)
    if b == nil then return nil end
    return firstRule(Rescue.KINDS, (roomCounts(b)))
end

-- Repère (règle de Rescue.LANDMARKS) d'un BuildingDef, ou nil.
function Rescue.landmarkOf(b)
    if b == nil then return nil end
    return firstRule(Rescue.LANDMARKS, (roomCounts(b)))
end

local function bounds(b)
    return { x1 = b:getX(), y1 = b:getY(), x2 = b:getX2(), y2 = b:getY2() }
end

-- Écart entre deux rectangles à fin exclusive (0 s'ils se touchent ou se chevauchent).
local function gap(a, b)
    local gx = math.max(0, b.x1 - a.x2, a.x1 - b.x2)
    local gy = math.max(0, b.y1 - a.y2, a.y1 - b.y2)
    return math.sqrt(gx * gx + gy * gy)
end
Rescue.gap = gap

local function pointRect(x, y, source)
    local fx, fy = math.floor(x), math.floor(y)
    return { x1 = fx, y1 = fy, x2 = fx + 1, y2 = fy + 1, source = source }
end

local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers and getOnlinePlayers()
        if list then
            for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        end
    elseif getNumActivePlayers and getSpecificPlayer then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

-- Bases connues : liste de rectangles { x1, y1, x2, y2 (exclusifs), source }. Voir l'en-tête.
function Rescue.knownBases(opts)
    opts = opts or {}
    local out = {}
    if SafeHouse and SafeHouse.getSafehouseList then
        local list = SafeHouse.getSafehouseList()
        for i = 0, (list and list:size() or 0) - 1 do
            local sh = list:get(i)
            local x, y = sh:getX(), sh:getY()
            out[#out + 1] = { x1 = x, y1 = y, x2 = x + sh:getW(), y2 = y + sh:getH(), source = "safehouse" }
        end
    end
    for _, p in ipairs(players()) do
        out[#out + 1] = pointRect(p:getX(), p:getY(), "player")
    end
    for _, a in ipairs(opts.avoid or {}) do
        if a.x1 then
            out[#out + 1] = { x1 = a.x1, y1 = a.y1, x2 = a.x2, y2 = a.y2, source = a.source or "avoid" }
        elseif a.x then
            out[#out + 1] = pointRect(a.x, a.y, a.source or "avoid")
        end
    end
    return out
end

local function nearestBase(rect, bases)
    local best, bestBase = nil, nil
    for _, base in ipairs(bases) do
        local d = gap(rect, base)
        if best == nil or d < best then best, bestBase = d, base end
    end
    return best, bestBase
end

local function inList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- Point du site : centre du premier rectangle d'une pièce, de préférence une pièce « main » du type au niveau 0,
-- sinon la plus grande pièce de niveau 0 ou plus, sinon la première pièce.
local function sitePoint(rooms, rule)
    local best, bestScore = nil, nil
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        local z = room:getZ()
        if z >= 0 and room:getRects():size() > 0 then
            local name = string.lower(room:getName() or "")
            local score = room:getArea() - z * 10000
            if inList(rule.main, name) then score = score + 100000 end
            if bestScore == nil or score > bestScore then best, bestScore = room, score end
        end
    end
    if best == nil then return nil end
    local rect = best:getRects():get(0)
    local x = math.floor((rect:getX() + rect:getX2() - 1) / 2)
    local y = math.floor((rect:getY() + rect:getY2() - 1) / 2)
    return x, y, best:getZ()
end

local function onWater(grid, x, y)
    local zones = grid:getZonesAt(x, y, 0)
    for i = 0, (zones and zones:size() or 0) - 1 do
        if zones:get(i):getType() == "Water" then return true end
    end
    return false
end

local function insideMap(grid, x, y)
    if not grid:isValidSquare(x, y) then return false end
    return grid:getCellData(math.floor(x / CELL), math.floor(y / CELL)) ~= nil
end

-- Examine un BuildingDef : site (table simple) ou nil et la raison du refus. opts.rules (facultatif) remplace la
-- liste des types admis (Rescue.KINDS par défaut ; même format) : LivingKnox/LK_Sites y ajoute les repaires (LK08-T08).
function Rescue.check(b, bases, opts, grid)
    opts = opts or {}
    if b == nil then return nil, "missing" end
    if b:isUserDefined() then return nil, "player-built" end
    if b:getRooms():size() == 0 or b:isBasement() then return nil, "no ground room" end
    local counts, rooms = roomCounts(b)
    local rule = firstRule(opts.rules or Rescue.KINDS, counts)
    if rule == nil then return nil, "not habitable" end
    if b:getArea() < (opts.minArea or Rescue.CONFIG.MIN_AREA) then return nil, "too small" end
    local id = b:getIDString()
    local key = "b" .. tostring(id)
    if opts.exclude and opts.exclude[key] then return nil, "excluded" end
    local rect = bounds(b)
    local d = nearestBase(rect, bases or {})
    if d ~= nil and d < (opts.minDistance or Rescue.CONFIG.MIN_DISTANCE) then return nil, "near a known base" end
    local x, y, z = sitePoint(rooms, rule)
    if x == nil then return nil, "no ground room" end
    if not insideMap(grid, x, y) then return nil, "outside the map" end
    if onWater(grid, x, y) then return nil, "water" end
    return { x = x, y = y, z = z, buildingId = id, key = key, kind = rule.kind, label = rule.label,
             bounds = rect, baseDistance = d and math.floor(d) or nil }
end

local function reasonSummary(reasons)
    local keys = {}
    for k in pairs(reasons) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. " " .. reasons[k] end
    return table.concat(parts, ", ")
end

-- Tire un bâtiment habitable loin des bases connues. opts (facultatifs) : seed, minDistance, maxAttempts, minArea,
-- avoid (liste de { x, y } ou { x1, y1, x2, y2 }), exclude (ensemble de clés de site déjà prises), noClues.
-- Rend le site, ou nil et la raison.
function Rescue.pick(opts)
    opts = opts or {}
    local grid = metaGrid()
    if grid == nil then return nil, "no metagrid" end
    local list = grid:getBuildings()
    local n = list and list:size() or 0
    if n == 0 then return nil, "no building in the metagrid" end
    local bases = Rescue.knownBases(opts)
    local draw = drawer(opts.seed)
    local maxAttempts = opts.maxAttempts or Rescue.CONFIG.MAX_ATTEMPTS
    local reasons = {}
    for attempt = 1, maxAttempts do
        local b = list:get(draw(n))
        local site, why = Rescue.check(b, bases, opts, grid)
        if site then
            site.attempts = attempt
            if not opts.noClues then site.clues, site.clueData = Rescue.clueData(b, grid) end
            log("picked a " .. site.kind .. " (" .. site.key .. ") after " .. attempt .. " draw(s)")
            return site
        end
        reasons[why] = (reasons[why] or 0) + 1
    end
    local reason = "no suitable building after " .. maxAttempts .. " draw(s): " .. reasonSummary(reasons)
    log(reason)
    return nil, reason
end

-- Indices --------------------------------------------------------------------------------------------------------

local NUMBER_WORDS = { "two", "three", "four", "five" }
-- Voisins comptés comme maisons (indice « rue habitée » ou « isolé »).
local RESIDENTIAL = { house = true, house_garage = true, farmhouse = true, apartments = true }

local function sizeWord(area)
    if area < 60 then return "small " end
    if area < 200 then return "" end
    if area < 500 then return "large " end
    return "very large "
end

local function floorsWord(b)
    local top = b:getMaxLevel()
    local bottom = math.max(0, b:getMinLevel())
    local levels = top - bottom + 1
    if levels <= 1 then return "single-storey " end
    if levels <= #NUMBER_WORDS + 1 then return NUMBER_WORDS[levels - 1] .. "-storey " end
    return "tall "
end

local function article(word)
    local c = string.sub(word, 1, 1)
    if c == "a" or c == "e" or c == "i" or c == "o" or c == "u" then return "an " end
    return "a "
end

-- Direction en mots du point (x, y) vers (tx, ty) ; le nord est vers les y décroissants.
local function direction(x, y, tx, ty)
    local dx, dy = tx - x, ty - y
    local ax, ay = math.abs(dx), math.abs(dy)
    local ns = dy < 0 and "north" or "south"
    local ew = dx < 0 and "west" or "east"
    if ax > ay * 2.4 then return ew end
    if ay > ax * 2.4 then return ns end
    return ns .. "-" .. ew
end
Rescue.direction = direction

local function distanceWords(d)
    if d < 25 then return "right next to it" end
    if d < 80 then return "a short walk" end
    return "a few blocks"
end

-- Bâtiments de la métagrille dont l'emprise croise le rectangle (r autour de rect), sans b lui-même. Interroge
-- seulement les cellules couvertes (IsoMetaGrid:getBuildingsIntersecting parcourt toute la grille).
function Rescue.nearbyBuildings(grid, b, r)
    local rect = bounds(b)
    local x1, y1 = math.max(0, rect.x1 - r), math.max(0, rect.y1 - r)
    local x2, y2 = rect.x2 + r, rect.y2 + r
    local found = ArrayList.new()
    for cy = math.floor(y1 / CELL), math.floor((y2 - 1) / CELL) do
        for cx = math.floor(x1 / CELL), math.floor((x2 - 1) / CELL) do
            local cell = grid:getCellData(cx, cy)
            if cell then cell:getBuildingsIntersecting(x1, y1, x2 - x1, y2 - y1, found) end
        end
    end
    local out = {}
    local id = b:getIDString()
    for i = 0, found:size() - 1 do
        local other = found:get(i)
        if other:getIDString() ~= id then out[#out + 1] = other end
    end
    return out
end

local function hasDigits(s)
    return string.find(s, "%d") ~= nil
end
Rescue.hasDigits = hasDigits

-- Codes des mots d'un indice (E11-T09 : indices traduits par le carnet, IGUI_RS_ClueSize_<code>,
-- IGUI_RS_ClueFloors_<code>, IGUI_RS_Dir_<code>, IGUI_RS_ClueDistance_<code>).
local SIZE_CODES = { ["small "] = "small", [""] = "medium", ["large "] = "large", ["very large "] = "very_large" }
local FLOOR_CODES = { ["single-storey "] = "single", ["two-storey "] = "two", ["three-storey "] = "three",
    ["four-storey "] = "four", ["five-storey "] = "five", ["tall "] = "tall" }
local DISTANCE_CODES = { ["a short walk"] = "short", ["a few blocks"] = "blocks" }

-- Indice de ville : { texte anglais, clé, nom } ou nil.
local function townData(cx, cy)
    local ok, dirs = pcall(getLotDirectories)
    local vanilla = false
    if ok and dirs then
        for i = 0, dirs:size() - 1 do
            if dirs:get(i) == Rescue.CONFIG.VANILLA_MAP then vanilla = true break end
        end
    end
    if not vanilla then return nil end
    local best, bestD = nil, nil
    for _, town in ipairs(Rescue.TOWNS) do
        local dx, dy = town.x - cx, town.y - cy
        local d = math.sqrt(dx * dx + dy * dy) / town.r
        if bestD == nil or d < bestD then best, bestD = town, d end
    end
    if best == nil then return nil end
    if bestD <= 0.5 then return "It is in " .. best.name .. ".", "TownIn", best.name end
    if bestD <= 1 then return "It is on the outskirts of " .. best.name .. ".", "TownOutskirts", best.name end
    if bestD <= 2 then return "It is out in the country, some way from " .. best.name .. ".", "TownCountry", best.name end
    return "It is out in the countryside, far from any town.", "TownFar", nil
end
-- Exposé pour le journal des faits (RS_Facts, E14-T01) : lieu arrondi à la ville, même règle que les indices.
Rescue.town = townData

-- Indices d'un BuildingDef en deux listes parallèles : phrases anglaises sans chiffres (prompt du pont) et données
-- traduisibles { key = <suffixe de IGUI_RS_Clue_>, args = { codes ou nom propre } } (carnet, E11-T09). Une phrase qui
-- contient un chiffre est retirée avec sa donnée.
function Rescue.clueData(b, grid)
    grid = grid or metaGrid()
    local counts = roomCounts(b)
    local rule = firstRule(Rescue.KINDS, counts) or { kind = "building", label = "building" }
    local out, data = {}, {}
    local function add(text, key, args)
        out[#out + 1] = text
        data[#data + 1] = { key = key, args = args or {} }
    end
    local size, floors = sizeWord(b:getArea()), floorsWord(b)
    local words = size .. floors .. rule.label
    add("The shelter is " .. article(words) .. words .. ".", "Kind",
        { rule.kind, SIZE_CODES[size] or "medium", FLOOR_CODES[floors] or "tall" })
    if b:getMinLevel() < 0 then add("It has a basement.", "Basement") end
    local rect = bounds(b)
    local cx, cy = (rect.x1 + rect.x2) / 2, (rect.y1 + rect.y2) / 2
    local nearest, houses = {}, 0
    if grid then
        for _, other in ipairs(Rescue.nearbyBuildings(grid, b, Rescue.CONFIG.LANDMARK_RADIUS)) do
            local mark = Rescue.landmarkOf(other)
            local orect = bounds(other)
            if mark then
                local d = gap(rect, orect)
                local prev = nearest[mark.kind]
                if prev == nil or d < prev.d then
                    nearest[mark.kind] = { d = d, kind = mark.kind, label = mark.label,
                        dir = direction(cx, cy, (orect.x1 + orect.x2) / 2, (orect.y1 + orect.y2) / 2) }
                end
            elseif gap(rect, orect) < 80 and RESIDENTIAL[(Rescue.classify(other) or {}).kind or ""] then
                houses = houses + 1
            end
        end
    end
    local marks = {}
    for _, m in pairs(nearest) do marks[#marks + 1] = m end
    table.sort(marks, function(a, b2)
        if a.d ~= b2.d then return a.d < b2.d end
        return a.label < b2.label
    end)
    for i = 1, math.min(#marks, Rescue.CONFIG.MAX_LANDMARKS) do
        local m = marks[i]
        local dir = (string.gsub(m.dir, "-", "_"))
        if m.d < 25 then
            add("There is " .. m.label .. " right next to it, to the " .. m.dir .. ".", "LandmarkNext", { m.kind, dir })
        else
            local words2 = distanceWords(m.d)
            add("There is " .. m.label .. " " .. words2 .. " to the " .. m.dir .. ".", "Landmark",
                { m.kind, DISTANCE_CODES[words2] or "blocks", dir })
        end
    end
    if #marks == 0 then add("There is no shop or public building nearby.", "NoLandmark") end
    if houses == 0 then
        add("It stands on its own, with no other house close by.", "Isolated")
    elseif houses <= 4 then
        add("There are a few other houses around it.", "FewHouses")
    else
        add("It is in a built-up street, among many houses.", "BuiltUp")
    end
    local town, key, name = townData(cx, cy)
    if town then add(town, key, { name }) end
    local clean, cleanData = {}, {}
    for i, line in ipairs(out) do
        if not hasDigits(line) then
            clean[#clean + 1] = line
            cleanData[#cleanData + 1] = data[i]
        end
    end
    return clean, cleanData
end

-- Indices descriptifs d'un BuildingDef (liste de phrases anglaises sans chiffres).
function Rescue.clues(b, grid)
    return (Rescue.clueData(b, grid))
end

-- Secours en cours : réserves, délai et équipe (E12-T02) ---------------------------------------------------------

Rescue.RUN = {
    -- délai par défaut (jours de jeu de réserves au départ) : option sandbox RadioSurvivor.RescueDays (E12-T06,
    -- Const.rescueDays, défaut 3), lue au lancement de chaque secours ; opts.days l'emporte (bancs, suites en jeu).
    MIN_DAYS = 1,
    MAX_DAYS = 10,
    MAX_RESERVE_DAYS = 10, -- plafond des réserves après livraisons
    POLL_MS = 1000,        -- sondage du décompte (temps réel)
    MAX_CLOSED = 16,       -- secours clos gardés (scènes à poser d'abord)
    MAX_NAME = 48,
    MAX_HELPERS = 8,       -- aidants gardés par secours (E12-T04)
}
Rescue.RESULTS = { saved = true, missed = true, abandoned = true }

local session = { age = nil, pollAt = 0 }
local storeOverride = nil

-- Suites en jeu et bancs : un magasin de secours de travail à la place de l'état privé (nil : retour à l'état).
function Rescue.useStore(d)
    storeOverride = d
    session.age = nil
end

function Rescue.newStore()
    return { seq = 0, active = {}, rescues = {} }
end

-- Magasin de travail actif (suites en jeu) : les effets durables hors du secours (faits, relevés de vie) sont omis.
function Rescue.isWorkStore()
    return storeOverride ~= nil
end

local function store()
    if storeOverride then return storeOverride end
    if not S.data or S.blocked then return nil end
    local d = S.data.rescues
    if type(d) ~= "table" or type(d.active) ~= "table" or type(d.rescues) ~= "table" then
        d = Rescue.newStore()
        S.data.rescues = d
    end
    return d
end
Rescue.store = store

local function dirty()
    if not storeOverride then S.dirty = true end
end

local function worldAge()
    local gt = getGameTime and getGameTime()
    if not gt or not gt.getWorldAgeHours then return nil end
    local age = gt:getWorldAgeHours()
    if type(age) ~= "number" or age ~= age or age < 0 then return nil end
    return age
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function view(rec)
    local out = copy(rec)
    out.hoursLeft = math.floor(rec.reserves or 0)
    out.daysLeft = math.ceil((rec.reserves or 0) / 24)
    return out
end

local function activeRec(d, team)
    local id = d.active[team]
    local rec = id and d.rescues[id]
    if rec and rec.state == "active" then return rec end
    if id then d.active[team] = nil end
    return nil
end

local function cleanName(value)
    if type(value) ~= "string" then return nil end
    local text = Const.oneLine(string.gsub(value, "%c", " "))
    if text == "" then return nil end
    return string.sub(text, 1, Rescue.RUN.MAX_NAME)
end

-- Au moins un joueur connecté : liste du serveur, joueurs locaux en solo.
function Rescue.connected()
    if isServer() then
        local list = getOnlinePlayers and getOnlinePlayers()
        return list ~= nil and list:size() > 0
    end
    return getNumActivePlayers ~= nil and getNumActivePlayers() > 0
end

-- Survivants du groupe (E12-T05) : tenues vanilla qu'ils décrivent à la radio, portées par leurs zombies si
-- l'aide arrive trop tard (RS_RescueLost). Liste fermée de tenues présentes pour les deux sexes dans
-- media/clothing/clothing.xml 42.21 (PersistentOutfits.pickOutfit rend 0 pour un sexe absent), hors Bandit et
-- Survivalist* (remplacées par ZombiesStageDefinitions.getAdvancedOutfitName) ; look = pièce toujours portée
-- (probabilité 1 dans la tenue), en anglais, sans chiffre (donnée du prompt comme les indices).
Rescue.SURVIVORS = { MIN = 2, MAX = 3 }
Rescue.OUTFITS = {
    { outfit = "Doctor", look = "a long white doctor's coat" },
    { outfit = "Nurse", look = "hospital scrubs" },
    { outfit = "HospitalPatient", look = "a hospital gown" },
    { outfit = "Fireman", look = "firefighter's trousers" },
    { outfit = "Police", look = "a police uniform" },
    { outfit = "Ranger", look = "a park ranger's uniform" },
    { outfit = "Chef", look = "chef's checked trousers" },
    { outfit = "Fossoil", look = "a Fossoil gas station T-shirt" },
    { outfit = "Sanitation", look = "a blue and red boiler suit" },
    { outfit = "Ski", look = "padded ski trousers" },
}

-- Survivants d'un secours : MIN à MAX, tenues distinctes tirées par l'identifiant et le site (même tirage après un
-- redémarrage) ; le premier est le demandeur (la voix). Liste de { outfit, look, requester }.
function Rescue.drawSurvivors(rec)
    local draw = drawer(tostring(rec.id) .. "|" .. tostring(rec.site and rec.site.key) .. "|survivors")
    local n = Rescue.SURVIVORS.MIN + draw(Rescue.SURVIVORS.MAX - Rescue.SURVIVORS.MIN + 1)
    local pool = {}
    for i, o in ipairs(Rescue.OUTFITS) do pool[i] = o end
    local out = {}
    for i = 1, math.min(n, #pool) do
        local o = table.remove(pool, draw(#pool) + 1)
        out[i] = { outfit = o.outfit, look = o.look, requester = i == 1 or nil }
    end
    return out
end

-- Description des tenues pour la voix (phrases anglaises sans chiffre, données du prompt comme les indices).
function Rescue.looks(survivors)
    local out = {}
    for _, s in ipairs(type(survivors) == "table" and survivors or {}) do
        if s.requester then out[#out + 1] = "I am wearing " .. s.look .. "."
        else out[#out + 1] = "One of the others is wearing " .. s.look .. "." end
    end
    return out
end

-- Démarre le secours d'une équipe (identifiant 'fac-<n>' de RS_Factions). opts (facultatifs) : days, requester
-- (nom de la voix), voice (identifiant), seed, minDistance, avoid, maxAttempts. Rend id et la copie du secours, ou
-- nil, la raison ('state', 'bad_team', 'team_busy' + id du secours actif, 'no_site' + raison du tirage).
function Rescue.startForTeam(team, opts)
    opts = opts or {}
    if type(team) ~= "string" or team == "" then return nil, "bad_team" end
    local d = store()
    if not d then return nil, "state" end
    local current = activeRec(d, team)
    if current then
        log("refused a second rescue for team " .. team .. ": " .. current.id .. " is still running")
        return nil, "team_busy", current.id
    end
    local days = math.floor(tonumber(opts.days) or Const.rescueDays())
    days = math.max(Rescue.RUN.MIN_DAYS, math.min(Rescue.RUN.MAX_DAYS, days))
    local exclude = {}
    for k, v in pairs(opts.exclude or {}) do exclude[k] = v end
    for _, rec in pairs(d.rescues) do
        if rec.state == "active" or rec.scene == "pending" then exclude[rec.site.key] = true end
    end
    local site, why = opts.site, nil
    if type(site) == "table" then -- E12-T03 : site imposé (suites en jeu : bâtiment du joueur de test)
        if type(site.bounds) ~= "table" or type(site.key) ~= "string" then return nil, "no_site", "bad site" end
        if exclude[site.key] then return nil, "no_site", "excluded" end
    else
        site, why = Rescue.pick({ seed = opts.seed, minDistance = opts.minDistance, avoid = opts.avoid,
            maxAttempts = opts.maxAttempts, exclude = exclude })
    end
    if not site then return nil, "no_site", why end
    d.seq = (d.seq or 0) + 1
    local id = "rsc-" .. string.format("%.0f", d.seq)
    local rec = {
        id = id, team = team, state = "active", days = days, reserves = days * 24, consumed = 0, delivered = 0,
        startedAt = worldAge(), requester = cleanName(opts.requester), voice = cleanName(opts.voice),
        site = { x = site.x, y = site.y, z = site.z, key = site.key, buildingId = site.buildingId, kind = site.kind,
                 label = site.label, bounds = copy(site.bounds) },
        clues = copy(site.clues or {}), clueData = copy(site.clueData or {}),
    }
    rec.survivors = Rescue.drawSurvivors(rec)
    rec.looks = Rescue.looks(rec.survivors)
    d.rescues[id], d.active[team] = rec, id
    dirty()
    log(id .. " started for team " .. team .. ": a " .. site.kind .. " (" .. site.key .. "), " .. days .. " day(s)")
    return id, view(rec)
end

-- Secours de l'équipe du joueur (faction vanilla ou joueur seul).
function Rescue.start(player, opts)
    local team = player and Factions.idOf(player)
    if not team then return nil, "state" end
    return Rescue.startForTeam(team, opts)
end

-- Identifiant d'équipe d'un joueur (RS_Factions), pour les appelants.
function Rescue.teamOf(player)
    return player and Factions.idOf(player) or nil
end

function Rescue.get(id)
    local d = store()
    local rec = d and d.rescues[id]
    return rec and view(rec) or nil
end

function Rescue.activeFor(team)
    local d = store()
    local rec = d and type(team) == "string" and activeRec(d, team)
    return rec and view(rec) or nil
end

-- Copies de tous les secours (actifs et clos), par numéro.
function Rescue.list()
    local d = store()
    local out = {}
    if not d then return out end
    for _, rec in pairs(d.rescues) do out[#out + 1] = view(rec) end
    table.sort(out, function(a, b) return (tonumber(string.sub(a.id, 5)) or 0) < (tonumber(string.sub(b.id, 5)) or 0) end)
    return out
end

local function seqOf(rec)
    return tonumber(string.sub(rec.id, 5)) or 0
end

local function pruneClosed(d)
    local closed = {}
    for _, rec in pairs(d.rescues) do
        if rec.state ~= "active" then closed[#closed + 1] = rec end
    end
    if #closed <= Rescue.RUN.MAX_CLOSED then return end
    -- Les scènes à poser partent en dernier, puis le plus ancien d'abord.
    table.sort(closed, function(a, b)
        local pa, pb = a.scene == "pending" and 1 or 0, b.scene == "pending" and 1 or 0
        if pa ~= pb then return pa < pb end
        return seqOf(a) < seqOf(b)
    end)
    for i = 1, #closed - Rescue.RUN.MAX_CLOSED do d.rescues[closed[i].id] = nil end
end

-- Noms des aidants notés (E12-T04), ou nil s'il n'y en a pas.
local function helperNames(rec)
    if type(rec.helpers) ~= "table" or #rec.helpers == 0 then return nil end
    local out = {}
    for _, h in ipairs(rec.helpers) do out[#out + 1] = h.name end
    return out
end

-- Issue d'un secours actif (E12-T04 « saved », E12-T05 « missed » ou décompte à zéro, « abandoned »). fields
-- (facultatif) : participants = liste de noms de personnages (par défaut : les aidants notés). Rend la copie du
-- secours clos, ou nil et la raison.
function Rescue.finish(id, result, fields)
    if not Rescue.RESULTS[result] then return nil, "bad_result" end
    local d = store()
    if not d then return nil, "state" end
    local rec = d.rescues[id]
    if not rec or rec.state ~= "active" then return nil, "not_active" end
    rec.state, rec.closedAt = result, worldAge()
    if result ~= "abandoned" then rec.scene = "pending" end
    if d.active[rec.team] == id then d.active[rec.team] = nil end
    dirty()
    log(id .. " of team " .. rec.team .. " closed: " .. result)
    local participants = type(fields) == "table" and fields.participants or helperNames(rec)
    if result ~= "abandoned" and not storeOverride and type(RS_Facts) == "table" and RS_Facts.record then
        local _, key, town = townData(rec.site.x, rec.site.y)
        RS_Facts.record("rescue", { result = result, requester = rec.requester, participants = participants,
            place = key and { key = key, town = town } or nil }, "rescue|" .. id)
    end
    if result ~= "abandoned" and Rescue.sceneHook then Rescue.sceneHook(rec, result) end
    local out = view(rec)
    pruneClosed(d)
    if Rescue.onOutcome then Rescue.onOutcome(copy(out), result) end
    return out
end

-- Dépôt constaté (E12-T03) : ajoute des heures de réserves, plafonnées. Rend les réserves, ou nil et la raison.
function Rescue.addReserves(id, hours)
    if type(hours) ~= "number" or hours ~= hours or hours <= 0 then return nil, "bad_amount" end
    local d = store()
    if not d then return nil, "state" end
    local rec = d.rescues[id]
    if not rec or rec.state ~= "active" then return nil, "not_active" end
    rec.reserves = math.min(Rescue.RUN.MAX_RESERVE_DAYS * 24, rec.reserves + hours)
    rec.delivered = (rec.delivered or 0) + hours
    dirty()
    return rec.reserves
end

-- Approche constatée (E12-T03, RS_RescueVisit) : info = { at (âge du monde), dir (code de direction), count,
-- vehicle, smoke (nom de couleur ou nil), aired } ; gardée dans le secours (rec.approach, rec.approaches). Rend true.
function Rescue.noteApproach(id, info)
    local d = store()
    local rec = d and d.rescues[id]
    if not rec or rec.state ~= "active" or type(info) ~= "table" then return false end
    rec.approach = { at = tonumber(info.at) or worldAge(), dir = info.dir, count = tonumber(info.count) or 1,
        vehicle = info.vehicle == true, smoke = info.smoke, aired = info.aired == true }
    rec.approaches = (rec.approaches or 0) + 1
    dirty()
    return true
end

-- Aidants (E12-T04, RS_RescueVisit) : membres près du bâtiment une fois un dépôt réel fait. helpers = liste de
-- { name, caller, cid } (nom du personnage, clé d'appelant de la radio, personnage du carnet ou nil) ; gardés dans le
-- secours (rec.helpers, au plus RUN.MAX_HELPERS, une fois par appelant, personnage et nom), rec.helped = true. Rend le
-- nombre d'aidants nouveaux, ou nil si le secours n'est pas actif.
function Rescue.noteHelpers(id, helpers)
    local d = store()
    local rec = d and d.rescues[id]
    if not rec or rec.state ~= "active" then return nil end
    if type(rec.helpers) ~= "table" then rec.helpers = {} end
    local changed, added = not rec.helped, 0
    rec.helped = true
    for _, h in ipairs(type(helpers) == "table" and helpers or {}) do
        local name = type(h) == "table" and cleanName(h.name) or nil
        local caller = type(h) == "table" and cleanName(h.caller) or nil
        local cid = type(h) == "table" and type(h.cid) == "string" and h.cid or nil
        if name and caller and #rec.helpers < Rescue.RUN.MAX_HELPERS then
            local known = false
            for _, k in ipairs(rec.helpers) do
                if k.caller == caller and k.cid == cid and k.name == name then known = true break end
            end
            if not known then
                rec.helpers[#rec.helpers + 1] = { name = name, caller = caller, cid = cid }
                added = added + 1
            end
        end
    end
    if changed or added > 0 then dirty() end
    return added
end

-- Identifiants des secours actifs déjà aidés (dépôt réel fait), triés.
function Rescue.helpedActive()
    local out = {}
    local d = store()
    for id, rec in pairs(d and d.rescues or {}) do
        if rec.state == "active" and rec.helped then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- Retire des heures aux secours actifs (cœur du décompte) ; un secours à zéro est clos « missed ». Rend true si
-- l'état a changé (heure entière de réserves franchie ou issue).
function Rescue.consume(hours)
    local d = store()
    if not d or type(hours) ~= "number" or hours <= 0 then return false end
    local changed, expired = false, {}
    for id, rec in pairs(d.rescues) do
        if rec.state == "active" then
            local before = math.floor(rec.reserves)
            rec.reserves = math.max(0, rec.reserves - hours)
            rec.consumed = (rec.consumed or 0) + hours
            if math.floor(rec.reserves) ~= before then changed = true end
            if rec.reserves <= 0 then expired[#expired + 1] = id end
        end
    end
    if changed then dirty() end
    table.sort(expired)
    for _, id in ipairs(expired) do Rescue.finish(id, "missed") end
    return changed or #expired > 0
end

-- Sondage du décompte (voir l'en-tête). force : ignore l'espacement POLL_MS (EveryHours).
function Rescue.poll(force)
    local now = getTimestampMs()
    if not force and now < session.pollAt then return false end
    session.pollAt = now + Rescue.RUN.POLL_MS
    if not store() then return false end
    local age = worldAge()
    if not age then return false end
    local last = session.age
    session.age = age
    if last == nil or age <= last then return false end
    if not Rescue.connected() then return false end -- serveur vide : réserves figées, aucun rattrapage
    return Rescue.consume(age - last)
end

-- Secours clos dont la scène reste à poser (E12-T04 / T05), par numéro.
function Rescue.pendingScenes()
    local out = {}
    for _, rec in ipairs(Rescue.list()) do
        if rec.scene == "pending" then out[#out + 1] = rec end
    end
    return out
end

function Rescue.scenePlaced(id)
    local d = store()
    local rec = d and d.rescues[id]
    if not rec or rec.scene ~= "pending" then return false end
    rec.scene = "placed"
    dirty()
    return true
end

-- Bancs : oublie l'âge du monde vu en dernier (nouvelle session).
function Rescue.resetSession()
    session = { age = nil, pollAt = 0 }
end

-- Abonnements une seule fois ; le module est relu dans le global RS_Rescue à chaque appel (rechargement Lua).
RS_Rescue = Rescue
if not RS_RescueHooked and Events then
    RS_RescueHooked = true
    if Events.OnTickEvenPaused then Events.OnTickEvenPaused.Add(function() RS_Rescue.poll(false) end) end
    if Events.EveryHours then Events.EveryHours.Add(function() RS_Rescue.poll(true) end) end
end

return Rescue
