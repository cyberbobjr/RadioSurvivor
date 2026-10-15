-- Living Knox : portes sur le trajet des corps de PNJ (LK04-T02). Fiche : docs/conception/deplacement.md, section
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
-- Porte refusée : rien n'est touché ; si le corps reste à REACH case, immobile depuis REFUSE_MS, la consigne est close
-- en échec par l'autorité (Directives.abort, raison journalisée, dernier refus dans Obstacles.lastRefused) et
-- l'exécutant arrête le corps. Jamais de refus pendant une escalade, ni devant une porte BASSE (portail de clôture,
-- isHoppable et non TallHoppable) : le corps l'enjambe, verrouillée ou non (IsoZombie.java:3051-3058, 1075) (LK04-T08 ;
-- l'ouvrir plutôt que l'enjamber relève de LK04-T09).
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
    windowsClosed = 0, windowsBusy = 0, windowsGivenUp = 0, routes = 0, routedByDoor = 0, routeNodes = 0,
    routeMs = 0, routeMaxMs = 0 }

local function log() return LivingKnox.Log end
local function Dir() return LivingKnox.Directives end
local function Bodies() return LivingKnox.Bodies end

local function now() return getTimestampMs() end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

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

-- Fenêtre du bord commun de deux cases voisines : IsoWindow ("window"), fenêtre construite IsoThumpable ("built") ou
-- cadre vide IsoWindowFrame ("frame"), quelle que soit la case qui la porte (IsoGridSquare.java:3131-3172,
-- 3228-3236) ; nil sinon. Une IsoWindow posée dans un cadre est rendue en premier.
function Obstacles.windowOf(sq, nb)
    local w = sq:getWindowTo(nb)
    if w ~= nil then return w, "window" end
    w = sq:getWindowThumpableTo(nb)
    if w ~= nil then return w, "built" end
    w = sq:getWindowFrameTo(nb)
    if w ~= nil then return w, "frame" end
    return nil
end

-- Vrai si un bord d'une case du carré 3 x 3 centré sur (x, y, z) porte une fenêtre (windowOf) ou une clôture basse
-- (isFenceTo) : un corps à une case de ce point peut être devant elle.
function Obstacles.crossingNear(x, y, z)
    local cell = getCell()
    for ax = x - 1, x + 1 do
        for ay = y - 1, y + 1 do
            local sq = cell:getGridSquare(ax, ay, z)
            if sq ~= nil then
                for _, nb in ipairs({ cell:getGridSquare(ax + 1, ay, z), cell:getGridSquare(ax, ay + 1, z),
                    cell:getGridSquare(ax - 1, ay, z), cell:getGridSquare(ax, ay - 1, z) }) do
                    if nb ~= nil and (Obstacles.windowOf(sq, nb) ~= nil or Obstacles.isFenceTo(sq, nb)) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Vrai si la fenêtre arrête un corps : barricadée, ou IsoWindow fermée et intacte. Fenêtre ouverte, cassée ou
-- détruite, cadre vide et fenêtre construite non barricadés : franchis par le moteur (IsoWindow.java:1220-1238,
-- IsoWindowFrame.java:348-372, IsoThumpable.java:2175-2186).
function Obstacles.windowBlocks(w, kind)
    if w:isBarricaded() then return true end
    return kind == "window" and not w:IsOpen() and not w:isDestroyed()
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
                    if nb ~= nil then w, wk = Obstacles.windowOf(sq, nb) end
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
local function stillFor(id, z, t)
    local tr = Obstacles.track[id]
    if tr == nil or dist(tr.x, tr.y, z:getX(), z:getY()) >= Obstacles.STILL then
        Obstacles.track[id] = { x = z:getX(), y = z:getY(), ms = t }
        return 0
    end
    return t - tr.ms
end

-- Vrai si le corps z est en train d'escalader (fenêtre ou clôture : nom de l'état d'action, en minuscules).
local function climbing(z)
    local st = z ~= nil and z:getActionStateName() or nil
    return st == "climbwindow" or st == "climbfence"
end

