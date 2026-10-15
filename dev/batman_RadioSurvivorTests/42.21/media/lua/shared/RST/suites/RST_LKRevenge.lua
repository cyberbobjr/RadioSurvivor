--[[
lk.revenge - delayed revenge of a Living Knox group after the loss of a member (LK11-T05, revenge section of
server/LivingKnox/LK_Relations.lua): a member killed by a player identified by the server gives the attitude fact
"kill"; a group left hostile swears revenge; after a delay a real team (living fighters of the roster, never the
leader, at least one member left home) leaves home as an offscreen expedition, travels, then hunts at the last known
zone of the player: its bodies are created only far from every living player (REVENGE.SPAWN_MIN squares or more);
failed hunts are counted and the revenge is given up after REVENGE.MAX_FAILS.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
outdoors with free ground around (the bodies appear 40 to 75 squares away, on the side of the test group's home,
400 squares east). Solo: RST.run({ suite = "lk.revenge", tags = "world" }). Dedicated server: RST.server({ suite =
"lk.revenge", tags = "world" }) from an admin client.
Shortened delays for the test (restored afterwards, DELAY_HOURS back to nil = the option): DELAY_HOURS 0,
RETRY_HOURS 0, HUNT_HOURS 1, SPEED 100000 (one hour of travel). The hours are driven by the suite
(Relations.offscreenHour and Relations.revengeReturn on the test group, as LK_Simulation does each game hour): no real
time passes. The kill is recorded with a test player key ("rst-rev-<ms>") and the player's account; no bubble is
checked here (the oath line needs a group body near the death: manual check, docs/conception/vengeance.md).
Cleanup (t:defer): bodies and npcs of the test group removed (Bodies.despawn), group removed, settings restored.

What is checked (nominal path):
    - raiders group (home 400 squares east of the player): kill -> oath (level hostile), revenge entry in the group
      log, the existing target choice attacks the player key for "revenge";
    - departure: team = 2 living fighters, not the leader, the leader stays home (present members);
    - hunt: one body per team member, each at SPAWN_MIN squares or more from every living player; no body at home;
    - bodies released, then failed hunts until the revenge ends "given_up" (abandon checked).
Second test (LK11-T10): the delay between the oath and the departure comes from the sandbox option
LivingKnox.RevengeDelayHours (integer 12..336, default 72), changed in memory as an admin would (option:setValue,
restored afterwards); an oath already sworn keeps its departure hour when the option changes. Offscreen only (no body).
Outside the game: tests/test_lk_revenge.py (the suite also runs there against doubles).
]]

require "RST/RST"

local FAR = 400   -- squares between the player and the test group's home

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Relations is not loaded on an MP client (authority only)")
    end
    local E = LivingKnox
    if E == nil or type(E.Relations) ~= "table" or E.Relations.offscreenHour == nil or type(E.Bodies) ~= "table" then
        t:skip("LivingKnox.Relations (revenge) is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    t:ok(E.Hostility.ensure(), "attitude registry not ready")
    return E
end

-- One game hour of the test group's revenge, as LK_Simulation does it (offscreen step, then the team's return).
local function step(E, gid, hour)
    E.Groups.update(function(d)
        local g = d.groups[gid]
        if g == nil then return false, false end
        E.Relations.offscreenHour(g, gid, hour)
        local e = g.expedition
        if type(e) == "table" and e.place == "revenge" and hour >= e.returns then
            E.Relations.revengeReturn(g, gid, hour, math.floor(hour / 24) + 1)
        end
        return true, true
    end)
    local g = E.Groups.get(gid)
    return g and g.revenge or nil
end

local function lastRevengeLog(E, gid)
    local out
    for _, e in ipairs(E.Groups.get(gid).log) do
        if e.kind == "revenge" then out = e.text end
    end
    return out
end

local function bodyOf(E, gid, mid)
    local m = E.Groups.get(gid).members[mid]
    return m and m.npc and E.Bodies.find(m.npc) or nil
end

