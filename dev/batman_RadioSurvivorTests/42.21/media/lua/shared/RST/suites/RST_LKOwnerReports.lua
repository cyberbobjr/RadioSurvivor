--[[
lk.ownerreports - state reports of a Living Knox body forged by a client (LK03-T02, LivingKnox.Reports). Tags "world"
and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player). Dedicated server:
RST.server({ suite = "lk.ownerreports", tags = "world" }) with two clients (autoclient --mp --clients 2); solo:
RST.run({ suite = "lk.ownerreports", tags = "world" }). Asynchronous run only (about 1 minute).

The reports are built on the server and SENT BY A REAL CLIENT through the real network path (step lk.report.forge of
RST_PeerChecksLK.lua: command "bodyReport" of module "LivingKnox", as LK_Executor sends them; solo: the direct call):
    non-owner   a client that does not simulate the body (MP: the other client; skipped in solo or with one client)
                sends a plausible report (body position + 3 squares, current lease): refused "not the owner";
    teleport    the client that simulates the body (solo: the local player) sends a report 40 squares away (beyond
                Config.REPORTS.MAX_GAP): refused "far from the body";
    health      the same owner sends a report at the accepted position with a health 0.5 above the last accepted one,
                no heal known: refused "health rose without a known heal".
Each time: the refusal is counted for that npc as suspect (Reports.rejectedOf), a WARN line "state report on npc <id>
from <account> refused: <reason>" is written (LivingKnox.Log.warn, captured during the test; the per-minute limit of
that sender and reason is cleared first), the accepted state never takes the forged values, and the server copy of the
body does not jump (no teleport). Figures: "[LKO] measure ..." lines. The npc is forgotten with t:defer.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecksLK"

local K = RST.LKHelpers
local PL = RST.PeerChecksLK
local measure = K.measurer("[LKO]")
local STATE_MS = 15000      -- first accepted state report of the new body
local REFUSE_MS = 8000      -- forged report refused on the server
local STEP_MS = 10000
local TELEPORT = 40         -- squares: beyond Config.REPORTS.MAX_GAP (22)
local HP_RISE = 0.5

local function B() return LivingKnox and LivingKnox.Bodies end
local function D() return LivingKnox and LivingKnox.Directives end
local function R() return LivingKnox and LivingKnox.Reports end

local function spawnNpc(t)
    t:ok(B() ~= nil and D() ~= nil and R() ~= nil, "LivingKnox.Bodies, Directives or Reports is not loaded here")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local id, body = B().spawn({}, math.floor(p:getX()) + 2, math.floor(p:getY()), math.floor(p:getZ()))
    if id then
        t:defer(function()
            D().forget(id)
            B().despawn(id, true)
        end, "forget " .. id)
    end
    t:ok(id ~= nil, "npc spawn refused: " .. tostring(body))
    return id, p
end

