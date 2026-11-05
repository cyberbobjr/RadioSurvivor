--[[
RadioSurvivorCore: files and heartbeat of the Python bridge (E18-T04, moved from RadioSurvivor_Const, E17-T16).

Exchange files of the queue (RC_Transport) and heartbeat file of the bridge. The folder stays the historical
batman_RadioSurvivor/ until E18-T12 moves it to batman_RadioSurvivorCore/ with the bridge (old folder read during
the transition).

Heartbeat: the bridge writes any answer, error included, at most BRIDGE_REPLY_MS after the request
(bridge/radio_bridge.py: MAX_AGE_S 75 + LLM_BUDGET_S 60) and, while it runs, keeps BRIDGE_ALIVE_FILE fresh
(alive=<getTimestampMs> every 5 s). Bridge seen alive (Bridge.alive): a request waits BRIDGE_TIMEOUT_MS (bound +
margin); bridge absent or silent for ALIVE_STALE_MS (or older bridge without heartbeat): the fallback of each request
goes after its own short delay. The file is read at most every ALIVE_READ_MS. ASCII only (Kahlua lexer).
]]
local Bridge = RC_Bridge or {}
RC_Bridge = Bridge

Bridge.REQUESTS_FILE = "batman_RadioSurvivor/requests.txt"
Bridge.RESPONSES_FILE = "batman_RadioSurvivor/responses.txt"
Bridge.BRIDGE_ALIVE_FILE = "batman_RadioSurvivor/bridge-alive.txt"
Bridge.BRIDGE_REPLY_MS = 135000
Bridge.BRIDGE_TIMEOUT_MS = 150000      -- = RS_Config.REQUEST_TIMEOUT_MS (notebook)
Bridge.NO_BRIDGE_TIMEOUT_MS = 90000    -- radio without bridge: static and NoAnswer refusal
Bridge.ALIVE_STALE_MS = 20000
Bridge.ALIVE_READ_MS = 5000
Bridge.seenMs = nil   -- last heartbeat read (getTimestampMs of the bridge), nil = never seen
local readAt = nil

local function nowMs(now)
    if now then return now end
    -- nil checks, not type() == "function": a Java function or a bench double (lupa userdata)
    return getTimestampMs and getTimestampMs() or 0
end

local function readAlive()
    if not getFileReader then return nil end
    local reader = getFileReader(Bridge.BRIDGE_ALIVE_FILE, false)
    if not reader then return nil end
    local stamp = nil
    local line = reader:readLine()
    while line do
        local v = tonumber(string.match(line, "^alive=(%d+)"))
        if v then stamp = v end
        line = reader:readLine()
    end
    reader:close()
    return stamp
end

-- True when the bridge wrote its heartbeat less than ALIVE_STALE_MS ago (file read at most every ALIVE_READ_MS;
-- force = read now).
function Bridge.alive(now, force)
    now = nowMs(now)
    if force or readAt == nil or now - readAt >= Bridge.ALIVE_READ_MS or now < readAt then
        readAt = now
        Bridge.seenMs = readAlive()
    end
    local seen = Bridge.seenMs
    return seen ~= nil and now - seen <= Bridge.ALIVE_STALE_MS and seen - now <= Bridge.ALIVE_STALE_MS
end

-- Wait of a request to the bridge: shortMs (fallback without bridge) or, bridge alive, at least BRIDGE_TIMEOUT_MS.
function Bridge.waitMs(shortMs, now)
    if Bridge.alive(now) then return math.max(shortMs, Bridge.BRIDGE_TIMEOUT_MS) end
    return shortMs
end

return Bridge
