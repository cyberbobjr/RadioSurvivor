"""Banc hors jeu des suites en jeu radio, carnet et factions des contrôles MP (classe « c » de l'audit du 2026-10-15) :
rs.worldradio (E06-T03), rs.radio (E06-T05), rs.carnet.load (E00-T04), rs.observations (E08-T07),
rs.factions.mandate (E09-T03), et de leurs étapes client (RST_PeerChecksRadio.lua).

    python RadioSurvivor/tests/test_rs_mp_suites.py

Chaque suite est jouée par le VRAI moteur RST (RST.lua, RST_Steps.lua, RST_Fixtures.lua) sur un serveur dédié simulé
et deux clients (une machine lupa chacun, `next` retiré comme dans Kahlua ; réseau en file, tables copiées comme le
réseau, livrées au tick suivant), puis en solo (une seule machine, sendClientCommand traité au tick suivant comme le
jeu, réponses de l'autorité remises directement aux modules client). Ce qui est réel ici : RadioSurvivor_Const,
RS_State, RS_Codec, RS_Config, RS_RadioLog (historique radio, côté serveur), RS_RadioHistory (copie client),
RS_Factions (avec la doublure de zombie.characters.Faction de tests/test_factions.py), RS_Observations et
RS_ObservationTriggers, LK_Core (listen / publish). Doublures : monde Java (cases, IsoRadio sans sprite, DeviceData,
inventaire, véhicule et sièges, paquets VehicleEnter et Faction*), juge de la commande talk (même ordre de contrôles
que RadioSurvivor_Server.findRadio : radio, portée du micro, allumage, siège), serveur et client du carnet réduits à ce
que les suites lisent (hello, snapshot, select, mandate, scan, purge, sauvegarde conditionnelle), moteur Living Knox
réduit à son API publique de test, ses groupes et son fait d'agression.
Chaque suite passe sur les doublures et échoue sur un défaut injecté (DEFECTS) qui contredit son critère. Ce banc ne
prouve ni l'API Java du jeu ni le vrai serveur du carnet (couverts par test_carnet, test_factions, test_observations,
test_radio_history, test_protocol) : l'exécution en jeu (campagne MP à deux clients, solo) reste nécessaire.
"""
from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

import lupa.lua51 as lupa

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_factions import FACTION_DOUBLE  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DEV = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua'
MOD = ROOT / 'Contents' / 'mods' / 'batman_RadioSurvivor' / '42.21' / 'media' / 'lua'
SUITES = DEV / 'shared' / 'RST' / 'suites'
STEPS_FILES = [DEV / 'shared' / 'RST' / name for name in ('RST_Steps.lua', 'RST_Fixtures.lua', 'RST_PeerChecksRadio.lua')]
SUITE_FILES = {name: SUITES / f'{name}.lua' for name in ('RS_WorldRadio', 'RS_RadioMP', 'RS_CarnetLoad',
                                                         'RS_ObservationWitnesses', 'RS_FactionsMandate')}
NEW_LUA = [DEV / 'shared' / 'RST' / 'RST_PeerChecksRadio.lua', *SUITE_FILES.values()]

# ------------------------------------------------------------------------------------------------ Java doubles