-- WARN lines of LivingKnox.Log written during the test (the module calls LivingKnox.Log.warn at each refusal).
local function captureWarnings(t)
    local Log = LivingKnox.Log
    local lines = {}
    local warn = Log.warn
    Log.warn = function(msg, ...)
        lines[#lines + 1] = Log.format(msg, ...)
        return warn(msg, ...)
    end
    t:defer(function() Log.warn = warn end, "LivingKnox.Log.warn restored")
    return lines
end

local function logged(lines, id, sender, reason)
    local want = "state report on npc " .. id .. " from " .. sender .. " refused: " .. reason
    for _, line in ipairs(lines) do
        if string.find(line, want, 1, true) == 1 then return true end
    end
    return false
end

-- Report built here from the last accepted state (current lease, number above every one sent so far).
local function forged(id, s, fields)
    local e = D().entries[id]
    PL.forgeN = (PL.forgeN or 1000000) + 1
    local out = { id = id, l = e and e.l or 0, n = PL.forgeN, x = s.x, y = s.y, z = s.z, a = s.a or 0, act = "idle",
        hp = s.hp, pose = "stand", t = 0 }
    for k, v in pairs(fields) do out[k] = v end
    return out
end

local function why(reason) return R().stats.why[reason] or 0 end

-- Waits for the body standing and one accepted state report; then suite(t, id, player, state, owner account).
local function ready(t, suite)
    local id, p = spawnNpc(t)
    t:waitUntil(K.standing(id), K.STAND_MS, function(t2)
        t2:waitUntil(function() return R().get(id) end, STATE_MS, function(t3, s)
            local z = B().find(id)
            t3:ok(z ~= nil, "npc body lost")
            local owner = isServer() and D().ownerName(z) or PL.accountOf(p)
            suite(t3, id, p, s, owner, z)
        end, "no state report accepted for the new body")
    end, "npc still on the floor")
end

-- Sends report from account (target of the step), waits for one more refusal of reason, checks state and body.
local function refused(t, id, target, sender, report, reason, after)
    local lines = captureWarnings(t)
    R().warned[tostring(sender) .. "|" .. reason] = nil   -- per-minute limit of the WARN line
    local n0, sus0 = R().rejectedOf(id)
    local why0 = why(reason)
    local z = B().find(id)
    local x0, y0 = z:getX(), z:getY()
    local seen = { forged = false, maxJump = 0 }
    RST.Steps.ask(t, "lk.report.forge", { report = report }, { target = target, timeoutMs = STEP_MS }, function(t2)
        t2:waitUntil(function()
            local s = R().get(id)
            if s ~= nil and s.x == report.x and s.y == report.y and s.hp == report.hp and s.n == report.n then
                seen.forged = true
            end
            local zb = B().find(id)
            if zb ~= nil then
                local jump = math.max(math.abs(zb:getX() - x0), math.abs(zb:getY() - y0))
                if jump > seen.maxJump then seen.maxJump = jump end
            end
            return why(reason) > why0
        end, REFUSE_MS, function(t3)
            local n1, sus1 = R().rejectedOf(id)
            local s = R().get(id)
            measure(string.format("%s from %s: refused %s, npc refusals +%d (suspect +%d), WARN line %s, state kept "
                .. "x %.2f hp %.3f by %s, body moved at most %.2f squares", reason, sender, reason, n1 - n0,
                sus1 - sus0, tostring(logged(lines, id, sender, reason)), s and s.x or -1, s and s.hp or -1,
                tostring(s and s.by), seen.maxJump))
            t3:ok(sus1 - sus0 >= 1, "refusal not counted as suspect for " .. id)
            t3:ok(logged(lines, id, sender, reason), "no WARN line for the refusal (" .. reason .. ")")
            t3:eq(false, seen.forged, "forged report accepted as the state")
            t3:ok(s == nil or s.n ~= report.n, "state carries the forged report number")
            t3:ok(seen.maxJump < 3, "body copy moved " .. seen.maxJump .. " squares after the forged report")
            if after then return after(t3) end
        end, "report not refused \"" .. reason .. "\"")
    end)
end

RST.suite("lk.ownerreports", { tags = { "world", "server" }, testTimeoutMs = 90000, timeoutMs = 300000 }, function(s)
    s.test("report of a client that does not simulate the body: refused, logged, state unchanged", function(t)
        if RST.Steps.isSolo() or PL.peer(t) == nil then
            t:skip("needs a dedicated server with two clients (the forger must not own the body)")
        end
        ready(t, function(t2, id, p, st, owner, z)
            local forger = nil
            for _, name in ipairs({ PL.accountOf(p), PL.peer(t2) }) do
                if forger == nil and name ~= owner then forger = name end
            end
            t2:ok(forger ~= nil, "both clients own the body?")
            measure("body " .. id .. " owned by " .. tostring(owner) .. ", forger " .. forger)
            -- A previous owner is ignored for Directives.OWNER_GRACE_MS (LK03-T03), not refused: wait until the
            -- forger held nothing for that delay and the owner is still the same.
            t2:waitUntil(function()
                local zb = B().find(id)
                return zb ~= nil and D().ownerName(zb) == owner and not D().isPreviousOwner(id, forger)
            end, 15000, function(t3)
                local zb = B().find(id)
                local report = forged(id, R().get(id) or st, { x = zb:getX() + 3, y = zb:getY(), z = zb:getZ() })
                refused(t3, id, { forger }, forger, report, "not the owner")
            end, "owner of the body not stable")
        end)
    end)

    s.test("owner report with a teleport, then a health rise: refused, no teleport", function(t)
        ready(t, function(t2, id, p, st, owner, z)
            if owner == "server" then t2:skip("body simulated by the server: no owner client to send the report") end
            local solo = RST.Steps.isSolo()
            local target = solo and "requester" or { owner }
            local sender = solo and D().senderName(p) or owner
            measure("body " .. id .. " owned by " .. tostring(owner) .. "; first accepted report by " .. tostring(st.by))
            local tp = forged(id, st, { x = z:getX() + TELEPORT, y = z:getY(), z = z:getZ() })
            refused(t2, id, target, sender, tp, "far from the body", function(t3)
                t3:sleep(1200, function(t4)   -- one token of the report bucket back
                    local s2 = R().get(id)
                    t4:ok(s2 ~= nil, "no accepted state left")
                    local rise = forged(id, s2, { hp = s2.hp + HP_RISE })
                    refused(t4, id, target, sender, rise, "health rose without a known heal")
                end)
            end)
        end)
    end)
end)
