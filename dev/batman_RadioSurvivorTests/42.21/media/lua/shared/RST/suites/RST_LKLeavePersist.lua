--[[
lk.leave persistence steps (E10-T04, E01-T17: "groupe loners et depart conserves apres redemarrage";
shared/RadioSurvivor/RS_LivingKnox.lua: leave, composition). Played by autoclient.py --mp --phases restart
--server-campaign mp-persist (base lk.leave):
    lk.leave.before         (opt-in "manual") a "settlers" group (leader m-1, fighter m-2) at home on the requester's
                            square; once both members have bodies, m-2 leaves (RS_LivingKnox.leave with the composition
                            read now): one "loners" group of one member linked to the same NPC, written at once.
                            Group ids, NPC ids and the old composition written to the snapshot. Nothing removed.
                            Run again: the groups of the previous snapshot are removed first.
    lk.leave.after-restart  after a real restart of the dedicated server, from the group registry read back: the
                            loner group exists, type "loners", one living member, the NPC found in it; the old group
                            without m-2, its leader still m-1; the same departure on the old composition refused; the
                            population never draws "loners". Then both groups, bodies and directives are removed and
                            the snapshot consumed.
Tags "world", "server", "manual": authority only, test saves rstest* only, exact names only. No truce (lk.leave
covers it with a notebook character). Snapshot: Zomboid/Lua/batman_RadioSurvivor/tests/leave-persist.txt of the
server (RST_Persist).
Outside the game: tests/test_persist_suites.py (listing).
]]

require "RST/RST"
require "RST/RST_Persist"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers

RST.LKLeavePersist = RST.LKLeavePersist or {}
local LP = RST.LKLeavePersist
LP.FILE = "leave-persist.txt"
LP.HEADER = "LKLEAVE1"
LP.BODIES_MS = 60000

local function LK() return LivingKnox end

local function modules(t)
    if type(isClient) == "function" and isClient() then t:skip("authority only (not on an MP client)") end
    local E = LK()
    local P = RS_LivingKnox
    t:ok(E ~= nil and E.Groups ~= nil and E.Sites ~= nil, "Living Knox server part is not loaded on this side")
    t:ok(P ~= nil and P.leave ~= nil and P.composition ~= nil, "RS_LivingKnox.leave (E10-T04) is not loaded")
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E, P
end

local function memberNpc(E, gid, mid)
    local g = E.Groups.get(gid)
    local m = g and g.members[mid] or nil
    return m and m.npc or nil
end

local function removeAll(E, snap)
    for _, gid in ipairs({ snap.gid, snap.loner }) do
        if gid ~= nil and E.Groups.get(gid) ~= nil then E.Groups.remove(gid) end
    end
    for _, npc in ipairs({ snap.leader, snap.mate }) do
        if npc ~= nil then
            E.Directives.forget(npc)
            E.Bodies.despawn(npc, true)
        end
    end
end

RST.suite("lk.leave.before", { tags = { "world", "server", "manual" }, testTimeoutMs = 120000 }, function(s)
    s.test("a member left its group: loner group written to the snapshot", function(t)
        local E, P = modules(t)
        local old = RST.Persist.read(LP.FILE, LP.HEADER)
        if old and type(old.gid) == "string" then
            removeAll(E, old)
            t:note("groups " .. tostring(old.gid) .. ", " .. tostring(old.loner) .. " of the previous snapshot removed")
        end
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        t:ok(sq ~= nil, "player square not loaded")
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST leave persist", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end
        assert(G.addMember(gid, { role = "worker", profile = "farmer", female = false, day = G.today() }))
        assert(G.addMember(gid, { role = "fighter", profile = "guard", female = true, day = G.today() }))
        assert(G.setLeader(gid, "m-1", G.today()))
        t:waitUntil(function()
            for _, mid in ipairs({ "m-1", "m-2" }) do
                local npc = memberNpc(E, gid, mid)
                if npc == nil or E.Bodies.find(npc) == nil or not K.standing(npc)() then return false end
            end
            return true
        end, LP.BODIES_MS, function(t2)
            local leader, mate = memberNpc(E, gid, "m-1"), memberNpc(E, gid, "m-2")
            local c = P.composition(mate)
            t2:ok(c ~= nil and c.canLeave == true, "m-2 may not leave its group")
            local out, why = P.leave(mate, { ref = c.ref, key = c.key })
            t2:ok(out ~= nil, "departure refused: " .. tostring(why))
            local ng = G.get(out.ref)
            t2:eq("loners", ng and ng.type, "type of the new group")
            t2:eq(out.ref, (G.findNpc(mate)), "group of the NPC")
            t2:ok(not G.isDirty(), "departure not written at once")
            local snap = { gid = gid, loner = out.ref, leader = leader, mate = mate, ref = c.ref, key = c.key,
                home = home }
            local ok, werr = RST.Persist.write(LP.FILE, LP.HEADER, snap)
            t2:ok(ok, werr)
            local back, rerr = RST.Persist.read(LP.FILE, LP.HEADER)
            t2:ok(back ~= nil and back.loner == out.ref and back.mate == mate, "snapshot: " .. tostring(rerr))
            t2:note("npc " .. tostring(mate) .. " left " .. gid .. " for " .. out.ref .. " (home " .. ng.home.x .. ","
                .. ng.home.y .. "), walk " .. (out.walk and ("#" .. tostring(out.walk)) or tostring(out.walkWhy)))
        end, "group members not materialized and standing")
    end)
end)

RST.suite("lk.leave.after-restart", { tags = { "world", "server", "manual" }, testTimeoutMs = 60000 }, function(s)
    s.test("loner group and departure kept by the restart", function(t)
        local E, P = modules(t)
        local snap, why = RST.Persist.read(LP.FILE, LP.HEADER)
        t:ok(snap ~= nil and type(snap.loner) == "string", why or "snapshot without loner group")
        t:defer(function()
            removeAll(E, snap)
            RST.Persist.consume(LP.FILE)
        end, "remove groups " .. snap.gid .. ", " .. snap.loner)
        local G = E.Groups
        local ng, old = G.get(snap.loner), G.get(snap.gid)
        t:ok(ng ~= nil, "loner group " .. snap.loner .. " lost by the restart")
        t:ok(old ~= nil, "old group " .. snap.gid .. " lost by the restart")
        t:eq("loners", ng.type, "type of the loner group")
        t:eq(1, G.livingCount(ng), "members of the loner group")
        t:eq(snap.loner, (G.findNpc(snap.mate)), "group of the NPC after the restart")
        t:eq(snap.gid, (G.findNpc(snap.leader)), "group of the leader after the restart")
        t:ok(old.members["m-2"] == nil, "member back in the old group")
        t:eq("m-1", old.leader, "leader of the old group")
        local again, refused = P.leave(snap.mate, { ref = snap.ref, key = snap.key })
        t:eq(nil, again, "departure on the old composition applied after the restart")
        t:note("second departure on the old composition: " .. tostring(refused))
        for _, w in ipairs(E.Population.typeWeights(E.Config.population())) do
            t:ne("loners", w.id, "loners drawn by the population")
        end
    end)
end)
