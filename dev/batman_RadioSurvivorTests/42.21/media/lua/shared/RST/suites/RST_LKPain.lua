--[[
lk.pain - pain cry of a Living Knox body (LK06-T06, LivingKnox.ZombieGuard). Tag "world": solo only in practice
(voices are played by each client, never by a server; on an MP client world suites are refused), on a save named
rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.pain", tags = "world" }). Asynchronous run only (about 1 minute; do not pause the game).

A zombie has no separate hurt, fall, death or eating sound: those cries are states (FMOD parameter ZombieState) of
its one voice event (Male/FemaleZombie[Sprinter]VoiceA/B/C), and IsoZombie.playHurtSound plays nothing. The guard
gives the body a voice prefix that names no sound and stops a vanilla voice still playing. What is measured here,
by reading the character emitter (isPlaying(name) compares the name of the GameSound played):
    - the npc is hit by the player through the vanilla API (IsoGameCharacter:Hit with a baseball bat, damage 0:
      full hit path, hit reaction, no health lost): for 3 s no vanilla zombie voice is playing on its emitter;
    - control: an ordinary zombie (made useless and toothless so it never attacks) hit the same way: its voice is
      seen playing at least once within 3 s, which proves the probe can hear a voice.
Figures are printed as "[LKP] measure ..." lines. Every test removes its npc and its vanilla zombie with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local STAND_MS = K.STAND_MS
local LISTEN_MS = 3000
local SETTLE_MS = 1000
local WEAPON = "Base.BaseballBat"

local B, G = K.B, K.G
local measure = K.measurer("[LKP]")

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

local function weapon(t)
    t:ok(type(instanceItem) == "function", "instanceItem is not available")
    local w = instanceItem(WEAPON)
    t:ok(w ~= nil and instanceof(w, "HandWeapon"), WEAPON .. " is not a HandWeapon")
    return w
end

-- Names of the vanilla zombie voices playing on the emitter of z (comma separated, "" when none).
local function voicesPlaying(z)
    local emitter = z:getEmitter()
    if emitter == nil then return "" end
    local out = {}
    for _, name in ipairs(G().ZOMBIE_VOICES) do
        if emitter:isPlaying(name) then out[#out + 1] = name end
    end
    return table.concat(out, ",")
end

-- Hits z with the player through the vanilla API (no damage), then samples its emitter every tick for LISTEN_MS.
-- done(t, seen) receives { samples, playing, names = { name = count }, health0, health1, dead }.
local function hitAndListen(t, z, p, w, done)
    local seen = { samples = 0, playing = 0, names = {}, health0 = z:getHealth() }
    z:Hit(w, p, 0.0, false, 1.0)
    local start = getTimestampMs()
    local function sample()
        seen.samples = seen.samples + 1
        local names = voicesPlaying(z)
        if names ~= "" then
            seen.playing = seen.playing + 1
            seen.names[names] = (seen.names[names] or 0) + 1
        end
        return getTimestampMs() - start >= LISTEN_MS
    end
    t:waitUntil(sample, LISTEN_MS + 5000, function(t2)
        seen.health1 = z:getHealth()
        seen.dead = z:isDead()
        done(t2, seen)
    end, "listening period")
end

local function names(seen)
    local out = {}
    for k, n in pairs(seen.names) do out[#out + 1] = k .. " x" .. n end
    table.sort(out)
    return #out > 0 and table.concat(out, "; ") or "none"
end

RST.suite("lk.pain", { tags = { "world" }, testTimeoutMs = 60000, timeoutMs = 180000 }, function(s)
    s.test("hit npc: no zombie voice; hit vanilla zombie: its voice is heard", function(t)
        if not (LivingKnox and LivingKnox.hasLocalPlayer and LivingKnox.hasLocalPlayer()) then
            t:skip("voices are played by clients only: run in solo")
            return
        end
        local w = weapon(t)
        -- 2 squares away: a standing player next to the body keeps it on the floor (isBeingSteppedOn).
        local id, _, p = spawnNpc(t, 2, 0)
        t:waitUntil(K.standing(id), STAND_MS, function(t2)
            t2:sleep(SETTLE_MS, function(t3)
                local z = B().find(id)
                t3:ok(z ~= nil, "npc body lost")
                t3:eq(G().SILENT_VOICE, K.voiceOf(z), "npc voice prefix")
                local stopped0 = G().stats.voicesStopped
                hitAndListen(t3, z, p, w, function(t4, seen)
                    measure("npc " .. id .. " hit: samples " .. seen.samples .. ", with a zombie voice "
                        .. seen.playing .. " (" .. names(seen) .. "), health " .. K.round(seen.health0) .. " -> "
                        .. K.round(seen.health1) .. ", hurtSound " .. tostring(z:getHurtSound())
                        .. ", voices stopped by the guard " .. tostring(G().stats.voicesStopped - stopped0))
                    t4:eq(false, seen.dead, "npc killed by the test hit")
                    t4:ok(seen.samples > 0, "no sample")
                    t4:eq(0, seen.playing, "samples with a zombie voice on the npc")
                    -- Control: an ordinary zombie hit the same way must be heard, or the probe proves nothing.
                    local v = K.spawnVanilla(t4, p, -3, 0)
                    v:setUseless(true)
                    v:setNoTeeth(true)
                    t4:sleep(SETTLE_MS, function(t5)
                        hitAndListen(t5, v, p, w, function(t6, vseen)
                            v:setTarget(nil)
                            measure("vanilla zombie hit: samples " .. vseen.samples .. ", with a zombie voice "
                                .. vseen.playing .. " (" .. names(vseen) .. "), voice prefix "
                                .. tostring(K.voiceOf(v)) .. ", hurtSound " .. tostring(v:getHurtSound()))
                            t6:ok(vseen.playing > 0, "probe inconclusive: the vanilla zombie voice was never seen")
                        end)
                    end)
                end)
            end)
        end, "npc still on the floor")
    end, { timeoutMs = 60000 })
end)
