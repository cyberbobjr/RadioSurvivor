--[[
lk.alert - group alert of Living Knox npcs (LK05-T08, server/LivingKnox/LK_Alert.lua, behaviour "alert" of
LK_Decisions.lua, cry played by client/LivingKnox/LK_AlertView.lua): a threat seen near the home or a member raises
the alert of the group once per threat; the members stop their tasks (sleepers get up), watch the last known
position with a guard (able member) or crouched (wounded or afraid, LK06-T07) gesture; the member who saw it shouts (speech bubble
"alert", vanilla shout voice, a world sound that also draws zombies); the alert level falls with the game time and
the routine resumes. Tags "world" and "server": the authority only, on a save named rstest*, with a target player
(t.ctx.player) standing INSIDE a house (the test group gets its home on the player's square), the Living Knox option
Enabled on. Solo: RST.run({ suite = "lk.alert", tags = "world" }). Asynchronous run only (about 2 to 4 minutes).
Multiplayer: final session.

What is done:
    - a test group "settlers" (two fighters, one worker) is created with its home on the player's square; its members
      get bodies near the player (LK_Materialize); the clock is moved to 6:59 first when it is night or late evening
      (the world age only moves forward); the target player is hidden from the perception of the group (an unknown
      player at home would be an intruder, LK05-T08);
    - an ordinary zombie is created on a free square in view of the first member, 3 to 6 squares away (inside the
      house first: a still zombie behind a wall is neither seen nor heard): the alert is raised once (id, kind, last
      known position), the cry is counted (line, world sound, voice), every member is alerted;
    - the zombie is removed: the alert level falls, the alert closes ("calm") and no member keeps an alert behaviour;
      the number of alerts raised during the run must be exactly one.
Second test (LK05-T14, danger thresholds read from the sandbox options): same kind of group; the perception of every
member gets a crowd of CROWD fake zombies seen 2 to 16 squares BEYOND the option LivingKnox.ZombieAlertDistance (no
real zombie is created; the real zombies of the world are removed from that perception, so that a wandering zombie
cannot raise a legitimate alert during the measure); for CROWD_HOLD_MS no alert is raised, no member takes a threat
behaviour, no home defense starts and the fear of the members stays low. The thresholds read from the options are
printed ("[LKA] measure thresholds ...").
Every phase prints "[LKA] measure ..." lines; the user checks the bubble, the voice and the gestures. E01-T16: the
other clients of the MP campaign must be among the listeners of the cry and have received it (nothing asked in solo). Cleanup
(t:defer): perception restored, zombie and bodies removed, test group removed. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"
require "RST/RST_PeerChecks"
require "RST/RST_PeerChecksH"

local K = RST.LKHelpers
local measure = K.measurer("[LKA]")

local BODIES_MS = 60000     -- materialization of the three members
local ALERT_MS = 30000      -- alert raised after the zombie is created
local MEMBERS_MS = 20000    -- every member alerted
local CALM_MS = 240000      -- alert closed and routine resumed (game minutes: depends on the day length)
local CROWD = 50            -- fake zombies perceived beyond the alert distance (LK05-T14)
local CROWD_HOLD_MS = 20000 -- the group must stay in its routine this long
local FACING_DEG = 60       -- members turned toward the last known position, seen by every client

local function LK() return LivingKnox end
local function Dec() return LivingKnox.Decisions end
local function Al() return LivingKnox.Alert end

local function memberNpcs(gid)
    local g = LK().Groups.get(gid)
    local out = {}
    if g == nil then return out end
    for mid, m in pairs(g.members) do
        if m.npc ~= nil then out[mid] = m.npc end
    end
    return out
end

local function sortedMids(gid)
    local out = {}
    for mid in pairs(memberNpcs(gid)) do out[#out + 1] = mid end
    table.sort(out)
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

local function describe(gid)
    local parts = {}
    local npcs = memberNpcs(gid)
    for _, mid in ipairs(sortedMids(gid)) do
        local npc = npcs[mid]
        local st = Dec().get(npc)
        parts[#parts + 1] = string.format("%s %s %s gesture %s vigilance %s", mid, npc, st and st.b or "none",
            LK().Anim.gestureOf(npc), LK().Senses.vigilanceOf(npc))
    end
    return table.concat(parts, "; ")
end

local function allAlerted(gid)
    for _, npc in pairs(memberNpcs(gid)) do
        local st = Dec().get(npc)
        if st == nil or st.rule ~= "threat" then return false end
    end
    return true
end

local function noneAlerted(gid)
    for _, npc in pairs(memberNpcs(gid)) do
        local st = Dec().get(npc)
        if st == nil or st.rule == "threat" then return false end
    end
    return true
end

-- Test group with its home on the player's square, three members; the target player is hidden from the perception
-- of the group and extra(per, id, body) may add entries to the perception of a member. Returns E, gid, home or skips.
local function makeGroup(t, name, extra)
    local E = LK()
    t:ok(E ~= nil and E.Alert ~= nil and E.Decisions ~= nil, "LivingKnox.Alert is not loaded on this side")
    t:ok(E.Groups.ensure(), "group registry not ready")
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    local sq = p:getCurrentSquare()
    if sq == nil or sq:getBuildingDef() == nil then t:skip("the player must stand inside a house") end
    local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
    local G = E.Groups
    local g = assert(G.create({ type = "settlers", name = name, day = G.today(), home = home }))
    local gid = g.id
    if E.Homes and E.Homes.skip then E.Homes.skip(gid) end   -- no furnishing (LK08-T04) on the test site
    for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "farmer" }, { "fighter", "guard" } }) do
        assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
    end
    assert(G.setLeader(gid, "m-1", G.today()))
    local tod = getGameTime():getTimeOfDay()
    if tod < 7 or tod >= 22.9 then
        getGameTime():setTimeOfDay(6.98)
        measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
    end
    -- The target player is hidden from the members of the test group: only zombies are threats here.
    local perceived = E.Senses.perceived
    E.Senses.perceived = function(id)
        local per = perceived(id)
        if G.findNpc(id) ~= gid then return per end
        if extra ~= nil then
            local body = E.Bodies.find(id)
            if body ~= nil then per = extra(per, id, body) end
        end
        if per ~= nil then per.p = {} end
        return per
    end
    t:defer(function()
        E.Senses.perceived = perceived
        E.Alert.forget(gid)
        local npcs = memberNpcs(gid)
        G.remove(gid)
        for _, npc in pairs(npcs) do
            E.Directives.forget(npc)
            E.Bodies.despawn(npc, true)
        end
    end, "remove group " .. gid)
    t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
    return E, gid, home
end

local function ready(gid)
    return function()
        local now = getGameTime():getTimeOfDay()
        return bodyCount(gid) == 3 and allStanding(gid) and now >= 7 and now < 22.9
    end
end

-- Danger thresholds as read now (LK05-T14 options; previous values when an option is missing).
local function thresholds()
    local E = LK()
    local D, A, Df, Zm, En = E.Decisions, E.Alert, E.Defense, E.Zombies, E.Encounters
    local parts = { "zombie alert " .. tostring(E.Config.zombieAlertDistance()) }
    parts[#parts + 1] = "reach " .. A.reach() .. ", shout " .. A.shoutRadius("zombie")
    parts[#parts + 1] = "flee " .. D.fleeDist() .. "/" .. D.fleeDistAfraid() .. ", retreat " .. D.retreatDist()
        .. ", reinforcements " .. D.helpRadius()
    if Zm ~= nil and Zm.engageRange ~= nil then parts[#parts + 1] = "engage " .. Zm.engageRange() end
    if Df ~= nil and Df.radii ~= nil then
        local r, rz = Df.radii()
        local w, h = Df.ratios()
        parts[#parts + 1] = string.format("defense %d (zombies %d), withdraw %d hold %d", r, rz, w, h)
    end
    if En ~= nil and En.radii ~= nil then
        local hz, hs, mz, ms = En.radii()
        parts[#parts + 1] = string.format("warnings home %d/%d group %d/%d", hz, hs, mz, ms)
    end
    return table.concat(parts, ", ")
end

local function fearOf(gid)
    local out = {}
    for _, mid in ipairs(sortedMids(gid)) do
        local n = Dec().needsOf(gid, mid)
        out[#out + 1] = mid .. " " .. tostring(n and n.fear or "?")
    end
    return table.concat(out, ", ")
end

RST.suite("lk.alert", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("alert raised once by a zombie near the home, cry, members alerted, back to the routine", function(t)
        local E, gid = makeGroup(t, "RST alert")
        local said = RST.PeerChecks.recordSpeech(t)   -- E01-T16: the cry heard by the other clients
        local raisedBefore = E.Alert.stats.raised
        local criesBefore = E.Alert.stats.cries
        local viewKey = gid .. "-" .. tostring(getTimestampMs())
        -- LK05-T08 (E01-T16): the cry counters of every client noted before the zombie (RST_PeerChecksH.lua).
        RST.Steps.ask(t, "lk.alert.view", { phase = "begin", key = viewKey }, { target = "all", timeoutMs = 10000 },
            function(t1)
            t1:waitUntil(ready(gid), BODIES_MS, function(t2)
                measure("members before: " .. describe(gid))
                local first = E.Bodies.find(memberNpcs(gid)["m-1"])
                local zombie, removeZombie = K.spawnVanillaInView(t2, first, 3, 6)
                measure(string.format("zombie created at %.1f,%.1f,%d", zombie:getX(), zombie:getY(),
                    math.floor(zombie:getZ())))
                t2:waitUntil(function() return Al().get(gid) ~= nil end, ALERT_MS, function(t3)
                    local a = Al().get(gid, Dec().currentMinute())
                    measure(string.format("alert raised: %s %s %s last seen at %d,%d,%d, level %d, spotter %s", a.id,
                        a.kind, a.label, a.x, a.y, a.z, a.level, tostring(a.spotter)))
                    local st = Al().stats
                    local V = E.AlertView
                    measure(string.format("cry: %d cry, %d line(s), %d world sound(s) of radius %d; voice %s (%s)",
                        st.cries, st.barks, st.noises, Al().shoutRadius(a.kind) or 0,
                        V and V.last and V.last.s or "not played here", V and V.last and (V.last.body and "body"
                        or "free emitter") or "-"))
                    t3:eq("zombie", a.kind, "kind of the alert")
                    t3:ok(st.cries >= 1, "no cry")
                    t3:waitUntil(function() return allAlerted(gid) end, MEMBERS_MS, function(t4)
                        measure("members alerted: " .. describe(gid))
                        for _, npc in pairs(memberNpcs(gid)) do
                            t4:eq("guard", E.Senses.vigilanceOf(npc), npc .. " vigilance during the alert")
                        end
                        -- LK05-T08 (E01-T16): every client sees the members turned toward the last known position.
                        local facing = {}
                        for _, npc in pairs(memberNpcs(gid)) do
                            facing[#facing + 1] = { npc = npc, x = a.x, y = a.y }
                        end
                        RST.Steps.ask(t4, "lk.facing", { bodies = facing, maxDeg = FACING_DEG },
                            { target = "all", timeoutMs = 10000 }, function(t4b)
                            removeZombie()
                            measure("zombie removed")
                            t4b:waitUntil(function() return Al().get(gid) == nil and noneAlerted(gid) end, CALM_MS,
                                function(t5)
                                    measure(string.format("calm: alerts raised during the run %d; members %s",
                                        Al().stats.raised - raisedBefore, describe(gid)))
                                    t5:eq(1, Al().stats.raised - raisedBefore, "alerts raised for one zombie")
                                    -- E01-T16: the cry bubble reached the other clients that heard it, and the requester.
                                    local cries = Al().stats.cries - criesBefore
                                    RST.PeerChecks.checkSpeech(t5, said, function(t6)
                                        -- requester: dedicated server only (solo: the authority's own speech view).
                                        local who = (type(isServer) == "function" and isServer()) and "requester" or {}
                                        RST.Steps.ask(t6, "lk.speech.seen", { lines = said },
                                            { target = who, timeoutMs = RST.PeerChecks.SPEECH_MS }, function(t7)
                                                -- LK05-T08: the "Hey!" voice played once per cry by every client.
                                                RST.Steps.ask(t7, "lk.alert.view", { phase = "end", key = viewKey,
                                                    cries = cries }, { target = "all", timeoutMs = 10000 })
                                            end)
                                    end)
                                end, "alert not closed or routine not resumed")
                        end)
                    end, "members not all alerted")
                end, "alert not raised by the zombie")
            end, "group members not materialized and standing")
        end)
    end)

    s.test("a crowd of zombies beyond the alert distance leaves the group in its routine", function(t)
        local C = LK() and LK().Config
        local limit = C and C.zombieAlertDistance and C.zombieAlertDistance()
        if limit == nil then t:skip("option LivingKnox.ZombieAlertDistance missing (sandbox-options.txt not loaded)") end
        local crowd = false
        -- CROWD fake zombies seen around the member, 2 to 16 squares beyond the alert distance; fake online ids.
        local function addCrowd(per, _, body)
            if not crowd then return per end
            local base = per or { ms = 0, age = 0, nz = 0, seen = 0, heard = 0, p = {}, z = {}, n = {} }
            local out, rows = {}, {}
            for k, v in pairs(base) do out[k] = v end   -- copy: the perception given may be kept by its owner
            -- Real zombies dropped: a zombie of the world wandering within the alert distance would raise a legitimate
            -- alert (seen in game on 2026-10-12: one alert by a real zombie 7 squares away).
            local bx, by, bz = body:getX(), body:getY(), math.floor(body:getZ())
            for i = 1, CROWD do
                local d = limit + 2 + (i % 15)
                local a = i * 2 * math.pi / CROWD
                rows[#rows + 1] = { o = 900000 + i, x = math.floor(bx + d * math.cos(a)),
                    y = math.floor(by + d * math.sin(a)), z = bz, a = 1, s = true, h = false, d = d }
            end
            out.z, out.p, out.stale = rows, {}, false
            return out
        end
        local E, gid = makeGroup(t, "RST crowd", addCrowd)
        local raisedBefore = E.Alert.stats.raised
        t:waitUntil(ready(gid), BODIES_MS, function(t2)
            measure("thresholds: " .. thresholds())
            measure("members before the crowd: " .. describe(gid) .. "; fear " .. fearOf(gid))
            crowd = true
            local start = getTimestampMs()
            local alerted, threatened, defended = 0, 0, 0
            t2:waitUntil(function()
                if Al().get(gid) ~= nil then alerted = alerted + 1 end
                for _, npc in pairs(memberNpcs(gid)) do
                    local st = Dec().get(npc)
                    if st ~= nil and st.rule == "threat" then threatened = threatened + 1 end
                end
                if E.Defense ~= nil and E.Defense.get ~= nil and E.Defense.get(gid) ~= nil then
                    defended = defended + 1
                end
                return getTimestampMs() - start >= CROWD_HOLD_MS
            end, CROWD_HOLD_MS + 10000, function(t3)
                crowd = false
                measure(string.format("crowd: %d s with %d zombies %d to %d squares away: alerts raised %d, alert "
                    .. "seen %d, threat behaviours seen %d, defense seen %d; members %s; fear %s",
                    math.floor(CROWD_HOLD_MS / 1000), CROWD, limit + 2, limit + 16, Al().stats.raised - raisedBefore,
                    alerted, threatened, defended, describe(gid), fearOf(gid)))
                t3:eq(0, Al().stats.raised - raisedBefore, "alerts raised by zombies beyond the alert distance")
                t3:eq(0, alerted, "alert seen while only zombies beyond the alert distance were perceived")
                t3:eq(0, threatened, "threat behaviours caused by zombies beyond the alert distance")
                t3:eq(0, defended, "home defense started by zombies beyond the alert distance")
                for _, mid in ipairs(sortedMids(gid)) do
                    local n = Dec().needsOf(gid, mid)
                    t3:ok(n ~= nil and (n.fear or 0) < Dec().CFG.NEED_HIGH.fear, mid .. " fear rose")
                end
            end, "crowd phase not finished")
        end, "group members not materialized and standing")
    end)
end)
