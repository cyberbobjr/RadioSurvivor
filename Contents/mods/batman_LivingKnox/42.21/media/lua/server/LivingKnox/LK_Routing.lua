-- Living Knox : itinéraires des PNJ autour des portes, fenêtres et clôtures (LK04-T09 à LK04-T20), sortis de
-- LK_Obstacles.lua (LK16-T11) : relevé des bords, recherche de chemin (A* sur les cases chargées), détours et points
-- de passage d'un "move". Fiche : docs/annexes/conception/deplacement.md. Autorité seulement, comme LK_Obstacles.
--
-- Modèles d'itinéraire (LK16-T11, constat D-OBS-01) : chaque modèle est inscrit par un fichier du dossier Routing/
-- (LivingKnox.Obstacles.Routing.registerModel(name, spec)) ; findRoute et lineClear le désignent par son nom. spec :
--   edgeCost(r, npcId, sqA, sqB, exitKeys, from) : surcoût en cases du passage du bord r (élément de edgeElement de
--     sorte "door", "window" ou "fence" ; bords "plain" (0) et "wall" (infranchissable) réglés par le moteur), cases
--     sqA (ouest ou nord) et sqB, exitKeys (bâtiments de sortie, ou nil), from (case d'où le bord est abordé) ; rend
--     le surcoût (nil : infranchissable) et le franchissement : "door" (passé debout), "climb" (escalade), "refused"
--     (passage que le PNJ ne prendra pas, compté par les modèles du chemin natif) ou nil ;
--   maxNodes() : facultatif, cases développées au plus (ROUTE_MAX_NODES sinon) ;
--   vanilla : facultatif, vrai pour un modèle du chemin natif d'un corps : meuble bas sous une fenêtre ou contre une
--     clôture praticable (squareKind 3), escalade d'une fenêtre vers un meuble bas notée "refused" au coût
--     refusedCost() (requis avec vanilla).
--
-- Porte d'abord (LK04-T09, décision de l'utilisateur du 2026-10-11 ; fiche deplacement.md, section « Porte
-- d'abord ») : le chemin vanilla d'un zombie traverse fenêtres et clôtures basses sans surcoût (et enjambe un portail
-- fermé), alors qu'un PNJ doit passer par une porte ou ouvrir un portail utilisable à proximité. Le chemin vanilla
-- n'étant pas lisible ni dirigeable en Lua, l'autorité calcule elle-même, à l'émission d'un "move"
-- (Directives.moveTo), un itinéraire sur les cases CHARGÉES (A* 8 voisins, boîte départ-destination élargie de
-- ROUTE_MARGIN cases, ROUTE_MAX_NODES cases développées au plus) : d'abord comme le moteur le ferait pour un zombie
-- (portes, fenêtres et clôtures basses sans surcoût) ; s'il franchit une fenêtre, une clôture basse ou un portail
-- fermé, un second itinéraire où chaque fenêtre ou clôture coûte ROUTE_PENALTY cases de plus (« rayon raisonnable » :
-- un détour par une porte d'au plus ROUTE_PENALTY cases est préféré), les portes et portails comptant selon les règles
-- de ce module (ouverte, ou décision "open" de decide ; portail refusé = clôture ; porte refusée, fenêtre refusée ou
-- barricade = infranchissable). Si ce second itinéraire passe par au moins une porte et franchit moins de fenêtres ou
-- clôtures, ses portes (ROUTE_MAX_DOORS au plus) deviennent des points de passage de la consigne (case avant la
-- porte, case après), comme les détours des potagers (LK05-T12) : la porte est alors sur l'étape courante et ce
-- module l'ouvre à DETECT cases (portail compris), puis la referme derrière le corps. Chaque tronçon entre deux
-- points étant parcouru par le chemin vanilla (non lisible, et que le modèle "zombie" ne prédit pas toujours), tout
-- l'itinéraire du PNJ est jalonné de points rapprochés (ROUTE_STEP cases au plus, en ligne dégagée de l'un à l'autre,
-- ROUTE_MAX_POINTS au plus, voir planDoorRoute) : aucun tronçon n'est assez long pour qu'un raccourci par une fenêtre
-- ou une clôture soit plus court que la ligne droite. Sinon rien ne change : fenêtre
-- ou clôture en dernier recours. Murs : isBlockedTo ; clôture basse : isFenceTo (objet enjambable ET drapeau de case
-- HoppableW/N, celui que lit le moteur) ; case praticable : squareKind (isFree(false), arbre ou buisson avec le
-- surcoût natif ROUTE_TREE, et pour le seul modèle "zombie" meuble solidtrans qui borde une fenêtre ou une clôture
-- basse). Une ligne dégagée ne traverse aucune case d'arbre ou de buisson avant sa dernière case (lineClear).
--
-- Porte refusée sur le chemin natif (LK04-T14 ; fiche deplacement.md, section « Porte refusée sur le chemin
-- natif ») : le chemin vanilla traverse toute porte fermée, verrouillée ou barricadée ; une porte que le PNJ ne
-- passera pas (doorRefusal : double, obstruée, cadenassée, foyer d'un autre groupe, verrouillée sans clé,
-- barricadée) arrêtait la consigne en échec. Le même calcul, à l'émission du "move", la repère sur l'itinéraire
-- "zombie" (franchissement "refused"), ou sur un itinéraire "zombie-door" (escalades à ROUTE_PENALTY, porte refusée
-- légèrement favorisée) à ROUTE_REFUSED_SLACK case au plus de la longueur du premier (chemin natif quasi égal) ;
-- l'itinéraire du PNJ ("npc", ou "detour" si DOORS_FIRST est coupé : fenêtres et clôtures sans surcoût, refus
-- infranchissables) est alors jalonné de la même façon, même sans porte ni escalade évitée. Aucun itinéraire : rien
-- n'est posé, raison « no way around the refused door(s) ... » (WARN), et le refus devant la porte reste l'issue.
-- Interrupteur AVOID_REFUSED, indépendant de DOORS_FIRST.
-- Essai solo du 2026-10-11 23:08 (fiche deplacement.md, section « Corrections après l'essai solo du 2026-10-11,
-- 23:08 ») : une fenêtre dont la case d'arrivée porte un meuble bas (isFurnitureLanding) fait tomber le corps (issue
-- "obstacle" des nœuds zombie) : fermée, elle est refusée au contact (decideWindow) ; ouverte ou fermée, les modèles
-- "zombie" la notent "refused" dans ce sens, et le même détour l'évite (même niveau seulement).
--
-- Sortir d'une maison par une porte (LK04-T15, décision de l'utilisateur du 2026-10-11 ; fiche deplacement.md,
-- section « Sortir d'un bâtiment par une porte ») : départ et destination dans deux bâtiments différents, ou l'un
-- dehors (bâtiment de la case : getBuildingDef, par la pièce seulement), et itinéraire "zombie" qui franchit une
-- fenêtre ou une clôture bordant l'un de ces bâtiments : un itinéraire "exit" (comme "npc", mais un tel franchissement
-- coûte ROUTE_EXIT_PENALTY, « infini ») est cherché dans une boîte élargie au bâtiment (ROUTE_EXIT_MARGIN) avec
-- ROUTE_EXIT_MAX_NODES cases au plus : la porte utilisable est prise quel que soit le détour. S'il franchit encore une
-- telle fenêtre (aucune porte utilisable) ou échoue, raison au journal et règle habituelle ("npc", ROUTE_PENALTY).
-- Fuite (Decisions : comportement "flee" du membre) : règle habituelle (isFleeing). Interrupteur EXIT_BY_DOOR.
-- LK04-T16 (essai solo du 2026-10-12) : destination hors d'atteinte par les règles (chambre derrière une porte
-- verrouillée sans clé) : l'itinéraire "exit" échouait et le chemin natif sortait par la fenêtre de la cuisine ;
-- désormais un itinéraire "exit-loose" (passages refusés à ROUTE_LOOSE_PENALTY) sort par la porte et s'arrête au
-- passage refusé. Itinéraire retenu s'il passe une porte et franchit moins de fenêtres ou clôtures des bâtiments que le
-- chemin natif ; porte voisine du départ : jalonnement quand même.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Obstacles"

