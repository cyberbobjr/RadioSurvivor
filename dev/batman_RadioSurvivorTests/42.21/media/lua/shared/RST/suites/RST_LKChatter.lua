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
            -- Hourly budget of the conversation lines emptied (as rs.conversations does): in a campaign the earlier
            -- suites use it up (MP campaign of 2026-11-07: no chatter within 30 s, budget of the Normal level spent).
            V.reset()
            Ch.reset()
            local opened, said = Ch.stats.opened, V.stats.said
            local conv
            local nextDiag = getTimestampMs() + 5000
            local ticks, tick = 0, Ch.tick
            Ch.tick = function(...) ticks = ticks + 1; return tick(...) end
            t2:defer(function() Ch.tick = tick end, "restore LK_Chatter.tick")
            -- Why no chatter opens yet (printed every 5 s, the failure case too).
            local function diagnose()
                local I = require "LivingKnox/LK_Initiatives"
                local Speech = require "RadioSurvivorCore/RC_SpeechConfig"
                local T = require "RadioSurvivorCore/RC_Transport"
                local Talk, now = H.talk, getTimestampMs()
                local calls, mine = 0, 0
                for _, at in ipairs(Talk.times or {}) do if now - at < 3600000 then calls = calls + 1 end end
                for _, at in ipairs(V.times or {}) do if now - at < 3600000 then mine = mine + 1 end end
                local parts = {}
                for _, f in ipairs({ a, b }) do
                    local body = H.objects()[f.id]
                    local g = LivingKnox.Groups.get(gid)
                    local home = g and g.home and { x = g.home.x, y = g.home.y, z = g.home.z, radius = Ch.CFG.HOME_RADIUS }
                    parts[#parts + 1] = string.format("%s body %s home %s pending %s busy %s engaged %s heard %d",
                        f.id, tostring(body ~= nil), tostring(home ~= nil and V.atHome(body, home)),
                        tostring(I.hasPending(Talk, f.id)), tostring(V.busy(f.id)),
                        tostring(H.P.engaged(f.incarnation)), body and #I.listeners(Talk, body) or -1)
                end
                local ba, bb = H.objects()[a.id], H.objects()[b.id]
                local ra, rb = H.P.npc(a.incarnation), H.P.npc(b.incarnation)
                local g = LivingKnox.Groups.get(gid)
                local topic = g and Ch.topic(gid, g) or nil
                parts[#parts + 1] = string.format("near %s (%.1f), groups %s/%s, topic %s, hour %s, ticks %d",
                    tostring(ba and bb and H.P.near(ba, bb, Ch.CFG.RANGE)),
                    ba and bb and math.sqrt((ba:getX() - bb:getX()) ^ 2 + (ba:getY() - bb:getY()) ^ 2) or -1,
                    tostring(ra and ra.group), tostring(rb and rb.group), tostring(topic and topic.subject),
                    tostring((require "RadioSurvivorCore/RC_WorldFacts").hour()), ticks)
                print(string.format("[RST] lk.chatter waiting: level %d, bridge down %s, canSpeak %s, pending %d/%d, "
                    .. "calls %d/%d, conversation lines %d, acks %d, last %s; %s", I.level(), tostring(I.bridge.down),
                    tostring(V.canSpeak(Talk, now)), #Talk.pending, Speech.MAX_PENDING, calls, Speech.MAX_PER_HOUR,
                    mine, #T.acks, tostring(Talk.data.chatter and Talk.data.chatter.last[gid]),
                    table.concat(parts, "; ")))
            end
            t2:waitUntil(function()
                conv = V.of(a.id) or V.of(b.id)
                if getTimestampMs() >= nextDiag then nextDiag = nextDiag + 5000; diagnose() end
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
