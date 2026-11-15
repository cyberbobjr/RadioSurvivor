if isClient() then return end
--[[
Fact source `helicopter` of a watch (E20-T14, CA_WatchFacts): the vanilla helicopter heard from the spot. Authority
only (solo or server: on an MP client Helicopter.update only plays the sound, Helicopter.java:105-109 in 42.22).
Signature, read in the 42.22 sources: during a pass, Helicopter.update calls WorldSoundManager.addSound(null, x, y, 0,
500, 500) at the position of the aircraft about every 10 s (Helicopter.java:217-218; updated by IsoWorld.update on the
authority, IsoWorld.java:2797), and WorldSound.init fires OnWorldSound(x, y, z, radius, volume, source)
(WorldSoundManager.java:480). The other sounds without source on level 0 have a radius of 600 or 5000
(AmbientStreamManager.java:463-468, 502-504; repeatWorldSounds is never called), so source nil, z 0, radius 500 and
volume 500 together is the helicopter (a mod could imitate it). IsoWorld.helicopter is an instance field without getter
(IsoWorld.java:361): not readable from Lua.
Each such sound is kept in memory with the world age it was heard at (at most MAX, none older than KEEP_HOURS); the
watch counts it when it came at or after the start of its current watch (m.watchFrom) within RANGE tiles of the spot.
ASCII only (Kahlua lexer).
]]
local Facts = require 'CoreAI/CA_WatchFacts'
local Clock = require 'CoreAI/CA_GameClock'

local Heli = {line = 'During the watch: a helicopter flew over.',
    RADIUS = 500, VOLUME = 500, -- world sound of a pass (Helicopter.java:218)
    RANGE = 500,                -- tiles between the spot and the aircraft: heard (the sound reaches 1000 tiles)
    KEEP_HOURS = 1,             -- game hours a sound is kept for the next readings of the watches
    MAX = 32}

local heard = {} -- { x, y, hour }, oldest first (memory only)

function Heli.isHelicopter(z, radius, volume, source)
    return source == nil and z == 0 and radius == Heli.RADIUS and volume == Heli.VOLUME
end

function Heli.onWorldSound(x, y, z, radius, volume, source)
    if not Heli.isHelicopter(z, radius, volume, source) then return end
    local hour = Clock.hours()
    if hour == nil then return end
    heard[#heard + 1] = {x = x, y = y, hour = hour}
    while #heard > Heli.MAX or hour - heard[1].hour > Heli.KEEP_HOURS do table.remove(heard, 1) end
end

function Heli.seen(m, spot)
    local from = m.watchFrom
    if type(from) ~= 'number' then return false end
    local range2 = Heli.RANGE * Heli.RANGE
    for _, s in ipairs(heard) do
        local dx, dy = s.x - spot.x, s.y - spot.y
        if s.hour >= from and dx * dx + dy * dy <= range2 then return true end
    end
    return false
end

Facts.register('helicopter', Heli)
Events.OnWorldSound.Add(Heli.onWorldSound)

return Heli
