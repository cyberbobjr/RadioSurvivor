--[[
lk.equipment - Living Knox npc weapons (LK02-T06, LivingKnox.Equipment). Tags "world" and "server": a save named
rstest*, with a target player (t.ctx.player); the Living Knox option Enabled on. Solo: the authority creates the npc and
the same machine displays it (hand items are set by the display machine, never by a server). Run:
RST.run({ suite = "lk.equipment", tags = "world" }). Asynchronous run only (about 1 minute; do not pause the game).
Dedicated server (E01-T19, campaign mp): RST.server({ suite = "lk.equipment", tags = "world" }): the server creates the
npc, sets its weapon and gestures, and EVERY connected client (requester and second client, LK02-T06) checks what it
displays, with the same checks, through RST.Steps (RST_ViewSteps.lua: lk.weapon.state, lk.weapon.count); no client
online: SKIP. On an MP client every test
is SKIP.

For each weapon: attached at its slot at rest (hands empty, variable Weapon empty), in hand for aim / guard / strike
(slot empty, Weapon = expected WeaponType value, LKActor node live), attached again back to idle; at the end the
weapon is removed and nothing is left on the body.
OnEquipPrimary: a temporary subscriber counts the events raised for the npc body, and
LivingKnox.Equipment.stats.skipped counts the calls of the vanilla fishing handler skipped for a non player. An error
of another subscriber is not visible from Lua: count the "handleFishing" lines of console.txt before and after the
run (protocol in docs/conception/equipement.md). Figures are printed as "[LKW] measure ..." lines. Every test
removes its npc with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/suites/RST_LKAnims"
require "RST/RST_LKHelpers"
require "RST/RST_Steps"
require "RST/RST_ViewSteps"

RST.LKEquipment = RST.LKEquipment or {}
local P = RST.LKEquipment

local STAND_MS = RST.LKHelpers.STAND_MS
local SETTLE_MS = 600       -- display pass every 3 ticks
local GESTURE_MS = 1200     -- blend times are 0.15 to 0.5 s

P.GESTURES = { "aim", "guard", "strike" }
-- Vanilla items (media/scripts/generated/items/weapon.txt, AttachmentType) and the slot of LK_Equipment.LOCATIONS;
-- weapon = WeaponType value with the item in hand (both hands for a two-handed item); node per gesture
-- (tools/anim_table.json).
P.CASES = {
    firearms = {
        { item = "Base.Shotgun", slot = "Rifle On Back", weapon = "firearm", nodes = { aim = "LKActorAimRifle" } },
        { item = "Base.Pistol", slot = "Holster Right", weapon = "handgun", nodes = { aim = "LKActorAimHandgun" } },
    },
    melee = {
        { item = "Base.BaseballBat", slot = "Shovel Back", weapon = "2handed",
            nodes = { guard = "LKActorGuard2H", strike = "LKActorStrike2H" } },
        { item = "Base.HandAxe", slot = "Belt Left", weapon = "1handed",
            nodes = { guard = "LKActorGuard1H", strike = "LKActorStrike1H" } },
    },
}

local function B() return LivingKnox and LivingKnox.Bodies end
local function A() return LivingKnox and LivingKnox.Anim end
local function E() return LivingKnox and LivingKnox.Equipment end
local function G() return LivingKnox and LivingKnox.ZombieGuard end

local function measure(text)
    print("[LKW] measure " .. tostring(text))
end

local function call(z, method, ...)
    local ok, v = pcall(z[method], z, ...)
    if ok then return v end
    return nil
end

local function typeOf(item)
    if item == nil then return "" end
    return item:getFullType()
end

-- Weapon facts of a character as displayed here: { hand, second, slot (item at slot), weapon (variable Weapon) }.
function P.state(z, slot)
    local out = { hand = typeOf(call(z, "getPrimaryHandItem")), second = typeOf(call(z, "getSecondaryHandItem")) }
    out.slot = slot and typeOf(call(z, "getAttachedItem", slot)) or ""
    out.weapon = call(z, "getVariableString", "Weapon") or ""
    return out
end

function P.describe(s)
    return "hand=" .. s.hand .. " second=" .. s.second .. " slot=" .. s.slot .. " Weapon=" .. s.weapon
end

local function has(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function onServer() return type(isServer) == "function" and isServer() end

-- Solo (the authority displays the body) or a dedicated server (the requester client checks what it displays).
local function needSolo(t)
    if onServer() then return end
    if not (LivingKnox and LivingKnox.isAuthority() and LivingKnox.hasLocalPlayer()) then
        t:skip("solo or dedicated server only: the authority must display the body, or ask its requester client")
    end
end

local ASK_MS = 10000

-- E01-T19: a check of the requester client (RST_ViewSteps.lua), then after(t2). LK02-T06: asked to every connected
-- client (target "all"; solo: the local player only), so that the second client sees the same weapon states.
local function ask(t, step, args, after)
    RST.Steps.ask(t, step, args, { target = "all", timeoutMs = ASK_MS, none = "skip" }, after)
end

local function spawnNpc(t, dx, dy)
    t:ok(B() ~= nil and A() ~= nil and E() ~= nil and G() ~= nil, "LivingKnox.Bodies, Anim, Equipment or ZombieGuard"
        .. " is not loaded")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local x, y, z = math.floor(p:getX()) + dx, math.floor(p:getY()) + dy, math.floor(p:getZ())
    local id, body = B().spawn({}, x, y, z)
    if id then
        t:defer(function()
            E().setWeapon(id, nil)
            A().setGesture(id, "idle")
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id
end

local standing = RST.LKHelpers.standing

local function body(t, id)
    local z = B().find(id)
    t:ok(z ~= nil, "npc body lost")
    return z
end

local function checkRest(t, id, c, label)
    local s = P.state(body(t, id), c.slot)
    measure(c.item .. " " .. label .. ": " .. P.describe(s))
    t:eq(c.item, s.slot, c.item .. " " .. label .. ": item at " .. c.slot)
    t:eq("", s.hand, c.item .. " " .. label .. ": primary hand")
    t:eq("", s.second, c.item .. " " .. label .. ": secondary hand")
    t:eq("", s.weapon, c.item .. " " .. label .. ": variable Weapon")
end

local function checkGesture(t, id, c, g)
    local z = body(t, id)
    local s = P.state(z, c.slot)
    local info = RST.LKAnims.info(z)
    measure(c.item .. " " .. g .. ": " .. P.describe(s) .. "; " .. RST.LKAnims.describe(info))
    t:eq(c.item, s.hand, c.item .. " " .. g .. ": primary hand")
    t:eq("", s.slot, c.item .. " " .. g .. ": slot " .. c.slot .. " not emptied")
    if c.weapon ~= nil then t:eq(c.weapon, s.weapon, c.item .. " " .. g .. ": variable Weapon") end
    if c.nodes[g] ~= true then
        t:ok(has(info.nodes, c.nodes[g]), c.item .. " " .. g .. ": node " .. c.nodes[g] .. " not live ("
            .. table.concat(info.nodes, ",") .. ")")
    end
end

-- Dedicated server: the same sequence, each check made by every connected client on its copy of the body (LK02-T06).
local function runCasesRemote(t, cases, id)
    local key = id .. "-" .. tostring(getTimestampMs())
    local function finish(tc)
        E().setWeapon(id, nil)
        local last = cases[#cases]
        ask(tc, "lk.weapon.state", { npc = id, slot = last.slot, item = last.item, mode = "none",
            label = "weapon removed" }, function(t3)
            ask(t3, "lk.weapon.count", { npc = id, phase = "end", key = key }, function(t4, res)
                for _, e in ipairs(res.list or {}) do
                    if e.data then
                        measure("weapon removed; OnEquipPrimary events for the npc " .. tostring(e.data.events)
                            .. ", fishing handler calls skipped " .. tostring(e.data.skipped) .. ", Lua errors "
                            .. tostring(e.data.errors) .. " (client " .. tostring(e.user) .. ")")
                    end
                end
                t4:note("checked by " .. #(res.list or {}) .. " client(s)")
            end)
        end)
    end
    local function caseStep(tc, ci)
        local c = cases[ci]
        if c == nil then return finish(tc) end
        A().setGesture(id, "idle")
        local ok, why = E().setWeapon(id, c.item)
        tc:ok(ok, "setWeapon " .. c.item .. ": " .. tostring(why))
        local base = { npc = id, slot = c.slot, item = c.item }
        local function args(extra)
            local out = {}
            for k, v in pairs(base) do out[k] = v end
            for k, v in pairs(extra) do out[k] = v end
            return out
        end
        ask(tc, "lk.weapon.state", args({ mode = "rest", label = "at rest" }), function(t3)
            local gestures = {}
            for _, g in ipairs(P.GESTURES) do
                if c.nodes[g] then gestures[#gestures + 1] = g end
            end
            local function gestureStep(tg, gi)
                local g = gestures[gi]
                if g == nil then
                    A().setGesture(id, "idle")
                    ask(tg, "lk.weapon.state", args({ mode = "rest", label = "back to idle" }), function(t4)
                        caseStep(t4, ci + 1)
                    end)
                    return
                end
                A().setGesture(id, g)
                local node = c.nodes[g] ~= true and c.nodes[g] or nil
                ask(tg, "lk.weapon.state", args({ mode = "hand", label = g, weapon = c.weapon, node = node }),
                    function(t4) gestureStep(t4, gi + 1) end)
            end
            gestureStep(t3, 1)
        end)
    end
    ask(t, "lk.weapon.count", { npc = id, phase = "begin", key = key }, function(t2) caseStep(t2, 1) end)
end

-- One npc, every case in turn, then the weapon removed; OnEquipPrimary events and skipped fishing calls compared.
local function runCases(t, cases, dx, dy)
    needSolo(t)
    local id = spawnNpc(t, dx, dy)
    if onServer() then
        t:waitUntil(standing(id), STAND_MS, function(t2) runCasesRemote(t2, cases, id) end, "npc still on the floor")
        return
    end
    local count = { events = 0 }
    local function onEquip(chr)
        if chr ~= nil and chr == B().find(id) then count.events = count.events + 1 end
    end
    Events.OnEquipPrimary.Add(onEquip)
    t:defer(function() Events.OnEquipPrimary.Remove(onEquip) end, "remove the OnEquipPrimary counter")
    local skipped0 = E().stats.skipped
    -- LK02-T13: Lua errors raised during the cases (any subscriber of OnEquipPrimary / OnEquipSecondary included),
    -- read from the error counter of the Lua debugger (getLuaDebuggerErrorCount, LuaManager.java:6437).
    local errors0 = getLuaDebuggerErrorCount and getLuaDebuggerErrorCount() or nil

    local function finish(tc)
        E().setWeapon(id, nil)
        tc:sleep(SETTLE_MS, function(t3)
            local last = cases[#cases]
            local s = P.state(body(t3, id), last.slot)
            local skipped = E().stats.skipped - skipped0
            local fishing = Fishing ~= nil and Fishing.Handler ~= nil
            measure("weapon removed: " .. P.describe(s) .. "; OnEquipPrimary events for the npc " .. count.events
                .. ", fishing handler calls skipped " .. skipped .. " (fishing handler loaded: " .. tostring(fishing)
                .. ")")
            t3:eq("", s.hand, "weapon removed: primary hand")
            t3:eq("", s.slot, "weapon removed: slot " .. last.slot)
            t3:ok(count.events > 0, "no OnEquipPrimary event for the npc")
            if fishing then t3:eq(count.events, skipped, "fishing handler calls not skipped for the npc") end
            if errors0 ~= nil then
                local n = getLuaDebuggerErrorCount() - errors0
                local list, lines = getLuaDebuggerErrors(), {}
                for i = math.max(0, list:size() - math.min(n, 3)), list:size() - 1 do
                    lines[#lines + 1] = string.match(tostring(list:get(i)), "[^\n]*")
                end
                measure("Lua errors during the cases: " .. n .. (n > 0 and (" (" .. table.concat(lines, " | ") .. ")")
                    or ""))
                t3:eq(0, n, "Lua errors while the npc took its weapons in hand")
            end
        end)
    end

    local function caseStep(tc, ci)
        local c = cases[ci]
        if c == nil then return finish(tc) end
        A().setGesture(id, "idle")
        local ok, why = E().setWeapon(id, c.item)
        tc:ok(ok, "setWeapon " .. c.item .. ": " .. tostring(why))
        tc:sleep(SETTLE_MS, function(t3)
            checkRest(t3, id, c, "at rest")
            local gestures = {}
            for _, g in ipairs(P.GESTURES) do
                if c.nodes[g] then gestures[#gestures + 1] = g end
            end
            local function gestureStep(tg, gi)
                local g = gestures[gi]
                if g == nil then
                    A().setGesture(id, "idle")
                    tg:sleep(SETTLE_MS, function(t4)
                        checkRest(t4, id, c, "back to idle")
                        caseStep(t4, ci + 1)
                    end)
                    return
                end
                A().setGesture(id, g)
                tg:sleep(GESTURE_MS, function(t4)
                    checkGesture(t4, id, c, g)
                    gestureStep(t4, gi + 1)
                end)
            end
            gestureStep(t3, 1)
        end)
    end

    t:waitUntil(standing(id), STAND_MS, function(t2) caseStep(t2, 1) end, "npc still on the floor")
end

-- LK02-T13: first firearm of an installed weapons mod (script module other than Base, ranged, with a known attachment
-- slot), by full name; a case without expected Weapon value nor node (measured only), or nil.
function P.modFirearm()
    local names = {}
    local all = getScriptManager():getAllItems()
    for i = 0, all:size() - 1 do
        local it = all:get(i)
        if it:getModuleName() ~= "Base" and it:isRanged() then names[#names + 1] = it:getFullName() end
    end
    table.sort(names)
    for _, n in ipairs(names) do
        local spec = E().spec(n)
        if spec ~= nil then return { item = spec.t, slot = spec.l, nodes = { aim = true } } end
    end
    return nil
end

RST.suite("lk.equipment", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 240000 }, function(s)
    s.test("firearms: attached at rest, in hand to aim, attached again", function(t)
        runCases(t, P.CASES.firearms, 2, 0)
    end, { timeoutMs = 90000 })

    s.test("melee weapons: attached at rest, in hand to guard and strike, attached again", function(t)
        runCases(t, P.CASES.melee, 2, 2)
    end, { timeoutMs = 90000 })

    s.test("firearm of an installed weapons mod: attached at rest, in hand to aim, no Lua error", function(t)
        needSolo(t)
        t:ok(E() ~= nil, "LivingKnox.Equipment is not loaded")
        local c = P.modFirearm()
        if c == nil then t:skip("no firearm of a weapons mod with a known attachment slot in this game") end
        measure("weapons mod firearm: " .. c.item .. " at " .. c.slot)
        runCases(t, { c }, -2, 2)
    end, { timeoutMs = 90000 })
end)

return P
