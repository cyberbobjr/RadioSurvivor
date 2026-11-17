--[[
lk.wounds - Knox virus of a Living Knox npc (LK21-T04, LivingKnox.Virus, LivingKnox.Infection, LivingKnox.Health).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on. Solo: RST.run({ suite = "lk.wounds", tags = "world" }); dedicated server:
RST.server({ suite = "lk.wounds", tags = "world" }) from an admin client. Asynchronous run only (about 30 s).

Automated (by code, real Java objects, on the authority):
    bitten     a new npc next to the player is bitten by a zombie (Health.applyHit with the "zombie" wound source and
               the "bite" issue, as LivingKnox.Zombies does for a real attack): it carries the virus and knows it
               (Health.get(id).virus). The delay before death is shortened for the test by the configuration
               (LivingKnox.Config.INFECTION.DELAY_HOURS, restored after the test). At the due hour the npc dies (cause
               "infection", one npcDied fact), its corpse gets the vanilla rise (IsoDeadBody.reanimateLater; a rise
               scheduled later than RISE_WAIT_H by the ZombieLore.Reanimate option is brought forward with
               reanimateNow, noted on the test), the engine raises it and the npc becomes an ordinary zombie: alive,
               without the Living Knox tag, out of the npc registry (LivingKnox.Infection.stats.risen + 1), never laid
               down again (Bodies.stats.laidDown unchanged).
SKIP when the sandbox options say the bite does not kill (ZombieLore.Transmission 4 "None", ZombieLore.Mortality 7
"Never"). Figures are printed as "[LKW] measure ..." lines. The risen zombie is removed at the end (t:defer).
Manual protocol (docs/annexes/conception/blessures-moteur.md, section 2.7): let a zombie bite a group member, check
the group journal entry, wait for the death, watch the corpse rise and attack.
]]

require "RST/RST"
require "RST/RST_ModLivingKnox"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local B, I = K.B, K.I
local measure = K.measurer("[LKW]")
local DELAY_H = 0.02          -- about 4.5 s with the default day length (90 minutes)
local RISE_WAIT_H = 0.05      -- a vanilla rise later than this is brought forward (reanimateNow)
local DEAD_MS = 30000
local RISEN_MS = 30000
local RADIUS = 3
local LISTENER = "RST.lk.wounds"

local function H() return LivingKnox and LivingKnox.Health end
local function Inf() return LivingKnox and LivingKnox.Infection end

-- Corpse of npc id near (x, y, z) (tagged), or nil.
local function corpseOf(id, x, y, z)
    local D = LivingKnox.Death
    return D ~= nil and D.findCorpse ~= nil and (D.findCorpse(id, x, y, z)) or nil
end

