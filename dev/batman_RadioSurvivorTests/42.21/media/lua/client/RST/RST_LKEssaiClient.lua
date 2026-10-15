--[[
RST_LKEssaiClient - console commands of the body trial LK02-T10 (see RST_LKEssai.lua). Development mod only.

From the Lua console (debug mode only; the server, or the solo game, also requires a save named rstest* and, on a
server, the DebugConsole capability):
    LKE.spawn("A")                 ordinary zombie in the vanilla outfit Generic01, 2 squares east of the player
    LKE.spawn("B")                 reanimated player (dressed corpse reanimated), 2 east and 2 south
    LKE.spawn("B", "clean")        same, human skin and no blood before the corpse (frozen shared descriptor)
    LKE.spawn("A", nil, 1, 0)      explicit offset (dx, dy) from the player square
    LKE.list()                     one observation line per trial body, from the authority (server or solo)
    LKE.here()                     same observation, from THIS client (what this client sees)
    LKE.set(1, "useless", true)    options: useless, noTeeth, clearTarget (bool); skin ("human", "MaleBody01");
                                   hand / serverHand ("Base.Hammer", "none"); attached ("Base.Shotgun",
                                   "Base.Pistol@Holster Right", "none"); voice ("normal", "prefix", "grapple")
    LKE.walk(1, 6, 0, "pathfind")  walk to the body square + (dx, dy); modes plain, pathfind, notarget, uselessline
    LKE.clear()  /  LKE.clear(1)   removes every trial body (or one), corpses included
An id is the number printed by spawn (1) or its full form ("LKE-1"). Every command returns true when the request
was sent (MP client) or handled (solo), false and a reason otherwise. Results are printed as "[LKE] ..." lines and
appended to Zomboid/Lua/batman_RadioSurvivor/tests/lke-essai.log (each machine writes its own file).

On an MP client this file also keeps the server snapshot (module "LKE", command "snapshot") and applies the
per-client settings to the local copy of each body every tick (zombie found by online id): visuals, hand item,
voice and the flags useless / noTeeth / clearTarget; the walk order is executed by the client that owns the body
(not isRemoteZombie()), which reports it to the server ("walked"). Nothing is ever created by a client.
]]

require "RST/RST"
require "RST/RST_LKEssai"

local C = LKE.Core
LKE.Client = LKE.Client or {}
local K = LKE.Client

K.remote = K.remote or {}   -- id -> { kind, onlineId, settings, walk } (last server snapshot)
K.cache = K.cache or {}     -- id -> local zombie object
K.walked = K.walked or {}   -- id -> last walk seq executed here
K.SCAN_TICKS = 10

local log = C.log

local function refuse(reason)
    log("refused: " .. reason)
    return false, reason
end

local function request(args)
    if type(isDebugEnabled) ~= "function" or not isDebugEnabled() then
        return refuse("debug mode is off (start the game with -debug)")
    end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    if C.side() == "client" then
        if player == nil then return refuse("no local player") end
        local ok, err = pcall(sendClientCommand, player, C.MODULE, "cmd", args)
        if not ok then return refuse("request not sent: " .. tostring(err)) end
        log("request " .. tostring(args.op) .. " sent to the server; the answer is printed here")
        return true
    end
    if LKE.Server == nil then return refuse("RST_LKEssaiServer.lua is not loaded") end
    local ok = LKE.Server.handle(player, args)
    return ok and true or false
end

function LKE.spawn(kind, preset, dx, dy)
    return request({ op = "spawn", kind = kind, preset = preset, dx = dx, dy = dy })
end

function LKE.list()
    return request({ op = "list" })
end

function LKE.set(id, option, value)
    local nid = C.normId(id)
    if not nid then return refuse("set expects a trial id such as 1 or \"LKE-1\"") end
    local v, why = C.parseOption(option, value)
    if v == nil then return refuse(why) end
    return request({ op = "set", id = nid, option = option, value = v })
end

