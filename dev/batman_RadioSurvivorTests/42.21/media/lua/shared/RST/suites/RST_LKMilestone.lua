--[[
lk.milestone1 - Living Knox milestone 1 (LK02-T08): bodies and gestures chained on the same npc, then on two npcs,
with the measures of the milestone report (docs/annexes/tests/validation/jalon1-<date>.md). Tags "world" and "server": the
authority only, on a save named rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.milestone1", tags = "world" }); dedicated server: RST.server({ suite = "lk.milestone1",
tags = "world" }) from an admin client standing still (the bodies are then simulated by a client: the checks that
only the displaying machine can make are replaced by "measure" lines and done on the clients, see the report).
Asynchronous run only (about 4 minutes; do not pause the game, do not move during the run).

Test 1, one npc, in this order:
    spawn       new npc 2 squares east of the player on a free square (registry, tag, generation 1); creation time
    stand       time from the spawn call until the body is up
    appearance  human skin of the profile, clothes without holes, blood, dirt or patches, no wound, nothing attached
    weapon      Base.Shotgun attached at rest, in hand to aim (solo: hands, variable Weapon, node), attached again
    guard       vanilla neighbour intact (no useless, no noTeeth, own voice) then removed; 30 s at contact: no target,
                no attack, no eating, player unhurt, guard flags and silent voice on the npc
    walk        "move" 9 squares east: arrival, walk gesture, speed (squares/s); stop: still 1.5 s, idle, useless back;
                face S: about 90 degrees
    run         "move" 9 squares back west with the run gesture: speed
    gesture     guard, strike, crouch, idle: LKGesture and node (solo), weapon in hand for guard and strike
    roundtrip   player 300 squares away then back: same body object, same generation, guard flags and weapon
Test 2, two npcs requested on the same square: two distinct free squares, both up, one weapon each, both walk 9
squares at the same time, gestures aim and guard.
Test 3, cleanup: no npc, directive, weapon, gesture or tagged body left by tests 1 and 2; probe removed; then the
engine cost with no npc (3 s).

MP section 6 (E01-T16): on a dedicated server every client runs its own probe during test 1 (lines "client <account>
cost ..." and the pose relay delay in the server report) and takes screenshots after the spawn, weapon and gesture
stages (lk-milestone1-<stage>-<account>.png, collected by the launcher).
Measures: a probe (RST_LKProbe.lua) wraps the engine OnTick subscribers, Bodies.scan and the network calls during
tests 1 to 3 and restores them (nothing of the published mod is changed): cost per tick on this machine, per phase,
zombies examined per scan slice, LivingKnox messages sent and received (MP only) with an approximate size. Every
step prints "[LKM] measure <step> ..." and keeps the same line in the RST report (t:note). Every test removes its
npcs, directives, weapons and vanilla zombie with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_LKProbe"
require "RST/RST_Steps"
require "RST/RST_PeerChecksLK2"
require "RST/suites/RST_LKAnims"
require "RST/suites/RST_LKEquipment"

RST.LKMilestone = RST.LKMilestone or {}
local M = RST.LKMilestone
M.ids = M.ids or {}         -- npc ids created by the current run (checked by the cleanup test)

local K = RST.LKHelpers
local F = RST.Fixtures
local Probe = RST.LKProbe
local W = RST.LKEquipment
local AN = RST.LKAnims

M.WEAPON = { item = "Base.Shotgun", slot = "Rifle On Back", weapon = "firearm", aimNode = "LKActorAimRifle" }
M.SECOND = { { item = "Base.Pistol", slot = "Holster Right", gesture = "aim" },
    { item = "Base.BaseballBat", slot = "Shovel Back", gesture = "guard" } }
M.GESTURES = { "guard", "strike", "crouch", "idle" }
-- Node expected with the shotgun held in both hands for guard and strike (tools/anim_table.json: the 1H nodes need
-- Weapon = 1handed), at rest for crouch and idle.
M.NODES = { guard = "LKActorGuard2H", strike = "LKActorStrike2H", crouch = "LKActorCrouchIdle", idle = "LKActorIdle",
    aim = "LKActorAimHandgun" }
M.HAND = { aim = true, guard = true, strike = true }

local TRIP = 9
local CONTACT_MS = 30000
local NEIGHBOUR_MS = 3000
local ARRIVE_MS = 40000
local DONE_MS = 10000
local SETTLE_MS = 600       -- equipment display pass every 3 ticks
local GESTURE_MS = 1200     -- blend times are 0.15 to 0.5 s
local STILL_MS = 1500
-- Copy of a body simulated by a client, read on a dedicated server: it only follows the owner's zombie packets (every
-- 4 s, sooner on a state change), so the position read at the arrival report lags behind (campaign MP 2026-10-15:
-- "moved 1.26 squares after the arrival", the copy catching up during STILL_MS). The stop is measured from a position
-- read once the copy has had one packet period to settle.
local COPY_SYNC_MS = 5000
local FACE_MS = 1500
local IDLE_PROBE_MS = 3000

