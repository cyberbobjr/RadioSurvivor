--[[
lk.loot - real loot of the corpse of a Living Knox npc (LK07-T05, LivingKnox.Loot, LivingKnox.Ammo).
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on. Solo: RST.run({ suite = "lk.loot", tags = "world" }); dedicated server:
RST.server({ suite = "lk.loot", tags = "world" }) from an admin client. Asynchronous run only (under 1 minute).

Automated (by code, real Java objects, on the authority):
    build      npc with a pistol (registry weapon) and, through a test seam on Loot.contextOf, the pockets of a
               medic at ammo level 50: one build (Loot.stats.built + 1), rounds in the weapon and spare magazines
               from the level, the medic pocket items in the body inventory; a second pass and a second build add
               nothing;
    death      same npc killed by Health.kill: one corpse carrying the pistol once, in its container AND attached
               to its slot (the item every client receives), the loaded rounds turned into a magazine item, the
               pocket items, no pistol on the ground around the corpse. The measure lists the creation hooks
               (OnCreate of the item scripts, none in vanilla for the pistol, its magazine and its rounds) and the
               whole corpse content. A creation hook set by another mod (a firearm overhaul that swaps vanilla
               guns, magazines and ammo once they leave a zombie inventory) makes the test SKIP with its name
               (LK07-T07), unless it is the known overhaul whose swap switches (SandboxVars.MarzGuns.Vanilla*
               Replacement) the test turns off for its own duration;
    swap on    with that swap on (as installed), the corpse still holds exactly one firearm (vanilla or swapped):
               the loot follows the weapon mod, as for zombies (decision of 2026-10-12). Without that mod (decision of
               2026-10-15, nothing cut), the minimal overhaul of the test mod plays its part (RST_GunSwap.lua: creation
               hook on the pistol script, the pistol swapped for RSTGuns.TestPistol in the corpse container and its
               slot at the next tick): one firearm in the corpse, the swapped one, no vanilla pistol left.
Figures are printed as "[LKL] measure ..." lines. Every test forgets its npc and removes its corpse with t:defer.

E01-T16 (LK07-T05): every client sees the same corpse content and the same items on the floor around it (world.keys,
corpse and floor); on a dedicated server the second client then grabs the corpse, drags it a moment and lets it go
(RST.Steps "corpse.drag", RST_PeerChecksLK2.lua: vanilla grab and let go): one tagged corpse again, same content on
the authority, no second loot build, and the same corpse and floor on every client.
Manual protocol (docs/annexes/conception/sante.md, "Butin reel du cadavre (LK07-T05)"): loot a materialized group member,
check the weapon, the ammo and the pocket items of its role; MP: two clients see the same items, nothing duplicated.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_GunSwap"
require "RST/RST_PeerChecks"
require "RST/RST_PeerChecksLK2"

local K = RST.LKHelpers
local B, I = K.B, K.I
local measure = K.measurer("[LKL]")
local PISTOL = "Base.Pistol"
local SLOT = "Holster Right"
local LEVEL = 50
local ROLE = "medic"
local RADIUS = 3
local DEAD_MS = 5000

local replacementOff   -- defined below (LK07-T07)
local function L() return LivingKnox and LivingKnox.Loot end
local function H() return LivingKnox and LivingKnox.Health end
local function A() return LivingKnox and LivingKnox.Ammo end

local function countIn(items, t)
    local n, rounds = 0, 0
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it ~= nil and it:getFullType() == t then
            n = n + 1
            local c = it:getCurrentAmmoCount()
            if type(c) == "number" then rounds = rounds + c end
        end
    end
    return n, rounds
end

-- OnCreate of the item script t (Item.getLuaCreate), or nil. None in vanilla for the types used here; another mod's
-- creation hook may swap the item later (LK07-T07).
local function createHook(t)
    local sm = t and getScriptManager()
    local s = sm and sm:FindItem(t)
    return s and s:getLuaCreate() or nil
end

-- Creation hooks of the types ts, as "type=function" entries.
local function hooksOf(ts)
    local out = {}
    for _, t in ipairs(ts) do
        local h = createHook(t)
        if h ~= nil then out[#out + 1] = t .. "=" .. tostring(h) end
    end
    return out
end

-- Whole content of a container, "type xN" sorted by type.
local function summary(items)
    local n, keys = {}, {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local t = it and it:getFullType()
        if t ~= nil then
            if n[t] == nil then
                n[t] = 0
                keys[#keys + 1] = t
            end
            n[t] = n[t] + 1
        end
    end
    table.sort(keys)
    local out = {}
    for _, t in ipairs(keys) do out[#out + 1] = t .. " x" .. n[t] end
    return #out > 0 and table.concat(out, ", ") or "nothing"
end

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

-- Pistols lying on the ground around (x, y, z).
local function groundCount(t, x, y, z)
    local n = 0
    for dy = -RADIUS, RADIUS do
        for dx = -RADIUS, RADIUS do
            local sq = getCell():getGridSquare(x + dx, y + dy, z)
            local list = sq and sq:getWorldObjects()
            if list ~= nil then
                for i = 0, list:size() - 1 do
                    local o = list:get(i)
                    local it = instanceof(o, "IsoWorldInventoryObject") and o:getItem() or nil
                    if it ~= nil and it:getFullType() == t then n = n + 1 end
                end
            end
        end
    end
    return n
end

-- New armed npc next to the player, with the medic pockets (test seam on Loot.contextOf, restored by t:defer).
-- waitCopies: MP, wait until the other clients hold their copy of the body (a death is checked there).
local function armedNpc(t, cont, waitCopies)
    t:ok(B() ~= nil and L() ~= nil and H() ~= nil and A() ~= nil,
        "LivingKnox.Loot (LK07-T05) is not loaded on this side")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ())
    local original = L().contextOf
    L().contextOf = function() return { role = ROLE, level = LEVEL } end
    t:defer(function() L().contextOf = original end, "restore Loot.contextOf")
    local id, body = B().spawn({}, x, y, z)
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    t:defer(function() B().despawn(id, true) end, "forget " .. id)
    t:defer(function()
        for _, o in ipairs(corpsesOf(id, x, y, z)) do o:getSquare():removeCorpse(o, false) end
    end, "remove the corpse of " .. id)
    local armed, why = LivingKnox.Equipment.setWeapon(id, PISTOL)
    t:ok(armed, "weapon refused: " .. tostring(why))
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        local zb = B().find(id)
        t2:ok(zb ~= nil, "npc body lost")
        if not waitCopies then return cont(t2, { id = id, p = p, x = x, y = y, z = z, body = zb }) end
        -- MP: the other clients must hold their copy before the death, or they never get its corpse (vanilla).
        RST.PeerChecks.waitCopies(t2, { zb }, function(t3)
            cont(t3, { id = id, p = p, x = x, y = y, z = z, body = zb })
        end)
    end, "npc still on the floor")
end

-- Swap switches of a firearm overhaul that replaces vanilla guns, magazines and ammo through creation hooks (read in
-- SandboxVars at each call). Returns the table and its switch names, or nil.
local SWAP_SWITCHES = { "VanillaWeaponReplacement", "VanillaAmmoReplacement", "VanillaAttachmentReplacement" }
local function swapSwitches()
    local vars = SandboxVars and SandboxVars.MarzGuns
    if type(vars) ~= "table" then return nil end
    return vars
end

-- Switches the replacement off until the end of the test; true when it was on.
replacementOff = function(t)
    local vars = swapSwitches()
    if vars == nil then return false end
    local saved, on = {}, false
    for _, k in ipairs(SWAP_SWITCHES) do
        saved[k] = vars[k]
        if vars[k] then on = true end
        vars[k] = false
    end
    t:defer(function()
        for _, k in ipairs(SWAP_SWITCHES) do vars[k] = saved[k] end
    end, "restore the swap switches of the firearm overhaul")
    measure("firearm overhaul swap switches " .. (on and "on: switched off for the test" or "already off"))
    return on
end

RST.suite("lk.loot", { tags = { "world", "server" }, testTimeoutMs = 45000, timeoutMs = 120000 }, function(s)
    s.test("loot built once: ammo from the level, pockets of the role", function(t)
        armedNpc(t, function(t2, c)
            local built0 = L().stats.built
            L().pass()
            local spec = A().spec(PISTOL)
            t2:ok(spec ~= nil and spec.mag ~= nil, PISTOL .. " is not a magazine firearm")
            local plan = L().ammoPlan(PISTOL, LEVEL)
            local items = c.body:getInventory():getItems()
            local mags, magRounds = countIn(items, spec.mag)
            local bandages = countIn(items, "Base.Bandage")
            local wipes = countIn(items, "Base.AlcoholWipes")
            local loaded = A().loaded(c.body, PISTOL)
            local again = L().build(c.id, c.body)
            L().pass()
            local mags2 = countIn(c.body:getInventory():getItems(), spec.mag)
            measure("build: built +" .. (L().stats.built - built0) .. ", loaded " .. loaded .. ", spare magazines "
                .. mags .. " (" .. magRounds .. " rounds), bandages " .. bandages .. ", wipes " .. wipes
                .. ", second build " .. tostring(again) .. ", magazines after " .. mags2)
            t2:eq(1, L().stats.built - built0, "builds")
            t2:eq(plan.loaded, loaded, "rounds in the weapon")
            t2:eq(plan.mags, mags, "spare magazines")
            t2:eq(plan.mags * spec.max, magRounds, "rounds in the spare magazines")
            t2:eq(2, bandages, "medic bandages")
            t2:eq(1, wipes, "medic alcohol wipes")
            t2:eq(false, again, "second build accepted")
            t2:eq(mags, mags2, "items added twice")
        end)
    end)

    s.test("death keeps the weapon in the corpse, loaded rounds become items", function(t)
        -- LK07-T07: a known firearm overhaul reads its swap switches from SandboxVars when an item is created: switched
        -- off for this test only, before any item is made (restored at the end); the vanilla loot must stay as built.
        local off = replacementOff(t)
        armedNpc(t, function(t2, c)
            L().pass()
            local spec = A().spec(PISTOL)
            local loaded = A().loaded(c.body, PISTOL)
            local _, spare = countIn(c.body:getInventory():getItems(), spec.mag)
            local hooks = hooksOf({ PISTOL, spec.mag, spec.round })
            if off then hooks = {} end
            local ok, why = H().kill(c.id)
            t2:ok(ok, "direct death refused: " .. tostring(why))
            t2:waitUntil(function() return #corpsesOf(c.id, c.x, c.y, c.z) == 1 end, DEAD_MS, function(t3)
                t3:sleep(1000, function(t4)
                    local corpses = corpsesOf(c.id, c.x, c.y, c.z)
                    local body = corpses[1]
                    local items = body:getContainer():getItems()
                    local guns = countIn(items, PISTOL)
                    local mags, rounds = countIn(items, spec.mag)
                    local att = body:getAttachedItems() and body:getAttachedItems():getItem(SLOT) or nil
                    local attachedIn = att ~= nil and body:getContainer():contains(att)
                    local ground = groundCount(PISTOL, c.x, c.y, c.z)
                    measure("death: corpses " .. #corpses .. ", pistols in the corpse " .. guns .. ", attached "
                        .. tostring(att and att:getFullType()) .. " in the container " .. tostring(attachedIn)
                        .. ", magazines " .. mags .. " (" .. rounds .. " rounds, expected " .. (loaded + spare)
                        .. "), bandages " .. countIn(items, "Base.Bandage") .. ", pistols on the ground " .. ground
                        .. ", creation hooks " .. (#hooks > 0 and table.concat(hooks, " ") or "none")
                        .. ", corpse content: " .. summary(items))
                    t4:eq(1, #corpses, "tagged corpses")
                    if #hooks > 0 then
                        t4:skip("creation hooked by another mod (" .. table.concat(hooks, " ") .. "): vanilla "
                            .. "items may be swapped in the corpse after the death; run on a save without this "
                            .. "replacement (LK07-T07)")
                    end
                    t4:eq(1, guns, "pistols in the corpse")
                    t4:eq(PISTOL, att and att:getFullType() or nil, "weapon attached on the corpse")
                    t4:eq(true, attachedIn, "attached weapon in the corpse container")
                    t4:eq(loaded + spare, rounds, "rounds in the corpse magazines")
                    t4:eq(2, countIn(items, "Base.Bandage"), "pocket bandages in the corpse")
                    t4:eq(0, ground, "pistols on the ground")
                    -- E01-T16: the other clients see the same corpse content (weapon, magazines, pockets).
                    local csq = body:getSquare()
                    local area = RST.PeerChecks.around(csq:getX(), csq:getY(), csq:getZ(), 2)
                    RST.PeerChecks.checkSquares(t4, area, { corpse = true, floor = true }, function(t5)
                        -- LK07-T05 (E01-T16): the corpse dragged and let go by the second client.
                        local others = RST.Steps.others(t5)
                        if not isServer() or #others == 0 then
                            t5:note("corpse drag not checked: needs a dedicated server and a second client")
                            return
                        end
                        local before, built0 = RST.PeerChecks.corpseKey(body), L().stats.built
                        RST.Steps.ask(t5, "corpse.drag", { x = csq:getX(), y = csq:getY(), z = csq:getZ(), r = 1,
                            holdMs = 1500 }, { target = { others[1] }, timeoutMs = 20000 }, function(t6)
                            t6:waitUntil(function() return #corpsesOf(c.id, c.x, c.y, c.z) == 1 end, DEAD_MS,
                                function(t7)
                                    local again = corpsesOf(c.id, c.x, c.y, c.z)[1]
                                    t7:eq(before, RST.PeerChecks.corpseKey(again), "corpse content after the drag")
                                    t7:eq(built0, L().stats.built, "loot built again after the drag")
                                    local dsq = again:getSquare()
                                    RST.PeerChecks.checkSquares(t7, RST.PeerChecks.around(dsq:getX(), dsq:getY(),
                                        dsq:getZ(), 2), { corpse = true, floor = true }, nil, true)
                                end, "no single tagged corpse after the drag")
                        end)
                    end, true)
                end)
            end, "no corpse after the direct death")
        end, true)
    end)

    -- LK07-T07, decision of 2026-10-12: with the swap of a firearm overhaul on, the corpse loot follows that mod as for
    -- zombies: one firearm (vanilla or swapped) in the corpse, the hook named in the measure.
    s.test("with a firearm overhaul swapping vanilla guns: the corpse still holds one firearm", function(t)
        local vars = swapSwitches()
        -- Decision of 2026-10-15 (nothing cut): without an installed overhaul, the swap of the test mod
        -- (RST_GunSwap.lua: creation hook on the pistol script, swap in the corpse container and slot) plays its part.
        local double = vars == nil or not vars.VanillaWeaponReplacement
        if double then
            if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
            RST.GunSwap.enable(t, PISTOL)
            measure("no installed firearm overhaul with its swap on: test swap " .. PISTOL .. " -> " .. RST.GunSwap.TO)
        end
        armedNpc(t, function(t2, c)
            L().pass()
            local spec = A().spec(PISTOL)
            local hooks = hooksOf({ PISTOL, spec.mag, spec.round })
            local ok, why = H().kill(c.id)
            t2:ok(ok, "direct death refused: " .. tostring(why))
            t2:waitUntil(function() return #corpsesOf(c.id, c.x, c.y, c.z) == 1 end, DEAD_MS, function(t3)
                t3:sleep(2000, function(t4)
                    local body = corpsesOf(c.id, c.x, c.y, c.z)[1]
                    local items = body:getContainer():getItems()
                    local guns = 0
                    for i = 0, items:size() - 1 do
                        local it = items:get(i)
                        if instanceof(it, "HandWeapon") and it:isRanged() then guns = guns + 1 end
                    end
                    measure("swap on: creation hooks " .. (#hooks > 0 and table.concat(hooks, " ") or "none")
                        .. ", firearms in the corpse " .. guns .. ", corpse content: " .. summary(items))
                    t4:eq(1, guns, "firearms in the corpse")
                    if double then
                        local st = RST.GunSwap.stats
                        measure("test swap: created " .. st.created .. ", swapped " .. st.swapped .. ", attachment slots "
                            .. st.attached .. ", pistols left " .. countIn(items, PISTOL) .. ", swapped guns "
                            .. countIn(items, RST.GunSwap.TO))
                        t4:ok(st.swapped >= 1, "the test swap never replaced the pistol in the corpse")
                        t4:eq(0, countIn(items, PISTOL), "vanilla pistols left in the corpse after the swap")
                        t4:eq(1, countIn(items, RST.GunSwap.TO), "swapped firearms in the corpse")
                    end
                end)
            end, "no corpse after the direct death")
        end)
    end)
end)
