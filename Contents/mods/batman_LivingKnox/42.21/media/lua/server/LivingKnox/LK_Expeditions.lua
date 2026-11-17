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
-- 5. Genres d'expédition (LK16-T08) : inscrits par Expeditions.registerKind, un fichier par genre (dossier
--    Expeditions/) ; le moteur ne connaît aucun genre. Au départ, les genres sont essayés par priorité (order) : un
--    genre permis à cette heure (hours), qui répond aux manques (wanted) et trouve un lieu (pickTarget) part ; le genre
--    de repli (fallback : le bâtiment ci-dessus) passe en dernier et fixe les heures de jour. Le genre mène la fouille
--    (round : fouille des conteneurs Ex.searchRound, ou tirages sur place Ex.drawnRound) et le retour hors écran
--    (offscreen : Ex.searchOffscreen ou Ex.drawnOffscreen). Genres de la nourriture (LK05-T11, inscrits par LK_Food :
--    fiche docs/annexes/conception/nourriture.md) : cueillette (« forage », zone de cueillette vanilla, de jour) et
--    pêche (« fish », rive libre, à l'aube et au crépuscule), à tirages k sur r (flux reproductible de LivingKnox.Food,
--    même résultat à l'écran et hors écran), objets notés à créer (a, f) et créés au dépôt par le genre (make).
-- Persistance (registre des groupes, schéma 1 inchangé, champ facultatif contrôlé ici, oublié s'il est malformé) :
--   trips = { v = FORMAT, n = expéditions parties, last = minute de jeu de la dernière fin, seen = { bâtiments },
--             cur = { n, phase, team = { mid }, want = { { c, m } }, target = { x, y, z, b, room, label, zone },
--                     start, due (minute limite de la phase), cap, carry = { { t, c, i, a, f } }, searched = { clé },
--                     from (phase quittée hors écran), kind (identifiant d'un genre inscrit, absent pour le genre de
--                     repli), k et r (tirages faits et prévus d'un genre à tirages) } ou absent }.
-- Mémoire (places, réservations, objets portés) : non sauvegardée.
-- Fichiers (LK20-T08, un par section, chargés par les require ci-dessous ; chacun requiert d'abord le socle) :
--   Expeditions/LK_Expeditions_Common.lua    socle : table, phases, ROOMS, ABSTRACT_ITEMS, CFG, état, table Ex._
--   Expeditions/LK_Expeditions_Kinds.lua     registre des genres (registerKind, kindOf)
--   Expeditions/LK_Expeditions_Record.lua    forme de l'historique (validCur, validTrips, memberTrip)
--   Expeditions/LK_Expeditions_Target.lua    choix du lieu (buildingsNear, rank, pickTarget)
--   Expeditions/LK_Expeditions_Depart.lua    départ (needBlocker, teamOf, departBlocker, wantOf, tryDepart)
--   Expeditions/LK_Expeditions_Phases.lua    phases, conteneurs du lieu, fouille (siteContainers, searchContainer)
--   Expeditions/LK_Expeditions_Run.lua       comportement « expedition » (searchRound, drawnRound, apply)
--   Expeditions/LK_Expeditions_Deliver.lua   dépôt au foyer (deliver)
--   Expeditions/LK_Expeditions_Offscreen.lua hors écran (onReleased, searchOffscreen, resolveAbstract)
--   Expeditions/LK_Expeditions_Minute.lua    passage par minute, lectures, abandon (minutePass, get, cancel)
-- Ce fichier garde les événements, les écouteurs, le contexte, l'extension, la priorité de passage et
-- Expeditions.reset. Les genres (Expeditions/LK_Exp_*.lua) requièrent ce fichier et s'inscrivent ensuite.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Passage"   -- LK18-T01 : priorité de passage déclarée plus bas
require "LivingKnox/Expeditions/LK_Expeditions_Common"
require "LivingKnox/Expeditions/LK_Expeditions_Kinds"
require "LivingKnox/Expeditions/LK_Expeditions_Record"
require "LivingKnox/Expeditions/LK_Expeditions_Target"
require "LivingKnox/Expeditions/LK_Expeditions_Depart"
require "LivingKnox/Expeditions/LK_Expeditions_Phases"
require "LivingKnox/Expeditions/LK_Expeditions_Run"
require "LivingKnox/Expeditions/LK_Expeditions_Deliver"
require "LivingKnox/Expeditions/LK_Expeditions_Offscreen"
require "LivingKnox/Expeditions/LK_Expeditions_Minute"

local Ex = LivingKnox.Expeditions

function Ex.reset()
    Ex.state = { npcs = {}, claims = {}, sites = {}, carried = {}, checked = {} }
end

local function onEveryOneMinute()
    Ex.minutePass()
end

LivingKnox.subscribe("EveryOneMinute", "Expeditions.minutePass", onEveryOneMinute)

-- LK16-T04 : membre rendu à la simulation abstraite (LK_Materialize, "memberReleased") : équipe d'une expédition
-- physique ou bascule hors écran (LK05-T05).
LivingKnox.listen("memberReleased", "Expeditions.onReleased", function(info)
    local E = LivingKnox.Expeditions
    if E ~= nil and E.onReleased ~= nil then E.onReleased(info.group, info.member) end
end, 10)

-- LK16-T04 : retour publié par LK_Simulation ("expeditionReturn", premier écouteur) : expédition physique passée hors
-- écran (LK05-T05, aucune perte).
LivingKnox.listen("expeditionReturn", "Expeditions.resolveAbstract", function(info)
    if info.handled or info.expedition.trip == nil then return end
    info.handled = true
    LivingKnox.Expeditions.resolveAbstract(info.g, info.gid, info.hour, info.erand, info.day)
end, 10)

-- LK16-T05 : champ de contexte de la cascade (LivingKnox.Decisions.registerContext, ordre 20) : expédition en cours
-- qui compte ce membre (LK05-T05, règle duty -> comportement « expedition »).
LivingKnox.Decisions.registerContext({ id = "expedition", order = 20, fill = function(ctx, src)
    ctx.trip = Ex.memberTrip(src.gid, src.mid)
end })

-- LK16-T06 : comportement « expedition » de la cascade mené par ce module (extension propriétaire, LK_Decisions.lua) :
-- trajet, fouille et retour.
LivingKnox.Decisions.registerExtension({ id = "expedition", order = 50,
    apply = function(id, st, ctx, fresh) return Ex.apply(id, st, ctx, fresh) end })

-- LK18-T01 (ADR adr-ceder-le-passage.md D02, fiche passage.md) : priorité de passage du comportement, déclarée ici.
LivingKnox.Passage.priority("expedition", 60)

return Ex
