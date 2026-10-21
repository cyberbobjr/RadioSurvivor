--[[
lk.routines - routines of Living Knox npcs at home (LK05-T03, server/LivingKnox/LK_Routines.lua): survey of the home
(guard posts at doors and windows, a round around the building, beds), guard post at night, round at dawn, sleep on
a bed (or sitting inside), a threat that interrupts the routine. Tags "world" and "server": the authority only, on a
save named rstest*, with a target player (t.ctx.player) standing INSIDE a house (the test group gets its home on the
player's square), the Living Knox option Enabled on. Solo: RST.run({ suite = "lk.routines", tags = "world" }).
Asynchronous run only (about 3 to 5 minutes). Multiplayer: final session.

What is done:
    - a test group "settlers" (two fighters, one worker) is created with its home on the player's square; its members
      get bodies near the player (LK_Materialize) and the home is surveyed at their first decision;
    - the clock is moved to 23:00 (GameTime.setTimeOfDay; the world age follows, see docs/annexes/conception/routines.md),
      the group is scored again: one sentry walks to a guard post and faces out, the two others sleep (a bed, or
      sitting inside the house);
    - a fake zombie is reported to a sleeper (LivingKnox.Senses.perceived replaced for the test): it gets up and
      watches or flees; the fake zombie is removed, the routine resumes;
    - the clock is moved to 6:30 (dawn): the sentry makes the round (at least two points visited in order).
Every phase prints "[LKR] measure ..." lines. Cleanup (t:defer): perception restored, bodies removed, test group
removed. The clock is NOT set back (the world age would go backwards): the save ends the run at dawn.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

local K = RST.LKHelpers
local measure = K.measurer("[LKR]")

local BODIES_MS = 60000     -- materialization of the three members
local SURVEY_MS = 20000     -- first decisions of the members (survey of the home)
local POST_MS = 90000       -- sentry at its post, facing out
local SLEEP_MS = 120000     -- sleepers sitting
local THREAT_MS = 15000     -- reaction to the fake zombie
local ROUND_MS = 150000     -- two round points visited

local function LK() return LivingKnox end
local function R() return LivingKnox.Routines end
local function Dec() return LivingKnox.Decisions end

local function memberNpcs(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    if g == nil then return out end
    for mid, m in pairs(g.members) do
        if m.npc ~= nil then out[mid] = m.npc end
    end
    return out
end

local function bodyCount(gid)
    local n = 0
    for _, npc in pairs(memberNpcs(gid)) do
        if LK().Bodies.find(npc) ~= nil then n = n + 1 end
    end
    return n
end

local function allStanding(gid)
    for _, npc in pairs(memberNpcs(gid)) do
        if not K.standing(npc)() then return false end
    end
    return true
end

-- Members by duty: { sentry = { mid, ... }, other = { mid, ... } } (sorted).
local function byDuty(gid)
    local g = LK().Groups.get(gid)
    local out = { sentry = {}, other = {} }
    for mid, m in pairs(g.members) do
        if m.duty == "sentry" then out.sentry[#out.sentry + 1] = mid else out.other[#out.other + 1] = mid end
    end
    table.sort(out.sentry)
    table.sort(out.other)
    return out
end

local function setHour(hod)
    getGameTime():setTimeOfDay(hod)
    local n = Dec().scorePass(nil, nil)
    measure(string.format("time of day set to %.1f, world age %.2f h, %d group(s) scored", hod,
        getGameTime():getWorldAgeHours(), n))
end

local function dist(z, x, y)
    local dx, dy = z:getX() - (x + 0.5), z:getY() - (y + 0.5)
    return math.sqrt(dx * dx + dy * dy)
end

RST.suite("lk.routines", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("survey, guard post at night, sleep, threat, round at dawn", function(t)
        local E = LK()
        t:ok(E ~= nil and E.Routines ~= nil and E.Decisions ~= nil, "LivingKnox.Routines is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local sq = p:getCurrentSquare()
        if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST routines", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end   -- no furnishing (LK08-T04) on the test site
        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "farmer" }, { "fighter", "guard" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        -- The player stands in the home of the group: unknown, it is an intruder and the whole group watches it
        -- instead of following its routine (in-game run of 2026-10-13, alert "intruder" for 90 s). Two gifts make it
        -- a known, friendly player for this group (LivingKnox.Alert.playerKind).
        -- Without a notebook character bound to the player (bench doubles) there is no attitude key: nothing to do.
        local Ho = E.Hostility
        local key = Ho and Ho.keyOf and Ho.keyOf(p)
        if key ~= nil then
            for _ = 1, 2 do
                local res, why = Ho.record(gid, key, "gift", { attributable = true, day = G.today() })
                t:ok(res ~= nil, "attitude fact refused: " .. tostring(why))
            end
            t:eq(nil, E.Alert.playerKind(gid, "settlers", p), "the player is still a threat to the test group")
        else
            measure("no attitude key for the target player (no notebook character bound): not befriended")
        end
        -- Water, food and ammo in the first container of the home: without them the need "supply" outranks the night
        -- rest and only one member sleeps (in-game runs of 2026-10-13: "supply 90 (water 0) > rest 72", then, water
        -- given, "supply 90 (ammo 0) > rest 70": the kit stores nothing when no container of the home is owned).
        local St = E.Stock
        local fixture = {}
        local cts
        if E.Homes ~= nil and E.Homes.ready ~= nil and St ~= nil and St.containers ~= nil then
            local style, def = E.Homes.ready(home)
            if style ~= nil then cts = St.containers(gid, home, style, def ~= nil and def:getIDString() or nil) end
        end
        if cts ~= nil and #cts > 0 then
            local fixtureBox = cts[1].container
            if not fixtureBox:isExplored() then fixtureBox:setExplored(true) end
            for _, ft in ipairs({ "Base.WaterBottle", "Base.WaterBottle", "Base.WaterBottle", "Base.WaterBottle",
                "Base.TinnedBeans", "Base.TinnedBeans", "Base.ShotgunShellsBox", "Base.ShotgunShellsBox" }) do
                local it = instanceItem(ft)
                if it ~= nil then
                    if it:getFluidContainer() ~= nil then
                        it:getFluidContainer():Empty()
                        it:getFluidContainer():addFluid(Fluid.Water, it:getFluidContainer():getCapacity())
                    end
                    fixtureBox:AddItem(it)
                    if isServer() then sendAddItemToContainer(fixtureBox, it) end
                    fixture[#fixture + 1] = it
                end
            end
            t:defer(function()
                for _, it in ipairs(fixture) do
                    if fixtureBox:containsID(it:getID()) then
                        fixtureBox:DoRemoveItem(it)
                        if isServer() then sendRemoveItemFromContainer(fixtureBox, it) end
                    end
                end
                if St.clear then St.clear(gid) end
            end, "remove the water and food of the test")
            local r = St.check(gid, { force = true })
            if type(r) == "table" and r.totals then
                measure(string.format("stock: %d food, %d water, %d ammo", r.totals.food or 0, r.totals.water or 0,
                    r.totals.ammo or 0))
            end
        else
            measure("no container in the home: no water given, the night rest may lose to the need supply")
        end
        -- The world age only moves forward when the clock is set between 7:00 and 23:00 (GameTime.getWorldAgeHours:
        -- nights x 24 + hour - 7, or + 17 before 7:00); before 7:00 or late in the evening, the clock is first put
        -- at 6:59 and the game itself crosses 7:00 (one more night survived). The time is not set back afterwards.
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 22.9 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        local perceived = E.Senses.perceived
        t:defer(function()
            E.Senses.perceived = perceived
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove group " .. gid)
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        -- Dedicated server: the players leave the house (solid; campaign MP 2026-10-15: sentry stuck against them).
        K.clearHome(t, home, function(tc)
        tc:waitUntil(function()
            local now = getGameTime():getTimeOfDay()
            return bodyCount(gid) == 3 and allStanding(gid) and now >= 7 and now < 22.9
        end, BODIES_MS, function(t2)
            t2:waitUntil(function()
                local live = G.get(gid)
                return live ~= nil and live.posts ~= nil
            end, SURVEY_MS, function(t3)
                local posts = G.get(gid).posts
                measure(string.format("survey: %d post(s), round of %d, %d bed(s), camp %s", #posts.posts,
                    #posts.round, #posts.beds, tostring(posts.camp == true)))
                t3:ok(posts.camp ~= true, "home surveyed as a camp (no building)")
                setHour(23)
                local duty = byDuty(gid)
                t3:ok(#duty.sentry >= 1 and #duty.other >= 1, "night duties: " .. #duty.sentry .. " sentry, "
                    .. #duty.other .. " other")
                local npcs = memberNpcs(gid)
                local sentry = npcs[duty.sentry[1]]
                local live = G.get(gid)
                local post = R().postFor(posts, live, duty.sentry[1], Dec().currentHour())
                t3:waitUntil(function()
                    local m = R().get(sentry)
                    local e = E.Directives.get(sentry)
                    if post == nil then return e ~= nil and e.op == "face" and e.done end
                    local z = E.Bodies.find(sentry)
                    return m ~= nil and m.faceV ~= nil and e ~= nil and e.v == m.faceV and e.done and z ~= nil
                        and dist(z, post.x, post.y) <= 1.5
                end, POST_MS, function(t4)
                    local z = E.Bodies.find(sentry)
                    measure(string.format("night post: %s at %s, body %.1f,%.1f facing %d (post angle %s), vigilance %s",
                        sentry, post and (post.k .. " " .. post.x .. "," .. post.y) or "none", z:getX(), z:getY(),
                        math.floor(z:getDirectionAngle()), tostring(post and post.a), E.Senses.vigilanceOf(sentry)))
                    t4:eq("guard", E.Senses.vigilanceOf(sentry), "sentry vigilance")
                    t4:waitUntil(function()
                        for _, mid in ipairs(duty.other) do
                            if E.Anim.gestureOf(npcs[mid]) ~= "sit" then return false end
                        end
                        return true
                    end, SLEEP_MS, function(t5)
                        for _, mid in ipairs(duty.other) do
                            local npc = npcs[mid]
                            local bed = R().bedFor(posts, G.get(gid), mid)
                            local zb = E.Bodies.find(npc)
                            measure(string.format("sleep: %s %s, body %.1f,%.1f, bed %s, vigilance %s", mid, npc,
                                zb:getX(), zb:getY(), bed and (bed.bx .. "," .. bed.by) or "none (sitting inside)",
                                E.Senses.vigilanceOf(npc)))
                            t5:eq("sleep", E.Senses.vigilanceOf(npc), mid .. " vigilance")
                        end
                        local woken = npcs[duty.other[1]]
                        local wz = E.Bodies.find(woken)
                        local zx, zy = math.floor(wz:getX()) + 3, math.floor(wz:getY())
                        E.Senses.perceived = function(id)
                            if id ~= woken then return perceived(id) end
                            return { ms = getTimestampMs(), age = 0, stale = false, nz = 1, seen = 1, heard = 0, p = {},
                                z = { { o = -42, x = zx, y = zy, z = math.floor(wz:getZ()), a = 1, s = true, h = false,
                                    d = 3 } }, n = {} }
                        end
                        t5:waitUntil(function()
                            local st = Dec().get(woken)
                            return st ~= nil and st.rule == "threat" and E.Anim.gestureOf(woken) ~= "sit"
                        end, THREAT_MS, function(t6)
                            local st = Dec().get(woken)
                            measure("threat: " .. woken .. " " .. st.b .. " (" .. st.why .. "), gesture "
                                .. E.Anim.gestureOf(woken))
                            t6:ok(R().get(woken) == nil, "routine memory kept during the threat")
                            E.Senses.perceived = perceived
                            setHour(6.5)
                            local dawn = byDuty(gid)
                            t6:ok(#dawn.sentry >= 1, "no sentry at dawn")
                            local walker = npcs[dawn.sentry[1]]
                            local seen = {}
                            t6:waitUntil(function()
                                local m = R().get(walker)
                                if m ~= nil and m.k ~= nil and seen[#seen] ~= m.k then seen[#seen + 1] = m.k end
                                return #seen >= 3
                            end, ROUND_MS, function(t7)
                                local ws = Dec().get(walker)
                                measure("dawn round: " .. walker .. " points " .. table.concat(seen, ",") .. ", state "
                                    .. tostring(ws and ws.b) .. ", laps " .. R().stats.laps)
                                t7:eq("patrol", ws and ws.b, "sentry behaviour at dawn")
                            end, "round not walked (fewer than two round points reached)")
                        end, "threat ignored by the sleeper")
                    end, "sleepers not sitting")
                end, "sentry not at its post")
            end, "home not surveyed")
        end, "group members not materialized and standing")
        end)
    end)
end)
