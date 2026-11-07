if isClient() then return end
--[[
RadioSurvivorCore: readings of the world shared by RadioSurvivor (RS_Facts) and Living Knox (LK_ObservationTriggers)
(E18-T27, moved from RS_ObservationTriggers). Authority only; plain readings, no state.

    World.hour()         world age in whole game hours, nil without a clock
    World.today()        game day (1 = first day), 1 without a clock
    World.weatherNow()   weather period running now: 'tropical_storm' | 'storm' | 'blizzard', or nil (no fog: almost
                         every morning, its strength depends on the fogQuality graphics option, ClimateManager.java:1307)
    World.gridPower()    global power grid present (true), cut (false), nil without options
                         (SandboxOptions.doesPowerGridExist, no loaded square needed)
]]
local World = {}

function World.hour()
    local gt = getGameTime and getGameTime()
    if not gt or not gt.getWorldAgeHours then return nil end
    local hours = gt:getWorldAgeHours()
    if type(hours) ~= 'number' or hours ~= hours or hours < 0 then return nil end
    return math.floor(hours)
end

function World.today()
    local hour = World.hour()
    if not hour then return 1 end
    return math.floor(hour / 24) + 1
end

function World.weatherNow()
    local cm = getClimateManager and getClimateManager()
    if not cm or not cm.getIsThunderStorming then return nil end
    local wp = cm:getWeatherPeriod()
    if cm:getIsThunderStorming() then
        if wp and wp:isTropicalStorm() then return 'tropical_storm' end
        return 'storm'
    end
    if wp and wp:isRunning() and wp:isBlizzard() then return 'blizzard' end
    return nil
end

function World.gridPower()
    local options = getSandboxOptions and getSandboxOptions()
    if not options or not options.doesPowerGridExist then return nil end
    return options:doesPowerGridExist() == true
end

return World
