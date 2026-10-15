--[[
lk.windowkill - window offensive of Living Knox npcs (LK06-T09, server/LivingKnox/LK_Defense.lua point 7,
LK_Combat.lua and LK_Zombies.lua floor strikes): a vanilla zombie thumps a closed window of the home of a test group;
an able member opens it with the player gesture, the zombie climbs through and falls inside, the members finish it
on the floor. Tags "world" and "server": the authority only, on a save named rstest*, with a player (t.ctx.player)
standing INSIDE a house that has, within SEARCH squares, an outer window that is closed, intact, not barricaded,
without a closed curtain, over solid ground, and not alarmed; the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.windowkill", tags = "world" }). Asynchronous run only (about 1 to 3 minutes).

What is done (the player is protected by god mode, made invisible to zombies and hidden from the perception of the
test group):
    - a test group "settlers" (two fighters with a baseball bat, one worker) gets its home on the player's square
      (no furnishing: LivingKnox.Homes.skip); its members get bodies; the home is surveyed (posts, LK05-T03);
    - the engagement range of the test members is 0 until the zombie lies inside (LivingKnox.Zombies.engageRange
      wrapped, then restored: the members finish the fallen zombie with their usual range): no sally (LK06-T14) nor
      free fight (LK06-T04) against the zombie on its way to the glass, which would kill it outside before any thump
      (in-game runs of 2026-10-14 MP and 2026-10-15 solo: members out through the door next to the window, zombie
      killed 4 squares out within 10 s); the zombie may thump another window of the home than the lured one (solo
      run of 2026-10-15): the window of the offensive is followed from then on;
    - one ordinary zombie is created DISTANCE squares out of the nearest such window: it sees the npcs through the
      glass, comes and thumps the window (LK06-T08); as the members may stand out of its sight (night posts, beds),
      a sound without source on the inside square of the window is repeated until the offensive starts; the alert
      starts the home defense ("hold");
    - checked in order: a window offensive at that window (Defense.get(gid).offense), the window opened by an npc,
      the zombie on the floor inside the house, the zombie killed with at least one floor hit
      (LivingKnox.Zombies.stats.floorHits) before it got up, the offensive over and the window closed again by a
      member (LK06-T11: closewindow gesture, Defense.stats.windowsClosed);
    - LK06-T11, measured when the zombie is killed: one impact sound entry sent per applied melee hit
      (LivingKnox.Combat.stats.meleeSounds) and, in solo (sounds played on this machine, LivingKnox.CombatView), as
      many impacts played (BaseballBatHit with the bat) and at least as many swings (BaseballBatSwing).
Figures are printed as "[LKX] measure ..." lines. Cleanup (t:defer): zombie, bodies and test group removed,
perception, visibility and god mode restored (rstest save only).
LK06-T11, multiplayer: the zombie is simulated by a client; the server learns the window it thumps only from the
report of that client (Defense.stats.thumpReported, LivingKnox.Senses.stats.thumps, printed while waiting).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"

local K = RST.LKHelpers
local measure = K.measurer("[LKX]")

local SEARCH = 8            -- squares around the player: outer window searched
local DISTANCE = 5          -- squares out of the window: the zombie is created there
local LURE_RADIUS = 18      -- source-less sound on the inside square of the window: radius and volume. MP pass of
                            -- 2026-10-15 (1 run in 3 failed): with the sandbox Hearing "random" (5), the copy of the
                            -- client that simulates the zombie may have Poor hearing (x 0.45, drawn on each machine):
                            -- radius 12 reached 5.4 squares only, the zombie 5 squares out (x 1.68 indoors/outdoors)
                            -- never heard it; 18 x 0.45 = 8.1 > 5 x 1.3
local LURE_EVERY_MS = 4000  -- repeated until the window offensive starts
local BODIES_MS = 60000     -- materialization of the three members
local POSTS_MS = 30000      -- home survey done
local INSIDE_MS = 30000     -- members back inside the house before the zombie is created (not a failure past it)
local OFFENSE_MS = 90000    -- zombie at the window, defense and offensive started
local OPEN_MS = 30000       -- window opened by an npc
local FALL_MS = 20000       -- zombie on the floor inside
local KILL_MS = 40000       -- zombie killed
local END_MS = 40000        -- offensive over, window closed again (LK06-T11, Defense.CFG.OFFENSE_CLOSE_MS 20 s)

local function LK() return LivingKnox end
local function Df() return LivingKnox.Defense end

local function memberNpcs(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    if g == nil then return out end
    for mid, m in pairs(g.members) do
        if m.npc ~= nil then out[mid] = m.npc end
    end
    return out
end

local function bodyCount(gid)
    local n = 0
    for _, npc in pairs(memberNpcs(gid)) do
        if LK().Bodies.find(npc) ~= nil then n = n + 1 end
    end
    return n
end

local function allStanding(gid)
    for _, npc in pairs(memberNpcs(gid)) do
        if not K.standing(npc)() then return false end
    end
    return true
end

-- Nearest outer window of the player's building: { w, inside, outside, dx, dy (outward) } or nil.
local function findWindow(p)
    local cell = getCell()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local def = p:getCurrentSquare() and p:getCurrentSquare():getBuildingDef() or nil
    local best, bestD = nil, nil
    for x = px - SEARCH, px + SEARCH do
        for y = py - SEARCH, py + SEARCH do
            local sq = cell:getGridSquare(x, y, pz)
            local list = sq ~= nil and sq:getSpecialObjects() or nil
            if list ~= nil then
                for i = 0, list:size() - 1 do
                    local w = list:get(i)
                    if instanceof(w, "IsoWindow") and not w:IsOpen() and not w:isDestroyed() and not w:isBarricaded()
                        and not w:isPermaLocked() then
                        local a, b = w:getSquare(), w:getOppositeSquare()
                        if a ~= nil and b ~= nil and (a:getRoom() == nil) ~= (b:getRoom() == nil) then
                            local inside = a:getRoom() ~= nil and a or b
                            local outside = inside == a and b or a
                            local d = math.abs(x - px) + math.abs(y - py)
                            if inside:getBuildingDef() == def and outside:TreatAsSolidFloor()
                                and (bestD == nil or d < bestD) then
                                bestD = d
                                best = { w = w, inside = inside, outside = outside,
                                    dx = outside:getX() - inside:getX(), dy = outside:getY() - inside:getY() }
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Machine that simulates a zombie (or an npc body): account of the owner connection, "server" when the server does.
local function ownerOf(z)
    if z == nil then return "?" end
    local p = z.getOwnerPlayer ~= nil and z:getOwnerPlayer() or nil
    if p ~= nil then return tostring(p:getUsername()) end
    return isServer() and "server" or "local"
end

local function membersOwners(gid)
    local parts = {}
    local npcs = memberNpcs(gid)
    local mids = {}
    for mid in pairs(npcs) do mids[#mids + 1] = mid end
    table.sort(mids)
    for _, mid in ipairs(mids) do parts[#parts + 1] = mid .. "=" .. ownerOf(LK().Bodies.find(npcs[mid])) end
    return table.concat(parts, " ")
end

-- LK06-T11: last window reported as thumped by the client that simulates zombie z (server), as text.
local function lastThump(z)
    local S = LK().Senses
    local r = S ~= nil and S.thumpOf ~= nil and S.thumpOf(z:getOnlineID()) or nil
    if r == nil then return "none" end
    return string.format("%d,%d,%d,%s by %s %d ms ago", r.x, r.y, r.z, r.k, tostring(r.by), getTimestampMs() - r.ms)
end

local function describe(gid)
    local parts = {}
    local npcs = memberNpcs(gid)
    local mids = {}
    for mid in pairs(npcs) do mids[#mids + 1] = mid end
    table.sort(mids)
    for _, mid in ipairs(mids) do
        local npc = npcs[mid]
        local body = LK().Bodies.find(npc)
        local o = LK().Combat and LK().Combat.get(npc) or nil
        parts[#parts + 1] = string.format("%s at %s gesture %s combat %s", mid,
            body and string.format("%.1f,%.1f", body:getX(), body:getY()) or "?", LK().Anim.shownOf(npc),
            o and (tostring(o.u) .. " " .. tostring(o.phase)) or "-")
    end
    return table.concat(parts, "; ")
end

RST.suite("lk.windowkill", { tags = { "world", "server" }, testTimeoutMs = 360000, timeoutMs = 420000 }, function(s)
    s.test("zombie at a window: window opened by an npc, zombie on the floor inside, finished on the floor",
        function(t)
        local E = LK()
        t:ok(E ~= nil and E.Defense ~= nil and E.Defense.updateOffense ~= nil and E.Zombies ~= nil,
            "LivingKnox.Defense (LK06-T09) is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local o = findWindow(p)
        if o == nil then t:skip("no closed, intact, unbarricaded outer window within " .. SEARCH .. " squares") end
        if E.Obstacles ~= nil and E.Obstacles.alarmArmed ~= nil and E.Obstacles.alarmArmed(o.w) then
            t:skip("the window belongs to an alarmed house")
        end
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the player")
        if p.setInvisible ~= nil and p.isInvisible ~= nil then
            local wasInvisible = p:isInvisible()
            p:setInvisible(true)
            t:defer(function() p:setInvisible(wasInvisible) end, "restore the visibility of the player")
        end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST window kill", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end
        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "farmer" }, { "fighter", "guard" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        K.hidePlayersFrom(t, gid)
        local removers = {}
        local st0 = { floor = E.Zombies.stats.floorHits or 0, kills = E.Zombies.stats.kills or 0,
            opened = E.Defense.stats.windowsOpened or 0, closed = E.Defense.stats.windowsClosed or 0 }
        local function sounds()   -- LK06-T11
            local v = E.CombatView
            return { applied = E.Combat.stats.applied or 0, sent = E.Combat.stats.meleeSounds or 0,
                swings = v and v.stats.meleeSwings or 0, impacts = v and v.stats.meleeImpacts or 0 }
        end
        local snd0 = sounds()
        t:defer(function()
            for _, remove in ipairs(removers) do remove() end
            E.Alert.forget(gid)
            E.Defense.forgetGroup(gid)
            local npcs = memberNpcs(gid)
            for _, npc in pairs(npcs) do
                if E.Combat then E.Combat.disengage(npc, "suite lk.windowkill over") end
            end
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove group " .. gid)
        t:note(string.format("group %s home %d,%d,%d window inside %d,%d outward %d,%d", gid, home.x, home.y, home.z,
            o.inside:getX(), o.inside:getY(), o.dx, o.dy))
        t:waitUntil(function()
            return bodyCount(gid) == 3 and allStanding(gid)
        end, BODIES_MS, function(t2)
            for _, mid in ipairs({ "m-1", "m-3" }) do
                local npc = memberNpcs(gid)[mid]
                if npc ~= nil and E.Equipment and E.Equipment.setWeapon then E.Equipment.setWeapon(npc, "Base.BaseballBat") end
            end
            local engage = E.Zombies.engageRange
            local ours = {}
            for _, npc in pairs(memberNpcs(gid)) do ours[npc] = true end
            E.Zombies.engageRange = function(npcId, role)
                if npcId ~= nil and ours[npcId] then return 0 end
                return engage(npcId, role)
            end
            local function restoreEngage() E.Zombies.engageRange = engage end
            t:defer(restoreEngage, "restore Zombies.engageRange")
            -- The sentry keeps its post inside (no round out of the house): on a round it walks out by a door, the
            -- zombie follows it to that door, and the member back at the door post keeps the door open (MP campaign
            -- of 2026-10-15: zombie fought at the open door, no window offensive). Restored at the end.
            local sentryKind = E.Routines.sentryKind
            E.Routines.sentryKind = function() return "guard" end
            t:defer(function() E.Routines.sentryKind = sentryKind end, "restore Routines.sentryKind")
            local defOf = sq:getBuildingDef()
            local function allInside()
                for _, npc in pairs(memberNpcs(gid)) do
                    local b = E.Bodies.find(npc)
                    local bs = b ~= nil and b:getCurrentSquare() or nil
                    if bs == nil or bs:getBuildingDef() ~= defOf then return false end
                end
                return true
            end
            -- Dedicated server: the clients stand in the spawn house, the home of the group (MP pass of 2026-10-15
            -- 11:29: the member sent to open the window stuck 30 s against the player at 10656.5,10137.5, "window not
            -- opened in time"). They are moved out, on the side of the house away from the window (K.clearHome).
            -- The clients are also made invisible to zombies (K.invisibleClients; setInvisible on the server copy
            -- is not sent: MP pass of 2026-10-15 11:44, the zombie went for the moved player instead of the window).
            K.clearHome(t2, home, function(t2a) K.invisibleClients(t2a, function(t2b)
            t2b:waitUntil(function()
                local live = G.state.data.groups[gid]
                local posts = live and E.Routines.ensurePosts(gid, live) or nil
                return posts ~= nil
            end, POSTS_MS, function(t3a)
              local insideFrom = getTimestampMs()
              t3a:waitQuiet(function() return allInside() or getTimestampMs() - insideFrom >= INSIDE_MS end,
                INSIDE_MS + 5000, function(t3)
                measure(string.format("members inside the house before the zombie: %s; %s", tostring(allInside()),
                    describe(gid)))
                K.clearZombiesNear(t3, o.inside:getX(), o.inside:getY(), o.inside:getZ(), 20)
                local z, remove = K.spawnVanilla(t3, o.outside, o.dx * (DISTANCE - 1), o.dy * (DISTANCE - 1))
                removers[#removers + 1] = remove
                local t0 = getTimestampMs()
                measure(string.format("zombie created at %.1f,%.1f,%d", z:getX(), z:getY(), math.floor(z:getZ())))
                local function off()
                    local plan = Df().get(gid)
                    return plan and plan.offense or nil
                end
                -- The members may all stand out of the zombie's sight (night posts and beds, in-game run of
                -- 2026-10-13: no lure at all): a sound without source on the inside square of the window, every
                -- LURE_EVERY_MS until the offensive starts, brings the zombie along its vanilla path to the glass
                -- (a source-less sound: a zombie source would be ignored by every zombie).
                local lastLure = nil
                local function lure()
                    local now = getTimestampMs()
                    if lastLure ~= nil and now - lastLure < LURE_EVERY_MS then return end
                    lastLure = now
                    addSound(nil, o.inside:getX(), o.inside:getY(), o.inside:getZ(), LURE_RADIUS, LURE_RADIUS)
                end
                local nextDiag = t0 + 10000
                t3:waitUntil(function()
                    if off() ~= nil then return true end
                    lure()
                    if getTimestampMs() >= nextDiag then   -- what happened at the window, in the failure case too
                        nextDiag = nextDiag + 10000
                        K.probeZombies({ z:getOnlineID() }, string.format("windowkill %d s",
                            math.floor((getTimestampMs() - t0) / 1000)))   -- what the owner's copy does (MP)
                        local plan = Df().get(gid)
                        measure(string.format("waiting %d s: window open %s smashed %s; zombie %s at %.1f,%.1f "
                            .. "state %s; defense %s; %s", math.floor((getTimestampMs() - t0) / 1000),
                            tostring(o.w:IsOpen()), tostring(o.w:isSmashed()), K.diedOf(z) and "dead" or "alive",
                            z:getX(), z:getY(), tostring(z:getActionStateName()),
                            plan and (tostring(plan.id) .. " " .. tostring(plan.phase)) or "none", describe(gid)))
                        measure(string.format("thump target: here %s, reported %d (accepted %d, dropped %d); "
                            .. "simulated by: zombie %s, members %s; last report for zombie %s: %s",
                            tostring(z:getThumpTarget()),
                            E.Defense.stats.thumpReported or 0, E.Senses and E.Senses.stats.thumps or 0,
                            E.Senses and E.Senses.stats.thumpsDropped or 0, ownerOf(z), membersOwners(gid),
                            tostring(z:getOnlineID()), lastThump(z)))
                    end
                    return false
                end, OFFENSE_MS, function(t4)
                    local f = off()
                    local plan = Df().get(gid)
                    measure(string.format("offensive %s by %s (%s) after %d ms; defense %s %s; thump seen %s; %s",
                        f.key, f.mid, f.state, getTimestampMs() - t0, plan.id, plan.phase,
                        tostring(z:getActionStateName()), describe(gid)))
                    t4:eq("hold", plan.phase, "defense phase against one zombie")
                    -- Window of the offensive (key x,y,z,N|W), which may differ from the lured one.
                    local kx, ky, kz, kk = string.match(f.key, "^(%-?%d+),(%-?%d+),(%-?%d+),([NW])$")
                    local ow = kx ~= nil and E.Senses.windowAt(tonumber(kx), tonumber(ky), tonumber(kz), kk) or nil
                    t4:ok(ow ~= nil, "window of the offensive " .. tostring(f.key) .. " not found")
                    if not rawequal(ow, o.w) then measure("offensive at another window than the lured one: " .. f.key) end
                    t4:waitUntil(function() return ow:IsOpen() end, OPEN_MS, function(t5)
                        measure(string.format("window opened after %d ms (windows opened %d); %s",
                            getTimestampMs() - t0, (E.Defense.stats.windowsOpened or 0) - st0.opened, describe(gid)))
                        t5:ok((E.Defense.stats.windowsOpened or 0) > st0.opened, "the window was not opened by an npc")
                        local function inside()
                            local zs = z:getCurrentSquare()
                            return zs ~= nil and zs:getBuildingDef() ~= nil
                        end
                        t5:waitUntil(function()
                            return K.diedOf(z) or (z:isOnFloor() and inside())
                        end, FALL_MS, function(t6)
                            restoreEngage()   -- zombie on the floor inside: the members close in to finish it
                            measure(string.format("zombie %s at %.1f,%.1f after %d ms (state %s); %s",
                                K.diedOf(z) and "dead" or "on the floor", z:getX(), z:getY(), getTimestampMs() - t0,
                                tostring(z:getActionStateName()), describe(gid)))
                            local gotUp = false
                            t6:waitUntil(function()
                                if not K.diedOf(z) and not z:isOnFloor() and inside() then gotUp = true end
                                return K.diedOf(z)
                            end, KILL_MS, function(t7)
                                local floor = (E.Zombies.stats.floorHits or 0) - st0.floor
                                measure(string.format("zombie killed after %d ms: floor hits %d, kills %d, got up "
                                    .. "before %s; %s", getTimestampMs() - t0, floor,
                                    (E.Zombies.stats.kills or 0) - st0.kills, tostring(gotUp), describe(gid)))
                                t7:ok(floor >= 1, "no floor hit on the zombie")
                                local snd = sounds()
                                local applied = snd.applied - snd0.applied
                                local last = E.CombatView and E.CombatView.lastMelee or {}
                                measure(string.format("melee sounds: hits applied %d, impacts sent %d, played here: "
                                    .. "swings %d, impacts %d (last swing %s, last impact %s)", applied,
                                    snd.sent - snd0.sent, snd.swings - snd0.swings, snd.impacts - snd0.impacts,
                                    tostring(last.sw), tostring(last.hit)))
                                t7:eq(applied, snd.sent - snd0.sent, "impact entries sent = melee hits applied")
                                if E.CombatView ~= nil then
                                    t7:eq(applied, snd.impacts - snd0.impacts, "impacts played here = hits applied")
                                    t7:ok(snd.swings - snd0.swings >= applied, "fewer swings than hits played here")
                                end
                                t7:waitUntil(function() return off() == nil end, END_MS, function(t8)
                                    local closed = (E.Defense.stats.windowsClosed or 0) - st0.closed
                                    measure(string.format("offensive over: window open %s, closed by an npc %d, "
                                        .. "close gestures %d, waits %d, given up %d; %s", tostring(ow:IsOpen()),
                                        closed, E.Defense.stats.closeGestures or 0, E.Defense.stats.closeWaits or 0,
                                        E.Defense.stats.closeGivenUp or 0, describe(gid)))
                                    t8:ok(not ow:IsOpen(), "window not closed again after the offensive")
                                    t8:eq(1, closed, "window closed by an npc")
                                end, "offensive not over after the kill")
                            end, "zombie not killed")
                        end, "zombie not on the floor inside")
                    end, "window not opened")
                end, "no window offensive (zombie not at the window, or defense not started)")
              end)
            end, "home not surveyed")
            end) end, { away = { -o.dx, -o.dy }, minR = 6 })
        end, "group members not materialized and standing")
    end)
end)
