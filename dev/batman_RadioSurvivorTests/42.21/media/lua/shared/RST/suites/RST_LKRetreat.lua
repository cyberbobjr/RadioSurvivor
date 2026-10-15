--[[
lk.retreat - flight, surrender and call for help of Living Knox npcs (LK06-T05, LK06-T12, server/LivingKnox/LK_Decisions.lua,
behaviours "retreat" and "surrender", Decisions.noteHit called by LivingKnox.Health.applyHit). Tag "world" (and
"server"): the authority only, on a save named rstest*, with a target player (t.ctx.player) standing INSIDE a house
(the test group gets its home on the player's square), the Living Knox option Enabled on. Solo:
RST.run({ suite = "lk.retreat", tags = "world" }). Asynchronous run only (about 1 to 3 minutes). Multiplayer: final
session.

What is done (the target player is protected by god mode; stay close to the two members, in their sight):
    - a test group "settlers" (one fighter, one worker; settlers never strike first) is created with its home on the
      player's square; its members get bodies near the player;
    - help: the worker is hit by the player through LivingKnox.Health.applyHit (the path of an accepted hit): the
      group calls for help and the fighter engages the player (reason "help"); the fighter may strike the player;
    - surrender: the worker is hit again below 60 % of its health: it surrenders (behaviour "surrender", gesture
      "surrender": both hands raised, facing the player), says ONE surrender line (bubble, IGUI_LK_Surrender_<n>,
      Decisions.stats.surrenderLines + 1, never a second one while it lasts) and the group spares the player: the
      fighter stops fighting;
    - broken surrender: the player hits the worker once more: the surrender is broken, the hands go down at once, the
      worker says one betrayal line (IGUI_LK_Surrender_Betrayed_<n>) and the fighter engages again;
    - retreat: the home of the test group is moved 15 squares away and the fighter is wounded down to 30 % by the
      player: it retreats (behaviour "retreat", run order towards the home) and stops fighting.
Every phase prints "[LKT] measure ..." lines; the user checks the raised hands and the bubble of the worker, then the
running fighter. E01-T16: at the end, the other clients of the MP campaign must be among the listeners and have
received the lines they heard (RST.PeerChecks.checkSpeech; nothing asked in solo). Cleanup
(t:defer): bodies removed, test group removed, god mode restored.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"

local K = RST.LKHelpers
local measure = K.measurer("[LKT]")

local BODIES_MS = 60000     -- materialization of the two members
local STEP_MS = 30000       -- each phase

local function LK() return LivingKnox end
local function Dec() return LivingKnox.Decisions end
local function C() return LivingKnox.Combat end

local function memberNpc(gid, mid)
    local g = LK().Groups.get(gid)
    local m = g and g.members[mid] or nil
    return m and m.npc or nil
end

local function stateOf(npc)
    local st = Dec().get(npc)
    if st == nil then return "none" end
    return st.b .. " (" .. tostring(st.why) .. ")"
end

local function engagedOn(npc, name)
    local o = C().get(npc)
    return o ~= nil and o.u == name
end

-- Hit of the player on the npc: the accepted hit path of the authority (reference health, death, call for help).
local function hit(npc, p, toRatio, minimum)
    local E = LK()
    local body = E.Bodies.find(npc)
    local h = E.Health.get(npc)
    if body == nil or h == nil then return nil end
    local amount = minimum
    if toRatio ~= nil then amount = math.max(minimum, h.hp - toRatio * h.max) end
    return E.Health.applyHit(npc, body, amount, "suite lk.retreat", p, nil)
end

RST.suite("lk.retreat", { tags = { "world", "server" }, testTimeoutMs = 400000, timeoutMs = 600000 }, function(s)
    s.test("call for help, surrender that spares the player, broken surrender, wounded fighter retreats", function(t)
        local E = LK()
        t:ok(E ~= nil and E.Decisions ~= nil and E.Decisions.noteHit ~= nil and E.Health ~= nil,
            "LivingKnox.Decisions (LK06-T05) is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local name = p:getUsername()
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local wasGod = p:isGodMod()
        p:setGodMod(true)
        local said = RST.PeerChecks.recordSpeech(t)   -- E01-T16: lines heard by the other clients
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST retreat", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end   -- no furnishing (LK08-T04) on the test site
        assert(G.addMember(gid, { role = "fighter", profile = "guard", female = false, day = G.today() }))
        assert(G.addMember(gid, { role = "worker", profile = "farmer", female = false, day = G.today() }))
        assert(G.setLeader(gid, "m-1", G.today()))
        t:defer(function()
            p:setGodMod(wasGod)
            if E.Alert then E.Alert.forget(gid) end
            local npcs = { memberNpc(gid, "m-1"), memberNpc(gid, "m-2") }
            for _, npc in ipairs(npcs) do C().disengage(npc, "suite lk.retreat over") end
            G.remove(gid)
            for _, npc in ipairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove group " .. gid)
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        local fighter, worker
        local function describe()
            return string.format("fighter %s: %s, combat %s; worker %s: %s, gesture %s", tostring(fighter),
                stateOf(fighter), tostring(C().get(fighter) and C().get(fighter).u), tostring(worker), stateOf(worker),
                E.Anim.gestureOf(worker))
        end
        t:waitUntil(function()
            fighter, worker = memberNpc(gid, "m-1"), memberNpc(gid, "m-2")
            return fighter ~= nil and worker ~= nil and E.Bodies.find(fighter) ~= nil and E.Bodies.find(worker) ~= nil
                and K.standing(fighter)() and K.standing(worker)()
        end, BODIES_MS, function(t2)
            measure("members before: " .. describe())
            local st = Dec().stats
            local calls0 = st.helpCalls
            local lines0, betrayals0 = st.surrenderLines or 0, st.betrayalLines or 0
            t2:ok(hit(worker, p, nil, 0.05) ~= nil, "first hit not applied")
            measure("worker hit once: help calls " .. (st.helpCalls - calls0))
            t2:eq(1, st.helpCalls - calls0, "call for help after the hit")
            t2:waitUntil(function() return engagedOn(fighter, name) end, STEP_MS, function(t3)
                measure("help: " .. describe())
                t3:ok(string.find(Dec().get(fighter).why or "", "(help)", 1, true) ~= nil, "fighter not engaged for help")
                hit(worker, p, 0.5, 0.05)
                measure(string.format("worker hit below 60 %%: health %.2f of %.2f", E.Health.get(worker).hp,
                    E.Health.get(worker).max))
                t3:waitUntil(function()
                    local ws = Dec().get(worker)
                    return ws ~= nil and ws.b == "surrender" and E.Anim.gestureOf(worker) == "surrender"
                        and C().get(fighter) == nil
                end, STEP_MS, function(t4)
                    measure("surrender: " .. describe() .. ", spared " .. tostring(Dec().spared(gid, name,
                        Dec().currentMinute())))
                    t4:ok(Dec().spared(gid, name, Dec().currentMinute()), "player not spared by the group")
                    -- LK06-T12: one line at the start, none later (more decision passes while it lasts).
                    t4:sleep(5000, function(t4b)
                        measure(string.format("surrender line: %d said, %d betrayal line(s), gesture %s",
                            st.surrenderLines - lines0, st.betrayalLines - betrayals0, E.Anim.gestureOf(worker)))
                        t4b:eq(1, st.surrenderLines - lines0, "one surrender line (heard by the player)")
                        t4b:eq("surrender", E.Anim.gestureOf(worker), "hands not raised")
                        local broken0 = st.surrenderBroken
                        hit(worker, p, nil, 0.02)
                        t4b:eq(1, st.surrenderBroken - broken0, "surrender broken by a new hit")
                        measure(string.format("betrayal: %d line(s), gesture %s", st.betrayalLines - betrayals0,
                            E.Anim.gestureOf(worker)))
                        t4b:ok(E.Anim.gestureOf(worker) ~= "surrender", "hands still raised after the betrayal")
                        t4b:waitUntil(function()
                            local ws = Dec().get(worker)
                            return engagedOn(fighter, name) and (ws == nil or ws.b ~= "surrender")
                        end, STEP_MS, function(t5)
                            measure("broken surrender: " .. describe())
                            local live = G.state.data.groups[gid]
                            live.home = { x = home.x + 15, y = home.y, z = home.z }
                            measure("home moved to " .. live.home.x .. "," .. live.home.y .. "," .. live.home.z)
                            hit(fighter, p, 0.3, 0.05)
                            t5:waitUntil(function()
                                local fs = Dec().get(fighter)
                                local e = E.Directives.get(fighter)
                                return fs ~= nil and fs.b == "retreat" and C().get(fighter) == nil and e ~= nil
                                    and e.op == E.Directives.OP_MOVE and e.g == "run"
                            end, STEP_MS, function(t6)
                                local e = E.Directives.get(fighter)
                                measure(string.format("retreat: %s, run order to %d,%d,%d, retreats %d, help calls %d",
                                    describe(), e.x, e.y, e.z, st.retreats, st.helpCalls - calls0))
                                t6:ok(e.x > home.x, "run order not towards the moved home")
                                -- E01-T16: the surrender and betrayal bubbles reached the other clients.
                                RST.PeerChecks.checkSpeech(t6, said)
                            end, "wounded fighter did not retreat")
                        end, "fighter not engaged again after the broken surrender")
                    end)
                end, "worker did not surrender, or the fighter kept fighting")
            end, "fighter did not come to help")
        end, "group members not materialized and standing")
    end)
end)
