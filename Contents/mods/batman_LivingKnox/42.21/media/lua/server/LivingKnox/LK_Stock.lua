-- Living Knox : stock réel du groupe dans les conteneurs de son foyer (LK08-T06). Fiche : docs/annexes/conception/stock.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Catégories (CATEGORIES) tirées des données de script des objets, jamais de leur nom affiché : eau = récipient
-- (FluidContainer) non vide dont le fluide principal est Fluid.Water ou Fluid.TaintedWater ; sinon d'après
-- DisplayCategory du script (InventoryItem.getDisplayCategory, J/inventory/InventoryItem.java:2873) : Food ->
-- nourriture, FirstAid et Bandage -> soins, Ammo -> munitions, Material et MaterialWeapon (planches) -> matériaux.
-- Tout autre objet est ignoré (ni compté, ni surveillé).
-- Conteneurs du foyer (zone de LK_Homes : RADIUS cases autour du foyer, niveau du foyer) : bâtiment = tous les
--   conteneurs des objets des cases du bâtiment du foyer (frigo, placards, caisse posée...) ; camp = conteneurs des
--   objets posés par LK_Homes pour le groupe (tentes, ModData LKHome). Seuls les objets au premier niveau d'un
--   conteneur comptent (pas le contenu d'un sac rangé dedans).
-- Inventaire de référence privé (registre des groupes, champ facultatif stock, schéma 1 inchangé, contrôlé ici) :
--   stock = { v = FORMAT, hx, hy, hz, fill = "filling" | "done", day, items = { { i = id, t = type complet,
--             c = catégorie, k = clé du conteneur }, ... } } (MAX_ITEMS au plus).
--   Identité d'un objet = InventoryItem.getID(), tirée au hasard à la création et sauvegardée avec l'objet
--   (J/inventory/InventoryItemFactory.java:126, InventoryItem.java:1521, 1740) ; un transfert MP déplace le même
--   objet (J/core/Transaction.java:258-262 : Remove puis addItem). Clé d'un conteneur = "x,y,z,type,n" (n = rang
--   parmi les conteneurs du même type sur la case).
-- Remplissage initial, une seule fois par foyer : après l'aménagement (marque LK_Homes valide), les objets du kit du
--   type de groupe (KITS, objets vanilla, quantités modestes, sans périssable) sont créés (instanceItem), marqués
--   (ModData LKStock = groupe), bouteilles d'eau vidées puis remplies d'eau (FluidContainer.Empty puis addFluid,
--   base api-42-21.md), rangés tour à tour dans les conteneurs posés par LK_Homes (caisse ou tentes), marqués
--   explorés avant (un conteneur non exploré recevrait le butin vanilla en plus : base world-placement.md) et
--   envoyés aux clients par sendAddItemToContainer sur un serveur. Sans conteneur posé (foyer « skip » des suites) :
--   rien n'est créé. Marque écrite AVANT la création (fill = "filling") : un arrêt en plein remplissage ou une
--   marque « filling » relue au redémarrage ne fait jamais recréer. Garde si le registre recule (fichier plus ancien
--   que le monde) : un objet marqué LKStock du groupe déjà présent dans un conteneur du foyer rétablit la référence
--   sans rien créer.
-- Relecture (Stock.check) : chaque fois que la zone du foyer est chargée (LoadChunk au plus une fois par SCAN_MS,
--   chaque minute de jeu ; au plus une relecture par groupe toutes les CHECK_MS) et seulement si toutes les cases de
--   la zone sont lisibles (LK_Homes.ready, puis chaque case : un conteneur d'une case non chargée paraîtrait vidé).
--   La référence devient le contenu réel. Différence avec l'ancienne référence :
--   - objet ajouté (joueur qui dépose, butin vanilla d'un conteneur ouvert plus tard) : accepté ;
--   - objet déplacé d'un conteneur du foyer à un autre : accepté ;
--   - objet disparu : cherché par son identifiant dans l'inventaire de chaque joueur connecté (sacs compris,
--     ItemContainer.getItemWithIDRecursiv, J/inventory/ItemContainer.java:2909) : trouvé = vol attribuable à ce
--     joueur, rapporté à LK_Hostility (fait "theft", attributable) une fois par joueur et par relecture, et au plus
--     une fois par THEFT_COOLDOWN_HOURS par groupe et par joueur ; introuvable (objet mangé, posé au sol, donné) :
--     perte journalisée sans coupable.
--   Choix documenté : aucun événement serveur fiable ne signale un transfert d'objet (en MP, transaction Java sans
--   Lua côté serveur : base combat-and-xp.md, « Transferts d'objets en MP ») ; la différence à la relecture, avec
--   l'identifiant de l'objet retrouvé dans l'inventaire du joueur, est la seule preuve côté serveur.
-- Les prélèvements du groupe lui-même (repas, dons, troc : LK05-T07, LK11-T06, LK11-T08) passent par ce module pour
-- mettre la référence à jour dans le même pas ; la mise à jour des conteneurs réels d'après la référence (simulation
-- hors écran) est LK09-T06.
-- Repas réels (LK05-T07, fiche docs/annexes/conception/besoins.md, « Repas réels ») : Stock.findMeal cherche le premier objet
--   consommable (Stock.consumable : nourriture ni pourrie, ni gelée, ni crue dangereuse ; eau = récipient dont le fluide
--   principal est Fluid.Water, eau croupie écartée) dans l'ordre des conteneurs du foyer ; Stock.takeMeal retire UN
--   objet d'un conteneur relu au moment de la prise (DoRemoveItem, une seule surcharge ; sendRemoveItemFromContainer
--   sur un serveur : clients proches, J/network/GameServer.java:2269-2277) et l'ôte de la référence dans la même
--   écriture du registre : la relecture suivante ne le voit ni perdu ni volé. Rien n'est jamais créé. Aucun objet
--   consommable : Stock.reportShortage écrit au journal du groupe (kind « shortage », au plus une fois par
--   SHORTAGE_HOURS et par catégorie) ; le rationnement et les besoins du groupe suivent la référence (LK08-T07).
--
-- Seuils, rationnement et besoins du groupe (LK08-T07, fiche docs/annexes/conception/stock.md, section « Seuils ») :
--   - réserve visée par catégorie selon le nombre de membres vivants n (SUPPLY) : nourriture et eau = DAILY x n x
--     TARGET_DAYS (portions abstraites : un objet = une portion de la journée d'un membre), soins, munitions,
--     matériaux = PER_MEMBER x n (arrondi au-dessus) ; niveau 0..100 = réserve / visée ;
--   - jours d'autonomie = objets / (DAILY x n) pour la nourriture et l'eau, au dixième inférieur ; autonomie du
--     groupe = la plus basse des deux ;
--   - rationnement (champ facultatif stock.ration 0..3, jamais une raison d'écarter la référence) : normal, réduit
--     (autonomie < RATION_DAYS[1]), strict (< RATION_DAYS[2]), épuisé (nourriture ou eau à zéro) ; on durcit
--     aussitôt, on ne revient à un niveau plus doux qu'avec RATION_MARGIN jour(s) d'avance ; changement relu à
--     chaque Stock.check, écrit au journal du groupe (kind « ration ») et au journal du moteur ;
--   - besoins = catégories sous leur visée, ordre fixe et reproductible : épuisé, critique (niveau < CRITICAL), bas,
--     puis niveau croissant, puis ordre de CATEGORIES. Stock.needs(gid) (copie) ; Stock.assessGroup(g) pour le
--     cadre de décision (LK_Decisions.groupInput lit les niveaux à chaque notation horaire).
--   Points d'appel des consommateurs à venir : expéditions (LK05-T05) et missions des PNJ = Stock.needs(gid)
--   .needs (premier = ce qui manque le plus) ; fortification (LK14) = entrée « materials » ; repas réels (LK05-T07) et
--   stock hors écran (LK09-T06) = Stock.portion(gid) (part d'une ration normale).
--
-- Stock hors écran (LK09-T06, fiche docs/annexes/conception/stock.md, section « Hors écran ») :
--   - pendant la simulation (LK_Simulation.advance, dans son écriture du registre, logique pure sans accès au monde) :
--     repas abstrait quotidien à l'heure du jour OFFSCREEN.MEAL_HOUR (Stock.offscreenHour : membres vivants au foyer,
--     hors expédition et hors membres incarnés, DAILY x part de ration Stock.portion, arrondi au plus proche) et
--     butin d'une expédition abstraite LK09-T02 (Stock.offscreenLoot : un objet par OFFSCREEN.LEVEL_PER_ITEM points
--     de réserve gagnés, types vanilla OFFSCREEN.ITEMS) modifient l'inventaire de référence ; l'écart avec les
--     conteneurs réels est gardé dans le journal d'écarts en attente stock.pend = { n = dernier numéro d'écart,
--     ops = { { u = numéro, o = "take", i, t, c, k } | { u = numéro, o = "add", t, c } } } (borné : PEND_MAX ; un
--     objet pris quitte items, un objet ajouté n'a pas encore d'identifiant). Une prise annule d'abord un ajout en
--     attente de la même catégorie. Les totaux (Stock.count, besoins, rationnement) comptent les ajouts en attente.
--   - à l'arrivée d'un joueur (Stock.check, dès que toute la zone du foyer est lisible, avant la différence ; et avant
--     toute prise du groupe dans les conteneurs) : Stock.applyPending retire les objets pris (DoRemoveItem,
--     sendRemoveItemFromContainer) et crée les objets ajoutés (instanceItem, objets « Base. » seulement, dans le
--     conteneur posé par LK_Homes sinon le premier, sendAddItemToContainer), puis ôte du journal les seuls écarts
--     traités (par numéro) et ajoute les objets créés à la référence, en une écriture. Marque d'application
--     idempotente : chaque objet créé porte ModData LKStockOp = "<groupe>:<numéro>" jusqu'à cette écriture ; si elle
--     n'a pas eu lieu (erreur, arrêt), l'objet marqué est repris au lieu d'être recréé ; un objet pris déjà absent
--     n'est pas recherché ailleurs. Un écart ajouté pendant l'application reste en attente.
--   - fortification hors écran (LK14-T05, LK_Fortify) : Stock.offscreenCount / Stock.offscreenTake prennent des
--     matériaux par type complet dans la référence (écarts « take » du même journal, appliqués de la même façon).
-- Fichiers (LK20-T08, un par section, chargés par les require ci-dessous ; chacun requiert d'abord le socle) :
--   Stock/LK_Stock_Common.lua     socle : table, formats, kits, CFG, SUPPLY, OFFSCREEN, état, compteurs, table Stock._
--   Stock/LK_Stock_Reference.lua  catégories et inventaire de référence (validRef, validPend, count, reference)
--   Stock/LK_Stock_Containers.lua conteneurs du foyer, lecture et remplissage initial (containers, read, fill)
--   Stock/LK_Stock_Check.lua      joueurs, vols, différence et relecture (holderOf, diff, check)
--   Stock/LK_Stock_Ration.lua     seuils, rationnement et besoins (assess, needs, portion, updateRation)
--   Stock/LK_Stock_Meals.lua      repas réels et pénuries (findMeal, takeMeal, reportShortage)
--   Stock/LK_Stock_Materials.lua  matériaux d'entretien (findItem, drawFluid, takeItem, untrack)
--   Stock/LK_Stock_Offscreen.lua  stock hors écran (offscreenHour, offscreenLoot, offscreenCount, offscreenTake)
--   Stock/LK_Stock_Apply.lua      application du journal d'écarts (applyPending)
--   Stock/LK_Stock_Queue.lua      examen des foyers et relecture de la minute étalée (scan, queueScan)
-- Ce fichier garde les événements, la passe horaire, Stock.clear et Stock.reset.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Simulation"   -- LK16-T09 : passe horaire (registerHourly)
require "LivingKnox/Stock/LK_Stock_Common"
require "LivingKnox/Stock/LK_Stock_Reference"
require "LivingKnox/Stock/LK_Stock_Containers"
require "LivingKnox/Stock/LK_Stock_Check"
require "LivingKnox/Stock/LK_Stock_Ration"
require "LivingKnox/Stock/LK_Stock_Meals"
require "LivingKnox/Stock/LK_Stock_Materials"
require "LivingKnox/Stock/LK_Stock_Offscreen"
require "LivingKnox/Stock/LK_Stock_Apply"
require "LivingKnox/Stock/LK_Stock_Queue"

local Stock = LivingKnox.Stock
local P = Stock._   -- fonctions privées partagées entre les fichiers de Stock/ (LK_Stock_Common.lua)

-- Efface la référence d'un groupe (suites en jeu, administration). Les objets restent où ils sont.
function Stock.clear(gid)
    local g = LivingKnox.Groups.get(gid)
    if g ~= nil and g.stock ~= nil then P.writeRef(gid, nil) end
    Stock.state.checked[gid] = nil
end

function Stock.reset()
    Stock.state = { checked = {}, lastScan = nil, lastTheft = {}, shortage = {} }
    Stock.queue:clear()
end

-- Événements : LoadChunk et EveryOneMinute, inscrits après ceux de LK_Homes (ordre des fichiers) : le stock d'un
-- foyer aménagé dans la même minute est relu à partir de l'image suivante (LK13-T09 : un groupe par image).
local function onLoadChunk()
    Stock.scan("chunk")
end

local function onEveryOneMinute()
    Stock.queueScan()
end

LivingKnox.subscribe("LoadChunk", "Stock.onLoadChunk", onLoadChunk)
LivingKnox.subscribe("EveryOneMinute", "Stock.onEveryOneMinute", onEveryOneMinute)
LivingKnox.subscribe("OnTickEvenPaused", "Stock.frameStart", function() Stock.onFrameStart() end)
LivingKnox.subscribe("OnTick", "Stock.minuteQueue", function() Stock.onFrame() end)

-- LK16-T09 : passe horaire de la simulation hors écran (ordre 50, après les besoins, avant les chantiers) : repas
-- abstrait pris dans le stock de référence (LK09-T06).
LivingKnox.Simulation.registerHourly({ id = "meal", order = 50, run = function(g, gid, hour, _, step)
    Stock.offscreenHour(g, gid, hour, step.day)
end })

return Stock
