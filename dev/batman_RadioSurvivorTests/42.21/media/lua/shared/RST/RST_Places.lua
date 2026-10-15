--[[
RST_Places - "find a place and stand there" for the world suites of the development mod (RST.Places). Development mod
only. Load with: require "RST/RST_Places". No side effect at load time (definitions only).

    local Pl = RST.Places
    Pl.ensure(t, spec, suite)   puts the target player on a square where spec.spot(player) finds what the test needs,
                                then runs suite(t, square, info) as the next step (asynchronous run only).
        spec = {
            name     = "house with a fire or a stove"   text of the measure and of the SKIP reason;
            spot     = function(p) -> square or nil     the square to stand on, given the player where he stands now
                                                         (may be his own square); called first at the current place,
                                                         then at each candidate place;
            outdoor  = true                             candidates are open squares around buildings (yards, streets)
                                                         instead of rooms inside buildings;
            building = function(def) -> bool           optional filter of the candidate buildings (metagrid, no load);
            near     = { x = ..., y = ... }             optional: candidates around this point of the map (a known
                                                         decor, e.g. a river shore) instead of the start place;
            radius   = 250, tries = 8                   candidate buildings within radius squares of the player, at
                                                         most tries candidate places teleported to;
        }
        The current place is kept when spec.spot accepts it (the player is not moved; the square given may differ from
        his own, e.g. a free square next to the fire of his house). Otherwise the player is teleported to candidate
        places, nearest buildings first (no basement, no user-defined building; ground floor), the area is left to load
        (the square and the building fully streamed in, at most LOAD_MS; on a server also the squares within
        spec.loadRadius, default LOAD_RADIUS, of the place), and spec.spot is asked again. The first square found is
        where the player is put (centre of the square). A "[RSTP] place ..." line is printed. Cleanup (t:defer,
        registered at the first move): the player goes back to where he stood, and (solo) the cleanup waits until he
        stands there and the squares within Pl.BACK_RADIUS are loaded again (Pl.areaBack, at most Pl.BACK_LOAD_MS).
        No place found: the test is SKIP with spec.name and the number of places tried.
        Candidates come from the metagrid around the place where the player stood when the test started: from the same
        start place (spawn of a test save, spawn house of the MP campaign) the same places are tried in the same order,
        so a suite finds the same decor at each run (deterministic choice, no random draw).
        Dedicated server (SERVER_MOVES, default on since 2026-10-15): the target player and every other online player
        are moved by the same offset (RST.Fixtures "fx.move": the client asks "/teleportto", admin access level), so
        that a second client stays near the place (owner of the bodies, observer of the RST.Steps checks); the first
        move goes through RST.Fixtures.movePlayers, whose cleanup brings every moved player back to its own origin
        (the position guard of the world suites does it too). An MP client never moves: SKIP as before.
    Pl.protect(t, p, invisible) god mode (and invisible to zombies when invisible is true) until the end of the test.
    Pl.visible(t, p)            neither invisible nor in ghost mode until the end of the test (perception tests).
    Pl.inside(sq)               true when sq is inside a building (room or building def) on the ground floor.
    Pl.openAround(sq, r)        true when every square within r of sq is loaded, walkable, outside any building and
                                without stairs.
    Pl.buildingSquares(def, z, fn)
                                calls fn(square) for every loaded square of the rooms of def at level z; stops at the
                                first truthy return and returns it.
    Pl.fireNear(sq, r)          nearest loaded square of the building of sq, same level, within r squares (default 20),
                                carrying an IsoFireplace (fireplace, wood stove, barbecue) or an IsoStove with a "stove"
                                container (oven, not a microwave), and the object; nil otherwise.
    Pl.freeNear(sq, r)          nearest walkable square of the same room as sq within r squares (sq first), or nil.
]]

require "RST/RST"
require "RST/RST_Fixtures"

RST.Places = RST.Places or {}
local Pl = RST.Places

Pl.RADIUS = 250
Pl.TRIES = 8
Pl.LOAD_MS = 8000           -- after a teleport: wait at most this long for the building to be fully streamed in
Pl.SETTLE_MS = 1000         -- at least this long after a teleport (first chunks, square objects)
Pl.WAIT_MS = 30000          -- limit of one wait (never reached: the condition ends at LOAD_MS)
Pl.OUT = 5                  -- outdoor candidates: squares out of the bounding box of a building
Pl.SERVER_MOVES = true      -- dedicated server: players moved by "fx.move" (false: SKIP there, as before 2026-10-15)
Pl.LOAD_RADIUS = 25         -- server: squares around a candidate that must be loaded before spec.spot is asked

local function log(msg) print("[RSTP] " .. tostring(msg)) end

local function solo()
    return not (type(isClient) == "function" and isClient()) and not (type(isServer) == "function" and isServer())
