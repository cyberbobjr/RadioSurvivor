-- Living Knox : entrée côté autorité (serveur dédié ou hébergé, solo).
-- Un client MP charge aussi media/lua/server : il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
require "LivingKnox/LK_Store"
require "LivingKnox/LK_Bodies"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Simulation"
require "LivingKnox/LK_Population"
require "LivingKnox/LK_Hostility"
require "LivingKnox/LK_Materialize"   -- LK09-T03 : appelé par Bodies.tick, Bodies.release, Bodies.onZombieDead
require "LivingKnox/LK_Needs"         -- LK05-T06 : faim, soif, fatigue, peur (lus par LK_Decisions)
require "LivingKnox/LK_Alert"         -- LK05-T08 : alerte de groupe (appelée par LK_Decisions)
require "LivingKnox/LK_Decisions"     -- LK05-T02 : cadre de décision (objectifs par heure, cascade par membre)
require "LivingKnox/LK_Routines"      -- LK05-T03 : postes, rondes, relèves et sommeil (appelé par LK_Decisions)
local WorldStart = require "RadioSurvivor/RS_WorldStart"   -- monde neuf : signal de la radio (serveur dédié)

local Server = LivingKnox.Server or {}
LivingKnox.Server = Server

function Server.onStart()
    local Config = LivingKnox.Config
    LivingKnox.Log.info("engine %s started (side=%s, enabled=%s, debug=%s)", LivingKnox.VERSION, LivingKnox.side(),
        tostring(Config.isEnabled()), tostring(Config.isDebug()))
end

-- Serveur : OnServerStarted (GameServer.startServer, après le chargement du monde et des options).
-- Solo : OnServerStarted n'existe pas, OnGameStart (IngameState.enter) part au chargement de la partie.
local function onStart()
    LivingKnox.Server.onStart()
end

LivingKnox.subscribe(isServer() and "OnServerStarted" or "OnGameStart", "Server.onStart", onStart)