RST.suite("lk.revenge", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("oath, team from the roster, spawn away from the players, abandon", function(t)
        local E = module(t)
        local R, G, H, B = E.Relations, E.Groups, E.Hostility, E.Bodies
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local px, py = math.floor(p:getX()), math.floor(p:getY())
        local cfg = R.REVENGE
        local keys, saved = { "DELAY_HOURS", "RETRY_HOURS", "HUNT_HOURS", "SPEED" }, {}
        for _, k in ipairs(keys) do saved[k] = cfg[k] end
        cfg.DELAY_HOURS, cfg.RETRY_HOURS, cfg.HUNT_HOURS, cfg.SPEED = 0, 0, 1, 100000
        local home = { x = px + FAR, y = py, z = 0 }
        local g = assert(G.create({ type = "raiders", name = "RST revenge", day = G.today(), home = home }))
        local gid = g.id
        for _, role in ipairs({ "deputy", "fighter", "fighter", "worker" }) do
            assert(G.addMember(gid, { role = role, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        t:defer(function()
            for _, k in ipairs(keys) do cfg[k] = saved[k] end   -- DELAY_HOURS nil = the sandbox option (LK11-T10)
            local live = G.get(gid)
            for _, m in pairs(live and live.members or {}) do
                if m.npc ~= nil then B.despawn(m.npc, true) end
            end
            G.remove(gid)
        end, "remove the bodies, the npcs and group " .. gid .. ", restore the revenge settings")

        -- Oath.
        local key = "rst-rev-" .. tostring(getTimestampMs())
        G.markDead(gid, "m-4", G.today())
        local out, why = R.memberKilled(gid, "m-4", key, { u = p:getUsername(), x = px, y = py, z = 0 })
        t:ok(out ~= nil, "kill not recorded: " .. tostring(why))
        t:eq(true, out.sworn, "oath (" .. tostring(out.reason) .. ")")
        t:eq("hostile", out.level, "attitude after the kill")
        t:ok(string.find(lastRevengeLog(E, gid) or "", "revenge sworn", 1, true) ~= nil, "no oath in the group log")
        local choice = H.chooseTarget(gid, "lk-0", { { u = "rst", key = key, d = 5 } }, G.today() + 5)
        t:eq("revenge", choice and choice.target and choice.target.reason, "reason of the target choice")

        -- Departure of a real team.
        local hour = math.floor(getGameTime():getWorldAgeHours())
        local r = step(E, gid, hour)
        t:ok(r ~= nil, "revenge lost at the departure")
        t:eq("out", r.phase, "phase after the shortened delay")
        t:eq(2, #r.team, "team size")
        local live = G.get(gid)
        for _, mid in ipairs(r.team) do
            local m = live.members[mid]
            t:ok(m ~= nil and m.alive, "team member " .. tostring(mid) .. " is not a living member")
            t:ok(mid ~= live.leader, "the leader left with the team")
            t:ok(R.combatant(live.type, m.role), "team member " .. mid .. " is not a fighter (" .. m.role .. ")")
        end
        local present = E.Materialize.presentMembers(live)
        t:eq(1, #present, "members left at home")
        t:eq("m-1", present[1], "member left at home")

        -- Hunt: bodies far from every living player.
        r = step(E, gid, hour + 1)
        t:eq("hunt", r.phase, "phase after the travel")
        local made = R.huntPass() + R.huntPass()
        t:eq(#r.team, made, "bodies created for the hunt")
        local players = B.livingPlayers()
        for _, mid in ipairs(r.team) do
            local z = bodyOf(E, gid, mid)
            t:ok(z ~= nil, "team member " .. mid .. " has no body")
            for _, q in ipairs(players) do
                local gap = math.max(math.abs(z:getX() - q:getX()), math.abs(z:getY() - q:getY()))
                t:ok(gap >= cfg.SPAWN_MIN, string.format("member %s appeared %.1f squares from %s (min %d)", mid,
                    gap, tostring(q:getUsername()), cfg.SPAWN_MIN))
            end
            t:note(string.format("member %s at %d,%d", mid, math.floor(z:getX()), math.floor(z:getY())))
        end
        t:eq(nil, bodyOf(E, gid, "m-1"), "the leader got a body")

        -- Abandon: bodies back to the simulation, then failed hunts until the revenge ends.
        for _, mid in ipairs(r.team) do
            local m = G.get(gid).members[mid]
            if m.npc ~= nil and B.find(m.npc) ~= nil then B.release(m.npc, "lk.revenge") end
        end
        local h = hour + 1
        for _ = 1, 40 do
            h = h + 1
            r = step(E, gid, h)
            if r == nil then break end
        end
        t:eq(nil, r, "revenge still active after the failed hunts")
        local last = lastRevengeLog(E, gid) or ""
        t:ok(string.find(last, "ended: given_up", 1, true) ~= nil, "last revenge log entry: " .. last)
        t:eq(false, H.isRevengeTarget(gid, key), "player still a revenge target")
        print("[LKR] measure revenge: group " .. gid .. ", " .. made .. " bodies, abandoned at hour " .. h)
    end)

    s.test("the oath delay comes from the RevengeDelayHours option", function(t)
        local E = module(t)
        local R, G = E.Relations, E.Groups
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        t:eq(nil, R.REVENGE.DELAY_HOURS, "delay forced (REVENGE.DELAY_HOURS) instead of the option")
        local options = getSandboxOptions and getSandboxOptions()
        local o = options and options:getOptionByName("LivingKnox.RevengeDelayHours")
        t:ok(o ~= nil, "option LivingKnox.RevengeDelayHours not registered (sandbox-options.txt)")
        local v0 = o:getValue()
        t:defer(function() o:setValue(v0) end, "restore LivingKnox.RevengeDelayHours")
        t:eq(v0, R.revengeDelayHours(), "delay read from the option")
        local v1 = v0 == 24 and 36 or 24
        o:setValue(v1)
        t:eq(v1, o:getValue(), "option changed in memory")
        local px, py = math.floor(p:getX()), math.floor(p:getY())
        local g = assert(G.create({ type = "raiders", name = "RST revenge delay", day = G.today(),
            home = { x = px + FAR, y = py, z = 0 } }))
        local gid = g.id
        for _, role in ipairs({ "deputy", "fighter", "fighter", "worker" }) do
            assert(G.addMember(gid, { role = role, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        t:defer(function() G.remove(gid) end, "remove group " .. gid)
        local key = "rst-revd-" .. tostring(getTimestampMs())
        G.markDead(gid, "m-4", G.today())
        local out, why = R.memberKilled(gid, "m-4", key, { u = p:getUsername(), x = px, y = py, z = 0 })
        t:ok(out ~= nil, "kill not recorded: " .. tostring(why))
        t:eq(true, out.sworn, "oath (" .. tostring(out.reason) .. ")")
        local r = G.get(gid).revenge
        t:ok(r ~= nil, "no revenge entry after the oath")
        t:eq(v1, r.due - r.sworn, "hours between the oath and the departure")
        local due = r.due
        o:setValue(v1 == 24 and 300 or 12)
        t:eq(due, G.get(gid).revenge.due, "departure of a sworn revenge changed with the option")
        t:note(string.format("RevengeDelayHours %s -> %d: sworn at hour %d, departure at hour %d", tostring(v0), v1,
            r.sworn, due))
    end)
end)
