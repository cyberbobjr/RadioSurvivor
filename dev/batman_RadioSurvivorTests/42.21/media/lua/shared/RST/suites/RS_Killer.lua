--[[
rs.killer - who killed a Living Knox npc, as established on the authority (E04-T06, LivingKnox.Bodies.deathCause).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on. Solo: RST.run({ suite = "rs.killer", tags = "world" }); dedicated server:
RST.server({ suite = "rs.killer", tags = "world" }) from an admin client. Asynchronous run only (about 30 s).

Automated (by code, real Java objects, on the authority):
    melee      the target player hits the npc with a baseball bat through IsoGameCharacter:Hit (lethal damage):
               cause melee, killer = the player account, weapon Base.BaseballBat, death listener called once;
    firearm    same path with a pistol (HandWeapon:isRanged): cause firearm. A real shot over the network goes
               through the same IsoZombie.Hit on the server (PlayerHitZombie packet): manual protocol below;
    stale      a harmless hit (damage 0) then, HIT_WINDOW_MS + 1 s later, Kill(getAttackedBy()), which is what the
               server does when the owner client reports a zero health: cause other, no killer;
    recent     a harmless hit then Kill(getAttackedBy()) at once: cause melee, killer = the player;
    fire       the npc is weakened (health 0.05) and set on fire (SetOnFire): cause fire, no killer, burning.
               With the reference health of LK07-T02 (LivingKnox.Health loaded), the body is invulnerable: the
               fire goes out at once and the npc stays alive; lethal hits first lower the reference health.
Every test forgets its npc and removes its corpse with t:defer. Figures are printed as "[RSK] measure ..." lines.

Manual protocol (not automated): real melee kill and real gunshot by a player (solo, then a client of a dedicated
server), Molotov cocktail, pipe bomb, run over by a car (driver, then a passenger driving with another player at
the wheel): spawn with LKB.spawn(), kill, then read the "[LivingKnox] INFO npc lk-<n> died ... cause ..." line of the
authority log (solo console.txt, or the server log). docs/tests-en-jeu.md, section 12.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local B, I = K.B, K.I
local measure = K.measurer("[RSK]")
local BAT, PISTOL = "Base.BaseballBat", "Base.Pistol"
local LETHAL = 100.0

local function spawnNpc(t, dx, dy)
    t:ok(B() ~= nil and B().deathCause ~= nil, "LivingKnox.Bodies (E04-T06) is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    t:defer(function() B().despawn(id, true) end, "forget " .. id)
    -- Corpse left by the death: tagged with the npc id (ModData copied by IsoDeadBody), removed at the end.
    t:defer(function()
        for ddy = -3, 3 do
            for ddx = -3, 3 do
                local sq = getCell():getGridSquare(x + ddx, y + ddy, z)
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
    return id, body, p
end

local function weapon(t, fullType)
    t:ok(type(instanceItem) == "function", "instanceItem is not available")
    local w = instanceItem(fullType)
    t:ok(w ~= nil and instanceof(w, "HandWeapon"), fullType .. " is not a HandWeapon")
    return w
end

-- Death listener of LivingKnox.Bodies, restored at the end. Returns the table of received calls.
local function listen(t)
    local calls = {}
    local previous = B().onDied
    B().onDied = function(id, z, cause) calls[#calls + 1] = { id = id, z = z, cause = cause } end
    t:defer(function() B().onDied = previous end, "restore the death listener")
    return calls
end

local function dead(id)
    return function()
        local npc = K.registry().npcs[id]
        return npc ~= nil and npc.state == "dead"
    end
end

local function show(id)
    local d = K.registry().npcs[id].death or {}
    return "cause " .. tostring(d.cause) .. ", killer " .. tostring(d.killer) .. ", weapon " .. tostring(d.weapon)
        .. ", burning " .. tostring(d.burning)
end

-- Spawns an npc 2 squares away (a standing player next to it keeps it on the floor), waits until it stands, then
-- cont(t, id, body, p).
local function standingNpc(t, cont)
    local id, _, p = spawnNpc(t, 2, 0)
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        local z = B().find(id)
        t2:ok(z ~= nil, "npc body lost")
        cont(t2, id, z, p)
    end, "npc still on the floor")
end

-- Reference health of the authority (LK07-T02, LivingKnox.Health): the reference health is lowered first so that
-- one hit is lethal whatever the zombie toughness and the solo estimate of the hit (no weapon cap since LK07-T06).
local function weaken(id)
    local H = LivingKnox and LivingKnox.Health
    if H ~= nil and H.setBirth ~= nil then H.setBirth(id, 0.01) end
end

local function lethalHit(label, fullType, category)
    return function(t)
        local w = weapon(t, fullType)
        standingNpc(t, function(t2, id, z, p)
            local calls = listen(t2)
            weaken(id)
            z:Hit(w, p, LETHAL, false, 1.0)
            t2:waitUntil(dead(id), 5000, function(t3)
                measure(label .. ": " .. show(id) .. ", listener calls " .. #calls)
                local d = K.registry().npcs[id].death
                t3:eq(category, d.cause, "cause")
                t3:eq(p:getUsername(), d.killer, "killer")
                t3:eq(fullType, d.weapon, "weapon")
                t3:eq(1, #calls, "death listener calls")
                t3:eq(id, calls[1].id, "listener id")
                t3:eq(category, calls[1].cause.cause, "listener cause")
            end, "npc not dead after a lethal hit")
        end)
    end
end

RST.suite("rs.killer", { tags = { "world", "server" }, testTimeoutMs = 60000, timeoutMs = 300000 }, function(s)
    s.test("melee: lethal bat hit attributed to the player", lethalHit("melee", BAT, "melee"))

    s.test("firearm: lethal pistol hit attributed to the player", lethalHit("firearm", PISTOL, "firearm"))

    s.test("recent harmless hit then Kill(getAttackedBy()): attributed", function(t)
        local w = weapon(t, BAT)
        standingNpc(t, function(t2, id, z, p)
            z:Hit(w, p, 0.0, false, 1.0)
            measure("after a harmless hit: getAttackedBy is the player " .. tostring(z:getAttackedBy() == p))
            z:Kill(z:getAttackedBy())
            t2:waitUntil(dead(id), 5000, function(t3)
                measure("recent: " .. show(id))
                local d = K.registry().npcs[id].death
                t3:eq("melee", d.cause, "cause")
                t3:eq(p:getUsername(), d.killer, "killer")
            end, "npc not dead after Kill")
        end)
    end)

    s.test("stale harmless hit then Kill(getAttackedBy()): not attributed", function(t)
        local w = weapon(t, BAT)
        standingNpc(t, function(t2, id, z, p)
            z:Hit(w, p, 0.0, false, 1.0)
            t2:sleep(B().HIT_WINDOW_MS + 1000, function(t3)
                local k = z:getAttackedBy()
                measure("stale: getAttackedBy after " .. (B().HIT_WINDOW_MS + 1000) .. " ms is the player "
                    .. tostring(k == p) .. " (" .. tostring(k) .. ")")
                z:Kill(k)
                t3:waitUntil(dead(id), 5000, function(t4)
                    measure("stale: " .. show(id))
                    local d = K.registry().npcs[id].death
                    t4:eq(nil, d.killer, "killer")
                    t4:ok(d.cause == "other" or d.cause == "unknown", "cause " .. tostring(d.cause))
                end, "npc not dead after Kill")
            end)
        end)
    end)

    s.test("fire: burning body dies without a killer", function(t)
        standingNpc(t, function(t2, id, z)
            if LivingKnox.Health ~= nil then
                -- LK07-T02: an invulnerable body is put out at once (IsoGameCharacter.java:6036-6039), never burns.
                z:SetOnFire()
                t2:sleep(3000, function(t3)
                    measure("fire with reference health: on fire " .. tostring(z:isOnFire()) .. ", npc "
                        .. tostring(K.registry().npcs[id].state))
                    t3:eq(false, z:isOnFire(), "invulnerable body still burning")
                    t3:eq("embodied", K.registry().npcs[id].state, "npc state")
                end)
                return
            end
            local calls = listen(t2)
            z:setHealth(0.05)
            z:SetOnFire()
            t2:waitUntil(dead(id), 45000, function(t3)
                measure("fire: " .. show(id) .. ", listener calls " .. #calls)
                local d = K.registry().npcs[id].death
                t3:eq("fire", d.cause, "cause")
                t3:eq(nil, d.killer, "killer")
                t3:eq(true, d.burning, "burning")
                t3:eq(1, #calls, "death listener calls (double OnZombieDead of fire)")
            end, "burning npc not dead")
        end)
    end, { timeoutMs = 90000 })
end)
