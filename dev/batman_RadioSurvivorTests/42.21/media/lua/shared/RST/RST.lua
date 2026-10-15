--[[
RST — RadioSurvivor Tests : in-game test engine core (registry, suites, assertions, filters, text report).
Development mod only (batman_RadioSurvivorTests), never published. Load with: require "RST/RST"

Writing tests
    RST.suite("rs.codec", { tags = { "shared" } }, function(s)
        s.before(function(t) ... end)          -- before EACH test (several calls = several hooks, in order)
        s.after(function(t) ... end)           -- after EACH test, always called, even if before or the test failed
        s.test("decodes a line", function(t) t:eq(3, f()) end)
        s.test("later", function(t) end, { skip = "reason" })
        s.skip("other", "reason")
    end)
    RST.suite(name, fn) is accepted (no options). Declaring a suite again with the same name replaces it
    (Lua reload) at the same place in the declaration order, with a printed warning.
    The suite body runs immediately, under pcall. If it raises, the suite is kept with its error: running it
    reports a single ERROR line "(declaration)" and none of its tests (the declaration is incomplete).

Assertions (methods of the object t passed to tests and hooks)
    t:ok(v, msg)  t:eq(expected, actual, msg)  t:ne(unexpected, actual, msg)  t:near(expected, actual, eps, msg)
    t:fails(fn, pattern, msg)  t:skip(reason)  t:defer(fn, label)  t:waitUntil / t:waitQuiet / t:sleep (below)
    t:note(text)  keeps a line for the report (measures): not an assertion, allowed in any step (even after a
                  registered wait) and in hooks and cleanups; printed under the test line as "       note: text"
                  (result.notes, a list of strings; absent when the test wrote none).
    t:eq / t:ne compare tables deeply (cycle-safe); the message reads "expected X, got Y" (bounded rendering)
    plus the first differing key path. A failed assertion stops the current test or hook.
    t.ctx is the context table given to RST.runSync / RST.start (launchers put ctx.side and ctx.player there).

Cleanups (t:defer)
    t:defer(fn, label) registers fn(t) to run after the test: after the suite's after hooks, in reverse order of
    registration (last registered, first run), whatever happened before (failure, error, skip, timeout, cancel).
    It may be called from before hooks, the test body or after hooks. Each cleanup is its own phase: a failing
    or raising cleanup is reported like a failing after hook ("cleanup <label>: ...") and the next cleanups still
    run. In an asynchronous run a cleanup may wait in steps (t:waitUntil, t:sleep, see "Waiting in steps") and
    has the hook limit of its own.
    RST_Fixtures.lua (RST.Fixtures) registers its undo steps with t:defer.

World guard (suites tagged "world")
    A suite tagged "world" changes the game world (items, player position): it only runs when the save name
    (getWorld():getWorld(), i.e. Core.gameSaveWorld) starts with "rstest", compared case-insensitively
    ("rstest-solo", "RSTest_2" are test saves). Otherwise every test of the suite is SKIP with the reason
    "world suite refused: save '<name>' is not a test save (rstest*)", even when the filter asks for it
    explicitly. No save name (getWorld absent, error, nil or "") is a refusal too. The guard is decided once per
    plan (RST.plan), in the core, so it holds for the client, solo and server launchers alike. Note: on a
    dedicated server the name is the server name (-servername); on an MP client it is "<ip>_<port>_<hash>",
    so world suites never run on an MP client. RST.saveName(), RST.worldGuard() -> true or false, reason.
    Position guard: in an asynchronous run, when RST.worldJobGuard is set (RST_Fixtures.lua) each job of a world
    suite calls it first; it records the players' places and registers the first cleanup of the test (run last),
    which moves back every player the test left elsewhere and notes it ("position guard: ...").

Statuses
    PASS   the test ran and made at least one assertion, all passed.
    FAIL   an assertion failed (in the test, in a before hook or in an after hook).
    ERROR  an unexpected Lua error (in the test or a hook) or a suite whose declaration raised.
    SKIP   s.skip, opts.skip or t:skip(reason).
    EMPTY  the test body returned without any assertion and without skip. Counted apart (report.empty) and
           treated as a failure: report.ok is false when fail + error + empty > 0. Assertions made in hooks do
           not count for the test body.
    A failing after hook turns PASS / EMPTY / SKIP into FAIL or ERROR; on an already failing test its message
    is appended.

Filters (RST.select, RST.list, RST.runSync)
    nil                 every suite, every test.
    "name"              suites whose name equals "name" or starts with "name." (dot-separated prefix:
                        "rst" selects "rst" and "rst.selftest", not "rstx"). A filter ending with "." is a plain
                        prefix ("rs." selects "rs.codec").
    { suite = "name" or { "a", "b" },   suite names, same rule as the string form; any of them (OR)
      test = "pattern",                 Lua pattern searched (string.find) in each test name; other tests
                                        are left out of the run (not reported as skipped)
      tags = "t" or { "t1", "t2" },     suites having at least one of these tags (OR)
      exclude = "t" or { ... } }        suites having any of these tags are left out
    All given fields must hold (AND between fields). A suite with no selected test is left out, except a suite
    whose declaration failed: it stays visible when its name and tags match.

Running
    RST.runSync(filter, ctx) runs synchronously and returns a report:
      { pass, fail, error, skip, empty, total, ok, startedMs, durationMs, results = { {suite, test, status,
        ms, message}, ... } }
    The run is split into RST.plan (list of jobs), RST.newReport, RST.runJob and RST.finishReport so that a
    tick scheduler can step through the jobs later.
    RST.formatReport(report, header) returns text lines (no file, no UI); RST.summaryLine(report) its last line.

Report files and network filters (shared by RST_Client.lua and RST_Server.lua)
    RST.runInfo(filter, effective, side), RST.reportHeader(info), RST.stamp() ("YYYYMMDD-HHMMSS", UTC),
    RST.writeLines(path, lines) (getFileWriter, Zomboid/Lua of the machine running the Lua), RST.FILE_DIR.
    RST.checkFilter(filter) -> true, or false and a reason: only nil, a string, or a table with the fields suite,
    tags, exclude (string or list of strings) and test (string) can travel through sendClientCommand.
    RST.copyFilter(filter) returns a plain copy of such a filter.

Asynchronous run (tests that wait, driven by ticks)
    RST.start(filter, opts) -> true, or false and a reason (also printed). Only one run at a time: a second
    start during a run is refused. opts (all optional):
      ctx            table exposed as t.ctx
      onDone         function(report) called once at the end (errors are caught and printed)
      testTimeoutMs  default per-test limit (30000); per suite: opts.testTimeoutMs; per test: opts.timeoutMs
      suiteTimeoutMs default per-suite limit (120000); per suite: opts.timeoutMs
      budgetMs       time budget of one RST.step (50): synchronous tests are spread over several ticks
      attach         false to leave the tick events alone (RST.step is then called by the caller)
    RST.step() advances the run (normally once per tick); returns true while the run goes on.
    RST.running() tells whether a run is in progress; RST.cancel() stops it: the current test becomes SKIP
    "cancelled" (its after hooks still run), every remaining test is SKIP "cancelled".
    RST.last() returns the report of the last asynchronous run (nil before).

Waiting in steps (asynchronous run only)
    A test never suspends: in Kahlua an error() or a Java exception raised inside a suspended Lua thread
    escapes its resume ("Internal Kahlua error ... changed in pcall", E01-T11), so the engine uses none.
    Every phase (before hook, test body, after hook, t:defer cleanup) is a chain of steps; each step is a plain
    function(t[, value]) run under pcall at a tick.
    The first step is the hook, body or cleanup itself. A step that wants to wait REGISTERS the next step and
    returns:
        s.test("bridge", function(t)
            send()
            t:waitUntil(reply, 5000, function(t, value)    -- next step, called once reply() is true
                t:eq("ok", value)
                t:sleep(1000, function(t) t:ok(done()) end) -- steps chain: one more step after 1 s
            end)
        end)
      t:waitUntil(cond, ms, suite, msg)   ms, suite and msg optional (a string in place of suite is msg; msg may
                                    be a function, called at failure time for a message naming the cause).
                                    cond() is called under pcall right after the step, then once per tick. As
                                    soon as it returns a true value, the wait counts as one assertion and
                                    suite(t, value) runs as the next step (same tick); without suite the phase
                                    ends there (a test that only waits PASSes). FAIL "msg: condition not met
                                    within N ms" after ms (a failed wait is not an assertion); without ms only
                                    the test limit applies. An error raised by cond is ERROR ("waitUntil
                                    condition raised: ..."; an assertion signal raised there keeps FAIL / SKIP).
      t:waitQuiet(cond, ms, suite, msg) same, but the success is not an assertion (fixtures use it).
      t:sleep(ms, suite)            suite(t) runs at the first LATER tick where ms have elapsed (never the
                                    same tick); without suite the phase ends there.
    One wait per step: a second t:waitUntil / t:waitQuiet / t:sleep, or any assertion (t:ok, t:eq, t:ne,
    t:near, t:fails), made by the same step after it registered a wait is an ERROR ("... after t:waitUntil in
    the same step: ..."). Code after the wait call still runs at once, BEFORE the wait: put everything that
    depends on the wait in the continuation. t:defer and t:skip stay allowed. An error raised by the step after
    the registration wins (the wait is dropped). Do not wait inside t:fails: the wait would apply to the step.
    Under RST.runSync a wait is an ERROR with an explicit message ("needs an asynchronous run").
    Limits: a test over its limit (before hooks + body, all their steps and waits included) is FAIL "timeout:
    ..."; its after hooks then run, each with the same limit of its own (all its steps). When a suite exceeds
    its limit (counted from its first test), the current test is FAIL "timeout: suite ..." (after hooks run)
    and its remaining tests are FAIL without running. The run always goes on with the next suite.
    RST.attachTicks() subscribes RST.step once (idempotent, survives a reload of this file) to
    Events.OnTick, or Events.OnTickEvenPaused on a dedicated server (isServer()); RST.start calls it unless
    opts.attach is false, and the end of the run calls RST.detachTicks(). Loading this file subscribes
    nothing.

Opt-in suites (tags "selfcheck" and "manual", RST.EXPLICIT_TAGS)
    A suite tagged "selfcheck" (e.g. rst.failures: deliberate FAIL / ERROR) or "manual" (one step of a protocol
    played between manual actions, e.g. rs.identity.before) is left out of every selection unless the filter
    names it exactly (suite = "rst.failures") or asks for its opt-in tag (tags = "selfcheck", tags = "manual"):
    "rst", "rs", nil or the autorun default never run it.

Clock: RST.clock() returns milliseconds; getTimestampMs() (PZ global) if present, else os.time() * 1000,
else 0. It can be replaced (tests use a simulated clock).

Kahlua: no next(), no goto, no bitwise operators, no string.format("%q"), no debug.traceback.
]]

RST = RST or {}
RST.VERSION = "0.5.0"
RST._suites = RST._suites or {}

local function defaultClock()
    if type(getTimestampMs) == "function" then
        return getTimestampMs()
    end
    if os and type(os.time) == "function" then
        return os.time() * 1000
    end
    return 0
end

if type(RST.clock) ~= "function" then
    RST.clock = defaultClock
end

local function now()
    local ok, v = pcall(RST.clock)
    if ok and type(v) == "number" then return v end
    return 0
end
RST.now = now

-- ---------------------------------------------------------------- helpers

local function log(msg)
    print("[RST] " .. msg)
end

local function startsWith(s, prefix)
    return string.sub(s, 1, string.len(prefix)) == prefix
end

local function toList(v)
    if v == nil then return nil end
    if type(v) == "table" then return v end
    return { v }
end

local function hasAnyTag(tags, wanted)
    for _, w in ipairs(wanted) do
        for _, tag in ipairs(tags) do
            if tag == w then return true end
        end
    end
    return false
end

local function oneLine(s)
    s = tostring(s)
    s = string.gsub(s, "\r", "")
    s = string.gsub(s, "\n", " / ")
    return s
end

-- Small insertion sort (independent of table.sort, which Kahlua only gets from stdlib.lua).
local function sortList(list, less)
    for i = 2, #list do
        local v = list[i]
        local j = i - 1
        while j >= 1 and less(v, list[j]) do
            list[j + 1] = list[j]
            j = j - 1
        end
        list[j + 1] = v
    end
    return list
end

local TYPE_ORDER = { number = 1, string = 2, boolean = 3 }

local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return (TYPE_ORDER[ta] or 9) < (TYPE_ORDER[tb] or 9)
    end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    return sortList(keys, keyLess)
end

-- ---------------------------------------------------------------- rendering

local MAX_DEPTH = 3
local MAX_ITEMS = 12
local MAX_LEN = 240

local function quote(s)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "\"", "\\\"")
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\r", "\\r")
    return "\"" .. s .. "\""
end

local function isIdentifier(k)
    return type(k) == "string" and string.find(k, "^[%a_][%w_]*$") ~= nil
end

local renderValue

local function renderTable(t, depth, seen)
    if seen[t] then return "<cycle>" end
    if depth >= MAX_DEPTH then return "{...}" end
    seen[t] = true
    local parts = {}
    local n = #t
    local count = 0
    for i = 1, n do
        if count >= MAX_ITEMS then break end
        parts[#parts + 1] = renderValue(t[i], depth + 1, seen)
        count = count + 1
    end
    local keys = sortedKeys(t)
    local more = false
    for _, k in ipairs(keys) do
        local inArray = type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k
        if not inArray then
            if count >= MAX_ITEMS then
                more = true
                break
            end
            local ks
            if isIdentifier(k) then
                ks = k
            else
                ks = "[" .. renderValue(k, depth + 1, seen) .. "]"
            end
            parts[#parts + 1] = ks .. "=" .. renderValue(t[k], depth + 1, seen)
            count = count + 1
        end
    end
    if count >= MAX_ITEMS and (more or n > MAX_ITEMS) then
        parts[#parts + 1] = "..."
    end
    seen[t] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

renderValue = function(v, depth, seen)
    local tv = type(v)
    if tv == "string" then return quote(v) end
    if tv == "table" then return renderTable(v, depth or 0, seen or {}) end
    return tostring(v)
end

-- Readable, bounded rendering of any value.
function RST.render(v)
    local s = renderValue(v, 0, {})
    if string.len(s) > MAX_LEN then
        s = string.sub(s, 1, MAX_LEN - 3) .. "..."
    end
    return s
end

-- ---------------------------------------------------------------- deep equality

local function pathKey(k)
    if isIdentifier(k) then return "." .. k end
    return "[" .. renderValue(k, MAX_DEPTH, {}) .. "]"
end

-- Returns true, or false and the path of the first difference ("" for the root).
local function deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false, "" end
    seen = seen or {}
    if seen[a] and seen[a] == b then return true end
    seen[a] = b
    for _, k in ipairs(sortedKeys(a)) do
        local same, sub = deepEqual(a[k], b[k], seen)
        if not same then return false, pathKey(k) .. sub end
    end
    for _, k in ipairs(sortedKeys(b)) do
        if a[k] == nil then return false, pathKey(k) end
    end
    return true
end

RST.deepEqual = function(a, b)
    return deepEqual(a, b, nil)
end

-- ---------------------------------------------------------------- assertions

local FAIL, SKIP = "fail", "skip"

local Signal = {}
Signal.__index = Signal
Signal.__tostring = function(self) return self.message end

local function signal(kind, message)
    return setmetatable({ rstKind = kind, message = oneLine(message) }, Signal)
end

local function isSignal(err, kind)
    return type(err) == "table" and err.rstKind == kind
end

local function withMsg(msg, text)
    if type(msg) == "function" then -- E17-T15: message built at failure time (cause known only then)
        local ok, built = pcall(msg)
        msg = ok and built or ("failure message raised: " .. tostring(built))
    end
    if msg ~= nil and msg ~= "" then return tostring(msg) .. ": " .. text end
    return text
end

local T = {}
T.__index = T

-- Registers fn(t) to run after the test (reverse order, see "Cleanups" in the header). Returns fn.
function T:defer(fn, label)
    if type(fn) ~= "function" then
        error("t:defer(fn[, label]) expects a function", 2)
    end
    local list = self._deferred
    if not list then
        list = {}
        self._deferred = list
    end
    list[#list + 1] = { fn = fn, label = label and tostring(label) or ("#" .. tostring(#list + 1)) }
    return fn
end

-- Keeps a report line (see "Assertions"). Returns the text kept.
function T:note(text)
    local list = self._notes
    if not list then
        list = {}
        self._notes = list
    end
    local line = oneLine(text)
    list[#list + 1] = line
    return line
end

local function newT(ctx)
    return setmetatable({ assertions = 0, ctx = ctx }, T)
end

-- One wait per step (see "Waiting in steps"): nothing may be asserted or awaited after a registered wait.
local function checkNoWait(t, what)
    local pending = t._pending
    if pending then
        error("t:" .. what .. " after t:" .. pending.what .. " in the same step: one wait per step; put the rest"
            .. " in the continuation function", 0)
    end
end

local function countAssertion(t, what)
    checkNoWait(t, what)
    t.assertions = t.assertions + 1
end

function T:fail(text)
    error(signal(FAIL, text), 0)
end

function T:ok(v, msg)
    countAssertion(self, "ok")
    if not v then
        self:fail(withMsg(msg, "expected a true value, got " .. RST.render(v)))
    end
    return v
end

function T:eq(expected, actual, msg)
    countAssertion(self, "eq")
    local same, path = deepEqual(expected, actual, nil)
    if not same then
        local text = "expected " .. RST.render(expected) .. ", got " .. RST.render(actual)
        if path and path ~= "" then
            text = text .. " (first difference at " .. path .. ")"
        end
        self:fail(withMsg(msg, text))
    end
end

function T:ne(unexpected, actual, msg)
    countAssertion(self, "ne")
    if deepEqual(unexpected, actual, nil) then
        self:fail(withMsg(msg, "expected a value different from " .. RST.render(unexpected)))
    end
end

function T:near(expected, actual, eps, msg)
    countAssertion(self, "near")
    eps = eps or 1e-6
    if type(expected) ~= "number" or type(actual) ~= "number" then
        self:fail(withMsg(msg, "expected numbers, got " .. RST.render(expected) .. " and " .. RST.render(actual)))
    end
    if math.abs(expected - actual) > eps then
        self:fail(withMsg(msg, "expected " .. tostring(expected) .. " +/- " .. tostring(eps) .. ", got "
            .. tostring(actual)))
    end
end

-- Expects fn to raise. pattern (optional) is a Lua pattern searched in the error message.
-- Returns the error message.
function T:fails(fn, pattern, msg)
    countAssertion(self, "fails")
    local ok, err = pcall(fn)
    if ok then
        self:fail(withMsg(msg, "expected an error, none raised"))
    end
    local text
    if type(err) == "table" and err.rstKind then
        text = err.message
    else
        text = tostring(err)
    end
    if pattern ~= nil and not string.find(text, pattern) then
        self:fail(withMsg(msg, "error " .. quote(oneLine(text)) .. " does not match " .. quote(pattern)))
    end
    return text
end

function T:skip(reason)
    error(signal(SKIP, reason or "skipped"), 0)
end

local function requireAsync(t, what)
    if not t._async then
        error("t:" .. what .. " needs an asynchronous run (RST.start); RST.runSync cannot wait", 0)
    end
end

-- Registers the wait of the current step (see "Waiting in steps"); the scheduler runs it after the step.
local function registerWait(t, what, cond, ms, suite, msg, counted)
    local usage = "t:" .. what .. "(cond[, ms[, suite[, msg]]])"
    if type(cond) ~= "function" then
        error(usage .. " expects a function", 0)
    end
    if ms ~= nil and type(ms) ~= "number" then
        error(usage .. " expects ms to be a number", 0)
    end
    if type(suite) == "string" and msg == nil then
        suite, msg = nil, suite
    end
    if suite ~= nil and type(suite) ~= "function" then
        error(usage .. " expects suite to be a function", 0)
    end
    requireAsync(t, what)
    checkNoWait(t, what)
    t._pending = { what = what, kind = "until", cond = cond, ms = ms, deadline = ms and (now() + ms),
        suite = suite, msg = msg, counted = counted }
end

-- Next step suite(t, value) once cond() is true; the success counts as one assertion.
function T:waitUntil(cond, ms, suite, msg)
    registerWait(self, "waitUntil", cond, ms, suite, msg, true)
end

-- Same as t:waitUntil, without counting an assertion (waits of the fixtures).
function T:waitQuiet(cond, ms, suite, msg)
    registerWait(self, "waitQuiet", cond, ms, suite, msg, false)
end

-- Next step suite(t) at the first later tick where ms milliseconds have elapsed.
function T:sleep(ms, suite)
    if type(ms) ~= "number" then
        error("t:sleep(ms[, suite]) expects a number", 0)
    end
    if suite ~= nil and type(suite) ~= "function" then
        error("t:sleep(ms[, suite]) expects suite to be a function", 0)
    end
    requireAsync(self, "sleep")
    checkNoWait(self, "sleep")
    self._pending = { what = "sleep", kind = "sleep", wake = now() + ms, suite = suite }
end

RST.T = T

-- ---------------------------------------------------------------- registry

local function findSuite(name)
    for i, s in ipairs(RST._suites) do
        if s.name == name then return i, s end
    end
    return nil
end

local function newBuilder(suite)
    local s = {}
    s.test = function(name, fn, opts)
        if type(name) ~= "string" or type(fn) ~= "function" then
            error("s.test(name, fn[, opts]) expects a string and a function", 2)
        end
        opts = opts or {}
        for i, existing in ipairs(suite.tests) do
            if existing.name == name then
                log("WARNING: suite '" .. suite.name .. "' declares test '" .. name .. "' twice; the last one wins")
                table.remove(suite.tests, i)
                break
            end
        end
        local skip = opts.skip
        if skip == true then skip = "skipped" end
        suite.tests[#suite.tests + 1] = { name = name, fn = fn, skip = skip, opts = opts }
    end
    s.skip = function(name, reason)
        s.test(name, function() end, { skip = reason or "skipped" })
    end
    s.before = function(fn)
        suite.before[#suite.before + 1] = fn
    end
    s.after = function(fn)
        suite.after[#suite.after + 1] = fn
    end
    return s
end

function RST.suite(name, opts, fn)
    if type(opts) == "function" and fn == nil then
        fn, opts = opts, nil
    end
    if type(name) ~= "string" or name == "" or type(fn) ~= "function" then
        error("RST.suite(name[, opts], fn) expects a non-empty string and a function", 2)
    end
    opts = opts or {}
    local suite = { name = name, tags = toList(opts.tags) or {}, opts = opts, tests = {}, before = {}, after = {} }
    local ok, err = pcall(fn, newBuilder(suite))
    if not ok then
        suite.declError = oneLine(tostring(err))
        log("ERROR: declaration of suite '" .. name .. "' failed: " .. suite.declError)
    end
    local index = findSuite(name)
    if index then
        log("WARNING: suite '" .. name .. "' declared again; the new declaration replaces the old one")
        RST._suites[index] = suite
    else
        RST._suites[#RST._suites + 1] = suite
    end
    return suite
end

-- Removes every registered suite (tests of the engine itself, full reload).
function RST.reset()
    RST._suites = {}
end

-- ---------------------------------------------------------------- filters

local function nameMatches(name, f)
    if string.sub(f, -1) == "." then return startsWith(name, f) end
    return name == f or startsWith(name, f .. ".")
end

local function normalizeFilter(filter)
    if filter == nil then return {} end
    if type(filter) == "string" then return { suite = { filter } } end
    if type(filter) ~= "table" then
        error("RST filter must be nil, a string or a table, got " .. type(filter), 3)
    end
    return {
        suite = toList(filter.suite),
        test = filter.test,
        tags = toList(filter.tags),
        exclude = toList(filter.exclude),
    }
end

RST.EXPLICIT_TAG = "selfcheck"
RST.EXPLICIT_TAGS = { RST.EXPLICIT_TAG, "manual" }

-- An opt-in suite ("selfcheck", "manual") needs its exact name in f.suite or one of its opt-in tags in f.tags
-- (see "Opt-in suites").
local function explicitlyAsked(suite, f)
    for _, tag in ipairs(RST.EXPLICIT_TAGS) do
        if f.tags and hasAnyTag(f.tags, { tag }) and hasAnyTag(suite.tags, { tag }) then return true end
    end
    for _, name in ipairs(f.suite or {}) do
        if name == suite.name then return true end
    end
    return false
end

local function suiteMatches(suite, f)
    if hasAnyTag(suite.tags, RST.EXPLICIT_TAGS) and not explicitlyAsked(suite, f) then return false end
    if f.suite then
        local any = false
        for _, name in ipairs(f.suite) do
            if nameMatches(suite.name, name) then
                any = true
                break
            end
        end
        if not any then return false end
    end
    if f.tags and not hasAnyTag(suite.tags, f.tags) then return false end
    if f.exclude and hasAnyTag(suite.tags, f.exclude) then return false end
    return true
end

-- Returns { { suite = suite, tests = { test, ... } }, ... } in declaration order.
function RST.select(filter)
    local f = normalizeFilter(filter)
    local selection = {}
    for _, suite in ipairs(RST._suites) do
        if suiteMatches(suite, f) then
            local tests = {}
            if not suite.declError then
                for _, test in ipairs(suite.tests) do
                    if not f.test or string.find(test.name, f.test) then
                        tests[#tests + 1] = test
                    end
                end
            end
            if suite.declError or #tests > 0 then
                selection[#selection + 1] = { suite = suite, tests = tests }
            end
        end
    end
    return selection
end

-- Returns { { name, tags, count, error }, ... }; prints one line per suite unless silent is true.
function RST.list(filter, silent)
    local out = {}
    for _, item in ipairs(RST.select(filter)) do
        local entry = { name = item.suite.name, tags = item.suite.tags, count = #item.tests, error = item.suite.declError }
        out[#out + 1] = entry
        if not silent then
            local line = entry.name .. " [" .. table.concat(entry.tags, ",") .. "] " .. entry.count .. " test(s)"
            if entry.error then line = line .. " DECLARATION ERROR: " .. entry.error end
            log(line)
        end
    end
    if not silent then log(#out .. " suite(s)") end
    return out
end

-- ---------------------------------------------------------------- world guard

RST.WORLD_TAG = "world"
RST.TEST_SAVE_PREFIX = "rstest"

-- Save name (getWorld():getWorld()), or nil when unavailable or empty.
function RST.saveName()
    if type(getWorld) ~= "function" then return nil end
    local ok, name = pcall(function()
        local world = getWorld()
        if world == nil then return nil end
        return world:getWorld()
    end)
    if not ok or name == nil then return nil end
    name = tostring(name)
    if name == "" then return nil end
    return name
end

-- Returns true when world suites may run here, else false and the refusal reason (see the header).
function RST.worldGuard()
    local name = RST.saveName()
    if not name then
        return false, "world suite refused: save name unavailable (getWorld():getWorld())"
    end
    if startsWith(string.lower(name), RST.TEST_SAVE_PREFIX) then return true end
    return false, "world suite refused: save '" .. name .. "' is not a test save (" .. RST.TEST_SAVE_PREFIX .. "*)"
end

-- ---------------------------------------------------------------- running

-- Maps a raised error to a status ("FAIL", "SKIP", "ERROR") and a message. pcall returns the raised object
-- itself (no suspended thread in between), so assertion signals come back intact.
local function classify(err)
    if isSignal(err, FAIL) then return "FAIL", err.message end
    if isSignal(err, SKIP) then return "SKIP", err.message end
    return "ERROR", oneLine(tostring(err))
end

-- Runs fn(t) under pcall; returns nil on success, else status ("FAIL", "SKIP", "ERROR") and message.
local function protect(fn, t)
    t._pending = nil
    local ok, err = pcall(fn, t)
    t._pending = nil
    if ok then return nil end
    return classify(err)
end

-- One job per test, or one per suite whose declaration failed.
-- Tests of a refused world suite carry job.refused (recorded as SKIP without running).
function RST.plan(filter)
    local jobs = {}
    local guardDone, refusal = false, nil
    for _, item in ipairs(RST.select(filter)) do
        if item.suite.declError then
            jobs[#jobs + 1] = { suite = item.suite, declError = item.suite.declError }
        else
            local refused = nil
            if hasAnyTag(item.suite.tags, { RST.WORLD_TAG }) then
                if not guardDone then
                    guardDone = true
                    local allowed, why = RST.worldGuard()
                    if not allowed then
                        refusal = why
                        log(why)
                    end
                end
                refused = refusal
            end
            for _, test in ipairs(item.tests) do
                jobs[#jobs + 1] = { suite = item.suite, test = test, refused = refused }
            end
        end
    end
    return jobs
end

function RST.newReport()
    return { pass = 0, fail = 0, error = 0, skip = 0, empty = 0, total = 0, ok = true,
        startedMs = now(), durationMs = 0, results = {} }
end

local COUNTER = { PASS = "pass", FAIL = "fail", ERROR = "error", SKIP = "skip", EMPTY = "empty" }

local function record(report, result)
    report.results[#report.results + 1] = result
    report.total = report.total + 1
    local key = COUNTER[result.status]
    report[key] = report[key] + 1
    return result
end

local function jobTestName(job)
    if job.declError then return "(declaration)" end
    return job.test.name
end

-- Records a job that needs no execution (failed declaration, skipped test); nil otherwise.
local function recordImmediate(job, report)
    if job.declError then
        return record(report, { suite = job.suite.name, test = "(declaration)", status = "ERROR", ms = 0,
            message = job.declError })
    end
    if job.refused then
        return record(report, { suite = job.suite.name, test = job.test.name, status = "SKIP", ms = 0,
            message = job.refused })
    end
    if job.test.skip then
        return record(report, { suite = job.suite.name, test = job.test.name, status = "SKIP", ms = 0,
            message = tostring(job.test.skip) })
    end
    return nil
end

-- Job state shared by the synchronous and the asynchronous runs. Stages: "before" (before hooks, then the
-- body starts), "body" (body running), "after" (after hooks, always reached), "cleanup" (t:defer, reverse order).
-- Asynchronous run: st.phase is true while a phase (hook, body, cleanup) has steps left; st.wait is what it waits
-- for: { kind = "start", fn } (first step), "sleep" or "until" (registered by the previous step).
local function newJobState(job, ctx, async)
    local t = newT(ctx)
    t._async = async
    -- Position guard of the world suites (RST_Fixtures.lua, F.guardPositions): registered before anything else,
    -- so its way back is the last cleanup of the test.
    if async and type(RST.worldJobGuard) == "function" and hasAnyTag(job.suite.tags, { RST.WORLD_TAG }) then
        local ok, err = pcall(RST.worldJobGuard, t, job)
        if not ok then log("WARNING: position guard not set: " .. oneLine(tostring(err))) end
    end
    return { job = job, suite = job.suite, test = job.test, t = t, started = now(), stage = "before",
        index = 0, bodyStart = 0 }
end

local function isTeardown(stage)
    return stage == "after" or stage == "cleanup"
end

-- Returns the kind ("before", "body", "after", "cleanup") and the function of the next phase, or nil when done.
local function nextPhase(st)
    if st.stage == "before" then
        local hook = st.suite.before[st.index + 1]
        if hook then
            st.index = st.index + 1
            return "before", hook
        end
        st.stage = "body"
        st.bodyStart = st.t.assertions
        return "body", st.test.fn
    end
    if st.stage == "after" then
        local hook = st.suite.after[st.index + 1]
        if hook then
            st.index = st.index + 1
            return "after", hook
        end
        st.stage = "cleanup"
    end
    if st.stage ~= "cleanup" then return nil end
    local list = st.t._deferred
    local n = list and #list or 0
    if n == 0 then return nil end
    local entry = list[n]
    list[n] = nil
    st.cleanupLabel = entry.label
    return "cleanup", entry.fn
end

local function toAfterStage(st)
    st.stage = "after"
    st.index = 0
end

-- Applies the outcome of a phase (status nil = success) with the rules described in the header.
local function applyPhase(st, kind, status, message)
    if kind == "before" then
        if status then
            st.status, st.message = status, "before: " .. message
            toAfterStage(st)
        end
    elseif kind == "body" then
        if status then
            st.status, st.message = status, message
        elseif st.t.assertions > st.bodyStart then
            st.status = "PASS"
        else
            st.status, st.message = "EMPTY", "no assertion"
        end
        toAfterStage(st)
    elseif status then
        local prefix = "after: "
        if kind == "cleanup" then prefix = "cleanup " .. tostring(st.cleanupLabel) .. ": " end
        local hMessage = prefix .. message
        if st.status == "FAIL" or st.status == "ERROR" then
            st.message = (st.message or "") .. " ; " .. hMessage
        else
            if status == "SKIP" then status = "ERROR" end
            st.status, st.message = status, hMessage
        end
    end
end

-- Stops the running phase (timeout, cancel): during before hooks or the body it gives the job its status;
-- during an after hook or a cleanup it counts as a failing after hook or cleanup.
local function abortPhase(st, status, message)
    st.phase, st.wait = nil, nil
    if not isTeardown(st.stage) then
        st.status, st.message = status, message
        toAfterStage(st)
    else
        applyPhase(st, st.kind == "cleanup" and "cleanup" or "after", status, message)
    end
end

local function finishJob(st, report)
    local ms = now() - st.started
    if ms < 0 then ms = 0 end
    return record(report, { suite = st.suite.name, test = st.test.name, status = st.status, ms = ms,
        message = st.message, notes = st.t._notes })
end

-- Runs one job synchronously and records its result in the report.
function RST.runJob(job, report, ctx)
    local done = recordImmediate(job, report)
    if done then return done end
    local st = newJobState(job, ctx, false)
    while true do
        local kind, fn = nextPhase(st)
        if not kind then break end
        local status, message = protect(fn, st.t)
        applyPhase(st, kind, status, message)
    end
    return finishJob(st, report)
end

function RST.finishReport(report)
    report.durationMs = now() - report.startedMs
    if report.durationMs < 0 then report.durationMs = 0 end
    report.ok = (report.fail + report.error + report.empty) == 0
    return report
end

-- Synchronous run. ctx (optional table) is exposed to tests as t.ctx.
function RST.runSync(filter, ctx)
    local jobs = RST.plan(filter)
    local report = RST.newReport()
    for _, job in ipairs(jobs) do
        RST.runJob(job, report, ctx)
    end
    return RST.finishReport(report)
end

-- ---------------------------------------------------------------- asynchronous run

RST.DEFAULT_TEST_TIMEOUT_MS = 30000
RST.DEFAULT_SUITE_TIMEOUT_MS = 120000
RST.DEFAULT_BUDGET_MS = 50

local function positive(v)
    if type(v) == "number" and v > 0 then return v end
    return nil
end

local function testLimit(run, job)
    return positive(job.test.opts and job.test.opts.timeoutMs) or positive(job.suite.opts.testTimeoutMs)
        or run.testTimeoutMs
end

local function suiteLimit(run, suite)
    return positive(suite.opts.timeoutMs) or run.suiteTimeoutMs
end

-- Runs one step fn(t, ...) under pcall. Returns "registered" when the step registered a wait (kept in st.wait),
-- else "done" with status and message (nil = success).
local function runStep(run, st, fn, ...)
    local t = st.t
    t._pending = nil
    local ok, err = pcall(fn, t, ...)
    local pending = t._pending
    t._pending = nil
    if not ok then
        return "done", classify(err)
    end
    if pending then
        pending.tick = run.tick
        st.wait = pending
        return "registered"
    end
    return "done"
end

-- Goes on with the current phase: first step, or the wait registered by the previous step. Returns "wait" (still
-- waiting: next tick), "registered" (a step registered a new wait) or "done" with status and message.
local function resumePhase(run, st)
    local w = st.wait
    st.wait = nil
    if w.kind == "start" then
        return runStep(run, st, w.fn)
    end
    if w.kind == "sleep" then
        if run.tick <= w.tick or now() < w.wake then
            st.wait = w
            return "wait"
        end
        if w.suite then return runStep(run, st, w.suite) end
        return "done"
    end
    local ok, v = pcall(w.cond)
    st.t._pending = nil
    if not ok then
        local status, message = classify(v)
        if status == "ERROR" then message = "waitUntil condition raised: " .. message end
        return "done", status, message
    end
    if v then
        if w.counted then st.t.assertions = st.t.assertions + 1 end
        if w.suite then return runStep(run, st, w.suite, v) end
        return "done"
    end
    if w.deadline and now() >= w.deadline then
        return "done", "FAIL", withMsg(w.msg, "condition not met within " .. tostring(w.ms) .. " ms")
    end
    st.wait = w
    return "wait"
end

local function suiteTimeoutMessage(run)
    return "timeout: suite '" .. run.suite.name .. "' exceeded " .. tostring(run.suiteLimit) .. " ms"
end

-- Takes the next job. Returns "progress" (recorded without running, or job state ready) or "done".
local function takeJob(run)
    run.index = run.index + 1
    local job = run.jobs[run.index]
    if not job then return "done" end
    if run.suite ~= job.suite then
        run.suite = job.suite
        run.suiteStart = now()
        run.suiteLimit = suiteLimit(run, job.suite)
        run.suiteTimedOut = false
    end
    if recordImmediate(job, run.report) then return "progress" end
    if run.suiteTimedOut or now() - run.suiteStart >= run.suiteLimit then
        run.suiteTimedOut = true
        record(run.report, { suite = job.suite.name, test = job.test.name, status = "FAIL", ms = 0,
            message = suiteTimeoutMessage(run) .. " (not run)" })
        return "progress"
    end
    local st = newJobState(job, run.ctx, true)
    st.limit = testLimit(run, job)
    run.job = st
    return "progress"
end

-- Advances the run by one unit of work. Returns "progress", "wait" (a phase waits for a later tick) or "done".
local function advance(run)
    local st = run.job
    if run.cancelled then
        if st and not isTeardown(st.stage) then
            abortPhase(st, "SKIP", "cancelled")
        end
        if not st then
            while run.index < #run.jobs do
                run.index = run.index + 1
                local job = run.jobs[run.index]
                record(run.report, { suite = job.suite.name, test = jobTestName(job), status = "SKIP", ms = 0,
                    message = "cancelled" })
            end
            return "done"
        end
    end
    if not st then
        return takeJob(run)
    end
    if not st.phase then
        local kind, fn = nextPhase(st)
        if not kind then
            finishJob(st, run.report)
            run.job = nil
            return "progress"
        end
        st.phase, st.kind, st.phaseStart = true, kind, now()
        st.wait = { kind = "start", fn = fn }
    end
    local t0 = now()
    if st.kind == "after" or st.kind == "cleanup" then
        if t0 - st.phaseStart >= st.limit then
            abortPhase(st, "FAIL", "timeout: hook exceeded " .. tostring(st.limit) .. " ms")
            return "progress"
        end
    elseif t0 - st.started >= st.limit then
        abortPhase(st, "FAIL", "timeout: test exceeded " .. tostring(st.limit) .. " ms")
        return "progress"
    elseif t0 - run.suiteStart >= run.suiteLimit then
        run.suiteTimedOut = true
        abortPhase(st, "FAIL", suiteTimeoutMessage(run))
        return "progress"
    end
    local state, status, message = resumePhase(run, st)
    if state == "wait" then return "wait" end
    if state == "registered" then return "progress" end
    st.phase, st.wait = nil, nil
    applyPhase(st, st.kind, status, message)
    return "progress"
end

local function finishRun(run)
    RST._run = nil
    local r = RST.finishReport(run.report)
    RST._last = r
    RST.detachTicks()
    log("run finished: " .. (r.ok and "OK" or "FAILED") .. " - " .. r.total .. " test(s): " .. r.pass .. " pass, "
        .. r.fail .. " fail, " .. r.error .. " error, " .. r.skip .. " skip, " .. r.empty .. " empty")
    if type(run.onDone) == "function" then
        local ok, err = pcall(run.onDone, r)
        if not ok then
            log("ERROR: onDone failed: " .. oneLine(tostring(err)))
        end
    end
end

function RST.running()
    return RST._run ~= nil
end

function RST.last()
    return RST._last
end

local function refuse(reason)
    log("start refused: " .. reason)
    return false, reason
end

-- Starts an asynchronous run. Returns true, or false and a reason.
function RST.start(filter, opts)
    if RST._run then return refuse("a run is already in progress") end
    opts = opts or {}
    local ok, jobs = pcall(RST.plan, filter)
    if not ok then return refuse(oneLine(tostring(jobs))) end
    RST._run = { jobs = jobs, index = 0, tick = 0, report = RST.newReport(), ctx = opts.ctx, onDone = opts.onDone,
        testTimeoutMs = positive(opts.testTimeoutMs) or RST.DEFAULT_TEST_TIMEOUT_MS,
        suiteTimeoutMs = positive(opts.suiteTimeoutMs) or RST.DEFAULT_SUITE_TIMEOUT_MS,
        budgetMs = positive(opts.budgetMs) or RST.DEFAULT_BUDGET_MS }
    log("run started: " .. #jobs .. " test(s)")
    if opts.attach ~= false then
        RST.attachTicks()
    end
    return true
end

-- Advances the current run within its time budget (at least one unit of work). Returns true while the run
-- goes on, false when there is none or it just finished.
function RST.step()
    local run = RST._run
    if not run or run.stepping then return false end
    run.stepping = true
    run.tick = run.tick + 1
    local budgetEnd = now() + run.budgetMs
    local state
    repeat
        local ok, res = pcall(advance, run)
        if ok then
            state = res
        else
            local message = oneLine(tostring(res))
            log("ERROR: scheduler failure, run aborted: " .. message)
            record(run.report, { suite = "RST", test = "(scheduler)", status = "ERROR", ms = 0, message = message })
            state = "done"
        end
    until state ~= "progress" or now() >= budgetEnd
    run.stepping = false
    if state == "done" then
        finishRun(run)
        return false
    end
    return true
end

-- Cancels the current run (see header) and steps it once. Returns true, or false and a reason.
function RST.cancel()
    local run = RST._run
    if not run then return false, "no run in progress" end
    if not run.cancelled then
        run.cancelled = true
        log("run cancelled")
    end
    if not run.stepping then
        RST.step()
    end
    return true
end

-- Subscribes RST.step to the tick event once. Returns true (subscribed now or before), or false and a reason.
function RST.attachTicks()
    if RST._tick then return true end
    if type(Events) ~= "table" then return false, "Events not available" end
    local name = "OnTick"
    if type(isServer) == "function" and isServer() then
        name = "OnTickEvenPaused"
    end
    local event = Events[name]
    if type(event) ~= "table" or type(event.Add) ~= "function" then
        return false, name .. " not available"
    end
    local handler = function() RST.step() end
    event.Add(handler)
    RST._tick = { event = name, fn = handler }
    return true
end

-- Removes the subscription made by RST.attachTicks. Returns true if there was one.
function RST.detachTicks()
    local tick = RST._tick
    if not tick then return false end
    RST._tick = nil
    local event = type(Events) == "table" and Events[tick.event]
    if type(event) == "table" and type(event.Remove) == "function" then
        event.Remove(tick.fn)
    end
    return true
end

-- ---------------------------------------------------------------- text report

local function pad(s, width)
    local n = string.len(s)
    if n >= width then return s end
    return s .. string.rep(" ", width - n)
end

local function ms(v)
    return tostring(math.floor((v or 0) + 0.5))
end

-- Returns a list of text lines: header lines, one line per test, then a summary line.
function RST.formatReport(report, header)
    local lines = {}
    for _, h in ipairs(header or {}) do
        lines[#lines + 1] = oneLine(h)
    end
    for _, r in ipairs(report.results) do
        local line = pad(r.status, 5) .. "  " .. r.suite .. " :: " .. r.test .. " (" .. ms(r.ms) .. " ms)"
        if r.message and r.message ~= "" then
            line = line .. " " .. oneLine(r.message)
        end
        lines[#lines + 1] = line
        for _, note in ipairs(r.notes or {}) do
            lines[#lines + 1] = "       note: " .. oneLine(note)
        end
    end
    lines[#lines + 1] = RST.summaryLine(report)
    return lines
end

-- Last line of a text report: "OK - N test(s): ... (D ms)".
function RST.summaryLine(report)
    return (report.ok and "OK" or "FAILED") .. " - " .. report.total .. " test(s): "
        .. report.pass .. " pass, " .. report.fail .. " fail, " .. report.error .. " error, "
        .. report.skip .. " skip, " .. report.empty .. " empty (" .. ms(report.durationMs) .. " ms)"
end

-- ---------------------------------------------------------------- report files (client, solo and server)
-- Shared by the launchers RST_Client.lua (client, solo) and RST_Server.lua (server): header, timestamp, file.

RST.FILE_DIR = "batman_RadioSurvivor/tests/"

local function safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- Civil date from days since 1970-01-01 (H. Hinnant), only small numbers (no % beyond 2^31 quotients).
local function civil(days)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + 3
    if m > 12 then m = m - 12 end
    if m <= 2 then y = y + 1 end
    return y, m, d
end

local function two(n)
    if n < 10 then return "0" .. tostring(n) end
    return tostring(n)
end

-- "YYYYMMDD-HHMMSS" in UTC from epoch milliseconds.
function RST.stampFromMs(msValue)
    local secs = math.floor(msValue / 1000)
    local days = math.floor(secs / 86400)
    local rest = secs - days * 86400
    local y, m, d = civil(days)
    local hh = math.floor(rest / 3600)
    local mm = math.floor((rest - hh * 3600) / 60)
    local ss = rest - hh * 3600 - mm * 60
    return tostring(y) .. two(m) .. two(d) .. "-" .. two(hh) .. two(mm) .. two(ss)
end

-- UTC timestamp "YYYYMMDD-HHMMSS": Kahlua os.date (OsLib, UTC), else derived from getTimestampMs().
function RST.stamp()
    if os and type(os.date) == "function" then
        local s = safe(os.date, "!%Y%m%d-%H%M%S")
        if type(s) == "string" and string.find(s, "^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$") then return s end
    end
    local v = (type(getTimestampMs) == "function" and safe(getTimestampMs)) or 0
    return RST.stampFromMs(v)
end

-- Returns the list of active mod IDs (Java List: size/get).
local function activeMods()
    local out = {}
    local list = type(getActivatedMods) == "function" and safe(getActivatedMods) or nil
    if not list then return out end
    local n = safe(function() return list:size() end) or 0
    for i = 0, n - 1 do
        out[#out + 1] = tostring(list:get(i))
    end
    return out
end

-- Run description used by the report header: filter, effective filter, side, version, save, mods, stamp.
function RST.runInfo(filter, effective, side)
    return { filter = filter, effective = effective, side = side,
        version = safe(function() return tostring(getCore():getVersion()) end) or "unknown",
        save = safe(function() return tostring(getWorld():getWorld()) end) or "unknown",
        mods = activeMods(), stamp = RST.stamp() }
end

function RST.reportHeader(info)
    local mods = info.mods or {}
    local lines = {
        "RST report (batman_RadioSurvivorTests, RST " .. tostring(RST.VERSION) .. ")",
        "game version: " .. info.version,
        "side: " .. info.side,
    }
    if info.requester then lines[#lines + 1] = "requested by: " .. tostring(info.requester) end
    lines[#lines + 1] = "save: " .. info.save
    lines[#lines + 1] = "filter: " .. RST.render(info.filter) .. " -> " .. RST.render(info.effective)
    lines[#lines + 1] = "date (UTC): " .. info.stamp
    lines[#lines + 1] = "active mods (" .. #mods .. "): " .. table.concat(mods, ";")
    lines[#lines + 1] = ""
    return lines
end

-- Writes the lines to Zomboid/Lua/<path> (cache folder of the machine running the Lua: the server in MP).
-- Returns true, or false and a reason. The writer is always closed.
function RST.writeLines(path, lines)
    if type(getFileWriter) ~= "function" then return false, "getFileWriter not available" end
    local ok, writer = pcall(getFileWriter, path, true, false)
    if not ok or not writer then return false, "getFileWriter refused " .. path end
    local wrote, err = pcall(function()
        for _, line in ipairs(lines) do
            writer:writeln(line)
        end
    end)
    local closed, cerr = pcall(function() writer:close() end)
    if not wrote then return false, "write failed: " .. tostring(err) end
    if not closed then return false, "close failed: " .. tostring(cerr) end
    return true
end

-- ---------------------------------------------------------------- network-safe filters

local FILTER_FIELDS = { suite = true, test = true, tags = true, exclude = true }

local function checkStrings(field, v)
    if type(v) == "string" then return true end
    if type(v) ~= "table" then
        return false, "filter field '" .. field .. "' must be a string or a list of strings, got " .. type(v)
    end
    local n, count = #v, 0
    for k, item in pairs(v) do
        count = count + 1
        if type(k) ~= "number" or k < 1 or k > n or math.floor(k) ~= k then
            return false, "filter field '" .. field .. "' must be a list (key " .. RST.render(k) .. ")"
        end
        if type(item) ~= "string" then
            return false, "filter field '" .. field .. "' must only hold strings, got " .. type(item)
        end
    end
    if count ~= n then return false, "filter field '" .. field .. "' must be a list without holes" end
    return true
end

-- Checks that a filter can travel through sendClientCommand (strings only: a function or a Java object would be
-- dropped silently by the network). Returns true, or false and a reason.
function RST.checkFilter(filter)
    if filter == nil or type(filter) == "string" then return true end
    if type(filter) ~= "table" then
        return false, "filter must be nil, a string or a table, got " .. type(filter)
    end
    for k, v in pairs(filter) do
        if type(k) ~= "string" or not FILTER_FIELDS[k] then
            return false, "unknown filter field " .. RST.render(k) .. " (suite, test, tags, exclude)"
        end
        if k == "test" then
            if type(v) ~= "string" then return false, "filter field 'test' must be a string, got " .. type(v) end
        else
            local ok, reason = checkStrings(k, v)
            if not ok then return false, reason end
        end
    end
    return true
end

-- Plain copy of a filter accepted by RST.checkFilter (lists copied, network tables become Lua tables).
function RST.copyFilter(filter)
    if type(filter) ~= "table" then return filter end
    local out = {}
    for _, k in ipairs({ "suite", "test", "tags", "exclude" }) do
        local v = filter[k]
        if type(v) == "table" then
            local list = {}
            for i, item in ipairs(v) do list[i] = item end
            v = list
        end
        out[k] = v
    end
    return out
end

return RST