JAVA = r'''
CLOCK = 1000000
getTimestampMs = function() return CLOCK end
isServer = function() return ROLE == "server" end
isClient = function() return ROLE == "client" end
isDebugEnabled = function() return true end
LOGS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(t, " ") end
function logged(pattern) for _, l in ipairs(LOGS) do if string.find(l, pattern, 1, true) then return l end end end
WORLD_NAME = "rstest_bench"
getWorld = function() return { getWorld = function() return WORLD_NAME end,
    getGameMode = function() return ROLE == "solo" and "Sandbox" or "Multiplayer" end } end
getCore = function() return { getVersion = function() return "42.21.0 bench" end } end
getActivatedMods = function() return JList({ "batman_RadioSurvivor", "batman_RadioSurvivorTests" }) end
local seed = 0
ZombRand = function(a, b) seed = seed + 1 if b then return a + (seed % (b - a)) end return seed % a end
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    e.Add = function(f) table.insert(e.list, f) end
    e.Remove = function(f) for i, g in ipairs(e.list) do if g == f then table.remove(e.list, i) return end end end
    rawset(t, k, e) return e end })
function fire(name, ...) local copy = {} for i, f in ipairs(Events[name].list) do copy[i] = f end
    for _, f in ipairs(copy) do f(...) end end
triggerEvent = function(name, ...) fire(name, ...) end
-- LuaManager.getFileWriter / getFileReader under this machine's Zomboid/Lua (txt only, no "..").
getFileWriter = function(name, create, append)
    if not string.find(name, "%.txt$") or string.find(name, "%.%.") then return nil end
    local full = FILE_ROOT .. "/" .. name
    mkdirs(full)
    local f = assert(io.open(full, append and "a" or "w"))
    return { write = function(self, s) f:write(s) end, writeln = function(self, s) f:write(s, "\n") end,
        close = function(self) f:close() end }
end
getFileReader = function(name, create)
    if string.find(name, "%.%.") then return nil end
    local f = io.open(FILE_ROOT .. "/" .. name, "r")
    if not f then return nil end
    return { readLine = function(self) return f:read("*l") end, close = function(self) f:close() end }
end
SandboxVars = { RadioSurvivor = { Enabled = true, PlayerCooldown = 10 }, LivingKnox = { Enabled = true } }
getSandboxOptions = function() return nil end
GAME_HOURS = 100.5
getGameTime = function() return { getWorldAgeHours = function() return GAME_HOURS end,
    getYear = function() return 1993 end, getMonth = function() return 6 end, getDay = function() return 11 end,
    getHour = function() return 4 end, getMinutes = function() return 30 end } end
getText = function(k) return k end
HaloTextHelper = { addGoodText = function() end, addBadText = function() end }

function JList(items)
    local l = { items = items or {} }
    function l:size() return #self.items end
    function l:get(i) return self.items[i + 1] end
    function l:add(v) self.items[#self.items + 1] = v return true end
    function l:remove(v) for i, x in ipairs(self.items) do if x == v then table.remove(self.items, i) return true end end
        return false end
    function l:contains(v) for _, x in ipairs(self.items) do if x == v then return true end end return false end
    return l
end
local function classes(...) local c = {} for _, n in ipairs({ ... }) do c[n] = true end return c end
CLASSES = classes
instanceof = function(o, c) return type(o) == "table" and type(o.classes) == "table" and o.classes[c] == true end

-- Squares: x, y within 60 of 1000 are loaded; x < 1005 inside the house, outside beyond.
local squares = {}
CELL = {}
function CELL:getGridSquare(x, y, z)
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    if math.abs(x - 1000) > 60 or math.abs(y - 1000) > 60 then return nil end
    local key = x .. "," .. y .. "," .. z
    local sq = squares[key]
    if sq == nil then
        sq = { x = x, y = y, z = z, objects = JList({}), statics = JList({}) }
        function sq:getX() return self.x end
        function sq:getY() return self.y end
        function sq:getZ() return self.z end
        function sq:getObjects() return self.objects end
        function sq:getStaticMovingObjects() return self.statics end
        function sq:isOutside() return self.x >= 1005 end
        function sq:getBuilding() if self.x >= 1005 then return nil end return { house = true } end
        function sq:isFree() return true end
        function sq:transmitAddObjectToSquare(o, i) o.square = self; self.objects:add(o) end
        function sq:transmitRemoveItemFromSquare(o) self.objects:remove(o); o.square = nil end
        function sq:removeCorpse(o) self.statics:remove(o) end
        squares[key] = sq
    end
    return sq
end
getCell = function() return CELL end

-- DeviceData (zombie.radio.devices.DeviceData): defaults of the Java class (micRange 5, 200..1000000, 88000).
function newDevice()
    local d = { twoWay = false, mic = 5, on = false, channel = 88000, min = 200, max = 1000000, batteryPowered = true,
        hasBattery = true, power = 1.0, portable = false, muted = false }
    function d:setIsTwoWay(b) self.twoWay = b end
    function d:getIsTwoWay() return self.twoWay end
    function d:setMicRange(r) self.mic = r end
    function d:getMicRange() return self.mic end
    function d:setTurnedOnRaw(b) self.on = b end
    function d:getIsTurnedOn() return self.on end
    function d:setChannelRaw(k) self.channel = k end
    function d:setChannel(k) self.channel = k end
    function d:getChannel() return self.channel end
    function d:getMinChannelRange() return self.min end
    function d:getMaxChannelRange() return self.max end
    function d:setIsBatteryPowered(b) self.batteryPowered = b end
    function d:getIsBatteryPowered() return self.batteryPowered end
    function d:setHasBattery(b) self.hasBattery = b end
    function d:getHasBattery() return self.hasBattery end
    function d:setPower(p) self.power = p end
    function d:getPower() return self.power end
    function d:getIsPortable() return self.portable end
    function d:getIsTelevision() return false end
    function d:isNoTransmit() return false end
    function d:setMicIsMuted(b) self.muted = b end
    function d:getMicIsMuted() return self.muted end
    function d:getIsHighTier() return false end
    function d:getDeviceName() return "Radio" end
    return d
end
-- IsoRadio(cell, square, sprite): no sprite = new DeviceData (IsoWaveSignal.init); added by transmitAddObjectToSquare.
IsoRadio = { new = function(cell, sq, sprite)
    local r = { classes = classes("IsoRadio", "IsoWaveSignal", "IsoObject"), device = newDevice() }
    function r:getDeviceData() return self.device end
    function r:getSquare() return self.square end
    function r:getObjectIndex()
        if self.square == nil then return -1 end
        for i, o in ipairs(self.square.objects.items) do if o == self then return i - 1 end end
        return -1
    end
    return r
end }

ITEM_ID = 500
function newItem(fullType)
    ITEM_ID = ITEM_ID + 1
    local it = { id = ITEM_ID, fullType = fullType, classes = classes("InventoryItem") }
    function it:getID() return self.id end
    function it:getFullType() return self.fullType end
    function it:getContainer() return self.container end
    if string.find(fullType, "WalkieTalkie", 1, true) then
        it.classes.Radio = true
        it.device = newDevice()
        it.device.twoWay, it.device.portable = true, true
        function it:getDeviceData() return self.device end
    end
    return it
end
function newInventory()
    local inv = { items = {} }
    function inv:AddItem(x)
        local it = type(x) == "string" and newItem(x) or x
        self.items[#self.items + 1] = it
        it.container = self
        return it
    end
    function inv:Remove(it)
        for i, x in ipairs(self.items) do if x == it then table.remove(self.items, i); it.container = nil; return end end
    end
    function inv:getItemWithID(id) for _, x in ipairs(self.items) do if x.id == id then return x end end end
    function inv:getItemWithIDRecursiv(id) return self:getItemWithID(id) end
    function inv:getItems() return JList(self.items) end
    return inv
end
sendAddItemToContainer = function() end
sendRemoveItemFromContainer = function() end

PLAYERS, ONLINE = {}, {}
function makePlayer(name, x, y, z)
    local p = { classes = classes("IsoPlayer", "IsoGameCharacter"), username = name, x = x or 1000.5, y = y or 1000.5,
        z = z or 0, md = {}, inv = newInventory() }
    function p:getUsername() return self.username end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:getSquare() return CELL:getGridSquare(self.x, self.y, self.z) end
    p.getCurrentSquare = p.getSquare
    function p:getPrimaryHandItem() return self.primary end
    function p:setPrimaryHandItem(it) self.primary = it end
    function p:getSecondaryHandItem() return nil end
    function p:getClothingItem_Back() return nil end
    function p:isEquipped(it) return self.primary == it end
    function p:removeFromHands(it) if self.primary == it then self.primary = nil end end
    function p:removeWornItem() end
    function p:removeAttachedItem() end
    function p:isAttachedItem() return false end
    function p:getInventory() return self.inv end
    function p:getModData() return self.md end
    function p:getPlayerNum() return 0 end
    function p:isDead() return false end
    function p:getVehicle() return self.vehicle end
    PLAYERS[name] = p
    return p
end
function login(name) ONLINE[#ONLINE + 1] = name end
getOnlinePlayers = function()
    local list = {}
    for i, n in ipairs(ONLINE) do list[i] = PLAYERS[n] end
    return JList(list)
end

-- Vehicles: seats 0..3; BaseVehicle.enter/exit; on a client the VehicleEnter/VehicleExit packets go to the server.
VEHICLES, VEHICLE_SEQ = {}, 0
IsoDirections = { E = "E" }
function newVehicle(id)
    local v = { id = id, seats = {}, parts = { Radio = { id = "Radio" } } }
    function v:getId() return self.id end
    function v:getSqlId() return self.id end
    function v:getSeat(chr) for s = 0, 3 do if self.seats[s] == chr then return s end end return -1 end
    function v:getPartById(name) return self.parts[name] end
    function v:enter(seat, chr)
        if self.seats[seat] ~= nil then return false end
        if chr.vehicle ~= nil then chr.vehicle:exit(chr) end
        self.seats[seat], chr.vehicle = chr, self
        if isClient() then PY_PACKET("vehicle_enter", { id = self.id, seat = seat }) end
        return true
    end
    function v:exit(chr)
        local s = self:getSeat(chr)
        if s < 0 then return false end
        self.seats[s], chr.vehicle = nil, nil
        if isClient() then PY_PACKET("vehicle_exit", { id = self.id }) end
        return true
    end
    function v:permanentlyRemove() VEHICLES[self.id] = nil end
    v.parts.Radio.getDeviceData = function(self) return self.device end
    -- Spawned with its parts: the radio part already holds a car radio (Base.RadioBlack, not two way), as a
    -- CarNormal of the game does (VehicleUtils.createPartInventoryItem_Radio at creation).
    v.parts.Radio.item = instanceItem("Base.RadioBlack")
    v.parts.Radio.getInventoryItem = function(self) return self.item end
    v.parts.Radio.setInventoryItem = function(self, item) self.item = item end
    return v
end
addVehicleDebug = function(script, dir, skin, sq)
    VEHICLE_SEQ = VEHICLE_SEQ + 1
    local v = newVehicle(VEHICLE_SEQ)
    v.square = sq
    VEHICLES[v.id] = v
    if isServer() then PY_BCAST("vehicle_add", { id = v.id }) end
    return v
end
getVehicleById = function(id) return VEHICLES[id] end
-- instanceItem: the radio items of these suites only; nil for any other type, as the game for an unknown type.
RADIO_ITEMS = { ["Base.HamRadio1"] = true, ["Base.RadioBlack"] = false }
instanceItem = function(fullType)
    local twoWay = RADIO_ITEMS[fullType]
    if twoWay == nil then return nil end
    local item = { fullType = fullType, device = newDevice() }
    item.device.twoWay = twoWay
    function item:getDeviceData() return self.device end
    function item:getFullType() return self.fullType end
    return item
end
Vehicles = { Create = { Radio_HAM = function(v, part)
    -- Vanilla (server/Vehicles/Vehicles.lua): copies the device data of the part's item, created from the part's
    -- itemType only when the part has none (createPartInventoryItem_HAMRadio): a car radio already there stays a car
    -- radio. Powered by the car (DeviceData.canBePoweredHere: VehiclePart.hasDevicePower), flat battery here.
    if part.item == nil then part.item = instanceItem("Base.RadioBlack") end
    part.device = newDevice(); part.device.twoWay = part.item.device.twoWay; part.device.batteryPowered = false
    part.device.carPowered = true
end } }

function CLIENT_PACKET(kind, a)
    if kind == "vehicle_add" then VEHICLES[a.id] = newVehicle(a.id)
    elseif kind == "faction_sync" then
        local f = Faction.getFaction(a.name) or FACTION_CREATE(a.name, a.owner)
        if f then f:setName(a.title or a.name) end
    elseif kind == "faction_title" then
        local f = Faction.getFaction(a.name)
        if f then f:setName(a.title) end
    elseif kind == "faction_disband" then
        local f = Faction.getFaction(a.name)
        if f then Faction.factions:remove(f) end
    end
end
function SERVER_PACKET(kind, user, a)
    local p = PLAYERS[user]
    if kind == "vehicle_enter" then
        local v = VEHICLES[a.id]
        if v then v.seats[a.seat], p.vehicle = p, v end
    elseif kind == "vehicle_exit" then
        local v = VEHICLES[a.id]
        if v then local s = v:getSeat(p); if s >= 0 then v.seats[s] = nil end end
        p.vehicle = nil
    elseif kind == "faction_create" then
        if FACTION_OPTION ~= false and FACTION_CREATE(a.name, user) then
            PY_BCAST("faction_sync", { name = a.name, owner = user })
        end
    elseif kind == "faction_rename" then
        local f = Faction.getFaction(a.name)
        if f and f:isOwner(user) then FACTION_RENAME(f, a.title); PY_BCAST("faction_title", { name = a.name, title = a.title }) end
    elseif kind == "faction_disband" then
        local f = Faction.getFaction(a.name)
        if f and f:isOwner(user) then FACTION_DISBAND(f); PY_BCAST("faction_disband", { name = a.name }) end
    end
end
'''

