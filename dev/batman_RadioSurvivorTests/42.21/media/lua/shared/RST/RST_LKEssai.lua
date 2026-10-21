--[[
RST_LKEssai - shared core of the comparative body trial LK02-T10 (Living Knox): an NPC body built on an ordinary
zombie (kind "A") or on a reanimated player (kind "B"). Development mod only, never published.

Files
    shared/RST/RST_LKEssai.lua          this core: constants, option parsing, log, observation, local application
    server/RST/RST_LKEssaiServer.lua    authority (server, or solo): registry, spawn, set, walk, clear, list
    client/RST/RST_LKEssaiClient.lua    console commands LKE.* and the per-client application loop
    shared/RST/suites/RST_LKEssaiSuite.lua   suite "lk.essai" (tags world, server)
Protocol and result table: docs/annexes/conception/corps-et-animations.md, section "Essai comparatif - protocole".

Options (LKE.set(id, option, value)); where each one is applied (see LKE.Core.applyLocal):
    useless      bool   setUseless, on every machine (the owner's value wins, NetworkZombieVariables)
    noTeeth      bool   setNoTeeth, on every machine (not transmitted)
    clearTarget  bool   setTarget(nil) at every tick, on every machine
    skin         "human" | "<Male|Female>Body0N"   setSkinTextureName + blood, dirt, wounds removed + resetModel;
                        on the clients after the local dressing (isPersistentOutfitInit), again after a recreation
    hand         "none" | "Module.Item"   setPrimaryHandItem on the clients and in solo only (never on a server)
    serverHand   "none" | "Module.Item"   setPrimaryHandItem ON THE SERVER, on purpose: expected exception in
                        IsoGameCharacter.preupdate (zombies-as-npc-bodies.md); MP server only
    attached     "none" | "Module.Item" | "Module.Item@Location"   setAttachedItem by the authority, then
                        sendAttachedItem on a server (clients present at that moment only); default location
                        "Rifle On Back"
    voice        "normal" | "prefix" | "grapple"   voice cut tracks, on every machine: "prefix" = unknown voice
                        prefix + current voice stopped; "grapple" = setReanimatedForGrappleOnly(true)
Walk modes (LKE.walk(id, dx, dy, mode)), executed once by the machine that simulates the body:
    plain        useless off, pathToLocation
    pathfind     useless on, pathToLocation, then bPathfind forced (setVariable) and setMoving(false)
    notarget     useless off, target cleared at every tick, pathToLocation
    uselessline  useless on, plain pathToLocation (measure: WalkTowardState sends a useless zombie back to idle)

Who simulates a zombie (LKE.Core.simulatedHere): isRemoteZombie() is NetworkZombieComponent.isRemote(), i.e.
"no owner connection" (NetworkZombieComponent.java:23): on an MP client false = this client owns it
(NetworkZombieSimulator.becomeLocal, java:124-129); on a server it is TRUE for a zombie the server simulates and
false for a client-owned one; in solo it is always true and meaningless. Hence: client = not isRemoteZombie();
server = getOwner() == nil; solo = always.

Every console or log line is English and starts with "[LKE]". Lines are also appended to
Zomboid/Lua/batman_RadioSurvivor/tests/lke-essai.log of the machine that wrote them (getFileWriter, append).
]]

require "RST/RST"

LKE = LKE or {}
LKE.Core = LKE.Core or {}
local C = LKE.Core

C.MODULE = "LKE"
-- Vanilla civilian outfit, female and male lists: media/clothing/clothing.xml:7719 and :27617 ("Generic01").
C.OUTFIT = "Generic01"
C.FEMALE_CHANCE = 50
C.MOD_KEY = "lkEssaiId"
C.LOG_FILE = RST.FILE_DIR .. "lke-essai.log"
C.SILENT_PREFIX = "LKESilent"
C.DEFAULT_ATTACH_LOCATION = "Rifle On Back"
C.WALK_MODES = { plain = true, pathfind = true, notarget = true, uselessline = true }
C.OPTION_KINDS = { useless = "bool", noTeeth = "bool", clearTarget = "bool", skin = "skin", hand = "item",
    serverHand = "item", attached = "attached", voice = "voice" }
C.ONE_SHOT = { "skin", "hand", "serverHand", "attached", "voice" }

-- ---------------------------------------------------------------- environment

function C.side()
    if type(isClient) == "function" and isClient() then return "client" end
    if type(isServer) == "function" and isServer() then return "server" end
    return "solo"
end

function C.isAuthority()
    return C.side() ~= "client"
end

-- ---------------------------------------------------------------- log

local function oneLine(s)
    s = string.gsub(tostring(s), "\r", "")
    return (string.gsub(s, "\n", " / "))
end

-- Appends one line to the log file of this machine (protected: never raises).
local function appendFile(line)
    if type(getFileWriter) ~= "function" then return end
    pcall(function()
        local w = getFileWriter(C.LOG_FILE, true, true)
        if w then
            w:writeln(line)
            w:close()
        end
    end)
end

function C.log(msg)
    local line = "[LKE] " .. oneLine(msg)
    print(line)
    appendFile(line)
    local cap = C._capture
    if cap then cap[#cap + 1] = line end
    return line
end

-- Collects the lines logged by fn(...) (nested captures keep the outer one). Returns the lines, then fn's results.
function C.capture(fn, ...)
    local outer = C._capture
    local lines = outer or {}
    C._capture = lines
    local ok, a, b = pcall(fn, ...)
    C._capture = outer
    if not ok then
        local line = "[LKE] ERROR: " .. oneLine(a)
        print(line)
        appendFile(line)
        lines[#lines + 1] = line
        return lines, false, "error: " .. oneLine(a)
    end
    return lines, a, b
end

-- ---------------------------------------------------------------- values

function C.round(v)
    if type(v) ~= "number" then return tostring(v) end
    return tostring(math.floor(v * 100 + 0.5) / 100)
end

function C.normId(v)
    if type(v) == "number" then return "LKE-" .. tostring(math.floor(v)) end
    if type(v) == "string" then
        if string.find(v, "^%d+$") then return "LKE-" .. v end
        return v
    end
    return nil
end

local function parseBool(v)
    if v == true or v == "true" or v == "on" or v == 1 then return true end
    if v == false or v == "false" or v == "off" or v == 0 then return false end
    return nil
end

local function isItemType(v)
    return type(v) == "string" and string.find(v, "^[%w_]+%.[%w_]+$") ~= nil
end

-- Returns the normalized value, or nil and a reason.
function C.parseOption(option, value)
    local kind = C.OPTION_KINDS[option]
    if not kind then
        local names = {}
        for name in pairs(C.OPTION_KINDS) do names[#names + 1] = name end
        table.sort(names)
        return nil, "unknown option '" .. tostring(option) .. "' (" .. table.concat(names, ", ") .. ")"
    end
    if kind == "bool" then
        local b = parseBool(value)
        if b == nil then return nil, option .. " expects true or false, got " .. tostring(value) end
        return b
    end
    if kind == "skin" then
        if value == "human" then return value end
        if type(value) == "string" and string.find(value, "^%a+Body0%d$") then return value end
        return nil, "skin expects \"human\" or a body texture such as MaleBody01, got " .. tostring(value)
    end
    if kind == "item" then
        if value == "none" or isItemType(value) then return value end
        return nil, option .. " expects \"none\" or a full item type such as Base.Hammer, got " .. tostring(value)
    end
    if kind == "attached" then
        if value == "none" then return value end
        if type(value) == "string" then
            local item = string.match(value, "^([^@]+)@") or value
            if isItemType(item) then return value end
        end
        return nil, "attached expects \"none\", Module.Item or Module.Item@Location, got " .. tostring(value)
    end
    if value == "normal" or value == "prefix" or value == "grapple" then return value end
    return nil, "voice expects normal, prefix or grapple, got " .. tostring(value)
end

-- Settings implied by a walk mode (see the header).
function C.walkSettings(mode)
    if mode == "plain" then return { useless = false, clearTarget = false } end
    if mode == "pathfind" then return { useless = true } end
    if mode == "notarget" then return { useless = false, clearTarget = true } end
    if mode == "uselessline" then return { useless = true } end
    return nil
end

-- ---------------------------------------------------------------- observation

-- obj:method() under pcall; nil when obj is nil, the method is missing or raises.
local function get(obj, method)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[method](obj) end)
    if ok then return v end
    return nil
end
C.get = get

function C.isDead(z)
    return z == nil or get(z, "isDead") == true
end

-- True when this machine simulates the zombie (see the header).
function C.simulatedHere(z)
    local side = C.side()
    if side == "client" then return get(z, "isRemoteZombie") == false end
    if side == "server" then return get(z, "getOwner") == nil end
    return true
end

function C.ownerName(z)
    local side = C.side()
    if side == "server" then
        local p = get(z, "getOwnerPlayer")
        if p ~= nil then return tostring(get(p, "getUsername")) end
        return "server"
    end
    if side == "client" then
        if C.simulatedHere(z) then return "this client" end
        return "remote"
    end
    return "solo"
end

function C.distance(z, x, y)
    local zx, zy = get(z, "getX"), get(z, "getY")
    if type(zx) ~= "number" or type(zy) ~= "number" then return nil end
    return math.sqrt((zx - x) * (zx - x) + (zy - y) * (zy - y))
end

function C.describe(z)
    if z == nil then return "body=nil" end
    local hv = get(z, "getHumanVisual")
    local desc = get(z, "getDescriptor")
    local target = get(z, "getTarget")
    local md = get(z, "getModData")
    local parts = {
        "pos=" .. C.round(get(z, "getX")) .. "," .. C.round(get(z, "getY")) .. "," .. C.round(get(z, "getZ")),
        "onlineId=" .. tostring(get(z, "getOnlineID")),
        "state=" .. tostring(get(z, "getCurrentStateName")),
        "real=" .. tostring(get(z, "getRealState")),
        "reanimatedPlayer=" .. tostring(get(z, "isReanimatedPlayer")),
        "outfitId=" .. tostring(get(z, "getPersistentOutfitID")),
        "useless=" .. tostring(get(z, "isUseless")),
        "noTeeth=" .. tostring(get(z, "isNoTeeth")),
        "target=" .. (target ~= nil and tostring(target) or "nil"),
        "onFloor=" .. tostring(get(z, "isOnFloor")),
        "dead=" .. tostring(get(z, "isDead")),
        "owner=" .. C.ownerName(z),
        "skin=" .. tostring(get(hv, "getSkinTexture")),
        "voice=" .. tostring(get(desc, "getVoicePrefix")),
        "grapple=" .. tostring(get(z, "isReanimatedForGrappleOnly")),
        "tag=" .. tostring(type(md) == "table" and md[C.MOD_KEY] or nil),
    }
    return table.concat(parts, " ")
end

-- ---------------------------------------------------------------- local application

local function cleanVisual(z, skinName)
    local hv = z:getHumanVisual()
    if skinName then hv:setSkinTextureName(skinName) end
    hv:removeBlood()
    hv:removeDirt()
    hv:getBodyVisuals():clear()
    local ivs = z:getItemVisuals()
    for i = 0, ivs:size() - 1 do
        local iv = ivs:get(i)
        iv:removeBlood()
        iv:removeDirt()
    end
end

function C.skinName(z, value)
    if value ~= "human" then return value end
    if get(z, "isFemale") then return "FemaleBody01" end
    return "MaleBody01"
end

-- Human skin and cleaning on a zombie of this machine; resetModel outside a server. Raises on a Java error.
function C.applySkin(z, value)
    cleanVisual(z, C.skinName(z, value))
    if C.side() ~= "server" then z:resetModel() end
end

local function splitAttached(value)
    local item, loc = string.match(value, "^([^@]+)@(.+)$")
    if item then return item, loc end
    return value, C.DEFAULT_ATTACH_LOCATION
end

local function newItem(fullType)
    if type(instanceItem) ~= "function" then error("instanceItem is not available", 0) end
    local item = instanceItem(fullType)
    if item == nil then error("instanceItem(" .. fullType .. ") returned nil", 0) end
    return item
end

C.voiceOrigin = C.voiceOrigin or {}

local function applyVoice(z, value)
    local desc = z:getDescriptor()
    local origin = C.voiceOrigin[z]
    if origin == nil then
        origin = desc:getVoicePrefix()
        C.voiceOrigin[z] = origin
    end
    if value == "prefix" then
        local current = z:getVoiceSoundName()
        desc:setVoicePrefix(C.SILENT_PREFIX)
        z:getEmitter():stopSoundByName(current)
    elseif value == "grapple" then
        z:setReanimatedForGrappleOnly(true)
    else
        desc:setVoicePrefix(origin)
        z:setReanimatedForGrappleOnly(false)
    end
end

-- One-shot application of one option on this machine. Returns a short action text, or nil when nothing is done
-- here (wrong side, or not ready yet: retried later). Raises on a Java error.
local function applyOne(z, option, value, side)
    if option == "skin" then
        if side == "client" and get(z, "isPersistentOutfitInit") ~= true then return nil end
        C.applySkin(z, value)
        return "skin " .. tostring(C.skinName(z, value))
    end
    if option == "hand" then
        if side == "server" then return "hand skipped on the server" end
        if value == "none" then z:setPrimaryHandItem(nil) else z:setPrimaryHandItem(newItem(value)) end
        return "hand " .. value
    end
    if option == "serverHand" then
        if side ~= "server" then return "serverHand skipped outside a server" end
        if value == "none" then z:setPrimaryHandItem(nil) else z:setPrimaryHandItem(newItem(value)) end
        return "serverHand " .. value .. " (watch the server console for an exception)"
    end
    if option == "attached" then
        if side == "client" then return "attached left to the authority" end
        local itemType, loc = splitAttached(value)
        if value == "none" then
            loc = C.DEFAULT_ATTACH_LOCATION
            z:setAttachedItem(loc, nil)
            return "attached none at " .. loc
        end
        local item = newItem(itemType)
        z:setAttachedItem(loc, item)
        if side == "server" then sendAttachedItem(z, loc, item) end
        return "attached " .. itemType .. " at " .. loc .. (side == "server" and " (sendAttachedItem)" or "")
    end
    if option == "voice" then
        applyVoice(z, value)
        return "voice " .. value
    end
    return nil
end

C.applied = C.applied or {}

-- Applies settings to a zombie of this machine. Continuous settings every call; one-shot settings once per
-- zombie object and value (a recreated zombie is a new object: applied again). Returns the list of actions done.
function C.applyLocal(z, settings, label)
    local actions = {}
    if z == nil or type(settings) ~= "table" or C.isDead(z) then return actions end
    local side = C.side()
    if settings.useless ~= nil and z:isUseless() ~= settings.useless then
        z:setUseless(settings.useless)
        actions[#actions + 1] = "useless " .. tostring(settings.useless)
    end
    if settings.noTeeth ~= nil and z:isNoTeeth() ~= settings.noTeeth then
        z:setNoTeeth(settings.noTeeth)
        actions[#actions + 1] = "noTeeth " .. tostring(settings.noTeeth)
    end
    if settings.clearTarget and z:getTarget() ~= nil then
        z:setTarget(nil)
    end
    local done = C.applied[z]
    if done == nil then
        done = {}
        C.applied[z] = done
    end
    for _, option in ipairs(C.ONE_SHOT) do
        local value = settings[option]
        if value ~= nil and done[option] ~= value then
            local ok, action = pcall(applyOne, z, option, value, side)
            if not ok then
                done[option] = value
                actions[#actions + 1] = option .. " FAILED: " .. oneLine(action)
            elseif action ~= nil then
                done[option] = value
                actions[#actions + 1] = action
            end
        end
    end
    if #actions > 0 and label then
        C.log(label .. ": " .. table.concat(actions, "; "))
    end
    return actions
end

-- Executes a walk order on a zombie this machine simulates. Returns a short text.
function C.execWalk(z, walk)
    z:pathToLocation(walk.x, walk.y, walk.z)
    if walk.mode == "pathfind" then
        z:setVariable("bPathfind", true)
        z:setMoving(false)
    end
    return "walk #" .. tostring(walk.seq) .. " " .. tostring(walk.mode) .. " to " .. walk.x .. "," .. walk.y .. ","
        .. walk.z .. " executed (" .. C.side() .. "); state now " .. tostring(get(z, "getCurrentStateName"))
end

function C.forget(z)
    C.applied[z] = nil
    C.voiceOrigin[z] = nil
end

-- Zombie of this machine with this online id (nil when absent or dead). Linear scan of the zombie list.
function C.findByOnlineId(onlineId)
    if type(onlineId) ~= "number" or onlineId < 0 then return nil end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z ~= nil and z:getOnlineID() == onlineId and not C.isDead(z) then return z end
    end
    return nil
end

return C
