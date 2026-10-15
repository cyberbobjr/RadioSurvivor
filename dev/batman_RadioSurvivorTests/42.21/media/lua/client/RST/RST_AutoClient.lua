--[[
RST_AutoClient - Lua driver of the automatic client launcher (E01-T14, tools/autoclient/autoclient.py). Development
mod only. Without the command file below this file does nothing (it only subscribes four events once).

Command file (written by the launcher in the temporary cache folder, read only here, never changed nor removed):
    Zomboid/Lua/batman_RadioSurvivor/tests/autoclient.txt     UTF-8 without BOM, one "key=value" per line
        # comment              ignored, as are empty lines
        token=<letters/digits> required: identifies this launch in the status file
        save=<save folder>     required: Zomboid/Saves/<mode>/<save>
        mode=Sandbox           optional (default Sandbox)
        campaign=<name>        RST.campaign(name)                  (exactly one of campaign / suite)
        suite=<a,b,...>        RST.run({ suite = { "a", "b" } })   default exclusion of RST_Client (server, world)
        tags=<a,b,...>         optional with suite=: explicit filter tags (e.g. world), no default exclusion
        exclude=<a,b,...>      optional with suite=: explicit exclusion (empty = none), no default exclusion
        startDelaySec=<n>      optional (default 5): real seconds between OnGameStart and the run
        quit=true|false        optional (default true): quit to desktop at the end (the game saves first)
        screenshot=true|false  optional (default true): takeScreenshot("autoclient-<token>.png") before quitting
    Multiplayer client (E01-T15, autoclient.py --mp): connect= replaces save=/mode=
        connect=<host>:<port>  join this dedicated server (no save= needed)
        user=<account>         required with connect=; password=<text> (may be empty)
        serverSuite=<a,b,...>  RST.server({ suite = {...} }) once the client run (if any) is over; serverTags= and
                               serverExclude= as tags=/exclude= (explicit server filter)
                               "a,b;c" (E01-T17): successive server runs, the next one requested once the report of
                               the previous one is in (e.g. "rs.identity.after-reconnect;rs.identity.before": the
                               snapshot is taken again after the checks); tags and exclusion apply to every run, the
                               counters and failure lines are summed into one result (serverReport= ","-joined)
        serverCampaign=<name>  RST.server({ suite = RST.CAMPAIGNS[name], exclude = { "manual" } })
        serverTimeoutSec=<n>   optional (default 3600): real seconds to wait for the server report
        control=true           optional (default false): wait for a line "go" in autoclient-control.txt before the
                               run, and for a line "quit" after it (instead of quitting at once). The launcher writes
                               that file when every client is in game, then when every client is done.
        Without any of campaign/suite/serverSuite/serverCampaign the client is "idle": it only stays connected
        (second player), status "idle", and quits on "quit".
        peer=true              optional with connect= (E01-T16, second client of autoclient.py --mp --clients 2): an
                               idle client that answers the steps of the server suites (RST.Steps, RST_PeerChecks.lua;
                               every client answers them, peer or not) and, on "quit", writes its result file from
                               the steps it answered: "RST-RESULT ok=... total=<steps> pass= fail= error= skip=
                               empty=0 durationMs=0 [report=<stamp>-steps.txt]" (ok=true with total=0: nothing asked).

Sequence (vanilla paths, see docs/tests-en-jeu.md, section "Lanceur client automatique"):
    main menu  OnMainMenuEnter: "Break On Error" off; OnFETick waits until MainScreen.instance exists and 3 s have
               passed, then MainScreen.continueLatestSave(mode, save) (what LoadGameScreen:clickPlay calls). The
               loading screen then waits for a left click (GameLoadingState.update reads Mouse.isButtonDown(0)):
               the launcher posts it to the window while the last status is "load".
               If the menu shows a save error dialog (MainScreen.instance.checkSavefileModal) the driver writes an
               error result and quits. A Lua reset (save mods different from the default list) fires
               OnMainMenuEnter again in a new Lua state: the status file tells that the load was already asked.
    in game    OnGameStart: status "ingame"; after startDelaySec the run starts (status "run"); OnTick polls
               RST.running(); at the end the result file is written, then screenshot and getCore():quitToDesktop()
               (GameWindow.exit saves the game first: okToSaveOnExit).
    MP join    at the menu (3 s after MainScreen.instance) ConnectToServer.instance:connect(bottomPanel, "", user,
               password, host, "", port, "", false, true, 1), the call of the "Join server" popup
               (ServerConnectPopup.lua:210). The client then resets Lua (ConnectToServerState.receiveServerOptions:
               ResetLua "client"): in the new state the status file holds "connect", the driver waits for the
               character creation that ConnectToServer:OnConnected shows to a new account (the server ini has a
               fixed SpawnPoint, so no spawn choice), presses NEXT on CharacterCreationProfession then on
               CharacterCreationMain (vanilla defaults: unemployed, random look and name), status "load", and the
               launcher clicks the loading screen as in solo. An account that already has a character (reconnection
               of a later phase, E01-T17) gets no creation screen: OnConnected with checkSavePlayerExists() writes
               "load" at once. OnConnectFailed or a return to the plain menu fails
               the launch. A client started with -debug is disconnected unless its role has ConnectWithDebug
               (admin only): the launcher makes every account admin.
    MP death   (E00-T02, E03-T04, E15-T02, suite rs.death) OnPlayerDeath of the local player of an MP client: after
               RESPAWN_DELAY_MS (the post-death screen shows its buttons after 3 s) the driver presses Respawn
               (ISPostDeathUI:onRespawn), then on the in-game creation (CoopCharacterCreation.newPlayerMouse) the spawn
               choice if shown (CoopMapSpawnSelect:clickNext, first region), NEXT on CoopCharacterCreationProfession
               and NEXT on CoopCharacterCreationMain (accept: setPlayerMouse(nil) adds the new player in place, no
               loading screen). Each phase writes a status line that REPEATS the current state (idle for a peer)
               with a detail "respawn: ...", so the launcher sees no change of state; the run, steps and control
               file go on in the same Lua state. A failure (RESPAWN_TIMEOUT_MS) is only written in the detail.
Status file (appended, one line per step): Zomboid/Lua/batman_RadioSurvivor/tests/autoclient-status.txt
    "<token> <state> <detail>" with state in menu, connect, create, load, ingame, go, run, server, done, idle, quit,
    error.
Control file (MP, control=true, written by the launcher, read only here): Zomboid/Lua/batman_RadioSurvivor/tests/
autoclient-control.txt, one word per line: "go", "quit", "reload" (E01-T17, phase reconnect2: the client stays
connected, reads autoclient.txt again once its run is over and starts the new command if its token changed, see
A.reload).
Result file: Zomboid/Lua/batman_RadioSurvivor/tests/autoclient-result.txt, same format as autorun-result.txt
(RST_Server.lua): first line "RST-RESULT ok=... total=... ... [report=<file>] [reason=<text>]", the report lines,
last line "RST-END".
]]