FACTION_EXTRA = r'''
function Faction.getFaction(name)
    for _, f in ipairs(Faction.factions.items) do if f:getName() == name then return f end end
end
local byName = Faction.getPlayerFaction
-- Faction.getPlayerFaction(IsoPlayer) and (String) overloads (Faction.java:109-135).
Faction.getPlayerFaction = function(x)
    if type(x) == "table" then x = x:getUsername() end
    return byName(x)
end
sendFactionCreate = function(name, user) PY_PACKET("faction_create", { name = name }) end
sendFactionChangeTitle = function(f, title) PY_PACKET("faction_rename", { name = f:getName(), title = title }) end
sendFactionDisband = function(f) PY_PACKET("faction_disband", { name = f:getName() }) end
'''

# ------------------------------------------------------------------------------------------------ mod doubles

AUTHORITY = r'''
DEFECT = DEFECT or {}
Const = require "RadioSurvivor/RadioSurvivor_Const"
C = require "RadioSurvivor/RS_Config"
S = require "RadioSurvivor/RS_State"
assert(S.init(true))
WALT = 130000
package.loaded["RadioSurvivor/RS_Personas"] = {
    voiceAt = function(k) if k == WALT then return "walt" end end,
    channel = function(k) if k == WALT then return { walt = true } end end }
RS_RadioServer = { bench = true }

-- Living Knox reduced to its test API, groups, hostility fact and bodies (public API of docs/api.md).
require "LivingKnox/LK_Core"
local LK = LivingKnox
BODIES, LKNPCS, GROUPS, BLIND = {}, {}, {}, {}
local npcSeq, groupSeq = 0, 0
DAY = 5
local function body(id, x, y, z)
    local b = { classes = CLASSES("IsoZombie", "IsoGameCharacter", "IsoMovingObject"), id = id, x = x + 0.5,
        y = y + 0.5, z = z, md = { lk = id } }
    function b:getX() return self.x end
    function b:getY() return self.y end
    function b:getZ() return self.z end
    function b:isDead() return self.dead == true end
    function b:getSquare() return CELL:getGridSquare(self.x, self.y, self.z) end
    function b:CanSee(o) return not BLIND[math.floor(self.x) .. "," .. math.floor(self.y)] end
    function b:getModData() return self.md end
    function b:hasModData() return true end
    function b:Kill(killer)
        self.dead = true
        BODIES[self.id] = nil
        LKNPCS[self.id].state = "dead"
        local gid, mid = LK.Groups.findNpc(self.id)
        if gid then
            GROUPS[gid].members[mid].alive = false
            LK.publish("memberDied", { group = gid, member = mid, npc = self.id, day = DAY, offscreen = false, body = self })
            if DEFECT.doubleDeath then
                local g = GROUPS[gid]
                LK.publish("memberDied", { group = gid, member = mid, npc = self.id, day = DAY, offscreen = true,
                    witnesses = LK.Groups.present(g, mid), x = g.home.x, y = g.home.y })
            end
        end
    end
    return b
end
LK.API = {
    testSpawnNpc = function(x, y, z)
        if CELL:getGridSquare(x, y, z) == nil then return nil, "square not loaded" end
        npcSeq = npcSeq + 1
        local id = "lk-" .. npcSeq
        LKNPCS[id] = { state = "alive" }
        BODIES[id] = body(id, x, y, z)
        return id
    end,
    testRemoveNpc = function(id) BODIES[id] = nil; LKNPCS[id] = nil; return true end,
}
LK.Store = { data = function() return { npcs = LKNPCS } end }
-- Bodies.despawn(id, forget) (LK_Bodies.lua:450): false and a reason for an unknown npc.
LK.Bodies = { find = function(id) return BODIES[id] end,
    despawn = function(id, forget)
        if not LKNPCS[id] then return false, "unknown npc " .. tostring(id) end
        BODIES[id] = nil
        if forget then LKNPCS[id] = nil end
        return true, 1
    end }
LK.Identity = { readTag = function(md) return md.lk end }
LK.Health = { setBirth = function() end }
LK.Homes = { skip = function() end }
LK.Senses = { perceived = function(id) return { p = {} } end }
LK.Groups = {
    ensure = function() return true end,
    today = function() return DAY end,
    create = function(spec)
        groupSeq = groupSeq + 1
        local g = { id = "grp-" .. groupSeq, members = {}, n = 0, home = spec.home }
        GROUPS[g.id] = g
        return { id = g.id }
    end,
    addMember = function(gid, spec)
        local g = GROUPS[gid]
        g.n = g.n + 1
        local mid = "m-" .. g.n
        g.members[mid] = { npc = spec.npc, alive = true }
        -- MATERIALIZE: a member without body is embodied at once as a real npc (not a test npc), as Living Knox
        -- does while a player is near its home (LK_Groups member "materialized as npc").
        if MATERIALIZE and spec.npc == nil then
            npcSeq = npcSeq + 1
            local id = "lk-" .. npcSeq
            LKNPCS[id] = { state = "alive" }
            BODIES[id] = body(id, g.home.x, g.home.y + 3, g.home.z)
            g.members[mid].npc = id
        end
        return mid
    end,
    get = function(gid) return GROUPS[gid] end,
    findNpc = function(npc)
        for gid, g in pairs(GROUPS) do
            for mid, m in pairs(g.members) do if m.npc == npc then return gid, mid end end
        end
    end,
    present = function(g, mid)
        local out = {}
        for k, m in pairs(g.members) do if k ~= mid and m.alive and m.npc then out[#out + 1] = m.npc end end
        table.sort(out)
        return out
    end,
    markDead = function(gid, mid, day)
        local g = GROUPS[gid]
        local m = g and g.members[mid]
        if not m then return nil, "unknown member" end
        m.alive = false
        LK.publish("memberDied", { group = gid, member = mid, npc = m.npc, day = day, offscreen = true,
            witnesses = LK.Groups.present(g, mid), x = g.home.x, y = g.home.y })
        return true
    end,
    remove = function(gid) GROUPS[gid] = nil end,
}
LK.Hostility = { record = function(gid, key, fact, opts)
    if not GROUPS[gid] then return nil, "unknown group" end
    if opts.witnessed then
        local w = {}
        for _, x in ipairs(opts.witnesses or {}) do w[#w + 1] = x end
        if DEFECT.allWitness then w = LK.Groups.present(GROUPS[gid], nil) end
        LK.publish("assaultSeen", { group = gid, player = key, fact = fact, day = DAY, witnesses = w, x = opts.x,
            y = opts.y })
    end
    return { level = 0 }
end }

-- Notebook provider (RS_NPCProvider interface) over the bodies above.
local function dist(a, b)
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end
P = {
    active = function() return { name = "livingknox" } end,
    available = function() return true end,
    objects = function() local out = {} for id, b in pairs(BODIES) do out[id] = b end return out end,
    id = function(b) return b.id end,
    npc = function(id)
        if not LKNPCS[id] then return nil end
        local gid = LK.Groups.findNpc(id)
        return { signature = "lk|" .. id, name = "Npc " .. id, group = gid or "" }
    end,
    hears = function(source, listener, range) return source ~= nil and listener ~= nil and dist(source, listener) <= range end,
    near = function(a, b, range) return a ~= nil and b ~= nil and dist(a, b) <= range end,
    presence = function() return nil end,
}
package.loaded["RadioSurvivor/RS_NPCProvider"] = P

-- RS_Missions reduced to create / accept / finish and its optional listener (RS_Missions.lua:87-160).
M = { onFinished = nil }
function M.create(state, npc, cid)
    if npc.mission then return state.missions[npc.mission] end
    local m = { id = npc.id .. "-d1", npc = npc.id, state = "offer", participants = {}, invited = { [cid] = true } }
    state.missions[m.id], npc.mission = m, m.id
    return m
end
function M.accept(state, m, cid, name)
    if not m.invited[cid] then return false end
    m.state = "active"
    m.participants[cid] = { name = name }
    return true
end
function M.finish(state, m, result)
    if m.state ~= "active" then return false end
    m.state = result
    if M.onFinished then M.onFinished(state, m, result) end
    return true
end
package.loaded["RadioSurvivor/RS_Missions"] = M

-- Notebook server reduced to what the suites read (RS_Carnet_Server.lua: hello, snapshot, select, mandate, scan,
-- prune, conditional save, enrichment of a contacted fiche).
F = require "RadioSurvivor/RS_Factions"
local MANDATE_ERRORS = { not_owner = "MandateOwner", not_member = "MandateMember", full = "MandateFull" }
Server = { store = S, bound = {}, selected = {}, objects = {}, pending = {}, enrichTimes = {}, times = {} }
RS_CarnetServer = Server
local function players()
    if isServer() then local out = {} for i, n in ipairs(ONLINE) do out[i] = PLAYERS[n] end return out end
    return { getPlayer() }
end
local function send(player, command, args)
    args = args or {}
    args.world, args.run = S.data.world, S.run
    if isServer() then sendServerCommand(player, C.MODULE, command, args)
    elseif RS_CarnetClient then RS_CarnetClient.receive(command, args) end
end
local function publish() for _, p in ipairs(players()) do send(p, "snapshot", {}) end end
function Server.find(id) for _, npc in pairs(S.data.npcs) do if npc.incarnation == id then return npc end end end
function Server.ensure(id)
    if not P.npc(id) then return nil end
    local npc = Server.find(id)
    if not npc then
        npc = { id = S.uid("npc"), incarnation = id, alive = true, seenAt = getTimestampMs(), enrichState = "idle" }
        S.data.npcs[npc.id] = npc
        S.dirty = true
    end
    return npc
end
local function scan()
    local objects = {}
    for id, b in pairs(P.objects()) do
        local npc = Server.find(id)
        if npc == nil and DEFECT.ensureOnScan then npc = Server.ensure(id) end
        if npc and npc.alive then
            objects[npc.id] = b
            if getTimestampMs() - (npc.seenAt or 0) > 60000 then npc.seenAt, S.dirty = getTimestampMs(), true end
        end
    end
    Server.objects = objects
end
function Server.command(module, command, player, args)
    if module ~= C.MODULE or not player then return end
    args = args or {}
    if command == "hello" then
        local cid = "character-" .. player:getUsername()
        S.data.characters[cid] = S.data.characters[cid] or { id = cid, contacts = {}, knownMissions = {} }
        Server.bound[player] = cid
        send(player, "identity", { character = cid })
        scan()
        send(player, "snapshot", {})
        return
    end
    local cid = Server.bound[player]
    if not cid then return send(player, "error", { reason = "Identity" }) end
    scan()
    if command == "snapshot" then send(player, "snapshot", {})
    elseif command == "select" then
        local npc = Server.ensure(args.incarnation)
        if npc and Server.objects[npc.id] then
            local record = S.data.characters[cid]
            record.contacts[npc.id] = record.contacts[npc.id] or { history = {}, note = "" }
            if npc.enrichState == "idle" then npc.enrichState = "needed" end
            Server.selected[cid] = npc.id
            S.save()
            send(player, "snapshot", {})
        else send(player, "error", { reason = "Range" }) end
    elseif command == "mandate" then
        local ok, reason = F.designate(player, args.member, args.action == "grant")
        if not ok then return send(player, "error", { reason = MANDATE_ERRORS[reason] or "State" }) end
        S.save()
        publish()
    end
end
Events.OnClientCommand.Add(Server.command)
local function prune(now)
    local kept = {}
    if not DEFECT.pruneContacts then
        for _, record in pairs(S.data.characters) do for id in pairs(record.contacts) do kept[id] = true end end
    end
    for _, r in ipairs(Server.pending) do kept[r.npc] = true end
    for id, npc in pairs(S.data.npcs) do
        if not kept[id] and not Server.objects[id] and (not npc.alive or now - (npc.seenAt or 0) > C.NPC_UNSEEN_MS) then
            S.data.npcs[id] = nil
            S.dirty = true
        end
    end
end
Triggers = require "RadioSurvivor/RS_ObservationTriggers"
Triggers.attach(Server)
local checkAt, pruneAt, saveAt = 0, getTimestampMs() + C.PRUNE_INTERVAL_MS, getTimestampMs() + C.SAVE_INTERVAL_MS
Events.OnTickEvenPaused.Add(function()
    local now = getTimestampMs()
    for _, v in pairs(VEHICLES) do
        local d = v.parts.Radio.device
        if d and d.on and d.carPowered and not d.batteryPowered then d.on = false end
    end
    if now >= checkAt then
        scan()
        Triggers.link()
        Triggers.returns(Server)
        if DEFECT.pushEverySecond then publish() end
        -- Other modules broadcast (3-argument overload) and save after a real change while the notebook is idle.
        sendServerCommand("RSTBenchOther", "tick", {})
        if DEFECT.seenEverySecond then
            S.data.benchSeenAt = now
            S.save()
        end
        for _, npc in pairs(S.data.npcs) do
            if npc.enrichState == "needed" then
                npc.enrichState = "pending"
                Server.pending[#Server.pending + 1] = { npc = npc.id, kind = "npc_enrich" }
                Server.enrichTimes[#Server.enrichTimes + 1] = now
            end
        end
        checkAt = now + 1000
    end
    if now >= pruneAt then prune(now); pruneAt = now + C.PRUNE_INTERVAL_MS end
    if now >= saveAt then
        if S.dirty or DEFECT.saveAlways then S.save() end
        saveAt = now + C.SAVE_INTERVAL_MS
    end
end)

-- Judge of the radio command talk: order of RadioSurvivor_Server.findRadio (radio, microphone range, on, seat), then
-- the silence path of a frequency without voice (RS_RadioLog.spoken, accepted, done) and the history command.
Log = require "RadioSurvivor/RS_RadioLog"
local function carried(player, itemId)
    local list = { player:getPrimaryHandItem(), player:getSecondaryHandItem(), player:getClothingItem_Back() }
    for i = 1, 3 do
        local it = list[i]
        if it ~= nil and instanceof(it, "Radio") and (itemId == nil or it:getID() == itemId)
                and it:getDeviceData():getIsTwoWay() then return it end
    end
end
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Const.MODULE then return end
    args = args or {}
    if command == "history" then return Log.sendAll(player) end
    if command ~= "talk" then return end
    local function reject(reason) Const.toClient(player, "rejected", { reason = reason }) end
    local text = Const.oneLine(args.text)
    local data, khz
    if args.source == nil or args.source == "item" then
        local radio = carried(player, tonumber(args.itemId))
        if radio == nil and not DEFECT.anyRadio then return reject("NoRadio") end
        khz = tonumber(args.channel)
    elseif args.source == "world" then
        local sq = getCell():getGridSquare(args.x, args.y, args.z)
        local obj = sq and sq:getObjects():get(args.index)
        data = obj and instanceof(obj, "IsoWaveSignal") and obj:getDeviceData()
        if not data or not data:getIsTwoWay() then return reject("NoRadio") end
        if not DEFECT.noRange and not Const.inMicRange(player, data, sq:getX(), sq:getY(), sq:getZ()) then
            return reject("TooFar")
        end
        if not data:getIsTurnedOn() then return reject("Off") end
        khz = data:getChannel()
    elseif args.source == "vehicle" then
        local v = player:getVehicle()
        if DEFECT.noSeat then v = getVehicleById(args.vehicleId)
        elseif not Const.inVehicle(player, v) or v:getId() ~= args.vehicleId then return reject("NotInVehicle") end
        local part = v:getPartById(args.part)
        data = part and part:getDeviceData()
        if not data or not data:getIsTwoWay() then return reject("NoRadio") end
        if not data:getIsTurnedOn() then return reject("Off") end
        khz = data:getChannel()
    else return reject("NoRadio") end
    Log.spoken(player, khz, text)
    if DEFECT.historyToAll then
        local cid = Server.bound[player]
        for _, other in ipairs(players()) do
            if other ~= player then Const.toClient(other, "history_add", { character = cid, khz = khz, last = 1,
                line = { kind = "said", text = text, when = "", seq = 99 } }) end
        end
    end
    Const.toClient(player, "accepted", { text = text })
    Const.toClient(player, "done", {})
end)
'''

