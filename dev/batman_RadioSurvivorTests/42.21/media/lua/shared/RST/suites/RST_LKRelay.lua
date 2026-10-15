--[[
lk.relay - gesture relay to the clients, delay and range filter (LK03-T05, LivingKnox.Relay on the server,
LivingKnox.Anim on the clients). Tags "world" and "server". Dedicated server with two clients (autoclient --mp
--clients 2): RST.server({ suite = "lk.relay", tags = "world" }); solo: SKIP (no relay, the only machine reads the
gesture directly); one client: SKIP. Asynchronous run only (about 1 minute).

    delay   the second client stands GAP squares from an npc; for each gesture of GESTURES, it arms a watcher
            (step lk.gesture.watch, RST_PeerChecksLK.lua), then the server sets the gesture (LivingKnox.Anim.setGesture)
            and notes the server clock (GameTime.getServerTimeMills); the client answers the first tick at which its
            relayed gesture (Anim.gestureOf) is the new one, on its synchronised server clock (step lk.gesture.seen).
            Accepted (plan): every gesture seen in less than DELAY_MS (300 ms on a local network; the clients run on
            the server's machine, so this is the delay of the relay and of the frames, not of a real network);
    range   the second client is moved FAR squares away (beyond Directives.NEAR_RADIUS, 100): once the relay no longer
            lists it for that npc (Relay.near), a new gesture is set: the requester still gets relay messages, the
            second client gets none (Relay.stats.byClient) and its gesture for that npc stays unchanged (step
            lk.gesture.not): traffic follows the players near the npc, not the number of players.
Figures: "[LKR] measure ..." lines. The npc is forgotten, its gesture set back and the player moved back with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecksLK"

local K = RST.LKHelpers
local PL = RST.PeerChecksLK
local measure = K.measurer("[LKR]")
local GESTURES = { "crouch", "sit", "idle" }
local DELAY_MS = 300
local STEP_MS = 5000
local GAP = 3
local FAR = 160             -- squares: beyond Directives.NEAR_RADIUS (100), inside the 300 of K.FAR
local LEAVE_MS = 20000      -- relay recipients rescanned every Config.RELAY.SCAN_EVERY ticks
local QUIET_MS = 2000

local function B() return LivingKnox and LivingKnox.Bodies end
local function D() return LivingKnox and LivingKnox.Directives end
local function A() return LivingKnox and LivingKnox.Anim end
local function RL() return LivingKnox and LivingKnox.Relay end

local function serverClock()
    if GameTime ~= nil and GameTime.getServerTimeMills ~= nil then return GameTime.getServerTimeMills() end
    return getTimestampMs()
end

-- Npc next to the requester, the second client GAP squares south of it; then suite(t, id, peer name, peer player).
local function setup(t, suite)
    if RST.Steps.isSolo() then t:skip("solo: no gesture relay (the only machine reads the gesture directly)") end
    local peer = PL.peer(t)
    if peer == nil then t:skip("needs a second client on the dedicated server") end
    t:ok(B() ~= nil and A() ~= nil and RL() ~= nil and D() ~= nil, "LivingKnox.Bodies, Anim, Directives or Relay "
        .. "is not loaded here")
    local p = RST.Fixtures.player(t)
    local pp = RST.Steps.playerOf(peer)
    t:ok(pp ~= nil, "second client " .. peer .. " not online")
    local id, body = B().spawn({}, math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ()))
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    t:defer(function()
        A().setGesture(id, "idle")
        D().forget(id)
        B().despawn(id, true)
    end, "forget " .. id)
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        local z = B().find(id)
        RST.Fixtures.movePlayer(t2, pp, math.floor(z:getX()), math.floor(z:getY()) + GAP, math.floor(z:getZ()),
            function(t3) return suite(t3, id, peer, pp) end)
    end, "npc still on the floor")
end

RST.suite("lk.relay", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 }, function(s)
    s.test("gesture seen by the second client within 300 ms", function(t)
        setup(t, function(t2, id, peer)
            local delays = {}
            local function one(tg, i)
                if i > #GESTURES then
                    local text = {}
                    local max = 0
                    for k, d in ipairs(delays) do
                        text[k] = GESTURES[k] .. " " .. tostring(d)
                        if d > max then max = d end
                    end
                    local st = RL().stats
                    measure("gesture delays at " .. peer .. ": " .. table.concat(text, ", ") .. " ms (max " .. max
                        .. "); relay emission delay last " .. st.lastDelay .. " max " .. st.maxDelay .. " ms")
                    tg:eq(#GESTURES, #delays, "gestures measured")
                    tg:ok(max < DELAY_MS, "gesture seen " .. max .. " ms after it was set (limit " .. DELAY_MS .. ")")
                    return
                end
                local g = GESTURES[i]
                local key = id .. ":" .. g .. ":" .. i
                RST.Steps.ask(tg, "lk.gesture.watch", { key = key, id = id, g = g }, { target = { peer },
                    timeoutMs = STEP_MS }, function(tw)
                    local t0 = serverClock()
                    local ok, why = A().setGesture(id, g)
                    tw:ok(ok, "gesture " .. g .. " refused: " .. tostring(why))
                    RST.Steps.ask(tw, "lk.gesture.seen", { key = key, t0 = t0 }, { target = { peer },
                        timeoutMs = STEP_MS }, function(ts, res)
                        local a = res.by[peer]
                        if a ~= nil and a.status == "PASS" and a.data ~= nil then delays[#delays + 1] = a.data.delay end
                        ts:sleep(500, function(tn) return one(tn, i + 1) end)
                    end)
                end)
            end
            return one(t2, 1)
        end)
    end)

    s.test("client out of range receives no gesture; the near one does", function(t)
        setup(t, function(t2, id, peer, pp)
            local me = PL.accountOf(RST.Fixtures.player(t2))
            local z = B().find(id)
            RST.Fixtures.movePlayer(t2, pp, math.floor(z:getX()) + FAR, math.floor(z:getY()), math.floor(z:getZ()),
                function(t3)
                    -- recipients are rescanned every Config.RELAY.SCAN_EVERY ticks (1 s on a dedicated server)
                    t3:sleep(1500, function(t3b) t3b:waitUntil(function()
                        local near = RL().near[id]
                        local sent = RL().sent[peer]
                        return (near == nil or near[peer] == nil) and (sent == nil or sent[id] == nil)
                    end, LEAVE_MS, function(t4)
                        local by = RL().stats.byClient
                        local peer0 = by[peer] and by[peer].msgs or 0
                        local me0 = by[me] and by[me].msgs or 0
                        local ok, why = A().setGesture(id, "crouch")
                        t4:ok(ok, "gesture refused: " .. tostring(why))
                        RST.Steps.ask(t4, "lk.gesture.not", { id = id, g = "crouch", waitMs = QUIET_MS },
                            { target = { peer }, timeoutMs = QUIET_MS + STEP_MS }, function(t5)
                                local by5 = RL().stats.byClient
                                local peerN = (by5[peer] and by5[peer].msgs or 0) - peer0
                                local meN = (by5[me] and by5[me].msgs or 0) - me0
                                local names = {}
                                for name in pairs(RL().near[id] or {}) do names[#names + 1] = name end
                                table.sort(names)
                                measure(string.format("out of range (%d squares): messages to %s +%d, to %s (near) +%d; "
                                    .. "recipients of %s: %s", FAR, peer, peerN, tostring(me), meN, id,
                                    table.concat(names, ", ")))
                                t5:eq(0, peerN, "relay messages sent to the client out of range")
                                t5:ok(meN >= 1, "no relay message to the near client")
                            end)
                    end, "second client still a relay recipient of " .. id) end)
                end)
        end)
    end)
end)
