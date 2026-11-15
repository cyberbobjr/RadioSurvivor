--[[
RST_LKBodiesClient - dev console of Living Knox bodies (LK02-T02 to T07). Development mod only.

From the Lua console (debug mode only; the server, or the solo game, also requires a save named rstest* and, on a
server, the DebugConsole capability):
    LKB.spawn()                    new npc, 2 east and 2 south of the player; appearance drawn from its number
    LKB.spawn(1, 0, true)          explicit offset (dx, dy) and a female npc
    LKB.spawn("manFairBeard")      named appearance profile (LivingKnox.Appearance.LOOKS), for screenshots:
                                   manFairBeard, manDarkGoatee, manBlondShaven, manOliveChops, manElderMoustache,
                                   womanFairBun, womanTanBob, womanDarkPonytail, womanBlondLong, womanBrownKate
    LKB.spawn("womanTanBob", 3, 0) named profile and explicit offset
    LKB.list()                     one line per npc of the registry: generation, state, inWorld, positions
    LKB.despawn(1)                 body removed, npc back to virtual (id 1 or "lk-1")
    LKB.embody(1[, dx, dy])        new body for a virtual npc near the player + (dx, dy), recorded clothes replayed
    LKB.forget(1)                  body removed, npc removed from the registry (its number is never reused)
    LKB.scan()                     full immediate scan: binding, duplicates, orphans
    LKB.clear()                    every npc forgotten
    LKB.gesture(1, "aim")          gesture of npc 1 (LK02-T05): idle, walk, run, crouch, aim, guard, strike
    LKB.weapon(1, "Base.Pistol")   weapon of npc 1 (LK02-T06): attached at rest, in hand for aim / guard / strike;
                                   "none" removes it (vanilla HandWeapon with a known AttachmentType only)
    LKB.anim(1)                    animation facts of npc 1 as displayed HERE (local copy, read on this machine):
                                   LKActor, LKGesture, action state, AnimSet state, live nodes and clips; weapon wanted
                                   here, hand items, item at its slot and variable Weapon
    LKB.moveTo(1, 9, 0, "walk")    directive of npc 1 (LK02-T07): go to its body square + (dx, dy); gesture walk
                                   (default), run or crouch; executed by the machine that simulates the body
    LKB.stop(1)                    directive: stop where it is
    LKB.face(1, "S")               directive: face N, NE, E, SE, S, SW, W, NW or an angle in degrees
    LKB.directive(1)               current directive of npc 1 on the authority: number, state, executor, last pose
    LKB.pose(1)                    read HERE: directive received, local execution, relayed pose and relay delays
Every command returns true when the request was sent (MP client) or handled (solo). Answers are "[LKB] ..." lines.
]]

require "RST/RST"
require "RST/suites/RST_LKAnims"
require "RST/suites/RST_LKEquipment"

LKB = LKB or {}

local function request(args)
    if not isDebugEnabled() then
        print("[LKB] refused: debug mode is off (start the game with -debug)")
        return false
    end
    local player = getPlayer()
    if isClient() then
        if player == nil then
            print("[LKB] refused: no local player")
            return false
        end
        sendClientCommand(player, "LKB", "cmd", args)
        print("[LKB] request " .. tostring(args.op) .. " sent to the server; the answer is printed here")
        return true
    end
    if LKB.Server == nil then
        print("[LKB] refused: RST_LKBodiesServer.lua is not loaded")
        return false
    end
    local ok = LKB.Server.handle(player, args)
    return ok and true or false
end

function LKB.spawn(dx, dy, female)
    if type(dx) == "string" then return request({ op = "spawn", look = dx, dx = dy, dy = female }) end
    return request({ op = "spawn", dx = dx, dy = dy, female = female == true })
