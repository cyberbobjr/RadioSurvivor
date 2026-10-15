--[[
lk.materialize - Living Knox groups materialized near a player (LK09-T03, server/LivingKnox/LK_Materialize.lua):
the player is moved next to the home of a group of the initial population; the living members present at home
(not on an expedition, not dead) get bodies, with the health of their abstract wound; the player leaves beyond the
release radius (release delay shortened to 3 s for the test), the bodies go back to the offscreen simulation; the
player comes back: the same npcs come back (same ids, next generation, no new npc number), no dead member.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player); the
Living Knox option Enabled must be on and the initial population made (at least one group with a home).
Solo: RST.run({ suite = "lk.materialize", tags = "world" }); dedicated server: RST.server({ suite =
"lk.materialize", tags = "world" }) from an admin client. Asynchronous run only (teleports and waits, about 2 min).
Each body is printed as a note ("member m-<k> npc lk-<n> wound w health h") for the report.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local FAR = 300             -- squares from the home: beyond the release radius (120) and the loaded area
local NEAR = 20             -- squares from the home: within the materialization radius (80)

local function LK() return LivingKnox end

-- First group (by number) with a home and at least one living member present at home; nil when none.
local function pickGroup()
    local G, M = LK().Groups, LK().Materialize
    for _, gid in ipairs(G.list()) do
        local g = G.get(gid)
        if g and g.home and #M.presentMembers(g) > 0 then return gid, g end
    end
    return nil
end

-- Members present at home whose npc is not dead (those expected to get a body), capped by MAX_PER_GROUP.
local function expected(g)
    local M = LK().Materialize
    local registry = LK().Store.data()
    local out = {}
    for _, mid in ipairs(M.presentMembers(g)) do
        if M.npcState(g.members[mid], registry) ~= "dead" then out[#out + 1] = mid end
    end
    local cap = M.settings().maxPerGroup
    while #out > cap do table.remove(out) end
    return out
end

-- Members of the group that have a body in the world: { [mid] = { npc, body } }, and their count.
local function bodies(gid)
    local g = LK().Groups.get(gid)
    local out, n = {}, 0
    for mid, m in pairs(g.members) do
        local z = m.npc and (LK().Bodies.find(m.npc)) or nil
        if z ~= nil then
            out[mid] = { npc = m.npc, body = z }
            n = n + 1
        end
    end
    return out, n
end

local function allVirtual(ids)
    local registry = LK().Store.data()
    for _, id in pairs(ids) do
        local npc = registry.npcs[id]
        if npc == nil or npc.state ~= "virtual" then return false end
    end
    return true
end

RST.suite("lk.materialize", { tags = { "world", "server" }, testTimeoutMs = 300000, timeoutMs = 600000 }, function(s)
    s.test("approach, departure and return of a group of the initial population", function(t)
        local E = LK()
        t:ok(E ~= nil and E.Materialize ~= nil, "LivingKnox.Materialize is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local gid, g = pickGroup()
        if gid == nil then t:skip("no group with a home and a member present at home (initial population?)") end
        local want = expected(g)
        t:ok(#want > 0, "group " .. gid .. ": no member to materialize")
        t:note("group " .. gid .. " " .. g.type .. " home " .. g.home.x .. "," .. g.home.y .. "," .. g.home.z
            .. ": " .. #want .. " member(s) expected")
        local C = E.Config.BODIES
        local delay = C.RELEASE_DELAY_MS
        C.RELEASE_DELAY_MS = 3000
        t:defer(function() C.RELEASE_DELAY_MS = delay end, "restore the release delay")
        local F = RST.Fixtures
        local p = F.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local hx, hy, hz = g.home.x, g.home.y, g.home.z
        local count = function() local _, n = bodies(gid) return n end
        F.movePlayer(t, p, hx + NEAR, hy, hz, function(t2)
            t2:waitUntil(function() return count() >= #want end, 90000, function(t3)
                local found, n = bodies(gid)
                t3:eq(#want, n, "bodies of the group")
                local ids, gens = {}, {}
                local registry = E.Store.data()
                local live = E.Groups.get(gid)
                for _, mid in ipairs(want) do
                    local b = found[mid]
                    t3:ok(b ~= nil, "member " .. mid .. " has no body")
                    local npc = registry.npcs[b.npc]
                    local w = live.members[mid].wound or 0
                    local full = npc.hpMax or E.Materialize.settings().fullHealth
                    t3:near(E.Materialize.healthOf(w, full), b.body:getHealth(), 0.01, "health of " .. mid)
                    ids[mid], gens[mid] = b.npc, npc.generation
                    t3:note("member " .. mid .. " npc " .. b.npc .. " wound " .. w .. " health "
                        .. string.format("%.3f", b.body:getHealth()) .. " at " .. math.floor(b.body:getX()) .. ","
                        .. math.floor(b.body:getY()))
                end
                for mid, m in pairs(live.members) do
                    if not m.alive then t3:eq(nil, found[mid], "dead member " .. mid .. " has a body") end
                end
                local nextId = registry.nextId
                F.movePlayer(t3, p, hx + FAR, hy, hz, function(t4)
                    t4:waitUntil(function() return allVirtual(ids) end, 90000, function(t5)
                        local _, left = bodies(gid)
                        t5:eq(0, left, "bodies after the release")
                        F.movePlayer(t5, p, hx + NEAR, hy, hz, function(t6)
                            t6:waitUntil(function() return count() >= #want end, 90000, function(t7)
                                local again, n2 = bodies(gid)
                                t7:eq(#want, n2, "bodies after the return")
                                for mid, id in pairs(ids) do
                                    t7:eq(id, again[mid] and again[mid].npc, "npc of " .. mid)
                                    t7:eq(gens[mid] + 1, E.Store.data().npcs[id].generation, "generation of " .. mid)
                                end
                                t7:eq(nextId, E.Store.data().nextId, "no new npc number")
                                print("[LKM] measure materialize: group " .. gid .. ", " .. n2 .. " bodies after the "
                                    .. "round trip")
                            end, "bodies not back after the return")
                        end)
                    end, "bodies not released")
                end)
            end, "bodies not materialized near the home")
        end)
    end, { timeoutMs = 300000 })
end)
