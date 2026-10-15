--[[
lk.contest - refusal of an engine order by an embodied Living Knox member (E10-T03, server/LivingKnox/LK_Decisions.lua:
Decisions.judgeOrder, refuseDuties, flushRefusals). Tags "world" and "server": the authority only, on a save named
rstest*, with a target player (t.ctx.player), the Living Knox option Enabled on. Solo: RST.run({ suite = "lk.contest",
tags = "world" }); dedicated server: RST.server({ suite = "lk.contest", tags = "world" }) from an admin client.
Asynchronous run only (about 1 minute).

What is done (stay next to the three members, in their sight):
    - a test group "settlers" (worker leader m-1, fighters m-2 and m-3) gets its home on the player's square; its
      members get bodies near the player;
    - the group morale drops to 20: the newest fighter m-3 has a wavering loyalty (morale + seniority < 30), m-2 stays
      steady, the leader never refuses;
    - the guard order is given to m-3: it refuses (reason "morale"), one "refusal" entry in the group journal, its
      template line is said once (LivingKnox.Speech, heard by the player: bubble "Stand guard again? Not tonight...");
    - the hourly scoring of the group (Decisions.scorePass) never gives the watch to m-3 while the refusal holds; the
      registry keeps m-3 alive in the group.
No bridge, no LLM: an engine order is judged by fixed rules. The member reactions to a decision born of a conversation
(npc_member, bridge on) are checked by hand (protocol in docs/conception/contestation.md).
Every phase prints "[LKC] measure ..." lines. Cleanup (t:defer): bodies removed, test group removed.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local measure = K.measurer("[LKC]")

local BODIES_MS = 60000

local function LK() return LivingKnox end
local function Dec() return LivingKnox.Decisions end

local function memberNpc(gid, mid)
    local g = LK().Groups.get(gid)
    local m = g and g.members[mid] or nil
    return m and m.npc or nil
end

local function refusals(gid)
    local out = {}
    for _, e in ipairs(LK().Groups.get(gid).log or {}) do
        if e.kind == "refusal" then out[#out + 1] = e.text end
    end
    return out
end

RST.suite("lk.contest", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 }, function(s)
    s.test("a wavering member refuses the watch: journal, template line, another member keeps the post", function(t)
        local E = LK()
        t:ok(E ~= nil and E.Decisions ~= nil and E.Decisions.judgeOrder ~= nil,
            "LivingKnox.Decisions (E10-T03) is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        t:ok(sq ~= nil, "player square not loaded")
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST contest", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end
        assert(G.addMember(gid, { role = "worker", profile = "farmer", female = false, day = G.today() }))
        assert(G.addMember(gid, { role = "fighter", profile = "guard", female = false, day = G.today() }))
        assert(G.addMember(gid, { role = "fighter", profile = "guard", female = true, day = G.today() }))
        assert(G.setLeader(gid, "m-1", G.today()))
        t:defer(function()
            local npcs = { memberNpc(gid, "m-1"), memberNpc(gid, "m-2"), memberNpc(gid, "m-3") }
            G.remove(gid)
            for _, npc in ipairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove group " .. gid)
        t:waitUntil(function()
            for _, mid in ipairs({ "m-1", "m-2", "m-3" }) do
                local npc = memberNpc(gid, mid)
                if npc == nil or E.Bodies.find(npc) == nil or not K.standing(npc)() then return false end
            end
            return true
        end, BODIES_MS, function(t2)
            assert(G.setMorale(gid, 20))
            local live = G.state.data.groups[gid]
            local l2, s2 = Dec().loyaltyOfMember(live, "m-2")
            local l3, s3 = Dec().loyaltyOfMember(live, "m-3")
            measure(string.format("morale 20: m-2 %s %d, m-3 %s %d", l2, s2, l3, s3))
            t2:eq("wavering", l3, "loyalty of the newest fighter")
            t2:ne("wavering", l2, "loyalty of the older fighter")
            local said0 = E.Speech and E.Speech.stats.said or 0
            local minute = Dec().currentMinute()
            local reason, why = Dec().judgeOrder(gid, live, "m-3", live.members["m-3"], "guard", "sentry", minute)
            t2:eq("morale", reason, "refusal reason of m-3")
            t2:eq(nil, (Dec().judgeOrder(gid, live, "m-1", live.members["m-1"], "guard", "sentry", minute)),
                "the leader refused")
            Dec().flushRefusals()
            local said = E.Speech and E.Speech.stats.said or 0
            measure(string.format("refusal: %s (%s), journal %d entry(ies), lines said %d", tostring(reason),
                tostring(why), #refusals(gid), said - said0))
            t2:eq(1, #refusals(gid), "refusal entries in the group journal")
            t2:eq(1, said - said0, "template line said (heard by the player)")
            Dec().scorePass(Dec().currentHour(), gid)
            local duties = {}
            for _, mid in ipairs({ "m-1", "m-2", "m-3" }) do
                duties[#duties + 1] = mid .. " " .. tostring(live.members[mid].duty)
            end
            measure("duties after the scoring: " .. table.concat(duties, ", "))
            t2:ne("sentry", live.members["m-3"].duty, "m-3 got the watch it refused")
            t2:eq(1, #refusals(gid), "refusal announced twice")
            t2:eq(gid, (G.findNpc(memberNpc(gid, "m-3"))), "m-3 left the group")
        end, "group members not materialized and standing")
    end)
end)
