--[[
lk.zombies - a Living Knox npc against vanilla zombies, both ways (LK06-T04, LivingKnox.Zombies, LivingKnox.Combat,
LivingKnox.Health). Tag "world": the authority only, on a save named rstest*, with a player (t.ctx.player) used as
an anchor; the Living Knox option Enabled must be on. Solo: RST.run({ suite = "lk.zombies", tags = "world" });
dedicated server: RST.server({ suite = "lk.zombies", tags = "world" }) from an admin client. Asynchronous run only
(up to about 70 s).

Automated (real Java objects, on the authority):
    fight      the player is made invisible to zombies and protected by god mode (both restored at the end); an
               npc armed with a baseball bat is spawned 8 squares from him, then ZOMBIES ordinary zombies are
               created 2 squares around the npc. While the test runs, the npc is engaged (LivingKnox.Combat.engage,
               source "api") against the zombie chosen by LivingKnox.Zombies.targetFor whenever it has no order.
               Within WAIT_MS, either every zombie is dead or the npc's death is decided. Checked: every zombie
               death caused by the npc is counted once (Zombies kills = dead zombies), no npc hit refused for
               reach or cadence, the attacks of the zombies on the npc are all resolved (avoided + scratch +
               laceration + bite = attacks), the npc's death is decided at most once, and the npc's reference
               health never rises.
Figures are printed as "[LKZ] measure ..." lines. The npc is forgotten and the zombies left alive are removed with
t:defer. Look at the npc while the suite runs: it should swing at the zombies, which come to it and claw it.

E01-T16 (LK06-T04): once the fight is over, every connected client holds the same zombie corpses (clothes and
content) around the death squares as the authority (world.keys, union of the 3 x 3 squares, RST_PeerChecks.lua).
Manual MP protocol (two clients, docs/annexes/conception/zombies.md, "Protocole en jeu"): the rest is not automated.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

local K = RST.LKHelpers
local B = K.B
local measure = K.measurer("[LKZ]")
local ZOMBIES = 2
local WEAPON = "Base.BaseballBat"
local WAIT_MS = 60000
local SPOTS = { { 2, 0 }, { -2, 1 }, { 0, -2 } }
local NEAR, FAR_SPOT = 2, 4 -- squares: zombies created on free squares in view of the npc (K.squareInView)
local DIAG_MS = 15000

-- Free square in view of the npc at NEAR..FAR_SPOT squares not used yet, else the fixed spot i. A fixed spot behind a
-- wall gave a zombie that the npc never saw (MP campaign of 2026-10-14, spawn house of Muldraugh: one zombie killed,
-- the other one never a target); the solo test site happened to have both spots in view.
local function spot(anchor, i, used)
    local S = LivingKnox.Senses
    if S == nil or S.lineOfSight == nil then return SPOTS[i][1], SPOTS[i][2] end
    local cell = getCell()
    local ax, ay, az = math.floor(anchor:getX()), math.floor(anchor:getY()), math.floor(anchor:getZ())
    for d = NEAR, FAR_SPOT do
        for dy = -d, d do
            for dx = -d, d do
                local key = dx .. "," .. dy
                if math.max(math.abs(dx), math.abs(dy)) == d and not used[key] then
                    local sq = cell:getGridSquare(ax + dx, ay + dy, az)
                    if sq ~= nil and sq:isFree(false)
                        and S.lineOfSight(ax, ay, az, ax + dx, ay + dy, az) == "Clear" then
                        used[key] = true
                        return dx, dy
                    end
                end
            end
        end
    end
    return SPOTS[i][1], SPOTS[i][2]
end

local function C() return LivingKnox and LivingKnox.Combat end
local function Zm() return LivingKnox and LivingKnox.Zombies end
local function H() return LivingKnox and LivingKnox.Health end

local function copy(st)
    local out = {}
    for k, v in pairs(st) do
        if type(v) == "number" then out[k] = v end
    end
    return out
end

RST.suite("lk.zombies", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 150000 }, function(s)
    s.test("npc fights vanilla zombies, every death counted once", function(t)
        t:ok(B() ~= nil and C() ~= nil and Zm() ~= nil and Zm().targetFor ~= nil and H() ~= nil,
            "LivingKnox.Zombies (LK06-T04) is not loaded on this side")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no anchor player (t.ctx.player)")
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        t:defer(function() p:setGodMod(wasGod) end, "restore the god mode of the player")
        if p.setInvisible ~= nil and p.isInvisible ~= nil then
            local wasInvisible = p:isInvisible()
            p:setInvisible(true)
            t:defer(function() p:setInvisible(wasInvisible) end, "restore the visibility of the player")
        end
        local x, y, z = math.floor(p:getX()) + 8, math.floor(p:getY()), math.floor(p:getZ())
        local id, body = B().spawn({}, x, y, z)
        t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
        t:defer(function() B().despawn(id, true) end, "forget " .. id)
        t:defer(function() C().disengage(id, "suite lk.zombies over") end, "end the combat of " .. id)
        t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
            local ok, why = K.E().setWeapon(id, WEAPON)
            t2:ok(ok, "setWeapon refused: " .. tostring(why))
            local npcBody = B().find(id)
            local zombies, used = {}, {}
            for i = 1, ZOMBIES do
                local dx, dy = spot(npcBody, i, used)
                zombies[i] = K.spawnVanilla(t2, npcBody, dx, dy)
                measure(string.format("zombie %d created at %+d,%+d of the npc", i, dx, dy))
            end
            local zs, cs, hs = copy(Zm().stats), copy(C().stats), copy(H().stats)
            local reach0, fast0 = C().stats.why["out of reach"] or 0, C().stats.why["too fast"] or 0
            local hp0 = H().reference(id)
            local rose = false
            local last = hp0
            local ignored = {}   -- zombies chosen by targetFor that the suite did not create (noted once)
            local deathAt = {}   -- LK06-T04: square of each zombie at its death (the object is reused 5 s later)
            local function dead()
                local n = 0
                for i, zb in ipairs(zombies) do
                    if K.diedOf(zb) then
                        n = n + 1
                        if deathAt[i] == nil then
                            deathAt[i] = { x = math.floor(zb:getX()), y = math.floor(zb:getY()), z = math.floor(zb:getZ()) }
                        end
                    end
                end
                return n
            end
            local start, nextDiag = getTimestampMs(), getTimestampMs() + DIAG_MS
            local function diag()
                local b = B().find(id)
                local parts = {}
                for i, zb in ipairs(zombies) do
                    local ex, ey = b and zb:getX() - b:getX() or 0, b and zb:getY() - b:getY() or 0
                    local d = b and math.sqrt(ex * ex + ey * ey) or -1
                    parts[#parts + 1] = string.format("z%d %s at %.1f,%.1f d %.1f %s", i, K.diedOf(zb) and "dead"
                        or "alive", zb:getX(), zb:getY(), d, b and Zm().sees(b, zb) and "seen" or "unseen")
                end
                local tg = Zm().targetFor(id)
                local o = C().get(id)
                local R = LivingKnox.Reports
                local rp = R and R.get and R.get(id) or nil
                measure(string.format("after %d s: %s; target %s, combat %s phase %s, npc copy %.1f,%.1f report %s, "
                    .. "gesture %s, owner %s", math.floor((getTimestampMs() - start) / 1000), table.concat(parts, "; "),
                    tostring(tg and tg.u), tostring(o ~= nil), tostring(o and o.phase), b and b:getX() or -1,
                    b and b:getY() or -1, rp and string.format("%.1f,%.1f %s", rp.x, rp.y, tostring(rp.act)) or "none",
                    tostring(K.A().gestureOf(id)), b and (K.G().simulatedHere(b) and "here" or "a client") or "-"))
            end
            t2:waitUntil(function()
                if getTimestampMs() >= nextDiag then
                    nextDiag = nextDiag + DIAG_MS
                    diag()
                end
                local hp = H().reference(id)
                if hp ~= nil and last ~= nil and hp > last + 1e-6 then rose = true end
                if hp ~= nil then last = hp end
                if H().decided[id] or dead() == #zombies then return true end
                if C().get(id) == nil then
                    -- Only the zombies of the test: Zombies.stats.kills counts every kill of the npc, and an ambient
                    -- zombie chosen by targetFor was killed too (MP campaign of 2026-10-15: kills 3 for 2 dead test
                    -- zombies, z:1157 not created by the suite).
                    local tg = Zm().targetFor(id)
                    local target = nil
                    if tg ~= nil then
                        for _, zb in ipairs(zombies) do
                            if zb == tg.zombie then target = zb end
                        end
                        if target == nil and not ignored[tg.zombie] then
                            ignored[tg.zombie] = true
                            measure("zombie " .. tostring(tg.u) .. " chosen by targetFor is not a test zombie: ignored")
                        end
                    end
                    if target == nil then
                        local b = B().find(id)
                        for _, zb in ipairs(zombies) do
                            if target == nil and not K.diedOf(zb) and b ~= nil and Zm().sees(b, zb) then target = zb end
                        end
                    end
                    if target ~= nil then C().engage(id, target, { source = "api", why = "suite lk.zombies" }) end
                end
                return false
            end, WAIT_MS, function(t3)
                local st = Zm().stats
                local kills = st.kills - zs.kills
                local attacks = st.attacks - zs.attacks
                local outcomes = 0
                for _, k in ipairs({ "avoided", "scratch", "laceration", "bite" }) do
                    outcomes = outcomes + (st[k] - zs[k])
                end
                measure("zombies killed " .. kills .. " of " .. #zombies .. " (dead " .. dead() .. "), npc hits "
                    .. (st.hits - zs.hits) .. ", hits applied " .. (C().stats.applied - cs.applied) .. ", refused "
                    .. (C().stats.refused - cs.refused) .. ", zombie attacks " .. attacks .. " (avoided "
                    .. (st.avoided - zs.avoided) .. ", scratch " .. (st.scratch - zs.scratch) .. ", laceration "
                    .. (st.laceration - zs.laceration) .. ", bite " .. (st.bite - zs.bite) .. "), lures "
                    .. (st.lures - zs.lures) .. ", npc health " .. tostring(hp0 and K.round(hp0)) .. " -> "
                    .. tostring(last and K.round(last)) .. ", npc dead " .. tostring(H().decided[id] == true))
                t3:eq(dead(), kills, "zombie deaths counted once (killed by the npc)")
                t3:eq(attacks, outcomes, "every zombie attack resolved")
                t3:ok(H().stats.deaths - hs.deaths <= 1, "npc death decided at most once")
                t3:ok(not rose, "npc reference health rose during the fight")
                t3:eq(0, (C().stats.why["out of reach"] or 0) - reach0, "npc hits refused out of reach")
                t3:eq(0, (C().stats.why["too fast"] or 0) - fast0, "npc hits refused as too fast")
                -- LK06-T04 (E01-T16): the same corpses (clothes and content) around each death square on every
                -- client as on the authority (world.keys, union of the squares; solo: the local player).
                local squares, seen = {}, {}
                for i = 1, #zombies do
                    local d = deathAt[i]
                    if d ~= nil then
                        for _, sq in ipairs(RST.PeerChecks.around(d.x, d.y, d.z, 1)) do
                            local k = sq.x .. "," .. sq.y .. "," .. sq.z
                            if not seen[k] then
                                seen[k] = true
                                squares[#squares + 1] = sq
                            end
                        end
                    end
                end
                if #squares > 0 then
                    t3:sleep(1500, function(t4)   -- the corpse is created on the next update of the authority
                        RST.PeerChecks.checkSquares(t4, squares, { corpse = true }, nil, true)
                    end)
                end
            end, "neither the zombies nor the npc died in " .. WAIT_MS .. " ms")
        end, "npc still on the floor")
    end)
end)
