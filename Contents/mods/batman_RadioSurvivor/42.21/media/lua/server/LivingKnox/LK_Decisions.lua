-- Living Knox : cadre de décision des PNJ, côté autorité (LK05-T02). Fiche : docs/annexes/conception/decisions.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
-- Aucune décision n'est prise par un client : le client propriétaire d'un corps n'exécute que des consignes LK03
-- (LK_Directives) et ne fait que rapporter ce que son PNJ perçoit (LK_Senses).
--
-- Modèle hybride (décision du 2026-10-08, docs/annexes/plans/LK05-perception-decisions-routines.md) :
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
--      rôle l'emporte. Comportements en liste fermée BEHAVIOURS. Entrées : perception (LivingKnox.Senses.perceived),
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
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"

local Decisions = LivingKnox.Decisions or {}
LivingKnox.Decisions = Decisions

-- Objectifs du groupe (liste fermée ; ordre = départage à score égal).
Decisions.OBJECTIVES = { "settle", "rest", "guard", "heal", "supply", "fortify" }
-- Postes attribués aux membres par l'objectif (liste fermée).
Decisions.DUTIES = { "sentry", "rest", "keeper", "carer", "forager", "builder" }
-- Comportements de rôle (LivingKnox.GroupTypes.BEHAVIOURS) qui rendent un membre apte à un poste.
Decisions.DUTY_NEEDS = {
    sentry = { "guard", "patrol", "defend" },
    carer = { "heal" },
    forager = { "scavenge", "forage", "expedition", "raid", "scout" },
    builder = { "fortify", "maintain" },
}
-- Cascade de priorités du membre (ordre fixe, décision du 2026-10-08).
Decisions.PRIORITIES = { "threat", "fear", "wound", "hunger", "thirst", "fatigue", "duty", "routine" }
-- Comportements (liste fermée) : vigilance de la perception, conditions de rôle. needs : au moins un de ces
-- comportements de rôle ; nonCombatant : interdit à un combattant (rôle qui permet fight ou defend ; plus aucun
-- comportement ne le porte depuis LK06-T07, condition gardée pour les comportements ajoutés plus tard).
Decisions.BEHAVIOURS = {
    home = { vigil = "rest" },                                     -- rester au foyer (y retourner s'il est loin)
    rest = { vigil = "rest" },                                     -- se reposer au foyer
    sleep = { vigil = "sleep" },                                   -- dormir au foyer
    guard = { vigil = "guard", needs = { "guard", "patrol", "defend" } },   -- guet : au poste, regard vers l'extérieur
    patrol = { vigil = "guard", needs = { "guard", "patrol", "defend" } },  -- ronde autour du foyer (LK05-T03)
    chore = { vigil = "rest" },                                    -- corvée visible au foyer (LK05-T04, de jour)
    watch = { vigil = "guard" },                                   -- regarder une menace perçue
    flee = { vigil = "guard" },                                    -- s'éloigner d'une menace (LK06-T07 : constantes
                                                                   -- mauvaises ou groupe débordé, tout rôle)
    alert = { vigil = "guard" },                                   -- alerte du groupe (LK05-T08) : dernière position
    fight = { vigil = "guard" },                                   -- mêlée ou tir contre la cible retenue (LK06-T02,
                                                                   -- LK_Combat) ; LK06-T07 : zombie pour tout rôle,
                                                                   -- joueur pour un rôle qui permet fight ou defend
    meal = { vigil = "rest" },                                     -- manger ou boire dans le stock (LK05-T07)
    retreat = { vigil = "guard" },                                 -- retraite (LK06-T05) : foyer, fuite ou abri
    surrender = { vigil = "guard" },                               -- reddition (LK06-T05) : arrêt, mains levées
    defend = { vigil = "guard" },                                  -- défense du foyer (LK05-T09, LK_Defense)
    warn = { vigil = "guard", needs = { "fight", "defend" } },     -- sommation (LK11-T02, LK_Encounters)
    expedition = { vigil = "guard" },                              -- expédition physique (LK05-T05, LK_Expeditions)
    revenge = { vigil = "guard" },                                 -- vengeance : traque, retour (LK11-T05, LK_Relations)
}
Decisions.COMBAT_BEHAVIOURS = { "fight", "defend" }
-- Besoins individuels (LivingKnox.Needs, LK05-T06) : valeurs neutres si le module manque.
Decisions.NEEDS = { "hunger", "thirst", "fatigue", "fear" }

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche ; à recalibrer en jeu).
Decisions.CFG = Decisions.CFG or {
    PASS_MS = 1000,          -- un passage des membres au plus par seconde réelle
    MEMBERS_PER_PASS = 4,    -- membres évalués au plus par passage
    MEMBERS_PER_FRAME = 1,   -- LK13-T11 : membres du passage évalués au plus par image (le reste aux images suivantes)
    ROSTER_MS = 5000,        -- liste des membres incarnés refaite au plus toutes les 5 s
    HOME_RADIUS = 10,        -- cases : « au foyer » à cet écart au plus (en x et en y) de la case du foyer, même
                             -- niveau ; au-delà de la place d'un membre matérialisé (Config.MATERIALIZE.PLACE_RADIUS 8)
    HOME_PLACE_RADIUS = 6,   -- cases : recherche d'une case libre près du foyer pour y retourner
    FLEE_DIST = 6,           -- cases : menace plus proche -> un membre aux constantes mauvaises s'éloigne (LK06-T07)
    FLEE_DIST_AFRAID = 12,   -- cases : idem quand sa peur atteint NEED_HIGH.fear (LK05-T06) ; source de la peur
                             -- (LivingKnox.Needs.fearSource) à cet écart au plus -> fuite sans menace perçue
    FLEE_STEP = 10,          -- cases : longueur du pas de fuite
    FACE_DELTA = 30,         -- degrés : nouvelle consigne « face » si la menace a tourné d'au moins autant
    WOUND_RATIO = 0.5,       -- santé de référence / santé de naissance sous laquelle le membre se repose
    WOUND_DUTY = 50,         -- blessure (0..100) à partir de laquelle le poste est « rest »
    NEED_HIGH = { fear = 70, hunger = 70, thirst = 70, fatigue = 80 },
    MINUTES = { watch = { 1, 1 }, flee = { 2, 2 }, guard = { 10, 20 }, patrol = { 10, 20 }, home = { 15, 30 },
        rest = { 20, 40 }, sleep = { 30, 60 }, fight = { 1, 1 },
        chore = { 20, 40 }, alert = { 2, 2 }, warn = { 1, 1 },
        meal = { 15, 30 }, retreat = { 3, 3 }, surrender = { 2, 2 }, defend = { 1, 1 },
        expedition = { 10, 10 }, revenge = { 10, 10 } },   -- minutes de jeu : durée
                                                                         -- d'un état
                                                                         -- (tirée entre les deux bornes)
    -- LK06-T05 : retraite (santé et moral), reddition, appel à l'aide (seuils et raisons : fuite-reddition.md).
    RETREAT = {
        HEALTH = 0.35,       -- santé de référence / naissance sous laquelle un membre en danger se retire
        FEAR = 85,           -- peur à partir de laquelle un combattant en danger rompt
        LOW_MORALE = 30,     -- moral du groupe sous lequel les seuils deviennent plus prudents :
        MORALE_HEALTH = 0.15,   --   santé limite relevée d'autant
        MORALE_FEAR = 20,       --   peur limite abaissée d'autant
        DIST = 15,           -- cases : menace (fuite permise) assez proche pour mettre en danger
        WEIGH_DIST = 15,     -- cases : menaces comptées dans la fuite pondérée
    },
    SURRENDER = {
        HEALTH = 0.6,        -- santé sous laquelle un membre frappé par un joueur se rend
        DIST = 2,            -- cases : joueur assez proche pour qu'on ne puisse plus le fuir
        KEEP = 15,           -- cases : la reddition dure tant que le joueur reste perçu à cette distance
        LINGER = 2,          -- minutes : puis encore ce délai après l'avoir perdu de vue
        BETRAYED = 60,       -- minutes : plus de reddition à un joueur qui l'a rompue
    },
    HIT_MINUTES = 2,         -- minutes : un coup reçu met le membre en danger
    HELP = {
        MINUTES = 3,         -- minutes : durée d'une demande d'aide
        RADIUS = 20,         -- cases (même niveau) autour de la victime : combattants qui viennent en renfort
    },
    -- LK06-T07 : groupe débordé hors de la défense du foyer (menaces perçues à RETREAT.DIST cases contre membres
    -- valides proches) ; rapport = option DefenseWithdrawRatio (LivingKnox.Defense.ratios), repli ci-dessous.
    OVERWHELM = {
        RATIO = 3,           -- débordé si menace > RATIO x membres valides (retour : menace <= (RATIO - 1) x valides)
        HOSTILE_WEIGHT = 3,  -- un joueur hostile compte comme autant de zombies (= Defense.CFG.HOSTILE_WEIGHT)
        RADIUS = 20,         -- cases (même niveau) : membres valides comptés autour du membre (= HELP.RADIUS)
    },
    THREAT_HOURS = 6,        -- heures : menaces « connues » du groupe
    WATCH_HOURS = 4,         -- heures : durée d'un quart de garde (relève des guetteurs, LK05-T03)
    WATCH_START = 22,        -- heure du jour où commence un quart (22 h, 2 h, 6 h, 10 h, 14 h, 18 h)
    THREAT_KEYS = 16,        -- menaces distinctes comptées au plus par heure et par groupe
    FORT_NEUTRAL = 50,       -- fortification inconnue (LK14 absent) : valeur neutre
    FORT_THREAT = 5,         -- LK14-T02 : par menace connue, bonus de fortify quand un chantier est faisable
    FORT_THREAT_MAX = 20,    --   plafonné à autant
    JITTER = 3,              -- écart déterministe des scores par (groupe, jour)
    NEED_OK = 60,            -- réserve à partir de laquelle ravitailler ne presse plus
    REST_OK = 60,            -- repos du groupe à partir duquel se reposer de jour ne presse plus
    HEAL_MIN = 30,           -- blessure la plus grave à partir de laquelle soigner compte
    SETTLE = 30,             -- score fixe de la vie ordinaire au foyer
    NIGHT_REST = 70,         -- score du repos la nuit
    -- Personnalité du chef : bonus par trait (LivingKnox.GroupTypes.TRAITS) et par objectif.
    TRAITS = { nervous = { guard = 15 }, keenHearing = { guard = 5 }, tidy = { settle = 5, fortify = 10 },
        strong = { fortify = 10 }, smoker = { rest = 5 }, drinker = { rest = 5 } },
}

Decisions.state = Decisions.state or { members = {}, issued = {}, threats = {}, scored = {}, roster = {},
    rosterMs = nil, cursor = 0, lastPass = nil, gestures = {} }
Decisions.stats = Decisions.stats or { passes = 0, evaluated = 0, decided = 0, kept = 0, issued = 0, refused = 0,
    external = 0, maxPerPass = 0, scored = 0, objectiveChanges = 0, watchChanges = 0 }
for _, k in ipairs({ "hitsNoted", "helpCalls", "helpTargets", "retreats", "surrenders", "surrenderBroken",
    "spared", "surrenderLines", "betrayalLines" }) do
    Decisions.stats[k] = Decisions.stats[k] or 0   -- LK06-T05
end

local M = 2147483647

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function cfg() return Decisions.CFG end

-- LK05-T14 : seuils de danger réglables (options sandbox, LivingKnox.Config.danger) ; repli : valeurs de CFG.
function Decisions.fleeDist() return LivingKnox.Config.danger("FleeDistance", cfg().FLEE_DIST) end
function Decisions.fleeDistAfraid() return LivingKnox.Config.danger("FleeDistanceAfraid", cfg().FLEE_DIST_AFRAID) end
function Decisions.retreatDist() return LivingKnox.Config.danger("RetreatDangerDistance", cfg().RETREAT.DIST) end
function Decisions.helpRadius() return LivingKnox.Config.danger("ReinforcementRadius", cfg().HELP.RADIUS) end
-- LK05-T16 : seuils « blessé » (option WoundedHealth, en % : santé de référence / naissance sous ce rapport) et
-- « apeuré » (option AfraidFear : peur à partir de cette valeur), employés par toutes les règles qui lisaient
-- WOUND_RATIO et NEED_HIGH.fear (inaptitude, repos, fuite apeurée, cascade de la peur ; LK_Defense, LK_Expeditions).
function Decisions.woundRatio() return LivingKnox.Config.danger("WoundedHealth", cfg().WOUND_RATIO * 100) / 100 end
function Decisions.fearHigh() return LivingKnox.Config.danger("AfraidFear", cfg().NEED_HIGH.fear) end
-- Seuil d'envie name de la cascade : peur = Decisions.fearHigh(), autres = NEED_HIGH.
function Decisions.needHigh(name)
    if name == "fear" then return Decisions.fearHigh() end
    return cfg().NEED_HIGH[name]
end
local function now() return getTimestampMs() end

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function anyOf(set, names)
    for _, n in ipairs(names) do
        if set[n] then return true end
    end
    return false
end

-- Hasard déterministe ------------------------------------------------------------------------------------------------

local function hashText(s, h)
    for i = 1, #s do
        h = (h * 31 + string.byte(s, i)) % M
    end
    return h
end

