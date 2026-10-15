--[[
RST_LKEssaiServer - authority side of the body trial LK02-T10 (see RST_LKEssai.lua). Development mod only.
Runs on the dedicated server and in solo; an MP client also loads this file (server/ is loaded by clients) but
never handles a command nor ticks here.

API (also used by the suite lk.essai; player = the requester IsoPlayer)
    LKE.Server.spawn(player, kind, preset, dx, dy) -> entry, or nil and a reason
        kind "A": addZombiesInOutfit(x, y, z, 1, "Generic01", 50) (LuaManager.java:8355-8445), tag in the ModData
                  (lost on recycling: identity check only), preset "clean" = skin "human" for every client.
        kind "B": addZombiesInOutfit (dressed), DoZombieInventory (clothes become worn items, as vanilla
                  addZombiesEating, LuaManager.java:8317-8341), sq:createCorpse(zombie) (IsoGridSquare.java:10109:
                  the zombie leaves the world, IsoDeadBody keeps visual, worn items, ModData), then body:reanimate()
                  (IsoDeadBody.java:1832-1946: new zombie, reanimated player, ModData copied, shared descriptor
                  sent to the connections, corpse removed). preset "clean" = human skin and no blood BEFORE the
                  corpse: the shared descriptor is a frozen copy (SharedDescriptors.java:44-96).
        Spawn square: player square + (dx, dy) (default A: 2,0; B: 2,2), level of the player; must be loaded.
    LKE.Server.set(id, option, value)        -> true, or false and a reason
    LKE.Server.walk(id, dx, dy, mode)        -> true, or false and a reason (target = body square + dx, dy)
    LKE.Server.list()                        -> number of entries (logs one line per entry)
    LKE.Server.clear(id)                     -> number of objects removed (id nil = every trial body)
    LKE.Server.find(entry)                   -> zombie or nil, how ("object", "moddata", "outfit", "lost"), count
    LKE.Server.handle(player, args)          -> ok, lines   (console request, guards included)
Guards (handle): debug console capability on a server (RST.Server.allowed: admin role), isDebugEnabled() in solo,
and the save name rstest* (RST.worldGuard) everywhere.

Network (module "LKE")
    client -> server   cmd      { op = "spawn" | "set" | "walk" | "list" | "clear" | "walked", ... }
    server -> client   log      { lines }                   lines logged while handling the request (requester)
                       snapshot { entries = { [id] = { kind, onlineId, settings, walk } } }   every client
                       removed  { onlineIds = { ... } }     zombies the server removed (clients drop their copy)
Removal: zombie:removeFromWorld() + removeFromSquare() (vanilla ISSpawnHordeUI.lua:325-326); a reanimated player
gets setHealth(0) first, otherwise VirtualZombieManager.RemoveZombie parks it in ReanimatedPlayers and it comes
back with its chunk (ReanimatedPlayers.java:69-110, VirtualZombieManager.java:677-684). The server cannot call
NetworkZombiePacker.deleteZombie (used by /removezombies): clients drop their copy on "removed", or after 5 s
without packet (IsoZombie.java:2716-2722). Leftover corpses: square:removeCorpse(body, false) (sent to clients,
IsoGridSquare.java:2600-2620).
]]

require "RST/RST"
require "RST/RST_LKEssai"

local C = LKE.Core
LKE.Server = LKE.Server or {}
local S = LKE.Server

S.entries = S.entries or {}
S.order = S.order or {}
S.seq = S.seq or 0
S.OFFSETS = { A = { 2, 0 }, B = { 2, 2 } }
S.OUTFIT_RADIUS = 30
S.CORPSE_RADIUS = 3
S.REFRESH_TICKS = 30
S.MAX_REPLY_LINES = 60
S.MAX_LINE_LEN = 300

local log = C.log
local get = C.get

local function oneLine(s)
    return (string.gsub(tostring(s), "[\r\n]", " "))
end

-- ---------------------------------------------------------------- registry

function S.entry(id)
    return S.entries[C.normId(id) or ""]
end

