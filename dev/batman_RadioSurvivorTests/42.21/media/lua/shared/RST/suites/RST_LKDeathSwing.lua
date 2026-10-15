--[[
lk.deathswing - npc killed during its melee swing: no melee sound left playing at a client (LK06-T13,
LivingKnox.Combat on the authority, LivingKnox.CombatView on each machine that plays sounds). Tags "world" and
"server". Dedicated server with two clients (autoclient --mp --clients 2): RST.server({ suite = "lk.deathswing",
tags = "world" }), the second client listens; solo: RST.run({ suite = "lk.deathswing", tags = "world" }), the local
player listens (same steps, no network). One client on a server: SKIP. Asynchronous run only (about 30 s).

An npc armed with a machete strikes the requester (god mode on, restored at the end). The listening client waits
until it plays a swing on its copy of the body (step lk.melee.swing, RST_PeerChecksLK.lua: CombatView swing counter and
the swing name playing on the copy's emitter) and answers at once; the authority then kills the npc
(LivingKnox.Health.kill with the requester and a hammer). The listener (step lk.melee.silence) checks, LISTEN_MS after
the death it saw (OnZombieDead or isDead of its copy): no swing nor impact played after the death, the emitter of the
dead copy plays neither the swing nor the impact, and a swing still playing at the death was stopped by CombatView
(bodySoundsStopped). On a server the kill follows the swing after one network round trip: whether the swing was still
playing at the death is printed (playingAtDeath), the silence is checked either way. Figures: "[LKD] measure ..."
lines. The npc is forgotten and the melee ended with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecksLK"

local K = RST.LKHelpers
local PL = RST.PeerChecksLK
local measure = K.measurer("[LKD]")
local SWING_MS = 25000
local LISTEN_MS = 4000
local WEAPON = "Base.Machete"

local function B() return LivingKnox and LivingKnox.Bodies end
local function C() return LivingKnox and LivingKnox.Combat end
local function H() return LivingKnox and LivingKnox.Health end
local function E() return LivingKnox and LivingKnox.Equipment end

-- Body of the test, shared with lk.melee (LK06-T02: its "killed during a swing" test runs this one on a dedicated
-- server, where the melee sounds are played by the clients).
RST.LKDeathSwing = RST.LKDeathSwing or {}
function RST.LKDeathSwing.run(t)
    t:ok(B() ~= nil and C() ~= nil and H() ~= nil and E() ~= nil and C().engage ~= nil and H().kill ~= nil,
        "LivingKnox.Combat, Health or Equipment not loaded here")
    local target = PL.watchTarget(t)
    if target == nil then t:skip("needs a second client on the dedicated server (the listener)") end
    local listener = type(target) == "table" and target[1] or RST.Steps.LOCAL
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local wasGod = p:isGodMod()
    p:setGodMod(true)
    t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
    local id, body = B().spawn({}, math.floor(p:getX()) + 3, math.floor(p:getY()), math.floor(p:getZ()))
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    t:defer(function() B().despawn(id, true) end, "forget " .. id)
    t:defer(function() C().disengage(id, "suite lk.deathswing over") end, "end the melee of " .. id)
    local function near(tn, suite)   -- the listener of a server stands next to the requester
        local pp = type(target) == "table" and RST.Steps.playerOf(listener) or nil
        if pp == nil then return suite(tn) end
        RST.Fixtures.movePlayer(tn, pp, math.floor(p:getX()), math.floor(p:getY()) + 2, math.floor(p:getZ()), suite)
    end
    near(t, function(tn) tn:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        local okW, whyW = E().setWeapon(id, WEAPON)
        t2:ok(okW, "machete refused: " .. tostring(whyW))
        local c, why = C().engage(id, p:getUsername(), { source = "api", why = "suite lk.deathswing" })
        t2:ok(c ~= nil, "engage refused: " .. tostring(why))
        local order = C().get(id)
        local sw = order and order.sw
        t2:ok(type(sw) == "string", "melee order without a swing sound")
        local hit = C().impactSound(instanceItem(WEAPON), "strike")
        local key = "death:" .. id
        RST.Steps.ask(t2, "lk.melee.swing", { key = key, id = id, sw = sw, hit = hit },
            { target = target, timeoutMs = SWING_MS }, function(t3, res)
                local a = res.by[listener]
                if a == nil or a.status ~= "PASS" then return end   -- failure already asserted by the step
                local ok, whyK = H().kill(id, nil, p, instanceItem("Base.Hammer"))
                t3:eq(true, ok, "death refused: " .. tostring(whyK))
                RST.Steps.ask(t3, "lk.melee.silence", { key = key, listenMs = LISTEN_MS },
                    { target = target, timeoutMs = LISTEN_MS + 15000 }, function(_, res2)
                        local d = res2.by[listener] and res2.by[listener].data
                        measure("death during a swing (" .. tostring(sw) .. ", impact " .. tostring(hit)
                            .. ") at " .. listener .. ": " .. tostring(res2.by[listener]
                            and res2.by[listener].message) .. (d and (" [playing at death "
                            .. tostring(d.playingAtDeath) .. "]") or ""))
                    end)
            end)
    end, "npc still on the floor") end)
end

RST.suite("lk.deathswing", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 120000 }, function(s)
    s.test("npc killed during a swing: silence at the listening client after the fall", RST.LKDeathSwing.run)
end)
