--[[
lk.raid - raids of a raider group on a player base (LK11-T07, server/LivingKnox/LK_Raids.lua): a base noted on two
different days sends one or two real scouts (scout role first, never the leader); killed scouts call the raid off;
scouts back home announce it (group log, public fact), then a real team (members of a "raid" role, scouts included,
one member left home) leaves home, travels and attacks: its bodies are created only far from every living player
(REVENGE.SPAWN_MIN squares or more, same spawning as the revenge of LK11-T05), then it goes home.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player) standing
in his base (a building; outdoors, a 10 x 10 base is assumed around him) with free ground around (the bodies appear
40 to 75 squares away, on the side of the test group's home, 400 squares east). Solo: RST.run({ suite = "lk.raid",
tags = "world" }). Dedicated server: RST.server({ suite = "lk.raid", tags = "world" }) from an admin client.
Shortened for the test (restored afterwards): RaidDays 0 (Raids.settings), SCOUT_HOURS 1, ANNOUNCE_HOURS 0,
ATTACK_HOURS 1, SPEED 100000 (one hour of travel). The hours are driven by the suite (Raids.offscreenHour and
Raids.raidReturn on the test group, as LK_Simulation does each game hour): no real time passes. The sightings are
noted directly (Raids.note, two days) with a test player key ("rst-raid-<ms>"); the real signs of the base are only
noted (t:note), not required. No speech bubble is checked here (manual check, docs/conception/raids.md).
Cleanup (t:defer): bodies and npcs of the test groups removed (Bodies.despawn), groups removed, settings restored.

What is checked (nominal path):
    - scouts: 1 or 2 living members, scout role first, never the leader; their bodies at SPAWN_MIN squares or more
      from every living player; killed scouts: raid ended "cancelled", no attack;
    - announce: "scouts saw the base" entry in the group log, then the scouts back home;
    - attack: team of 2 or more members of a "raid" role, not the leader, one member left home; bodies at SPAWN_MIN
      squares or more from every living player; return and end "done".
Outside the game: tests/test_lk_raids.py (the suite also runs there against doubles).
]]

require "RST/RST"

local FAR = 400   -- squares between the player and the test group's home

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Raids is not loaded on an MP client (authority only)")
    end
    local E = LivingKnox
    if E == nil or type(E.Raids) ~= "table" or E.Raids.offscreenHour == nil or type(E.Bodies) ~= "table" then
        t:skip("LivingKnox.Raids is not loaded here")
    end
    t:ok(E.Groups.ensure(), "group registry not ready")
    t:ok(E.Hostility.ensure(), "attitude registry not ready")
    return E
end

-- Shortened settings, restored by the returned function.
local function shorten(E)
    local Ra, cfg = E.Raids, E.Raids.CFG
    local saved = { settings = Ra.settings }
    for _, k in ipairs({ "SCOUT_HOURS", "ANNOUNCE_HOURS", "ATTACK_HOURS", "SPEED" }) do saved[k] = cfg[k] end
    Ra.settings = function() return { enabled = true, days = 0 } end
    cfg.SCOUT_HOURS, cfg.ANNOUNCE_HOURS, cfg.ATTACK_HOURS, cfg.SPEED = 1, 0, 1, 100000
    return function()
        Ra.settings = saved.settings
        for k, v in pairs(saved) do
            if k ~= "settings" then cfg[k] = v end
        end
    end
end

-- Test group of raiders 400 squares east of the player: m-1 leader (deputy), m-2 scout, m-3 and m-4 fighters,
-- m-5 worker.
local function makeGroup(E, t, p, name)
    local G, B = E.Groups, E.Bodies
    local home = { x = math.floor(p:getX()) + FAR, y = math.floor(p:getY()), z = 0 }
    local g = assert(G.create({ type = "raiders", name = name, day = G.today(), home = home }))
    local gid = g.id
    for _, role in ipairs({ "deputy", "scout", "fighter", "fighter", "worker" }) do
        assert(G.addMember(gid, { role = role, day = G.today() }))
    end
    assert(G.setLeader(gid, "m-1", G.today()))
    t:defer(function()
        local live = G.get(gid)
        for _, m in pairs(live and live.members or {}) do
            if m.npc ~= nil then B.despawn(m.npc, true) end
        end
        G.remove(gid)
    end, "remove the bodies, the npcs and group " .. gid)
    return gid
