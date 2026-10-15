--[[
lk.essai - automatable measures of the body trial LK02-T10 (A = ordinary zombie, B = reanimated player).
Tags "world" and "server": the authority only, on a save named rstest* (world guard, RST.lua), with a target
player (t.ctx.player). Solo: RST.run({ suite = "lk.essai", tags = "world" }) or RST.server({ suite = "lk.essai",
tags = "world" }); dedicated server: RST.server({ suite = "lk.essai", tags = "world" }) from an admin client.
Asynchronous run only (waits in steps). About 6 minutes; do not pause the game.

Each test asserts the hypothesis of docs/conception/corps-et-animations.md: a FAIL is a measure that refutes it,
not a broken test. Figures are logged as "[LKE] measure ..." lines (console and lke-essai.log of the authority).
Visual measures (appearance on two clients, voices, hand item) stay in the manual protocol.
Every test removes its bodies with t:defer (LKE.Server.clear), even when it fails.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKEssai"
require "RST/RST_Places"

local C = LKE.Core
local MODES = { "plain", "pathfind", "notarget" }
local STAND_MS = 20000      -- a reanimated corpse lies on the floor first (IsoDeadBody.reanimate: setOnFloor)
local WALK_MS = 8000
local WALK_MIN = 1.5        -- squares moved in WALK_MS to count as "walks"
local STILL_MAX = 0.5       -- squares moved in WALK_MS to count as "stays"
local CONTACT_MS = 60000
local FAR = 300             -- squares: beyond the loaded area (13 to 19 chunks of 8 squares)
-- Dedicated server (campaign MP 2026-10-15): the walk is executed by the owning client and read here on the server
-- copy, which only follows the owner's zombie packets (every 4 s); a reanimated corpse lies longer on the floor (the
-- client forces the floor state of a reanimated corpse, NetworkZombieSimulator; the trial body has no LK_Stand).
local STAND_MS_MP = 60000
local COPY_SYNC_MS = 5000
-- Base A (ordinary zombie) was abandoned on 2026-10-09 (docs/plan/LK02, base B retained): its walk measures stay a
-- solo trial. On a dedicated server they cannot refute anything: the copy read here is late, so a still body passes
-- the "useless" measure and a walking one fails the others (2026-10-15: moved 0 / 0.03 squares).
local A_SOLO_ONLY = "base A abandoned on 2026-10-09 (LK02, base B retained): its walk trial is solo only (on a "
    .. "dedicated server the copy of the client executor read here is late)"

local function dedicated()
    return isServer() and not (RST.Steps ~= nil and RST.Steps.isSolo ~= nil and RST.Steps.isSolo())
end

local function S() return LKE.Server end

local function measure(text)
    C.log("measure " .. text)
end

local function spawn(t, kind, preset, dx, dy)
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    t:ok(S() ~= nil, "RST_LKEssaiServer.lua is not loaded on this side")
    local entry, why = S().spawn(p, kind, preset, dx, dy)
    if entry then
        local id = entry.id
        t:defer(function() S().clear(id) end, "clear " .. id)
    end
    t:ok(entry ~= nil, "spawn " .. kind .. " refused: " .. tostring(why))
    return entry, p
end

local function body(entry)
    return (S().find(entry))
end

local function standing(entry)
    return function()
        local z = body(entry)
        return z ~= nil and not z:isOnFloor()
    end
end

-- Start square for a walk measure (MP campaign of 2026-10-15): the default square (+2,+2 of the player) is where the
-- body of the previous suite stood (its ghost copy on the owner client kept the trial body on the floor for 83 s) and
-- the walk 6 squares east from there met the walls of the spawn house (moved 0.51 squares). An outdoor square within
-- SPOT_RADIUS of the player, out of the 3 x 3 squares around the default one, with its neighbours free and outdoor,
-- and a straight open lane of WALK_DIST squares in one of the four directions. Returns dx, dy (from the player), wx,
-- wy (walk offset), or nil.
local SPOT_RADIUS = 20
local WALK_DIST = 6
local function outdoorFree(sq)
    return sq ~= nil and sq:isOutside() and sq:getBuildingDef() == nil and sq:isFree(false)
end
local function laneOpen(cell, x, y, z, ux, uy)
    local prev = cell:getGridSquare(x, y, z)
    for i = 1, WALK_DIST do
        local sq = cell:getGridSquare(x + ux * i, y + uy * i, z)
        if not outdoorFree(sq) or prev:isBlockedTo(sq) or prev:isWallTo(sq) or prev:isHoppableTo(sq) then
            return false
        end
        prev = sq
    end
    return true
end
local function walkSpot(p)
    local cell = getCell()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for r = 3, SPOT_RADIUS do
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r and not (math.abs(dx - 2) <= 1 and math.abs(dy - 2) <= 1)
                    and RST.Places.openAround(cell:getGridSquare(px + dx, py + dy, pz), 1) then
                    for _, u in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        if laneOpen(cell, px + dx, py + dy, pz, u[1], u[2]) then
                            return dx, dy, u[1] * WALK_DIST, u[2] * WALK_DIST
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Walk measure of base kind in mode: the body stands, gets a walk WALK_DIST squares along an open lane, and moves
-- WALK_MIN squares at least.
local function walkTest(s, kind, mode)
    s.test(kind .. ": walk mode " .. mode .. " moves the body", function(t)
        local mp = dedicated()
        if mp and kind == "A" then t:skip(A_SOLO_ONLY) end
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local dx, dy, wx, wy = walkSpot(p)
        if dx == nil then
            wx, wy = WALK_DIST, 0
            measure(kind .. " " .. mode .. ": no open outdoor lane near the player, default square and walk east")
        end
        local e = spawn(t, kind, nil, dx, dy)
        t:waitUntil(standing(e), mp and STAND_MS_MP or STAND_MS, function(t2)
            t2:ok(S().walk(e.id, wx, wy, mode), "walk refused")
            local z = body(e)
            local x0, y0 = z:getX(), z:getY()
            local wait = WALK_MS + (mp and COPY_SYNC_MS or 0)
            local from = getTimestampMs()
            -- Ends as soon as the body walked WALK_MIN squares (no fixed wait), at the latest after wait ms.
            t2:waitQuiet(function()
                local zw = body(e)
                return getTimestampMs() - from >= wait or (zw ~= nil and C.distance(zw, x0, y0) >= WALK_MIN)
            end, wait + 5000, function(t3)
                local z3 = body(e)
                t3:ok(z3 ~= nil, "body lost")
                local d = C.distance(z3, x0, y0)
                measure(e.id .. " " .. kind .. " " .. mode .. " moved " .. C.round(d) .. " in " .. (getTimestampMs() - from)
                    .. " ms, state " .. tostring(z3:getCurrentStateName()) .. ", owner " .. C.ownerName(z3))
                t3:ok(d >= WALK_MIN, kind .. " " .. mode .. ": moved only " .. C.round(d) .. " squares")
            end)
        end, "body still on the floor")
    end)
end

RST.suite("lk.essai", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 900000 }, function(s)
    s.test("B: dressed corpse reanimated into a reanimated player, no corpse left", function(t)
        local e = spawn(t, "B")
        local z = e.zombie
        t:ok(z ~= nil, "reanimate gave no zombie")
        t:eq(nil, e.body, "corpse kept")
        t:eq(true, z:isReanimatedPlayer())
        t:eq(e.id, z:getModData()[C.MOD_KEY], "ModData copied from the corpse")
        t:eq(0, #S().taggedCorpses(e), "tagged corpse left on the ground")
        measure(e.id .. " B created: " .. C.describe(z))
    end)

    for _, mode in ipairs(MODES) do
        walkTest(s, "B", mode)
    end

    s.test("A and B at contact for 60 s: no attack, no target, player unhurt", function(t)
        local ea, p = spawn(t, "A", nil, 1, 0)
        local eb = spawn(t, "B", nil, 0, 1)
        for _, e in ipairs({ ea, eb }) do
            S().set(e.id, "useless", true)
            S().set(e.id, "noTeeth", true)
            S().set(e.id, "clearTarget", true)
        end
        local both = function() return standing(ea)() and standing(eb)() end
        t:waitUntil(both, STAND_MS, function(t2)
            local bd = p:getBodyDamage()
            local h0 = bd:getOverallBodyHealth()
            local start = getTimestampMs()
            local seen = { target = 0, attack = 0, minHealth = h0 }
            local function sample()
                for _, e in ipairs({ ea, eb }) do
                    local z = body(e)
                    if z ~= nil then
                        if z:getTarget() ~= nil then seen.target = seen.target + 1 end
                        local st = tostring(z:getCurrentStateName())
                        if string.find(string.lower(st), "attack") or string.find(string.lower(st), "lunge") then
                            seen.attack = seen.attack + 1
                        end
                    end
                end
                local h = bd:getOverallBodyHealth()
                if h < seen.minHealth then seen.minHealth = h end
                return getTimestampMs() - start >= CONTACT_MS
            end
            t2:waitUntil(sample, CONTACT_MS + 15000, function(t3)
                measure("contact 60 s: health " .. C.round(h0) .. " -> min " .. C.round(seen.minHealth)
                    .. ", target samples " .. seen.target .. ", attack/lunge samples " .. seen.attack
                    .. ", player dead " .. tostring(p:isDead()))
                t3:eq(false, p:isDead(), "player dead")
                t3:ok(seen.minHealth >= h0 - 0.01, "player health dropped to " .. C.round(seen.minHealth))
                t3:eq(0, seen.attack, "attack or lunge state samples")
                t3:eq(0, seen.target, "samples with a target")
                t3:ok(body(ea) ~= nil and body(eb) ~= nil, "a body disappeared")
            end, "contact period")
        end, "bodies still on the floor")
    end, { timeoutMs = 120000 })

    s.test("identity after a round trip out of the loaded area", function(t)
        local F = RST.Fixtures
        local ea, p = spawn(t, "A")
        local eb = spawn(t, "B")
        local ox, oy, oz = p:getX(), p:getY(), p:getZ()
        local ax, ay, az = math.floor(ea.x), math.floor(ea.y), math.floor(ea.z)
        local onlineBefore = { a = ea.onlineId, b = eb.onlineId }
        -- Every online player moves away (F.movePlayers): another client left near the body keeps its square loaded
        -- on the server (campaign MP 2026-10-15: "body square still loaded" for 60 s with F.movePlayer).
        F.movePlayers(t, p, ox + FAR, oy, oz, function(t2)
            local unloaded = function() return getCell():getGridSquare(ax, ay, az) == nil end
            t2:waitUntil(unloaded, 60000, function(t3)
                measure("round trip: body square " .. ax .. "," .. ay .. "," .. az .. " unloaded")
                F.movePlayers(t3, p, ox, oy, oz, function(t4)
                    F.waitSquare(t4, ax, ay, az, 30000, function(t5)
                        t5:sleep(5000, function(t6)
                            local za, howA, nA = S().find(ea)
                            local zb, howB, nB = S().find(eb)
                            measure("round trip A: found=" .. howA .. " candidates=" .. nA .. " onlineId "
                                .. tostring(onlineBefore.a) .. " -> " .. tostring(za and za:getOnlineID())
                                .. " tag=" .. tostring(za and za:getModData()[C.MOD_KEY]))
                            measure("round trip B: found=" .. howB .. " candidates=" .. nB .. " onlineId "
                                .. tostring(onlineBefore.b) .. " -> " .. tostring(zb and zb:getOnlineID())
                                .. " tag=" .. tostring(zb and zb:getModData()[C.MOD_KEY]))
                            t6:ok(zb ~= nil and (howB == "object" or howB == "moddata"), "B not found by object or tag: "
                                .. howB)
                            t6:ok(nB <= 1, "B duplicated: " .. nB)
                            t6:ok(za ~= nil, "A lost (" .. howA .. ")")
                            t6:ok(nA <= 1, "A candidates: " .. nA)
                        end)
                    end)
                end)
            end, "body square still loaded")
        end)
    end, { timeoutMs = 180000 })

    s.test("clear removes every trial body and corpse", function(t)
        local ea = spawn(t, "A")
        local eb = spawn(t, "B")
        local ids = { ea.id, eb.id }
        local removed = S().clear()
        t:ok(removed >= 2, "removed " .. tostring(removed))
        for _, id in ipairs(ids) do
            t:eq(nil, S().entry(id), "entry kept: " .. id)
        end
        t:sleep(1000, function(t2)
            local list = getCell():getZombieList()
            local left = 0
            for i = 0, list:size() - 1 do
                local z = list:get(i)
                local tag = z and z:getModData()[C.MOD_KEY]
                if tag == ids[1] or tag == ids[2] then left = left + 1 end
            end
            t2:eq(0, left, "tagged zombies left")
            t2:eq(0, #S().taggedCorpses({ id = ids[2], x = eb.x, y = eb.y, z = eb.z }), "tagged corpses left")
        end)
    end)
end)

-- Base A (ordinary zombie, abandoned on 2026-10-09: docs/plan/LK02, base B retained) in a suite of its own, out of
-- the MP campaign (decision confirmed by default, 2026-10-15): "lk.essai" does not select "lk.essai_a" (prefix rule
-- "<entry>." of RST.select). Solo: RST.run({ suite = "lk.essai_a", tags = "world" }).
RST.suite("lk.essai_a", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 600000 }, function(s)
    s.test("A: ordinary zombie created, tagged, not a reanimated player", function(t)
        local e = spawn(t, "A")
        local z = e.zombie
        t:ok(z ~= nil, "no zombie")
        t:eq("A", e.kind)
        t:eq(false, z:isReanimatedPlayer())
        t:ok(z:getPersistentOutfitID() ~= 0, "persistent outfit id is 0")
        t:eq(e.id, z:getModData()[C.MOD_KEY], "ModData tag")
        local _, how = S().find(e)
        t:eq("object", how)
        measure(e.id .. " A created: " .. C.describe(z))
    end)

    s.test("A: useless keeps a straight walk (walktoward) from moving", function(t)
        if dedicated() then t:skip(A_SOLO_ONLY) end
        local e = spawn(t, "A")
        t:waitUntil(standing(e), STAND_MS, function(t2)
            t2:ok(S().walk(e.id, 6, 0, "uselessline"), "walk refused")
            local z = body(e)
            local x0, y0 = z:getX(), z:getY()
            t2:sleep(WALK_MS, function(t3)
                local z3 = body(e)
                t3:ok(z3 ~= nil, "body lost")
                local d = C.distance(z3, x0, y0)
                measure(e.id .. " A uselessline moved " .. C.round(d) .. " in " .. WALK_MS .. " ms, state "
                    .. tostring(z3:getCurrentStateName()))
                t3:ok(d <= STILL_MAX, "a useless zombie walked " .. C.round(d) .. " squares in a straight line")
            end)
        end, "body still on the floor")
    end)

    for _, mode in ipairs(MODES) do
        walkTest(s, "A", mode)
    end
end)
