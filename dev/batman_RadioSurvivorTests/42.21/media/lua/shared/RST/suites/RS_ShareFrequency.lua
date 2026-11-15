--[[
rs.actions.share - action share_frequency of the radio voices (E07-T10, decision of the user 2026-10-18): a voice gives
the frequency of another voice only exceptionally. Server: RS_MissionVoice (executor share_frequency), RS_VoiceBonds
(bond and delays), RS_RadioLog (the voice written in the notebook, E06-T07); client: RS_RadioHistory (copy of the
radio history read by the Radio tab, step "rs.voice.tab" of RST_PeerChecksVoices.lua after "rs.history").

The test voice is a sheet held in memory and read by the REAL parser (RS_Persona.parseLines, as rs.actions.map does),
with actions=say,share_frequency and shares=<target>, the target being a voice really served in this game (active,
not a group voice). The installed sheets are never written: walt.txt of the user's game is edited by the admin and
may lack share_frequency and shares=, so the suite relies on its own sheet only.
Decisions go through the REAL decision path (RS_Actions.decide, the function the bridge answer goes through in
RadioSurvivor_Server); exchanges are recorded by the REAL bond path (RS_VoiceBonds.answered, called by
RadioSurvivor_Server for every answer on the air). Game days: the bond counts distinct game days and the delays are 7
and 3 game days; a test cannot wait for them, so the game day read by the bond (CA_Reputation.today, the only clock of
RS_VoiceBonds) is shifted for the time of the server decisions, then put back before any client step.

rs.actions.share (tags "server" and "world": the authority, solo or dedicated server, save rstest*)
    - no bond: refused not_trusted; four exchanges on one game day: still refused (one day is not a bond);
    - one more exchange on the day before: accepted; the requester knows the target voice (server state: voice of its
      frequency, one "reply" line naming it), its client copy shows the voice on that frequency; the second client
      (MP) does not (server state and client copy);
    - the same voice again within 7 days: voice_too_soon; another bonded voice within 3 days: too_soon; that voice
      after 3 days, and the first one after 7 days: nothing_new (the target is already known: never given twice).
    - with a good reputation (CA_Reputation.testSetLevel, debug mode and rstest* save), no exchange at all: accepted.
Cleanup (t:defer): game day put back, bonds and last share day of both characters, action counters of the test voices
(unique ids per run), radio histories of both characters (the frequencies of the target are emptied first so that the
checks start from an unknown voice, then put back and sent again to the clients), reputation entry.

Solo: RST.run({ suite = "rs.actions.share", tags = { "world" } })
MP: autoclient.py --mp --clients 2 --server-suite rs.actions.share --server-tags world
Outside the game: tests/test_rs_share_suite.py.
]]

require "RST/RST"
require "RST/RST_Fixtures"
require "RST/RST_Steps"
require "RST/RST_RSHelpers"
require "RST/RST_PeerChecksRadio"
require "RST/RST_PeerChecksVoices"

local PR = RST.PeerRadio
local Steps = RST.Steps
local ANSWER_KHZ = 199800   -- frequency of the test voice (not served: the share line goes to the target frequency)

local function onServer() return type(isServer) == "function" and isServer() end

-- A voice served in this game, active and not a group voice: id, served frequency, sheet; nil when none.
local function targetVoice(Personas)
    for _, id in ipairs(Personas.ids()) do
        local sheet = Personas.get(id)
        local khz = Personas.served(id)[1]
        if sheet ~= nil and sheet.state == "active" and not sheet.group and khz ~= nil
                and Personas.voiceAt(khz) == id then
            return id, khz, sheet
        end
    end
    return nil
end

