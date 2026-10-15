--[[
RST_LKHelpers - helpers shared by the Living Knox suites of the development mod (RST.LKHelpers). Development mod
only. Load with: require "RST/RST_LKHelpers". At load time: definitions, and the client step K.PROBE_STEP.

    local K = RST.LKHelpers
    K.B() K.G() K.A() K.E() K.D() K.I()  LivingKnox.Bodies, ZombieGuard, Anim, Equipment, Directives, Identity
                                         (nil when the module is not loaded on this side)
    K.registry()                         registry table of LivingKnox.Store (nil before its init)
    K.round(v)                           v rounded to 2 decimals
    K.angleGap(a, b)                     difference of two angles in degrees, in [0, 180]
    K.standing(id)                       condition for t:waitUntil: the body of npc id is bound and not on the floor
    K.voiceOf(z)                         voice prefix of a character (descriptor), or nil
    K.spawnVanilla(t, anchor, dx, dy)    ordinary zombie (outfit K.VANILLA_OUTFIT) at anchor + (dx, dy) (anchor: a
                                         player or a body), removed by t:defer when still alive; returns the zombie
                                         and a function removing it at once (idempotent)
    K.diedOf(z)                          true once a zombie of K.spawnVanilla died (kept past the reuse of the
                                         Java object, 5 s after it leaves the world)
    K.target(z, dx, dy)                  free square near (body + dx, dy) (LivingKnox.Bodies.findFreeSquare), or nil
    K.hideOtherPlayersFrom(t, gid, user) players other than the account user hidden from group gid (test only)
    K.unlockDoorsNear(t, anchor, r)      locked doors and windows within r squares unlocked for the test (locked
                                         again at the end); returns their number
    K.clothesDamage(body)                count, holes, blood, dirt, patches summed over the item visuals of a body
    K.bodyDirt(hv)                       dirt of a HumanVisual summed over the blood body parts
    K.measurer(prefix)                   function(text) printing "<prefix> measure <text>"
    K.clearHome(t, home, after, opts)    dedicated server: online players standing in the building of home (or next
                                         to the home square) moved to free outdoor squares near it, back at the end
                                         (F.movePlayer and its t:defer); then after(t). Solo: after(t) at once
    K.clearZombiesNear(t, x, y, z, r)    vanilla zombies within r squares removed before a scene (noted)
    K.invisibleClients(t, after)         server: every online player invisible to zombies (client admin command), visible
                                         again at the end; then after(t)
    K.probeZombies(ids, tag)             server: every MP client prints what its copy of each zombie (onlineIds ids)
                                         does (step lk.zprobe, not awaited: diagnostic lines in the client console)
]]

require "RST/RST"

RST.LKHelpers = RST.LKHelpers or {}
local K = RST.LKHelpers

K.STAND_MS = 20000          -- a reanimated corpse lies on the floor first
K.FAR = 300                 -- squares: beyond the loaded area (13 to 19 chunks of 8 squares)
K.VANILLA_OUTFIT = "Generic01"

function K.B() return LivingKnox and LivingKnox.Bodies end
function K.G() return LivingKnox and LivingKnox.ZombieGuard end
function K.A() return LivingKnox and LivingKnox.Anim end
function K.E() return LivingKnox and LivingKnox.Equipment end
function K.D() return LivingKnox and LivingKnox.Directives end
function K.I() return LivingKnox and LivingKnox.Identity end
function K.registry() return LivingKnox and LivingKnox.Store and LivingKnox.Store.data() end

function K.round(v) return math.floor(v * 100 + 0.5) / 100 end

-- Angle difference in degrees, in [0, 180].
function K.angleGap(a, b)
    local d = (a - b) - math.floor((a - b) / 360) * 360
    if d > 180 then d = 360 - d end
    return d
end

function K.standing(id)
    return function()
        local z = K.B().find(id)
        return z ~= nil and not z:isOnFloor()
    end
end

function K.voiceOf(z)
    local d = z:getDescriptor()
    return d and d:getVoicePrefix() or nil
end

