-- Living Knox : options sandbox (page LivingKnox).
-- Lecture à chaque appel, sans cache : une option peut changer en cours de partie.
require "LivingKnox/LK_Core"

local Config = LivingKnox.Config or {}
LivingKnox.Config = Config

Config.NAMESPACE = "LivingKnox"
Config.DEFAULTS = {
    Enabled = true,
    Debug = false,
    -- Population (LK08-T05, docs/conception/groupes.md, section « Population ») : = default de sandbox-options.txt.
    GroupCount = 4,
    WeightSettlers = 40,
    WeightRaiders = 35,
    WeightNeutrals = 25,
    GroupSizeMin = 4,
    GroupSizeMax = 8,
    ReliefDaysMin = 2,
    ReliefDaysMax = 5,
    -- Raids des pillards (LK11-T07, docs/conception/raids.md) : = default de sandbox-options.txt.
    RaidsEnabled = true,
    RaidDays = 14,
    -- Vengeance (LK11-T10, docs/conception/vengeance.md) : = default de sandbox-options.txt.
    RevengeDelayHours = 72,
}

-- Bornes des options entières (= min / max de sandbox-options.txt ; vérifié par tests/test_lk_population.py).
Config.INT_BOUNDS = {
    GroupCount = { 3, 5 },
    WeightSettlers = { 0, 100 },
    WeightRaiders = { 0, 100 },
    WeightNeutrals = { 0, 100 },
    GroupSizeMin = { 4, 8 },
    GroupSizeMax = { 4, 8 },
    ReliefDaysMin = { 2, 5 },
    ReliefDaysMax = { 2, 5 },
    RaidDays = { 3, 90 },
    RevengeDelayHours = { 12, 336 },
}

-- Poids de tirage des types de groupes livrés : option sandbox de chaque type. Un type sans option (ajouté par un
-- autre mod) n'est pas tiré par la population initiale.
Config.TYPE_WEIGHT_OPTIONS = { settlers = "WeightSettlers", raiders = "WeightRaiders", neutrals = "WeightNeutrals" }

-- Valeur brute d'une option, ou nil : options enregistrées (Java) d'abord, à jour sur le serveur comme sur les
-- clients, même après un changement en cours de partie ; repli : SandboxVars.
function Config.readRaw(name)
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName(Config.NAMESPACE .. "." .. name)
    if option then
        local value = option:getValue()
        if value ~= nil then return value end
    end
    local vars = SandboxVars and SandboxVars[Config.NAMESPACE]
    local value = vars and vars[name]
    if value == nil then return nil end
    return value
end

-- Valeur d'une option, ou sa valeur par défaut si elle est absente.
function Config.read(name)
    local value = Config.readRaw(name)
    if value == nil then return Config.DEFAULTS[name] end
    return value
end

local function warn(msg, ...)
    local Log = LivingKnox.Log
    if Log then Log.warn(msg, ...) end
end

local function isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

-- Option entière de INT_BOUNDS : valeur absente, non entière ou hors bornes -> valeur par défaut et avertissement.
function Config.readInt(name)
    local bounds, default = Config.INT_BOUNDS[name], Config.DEFAULTS[name]
    local value = Config.readRaw(name)
    if value == nil then
        warn("option %s.%s missing, default %s used", Config.NAMESPACE, name, tostring(default))
        return default
    end
    if not isInt(value, bounds[1], bounds[2]) then
        warn("option %s.%s = %s is not an integer from %d to %d, default %s used", Config.NAMESPACE, name,
            tostring(value), bounds[1], bounds[2], tostring(default))
        return default
    end
    return value
end

-- Couple d'options min / max : min > max -> les deux valeurs par défaut et avertissement.
local function readRange(minName, maxName)
    local lo, hi = Config.readInt(minName), Config.readInt(maxName)
    if lo > hi then
        warn("options %s.%s = %d > %s = %d, defaults %d..%d used", Config.NAMESPACE, minName, lo, maxName, hi,
            Config.DEFAULTS[minName], Config.DEFAULTS[maxName])
        return Config.DEFAULTS[minName], Config.DEFAULTS[maxName]
    end
    return lo, hi
end

-- Réglages de population lus à chaque appel (LK08-T05) : { count, weights = { [type] = 0..100 }, sizeMin, sizeMax,
-- reliefMin, reliefMax }. Délai de relève en jours : lu ici seulement, consommé par la relève (LK09-T04).
function Config.population()
    local out = { count = Config.readInt("GroupCount"), weights = {} }
    for groupType, option in pairs(Config.TYPE_WEIGHT_OPTIONS) do out.weights[groupType] = Config.readInt(option) end
    out.sizeMin, out.sizeMax = readRange("GroupSizeMin", "GroupSizeMax")
    out.reliefMin, out.reliefMax = readRange("ReliefDaysMin", "ReliefDaysMax")
    return out
