--[[
rs.radiomodule - the "Transmit" module of the vanilla radio window (E06-T02). Client side only (solo or MP
client): the window, the module and the received lines live in the client Lua state.

rs.radiomodule (tag "client", memory only: radio items made by instanceItem, never added to a container or to the
world; windows built with ISRadioWindow:new + instantiate, never added to the UI manager)
    - a new radio window gets the module once, last, with its translated title, around the vanilla modules;
    - presence by radio type through the real ISRadioWindow:readFromObject: two-way walkie-talkies (hand), the
      manpack radio (back) and HAM radios show the module when on with the microphone open; receivers
      (Base.RadioBlack, Base.RadioRed) never do;
    - turning the radio off or muting the microphone hides the module at the next frame of the window
      (RS_RadioModule.sync), turning it back on shows it again;
    - world radio (IsoObject) and car radio (VehiclePart): the module reads only the DeviceData of the device, so a
      HAM DeviceData shows it and a receiver does not; a device that is neither a Radio, an IsoWaveSignal nor a
      VehiclePart is refused with the server's "NoRadio" text. Sending from a real placed radio or car radio
      (microphone range, seat, server checks: E06-T03) is the visual protocol (docs/annexes/tests/tests-en-jeu.md);
    - the text field gives the keyboard back when the window closes.

rs.radiomodule.world (tags "client" and "world": solo on a save named rstest*; skipped on an MP client, where items
cannot be given)
    - a walkie-talkie given to the player and held in the main hand, turned on, opens the real window
      (ISRadioWindow.activate): the module shows once the window has drawn (t:waitUntil), hides when the
      microphone is muted, shows again when it is opened, and closing the window releases the keyboard.
    Cleanup: the window is closed, the walkie-talkie removed (RST.Fixtures.giveItem).
    - (solo, bridge running) Enter in the field of the real window sends to Walt on the frequency of this game: field
      emptied, keyboard released, input greyed while waiting, answer in the two last lines, input back after.

Solo:      RST.run("rs.radiomodule") (memory suite); RST.run({ suite = "rs.radiomodule", tags = { "client", "world" } })
MP client: RST.run("rs.radiomodule") (the world suite is skipped there).
]]

require "RST/RST"

local TWO_WAY = { "Base.WalkieTalkie1", "Base.WalkieTalkie2", "Base.WalkieTalkie3", "Base.WalkieTalkie4",
    "Base.WalkieTalkie5", "Base.WalkieTalkieMakeShift", "Base.ManPackRadio", "Base.HamRadio1", "Base.HamRadio2" }
local RECEIVERS = { "Base.RadioBlack", "Base.RadioRed" }
local HELD = "Base.WalkieTalkie3"

local function client(t)
    if type(isServer) == "function" and isServer() then
        t:skip("the radio window and its module are client UI (not loaded on a server)")
    end
    local ok, Module = pcall(require, "RadioSurvivor/RS_RadioModule")
    t:ok(ok and type(Module) == "table", "RadioSurvivor/RS_RadioModule is not loaded on this side")
    t:ok(ISRadioWindow ~= nil, "ISRadioWindow missing")
    return Module, Module.Talk
end

local function player(t)
    local p = t.ctx and t.ctx.player or getPlayer()
    t:ok(p ~= nil, "no player")
    return p
end

-- Radio window in memory: built like ISRadioWindow.activate, never shown.
local function newWindow(p)
    local w = ISRadioWindow:new(100, 100, 250 + getCore():getOptionFontSizeReal() * 50, 500, p)
    w:initialise()
    w:instantiate()
    return w
end

-- Radio item in memory, on (raw: no square, no battery check) with the microphone open.
local function newRadio(t, fullType)
    local item = instanceItem(fullType)
    t:ok(item ~= nil and instanceof(item, "Radio"), "instanceItem(" .. fullType .. ") is not a Radio")
    local data = item:getDeviceData()
    data:setTurnedOnRaw(true)
    data:setMicIsMuted(false)
    return item, data
end

local function releaseOnExit(t, entry)
    t:defer(function()
        if entry:isFocused() then entry:unfocus() end
    end, "unfocus the text field")