CLIENT_SIDE = r'''
Const = Const or require "RadioSurvivor/RadioSurvivor_Const"
History = require "RadioSurvivor/RS_RadioHistory"
Const.clientHandler = function(command, args) History.receive(command, args) end
RS_CarnetClient = { snapshots = 0 }
local CC = RS_CarnetClient
function CC.send(command, args)
    args = args or {}
    args.world, args.run = CC.world, CC.run
    sendClientCommand(getPlayer(), "RS_Carnet", command, args)
end
function CC.receive(command, args)
    if command == "identity" then CC.world, CC.run, CC.character = args.world, args.run, args.character
    elseif command == "error" then CC.lastError = args.reason
    elseif command == "snapshot" then CC.snapshots = CC.snapshots + 1 end
end
if isClient() then
    Events.OnServerCommand.Add(function(m, c, a)
        if m == Const.MODULE then Const.clientHandler(c, a or {}) end
        if m == "RS_Carnet" then CC.receive(c, a or {}) end
    end)
end
-- Closed notebook: one pull every SNAPSHOT_CLOSED_MS (RS_Client.lua OnTick), hello first.
local nextSync = 0
Events.OnTick.Add(function()
    if getTimestampMs() >= nextSync then
        if CC.world then CC.send("snapshot") else CC.send("hello") end
        nextSync = getTimestampMs() + 30000
    end
end)
'''


