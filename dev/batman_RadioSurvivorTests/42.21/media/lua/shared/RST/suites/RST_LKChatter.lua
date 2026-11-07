--[[
lk.chatter - two members of a group chat at their home in front of a player (E18-T32: LK_Chatter, conversations of
LK_Conversations, topic of npc_converse). Tags "world" and "server": a save named rstest*, with a target player.
Living Knox alone or with RadioSurvivor (speech host of either). Run with the bridge (fake model):
    python tools/autoclient/autoclient.py --mods lk --suite lk.chatter --tags world --bridge on --llm fake
    python tools/autoclient/autoclient.py --mods both --mp --clients 1 --server-suite lk.chatter --server-tags world
        --bridge on --llm fake

The test group of RST.LKGroup has its home on the player's square and two members (leader m-1, fighter m-2); both get
a speaker record of the host. One pass of the chatter (LK_Chatter.tick, every EVERY_MS) opens a chatter between them:
a topic drawn from the group's state, its number of lines (LK_Chatter.TURNS), every line said by the speech channel
of the NPCs. The group then waits the delay of the option (no second chatter at once).
]]
require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKGroupFixture"
require "RST/RST_RSHelpers"

local OPEN_MS = 30000
local LINES_MS = 120000

RST.suite("lk.chatter", { tags = { "world", "server" }, testTimeoutMs = 240000, timeoutMs = 300000 }, function(s)
    s.test("two members chat at their home in front of the player", function(t)
        local H = RST.RSHelpers.speech(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        RST.LKGroup.ensure(t, p, function(t2, gid)
            local Ch = require "LivingKnox/LK_Chatter"
            local V = require "LivingKnox/LK_Conversations"
            local a = H.ensure(RST.LKGroup.memberNpc(gid, "m-1"))
            local b = H.ensure(RST.LKGroup.memberNpc(gid, "m-2"))
            t2:ok(a ~= nil and b ~= nil, "no speaker record for the two members")
            local opened, said = Ch.stats.opened, V.stats.said
            local conv
            t2:waitUntil(function()
                conv = V.of(a.id) or V.of(b.id)
                return conv ~= nil and conv.chatter ~= nil
            end, OPEN_MS, function(t3)
                t3:eq(opened + 1, Ch.stats.opened, "chatter opened once")
                t3:eq(Ch.TURNS[conv.chatter.subject], conv.maxTurns, "lines of the topic " .. conv.chatter.subject)
                local last = H.talk.data.chatter.last[gid]
                t3:ok(last ~= nil, "group delay not recorded")
                local turns = conv.maxTurns
                t3:waitUntil(function() return V.active[conv.id] == nil end, LINES_MS, function(t4)
                    t4:eq(said + turns, V.stats.said, "lines said by the two members")
                    t4:eq(opened + 1, Ch.stats.opened, "a second chatter within the group delay")
                end, "chatter " .. conv.id .. " never ended")
            end, "no chatter between the two members (is the bridge running?)")
        end)
    end)
end)
