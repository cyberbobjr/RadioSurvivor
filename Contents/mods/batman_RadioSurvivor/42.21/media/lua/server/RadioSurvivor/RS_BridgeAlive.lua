if isClient() then return end
--[[
Heartbeat of the Python bridge (E17-T16). Authority only (dedicated server or solo). At every OnTickEvenPaused,
Const.refreshTimeout() sets Const.TIMEOUT_MS (wait of the radio requests in RadioSurvivor_Server.lua): the long delay
Const.BRIDGE_TIMEOUT_MS while bridge/radio_bridge.py keeps its file Const.BRIDGE_ALIVE_FILE fresh (it may answer up
to Const.BRIDGE_REPLY_MS after a request), the short Const.NO_BRIDGE_TIMEOUT_MS otherwise (no bridge, bridge stopped
or older bridge without heartbeat). The file is read at most every Const.ALIVE_READ_MS. Kept out of the shared
RadioSurvivor_Const module, which every side requires. ASCII only in this file (Kahlua lexer).
]]
local Const = require "RadioSurvivor/RadioSurvivor_Const"

local B = {}

function B.tick()
    Const.refreshTimeout()
end

Events.OnTickEvenPaused.Add(B.tick)

return B
