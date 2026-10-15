--[[
lk.senses - perception of Living Knox npcs (LK05-T01): sight, hearing, light. Tags "world" and "server": the
authority reads LivingKnox.Senses.perceived (solo; on a dedicated server the npc body must be simulated by a client
that reports it), on a save named rstest*, with a target player (t.ctx.player) STANDING STILL, the Living Knox
option Enabled on. Solo: RST.run({ suite = "lk.senses", tags = "world" }). Asynchronous run only (about 1 minute).
The suite makes the player visible (invisible and ghost mode restored at the end) and, when no room around him offers
both sites, moves him into a nearby house where it finds one (RST.Places, solo).

What is checked (docs/conception/perception.md):
    - open ground: an npc put 3 to 6 squares from the player, with a clear line of sight (LosUtil.lineClear =
      Clear) and facing the player, reports the player as seen within SEE_MS;
    - behind a wall: an npc put 2 to 8 squares from the player where the line of sight is Blocked (wall or closed
      door) with a margin of one square on both sides (LK05-T17: a site grazing the corner of a wall next to an
      opening is Blocked for the exact squares only), facing the player, does not report the player as seen after
      BLIND_MS (the player stands still: no noise of his own; the line of sight between the squares of the body and
      of the player at the measure must still be Blocked, printed with the measure); then the
      player makes a noise (addSound from the player, radius NOISE_RADIUS, the global of LuaManager.java:9239)
      and the npc reports the player as heard, still not seen, within HEAR_MS.
Figures are printed as "[LKS] measure ..." lines: light level of the player square, time until seen or heard,
awareness, executor pass counters (Senses.stats.last). Every test removes its npc (and its directive) with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

require "RST/RST_Places"

local K = RST.LKHelpers
local B, D = K.B, K.D
local measure = K.measurer("[LKS]")

local STAND_MS = K.STAND_MS
local SEE_MS = 15000
local BLIND_MS = 8000
local HEAR_MS = 10000
local NOISE_RADIUS = 12
local NOISE_EVERY_MS = 1000

local function S() return LivingKnox and LivingKnox.Senses end

-- Squares of the ring at Chebyshev distance r around (cx, cy), in a fixed order.
local function ring(cx, cy, r)
    local out = {}
    for dx = -r, r do
        out[#out + 1] = { cx + dx, cy - r }
        out[#out + 1] = { cx + dx, cy + r }
    end
    for dy = -r + 1, r - 1 do
        out[#out + 1] = { cx - r, cy + dy }
        out[#out + 1] = { cx + r, cy + dy }
    end
    return out
end

-- The square (x, y, z) and its walkable neighbours on the same side of the walls (lineOfSight not Blocked between
-- them): where a body standing on (x, y) may be found a moment later (pushed, stepped aside, square edge).
local function margin(x, y, z)
    local cell = getCell()
    local out = { { x, y } }
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local sq = cell:getGridSquare(x + dx, y + dy, z)
                if sq ~= nil and sq:isFree(false) and S().lineOfSight(x, y, z, x + dx, y + dy, z) ~= "Blocked" then
                    out[#out + 1] = { x + dx, y + dy }
                end
            end
        end
    end
    return out
end

-- Behind a real wall: the line of sight is Blocked from every square of the margin of (x, y) towards every square
-- of the player's margin (same direction as Senses.scan: npc -> target). A site that only grazes the corner of a wall
-- next to an opening is Blocked for the exact pair of squares and Clear one square aside (LK05-T17).
local function blockedAround(x, y, z, side)
    for _, a in ipairs(margin(x, y, z)) do
        for _, b in ipairs(side) do
            if S().lineOfSight(a[1], a[2], z, b[1], b[2], z) ~= "Blocked" then return false end
        end
    end
    return true
end

-- Walkable square near the player p whose line of sight towards p is wanted ("Clear" or "Blocked", the latter with
-- the margin of blockedAround), from rMin to rMax squares, or nil. Same level only.
local function siteFor(p, wanted, rMin, rMax)
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local cell = getCell()
    local side = wanted == "Blocked" and margin(px, py, pz) or nil
    for r = rMin, rMax do
        for _, q in ipairs(ring(px, py, r)) do
            local sq = cell:getGridSquare(q[1], q[2], pz)
            if sq ~= nil and sq:isFree(false) and S().lineOfSight(q[1], q[2], pz, px, py, pz) == wanted
                and (side == nil or blockedAround(q[1], q[2], pz, side)) then
                return sq
            end
        end
    end
    return nil
end

-- Squares of the npc body and of the player now, and the line of sight between them (npc -> player, as in
-- Senses.scan): "npc x,y, player x,y, los R".
local function lineNow(id, p)
    local z = B().find(id)
    if z == nil then return "Blocked", "npc body lost" end
    local nx, ny, nz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local los = S().lineOfSight(nx, ny, nz, px, py, pz)
    return los, "npc " .. nx .. "," .. ny .. ", player " .. px .. "," .. py .. ", los " .. los
end

local function spawnAt(t, sq)
    t:ok(B() ~= nil and D() ~= nil and S() ~= nil, "LivingKnox.Bodies, Directives or Senses is not loaded here")
    local id, body = B().spawn({}, sq:getX(), sq:getY(), sq:getZ())
    if id then
        t:defer(function()
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id
end

-- Directive "face" towards the player p.
local function facePlayer(t, id, p)
    local z = B().find(id)
    t:ok(z ~= nil, "npc body lost")
    local a = math.atan2(p:getY() - z:getY(), p:getX() - z:getX()) * 180 / math.pi
    local v, why = D().face(id, a)
    t:ok(v ~= nil, "face refused: " .. tostring(why))
    return a
end

local function entry(id, p)
    return S().perceivedPlayer(id, p:getUsername())
end

local function lightOf(p)
    local sq = p:getCurrentSquare()
    if sq == nil then return -1 end
    return K.round(sq:getLightLevel(p:getPlayerNum()))
end

local function passInfo()
    local l = S().stats.last or {}
    return "npcs " .. tostring(l.npcs) .. ", targets " .. tostring(l.targets) .. ", los " .. tostring(l.los)
        .. ", zombies " .. tostring(l.zombies)
end

-- Both sites of the suite from the player's square (inside a room): open ground 3 to 6 squares away and a square
-- behind a wall 2 to 8 squares away. Returns the player's square, or nil.
local function sensesSpot(p)
    local sq = p:getCurrentSquare()
    if sq == nil or not sq:isFree(false) then return nil end
    if siteFor(p, "Clear", 3, 6) == nil or siteFor(p, "Blocked", 2, 8) == nil then return nil end
    return sq
end

RST.suite("lk.senses", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 300000 }, function(s)
    s.test("open ground: the npc sees the player", function(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        RST.Places.visible(t, p)   -- an invisible or ghost player is never perceived: visible for the test
        RST.Places.ensure(t, { name = "room with a clear view and a wall", spot = sensesSpot,
            building = function(def) return def:isResidential() end }, function(t) -- luacheck: ignore 432
        local sq = siteFor(p, "Clear", 3, 6)
        if sq == nil then t:skip("no walkable square with a clear line of sight 3 to 6 squares from the player") end
        local id = spawnAt(t, sq)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            local a = facePlayer(t2, id, p)
            local started = getTimestampMs()
            t2:waitUntil(function()
                local e = entry(id, p)
                return e ~= nil and e.s == true
            end, SEE_MS, function(t3)
                local e = entry(id, p)
                measure(string.format("open ground: seen after %d ms at %.1f squares, awareness %s, light %s, "
                    .. "facing %d deg, %s", getTimestampMs() - started, e.d or -1, tostring(e.a), tostring(lightOf(p)),
                    math.floor(a), passInfo()))
                t3:eq(true, e.s, "player seen")
            end, "player not seen in the open")
        end, "npc still on the floor")
        end)
    end)

    s.test("behind a wall: not seen, heard when the player makes noise", function(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        RST.Places.visible(t, p)
        RST.Places.ensure(t, { name = "room with a clear view and a wall", spot = sensesSpot,
            building = function(def) return def:isResidential() end }, function(t) -- luacheck: ignore 432
        local sq = siteFor(p, "Blocked", 2, 8)
        if sq == nil then
            t:skip("no walkable square behind a wall 2 to 8 squares from the player (margin of one square on both "
                .. "sides: stand inside a room, not next to an opening)")
        end
        measure("behind a wall: npc square " .. sq:getX() .. "," .. sq:getY() .. ", player "
            .. math.floor(p:getX()) .. "," .. math.floor(p:getY()))
        local id = spawnAt(t, sq)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            facePlayer(t2, id, p)
            t2:sleep(BLIND_MS, function(t3)
                local all = S().perceived(id)
                t3:ok(all ~= nil, "no perception report received for " .. id)
                local e = entry(id, p)
                local los, where = lineNow(id, p)
                measure(string.format("behind a wall after %d ms: %s, entry %s, seen %s, heard %s, light %s, %s",
                    BLIND_MS, where, tostring(e ~= nil), tostring(e and e.s), tostring(e and e.h),
                    tostring(lightOf(p)), passInfo()))
                t3:ok(los == "Blocked", "line of sight no longer blocked at the measure (" .. where
                    .. "): the npc or the player moved, the player must stand still")
                t3:ok(e == nil or e.s ~= true, "player seen through the wall")
                local started, lastNoise = getTimestampMs(), 0
                t3:waitUntil(function()
                    local t0 = getTimestampMs()
                    if t0 - lastNoise >= NOISE_EVERY_MS then
                        lastNoise = t0
                        addSound(p, math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), NOISE_RADIUS,
                            NOISE_RADIUS)
                    end
                    local h = entry(id, p)
                    return h ~= nil and h.h == true
                end, HEAR_MS, function(t4)
                    local h = entry(id, p)
                    local _, where2 = lineNow(id, p)
                    measure(string.format("behind a wall: heard after %d ms (noise radius %d), seen %s, awareness %s, %s",
                        getTimestampMs() - started, NOISE_RADIUS, tostring(h.s), tostring(h.a), where2))
                    t4:eq(true, h.h, "player heard")
                    t4:ok(h.s ~= true, "player seen through the wall")
                end, "player noise not heard")
            end)
        end, "npc still on the floor")
        end)
    end)
end)
