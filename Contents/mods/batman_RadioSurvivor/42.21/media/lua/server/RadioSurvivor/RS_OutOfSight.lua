-- Radio Survivor : out-of-sight rule and game-hour delay of the radio voices (E20-T05, ADR D06). A voice acts on the
-- world (collects a dead drop, later: an ID card, a trade exchange, a personal item) only where nobody can see it and
-- only after a delay in game hours. One unit, reused by every such feature.
--
-- In view: a connected player (server copies; solo: the local players) within VIEW_TILES on both axes, levels ignored
-- (Chebyshev distance). The game sends a connection the world within relevantRange * 8 tiles on each axis
-- (UdpConnection.isRelevantTo, java 42.22 UdpConnection.java:216-232), relevantRange = clamp(view, 12, 20) / 2 + 2
-- chunks (GameServer.java:2638-2639): 96 tiles at most; VIEW_TILES adds a margin. A square not loaded on the authority
-- is out of view (nobody stands near enough to load it).
-- Delay: game hours (CA_GameClock.hours, world age): stops while paused, runs faster at speed x2/x3 or asleep, does not
-- run while the server is stopped. A player back in view resets it to zero.
--
-- Ports (injected; Sight.engine() binds the game): positions() -> list of {x, y} of the possible witnesses,
-- loaded(x, y, z) -> boolean, hours() -> game hours or nil.
-- Record (saved by the caller with its own state): hiddenSince = game hour the point left everyone's view, nil while
-- seen. ASCII only (Kahlua lexer).
if isClient() then return end
local Clock = require 'CoreAI/CA_GameClock'

local Sight = {}

Sight.VIEW_TILES = 100

function Sight.new(ports)
    local watcher = {}

    function watcher.inView(point)
        if not ports.loaded(point.x, point.y, point.z or 0) then return false end
        for _, p in ipairs(ports.positions()) do
            if math.abs(p.x - point.x) <= Sight.VIEW_TILES and math.abs(p.y - point.y) <= Sight.VIEW_TILES then
                return true
            end
        end
        return false
    end

    -- True once the point has been out of everyone's view for `hours` game hours in a row. Updates record.hiddenSince;
    -- the second result is true when the record changed (the caller saves it).
    function watcher.watch(record, point, hours)
        local now = ports.hours()
        if now == nil then return false, false end
        if watcher.inView(point) then
            if record.hiddenSince ~= nil then
                record.hiddenSince = nil
                return false, true
            end
            return false, false
        end
        -- First pass out of view, or the world age went back (admin clock change): the wait starts now.
        if type(record.hiddenSince) ~= 'number' or now < record.hiddenSince then
            record.hiddenSince = now
            return hours <= 0, true
        end
        return now - record.hiddenSince >= hours, false
    end

    return watcher
end

-- Game ports -------------------------------------------------------------------------------------------------

local function addAlive(out, player)
    if player and not player:isDead() then out[#out + 1] = {x = player:getX(), y = player:getY()} end
end

local function positions()
    local out = {}
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do addAlive(out, players:get(i)) end
    else
        for i = 0, getNumActivePlayers() - 1 do addAlive(out, getSpecificPlayer(i)) end
    end
    return out
end

local function loaded(x, y, z)
    local cell = getCell()
    return cell ~= nil and cell:getGridSquare(x, y, z) ~= nil
end

function Sight.enginePorts()
    return {positions = positions, loaded = loaded, hours = Clock.hours}
end

function Sight.engine()
    return Sight.new(Sight.enginePorts())
end

return Sight