end

-- Base of the player (his building or safehouse), or a 10 x 10 base around him.
local function baseOf(E, t, p)
    local b = E.Raids.baseOf(p)
    if b ~= nil then
        local s = E.Raids.signs(b)
        t:note(string.format("base %s at %d,%d: signs '%s' (score %d, %d squares read)", b.id, b.x, b.y, s.text,
            s.score, s.squares))
        return b
    end
    local x, y = math.floor(p:getX()), math.floor(p:getY())
    t:note("player outdoors: a 10 x 10 base is assumed around him")
    return { id = "rst:" .. x .. "," .. y, x1 = x - 5, y1 = y - 5, x2 = x + 4, y2 = y + 4, x = x, y = y, z = 0,
        src = "building", top = 0 }
end

-- Base noted on two different days by the group (as Raids.survey does).
local function noted(E, gid, b, p, key)
    local G = E.Groups
    local day = G.today()
    G.update(function(d)
        local g = d.groups[gid]
        E.Raids.note(g, gid, b, { text = "rst", score = 9 }, p:getUsername(), key, day - 1)
        E.Raids.note(g, gid, b, { text = "rst", score = 9 }, p:getUsername(), key, day)
        return true, true
    end)
end

-- One game hour of the test group's raid, as LK_Simulation does it (offscreen step, then the team's return).
local function step(E, gid, hour)
    E.Groups.update(function(d)
        local g = d.groups[gid]
        if g == nil then return false, false end
        E.Raids.offscreenHour(d, g, gid, hour)
        local e = g.expedition
        if type(e) == "table" and e.place == "raid" and hour >= e.returns then
            E.Raids.raidReturn(g, gid, hour, math.floor(hour / 24) + 1)
        end
        return true, true
    end)
    local g = E.Groups.get(gid)
    return g and g.raid or nil
end

local function lastRaidLog(E, gid, text)
    local out
    for _, e in ipairs(E.Groups.get(gid).log) do
        if e.kind == "raid" and (text == nil or string.find(e.text, text, 1, true) ~= nil) then out = e.text end
    end
    return out
end

