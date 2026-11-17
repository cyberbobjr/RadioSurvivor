-- Living Knox : fortification du foyer, socle commun (LK20-T07 : sorti de LK_Fortify.lua sans changement de
-- comportement) : table LivingKnox.Fortify, constantes des matériaux, réglages CFG, état en mémoire et compteurs,
-- ports vers les autres modules, et table privée Fortify._ des fonctions partagées entre les fichiers de Fortify/.
-- Chaque fichier de la fortification le requiert en premier : il se charge donc dans n'importe quel ordre (le jeu lit
-- Fortify/ avant LK_Fortify.lua, par nom ; la façade requiert ensuite chaque fichier, une seule fois).
-- Façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Homes"
require "LivingKnox/LK_Routines"
require "LivingKnox/LK_Simulation"   -- LK16-T09 : passe horaire (registerHourly)


local Fortify = LivingKnox.Fortify or {}
LivingKnox.Fortify = Fortify
LivingKnox.Fortification = Fortify   -- interface lue par LK_Decisions (levelOf)
-- LK20-T07 : fonctions privées partagées entre les fichiers de Fortify/ (cfg, Stock, now, settle, puis celles
-- que chaque fichier y range à sa fin) ; même table d'un chargement à l'autre.
Fortify._ = Fortify._ or {}
local P = Fortify._

Fortify.TIERS = { "ground", "upper", "outer" }
-- Rang des ouvertures dans un tier : cadre vide (trou), fenêtre, porte.
Fortify.OPENING_RANK = { frame = 1, window = 2, door = 3 }
Fortify.PLANK = "Base.Plank"
Fortify.NAILS = "Base.Nails"
Fortify.NAILS_BOX = "Base.NailsBox"
Fortify.LOG = "Base.Log"
Fortify.TIES = { "Base.RippedSheets", "Base.RippedSheetsDirty", "Base.Twine", "Base.Rope", "Base.SheetRope" }


