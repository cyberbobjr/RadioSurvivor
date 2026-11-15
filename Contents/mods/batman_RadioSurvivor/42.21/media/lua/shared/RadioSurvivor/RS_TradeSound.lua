-- Radio Survivor : sound of a trader heard at its landing (E20-T07, ADR D07: approach and departure sound of the
-- arrival mode). The authority decides; each client near the landing plays the sound locally.
-- MP server: command Sound.COMMAND { s = vanilla sound name, x, y, z } sent to every online player within RADIUS tiles
-- (sendServerCommand); the client plays it on a free emitter at the landing. Solo: played directly.
-- Local play: getWorld():getFreeEmitter(x, y, z):playSoundImpl(name, false, nil) (never (name, nil) on a free
-- emitter: IsoGridSquare overload; knowledge base sounds-and-noise.md, kahlua-lua.md). A name absent from the sound
-- scripts plays nothing and raises no error. ASCII only (Kahlua lexer).
local Const = require "RadioSurvivor/RadioSurvivor_Const"

local Sound = {}

Sound.COMMAND = "trade_sound"
Sound.RADIUS = 100            -- distanceMax of the vanilla small-engine sounds (sounds_object_generator.txt)

-- Plays the sound locally at (x, y, z). Returns true when an emitter took it.
function Sound.playLocal(name, x, y, z)
    if type(name) ~= "string" or not string.match(name, "^[%w_]+$") or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local world = getWorld and getWorld()
    local emitter = world and world:getFreeEmitter(x, y, tonumber(z) or 0)
    if not emitter then return false end
    emitter:playSoundImpl(name, false, nil)
    return true
end

-- Authority: sound `name` heard at point { x, y, z } by the players near it.
function Sound.playAt(name, point)
    if not isServer() then
        return Sound.playLocal(name, point.x, point.y, point.z)
    end
    local list = getOnlinePlayers and getOnlinePlayers()
    if not list then return false end
    local args = { s = name, x = point.x, y = point.y, z = point.z or 0 }
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p and math.abs(p:getX() - point.x) <= Sound.RADIUS and math.abs(p:getY() - point.y) <= Sound.RADIUS then
            sendServerCommand(p, Const.MODULE, Sound.COMMAND, args)
        end
    end
    return true
end

-- Client: command of the authority.
function Sound.onServerCommand(module, command, args)
    if module ~= Const.MODULE or command ~= Sound.COMMAND or type(args) ~= "table" then return end
    Sound.playLocal(args.s, tonumber(args.x), tonumber(args.y), tonumber(args.z))
end

if isClient() and Events and Events.OnServerCommand then Events.OnServerCommand.Add(Sound.onServerCommand) end

return Sound