local Obstacles = LivingKnox.Obstacles

-- Porte d'abord (LK04-T09)
Obstacles.DOORS_FIRST = true      -- règle active (coupée par les essais en jeu des fenêtres et clôtures)
Obstacles.ROUTE_PENALTY = 20      -- cases : surcoût d'une fenêtre ou d'une clôture basse pour un PNJ
Obstacles.ROUTE_MARGIN = 12       -- cases ajoutées autour de la boîte départ-destination
Obstacles.ROUTE_MAX_NODES = 4000  -- cases développées au plus par recherche
Obstacles.ROUTE_MAX_DOORS = 3     -- portes guidées au plus (deux points de passage chacune)
Obstacles.ROUTE_TREE = 5          -- cases : surcoût d'une case d'arbre ou de buisson (coût natif, SquareUpdateTask:getCost)
Obstacles.ROUTE_GAP = 1.5         -- cases : point de passage trop près du précédent ou de la destination, écarté
Obstacles.ROUTE_STEP = 4          -- cases : longueur maximale d'un tronçon entre deux points de passage
Obstacles.ROUTE_MAX_POINTS = 24   -- points de passage au plus pour un trajet guidé par une porte
Obstacles.ROUTE_ZOMBIE_CLIMB_BONUS = -0.3   -- cases : escalade du modèle "zombie" un peu favorisée (prudence)
-- Porte refusée sur le chemin natif (LK04-T14)
Obstacles.AVOID_REFUSED = true    -- détour autour d'une porte refusée (indépendant de DOORS_FIRST)
Obstacles.ROUTE_REFUSED_SLACK = 1.5   -- cases : chemin natif par une porte refusée à peine plus long que le plus court
-- Sortir d'un bâtiment (ou y entrer) par une porte, quel que soit le détour (LK04-T15)
Obstacles.EXIT_BY_DOOR = true     -- règle active (avec DOORS_FIRST)
Obstacles.ROUTE_EXIT_PENALTY = 1000   -- cases : fenêtre ou clôture bordant le bâtiment quitté ou rejoint (« infini »)
Obstacles.ROUTE_EXIT_MARGIN = 3   -- cases ajoutées autour du bâtiment à la boîte de recherche (portes éloignées)
Obstacles.ROUTE_EXIT_MAX_NODES = 8000 -- cases développées au plus par la recherche d'une sortie par une porte
Obstacles.ROUTE_LOOSE_PENALTY = 3000  -- cases : passage refusé du modèle "exit-loose" (au-delà d'une escalade de sortie)
-- Fenêtre refusée au contact (LK05-T23, campagne solo du 2026-11-15, lk.expedition : fenêtre condamnée prise par le
-- chemin natif sans que le modèle "zombie" la prévoie, même refus une minute plus tard) : pendant ce temps, tout trajet
-- du PNJ est jalonné en lignes dégagées (sans fenêtre) sur son itinéraire "npc", par les portes.
Obstacles.WINDOW_WARY_MS = 300000

local Routing = Obstacles.Routing or {}
Obstacles.Routing = Routing
Routing.items = Routing.items or {}   -- modèles, dans l'ordre d'inscription
Routing.byName = Routing.byName or {}   -- nom -> spec

local function validModel(spec)
    if type(spec) ~= "table" then return false, "spec must be a table" end
    if type(spec.name) ~= "string" or spec.name == "" then return false, "name must be a non-empty string" end
    if type(spec.edgeCost) ~= "function" then return false, "spec needs edgeCost" end
    if spec.maxNodes ~= nil and type(spec.maxNodes) ~= "function" then return false, "maxNodes must be a function" end
    if spec.vanilla and type(spec.refusedCost) ~= "function" then return false, "a vanilla model needs refusedCost" end
    return true
end

local models = LivingKnox.Registry.new("LivingKnox.Obstacles.Routing.registerModel", { key = "name", sort = false,
    validate = validModel, items = Routing.items, byKey = Routing.byName })

-- Inscrit le modèle d'itinéraire name (voir l'en-tête) ; le même nom remplace l'ancien (rechargement). Spec refusée :
-- erreur, rien n'est inscrit.
function Routing.registerModel(name, spec)
    if type(spec) == "table" then spec.name = name end
    return models:register(spec, 2)
end

-- Modèle de nom name, ou nil.
function Routing.get(name) return models:get(name) end

-- Modèles inscrits, dans l'ordre d'inscription (table vivante, à ne pas modifier).
function Routing.list() return models:list() end

local function log() return LivingKnox.Log end
local function Dir() return LivingKnox.Directives end

local function now() return getTimestampMs() end

local dist, edge, buildingOf = Obstacles.dist, Obstacles.edge, Obstacles.buildingOf

-- ---------------------------------------------------------------- porte d'abord (LK04-T09)

-- Élément du bord commun de deux cases voisines (orthogonales) : { kind = "door" | "window" | "fence" | "wall" |
-- "plain", obj, wk }. Porte (IsoDoor, porte construite, portail : getDoorTo) d'abord, puis fenêtre, fenêtre
-- construite ou cadre (windowOf), clôture basse (isFenceTo : objet enjambable et drapeau HoppableN/W de la case,
-- ci-dessous), enfin mur, fenêtre bloquée, porte bloquée ou escalier (isBlockedTo, IsoGridSquare.java:935-941 ; une clôture basse
-- est aussi un mur pour isWallTo, d'où l'ordre).
-- Clôture basse du bord commun des cases voisines (orthogonales) sq et nb TELLE QUE LE MOTEUR LA VOIT (essai solo du
-- 2026-10-11 23:08, bord 10747,9538,0,W : mur walls_interior_house_02_48 et comptoir location_restaurant_pileocrepe_01_56
-- « HoppableW » sur le même bord). isHoppableTo lit les OBJETS (IsoGridSquare.java:1043-1049, IsoObject.java:3329-3349)
-- et rend vrai ; mais RecalcProperties retire HoppableW/N (et canPathW/N) des drapeaux de la case dès qu'un autre objet
-- du bord pose collideW/N sans Hoppable (IsoGridSquare.java:6144-6179, 6233-6236), et le chemin natif (bit de clôture
-- tiré du drapeau de case, SquareUpdateTask.java:129-137) comme l'enjambée à la collision (IsoMovingObject.java:
-- 1565-1582) ne lisent que ce drapeau : ce bord est un mur. Le drapeau est porté par la case est (bord W) ou sud (N).
function Obstacles.isFenceTo(sq, nb)
    if not sq:isHoppableTo(nb) then return false end
    if nb:getX() ~= sq:getX() then
        local east = nb:getX() > sq:getX() and nb or sq
        return east:has(IsoFlagType.HoppableW) == true
    end
    local south = nb:getY() > sq:getY() and nb or sq
    return south:has(IsoFlagType.HoppableN) == true
