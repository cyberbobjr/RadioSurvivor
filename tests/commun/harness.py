"""Banc de tests hors jeu Living Knox : un serveur dédié et deux clients simulés (ou un solo), sous Lua 5.1 (lupa).

Simulation, PAS validation : les doublures reproduisent le comportement relevé dans le Java 42.21.0 décompilé
(références dans les commentaires), mais seul un test en jeu valide l'API réelle.

Utilisation
-----------
    from harness import Harness
    h = Harness(mode='mp')                  # machines 'server', 'A', 'B' (Lua séparés) ; mode='solo' : machine 'solo'
    h.server, h.clients['A']                # objets Machine (h.server est la machine solo en mode solo)
    h.load('server', 'shared/LivingKnox/LK_Core.lua')   # fichier relatif à .../42.21/media/lua
    Harness(lua_roots=[DEV_LUA])            # racines media/lua supplémentaires (mod de dev) : require et load
    Harness(with_rs=False)                  # E21-T08 : mod commun et Living Knox seuls (RadioSurvivor hors du chemin)
    tests_lua_src('shared/RST/RST.lua')     # fichier d'un mod de test (E21-T07 : CoreAITests, LivingKnoxTests, RS…)
    h.load('A', 'X = 1')                    # ou une chaîne Lua ; rend les valeurs du bloc
    h.eval('A', 'X')                        # valeur d'une expression Lua
    h.spawn_zombie(1001, 10, 20, 0, owner='A')   # zombie chargé sur toutes les machines ; owner : 'server', 'A', 'B'
    h.set_owner(1001, 'B')                  # transfert instantané (le jeu exige distance et délai)
    h.set_owner(1001, 'B', via_network=True)   # serveur à l'instant, clients à la livraison de leur ZombieList
    h.at_tick(20, action)                   # action() à la fin de la 20e image à venir
    h.move_zombie(1001, 11, 20); h.kill_zombie(1001); h.move_player('A', 5, 5, 0); h.kill_player('A')
    h.zombie('A', 1001), h.player('server', 'A')   # objets Lua de cette machine
    h.fire('server', 'OnTick', 0)           # déclenche un événement (dict/list Python convertis en tables)
    h.tick(n)                               # n images : par machine OnTickEvenPaused, OnZombieUpdate, OnTick
    h.pump(order='fifo'|'lifo'|'random', limit=None)   # livre la file réseau ; rend le nombre de commandes livrées
    Harness(order='random', seed=1, delay=2)   # random : chaque message retenu 0 à delay pompes (perte, renvoi)
    h.pending(), h.pending_packets()        # commandes Lua en attente (dicts) ; paquets du moteur en attente
    h.relevant_to('B', x, y)                # le serveur écrirait-il maintenant à B un paquet lié à la case x, y
    HARNESS.sendToRelative(x, y, 'AddCorpseToMap', args)   # (Lua serveur) paquet aux seuls clients de la zone
    HARNESS.onPacket('AddCorpseToMap', function(args) … end)   # (Lua client) réception de ce paquet
    h.advance(minutes)                      # horloge de jeu, minute par minute : EveryDays, EveryHours,
                                            # EveryTenMinutes, EveryOneMinute (GameTime.update)
    h.jump_to(hour, minute=0)               # prochaine heure du jour hh:mm, sans événement (partie chargée là)
    h.skip(minutes)                         # horloge avancée sans événement (serveur arrêté, heures manquées)
    h.advance_ms(ms)                        # horloge réelle (getTimestampMs, GameTime.getServerTimeMills)
    h.set_clock_synced('A', False)          # getServerTimeMills() rend 0 sur ce client
    h.set_paused('server', True)            # serveur vide en pause : OnTickEvenPaused seul
    h.logs('server'), h.errors('server')    # lignes print ; erreurs attrapées dans les abonnés d'événements
    h.file_root('A')                        # dossier Zomboid/Lua simulé de la machine
    h.close()                               # ou « with Harness() as h: »
    Harness(java_api=False)                 # doublures libres (échappatoire locale, à justifier dans le banc)
    HARNESS.fake('IsoPlayer', { … })        # (Lua) table rattachée à sa classe Java, mêmes contrôles qu'une classe
    h.load_vanilla('server', 'server/Farming/SFarmingSystem.lua')   # vrai Lua vanilla du jeu installé (E19-T04)

Lua vanilla réel (E19-T04, ADR banc mimétique D03)
--------------------------------------------------
h.load_vanilla(machine, rel, ...) exécute des fichiers de media/lua du jeu installé (tools/pz_paths.py ; à défaut les
sources de référence PZ_SOURCE_DIR/media/lua), lus sur le poste, jamais copiés dans le dépôt. Un fichier ne tourne
qu'une fois par machine (LuaManager.RunLuaInternal) ; ses require vanilla trouvent leurs fichiers (dossiers vanilla
ajoutés après ceux des mods dans package.path, côtés de la machine). Les objets Java qu'il touche restent des
doublures strictes à écrire dans le banc. Sans le jeu ni les sources : unittest.SkipTest(VANILLA_MISSING), banc
sauté avec le message de ce qui manque. vanilla_lua_dir() rend le dossier ou None (pour un skipUnless).

Doublures strictes (E19-T03, ADR banc mimétique D01)
---------------------------------------------------
Quand les sources de référence 42.22 sont présentes (tools/pz_api.py, PZ_SOURCE_DIR), toute classe créée par
HARNESS.class(nom) ou HARNESS.fake(nom) dont le nom est une classe exposée à Lua est contrôlée à l'exécution :
- définir une méthode absente de la classe Java (héritage compris) lève « harness: Classe:m n'existe pas dans la classe
  Java … » à la définition, avec le nom Java proche s'il y en a un ;
- appeler une méthode doublée avec un nombre d'arguments qu'aucune surcharge n'accepte lève le message de Kahlua
  (LuaJavaInvoker.java) : « expected N argument(s), got M » (une surcharge), « No implementation found for
  function: … » (plusieurs) ; nil explicites comptés ; méthode statique : appelée sans self, tous ses arguments
  comptés ;
- lire sur une instance une méthode du jeu non doublée rend une fonction qui lève « doublure incomplète : Classe:m
  existe dans le jeu mais n'est pas doublée » ; un nom inconnu du jeu reste nil (erreur Lua d'appel de nil, comme en
  jeu). Un champ de données du banc ne doit donc pas porter le nom d'une méthode Java (ex. « climb »).
Convention des aides de test : nom de classe suffixé « Double » (HARNESS.class('IsoZombieDouble', C.IsoZombie)) ;
jamais contrôlé, instanceof suit sa classe mère. Méthodes rangées hors de la table de classe : rawget/rawset sur une
classe stricte ne voient pas les méthodes (affecter normalement). Méthode posée sur une instance : contrôlée à sa
première définition seulement. Sans les sources, ou Harness(java_api=False), le banc se comporte comme avant.
Table de l'API : construite à la demande et gardée par processus, et dans un fichier JSON du dossier temporaire du
système (jamais dans le dépôt) pour que chaque processus n'analyse pas le Java à nouveau.

Règles simulées
---------------
- Chaque machine : LuaRuntime lua51 distinct, `next = nil`, pas de global `python`, `isClient()`/`isServer()` :
  serveur (false, true), client (true, false), solo (false, false) ; `isDebugEnabled()` = Harness(debug=...).
- `Events` : seuls les événements déclarés par LuaEventManager.java:634-895 existent (`Events.Inconnu` vaut nil),
  plus ceux de `LuaEventManager.AddEvent` ; Add sans dédoublonnage, Remove de la première occurrence, Remove depuis
  l'abonné pendant le déclenchement, erreur d'un abonné attrapée sans arrêter les suivants (Event.java:29-63).
  Avec strict=True (défaut), une erreur d'abonné lève HarnessError à la fin de fire/tick/pump/advance.
- Réseau (LuaManager.java:7214-7257, GameClient.java:1754-1774, GameServer.java:3236-3314, TableNetworkUtils) :
  copie profonde ; clés chaîne ou nombre, valeurs chaîne, nombre, booléen, table ; le reste est retiré (clé
  booléenne, fonction, objet du moteur) avec la ligne « ERROR: sendXCommand: can't save key,value=… » pour le
  premier niveau ; table vide ou nil → nil chez le destinataire. Client → serveur et serveur → client passent
  par une file livrée par pump(). Solo : sendClientCommand livré pendant l'envoi, sendServerCommand sans effet.
- Ordre et zone d'envoi (E19-T06, sources 42.22 ; aide tests/commun/net_disorder.py) : commandes Lua fiables NON ordonnées
  (PacketTypes.java:491, reliability 2), même entre deux commandes d'un même émetteur ; paquets du moteur simulés
  (PACKET_CHANNELS) fiables ordonnés par (émetteur, destinataire, canal), jamais inversés dans leur flux. Un message
  envoyé pendant une livraison part au lot suivant (jamais de réponse avant sa demande). Zone d'envoi (SendZone) :
  boîte de 88 cases autour de la position que chaque client a SIGNALÉE ; un client signale sa position à la fin d'une
  image où elle a changé (paquet PlayerUpdate livré par pump) : après move_player, le serveur le compte à son ancienne
  place jusqu'à cette livraison. Non simulés : perte définitive, latence en temps réel, reconnexion, paquets de zombie
  et interpolation des copies, chargement des cases côté client (un paquet manqué n'est jamais renvoyé).
- Zombies (NetworkZombieComponent.java:23) : isRemoteZombie() = aucune connexion propriétaire. Client : faux pour
  le zombie qu'il simule, vrai sinon. Serveur : vrai pour un zombie qu'il simule, faux pour un zombie possédé par un
  client (getOwner() rend alors sa connexion, getOwnerPlayer() son joueur). Solo : toujours vrai, getOwner() nil ; OnZombieUpdate pour tous les zombies chargés, locaux ou distants (IsoZombie.java:2738).
- Horloge de jeu (sources 42.22, java/zombie/GameTime.java) : une horloge pour toutes les machines, à la minute.
  advance() joue une mise à jour par minute et, dans la minute, sur chaque machine non en pause : EveryDays au
  passage de minuit (jour, mois, année déjà avancés : 532-534, 582-593), EveryHours si l'heure a changé (547-548),
  EveryTenMinutes si la dizaine a changé (559-568), EveryOneMinute (572-573). L'horloge lue pendant l'événement est
  la nouvelle. getNightsSurvived() + 1 au passage de 7 h (515-516) ; getWorldAgeHours() = nuits * 24 + heures depuis
  7 h (824-827), continu ; setTimeOfDay(h) change l'heure seule (jour et nuits gardés, âge recalculé, aucun
  événement : 764-766, 471). Machine en pause (serveur vide PauseEmpty) : aucun événement d'horloge (191-193, 474).
"""
from __future__ import annotations

import datetime as _dt
import difflib
import functools
import hashlib
import json
import os
import random
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from typing import NamedTuple

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import pz_api  # noqa: E402  (API Java lue sur les sources de référence du poste, E19-T03)
import pz_paths  # noqa: E402  (installation du jeu : Lua vanilla, E19-T04)

HELPER_SUFFIX = 'Double'  # classe d'aide de test : nom suffixé, jamais contrôlé contre l'API Java
LUA = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua'
CORE_LUA = ROOT / 'Contents/mods/batman_CoreAI/42.21/media/lua'  # mod commun exigé (E18)
LK_LUA = ROOT / 'Contents/mods/batman_LivingKnox/42.21/media/lua'  # moteur des PNJ (E18-T07)
# Mods de test de dev (E21-T07) : moteur RST et suites du commun, suites de Living Knox, suites de RadioSurvivor.
CORE_TESTS_LUA = ROOT / 'dev/batman_CoreAITests/42.21/media/lua'
LK_TESTS_LUA = ROOT / 'dev/batman_LivingKnoxTests/42.21/media/lua'
RS_TESTS_LUA = ROOT / 'dev/batman_RadioSurvivorTests/42.21/media/lua'
TESTS_LUA_ROOTS = (CORE_TESTS_LUA, LK_TESTS_LUA, RS_TESTS_LUA)
LK_TESTS_LUA_ROOTS = (CORE_TESTS_LUA, LK_TESTS_LUA)   # montage Living Knox seul (bancs test_lk_*)
LuaError = lupa.LuaError