def to_py(value):
    if lupa.lua_type(value) == 'table':
        out = {}
        for k, v in value.items():
            if isinstance(k, (str, int, float)) and not isinstance(k, bool):
                conv = to_py(v)
                if conv is not None:
                    out[k] = conv
        return out
    if isinstance(value, (str, int, float, bool)):
        return value
    return None


class Machine:
    def __init__(self, net, name, role):
        self.net, self.name, self.role = net, name, role
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.g = self.rt.globals()
        g.next = None  # absent de Kahlua
        self.root = net.root / name
        self.root.mkdir(parents=True, exist_ok=True)
        g.ROLE = role
        g.FILE_ROOT = self.root.as_posix()
        g.mkdirs = lambda full: Path(full).parent.mkdir(parents=True, exist_ok=True)
        sides = ['shared'] + (['client'] if role != 'server' else []) + (['server'] if role != 'client' else [])
        paths = [DEV / 'shared'] + [MOD / s for s in sides]
        self.rt.execute('package.path = [[' + ''.join(f'{p.as_posix()}/?.lua;' for p in paths) + ']] .. package.path')
        self.rt.execute(JAVA)
        self.rt.execute(FACTION_DOUBLE)
        self.rt.execute(FACTION_EXTRA)
        g.PY_SEND = lambda kind, *a: net.send(name, kind, *a)
        self.rt.execute('''
            -- Both Java overloads (GlobalObject.sendServerCommand): (module, command, args) to every client,
            -- (player, module, command, args) to one; the broadcast form given a 4th argument (even nil) has no
            -- implementation and throws, as in the game.
            sendServerCommand = function(...)
                local n, a, b, c, d = select("#", ...), ...
                if type(a) == "string" then
                    if n ~= 3 then error("No implementation found for function: sendServerCommand") end
                    if isServer() then
                        for _, user in ipairs(ONLINE) do PY_SEND("s2c", user, a, b, c) end
                    end
                    return
                end
                if isServer() then PY_SEND("s2c", a:getUsername(), b, c, d) end
            end
            sendClientCommand = function(player, module, command, args)
                PY_SEND(isClient() and "c2s" or "solo", module, command, args)
            end
            PY_PACKET = function(kind, args) PY_SEND("pkt", kind, args) end
            PY_BCAST = function(kind, args) PY_SEND("bcast", kind, args) end
            getSpecificPlayer = function() return LOCAL_PLAYER end
            getPlayer = function() return LOCAL_PLAYER end
        ''')

    def lua(self, code):
        return self.rt.execute(code)

    def table(self, data):
        if isinstance(data, dict):
            return self.rt.table_from({k: self.table(v) for k, v in data.items()})
        return data

    def load(self, path: Path):
        self.rt.execute(f'dofile([[{path.as_posix()}]])')


