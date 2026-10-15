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
    h.load('A', 'X = 1')                    # ou une chaîne Lua ; rend les valeurs du bloc
    h.eval('A', 'X')                        # valeur d'une expression Lua
    h.spawn_zombie(1001, 10, 20, 0, owner='A')   # zombie chargé sur toutes les machines ; owner : 'server', 'A', 'B'
    h.set_owner(1001, 'B')                  # transfert instantané (le jeu exige distance et délai)
    h.move_zombie(1001, 11, 20); h.kill_zombie(1001); h.move_player('A', 5, 5, 0); h.kill_player('A')
    h.zombie('A', 1001), h.player('server', 'A')   # objets Lua de cette machine
    h.fire('server', 'OnTick', 0)           # déclenche un événement (dict/list Python convertis en tables)
    h.tick(n)                               # n images : par machine OnTickEvenPaused, OnZombieUpdate, OnTick
    h.pump(order='fifo'|'lifo'|'random', limit=None)   # livre la file réseau ; rend le nombre livré
    h.pending()                             # messages en attente (dicts)
    h.advance(minutes)                      # horloge de jeu ; EveryTenMinutes puis EveryOneMinute à chaque minute
    h.advance_ms(ms)                        # horloge réelle (getTimestampMs, GameTime.getServerTimeMills)
    h.set_clock_synced('A', False)          # getServerTimeMills() rend 0 sur ce client
    h.set_paused('server', True)            # serveur vide en pause : OnTickEvenPaused seul
    h.logs('server'), h.errors('server')    # lignes print ; erreurs attrapées dans les abonnés d'événements
    h.file_root('A')                        # dossier Zomboid/Lua simulé de la machine
    h.close()                               # ou « with Harness() as h: »

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
- Zombies (NetworkZombieComponent.java:23) : isRemoteZombie() = aucune connexion propriétaire. Client : faux pour
  le zombie qu'il simule, vrai sinon. Serveur : vrai pour un zombie qu'il simule, faux pour un zombie possédé par un
  client (getOwner() rend alors sa connexion, getOwnerPlayer() son joueur). Solo : toujours vrai, getOwner() nil ; OnZombieUpdate pour tous les zombies chargés, locaux ou distants (IsoZombie.java:2738).
