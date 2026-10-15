--[[
lk.guard - Living Knox body neutralisation (LK02-T04, LivingKnox.ZombieGuard). Tags "world" and "server": the
authority only, on a save named rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.guard", tags = "world" }); dedicated server: RST.server({ suite = "lk.guard",
tags = "world" }) from an admin client. Asynchronous run only (about 3 minutes; do not pause the game).

What is measured here, on the authority:
    - a vanilla zombie next to the npc keeps its behaviour (no useless, no noTeeth, its own voice prefix; whether it
      targets the player is logged), removed at the end of the test;
    - 60 s at contact with the npc: no target, no attack or lunge state, no eating, player health unchanged;
    - after a round trip out of the loaded area the guard flags are back on the bound body.
On a dedicated server the voice is not checked (voices are played and cut by each client): the voice of the
other clients and the owner-side flags are checked by hand (protocol in docs/conception/neutralisation.md).
E01-T16 (LK02-T04): on a dedicated server with a second client, that client is moved 2 squares from a standing npc
and samples, on its own machine and for 60 s, the copy of the npc and its own player (RST.Steps "lk.contact",
RST_PeerChecksLK2.lua): no target on it, no attack or lunge state, no eating, its health unchanged, contact kept.
Figures are printed as "[LKG] measure ..." lines. Every test removes its npc and its vanilla zombie with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksLK2"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local CONTACT_MS = 60000
local NEIGHBOUR_MS = 3000
local FAR = K.FAR

local function B() return LivingKnox and LivingKnox.Bodies end
local function G() return LivingKnox and LivingKnox.ZombieGuard end

local function measure(text)
    print("[LKG] measure " .. tostring(text))
end

local function lower(s) return string.lower(tostring(s)) end

