-- Voice mission `watch` (E20-T14, ADR D10) at the square of the player. Real start path of a voice
-- (RS_MissionVoice.start, sheet with one [mission] of type watch and one place use=target where the player stands),
-- real set-up of the target place (RS_MissionTarget), real engine poll (CA_Missions.observe: the template reads the
-- server copy of the player and the world age), real radio report (RS_MissionVoice.report).
-- The game clock is moved forward by GameTime.setTimeOfDay (world age = nights * 24 + hours since 7:00,
-- GameTime.java:824-827 in 42.22), in steps shorter than the gap the watch tolerates between two readings, with a poll
-- after each step.
-- Steps: report refused at the start; half an hour watched; the player goes AWAY tiles off and half an hour passes:
-- the watch starts again from zero; back at the spot, the whole duration passes: objective met, radio report
-- accepted. The facts seen meanwhile (helicopter, horde) are noted, not required. In-memory state (store whose save
-- does nothing): no notebook state. The player is moved back by the undo of RST.Fixtures.movePlayer.
require 'RST/RST'
require 'RST/RST_Fixtures'
local F = RST.Fixtures

local KHZ = 199900
local HOURS = 1        -- game hours of the test watch
local AWAY = 40        -- tiles east of the spot: beyond the watch radius, the area stays loaded
local STEP = 0.25      -- game hours per step of the clock (below gapHours of CA_MissionConfig)

-- Moves the game clock forward by `hours` in steps, calling poll after each (never across 7:00: the world age would
-- go back).
local function advance(hours, poll)
    local gt = getGameTime()
    local left = hours
    while left > 0 do
        local h = math.min(STEP, left)
        gt:setTimeOfDay(gt:getTimeOfDay() + h)
        poll()
        left = left - h
    end
end

local function near(a, b) return type(a) == 'number' and math.abs(a - b) < 0.05 end

local function factsOf(m)
    local out = {}
    for name, seen in pairs(type(m.facts) == 'table' and m.facts or {}) do
        if seen then out[#out + 1] = name end
    end
    table.sort(out)
    return table.concat(out, ', ')
end

local function run(t)
    if isClient() then t:skip('authority only') end
    local M = require 'CoreAI/CA_Missions'
    local V = require 'RadioSurvivor/RS_MissionVoice'
    local W = require 'CoreAI/CA_MissionWatch'
    local p = F.player(t)
    if not p then t:skip('no target player') end
    local gt = getGameTime()
    if gt:getTimeOfDay() < 7.5 or gt:getTimeOfDay() > 19 then
        gt:setTimeOfDay(8)
        t:note('game clock set to 8:00 so that it can be moved forward by a few hours')
    end
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local sheet = {id = 'rst-voice-watch', name = 'RST Voice', actions = {'say', 'start_mission'}, budgets = {},
        missions = {{id = 'watch', type = 'watch', target = 'post', params = {hours = HOURS}}},
        places = {{id = 'post', label = 'RST post', x = x, y = y, z = z, uses = {'target'}, use = {target = true}}}}
    local state = {missions = {}, npcs = {}, voiceDonors = {}, characters = {}, outcomes = {}}
    state.characters.char1 = {name = 'Tester', contacts = {}, knownMissions = {}}
    local store = {data = state, save = function() return true end}
    local m, why = V.start(store, sheet, 'char1', p, KHZ, 'watch')
    t:ok(m ~= nil, 'watch mission not created: ' .. tostring(why))
    local function poll()
        W.resetForTests() -- no wait between two samplings of the suite
        return M.observe(state, {{player = p, character = 'char1'}}, store)
    end
    poll()
    t:eq({'watch', HOURS, 0, 0}, {m.template, m.hours, m.watched, m.breaks}, 'mission at its start')
    t:eq({nil, 'not_done'}, {V.report(store, sheet, 'char1', p, KHZ)}, 'report before the watch')
    advance(0.5, poll)
    t:ok(near(m.watched, 0.5), 'half an hour at the spot not counted: ' .. tostring(m.watched))
    F.movePlayer(t, p, x + AWAY, y, z, function(t2, origin)
        poll()
        advance(0.5, poll)
        t2:eq({0, 1}, {m.watched, m.breaks}, 'long absence did not start the watch again')
        F.movePlayer(t2, p, origin.x, origin.y, origin.z, function(t3)
            poll()
            t3:eq(false, M.reportReady(m), 'watch done right after coming back')
            advance(HOURS + STEP, poll) -- one step more: timeOfDay is a Java float (rounding of the last digit)
            t3:note('watched ' .. tostring(m.watched) .. ' h, facts: ' .. factsOf(m))
            t3:eq(true, M.reportReady(m), 'whole watch at the spot not counted: ' .. tostring(m.watched))
            local brief = M.voiceBrief(m)
            t3:ok(brief and string.find(brief.job, 'Keep watch', 1, true) ~= nil, 'job not told to the voice')
            t3:eq(true, V.report(store, sheet, 'char1', p, KHZ) == m, 'radio report refused after the watch')
            t3:eq('success', m.state)
        end)
    end)
end

RST.suite("rs.voicewatch", {tags = {"server", "world"}, testTimeoutMs = 120000}, function(s)
    s.test('watch counted in game time at the spot, a long absence starts it again, then the radio report', run)
end)
