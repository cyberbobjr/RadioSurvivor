--[[
rs.notes.written - a voice whose frequency note and spontaneous call are written in its sheet (E22-T07, ADR D07 of
the voice workshop): [note] text= lines instead of item= and key=, and call= instead of call_text=. Probe sheet
rstest_written.txt (Zomboid/Lua/batman_RadioSurvivor/personas/), on a band no voice of the mod uses, emptied and
unloaded at the end (an empty sheet is refused and dropped by the reload).
    note    the generic handwritten note of the mod (RS_Notes.GENERIC_ITEM) is declared for the probe, with the loot
            lists of its sheet (RS_NotesServer.entries; the vanilla lists themselves are filled at world load only:
            a sheet added during the game reaches them at the next load); a note given to the requester carries,
            written by the authority, the voice, the frequency of this game and the text of the sheet; the requester
            client composes it from the ModData it received with the item (RST.Steps "rs.note.compose" of
            RST_PeerChecksVoices.lua): text with the frequency in place of %1.
    call    every other voice set to call_one_in = 0 in memory (put back at the end), the probe calls at every full
            hour; at the next one, with no bridge answer, the text of call= is aired on its frequency with the
            frequency in place of %1 (lines given to RS_RadioLog.broadcast, wrapped during the test). A running
            bridge writes its own call: run with the bridge stopped.
Tags "world" and "server": the authority (solo, or RST.server from an admin client), save rstest*. Solo:
RST.run({ suite = "rs.notes.written", tags = { "world", "server" } }). MP: autoclient.py --mp --clients 1
--server-suite rs.notes.written --server-tags world. The game must run (not paused) for the call test. The hourly
cap (MaxPerHour) and the budget still apply: a call refused by them fails the call test with that hint.
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_ModRadioSurvivor"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_RSHelpers"
require "RST/RST_PeerChecksVoices"

local R = RST.RSHelpers
local Steps = RST.Steps
local PV = RST.PeerVoices
local PROBE_ID = "rstest_written"
local RANGE = "300.0-309.8"
local CALL = "RST written call on %1, anyone? Over."
local TEXT = { "RST written note", "Listen on %1 MHz" }

local function onServer() return type(isServer) == "function" and isServer() end

local function withFrequency(text, label)
    return (string.gsub(text, "%%1", function() return label end))
end

-- Probe sheet written and loaded; emptied and unloaded at the end. { Const, P, Notes, khz, label }.
local function setup(t)
    if type(isClient) == "function" and isClient() then
        t:skip("voice sheets live on the authority (solo or dedicated server), not on an MP client")
    end
    local Const = require "RadioSurvivor/RadioSurvivor_Const"
    if not Const.isEnabled() then t:skip("sandbox option RadioSurvivor.Enabled is off") end
    local P = require "RadioSurvivor/RS_Personas"
    local Notes = require "RadioSurvivor/RS_Notes"
    local path = P.DIR .. "/" .. PROBE_ID .. ".txt"
    t:defer(function(t2)
        R.writeLines(t2, path, {})
        P.reload()
        t2:ok(P.get(PROBE_ID) == nil, "probe voice still loaded after emptying its sheet")
    end, "empty the probe sheet")
    local lines = { "format=1", "id=" .. PROBE_ID, "name=RST Written", "frequency_range=" .. RANGE, "listen=always",
        "state=active", "call_one_in=1", "call=" .. CALL, "", "[note]" }
    for _, line in ipairs(TEXT) do lines[#lines + 1] = "text=" .. line end
    lines[#lines + 1] = "loot=OfficeDesk:1"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[prompt]"
    lines[#lines + 1] = "Test voice of the rs.notes.written suite."
    R.writeLines(t, path, lines)
    P.reload()
    t:ok(P.get(PROBE_ID) ~= nil, "probe sheet refused (see the personas: lines of the log)")
    local khz = P.served(PROBE_ID)[1]
    t:ok(khz ~= nil, "probe voice serves no frequency in " .. RANGE)
    return { Const = Const, P = P, Notes = Notes, khz = khz, label = Notes.frequencyLabel({ khz = khz }) }
end

RST.suite("rs.notes.written", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 300000 },
    function(s)
    s.test("note written in the sheet: generic item, text and frequency read on the client", function(t)
        local c = setup(t)
        local NotesServer = require "RadioSurvivor/RS_NotesServer"
        local def = c.Notes.forVoice(PROBE_ID)
        t:ok(def ~= nil and def.fullType == c.Notes.GENERIC_ITEM, "probe note not declared on " .. c.Notes.GENERIC_ITEM)
        local listed = false
        for _, e in ipairs(NotesServer.entries()) do
            if e.voice == PROBE_ID and e.fullType == c.Notes.GENERIC_ITEM and e.list == "OfficeDesk" then
                listed = true
            end
        end
        t:ok(listed, "loot list OfficeDesk of the probe missing from RS_NotesServer.entries()")
        local p = RST.Fixtures.player(t)
        t:ok(p ~= nil, "no target player")
        local note = RST.Fixtures.giveItem(t, p, c.Notes.GENERIC_ITEM)[1]
        local md = note:getModData()[c.Notes.MODDATA_KEY]
        local written = table.concat(TEXT, "\n")
        t:ok(type(md) == "table" and md.voice == PROBE_ID and tonumber(md.khz) == c.khz and md.text == written,
            "note written by OnCreate: " .. RST.render(md) .. ", expected " .. PROBE_ID .. " on " .. tostring(c.khz))
        local name = onServer() and p:getUsername() or Steps.LOCAL
        Steps.ask(t, "rs.note.compose", { itemId = note:getID() }, { target = { name }, timeoutMs = PV.READ_MS + 2000 },
            function(t2, res)
                local d = res.by[name] and res.by[name].data or {}
                t2:eq(PROBE_ID, d.voice, "voice of the note on the client")
                t2:eq(c.khz, d.khz, "frequency of the note on the client")
                t2:eq(withFrequency(written, c.label), d.text, "text of the note composed on the client")
                t2:ok(type(d.info) == "string" and string.find(d.info, ">" .. withFrequency(TEXT[2], c.label), 1, true)
                    ~= nil, "layout of the note without its line '" .. withFrequency(TEXT[2], c.label) .. "'")
                t2:note("client reads: " .. tostring(d.text))
            end)
    end)

    s.test("call written in the sheet aired with the frequency", function(t)
        local c = setup(t)
        if not c.Const.spontaneousCalls() then t:skip("spontaneous calls disabled (sandbox)") end
        local saved = {}
        for _, id in ipairs(c.P.ids()) do
            local sheet = c.P.get(id)
            if id ~= PROBE_ID then
                saved[id] = sheet.call_one_in
                sheet.call_one_in = 0
            end
        end
        t:defer(function()
            for id, value in pairs(saved) do
                local sheet = c.P.get(id)
                if sheet then sheet.call_one_in = value end
            end
        end, "restore call_one_in of the voices")
        local Log = require "RadioSurvivor/RS_RadioLog"
        local aired = {}
        local broadcast = Log.broadcast
        Log.broadcast = function(khz, lines, cid)
            if khz == c.khz then aired[#aired + 1] = lines end
            return broadcast(khz, lines, cid)
        end
        t:defer(function() Log.broadcast = broadcast end, "unwrap RS_RadioLog.broadcast")
        R.nextHour(t, function(t2, firedAt)
            t2:waitUntil(function() return aired[1] end, c.Const.CALL_TIMEOUT_MS + 30000, function(t3, lines)
                t3:note("aired on " .. c.label .. " MHz " .. tostring(getTimestampMs() - firedAt) .. " ms after the hour: "
                    .. table.concat(lines, " / "))
                t3:eq(withFrequency(CALL, c.label), lines[2],
                    "call text of the sheet (a running bridge writes its own: run with the bridge stopped)")
            end, "no call aired on " .. c.label .. " MHz (hourly cap MaxPerHour or budget reached?)")
        end)
    end)
end)
