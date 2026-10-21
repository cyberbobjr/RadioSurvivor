--[[
Radio Survivor: game clock of the gameplay delays (E11-T20, review point C27, user decision of 2026-10-21).
Mission delays follow game time like vanilla delays: they stop while the game is paused (solo Esc, dedicated server
empty with PauseEmpty: GameTime.update is not called), run faster at speed x2/x3 and while sleeping, and do not run
while the server is stopped (the world age is saved with the world).

Unit: "play ms", the real milliseconds the delay takes at normal speed. A delay of 7 200 000 play ms lasts 2 real hours
at speed x1 whatever the day length of the sandbox, 40 minutes at x3, and nothing while paused. The game time comes
from the world age (GameTime.getWorldAgeHours, game hours) and one game hour lasts getMinutesPerDay() * 60000 / 24
real ms at normal speed (GameTime.java:867, set from the DayLength option by SandboxOptions.applySettings).

getWorldAgeHours is a Java float (GameTime.java:830-834): elapsed time is always the difference of two readings, never
a sum of rounded steps, so no drift builds up. It can go back (setTimeOfDay of an admin, knowledge base
api-42-21.md): a meter then restarts from the new value without counting anything.
Real-time delays (bridge, quotas, request timeouts, cadences, placement retries) keep getTimestampMs.
]]
local Clock = {}

Clock.DEFAULT_MINUTES_PER_DAY = 90 -- SandboxOptions DayLength default 4 = 90 real minutes per game day

-- World age in game hours, nil before the game time exists.
function Clock.hours()
    local gt = getGameTime and getGameTime()
    if gt == nil then return nil end
    local h = gt:getWorldAgeHours()
    if type(h) ~= 'number' or h ~= h then return nil end
    return h
end

-- Real ms of one game hour at normal speed.
function Clock.msPerHour()
    local gt = getGameTime and getGameTime()
    local minutes = gt and gt:getMinutesPerDay()
    if type(minutes) ~= 'number' or minutes <= 0 then minutes = Clock.DEFAULT_MINUTES_PER_DAY end
    return minutes * 60000 / 24
end

-- World age (game hours) reached after `ms` play ms from now; nil without game time.
function Clock.after(ms)
    local h = Clock.hours()
    if h == nil then return nil end
    return h + math.max(0, tonumber(ms) or 0) / Clock.msPerHour()
end

-- Play ms left before the world age `hour` (0 when reached); nil without game time.
function Clock.leftMs(hour)
    local h = Clock.hours()
    if h == nil or type(hour) ~= 'number' then return nil end
    return math.max(0, (hour - h) * Clock.msPerHour())
end

-- New meter: each call returns the whole play ms elapsed since the previous call (the fraction is carried to the next
-- call, so saved delays stay whole numbers). 0 on the first call, without game time, or when the world age went back
-- (the meter then restarts from the new value).
function Clock.meter()
    local last, carry = nil, 0
    return function()
        local h = Clock.hours()
        if h == nil then return 0 end
        if last == nil or h < last then
            last, carry = h, 0
            return 0
        end
        local elapsed = (h - last) * Clock.msPerHour() + carry
        last = h
        local whole = math.floor(elapsed)
        carry = elapsed - whole
        return whole
    end
end

return Clock