-- Bonds and last share day of the character put back at the end; the radio history put back and sent again; the
-- frequencies of the target voice emptied (the voice unknown at the start).
local function guardCharacter(t, c, who)
    local rec = c.S.data.characters[who.cid]
    t:ok(type(rec) == "table", "no private record for " .. who.label)
    local bonds, last = RST.deepCopy(rec.voiceBonds), rec.lastShareDay
    t:defer(function()
        rec.voiceBonds, rec.lastShareDay = bonds, last
        c.S.dirty = true
    end, "bonds of " .. who.label .. " put back")
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
            if f.khz ~= c.khz and f.voice ~= c.target then kept[#kept + 1] = f end
        end
        work.frequencies = kept
    end
    RST.setRadio(who.cid, work)
    c.S.dirty = true
end

-- The authority, the modules, the requester, the second client (MP), the target voice, the game day clock.
local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the bonds and the radio history live on the authority (solo or dedicated server), not on an MP client")
    end
    local Server = RS_CarnetServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then
        t:skip("notebook server state not ready (RS_CarnetServer)")
    end
    local Personas = require "RadioSurvivor/RS_Personas"
    local c = { Actions = require "RadioSurvivor/RS_Actions", Bonds = require "RadioSurvivor/RS_VoiceBonds",
        Voice = require "RadioSurvivor/RS_MissionVoice", Log = require "RadioSurvivor/RS_RadioLog",
        S = require "RadioSurvivor/RS_State", Rep = require "CoreAI/CA_Reputation", Personas = Personas }
    if c.S.blocked or c.S.data == nil then t:skip("private state of the notebook not loaded or blocked") end
    local p = RST.Fixtures.player(t)
    t:ok(p ~= nil, "no target player (t.ctx.player)")
    c.me = { player = p, name = onServer() and p:getUsername() or Steps.LOCAL, label = "requester",
        cid = RST.RSHelpers.character(t, p) }
    local other = Steps.others(t)[1]
    if other ~= nil and Steps.playerOf(other) ~= nil then
        local player = Steps.playerOf(other)
        c.other = { player = player, name = other, label = "client " .. other,
            cid = RST.RSHelpers.character(t, player) }
    else
        t:note("no second client online: the requester alone (solo or one client)")
    end
    c.target, c.khz, c.sheet = targetVoice(Personas)
    if c.target == nil then t:skip("no active voice served in this game") end
    -- Game day of the bond (CA_Reputation.today): shifted by c.at(offset), put back by c.realDay() and at the end.
    local today = c.Rep.today
    c.day = today()
    t:ok(type(c.day) == "number", "no game day (CA_Reputation.today)")
    c.at = function(offset) c.Rep.today = function() return c.day + offset end end
    c.realDay = function() c.Rep.today = today end
    t:defer(c.realDay, "game day of the bonds put back")
    guardCharacter(t, c, c.me)
    if c.other ~= nil then guardCharacter(t, c, c.other) end
    c.now = getTimestampMs()
    return c
end

-- Test sheet read by the real parser, unique id per run; its action counters removed at the end.
local function testSheet(t, c, tag)
    local Persona = require "RadioSurvivor/RS_Persona"
    local id = "rstest_share_" .. tag .. "_" .. string.format("%.0f", getTimestampMs())
    local lines = { "format=1", "id=" .. id, "name=RST Share", "frequencies=" .. string.format("%.1f", ANSWER_KHZ / 1000),
        "actions=say,share_frequency", "shares=" .. c.target, "[prompt]", "Test voice of rs.actions.share." }
    local sheet, why = Persona.parseLines(lines, id)
    t:ok(sheet ~= nil, "test sheet refused: " .. tostring(why))
    t:defer(function()
        if type(c.S.data.actionCounters) == "table" and c.S.data.actionCounters[id] ~= nil then
            c.S.data.actionCounters[id] = nil
            c.S.dirty = true
        end
    end, "action counters of " .. id)
    return sheet
end

-- One share_frequency decision of the test sheet for the requester, past the per-voice cooldown of RS_Actions.
local function share(c, sheet)
    c.now = c.now + c.Voice.COOLDOWN_MS + 1000
    local decisions = c.Actions.decide(sheet, c.me.name, { { type = "share_frequency" } }, c.now,
        { player = c.me.player, cid = c.me.cid, khz = ANSWER_KHZ })
    local d = decisions[1]
    return d and d.reason or "none"
end

-- n exchanges of the test voice with the requester recorded on game day offset.
local function exchanges(t, c, sheet, n, offset)
    c.at(offset)
    for _ = 1, n do t:ok(c.Bonds.answered(c.me.cid, sheet.id), "exchange not recorded (RS_VoiceBonds.answered)") end
end

local function frequencyOf(cid, khz)
    for _, f in ipairs(RST.radioOf(cid) and RST.radioOf(cid).frequencies or {}) do
        if f.khz == khz then return f end
    end
    return nil
end

-- Does the character know the voice (E06-T07: voice of one of its frequencies)? Read from the history itself, not
-- through RS_RadioLog.knowsVoice that the executor uses.
local function knows(cid, voice)
    for _, f in ipairs(RST.radioOf(cid) and RST.radioOf(cid).frequencies or {}) do
        if f.voice == voice then return true end
    end
    return false
end

-- "reply" lines of the target frequency naming the target voice (the share line).
local function shareLines(c, cid)
    local f = frequencyOf(cid, c.khz)
    local out = {}
    for _, l in ipairs(f and f.lines or {}) do
        if l.kind == "reply" and string.find(l.text, c.sheet.name or c.target, 1, true) ~= nil then
            out[#out + 1] = l
        end
    end
    return out
end

-- The reputation entry of the requester put back at the end, then the level forced (debug mode, rstest* save).
local function reputation(t, c, level)
    t:ok(c.Rep.ensure(), "reputation state of the core mod not loaded")
    local data = c.Rep.data
    local saved = RST.deepCopy(type(data.reputation) == "table" and data.reputation[c.me.cid] or nil)
    t:defer(function()
        if type(data.reputation) ~= "table" then data.reputation = {} end
        data.reputation[c.me.cid] = saved
        c.Rep.save()
    end, "reputation of the requester put back")
    local ok, why = c.Rep.testSetLevel(nil, c.me.cid, level)
    if not ok then t:skip("test reputation refused: " .. tostring(why)) end
end

-- Every client re-reads its history, then the target frequency of its Radio tab: the requester sees the voice there,
-- every other client does not.
local function clientsSee(t, c)
    Steps.ask(t, "rs.history", { texts = {} }, { target = "all", timeoutMs = PR.HISTORY_MS }, function(t2)
        Steps.ask(t2, "rs.voice.tab", { khz = c.khz }, { target = "all", timeoutMs = PR.HISTORY_MS }, function(t3, res)
            local seen = false
            for _, e in ipairs(res.list) do
                local d = e.data or {}
                if PR.player(t3, e.user) == c.me.player then
                    seen = true
                    t3:ok(d.row == true, "requester: frequency " .. c.khz .. " missing in the Radio tab")
                    t3:eq(c.target, d.voice, "requester: voice of the shared frequency in the Radio tab")
                else
                    t3:eq(nil, d.voice, "client " .. tostring(e.user) .. ": voice shared with another player shown")
                end
            end
            t3:ok(seen, "no answer from the requester client")
        end)
    end)
end

RST.suite("rs.actions.share", { tags = { "server", "world" }, testTimeoutMs = 60000 }, function(s)
    s.test("a voice presents another voice after several exchanges, and not before (E07-T10)", function(t)
        local c = authority(t)
        if c.Rep.level(c.me.cid) == "good" then reputation(t, c, "neutral") end
        local sheet = testSheet(t, c, "a")
        c.at(0)
        t:eq("not_trusted", share(c, sheet), "share without any exchange")
        exchanges(t, c, sheet, 4, 0)
        c.at(0)
        t:eq("not_trusted", share(c, sheet), "share after four exchanges on one game day")
        t:eq(false, knows(c.me.cid, c.target), "requester knows " .. c.target .. " before the bond")
        exchanges(t, c, sheet, 1, -1)
        c.at(0)
        t:eq("ok", share(c, sheet), "share after exchanges over two game days")
        t:eq(true, knows(c.me.cid, c.target), "requester knows " .. c.target .. " (server)")
        local f = frequencyOf(c.me.cid, c.khz)
        t:eq(c.target, f and f.voice, "voice of " .. c.khz .. " kHz for the requester (server)")
        t:eq(1, #shareLines(c, c.me.cid), "share lines naming " .. c.target .. " (server)")
        if c.other ~= nil then
            t:eq(false, knows(c.other.cid, c.target), c.other.label .. " knows " .. c.target .. " (server)")
        end
        -- Delays: 7 game days per voice and character, 3 game days per character.
        c.at(6)
        t:eq("voice_too_soon", share(c, sheet), "same voice six days later")
        local second = testSheet(t, c, "b")
        exchanges(t, c, second, 2, 1)
        exchanges(t, c, second, 2, 2)
        c.at(2)
        t:eq("too_soon", share(c, second), "another voice two days later")
        -- Never an already known voice.
        c.at(3)
        t:eq("nothing_new", share(c, second), "another voice three days later (target already known)")
        c.at(7)
        t:eq("nothing_new", share(c, sheet), "same voice seven days later (target already known)")
        t:eq(1, #shareLines(c, c.me.cid), "share lines naming " .. c.target .. " after the refusals (server)")
        c.realDay()
        clientsSee(t, c)
    end)

    s.test("a good reputation is a bond, no exchange needed (E07-T10)", function(t)
        local c = authority(t)
        reputation(t, c, "good")
        local sheet = testSheet(t, c, "rep")
        t:eq("ok", share(c, sheet), "share with a good reputation")
        t:eq(true, knows(c.me.cid, c.target), "requester knows " .. c.target .. " (server)")
        if c.other ~= nil then
            t:eq(false, knows(c.other.cid, c.target), c.other.label .. " knows " .. c.target .. " (server)")
        end
    end)
end)