end
Pl.solo = solo

local function onServer()
    return type(isServer) == "function" and isServer() and true or false
end

-- Whether this machine can move the target player: solo, or a dedicated server with SERVER_MOVES.
function Pl.canMove()
    return solo() or (onServer() and Pl.SERVER_MOVES == true)
end

-- Every square at the corners and the centre of the box of radius r around x, y, z is loaded (server).
local function loadedBox(x, y, z, r)
    local cell = getCell()
    if cell == nil then return false end
    for _, d in ipairs({ { 0, 0 }, { -r, -r }, { r, -r }, { -r, r }, { r, r } }) do
        if cell:getGridSquare(x + d[1], y + d[2], z) == nil then return false end
    end
    return true
end

local function placeLocal(p, x, y, z)
    if p.ensureNotInVehicle ~= nil then p:ensureNotInVehicle() end
    p:setX(x)
    p:setY(y)
    p:setZ(z)
    p:setLastX(x)
    p:setLastY(y)
    p:setLastZ(z)
end

-- After a way back (solo): waits until the player stands on his square again and every square of the box of
-- Pl.BACK_RADIUS around it is loaded, at most Pl.BACK_LOAD_MS (then a note, no failure: the next suite says what it
-- misses). Returns nothing; the wait is the last step of the calling cleanup.
Pl.BACK_RADIUS = 10        -- squares around the start place loaded before the next test (npcs spawned 2 to 5 away)
Pl.BACK_LOAD_MS = 15000
function Pl.areaBack(t, p, origin)
    local x, y, z = math.floor(origin.x), math.floor(origin.y), math.floor(origin.z)
    local since = getTimestampMs()
    local function ready()
        local sq = p:getCurrentSquare()
        return sq ~= nil and sq:getX() == x and sq:getY() == y and sq:getZ() == z and loadedBox(x, y, z, Pl.BACK_RADIUS)
    end
    t:waitQuiet(function()
        return ready() or getTimestampMs() - since >= Pl.BACK_LOAD_MS
    end, Pl.BACK_LOAD_MS + 5000, function(t2)
        if ready() then
            log(string.format("area around %d,%d,%d loaded again after %d ms", x, y, z, getTimestampMs() - since))
        else
            t2:note(string.format("area around the start place %d,%d,%d not loaded %d ms after the way back", x, y, z,
                Pl.BACK_LOAD_MS))
        end
    end, "area of the start place not loaded")
end

local function target(t)
    local p = t.ctx and t.ctx.player or nil
    if p == nil and type(getPlayer) == "function" then p = getPlayer() end
    return p
end

-- ---------------------------------------------------------------- predicates

function Pl.inside(sq)
    return sq ~= nil and sq:getZ() == 0 and (sq:getRoom() ~= nil or sq:getBuildingDef() ~= nil)
end

function Pl.openAround(sq, r)
    if sq == nil then return false end
    local cell = getCell()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for dy = -r, r do
        for dx = -r, r do
            local q = cell:getGridSquare(x + dx, y + dy, z)
            if q == nil or not q:isFree(false) or q:getRoom() ~= nil or q:getBuildingDef() ~= nil or q:HasStairs() then
                return false
            end
        end
    end
    return true
end

function Pl.buildingSquares(def, z, fn)
    if def == nil then return nil end
    local cell = getCell()
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        if room:getZ() == z then
            local rects = room:getRects()
            for j = 0, rects:size() - 1 do
                local r = rects:get(j)
                for y = r:getY(), r:getY2() - 1 do
                    for x = r:getX(), r:getX2() - 1 do
                        local sq = cell:getGridSquare(x, y, z)
                        if sq ~= nil then
                            local v = fn(sq)
                            if v then return v end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function fireObject(sq)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoFireplace") then return o end
        if instanceof(o, "IsoStove") then
            local c = o:getContainer()
            if c ~= nil and c:getType() == "stove" then return o end
        end
    end
    return nil
end

function Pl.fireNear(sq, r)
    local def = sq and sq:getBuildingDef()
    if def == nil then return nil end
    local bid = def:getIDString()
    local cell = getCell()
    for d = 0, r or 20 do
        for dy = -d, d do
            for dx = -d, d do
                if math.max(math.abs(dx), math.abs(dy)) == d then
                    local q = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                    local qd = q and q:getBuildingDef()
                    if qd ~= nil and qd:getIDString() == bid then
                        local o = fireObject(q)
                        if o ~= nil then return q, o end
                    end
                end
            end
        end
    end
    return nil
end