class Net:
    """Serveur dédié et clients (ou solo) ; commandes et paquets en file, livrés au tick suivant."""

    def __init__(self, root: Path, users=('rs_mp1', 'rs_mp2'), solo=False, defects=(), positions=None):
        self.root, self.queue, self.solo = root, [], solo
        positions = positions or {}
        self.server = Machine(self, 'solo' if solo else 'server', 'solo' if solo else 'server')
        self.clients = {}
        defect = '{' + ', '.join(f'{d} = true' for d in defects) + '}'
        self.server.lua(f'DEFECT = {defect}')
        if solo:
            x, y = positions.get('player', (1000.5, 1000.5))
            self.server.lua(f'LOCAL_PLAYER = makePlayer("player", {x}, {y}, 0)')
        else:
            for u in users:
                x, y = positions.get(u, (1000.5, 1000.5))
                self.server.lua(f'makePlayer("{u}", {x}, {y}, 0); login("{u}")')
                c = Machine(self, u, 'client')
                c.lua(f'LOCAL_PLAYER = makePlayer("{u}", {x}, {y}, 0)')
                self.clients[u] = c
        self.server.lua(AUTHORITY)
        for m in self.machines():
            if m.role != 'server':
                m.lua(CLIENT_SIDE)
            m.lua('require "RST/RST"')
            for f in STEPS_FILES:
                m.load(f)
            for f in SUITE_FILES.values():
                m.load(f)
        for _ in range(3):
            self.tick()

    def machines(self):
        return [self.server, *self.clients.values()]

    def send(self, sender, kind, *a):
        self.queue.append((sender, kind, [to_py(x) if lupa.lua_type(x) == 'table' else x for x in a]))

    def pump(self):
        while self.queue:
            sender, kind, a = self.queue.pop(0)
            s = self.server
            if kind == 'c2s':
                module, command, args = a
                s.g.fire('OnClientCommand', module, command, s.g.PLAYERS[sender], s.table(args or {}))
            elif kind == 'solo':
                module, command, args = a
                s.g.fire('OnClientCommand', module, command, s.g.LOCAL_PLAYER, s.table(args or {}))
            elif kind == 's2c':
                user, module, command, args = a
                if user in self.clients:
                    c = self.clients[user]
                    c.g.fire('OnServerCommand', module, command, c.table(args or {}))
            elif kind == 'pkt':
                packet, args = a
                if self.solo:
                    continue
                s.g.SERVER_PACKET(packet, sender, s.table(args or {}))
            elif kind == 'bcast':
                packet, args = a
                for c in self.clients.values():
                    c.g.CLIENT_PACKET(packet, c.table(args or {}))

    def tick(self, dt=100):
        self.pump()
        for m in self.machines():
            m.g.CLOCK = m.g.CLOCK + dt
        self.server.g.fire('OnTickEvenPaused')
        self.server.g.fire('OnTick')
        for c in self.clients.values():
            c.g.fire('OnTick')
        self.pump()

    def run(self, suite, requester='rs_mp1', limit=6000, dt=100):
        s = self.server
        player = 'LOCAL_PLAYER' if self.solo else f'PLAYERS["{requester}"]'
        side = 'solo' if self.solo else 'server'
        s.lua(f'REPORT = nil; assert(RST.start({{ suite = "{suite}", tags = {{ "server", "world" }} }}, '
              f'{{ ctx = {{ side = "{side}", player = {player} }}, onDone = function(r) REPORT = r end }}))')
        for _ in range(limit):
            if not s.lua('return RST.running()'):
                return Report(s.g.REPORT)
            self.tick(dt)
        raise AssertionError('run not over: ' + suite)


