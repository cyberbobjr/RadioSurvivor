--[[
lk.windowsally - a zombie that thumps a window of a Living Knox home is killed OUTSIDE by a member who goes out to it
(E18-T34, decision of the user of 2026-11-07, replacing the window offensive of lk.windowkill: server/LivingKnox/
LK_Defense.lua points 4 and 7, sally of LK06-T14 joining a zombie seen behind the glass through a door). Tags "world"
and "server": the authority only, on a save named rstest*, with a player (t.ctx.player) standing INSIDE a house that
has, within SEARCH squares, an outer window that is closed, intact, not barricaded, without a closed curtain, over
solid ground, and not alarmed; the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.windowsally", tags = "world" }). MP:
    python tools/autoclient/autoclient.py --mp --clients 1 --server-suite lk.windowsally --server-tags world

What is done (the player is protected by god mode, made invisible to zombies and hidden from the perception of the
test group): a test group "settlers" (two fighters with a baseball bat, one worker) gets its home on the player's
square (no furnishing: LivingKnox.Homes.skip); its members get bodies; the home is surveyed (posts, LK05-T03); one
ordinary zombie is created DISTANCE squares out of the nearest such window, a sound without source on the inside
square of the window bringing it to the glass. Checked: the zombie killed by the members (LivingKnox.Zombies.stats.kills)
within KILL_MS, on a square outside the house, the window never opened, then every member back inside within BACK_MS.
Figures are printed as "[LKX] measure ..." lines. Cleanup (t:defer): zombie, bodies and test group removed,
perception, visibility and god mode restored (rstest save only).
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
local KILL_MS = 120000      -- zombie killed by the members (sally out of the door, LK06-T14)
local BACK_MS = 60000       -- members back inside after the kill

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

RST.suite("lk.windowsally", { tags = { "world", "server" }, testTimeoutMs = 300000, timeoutMs = 360000 }, function(s)
    s.test("zombie thumping a window of the home: a member goes out, kills it outside, comes back", function(t)
        local E = LK()
        t:ok(E ~= nil and E.Defense ~= nil and E.Zombies ~= nil, "LivingKnox.Defense is not loaded on this side")
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
        local g = assert(G.create({ type = "settlers", name = "RST window sally", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end
        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "farmer" }, { "fighter", "guard" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        K.hidePlayersFrom(t, gid)
        -- Empty stock on the test site: supply objective; an expedition would take a member away before the zombie
        -- comes (MP campaign of 2026-11-08: m-2 left with "trip 1", never back inside). The test group stays home.
        local Ex = E.Expeditions
        local tryDepart = Ex and Ex.tryDepart or nil
        if tryDepart ~= nil then
            Ex.tryDepart = function(id, minute)
                if id == gid then return nil, "test group of lk.windowsally stays home" end
                return tryDepart(id, minute)
            end
            t:defer(function() Ex.tryDepart = tryDepart end, "restore Expeditions.tryDepart")
        end
        local removers = {}
        local kills0 = E.Zombies.stats.kills or 0
        t:defer(function()
            for _, remove in ipairs(removers) do remove() end
            E.Alert.forget(gid)
            E.Defense.forgetGroup(gid)
            local npcs = memberNpcs(gid)
            for _, npc in pairs(npcs) do
                if E.Combat then E.Combat.disengage(npc, "suite lk.windowsally over") end
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
            local defOf = sq:getBuildingDef()
            local function allInside()
                for _, npc in pairs(memberNpcs(gid)) do
                    local b = E.Bodies.find(npc)
                    local bs = b ~= nil and b:getCurrentSquare() or nil
                    if bs == nil or bs:getBuildingDef() ~= defOf then return false end
                end
                return true
            end
            -- Dedicated server: the clients stand in the spawn house, the home of the group; they are moved out, on
            -- the side of the house away from the window (K.clearHome), and made invisible to zombies.
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
                -- A sound without source on the inside square of the window brings the zombie to the glass (the
                -- members may stand out of its sight), every LURE_EVERY_MS until it is killed.
                local lastLure = nil
                local function lure()
                    local now = getTimestampMs()
                    if lastLure ~= nil and now - lastLure < LURE_EVERY_MS then return end
                    lastLure = now
                    addSound(nil, o.inside:getX(), o.inside:getY(), o.inside:getZ(), LURE_RADIUS, LURE_RADIUS)
                end
                local deathOutside, nextDiag = nil, t0 + 10000
                -- Checked at every pass (MP campaign of 2026-11-08: window opened then closed again within 7 s).
                local everOpen = false
                t3:waitUntil(function()
                    if o.w:IsOpen() then everOpen = true end
                    if K.diedOf(z) then
                        if deathOutside == nil then
                            local zs = getCell():getGridSquare(math.floor(z:getX()), math.floor(z:getY()),
                                math.floor(z:getZ()))
                            deathOutside = zs == nil or zs:getBuildingDef() ~= defOf
                        end
                        return true
                    end
                    lure()
                    if getTimestampMs() >= nextDiag then
                        nextDiag = nextDiag + 10000
                        local plan = Df().get(gid)
                        measure(string.format("waiting %d s: zombie at %.1f,%.1f state %s; window open %s smashed %s; "
                            .. "defense %s; simulated by: zombie %s, members %s; %s",
                            math.floor((getTimestampMs() - t0) / 1000), z:getX(), z:getY(),
                            tostring(z:getActionStateName()), tostring(o.w:IsOpen()), tostring(o.w:isSmashed()),
                            plan and (tostring(plan.id) .. " " .. tostring(plan.phase)) or "none", ownerOf(z),
                            membersOwners(gid), describe(gid)))
                    end
                    return false
                end, KILL_MS, function(t4)
                    measure(string.format("zombie killed after %d ms, outside %s, kills %d; window open %s (ever %s) "
                        .. "smashed %s; %s",
                        getTimestampMs() - t0, tostring(deathOutside), (E.Zombies.stats.kills or 0) - kills0,
                        tostring(o.w:IsOpen()), tostring(everOpen), tostring(o.w:isSmashed()), describe(gid)))
                    t4:ok((E.Zombies.stats.kills or 0) > kills0, "zombie not killed by the members")
                    t4:ok(deathOutside == true, "zombie killed inside the house (the members did not go out)")
                    t4:ok(not everOpen and not o.w:IsOpen(), "window opened by a member")
                    t4:waitUntil(function()
                        if o.w:IsOpen() then everOpen = true end
                        return allInside()
                    end, BACK_MS, function(t5)
                        measure("members back inside after " .. (getTimestampMs() - t0) .. " ms; " .. describe(gid))
                        t5:ok(allInside(), "members not back inside")
                        t5:ok(not everOpen, "window opened by a member on the way back")
                    end, "members not back inside after the kill")
                end, "zombie not killed by the members (no sally)")
              end)
            end, "home not surveyed")
            end) end, { away = { -o.dx, -o.dy }, minR = 6 })
        end, "group members not materialized and standing")
    end)
end)