end

RST.suite("rs.radiomodule", { tags = { "client" } }, function(s)
    s.test("module added once, last, with its translated title", function(t)
        client(t)
        local w = newWindow(player(t))
        local record = w.rsTalkRecord
        t:ok(record ~= nil, "no module record on a new ISRadioWindow")
        t:ok(w.modules[#w.modules] == record, "the module is not the last one")
        t:ok(#w.modules > 1, "vanilla modules missing")
        local count = 0
        for _, m in ipairs(w.modules) do
            if m.element.subpanel and m.element.subpanel.Type == "RS_RadioModule" then count = count + 1 end
        end
        t:eq(1, count, "number of Transmit modules")
        t:eq(getText("IGUI_RadioSurvivor_Module"), record.element.titleText, "title")
        t:ne("IGUI_RadioSurvivor_Module", record.element.titleText, "title not translated")
        t:ok(record.element.subpanel.entry.javaObject ~= nil, "text field not instantiated")
    end)

    s.test("two-way radios show it, receivers do not", function(t)
        client(t)
        local p = player(t)
        local w = newWindow(p)
        for _, fullType in ipairs(TWO_WAY) do
            local item = newRadio(t, fullType)
            w:readFromObject(p, item)
            t:ok(w.rsTalkRecord.enabled == true, fullType .. ": module hidden on a two-way radio")
        end
        for _, fullType in ipairs(RECEIVERS) do
            local item = newRadio(t, fullType)
            w:readFromObject(p, item)
            t:ok(w.rsTalkRecord.enabled ~= true, fullType .. ": module shown on a receiver")
        end
        t:note(#TWO_WAY .. " two-way radios, " .. #RECEIVERS .. " receivers")
    end)

    s.test("off or muted hides it at the next frame", function(t)
        local Module = client(t)
        local p = player(t)
        local w = newWindow(p)
        local item, data = newRadio(t, HELD)
        w:readFromObject(p, item)
        local record = w.rsTalkRecord
        t:ok(record.enabled, "shown when on")
        data:setTurnedOnRaw(false)
        Module.sync(w)
        t:ok(not record.enabled and not record.element:isVisible(), "still shown when off")
        data:setTurnedOnRaw(true)
        Module.sync(w)
        t:ok(record.enabled and record.element:isVisible(), "not shown again when on")
        data:setMicIsMuted(true)
        Module.sync(w)
        t:ok(not record.enabled, "still shown with the microphone muted")
    end)

    s.test("world radio and car radio: DeviceData decides, unknown device refused", function(t)
        local _, Talk = client(t)
        local p = player(t)
        local w = newWindow(p)
        local element = w.rsTalkRecord.element
        local _, ham = newRadio(t, "Base.HamRadio1")
        local _, receiver = newRadio(t, "Base.RadioBlack")
        local device = {}
        t:ok(element:readFromObject(p, device, ham, "IsoObject") == true, "HAM radio placed in the world: hidden")
        t:ok(element:readFromObject(p, device, ham, "VehiclePart") == true, "HAM car radio: hidden")
        t:ok(element:readFromObject(p, device, receiver, "VehiclePart") ~= true, "car receiver: shown")
        t:eq(getText("IGUI_RadioSurvivor_Reject_NoRadio"), Talk.problem(p, device), "refusal of a non-item device")
    end)

    s.test("closing the window releases the keyboard", function(t)
        client(t)
        local p = player(t)
        local w = newWindow(p)
        local item = newRadio(t, HELD)
        w:readFromObject(p, item)
        local entry = w.rsTalkRecord.element.subpanel.entry
        releaseOnExit(t, entry)
        entry:focus()
        t:ok(entry:isFocused(), "the text field did not take the focus")
        w:close()
        t:ok(not entry:isFocused(), "text field still focused after ISRadioWindow:close")
    end)
end)

RST.suite("rs.radiomodule.world", { tags = { "client", "world" }, testTimeoutMs = 30000, timeoutMs = 240000 }, function(s)
    s.test("held walkie-talkie: real window shows, hides and releases", function(t)
        client(t)
        if type(isClient) == "function" and isClient() then
            t:skip("items are given by the authority: solo only")
        end
        require "RST/RST_Fixtures"
        local p = player(t)
        local item = RST.Fixtures.giveItem(t, p, HELD)[1]
        p:setPrimaryHandItem(item)
        local data = item:getDeviceData()
        data:setTurnedOnRaw(true)
        data:setMicIsMuted(false)
        local w = ISRadioWindow.activate(p, item)
        t:defer(function() if w:isVisible() then w:close() end end, "close the radio window")
        local record = w.rsTalkRecord
        local entry = record.element.subpanel.entry
        releaseOnExit(t, entry)
        local function shown() return record.enabled and record.element:isVisible() and w:isVisible() end
        t:waitUntil(shown, 5000, function(t2)
            data:setMicIsMuted(true)
            t2:waitUntil(function() return not record.element:isVisible() end, 5000, function(t3)
                data:setMicIsMuted(false)
                t3:waitUntil(shown, 5000, function(t4)
                    entry:focus()
                    t4:ok(entry:isFocused(), "the text field did not take the focus")
                    w:close()
                    t4:ok(not entry:isFocused(), "text field still focused after closing the window")
                end, "module not shown again with the microphone open")
            end, "module still shown with the microphone muted")
        end, "module not shown in the real window")
    end)

    -- E06-T02 in game: Enter in the text field of the module sends the sentence to Walt (frequency of this game), the
    -- field empties and gives the keyboard back at once, the input is greyed while the answer is awaited, the answer
    -- shows in the two last lines of the module, then the input comes back. Solo with the bridge running (--offline
    -- is enough: "Walt, hors ligne...").
    s.test("Enter sends to Walt, keyboard released, answer in the two last lines (solo, bridge)", function(t)
        local _, Talk = client(t)
        require "RST/RST_RSHelpers"
        local R = RST.RSHelpers
        R.solo(t)
        local P = require "RadioSurvivor/RS_Personas"
        local khz = P.served("walt")[1]
        if khz == nil or P.get("walt").state ~= "active" then t:skip("walt is not an active voice") end
        local p = player(t)
        local item = R.radioInHand(t, p, "Base.WalkieTalkie5", khz)
        local heard = R.hear(t)
        local w = ISRadioWindow.activate(p, item)
        t:defer(function() if w:isVisible() then w:close() end end, "close the radio window")
        local record = w.rsTalkRecord
        local panel = record.element.subpanel
        local entry = panel.entry
        releaseOnExit(t, entry)
        local phrase = R.language() == "FR" and "Walt, tu m'entends ?" or "Walt, do you copy?"
        t:waitUntil(function() return record.enabled and record.element:isVisible() and Talk.busyReason() == nil end,
            20000, function(t2)
            entry:focus()
            entry:setText(phrase)
            local sentAt = getTimestampMs()
            entry.onCommandEntered()
            t2:eq("", entry:getText(), "text field not emptied after Enter")
            t2:ok(not entry:isFocused(), "keyboard not given back after Enter")
            t2:ok(Talk.busyReason() ~= nil, "input not greyed while the answer is awaited")
            t2:note("greyed: " .. tostring(Talk.busyReason()))
            t2:waitUntil(function()
                for _, line in ipairs(R.words(heard, khz, sentAt)) do
                    if line ~= phrase then return line end
                end
                return nil
            end, 90000, function(t3, line)
                t3:note("answer after " .. tostring(getTimestampMs() - sentAt) .. " ms: " .. line)
                local shown = false
                for _, l in ipairs(Talk.lastLines(khz)) do if l == line then shown = true end end
                t3:ok(shown, "answer not in the last lines of the module")
                t3:waitUntil(function() return Talk.busyReason() == nil end, 20000, function(t4)
                    t4:note("input back " .. tostring(getTimestampMs() - sentAt) .. " ms after the sentence")
                end, "input still greyed 20 s after the answer")
            end, "no answer of Walt within 90 s (is the bridge running?)")
        end, "module not shown or input still greyed (previous sentence) within 20 s")
    end, { timeoutMs = 150000 })
end)
