if isClient() then return end
--[[
Fact source `horde` of a watch (E20-T14, RC_WatchFacts): a large group of the dead near the spot. Authority only.
Read when the watch samples the spot (a participant there, at most every scanMs of the template): the zombies of the
server cell (IsoCell.getZombieList, IsoCell.java:2340 in 42.22: the loaded zombies, which include the area of a
participant standing there) within RADIUS tiles of the spot on the ground plane, any level, at least COUNT of them.
Reanimated players are left out (IsoZombie.isReanimatedPlayer, IsoZombie.java:3700): the bodies of an NPC engine are
people, not the dead.
ASCII only (Kahlua lexer).
]]
local Facts = require 'RadioSurvivorCore/RC_WatchFacts'

local Horde = {line = 'During the watch: a large group of the dead moved nearby.',
    RADIUS = 30, -- tiles around the spot
    COUNT = 10}  -- dead at once: a group

-- Zombies within RADIUS of the spot, counted up to COUNT.
function Horde.count(spot)
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if list == nil then return 0 end
    local n, r2 = 0, Horde.RADIUS * Horde.RADIUS
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local dx, dy = z:getX() - spot.x, z:getY() - spot.y
        if dx * dx + dy * dy <= r2 and not z:isReanimatedPlayer() then
            n = n + 1
            if n >= Horde.COUNT then return n end
        end
    end
    return n
end

function Horde.seen(m, spot)
    return Horde.count(spot) >= Horde.COUNT
end

Facts.register('horde', Horde)

return Horde
