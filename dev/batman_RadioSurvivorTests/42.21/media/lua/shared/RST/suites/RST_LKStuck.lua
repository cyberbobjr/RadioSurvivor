--[[
lk.stuck - blocked Living Knox npc (LK04-T05, shared/LivingKnox/LK_Movement.lua): no progress toward the step,
new path request, unblocking point, then failure "stuck" reported to the authority, target avoided by the same npc.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
on open ground (an empty outdoor area of 10 x 7 squares within 20 squares, no building, wall, fence or plant), the
Living Knox option Enabled on. Solo: RST.run({ suite = "lk.stuck", tags = "world" }); dedicated server:
RST.server({ suite = "lk.stuck", tags = "world" }) from an admin client standing still (the body is then simulated,
and its moves executed, by a client). Asynchronous run only (about 2 minutes; do not pause the game).

The area is searched around the player ("[LKS] open area at ..."); obstacles are vanilla solid tiles (industry_01_48,
property "solid") added with transmitAddObjectToSquare and removed afterwards (t:defer).
    - unreachable target: the target square is walled in by 8 solid tiles; the npc is sent to it from 6 squares
      away: the move fails with the reason "stuck" in less than 30 s (acceptance of LK04-T05), and a new move of
      the same npc to that square is refused ("avoided") while another square is accepted;
    - npc boxed in behind furniture: solid tiles form a U open away from the target around the npc; the npc is sent
      5 squares past it: the move ends (arrived around the U, or failed "stuck") in less than 30 s, and the longest
      stretch without progress stays under 30 s.
Figures are printed as "[LKS] measure ..." lines (time, outcome, reason and detail, unblocking points, path requests).
Every test removes its npc (and its directive, and its stuck memory) and its tiles with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local LIMIT_MS = 30000      -- acceptance of LK04-T05: no npc blocked more than 30 s
local WAIT_MS = 45000
local SPRITE = "industry_01_48"
local AREA_W, AREA_H = 10, 7
local SEARCH = 20

local B, D = K.B, K.D
local measure = K.measurer("[LKS]")

local function M() return LivingKnox and LivingKnox.Movement end

-- True if every square of the rectangle is loaded, walkable, outdoors, without plant, and no edge between two of its
-- squares is blocked (wall, door, window, fence).
local function openRect(cell, ox, oy, lv)
    for x = ox, ox + AREA_W - 1 do
        for y = oy, oy + AREA_H - 1 do
            local sq = cell:getGridSquare(x, y, lv)
            if sq == nil or not sq:isFree(false) or sq:getRoom() ~= nil or sq:hasFarmingPlant() then return false end
            if x > ox then
                local w = cell:getGridSquare(x - 1, y, lv)
                if M().edgeBlocked(w, sq) then return false end
            end
            if y > oy then
                local n = cell:getGridSquare(x, y - 1, lv)
                if M().edgeBlocked(n, sq) then return false end
            end
        end
    end
    return true
end

-- Open area near the player (rings of origins, fixed order), or nil.
local function openArea(t)
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local cell = getCell()
    local px, py, lv = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for r = 2, SEARCH do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local ox, oy = px + dx, py + dy
                    -- the player must not stand in the area (he would block a square)
                    local inside = px >= ox and px < ox + AREA_W and py >= oy and py < oy + AREA_H
                    if not inside and openRect(cell, ox, oy, lv) then
                        print("[LKS] open area at " .. ox .. "," .. oy .. "," .. lv .. " (" .. AREA_W .. " x " .. AREA_H
                            .. ")")
                        return { x = ox, y = oy, z = lv }
                    end
                end
            end
        end
    end
    return nil
end

-- Solid vanilla tile on (x, y, z), removed afterwards. Returns false if the square stays walkable.
local function solid(t, x, y, z)
    local sq = getCell():getGridSquare(x, y, z)
    local o = IsoObject.new(getCell(), sq, SPRITE)
    sq:transmitAddObjectToSquare(o, -1)
    t:defer(function()
        if o:getSquare() ~= nil and o:getObjectIndex() ~= -1 then
            if isServer() then sq:transmitRemoveItemFromSquare(o) else sq:RemoveTileObject(o) end
        end
    end, "remove the tile on " .. x .. "," .. y)
    return not sq:isFree(false)
end

local function tiles(t, list, z)
    for _, c in ipairs(list) do
        if not solid(t, c[1], c[2], z) then
            t:skip("tile " .. SPRITE .. " on " .. c[1] .. "," .. c[2] .. " left the square walkable")
        end
    end
end

local function spawnAt(t, x, y, z)
    t:ok(B() ~= nil and D() ~= nil and M() ~= nil, "LivingKnox.Bodies, Directives or Movement is not loaded here")
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function()
            M().forgetStuck(id)
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id
end

-- Move of npc id to (x, y, z) followed until closed: then(t, info) with info.state, why, wd, ms, still (longest
-- stretch without getting 0.5 square closer, as seen by the authority).
local function follow(t, id, x, y, z, what, after)
    local v, why = D().moveTo(id, x, y, z, "walk")
    t:ok(v ~= nil, what .. ": move refused: " .. tostring(why))
    local info = { start = getTimestampMs(), still = 0 }
    local best, bestMs = nil, info.start
    local m0 = M().stats
    local base = { unblocks = m0.unblocks or 0, repaths = m0.repaths or 0 }
    t:waitUntil(function()
        local tnow = getTimestampMs()
        local body = B().find(id)
        if body ~= nil then
            local d = D().distToTarget({ x = x, y = y, z = z }, body:getX(), body:getY(), body:getZ())
            if d ~= nil and (best == nil or d <= best - 0.5) then
                best, bestMs = d, tnow
            end
            if tnow - bestMs > info.still then info.still = tnow - bestMs end
        end
        local e = D().get(id)
        return e ~= nil and (e.v ~= v or e.done == true)
    end, WAIT_MS, function(t2)
        local e = D().get(id)
        info.state, info.why, info.wd = e and e.s, e and e.why, e and e.wd
        info.ms = getTimestampMs() - info.start
        local st = M().stats   -- solo: the executor runs here; on a server these counters stay at 0 (client side)
        measure(string.format("%s: %s in %d ms, reason %s (%s), longest still %d ms, unblocking points %d, new path "
            .. "requests %d", what, tostring(info.state), info.ms, tostring(info.why), tostring(info.wd), info.still,
            (st.unblocks or 0) - base.unblocks, (st.repaths or 0) - base.repaths))
        t2:ok(e ~= nil and e.v == v, what .. ": move #" .. tostring(v) .. " replaced")
        after(t2, info, v)
    end, what .. ": move not closed within " .. WAIT_MS .. " ms")
end

RST.suite("lk.stuck", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 }, function(suite)
    suite.test("unreachable target: failed as stuck within 30 s, then avoided", function(t)
        local a = openArea(t)
        if a == nil then t:skip("no open area of " .. AREA_W .. " x " .. AREA_H .. " within " .. SEARCH .. " squares") end
        local cy = a.y + 3
        local sx, tx = a.x + 1, a.x + 7
        local ring = {}
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then ring[#ring + 1] = { tx + dx, cy + dy } end
            end
        end
        tiles(t, ring, a.z)
        local id = spawnAt(t, sx, cy, a.z)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            if math.floor(z:getX()) ~= sx or math.floor(z:getY()) ~= cy then
                t2:skip("body spawned off its square at " .. z:getX() .. "," .. z:getY())
            end
            follow(t2, id, tx, cy, a.z, "unreachable target", function(t3, info)
                t3:eq("failed", info.state, "directive state")
                t3:eq("stuck", info.why, "reason of the failure")
                t3:ok(info.ms < LIMIT_MS, "failed after " .. info.ms .. " ms (limit " .. LIMIT_MS .. ")")
                local v, why = D().moveTo(id, tx, cy, a.z, "walk")
                t3:ok(v == nil and string.find(tostring(why), "avoided", 1, true) ~= nil,
                    "same target accepted again: " .. tostring(v) .. " " .. tostring(why))
                local v2, why2 = D().moveTo(id, sx + 1, cy - 2, a.z, "walk")
                t3:ok(v2 ~= nil, "other target refused: " .. tostring(why2))
                D().stop(id)
            end)
        end, "npc still on the floor")
    end)

    suite.test("npc boxed in behind furniture: never blocked more than 30 s", function(t)
        local a = openArea(t)
        if a == nil then t:skip("no open area of " .. AREA_W .. " x " .. AREA_H .. " within " .. SEARCH .. " squares") end
        local cy = a.y + 3
        local sx, tx = a.x + 3, a.x + 8
        tiles(t, { { sx + 1, cy - 1 }, { sx + 1, cy }, { sx + 1, cy + 1 }, { sx, cy - 1 }, { sx, cy + 1 } }, a.z)
        local id = spawnAt(t, sx, cy, a.z)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            if math.floor(z:getX()) ~= sx or math.floor(z:getY()) ~= cy then
                t2:skip("body spawned off its square at " .. z:getX() .. "," .. z:getY())
            end
            follow(t2, id, tx, cy, a.z, "boxed in", function(t3, info)
                t3:ok(info.state == "arrived" or (info.state == "failed" and info.why == "stuck"),
                    "directive state " .. tostring(info.state) .. " (" .. tostring(info.why) .. ")")
                t3:ok(info.ms < LIMIT_MS, "closed after " .. info.ms .. " ms (limit " .. LIMIT_MS .. ")")
                t3:ok(info.still < LIMIT_MS, "still for " .. info.still .. " ms")
            end)
        end, "npc still on the floor")
    end)
end)