end

-- Seuils de danger réglables (LK05-T14, fiche docs/conception/decisions.md, section « Seuils de danger réglables ») :
-- options sandbox entières LivingKnox.<nom>, en cases (DefenseWithdrawRatio : rapport sans unité). Chaque entrée :
-- { min, max, défaut } = min / max / default de sandbox-options.txt (vérifié par tests/test_lk_thresholds.py).
-- Lues à chaque appel (sondage : aucun événement ne suit un changement d'option et SandboxVars reste périmé en solo,
-- base load-warnings.md). Option absente (sandbox-options.txt non chargé : banc, partie sans la page) ou invalide
-- (non entière, hors bornes) : valeur de repli du module appelant, celle d'avant LK05-T14 ; ZombieAlertDistance
-- absente : aucune limite (tout zombie perçu compte, comme avant).
Config.DANGER = {
    ZombieAlertDistance = { 1, 30, 10 },     -- zombie perçu au-delà (du membre) : ignoré (alerte, cascade, défense)
    AlertReach = { 5, 60, 20 },              -- Alert.CFG.REACH 30, Defense.CFG.REINFORCE_RADIUS 30
    AlertShoutZombie = { 1, 30, 10 },        -- Alert.CFG.SHOUT.zombie 15
    FleeDistance = { 1, 20, 4 },             -- Decisions.CFG.FLEE_DIST 6
    FleeDistanceAfraid = { 1, 30, 8 },       -- Decisions.CFG.FLEE_DIST_AFRAID 12
    -- LK06-T14 : portée d'engagement des zombies PAR RÔLE (décision de l'utilisateur du 2026-10-13), Config.ZOMBIES.
    -- DEFEND_RANGE 10 ; remplace l'option unique ZombieEngageDistance (défaut 4), retirée.
    ZombieEngageDeputy = { 1, 15, 10 },
    ZombieEngageFighter = { 1, 15, 10 },
    ZombieEngageScout = { 1, 15, 10 },
    ZombieEngageMedic = { 1, 15, 10 },
    ZombieEngageWorker = { 1, 15, 10 },
    ZombieEngageBreaker = { 1, 15, 10 },
    DefenseRadius = { 3, 30, 8 },            -- Defense.CFG.THREAT_RADIUS 12
    DefenseWithdrawRatio = { 2, 10, 3 },     -- Defense.CFG.WITHDRAW_RATIO 3 (retour aux postes : rapport - 1)
    RetreatDangerDistance = { 2, 30, 8 },    -- Decisions.CFG.RETREAT.DIST 15
    ReinforcementRadius = { 3, 50, 15 },     -- Decisions.CFG.HELP.RADIUS 20
    WarnHomeRadius = { 4, 30, 14 },          -- Encounters.CFG.HOME_ZONE 14 (sécurité : la moitié)
    WarnGroupRadius = { 2, 30, 10 },         -- Encounters.CFG.MEMBER_ZONE 10 (sécurité : la moitié)
}
Config.dangerWarned = Config.dangerWarned or {}

-- Seuils « blessé » et « apeuré » réglables (LK05-T16, fiche docs/conception/decisions.md, section « Seuils blessé et
-- apeuré réglables ») : options sandbox entières LivingKnox.<nom>, lues comme Config.DANGER (Config.danger, même
-- repli). { min, max, défaut } = min / max / default de sandbox-options.txt (vérifié par tests/test_lk_fitness.py).
-- Une seule notion par option, partout où le moteur l'emploie (LK_Decisions : Decisions.woundRatio, Decisions.fearHigh).
Config.FITNESS = {
    WoundedHealth = { 10, 90, 50 },          -- % de la santé de naissance : Decisions.CFG.WOUND_RATIO 0,5
    AfraidFear = { 30, 100, 70 },            -- peur 0..100 : Decisions.CFG.NEED_HIGH.fear 70
}

