--[[
lk.bodies - Living Knox npc bodies and registry (LK02-T02): creation, binding after a round trip out of the loaded
area, simulated duplicate, orphans, removal; release beyond the release radius (LK03-T04: the npc goes back to the
offscreen simulation, no body left after the way back, release delay shortened to 3 s for the test).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on.
Solo: RST.run({ suite = "lk.bodies", tags = "world" }); dedicated server: RST.server({ suite = "lk.bodies",
tags = "world" }) from an admin client. Asynchronous run only (the round trip waits in steps, about 1 minute).
Every test forgets its npcs and removes its extra bodies with t:defer, even when it fails.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Places"

local FAR = 300             -- squares: beyond the loaded area (13 to 19 chunks of 8 squares)
local OFFSET = 2

local function B() return LivingKnox and LivingKnox.Bodies end
local function I() return LivingKnox and LivingKnox.Identity end
local function R() return LivingKnox and LivingKnox.Store and LivingKnox.Store.data() end

-- Living zombies of the cell carrying this npc id (any generation).
local function tagged(id)
    local out = {}
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z ~= nil and not z:isDead() and z:hasModData() then
            local tid = I().readTag(z:getModData())
            if tid == id then out[#out + 1] = z end
        end
    end
    return out
end

local function spawn(t, dx, dy)
    t:ok(B() ~= nil, "LivingKnox.Bodies is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + (dx or OFFSET), math.floor(p:getY()) + (dy or OFFSET), math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
    end
    t:ok(id ~= nil, "spawn refused: " .. tostring(body))
    return id, body, p
end

-- Extra body made with a given tag (no registry change), removed at the end if still there.
local function rawBody(t, id, generation, dx, dy)
    local p = RST.Fixtures.player(t)
    local sq = getCell():getGridSquare(math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ()))
    t:ok(sq ~= nil, "square not loaded")
    local z, why = B().createBody(sq, I().normalizeProfile({}), id, generation)
    t:ok(z ~= nil, "createBody failed: " .. tostring(why))
    t:defer(function()
        if B().inWorld(z) then B().removeBody(z, "test cleanup") end
    end, "remove extra body " .. id .. "#" .. generation)
    return z
end

RST.suite("lk.bodies", { tags = { "world", "server" }, testTimeoutMs = 60000, timeoutMs = 300000 }, function(s)
    s.test("spawn: reanimated player tagged with id and generation 1, useless, registry saved", function(t)
        local id, body, p = spawn(t)
        t:ok(I().isId(id), "bad id " .. tostring(id))
        t:eq(true, body:isReanimatedPlayer())
        local tid, gen = I().readTag(body:getModData())
        t:eq(id, tid, "ModData id")
        t:eq(1, gen, "ModData generation")
        t:eq(true, body:isUseless(), "useless")
        local found, how = B().find(id)
        t:eq(body, found, "find")
        t:eq("bound", how)
        local npc = R().npcs[id]
        t:eq("embodied", npc.state)
        t:eq(1, npc.generation)
        t:eq(math.floor(p:getX()) + OFFSET, npc.want.x, "want.x: requested square")
        t:eq(math.floor(p:getY()) + OFFSET, npc.want.y, "want.y: requested square")
        t:eq(math.floor(body:getX()), npc.last.x, "last.x: square of the body")
        t:eq(math.floor(body:getY()), npc.last.y, "last.y: square of the body")
        t:eq(1, #tagged(id), "tagged bodies")
        -- LK13-T10: written at the end of the frame; flush writes it now.
        t:eq(true, LivingKnox.Store.flush(), "registry written on change")
        t:eq(false, LivingKnox.Store.isQueued(), "nothing left to write")
    end)

    -- LK02-T11: a body made on a square where a standing character is next to it never gets up; the spawn picks the
    -- nearest free square instead (no standing character on it nor on its 8 neighbours) and logs "(wanted ...)".
    s.test("two npcs wanted on the square of an npc already there: all on distinct free squares, all standing",
        function(t)
        local function openSpot(p)
            local sq = p:getCurrentSquare()
            if sq ~= nil and RST.Places.openAround(sq, 4) then return sq end
            return nil
        end
        RST.Places.ensure(t, { name = "open ground", spot = openSpot, outdoor = true, tries = 12 }, function(t1, sq)
            local first, firstBody = B().spawn({}, sq:getX() + 2, sq:getY(), sq:getZ())
            if first then t1:defer(function() B().despawn(first, true) end, "forget " .. first) end
            t1:ok(first ~= nil, "first npc refused: " .. tostring(firstBody))
            local wx, wy, wz = math.floor(firstBody:getX()), math.floor(firstBody:getY()), math.floor(firstBody:getZ())
            local ids = { first }
            for i = 1, 2 do
                local id, body = B().spawn({}, wx, wy, wz)
                if id then t1:defer(function() B().despawn(id, true) end, "forget " .. id) end
                t1:ok(id ~= nil, "npc " .. i .. " wanted on " .. wx .. "," .. wy .. " refused: " .. tostring(body))
                ids[#ids + 1] = id
            end
            local where = {}
            for _, id in ipairs(ids) do
                local npc = R().npcs[id]
                where[#where + 1] = string.format("%s wanted %d,%d created %d,%d", id, npc.want.x, npc.want.y,
                    npc.last.x, npc.last.y)
            end
            print("[LKB] measure same square: " .. table.concat(where, "; "))
            for i = 1, #ids do
                for j = i + 1, #ids do
                    local a, b = R().npcs[ids[i]].last, R().npcs[ids[j]].last
                    t1:ok(math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) >= 2, ids[i] .. " and " .. ids[j]
                        .. " created next to each other")
                end
            end
            local since = getTimestampMs()
            t1:waitUntil(function()
                if getTimestampMs() - since < 3000 then return false end
                for _, id in ipairs(ids) do
                    local z = B().find(id)
                    if z == nil or z:isOnFloor() then return false end
                end
                return true
            end, 25000, function(t2)
                local states = {}
                for _, id in ipairs(ids) do
                    local z = B().find(id)
                    states[#states + 1] = id .. " " .. tostring(z:getActionStateName())
                end
                print("[LKB] measure same square after 3 s: " .. table.concat(states, ", "))
                t2:eq(3, #ids, "npcs standing")
            end, "an npc of the same square stays on the floor")
        end)
    end, { timeoutMs = 60000 })

    s.test("duplicate with the current tag is removed, the bound body kept", function(t)
        local id, body = spawn(t)
        rawBody(t, id, 1, OFFSET + 1, OFFSET)
        t:eq(2, #tagged(id), "two bodies before the scan")
        B().scanAll()
        local left = tagged(id)
        t:eq(1, #left, "bodies after the scan")
        t:eq(body, left[1], "kept body")
        t:eq(body, (B().find(id)), "binding")
    end)

    s.test("stale generation, generation ahead and unknown id are removed as orphans", function(t)
        local id = spawn(t)
        t:ok(B().despawn(id), "despawn")
        local body2 = B().embody(id, math.floor(RST.Fixtures.player(t):getX()) + OFFSET,
            math.floor(RST.Fixtures.player(t):getY()) + OFFSET, math.floor(RST.Fixtures.player(t):getZ()))
        t:ok(body2 ~= nil, "embody")
        t:eq(2, R().npcs[id].generation, "second incarnation")
        rawBody(t, id, 1, OFFSET + 1, OFFSET)
        rawBody(t, id, 3, OFFSET - 1, OFFSET)
        local unknown = "lk-" .. tostring(R().nextId + 1000)
        rawBody(t, unknown, 1, OFFSET, OFFSET + 1)
        B().scanAll()
        local left = tagged(id)
        t:eq(1, #left, "bodies of " .. id)
        t:eq(body2, left[1], "current incarnation kept")
        t:eq(0, #tagged(unknown), "unknown id removed")
    end)

    s.test("despawn removes the body; forget removes the npc, its number is not reused", function(t)
        local id = spawn(t)
        local nextId = R().nextId
        t:ok(B().despawn(id), "despawn")
        t:eq(0, #tagged(id), "body left")
        t:eq("virtual", R().npcs[id].state)
        t:eq(nil, (B().find(id)))
        t:ok(B().despawn(id, true), "forget")
        t:eq(nil, R().npcs[id], "npc kept")
        t:eq(nextId, R().nextId, "nextId changed")
    end)

    s.test("binding kept after a round trip out of the loaded area", function(t)
        local F = RST.Fixtures
        local id, body, p = spawn(t)
        local ox, oy, oz = p:getX(), p:getY(), p:getZ()
        local bx, by, bz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
        F.movePlayers(t, p, ox + FAR, oy, oz, function(t2)
            local unloaded = function() return getCell():getGridSquare(bx, by, bz) == nil end
            t2:waitUntil(unloaded, 60000, function(t3)
                local _, state = B().find(id)
                t3:eq("embodied", state, "state while out of the loaded area")
                F.movePlayers(t3, p, ox, oy, oz, function(t4)
                    F.waitSquare(t4, bx, by, bz, 30000, function(t5)
                        t5:waitUntil(function() return B().find(id) ~= nil end, 15000, function(t6)
                            local left = tagged(id)
                            t6:eq(1, #left, "bodies after the round trip")
                            local tid, gen = I().readTag(left[1]:getModData())
                            t6:eq(id, tid)
                            t6:eq(1, gen)
                            t6:eq(true, left[1]:isUseless(), "useless after the round trip")
                            print("[LKB] measure round trip: same object " .. tostring(left[1] == body))
                        end, "body not bound again")
                    end)
                end)
            end, "body square still loaded")
        end)
    end, { timeoutMs = 180000 })

    s.test("release: beyond the release radius the npc goes back to the offscreen simulation, no body left", function(t)
        local F = RST.Fixtures
        local C = LivingKnox.Config.BODIES
        local delay = C.RELEASE_DELAY_MS
        C.RELEASE_DELAY_MS = 3000
        t:defer(function() C.RELEASE_DELAY_MS = delay end, "restore the release delay")
        t:ok(FAR > C.RELEASE_RADIUS + OFFSET, "FAR must exceed the release radius")
        local id, body, p = spawn(t)
        local ox, oy, oz = p:getX(), p:getY(), p:getZ()
        local bx, by, bz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
        local released = function() return R().npcs[id] ~= nil and R().npcs[id].state == "virtual" end
        F.movePlayers(t, p, ox + FAR, oy, oz, function(t2)
            t2:waitUntil(released, 60000, function(t3)
                t3:eq(nil, (B().find(id)), "bound body after the release")
                t3:eq(0, #tagged(id), "bodies in the loaded area after the release")
                local last = R().npcs[id].last
                t3:ok(last ~= nil and math.abs(last.x - bx) <= 1 and math.abs(last.y - by) <= 1, "last seen position")
                F.movePlayers(t3, p, ox, oy, oz, function(t4)
                    F.waitSquare(t4, bx, by, bz, 30000, function(t5)
                        local since = getTimestampMs()
                        local swept = function()
                            return #tagged(id) == 0 and getTimestampMs() - since >= 10000
                        end
                        t5:waitUntil(swept, 30000, function(t6)
                            t6:eq("virtual", R().npcs[id].state, "state after the way back")
                            t6:eq(nil, (B().find(id)), "bound body after the way back")
                            print("[LKB] measure release: health kept " .. tostring(R().npcs[id].hp)
                                .. ", generation " .. tostring(R().npcs[id].generation))
                        end, "a body of the released npc is still in the world")
                    end)
                end)
            end, "npc not released")
        end)
    end, { timeoutMs = 180000 })
end)
