-- Living Knox : plan de fortification du foyer d'un groupe (LK14-T02). Fiches : docs/annexes/conception/fortification.md
-- (règles vanilla 42.21, LK14-T01 ; section « Plan de fortification » pour ce module). Java 42.21.0 cité en abrégé
-- (J = zombie/...) ; M = media/scripts/generated vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Ce module ne pose rien : il lit le monde chargé et dresse la liste des chantiers du foyer, par priorité, avec les
-- matériaux vanilla qui restent à fournir et la durée ; LK14-T03 (barricades), LK14-T04 (murs, palissade) et LK14-T05
-- (rattrapage hors écran) feront le travail.
--   1. Rez-de-chaussée (niveau 0, tier "ground") : portes et fenêtres extérieures du bâtiment du foyer (objets
--      BarricadeAble dont un côté est dans le bâtiment et l'autre dehors : IsoDoor simple, IsoWindow, IsoWindowFrame
--      sans fenêtre, IsoThumpable barricadable ; isBarricadeAllowed écarte portes doubles et de garage,
--      J/iso/objects/IsoDoor.java:1699-1701), jusqu'à PLANKS.ground planches. Cadres vides d'abord (trou ouvert), puis
--      fenêtres, puis portes ; à rang égal, les plus éloignées du foyer d'abord (arrière de la maison, comme
--      LK_Homes). L'entrée du foyer (porte extérieure simple du rez-de-chaussée la plus proche de la case du foyer)
--      n'est jamais barricadée : une barricade, d'un côté ou de l'autre, bloque la porte pour tous (IsoDoor.java
--      :1320-1325, fortification.md §5.3).
--   2. Étages (niveaux 1 .. BuildingDef:getMaxLevel(), tier "upper") : mêmes ouvertures, jusqu'à PLANKS.upper planches.
--   3. Défenses extérieures (tier "outer", décision LK14-T04 du 2026-10-08) : bâtiment = murs en bois vanilla
--      (WoodenWallFrame puis WoodenWallLvl1) sur le pourtour d'un rectangle à OUTER_MARGIN cases du bâtiment ; camp =
--      palissade de rondins (LogWall) sur le pourtour d'un carré de CAMP_RING cases autour du foyer. Seuls ces deux
--      ouvrages arrêtent un zombie (fortification.md §2.2). Une brèche de 2 × GAP + 1 segments reste ouverte en face de
--      l'entrée (camp : côté sud) : le portail en bois vanilla est enjambé. Segment écarté : case hors zone chargée,
--      dans un bâtiment, eau, escalier, case impraticable, bord déjà fermé (isBlockedTo) ; pourtour de plus de
--      MAX_OUTER segments : aucune défense extérieure (bâtiment trop grand).
-- Matériaux (scripts vanilla) : barricade = 1 Base.Plank + 1 Base.Nails par planche, marteau (tag Hammer), durée 200
--   par planche (M/entities/barricades/entity_barricade_planks.txt:46-60) ; mur = cadre (2 planches, 2 clous) + mur
--   (2 planches, 4 clous), marteau, 200 + 200 (walls/entity_woodenwallframe.txt:33-43, entity_wood_walllvl1.txt
--   :37-47) ; palissade = 4 Base.Log + 4 liens (draps déchirés, ficelle, corde, corde de draps), sans outil, 200
--   (walls/entity_logwall.txt:33-41). Durées en unités des actions vanilla (environ 48 par seconde réelle à vitesse 1 :
--   base api-42-21.md « unités de durée »). Compétences requises (Menuiserie 2 pour un mur) non vérifiées : les PNJ
--   n'ont pas de niveaux.
-- Reproductible : même foyer et même monde = même plan (cases parcourues dans un ordre fixe, tri total des
--   chantiers, identifiants de chantier tirés des coordonnées). Aucun chantier hors du foyer : ouvertures du seul
--   bâtiment du foyer, segments dans le rectangle plan.bounds (bâtiment + marge, ou carré du camp, plus une case).
-- Niveau 0..100 (Fortify.levelOf(gid), interface LivingKnox.Fortification lue par LK_Decisions.fortificationOf) :
--   avancement pondéré des trois tiers (WEIGHTS), étapes faites / étapes visées (planches, cadre + mur, palissade) ;
--   foyer sans aucun chantier possible = 100. Plan gardé en mémoire PLAN_MS ; zone non chargée : dernier plan connu,
--   sinon nil (le cadre de décision prend alors sa valeur neutre).
-- Faisable : matériaux comptés dans l'inventaire de référence du stock (LivingKnox.Stock.reference ; une boîte de
--   clous vaut BOX_NAILS clous, recette OpenBox100, M/recipes/recipes_packing.txt:220-241) et outil cherché dans
--   les conteneurs du foyer (LivingKnox.Stock.findItem, hasTag(ItemTag.HAMMER)). Les chantiers faisables sont pris
--   dans l'ordre du plan, les matériaux réservés de l'un au suivant (deux ouvriers ne comptent jamais les mêmes planches).
-- Point d'appel de LK14-T03 : Fortify.siteFor(gid, mid) rend au k-ième membre de poste « builder » (numéro croissant)
--   le k-ième chantier faisable. Cadre de décision : Fortify.hasWork(gid) (LK_Decisions.groupInput, champ fortWork).
-- Barricades posées (LK14-T03, Fortify/LK_Fortify_Build.lua) : un membre de poste « builder » dont la
--   cascade choisit « chore » (de jour, au foyer) reçoit son chantier de siteFor (Fortify.run, appelé par
--   LK_Routines.apply avant l'entretien et les corvées) ; il va à la case intérieure de l'ouverture, se tourne vers elle,
--   travaille avec le geste existant CFG.GESTURE pendant CFG.PLANK_MINUTES minutes de jeu par planche, puis l'autorité
--   cloue UNE planche (Fortify.nailPlank : état relu, une planche et un clou retirés du stock par LivingKnox.Stock
--   .takeItem, boîte de clous ouverte au besoin, IsoBarricade.AddBarricadeToObject + addPlank + transmission comme
--   BuildRecipeCode.barricade.OnCreate) ; il recommence jusqu'au nombre de planches visé.
-- Murs et palissade (LK14-T04, Fortify/LK_Fortify_Build.lua) : même ouvrier, même parcours ; un
--   chantier du pourtour se fait depuis sa case intérieure, geste CFG.RING_GESTURES, CFG.STAGE_MINUTES minutes avant
--   chaque étape (cadre puis mur ; palissade), posée par Fortify.buildStep (matériaux du stock retirés une seule fois,
--   ouvrage vanilla posé comme ISBuildIsoEntity:setInfo, transmis aux clients). La brèche n'est jamais construite.
-- Entretien et réparation (LK14-T06, Fortify/LK_Fortify_Work.lua, fiche §9) : le relevé note l'état de la planche
--   extérieure des barricades complètes (getThumpCondition : seule la planche extérieure s'use, IsoBarricade.java
--   :459-497) et la santé des murs et palissades achevés ; sous CFG.REPAIR_BELOW, un chantier « repair » s'ajoute au
--   plan (tier de l'ouvrage). Une planche retirée (barricade sous sa visée) reste un chantier de barricade ordinaire.
--   Après une attaque repoussée (marque LivingKnox.Defense.after de moins de CFG.REPAIR_URGENT_MINUTES), réparations
--   puis barricades entamées passent en tête du plan ; sinon les réparations viennent en dernier. Le même ouvrier
--   répare (Fortify.repair) : barricade = planche extérieure abîmée retirée (rendue au conteneur, comme
--   ISUnbarricadeAction) et planche saine clouée (1 planche + 1 clou) ; mur ou palissade = recette vanilla de
--   réparation « Wood » / « Log » (ISMoveableDefinitions.lua:656-668 : marteau, scie, planches ou rondins selon les
--   dégâts, une pièce facultative), santé remise au maximum (setHealth, synchronisé par le Java). Matériaux ou outils
--   absents : besoin noté (Fortify.needOf) et écrit au journal du groupe (kind « shortage »).
-- Rattrapage hors écran (LK14-T05, Fortify/LK_Fortify_Offscreen.lua, fiche §10) : relevé du plan gardé au
--   registre privé des groupes (champ fort), avancé par la simulation (Fortify.offscreenHour, appelé par
--   LK_Simulation.advance : ouvriers, temps, outils, matériaux pris une fois dans la référence du stock par son journal
--   d'écarts), posé par Fortify.addPlanks / Fortify.placeStructure quand la zone du foyer est chargée
--   (Fortify.applyPending, marque d'application idempotente LKFortOp).
-- Persistance : plan recalculé d'après le monde ; les objets posés par LK14-T03/T04 sont sauvegardés par le jeu avec
--   leur case ; besoins de réparation en mémoire seulement ; relevé hors écran (LK14-T05) dans le registre des groupes.
-- Fichiers (LK20-T07, un par section, chargés par les require ci-dessous ; chacun requiert d'abord le socle) :
--   Fortify/LK_Fortify_Common.lua    socle : table, constantes, CFG, état, compteurs, ports, table privée Fortify._
--   Fortify/LK_Fortify_Kinds.lua     registre des sortes de chantier
--   Fortify/LK_Fortify_World.lua     lecture du monde (Fortify.survey)
--   Fortify/LK_Fortify_Plan.lua      plan pur (Fortify.build)
--   Fortify/LK_Fortify_Authority.lua stock, faisabilité et autorité (Fortify.plan, feasible, siteFor)
--   Fortify/LK_Fortify_Build.lua     pose des barricades, murs et palissades
--   Fortify/LK_Fortify_Work.lua      réparations et travail de l'ouvrier (Fortify.run)
--   Fortify/LK_Fortify_Persist.lua   relevé hors écran gardé au registre, forme compacte (LK13-T07)
--   Fortify/LK_Fortify_Offscreen.lua rattrapage hors écran (Fortify.offscreenHour, snapshot)
--   Fortify/LK_Fortify_Apply.lua     pose du travail hors écran (Fortify.applyPending)
--   Fortify/LK_Fortify_Queue.lua     relevé de la minute étalé et examen des foyers (Fortify.scan)
-- Ce fichier garde les événements, l'activité « chore », la passe horaire et Fortify.reset. Les sortes de chantier
-- (LK_Fortify_Barricade, _Palisade, _Repair, _Wall) requièrent ce fichier et s'inscrivent ensuite.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_Simulation"   -- LK16-T09 : passe horaire (registerHourly)
require "LivingKnox/Fortify/LK_Fortify_Common"
require "LivingKnox/Fortify/LK_Fortify_Kinds"
require "LivingKnox/Fortify/LK_Fortify_World"
require "LivingKnox/Fortify/LK_Fortify_Plan"
require "LivingKnox/Fortify/LK_Fortify_Authority"
require "LivingKnox/Fortify/LK_Fortify_Build"
require "LivingKnox/Fortify/LK_Fortify_Work"
require "LivingKnox/Fortify/LK_Fortify_Persist"
require "LivingKnox/Fortify/LK_Fortify_Offscreen"
require "LivingKnox/Fortify/LK_Fortify_Apply"
require "LivingKnox/Fortify/LK_Fortify_Queue"

local Fortify = LivingKnox.Fortify


local function onLoadChunk()
    Fortify.scan("chunk")
end

local function onEveryOneMinute()
    Fortify.scan("minute")
end

LivingKnox.subscribe("LoadChunk", "Fortify.onLoadChunk", onLoadChunk)
LivingKnox.subscribe("EveryOneMinute", "Fortify.onEveryOneMinute", onEveryOneMinute)
-- LK13-T11 : file des relevés de la minute (une image chacun), vidée avant la sauvegarde du monde.
LivingKnox.subscribe("OnTickEvenPaused", "Fortify.frameStart", function() Fortify.onFrameStart() end)
LivingKnox.subscribe("OnTick", "Fortify.minuteQueue", function() Fortify.onFrame() end)
LivingKnox.subscribe("OnSave", "Fortify.minuteSave", function() Fortify.finishQueue() end)

-- Oublie les plans en mémoire (suites en jeu, administration).
function Fortify.reset()
    Fortify.state = { plans = {}, rest = {}, claims = {}, needs = {} }
    Fortify.minuteJobs:clear()   -- LK13-T11
end

-- Activité « chore » (ADR D04, ordre 10) : barricades du foyer pour un membre de poste « builder », avant l'entretien
-- et les corvées visibles (LK14-T03 ; inscrite en LK15-T02).
LivingKnox.Routines.registerActivity({ id = "chore.fortify", behaviour = "chore", order = 10,
    run = function(id, st, ctx, g)
        if ctx.duty ~= "builder" then return false end
        return Fortify.run(id, st, ctx, g)
    end })

-- LK16-T09 : passe horaire de la simulation hors écran (ordre 60, la dernière) : chantiers avancés hors écran avec
-- les matériaux du stock (LK14-T05).
LivingKnox.Simulation.registerHourly({ id = "fortify", order = 60, run = function(g, gid, hour)
    Fortify.offscreenHour(g, gid, hour)
end })
