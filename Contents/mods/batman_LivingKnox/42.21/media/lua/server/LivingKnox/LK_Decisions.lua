-- Living Knox : cadre de décision des PNJ, côté autorité (LK05-T02). Fiche : docs/annexes/conception/decisions.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
-- Aucune décision n'est prise par un client : le client propriétaire d'un corps n'exécute que des consignes LK03
-- (LK_Directives) et ne fait que rapporter ce que son PNJ perçoit (LK_Senses).
--
-- Modèle hybride (décision du 2026-10-08, docs/annexes/plans-termines/LK05-perception-decisions-routines.md) :
--   1. Groupe, long terme (Decisions.scoreGroup, pur) : à chaque heure de jeu, chaque groupe matérialisé (au moins un
--      membre incarné) note les objectifs de la liste fermée OBJECTIVES par utilité (0..100) d'après ses réserves
--      (stock réel du foyer, LivingKnox.Stock.assessGroup, LK08-T07 ; sinon besoins abstraits du registre), ses
--      blessés, son repos, la nuit, les menaces connues (vues par ses membres ces THREAT_HOURS dernières heures), sa
--      fortification (LK_Fortify, LK14-T02 : niveau, chantier faisable ; neutre si inconnue), l'hostilité de son type et la
--      personnalité de son chef (traits) ; petit écart déterministe par (groupe, jour). Le meilleur objectif fixe les
--      postes des membres (liste fermée DUTIES), choisis selon les comportements que leur rôle permet
--      (LivingKnox.GroupTypes : roles[rôle].behaviours) avec une rotation déterministe par jour. Changement
--      d'objectif ou de postes : une entrée « objective » au journal du groupe (raison écrite), sauvegarde.
--      Heures comptées d'après getWorldAgeHours (EveryHours ne part qu'une fois par mise à jour, même si plusieurs
--      heures passent : base api-42-21.md) ; un groupe qui se matérialise est noté aussitôt.
--   2. Membre, court terme (Decisions.decide, pur) : cascade de priorités fixe PRIORITIES (menace, peur, blessure,
--      faim, soif, fatigue, poste du groupe, routine) ; la première règle qui propose un comportement permis par le
--      rôle l'emporte. Comportements en liste fermée BEHAVIOURS, complétée par les extensions inscrites
--      (Decisions.registerExtension, LK05-T20 : règles placées avant une règle de PRIORITIES, au même rang, et leur
--      comportement ; aucune n'est nommée ici). Entrées : perception (LivingKnox.Senses.perceived),
--      santé de référence (LivingKnox.Health.get), attitude du groupe envers les joueurs perçus (LivingKnox.Hostility),
--      besoins (LivingKnox.Needs, LK05-T06 : jauges tenues par l'autorité ; module absent : valeurs neutres), poste
--      du groupe. Envies : fatigue -> dormir, faim et soif -> rentrer au foyer (repas abstrait au pas horaire de
--      LK_Needs, repas réels LK05-T07), peur -> un membre apeuré fuit la source récente de sa peur ou une menace plus
--      lointaine (FLEE_DIST_AFRAID), sinon se met à l'abri au foyer.
--      État à échéance : un comportement choisi dure jusqu'à son échéance (minutes de jeu, durée tirée) ; il n'est
--      recalculé qu'à l'échéance ou sur interruption (règle gagnante, comportement ou cible qui change).
--      Hasard déterministe : flux Park-Miller tiré de l'identité du PNJ et de la minute de jeu de la décision.
--   3. Sortie : consignes LK03 existantes seulement (Directives.moveTo, face, stop) et vigilance de la perception
--      (Senses.setVigilance) ; aucune autre action. Une consigne ouverte émise par un autre module (suite de test,
--      API) n'est jamais remplacée. Cadence bornée : un passage toutes les PASS_MS au plus, MEMBERS_PER_PASS membres
--      évalués par passage (tour à tour), liste des membres incarnés refaite toutes les ROSTER_MS.
-- Comportements branchés dans ce premier lot : rester au foyer (y retourner s'il est loin), se reposer, dormir, guet
-- (regard vers l'extérieur), regarder une menace perçue, s'éloigner d'une menace trop proche (LK06-T07 :
-- constantes mauvaises). Le combat (LK06), les routines riches (LK05-T03, T04), les repas (LK05-T07) et l'alerte de
-- groupe (LK05-T08) se branchent sur ces listes. LK05-T04 : comportement « chore » (corvée visible au foyer, de jour, pour les
-- postes keeper, carer, forager, builder et la routine), choisi et exécuté par LivingKnox.Routines.
-- LK05-T08 : alerte de groupe (LivingKnox.Alert, LK_Alert.lua). Chaque évaluation transmet la perception du membre à
-- l'alerte (Alert.observe) ; un membre concerné par une alerte en cours qui ne perçoit lui-même aucune menace prend le
-- comportement « alert » (règle threat, rang 1 : tâches, corvées et sommeil interrompus), regarde la dernière
-- position connue de la menace, geste de garde (membre valide) ou accroupi (constantes mauvaises, LK06-T07 : rentre
-- d'abord au foyer en courant) ; le même geste accompagne « watch » pendant une alerte. Alerte retombée : la cascade reprend.
-- LK06-T02 : un combattant dont le groupe a une cible d'attaque parmi les joueurs vus (LivingKnox.Combat.targetFor,
-- Hostility.chooseTarget) prend le comportement « fight » (règle threat, avant regard et fuite) ; la mêlée elle-même
-- est menée par LivingKnox.Combat (LK_Combat.lua), qui s'arrête dès que le membre change de comportement.
-- LK06-T05 (fiche docs/annexes/conception/fuite-reddition.md) : en tête de la règle threat, dans l'ordre :
--   - reddition (« surrender ») d'un non-combattant d'un groupe qui ne tire pas le premier, frappé par un joueur et
--     blessé, ou acculé par un joueur hostile : arrêt, regard vers le joueur, mains levées (geste « surrender »,
--     LK06-T12) et une réplique de reddition dite une fois à l'entrée (Decisions.announceSurrender) ; tant qu'elle
--     dure, le groupe ne prend plus ce joueur pour cible (Decisions.spared) ; un nouveau coup de ce joueur la rompt
--     (Decisions.noteHit : mains baissées aussitôt, réplique de trahison) ;
--   - retraite (« retreat ») d'un membre en danger (cible, coup reçu, menace proche) blessé (santé < RETREAT.HEALTH)
--     ou, pour un combattant, à bout de nerfs (peur >= RETREAT.FEAR) ; moral du groupe bas : seuils plus prudents.
--     Loin du foyer : il y rentre en courant ; sans foyer : fuite pondérée par la proximité des menaces ; au foyer,
--     un combattant à bout de nerfs se terre (accroupi) et un blessé s'y défend ;
--   - appel à l'aide : un coup accepté sur un membre (LK_Health -> Decisions.noteHit) alerte le groupe (LK_Alert, cri)
--     et pose une demande d'aide ; les combattants à HELP.RADIUS cases prennent l'agresseur pour cible (défense) ;
--     un combattant qui se retire passe sa cible aux autres de la même façon.
-- LK11-T02 (fiche docs/annexes/conception/sommations.md) : un combattant qui voit un joueur averti (Hostility.chooseTarget,
-- action "warn") près du foyer ou du groupe mène sa sommation (comportement « warn », LivingKnox.Encounters), après
-- la retraite et avant la défense, sans cible d'attaque.
-- LK05-T09 (fiche docs/annexes/conception/defense.md) : pendant une défense du foyer (LivingKnox.Defense.contextFor, alerte et
-- menace recensée près du foyer), règle threat après la retraite : comportement « defend » (place au poste ou à l'abri,
-- cible prise seulement depuis la place), mené par LivingKnox.Defense.apply.
-- LK06-T07 (décision du 2026-10-12, « tout le monde se bat », fiche decisions.md) : la fuite, l'abri et la retraite ne
-- dépendent plus du rôle. Tout membre valide (Decisions.unfitOf : santé >= woundRatio et peur < fearHigh) se
-- bat contre un zombie à portée (Zombies.targetFor ; un joueur reste la cible des seuls rôles fight / defend) et
-- tient face à une menace proche ; un membre aux constantes mauvaises fuit (ou s'abrite au foyer) ; un groupe
-- débordé (Decisions.overwhelmedOf : menaces perçues > rapport DefenseWithdrawRatio x membres valides proches) se
-- replie (« retreat », clé « overwhelmed », hystérésis à rapport - 1). Les rôles gardent le poste, la sommation, la
-- reddition et la montée de peur (LK_Needs).
-- LK05-T05 (fiche docs/annexes/conception/expeditions.md) : membre de l'équipe d'une expédition en cours (ctx.trip,
-- LivingKnox.Expeditions.memberTrip) : règle duty -> comportement « expedition » (trajet, fouille, retour menés par
-- LivingKnox.Expeditions.apply) ; faim, soif et fatigue attendent le retour, menace, peur et blessure passent avant.
--
-- Persistance (registre des groupes, schéma 1 inchangé, champs facultatifs : voir LK_Groups.lua) : group.objective
-- (dernier objectif choisi), member.duty (dernier poste). États des membres, mémoire des menaces et heure de la
-- dernière notation : mémoire seulement (recalculés après un redémarrage).
-- Fichiers du moteur (LK20-T09, un par section, chargés par les require ci-dessous ; chacun requiert d'abord le
-- socle ; les comportements LK_Decide_*.lua du même dossier requièrent cette façade) :
--   Decisions/LK_Decisions_Common.lua      socle : table, listes fermées, CFG, état, compteurs, seuils de danger,
--                                          hasard déterministe, horloge, table Decisions._ (cfg, now, anyOf, pick)
--   Decisions/LK_Decisions_Goals.lua       objectifs du groupe et postes (scoreObjectives, assignDuties ; pur)
--   Decisions/LK_Decisions_Cascade.lua     cascade d'un membre et décision (règles, decide, replaces ; pur)
--   Decisions/LK_Decisions_Registries.lua  extensions de la cascade et fournisseurs de contexte (registerExtension,
--                                          registerContext)
--   Decisions/LK_Decisions_Inputs.lua      entrées de l'autorité et notation des groupes (groupInput, scoreGroup,
--                                          scorePass)
--   Decisions/LK_Decisions_HourQueue.lua   notation horaire étalée (hourQueue, onEveryHours, finishHourQueue)
--   Decisions/LK_Decisions_Members.lua     menaces perçues d'un membre (threatsOf)
--   Decisions/LK_Decisions_Aid.lua         coups reçus, aide et reddition (noteHit, callHelp, announceSurrender)
--   Decisions/LK_Decisions_Context.lua     contexte d'un membre (context, perceptionOf, targetOf, ableNear)
--   Decisions/LK_Decisions_Apply.lua       consignes, gestes et application d'une décision (apply)
--   Decisions/LK_Decisions_Pass.lua        évaluation, passages des membres, lecture pour les accords (evaluate, tick,
--                                          aims)
--   Decisions/LK_Decisions_Refusals.lua    refus d'un ordre du moteur (judgeOrder, refuseDuties, flushRefusals)
-- Ce fichier garde les fournisseurs de contexte propres au moteur, les événements, Decisions.get et Decisions.reset.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"
require "LivingKnox/Decisions/LK_Decisions_Common"
require "LivingKnox/Decisions/LK_Decisions_Goals"
require "LivingKnox/Decisions/LK_Decisions_Cascade"
require "LivingKnox/Decisions/LK_Decisions_Registries"
require "LivingKnox/Decisions/LK_Decisions_Inputs"
require "LivingKnox/Decisions/LK_Decisions_HourQueue"
require "LivingKnox/Decisions/LK_Decisions_Members"
require "LivingKnox/Decisions/LK_Decisions_Aid"
require "LivingKnox/Decisions/LK_Decisions_Context"
require "LivingKnox/Decisions/LK_Decisions_Apply"
require "LivingKnox/Decisions/LK_Decisions_Pass"
require "LivingKnox/Decisions/LK_Decisions_Refusals"

local Decisions = LivingKnox.Decisions
local P = Decisions._   -- fonctions privées partagées entre les fichiers du moteur (LK_Decisions_Common.lua)

-- Fournisseurs propres au moteur (ordre : voir le registre). Les champs des modules (routines, expédition, traque,
-- alerte, défense du foyer, sommation, peur) sont inscrits par ces modules eux-mêmes.
Decisions.registerContext({ id = "home", order = 40, fill = function(ctx)
    if ctx.home == nil then return end
    ctx.homeDist = math.max(math.abs(ctx.x - (ctx.home.x + 0.5)), math.abs(ctx.y - (ctx.home.y + 0.5)))
    ctx.atHome = ctx.z == ctx.home.z and ctx.homeDist <= P.cfg().HOME_RADIUS
end })
Decisions.registerContext({ id = "perception", order = 50, fill = function(ctx, src)
    src.per = Decisions.perceptionOf(ctx.id)
end })
Decisions.registerContext({ id = "threats", order = 60, fill = function(ctx, src)
    ctx.threats = Decisions.threatsOf(src.per, P.attitudesFor(src.gid, src.g, src.players))
    ctx.threat = ctx.threats[1]
end })
Decisions.registerContext({ id = "target", order = 70, fill = function(ctx, src)
    ctx.target = Decisions.targetOf(ctx, src)
end })
Decisions.registerContext({ id = "defence", order = 80, fill = function(ctx, src)   -- LK06-T05
    Decisions.defenceContext(ctx, src.gid, src.g, src.m, src.per, src.players, src.minute)
end })
-- Besoins (LK05-T06) : lus après la montée de la peur (fournisseur « fear » de LK_Needs, ordre 120) ; module absent :
-- valeurs neutres (Decisions.needsOf).
Decisions.registerContext({ id = "needs", order = 130, fill = function(ctx, src)
    ctx.needs = Decisions.needsOf(src.gid, src.mid)
end })
-- LK06-T07 : groupe débordé (menaces perçues qui mettent en danger contre membres valides proches), pour un membre
-- valide seulement (aux constantes mauvaises, la règle threat le retire déjà).
Decisions.registerContext({ id = "overwhelmed", order = 140, fill = function(ctx, src)
    local weight = Decisions.threatWeight(ctx.threats)
    if weight <= 0 or Decisions.unfitOf(ctx) ~= nil then return end
    local prev = Decisions.state.members[ctx.id]
    ctx.overwhelmed = Decisions.overwhelmedOf(weight, Decisions.ableNear(src.gid, src.g, ctx.x, ctx.y, ctx.z),
        prev ~= nil and prev.b == "retreat" and prev.key == "overwhelmed")
end })

LivingKnox.subscribe("OnTickEvenPaused", "Decisions.hourFrameStart", function() LivingKnox.Decisions.onFrameStart() end)
LivingKnox.subscribe("OnTick", "Decisions.hourQueue", function() LivingKnox.Decisions.hourTick() end)
LivingKnox.subscribe("OnSave", "Decisions.hourSave", function() LivingKnox.Decisions.finishHourQueue() end)

-- État courant d'un membre (copie), ou nil : { b, rule, why, key, start, untilMin, gid, mid, ... }.
function Decisions.get(id)
    local s = Decisions.state.members[id]
    if s == nil then return nil end
    local out = {}
    for k, v in pairs(s) do out[k] = v end
    return out
end

-- Réinitialisation de la mémoire (nouvelle partie, tests).
function Decisions.reset()
    Decisions.state = { members = {}, issued = {}, threats = {}, scored = {}, roster = {}, rosterMs = nil,
        cursor = 0, lastPass = nil, gestures = {} }
    Decisions.hourQueue:clear()   -- LK13-T11
    Decisions.evals.at = {}   -- E09-T05 : numéros oubliés, compteur gardé (jamais réutilisé)
end

return Decisions