-- Refus d'une consigne bloquée par une porte (what = "door") ou une fenêtre ("window") : close en échec par
-- l'autorité.
local function refuse(id, e, c, why, what)
    what = what or "door"
    count("refused")
    Obstacles.lastRefused = { id = id, what = what, key = c.e.key, why = why, ms = now() }
    log().warn("npc %s: move #%d refused at the %s %s: %s", id, e.v, what, c.e.key, why)
    Dir().abort(id, what .. " " .. c.e.key .. ": " .. why)
end

-- Fenêtre contre laquelle le corps z du PNJ id (consigne e) est arrêté depuis still ms : ouverture (notée pour être
-- refermée) ou refus (voir l'en-tête). Une seule fenêtre par passage. Rend vrai si une fenêtre a été traitée.
function Obstacles.checkWindows(id, e, z, still, t)
    if still < Obstacles.STUCK_MS then return false end
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
    return door:isHoppable() == true and door:isTallHoppable() ~= true
end

-- Portes du PNJ id (consigne e, corps z) : ouverture ou refus. seen : clés des bords sur un trajet à ce passage.
-- Jamais de refus pendant une escalade, ni devant une porte basse (enjambée par le moteur).
-- Une porte qui rapproche de l'étape SUIVANTE compte aussi (LK04-T09) : le point de passage « case avant la porte »
-- est atteint à ARRIVE case près, souvent à moins d'une case de la porte ; elle est ainsi ouverte avant (en course,
-- moins d'une demi-seconde sépare l'arrivée sur ce point du contact).
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
    for _, c in ipairs(Obstacles.doorsNear(px, py, pz)) do
        local contact = still >= Obstacles.STUCK_MS and c.d <= Obstacles.REACH
        local route = Obstacles.onRoute(c.e, px, py, tx, ty) or (nx ~= nil and Obstacles.onRoute(c.e, px, py, nx, ny))
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
-- au contact d'une porte ou d'une fenêtre refusée (REFUSE_MS) : aucun détour n'a été trouvé à l'émission du "move"
-- (porte d'abord, détour LK04-T14 : contourner reste la première réponse, pour tous). Comportement selon l'hostilité du
-- type de groupe du PNJ (blockedPolicy) :
--   - "detour" (colons, PNJ sans groupe) : refus aussitôt, comme avant (consigne close en échec ; le cadre de décision
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
    if h >= Obstacles.FORCE_HOSTILITY then return "force" end
    if h >= Obstacles.WAIT_HOSTILITY then return "wait" end
    return "detour"
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
    if what == "window" then
        if not c.win:isBarricaded() then return nil, tostring(why) .. ": only a barricade is forced" end
    else
        local d = c.door
        if isThumpable(d) then return nil, "built door never forced" end
        local kind = Obstacles.kindOf(d)
        if kind ~= "single" then return nil, kind .. " door not forced" end
        if d:isObstructed() then return nil, "obstructed door" end
        local home = Obstacles.homeOf(c.sqA, c.sqB)
        local other = home ~= nil and home ~= Obstacles.groupOf(npcId)
        if not (d:isBarricaded() or Obstacles.isLocked(d) or other) then return nil, tostring(why) end
    end
    local home = Obstacles.homeOf(c.sqA, c.sqB)
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

-- Passage du bord r (cases sqA ouest ou nord, sqB) pour le modèle mode :
--   "zombie" : chemin vanilla d'un corps (portes, fenêtres et clôtures basses traversées sans surcoût, portail fermé
--     enjambé ; fiche deplacement.md, section 2) ; une porte que le PNJ ne passera pas (doorRefusal) est franchie
--     comme les autres mais marquée "refused" (LK04-T14) ;
--   "zombie-door" : même modèle, mais chaque escalade coûte ROUTE_PENALTY et chaque porte refusée a le léger bonus
--     ROUTE_ZOMBIE_CLIMB_BONUS : chemin vanilla qui préférerait une porte refusée à une clôture ou une fenêtre
--     (LK04-T14, voir planDoorRoute) ;
--   "npc" : porte d'abord (fenêtre, clôture à ROUTE_PENALTY, porte refusée infranchissable) ;
--   "detour" : règle porte d'abord coupée (DOORS_FIRST faux) : fenêtres et clôtures sans surcoût, mais portes et
--     fenêtres refusées infranchissables (LK04-T14) ;
--   "exit" : comme "npc", mais une escalade dont une case est dans un bâtiment de exitKeys (identifiants
--     getIDString -> vrai) coûte ROUTE_EXIT_PENALTY (LK04-T15) ;
--   "exit-loose" : comme "exit", mais une porte ou une fenêtre que le PNJ ne passera pas (refusée, barricadée) coûte
--     ROUTE_LOOSE_PENALTY au lieu d'être infranchissable, marquée "refused" : destination hors d'atteinte par les
--     règles (pièce derrière une porte verrouillée sans clé), sortie du bâtiment de départ par une porte quand même
--     (LK04-T16) ;
--   "trapped" : dernier recours d'un PNJ enfermé (LK04-T20 : aucune porte utilisable pour sortir) : comme "npc", mais
--     avec les décisions trapped de decide et decideWindow (porte ou fenêtre du foyer d'un autre groupe abordée depuis
--     ce foyer, fenêtre verrouillée abordée de l'intérieur) ; barricade, chute, meuble à l'arrivée, fenêtre inamovible
--     et alarme restent infranchissables. Chaque escalade coûte ROUTE_PENALTY.
-- Rend le surcoût en cases (nil : infranchissable) et le franchissement : "door" (porte ou portail passé debout),
-- "climb" (fenêtre, clôture basse, portail enjambé), "refused" (modèles zombie et "exit-loose") ou nil.
-- from : case d'où le bord est abordé (sqA ou sqB), pour l'ouverture de l'intérieur d'une porte verrouillée (LK04-T17).
local function edgeCost(r, mode, npcId, sqA, sqB, exitKeys, from)
    local k = r.kind
    if k == "plain" then return 0 end
    if k == "wall" then return nil end
    if mode == "exit-loose" then
        local c, what = edgeCost(r, "exit", npcId, sqA, sqB, exitKeys, from)
        if c == nil then return Obstacles.ROUTE_LOOSE_PENALTY, "refused" end
        return c, what
    end
    if mode == "zombie" or mode == "zombie-door" then
        if k == "door" and (Obstacles.isOpen(r.obj) or not Obstacles.isLowGate(r.obj)) then
            if doorRefusal(npcId, r.obj, sqA, sqB, from) ~= nil then
                return mode == "zombie" and 0 or Obstacles.ROUTE_ZOMBIE_CLIMB_BONUS, "refused"
            end
            return 0, "door"
        end
        if mode == "zombie-door" then return Obstacles.ROUTE_PENALTY, "climb" end
        -- Léger bonus (essai solo du 2026-10-11) : à longueur égale ou presque, le chemin vanilla peut passer par une
        -- fenêtre que l'A* aurait départagée autrement ; le modèle "zombie" choisit donc l'escalade dans le doute, pour
        -- que la vérification des tronçons soit prudente.
        return Obstacles.ROUTE_ZOMBIE_CLIMB_BONUS, "climb"
    end
    if mode == "trapped" then
        local P = Obstacles.ROUTE_PENALTY
        if k == "door" then
            local d = r.obj
            if d:isBarricaded() then return nil end
            if Obstacles.isOpen(d) or Obstacles.decide(npcId, d, sqA, sqB, nil, from, true) == "open" then
                return 0, "door"
            end
            if Obstacles.isLowGate(d) then return P, "climb" end
            return nil
        elseif k == "window" then
            local w = r.obj
            if w:isBarricaded() then return nil end
            local far = from == sqA and sqB or sqA
            -- Fenêtre ouverte ou cassée : franchie par le moteur, mais jamais vers une chute ou un meuble bas.
            if not Obstacles.windowBlocks(w, r.wk) then
                if Obstacles.isDrop(far) or Obstacles.isFurnitureLanding(far) then return nil end
                return P, "climb"
            end
            if Obstacles.decideWindow(npcId, w, r.wk, sqA, sqB, far, true, from) == "open" then return P, "climb" end
            return nil
        end
        return P, "climb"   -- clôture basse
    end
    local P = mode == "detour" and 0 or Obstacles.ROUTE_PENALTY
    if mode == "exit" and exitKeys ~= nil then
        local ia, ib = buildingOf(sqA), buildingOf(sqB)
        if (ia ~= nil and exitKeys[ia]) or (ib ~= nil and exitKeys[ib]) then P = Obstacles.ROUTE_EXIT_PENALTY end
    end
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
function Obstacles.findRoute(npcId, x0, y0, tx, ty, z, mode, shared)
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
    local maxNodes = (mode == "exit" or mode == "exit-loose" or mode == "trapped") and Obstacles.ROUTE_EXIT_MAX_NODES
        or Obstacles.ROUTE_MAX_NODES
    local exitKeys = shared.exitKeys
    local H = maxy - miny + 1
    local function idx(x, y) return (x - minx) * H + (y - miny) + 1 end
    shared.sqs, shared.walk, shared.elems = shared.sqs or {}, shared.walk or {}, shared.elems or {}
    local sqs, walk, elems, edges = shared.sqs, shared.walk, shared.elems, {}
    local zombieModel = mode == "zombie" or mode == "zombie-door"
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
    -- pour le seul modèle "zombie", voir squareKind).
    local function walkable(x, y)
        local i = idx(x, y)
        local v = walk[i]
        if v == nil then
            v = squareKind(square(x, y))
            walk[i] = v
        end
        if v == 3 and mode ~= "zombie" and mode ~= "zombie-door" then return 0 end
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
                if what == "climb" and el.kind == "window" and zombieModel then win = true end
            end
            if cost ~= nil then c = { cost, what, win } else c = false end
            edges[dkey] = c
        end
        if c == false then return nil end
        -- Fenêtre vers un meuble bas (modèles zombie, selon le sens) : le chemin natif la prend, mais l'escalade finit
        -- au sol (isFurnitureLanding) : franchissement refusé, comme une porte refusée (détour LK04-T14).
        if c[3] and Obstacles.isFurnitureLanding(square(x + dx, y + dy)) then
            shared.sawRefused = true
            return mode == "zombie" and 0 or Obstacles.ROUTE_ZOMBIE_CLIMB_BONUS, "refused"
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
    if info.climbs == 0 and not risk then return done({}, "no window, low fence or closed gate on the way") end
    local mode = Obstacles.DOORS_FIRST and "npc" or "detour"
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
    if not risk and not exitUsed and not trapped and (doors == 0 or climbs >= info.climbs) then
        return done({}, "no usable door or gate within " .. Obstacles.ROUTE_PENALTY .. " squares of detour")
    end
    local guided = exitUsed or trapped   -- points de passage gardés près du départ et de la destination
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

-- Vrai si la porte notée rec peut être refermée maintenant (voir l'en-tête).
local function closeDue(rec, t)
    local z = Bodies().find(rec.id)
    if z == nil then return true end
    local away = dist(z:getX(), z:getY(), rec.e.mx, rec.e.my) >= Obstacles.CLOSE_DIST
    if not away then return false end
    local passed = sideOf(rec.e, z:getX(), z:getY()) ~= rec.from
    local d = Dir().entries[rec.id]
    local going = d ~= nil and d.op == Dir().OP_MOVE and not d.done
    return passed or not going or t - rec.seenMs >= Obstacles.CLOSE_AFTER_MS
end

-- Portes ouvertes ici : refermées (et reverrouillées) quand c'est dû. seen : bords encore sur un trajet.
function Obstacles.closePass(seen, t)
    local drop, shut = {}, {}
    for key, rec in pairs(Obstacles.opened) do
        local door = rec.door
        if door:getSquare() == nil or door:getObjectIndex() == -1 then
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
    local passed = sideOf(rec.e, z:getX(), z:getY()) ~= rec.from
    local d = Dir().entries[rec.id]
    local going = d ~= nil and d.op == Dir().OP_MOVE and not d.done
    return passed or not going or t - rec.seenMs >= Obstacles.CLOSE_AFTER_MS
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
            if w:getSquare() == nil or w:getObjectIndex() == -1 then
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
        if w:getSquare() == nil or w:getObjectIndex() == -1 then
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
        if door:getSquare() == nil or door:getObjectIndex() == -1 or not Obstacles.isOpen(door)
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