-- Zombies created by K.spawnVanilla that died (OnZombieDead), keyed by the Java object. A dead or removed IsoZombie
-- is reset and reused 5 s after it leaves the world (VirtualZombieManager.update -> reuseZombie: isDead false again,
-- ModData cleared): a test that reads isDead() on a reference kept longer misses the death (MP campaign of
-- 2026-10-14, lk.zombies: the first zombie killed was alive again when the second died) and its cleanup must not
-- remove the reused object.
K.died = K.died or {}
K.spawned = K.spawned or {}

function K.diedOf(z)
    return K.died[z] == true or z:isDead()
end

if not K._deadSubscribed and type(Events) == "table" and Events.OnZombieDead ~= nil then
    Events.OnZombieDead.Add(function(z)
        local H = RST.LKHelpers
        if H.spawned[z] then H.died[z] = true end
    end)
    K._deadSubscribed = true
end

-- Ordinary zombie (no tag) at anchor + (dx, dy) (anchor: player or body), removed at the end. Returns the zombie
-- and a function that removes it at once (once; the cleanup then does nothing). Its death is remembered
-- (K.diedOf), the object being reused 5 s later.
function K.spawnVanilla(t, anchor, dx, dy)
    local list = addZombiesInOutfit(math.floor(anchor:getX()) + dx, math.floor(anchor:getY()) + dy,
        math.floor(anchor:getZ()), 1, K.VANILLA_OUTFIT, 50)
    t:ok(list ~= nil and list:size() == 1, "vanilla zombie not created")
    local z = list:get(0)
    K.spawned[z] = true
    K.died[z] = nil
    local removed = false
    local function remove()
        if removed then return end
        removed = true
        if not K.died[z] and not z:isDead() then
            -- Dedicated server: the client that simulates the zombie is told too (LivingKnox.Zombies.tellBodyGone):
            -- otherwise its copy stays and walks on, and the server takes it back from its packets (MP pass of
            -- 2026-10-15: a zombie "removed" by lk.defense kept the test group of lk.repair in alert for 5 min).
            local Zm = LivingKnox and LivingKnox.Zombies
            if Zm ~= nil and Zm.tellBodyGone ~= nil then
                pcall(Zm.tellBodyGone, { o = z:getOnlineID(), x = z:getX(), y = z:getY(), z = z:getZ() })
            end
            z:removeFromWorld()
            z:removeFromSquare()
        end
        K.spawned[z], K.died[z] = nil, nil
    end
    t:defer(remove, "remove the vanilla zombie")
    return z, remove
end