-- Seuil name (Config.DANGER ou Config.FITNESS) : valeur de l'option, ou fallback si elle est absente ou invalide (une
-- ligne d'avertissement par valeur invalide).
function Config.danger(name, fallback)
    local spec = Config.DANGER[name] or Config.FITNESS[name]
    if spec == nil then return fallback end
    local value = Config.readRaw(name)
    if value == nil then return fallback end
    if not isInt(value, spec[1], spec[2]) then
        local key = name .. "=" .. tostring(value)
        if not Config.dangerWarned[key] then
            Config.dangerWarned[key] = true
            warn("option %s.%s = %s is not an integer from %d to %d, previous value %s used", Config.NAMESPACE, name,
                tostring(value), spec[1], spec[2], tostring(fallback))
        end
        return fallback
    end
    return value
end

-- LK06-T14 : option de portée d'engagement des zombies de chaque rôle (Config.GROUP_ROLES) ; un rôle inconnu (autre
-- mod, rôle absent) prend celle de fighter (Config.zombieEngageOption).
Config.ZOMBIE_ENGAGE = { deputy = "ZombieEngageDeputy", fighter = "ZombieEngageFighter", scout = "ZombieEngageScout",
    medic = "ZombieEngageMedic", worker = "ZombieEngageWorker", breaker = "ZombieEngageBreaker" }

function Config.zombieEngageOption(role)
    return Config.ZOMBIE_ENGAGE[role] or Config.ZOMBIE_ENGAGE.fighter
end

-- Distance maximale (cases, du membre qui le perçoit) d'un zombie qui compte comme menace, ou nil (aucune limite).
function Config.zombieAlertDistance()
    return Config.danger("ZombieAlertDistance", nil)
end

-- Groupes (LK08-T01, fiche docs/conception/groupes.md) : liste fermée lue par LK_Groups et LK_GroupTypes à chaque appel.
-- Les types de groupes ne sont plus listés ici : registre LivingKnox.GroupTypes, rempli par des fichiers de données
-- (LK08-T02, media/lua/shared/LivingKnox/Data/).
-- GROUP_ROLES : rôles des membres, dans l'ordre de priorité de la succession du chef (le premier d'abord). Un rôle
-- nouveau s'ajoute EN FIN de liste (l'ordre des rôles existants, donc la succession des groupes relus, ne change pas) ;
-- un rôle retiré rendrait invalides les groupes qui l'emploient. breaker (casseur de barricades, I6.9) : LK08-T02.
Config.GROUP_ROLES = Config.GROUP_ROLES or { "deputy", "fighter", "scout", "medic", "worker", "breaker" }