end

local function edgeElement(sq, nb)
    local door = sq:getDoorTo(nb)
    if door ~= nil then return { kind = "door", obj = door } end
    local w, wk = Obstacles.windowOf(sq, nb)
    if w ~= nil then return { kind = "window", obj = w, wk = wk } end
    if Obstacles.isFenceTo(sq, nb) then return { kind = "fence" } end
    if sq:isBlockedTo(nb) then return { kind = "wall" } end
    return { kind = "plain" }
end

-- Raison (anglais) pour laquelle le PNJ npcId ne passera pas la porte d, ou nil s'il la passe debout (ouverte, ou
-- décision "open" de decide) ; portail fermé (porte basse) : nil, il est enjambé (LK04-T08). Porte ouverte mais
-- barricadée : refusée, comme dans check (LK04-T14).
local function doorRefusal(npcId, d, sqA, sqB, from)
    if d:isBarricaded() then return "barricaded door" end
    if Obstacles.isOpen(d) or Obstacles.isLowGate(d) then return nil end
    local act, why = Obstacles.decide(npcId, d, sqA, sqB, nil, from)
    if act == "open" then return nil end
    return why or "door refused"
end
Obstacles.doorRefusal = doorRefusal

-- Règles de passage partagées par les modèles d'itinéraire (fichiers du dossier Routing/) pour un bord r de sorte
-- "door", "window" ou "fence" (cases sqA ouest ou nord, sqB ; from : case d'où le bord est abordé, pour l'ouverture de
-- l'intérieur d'une porte verrouillée, LK04-T17).

-- Chemin vanilla d'un corps (fiche deplacement.md, section 2) : portes, fenêtres et clôtures basses traversées, portail
-- fermé enjambé ; une porte que le PNJ ne passera pas (doorRefusal) est franchie comme les autres mais marquée
-- "refused" (LK04-T14), au coût refused ; toute escalade coûte climb.
function Routing.bodyCost(r, npcId, sqA, sqB, from, refused, climb)
    if r.kind == "door" and (Obstacles.isOpen(r.obj) or not Obstacles.isLowGate(r.obj)) then
        if doorRefusal(npcId, r.obj, sqA, sqB, from) ~= nil then return refused, "refused" end
        return 0, "door"
    end
    return climb, "climb"
end

-- Règle porte d'abord (LK04-T09) : porte passée debout si ouverte ou décision "open" de decide, portail refusé enjambé
-- au coût P comme une clôture, porte refusée et barricade infranchissables ; fenêtre au coût P si elle n'arrête pas le
-- corps ou si decideWindow l'ouvre, sinon infranchissable ; clôture basse au coût P.
function Routing.doorFirstCost(r, npcId, sqA, sqB, from, P)
    local k = r.kind
    if k == "door" then
        local d = r.obj
        if d:isBarricaded() then return nil end
        if Obstacles.isOpen(d) or Obstacles.decide(npcId, d, sqA, sqB, nil, from) == "open" then return 0, "door" end
        if Obstacles.isLowGate(d) then return P, "climb" end   -- portail refusé : enjambé, comme une clôture
        return nil
    elseif k == "window" then
        local w = r.obj
        if w:isBarricaded() then return nil end
        if not Obstacles.windowBlocks(w, r.wk) or Obstacles.decideWindow(npcId, w, r.wk, sqA, sqB, sqB) == "open" then
            return P, "climb"
        end
        return nil
    end
    return P, "climb"   -- clôture basse
end

-- Passage du bord r (cases sqA ouest ou nord, sqB) pour le modèle d'itinéraire de nom mode : bord sans élément 0,
-- mur infranchissable, sinon edgeCost du modèle (voir l'en-tête ; modèle inconnu : infranchissable).
local function edgeCost(r, mode, npcId, sqA, sqB, exitKeys, from)
    local k = r.kind
    if k == "plain" then return 0 end
    if k == "wall" then return nil end
    local m = models:get(mode)
    if m == nil then return nil end
    return m.edgeCost(r, npcId, sqA, sqB, exitKeys, from)
end
Routing.edgeCost = edgeCost
Routing.edgeElement = edgeElement


local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- Praticabilité d'une case pour l'itinéraire : 0 impraticable (absente, sans sol, mur plein, meuble), 1 libre
-- (isFree(false)), 2 arbre (HasTree) ou buisson (hasBush, haie basse comprise : isFree la dit libre), surcoût
-- ROUTE_TREE, 3 meuble bas « solidtrans » (comptoir, cuisinière,
-- réfrigérateur...) sur une case qui borde une fenêtre, un cadre ou une clôture basse. Le chemin vanilla ne tient une
-- case solidtrans pour pleine que loin d'une fenêtre ou d'une clôture (J/pathfind/Square.java:60-62, isReallySolid :
-- bit 1024 et ni isAdjacentToWindow ni isAdjacentToHoppable ; bits posés par SquareUpdateTask.java:94-105, 139-150) :
-- un zombie passe donc par la fenêtre au-dessus d'un comptoir (issue "obstacle" de l'escalade). isFree(false) la dit
-- impraticable (IsoGridSquare.java:2894-2915) : sans cette valeur, le modèle "zombie" ne voyait pas ce raccourci
-- (essai solo du 2026-10-11, fenêtre 10693,9387 N au-dessus du comptoir 10693,9386).
-- Buisson (essai solo du 2026-10-11 23:08, haie f_bushes_1 le long de x = 10753) : le chemin natif ajoute 5 à toute
-- case d'arbre ou de buisson où il entre (SquareUpdateTask.java:260-266, SearchNode.java:162-164 ; hasBush :
-- IsoGridSquare.java:2382-2392, IsoObject.java:6073-6075) ; une case de buisson comptée libre laissait passer pour
-- dégagé un tronçon que le chemin natif contournait par une fenêtre.
local function squareKind(sq)
    if sq == nil then return 0 end
    if sq:isFree(false) then
        if sq:hasBush() then return 2 end
        return 1
    end
    if not sq:TreatAsSolidFloor() then return 0 end
    if sq:HasTree() then return 2 end
    if sq:isSolidTrans() and not sq:isSolid() and (sq:isAdjacentToWindow() or sq:isAdjacentToHoppable()) then
        return 3
    end
    return 0
end
Obstacles.squareKind = squareKind