function Pl.freeNear(sq, r)
    if sq == nil then return nil end
    local cell = getCell()
    local room = sq:getRoom()
    local best, bestD
    for dy = -r, r do
        for dx = -r, r do
            local q = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if q ~= nil and q:isFree(false) and not q:HasStairs() and q:getRoom() == room then
                local d = dx * dx + dy * dy
                if bestD == nil or d < bestD then best, bestD = q, d end
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------- player state

function Pl.protect(t, p, invisible)
    local wasGod = p:isGodMod()
    p:setGodMod(true)
    t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the player")
    if invisible and p.setInvisible ~= nil then
        local was = p:isInvisible()
        p:setInvisible(true)
        t:defer(function() p:setInvisible(was) end, "restore the visibility of the player")
    end
end

function Pl.visible(t, p)
    local inv, ghost = p:isInvisible(), p:isGhostMode()
    if inv then p:setInvisible(false) end
    if ghost then p:setGhostMode(false) end
    if inv or ghost then
        log("player made visible for the test (invisible " .. tostring(inv) .. ", ghost " .. tostring(ghost) .. ")")
        t:defer(function()
            if inv then p:setInvisible(true) end
            if ghost then p:setGhostMode(true) end
        end, "restore the invisibility / ghost mode of the player")
    end
end

-- ---------------------------------------------------------------- candidates