-- Flux reproductible : rnd() -> ]0, 1[, tiré de (clé texte, instant entier, sel entier). Park-Miller suivi d'un
-- mélange, sans opérateur binaire (quotients sous 2^53, exacts en Kahlua).
function Decisions.stream(key, t, salt)
    local x = (hashText(tostring(key), 7) * 7919 + (math.floor(t or 0) % M) * 31 + ((salt or 0) % M) + 1) % M
    if x == 0 then x = 1 end
    local function rnd()
        x = (x * 48271) % M
        x = (x + (x % 65521) * 31337) % M
        if x == 0 then x = 1 end
        return x / M
    end
    for _ = 1, 3 do rnd() end
    return rnd
end

local function pick(lo, hi, rnd)
    if hi <= lo then return lo end
    return math.min(hi, lo + math.floor(rnd() * (hi - lo + 1)))
end

-- Angle (degrés, 0..360) de (dx, dy) dans la convention de setDirectionAngle (y croissant = sud,
-- Directives.ANGLES) ; nil pour un vecteur nul.
function Decisions.angleTo(dx, dy)
    if dx == 0 and dy == 0 then return nil end
    local a = math.atan2(dy, dx) * 180 / math.pi
    a = math.floor(a + 0.5)
    return a - math.floor(a / 360) * 360
end

local function angleGap(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then d = 360 - d end
    return d
end

-- Horloge ----------------------------------------------------------------------------------------------------------

-- Minute de jeu courante (âge du monde en minutes, entier), ou nil si l'horloge manque.
function Decisions.currentMinute()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if not finite(hours) or hours < 0 then return nil end
    return math.floor(hours * 60 + 0.5)
end

-- Heure de jeu courante (âge du monde, entier), comme LK_Simulation.
function Decisions.currentHour()
    local minute = Decisions.currentMinute()
    if minute == nil then return nil end
    return math.floor(minute / 60)
end

-- Nuit à l'heure d'âge h : heure du jour (h + 7) % 24 (âge 0 à 7 h, base api-42-21.md) entre NIGHT_START et
-- NIGHT_END de Config.SIMULATION (même nuit que la simulation hors écran).
function Decisions.isNight(hour)
    local s = LivingKnox.Config.SIMULATION or {}
    local start, stop = s.NIGHT_START or 22, s.NIGHT_END or 6
    local hod = (hour + 7) % 24
    return hod >= start or hod < stop
end

-- Numéro de quart de garde (LK05-T03) à l'heure d'âge h : croissant, aligné sur WATCH_START (heure du jour) ;
-- les quarts de nuit (22 h-2 h, 2 h-6 h) existent chaque jour.
function Decisions.watchOf(hour)
    local c = cfg()
    return math.floor((hour + 7 + 24 - c.WATCH_START) / c.WATCH_HOURS)
end

-- Rotation des postes à l'heure d'âge h (LK05-T03, I3.1) : décalage propre au groupe + numéro de quart. Le guetteur
-- change à chaque quart, à tour de rôle parmi les membres aptes (horaires décalés, veille de nuit).
function Decisions.rotation(gidNumber, hour)
    return pick(0, 1000, Decisions.stream("duty" .. tostring(gidNumber), 0, 7)) + Decisions.watchOf(hour)
end

-- ================================================================ groupe : objectifs et postes (pur)

local function jitter(gidNumber, day, i)
    local j = cfg().JITTER
    if j <= 0 then return 0 end
    local rnd = Decisions.stream("group" .. tostring(gidNumber), day, 1000 + i)
    return pick(-j, j, rnd)
end

-- Notation des objectifs (pur). gin = { gidNumber, day, night, needs = { food, water (facultatif : stock réel,
-- LK08-T07), medical, ammo } (réserves 0..100 : LivingKnox.Stock.assessGroup, sinon besoins abstraits), rest (0..100),
-- worstWound (0..100), threats (nombre de menaces connues), fortification (0..100 ou nil), fortWork (chantier de
-- fortification faisable : vrai, faux, ou nil inconnu, LK14-T02), hostility (0..100),
-- traits = { [trait] = vrai } (chef) }. Rend { objective, score, scores = { [objectif] = entier }, why }.
function Decisions.scoreObjectives(gin)
    local c = cfg()
    local raw, factors = {}, {}
    for _, o in ipairs(Decisions.OBJECTIVES) do
        raw[o], factors[o] = 0, {}
    end
    local function add(o, v, what)
        if v == 0 then return end
        raw[o] = raw[o] + v
        if what then factors[o][#factors[o] + 1] = what end
    end
    add("settle", c.SETTLE)
    local rest = gin.rest or 50
    if gin.night then
        add("rest", c.NIGHT_REST, "night")
    elseif rest < c.REST_OK then
        add("rest", (c.REST_OK - rest) * 1.5, "rest " .. rest)
    end
    if (gin.threats or 0) > 0 then add("guard", math.min(80, gin.threats * 20), "threats " .. gin.threats) end
    local hostility = gin.hostility or 0
    if hostility > 0 then add("guard", math.floor(hostility * 0.1 + 0.5), "hostility " .. hostility) end
    local needs = gin.needs or {}
    if (needs.medical or 0) > 0 and (gin.worstWound or 0) >= c.HEAL_MIN then
        add("heal", math.floor(gin.worstWound * 0.9 + 0.5), "wound " .. gin.worstWound)
    end
    local lowest, lowKey = 100, nil
    for _, key in ipairs({ "food", "water", "medical", "ammo" }) do
        local v = needs[key]   -- water : seulement d'après le stock réel (LK08-T07), sinon ignorée
        if v == nil and key ~= "water" then v = 50 end
        if v ~= nil and v < lowest then lowest, lowKey = v, key end
    end
    if lowest < c.NEED_OK then add("supply", (c.NEED_OK - lowest) * 1.5, (lowKey or "?") .. " " .. lowest) end
    -- LK14-T02 : fortWork (LivingKnox.Fortification.hasWork) faux = aucun chantier faisable avec le stock du foyer :
    -- pas de score de fortification ; vrai : les menaces connues pressent le chantier ; nil (inconnu) : comme avant.
    if lowest >= 50 and gin.fortWork ~= false then
        local fort = gin.fortification
        local known = fort ~= nil
        if not known then fort = c.FORT_NEUTRAL end
        add("fortify", math.floor((100 - fort) * 0.5 + 0.5), (known and "fortification " or "fortification unknown ")
            .. fort)
        if gin.fortWork == true and (gin.threats or 0) > 0 and fort < 100 then
            add("fortify", math.min(c.FORT_THREAT_MAX, gin.threats * c.FORT_THREAT), "threats " .. gin.threats)
        end
    end
    local traits = gin.traits or {}
    local names = {}
    for t in pairs(traits) do names[#names + 1] = t end
    table.sort(names)
    for _, t in ipairs(names) do
        local bonus = c.TRAITS[t]
        if bonus then
            for _, o in ipairs(Decisions.OBJECTIVES) do
                if bonus[o] then add(o, bonus[o], "leader " .. t) end
            end
        end
    end
    local scores = {}
    local best, bestScore
    for i, o in ipairs(Decisions.OBJECTIVES) do
        local s = clamp(math.floor(raw[o] + 0.5) + jitter(gin.gidNumber or 0, gin.day or 0, i), 0, 100)
        scores[o] = s
        if best == nil or s > bestScore then best, bestScore = o, s end
    end
    local second, secondScore
    for _, o in ipairs(Decisions.OBJECTIVES) do
        if o ~= best and (second == nil or scores[o] > secondScore) then second, secondScore = o, scores[o] end
    end
    local why = best .. " " .. bestScore
    if #factors[best] > 0 then why = why .. " (" .. table.concat(factors[best], ", ") .. ")" end
    if second then why = why .. " > " .. second .. " " .. secondScore end
    return { objective = best, score = bestScore, scores = scores, why = why }
end

local function eligible(member, duty)
    if member.refuses ~= nil and member.refuses[duty] then return false end   -- E10-T03 : poste refusé
    local need = Decisions.DUTY_NEEDS[duty]
    return need == nil or anyOf(member.allowed or {}, need)
end

-- Postes (pur). members = { { mid, number, allowed = { [comportement] = vrai }, wound (0..100) }, ... } (ordre
-- quelconque), objective, night, rotation = entier >= 0. Rend { [mid] = poste }.
function Decisions.assignDuties(members, objective, night, rotation)
    local c = cfg()
    local list = {}
    for _, m in ipairs(members) do list[#list + 1] = m end
    table.sort(list, function(a, b) return a.number < b.number end)
    local n = #list
    local out = {}
    local able = {}
    for _, m in ipairs(list) do
        if (m.wound or 0) >= c.WOUND_DUTY then out[m.mid] = "rest" else able[#able + 1] = m end
    end
    -- Rotation : la liste des valides commence au rang rotation % nombre (relève de jour en jour).
    local k = #able
    local rotated = {}
    for i = 1, k do rotated[i] = able[((i - 1 + (rotation or 0)) % k) + 1] end
    local function take(duty, count)
        local got = 0
        for _, m in ipairs(rotated) do
            if got >= count then return end
            if out[m.mid] == nil and eligible(m, duty) then
                out[m.mid] = duty
                got = got + 1
            end
        end
    end
    local sentries = 1
    if objective == "guard" then sentries = math.floor((n + 1) / 2) end
    take("sentry", sentries)
    if objective == "heal" then take("carer", k) end
    if objective == "supply" then take("forager", math.max(1, math.floor(n / 2))) end
    if objective == "fortify" then take("builder", math.max(1, math.floor(n / 2))) end
    local rest = objective == "rest" or (night and objective ~= "guard")
    for _, m in ipairs(rotated) do
        if out[m.mid] == nil then out[m.mid] = rest and "rest" or "keeper" end
    end
    return out
end

-- ================================================================ membre : cascade (pur)

-- Vrai si le comportement b est permis au membre (ctx.allowed : comportements de son rôle ; ctx.combatant).
function Decisions.allows(ctx, b)
    local def = Decisions.BEHAVIOURS[b]
    if def == nil then return false end
    if def.needs and not anyOf(ctx.allowed or {}, def.needs) then return false end
    if def.nonCombatant and ctx.combatant then return false end
    return true
end

local function atHomeOr(ctx, b)
    if ctx.home ~= nil and not ctx.atHome then return "home" end
    return b
end

-- LK06-T05 ----------------------------------------------------------------------------------------------------------

-- Fuite pondérée (pur, I6.5) : angle (degrés) d'éloignement depuis (x, y), somme des directions opposées aux menaces
-- (fuite permise, à RETREAT.WEIGH_DIST cases au plus), chacune pesée par l'inverse de sa distance (la plus proche
-- compte le plus) ; sans menace retenue : à l'opposé de src ({ x, y }) ; nil si rien ne donne de direction.
function Decisions.fleeAngle(x, y, threats, src)
    local sx, sy, n = 0, 0, 0
    for _, t in ipairs(threats or {}) do
        if t.flee and (t.d or 0) <= cfg().RETREAT.WEIGH_DIST then
            local dx, dy = x - (t.x + 0.5), y - (t.y + 0.5)
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
                local w = 1 / math.max(len, 1)
                sx, sy, n = sx + dx / len * w, sy + dy / len * w, n + 1
            end
        end
    end
    if n == 0 and src ~= nil then return Decisions.angleTo(x - (src.x + 0.5), y - (src.y + 0.5)) end
    if math.abs(sx) < 1e-6 and math.abs(sy) < 1e-6 then return nil end
    return Decisions.angleTo(sx, sy)
end

-- Position d'un joueur de compte u pour le membre (pur) : perçu (ctx.seen), sinon lieu de l'agresseur du dernier coup
-- reçu (ctx.hit, même compte). Rend { x, y, d } ou nil.
function Decisions.playerSpot(ctx, u)
    local e = (ctx.seen or {})[u]
    if e ~= nil then return e end
    local hit = ctx.hit
    if hit == nil or hit.u ~= u or hit.x == nil then return nil end
    local dx, dy = hit.x + 0.5 - ctx.x, hit.y + 0.5 - ctx.y
    return { x = hit.x, y = hit.y, d = math.floor(math.sqrt(dx * dx + dy * dy) * 10 + 0.5) / 10 }
end

-- Reddition (pur) : compte du joueur auquel le membre se rend, raison ; ou nil. Entrées : ctx.canSurrender
-- (non-combattant d'un groupe qui ne tire pas le premier), ctx.seen ({ [compte] = { x, y, z, d } } joueurs perçus),
-- ctx.surrendered (reddition en cours de ce membre { u, last = dernière minute où le joueur était perçu à KEEP
-- cases }), ctx.betrayed ({ [compte] = vrai }), ctx.hit (dernier
-- coup reçu { u = compte d'un joueur ou nil }), ctx.health, ctx.threats.
function Decisions.surrenderTo(ctx)
    if not ctx.canSurrender then return nil end
    local c = cfg().SURRENDER
    local seen, betrayed = ctx.seen or {}, ctx.betrayed or {}
    local cur = ctx.surrendered
    if cur ~= nil and not betrayed[cur.u] then
        local e = seen[cur.u]
        if e ~= nil and e.d <= c.KEEP then return cur.u, string.format("still surrendering to %s at %.1f", cur.u, e.d) end
        if (ctx.minute or 0) - (cur.last or 0) <= c.LINGER then
            return cur.u, string.format("still surrendering to %s (out of sight)", cur.u)
        end
    end
    local hit = ctx.hit
    if hit ~= nil and hit.u ~= nil and not betrayed[hit.u] then
        local e = Decisions.playerSpot(ctx, hit.u)   -- perçu, sinon lieu du coup reçu
        if e ~= nil and e.d <= c.KEEP and (ctx.health or 1) < c.HEALTH then
            return hit.u, string.format("hit by %s at %.1f, health %d%%", hit.u, e.d,
                math.floor((ctx.health or 1) * 100 + 0.5))
        end
    end
    for _, t in ipairs(ctx.threats or {}) do
        if t.kind == "player" and t.flee and t.seen and t.d <= c.DIST and not betrayed[t.label] then
            return t.label, string.format("cornered by %s at %.1f", t.label, t.d)
        end
    end
    return nil
end

-- LK06-T07 (décision du 2026-10-12 : « tout le monde se bat ») : constantes mauvaises d'un membre (pur), quel que
-- soit son rôle : santé de référence sous Decisions.woundRatio() ou peur >= Decisions.fearHigh() (LK05-T16 : options
-- WoundedHealth et AfraidFear, relues à chaque appel). Rend la raison, ou nil (membre valide : il se bat contre un
-- zombie à portée, ne fuit pas et ne s'abrite pas).
function Decisions.unfitOf(ctx)
    local ratio = Decisions.woundRatio()
    if ctx.health ~= nil and ctx.health < ratio then
        return string.format("health %d%% < %d%%", math.floor(ctx.health * 100 + 0.5), math.floor(ratio * 100 + 0.5))
    end
    local fear, high = (ctx.needs or {}).fear or 0, Decisions.fearHigh()
    if fear >= high then
        return string.format("fear %d >= %d", math.floor(fear), high)
    end
    return nil
end

-- Rapport de repli hors de la défense : option DefenseWithdrawRatio (LivingKnox.Defense.ratios), sinon OVERWHELM.RATIO.
function Decisions.overwhelmRatio()
    local Df = LivingKnox.Defense
    if Df ~= nil and Df.ratios ~= nil then return (Df.ratios()) end
    return LivingKnox.Config.danger("DefenseWithdrawRatio", cfg().OVERWHELM.RATIO)
end

-- Poids des menaces perçues qui mettent en danger (pur) : menaces à fuir à RETREAT.DIST cases au plus ; zombie 1,
-- joueur hostile OVERWHELM.HOSTILE_WEIGHT.
function Decisions.threatWeight(threats)
    local w = 0
    local dist = Decisions.retreatDist()
    for _, t in ipairs(threats or {}) do
        if t.flee and (t.d or 0) <= dist then
            w = w + (t.kind == "player" and cfg().OVERWHELM.HOSTILE_WEIGHT or 1)
        end
    end
    return w
end

-- Groupe débordé (pur) : menace pondérée weight contre able membres valides ; before = le membre se repliait déjà
-- parce que débordé (hystérésis : il reste replié tant que menace > (rapport - 1) x valides). Rend la raison ou nil.
function Decisions.overwhelmedOf(weight, able, before)
    if weight == nil or weight <= 0 then return nil end
    local ratio = Decisions.overwhelmRatio()
    if able <= 0 then return string.format("overwhelmed: threat %d, no able member", weight) end
    local limit = before and (ratio - 1) or ratio
    if weight > limit * able then
        return string.format("overwhelmed: threat %d > %d x %d able member(s)", weight, limit, able)
    end
    return nil
end

-- Retraite (pur) : raison si le membre en danger doit se retirer, ou nil. Danger : cible d'attaque (ctx.target), coup
-- reçu récent (ctx.hit) ou menace à fuir à RETREAT.DIST cases. Blessé : santé < HEALTH ; à bout de nerfs : peur >=
-- FEAR (tout rôle depuis LK06-T07) ; moral du groupe (ctx.morale) sous LOW_MORALE : santé limite relevée, peur limite
-- abaissée. LK06-T07 : groupe débordé (ctx.overwhelmed, hors de la défense du foyer qui fait son propre repli). Au
-- foyer, seul un membre à bout de nerfs ou débordé sans défense se retire (il se terre) ; un blessé au foyer passe
-- par la défense (abri) ou la règle de fuite.
function Decisions.retreatOf(ctx)
    local c = cfg().RETREAT
    local t = ctx.threat
    local danger = ctx.target ~= nil or ctx.hit ~= nil or (t ~= nil and t.flee and t.d <= Decisions.retreatDist())
    if not danger then return nil end
    local low = ctx.morale ~= nil and ctx.morale < c.LOW_MORALE
    local hpLimit = c.HEALTH + (low and c.MORALE_HEALTH or 0)
    local fearLimit = c.FEAR - (low and c.MORALE_FEAR or 0)
    local fear = (ctx.needs or {}).fear or 0
    local wounded = ctx.health ~= nil and ctx.health < hpLimit
    local broken = fear >= fearLimit
    local over = ctx.overwhelmed
    if over ~= nil and ctx.defense ~= nil then over = nil end   -- défense du foyer : repli collectif de LK_Defense
    if not wounded and not broken and over == nil then return nil end
    if ctx.home ~= nil and ctx.atHome and not broken and (over == nil or wounded) then return nil end
    local why
    if wounded then
        why = string.format("health %d%% < %d%%", math.floor(ctx.health * 100 + 0.5), math.floor(hpLimit * 100 + 0.5))
    elseif broken then
        why = string.format("fear %d >= %d", math.floor(fear), math.floor(fearLimit))
    else
        why = over
    end
    if low then why = why .. ", group morale " .. ctx.morale end
    local onlyOver = not wounded and not broken   -- second retour : repli du seul débordement (hystérésis)
    if ctx.home ~= nil and not ctx.atHome then return why .. ", back home", onlyOver end
    if ctx.home == nil then return why .. ", fleeing", onlyOver end
    return why .. ", hiding at home", onlyOver
end

local RULES = {}

function RULES.threat(ctx)
    -- LK06-T05 : reddition, puis retraite, avant tout combat.
    local su, swhy = Decisions.surrenderTo(ctx)
    if su ~= nil then return "surrender", swhy, "p" .. su end
    local rwhy, onlyOver = Decisions.retreatOf(ctx)
    if rwhy ~= nil then return "retreat", rwhy, onlyOver and "overwhelmed" or "retreat" end
    -- LK05-T09 : défense du foyer (LivingKnox.Defense.contextFor) : place, cible depuis la place, avant le combat libre.
    local dv = ctx.defense
    -- LK11-T02 : sommation (LivingKnox.Encounters.contextFor), sans cible d'attaque ni cible de défense.
    local wn = ctx.warn
    if wn ~= nil and ctx.target == nil and (dv == nil or dv.target == nil) and Decisions.allows(ctx, "warn") then
        return "warn", wn.why, wn.key
    end
    if dv ~= nil then return "defend", dv.why, dv.key end
    -- LK06-T02 : cible d'attaque retenue par Hostility.chooseTarget (ctx.target) : un combattant engage la mêlée.
    -- LK06-T07 : tout membre valide (constantes bonnes, Decisions.unfitOf) se bat contre un zombie à portée, quel que
    -- soit son rôle ; un joueur reste la cible des seuls rôles qui permettent fight ou defend.
    local unfit = Decisions.unfitOf(ctx)
    local tg = ctx.target
    if tg ~= nil and unfit == nil then
        if tg.kind == "zombie" then   -- LK06-T04 : zombie proche à repousser (LivingKnox.Zombies.targetFor)
            return "fight", string.format("fight zombie %s at %.1f", tg.u, tg.d or 0), tg.u
        end
        if anyOf(ctx.allowed or {}, Decisions.COMBAT_BEHAVIOURS) then
            return "fight", string.format("attack player %s at %.1f (%s)", tg.u, tg.d or 0, tostring(tg.reason)),
                "p" .. tg.u
        end
    elseif tg ~= nil then
        -- Constantes mauvaises devant une cible : retraite (abri au foyer, retour au foyer, fuite pondérée sans foyer).
        local where = ", hiding at home"
        if ctx.home == nil then where = ", fleeing" elseif not ctx.atHome then where = ", back home" end
        return "retreat", string.format("%s %s at %.1f, %s%s", tg.kind == "zombie" and "zombie" or "player", tg.u,
            tg.d or 0, unfit, where), "retreat"
    end
    local t = ctx.threat
    if t == nil then
        -- LK05-T08 : alerte du groupe sans menace perçue par ce membre : dernière position connue partagée.
        local al = ctx.alert
        if al == nil then return nil end
        return "alert", string.format("group alert %s: %s %s last seen at %d,%d,%d (%.1f away, level %d)", al.id,
            al.kind, al.label, al.x, al.y, al.z, al.d, al.level), al.key
    end
    local what = string.format("%s %s at %.1f (%s)", t.kind, t.label or t.key, t.d, t.seen and "seen" or "heard")
    local afraid = ((ctx.needs or {}).fear or 0) >= Decisions.fearHigh()
    local flee = Decisions.fleeDist()
    if t.flee and (t.d <= flee or (afraid and t.d <= Decisions.fleeDistAfraid())) then
        -- LK06-T07 : fuite (ou abri au foyer) seulement aux constantes mauvaises ; un membre valide tient.
        if unfit ~= nil then
            if ctx.home ~= nil and ctx.atHome then
                return "retreat", what .. ", " .. unfit .. ", hiding at home", "retreat"
            end
            return "flee", what .. (t.d <= flee and ", too close, " or ", afraid, ") .. unfit, t.key
        end
        if t.d <= flee then return "watch", what .. ", too close, able member holds", t.key end
    end
    return "watch", what, t.key
end

local function needRule(name, behaviour)
    return function(ctx)
        local v = (ctx.needs or {})[name] or 0
        if v < Decisions.needHigh(name) then return nil end
        if ctx.unfed ~= nil and ctx.unfed[name] then return nil end   -- LK05-T07 : rien à prendre, repas récent
        if (ctx.trip ~= nil or ctx.hunt ~= nil) and name ~= "fear" then return nil end   -- LK05-T05, LK11-T05 : au retour
        return atHomeOr(ctx, behaviour), name .. " " .. v, name
    end
end

-- Peur (LK05-T06) : un membre apeuré fuit la source récente de sa peur si elle est proche (aucune menace perçue :
-- la règle threat passe avant) ; sinon il se met à l'abri au foyer. LK06-T07 : tout rôle (la peur élevée est une
-- constante mauvaise), et non plus les seuls non-combattants.
local fearAtHome = needRule("fear", "rest")
function RULES.fear(ctx)
    local b, why, key = fearAtHome(ctx)
    if b == nil then return nil end
    local src = ctx.fearFrom
    if src ~= nil and Decisions.allows(ctx, "flee") then
        local d = math.max(math.abs(src.x + 0.5 - ctx.x), math.abs(src.y + 0.5 - ctx.y))
        if d <= Decisions.fleeDistAfraid() then
            return "flee", string.format("%s, fleeing what scared it (%.1f away)", why, d), key
        end
    end
    return b, why, key
end
-- Faim, soif : repas réel au foyer (LK05-T07, routine « meal » de LK_Routines, ctx.meals) ; sans elle : au foyer.
local hungerHome, thirstHome = needRule("hunger", "home"), needRule("thirst", "home")
local hungerMeal, thirstMeal = needRule("hunger", "meal"), needRule("thirst", "meal")
function RULES.hunger(ctx) return (ctx.meals and hungerMeal or hungerHome)(ctx) end
function RULES.thirst(ctx) return (ctx.meals and thirstMeal or thirstHome)(ctx) end
RULES.fatigue = needRule("fatigue", "sleep")

function RULES.wound(ctx)
    if ctx.health == nil or ctx.health >= Decisions.woundRatio() then return nil end
    return atHomeOr(ctx, "rest"), string.format("health %d%%", math.floor(ctx.health * 100 + 0.5)), "wound"
end

function RULES.duty(ctx)
    -- LK05-T05 : membre de l'équipe d'une expédition en cours (LivingKnox.Expeditions.memberTrip), quel que soit son
    -- poste actuel ; une nouvelle expédition (autre numéro) interrompt l'état.
    local tr = ctx.trip
    if tr ~= nil then return "expedition", "expedition " .. tr.n .. " " .. tr.phase, "trip" .. tr.n end
    local hu = ctx.hunt   -- LK11-T05 : membre de l'équipe d'une vengeance en traque ou au retour (LivingKnox.Relations)
    if hu ~= nil then   -- LK11-T07 : même comportement pour un raid (kind "raid", LivingKnox.Raids)
        local kind = hu.kind or "revenge"
        return "revenge", kind .. " " .. hu.n .. " " .. hu.phase, (kind == "raid" and "raid" or "hunt") .. hu.n
    end
    local d = ctx.duty
    if d == nil then return nil end
    local why = "duty " .. d .. " (objective " .. tostring(ctx.objective) .. ")"
    if d == "sentry" then
        if not Decisions.allows(ctx, "guard") then return nil end
        -- LK05-T03 : poste de guet ou ronde selon l'heure (LivingKnox.Routines.sentryKind), poste par défaut.
        local kind = ctx.sentryKind == "patrol" and "patrol" or "guard"
        return atHomeOr(ctx, kind), why, d
    end
    if d == "rest" then return atHomeOr(ctx, ctx.night and "sleep" or "rest"), why, d end
    -- keeper, carer, forager, builder : corvées au foyer de jour (LK05-T04, routines chargées), sinon au foyer
    -- (expéditions LK05-T05, fortification LK14).
    -- Comme « home » : loin du foyer, la corvée commence par le retour (Decisions.apply), sans interrompre l'état.
    if ctx.chores and not ctx.night then return "chore", why, d end
    return "home", why, d
end

function RULES.routine(ctx)
    if ctx.chores and not ctx.night then return "chore", "routine", "routine" end
    return atHomeOr(ctx, ctx.night and "rest" or "home"), "routine", "routine"
end

-- Décision d'un membre (pur) : ctx = { id, role, allowed, combatant, x, y, z, home, atHome, threat (menace la plus
-- proche ou nil), alert (alerte du groupe qui le concerne, Alert.forMember, LK05-T08, ou nil), needs, fearFrom
-- (source récente de la peur { x, y, z } ou nil, LK05-T06), health (0..1 ou nil), duty, objective, night, minute,
-- meals (vrai si les repas réels de LK05-T07 sont chargés), unfed (besoins mis de côté { hunger, thirst } ou nil),
-- sentryKind ("guard" ou "patrol", LK05-T03 ; absent = "guard"), chores (vrai si les corvées de LK05-T04 sont
-- chargées) }. Rend { b, p (rang de la règle), rule, why, key, start, untilMin, angle (guet
-- ou menace), away (fuite : angle d'éloignement) }.
function Decisions.decide(ctx)
    for i, rule in ipairs(Decisions.PRIORITIES) do
        local b, why, key = RULES[rule](ctx)
        if b ~= nil and Decisions.allows(ctx, b) then
            local rnd = Decisions.stream(ctx.id, ctx.minute or 0, i)
            local span = cfg().MINUTES[b] or { 5, 5 }
            local out = { b = b, p = i, rule = rule, why = why, key = key, start = ctx.minute or 0 }
            out.untilMin = out.start + pick(span[1], span[2], rnd)
            local t = ctx.threat
            if b == "watch" and t then
                out.angle = Decisions.angleTo(t.x + 0.5 - ctx.x, t.y + 0.5 - ctx.y)
            elseif b == "alert" and ctx.alert then
                out.angle = Decisions.angleTo(ctx.alert.x + 0.5 - ctx.x, ctx.alert.y + 0.5 - ctx.y)
            elseif (b == "flee" or b == "retreat") and (t or ctx.fearFrom) then
                local src = t or ctx.fearFrom   -- menace perçue, sinon source récente de la peur (LK05-T06)
                -- LK06-T05 : fuite pondérée par la proximité de toutes les menaces perçues (I6.5).
                out.away = Decisions.fleeAngle(ctx.x, ctx.y, ctx.threats or { t }, src) or pick(0, 7, rnd) * 45
                out.side = rnd() < 0.5 and -1 or 1
                if b == "retreat" and t then out.angle = Decisions.angleTo(t.x + 0.5 - ctx.x, t.y + 0.5 - ctx.y) end
            elseif b == "surrender" then
                local e = Decisions.playerSpot(ctx, string.sub(key or "", 2))   -- clé "p<compte>"
                if e ~= nil then out.angle = Decisions.angleTo(e.x + 0.5 - ctx.x, e.y + 0.5 - ctx.y) end
                out.u = string.sub(key or "", 2)
            elseif b == "guard" then
                -- Regard vers l'extérieur du foyer (sinon direction tirée), décalé de -45, 0 ou +45 degrés.
                local base
                if ctx.home then base = Decisions.angleTo(ctx.x - (ctx.home.x + 0.5), ctx.y - (ctx.home.y + 0.5)) end
                if base == nil then base = pick(0, 7, rnd) * 45 end
                local a = base + (pick(0, 2, rnd) - 1) * 45
                out.angle = a - math.floor(a / 360) * 360
            end
            return out
        end
    end
    return nil   -- inaccessible : la routine est toujours permise
end

-- Vrai si la décision out remplace l'état st : aucun état, échéance atteinte, ou interruption (autre règle, autre
-- comportement, autre cible).
function Decisions.replaces(st, out, minute)
    if st == nil then return true, "new" end
    if out.p ~= st.p or out.b ~= st.b or out.key ~= st.key then return true, "interrupted" end
    if minute >= st.untilMin then return true, "deadline" end
    return false
end

-- ================================================================ entrées (autorité)

-- Besoins individuels (LK05-T06, LK_Needs.lua) : LivingKnox.Needs.get(gid, mid) -> { hunger, thirst, fatigue, fear }
-- (0..100). Module absent ou valeur invalide : neutre (0).
function Decisions.needsOf(gid, mid)
    local out = {}
    local N = LivingKnox.Needs
    local got = N ~= nil and N.get ~= nil and N.get(gid, mid) or nil
    for _, key in ipairs(Decisions.NEEDS) do
        local v = type(got) == "table" and got[key] or nil
        out[key] = finite(v) and clamp(math.floor(v + 0.5), 0, 100) or 0
    end
    return out
end

-- Interface de la fortification du foyer (LK14) : LivingKnox.Fortification.levelOf(gid) -> 0..100, sinon nil.
function Decisions.fortificationOf(gid)
    local F = LivingKnox.Fortification
    local v = F ~= nil and F.levelOf ~= nil and F.levelOf(gid) or nil
    if finite(v) then return clamp(v, 0, 100) end
    return nil
end

-- LK14-T02 : chantier de fortification faisable (LivingKnox.Fortification.hasWork(gid)) : vrai, faux, ou nil.
function Decisions.fortifyWorkOf(gid)
    local F = LivingKnox.Fortification
    if F == nil or F.hasWork == nil then return nil end
    local v = F.hasWork(gid)
    if v == true or v == false then return v end
    return nil
end

-- Santé d'un membre (0..1) : référence du corps (LK_Health) pour un membre incarné, sinon blessure abstraite.
function Decisions.healthOf(m)
    local H = LivingKnox.Health
    if m.npc ~= nil and H ~= nil and H.get ~= nil then
        local h = H.get(m.npc)
        if h ~= nil and finite(h.hp) and finite(h.max) and h.max > 0 then return clamp(h.hp / h.max, 0, 1) end
    end
    return clamp(1 - (m.wound or 0) / 100, 0, 1)
end

local function isEmbodied(m, registry)
    if m.npc == nil or registry == nil or type(registry.npcs) ~= "table" then return false end
    local npc = registry.npcs[m.npc]
    return npc ~= nil and npc.state == "embodied"
end

local function registryOfBodies()
    local S = LivingKnox.Store
    if S == nil or S.isReady == nil or not S.isReady() then return nil end
    return S.data()
end

-- Comportements permis par le rôle du membre dans son type de groupe (copie en ensemble).
function Decisions.allowedOf(groupType, role)
    local out = {}
    local def = LivingKnox.GroupTypes.peek(groupType)   -- LK13-T11 : lecture en place (rien n'est écrit ni gardé)
    local r = def and def.roles and def.roles[role] or nil
    for _, b in ipairs(r and r.behaviours or {}) do out[b] = true end
    return out
end

-- Menaces connues d'un groupe : menaces distinctes vues ces THREAT_HOURS dernières heures (mémoire).
function Decisions.knownThreats(gid, hour)
    local per = Decisions.state.threats[gid]
    if per == nil then return 0 end
    local n = 0
    for h, keys in pairs(per) do
        if h > hour - cfg().THREAT_HOURS and h <= hour then n = n + keys.n end
    end
    return n
end

local function noteThreat(gid, key, hour)
    local st = Decisions.state.threats
    st[gid] = st[gid] or {}
    local per = st[gid]
    local old = {}
    for h in pairs(per) do
        if h <= hour - cfg().THREAT_HOURS then old[#old + 1] = h end
    end
    for _, h in ipairs(old) do per[h] = nil end
    per[hour] = per[hour] or { n = 0, keys = {} }
    local slot = per[hour]
    if slot.keys[key] or slot.n >= cfg().THREAT_KEYS then return end
    slot.keys[key] = true
    slot.n = slot.n + 1
end

-- Entrée de notation d'un groupe vivant (registre) à l'heure hour.
function Decisions.groupInput(gid, g, hour)
    local G = Groups()
    local away = {}
    if type(g.expedition) == "table" and type(g.expedition.team) == "table" then
        for _, mid in ipairs(g.expedition.team) do away[mid] = true end
    end
    local members, worst = {}, 0
    for mid, m in pairs(g.members) do
        if m.alive and not away[mid] then
            local wound = math.floor((1 - Decisions.healthOf(m)) * 100 + 0.5)
            if wound > worst then worst = wound end
            members[#members + 1] = { mid = mid, number = G.memberNumber(mid) or 0, wound = wound,
                allowed = Decisions.allowedOf(g.type, m.role) }
        end
    end
    local traits = {}
    local leader = g.leader and g.members[g.leader] or nil
    if leader and type(leader.traits) == "table" then
        for _, t in ipairs(leader.traits) do traits[t] = true end
    end
    local def = LivingKnox.GroupTypes.peek(g.type)   -- LK13-T11 : lecture en place (hostilité seule)
    local needs = { food = g.needs.food, medical = g.needs.medical, ammo = g.needs.ammo }
    local St = LivingKnox.Stock   -- LK08-T07 : niveaux du stock réel du foyer quand sa référence existe
    local stock = St ~= nil and St.assessGroup ~= nil and St.assessGroup(g) or nil
    if stock ~= nil then
        needs = { food = stock.levels.food, water = stock.levels.water, medical = stock.levels.medical,
            ammo = stock.levels.ammo }
    end
    return { gidNumber = G.idNumber(gid) or 0, day = math.floor(hour / 24) + 1, night = Decisions.isNight(hour),
        needs = needs, rest = g.rest,
        worstWound = worst, threats = Decisions.knownThreats(gid, hour), fortification = Decisions.fortificationOf(gid),
        fortWork = Decisions.fortifyWorkOf(gid),
        hostility = def and def.hostility or 0, traits = traits, members = members }
end

-- Notation d'un groupe vivant (registre) : objectif, postes, journal si changement. Rend vrai si le registre change.
function Decisions.scoreGroup(gid, g, hour)
    local gin = Decisions.groupInput(gid, g, hour)
    if #gin.members == 0 then return false end
    local result = Decisions.scoreObjectives(gin)
    local duties = Decisions.assignDuties(gin.members, result.objective, gin.night,
        Decisions.rotation(gin.gidNumber, hour))
    for _ = 1, #gin.members do   -- E10-T03 : guet refusé, postes refaits ; le nouveau guetteur est jugé à son tour
        if not Decisions.refuseDuties(gid, g, gin.members, duties, hour) then break end
        duties = Decisions.assignDuties(gin.members, result.objective, gin.night, Decisions.rotation(gin.gidNumber, hour))
    end
    Decisions.state.scored[gid] = hour
    Decisions.stats.scored = Decisions.stats.scored + 1
    local changed = g.objective ~= result.objective
    for _, m in ipairs(gin.members) do
        if g.members[m.mid].duty ~= duties[m.mid] then changed = true end
    end
    if not changed then return false end
    -- Changement prévu par l'horloge seule (LK05-T03 : relève d'un quart, tombée de la nuit, aube) : même objectif et
    -- postes gardés = ceux de l'heure précédente ; journal du moteur seulement (pas de journal du groupe à chaque quart).
    local scheduled = false
    if g.objective == result.objective and hour > 0 then
        local before = Decisions.assignDuties(gin.members, result.objective, Decisions.isNight(hour - 1),
            Decisions.rotation(gin.gidNumber, hour - 1))
        scheduled = true
        for _, m in ipairs(gin.members) do
            if g.members[m.mid].duty ~= before[m.mid] then scheduled = false end
        end
    end
    g.objective = result.objective
    local byDuty, order = {}, {}
    for _, m in ipairs(gin.members) do
        local d = duties[m.mid]
        g.members[m.mid].duty = d
        if byDuty[d] == nil then
            byDuty[d] = {}
            order[#order + 1] = d
        end
        byDuty[d][#byDuty[d] + 1] = m
    end
    table.sort(order, function(a, b)
        local ia, ib = 0, 0
        for i, d in ipairs(Decisions.DUTIES) do
            if d == a then ia = i end
            if d == b then ib = i end
        end
        return ia < ib
    end)
    local parts = {}
    for _, d in ipairs(order) do
        local list = byDuty[d]
        table.sort(list, function(a, b) return a.number < b.number end)
        local ids = {}
        for i, m in ipairs(list) do ids[i] = m.mid end
        parts[#parts + 1] = d .. " " .. table.concat(ids, " ")
    end
    local G = Groups()
    local text = result.why .. "; " .. table.concat(parts, ", ")
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then
        Ac.note(gid, nil, "objective", (scheduled and ("watch " .. Decisions.watchOf(hour) .. ": ") or "") .. text)
    end
    if scheduled then
        Decisions.stats.watchChanges = Decisions.stats.watchChanges + 1
        log().info("group %s watch %d (hour of day %d): %s", gid, Decisions.watchOf(hour), (hour + 7) % 24,
            table.concat(parts, ", "))
        return true
    end
    G.appendLog(g, "objective", string.sub(text, 1, G.TEXT_MAX), gin.day)
    Decisions.stats.objectiveChanges = Decisions.stats.objectiveChanges + 1
    log().info("group %s objective: %s", gid, text)
    return true
end

-- Groupe matérialisé : au moins un membre vivant incarné.
function Decisions.materialized(g, registry)
    for _, m in pairs(g.members) do
        if m.alive and isEmbodied(m, registry) then return true end
    end
    return false
end

-- Notation de tous les groupes matérialisés à l'heure hour (défaut : heure courante), ou du seul groupe only.
-- Une sauvegarde si un objectif ou un poste change. Rend le nombre de groupes notés.
function Decisions.scorePass(hour, only)
    if not LivingKnox.isAuthority() then return 0 end
    hour = hour or Decisions.currentHour()
    if hour == nil then return 0 end
    local G = Groups()
    if not G.ensure() then return 0 end
    local registry = registryOfBodies()
    local count = 0
    G.update(function(data)
        local changed = false
        local ids = {}
        for gid in pairs(data.groups) do ids[#ids + 1] = gid end
        table.sort(ids)
        for _, gid in ipairs(ids) do
            local g = data.groups[gid]
            if (only == nil or only == gid) and Decisions.materialized(g, registry) then
                count = count + 1
                if Decisions.scoreGroup(gid, g, hour) then changed = true end
            end
        end
        return changed, true
    end)
    Decisions.flushRefusals()   -- E10-T03 : refus du guet annoncés hors de l'écriture du registre
    return count
end

-- hour : heure de jeu lue à l'EveryHours (LK13-T09, file du pas horaire de LK_Simulation) ; nil = heure courante.
-- LK13-T11 : notation étalée : les groupes (ordre trié, comme scorePass) sont notés un par image à partir de l'image
-- suivante (Decisions.tick), chacun avec cette heure ; un groupe non matérialisé est passé sans coût dans la même
-- image. Écriture du registre retenue jusqu'à la fin (Groups.hold("decisions")). Une heure nouvelle, OnSave et
-- Simulation.finishHour font d'abord les notations restantes (Decisions.finishHourQueue).
Decisions.hourQueue = Decisions.hourQueue or { list = {}, head = 1, hour = nil, fresh = false }
Decisions.HOUR_HOLD_MARGIN = 3

function Decisions.onEveryHours(hour)
    if not LivingKnox.Config.isEnabled() then return end
    Decisions.finishHourQueue()
    hour = hour or Decisions.currentHour()
    local G = Groups()
    if hour == nil or not G.ensure() then return end
    local ids = {}
    for gid in pairs(G.state.data.groups) do ids[#ids + 1] = gid end
    table.sort(ids)
    if #ids == 0 then return end
    Decisions.hourQueue = { list = ids, head = 1, hour = hour, fresh = true }
    G.hold("decisions", #ids + Decisions.HOUR_HOLD_MARGIN)
end

-- Vrai si le groupe gid sera noté pour l'heure hour par la notation horaire encore en attente : passe différée de
-- LK_Simulation pas encore faite (même heure), ou groupe encore dans la file de notation de cette heure.
function Decisions.hourScoringPending(gid, hour)
    local q = Decisions.hourQueue
    if q ~= nil and q.hour == hour and q.head <= #q.list then
        for i = q.head, #q.list do
            if q.list[i] == gid then return true end
        end
    end
    local S = LivingKnox.Simulation
    local h = S ~= nil and S.hourly or nil
    if h ~= nil and h.hour == hour and h.head <= #h.jobs then
        for i = h.head, #h.jobs do
            if h.jobs[i].name == "Decisions" then return true end
        end
    end
    return false
end

-- Une notation de la file (au plus un groupe matérialisé noté). Rend vrai si la file a avancé.
local function hourStep(all)
    local q = Decisions.hourQueue
    if q.head > #q.list then return false end
    while q.head <= #q.list do
        local gid = q.list[q.head]
        q.head = q.head + 1
        if Decisions.scorePass(q.hour, gid) > 0 and not all then break end
    end
    if q.head > #q.list then
        Decisions.hourQueue = { list = {}, head = 1, hour = nil, fresh = false }
        local G = Groups()
        G.release("decisions")
        if not all and G.isDirty() and not G.isHeld() then G.flush() end   -- une autre retenue écrira à sa fin
    end
    return true
end

-- Notations restantes tout de suite (heure nouvelle, OnSave, Simulation.finishHour, bancs).
function Decisions.finishHourQueue()
    local q = Decisions.hourQueue
    if q == nil or q.head > #q.list then return end
    q.fresh = false
    hourStep(true)
end

-- ================================================================ membres (autorité)

-- Attitude du groupe gid envers les joueurs vivants connus : { [compte] = niveau } (LK_Hostility ; sans identité de
-- personnage : niveau de départ du type).
local function attitudesFor(gid, g, players)
    local out = {}
    local Ho = LivingKnox.Hostility
    if Ho == nil then return out end
    for _, p in ipairs(players) do
        local name = p:getUsername()
        local key = Ho.keyOf and Ho.keyOf(p) or nil
        local level
        if key ~= nil then
            local view = Ho.get(gid, key)
            level = view and view.level or nil
        end
        if level == nil then level = Ho.levelOf(Ho.startFor(g.type)) end
        out[name] = level
    end
    return out
end

-- Menaces perçues (liste triée par distance puis clé) : zombies vus ou entendus ; joueurs vus ou entendus envers qui
-- le groupe est hostile (fuite permise) ou méfiant (regard seulement). Perception absente ou périmée : aucune.
-- LK05-T14 : un zombie perçu au-delà de Config.zombieAlertDistance() (option ZombieAlertDistance) est ignoré.
function Decisions.threatsOf(per, attitudes)
    local out = {}
    if per == nil or per.stale then return out end
    local zmax = LivingKnox.Config.zombieAlertDistance()
    for _, e in ipairs(per.z or {}) do
        if (e.s or e.h) and (zmax == nil or (e.d or 0) <= zmax) then
            out[#out + 1] = { kind = "zombie", key = "z" .. tostring(e.o), label = tostring(e.o), x = e.x, y = e.y,
                z = e.z, d = e.d or 0, seen = e.s, flee = true }
        end
    end
    for _, e in ipairs(per.p or {}) do
        local level = attitudes[e.u]
        if (e.s or e.h) and (level == "hostile" or level == "wary") then
            out[#out + 1] = { kind = "player", key = "p" .. e.u, label = e.u, x = e.x, y = e.y, z = e.z, d = e.d or 0,
                seen = e.s, flee = level == "hostile" }
        end
    end
    table.sort(out, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    return out
end

-- ================================================================ LK06-T05 : coups reçus, aide, reddition (autorité)

-- Tables de mémoire créées à la demande (Decisions.reset les vide toutes) : hits (npcId -> dernier coup reçu), help
-- (gid -> demande d'aide), surrenders (gid -> { [compte] = { npc, since, last (reddition revue), seen (joueur perçu à
-- SURRENDER.KEEP cases) } }), betrayed (gid -> { [compte] =
-- minute de la rupture }).
local function bucket(name)
    local st = Decisions.state
    st[name] = st[name] or {}
    return st[name]
end

local function playerName(p)
    if p == nil or p.getUsername == nil then return nil end
    return tostring(p:getUsername())
end

local function cheb(x1, y1, x2, y2) return math.max(math.abs(x1 - x2), math.abs(y1 - y2)) end

-- Groupe et membre vivant du PNJ id (état de la cascade, sinon registre) : gid, mid, g, m ; ou nil.
local function memberOf(id)
    local G = Groups()
    local data = G ~= nil and G.isReady() and G.state.data or nil
    if data == nil then return nil end
    local s = Decisions.state.members[id]
    if s ~= nil and s.gid ~= nil then
        local g = data.groups[s.gid]
        local m = g and g.members[s.mid] or nil
        if m ~= nil and m.npc == id and m.alive then return s.gid, s.mid, g, m end
    end
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids)
    for _, gid in ipairs(ids) do
        local g = data.groups[gid]
        for mid, m in pairs(g.members) do
            if m.npc == id and m.alive then return gid, mid, g, m end
        end
    end
    return nil
end

-- Vrai si le groupe gid épargne le joueur de compte u : un de ses membres s'est rendu à lui (reddition en cours,
-- revue il y a SURRENDER.LINGER minutes au plus) et le joueur n'a plus frappé depuis (sinon la reddition est rompue).
function Decisions.spared(gid, u, minute)
    local per = bucket("surrenders")[gid]
    local s = per and u and per[u] or nil
    if s == nil or minute == nil then return false end
    return minute - s.last <= cfg().SURRENDER.LINGER
end

-- Demande d'aide en cours du groupe gid qui concerne un membre en (x, y, z) : même niveau que la victime, à
-- HELP.RADIUS cases au plus d'elle, posée il y a HELP.MINUTES minutes au plus. Rend la demande (table interne) ou nil.
function Decisions.helpFor(gid, x, y, z, minute)
    local h = bucket("help")[gid]
    if h == nil or minute == nil then return nil end
    local c = cfg().HELP
    if minute < h.minute or minute - h.minute > c.MINUTES then return nil end
    if h.oz ~= z or cheb(x, y, h.ox + 0.5, h.oy + 0.5) > Decisions.helpRadius() then return nil end
    return h
end

-- Appel à l'aide du membre m (mid, corps body) du groupe gid contre l'agresseur rec = { kind = "player" | "zombie",
-- u (compte), key, zombie (objet), x, y, z } : demande d'aide posée (renfort des combattants proches), alerte du
-- groupe (LK_Alert : cri si l'alerte est nouvelle ou plus grave). Rend la demande.
function Decisions.callHelp(gid, g, mid, m, body, rec, minute, why)
    local label = rec.kind == "zombie" and ("zombie " .. tostring(rec.key)) or ("player " .. tostring(rec.u))
    local h = { npc = m.npc, mid = mid, kind = rec.kind, u = rec.u, key = rec.key, zombie = rec.zombie, x = rec.x,
        y = rec.y, z = rec.z, ox = math.floor(body:getX()), oy = math.floor(body:getY()), oz = math.floor(body:getZ()),
        minute = minute, why = why }
    bucket("help")[gid] = h
    Decisions.stats.helpCalls = Decisions.stats.helpCalls + 1
    log().info("group %s: npc %s (%s) calls for help against %s at %d,%d,%d (%s)", gid, tostring(m.npc), mid, label,
        h.x, h.y, h.z, tostring(why))
    local A = LivingKnox.Alert
    if A ~= nil and A.raise ~= nil then
        local female = m.female
        if female == nil and body.isFemale ~= nil then female = body:isFemale() end
        local dx, dy = h.x + 0.5 - body:getX(), h.y + 0.5 - body:getY()
        local t = { kind = rec.kind == "zombie" and "zombie" or "hostile",
            key = "help:" .. (rec.kind == "zombie" and tostring(rec.key) or ("p:" .. tostring(rec.u))),
            label = rec.kind == "zombie" and tostring(rec.key) or tostring(rec.u), x = h.x, y = h.y, z = h.z,
            d = math.floor(math.sqrt(dx * dx + dy * dy) * 10 + 0.5) / 10, seen = true }
        A.raise(gid, t, { npc = m.npc, mid = mid, x = body:getX(), y = body:getY(), z = h.oz,
            female = female == true }, body, minute, g.home, "called by")
    end
    return h
end

-- Coup accepté sur le PNJ id (corps body) par wielder (joueur ou zombie vanilla), appelé par LivingKnox.Health.applyHit
-- (autorité). Note le coup (danger, reddition), rompt une reddition du groupe envers ce joueur, appelle à l'aide.
-- Rend vrai si le coup est noté.
function Decisions.noteHit(id, body, wielder)
    if not LivingKnox.isAuthority() or wielder == nil or body == nil then return false end
    local minute = Decisions.currentMinute()
    if minute == nil then return false end
    local gid, mid, g, m = memberOf(id)
    if gid == nil then return false end
    local rec = { minute = minute, x = math.floor(wielder:getX()), y = math.floor(wielder:getY()),
        z = math.floor(wielder:getZ()) }
    if instanceof(wielder, "IsoPlayer") then
        rec.kind, rec.u = "player", playerName(wielder)
        if rec.u == nil then return false end
    elseif instanceof(wielder, "IsoZombie") then
        local Zm = LivingKnox.Zombies
        rec.kind, rec.zombie = "zombie", wielder
        rec.key = Zm ~= nil and Zm.keyOf ~= nil and Zm.keyOf(wielder) or "z?"
    else
        return false
    end
    bucket("hits")[id] = rec
    Decisions.stats.hitsNoted = Decisions.stats.hitsNoted + 1
    local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement)
    if Ac ~= nil then Ac.note(gid, mid, "combat", "hit by " .. rec.kind .. " " .. tostring(rec.u or rec.key), id) end
    if rec.kind == "player" then
        local per = bucket("surrenders")[gid]
        local s = per and per[rec.u] or nil
        if s ~= nil then
            per[rec.u] = nil
            local b = bucket("betrayed")
            b[gid] = b[gid] or {}
            b[gid][rec.u] = minute
            Decisions.stats.surrenderBroken = Decisions.stats.surrenderBroken + 1
            log().info("group %s: %s hit npc %s after npc %s surrendered: surrender broken", gid, rec.u, id, s.npc)
            Decisions.setAlertGesture(s.npc, nil)   -- LK06-T12 : mains baissées sans attendre la décision suivante
            Decisions.announceSurrender(s.npc, "betrayed", minute)
        end
    end
    Decisions.callHelp(gid, g, mid, m, body, rec, minute, "hit")
    return true
end

-- Cible de renfort d'un combattant (contexte ctx, PNJ npc) pour la demande h : zombie vanilla encore là, même
-- niveau ; joueur présent, vivant, ni couvert (trêve, LK_Hostility.isCovered) ni épargné (reddition). Rend la cible
-- au format de Combat.targetFor (raison "help") ou nil.
function Decisions.helpTarget(gid, npc, h, ctx, players, minute)
    local tx, ty, out
    if h.kind == "zombie" then
        local z, Zm = h.zombie, LivingKnox.Zombies
        if z == nil or Zm == nil or not Zm.isVanilla(z) or not Zm.inWorld(z) then return nil end
        if math.floor(z:getZ()) ~= ctx.z then return nil end
        tx, ty = z:getX(), z:getY()
        out = { kind = "zombie", u = h.key, reason = "help", zombie = z }
    else
        if Decisions.spared(gid, h.u, minute) then return nil end
        local p = nil
        for _, q in ipairs(players or {}) do
            if playerName(q) == h.u then p = q end
        end
        if p == nil or p:isDead() then return nil end
        local Ho = LivingKnox.Hostility
        local key = Ho ~= nil and Ho.keyOf ~= nil and Ho.keyOf(p) or nil
        if key ~= nil and Ho.isCovered ~= nil and Ho.isCovered(gid, key, npc) then return nil end
        tx, ty = p:getX(), p:getY()
        out = { u = h.u, reason = "help" }
    end
    local dx, dy = tx - ctx.x, ty - ctx.y
    out.d = math.floor(math.sqrt(dx * dx + dy * dy) * 10 + 0.5) / 10
    Decisions.stats.helpTargets = Decisions.stats.helpTargets + 1
    return out
end

-- Entrées LK06-T05 du contexte : moral du groupe, coup reçu récent, joueurs perçus, reddition possible, en cours ou
-- refusée (trahison), cible épargnée (reddition), cible de renfort (demande d'aide du groupe).
function Decisions.defenceContext(ctx, gid, g, m, per, players, minute)
    ctx.morale = g.morale
    local hit = bucket("hits")[m.npc]
    if hit ~= nil and minute >= hit.minute and minute - hit.minute <= cfg().HIT_MINUTES then ctx.hit = hit end
    local seen = {}
    if per ~= nil and not per.stale then
        for _, e in ipairs(per.p or {}) do
            if (e.s or e.h) and seen[e.u] == nil then seen[e.u] = { x = e.x, y = e.y, z = e.z, d = e.d or 0 } end
        end
    end
    ctx.seen = seen
    local Ho = LivingKnox.Hostility
    ctx.canSurrender = not ctx.combatant and Ho ~= nil and Ho.firstStrike ~= nil and not Ho.firstStrike(g.type)
    local mine = Decisions.state.members[m.npc]
    local sur = bucket("surrenders")[gid]
    local cur = mine ~= nil and mine.b == "surrender" and sur ~= nil and sur[mine.u] or nil
    if cur ~= nil and cur.npc == m.npc then ctx.surrendered = { u = mine.u, last = cur.seen } end
    local betrayed = {}
    for u, at in pairs(bucket("betrayed")[gid] or {}) do
        if minute - at <= cfg().SURRENDER.BETRAYED then betrayed[u] = true end
    end
    ctx.betrayed = betrayed
    local tg = ctx.target
    if tg ~= nil and tg.kind ~= "zombie" and Decisions.spared(gid, tg.u, minute) then
        Decisions.stats.spared = Decisions.stats.spared + 1
        ctx.target = nil
        local Zm = LivingKnox.Zombies
        if Zm ~= nil and Zm.targetFor ~= nil then ctx.target = Zm.targetFor(m.npc) end
    end
    if ctx.target == nil then
        local h = Decisions.helpFor(gid, ctx.x, ctx.y, ctx.z, minute)
        -- LK06-T07 : tout membre vient en renfort contre un zombie ; contre un joueur, les seuls combattants.
        if h ~= nil and (ctx.combatant or h.kind == "zombie") then
            ctx.help = h
            ctx.target = Decisions.helpTarget(gid, m.npc, h, ctx, players, minute)
        end
    end
end

-- Suites d'une décision (evaluate) : reddition notée pour le groupe (ou close), retraite comptée ; un combattant qui
-- se retire passe sa cible aux autres (demande d'aide).
local function afterDecision(gid, g, mid, m, body, st, prev, ctx, fresh, minute)
    local id = m.npc
    local sur = bucket("surrenders")
    if prev ~= nil and prev.b == "surrender" and (st.b ~= "surrender" or st.u ~= prev.u) then
        local per = sur[gid]
        if per ~= nil and per[prev.u] ~= nil and per[prev.u].npc == id then per[prev.u] = nil end
        log().info("npc %s (%s %s): surrender to %s over", id, gid, mid, tostring(prev.u))
    end
    if st.b == "surrender" and st.u ~= nil then
        sur[gid] = sur[gid] or {}
        local s = sur[gid][st.u]
        if s == nil or s.npc ~= id then
            sur[gid][st.u] = { npc = id, since = minute, last = minute, seen = minute }
            Decisions.stats.surrenders = Decisions.stats.surrenders + 1
            log().info("npc %s (%s %s) surrenders to %s: %s", id, gid, mid, st.u, tostring(st.why))
            Decisions.announceSurrender(id, "surrender", minute)   -- LK06-T12 : une seule réplique par reddition
        else
            s.last = minute   -- reddition revue (validité de Decisions.spared)
            local e = (ctx.seen or {})[st.u]
            if e ~= nil and e.d <= cfg().SURRENDER.KEEP then s.seen = minute end   -- joueur encore perçu
        end
    end
    if fresh and st.b == "retreat" then
        Decisions.stats.retreats = Decisions.stats.retreats + 1
        log().info("npc %s (%s %s) retreats: %s", id, gid, mid, tostring(st.why))
        local tg = ctx.target
        if tg ~= nil then
            local rec
            if tg.kind == "zombie" and tg.zombie ~= nil then
                local z = tg.zombie
                rec = { kind = "zombie", key = tg.u, zombie = z, x = math.floor(z:getX()), y = math.floor(z:getY()),
                    z = math.floor(z:getZ()) }
            elseif tg.kind ~= "zombie" then
                local e = (ctx.seen or {})[tg.u]
                local p = Decisions.findPlayer(tg.u)
                local x, y, z = e and e.x, e and e.y, e and e.z
                if p ~= nil then x, y, z = p:getX(), p:getY(), p:getZ() end
                if x ~= nil then
                    rec = { kind = "player", u = tg.u, x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
                end
            end
            if rec ~= nil then Decisions.callHelp(gid, g, mid, m, body, rec, minute, "retreat") end
        end
    end
end

-- LK06-T12 (fiche docs/annexes/conception/fuite-reddition.md, « Reddition visible ») : réplique de gabarit du PNJ id, traduite
-- par chaque client (LivingKnox.Speech.say, clé IGUI_LK_Surrender_<n> à l'entrée en reddition, appelée une fois par
-- afterDecision à la création de la reddition ; IGUI_LK_Surrender_Betrayed_<n> quand le joueur la rompt, noteHit).
-- Variante tirée de (PNJ, minute) : reproductible, sans LLM. Personne à portée : journal debug seul, rien n'est redit.
-- Rend l'identifiant de la réplique, ou nil et la raison.
Decisions.SURRENDER_GESTURE = "surrender"
Decisions.SURRENDER_KEY = "IGUI_LK_Surrender_"
Decisions.SURRENDER_LINES = { surrender = { prefix = "", n = 4, salt = 1201, stat = "surrenderLines" },
    betrayed = { prefix = "Betrayed_", n = 2, salt = 1202, stat = "betrayalLines" } }
function Decisions.announceSurrender(id, kind, minute)
    local c = Decisions.SURRENDER_LINES[kind]
    local Sp = LivingKnox.Speech
    if c == nil or id == nil then return nil, "bad line" end
    if Sp == nil or Sp.say == nil then return nil, "speech not loaded" end
    local key = Decisions.SURRENDER_KEY .. c.prefix .. pick(1, c.n, Decisions.stream(id, minute or 0, c.salt))
    local out, why = Sp.say(id, { key = key })
    if out == nil then
        log().debug("npc %s: %s line not heard: %s", id, kind, tostring(why))
        return nil, why
    end
    Decisions.stats[c.stat] = Decisions.stats[c.stat] + 1
    log().info("npc %s says %s (%s)", id, key, kind)
    return out.id
end

-- Joueur de compte name (serveur : connectés ; solo : locaux), ou nil (LivingKnox.Combat.playerByName).
function Decisions.findPlayer(name)
    local C = LivingKnox.Combat
    if C ~= nil and C.playerByName ~= nil then return C.playerByName(name) end
    return nil
end

-- Perception per du membre, plus le zombie qu'il combat (cible du serveur, Zombies.targetFor) quand elle ne le porte
-- pas encore. Sur un serveur, la perception vient du rapport du propriétaire, en retard d'une seconde ou plus ; le
-- membre pouvait tuer un zombie à 3 cases avant que l'alerte du groupe ne soit levée (campagne MP du 2026-10-14). En
-- solo la perception le porte déjà : rien n'est ajouté. Rend per, ou une copie complétée.
function Decisions.withTarget(per, tg)
    if not isServer() or tg == nil or tg.zombie == nil then return per end
    local z = tg.zombie
    local o = z:getOnlineID()
    if type(o) ~= "number" or o < 0 then return per end
    for _, e in ipairs(per and per.z or {}) do
        if e.o == o then return per end
    end
    local fresh = per ~= nil and not per.stale   -- résumé périmé : seul le fait du serveur compte
    local out = { z = {}, p = fresh and per.p or {}, n = fresh and per.n or {}, stale = false }
    if fresh then
        for k, v in pairs(per) do
            if out[k] == nil then out[k] = v end
        end
        for i, e in ipairs(per.z or {}) do out.z[i] = e end
    end
    out.z[#out.z + 1] = { o = o, x = z:getX(), y = z:getY(), z = z:getZ(), a = 1, s = true, h = false, d = tg.d or 0 }
    return out
end

-- Contexte d'un membre incarné (corps body) pour Decisions.decide.
function Decisions.context(gid, g, mid, m, body, players, minute)
    local allowed = Decisions.allowedOf(g.type, m.role)
    local x, y, z = body:getX(), body:getY(), body:getZ()
    local ctx = { id = m.npc, gid = gid, mid = mid, role = m.role, allowed = allowed,
        combatant = anyOf(allowed, Decisions.COMBAT_BEHAVIOURS), x = x, y = y, z = math.floor(z), home = g.home,
        health = Decisions.healthOf(m), duty = m.duty, objective = g.objective,
        night = Decisions.isNight(math.floor(minute / 60)), minute = minute }
    local R = LivingKnox.Routines   -- LK05-T03 : postes relevés au foyer, poste de guet ou ronde selon l'heure
    if R ~= nil and R.sentryKind ~= nil then
        ctx.sentryKind = R.sentryKind(math.floor(minute / 60), R.ensurePosts(gid, g))
    end
    ctx.chores = R ~= nil and R.handles ~= nil and R.handles("chore") or nil   -- LK05-T04
    -- LK05-T07 : repas réels (routine « meal ») et besoins mis de côté (rien à prendre, repas récent).
    ctx.meals = R ~= nil and R.handles ~= nil and R.handles("meal") or nil
    if ctx.meals and R.unfed ~= nil then ctx.unfed = R.unfed(gid, mid, minute) end
    local Ex = LivingKnox.Expeditions   -- LK05-T05 : expédition en cours qui compte ce membre
    if Ex ~= nil and Ex.memberTrip ~= nil then ctx.trip = Ex.memberTrip(gid, mid) end
    local Rl = LivingKnox.Relations   -- LK11-T05 : traque d'une vengeance qui compte ce membre
    if ctx.trip == nil and Rl ~= nil and Rl.memberHunt ~= nil then ctx.hunt = Rl.memberHunt(gid, mid) end
    if ctx.home ~= nil then
        ctx.homeDist = math.max(math.abs(x - (ctx.home.x + 0.5)), math.abs(y - (ctx.home.y + 0.5)))
        ctx.atHome = ctx.z == ctx.home.z and ctx.homeDist <= cfg().HOME_RADIUS
    end
    local S = LivingKnox.Senses
    local per = S ~= nil and S.perceived ~= nil and S.perceived(m.npc) or nil
    ctx.threats = Decisions.threatsOf(per, attitudesFor(gid, g, players))
    ctx.threat = ctx.threats[1]
    local C = LivingKnox.Combat   -- LK06-T02 : cible d'attaque d'un combattant (joueurs vus, Hostility.chooseTarget)
    if ctx.combatant and C ~= nil and C.targetFor ~= nil then
        ctx.target = C.targetFor(gid, m.npc, per, players)
    elseif not ctx.combatant then   -- LK06-T07 : tout rôle se bat contre un zombie à portée (jamais contre un joueur)
        local Zm = LivingKnox.Zombies
        if Zm ~= nil and Zm.targetFor ~= nil then ctx.target = Zm.targetFor(m.npc) end
    end
    Decisions.defenceContext(ctx, gid, g, m, per, players, minute)   -- LK06-T05
    -- Alerte de groupe (LK05-T08) : la perception du membre est notée, puis l'alerte en cours qui le concerne est lue.
    local A = LivingKnox.Alert
    if A ~= nil and A.observe ~= nil then
        A.observe(gid, g, mid, m, body, Decisions.withTarget(per, ctx.target), players, minute)
        ctx.alert = A.forMember(gid, x, y, ctx.z, ctx.home == nil or ctx.atHome == true, minute)
    end
    local Df = LivingKnox.Defense   -- LK05-T09 : défense coordonnée du foyer (place, cible depuis la place)
    if Df ~= nil and Df.contextFor ~= nil then ctx.defense = Df.contextFor(gid, g, mid, m, body, ctx, players, minute) end
    local En = LivingKnox.Encounters   -- LK11-T02 : sommation d'un joueur averti près du foyer ou du groupe
    if En ~= nil and En.contextFor ~= nil then ctx.warn = En.contextFor(gid, g, mid, m, body, ctx, per, players, minute) end
    -- Besoins (LK05-T06) : la menace perçue fait d'abord monter la peur, puis les jauges sont lues.
    local N = LivingKnox.Needs
    if N ~= nil and N.perceive ~= nil then N.perceive(gid, mid, ctx.threats, ctx.combatant, minute) end
    ctx.needs = Decisions.needsOf(gid, mid)
    if N ~= nil and N.fearSource ~= nil then ctx.fearFrom = N.fearSource(gid, mid, minute) end
    -- LK06-T07 : groupe débordé (menaces perçues qui mettent en danger contre membres valides proches), pour un membre
    -- valide seulement (aux constantes mauvaises, la règle threat le retire déjà).
    local weight = Decisions.threatWeight(ctx.threats)
    if weight > 0 and Decisions.unfitOf(ctx) == nil then
        local prev = Decisions.state.members[m.npc]
        ctx.overwhelmed = Decisions.overwhelmedOf(weight, Decisions.ableNear(gid, g, x, y, ctx.z),
            prev ~= nil and prev.b == "retreat" and prev.key == "overwhelmed")
    end
    return ctx
end

-- LK06-T07 : membres valides (Decisions.unfitOf : santé et peur) du groupe gid, incarnés, au même niveau et à
-- OVERWHELM.RADIUS cases au plus de (x, y), le membre évalué compris.
function Decisions.ableNear(gid, g, x, y, z)
    local B = LivingKnox.Bodies
    if B == nil or B.find == nil then return 0 end
    local n = 0
    local radius = cfg().OVERWHELM.RADIUS
    for mid, m in pairs(g.members or {}) do
        local body = m.alive and m.npc ~= nil and B.find(m.npc) or nil
        if body ~= nil and not body:isDead() and math.floor(body:getZ()) == z
            and cheb(body:getX(), body:getY(), x, y) <= radius
            and Decisions.unfitOf({ health = Decisions.healthOf(m), needs = Decisions.needsOf(gid, mid) }) == nil then
            n = n + 1
        end
    end
    return n
end

-- Consigne ouverte émise par un autre module : jamais remplacée.
local function externalDirective(id)
    local D = LivingKnox.Directives
    if D == nil or D.get == nil then return nil end
    local e = D.get(id)
    if e == nil or e.done then return nil end
    if Decisions.state.issued[id] == e.v then return nil end
    return e
end

-- Consigne ouverte émise par ce module (ou par les routines LK05-T03 pour lui), ou nil.
local function ownOpen(id)
    local D = LivingKnox.Directives
    local e = D and D.get and D.get(id) or nil
    if e == nil or e.done or Decisions.state.issued[id] ~= e.v then return nil end
    return e
end

local function issued(id, v, why)
    if v == nil then
        Decisions.stats.refused = Decisions.stats.refused + 1
        log().debug("npc %s: decision directive refused: %s", id, tostring(why))
        return false
    end
    Decisions.state.issued[id] = v
    Decisions.stats.issued = Decisions.stats.issued + 1
    return true
end
-- Partagés avec les routines (LK05-T03) : leurs consignes comptent comme celles du cadre (jamais « externes »).
Decisions.ownOpen = ownOpen
Decisions.noteIssued = issued

-- Case de retour au foyer : case libre près du foyer (même bâtiment, LK_Materialize), sinon la case du foyer.
local function homeTarget(home)
    local Mat = LivingKnox.Materialize
    if Mat ~= nil and Mat.homeSquare ~= nil then
        local sq, bid = Mat.homeSquare(home)
        if sq == nil then return nil, "home not loaded" end
        local place = Mat.placeFor and Mat.placeFor(home, bid, cfg().HOME_PLACE_RADIUS) or nil
        if place ~= nil then return place:getX(), place:getY(), place:getZ() end
    end
    return home.x, home.y, home.z
end

local function goHome(id, ctx)
    local D = LivingKnox.Directives
    local open = ownOpen(id)
    if open ~= nil and open.op == D.OP_MOVE and open.g ~= "run" then return end   -- déjà en route
    local x, y, z = homeTarget(ctx.home)
    if x == nil then
        log().debug("npc %s: cannot go home: %s", id, tostring(y))
        return
    end
    issued(id, D.moveTo(id, x, y, z, "walk"))
end

local function face(id, angle)
    local D = LivingKnox.Directives
    if angle == nil then return end
    issued(id, D.face(id, angle))
end

local function flee(id, ctx, out)
    local D = LivingKnox.Directives
    local cell = getCell()
    local step = cfg().FLEE_STEP
    local offsets = { 0, 45 * out.side, -45 * out.side, 90 * out.side, -90 * out.side }
    for _, off in ipairs(offsets) do
        local a = (out.away + off) * math.pi / 180
        local tx = math.floor(ctx.x + step * math.cos(a))
        local ty = math.floor(ctx.y + step * math.sin(a))
        local sq = cell and cell:getGridSquare(tx, ty, ctx.z) or nil
        if sq ~= nil and sq:isFree(false) then
            local v = D.moveTo(id, tx, ty, ctx.z, "run")
            if v ~= nil then
                issued(id, v)
                return true
            end
        end
    end
    Decisions.stats.refused = Decisions.stats.refused + 1
    log().debug("npc %s: no square to flee to, watching instead", id)
    if ctx.threat then face(id, Decisions.angleTo(ctx.threat.x + 0.5 - ctx.x, ctx.threat.y + 0.5 - ctx.y)) end
    return false
end

local function stopOwnMove(id)
    local D = LivingKnox.Directives
    local open = ownOpen(id)
    if open ~= nil and open.op == D.OP_MOVE then issued(id, D.stop(id)) end
end

local function faceTowards(id, st, ctx, x, y, fresh)
    if x == nil then return false end
    local a = Decisions.angleTo(x + 0.5 - ctx.x, y + 0.5 - ctx.y)
    if a == nil or not (fresh or st.faced == nil or angleGap(a, st.faced) >= cfg().FACE_DELTA) then return false end
    st.faced = a
    face(id, a)
    return true
end

-- LK06-T05 : reddition (arrêt, regard vers le joueur, mains levées : geste SURRENDER_GESTURE, LK06-T12) et retraite
-- (course vers le foyer ; sans foyer, fuite pondérée ; au foyer, accroupi face à la menace). Gestes posés après les
-- consignes (une consigne « face » ou « stop » remet le geste au repos) et retirés à la sortie
-- (Decisions.setAlertGesture).
function Decisions.applyDefence(id, st, ctx, fresh)
    local D = LivingKnox.Directives
    if st.b == "surrender" then
        stopOwnMove(id)
        local e = Decisions.playerSpot(ctx, st.u)
        if e ~= nil then faceTowards(id, st, ctx, e.x, e.y, fresh) end
        Decisions.setAlertGesture(id, Decisions.SURRENDER_GESTURE)
        return
    end
    if ctx.home ~= nil and not ctx.atHome then
        Decisions.setAlertGesture(id, nil)
        local open = ownOpen(id)
        if open == nil or open.op ~= D.OP_MOVE or open.g ~= "run" then
            local x, y, z = homeTarget(ctx.home)
            if x ~= nil then issued(id, D.moveTo(id, x, y, z, "run")) end
        end
        return
    end
    if ctx.home == nil then
        Decisions.setAlertGesture(id, nil)
        if fresh and st.away ~= nil then flee(id, ctx, st) end
        return
    end
    stopOwnMove(id)
    local t = ctx.threat
    if t ~= nil then faceTowards(id, st, ctx, t.x, t.y, fresh) end
    Decisions.setAlertGesture(id, "crouch")
end

-- Applique un état nouveau (fresh) ou en cours : vigilance, puis consigne si nécessaire.
-- Routines (LK05-T03, LK_Routines.lua) : guet au poste, ronde et sommeil au couchage, appliqués à chaque passage
-- (progression de la ronde, arrivée au poste, geste assis) ; sans routines chargées : regard vers l'extérieur.
-- Vigilance : posée pour la perception de l'autorité et portée par la consigne courante (champ vg, MP).
-- Geste d'alerte (LK05-T08) : garde pour un combattant, accroupi sinon ; posé après la consigne (une consigne
-- « face » ou « stop » remet le geste au repos, LK_Directives.issue), reposé à chaque passage s'il a changé ; retiré
-- quand le membre quitte « alert » ou « watch » (seulement s'il est encore le nôtre).
local function alertGestures()
    local st = Decisions.state
    st.gestures = st.gestures or {}
    return st.gestures
end

function Decisions.setAlertGesture(id, gesture)
    local A = LivingKnox.Anim
    if A == nil then return end
    local mine = alertGestures()
    if gesture == nil then
        local had = mine[id]
        mine[id] = nil
        if had ~= nil and A.gestureOf(id) == had then A.setGesture(id, A.DEFAULT) end
        return
    end
    mine[id] = gesture
    if A.gestureOf(id) ~= gesture then A.setGesture(id, gesture) end
end

function Decisions.apply(id, st, ctx, fresh)
    local D = LivingKnox.Directives
    local S = LivingKnox.Senses
    local vigil = Decisions.BEHAVIOURS[st.b].vigil
    local alertGesture = nil
    local unfit = Decisions.unfitOf(ctx) ~= nil   -- LK06-T07 : geste et abri selon les constantes, non le rôle
    if st.b == "alert" or (st.b == "watch" and ctx.alert ~= nil) then
        alertGesture = unfit and "crouch" or "guard"
    elseif st.b == "surrender" or st.b == "retreat" or st.b == "defend" or st.b == "warn" then   -- geste posé plus bas
        alertGesture = nil
    else
        Decisions.setAlertGesture(id, nil)
    end
    if S ~= nil and S.setVigilance ~= nil then S.setVigilance(id, vigil) end
    if D == nil then return end
    if D.setVigil ~= nil then D.setVigil(id, vigil) end
    local b = st.b
    local R = LivingKnox.Routines
    local routine = R ~= nil and R.handles(b) and (ctx.home == nil or ctx.atHome)
    if R ~= nil and not routine then R.leave(id) end   -- routine interrompue ou finie : debout, mémoire oubliée
    local C = LivingKnox.Combat   -- LK06-T02 : mêlée menée par LK_Combat ; tout autre comportement y met fin
    if b == "fight" then
        if C ~= nil then C.apply(id, st, ctx, fresh) end
        return
    end
    local Df = LivingKnox.Defense   -- LK05-T09 : engagement depuis la place, ou place, regard et geste
    if b == "defend" and Df ~= nil then
        Df.apply(id, st, ctx, fresh)
        return
    end
    if C ~= nil and C.leave ~= nil then C.leave(id) end
    local Ex = LivingKnox.Expeditions   -- LK05-T05 : trajet, fouille et retour menés par LK_Expeditions
    if b == "expedition" and Ex ~= nil then
        Ex.apply(id, st, ctx, fresh)
        return
    end
    local Rl = LivingKnox.Relations   -- LK11-T05 : traque et retour menés par LK_Relations
    if b == "revenge" and Rl ~= nil and Rl.applyHunt ~= nil then
        Rl.applyHunt(id, st, ctx, fresh)
        return
    end
    local En = LivingKnox.Encounters   -- LK11-T02 : sommation (arrêt, regard, geste, réplique, coup de semonce)
    if b == "warn" and En ~= nil then
        En.apply(id, st, ctx, fresh)
        return
    end
    local Ca = LivingKnox.Care   -- LK07-T03 : soin (médecin ou blessé seul) mené pendant un comportement calme au foyer
    if Ca ~= nil and Ca.apply ~= nil and Ca.apply(id, st, ctx, fresh) then return end
    if b == "surrender" or b == "retreat" then
        Decisions.applyDefence(id, st, ctx, fresh)   -- LK06-T05
        return
    end
    if b == "watch" or b == "alert" then
        local t = b == "watch" and ctx.threat or ctx.alert
        if b == "alert" and unfit and ctx.home ~= nil and not ctx.atHome then
            -- Membre aux constantes mauvaises loin du foyer (LK06-T07) : il y court d'abord (abri), accroupi ensuite.
            local open = ownOpen(id)
            if open == nil or open.op ~= D.OP_MOVE then
                local x, y, z = homeTarget(ctx.home)
                if x ~= nil then issued(id, D.moveTo(id, x, y, z, "run")) end
            end
            return
        end
        local a = t and Decisions.angleTo(t.x + 0.5 - ctx.x, t.y + 0.5 - ctx.y) or nil
        if a ~= nil and (fresh or st.faced == nil or angleGap(a, st.faced) >= cfg().FACE_DELTA) then
            st.faced = a
            face(id, a)
        end
        if alertGesture ~= nil then Decisions.setAlertGesture(id, alertGesture) end
        return
    end
    if routine then
        R.apply(id, st, ctx, fresh)
        return
    end
    if not fresh then return end
    if b == "flee" then
        flee(id, ctx, st)
    elseif ctx.home ~= nil and not ctx.atHome then
        goHome(id, ctx)
    elseif b == "guard" or b == "patrol" then
        face(id, st.angle)
    else
        local open = ownOpen(id)
        if open ~= nil and open.op == D.OP_MOVE then issued(id, D.stop(id)) end   -- fin d'une fuite au foyer
    end
end

-- Évalue un membre incarné : décision, état gardé ou remplacé, application. Rend vrai si une décision a été prise.
function Decisions.evaluate(gid, g, mid, m, body, players, minute)
    local id = m.npc
    Decisions.stats.evaluated = Decisions.stats.evaluated + 1
    Decisions.markEvaluated(id)   -- E09-T05 : passage de décision constaté par Decisions.aims
    if externalDirective(id) ~= nil then
        Decisions.stats.external = Decisions.stats.external + 1
        return false
    end
    local ctx = Decisions.context(gid, g, mid, m, body, players, minute)
    Decisions.judgeDefense(gid, g, mid, m, ctx, players, minute)   -- E10-T03 : poste de défense refusé
    local out = Decisions.decide(ctx)
    if out == nil then return false end
    if out.rule == "threat" and out.b ~= "alert" and out.b ~= "defend" then noteThreat(gid, out.key, math.floor(minute / 60)) end
    local st = Decisions.state.members[id]
    local prev = st
    -- LK04-T05 : notre consigne close en échec "stuck" (LK_Movement) : échéance avancée, la cascade choisit une autre
    -- consigne (la case du blocage est refusée à ce PNJ par Directives.moveTo pendant Movement.AVOID_MS).
    local Mv = LivingKnox.Movement
    if st ~= nil and Mv ~= nil and Mv.takeStuck ~= nil and Mv.takeStuck(id, Decisions.state.issued[id]) then
        st.untilMin = minute
        log().info("npc %s: %s directive stuck, decision taken again", id, tostring(st.b))
    end
    local fresh, why = Decisions.replaces(st, out, minute)
    if fresh and st ~= nil and st.b == "sleep" and out.rule == "threat" and ctx.alert ~= nil then
        local A = LivingKnox.Alert   -- LK05-T08 : dormeur réveillé par l'alerte
        if A ~= nil and A.noteWoken ~= nil then A.noteWoken(gid, id) end
    end
    if fresh then
        out.gid, out.mid = gid, mid
        Decisions.state.members[id] = out
        st = out
        Decisions.stats.decided = Decisions.stats.decided + 1
        log().debug("npc %s (%s %s %s): %s -> %s until minute %d (%s)", id, gid, mid, tostring(m.role), out.rule, out.b,
            out.untilMin, out.why .. ", " .. why)
        local Ac = LivingKnox.Activity   -- LK13-T14 : journal d'activité (mémoire seulement, aucune décision changée)
        if Ac ~= nil then Ac.behaviour(gid, mid, id, prev, out, why) end
    else
        Decisions.stats.kept = Decisions.stats.kept + 1
    end
    afterDecision(gid, g, mid, m, body, st, prev, ctx, fresh, minute)   -- LK06-T05
    Decisions.apply(id, st, ctx, fresh)
    local N = LivingKnox.Needs   -- LK05-T06 : activité de l'heure pour le pas horaire des besoins
    if N ~= nil and N.observe ~= nil then N.observe(gid, mid, st.b, ctx.home == nil or ctx.atHome, minute) end
    return fresh
end

-- Liste des membres incarnés dont le corps est relié : { { gid, mid, npc }, ... } triée (groupe, numéro de membre).
function Decisions.buildRoster()
    local out = {}
    local G = Groups()
    local registry = registryOfBodies()
    local data = G.isReady() and G.state.data or nil
    if data == nil or registry == nil then return out end
    local B = LivingKnox.Bodies
    local ids = {}
    for gid in pairs(data.groups) do ids[#ids + 1] = gid end
    table.sort(ids)
    for _, gid in ipairs(ids) do
        local g = data.groups[gid]
        local mids = {}
        for mid, m in pairs(g.members) do
            if m.alive and isEmbodied(m, registry) and B ~= nil and B.find(m.npc) ~= nil then mids[#mids + 1] = mid end
        end
        table.sort(mids, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
        for _, mid in ipairs(mids) do out[#out + 1] = { gid = gid, mid = mid, npc = g.members[mid].npc } end
    end
    local keep = {}
    for _, r in ipairs(out) do keep[r.npc] = true end
    local gone = {}
    for id in pairs(Decisions.state.members) do
        if not keep[id] then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do Decisions.forget(id) end
    return out
end

function Decisions.forget(id)
    Decisions.state.members[id] = nil
    Decisions.evals.at[id] = nil   -- E09-T05
    bucket("refusals")[id] = nil   -- E10-T03
    Decisions.state.issued[id] = nil
    Decisions.setAlertGesture(id, nil)   -- LK06-T12 : geste d'alerte ou de reddition retiré (mort, corps parti)
    bucket("hits")[id] = nil   -- LK06-T05 : coup reçu, reddition de ce PNJ
    for _, per in pairs(bucket("surrenders")) do
        local gone = {}
        for u, s in pairs(per) do
            if s.npc == id then gone[#gone + 1] = u end
        end
        for _, u in ipairs(gone) do per[u] = nil end
    end
    local R = LivingKnox.Routines
    if R ~= nil then R.forget(id) end
    local C = LivingKnox.Combat   -- LK06-T02
    if C ~= nil and C.forget ~= nil then C.forget(id) end
    local Df = LivingKnox.Defense   -- LK05-T09
    if Df ~= nil and Df.forget ~= nil then Df.forget(id) end
    local En = LivingKnox.Encounters   -- LK11-T02
    if En ~= nil and En.forget ~= nil then En.forget(id) end
end

-- Passage des membres : au plus MEMBERS_PER_PASS choisis, tour à tour. Liste refaite toutes les ROSTER_MS, ou à
-- chaque passage tant qu'elle est vide (un membre incarné entre-temps attend au plus ROSTER_MS). LK13-T11 : les
-- membres choisis sont évalués MEMBERS_PER_FRAME par image (Decisions.memberStep), le premier dans l'image du
-- passage, les suivants aux images qui suivent (300 ms au plus sur un serveur dédié) : même fréquence par membre,
-- coût d'une image borné à un membre. Chaque membre est relu (groupe, membre, corps) et évalué avec l'heure et les
-- joueurs de son image. Un passage suivant remplace ce qui reste du précédent. Rend le nombre évalué dans l'image.
function Decisions.memberPass(t)
    local st = Decisions.state
    t = t or now()
    if st.rosterMs == nil or t - st.rosterMs >= cfg().ROSTER_MS or #st.roster == 0 then
        st.roster = Decisions.buildRoster()
        st.rosterMs = t
    end
    local roster = st.roster
    local n = #roster
    st.batch, st.batchHead = nil, 1
    if n == 0 then return 0 end
    local minute = Decisions.currentMinute()
    if minute == nil then return 0 end
    local A = LivingKnox.Alert   -- LK05-T08 : alertes retombées closes (écouteurs « calm »)
    if A ~= nil and A.update ~= nil then A.update(minute) end
    local batch = {}
    for _ = 1, math.min(n, cfg().MEMBERS_PER_PASS) do
        st.cursor = (st.cursor % n) + 1
        batch[#batch + 1] = roster[st.cursor]
    end
    st.batch = batch
    Decisions.stats.passes = Decisions.stats.passes + 1
    return Decisions.memberStep()
end

-- Membres du passage en cours évalués dans cette image (au plus MEMBERS_PER_FRAME ; un membre sans corps est passé
-- sans compter). Rend le nombre évalué.
function Decisions.memberStep()
    local st = Decisions.state
    local batch = st.batch
    if batch == nil then return 0 end
    local minute = Decisions.currentMinute()
    if minute == nil then return 0 end
    local hour = math.floor(minute / 60)
    local G = Groups()
    local data = G.state.data
    local B = LivingKnox.Bodies
    local players = B ~= nil and B.livingPlayers ~= nil and B.livingPlayers() or {}
    local done, budget = 0, math.max(1, cfg().MEMBERS_PER_FRAME or 1)
    while done < budget and st.batchHead <= #batch do
        local r = batch[st.batchHead]
        st.batchHead = st.batchHead + 1
        local g = data and data.groups[r.gid] or nil
        local m = g and g.members[r.mid] or nil
        local body = m and m.alive and m.npc == r.npc and B.find(r.npc) or nil
        if body ~= nil then
            -- Groupe noté à son arrivée ; LK13-T11 : pas s'il le sera par la notation de l'heure encore en attente
            -- (passe différée de LK_Simulation ou file de notation) : ses membres gardent d'ici là l'objectif et les
            -- postes de l'heure précédente (quelques images).
            if st.scored[r.gid] ~= hour and not Decisions.hourScoringPending(r.gid, hour) then
                Decisions.scorePass(hour, r.gid)
            end
            Decisions.evaluate(r.gid, g, r.mid, m, body, players, minute)
            done = done + 1
        end
    end
    if st.batchHead > #batch then st.batch = nil end
    Decisions.flushRefusals()   -- E10-T03 : refus de la défense et des expéditions (LK_Expeditions.teamOf)
    local stats = Decisions.stats
    if done > stats.maxPerPass then stats.maxPerPass = done end   -- LK13-T11 : membres évalués dans une image
    return done
end

function Decisions.tick()
    if not LivingKnox.isAuthority() or getCell() == nil then return end
    if not LivingKnox.Config.isEnabled() then return end
    local t = now()
    local st = Decisions.state
    if st.lastPass ~= nil and t - st.lastPass < cfg().PASS_MS then
        if st.batch ~= nil and Groups().isReady() then Decisions.memberStep() end   -- LK13-T11 : suite du passage
        return
    end
    st.lastPass = t
    if not Groups().isReady() then return end
    Decisions.memberPass(t)
end

-- LK13-T11 : file de notation de l'heure (une notation par image, à partir de l'image qui suit l'EveryHours).
function Decisions.onFrameStart()
    Decisions.hourQueue.fresh = false
end

function Decisions.hourTick()
    if not LivingKnox.isAuthority() then return end
    local q = Decisions.hourQueue
    if q.fresh or q.head > #q.list then return end
    if not Groups().isReady() then return end
    hourStep(false)
end

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
    Decisions.hourQueue = { list = {}, head = 1, hour = nil, fresh = false }   -- LK13-T11
    if Groups() ~= nil and Groups().release ~= nil then Groups().release("decisions") end
    Decisions.evals.at = {}   -- E09-T05 : numéros oubliés, compteur gardé (jamais réutilisé)
end

-- E09-T05 (accords de faction, RS_Factions ; fiche docs/annexes/conception/accords.md) : point de lecture du passage de
-- décision. Chaque évaluation d'un membre reçoit un numéro croissant (mémoire seulement, jamais réutilisé).
Decisions.evals = Decisions.evals or { seq = 0, at = {} }

-- Note l'évaluation du membre id ; rend son numéro.
function Decisions.markEvaluated(id)
    local e = Decisions.evals
    e.seq = e.seq + 1
    e.at[id] = e.seq
    return e.seq
end

-- Joueur visé par le membre id : engagement de LK_Combat contre un joueur (mêlée, tir, défense du foyer), sinon
-- comportement « fight » ou « warn » de la cascade (clé "p<compte>"). Compte ou nil.
local function aimedAccount(id)
    local C = LivingKnox.Combat
    local o = C ~= nil and C.get ~= nil and C.get(id) or nil
    if o ~= nil and o.k ~= "zombie" and type(o.u) == "string" then return o.u end
    local st = Decisions.state.members[id]
    if st ~= nil and (st.b == "fight" or st.b == "warn") and type(st.key) == "string"
            and string.sub(st.key, 1, 1) == "p" then
        return string.sub(st.key, 2)
    end
    return nil
end

-- Lecture seule, pour l'application d'un accord : { seq = dernier numéro d'évaluation, members = { { npc, eval =
-- numéro de sa dernière évaluation ou nil, active = vrai s'il a un état de décision ou un engagement, u = compte du
-- joueur visé ou nil }, ... } } pour chaque membre vivant du groupe gid (ordre des numéros de membre), ou nil.
function Decisions.aims(gid)
    local G = Groups()
    local g = G.isReady() and G.state.data.groups[gid] or nil
    if g == nil then return nil end
    local mids = {}
    for mid, m in pairs(g.members) do
        if m.alive and type(m.npc) == "string" then mids[#mids + 1] = mid end
    end
    table.sort(mids, function(a, b) return (G.memberNumber(a) or 0) < (G.memberNumber(b) or 0) end)
    local out = {}
    local C = LivingKnox.Combat
    for _, mid in ipairs(mids) do
        local id = g.members[mid].npc
        local engaged = C ~= nil and C.get ~= nil and C.get(id) ~= nil
        out[#out + 1] = { npc = id, eval = Decisions.evals.at[id],
            active = Decisions.state.members[id] ~= nil or engaged, u = aimedAccount(id) }
    end
    return { seq = Decisions.evals.seq, members = out }
end

-- ================================================================ E10-T03 : refus d'un ordre du moteur
-- Fiche docs/annexes/conception/contestation.md. Un membre INCARNÉ peut refuser un ordre du moteur : le guet (poste sentry,
-- Decisions.scoreGroup), le départ en expédition (LK_Expeditions.teamOf) ou sa place de combat dans la défense du
-- foyer (rôle "post" de LK_Defense, Decisions.evaluate). Règles simples et déterministes, sans LLM, dans cet ordre :
-- chef (ne refuse jamais), blessure, moral (loyauté chancelante), attitude (défense contre un joueur que le groupe
-- apprécie), rôle (ordre que son rôle ne permet pas). Conséquence bornée : le membre n'exécute pas cet ordre (un autre
-- prend le guet, l'équipe part sans lui, il quitte sa place de combat), garde mémoire et appartenance ; aucun champ
-- persistant (refus gardés en mémoire HOLD_MINUTES pour la même instance d'ordre). Annonce une seule fois par refus :
-- entrée « refusal » au journal du groupe (anglais, faits seulement) et réplique de gabarit traduite par chaque client
-- (LivingKnox.Speech.say, clé IGUI_LK_Refuse_<ordre>_<raison>), entendue par les joueurs à portée. Un membre non
-- incarné n'est jamais jugé ici : la contestation hors écran reste l'événement « conflict » de LK_Simulation (LK09-T05).
-- Loyauté (E10-T03) : dérivée du moral du groupe et de l'ancienneté du membre (rang parmi les vivants), sans champ.
Decisions.ORDERS = { "guard", "expedition", "defend" }
Decisions.REFUSAL_REASONS = { "wound", "morale", "attitude", "role" }
Decisions.REFUSAL_KEY = "IGUI_LK_Refuse_"
Decisions.CFG.REFUSE = Decisions.CFG.REFUSE or {
    HEALTH = 0.6,         -- santé de référence / naissance sous laquelle un membre refuse un ordre
    SENIOR_BONUS = 20,    -- loyauté : points ajoutés au moral pour le plus ancien vivant (0 pour le dernier arrivé)
    LOYAL = 60,           -- loyauté >= LOYAL : "loyal"
    WAVERING = 30,        -- loyauté < WAVERING : "wavering" (moral très bas) : refuse les ordres
    HOLD_MINUTES = 240,   -- minutes de jeu : un refus vaut pour la même instance d'ordre, puis il est rejugé
}
-- Comportements de rôle exigés par un ordre (règle « rôle ») ; defend : tout rôle défend (LK06-T07).
Decisions.ORDER_NEEDS = { guard = Decisions.DUTY_NEEDS.sentry, expedition = Decisions.DUTY_NEEDS.forager }
-- Niveaux d'attitude (LK_Hostility) d'un joueur que le groupe apprécie : un membre refuse de le combattre.
Decisions.FRIENDLY_LEVELS = { trusting = true, favorable = true }

-- Rang d'ancienneté du membre mid parmi les membres vivants de g (1 = plus ancien) et nombre de vivants.
function Decisions.seniorityOf(g, mid)
    local G = Groups()
    local mine = G.memberNumber(mid) or 0
    local older, alive = 0, 0
    for other, m in pairs(g.members or {}) do
        if m.alive then
            alive = alive + 1
            if other ~= mid and (G.memberNumber(other) or 0) < mine then older = older + 1 end
        end
    end
    return older + 1, alive
end

-- Loyauté (pur) : moral du groupe (0..100) + SENIOR_BONUS x ancienneté (1 pour le plus ancien des count vivants, 0
-- pour le dernier arrivé). Rend "loyal" | "steady" | "wavering" et le score entier.
function Decisions.loyaltyOf(morale, rank, count)
    local c = cfg().REFUSE
    morale = finite(morale) and clamp(morale, 0, 100) or 50
    local seniority = 0
    if finite(rank) and finite(count) and count > 1 then seniority = clamp((count - rank) / (count - 1), 0, 1) end
    local score = math.floor(morale + c.SENIOR_BONUS * seniority + 0.5)
    if score >= c.LOYAL then return "loyal", score end
    if score < c.WAVERING then return "wavering", score end
    return "steady", score
end

-- Loyauté du membre mid du groupe g (registre).
function Decisions.loyaltyOfMember(g, mid)
    local rank, count = Decisions.seniorityOf(g, mid)
    return Decisions.loyaltyOf(g.morale, rank, count)
end

-- Refus d'un ordre (pur). r = { order (ORDERS), leader (booléen), health (0..1 ou nil), loyalty, score, role, allowed
-- (ensemble des comportements du rôle), playerLevel (attitude du groupe envers le joueur visé par la défense, ou
-- nil) }. Rend la raison (REFUSAL_REASONS) et son détail anglais, ou nil (ordre accepté).
function Decisions.refusalOf(r)
    local c = cfg().REFUSE
    if r.leader then return nil end
    if r.health ~= nil and r.health < c.HEALTH then
        return "wound", string.format("health %d%% < %d%%", math.floor(r.health * 100 + 0.5),
            math.floor(c.HEALTH * 100 + 0.5))
    end
    if r.loyalty == "wavering" then return "morale", "loyalty " .. tostring(r.score) .. " < " .. c.WAVERING end
    if r.order == "defend" and r.playerLevel ~= nil and Decisions.FRIENDLY_LEVELS[r.playerLevel] then
        return "attitude", "player is " .. tostring(r.playerLevel)
    end
    local need = Decisions.ORDER_NEEDS[r.order]
    if need ~= nil and not anyOf(r.allowed or {}, need) then
        return "role", "role " .. tostring(r.role) .. " not fit"
    end
    return nil
end

-- Jugement de l'ordre order (instance key) donné au membre incarné mid à la minute minute (autorité). extra =
-- { playerLevel } pour la défense. Rend la raison et le détail d'un refus, ou nil. Un refus encore valable (même
-- instance, HOLD_MINUTES) est rendu sans nouvelle annonce ; un nouveau refus est mis en file (flushRefusals).
function Decisions.judgeOrder(gid, g, mid, m, order, key, minute, extra)
    local id = m and m.npc or nil
    if id == nil or not finite(minute) then return nil end
    local all = bucket("refusals")
    local mine = all[id]
    local rec = mine ~= nil and mine[order] or nil
    -- Refus encore valable : à moins de HOLD_MINUTES de son jugement, dans un sens ou dans l'autre. Le guet est jugé à
    -- l'heure pleine (refuseDuties : heure x 60), les autres appelants à la minute près : un jugement à 23 h 25 puis
    -- un autre à « 23 h 00 » est le même refus (essai en jeu du 2026-10-13, lk.contest : refus annoncé deux fois).
    if rec ~= nil and rec.key == key and math.abs(minute - rec.since) < rec.untilMin - rec.since then
        return rec.reason, rec.why
    end
    local level, score = Decisions.loyaltyOfMember(g, mid)
    local reason, why = Decisions.refusalOf({ order = order, leader = g.leader == mid, health = Decisions.healthOf(m),
        loyalty = level, score = score, role = m.role, allowed = Decisions.allowedOf(g.type, m.role),
        playerLevel = extra and extra.playerLevel or nil })
    if reason == nil then
        if mine ~= nil then mine[order] = nil end
        return nil
    end
    all[id] = mine or {}
    all[id][order] = { key = key, reason = reason, why = why, since = minute,
        untilMin = minute + cfg().REFUSE.HOLD_MINUTES }
    local q = bucket("refusalQueue")
    q[#q + 1] = { gid = gid, mid = mid, npc = id, order = order, reason = reason, why = why }
    Decisions.stats.orderRefusals = (Decisions.stats.orderRefusals or 0) + 1
    log().info("npc %s (%s %s) refuses the %s order: %s (%s)", id, gid, mid, order, reason, why)
    return reason, why
end

-- Refus actif (copie) du PNJ id pour l'ordre order, ou nil : { key, reason, why, since, untilMin }.
function Decisions.refusalFor(id, order)
    local mine = bucket("refusals")[id]
    local rec = mine ~= nil and mine[order] or nil
    if rec == nil then return nil end
    local out = {}
    for k, v in pairs(rec) do out[k] = v end
    return out
end

-- Guet (appelé par scoreGroup dans l'écriture du registre) : chaque membre incarné à qui le guet échoit est jugé ;
-- un refus le rend inapte au poste sentry (members[i].refuses). Rend vrai si un nouveau membre refuse (postes à refaire).
function Decisions.refuseDuties(gid, g, members, duties, hour)
    local registry = registryOfBodies()
    local any = false
    for _, gm in ipairs(members) do
        local m = g.members[gm.mid]
        if duties[gm.mid] == "sentry" and m ~= nil and isEmbodied(m, registry)
            and not (gm.refuses ~= nil and gm.refuses.sentry)
            and Decisions.judgeOrder(gid, g, gm.mid, m, "guard", "sentry", hour * 60) ~= nil then
            gm.refuses = gm.refuses or {}
            gm.refuses.sentry = true
            any = true
        end
    end
    return any
end

-- Défense (appelée par evaluate) : place de combat (rôle "post") refusée -> le membre quitte la défense (ctx.defense
-- effacé) et ne combat aucun joueur (cible joueur effacée ; un zombie à portée reste combattu, LK06-T07).
function Decisions.judgeDefense(gid, g, mid, m, ctx, players, minute)
    local dv = ctx.defense
    if dv == nil or dv.role ~= "post" then return nil end
    local level
    local tg = dv.target or ctx.target
    if tg ~= nil and tg.kind ~= "zombie" and tg.u ~= nil then level = attitudesFor(gid, g, players)[tg.u] end
    local reason = Decisions.judgeOrder(gid, g, mid, m, "defend", "defense " .. tostring(dv.id), minute,
        { playerLevel = level })
    if reason == nil then return nil end
    ctx.defense = nil
    if ctx.target ~= nil and ctx.target.kind ~= "zombie" then ctx.target = nil end
    ctx.refused = reason
    return reason
end

-- Annonce des refus en file : journal du groupe (Groups.addLog, kind "refusal") et réplique de gabarit entendue par
-- les joueurs à portée (LivingKnox.Speech.say ; module absent ou personne à portée : journal seul). Rend le nombre.
function Decisions.flushRefusals()
    local q = Decisions.state.refusalQueue
    if q == nil or #q == 0 then return 0 end
    Decisions.state.refusalQueue = {}
    local G, Sp = Groups(), LivingKnox.Speech
    for _, r in ipairs(q) do
        local text = string.sub(string.format("%s refused the %s order: %s (%s)", r.mid, r.order, r.reason, r.why), 1,
            G.TEXT_MAX)
        local ok, err = G.addLog(r.gid, "refusal", text)
        if not ok then log().warn("group %s: refusal of %s not logged: %s", r.gid, r.mid, tostring(err)) end
        if Sp ~= nil and Sp.say ~= nil then
            local out, why = Sp.say(r.npc, { key = Decisions.REFUSAL_KEY .. r.order .. "_" .. r.reason })
            if out == nil then log().debug("npc %s: refusal line not heard: %s", r.npc, tostring(why)) end
        end
    end
    return #q
end

return Decisions
