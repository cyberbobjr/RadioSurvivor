--[[
lk.health - reference health of a Living Knox npc, held by the authority (LK07-T02, LivingKnox.Health).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on. Solo: RST.run({ suite = "lk.health", tags = "world" }); dedicated server:
RST.server({ suite = "lk.health", tags = "world" }) from an admin client. Asynchronous run only (about 1 minute).

Automated (by code, real Java objects, on the authority):
    hit        the npc body is invulnerable; the target player hits it with a baseball bat through
               IsoGameCharacter:Hit (damage 1): the reference health drops, the vanilla health of the body does not
               change, and 3 s later the reference health has not risen;
    death      one lethal hit (damage 100, far above the maximum of the bat, believed as is since LK07-T06) kills
               the npc, then more hits on the dead body: one death decided by the authority (Health.stats.deaths
               + 1, no engine death), death listener called once, registry state dead with health 0.
Figures are printed as "[LKH] measure ..." lines. Every test forgets its npc and removes its corpse with t:defer.

E01-T16 (LK07-T02): after the hit, every connected client reads the same reference health through
LivingKnox.HealthView.get (step lk.health.view, RST_PeerChecksH.lua, target "all"; solo: the local player).
Manual MP protocol (two clients, docs/conception/sante.md, "Protocole en jeu"): the rest is not automated.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_PeerChecksH"

local K = RST.LKHelpers
local B, I = K.B, K.I
local measure = K.measurer("[LKH]")
local BAT = "Base.BaseballBat"
local SMALL, LETHAL = 1.0, 100.0
local MAX_HITS = 20
local KNIFE = "Base.HuntingKnife"
local FINISH = 900.0         -- value of a finishing blow sent by a client (tests/test_lk_health.py)

local function H() return LivingKnox and LivingKnox.Health end

local function spawnNpc(t)
    t:ok(B() ~= nil and H() ~= nil and H().reference ~= nil, "LivingKnox.Health (LK07-T02) is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    t:defer(function() B().despawn(id, true) end, "forget " .. id)
    t:defer(function()
        for dy = -3, 3 do
            for dx = -3, 3 do
                local sq = getCell():getGridSquare(x + dx, y + dy, z)
                local list = sq and sq:getStaticMovingObjects()
                if list ~= nil then
                    for i = list:size() - 1, 0, -1 do
                        local o = list:get(i)
                        if instanceof(o, "IsoDeadBody") and o:hasModData() and I().readTag(o:getModData()) == id then
                            sq:removeCorpse(o, false)
                        end
                    end
                end
            end
        end
    end, "remove the corpse of " .. id)
    return id, p
end

local function standingNpc(t, cont)
    local id, p = spawnNpc(t)
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        local z = B().find(id)
        t2:ok(z ~= nil, "npc body lost")
        cont(t2, id, z, p)
    end, "npc still on the floor")
end

local function bat(t)
    local w = instanceItem(BAT)
    t:ok(w ~= nil and instanceof(w, "HandWeapon"), BAT .. " is not a HandWeapon")
    return w
end

RST.suite("lk.health", { tags = { "world", "server" }, testTimeoutMs = 60000, timeoutMs = 180000 }, function(s)
    s.test("hit lowers the reference health, vanilla health inert, no rise", function(t)
        local w = bat(t)
        standingNpc(t, function(t2, id, z, p)
            t2:eq(true, z:isInvulnerable(), "body invulnerable")
            local ref0, vanilla0 = H().reference(id), z:getHealth()
            t2:ok(ref0 ~= nil and ref0 > 0, "reference health unknown")
            z:Hit(w, p, SMALL, false, 1.0)
            local ref1 = H().reference(id)
            measure("hit: reference " .. tostring(ref0) .. " -> " .. tostring(ref1) .. ", vanilla "
                .. tostring(vanilla0) .. " -> " .. tostring(z:getHealth()))
            t2:ok(ref1 ~= nil and ref1 < ref0, "reference health did not drop")
            t2:near(vanilla0, z:getHealth(), 0.0005, "vanilla health changed")
            -- The hit itself may start a bleeding (LK07-T03, Health.bleedPass): the reference health may then go
            -- down a little; it must never rise, and must not move at all without a bleeding.
            local bleed = H().bleeding(id)
            t2:sleep(3000, function(t3)
                local ref2 = H().reference(id)
                measure("3 s later: reference " .. tostring(ref2) .. ", bleeding " .. tostring(bleed) .. " per hour")
                t3:ok(ref2 ~= nil and ref2 <= ref1, "reference health rose without care: "
                    .. tostring(ref1) .. " -> " .. tostring(ref2))
                if bleed <= 0 then t3:eq(ref1, ref2, "reference health changed without a hit nor a bleeding") end
                -- LK07-T02 (E01-T16): every connected client reads the same health through HealthView.get (copy
                -- sent by the server, npcHealth); solo: the local player reads the authority. A bleeding lowers the
                -- reference meanwhile: tolerance of 1 % of the maximum.
                local ref = H().get(id)
                if ref ~= nil and RST.Steps.ask ~= nil then
                    RST.Steps.ask(t3, "lk.health.view", { npc = id, hp = ref.hp, max = ref.max,
                        tol = math.max(0.01, (ref.max or 1) * 0.01) }, { target = "all", timeoutMs = 10000 })
                end
            end)
        end)
    end)

    s.test("lethal hits: one death decided by the authority", function(t)
        local w = bat(t)
        standingNpc(t, function(t2, id, z, p)
            local calls = {}
            local previous = B().onDied
            B().onDied = function(nid) calls[#calls + 1] = nid end
            t2:defer(function() B().onDied = previous end, "restore the death listener")
            local st = H().stats
            local deaths0, engine0 = st.deaths, st.engineDeaths
            local hits = 0
            while hits < MAX_HITS and not z:isDead() do
                z:Hit(w, p, LETHAL, false, 1.0)
                hits = hits + 1
            end
            for _ = 1, 3 do z:Hit(w, p, LETHAL, false, 1.0) end   -- hits on the dying body: ignored
            t2:waitUntil(function() return K.registry().npcs[id].state == "dead" end, 5000, function(t3)
                local npc = K.registry().npcs[id]
                measure("death after " .. hits .. " hit(s): deaths +" .. (st.deaths - deaths0) .. ", engine deaths +"
                    .. (st.engineDeaths - engine0) .. ", listener calls " .. #calls .. ", health " .. tostring(npc.hp))
                t3:eq(1, hits, "hits needed (no cap from the weapon, LK07-T06)")
                t3:eq(1, st.deaths - deaths0, "deaths decided")
                t3:eq(0, st.engineDeaths - engine0, "engine deaths")
                t3:eq(1, #calls, "death listener calls")
                t3:eq(0, npc.hp, "registry health")
            end, "npc not dead after " .. MAX_HITS .. " lethal hits")
        end)
    end)

    -- LK07-T06: the value of a hit is believed as is (no cap from the weapon). A finishing blow with a knife, aimed at
    -- the floor on an npc lying down, with the value a client sends for it (FINISH): one hit kills. The range check
    -- runs on a dedicated server only (Health.judge): out of range refusal = MP session.
    s.test("finishing blow with a knife on an npc on the floor: one hit kills", function(t)
        local w = instanceItem(KNIFE)
        t:ok(w ~= nil and instanceof(w, "HandWeapon"), KNIFE .. " is not a HandWeapon")
        standingNpc(t, function(t2, id, z, p)
            z:setOnFloor(true)
            z:setKnockedDown(true)
            local aimed = p:isAimAtFloor()
            p:setAimAtFloor(true)
            t2:defer(function() p:setAimAtFloor(aimed) end, "restore the floor aim of the player")
            local ref0 = H().reference(id)
            local real = H().judge(id, z, p, w, w:getMaxDamage())
            measure(string.format("knife on the floor: reference %.3f, a plain knife hit (max damage %.2f) would take "
                .. "%.3f", ref0 or -1, w:getMaxDamage(), real or -1))
            local hits = 0
            while hits < 3 and not z:isDead() and K.registry().npcs[id].state ~= "dead" do
                z:Hit(w, p, FINISH, false, 1.0)
                hits = hits + 1
            end
            t2:waitUntil(function() return K.registry().npcs[id].state == "dead" end, 5000, function(t3)
                measure("finishing blow: dead after " .. hits .. " hit(s) of " .. FINISH)
                t3:eq(1, hits, "hits of the finishing blow")
            end, "npc not dead after the finishing blow")
        end)
    end)
end)
