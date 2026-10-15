--[[
RST_Server — server side of the in-game test engine: runs the "server" and "shared" suites on request of a client
(RST.server(filter) in RST_Client.lua). Development mod only.

Network (module "RST")
    client -> server   run      { id = number, filter = nil | string | { suite, test, tags, exclude } }
    server -> client   started  { id, total }                       run accepted, number of selected tests
                       denied   { id, reason }                      the account lacks the right (logged)
                       busy     { id, reason }                      a run is already in progress on the server
                       refused  { id, reason }                      bad filter, or the core refused to start
                       report   { id, ok, total, pass, fail, error, skip, empty, durationMs, summary,
                                  file, written, failures = { line, ... }, failuresTotal, truncated }
    Only the requester gets answers (sendServerCommand(player, ...)). Commands are RELIABLE but not ordered: a
    "started" may arrive after its "report" (rare); the client matches answers by id. "file" is relative to the
    Lua cache folder of the server (Zomboid/Lua), never an absolute path.

Right: checkPermissions(player, Capability.DebugConsole) AND player:getRole():hasCapability(...). On a server,
checkPermissions reads the role of the connection (AntiCheatCapability.validate) but returns true when the
connection is missing; the IsoPlayer role is the connection role copied at login and on every role change. The
built-in "admin" role holds every capability, DebugConsole included. Outside a server (solo) RST.server runs
RST.Server.runSuites directly, without network and without this check.

Effective filter (RST.Server.effectiveFilter)
    nil / string / table without tags: tags = { "server", "shared" } (untagged suites never run here).
    nil / string / table without tags and without exclude: exclude = { "world" } (fixtures and test save: E01-T06).
    Explicit tags or exclude are kept; "client" is ALWAYS added to exclude: client suites never run on the server.

Context of the tests (t.ctx): { side = "server" or "solo", player = requester IsoPlayer (nil for a run started
without a requester, E01-T07) }. The IsoPlayer is the one of the request: a reconnection during the run makes it stale.
Reuse (E01-T07): RST.Server.runSuites(filter, onDone, info) starts a run and calls onDone(result) at the end with
    { report, lines, file, written, reason }; RST.Server.payload(result, id) builds the bounded network summary.
One run at a time for the whole Lua state: on a dedicated server the client VMs are separate (RST.run on a client
and a server run coexist); in solo RST.run and RST.server share RST._run and the second one is refused.
Loading this file subscribes OnClientCommand and OnServerStarted once (idempotent); it starts nothing.

Automatic run on a dedicated server (E01-T07, tests/run_dedicated_smoke.ps1)
    At OnServerStarted (GameServer.startServer, dedicated server only), when the file
    Zomboid/Lua/batman_RadioSurvivor/tests/autorun.txt exists in the cache folder of the server (getFileReader, read
    only: never changed nor removed), the server suites run once without a requester (t.ctx.player is nil: fixtures
    raise "no target player"; the default filter excludes the "world" suites anyway). Format of autorun.txt (UTF-8):
        # comment                 lines starting with "#" (after leading spaces) are ignored, as are empty lines
        rst                       one suite name or dot-separated prefix per line (same rule as the string filter),
        rs.codec                  surrounding spaces trimmed; the lines are ORed: { suite = { "rst", "rs.codec" } }
    No filter line at all = every "server" / "shared" suite. A line holding a space is refused. Nothing else is read
    (no Lua, no loadstring). The run is asynchronous (OnTickEvenPaused, which also runs while an empty server is
    paused by PauseEmpty). At the end the usual report is written (<stamp>-server.txt) and
    Zomboid/Lua/batman_RadioSurvivor/tests/autorun-result.txt, once per Lua state:
        RST-RESULT ok=true total=3 pass=3 fail=0 error=0 skip=0 empty=0 durationMs=2104 report=batman_...txt
        <the usual report lines>
        RST-END
    First line: key=value pairs separated by single spaces, in this order (report= only when the report file was
    written); an optional last pair reason=<text up to the end of the line> explains a refusal (bad file, run not
    started: counters at 0) or "no test selected". ok is true only when the report is OK AND at least one test ran
    (a filter that selects nothing is a failure). The last line "RST-END" tells a reader that the file is complete.
    Without autorun.txt nothing happens.
]]

require "RST/RST"

