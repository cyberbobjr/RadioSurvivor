--[[
RST_Fixtures — world fixtures for the in-game tests (RST.Fixtures). Development mod only.
Load with: require "RST/RST_Fixtures". Meant for suites tagged "world" (see the world guard in RST.lua: they only
run on a save whose name starts with "rstest").

Every fixture takes the test object t first and registers its undo step with t:defer (RST.lua): the undo runs after
the test and its after hooks, in reverse order, even when the test failed, raised, timed out or was cancelled. A
failing undo is reported as "cleanup <label>: ..." on the test and does not stop the other undo steps.

    local F = RST.Fixtures
    F.player(t)                          target player: t.ctx.player (set by the launchers: getPlayer() on the
                                         client and in solo, the requester on the server), else getPlayer()
                                         outside a server; nil when there is none.
    F.giveItem(t, player, fullType[, count])
                                         adds count (default 1) new items "Module.Item" to the main inventory and
                                         returns them (Lua list). Undo: removes exactly these items (by id), wherever
                                         they are in the player's inventory (bags included), after taking them off
                                         the hands, the hotbar and the body. An item the test moved off the player
                                         (floor, other container) is left where it is and logged (WARNING).
    F.removeItem(t, player, item)        takes the item off the player (hands, hotbar, body) and out of its
                                         container. Undo: puts the same item object back into its former container
                                         when that container is still on the player, else into the main inventory.
                                         Limits: the item is not equipped, worn or attached again; nothing is done
                                         (logged) when the item is back on the player already or sits in another
                                         container; an item destroyed by the test cannot come back.
    F.movePlayer(t, player, x, y, z[, suite])
                                         moves the player; returns the origin { x, y, z }. With suite, the next
                                         step suite(t, origin) runs once the player is within F.MOVE_TOLERANCE of
                                         the target (t:waitQuiet: not an assertion; at once in solo, where the
                                         move is immediate). Without suite: solo moves at once and the step goes
                                         on; on a server or an MP client the move is a wait that ENDS the phase
                                         when reached (assertions after it in the same step are an ERROR: pass a
                                         suite). Undo: back to the origin (same float coordinates), waiting the
                                         same way in MP. A vehicle is left (not re-entered by the undo).
    F.movePlayers(t, player, x, y, z[, suite])
                                         as movePlayer, and on a server every other online player is moved by the
                                         same offset (each from its own position; undo: each back to its own
                                         origin): for a suite that needs the area of the target player unloaded
                                         while a second client is connected. Elsewhere: movePlayer.
                                         On a server, every move (and its undo) also waits until the squares
                                         within F.LOAD_RADIUS of the target are loaded (F.MOVE_TIMEOUT_SERVER_MS),
                                         so that the next step or suite finds the area loaded again.
    F.waitSquare(t, x, y, z[, ms][, suite])
                                         waits (t:waitUntil, counted as an assertion) until
                                         getCell():getGridSquare(x, y, z) exists, then runs suite(t, square) as
                                         the next step; FAIL "square x,y,z not loaded: condition not met within ms"
                                         at the deadline (default F.SQUARE_TIMEOUT_MS). Needs an asynchronous run.
    F.npcReady() -> true, or false and the refusal reason
                                         whether F.spawnNpc can work on this machine (authority, an NPC provider
                                         active in RS_NPCProvider, and it is Living Knox with its test API).
    F.spawnNpc(t, player[, suite])       a test NPC (no group) appears near the player (F.NPC_OFFSET squares east,
                                         nearest free loaded square) through the public Living Knox API on the
                                         authority (LivingKnox.API.testSpawnNpc,
                                         docs/specifications-techniques/api-living-knox.md); returns its
                                         provider id "lk-<n>" and its body as RS_NPCProvider sees it (nil when not
                                         seen yet). With suite, waits (t:waitQuiet, F.NPC_TIMEOUT_MS) until
                                         RS_NPCProvider.objects()[id] is a body whose RS_NPCProvider.id is id,
                                         then runs suite(t, id, body). Refused (error) outside a world run (save
                                         not rstest*), on an MP client, without an active NPC provider, with a
                                         provider other than Living Knox, or when Living Knox refuses (reason
                                         given). Undo: LivingKnox.API.testRemoveNpc(id) (body removed, NPC
                                         forgotten); a failed removal is a cleanup error.
    F.engagedMission(t, store, npc, members[, opts]) -> mission
                                         an ACTIVE notebook mission requested by the fiche npc (RS_CarnetServer
                                         .ensure of a provider NPC), offered to every character of members
                                         ({ [character] = name }) and accepted by each (RS_Missions.accept);
                                         marked m.rstTest = opts.tag. Undo: mission removed, unless opts.keep.
    F.testMissions(data[, tag]), F.removeTestMission(store, m)
                                         marked missions of the notebook state, removal of one of them.
    player may be nil in every fixture: F.player(t) is used then. Waits follow "Waiting in steps" (RST.lua): one
    wait per step, the rest of the test goes in the continuation function.

Where they run
    Items: on the authority only (solo, or the server in MP); an MP client gets an error. On the server the changes
    are sent to the owner (sendAddItemToContainer / sendRemoveItemFromContainer; both do nothing in solo).
    Moves: solo moves the player like TeleportPacket.processClient (setX/setY/setZ then setLastX/Y/Z). The server
    has no Lua call to teleport a client (GameServer.sendTeleport is not exposed): it sends "RST" "fx.move"
    { x, y, z } to the player, whose client (this file, OnServerCommand) asks the vanilla command
    "/teleportto x,y,z" (needs Capability.TeleportToCoordinates, held by admin; moves player 0 of the connection),
    then waits until the server copy of the player is within F.MOVE_TOLERANCE of the target (F.MOVE_TIMEOUT_MS).
    An MP client uses the same command and wait. Those waits need an asynchronous run (RST.start) and do not count
    as assertions (t:waitQuiet).
    NPC: on the authority only (solo, or the server in MP): LivingKnox.API does not exist on an MP client. The
    module RadioSurvivor/RS_NPCProvider (published mod) is required lazily, under pcall: without it, no provider.
]]