-- Candidate places (x, y) around (ox, oy): nearest buildings first; per building, the centre of its largest ground
-- floor room (inside), or four squares Pl.OUT out of its bounding box (outdoor).
local function candidates(spec, ox, oy)
    local grid = getWorld():getMetaGrid()
    if grid == nil or grid.getBuildings == nil then return {} end   -- bench doubles without the metagrid list
    local list = grid:getBuildings()
    local radius = spec.radius or Pl.RADIUS
    local near = {}
    for i = 0, list:size() - 1 do
        local def = list:get(i)
        local cx, cy = (def:getX() + def:getX2()) / 2, (def:getY() + def:getY2()) / 2
        local d = math.max(math.abs(cx - ox), math.abs(cy - oy))
        if d <= radius and not def:isUserDefined() and not def:isBasement() and def:getMinLevel() <= 0
            and (spec.building == nil or spec.building(def)) then
            near[#near + 1] = { def = def, d = d }
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    local out = {}
    local tries = spec.tries or Pl.TRIES
    for _, e in ipairs(near) do
        if #out >= tries then break end
        local def = e.def
        if spec.outdoor then
            local mx, my = math.floor((def:getX() + def:getX2()) / 2), math.floor((def:getY() + def:getY2()) / 2)
            for _, c in ipairs({ { def:getX2() + Pl.OUT, my }, { def:getX() - 1 - Pl.OUT, my },
                { mx, def:getY2() + Pl.OUT }, { mx, def:getY() - 1 - Pl.OUT } }) do
                if #out < tries then out[#out + 1] = { x = c[1], y = c[2], def = def } end
            end
        else
            local rooms, best, bestA = def:getRooms(), nil, -1
            for i = 0, rooms:size() - 1 do
                local r = rooms:get(i)
                if r:getZ() == 0 and r:getArea() > bestA then best, bestA = r, r:getArea() end
            end
            local rect = best and best:getRects():size() > 0 and best:getRects():get(0) or nil
            if rect ~= nil then
                out[#out + 1] = { x = math.floor((rect:getX() + rect:getX2()) / 2),
                    y = math.floor((rect:getY() + rect:getY2()) / 2), def = def }
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------- ensure

function Pl.ensure(t, spec, suite)
    local p = target(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local origin = { x = p:getX(), y = p:getY(), z = p:getZ() }
    local server = onServer()
    local registered = false
    local others = {}        -- server: other online players moved with the target { p, dx, dy, z }
    local function backLater()
        if registered or server then return end
        registered = true
        -- Solo: the way back also waits for the area around the start place (Pl.areaBack): campaign solo of
        -- 2026-10-15 (commit 54087fb), player put back by the cleanup and the next suites at once "npc spawn refused:
        -- square ... is not loaded" (11 tests). A cleanup runs even when the test failed or timed out.
        t:defer(function(tt)
            placeLocal(p, origin.x, origin.y, origin.z)
            log("player back at " .. math.floor(origin.x) .. "," .. math.floor(origin.y) .. "," .. math.floor(origin.z))
            return Pl.areaBack(tt, p, origin)
        end, "player back to where he stood")
    end
    -- Server: moves the target to x, y, z and the other online players by the same offset, then nextStep(tc) once the
    -- target stands there. The first move goes through RST.Fixtures.movePlayers (way back of every player registered).
    local function serverMove(tc, x, y, z, nextStep)
        local F = RST.Fixtures
        if not registered then
            registered = true
            if type(getOnlinePlayers) == "function" then
                local all = getOnlinePlayers()
                for i = 0, (all and all:size() or 0) - 1 do
                    local o = all:get(i)
                    if o ~= nil and o ~= p and not o:isDead() then
                        others[#others + 1] = { p = o, dx = o:getX() - origin.x, dy = o:getY() - origin.y, z = o:getZ() }
                    end
                end
            end
            return F.movePlayers(tc, p, x, y, z, function(t2) return nextStep(t2) end)
        end
        sendServerCommand(p, "RST", F.COMMAND, { x = x, y = y, z = z })
        for _, o in ipairs(others) do
            sendServerCommand(o.p, "RST", F.COMMAND, { x = x + o.dx, y = y + o.dy, z = o.z })
        end
        tc:waitQuiet(function()
            local sq = p:getCurrentSquare()
            return math.abs(p:getX() - x) <= F.MOVE_TOLERANCE and math.abs(p:getY() - y) <= F.MOVE_TOLERANCE
                and sq ~= nil and sq:getX() == math.floor(x) and sq:getY() == math.floor(y)
        end, F.MOVE_TIMEOUT_SERVER_MS, nextStep, "player did not reach " .. math.floor(x) .. "," .. math.floor(y))
    end
    local function standOn(tc, sq, how)
        local same = math.floor(p:getX()) == sq:getX() and math.floor(p:getY()) == sq:getY()
            and math.floor(p:getZ()) == sq:getZ()
        log(string.format("place %s: %d,%d,%d (%s, from %d,%d,%d)", spec.name, sq:getX(), sq:getY(), sq:getZ(), how,
            math.floor(origin.x), math.floor(origin.y), math.floor(origin.z)))
        -- At the current place the player is not moved: the suites read the square given (home, spot) or the place
        -- around the player, which spot has just accepted.
        if same or how == "here" then return suite(tc, sq, { moved = how ~= "here" }) end
        if server then
            return serverMove(tc, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), function(t2)
                suite(t2, sq, { moved = true })
            end)
        end
        backLater()
        placeLocal(p, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
        tc:sleep(500, function(t2) suite(t2, sq, { moved = true }) end)
    end
    -- The current square of a player follows setX/setY at his next update only: right after a move (the "player back"
    -- of the previous test runs in the same tick as this one, in-game run of 2026-10-13) getCurrentSquare is still
    -- the old square and spec.spot would accept a place the player has left.
    local function settled()
        local sq = p:getCurrentSquare()
        return sq ~= nil and sq:getX() == math.floor(p:getX()) and sq:getY() == math.floor(p:getY())
            and sq:getZ() == math.floor(p:getZ())
    end
    local list
    local function try(tc, i)
        local c = list[i]
        if c == nil then
            tc:skip("no " .. spec.name .. " found (" .. #list .. " place(s) tried within "
                .. (spec.radius or Pl.RADIUS) .. " squares)")
            return
        end
        local function waitLoaded(t1)
            local since = getTimestampMs()
            t1:waitQuiet(function()
                local elapsed = getTimestampMs() - since
                if elapsed < Pl.SETTLE_MS then return false end
                if getCell():getGridSquare(c.x, c.y, 0) == nil or not settled() then return elapsed >= Pl.LOAD_MS end
                if server and not loadedBox(c.x, c.y, 0, spec.loadRadius or Pl.LOAD_RADIUS) then
                    return elapsed >= Pl.LOAD_MS
                end
                return c.def:isFullyStreamedIn() or elapsed >= Pl.LOAD_MS
            end, Pl.WAIT_MS, function(t2)
                local sq = getCell():getGridSquare(c.x, c.y, 0) and spec.spot(p) or nil
                if sq ~= nil then return standOn(t2, sq, "candidate " .. i .. " of " .. #list) end
                return try(t2, i + 1)
            end, "candidate place " .. i .. " not loaded")
        end
        if server then return serverMove(tc, c.x + 0.5, c.y + 0.5, 0, waitLoaded) end
        backLater()
        placeLocal(p, c.x + 0.5, c.y + 0.5, 0)
        waitLoaded(tc)
    end
    local function start(tc)
        local here = spec.spot(p)
        if here ~= nil then return standOn(tc, here, "here") end
        if not Pl.canMove() then
            tc:skip("no " .. spec.name .. " here, and the suite moves the player in solo or on a dedicated server"
                .. " only: stand in such a place")
        end
        -- spec.near = { x, y } (known decor of the vanilla map, e.g. a river shore): candidates around that point
        -- instead of the start place (same deterministic order).
        local near = type(spec.near) == "table" and spec.near or nil
        list = candidates(spec, near and near.x or origin.x, near and near.y or origin.y)
        try(tc, 1)
    end
    if settled() then return start(t) end
    t:waitQuiet(settled, Pl.LOAD_MS, start, "the current square of the player never followed his position")
end

return Pl