require "RST/RST"
require "RST/RST_Client"
require "RST/RST_Campaign"
require "RST/RST_Steps"
require "RST/RST_PeerChecks"

RST.AutoClient = RST.AutoClient or {}
local A = RST.AutoClient

A.COMMAND_FILE = RST.FILE_DIR .. "autoclient.txt"
A.STATUS_FILE = RST.FILE_DIR .. "autoclient-status.txt"
A.RESULT_FILE = RST.FILE_DIR .. "autoclient-result.txt"
A.CONTROL_FILE = RST.FILE_DIR .. "autoclient-control.txt"
A.MENU_DELAY_MS = 3000
A.CONTROL_POLL_MS = 1000     -- control file read at most once a second
A.CREATE_STEP_MS = 1500      -- between the two NEXT presses of the character creation
A.JOIN_MENU_MS = 20000       -- MP: back on the plain menu this long after the reset = connection lost
A.JOIN_LOAD_MS = 120000      -- MP: no character creation this long after the reset = existing character, loading
A.MAX_LINES = 200
A.RESPAWN_DELAY_MS = 5000    -- MP death: ISPostDeathUI shows Respawn 3 s after the death (waitOver)
A.RESPAWN_TIMEOUT_MS = 120000

local function log(msg)
    print("[RST-AUTO] " .. msg)
end

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, v = pcall(getTimestampMs)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

local function oneLine(s)
    s = tostring(s)
    s = string.gsub(s, "[\r\n]+", " ")
    if #s > 300 then s = string.sub(s, 1, 300) .. "..." end
    return s
end

local function trim(s)
    s = string.gsub(s, "^[ \t]+", "")
    s = string.gsub(s, "[ \t]+$", "")
    return s
end

