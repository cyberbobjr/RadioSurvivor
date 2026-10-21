--[[
lk.ranged - firearm of a Living Knox npc against a player (LK06-T03, LivingKnox.Combat, LivingKnox.Ammo,
LivingKnox.CombatView). Tags "world" and "server": the authority only, on a save named rstest*, with a target player
(t.ctx.player); the Living Knox option Enabled must be on. Solo: RST.run({ suite = "lk.ranged", tags = "world" }).
Dedicated server (E01-T19, campaign mp): RST.server({ suite = "lk.ranged", tags = "world" }); the shots played by
EVERY connected client (requester and second client, LK06-T03; sound and flash once each) are counted there through
RST.Steps (RST_ViewSteps.lua: lk.combat.view,
counters noted before the engagement, compared after). Asynchronous run only (about 20 s).

Automated (real Java objects, on the authority):
    shots      an npc is spawned 5 squares from the target player, who is protected by god mode (setGodMod: the
               wounds are counted, the player is restored by the engine); its weapon is set to Base.Pistol and
               ROUNDS loose rounds of its ammo type are put in the inventory of its body (LivingKnox.Ammo.give, no
               magazine). It is engaged against the player through LivingKnox.Combat.engage: the order must be a
               ranged one; the npc reloads (reload gesture), aims and fires. Within WAIT_MS the authority must
               have accepted exactly ROUNDS shots (never more: no shot without ammo), at least one reload, one
               noise per shot, hits = damage calls, no ammo left on the body; the order is then replaced by a
               melee one with bare hands (out of ammo). On a machine that plays the shots (solo), the sound and
               the flash of every shot are played exactly once (CombatView: played = shots, no duplicate).
Figures are printed as "[LKR] measure ..." lines. The npc is forgotten and the god mode restored with t:defer.
Look at the npc while the suite runs: reload gesture, aim, one shot per second with the pistol sound and a flash.

Manual MP protocol (two clients, docs/annexes/conception/combat.md, "Tir", "Protocole en jeu"): not automated.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_ViewSteps"

local K = RST.LKHelpers
local B = K.B
local measure = K.measurer("[LKR]")
local GUN = "Base.Pistol"
local ROUNDS = 3
local WAIT_MS = 30000

local function C() return LivingKnox and LivingKnox.Combat end
local function Am() return LivingKnox and LivingKnox.Ammo end

local function snapshot(st, keys)
    local out = {}
    for _, k in ipairs(keys) do out[k] = st[k] or 0 end
    return out
end

local function onServer() return type(isServer) == "function" and isServer() end

-- E01-T19: the requester client notes or compares the shots it played (dedicated server only), then after(t2).
-- LK06-T03: every connected client (target "all"): the second client near the requester also plays each shot once
-- (sound and flash), the shots being relayed to the clients near the npc.
local function viewStep(t, args, after)
    if not onServer() then return after(t) end
    RST.Steps.ask(t, "lk.combat.view", args, { target = "all", timeoutMs = 10000 }, after)
end

RST.suite("lk.ranged", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 150000 }, function(s)
    s.test("npc reloads and fires every round it has, never more", function(t)
        t:ok(B() ~= nil and C() ~= nil and C().engage ~= nil and Am() ~= nil and Am().give ~= nil,
            "LivingKnox.Combat and LivingKnox.Ammo (LK06-T03) are not loaded on this side")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local x, y, z = math.floor(p:getX()) + 5, math.floor(p:getY()), math.floor(p:getZ())
        local id, body = B().spawn({}, x, y, z)
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
        t:defer(function() C().disengage(id, "suite lk.ranged over") end, "end the combat of " .. id)
        local key = id .. "-" .. tostring(getTimestampMs())
        t:waitUntil(K.standing(id), K.STAND_MS, function(t1)
            viewStep(t1, { phase = "begin", key = key }, function(t2)
                K.noLoot(id)   -- no loot ammo added after the rounds given here
                local ok, why = K.E().setWeapon(id, GUN)
                t2:ok(ok, "setWeapon refused: " .. tostring(why))
                local added, why2 = Am().give(id, GUN, ROUNDS, 0)
                t2:eq(ROUNDS, added, "rounds given (" .. tostring(why2) .. ")")
                local z0 = B().find(id)
                local st = C().stats
                local keys = { "shots", "hits", "misses", "reloads", "noises", "applied", "outOfAmmo" }
                local before = snapshot(st, keys)
                local noAmmo0 = st.why["no ammo"] or 0
                local V = LivingKnox.CombatView
                local vbefore = V ~= nil and snapshot(V.stats, { "shotsPlayed", "shotsDuplicate", "flashes" }) or nil
                local c, why3 = C().engage(id, p:getUsername(), { source = "api", why = "suite lk.ranged" })
                t2:ok(c ~= nil, "engage refused: " .. tostring(why3))
                local order = C().get(id)
                t2:eq("ranged", order and order.m, "kind of the order")
                measure("engaged: ranged #" .. tostring(c) .. " with " .. tostring(order and order.t) .. ", range "
                    .. tostring(order and K.round(order.reach)) .. ", one shot every " .. tostring(order and order.iv)
                    .. " ms, " .. tostring(Am().available(z0, GUN)) .. " round(s) available")
                t2:waitUntil(function()
                    local o = C().get(id)
                    return o == nil or o.m ~= "ranged"
                end, WAIT_MS, function(t3)
                    local d = {}
                    for _, k in ipairs(keys) do d[k] = (st[k] or 0) - before[k] end
                    local o = C().get(id)
                    local zb = B().find(id)
                    measure("shots " .. d.shots .. ", hits " .. d.hits .. ", misses " .. d.misses .. ", reloads "
                        .. d.reloads .. ", noises " .. d.noises .. ", refused for no ammo "
                        .. ((st.why["no ammo"] or 0) - noAmmo0) .. ", rounds left "
                        .. tostring(zb and Am().available(zb, GUN)) .. ", next order " .. tostring(o and o.m) .. " with "
                        .. tostring(o and o.t))
                    t3:eq(ROUNDS, d.shots, "shots accepted by the authority (one per round, never more)")
                    t3:ok(d.reloads >= 1, "no reload")
                    t3:eq(d.shots, d.noises, "one noise per shot")
                    t3:eq(d.shots, d.hits + d.misses, "every shot is a hit or a miss")
                    t3:eq(d.hits, d.applied, "damage applied once per hit")
                    t3:eq(1, d.outOfAmmo, "out of ammo once")
                    t3:eq(0, zb and Am().available(zb, GUN) or 0, "rounds left on the body")
                    t3:eq("melee", o and o.m, "order after the last round")
                    t3:eq("Base.BareHands", o and o.t, "weapon after the last round")
                    if V ~= nil and vbefore ~= nil then
                        local played = V.stats.shotsPlayed - vbefore.shotsPlayed
                        measure("played here: " .. played .. ", duplicates " .. (V.stats.shotsDuplicate
                            - vbefore.shotsDuplicate) .. ", flashes " .. (V.stats.flashes - vbefore.flashes))
                        t3:eq(d.shots, played, "shots played here (sound and flash once each)")
                        t3:eq(0, V.stats.shotsDuplicate - vbefore.shotsDuplicate, "duplicate shots")
                    else
                        measure("no CombatView on this side (dedicated server): sound and flash checked by every client")
                    end
                    viewStep(t3, { phase = "end", key = key, shots = d.shots }, function() end)
                end, "the npc still holds a ranged order after " .. WAIT_MS .. " ms")
            end)
        end, "npc still on the floor")
    end)
end)
