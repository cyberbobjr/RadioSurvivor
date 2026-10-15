--[[
rs.calls - spontaneous calls of the radio voices (E05-T05, server/RadioSurvivor_Server.lua onEveryHours / airCall) in
a real solo game: a walkie-talkie held by the player listens on Walt's frequency of this game.
    - Walt forced to call at every full hour (call_one_in = 1 and always listening, in memory: the sheet file is not
      touched; every other voice set to call_one_in = 0 so that Walt is the only candidate): the clock is put just
      before the next full hour (GameTime:setTimeOfDay, forward only), the game crosses it and fires EveryHours; the
      call is aired on Walt's frequency (text of the bridge, or the fixed call_text 30 s later without the bridge)
      and heard by the radio in hand.
    - Walt out of its listening hours at the next full hour: no call within CALL_TIMEOUT_MS + 10 s.
The values of every sheet are restored at the end (t:defer). The hourly cap (MaxPerHour, shared with the answers)
and the budget of the voice still apply: a call refused by them is reported as such. The game must run (not paused).
Tags "world" and "server", solo only. RST.run({ suite = "rs.calls", tags = { "world", "server" } }).
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_RSHelpers"

local R = RST.RSHelpers
local VOICE = "walt"
local RADIO = "Base.WalkieTalkie5"

local function setup(t)
    R.solo(t)
    local Const = require "RadioSurvivor/RadioSurvivor_Const"
    if not Const.isEnabled() or not Const.spontaneousCalls() then t:skip("spontaneous calls disabled (sandbox)") end
    local P = require "RadioSurvivor/RS_Personas"
    local sheet = P.get(VOICE)
    if sheet == nil or sheet.state ~= "active" or #P.served(VOICE) == 0 then t:skip(VOICE .. " is not an active voice") end
    local saved = {}
    for _, id in ipairs(P.ids()) do
        local s = P.get(id)
        saved[id] = { call = s.call_one_in, listen = s.listen }
        if id ~= VOICE then s.call_one_in = 0 end
    end
    t:defer(function()
        for id, v in pairs(saved) do
            local s = P.get(id)
            if s then s.call_one_in, s.listen = v.call, v.listen end
        end
    end, "restore call_one_in and listen of the voices")
    sheet.call_one_in, sheet.listen = 1, {}
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player")
    local khz = P.served(VOICE)[1]
    R.radioInHand(t, p, RADIO, khz)
    return { Const = Const, P = P, sheet = sheet, khz = khz, heard = R.hear(t) }
end

-- Puts the clock just before the next full hour and waits for EveryHours; next(t, firedAt).
local function nextHour(t, next)
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

RST.suite("rs.calls", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 }, function(s)
    s.test("a voice forced to call is heard at the next full hour", function(t)
        local c = setup(t)
        nextHour(t, function(t2, firedAt)
            t2:waitUntil(function()
                local words = R.words(c.heard, c.khz, firedAt)
                return #words > 0 and words or nil
            end, c.Const.CALL_TIMEOUT_MS + 30000, function(t3, words)
                t3:note("call heard on " .. R.label(c.khz) .. " MHz after " .. tostring(getTimestampMs() - firedAt)
                    .. " ms: " .. table.concat(words, " / "))
                t3:ok(string.find(table.concat(words, " "), "IGUI_", 1, true) == nil, "translation key aired as is")
            end, "no call heard (hourly cap MaxPerHour or budget reached? bridge pending?)")
        end)
    end)

    s.test("no call outside the listening hours", function(t)
        local c = setup(t)
        local h = getGameTime():getHour()
        local from, to = ((h + 3) % 24) * 60, ((h + 4) % 24) * 60
        c.sheet.listen = { { from = from, to = to } }
        -- A call of the previous test still on the air would be heard here: wait until the channel is free.
        t:waitQuiet(function()
            local channel = c.P.channel(c.khz)
            return channel ~= nil and channel:getAiringBroadcast() == nil
        end, 60000, function(t1)
            nextHour(t1, function(t2, firedAt)
                t2:sleep(c.Const.CALL_TIMEOUT_MS + 10000, function(t3)
                    local words = R.words(c.heard, c.khz, firedAt)
                    t3:eq(0, #words, "call heard out of the listening hours: " .. table.concat(words, " / "))
                    t3:note("listening " .. string.format("%02d:00-%02d:00", (h + 3) % 24, (h + 4) % 24) .. ", hour "
                        .. getGameTime():getHour() .. ": silence")
                end)
            end)
        end, "channel of " .. VOICE .. " still on the air")
    end)
end)
