--[[
RST_LKBodiesServer - authority side of the dev console LKB for Living Knox bodies (LK02-T02). Development mod only.
Runs on the dedicated server and in solo; an MP client also loads this file but never handles a request here.

Requests (module "LKB", command "cmd", args.op):
    spawn    { dx, dy, female, look }  new npc 2 squares east and 2 south of the player (or player + dx, dy), or on
                                  the nearest free square (LivingKnox.Bodies.findFreeSquare: no standing character
                                  on it or next to it, so the body can get up; the answer gives both squares);
                                  look = appearance profile name (LivingKnox.Appearance.LOOKS), else drawn
                                  from the npc number (female = true: among the women's profiles)
    list                          one line per npc of the registry (LivingKnox.Bodies.list)
    despawn  { id }               body removed, npc back to virtual
    embody   { id, dx, dy }       new body (next generation) for a virtual npc, near the player + (dx, dy) (default
                                  2, 2); its recorded clothes are replayed (LK02-T12)
    forget   { id }               body removed, npc removed from the registry
    clear                         every npc forgotten (test saves only, see the guard)
    scan                          full immediate scan (binding, duplicates, orphans)
    gesture  { id, gesture }      gesture of a known npc (LivingKnox.Anim.setGesture, LK02-T05)
    weapon   { id, item }         weapon of a known npc, "Module.Item" or "none" (LivingKnox.Equipment.setWeapon,
                                  LK02-T06): attached at rest, in hand for aim / guard / strike
    move     { id, dx, dy, gesture }  directive "go to the body square + (dx, dy)" (LivingKnox.Directives.moveTo,
                                  LK02-T07), gesture walk (default), run or crouch
    stop     { id }               directive "stop" (LivingKnox.Directives.stop)
    face     { id, dir }          directive "face dir" (LivingKnox.Directives.face): N, NE... or degrees
    directive { id }              current directive of a npc and its last accepted pose
Guard: debug console capability on a server (RST.Server.allowed: admin role), isDebugEnabled() in solo, and a save
named rstest* (RST.worldGuard) everywhere. Answers: "[LKB] ..." lines printed here and sent back to the requester
(sendServerCommand "LKB" "log").
]]

require "RST/RST"

LKB = LKB or {}
LKB.Server = LKB.Server or {}
local S = LKB.Server

S.MODULE = "LKB"
S.OFFSET = 2

local function side()
    if isClient() then return "client" end
    if isServer() then return "server" end
    return "solo"
end

local function B() return LivingKnox and LivingKnox.Bodies end

-- Normalized npc id: 3 or "3" -> "lk-3"; other strings unchanged.
function S.normId(v)
    if type(v) == "number" then return "lk-" .. tostring(math.floor(v)) end
    if type(v) == "string" and string.find(v, "^%d+$") then return "lk-" .. v end
    if type(v) == "string" then return v end
    return nil
end

local function pos(p)
    if type(p) ~= "table" then return "-" end
    return tostring(p.x) .. "," .. tostring(p.y) .. "," .. tostring(p.z)
end

function S.describe(e)
    local p = e.profile or {}
    return e.id .. " gen=" .. tostring(e.generation) .. " state=" .. tostring(e.state) .. " inWorld="
        .. tostring(e.inWorld) .. " female=" .. tostring(p.female) .. " outfit=" .. tostring(p.outfit)
        .. " look=" .. tostring(p.look) .. " skin=" .. tostring(p.skin) .. " hair=" .. tostring(p.hair)
        .. " beard=" .. tostring(p.beard) .. " variant=" .. tostring(p.variant)
        .. " want=" .. pos(e.want) .. " last=" .. pos(e.last) .. " clothes="
        .. (e.clothes and tostring(#e.clothes) or "none") .. " weapon=" .. tostring(e.weapon or "none")
end

-- Directive requests (LK02-T07).
function S.directive(op, args, out)
    local D = LivingKnox.Directives
    if D == nil then
        out[#out + 1] = "LivingKnox.Directives is not loaded"
        return false
    end
    local id = S.normId(args.id)
    local v, why
    if op == "move" then
        local z, where = B().find(id)
        if z == nil then
            out[#out + 1] = "move refused: npc " .. tostring(id) .. " has no body here (" .. tostring(where) .. ")"
            return false
        end
        local dx = type(args.dx) == "number" and math.floor(args.dx) or 0
        local dy = type(args.dy) == "number" and math.floor(args.dy) or 0
        local x, y, zz = math.floor(z:getX()) + dx, math.floor(z:getY()) + dy, math.floor(z:getZ())
        v, why = D.moveTo(id, x, y, zz, args.gesture)
        out[#out + 1] = v and ("move " .. tostring(id) .. " #" .. v .. " to " .. x .. "," .. y .. "," .. zz .. " ("
            .. tostring(args.gesture or "walk") .. ")") or ("move refused: " .. tostring(why))
        return v ~= nil
    elseif op == "stop" then
        v, why = D.stop(id)
        out[#out + 1] = v and ("stop " .. tostring(id) .. " #" .. v) or ("stop refused: " .. tostring(why))
        return v ~= nil
    elseif op == "face" then
        v, why = D.face(id, args.dir)
        out[#out + 1] = v and ("face " .. tostring(id) .. " #" .. v .. " " .. tostring(args.dir))
            or ("face refused: " .. tostring(why))
        return v ~= nil
    end
    local e = D.get(id)
    if e == nil then
        out[#out + 1] = tostring(id) .. ": no directive"
        return true
    end
    local target = e.op == "move" and (" to " .. e.x .. "," .. e.y .. "," .. e.z .. " (" .. tostring(e.g) .. ")")
        or (e.op == "face" and (" angle " .. tostring(e.a)) or "")
    out[#out + 1] = tostring(id) .. ": " .. e.op .. " #" .. e.v .. target .. ", state " .. tostring(e.s) .. ", done "
        .. tostring(e.done) .. ", executed by " .. tostring(e.by)
    local pose = D.poses[id]
    if pose ~= nil then
        out[#out + 1] = tostring(id) .. ": last pose " .. tostring(pose.s) .. " at " .. math.floor(pose.x * 10) / 10
            .. "," .. math.floor(pose.y * 10) / 10 .. " angle " .. tostring(pose.a) .. " by " .. tostring(pose.by)
    end
    local st = D.stats
    out[#out + 1] = "reports " .. st.reports .. ", accepted " .. st.accepted .. ", rejected " .. st.rejected
        .. ", stale " .. st.stale .. ", relayed " .. st.relayed
    return true
end

local function dispatch(player, args, out)
    local bodies = B()
    if bodies == nil then
        out[#out + 1] = "LivingKnox.Bodies is not loaded"
        return false
    end
    local op = args.op
    if op == "spawn" then
        if player == nil then
            out[#out + 1] = "spawn refused: no player"
            return false
        end
        local dx = type(args.dx) == "number" and math.floor(args.dx) or S.OFFSET
        local dy = type(args.dy) == "number" and math.floor(args.dy) or S.OFFSET
        local x, y, z = math.floor(player:getX()) + dx, math.floor(player:getY()) + dy, math.floor(player:getZ())
        local profile = {}
        if type(args.look) == "string" then
            profile.look = args.look
        elseif args.female == true then
            profile.female = true
        end
        local id, why = bodies.spawn(profile, x, y, z)
        if id then
            local at = math.floor(why:getX()) .. "," .. math.floor(why:getY()) .. "," .. math.floor(why:getZ())
            local wanted = x .. "," .. y .. "," .. z
            out[#out + 1] = "spawned " .. id .. " at " .. at .. (at ~= wanted and (" (wanted " .. wanted .. ")") or "")
        else
            out[#out + 1] = "spawn refused: " .. tostring(why)
        end
        return id ~= nil
    elseif op == "list" then
        local list = bodies.list()
        for _, e in ipairs(list) do out[#out + 1] = S.describe(e) end
        out[#out + 1] = #list .. " npc(s) (" .. side() .. ")"
        return true
    elseif op == "despawn" or op == "forget" then
        local id = S.normId(args.id)
        local ok, n = bodies.despawn(id, op == "forget")
        out[#out + 1] = ok and (op .. " " .. tostring(id) .. ": " .. tostring(n) .. " body removed")
            or (op .. " refused: " .. tostring(n))
        return ok
    elseif op == "embody" then
        if player == nil then
            out[#out + 1] = "embody refused: no player"
            return false
        end
        local id = S.normId(args.id)
        local dx = type(args.dx) == "number" and math.floor(args.dx) or S.OFFSET
        local dy = type(args.dy) == "number" and math.floor(args.dy) or S.OFFSET
        local body, why = bodies.embody(id, math.floor(player:getX()) + dx, math.floor(player:getY()) + dy,
            math.floor(player:getZ()))
        out[#out + 1] = body and ("embodied " .. tostring(id) .. " at " .. math.floor(body:getX()) .. ","
            .. math.floor(body:getY()) .. "," .. math.floor(body:getZ())) or ("embody refused: " .. tostring(why))
        return body ~= nil
    elseif op == "clear" then
        local count = 0
        for _, e in ipairs(bodies.list()) do
            if bodies.despawn(e.id, true) then count = count + 1 end
        end
        out[#out + 1] = "cleared " .. count .. " npc(s)"
        return true
    elseif op == "gesture" then
        local A = LivingKnox.Anim
        if A == nil then
            out[#out + 1] = "LivingKnox.Anim is not loaded"
            return false
        end
        local id = S.normId(args.id)
        local _, where = bodies.find(id)
        if where == "unknown" then
            out[#out + 1] = "gesture refused: unknown npc " .. tostring(id)
            return false
        end
        local ok, why = A.setGesture(id, args.gesture)
        out[#out + 1] = ok and ("gesture " .. tostring(id) .. " -> " .. tostring(args.gesture) .. " (body "
            .. tostring(where) .. ")") or ("gesture refused: " .. tostring(why))
        return ok
    elseif op == "weapon" then
        local E = LivingKnox.Equipment
        if E == nil then
            out[#out + 1] = "LivingKnox.Equipment is not loaded"
            return false
        end
        local id = S.normId(args.id)
        local item = args.item
        if item == nil then item = "none" end
        local ok, why = E.setWeapon(id, item)
        local _, where = bodies.find(id)
        out[#out + 1] = ok and ("weapon " .. tostring(id) .. " -> " .. tostring(item) .. " (body " .. tostring(where)
            .. ")") or ("weapon refused: " .. tostring(why))
        return ok
    elseif op == "move" or op == "stop" or op == "face" or op == "directive" then
        return S.directive(op, args, out)
    elseif op == "scan" then
        out[#out + 1] = "scanned " .. tostring(bodies.scanAll()) .. " zombie(s)"
        return true
    end
    out[#out + 1] = "unknown request '" .. tostring(op) .. "'"
    return false
end

function S.guard(player)
    if side() == "server" then
        if RST.Server == nil or not RST.Server.allowed(player) then
            return false, "permission denied: capability DebugConsole (admin) required"
        end
    elseif not isDebugEnabled() then
        return false, "debug mode is off (start the game with -debug)"
    end
    return RST.worldGuard()
end

-- Handles one request; returns ok and the answer lines (each also printed here).
function S.handle(player, args)
    if side() == "client" then return false, {} end
    args = type(args) == "table" and args or {}
    local out = {}
    local allowed, why = S.guard(player)
    local ok = false
    if not allowed then
        out[1] = "request " .. tostring(args.op) .. " refused: " .. tostring(why)
    else
        local okCall, result = pcall(dispatch, player, args, out)
        if okCall then ok = result else out[#out + 1] = "ERROR: " .. tostring(result) end
    end
    for i, line in ipairs(out) do
        out[i] = "[LKB] " .. line
        print(out[i])
    end
    return ok, out
end

function S.onClientCommand(module, command, player, args)
    if module ~= S.MODULE or command ~= "cmd" then return end
    local _, lines = S.handle(player, args)
    if side() == "server" and player ~= nil then
        pcall(sendServerCommand, player, S.MODULE, "log", { lines = lines })
    end
end

if not S._subscribed and type(Events) == "table" and type(Events.OnClientCommand) == "table" then
    Events.OnClientCommand.Add(function(module, command, player, args)
        LKB.Server.onClientCommand(module, command, player, args)
    end)
    S._subscribed = true
end

return S
