--[[
lk.melee - melee of a Living Knox npc against a player (LK06-T02, LivingKnox.Combat, LivingKnox.CombatView).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on. Solo: RST.run({ suite = "lk.melee", tags = "world" }); dedicated server:
RST.server({ suite = "lk.melee", tags = "world" }) from an admin client (the admin is the target). Asynchronous run
only (about 30 s).

Automated (real Java objects, on the authority):
    strikes    an npc (bare hands) is spawned 3 squares from the target player, who is protected by god mode
               (setGodMod: the hits are counted, the player is restored by the engine); the npc is engaged against
               the player through LivingKnox.Combat.engage: it runs to the player, faces him and plays the strike
               gesture; at least MIN_HITS hits are applied by the authority within WAIT_MS, every hit at most once
               (applied = damage calls seen by the suite), no hit refused for reach or cadence, and the gap between
               two applied hits is never shorter than CADENCE_MIN x STRIKE_MS.
    sounds     (LK06-T11, solo only: the machine that plays them) melee sounds played here while striking, counted by
               LivingKnox.CombatView.stats: at least one swing per applied hit (AttackShove, bare hands) and exactly
               one impact per applied hit (BareHandsHit); on a dedicated server the sounds are played by the clients
               and only the impact entries sent are counted (Combat.stats.meleeSounds).
    death      (LK06-T13, solo only) an npc armed with a machete strikes the protected player; right after a swing is
               played, the npc is killed by the authority (LivingKnox.Health.kill with the player and a hammer, the
               path of a deadly blow in solo); the swing must be playing on the body emitter at that moment, then
               stopped at the death (CombatView.stats.bodySoundsStopped), and during DEATH_LISTEN_MS no swing nor
               impact is played here and the dead body emitter plays neither the swing nor the impact. Listen while
               the body falls: nothing after the death.
Figures are printed as "[LKM] measure ..." lines. The npc is forgotten and the god mode restored with t:defer.
Look at the npc while the suite runs: it should run to the player, then swing at him; each swing and each hit must be
heard.

Dedicated server (decision of 2026-10-15, nothing cut): the "killed during a swing" test runs the body of
lk.deathswing (RST.LKDeathSwing.run): the second client (the listener) waits for a swing on its copy of the body, the
authority kills the npc during it, and the listener checks that no swing nor impact is played after the death. One
client only: SKIP (the listener is missing).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/suites/RST_LKDeathSwing"

local K = RST.LKHelpers
local B = K.B
local measure = K.measurer("[LKM]")
local MIN_HITS = 2
local WAIT_MS = 20000

local DEATH_LISTEN_MS = 4000

local function C() return LivingKnox and LivingKnox.Combat end
local function V() return LivingKnox and LivingKnox.CombatView end
local function H() return LivingKnox and LivingKnox.Health end

-- LK06-T11: melee sound counters (sounds played here, impact entries sent by the authority).
local function soundCounts()
    local v, st = V(), C().stats
    return { swings = v and v.stats.meleeSwings or 0, impacts = v and v.stats.meleeImpacts or 0,
        sent = st.meleeSounds or 0 }
end

RST.suite("lk.melee", { tags = { "world", "server" }, testTimeoutMs = 60000, timeoutMs = 120000 }, function(s)
    s.test("npc runs to the player and strikes him, each hit applied once", function(t)
        t:ok(B() ~= nil and C() ~= nil and C().engage ~= nil, "LivingKnox.Combat (LK06-T02) is not loaded on this side")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local x, y, z = math.floor(p:getX()) + 3, math.floor(p:getY()), math.floor(p:getZ())
        local id, body = B().spawn({}, x, y, z)
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
        t:defer(function() C().disengage(id, "suite lk.melee over") end, "end the melee of " .. id)
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
            local st = C().stats
            local applied0, refused0 = st.applied, st.refused
            local reach0, fast0 = st.why["out of reach"] or 0, st.why["too fast"] or 0
            local times = {}
            local snd0 = soundCounts()
            local bd = p:getBodyDamage()
            local c, why = C().engage(id, p:getUsername(), { source = "api", why = "suite lk.melee" })
            t2:ok(c ~= nil, "engage refused: " .. tostring(why))
            local order = C().get(id)
            measure("engaged: melee #" .. tostring(c) .. " with " .. tostring(order and order.t) .. ", reach "
                .. tostring(order and K.round(order.reach)) .. ", one strike every " .. tostring(order and order.iv)
                .. " ms, phase " .. tostring(order and order.phase))
            local lastApplied = applied0
            t2:waitUntil(function()
                if st.applied > lastApplied then
                    for _ = lastApplied + 1, st.applied do times[#times + 1] = getTimestampMs() end
                    lastApplied = st.applied
                end
                return st.applied - applied0 >= MIN_HITS + 1
            end, WAIT_MS, function(t3)
                local o = C().get(id)
                local minGap = nil
                for i = 2, #times do
                    local gap = times[i] - times[i - 1]
                    if minGap == nil or gap < minGap then minGap = gap end
                end
                measure("hits applied " .. (st.applied - applied0) .. ", refused " .. (st.refused - refused0)
                    .. " (out of reach " .. ((st.why["out of reach"] or 0) - reach0) .. ", too fast "
                    .. ((st.why["too fast"] or 0) - fast0) .. "), order hits " .. tostring(o and o.hits)
                    .. ", phase " .. tostring(o and o.phase) .. ", smallest gap " .. tostring(minGap) .. " ms, player "
                    .. "health " .. tostring(bd and K.round(bd:getHealth())))
                t3:ok(o ~= nil, "melee ended before the hits")
                t3:eq(st.applied - applied0, o.hits, "hits of the order = hits applied by the authority")
                t3:eq(0, (st.why["out of reach"] or 0) - reach0, "hits refused out of reach")
                t3:eq(0, (st.why["too fast"] or 0) - fast0, "hits refused as too fast")
                local floor = LivingKnox.Config.COMBAT.STRIKE_MS * LivingKnox.Config.COMBAT.CADENCE_MIN
                t3:ok(minGap == nil or minGap >= floor - 50, "two hits applied " .. tostring(minGap) .. " ms apart")
                local snd = soundCounts()
                local applied = st.applied - applied0
                local last = V() and V().lastMelee or {}
                measure("melee sounds: impacts sent " .. (snd.sent - snd0.sent) .. ", played here: swings "
                    .. (snd.swings - snd0.swings) .. ", impacts " .. (snd.impacts - snd0.impacts) .. " (last swing "
                    .. tostring(last.sw) .. ", last impact " .. tostring(last.hit) .. ")")
                t3:eq(applied, snd.sent - snd0.sent, "impact entries sent = hits applied")
                if V() ~= nil then
                    t3:eq(applied, snd.impacts - snd0.impacts, "impacts played here = hits applied")
                    t3:ok(snd.swings - snd0.swings >= applied, "fewer swings than hits played here")
                end
            end, "fewer than " .. (MIN_HITS + 1) .. " hits applied in " .. WAIT_MS .. " ms")
        end, "npc still on the floor")
    end)

    -- LK06-T13: npc killed in the middle of a swing.
    s.test("npc killed during a swing: the swing stops and no melee sound follows", function(t)
        t:ok(B() ~= nil and C() ~= nil and H() ~= nil and H().kill ~= nil, "LivingKnox.Combat or Health not loaded")
        if V() == nil or V().stats.bodySoundsStopped == nil then
            -- Dedicated server: the melee sounds are played by the clients; the second client listens to its copy of
            -- the body (lk.deathswing body: steps lk.melee.swing and lk.melee.silence, RST_PeerChecksLK.lua).
            t:note("dedicated server: the listening client checks the silence after the death (lk.deathswing)")
            return RST.LKDeathSwing.run(t)
        end
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local x, y, z = math.floor(p:getX()) + 3, math.floor(p:getY()), math.floor(p:getZ())
        local id, body = B().spawn({}, x, y, z)
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
        t:defer(function() C().disengage(id, "suite lk.melee over") end, "end the melee of " .. id)
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
            local okW, whyW = K.E().setWeapon(id, "Base.Machete")
            t2:ok(okW, "machete refused: " .. tostring(whyW))
            local c, why = C().engage(id, p:getUsername(), { source = "api", why = "suite lk.melee death" })
            t2:ok(c ~= nil, "engage refused: " .. tostring(why))
            local zb = B().find(id)
            t2:ok(zb ~= nil, "npc body not found")
            local order = C().get(id)
            local sw = order and order.sw
            local hit = C().impactSound(instanceItem("Base.Machete"), "strike")
            local swings0 = V().stats.meleeSwings
            t2:waitUntil(function() return V().stats.meleeSwings > swings0 end, WAIT_MS, function(t3)
                local em = zb:getEmitter()
                local wasPlaying = sw ~= nil and em:isPlaying(sw)
                local st = V().stats
                local stops0, soundStops0 = st.bodySoundsStopped, st.bodySoundStops
                local ok, whyK = H().kill(id, nil, p, instanceItem("Base.Hammer"))
                t3:eq(true, ok, "death refused: " .. tostring(whyK))
                local stopped = st.bodySoundsStopped - stops0
                local names = st.bodySoundStops - soundStops0
                local after = { swings = st.meleeSwings, impacts = st.meleeImpacts }
                local stillAtDeath = sw ~= nil and em:isPlaying(sw)
                t3:sleep(DEATH_LISTEN_MS, function(t4)
                    local swingLater = sw ~= nil and em:isPlaying(sw)
                    local hitLater = hit ~= nil and em:isPlaying(hit)
                    measure("death during a swing (" .. tostring(sw) .. ", impact " .. tostring(hit) .. "): playing "
                        .. "at the death " .. tostring(wasPlaying) .. ", stopped at the death " .. stopped .. " ("
                        .. names .. " name(s)), swing still playing " .. tostring(stillAtDeath) .. "; in the next "
                        .. DEATH_LISTEN_MS .. " ms: swings played " .. (st.meleeSwings - after.swings)
                        .. ", impacts played " .. (st.meleeImpacts - after.impacts) .. ", body emitter playing swing "
                        .. tostring(swingLater) .. ", impact " .. tostring(hitLater))
                    t4:ok(wasPlaying, "the swing was not playing when the npc was killed")
                    t4:eq(1, stopped, "body sounds stopped at the death")
                    t4:eq(false, stillAtDeath, "swing still playing right after the death")
                    t4:eq(0, st.meleeSwings - after.swings, "swings played after the death")
                    t4:eq(0, st.meleeImpacts - after.impacts, "impacts played after the death")
                    t4:eq(false, swingLater, "swing playing on the dead body")
                    t4:eq(false, hitLater, "impact playing on the dead body")
                end)
            end, "no swing played in " .. WAIT_MS .. " ms")
        end, "npc still on the floor")
    end, { timeoutMs = 100000 })
end)
