--[[
lk.windowlure - a vanilla zombie outside sees a Living Knox npc behind a bare window, comes to the window and thumps
it (LK06-T08, server/LivingKnox/LK_Zombies.lua: lure noise with no source, server/LivingKnox/LK_Combat.lua: no
strike through the glass). Tag "world": the authority only, on a save named rstest*, with a player (t.ctx.player)
within SEARCH squares of an outer window that is closed, intact, not barricaded and without a closed curtain (the
suite moves him next to such a window of a nearby house by itself, RST.Places, solo); the Living Knox option Enabled
must be on. Solo: RST.run({ suite = "lk.windowlure", tags = "world" }).
Asynchronous run only (up to about 90 s).

Automated (real Java objects, on the authority):
    window     the player is made invisible to zombies and protected by god mode (both restored at the end); an
               unarmed npc is spawned on the inside square of the nearest such window, then one ordinary zombie
               DISTANCE squares outside, in front of the window. Within WAIT_MS the zombie must thump the window
               (action state "thump", or the glass broken) from a square next to it. Checked: at least one lure noise
               emitted, no zombie attack on the npc while the glass held.
Dedicated server: the thump is the one the client that simulates the zombie reports at that window
(LivingKnox.Senses.thumpOf); the server copy never shows "thump". The client player is not made invisible by the
server (setInvisible on the server copy is not sent): the zombie may also see him through the glass.
Figures are printed as "[LKW] measure ..." lines. The npc is forgotten and the zombie removed with t:defer; the glass
may stay broken (rstest save only).

Manual checks (docs/annexes/conception/zombies.md, "Protocole en jeu"): closed curtain or barricade of 3 planks: the zombie
does not come; npc walking outside: zombies around come to its footsteps.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"

require "RST/RST_Places"

local K = RST.LKHelpers
local B = K.B
local measure = K.measurer("[LKW]")
local SEARCH = 8
local DISTANCE = 6
local WAIT_MS = 60000

local function Zm() return LivingKnox and LivingKnox.Zombies end

-- Nearest outer window around the player or the square p (anything with getX/getY/getZ): { w, inside = square,
-- outside = square, dx, dy (outward) } or nil.
local function findWindow(p, search)
    search = search or SEARCH
    local cell = getCell()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local best, bestD = nil, nil
    for x = px - search, px + search do
        for y = py - search, py + search do
            local sq = cell:getGridSquare(x, y, pz)
            local list = sq ~= nil and sq:getSpecialObjects() or nil
            if list ~= nil then
                for i = 0, list:size() - 1 do
                    local w = list:get(i)
                    if instanceof(w, "IsoWindow") and not w:IsOpen() and not w:isDestroyed()
                        and not w:isBarricaded() then
                        local a, b = w:getSquare(), w:getOppositeSquare()
                        if a ~= nil and b ~= nil and (a:getRoom() == nil) ~= (b:getRoom() == nil) then
                            local inside = a:getRoom() ~= nil and a or b
                            local outside = inside == a and b or a
                            local d = math.abs(x - px) + math.abs(y - py)
                            if bestD == nil or d < bestD then
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

local function seesThrough(o)
    local r = tostring(LosUtil.lineClear(getCell(), o.outside:getX() + o.dx * (DISTANCE - 1),
        o.outside:getY() + o.dy * (DISTANCE - 1), o.inside:getZ(), o.inside:getX(), o.inside:getY(),
        o.inside:getZ(), false))
    return r == "ClearThroughWindow", r
end

-- Square to stand on, inside, 2 or 3 squares from a see-through outer window that is the nearest window from there
-- (the one the test takes), searched up to 20 squares from the player; or nil. The inside square of the window must
-- take the npc body (LivingKnox.Bodies.freeSquare: walkable, no plant or campfire next to it): otherwise the body is
-- created on the nearest free square, which may be the OUTSIDE square of the window (in-game run of 2026-10-13: npc
-- outside, attacked by the zombie, no thump). Never next to it: the player standing there would push the body away.
local function insideFree(o)
    local Bo = B()
    if Bo ~= nil and Bo.freeSquare ~= nil then return Bo.freeSquare(o.inside) end
    return o.inside:isFree(false)
end

local function lureSpot(p)
    local o = findWindow(p, 20)
    if o == nil or not seesThrough(o) or not insideFree(o) then return nil end
    for k = 3, 2, -1 do
        local q = getCell():getGridSquare(o.inside:getX() - o.dx * k, o.inside:getY() - o.dy * k, o.inside:getZ())
        if q ~= nil and q:isFree(false) and q:getRoom() == o.inside:getRoom() then
            local o2 = findWindow(q)
            if o2 ~= nil and o2.w == o.w then return q end
        end
    end
    return nil
end

RST.suite("lk.windowlure", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 180000 }, function(s)
    s.test("zombie outside comes to a bare window and thumps it", function(t)
        t:ok(B() ~= nil and Zm() ~= nil and Zm().lureRadius ~= nil,
            "LivingKnox.Zombies (LK06-T08) is not loaded on this side")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no anchor player (t.ctx.player)")
        RST.Places.ensure(t, { name = "house with a see-through outer window", spot = lureSpot,
            building = function(def) return def:isResidential() end }, function(t, spot) -- luacheck: ignore 432
        -- The window seen from the square given (the player is not moved when his place is accepted as is).
        local o = findWindow(spot)
        if o == nil then t:skip("no closed, intact, unbarricaded outer window within " .. SEARCH .. " squares") end
        local clear, res = seesThrough(o)
        if not clear then t:skip("the window is not see-through from outside (" .. tostring(res) .. ")") end
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the player")
        if p.setInvisible ~= nil and p.isInvisible ~= nil then
            local wasInvisible = p:isInvisible()
            p:setInvisible(true)
            t:defer(function() p:setInvisible(wasInvisible) end, "restore the visibility of the player")
        end
        local id, body = B().spawn({}, o.inside:getX(), o.inside:getY(), o.inside:getZ())
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
        measure("window inside " .. o.inside:getX() .. "," .. o.inside:getY() .. " outward " .. o.dx .. "," .. o.dy
            .. ", npc created at " .. math.floor(body:getX()) .. "," .. math.floor(body:getY()))
        t:ok(math.floor(body:getX()) == o.inside:getX() and math.floor(body:getY()) == o.inside:getY(),
            "npc not created on the inside square of the window")
        -- Dedicated server: the clients invisible to zombies (K.invisibleClients), the lure is then what brings it.
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2x) K.invisibleClients(t2x, function(t2)
            local npcBody = B().find(id)
            K.clearZombiesNear(t2, o.inside:getX(), o.inside:getY(), o.inside:getZ(), 20)
            local z = K.spawnVanilla(t2, npcBody, o.dx * (DISTANCE + 1), o.dy * (DISTANCE + 1))
            local st0 = { lures = Zm().stats.lures, attacks = Zm().stats.attacks }
            local t0 = getTimestampMs()
            local thumps, brokeAt = 0, nil
            local attacksWhileIntact = 0
            local function nearWindow()
                return math.abs(math.floor(z:getX()) - o.outside:getX()) <= 1
                    and math.abs(math.floor(z:getY()) - o.outside:getY()) <= 1
            end
            -- Dedicated server (MP pass of 2026-10-15 11:23: zombie 0.5 square from the glass for 40 s, server copy
            -- "idle"): the copy of the server never enters "thump" (ThumpPacket only relayed to the other clients);
            -- the thump is the one reported by the client that simulates the zombie (LivingKnox.Senses.thumpOf,
            -- LK06-T11), at this window.
            local function reportedThump()
                local S = LivingKnox.Senses
                if not isServer() or S == nil or S.thumpOf == nil or S.windowAt == nil then return false end
                local r = S.thumpOf(z:getOnlineID())
                return r ~= nil and rawequal(S.windowAt(r.x, r.y, r.z, r.k), o.w)
            end
            -- Every 10 s: where the zombie stands and what it does (solo campaign of 2026-10-15: FAIL without any
            -- figure of the zombie's way).
            local nextDiag = t0 + 10000
            t2:waitUntil(function()
                if getTimestampMs() >= nextDiag then
                    nextDiag = nextDiag + 10000
                    local tg = z:getTarget()
                    measure(string.format("waiting %d s: zombie %s at %.1f,%.1f state %s, target %s, thump target %s, "
                        .. "lures %d, window open %s smashed %s; npc at %s", math.floor((getTimestampMs() - t0) / 1000),
                        K.diedOf(z) and "dead" or "alive", z:getX(), z:getY(), tostring(z:getActionStateName()),
                        tg ~= nil and tostring(tg) or "none", tostring(z:getThumpTarget()),
                        Zm().stats.lures - st0.lures, tostring(o.w:IsOpen()), tostring(o.w:isSmashed()),
                        (function()
                            local nb = B().find(id)
                            return nb and string.format("%.1f,%.1f", nb:getX(), nb:getY()) or "?"
                        end)()))
                    K.probeZombies({ z:getOnlineID(), npcBody:getOnlineID() }, "windowlure")
                end
                if not o.w:isDestroyed() then
                    -- Attacks on THIS npc only (contacts of its id; MP campaign of 2026-10-15: the global counter
                    -- also took the attacks of a zombie left by the previous suite on another npc).
                    local n = 0
                    for _, ct in pairs(Zm().contacts) do
                        if ct.id == id then n = n + (ct.n or 0) end
                    end
                    if n > attacksWhileIntact then attacksWhileIntact = n end
                elseif brokeAt == nil then
                    brokeAt = getTimestampMs() - t0
                end
                if nearWindow() and (z:getActionStateName() == "thump" or reportedThump()) then thumps = thumps + 1 end
                return thumps > 0 or (brokeAt ~= nil and nearWindow())
            end, WAIT_MS, function(t3)
                measure("lures " .. (Zm().stats.lures - st0.lures) .. ", thumps seen " .. thumps .. ", glass broken "
                    .. tostring(brokeAt ~= nil) .. ", time " .. (getTimestampMs() - t0) .. " ms, zombie attacks while "
                    .. "the glass held " .. attacksWhileIntact)
                t3:ok(Zm().stats.lures - st0.lures >= 1, "no lure noise emitted")
                t3:eq(0, attacksWhileIntact, "zombie attacks on the npc through the glass")
            end, "the zombie did not thump the window in " .. WAIT_MS .. " ms")
        end) end, "npc still on the floor")
        end)
    end)
end)