local function spawnNpc(t, dx, dy)
    t:ok(B() ~= nil and G() ~= nil, "LivingKnox.Bodies or LivingKnox.ZombieGuard is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id, body, p
end

local spawnVanilla, standing, voiceOf = K.spawnVanilla, K.standing, K.voiceOf

-- Guard flags expected on the bound body at rest, on this side (the voice only where voices are played).
local function checkRest(t, z, what)
    t:eq(true, z:isNoTeeth(), what .. ": noTeeth")
    if G().simulatedHere(z) then
        t:eq(true, z:isUseless(), what .. ": useless")
        t:eq(nil, z:getTarget(), what .. ": target")
        t:eq(nil, z:getEatBodyTarget(), what .. ": eat target")
    end
    if LivingKnox.hasLocalPlayer() then
        t:eq(G().SILENT_VOICE, voiceOf(z), what .. ": voice prefix")
    end
end

RST.suite("lk.guard", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 600000 }, function(s)
    s.test("guard flags on the npc; the vanilla neighbour keeps its own behaviour", function(t)
        local id, body, p = spawnNpc(t, 2, 0)
        local v = spawnVanilla(t, body, 4, 0) -- from the body: findFreeSquare may have moved it
        t:sleep(NEIGHBOUR_MS, function(t2)
            local z = B().find(id)
            t2:ok(z ~= nil, "npc body lost")
            checkRest(t2, z, "npc")
            t2:eq(false, v:isUseless(), "vanilla useless")
            t2:eq(false, v:isNoTeeth(), "vanilla noTeeth")
            t2:ne(G().SILENT_VOICE, voiceOf(v), "vanilla voice prefix")
            local target = v:getTarget()
            measure("vanilla neighbour after " .. NEIGHBOUR_MS .. " ms: target player " .. tostring(target == p)
                .. ", state " .. tostring(v:getCurrentStateName()) .. ", voice " .. tostring(voiceOf(v))
                .. "; npc " .. id .. " voice " .. tostring(voiceOf(z)) .. ", owner "
                .. tostring(G().simulatedHere(z) and "here" or "a client") .. ", body " .. tostring(body == z))
        end)
    end)

    s.test("60 s at contact: no target, no attack, no eating, player unhurt", function(t)
        -- 2 squares away: a standing player next to the body keeps it on the floor (isBeingSteppedOn).
        local id, _, p = spawnNpc(t, 2, 0)
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local bd = p:getBodyDamage()
            local h0 = bd:getOverallBodyHealth()
            local start = getTimestampMs()
            local passes0 = G().stats.passes
            local seen = { samples = 0, target = 0, attack = 0, eat = 0, minHealth = h0, maxDist = 0 }
            local function sample()
                local z = B().find(id)
                if z ~= nil then
                    seen.samples = seen.samples + 1
                    if z:getTarget() ~= nil then seen.target = seen.target + 1 end
                    if z:getEatBodyTarget() ~= nil then seen.eat = seen.eat + 1 end
                    local st = lower(z:getCurrentStateName())
                    if string.find(st, "attack") or string.find(st, "lunge") then seen.attack = seen.attack + 1 end
                    local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d > seen.maxDist then seen.maxDist = d end
                end
                local h = bd:getOverallBodyHealth()
                if h < seen.minHealth then seen.minHealth = h end
                return getTimestampMs() - start >= CONTACT_MS
            end
            t2:waitUntil(sample, CONTACT_MS + 15000, function(t3)
                measure("contact 60 s: health " .. tostring(h0) .. " -> min " .. tostring(seen.minHealth)
                    .. ", samples " .. seen.samples .. ", target " .. seen.target .. ", attack/lunge " .. seen.attack
                    .. ", eat " .. seen.eat .. ", max distance " .. tostring(math.floor(seen.maxDist * 100) / 100)
                    .. ", guard passes " .. tostring(G().stats.passes - passes0))
                t3:eq(false, p:isDead(), "player dead")
                t3:ok(seen.minHealth >= h0 - 0.01, "player health dropped to " .. tostring(seen.minHealth))
                t3:eq(0, seen.attack, "attack or lunge samples")
                t3:eq(0, seen.target, "samples with a target")
                t3:eq(0, seen.eat, "samples with an eat target")
                t3:ok(B().find(id) ~= nil, "npc body disappeared")
            end, "contact period")
        end, "npc still on the floor")
    end, { timeoutMs = 120000 })

    -- LK02-T04 (E01-T16): the same minute at contact, lived by the SECOND client on its own copy of the body.
    s.test("60 s at contact on the second client: no target, no attack, no eating, unhurt", function(t)
        if not isServer() then t:skip("needs a dedicated server and a second client (MP campaign)") end
        local others = RST.Steps.others(t)
        if #others == 0 then t:skip("no second client online (MP campaign, --clients 2)") end
        local peer = RST.Steps.playerOf(others[1])
        local id = spawnNpc(t, 2, 0)
        t:waitUntil(standing(id), STAND_MS, function(t2)
            local z = B().find(id)
            local sq = K.target(z, 0, 2) or K.target(z, 0, -2)
            t2:ok(sq ~= nil, "no free square 2 squares from the npc for the second client")
            RST.Fixtures.movePlayer(t2, peer, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), function(t3)
                RST.Steps.ask(t3, "lk.contact", { npc = id, ms = CONTACT_MS, maxDist = 4 },
                    { target = { others[1] }, timeoutMs = CONTACT_MS + 15000 }, function(t4, res)
                        local e = res.by[others[1]]
                        measure("second client " .. others[1] .. " at contact: " .. tostring(e and e.message))
                        t4:ok(B().find(id) ~= nil, "npc body disappeared")
                    end)
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 120000 })

    s.test("guard flags back after a round trip out of the loaded area", function(t)
        local F = RST.Fixtures
        local id, body, p = spawnNpc(t, 2, 2)
        local ox, oy, oz = p:getX(), p:getY(), p:getZ()
        local bx, by, bz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
        F.movePlayers(t, p, ox + FAR, oy, oz, function(t2)
            local unloaded = function() return getCell():getGridSquare(bx, by, bz) == nil end
            t2:waitUntil(unloaded, 60000, function(t3)
                F.movePlayers(t3, p, ox, oy, oz, function(t4)
                    F.waitSquare(t4, bx, by, bz, 30000, function(t5)
                        t5:waitUntil(function() return B().find(id) ~= nil end, 15000, function(t6)
                            -- Bound again: the guard reapplies within one pass.
                            t6:sleep(1000, function(t7)
                                local z = B().find(id)
                                t7:ok(z ~= nil, "npc body lost")
                                checkRest(t7, z, "after the round trip")
                                measure("round trip: same object " .. tostring(z == body) .. ", onlineId "
                                    .. tostring(z:getOnlineID()) .. ", voice " .. tostring(voiceOf(z)))
                            end)
                        end, "npc body not bound again")
                    end)
                end)
            end, "npc square still loaded")
        end)
    end, { timeoutMs = 180000 })
end)
