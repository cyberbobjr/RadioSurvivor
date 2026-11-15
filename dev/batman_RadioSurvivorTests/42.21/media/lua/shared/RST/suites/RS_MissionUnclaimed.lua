--[[
rs.missions.unclaimed - reward lot of a succeeded mission left unclaimed (E16-T10, user decision of 2026-10-21): kept 7
game days (168 hours of world age), real time alone never counts.
The mission is closed as a success by the real engine (CA_Missions.finish: the deadline unclaimedUntilHour is set by
its release from the world age) on an in-memory notebook state, as rs.missions.solo does; the real M.prune and M.claim
then run on it. Game time: CA_Missions reads the world age only through CA_GameClock.hours (CA_Missions.lua:284, 371);
the suite shifts that function of the shared module ahead for the duration of ONE call to M.prune and puts it back in
the same step (no tick runs meanwhile, so no meter of the game counts the jump; the real GameTime is never changed).
    kept    6 game days later (and 30 real days later) the lot is still there; it is then claimed by the real M.claim
            into the real inventory of the target player (instanceItem, AddItem, sendAddItemToContainer).
    purged  0.1 game hour before the deadline the lot is kept; 0.1 game hour after it, M.prune drops it.
Tags "server" and "world" (the claim fills a real inventory): authority only (solo or dedicated server), save named
rstest*, target player t.ctx.player. Selected by the prefix "rs.missions" of the campaigns solo-rs and mp.
Cleanup: claimed items removed, fact log put back (RST.FactsBook: CA_Missions.finish tells RS_Facts), clock function
restored. Outside the game: tests/test_rs_e14_e16_suites.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_FactsBook"

local REWARD, COUNT = "Base.Antibiotics", 2
local KEPT_HOURS = 168 -- 7 game days, user decision of 2026-10-21
local REAL_DAY_MS = 86400000

local function authority(t)
    if type(isClient) == "function" and isClient() then t:skip("authority only (solo or server), not an MP client") end
end

local function modules(t)
    authority(t)
    local M, Clock = require "CoreAI/CA_Missions", require "CoreAI/CA_GameClock"
    if Clock.hours() == nil then t:skip("no game time (GameTime not ready)") end
    return M, Clock
end

-- Result of fn() while CA_GameClock.hours reads `hours` game hours ahead; the real function is back before returning.
local function ahead(Clock, hours, fn)
    local real = Clock.hours
    Clock.hours = function()
        local h = real()
        return h and h + hours
    end
    local ok, result = pcall(fn)
    Clock.hours = real
    if not ok then error(result, 0) end
    return result
end

-- In-memory notebook state with one mission of a reward lot, closed as a success by the real engine.
local function wonLot(t, M, tag)
    RST.FactsBook.keep(t)
    local state = { missions = {}, npcs = {}, voiceDonors = {}, outcomes = {},
        characters = { rst = { name = "RST", contacts = {}, knownMissions = {} } } }
    local m = { id = "rst-unclaimed-" .. tag .. "-" .. tostring(RST.now()), npc = "rst-unclaimed-npc",
        state = "active", revision = 1, participants = { rst = { name = "RST" } }, invited = { rst = true },
        claimedBy = "", rewardType = REWARD, rewardCount = COUNT, receipts = {}, remainingMs = 60000 }
    state.missions[m.id] = m
    t:eq(true, M.finish(state, m, "success"), "mission not closed as a success")
    return state, m
end

local function rewardItems(inv)
    local out = {}
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == REWARD then out[item:getID()] = item end
    end
    return out
end

RST.suite("rs.missions.unclaimed", { tags = { "server", "world" } }, function(s)
    s.test("lot kept 6 game days, then claimed into the real inventory (E16-T10)", function(t)
        local M, Clock = modules(t)
        local p = RST.Fixtures.player(t)
        if p == nil then t:skip("no target player (t.ctx.player)") end
        local h0 = Clock.hours()
        local state, m = wonLot(t, M, "kept")
        local later = getTimestampMs() + 30 * REAL_DAY_MS
        local dropped = ahead(Clock, 6 * 24, function() return M.prune(state, later) end)
        t:eq(false, dropped, "a mission was dropped 6 game days after the success")
        t:ok(state.missions[m.id] == m, "lot gone 6 game days after the success")
        t:near(h0 + KEPT_HOURS, m.unclaimedUntilHour, 0.01, "deadline of the lot (world age)")

        local inv = p:getInventory()
        local before = rewardItems(inv)
        t:defer(function()
            for id, item in pairs(rewardItems(inv)) do
                if not before[id] then
                    inv:Remove(item)
                    if isServer() then sendRemoveItemFromContainer(inv, item) end
                end
            end
        end, "claimed reward items removed")
        local store = { data = state, save = function() return true end }
        local ok, why = M.claim(store, m, p, "rst", "rst-unclaimed-claim")
        t:eq(true, ok, "claim refused 6 game days after the success: " .. tostring(why))
        local added = 0
        for id in pairs(rewardItems(inv)) do
            if not before[id] then added = added + 1 end
        end
        t:eq(COUNT, added, REWARD .. " items added to the real inventory")
        t:eq("rst", m.claimedBy, "lot reserved by the claim")
        t:note(added .. " x " .. REWARD .. " claimed 6 game days after the success")
    end)

    s.test("lot purged once 7 game days are over (E16-T10)", function(t)
        local M, Clock = modules(t)
        local state, m = wonLot(t, M, "purged")
        local now = getTimestampMs()
        t:eq(false, ahead(Clock, KEPT_HOURS - 0.1, function() return M.prune(state, now) end),
            "lot dropped before 7 game days")
        t:ok(state.missions[m.id] == m, "lot gone before 7 game days")
        t:eq(true, ahead(Clock, KEPT_HOURS + 0.1, function() return M.prune(state, now) end),
            "lot kept past 7 game days")
        t:eq(nil, state.missions[m.id], "lot still listed past 7 game days")
    end)
end)