class Report:
    def __init__(self, rep):
        self.rep = rep
        self.results = {r.test: (r.status, r.message) for _, r in rep.results.items()}
        self.notes = {r.test: [n for _, n in (r.notes or {}).items()] for _, r in rep.results.items()}

    def status(self, test_part):
        hits = [v for k, v in self.results.items() if test_part in k]
        assert len(hits) == 1, (test_part, self.results)
        return hits[0]


class Bench(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-mp-suites-')
        self.root = Path(self.tmp.name)
        self.count = 0

    def tearDown(self):
        self.tmp.cleanup()

    def net(self, **kw):
        self.count += 1
        return Net(self.root / f'run{self.count}', **kw)

    def assert_status(self, report, test_part, status, message=None):
        got = report.status(test_part)
        self.assertEqual(got[0], status, f'{test_part}: {got}')
        if message is not None:
            self.assertIn(message, got[1] or '')


# ------------------------------------------------------------------------------------------------ E06-T03

class WorldRadioTests(Bench):
    """rs.worldradio : radio posée (portée du micro, allumage) et autoradio (siège) jugées par l'autorité."""

    def test_mp_two_clients_pass(self):
        net = self.net(positions={'rs_mp2': (1020.5, 1000.5)})
        rep = net.run('rs.worldradio')
        self.assertEqual({k: v[0] for k, v in rep.results.items()}, {
            'placed radio: accepted in microphone range, refused out of range or off (E06-T03)': 'PASS',
            'car radio: a seated passenger transmits, a player outside is refused (E06-T03)': 'PASS'})
        notes = ' '.join(rep.notes['placed radio: accepted in microphone range, refused out of range or off (E06-T03)'])
        self.assertIn('client rs_mp2 at', notes)
        # The requester left the car, the car is gone, the radios are removed, the test lines too.
        self.assertIsNone(net.server.g.PLAYERS['rs_mp1'].vehicle)
        self.assertEqual(net.server.lua('local n = 0 for _ in pairs(VEHICLES) do n = n + 1 end return n'), 0)
        self.assertEqual(net.server.lua('return CELL:getGridSquare(1001, 1000, 0):getObjects():size()'), 0)
        self.assertFalse(net.server.lua('for _, r in pairs(S.data.characters) do for _, f in ipairs(r.radio and '
                                        'r.radio.frequencies or {}) do if #f.lines > 0 then return true end end end '
                                        'return false'))

    def test_second_client_in_range_is_accepted_as_the_rule_says(self):
        net = self.net(positions={'rs_mp2': (1000.5, 1001.5)})
        rep = net.run('rs.worldradio')
        self.assert_status(rep, 'placed radio', 'PASS')
        self.assertIn('client rs_mp2 at 1 square(s): accepted', ' '.join(rep.notes[next(k for k in rep.notes
                                                                                        if 'placed' in k)]))

    def test_solo_pass(self):
        rep = self.net(solo=True).run('rs.worldradio')
        self.assertEqual({v[0] for v in rep.results.values()}, {'PASS'})

    def test_detects_a_range_not_checked(self):
        rep = self.net(defects=('noRange',)).run('rs.worldradio')
        self.assert_status(rep, 'placed radio', 'FAIL', 'far radio: requester')

    def test_detects_a_seat_not_checked(self):
        rep = self.net(defects=('noSeat',), positions={'rs_mp2': (1030.5, 1000.5)}).run('rs.worldradio')
        self.assert_status(rep, 'car radio', 'FAIL', 'client rs_mp2 outside the car')


# ------------------------------------------------------------------------------------------------ E06-T05

class RadioTabTests(Bench):
    """rs.radio : refus sans radio, onglet Radio de chaque client limité à son personnage."""

    def test_mp_two_clients_pass(self):
        net = self.net()
        rep = net.run('rs.radio')
        self.assert_status(rep, 'NoRadio', 'PASS')
        self.assert_status(rep, 'two players', 'PASS')
        self.assert_status(rep, 'reconnection', 'SKIP')
        # Walkie-talkies taken back, test lines removed from the private histories.
        self.assertEqual(net.server.lua('return #PLAYERS["rs_mp2"].inv.items'), 0)
        self.assertIsNone(net.server.g.PLAYERS['rs_mp2'].primary)

    def test_solo_pass(self):
        rep = self.net(solo=True).run('rs.radio')
        self.assert_status(rep, 'NoRadio', 'PASS')
        self.assert_status(rep, 'two players', 'PASS')

    def test_detects_a_sentence_accepted_without_radio(self):
        rep = self.net(defects=('anyRadio',)).run('rs.radio')
        self.assert_status(rep, 'NoRadio', 'FAIL', 'rejected NoRadio')

    def test_detects_a_history_sent_to_another_player(self):
        rep = self.net(defects=('historyToAll',)).run('rs.radio')
        self.assert_status(rep, 'two players', 'FAIL', 'history commands of another character received')


# ------------------------------------------------------------------------------------------------ E00-T04

class CarnetLoadTests(Bench):
    """rs.carnet.load : aucune fiche sans contact, aucun envoi ni sauvegarde à vide, fiche contactée gardée."""

    def test_mp_two_clients_pass(self):
        net = self.net()
        rep = net.run('rs.carnet.load')
        self.assertEqual({k: v[0] for k, v in rep.results.items()}, {
            'loaded npcs without contact get no fiche and no LLM request (E00-T04)': 'PASS',
            'an idle server pushes no snapshot and saves only after a change (E00-T04)': 'PASS',
            'a contacted fiche is never pruned, an uncontacted one is (E00-T04)': 'PASS'})
        self.assertEqual(net.server.lua('local n = 0 for _ in pairs(BODIES) do n = n + 1 end return n'), 0)

    def test_solo_pass(self):
        rep = self.net(solo=True).run('rs.carnet.load')
        self.assertEqual({v[0] for v in rep.results.values()}, {'PASS'})

    def test_detects_fiches_created_by_the_scan(self):
        rep = self.net(defects=('ensureOnScan',)).run('rs.carnet.load')
        self.assert_status(rep, 'no fiche and no LLM', 'FAIL', 'without contact')

    def test_detects_a_periodic_broadcast(self):
        rep = self.net(defects=('pushEverySecond',)).run('rs.carnet.load')
        self.assert_status(rep, 'idle server', 'FAIL', 'snapshot(s) pushed to')

    def test_detects_a_periodic_save(self):
        rep = self.net(defects=('saveAlways',), users=('rs_mp1',)).run('rs.carnet.load')
        self.assert_status(rep, 'idle server', 'FAIL', 'saves of an unchanged state')

    def test_save_after_a_real_change_is_not_an_idle_save(self):
        # A module that saves after a real change (fiche seen again) during the window: not a save of an unchanged
        # state (MP campaign of 2026-10-15: 1 save counted, the 3-argument broadcast threw in the suite's wrapper).
        rep = self.net(defects=('seenEverySecond',)).run('rs.carnet.load')
        self.assert_status(rep, 'idle server', 'PASS')

    def test_detects_a_contacted_fiche_pruned(self):
        rep = self.net(defects=('pruneContacts',)).run('rs.carnet.load')
        self.assert_status(rep, 'contacted fiche', 'FAIL', 'pruned')


# ------------------------------------------------------------------------------------------------ E08-T07

class ObservationTests(Bench):
    """rs.observations : un fait par témoin admissible, jamais chez un PNJ qui n'a rien pu voir, aucune fiche créée."""

    def test_mp_pass(self):
        rep = self.net().run('rs.observations')
        self.assertEqual({v[0] for v in rep.results.values()}, {'PASS'}, rep.results)

    def test_solo_pass(self):
        rep = self.net(solo=True).run('rs.observations')
        self.assertEqual({v[0] for v in rep.results.values()}, {'PASS'}, rep.results)

    def test_detects_unnamed_witnesses(self):
        rep = self.net(defects=('allWitness',)).run('rs.observations')
        self.assert_status(rep, 'assault_seen', 'FAIL', 'who could not witness it')

    def test_detects_a_second_publication_of_a_death(self):
        rep = self.net(defects=('doubleDeath',)).run('rs.observations')
        self.assert_status(rep, 'group_death: the members that see', 'FAIL', 'group_death of')

    def test_materialized_member_body_removed(self):
        # A body left by the member without body (materialized by Living Knox) stood on the spot of rs.relation.
        net = self.net()
        net.server.lua('MATERIALIZE = true')
        rep = net.run('rs.observations')
        self.assertEqual({v[0] for v in rep.results.values()}, {'PASS'}, rep.results)
        self.assertEqual(net.server.lua('local n = 0 for _ in pairs(BODIES) do n = n + 1 end return n'), 0)

    def test_blind_witness_expected_nothing(self):
        net = self.net()
        net.server.lua('BLIND["1002,1001"] = true')   # B (2, 1 from the requester) sees nothing
        rep = net.run('rs.observations')
        self.assert_status(rep, 'group_death: the members that see', 'PASS')
        notes = ' '.join(rep.notes[next(k for k in rep.notes if k.startswith('group_death: the members'))])
        self.assertIn('witnesses expected: A', notes)
        self.assertNotIn('A, B', notes)


# ------------------------------------------------------------------------------------------------ E09-T03

FACTION_DEFECTS = {
    # A member without mandate allowed to conclude (mandate ignored).
    'mandateIgnored': r'''
        local orig = F.canConclude
        F.canConclude = function(p)
            local ok, r, team = orig(p)
            if not ok and r == "no_mandate" then return true, "negotiator", team end
            return ok, r, team
        end''',
    # Agreements looked up by the name of the team at their conclusion (lost by a rename).
    'agreementByName': r'''
        local orig, names = F.agreementOf, {}
        local conclude = F.conclude
        F.conclude = function(p, gid, kind, expect, signer)
            local ok, why, a = conclude(p, gid, kind, expect, signer)
            if ok then for _, r in ipairs(F.list()) do if r.id == a.team then names[gid .. a.team] = r.name end end end
            return ok, why, a
        end
        F.agreementOf = function(gid, team)
            for _, r in ipairs(F.list()) do
                if r.id == team and names[gid .. team] and r.name ~= names[gid .. team] then return nil end
            end
            return orig(gid, team)
        end''',
}


class FactionMandateTests(Bench):
    """rs.factions.mandate : vrai RS_Factions, faction créée et renommée par les paquets du client propriétaire."""

    def faction_net(self, defect=None, **kw):
        net = self.net(**kw)
        if defect:
            net.server.lua(FACTION_DEFECTS[defect])
        return net

    def test_mp_two_clients_pass(self):
        net = self.faction_net()
        rep = net.run('rs.factions.mandate')
        self.assert_status(rep, 'renamed faction', 'PASS')
        self.assert_status(rep, 'solo:', 'SKIP')
        # Faction disbanded by its owner, agreement removed.
        self.assertEqual(net.server.lua('return Faction.getFactions():size()'), 0)
        self.assertEqual(net.server.lua('return #F.agreements()'), 0)

    def test_solo_personal_team(self):
        rep = self.faction_net(solo=True).run('rs.factions.mandate')
        self.assert_status(rep, 'solo:', 'PASS')
        self.assert_status(rep, 'renamed faction', 'SKIP')

    def test_one_client_skips(self):
        rep = self.faction_net(users=('rs_mp1',)).run('rs.factions.mandate')
        self.assert_status(rep, 'renamed faction', 'SKIP')

    def test_detects_a_mandate_ignored(self):
        rep = self.faction_net('mandateIgnored').run('rs.factions.mandate')
        self.assert_status(rep, 'renamed faction', 'FAIL', 'member without mandate may conclude')

    def test_detects_agreements_lost_by_a_rename(self):
        rep = self.faction_net('agreementByName').run('rs.factions.mandate')
        self.assert_status(rep, 'renamed faction', 'FAIL', 'agreement lost by the rename')

    def test_faction_option_off_fails_with_a_reason(self):
        net = self.faction_net()
        net.server.lua('FACTION_OPTION = false')
        rep = net.run('rs.factions.mandate')
        self.assert_status(rep, 'renamed faction', 'FAIL', 'faction never created')


# ------------------------------------------------------------------------------------------------ sources

class SourceTests(unittest.TestCase):

    def test_kahlua_constraints_and_ascii(self):
        for path in NEW_LUA:
            raw = path.read_bytes()
            self.assertTrue(all(b < 128 for b in raw), f'{path.name}: non-ASCII byte')
            code = re.sub(r'--\[\[.*?\]\]', '', raw.decode('ascii'), flags=re.S)
            code = re.sub(r'--[^\n]*', '', code)
            self.assertIsNone(re.search(r'(?<![.:\w])next\s*\(', code), path.name)
            self.assertIsNone(re.search(r'\bgoto\b|debug\.traceback|%q|coroutine\.', code), path.name)
            self.assertIsNone(re.search(r'[~&|]\s*\d|<<|>>|//', code.replace('~=', '')), path.name)

    def test_suites_tagged_for_the_mp_campaign(self):
        for name, path in SUITE_FILES.items():
            code = path.read_text(encoding='ascii')
            self.assertRegex(code, r'RST\.suite\("[\w.]+", \{ tags = \{ "server", "world" \}', name)

    def test_steps_file_loaded_by_every_suite_that_asks_its_steps(self):
        for name, path in SUITE_FILES.items():
            code = path.read_text(encoding='ascii')
            asked = set(re.findall(r'Steps\.ask\(\w+, "([\w.]+)"', code))
            if asked:
                self.assertIn('require "RST/RST_PeerChecksRadio"', code, name)
            steps = (DEV / 'shared' / 'RST' / 'RST_PeerChecksRadio.lua').read_text(encoding='ascii')
            for step in asked:
                self.assertIn(f'Steps.on("{step}"', steps, f'{name}: step {step}')


if __name__ == '__main__':
    unittest.main()
