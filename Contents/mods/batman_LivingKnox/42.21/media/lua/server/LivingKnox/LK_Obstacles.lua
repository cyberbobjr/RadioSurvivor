-- Living Knox : portes sur le trajet des corps de PNJ (LK04-T02). Fiche : docs/annexes/conception/deplacement.md, section
-- « Portes ». Java 42.21.0 cité en abrégé (J = zombie/...). Autorité seulement (serveur dédié ou hébergé, solo) : un
-- client MP charge aussi media/lua/server, il s'arrête ici ; l'attente devant une porte est dans LK_Executor.lua.
--
-- Pourquoi l'autorité : un corps de zombie n'ouvre jamais une porte en suivant son chemin (J/pathfind/
-- PathFindBehavior2.java:847) et s'arrête devant une porte fermée sans cible (J/characters/IsoZombie.java:1075-1091).
-- Le serveur tient la copie de référence de la porte : il FIXE l'état voulu (ouverte ou fermée, verrou) sur sa copie
-- puis l'envoie, état absolu, à toutes les connexions (IsoObject:sync, J/iso/objects/IsoDoor.java:1508-1535,
-- J/iso/IsoObject.java:988-1008) : une seule machine agit, aucune double bascule, et les deux clients reçoivent le
-- même état. Le client propriétaire ne bascule rien (une bascule depuis un client part de son état local et le
-- serveur l'accepterait sans contrôle, J/network/GameServer.java:2770-2791). En solo, même code, sync sans effet.
-- Aucun personnage n'est passé au moteur : ToggleDoor(zombie) lève une NullPointerException après la bascule
-- (IsoDoor.java:1432) ; on emploie ToggleDoorSilent (bascule de l'état et du sprite seulement, IsoDoor.java:1652-1666,
-- IsoThumpable.java:1227-1240), appelé seulement si l'état diffère de l'état voulu, puis
-- RecalcAllWithNeighbours(true), setSquareChanged() (recherche de chemin, régions, IsoGridSquare.java:4078-4083) et
-- sync(). Verrou : setLockedByKey(v, false) (pose aussi locked ; ne synchronise jamais sur le serveur,
-- IsoDoor.java:1786-1797), envoyé par le même sync.
--
-- Détection, sans charger de zone (getGridSquare rend nil hors zone chargée) : à chaque passage (PASS_EVERY images),
-- pour chaque consigne "move" ouverte et non suspendue dont le corps est dans le monde, portes (sq:getDoorTo(voisine),
-- IsoDoor ou porte IsoThumpable, J/iso/IsoGridSquare.java:3065-3111) des bords à DETECT cases au plus du corps, au
-- même niveau, qui le RAPPROCHENT de l'étape courante (case de l'autre côté plus proche de la case visée que celle du
-- côté du corps). Le chemin vanilla n'étant pas lisible en Lua, un corps arrêté (immobile depuis STUCK_MS) prend
-- aussi en compte toute porte à REACH case. Porte fermée retenue :
--   - barricadée, double (non gérée ici : objets qui changent de case), obstruée, cadenassée : refusée ;
--   - porte du foyer d'un AUTRE groupe (bâtiment du foyer, LivingKnox.Groups) : refusée ;
--   - verrouillée (isLocked, isLockedByKey, CustomLock) sans que le corps porte sa clé : refusée (LK04-T12, section
--     « clés »), sauf abordée de l'intérieur, comme pour un joueur (LK04-T17, opensFromInside ; reverrouillée
--     derrière un membre porteur de la clé du foyer si c'est une porte de son foyer sans clé propre, LK04-T19) ;
--   - porte de garage : tous ses panneaux ensemble (LK04-T17, panelsOf), mêmes règles ;
--   - sinon ouverte (déverrouillée s'il le faut : clé portée) et notée pour être refermée.
-- Porte refusée : rien n'est touché ; si le corps reste à REACH case, immobile depuis REFUSE_MS, la consigne reçoit un
-- détour (LK_Detour.lua, LK17-T01) ou, sans détour, est close en échec par l'autorité (Directives.abort, raison
-- journalisée, dernier refus dans Obstacles.lastRefused) et l'exécutant arrête le corps. Jamais de refus pendant une
-- escalade, ni devant une porte BASSE (portail de clôture, isHoppable et non TallHoppable) : le corps l'enjambe,
-- verrouillée ou non (IsoZombie.java:3051-3058, 1075) (LK04-T08 ; jamais ouverte par l'autorité).
-- Refermeture : quand le dernier PNJ qui avait la porte sur son trajet est passé de l'autre côté à CLOSE_DIST cases
-- au moins, ou au bout de CLOSE_AFTER_MS s'il n'est pas passé (consigne changée, corps disparu), et qu'aucun objet
-- mobile n'occupe les deux cases de la porte ; sinon nouvel essai à chaque passage, abandon (porte laissée ouverte,
-- journalisé) après GIVE_UP_MS. Une porte ouverte par quelqu'un d'autre n'est jamais refermée par ce module.
-- Clés (LK04-T12) : chaque membre d'un groupe dont le foyer est un bâtiment porte la clé vanilla de ce bâtiment dans
-- l'inventaire de son corps (section « clés ») ; une porte verrouillée n'est ouverte que si le corps porte une clé de
-- la porte (IsoDoor : checkKeyId donne la clé du bâtiment, IsoDoor.java:1979-2002). Refermée, une porte EXTÉRIEURE du
-- foyer (un côté dans le bâtiment, l'autre dehors) ou une porte qui était verrouillée est reverrouillée si le PNJ
-- porte toujours sa clé. securePass et shutPass ne verrouillent qu'avec un membre porteur de la clé au foyer.
-- Un joueur dehors a besoin de la clé du bâtiment ou d'un outil pour entrer (IsoDoor.java:1343-1366 ;
-- IsoThumpable.java:1136-1153) ; de l'intérieur, il ouvre sans clé comme en vanilla (canBeOpenFromInside).
-- securePass : toutes les SECURE_EVERY_MS, portes extérieures fermées et non verrouillées des foyers dont la case est
-- chargée verrouillées (au niveau du foyer), si un membre porteur de la clé est au foyer (LK04-T12).
-- Fermeture à l'arrivée (LK04-T10, shutPass, à chaque passage) : une « arrivée » est le passage de la case du foyer
-- de non chargée à chargée chez l'autorité (premier joueur qui approche, chargement de la partie, foyer neuf).
-- SHUT_DELAY_MS après l'arrivée, les portes extérieures OUVERTES du foyer à cet instant (liste figée, hors portes
-- ouvertes par ce module, suivies par la refermeture) sont fermées puis verrouillées (setDoor ; verrou seulement avec
-- un membre porteur de la clé au foyer, LK04-T12, sinon fermée seulement et verrouillée plus tard par securePass),
-- chacune seulement si
-- aucun objet mobile n'occupe ses deux cases, qu'elle n'est sur le trajet d'aucun PNJ à ce passage et qu'elle n'est
-- pas obstruée (véhicule, arbre : IsoDoor.java:2288-2324) ; sinon nouvel essai toutes les SHUT_RETRY_MS, abandon
-- (porte laissée ouverte, WARN) SHUT_GIVE_UP_MS après l'arrivée. Jamais : porte barricadée, détruite (une porte
-- cassée est retirée de sa case, IsoDoor.java:1178-1210), double (objets qui changent de case), cadenassée ; porte
-- de garage : tous ses panneaux (LK04-T17). Une seule fermeture par arrivée : une porte rouverte ensuite (joueur,
-- autre PNJ) reste ouverte jusqu'à la prochaine arrivée (case du foyer déchargée puis rechargée) ; pas de bataille
-- avec un joueur. Une fois refermée par quelqu'un, securePass la verrouille comme avant.
-- Mémoire seulement : un redémarrage oublie les portes à refermer (laissées ouvertes ; securePass reverrouille les
-- portes extérieures du foyer une fois refermées, et le chargement de la partie est une arrivée).
-- Alerte (complément de LK05-T08, section « alerte » plus bas) : une alerte déclenchée ou aggravée du groupe ferme de
-- même les portes extérieures ouvertes de son foyer (écouteur "doors" de LivingKnox.Alert, puis shutHome).
--
-- Fenêtres, clôtures, escaliers (LK04-T03, LK04-T07 ; fiche deplacement.md, section « Fenêtres, clôtures,
-- escaliers ») : franchir est l'affaire du moteur, au contact et sans test de useless (fenêtre ouverte ou cassée,
-- cadre vide, fenêtre construite : J/characters/IsoZombie.java:3016-3060 ; clôture basse :
-- J/iso/IsoMovingObject.java:1552-1582 ; escaliers : recherche de chemin) ; le corps reprend son chemin après
-- l'escalade (ClimbThroughWindowState.java:243-262, ClimbOverFenceState.java:229-263). Une fenêtre FERMÉE arrête le
-- corps (sans cible, IsoZombie.java:1075-1091) : elle n'est traitée ici que lorsqu'il est arrêté contre elle
-- (immobile depuis STUCK_MS, milieu du bord à REACH case, tourné vers elle à FACING près), preuve que son chemin la
-- traverse. Tout PNJ (pillards compris, avec ou sans groupe) : fenêtre OUVERTE par window:ToggleWindow(corps) sur la
-- copie de l'autorité, seulement si elle est fermée (c'est une bascule), jamais brisée ; ToggleWindow recalcule, met
-- à jour la recherche de chemin et synchronise lui-même, et n'arme pas l'alarme pour un zombie sauf option
-- ZombieLore.TriggerHouseAlarm (J/iso/objects/IsoWindow.java:701-731) ; la fermeture n'arme jamais l'alarme.
-- Refus (rien n'est touché, consigne close en échec après REFUSE_MS comme pour une porte) : fenêtre barricadée
-- (cadre et fenêtre construite compris), verrouillée (même celle du foyer du PNJ : il passe par la porte),
-- inamovible, donnant sur le vide (aucun sol de l'autre côté : chute, IsoWindow.java:1184-1218,
-- ClimbThroughWindowState.java:81-83), donnant sur un meuble bas (issue "obstacle", corps au sol :
-- isFurnitureLanding), foyer d'un autre groupe, maison à alarme quand l'option l'armerait.
-- Refermeture (LK04-T07, LK04-T18) : une fenêtre ouverte ici est notée ; tout PNJ dont elle rapproche l'étape (à
-- DETECT cases) en devient le dernier passant ; refermée (ToggleWindow, seulement si elle est encore ouverte) par ce
-- dernier PNJ, comme un joueur, JUSTE APRÈS son enjambée : corps dans le monde, au niveau de la fenêtre, hors escalade,
-- à ACT_REACH case au plus du milieu du bord (case voisine côté arrivée, diagonale comprise) et passé de l'autre côté
-- (ou consigne changée, CLOSE_AFTER_MS sans passage : refermée de son côté s'il est contre elle), et aucun objet
-- mobile autre que lui n'occupe ses deux cases ; sinon nouvel essai à chaque passage, laissée ouverte (WARN) après
-- GIVE_UP_MS. Jamais de loin : un corps disparu ou déjà à plus d'ACT_REACH la laisse ouverte (LK04-T18 : l'ancienne
-- règle, CLOSE_DIST cases au moins, la fermait pendant que le corps continuait sa marche, à 2 ou 3 cases). La fin
-- d'une escalade est guettée à chaque image (Obstacles.tick, landed) pour arrêter le corps sur la case d'arrivée. Une
-- fenêtre fermée, brisée ou barricadée entre-temps par quelqu'un d'autre n'est plus suivie ; une fenêtre ouverte par
-- quelqu'un d'autre n'est jamais refermée. Refermée par un PNJ, elle n'est pas rouverte par lui pendant
-- CLOSE_GUARD_MS (corps encore arrêté devant elle à la fin du geste).
-- Gestes (LK04-T13 ; fiche deplacement.md, section « Gestes d'ouverture et de fermeture ») : ouvrir ou refermer une
-- fenêtre se fait avec le geste du joueur (LivingKnox.Anim.startAct, geste "openwindow" ou "closewindow", corps tourné
-- vers la fenêtre ; nœuds lkactor_*window*, tools/anim_table.json). La fenêtre n'est basculée qu'à l'instant où le
-- clip du joueur la bascule (OPEN_TOGGLE_MS, CLOSE_TOGGLE_MS après le début du geste, windowActPass) : à l'ouverture,
-- le corps est déjà arrêté contre elle ; à la fermeture, l'exécutant l'arrête sur la case d'arrivée le temps du geste
-- puis relance le chemin de la même étape, et la bascule n'a lieu que corps arrêté (moins de STILL case depuis le
-- passage précédent), à ACT_REACH case au plus et tourné vers la fenêtre (closeReady ; sinon attente jusqu'à la fin du
-- geste, puis nouveau geste). Aucun geste pour une porte : le joueur vanilla l'ouvre sans animation (ISOpenCloseDoor,
-- durée 0) ; elle reste ouverte en marche, sans arrêt, et se referme quand le corps a quitté ses cases (CLOSE_DIST).
-- Interrupteur WINDOW_GESTURE (coupé : bascule immédiate, mêmes conditions de distance).
--
-- Chemin du jeu, détour seulement après un refus (LK17, ADR docs/architecture/decisions/adr-chemin-vanilla.md) :
-- aucun itinéraire n'est calculé ici. Un refus au contact (refuse, plus bas) passe d'abord par le gestionnaire
-- Obstacles.onRefusal (LK_Detour.lua) : détour court par une porte, ou dernier recours (e.lr, LK04-T20), sinon la
-- consigne est close en échec.
--
-- Passage bloqué (LK04-T04 ; fiche deplacement.md, section « Passage bloqué : attendre ou forcer » ; section
-- « passage bloqué » plus bas) : au lieu du refus au contact d'une porte ou d'une fenêtre refusée, selon le type du
-- groupe du PNJ : refus aussitôt (colons, sans groupe), attente puis refus (neutres), ou forçage (pillards : coups
-- vanilla WeaponHit sur la barricade puis la porte verrouillée, appliqués par l'autorité, effets synchronisés par le
-- moteur) ; jamais le foyer d'un groupe ami des joueurs sans consigne explicite (orderForce).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Directives"
require "LivingKnox/LK_Groups"
require "LivingKnox/Edges/LK_Edges"

