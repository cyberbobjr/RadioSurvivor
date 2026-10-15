-- Living Knox : routines des PNJ au foyer, côté autorité (LK05-T03) : guet aux postes, rondes, relèves, sommeil sur
-- un couchage. Fiche : docs/conception/routines.md. Java 42.21.0 cité en abrégé (J = zombie/...).
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- 1. Relevé du foyer (Routines.survey, une fois par foyer, au premier passage d'un membre incarné quand la zone du
--    foyer est chargée) : dans SURVEY_RADIUS cases autour de la case du foyer, au niveau du foyer, cases du même
--    bâtiment (IsoGridSquare.getBuildingDef, par la pièce : J/iso/IsoGridSquare.java:7805-7816) :
--      - postes de guet : case intérieure praticable contre une porte (getDoorTo) ou une fenêtre (getWindowTo,
--        getWindowThumpableTo) qui donne hors du bâtiment ; direction = vers l'extérieur ; portes d'abord ;
--      - couchages : objet dont le sprite porte le drapeau « bed » (IsoFlagType.bed, celui que lit le menu « Dormir »
--        du jeu : J/iso/ISWorldObjectContextMenuLogic.java:321-323, media/lua/client/ISUI/ISWorldObjectContextMenu.lua
--        :2642) ; qualité d'après la propriété BedType (absente = averageBed, J/iso/ISWorldObjectContextMenuLogic.java
--        :2847-2850) ; une moitié voisine d'un même lit n'est pas comptée deux fois ; place = case praticable voisine
--        du lit, regard vers le lit ;
--      - ronde : boucle de 3 à 8 cases hors bâtiment autour du rectangle du bâtiment (coins et milieux des côtés, à 2
--        cases, sinon 3 ou 1), toutes à HOME_RADIUS cases au plus du foyer (laisse, I3.2).
--    Foyer hors de tout bâtiment (camp) : ni poste, ni ronde, ni couchage (regard vers l'extérieur de LK05-T02).
--    Sauvegardé avec le groupe (registre des groupes, champ facultatif posts, schéma 1 inchangé, contrôlé ici et
--    relevé de nouveau s'il est malformé ou si le foyer a changé).
-- 2. Relèves (I3.1) : le poste « sentry » du cadre de décision tourne à chaque quart de 4 heures (22 h, 2 h, 6 h, 10 h,
--    14 h, 18 h ; LivingKnox.Decisions.rotation) ; poste choisi par (quart, rang du guetteur) : les postes tournent
--    aussi. Nuit (I3.3, maison tenue) : guet aux postes intérieurs ; aube (6 h-8 h, cour) : ronde ; jour : ronde la
--    première heure du quart, guet ensuite. Sans ronde : guet ; sans poste : regard vers l'extérieur (LK05-T02).
-- 3. Sommeil : le membre va à la place de son couchage (rang parmi les présents hors guetteurs = rang du lit), se
--    tourne vers le lit et s'assoit au sol (geste « sit », clip Bob_SitGround_Idle : aucune animation couchée n'est
--    prouvée pour un corps de zombie ; voir la fiche) ; sans couchage : retour dans le bâtiment du foyer s'il est
--    dehors (case libre près du foyer), arrêt et geste assis.
-- 4. Corvées (LK05-T04, comportement « chore » de la cascade : postes keeper, carer, forager, builder et routine, de
--    jour, au foyer) : petite activité visible tirée dans la liste fermée CHORES selon le poste, les comportements du
--    rôle et les traits du membre (I3.4), parmi celles qui ont une place au foyer : feu ou poêle (IsoFireplace, ou
--    conteneur de type « stove » : J/iso/CellLoader.java:115, 197-231), se chauffer les mains assis près du feu, ranger
--    un meuble (objet à conteneur, hors cuisson, feu et lessive), guetter à une fenêtre (postes relevés), bricoler à une
--    porte ou une fenêtre, fumer (trait smoker), soigner un blessé du groupe, se reposer assis. Un emplacement (case
--    praticable du bâtiment voisine de l'objet, sans mur entre les deux : IsoGridSquare.isBlockedTo,
--    J/iso/IsoGridSquare.java:935-941), un déplacement, un regard, un geste (clip Bob_ vanilla, nœuds générés par
--    tools/gen_animsets.py) et une durée (créneau de CHORE_MINUTES minutes de jeu, décalé par membre). Choix
--    déterministe : graine = identité du PNJ + créneau de temps de jeu. Effet purement visuel : aucun objet lu n'est
--    modifié (aucun conteneur ouvert, rien consommé). Emplacements des objets relevés en mémoire (non sauvegardés).
-- 5. Repas réels (LK05-T07, comportement « meal » de la cascade : faim ou soif >= NEED_HIGH, au foyer) : le membre
--    cherche dans le stock du foyer (LivingKnox.Stock.findMeal) un objet consommable (faim : nourriture ; soif : eau),
--    va à une case libre à côté du conteneur (même règle que les corvées), se tourne vers lui, fouille (geste
--    MEAL_TAKE_GESTURE, MEAL_TAKE_MINUTES), prend UN objet (Stock.takeMeal : retiré du conteneur et des clients, ôté de
--    la référence dans la même écriture : ni perte ni vol à la relecture), puis le consomme assis (MEAL_EAT_GESTURE,
--    MEAL_EAT_MINUTES). Le repas (LivingKnox.Needs.relieve : Needs.CFG.MEAL ou DRINK x part de ration, Stock.portion,
--    au moins celle du rationnement strict) est appliqué une seule fois : à la fin du repas, ou plus tôt si le repas
--    est interrompu (menace, corps retiré) après la prise. Ensuite, aucun nouveau repas du même besoin pendant
--    MEAL_GAP_MINUTES. Rien à manger ou à boire : pénurie au journal du groupe (Stock.reportShortage) et besoin mis de
--    côté UNFED_MINUTES (Routines.unfed, lu par la cascade) : le membre reprend son poste au lieu d'attendre. Mémoire des
--    repas : non sauvegardée.
-- 6. Entretien du foyer (LK05-T10, LK_Upkeep.lua) : un membre en corvée prend d'abord une tâche d'entretien ouverte du
--    foyer (générateur, sang, verre brisé), menée avec les outils de Routines.exec ; sinon corvée visible.
-- 7. Barricades (LK14-T03, LK_Fortify.lua) : un membre en corvée de poste « builder » barricade d'abord une ouverture
--    du foyer (Fortify.run, mémoire kind « fortify », mêmes outils de Routines.exec) ; sinon entretien, puis corvée.
-- Exécution : consignes LK03 seulement (Directives.moveTo, face, stop) émises au nom du cadre de décision
-- (Decisions.noteIssued : jamais vues comme « externes »), une consigne au plus par membre et par passage ; geste
-- par LivingKnox.Anim. Une menace interrompt la routine dans la cascade (LK_Decisions) ; la routine reprend ensuite
-- là où elle en était (point de ronde gardé). Mémoire des membres : non sauvegardée (recalculée).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Decisions"

local Routines = LivingKnox.Routines or {}
LivingKnox.Routines = Routines

Routines.FORMAT = 1
Routines.HANDLED = { guard = true, patrol = true, sleep = true, chore = true, meal = true }
Routines.POST_KINDS = { door = true, window = true }
Routines.SIT = "sit"
-- Corvées (LK05-T04) : liste fermée (ordre = ordre du tirage) et geste final de chacune (nil : debout, regard seul).
Routines.CHORES = { "fire", "warm", "tidy", "lookout", "repair", "smoke", "care", "rest" }
Routines.CHORE_GESTURE = { fire = "kneel", warm = "warmhands", tidy = "rummage", repair = "hammer", smoke = "smoke",
    care = "kneel", rest = "sit" }
-- Repas réels (LK05-T07) : besoin -> catégorie du stock ; gestes existants (aucun clip de repas n'est généré : fouille
-- pour prendre, assis pour consommer).
Routines.MEAL = { hunger = "food", thirst = "water" }
Routines.MEAL_TAKE_GESTURE = "rummage"
Routines.MEAL_EAT_GESTURE = "sit"
-- Gestes posés par les routines : remis au repos quand la routine s'arrête (Routines.leave).
Routines.GESTURES = { sit = true, kneel = true, warmhands = true, rummage = true, hammer = true, smoke = true }

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche).
Routines.CFG = Routines.CFG or {
    MAX_POSTS = 6,             -- postes de guet relevés au plus (portes d'abord)
    MAX_BEDS = 6,              -- couchages relevés au plus
    MAX_ROUND = 8,             -- cases d'une ronde au plus
    MIN_ROUND = 3,             -- en dessous, pas de ronde
    ROUND_MARGINS = { 2, 3, 1 },   -- cases entre le bâtiment et la ronde, dans l'ordre d'essai
    DAWN_END = 8,              -- heure du jour : fin de l'aube (la nuit finit à Config.SIMULATION.NIGHT_END)
    MAX_FAILS = 2,             -- trajets manqués vers une même case avant d'y renoncer (jusqu'au plan suivant)
    RETRY_MS = 10000,          -- relevé impossible (zone non chargée) : nouvel essai au plus toutes les 10 s
    BED_QUALITY = { goodBed = 4, averageBed = 3, badBed = 2, badChair = 1 },
    -- Corvées (LK05-T04).
    CHORE_MINUTES = 30,        -- minutes de jeu d'une corvée (créneau, décalé par membre)
    MAX_FIRES = 4,             -- feux et poêles relevés au plus
    MAX_FURNITURE = 12,        -- meubles à ranger relevés au plus
    CARE_HEALTH = 0.75,        -- santé (0..1) sous laquelle un membre présent est soigné par un autre
    -- Types de conteneur (propriété de tuile « container ») qui ne sont pas des meubles à ranger : cuisson, feu, lessive.
    NOT_FURNITURE = { stove = true, microwave = true, toaster = true, coffeemaker = true, fireplace = true,
        woodstove = true, brazier = true, campfire = true, barbecue = true, barbecuepropane = true,
        clothingwasher = true, clothingdryer = true },
    -- Poids des corvées : par poste (routine = sans poste à corvées), puis bonus par comportement du rôle et par trait.
    CHORE_DUTY = {
        keeper = { fire = 3, warm = 1, tidy = 3, lookout = 2, repair = 1, care = 1, rest = 2 },
        carer = { care = 6, fire = 1, tidy = 1, rest = 1 },
        forager = { tidy = 3, lookout = 1, repair = 1, rest = 2 },
        builder = { repair = 5, fire = 1, tidy = 1, rest = 1 },
        routine = { fire = 1, warm = 1, tidy = 1, lookout = 1, rest = 3 },
    },
    CHORE_ROLE = { heal = { care = 3 }, cook = { fire = 2 }, chores = { fire = 1, tidy = 1 }, maintain = { repair = 2 },
        fortify = { repair = 1 }, guard = { lookout = 1 }, patrol = { lookout = 1 }, scout = { lookout = 1 },
        scavenge = { tidy = 1 } },
    CHORE_TRAIT = { tidy = { tidy = 3 }, nervous = { lookout = 3 }, keenHearing = { lookout = 2 },
        strong = { repair = 2 }, smoker = { smoke = 4 }, drinker = { warm = 1, rest = 2 } },
    -- Repas réels (LK05-T07).
    MEAL_TAKE_MINUTES = 1,     -- minutes de jeu à fouiller le conteneur avant de prendre l'objet
    MEAL_EAT_MINUTES = 5,      -- minutes de jeu assis à manger ou boire
    MEAL_GAP_MINUTES = 60,     -- après un repas : pas de nouveau repas du même besoin avant (minutes de jeu)
    UNFED_MINUTES = 60,        -- rien à prendre (ou conteneur hors d'atteinte) : besoin mis de côté (minutes de jeu)
    MEAL_TRIES = 2,            -- objet parti entre le repérage et la prise : recherches au plus
}

Routines.state = Routines.state or { npcs = {}, valid = {}, tried = {}, spots = {}, byChore = {}, unfed = {} }
Routines.stats = Routines.stats or { surveys = 0, notLoaded = 0, moves = 0, faces = 0, stops = 0, sits = 0,
    refused = 0, laps = 0, gaveUp = 0, spotSurveys = 0, chores = 0, gestures = 0 }
Routines.stats.meals = Routines.stats.meals or 0        -- LK05-T07 : objets pris pour un repas
Routines.stats.fasts = Routines.stats.fasts or 0        -- LK05-T07 : besoins mis de côté (rien à prendre)

-- Directions orthogonales : décalage et angle de setDirectionAngle (y croissant = sud, Directives.ANGLES).
local DIRS = { { 0, -1, 270 }, { 1, 0, 0 }, { 0, 1, 90 }, { -1, 0, 180 } }

local function log() return LivingKnox.Log end
local function cfg() return Routines.CFG end
local function Decisions() return LivingKnox.Decisions end
local function Groups() return LivingKnox.Groups end
local function now() return getTimestampMs() end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end

local function leash() return Decisions().CFG.HOME_RADIUS end

-- ================================================================ heures (pur)

function Routines.hourOfDay(hour) return (hour + 7) % 24 end

-- "night", "dawn" ou "day" à l'heure d'âge hour (nuit de Config.SIMULATION, comme le cadre de décision).
function Routines.period(hour)
    if Decisions().isNight(hour) then return "night" end
    if Routines.hourOfDay(hour) < cfg().DAWN_END then return "dawn" end
    return "day"
end

-- Heure dans le quart (0 = première heure du quart).
function Routines.hourInWatch(hour)
    local c = Decisions().CFG
    return (hour + 7 + 24 - c.WATCH_START) % c.WATCH_HOURS
end

-- Guet ("guard") ou ronde ("patrol") du guetteur à l'heure hour, selon les postes relevés (posts, ou nil).
function Routines.sentryKind(hour, posts)
    local hasRound = type(posts) == "table" and type(posts.round) == "table" and #posts.round >= cfg().MIN_ROUND
    if not hasRound then return "guard" end
    local p = Routines.period(hour)
    if p == "night" then return "guard" end
    if p == "dawn" then return "patrol" end
    if Routines.hourInWatch(hour) == 0 then return "patrol" end
    return "guard"
end

-- ================================================================ relevé du foyer

local function buildingId(sq)
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()   -- long au-delà de 2^53 : texte exact (base world-placement.md)
end

-- Case où un corps peut se tenir : praticable (isFree sans compter les personnages), pas un escalier (isFree y est
-- vrai, J/iso/IsoGridSquare.java:2173-2175).
local function standable(sq)
    return sq ~= nil and sq:isFree(false) and not sq:HasStairs()
end

-- Qualité du meilleur couchage de la case (BED_QUALITY), ou nil.
function Routines.bedQuality(sq)
    if IsoFlagType == nil or IsoFlagType.bed == nil then return nil end
    local objs = sq:getObjects()
    if objs == nil then return nil end
    local best
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local props = o ~= nil and o:getSprite() ~= nil and o:getProperties() or nil
        if props ~= nil and props:has(IsoFlagType.bed) then
            local q = cfg().BED_QUALITY[props:get("BedType") or "averageBed"] or cfg().BED_QUALITY.averageBed
            if best == nil or q > best then best = q end
        end
    end
    return best
end

local function byPlace(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.d ~= b.d then return a.d < b.d end
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return (a.a or 0) < (b.a or 0)
end

-- Ronde autour du rectangle (x1, y1)-(x2, y2) du bâtiment : coins et milieux des côtés, sens horaire depuis le
-- nord-ouest ; chaque point à la première marge praticable, hors bâtiment, dans la laisse du foyer.
local function roundAround(cell, home, x1, y1, x2, y2)
    local mx, my = math.floor((x1 + x2) / 2), math.floor((y1 + y2) / 2)
    -- { x de base, signe x, y de base, signe y } : la marge m éloigne le point du bâtiment.
    local spots = { { x1, -1, y1, -1 }, { mx, 0, y1, -1 }, { x2, 1, y1, -1 }, { x2, 1, my, 0 }, { x2, 1, y2, 1 },
        { mx, 0, y2, 1 }, { x1, -1, y2, 1 }, { x1, -1, my, 0 } }
    local out = {}
    for _, s in ipairs(spots) do
        for _, m in ipairs(cfg().ROUND_MARGINS) do
            local x, y = s[1] + s[2] * m, s[3] + s[4] * m
            local sq = cell:getGridSquare(x, y, home.z)
            if standable(sq) and buildingId(sq) == nil and cheb(x, y, home.x, home.y) <= leash() then
                local last = out[#out]
                if last == nil or last.x ~= x or last.y ~= y then out[#out + 1] = { x = x, y = y, z = home.z } end
                break
            end
        end
        if #out >= cfg().MAX_ROUND then break end
    end
    if #out >= 2 and out[1].x == out[#out].x and out[1].y == out[#out].y then out[#out] = nil end
    if #out < cfg().MIN_ROUND then return {} end
    return out
end

-- Relevé du foyer home = { x, y, z } dans la zone chargée. Rend { v, hx, hy, hz, camp, posts, round, beds }, ou nil et
-- une raison (zone du foyer non chargée).
function Routines.survey(home)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local R = leash()
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    if hsq == nil then return nil, "home square not loaded" end
    for _, c in ipairs({ { -R, -R }, { R, -R }, { R, R }, { -R, R } }) do
        if cell:getGridSquare(home.x + c[1], home.y + c[2], home.z) == nil then return nil, "home area not loaded" end
    end
    local out = { v = Routines.FORMAT, hx = home.x, hy = home.y, hz = home.z, posts = {}, round = {}, beds = {} }
    local bid = buildingId(hsq)
    if bid == nil then
        out.camp = true
        return out
    end
    local posts, beds, used = {}, {}, {}
    local x1, y1, x2, y2
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, home.z)
            if sq ~= nil and buildingId(sq) == bid then
                if x1 == nil or x < x1 then x1 = x end
                if x2 == nil or x > x2 then x2 = x end
                if y1 == nil or y < y1 then y1 = y end
                if y2 == nil or y > y2 then y2 = y end
                local q = Routines.bedQuality(sq)
                if q ~= nil then
                    beds[#beds + 1] = { x = x, y = y, q = q, rank = -q, d = cheb(x, y, home.x, home.y) }
                elseif standable(sq) then
                    for _, d in ipairs(DIRS) do
                        local nb = cell:getGridSquare(x + d[1], y + d[2], home.z)
                        if nb ~= nil and buildingId(nb) ~= bid then
                            local kind
                            if sq:getDoorTo(nb) ~= nil then
                                kind = "door"
                            elseif sq:getWindowTo(nb) ~= nil or sq:getWindowThumpableTo(nb) ~= nil then
                                kind = "window"
                            end
                            if kind ~= nil then
                                posts[#posts + 1] = { x = x, y = y, z = home.z, a = d[3], k = kind,
                                    rank = kind == "door" and 1 or 2, d = cheb(x, y, home.x, home.y) }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(posts, byPlace)
    for _, p in ipairs(posts) do
        local key = p.x .. "," .. p.y
        if #out.posts < cfg().MAX_POSTS and not used[key] then
            used[key] = true
            out.posts[#out.posts + 1] = { x = p.x, y = p.y, z = p.z, a = p.a, k = p.k }
        end
    end
    -- Couchages : meilleure qualité d'abord ; une case de lit voisine d'un lit déjà retenu = le même lit.
    table.sort(beds, byPlace)
    local chosen = {}
    for _, b in ipairs(beds) do
        if #out.beds >= cfg().MAX_BEDS then break end
        local same = false
        for _, c in ipairs(chosen) do
            if cheb(b.x, b.y, c.x, c.y) <= 1 then same = true end
        end
        if not same then
            chosen[#chosen + 1] = b
            for _, d in ipairs(DIRS) do
                local sx, sy = b.x + d[1], b.y + d[2]
                local sq = cell:getGridSquare(sx, sy, home.z)
                local key = sx .. "," .. sy
                if not used[key] and standable(sq) and buildingId(sq) == bid and Routines.bedQuality(sq) == nil then
                    used[key] = true
                    local a = (d[3] + 180) % 360   -- de la place vers le lit
                    out.beds[#out.beds + 1] = { x = sx, y = sy, z = home.z, bx = b.x, by = b.y, a = a, q = b.q }
                    break
                end
            end
        end
    end
    out.round = roundAround(cell, home, x1, y1, x2, y2)
    return out
end

-- Forme d'un relevé sauvegardé pour le foyer home. Rend vrai, ou faux et une raison.
local function validList(list, max, check)
    if type(list) ~= "table" then return false end
    local n = 0
    for k in pairs(list) do
        if not isInt(k, 1, max) then return false end
        n = n + 1
    end
    if list[n] == nil and n > 0 then return false end
    for i = 1, n do
        local e = list[i]
        if type(e) ~= "table" or not isInt(e.x, 0, 2147483647) or not isInt(e.y, 0, 2147483647)
            or not isInt(e.z, -32, 31) or not check(e) then
            return false
        end
    end
    return true
end

function Routines.validPosts(p, home)
    if type(p) ~= "table" or p.v ~= Routines.FORMAT then return false, "unknown format" end
    if type(home) ~= "table" or p.hx ~= home.x or p.hy ~= home.y or p.hz ~= home.z then return false, "home moved" end
    if p.camp ~= nil and p.camp ~= true then return false, "bad camp flag" end
    local c = cfg()
    if not validList(p.posts, c.MAX_POSTS, function(e)
        return isInt(e.a, 0, 359) and Routines.POST_KINDS[e.k] == true
    end) then
        return false, "bad posts"
    end
    if not validList(p.round, c.MAX_ROUND, function() return true end) then return false, "bad round" end
    if not validList(p.beds, c.MAX_BEDS, function(e)
        return isInt(e.bx, 0, 2147483647) and isInt(e.by, 0, 2147483647) and isInt(e.a, 0, 359) and isInt(e.q, 1, 4)
    end) then
        return false, "bad beds"
    end
    return true
end

local function summary(p)
    local doors = 0
    for _, e in ipairs(p.posts) do
        if e.k == "door" then doors = doors + 1 end
    end
    return string.format("%d post(s) (%d door, %d window), round of %d square(s), %d bed(s)%s", #p.posts, doors,
        #p.posts - doors, #p.round, #p.beds, p.camp and ", camp (no building)" or "")
end

-- Relevé du foyer du groupe vivant g (registre), fait et sauvegardé s'il manque, est malformé ou si le foyer a
-- changé. Rend le relevé, ou nil (pas de foyer, zone non chargée : nouvel essai au plus toutes les RETRY_MS).
function Routines.ensurePosts(gid, g)
    if type(g) ~= "table" or type(g.home) ~= "table" then return nil end
    local home = g.home
    local key = home.x .. "," .. home.y .. "," .. home.z
    local st = Routines.state
    if st.valid[gid] == key and g.posts ~= nil then return g.posts end
    local ok, why = Routines.validPosts(g.posts, home)
    if ok then
        st.valid[gid] = key
        return g.posts
    end
    local t = now()
    if st.tried[gid] ~= nil and t - st.tried[gid] < cfg().RETRY_MS then return nil end
    st.tried[gid] = t
    local p, notLoaded = Routines.survey(home)
    if p == nil then
        Routines.stats.notLoaded = Routines.stats.notLoaded + 1
        log().debug("group %s: home survey postponed: %s", gid, tostring(notLoaded))
        return nil
    end
    p.day = Groups().today()
    if g.posts ~= nil then log().warn("group %s: home survey redone (%s)", gid, tostring(why)) end
    Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil then return false end
        live.posts = p
        return true
    end)
    g.posts = p   -- g peut être une copie : même relevé que le registre
    st.valid[gid] = key
    Routines.stats.surveys = Routines.stats.surveys + 1
    log().info("group %s home %s surveyed: %s", gid, key, summary(p))
    return p
end

-- Oublie le relevé d'un groupe (foyer modifié, essais) : il sera refait au prochain passage. Rend vrai si oublié.
function Routines.resurvey(gid)
    Routines.state.valid[gid], Routines.state.tried[gid] = nil, nil
    local done = Groups().update(function(data)
        local live = data.groups[gid]
        if live == nil or live.posts == nil then return false, false end
        live.posts = nil
        return true, true
    end)
    return done == true
end

-- ================================================================ affectations (pur)

-- Membres présents (vivants, hors expédition), triés par numéro : { mid, ... }.
function Routines.present(g)
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local out = {}
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then out[#out + 1] = mid end
    end
    local G = Groups()
    table.sort(out, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
    return out
end

local function rankOf(list, mid)
    for i, v in ipairs(list) do
        if v == mid then return i end
    end
    return nil
end

-- Guetteurs présents (poste "sentry"), triés par numéro.
function Routines.sentries(g)
    local out = {}
    for _, mid in ipairs(Routines.present(g)) do
        if g.members[mid].duty == "sentry" then out[#out + 1] = mid end
    end
    return out
end

-- Poste de guet du guetteur mid à l'heure hour : les postes tournent à chaque quart. nil sans poste.
function Routines.postFor(posts, g, mid, hour)
    local list = type(posts) == "table" and posts.posts or nil
    if type(list) ~= "table" or #list == 0 then return nil end
    local i = rankOf(Routines.sentries(g), mid) or 1
    return list[((Decisions().watchOf(hour) + i - 1) % #list) + 1]
end

-- Point de départ de la ronde du guetteur mid (guetteurs répartis sur la boucle).
function Routines.roundStart(posts, g, mid)
    local n = #posts.round
    local s = Routines.sentries(g)
    local i = rankOf(s, mid) or 1
    local spread = math.max(1, math.floor(n / math.max(1, #s)))
    return ((i - 1) * spread) % n + 1
end

-- Couchage du membre mid : rang du membre parmi les présents qui ne sont pas de garde = rang du couchage (le lit
-- d'un guetteur n'est pas perdu ; à la relève, le relevé reprend le lit laissé) ; un guetteur qui dort malgré tout
-- (fatigue) : les lits restants, après ceux des autres. nil s'il en manque.
function Routines.bedFor(posts, g, mid)
    local list = type(posts) == "table" and posts.beds or nil
    if type(list) ~= "table" then return nil end
    local sleepers, sentries = {}, {}
    for _, other in ipairs(Routines.present(g)) do
        if g.members[other].duty ~= "sentry" then
            sleepers[#sleepers + 1] = other
        else
            sentries[#sentries + 1] = other
        end
    end
    local r = rankOf(sleepers, mid)
    if r == nil then
        r = rankOf(sentries, mid)
        if r == nil then return nil end
        r = #sleepers + r
    end
    return list[r]
end

-- Plan du comportement b (guard, patrol, sleep) pour le membre mid à l'heure hour : { kind, key, x, y, z, a, sit,
-- points, start }. kind : "post" (aller au poste, regarder), "round", "bed" (aller au couchage, regarder le lit,
-- s'asseoir), "face" (regarder dans la direction a), "sit" (s'arrêter et s'asseoir).
function Routines.plan(b, posts, g, mid, hour, angle)
    if b == "guard" then
        local p = Routines.postFor(posts, g, mid, hour)
        if p ~= nil then
            return { kind = "post", key = string.format("post %d,%d,%d", p.x, p.y, p.z), x = p.x, y = p.y, z = p.z,
                a = p.a, what = p.k }
        end
        return { kind = "face", key = "face", a = angle }
    elseif b == "patrol" then
        if type(posts) == "table" and #posts.round >= cfg().MIN_ROUND then
            return { kind = "round", key = "round", points = posts.round, start = Routines.roundStart(posts, g, mid) }
        end
        return { kind = "face", key = "face", a = angle }
    elseif b == "sleep" then
        local bed = Routines.bedFor(posts, g, mid)
        if bed ~= nil then
            return { kind = "bed", key = string.format("bed %d,%d,%d", bed.x, bed.y, bed.z), x = bed.x, y = bed.y,
                z = bed.z, a = bed.a, sit = true }
        end
        return { kind = "sit", key = "sit" }
    end
    return nil
end

-- ================================================================ corvées (LK05-T04)

-- Objet de corvée de la case : "fire" (IsoFireplace : cheminée, poêle à bois, brasero ; ou conteneur de type
-- « stove »), "furniture" (autre objet à conteneur, hors NOT_FURNITURE), ou nil ; et son rang (cheminée 1, cuisinière
-- 2, meuble 3). Lecture seule : aucun conteneur ouvert ni modifié.
function Routines.choreObject(sq)
    local objs = sq ~= nil and sq:getObjects() or nil
    if objs == nil then return nil end
    local best, rank
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local k, r
        if instanceof(o, "IsoFireplace") then
            k, r = "fire", 1
        elseif o ~= nil and not instanceof(o, "IsoWorldInventoryObject") then
            local c = o:getContainer()
            local t = c ~= nil and c:getType() or nil
            if t == "stove" then
                k, r = "fire", 2
            elseif t ~= nil and not cfg().NOT_FURNITURE[t] then
                k, r = "furniture", 3
            end
        end
        if k ~= nil and (rank == nil or r < rank) then best, rank = k, r end
    end
    return best, rank
end

-- Place d'une corvée devant l'objet de la case (x, y) : case voisine (nord, est, sud, ouest) praticable, du bâtiment
-- bid, sans lit, libre dans used, sans mur ni porte fermée entre les deux (isBlockedTo). Rend { x, y, z, a, ox, oy }
-- (a : regard vers l'objet), ou nil.
local function placeBeside(cell, x, y, z, bid, used)
    local osq = cell:getGridSquare(x, y, z)
    if osq == nil then return nil end
    for _, d in ipairs(DIRS) do
        local sx, sy = x + d[1], y + d[2]
        local sq = cell:getGridSquare(sx, sy, z)
        local key = sx .. "," .. sy
        if not used[key] and standable(sq) and (bid == nil or buildingId(sq) == bid) and Routines.bedQuality(sq) == nil
            and not sq:isBlockedTo(osq) then
            used[key] = true
            return { x = sx, y = sy, z = z, a = (d[3] + 180) % 360, ox = x, oy = y }
        end
    end
    return nil
end

-- Relevé des places de corvée du foyer home (zone chargée, même bâtiment, niveau du foyer) : { fire = { place... },
-- furniture = { place... } }, cheminées d'abord, puis distance au foyer et position. Camp : listes vides. nil et une
-- raison si la zone du foyer n'est pas chargée.
function Routines.surveySpots(home)
    local cell = getCell()
    if cell == nil then return nil, "no cell" end
    local R = leash()
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    if hsq == nil then return nil, "home square not loaded" end
    for _, c in ipairs({ { -R, -R }, { R, -R }, { R, R }, { -R, R } }) do
        if cell:getGridSquare(home.x + c[1], home.y + c[2], home.z) == nil then return nil, "home area not loaded" end
    end
    local out = { fire = {}, furniture = {} }
    local bid = buildingId(hsq)
    if bid == nil then return out end
    local found = {}
    for dy = -R, R do
        for dx = -R, R do
            local x, y = home.x + dx, home.y + dy
            local sq = cell:getGridSquare(x, y, home.z)
            if sq ~= nil and buildingId(sq) == bid then
                local kind, rank = Routines.choreObject(sq)
                if kind ~= nil then
                    found[#found + 1] = { x = x, y = y, kind = kind, rank = rank, d = cheb(x, y, home.x, home.y) }
                end
            end
        end
    end
    table.sort(found, byPlace)
    local max = { fire = cfg().MAX_FIRES, furniture = cfg().MAX_FURNITURE }
    local used = {}
    for _, f in ipairs(found) do
        local list = out[f.kind]
        if #list < max[f.kind] then
            local p = placeBeside(cell, f.x, f.y, home.z, bid, used)
            if p ~= nil then list[#list + 1] = p end
        end
    end
    return out
end

-- Places de corvée du foyer du groupe gid (mémoire, refaites si le foyer change ; zone non chargée : nouvel essai au
-- plus toutes les RETRY_MS). Rend la table de surveySpots, ou nil.
function Routines.ensureSpots(gid, home)
    if type(home) ~= "table" then return nil end
    local key = home.x .. "," .. home.y .. "," .. home.z
    local st = Routines.state
    st.spots = st.spots or {}
    local s = st.spots[gid]
    if s ~= nil and s.key == key then
        if s.data ~= nil then return s.data end
        if now() - s.t < cfg().RETRY_MS then return nil end
    end
    local data, why = Routines.surveySpots(home)
    st.spots[gid] = { key = key, data = data, t = now() }
    if data == nil then
        log().debug("group %s: chore places postponed: %s", gid, tostring(why))
        return nil
    end
    Routines.stats.spotSurveys = Routines.stats.spotSurveys + 1
    log().info("group %s home %s chore places: %d fire(s), %d furniture", gid, key, #data.fire, #data.furniture)
    return data
end

-- Créneau de corvée du PNJ id à la minute de jeu minute : CHORE_MINUTES minutes, décalé de 0 à CHORE_MINUTES - 1
-- minutes selon l'identité (deux membres ne changent pas de corvée à la même minute).
function Routines.choreSlot(id, minute)
    local span = cfg().CHORE_MINUTES
    local off = math.floor(Decisions().stream("chore/" .. tostring(id), 0, 3)() * span)
    return math.floor((math.floor(minute) + off) / span)
end

-- Poids des corvées (pur) : poste duty (CHORE_DUTY, "routine" par défaut), comportements du rôle allowed
-- ({ [nom] = vrai }), traits ({ [nom] = vrai }), corvées possibles avail ({ [corvée] = vrai }). Rend { [corvée] = n }.
function Routines.choreWeights(duty, allowed, traits, avail)
    local c = cfg()
    local base = c.CHORE_DUTY[duty] or c.CHORE_DUTY.routine
    local out = {}
    for _, ch in ipairs(Routines.CHORES) do out[ch] = base[ch] or 0 end
    local function bonus(tbl, set)
        local names = {}
        for n in pairs(set or {}) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            local b = tbl[n]
            if b ~= nil then
                for _, ch in ipairs(Routines.CHORES) do out[ch] = out[ch] + (b[ch] or 0) end
            end
        end
    end
    bonus(c.CHORE_ROLE, allowed)
    bonus(c.CHORE_TRAIT, traits)
    for _, ch in ipairs(Routines.CHORES) do
        if not (avail or {})[ch] then out[ch] = 0 end
    end
    return out
end

-- Corvée tirée (pur, déterministe) : graine = identité id + créneau slot ; tirage pondéré dans l'ordre de CHORES.
-- Aucun poids : "rest".
function Routines.pickChore(id, slot, weights)
    local total = 0
    for _, ch in ipairs(Routines.CHORES) do total = total + (weights[ch] or 0) end
    if total <= 0 then return "rest" end
    local r = math.floor(Decisions().stream("chore/" .. tostring(id), slot, 11)() * total)
    for _, ch in ipairs(Routines.CHORES) do
        r = r - (weights[ch] or 0)
        if r < 0 then return ch end
    end
    return "rest"
end

-- Membre présent le plus blessé (santé sous CARE_HEALTH, corps incarné au foyer), autre que mid : mid, corps ; ou nil.
function Routines.woundedFor(g, mid, home)
    local B = LivingKnox.Bodies
    if B == nil or B.find == nil then return nil end
    local best, bestH, bestBody
    for _, other in ipairs(Routines.present(g)) do
        local m = g.members[other]
        if other ~= mid and m.npc ~= nil then
            local h = Decisions().healthOf(m)
            if h < cfg().CARE_HEALTH and (bestH == nil or h < bestH) then
                local z = B.find(m.npc)
                if z ~= nil and (home == nil or (math.floor(z:getZ()) == home.z
                    and cheb(z:getX(), z:getY(), home.x + 0.5, home.y + 0.5) <= leash())) then
                    best, bestH, bestBody = other, h, z
                end
            end
        end
    end
    return best, bestBody
end

local function windowsFree(posts, g, hour)
    local out = {}
    if type(posts) ~= "table" or type(posts.posts) ~= "table" then return out end
    local taken = {}
    for _, s in ipairs(Routines.sentries(g)) do
        local p = Routines.postFor(posts, g, s, hour)
        if p ~= nil then taken[p.x .. "," .. p.y] = true end
    end
    for _, p in ipairs(posts.posts) do
        if p.k == "window" and not taken[p.x .. "," .. p.y] then out[#out + 1] = p end
    end
    return out
end

-- Plan de corvée du membre (contexte ctx du cadre de décision, groupe g du registre, relevé posts) : { kind, key,
-- chore, x, y, z, a, gesture }. kind "spot" (aller, regarder, geste) ou "sit" (rester ou rentrer, s'arrêter, geste).
function Routines.chorePlan(id, ctx, g, posts)
    local m = g.members[ctx.mid] or {}
    local hour = math.floor(ctx.minute / 60)
    local spots = Routines.ensureSpots(ctx.gid, g.home) or { fire = {}, furniture = {} }
    local windows = windowsFree(posts, g, hour)
    local doors = type(posts) == "table" and type(posts.posts) == "table" and posts.posts or {}
    local wounded, wbody = Routines.woundedFor(g, ctx.mid, g.home)
    local avail = { fire = #spots.fire > 0, warm = #spots.fire > 0, tidy = #spots.furniture > 0,
        lookout = #windows > 0, repair = #doors > 0, smoke = true, care = wounded ~= nil, rest = true }
    local traits = {}
    for _, t in ipairs(type(m.traits) == "table" and m.traits or {}) do traits[t] = true end
    local duty = Routines.CFG.CHORE_DUTY[ctx.duty] ~= nil and ctx.duty or "routine"
    local slot = Routines.choreSlot(id, ctx.minute)
    local chore = Routines.pickChore(id, slot, Routines.choreWeights(duty, ctx.allowed, traits, avail))
    local rank = rankOf(Routines.present(g), ctx.mid) or 1
    local function nth(list) return list[((slot + rank - 1) % #list) + 1] end
    local gesture = Routines.CHORE_GESTURE[chore]
    local function spot(p, a)
        return { kind = "spot", chore = chore, key = string.format("chore %s %d,%d,%d", chore, p.x, p.y, p.z),
            x = p.x, y = p.y, z = p.z, a = a or p.a, gesture = gesture }
    end
    if chore == "fire" or chore == "warm" then return spot(nth(spots.fire)) end
    if chore == "tidy" then return spot(nth(spots.furniture)) end
    if chore == "lookout" then return spot(nth(windows)) end
    if chore == "repair" then
        -- Porte ou fenêtre du relevé : regard vers elle (direction du poste).
        return spot(nth(doors))
    end
    if chore == "smoke" and #windows > 0 then return spot(nth(windows)) end
    if chore == "care" then
        local cell = getCell()
        local wx, wy, wz = math.floor(wbody:getX()), math.floor(wbody:getY()), math.floor(wbody:getZ())
        local p = cell ~= nil and placeBeside(cell, wx, wy, wz, nil, {}) or nil
        if p ~= nil then
            local out = spot(p)
            out.key = string.format("chore care %s %d,%d,%d", wounded, p.x, p.y, p.z)
            return out
        end
        chore, gesture = "rest", Routines.CHORE_GESTURE.rest
    end
    return { kind = "sit", chore = chore, key = "chore " .. chore, gesture = gesture }
end

-- ================================================================ exécution (autorité)

function Routines.handles(b) return Routines.HANDLED[b] == true end

local function entryOf(id)
    local D = LivingKnox.Directives
    return D ~= nil and D.get ~= nil and D.get(id) or nil
end

local function note(id, m, v, why, what)
    if not Decisions().noteIssued(id, v, why) then
        Routines.stats.refused = Routines.stats.refused + 1
        return false
    end
    m.lastV = v
    Routines.stats[what] = Routines.stats[what] + 1
    return true
end

local function faceTo(id, m, a)
    if a == nil then return false end
    local v, why = LivingKnox.Directives.face(id, a)
    if note(id, m, v, why, "faces") then
        m.faceV = v
        return true
    end
    return false
end

-- Geste final de la routine (assis par défaut ; corvées : CHORE_GESTURE).
local function sitDown(id, m, gesture)
    gesture = gesture or Routines.SIT
    local A = LivingKnox.Anim
    if A == nil or A.gestureOf(id) == gesture then return end
    if A.setGesture(id, gesture) then
        m.sat = true
        if gesture == Routines.SIT then
            Routines.stats.sits = Routines.stats.sits + 1
        else
            Routines.stats.gestures = Routines.stats.gestures + 1
        end
    end
end

local function reached(ctx, x, y, z, m, e)
    if ctx.z == z then
        local dx, dy = ctx.x - (x + 0.5), ctx.y - (y + 0.5)
        if math.sqrt(dx * dx + dy * dy) <= LivingKnox.Directives.ARRIVE then return true end
    end
    -- Case visée décalée par l'autorité (plantes, feu de camp à côté) : l'arrivée acceptée compte.
    return m.moveV ~= nil and e ~= nil and e.v == m.moveV and e.done and e.s == "arrived"
end

-- Va à la case (x, y, z) : "here" (arrivé), "moving" (en route ou consigne émise), "failed" (renoncé).
local function goTo(id, ctx, x, y, z, m, e)
    if reached(ctx, x, y, z, m, e) then return "here" end
    if m.moveV ~= nil and e ~= nil and e.v == m.moveV then
        if not e.done then return "moving" end
        m.fails = m.fails + 1   -- trajet clos sans arrivée (échec, arrêt)
        m.moveV = nil
    end
    if m.fails >= cfg().MAX_FAILS then return "failed" end
    local v, why = LivingKnox.Directives.moveTo(id, x, y, z, "walk")
    if not note(id, m, v, why, "moves") then
        m.fails = m.fails + 1
        log().debug("npc %s: routine move to %d,%d,%d refused: %s", id, x, y, z, tostring(why))
        return m.fails >= cfg().MAX_FAILS and "failed" or "moving"
    end
    m.moveV = v
    return "moving"
end

-- Case où s'asseoir sans couchage : sur place si le corps est dans le bâtiment du foyer (ou si le foyer est un camp),
-- sinon une case libre près du foyer, dans son bâtiment (LivingKnox.Materialize.placeFor, comme le retour au foyer).
-- Rend x, y, z, ou nil (sur place).
local function sitPlace(ctx)
    local home = ctx.home
    local cell = getCell()
    if home == nil or cell == nil then return nil end
    local hsq = cell:getGridSquare(home.x, home.y, home.z)
    local bid = hsq ~= nil and buildingId(hsq) or nil
    if bid == nil then return nil end
    local here = cell:getGridSquare(math.floor(ctx.x), math.floor(ctx.y), ctx.z)
    if here ~= nil and buildingId(here) == bid then return nil end
    local Mat = LivingKnox.Materialize
    local place = Mat ~= nil and Mat.placeFor ~= nil and Mat.placeFor(home, bid, Decisions().CFG.HOME_PLACE_RADIUS) or nil
    if place == nil then return home.x, home.y, home.z end
    return place:getX(), place:getY(), place:getZ()
end

-- Arrêt puis geste (assis par défaut) sur place.
local function sitHere(id, m, e, gesture)
    if m.stopV == nil then
        local v, why = LivingKnox.Directives.stop(id)
        if note(id, m, v, why, "stops") then m.stopV = v end
        return
    end
    if e ~= nil and e.v == m.stopV and e.done then sitDown(id, m, gesture) end
end

local function runRound(id, ctx, plan, m, e)
    local pts = plan.points
    local n = #pts
    if m.k == nil or m.k > n then m.k = plan.start end
    for _ = 1, 2 do
        local p = pts[m.k]
        local res = goTo(id, ctx, p.x, p.y, p.z, m, e)
        if res == "moving" then return end
        if res == "failed" then
            Routines.stats.gaveUp = Routines.stats.gaveUp + 1
            log().debug("npc %s: round point %d,%d skipped", id, p.x, p.y)
        end
        m.k = (m.k % n) + 1
        if m.k == plan.start then Routines.stats.laps = Routines.stats.laps + 1 end
        m.fails, m.moveV = 0, nil
    end
end

-- Outils d'exécution partagés avec l'entretien du foyer (LK05-T10, LK_Upkeep.lua) : même déplacement, regard et geste
-- que les corvées et les repas, mémoire du membre dans Routines.state.npcs (kind « upkeep »).
Routines.exec = { goTo = goTo, faceTo = faceTo, sitDown = sitDown, placeBeside = placeBeside, standable = standable,
    buildingId = buildingId, entryOf = entryOf }

-- Applique la routine du comportement st.b au membre (contexte ctx du cadre de décision), à chaque passage.
function Routines.apply(id, st, ctx, fresh)
    local data = Groups().state.data
    local g = data ~= nil and data.groups[ctx.gid] or nil
    if g == nil then return end
    if st.b == "meal" then   -- LK05-T07
        Routines.runMeal(id, st, ctx, g)
        return
    end
    if st.b == "chore" then   -- LK14-T03 : poste « builder » : barricades du foyer (LK_Fortify) d'abord
        local F = LivingKnox.Fortify
        if ctx.duty == "builder" and F ~= nil and F.run ~= nil and F.run(id, st, ctx, g) then return end
    end
    if st.b == "chore" then   -- LK05-T10 : entretien du foyer (LK_Upkeep) avant une corvée visible
        local U = LivingKnox.Upkeep
        if U ~= nil and U.run ~= nil and U.run(id, st, ctx, g) then return end
    end
    local hour = math.floor(ctx.minute / 60)
    local posts = Routines.ensurePosts(ctx.gid, g)
    local plan
    if st.b == "chore" then
        plan = Routines.chorePlan(id, ctx, g, posts)
    else
        plan = Routines.plan(st.b, posts, g, ctx.mid, hour, st.angle)
    end
    if plan == nil then return end
    local mem = Routines.state.npcs
    local m = mem[id]
    if m == nil or m.key ~= plan.key then
        if m ~= nil then Routines.leave(id) end   -- autre plan (relève, réveil, corvée suivante) : debout d'abord
        m = { key = plan.key, kind = plan.kind, fails = 0, chore = plan.chore }
        mem[id] = m
        if plan.chore ~= nil then
            Routines.stats.chores = Routines.stats.chores + 1
            local by = Routines.state.byChore or {}
            Routines.state.byChore = by
            by[plan.chore] = (by[plan.chore] or 0) + 1
            log().debug("npc %s: chore %s (%s, %s)", id, plan.key, tostring(ctx.duty), st.why or st.b)
        else
            log().debug("npc %s: routine %s (%s)", id, plan.key, st.b)
        end
    end
    local gesture = plan.gesture or (plan.sit and Routines.SIT or nil)
    local e = entryOf(id)
    -- Une autre consigne est passée entre-temps (menace, retour au foyer, suite de test) : la routine reprend.
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) then
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
    end
    if plan.kind == "face" then
        if fresh or m.lastV == nil then faceTo(id, m, plan.a) end
    elseif plan.kind == "sit" then
        -- Sans couchage : à l'intérieur d'abord (maison tenue la nuit, I3.3), puis assis.
        if m.place == nil then
            local x, y, z = sitPlace(ctx)
            m.place = x ~= nil and { x = x, y = y, z = z } or false
        end
        if m.place and not m.placed then
            local res = goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
            if res == "moving" then return end
            m.placed = true   -- arrivé ou renoncé : assis là où il est
            e = entryOf(id)
        end
        sitHere(id, m, e, gesture)
    elseif plan.kind == "round" then
        runRound(id, ctx, plan, m, e)
    else
        local res = goTo(id, ctx, plan.x, plan.y, plan.z, m, e)
        if res == "moving" then return end
        if res == "failed" then
            if not m.gaveUp then
                m.gaveUp = true
                Routines.stats.gaveUp = Routines.stats.gaveUp + 1
                log().info("npc %s: cannot reach %s, staying here", id, plan.key)
            end
            if gesture ~= nil then sitHere(id, m, e, gesture) elseif m.faceV == nil then faceTo(id, m, plan.a) end
            return
        end
        if m.faceV == nil then
            faceTo(id, m, plan.a)
            return
        end
        if gesture ~= nil and e ~= nil and e.v == m.faceV and e.done then sitDown(id, m, gesture) end
    end
end

-- ================================================================ repas réels (LK05-T07)

local function unfedKey(gid, mid) return tostring(gid) .. "/" .. tostring(mid) end

-- Met de côté le besoin need ("hunger" ou "thirst") du membre jusqu'à la minute de jeu untilMin.
function Routines.fast(gid, mid, need, untilMin)
    local st = Routines.state
    st.unfed = st.unfed or {}
    local key = unfedKey(gid, mid)
    local f = st.unfed[key] or {}
    st.unfed[key] = f
    if f[need] == nil or untilMin > f[need] then f[need] = untilMin end
end

-- Besoins mis de côté du membre à la minute minute (lu par la cascade, LivingKnox.Decisions.context) :
-- { hunger = vrai, thirst = vrai } (clés présentes seulement), ou nil.
function Routines.unfed(gid, mid, minute)
    local f = (Routines.state.unfed or {})[unfedKey(gid, mid)]
    if f == nil or minute == nil then return nil end
    local out, any = {}, false
    for _, need in ipairs({ "hunger", "thirst" }) do
        if f[need] ~= nil and minute < f[need] then
            out[need], any = true, true
        end
    end
    if not any then return nil end
    return out
end

-- Repas pris (m.pending) appliqué une seule fois : jauge du membre baissée de m.relief, registre sauvegardé.
function Routines.finishMeal(id, m)
    if m == nil or not m.pending then return false end
    m.pending = false
    local N, G = LivingKnox.Needs, Groups()
    local value
    if N ~= nil and N.relieve ~= nil and G ~= nil then
        G.update(function(data)
            local g = data.groups[m.gid]
            if g == nil then return false, false end
            value = N.relieve(g, m.mid, m.need, m.relief)
            return value ~= nil, true
        end)
    end
    log().info("npc %s (%s %s): %s of %s done, %s -%d -> %s", tostring(id), tostring(m.gid), tostring(m.mid),
        m.need == "thirst" and "drink" or "meal", m.took and m.took.t or "?", m.need, m.relief or 0, tostring(value))
    return true
end

-- Part de ration d'un repas : Stock.portion, au moins celle du rationnement strict (un objet a bien été trouvé même
-- quand l'autre catégorie est épuisée).
local function mealPortion(gid)
    local S = LivingKnox.Stock
    if S == nil or S.portion == nil then return 1 end
    local p = S.portion(gid)
    local least = S.PORTIONS ~= nil and S.PORTIONS[3] or 0.5
    if type(p) ~= "number" or p < least then p = least end
    return p
end

local function mealOff(id, m, ctx, why, minutes)
    Routines.fast(ctx.gid, ctx.mid, m.need, ctx.minute + minutes)
    Routines.stats.fasts = Routines.stats.fasts + 1
    m.phase = "done"
    log().debug("npc %s: %s set aside for %d minute(s): %s", tostring(id), m.need, minutes, tostring(why))
end

local function mealRestart(m)
    m.phase, m.spot, m.place = "find", nil, nil
    m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
end

-- Repas réel du membre (comportement « meal », règle hunger ou thirst de la cascade), à chaque passage.
function Routines.runMeal(id, st, ctx, g)
    local need = st.rule == "thirst" and "thirst" or "hunger"
    local key = "meal " .. need
    local mem = Routines.state.npcs
    local m = mem[id]
    if m == nil or m.key ~= key then
        if m ~= nil then Routines.leave(id) end
        m = { key = key, kind = "meal", need = need, cat = Routines.MEAL[need], gid = ctx.gid, mid = ctx.mid,
            phase = "find", tries = 0, fails = 0 }
        mem[id] = m
        log().debug("npc %s: routine %s (%s)", id, key, tostring(st.why))
    end
    local e = entryOf(id)
    if m.lastV ~= nil and (e == nil or e.v ~= m.lastV) and (m.phase == "go" or m.phase == "face"
        or m.phase == "take") then
        -- Une autre consigne est passée avant la prise (suite de test, autre module) : retour à la place du repas.
        m.lastV, m.moveV, m.faceV, m.stopV, m.sat, m.fails = nil, nil, nil, nil, nil, 0
        m.phase = "go"
    end
    local S = LivingKnox.Stock
    if m.phase == "find" then
        if S == nil or S.findMeal == nil then return mealOff(id, m, ctx, "no stock module", cfg().UNFED_MINUTES) end
        local spot, why = S.findMeal(ctx.gid, m.cat)
        if spot == nil then
            if why == "none" then S.reportShortage(ctx.gid, m.cat, ctx.mid) end
            return mealOff(id, m, ctx, why, cfg().UNFED_MINUTES)
        end
        local cell = getCell()
        local home = g.home
        local hsq = cell ~= nil and type(home) == "table" and cell:getGridSquare(home.x, home.y, home.z) or nil
        local bid = hsq ~= nil and buildingId(hsq) or nil
        local place = cell ~= nil and placeBeside(cell, spot.x, spot.y, spot.z, bid, {}) or nil
        if place == nil then
            return mealOff(id, m, ctx, "no free square beside " .. spot.key, cfg().UNFED_MINUTES)
        end
        m.spot, m.place, m.phase = spot, place, "go"
    end
    if m.phase == "go" then
        local res = goTo(id, ctx, m.place.x, m.place.y, m.place.z, m, e)
        if res == "moving" then return end
        if res == "failed" then return mealOff(id, m, ctx, "cannot reach " .. m.spot.key, cfg().UNFED_MINUTES) end
        m.phase = "face"
    end
    if m.phase == "face" then
        if m.faceV == nil then
            faceTo(id, m, m.place.a)
            return
        end
        e = entryOf(id)
        if e == nil or e.v ~= m.faceV or not e.done then return end
        sitDown(id, m, Routines.MEAL_TAKE_GESTURE)
        m.since, m.phase = ctx.minute, "take"
        return
    end
    if m.phase == "take" then
        if ctx.minute - m.since < cfg().MEAL_TAKE_MINUTES then return end
        local portion = mealPortion(ctx.gid)
        local got, why = S.takeMeal(ctx.gid, m.cat, m.spot.key, nil, ctx.mid)
        if got == nil then
            m.tries = m.tries + 1
            log().debug("npc %s: %s at %s not taken: %s", id, m.cat, m.spot.key, tostring(why))
            if m.tries >= cfg().MEAL_TRIES then return mealOff(id, m, ctx, why, cfg().UNFED_MINUTES) end
            mealRestart(m)
            return
        end
        local N = LivingKnox.Needs
        local full = 60
        if N ~= nil and N.CFG ~= nil then full = need == "thirst" and N.CFG.DRINK or N.CFG.MEAL end
        m.took, m.relief, m.pending = got, math.floor(full * portion + 0.5), true
        Routines.stats.meals = Routines.stats.meals + 1
        sitDown(id, m, Routines.MEAL_EAT_GESTURE)
        m.since, m.phase = ctx.minute, "eat"
        return
    end
    if m.phase == "eat" then
        local A = LivingKnox.Anim
        if A ~= nil and A.gestureOf(id) ~= Routines.MEAL_EAT_GESTURE then sitDown(id, m, Routines.MEAL_EAT_GESTURE) end
        if ctx.minute - m.since < cfg().MEAL_EAT_MINUTES then return end
        Routines.finishMeal(id, m)
        Routines.fast(ctx.gid, ctx.mid, need, ctx.minute + cfg().MEAL_GAP_MINUTES)
        m.phase = "done"
    end
end

-- Fin d'une routine (le membre passe à un comportement sans routine) : geste de routine (assis, corvée) -> debout,
-- mémoire oubliée ; repas pris mais pas encore appliqué (LK05-T07) : appliqué maintenant.
function Routines.leave(id)
    local m = Routines.state.npcs[id]
    if m == nil then return end
    Routines.state.npcs[id] = nil
    Routines.finishMeal(id, m)
    local U = LivingKnox.Upkeep   -- LK05-T10 : tâche d'entretien libérée (reprise par un autre membre)
    if m.kind == "upkeep" and U ~= nil and U.release ~= nil then U.release(id, m) end
    local F = LivingKnox.Fortify   -- LK14-T03 : chantier de barricade libéré
    if m.kind == "fortify" and F ~= nil and F.release ~= nil then F.release(id, m) end
    local A = LivingKnox.Anim
    if A ~= nil and Routines.GESTURES[A.gestureOf(id)] then A.setGesture(id, A.DEFAULT) end
end

function Routines.forget(id)
    local m = Routines.state.npcs[id]
    Routines.state.npcs[id] = nil
    if m ~= nil then Routines.finishMeal(id, m) end
    local U = LivingKnox.Upkeep   -- LK05-T10
    if m ~= nil and m.kind == "upkeep" and U ~= nil and U.release ~= nil then U.release(id, m) end
    local F = LivingKnox.Fortify   -- LK14-T03
    if m ~= nil and m.kind == "fortify" and F ~= nil and F.release ~= nil then F.release(id, m) end
end

-- Mémoire d'un membre (copie), ou nil : { key, kind, k (point de ronde), fails, sat, ... }.
function Routines.get(id)
    local m = Routines.state.npcs[id]
    if m == nil then return nil end
    local out = {}
    for k, v in pairs(m) do out[k] = v end
    return out
end

function Routines.reset()
    Routines.state = { npcs = {}, valid = {}, tried = {}, spots = {}, byChore = {}, unfed = {} }
end

return Routines