function LKE.walk(id, dx, dy, mode)
    local nid = C.normId(id)
    if not nid then return refuse("walk expects a trial id such as 1 or \"LKE-1\"") end
    if type(dx) ~= "number" or type(dy) ~= "number" then return refuse("walk expects numbers dx, dy") end
    mode = mode or "plain"
    if not C.WALK_MODES[mode] then return refuse("unknown walk mode '" .. tostring(mode) .. "'") end
    return request({ op = "walk", id = nid, dx = dx, dy = dy, mode = mode })
end

function LKE.clear(id)
    local nid = nil
    if id ~= nil then
        nid = C.normId(id)
        if not nid then return refuse("clear expects nothing or a trial id") end
    end
    return request({ op = "clear", id = nid })
end

-- Observation from this machine (MP client: local copies found by online id; solo: the authority registry).
function LKE.here()
    if C.side() ~= "client" then
        if LKE.Server == nil then return refuse("RST_LKEssaiServer.lua is not loaded") end
        LKE.Server.list()
        return true
    end
    local user = getPlayer() and getPlayer():getUsername() or "?"
    local n = 0
    for id, e in pairs(K.remote) do
        n = n + 1
        local z = C.findByOnlineId(e.onlineId)
        log("client " .. tostring(user) .. " sees " .. id .. " kind " .. tostring(e.kind) .. " onlineId="
            .. tostring(e.onlineId) .. " " .. (z and C.describe(z) or "body not loaded here"))
    end
    log(n .. " trial body(ies) known by this client")
    return true
end

-- ---------------------------------------------------------------- server answers (MP client)

local function dropLocal(onlineId)
    local z = C.findByOnlineId(onlineId)
    if z == nil then return false end
    z:removeFromWorld()
    z:removeFromSquare()
    C.forget(z)
    return true
end

function K.onServerCommand(module, command, args)
    if module ~= C.MODULE then return end
    args = type(args) == "table" and args or {}
    if command == "log" then
        for _, line in ipairs(args.lines or {}) do
            print("[LKE] server: " .. tostring(line))
        end
    elseif command == "snapshot" then
        K.remote = type(args.entries) == "table" and args.entries or {}
        for id in pairs(K.cache) do
            if K.remote[id] == nil then K.cache[id] = nil end
        end
    elseif command == "removed" then
        local dropped = 0
        for _, onlineId in ipairs(args.onlineIds or {}) do
            if dropLocal(onlineId) then dropped = dropped + 1 end
        end
        log("server removed " .. #(args.onlineIds or {}) .. " zombie(s); " .. dropped .. " local copy(ies) dropped")
    end
end

-- ---------------------------------------------------------------- per-client application (MP client)

K.ticks = K.ticks or 0

local function report(id, text)
    local player = getPlayer()
    if player == nil then return end
    pcall(sendClientCommand, player, C.MODULE, "cmd", { op = "walked", id = id, text = text })
end

function K.tick()
    if C.side() ~= "client" then return end
    K.ticks = K.ticks + 1
    local scan = K.ticks >= K.SCAN_TICKS
    if scan then K.ticks = 0 end
    for id, e in pairs(K.remote) do
        local z = K.cache[id]
        if scan or z == nil or C.isDead(z) or z:getOnlineID() ~= e.onlineId then
            z = C.findByOnlineId(e.onlineId)
            K.cache[id] = z
        end
        if z ~= nil then
            C.applyLocal(z, e.settings, id .. " client")
            local w = e.walk
            if type(w) == "table" and K.walked[id] ~= w.seq and C.simulatedHere(z) then
                K.walked[id] = w.seq
                local ok, text = pcall(C.execWalk, z, w)
                text = ok and text or ("walk failed: " .. tostring(text))
                log(id .. ": " .. text)
                report(id, text)
            end
        end
    end
end

if not K._subscribed and type(Events) == "table" then
    if type(Events.OnServerCommand) == "table" then
        Events.OnServerCommand.Add(function(module, command, args)
            LKE.Client.onServerCommand(module, command, args)
        end)
    end
    if type(Events.OnTick) == "table" then
        Events.OnTick.Add(function() LKE.Client.tick() end)
    end
    K._subscribed = true
end

return K