-- Reads a text file of Zomboid/Lua (read only). Returns the list of lines, or nil when absent or unreadable.
local function readLines(path)
    if type(getFileReader) ~= "function" then return nil end
    local okOpen, reader = pcall(getFileReader, path, false)
    if not okOpen or reader == nil then return nil end
    local lines = {}
    local okRead = pcall(function()
        while #lines < A.MAX_LINES do
            local line = reader:readLine()
            if line == nil then break end
            lines[#lines + 1] = tostring(line)
        end
    end)
    pcall(function() reader:close() end)
    if not okRead then return nil end
    return lines
end

local function isTrue(v, default)
    if v == nil then return default end
    return v == "true"
end

-- Parses the command lines. Returns the command table, or nil and a reason.
function A.parse(lines)
    local cmd = {}
    for i, raw in ipairs(lines) do
        local line = trim(raw)
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            local key, value = string.match(line, "^([%a]+)=(.*)$")
            if not key then return nil, "line " .. i .. ": expected key=value" end
            cmd[key] = trim(value)
        end
    end
    if not cmd.token or not string.match(cmd.token, "^[%w]+$") then return nil, "token missing or not alphanumeric" end
    local mp = cmd.connect ~= nil
    if mp then
        if not string.match(cmd.connect, "^[^:]+:%d+$") then return nil, "connect= must be host:port" end
        if not cmd.user or cmd.user == "" then return nil, "user= is needed with connect=" end
        if cmd.campaign ~= nil and cmd.suite ~= nil then return nil, "at most one of campaign= and suite=" end
        if cmd.serverCampaign ~= nil and cmd.serverSuite ~= nil then
            return nil, "at most one of serverCampaign= and serverSuite="
        end
    else
        if not cmd.save or cmd.save == "" then return nil, "save missing" end
        if (cmd.campaign == nil) == (cmd.suite == nil) then return nil, "exactly one of campaign= and suite= is needed" end
        if cmd.serverSuite ~= nil or cmd.serverCampaign ~= nil then return nil, "server runs need connect=" end
        if cmd.peer ~= nil then return nil, "peer= needs connect=" end
    end
    local out = { token = cmd.token, save = cmd.save, mode = cmd.mode or "Sandbox", campaign = cmd.campaign,
        startDelayMs = (tonumber(cmd.startDelaySec or "5") or 5) * 1000,
        quit = isTrue(cmd.quit, true), screenshot = isTrue(cmd.screenshot, true),
        mp = mp, control = isTrue(cmd.control, false), user = cmd.user, password = cmd.password or "",
        peer = isTrue(cmd.peer, false),
        serverCampaign = cmd.serverCampaign,
        serverTimeoutMs = (tonumber(cmd.serverTimeoutSec or "3600") or 3600) * 1000 }
    if mp then
        out.host, out.port = string.match(cmd.connect, "^([^:]+):(%d+)$")
    end
    local function split(text)
        local list = {}
        for name in string.gmatch(text, "[^,]+") do
            name = trim(name)
            if name ~= "" then list[#list + 1] = name end
        end
        return list
    end
    if cmd.suite then
        local suites = split(cmd.suite)
        if #suites == 0 then return nil, "suite= is empty" end
        out.suites = suites
        -- Explicit filter (RST_Client rule): tags= and/or exclude= (empty exclude = no exclusion) replace the
        -- default exclusion of server and world suites, e.g. tags=world for rs.npctalk.
        if cmd.tags ~= nil then out.tags = split(cmd.tags) end
        if cmd.exclude ~= nil then out.exclude = split(cmd.exclude) end
    elseif cmd.tags ~= nil or cmd.exclude ~= nil then
        return nil, "tags= and exclude= need suite="
    end
    if cmd.serverSuite then
        local runs = {}
        for part in string.gmatch(cmd.serverSuite .. ";", "([^;]*);") do
            local suites = split(part)
            if #suites == 0 then return nil, "serverSuite= is empty (or has an empty run between ';')" end
            runs[#runs + 1] = suites
        end
        out.serverSuites = runs[1]
        out.serverRuns = runs
        if cmd.serverTags ~= nil then out.serverTags = split(cmd.serverTags) end
        if cmd.serverExclude ~= nil then out.serverExclude = split(cmd.serverExclude) end
    elseif cmd.serverTags ~= nil or cmd.serverExclude ~= nil then
        return nil, "serverTags= and serverExclude= need serverSuite="
    end
    out.idle = out.campaign == nil and out.suites == nil and out.serverSuites == nil and out.serverCampaign == nil
    if out.peer and not out.idle then return nil, "peer=true is for a client without run (no suite nor campaign)" end
    return out
end

-- Loads the command once per Lua state. Returns the command or nil (absent file, or invalid: logged).
function A.command()
    if A._cmdRead then return A._cmd end
    A._cmdRead = true
    local lines = readLines(A.COMMAND_FILE)
    if not lines then return nil end
    local cmd, why = A.parse(lines)
    if not cmd then
        log("ERROR: " .. A.COMMAND_FILE .. " refused: " .. why)
        A._invalid = why
        return nil
    end
    A._cmd = cmd
    return cmd
end

function A.status(state, detail)
    local cmd = A._cmd
    A._state = state
    local line = (cmd and cmd.token or "-") .. " " .. state .. " " .. oneLine(detail or "")
    log("status " .. line)
    if type(getFileWriter) ~= "function" then return end
    local ok, writer = pcall(getFileWriter, A.STATUS_FILE, true, true)
    if not ok or not writer then return end
    pcall(function() writer:writeln(line) end)
    pcall(function() writer:close() end)
end

-- True when the status file already holds state for the token of the command (survives a Lua reset).
function A.hasStatus(state)
    local cmd = A._cmd
    if not cmd then return false end
    local prefix = cmd.token .. " " .. state .. " "
    for _, line in ipairs(readLines(A.STATUS_FILE) or {}) do
        if string.sub(line .. " ", 1, #prefix) == prefix then return true end
    end
    return false
end

-- MP, control=true: true when the control file written by the launcher holds the word on a line of its own.
-- The file is read at most once per CONTROL_POLL_MS (the last answer is reused in between).
function A.control(word)
    local now = nowMs()
    if A._controlAt == nil or now >= A._controlAt then
        A._controlAt = now + A.CONTROL_POLL_MS
        local words = {}
        for _, line in ipairs(readLines(A.CONTROL_FILE) or {}) do words[trim(line)] = true end
        A._controlWords = words
    end
    return (A._controlWords or {})[word] == true
end

local function muteDebugger()
    if UIManager ~= nil then pcall(UIManager.setShowLuaDebuggerOnError, false) end
end

-- ---------------------------------------------------------------- result

function A.resultLine(report, reportFile, reason, serverFile)
    local r = report or { ok = false, total = 0, pass = 0, fail = 0, error = 0, skip = 0, empty = 0, durationMs = 0 }
    local ok = r.ok and r.total > 0 and reason == nil
    if reason == nil and r.total == 0 then reason = "no test selected" end
    local line = "RST-RESULT ok=" .. tostring(ok and true or false) .. " total=" .. r.total .. " pass=" .. r.pass
        .. " fail=" .. r.fail .. " error=" .. r.error .. " skip=" .. r.skip .. " empty=" .. r.empty
        .. " durationMs=" .. math.floor((r.durationMs or 0) + 0.5)
    if reportFile then line = line .. " report=" .. reportFile end
    if serverFile then line = line .. " serverReport=" .. serverFile end
    if reason then line = line .. " reason=" .. oneLine(reason) end
    return line
end

-- Result of a peer client (E01-T16): the steps it answered (RST.Steps.summary), one line per step.
function A.peerResult()
    local St = RST.Steps
    local sum = St and St.summary() or { ok = true, total = 0, pass = 0, fail = 0, error = 0, skip = 0 }
    local first = "RST-RESULT ok=" .. tostring(sum.ok and true or false) .. " total=" .. sum.total .. " pass=" .. sum.pass
        .. " fail=" .. sum.fail .. " error=" .. sum.error .. " skip=" .. sum.skip .. " empty=0 durationMs=0"
    if sum.file then first = first .. " report=" .. sum.file end
    local lines = {}
    for _, r in ipairs(St and St.records or {}) do
        lines[#lines + 1] = "STEP " .. r.status .. "  " .. r.step .. " #" .. tostring(r.seq)
            .. (r.message and (" " .. oneLine(r.message)) or "")
    end
    return first, lines
end

function A.writeResult(first, lines)
    local out = { first }
    for _, line in ipairs(lines or {}) do out[#out + 1] = line end
    out[#out + 1] = "RST-END"
    local ok, why = RST.writeLines(A.RESULT_FILE, out)
    if not ok then log("ERROR: result not written: " .. tostring(why)) end
end

-- ---------------------------------------------------------------- end of the launch

local quitState = nil

local function quitTick()
    local q = quitState
    if not q then return end
    if nowMs() < q.at then return end
    if q.step == "shot" then
        q.step = "quit"
        q.at = nowMs() + 1500
        local ok, err = pcall(takeScreenshot, "autoclient-" .. A._cmd.token .. ".png")
        if not ok then log("screenshot failed: " .. oneLine(err)) end
        return
    end
    quitState = nil
    Events.OnTickEvenPaused.Remove(quitTick)
    A.status("quit", "quitToDesktop")
    getCore():quitToDesktop()
end

-- Screenshot (in game, when asked) then quit to desktop. In the menu: quit at once.
function A.finish(inGame)
    local cmd = A._cmd
    if cmd and not cmd.quit then
        A.status("done", "quit=false: the game stays open")
        return
    end
    if not inGame then
        A.status("quit", "quitToDesktop from the menu")
        getCore():quitToDesktop()
        return
    end
    quitState = { step = (cmd and cmd.screenshot) and "shot" or "quit", at = nowMs() + 1000 }
    Events.OnTickEvenPaused.Add(quitTick)
end

function A.fail(reason, inGame)
    log("ERROR: " .. reason)
    A.status("error", reason)
    A.writeResult(A.resultLine(nil, nil, reason))
    A.finish(inGame)
end

-- ---------------------------------------------------------------- main menu

local menu = nil
local menuTick

local function stopMenu()
    menu = nil
    Events.OnFETick.Remove(menuTick)
end

-- Presses a vanilla screen button by its "internal" name (what a mouse click on it calls).
local function press(panel, internal)
    return pcall(function() panel:onOptionMouseDown({ internal = internal }, 0, 0) end)
end

local function isVisible(panel)
    if panel == nil then return false end
    local ok, v = pcall(function() return panel:getIsVisible() end)
    return ok and v and true or false
end

local function gameMode()
    local ok, v = pcall(function() return getWorld():getGameMode() end)
    if ok then return v end
    return nil
end

-- MP: ConnectToServer:connect as the "Join server" popup does (ServerConnectPopup.lua:210).
local function join(screen)
    local cmd = A._cmd
    A.status("connect", cmd.host .. ":" .. cmd.port .. " as " .. cmd.user)
    local ok, err = pcall(function()
        ConnectToServer.instance:connect(screen.bottomPanel or screen, "", cmd.user, cmd.password, cmd.host, "",
            cmd.port, "", false, true, 1)
    end)
    if not ok then
        stopMenu()
        A.fail("ConnectToServer.connect failed: " .. oneLine(err), false)
    end
end

-- MP, new Lua state after the connection reset: character creation of a new account, then the loading screen.
local function joinedTick(m, screen)
    local now = nowMs()
    if m.phase == "create" then
        if now < m.at then return end
        stopMenu()
        local main = screen and screen.charCreationMain or nil
        local ok, err = press(main, "NEXT")
        if not ok then
            A.fail("character creation: NEXT of CharacterCreationMain failed: " .. oneLine(err), false)
            return
        end
        A.status("load", "character created; loading the server world")
        return
    end
    local profession = screen and screen.charCreationProfession or nil
    if isVisible(profession) then
        A.status("create", "character creation shown by ConnectToServer:OnConnected")
        local ok, err = press(profession, "NEXT")
        if not ok then
            stopMenu()
            A.fail("character creation: NEXT of CharacterCreationProfession failed: " .. oneLine(err), false)
            return
        end
        m.phase = "create"
        m.at = now + A.CREATE_STEP_MS
        return
    end
    if now - m.at >= A.JOIN_MENU_MS and gameMode() ~= "Multiplayer" then
        stopMenu()
        A.fail("connection lost: back on the main menu without a character creation", false)
        return
    end
    if now - m.at >= A.JOIN_LOAD_MS then
        -- No creation screen: an existing character of this account goes straight to the loading screen.
        stopMenu()
        A.status("load", "no character creation (existing character?): loading")
    end
end

menuTick = function()
    local m = menu
    if not m then return end
    local screen = MainScreen and MainScreen.instance or nil
    if m.phase == "joined" or m.phase == "create" then
        joinedTick(m, screen)
        return
    end
    if m.phase == "joining" then return end -- OnConnectFailed or the Lua reset of the connection ends this state
    if m.phase == "wait" then
        if screen == nil then return end
        if m.at == nil then m.at = nowMs() + A.MENU_DELAY_MS end
        if nowMs() < m.at then return end
        if A._cmd.mp then
            m.phase = "joining"
            join(screen)
            return
        end
        m.phase = "asked"
        m.at = nowMs()
        A.status("load", A._cmd.mode .. "/" .. A._cmd.save)
        local ok, err = pcall(MainScreen.continueLatestSave, A._cmd.mode, A._cmd.save)
        if not ok then
            stopMenu()
            A.fail("MainScreen.continueLatestSave failed: " .. oneLine(err), false)
        end
        return
    end
    -- After the request: the menu only stays when vanilla refused the save with a dialog.
    if screen ~= nil and screen.checkSavefileModal ~= nil then
        stopMenu()
        A.fail("the main menu refused the save (save error dialog: missing mod, map or version)", false)
    end
end

-- MP: called in the new Lua state after the connection reset (OnMainMenuEnter, or the load of this file).
local function startJoined()
    if menu then return end
    A.status("menu", "Lua reset of the connection; waiting for the character creation")
    menu = { phase = "joined", at = nowMs() }
    Events.OnFETick.Add(menuTick)
end

local function onMainMenuEnter()
    local cmd = A.command()
    if not cmd then
        if A._invalid and not A._invalidReported then
            A._invalidReported = true
            A.writeResult(A.resultLine(nil, nil, "autoclient.txt refused: " .. A._invalid))
        end
        return
    end
    muteDebugger()
    if A.hasStatus("ingame") then
        -- Back at the menu after the game (exitToMenu by a test or a crash of the run): never load again.
        A.status("menu", "back at the main menu after the game")
        A.finish(false)
        return
    end
    if menu then return end
    if cmd.mp and A.hasStatus("connect") then
        if A.hasStatus("load") then return end -- loading screen asked: vanilla goes on
        startJoined()
        return
    end
    if not cmd.mp and A.hasStatus("load") then
        -- New Lua state after the reset asked by continueLatestSaveAux: vanilla goes on (onResetLua).
        A.status("menu", "Lua reset for the save mods; vanilla continues the load")
        menu = { phase = "asked", at = nowMs() }
    else
        A.status("menu", "main menu reached")
        menu = { phase = "wait" }
    end
    Events.OnFETick.Add(menuTick)
end

-- MP, account with a character already on the server (reconnection, E01-T17): vanilla ConnectToServer:OnConnected
-- skips the character creation and switches to LoadingQueueState at once (ConnectToServer.lua:291-293), so OnFETick
-- stops before the JOIN_LOAD_MS fallback: the loading screen is announced here (the launcher then clicks it).
local function onConnected()
    local cmd = A._cmd
    if not cmd or not cmd.mp or not A.hasStatus("connect") or A.hasStatus("load") or A.hasStatus("ingame") then return end
    local ok, exists = pcall(checkSavePlayerExists)
    if not ok or not exists then return end
    if menu then stopMenu() end
    A.status("load", "existing character of the account: loading")
end

local function onConnectFailed(message, detail)
    local cmd = A._cmd
    if not cmd or not cmd.mp or A.hasStatus("ingame") then return end
    if menu then stopMenu() end
    A.fail("connection refused: " .. oneLine(message) .. (detail and (" (" .. oneLine(detail) .. ")") or ""), false)
end

-- ---------------------------------------------------------------- in game

local game = nil
local gameTick

local function startRun(cmd)
    if cmd.campaign then
        return RST.campaign(cmd.campaign)
    end
    return RST.run({ suite = cmd.suites, tags = cmd.tags, exclude = cmd.exclude })
end

-- Filter of the server run: serverCampaign = its suites, manual suites excluded (prefix selection would take them).
-- index: run number for serverSuite= with several ";"-separated runs (default 1).
function A.serverFilter(cmd, index)
    if cmd.serverCampaign then
        local list = RST.CAMPAIGNS and RST.CAMPAIGNS[cmd.serverCampaign] or nil
        if type(list) ~= "table" or #list == 0 then return nil, "unknown or empty campaign " .. cmd.serverCampaign end
        local suites = {}
        for i, name in ipairs(list) do suites[i] = name end
        return { suite = suites, exclude = { "manual" } }
    end
    local suites = cmd.serverRuns and cmd.serverRuns[index or 1] or cmd.serverSuites
    return { suite = suites, tags = cmd.serverTags, exclude = cmd.serverExclude }
end

-- Number of server runs asked by the command (0, 1, or the ";"-separated runs of serverSuite=).
function A.serverRunCount(cmd)
    if cmd.serverRuns then return #cmd.serverRuns end
    if cmd.serverCampaign or cmd.serverSuites then return 1 end
    return 0
end

-- Answers of the server to our requests (RST_Server.lua), by request id. A "started" never replaces a final answer
-- (the commands are not ordered).
A._answers = A._answers or {}

function A.onServerCommand(module, command, args)
    if module ~= "RST" or type(args) ~= "table" or args.id == nil then return end
    local old = A._answers[args.id]
    if old ~= nil and command == "started" then return end
    A._answers[args.id] = { command = command, args = args }
end

local COUNTERS = { "total", "pass", "fail", "error", "skip", "empty", "durationMs" }

-- First line and lines of the result from the client report (or nil) and the server payload (or nil), or the list
-- of server payloads of successive runs (E01-T17), summed in order.
function A.compose(clientReport, clientLines, clientFile, server, reason)
    local sum = { ok = true }
    for _, k in ipairs(COUNTERS) do sum[k] = 0 end
    local lines = {}
    if clientReport then
        sum.ok = clientReport.ok and true or false
        for _, k in ipairs(COUNTERS) do sum[k] = sum[k] + (tonumber(clientReport[k]) or 0) end
        for _, line in ipairs(clientLines or {}) do lines[#lines + 1] = line end
    end
    local payloads = {}
    if server and server[1] ~= nil then payloads = server elseif server then payloads = { server } end
    local files = {}
    for _, srv in ipairs(payloads) do
        sum.ok = sum.ok and srv.ok and true or false
        for _, k in ipairs(COUNTERS) do sum[k] = sum[k] + (tonumber(srv[k]) or 0) end
        lines[#lines + 1] = "SERVER " .. tostring(srv.summary or "")
        for _, line in ipairs(srv.failures or {}) do lines[#lines + 1] = "SERVER " .. tostring(line) end
        if srv.truncated then
            lines[#lines + 1] = "SERVER " .. ((tonumber(srv.failuresTotal) or 0) - #(srv.failures or {}))
                .. " more failure line(s) in the server report"
        end
        if srv.written and srv.file then files[#files + 1] = tostring(srv.file) end
    end
    local serverFile = #files > 0 and table.concat(files, ",") or nil
    return A.resultLine(sum, clientFile, reason, serverFile), lines
end

local function endGame()
    game = nil
    Events.OnTick.Remove(gameTick)
end

local function finishRun(g, reason)
    local first, lines = A.compose(g.clientReport, g.clientLines, g.clientFile, g.servers, reason)
    A.writeResult(first, lines)
    A.status("done", first)
    if A._cmd.control then
        g.phase = "quitwait"
        return
    end
    endGame()
    A.finish(true)
end

local function startServerRun(g)
    local cmd = A._cmd
    g.serverRun = (g.serverRun or 0) + 1
    g.servers = g.servers or {}
    local filter, why = A.serverFilter(cmd, g.serverRun)
    if not filter then
        finishRun(g, "server run not started: " .. why)
        return
    end
    local ok, started, reason = pcall(RST.server, filter)
    if not ok or not started then
        finishRun(g, "server run not started: " .. oneLine(ok and reason or started))
        return
    end
    g.serverId = RST.Client and RST.Client.serverSeq or nil
    g.phase = "server"
    g.deadline = nowMs() + cmd.serverTimeoutMs
    local runs = A.serverRunCount(cmd)
    A.status("server", "request #" .. tostring(g.serverId) .. (runs > 1 and (" run " .. g.serverRun .. "/" .. runs) or "")
        .. " " .. (cmd.serverCampaign and ("campaign " .. cmd.serverCampaign) or ("suites " .. table.concat(filter.suite, ","))))
end

local function wantsServer(cmd)
    return cmd.serverSuites ~= nil or cmd.serverCampaign ~= nil
end

local function begin(g)
    local cmd = A._cmd
    if cmd.idle then
        A.status("idle", "connected, nothing to run")
        g.phase = "quitwait"
        if not cmd.control then
            endGame()
            A.finish(true)
        end
        return
    end
    if cmd.campaign == nil and cmd.suites == nil then
        startServerRun(g)
        return
    end
    g.phase = "run"
    local what = cmd.campaign and ("campaign " .. cmd.campaign) or ("suites " .. table.concat(cmd.suites, ","))
    local ok, started, reason = pcall(startRun, cmd)
    if not ok or not started then
        endGame()
        A.fail("run not started (" .. what .. "): " .. oneLine(ok and reason or started), true)
        return
    end
    A.status("run", what)
end

-- E01-T17, phase reconnect2: a client kept connected while another one reconnects gets a new command (new token, new
-- runs) in autoclient.txt and the word "reload" in the control file, instead of "quit". Once its run is over
-- (phase quitwait), the command is read again: same token = nothing new (false); new token = status "ingame" for
-- that token, results of the previous run forgotten, steps answered so far cleared, then "go" is awaited as after a
-- connection (true). An invalid new command fails the launch.
function A.reload(g)
    local old = A._cmd
    A._cmdRead, A._cmd, A._invalid = false, nil, nil
    local cmd = A.command()
    if cmd == nil then
        A._cmd, A._cmdRead = old, true
        A.fail("reload refused: " .. tostring(A._invalid or "autoclient.txt missing"), true)
        endGame()
        return true
    end
    if cmd.token == old.token then
        A._cmd = old
        return false
    end
    if not cmd.mp or not cmd.control then
        A._cmd = old
        A.fail("reload refused: the new command needs connect= and control=true", true)
        endGame()
        return true
    end
    if RST.Steps then RST.Steps.records = {} end
    A._controlAt = nil
    g.phase, g.clientReport, g.clientLines, g.clientFile = "go", nil, nil, nil
    g.servers, g.serverRun, g.serverId, g.deadline = nil, nil, nil, nil
    A.status("ingame", "reload: same connection, new command")
    return true
end

gameTick = function()
    local g = game
    if not g then return end
    local cmd = A._cmd
    if g.phase == "wait" then
        if nowMs() < g.at then return end
        if cmd.control then
            g.phase = "go"
        else
            begin(g)
        end
        return
    end
    if g.phase == "go" then
        if not A.control("go") then return end
        A.status("go", "control file")
        begin(g)
        return
    end
    if g.phase == "run" then
        if RST.running() then return end
        local report = RST._last
        local client = RST.Client or {}
        g.clientReport = report
        g.clientLines = (client.lastReport == report and client.lastLines) or (report and RST.formatReport(report)) or {}
        g.clientFile = client.lastFile
        if wantsServer(cmd) then
            startServerRun(g)
        else
            finishRun(g)
        end
        return
    end
    if g.phase == "server" then
        local answer = g.serverId and A._answers[g.serverId] or nil
        if answer and answer.command == "report" then
            g.servers[#g.servers + 1] = answer.args
            if g.serverRun < A.serverRunCount(cmd) then
                startServerRun(g)
            else
                finishRun(g)
            end
        elseif answer and answer.command ~= "started" then
            finishRun(g, "server run " .. answer.command .. ": " .. oneLine(answer.args.reason))
        elseif nowMs() >= g.deadline then
            finishRun(g, "no server report after " .. math.floor(cmd.serverTimeoutMs / 1000) .. " s")
        end
        return
    end
    if g.phase == "quitwait" then
        if A.control("reload") and A.reload(g) then return end
        if not A.control("quit") then return end
        if cmd.peer then
            local first, lines = A.peerResult()
            A.writeResult(first, lines)
            A.status("done", first)
        end
        endGame()
        A.finish(true)
    end
end

-- ---------------------------------------------------------------- MP death: respawn with a new character

local respawnTick

-- Status line that keeps the current state (the launcher reacts to states, not to details).
local function respawnStatus(detail)
    A.status(A._state or "ingame", "respawn: " .. detail)
end

function A.onPlayerDeath(player)
    local cmd = A._cmd
    if not cmd or not cmd.mp or A._respawn then return end
    local ok, num = pcall(function() return player:getPlayerNum() end)
    if not ok or num ~= 0 then return end
    local now = nowMs()
    A._respawn = { phase = "post", at = now + A.RESPAWN_DELAY_MS, deadline = now + A.RESPAWN_TIMEOUT_MS, dead = player }
    respawnStatus("local player died; Respawn in " .. math.floor(A.RESPAWN_DELAY_MS / 1000) .. " s")
    if Events.OnTickEvenPaused then Events.OnTickEvenPaused.Add(respawnTick) end
end

-- One tick of the respawn (true when over). r = A._respawn.
function A.respawnStep(r)
    local now = nowMs()
    if now >= r.deadline then
        respawnStatus("FAILED in phase " .. r.phase .. " after " .. math.floor(A.RESPAWN_TIMEOUT_MS / 1000) .. " s")
        return true
    end
    if r.phase == "post" then
        if now < r.at then return false end
        local ui = ISPostDeathUI and ISPostDeathUI.instance and ISPostDeathUI.instance[0] or nil
        if ui == nil then return false end
        local ok, err = pcall(function() ui:onRespawn() end)
        if not ok then log("ERROR: ISPostDeathUI:onRespawn raised: " .. oneLine(err)) return false end
        r.phase = "create"
        respawnStatus("Respawn pressed")
        return false
    end
    local w = CoopCharacterCreation and CoopCharacterCreation.instance or nil
    if r.phase == "create" then
        if w == nil then return false end
        if isVisible(w.mapSpawnSelect) then
            pcall(function() w.mapSpawnSelect:clickNext() end)
            return false
        end
        if isVisible(w.charCreationProfession) then
            press(w.charCreationProfession, "NEXT")
            r.phase, r.at = "main", now + A.CREATE_STEP_MS
            respawnStatus("NEXT on the profession screen")
        end
        return false
    end
    if r.phase == "main" then
        if now < r.at then return false end
        if w ~= nil and isVisible(w.charCreationMain) then
            press(w.charCreationMain, "NEXT")
            r.phase = "spawned"
            respawnStatus("NEXT on the character screen")
        end
        return false
    end
    local p = getSpecificPlayer(0)
    if p ~= nil and p ~= r.dead and not p:isDead() then
        local okN, name = pcall(function()
            return p:getDescriptor():getForename() .. " " .. p:getDescriptor():getSurname()
        end)
        respawnStatus("new character " .. (okN and tostring(name) or "?") .. " in game")
        return true
    end
    return false
end

respawnTick = function()
    local r = A._respawn
    if r == nil or A.respawnStep(r) then
        A._respawn = nil
        Events.OnTickEvenPaused.Remove(respawnTick)
    end
end

local function onGameStart()
    local cmd = A.command()
    if not cmd or game then return end
    if not A.hasStatus("load") or A.hasStatus("ingame") then return end
    muteDebugger()
    A.status("ingame", "save " .. tostring(getWorld():getWorld()))
    game = { phase = "wait", at = nowMs() + cmd.startDelayMs }
    Events.OnTick.Add(gameTick)
end

-- ---------------------------------------------------------------- subscriptions (once per Lua state)

if not A._subscribed and type(Events) == "table" then
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(onMainMenuEnter) end
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
    if Events.OnConnectFailed then Events.OnConnectFailed.Add(onConnectFailed) end
    if Events.OnConnected then Events.OnConnected.Add(onConnected) end
    if Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(function(player) RST.AutoClient.onPlayerDeath(player) end)
    end
    if Events.OnServerCommand then
        Events.OnServerCommand.Add(function(module, command, args) RST.AutoClient.onServerCommand(module, command, args) end)
    end
    A._subscribed = true
    -- MP: when the connection reset does not fire OnMainMenuEnter, the new Lua state goes on from here.
    local cmd = A.command()
    if cmd and cmd.mp and A.hasStatus("connect") and not A.hasStatus("load") and not A.hasStatus("ingame") then
        startJoined()
    end
end

return A
