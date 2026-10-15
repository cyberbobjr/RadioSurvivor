--[[
lk.weaponswap - weapon of a living Living Knox npc replaced by another mod, nothing lost (LK07-T08,
LivingKnox.Equipment.adoptForeign, LivingKnox.Ammo.convert, LivingKnox.Combat). Tag "world": the authority only, on a
save named rstest*, with a target player (t.ctx.player); the Living Knox option Enabled must be on.
Solo: RST.run({ suite = "lk.weaponswap", tags = "world" }). Asynchronous run only (about 15 s).

Automated (real Java objects, on the authority):
    replaced   an npc is spawned 5 squares from the target player, who is protected by god mode; its weapon is set
               to Base.Pistol with LOOSE loose rounds, one full magazine (LivingKnox.Ammo.give) and LOADED rounds in
               the weapon (LivingKnox.Ammo.setLoaded). Once the pistol hangs on its holster, the suite does what a
               weapon mod does: the attached pistol is replaced, at the same location, by a new REPLACEMENT item (an
               other firearm: other attachment slot, other ammo, no magazine), sent to the clients on a server. The
               engine must adopt it: registry weapon = REPLACEMENT, the same object moved to its own slot, the old
               slot empty, every round kept (rounds usable by REPLACEMENT = rounds before, no 9 mm round left). The
               npc is then engaged against the player: the order must be a ranged one with REPLACEMENT and at least
               two shots must be accepted within WAIT_MS.
               With a weapon mod active, the mod may in turn replace the pistol or REPLACEMENT itself (in-game run of
               2026-10-13: Guns of Marz turned the shotgun into MarzGuns.REMINGTON_870): the weapon adopted is then
               whatever foreign firearm ends attached, and every check uses that weapon.
Figures are printed as "[LKW] measure ..." lines. The npc is forgotten and the god mode restored with t:defer.
With a weapon mod that replaces vanilla weapons, run lk.ranged as well: its pistol may be replaced in the same way.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local B = K.B
local measure = K.measurer("[LKW]")
local GUN = "Base.Pistol"
local GUN_SLOT = "Holster Right"
local SHOTGUN = "Base.Shotgun"   -- REPLACEMENT of the header
local LOOSE, LOADED = 4, 9
local ADOPT_MS = 5000
local WAIT_MS = 20000

local function C() return LivingKnox and LivingKnox.Combat end
local function Am() return LivingKnox and LivingKnox.Ammo end

-- Count and rounds of the items of type t in the inventory of body z (first level).
local function items(z, t)
    local n, rounds = 0, 0
    local list = z:getInventory():getItems()
    for i = 0, list:size() - 1 do
        local it = list:get(i)
        if it ~= nil and it:getFullType() == t then
            n = n + 1
            local c = it:getCurrentAmmoCount()
            if type(c) == "number" then rounds = rounds + c end
        end
    end
    return n, rounds
end

local function typeOf(item)
    return item and item:getFullType() or "nil"
end

RST.suite("lk.weaponswap", { tags = { "world" }, testTimeoutMs = 60000, timeoutMs = 120000 }, function(s)
    s.test("replaced weapon adopted, ammo kept, npc fires with it", function(t)
        local E = K.E()
        t:ok(B() ~= nil and E ~= nil and E.adoptForeign ~= nil and C() ~= nil and Am() ~= nil
            and Am().convert ~= nil, "LivingKnox.Equipment.adoptForeign and LivingKnox.Ammo.convert (LK07-T08) are "
            .. "not loaded on this side")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the target player")
        local x, y, zl = math.floor(p:getX()) + 5, math.floor(p:getY()), math.floor(p:getZ())
        local id, body = B().spawn({}, x, y, zl)
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
        t:defer(function() C().disengage(id, "suite lk.weaponswap over") end, "end the combat of " .. id)
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
            K.noLoot(id)
            local ok, why = E.setWeapon(id, GUN)
            t2:ok(ok, "setWeapon refused: " .. tostring(why))
            local spec = Am().spec(GUN)
            t2:ok(spec ~= nil and spec.mag ~= nil, "no magazine for " .. GUN)
            local added = Am().give(id, GUN, LOOSE, 1)
            t2:eq(LOOSE + spec.max, added, "rounds given")
            local z0 = B().find(id)
            t2:eq(LOADED, Am().setLoaded(z0, GUN, LOADED), "rounds in the weapon")
            local total = Am().available(z0, GUN)
            t2:waitUntil(function()
                local z = B().find(id)
                return z ~= nil and typeOf(z:getAttachedItem(GUN_SLOT)) == GUN
            end, ADOPT_MS, function(t3)
                local z = B().find(id)
                local new = instanceItem(SHOTGUN)
                t3:ok(new ~= nil, "cannot create " .. SHOTGUN)
                z:setAttachedItem(GUN_SLOT, new)   -- what a weapon mod does
                if isServer() then sendAttachedItem(z, GUN_SLOT, new) end
                local adopted0 = E.stats.adopted or 0
                -- The weapon adopted: REPLACEMENT, or what a weapon mod turned the pistol or REPLACEMENT into.
                local function adoptedItem()
                    local zc = B().find(id)
                    local w = E.wantedOf(id)
                    if zc == nil or w == nil or w.t == GUN or w.l == nil then return nil end
                    local it = zc:getAttachedItem(w.l)
                    if it ~= nil and it:getFullType() == w.t then return it end
                    return nil
                end
                t3:waitUntil(function() return adoptedItem() ~= nil end, ADOPT_MS, function(t4)
                    local zb = B().find(id)
                    local w = E.wantedOf(id)
                    local REPLACEMENT = w.t
                    if REPLACEMENT ~= SHOTGUN then
                        measure("weapon mod replaced the weapons: adopted " .. REPLACEMENT .. " instead of " .. SHOTGUN)
                    end
                    new = adoptedItem()
                    local rspec = Am().spec(REPLACEMENT)
                    t4:ok(rspec ~= nil, "no ammo spec for the adopted " .. REPLACEMENT)
                    local clips, clipRounds = items(zb, spec.mag)
                    local bullets = items(zb, spec.round)
                    measure("adopted " .. REPLACEMENT .. " at " .. tostring(w.l) .. ": " .. GUN_SLOT .. " "
                        .. typeOf(zb:getAttachedItem(GUN_SLOT)) .. ", rounds before " .. total .. ", usable after "
                        .. Am().available(zb, REPLACEMENT) .. " (" .. Am().loaded(zb, REPLACEMENT) .. " in the "
                        .. "weapon), " .. spec.round .. " left " .. bullets .. ", " .. spec.mag .. " x" .. clips
                        .. " with " .. clipRounds .. " round(s)")
                    t4:ok((E.stats.adopted or 0) - adopted0 <= 1, "more than one adoption")
                    t4:ok(rawequal(zb:getAttachedItem(w.l), new), "replacement not moved to its slot " .. w.l)
                    if w.l ~= GUN_SLOT then t4:eq("nil", typeOf(zb:getAttachedItem(GUN_SLOT)), "old slot") end
                    t4:eq(total, Am().available(zb, REPLACEMENT), "rounds usable by " .. REPLACEMENT)
                    t4:eq(math.min(LOADED, rspec.max), Am().loaded(zb, REPLACEMENT), "rounds in the weapon")
                    t4:eq(0, bullets, "loose rounds of the old weapon")
                    t4:eq(0, clipRounds, "rounds left in magazines of the old weapon")
                    local st = C().stats
                    local shots0 = st.shots or 0
                    local c, why2 = C().engage(id, p:getUsername(), { source = "api", why = "suite lk.weaponswap" })
                    t4:ok(c ~= nil, "engage refused: " .. tostring(why2))
                    local order = C().get(id)
                    t4:eq("ranged", order and order.m, "kind of the order")
                    t4:eq(REPLACEMENT, order and order.t, "weapon of the order")
                    t4:waitUntil(function() return (st.shots or 0) - shots0 >= 2 end, WAIT_MS, function(t5)
                        local o = C().get(id)
                        measure("shots " .. ((st.shots or 0) - shots0) .. " with " .. tostring(o and o.t)
                            .. ", rounds left " .. Am().available(B().find(id), REPLACEMENT))
                        t5:eq(REPLACEMENT, o and o.t, "weapon of the order after the shots")
                        t5:eq(REPLACEMENT, E.wantedOf(id).t, "registry weapon after the shots")
                    end, "fewer than 2 shots with " .. REPLACEMENT .. " after " .. WAIT_MS .. " ms")
                end, "replacement not adopted within " .. ADOPT_MS .. " ms")
            end, GUN .. " never attached to " .. GUN_SLOT)
        end, "npc still on the floor")
    end)
end)