-- Living zombies near (x, y, z), untagged (ordinary zombies), as a list.
local function ordinaryNear(x, y, z)
    local out = {}
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local zb = list:get(i)
        if zb ~= nil and not zb:isDead() and math.floor(zb:getZ()) == z and math.abs(zb:getX() - x) <= RADIUS
            and math.abs(zb:getY() - y) <= RADIUS and (not zb:hasModData() or I().readTag(zb:getModData()) == nil) then
            out[#out + 1] = zb
        end
    end
    return out
end

local function removeZombie(zb)
    local Zm = LivingKnox.Zombies
    if Zm ~= nil and Zm.tellBodyGone ~= nil then
        pcall(Zm.tellBodyGone, { o = zb:getOnlineID(), x = zb:getX(), y = zb:getY(), z = zb:getZ() })
    end
    zb:removeFromWorld()
    zb:removeFromSquare()
end

local function option(name)
    local o = getSandboxOptions():getOptionByName(name)
    return o ~= nil and o:getValue() or nil
end

RST.suite("lk.wounds", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 120000 }, function(s)
    s.test("bitten npc dies at the due hour and rises as an ordinary zombie", function(t)
        t:ok(B() ~= nil and H() ~= nil and Inf() ~= nil, "LivingKnox.Infection (LK21-T04) is not loaded on this side")
        local transmission, mortality = option("ZombieLore.Transmission"), option("ZombieLore.Mortality")
        if transmission == 4 or mortality == 7 then
            t:skip("sandbox: a bite does not kill (transmission " .. tostring(transmission) .. ", mortality "
                .. tostring(mortality) .. ")")
        end
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local x, y, z = math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ())
        K.clearZombiesNear(t, x, y, z, K.CLEAR_RADIUS)
        local id, body = B().spawn({}, x, y, z)
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        local C = LivingKnox.Config.INFECTION
        local delay0 = C.DELAY_HOURS
        C.DELAY_HOURS = DELAY_H
        t:defer(function() C.DELAY_HOURS = delay0 end, "restore the infection delay")
        local facts, risen = {}, {}
        LivingKnox.listen("npcDied", LISTENER, function(info) if info.npc == id then facts[#facts + 1] = info end end)
        LivingKnox.listen("npcRisen", LISTENER, function(info) if info.npc == id then risen[#risen + 1] = info end end)
        t:defer(function()
            LivingKnox.listen("npcDied", LISTENER, function() end)
            LivingKnox.listen("npcRisen", LISTENER, function() end)
        end, "mute the listeners")
        t:defer(function()
            if K.registry().npcs[id] ~= nil then B().despawn(id, true) end
            local c = corpseOf(id, x, y, z)
            if c ~= nil then c:getSquare():removeCorpse(c, false) end
            if risen[1] ~= nil then
                for _, zb in ipairs(ordinaryNear(risen[1].x, risen[1].y, risen[1].z)) do removeZombie(zb) end
            end
        end, "remove the npc, its corpse or the risen zombie")
        local laid0, risen0 = B().stats.laidDown, Inf().stats.risen
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
            local zb = B().find(id)
            t2:ok(zb ~= nil, "npc body lost")
            H().applyHit(id, zb, 0.01, "zombie bite", nil, nil, { source = "zombie", issue = "bite" })
            local h = H().get(id)
            t2:eq(true, h ~= nil and h.virus, "the bitten npc does not carry the virus")
            local v = Inf().state(id)
            measure("bitten: virus " .. tostring(h and h.virus) .. ", due in "
                .. string.format("%.3f", v and (v.due - v.since) or -1) .. " h")
            local function dead() return K.registry().npcs[id] == nil or K.registry().npcs[id].state == "dead" end
            t2:waitUntil(dead, DEAD_MS, function(t3)
                t3:eq("infection", facts[1] and facts[1].cause, "death cause")
                t3:eq(1, #facts, "npcDied facts")
                local function scheduled()
                    local c = corpseOf(id, x, y, z)
                    return #risen > 0 or (c ~= nil and c:getReanimateTime() > 0)
                end
                t3:waitUntil(scheduled, 10000, function(t4)
                    local c = corpseOf(id, x, y, z)
                    if c ~= nil and c:getReanimateTime() - getGameTime():getWorldAgeHours() > RISE_WAIT_H then
                        t4:note("vanilla rise at hour " .. string.format("%.3f", c:getReanimateTime())
                            .. " (ZombieLore.Reanimate): brought forward")
                        c:reanimateNow()
                    end
                    t4:waitUntil(function() return #risen > 0 end, RISEN_MS, function(t5)
                        local r = risen[1]
                        local zs = ordinaryNear(r.x, r.y, r.z)
                        measure("risen: facts " .. #facts .. ", risen +" .. (Inf().stats.risen - risen0)
                            .. ", laid down +" .. (B().stats.laidDown - laid0) .. ", ordinary zombies near "
                            .. #zs .. ", registry " .. tostring(K.registry().npcs[id] ~= nil))
                        t5:eq(nil, K.registry().npcs[id], "npc still in the registry")
                        t5:eq(1, Inf().stats.risen - risen0, "risen npcs")
                        t5:eq(0, B().stats.laidDown - laid0, "risen zombie laid down")
                        t5:ok(#zs >= 1, "no ordinary zombie where the npc rose")
                    end, "corpse never rose")
                end, "corpse rise never scheduled")
            end, "bitten npc did not die at the due hour")
        end, "npc still on the floor")
    end)
end)
