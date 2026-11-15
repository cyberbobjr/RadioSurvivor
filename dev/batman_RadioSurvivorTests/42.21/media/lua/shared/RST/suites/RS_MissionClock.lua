--[[
rs.missions.clock - mission delays count game time in a real solo game (E11-T20, review point C27, user decision of
2026-10-21): the countdown stops while the game is paused and runs faster at fast-forward.
An active mission of the real engine lives in an in-memory notebook state (as rs.missions.unclaimed and
rs.missions.solo); its countdown is driven exactly like CA_NotebookServer.tick drives the real ones: on
OnTickEvenPaused, CA_Missions.advance(state, meter()) with a real CA_GameClock.meter. Three windows of real time:
    x1     normal speed (setGameSpeed(1), multiplier 1) for WINDOW_MS: the countdown runs at about one play ms per real
           ms and drops by exactly the world age elapsed times CA_GameClock.msPerHour.
    pause  the vanilla pause, setGameSpeed(0) (Esc menu: MainScreen.lua:1728; pause key: SpeedControlsHandler.lua) for
           PAUSE_MS: remainingMs and the world age do not move although real time passes.
    fast   the vanilla fast-forward FAST (SpeedControlsHandler.lua key FAST_FORWARD_X2 / SpeedControls button
           fasterForward: setGameSpeed(3) then GameTime:setMultiplier(20)) for WINDOW_MS: the countdown runs about
           FAST.multiplier times faster than at x1 over the same real duration (generous tolerance, ratio noted).
           setGameSpeed(3) alone keeps the world at x1: SpeedControls.SetCurrentGameSpeed resets the GameTime
           multiplier to 1 (SpeedControls.java:137); the game speed comes from that multiplier (GameTime.java:476).
Ticks while paused (GameWindow.java:373-391, IngameState.java:1379, 1680): in solo a paused frame skips
states.update, so OnTick does not fire and the RST engine (attached to OnTick in solo) does not step; only
OnTickEvenPaused fires. The pause is therefore measured and ENDED by the suite's own OnTickEvenPaused listener (the
driver): it resumes the game PAUSE_MS of real time after the pause was asked, whatever happens to the test, before
any other work of the frame. The RST waits only start again once the game runs. t:defer puts back the speed and the
multiplier found at the start (never a paused game) and removes the listeners, on success and failure alike.
Tags "world" (the game speed and the world age move): solo only (MP client: getGameSpeed is always 1 and the pause
belongs to the server; dedicated server: no SpeedControls), save named rstest*. Selected by the prefix "rs.missions"
of the campaign solo-rs. The in-memory mission is never saved; CA_Missions.advance only reads the mission's giver
kind ('npc', registered by RadioSurvivor or Living Knox). Outside the game: tests/test_rs_mission_clock_suite.py.
]]

require "RST/RST"

local MISSION_MS = 7200000 -- 2 h of play: far from expiring during the test
local WINDOW_MS, PAUSE_MS = 3000, 3000
local WAIT_MS = 15000
local NORMAL = { speed = 1, multiplier = 1 }
local FAST = { speed = 3, multiplier = 20 } -- SpeedControlsHandler.lua FAST_FORWARD_X2, SpeedControls fasterForward
local X1_RATE_TOLERANCE = 0.5 -- play ms per real ms at normal speed: 1 +/- 0.5
local RATIO_LOW, RATIO_HIGH = 0.5, 1.5 -- fast / x1 ratio within these fractions of FAST.multiplier
local AGE_EPS = 1e-6

local function solo(t)
    if (type(isClient) == "function" and isClient()) or (type(isServer) == "function" and isServer()) then
        t:skip("solo only: in MP the game speed and the pause belong to the server")
    end
    if type(setGameSpeed) ~= "function" or type(getGameSpeed) ~= "function" or getGameSpeed() == 0 then
        t:skip("no speed controls (getGameSpeed() is 0 outside a running solo game)")
    end
end

