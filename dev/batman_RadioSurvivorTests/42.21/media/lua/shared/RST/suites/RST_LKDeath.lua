--[[
lk.death - single death and corpse of a Living Knox npc (LK07-T04, LivingKnox.Health.kill, LivingKnox.Bodies).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on. Solo: RST.run({ suite = "lk.death", tags = "world" }); dedicated server:
RST.server({ suite = "lk.death", tags = "world" }) from an admin client. Asynchronous run only (about 1 minute).

Automated (by code, real Java objects, on the authority):
    hit        lethal baseball bat hits (IsoGameCharacter:Hit, damage 100) then more hits: one death decided
               (Health.stats.deaths + 1), one "npcDied" fact (cause melee, killer = the player), registry dead, one
               corpse on the ground carrying the npc tag and worn clothes, no living zombie carrying the tag 2 s later;
    bleeding   bleeding set on the npc (registry), one bleeding pass: death cause "bleeding", no killer, one corpse;
    risen      direct death (Health.kill without attacker), then the corpse is reanimated by code
               (IsoDeadBody:reanimate, as another mod would do) and the scan runs: the zombie is laid down at once
               (solo; MP server: once Bodies.RISEN_DELAY_MS elapsed, LK07-T09) (Bodies.stats.laidDown + 1), one
               tagged corpse again, still one death and one fact; MP: the other clients see that corpse only.
Figures are printed as "[LKD] measure ..." lines. Every test forgets its npc and removes its corpse with t:defer.

    nocopy     (LK07-T10) the npc is killed in the very call that creates it (Health.kill), so no client holds its
               copy and every client drops the vanilla death packet; on a MP server LivingKnox.Death asks the clients
               near the corpse (after Death.CHECK_DELAY_MS) and resends it to them (Death.stats.resent + 1): every
               client then sees exactly one corpse (no duplicate); solo: one corpse, nothing tracked.

E01-T16 (MP campaign with a second client): after the lethal hits the other clients see the same corpses on the
square of the corpse, with the same worn clothes and content (RST.PeerChecks.checkSquares; nothing asked in solo).
Manual protocol (docs/annexes/conception/sante.md, "Mort unique et cadavre (LK07-T04)"): drag the corpse (B42 grapple), drop
it, check it is still there with its clothes and items.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

local K = RST.LKHelpers
local B, I = K.B, K.I
local measure = K.measurer("[LKD]")
local BAT = "Base.BaseballBat"
local LETHAL = 100.0
local MAX_HITS = 20
local RADIUS = 3
local DEAD_MS = 5000
local LISTENER = "RST.lk.death"

local function H() return LivingKnox and LivingKnox.Health end

-- Tagged corpses of npc id near (x, y, z), as a list.
local function corpsesOf(id, x, y, z)
    local out = {}
    for dy = -RADIUS, RADIUS do
        for dx = -RADIUS, RADIUS do
            local sq = getCell():getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getStaticMovingObjects()
            if list ~= nil then
                for i = 0, list:size() - 1 do
                    local o = list:get(i)
                    if instanceof(o, "IsoDeadBody") and o:hasModData() and I().readTag(o:getModData()) == id then
                        out[#out + 1] = o
                    end
                end
            end
        end
    end
    return out
end

-- Living zombies carrying the tag of npc id.
local function aliveTagged(id)
    local list = getCell():getZombieList()
    local n = 0
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if not z:isDead() and z:hasModData() and I().readTag(z:getModData()) == id then n = n + 1 end
    end
    return n
end

-- New npc next to the player; its corpse and registry entry removed at the end. Returns id, player, x, y, z, facts.
local function spawnNpc(t)
    t:ok(B() ~= nil and H() ~= nil and H().kill ~= nil, "LivingKnox.Health (LK07-T04) is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    local facts = {}
    LivingKnox.listen("npcDied", LISTENER, function(info)
        if info.npc == id then facts[#facts + 1] = info end
    end)
    t:defer(function() LivingKnox.listen("npcDied", LISTENER, function() end) end, "mute the npcDied listener")
    t:defer(function() B().despawn(id, true) end, "forget " .. id)
    t:defer(function()
        local D = LivingKnox.Death
        if D ~= nil and D.pending ~= nil then D.pending[id] = nil end   -- LK07-T10: no resend after the test
        for _, o in ipairs(corpsesOf(id, x, y, z)) do o:getSquare():removeCorpse(o, false) end
    end, "remove the corpse of " .. id)
    return id, p, x, y, z, facts
end

local function standingNpc(t, cont)
    local id, p, x, y, z, facts = spawnNpc(t)
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        local body = B().find(id)
        t2:ok(body ~= nil, "npc body lost")
        -- MP: the other clients must hold their copy before the death, or they never get its corpse (vanilla).
        RST.PeerChecks.waitCopies(t2, { body }, function(t3)
            cont(t3, { id = id, p = p, x = x, y = y, z = z, facts = facts, body = body })
        end)
    end, "npc still on the floor")
end

local function isDead(id)
    return function() return K.registry().npcs[id].state == "dead" end
end

RST.suite("lk.death", { tags = { "world", "server" }, testTimeoutMs = 60000, timeoutMs = 180000 }, function(s)
    s.test("lethal hits: one death, one tagged corpse with clothes, one fact, no rise", function(t)
        local w = instanceItem(BAT)
        t:ok(w ~= nil and instanceof(w, "HandWeapon"), BAT .. " is not a HandWeapon")
        standingNpc(t, function(t2, c)
            local deaths0 = H().stats.deaths
            local hits = 0
            while hits < MAX_HITS and not c.body:isDead() do
                c.body:Hit(w, c.p, LETHAL, false, 1.0)
                hits = hits + 1
            end
            for _ = 1, 3 do c.body:Hit(w, c.p, LETHAL, false, 1.0) end   -- hits on the dying body: ignored
            t2:waitUntil(isDead(c.id), DEAD_MS, function(t3)
                t3:sleep(2000, function(t4)
                    local corpses = corpsesOf(c.id, c.x, c.y, c.z)
                    local worn = corpses[1] and corpses[1]:getWornItems() and corpses[1]:getWornItems():size() or 0
                    local f = c.facts[1] or {}
                    measure("hit: " .. hits .. " hit(s), deaths +" .. (H().stats.deaths - deaths0) .. ", facts "
                        .. #c.facts .. " (" .. tostring(f.cause) .. ", " .. tostring(f.killer) .. "), corpses "
                        .. #corpses .. ", worn items " .. worn .. ", living tagged zombies " .. aliveTagged(c.id))
                    t4:eq(1, H().stats.deaths - deaths0, "deaths decided")
                    t4:eq(1, #c.facts, "npcDied facts")
                    t4:eq("melee", f.cause, "death cause")
                    t4:eq(c.p:getUsername(), f.killer, "killer")
                    t4:eq(1, #corpses, "tagged corpses")
                    t4:ok(worn > 0, "corpse without worn clothes")
                    t4:eq(0, aliveTagged(c.id), "living zombies with the npc tag")
                    -- E01-T16: the other clients see the same corpse, worn clothes and content on its square.
                    local csq = corpses[1]:getSquare()
                    RST.PeerChecks.checkSquares(t4, RST.PeerChecks.around(csq:getX(), csq:getY(), csq:getZ(), 2),
                        { corpse = true }, nil, true)
                end)
            end, "npc not dead after " .. MAX_HITS .. " lethal hits")
        end)
    end)

    s.test("bleeding to death: cause bleeding, no killer", function(t)
        standingNpc(t, function(t2, c)
            local npc = K.registry().npcs[c.id]
            npc.hp, npc.bleed = 0.005, 0.6
            local minute = math.floor(getGameTime():getWorldAgeHours() * 60 + 0.5)
            H().bleedPass(minute)
            H().bleedPass(minute + 1)
            t2:waitUntil(isDead(c.id), DEAD_MS, function(t3)
                local d = K.registry().npcs[c.id].death or {}
                local corpses = corpsesOf(c.id, c.x, c.y, c.z)
                measure("bleeding: cause " .. tostring(d.cause) .. ", killer " .. tostring(d.killer) .. ", facts "
                    .. #c.facts .. ", corpses " .. #corpses)
                t3:eq("bleeding", d.cause, "death cause")
                t3:eq(nil, d.killer, "killer")
                t3:eq(1, #c.facts, "npcDied facts")
                t3:eq(1, #corpses, "tagged corpses")
            end, "npc did not bleed to death")
        end)
    end)

    s.test("risen corpse is laid down at once, never an npc again", function(t)
        standingNpc(t, function(t2, c)
            local deaths0, laid0 = H().stats.deaths, B().stats.laidDown
            local ok, why = H().kill(c.id)
            t2:eq(true, ok, "direct death refused: " .. tostring(why))
            t2:eq(false, (H().kill(c.id)), "second direct death accepted")
            t2:waitUntil(function() return #corpsesOf(c.id, c.x, c.y, c.z) == 1 end, DEAD_MS, function(t3)
                local zr = corpsesOf(c.id, c.x, c.y, c.z)[1]:reanimate()
                t3:ok(zr ~= nil, "corpse not reanimated by the engine")
                B().scanAll()
                -- MP server: laid down at the first scan after Bodies.RISEN_DELAY_MS (LK07-T09), at once otherwise.
                local function laid() return B().stats.laidDown - laid0 >= 1 end
                local wait = isServer() and (B().RISEN_DELAY_MS + 3 * B().SCAN_EVERY * 100 + 2000) or 1000
                t3:waitUntil(laid, wait, function(t3b) t3b:sleep(1000, function(t4)
                    local corpses = corpsesOf(c.id, c.x, c.y, c.z)
                    measure("risen: laid down +" .. (B().stats.laidDown - laid0) .. ", zombie dead "
                        .. tostring(zr:isDead()) .. ", corpses " .. #corpses .. ", deaths +"
                        .. (H().stats.deaths - deaths0) .. ", facts " .. #c.facts .. ", registry "
                        .. tostring(K.registry().npcs[c.id].state))
                    t4:eq(1, B().stats.laidDown - laid0, "risen corpses laid down")
                    t4:eq(0, aliveTagged(c.id), "living zombies with the npc tag")
                    t4:eq(1, #corpses, "tagged corpses")
                    t4:eq(1, H().stats.deaths - deaths0, "deaths decided")
                    t4:eq(1, #c.facts, "npcDied facts")
                    t4:eq("dead", K.registry().npcs[c.id].state, "registry state")
                    -- E01-T16 / LK07-T09: the other clients see the corpse laid down, and no longer the risen one.
                    if corpses[1] ~= nil then
                        local csq = corpses[1]:getSquare()
                        RST.PeerChecks.checkSquares(t4, RST.PeerChecks.around(csq:getX(), csq:getY(), csq:getZ(), 2),
                            { corpse = true }, nil, true)
                    end
                end) end, "risen corpse not laid down")
            end, "no corpse after the direct death")
        end)
    end)

    -- LK07-T10: killed before any client got its copy (vanilla: no corpse there); resent by LivingKnox.Death.
    s.test("killed before any client copy: corpse resent, one corpse on every client", function(t)
        local id, _, x, y, z = spawnNpc(t)
        local D = LivingKnox.Death
        t:ok(D ~= nil and D.stats ~= nil, "LivingKnox.Death (LK07-T10) is not loaded on this side")
        local s0 = { tracked = D.stats.tracked, asked = D.stats.asked, missing = D.stats.missing,
            resent = D.stats.resent }
        local deaths0 = H().stats.deaths
        local ok, why = H().kill(id)   -- same call as the creation: no copy has left the server yet
        t:eq(true, ok, "direct death refused: " .. tostring(why))
        t:waitUntil(function() return #corpsesOf(id, x, y, z) == 1 end, DEAD_MS, function(t2)
            local active = D.active()
            local list = active and getOnlinePlayers() or nil
            local clients = list ~= nil and list:size() > 0   -- MP: at least the requester lacks the corpse
            local function settled()
                return not clients or D.stats.resent > s0.resent
            end
            local wait = D.CHECK_DELAY_MS + D.RESEND_GAP_MS + 3 * D.EVERY * 100 + 5000
            t2:waitUntil(settled, wait, function(t3)
                local corpses = corpsesOf(id, x, y, z)
                measure("nocopy: corpses " .. #corpses .. ", deaths +" .. (H().stats.deaths - deaths0)
                    .. ", tracked +" .. (D.stats.tracked - s0.tracked) .. ", asked +" .. (D.stats.asked - s0.asked)
                    .. ", missing +" .. (D.stats.missing - s0.missing) .. ", resent +" .. (D.stats.resent - s0.resent)
                    .. " (MP server " .. tostring(active) .. ", clients " .. tostring(clients) .. ")")
                t3:eq(1, #corpses, "tagged corpses")
                t3:eq(1, H().stats.deaths - deaths0, "deaths decided")
                t3:eq(active and 1 or 0, D.stats.tracked - s0.tracked, "corpses tracked")
                if not active then t3:eq(0, D.stats.resent - s0.resent, "corpses resent in solo") end
                if clients then t3:ok(D.stats.missing - s0.missing >= 1, "no client reported the missing corpse") end
                -- Every client (requester included) sees exactly the server's corpse: none missing, no duplicate.
                local csq = corpses[1]:getSquare()
                RST.PeerChecks.checkSquares(t3, RST.PeerChecks.around(csq:getX(), csq:getY(), csq:getZ(), 2),
                    { corpse = true }, nil, true)
            end, "corpse never resent to the clients without the copy")
        end, "no corpse after the direct death")
    end)
end)