# Réseau du serveur dédié (E19-T06, sources 42.22, java/zombie/...). Zone d'envoi d'une connexion : rayon en cases de
# la boîte carrée autour de la position que le client a signalée (UdpConnection.java:216-232 : |dx| et |dy| <=
# relevantRange * 8 ; connectArea nulle pour un joueur connecté normalement, GameServer.java:2649).
# relevantRange = clamp(chunkGridWidth, 12, 20) / 2 + 2 (GameServer.java:2638-2639) ; chunkGridWidth vaut 19 dès
# 1920x1080 (IsoChunkMap.java:131-140, envoyé par ConnectPacket.java:42) : 11 * 8 = 88 cases.
RELEVANT_RANGE = (19 // 2 + 2) * 8
# Canal d'ordre RakNet des paquets simulés : entier = RELIABLE_ORDERED sur ce canal (ordre garanti entre paquets d'un
# même émetteur vers un même destinataire sur ce canal) ; None = sans ordre. Commandes Lua : ClientCommand,
# reliability 2 = RELIABLE, jamais ordonnées (PacketTypes.java:491, RakNetPeerInterface.java:44-51), dans les deux sens.
PACKET_CHANNELS = {
    'AddCorpseToMap': 0,                       # AddCorpseToMapPacket.java:27 (reliability 3, ordering 0)
    'ObjectChange': 0,                         # ObjectChangePacket.java:29
    'AddItemToMap': 1,                         # AddItemToMapPacket.java:32 (transmitCompleteItemToClients)
    'AddInventoryItemToContainer': 1,          # AddInventoryItemToContainerPacket.java:33
    'RemoveInventoryItemFromContainer': 1,     # RemoveInventoryItemFromContainerPacket.java:24
    'PlayerUpdate': 5,                         # PlayerPacketReliable.java:11 (client -> serveur)
    'ZombieList': None,                        # ZombieListPacket.java:15 (reliability 0 : non fiable, non ordonné)
}
ORDERS = ('fifo', 'lifo', 'random')


class SendZone:
    """Zone d'envoi des connexions d'un serveur dédié (UdpConnection.isRelevantTo, UdpConnection.java:216-232) :
    position signalée par chaque client (releventPos : à la connexion, GameServer.java:2646-2648, puis à chaque
    PlayerPacket reçu, PlayerPacket.java:169) et boîte carrée de relevant_range cases autour. Partagée par Harness et
    les bancs à simulateur propre (tests/radiosurvivor/test_mission_retrieve.py)."""

    def __init__(self, relevant_range: int = RELEVANT_RANGE):
        self.relevant_range = relevant_range
        self.reported: dict[str, tuple] = {}

    def report(self, client: str, x, y, z=0):
        self.reported[client] = (x, y, z)

    def relevant_to(self, client: str, x, y) -> bool:
        rx, ry = self.reported[client][:2]
        return abs(rx - x) <= self.relevant_range and abs(ry - y) <= self.relevant_range

    def relevant_clients(self, x, y) -> list[str]:
        """Connexions qui reçoivent un paquet lié à la case x, y envoyé maintenant (INetworkPacket.java:182-189)."""
        return [c for c in self.reported if self.relevant_to(c, x, y)]

# zombie/Lua/LuaEventManager.java:634-895 (42.21.0), AddEvent(...) du moteur.
GAME_EVENTS = """
AcceptedFactionInvite AcceptedMedicalCheck AcceptedSafehouseInvite AcceptedTrade AddXP DoSpecialTooltip EveryDays
EveryHours EveryOneMinute EveryTenMinutes LevelPerk LoadChunk LoadGridsquare LogLevelPerk MngInvReceiveItems
OnAcceptInvite OnAddBuilding onAddForageDefs OnAddMessage OnAdminMessage OnAIStateChange OnAIStateEnter
OnAIStateExecute OnAIStateExit OnAlertMessage OnAmbientSound OnAnimalTracks OnBeingHitByZombie
OnCGlobalObjectSystemInit OnChallengeQuery OnChangeWeather OnCharacterCollide OnCharacterCreateStats
OnCharacterDeath OnCharacterMeet OnChatWindowInit OnClickedAnimalForContext OnClientCommand OnClimateManagerInit
OnClimateTick OnClimateTickDebug OnClothingUpdated OnConnected OnConnectFailed OnConnectionStateChanged
OnContainerUpdate OnContextKey OnCoopJoinFailed OnCoopServerMessage OnCreateLivingCharacter OnCreatePlayer
OnCreateSurvivor OnCreateUI OnCustomUIKey OnCustomUIKeyPressed OnCustomUIKeyReleased OnDawn OnDeadBodySpawn
OnDestroyIsoThumpable OnDeviceText OnDisconnect OnDistributionMerge OnDoTileBuilding OnDoTileBuilding2
OnDoTileBuilding3 OnDusk OnDynamicMovableRecipe OnEnterVehicle OnEquipPrimary OnEquipSecondary OnFETick
OnFillContainer OnFillInventoryObjectContextMenu onFillSearchIconContextMenu OnFillWorldObjectContextMenu
OnFishingActionMPUpdate OnGameBoot OnGamepadConnect OnGamepadDisconnect OnGameStart OnGameStateEnter
OnGameTimeLoaded OnGoogleAuthRequest OnGridBurnt OnHitZombie OnInitGlobalModData OnInitModdedWeatherStage
OnInitRecordedMedia OnInitSeasons OnInitWorld OnIsoThumpableLoad OnIsoThumpableSave onItemFall OnItemFound
OnJoypadActivate OnJoypadActivateUI OnJoypadBeforeDeactivate OnJoypadBeforeReactivate OnJoypadDeactivate
OnJoypadDebugRenderUIOptionSet OnJoypadReactivate OnJoypadRenderUI OnKeyKeepPressed OnKeyPressed
OnKeyStartPressed OnLoad OnLoadedMapZones OnLoadedTileDefinitions OnLoadMapZones onLoadModDataFromServer
OnLoadRadioScripts OnLoadSoundBanks OnLoginState OnLoginStateSuccess OnMainMenuEnter OnMakeItem
OnMapLoadCreateIsoObject OnMechanicActionDone OnMiniScoreboardUpdate OnModsModified OnMouseDown OnMouseMove
OnMouseUp OnMouseWheel OnMovingObjectCrop OnMultiTriggerNPCEvent OnNetworkUsersReceived OnNewFire OnNewGame
OnNewSurvivorGroup OnNPCSurvivorUpdate OnObjectAboutToBeRemoved OnObjectAdded OnObjectCollide
OnObjectLeftMouseButtonDown OnObjectLeftMouseButtonUp OnObjectRightMouseButtonDown OnObjectRightMouseButtonUp
OnOverrideSearchManager OnPlayerAttackFinished OnPlayerDeath OnPlayerGetDamage OnPlayerMove
OnPlayerSetSafehouse OnPlayerUpdate OnPostCharactersSquareDraw OnPostDistributionMerge OnPostFloorLayerDraw
OnPostFloorSquareDraw OnPostMapLoad OnPostRender OnPostSave OnPostTileDraw OnPostTilesSquareDraw OnPostUIDraw
OnPostWallSquareDraw OnPreDistributionMerge OnPreFillInventoryObjectContextMenu OnPreFillWorldObjectContextMenu
OnPreGameStart OnPreMapLoad OnPressRackButton OnPressReloadButton OnPressWalkTo OnPreUIDraw OnProcessAction
OnProcessTransaction OnQRReceived OnRadioInteraction OnRainStart OnRainStop OnReceiveGlobalModData
OnReceiveItemListNet OnReceiveUserlog OnRefreshInventoryWindowContainers OnRenderTick OnRenderUpdate OnResetLua
OnResolutionChange OnRightMouseDown OnRightMouseUp OnRolesReceived OnSafehousesChanged OnSave
OnScoreboardUpdate OnSeeNewRoom OnServerCommand OnServerCustomizationDataReceived OnServerFinishSaving
OnServerStarted OnServerStartSaving OnServerStatisticReceived OnServerWorkshopItems OnSetDefaultTab
OnSGlobalObjectSystemInit OnSleepingTick OnSourceWindowFileReload OnSpawnRegionsLoaded OnSpawnVehicleEnd
OnSpawnVehicleStart OnSteamGameJoin OnSteamRefreshInternetServers OnSteamRulesRefreshComplete
OnSteamServerFailedToRespond2 OnSteamServerResponded OnSteamServerResponded2 OnTabAdded OnTabRemoved
OnTemplateTextInit OnThrowableExplode OnThunderEvent OnTick OnTickEvenPaused OnTileObjectAdded OnTileRemoved
OnTriggerNPCEvent onUpdateIcon OnUpdateModdedWeatherStage OnVehicleDamageTexture OnWarUpdate
OnWaterAmountChange OnWeaponHitCharacter OnWeaponHitThumpable OnWeaponHitTree OnWeaponHitXp OnWeaponSwing
OnWeaponSwingHitPoint OnWeatherPeriodComplete OnWeatherPeriodStage OnWeatherPeriodStart OnWeatherPeriodStop
OnWorldMessage OnWorldSound OnZombieCreate OnZombieDead OnZombieUpdate OptionControllerButtonStyleChanged
OptionGamepadBindingPresetChanged preAddCatDefs preAddForageDefs preAddItemDefs preAddSkillDefs preAddZoneDefs
ReceiveFactionInvite ReceiveSafehouseInvite RefreshCheats RenderOpaqueObjectsInWorld RequestMedicalCheck
RequestTrade ReuseGridsquare SendCustomModData ServerPinged SetDragItem SwitchChatStream SyncFaction
SyncFactionServer TradingUIAddItem TradingUIRemoveItem TradingUIUpdateState ViewBannedIPs ViewBannedSteamIDs
ViewTickets
""".split()

# LuaManager.java:1045 ALLOWED_FILE_EXTENSIONS (comparaison sensible à la casse).
FILE_EXTENSIONS = {'ini', 'cfg', 'txt', 'log', 'json'}

ENGINE = r'''
local MODE, NAME, PY, EVENT_NAMES, DEBUG, STRICT = ...
next = nil  -- absent de Kahlua (BaseLib)

HARNESS = { mode = MODE, name = NAME, errors = {}, objects = {}, zombies = {}, players = {} }
local H = HARNESS

print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
    PY.print(table.concat(parts, '\t'))  -- BaseLib.java:259-277 : séparateur tabulation
end

isClient = function() return MODE == 'client' end
isServer = function() return MODE == 'server' end
isDebugEnabled = function() return DEBUG == true end
getDebug = isDebugEnabled

-- Classes Java simulées --------------------------------------------------------------------------------
-- Doublure stricte (E19-T03) : classe exposée à Lua dont l'API 42.22 est lue sur le poste (PY.api_*), sauf nom
-- d'aide de test (suffixe Double). Méthodes rangées hors de la classe (table `methods`) pour que toute définition,
-- redéfinition comprise, passe par __newindex.
local apiCache = {}
local function apiOf(name)  -- false, ou table paresseuse méthode -> spécification d'arités (false si absente)
    local a = apiCache[name]
    if a == nil then
        a = false
        if STRICT and PY.api_strict(name) then
            a = setmetatable({}, { __index = function(t, k)
                local s = type(k) == 'string' and PY.api_method(name, k) or false
                rawset(t, k, s)
                return s
            end })
        end
        apiCache[name] = a
    end
    return a
end

-- Message de Kahlua (se/krka/kahlua/integration/expose/LuaJavaInvoker.java : une surcharge ;
-- MultiLuaJavaInvoker.java : plusieurs). n compte self pour une méthode d'instance.
local function arityError(cname, k, s, n)
    if s.expected then
        local got = s.static and n or n - 1
        error(('expected %d argument%s, got %d'):format(s.expected, s.expected == 1 and '' or 's', got), 3)
    end
    error('No implementation found for function: ' .. cname .. ':' .. k .. ' with ' .. (n - 1) .. ' arguments', 3)
end

local originals = setmetatable({}, { __mode = 'k' })
local function guard(cname, k, f, s)
    f = originals[f] or f
    local counts, varmin = s.counts, s.varmin
    local g = function(...)
        local n = select('#', ...)
        if not (counts[n] or (varmin and n >= varmin)) then arityError(cname, k, s, n) end
        return f(...)
    end
    originals[g] = f
    return g
end

local function checked(cname, api, k, v)  -- valeur à ranger pour la clé k d'une doublure stricte
    if type(v) ~= 'function' or type(k) ~= 'string' then return v end
    local s = api[k]
    if not s then
        local near = PY.api_suggest(cname, k)
        error('harness: ' .. cname .. ':' .. k .. " n'existe pas dans la classe Java " .. cname .. ' (API 42.22)'
            .. (near and (' ; voulu : ' .. near .. ' ?') or '') .. ' ; aide de test : classe suffixée Double', 3)
    end
    return guard(cname, k, v, s)
end

local incompletes = {}
local function missing(cname, api, k)  -- méthode du jeu non doublée : fonction qui le dit ; sinon nil
    if type(k) ~= 'string' or not api[k] then return nil end
    local key = cname .. ':' .. k
    local f = incompletes[key]
    if not f then
        f = function() error('doublure incomplète : ' .. key .. " existe dans le jeu mais n'est pas doublée", 2) end
        incompletes[key] = f
    end
    return f
end

-- Classe stricte : méthodes de classe rangées dans c.__methods (toute définition passe par __newindex) ; les
-- instances lisent un cache aplati (méthode trouvée en remontant les classes mères, ou fonction « doublure
-- incomplète »), vidé à chaque définition. Méthode posée sur une instance : contrôlée à sa première définition,
-- gardée dans l'instance. Données des instances : dans l'instance.
local caches = setmetatable({}, { __mode = 'k' })
local function flushCaches()
    for cache in pairs(caches) do
        for k in pairs(cache) do cache[k] = nil end
    end
end
local function lookup(cls, k)  -- méthode doublée par cls ou une classe mère (__super), nil sinon
    while cls do
        local v = rawget(rawget(cls, '__methods') or cls, k)
        if v ~= nil then return v end
        cls = rawget(cls, '__super')
    end
    return nil
end
local function allStrict(cls)  -- vrai si cls et toutes ses mères sont strictes (méthodes = noms de son API)
    while cls do
        if rawget(cls, '__methods') == nil then return false end
        cls = rawget(cls, '__super')
    end
    return true
end
local function strictClass(c, name, api)
    c.__methods = {}
    local onlyApi = allStrict(rawget(c, '__super'))
    local cache = setmetatable({}, { __index = function(t, k)
        if onlyApi and not api[k] then return nil end  -- champ de données : chemin court
        local v = lookup(c, k)
        if v == nil then v = missing(name, api, k) end
        if v ~= nil then rawset(t, k, v) end
        return v
    end })
    caches[cache] = true
    c.__index = cache
    c.__newindex = function(o, k, v) rawset(o, k, checked(name, api, k, v)) end
    setmetatable(c, { __index = function(_, k) return lookup(c, k) end, __newindex = function(_, k, v)
        if type(k) == 'string' and k:sub(1, 2) == '__' then rawset(c, k, v) return end
        rawset(c.__methods, k, checked(name, api, k, v))
        flushCaches()
    end })
end

local function newClass(name, parent)
    -- __parent : classe mère pour instanceof ; __super : classe mère dont les méthodes sont héritées.
    local c = { __javaName = name, __parent = parent, __super = parent }
    c.__tostring = function(o) return name .. '@' .. tostring(rawget(o, '__id') or '?') end
    local api = apiOf(name)
    if api then
        strictClass(c, name, api)
    else
        c.__index = c
        if parent then setmetatable(c, { __index = parent }) end
    end
    return c
end

local classes = {}
local function class(name, parent)
    local c = newClass(name, parent)
    classes[name] = c
    return c
end
H.class, H.classes = class, classes

-- Faux objet anonyme rattaché à sa classe Java (E19-T03) : mêmes contrôles qu'une doublure de classe, sans hériter
-- des méthodes doublées par le harnais ; instanceof suit la classe du harnais du même nom et ses mères.
local fakeClasses = {}
function H.fake(name, fields)
    local c = fakeClasses[name]
    if not c then
        c = newClass(name, nil)
        c.__parent = classes[name]
        fakeClasses[name] = c
    end
    local o = fields or {}
    local funcs = {}
    for k, v in pairs(o) do if type(v) == 'function' then funcs[k] = v end end
    for k in pairs(funcs) do o[k] = nil end
    setmetatable(o, c)
    for k, v in pairs(funcs) do o[k] = v end
    return o
end

function H.javaClass(v)
    if type(v) ~= 'table' then return nil end
    local mt = getmetatable(v)
    return mt and rawget(mt, '__javaName') or nil
end

-- Paramètre numérique d'une méthode Java : nil ou autre type = aucune surcharge applicable.
local function num(v, method)
    if type(v) ~= 'number' then
        error('No implementation found for ' .. method .. ' with argument ' .. tostring(v), 3)
    end
    return v
end
H.num = num

instanceof = function(o, name)  -- LuaManager.java:2842 : nil -> false
    if type(o) ~= 'table' then return false end
    local c = getmetatable(o)
    while c do
        if rawget(c, '__javaName') == name then return true end
        c = rawget(c, '__parent')
    end
    return false
end

-- java.util.ArrayList : indices depuis 0.
local ArrayList = class('ArrayList')
function H.list(items) return setmetatable({ items = items or {} }, ArrayList) end
function ArrayList:size() return #self.items end
function ArrayList:isEmpty() return #self.items == 0 end
function ArrayList:get(i)
    i = num(i, 'ArrayList.get')
    i = i >= 0 and math.floor(i) or math.ceil(i)  -- double -> int tronqué vers zéro
    if i < 0 or i >= #self.items then
        error('IndexOutOfBoundsException: Index ' .. i .. ' out of bounds for length ' .. #self.items, 2)
    end
    return self.items[i + 1]
end
function ArrayList:contains(o) for _, v in ipairs(self.items) do if v == o then return true end end return false end
function ArrayList:indexOf(o) for i, v in ipairs(self.items) do if v == o then return i - 1 end end return -1 end
function ArrayList:add(o) self.items[#self.items + 1] = o; return true end
function H.listRemove(list, o)
    for i, v in ipairs(list.items) do if v == o then table.remove(list.items, i) return true end end
    return false
end

-- Cases et cellule -------------------------------------------------------------------------------------
local IsoObject = class('IsoObject')
function IsoObject:getModData() local md = rawget(self, '__modData'); if not md then md = {}; self.__modData = md end return md end
function IsoObject:hasModData() return rawget(self, '__modData') ~= nil end
function IsoObject:getSquare() return self.square end
function IsoObject:getX() return self.x end
function IsoObject:getY() return self.y end
function IsoObject:getZ() return self.z end
-- IsoObject.java:1879 : conteneur de l'objet (nil sans conteneur) ; doublure : self.container.
function IsoObject:getContainer() return self.container end

local IsoGridSquare = class('IsoGridSquare')
function IsoGridSquare:getX() return self.x end
function IsoGridSquare:getY() return self.y end
function IsoGridSquare:getZ() return self.z end
function IsoGridSquare:getObjects() return self.objects end
function IsoGridSquare:getMovingObjects() return self.movingObjects end
function IsoGridSquare:getModData() local md = rawget(self, '__modData'); if not md then md = {}; self.__modData = md end return md end
function IsoGridSquare:getCell() return H.cell end
-- IsoGridSquare.java:2894-2915 : faux si bCountOtherCharacters et des objets mobiles, sinon sol solide sans mur,
-- meuble plein ni arbre (doublure : self.blocked = vrai pour une case impraticable).
function IsoGridSquare:isFree(countOthers)
    if countOthers and not self.movingObjects:isEmpty() then return false end
    return self.blocked ~= true
end

-- IsoGridSquare.java:3107-3112 : porte du bord commun avec une case voisine ; le banc n'a aucune porte (doublure de
-- test_lk_obstacles.py pour les portes).
function IsoGridSquare:getDoorTo(next) return nil end
-- IsoGridSquare.java:3131-3172, 3228-3236 : fenêtre, fenêtre construite, cadre du bord commun ; aucune sur le banc
-- (doublures de test_lk_obstacles.py pour les fenêtres, LK04-T03).
function IsoGridSquare:getWindowTo(next) return nil end
function IsoGridSquare:getWindowThumpableTo(next) return nil end
function IsoGridSquare:getWindowFrameTo(next) return nil end
-- IsoGridSquare.java:935-941 : mur, fenêtre, porte bloqués ou escalier entre deux cases ; aucun sur le banc
-- (doublures de test_lk_obstacles.py).
function IsoGridSquare:isBlockedTo(other) return false end
-- IsoGridSquare.java:718-731 : mur ou fenêtre du bord commun ; aucun sur le banc (doublures de test_lk_obstacles.py).
function IsoGridSquare:isWallTo(other) return false end
function IsoGridSquare:isWindowTo(other) return false end
-- IsoGridSquare.java:7813 : bâtiment de la case ; aucun sur le banc (doublures des bancs à bâtiments).
function IsoGridSquare:getBuildingDef() return nil end
-- IsoGridSquare.java:1043-1049 (42.22) : objet franchissable (clôture basse) du bord commun ; aucun sur le banc.
function IsoGridSquare:isHoppableTo(other) return false end
-- LK06-T08 : IsoGridSquare.java:971-977 (fenêtre fermée ou barricadée du bord commun) ; pièce de la case
-- (self.room, nil = dehors). Aucune fenêtre ni pièce sur le banc (doublures de test_lk_window_lure.py).
function IsoGridSquare:isWindowBlockedTo(other) return false end
function IsoGridSquare:getRoom() return self.room end
-- Sol nu par défaut (IsoGridSquare.java 42.22 : HasStairs 2169, hasBush 2378, isWaterSquare 9570) ; champs du banc.
function IsoGridSquare:HasStairs() return self.stairs == true end
function IsoGridSquare:hasBush() return self.bush == true end
function IsoGridSquare:isWaterSquare() return self.water == true end
function IsoGridSquare:getWorldObjects() return rawget(self, 'worldObjects') or H.list() end

local squares = {}
local function floorInt(v) return math.floor(v) end  -- PZMath.fastfloor (IsoCell.java:2734-2742)
function H.square(x, y, z)
    x, y, z = floorInt(x), floorInt(y), floorInt(z)
    local key = x .. ',' .. y .. ',' .. z
    local sq = squares[key]
    if not sq then
        sq = setmetatable({ x = x, y = y, z = z, objects = H.list(), movingObjects = H.list() }, IsoGridSquare)
        squares[key] = sq
    end
    return sq
end

local IsoCell = class('IsoCell')
function IsoCell:getGridSquare(x, y, z)
    num(x, 'IsoCell.getGridSquare'); num(y, 'IsoCell.getGridSquare'); num(z, 'IsoCell.getGridSquare')
    return H.square(x, y, z)
end
IsoCell.getOrCreateGridSquare = IsoCell.getGridSquare
function IsoCell:getZombieList() return H.zombieList end
H.cell = setmetatable({}, IsoCell)
H.zombieList = H.list()
getCell = function() return H.cell end

function H.addObject(x, y, z, obj)
    local sq = H.square(x, y, z)
    obj = obj or setmetatable({}, IsoObject)
    obj.square, obj.x, obj.y, obj.z = sq, sq.x, sq.y, sq.z
    sq.objects:add(obj)
    return obj
end

-- Personnages ------------------------------------------------------------------------------------------
local IsoMovingObject = class('IsoMovingObject', IsoObject)
function IsoMovingObject:getCurrentSquare() return self.square end
function IsoMovingObject:isOnFloor() return self.onFloor == true end  -- IsoMovingObject.java:2038
-- Positions écrites une à une, comme NetworkZombiePacker.applyZombie (IsoMovingObject.java:509-560, 1299-1350) :
-- set*() rend la valeur posée ; la case ne change que par setCurrent (IsoMovingObject.java:1849).
function IsoMovingObject:setX(v) self.x = v; return v end
function IsoMovingObject:setY(v) self.y = v; return v end
function IsoMovingObject:setZ(v) self.z = v; return v end
function IsoMovingObject:setLastX(v) self.lastX = v; return v end
function IsoMovingObject:setLastY(v) self.lastY = v; return v end
function IsoMovingObject:setLastZ(v) self.lastZ = v; return v end
function IsoMovingObject:setNextX(v) self.nextX = v; return v end
function IsoMovingObject:setNextY(v) self.nextY = v; return v end
function IsoMovingObject:setCurrent(sq)
    if self.square then H.listRemove(self.square.movingObjects, self) end
    self.square = sq
    if sq then sq.movingObjects:add(self) end
end
function IsoMovingObject:setMovingSquareNow() self.movingSquareSet = (self.movingSquareSet or 0) + 1 end
local IsoGameCharacter = class('IsoGameCharacter', IsoMovingObject)
function IsoGameCharacter:isDead() return self.dead == true end
function IsoGameCharacter:getOnlineID() return self.onlineID end
function IsoGameCharacter:isZombie() return false end
function IsoGameCharacter:getVehicle() return self.vehicle end  -- IsoGameCharacter.java:10202 (nil hors vehicule)
-- IsoGameCharacter.java:13210 : état d'action courant (nom de dossier d'actiongroups en minuscules) ; self.actionState.
function IsoGameCharacter:getActionStateName() return self.actionState or 'idle' end
-- IsoGameCharacter (42.22) : endormi, invisible (champs du banc, faux par défaut) ; ouïe modifiée par les vêtements
-- portés : 1 / wornItemsHearingModifier (IsoGameCharacter.java:14248-14254), 1 sans vêtement qui la change.
function IsoGameCharacter:isAsleep() return self.asleep == true end
function IsoGameCharacter:isInvisible() return self.invisible == true end
function IsoGameCharacter:setInvisible(b) self.invisible = b end
function IsoGameCharacter:getWornItemsHearingMultiplier() return 1 / (self.wornItemsHearingModifier or 1) end
-- IsoGameCharacter.java:14264-14268 : 1 - pluie * 0,33 - brouillard * 0,1 ; ni pluie ni brouillard sur le banc.
function IsoGameCharacter:getWeatherHearingMultiplier() return 1 end
-- Corps au sol et remise debout (LK02-T14). IsoMovingObject.java:2018, 2042 ; IsoGameCharacter.java:11555,
-- 13419 ; IsoObject.java:1766-1777 (alpha du joueur local courant). Relevé / rejeu de l'état d'action
-- (IsoGameCharacter.java:11516-11528, ActionStateContainer.java:199-243) : objet ActionStateSnapshot opaque, rejeu
-- immédiat de l'état d'action ; l'état Java (self.aiState) ne change que par changeState (StateMachine.java:34-72)
-- ou à la mise à jour suivante du moteur (non simulée ici). États Java : objets uniques ZombieIdleState.instance(),
-- ZombieOnGroundState.instance().
function IsoMovingObject:setOnFloor(b) self.onFloor = b end
function IsoMovingObject:setCollidable(b) self.collidable = b end
function IsoMovingObject:isCollidable() return self.collidable ~= false end
function IsoObject:setAlpha(a) num(a, 'setAlpha'); self.alpha = a end
function IsoObject:getAlpha() return rawget(self, 'alpha') or 1 end
function IsoGameCharacter:setFallOnFront(b) self.fallOnFront = b end
function IsoGameCharacter:isFallOnFront() return self.fallOnFront == true end
function IsoGameCharacter:setKnockedDown(b) self.knockedDown = b end
function IsoGameCharacter:isKnockedDown() return self.knockedDown == true end
local Snapshot = class('ActionStateSnapshot')
function IsoGameCharacter:playbackRecordCurrentStateSnapshot()
    return setmetatable({ stateName = self:getActionStateName() }, Snapshot)
end
function IsoGameCharacter:playbackSetCurrentStateSnapshot(s)
    if getmetatable(s) ~= Snapshot then error('No implementation found for playbackSetCurrentStateSnapshot', 2) end
    self.actionState = s.stateName
end
local State = class('State')
local idleState = setmetatable({ name = 'ZombieIdleState' }, State)
local onGroundState = setmetatable({ name = 'ZombieOnGroundState' }, State)
ZombieIdleState = { instance = function() return idleState end }
ZombieOnGroundState = { instance = function() return onGroundState end }
function IsoGameCharacter:changeState(s)
    if getmetatable(s) ~= State then error('No implementation found for changeState', 2) end
    self.aiState = s
end
function IsoGameCharacter:getCurrentState() return self.aiState or idleState end
local IsoPlayer = class('IsoPlayer', IsoGameCharacter)
function IsoPlayer:getUsername() return self.username end
function IsoPlayer:getDisplayName() return self.username end
function IsoPlayer:isLocalPlayer() return self.isLocal == true end
function IsoPlayer:getPlayerNum() return self.isLocal and 0 or -1 end
local IsoZombie = class('IsoZombie', IsoGameCharacter)
function IsoZombie:isZombie() return true end
-- Propriétaire : self.owner = nom de la machine qui simule ('server', 'A', 'B'...). Java : IsoZombie.java:441-458 ->
-- NetworkZombieComponent.java:23-41 : isRemote() = authOwner == null. Un client pose authOwner = sa connexion et
-- ownerPlayer = son joueur pour les zombies qu'il simule (NetworkZombieSimulator.java:124-129) ; le serveur pose la
-- connexion du client propriétaire, rien pour un zombie qu'il simule ; en solo, personne ne pose rien.
local function ownedHere(zb)
    if MODE == 'client' then return zb.owner == NAME end
    if MODE == 'server' then return zb.owner ~= nil and zb.owner ~= 'server' end
    return false
end
H.connections = {}
local function connection(name)
    local c = H.connections[name]
    if not c then c = { __id = 'conn:' .. name, username = name }; H.connections[name] = c end
    return c
end
-- Client : faux pour le zombie qu'il simule. Serveur : vrai pour un zombie qu'il simule, faux s'il est possédé par
-- un client. Solo : toujours vrai.
function IsoZombie:isRemoteZombie() return not ownedHere(self) end
-- IsoMovingObject.getThumpTarget (cible de coups posée par ThumpState) : self.thump, nil par défaut.
function IsoZombie:getThumpTarget() return self.thump end
-- IsoZombie.java:4334-4336 : état réseau reçu (NetworkVariables.ZombieState en minuscules) ; self.realState.
function IsoZombie:getRealState() return self.realState or 'idle' end
function IsoZombie:getOwner() return ownedHere(self) and connection(self.owner) or nil end
function IsoZombie:getOwnerPlayer()
    if not ownedHere(self) then return nil end
    if MODE == 'client' then return H.localPlayer end
    return H.players[self.owner]
end

function H.place(o, x, y, z)
    if o.square then H.listRemove(o.square.movingObjects, o) end
    o.x, o.y, o.z = x, y, z
    o.square = H.square(x, y, z)
    o.square.movingObjects:add(o)
end

function H.spawnZombie(id, x, y, z, owner)
    local zb = setmetatable({ __id = id, onlineID = id, owner = owner }, IsoZombie)
    H.place(zb, x, y, z)
    H.zombies[id] = zb
    H.zombieList:add(zb)
    return zb
end

function H.removeZombie(id)
    local zb = H.zombies[id]
    if not zb then return end
    H.listRemove(H.zombieList, zb)
    if zb.square then H.listRemove(zb.square.movingObjects, zb) end
    H.zombies[id] = nil
end

function H.updateZombies()
    local snapshot = {}
    for i, zb in ipairs(H.zombieList.items) do snapshot[i] = zb end
    for _, zb in ipairs(snapshot) do
        if H.zombies[zb.onlineID] == zb then H.trigger('OnZombieUpdate', zb) end
    end
end

function H.addPlayer(username, onlineID, x, y, z, isLocal)
    local p = setmetatable({ __id = username, username = username, onlineID = onlineID, isLocal = isLocal }, IsoPlayer)
    H.place(p, x, y, z)
    H.players[username] = p
    if isLocal then H.localPlayer = p end
    return p
end

local function onlinePlayers()
    local list = {}
    for _, p in pairs(H.players) do list[#list + 1] = p end
    table.sort(list, function(a, b) return a.onlineID < b.onlineID end)
    return list
end
-- LuaManager.java:3833-3842 : liste vide hors MP.
getOnlinePlayers = function()
    if MODE == 'solo' then return H.list() end
    return H.list(onlinePlayers())
end
getPlayer = function() return H.localPlayer end  -- nil sur un serveur dédié
getSpecificPlayer = function(i) num(i, 'getSpecificPlayer'); if i == 0 then return H.localPlayer end return nil end
getNumActivePlayers = function() return H.localPlayer and 1 or 0 end
getPlayerByOnlineID = function(id)  -- LuaManager.java:3463-3472
    num(id, 'getPlayerByOnlineID')
    if MODE == 'solo' then return nil end
    for _, p in pairs(H.players) do if p.onlineID == id then return p end end
    return nil
end
getPlayerFromUsername = function(name)  -- LuaManager.java:7377 : table de GameClient, vide hors client
    if MODE ~= 'client' then return nil end
    return H.players[name]
end

-- Événements -------------------------------------------------------------------------------------------
Events = {}
local events = {}
local function addEvent(name)
    if events[name] then return events[name] end
    local e = { name = name, callbacks = {} }
    e.table = {
        Add = function(f) if type(f) == 'function' then e.callbacks[#e.callbacks + 1] = f end end,
        Remove = function(f)
            for i, g in ipairs(e.callbacks) do if g == f then table.remove(e.callbacks, i) return end end
        end,
    }
    events[name] = e
    Events[name] = e.table
    return e
end
for _, name in ipairs(EVENT_NAMES) do addEvent(name) end
LuaEventManager = { AddEvent = function(name) addEvent(name) end }

local function contains(list, f) for _, g in ipairs(list) do if g == f then return true end end return false end
function H.trigger(name, ...)
    local e = events[name]
    if not e or #e.callbacks == 0 then return false end
    local n = 1
    while n <= #e.callbacks do  -- Event.java:52-62
        local f = e.callbacks[n]
        local ok, err = pcall(f, ...)
        if not ok then
            H.errors[#H.errors + 1] = name .. ': ' .. tostring(err)
            PY.print('ERROR: event ' .. name .. ': ' .. tostring(err))
        end
        if not contains(e.callbacks, f) then n = n - 1 end
        n = n + 1
    end
    return true
end
triggerEvent = function(name, ...) H.trigger(name, ...) end

-- Horloges ---------------------------------------------------------------------------------------------
H.clock = { realMs = 0, serverMs = 0, synced = true, year = 1993, month = 6, day = 8, hour = 9, minute = 0,
    ageHours = 2, nights = 0, multiplier = 1 }
getTimestampMs = function() return H.clock.realMs end
-- Rand.java (42.21.0) : ZombRand(max) dans [0, max[, ZombRand(min, max) dans [min, max[ ; tirage du banc (math.random).
ZombRand = function(a, b)
    if b == nil then return a <= 0 and 0 or math.random(0, a - 1) end
    if b <= a then return a end
    return math.random(a, b - 1)
end
local GameTimeClass = class('GameTime')
local gameTime = setmetatable({}, GameTimeClass)
function GameTimeClass:getYear() return H.clock.year end
function GameTimeClass:getMonth() return H.clock.month end
function GameTimeClass:getDay() return H.clock.day end
function GameTimeClass:getDayPlusOne() return H.clock.day + 1 end
function GameTimeClass:getHour() return H.clock.hour end
function GameTimeClass:getMinutes() return H.clock.minute end
function GameTimeClass:getTimeOfDay() return H.clock.hour + H.clock.minute / 60 end
function GameTimeClass:getWorldAgeHours() return H.clock.ageHours end
function GameTimeClass:getNightsSurvived() return H.clock.nights end
-- GameTime.java:764-766 : heure du jour seule ; l'horloge du banc est commune aux machines (synchronisation).
function GameTimeClass:setTimeOfDay(h) PY.set_time_of_day(num(h, 'setTimeOfDay')) end
-- GameTime.java:867: real minutes of one game day (DayLength, vanilla default 90), read by CA_GameClock (E11-T20).
function GameTimeClass:getMinutesPerDay() return H.clock.minutesPerDay or 90 end
function GameTimeClass:getMultiplier() return H.clock.multiplier end
getGameTime = function() return gameTime end
GameTime = {
    getInstance = function() return gameTime end,
    -- GameTime.java:160-178 : serveur = horloge monotone ; client = 0 avant synchronisation ; solo = 0.
    getServerTimeMills = function()
        if MODE == 'server' then return H.clock.serverMs end
        if MODE == 'client' and H.clock.synced then return H.clock.serverMs end
        return 0
    end,
}

-- Fichiers (LuaManager.java:4904-4928, 5535-5568, 9881-9899) -----------------------------------------
local LuaFileWriter = class('LuaFileWriter')
function LuaFileWriter:write(s)
    if s == nil then error('NullPointerException: LuaFileWriter.write(nil)', 2) end
    PY.file_write(self.handle, tostring(s))
end
function LuaFileWriter:writeln(s)
    if s == nil then error('NullPointerException: LuaFileWriter.writeln(nil)', 2) end
    PY.file_write(self.handle, tostring(s) .. '\n')
end
function LuaFileWriter:close() PY.file_close(self.handle) end
getFileWriter = function(name, createIfNull, append)
    local handle = PY.file_open(name, createIfNull == true, append == true)
    if handle == nil then return nil end
    return setmetatable({ handle = handle }, LuaFileWriter)
end
local BufferedReader = class('BufferedReader')
function BufferedReader:readLine()
    local i = self.pos
    if i > #self.lines then return nil end
    self.pos = i + 1
    return self.lines[i]
end
function BufferedReader:ready() return self.pos <= #self.lines end
function BufferedReader:close() end
getFileReader = function(name, createIfNull)
    local lines = PY.file_read(name, createIfNull == true)
    if lines == nil then return nil end
    return setmetatable({ lines = lines, pos = 1 }, BufferedReader)
end

-- Réseau -----------------------------------------------------------------------------------------------
-- Copie façon TableNetworkUtils : clés chaîne/nombre ; valeurs chaîne, nombre, booléen, table simple.
local function netCopy(t, seen)
    if seen[t] then error('harness: cyclic table in network args (TableNetworkUtils would overflow)', 0) end
    seen[t] = true
    local out = {}
    for k, v in pairs(t) do
        local kt, vt = type(k), type(v)
        if (kt == 'string' or kt == 'number') then
            if vt == 'string' or vt == 'number' or vt == 'boolean' then out[k] = v
            elseif vt == 'table' and H.javaClass(v) == nil then out[k] = netCopy(v, seen) end
        end
    end
    seen[t] = nil
    return out
end
local function canSave(k, v)
    local kt, vt = type(k), type(v)
    if kt ~= 'string' and kt ~= 'number' then return false end
    return vt == 'string' or vt == 'number' or vt == 'boolean' or (vt == 'table' and H.javaClass(v) == nil)
end
-- Rend nil (aucun argument, comme `args != null && !args.isEmpty()`) ou la copie filtrée.
function H.netArgs(args, fname)
    if type(args) ~= 'table' then return nil end
    local empty = true
    for k, v in pairs(args) do
        empty = false
        if not canSave(k, v) then
            PY.print('ERROR: ' .. fname .. ": can't save key,value=" .. tostring(k) .. ',' .. tostring(v))
        end
    end
    if empty then return nil end
    return netCopy(args, {})
end

local function isPlayer(v) return instanceof(v, 'IsoPlayer') end

sendClientCommand = function(...)
    local n = select('#', ...)
    local player, module, command, args
    if n >= 4 or isPlayer((...)) then player, module, command, args = ...
    else module, command, args = ... end
    if n >= 4 or isPlayer(player) then
        -- LuaManager.java:7226-7243
        if MODE == 'server' then H.trigger('OnClientCommand', module, command, player, args) return end
        if player == nil or not player:isLocalPlayer() then return end
    elseif MODE == 'server' then
        error("IllegalStateException: can't call this function on the server", 2)  -- LuaManager.java:7219-7220
    end
    PY.client_send(module, command, H.netArgs(args, 'sendClientCommand'))
end

sendServerCommand = function(...)
    if MODE ~= 'server' then return end  -- LuaManager.java:7245-7257 : sans effet hors serveur (solo compris)
    local n = select('#', ...)
    if n >= 4 or isPlayer((...)) then
        local player, module, command, args = ...
        if not isPlayer(player) or H.players[player.username] ~= player then return end  -- PlayerToAddressMap
        PY.server_send(player.username, module, command, H.netArgs(args, 'sendServerCommand'))
    else
        local module, command, args = ...
        PY.server_send(nil, module, command, H.netArgs(args, 'sendServerCommand'))
    end
end

-- Paquets liés à une case (E19-T06) : INetworkPacket.sendToRelative et GameServer.sendCorpse n'écrivent qu'aux
-- connexions dont la zone couvre la case (INetworkPacket.java:182-189, GameServer.java:1869-1883, 42.22) ; sans effet
-- hors serveur dédié (GameServer.server faux : client et solo). Les doublures des bancs (sendCorpse,
-- transmitCompleteItemToClients, sendObjectChange...) appellent H.sendToRelative ; le client reçoit par H.onPacket.
H.packetHandlers = {}
function H.onPacket(packet, f) H.packetHandlers[packet] = f end
function H.sendToRelative(x, y, packet, args)
    if MODE ~= 'server' then return end
    PY.send_relative(num(x, 'sendToRelative'), num(y, 'sendToRelative'), packet, H.netArgs(args, packet))
end
function H.receivePacket(packet, args)
    local f = H.packetHandlers[packet]
    if f then f(args) end
end

function H.run(src, chunkname)
    local f, err = loadstring(src, chunkname)
    if not f then error(err, 0) end
    return f()
end

-- Fichier vanilla (E19-T04) : une fois par machine sous son nom de require (LuaManager.RunLuaInternal : déjà chargé,
-- rend le retour gardé ; chargé par require ou par load_vanilla, c'est le même fichier).
function H.loadVanilla(module, src, chunkname)
    local done = package.loaded[module]
    if done ~= nil then return done end
    local r = H.run(src, chunkname)
    if package.loaded[module] == nil then package.loaded[module] = r == nil and true or r end
    return package.loaded[module]
end
'''


# Objets globaux du serveur (E19-T04), doublures strictes de J/globalObjects (42.22), à charger sur l'autorité (serveur
# dédié ou solo) avant un système vanilla qui s'appuie dessus (Map/SGlobalObjectSystem.lua : potager, feux de camp...).
# La table Lua d'un système et celle d'un objet sont les getModData() du Java, comme en jeu (le Lua y pose sa
# métatable). Refus du Java : objet sur une case déjà prise (GlobalObjectSystem.java:40-48), objet nil ou d'un autre
# système (:50-60, SGlobalObjectSystem.java:117-145), clé non chaîne (:47-89), système déjà créé ou nom à « .. »
# (SGlobalObjects.java:48-57, GlobalObjectSystem.java:22-27). Aucun fichier gos_<nom>.bin : loadedWorldVersion() = -1
# (monde neuf). Envois aux clients comptés dans GLOBAL_OBJECTS_SENT (SGlobalObjectNetwork, effet client non simulé).
GLOBAL_OBJECTS = r'''
local H = HARNESS
local C = H.classes
if SGlobalObjects ~= nil then return end
local Sys = H.class('SGlobalObjectSystem')
local GO = H.class('SGlobalObject')
local SGO = H.class('SGlobalObjects')
local systems = {}
GLOBAL_OBJECTS_SENT = { add = 0, remove = 0, update = 0, command = 0 }
local function int(v, method)  -- paramètre int du Java : nombre tronqué vers zéro
    H.num(v, method)
    return v >= 0 and math.floor(v) or math.ceil(v)
end
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
local function wipe(t) for k in pairs(t) do t[k] = nil end end   -- KahluaTable.wipe

function SGO.getSystemByName(name)
    for _, s in ipairs(systems) do if s.goName == name then return s end end
    return nil
end
function SGO.newSystem(name)
    if type(name) ~= 'string' then error('No implementation found for SGlobalObjects.newSystem', 2) end
    if SGO.getSystemByName(name) ~= nil then error('IllegalStateException: system with that name already exists', 2) end
    if string.find(name, '..', 1, true) then
        error('IllegalStateException: Name of GlobalObjectSystem invalid: ' .. name, 2)
    end
    local s = setmetatable({ goName = name, goData = {}, goList = {}, goAt = {} }, Sys)
    systems[#systems + 1] = s
    return s
end
-- SGlobalObjects.java:40-46 : système existant, sinon nouveau puis load() (aucun fichier : rien n'est lu).
function SGO.registerSystem(name) return SGO.getSystemByName(name) or SGO.newSystem(name) end
function SGO.getSystemCount() return #systems end
function SGO.getSystemByIndex(i)
    i = int(i, 'SGlobalObjects.getSystemByIndex')
    return systems[i + 1]
end
SGlobalObjects = SGO

function Sys:getName() return self.goName end
function Sys:getModData() return self.goData end
local function keys(t, method)
    if t == nil then return end
    if type(t) ~= 'table' then error('No implementation found for ' .. method, 3) end
    for _, v in pairs(t) do
        if type(v) ~= 'string' then
            error('IllegalArgumentException: expected string but got "' .. tostring(v) .. '"', 3)
        end
    end
end
function Sys:setModDataKeys(t) keys(t, 'setModDataKeys') self.goKeys = t end
function Sys:setObjectModDataKeys(t) keys(t, 'setObjectModDataKeys') self.goObjectKeys = t end
function Sys:setObjectSyncKeys(t) keys(t, 'setObjectSyncKeys') self.goSyncKeys = t end
function Sys:loadedWorldVersion() return -1 end
function Sys:getObjectAt(x, y, z)
    if z == nil then  -- getObjectAt(IsoGridSquare)
        if not instanceof(x, 'IsoGridSquare') then error('No implementation found for getObjectAt', 2) end
        x, y, z = x:getX(), x:getY(), x:getZ()
    end
    return self.goAt[key(int(x, 'getObjectAt'), int(y, 'getObjectAt'), int(z, 'getObjectAt'))]
end
function Sys:newObject(x, y, z)
    x, y, z = int(x, 'newObject'), int(y, 'newObject'), int(z, 'newObject')
    if self:getObjectAt(x, y, z) ~= nil then
        error('IllegalStateException: already an object at ' .. x .. ',' .. y .. ',' .. z, 2)
    end
    local o = setmetatable({ system = self, x = x, y = y, z = z, modData = {} }, GO)
    self.goList[#self.goList + 1] = o
    self.goAt[key(x, y, z)] = o
    return o
end
function Sys:removeObject(o)
    if o == nil then error('NullPointerException: object is null', 2) end
    if getmetatable(o) ~= GO then error('No implementation found for removeObject', 2) end
    if o.system ~= self then error('IllegalStateException: object not in this system', 2) end
    for i, v in ipairs(self.goList) do if v == o then table.remove(self.goList, i) break end end
    self.goAt[key(o.x, o.y, o.z)] = nil
    o.system = nil   -- GlobalObject.Reset : système oublié, table vidée (la table Lua de l'objet aussi)
    wipe(o.modData)
end
function Sys:getObjectCount() return #self.goList end
function Sys:getObjectByIndex(i)
    i = int(i, 'getObjectByIndex')
    return self.goList[i + 1]
end
-- GlobalObjectLookup.java:122-131 : les neuf cases autour, la case elle-même comprise.
function Sys:getObjectsAdjacentTo(x, y, z)
    x, y, z = int(x, 'getObjectsAdjacentTo'), int(y, 'getObjectsAdjacentTo'), int(z, 'getObjectsAdjacentTo')
    local list = H.list()
    for dy = -1, 1 do
        for dx = -1, 1 do
            local o = self.goAt[key(x + dx, y + dy, z)]
            if o ~= nil then list:add(o) end
        end
    end
    return list
end
function Sys:finishedWithList(list) if list ~= nil then list.items = {} end end
local function onClient(self, o, kind)
    if o == nil then error('IllegalArgumentException: globalObject is null', 3) end
    if getmetatable(o) ~= GO then error('No implementation found for ' .. kind .. 'GlobalObjectOnClient', 3) end
    if o.system ~= self then error('IllegalArgumentException: object not in this system', 3) end
    GLOBAL_OBJECTS_SENT[kind] = GLOBAL_OBJECTS_SENT[kind] + 1
end
function Sys:addGlobalObjectOnClient(o) onClient(self, o, 'add') end
function Sys:removeGlobalObjectOnClient(o) onClient(self, o, 'remove') end
function Sys:updateGlobalObjectOnClient(o) onClient(self, o, 'update') end
function Sys:sendCommand(command, args)
    if type(command) ~= 'string' then error('No implementation found for sendCommand', 2) end
    GLOBAL_OBJECTS_SENT.command = GLOBAL_OBJECTS_SENT.command + 1
end

function GO:getModData() return self.modData end
function GO:getX() return self.x end
function GO:getY() return self.y end
function GO:getZ() return self.z end
function GO:getSystem() return self.system end
function GO:getSquare() return getCell():getGridSquare(self.x, self.y, self.z) end

-- IsoGridSquare.java:9702-9718 : plante du système « farming » de la case (SGlobalObjects hors client MP).
function C.IsoGridSquare:getFarmingPlant()
    local s = SGO.getSystemByName('farming')
    if s == nil then return nil end
    return s:getObjectAt(self)
end
function C.IsoGridSquare:hasFarmingPlant() return self:getFarmingPlant() ~= nil end
'''


def lua_src(rel, base=None):
    """Source file of a Lua path relative to .../media/lua ('server/LivingKnox/LK_Homes.lua'): first mod that holds
    it among the core mod, Living Knox and RadioSurvivor (E18-T07), else base (RadioSurvivor by default) / rel."""
    base = LUA if base is None else base
    for root in (CORE_LUA, LK_LUA, base):
        if (root / rel).exists():
            return root / rel
    return base / rel


TESTS_SETUPS = {'core': (CORE_TESTS_LUA,), 'lk': LK_TESTS_LUA_ROOTS, 'rs': (CORE_TESTS_LUA, RS_TESTS_LUA),
                'both': TESTS_LUA_ROOTS}
_MERGED: dict[str, Path] = {}


def tests_lua(setup: str = 'both') -> Path:
    """media/lua of the test mods of a setup (TESTS_SETUPS) as the game sees it (E21-T07): the game merges the media/lua
    folders of the active mods, so a require or a path of one test mod finds the files of the others. One temporary
    folder per setup and process holds a copy of their files (removed at exit); 'lk' never holds a RadioSurvivor
    file."""
    if setup not in _MERGED:
        import atexit
        out = Path(tempfile.mkdtemp(prefix=f'rst_lua_{setup}_'))
        atexit.register(shutil.rmtree, out, True)
        for root in TESTS_SETUPS[setup]:
            shutil.copytree(root, out, dirs_exist_ok=True)
        _MERGED[setup] = out
    return _MERGED[setup]


def tests_lua_src(rel, roots=TESTS_LUA_ROOTS):
    """File of a test mod for a path relative to .../media/lua ('shared/RST/suites/RST_LKHomes.lua'): first test mod
    of roots that holds it (E21-T07), else roots[0] / rel."""
    for root in roots:
        if (root / rel).exists():
            return root / rel
    return roots[0] / rel


MISSION_VIEWS_DIR = CORE_LUA / 'client' / 'CoreAI' / 'MissionViews'


def mission_view_files():
    """Vues du carnet des gabarits de mission (E20-T01, mod commun depuis E21-T03) comme le jeu les charge : chaque
    fichier du dossier client/CoreAI/MissionViews/, trié par nom ; chacune s'inscrit au registre CA_MissionViews."""
    names = sorted((p.name for p in MISSION_VIEWS_DIR.glob('*.lua')), key=str.lower)
    return [f'client/CoreAI/MissionViews/{name}' for name in names]


def core_notebook_files():
    """Client files of the notebook of the core mod (E21-T03) as the game loads them: transport, frame, one file per
    common tab, then every mission view. The frame CA_Notebook is
    run by their require (the game runs a file once)."""
    names = ('CA_NotebookClient', 'CA_NotebookContacts', 'CA_NotebookMissions',
             'CA_NotebookReputation')
    return [f'client/CoreAI/{name}.lua' for name in names] + mission_view_files()


def rs_notebook_files():
    """Client files of RadioSurvivor's part of the notebook (E21-T03): Radio tab, its reputation acts and the
    views of its voice missions."""
    names = ('RS_NotebookRadio', 'RS_NotebookReputation', 'RS_VoiceMissionViews')
    return [f'client/RadioSurvivor/{name}.lua' for name in names]


ROUTINES_DIR = LK_LUA / 'server' / 'LivingKnox' / 'Routines'
CHORES_DIR = LK_LUA / 'server' / 'LivingKnox' / 'Chores'


def routine_files():
    """Fichiers des routines (LK15-T02) comme le jeu les charge : outils d'exécution, relevé, puis chaque activité du
    dossier Routines/ et chaque corvée du dossier Chores/ (LK16-T07), triées par nom comme le chargement du jeu
    (l'ordre entre activités et entre corvées vient de leur order)."""
    def listed(folder):
        names = sorted((p.name for p in folder.glob('*.lua')), key=str.lower)
        return [f'server/LivingKnox/{folder.name}/{name}' for name in names]
    return (['server/LivingKnox/LK_RoutineExec.lua', 'server/LivingKnox/LK_Routines.lua'] + listed(ROUTINES_DIR)
            + listed(CHORES_DIR))


FORTIFY_KINDS_DIR = LK_LUA / 'server' / 'LivingKnox' / 'Fortify'


def facade_parts(facade: str, folder: str):
    """Noms des fichiers du dossier folder que la façade server/LivingKnox/<facade> requiert (LK20-T07, LK20-T08 :
    socle et sections d'un moteur découpé), dans l'ordre de ses require."""
    pattern = re.compile(rf'^require "LivingKnox/{folder}/(\w+)"', re.M)
    return pattern.findall((LK_LUA / 'server' / 'LivingKnox' / facade).read_text(encoding='utf-8'))


def facade_sources(facade: str, folder: str):
    """Chemins de la façade server/LivingKnox/<facade> puis des fichiers de folder qu'elle requiert, dans l'ordre de
    ses require (LK20-T09 : texte complet d'un moteur découpé, pour les contrôles de source)."""
    base = LK_LUA / 'server' / 'LivingKnox'
    return [base / facade] + [base / folder / (name + '.lua') for name in facade_parts(facade, folder)]


def fortify_parts():
    """Noms des fichiers de Fortify/ que la façade LK_Fortify.lua requiert (LK20-T07 : socle et sections du moteur),
    dans l'ordre de ses require ; les autres fichiers du dossier sont les sortes de chantier."""
    return facade_parts('LK_Fortify.lua', 'Fortify')


def fortify_files():
    """Fichiers de la fortification (LK16-T02) comme le jeu les charge : façade (qui requiert le socle et les
    sections du moteur, LK20-T07), puis chaque fichier du dossier Fortify/ (trié par nom, comme le chargement du jeu ;
    l'ordre entre sortes vient de leur order ; un fichier du moteur relu ainsi ne fait que se redéfinir)."""
    names = sorted((p.name for p in FORTIFY_KINDS_DIR.glob('*.lua')), key=str.lower)
    return ['server/LivingKnox/LK_Fortify.lua'] + [f'server/LivingKnox/Fortify/{name}' for name in names]


FURNISHINGS_DIR = LK_LUA / 'server' / 'LivingKnox' / 'Furnishings'


def homes_files():
    """Fichiers de l'aménagement des foyers (LK16-T10) comme le jeu les charge : moteur, puis chaque aménagement du
    dossier Furnishings/ (trié par nom, comme le chargement du jeu ; l'ordre entre aménagements vient de leur order)."""
    names = sorted((p.name for p in FURNISHINGS_DIR.glob('*.lua')), key=str.lower)
    return ['server/LivingKnox/LK_Homes.lua'] + [f'server/LivingKnox/Furnishings/{name}' for name in names]


EXPEDITION_KINDS_DIR = LK_LUA / 'server' / 'LivingKnox' / 'Expeditions'
FOOD_REQUIRE = 'require "LivingKnox/LK_Food"'


def expedition_parts():
    """Noms des fichiers d'Expeditions/ que la façade LK_Expeditions.lua requiert (LK20-T08 : socle et sections du
    moteur), dans l'ordre de ses require ; les autres fichiers du dossier sont les genres."""
    return facade_parts('LK_Expeditions.lua', 'Expeditions')


def _expedition_kinds(food: bool):
    """Genres d'expédition du dossier Expeditions/ (triés par nom, comme le chargement du jeu ; l'ordre entre genres
    vient de leur order) : ceux qui requièrent la nourriture (food vrai) ou les autres. Les sections du moteur
    (LK20-T08), chargées par les require de la façade, n'en sont pas."""
    parts = set(expedition_parts())
    names = sorted((p.name for p in EXPEDITION_KINDS_DIR.glob('*.lua') if p.stem not in parts), key=str.lower)
    return [f'server/LivingKnox/Expeditions/{name}' for name in names
            if (FOOD_REQUIRE in (EXPEDITION_KINDS_DIR / name).read_text(encoding='utf-8')) == food]


def expedition_files():
    """Fichiers des expéditions (LK16-T08) comme le jeu les charge : moteur, puis chaque genre du dossier Expeditions/
    qui ne dépend pas de la nourriture (bâtiment)."""
    return ['server/LivingKnox/LK_Expeditions.lua'] + _expedition_kinds(False)


def food_files():
    """Fichiers de la nourriture (LK16-T08) : LK_Food, puis les genres d'expédition qu'elle inscrit (cueillette,
    pêche : fichiers du dossier Expeditions/ qui la requièrent). À charger après expedition_files()."""
    return ['server/LivingKnox/LK_Food.lua'] + _expedition_kinds(True)



SIM_EVENTS_DIR = LK_LUA / 'server' / 'LivingKnox' / 'SimEvents'


def sim_event_files():
    """Événements de groupe de la simulation hors écran (LK16-T09), un par fichier du dossier SimEvents/, triés par nom
    comme le chargement du jeu (l'ordre du tirage vient de leur order). À charger après LK_Simulation.lua (requis par
    LK_Server.lua)."""
    names = sorted((p.name for p in SIM_EVENTS_DIR.glob('*.lua')), key=str.lower)
    return [f'server/LivingKnox/SimEvents/{name}' for name in names]

# Lua vanilla réel (E19-T04, ADR banc mimétique D03) ------------------------------------------------------------------
VANILLA_MISSING = ('vanilla Lua not found: install Project Zomboid (PZ_STEAM_LIBRARY, PZ_DIR or PZ_MEDIA, '
                   'tools/pz_paths.py) or set PZ_SOURCE_DIR to the 42.22 reference sources (media/lua)')


def vanilla_lua_dir() -> Path | None:
    """Dossier media/lua vanilla : installation du jeu (tools/pz_paths.py), à défaut les sources de référence 42.22
    (PZ_SOURCE_DIR/media/lua) ; None si aucun des deux. Lecture seule : rien n'est copié dans le dépôt."""
    for root in (pz_paths.lua_dir(), pz_api.source_dir() / 'media' / 'lua'):
        if (root / 'shared').is_dir() and (root / 'server').is_dir():
            return root
    return None


def vanilla_module(rel: str) -> str:
    """Nom de require d'un fichier vanilla : 'server/Farming/SFarmingSystem.lua' -> 'Farming/SFarmingSystem'
    (LuaManager.require cherche « nom.lua » dans shared, client et server : LuaManager.java:4753-4766)."""
    side, _, rest = rel.replace('\\', '/').partition('/')
    if side not in ('shared', 'client', 'server') or not rest.endswith('.lua'):
        raise HarnessError(f'harness: vanilla path must be <shared|client|server>/....lua, got {rel!r}')
    return rest[:-4]


class HarnessError(AssertionError):
    pass


# --- API Java des doublures strictes (E19-T03) -----------------------------------------------------------------

class CallSpec(NamedTuple):
    """Nombres d'arguments acceptés par une méthode Java, self compris pour une surcharge d'instance (appel avec ':'),
    sans self pour une surcharge statique ; varmin : minimum d'une surcharge à varargs ; expected : paramètres de
    l'unique surcharge (message « expected N arguments, got M » de Kahlua), None sinon."""
    counts: frozenset
    varmin: int | None
    expected: int | None
    static: bool


def call_spec(arities, statics) -> CallSpec:
    """Spécification d'appel d'une méthode d'après ses surcharges (pz_api.Arity) et celles qui sont statiques."""
    counts, varmins = set(), []
    for a in arities:
        shift = 0 if a in statics else 1
        if a.varargs:
            varmins.append(a.params - 1 + shift)
        else:
            counts.add(a.params + shift)
    single = next(iter(arities)) if len(arities) == 1 else None
    expected = single.params if single is not None and not single.varargs else None
    return CallSpec(frozenset(counts), min(varmins) if varmins else None, expected,
                    single is not None and single in statics)


def compute_class_specs(cls: str) -> dict[str, CallSpec] | None:
    """Méthode -> CallSpec d'une classe exposée, d'après les sources de référence (pz_api) ; None si non exposée."""
    api = pz_api.api()
    methods = api.class_methods(cls)
    if methods is None:
        return None
    statics = api.class_static_methods(cls) or {}
    return {name: call_spec(arities, statics.get(name, set())) for name, arities in methods.items()}


class SpecStore:
    """Spécifications d'appel par classe, gardées en mémoire et dans un fichier JSON du dossier temporaire du système
    (jamais dans le dépôt : données tirées du Java du poste) pour que chaque processus de banc n'analyse pas le Java à
    nouveau (environ 0,6 s). Clé du fichier : dossier des sources, index des classes exposées, pz_api.py et ce fichier."""

    DIR = Path(tempfile.gettempdir()) / 'rs-harness-java-api'

    def __init__(self, root: str):
        stamps = [str(Path(root).resolve())]
        for path in (Path(root) / pz_api.EXPOSED_INDEX, Path(pz_api.__file__), Path(__file__)):
            stat = path.stat()
            stamps.append(f'{stat.st_mtime_ns}:{stat.st_size}')
        self.path = self.DIR / (hashlib.sha1('|'.join(stamps).encode()).hexdigest()[:16] + '.json')
        self._raw = self._read()
        self._specs: dict[str, dict[str, CallSpec] | None] = {}

    def _read(self) -> dict:
        try:
            return json.loads(self.path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            return {}

    def _write(self, cls: str, raw):
        """Ajoute une classe au fichier (relu d'abord : les bancs tournent en parallèle), remplacement atomique."""
        try:
            self.DIR.mkdir(parents=True, exist_ok=True)
            merged = {**self._read(), cls: raw}
            tmp = self.path.with_suffix(f'.{os.getpid()}.tmp')
            tmp.write_text(json.dumps(merged), encoding='utf-8')
            os.replace(tmp, self.path)
        except OSError:
            pass  # cache seulement : le calcul reste juste sans lui

    def get(self, cls: str) -> dict[str, CallSpec] | None:
        if cls not in self._specs:
            if cls in self._raw:
                raw = self._raw[cls]
                specs = None if raw is None else {m: CallSpec(frozenset(s[0]), s[1], s[2], s[3])
                                                  for m, s in raw.items()}
            else:
                specs = compute_class_specs(cls)
                self._write(cls, None if specs is None else
                            {m: [sorted(s.counts), s.varmin, s.expected, s.static] for m, s in specs.items()})
            self._specs[cls] = specs
        return self._specs[cls]


@functools.lru_cache(maxsize=None)
def _spec_store(root: str) -> SpecStore:
    return SpecStore(root)


def _class_specs(root: str, cls: str) -> dict[str, CallSpec] | None:
    return _spec_store(root).get(cls)


class JavaApiTable:
    """API Java 42.22 vue par les doublures : classes strictes, spécification d'appel, nom proche suggéré."""

    def __init__(self, root: str):
        self.root = root

    def strict(self, cls: str) -> bool:
        return not cls.endswith(HELPER_SUFFIX) and _class_specs(self.root, cls) is not None

    def spec(self, cls: str, method: str) -> CallSpec | None:
        specs = _class_specs(self.root, cls)
        return specs.get(method) if specs else None

    def suggest(self, cls: str, method: str) -> str | None:
        names = list(_class_specs(self.root, cls) or ())
        same_case = [n for n in names if n.lower() == method.lower()]
        close = same_case or difflib.get_close_matches(method, names, n=1, cutoff=0.8)
        return close[0] if close else None


def java_api_table(enabled: bool | None) -> JavaApiTable | None:
    """Table de l'API pour un Harness : None (doublures libres) si désactivée ou sans les sources de référence."""
    if enabled is False or not pz_api.available():
        return None
    return JavaApiTable(str(pz_api.source_dir()))


class _Bridge:
    """Fonctions Python appelées par le prélude Lua d'une machine."""

    def __init__(self, machine: 'Machine'):
        self.m = machine

    def print(self, line):
        self.m.log_lines.append(line)

    def client_send(self, module, command, args):
        self.m.harness._client_send(self.m, module, command, args)

    def server_send(self, username, module, command, args):
        self.m.harness._server_send(self.m, username, module, command, args)

    def send_relative(self, x, y, packet, args):
        self.m.harness.send_to_relative(x, y, packet, _to_py(args) if args is not None else None)

    def file_open(self, name, create, append):
        return self.m._file_open(name, create, append)

    def file_write(self, handle, text):
        self.m._writers[handle][1].append(text)

    def file_close(self, handle):
        self.m._file_close(handle)

    def file_read(self, name, create):
        return self.m._file_read(name, create)

    def set_time_of_day(self, hours):
        self.m.harness.set_time_of_day(hours)

    def api_strict(self, cls):
        return self.m.harness.java_api.strict(cls)

    def api_method(self, cls, method):
        spec = self.m.harness.java_api.spec(cls, method)
        if spec is None:
            return None
        fields = {'counts': self.m.rt.table_from({n: True for n in spec.counts}), 'static': spec.static}
        if spec.varmin is not None:
            fields['varmin'] = spec.varmin
        if spec.expected is not None:
            fields['expected'] = spec.expected
        return self.m.rt.table_from(fields)

    def api_suggest(self, cls, method):
        return self.m.harness.java_api.suggest(cls, method)


class Machine:
    """Une machine Lua : 'server', un client ('A', 'B'…) ou 'solo'."""

    def __init__(self, harness: 'Harness', name: str, mode: str, files: Path):
        self.harness, self.name, self.mode = harness, name, mode
        mods = [CORE_LUA, LK_LUA, LUA] if harness.with_rs else [CORE_LUA, LK_LUA]
        self.roots = mods + [Path(r) for r in harness.lua_roots]
        self.files = files
        files.mkdir(parents=True, exist_ok=True)
        self.log_lines: list[str] = []
        self._writers: dict[int, tuple[Path, list[str]]] = {}
        self._next_handle = 1
        self.ticks = 0
        self.paused = False
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False, register_builtins=False)
        self.g = self.rt.globals()
        self.g.python = None
        self.rt.execute(ENGINE, mode, name, _Bridge(self), self.rt.table_from(GAME_EVENTS), harness.debug,
                        harness.java_api is not None)
        self.H = self.g.HARNESS
        # Dédié : shared, client (somme de contrôle seulement), server (GameServer.java:1403-1405) ;
        # client MP et solo : shared, client au démarrage puis server au chargement (LuaManager.java:1242-1246,
        # GameLoadingState.java:153) : les fichiers server/ tournent aussi sur un client MP.
        self.sides = ('shared', 'server') if mode == 'server' else ('shared', 'client', 'server')
        paths = ';'.join((root / side).as_posix() + '/?.lua' for root in self.roots for side in self.sides)
        self.rt.execute(f'package.path = [[{paths}]]; package.cpath = ""')
        self._vanilla_root: Path | None = None

    # Lua --------------------------------------------------------------------------------------------
    def load(self, path_or_code: str):
        if '\n' not in path_or_code and path_or_code.endswith('.lua'):
            path = next((r / path_or_code for r in self.roots if (r / path_or_code).exists()),
                        self.roots[-1] / path_or_code)
            return self.H.run(path.read_text(encoding='utf-8'), '@' + path_or_code)
        return self.H.run(path_or_code, '=' + self.name)

    def load_vanilla(self, rel: str):
        """Exécute le fichier Lua vanilla rel ('server/Farming/SFarmingSystem.lua') du jeu installé, une fois par
        machine comme LuaManager.RunLuaInternal (fichier déjà chargé : rien, rend son retour gardé, LuaManager.java
        :1334-1336). Au premier appel, les dossiers vanilla des côtés de la machine passent après ceux des mods dans
        package.path : un require vanilla (« ISBaseObject », « Map/SGlobalObjectSystem ») trouve son fichier, marqué
        chargé lui aussi. Lève unittest.SkipTest (VANILLA_MISSING) sans le jeu ni les sources de référence."""
        root = vanilla_lua_dir()
        if root is None:
            raise unittest.SkipTest(VANILLA_MISSING)
        module = vanilla_module(rel)
        path = root / rel
        if not path.is_file():
            raise HarnessError(f'harness: vanilla Lua file not found: {path}')
        if self._vanilla_root is None:
            self._vanilla_root = root
            extra = ';'.join((root / side).as_posix() + '/?.lua' for side in self.sides)
            self.rt.execute(f'package.path = package.path .. [[;{extra}]]')
        return self.H.loadVanilla(module, path.read_text(encoding='utf-8-sig'), '@' + rel)

    def eval(self, expr: str):
        return self.load('return ' + expr)

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.rt.table_from({k: self.to_lua(v) for k, v in value.items()})
        if isinstance(value, (list, tuple)):
            return self.rt.table_from([self.to_lua(v) for v in value])
        return value

    def errors(self) -> list[str]:
        return [self.H.errors[i] for i in range(1, len(self.H.errors) + 1)]

    # Fichiers -----------------------------------------------------------------------------------------
    def _path(self, name: str):
        if not isinstance(name, str):
            raise LuaError(f'No implementation found for getFileWriter/getFileReader with name {name!r}')
        if '..' in name:  # LuaManager.hasRelativePath (java:6929-6935)
            return None
        rel = name.replace('\\', '/').lstrip('/')
        if re.match(r'^[A-Za-z]:', rel):
            raise HarnessError(f'harness: absolute path refused: {name}')
        return self.files / rel

    def _file_open(self, name, create, append):
        path = self._path(name)
        if path is None:
            return None
        base = re.split(r'[\\/]', name)[-1]
        ext = base.rsplit('.', 1)[1] if '.' in base else ''
        if ext not in FILE_EXTENSIONS:
            return None
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()  # FileOutputStream crée le fichier même sans createIfNull
        if not append:
            path.write_text('', encoding='utf-8')  # FileOutputStream(append=false) tronque dès l'ouverture
        handle = self._next_handle
        self._next_handle += 1
        self._writers[handle] = (path, [])
        return handle

    def _file_close(self, handle):
        entry = self._writers.pop(handle, None)
        if entry is None:
            return
        path, parts = entry
        with path.open('a', encoding='utf-8', newline='') as f:
            f.write(''.join(parts))

    def _file_read(self, name, create):
        path = self._path(name)
        if path is None:
            return None
        if not path.exists() and create:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        if not path.exists():
            return None
        text = path.read_text(encoding='utf-8')
        lines = re.split(r'\r\n|\r|\n', text)
        if lines and lines[-1] == '':
            lines.pop()
        return self.rt.table_from(lines)


def _to_py(value):
    if lupa.lua_type(value) == 'table':
        return {k: _to_py(v) for k, v in value.items()}
    return value


class Harness:
    def __init__(self, mode: str = 'mp', clients=('A', 'B'), order: str = 'fifo', seed: int = 0,
                 debug: bool = False, strict: bool = True, tick_ms: int = 16,
                 start=(1993, 7, 9, 9, 0), root: Path | None = None, lua_roots=(), java_api: bool | None = None,
                 relevant_range: int = RELEVANT_RANGE, delay: int = 0, with_rs: bool = True):
        if mode not in ('mp', 'solo'):
            raise ValueError("mode must be 'mp' or 'solo'")
        self.java_api = java_api_table(java_api)  # avant les machines : leurs classes en dépendent
        self.mode, self.order, self.debug, self.strict, self.tick_ms = mode, order, debug, strict, tick_ms
        self.lua_roots = list(lua_roots)  # racines media/lua supplémentaires, après celle du mod publié
        self.with_rs = with_rs  # E21-T08 : False = mod commun et Living Knox seuls (bancs de Living Knox)
        self.rng = random.Random(seed)
        self.zone = SendZone(relevant_range)   # serveur : zone d'envoi de chaque client
        self.delay = delay              # order='random' : pompes de retard au plus d'un message (renvoi après perte)
        self._tmp = None if root else tempfile.mkdtemp(prefix='lk_harness_')
        self.root = Path(root or self._tmp)
        self.queue: list[dict] = []
        self._sent_pos: dict[str, tuple] = {}   # client : dernière position envoyée au serveur
        self.frame = 0
        self._scheduled: list[tuple[int, object]] = []
        self.owners: dict[int, str] = {}
        self.real_ms = 1_790_000_000_000
        self.server_ms = 5_000_000
        self.date = _dt.datetime(*start)
        self.age_minutes = int((self.date.hour - 7) * 60 + self.date.minute)  # getWorldAgeHours = 0 à 7 h le 1er jour
        self._error_marks: dict[str, int] = {}
        if mode == 'solo':
            solo = Machine(self, 'solo', 'solo', self.root / 'solo' / 'Lua')
            self.machines = {'solo': solo}
            self.server = solo
            self.clients = {clients[0]: solo}
            solo.H.addPlayer(clients[0], 0, 0, 0, 0, True)
        else:
            self.server = Machine(self, 'server', 'server', self.root / 'server' / 'Lua')
            self.clients = {c: Machine(self, c, 'client', self.root / c / 'Lua') for c in clients}
            self.machines = {'server': self.server, **self.clients}
            for m in self.machines.values():
                for i, c in enumerate(clients):
                    m.H.addPlayer(c, i, 0, 0, 0, m.name == c)
            for c in clients:   # connexion : releventPos = position du joueur (GameServer.java:2646-2648)
                self._sent_pos[c] = self._position(c)
                self.zone.report(c, *self._sent_pos[c])
        self._push_clock()
        self._mark()

    # Accès --------------------------------------------------------------------------------------------
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def close(self):
        if self._tmp:
            shutil.rmtree(self._tmp, ignore_errors=True)
            self._tmp = None

    def machine(self, name) -> Machine:
        if isinstance(name, Machine):
            return name
        if self.mode == 'solo':
            if name in ('solo', 'server') or name in self.clients:
                return self.server
        return self.machines[name]

    def load(self, machine, path_or_code: str):
        return self.machine(machine).load(path_or_code)

    def load_vanilla(self, machine, *rels: str):
        """Fichiers Lua vanilla du jeu installé, dans l'ordre donné (Machine.load_vanilla) ; rend le retour du
        dernier. Sans le jeu ni les sources de référence : unittest.SkipTest."""
        result = None
        for rel in rels:
            result = self.machine(machine).load_vanilla(rel)
        return result

    def eval(self, machine, expr: str):
        return self.machine(machine).eval(expr)

    def logs(self, machine) -> list[str]:
        return list(self.machine(machine).log_lines)

    def errors(self, machine) -> list[str]:
        return self.machine(machine).errors()

    def file_root(self, machine) -> Path:
        return self.machine(machine).files

    def zombie(self, machine, zid):
        return self.machine(machine).H.zombies[zid]

    def player(self, machine, username):
        return self.machine(machine).H.players[username]

    def _all(self):
        return list(self.machines.values())

    # Erreurs d'abonnés ----------------------------------------------------------------------------------
    def _mark(self):
        self._error_marks = {m.name: len(m.H.errors) for m in self._all()}

    def _check(self):
        new = []
        for m in self._all():
            errs = m.errors()
            new += [f'{m.name}: {e}' for e in errs[self._error_marks.get(m.name, 0):]]
        self._mark()
        if new and self.strict:
            raise HarnessError('Lua errors in event callbacks:\n' + '\n'.join(new))

    # Monde ----------------------------------------------------------------------------------------------
    def spawn_zombie(self, zid: int, x, y, z=0, owner: str = 'server'):
        self._check_owner(owner)
        self.owners[zid] = owner
        for m in self._all():
            m.H.spawnZombie(zid, x, y, z, owner)

    def _check_owner(self, owner):
        if self.mode == 'mp' and owner not in self.machines:
            raise ValueError(f'unknown owner {owner!r}')

    def set_owner(self, zid: int, owner: str, via_network: bool = False):
        """Nouveau propriétaire. via_network (MP) : le serveur le pose à l'instant (NetworkZombiePacker.postupdate),
        chaque client ne l'apprend qu'à la livraison de son paquet ZombieList (non fiable, non ordonné avec les
        commandes Lua : ZombieListPacket.java:15) ; l'ancien propriétaire se croit propriétaire jusque-là."""
        self._check_owner(owner)
        self.owners[zid] = owner
        if not via_network or self.mode != 'mp':
            for m in self._all():
                m.H.zombies[zid].owner = owner
            return
        self.server.H.zombies[zid].owner = owner
        for c in self.clients:
            self._enqueue_packet('server', c, 'ZombieList', {'zid': zid, 'owner': owner})

    def move_zombie(self, zid, x, y, z=None):
        for m in self._all():
            zb = m.H.zombies[zid]
            m.H.place(zb, x, y, zb.z if z is None else z)

    def move_player(self, username, x, y, z=None):
        for m in self._all():
            p = m.H.players[username]
            m.H.place(p, x, y, p.z if z is None else z)

    def kill_zombie(self, zid, events=('OnCharacterDeath',)):
        """Marque mort partout, déclenche les événements (machine par machine) puis retire le zombie des listes."""
        for m in self._all():
            zb = m.H.zombies[zid]
            zb.dead = True
            for e in events:
                m.H.trigger(e, zb)
            m.H.removeZombie(zid)
        self.owners.pop(zid, None)
        self._check()

    def kill_player(self, username, events=('OnCharacterDeath',)):
        for m in self._all():
            p = m.H.players[username]
            p.dead = True
            for e in events:
                m.H.trigger(e, p)
        self._check()

    # Événements -----------------------------------------------------------------------------------------
    def fire(self, machine, event: str, *args):
        m = self.machine(machine)
        result = m.H.trigger(event, *[m.to_lua(a) for a in args])
        self._check()
        return result

    def tick(self, n: int = 1):
        """IngameState.java:1380 (OnTickEvenPaused), 1543 (IsoWorld.update -> OnZombieUpdate), 1604, 1681 (OnTick).
        MP : à la fin de l'image, chaque client dont le joueur a bougé envoie sa position (PlayerUpdate) ; puis les
        actions de at_tick dues."""
        for _ in range(n):
            self.advance_ms(self.tick_ms)
            for m in self._all():
                m.H.trigger('OnTickEvenPaused', float(m.ticks))
                if m.paused:
                    continue
                m.H.updateZombies()
                m.ticks += 1
                m.H.trigger('OnTick', float(m.ticks))
            self._send_positions()
            self.frame += 1
            self._run_scheduled()
        self._check()

    def at_tick(self, n: int, action):
        """action() jouée à la fin de la n-ième image à venir (changement de propriétaire pendant une scène...)."""
        self._scheduled.append((self.frame + int(n), action))

    def _run_scheduled(self):
        due = [a for f, a in self._scheduled if f <= self.frame]
        self._scheduled = [(f, a) for f, a in self._scheduled if f > self.frame]
        for action in due:
            action()

    def set_paused(self, machine, paused: bool = True):
        self.machine(machine).paused = paused

    # Horloges -------------------------------------------------------------------------------------------
    def _push_clock(self):
        d = self.date
        for m in self._all():
            c = m.H.clock
            c.realMs, c.serverMs = self.real_ms, self.server_ms
            c.year, c.month, c.day, c.hour, c.minute = d.year, d.month - 1, d.day - 1, d.hour, d.minute
            c.ageHours = self.age_minutes / 60.0
            c.nights = self.age_minutes // 1440                  # âge 0 à 7 h : une nuit de plus à chaque 7 h

    def advance_ms(self, ms: int):
        self.real_ms += int(ms)
        self.server_ms += int(ms)
        self._push_clock()

    def set_clock_synced(self, client: str, synced: bool = True):
        self.machine(client).H.clock.synced = synced

    def advance(self, minutes: int = 1):
        """Une mise à jour de GameTime par minute (GameTime.java:431-580, 42.22) : horloge avancée d'abord, puis sur
        chaque machine non en pause EveryDays (minuit), EveryHours (heure changée), EveryTenMinutes (dizaine
        changée), EveryOneMinute. Vitesse normale : jamais plus d'une minute par mise à jour."""
        for _ in range(int(minutes)):
            before = self.date
            self.date += _dt.timedelta(minutes=1)
            self.age_minutes += 1
            self._push_clock()
            events = [name for name, changed in (
                ('EveryDays', self.date.date() != before.date()),
                ('EveryHours', self.date.hour != before.hour),
                ('EveryTenMinutes', self.date.minute // 10 != before.minute // 10),
                ('EveryOneMinute', True)) if changed]
            for m in self._all():
                if m.paused:
                    continue
                for name in events:
                    m.H.trigger(name)
        self._check()

    def jump_to(self, hour: int, minute: int = 0):
        """Avance l'horloge, sans événement, jusqu'à la prochaine heure du jour hour:minute (strictement plus tard) :
        partie chargée à cette heure."""
        now = self.date.hour * 60 + self.date.minute
        self.skip((hour * 60 + minute - now) % 1440 or 1440)

    def skip(self, minutes: int):
        """Avance l'horloge de minutes sans aucun événement : temps passé serveur arrêté (heures manquées rattrapées
        au démarrage) ou partie rechargée plus tard."""
        self.date += _dt.timedelta(minutes=int(minutes))
        self.age_minutes += int(minutes)
        self._push_clock()

    def set_time_of_day(self, hours: float):
        """GameTime.setTimeOfDay (GameTime.java:764-766) : heure du jour seule, à la minute (getMinutes, 423-424) ;
        jour du calendrier et nuits survécues gardés, âge du monde recalculé (824-827) ; aucun événement."""
        tod = int(float(hours) * 60) % 1440
        nights = self.age_minutes // 1440
        self.date = self.date.replace(hour=tod // 60, minute=tod % 60)
        self.age_minutes = nights * 1440 + (tod - 420) % 1440
        self._push_clock()

    # Réseau ---------------------------------------------------------------------------------------------
    def _client_send(self, sender: Machine, module, command, args):
        payload = None if args is None else _to_py(args)
        if sender.mode == 'solo':
            # SinglePlayerClient : relais direct, traité pendant l'envoi.
            sender.H.trigger('OnClientCommand', module, command, sender.H.localPlayer, sender.to_lua(payload))
            return
        self.queue.append({'to': 'server', 'from': sender.name, 'module': module, 'command': command,
                           'args': payload})

    def _server_send(self, sender: Machine, username, module, command, args):
        payload = None if args is None else _to_py(args)
        targets = [username] if username else list(self.clients)
        for t in targets:
            if t in self.clients:
                self.queue.append({'to': t, 'from': 'server', 'module': module, 'command': command,
                                   'args': payload})

    _COMMAND_KEYS = ('to', 'from', 'module', 'command', 'args')

    def pending(self) -> list[dict]:
        """Commandes Lua en attente (sendClientCommand / sendServerCommand), sans les paquets du moteur."""
        return [{k: msg[k] for k in self._COMMAND_KEYS} for msg in self.queue if 'packet' not in msg]

    def pending_packets(self) -> list[dict]:
        """Paquets du moteur en attente (position du joueur, paquets liés à une case, ZombieList)."""
        return [{k: msg[k] for k in ('to', 'from', 'packet', 'args')} for msg in self.queue if 'packet' in msg]

    # Zone d'envoi (E19-T06) ------------------------------------------------------------------------------
    def _position(self, username) -> tuple:
        """Position du joueur sur sa propre machine (celle qu'il signale au serveur)."""
        p = self.machines[username].H.players[username]
        return (p.x, p.y, p.z)

    @property
    def relevant_range(self) -> int:
        return self.zone.relevant_range

    def relevant_to(self, client: str, x, y) -> bool:
        """Le serveur écrirait-il maintenant à ce client un paquet lié à la case x, y (SendZone)."""
        return self.zone.relevant_to(client, x, y)

    def _send_positions(self):
        """Fin d'image d'un client : position envoyée au serveur si elle a changé (NetworkPlayerAI.java:300-333, paquet
        fiable dès que la case change ; téléportation : GameClient.sendPlayer, TeleportPacket.java:70-76). Le serveur
        la prend à la livraison : jusque-là, le client reste compté à son ancienne place. Solo : aucun réseau."""
        if self.mode != 'mp':
            return
        for c, m in self.clients.items():
            if m.paused:
                continue
            pos = self._position(c)
            if pos != self._sent_pos[c]:
                self._sent_pos[c] = pos
                self._enqueue_packet(c, 'server', 'PlayerUpdate', {'x': pos[0], 'y': pos[1], 'z': pos[2]})

    def send_to_relative(self, x, y, packet: str, args):
        """Paquet du serveur lié à la case x, y, mis en file pour chaque client dont la zone la couvre AU MOMENT de
        l'envoi (INetworkPacket.java:182-189, GameServer.sendCorpse 1869-1883) ; un client hors zone ne le reçoit
        jamais (aucun renvoi : il ne verra l'objet qu'avec la case rechargée)."""
        if self.mode != 'mp':
            return
        for c in self.zone.relevant_clients(x, y):
            self._enqueue_packet('server', c, packet, args)

    def _enqueue_packet(self, sender: str, to: str, packet: str, args):
        if packet not in PACKET_CHANNELS:
            raise HarnessError(f'harness: packet {packet!r} not simulated (PACKET_CHANNELS)')
        self.queue.append({'to': to, 'from': sender, 'packet': packet, 'args': args,
                           'channel': PACKET_CHANNELS[packet]})

    # Livraison ------------------------------------------------------------------------------------------
    @staticmethod
    def _stream(msg):
        """Flux ordonné RakNet d'un message (émetteur, destinataire, canal), ou None (aucun ordre garanti)."""
        channel = msg.get('channel')
        return None if channel is None else (msg['from'], msg['to'], channel)

    def _take_ready(self, order):
        """Sépare la file en messages livrables et retenus. order='random' avec delay : chaque message vu pour la
        première fois est retenu 0 à delay pompes (paquet perdu puis renvoyé) ; un message retenu d'un flux ordonné
        retient les suivants de son flux."""
        ready, held, blocked = [], [], set()
        for msg in self.queue:
            if 'hold' not in msg:
                msg['hold'] = self.rng.randint(0, self.delay) if order == 'random' and self.delay > 0 else 0
            stream = self._stream(msg)
            if msg['hold'] > 0 or (stream is not None and stream in blocked):
                held.append(msg)
                if stream is not None:
                    blocked.add(stream)
            else:
                ready.append(msg)
        return ready, held

    def _arrange(self, batch, order):
        """Ordre de livraison d'un lot : fifo, lifo ou random sur l'ensemble, puis chaque flux ordonné remis dans son
        ordre d'envoi aux places qu'il occupe (RELIABLE_ORDERED : ordre garanti dans un flux, aucun entre flux)."""
        arranged = list(batch)
        if order == 'lifo':
            arranged.reverse()
        elif order == 'random':
            self.rng.shuffle(arranged)
        streams: dict = {}
        for msg in batch:
            stream = self._stream(msg)
            if stream is not None:
                streams.setdefault(stream, []).append(msg)
        for stream, sent in streams.items():
            slots = [i for i, msg in enumerate(arranged) if self._stream(msg) == stream]
            for i, msg in zip(slots, sent):
                arranged[i] = msg
        return arranged

    def pump(self, order: str | None = None, limit: int | None = None) -> int:
        """Livre la file : messages livrables par lots (ceux qu'une livraison envoie forment le lot suivant), dans
        l'ordre demandé ; rend le nombre de commandes Lua livrées (les paquets du moteur ne comptent pas)."""
        order = order or self.order
        if order not in ORDERS:
            raise ValueError(f'unknown order {order!r}')
        for msg in self.queue:
            if msg.get('hold', 0) > 0:
                msg['hold'] -= 1
        delivered = handled = 0
        while limit is None or delivered < limit:
            batch, held = self._take_ready(order)
            if not batch:
                break
            self.queue = held
            batch = self._arrange(batch, order)
            for i, msg in enumerate(batch):
                if limit is not None and delivered >= limit:
                    self.queue = batch[i:] + self.queue
                    break
                self._deliver(msg)
                handled += 1
                if 'packet' not in msg:
                    delivered += 1
            if handled > 100_000:
                raise HarnessError('harness: network loop (more than 100000 messages)')
        self._check()
        return delivered

    def _deliver(self, msg):
        if 'packet' in msg:
            self._deliver_packet(msg)
        elif msg['to'] == 'server':
            m = self.server
            player = m.H.players[msg['from']]
            m.H.trigger('OnClientCommand', msg['module'], msg['command'], player, m.to_lua(msg['args']))
        else:
            m = self.clients[msg['to']]
            m.H.trigger('OnServerCommand', msg['module'], msg['command'], m.to_lua(msg['args']))

    def _deliver_packet(self, msg):
        args = msg['args']
        if msg['packet'] == 'PlayerUpdate':
            self.zone.report(msg['from'], args['x'], args['y'], args['z'])
        elif msg['packet'] == 'ZombieList':
            zb = self.clients[msg['to']].H.zombies[args['zid']]
            if zb is not None:
                zb.owner = args['owner']
        else:
            m = self.clients[msg['to']]
            m.H.receivePacket(msg['packet'], m.to_lua(args))
