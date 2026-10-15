--[[
RST_Client — console launcher of the in-game test engine (client and solo). Development mod only.

From the Lua console (debug mode, key "²" / "`"):
    RST.run()                  every suite except those tagged "server" or "world"
    RST.run("rst")             suites "rst" and "rst.*" (same exclusion)
    RST.run({ suite = "rs", tags = "world" })   explicit table filter: see the rule below
    RST.list(filter)           prints the registered suites (core, RST.lua)
    RST.last()                 prints the lines of the last report and returns the report object
    RST.cancel()               stops the current run (core)
    RST.server(filter)         runs the "server" and "shared" suites on the server (see RST_Server.lua)
    RST.lastServer()           prints the last server report received and returns it

RST.server(filter) -> true, or false and a reason (also printed). Refused when isDebugEnabled() is false or when
the filter cannot travel through the network (RST.checkFilter: strings only, no function). Effective filter on
the server: RST.Server.effectiveFilter (tags server/shared, world excluded by default, client always excluded).
    MP client  sendClientCommand("RST", "run", { id, filter }); the server checks the DebugConsole capability
               (admin role included), answers started / denied / busy / refused, then "report": summary and at most
               40 failure lines, printed here and kept by RST.lastServer(). The full report is the server file
               Zomboid/Lua/batman_RadioSurvivor/tests/<stamp>-server.txt in the server cache folder.
    solo       same code path without network: RST.Server.runSuites in this Lua state, file <stamp>-server.txt
               in the local Zomboid/Lua, then the same "report" handler. "Break On Error" is switched off as for
               RST.run. RST.run and RST.server share one run (RST._run): the second one is refused.
    A client run (RST.run) and a server run coexist in MP: they run in separate Lua states.

Default filter rule (RST.effectiveFilter)
    nil or a string            gets exclude = { "server", "world" }: server suites belong to RST.server (E01-T05),
                               world suites need a test save and fixtures (E01-T06).
    a table without "tags" and without "exclude"
                               gets the same exclusion (a copy; the caller's table is not modified).
    a table with "tags" or "exclude" (even an empty exclude = {})
                               is used as given: this is the explicit request to include server or world suites.

RST.run(filter) -> true, or false and a reason (also printed). Refused when isDebugEnabled() is false, when a run
is already in progress, or when the core refuses to start. During the run, the Lua debugger "Break On Error"
(UIManager.setShowLuaDebuggerOnError) is switched off and the previous value is restored at the end, on cancel,
when the start is refused and when the launcher itself fails.

End of a run: report lines (RST.formatReport) with a header (game version, side, save name, filter, date, active
mods) printed line by line, a short summary above the player, and a file written through getFileWriter:
    Zomboid/Lua/batman_RadioSurvivor/tests/<YYYYMMDD-HHMMSS>-client.txt   (UTC time; getFileWriter creates folders)
Context of the tests (t.ctx): { side = "client" or "solo", player = getPlayer() } (target of RST.Fixtures).
The path is printed. Loading this file starts no run: it defines functions and subscribes OnServerCommand once.
Suites live in shared/RST/suites/*.lua: the game runs every shared file before client files, and each suite file
does require "RST/RST" (executed once). Declaring a suite again (reload) replaces it.
]]

require "RST/RST"

RST.Client = RST.Client or {}
local C = RST.Client

C.FILE_DIR = RST.FILE_DIR
C.DEFAULT_EXCLUDE = { "server", "world" }

local function log(msg)
    print("[RST] " .. msg)
end

local function safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- ---------------------------------------------------------------- environment

local function sideName()
    if type(isClient) == "function" and isClient() then return "client" end
    return "solo"
end

-- Kept for the console and the tests: the implementations live in the shared core (RST.lua).
C.stampFromMs = RST.stampFromMs
C.stamp = RST.stamp

-- ---------------------------------------------------------------- filter

local function hasField(t, k)
    return rawget(t, k) ~= nil
end

-- Applies the default exclusion rule described in the header. Returns a new filter.
function C.effectiveFilter(filter)
    if filter == nil then
        return { exclude = C.DEFAULT_EXCLUDE }
    end
    if type(filter) == "string" then
        return { suite = filter, exclude = C.DEFAULT_EXCLUDE }
    end
    if type(filter) ~= "table" then
        return filter -- refused later by the core with its own message
    end
    local copy = {}
    for _, k in ipairs({ "suite", "test", "tags", "exclude" }) do
        copy[k] = filter[k]
    end
    if not hasField(filter, "tags") and not hasField(filter, "exclude") then
        copy.exclude = C.DEFAULT_EXCLUDE
    end
    return copy
end

-- ---------------------------------------------------------------- "Break On Error"

local function debuggerApi()
    if UIManager == nil then return nil end
    local ok, has = pcall(function()
        return UIManager.isShowLuaDebuggerOnError ~= nil and UIManager.setShowLuaDebuggerOnError ~= nil
    end)
    if ok and has then return UIManager end
    return nil
end

-- Switches "Break On Error" off; remembers the previous value once (RST.Client.savedBreak).
local function muteDebugger()
    local ui = debuggerApi()
    if not ui then return end
    local ok, was = pcall(ui.isShowLuaDebuggerOnError)
    if not ok then return end
    if C.savedBreak == nil then
        C.savedBreak = was and true or false
    end
    if was then
        pcall(ui.setShowLuaDebuggerOnError, false)
        log("Break On Error switched off for the run")
    end
end

-- Restores the value saved by muteDebugger (no-op when nothing was saved).
function C.restoreDebugger()
    local saved = C.savedBreak
    if saved == nil then return end
    C.savedBreak = nil
    local ui = debuggerApi()
    if ui and saved then
        pcall(ui.setShowLuaDebuggerOnError, true)
        log("Break On Error restored")
    end
end

-- ---------------------------------------------------------------- report output

function C.header(info, report)
    return RST.reportHeader(info)
end

C.writeLines = RST.writeLines

local function summary(report, prefix)
    return (prefix or "RST ") .. (report.ok and "OK" or "FAILED") .. ": " .. report.pass .. "/" .. report.total .. " pass, "
        .. report.fail .. " fail, " .. report.error .. " error, " .. report.empty .. " empty"
end

local function showOverhead(report, prefix)
    local player = type(getPlayer) == "function" and safe(getPlayer) or nil
    if not player or type(HaloTextHelper) == "nil" then return end
    local text = summary(report, prefix)
    if report.ok then
        pcall(HaloTextHelper.addGoodText, player, text)
    else
        pcall(HaloTextHelper.addBadText, player, text)
    end
end

-- End of a client run: restore the debugger first, then report (each step protected).
local function finish(info, report)
    C.restoreDebugger()
    local lines = RST.formatReport(report, C.header(info, report))
    C.lastReport, C.lastLines = report, lines
    for _, line in ipairs(lines) do
        print("[RST] " .. line)
    end
    local path = C.FILE_DIR .. info.stamp .. "-" .. info.side .. ".txt"
    local ok, reason = C.writeLines(path, lines)
    if ok then
        C.lastFile = path
        log("report written: Zomboid/Lua/" .. path)
    else
        C.lastFile = nil
        log("ERROR: report not written: " .. tostring(reason))
    end
    showOverhead(report)
end

-- ---------------------------------------------------------------- commands

local function refuse(reason)
    log("run refused: " .. reason)
    return false, reason
end

function RST.run(filter)
    if type(isDebugEnabled) ~= "function" or not isDebugEnabled() then
        return refuse("debug mode is off (start the game with -debug); no test was run")
    end
    if RST.running() then
        return refuse("a run is already in progress (RST.cancel() stops it)")
    end
    local ok, started, reason = pcall(function()
        local info = RST.runInfo(filter, C.effectiveFilter(filter), sideName())
        muteDebugger()
        return RST.start(info.effective, {
            ctx = { side = info.side, player = type(getPlayer) == "function" and safe(getPlayer) or nil },
            onDone = function(report) finish(info, report) end,
        })
    end)
    if not ok then
        C.restoreDebugger()
        return refuse("launcher error: " .. tostring(started))
    end
    if not started then
        C.restoreDebugger()
        return false, reason
    end
    return true
end

-- Prints the lines of the last report and returns the report object (nil before any run).
function RST.last()
    local report = RST._last
    if not report then
        log("no report yet")
        return nil
    end
    local lines = (C.lastReport == report and C.lastLines) or RST.formatReport(report)
    for _, line in ipairs(lines) do
        print("[RST] " .. line)
    end
    if C.lastReport == report and C.lastFile then log("file: Zomboid/Lua/" .. C.lastFile) end
    return report
end

-- ---------------------------------------------------------------- server suites (E01-T05)

C.serverSeq = C.serverSeq or 0

local function printServerReport(p)
    log("server report" .. (p.id and (" #" .. tostring(p.id)) or "") .. ": "
        .. tostring(p.summary or ((p.ok and "OK" or "FAILED") .. " - " .. tostring(p.total) .. " test(s)")))
    local failures = p.failures or {}
    for _, line in ipairs(failures) do
        log("server " .. tostring(line))
    end
    if p.truncated then
        log("server: " .. (tonumber(p.failuresTotal) or 0) - #failures .. " more failure line(s) in the server file")
    end
    if p.written and p.file then
        log("server file: Zomboid/Lua/" .. tostring(p.file) .. " (server cache folder)")
    else
        log("server file: not written")
    end
end

-- OnServerCommand handler (module "RST"). Also called directly in solo.
function C.onServerCommand(module, command, args)
    if module ~= "RST" then return end
    args = type(args) == "table" and args or {}
    local tag = args.id and (" #" .. tostring(args.id)) or ""
    if command == "report" then
        C.lastServerReport = args
        printServerReport(args)
        showOverhead(args, "RST server ")
    elseif command == "started" then
        log("server run" .. tag .. " started: " .. tostring(args.total) .. " test(s)")
    elseif command == "denied" or command == "busy" or command == "refused" then
        log("server run" .. tag .. " " .. command .. ": " .. tostring(args.reason))
    end
end

local function soloServerRun(filter, id)
    if RST.Server == nil or type(RST.Server.runSuites) ~= "function" then
        return refuse("RST_Server.lua is not loaded (server Lua)")
    end
    if RST.running() then
        return refuse("a run is already in progress (RST.cancel() stops it)")
    end
    local ok, started, reason = pcall(function()
        muteDebugger()
        return RST.Server.runSuites(filter, function(result)
            C.restoreDebugger()
            C.onServerCommand("RST", "report", RST.Server.payload(result, id))
        end, { side = "solo (server suites, no network)",
            player = type(getPlayer) == "function" and safe(getPlayer) or nil })
    end)
    if not ok then
        C.restoreDebugger()
        return refuse("launcher error: " .. tostring(started))
    end
    if not started then
        C.restoreDebugger()
        return refuse(tostring(reason))
    end
    log("server suites started in this game (solo, no network)")
    return true
end

function RST.server(filter)
    if type(isDebugEnabled) ~= "function" or not isDebugEnabled() then
        return refuse("debug mode is off (start the game with -debug); no test was run")
    end
    local okFilter, why = RST.checkFilter(filter)
    if not okFilter then
        return refuse("filter cannot be sent to the server: " .. why)
    end
    C.serverSeq = C.serverSeq + 1
    local id = C.serverSeq
    if type(isClient) == "function" and isClient() then
        local player = type(getPlayer) == "function" and safe(getPlayer) or nil
        if not player then return refuse("no local player to send the request") end
        local sent, err = pcall(sendClientCommand, player, "RST", "run", { id = id, filter = RST.copyFilter(filter) })
        if not sent then return refuse("request not sent: " .. tostring(err)) end
        log("server run #" .. id .. " requested; the report will be printed here")
        return true
    end
    return soloServerRun(RST.copyFilter(filter), id)
end

-- Prints the last server report received and returns it (nil before any).
function RST.lastServer()
    local p = C.lastServerReport
    if not p then
        log("no server report yet")
        return nil
    end
    printServerReport(p)
    return p
end

-- One subscription per Lua state (survives a reload of this file: the dispatcher reads C.onServerCommand).
if not C._serverSubscribed and type(Events) == "table" and type(Events.OnServerCommand) == "table" then
    Events.OnServerCommand.Add(function(module, command, args)
        RST.Client.onServerCommand(module, command, args)
    end)
    C._serverSubscribed = true
end
