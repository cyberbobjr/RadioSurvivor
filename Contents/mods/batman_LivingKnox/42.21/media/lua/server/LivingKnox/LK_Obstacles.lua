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
-- Refermeture (LK04-T07, LK04-T18, LK19-T01) : une fenêtre ouverte ici est notée avec son passant, le PNJ qui l'a
-- ouverte ; un autre PNJ n'en devient le passant qu'en l'escaladant (climbedWindows, ADR adr-fenetres-chacun-referme.md),
-- jamais parce qu'elle est sur son trajet ; tant qu'un PNJ dont elle rapproche l'étape est à DETECT cases, elle n'est
-- pas refermée (il arrive). Refermée (ToggleWindow, seulement si elle est encore ouverte) par son passant, comme un
-- joueur, JUSTE APRÈS son enjambée : corps dans le monde, au niveau de la fenêtre, hors escalade,
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
-- Fichiers (LK20-T09, un par section, chargés par les require ci-dessous ; chacun requiert d'abord le socle) :
--   Obstacles/LK_Obstacles_Common.lua   socle : table, réglages, état, compteurs, table Obstacles._ (now, dist, count)
--   Obstacles/LK_Obstacles_Doors.lua    bords, état d'une porte, bâtiments des foyers, décision et effet (decide, setDoor)
--   Obstacles/LK_Obstacles_Keys.lua     clés des foyers (homeKeyOf, giveKey, keyPass, keyHolderAt)
--   Obstacles/LK_Obstacles_Windows.lua  fenêtres (decideWindow, setWindow, gestes, checkWindows, noteWindows,
--                                       climbedWindows)
--   Obstacles/LK_Obstacles_Glass.lua    verre brisé : retiré avant l'enjambée, ou risque du vanilla pour un PNJ pressé
--                                       (inHurry, checkGlass, glassActPass, climbedGlass ; LK21-T12)
--   Obstacles/LK_Obstacles_Check.lua    détection des portes, immobilité, refus, contrôle d'un PNJ (doorsNear, check)
--   Obstacles/LK_Obstacles_Blocked.lua  passage bloqué : attendre ou forcer (blockedPolicy, onBlocked, blockedPass)
--   Obstacles/LK_Obstacles_Closing.lua  refermeture des portes et des fenêtres (closePass, windowActPass, landed)
--   Obstacles/LK_Obstacles_Secure.lua   foyers verrouillés, fermeture à l'arrivée et à l'alerte (secureHome, shutPass,
--                                       onAlert, hookAlert, securePass)
-- Ce fichier garde le passage, l'image et l'abonnement à OnTick.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Directives"
require "LivingKnox/LK_Groups"
require "LivingKnox/Edges/LK_Edges"
require "LivingKnox/Obstacles/LK_Obstacles_Common"
require "LivingKnox/Obstacles/LK_Obstacles_Doors"
require "LivingKnox/Obstacles/LK_Obstacles_Keys"
require "LivingKnox/Obstacles/LK_Obstacles_Windows"
require "LivingKnox/Obstacles/LK_Obstacles_Glass"
require "LivingKnox/Obstacles/LK_Obstacles_Check"
require "LivingKnox/Obstacles/LK_Obstacles_Blocked"
require "LivingKnox/Obstacles/LK_Obstacles_Closing"
require "LivingKnox/Obstacles/LK_Obstacles_Secure"

local Obstacles = LivingKnox.Obstacles
local P = Obstacles._   -- fonctions privées partagées entre les fichiers d'Obstacles/ (LK_Obstacles_Common.lua)

-- ---------------------------------------------------------------- passage

function Obstacles.pass()
    if not LivingKnox.isAuthority() or getCell() == nil then return end
    local B, D = LivingKnox.Bodies, LivingKnox.Directives
    if B == nil or D == nil or not B.canAct(false) then return end
    local t = P.now()
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
    Obstacles.glassActPass(t)   -- LK21-T12 : verre retiré à la fin du geste
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
    if st.ticks < Obstacles.PASS_EVERY then P.count("landings") end
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
