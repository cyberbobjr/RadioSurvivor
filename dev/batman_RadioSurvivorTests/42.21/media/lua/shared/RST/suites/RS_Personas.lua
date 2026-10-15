--[[
rs.personas - voice sheets on the authority (E05-T02, server/RadioSurvivor/RS_Personas.lua): bundled sheet installed,
periodic reload, one dynamic radio channel per served frequency, frequency change, states, invalid sheet, conflict;
E05-T08: no voice frequency reaches the clients (channel names hidden from the RadioServerData list, no list command).
Solo only: a channel created by a reload is received by a walkie-talkie held in hand (a line aired on it, OnDeviceText).
Tags "world" and "server": the authority only (dedicated server or solo), on a save named rstest*. Solo:
RST.run({ suite = "rs.personas", tags = { "world", "server" } }); dedicated server:
RST.server({ suite = "rs.personas", tags = { "world", "server" } }) from an admin client (a plain string filter
runs 0 test: default exclusions). Asynchronous run only
(the periodic reload is awaited once, up to RELOAD_MS + 5 s).

The suite writes its own sheet Zomboid/Lua/batman_RadioSurvivor/personas/rstest_probe.txt on the machine of the
authority, on the free frequencies 999.8 and 999.6 MHz. Lua cannot delete a file: the cleanup empties the sheet (an
empty file is a removed voice) and reloads, which removes the channel; the empty file stays. The bundled sheet of
Walt is only read, never changed.
]]

require "RST/RST"
require "RST/RST_Fixtures"

local DIR = "batman_RadioSurvivor/personas"
local PROBE_ID = "rstest_probe"
local PROBE = DIR .. "/" .. PROBE_ID .. ".txt"
local F1, F2 = 999800, 999600
local OLDER_ID = "rstest_probe_older"   -- second probe voice, loaded before the probe (conflict test)
local OLDER = DIR .. "/" .. OLDER_ID .. ".txt"
local MAX_SHEET_KHZ = 999800            -- highest frequency a sheet accepts (RS_Persona.lua: 1.0 to 999.8 MHz)
local HELD_RADIO = "Base.WalkieTalkie5"

local function personas(t)
    if type(isClient) == "function" and isClient() then
        t:skip("voice sheets live on the authority (not loaded on an MP client)")
    end
    local ok, P = pcall(require, "RadioSurvivor/RS_Personas")
    t:ok(ok and type(P) == "table", "RadioSurvivor/RS_Personas is not loaded on this side")
    return P
end

local function manager(t)
    local radio = getZomboidRadio()
    local m = radio and radio:getScriptManager()
    t:ok(m ~= nil, "no RadioScriptManager on this side")
    return m
end

local function writeSheet(t, lines, path)
    path = path or PROBE
    local writer = getFileWriter(path, true, false)
    t:ok(writer ~= nil, "cannot write " .. path)
    for _, line in ipairs(lines) do writer:write(line .. "\n") end
    writer:close()
end

local function probeLines(frequencies, state, id)
    return { "format=1", "id=" .. (id or PROBE_ID), "name=RST probe", "frequencies=" .. frequencies,
        "state=" .. (state or "active"), "", "[prompt]", "Test voice of the rs.personas suite." }
end

local function uuid(P, khz)
    return P.CHANNEL_PREFIX .. PROBE_ID .. "-" .. tostring(khz)
end

-- Channel of the probe in the real script manager, with its frequency checked.
local function checkChannel(t, P, khz)
    local channel = manager(t):getRadioChannel(uuid(P, khz))
    t:ok(channel ~= nil, "no channel " .. uuid(P, khz) .. " in the RadioScriptManager")
    t:eq(khz, channel:GetFrequency(), "frequency of the channel")
    t:eq(PROBE_ID, P.voiceAt(khz), "voice of the frequency")
end

local function cleanup(t, P)
    t:defer(function()
        local writer = getFileWriter(PROBE, true, false)
        if writer then writer:close() end
        P.reload()
        t:ok(P.get(PROBE_ID) == nil, "probe voice still loaded after emptying its sheet")
        local m = manager(t)
        t:ok(m:getRadioChannel(uuid(P, F1)) == nil and m:getRadioChannel(uuid(P, F2)) == nil,
            "probe channel still in the RadioScriptManager")
    end, "empty the probe sheet and remove its channel")