-- Simulation abstraite hors écran (LK09-T01, fiche docs/conception/simulation.md) : taux par heure de jeu, seuils
-- sur 0..100. Valeurs de départ propres au mod (raisons dans la fiche), à recalibrer en jeu. Lues à chaque pas.
Config.SIMULATION = Config.SIMULATION or {
    MAX_CATCHUP_HOURS = 72,      -- rattrapage au plus (heures manquantes au-delà : ignorées et journalisées)
    SEED = nil,                  -- graine fixe (entier) ; nil = dérivée du mode et du nom de la partie
    -- Consommation par membre vivant et par heure (arrondi aléatoire reproductible) : 6 membres mangent ~11.5/jour.
    FOOD_PER_MEMBER = 0.08,
    AMMO_PER_MEMBER = 0.02,
    -- Seuils des réserves : LOW = manque (moral en baisse, fouille prioritaire) ; OK = correctes (moral remonte).
    NEED_LOW = 25,
    NEED_OK = 40,
    NEED_TARGET = 60,            -- en dessous, une réserve justifie une fouille de jour
    -- Moral par heure.
    MORALE_LOW_NEED = -0.5,      -- par réserve sous NEED_LOW
    MORALE_TIRED = -0.5,         -- repos sous REST_LOW
    MORALE_GOOD = 0.1,           -- toutes réserves >= NEED_OK et repos >= REST_OK (~2.4 par jour)
    MORALE_STARVING = -1,        -- nourriture à 0
    MORALE_DEATH = -10,          -- par membre mort
    -- Repos du groupe (0..100) par heure ; nuit = de NIGHT_START à NIGHT_END (heure du jour, 0..23).
    NIGHT_START = 22,
    NIGHT_END = 6,
    REST_GAIN = 6,               -- tâche « rest »
    REST_DAY_LOSS = -2,          -- autre tâche, de jour
    REST_SCAVENGE_LOSS = -4,     -- tâche « scavenge »
    REST_LOW = 25,
    REST_OK = 50,
    -- Blessures abstraites par membre (0..100, mort à WOUND_DEATH).
    WOUND_DEATH = 100,
    WOUND_MINOR = 20,            -- en dessous : guérit seule (WOUND_SELF_HEAL)
    WOUND_SERIOUS = 40,          -- au-dessus : la tâche « heal » passe en tête
    WOUND_SELF_HEAL = -0.25,
    WOUND_HEAL = -1,             -- avec des soins (medical > 0), doublé par la tâche « heal »
    WOUND_WORSEN = 0.5,          -- sans soins, au-dessus de WOUND_MINOR
    WOUND_STARVING = 0.3,        -- chaque membre vivant quand la nourriture est à 0
    MEDICAL_PER_HEAL = 0.25,     -- soins consommés par membre soigné et par heure
    WOUND_CHANCE = 0.002,        -- chance par membre et par heure d'une blessure (~5 % par jour)
    WOUND_CHANCE_SCAVENGE = 0.01, -- pendant une fouille
    WOUND_MIN = 10,
    WOUND_MAX = 40,
    -- Fouille (tâche « scavenge ») : gain par heure tiré de 0 à SCAVENGE_MAX, sur la réserve la plus basse.
    SCAVENGE_MAX = 3,
    -- Expéditions abstraites (LK09-T02, fiche simulation.md, section « Expéditions ») : une équipe part vers un type de
    -- lieu quand une réserve est basse ; résultats tirés à son retour. Toutes les valeurs sont bornées à la lecture
    -- (probabilités 0..1, entiers dans leurs bornes ; valeur non numérique = borne basse, lieu malformé ignoré).
    EXPEDITIONS = {
        NEED_TRIGGER = 35,       -- tâche « scavenge » et réserve la plus basse sous ce seuil : expédition possible
        DEPART_CHANCE = 0.25,    -- chance par heure éligible de partir (0 = jamais, 1 = dès la première heure)
        TEAM_MIN = 2,            -- équipe : 1..32 membres vivants, au foyer, hors chef, blessure < WOUND_MINOR
        TEAM_MAX = 4,
        MIN_HOME = 2,            -- membres vivants qui restent au foyer (1..32 ; chef compris)
        -- Ordre de choix de l'équipe (puis ancienneté) ; un rôle absent de la liste passe en dernier.
        TEAM_ROLES = { "scout", "fighter", "worker", "breaker", "medic", "deputy" },
        -- Sécurité : risque effectif = risk x (1 - somme des bonus des rôles de l'équipe, plafonnée à SAFETY_MAX).
        ROLE_SAFETY = { fighter = 0.15, scout = 0.1, deputy = 0.1, breaker = 0.05 },
        SAFETY_MAX = 0.5,
        -- Rendement : gain moyen = yield x survivants x (1 + bonus des rôles, plafonné à YIELD_BONUS_MAX).
        ROLE_YIELD = { scout = 0.15, worker = 0.1, breaker = 0.1 },
        YIELD_BONUS_MAX = 0.5,
        DEATH_SHARE = 0.2,       -- part des incidents (chance = risque effectif par membre) qui sont mortels
        WOUND_MIN = 15,          -- blessure d'un incident non mortel (bornée à WOUND_DEATH - 1)
        WOUND_MAX = 45,
        MORALE_RETURN = 2,       -- retour sans perte avec un gain ; chaque mort : MORALE_DEATH
        -- Lieux (liste fermée, ordre = ordre de tirage) : durée en heures de jeu (1..72), risque d'incident par
        -- membre (0..1), chance d'une recrue au retour (0..1), gain moyen par survivant et par réserve (0..100).
        -- Lieu choisi au hasard selon son rendement sur la réserve la plus basse.
        PLACES = {
            { id = "houses", hoursMin = 4, hoursMax = 8, risk = 0.1, recruit = 0.04,
                yield = { food = 4, medical = 1, ammo = 0.5 } },
            { id = "stores", hoursMin = 6, hoursMax = 10, risk = 0.2, recruit = 0.05,
                yield = { food = 6, medical = 1, ammo = 0.5 } },
            { id = "pharmacy", hoursMin = 4, hoursMax = 8, risk = 0.25, recruit = 0.03,
                yield = { food = 0.5, medical = 6, ammo = 0 } },
            { id = "police", hoursMin = 6, hoursMax = 10, risk = 0.35, recruit = 0.03,
                yield = { food = 0.5, medical = 1, ammo = 6 } },
            { id = "farm", hoursMin = 8, hoursMax = 12, risk = 0.08, recruit = 0.06,
                yield = { food = 5, medical = 0, ammo = 0.5 } },
            { id = "forest", hoursMin = 8, hoursMax = 14, risk = 0.05, recruit = 0.02,
                yield = { food = 3, medical = 0.5, ammo = 0 } },
        },
    },
    -- Événements de groupe (LK09-T05, fiche simulation.md, section « Événements ») : liste fermée (departure,
    -- recruit, conflict, illness, clash), un tirage par groupe et par jour à l'heure HOUR, au plus un événement par
    -- groupe et par jour. Chances par jour (0..1), sommées puis plafonnées à MAX_DAILY. Toutes les valeurs sont
    -- bornées à la lecture (valeur non numérique : 0 ramené dans ses bornes, donc chance nulle) ; EVENTS absent :
    -- aucun événement ; sous-table d'un événement absente : cet événement seul désactivé.
    EVENTS = {
        HOUR = 12,               -- heure du jour (0..23) du tirage quotidien
        MAX_DAILY = 0.5,         -- somme des chances du jour plafonnée (proportions conservées)
        -- Départ d'un membre (jamais le chef, ni un membre lié à un PNJ, ni un absent) quand le moral est bas :
        -- chance = CHANCE x (MORALE_MAX - moral) / MORALE_MAX ; au moins MIN_LEFT vivants restent.
        DEPARTURE = { CHANCE = 0.2, MORALE_MAX = 30, MIN_LEFT = 2, MORALE = -4 },
        -- Un survivant rejoint le groupe (profil tiré du type, bornes size.max et MAX_MEMBERS comme LK09-T02).
        RECRUIT = { CHANCE = 0.03, FOOD_MIN = 40, MORALE_MIN = 40, MORALE = 2 },
        -- Conflit interne : moral bas (sous MORALE_MAX) ou réserve sous NEED_LOW ; chance = CHANCE + CHANCE_LOW_NEED
        -- par réserve basse. Moral MORALE, blessure légère possible, chef contesté au journal seulement.
        CONFLICT = { CHANCE = 0.02, CHANCE_LOW_NEED = 0.03, MORALE_MAX = 50, MIN_MEMBERS = 2, MORALE = -6,
            WOUND_CHANCE = 0.3, WOUND_MIN = 5, WOUND_MAX = 15, CONTEST_CHANCE = 0.25 },
        -- Maladie : chance = CHANCE (+ CHANCE_HUNGRY si nourriture sous NEED_LOW) ; un malade, puis chaque autre
        -- membre au foyer avec SPREAD, MAX_SICK au plus ; blessure WOUND_MIN..WOUND_MAX (moitié si soigné :
        -- MEDICAL_PER_SICK consommé par malade soigné, tant qu'il en reste).
        ILLNESS = { CHANCE = 0.02, CHANCE_HUNGRY = 0.04, SPREAD = 0.25, MAX_SICK = 3, WOUND_MIN = 10, WOUND_MAX = 25,
            MEDICAL_PER_SICK = 3, MORALE = -3 },
        -- Combat abstrait (I9.1) d'un groupe d'un type ATTACKERS contre un groupe d'un autre type : deux foyers
        -- connus à MAX_DISTANCE cases au plus, chacun à PLAYER_DISTANCE cases au moins de toute base connue
        -- (RS_Rescue.knownBases : refuges, joueurs connectés ou locaux). Issue selon les effectifs au foyer.
        CLASH = { CHANCE = 0.05, CHANCE_NEEDY = 0.05, ATTACKERS = { "raiders" }, MAX_DISTANCE = 2000,
            PLAYER_DISTANCE = 300, MIN_FORCE = 2, DEFENSE_BONUS = 1.25, LOSS_WIN = 0.05, LOSS_LOSE = 0.2,
            WOUND_WIN = 0.2, WOUND_LOSE = 0.4, MAX_DEATHS = 3, WOUND_MIN = 15, WOUND_MAX = 40, LOOT_SHARE = 0.25,
            LOOT_MAX = 20, AMMO_COST = 4, MORALE_WIN = 3, MORALE_LOSE = -8, PLACE_ROUND = 10 },
    },
}

-- Attitude d'un groupe envers un personnage joueur (LK11-T03, fiche docs/conception/attitude.md, LK_Hostility.lua).
-- Valeur interne -100..100, jamais affichée ni rendue par l'API ; seuls le niveau et la tendance sortent. Valeurs de
-- départ propres au mod, à recalibrer en jeu ; lues à chaque appel et bornées à la lecture (valeur non numérique :
-- valeur de repli du module ; seuils non croissants : seuils de repli).
Config.ATTITUDE = Config.ATTITUDE or {
    -- Valeur de départ = arrondi de (50 - hostilité du type) x START_SCALE (hostilité 0..100 des données de type) :
    -- colons (10) = 50 favorable, neutres (45) = 6 prudent, pillards (90) = -50 hostile.
    START_SCALE = 1.25,
    -- Seuil bas de chaque niveau (décision E09-T01 : hostile, méfiant, prudent, favorable, confiant) ; hostile = tout
    -- ce qui est sous WARY. Strictement croissants, dans -99..100.
    LEVEL_MIN = { wary = -44, cautious = -14, favorable = 15, trusting = 60 },
    -- Effet de chaque fait (liste fermée de LK_Hostility.FACTS), borné à +-EFFECT_MAX (0..200).
    EFFECTS = {
        gift = 8, heal = 12, delivery = 10,            -- aide : don, soin, livraison
        hit = -15, shot = -25,                         -- agression : coup, tir sur un membre
        kill = -60,                                    -- mort d'un membre causée (meurtre : plafond du déclin)
        theft = -20,                                   -- vol constaté (I5.2)
        mission_success = 15, mission_failure = -10,   -- mission pour le groupe
    },
    EFFECT_MAX = 60,
    -- Retour lent vers la valeur de départ (I9.4) : DECAY_PER_DAY points par jour de jeu (0..50), au plus
    -- DECAY_MAX_DAYS jours rattrapés par appel (1..365). Après un meurtre, le déclin ne remonte jamais au-dessus de
    -- MURDER_CAP (-100..100) ; les actes (aide, missions) le peuvent.
    DECAY_PER_DAY = 2,
    DECAY_MAX_DAYS = 30,
    MURDER_CAP = -15,
}

-- Rapports d'état d'un corps (LK03-T02, fiche docs/conception/rapports.md, LK_Reports.lua et LK_Executor.lua) :
-- seuils de plausibilité côté autorité et cadence d'envoi côté exécutant. Lus à chaque appel. MAX_SPEED, SLACK et
-- MAX_GAP servent aussi aux rapports d'exécution des consignes (LK_Directives.lua).
Config.REPORTS = Config.REPORTS or {
    -- Déplacement horizontal entre deux rapports acceptés : au plus SLACK + MAX_SPEED x durée (s). Course mesurée à
    -- 4,78 cases/s (lk.milestone1, docs/validation/jalon1-2026-10-09.md, section 5), marche à 2,3 ; le moteur refuse
    -- un joueur à pied au-delà de 20 cases/s mesurées sur 1 s (J/network/anticheats/AntiCheatSpeed.java:16, 33 ;
    -- J/characters/NetworkCharacterAI.java:339-376). 8 = 1,7 fois la course mesurée.
    MAX_SPEED = 8,
    SLACK = 3,                 -- cases : gigue réseau (livraison regroupée), poussée, premier rapport
    -- Écart au plus avec la copie du serveur. Le propriétaire n'envoie la position d'un zombie que toutes les 4 s
    -- (J/network/GameClient.java:207 sendZombieTimer, J/iso/IsoCell.java:3531, J/popman/NetworkZombieSimulator.java
    -- send ; plus tôt seulement à un changement d'état) et la copie du serveur ne la rattrape qu'à chaque paquet
    -- (J/characters/NetworkZombieAI.java parse : saut au-delà de 3 cases) : retard jusqu'à 4 s de course. 6 cases
    -- refusaient des rapports légitimes en course (6,0 à 6,3 cases, campagne MP du 2026-10-14). SLACK + course
    -- mesurée x 4 s = 3 + 4,78 x 4 = 22 ; le déplacement entre deux rapports reste borné par MAX_SPEED.
    MAX_GAP = 22,
    MAX_LEVEL_GAP = 1,         -- niveaux : écart au plus avec le niveau de la copie du serveur
    -- Changement de niveau entre deux rapports acceptés (z flottant, escaliers compris) : montée au plus
    -- CLIMB_SLACK + CLIMB_RATE x durée ; descente au plus FALL_SLACK + max(CLIMB_RATE x durée, FALL_ACCEL / 2 x
    -- durée^2). Chute du moteur : vitesse + 5,001 niveaux/s par seconde, distance 2,5 x dt^2
    -- (J/characters/IsoGameCharacter.java:8679-8685, dt = GameTime.getTimeDelta, secondes à vitesse normale) ;
    -- volée d'escalier = 1 niveau sur 3 cases (0,6 s à la course mesurée).
    CLIMB_RATE = 2,
    CLIMB_SLACK = 0.5,
    FALL_ACCEL = 6,
    FALL_SLACK = 1,
    -- Bornes des valeurs : niveaux -32..31 (base map-files.md) ; santé 0..32,767 (short x 1000 du paquet zombie,
    -- docs/conception/sante.md, J/network/packets/character/ZombiePacket.java:58, 112) ; coordonnées 0..COORD_MAX.
    Z_MIN = -32,
    Z_MAX = 31,
    HP_MAX = 32.767,
    HP_EPSILON = 0.002,        -- précision du short x 1000, plus un arrondi
    COORD_MAX = 1000000,
    -- Cadence acceptée par PNJ (seau à jetons) : RATE rapports par seconde, BURST d'avance.
    RATE = 5,
    BURST = 10,
    WARN_EVERY_MS = 60000,     -- une ligne par (expéditeur, raison) au plus par minute
    -- Exécutant : un rapport par PNJ au plus toutes les STATE_MS s'il a bougé (MOVED cases) ou si sa santé a changé,
    -- tout de suite (au plus toutes les MIN_MS) si son activité ou sa pose change, sinon toutes les IDLE_MS.
    STATE_MS = 1000,
    MIN_MS = 250,
    IDLE_MS = 5000,
    MOVED = 0.1,
}

-- Retrait des corps loin des joueurs (LK03-T04, fiche docs/conception/corps-registre.md, « Retrait loin des
-- joueurs », LK_Bodies.lua : Bodies.releasePass). Lus à chaque passage. Un corps de PNJ dont aucun joueur vivant n'est
-- à RELEASE_RADIUS cases ou moins (écart en x et en y, niveaux ignorés, comme la portée réseau du moteur) pendant
-- RELEASE_DELAY_MS d'affilée est retiré ; le PNJ repasse en simulation abstraite (LK09).
--   RELEASE_RADIUS : au-delà de la portée réseau d'un client (64 à 96 cases, J/network/GameServer.java:2615-2616),
--   du rayon d'envoi des consignes (Directives.NEAR_RADIUS = 100) et de la zone chargée en solo (79 cases au plus,
--   J/iso/IsoChunkMap.java:131-139) : aucun client ne voit ni ne simule le corps, aucun ne détient sa consigne ; la
--   marge de 20 cases évite qu'un joueur au bord du rayon fasse alterner retrait et réapparition.
--   RELEASE_DELAY_MS : plus long qu'un tour complet du balayage des corps (2 000 zombies en ≈ 8 s), qu'une
--   reconnexion (liste des joueurs vide un moment) ou qu'un aller-retour au bord du rayon.
--   RELEASE_GAP_MS : un écart plus long entre deux passages (pause, serveur figé) remet les délais à zéro.
Config.BODIES = Config.BODIES or {
    RELEASE_RADIUS = 120,
    RELEASE_DELAY_MS = 60000,
    RELEASE_GAP_MS = 10000,
}

-- Matérialisation des groupes à l'approche d'un joueur (LK09-T03, fiche docs/conception/corps-registre.md,
-- « Matérialisation », server/LivingKnox/LK_Materialize.lua). Lus à chaque passage.
--   RADIUS : un joueur vivant à RADIUS cases ou moins du foyer (écart en x et en y, niveaux ignorés) déclenche la
--   matérialisation des membres présents ; PLACE_RADIUS : cases autour du foyer où les corps sont posés. Hystérésis
--   avec le retrait (BODIES.RELEASE_RADIUS = 120, après 60 s) : RADIUS + PLACE_RADIUS = 88 < 120, un corps posé n'est
--   jamais à portée de retrait tant que le joueur qui l'a fait naître reste à RADIUS du foyer ; entre 80 et 120 cases,
--   rien ne change (ni création, ni retrait). RADIUS <= 80 : zone chargée d'un client solo (79 cases au plus,
--   J/iso/IsoChunkMap.java:131-139) ; le foyer doit de toute façon être chargé.
--   MAX_PER_GROUP / MAX_TOTAL : corps de membres de groupe au plus par groupe et en tout (Bodies.MAX_EMBODIED = 50
--   reste la borne de tous les PNJ) ; PER_PASS : corps créés au plus par passage (une tranche de balayage, 15 images :
--   0,25 s en solo à 60 images/s, 1,5 s sur un serveur dédié à 10 images/s).
--   FULL_HEALTH : santé de référence d'un corps dont la santé de naissance est inconnue (corps créé avant LK09-T03) ;
--   1,8 = robustesse « normale » vanilla (docs/conception/sante.md).
Config.MATERIALIZE = Config.MATERIALIZE or {
    RADIUS = 80,
    PLACE_RADIUS = 8,
    MAX_PER_GROUP = 8,
    MAX_TOTAL = 24,
    PER_PASS = 2,
    FULL_HEALTH = 1.8,
}

-- Relais des gestes et des poses vers les clients (LK03-T05, server/LivingKnox/LK_Relay.lua, fiche
-- docs/conception/corps-et-animations.md, « Relais des gestes »). Lus à chaque image du serveur.
--   Destinataires : ceux des consignes (Directives.targets : joueurs à NEAR_RADIUS = 100 cases, et le propriétaire).
--   WINDOW_MS : un état publié par PNJ au plus par fenêtre (cadence <= 1000 / WINDOW_MS par PNJ) ; les changements
--   d'une même fenêtre sont regroupés (dernier état gagnant). Un serveur dédié tourne à 10 images par seconde
--   (J/network/GameServer.java:261, 835-836 : UpdateLimit(100)) : délai d'émission <= WINDOW_MS + une image
--   (100 ms) = 250 ms, sous les 300 ms visés avec le réseau local.
--   MAX_PER_TICK : messages de gestes émis par image du serveur, tous clients confondus (un message par client et par
--   image, tous ses PNJ regroupés) ; au-delà, différés à l'image suivante dans l'ordre d'attente.
--   SCAN_EVERY : images entre deux recalculs des destinataires (joueur entré dans le rayon ou sorti) ; 10 = 1 s.
--   KEEP_GESTURES : gestes ponctuels importants, jamais écrasés par le regroupement (publiés avant l'état suivant) ;
--   les poses finales (arrived, stopped, faced, failed) le sont aussi. MAX_KEPT : en attente au plus par PNJ.
Config.RELAY = Config.RELAY or {
    WINDOW_MS = 150,
    MAX_PER_TICK = 16,
    SCAN_EVERY = 10,
    KEEP_GESTURES = { strike = true, force = true, openwindow = true, closewindow = true },   -- LK04-T13, T04
    MAX_KEPT = 4,
}

-- Foyer d'un membre parti (E10-T05, fiche docs/conception/depart.md, « Foyer du solitaire ») : RS_LivingKnox.leave tire
-- le foyer dans l'anneau HOME_MIN..HOME_MAX cases (distance euclidienne) autour de l'ancien foyer, élargi par paliers
-- (LivingKnox.Sites.CONFIG.NEAR_WIDEN : x 2, puis x 4) avant la carte entière. Lus à chaque départ.
--   HOME_MIN = Sites.CONFIG.GROUP_DISTANCE (400) : l'ancien foyer reste soumis à la règle commune des foyers.
--   HOME_MAX = 2 x Sites.CONFIG.BASE_DISTANCE (600) : le joueur qui parle au PNJ, près de l'ancien foyer, est une base
--   (Rescue.knownBases) ; l'anneau garde au moins 600 cases de large au-delà de ce rayon, à l'échelle d'une ville.
Config.LEAVE = Config.LEAVE or {
    HOME_MIN = 400,
    HOME_MAX = 1200,
}

-- Raids des pillards (LK11-T07, fiche docs/conception/raids.md) : { enabled, days } lus à chaque appel ; days = jours
-- de jeu au moins entre deux raids (départs des éclaireurs) et avant le premier. Lu à chaque heure simulée de chaque
-- groupe : option absente (banc, page non chargée) = valeur par défaut sans avertissement ; invalide = valeur par
-- défaut, un avertissement par valeur.
function Config.raids()
    local on = Config.readRaw("RaidsEnabled")
    if type(on) ~= "boolean" then on = Config.DEFAULTS.RaidsEnabled end
    local days, b = Config.readRaw("RaidDays"), Config.INT_BOUNDS.RaidDays
    if days == nil then
        days = Config.DEFAULTS.RaidDays
    elseif not isInt(days, b[1], b[2]) then
        local key = "RaidDays=" .. tostring(days)
        if not Config.dangerWarned[key] then
            Config.dangerWarned[key] = true
            warn("option %s.RaidDays = %s is not an integer from %d to %d, default %d used", Config.NAMESPACE,
                tostring(days), b[1], b[2], Config.DEFAULTS.RaidDays)
        end
        days = Config.DEFAULTS.RaidDays
    end
    return { enabled = on, days = days }
end

function Config.isEnabled()
    return Config.read("Enabled") == true
end

function Config.isDebug()
    return Config.read("Debug") == true
end

return Config