Fortify.CFG = Fortify.CFG or {
    PLANKS = { ground = 4, upper = 2 },   -- planches visées par ouverture (4 = maximum vanilla, IsoBarricade.java:62-67)
    OUTER_MARGIN = 2,     -- cases entre le bâtiment et le pourtour des murs
    CAMP_RING = 7,        -- demi-côté du carré de la palissade d'un camp (tentes jusqu'à 6 cases du foyer, LK_Homes)
    GAP = 1,              -- segments laissés ouverts de part et d'autre du segment en face de l'entrée
    MAX_OUTER = 96,       -- segments au plus sur le pourtour
    MAX_OPENINGS = 64,    -- ouvertures relevées au plus
    WEIGHTS = { ground = 3, upper = 1, outer = 2 },
    TIME = { plank = 200, frame = 200, wall = 200, palisade = 200, repair = 1000 },   -- unités des actions vanilla
                          -- (repair : réparation d'un ouvrage, ISMoveableDefinitions.lua:656-662, LK14-T06)
    BOX_NAILS = 100,      -- clous d'une boîte (recette OpenBox100)
    PLAN_MS = 60000,      -- plan gardé en mémoire au plus une minute réelle
    -- LK14-T03 : pose des barricades.
    GESTURE = "hammer",   -- geste existant (nœud lkactor_hammer, clip vanilla Bob_IdleHammering de l'action Build)
    PLANK_MINUTES = 2,    -- minutes de jeu de travail avant chaque planche
    REST_MINUTES = 2,     -- chantier fini ou abandonné : pas de nouveau chantier avant
    IDLE_MINUTES = 10,    -- aucun chantier pour ce membre : nouvel essai après
    -- LK14-T04 : murs et palissade du pourtour.
    STAGE_MINUTES = 2,    -- minutes de jeu de travail avant chaque étape (cadre, mur, palissade : 200 unités chacune)
    RING_GESTURES = { wall = "hammer", palisade = "rummage" },   -- gestes existants (actions vanilla BuildWallHammer :
                          -- Build ; BuildWallNoTool : Loot, M/scripts/generated/timedactions.txt:828-858)
}
-- LK14-T06 : entretien et réparation (valeurs de départ propres au mod, à recalibrer en jeu).
Fortify.CFG.REPAIR_BELOW = Fortify.CFG.REPAIR_BELOW or 0.75   -- état (0..1) sous lequel planche ou ouvrage est réparé
Fortify.CFG.REPAIR_URGENT_MINUTES = Fortify.CFG.REPAIR_URGENT_MINUTES or 1440   -- après une attaque : réparations en tête
Fortify.CFG.REPAIR_MINUTES = Fortify.CFG.REPAIR_MINUTES or { barricade = 4, wall = 10, palisade = 10 }   -- minutes de
                          -- jeu de travail : retrait + pose d'une planche (200 + 200 unités) ; réparation vanilla 1000
Fortify.CFG.NEED_HOURS = Fortify.CFG.NEED_HOURS or 6   -- même besoin de matériaux au journal au plus toutes les 6 h

Fortify.state = Fortify.state or { plans = {} }
Fortify.state.rest = Fortify.state.rest or {}       -- LK14-T03 : npcId -> minute de jeu avant un nouveau chantier
Fortify.state.claims = Fortify.state.claims or {}   -- LK14-T03 : "gid|chantier" -> npcId qui y travaille
Fortify.stats = Fortify.stats or { surveys = 0, notReady = 0, changed = 0 }
for _, k in ipairs({ "started", "planks", "finished", "skipped", "boxes", "stages", "corners", "repairs", "needs" }) do
    Fortify.stats[k] = Fortify.stats[k] or 0   -- LK14-T03/T04/T06
end
Fortify.state.needs = Fortify.state.needs or {}   -- LK14-T06 : gid -> besoin de réparation { materials, tools, ... }

function P.cfg() return Fortify.CFG end

-- Ports (LK16-T04, A-A20, A-A21) : tout ce que la fortification lit hors d'elle dans le stock, la simulation, les
-- décisions et la défense, en un seul endroit. Adaptateurs par défaut liés au module à l'appel ; module absent : la
-- valeur neutre d'avant (stock nil, jour, non incarné, non matérialisé, minute nil, aucune attaque). Un banc ou une
-- racine de composition remplace un port : Fortify.ports.<nom> = fn.
Fortify.ports = {
    -- Stock du foyer (LK_Stock : reference, findItem, takeItem, check, validRef, offscreenTake...), ou nil.
    stock = function() return LivingKnox.Stock end,
    -- Vrai si l'heure du jour hourOfDay est de nuit (LK_Simulation.isNight).
    isNight = function(hourOfDay)
        local S = LivingKnox.Simulation
        return S ~= nil and S.isNight ~= nil and S.isNight(hourOfDay) or false
    end,
    -- Vrai si le membre m a un corps (LK_Simulation.isEmbodied).
    isEmbodied = function(m)
        local S = LivingKnox.Simulation
        return S ~= nil and S.isEmbodied ~= nil and S.isEmbodied(m) or false
    end,
    -- Vrai si le groupe g est matérialisé (LK_Simulation.materialized).
    materialized = function(g)
        local S = LivingKnox.Simulation
        return S ~= nil and S.materialized ~= nil and S.materialized(g) or false
    end,
    -- Minute de jeu courante (LK_Decisions.currentMinute), ou nil.
    currentMinute = function()
        local Dc = LivingKnox.Decisions
        return Dc ~= nil and Dc.currentMinute ~= nil and Dc.currentMinute() or nil
    end,
    -- Angle de la direction (dx, dy) (LK_Decisions.angleTo).
    angleTo = function(dx, dy) return LivingKnox.Decisions.angleTo(dx, dy) end,
    -- Marque de la dernière attaque repoussée du groupe gid (LK_Defense.after, LK05-T09), ou nil.
    attackMark = function(gid)
        local D = LivingKnox.Defense
        return D ~= nil and D.after ~= nil and D.after(gid) or nil
    end,
}
function P.Stock() return Fortify.ports.stock() end
-- LK13-T11 : relevé de la minute fait dans une image suivante avec l'heure de la minute (Fortify.clockAt, file
-- Fortify.minuteJobs, LK_Fortify_Queue.lua) : PLAN_MS compté comme si le relevé avait été fait dans l'image de la minute.
function P.now() return Fortify.clockAt or getTimestampMs() end
-- P.settle(gid) : LK13-T11, relevé en file du groupe gid fait tout de suite (défini avec la file, LK_Fortify_Queue.lua)