end
function LKB.list() return request({ op = "list" }) end
function LKB.despawn(id) return request({ op = "despawn", id = id }) end
function LKB.embody(id, dx, dy) return request({ op = "embody", id = id, dx = dx, dy = dy }) end
function LKB.forget(id) return request({ op = "forget", id = id }) end
function LKB.scan() return request({ op = "scan" }) end
function LKB.clear() return request({ op = "clear" }) end
function LKB.gesture(id, gesture) return request({ op = "gesture", id = id, gesture = gesture }) end
function LKB.weapon(id, item) return request({ op = "weapon", id = id, item = item }) end
function LKB.moveTo(id, dx, dy, gesture) return request({ op = "move", id = id, dx = dx, dy = dy, gesture = gesture }) end
function LKB.stop(id) return request({ op = "stop", id = id }) end
function LKB.face(id, dir) return request({ op = "face", id = id, dir = dir }) end
function LKB.directive(id) return request({ op = "directive", id = id }) end

local function npcId(id)
    if type(id) == "number" then id = tostring(math.floor(id)) end
    if type(id) == "string" and string.find(id, "^%d+$") then id = "lk-" .. id end
    return id
end

-- Local read only: what this machine received, executes and shows for the npc.
function LKB.pose(id)
    local X, P = LivingKnox and LivingKnox.Executor, LivingKnox and LivingKnox.Presentation
    if X == nil then
        print("[LKB] LivingKnox.Executor is not loaded")
        return false
    end
    id = npcId(id)
    local e = X.directives()[id]
    print("[LKB] " .. tostring(id) .. " directive here: " .. (e and (e.op .. " #" .. tostring(e.v) .. " state "
        .. tostring(e.s) .. " done " .. tostring(e.done)) or "none"))
    local run = X.runs[id]
    print("[LKB] " .. tostring(id) .. " executed here: " .. (run and (run.op .. " #" .. tostring(run.v) .. " phase "
        .. tostring(run.phase) .. " retries " .. tostring(run.retries)) or "no"))
    if P ~= nil then
        local pose = P.poseOf(id)
        local st = P.stats
        print("[LKB] " .. tostring(id) .. " relayed pose: " .. (pose and (tostring(pose.s) .. " pr " .. tostring(pose.pr)
            .. " angle " .. tostring(pose.a) .. " gesture " .. tostring(pose.g)) or "none") .. "; relay delay last "
            .. tostring(st.lastDelay) .. " ms, max " .. tostring(st.maxDelay) .. " ms, mean "
            .. tostring(math.floor(P.meanDelay())) .. " ms over " .. tostring(st.samples) .. " pose(s)")
    end
    return true
end

-- Local read only: animation variables are not synchronized, each machine reads its own copy of the body.
function LKB.anim(id)
    local A = LivingKnox and LivingKnox.Anim
    if A == nil then
        print("[LKB] LivingKnox.Anim is not loaded")
        return false
    end
    if type(id) == "number" then id = tostring(math.floor(id)) end
    if type(id) == "string" and string.find(id, "^%d+$") then id = "lk-" .. id end
    local z = A.knownBodies()[id]
    if z == nil then
        print("[LKB] npc " .. tostring(id) .. " has no body displayed here")
        return false
    end
    local P = RST.LKAnims
    print("[LKB] " .. tostring(id) .. " wanted " .. A.gestureOf(id) .. "; " .. P.describe(P.info(z)))
    local E = LivingKnox.Equipment
    if E ~= nil then
        local w = E.wantedOf(id)
        local W = RST.LKEquipment
        print("[LKB] " .. tostring(id) .. " weapon " .. tostring(w and w.t or "none") .. (w and (" at " .. w.l) or "")
            .. "; " .. W.describe(W.state(z, w and w.l)))
    end
    return true
end

local function onServerCommand(module, command, args)
    if module ~= "LKB" or command ~= "log" or type(args) ~= "table" then return end
    for _, line in ipairs(args.lines or {}) do print("[LKB] server: " .. tostring(line)) end
end

if not LKB._clientSubscribed and type(Events) == "table" and type(Events.OnServerCommand) == "table" then
    Events.OnServerCommand.Add(onServerCommand)
    LKB._clientSubscribed = true
end

return LKB
