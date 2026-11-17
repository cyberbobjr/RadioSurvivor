-- Living Knox : cadre de décision des PNJ, socle commun (LK20-T09 : sorti de LK_Decisions.lua sans changement de
-- comportement) : table LivingKnox.Decisions, listes fermées (objectifs, postes, priorités, comportements), réglages
-- CFG, état en mémoire et compteurs, seuils de danger, hasard déterministe, horloge, et table privée Decisions._ des
-- fonctions partagées entre les fichiers du moteur dans Decisions/. Chaque fichier du moteur le requiert en premier : il
-- se charge donc dans n'importe quel ordre (la façade requiert chaque fichier, et le jeu n'exécute jamais deux fois le
-- même fichier). Les comportements LK_Decide_*.lua du même dossier requièrent la façade.
-- Façade et vue d'ensemble : LK_Decisions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_GroupTypes"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Groups"

local Decisions = LivingKnox.Decisions or {}
LivingKnox.Decisions = Decisions
-- LK20-T09 : fonctions privées partagées entre les fichiers de Decisions/ (rangées par chaque fichier à sa fin) ;
-- même table d'un chargement à l'autre.
Decisions._ = Decisions._ or {}
local P = Decisions._

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
-- LK16-T06 : cette liste déclare les comportements que proposent les règles du moteur (RULES, qui restent ici :
-- décision D04 de l'ADR de remise en ordre) ; leur APPLICATION (apply, visée aim, geste, sortie) est menée par
-- l'extension propriétaire inscrite sous le même id (Decisions.registerExtension) par le module qui mène le
-- comportement ou par un fichier de server/LivingKnox/Decisions/. owned : sans son extension (module absent), le
-- moteur n'applique rien (ni soin, ni routine, ni retour au foyer) ; sinon, repli du moteur (soin, routine, foyer).
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
    fight = { vigil = "guard", owned = true },                     -- mêlée ou tir contre la cible retenue (LK06-T02,
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
-- Entier tiré dans [lo, hi] du flux rnd (visées des comportements, LK16-T06).
Decisions.pick = pick

-- Angle (degrés, 0..360) de (dx, dy) dans la convention de setDirectionAngle (y croissant = sud,
-- Directives.ANGLES) ; nil pour un vecteur nul.
function Decisions.angleTo(dx, dy)
    if dx == 0 and dy == 0 then return nil end
    local a = math.atan2(dy, dx) * 180 / math.pi
    a = math.floor(a + 0.5)
    return a - math.floor(a / 360) * 360
end

-- Horloge ----------------------------------------------------------------------------------------------------------

-- Minute de jeu courante (âge du monde en minutes, entier), ou nil si l'horloge manque.
function Decisions.currentMinute()
    local gt = getGameTime and getGameTime()
    if not gt then return nil end
    local hours = gt:getWorldAgeHours()
    if not LivingKnox.Num.finite(hours) or hours < 0 then return nil end
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

-- E09-T05 (accords de faction, LK_Agreements depuis E18-T20 ; fiche docs/annexes/conception/accords.md) : point de
-- lecture du passage de
-- décision. Chaque évaluation d'un membre reçoit un numéro croissant (mémoire seulement, jamais réutilisé).
Decisions.evals = Decisions.evals or { seq = 0, at = {} }

P.anyOf = anyOf
P.cfg = cfg
P.now = now
P.pick = pick
