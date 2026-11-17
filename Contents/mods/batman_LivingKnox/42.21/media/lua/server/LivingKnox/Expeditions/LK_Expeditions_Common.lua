-- Living Knox : expéditions, socle commun (LK20-T08 : sorti de LK_Expeditions.lua sans changement de
-- comportement) : table LivingKnox.Expeditions, phases, pièces promises, butin abstrait, réglages CFG, état en
-- mémoire et compteurs, et table privée Expeditions._ des fonctions partagées entre les fichiers du moteur.
-- Chaque fichier du moteur le requiert en premier : il se charge donc dans n'importe quel ordre (le jeu lit
-- Expeditions/ avant LK_Expeditions.lua, par nom ; la façade requiert chaque fichier, et le jeu n'exécute jamais
-- deux fois le même fichier). Les genres (LK_Exp_*.lua du même dossier) requièrent la façade.
-- Façade et vue d'ensemble : LK_Expeditions.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"
require "LivingKnox/LK_Stock"
require "LivingKnox/LK_Decisions"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_StopPlace"   -- LK18-T03 : places d'arrêt
require "LivingKnox/LK_Passage"   -- LK18-T01 : priorité de passage déclarée par la façade

local Ex = LivingKnox.Expeditions or {}
LivingKnox.Expeditions = Ex
-- LK20-T08 : fonctions privées partagées entre les fichiers du moteur (cfg, X, cut, inList, CATS, puis celles que
-- chaque fichier y range à sa fin) ; même table d'un chargement à l'autre.
Ex._ = Ex._ or {}
local P = Ex._

Ex.FORMAT = 1
Ex.PHASES = { out = true, search = true, back = true, away = true, deliver = true }
Ex.ACTIVE = { out = true, search = true, back = true }   -- membres menés par la cascade (comportement « expedition »)
Ex.PLACE = "trip"                                       -- lieu de l'expédition abstraite (LK_Simulation)
-- Pièces de la carte (RoomDef:getName, noms des distributions vanilla M/lua/server/Items/Distributions.lua) qui
-- promettent une catégorie du stock.
Ex.ROOMS = {
    food = { "kitchen", "grocery", "grocerystorage", "conveniencestore", "cornerstore", "gigamart", "generalstore",
        "zippeestore", "gasstore", "fossoil", "restaurantkitchen" },
    water = { "kitchen", "grocery", "grocerystorage", "conveniencestore", "cornerstore", "gigamart", "generalstore",
        "zippeestore", "gasstore", "fossoil", "liquorstore" },
    medical = { "bathroom", "pharmacy", "pharmacystorage", "medicalstorage", "hospitalroom" },
    ammo = { "gunstore", "gunstorestorage", "policestorage", "armysurplus", "bedroom" },
    materials = { "garagestorage", "shed", "toolstore", "storageunit", "warehouse" },
}
-- Butin abstrait (hors écran seulement) : objets vanilla 42.21 par catégorie (bouteille remplie d'eau).
Ex.ABSTRACT_ITEMS = {
    food = { "Base.TinnedBeans", "Base.CannedCorn", "Base.TinnedSoup" },
    water = { "Base.WaterBottle" },
    medical = { "Base.Bandage", "Base.Pills" },
    ammo = { "Base.Bullets9mmBox", "Base.ShotgunShellsBox" },
    materials = { "Base.NailsBox", "Base.DuctTape" },
}

-- Réglages (valeurs de départ propres au mod, raisons dans la fiche ; à recalibrer en jeu).
Ex.CFG = Ex.CFG or {
    TEAM_MAX = 2,              -- fourrageurs au plus par expédition
    TEAM_MIN = 1,
    MIN_HOME = 1,              -- membres vivants qui restent au foyer
    TEAM_HEALTH = 0.6,         -- santé (0..1) minimale pour partir
    DEPART_FROM = 7,           -- heure du jour : départ permis de 7 h
    DEPART_TO = 16,            -- ... à 16 h (exclue) : retour avant la nuit
    COOLDOWN_MINUTES = 240,    -- minutes de jeu entre la fin d'une expédition et le départ suivant
    CHECK_MINUTES = 10,        -- départ examiné au plus toutes les 10 minutes de jeu par groupe
    MIN_DIST = 6,              -- cases entre le foyer et le bâtiment visé (écart au rectangle)
    MAX_DIST = 45,             -- cases au plus (consigne move : Directives.MAX_TRIP = 60)
    MAX_BUILDINGS = 64,        -- bâtiments examinés au plus par départ
    MAX_CANDIDATES = 6,        -- bâtiments essayés (point visé chargé et libre) par départ
    SEEN_MAX = 8,              -- derniers bâtiments fouillés écartés
    ROOM_SCORE = 10,           -- points par catégorie promise (x rang du manque)
    DIST_WEIGHT = 0.5,         -- points retirés par case
    SPOT_RADIUS = 4,           -- cases : places libres autour du point visé
    SEARCH_RADIUS = 10,        -- cases autour du point visé : conteneurs fouillés
    MAX_CONTAINERS = 12,
    RUMMAGE_MINUTES = 2,       -- minutes de jeu de fouille par conteneur
    CLAIM_MINUTES = 15,        -- réservation rendue sans nouvelle de son membre
    CARRY_PER_MEMBER = 4,      -- objets portés par membre
    CARRY_MAX = 8,
    OUT_MINUTES = 120,         -- délais des phases (minutes de jeu)
    SEARCH_MINUTES = 60,
    BACK_MINUTES = 120,
    ABSTRACT_HOURS = { out = 3, search = 2, back = 1 },   -- heures hors écran restantes selon la phase quittée
    ABSTRACT_FIND = 0.5,       -- chance par membre et par catégorie manquante de rapporter un objet hors écran
}

Ex.state = Ex.state or { npcs = {}, claims = {}, sites = {}, carried = {}, checked = {} }
Ex.stats = Ex.stats or { departed = 0, refused = 0, arrived = 0, searched = 0, taken = 0, delivered = 0,
    deposited = 0, lost = 0, abstract = 0, resolved = 0, created = 0, dropped = 0, filled = 0 }
function P.cfg() return Ex.CFG end
function P.X() return LivingKnox.Routines.exec end

function P.cut(s) return string.sub(s, 1, LivingKnox.Groups.TEXT_MAX or 200) end

function P.inList(list, v)
    for _, x in ipairs(list or {}) do
        if x == v then return true end
    end
    return false
end

P.CATS = {}
for _, c in ipairs(LivingKnox.Stock.CATEGORIES) do P.CATS[c] = true end