"""
from __future__ import annotations

import datetime as _dt
import random
import re
import shutil
import tempfile
from pathlib import Path

import lupa.lua51 as lupa

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua'
LuaError = lupa.LuaError

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
local MODE, NAME, PY, EVENT_NAMES, DEBUG = ...
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
local classes = {}
local function class(name, parent)
    local c = { __javaName = name, __parent = parent }
    c.__index = c
    c.__tostring = function(o) return name .. '@' .. tostring(rawget(o, '__id') or '?') end
    if parent then setmetatable(c, { __index = parent }) end
    classes[name] = c
    return c
end
H.class, H.classes = class, classes

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
-- LK06-T08 : IsoGridSquare.java:971-977 (fenêtre fermée ou barricadée du bord commun) ; pièce de la case
-- (self.room, nil = dehors). Aucune fenêtre ni pièce sur le banc (doublures de test_lk_window_lure.py).
function IsoGridSquare:isWindowBlockedTo(other) return false end
function IsoGridSquare:getRoom() return self.room end

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
local IsoGameCharacter = class('IsoGameCharacter', IsoMovingObject)
function IsoGameCharacter:isDead() return self.dead == true end
function IsoGameCharacter:getOnlineID() return self.onlineID end
function IsoGameCharacter:isZombie() return false end
function IsoGameCharacter:getVehicle() return self.vehicle end  -- IsoGameCharacter.java:10202 (nil hors vehicule)
-- IsoGameCharacter.java:13210 : état d'action courant (nom de dossier d'actiongroups en minuscules) ; self.actionState.
function IsoGameCharacter:getActionStateName() return self.actionState or 'idle' end
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
    ageHours = 2, multiplier = 1 }
getTimestampMs = function() return H.clock.realMs end
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

function H.run(src, chunkname)
    local f, err = loadstring(src, chunkname)
    if not f then error(err, 0) end
    return f()
end
'''


class HarnessError(AssertionError):
    pass


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

    def file_open(self, name, create, append):
        return self.m._file_open(name, create, append)

    def file_write(self, handle, text):
        self.m._writers[handle][1].append(text)

    def file_close(self, handle):
        self.m._file_close(handle)

    def file_read(self, name, create):
        return self.m._file_read(name, create)


class Machine:
    """Une machine Lua : 'server', un client ('A', 'B'…) ou 'solo'."""

    def __init__(self, harness: 'Harness', name: str, mode: str, files: Path):
        self.harness, self.name, self.mode = harness, name, mode
        self.roots = [LUA] + [Path(r) for r in harness.lua_roots]
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
        self.rt.execute(ENGINE, mode, name, _Bridge(self), self.rt.table_from(GAME_EVENTS), harness.debug)
        self.H = self.g.HARNESS
        # Dédié : shared, client (somme de contrôle seulement), server (GameServer.java:1403-1405) ;
        # client MP et solo : shared, client au démarrage puis server au chargement (LuaManager.java:1242-1246,
        # GameLoadingState.java:153) : les fichiers server/ tournent aussi sur un client MP.
        sides = ('shared', 'server') if mode == 'server' else ('shared', 'client', 'server')
        paths = ';'.join((root / side).as_posix() + '/?.lua' for root in self.roots for side in sides)
        self.rt.execute(f'package.path = [[{paths}]]; package.cpath = ""')

    # Lua --------------------------------------------------------------------------------------------
    def load(self, path_or_code: str):
        if '\n' not in path_or_code and path_or_code.endswith('.lua'):
            path = next((r / path_or_code for r in self.roots if (r / path_or_code).exists()), LUA / path_or_code)
            return self.H.run(path.read_text(encoding='utf-8'), '@' + path_or_code)
        return self.H.run(path_or_code, '=' + self.name)

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
                 start=(1993, 7, 9, 9, 0), root: Path | None = None, lua_roots=()):
        if mode not in ('mp', 'solo'):
            raise ValueError("mode must be 'mp' or 'solo'")
        self.mode, self.order, self.debug, self.strict, self.tick_ms = mode, order, debug, strict, tick_ms
        self.lua_roots = list(lua_roots)  # racines media/lua supplémentaires, après celle du mod publié
        self.rng = random.Random(seed)
        self._tmp = None if root else tempfile.mkdtemp(prefix='lk_harness_')
        self.root = Path(root or self._tmp)
        self.queue: list[dict] = []
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

    def set_owner(self, zid: int, owner: str):
        self._check_owner(owner)
        self.owners[zid] = owner
        for m in self._all():
            m.H.zombies[zid].owner = owner

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
        """IngameState.java:1380 (OnTickEvenPaused), 1543 (IsoWorld.update -> OnZombieUpdate), 1604, 1681 (OnTick)."""
        for _ in range(n):
            self.advance_ms(self.tick_ms)
            for m in self._all():
                m.H.trigger('OnTickEvenPaused', float(m.ticks))
                if m.paused:
                    continue
                m.H.updateZombies()
                m.ticks += 1
                m.H.trigger('OnTick', float(m.ticks))
        self._check()

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

    def advance_ms(self, ms: int):
        self.real_ms += int(ms)
        self.server_ms += int(ms)
        self._push_clock()

    def set_clock_synced(self, client: str, synced: bool = True):
        self.machine(client).H.clock.synced = synced

    def advance(self, minutes: int = 1):
        """GameTime.java:565-581 : EveryTenMinutes (changement de dizaine) puis EveryOneMinute, sur chaque machine."""
        for _ in range(int(minutes)):
            before = self.date
            self.date += _dt.timedelta(minutes=1)
            self.age_minutes += 1
            self._push_clock()
            for m in self._all():
                if self.date.minute // 10 != before.minute // 10:
                    m.H.trigger('EveryTenMinutes')
                m.H.trigger('EveryOneMinute')
        self._check()

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

    def pending(self) -> list[dict]:
        return [dict(msg) for msg in self.queue]

    def pump(self, order: str | None = None, limit: int | None = None) -> int:
        order = order or self.order
        delivered = 0
        while self.queue and (limit is None or delivered < limit):
            batch, self.queue = self.queue, []
            if order == 'lifo':
                batch.reverse()
            elif order == 'random':
                self.rng.shuffle(batch)
            elif order != 'fifo':
                raise ValueError(f'unknown order {order!r}')
            for i, msg in enumerate(batch):
                if limit is not None and delivered >= limit:
                    self.queue = batch[i:] + self.queue
                    break
                self._deliver(msg)
                delivered += 1
            if delivered > 100_000:
                raise HarnessError('harness: network loop (more than 100000 messages)')
        self._check()
        return delivered

    def _deliver(self, msg):
        if msg['to'] == 'server':
            m = self.server
            player = m.H.players[msg['from']]
            m.H.trigger('OnClientCommand', msg['module'], msg['command'], player, m.to_lua(msg['args']))
        else:
            m = self.clients[msg['to']]
            m.H.trigger('OnServerCommand', msg['module'], msg['command'], m.to_lua(msg['args']))
