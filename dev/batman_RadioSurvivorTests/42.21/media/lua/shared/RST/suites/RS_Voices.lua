--[[
rs.voices - the network of radio voices on the authority (E05-T06). Two suites, both run on the authority only
(dedicated server, or the solo game; skipped on an MP client, which loads no voice sheet):

rs.voices (tag "server", read only: no file, channel or game state is changed)
    - every voice sheet installed in Zomboid/Lua/batman_RadioSurvivor/personas/ is valid, and the voice in service
      is the one of the file: state, radio, listening hours, frequencies or ranges read from it (a delivered sheet
      changed by the admin is only noted);
    - every active or silent voice holds one channel per frequency of this game, on the frequency drawn in its
      range (0.2 MHz step), and that channel is the voice's own; gone or dead voices hold none;
    - drawn frequencies are free of every other radio channel (vanilla, emergency broadcast of GameTime ModData,
      other mods) and at least Personas.MIN_GAP_KHZ apart between voices;
    - no channel name of a voice is listed (the list reaches every client at login, E05-T08);
    - a silent voice keeps its channel (its frequency stays reserved); that it never answers is checked by
      rs.voices.world, that it never calls by the bench (tests/test_personas_server.py) and the protocol.
    It runs in the automatic run of the test dedicated server (tests/run_dedicated_smoke.ps1 -Filters rst,rs).

rs.voices.world (tags "world" and "server": save named rstest* only)
    - a phrase said on the frequency of each voice reaches the bridge with voice=<id> when the voice is active and
      listening at the current game hour, silence otherwise (silent voice, out of hours); a phrase on a free
      frequency gives silence and no request;
    - a voice sheet radio=high_tier (probe sheet rstest_voices.txt, on a free frequency that an ordinary walkie can
      reach) is silent to an ordinary walkie (Base.WalkieTalkie1) and answers a high-tier one (Base.WalkieTalkie5);
    - an installed sheet changed while the game runs (its name= line, a harmless field) is picked up by the
      periodic reload (Personas.RELOAD_MS) without touching its channels, then restored.

How a phrase is simulated: the suite builds a fake player (a Lua table) holding a real radio item created by
instanceItem (never added to a container or to the world) and fires the real server handler with
triggerEvent("OnClientCommand", "RadioSurvivor", "talk", fakePlayer, args). The vanilla OnClientCommand subscribers
check their module first. During a test, Const.toClient is wrapped: the answers meant for the fake players are kept
for the checks (on a dedicated server the other players still get theirs; in solo every answer is kept: do not
talk on a radio during the run). A request written for the bridge is answered by the suite itself (simulated
bridge: responses.txt with one "<fzzt>" line, aired as static on the voice's frequency), then the suite waits until
the server dropped it. Run with the bridge stopped or started with --offline: a bridge connected to the LLM would
answer the probe phrases too (harmless, but it costs calls). The responses of real requests pending at that moment
are overwritten (test save only).

Callers: on a dedicated server each phrase uses its own account name (rstest_voices_<n>): no delay between them. In
solo every phrase shares the caller key "solo": the suite waits PlayerCooldown (sandbox, 10 s by default) after each
answered request, and the anti-spam limit (Const.SPAM_MAX phrases per minute) allows one run per minute. The game
must run (not paused): the server reads the answers in OnTick.

Files: rstest_voices.txt (probe sheet) is emptied at the end (Lua cannot delete a file: an empty file is a removed
voice). The changed sheet is backed up first in Zomboid/Lua/batman_RadioSurvivor/rstest_voices_backup_<id>.txt and
restored by the cleanup; a non-empty backup left by an interrupted run is restored at the start of the next run of
that test (and in any case the backup file is the exact text to copy back by hand).

Solo:   RST.server("rs.voices") (read only); RST.server({ suite = "rs.voices", tags = { "server", "world" } }) (both)
Server: same commands from an admin client (DebugConsole).
]]

require "RST/RST"

local PROBE_ID = "rstest_voices"
local BACKUP_PREFIX = "batman_RadioSurvivor/rstest_voices_backup_"
local RELOAD_VOICE = "walt"
local LOW_RADIO, HIGH_RADIO = "Base.WalkieTalkie1", "Base.WalkieTalkie5"
local DELIVERED_FALLBACK = { "cody", "darlene", "gus", "nightowl", "walt", "whitaker" }
local STEP_KHZ = 200

-- Helpers ---------------------------------------------------------------------------------------

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("voice sheets live on the authority (not loaded on an MP client)")
    end
    local ok, P = pcall(require, "RadioSurvivor/RS_Personas")
    t:ok(ok and type(P) == "table", "RadioSurvivor/RS_Personas is not loaded on this side")
    return P, require "RadioSurvivor/RadioSurvivor_Const", require "RadioSurvivor/RS_Persona"
end

local function manager(t)
    local radio = getZomboidRadio()
    local m = radio and radio:getScriptManager()
    t:ok(m ~= nil, "no RadioScriptManager on this side")
    return m
end

local function javaList(list)
    local out = {}
    if list == nil then return out end
    for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    return out
end

local function readLines(path)
    local reader = getFileReader(path, false)
    if not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

local function writeLines(t, path, lines)
    local writer = getFileWriter(path, true, false)
    t:ok(writer ~= nil, "cannot write Zomboid/Lua/" .. path)
    for _, line in ipairs(lines) do writer:write(line .. "\n") end
    writer:close()
end

local function label(khz)
    return string.format("%.1f", khz / 1000)
end

local function minuteOfDay()
    local gt = getGameTime()
    return gt:getHour() * 60 + gt:getMinutes()
end

local function copyList(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

-- Ids of the delivered sheets (personas folder of the mod), or the known list if the folder cannot be listed.
local function deliveredIds(P)
    local ids = {}
    local listing = listFilesInModDirectory and listFilesInModDirectory(P.MOD_ID, P.BUNDLED_DIR)
    for _, name in ipairs(javaList(listing)) do
        name = tostring(name)
        if string.len(name) > 4 and string.sub(name, -4) == ".txt" then ids[#ids + 1] = string.sub(name, 1, -5) end
    end
    if #ids == 0 then ids = copyList(DELIVERED_FALLBACK) end
    table.sort(ids)
    return ids
end

local function bundledLines(P, id)
    local reader = getModFileReader and getModFileReader(P.MOD_ID, P.BUNDLED_DIR .. "/" .. id .. ".txt", false)
    if not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

-- Frequencies taken by channels that are not voices of the mod, and by the dynamic vanilla channels of the game
-- (GameTime ModData dynamicRadio: emergency broadcast). kHz -> channel name.
local function foreignFrequencies(P, m)
    local foreign = {}
    local prefix = P.CHANNEL_PREFIX
    for _, channel in ipairs(javaList(m:getChannelsList())) do
        if string.sub(tostring(channel:getGUID()), 1, string.len(prefix)) ~= prefix then
            foreign[channel:GetFrequency()] = tostring(channel:GetName())
        end
    end
    local modData = getGameTime():getModData()
    local dynamic = modData and modData.dynamicRadio
    if type(dynamic) == "table" then
        for _, channel in ipairs(dynamic) do
            if type(channel) == "table" and type(channel.freq) == "number" then
                foreign[channel.freq] = tostring(channel.name)
            end
        end
    end
    return foreign
end

-- Free frequency in [low, high] (0.2 MHz step): no channel of any kind, at least MIN_GAP_KHZ from every frequency
-- of every loaded voice. Searched from the top of the range.
local function freeFrequency(P, m, low, high)
    local foreign = foreignFrequencies(P, m)
    local taken = {}
    for _, id in ipairs(P.ids()) do
        if id ~= PROBE_ID then
            for _, khz in ipairs(P.frequencies(id)) do taken[#taken + 1] = khz end
        end
    end
    for khz = high, low, -STEP_KHZ do
        local ok = not foreign[khz] and P.voiceAt(khz) == nil
        for _, other in ipairs(taken) do
            if math.abs(other - khz) < P.MIN_GAP_KHZ then ok = false end
        end
        if ok then return khz end
    end
    return nil
end

local function inRanges(sheet, khz)
    if #sheet.frequency_ranges == 0 then
        for _, f in ipairs(sheet.frequencies) do
            if f == khz then return true end
        end
        return false
    end
    for _, range in ipairs(sheet.frequency_ranges) do
        if khz >= range.low and khz <= range.high and (khz - range.low) % STEP_KHZ == 0 then return true end
    end
    return false
end

local function listenLabel(sheet)
    if #sheet.listen == 0 then return "always" end
    local out = {}
    for _, r in ipairs(sheet.listen) do
        out[#out + 1] = string.format("%02d:%02d-%02d:%02d", math.floor(r.from / 60), r.from % 60, math.floor(r.to / 60),
            r.to % 60)
    end
    return table.concat(out, ",")
end

-- Requests of requests.txt: list of { id, caller, voice, text, ... }.
local function requests(Const)
    local list, current = {}, nil
    for _, line in ipairs(readLines(Const.REQUESTS_FILE) or {}) do
        local key, value = string.match(line, "^(%a+)=(.*)$")
        if key == "req" then
            current = { id = value }
            list[#list + 1] = current
        elseif key and current then
            current[key] = value
        end
    end
    return list
end

local function findRequest(Const, field, value)
    for _, req in ipairs(requests(Const)) do
        if req[field] == value then return req end
    end
    return nil
end

-- Phrases ---------------------------------------------------------------------------------------

-- Wraps Const.toClient for the test: answers to the fake players (and, in solo, every answer) are recorded instead
-- of being sent. Restored by t:defer.
local function newTalker(t, Const)
    local talker = { n = 0, fakes = {}, sent = {} }
    local original = Const.toClient
    Const.toClient = function(player, command, args)
        local solo = not (type(isServer) == "function" and isServer())
        if solo or talker.fakes[player] then
            local reason = type(args) == "table" and args.reason
            talker.sent[#talker.sent + 1] = reason and (command .. ":" .. tostring(reason)) or command
            return
        end
        return original(player, command, args)
    end
    t:defer(function() Const.toClient = original end, "restore Const.toClient")
    return talker
end

local function newRadio(t, fullType, highTier)
    local radio = instanceItem(fullType)
    t:ok(radio ~= nil and instanceof(radio, "Radio"), "instanceItem(" .. fullType .. ") is not a Radio")
    local data = radio:getDeviceData()
    t:ok(data ~= nil and data:getIsTwoWay() == true, fullType .. " is not a two-way radio")
    t:eq(highTier, data:getIsHighTier() == true, "getIsHighTier of " .. fullType)
    return radio
end

local function fakePlayer(talker, radio, username)
    local player = { radio = radio, username = username }
    function player:getPrimaryHandItem() return self.radio end
    function player:getSecondaryHandItem() return nil end
    function player:getClothingItem_Back() return nil end
    -- Radio in hand: the server looks in the main inventory only for a radio carried elsewhere (belt, E06 fix).
    function player:getInventory() return nil end
    function player:getUsername() return self.username end
    function player:getHoursSurvived() return 24 end
    local descriptor = {}
    function descriptor:getForename() return "RST" end
    function descriptor:getSurname() return "Voices" end
    function player:getDescriptor() return descriptor end
    talker.fakes[player] = true
    return player
end

-- Says a phrase through the real server handler. Returns the commands sent back and the request written for the
-- bridge (nil if none).
-- Callers of a dedicated server are numbered for the whole Lua state, not per test: two tests of a run (rs.voices,
-- then rs.voices.world) reusing "rstest_voices_1" within PlayerCooldown got "rejected:Cooldown" (MP run of
-- 2026-10-14, E01-T15).
local callerSeq = 0

local function say(talker, Const, radio, khz)
    talker.n = talker.n + 1
    callerSeq = callerSeq + 1
    local text = "rst voices probe " .. tostring(talker.n) .. " " .. string.format("%.0f", getTimestampMs())
    local server = type(isServer) == "function" and isServer()
    local key = server and ("rstest_voices_" .. tostring(callerSeq)) or "solo"
    local player = fakePlayer(talker, radio, key)
    local first = #talker.sent + 1
    triggerEvent("OnClientCommand", Const.MODULE, Const.CMD.TALK, player,
        { text = text, itemId = radio:getID(), channel = khz })
    local sent = {}
    for i = first, #talker.sent do sent[#sent + 1] = talker.sent[i] end
    return { sent = sent, key = key, request = findRequest(Const, "text", text) }
end

-- One phrase on khz with its expected outcome (expectVoice = id of the voice that must get the request, or nil for
-- silence), then continue(t). A request is answered by the suite (simulated bridge) and awaited until the server
-- dropped it; in solo, the PlayerCooldown delay is awaited too (shared caller key).
local function phrase(t, talker, Const, radio, khz, expectVoice, what, continue)
    local result = say(talker, Const, radio, khz)
    if not expectVoice then
        t:eq({ "accepted", "done" }, result.sent, what .. ": answers to the caller (silence expected)")
        t:ok(result.request == nil, what .. ": a request reached the bridge")
        return continue(t)
    end
    t:eq({ "accepted" }, result.sent, what .. ": answers to the caller (request expected)")
    local req = result.request
    t:ok(req ~= nil, what .. ": no request in " .. Const.REQUESTS_FILE)
    t:eq(expectVoice, req.voice, what .. ": voice= of the request")
    t:eq(result.key, req.caller, what .. ": caller= of the request")
    -- text= holds a timestamp (unique phrase): not checked.
    for _, field in ipairs({ "voice", "caller", "name", "date", "days", "radio" }) do
        local value = tostring(req[field] or "")
        t:ok(string.find(value, label(khz), 1, true) == nil and string.find(value, tostring(khz), 1, true) == nil,
            what .. ": frequency written in the " .. field .. "= field of the request")
    end
    local writer = getFileWriter(Const.RESPONSES_FILE, true, false)
    t:ok(writer ~= nil, "cannot write Zomboid/Lua/" .. Const.RESPONSES_FILE)
    writer:write("resp=" .. req.id .. "\nline=<fzzt>\nend\n")
    writer:close()
    local answeredAt = getTimestampMs()
    t:waitUntil(function() return findRequest(Const, "id", req.id) == nil end, 20000, function(t2)
        if type(isServer) == "function" and isServer() then return continue(t2) end
        local wait = Const.playerCooldownMs() + 250
        t2:waitQuiet(function() return getTimestampMs() - answeredAt >= wait end, wait + 5000, continue,
            "PlayerCooldown delay")
    end, what .. ": request still pending after the simulated answer (game paused? OnTick not running?)")
end

-- Runs the steps one after the other (each step is function(t, continue)), then finish(t).
local function chain(t, steps, index, finish)
    if index > #steps then return finish(t) end
    return steps[index](t, function(t2) return chain(t2, steps, index + 1, finish) end)
end

-- Suites ----------------------------------------------------------------------------------------

RST.suite("rs.voices", { tags = { "server" } }, function(s)
    s.test("installed sheets valid and read into the voices in service", function(t)
        local P, _, Persona = authority(t)
        local ids = P.ids()
        t:ok(#ids > 0, "no voice loaded (see the [RadioSurvivor] personas: lines of the log)")
        for _, id in ipairs(deliveredIds(P)) do
            t:ok(P.get(id) ~= nil, "delivered voice '" .. id .. "' not loaded (sheet removed, emptied or refused?)")
        end
        for _, id in ipairs(ids) do
            local lines = readLines(P.DIR .. "/" .. id .. ".txt")
            if P.get(id).generated then
                -- Generated voice (RS_GroupRadio: one per group holding a transmitter, Personas.setGenerated): no
                -- sheet file by design; a file of the same id would win and the voice would not be generated.
                t:ok(lines == nil or #lines == 0, "generated voice " .. id .. " has a sheet file, which should win")
                t:note(id .. ": generated group voice, " .. P.get(id).state .. " (no sheet file by design)")
            else
                t:ok(lines ~= nil and #lines > 0, "Zomboid/Lua/" .. P.DIR .. "/" .. id .. ".txt missing or empty")
                local sheet, err = Persona.parseLines(lines, id)
                t:ok(sheet ~= nil, "installed sheet " .. id .. ".txt refused: " .. tostring(err)
                    .. " (an older valid version is in service)")
                local live = P.get(id)
                for _, field in ipairs({ "state", "radio", "listen", "frequencies", "frequency_ranges", "budget",
                    "call_one_in" }) do
                    t:eq(sheet[field], live[field], "voice " .. id .. ": " .. field .. " in service differs from the file")
                end
                local bundled = bundledLines(P, id)
                local changed = bundled ~= nil and table.concat(bundled, "\n") ~= table.concat(lines, "\n")
                t:note(id .. ": " .. live.state .. ", radio " .. live.radio .. ", listen " .. listenLabel(live)
                    .. (changed and " (sheet changed by the admin)" or "") .. (bundled == nil and " (not delivered)" or ""))
            end
        end
    end)

    s.test("each voice holds its own channel on the frequency drawn in its range", function(t)
        local P = authority(t)
        local m = manager(t)
        for _, id in ipairs(P.ids()) do
            local sheet = P.get(id)
            local frequencies = P.frequencies(id)
            local served = P.served(id)
            if P.holdsFrequencies(sheet) then
                local expected = #sheet.frequency_ranges
                if expected == 0 then expected = #sheet.frequencies end
                t:eq(expected, #frequencies, "voice " .. id .. ": one frequency per range or fixed frequency")
                t:eq(frequencies, served, "voice " .. id .. ": frequencies not all served (conflict or taken: see the log)")
                for _, khz in ipairs(served) do
                    t:ok(inRanges(sheet, khz), "voice " .. id .. ": " .. label(khz) .. " MHz outside its ranges or step")
                    local channel = m:getRadioChannel(P.CHANNEL_PREFIX .. id .. "-" .. tostring(khz))
                    t:ok(channel ~= nil, "voice " .. id .. ": no channel on " .. label(khz) .. " MHz")
                    t:eq(khz, channel:GetFrequency(), "voice " .. id .. ": frequency of its channel")
                    t:eq(id, P.voiceAt(khz), "owner of " .. label(khz) .. " MHz")
                end
                t:note(id .. " (" .. sheet.state .. ") on " .. table.concat((function()
                    local out = {}
                    for _, khz in ipairs(served) do out[#out + 1] = label(khz) end
                    return out
                end)(), ", ") .. " MHz")
            else
                t:eq(0, #served, "voice " .. id .. " is " .. sheet.state .. " but serves frequencies")
                for _, khz in ipairs(frequencies) do
                    t:ok(m:getRadioChannel(P.CHANNEL_PREFIX .. id .. "-" .. tostring(khz)) == nil,
                        "voice " .. id .. " is " .. sheet.state .. " but keeps its channel on " .. label(khz))
                end
                t:note(id .. " (" .. sheet.state .. "): no channel")
            end
        end
    end)

    s.test("frequencies free of other channels and apart from each other", function(t)
        local P = authority(t)
        local m = manager(t)
        local foreign = foreignFrequencies(P, m)
        local held = {}
        for _, id in ipairs(P.ids()) do
            for _, khz in ipairs(P.served(id)) do
                t:ok(foreign[khz] == nil, "voice " .. id .. " on " .. label(khz) .. " MHz, also used by channel '"
                    .. tostring(foreign[khz]) .. "'")
                held[#held + 1] = { id = id, khz = khz, drawn = #P.get(id).frequency_ranges > 0 }
            end
        end
        t:ok(#held > 0, "no voice holds a frequency")
        for i = 1, #held do
            for j = i + 1, #held do
                local a, b = held[i], held[j]
                t:ok(a.khz ~= b.khz, "two voices on " .. label(a.khz) .. " MHz: " .. a.id .. ", " .. b.id)
                if a.id ~= b.id and a.drawn and b.drawn then
                    t:ok(math.abs(a.khz - b.khz) >= P.MIN_GAP_KHZ, "drawn frequencies of " .. a.id .. " and " .. b.id
                        .. " closer than " .. label(P.MIN_GAP_KHZ) .. " MHz: " .. label(a.khz) .. ", " .. label(b.khz))
                end
            end
        end
        local count = 0
        for _ in pairs(foreign) do count = count + 1 end
        t:note(tostring(#held) .. " voice frequencies, " .. tostring(count) .. " other channels avoided")
    end)

    s.test("no voice channel name listed for the clients", function(t)
        local P = authority(t)
        local held = P.heldFrequencies()
        t:ok(#held > 0, "no voice holds a frequency")
        for _, khz in ipairs(held) do
            t:ok(getZomboidRadio():getChannelName(khz) == nil, "name of the voice channel on " .. label(khz)
                .. " MHz listed (sent to every client at login)")
        end
    end)

    s.test("silent voice keeps its reserved channel", function(t)
        local P = authority(t)
        local silent = {}
        for _, id in ipairs(P.ids()) do
            if P.get(id).state == "silent" then silent[#silent + 1] = id end
        end
        if #silent == 0 then t:skip("no silent voice (whitaker is delivered silent: sheet changed?)") end
        for _, id in ipairs(silent) do
            t:ok(#P.served(id) > 0, "silent voice " .. id .. " lost its reserved frequency")
            t:note(id .. " silent on " .. label(P.served(id)[1]) .. " MHz (no answer: rs.voices.world)")
        end
    end)
end)

RST.suite("rs.voices.world", { tags = { "world", "server" }, testTimeoutMs = 120000, timeoutMs = 360000 },
    function(s)
    s.test("phrase on each voice frequency reaches the bridge with its voice, silence elsewhere", function(t)
        local P, Const = authority(t)
        local m = manager(t)
        local talker = newTalker(t, Const)
        local radio = newRadio(t, HIGH_RADIO, true)
        local steps = {}
        for _, id in ipairs(P.ids()) do
            local khz = P.served(id)[1]
            if khz and id ~= PROBE_ID then
                local generated = P.get(id).generated
                steps[#steps + 1] = function(t2, continue)
                    local sheet = P.get(id)
                    if sheet == nil and generated then
                        -- Withdrawn since the steps were built: a generated group voice goes with the group's
                        -- transmitter (RS_GroupRadio.refresh). A sheet voice never goes during the suite.
                        t2:note(id .. ": generated group voice withdrawn during the run, not checked")
                        return continue(t2)
                    end
                    t2:ok(sheet ~= nil, "voice " .. id .. " gone during the run")
                    local listening = P.isListening(sheet, minuteOfDay())
                    local expect = sheet.state == "active" and listening and id or nil
                    if sheet.generated then
                        -- Group voice (RS_GroupRadio.talk): answered through the notebook npc queue by the speaker
                        -- of the group, never by a voice request to the bridge; the fake talker has no notebook
                        -- character, so silence (the group call itself is rs.groupradio).
                        expect = nil
                        t2:note(id .. " on " .. label(khz) .. " MHz: generated group voice -> silence for a caller "
                            .. "without a notebook character, no voice request")
                    else
                        t2:note(id .. " on " .. label(khz) .. " MHz: " .. sheet.state .. ", listen "
                            .. listenLabel(sheet) .. (listening and " (listening now)" or " (not listening now)")
                            .. " -> " .. (expect and "request" or "silence"))
                    end
                    return phrase(t2, talker, Const, radio, khz, expect, "voice " .. id, continue)
                end
            end
        end
        t:ok(#steps > 0, "no voice holds a frequency")
        local free = freeFrequency(P, m, 75000, 199800)
        t:ok(free ~= nil, "no free frequency found between 75.0 and 199.8 MHz")
        steps[#steps + 1] = function(t2, continue)
            t2:note("free frequency " .. label(free) .. " MHz -> silence")
            return phrase(t2, talker, Const, radio, free, nil, "free frequency " .. label(free), continue)
        end
        chain(t, steps, 1, function(t2) t2:ok(true, "all phrases checked") end)
    end)

    s.test("ordinary radio refused by a high_tier voice, high-tier radio answered", function(t)
        local P, Const = authority(t)
        local m = manager(t)
        local path = P.DIR .. "/" .. PROBE_ID .. ".txt"
        t:defer(function(t2)
            writeLines(t2, path, {})
            P.reload()
            t2:ok(P.get(PROBE_ID) == nil, "probe voice still loaded after emptying its sheet")
        end, "empty the probe sheet")
        local talker = newTalker(t, Const)
        local low = newRadio(t, LOW_RADIO, false)
        local high = newRadio(t, HIGH_RADIO, true)
        local data = low:getDeviceData()
        local khz = freeFrequency(P, m, data:getMinChannelRange(), math.min(data:getMaxChannelRange(), 999800))
        t:ok(khz ~= nil, "no free frequency within the range of " .. LOW_RADIO)
        writeLines(t, path, { "format=1", "id=" .. PROBE_ID, "name=RST Voices", "frequencies=" .. label(khz),
            "radio=high_tier", "listen=always", "state=active", "", "[prompt]", "Test voice of the rs.voices suite." })
        P.reload()
        t:ok(P.isServed(PROBE_ID, khz), "probe voice not served on " .. label(khz) .. " MHz (see the log)")
        t:note("probe radio=high_tier on " .. label(khz) .. " MHz")
        chain(t, {
            function(t2, continue)
                return phrase(t2, talker, Const, low, khz, nil, LOW_RADIO .. " on a high_tier voice", continue)
            end,
            function(t2, continue)
                return phrase(t2, talker, Const, high, khz, PROBE_ID, HIGH_RADIO .. " on a high_tier voice", continue)
            end,
        }, 1, function(t2) t2:ok(true, "both radios checked") end)
    end)

    s.test("installed sheet changed during the game, reloaded without touching its channels, restored", function(t)
        local P = authority(t)
        -- Backups left by an interrupted run: restored first.
        for _, id in ipairs(deliveredIds(P)) do
            local backup = BACKUP_PREFIX .. id .. ".txt"
            local saved = readLines(backup)
            if saved and #saved > 0 then
                writeLines(t, P.DIR .. "/" .. id .. ".txt", saved)
                writeLines(t, backup, {})
                P.reload()
                t:note("sheet " .. id .. ".txt restored from the backup of an interrupted run")
            end
        end
        local id = RELOAD_VOICE
        if P.get(id) == nil then
            id = nil
            for _, other in ipairs(P.ids()) do
                if id == nil and other ~= PROBE_ID and not P.get(other).generated then id = other end
            end
        end
        t:ok(id ~= nil and P.get(id) ~= nil, "no voice loaded")
        local path = P.DIR .. "/" .. id .. ".txt"
        local backup = BACKUP_PREFIX .. id .. ".txt"
        local original = readLines(path)
        t:ok(original ~= nil and #original > 0, "Zomboid/Lua/" .. path .. " missing or empty")
        local before = P.get(id)
        local name = before.name .. " RST"
        local changed, found = {}, false
        for i, line in ipairs(original) do
            if not found and string.sub(line, 1, 5) == "name=" then
                changed[i] = "name=" .. name
                found = true
            else
                changed[i] = line
            end
        end
        t:ok(found, "no name= line in " .. id .. ".txt")
        local served = copyList(P.served(id))
        local channels = {}
        for i, khz in ipairs(served) do channels[i] = P.channel(khz) end
        writeLines(t, backup, original)
        t:defer(function(t2)
            writeLines(t2, path, original)
            P.reload()
            t2:eq(before.name, P.get(id).name, "name of " .. id .. " after the restore")
            t2:eq(served, P.served(id), "frequencies of " .. id .. " after the restore")
            writeLines(t2, backup, {})
        end, "restore " .. id .. ".txt")
        writeLines(t, path, changed)
        local started = getTimestampMs()
        t:waitUntil(function()
            local sheet = P.get(id)
            return sheet ~= nil and sheet.name == name
        end, P.RELOAD_MS + 5000, function(t2)
            t2:note(id .. ".txt reloaded " .. tostring(getTimestampMs() - started) .. " ms after the change")
            t2:eq(before.state, P.get(id).state, "state of " .. id .. " after the reload")
            t2:eq(served, P.served(id), "frequencies of " .. id .. " after the reload")
            for i, khz in ipairs(served) do
                t2:ok(P.channel(khz) ~= nil, "channel of " .. id .. " on " .. label(khz) .. " MHz lost by the reload")
                t2:ok(P.channel(khz) == channels[i], "channel of " .. id .. " on " .. label(khz)
                    .. " MHz replaced by the reload")
            end
        end, "name change of " .. id .. ".txt not picked up by the periodic reload")
    end)
end)
