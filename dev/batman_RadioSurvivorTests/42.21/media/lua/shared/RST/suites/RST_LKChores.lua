--[[
lk.chores - chores of Living Knox npcs at home (LK05-T04, server/LivingKnox/LK_Routines.lua, behaviour "chore" of
LK_Decisions.lua): by day, members on duty keeper, carer, forager or builder do a small visible activity picked in the
closed list LivingKnox.Routines.CHORES (fire or stove, warm hands, tidy a piece of furniture, look out of a window,
repair at a door or a window, smoke, care for a wounded member, rest sitting), walk to its place, face the object and
play its gesture. Purely visual: no object is modified. Tags "world" and "server": the authority only, on a save named
rstest*, with a target player (t.ctx.player); the suite puts him by itself (RST.Places, solo) next to the fire or
the stove of a house, where the test group gets its home; the Living Knox option Enabled on.
Solo: RST.run({ suite = "lk.chores", tags = "world" }). Asynchronous run
only (about 2 to 4 minutes). Multiplayer: final session.

What is done:
    - a test group "settlers" (one fighter, one handyman, one doctor, one farmer) is created with its home on the
      player's square (the player is hidden from the perception of the group: an unknown player at home is an
      intruder, LK05-T08) and kept out of the expeditions (no stock on the test site: supply objective); its members
      get bodies near the player (LK_Materialize); the clock is moved to 6:59 first
      when it is night or late evening (the world age only moves forward), so that the test runs by day;
    - the places of the chores are surveyed (fires, stoves, furniture) and the items of their containers counted;
    - one member reaches its chore: at its place, facing the object, with the gesture of the chore (or facing out of
      the window for a lookout); every member's chore is printed;
    - a fake zombie is reported to that member (LivingKnox.Senses.perceived replaced for the test): the chore stops
      (standing gesture, routine memory forgotten) and it watches or flees; the fake zombie is removed and the chore
      resumes;
    - the containers and fires of the chore places are counted again: nothing changed.
Every phase prints "[LKC] measure ..." lines; the user checks the gesture on screen. Cleanup (t:defer): perception
restored, bodies removed, test group removed. The clock is not set back.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_LKHelpers"

require "RST/RST_Places"

local K = RST.LKHelpers
local measure = K.measurer("[LKC]")

local BODIES_MS = 60000     -- materialization of the four members
local SURVEY_MS = 20000     -- first decisions (survey of the home and of the chore places)
local CHORE_MS = 150000     -- a member at its chore, gesture played
local THREAT_MS = 15000     -- reaction to the fake zombie
local RESUME_MS = 30000     -- chore resumed after the threat

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

-- Chore reached by npc: routine memory with a chore, final gesture played (lookout: facing out, done).
local function choreDone(npc)
    local m = R().get(npc)
    if m == nil or m.chore == nil then return false end
    local want = R().CHORE_GESTURE[m.chore]
    if want ~= nil then return LK().Anim.gestureOf(npc) == want end
    local e = LK().Directives.get(npc)
    return m.faceV ~= nil and e ~= nil and e.v == m.faceV and e.done
end

-- Items in the containers of the chore places, and lit fires: read only.
local function objectsState(spots)
    local items, lit, objects = 0, 0, 0
    local cell = getCell()
    for _, kind in ipairs({ "fire", "furniture" }) do
        for _, p in ipairs(spots and spots[kind] or {}) do
            local sq = cell:getGridSquare(p.ox, p.oy, p.z)
            local objs = sq ~= nil and sq:getObjects() or nil
            for i = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(i)
                objects = objects + 1
                local c = o:getContainer()
                if c ~= nil then items = items + c:getItems():size() end
                if instanceof(o, "IsoFireplace") and o:isLit() then lit = lit + 1 end
            end
        end
    end
    return string.format("%d object(s), %d item(s), %d lit fire(s)", objects, items, lit)
end

local function describe(gid)
    local g = LK().Groups.get(gid)
    local parts = {}
    for _, mid in ipairs(sortedMids(gid)) do
        local npc = g.members[mid].npc
        local st = Dec().get(npc)
        local m = R().get(npc)
        parts[#parts + 1] = string.format("%s %s %s %s %s", mid, tostring(g.members[mid].duty), tostring(st and st.b),
            tostring(m and m.key), LK().Anim.gestureOf(npc))
    end
    return table.concat(parts, "; ")
end

-- Square to stand on in the player's house next to its fire or stove (ground floor), or nil.
local function fireSpot(p)
    local Pl = RST.Places
    local sq = p:getCurrentSquare()
    if not Pl.inside(sq) then return nil end
    local f = Pl.fireNear(sq, 20)
    return f and Pl.freeNear(f, 3) or nil
end

RST.suite("lk.chores", { tags = { "world", "server" }, testTimeoutMs = 600000, timeoutMs = 900000 }, function(s)
    s.test("chore at home by day, interrupted by a threat, no object modified", function(t)
        local E = LK()
        t:ok(E ~= nil and E.Routines ~= nil and E.Routines.chorePlan ~= nil and E.Decisions ~= nil,
            "LivingKnox.Routines (chores) is not loaded on this side")
        t:ok(E.Groups.ensure(), "group registry not ready")
        -- The suite puts the player in a house with a fire or a stove by itself (RST.Places, solo).
        RST.Places.ensure(t, { name = "house with a fire or a stove (ground floor)", spot = fireSpot,
            building = function(def) return def:isResidential() end }, function(t, sq) -- luacheck: ignore 432
        local home = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        local G = E.Groups
        local g = assert(G.create({ type = "settlers", name = "RST chores", day = G.today(), home = home }))
        local gid = g.id
        if E.Homes and E.Homes.skip then E.Homes.skip(gid) end   -- no furnishing (LK08-T04) on the test site
        for _, spec in ipairs({ { "fighter", "guard" }, { "worker", "handyman" }, { "medic", "doctor" },
            { "worker", "farmer" } }) do
            assert(G.addMember(gid, { role = spec[1], profile = spec[2], female = false, day = G.today() }))
        end
        assert(G.setLeader(gid, "m-1", G.today()))
        -- By day only (chores stop at night); the world age only moves forward (see lk.routines).
        local tod = getGameTime():getTimeOfDay()
        if tod < 7 or tod >= 20 then
            getGameTime():setTimeOfDay(6.98)
            measure(string.format("time of day %.2f: clock set to 6:59 first", tod))
        end
        -- The target player stands in the home: an unknown player there is an intruder (LK05-T08) and the alert it
        -- raises keeps every member facing him (in-game run of 2026-10-13: alert al-2 "intruder JaredBoles", no chore
        -- in 150 s). He is hidden from the members of the test group, as in lk.alert: only the fake zombie below is
        -- a threat here.
        local perceived = E.Senses.perceived
        local function hidden(id)
            local per = perceived(id)
            if per ~= nil and G.findNpc(id) == gid then per.p = {} end
            return per
        end
        E.Senses.perceived = hidden
        -- No furnishing on the test site, so no crate and an empty stock: the group's objective is "supply" and an
        -- expedition would take a forager away from its chore (campaign MP 2026-10-15: lk-134, forager m-2 at its
        -- chore, left with "trip 1" right after the threat; chore never resumed). The test group stays home.
        local Ex = E.Expeditions
        local tryDepart = Ex and Ex.tryDepart or nil
        if tryDepart ~= nil then
            Ex.tryDepart = function(id, minute)
                if id == gid then return nil, "test group of lk.chores stays home" end
                return tryDepart(id, minute)
            end
        end
        t:defer(function()
            if tryDepart ~= nil then Ex.tryDepart = tryDepart end
            if E.Alert ~= nil and E.Alert.forget ~= nil then E.Alert.forget(gid) end
            E.Senses.perceived = perceived
            local npcs = memberNpcs(gid)
            G.remove(gid)
            for _, npc in pairs(npcs) do
                E.Directives.forget(npc)
                E.Bodies.despawn(npc, true)
            end
        end, "remove group " .. gid)
        t:note("group " .. gid .. " home " .. home.x .. "," .. home.y .. "," .. home.z)
        -- Dedicated server: the players leave the house (solid; campaign MP 2026-10-15, lk.routines: npcs stuck
        -- against them in the hall).
        K.clearHome(t, home, function(tc)
        tc:waitUntil(function()
            local now = getGameTime():getTimeOfDay()
            return bodyCount(gid) == 4 and allStanding(gid) and now >= 7 and now < 21.5
        end, BODIES_MS, function(t2)
            t2:waitUntil(function()
                local live = G.get(gid)
                return live ~= nil and live.posts ~= nil and R().ensureSpots(gid, home) ~= nil
            end, SURVEY_MS, function(t3)
                local posts = G.get(gid).posts
                local spots = R().ensureSpots(gid, home)
                local before = objectsState(spots)
                measure(string.format("places: %d fire(s), %d furniture, %d post(s); objects before: %s",
                    #spots.fire, #spots.furniture, #posts.posts, before))
                Dec().scorePass(nil, nil)
                local npcs = memberNpcs(gid)
                local worker
                t3:waitUntil(function()
                    for _, mid in ipairs(sortedMids(gid)) do
                        if choreDone(npcs[mid]) then
                            worker = npcs[mid]
                            return true
                        end
                    end
                    return false
                end, CHORE_MS, function(t4)
                    local m = R().get(worker)
                    local z = E.Bodies.find(worker)
                    measure(string.format("chore: %s %s, gesture %s, body %.1f,%.1f facing %d, vigilance %s", worker,
                        m.key, E.Anim.gestureOf(worker), z:getX(), z:getY(), math.floor(z:getDirectionAngle()),
                        E.Senses.vigilanceOf(worker)))
                    measure("members: " .. describe(gid))
                    t4:eq("chore", Dec().get(worker).b, "behaviour of the member at its chore")
                    t4:eq("rest", E.Senses.vigilanceOf(worker), "vigilance during a chore")
                    local wx, wy = math.floor(z:getX()) + 3, math.floor(z:getY())
                    E.Senses.perceived = function(id)
                        if id ~= worker then return hidden(id) end
                        return { ms = getTimestampMs(), age = 0, stale = false, nz = 1, seen = 1, heard = 0, p = {},
                            z = { { o = -43, x = wx, y = wy, z = math.floor(z:getZ()), a = 1, s = true, h = false,
                                d = 3 } }, n = {} }
                    end
                    t4:waitUntil(function()
                        local st = Dec().get(worker)
                        return st ~= nil and st.rule == "threat" and not R().GESTURES[E.Anim.gestureOf(worker)]
                    end, THREAT_MS, function(t5)
                        local st = Dec().get(worker)
                        measure("threat: " .. worker .. " " .. st.b .. " (" .. st.why .. "), gesture "
                            .. E.Anim.gestureOf(worker))
                        t5:ok(R().get(worker) == nil, "routine memory kept during the threat")
                        E.Senses.perceived = hidden
                        -- The fake zombie also raised a group alert (LK05-T08, suite lk.alert), which lasts some game
                        -- minutes: closed here, so that the chore resumes at once.
                        if E.Alert ~= nil and E.Alert.calm ~= nil then E.Alert.calm(gid, Dec().currentMinute()) end
                        t5:waitUntil(function()
                            local st2 = Dec().get(worker)
                            return st2 ~= nil and st2.b == "chore" and R().get(worker) ~= nil
                        end, RESUME_MS, function(t6)
                            local m2 = R().get(worker)
                            measure("resumed: " .. worker .. " " .. tostring(m2 and m2.key))
                            local after = objectsState(spots)
                            measure("objects after: " .. after)
                            t6:eq(before, after, "objects of the chore places changed")
                        end, "chore not resumed after the threat")
                    end, "threat ignored during the chore")
                end, "no member reached its chore")
            end, "home not surveyed")
        end, "group members not materialized and standing")
        end)
        end)
    end)
end)
