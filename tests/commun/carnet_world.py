"""Lua doubles of the world for the notebook bench (E26, moved from tests/livingknox/test_observations.py): game clock
of the server (GAME_CLOCK) and climate, power grid and provider presence (WORLD_STUBS). Executed on the server of a
test_carnet.Simulation; shared by the Living Knox and RadioSurvivor tests."""

# Game clock of the server (GameTime.getWorldAgeHours, IsoWorld age in hours) for the E08-T07 triggers; the protocol
# stubs have no world age (the triggers then record nothing, as without a clock).
GAME_CLOCK = r'''
WORLD_HOURS = 0
local baseGameTime = getGameTime
getGameTime = function()
    local gt = baseGameTime()
    gt.getWorldAgeHours = function() return WORLD_HOURS end
    return gt
end
function BODY(id) for _, z in ipairs(ZOMBIES) do if z.id == id then return z end end end
'''


# E08-T08 doubles of the Java world (signatures checked in the decompiled 42.21.0 Java): ClimateManager
# (getIsThunderStorming = running period and (thunder storm or tropical storm), ClimateManager.java:653-655; WeatherPeriod
# flags), SandboxOptions.doesPowerGridExist (SandboxOptions.java:1226-1231), optional provider presence.
WORLD_STUBS = r'''
CLIMATE = {running = false, thunder = false, tropical = false, blizzard = false}
local period = {
    isRunning = function() return CLIMATE.running end,
    isThunderStorm = function() return CLIMATE.thunder end,
    isTropicalStorm = function() return CLIMATE.tropical end,
    isBlizzard = function() return CLIMATE.blizzard end,
}
getClimateManager = function() return {
    getWeatherPeriod = function() return period end,
    getIsThunderStorming = function() return CLIMATE.running and (CLIMATE.thunder or CLIMATE.tropical) end,
} end
GRID = true
local baseOptions = getSandboxOptions
getSandboxOptions = function()
    local options = baseOptions and baseOptions() or {}
    options.doesPowerGridExist = function() return GRID end
    -- SandboxOptions.getOptionByName: nil for an unknown option (Living Knox then reads SandboxVars).
    options.getOptionByName = options.getOptionByName or function() return nil end
    return options
end
PRESENCE = {}
if FAKE_PROVIDER then FAKE_PROVIDER.presence = function(id) return PRESENCE[id] end end
function UNLOAD(id)
    for i, z in ipairs(ZOMBIES) do if z.id == id then table.remove(ZOMBIES, i); return end end
end
'''