-- Registre des PNJ : relu à l'initialisation de la partie (GlobalModData.java:56, avant la cellule). Monde neuf :
-- registre vide, même si un ancien fichier porte le même nom. isNewGame (WorldDictionary.isIsNewGame()) est toujours
-- vrai sur un serveur dédié : le monde neuf se lit par RS_WorldStart (signal d'OnLoadRadioScripts).
local function onInitGlobalModData(isNewGame)
    LivingKnox.Store.init(WorldStart.isNewWorld(isNewGame))
end

-- Registre des groupes (LK08-T01) : même moment, même règle de monde neuf ; fichier distinct (groups-...).
-- Population initiale (LK08-T05) : tentative de la session remise à zéro avec la relecture du registre.
local function onInitGroups(isNewGame)
    LivingKnox.Groups.init(WorldStart.isNewWorld(isNewGame))
    LivingKnox.Population.reset()
end

-- Corps : tranche de balayage borné (OnTick tourne aussi sur un serveur dédié ; à l'arrêt, sans joueur, rien à
-- relier), coups et mort d'un corps courant, positions vues écrites à la sauvegarde.
local function onTick()
    LivingKnox.Bodies.tick()
end

local function onZombieDead(zombie)
    LivingKnox.Bodies.onZombieDead(zombie)
end

-- Dernier coup d'un joueur sur un corps (E04-T06) : relevé avant les dégâts, lu à la mort.
local function onHitZombie(zombie, wielder, bodyPart, weapon)
    LivingKnox.Bodies.onHitZombie(zombie, wielder, bodyPart, weapon)
end

local function onSave()
    LivingKnox.Store.saveIfDirty()
end

LivingKnox.subscribe("OnInitGlobalModData", "Store.init", onInitGlobalModData)
LivingKnox.subscribe("OnInitGlobalModData", "Groups.init", onInitGroups)

-- Attitudes des groupes envers les joueurs (LK11-T03) : même moment, même règle de monde neuf ; fichier attitudes-...
local function onInitAttitudes(isNewGame)
    LivingKnox.Hostility.init(WorldStart.isNewWorld(isNewGame))
end

LivingKnox.subscribe("OnInitGlobalModData", "Hostility.init", onInitAttitudes)
LivingKnox.subscribe("OnTick", "Bodies.tick", onTick)
LivingKnox.subscribe("OnZombieDead", "Bodies.onZombieDead", onZombieDead)
LivingKnox.subscribe("OnHitZombie", "Bodies.onHitZombie", onHitZombie)
LivingKnox.subscribe("OnSave", "Store.onSave", onSave)

-- Population initiale (LK08-T05, LK_Population.lua) : une seule fois par monde, au démarrage de l'autorité, après
-- OnInitGlobalModData (registre relu), la métagrille et les refuges (lus de map_meta.bin avant OnServerStarted /
-- OnGameStart, base multiplayer.md) ; sinon au premier EveryHours qui suit le démarrage. Inscrite avant la
-- simulation : les groupes créés partent de l'heure courante, sans rattrapage.
local function onPopulationStart()
    LivingKnox.Population.onStart()
end

local function onPopulationHour()   -- LK13-T09 : dans l'image de l'heure, après la file de l'heure précédente
    LivingKnox.Simulation.runNow("Population", function() LivingKnox.Population.onEveryHours() end)
end

LivingKnox.subscribe(isServer() and "OnServerStarted" or "OnGameStart", "Population.onStart", onPopulationStart)
LivingKnox.subscribe("EveryHours", "Population.onEveryHours", onPopulationHour)

-- Simulation hors écran (LK09-T01) : un pas à chaque heure de jeu (GameTime.java:553-554, changement d'heure ; aucun
-- sur un serveur vide en pause PauseEmpty, l'heure n'avançant pas), et un rattrapage borné au démarrage.
local function onEveryHours()
    LivingKnox.Simulation.runNow("Simulation", function(hour) LivingKnox.Simulation.onEveryHours(hour) end)
end

local function onSimulationStart()
    LivingKnox.Simulation.onStart()
end

LivingKnox.subscribe("EveryHours", "Simulation.onEveryHours", onEveryHours)

-- Besoins individuels (LK05-T06, LK_Needs.lua) : un pas horaire de tous les membres vivants, après la simulation (tâche
-- et expéditions à jour) et avant la notation des objectifs ; rattrapage borné au démarrage.
local function onNeedsHour()
    LivingKnox.Simulation.runNow("Needs", function(hour) LivingKnox.Needs.onEveryHours(hour) end)
end

local function onNeedsStart()
    LivingKnox.Needs.onStart()
end

LivingKnox.subscribe("EveryHours", "Needs.onEveryHours", onNeedsHour)

-- Cadre de décision (LK05-T02, LK_Decisions.lua) : objectifs des groupes matérialisés notés à chaque heure de jeu,
-- après le pas de la simulation (réserves à jour) ; passage borné des membres incarnés à chaque image (au plus un
-- passage par Decisions.CFG.PASS_MS).
local function onDecisionsHour()   -- LK13-T09 : rangée dans la file du pas horaire étalé (image suivante)
    LivingKnox.Simulation.defer("Decisions", function(hour) LivingKnox.Decisions.onEveryHours(hour) end)
end

local function onDecisionsTick()
    LivingKnox.Decisions.tick()
end

LivingKnox.subscribe("EveryHours", "Decisions.onEveryHours", onDecisionsHour)
LivingKnox.subscribe("OnTick", "Decisions.tick", onDecisionsTick)

-- Déclin des attitudes (LK11-T03) : vérifié à chaque heure, appliqué quand le jour de jeu a changé.
local function onAttitudeHour()
    LivingKnox.Simulation.defer("Hostility", function() LivingKnox.Hostility.onEveryHours() end)
end

LivingKnox.subscribe("EveryHours", "Hostility.onEveryHours", onAttitudeHour)

-- Pas horaire étalé (LK13-T09, LK_Simulation) : une passe de la file par image, à partir de l'image qui suit
-- l'EveryHours ; file vidée avant la sauvegarde du monde (OnSave, solo), puis écriture.
local function onSpreadFrameStart()
    LivingKnox.Simulation.onFrameStart()
end

local function onSpreadFrame()
    LivingKnox.Simulation.onFrame()
end

local function onSpreadSave()
    if not LivingKnox.Simulation.hourPending() then return end
    LivingKnox.Simulation.finishHour()
    LivingKnox.Groups.flush()
end

LivingKnox.subscribe("OnTickEvenPaused", "Simulation.hourFrameStart", onSpreadFrameStart)
LivingKnox.subscribe("OnTick", "Simulation.hourFrame", onSpreadFrame)
LivingKnox.subscribe("OnSave", "Simulation.hourSave", onSpreadSave)
LivingKnox.subscribe(isServer() and "OnServerStarted" or "OnGameStart", "Simulation.onStart", onSimulationStart)
LivingKnox.subscribe(isServer() and "OnServerStarted" or "OnGameStart", "Needs.onStart", onNeedsStart)

return Server