end

RST.suite("rs.personas", { tags = { "world", "server" }, testTimeoutMs = 60000, timeoutMs = 240000 }, function(s)
    s.test("Walt sheet installed and served by a channel", function(t)
        local P = personas(t)
        local reader = getFileReader(DIR .. "/walt.txt", false)
        t:ok(reader ~= nil, "Zomboid/Lua/" .. DIR .. "/walt.txt missing (bundled sheet not installed)")
        reader:close()
        local walt = P.get("walt")
        t:ok(walt ~= nil, "walt.txt not loaded (refused? see [RadioSurvivor] personas: lines of the log)")
        if walt.state == "gone" or walt.state == "dead" then
            t:skip("walt is " .. walt.state .. " in the admin sheet")
        end
        local served = P.served("walt")
        t:ok(#served > 0, "no frequency of walt is served (conflict or frequency taken: see the log)")
        local channel = manager(t):getRadioChannel(P.CHANNEL_PREFIX .. "walt-" .. tostring(served[1]))
        t:ok(channel ~= nil, "no channel for walt")
        t:eq(served[1], channel:GetFrequency(), "frequency of walt's channel")
        t:note("walt " .. walt.state .. " on " .. tostring(served[1]) .. " kHz")
    end)

    s.test("voice frequencies never published to the clients (E05-T08)", function(t)
        local P = personas(t)
        local Const = require "RadioSurvivor/RadioSurvivor_Const"
        t:ok(Const.CMD.FREQUENCIES == nil, "the frequency list command still exists")
        t:ok(Const.talkFrequencies == nil and Const.toAllClients == nil, "a frequency list is still kept or broadcast")
        -- The channel names are what ZomboidRadio.WriteRadioServerDataPacket sends to every client at login.
        local held = P.heldFrequencies()
        t:ok(#held > 0, "no voice holds a frequency")
        for _, khz in ipairs(held) do
            t:ok(getZomboidRadio():getChannelName(khz) == nil, "name of the voice channel on " .. tostring(khz)
                .. " kHz still listed (removeChannelName not applied)")
        end
        t:note(tostring(#held) .. " voice frequencies, no channel name listed")
    end)

    s.test("new sheet picked up by the periodic reload, then frequency and state changed", function(t)
        local P = personas(t)
        cleanup(t, P)
        writeSheet(t, probeLines("999.8"))
        local started = getTimestampMs()
        t:waitUntil(function() return P.isServed(PROBE_ID, F1) end, P.RELOAD_MS + 5000, function(t2)
            t2:note("periodic reload after " .. tostring(getTimestampMs() - started) .. " ms")
            checkChannel(t2, P, F1)
            -- Frequency changed: old channel removed, new one created (a channel frequency is immutable).
            writeSheet(t2, probeLines("999.6"))
            P.reload()
            t2:ok(manager(t2):getRadioChannel(uuid(P, F1)) == nil, "old channel still present after the change")
            checkChannel(t2, P, F2)
            -- silent keeps the channel, gone removes it.
            writeSheet(t2, probeLines("999.6", "silent"))
            P.reload()
            t2:eq("silent", P.get(PROBE_ID).state, "state")
            checkChannel(t2, P, F2)
            writeSheet(t2, probeLines("999.6", "gone"))
            P.reload()
            t2:ok(manager(t2):getRadioChannel(uuid(P, F2)) == nil, "channel of a gone voice still present")
            t2:eq(0, #P.served(PROBE_ID), "frequencies served by a gone voice")
        end, "sheet not loaded by the periodic reload")
    end)

    s.test("invalid sheet keeps the last valid version", function(t)
        local P = personas(t)
        cleanup(t, P)
        writeSheet(t, probeLines("999.8"))
        P.reload()
        checkChannel(t, P, F1)
        writeSheet(t, probeLines("999.7"))
        P.reload()
        t:eq(F1, P.get(PROBE_ID).frequencies[1], "frequency of the voice in service")
        checkChannel(t, P, F1)
    end)

    -- E05-T02 in game: a channel created by a reload (AddChannel after OnLoadRadioScripts) is received by a real
    -- radio held in hand. The probe sheet takes a free frequency the walkie-talkie can tune; one line is aired on it
    -- (RS_RadioServer.air, the queue of the voices' answers) and awaited through OnDeviceText. Solo only.
    s.test("channel created after loading reaches a radio held in hand (solo)", function(t)
        local P = personas(t)
        require "RST/RST_RSHelpers"
        local R = RST.RSHelpers
        R.solo(t)
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        local m = manager(t)
        local probe = instanceItem(HELD_RADIO):getDeviceData()
        local taken = {}
        for i = 0, m:getChannelsList():size() - 1 do taken[m:getChannelsList():get(i):GetFrequency()] = true end
        local others = {}
        for _, id in ipairs(P.ids()) do
            if id ~= PROBE_ID then for _, khz in ipairs(P.frequencies(id)) do others[#others + 1] = khz end end
        end
        local free = nil
        -- A sheet takes 999.8 MHz at most (in-game run of 2026-10-13: the walkie-talkie tunes up to 1000.0 MHz, a
        -- sheet on '1000.0' is refused and no channel is made).
        local top = math.min(probe:getMaxChannelRange(), MAX_SHEET_KHZ)
        for khz = top - top % 200, probe:getMinChannelRange(), -200 do
            local ok = free == nil and not taken[khz] and P.voiceAt(khz) == nil
            for _, other in ipairs(others) do
                if math.abs(other - khz) < P.MIN_GAP_KHZ then ok = false end
            end
            if ok then free = khz end
        end
        t:ok(free ~= nil, "no free frequency within the range of " .. HELD_RADIO)
        cleanup(t, P)
        writeSheet(t, probeLines(string.format("%.1f", free / 1000)))
        P.reload()
        checkChannel(t, P, free)
        R.radioInHand(t, p, HELD_RADIO, free)
        local heard = R.hear(t)
        local text = "RST probe line " .. string.format("%.0f", getTimestampMs())
        local aired = getTimestampMs()
        RS_RadioServer.air(free, { "<fzzt>", text, "<szzt>" })
        t:waitUntil(function()
            for _, h in ipairs(heard) do
                if h.khz == free and string.find(h.text, text, 1, true) then return h end
            end
            return nil
        end, 30000, function(t2, h)
            t2:note("line received on " .. string.format("%.1f", free / 1000) .. " MHz after "
                .. tostring(h.at - aired) .. " ms")
        end, "line of the new channel never received by the radio in hand")
    end)

    -- Conflict between two sheets with fixed frequencies: the voice loaded first keeps the frequency, the newer
    -- sheet loses only that one (RS_Personas.lua, header). Walt is not used any more: his sheet has frequency
    -- ranges since E05-T07, and a fixed frequency of another voice wins over a drawn one (the drawn voice draws
    -- again: in-game run of 2026-10-13, walt moved from 148.4 to 143.8 MHz and the test failed).
    s.test("frequency of an older voice refused to a newer sheet", function(t)
        local P = personas(t)
        cleanup(t, P)
        t:defer(function()
            local writer = getFileWriter(OLDER, true, false)
            if writer then writer:close() end
            P.reload()
            t:ok(P.get(OLDER_ID) == nil, "older probe voice still loaded after emptying its sheet")
        end, "empty the older probe sheet")
        writeSheet(t, probeLines("999.6", nil, OLDER_ID), OLDER)
        P.reload()
        t:eq(OLDER_ID, P.voiceAt(F2), "owner of 999.6 after the first sheet")
        writeSheet(t, probeLines("999.6, 999.8"))
        P.reload()
        t:eq(OLDER_ID, P.voiceAt(F2), "owner of the frequency of the older voice")
        t:eq(1, #P.served(PROBE_ID), "frequencies served by the newer sheet")
        checkChannel(t, P, F1)
    end)
end)