local function addEntry(entry)
    S.entries[entry.id] = entry
    S.order[#S.order + 1] = entry.id
end

local function dropEntry(id)
    S.entries[id] = nil
    for i = #S.order, 1, -1 do
        if S.order[i] == id then table.remove(S.order, i) end
    end
end

local function zombieList()
    return getCell():getZombieList()
end

local function inWorld(z)
    if z == nil or C.isDead(z) then return false end
    local list = zombieList()
    for i = 0, list:size() - 1 do
        if list:get(i) == z then return true end
    end
    return false
end

local function tagOf(obj)
    local md = get(obj, "getModData")
    if type(md) ~= "table" then return nil end
    return md[C.MOD_KEY]
end

-- Finds the body of an entry: same object, else ModData tag, else (kind A) persistent outfit id near the last
-- known position. Returns zombie or nil, how, number of candidates of that kind (duplicates when > 1).
function S.find(entry)
    if inWorld(entry.zombie) then return entry.zombie, "object", 1 end
    local list = zombieList()
    local byTag, tagCount, byOutfit, outfitCount = nil, 0, nil, 0
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z ~= nil and not C.isDead(z) then
            if tagOf(z) == entry.id then
                tagCount = tagCount + 1
                byTag = byTag or z
            elseif entry.kind == "A" and entry.outfitId ~= nil and get(z, "getPersistentOutfitID") == entry.outfitId then
                local d = C.distance(z, entry.x, entry.y)
                if d ~= nil and d <= S.OUTFIT_RADIUS then
                    outfitCount = outfitCount + 1
                    byOutfit = byOutfit or z
                end
            end
        end
    end
    if byTag then return byTag, "moddata", tagCount end
    if byOutfit then return byOutfit, "outfit", outfitCount end
    return nil, "lost", 0
end

-- Refreshes the cached object, online id and position. Returns zombie, how, count, changed (online id changed).
function S.refresh(entry)
    local z, how, count = S.find(entry)
    local changed = false
    if z ~= nil then
        if entry.zombie ~= z then C.forget(entry.zombie) end
        entry.zombie = z
        local onlineId = get(z, "getOnlineID")
        changed = onlineId ~= entry.onlineId
        entry.onlineId = onlineId
        entry.x, entry.y, entry.z = get(z, "getX"), get(z, "getY"), get(z, "getZ")
    end
    entry.how = how
    return z, how, count, changed
end

-- Corpses tagged with the entry id on the squares around its last position.
function S.taggedCorpses(entry)
    local found = {}
    if type(entry.x) ~= "number" then return found end
    local cx, cy, cz = math.floor(entry.x), math.floor(entry.y), math.floor(entry.z or 0)
    for x = cx - S.CORPSE_RADIUS, cx + S.CORPSE_RADIUS do
        for y = cy - S.CORPSE_RADIUS, cy + S.CORPSE_RADIUS do
            local sq = getCell():getGridSquare(x, y, cz)
            if sq ~= nil then
                local objs = sq:getStaticMovingObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if instanceof(o, "IsoDeadBody") and tagOf(o) == entry.id then found[#found + 1] = o end
                end
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------- network

local function broadcast(command, args)
    if C.side() ~= "server" then return end -- solo: the authority applies everything itself
    local ok, err = pcall(sendServerCommand, C.MODULE, command, args)
    if not ok then log("ERROR: " .. command .. " not sent: " .. oneLine(err)) end
end

local function reply(player, lines)
    if C.side() ~= "server" or player == nil then return end
    local out = {}
    for i, line in ipairs(lines) do
        if i > S.MAX_REPLY_LINES then
            out[#out + 1] = "[LKE] ... " .. (#lines - S.MAX_REPLY_LINES) .. " more line(s) in the server log"
            break
        end
        if string.len(line) > S.MAX_LINE_LEN then line = string.sub(line, 1, S.MAX_LINE_LEN - 3) .. "..." end
        out[#out + 1] = line
    end
    local ok, err = pcall(sendServerCommand, player, C.MODULE, "log", { lines = out })
    if not ok then print("[LKE] ERROR: reply not sent: " .. oneLine(err)) end
end

function S.snapshot()
    local entries = {}
    for _, id in ipairs(S.order) do
        local e = S.entries[id]
        entries[id] = { kind = e.kind, onlineId = e.onlineId, settings = e.settings, walk = e.walk }
    end
    return { entries = entries }
end

function S.sync()
    broadcast("snapshot", S.snapshot())
end

-- ---------------------------------------------------------------- spawn

local function spawnSquare(player, kind, dx, dy)
    if player == nil then return nil, "no player" end
    local off = S.OFFSETS[kind]
    local x = math.floor(player:getX()) + (type(dx) == "number" and math.floor(dx) or off[1])
    local y = math.floor(player:getY()) + (type(dy) == "number" and math.floor(dy) or off[2])
    local z = math.floor(player:getZ())
    local sq = getCell():getGridSquare(x, y, z)
    if sq == nil then return nil, "square " .. x .. "," .. y .. "," .. z .. " is not loaded" end
    return sq
end

local function newZombie(sq)
    local list = addZombiesInOutfit(sq:getX(), sq:getY(), sq:getZ(), 1, C.OUTFIT, C.FEMALE_CHANCE)
    if list == nil or list:size() == 0 then return nil end
    return list:get(0)
end

local function removeZombie(z)
    local onlineId = get(z, "getOnlineID")
    if get(z, "isReanimatedPlayer") then z:setHealth(0) end
    z:removeFromWorld()
    z:removeFromSquare()
    C.forget(z)
    return onlineId
end

-- Kind B on the square: returns zombie, body (body only when the reanimation failed), temporary online id.
local function spawnB(sq, id, preset)
    local tmp = newZombie(sq)
    if tmp == nil then return nil, nil, nil, "addZombiesInOutfit created no zombie" end
    local tmpOnline = get(tmp, "getOnlineID")
    tmp:getModData()[C.MOD_KEY] = id
    if preset == "clean" then C.applySkin(tmp, "human") end
    tmp:DoZombieInventory()
    local body = sq:createCorpse(tmp)
    if body == nil then
        removeZombie(tmp)
        return nil, nil, tmpOnline, "createCorpse returned nil"
    end
    local z = body:reanimate()
    if z == nil then return nil, body, tmpOnline, "reanimate returned nil (corpse kept, removed by clear)" end
    return z, nil, tmpOnline
end

function S.spawn(player, kind, preset, dx, dy)
    if kind ~= "A" and kind ~= "B" then return nil, "kind must be \"A\" or \"B\", got " .. tostring(kind) end
    if preset ~= nil and preset ~= "clean" then return nil, "preset must be nil or \"clean\", got " .. tostring(preset) end
    if not C.isAuthority() then return nil, "spawn needs the authority (server or solo)" end
    local sq, why = spawnSquare(player, kind, dx, dy)
    if sq == nil then return nil, why end
    S.seq = S.seq + 1
    local id = "LKE-" .. S.seq
    local entry = { id = id, kind = kind, preset = preset, settings = {}, walkSeq = 0 }
    local z, body, tmpOnline, err
    if kind == "A" then
        z = newZombie(sq)
        if z == nil then err = "addZombiesInOutfit created no zombie" else z:getModData()[C.MOD_KEY] = id end
        if preset == "clean" then entry.settings.skin = "human" end
    else
        z, body, tmpOnline, err = spawnB(sq, id, preset)
        if tmpOnline ~= nil and tmpOnline >= 0 then broadcast("removed", { onlineIds = { tmpOnline } }) end
    end
    if z == nil and body == nil then return nil, err end
    entry.zombie, entry.body = z, body
    entry.x, entry.y, entry.z = sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ()
    if z ~= nil then
        entry.outfitId = get(z, "getPersistentOutfitID")
        entry.onlineId = get(z, "getOnlineID")
        entry.x, entry.y, entry.z = get(z, "getX"), get(z, "getY"), get(z, "getZ")
        C.applyLocal(z, entry.settings, id)
    end
    addEntry(entry)
    log("spawned " .. id .. " kind " .. kind .. (preset and (" preset " .. preset) or "") .. " at "
        .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ() .. " (" .. C.side() .. ")"
        .. (kind == "B" and (" temporary zombie onlineId=" .. tostring(tmpOnline)) or "") .. ": " .. C.describe(z))
    if err then log("WARNING: " .. id .. ": " .. err) end
    S.sync()
    return entry
end

-- ---------------------------------------------------------------- settings and walk

function S.set(id, option, value)
    local entry = S.entry(id)
    if not entry then return false, "unknown trial id " .. tostring(id) end
    local v, why = C.parseOption(option, value)
    if v == nil then return false, why end
    entry.settings[option] = v
    local z = S.refresh(entry)
    log("set " .. entry.id .. " " .. option .. "=" .. tostring(v) .. " (sent to every client)")
    if z ~= nil then C.applyLocal(z, entry.settings, entry.id .. " authority") end
    S.sync()
    return true
end

local function walkHere(entry, z)
    local w = entry.walk
    if w == nil or entry.walkDone == w.seq or not C.simulatedHere(z) then return end
    entry.walkDone = w.seq
    local ok, text = pcall(C.execWalk, z, w)
    if ok then log(entry.id .. ": " .. text) else log("ERROR: " .. entry.id .. " walk failed: " .. oneLine(text)) end
end

function S.walk(id, dx, dy, mode)
    local entry = S.entry(id)
    if not entry then return false, "unknown trial id " .. tostring(id) end
    mode = mode or "plain"
    if not C.WALK_MODES[mode] then return false, "unknown walk mode '" .. tostring(mode)
        .. "' (plain, pathfind, notarget, uselessline)" end
    if type(dx) ~= "number" or type(dy) ~= "number" then return false, "walk expects numbers dx, dy" end
    local z = S.refresh(entry)
    if z == nil then return false, entry.id .. " has no body in the world (" .. tostring(entry.how) .. ")" end
    for k, v in pairs(C.walkSettings(mode)) do entry.settings[k] = v end
    entry.walkSeq = entry.walkSeq + 1
    local sx, sy = get(z, "getX"), get(z, "getY")
    entry.walk = { seq = entry.walkSeq, mode = mode, x = math.floor(sx) + math.floor(dx),
        y = math.floor(sy) + math.floor(dy), z = math.floor(get(z, "getZ")) }
    entry.walkFrom = { x = sx, y = sy, ms = getTimestampMs() }
    log("walk " .. entry.id .. " #" .. entry.walkSeq .. " mode " .. mode .. " from " .. C.round(sx) .. ","
        .. C.round(sy) .. " to " .. entry.walk.x .. "," .. entry.walk.y .. "," .. entry.walk.z
        .. "; simulated by " .. C.ownerName(z))
    C.applyLocal(z, entry.settings, entry.id .. " authority")
    walkHere(entry, z)
    S.sync()
    return true
end

-- ---------------------------------------------------------------- list and clear

function S.list()
    local changed = false
    for _, id in ipairs(S.order) do
        local e = S.entries[id]
        local z, how, count, moved = S.refresh(e)
        changed = changed or moved
        local settings = {}
        for k, v in pairs(e.settings) do settings[#settings + 1] = k .. "=" .. tostring(v) end
        table.sort(settings)
        local walk = ""
        if e.walk and e.walkFrom and z then
            walk = " walk#" .. e.walk.seq .. "=" .. e.walk.mode .. " moved=" .. C.round(C.distance(z, e.walkFrom.x,
                e.walkFrom.y)) .. " toTarget=" .. C.round(C.distance(z, e.walk.x + 0.5, e.walk.y + 0.5)) .. " after "
                .. C.round((getTimestampMs() - e.walkFrom.ms) / 1000) .. " s"
        end
        log(id .. " kind " .. e.kind .. " found=" .. how .. " candidates=" .. count .. " corpses="
            .. #S.taggedCorpses(e) .. " settings={" .. table.concat(settings, ",") .. "}" .. walk .. " "
            .. C.describe(z))
    end
    log(#S.order .. " trial body(ies) (" .. C.side() .. ")")
    if changed then S.sync() end
    return #S.order
end

local function clearEntry(entry, onlineIds)
    local removed = 0
    for _ = 1, 4 do -- the object, then duplicates found by tag or outfit
        local z = S.find(entry)
        if z == nil then break end
        local onlineId = removeZombie(z)
        if type(onlineId) == "number" and onlineId >= 0 then onlineIds[#onlineIds + 1] = onlineId end
        removed = removed + 1
        entry.zombie = nil
    end
    local corpses = S.taggedCorpses(entry)
    if entry.body ~= nil then corpses[#corpses + 1] = entry.body end
    for _, body in ipairs(corpses) do
        local sq = get(body, "getSquare")
        if sq ~= nil then
            sq:removeCorpse(body, false)
            removed = removed + 1
        end
    end
    entry.body = nil
    log("cleared " .. entry.id .. ": " .. removed .. " object(s) removed")
    dropEntry(entry.id)
    return removed
end

function S.clear(id)
    local ids = {}
    if id == nil then
        for i, v in ipairs(S.order) do ids[i] = v end
    else
        local entry = S.entry(id)
        if not entry then
            log("clear: unknown trial id " .. tostring(id))
            return 0
        end
        ids[1] = entry.id
    end
    local onlineIds, removed = {}, 0
    for _, eid in ipairs(ids) do
        local ok, n = pcall(clearEntry, S.entries[eid], onlineIds)
        if ok then removed = removed + n else log("ERROR: clear " .. eid .. ": " .. oneLine(n)) end
    end
    if #onlineIds > 0 then broadcast("removed", { onlineIds = onlineIds }) end
    S.sync()
    return removed
end

-- ---------------------------------------------------------------- requests

function S.guard(player)
    if C.side() == "server" then
        if RST.Server == nil or not RST.Server.allowed(player) then
            return false, "permission denied: capability DebugConsole (admin) required"
        end
    elseif type(isDebugEnabled) ~= "function" or not isDebugEnabled() then
        return false, "debug mode is off (start the game with -debug)"
    end
    return RST.worldGuard()
end

local function dispatch(player, args)
    local op = args.op
    if op == "spawn" then
        local entry, why = S.spawn(player, args.kind, args.preset, args.dx, args.dy)
        if not entry then log("spawn refused: " .. tostring(why)) end
        return entry ~= nil
    elseif op == "set" then
        local ok, why = S.set(args.id, args.option, args.value)
        if not ok then log("set refused: " .. tostring(why)) end
        return ok
    elseif op == "walk" then
        local ok, why = S.walk(args.id, args.dx, args.dy, args.mode)
        if not ok then log("walk refused: " .. tostring(why)) end
        return ok
    elseif op == "list" then
        S.list()
        return true
    elseif op == "clear" then
        S.clear(args.id)
        return true
    elseif op == "walked" then
        log(tostring(args.id) .. ": client " .. tostring(get(player, "getUsername")) .. " reports: "
            .. tostring(args.text))
        return true
    end
    log("unknown request '" .. tostring(op) .. "'")
    return false
end

-- Handles one console request (MP server: from OnClientCommand; solo: called by the console directly).
function S.handle(player, args)
    if not C.isAuthority() then return false, {} end
    args = type(args) == "table" and args or {}
    local allowed, why = S.guard(player)
    if not allowed then
        local line = log("request " .. tostring(args.op) .. " from " .. tostring(get(player, "getUsername"))
            .. " refused: " .. tostring(why))
        return false, { line }
    end
    local lines, ok = C.capture(dispatch, player, args)
    return ok and true or false, lines
end

function S.onClientCommand(module, command, player, args)
    if module ~= C.MODULE or command ~= "cmd" then return end
    local _, lines = S.handle(player, args)
    reply(player, lines)
end

-- ---------------------------------------------------------------- tick (authority)

S.ticks = S.ticks or 0

function S.tick()
    if not C.isAuthority() or #S.order == 0 then return end
    S.ticks = S.ticks + 1
    local refresh = S.ticks >= S.REFRESH_TICKS
    if refresh then S.ticks = 0 end
    local changed = false
    for _, id in ipairs(S.order) do
        local e = S.entries[id]
        local z = e.zombie
        if refresh then
            local found, _, _, moved = S.refresh(e)
            z = found
            changed = changed or moved
        end
        if z ~= nil and not C.isDead(z) then
            C.applyLocal(z, e.settings, e.id .. " authority")
            walkHere(e, z)
        end
    end
    if changed then S.sync() end
end

if not S._subscribed and type(Events) == "table" then
    if type(Events.OnClientCommand) == "table" then
        Events.OnClientCommand.Add(function(module, command, player, args)
            LKE.Server.onClientCommand(module, command, player, args)
        end)
    end
    -- Dedicated server: OnTickEvenPaused (the RST rule); solo: OnTick (stops while paused).
    local tickEvent = (type(isServer) == "function" and isServer()) and Events.OnTickEvenPaused or Events.OnTick
    if type(tickEvent) == "table" then
        tickEvent.Add(function() LKE.Server.tick() end)
    end
    S._subscribed = true
end

return S