RST.Server = RST.Server or {}
local S = RST.Server

S.DEFAULT_TAGS = { "server", "shared" }
S.DEFAULT_EXCLUDE = { "world" }
S.ALWAYS_EXCLUDE = "client"
S.MAX_FAILURE_LINES = 40
S.MAX_LINE_LEN = 300
S.CAPABILITY = "DebugConsole"

local function log(msg)
    print("[RST] " .. msg)
end

local function oneLine(s)
    s = string.gsub(tostring(s), "\r", "")
    s = string.gsub(s, "\n", " / ")
    return s
end

local function bounded(s, maxLen)
    s = oneLine(s)
    if string.len(s) > maxLen then
        return string.sub(s, 1, maxLen - 3) .. "..."
    end
    return s
end

local function isServerSide()
    return type(isServer) == "function" and isServer() and true or false
end

local function copyList(v)
    if v == nil then return nil end
    if type(v) ~= "table" then return { v } end
    local out = {}
    for i, item in ipairs(v) do out[i] = item end
    return out
end

-- ---------------------------------------------------------------- filter

-- Applies the server rule described in the header. Returns a new filter (the argument is not modified).
function S.effectiveFilter(filter)
    local f
    if filter == nil then
        f = {}
    elseif type(filter) == "string" then
        f = { suite = filter }
    elseif type(filter) == "table" then
        f = RST.copyFilter(filter)
    else
        return filter -- refused by the core with its own message
    end
    local explicitTags = f.tags ~= nil
    if not explicitTags then f.tags = copyList(S.DEFAULT_TAGS) end
    local exclude = copyList(f.exclude)
    if exclude == nil then
        exclude = explicitTags and {} or copyList(S.DEFAULT_EXCLUDE)
    end
    local has = false
    for _, tag in ipairs(exclude) do
        if tag == S.ALWAYS_EXCLUDE then has = true end
    end
    if not has then exclude[#exclude + 1] = S.ALWAYS_EXCLUDE end
    f.exclude = exclude
    return f
end

-- ---------------------------------------------------------------- right

local function username(player)
    if player == nil then return "?" end
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return "?"
end

-- Returns true when the player may run the server suites (see the header).
function S.allowed(player)
    if player == nil or Capability == nil then return false end
    local cap = Capability[S.CAPABILITY]
    if cap == nil then return false end
    if type(checkPermissions) ~= "function" then return false end
    local ok, permitted = pcall(checkPermissions, player, cap)
    if not ok or not permitted then return false end
    local okRole, has = pcall(function()
        local role = player:getRole()
        return role ~= nil and role:hasCapability(cap)
    end)
    return okRole and has and true or false
end

-- ---------------------------------------------------------------- run

-- End of a server run: text report (header, one line per test, summary) written to
-- Zomboid/Lua/batman_RadioSurvivor/tests/<stamp>-server.txt. Returns the result table.
function S.finish(info, report)
    local lines = RST.formatReport(report, RST.reportHeader(info))
    for _, line in ipairs(lines) do
        print("[RST] " .. line)
    end
    local path = RST.FILE_DIR .. info.stamp .. "-server.txt"
    local written, reason = RST.writeLines(path, lines)
    if written then
        log("report written: Zomboid/Lua/" .. path)
    else
        log("ERROR: report not written: " .. tostring(reason))
    end
    local result = { report = report, lines = lines, file = path, written = written and true or false,
        reason = reason }
    S.lastResult = result
    return result
end

-- Starts the server suites. Returns true, or false and a reason ("busy: ..." when a run is in progress).
-- onDone(result) is called once at the end (see S.finish). info (optional) may hold requester, side and player
-- (IsoPlayer of the requester, exposed as t.ctx.player: target of RST.Fixtures on the server).
function S.runSuites(filter, onDone, info)
    if RST.running() then return false, "busy: a run is already in progress" end
    local ok, reason = RST.checkFilter(filter)
    if not ok then return false, reason end
    local effective = S.effectiveFilter(filter)
    local ctxSide = isServerSide() and "server" or "solo"
    local runInfo = RST.runInfo(filter, effective, (info and info.side) or ctxSide)
    runInfo.requester = info and info.requester
    local started, why = RST.start(effective, {
        ctx = { side = ctxSide, player = info and info.player },
        onDone = function(report)
            local result = S.finish(runInfo, report)
            if type(onDone) == "function" then onDone(result) end
        end,
    })
    if not started then return false, why end
    return true
end

-- Network summary of a result: counters, summary line, relative file name and bounded failure lines.
function S.payload(result, id)
    local r = result.report
    local failures, total = {}, 0
    for _, res in ipairs(r.results) do
        if res.status == "FAIL" or res.status == "ERROR" or res.status == "EMPTY" then
            total = total + 1
            if #failures < S.MAX_FAILURE_LINES then
                local line = res.status .. "  " .. res.suite .. " :: " .. res.test
                if res.message and res.message ~= "" then line = line .. " " .. res.message end
                failures[#failures + 1] = bounded(line, S.MAX_LINE_LEN)
            end
        end
    end
    return { id = id, ok = r.ok, total = r.total, pass = r.pass, fail = r.fail, error = r.error, skip = r.skip,
        empty = r.empty, durationMs = r.durationMs, summary = RST.summaryLine(r),
        file = result.written and result.file or nil, written = result.written,
        failures = failures, failuresTotal = total, truncated = total > #failures }
end

-- ---------------------------------------------------------------- network

-- Finds the online player of an account (the IsoPlayer object changes on reconnection). nil when offline.
local function onlinePlayer(name)
    if type(getOnlinePlayers) ~= "function" then return nil end
    local ok, found = pcall(function()
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil and username(p) == name then return p end
        end
        return nil
    end)
    if ok then return found end
    return nil
end

local function send(player, command, args)
    if type(sendServerCommand) ~= "function" then return false end
    local ok, err = pcall(sendServerCommand, player, "RST", command, args)
    if not ok then
        log("ERROR: answer '" .. command .. "' not sent: " .. oneLine(err))
        return false
    end
    return true
end

local function answer(player, command, id, reason)
    send(player, command, { id = id, reason = reason })
end

-- OnClientCommand handler (module "RST", command "run").
function S.onClientCommand(module, command, player, args)
    if module ~= "RST" or command ~= "run" then return end
    local name = username(player)
    local id = type(args) == "table" and type(args.id) == "number" and args.id or nil
    if not S.allowed(player) then
        log("run DENIED for account '" .. name .. "': capability " .. S.CAPABILITY .. " required")
        answer(player, "denied", id, "permission denied: capability " .. S.CAPABILITY .. " (or admin) required")
        return
    end
    if RST.running() then
        log("run refused for account '" .. name .. "': a run is already in progress")
        answer(player, "busy", id, "a run is already in progress on the server")
        return
    end
    local filter = type(args) == "table" and args.filter or nil
    local okFilter, why = RST.checkFilter(filter)
    if not okFilter then
        log("run refused for account '" .. name .. "': " .. why)
        answer(player, "refused", id, why)
        return
    end
    filter = RST.copyFilter(filter)
    local started, reason = S.runSuites(filter, function(result)
        local target = onlinePlayer(name)
        if target == nil then
            log("requester '" .. name .. "' is offline: report kept in the server file only")
            return
        end
        send(target, "report", S.payload(result, id))
    end, { requester = name, player = player })
    if not started then
        log("run refused for account '" .. name .. "': " .. tostring(reason))
        answer(player, "refused", id, tostring(reason))
        return
    end
    log("run started by account '" .. name .. "'")
    local total = RST._run and #RST._run.jobs or 0
    send(player, "started", { id = id, total = total })
end

-- One subscription per Lua state (survives a reload of this file: the dispatcher reads S.onClientCommand).
if not S._subscribed and type(Events) == "table" and type(Events.OnClientCommand) == "table" then
    Events.OnClientCommand.Add(function(module, command, player, args)
        RST.Server.onClientCommand(module, command, player, args)
    end)
    S._subscribed = true
end

-- ---------------------------------------------------------------- automatic run (see the header)

S.AUTORUN_FILE = RST.FILE_DIR .. "autorun.txt"
S.AUTORUN_RESULT = RST.FILE_DIR .. "autorun-result.txt"
S.AUTORUN_MAX_LINES = 500
S.RESULT_PREFIX = "RST-RESULT"
S.RESULT_END = "RST-END"

local function trim(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

-- Parses the lines of autorun.txt. Returns a filter (nil = every server/shared suite), or false and a reason.
function S.parseAutorun(lines)
    local suites = {}
    for i, raw in ipairs(lines) do
        local line = trim(tostring(raw))
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            if string.find(line, "%s") then
                return false, "autorun.txt line " .. i .. ": one suite name per line, got '" .. bounded(line, 80) .. "'"
            end
            suites[#suites + 1] = line
        end
    end
    if #suites == 0 then return nil end
    return { suite = suites }
end

-- Reads autorun.txt (read only). Returns "absent", or "ok" and the list of lines, or "error" and a reason.
function S.readAutorun()
    if type(getFileReader) ~= "function" then return "absent" end
    local okOpen, reader = pcall(getFileReader, S.AUTORUN_FILE, false)
    if not okOpen then return "error", "autorun.txt not readable: " .. oneLine(reader) end
    if reader == nil then return "absent" end
    local lines = {}
    local okRead, err = pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            if #lines >= S.AUTORUN_MAX_LINES then error("more than " .. S.AUTORUN_MAX_LINES .. " lines", 0) end
            lines[#lines + 1] = tostring(line)
        end
    end)
    pcall(function() reader:close() end)
    if not okRead then return "error", "autorun.txt not readable: " .. oneLine(err) end
    return "ok", lines
end

-- First line of autorun-result.txt (format in the header). report nil = run not started (counters at 0).
function S.resultLine(report, reportFile, reason)
    local r = report or { ok = false, total = 0, pass = 0, fail = 0, error = 0, skip = 0, empty = 0, durationMs = 0 }
    local ok = r.ok and r.total > 0 and reason == nil
    if reason == nil and r.total == 0 then reason = "no test selected" end
    local line = S.RESULT_PREFIX .. " ok=" .. tostring(ok and true or false) .. " total=" .. r.total
        .. " pass=" .. r.pass .. " fail=" .. r.fail .. " error=" .. r.error .. " skip=" .. r.skip
        .. " empty=" .. r.empty .. " durationMs=" .. math.floor((r.durationMs or 0) + 0.5)
    if reportFile then line = line .. " report=" .. reportFile end
    if reason then line = line .. " reason=" .. oneLine(reason) end
    return line
end

local function writeAutorunResult(first, lines)
    local out = { first }
    for _, line in ipairs(lines or {}) do out[#out + 1] = line end
    out[#out + 1] = S.RESULT_END
    local written, reason = RST.writeLines(S.AUTORUN_RESULT, out)
    if written then
        log("autorun result written: Zomboid/Lua/" .. S.AUTORUN_RESULT .. " (" .. first .. ")")
    else
        log("ERROR: autorun result not written: " .. tostring(reason))
    end
    return written and true or false
end

local function autorunRefused(reason)
    log("ERROR: autorun refused: " .. reason)
    S._autorun.state = "done"
    writeAutorunResult(S.resultLine(nil, nil, reason))
    return false
end

-- Starts the automatic run when autorun.txt exists (called at OnServerStarted). At most once per Lua state.
-- Returns true when a run was started; false otherwise (no file, already done, or refused: result written).
function S.autorun()
    if S._autorun then return false end
    local status, data = S.readAutorun()
    if status == "absent" then return false end
    S._autorun = { state = "started" }
    if status == "error" then return autorunRefused(data) end
    local filter, why = S.parseAutorun(data)
    if filter == false then return autorunRefused(why) end
    local started, reason = S.runSuites(filter, function(result)
        S._autorun.state = "done"
        S._autorun.result = result
        writeAutorunResult(S.resultLine(result.report, result.written and result.file or nil), result.lines)
    end, { requester = "autorun.txt" })
    if not started then return autorunRefused("run not started: " .. tostring(reason)) end
    log("autorun started from Zomboid/Lua/" .. S.AUTORUN_FILE .. " (filter " .. RST.render(filter) .. ")")
    return true
end

-- OnServerStarted only fires on a server (GameServer.startServer); isServer() is checked again for safety.
if not S._serverStartedSubscribed and type(Events) == "table" and type(Events.OnServerStarted) == "table" then
    Events.OnServerStarted.Add(function()
        if isServerSide() then RST.Server.autorun() end
    end)
    S._serverStartedSubscribed = true
end

return S
