--[[
lk.anims - Living Knox gestures of npc bodies (LK02-T05, LivingKnox.Anim and the generated zombie AnimSet nodes
common/media/AnimSets/zombie/<state>/lkactor_*.xml). Tag "world": a save named rstest*, with a target player
(t.ctx.player); the Living Knox option Enabled on. Solo only: the authority creates the npc and the same machine
displays it (animation variables are local and a dedicated server never sets them on a zombie,
IsoGameCharacter.java:11374-11396). Run: RST.run({ suite = "lk.anims", tags = "world" }). Asynchronous run only
(about 1 minute; do not pause the game). On an MP client every test is SKIP.

What is read here (public Java API, IsoGameCharacter.java 42.21.0):
    getVariableBoolean / getVariableString (IAnimationVariableSource.java:17-35) for LKActor and LKGesture;
    getActionStateName (IsoGameCharacter.java:13210) for the action state;
    getAnimationDebug (IsoGameCharacter.java:1545, AdvancedAnimator.GetDebug, AnimLayer.GetDebugString:231-250):
    "State: zombie/<state>", one "Node: <m_Name>" line per live node and "Anim: <clip> Weight: w" per track of the
    root layer. RST.LKAnims.info(z) parses it.
Figures are printed as "[LKA] measure ..." lines. The visual check (does the body look like the gesture) stays in the
protocol of docs/conception/corps-et-animations.md. Every test removes its npc and its vanilla zombie with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Places"

RST.LKAnims = RST.LKAnims or {}
local P = RST.LKAnims

local STAND_MS = RST.LKHelpers.STAND_MS
local GESTURE_MS = 1200     -- blend times are 0.15 to 0.5 s
local WALK_MS = 7000
local SAMPLE_EVERY = 10     -- ticks between two samples of the walk test
local RISE_WATCH_MS = 4000  -- a body that lies first gets up after 1 to 3 s, then plays a get-up of about 2 s
local PROBE_MS = 1500       -- LK06-T10: a probe noise behind the walking body at this pace
local PROBE_RADIUS = 10     -- radius and volume of the probe noise (heard at 3 squares by a non-useless zombie)
local MIN_MOVED = 3         -- squares walked at least in WALK_MS (pathfind walk measured at about 6.5 in 8 s)

-- Node expected in the idle state for each gesture, no weapon in hand (tools/anim_table.json).
P.IDLE_NODES = { idle = "LKActorIdle", walk = "LKActorIdle", run = "LKActorIdle", crouch = "LKActorCrouchIdle",
    aim = "LKActorAimHandgun", guard = "LKActorGuard2H", strike = "LKActorStrike2H" }
P.ORDER = { "aim", "guard", "strike", "crouch", "walk", "run", "idle" }
P.MOVING_STATES = { walktoward = true, ["walktoward-network"] = true, pathfind = true }
-- LK06-T10: zombie states that follow a noise or a target (media/actiongroups/zombie).
P.ALERT_STATES = { turnalerted = true, lunge = true, ["lunge-network"] = true, attack = true,
    ["attack-network"] = true, ["face-target"] = true }

local function B() return LivingKnox and LivingKnox.Bodies end
local function A() return LivingKnox and LivingKnox.Anim end
local function G() return LivingKnox and LivingKnox.ZombieGuard end

local function measure(text)
    print("[LKA] measure " .. tostring(text))
end

local function call(z, method, ...)
    local ok, v = pcall(z[method], z, ...)
    if ok then return v end
    return nil
end

-- Animation facts of a character, read through the public API. Returns { actor, gesture, action, state,
-- nodes = { names }, anims = { clips } }; nodes and anims of the root layer only.
function P.info(z)
    local out = { nodes = {}, anims = {} }
    out.actor = call(z, "getVariableBoolean", "LKActor") == true
    out.gesture = call(z, "getVariableString", "LKGesture") or ""
    out.action = call(z, "getActionStateName")
    local text = call(z, "getAnimationDebug") or ""
    local layer = -1
    for line in string.gmatch(text, "[^\n]+") do
        if string.find(line, "^Layer: ") then
            layer = 0
        elseif string.find(line, "^SubLayer: ") or string.find(line, "^Variables:") then
            layer = 1
        elseif layer == 0 then
            local state = string.match(line, "^State: [^/]*/(.+)$")
            local node = string.match(line, "^%s+Node: (.+)$")
            local anim = string.match(line, "^%s+Anim: (%S+)")
            if state then out.state = state end
            if node then out.nodes[#out.nodes + 1] = node end
            if anim then out.anims[#out.anims + 1] = anim end
        end
    end
    return out
end

function P.describe(i)
    return "actor=" .. tostring(i.actor) .. " gesture=" .. tostring(i.gesture) .. " action=" .. tostring(i.action)
        .. " state=" .. tostring(i.state) .. " nodes=" .. table.concat(i.nodes, ",") .. " anims="
        .. table.concat(i.anims, ",")
end

local function has(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function anyOurs(list)
    for _, v in ipairs(list) do
        if string.find(v, "^LKActor") then return true end
    end
    return false
end

-- A straight line of WALK_SQUARES squares from (x, y, z) towards (dx, dy) with nothing on any edge (wall, door, window,
-- frame, low fence) and free squares: the walk test needs one (in-game run of 2026-10-13: inside a house the fixed walk
-- to the east met a wall after one square). Returns true or false.
local WALK_SQUARES = 6
local function clearLine(x, y, z, dx, dy)
    local cell = getCell()
    local p = cell:getGridSquare(x, y, z)
    for _ = 1, WALK_SQUARES do
        local q = p and cell:getGridSquare(p:getX() + dx, p:getY() + dy, z)
        if p == nil or q == nil or not q:isFree(false) or p:isBlockedTo(q) or p:isDoorTo(q) or p:isWindowTo(q)
            or p:isHoppableTo(q) or p:getWindowFrameTo(q) ~= nil then
            return false
        end
        p = q
    end
    return true
end

local function needSolo(t)
    if not (LivingKnox and LivingKnox.isAuthority() and LivingKnox.hasLocalPlayer()) then
        t:skip("solo only: the authority must also display the body")
    end
end

local function spawnNpc(t, dx, dy)
    t:ok(B() ~= nil and A() ~= nil and G() ~= nil, "LivingKnox.Bodies, Anim or ZombieGuard is not loaded")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function()
            G().setTravelling(id, false)
            A().setGesture(id, "idle")
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    -- Nearest free square (no standing character on it or next to it): an npc made by hand near the player does not
    -- keep this one on the floor.
    measure("npc " .. id .. " wanted " .. x .. "," .. y .. "," .. z .. ", created at " .. math.floor(body:getX()) .. ","
        .. math.floor(body:getY()) .. "," .. math.floor(body:getZ()))
    return id, body, p
end

local spawnVanilla, standing = RST.LKHelpers.spawnVanilla, RST.LKHelpers.standing

-- Open ground around the player (no building, every square walkable within 3) with a clear line of WALK_SQUARES
-- squares from the square of the walk test (player + 2, + 2), or nil.
local function openSpot(p)
    local sq = p:getCurrentSquare()
    if sq == nil or not RST.Places.openAround(sq, 3) then return nil end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if clearLine(sq:getX() + 2, sq:getY() + 2, sq:getZ(), d[1], d[2]) then return sq end
    end
    return nil
end

RST.suite("lk.anims", { tags = { "world" }, testTimeoutMs = 90000, timeoutMs = 300000 }, function(s)
    -- Each test: player protected (god mode, invisible to the vanilla zombie) on open ground (RST.Places, solo: moved
    -- to a yard or a street nearby when needed, back at the end).
    s.before(function(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        RST.Places.protect(t, p, true)
        RST.Places.ensure(t, { name = "open ground", spot = openSpot, outdoor = true, tries = 12 }, function() end)
    end)

    s.test("each gesture selects its node on the npc; a vanilla zombie keeps its own nodes", function(t)
        needSolo(t)
        -- LK02-T11: an npc already stands on the square wanted for the test npc (made "by hand" near the player): the
        -- test npc is created on another free square and stands up all the same.
        local p0 = RST.Fixtures.player(t)
        local by, byBody = B().spawn({}, math.floor(p0:getX()) + 2, math.floor(p0:getY()), math.floor(p0:getZ()))
        if by then t:defer(function() B().despawn(by, true) end, "forget the bystander " .. by) end
        t:ok(by ~= nil, "bystander npc refused: " .. tostring(byBody))
        measure("bystander npc " .. by .. " at " .. math.floor(byBody:getX()) .. "," .. math.floor(byBody:getY()))
        local id, body = spawnNpc(t, 2, 0)
        local v = spawnVanilla(t, body, 4, 0) -- from the body: findFreeSquare may have moved it
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local function step(tc, i)
                local g = P.ORDER[i]
                if g == nil then return end
                local ok, why = A().setGesture(id, g)
                tc:ok(ok, "setGesture " .. g .. ": " .. tostring(why))
                tc:sleep(GESTURE_MS, function(t3)
                    local z = B().find(id)
                    t3:ok(z ~= nil, "npc body lost")
                    local info = P.info(z)
                    local vinfo = P.info(v)
                    measure(g .. ": npc " .. P.describe(info))
                    measure(g .. ": vanilla " .. P.describe(vinfo))
                    t3:eq(true, info.actor, g .. ": LKActor on the npc")
                    t3:eq(g, info.gesture, g .. ": LKGesture on the npc")
                    t3:eq("idle", info.state, g .. ": animation state of the npc at rest")
                    t3:ok(has(info.nodes, P.IDLE_NODES[g]), g .. ": node " .. P.IDLE_NODES[g] .. " not live ("
                        .. table.concat(info.nodes, ",") .. ")")
                    t3:eq(false, vinfo.actor, g .. ": LKActor on the vanilla zombie")
                    t3:eq(false, anyOurs(vinfo.nodes), g .. ": a Living Knox node on the vanilla zombie")
                    step(t3, i + 1)
                end)
            end
            step(t2, 1)
        end, "npc still on the floor")
    end, { timeoutMs = 90000 })

    -- LK02-T14: the body is stood up in the very call of its reanimation (LivingKnox.Stand.now). Its animator
    -- still blends out of the lying clip for about 0.3 s (hidden by the fade-in): only the action state, the
    -- floor flag and the get-up clip are checked; the lying clip seen during the blend is measured.
    s.test("a new npc is standing from its creation and never plays the get-up", function(t)
        needSolo(t)
        local id, body = spawnNpc(t, 2, -2)
        local first = P.info(body)
        measure("at creation: floor=" .. tostring(body:isOnFloor()) .. " alpha=" .. tostring(body:getAlpha())
            .. " " .. P.describe(first))
        t:eq(false, body:isOnFloor(), "npc on the floor right after its creation")
        t:eq("idle", first.action, "action state right after the creation")
        local seen = { samples = 0, down = {}, getup = 0, lyingClip = 0 }
        local start = getTimestampMs()
        t:waitUntil(function()
            local z = B().find(id)
            if z ~= nil then
                local info = P.info(z)
                seen.samples = seen.samples + 1
                if z:isOnFloor() or LivingKnox.Stand.LYING_ACTIONS[info.action or ""] then
                    seen.down[#seen.down + 1] = P.describe(info)
                end
                if has(info.anims, "Zombie_GetUp") then seen.getup = seen.getup + 1 end
                if has(info.anims, "Zombie_Idle_FloorOnBack") or has(info.anims, "Zombie_Idle_FloorOnFront") then
                    seen.lyingClip = seen.lyingClip + 1
                end
            end
            return getTimestampMs() - start >= RISE_WATCH_MS
        end, RISE_WATCH_MS + 5000, function(t2)
            measure("first " .. RISE_WATCH_MS .. " ms: " .. seen.samples .. " samples, down " .. #seen.down
                .. ", get-up clip " .. seen.getup .. ", lying clip still blending " .. seen.lyingClip)
            t2:eq(0, #seen.down, "npc seen lying or getting up: " .. table.concat(seen.down, " | "))
            t2:eq(0, seen.getup, "Zombie_GetUp played on the npc")
        end, "watch the new npc")
    end, { timeoutMs = 30000 })

    s.test("an npc put on the floor later gets up through the vanilla get-up", function(t)
        needSolo(t)
        local id = spawnNpc(t, -2, -2)
        -- The fall is applied 1.5 s after the creation (in-game run of 2026-10-11: a fall set in the creation call
        -- was never seen), once the body has settled in its standing state.
        local seen = { onground = false, getup = false }
        local fallAt, fallen = getTimestampMs() + 1500, false
        t:waitUntil(function()
            local z = B().find(id)
            if z == nil then return false end
            if not fallen then
                if getTimestampMs() < fallAt then return false end
                fallen = true
                z:setOnFloor(true) -- what a fall does: the action state goes to onground at the next update
                z:setKnockedDown(true)
                return false
            end
            local info = P.info(z)
            if info.action ~= seen.last then   -- each change of action state, for the diagnosis
                seen.last = info.action
                measure("fallen npc: action " .. tostring(info.action) .. ", floor " .. tostring(z:isOnFloor())
                    .. ", anims " .. (type(info.anims) == "table" and table.concat(info.anims, ",") or tostring(info.anims)))
            end
            if info.action == "onground" then seen.onground = true end
            if string.find(info.action or "", "^getup") or has(info.anims, "Zombie_GetUp") then seen.getup = true end
            return seen.onground and seen.getup and not z:isOnFloor() and info.action == "idle"
        end, 15000, function(t2)
            measure("fallen npc: onground " .. tostring(seen.onground) .. ", get-up " .. tostring(seen.getup)
                .. ", stood " .. tostring(LivingKnox.Stand.stats.stood))
            t2:eq(true, seen.getup, "fallen npc got up without the vanilla get-up")
        end, "fallen npc never went through onground, the get-up and back to idle")
    end, { timeoutMs = 30000 })

    -- LK06-T10: the body walks the way LivingKnox.Executor.issuePath makes it walk (pathfind state, useless kept by the
    -- guard). Its own step noises (source nil since LK06-T08) and a probe noise behind it every PROBE_MS must never
    -- alert it: no turnalerted state, alerted variable false, no lunge or target, useless always true.
    s.test("walk and run play the Living Knox moving nodes", function(t)
        needSolo(t)
        local id = spawnNpc(t, 2, 2)
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local function walkTo(tc, gesture, dx, dy, done)
                local z = B().find(id)
                tc:ok(z ~= nil, "npc body lost")
                local x0, y0 = z:getX(), z:getY()
                A().setGesture(id, gesture)
                z:pathToLocation(math.floor(x0) + dx * WALK_SQUARES, math.floor(y0) + dy * WALK_SQUARES,
                    math.floor(z:getZ()))
                z:setVariable("bPathfind", true)
                z:setMoving(false)
                local seen = { samples = 0, moving = 0, ours = 0, other = {}, ticks = 0, alerted = {}, notUseless = 0,
                    probes = 0, lastProbe = 0 }
                local start = getTimestampMs()
                tc:waitUntil(function()
                    seen.ticks = seen.ticks + 1
                    local zz = B().find(id)
                    local now = getTimestampMs()
                    if zz ~= nil and addSound ~= nil and now - seen.lastProbe >= PROBE_MS then
                        -- Probe: a noise 3 squares behind the body (opposite to its walk), heard by any non-useless
                        -- zombie at that distance (radius PROBE_RADIUS, source nil).
                        seen.lastProbe = now
                        seen.probes = seen.probes + 1
                        addSound(nil, math.floor(zz:getX()) - 3 * dx, math.floor(zz:getY()) - 3 * dy,
                            math.floor(zz:getZ()),
                            PROBE_RADIUS, PROBE_RADIUS)
                    end
                    if seen.ticks % SAMPLE_EVERY == 0 and zz ~= nil then
                        local info = P.info(zz)
                        seen.samples = seen.samples + 1
                        if not zz:isUseless() then seen.notUseless = seen.notUseless + 1 end
                        if P.ALERT_STATES[info.action or ""] or P.ALERT_STATES[info.state or ""]
                            or call(zz, "getVariableBoolean", "alerted") == true or zz:getTarget() ~= nil then
                            seen.alerted[#seen.alerted + 1] = P.describe(info)
                        end
                        if P.MOVING_STATES[info.state or ""] then
                            seen.moving = seen.moving + 1
                            if anyOurs(info.nodes) then
                                seen.ours = seen.ours + 1
                            else
                                seen.other[#seen.other + 1] = P.describe(info)
                            end
                        end
                    end
                    return now - start >= WALK_MS
                end, WALK_MS + 5000, function(t3)
                    local zz = B().find(id)
                    local moved = zz and math.sqrt((zz:getX() - x0) ^ 2 + (zz:getY() - y0) ^ 2) or -1
                    measure(gesture .. ": " .. seen.samples .. " samples, moving " .. seen.moving .. ", our node "
                        .. seen.ours .. ", alerted " .. #seen.alerted .. ", not useless " .. seen.notUseless
                        .. ", probe noises " .. seen.probes .. ", moved " .. tostring(math.floor(moved * 100) / 100)
                        .. " squares in " .. WALK_MS .. " ms" .. (zz and (", now " .. P.describe(P.info(zz))) or ""))
                    t3:ok(seen.moving > 0, gesture .. ": the npc never entered a moving state")
                    t3:eq(seen.moving, seen.ours, gesture .. ": moving samples without our node: "
                        .. table.concat(seen.other, " | "))
                    t3:eq(0, #seen.alerted, gesture .. ": npc alerted by a noise: " .. table.concat(seen.alerted, " | "))
                    t3:eq(0, seen.notUseless, gesture .. ": samples with useless off")
                    t3:ok(moved >= MIN_MOVED, gesture .. ": moved only " .. tostring(moved) .. " squares")
                    done(t3)
                end, "walk sampling")
            end
            -- A direction with WALK_SQUARES clear squares ahead: walk there, then run back along the same line.
            local z = B().find(id)
            local zx, zy, zz = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
            local dir
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                if clearLine(zx, zy, zz, d[1], d[2]) then dir = d break end
            end
            if dir == nil then
                t2:skip("no line of " .. WALK_SQUARES .. " clear squares around the npc at " .. zx .. "," .. zy
                    .. ": run the suite in a room or yard with more room")
                return
            end
            walkTo(t2, "walk", dir[1], dir[2], function(t3)
                walkTo(t3, "run", -dir[1], -dir[2], function() end)
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 90000 })
end)

return P
