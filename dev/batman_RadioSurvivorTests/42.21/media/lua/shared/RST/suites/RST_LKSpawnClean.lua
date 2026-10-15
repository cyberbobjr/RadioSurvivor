--[[
lk.spawnclean - clean appearance of a Living Knox body at the clients (LK03-T06, LivingKnox.Bodies creation path,
LivingKnox.ZombieGuard on the clients). Tags "world" and "server". Dedicated server with two clients (autoclient --mp
--clients 2): RST.server({ suite = "lk.spawnclean", tags = "world" }); solo: RST.run({ suite = "lk.spawnclean",
tags = "world" }) (the checks then run on the only machine, without the MP-only ones). Asynchronous run only (about
2 minutes).

The clients (every online client on a server: the second client is brought next to the requester first; solo: the
local player) watch the squares around the spawn point at each tick (steps lk.appear.watch / lk.appear.check,
RST_PeerChecksLK.lua): zombies already there are left out, then every zombie seen there is noted with its online id,
its voice prefix and the zombie voices played by its emitter (LivingKnox.ZombieGuard.ZOMBIE_VOICES).
    spawn         the npc is created; WATCH_MS later (beyond the 5 s a copy without packets would stay): one zombie
                  at a time near the spawn point, no zombie of another online id (the temporary zombie of the
                  creation, path B, never sent), no zombie voice played; on an MP client also the voice prefix
                  silent from the first tick the copy was seen and no voice stopped by the guard (no moan started);
    chunk return  every player goes K.FAR squares away (F.movePlayers) until the body square is unloaded on the server,
                  the clients watch the body square again, everybody comes back: same checks once the body is bound
                  again.
Not automated: reconnection of a client (the launcher keeps both clients connected; protocol in
docs/conception/neutralisation.md). Figures: "[LKA] measure ..." lines. The npc is forgotten with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecksLK"

local K = RST.LKHelpers
local PL = RST.PeerChecksLK
local measure = K.measurer("[LKA]")
local RADIUS = 3
local WATCH_MS = 6000
local STEP_MS = 15000
local UNLOAD_MS = 60000
local BIND_MS = 20000

local function B() return LivingKnox and LivingKnox.Bodies end
local function D() return LivingKnox and LivingKnox.Directives end

-- Step target: every online client on a server (each one checks its own copy), the local player in solo.
local function targets()
    if RST.Steps.isSolo() then return "requester" end
    return "all"
end

-- On a server with a second client, that client is brought next to the requester first; then suite(t).
local function together(t, p, suite)
    local peer = PL.peer(t)
    local pp = peer and RST.Steps.playerOf(peer)
    if pp == nil then return suite(t) end
    RST.Fixtures.movePlayer(t, pp, math.floor(p:getX()), math.floor(p:getY()) + 1, math.floor(p:getZ()), suite)
end

local function check(t, key, id, after)
    RST.Steps.ask(t, "lk.appear.check", { key = key, id = id, strict = not RST.Steps.isSolo() },
        { target = targets(), timeoutMs = STEP_MS }, function(t2, res)
            for _, e in ipairs(res.list) do
                local d = e.data
                if d ~= nil then
                    measure(string.format("%s at %s: most %s at once, other zombies %s, voice ticks %s, vanilla prefix "
                        .. "ticks %s, guard stopped %s pre-silenced %s adopted %s", key, e.user, tostring(d.most),
                        tostring(d.ghosts), tostring(d.voiceTicks), tostring(d.loudTicks), tostring(d.stopped),
                        tostring(d.pre), tostring(d.adopted)))
                end
            end
            if after then return after(t2) end
        end)
end

local function spawnAt(t, x, y, z)
    local id, body = B().spawn({}, x, y, z)
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    t:defer(function()
        if D() ~= nil then D().forget(id) end
        B().despawn(id, true)
    end, "forget " .. id)
    return id, body
end

RST.suite("lk.spawnclean", { tags = { "world", "server" }, testTimeoutMs = 150000, timeoutMs = 360000 }, function(s)
    s.test("npc appears: one body at the clients, no ghost zombie, no moan", function(t)
        t:ok(B() ~= nil, "LivingKnox.Bodies is not loaded here")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        together(t, p, function(t2)
            local x, y, z = math.floor(p:getX()) + 3, math.floor(p:getY()), math.floor(p:getZ())
            local key = "spawn:" .. x .. "," .. y
            RST.Steps.ask(t2, "lk.appear.watch", { key = key, x = x, y = y, z = z, r = RADIUS },
                { target = targets(), timeoutMs = STEP_MS }, function(t3)
                    local id = spawnAt(t3, x, y, z)
                    t3:sleep(WATCH_MS, function(t4) check(t4, key, id) end)
                end)
        end)
    end)

    s.test("chunk return: one body at the clients, no ghost zombie, no moan", function(t)
        t:ok(B() ~= nil, "LivingKnox.Bodies is not loaded here")
        local F = RST.Fixtures
        local C = LivingKnox.Config.BODIES
        local delay = C.RELEASE_DELAY_MS
        C.RELEASE_DELAY_MS = 900000   -- the npc stays embodied while everybody is away
        t:defer(function() C.RELEASE_DELAY_MS = delay end, "restore the release delay")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        together(t, p, function(t2)
            -- 3 squares away from the spawn point of the first test: a body removed by the server stays visible up
            -- to 5 s at the clients (deleteZombie not exposed, LK03-T06 "Reste")
            local id, body = spawnAt(t2, math.floor(p:getX()) + 3, math.floor(p:getY()) + 3, math.floor(p:getZ()))
            t2:waitUntil(K.standing(id), K.STAND_MS, function(t3)
                local zb = B().find(id) or body
                local bx, by, bz = math.floor(zb:getX()), math.floor(zb:getY()), math.floor(zb:getZ())
                local ox, oy, oz = p:getX(), p:getY(), p:getZ()
                F.movePlayers(t3, p, ox + K.FAR, oy, oz, function(t4)
                    t4:waitUntil(function() return getCell():getGridSquare(bx, by, bz) == nil end, UNLOAD_MS,
                        function(t5)
                            local key = "return:" .. id
                            RST.Steps.ask(t5, "lk.appear.watch", { key = key, x = bx, y = by, z = bz, r = RADIUS },
                                { target = targets(), timeoutMs = STEP_MS }, function(t6)
                                    F.movePlayers(t6, p, ox, oy, oz, function(t7)
                                        t7:waitUntil(function() return B().find(id) ~= nil end, BIND_MS, function(t8)
                                            t8:sleep(WATCH_MS, function(t9) check(t9, key, id) end)
                                        end, "npc body not bound again after the return")
                                    end)
                                end)
                        end, "body square still loaded on the server")
                end)
            end, "npc still on the floor")
        end)
    end)
end)