-- Vanilla zombies (not npc bodies) within r squares of x, y on level z removed before a scene, as K.spawnVanilla's
-- remover does (client copy told on a server): MP pass of 2026-10-15 12:15, two zombies left by the previous suite
-- killed the npc of lk.windowlure through the glass. Returns their number (noted on the test).
function K.clearZombiesNear(t, x, y, z, r)
    local Zm = LivingKnox and LivingKnox.Zombies
    local list = getCell():getZombieList()
    local gone = {}
    for i = 0, list:size() - 1 do
        local zb = list:get(i)
        if zb ~= nil and not zb:isDead() and math.floor(zb:getZ()) == z and math.abs(zb:getX() - x) <= r
            and math.abs(zb:getY() - y) <= r and (Zm == nil or Zm.isVanilla(zb)) then
            gone[#gone + 1] = zb
        end
    end
    for _, zb in ipairs(gone) do
        if Zm ~= nil and Zm.tellBodyGone ~= nil then
            pcall(Zm.tellBodyGone, { o = zb:getOnlineID(), x = zb:getX(), y = zb:getY(), z = zb:getZ() })
        end
        zb:removeFromWorld()
        zb:removeFromSquare()
    end
    if #gone > 0 then t:note(#gone .. " vanilla zombie(s) removed around " .. x .. "," .. y .. " before the scene") end
    return #gone
end

-- Loot of the npc id marked as built (LivingKnox.Loot: mark MD_BUILT on its body, the same mark the module sets so
-- that it never builds twice): a suite that sets the ammo itself keeps exactly that ammo (seen in game on 2026-10-12:
-- lk.ranged gave 3 rounds, then the loot added a magazine and 8 rounds and the npc fired 23 times).
function K.noLoot(id)
    local L, z = LivingKnox.Loot, LivingKnox.Bodies.find(id)
    if L ~= nil and L.MD_BUILT ~= nil and z ~= nil then z:getModData()[L.MD_BUILT] = L.VERSION end
end

-- Players hidden from the perception of the members of group gid until the end of the test (t:defer): the target
-- player stands in the home of the test group, where a visible player is an unknown intruder and raises an alert that
-- comes before every need in the cascade (seen in game on 2026-10-12: lk.meals blocked by an "intruder" alert).
function K.hidePlayersFrom(t, gid)
    local E = LivingKnox
    local perceived = E.Senses.perceived
    E.Senses.perceived = function(id)
        local per = perceived(id)
        if per ~= nil and E.Groups.findNpc(id) == gid then
            local out = {}
            for k, v in pairs(per) do out[k] = v end   -- copy: the perception given may be kept by its owner
            out.p = {}
            return out
        end
        return per
    end
    t:defer(function() E.Senses.perceived = perceived end, "players visible again to group " .. gid)
end

-- Every player but the target (username keep) hidden from the perception of the members of group gid until the end
-- of the test: with a second MP client standing in the same house, a test group saw two players and fought the
-- other one (MP campaign of 2026-10-14, lk.warn: a first-strike group shot the second client). No effect in solo.
function K.hideOtherPlayersFrom(t, gid, keep)
    local E = LivingKnox
    local perceived = E.Senses.perceived
    E.Senses.perceived = function(id)
        local per = perceived(id)
        if per ~= nil and E.Groups.findNpc(id) == gid then
            local out = {}
            for k, v in pairs(per) do out[k] = v end
            local rows = {}
            for _, e in ipairs(per.p or {}) do
                if e.u == keep then rows[#rows + 1] = e end
            end
            out.p = rows
            return out
        end
        return per
    end
    t:defer(function() E.Senses.perceived = perceived end, "other players visible again to group " .. gid)
end

-- Free square seen from anchor (clear line of sight, LivingKnox.Senses.lineOfSight), at minD..maxD squares, same
-- floor; squares of the anchor's building first. Returns dx, dy from the anchor's square, or nil.
function K.squareInView(anchor, minD, maxD)
    local cell = getCell()
    local ax, ay, az = math.floor(anchor:getX()), math.floor(anchor:getY()), math.floor(anchor:getZ())
    local asq = cell:getGridSquare(ax, ay, az)
    local adef = asq and asq:getBuildingDef()
    local bid = adef and adef:getIDString() or nil
    local inside, outside
    for d = minD, maxD do
        for dy = -d, d do
            for dx = -d, d do
                if math.max(math.abs(dx), math.abs(dy)) == d then
                    local sq = cell:getGridSquare(ax + dx, ay + dy, az)
                    if sq ~= nil and sq:isFree(false) and not sq:HasStairs()
                        and LivingKnox.Senses.lineOfSight(ax, ay, az, ax + dx, ay + dy, az) == "Clear" then
                        local def = sq:getBuildingDef()
                        local same = bid ~= nil and def ~= nil and def:getIDString() == bid
                        if same and inside == nil then inside = { dx, dy } end
                        if outside == nil then outside = { dx, dy } end
                    end
                end
            end
        end
        if inside ~= nil then break end
    end
    local pick = inside or outside
    if pick == nil then return nil end
    return pick[1], pick[2]
end

-- Ordinary zombie created on a free square seen from anchor, at minD..maxD squares (K.squareInView: a zombie behind
-- a wall is neither seen nor heard while it stands still). Same return values as K.spawnVanilla; skips the test when
-- no such square exists.
function K.spawnVanillaInView(t, anchor, minD, maxD)
    local dx, dy = K.squareInView(anchor, minD, maxD)
    if dx == nil then t:skip("no free square in view of the member at " .. minD .. " to " .. maxD .. " squares") end
    return K.spawnVanilla(t, anchor, dx, dy)
end

-- Doors (IsoDoor) and windows (IsoWindow, not perma-locked) locked within r squares of the anchor, same level,
-- unlocked until the end of the test (t:defer locks them again; door state sent with sync on a server). A home door
-- left locked by the group of an earlier suite (members lock it behind them) left a lone test npc with no exit but a
-- locked window (MP campaign of 2026-10-14, lk.executor). Returns the number of openings unlocked.
function K.unlockDoorsNear(t, anchor, r)
    local cell = getCell()
    local ax, ay, az = math.floor(anchor:getX()), math.floor(anchor:getY()), math.floor(anchor:getZ())
    local doors = {}
    for dy = -r, r do
        for dx = -r, r do
            local sq = cell:getGridSquare(ax + dx, ay + dy, az)
            local objs = sq and sq:getObjects() or nil
            if objs ~= nil then
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if instanceof(o, "IsoDoor") and (o:isLocked() or o:isLockedByKey()) then
                        o:setLockedByKey(false, false)
                        o:setIsLocked(false)
                        if isServer() then o:sync() end
                        doors[#doors + 1] = o
                    elseif instanceof(o, "IsoWindow") and o:isLocked() and not o:isPermaLocked() then
                        o:setIsLocked(false)   -- authority state read by the npc route (LK_Obstacles.decideWindow)
                        doors[#doors + 1] = o
                    end
                end
            end
        end
    end
    if #doors > 0 then
        t:defer(function()
            for _, o in ipairs(doors) do
                if o:getObjectIndex() ~= -1 and not o:IsOpen() then
                    if instanceof(o, "IsoDoor") then
                        o:setLockedByKey(true, false)
                        if isServer() then o:sync() end
                    else
                        o:setIsLocked(true)
                    end
                end
            end
        end, #doors .. " door(s) or window(s) locked again")
    end
    return #doors
end

-- Free target square near (body + dx, dy), or nil.
function K.target(z, dx, dy)
    return K.B().findFreeSquare(math.floor(z:getX()) + dx, math.floor(z:getY()) + dy, math.floor(z:getZ()))
end

local function parts()
    local out = {}
    for i = 0, BloodBodyPartType.MAX:index() - 1 do out[#out + 1] = BloodBodyPartType.FromIndex(i) end
    return out
end

-- Holes, blood, dirt and patches summed over the clothes of a body (item visuals of its worn items).
function K.clothesDamage(body)
    local items = body:getItemVisuals()
    local holes, blood, dirt, patches = 0, 0, 0, 0
    for i = 0, items:size() - 1 do
        local iv = items:get(i)
        holes = holes + iv:getHolesNumber()
        blood = blood + iv:getTotalBlood()
        patches = patches + iv:getBasicPatchesNumber()
        for _, part in ipairs(parts()) do
            dirt = dirt + iv:getDirt(part)
            patches = patches + iv:getDenimPatch(part) + iv:getLeatherPatch(part)
        end
    end
    return items:size(), holes, blood, dirt, patches
end

function K.bodyDirt(hv)
    local dirt = 0
    for _, part in ipairs(parts()) do dirt = dirt + hv:getDirt(part) end
    return dirt
end

function K.measurer(prefix)
    return function(text)
        print(prefix .. " measure " .. tostring(text))
    end
end

-- Players are solid: on a dedicated server the requester and the second client stand in the spawn house, where the
-- test groups get their home, and npcs of the group walk into them (campaign MP 2026-10-15, lk.routines: sentry and
-- sleeper "stuck: no approach at 10656.5,10137.x" for 25 s next to the players in the hall, sentry never at its
-- post). Every online player standing in the building of the home (or within one square of the home square) is moved
-- to a free outdoor square 3 to CLEAR_RADIUS squares away (one per player, two squares apart), still in the loaded
-- area; F.movePlayer moves him back at the end of the test. Solo: the suites place the player themselves.
K.CLEAR_RADIUS = 20

local function inHome(sq, home, bid)
    if sq == nil or sq:getZ() ~= home.z then return false end
    if math.abs(sq:getX() - home.x) <= 1 and math.abs(sq:getY() - home.y) <= 1 then return true end
    local def = sq:getBuildingDef()
    return bid ~= nil and def ~= nil and def:getIDString() == bid
end

local function outdoorSpots(home, n, opts)
    local cell = getCell()
    local spots = {}
    local away = opts ~= nil and opts.away or nil   -- { dx, dy }: only squares on that side of the home
    for r = (opts ~= nil and opts.minR) or 3, K.CLEAR_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                local side = away == nil or dx * away[1] + dy * away[2] >= r
                if #spots < n and side and (math.abs(dx) == r or math.abs(dy) == r) then
                    local sq = cell:getGridSquare(home.x + dx, home.y + dy, home.z)
                    if sq ~= nil and sq:getBuildingDef() == nil and sq:isOutside() and sq:isFree(false) then
                        local apart = true
                        for _, o in ipairs(spots) do
                            if math.abs(o:getX() - sq:getX()) + math.abs(o:getY() - sq:getY()) < 2 then apart = false end
                        end
                        if apart then spots[#spots + 1] = sq end
                    end
                end
            end
        end
        if #spots >= n then break end
    end
    return spots
end

-- opts (optional): { away = { dx, dy }, minR = n }: the free outdoor squares are taken on the side (dx, dy) of the
-- home only, at least minR squares away (lk.windowkill: players out of the zombie's side of the house).
function K.clearHome(t, home, after, opts)
    local solo = not isServer() or (RST.Steps ~= nil and RST.Steps.isSolo ~= nil and RST.Steps.isSolo())
    if solo or type(getOnlinePlayers) ~= "function" then return after(t) end
    local hsq = getCell():getGridSquare(home.x, home.y, home.z)
    local hdef = hsq ~= nil and hsq:getBuildingDef() or nil
    local bid = hdef ~= nil and hdef:getIDString() or nil
    local movers = {}
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        if p ~= nil and not p:isDead() and inHome(p:getCurrentSquare(), home, bid) then movers[#movers + 1] = p end
    end
    if #movers == 0 then return after(t) end
    local spots = outdoorSpots(home, #movers, opts)
    if #spots < #movers then
        t:note("players left in the home: " .. #spots .. " free outdoor square(s) for " .. #movers .. " player(s)")
        return after(t)
    end
    local i = 0
    local function nextMove(tt)
        i = i + 1
        if i > #movers then return after(tt) end
        local sq = spots[i]
        tt:note("player " .. tostring(movers[i]:getUsername()) .. " moved out of the home to " .. sq:getX() .. ","
            .. sq:getY() .. "," .. sq:getZ() .. " (players are solid)")
        -- RST.Fixtures: loaded by every suite that calls clearHome (not required here: the helpers load alone).
        return RST.Fixtures.movePlayer(tt, movers[i], sq:getX(), sq:getY(), sq:getZ(), nextMove)
    end
    return nextMove(t)
end

-- Diagnostic probe of zombies on the MP clients (step K.PROBE_STEP, answers not awaited): each client prints, in its
-- own console (RST_Steps line "PASS lk.zprobe #n: ..."), what its copy of each zombie of onlineId list ids does: state,
-- simulated here or remote, target, hearing multiplier, position. Server: K.probeZombies(ids, tag) sends it to every
-- online player and returns the number of sends; elsewhere it does nothing (solo: the authority already sees).
K.PROBE_STEP = "lk.zprobe"
K.INVISIBLE_STEP = "lk.invisible"
K.probeSeq = K.probeSeq or 900000

local function probeOne(o)
    local list = getCell() and getCell():getZombieList() or nil
    for i = 0, (list and list:size() or 0) - 1 do
        local z = list:get(i)
        if z ~= nil and z:getOnlineID() == o then
            local tg = z:getTarget()
            local W = getWorldSoundManager and getWorldSoundManager() or nil
            local hm = W ~= nil and W:getHearingMultiplier(z) or -1
            return string.format("z:%d %s at %.1f,%.1f state %s target %s hearing %.2f useless %s onfloor %s", o,
                z:isRemoteZombie() and "remote" or "simulated here", z:getX(), z:getY(),
                tostring(z:getActionStateName()), tg ~= nil and tostring(tg) or "none", hm, tostring(z:isUseless()),
                tostring(z:isOnFloor()))
        end
    end
    return "z:" .. tostring(o) .. " not here"
end

-- Registered once RST_Steps is loaded (the suites require it; this file does not, so that it loads alone): at load
-- time when it is already there, else at OnGameStart.
function K.registerProbe()
    if RST.Steps == nil or RST.Steps.on == nil then return false end
    -- Invisible to zombies on every machine (dedicated server): the server cannot send it (setInvisible on its copy
    -- stays there; sendPlayerExtraInfo is the client's), the admin command /invisible does (InvisibleCommand:
    -- setInvisible, setGhostMode, ExtraInfo to all). The poll ends when the local player shows the wanted state.
    RST.Steps.on(K.INVISIBLE_STEP, function(args)
        local on = args.on == true
        local p = getPlayer()
        if p == nil then return RST.Steps.skip("no local player") end
        if p:isInvisible() ~= on then SendCommandToServer("/invisible " .. (on and "-true" or "-false")) end
        return function(ctx)
            local q = getPlayer()
            if q ~= nil and q:isInvisible() == on then
                return RST.Steps.pass("invisible " .. tostring(on))
            end
            if ctx.final then return RST.Steps.fail("still invisible " .. tostring(q and q:isInvisible())) end
            return nil
        end
    end)
    RST.Steps.on(K.PROBE_STEP, function(args)
        local rows = {}
        for _, o in ipairs(type(args.ids) == "table" and args.ids or {}) do rows[#rows + 1] = probeOne(o) end
        local p = getPlayer()
        local me = p ~= nil and string.format("player at %.1f,%.1f invisible %s", p:getX(), p:getY(),
            tostring(p:isInvisible())) or "no player"
        return RST.Steps.pass(tostring(args.tag) .. ": " .. table.concat(rows, "; ") .. "; " .. me)
    end)
    return true
end

if not K.registerProbe() and type(Events) == "table" and Events.OnGameStart ~= nil then
    Events.OnGameStart.Add(function() RST.LKHelpers.registerProbe() end)
end

-- Dedicated server: every online player made invisible to zombies by its own client (step K.INVISIBLE_STEP, admin
-- command /invisible), visible again at the end of the test (t:defer, not awaited); then after(t). Solo or no
-- client: after(t) at once (solo: the suites set it on the local player themselves).
function K.invisibleClients(t, after)
    if not isServer() or RST.Steps == nil or RST.Steps.ask == nil then return after(t) end
    t:defer(function()
        local list = getOnlinePlayers()
        for i = 0, (list and list:size() or 0) - 1 do
            local p = list:get(i)
            if p ~= nil then
                K.probeSeq = K.probeSeq + 1
                sendServerCommand(p, RST.Steps.MODULE, "ask", { seq = K.probeSeq, step = K.INVISIBLE_STEP,
                    args = { on = false }, ms = 5000 })
            end
        end
    end, "players visible again")
    RST.Steps.ask(t, K.INVISIBLE_STEP, { on = true }, { target = "all", timeoutMs = 10000 }, function(t2)
        return after(t2)
    end)
end

function K.probeZombies(ids, tag)
    if not isServer() or type(getOnlinePlayers) ~= "function" or RST.Steps == nil then return 0 end
    local list = getOnlinePlayers()
    local n = 0
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        if p ~= nil then
            K.probeSeq = K.probeSeq + 1
            sendServerCommand(p, RST.Steps.MODULE, "ask", { seq = K.probeSeq, step = K.PROBE_STEP,
                args = { ids = ids, tag = tag }, ms = 2000 })
            n = n + 1
        end
    end
    return n
end

return K