local function modules(t)
    solo(t)
    local M, Clock = require "CoreAI/CA_Missions", require "CoreAI/CA_GameClock"
    if Clock.hours() == nil then t:skip("no game time (GameTime not ready)") end
    if M.donor("npc") == nil then t:skip("no mission giver 'npc' registered (RadioSurvivor or Living Knox)") end
    return M, Clock
end

local function setSpeed(s)
    setGameSpeed(s.speed)
    getGameTime():setMultiplier(s.multiplier)
end

-- Speed found at the start, never a paused one.
local function currentSpeed()
    local speed = getGameSpeed()
    if speed < 1 then return NORMAL end
    return { speed = speed, multiplier = getGameTime():getTrueMultiplier() }
end

-- In-memory notebook state with one active mission (never saved).
local function activeMission()
    local m = { id = "rst-clock-" .. tostring(RST.now()), npc = "rst-clock-npc", state = "active", revision = 1,
        participants = { rst = { name = "RST" } }, invited = { rst = true }, claimedBy = "", receipts = {},
        rewardType = "Base.Nails", rewardCount = 1, durationMs = MISSION_MS, remainingMs = MISSION_MS }
    local state = { missions = {}, npcs = {}, voiceDonors = {}, outcomes = {}, characters = {} }
    state.missions[m.id] = m
    return state, m
end

--[[ Driver: one OnTickEvenPaused listener (fires paused or not, before GameTime.update of the frame) that
    1. ends a pause it was asked to hold once its real time is over (first, so that nothing below can keep the game
       paused);
    2. counts the play time of the mission like CA_NotebookServer.tick (CA_Missions.advance with a CA_GameClock meter);
    3. records the start and end readings of the current phase.
A second listener on OnTick only counts the frames that reach OnTick (none while paused in solo). ]]
local function newDriver(M, Clock, state, m)
    local d = { meter = Clock.meter(), ticks = 0, error = nil, phase = nil }
    d.meter() -- starts the meter: nothing counted before the test

    local function reading()
        return { ms = m.remainingMs, age = Clock.hours(), real = getTimestampMs(), ticks = d.ticks }
    end

    local function finish(p, r)
        p.finish, p.closed, d.phase = r, true, nil
        if p.onEnd then p.onEnd() end
    end

    d.onPaused = function()
        local p = d.phase
        if p and p.holdUntil and getTimestampMs() >= p.holdUntil then
            finish(p, p.start and reading() or nil)
            p = nil
        end
        local ok, err = pcall(function() M.advance(state, d.meter()) end)
        if not ok and d.error == nil then d.error = tostring(err) end
        if p == nil then return end
        if p.start == nil then
            if p.ready == nil or p.ready() then
                p.start = reading()
                p.frames = 1
            end
        else
            p.frames = p.frames + 1
            if p.ms and getTimestampMs() - p.start.real >= p.ms then finish(p, reading()) end
        end
    end
    d.onTick = function() d.ticks = d.ticks + 1 end

    -- New phase: measured from the first driver frame where ready() holds (always without ready); a window ends ms
    -- of real time after its start; a held pause ends `hold` ms of real time after this call, then onEnd() runs.
    function d.measure(opts)
        local p = { ms = opts.ms, ready = opts.ready, onEnd = opts.onEnd,
            holdUntil = opts.hold and (getTimestampMs() + opts.hold) or nil }
        d.phase = p
        return p
    end

    Events.OnTickEvenPaused.Add(d.onPaused)
    Events.OnTick.Add(d.onTick)
    function d.stop()
        Events.OnTickEvenPaused.Remove(d.onPaused)
        Events.OnTick.Remove(d.onTick)
    end
    return d
end

-- Play ms counted and real ms elapsed over a phase.
local function span(p)
    local drop = p.start.ms - p.finish.ms
    local real = p.finish.real - p.start.real
    return drop, real, p.finish.age - p.start.age
end

local function noDriverError(t, d)
    if d.error then t:fail("CA_Missions.advance raised in the driver: " .. d.error) end
end