local fixed = Probe.fixed
local round = K.round

local function side()
    if isServer() then return "server" end
    if isClient() then return "client" end
    return "solo"
end

-- The authority also displays the bodies (solo): hand items, animation variables and nodes can be read here.
local function displaysHere()
    return LivingKnox ~= nil and LivingKnox.isAuthority() and LivingKnox.hasLocalPlayer()
end

local function note(t, step, text)
    local line = step .. " " .. tostring(text)
    print("[LKM] measure " .. line)
    t:note(line)
end

local function has(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function sqText(o)
    return math.floor(o:getX()) .. "," .. math.floor(o:getY()) .. "," .. math.floor(o:getZ())
end

local function body(t, id)
    local z = K.B().find(id)
    t:ok(z ~= nil, "npc " .. tostring(id) .. " body lost")
    return z
end

local function closed(id)
    return function()
        local e = K.D().get(id)
        return e ~= nil and e.done == true
    end
end

local function loaded(t)
    t:ok(K.B() ~= nil and K.G() ~= nil and K.A() ~= nil and K.E() ~= nil and K.D() ~= nil and K.I() ~= nil,
        "LivingKnox.Bodies, ZombieGuard, Anim, Equipment, Directives or Identity is not loaded on this side")
end

-- New npc wanted at player + (dx, dy). Returns the npc context { id, body, player, spawnMs, t0, want }.
local function spawnNpc(t, dx, dy, profile)
    local p = F.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    local t0 = getTimestampMs()
    local id, b = K.B().spawn(profile or {}, x, y, z)
    local ms = getTimestampMs() - t0
    if id then
        M.ids[#M.ids + 1] = id
        t:defer(function()
            K.D().forget(id)
            K.E().setWeapon(id, nil)
            K.G().setTravelling(id, false)
            K.A().setGesture(id, "idle")
            K.B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(b))
    return { id = id, body = b, player = p, spawnMs = ms, t0 = t0, want = x .. "," .. y .. "," .. z }
end

-- Starts a probe, then suite(t, probe) once its wrappers are installed (next tick).
local function withProbe(t, suite)
    local probe, why = Probe.start()
    t:ok(probe ~= nil, "probe not started: " .. tostring(why))
    t:defer(function() Probe.stop(probe) end, "stop the probe")
    t:waitUntil(function() return probe.installed end, 5000, function(t2) suite(t2, probe) end, "probe not installed")
end

local function stopProbe(t, probe, label, npcs)
    local s = Probe.stop(probe)
    for _, line in ipairs(Probe.lines(s)) do note(t, "cost " .. label, line) end
    local secs = s.durationMs / 1000
    if npcs > 0 and secs > 0 then
        note(t, "net " .. label, "per npc on " .. s.side .. ": sent " .. fixed(s.net.out.count / npcs / secs, 2)
            .. " msg/s and " .. fixed(s.net.out.bytes / npcs / secs, 1) .. " B/s, received "
            .. fixed(s.net.inc.count / npcs / secs, 2) .. " msg/s and " .. fixed(s.net.inc.bytes / npcs / secs, 1)
            .. " B/s over " .. fixed(secs, 1) .. " s" .. (isServer() and "" or " (nothing travels in solo)"))
    end
    if isServer() then
        note(t, "mp " .. label, "observer cost and pose relay delay: LKM.start() / LKM.stop() and LKB.pose(<npc>) on"
            .. " the observer client (not the owner)")
    end
    return s
end

-- Guard flags expected on a bound body at rest, on this side (the voice only where voices are played).
local function checkRest(t, z, what)
    t:eq(true, z:isNoTeeth(), what .. ": noTeeth")
    if K.G().simulatedHere(z) then
        t:eq(true, z:isUseless(), what .. ": useless")
        t:eq(nil, z:getTarget(), what .. ": target")
        t:eq(nil, z:getEatBodyTarget(), what .. ": eat target")
    end
    if LivingKnox.hasLocalPlayer() then
        t:eq(K.G().SILENT_VOICE, K.voiceOf(z), what .. ": voice prefix")
    end
end

-- ---------------------------------------------------------------- stages of test 1 (one npc)

local function stageStand(t, c, done)
    local b = c.body
    local tag, gen = K.I().readTag(b:getModData())
    local npc = K.registry().npcs[c.id]
    note(t, "spawn", c.id .. " created in " .. c.spawnMs .. " ms at " .. sqText(b) .. " (wanted " .. c.want
        .. "), tag " .. tostring(tag) .. "#" .. tostring(gen) .. ", registry " .. tostring(npc and npc.state)
        .. ", look " .. tostring(npc and npc.profile.look))
    t:eq(c.id, tag, "ModData id")
    t:eq(1, gen, "ModData generation")
    t:eq(true, b:isReanimatedPlayer(), "reanimated player")
    t:eq("embodied", npc and npc.state, "registry state")
    t:waitUntil(K.standing(c.id), K.STAND_MS, function(t2)
        c.standMs = getTimestampMs() - c.t0
        note(t2, "stand", c.id .. " up " .. c.standMs .. " ms after the spawn call")
        done(t2)
    end, "npc still on the floor")
end

local function stageAppearance(t, c, done)
    local z = body(t, c.id)
    local p = K.registry().npcs[c.id].profile
    local hv = z:getHumanVisual()
    local skin = hv:getSkinTexture()
    local n, holes, blood, dirt, patches = K.clothesDamage(z)
    note(t, "appearance", c.id .. " skin=" .. tostring(skin) .. " hair=" .. tostring(hv:getHairModel()) .. " beard="
        .. tostring(hv:getBeardModel()) .. " clothes=" .. n .. " holes=" .. holes .. " blood=" .. blood .. " dirt="
        .. dirt .. " patches=" .. patches .. " bodyBlood=" .. hv:getTotalBlood() .. " wounds="
        .. hv:getBodyVisuals():size() .. " attached=" .. z:getAttachedItems():size())
    t:eq(p.skin, skin, "skin of the profile")
    t:ok(string.find(skin, p.female and "^FemaleBody0[1-5]$" or "^MaleBody0[1-5]$") ~= nil,
        "not a human skin: " .. tostring(skin))
    t:ok(n > 0, "no clothes")
    t:eq(0, holes, "holes")
    t:eq(0, blood, "blood on clothes")
    t:eq(0, dirt, "dirt on clothes")
    t:eq(0, patches, "patches")
    t:eq(0, hv:getTotalBlood(), "blood on the body")
    t:eq(0, K.bodyDirt(hv), "dirt on the body")
    t:eq(0, hv:getBodyVisuals():size(), "wounds and bandages")
    t:eq(0, z:getAttachedItems():size(), "attached items before the weapon")
    done(t)
end

local function stageWeapon(t, c, done)
    local w = M.WEAPON
    local ok, why = K.E().setWeapon(c.id, w.item)
    t:ok(ok, "setWeapon " .. w.item .. ": " .. tostring(why))
    t:sleep(SETTLE_MS, function(t2)
        local s = W.state(body(t2, c.id), w.slot)
        note(t2, "weapon", w.item .. " at rest: " .. W.describe(s))
        t2:eq(w.item, s.slot, "at rest: item at " .. w.slot)
        t2:eq("", s.hand, "at rest: primary hand")
        K.A().setGesture(c.id, "aim")
        t2:sleep(GESTURE_MS, function(t3)
            local z = body(t3, c.id)
            local s3 = W.state(z, w.slot)
            if displaysHere() then
                local info = AN.info(z)
                note(t3, "weapon", w.item .. " aim: " .. W.describe(s3) .. "; " .. AN.describe(info))
                t3:eq(w.item, s3.hand, "aim: primary hand")
                t3:eq(w.item, s3.second, "aim: secondary hand (two-handed)")
                t3:eq("", s3.slot, "aim: slot " .. w.slot .. " not emptied")
                t3:eq(w.weapon, s3.weapon, "aim: variable Weapon")
                t3:ok(has(info.nodes, w.aimNode), "aim: node " .. w.aimNode .. " not live ("
                    .. table.concat(info.nodes, ",") .. ")")
            else
                note(t3, "weapon", w.item .. " aim on " .. side() .. ": copy here " .. W.describe(s3)
                    .. " (hand items are set by each client: screenshots of both clients)")
                t3:eq("aim", K.A().gestureOf(c.id), "aim: gesture")
                t3:eq(w.item, s3.slot, "aim: the authority copy keeps the weapon attached")
            end
            K.A().setGesture(c.id, "idle")
            t3:sleep(SETTLE_MS, function(t4)
                local s4 = W.state(body(t4, c.id), w.slot)
                note(t4, "weapon", w.item .. " back to idle: " .. W.describe(s4))
                t4:eq(w.item, s4.slot, "back to idle: item at " .. w.slot)
                t4:eq("", s4.hand, "back to idle: primary hand")
                done(t4)
            end)
        end)
    end)
end

local function stageGuard(t, c, done)
    local z = body(t, c.id)
    local p = c.player
    -- South of the body, away from the walk (east) and 3 squares or more from the player.
    local v, removeVanilla = K.spawnVanilla(t, z, 0, 3)
    t:sleep(NEIGHBOUR_MS, function(t2)
        local zz = body(t2, c.id)
        note(t2, "guard", "vanilla neighbour after " .. NEIGHBOUR_MS .. " ms: useless " .. tostring(v:isUseless())
            .. ", noTeeth " .. tostring(v:isNoTeeth()) .. ", voice " .. tostring(K.voiceOf(v)) .. ", target player "
            .. tostring(v:getTarget() == p) .. ", state " .. tostring(v:getCurrentStateName()) .. "; npc voice "
            .. tostring(K.voiceOf(zz)) .. ", simulated " .. (K.G().simulatedHere(zz) and "here" or "by a client"))
        checkRest(t2, zz, "npc")
        t2:eq(false, v:isUseless(), "vanilla useless")
        t2:eq(false, v:isNoTeeth(), "vanilla noTeeth")
        t2:ne(K.G().SILENT_VOICE, K.voiceOf(v), "vanilla voice prefix")
        removeVanilla()
        local bd = p:getBodyDamage()
        local h0 = bd:getOverallBodyHealth()
        local start = getTimestampMs()
        local passes0 = K.G().stats.passes
        local seen = { samples = 0, target = 0, attack = 0, eat = 0, minHealth = h0, maxDist = 0 }
        local function sample()
            local b = K.B().find(c.id)
            if b ~= nil then
                seen.samples = seen.samples + 1
                if b:getTarget() ~= nil then seen.target = seen.target + 1 end
                if b:getEatBodyTarget() ~= nil then seen.eat = seen.eat + 1 end
                local st = string.lower(tostring(b:getCurrentStateName()))
                if string.find(st, "attack") or string.find(st, "lunge") then seen.attack = seen.attack + 1 end
                local d = K.D().dist(b:getX(), b:getY(), p:getX(), p:getY())
                if d > seen.maxDist then seen.maxDist = d end
            end
            local h = bd:getOverallBodyHealth()
            if h < seen.minHealth then seen.minHealth = h end
            return getTimestampMs() - start >= CONTACT_MS
        end
        t2:waitUntil(sample, CONTACT_MS + 15000, function(t3)
            note(t3, "guard", "contact " .. CONTACT_MS / 1000 .. " s: health " .. tostring(h0) .. " -> min "
                .. tostring(seen.minHealth) .. ", samples " .. seen.samples .. ", target " .. seen.target
                .. ", attack/lunge " .. seen.attack .. ", eat " .. seen.eat .. ", max distance " .. round(seen.maxDist)
                .. ", guard passes " .. tostring(K.G().stats.passes - passes0))
            t3:eq(false, p:isDead(), "player dead")
            t3:ok(seen.minHealth >= h0 - 0.01, "player health dropped to " .. tostring(seen.minHealth))
            t3:eq(0, seen.attack, "attack or lunge samples")
            t3:eq(0, seen.target, "samples with a target")
            t3:eq(0, seen.eat, "samples with an eat target")
            checkRest(t3, body(t3, c.id), "after the contact")
            done(t3)
        end, "contact period")
    end)
end

-- "move" of the npc to a free square dx squares east of its body with a gesture; done(t, arrival) once closed.
-- Speed = path length sampled every tick / time between the tick before the first move and the last move.
local function stageMove(t, c, gesture, dx, step, done)
    local z = body(t, c.id)
    local sq = K.target(z, dx, 0)
    t:ok(sq ~= nil, "no free target square near " .. dx .. " squares east of the body")
    local goal = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
    local x0, y0 = z:getX(), z:getY()
    local v, why = K.D().moveTo(c.id, goal.x, goal.y, goal.z, gesture)
    t:ok(v ~= nil, "move refused: " .. tostring(why))
    local start = getTimestampMs()
    local tr = { lx = x0, ly = y0, path = 0, prev = start, gesture = false, travel = false }
    local function sample()
        local ms = getTimestampMs()
        local b = K.B().find(c.id)
        if b ~= nil then
            local d = K.D().dist(b:getX(), b:getY(), tr.lx, tr.ly)
            if d > 0.001 then
                if tr.first == nil then tr.first = tr.prev end
                tr.last = ms
                tr.path = tr.path + d
                tr.lx, tr.ly = b:getX(), b:getY()
            end
        end
        tr.prev = ms
        if K.A().gestureOf(c.id) == gesture then tr.gesture = true end
        if K.G().isTravelling(c.id) then tr.travel = true end
        return closed(c.id)()
    end
    t:waitUntil(sample, ARRIVE_MS, function(t2)
        local e = K.D().get(c.id)
        local b = body(t2, c.id)
        local closedMs = getTimestampMs() - start
        local moving = (tr.first ~= nil and tr.last ~= nil) and (tr.last - tr.first) or 0
        local speed = moving > 0 and tr.path / (moving / 1000) or 0
        local straight = K.D().dist(b:getX(), b:getY(), x0, y0)
        local dist = K.D().distToTarget(goal, b:getX(), b:getY(), b:getZ())
        c.speed = c.speed or {}
        c.speed[gesture] = speed
        note(t2, step, gesture .. " to " .. goal.x .. "," .. goal.y .. " (" .. dx .. " squares): " .. tostring(e and e.s)
            .. " in " .. closedMs .. " ms, moving " .. moving .. " ms, path " .. round(tr.path) .. " squares, straight "
            .. round(straight) .. ", speed " .. round(speed) .. " squares/s, distance to target "
            .. tostring(dist and round(dist)) .. ", executed by " .. tostring(e and e.by) .. ", travel flag seen "
            .. tostring(tr.travel))
        t2:eq("arrived", e and e.s, gesture .. ": directive state")
        t2:ok(tr.gesture, gesture .. ": gesture not seen during the trip")
        t2:ok(dist ~= nil and dist <= K.D().ARRIVE + 1, gesture .. ": body " .. tostring(dist) .. " squares from the target")
        t2:ok(speed > 0, gesture .. ": no movement measured")
        done(t2, { x = b:getX(), y = b:getY() })
    end, gesture .. " not finished")
end

local function stageWalk(t, c, done)
    stageMove(t, c, "walk", TRIP, "walk", function(t2a, arrival0)
        local b0 = body(t2a, c.id)
        local remote = not K.G().simulatedHere(b0)
        t2a:sleep(remote and COPY_SYNC_MS or 0, function(t2)
        local bs = body(t2, c.id)
        local arrival = remote and { x = bs:getX(), y = bs:getY() } or arrival0
        if remote then
            note(t2, "stop", "copy simulated by a client: arrival position read " .. COPY_SYNC_MS .. " ms after the "
                .. "report, " .. round(K.D().dist(arrival.x, arrival.y, arrival0.x, arrival0.y))
                .. " squares from the position read at the report")
        end
        t2:sleep(STILL_MS, function(t3)
            local b = body(t3, c.id)
            local moved = K.D().dist(b:getX(), b:getY(), arrival.x, arrival.y)
            local useless = K.G().simulatedHere(b) and tostring(b:isUseless()) or "not checked (simulated by a client)"
            note(t3, "stop", "after the arrival: moved " .. round(moved) .. " squares in " .. STILL_MS .. " ms, gesture "
                .. K.A().gestureOf(c.id) .. ", travel flag " .. tostring(K.G().isTravelling(c.id)) .. ", useless "
                .. useless)
            t3:ok(moved < 0.5, "body moved " .. round(moved) .. " squares after the arrival")
            t3:eq("idle", K.A().gestureOf(c.id), "gesture after the arrival")
            t3:eq(false, K.G().isTravelling(c.id), "travel flag after the arrival")
            if K.G().simulatedHere(b) then t3:eq(true, b:isUseless(), "useless after the arrival") end
            local fv, why = K.D().face(c.id, "S")
            t3:ok(fv ~= nil, "face refused: " .. tostring(why))
            t3:waitUntil(closed(c.id), DONE_MS, function(t4)
                t4:eq("faced", K.D().get(c.id).s, "face: directive state")
                t4:sleep(FACE_MS, function(t5)
                    local a = body(t5, c.id):getDirectionAngle()
                    note(t5, "face", "S: angle " .. round(a) .. " degrees (expected 90)")
                    t5:ok(K.angleGap(a, 90) <= 20, "body faces " .. round(a) .. " degrees, not south (90)")
                    done(t5)
                end)
            end, "face not finished")
        end)
        end)
    end)
end

local function stageRun(t, c, done)
    stageMove(t, c, "run", -TRIP, "run", function(t2)
        local walk, run = c.speed.walk or 0, c.speed.run or 0
        note(t2, "speed", "walk " .. round(walk) .. " squares/s, run " .. round(run) .. " squares/s, ratio "
            .. (walk > 0 and round(run / walk) or "-") .. " (Directives.MAX_SPEED " .. K.D().MAX_SPEED .. ")")
        t2:ok(run < K.D().MAX_SPEED and walk < K.D().MAX_SPEED, "speed above Directives.MAX_SPEED")
        done(t2)
    end)
end

local function stageGestures(t, c, done)
    local w = M.WEAPON
    local function step(tc, i)
        local g = M.GESTURES[i]
        if g == nil then return done(tc) end
        local ok, why = K.A().setGesture(c.id, g)
        tc:ok(ok, "setGesture " .. g .. ": " .. tostring(why))
        tc:sleep(GESTURE_MS, function(t2)
            local z = body(t2, c.id)
            local s = W.state(z, w.slot)
            if displaysHere() then
                local info = AN.info(z)
                note(t2, "gesture", g .. ": " .. AN.describe(info) .. "; " .. W.describe(s))
                t2:eq(g, info.gesture, g .. ": LKGesture")
                t2:ok(has(info.nodes, M.NODES[g]), g .. ": node " .. M.NODES[g] .. " not live ("
                    .. table.concat(info.nodes, ",") .. ")")
                if M.HAND[g] then
                    t2:eq(w.item, s.hand, g .. ": weapon in hand")
                else
                    t2:eq(w.item, s.slot, g .. ": weapon attached")
                end
            else
                note(t2, "gesture", g .. " on " .. side() .. ": wanted " .. K.A().gestureOf(c.id) .. "; copy here "
                    .. W.describe(s) .. " (nodes and hands are read on the clients: LKB.anim)")
                t2:eq(g, K.A().gestureOf(c.id), g .. ": gesture")
            end
            step(t2, i + 1)
        end)
    end
    step(t, 1)
end

local function stageRoundTrip(t, c, done)
    local p = c.player
    local z0 = body(t, c.id)
    local gen0 = K.registry().npcs[c.id].generation
    local ox, oy, oz = p:getX(), p:getY(), p:getZ()
    local bx, by, bz = math.floor(z0:getX()), math.floor(z0:getY()), math.floor(z0:getZ())
    local t0 = getTimestampMs()
    -- Every online player goes (F.movePlayers): a second client left at the spawn kept the npc square loaded on the
    -- server (MP campaign of 2026-10-15, "npc square still loaded" after 60 s).
    F.movePlayers(t, p, ox + K.FAR, oy, oz, function(t2)
        local unloaded = function() return getCell():getGridSquare(bx, by, bz) == nil end
        t2:waitUntil(unloaded, 60000, function(t3)
            local outMs = getTimestampMs() - t0
            local _, state = K.B().find(c.id)
            t3:eq("embodied", state, "registry state while out of the loaded area")
            F.movePlayers(t3, p, ox, oy, oz, function(t4)
                F.waitSquare(t4, bx, by, bz, 30000, function(t5)
                    local back = getTimestampMs()
                    t5:waitUntil(function() return K.B().find(c.id) ~= nil end, 15000, function(t6)
                        local bindMs = getTimestampMs() - back
                        t6:sleep(FACE_MS, function(t7)
                            local z = body(t7, c.id)
                            local tag, gen = K.I().readTag(z:getModData())
                            local s = W.state(z, M.WEAPON.slot)
                            note(t7, "roundtrip", "square unloaded " .. outMs .. " ms after leaving, body bound again "
                                .. bindMs .. " ms after the square came back; same object " .. tostring(z == z0)
                                .. ", tag " .. tostring(tag) .. "#" .. tostring(gen) .. " (registry generation "
                                .. tostring(K.registry().npcs[c.id].generation) .. "), noTeeth " .. tostring(z:isNoTeeth())
                                .. ", voice " .. tostring(K.voiceOf(z)) .. ", weapon " .. W.describe(s))
                            t7:ok(z == z0, "not the same body object after the round trip")
                            t7:eq(c.id, tag, "ModData id after the round trip")
                            t7:eq(gen0, gen, "ModData generation after the round trip")
                            t7:eq(gen0, K.registry().npcs[c.id].generation, "registry generation after the round trip")
                            checkRest(t7, z, "after the round trip")
                            t7:eq(M.WEAPON.item, s.slot, "weapon attached again after the round trip")
                            done(t7)
                        end)
                    end, "npc body not bound again")
                end)
            end)
        end, "npc square still loaded")
    end)
end

-- ---------------------------------------------------------------- tests

-- Test 1: the stages above on one npc, one probe phase per stage.
-- LK02-T08 section 6 (E01-T16), dedicated server only: every client runs its own probe during test 1 (observer and
-- owner cost, pose relay delay: RST.Steps "lk.probe", RST_PeerChecksLK2.lua) and takes a screenshot after the stages
-- of M.SHOTS (Zomboid/Screenshots, collected by the launcher into runs/<run>/client<N>/).
M.SHOTS = { spawn = true, weapon = true, gestures = true }
local function clientStep(t, step, args, ms, after)
    if not isServer() then return after(t) end
    RST.Steps.ask(t, step, args, { target = "all", timeoutMs = ms }, after)
end

local function oneNpc(t, probe)
    local c = spawnNpc(t, 2, 0)
    local key = "milestone-" .. tostring(getTimestampMs())
    local chain = {
        { "spawn", function(tc, done) stageStand(tc, c, function(t2) stageAppearance(t2, c, done) end) end },
        { "weapon", function(tc, done) stageWeapon(tc, c, done) end },
        { "guard", function(tc, done) stageGuard(tc, c, done) end },
        { "walk", function(tc, done) stageWalk(tc, c, done) end },
        { "run", function(tc, done) stageRun(tc, c, done) end },
        { "gestures", function(tc, done) stageGestures(tc, c, done) end },
        { "roundtrip", function(tc, done) stageRoundTrip(tc, c, done) end },
    }
    local function step(tc, i)
        local stage = chain[i]
        if stage == nil then
            stopProbe(tc, probe, "1 npc", 1)
            clientStep(tc, "lk.probe", { phase = "stop", key = key }, 5000, function(tp, res)
                for _, e in ipairs(res and res.list or {}) do
                    for _, line in ipairs(e.data and e.data.lines or {}) do note(tp, "client " .. e.user, line) end
                    if e.data and e.data.relay then note(tp, "client " .. e.user, e.data.relay) end
                end
            end)
            return
        end
        stage[2](tc, function(t2)
            Probe.split(probe, stage[1])
            if not M.SHOTS[stage[1]] then return step(t2, i + 1) end
            clientStep(t2, "rst.shot", { name = "lk-milestone1-" .. stage[1], settleMs = 300 }, 5000, function(t3)
                step(t3, i + 1)
            end)
        end)
    end
    clientStep(t, "lk.probe", { phase = "start", key = key }, 5000, function(ts) step(ts, 1) end)
end

-- Test 2: two npcs wanted on the same square, one weapon each, walking at the same time, then a gesture each.
local function twoNpcs(t, probe)
    local npcs = { spawnNpc(t, 3, 0), spawnNpc(t, 3, 0) }
    local a, b = npcs[1], npcs[2]
    note(t, "two", a.id .. " created in " .. a.spawnMs .. " ms at " .. sqText(a.body) .. ", " .. b.id .. " in "
        .. b.spawnMs .. " ms at " .. sqText(b.body) .. " (both wanted " .. a.want .. ")")
    t:ne(sqText(a.body), sqText(b.body), "both npcs on the same square")
    local both = function() return K.standing(a.id)() and K.standing(b.id)() end
    t:waitUntil(both, K.STAND_MS, function(t2)
        note(t2, "two", "both up " .. (getTimestampMs() - a.t0) .. " ms after the first spawn call")
        local goals = {}
        for i, n in ipairs(npcs) do
            local ok, why = K.E().setWeapon(n.id, M.SECOND[i].item)
            t2:ok(ok, "setWeapon " .. M.SECOND[i].item .. ": " .. tostring(why))
            local sq = K.target(body(t2, n.id), TRIP, 0)
            t2:ok(sq ~= nil, "no free target square for " .. n.id)
            goals[i] = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        end
        Probe.split(probe, "spawn")
        t2:ok(goals[1].x ~= goals[2].x or goals[1].y ~= goals[2].y, "same target square for both npcs")
        local start = getTimestampMs()
        for i, n in ipairs(npcs) do
            local v, why = K.D().moveTo(n.id, goals[i].x, goals[i].y, goals[i].z, "walk")
            t2:ok(v ~= nil, "move " .. n.id .. " refused: " .. tostring(why))
        end
        local arrived = function() return closed(a.id)() and closed(b.id)() end
        t2:waitUntil(arrived, ARRIVE_MS, function(t3)
            local ea, eb = K.D().get(a.id), K.D().get(b.id)
            note(t3, "two", "both moves closed " .. (getTimestampMs() - start) .. " ms after the orders: " .. a.id
                .. " " .. tostring(ea.s) .. ", " .. b.id .. " " .. tostring(eb.s))
            t3:eq("arrived", ea.s, a.id .. ": directive state")
            t3:eq("arrived", eb.s, b.id .. ": directive state")
            Probe.split(probe, "walk")
            for i, n in ipairs(npcs) do K.A().setGesture(n.id, M.SECOND[i].gesture) end
            t3:sleep(GESTURE_MS, function(t4)
                for i, n in ipairs(npcs) do
                    local sc = M.SECOND[i]
                    local z = body(t4, n.id)
                    local st = W.state(z, sc.slot)
                    if displaysHere() then
                        local info = AN.info(z)
                        note(t4, "two", n.id .. " " .. sc.gesture .. ": " .. AN.describe(info) .. "; "
                            .. W.describe(st))
                        t4:eq(sc.gesture, info.gesture, n.id .. ": LKGesture")
                        t4:eq(sc.item, st.hand, n.id .. ": weapon in hand")
                    else
                        note(t4, "two", n.id .. " " .. sc.gesture .. " on " .. side() .. ": copy here "
                            .. W.describe(st))
                        t4:eq(sc.gesture, K.A().gestureOf(n.id), n.id .. ": gesture")
                    end
                    checkRest(t4, z, n.id)
                end
                Probe.split(probe, "gestures")
                stopProbe(t4, probe, "2 npcs", 2)
            end)
        end, "moves of the two npcs not finished")
    end, "npcs still on the floor")
end

-- Test 3: what the run left (ids recorded by tests 1 and 2), then the engine cost with no npc.
local function cleanup(t)
    t:ok(#M.ids > 0, "no npc recorded by the previous tests (run the whole suite)")
    local registry = K.registry()
    local left = {}
    for _, id in ipairs(M.ids) do
        if registry.npcs[id] ~= nil then left[#left + 1] = id .. " in the registry" end
        if K.D().get(id) ~= nil then left[#left + 1] = id .. " directive" end
        if K.E().wantedOf(id) ~= nil then left[#left + 1] = id .. " weapon" end
        if K.A().gestureOf(id) ~= K.A().DEFAULT then left[#left + 1] = id .. " gesture" end
        if K.G().isTravelling(id) then left[#left + 1] = id .. " travel flag" end
        if K.B().bound[id] ~= nil then left[#left + 1] = id .. " bound body" end
    end
    local list = getCell():getZombieList()
    local tagged = 0
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z ~= nil and not z:isDead() and z:hasModData() then
            local tid = K.I().readTag(z:getModData())
            if tid ~= nil and has(M.ids, tid) then tagged = tagged + 1 end
        end
    end
    note(t, "cleanup", #M.ids .. " npc(s) created by the run (" .. table.concat(M.ids, ",") .. "): "
        .. (#left > 0 and table.concat(left, "; ") or "nothing left") .. ", tagged bodies in the cell " .. tagged
        .. ", probe active " .. tostring(Probe.active ~= nil))
    t:eq(0, #left, "left by the run: " .. table.concat(left, "; "))
    t:eq(0, tagged, "tagged bodies left in the cell")
    t:eq(nil, Probe.active, "probe still active")
    withProbe(t, function(t1, probe)
        t1:sleep(IDLE_PROBE_MS, function(t2) stopProbe(t2, probe, "0 npc", 0) end)
    end)
end

RST.suite("lk.milestone1", { tags = { "world", "server" }, testTimeoutMs = 360000, timeoutMs = 900000 }, function(s)
    s.test("one npc: spawn, appearance, weapon, guard, walk, run, gestures, round trip", function(t)
        loaded(t)
        M.ids = {}
        withProbe(t, oneNpc)
    end, { timeoutMs = 360000 })

    s.test("two npcs on the same wanted square: both up, armed, walking together", function(t)
        loaded(t)
        withProbe(t, twoNpcs)
    end, { timeoutMs = 180000 })

    s.test("cleanup: nothing left by the run; engine cost with no npc", function(t)
        loaded(t)
        cleanup(t)
    end, { timeoutMs = 30000 })
end)

return M
