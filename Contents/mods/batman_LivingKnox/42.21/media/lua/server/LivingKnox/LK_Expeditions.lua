-- Living Knox : expéditions physiques des fourrageurs et retour au foyer (LK05-T05). Fiche :
-- docs/annexes/conception/expeditions.md. Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- 1. Départ (Expeditions.minutePass, chaque minute de jeu, chaque groupe au plus toutes les CHECK_MINUTES) : groupe
--    matérialisé dont l'objectif est « supply » (LK_Decisions), de jour (DEPART_FROM..DEPART_TO), sans expédition
--    abstraite (LK09-T02) ni expédition en cours, COOLDOWN_MINUTES après la précédente, avec un stock de référence
--    (LK_Stock) qui manque de quelque chose (Stock.needs : catégories sous leur visée, dans l'ordre du manque).
--    Équipe : membres de poste « forager », vivants, incarnés, au foyer, hors chef, santé >= TEAM_HEALTH, par numéro,
--    TEAM_MAX au plus, en laissant MIN_HOME membres au foyer. LK05-T15 (décision du 2026-10-12) : un besoin élevé
--    (Decisions.needHigh : NEED_HIGH, peur = option AfraidFear depuis LK05-T16) écarte le membre, sauf si l'expédition
--    y répond : faim et nourriture cherchée, soif et
--    eau cherchée ; fatigue ou peur élevées écartent toujours (il mange, boit ou dort au foyer à la place).
--    Lieu (I4.1, choisi par le serveur) : bâtiment de la
--    métagrille (IsoMetaCell:getBuildingsIntersecting des cellules couvertes, sans charger : base world-placement.md)
--    à MIN_DIST..MAX_DIST cases du foyer, ni le bâtiment du foyer ni celui d'un autre groupe, ni un des SEEN_MAX
--    derniers fouillés ; noté par ses pièces au niveau du foyer (noms de pièce de la carte, ROOMS : données du jeu,
--    jamais un texte de joueur) selon les manques (I4.2), moins la distance ; point visé = centre de la meilleure pièce,
--    case chargée et libre du bâtiment la plus proche. Écrit au registre (champ facultatif trips) et au journal du
--    groupe (kind « expedition »).
-- 2. Exécution (Expeditions.apply, appelé par LK_Decisions pour le comportement « expedition », règle duty de la
--    cascade : menace, peur et blessure passent avant ; faim, soif et fatigue attendent le retour) : consignes LK03
--    seulement (outils de LK_Routines.exec : marche, regard, geste), une au plus par passage.
--      out    : chaque membre marche jusqu'à une place libre près du point visé (une par rang) ; la première arrivée
--               ouvre la fouille ;
--      search : conteneurs du bâtiment visé au niveau visé, à SEARCH_RADIUS cases du point, MAX_CONTAINERS au plus,
--               du plus proche au plus loin ; chacun réservé par UN membre (I4.1, réservation en mémoire, rendue après
--               CLAIM_MINUTES sans nouvelle) ; place libre à côté (même règle que les corvées), regard, fouille
--               (geste rummage, RUMMAGE_MINUTES) ; conteneur jamais ouvert : butin vanilla tiré d'abord comme à
--               l'ouverture par un joueur (ItemPickerJava.fillContainer puis setExplored, ISInventoryPage.lua
--               :1511-1523 ; sendItemsInContainer sur un serveur, base world-placement.md) ; prise des objets dont la
--               catégorie manque (Stock.categoryOf ; nourriture et eau consommables : Stock.consumable), au plus le
--               manque de chaque catégorie et la charge de l'équipe (CARRY_PER_MEMBER x équipe, CARRY_MAX) ; objet
--               retiré (DoRemoveItem, sendRemoveItemFromContainer sur un serveur) et porté par l'expédition (mémoire,
--               liste des types au registre). Fin : manques couverts, charge pleine, plus de conteneur, ou délai ;
--      back   : retour au foyer ; le premier membre arrivé ouvre le dépôt (phase deliver).
--    Délais par phase (OUT_MINUTES, SEARCH_MINUTES, BACK_MINUTES) : une équipe bloquée finit toujours par rentrer.
-- 3. Dépôt (phase deliver, chaque minute tant que la zone du foyer n'est pas lisible) : objets portés rangés dans le
--    conteneur posé par LK_Homes (caisse, tente), sinon le premier conteneur du foyer (AddItem, sendAddItemToContainer
--    sur un serveur) et ajoutés à la référence du stock dans la même écriture que la clôture de l'expédition (journal
--    « return ») ; rationnement relu. Aucun objet n'est créé pour un butin fouillé à l'écran : les objets portés
--    sont ceux pris dans les conteneurs. Objet porté perdu de la mémoire (redémarrage du serveur) : compté perdu,
--    jamais recréé (pas de doublon possible).
-- 4. Bascule hors écran : quand les membres de l'équipe sont retirés du monde loin des joueurs (Bodies.release ->
--    Materialize.onReleased -> Expeditions.onReleased), l'expédition devient abstraite : champ expedition du groupe
--    (LK09-T02 : place « trip », équipe absente du foyer, jamais matérialisée) avec retour dans ABSTRACT_HOURS heures
--    selon la phase. Un membre retiré pendant que le reste de l'équipe est encore près d'un joueur quitte seulement
--    l'équipe (de retour au foyer pour la simulation, comme tout corps retiré). Au retour abstrait (LK_Simulation,
--    heure returns -> Expeditions.resolveAbstract) : aucun membre perdu ni blessé ; butin abstrait tiré du flux
--    reproductible de la simulation (ABSTRACT_FIND par membre et par manque, objets ABSTRACT_ITEMS), puis phase
--    deliver : le dépôt (objets abstraits créés à ce moment, seul cas de création) attend que le foyer soit lisible ;
--    les membres, de nouveau présents, sont matérialisés au foyer si un joueur est proche (reprise de l'état).
-- 5. Cueillette (LK05-T11, fiche docs/annexes/conception/nourriture.md, tirages de LivingKnox.Food) : quand la nourriture est
--    le premier manque et qu'une zone de cueillette vanilla proche rapporte assez de nourriture à cette saison
--    (Food.pickTarget), l'expédition est de genre « forage » : seulement la nourriture (want, charge), lieu = case
--    libre hors bâtiment de la zone ; en fouille, chaque membre arrivé cueille (geste FORAGE_GESTURE) et fait un
--    tirage des tables vanilla toutes les Food.CFG.ROUND_MINUTES (tirage k de la cueillette, reproductible), r tirages
--    au plus (Food.CFG.ROUNDS par membre au départ) ; objets notés au registre comme objets à créer (a, f), créés au
--    dépôt par Food.make (instanceItem + fonctions d'apparition vanilla, empoisonnés jetés). Hors écran : tirages
--    restants faits au retour abstrait, avec le même flux (même résultat qu'à l'écran aux mêmes conditions).
-- 6. Pêche (LK05-T11, décision du 2026-10-15) : à l'aube et au crépuscule (Food.fishHour : fenêtres Food.FISH_HOURS,
--    seules heures hors DEPART_FROM..DEPART_TO où un départ est permis, et pour la pêche seulement), quand la
--    nourriture est le premier manque et qu'une rive libre est à portée (Food.fishTarget : eau à Food.CFG.MAX_DIST
--    cases), l'expédition est de genre « fish » : même équipe, mêmes phases et même dépôt qu'une cueillette ; chaque
--    membre arrivé sur la rive se tourne vers l'eau, s'agenouille et fait un tirage des tables du filet vanilla
--    (Food.fishRound) toutes les Food.CFG.FISH_MINUTES, Food.CFG.FISH_ROUNDS tirages par membre au plus ; prises
--    créées au dépôt (instanceItem du type tiré). Hors écran : tirages restants au retour abstrait, même flux.
-- Persistance (registre des groupes, schéma 1 inchangé, champ facultatif contrôlé ici, oublié s'il est malformé) :
--   trips = { v = FORMAT, n = expéditions parties, last = minute de jeu de la dernière fin, seen = { bâtiments },
--             cur = { n, phase, team = { mid }, want = { { c, m } }, target = { x, y, z, b, room, label, zone },
--                     start, due (minute limite de la phase), cap, carry = { { t, c, i, a, f } }, searched = { clé },
--                     from (phase quittée hors écran), kind (« forage », « fish » ou absent), k et r (tirages faits
--                     et prévus d'une cueillette ou d'une pêche) } ou absent }.
-- Mémoire (places, réservations, objets portés) : non sauvegardée.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"
require "LivingKnox/LK_Stock"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Routines"

local Ex = LivingKnox.Expeditions or {}
LivingKnox.Expeditions = Ex

Ex.FORMAT = 1
Ex.PHASES = { out = true, search = true, back = true, away = true, deliver = true }
Ex.ACTIVE = { out = true, search = true, back = true }   -- membres menés par la cascade (comportement « expedition »)
Ex.GESTURE = "rummage"
Ex.FORAGE_GESTURE = "kneel"                              -- cueillette (LK05-T11)
Ex.FORAGE = "forage"                                     -- genre d'une cueillette (= LivingKnox.Food.KIND)
Ex.FISH = "fish"                                         -- genre d'une sortie de pêche (= LivingKnox.Food.FISH_KIND)
Ex.DRAWN = { forage = true, fish = true }                -- genres à tirages (k, r) sur place, objets créés au dépôt
Ex.PLACE = "trip"                                       -- lieu de l'expédition abstraite (LK_Simulation)
-- Pièces de la carte (RoomDef:getName, noms des distributions vanilla M/lua/server/Items/Distributions.lua) qui
-- promettent une catégorie du stock.
Ex.ROOMS = {
    food = { "kitchen", "grocery", "grocerystorage", "conveniencestore", "cornerstore", "gigamart", "generalstore",
        "zippeestore", "gasstore", "fossoil", "restaurantkitchen" },
    water = { "kitchen", "grocery", "grocerystorage", "conveniencestore", "cornerstore", "gigamart", "generalstore",
        "zippeestore", "gasstore", "fossoil", "liquorstore" },
    medical = { "bathroom", "pharmacy", "pharmacystorage", "medicalstorage", "hospitalroom" },
    ammo = { "gunstore", "gunstorestorage", "policestorage", "armysurplus", "bedroom" },
    materials = { "garagestorage", "shed", "toolstore", "storageunit", "warehouse" },
}
-- Butin abstrait (hors écran seulement) : objets vanilla 42.21 par catégorie (bouteille remplie d'eau).
Ex.ABSTRACT_ITEMS = {
    food = { "Base.TinnedBeans", "Base.CannedCorn", "Base.TinnedSoup" },
    water = { "Base.WaterBottle" },
    medical = { "Base.Bandage", "Base.Pills" },
    ammo = { "Base.Bullets9mmBox", "Base.ShotgunShellsBox" },
    materials = { "Base.NailsBox", "Base.DuctTape" },
}

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche ; à recalibrer en jeu).
Ex.CFG = Ex.CFG or {
    TEAM_MAX = 2,              -- fourrageurs au plus par expédition
    TEAM_MIN = 1,
    MIN_HOME = 1,              -- membres vivants qui restent au foyer
    TEAM_HEALTH = 0.6,         -- santé (0..1) minimale pour partir
    DEPART_FROM = 7,           -- heure du jour : départ permis de 7 h
    DEPART_TO = 16,            -- ... à 16 h (exclue) : retour avant la nuit
    COOLDOWN_MINUTES = 240,    -- minutes de jeu entre la fin d'une expédition et le départ suivant
    CHECK_MINUTES = 10,        -- départ examiné au plus toutes les 10 minutes de jeu par groupe
    MIN_DIST = 6,              -- cases entre le foyer et le bâtiment visé (écart au rectangle)
    MAX_DIST = 45,             -- cases au plus (consigne move : Directives.MAX_TRIP = 60)
    MAX_BUILDINGS = 64,        -- bâtiments examinés au plus par départ
    MAX_CANDIDATES = 6,        -- bâtiments essayés (point visé chargé et libre) par départ
    SEEN_MAX = 8,              -- derniers bâtiments fouillés écartés
    ROOM_SCORE = 10,           -- points par catégorie promise (x rang du manque)
    DIST_WEIGHT = 0.5,         -- points retirés par case
    SPOT_RADIUS = 4,           -- cases : places libres autour du point visé
    SEARCH_RADIUS = 10,        -- cases autour du point visé : conteneurs fouillés
    MAX_CONTAINERS = 12,
    RUMMAGE_MINUTES = 2,       -- minutes de jeu de fouille par conteneur
    CLAIM_MINUTES = 15,        -- réservation rendue sans nouvelle de son membre
    CARRY_PER_MEMBER = 4,      -- objets portés par membre
    CARRY_MAX = 8,
    OUT_MINUTES = 120,         -- délais des phases (minutes de jeu)
    SEARCH_MINUTES = 60,
    BACK_MINUTES = 120,
    ABSTRACT_HOURS = { out = 3, search = 2, back = 1 },   -- heures hors écran restantes selon la phase quittée
    ABSTRACT_FIND = 0.5,       -- chance par membre et par catégorie manquante de rapporter un objet hors écran
}

Ex.state = Ex.state or { npcs = {}, claims = {}, sites = {}, carried = {}, checked = {} }
Ex.stats = Ex.stats or { departed = 0, refused = 0, arrived = 0, searched = 0, taken = 0, delivered = 0,
    deposited = 0, lost = 0, abstract = 0, resolved = 0, created = 0, dropped = 0, filled = 0 }

local M = 2147483647

local function log() return LivingKnox.Log end
local function cfg() return Ex.CFG end
local function Groups() return LivingKnox.Groups end
local function Stock() return LivingKnox.Stock end
local function Homes() return LivingKnox.Homes end
local function Decisions() return LivingKnox.Decisions end
local function X() return LivingKnox.Routines.exec end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function cut(s) return string.sub(s, 1, Groups().TEXT_MAX or 200) end

local function inList(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

local CATS = {}
for _, c in ipairs(LivingKnox.Stock.CATEGORIES) do CATS[c] = true end

-- ================================================================ registre (forme)

local function validStrList(list, max, pred)
    if type(list) ~= "table" then return false end
    local n = 0
    for k in pairs(list) do
        if not isInt(k, 1, max) then return false end
        n = n + 1
    end
    if n > 0 and list[n] == nil then return false end
    for i = 1, n do
        if not pred(list[i]) then return false end
    end
    return true
end

local function shortText(v) return type(v) == "string" and #v > 0 and #v <= 96 end

-- Expédition en cours bien formée. Rend vrai, ou faux et une raison.
function Ex.validCur(t)
    if type(t) ~= "table" then return false, "trip is not a table" end
    if not isInt(t.n, 1, M) or not Ex.PHASES[t.phase] then return false, "bad trip number or phase" end
    if not validStrList(t.team, Groups().MAX_MEMBERS, function(v) return Groups().memberNumber(v) ~= nil end) then
        return false, "bad team"
    end
    if not validStrList(t.want, #LivingKnox.Stock.CATEGORIES, function(w)
        return type(w) == "table" and CATS[w.c] == true and isInt(w.m, 0, 1000)
    end) then
        return false, "bad wants"
    end
    local tg = t.target
    if type(tg) ~= "table" or not isInt(tg.x, 0, M) or not isInt(tg.y, 0, M) or not isInt(tg.z, -32, 31)
        or not shortText(tg.b) then
        return false, "bad target"
    end
    if not isInt(t.start, 0, M) or not isInt(t.due, 0, M) or not isInt(t.cap, 0, 1000) then
        return false, "bad times or load"
    end
    if not validStrList(t.carry, 1000, function(e)
        return type(e) == "table" and type(e.t) == "string" and #e.t > 0 and #e.t <= 128 and CATS[e.c] == true
            and (e.i == nil or isInt(e.i, -2147483648, 2147483647)) and (e.a == nil or e.a == true)
            and (e.f == nil or e.f == true)
    end) then
        return false, "bad load"
    end
    if not validStrList(t.searched, 1000, shortText) then return false, "bad searched list" end
    if t.kind ~= nil and not Ex.DRAWN[t.kind] then return false, "unknown kind" end
    if Ex.DRAWN[t.kind] and (not isInt(t.k, 0, 1000) or not isInt(t.r, 0, 1000) or not shortText(tg.room)) then
        return false, "bad foraging rounds"
    end
    return true
end

-- Historique des expéditions bien formé. Rend vrai, ou faux et une raison.
function Ex.validTrips(s)
    if type(s) ~= "table" or s.v ~= Ex.FORMAT then return false, "unknown format" end
    if not isInt(s.n, 0, M) or (s.last ~= nil and not isInt(s.last, 0, M)) then return false, "bad counters" end
    if not validStrList(s.seen, cfg().SEEN_MAX, shortText) then return false, "bad seen list" end
    if s.cur ~= nil then return Ex.validCur(s.cur) end
    return true
end

-- Historique du groupe g (registre vivant) ; malformé : oublié (avertissement), expédition en cours abandonnée.
local function tripsOf(gid, g)
    local s = g.trips
    if s == nil then return nil end
    local ok, why = Ex.validTrips(s)
    if ok then return s end
    log().warn("expedition: group %s trip record dropped (%s)", gid, tostring(why))
    g.trips = nil
    return nil
end

local function liveGroup(gid)
    local G = Groups()
    local data = G.isReady() and G.state.data or nil
    return data and data.groups[gid] or nil
end

-- Expédition en cours (registre vivant) du groupe gid, ou nil.
local function curOf(gid)
    local g = liveGroup(gid)
    local s = g and g.trips or nil
    if type(s) ~= "table" or type(s.cur) ~= "table" then return nil end
    return s.cur, g
end

-- Expédition du membre mid (contexte du cadre de décision, LK_Decisions) : { n, phase } si une expédition en cours
-- le compte dans son équipe et le mène (out, search, back), sinon nil.
function Ex.memberTrip(gid, mid)
    local t = curOf(gid)
    if t == nil or not Ex.ACTIVE[t.phase] or not inList(t.team, mid) then return nil end
    return { n = t.n, phase = t.phase }
end

-- ================================================================ choix du lieu (métagrille, sans charger)

local CELL = 256

-- Bâtiments de la métagrille qui croisent le carré de rayon r autour de (x, y) : { BuildingDef }, triés par
-- identifiant (cellules couvertes seulement, comme LK_Sites).
function Ex.buildingsNear(x, y, r)
    local world = getWorld and getWorld() or nil
    local grid = world ~= nil and world.getMetaGrid ~= nil and world:getMetaGrid() or nil
    if grid == nil or ArrayList == nil then return {} end
    local x1, y1, x2, y2 = math.max(0, x - r), math.max(0, y - r), x + r + 1, y + r + 1
    local found = ArrayList.new()
    for cy = math.floor(y1 / CELL), math.floor((y2 - 1) / CELL) do
        for cx = math.floor(x1 / CELL), math.floor((x2 - 1) / CELL) do
            local cell = grid:getCellData(cx, cy)
            if cell then cell:getBuildingsIntersecting(x1, y1, x2 - x1, y2 - y1, found) end
        end
    end
    local out, seen = {}, {}
    for i = 0, found:size() - 1 do
        local b = found:get(i)
        local id = b:getIDString()
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = b
        end
    end
    table.sort(out, function(a, b) return a:getIDString() < b:getIDString() end)
    return out
end

-- Écart (cases) entre (x, y) et le rectangle [x1, x2[ x [y1, y2[ (0 dedans).
local function gapTo(x, y, x1, y1, x2, y2)
    local dx, dy = 0, 0
    if x < x1 then dx = x1 - x elseif x > x2 - 1 then dx = x - (x2 - 1) end
    if y < y1 then dy = y1 - y elseif y > y2 - 1 then dy = y - (y2 - 1) end
    return math.max(dx, dy)
end

-- Note d'une pièce pour les manques want ({ { c, m } }, ordre du manque) : somme de (rang inverse) x ROOM_SCORE des
-- catégories que son nom promet. Pur.
function Ex.roomScore(name, want)
    local n = #want
    local score = 0
    for i, w in ipairs(want) do
        if inList(Ex.ROOMS[w.c], name) then score = score + (n - i + 1) * cfg().ROOM_SCORE end
    end
    return score
end

-- Candidats (pur sur des descriptions) : list = { { id, x1, y1, x2, y2 (fin exclue), rooms = { { name, z, x1, y1,
-- x2, y2 } } } }, home = { x, y, z }, want, skip = { [id] = vrai }, homes = { { x, y } } (foyers des groupes : un
-- bâtiment qui en contient un est écarté). Rend les candidats triés (note décroissante, puis distance, puis
-- identifiant) : { id, d, score, room = { name, x, y } (centre de la meilleure pièce), label }.
function Ex.rank(list, home, want, skip, homes)
    local c = cfg()
    local out = {}
    for _, b in ipairs(list) do
        local d = gapTo(home.x, home.y, b.x1, b.y1, b.x2, b.y2)
        local lived = false
        for _, h in ipairs(homes or {}) do
            if gapTo(h.x, h.y, b.x1, b.y1, b.x2, b.y2) == 0 then lived = true end
        end
        if not skip[b.id] and not lived and d >= c.MIN_DIST and d <= c.MAX_DIST then
            local best, bestScore
            for _, r in ipairs(b.rooms) do
                if r.z == home.z and r.x2 > r.x1 and r.y2 > r.y1 then
                    local s = Ex.roomScore(r.name, want)
                    local area = (r.x2 - r.x1) * (r.y2 - r.y1)
                    if best == nil or s > bestScore or (s == bestScore and area > best.area) then
                        best, bestScore = { name = r.name, x = r.cx or math.floor((r.x1 + r.x2 - 1) / 2),
                            y = r.cy or math.floor((r.y1 + r.y2 - 1) / 2), area = area }, s
                    end
                end
            end
            if best ~= nil then
                out[#out + 1] = { id = b.id, d = d, score = bestScore - d * c.DIST_WEIGHT, room = best,
                    label = best.name .. " " .. best.x .. "," .. best.y }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.d ~= b.d then return a.d < b.d end
        return a.id < b.id
    end)
    return out
end

-- Description d'un BuildingDef pour Ex.rank. Centre de pièce = centre de son premier rectangle (RoomDef.RoomRect,
-- fin exclue, J/iso/RoomDef.java:482-496) : toujours dans la pièce, contrairement au centre de son emprise (pièce en
-- L, base world-placement.md).
local function describe(b)
    local rooms = {}
    local list = b:getRooms()
    for i = 0, list:size() - 1 do
        local r = list:get(i)
        local e = { name = string.lower(r:getName() or ""), z = r:getZ(), x1 = r:getX(), y1 = r:getY(),
            x2 = r:getX2(), y2 = r:getY2() }
        local rects = r:getRects()
        if rects ~= nil and rects:size() > 0 then
            local q = rects:get(0)
            e.cx, e.cy = math.floor((q:getX() + q:getX2() - 1) / 2), math.floor((q:getY() + q:getY2() - 1) / 2)
        end
        rooms[#rooms + 1] = e
    end
    return { id = b:getIDString(), x1 = b:getX(), y1 = b:getY(), x2 = b:getX2(), y2 = b:getY2(), rooms = rooms }
end

local function buildingIdAt(x, y, z)
    local sq = getCell():getGridSquare(x, y, z)
    if sq == nil then return nil, false end
    local def = sq:getBuildingDef()
    return def ~= nil and def:getIDString() or nil, true
end

-- Case libre du bâtiment bid la plus proche de (x, y, z), à radius cases au plus, la rank-ième (1 = la plus proche).
local function freeNear(x, y, z, bid, radius, rank)
    local B = LivingKnox.Bodies
    local cell = getCell()
    local n = 0
    for r = 0, radius do
        for _, d in ipairs(B.ring(r)) do
            local sq = cell:getGridSquare(x + d[1], y + d[2], z)
            if sq ~= nil and (bid == nil or X().buildingId(sq) == bid) and not sq:HasStairs() and B.freeSquare(sq) then
                n = n + 1
                if n >= (rank or 1) then return sq end
            end
        end
    end
    return nil
end

-- Bâtiments à écarter : foyer du groupe, foyers des autres groupes, derniers fouillés.
local function skipSet(g, data)
    local skip, homes = {}, {}
    for _, b in ipairs(type(g.trips) == "table" and g.trips.seen or {}) do skip[b] = true end
    local ids = {}
    for other in pairs(data.groups) do ids[#ids + 1] = other end
    table.sort(ids)
    for _, other in ipairs(ids) do
        local h = data.groups[other].home
        if type(h) == "table" then
            homes[#homes + 1] = { x = h.x, y = h.y }
            local bid = buildingIdAt(h.x, h.y, h.z)
            if bid ~= nil then skip[bid] = true end
        end
    end
    return skip, homes
end

-- Lieu d'une expédition du groupe gid (registre vivant g) pour les manques want : { x, y, z, b, room, label, d } ou
-- nil et une raison.
function Ex.pickTarget(gid, g, want, data)
    local home = g.home
    local c = cfg()
    local list = {}
    for i, b in ipairs(Ex.buildingsNear(home.x, home.y, c.MAX_DIST + 1)) do
        if i > c.MAX_BUILDINGS then break end
        local ok, d = pcall(describe, b)
        if ok then list[#list + 1] = d end
    end
    if #list == 0 then return nil, "no building near home" end
    local skip, homes = skipSet(g, data)
    local ranked = Ex.rank(list, home, want, skip, homes)
    if #ranked == 0 then return nil, "no building at " .. c.MIN_DIST .. ".." .. c.MAX_DIST .. " squares" end
    for i, cand in ipairs(ranked) do
        if i > c.MAX_CANDIDATES then break end
        local sq = freeNear(cand.room.x, cand.room.y, home.z, cand.id, c.SPOT_RADIUS, 1)
        if sq ~= nil then
            return { x = sq:getX(), y = sq:getY(), z = home.z, b = cand.id, room = cand.room.name, label = cand.label,
                d = cand.d, score = cand.score }
        end
    end
    return nil, "no loaded free square in the " .. math.min(#ranked, c.MAX_CANDIDATES) .. " best building(s)"
end

-- ================================================================ départ

local function hourOfDay(minute) return (math.floor(minute / 60) + 7) % 24 end

-- Vrai si l'heure du jour hod permet tout départ (DEPART_FROM..DEPART_TO).
function Ex.dayHour(hod) return hod >= cfg().DEPART_FROM and hod < cfg().DEPART_TO end

-- LK05-T11 : vrai si l'heure du jour hod est une heure de pêche (aube, crépuscule : LivingKnox.Food.fishHour).
local function fishHour(hod)
    local F = LivingKnox.Food
    return F ~= nil and F.fishHour ~= nil and F.fishHour(hod) == true
end

local function isEmbodied(m)
    local Si = LivingKnox.Simulation
    return Si ~= nil and Si.isEmbodied ~= nil and Si.isEmbodied(m)
end

local function bodyAtHome(m, home)
    local z = LivingKnox.Bodies.find(m.npc)
    if z == nil then return false end
    return math.floor(z:getZ()) == home.z and cheb(z:getX(), z:getY(), home.x + 0.5, home.y + 0.5)
        <= Decisions().CFG.HOME_RADIUS
end

-- Besoins qui retiennent un membre au foyer (LK05-T15) : rend la raison, ou nil s'il peut partir. want = manques de
-- l'expédition ({ { c, m } }) : faim élevée admise si la nourriture est cherchée, soif élevée si l'eau l'est.
local NEED_ANSWERED_BY = { hunger = "food", thirst = "water" }
function Ex.needBlocker(needs, want)
    local sought = {}
    for _, w in ipairs(want or {}) do sought[w.c] = true end
    for _, key in ipairs({ "fear", "fatigue", "hunger", "thirst" }) do
        local v, lim = needs and needs[key] or 0, Decisions().needHigh(key)   -- LK05-T16 : peur = AfraidFear
        if lim ~= nil and v >= lim then
            local cat = NEED_ANSWERED_BY[key]
            if cat == nil or not sought[cat] then return key .. " " .. v end
        end
    end
    return nil
end

-- Équipe (pur sur le registre vivant) : fourrageurs vivants, incarnés, au foyer, hors chef, assez valides, sans
-- besoin élevé que l'expédition ne comble pas (gid et want donnés : Ex.needBlocker). Rend la liste triée par numéro
-- et le nombre de vivants présents au foyer.
function Ex.teamOf(g, gid, want)
    local G, c = Groups(), cfg()
    local mids, present = {}, 0
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then
            present = present + 1
            if m.duty == "forager" and mid ~= g.leader and m.npc ~= nil and isEmbodied(m)
                and Decisions().healthOf(m) >= c.TEAM_HEALTH and bodyAtHome(m, g.home)
                and (gid == nil or Ex.needBlocker(Decisions().needsOf(gid, mid), want) == nil) then
                mids[#mids + 1] = mid
            end
        end
    end
    table.sort(mids, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
    local n = math.min(c.TEAM_MAX, #mids, present - c.MIN_HOME)
    local team = {}
    -- E10-T03 : gid donné, chaque partant est jugé (Decisions.judgeOrder) : un refus le laisse au foyer, le suivant part.
    local D = Decisions()
    local minute = gid ~= nil and D.judgeOrder ~= nil and D.currentMinute() or nil
    for _, mid in ipairs(mids) do
        if #team >= n then break end
        if minute == nil or D.judgeOrder(gid, g, mid, g.members[mid], "expedition", "expedition", minute) == nil then
            team[#team + 1] = mid
        end
    end
    return team, present
end

-- Raison pour laquelle le groupe ne part pas (ou nil : il peut partir), sans lire le monde.
function Ex.departBlocker(g, minute)
    local c = cfg()
    if type(g.home) ~= "table" then return "no home" end
    if g.objective ~= "supply" then return "objective " .. tostring(g.objective) end
    if g.expedition ~= nil then return "offscreen expedition under way" end
    local s = g.trips
    if type(s) == "table" and s.cur ~= nil then return "expedition under way" end
    if type(s) == "table" and s.last ~= nil and minute - s.last < c.COOLDOWN_MINUTES and minute >= s.last then
        return "rested less than " .. c.COOLDOWN_MINUTES .. " minutes"
    end
    local hod = hourOfDay(minute)
    if not Ex.dayHour(hod) and not fishHour(hod) then return "hour of day " .. hod end
    return nil
end

-- Manques du stock (Stock.needs) : { { c, m } } dans l'ordre du manque, ou nil et une raison.
function Ex.wantOf(gid)
    local a, why = Stock().needs(gid)
    if a == nil then return nil, why end
    local want = {}
    for _, nd in ipairs(a.needs) do
        if CATS[nd.c] and nd.missing > 0 then want[#want + 1] = { c = nd.c, m = nd.missing } end
    end
    if #want == 0 then return nil, "nothing missing" end
    return want
end

local function wantText(want)
    local parts = {}
    for _, w in ipairs(want) do parts[#parts + 1] = w.c .. " " .. w.m end
    return table.concat(parts, ", ")
end

-- Départ éventuel du groupe gid à la minute minute. Rend le numéro de l'expédition partie, ou nil et une raison.
function Ex.tryDepart(gid, minute)
    local g = liveGroup(gid)
    if g == nil then return nil, "unknown group" end
    tripsOf(gid, g)
    local why = Ex.departBlocker(g, minute)
    if why ~= nil then return nil, why end
    if not Decisions().materialized(g, LivingKnox.Store.isReady() and LivingKnox.Store.data() or nil) then
        return nil, "not materialized"
    end
    local want, wwhy = Ex.wantOf(gid)
    if want == nil then return nil, wwhy end
    local team = Ex.teamOf(g, gid, want)
    if #team < cfg().TEAM_MIN then return nil, "no forager free to leave" end
    local data = Groups().state.data
    -- LK05-T11 : la nourriture manque le plus et une zone de cueillette proche en rapporte à cette saison.
    local F = LivingKnox.Food
    local target, twhy, kind
    local hod = hourOfDay(minute)
    -- LK05-T11 : à l'aube et au crépuscule, une sortie de pêche si la nourriture manque le plus et qu'une rive est
    -- à portée ; hors des heures de jour, rien d'autre.
    if fishHour(hod) and F ~= nil and F.wanted ~= nil and F.wanted(want) and F.fishTarget ~= nil then
        local ok, tg, fwhy = pcall(F.fishTarget, gid, g)
        if not ok then
            log().error("expedition: group %s fishing place failed: %s", gid, tostring(tg))
        elseif tg ~= nil then
            target, kind = tg, Ex.FISH
            want = { { c = "food", m = want[1].m } }
        else
            twhy = "no fishing: " .. tostring(fwhy)
            log().debug("expedition: group %s does not fish: %s", gid, tostring(fwhy))
        end
    end
    if target == nil and not Ex.dayHour(hod) then
        return nil, "hour of day " .. hod .. (twhy ~= nil and (" (" .. twhy .. ")") or "")
    end
    if target == nil and F ~= nil and F.wanted ~= nil and F.wanted(want) then
        local ok, tg, fwhy = pcall(F.pickTarget, gid, g)
        if not ok then
            log().error("expedition: group %s foraging place failed: %s", gid, tostring(tg))
        elseif tg ~= nil then
            target, kind = tg, Ex.FORAGE
            want = { { c = "food", m = want[1].m } }
        else
            log().debug("expedition: group %s does not forage: %s", gid, tostring(fwhy))
        end
    end
    if target == nil then target, twhy = Ex.pickTarget(gid, g, want, data) end
    if target == nil then
        Ex.stats.refused = Ex.stats.refused + 1
        return nil, twhy
    end
    local c = cfg()
    local missing = 0
    for _, w in ipairs(want) do missing = missing + w.m end
    local cap = math.min(c.CARRY_PER_MEMBER * #team, c.CARRY_MAX, missing)
    local n
    local G = Groups()
    G.update(function(d)
        local live = d.groups[gid]
        if live == nil then return false, false end
        local s = live.trips
        if type(s) ~= "table" then s = { v = Ex.FORMAT, n = 0, seen = {} } end
        s.n = s.n + 1
        n = s.n
        s.cur = { n = n, phase = "out", team = team, want = want,
            target = { x = target.x, y = target.y, z = target.z, b = target.b, room = target.room,
                label = target.label }, start = minute, due = minute + c.OUT_MINUTES, cap = cap, carry = {},
            searched = {} }
        if kind == Ex.FORAGE then
            local zn = target.zone
            s.cur.kind, s.cur.k, s.cur.r = kind, 0, #team * F.CFG.ROUNDS
            s.cur.target.zone = { x = zn.x, y = zn.y, w = zn.w, h = zn.h }
        elseif kind == Ex.FISH then
            s.cur.kind, s.cur.k, s.cur.r = kind, 0, #team * F.CFG.FISH_ROUNDS
        end
        live.trips = s
        G.appendLog(live, "expedition", cut(string.format("trip %d to %s (%d squares): %s for %s", n, target.label,
            target.d, table.concat(team, " "), wantText(want))), G.today())
        return true, true
    end)
    Ex.stats.departed = Ex.stats.departed + 1
    log().info("expedition: group %s trip %d leaves for building %s %s at %d,%d,%d (%d squares, score %.1f): %s, "
        .. "wants %s, load %d", gid, n, target.b, target.label, target.x, target.y, target.z, target.d, target.score,
        table.concat(team, " "), wantText(want), cap)
    return n
end

-- ================================================================ phases (registre)

local function setPhase(gid, n, phase, minute, why)
    local c = cfg()
    local span = { search = c.SEARCH_MINUTES, back = c.BACK_MINUTES, deliver = 0 }
    Groups().update(function(d)
        local g = d.groups[gid]
        local t = g and g.trips and g.trips.cur or nil
        if t == nil or t.n ~= n or t.phase == phase then return false, false end
        t.phase = phase
        t.due = minute + (span[phase] or 0)
        return true, true
    end)
    log().info("expedition: group %s trip %d %s (%s)", gid, n, phase, tostring(why))
end

local function memOf(id, gid, n, mid)
    local mem = Ex.state.npcs
    local m = mem[id]
    if m == nil or m.n ~= n or m.gid ~= gid then
        m = { gid = gid, n = n, mid = mid, fails = 0 }
        mem[id] = m
    end
    return m
end

local function resetSteps(m)
    m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
    m.faced = nil   -- pêche (LK05-T11) : de nouveau tourné vers l'eau après une interruption
end

local function standUp(id)
    local A = LivingKnox.Anim
    if A ~= nil and (A.gestureOf(id) == Ex.GESTURE or A.gestureOf(id) == Ex.FORAGE_GESTURE) then
        A.setGesture(id, A.DEFAULT)
    end
end

local function claimsOf(gid, n)
    local key = gid .. "#" .. n
    Ex.state.claims[key] = Ex.state.claims[key] or {}
    return Ex.state.claims[key]
end

-- Conteneurs du bâtiment visé (mémoire, relevés à la première demande) : { { key, x, y, z, place } } du plus proche
-- au plus loin du point visé (cases non chargées ignorées ; relevé gardé pour toute l'expédition).
function Ex.siteContainers(gid, t)
    local key = gid .. "#" .. t.n
    local cached = Ex.state.sites[key]
    if cached ~= nil then return cached end
    local cell = getCell()
    local tg = t.target
    local R = cfg().SEARCH_RADIUS
    local found = {}
    for dy = -R, R do
        for dx = -R, R do
            local x, y = tg.x + dx, tg.y + dy
            local sq = cell:getGridSquare(x, y, tg.z)
            if sq ~= nil and X().buildingId(sq) == tg.b then
                local objs = sq:getObjects()
                local seen = {}
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if o ~= nil and o.getContainerCount ~= nil and not instanceof(o, "IsoWorldInventoryObject") then
                        for ci = 0, o:getContainerCount() - 1 do
                            local ct = o:getContainerByIndex(ci)
                            if ct ~= nil then
                                local ctype = tostring(ct:getType())
                                local k = (seen[ctype] or 0) + 1
                                seen[ctype] = k
                                found[#found + 1] = { key = x .. "," .. y .. "," .. tg.z .. "," .. ctype .. "," .. k,
                                    x = x, y = y, z = tg.z, d = cheb(x, y, tg.x, tg.y) }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    local out, used = {}, {}
    for _, f in ipairs(found) do
        if #out >= cfg().MAX_CONTAINERS then break end
        local p = X().placeBeside(cell, f.x, f.y, f.z, tg.b, used)
        f.place = p
        out[#out + 1] = f
    end
    Ex.state.sites[key] = out
    log().info("expedition: group %s trip %d: %d container(s) to search in building %s", gid, t.n, #out, tg.b)
    return out
end

-- Conteneur de clé key sur sa case (relu maintenant) : conteneur et objet porteur, ou nil.
local function containerAt(f)
    local sq = getCell():getGridSquare(f.x, f.y, f.z)
    if sq == nil then return nil end
    local objs = sq:getObjects()
    local seen = {}
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o ~= nil and o.getContainerCount ~= nil and not instanceof(o, "IsoWorldInventoryObject") then
            for ci = 0, o:getContainerCount() - 1 do
                local ct = o:getContainerByIndex(ci)
                if ct ~= nil then
                    local ctype = tostring(ct:getType())
                    local k = (seen[ctype] or 0) + 1
                    seen[ctype] = k
                    if f.x .. "," .. f.y .. "," .. f.z .. "," .. ctype .. "," .. k == f.key then return ct, o end
                end
            end
        end
    end
    return nil
end

local function remaining(t)
    local left, wanted = 0, {}
    for _, w in ipairs(t.want) do
        wanted[w.c] = w.m
        left = left + w.m
    end
    return left, wanted
end

-- Prochain conteneur libre pour le PNJ id : ni fouillé, ni réservé par un autre membre (réservation récente).
local function claimNext(gid, t, id, minute)
    local list = Ex.siteContainers(gid, t)
    local claims = claimsOf(gid, t.n)
    for key, cl in pairs(claims) do
        if cl.id == id then claims[key] = nil end
    end
    for _, f in ipairs(list) do
        local cl = claims[f.key]
        local stale = cl ~= nil and minute - cl.minute > cfg().CLAIM_MINUTES
        if not inList(t.searched, f.key) and (cl == nil or stale) then
            claims[f.key] = { id = id, minute = minute }
            return f
        end
    end
    return nil, "none"
end

-- Fin de la fouille ? Rend vrai et la raison si l'expédition doit rentrer.
function Ex.searchDone(gid, t, minute)
    local left = remaining(t)
    if left <= 0 then return true, "wants covered" end
    if #t.carry >= t.cap then return true, "load full" end
    if minute >= t.due then return true, "search time over" end
    for _, f in ipairs(Ex.siteContainers(gid, t)) do
        if not inList(t.searched, f.key) then return false end
    end
    return true, "nothing left to search"
end

local function carriedOf(gid, n)
    local key = gid .. "#" .. n
    Ex.state.carried[key] = Ex.state.carried[key] or {}
    return Ex.state.carried[key]
end

-- Fouille du conteneur f par le PNJ id (membre mid) : butin vanilla tiré si jamais ouvert, objets manquants pris
-- (catégorie, consommable, manque, charge), retirés du conteneur et des clients. Conteneur marqué fouillé, objets
-- portés écrits au registre dans la même écriture. Rend le nombre d'objets pris.
function Ex.searchContainer(gid, n, f, id, mid)
    local ct, obj = containerAt(f)
    local taken, entries = {}, {}
    local t = curOf(gid)
    if t == nil or t.n ~= n then return 0 end
    if ct ~= nil then
        if ct.isExplored ~= nil and not ct:isExplored() then
            -- Premier regard sur ce conteneur : butin vanilla comme à l'ouverture par un joueur.
            if ItemPickerJava ~= nil and ItemPickerJava.fillContainer ~= nil then
                ItemPickerJava.fillContainer(ct, nil)
                Ex.stats.filled = Ex.stats.filled + 1
            end
            ct:setExplored(true)
            if isServer() and obj ~= nil and sendItemsInContainer ~= nil then sendItemsInContainer(obj, ct) end
        end
        local _, wanted = remaining(t)
        local room = t.cap - #t.carry
        local items = ct:getItems()
        local picks = {}
        for j = 0, items:size() - 1 do
            if #picks >= room then break end
            local it = items:get(j)
            local cat = it ~= nil and Stock().categoryOf(it) or nil
            if cat ~= nil and (wanted[cat] or 0) > 0
                and ((cat ~= "food" and cat ~= "water") or Stock().consumable(it, cat)) then
                wanted[cat] = wanted[cat] - 1
                picks[#picks + 1] = { it = it, c = cat }
            end
        end
        local carried = carriedOf(gid, n)
        for _, p in ipairs(picks) do
            ct:DoRemoveItem(p.it)
            if isServer() then sendRemoveItemFromContainer(ct, p.it) end
            local i = p.it:getID()
            carried[i] = p.it
            taken[#taken + 1] = p.it:getFullType()
            entries[#entries + 1] = { t = p.it:getFullType(), c = p.c, i = i }
        end
    end
    local G = Groups()
    G.update(function(d)
        local g = d.groups[gid]
        local cur = g and g.trips and g.trips.cur or nil
        if cur == nil or cur.n ~= n then return false, false end
        if not inList(cur.searched, f.key) and #cur.searched < 1000 then cur.searched[#cur.searched + 1] = f.key end
        for _, e in ipairs(entries) do
            cur.carry[#cur.carry + 1] = e
            for _, w in ipairs(cur.want) do
                if w.c == e.c and w.m > 0 then
                    w.m = w.m - 1
                    break
                end
            end
        end
        return true, true
    end)
    Ex.stats.searched = Ex.stats.searched + 1
    Ex.stats.taken = Ex.stats.taken + #entries
    log().info("expedition: group %s trip %d: %s (%s) searched %s%s: %s", gid, n, tostring(mid), tostring(id), f.key,
        ct == nil and " (gone)" or "", #taken > 0 and table.concat(taken, " ") or "nothing taken")
    return #entries
end

-- ================================================================ exécution (comportement « expedition »)

-- Case de retour au foyer (comme LK_Decisions : case libre près du foyer).
local function homeSpot(home, rank)
    local sq, bid = LivingKnox.Materialize.homeSquare(home)
    if sq == nil then return home.x, home.y, home.z end
    local place = freeNear(home.x, home.y, home.z, bid, Decisions().CFG.HOME_PLACE_RADIUS, rank)
    if place == nil then return home.x, home.y, home.z end
    return place:getX(), place:getY(), place:getZ()
end

local function rankIn(list, v)
    for i, x in ipairs(list) do
        if x == v then return i end
    end
    return 1
end

-- Conteneur écarté sans fouille (hors d'atteinte) : marqué fouillé, réservation rendue, rien n'est pris.
local function skipContainer(gid, n, f, id, why)
    log().info("expedition: group %s trip %d: npc %s skips %s (%s)", gid, n, tostring(id), f.key, why)
    Groups().update(function(d)
        local cur = d.groups[gid] and d.groups[gid].trips and d.groups[gid].trips.cur
        if cur == nil or cur.n ~= n or inList(cur.searched, f.key) then return false, false end
        cur.searched[#cur.searched + 1] = f.key
        return true, true
    end)
    claimsOf(gid, n)[f.key] = nil
end

local function search(id, ctx, t, m, e)
    local minute = ctx.minute
    if m.job == nil then
        local f = claimNext(ctx.gid, t, id, minute)
        if f == nil then
            standUp(id)
            local done, why = Ex.searchDone(ctx.gid, t, minute)
            if done then setPhase(ctx.gid, t.n, "back", minute, why) end
            return
        end
        if f.place == nil then
            skipContainer(ctx.gid, t.n, f, id, "no free square beside it")   -- hors d'atteinte : rien n'est pris
            return
        end
        m.job = f
        resetSteps(m)
    end
    local f = m.job
    local claims = claimsOf(ctx.gid, t.n)
    if claims[f.key] ~= nil and claims[f.key].id == id then claims[f.key].minute = minute end
    local res = X().goTo(id, ctx, f.place.x, f.place.y, f.place.z, m, e)
    if res == "moving" then return end
    if res == "failed" then
        skipContainer(ctx.gid, t.n, f, id, "cannot reach it")
        m.job = nil
        return
    end
    if m.faceV == nil then
        X().faceTo(id, m, f.place.a)
        return
    end
    if m.since == nil then
        local entry = X().entryOf(id)
        if entry == nil or entry.v ~= m.faceV or not entry.done then return end
        X().sitDown(id, m, Ex.GESTURE)
        m.since = minute
        return
    end
    if minute - m.since < cfg().RUMMAGE_MINUTES then return end
    Ex.searchContainer(ctx.gid, t.n, f, id, ctx.mid)
    claims[f.key] = nil
    m.job, m.since = nil, nil
    standUp(id)
    local cur = curOf(ctx.gid)
    if cur ~= nil and cur.n == t.n then
        local done, why = Ex.searchDone(ctx.gid, cur, minute)
        if done then setPhase(ctx.gid, t.n, "back", minute, why) end
    end
end

-- ================================================================ cueillette (LK05-T11)

-- Fin de la cueillette ? Rend vrai et la raison si l'équipe doit rentrer.
function Ex.forageDone(t, minute)
    local left = remaining(t)
    if left <= 0 then return true, "wants covered" end
    if #t.carry >= t.cap then return true, "load full" end
    if (t.k or 0) >= (t.r or 0) then return true, "foraging done" end
    if minute >= t.due then return true, "search time over" end
    return false
end

local function addFinds(cur, entries)
    for _, e in ipairs(entries) do
        if #cur.carry >= cur.cap then break end
        cur.carry[#cur.carry + 1] = e
        for _, w in ipairs(cur.want) do
            if w.c == e.c and w.m > 0 then
                w.m = w.m - 1
                break
            end
        end
    end
end

-- Tirage k d'une expédition à tirages t (cueillette : tables vanilla de la zone aux conditions c ; pêche : tables
-- du filet vanilla) : entrées à noter et texte.
local function drawRound(F, gid, t, k, c)
    if t.kind == Ex.FISH then return F.fishRound(gid, t.n, k, t.cap - #t.carry) end
    return F.round(gid, t.n, k, t.target.room, c, t.cap - #t.carry)
end

-- Tirage suivant de la cueillette (ou de la pêche, LK05-T11) n du groupe gid (membre mid) : tables vanilla de la
-- zone, conditions du moment ; objets notés à créer au dépôt. Rend le nombre d'objets notés.
function Ex.forageRound(gid, n, mid)
    local F = LivingKnox.Food
    local t = curOf(gid)
    if F == nil or t == nil or t.n ~= n or not Ex.DRAWN[t.kind] or (t.k or 0) >= (t.r or 0) or #t.carry >= t.cap then
        return 0
    end
    local k = (t.k or 0) + 1
    local c = F.conditions()
    local entries, text = drawRound(F, gid, t, k, c)
    local added = 0
    Groups().update(function(d)
        local g = d.groups[gid]
        local cur = g and g.trips and g.trips.cur or nil
        if cur == nil or cur.n ~= n or cur.kind ~= t.kind or (cur.k or 0) >= k then return false, false end
        cur.k = k
        local before = #cur.carry
        addFinds(cur, entries)
        added = #cur.carry - before
        return true, true
    end)
    Ex.stats.taken = Ex.stats.taken + added
    log().info("expedition: group %s trip %d: %s %s (draw %d of %d, %s%s): %s", gid, n, tostring(mid),
        t.kind == Ex.FISH and "fishes" or "forages", k, t.r or 0, tostring(t.target.room),
        t.kind == Ex.FISH and "" or (", " .. F.conditionText(c)), text)
    return added
end

-- Cueillette d'un membre arrivé : à sa place (retour après une interruption), geste, un tirage toutes les
-- ROUND_MINUTES minutes de jeu.
local function forage(id, ctx, t, m, e)
    local minute = ctx.minute
    local A = LivingKnox.Anim
    if m.spot ~= nil and not m.stay then
        local res = X().goTo(id, ctx, m.spot.x, m.spot.y, m.spot.z, m, e)
        if res == "moving" then
            m.since = nil
            return
        end
        if res == "failed" then m.stay = true end   -- place hors d'atteinte : il cueille là où il est
    end
    if m.spot ~= nil and m.spot.a ~= nil and not m.faced and not m.stay then
        -- Pêche : tourné vers l'eau d'abord (comme la fouille : consigne de regard puis attente de sa fin).
        if m.faceV == nil then
            X().faceTo(id, m, m.spot.a)
            return
        end
        local entry = X().entryOf(id)
        if entry == nil or entry.v ~= m.faceV or not entry.done then return end
        m.faced = true
    end
    if m.since == nil then
        X().sitDown(id, m, Ex.FORAGE_GESTURE)
        m.since = minute
        return
    end
    if A ~= nil and A.gestureOf(id) ~= Ex.FORAGE_GESTURE then X().sitDown(id, m, Ex.FORAGE_GESTURE) end
    local F = LivingKnox.Food
    if minute - m.since < (t.kind == Ex.FISH and F.CFG.FISH_MINUTES or F.CFG.ROUND_MINUTES) then return end
    m.since = minute
    Ex.forageRound(ctx.gid, t.n, ctx.mid)
    local cur = curOf(ctx.gid)
    if cur ~= nil and cur.n == t.n then
        local done, why = Ex.forageDone(cur, minute)
        if done then setPhase(ctx.gid, t.n, "back", minute, why) end
    end
end

-- Place d'un membre à l'arrivée : case libre près du point visé (bâtiment visé, ou zone de cueillette hors bâtiment).
local function spotFor(t, rank)
    local tg = t.target
    local F = LivingKnox.Food
    if t.kind == Ex.FISH and F ~= nil then
        -- Rive libre la plus proche de la rive visée, une par rang ; angle vers l'eau voisine.
        local sq, wx, wy = F.shoreSpot(tg.x, tg.y, tg.z, F.CFG.SHORE_RADIUS, rank)
        if sq == nil then return nil end
        local D = Decisions()
        local a = D ~= nil and D.angleTo ~= nil and D.angleTo(wx - sq:getX(), wy - sq:getY()) or nil
        return sq, a
    end
    if t.kind == Ex.FORAGE and F ~= nil then
        local zn = type(tg.zone) == "table" and tg.zone or { x = tg.x - 2, y = tg.y - 2, w = 5, h = 5 }
        return F.spotIn(zn, tg.x, tg.y, tg.z, F.CFG.SPOT_RADIUS, rank)
    end
    return freeNear(tg.x, tg.y, tg.z, tg.b, cfg().SPOT_RADIUS, rank)
end

-- Vrai si un membre de l'équipe de l'expédition t du groupe gid est arrivé au lieu (mémoire de cette session).
function Ex.anyArrived(gid, t)
    for _, m in pairs(Ex.state.npcs) do
        if m.gid == gid and m.n == t.n and m.arrived and inList(t.team, m.mid) then return true end
    end
    return false
end

-- Applique l'expédition au membre (contexte ctx du cadre de décision), à chaque passage.
function Ex.apply(id, st, ctx, fresh)
    local t = curOf(ctx.gid)
    if t == nil or not Ex.ACTIVE[t.phase] or not inList(t.team, ctx.mid) then return end
    local m = memOf(id, ctx.gid, t.n, ctx.mid)
    local e = X().entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) then
        -- Une autre consigne est passée entre-temps (menace, suite de test) : l'étape en cours reprend.
        resetSteps(m)
        m.since = nil
    end
    if m.phase ~= t.phase then
        if m.phase == "search" then
            standUp(id)
            m.job, m.since = nil, nil
        end
        if t.phase == "back" then resetSteps(m) end   -- un trajet vers le lieu en cours ne repart pas pour rien
        m.phase = t.phase
    end
    if t.phase == "out" or (t.phase == "search" and not m.arrived) then
        if m.spot == nil then
            local tg = t.target
            local sq, a = spotFor(t, rankIn(t.team, ctx.mid))
            m.spot = sq ~= nil and { x = sq:getX(), y = sq:getY(), z = sq:getZ(), a = a } or { x = tg.x, y = tg.y, z = tg.z }
        end
        local res = X().goTo(id, ctx, m.spot.x, m.spot.y, m.spot.z, m, e)
        if res == "moving" then return end
        m.arrived = true
        resetSteps(m)
        e = X().entryOf(id)
        Ex.stats.arrived = Ex.stats.arrived + 1
        log().info("expedition: npc %s (%s %s) %s building %s", id, ctx.gid, ctx.mid,
            res == "failed" and "gave up reaching" or "reached", t.target.b)
        if t.phase == "out" then setPhase(ctx.gid, t.n, "search", ctx.minute, ctx.mid .. " arrived") end
        t = curOf(ctx.gid)
        if t == nil then return end
        m.phase = t.phase
    end
    if t.phase == "search" then
        if Ex.DRAWN[t.kind] then forage(id, ctx, t, m, e) else search(id, ctx, t, m, e) end
        return
    end
    if t.phase == "back" then
        -- Dépôt ouvert par un membre qui a été au lieu (il porte le butin) ; mémoire perdue (redémarrage) : le premier.
        if ctx.atHome and (m.arrived or not Ex.anyArrived(ctx.gid, t)) then
            standUp(id)
            setPhase(ctx.gid, t.n, "deliver", ctx.minute, ctx.mid .. " back home")
            Ex.deliver(ctx.gid)
            return
        end
        if m.home == nil then
            local x, y, z = homeSpot(ctx.home, rankIn(t.team, ctx.mid))
            m.home = { x = x, y = y, z = z }
        end
        X().goTo(id, ctx, m.home.x, m.home.y, m.home.z, m, e)
    end
end

-- ================================================================ dépôt au foyer

-- Conteneur de dépôt du foyer : conteneur posé par LK_Homes (caisse, tente), sinon le premier (ordre des clés) ; ou
-- nil et une raison.
local function depotOf(gid, g)
    if not Stock().validRef(g.stock, g.home) then return nil, "no stock reference" end
    local style, def = Homes().ready(g.home)
    if style == nil then return nil, def end
    local list, why = Stock().containers(gid, g.home, style, def ~= nil and def:getIDString() or nil)
    if list == nil then return nil, why end
    for _, ct in ipairs(list) do
        if ct.owned then return ct end
    end
    if #list > 0 then return list[1] end
    return nil, "no container at home"
end

local function makeAbstract(e)
    local item = instanceItem(e.t)
    if item == nil then return nil end
    local fc = item:getFluidContainer()
    if e.c == "water" and fc ~= nil and Fluid ~= nil and Fluid.Water ~= nil then
        fc:Empty()
        fc:addFluid(Fluid.Water, fc:getCapacity())
    end
    return item
end

-- Dépôt des objets portés par l'expédition du groupe gid (phase deliver) quand la zone du foyer est lisible ;
-- clôture de l'expédition (journal « return »), référence du stock à jour dans la même écriture. Rend vrai si fait.
function Ex.deliver(gid)
    local t, g = curOf(gid)
    if t == nil or t.phase ~= "deliver" then return false end
    local depot, why = depotOf(gid, g)
    if depot == nil then
        local key = gid .. "#" .. t.n
        if Ex.state.checked[key] ~= why then
            Ex.state.checked[key] = why
            log().info("expedition: group %s trip %d waits to unload: %s", gid, t.n, tostring(why))
        end
        return false
    end
    local carried = carriedOf(gid, t.n)
    local refs, counts, lost, created, poisoned = {}, {}, 0, 0, 0
    local F = LivingKnox.Food
    for _, e in ipairs(t.carry) do
        local items, bad = {}, 0
        if e.a and e.f and F ~= nil then
            -- Cueillette ou pêche (LK05-T11) : objet tiré des tables vanilla, créé maintenant avec ses fonctions
            -- d'apparition (cueillette : graines comprises ; pêche : aucune) ; un objet empoisonné est jeté.
            local ok, list, nbad = pcall(F.make, e.t)
            if ok then
                items, bad = list, nbad or 0
            else
                log().error("expedition: group %s trip %d: %s not made: %s", gid, t.n, e.t, tostring(list))
            end
            created = created + #items
            poisoned = poisoned + bad
        elseif e.a then
            local ok, it = pcall(makeAbstract, e)
            if ok and it ~= nil then
                items[1] = it
                created = created + 1
            end
        elseif e.i ~= nil and carried[e.i] ~= nil then
            items[1] = carried[e.i]
        end
        if #items == 0 and bad == 0 then lost = lost + 1 end
        for _, item in ipairs(items) do
            depot.container:AddItem(item)
            if isServer() then sendAddItemToContainer(depot.container, item) end
            local cat = Stock().categoryOf(item)
            if cat == nil and not e.f then cat = e.c end   -- objet d'une cueillette hors catégories (graines) : non suivi
            if cat ~= nil then refs[#refs + 1] = { i = item:getID(), t = item:getFullType(), c = cat, k = depot.key } end
            if not e.f or item:getFullType() == e.t then counts[e.c] = (counts[e.c] or 0) + 1 end
        end
    end
    local G = Groups()
    local minute = Decisions().currentMinute() or t.start
    local parts = {}
    for _, c in ipairs(LivingKnox.Stock.CATEGORIES) do
        if counts[c] then parts[#parts + 1] = c .. " +" .. counts[c] end
    end
    local text = string.format("trip %d back from %s: %d back, %s%s%s", t.n, tostring(t.target.label), #t.team,
        #parts > 0 and table.concat(parts, " ") or "nothing found", lost > 0 and (", " .. lost .. " lost") or "",
        poisoned > 0 and (", " .. poisoned .. " poisoned thrown away") or "")
    G.update(function(d)
        local live = d.groups[gid]
        local s = live and live.trips or nil
        if s == nil or s.cur == nil or s.cur.n ~= t.n then return false, false end
        if type(live.home) == "table" and Stock().validRef(live.stock, live.home) then
            local have = {}
            for _, e in ipairs(live.stock.items) do have[e.i] = true end
            for _, r in ipairs(refs) do
                if not have[r.i] and #live.stock.items < Stock().MAX_ITEMS then
                    live.stock.items[#live.stock.items + 1] = r
                end
            end
        end
        s.cur = nil
        s.last = minute
        local seen = s.seen
        if t.kind == nil and not inList(seen, t.target.b) then seen[#seen + 1] = t.target.b end
        while #seen > cfg().SEEN_MAX do table.remove(seen, 1) end
        G.appendLog(live, "return", cut(text), G.today())
        return true, true
    end)
    Ex.state.carried[gid .. "#" .. t.n] = nil
    Ex.state.claims[gid .. "#" .. t.n] = nil
    Ex.state.sites[gid .. "#" .. t.n] = nil
    Ex.stats.delivered = Ex.stats.delivered + 1
    Ex.stats.deposited = Ex.stats.deposited + #refs
    Ex.stats.lost = Ex.stats.lost + lost
    Ex.stats.created = Ex.stats.created + created
    log().info("expedition: group %s %s (into %s%s)", gid, text, depot.key,
        created > 0 and (", " .. created .. " found offscreen") or "")
    Stock().updateRation(gid)
    return true
end

-- ================================================================ hors écran (LK09)

-- Bascule de l'expédition en cours du groupe g (registre vivant, dans une écriture) en expédition abstraite.
local function toAbstract(gid, g, t, team, hour, why)
    local hours = cfg().ABSTRACT_HOURS[t.phase] or 1
    g.expedition = { place = Ex.PLACE, team = team, departed = hour, returns = hour + hours, trip = t.n }
    t.from = t.phase
    t.phase = "away"
    t.team = team
    local G = Groups()
    G.appendLog(g, "trip", cut(string.format("trip %d offscreen (%s): %s, back in %d h", t.n, t.from,
        table.concat(team, " "), hours)), G.today())
    Ex.stats.abstract = Ex.stats.abstract + 1
    log().info("expedition: group %s trip %d goes offscreen during %s (%s): %s, back at hour %d", gid, t.n, t.from,
        tostring(why), table.concat(team, " "), hour + hours)
    Ex.state.claims[gid .. "#" .. t.n] = nil
end

-- PNJ npcId d'un membre retiré du monde (Materialize.onReleased, LK03-T04) : membre de l'équipe d'une expédition en
-- cours retiré de l'équipe (de retour au foyer pour la simulation), ou toute l'équipe hors écran si plus aucun de ses
-- corps n'a de joueur à BODIES.RELEASE_RADIUS cases. Rend "abstract", "left" ou nil.
function Ex.onReleased(gid, mid)
    local t, g = curOf(gid)
    if t == nil or not Ex.ACTIVE[t.phase] or not inList(t.team, mid) then return nil end
    local B = LivingKnox.Bodies
    local players = B.livingPlayers()
    local r = LivingKnox.Config.BODIES and LivingKnox.Config.BODIES.RELEASE_RADIUS or 120
    local near = false
    for _, other in ipairs(t.team) do
        local m = g.members[other]
        if other ~= mid and m ~= nil and m.alive and m.npc ~= nil and isEmbodied(m) then
            local z = B.find(m.npc)
            if z ~= nil and B.playerNear(players, z:getX(), z:getY(), r) then near = true end
        end
    end
    local hour = Decisions().currentHour() or 0
    local result
    Groups().update(function(d)
        local live = d.groups[gid]
        local cur = live and live.trips and live.trips.cur or nil
        if cur == nil or cur.n ~= t.n then return false, false end
        local team = {}
        for _, other in ipairs(cur.team) do
            local m = live.members[other]
            if m ~= nil and m.alive and (not near or other ~= mid) then team[#team + 1] = other end
        end
        if near then
            cur.team = team
            result = "left"
            log().info("expedition: group %s trip %d: %s left the team (released, the others are still seen)", gid,
                cur.n, mid)
        elseif #team > 0 then
            toAbstract(gid, live, cur, team, hour, mid .. " released")
            result = "abstract"
        end
        return true, true
    end)
    return result
end

-- Retour d'une expédition abstraite (appelé par LivingKnox.Simulation.simulateHour, à l'heure returns, dans
-- l'écriture du pas) : aucun membre perdu ni blessé ; butin abstrait tiré du flux erand (reproductible) ; phase
-- deliver (dépôt dès que le foyer est lisible). Pur sur le registre : aucun accès au monde. Rend le bilan.
function Ex.resolveAbstract(g, gid, hour, erand, day)
    local e = g.expedition
    g.expedition = nil
    local G = Groups()
    local s = g.trips
    local t = type(s) == "table" and s.cur or nil
    local back = 0
    for _, mid in ipairs(e.team) do
        local m = g.members[mid]
        if m ~= nil and m.alive then back = back + 1 end
    end
    if t == nil or t.n ~= e.trip or t.phase ~= "away" or not Ex.validCur(t) then
        G.appendLog(g, "return", cut("trip " .. tostring(e.trip) .. ": record lost, " .. back .. " back"), day)
        if type(s) == "table" then s.cur = nil end
        return { back = back, found = 0 }
    end
    local c = cfg()
    local found = 0
    local F = LivingKnox.Food
    if Ex.DRAWN[t.kind] and F ~= nil then
        -- LK05-T11 : tirages restants de la cueillette ou de la pêche, même flux qu'à l'écran (tirage k), conditions
        -- du moment.
        local cond = F.conditions()
        while (t.k or 0) < (t.r or 0) and #t.carry < t.cap and remaining(t) > 0 do
            t.k = (t.k or 0) + 1
            local before = #t.carry
            addFinds(t, (drawRound(F, gid, t, t.k, cond)))
            found = found + #t.carry - before
        end
    else
        for _, w in ipairs(t.want) do
            local list = Ex.ABSTRACT_ITEMS[w.c] or {}
            for _ = 1, back do
                if w.m > 0 and #t.carry < t.cap and #list > 0 and erand() < c.ABSTRACT_FIND then
                    local k = math.min(#list, math.floor(erand() * #list) + 1)
                    t.carry[#t.carry + 1] = { t = list[k], c = w.c, a = true }
                    w.m = w.m - 1
                    found = found + 1
                end
            end
        end
    end
    t.phase = "deliver"
    t.due = math.floor(hour * 60)
    G.appendLog(g, "trip", cut(string.format("trip %d back offscreen: %d back, %d item(s) found", t.n, back, found)),
        day)
    Ex.stats.resolved = Ex.stats.resolved + 1
    log().info("expedition: group %s trip %d back from offscreen at hour %d: %d back, %d item(s) found", gid, t.n,
        hour, back, found)
    return { back = back, found = found }
end

-- ================================================================ passage par minute

-- Contrôles d'une expédition en cours : équipe morte, délais des phases, dépôt en attente.
local function watch(gid, minute)
    local t, g = curOf(gid)
    if t == nil then return end
    if t.phase == "deliver" then
        Ex.deliver(gid)
        return
    end
    if not Ex.ACTIVE[t.phase] then return end
    local alive = 0
    for _, mid in ipairs(t.team) do
        local m = g.members[mid]
        if m ~= nil and m.alive then alive = alive + 1 end
    end
    if alive == 0 then
        local G = Groups()
        G.update(function(d)
            local live = d.groups[gid]
            local s = live and live.trips or nil
            if s == nil or s.cur == nil or s.cur.n ~= t.n then return false, false end
            s.cur, s.last = nil, minute
            G.appendLog(live, "return", cut(string.format("trip %d: no one came back from %s", t.n,
                tostring(t.target.label))), G.today())
            return true, true
        end)
        Ex.state.carried[gid .. "#" .. t.n] = nil
        log().info("expedition: group %s trip %d over: no member of the team alive", gid, t.n)
        return
    end
    if minute < t.due then return end
    if t.phase == "out" then
        setPhase(gid, t.n, "back", minute, "never reached the building")
    elseif t.phase == "search" then
        setPhase(gid, t.n, "back", minute, "search time over")
    elseif t.phase == "back" then
        setPhase(gid, t.n, "deliver", minute, "return time over")
        Ex.deliver(gid)
    end
end

-- Chaque minute de jeu : expéditions en cours surveillées, départs examinés. Rend le nombre de départs.
function Ex.minutePass()
    if not LivingKnox.isAuthority() or getCell() == nil then return 0 end
    local Config = LivingKnox.Config
    if Config.isEnabled ~= nil and not Config.isEnabled() then return 0 end
    local G = Groups()
    if not G.isReady() then return 0 end
    local minute = Decisions().currentMinute()
    if minute == nil then return 0 end
    local n = 0
    for _, gid in ipairs(G.list()) do
        local g = liveGroup(gid)
        if g ~= nil then
            tripsOf(gid, g)
            local ok, err = pcall(watch, gid, minute)
            if not ok then log().error("expedition: group %s watch failed: %s", gid, tostring(err)) end
            local last = Ex.state.checked[gid]
            if g.trips == nil or g.trips.cur == nil then
                if type(last) ~= "number" or minute - last >= cfg().CHECK_MINUTES or minute < last then
                    Ex.state.checked[gid] = minute
                    local okD, res, why = pcall(Ex.tryDepart, gid, minute)
                    if not okD then
                        log().error("expedition: group %s departure failed: %s", gid, tostring(res))
                    elseif res ~= nil then
                        n = n + 1
                    elseif why ~= nil then
                        log().debug("expedition: group %s stays home: %s", gid, tostring(why))
                    end
                end
            end
        end
    end
    return n
end

-- Expédition en cours du groupe gid (copie), ou nil.
function Ex.get(gid)
    local t = curOf(gid)
    if t == nil then return nil end
    return Groups().copy(t)
end

-- Mémoire d'un membre (copie), ou nil.
function Ex.memberState(id)
    local m = Ex.state.npcs[id]
    if m == nil then return nil end
    return Groups().copy(m)
end

-- Objets portés en mémoire par l'expédition n du groupe gid : nombre.
function Ex.carriedCount(gid, n)
    local k = 0
    for _ in pairs(Ex.state.carried[gid .. "#" .. n] or {}) do k = k + 1 end
    return k
end

-- Expédition abandonnée (suites, administration) : registre effacé (expédition abstraite liée comprise) ; les objets
-- portés sont perdus, jamais recréés. Rend vrai si une expédition était en cours.
function Ex.cancel(gid, why)
    local t = curOf(gid)
    if t == nil then return false end
    Groups().update(function(d)
        local live = d.groups[gid]
        if live == nil or live.trips == nil then return false, false end
        live.trips.cur = nil
        if type(live.expedition) == "table" and live.expedition.trip == t.n then live.expedition = nil end
        return true, true
    end)
    Ex.state.carried[gid .. "#" .. t.n] = nil
    log().info("expedition: group %s trip %d cancelled (%s)", gid, t.n, tostring(why))
    return true
end

function Ex.reset()
    Ex.state = { npcs = {}, claims = {}, sites = {}, carried = {}, checked = {} }
end

local function onEveryOneMinute()
    Ex.minutePass()
end

LivingKnox.subscribe("EveryOneMinute", "Expeditions.minutePass", onEveryOneMinute)

return Ex