local Obstacles = LivingKnox.Obstacles or {}
LivingKnox.Obstacles = Obstacles

Obstacles.PASS_EVERY = 5          -- images entre deux passages
Obstacles.DETECT = 2.0            -- cases : porte (milieu du bord) à cette distance du corps au plus
Obstacles.REACH = 1.0             -- cases : porte au contact d'un corps arrêté
Obstacles.STILL = 0.1             -- cases : déplacement en deçà duquel le corps est immobile
Obstacles.STUCK_MS = 800          -- immobile depuis ce temps : portes au contact prises en compte
Obstacles.REFUSE_MS = 1500        -- immobile depuis ce temps au contact d'une porte refusée : consigne refusée
Obstacles.CLOSE_DIST = 1.5        -- cases : corps à cette distance de la porte au moins pour la refermer
Obstacles.CLOSE_AFTER_MS = 15000  -- porte refermée au bout de ce temps sans passage
Obstacles.GIVE_UP_MS = 60000      -- porte toujours occupée : laissée ouverte
Obstacles.HOMES_MS = 2000         -- validité du relevé des bâtiments de foyer (foyer changé : vu dans ce délai)
Obstacles.SECURE_EVERY_MS = 30000 -- verrouillage des portes extérieures des foyers chargés
Obstacles.SHUT_DELAY_MS = 3000    -- arrivée près d'un foyer : ses portes extérieures ouvertes fermées après ce délai
Obstacles.SHUT_RETRY_MS = 2000    -- porte occupée ou sur un trajet : nouvel essai après ce délai
Obstacles.SHUT_GIVE_UP_MS = 60000 -- porte toujours occupée : laissée ouverte (jusqu'à la prochaine arrivée)
Obstacles.FACING = 0.5            -- fenêtre : produit scalaire minimal entre l'orientation du corps et le bord
-- Gestes d'ouverture et de fermeture des fenêtres (LK04-T13). Clips du joueur à la vitesse 0,80 de ses nœuds
-- (fichiers .x à 4800 tics/s) : ouverture Bob_WindowStruggle_Start 0,333 s puis Bob_WindowStruggleSuccess 1,067 s,
-- fenêtre ouverte à 45 % du second (WindowOpenSuccess) ; fermeture Bob_WindowCloseStart 0,433 s puis
-- Bob_WindowCloseSuccess 1,233 s, fenêtre fermée à 35 % (WindowCloseSuccess).
Obstacles.WINDOW_GESTURE = true   -- geste joué par le corps, bascule à l'instant du clip (coupé : bascule immédiate)
Obstacles.OPEN_TOGGLE_MS = 1000   -- 0,333 / 0,8 + 0,45 x 1,067 / 0,8
Obstacles.OPEN_GESTURE_MS = 1750  -- (0,333 + 1,067) / 0,8
Obstacles.CLOSE_TOGGLE_MS = 1080  -- 0,433 / 0,8 + 0,35 x 1,233 / 0,8
Obstacles.CLOSE_GESTURE_MS = 2080 -- (0,433 + 1,233) / 0,8
Obstacles.ACT_REACH = 1.5         -- cases : fenêtre refermée par un corps à cette distance au plus de son milieu
Obstacles.CLOSE_GUARD_MS = 5000   -- fenêtre refermée par un PNJ : pas rouverte par lui pendant ce temps (LK04-T18)

Obstacles.opened = Obstacles.opened or {}   -- clé de bord -> porte ouverte ici, à refermer
Obstacles.openWins = Obstacles.openWins or {}   -- clé de bord -> fenêtre ouverte ici, à refermer
Obstacles.winActs = Obstacles.winActs or {}     -- clé de bord -> geste en cours devant la fenêtre (LK04-T13)
Obstacles.closedBy = Obstacles.closedBy or {}   -- clé de bord -> { id, ms } fenêtre refermée par ce PNJ (LK04-T18)
Obstacles.alertShuts = Obstacles.alertShuts or {}   -- gid|bâtiment -> fermeture demandée par une alerte (LK05-T08)
Obstacles.track = Obstacles.track or {}     -- npcId -> { x, y, ms } dernière position mobile
Obstacles.homes = Obstacles.homes or { ms = nil, byBuilding = {}, list = {} }
Obstacles.state = Obstacles.state or { ticks = 0, secured = nil }
Obstacles.arrivals = Obstacles.arrivals or {}   -- gid|bâtiment -> { ms, due, doors, done } arrivée près du foyer
Obstacles.stats = Obstacles.stats or { passes = 0, opened = 0, unlocked = 0, closed = 0, locked = 0, refused = 0,
    syncs = 0, busy = 0, givenUp = 0, secured = 0, shut = 0, shutBusy = 0, shutRefused = 0, shutGivenUp = 0,
    windowsOpened = 0, windowToggles = 0, windowsRefused = 0,
    windowsClosed = 0, windowsBusy = 0, windowsGivenUp = 0, detoured = 0 }

local function log() return LivingKnox.Log end
local function Dir() return LivingKnox.Directives end
local function Bodies() return LivingKnox.Bodies end

local function now() return getTimestampMs() end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end
Obstacles.dist = dist

local function count(name)
    local st = Obstacles.stats
    st[name] = (st[name] or 0) + 1
end

-- ---------------------------------------------------------------- portes

-- Bord entre la case (x, y) et sa voisine est (kind "W" : bord ouest de x + 1) ou sud (kind "N" : bord nord de y + 1).
-- Rend { key, kind, ex, ey, mx, my, ax, ay, bx, by, z } (a = case ouest ou nord, b = case est ou sud).
local function edge(x, y, z, kind)
    local e = { kind = kind, z = z, ax = x, ay = y }
    if kind == "W" then
        e.ex, e.ey, e.bx, e.by, e.mx, e.my = x + 1, y, x + 1, y, x + 1, y + 0.5
    else
        e.ex, e.ey, e.bx, e.by, e.mx, e.my = x, y + 1, x, y + 1, x + 0.5, y + 1
    end
    e.key = e.ex .. "," .. e.ey .. "," .. z .. "," .. kind
    return e
end
Obstacles.edge = edge

-- Côté du point (px, py) : "a" (ouest ou nord du bord) ou "b".
local function sideOf(e, px, py)
    if e.kind == "W" then return px >= e.ex and "b" or "a" end
    return py >= e.ey and "b" or "a"
end
Obstacles.sideOf = sideOf

function Obstacles.isOpen(door) return door:IsOpen() == true end

local function isThumpable(door) return instanceof(door, "IsoThumpable") end

-- Vrai si la porte est verrouillée pour un joueur sans clé (verrou, clé, cadenas, verrou de mod CustomLock).
function Obstacles.isLocked(door)
    if door:isLocked() or door:isLockedByKey() then return true end
    if isThumpable(door) then return door:isLockedByPadlock() == true end
    return door:hasModData() and door:getModData().CustomLock == true
end

-- Porte simple, ou "double" (quatre objets qui changent de case en s'ouvrant : non gérée ici) / "garage" (panneaux
-- alignés, gérés ensemble, LK04-T17 : voir panelsOf).
function Obstacles.kindOf(door)
    if IsoDoor.getDoubleDoorIndex(door) ~= -1 then return "double" end
    if IsoDoor.getGarageDoorIndex(door) ~= -1 then return "garage" end
    return "single"
end

-- Panneaux d'une porte de garage (LK04-T17), du premier au dernier ; { door } pour toute autre porte. Un joueur bascule
-- tous les panneaux d'un coup (IsoDoor.toggleGarageDoor depuis ToggleDoorActual : chaque panneau ouvert ou fermé et
-- déverrouillé, J/iso/objects/IsoDoor.java:1389-1403, 2880-2932) ; les panneaux restent sur leur case et leur bord
-- (getGarageDoorPrev / Next : case voisine le long du mur, index 1 à 3, :2770-2878).
function Obstacles.panelsOf(door)
    if Obstacles.kindOf(door) ~= "garage" then return { door } end
    local out = {}
    local p = IsoDoor.getGarageDoorFirst(door)
    while p ~= nil and #out < 8 do
        out[#out + 1] = p
        p = IsoDoor.getGarageDoorNext(p)
    end
    if #out == 0 then out[1] = door end
    return out
end

-- Vrai si un panneau de la porte est barricadé.
local function anyBarricaded(door)
    for _, p in ipairs(Obstacles.panelsOf(door)) do
        if p:isBarricaded() then return true end
    end
    return false
end

-- Identifiant stable du bâtiment de la case (BuildingDef:getIDString), ou nil.
local function buildingOf(sq)
    if sq == nil then return nil end
    local def = sq:getBuildingDef()
    if def == nil then return nil end
    return def:getIDString()
end
Obstacles.buildingOf = buildingOf

-- ---------------------------------------------------------------- foyers

-- Relevé (au plus toutes les HOMES_MS) des bâtiments de foyer : byBuilding[idString] = gid ; list = { { gid, id, def,
-- x, y, z } }. Foyer en clairière ou hors bâtiment : ignoré. Métagrille seulement (getBuildingAt(x, y, z) indexé).
function Obstacles.refreshHomes(force)
    local H = Obstacles.homes
    local t = now()
    if not force and H.ms ~= nil and t - H.ms < Obstacles.HOMES_MS then return H end
    H.ms, H.byBuilding, H.list = t, {}, {}
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return H end
    local grid = getWorld():getMetaGrid()
    for _, gid in ipairs(G.list()) do
        local g = G.peek(gid)   -- LK13-T08 : lecture en place, seule (coordonnées recopiées)
        local h = g and g.home
        if h ~= nil then
            local def = grid:getBuildingAt(h.x, h.y, h.z)
            if def ~= nil then
                local id = def:getIDString()
                if H.byBuilding[id] == nil then   -- deux groupes dans un même bâtiment : le premier (Groups.list trié)
                    H.byBuilding[id] = gid
                    H.list[#H.list + 1] = { gid = gid, id = id, def = def, x = h.x, y = h.y, z = h.z }
                end
            end
        end
    end
    return H
end

-- Groupe dont le foyer est le bâtiment d'un des deux côtés de la porte, et vrai si la porte est extérieure (l'autre
-- côté hors de ce bâtiment). Rend nil hors de tout foyer.
function Obstacles.homeOf(sqA, sqB)
    local H = Obstacles.refreshHomes(false)
    local ia, ib = buildingOf(sqA), buildingOf(sqB)
    local ga = ia and H.byBuilding[ia]
    if ga ~= nil then return ga, ib ~= ia end
    local gb = ib and H.byBuilding[ib]
    if gb ~= nil then return gb, true end
    return nil
end

-- Groupe du PNJ (LivingKnox.Groups.findNpc), ou nil.
function Obstacles.groupOf(npcId)
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil end
    return (G.findNpc(npcId))
end

-- ---------------------------------------------------------------- clés (LK04-T12)
-- Fiche : deplacement.md, section « Portes », « Clés ». Java 42.21.0 :
-- - clé d'une porte : IsoDoor:checkKeyId() (celle qu'emploient ISLockDoor.lua:6, IsoDoor.ToggleDoor et saveState,
--   J/iso/objects/IsoDoor.java:805, 1326, 1979-2002) : keyId propre de la porte, sinon celui du bâtiment
--   (BuildingDef:getKeyId) quand un seul côté est dans un bâtiment (ou sprite forceLocked) ; porte intérieure sans
--   keyId : -1, aucune clé. Porte construite IsoThumpable : getKeyId(). Le keyId d'un bâtiment est tiré à sa création
--   et sauvegardé dans map_meta.bin (J/iso/BuildingDef.java:72-75, J/iso/IsoMetaGrid.java:923, 1041-1053) ;
-- - une clé est un objet de classe Key (Base.Key1, ItemType base:key, media/scripts/generated/items/key.txt:3-15),
--   keyId fixé par setKeyId (J/inventory/types/Key.java : -1 tiré au hasard ; sauvegardé avec l'objet) ;
--   ItemContainer:haveThisKeyId(keyId) la cherche dans l'inventaire et les porte-clés (J/inventory/ItemContainer.java:
--   3052-3064), comme pour un joueur (IsoDoor.java:1347-1366).
-- - inventaire du corps : un joueur réanimé garde l'inventaire du cadavre dont il sort (IsoDeadBody.reanimate,
--   IsoDeadBody.java:1850-1853) ; à sa mort, DoZombieInventory ne fait rien pour un joueur réanimé
--   (J/characters/IsoZombie.java:3129-3133) et le cadavre prend l'inventaire du mort (IsoDeadBody.java:327-332) :
--   la clé posée sur le corps se retrouve sur son cadavre. Sauvegardée avec le corps (reanimated.bin,
--   IsoGameCharacter.save, IsoGameCharacter.java:5032).
-- Règles : chaque membre d'un groupe dont le foyer est un bâtiment porte UNE clé Base.Key1 au keyId de ce bâtiment,
-- marquée KEY_TAG (ModData de l'objet : identifiant du bâtiment). Posée par l'autorité sur SA copie du corps
-- (l'inventaire d'un zombie n'est jamais envoyé aux clients ; le cadavre part avec son contenu). Le corps garde dans
-- sa ModData (KEY_GIVEN) le keyId déjà remis : la clé n'est remise qu'une fois par corps et par foyer (une clé perdue
-- par le corps courant ne revient pas ; chaque nouveau corps, à chaque incarnation, reçoit la sienne ; un corps relu
-- de reanimated.bin garde la sienne, sans doublon). Foyer changé : les clés KEY_TAG du corps sont RETIRÉES et la clé
-- du nouveau foyer posée (aucune clé d'un ancien foyer) ; plus de foyer ni de groupe : clés KEY_TAG retirées. Une
-- clé non marquée (butin futur) n'est jamais touchée.
Obstacles.KEY_ITEM = "Base.Key1"
Obstacles.KEY_TAG = "LKHomeKey"        -- ModData de la clé : identifiant du bâtiment du foyer (getIDString)
Obstacles.KEY_GIVEN = "LKKeyGiven"     -- ModData du corps : keyId de la clé déjà remise à ce corps
Obstacles.KEYS_EVERY_MS = 2000         -- relevé des clés des corps liés (foyer changé)
Obstacles.KEYHOLDER_RADIUS = 20        -- cases : membre « au foyer » (dans le bâtiment, ou à cette distance du foyer)

-- keyId, identifiant du bâtiment et groupe du foyer du PNJ npcId ; nil sans groupe, sans foyer ou foyer hors de tout
-- bâtiment (métagrille seulement : getBuildingAt(x, y, z) indexé).
function Obstacles.homeKeyOf(npcId)
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil end
    local gid = G.findNpc(npcId)
    local g = gid and G.peek(gid)   -- LK13-T08 : lecture en place, seule (passage fréquent des clés)
    local h = g and g.home
    if h == nil then return nil end
    local def = getWorld():getMetaGrid():getBuildingAt(h.x, h.y, h.z)
    if def == nil then return nil end
    return def:getKeyId(), def:getIDString(), gid
end

-- Clés posées par ce module (objets Key marqués KEY_TAG) dans l'inventaire du corps z.
function Obstacles.keysOf(z)
    local out = {}
    local items = z:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if instanceof(it, "Key") and it:hasModData() and it:getModData()[Obstacles.KEY_TAG] ~= nil then
            out[#out + 1] = it
        end
    end
    return out
end

-- Retire du corps z les clés posées par ce module. Rend leur nombre.
function Obstacles.removeKeys(z)
    local inv = z:getInventory()
    local keys = Obstacles.keysOf(z)
    for _, k in ipairs(keys) do inv:DoRemoveItem(k) end
    return #keys
end

-- Vrai si le corps z porte une clé (objet Key, porte-clés compris) de keyId.
function Obstacles.hasKey(z, keyId)
    if z == nil or keyId == nil or keyId == -1 then return false end
    return z:getInventory():haveThisKeyId(keyId) ~= nil
end

-- Clé de la porte door (voir l'en-tête de la section) ; -1 : aucune.
function Obstacles.doorKeyId(door)
    if instanceof(door, "IsoDoor") then return door:checkKeyId() end
    return door:getKeyId()
end

-- Case de l'autre côté d'une porte (bord nord : case au nord ; bord ouest : case à l'ouest), ou nil.
local function oppositeOf(door)
    local sq = door:getSquare()
    if sq == nil then return nil end
    if door:getNorth() then return getCell():getGridSquare(sq:getX(), sq:getY() - 1, sq:getZ()) end
    return getCell():getGridSquare(sq:getX() - 1, sq:getY(), sq:getZ())
end

-- Ouverture « de l'intérieur » d'une porte verrouillée, sans clé (LK04-T17), pour un personnage sur la case from.
-- Règle vanilla d'un joueur (Java 42.21.0) :
-- - IsoDoor (canBeOpenFromInside, J/iso/objects/IsoDoor.java:1266-1268) : case du personnage non extérieure
--   (IsoGameCharacter.isOutside = drapeau exterior de la case, IsoGameCharacter.java:9340-9345,
--   IsoGridSquare.java:7968-7970), dans la pièce de l'une des deux cases de la porte, sprite sans forceLocked
--   (porte blindée). couldBeOpen rend alors vrai avant tout test de clé (:1271-1291) et ToggleDoorActual déverrouille
--   puis ouvre (:1343-1346), portes de garage comprises (:1389-1403) ;
-- - IsoThumpable (porte construite) : le verrou (clé ou bouton) ne retient que sur une case extérieure
--   (IsoThumpable.java:1100-1114, 1136-1153).
-- Une porte verrouillée de l'extérieur sans keyId (-1 : porte intérieure, IsoDoor.java:1979-2002) ne s'ouvre donc que
-- de l'intérieur, et toute porte d'un bâtiment s'ouvre sans clé depuis une pièce : le verrou ne retient que celui qui
-- est dehors.
function Obstacles.opensFromInside(door, from)
    if from == nil or from:isOutside() then return false end
    if isThumpable(door) then return true end
    local props = door:getProperties()
    if props ~= nil and props:has("forceLocked") then return false end
    local room = from:getRoom()
    local sq, other = door:getSquare(), oppositeOf(door)
    return (sq ~= nil and room == sq:getRoom()) or (other ~= nil and room == other:getRoom())
end

-- Clé du foyer du PNJ npcId sur son corps z (règles ci-dessus). Autorité seulement. Rend le keyId porté pour le foyer
-- (nil : aucun foyer) et ce qui a été fait : "kept", "given", "changed", "removed", "none".
function Obstacles.giveKey(npcId, z)
    if z == nil or not LivingKnox.isAuthority() then return nil, "none" end
    local want, bid = Obstacles.homeKeyOf(npcId)
    local md = z:getModData()
    local given = md[Obstacles.KEY_GIVEN]
    if given == want then return want, want and "kept" or "none" end
    local removed = 0
    if given ~= nil then removed = Obstacles.removeKeys(z) end
    if want == nil then
        md[Obstacles.KEY_GIVEN] = nil
        count("keysRemoved")
        log().info("npc %s: %d key(s) of a former home removed (no home)", npcId, removed)
        return nil, "removed"
    end
    local key = instanceItem(Obstacles.KEY_ITEM)
    key:setKeyId(want)
    key:getModData()[Obstacles.KEY_TAG] = bid
    z:getInventory():AddItem(key)
    md[Obstacles.KEY_GIVEN] = want
    count("keysGiven")
    log().info("npc %s: key %s of its home building %s given%s", npcId, tostring(want), tostring(bid),
        removed > 0 and (" (" .. removed .. " key(s) of a former home removed)") or "")
    return want, given ~= nil and "changed" or "given"
end

-- Toutes les KEYS_EVERY_MS : clés des corps liés dans le monde (foyer changé, groupe quitté). La remise à la liaison
-- d'un corps se fait dans Bodies.guardNow.
function Obstacles.keyPass(t)
    local st = Obstacles.state
    if st.keysMs ~= nil and t - st.keysMs < Obstacles.KEYS_EVERY_MS then return end
    st.keysMs = t
    local B = Bodies()
    local ids = {}
    for id in pairs(B.bound) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local z = B.bound[id]
        if z ~= nil and B.inWorld(z) then Obstacles.giveKey(id, z) end
    end
end

-- Membre du groupe du foyer h ({ gid, id, x, y }) présent au foyer (corps dans le monde, dans le bâtiment du foyer ou
-- à KEYHOLDER_RADIUS cases au plus du point du foyer) et portant une clé de keyId : identifiant du PNJ, ou nil.
function Obstacles.keyHolderAt(h, keyId)
    if keyId == nil or keyId == -1 then return nil end
    local G = LivingKnox.Groups
    if G == nil or not G.isReady() then return nil end
    local B = Bodies()
    local ids = {}
    for id in pairs(B.bound) do ids[#ids + 1] = id end
    table.sort(ids)
    local R = Obstacles.KEYHOLDER_RADIUS
    for _, id in ipairs(ids) do
        local z = B.bound[id]
        if z ~= nil and B.inWorld(z) and G.findNpc(id) == h.gid then
            Obstacles.giveKey(id, z)
            if Obstacles.hasKey(z, keyId) then
                local sq = getCell():getGridSquare(math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ()))
                if buildingOf(sq) == h.id or (math.abs(z:getX() - h.x) <= R and math.abs(z:getY() - h.y) <= R) then
                    return id
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- décision et effet

-- Décision pour le PNJ npcId (corps body, ou son corps courant) devant la porte fermée door (cases sqA, sqB). Rend
-- "open", lockAfter, gid, keyId (clé de la porte) ; ou nil et la raison du refus (anglais, journal).
-- LK04-T12 : une porte verrouillée n'est ouverte que si le corps porte une clé de la porte (Obstacles.hasKey) ; elle
-- est alors reverrouillée derrière lui, comme une porte extérieure de son foyer. Sans clé, une porte non verrouillée
-- s'ouvre mais n'est jamais verrouillée ensuite.
-- LK04-T17 (essai solo du 2026-10-12, lk-73 enfermé dans son foyer : porte intérieure verrouillée, keyId -1, refusée
-- malgré la clé du bâtiment) : sans clé, une porte verrouillée s'ouvre aussi de l'intérieur, comme pour un joueur
-- (opensFromInside), depuis la case from (côté d'où le PNJ l'aborde ; nil : case courante du corps) ; elle n'est pas
-- reverrouillée ensuite sans clé, sauf porte de son foyer sans clé propre et clé du foyer portée (LK04-T19). Rend en
-- cinquième valeur vrai si la porte verrouillée est ouverte de l'intérieur sans sa clé. Porte de garage : tous ses
-- panneaux (panelsOf), sans test d'obstruction à l'ouverture (le moteur n'en fait pas : IsoDoor.java:1389-1398,
-- isGarageDoorObstructed faux pour une porte fermée, :2934-2944).
-- LK04-T20 (campagne MP du 2026-10-15, lk-7 sans groupe apparu dans le foyer de grp-5) : trapped (consigne de dernier
-- recours, e.lr) : la porte du foyer d'un autre groupe abordée depuis l'intérieur de ce foyer (inHomeOf) n'est plus
-- refusée ; elle suit alors les règles d'une porte ordinaire (verrou ouvert de l'intérieur), jamais reverrouillée.
function Obstacles.decide(npcId, door, sqA, sqB, body, from, trapped)
    if anyBarricaded(door) then return nil, "barricaded door" end
    local kind = Obstacles.kindOf(door)
    if kind == "double" then return nil, "double door not handled" end
    if kind == "single" and door:isObstructed() then return nil, "obstructed door" end
    if isThumpable(door) and door:isLockedByPadlock() then return nil, "padlocked door" end
    local home, exterior = Obstacles.homeOf(sqA, sqB)
    local mine = Obstacles.groupOf(npcId)
    local foreign = home ~= nil and home ~= mine
    local z = body
    if foreign then
        if trapped and from == nil and z == nil then z = Bodies().find(npcId) end
        if trapped and from == nil and z ~= nil then from = z:getCurrentSquare() end
        if not (trapped and Obstacles.inHomeOf(from, home)) then
            return nil, "door of the home of " .. home .. " (not a member)"
        end
    end
    local locked = Obstacles.isLocked(door)
    local keyId, key = nil, false
    if locked or home ~= nil then   -- sinon la clé ne sert à rien : ni corps ni inventaire lus
        keyId = Obstacles.doorKeyId(door)
        if z == nil then z = Bodies().find(npcId) end
        if z ~= nil then Obstacles.giveKey(npcId, z) end   -- clé du foyer (une fois par corps et par foyer)
        key = Obstacles.hasKey(z, keyId)
    end
    if locked and not key then
        if from == nil and z ~= nil then from = z:getCurrentSquare() end
        if not Obstacles.opensFromInside(door, from) then return nil, "locked door (no key)" end
        -- LK04-T19 (décision de l'utilisateur du 2026-10-14) : ouverte de l'intérieur sans la clé de la porte, une
        -- porte verrouillée de SON foyer (home : décision déjà refusée pour le foyer d'un autre groupe) est
        -- reverrouillée derrière lui s'il porte la clé de son foyer et que la porte n'a pas d'autre clé : keyId -1
        -- (porte intérieure du bâtiment, IsoDoor.checkKeyId, IsoDoor.java:1979-2002 ; cas de lk-73). Une porte à
        -- keyId propre différent de celui du foyer reste déverrouillée (la clé du foyer ne la ferme pas) ; une porte
        -- au keyId du foyer s'ouvre déjà avec la clé (branche key ci-dessus). keyId rendu : clé du foyer, revérifiée
        -- à la refermeture (closePass) ; inside : ouverte sans la clé de la porte (journal).
        if home ~= nil and not foreign and (keyId == nil or keyId == -1) then
            local homeKey = Obstacles.homeKeyOf(npcId)
            if homeKey ~= nil and homeKey ~= -1 and Obstacles.hasKey(z, homeKey) then
                return "open", true, home, homeKey, true
            end
        end
        return "open", false, home, keyId, true
    end
    return "open", key and (locked or (home ~= nil and not foreign and exterior)), home, keyId, false
end

-- Vrai si la case sq est dans le bâtiment du foyer du groupe gid (LK04-T20 : passage abordé depuis l'intérieur).
function Obstacles.inHomeOf(sq, gid)
    local id = buildingOf(sq)
    if id == nil or gid == nil then return false end
    return Obstacles.refreshHomes(false).byBuilding[id] == gid
end

-- Case du bord e du côté du point (px, py) : sqA (ouest ou nord) ou sqB.
local function nearSquare(e, px, py, sqA, sqB)
    if sideOf(e, px, py) == "a" then return sqA end
    return sqB
end

-- Fixe l'état de la porte : ouverte (déverrouillée) ou fermée (verrouillée si lock). Bascule seulement si l'état
-- diffère (jamais deux fois) ; recalcul des cases et envoi de l'état absolu (sync) si quelque chose a changé. Rend
-- vrai si la porte a changé. Porte de garage (LK04-T17) : chaque panneau (panelsOf), comme toggleGarageDoor ; un
-- verrou ou un déverrouillage compté une fois pour la porte.
local function setPanel(door, open, lock)
    local changed, unlocked, locked = false, false, false
    if open then
        if door:isLocked() or door:isLockedByKey() then
            door:setLockedByKey(false, false)
            door:setIsLocked(false)
            unlocked, changed = true, true
        end
        if not Obstacles.isOpen(door) then
            door:ToggleDoorSilent()
            changed = true
        end
    else
        if Obstacles.isOpen(door) then
            door:ToggleDoorSilent()
            changed = true
        end
        if lock and not (door:isLocked() or door:isLockedByKey()) and not Obstacles.isOpen(door) then
            if instanceof(door, "IsoDoor") then door:checkKeyId() end
            door:setLockedByKey(true, false)
            locked, changed = true, true
        end
    end
    return changed, unlocked, locked
end

-- Recalcul et envoi d'état après que TOUS les panneaux ont pris leur état : un SyncIsoObject de panneau de garage
-- applique son état à tous les panneaux chez le destinataire (IsoDoor.java:1487-1503, 1601-1622).
function Obstacles.setDoor(door, open, lock)
    local changed, unlocked, locked = false, false, false
    local done = {}
    for _, p in ipairs(Obstacles.panelsOf(door)) do
        local c, u, l = setPanel(p, open, lock)
        if c then done[#done + 1] = p end
        changed, unlocked, locked = changed or c, unlocked or u, locked or l
    end
    for _, p in ipairs(done) do
        local sq = p:getSquare()
        sq:RecalcAllWithNeighbours(true)
        sq:setSquareChanged()
        p:sync()
        count("syncs")
    end
    if unlocked then count("unlocked") end
    if locked then count("locked") end
    return changed
end

-- ---------------------------------------------------------------- fenêtres (LK04-T03)

-- Fenêtre d'un bord : LivingKnox.Edges.windowOf (ADR adr-bords-des-cases.md).

-- Vrai si la fenêtre arrête un corps : barricadée, ou IsoWindow fermée et intacte. Fenêtre ouverte, cassée ou
-- détruite, cadre vide et fenêtre construite non barricadés : franchis par le moteur (IsoWindow.java:1220-1238,
-- IsoWindowFrame.java:348-372, IsoThumpable.java:2175-2186).
function Obstacles.windowBlocks(w, kind)
    return LivingKnox.EdgeRules.windowStops(LivingKnox.Edges.windowFacts(w, kind))
end

-- Vrai si la case sq n'offre aucun sol où se poser : franchir serait une chute (issue "fall" quand la case opposée
-- n'est pas un sol, ClimbThroughWindowState.java:81-83, 576). Case absente (non chargée) : vrai, par prudence.
function Obstacles.isDrop(sq)
    if sq == nil then return true end
    return not sq:TreatAsSolidFloor()
end

-- Vrai si la case sq, de l'autre côté d'une fenêtre, porte un meuble bas (drapeau solidtrans : comptoir, table,
-- cuisinière...) : l'escalade prend l'issue "obstacle" (zombie : case suivante libre) ou finit sur le meuble
-- (ClimbThroughWindowState.java:574-588), jouée par les nœuds zombie qui mettent le corps au sol (LK04-T11 ne remplace
-- que l'issue "success"). Essai solo du 2026-10-11 23:08 : fenêtre 10747,9532,0,W au-dessus de la table
-- furniture_tables_high_01_15, « on the floor after a crossing true ».
function Obstacles.isFurnitureLanding(sq)
    return sq ~= nil and sq:isSolidTrans() == true
end

-- Case de l'autre côté du bord e, vue du point (px, py).
local function farSquare(e, px, py)
    if sideOf(e, px, py) == "a" then return getCell():getGridSquare(e.bx, e.by, e.z) end
    return getCell():getGridSquare(e.ax, e.ay, e.z)
end

-- Vrai si le corps z est tourné vers l'autre côté du bord e (produit scalaire de son orientation avec la normale du
-- bord au moins FACING ; orientation en degrés, vecteur (cos, sin), IsoGameCharacter.java:2626-2635).
function Obstacles.facing(z, e)
    local a = z:getDirectionAngle() * math.pi / 180
    local s = sideOf(e, z:getX(), z:getY()) == "a" and 1 or -1
    local f = e.kind == "W" and math.cos(a) or math.sin(a)
    return f * s >= Obstacles.FACING
end

-- Vrai si ouvrir la fenêtre w avec un zombie armerait l'alarme : option ZombieLore.TriggerHouseAlarm et bâtiment
-- du côté intérieur à alarme (IsoWindow.java:164-173, 328-340, 716-718 ; option lue à chaque appel).
function Obstacles.alarmArmed(w)
    local on
    local opt = getSandboxOptions ~= nil and getSandboxOptions():getOptionByName("ZombieLore.TriggerHouseAlarm") or nil
    if opt ~= nil then
        on = opt:getValue() == true
    else
        on = SandboxVars ~= nil and SandboxVars.ZombieLore ~= nil and SandboxVars.ZombieLore.TriggerHouseAlarm == true
    end
    if not on then return false end
    local sq = w:getIndoorSquare()
    local def = sq ~= nil and sq:getBuildingDef() or nil
    return def ~= nil and def:isAlarmed() == true
end

-- Décision pour le PNJ npcId (tout PNJ, pillards compris) arrêté contre la fenêtre w (kind, cases sqA et sqB, case
-- de l'autre côté far) : rend "open", ou nil et la raison du refus (anglais, journal). Jamais de bris.
-- LK04-T20 : trapped (consigne de dernier recours, e.lr : aucune porte utilisable pour sortir), from = case d'où la
-- fenêtre est abordée. Une fenêtre verrouillée s'ouvre alors depuis une case non extérieure (le joueur vanilla l'ouvre
-- de l'intérieur : OpenWindowState ne lutte que dehors ; ToggleWindow ignore et lève le verrou, IsoWindow.java:701-731),
-- et une fenêtre du foyer d'un autre groupe abordée depuis ce foyer (inHomeOf) n'est plus refusée. Barricade,
-- fenêtre inamovible, chute, meuble à l'arrivée et alarme restent refusés.
function Obstacles.decideWindow(npcId, w, kind, sqA, sqB, far, trapped, from)
    if w:isBarricaded() then return nil, "barricaded window" end
    if kind ~= "window" then return nil, kind .. " window not handled" end
    if w:isPermaLocked() then return nil, "window that cannot be opened" end
    if w:isLocked() and not (trapped and from ~= nil and not from:isOutside()) then
        return nil, "locked window"   -- même au foyer du PNJ : il passe par la porte
    end
    if Obstacles.isDrop(far) then return nil, "window over a drop" end
    if Obstacles.isFurnitureLanding(far) then return nil, "window over furniture" end
    local home = Obstacles.homeOf(sqA, sqB)
    local mine = Obstacles.groupOf(npcId)
    if home ~= nil and home ~= mine and not (trapped and Obstacles.inHomeOf(from, home)) then
        return nil, "window of the home of " .. home .. " (not a member)"
    end
    if Obstacles.alarmArmed(w) then return nil, "window of an alarmed house" end
    return "open"
end

-- Fixe l'état de la fenêtre w (ouverte si open) : ToggleWindow(chr) seulement si l'état diffère (c'est une
-- bascule : jamais deux fois) ; le moteur recalcule la case, met à jour la recherche de chemin et synchronise
-- (IsoWindow.java:701-731). chr : le corps (copie de l'autorité) ou nil (fermeture sans corps : aucune alarme, aucun
-- contrôle de barricade). Rend vrai si la fenêtre est maintenant dans l'état voulu par cet appel.
-- Fenêtre cassée ou inamovible : jamais touchée (ToggleWindow n'y fait rien, IsoWindow.java:705-711) ; bascule
-- comptée seulement si l'état a changé (LK04-T08).
function Obstacles.setWindow(w, open, chr)
    if (w:IsOpen() == true) == open then return false end
    if w:isDestroyed() or w:isPermaLocked() then return false end
    w:ToggleWindow(chr)
    local done = (w:IsOpen() == true) == open
    if done then count("windowToggles") end
    return done
end

-- Ouvre la fenêtre w avec le corps body. Rend vrai si elle est maintenant ouverte par cet appel.
function Obstacles.openWindow(w, body) return Obstacles.setWindow(w, true, body) end

-- Angle (degrés, convention de setDirectionAngle : E 0, S 90, W 180, N 270) qui tourne un corps placé au point
-- (px, py) face au bord e.
function Obstacles.faceAngle(e, px, py)
    local west = sideOf(e, px, py) == "a"
    if e.kind == "W" then return west and 0 or 180 end
    return west and 90 or 270
end

-- Geste devant la fenêtre w du bord e (LK04-T13) : kind "open" (geste openwindow) ou "close" (closewindow), joué par
-- le corps z du PNJ id tourné vers la fenêtre (LivingKnox.Anim.startAct ; l'exécutant arrête le corps et le tourne).
-- La fenêtre n'est basculée qu'à l'instant du clip (windowActPass). Rend vrai si le geste est posé.
function Obstacles.startWindowAct(id, z, w, e, kind, t)
    local A = LivingKnox.Anim
    if not Obstacles.WINDOW_GESTURE or A == nil or A.startAct == nil or z == nil then return false end
    local open = kind == "open"
    local g = open and "openwindow" or "closewindow"
    local ms = open and Obstacles.OPEN_GESTURE_MS or Obstacles.CLOSE_GESTURE_MS
    local ok, why = A.startAct(id, g, ms, Obstacles.faceAngle(e, z:getX(), z:getY()))
    if not ok then
        log().warn("npc %s: %s gesture at the window %s refused: %s", id, g, e.key, tostring(why))
        return false
    end
    t = t or now()
    Obstacles.winActs[e.key] = { win = w, e = e, id = id, kind = kind, g = g, ms = t, endMs = t + ms,
        toggleMs = t + (open and Obstacles.OPEN_TOGGLE_MS or Obstacles.CLOSE_TOGGLE_MS),
        from = sideOf(e, z:getX(), z:getY()), lx = z:getX(), ly = z:getY() }   -- lx, ly : closeReady (LK04-T18)
    count("windowGestures")
    log().info("npc %s: %s gesture at the window %s", id, g, e.key)
    return true
end

-- Fenêtres des bords à REACH case au plus du point (px, py) au niveau z, triées par distance. Chaque élément :
-- { win, wk (sorte), e (bord), d, sqA, sqB }.
function Obstacles.windowsNear(px, py, z)
    local cell = getCell()
    local out = {}
    local fx, fy = math.floor(px), math.floor(py)
    for x = fx - 1, fx + 1 do
        for y = fy - 1, fy + 1 do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                for _, kind in ipairs({ "W", "N" }) do
                    local e = edge(x, y, z, kind)
                    local nb = cell:getGridSquare(e.bx, e.by, z)
                    local w, wk
                    if nb ~= nil then w, wk = LivingKnox.Edges.windowOf(sq, nb) end
                    if w ~= nil then
                        local d = dist(px, py, e.mx, e.my)
                        if d <= Obstacles.REACH then
                            out[#out + 1] = { win = w, wk = wk, e = e, d = d, sqA = sq, sqB = nb }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.e.key < b.e.key
    end)
    return out
end

-- ---------------------------------------------------------------- détection

-- Portes des bords à DETECT cases au plus du point (px, py) au niveau z, triées par distance. Chaque élément :
-- { door, e (bord), d (distance au milieu du bord), sqA, sqB }.
function Obstacles.doorsNear(px, py, z)
    local cell = getCell()
    local out = {}
    local r = math.ceil(Obstacles.DETECT)
    local fx, fy = math.floor(px), math.floor(py)
    for x = fx - r, fx + r do
        for y = fy - r, fy + r do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                for _, kind in ipairs({ "W", "N" }) do
                    local e = edge(x, y, z, kind)
                    local nb = cell:getGridSquare(e.bx, e.by, z)
                    local door = nb and sq:getDoorTo(nb)
                    if door ~= nil then
                        local d = dist(px, py, e.mx, e.my)
                        if d <= Obstacles.DETECT then
                            out[#out + 1] = { door = door, e = e, d = d, sqA = sq, sqB = nb }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.e.key < b.e.key
    end)
    return out
end

-- Vrai si franchir le bord e rapproche le point (px, py) de la case visée (tx, ty) (centres des cases).
function Obstacles.onRoute(e, px, py, tx, ty)
    local nx, ny, fx, fy
    if sideOf(e, px, py) == "a" then
        nx, ny, fx, fy = e.ax, e.ay, e.bx, e.by
    else
        nx, ny, fx, fy = e.bx, e.by, e.ax, e.ay
    end
    return dist(fx + 0.5, fy + 0.5, tx + 0.5, ty + 0.5) < dist(nx + 0.5, ny + 0.5, tx + 0.5, ty + 0.5) - 0.01
end

-- Temps (ms) depuis lequel le corps du PNJ id est immobile (STILL case).
-- E18-T35 : un corps simulé par un client n'est vu du serveur qu'aux rapports de l'exécutant (copie recalée par
-- Directives.syncServerCopy, au moins tous les REPORT_MS) ou aux paquets du moteur (200 ms à 4 s) : entre deux, sa copie
-- paraît immobile alors qu'il marche. Cette attente est retranchée (campagne MP à un client du 2026-11-12 : porte
-- refusée longée, prise « au contact » après 800 ms et ouverte de l'intérieur).
local function stillFor(id, z, t)
    local tr = Obstacles.track[id]
    if tr == nil or dist(tr.x, tr.y, z:getX(), z:getY()) >= Obstacles.STILL then
        Obstacles.track[id] = { x = z:getX(), y = z:getY(), ms = t }
        return 0
    end
    local blind = (isServer() and z:getOwner() ~= nil) and Dir().REPORT_MS or 0
    return math.max(0, t - tr.ms - blind)
end

-- Vrai si le corps z est en train d'escalader (fenêtre ou clôture : nom de l'état d'action, en minuscules).
local function climbing(z)
    local st = z ~= nil and z:getActionStateName() or nil
    return st == "climbwindow" or st == "climbfence"
end

-- Refus d'une consigne bloquée par une porte (what = "door") ou une fenêtre ("window"). LK17-T01 : le gestionnaire
-- Obstacles.onRefusal (LK_Detour.lua : function(id, e, c, why, what), vrai si la consigne a reçu un détour) est
-- consulté d'abord ; détour donné : consigne gardée, immobilité du corps remise à zéro (aucun second refus avant
-- REFUSE_MS). Sinon close en échec par l'autorité.
local function refuse(id, e, c, why, what)
    what = what or "door"
    count("refused")
    Obstacles.lastRefused = { id = id, what = what, key = c.e.key, why = why, ms = now() }
    if Obstacles.onRefusal ~= nil and Obstacles.onRefusal(id, e, c, why, what) then
        count("detoured")
        Obstacles.track[id] = nil
        log().info("npc %s: move #%d refused at the %s %s: %s; detour given", id, e.v, what, c.e.key, why)
        return
    end
    log().warn("npc %s: move #%d refused at the %s %s: %s", id, e.v, what, c.e.key, why)
    -- E18-T38 : sans détour, case visée derrière une fenêtre refusée écartée comme après un échec "stuck"
    -- (Movement.AVOID_MS) : le même trajet revenait sur la même fenêtre verrouillée à chaque consigne (campagne solo du
    -- 2026-11-13 : 37 refus de suite).
    local Mv = LivingKnox.Movement
    if what == "window" and Mv ~= nil and Mv.noteStuck ~= nil then Mv.noteStuck(id, e) end
    Dir().abort(id, what .. " " .. c.e.key .. ": " .. why)
end

-- Fenêtre contre laquelle le corps z du PNJ id (consigne e) est arrêté depuis still ms : ouverture (notée pour être
-- refermée) ou refus (voir l'en-tête). Une seule fenêtre par passage. Rend vrai si une fenêtre a été traitée.
function Obstacles.checkWindows(id, e, z, still, t)
    if still < Obstacles.STUCK_MS then return false end
    -- E18-T34 : corps mené vers la porte d'un détour (LK17-T01, Directives.detouring) : l'arrêt vient de la porte ou
    -- d'un pas du chemin, jamais d'une fenêtre à ouvrir (campagne MP du 2026-11-08,
    -- runs/20261108-012549-mp-a2dbaf99cf8b : fenêtre du foyer ouverte par un membre arrêté à sa porte).
    if Dir().detouring(e) then return false end
    t = t or now()
    local px, py = z:getX(), z:getY()
    local near = Obstacles.windowsNear(px, py, math.floor(z:getZ()))
    -- LK04-T20 : fenêtre voisine ouverte par ce PNJ (ou geste en cours) : il va la franchir ; une autre fenêtre au
    -- contact (barricadée à côté) n'est pas une raison de refuser la consigne.
    local ownWay = false
    for _, c in ipairs(near) do
        local ow, wa = Obstacles.openWins[c.e.key], Obstacles.winActs[c.e.key]
        if (ow ~= nil and ow.id == id and not Obstacles.windowBlocks(c.win, c.wk)) or (wa ~= nil and wa.id == id) then
            ownWay = true
        end
    end
    for _, c in ipairs(near) do
        local cb = Obstacles.closedBy[c.e.key]
        local guarded = cb ~= nil and cb.id == id and t - cb.ms < Obstacles.CLOSE_GUARD_MS   -- refermée par lui
        if not guarded and Obstacles.windowBlocks(c.win, c.wk) and Obstacles.facing(z, c.e) then
            if Obstacles.winActs[c.e.key] ~= nil then return true end   -- geste en cours : bascule par windowActPass
            local act, why = Obstacles.decideWindow(id, c.win, c.wk, c.sqA, c.sqB, farSquare(c.e, px, py),
                e.lr == true, nearSquare(c.e, px, py, c.sqA, c.sqB))   -- LK04-T20 : dernier recours
            if act == "open" and Obstacles.startWindowAct(id, z, c.win, c.e, "open", t) then
                return true   -- LK04-T13 : ouverte à l'instant du geste (windowActPass)
            elseif act == "open" and Obstacles.openWindow(c.win, z) then
                count("windowsOpened")
                Obstacles.openWins[c.e.key] = { win = c.win, e = c.e, id = id, ms = t, seenMs = t,
                    from = sideOf(c.e, px, py) }
                log().info("npc %s: window %s opened (group %s)", id, c.e.key, tostring(Obstacles.groupOf(id)))
            elseif still >= Obstacles.REFUSE_MS and not climbing(z) and not ownWay
                and not Obstacles.onBlocked(id, e, z, c, why or "window did not open", "window", t) then
                count("windowsRefused")
                refuse(id, e, c, why or "window did not open", "window")
            end
            return true
        end
    end
    return false
end

-- Fenêtres ouvertes ici que franchir rapproche le corps z du PNJ id de l'étape (tx, ty) : ce PNJ en devient le
-- dernier passant (et son côté) ; bord noté dans seen (pas de refermeture à ce passage).
function Obstacles.noteWindows(id, z, tx, ty, seen, t)
    local px, py, pz = z:getX(), z:getY(), math.floor(z:getZ())
    for key, rec in pairs(Obstacles.openWins) do
        local e = rec.e
        if e.z == pz and dist(px, py, e.mx, e.my) <= Obstacles.DETECT and Obstacles.onRoute(e, px, py, tx, ty) then
            seen[key] = true
            rec.id, rec.seenMs, rec.from = id, t, sideOf(e, px, py)
        end
    end
end

-- Vrai si la porte fermée door est basse (portail de clôture) : le corps l'enjambe, verrouillée ou non, et ne s'y
-- arrête jamais (IsoZombie.java:3051-3058 tryThump, 1075 collideWith exclut IsoDoor enjambable ; IsoThumpable :
-- 3065-3071 ; IsoDoor.java:1244-1253). LK04-T08.
function Obstacles.isLowGate(door)
    return LivingKnox.Edges.isLowGate(door)
end

-- Portes du PNJ id (consigne e, corps z) : ouverture ou refus. seen : clés des bords sur un trajet à ce passage.
-- Jamais de refus pendant une escalade, ni devant une porte basse (enjambée par le moteur).
-- Une porte qui rapproche de l'étape SUIVANTE compte aussi (LK04-T09, détour LK17-T01) : le point de passage « case
-- avant la porte » est atteint à ARRIVE case près, souvent à moins d'une case de la porte ; elle est ainsi ouverte
-- avant (en course, moins d'une demi-seconde sépare l'arrivée sur ce point du contact).
function Obstacles.check(id, e, z, seen, t)
    local px, py, pz = z:getX(), z:getY(), math.floor(z:getZ())
    local tx, ty = Dir().stepTarget(e, e.k)
    local k = (type(e.k) == "number" and e.k >= 1) and e.k or 1
    local nx, ny
    if type(e.w) == "table" and k <= #e.w then nx, ny = Dir().stepTarget(e, k + 1) end
    -- LK04-T17 (lk.traversal du 2026-10-12, « refused door next to a low fence ») : l'immobilité ne court pas pendant
    -- une escalade (corps figé par l'animation) ; sinon, à la fin de l'escalade, une porte refusée LONGEANT le trajet
    -- était « au contact » depuis plus de REFUSE_MS et la consigne échouait.
    if climbing(z) then Obstacles.track[id] = { x = px, y = py, ms = t } end
    local still = stillFor(id, z, t)
    local near = Obstacles.doorsNear(px, py, pz)
    local function onWay(c)
        return Obstacles.onRoute(c.e, px, py, tx, ty) or (nx ~= nil and Obstacles.onRoute(c.e, px, py, nx, ny))
    end
    -- E18-T31 (campagne MP du 2026-11-08, runs/20261108-101002-mp-0569ec9c26f8, lk.traversal) : une porte du même mur
    -- une case à côté rapproche aussi de l'étape ; tant que la porte ouverte par ce PNJ n'est pas franchie, une autre
    -- porte fermée n'est ouverte qu'au contact.
    local pending = false
    for _, c in ipairs(near) do
        local rec = Obstacles.opened[c.e.key]
        if rec ~= nil and rec.door == c.door and rec.id == id and Obstacles.isOpen(c.door) and onWay(c) then
            pending = true
        end
    end
    for _, c in ipairs(near) do
        local contact = still >= Obstacles.STUCK_MS and c.d <= Obstacles.REACH
        local route = onWay(c)
        if pending and route and not contact and not Obstacles.isOpen(c.door) then route = false end
        if contact or route then
            seen[c.e.key] = true
            local rec = Obstacles.opened[c.e.key]
            if rec ~= nil and rec.door == c.door then   -- dernier PNJ qui l'a sur son trajet, et son côté
                rec.id, rec.seenMs, rec.from = id, t, sideOf(c.e, px, py)
            end
            if not Obstacles.isOpen(c.door) or c.door:isBarricaded() then
                local act, lockAfter, home, keyId, inside = Obstacles.decide(id, c.door, c.sqA, c.sqB, z,
                    nearSquare(c.e, px, py, c.sqA, c.sqB), e.lr == true)   -- refus : lockAfter = raison
                if act == "open" then
                    local wasLocked = Obstacles.isLocked(c.door)
                    Obstacles.setDoor(c.door, true)
                    count("opened")
                    Obstacles.opened[c.e.key] = { door = c.door, e = c.e, id = id, ms = t, seenMs = t,
                        from = sideOf(c.e, px, py), lock = lockAfter == true, home = home, keyId = keyId }
                    -- LK04-T17 : sans clé portée, ouverte de l'intérieur (opensFromInside) ; LK04-T19 : reverrouillée
                    -- derrière lui avec la clé de son foyer.
                    local how = inside and " from inside" or (" with its key " .. tostring(keyId))
                    if inside and lockAfter then how = how .. " (to be relocked with its home key " .. tostring(keyId)
                        .. ")" end
                    log().info("npc %s: door %s opened%s", id, c.e.key, wasLocked and (" and unlocked"
                        .. (home and (" (member of " .. tostring(home) .. ")") or "") .. how) or "")
                elseif contact and still >= Obstacles.REFUSE_MS and not climbing(z)
                    and not Obstacles.isLowGate(c.door) and (route or Obstacles.facing(z, c.e)) then
                    -- LK04-T17 : porte au contact refusée seulement sur le trajet ou en face du corps (pas celle qu'il
                    -- longe), comme une fenêtre (checkWindows).
                    -- LK04-T04 : attendre ou forcer selon le type de groupe, sinon refus (voir « passage bloqué »).
                    if not Obstacles.onBlocked(id, e, z, c, lockAfter, "door", t) then refuse(id, e, c, lockAfter) end
                    return
                end
            end
        end
    end
    Obstacles.noteWindows(id, z, tx, ty, seen, t)
    Obstacles.checkWindows(id, e, z, still, t)
end

-- ---------------------------------------------------------------- passage bloqué (LK04-T04)
-- Fiche : deplacement.md, section « Passage bloqué : attendre ou forcer ». Un passage est bloqué quand le corps reste
-- au contact d'une porte ou d'une fenêtre refusée (REFUSE_MS). Comportement selon l'hostilité du type de groupe du PNJ
-- (blockedPolicy), avant le refus (qui donne un détour par une porte s'il y en a une, LK_Detour.lua, LK17-T01) :
--   - "detour" (colons, PNJ sans groupe) : refus aussitôt (détour, ou consigne close en échec : le cadre de décision
--     choisit autre chose) ;
--   - "wait" (neutres) : le corps attend WAIT_MS devant l'obstacle (geste ponctuel "wait", clip de repos : l'exécutant
--     le garde arrêté et tourné vers l'obstacle), passage repris dès que l'obstacle cède (porte ouverte ou
--     déverrouillée par quelqu'un, barricade retirée) ; refus à la fin de l'attente ;
--   - "force" (pillards) : le corps frappe l'obstacle (geste ponctuel "force", clip "strike" du combat en boucle) et
--     l'autorité applique un coup par boucle du clip (STRIKE_MS, premier à IMPACT_MS) avec le chemin vanilla d'un coup
--     d'arme sur un objet : IsoBarricade:WeaponHit (barricade du côté du corps, puis celle d'en face ; dégâts
--     DoorDamage x 5 sur la planche extérieure ou le métal, synchronisés par sync() sur le serveur, barricade retirée
--     pour tous à la dernière planche : J/iso/objects/IsoBarricade.java:416-457, 459-501) puis IsoDoor:WeaponHit pour
--     une porte verrouillée sans clé (dégâts DoorDamage x 2 x 0,5 : force 0 d'un zombie, plus un coup fort 1 fois sur
--     10 ; porte cassée à 0 : destroy(), planches, poignée et charnières au sol, porte retirée pour tous :
--     J/iso/objects/IsoDoor.java:1056-1176, 1178-1210). Planche retirée : sendObjectChange(STATE) en plus (comme
--     IsoBarricade.Thump, :375-379 : sync() ne redessine pas la barricade chez les clients, loadChange le fait :
--     :646-656). Porte d'un autre foyer non verrouillée : ouverte (setDoor) et refermée derrière comme les autres.
--     Arme : celle du PNJ (LivingKnox.Equipment.wantedOf), de mêlée, DoorDamage >= FORCE_MIN_DOOR_DAMAGE ; sans arme
--     capable (mains nues : DoorDamage 0, arme à feu), pas de forçage. Abandon (refus) après FORCE_GIVE_UP_MS.
-- Jamais forcé : le foyer d'un groupe AMI DES JOUEURS (hostilité du type < FRIENDLY_HOSTILITY : colons, neutres) sans
-- consigne explicite (Obstacles.orderForce, valable pour un "move" donné) ; porte double, de garage, construite
-- (IsoThumpable), cadenassée ou obstruée ; fenêtre seulement barricadée (jamais brisée, LK04-T03 : après la barricade,
-- règles des fenêtres). Pendant une attente ou un forçage : aucune autre décision d'obstacle pour ce PNJ ; une autre
-- consigne (cadre de décision, combat) l'interrompt. Interrupteur BLOCKED_RULES (coupé : refus aussitôt pour tous).
Obstacles.BLOCKED_RULES = true
Obstacles.FORCE_HOSTILITY = 75      -- hostilité du type au moins : force (pillards 90 ; même seuil que « tire le premier »)
Obstacles.WAIT_HOSTILITY = 30       -- au moins : attend (neutres 45) ; en deçà : refus aussitôt (colons 10)
Obstacles.FRIENDLY_HOSTILITY = 50   -- foyer d'un groupe dont le type est en deçà : ami des joueurs, jamais forcé
Obstacles.WAIT_MS = 15000           -- attente devant un passage bloqué
Obstacles.FORCE_GIVE_UP_MS = 240000 -- forçage abandonné après ce temps (refus ; une porte à la batte demande environ 2 min)
Obstacles.STRIKE_MS = 1250          -- boucle du clip de frappe (LivingKnox.Config.COMBAT.STRIKE_MS : 1,0 s à 0,80)
Obstacles.IMPACT_MS = 312           -- impact dans la boucle (AttackCollisionCheck à 25 % du clip)
Obstacles.FORCE_MIN_DOOR_DAMAGE = 1 -- DoorDamage minimal de l'arme (Sledgehammer 40, Axe 35, Crowbar 8, BaseballBat 5)
Obstacles.ACT_RENEW_MS = 3000       -- geste ponctuel renouvelé quand il lui reste moins que ce temps (Anim.ACT_MAX_MS)

Obstacles.forcing = Obstacles.forcing or {}       -- npcId -> forçage en cours
Obstacles.waiting = Obstacles.waiting or {}       -- npcId -> attente en cours
Obstacles.forceOrders = Obstacles.forceOrders or {}   -- npcId -> { v } consigne explicite de forcer (un "move")
Obstacles.weapons = Obstacles.weapons or {}       -- type d'arme -> objet HandWeapon de l'autorité (false : aucun)

-- Hostilité du type du groupe gid (LivingKnox.GroupTypes), ou nil.
function Obstacles.typeHostility(gid)
    local G, T = LivingKnox.Groups, LivingKnox.GroupTypes
    if gid == nil or G == nil or T == nil or not G.isReady() then return nil end
    local g = G.peek(gid)   -- LK13-T08 : lecture en place, seule
    local def = g and T.get(g.type) or nil
    return def and def.hostility or nil
end

-- Comportement du PNJ npcId devant un passage bloqué : "force", "wait" ou "detour" (voir l'en-tête de la section).
function Obstacles.blockedPolicy(npcId)
    if not Obstacles.BLOCKED_RULES then return "detour" end
    local h = Obstacles.typeHostility(Obstacles.groupOf(npcId))
    if type(h) ~= "number" then return "detour" end
    if h >= Obstacles.FORCE_HOSTILITY then return Obstacles.breachPolicy(npcId) end
    if h >= Obstacles.WAIT_HOSTILITY then return "wait" end
    return "detour"
end

-- Comportement "breach" (rôle casseur des pillards, décision du 2026-11-13) : un membre dont le rôle le permet force ;
-- les autres attendent (WAIT_MS) qu'un casseur du groupe, incarné à BREACH_RANGE cases au plus, ouvre le passage ;
-- sans casseur sur place (resté au foyer, mort, sans corps) : chacun force comme avant.
Obstacles.BREACH_RANGE = 20
function Obstacles.breachPolicy(npcId)
    local G, D = LivingKnox.Groups, LivingKnox.Decisions
    local gid, mid = nil, nil
    if G ~= nil and G.isReady() then gid, mid = G.findNpc(npcId) end
    local g = gid and G.peek(gid) or nil
    if g == nil or D == nil or D.allowedOf == nil then return "force" end
    local function breaks(m) return m ~= nil and m.role ~= nil and (D.allowedOf(g.type, m.role) or {}).breach == true end
    if breaks(g.members[mid]) then return "force" end
    local B = LivingKnox.Bodies
    local me = B and B.find(npcId) or nil
    if me == nil then return "force" end
    for omid, m in pairs(g.members) do
        local other = omid ~= mid and m.npc ~= nil and breaks(m) and B.find(m.npc) or nil
        if other ~= nil and math.abs(other:getX() - me:getX()) <= Obstacles.BREACH_RANGE
            and math.abs(other:getY() - me:getY()) <= Obstacles.BREACH_RANGE then
            return "wait"
        end
    end
    return "force"
end

-- Consigne explicite (autorité) : le PNJ npcId peut forcer le foyer d'un groupe ami des joueurs pendant le "move" v
-- (défaut : sa consigne "move" ouverte). Rend vrai, ou faux et une raison.
function Obstacles.orderForce(npcId, v)
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    local e = Dir().entries[npcId]
    if v == nil and e ~= nil and e.op == Dir().OP_MOVE and not e.done then v = e.v end
    if type(v) ~= "number" then return false, "no open move for npc " .. tostring(npcId) end
    Obstacles.forceOrders[npcId] = { v = v }
    log().info("npc %s: may force the home of a friendly group during move #%d (explicit order)", npcId, v)
    return true
end

local function ordered(id, e)
    local o = Obstacles.forceOrders[id]
    return o ~= nil and e ~= nil and o.v == e.v
end

-- Arme de forçage du PNJ npcId : son arme de mêlée (Equipment.wantedOf) si elle abîme une porte, sinon nil.
function Obstacles.forceWeapon(npcId)
    local E = LivingKnox.Equipment
    local spec = E ~= nil and E.wantedOf ~= nil and E.wantedOf(npcId) or nil
    local t = spec and spec.t
    if type(t) ~= "string" then return nil end
    local w = Obstacles.weapons[t]
    if w == nil then
        w = instanceItem(t)
        if w == nil or not instanceof(w, "HandWeapon") then w = false end
        Obstacles.weapons[t] = w
    end
    if w == false or w:isRanged() then return nil end
    local dd = w:getDoorDamage()
    if type(dd) ~= "number" or dd < Obstacles.FORCE_MIN_DOOR_DAMAGE then return nil end
    return w
end

-- Arme du forçage en cours rec (objet), ou nil.
local function weaponOf(rec)
    local w = Obstacles.weapons[rec.weapon]
    if w == nil or w == false then return nil end
    return w
end

-- Le PNJ npcId (consigne e) peut-il forcer l'obstacle c (what "door" ou "window", refusé pour why) ? Rend l'arme, ou
-- nil et la raison.
function Obstacles.canForce(npcId, e, c, what, why)
    local home
    if what == "window" then
        if not c.win:isBarricaded() then return nil, tostring(why) .. ": only a barricade is forced" end
        home = Obstacles.homeOf(c.sqA, c.sqB)
    else
        local d = c.door
        if isThumpable(d) then return nil, "built door never forced" end
        local kind = Obstacles.kindOf(d)
        if kind ~= "single" then return nil, kind .. " door not forced" end
        if d:isObstructed() then return nil, "obstructed door" end
        home = Obstacles.homeOf(c.sqA, c.sqB)
        local other = home ~= nil and home ~= Obstacles.groupOf(npcId)
        if not (d:isBarricaded() or Obstacles.isLocked(d) or other) then return nil, tostring(why) end
    end
    if home ~= nil and home ~= Obstacles.groupOf(npcId) and not ordered(npcId, e) then
        local h = Obstacles.typeHostility(home)
        if type(h) == "number" and h < Obstacles.FRIENDLY_HOSTILITY then
            return nil, "home of " .. home .. ", a group friendly to the players (no order to force it)"
        end
    end
    local w = Obstacles.forceWeapon(npcId)
    if w == nil then return nil, "no weapon able to damage a door" end
    return w
end

-- Geste ponctuel g ("force" ou "wait") du corps z du PNJ id tourné vers le bord de rec, posé ou renouvelé avant son
-- échéance (Anim.ACT_MAX_MS au plus ; until : fin voulue, facultative).
local function holdAct(id, z, rec, g, t, untilMs)
    local A = LivingKnox.Anim
    if A == nil or A.startAct == nil then return false end
    local act = A.actOf(id)
    if act == g and rec.actUntil ~= nil and rec.actUntil - t >= Obstacles.ACT_RENEW_MS then return true end
    local ms = A.ACT_MAX_MS or 10000
    if untilMs ~= nil then ms = math.max(1, math.min(ms, untilMs - t)) end
    local ok = A.startAct(id, g, ms, Obstacles.faceAngle(rec.e, z:getX(), z:getY()))
    if ok then rec.actUntil = t + ms end
    return ok == true
end

local function endHold(id, g)
    local A = LivingKnox.Anim
    if A ~= nil and A.endAct ~= nil then A.endAct(id, g) end
end

-- Passage bloqué du PNJ id (consigne e, corps z) au contact de l'obstacle c (what "door" ou "window", refusé pour why).
-- Rend vrai si le PNJ attend ou force (aucun refus maintenant), faux si l'appelant doit refuser la consigne.
function Obstacles.onBlocked(id, e, z, c, why, what, t)
    t = t or now()
    local f, w = Obstacles.forcing[id], Obstacles.waiting[id]
    if (f ~= nil and f.v == e.v) or (w ~= nil and w.v == e.v) then return true end   -- un obstacle à la fois
    local policy = Obstacles.blockedPolicy(id)
    local rec = { v = e.v, key = c.e.key, e = c.e, what = what, door = c.door, win = c.win, wk = c.wk, sqA = c.sqA,
        sqB = c.sqB, why = why, ms = t, from = sideOf(c.e, z:getX(), z:getY()) }
    if policy == "force" then
        local weapon, cause = Obstacles.canForce(id, e, c, what, why)
        if weapon == nil then
            count("forceRefused")
            log().info("npc %s: %s %s not forced: %s", id, what, c.e.key, tostring(cause))
            return false
        end
        rec.weapon, rec.nextMs, rec.hits, rec.planks = weapon:getFullType(), t + Obstacles.IMPACT_MS, 0, 0
        Obstacles.forcing[id] = rec
        holdAct(id, z, rec, "force", t)
        count("forcings")
        log().info("npc %s: forcing the %s %s (%s) with %s%s", id, what, c.e.key, tostring(why), rec.weapon,
            ordered(id, e) and " (explicit order)" or "")
        return true
    elseif policy == "wait" then
        rec.untilMs = t + Obstacles.WAIT_MS
        Obstacles.waiting[id] = rec
        holdAct(id, z, rec, "wait", t, rec.untilMs)
        count("waits")
        log().info("npc %s: waiting %d ms at the %s %s (%s)", id, Obstacles.WAIT_MS, what, c.e.key, tostring(why))
        return true
    end
    return false
end

-- Vrai si l'objet o (porte, fenêtre) n'est plus dans le monde.
local function gone(o)
    return o == nil or o:getSquare() == nil or o:getObjectIndex() == -1
end

-- Vrai si l'obstacle de rec ne bloque plus le PNJ id : porte retirée, ouverte et sans barricade, ou décision "open" ;
-- fenêtre retirée, ou qui ne l'arrête plus, ou décision "open".
local function passable(id, rec, z)
    local de = Dir().entries[id]
    local trapped = de ~= nil and de.v == rec.v and de.lr == true   -- LK04-T20 : dernier recours de cette consigne
    local near = nearSquare(rec.e, z:getX(), z:getY(), rec.sqA, rec.sqB)
    if rec.what == "door" then
        local d = rec.door
        if gone(d) or d:isDestroyed() then return true end
        if d:isBarricaded() then return false end
        if Obstacles.isOpen(d) then return true end
        return Obstacles.decide(id, d, rec.sqA, rec.sqB, z, near, trapped) == "open"
    end
    local w = rec.win
    if gone(w) then return true end
    if w:isBarricaded() then return false end
    if not Obstacles.windowBlocks(w, rec.wk or "window") then return true end
    local px, py = z:getX(), z:getY()
    return Obstacles.decideWindow(id, w, "window", rec.sqA, rec.sqB, farSquare(rec.e, px, py), trapped, near)
        == "open"
end

-- Barricade à frapper sur l'objet o pour le corps z : celle de son côté, sinon celle d'en face (ordre de
-- IsoDoor.getThumpableFor, J/iso/objects/IsoDoor.java:1032-1046).
local function barricadeFor(o, z)
    local b = o:getBarricadeForCharacter(z)
    if b == nil then b = o:getBarricadeOppositeCharacter(z) end
    return b
end

-- Un coup du corps z (PNJ id) sur l'obstacle de rec, avec l'arme w. Rend "hit" ou "done" (porte non verrouillée
-- d'un autre foyer ouverte ici) ; nil et raison si l'obstacle ne se force plus.
local function strikeOnce(id, rec, z, w, t)
    local o = rec.what == "door" and rec.door or rec.win
    local b = barricadeFor(o, z)
    if b ~= nil then
        local n0 = b:getNumPlanks()
        b:WeaponHit(z, w)
        rec.hits = rec.hits + 1
        count("forceHits")
        local destroyed = b:isDestroyed()
        local n1 = destroyed and 0 or b:getNumPlanks()
        if n1 < n0 then
            rec.planks = rec.planks + (n0 - n1)
            local st = Obstacles.stats
            st.planksBroken = (st.planksBroken or 0) + (n0 - n1)
            log().info("npc %s: plank of the barricade on the %s %s broken (%d left)", id, rec.what, rec.key, n1)
            -- sync() de Damage ne redessine pas la barricade chez les clients : STATE comme IsoBarricade.Thump.
            if not destroyed and isServer() then b:sendObjectChange(IsoObjectChange.STATE) end
        end
        if destroyed then
            count("barricadesBroken")
            log().info("npc %s: barricade on the %s %s broken", id, rec.what, rec.key)
        end
        return "hit"
    end
    if rec.what ~= "door" then return nil, "window no longer barricaded" end
    local d = rec.door
    if Obstacles.isLocked(d) then
        d:WeaponHit(z, w)
        rec.hits = rec.hits + 1
        count("forceHits")
        if gone(d) or d:isDestroyed() then
            count("doorsBroken")
            log().info("npc %s: door %s broken", id, rec.key)
        end
        return "hit"
    end
    -- Porte non verrouillée et sans barricade d'un autre foyer : ouverte (refermée derrière lui, jamais verrouillée).
    local home = Obstacles.homeOf(rec.sqA, rec.sqB)
    if home ~= nil and home ~= Obstacles.groupOf(id) and not Obstacles.isOpen(d) then
        Obstacles.setDoor(d, true)
        count("opened")
        Obstacles.opened[rec.key] = { door = d, e = rec.e, id = id, ms = t, seenMs = t, from = rec.from, lock = false }
        log().info("npc %s: door %s of the home of %s opened by force", id, rec.key, home)
        return "done"
    end
    return nil, tostring(rec.why)
end

-- Fin d'une attente ou d'un forçage : geste ponctuel retiré ; refus de la consigne si why est donné.
local function release(id, rec, list, g, outcome, refuseWhy)
    list[id] = nil
    endHold(id, g)
    log().info("npc %s: %s at the %s %s ended after %d ms: %s", id, g == "force" and "forcing" or "waiting", rec.what,
        rec.key, now() - rec.ms, outcome)
    if refuseWhy ~= nil then
        local e = Dir().entries[id]
        if e ~= nil and not e.done and e.v == rec.v then refuse(id, e, rec, refuseWhy, rec.what) end
    end
end

-- Raison d'arrêter une attente ou un forçage sans refus (consigne changée, corps parti), ou nil.
local function interrupted(id, rec, z)
    local e = Dir().entries[id]
    if e == nil or e.done or e.v ~= rec.v or e.op ~= Dir().OP_MOVE or e.suspended ~= nil then
        return "move no longer running"
    end
    if z == nil or not Bodies().inWorld(z) then return "body gone" end
    return nil
end

-- À chaque passage : attentes et forçages en cours (voir l'en-tête de la section).
function Obstacles.blockedPass(t)
    for _, list in ipairs({ Obstacles.waiting, Obstacles.forcing }) do
        local ids = {}
        for id in pairs(list) do ids[#ids + 1] = id end
        table.sort(ids)   -- ordre déterministe ; table modifiée hors de pairs
        local forcing = list == Obstacles.forcing
        local g = forcing and "force" or "wait"
        for _, id in ipairs(ids) do
            local rec = list[id]
            local z = Bodies().find(id)
            local stop = interrupted(id, rec, z)
            if stop ~= nil then
                release(id, rec, list, g, stop)
            elseif passable(id, rec, z) then
                count(forcing and "forced" or "waitResumed")
                release(id, rec, list, g, forcing and string.format("way open (%d hit(s), %d plank(s) broken)",
                    rec.hits, rec.planks) or "way open")
            elseif not forcing then
                if t >= rec.untilMs then
                    count("waitedOut")
                    release(id, rec, list, g, "nobody opened", rec.why .. " (waited " .. Obstacles.WAIT_MS .. " ms)")
                else
                    holdAct(id, z, rec, "wait", t, rec.untilMs)
                end
            elseif t - rec.ms >= Obstacles.FORCE_GIVE_UP_MS then
                count("forceGivenUp")
                release(id, rec, list, g, "given up", rec.why .. " (forcing given up after " .. rec.hits .. " hit(s))")
            else
                holdAct(id, z, rec, "force", t)
                local w = weaponOf(rec)
                if w == nil then
                    release(id, rec, list, g, "no weapon", rec.why)
                elseif t >= rec.nextMs then
                    rec.nextMs = math.max(rec.nextMs + Obstacles.STRIKE_MS, t + 1)
                    local res, why = strikeOnce(id, rec, z, w, t)
                    if res == nil then
                        release(id, rec, list, g, "cannot be forced", why)
                    elseif res == "done" then
                        count("forced")
                        release(id, rec, list, g, "door opened")
                    end
                end
            end
        end
    end
    local drop = {}
    for id, o in pairs(Obstacles.forceOrders) do
        local e = Dir().entries[id]
        if e == nil or e.v ~= o.v or e.done then drop[#drop + 1] = id end
    end
    for _, id in ipairs(drop) do Obstacles.forceOrders[id] = nil end
end

-- ---------------------------------------------------------------- refermeture

-- Vrai si un objet mobile occupe les cases de la porte ou de la fenêtre notée rec. except : le corps qui la referme
-- (LK04-T18 : arrêté sur la case d'arrivée d'une fenêtre, il n'empêche pas sa propre fermeture).
local function occupied(rec, except)
    local cell = getCell()
    for _, p in ipairs({ { rec.e.ax, rec.e.ay }, { rec.e.bx, rec.e.by } }) do
        local sq = cell:getGridSquare(p[1], p[2], rec.e.z)
        local list = sq ~= nil and sq:getMovingObjects() or nil
        for i = 0, (list ~= nil and list:size() or 0) - 1 do
            if list:get(i) ~= except then return true end
        end
    end
    -- Porte de garage (LK04-T17) : cases des deux côtés de chaque panneau, et véhicule sous un panneau (approche de
    -- isGarageDoorObstructed, privé : IsoDoor.isDoorObstructed de chaque panneau, IsoDoor.java:2288-2324).
    if rec.door ~= nil and Obstacles.kindOf(rec.door) == "garage" then
        for _, pn in ipairs(Obstacles.panelsOf(rec.door)) do
            if pn:isObstructed() then return true end
            for _, sq in ipairs({ pn:getSquare(), oppositeOf(pn) }) do
                if sq ~= nil and sq:getMovingObjects():size() > 0 then return true end
            end
        end
    end
    return false
end

-- Vrai si le dernier passant de la porte ou de la fenêtre notée rec (corps z) est passé de l'autre côté, n'a plus de
-- "move" en cours, ou ne l'a plus sur son trajet depuis CLOSE_AFTER_MS.
local function passedOrStale(rec, z, t)
    local passed = sideOf(rec.e, z:getX(), z:getY()) ~= rec.from
    local d = Dir().entries[rec.id]
    local going = d ~= nil and d.op == Dir().OP_MOVE and not d.done
    return passed or not going or t - rec.seenMs >= Obstacles.CLOSE_AFTER_MS
end

-- Vrai si la porte notée rec peut être refermée maintenant (voir l'en-tête).
local function closeDue(rec, t)
    local z = Bodies().find(rec.id)
    if z == nil then return true end
    local away = dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) >= Obstacles.CLOSE_DIST
    if not away then return false end
    return passedOrStale(rec, z, t)
end

-- Portes ouvertes ici : refermées (et reverrouillées) quand c'est dû. seen : bords encore sur un trajet.
function Obstacles.closePass(seen, t)
    local drop, shut = {}, {}
    for key, rec in pairs(Obstacles.opened) do
        local door = rec.door
        if gone(door) then
            drop[#drop + 1] = key
        elseif not Obstacles.isOpen(door) then
            drop[#drop + 1] = key   -- refermée par quelqu'un d'autre : plus à nous
        elseif not seen[key] and closeDue(rec, t) then
            if occupied(rec) then
                count("busy")
                if t - rec.ms >= Obstacles.GIVE_UP_MS then
                    count("givenUp")
                    log().warn("door %s left open: its squares stay occupied", key)
                    drop[#drop + 1] = key
                end
            else
                shut[#shut + 1] = key
            end
        end
    end
    for _, key in ipairs(shut) do   -- table modifiée hors de pairs
        local rec = Obstacles.opened[key]
        -- LK04-T12 : reverrouillée seulement si le PNJ porte toujours la clé (corps disparu : clé gardée par le PNJ).
        local lock = rec.lock
        local z = lock and Bodies().find(rec.id) or nil
        if z ~= nil and not Obstacles.hasKey(z, rec.keyId) then
            lock = false
            log().info("door %s: npc %s lost its key, left unlocked", key, rec.id)
        end
        Obstacles.setDoor(rec.door, false, lock)
        count("closed")
        log().info("door %s closed behind npc %s%s", key, rec.id, lock and " and locked" or "")
        Obstacles.opened[key] = nil
    end
    for _, key in ipairs(drop) do Obstacles.opened[key] = nil end
end

-- Consigne "move" ouverte et non suspendue du PNJ id (moving), ou close à l'arrivée (arrived).
local function moveState(id)
    local d = Dir().entries[id]
    if d == nil or d.op ~= Dir().OP_MOVE then return nil end
    if not d.done then return d.suspended == nil and "moving" or nil end
    return d.s == "arrived" and "arrived" or nil
end

-- Vrai si la fenêtre notée rec peut être refermée maintenant par le corps z de son dernier passant (LK04-T18, voir
-- l'en-tête) : corps dans le monde, au niveau de la fenêtre, hors escalade, à ACT_REACH case au plus du milieu du
-- bord, et passé de l'autre côté (ou consigne changée, ou CLOSE_AFTER_MS sans passage). Jamais de loin.
local function windowCloseDue(rec, z, t)
    if z == nil or not Bodies().inWorld(z) or climbing(z) or math.floor(z:getZ()) ~= rec.e.z then return false end
    if dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) > Obstacles.ACT_REACH then return false end
    return passedOrStale(rec, z, t)
end

-- Fenêtre notée rec à refermer (LK04-T13) par le corps z (windowCloseDue vrai) : geste de fermeture si la consigne
-- est un "move" en marche ou arrivé (une autre consigne, regard ou arrêt, n'est pas détournée). Rend vrai si le geste
-- est posé (fenêtre fermée plus tard par windowActPass, l'exécutant arrête le corps).
local function closeWithGesture(rec, z, t)
    if not Obstacles.WINDOW_GESTURE or moveState(rec.id) == nil then return false end
    return Obstacles.startWindowAct(rec.id, z, rec.win, rec.e, "close", t)
end

-- Geste de fermeture r (corps z) : la fenêtre ne bascule que corps arrêté (moins de STILL case depuis le passage
-- précédent), à ACT_REACH case au plus et tourné vers elle (LK04-T18). Rend ce constat et la distance du corps au
-- milieu du bord ; met à jour la position de référence.
function Obstacles.closeReady(r, z)
    local x, y = z:getX(), z:getY()
    local still = dist(x, y, r.lx or x, r.ly or y) < Obstacles.STILL
    r.lx, r.ly = x, y
    local d = dist(x, y, r.e.mx, r.e.my)
    return still and d <= Obstacles.ACT_REACH and Obstacles.facing(z, r.e), d
end

-- Fenêtre key refermée par le PNJ id, corps à d case de son milieu (gesture : avec le geste) : constat gardé pour les
-- essais en jeu (Obstacles.lastClose, lk.traversal) et garde contre une réouverture par le même PNJ (closedBy).
local function noteClosed(key, e, id, z, d, gesture, t)
    count("windowsClosed")
    Obstacles.closedBy[key] = { id = id, ms = t }
    Obstacles.lastClose = { key = key, id = id, d = d, gesture = gesture, ms = t,
        facing = z ~= nil and Obstacles.facing(z, e) or false }
    log().info("window %s closed behind npc %s (body %.2f square(s) away%s)", key, id, d,
        gesture and ", gesture" or "")
end

-- Gestes en cours devant une fenêtre (LK04-T13), à chaque passage : bascule à l'instant du clip (toggleMs), geste
-- oublié à sa fin (endMs). Ouverture : fenêtre ouverte avec le corps (openWindow) puis notée pour être refermée, comme
-- sans geste ; fermeture : fenêtre fermée si ses deux cases sont libres, sinon nouvel essai à chaque passage jusqu'à la
-- fin du geste, puis closeWindowsPass reprend (nouveau geste, abandon après GIVE_UP_MS). Geste interrompu (fin
-- anticipée de l'animation) si la fenêtre a disparu, est brisée, barricadée ou déjà dans l'état voulu (quelqu'un
-- d'autre), si le corps n'est plus dans le monde ou, pour une ouverture, si la consigne "move" n'est plus en cours.
function Obstacles.windowActPass(t)
    local keys = {}
    for key in pairs(Obstacles.winActs) do keys[#keys + 1] = key end
    table.sort(keys)   -- ordre déterministe ; table modifiée hors de pairs
    for _, key in ipairs(keys) do
        local r = Obstacles.winActs[key]
        local w = r.win
        local open = r.kind == "open"
        local z = Bodies().find(r.id)
        local why = nil
        if r.done then
            if t >= r.endMs then Obstacles.winActs[key] = nil end
        else
            local ready, d = false, nil
            if not open and z ~= nil then ready, d = Obstacles.closeReady(r, z) end   -- LK04-T18
            if gone(w) then
                why = "window removed"
            elseif w:isDestroyed() or w:isBarricaded() then
                why = "window broken or barricaded"
            elseif (w:IsOpen() == true) == open then
                why = open and "window already open" or "window already closed"
            elseif z == nil or not Bodies().inWorld(z) then
                why = "body gone"
            elseif open and moveState(r.id) ~= "moving" then
                why = "move no longer running"
            elseif t >= r.toggleMs then
                if open then
                    if Obstacles.openWindow(w, z) then
                        r.done = true
                        count("windowsOpened")
                        Obstacles.openWins[key] = { win = w, e = r.e, id = r.id, ms = t, seenMs = t, from = r.from }
                        log().info("npc %s: window %s opened (group %s)", r.id, key, tostring(Obstacles.groupOf(r.id)))
                    else
                        why = "window did not open"
                    end
                else
                    local rec = Obstacles.openWins[key]
                    if rec == nil then
                        why = "window no longer followed"
                    elseif not ready then
                        -- LK04-T18 : corps pas encore arrêté devant elle (relais, exécutant) : attente jusqu'à la fin
                        -- du geste, puis nouvel essai par closeWindowsPass s'il est toujours à ACT_REACH.
                        count("windowCloseWaits")
                        if t >= r.endMs then Obstacles.winActs[key] = nil end
                    elseif occupied(rec, z) then
                        count("windowsBusy")
                        if t >= r.endMs then Obstacles.winActs[key] = nil end   -- nouvel essai par closeWindowsPass
                    elseif Obstacles.setWindow(w, false, z) then
                        r.done = true
                        noteClosed(key, r.e, r.id, z, d, true, t)
                        Obstacles.openWins[key] = nil
                    else
                        log().warn("window %s could not be closed behind npc %s", key, r.id)
                        Obstacles.openWins[key] = nil
                        why = "window did not close"
                    end
                end
            end
            if why ~= nil then
                Obstacles.winActs[key] = nil
                count("windowGesturesStopped")
                local A = LivingKnox.Anim
                if A ~= nil and A.endAct ~= nil then A.endAct(r.id, r.g) end
                log().info("npc %s: %s gesture at the window %s stopped: %s", r.id, r.g, key, why)
            end
        end
    end
end

-- Fenêtres ouvertes ici : refermées quand c'est dû (voir l'en-tête). seen : bords encore sur un trajet.
function Obstacles.closeWindowsPass(seen, t)
    local drop, shut = {}, {}
    for key, rec in pairs(Obstacles.openWins) do
        local w = rec.win
        if gone(w) then
            drop[#drop + 1] = key
        elseif not w:IsOpen() or w:isDestroyed() or w:isBarricaded() then
            drop[#drop + 1] = key   -- fermée, brisée ou barricadée par quelqu'un d'autre : plus à nous
        elseif Obstacles.winActs[key] == nil then   -- geste en cours devant elle : windowActPass (LK04-T13)
            local z = Bodies().find(rec.id)
            -- LK04-T18 : escalade de cette fenêtre en cours, fin guettée à chaque image (Obstacles.landed).
            rec.climbing = (z ~= nil and climbing(z) and math.floor(z:getZ()) == rec.e.z
                and dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) <= Obstacles.DETECT) or nil
            local due = not seen[key] and windowCloseDue(rec, z, t)
            local busy = due and occupied(rec, z)
            if due and not busy then
                if not closeWithGesture(rec, z, t) then shut[#shut + 1] = key end
            else
                if busy then count("windowsBusy") end
                if t - rec.ms >= Obstacles.GIVE_UP_MS then
                    count("windowsGivenUp")
                    log().warn("window %s left open: npc %s not next to it in time or its squares stay occupied",
                        key, rec.id)
                    drop[#drop + 1] = key
                end
            end
        end
    end
    for _, key in ipairs(shut) do   -- table modifiée hors de pairs (corps à ACT_REACH au plus : windowCloseDue)
        local rec = Obstacles.openWins[key]
        local z = Bodies().find(rec.id)
        if Obstacles.setWindow(rec.win, false, z) then
            noteClosed(key, rec.e, rec.id, z, z ~= nil and dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) or -1, false, t)
        else
            log().warn("window %s could not be closed behind npc %s", key, rec.id)
        end
        Obstacles.openWins[key] = nil
    end
    for _, key in ipairs(drop) do Obstacles.openWins[key] = nil end
    local old = {}
    for key, cb in pairs(Obstacles.closedBy) do
        if t - cb.ms >= Obstacles.CLOSE_GUARD_MS then old[#old + 1] = key end
    end
    for _, key in ipairs(old) do Obstacles.closedBy[key] = nil end
end

-- Vrai si le dernier passant d'une fenêtre à refermer vient de finir son escalade (LK04-T18) : passage avancé à
-- l'image suivante, pour arrêter le corps sur la case d'arrivée avant qu'il ne s'éloigne.
function Obstacles.landed()
    for _, rec in pairs(Obstacles.openWins) do
        if rec.climbing then
            local z = Bodies().find(rec.id)
            if z == nil or not climbing(z) then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------- foyers verrouillés

-- Portes extérieures du foyer h ({ gid, def, z }) au niveau du foyer, dans la zone chargée (bords du rectangle du
-- bâtiment compris) : fn(door, e) pour chacune.
local function eachExteriorDoor(h, fn)
    local cell = getCell()
    local def, z = h.def, h.z
    for x = def:getX() - 1, def:getX2() - 1 do
        for y = def:getY() - 1, def:getY2() - 1 do
            local sq = cell:getGridSquare(x, y, z)
            if sq ~= nil then
                for _, kind in ipairs({ "W", "N" }) do
                    local e = edge(x, y, z, kind)
                    local nb = cell:getGridSquare(e.bx, e.by, z)
                    local door = nb and sq:getDoorTo(nb)
                    if door ~= nil then
                        local gid, exterior = Obstacles.homeOf(sq, nb)
                        if gid == h.gid and exterior then fn(door, e) end
                    end
                end
            end
        end
    end
end

-- Verrouille les portes extérieures fermées et non verrouillées du foyer h dans la zone chargée, sauf celles ouvertes
-- ici, chacune seulement si un membre porteur de sa clé est au foyer (LK04-T12, keyHolderAt). Rend le nombre de
-- portes verrouillées.
function Obstacles.secureHome(h)
    local n = 0
    local holders = {}   -- keyId -> membre porteur (false : aucun), relevé une fois par appel
    eachExteriorDoor(h, function(door, e)
        if Obstacles.opened[e.key] == nil and not Obstacles.isOpen(door)
            and Obstacles.kindOf(door) ~= "double" and not Obstacles.isLocked(door) then
            local keyId = Obstacles.doorKeyId(door)
            if holders[keyId] == nil then holders[keyId] = Obstacles.keyHolderAt(h, keyId) or false end
            if holders[keyId] == false then
                count("secureKeyless")
            elseif Obstacles.setDoor(door, false, true) then
                n = n + 1
            end
        end
    end)
    if n > 0 then
        count("secured")
        -- E18-T31 : portes verrouillees par le foyer, comptees aussi dans stats.locked (setDoor).
        Obstacles.stats.securedDoors = (Obstacles.stats.securedDoors or 0) + n
        log().info("group %s: %d exterior door(s) of its home locked", h.gid, n)
    end
    return n
end

-- Raison (anglais, journal) pour laquelle une porte extérieure ouverte du foyer n'est jamais fermée par shutHome, ou
-- nil : barricadée (ToggleDoorSilent la refuse), détruite, double (objets qui changent de case), cadenassée. Porte de
-- garage : tous ses panneaux (LK04-T17).
function Obstacles.shutRefusal(door)
    if anyBarricaded(door) then return "barricaded door" end
    if door:isDestroyed() then return "destroyed door" end
    local kind = Obstacles.kindOf(door)
    if kind == "double" then return "double door not handled" end
    if isThumpable(door) and door:isLockedByPadlock() then return "padlocked door" end
    return nil
end

-- Arrivée a ({ ms, due, doors, done }) près du foyer h : ferme et verrouille ses portes extérieures ouvertes (liste
-- figée au premier essai), sauf celles occupées, sur un trajet (seen) ou obstruées, réessayées plus tard (voir
-- l'en-tête). Rend le nombre de portes fermées.
function Obstacles.shutHome(h, a, seen, t)
    seen = seen or {}
    t = t or now()
    if a.doors == nil then
        a.doors = {}
        eachExteriorDoor(h, function(door, e)
            if Obstacles.isOpen(door) and Obstacles.opened[e.key] == nil then
                local why = Obstacles.shutRefusal(door)
                if why == nil then
                    a.doors[e.key] = { door = door, e = e }
                else
                    count("shutRefused")
                    log().info("group %s: exterior door %s of its home left open: %s", h.gid, e.key, why)
                end
            end
        end)
    end
    local keys = {}
    for key in pairs(a.doors) do keys[#keys + 1] = key end
    table.sort(keys)   -- ordre déterministe ; table modifiée hors de pairs
    local shut, busy, unlocked = 0, 0, 0
    for _, key in ipairs(keys) do
        local c = a.doors[key]
        local door = c.door
        if gone(door) or not Obstacles.isOpen(door)
            or Obstacles.opened[key] ~= nil or Obstacles.shutRefusal(door) ~= nil then
            a.doors[key] = nil   -- retirée, fermée ou barricadée par quelqu'un, ou suivie par la refermeture
        elseif seen[key] or occupied(c) or door:isObstructed() then
            busy = busy + 1
        else
            -- LK04-T12 : fermer ne demande aucune clé ; verrouiller, un membre porteur de la clé au foyer (sinon
            -- securePass la verrouille plus tard, quand un porteur est là).
            local lock = Obstacles.keyHolderAt(h, Obstacles.doorKeyId(door)) ~= nil
            Obstacles.setDoor(door, false, lock)
            a.doors[key] = nil
            shut = shut + 1
            if not lock then unlocked = unlocked + 1 end
        end
    end
    local st = Obstacles.stats
    local cause = a.why and (" (" .. a.why .. ")") or ""   -- alerte (LK05-T08), sinon arrivée
    if shut > 0 then
        st.shut = (st.shut or 0) + shut
        st.shutUnlocked = (st.shutUnlocked or 0) + unlocked
        if unlocked == 0 then
            log().info("group %s: %d open exterior door(s) of its home closed and locked%s", h.gid, shut, cause)
        else
            log().info("group %s: %d open exterior door(s) of its home closed, %d left unlocked: no member with "
                .. "the key at home%s", h.gid, shut, unlocked, cause)
        end
    end
    if busy == 0 then
        a.done = true
    elseif t - a.ms >= Obstacles.SHUT_GIVE_UP_MS then
        a.done = true
        count("shutGivenUp")
        log().warn("group %s: %d exterior door(s) of its home left open: squares occupied or on a path%s", h.gid, busy,
            cause)
    else
        count("shutBusy")
        a.due = t + Obstacles.SHUT_RETRY_MS
    end
    return shut
end

-- À chaque passage : arrivées près des foyers (case du foyer chargée après ne pas l'avoir été) et fermeture de leurs
-- portes extérieures ouvertes quand elle est due. Foyer déchargé, supprimé ou déplacé : arrivée oubliée.
function Obstacles.shutPass(seen, t)
    local A = Obstacles.arrivals
    local live = {}
    local cell = getCell()
    for _, h in ipairs(Obstacles.refreshHomes(false).list) do
        local key = h.gid .. "|" .. h.id
        if cell:getGridSquare(h.x, h.y, h.z) ~= nil then
            live[key] = true
            local a = A[key]
            if a == nil then
                a = { ms = t, due = t + Obstacles.SHUT_DELAY_MS }
                A[key] = a
            end
            if not a.done and t >= a.due then Obstacles.shutHome(h, a, seen, t) end
        end
    end
    local stale = {}
    for key in pairs(A) do
        if not live[key] then stale[#stale + 1] = key end
    end
    for _, key in ipairs(stale) do A[key] = nil end   -- table modifiée hors de pairs
    Obstacles.alertShutPass(seen, t)
end

-- ---------------------------------------------------------------- alerte (complément de LK05-T08)
-- Fiche : deplacement.md, section « Portes refermées à l'alerte » ; alerte.md, « Portes refermées ». Écouteur "doors"
-- de LivingKnox.Alert (Alert.subscribe) : à une alerte déclenchée ou aggravée (raised, escalated) du groupe gid, les
-- portes extérieures OUVERTES de son foyer (bâtiment, niveau du foyer, zone chargée) sont fermées, et verrouillées si
-- un membre porteur de la clé est au foyer (LK04-T10, LK04-T12) : même code que la fermeture à l'arrivée (shutHome :
-- liste figée au premier essai, hors portes ouvertes ici pour un PNJ en route, refermées derrière lui ; cases libres,
-- pas sur le trajet d'un PNJ à ce passage, porte non obstruée ; nouvel essai toutes les SHUT_RETRY_MS, abandon (WARN)
-- après SHUT_GIVE_UP_MS ; jamais barricadée, détruite, double ni cadenassée). L'écouteur ne touche aucune
-- porte : il note la demande, traitée au passage suivant (où les trajets des PNJ sont connus). Une demande par foyer
-- en cours au plus ; une porte rouverte ensuite reste ouverte jusqu'à l'alerte suivante (pas de bataille avec un
-- joueur). Foyer hors bâtiment, déchargé ou changé : rien.

-- Écouteur "raised" : note la fermeture des portes du foyer du groupe gid. Rend le nombre de foyers notés.
function Obstacles.onAlert(gid, info, event)
    if not LivingKnox.isAuthority() then return 0 end
    local t = now()
    local n = 0
    local label = "alert " .. tostring(type(info) == "table" and info.id or "?") .. " " .. tostring(event or "raised")
    for _, h in ipairs(Obstacles.refreshHomes(true).list) do
        if h.gid == gid then
            local key = h.gid .. "|" .. h.id
            local a = Obstacles.alertShuts[key]
            if a == nil or a.done then
                Obstacles.alertShuts[key] = { ms = t, due = t, why = label }
                n = n + 1
            end
        end
    end
    if n > 0 then
        count("alertShuts")
        log().info("group %s: %s: open exterior doors of its home to be closed", tostring(gid), label)
    end
    return n
end

-- À chaque passage (depuis shutPass) : demandes de l'alerte traitées par shutHome. seen : bords sur un trajet.
function Obstacles.alertShutPass(seen, t)
    local AS = Obstacles.alertShuts
    local homes = {}
    for _, h in ipairs(Obstacles.refreshHomes(false).list) do homes[h.gid .. "|" .. h.id] = h end
    local keys = {}
    for key in pairs(AS) do keys[#keys + 1] = key end
    table.sort(keys)   -- ordre déterministe ; table modifiée hors de pairs
    local cell = getCell()
    for _, key in ipairs(keys) do
        local a, h = AS[key], homes[key]
        if h == nil or cell:getGridSquare(h.x, h.y, h.z) == nil then
            AS[key] = nil   -- foyer changé, supprimé ou déchargé
        elseif not a.done and t >= a.due then
            Obstacles.shutHome(h, a, seen, t)
        end
        if AS[key] ~= nil and AS[key].done then AS[key] = nil end
    end
end

-- Abonnement de l'écouteur "doors" à LivingKnox.Alert (chargé avant ou après ce fichier : appelé au chargement et à
-- chaque passage ; un même nom remplace l'écouteur). Rend vrai si l'alerte est branchée.
function Obstacles.hookAlert()
    local A = LivingKnox.Alert
    if A == nil or A.subscribe == nil then return false end
    if Obstacles.state.alertHook == A then return true end
    local function raised(gid, info, event) return LivingKnox.Obstacles.onAlert(gid, info, event) end
    A.subscribe("doors", { raised = raised })
    Obstacles.state.alertHook = A
    return true
end

-- Toutes les SECURE_EVERY_MS : foyers dont la case est chargée. La fermeture à l'arrivée (shutPass) a lieu à chaque
-- passage.
function Obstacles.securePass(t, seen)
    Obstacles.shutPass(seen or {}, t)
    local st = Obstacles.state
    if st.secured ~= nil and t - st.secured < Obstacles.SECURE_EVERY_MS then return 0 end
    st.secured = t
    local n = 0
    for _, h in ipairs(Obstacles.refreshHomes(false).list) do
        if getCell():getGridSquare(h.x, h.y, h.z) ~= nil then n = n + Obstacles.secureHome(h) end
    end
    return n
end

-- ---------------------------------------------------------------- passage

function Obstacles.pass()
    if not LivingKnox.isAuthority() or getCell() == nil then return end
    local B, D = Bodies(), Dir()
    if B == nil or D == nil or not B.canAct(false) then return end
    local t = now()
    local seen = {}
    local ids = {}
    for id in pairs(D.entries) do ids[#ids + 1] = id end
    table.sort(ids)   -- ordre déterministe ; consignes modifiées (abort) hors de pairs
    for _, id in ipairs(ids) do
        local e = D.entries[id]
        if e ~= nil and e.op == D.OP_MOVE and not e.done and e.suspended == nil then
            local z = B.find(id)
            if z ~= nil then Obstacles.check(id, e, z, seen, t) end
        else
            Obstacles.track[id] = nil
        end
    end
    Obstacles.blockedPass(t)   -- LK04-T04 : attentes et forçages devant un passage bloqué
    Obstacles.windowActPass(t)
    Obstacles.closePass(seen, t)
    Obstacles.closeWindowsPass(seen, t)
    Obstacles.keyPass(t)
    Obstacles.hookAlert()   -- LK05-T08 : portes refermées à l'alerte (sans effet une fois branché)
    Obstacles.securePass(t, seen)
    Obstacles.stats.passes = Obstacles.stats.passes + 1
end

function Obstacles.tick()
    local st = Obstacles.state
    st.ticks = st.ticks + 1
    if st.ticks < Obstacles.PASS_EVERY and not Obstacles.landed() then return end
    if st.ticks < Obstacles.PASS_EVERY then count("landings") end
    st.ticks = 0
    Obstacles.pass()
end

if LivingKnox.isAuthority() then
    local function onTick()
        LivingKnox.Obstacles.tick()
    end
    LivingKnox.subscribe("OnTick", "Obstacles.tick", onTick)
    Obstacles.hookAlert()
end

return Obstacles
