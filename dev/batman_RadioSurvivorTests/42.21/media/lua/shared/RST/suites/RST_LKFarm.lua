--[[
lk.farm - Living Knox bodies near farming plants and campfires (LK04-T06). Tags "world" and "server": the authority
only (the vanilla systems SFarmingSystem and SCampfireSystem exist on the server and in solo only), on a save named
rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on, outdoors on open ground.
Solo: RST.run({ suite = "lk.farm", tags = "world" }); dedicated server: RST.server({ suite = "lk.farm",
tags = "world" }) from an admin client standing still. Asynchronous run only (about 7 minutes; do not pause the game).

The engine destroys a farming plant on the square of a zombie (about 1 in 100 per update, IsoZombie.java:2837-2841)
and puts out a lit campfire under a walking zombie (about 1 in 10000 per update, IsoZombie.java:2843-2847). What is
checked here:
    - "move" onto a seeded plant: the target is shifted away (no plant within 2 squares), the body arrives there
      and the plant is still alive (state not "destroyed") 60 s later;
    - "move" onto a lit campfire: same, the campfire still exists and is still lit 60 s later;
    - body at rest with a plant put next to it: within a few seconds a short "move" takes it away (no plant on its
      square or next to it), the plant still alive 60 s later;
    - measure only (never fails on the result): a trip whose straight line crosses a plant; whether the vanilla path
      crossed it and the plant survived is printed (residual risk documented in docs/conception/consignes.md);
      since LK05-T12 the authority splits such a trip into waypoints, the measure shows their effect;
    - waypoints (LK05-T12): a trip to the other side of a garden row (5 plants aligned across the straight line) is
      split into steps around it; the body arrives, is never seen on a plant square, and every plant is alive at
      the arrival. Steps and plant states are printed. Since LK05-T13 the row is put on a clear site searched around
      the body (E, W, N, S, several distances; "[LKF] garden row placed at ..."), SKIP when there is none.
Figures are printed as "[LKF] measure ..." lines. Every test removes its npc (and its directive), plant and campfire
with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local ARRIVE_MS = 40000
local AWAY_MS = 15000       -- body at rest next to a plant: hazard pass every second, retry every 10 s
local SURVIVE_MS = 60000
local SEED = "Carrots"

local B, D = K.B, K.D
local measure = K.measurer("[LKF]")

local function farming() return SFarmingSystem and SFarmingSystem.instance end
local function campfires() return SCampfireSystem and SCampfireSystem.instance end

local function spawnNpc(t, dx, dy)
    t:ok(B() ~= nil and D() ~= nil, "LivingKnox.Bodies or Directives is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function()
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id
end

-- Walkable square without plant or campfire on it or next to it, near (x + dx, y + dy), or nil.
local function freeNear(z, dx, dy)
    return B().safeSquare(math.floor(z:getX()) + dx, math.floor(z:getY()) + dy, math.floor(z:getZ()), 2, 1)
end

-- Seeded plant on sq (vanilla SFarmingSystem:plow then SPlantGlobalObject:seed), removed by t:defer. Returns x, y, z.
local function plantOn(t, sq)
    local sys = farming()
    t:ok(sys ~= nil, "SFarmingSystem is not loaded on this side (authority only)")
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    t:ok(sys:getLuaObjectAt(x, y, z) == nil, "square " .. x .. "," .. y .. " is already farmed")
    t:defer(function()
        local q = sys:getLuaObjectAt(x, y, z)
        if q ~= nil then sys:removePlant(q) end
    end, "remove the plant")
    sys:plow(sq)
    local p = sys:getLuaObjectAt(x, y, z)
    t:ok(p ~= nil, "plow created no plant")
    p:seed(SEED, 0)
    t:ok(sq:hasFarmingPlant(), "hasFarmingPlant false on the seeded square")
    return x, y, z
end

local function plantAlive(x, y, z)
    local q = farming():getLuaObjectAt(x, y, z)
    return q ~= nil and q.state ~= "destroyed", q and q.state
end

-- Lit campfire on sq (vanilla SCampfireSystem:addCampfire, addFuel, lightFire), removed by t:defer.
local function campfireOn(t, sq)
    local sys = campfires()
    t:ok(sys ~= nil, "SCampfireSystem is not loaded on this side (authority only)")
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    t:defer(function()
        local c = sys:getLuaObjectAt(x, y, z)
        if c ~= nil then sys:removeCampfire(c) end
    end, "remove the campfire")
    local c = sys:addCampfire(sq)
    t:ok(c ~= nil, "addCampfire created nothing on " .. x .. "," .. y)
    c:addFuel(120)
    c:lightFire()
    t:ok(sq:hasLitCampfire(), "hasLitCampfire false on the lit campfire")
    return x, y, z
end

local function done(id)
    return function()
        local e = D().get(id)
        return e ~= nil and e.done == true
    end
end

local function cheb(ax, ay, bx, by)
    return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- "move" onto the hazard square (hx, hy): shifted target, arrival away from it, hazard intact after SURVIVE_MS.
local function moveOnto(t2, id, hx, hy, hz, what, intact)
    local v, why = D().moveTo(id, hx, hy, hz, "walk")
    t2:ok(v ~= nil, "move refused: " .. tostring(why))
    local e = D().get(id)
    measure(what .. ": target " .. hx .. "," .. hy .. " shifted to " .. e.x .. "," .. e.y)
    t2:ok(cheb(e.x, e.y, hx, hy) >= 3, "target " .. e.x .. "," .. e.y .. " too close to the " .. what)
    t2:waitUntil(done(id), ARRIVE_MS, function(t3)
        local e3 = D().get(id)
        local z = B().find(id)
        t3:ok(z ~= nil, "npc body lost")
        t3:eq("arrived", e3 and e3.s, "directive state")
        local bx, by = math.floor(z:getX()), math.floor(z:getY())
        t3:ok(B().hazardNear(bx, by, hz, 1) == nil, "body stopped at " .. bx .. "," .. by .. " next to the " .. what)
        t3:sleep(SURVIVE_MS, function(t4)
            local ok, state = intact()
            measure(what .. ": intact after " .. SURVIVE_MS .. " ms: " .. tostring(ok) .. " (" .. tostring(state)
                .. "), executed by " .. tostring(e3 and e3.by))
            t4:ok(ok, what .. " not intact after " .. SURVIVE_MS .. " ms: " .. tostring(state))
        end)
    end, "move not finished")
end

-- ---------------------------------------------------------------- garden row site (LK05-T13)
-- The garden row test needs ROW_HALF * 2 + 1 plants across the trip, a target past it and room around it for the
-- detour of Directives.planDetour. The site is searched around the body BEFORE anything is planted, in a fixed order:
-- directions E, W, N, S, then row distances ROW_AT. Predicted from planDetour (LK_Directives.lua): hazard box = the row
-- (a line, LINK keeps it alone if no other hazard is within LINK squares), corners at DETOUR_MARGIN squares of it,
-- shortest path = start -> two corners of one side -> target (single corner paths cross the zone). Required: every
-- square of the area (start to target, corners plus NUDGE) loaded and free of plants and campfires, with no hazard
-- within LINK squares either; walkable (isFree(false)) start, target, row squares, the 4 corners and the squares of
-- both side paths. Returns a site table, or nil and the reason of the last refusal.
local ROW_HALF = 2
local ROW_AT = { 5, 4, 6 }   -- squares between the body and the row, tried in this order
local ROW_PAST = 5           -- squares between the row and the target
local DIRS = { { 1, 0, "E" }, { -1, 0, "W" }, { 0, -1, "N" }, { 0, 1, "S" } }

-- Squares of the segment (ax, ay) -> (bx, by) (centres, quarter of a square steps, as hazardsOnLine).
local function lineSquares(ax, ay, bx, by, out)
    local x0, y0, x1, y1 = ax + 0.5, ay + 0.5, bx + 0.5, by + 0.5
    local len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
    local steps = math.max(1, math.ceil(len * 4))
    for i = 0, steps do
        out[#out + 1] = { math.floor(x0 + (x1 - x0) * i / steps), math.floor(y0 + (y1 - y0) * i / steps) }
    end
end

local function trySite(bx, by, bz, dir, rowAt)
    local cell = getCell()
    local g, nudge, link = D().DETOUR_MARGIN, D().NUDGE, D().LINK
    local dx, dy, px, py = dir[1], dir[2], -dir[2], dir[1]
    local function at(a, p) return bx + dx * a + px * p, by + dy * a + py * p end
    local wide = ROW_HALF + g + nudge
    -- loaded area, no hazard (the row must stay alone in its hazard box)
    for a = -1 - link, rowAt + ROW_PAST + 1 + link do
        for p = -wide - link, wide + link do
            local x, y = at(a, p)
            local sq = cell:getGridSquare(x, y, bz)
            local core = a >= -1 and a <= rowAt + ROW_PAST + 1 and p >= -wide and p <= wide
            if sq == nil and core then return nil, string.format("square %d,%d is not loaded", x, y) end
            if B().hazardOn(sq) ~= nil then
                return nil, string.format("farming plant or campfire at %d,%d", x, y)
            end
        end
    end
    local need = {}
    local tx, ty = at(rowAt + ROW_PAST, 0)
    local row = {}
    for p = -ROW_HALF, ROW_HALF do
        local x, y = at(rowAt, p)
        row[#row + 1] = { x = x, y = y }
        need[#need + 1] = { x, y }
    end
    local corners = {}
    for _, side in ipairs({ -1, 1 }) do
        local c1x, c1y = at(rowAt - g, side * (ROW_HALF + g))
        local c2x, c2y = at(rowAt + g, side * (ROW_HALF + g))
        corners[#corners + 1] = c1x .. "," .. c1y
        corners[#corners + 1] = c2x .. "," .. c2y
        lineSquares(bx, by, c1x, c1y, need)
        lineSquares(c1x, c1y, c2x, c2y, need)
        lineSquares(c2x, c2y, tx, ty, need)
    end
    for _, q in ipairs(need) do
        local sq = cell:getGridSquare(q[1], q[2], bz)
        if sq == nil or not sq:isFree(false) then
            return nil, string.format("square %d,%d is not walkable", q[1], q[2])
        end
    end
    return { dir = dir[3], rowAt = rowAt, row = row, tx = tx, ty = ty, corners = corners }
end

local function gardenSite(bx, by, bz)
    local why = "no direction tried"
    for _, rowAt in ipairs(ROW_AT) do
        for _, dir in ipairs(DIRS) do
            local site, reason = trySite(bx, by, bz, dir, rowAt)
            if site ~= nil then return site end
            why = dir[3] .. " at " .. rowAt .. ": " .. tostring(reason)
        end
    end
    return nil, why
end

RST.LKFarm = RST.LKFarm or {}
RST.LKFarm.gardenSite = gardenSite

RST.suite("lk.farm", { tags = { "world", "server" }, testTimeoutMs = 150000, timeoutMs = 900000 }, function(s)
    s.test("move onto a plant: target shifted, plant intact after 60 s", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local sq = freeNear(B().find(id), 5, 0)
            t2:ok(sq ~= nil, "no free square 5 squares east of the body")
            local x, y, z = plantOn(t2, sq)
            moveOnto(t2, id, x, y, z, "plant", function() return plantAlive(x, y, z) end)
        end, "npc still on the floor")
    end, { timeoutMs = 150000 })

    s.test("move onto a lit campfire: target shifted, campfire lit after 60 s", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local sq = freeNear(B().find(id), 5, 0)
            t2:ok(sq ~= nil, "no free square 5 squares east of the body")
            local x, y, z = campfireOn(t2, sq)
            moveOnto(t2, id, x, y, z, "campfire", function()
                local c = campfires():getLuaObjectAt(x, y, z)
                return c ~= nil and c.isLit == true, c and ("lit " .. tostring(c.isLit)) or "gone"
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 150000 })

    s.test("body at rest next to a plant walks away, plant intact after 60 s", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local bx, by, bz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
            local sq = getCell():getGridSquare(bx + 1, by, bz)
            t2:ok(sq ~= nil and sq:isFree(false), "square east of the body is not walkable")
            local x, y = plantOn(t2, sq)
            local start = getTimestampMs()
            local function away()
                local e = D().get(id)
                return e ~= nil and e.op == "move" and e.done == true
            end
            t2:waitUntil(away, AWAY_MS + ARRIVE_MS, function(t3)
                local e = D().get(id)
                local b = B().find(id)
                t3:ok(b ~= nil, "npc body lost")
                local nx, ny = math.floor(b:getX()), math.floor(b:getY())
                measure("at rest next to a plant: moved from " .. bx .. "," .. by .. " to " .. nx .. "," .. ny
                    .. " (" .. tostring(e and e.s) .. ") in " .. (getTimestampMs() - start) .. " ms")
                t3:eq("arrived", e and e.s, "move away state")
                t3:ok(B().hazardNear(nx, ny, bz, 1) == nil, "body still next to the plant at " .. nx .. "," .. ny)
                t3:sleep(SURVIVE_MS, function(t4)
                    local ok, state = plantAlive(x, y, bz)
                    measure("at rest next to a plant: intact after " .. SURVIVE_MS .. " ms: " .. tostring(ok)
                        .. " (" .. tostring(state) .. ")")
                    t4:ok(ok, "plant not intact: " .. tostring(state))
                end)
            end, "no move away from the plant")
        end, "npc still on the floor")
    end, { timeoutMs = 150000 })

    s.test("measure: trip whose straight line crosses a plant", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local bx, by, bz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
            local sq = getCell():getGridSquare(bx + 3, by, bz)
            local target = freeNear(z, 7, 0)
            t2:ok(sq ~= nil and sq:isFree(false) and target ~= nil, "no room for the trip east of the body")
            local x, y = plantOn(t2, sq)
            local n = D().hazardsOnLine(z:getX(), z:getY(), target:getX() + 0.5, target:getY() + 0.5, bz)
            local v, why = D().moveTo(id, target:getX(), target:getY(), bz, "walk")
            t2:ok(v ~= nil, "move refused: " .. tostring(why))
            local crossed = { on = false }
            local function arrived()
                local b = B().find(id)
                if b ~= nil and math.floor(b:getX()) == x and math.floor(b:getY()) == y then crossed.on = true end
                return done(id)()
            end
            t2:waitUntil(arrived, ARRIVE_MS, function(t3)
                local e = D().get(id)
                local ok, state = plantAlive(x, y, bz)
                measure("trip across a plant: straight line hazards " .. tostring(n) .. ", body seen on the plant "
                    .. tostring(crossed.on) .. ", plant alive " .. tostring(ok) .. " (" .. tostring(state) .. "), "
                    .. tostring(e and e.s) .. " by " .. tostring(e and e.by))
                t3:note("measure only: the vanilla path of a zombie does not avoid plants")
            end, "move not finished")
        end, "npc still on the floor")
    end, { timeoutMs = 120000 })

    s.test("trip across a garden row: waypoints around it, every plant intact", function(t)
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local bx, by, bz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
            local site, noSite = gardenSite(bx, by, bz)
            if site == nil then
                t2:skip("no clear site for a garden row around " .. bx .. "," .. by .. " (last: " .. tostring(noSite)
                    .. ")")
            end
            print("[LKF] garden row placed at " .. site.row[1].x .. "," .. site.row[1].y .. "-" .. site.row[#site.row].x
                .. "," .. site.row[#site.row].y .. " (" .. site.dir .. ", " .. site.rowAt .. " squares from "
                .. bx .. "," .. by .. "), target " .. site.tx .. "," .. site.ty .. ", corners "
                .. table.concat(site.corners, " "))
            local target = getCell():getGridSquare(site.tx, site.ty, bz)
            t2:ok(target ~= nil and target:isFree(false), "target square " .. site.tx .. "," .. site.ty
                .. " is not walkable")
            local row = {}
            for _, q in ipairs(site.row) do
                local sq = getCell():getGridSquare(q.x, q.y, bz)
                t2:ok(sq ~= nil and sq:isFree(false), "garden square " .. q.x .. "," .. q.y .. " is not walkable")
                local px, py = plantOn(t2, sq)
                row[#row + 1] = { x = px, y = py }
            end
            local n = D().hazardsOnLine(z:getX(), z:getY(), target:getX() + 0.5, target:getY() + 0.5, bz)
            local v, why = D().moveTo(id, target:getX(), target:getY(), bz, "walk")
            t2:ok(v ~= nil, "move refused: " .. tostring(why))
            local e = D().get(id)
            local parts = {}
            if e and e.w then
                for i = 1, #e.w do parts[i] = e.w[i].x .. "," .. e.w[i].y end
            end
            measure("garden row: straight line hazards " .. tostring(n) .. ", waypoints " .. table.concat(parts, " ")
                .. " then " .. tostring(e and e.x) .. "," .. tostring(e and e.y))
            t2:ok(e ~= nil and e.w ~= nil and #e.w >= 1, "trip across the garden row not split into steps")
            local seen = { onPlant = 0, inZone = 0, k = 1 }
            local function arrived()
                local b = B().find(id)
                local cur = D().get(id)
                if b ~= nil then
                    local sx, sy = math.floor(b:getX()), math.floor(b:getY())
                    for _, p in ipairs(row) do
                        local d = cheb(sx, sy, p.x, p.y)
                        if d == 0 then seen.onPlant = seen.onPlant + 1 end
                        if d <= 1 then seen.inZone = seen.inZone + 1 end
                    end
                end
                if cur ~= nil and cur.k ~= nil and cur.k ~= seen.k then
                    measure("garden row: step " .. seen.k .. " reached, now step " .. cur.k .. " after "
                        .. (getTimestampMs() - (cur.issued or getTimestampMs())) .. " ms")
                    seen.k = cur.k
                end
                return done(id)()
            end
            t2:waitUntil(arrived, ARRIVE_MS + 30000, function(t3)
                local e3 = D().get(id)
                local alive, states = 0, {}
                for _, p in ipairs(row) do
                    local ok, state = plantAlive(p.x, p.y, bz)
                    if ok then alive = alive + 1 end
                    states[#states + 1] = p.x .. "," .. p.y .. " " .. tostring(state)
                end
                measure("garden row: " .. tostring(e3 and e3.s) .. " by " .. tostring(e3 and e3.by) .. ", ticks on a "
                    .. "plant " .. seen.onPlant .. ", ticks next to a plant " .. seen.inZone .. ", plants alive "
                    .. alive .. "/" .. #row .. " (" .. table.concat(states, "; ") .. ")")
                t3:eq("arrived", e3 and e3.s, "directive state")
                t3:eq(0, seen.onPlant, "ticks with the body on a plant square")
                t3:eq(#row, alive, "plants alive at the arrival")
            end, "move not finished")
        end, "npc still on the floor")
    end, { timeoutMs = 150000 })
end)
