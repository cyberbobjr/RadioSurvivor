--[[
RST_RSHelpers - helpers of the RadioSurvivor solo suites of the development mod (RST.RSHelpers): radio held in hand
and lines heard, files, next full hour. Development mod only. Load with: require "RST/RST_RSHelpers". No side effect at
load time (definitions only).
E21-T11: the notebook helpers live in RST_CarnetHelpers.lua of batman_CoreAITests (RST.CarnetHelpers); the
RadioSurvivor suites reach them here under the same names: R.solo, R.notebook, R.character, R.npcWithFiche,
R.nearestTown, R.place, R.god, R.language, R.select, R.watchRequest, R.talk.

    local R = RST.RSHelpers
    R.radioInHand(t, p, fullType, khz)
                                     radio given (RST.Fixtures.giveItem) and held in the main hand, battery full, on,
                                     microphone open, tuned to khz; the former main hand item is held again at the end
    R.hear(t)                        list of lines heard by any device (OnDeviceText), { khz, text, at }; listener
                                     removed at the end
    R.words(heard, khz, since)       lines of heard on khz since the given time, words only
    R.readLines(path) R.writeLines(t, path, lines)
                                     Zomboid/Lua files (getFileReader / getFileWriter)
    R.label(khz)                     "145.0"
    R.nextHour(t, next)              clock put just before the next full hour (forward only), EveryHours awaited (60 s);
                                     next(t, firedAt)
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_PeerChecks"
require "RST/RST_CarnetHelpers"

RST.RSHelpers = RST.RSHelpers or {}
local R = RST.RSHelpers

-- Notebook helpers of the core test mod, under the names the RadioSurvivor suites use (E21-T11).
local N = RST.CarnetHelpers
for _, name in ipairs({ "solo", "notebook", "character", "npcWithFiche", "nearestTown", "place", "god", "language",
    "select", "watchRequest", "talk" }) do
    R[name] = N[name]
end

function R.radioInHand(t, p, fullType, khz)
    local item = RST.Fixtures.giveItem(t, p, fullType)[1]
    local previous = p:getPrimaryHandItem()
    p:setPrimaryHandItem(item)
    t:defer(function()
        if p:getPrimaryHandItem() == item then p:setPrimaryHandItem(previous) end
    end, "hold the former main hand item again")
    local data = item:getDeviceData()
    t:ok(data ~= nil, fullType .. " has no DeviceData")
    t:ok(khz >= data:getMinChannelRange() and khz <= data:getMaxChannelRange(),
        fullType .. " cannot tune " .. R.label(khz) .. " MHz")
    data:setHasBattery(true)
    data:setPower(1.0)
    data:setTurnedOnRaw(true)
    data:setChannel(khz)
    data:setMicIsMuted(false)
    p:updateEquippedRadioFreq()
    return item, data
end

function R.hear(t)
    local heard = {}
    local function listener(_guid, _codes, _x, _y, _z, line, device)
        if type(line) ~= "string" then
            if line ~= nil and instanceof(line, "ChatMessage") then line = line:getText() else return end
        end
        local khz = nil
        local ok, data = pcall(function() return device:getDeviceData() end)
        if ok and data ~= nil then khz = data:getChannel() end
        heard[#heard + 1] = { khz = khz, text = line, at = getTimestampMs() }
    end
    Events.OnDeviceText.Add(listener)
    t:defer(function() Events.OnDeviceText.Remove(listener) end, "remove the OnDeviceText listener")
    return heard
end

-- Lines of heard on khz since the given time, words only (static "<fzzt>" lines left out).
function R.words(heard, khz, since)
    local out = {}
    for _, h in ipairs(heard) do
        if h.khz == khz and h.at >= (since or 0) and not string.match(h.text, "^%s*<%a+>%s*$") then
            out[#out + 1] = h.text
        end
    end
    return out
end

function R.readLines(path)
    local reader = getFileReader(path, false)
    if not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

function R.writeLines(t, path, lines)
    local writer = getFileWriter(path, true, false)
    t:ok(writer ~= nil, "cannot write Zomboid/Lua/" .. path)
    for _, line in ipairs(lines) do writer:write(line .. "\n") end
    writer:close()
end

function R.label(khz)
    return string.format("%.1f", khz / 1000)
end

-- Puts the clock just before the next full hour (forward only) and waits for EveryHours; next(t, firedAt).
function R.nextHour(t, next)
    local fired = nil
    local function onHour() fired = fired or getTimestampMs() end
    Events.EveryHours.Add(onHour)
    t:defer(function() Events.EveryHours.Remove(onHour) end, "remove the EveryHours listener")
    local gt = getGameTime()
    local tod = gt:getTimeOfDay()
    local target = math.floor(tod) + 0.99
    if tod < target then gt:setTimeOfDay(target) end
    t:waitUntil(function() return fired end, 60000, next, "EveryHours not fired within 60 s (game paused?)")
end

return R
