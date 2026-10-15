--[[
RST_PeerChecksLoad - client side of the multiplayer load measure lk.loadmp (LK13-T02), asked by the authority through
RST.Steps. Development mod only. Shared file: it only registers a step handler. Load with:
require "RST/RST_PeerChecksLoad".

Client handler (RST.Steps.on)
    lk.load.local  { action = "start", windowMs }: starts the load measure of THIS machine (LivingKnox.Load.start, the
                   Living Knox subscribers of the client: views, executor, relay...; window windowMs, log lines on);
                   a measure already running is stopped first (its summary is dropped). PASS "started".
                   { action = "stop" }: stops it and answers its summary in data: { side, secs, ticks, perTickMs,
                   tickMaxMs, sentPerSec, sentBytesPerSec, recvPerSec, over = { text, ... } (LivingKnox.Load.check:
                   budgets of the client), lines = { report line, ... } (LivingKnox.Load.lines, at most MAX_LINES) }.
                   FAIL when no measure runs. SKIP when LivingKnox.Load is not loaded here.
Kahlua: no next(), no goto. Every handler is pcall-protected by RST.Steps.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerChecksLoad = RST.PeerChecksLoad or {}
local PLD = RST.PeerChecksLoad
local Steps = RST.Steps

PLD.MAX_LINES = 40

local function Load() return LivingKnox and LivingKnox.Load end

-- Plain copy of a measure summary for the network (numbers, strings and lists only).
function PLD.digest(sum)
    local L = Load()
    local lines = {}
    for i, line in ipairs(L and L.lines(sum) or {}) do
        if i > PLD.MAX_LINES then break end
        lines[#lines + 1] = tostring(line)
    end
    local over = {}
    for _, text in ipairs(sum.over or {}) do over[#over + 1] = tostring(text) end
    return { side = tostring(sum.side), secs = sum.secs, ticks = sum.ticks, perTickMs = sum.perTickMs,
        tickMaxMs = sum.tickMaxMs, sentPerSec = sum.sentPerSec, sentBytesPerSec = sum.sentBytesPerSec,
        recvPerSec = sum.recvPerSec, over = over, lines = lines }
end

Steps.on("lk.load.local", function(args)
    local L = Load()
    if L == nil or type(L.start) ~= "function" then return Steps.skip("LivingKnox.Load is not loaded here") end
    if args.action == "start" then
        if L.active ~= nil then L.stop() end
        local s, why = L.start({ windowMs = tonumber(args.windowMs) or 60000, log = true })
        if s == nil then return Steps.fail("measure not started: " .. tostring(why)) end
        return Steps.pass("started (window " .. tostring(s.windowMs) .. " ms)")
    elseif args.action == "stop" then
        if L.active == nil then return Steps.fail("no measure running here") end
        local sum = L.stop()
        if sum == nil then return Steps.fail("no summary") end
        local d = PLD.digest(sum)
        for _, line in ipairs(d.lines) do print("[LivingKnox] INFO load: " .. line) end
        return Steps.pass(string.format("%.1f s, %d ticks, %.3f ms/tick, max %.1f ms, %d budget(s) over", d.secs or 0,
            d.ticks or 0, d.perTickMs or 0, d.tickMaxMs or 0, #d.over), d)
    end
    return Steps.fail("lk.load.local { action = start | stop }")
end)

return PLD