-- The countdown follows the world age exactly (whole ms, the meter carries the fraction).
local function followsWorldAge(t, Clock, p, label)
    local drop, _, age = span(p)
    t:near(age * Clock.msPerHour(), drop, 2, label .. ": countdown = world age elapsed x msPerHour")
end

local function closed(p) return function() return p.closed end end

-- Rounded text of a number (Kahlua: no string.format reliance for the report lines).
local function num(v, digits)
    local f = 10 ^ (digits or 0)
    return tostring(math.floor(v * f + 0.5) / f)
end

RST.suite("rs.missions.clock", { tags = { "world" } }, function(s)
    s.test("countdown stopped while paused, faster at fast-forward (E11-T20)", function(t)
        local M, Clock = modules(t)
        local original = currentSpeed()
        local state, m = activeMission()
        local d = newDriver(M, Clock, state, m)
        t:defer(d.stop, "clock driver listeners removed")
        t:defer(function() setSpeed(original) end, "game speed " .. tostring(original.speed) .. " and multiplier "
            .. tostring(original.multiplier) .. " restored")
        setSpeed(NORMAL)
        local x1 = d.measure({ ms = WINDOW_MS })
        t:waitUntil(closed(x1), WAIT_MS, function(t2)
            noDriverError(t2, d)
            local drop, real = span(x1)
            t2:ok(drop > 0, "countdown did not run at normal speed (" .. num(drop) .. " play ms in " .. num(real)
                .. " real ms)")
            followsWorldAge(t2, Clock, x1, "x1")
            local rate1 = drop / real
            t2:near(1, rate1, X1_RATE_TOLERANCE, "play ms per real ms at normal speed")
            t2:note("x1: " .. num(drop) .. " play ms in " .. num(real) .. " real ms (rate " .. num(rate1, 3) .. ")")

            -- Vanilla pause (SpeedControlsHandler.lua): OnTick stops, the driver ends the pause on time.
            local pause = d.measure({ hold = PAUSE_MS, ready = isGamePaused, onEnd = function() setSpeed(NORMAL) end })
            setGameSpeed(0)
            t2:waitUntil(closed(pause), WAIT_MS, function(t3)
                noDriverError(t3, d)
                t3:ok(pause.start ~= nil and pause.finish ~= nil,
                    "the game never paused after setGameSpeed(0) (isGamePaused() stayed false)")
                local pdrop, preal, page = span(pause)
                t3:ok(preal >= PAUSE_MS / 2, "pause too short to prove anything: " .. num(preal) .. " real ms")
                t3:near(0, pdrop, 1, "countdown moved while paused (" .. num(preal) .. " real ms)")
                t3:near(0, page, AGE_EPS, "world age moved while paused")
                t3:note("pause: " .. num(pdrop) .. " play ms counted in " .. num(preal) .. " real ms, "
                    .. tostring(pause.frames) .. " paused frames, OnTick fired "
                    .. tostring(pause.finish.ticks - pause.start.ticks) .. " times")

                setSpeed(FAST)
                local fast = d.measure({ ms = WINDOW_MS, onEnd = function() setSpeed(NORMAL) end })
                t3:waitUntil(closed(fast), WAIT_MS, function(t4)
                    noDriverError(t4, d)
                    local fdrop, freal = span(fast)
                    followsWorldAge(t4, Clock, fast, "fast")
                    local ratio = (fdrop / freal) / rate1
                    t4:note("fast (speed " .. FAST.speed .. ", multiplier " .. FAST.multiplier .. "): " .. num(fdrop)
                        .. " play ms in " .. num(freal) .. " real ms, ratio to x1 " .. num(ratio, 2)
                        .. " (expected about " .. FAST.multiplier .. ")")
                    t4:ok(ratio >= FAST.multiplier * RATIO_LOW and ratio <= FAST.multiplier * RATIO_HIGH,
                        "countdown at fast-forward runs " .. num(ratio, 2) .. " times the x1 rate, expected about "
                        .. FAST.multiplier)
                end, "fast-forward window never closed")
            end, "pause never ended")
        end, "normal speed window never closed")
    end, { timeoutMs = 60000 })
end)