require "RST/RST"

RST.Fixtures = RST.Fixtures or {}
local F = RST.Fixtures

F.MOVE_TIMEOUT_MS = 10000
F.MOVE_TIMEOUT_SERVER_MS = 20000
F.LOAD_RADIUS = 12
F.WAIT_LOADED = true        -- server moves wait for the squares (false: bench doubles without any square)
F.MOVE_TOLERANCE = 1.0
F.SQUARE_TIMEOUT_MS = 10000
F.COMMAND = "fx.move"
F.NPC_TIMEOUT_MS = 10000
F.NPC_OFFSET = 2
F.NPC_PROVIDER = "livingknox"

local function log(msg)
    print("[RST] fixtures: " .. msg)
end

local function isServerSide()
    return type(isServer) == "function" and isServer() and true or false
end

local function isClientSide()
    return type(isClient) == "function" and isClient() and true or false
end

local function checkNumber(what, name, v)
    if type(v) ~= "number" then
        error(what .. ": " .. name .. " must be a number, got " .. type(v), 0)
    end
end

local function itemLabel(item)
    local okType, fullType = pcall(function() return item:getFullType() end)
    local okId, id = pcall(function() return item:getID() end)
    return tostring(okType and fullType or "?") .. "#" .. tostring(okId and id or "?")
end

-- ---------------------------------------------------------------- target

function F.player(t)
    local ctx = t and t.ctx
    if type(ctx) == "table" and ctx.player ~= nil then return ctx.player end
    if not isServerSide() and type(getPlayer) == "function" then
        local ok, p = pcall(getPlayer)
        if ok then return p end
    end
    return nil
end

local function target(t, player, what)
    if type(t) ~= "table" or type(t.defer) ~= "function" then
        error(what .. ": the first argument must be the test object t", 0)
    end
    local p = player or F.player(t)
    if p == nil then
        error(what .. ": no target player (t.ctx.player is missing)", 0)
    end
    return p
end

local function requireAuthority(what)
    if isClientSide() then
        error(what .. ": inventory changes need the authority (solo or server), not an MP client", 0)
    end
end

-- ---------------------------------------------------------------- inventory

local function syncAdd(container, item)
    if isServerSide() then sendAddItemToContainer(container, item) end
end

local function syncRemove(container, item)
    if isServerSide() then sendRemoveItemFromContainer(container, item) end
end

