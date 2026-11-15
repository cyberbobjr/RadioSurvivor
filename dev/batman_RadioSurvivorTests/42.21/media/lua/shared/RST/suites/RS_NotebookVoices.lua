--[[
rs.notebook.voices - voice and listening hours of a known frequency in the Radio tab of the notebook (E06-T07; server
server/RadioSurvivor/RS_RadioLog.lua: f.voice, Log.voiceInfo, command note_read; client RS_RadioHistory.lua and the
Radio tab of RS_NotebookRadio.lua). Through the REAL server path: the requester client sends the real radio commands
("talk", "note_read") and reads its own Radio tab (RST.Steps "rs.talk", "rs.history" of RST_PeerChecksRadio.lua,
"rs.voice.read" and "rs.voice.tab" of RST_PeerChecksVoices.lua).
    voice chosen    a voice of a frequency note (RS_Notes.voices) served in this game, not a group voice; its
                    listening hours are set, in memory, to a window two to four hours after the current game time
                    (the sheet file is untouched; put back at the end).
    no answer       the requester says a sentence on the frequency of the voice with a walkie-talkie: outside its
                    hours the voice stays silent (accepted, no bridge request); the sentence is in the Radio tab, the
                    voice is not (server state and client copy).
    note read       a real note of the voice is given to the requester (OnCreate writes voice and frequency on the
                    authority); the requester sends note_read like the note reader. Then the requester's Radio tab
                    shows the voice on that frequency: second line of the row = voice name, page = name and hours
                    "HH:MM-HH:MM" of the window set above (real notebook window, opened then put back). The second
                    client (MP) does NOT know the voice: its tab has no voice there, its server state neither.
Tags "server" and "world": the authority (solo, or RST.server from an admin client), save rstest*. Solo runs the same
code with the local player only (second-client parts noted). MP: autoclient.py --mp --clients 2 --server-suite
rs.notebook.voices --server-tags world. Cleanup: radio histories of both characters put back as they were (the
frequency of the voice is emptied first so that the checks start from an unknown voice), listening hours put back,
walkie-talkie and note taken back, histories sent again to the clients. Outside the game:
tests/test_rs_notebook_voices_suite.py.
]]

require "RST/RST"
require "RST/RST_ModRadioSurvivor"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_RSHelpers"
require "RST/RST_PeerChecksRadio"
require "RST/RST_PeerChecksVoices"

local PR = RST.PeerRadio
local PV = RST.PeerVoices
local Steps = RST.Steps
local MARK = "RST voices "
local WALKIE = "Base.WalkieTalkie5"
local HOURS_AHEAD_MIN, HOURS_SPAN_MIN = 120, 120

local function onServer() return type(isServer) == "function" and isServer() end

local function minuteOfDay()
    local gt = getGameTime()
    return gt:getHour() * 60 + gt:getMinutes()
end

local function clock(minute)
    return string.format("%02d:%02d", math.floor(minute / 60), minute % 60)
end

-- A voice of a frequency note served in this game (not a group voice), whose note item is its own (an item shared by
-- several voices names one of them, drawn at its creation): def of RS_Notes, its frequency, its sheet.
local function noteVoice(Notes, Personas)
    for _, def in ipairs(Notes.voices()) do
        local sheet = Personas.get(def.voice)
        local khz = Personas.served(def.voice)[1]
        if sheet ~= nil and not sheet.group and khz ~= nil and Personas.voiceAt(khz) == def.voice
            and #Notes.forType(def.type) == 1 then
            return Notes.forVoice(def.voice), khz, sheet
        end
    end
    return nil
end

