--[[
Radio Survivor: per-account rate limit of client commands on a multiplayer server (review points C21, C31).

A modified client can repeat a command every frame; several commands rebuild large state (notebook snapshot, radio
history, list of the bodies of the NPCs in range). Each guarded handler owns a token bucket per account: `capacity`
commands at once, then `perSecond` commands per second. A refused command is dropped silently (no reply, so no
traffic either) and logged once per account and bucket every LOG_EVERY_MS. Normal play stays far below the limits:
the client polls the notebook every 3 s, asks the radio history when it opens the window, and repeats "guardHello"
every 600 frames until it gets the list; a reconnection starts with a full bucket.

Only a multiplayer server limits (isServer()): solo has no other client, and the limit would only get in the way of
the automated tests that send commands faster than a player. Real time (getTimestampMs), never game time: the server
must stay protected while paused.
]]
local RL = {}

RL.LOG_EVERY_MS = 60000
RL.buckets = RL.buckets or {}

local function account(player)
    if player == nil then return "?" end
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return tostring(player)
end
RL.account = account

-- true if the command of this player under `key` may run now; false if it must be dropped.
function RL.allow(player, key, capacity, perSecond)
    if not (isServer and isServer()) then return true end
    local now = getTimestampMs()
    local slot = account(player) .. "|" .. tostring(key)
    local b = RL.buckets[slot]
    if b == nil then
        b = { tokens = capacity, at = now, logged = nil, dropped = 0 }
        RL.buckets[slot] = b
    else
        local elapsed = now - b.at
        if elapsed > 0 then
            b.tokens = math.min(capacity, b.tokens + elapsed * perSecond / 1000)
            b.at = now
        elseif elapsed < 0 then
            b.at = now -- clock moved back: restart from here without granting anything
        end
    end
    if b.tokens >= 1 then
        b.tokens = b.tokens - 1
        return true
    end
    b.dropped = b.dropped + 1
    if b.logged == nil or now - b.logged >= RL.LOG_EVERY_MS then
        print("[RadioSurvivor] rate limit: dropped " .. tostring(b.dropped) .. " command(s) " .. tostring(key)
            .. " from " .. slot:sub(1, #slot - #tostring(key) - 1))
        b.logged = now
        b.dropped = 0
    end
    return false
end

-- Forget every bucket (tests, Lua reload).
function RL.reset()
    RL.buckets = {}
end

RS_RateLimit = RL
return RL