-- Takes the item off the character, then out of its container (vanilla ISTransferAction:removeItemOnCharacter and
-- transferItem). Returns the former container (nil when the item was in none).
local function detach(player, item)
    player:removeAttachedItem(item)
    if player:isEquipped(item) then
        player:removeFromHands(item)
        player:removeWornItem(item, false)
        if type(triggerEvent) == "function" then triggerEvent("OnClothingUpdated", player) end
    end
    local container = item:getContainer()
    if container ~= nil then
        container:Remove(item)
        syncRemove(container, item)
    end
    return container
end

-- Undo of giveItem: removes the given items still on the player (reverse order).
local function takeBack(player, given)
    local inv = player:getInventory()
    local missing = {}
    for i = #given, 1, -1 do
        local g = given[i]
        local item = inv:getItemWithIDRecursiv(g.id)
        if item == nil then
            missing[#missing + 1] = g.fullType .. "#" .. tostring(g.id)
        else
            detach(player, item)
        end
    end
    if #missing > 0 then
        log("WARNING: giveItem cleanup: " .. #missing .. " item(s) no longer on the player, left where they are: "
            .. table.concat(missing, ", "))
    end
end

function F.giveItem(t, player, fullType, count)
    local p = target(t, player, "giveItem")
    requireAuthority("giveItem")
    if type(fullType) ~= "string" or not string.find(fullType, ".", 1, true) then
        error("giveItem: a full type 'Module.Item' is expected, got " .. RST.render(fullType), 0)
    end
    count = count or 1
    if type(count) ~= "number" or count < 1 or math.floor(count) ~= count then
        error("giveItem: count must be a positive integer, got " .. RST.render(count), 0)
    end
    local inv = p:getInventory()
    local given = {}
    -- Registered first: items added before an error are removed too.
    t:defer(function() takeBack(p, given) end, "giveItem " .. fullType .. " x" .. tostring(count))
    local items = {}
    for _ = 1, count do
        local item = inv:AddItem(fullType)
        if item == nil then
            error("giveItem: the game refused '" .. fullType .. "' (unknown or obsolete item)", 0)
        end
        syncAdd(inv, item)
        given[#given + 1] = { id = item:getID(), fullType = fullType }
        items[#items + 1] = item
    end
    return items
end

-- Undo of removeItem: puts the item back (see the header for the limits).
local function putBack(player, item, container)
    local inv = player:getInventory()
    local label = itemLabel(item)
    if inv:getItemWithIDRecursiv(item:getID()) ~= nil then
        log("removeItem cleanup: " .. label .. " is already back on the player; nothing done")
        return
    end
    if item:getContainer() ~= nil then
        log("WARNING: removeItem cleanup: " .. label .. " is now in another container; not taken back")
        return
    end
    local dest = inv
    if container ~= nil and container ~= inv then
        local holder = container:getContainingItem()
        if holder ~= nil and inv:getItemWithIDRecursiv(holder:getID()) ~= nil then
            dest = container
        end
    end
    dest:AddItem(item)
    syncAdd(dest, item)
end

function F.removeItem(t, player, item)
    local p = target(t, player, "removeItem")
    requireAuthority("removeItem")
    if item == nil then error("removeItem: item is nil", 0) end
    local inv = p:getInventory()
    if inv:getItemWithIDRecursiv(item:getID()) == nil then
        error("removeItem: " .. itemLabel(item) .. " is not on the player", 0)
    end
    local container = detach(p, item)
    t:defer(function() putBack(p, item, container) end, "removeItem " .. itemLabel(item))
    return item
end

-- ---------------------------------------------------------------- position

local function coords(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

-- Local move, as TeleportPacket.processClient (vehicle left first).
local function placeLocal(p, x, y, z)
    p:ensureNotInVehicle()
    p:setX(x)
    p:setY(y)
    p:setZ(z)
    p:setLastX(x)
    p:setLastY(y)
    p:setLastZ(z)
end

-- Asks the server to teleport the local player 0 (vanilla admin command, see the header).
function F.requestTeleport(x, y, z)
    SendCommandToServer("/teleportto " .. coords(x, y, z))
end

local function near(p, x, y, z)
    local tol = F.MOVE_TOLERANCE
    return math.abs(p:getX() - x) <= tol and math.abs(p:getY() - y) <= tol and math.abs(p:getZ() - z) < 1
end

-- Whether the server has loaded the squares around x, y, z (centre and the corners at F.LOAD_RADIUS): after a
-- teleport the server copy of the player arrives before its chunks are loaded, and a suite run right after a way back
-- found "square ... is not loaded" (MP campaign of 2026-10-14). Always true outside a server.
local function loadedAround(x, y, z)
    if not isServerSide() or not F.WAIT_LOADED then return true end
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil then return false end
    local r = F.LOAD_RADIUS
    local cx, cy, cz = math.floor(x), math.floor(y), math.floor(z)
    for _, d in ipairs({ { 0, 0 }, { -r, -r }, { r, -r }, { -r, r }, { r, r } }) do
        if cell:getGridSquare(cx + d[1], cy + d[2], cz) == nil then return false end
    end
    return true
end

-- Registers the wait until every moved player is near its target and, on a server, the squares around the first
-- target are loaded (t:waitQuiet: not an assertion of the test); suite (optional) is the next step.
local function waitNear(t, moves, what, suite)
    if not t._async then
        error(what .. ": waiting for the move needs an asynchronous run (RST.start)", 0)
    end
    local first = moves[1]
    t:waitQuiet(function()
        for _, m in ipairs(moves) do
            if not near(m.p, m.x, m.y, m.z) then return false end
            -- Server: the current square of the player follows its position one update later (getCurrentSquare
            -- still the old one, or nil): a suite started right after the way back skipped "the player must stand
            -- inside a house" (MP run of 2026-10-14).
            if isServerSide() and F.WAIT_LOADED then
                local sq = m.p:getCurrentSquare()
                if sq == nil or sq:getX() ~= math.floor(m.x) or sq:getY() ~= math.floor(m.y) then return false end
            end
        end
        return loadedAround(first.x, first.y, first.z)
    end, isServerSide() and F.MOVE_TIMEOUT_SERVER_MS or F.MOVE_TIMEOUT_MS, suite,
        what .. ": player did not reach " .. coords(first.x, first.y, first.z) .. " (or its squares not loaded)")
end

-- Moves the players (moves: list of { p, x, y, z }, see the header); suite(t) is the next step, or nil.
local function place(t, moves, what, suite)
    if isServerSide() then
        for _, m in ipairs(moves) do
            sendServerCommand(m.p, "RST", F.COMMAND, { x = m.x, y = m.y, z = m.z })
        end
        waitNear(t, moves, what, suite)
    elseif isClientSide() then
        local m = moves[1]
        F.requestTeleport(m.x, m.y, m.z)
        waitNear(t, { m }, what, suite)
    else
        for _, m in ipairs(moves) do placeLocal(m.p, m.x, m.y, m.z) end
        if suite then waitNear(t, moves, what, suite) end
    end
end

-- The other online players of a server (none elsewhere: an MP client only moves its own player).
local function otherPlayers(p)
    local out = {}
    if not isServerSide() or type(getOnlinePlayers) ~= "function" then return out end
    local list = getOnlinePlayers()
    if list == nil then return out end
    for i = 0, list:size() - 1 do
        local o = list:get(i)
        if o ~= nil and o ~= p and not o:isDead() then out[#out + 1] = o end
    end
    return out
end

local function move(t, player, x, y, z, suite, all, what)
    local p = target(t, player, what)
    checkNumber(what, "x", x)
    checkNumber(what, "y", y)
    checkNumber(what, "z", z)
    if suite ~= nil and type(suite) ~= "function" then
        error(what .. ": suite must be a function, got " .. type(suite), 0)
    end
    local origin = { x = p:getX(), y = p:getY(), z = p:getZ() }
    local moves = { { p = p, x = x, y = y, z = z } }
    local back = { { p = p, x = origin.x, y = origin.y, z = origin.z } }
    if all then
        for _, o in ipairs(otherPlayers(p)) do
            local ox, oy, oz = o:getX(), o:getY(), o:getZ()
            moves[#moves + 1] = { p = o, x = ox + x - origin.x, y = oy + y - origin.y, z = oz }
            back[#back + 1] = { p = o, x = ox, y = oy, z = oz }
        end
    end
    t:defer(function(tt) place(tt, back, what .. " cleanup") end,
        what .. " back to " .. coords(origin.x, origin.y, origin.z))
    local continuation = nil
    if suite then
        continuation = function(tt) return suite(tt, origin) end
    end
    place(t, moves, what, continuation)
    return origin
end

function F.movePlayer(t, player, x, y, z, suite)
    return move(t, player, x, y, z, suite, false, "movePlayer")
end

function F.movePlayers(t, player, x, y, z, suite)
    return move(t, player, x, y, z, suite, true, "movePlayers")
end

-- ---------------------------------------------------------------- position guard

-- Position guard of the world suites (RST.worldJobGuard, called by RST.lua when an asynchronous job of a "world"
-- suite starts): records where every player stands (server: online players by account; solo: the local player;
-- an MP client: nobody, world suites never run there) and registers, as the FIRST cleanup of the test (so it runs
-- LAST, after the undo steps of the test), the way back of every player found more than F.GUARD_TOLERANCE squares
-- (or a level) away from its recorded place. A suite that leaves a player elsewhere (vehicle seat left outside,
-- move without undo) no longer makes the next suites skip "the player must stand inside a house" (MP campaign of
-- 2026-10-15: rs.worldradio left client 1 next to the test car, 30 lk suites skipped). The way back is noted on
-- the test ("position guard: ...") so the suite at fault stays visible.
F.GUARD_TOLERANCE = 1.5

local function guardPlayers()
    local out = {}
    if isServerSide() then
        if type(getOnlinePlayers) ~= "function" then return out end
        local list = getOnlinePlayers()
        for i = 0, (list and list:size() or 0) - 1 do
            local p = list:get(i)
            if p ~= nil and not (p.isDead ~= nil and p:isDead()) then out[#out + 1] = p end
        end
    elseif not isClientSide() and type(getPlayer) == "function" then
        local ok, p = pcall(getPlayer)
        if ok and p ~= nil and not (p.isDead ~= nil and p:isDead()) then out[1] = p end
    end
    return out
end

-- Seated in a vehicle (the guard brings the player out: the move leaves the vehicle). Test doubles without the
-- method count as not seated.
local function inVehicle(p)
    local ok, v = pcall(function() return p:getVehicle() end)
    return ok and v ~= nil
end

local function guardKey(p)
    local ok, name = pcall(function() return p:getUsername() end)
    return ok and name ~= nil and tostring(name) or "player"
end

function F.guardPositions(t)
    local recorded = {}
    for _, p in ipairs(guardPlayers()) do
        recorded[guardKey(p)] = { x = p:getX(), y = p:getY(), z = p:getZ() }
    end
    t:defer(function(tt)
        local moves = {}
        for _, p in ipairs(guardPlayers()) do
            local r = recorded[guardKey(p)]
            if r ~= nil and (math.abs(p:getX() - r.x) > F.GUARD_TOLERANCE or math.abs(p:getY() - r.y) > F.GUARD_TOLERANCE
                or math.floor(p:getZ()) ~= math.floor(r.z) or inVehicle(p)) then
                tt:note("position guard: player " .. guardKey(p) .. " left at " .. coords(math.floor(p:getX()),
                    math.floor(p:getY()), math.floor(p:getZ())) .. " by the test, moved back to "
                    .. coords(math.floor(r.x), math.floor(r.y), math.floor(r.z)))
                moves[#moves + 1] = { p = p, x = r.x, y = r.y, z = r.z }
            end
        end
        if #moves == 0 then return end
        if not tt._async and (isServerSide() or isClientSide()) then return end
        place(tt, moves, "position guard")
    end, "position guard: players back where the test found them")
end

RST.worldJobGuard = F.guardPositions

-- ---------------------------------------------------------------- squares

function F.waitSquare(t, x, y, z, ms, suite)
    checkNumber("waitSquare", "x", x)
    checkNumber("waitSquare", "y", y)
    checkNumber("waitSquare", "z", z)
    t:waitUntil(function()
        if type(getCell) ~= "function" then return nil end
        local cell = getCell()
        if cell == nil then return nil end
        return cell:getGridSquare(x, y, z)
    end, ms or F.SQUARE_TIMEOUT_MS, suite, "square " .. coords(x, y, z) .. " not loaded")
end

-- ---------------------------------------------------------------- npc (provider)

local function provider()
    local ok, P = pcall(require, "RadioSurvivor/RS_NPCProvider")
    if ok and type(P) == "table" and type(P.active) == "function" then return P end
    return nil
end

local function testApi()
    local API = LivingKnox and LivingKnox.API
    if type(API) == "table" and type(API.testSpawnNpc) == "function" and type(API.testRemoveNpc) == "function" then
        return API
    end
    return nil
end

function F.npcReady()
    if isClientSide() then return false, "needs the authority (solo or server), not an MP client" end
    local P = provider()
    if P == nil then return false, "no NPC provider active (RS_NPCProvider not loaded)" end
    local name = tostring(P.active().name)
    if not P.available() then return false, "no NPC provider active (RS_NPCProvider: " .. name .. ")" end
    if name ~= F.NPC_PROVIDER then
        return false, "the active NPC provider is " .. name .. ", not Living Knox (" .. F.NPC_PROVIDER .. ")"
    end
    if testApi() == nil then return false, "Living Knox test API unavailable (LivingKnox.API.testSpawnNpc)" end
    return true
end

-- Body of the provider NPC id as RS_NPCProvider sees it, or nil.
local function seenBody(P, id)
    local body = P.objects()[id]
    if body ~= nil and P.id(body) == id then return body end
    return nil
end

function F.spawnNpc(t, player, suite)
    local p = target(t, player, "spawnNpc")
    if suite ~= nil and type(suite) ~= "function" then
        error("spawnNpc: suite must be a function, got " .. type(suite), 0)
    end
    if suite ~= nil and not t._async then
        error("spawnNpc: waiting for the provider needs an asynchronous run (RST.start)", 0)
    end
    local allowed, refusal = RST.worldGuard()
    if not allowed then error("spawnNpc: world suites only: " .. tostring(refusal), 0) end
    local ready, why = F.npcReady()
    if not ready then error("spawnNpc: " .. why, 0) end
    local P, API = provider(), testApi()
    local x, y, z = math.floor(p:getX()) + F.NPC_OFFSET, math.floor(p:getY()), math.floor(p:getZ())
    -- The square may not be loaded yet right after a player move (solo cleanup of a former test puts the player
    -- back at once; in-game run of 2026-10-14: "square ... is not loaded"): with a continuation, wait for it first.
    local cell = type(getCell) == "function" and getCell() or nil
    if suite and (cell == nil or cell:getGridSquare(x, y, z) == nil) then
        F.waitSquare(t, x, y, z, nil, function(tt) F.spawnNpc(tt, p, suite) end)
        return nil, nil
    end
    local id, err = API.testSpawnNpc(x, y, z)
    if id == nil then error("spawnNpc: Living Knox refused the NPC at " .. coords(x, y, z) .. ": " .. tostring(err), 0) end
    t:defer(function()
        local removed, reason = API.testRemoveNpc(id)
        if not removed then error("spawnNpc cleanup: npc " .. id .. " not removed: " .. tostring(reason), 0) end
    end, "remove test npc " .. id)
    log("npc " .. id .. " spawned near " .. coords(x, y, z))
    if suite then
        t:waitQuiet(function() return seenBody(P, id) end, F.NPC_TIMEOUT_MS,
            function(tt, body) return suite(tt, id, body) end,
            "spawnNpc: npc " .. id .. " not seen by the NPC provider")
    end
    return id, seenBody(P, id)
end

-- ---------------------------------------------------------------- engaged mission (notebook)

F.TEST_MISSION_FIELD = "rstTest"

-- Missions of the notebook state data marked by F.engagedMission with this tag (any tag when tag is nil): list.
function F.testMissions(data, tag)
    local out = {}
    for _, m in pairs(data and data.missions or {}) do
        local mark = m[F.TEST_MISSION_FIELD]
        if mark ~= nil and (tag == nil or mark == tag) then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

-- Removes a mission made by F.engagedMission (requester fiche freed); true when something was removed.
function F.removeTestMission(store, m)
    if store == nil or type(store.data) ~= "table" or m == nil or store.data.missions[m.id] ~= m then return false end
    store.data.missions[m.id] = nil
    for _, record in pairs(store.data.characters or {}) do
        if record.knownMissions then record.knownMissions[m.id] = nil end
    end
    local npc = store.data.npcs and store.data.npcs[m.npc]
    if npc and npc.mission == m.id then npc.mission, npc.nextOfferAt, npc.nextOfferHour = nil, nil, nil end
    store.dirty = true
    if type(store.save) == "function" then pcall(store.save) end
    return true
end

-- An ACTIVE mission of the notebook requested by the fiche npc (RS_CarnetServer.ensure of a provider NPC) with every
-- character of members ({ [character] = name }) engaged: offer of the default template (deliver, catalogue entry
-- RS_Config.Missions.deliver, no supply terms) invited to all, then accepted by each through RS_Missions.accept, the
-- path of the notebook "accept" command. Marked m.rstTest = tag ("rst" by default). store: RS_CarnetServer.store.
-- Undo (t:defer) unless opts.keep: the mission removed (F.removeTestMission). Authority only.
function F.engagedMission(t, store, npc, members, opts)
    opts = opts or {}
    if isClientSide() then error("engagedMission: the notebook state lives on the authority, not an MP client", 0) end
    t:ok(type(store) == "table" and type(store.data) == "table", "engagedMission: notebook state not ready")
    t:ok(type(npc) == "table" and type(npc.id) == "string", "engagedMission: no npc fiche")
    local M = require "RadioSurvivor/RS_Missions"
    local Config = require "RadioSurvivor/RS_Config"
    local c = Config.Missions and Config.Missions.deliver
    t:ok(type(c) == "table", "engagedMission: no deliver entry in RS_Config.Missions")
    local data = store.data
    if npc.mission ~= nil and data.missions[npc.mission] == nil then npc.mission = nil end
    t:ok(npc.mission == nil, "engagedMission: npc " .. npc.id .. " already requests " .. tostring(npc.mission))
    npc.missionCount = (npc.missionCount or 0) + 1
    local m = { id = npc.id .. "-rst" .. npc.missionCount, npc = npc.id, template = "deliver", offer = c.id,
        titleKey = c.titleKey, state = "offer", revision = 1, durationMs = c.durationMs, remainingMs = c.durationMs,
        offerRemainingMs = Config.OFFER_TTL_MS, participants = {}, invited = {}, rewardType = c.rewardType,
        rewardCount = c.rewardCount, claimedBy = "", receipts = {}, quantity = c.quantity, delivered = 0,
        accepted = {} }
    for k, v in pairs(c.accepted or {}) do m.accepted[k] = v end
    m[F.TEST_MISSION_FIELD] = opts.tag or "rst"
    local ids = {}
    for cid in pairs(members) do ids[#ids + 1] = cid end
    table.sort(ids)
    t:ok(#ids > 0, "engagedMission: no member")
    for _, cid in ipairs(ids) do m.invited[cid] = true end
    data.missions[m.id], npc.mission = m, m.id
    if not opts.keep then
        t:defer(function() F.removeTestMission(store, m) end, "test mission " .. m.id .. " removed")
    end
    for _, cid in ipairs(ids) do
        t:ok(M.accept(data, m, cid, tostring(members[cid])), "engagedMission: " .. cid .. " could not accept " .. m.id)
        local record = data.characters[cid]
        if record and record.knownMissions then record.knownMissions[m.id] = true end
    end
    t:eq("active", m.state, "engagedMission: state of " .. m.id)
    store.dirty = true
    if type(store.save) == "function" then pcall(store.save) end
    log("mission " .. m.id .. " engaged by " .. table.concat(ids, ", "))
    return m
end

-- ---------------------------------------------------------------- client side of a server move

-- OnServerCommand handler ("RST", "fx.move"): the server asks this client to teleport its player (debug only).
function F.onServerCommand(module, command, args)
    if module ~= "RST" or command ~= F.COMMAND then return end
    if type(isDebugEnabled) ~= "function" or not isDebugEnabled() then
        log("move request ignored: debug mode is off")
        return
    end
    if type(args) ~= "table" or type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number" then
        log("move request ignored: bad coordinates")
        return
    end
    F.requestTeleport(args.x, args.y, args.z)
end

-- One subscription per Lua state (survives a reload: the dispatcher reads F.onServerCommand).
if not F._subscribed and type(Events) == "table" and type(Events.OnServerCommand) == "table" then
    Events.OnServerCommand.Add(function(module, command, args)
        RST.Fixtures.onServerCommand(module, command, args)
    end)
    F._subscribed = true
end

return F