-- Radio history of the character saved, the frequency khz emptied for the test, the whole history put back at the end
-- and sent again to the player (refresh of its client copy).
local function freshFrequency(t, c, who, khz)
    local saved = RST.deepCopy(RST.radioOf(who.cid))
    t:defer(function()
        RST.setRadio(who.cid, saved)
        c.S.dirty = true
        c.Log.sendAll(who.player)
    end, "radio history of " .. who.label .. " put back")
    local work = RST.deepCopy(saved)
    if work ~= nil then
        local kept = {}
        for _, f in ipairs(work.frequencies or {}) do
            if f.khz ~= khz then kept[#kept + 1] = f end
        end
        work.frequencies = kept
    end
    RST.setRadio(who.cid, work)
    c.S.dirty = true
end

local function serverFrequency(cid, khz)
    for _, f in ipairs(RST.radioOf(cid) and RST.radioOf(cid).frequencies or {}) do
        if f.khz == khz then return f end
    end
    return nil
end

local function has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the radio history lives on the authority (solo or dedicated server), not on an MP client")
    end
    local okC, Const = pcall(require, "RadioSurvivor/RadioSurvivor_Const")
    t:ok(okC and type(Const) == "table" and Const.CMD ~= nil and Const.CMD.NOTE_READ ~= nil,
        "RadioSurvivor_Const (E06-T07) not loaded")
    t:ok(type(RS_RadioServer) == "table", "RadioSurvivor_Server.lua (talk, note_read commands) not loaded on this side")
    local Server = CoreAI and CoreAI.notebookServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (CoreAI.notebookServer)")
    end
    if not Const.isEnabled() then t:skip("sandbox option RadioSurvivor.Enabled is off") end
    local Personas = require "RadioSurvivor/RS_Personas"
    local Notes = require "RadioSurvivor/RS_Notes"
    local c = { Const = Const, Log = require "RadioSurvivor/RS_RadioLog", S = require "RadioSurvivor/RS_State",
        Notes = Notes, Server = Server }
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    c.me = { player = p, name = onServer() and p:getUsername() or Steps.LOCAL, label = "requester" }
    c.me.cid = c.Log.characterOf(p)
    t:ok(type(c.me.cid) == "string", "no notebook character bound to the requester (hello not received)")
    local other = Steps.others(t)[1]
    if other ~= nil and Steps.playerOf(other) ~= nil then
        local player = Steps.playerOf(other)
        c.other = { player = player, name = other, label = "client " .. other, cid = c.Log.characterOf(player) }
        t:ok(type(c.other.cid) == "string", "no notebook character bound to " .. c.other.label)
    else
        t:note("no second client online: the requester alone (solo or one client)")
    end
    c.def, c.khz, c.sheet = noteVoice(Notes, Personas)
    if c.def == nil then t:skip("no voice of a frequency note served in this game") end
    -- Listening hours of the voice: a window that starts two hours from now (silence now, hours known in advance).
    local saved = c.sheet.listen
    t:defer(function() c.sheet.listen = saved end, "listening hours of " .. c.def.voice .. " put back")
    local from = (minuteOfDay() + HOURS_AHEAD_MIN) % 1440
    local to = (from + HOURS_SPAN_MIN) % 1440
    c.sheet.listen = { { from = from, to = to } }
    c.hours = clock(from) .. "-" .. clock(to)
    freshFrequency(t, c, c.me, c.khz)
    if c.other ~= nil then freshFrequency(t, c, c.other, c.khz) end
    return c
end

local n = 0
local function sentence(tag)
    n = n + 1
    return MARK .. tag .. " " .. tostring(ZombRand(1000, 9999)) .. "-" .. n
end

-- The requester's Radio tab, re-read from the server first (like the notebook does when it opens).
local function readTab(t, c, target, page, after)
    Steps.ask(t, "rs.history", { texts = {} }, { target = target, timeoutMs = PR.HISTORY_MS }, function(t2)
        Steps.ask(t2, "rs.voice.tab", { khz = c.khz, page = page }, { target = target, timeoutMs = PR.HISTORY_MS },
            after)
    end)
end

RST.suite("rs.notebook.voices", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 200000 },
    function(s)
    s.test("a sentence left without answer does not make the voice known (E06-T07)", function(t)
        local c = authority(t)
        local radio = RST.RSHelpers.radioInHand(t, c.me.player, WALKIE, c.khz)
        local text = sentence("silence")
        Steps.ask(t, "rs.talk", { args = { text = text, channel = c.khz, itemId = radio:getID() } },
            { target = { c.me.name }, timeoutMs = PR.TALK_MS }, function(t2, res)
                local e = res.by[c.me.name]
                t2:eq("accepted", e and e.data and e.data.command, "sentence on the frequency of " .. c.def.voice
                    .. " (refusal: " .. tostring(e and e.data and e.data.reason) .. ")")
                local f = serverFrequency(c.me.cid, c.khz)
                t2:ok(f ~= nil, "sentence not kept on " .. c.khz .. " kHz (server)")
                t2:eq(nil, f and f.voice, "voice known on the server after a sentence without answer")
                readTab(t2, c, { c.me.name }, false, function(t3, res3)
                    local d = res3.by[c.me.name] and res3.by[c.me.name].data or {}
                    t3:ok(d.row == true, "frequency " .. c.khz .. " missing in the Radio tab")
                    t3:ok(has(d.lines, "said:" .. text), "own sentence missing in the Radio tab")
                    t3:eq(nil, d.voice, "voice shown in the Radio tab after a sentence without answer")
                    t3:eq(nil, d.hours, "listening hours shown after a sentence without answer")
                end)
            end)
    end)

    s.test("a note read shows voice and hours in the reader's Radio tab only (E06-T07)", function(t)
        local c = authority(t)
        local note = RST.Fixtures.giveItem(t, c.me.player, c.def.fullType)[1]
        local md = note:getModData()[c.Notes.MODDATA_KEY]
        t:ok(type(md) == "table" and md.voice == c.def.voice and tonumber(md.khz) == c.khz,
            "note written by OnCreate: " .. RST.render(md) .. ", expected " .. c.def.voice .. " on " .. c.khz)
        Steps.ask(t, "rs.voice.read", { itemId = note:getID() }, { target = { c.me.name }, timeoutMs = PV.READ_MS + 2000 },
            function(t2)
                local f = serverFrequency(c.me.cid, c.khz)
                t2:eq(c.def.voice, f and f.voice, "voice known on the server after the note read")
                if c.other ~= nil then
                    local g = serverFrequency(c.other.cid, c.khz)
                    t2:eq(nil, g and g.voice, c.other.label .. ": voice known on the server")
                end
                readTab(t2, c, "all", true, function(t3, res)
                    for _, e in ipairs(res.list) do
                        local d = e.data or {}
                        if PR.player(t3, e.user) == c.me.player then
                            t3:eq(c.def.voice, d.voice, "requester: voice of the frequency in the Radio tab")
                            t3:ok(type(d.name) == "string" and d.name ~= "", "requester: no voice name")
                            t3:eq(c.hours, d.hours, "requester: listening hours")
                            t3:ok(has(d.lines, "note:" .. c.def.voice), "requester: 'note read' line missing")
                            if d.second ~= nil then
                                t3:eq(d.name, d.second, "requester: second line of the frequency row")
                            else
                                t3:note("requester: notebook pages (RS_NotebookRadio) not loaded: second line not read")
                            end
                            local page = type(d.page) == "string" and d.page or ""
                            t3:ok(string.find(page, c.hours, 1, true) ~= nil, "requester: hours missing on the page: "
                                .. page)
                            t3:ok(type(d.name) == "string" and string.find(page, d.name, 1, true) ~= nil,
                                "requester: voice name missing on the page")
                        else
                            t3:eq(nil, d.voice, "client " .. e.user .. ": voice of another player's note shown")
                            t3:eq(nil, d.hours, "client " .. e.user .. ": listening hours of another player's note")
                        end
                    end
                end)
            end)
    end)
end)
