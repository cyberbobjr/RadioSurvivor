-- Living Knox : portes et fenêtres sur le trajet des corps de PNJ, socle commun (LK20-T09 : sorti de
-- LK_Obstacles.lua sans changement de comportement) : table LivingKnox.Obstacles, réglages, état en mémoire et
-- compteurs, et table privée Obstacles._ des fonctions partagées entre les fichiers d'Obstacles/. Chaque fichier le
-- requiert en premier : il se charge donc dans n'importe quel ordre (le jeu lit LK_Obstacles.lua avant Obstacles/,
-- par nom ; la façade requiert chaque fichier, et le jeu n'exécute jamais deux fois le même fichier).
-- Façade et vue d'ensemble : LK_Obstacles.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Directives"
require "LivingKnox/LK_Groups"
require "LivingKnox/Edges/LK_Edges"

local Obstacles = LivingKnox.Obstacles or {}
LivingKnox.Obstacles = Obstacles
-- LK20-T09 : fonctions privées partagées entre les fichiers d'Obstacles/ (rangées par chaque fichier à sa fin) ;
-- même table d'un chargement à l'autre.
Obstacles._ = Obstacles._ or {}
local P = Obstacles._

Obstacles.PASS_EVERY = 5          -- images entre deux passages
Obstacles.DETECT = 2.0            -- cases : porte (milieu du bord) à cette distance du corps au plus
Obstacles.ALIGN = 0.75            -- cases : corps qui escalade à cette distance du milieu d'une fenêtre : son passant
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
    windowsClosed = 0, windowsBusy = 0, windowsGivenUp = 0, detoured = 0 }

local function now() return getTimestampMs() end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end
Obstacles.dist = dist

local function count(name)
    local st = Obstacles.stats
    st[name] = (st[name] or 0) + 1
end

-- Passage bloqué (LK04-T04, LK_Obstacles_Blocked.lua).
Obstacles.forcing = Obstacles.forcing or {}       -- npcId -> forçage en cours
Obstacles.waiting = Obstacles.waiting or {}       -- npcId -> attente en cours
Obstacles.forceOrders = Obstacles.forceOrders or {}   -- npcId -> { v } consigne explicite de forcer (un "move")
Obstacles.weapons = Obstacles.weapons or {}       -- type d'arme -> objet HandWeapon de l'autorité (false : aucun)

P.count = count
P.dist = dist
P.now = now