-- Itinéraire de la case du point (x0, y0) à la case (tx, ty) au niveau z pour le modèle mode (voir edgeCost), sur les
-- cases chargées seulement (getGridSquare rend nil ailleurs). A* 8 voisins : pas orthogonal 1 + surcoût du bord, pas
-- diagonal 1,414 seulement entre quatre bords sans élément et deux cases praticables ; case d'arbre + ROUTE_TREE.
-- Rend la liste des cases { { x, y, cross }, ... } du départ à la destination (cross : franchissement du pas qui y
-- mène), et le nombre de cases développées ; nil, nombre et raison si aucun itinéraire. shared (facultatif) : table
-- réutilisée par un second appel de mêmes départ, destination et niveau (cases, praticabilité, éléments des bords).
-- shared.box (facultatif) : boîte { minx, miny, maxx, maxy } imposée (sortie d'un bâtiment, LK04-T15), sinon posée
-- au premier appel (départ-destination élargie de ROUTE_MARGIN) ; shared.exitKeys : bâtiments du modèle "exit".
-- Modèle inconnu : nil, 0 et la raison.
function Obstacles.findRoute(npcId, x0, y0, tx, ty, z, mode, shared)
    local model = models:get(mode)
    if model == nil then return nil, 0, "unknown route model " .. tostring(mode) end
    local cell = getCell()
    local sx, sy = math.floor(x0), math.floor(y0)
    shared = shared or {}
    local box = shared.box
    if box == nil then
        local m = Obstacles.ROUTE_MARGIN
        box = { math.min(sx, tx) - m, math.min(sy, ty) - m, math.max(sx, tx) + m, math.max(sy, ty) + m }
        shared.box = box
    end
    local minx, miny, maxx, maxy = box[1], box[2], box[3], box[4]
    local maxNodes = model.maxNodes ~= nil and model.maxNodes() or Obstacles.ROUTE_MAX_NODES
    local exitKeys = shared.exitKeys
    local H = maxy - miny + 1
    local function idx(x, y) return (x - minx) * H + (y - miny) + 1 end
    shared.sqs, shared.walk, shared.elems = shared.sqs or {}, shared.walk or {}, shared.elems or {}
    local sqs, walk, elems, edges = shared.sqs, shared.walk, shared.elems, {}
    local vanilla = model.vanilla == true
    local function square(x, y)
        local i = idx(x, y)
        local sq = sqs[i]
        if sq == nil then
            sq = cell:getGridSquare(x, y, z) or false
            sqs[i] = sq
        end
        return sq or nil
    end
    -- 0 : impraticable, 1 : libre, 2 : arbre, 3 : meuble bas sous une fenêtre ou contre une clôture basse (praticable
    -- pour les seuls modèles du chemin natif, vanilla : voir squareKind).
    local function walkable(x, y)
        local i = idx(x, y)
        local v = walk[i]
        if v == nil then
            v = squareKind(square(x, y))
            walk[i] = v
        end
        if v == 3 and not vanilla then return 0 end
        return v
    end
    -- Pas orthogonal (dx, dy) depuis (x, y) : surcoût et franchissement, ou nil (bord infranchissable).
    local function cross(x, y, dx, dy)
        local ax, ay, bx, by = x, y, x + dx, y + dy
        if dx < 0 or dy < 0 then ax, ay, bx, by = bx, by, x, y end
        local key = idx(bx, by) * 2 + (dx ~= 0 and 0 or 1)
        -- Sens compris (LK04-T17) : une porte verrouillée s'ouvre de l'intérieur seulement (opensFromInside).
        local dkey = key * 2 + ((dx < 0 or dy < 0) and 1 or 0)
        local c = edges[dkey]
        if c == nil then
            local sqA, sqB = square(ax, ay), square(bx, by)
            local cost, what, win
            if sqA ~= nil and sqB ~= nil then
                local el = elems[key]
                if el == nil then
                    el = edgeElement(sqA, sqB)
                    elems[key] = el
                end
                cost, what = edgeCost(el, mode, npcId, sqA, sqB, exitKeys, square(x, y))
                if what == "refused" then shared.sawRefused = true end   -- porte refusée vue (LK04-T14)
                if what == "climb" and el.kind == "window" and vanilla then win = true end
            end
            if cost ~= nil then c = { cost, what, win } else c = false end
            edges[dkey] = c
        end
        if c == false then return nil end
        -- Fenêtre vers un meuble bas (modèles du chemin natif, selon le sens) : le chemin natif la prend, mais l'escalade
        -- finit au sol (isFurnitureLanding) : franchissement refusé, comme une porte refusée (détour LK04-T14).
        if c[3] and Obstacles.isFurnitureLanding(square(x + dx, y + dy)) then
            shared.sawRefused = true
            return model.refusedCost(), "refused"
        end
        return c[1], c[2]
    end
    local function plain(x, y, dx, dy)
        local c, what = cross(x, y, dx, dy)
        return c == 0 and what == nil
    end
    local function heur(x, y)
        local dx, dy = math.abs(x - tx), math.abs(y - ty)
        return math.max(dx, dy) + 0.4142 * math.min(dx, dy)
    end
    -- Tas binaire (f croissant), tableaux parallèles.
    local hf, hi, hn = {}, {}, 0
    local function push(f, i)
        hn = hn + 1
        local c = hn
        while c > 1 do
            local p = math.floor(c / 2)
            if hf[p] <= f then break end
            hf[c], hi[c] = hf[p], hi[p]
            c = p
        end
        hf[c], hi[c] = f, i
    end
    local function pop()
        local i = hi[1]
        local lf, li = hf[hn], hi[hn]
        hf[hn], hi[hn] = nil, nil
        hn = hn - 1
        if hn > 0 then
            local c = 1
            while true do
                local l = c * 2
                if l > hn then break end
                if l + 1 <= hn and hf[l + 1] < hf[l] then l = l + 1 end
                if hf[l] >= lf then break end
                hf[c], hi[c] = hf[l], hi[l]
                c = l
            end
            hf[c], hi[c] = lf, li
        end
        return i
    end
    local start, goal = idx(sx, sy), idx(tx, ty)
    local g, from, via, closed = { [start] = 0 }, {}, {}, {}
    push(heur(sx, sy), start)
    local n = 0
    while hn > 0 do
        local i = pop()
        if not closed[i] then
            closed[i] = true
            if i == goal then
                local out, j = {}, i
                while j ~= nil do
                    out[#out + 1] = { x = minx + math.floor((j - 1) / H), y = miny + (j - 1) % H, cross = via[j] }
                    j = from[j]
                end
                local path = {}
                for k = #out, 1, -1 do path[#path + 1] = out[k] end
                return path, n
            end
            n = n + 1
            if n > maxNodes then return nil, n, "more than " .. maxNodes .. " squares" end
            local x, y = minx + math.floor((i - 1) / H), miny + (i - 1) % H
            for _, d in ipairs(DIRS) do
                local nx, ny = x + d[1], y + d[2]
                if nx >= minx and nx <= maxx and ny >= miny and ny <= maxy then
                    local w = walkable(nx, ny)
                    if w > 0 then
                        local cost, what
                        if d[1] ~= 0 and d[2] ~= 0 then
                            if walkable(x + d[1], y) > 0 and walkable(x, y + d[2]) > 0 and plain(x, y, d[1], 0)
                                and plain(x, y, 0, d[2]) and plain(x + d[1], y, 0, d[2]) and plain(x, y + d[2], d[1], 0) then
                                cost = 1.4142
                            end
                        else
                            local c
                            c, what = cross(x, y, d[1], d[2])
                            if c ~= nil then cost = 1 + c end
                        end
                        if cost ~= nil then
                            if w == 2 then cost = cost + Obstacles.ROUTE_TREE end
                            local j = idx(nx, ny)
                            local ng = g[i] + cost
                            if not closed[j] and (g[j] == nil or ng < g[j] - 1e-9) then
                                g[j], from[j], via[j] = ng, i, what
                                push(ng + heur(nx, ny), j)
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, n, "no route in the loaded squares"
end

-- Escalades, portes passées debout et portes refusées (modèles zombie) d'un itinéraire.
local function climbsOf(path)
    local c, d, f = 0, 0, 0
    for _, p in ipairs(path) do
        if p.cross == "climb" then c = c + 1 elseif p.cross == "door" then d = d + 1
        elseif p.cross == "refused" then f = f + 1 end
    end
    return c, d, f
end

-- Longueur d'un itinéraire en cases (pas orthogonal 1, diagonal 1,414), sans les surcoûts.
local function pathLength(path)
    local n = 0
    for i = 2, #path do
        local p, q = path[i - 1], path[i]
        n = n + ((p.x ~= q.x and p.y ~= q.y) and 1.4142 or 1)
    end
    return n
end

-- Portes refusées (et fenêtres vers un meuble bas) franchies par l'itinéraire path (niveau z) : { { key, why, door,
-- window }, ... } (LK04-T14). loose (itinéraire "exit-loose", LK04-T16) : raison d'une fenêtre lue par decideWindow.
local function refusedOf(npcId, path, z, loose)
    local out, cell = {}, getCell()
    for i = 2, #path do
        if path[i].cross == "refused" then
            local p, q = path[i - 1], path[i]
            local ax, ay = math.min(p.x, q.x), math.min(p.y, q.y)
            local de = edge(ax, ay, z, p.x ~= q.x and "W" or "N")
            local sqA, sqB = cell:getGridSquare(ax, ay, z), cell:getGridSquare(de.bx, de.by, z)
            local door = sqA and sqB and sqA:getDoorTo(sqB) or nil
            local why = door and doorRefusal(npcId, door, sqA, sqB, cell:getGridSquare(p.x, p.y, z)) or nil
            local win = nil
            if door == nil and sqA ~= nil and sqB ~= nil then
                local wk
                win, wk = Obstacles.windowOf(sqA, sqB)
                if win ~= nil and loose then
                    local _, wwhy = Obstacles.decideWindow(npcId, win, wk, sqA, sqB, cell:getGridSquare(q.x, q.y, z))
                    why = wwhy or "window refused"
                elseif win ~= nil then
                    why = "window over furniture"
                end
            end
            out[#out + 1] = { key = de.key, door = door, window = win, why = why or "door refused" }
        end
    end
    return out
end

-- Texte des passages refusés : "door(s) 10747,9537,0,W (garage door not handled)", ou "door(s) or window(s) ..." si
-- une fenêtre en est.
local function refusedText(list)
    local parts, noun = {}, "door(s) "
    for i, r in ipairs(list) do
        parts[i] = r.key .. " (" .. tostring(r.why) .. ")"
        if r.window ~= nil then noun = "door(s) or window(s) " end
    end
    return noun .. table.concat(parts, ", ")
end

-- Ligne dégagée pour un PNJ du point (ax, ay) au point (bx, by), au niveau z : chaque case traversée après celle de
-- départ est praticable (squareKind 1 ou 2 : ni meuble, ni mur plein ; 2, arbre ou buisson, seulement pour la
-- dernière case : coût natif, voir squareKind) et chaque bord franchi est sans élément, sauf
-- une porte ou un portail que le PNJ passe debout (edgeCost "npc" rend "door"). Une ligne qui passe par un coin exige
-- les deux cases et les quatre bords du coin libres (règle diagonale de findRoute). Échantillonnée tous les 0,1 case.
-- cache : table facultative partagée entre appels de même niveau (cases, praticabilité, bords).
-- mode : modèle des portes (edgeCost), "npc" par défaut ; "trapped" pour un dernier recours (LK04-T20). Un cache ne
-- sert qu'à un seul mode.
local function lineClear(npcId, ax, ay, bx, by, z, cache, mode)
    local cell = getCell()
    cache = cache or {}
    local function sqAt(x, y)
        local k = x .. "," .. y
        local v = cache[k]
        if v == nil then
            v = cell:getGridSquare(x, y, z) or false
            cache[k] = v
        end
        return v or nil
    end
    local function free(x, y)
        local k = "f" .. x .. "," .. y
        local v = cache[k]
        if v == nil then
            local w = squareKind(sqAt(x, y))
            v = w == 1 or w == 2
            cache[k] = v
        end
        return v
    end
    -- Pas orthogonal de la case (x, y) à la case (x + dx, y + dy).
    local function pass(x, y, dx, dy)
        local k = "e" .. x .. "," .. y .. "," .. dx .. "," .. dy
        local v = cache[k]
        if v == nil then
            v = false
            local sA, sB = sqAt(x, y), sqAt(x + dx, y + dy)
            if sA ~= nil and sB ~= nil and free(x + dx, y + dy) then
                if dx < 0 or dy < 0 then sA, sB = sB, sA end
                local el = edgeElement(sA, sB)
                if el.kind == "plain" then
                    v = true
                elseif el.kind == "door" then
                    local c, what = edgeCost(el, mode or "npc", npcId, sA, sB, nil, sqAt(x, y))
                    v = c ~= nil and what == "door"
                end
            end
            cache[k] = v
        end
        return v
    end
    -- Case d'arbre ou de buisson (squareKind 2) : le chemin natif paie ROUTE_TREE pour y entrer. Toléré pour la
    -- dernière case de la ligne (tout chemin y entre), refusé avant : un détour (par une fenêtre) pourrait coûter moins.
    local function costly(x, y)
        local k = "c" .. x .. "," .. y
        local v = cache[k]
        if v == nil then
            v = squareKind(sqAt(x, y)) == 2
            cache[k] = v
        end
        return v
    end
    local ex, ey = math.floor(bx), math.floor(by)
    local n = math.max(1, math.ceil(dist(ax, ay, bx, by) * 10))
    local cx, cy = math.floor(ax), math.floor(ay)
    for i = 1, n do
        local nx, ny = math.floor(ax + (bx - ax) * i / n), math.floor(ay + (by - ay) * i / n)
        if nx ~= cx or ny ~= cy then
            local dx, dy = nx - cx, ny - cy
            if math.abs(dx) > 1 or math.abs(dy) > 1 then return false end
            if dx ~= 0 and dy ~= 0 then
                if not (pass(cx, cy, dx, 0) and pass(cx + dx, cy, 0, dy) and pass(cx, cy, 0, dy)
                    and pass(cx, cy + dy, dx, 0)) then
                    return false
                end
            elseif not pass(cx, cy, dx, dy) then
                return false
            end
            if (nx ~= ex or ny ~= ey) and costly(nx, ny) then return false end
            cx, cy = nx, ny
        end
    end
    return true
end
Obstacles.lineClear = lineClear

-- Vrai si le PNJ npcId est en fuite : état de décision courant "flee" (LivingKnox.Decisions.state.members, posé avant
-- l'émission du "move" de fuite, LK_Decisions.evaluate puis apply). Limite : un "move" émis par un autre module
-- (consigne externe) pendant que cet état est encore "flee" est traité comme une fuite (LK04-T15).
function Obstacles.isFleeing(npcId)
    local D = LivingKnox.Decisions
    local st = D ~= nil and D.state ~= nil and D.state.members ~= nil and D.state.members[npcId] or nil
    return st ~= nil and st.b == "flee"
end

-- Sortie d'un bâtiment (LK04-T15) : départ (x0, y0) et destination (tx, ty) au niveau z dans deux bâtiments
-- différents, ou l'un dehors. Rend nil (même bâtiment, ou dehors tous les deux, ou règle coupée), sinon { keys
-- (getIDString -> vrai), text, box (boîte de recherche élargie aux bâtiments de ROUTE_EXIT_MARGIN) }.
function Obstacles.exitOf(x0, y0, tx, ty, z)
    if not Obstacles.EXIT_BY_DOOR or not Obstacles.DOORS_FIRST then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local sx, sy = math.floor(x0), math.floor(y0)
    local sqA, sqB = cell:getGridSquare(sx, sy, z), cell:getGridSquare(tx, ty, z)
    local da = sqA ~= nil and sqA:getBuildingDef() or nil
    local db = sqB ~= nil and sqB:getBuildingDef() or nil
    local ia, ib = da and da:getIDString() or nil, db and db:getIDString() or nil
    if ia == ib then return nil end
    local m = Obstacles.ROUTE_MARGIN
    local box = { math.min(sx, tx) - m, math.min(sy, ty) - m, math.max(sx, tx) + m, math.max(sy, ty) + m }
    local keys, parts = {}, {}
    local E = Obstacles.ROUTE_EXIT_MARGIN
    for _, p in ipairs({ { da, ia, "out of" }, { db, ib, "into" } }) do
        local def, id = p[1], p[2]
        if def ~= nil then
            keys[id] = true
            parts[#parts + 1] = p[3] .. " building " .. id
            box[1] = math.min(box[1], def:getX() - E)
            box[2] = math.min(box[2], def:getY() - E)
            box[3] = math.max(box[3], def:getX2() - 1 + E)
            box[4] = math.max(box[4], def:getY2() - 1 + E)
        end
    end
    return { keys = keys, text = table.concat(parts, " and "), box = box }
end

-- Escalades d'un itinéraire dont une case est dans un bâtiment de keys (LK04-T15).
local function exitClimbsOf(path, z, keys)
    local n, cell = 0, getCell()
    for i = 2, #path do
        if path[i].cross == "climb" then
            local p, q = path[i - 1], path[i]
            local ia, ib = buildingOf(cell:getGridSquare(p.x, p.y, z)), buildingOf(cell:getGridSquare(q.x, q.y, z))
            if (ia ~= nil and keys[ia]) or (ib ~= nil and keys[ib]) then n = n + 1 end
        end
    end
    return n
end

-- Itinéraire du PNJ pour planDoorRoute (D-OBS-06 : cascade sortie par une porte, règle habituelle, dernier recours),
-- sur les cases de shared, itinéraire du chemin natif zr, sortie exit (exitOf, ou nil) et modèle mode ("npc" ou
-- "detour"). Complète info (nodes, exitClimbs, loose, noExitDoor, lastResort). Rend l'itinéraire (ou nil), la raison
-- de son absence, vrai s'il sort par une porte (exitUsed) et vrai s'il est de dernier recours (trapped).
local function chooseRoute(npcId, x0, y0, tx, ty, z, shared, exit, zr, mode, info)
    -- Sortie (ou entrée) par une porte quel que soit le détour (LK04-T15) : seulement si l'itinéraire "zombie"
    -- franchit une fenêtre ou une clôture du bâtiment ; aucune porte utilisable : règle habituelle, raison au journal.
    -- LK04-T16 (essai solo du 2026-10-12, lk-36 : cuisine du foyer, chambre visée derrière une porte verrouillée sans
    -- clé dans un autre bâtiment) : (1) destination hors d'atteinte par les règles ("exit" sans itinéraire) : itinéraire
    -- "exit-loose", qui sort quand même par une porte et s'arrête au passage refusé (refus au contact, comme avant) ;
    -- (2) itinéraire retenu dès qu'il passe une porte et franchit moins de fenêtres ou clôtures des bâtiments que le
    -- chemin natif (porte pour sortir du foyer, fenêtre seulement pour entrer dans un bâtiment sans porte utilisable),
    -- et non plus seulement sans aucune.
    local r, n, why2
    local exitUsed, loose, trapped = false, nil, false
    if exit ~= nil and exitClimbsOf(zr, z, exit.keys) > 0 then
        info.exitClimbs = exitClimbsOf(zr, z, exit.keys)
        r, n, why2 = Obstacles.findRoute(npcId, x0, y0, tx, ty, z, "exit", shared)
        info.nodes = info.nodes + n
        if r == nil then
            local lr, ln = Obstacles.findRoute(npcId, x0, y0, tx, ty, z, "exit-loose", shared)
            info.nodes = info.nodes + ln
            if lr ~= nil then
                r = lr
                loose = refusedOf(npcId, lr, z, true)
            end
        end
        local _, edoors = 0, 0
        if r ~= nil then _, edoors = climbsOf(r) end
        if r ~= nil and edoors > 0 and exitClimbsOf(r, z, exit.keys) < info.exitClimbs then
            exitUsed = true
            info.loose = loose
        else
            -- LK04-T20 : raison lue AVANT d'écarter l'itinéraire (le journal disait « no route in the loaded squares »
            -- alors qu'un itinéraire "exit-loose" existait) ; un itinéraire "exit-loose" sans aucune porte passée
            -- (premier passage de sortie déjà refusé, porte du foyer d'un autre groupe) ne sort par aucune porte.
            local cause
            if r == nil then
                cause = "exit route: " .. tostring(why2)
            elseif loose ~= nil and edoors == 0 then
                cause = "every way out is refused: " .. refusedText(loose)
            else
                cause = "every way crosses a window or a fence of the building"
            end
            info.noExitDoor = cause
            log().info("npc %s: no usable door %s in the loaded squares (%s): window or fence as a last resort",
                tostring(npcId), exit.text, cause)
            r = nil
        end
    end
    if r == nil then
        r, n, why2 = Obstacles.findRoute(npcId, x0, y0, tx, ty, z, mode, shared)
        info.nodes = info.nodes + n
    end
    -- LK04-T20 (campagne MP du 2026-10-15, lk-7) : PNJ enfermé (aucune porte utilisable pour sortir, aucun
    -- itinéraire "npc") : itinéraire "trapped" (fenêtre verrouillée ou du foyer d'un autre groupe ouverte de
    -- l'intérieur, jamais une barricade), jalonné comme une sortie par une porte (case avant et après chaque
    -- franchissement) ; la consigne porte e.lr (Directives.moveTo) pour que les décisions au contact l'autorisent.
    -- Avant : liste vide, chemin natif gardé (qui peut viser une fenêtre barricadée), refus au contact.
    -- Aussi quand le chemin natif ne franchit qu'une porte refusée (aucune escalade : pas de recherche "exit").
    if r == nil and exit ~= nil then
        info.noExitDoor = info.noExitDoor or ("npc route: " .. tostring(why2))
        local tr, tn, twhy = Obstacles.findRoute(npcId, x0, y0, tx, ty, z, "trapped", shared)
        info.nodes = info.nodes + tn
        if tr ~= nil then
            r, trapped = tr, true
            info.lastResort = true
        else
            why2 = tostring(why2) .. "; trapped route: " .. tostring(twhy)
        end
    end
    return r, why2, exitUsed, trapped
end

-- Vrai si le PNJ npcId a été refusé au contact d'une fenêtre depuis moins de WINDOW_WARY_MS (LK05-T23).
local function waryOfWindows(npcId)
    local t = Obstacles.windowRefusedAt ~= nil and Obstacles.windowRefusedAt[npcId] or nil
    return t ~= nil and now() - t < Obstacles.WINDOW_WARY_MS
end

-- Points de passage « porte d'abord » d'un "move" du PNJ npcId, du point (x0, y0) à la case (tx, ty) au niveau z (même
-- niveau que le corps ; voir l'en-tête). Rend une liste { { x, y }, ... } (vide : aucun guidage, le chemin vanilla
-- reste seul) et un relevé { reason, climbs (itinéraire du zombie), npcClimbs, doors, doorEdges (bords des portes
-- guidées, avec door), steps (points de passage), extra (points de jalonnement, hors portes), blind (tronçons sans
-- ligne dégagée), unsafe (raison d'un jalonnement abandonné), nodes, ms, noExitDoor (raison : aucune porte pour
-- sortir), lastResort (vrai : itinéraire "trapped" de dernier recours, LK04-T20), climbEdges (bords des escalades
-- jalonnées en dernier recours) }.
function Obstacles.planDoorRoute(npcId, x0, y0, tx, ty, z)
    local t0 = now()
    local info = { nodes = 0 }
    local function done(out, reason)
        info.reason = reason
        info.ms = now() - t0
        local st = Obstacles.stats
        st.routes = (st.routes or 0) + 1
        st.routeNodes = info.nodes
        st.routeMs = info.ms
        if info.ms > (st.routeMaxMs or 0) then st.routeMaxMs = info.ms end
        if #out > 0 then st.routedByDoor = (st.routedByDoor or 0) + 1 end
        return out, info
    end
    local avoid = Obstacles.AVOID_REFUSED == true
    if not Obstacles.DOORS_FIRST and not avoid then return done({}, "door-first rule off") end
    if getCell() == nil then return done({}, "no cell") end
    local shared = {}
    -- Sortie d'un bâtiment par une porte (LK04-T15) : boîte élargie au bâtiment pour tous les calculs de ce trajet.
    local exit = Obstacles.exitOf(x0, y0, tx, ty, z)
    if exit ~= nil and Obstacles.isFleeing(npcId) then
        info.exit = "fleeing: shortest way kept " .. exit.text
        exit = nil
    end
    if exit ~= nil then
        shared.box, shared.exitKeys = exit.box, exit.keys
        info.exit = exit.text
    end
    info.waryOfWindows = waryOfWindows(npcId)   -- LK05-T23 : pour le journal, même si aucun itinéraire n'est trouvé
    local zr, zn, why = Obstacles.findRoute(npcId, x0, y0, tx, ty, z, "zombie", shared)
    info.nodes = zn
    if zr == nil then return done({}, "zombie route: " .. tostring(why)) end
    local zclimbs, _, zrefused = climbsOf(zr)
    info.climbs = zclimbs
    -- Porte refusée sur le chemin natif (LK04-T14) : sur l'itinéraire du modèle "zombie", ou sur celui d'un chemin
    -- natif qui préférerait une porte refusée (modèle "zombie-door") pour au plus ROUTE_REFUSED_SLACK cases de plus
    -- (essai solo du 2026-10-11 22:30 : corps parti du coin de sa case, porte de garage voisine de la clôture prise par
    -- le chemin natif pour 0,8 case de plus). Ce second calcul n'a lieu que si l'itinéraire escalade ou si une porte
    -- refusée a été vue pendant le premier.
    local refused = {}
    if avoid then
        if zrefused > 0 then
            refused = refusedOf(npcId, zr, z)
        elseif info.climbs > 0 or shared.sawRefused then
            local dr, dn = Obstacles.findRoute(npcId, x0, y0, tx, ty, z, "zombie-door", shared)
            info.nodes = info.nodes + dn
            if dr ~= nil and pathLength(dr) <= pathLength(zr) + Obstacles.ROUTE_REFUSED_SLACK + 1e-6 then
                refused = refusedOf(npcId, dr, z)
            end
        end
    end
    local risk = #refused > 0
    if risk then info.refused = refused end
    if not Obstacles.DOORS_FIRST and not risk then return done({}, "door-first rule off") end
    local wary = info.climbs == 0 and not risk and waryOfWindows(npcId)
    info.wary = wary
    if info.climbs == 0 and not risk and not wary then return done({}, "no window, low fence or closed gate on the way") end
    local mode = Obstacles.DOORS_FIRST and "npc" or "detour"
    local r, why2, exitUsed, trapped = chooseRoute(npcId, x0, y0, tx, ty, z, shared, exit, zr, mode, info)
    if r == nil then
        if risk then
            local text = "no way around the refused " .. refusedText(refused) .. ": " .. mode .. " route: "
                .. tostring(why2)
            log().warn("npc %s: %s", tostring(npcId), text)
            return done({}, text)
        end
        return done({}, "npc route: " .. tostring(why2))
    end
    local climbs, doors = climbsOf(r)
    info.npcClimbs, info.doors = climbs, doors
    if not risk and not exitUsed and not trapped and not wary and (doors == 0 or climbs >= info.climbs) then
        return done({}, "no usable door or gate within " .. Obstacles.ROUTE_PENALTY .. " squares of detour")
    end
    local guided = exitUsed or trapped or wary   -- points de passage gardés près du départ et de la destination
    local marks, used = {}, 0                              -- indices de r
    local outward = {}                                     -- indice de la case juste après une escalade -> pas
    info.doorEdges = {}
    for i = 2, #r do
        -- Dernier recours (LK04-T20) : fenêtres et clôtures jalonnées comme les portes.
        local mark = r[i].cross == "door" or (trapped and r[i].cross == "climb")
        if mark and used < Obstacles.ROUTE_MAX_DOORS then
            used = used + 1
            local p, q = r[i - 1], r[i]
            local ax, ay = math.min(p.x, q.x), math.min(p.y, q.y)
            local de = edge(ax, ay, z, p.x ~= q.x and "W" or "N")
            local sqA = getCell():getGridSquare(ax, ay, z)
            if r[i].cross == "door" then
                de.door = sqA and sqA:getDoorTo(getCell():getGridSquare(de.bx, de.by, z)) or nil
                info.doorEdges[#info.doorEdges + 1] = de
            else
                info.climbEdges = info.climbEdges or {}
                info.climbEdges[#info.climbEdges + 1] = de
            end
            marks[#marks + 1] = i - 1                      -- case avant la porte
            local after = i
            -- Une case plus loin si libre ; sortie par une porte (LK04-T16) : jamais la destination elle-même.
            -- Escalade de dernier recours (LK04-T20) : seulement dans le prolongement du franchissement (point à deux
            -- cases du bord, qu'un corps arrêté contre la fenêtre fermée n'atteint pas à ARRIVE près du mauvais côté).
            local further = i + 1 <= #r and r[i + 1].cross == nil and (i + 1 < #r or not guided)
            if further and r[i].cross == "climb" then
                further = r[i + 1].x - q.x == q.x - p.x and r[i + 1].y - q.y == q.y - p.y
            end
            if further then after = i + 1 end
            if after == i and r[i].cross == "climb" then outward[i] = { q.x - p.x, q.y - p.y } end
            marks[#marks + 1] = after
        end
    end
    local GAP = Obstacles.ROUTE_GAP
    local function d2(a, b) return dist(r[a].x + 0.5, r[a].y + 0.5, r[b].x + 0.5, r[b].y + 0.5) end
    -- Sortie par une porte (LK04-T16) : cases de porte gardées même près du départ ou de la destination (fenêtre
    -- voisine : le chemin natif d'un point écarté au suivant la prendrait).
    local keep, lx, ly = { 1 }, x0, y0
    for _, k in ipairs(marks) do
        local cx, cy = r[k].x + 0.5, r[k].y + 0.5
        if k > keep[#keep] and k < #r and (guided or (dist(lx, ly, cx, cy) >= GAP and d2(k, #r) >= GAP)) then
            keep[#keep + 1] = k
            lx, ly = cx, cy
        end
    end
    -- Sortie par une porte (LK04-T16) : jamais rendu au chemin natif, qui prendrait la fenêtre voisine (porte à côté
    -- du départ ou de la destination : jalonnement seul, sans point de porte).
    if #keep == 1 and not risk and not guided then return done({}, "door next to the start or the destination") end
    keep[#keep + 1] = #r
    -- Jalonnement (essais solo du 2026-10-11, rstest-1011) : entre deux points, le corps suit le chemin vanilla, que
    -- Lua ne lit pas et que le modèle "zombie" ne prédit pas toujours (fenêtre au-dessus d'un comptoir, squareKind).
    -- Au lieu de prédire ce chemin, tout l'itinéraire du PNJ est jalonné : depuis le corps puis depuis chaque point, le
    -- point suivant est la case la plus loin de l'itinéraire, sans dépasser la prochaine porte (case avant ou après),
    -- à ROUTE_STEP cases au plus, à ROUTE_GAP au moins de la destination (sauf la destination elle-même) et en ligne
    -- dégagée (lineClear : ni mur, ni fenêtre, ni clôture, ni meuble). La ligne droite étant praticable et courte,
    -- aucun détour par une fenêtre ou une clôture n'est plus court qu'elle. Un pas de l'itinéraire sans aucune case
    -- dégagée (fenêtre ou clôture gardée en dernier recours) est suivi tel quel ("blind"). Deux cases distinctes sont
    -- à une case au moins l'une de l'autre ; seul un premier point à moins d'ARRIVE du corps est omis. Au-delà de
    -- ROUTE_MAX_POINTS points, seules les cases des portes restent (raison "unsafe").
    local STEP, cache = Obstacles.ROUTE_STEP, {}
    local NEAR = (Dir() and Dir().ARRIVE) or 1.0
    local isDoorMark = {}
    for s = 2, #keep - 1 do isDoorMark[keep[s]] = true end
    local final, extra, blind, unsafe = {}, 0, 0, nil
    local cur, ox, oy = 1, x0, y0
    local function emit(k)
        if k >= #r then return end
        if isDoorMark[k] or ((#final > 0 or dist(x0, y0, ox, oy) >= NEAR) and d2(k, #r) >= GAP) then
            final[#final + 1] = k
            if not isDoorMark[k] then extra = extra + 1 end
        end
    end
    for s = 2, #keep do
        local m = keep[s]
        while cur < m do
            local best = nil
            for k = m, cur + 1, -1 do
                local cx, cy = r[k].x + 0.5, r[k].y + 0.5
                if dist(ox, oy, cx, cy) <= STEP and (k == #r or isDoorMark[k] or d2(k, #r) >= GAP)
                    and lineClear(npcId, ox, oy, cx, cy, z, cache, trapped and "trapped" or nil) then
                    best = k
                    break
                end
            end
            if best == nil then
                blind = blind + 1
                best = cur + 1
                -- Escalade de dernier recours (LK04-T20) : aucun point entre la case avant et la case après (un point
                -- juste derrière la fenêtre serait atteint à ARRIVE près depuis l'intérieur).
                if trapped and r[best].cross == "climb" and isDoorMark[m] then best = m end
            end
            cur = best
            ox, oy = r[cur].x + 0.5, r[cur].y + 0.5
            emit(cur)
        end
    end
    if #final > Obstacles.ROUTE_MAX_POINTS then
        unsafe = "more than " .. Obstacles.ROUTE_MAX_POINTS .. " steps, door steps only"
        final, extra = {}, 0
        for s = 2, #keep - 1 do final[#final + 1] = keep[s] end
    end
    local out = {}
    for _, k in ipairs(final) do
        local px, py = r[k].x, r[k].y
        -- Escalade de dernier recours (LK04-T20) : la case juste derrière la fenêtre est à une case du point d'avant,
        -- atteinte à ARRIVE près par un corps arrêté contre la fenêtre fermée, encore dedans ; point reporté une case
        -- plus loin dans le prolongement (case libre, bord sans élément), sinon gardé.
        local o = outward[k]
        if o ~= nil then
            local cell = getCell()
            local sq, nb = cell:getGridSquare(px, py, z), cell:getGridSquare(px + o[1], py + o[2], z)
            if sq ~= nil and nb ~= nil and squareKind(nb) == 1 and edgeElement(sq, nb).kind == "plain" then
                px, py = px + o[1], py + o[2]
            end
        end
        if px ~= tx or py ~= ty then
            -- Point de porte à côté d'une fenêtre ou d'une clôture (campagne solo du 2026-10-15, porte 11360,6977 W et
            -- fenêtre 11360,6978 W) : atteint à ARRIVE (1 case) près, le corps était encore devant la fenêtre et le
            -- chemin natif vers le point suivant la prenait. Ce point est "serré" (t) : atteint à
            -- Directives.STEP_TIGHT près (Directives.distToStep).
            local p = { x = px, y = py }
            if isDoorMark[k] and Obstacles.crossingNear(px, py, z) then p.t = true end
            out[#out + 1] = p
        end
    end
    info.steps, info.extra, info.blind, info.unsafe = #out, extra, blind, unsafe
    local text = "through " .. used .. " door(s) instead of " .. info.climbs .. " window or fence crossing(s)"
    if exitUsed then
        text = exit.text .. " through " .. used .. " door(s) whatever the detour, instead of " .. info.exitClimbs
            .. " window or fence crossing(s) of the building"
        if info.loose ~= nil and #info.loose > 0 then
            text = text .. ", the destination being beyond the refused " .. refusedText(info.loose)
        end
    end
    info.exitUsed = exitUsed
    if wary then text = text .. " after a refused window" end
    if risk and info.loose == nil and not trapped then
        text = "around the refused " .. refusedText(refused) .. " through " .. used .. " door(s) and "
            .. climbs .. " window or fence crossing(s)"
        if #out == 0 then
            log().warn("npc %s: %s: no step needed or kept (%s)", tostring(npcId), text, tostring(unsafe or "short trip"))
        end
    end
    if trapped then
        text = "last resort " .. exit.text .. " through " .. climbs .. " window or fence crossing(s) and "
            .. doors .. " door(s) (" .. tostring(info.noExitDoor) .. ")"
    end
    if unsafe == nil then
        text = text .. ", " .. #out .. " step(s) at most " .. STEP .. " squares apart in clear lines"
        if blind > 0 then text = text .. " (" .. blind .. " route step(s) without a clear line)" end
    else
        text = text .. " (legs may still cross: " .. unsafe .. ")"
    end
    return done(out, text)
end