-- Bodies of the team created by the pass, each far from every living player; then released. Returns their number.
local function bodiesFar(E, t, gid, team, what)
    local B, cfg = E.Bodies, E.Relations.REVENGE
    local made = E.Raids.pass() + E.Raids.pass() + E.Raids.pass()
    t:eq(#team, made, what .. " bodies created")
    local players = B.livingPlayers()
    for _, mid in ipairs(team) do
        local m = E.Groups.get(gid).members[mid]
        local z = m and m.npc and B.find(m.npc) or nil
        t:ok(z ~= nil, what .. " member " .. mid .. " has no body")
        for _, q in ipairs(players) do
            local gap = math.max(math.abs(z:getX() - q:getX()), math.abs(z:getY() - q:getY()))
            t:ok(gap >= cfg.SPAWN_MIN, string.format("%s member %s appeared %.1f squares from %s (min %d)", what, mid,
                gap, tostring(q:getUsername()), cfg.SPAWN_MIN))
        end
        t:note(string.format("%s member %s at %d,%d", what, mid, math.floor(z:getX()), math.floor(z:getY())))
    end
    for _, mid in ipairs(team) do
        local m = E.Groups.get(gid).members[mid]
        if m.npc ~= nil and B.find(m.npc) ~= nil then B.release(m.npc, "lk.raid") end
    end
    return made
end

local function checkTeam(E, t, gid, team, what)
    local live = E.Groups.get(gid)
    for _, mid in ipairs(team) do
        local m = live.members[mid]
        t:ok(m ~= nil and m.alive, what .. " " .. tostring(mid) .. " is not a living member")
        t:ok(mid ~= live.leader, "the leader left with the " .. what)
        t:ok(E.Raids.roleHas(live.type, m.role, "raid"), what .. " " .. mid .. " has no raid role (" .. m.role .. ")")
    end
    t:ok(#E.Materialize.presentMembers(live) >= 1, "nobody left home")
end

RST.suite("lk.raid", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("scouts, announce, real team far from the players, return", function(t)
        local E = module(t)
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        t:defer(shorten(E), "restore the raid settings")
        local gid = makeGroup(E, t, p, "RST raid")
        local key = "rst-raid-" .. tostring(getTimestampMs())
        noted(E, gid, baseOf(E, t, p), p, key)
        local hour = math.floor(getGameTime():getWorldAgeHours())

        -- Scouts.
        local r = step(E, gid, hour)
        t:ok(r ~= nil, "raid lost at the scouts' departure")
        t:eq("scout", r.phase, "phase after a base seen on two days")
        t:ok(#r.team >= 1 and #r.team <= 2, "scouts: " .. #r.team)
        t:eq("m-2", r.team[1], "first scout (scout role first)")
        checkTeam(E, t, gid, r.team, "scout")
        r = step(E, gid, hour + 1)
        t:eq("at", r.step, "scouts at the base after the travel")
        bodiesFar(E, t, gid, r.team, "scout")

        -- Announce, scouts back home.
        r = step(E, gid, hour + 2)
        t:ok(lastRaidLog(E, gid, "scouts saw the base") ~= nil, "no announce in the group log")
        local h = hour + 2
        for _ = 1, 4 do
            if r == nil or r.phase ~= "scout" then break end
            h = h + 1
            r = step(E, gid, h)
        end
        t:ok(r ~= nil, "raid lost after the scouting")
        t:ok(r.phase == "ready" or r.phase == "raid", "phase after the scouts' return: " .. tostring(r.phase))

        -- Attack by a real team.
        for _ = 1, 3 do
            if r.phase == "raid" then break end
            h = h + 1
            r = step(E, gid, h)
        end
        t:eq("raid", r.phase, "attack not launched")
        t:ok(#r.team >= 2, "attack team: " .. #r.team)
        checkTeam(E, t, gid, r.team, "raider")
        h = h + 1
        r = step(E, gid, h)
        t:eq("at", r.step, "raiders at the base after the travel")
        local made = bodiesFar(E, t, gid, r.team, "raider")

        -- Return and end.
        for _ = 1, 6 do
            h = h + 1
            r = step(E, gid, h)
            if r == nil then break end
        end
        t:eq(nil, r, "raid still under way after the attack")
        local last = lastRaidLog(E, gid) or ""
        t:ok(string.find(last, "ended: done", 1, true) ~= nil, "last raid log entry: " .. last)
        print("[LKR] measure raid: group " .. gid .. ", " .. made .. " raider bodies, ended at hour " .. h)
    end)

    s.test("killed scouts call the raid off", function(t)
        local E = module(t)
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        t:defer(shorten(E), "restore the raid settings")
        local gid = makeGroup(E, t, p, "RST raid off")
        noted(E, gid, baseOf(E, t, p), p, "rst-raid-off-" .. tostring(getTimestampMs()))
        local hour = math.floor(getGameTime():getWorldAgeHours())
        local r = step(E, gid, hour)
        t:eq("scout", r and r.phase, "scouts not sent")
        for _, mid in ipairs(r.team) do E.Groups.markDead(gid, mid, E.Groups.today()) end
        r = step(E, gid, hour + 1)
        t:eq(nil, r, "raid still under way after the death of its scouts")
        local last = lastRaidLog(E, gid) or ""
        t:ok(string.find(last, "ended: cancelled", 1, true) ~= nil, "last raid log entry: " .. last)
        for h = hour + 2, hour + 6 do t:eq(nil, step(E, gid, h), "raid revived at hour " .. h) end
        t:eq(nil, E.Groups.get(gid).expedition, "an expedition left after the cancel")
    end)
end)
