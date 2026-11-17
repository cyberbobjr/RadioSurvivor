-- Living Knox : stock du groupe, socle commun (LK20-T08 : sorti de LK_Stock.lua sans changement de comportement) :
-- table LivingKnox.Stock, formats, kits, réglages CFG, SUPPLY et OFFSCREEN, état en mémoire et compteurs, et table
-- privée Stock._ des fonctions partagées entre les fichiers de Stock/. Chaque fichier du stock le requiert en
-- premier : il se charge donc dans n'importe quel ordre (le jeu lit LK_Stock.lua avant Stock/, par nom ; la façade
-- requiert chaque fichier, et le jeu n'exécute jamais deux fois le même fichier).
-- Façade et vue d'ensemble : LK_Stock.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"
require "LivingKnox/LK_Hostility"
require "LivingKnox/LK_Simulation"   -- LK16-T09 : passe horaire (registerHourly)

local Stock = LivingKnox.Stock or {}
LivingKnox.Stock = Stock
-- LK20-T08 : fonctions privées partagées entre les fichiers de Stock/ (cfg, now, puis celles que chaque fichier y
-- range à sa fin) ; même table d'un chargement à l'autre.
Stock._ = Stock._ or {}
local P = Stock._

Stock.FORMAT = 1
Stock.TAG = "LKStock"
Stock.CATEGORIES = { "food", "water", "medical", "ammo", "materials" }
Stock.MAX_ITEMS = 128
Stock.TYPE_MAX = 128
Stock.KEY_MAX = 96
Stock.OP_TAG = "LKStockOp"              -- LK09-T06 : marque d'application d'un objet créé d'après le journal d'écarts
Stock.PEND_MAX = 2 * Stock.MAX_ITEMS    -- LK09-T06 : écarts en attente au plus (prises <= MAX_ITEMS, ajouts aussi)

-- LK09-T06 : stock hors écran (valeurs de départ propres au mod, à recalibrer en jeu).
Stock.OFFSCREEN = Stock.OFFSCREEN or {
    MEAL_HOUR = 18,         -- heure du jour du repas abstrait quotidien (une fois par jour simulé)
    LEVEL_PER_ITEM = 5,     -- points de réserve abstraite gagnés (LK09-T02) par objet rapporté
    -- Objets vanilla 42.21 du butin abstrait (pris tour à tour d'après le numéro d'écart), sans périssable.
    ITEMS = {
        food = { "Base.TinnedBeans", "Base.CannedCorn", "Base.TinnedSoup" },
        water = { "Base.WaterBottle" },
        medical = { "Base.Bandage", "Base.Pills" },
        ammo = { "Base.Bullets9mmBox", "Base.ShotgunShellsBox" },
        materials = { "Base.NailsBox", "Base.DuctTape" },
    },
}

-- DisplayCategory du script -> catégorie (l'eau se reconnaît à son fluide, avant).
Stock.DISPLAY = {
    Food = "food",
    FirstAid = "medical",
    Bandage = "medical",
    Ammo = "ammo",
    Material = "materials",
    MaterialWeapon = "materials",
}

-- Kits du remplissage initial par type de groupe (objets vanilla 42.21, media/scripts/generated/items : conserves
-- et biscuits sans DaysFresh, bouteilles d'eau remplies, soins, munitions, matériaux) ; un type sans kit reçoit
-- DEFAULT_KIT. Entrée : { type complet, nombre, fill = nom du fluide facultatif }.
Stock.DEFAULT_KIT = "settlers"
Stock.KITS = Stock.KITS or {
    settlers = {
        { "Base.TinnedBeans", 2 }, { "Base.CannedCorn", 2 }, { "Base.TinnedSoup", 2 },
        { "Base.WaterBottle", 3, fill = "Water" },
        { "Base.Bandage", 3 }, { "Base.Pills", 1 }, { "Base.Disinfectant", 1 },
        { "Base.Bullets9mmBox", 1 },
        { "Base.NailsBox", 1 }, { "Base.Rope", 1 }, { "Base.DuctTape", 1 },
    },
    raiders = {
        { "Base.TinnedBeans", 2 }, { "Base.CannedChili", 2 },
        { "Base.WaterBottle", 2, fill = "Water" },
        { "Base.Bandage", 2 }, { "Base.AlcoholWipes", 1 },
        { "Base.Bullets9mmBox", 1 }, { "Base.ShotgunShellsBox", 2 },
        { "Base.ScrapMetal", 2 }, { "Base.DuctTape", 1 },
    },
    neutrals = {
        { "Base.CannedPeas", 2 }, { "Base.TinnedSoup", 2 }, { "Base.Crackers", 1 },
        { "Base.WaterBottle", 3, fill = "Water" },
        { "Base.Bandage", 2 }, { "Base.Pills", 1 },
        { "Base.ShotgunShellsBox", 1 },
        { "Base.NailsBox", 1 }, { "Base.Rope", 1 },
    },
}

Stock.CFG = Stock.CFG or {
    SCAN_MS = 1000,               -- examen depuis LoadChunk au plus une fois par seconde
    CHECK_MS = 2000,              -- relecture d'un même groupe au plus toutes les 2 s (temps réel)
    THEFT_COOLDOWN_HOURS = 1,     -- un vol rapporté au plus une fois par heure de jeu, par groupe et par joueur
    SHORTAGE_HOURS = 6,           -- LK05-T07 : pénurie au journal au plus une fois par 6 h de jeu, groupe, catégorie
}

-- LK08-T07 : seuils, autonomie et rationnement (valeurs de départ propres au mod, à recalibrer en jeu).
Stock.SUPPLY = Stock.SUPPLY or {
    DAILY = { food = 1, water = 1 },                       -- portions par membre vivant et par jour
    TARGET_DAYS = 3,                                       -- réserve visée des consommables, en jours
    PER_MEMBER = { medical = 1, ammo = 0.5, materials = 1 }, -- réserve visée des autres catégories, par membre vivant
    CRITICAL = 25,                                         -- niveau (0..100) sous lequel un besoin est critique
    RATION_DAYS = { 2, 1 },                                -- autonomie sous laquelle : réduit, strict
    RATION_MARGIN = 0.5,                                   -- jours d'avance pour revenir à un niveau plus doux
}
-- Niveaux de rationnement (indice = niveau + 1) et part d'une ration normale.
Stock.RATIONS = { "normal", "reduced", "strict", "out" }
Stock.PORTIONS = { 1, 0.75, 0.5, 0 }
-- Ordre des besoins : statut d'abord.
Stock.STATUS_ORDER = { empty = 1, critical = 2, low = 3 }

Stock.state = Stock.state or { checked = {}, lastScan = nil, lastTheft = {} }
Stock.stats = Stock.stats or { filled = 0, created = 0, checks = 0, thefts = 0, lost = 0 }
Stock.stats.meals = Stock.stats.meals or 0          -- LK05-T07 : objets pris par un membre pour manger ou boire
Stock.stats.shortages = Stock.stats.shortages or 0  -- LK05-T07 : pénuries écrites au journal du groupe
for _, k in ipairs({ "offMeals", "offEaten", "offShort", "offLoot", "applied", "removed", "gone", "made", "adopted" }) do
    Stock.stats[k] = Stock.stats[k] or 0            -- LK09-T06 : stock hors écran et application des écarts
end
function P.cfg() return Stock.CFG end
function P.now() return getTimestampMs() end
