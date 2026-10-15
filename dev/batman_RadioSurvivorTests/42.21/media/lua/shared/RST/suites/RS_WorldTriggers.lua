--[[
rs.worldtriggers - world triggers of the NPC observations (E08-T08, server/RadioSurvivor/RS_ObservationTriggers.lua)
provoked in a real game. A Living Knox test npc with a notebook fiche stands next to the player (present witness).
    - storm: the vanilla climate is forced into a storm (a modded weather period that starts with its STORM stage);
      the hourly poll (Triggers.hourly, the EveryHours subscriber, called twice here = two game hours of the same
      storm) gives the fiche ONE weather observation.
    - power cut: ElecShutModifier set after today (grid on), one poll, then set to -1 (grid off), two polls: ONE
      power_cut observation. The option and the world event state are restored at the end.
    - helicopter: the vanilla helicopter (testHelicopter, it flies to the player: god mode and invisibility on) is
      heard through its world sound (OnWorldSound, radius and volume 500): ONE helicopter observation.
Note: the real fiches of the test save are witnesses too and keep these observations.
Tags "world" and "server" (authority; the helicopter needs a player). Asynchronous run:
RST.run({ suite = "rs.worldtriggers", tags = { "world", "server" } }).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_RSHelpers"

local R = RST.RSHelpers
local STORM_STAGE, CLEARING_STAGE = 3, 4   -- WeatherPeriod.STAGE_STORM, STAGE_CLEARING (WeatherPeriod.java:40-41)

local function count(Obs, fiche, fact)
    local n, subjects = 0, {}
    for _, item in ipairs(Obs.list(fiche.id)) do
        if item.fact == fact then
            n = n + 1
            subjects[#subjects + 1] = tostring(item.subject) .. "@" .. tostring(item.place) .. " day " .. tostring(item.day)
        end
    end
    return n, table.concat(subjects, ", ")
end

local function witness(t, after)
    if type(isClient) == "function" and isClient() then t:skip("observations live on the authority") end
    R.notebook(t)
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player")
    local Triggers = require "RadioSurvivor/RS_ObservationTriggers"
    local Obs = require "RadioSurvivor/RS_Observations"
    local S = require "RadioSurvivor/RS_State"
    R.god(t, p)
    R.npcWithFiche(t, p, 2, function(t2, id, fiche)
        return after(t2, { Triggers = Triggers, Obs = Obs, S = S, p = p, id = id, fiche = fiche })
    end)
end

-- World event state of the triggers (private notebook state), copied and restored at the end.
local function keepEvents(t, S)
    if type(S.data.worldEvents) ~= "table" then S.data.worldEvents = {} end
    local ev = S.data.worldEvents
    local saved = {}
    for k, v in pairs(ev) do saved[k] = v end
    t:defer(function()
        for k in pairs(ev) do ev[k] = nil end
        for k, v in pairs(saved) do ev[k] = v end
        S.dirty = true
    end, "restore the world events of the triggers")
    return ev
end

RST.suite("rs.worldtriggers", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 400000 }, function(s)
    s.test("a forced storm gives one weather observation per fiche", function(t)
        witness(t, function(t2, c)
            local ev = keepEvents(t2, c.S)
            local cm = getClimateManager()
            t2:defer(function() cm:stopWeatherAndThunder() end, "stop the forced storm")
            cm:stopWeatherAndThunder()
            ev.weather, ev.weatherDay = nil, nil
            -- triggerCustomWeatherStage(STAGE_STORM, d) builds START (1 game hour, no storm flag), STORM, CLEARING
            -- (WeatherPeriod.createSingleStage): the storm begins one game hour later, 2.5 to 10 real minutes with the
            -- usual day lengths (in-game run of 2026-10-13: never within 60 s). A modded period made of the STORM stage
            -- first starts the thunderstorm at the next climate update.
            local wp = cm:getWeatherPeriod()
            t2:ok(wp:startCreateModdedPeriod(true, 0.95, 0), "WeatherPeriod:startCreateModdedPeriod refused")
            wp:createAndAddStage(STORM_STAGE, 2)
            wp:createAndAddStage(CLEARING_STAGE, 1)
            t2:ok(wp:endCreateModdedPeriod(), "WeatherPeriod:endCreateModdedPeriod refused")
            t2:waitUntil(function() return c.Triggers.weatherNow() end, 60000, function(t3, kind)
                c.Triggers.hourly()
                c.Triggers.hourly()
                local n, what = count(c.Obs, c.fiche, "weather")
                t3:eq(1, n, "weather observations of the fiche after two polls: " .. what)
                t3:note("storm '" .. tostring(kind) .. "' -> " .. what)
            end, "the climate never reported a storm (getIsThunderStorming)")
        end)
    end)

    s.test("the grid going off gives one power_cut observation", function(t)
        witness(t, function(t2, c)
            local ev = keepEvents(t2, c.S)
            local options = getSandboxOptions()
            local option = options:getOptionByName("ElecShutModifier")
            local old = option:getValue()
            t2:defer(function() options:set("ElecShutModifier", old) end, "restore ElecShutModifier")
            local today = math.floor(getGameTime():getWorldAgeDaysSinceBegin())
            options:set("ElecShutModifier", today + 30)
            ev.grid, ev.powerCut = nil, nil
            t2:eq(true, c.Triggers.gridPower(), "grid not on with ElecShutModifier = " .. (today + 30))
            c.Triggers.hourly()
            t2:eq(0, (count(c.Obs, c.fiche, "power_cut")), "power_cut while the grid is on")
            options:set("ElecShutModifier", -1)
            t2:eq(false, c.Triggers.gridPower(), "grid still on with ElecShutModifier = -1")
            c.Triggers.hourly()
            c.Triggers.hourly()
            local n, what = count(c.Obs, c.fiche, "power_cut")
            t2:eq(1, n, "power_cut observations after the cut: " .. what)
            t2:note("ElecShutModifier " .. tostring(old) .. " -> " .. (today + 30) .. " -> -1: " .. what)
        end)
    end)

    s.test("the vanilla helicopter gives one helicopter observation", function(t)
        witness(t, function(t2, c)
            keepEvents(t2, c.S)
            local first = nil
            local function onSound(_x, _y, z, radius, volume, source)
                if source == nil and z == 0 and radius == 500 and volume == 500 then first = first or getTimestampMs() end
            end
            Events.OnWorldSound.Add(onSound)
            t2:defer(function() Events.OnWorldSound.Remove(onSound) end, "remove the OnWorldSound listener")
            t2:defer(function() endHelicopter() end, "end the helicopter")
            local started = getTimestampMs()
            testHelicopter()
            t2:waitUntil(function() return (count(c.Obs, c.fiche, "helicopter")) > 0 end, 110000, function(t3)
                local n, what = count(c.Obs, c.fiche, "helicopter")
                t3:eq(1, n, "helicopter observations: " .. what)
                t3:note("first helicopter sound after " .. tostring(first and (first - started)) .. " ms; " .. what)
            end, "no helicopter observation within 110 s (first sound: " .. tostring(first) .. ")")
        end)
    end)
end)
