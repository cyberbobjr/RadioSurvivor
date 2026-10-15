--[[
RST_Steps - named steps between a suite running on the authority and the connected clients (E01-T16). Development
mod only. Load with: require "RST/RST_Steps" (shared: the same file serves the server, the clients and solo).

A suite run by the authority (dedicated server through RST.server, or solo) asks the clients to check what THEY see or
to act as a player would (notebook line, request of a tool, change of access level); each client runs the handler of
the step and answers PASS, FAIL, ERROR or SKIP. The server writes the answers in its own report (one assertion per
client) and fails the test when a client misses the step within the delay.

Authority (suite code)
    RST.Steps.ask(t, step, args, opts, after)
        step   name of a client handler (RST.Steps.on), e.g. "world.keys"
        args   plain table sent to the clients (strings, numbers, booleans, nested tables)
        opts   { target = "others" (default: every online player except the requester t.ctx.player) | "requester" |
                 "all" | { "account", ... }, timeoutMs = 30000 (client deadline; the server waits MARGIN_MS more),
                 assert = true (false: only a missed step is asserted, after() reads the answers itself),
                 none = "note" (default) | "skip" (no target online: t:note and go on, or t:skip) }
        after  function(t, result) run as the next step once every target answered or the delay is over;
               result = { list = { { user, status, message, data }, ... }, by = { [user] = answer }, none = bool }
    Asserted for each target (unless opts.assert is false): answer present ("client <user> missed step <step> within
    N ms"), status PASS or SKIP (SKIP is noted, not failed: a client that cannot check, e.g. a square not loaded there).
    RST.Steps.others(t) -> list of the account names of the other online players (server), {} in solo.
    Solo (no network): the targets are the local player only for "requester" and "all"; "others" has no target.
    The handler then runs in the same Lua state (same code path, same polling).

Clients (and solo)
    RST.Steps.on(step, handler)   handler(args, ctx) -> result | poll
        result  RST.Steps.pass(message, data) | RST.Steps.fail(message, data) | RST.Steps.skip(message)
        poll    function(ctx) called at once and then at every tick until it returns a result; ctx.final is true
                at the last call (client deadline reached): return a FAIL with the diagnostic then (nil = generic
                "no result within N ms"). ctx = { step, seq, user, startedMs, deadlineMs, final }.
        A raising handler or poll answers ERROR with the message. Unknown step: ERROR "unknown step".
    Every answer is kept for the client report: Zomboid/Lua/batman_RadioSurvivor/tests/<stamp>-steps.txt (rewritten
    at each answer; the launcher copies it into runs/<run>/client<N>/), and RST.Steps.summary() gives the counters
    used by the result line of a peer client (RST_AutoClient.lua, peer=true).

Network (module "RSTStep"; RELIABLE, not ordered: matched by sequence number)
    server -> client  ask     { seq, step, args, ms }
    client -> server  answer  { seq, step, status, message, data }
    The server keeps an answer only from an account the step was sent to, once (others are logged and ignored).
Loading this file subscribes OnServerCommand (client) or OnClientCommand (server) once per Lua state; it starts
nothing. OnTick is subscribed while a handler polls (clients and solo) and removed when none is left.
Kahlua: no next() and no goto; nothing suspends (polls are plain functions called at each tick).
]]

require "RST/RST"

RST.Steps = RST.Steps or {}
local S = RST.Steps

S.MODULE = "RSTStep"
S.DEFAULT_MS = 30000
S.MARGIN_MS = 3000          -- server wait beyond the client deadline (network, one tick)
S.MAX_MESSAGE = 700
S.handlers = S.handlers or {}
S.asks = S.asks or {}       -- authority: seq -> { step, users = { name, ... }, expected = { [name] = true }, answers }
S.jobs = S.jobs or {}       -- clients and solo: running handlers { seq, step, poll, ctx, done }
S.records = S.records or {} -- clients and solo: answered steps, in order (report)
S.seq = S.seq or 0
S.LOCAL = "local"

local function log(msg)
    print("[RST-STEP] " .. msg)
end

local function now()
    return RST.now()
end

local function oneLine(s)
    s = string.gsub(tostring(s), "[\r\n]+", " / ")
    if string.len(s) > S.MAX_MESSAGE then s = string.sub(s, 1, S.MAX_MESSAGE - 3) .. "..." end
    return s
end

local function isServerSide() return type(isServer) == "function" and isServer() and true or false end
local function isClientSide() return type(isClient) == "function" and isClient() and true or false end
function S.isSolo() return not isServerSide() and not isClientSide() end

-- ---------------------------------------------------------------- results

function S.pass(message, data) return { status = "PASS", message = message, data = data } end
function S.fail(message, data) return { status = "FAIL", message = message, data = data } end
function S.skip(message) return { status = "SKIP", message = message } end

local STATUSES = { PASS = true, FAIL = true, ERROR = true, SKIP = true }

local function normalize(res)
    if type(res) ~= "table" or not STATUSES[res.status] then
        return { status = "ERROR", message = "handler returned no result table (" .. type(res) .. ")" }
    end
    return { status = res.status, message = res.message ~= nil and oneLine(res.message) or nil, data = res.data }
end

function S.on(step, handler)
    if type(step) ~= "string" or type(handler) ~= "function" then error("RST.Steps.on(step, handler)", 2) end
    S.handlers[step] = handler
end

-- ---------------------------------------------------------------- client side (and solo)

-- Account of the local player as the authority names it (getUsername, may be "" in solo).
local function rawName()
    if type(getPlayer) ~= "function" then return "" end
    local ok, name = pcall(function() return getPlayer():getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return ""
end

local function username()
    local name = rawName()
    if name ~= "" then return name end
    return S.LOCAL
end
S.username = username

-- Report file of this Lua state (one per client session).
function S.writeReport()
    if S.fileStamp == nil then S.fileStamp = RST.stamp() end
    local path = RST.FILE_DIR .. S.fileStamp .. "-steps.txt"
    local sum = S.summary()
    local lines = { "RST steps answered by " .. username() .. " (" .. (isClientSide() and "client" or "solo") .. ")" }
    for _, r in ipairs(S.records) do
        local line = r.status .. "  " .. r.step .. " #" .. tostring(r.seq) .. " (" .. r.ms .. " ms)"
        if r.message then line = line .. " " .. r.message end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = (sum.ok and "OK" or "FAILED") .. " - " .. sum.total .. " step(s): " .. sum.pass .. " pass, "
        .. sum.fail .. " fail, " .. sum.error .. " error, " .. sum.skip .. " skip"
    local ok, why = RST.writeLines(path, lines)
    if ok then S.file = path else log("ERROR: steps report not written: " .. tostring(why)) end
    return ok
end

function S.summary()
    local sum = { total = #S.records, pass = 0, fail = 0, error = 0, skip = 0 }
    for _, r in ipairs(S.records) do
        local k = string.lower(r.status)
        sum[k] = (sum[k] or 0) + 1
    end
    sum.ok = sum.fail == 0 and sum.error == 0
    sum.file = S.file
    return sum
end

local function record(job, res)
    S.records[#S.records + 1] = { seq = job.seq, step = job.step, status = res.status, message = res.message,
        ms = math.floor(now() - job.ctx.startedMs) }
    log(res.status .. " " .. job.step .. " #" .. tostring(job.seq) .. (res.message and (": " .. res.message) or ""))
    S.writeReport()
end

local function finish(job, res)
    if job.done then return end
    job.done = true
    res = normalize(res)
    record(job, res)
    local ok, err = pcall(job.reply, res)
    if not ok then log("ERROR: answer of " .. job.step .. " #" .. tostring(job.seq) .. " not sent: " .. oneLine(err)) end
end

local function callPoll(job)
    local ok, res = pcall(job.poll, job.ctx)
    if not ok then return { status = "ERROR", message = "poll raised: " .. oneLine(res) } end
    if res == nil and job.ctx.final then
        return { status = "FAIL", message = "no result within " .. job.ms .. " ms" }
    end
    return res
end

-- Runs the handler of a step; reply(result) is called once (now or at a later tick).
function S.start(seq, step, args, ms, reply)
    ms = tonumber(ms) or S.DEFAULT_MS
    local t0 = now()
    local job = { seq = seq, step = step, ms = ms, reply = reply,
        ctx = { step = step, seq = seq, user = rawName(), startedMs = t0, deadlineMs = t0 + ms, final = false } }
    local handler = S.handlers[step]
    if handler == nil then
        finish(job, { status = "ERROR", message = "unknown step '" .. tostring(step) .. "' on this client" })
        return job
    end
    local ok, res = pcall(handler, type(args) == "table" and args or {}, job.ctx)
    if not ok then
        finish(job, { status = "ERROR", message = "handler raised: " .. oneLine(res) })
        return job
    end
    if type(res) == "function" then
        job.poll = res
        local first = callPoll(job)
        if first ~= nil then
            finish(job, first)
        else
            S.jobs[#S.jobs + 1] = job
            S.attachTick()
        end
        return job
    end
    finish(job, res)
    return job
end

local function onTick() RST.Steps.tick() end

-- OnTick subscribed once while handlers poll (idempotent); removed by S.tick when none is left.
function S.attachTick()
    if S._ticking or type(Events) ~= "table" or Events.OnTick == nil then return end
    Events.OnTick.Add(onTick)
    S._ticking = onTick
end

-- One tick of the running handlers (OnTick on clients and solo).
function S.tick()
    if #S.jobs == 0 then
        if S._ticking and type(Events) == "table" and Events.OnTick then Events.OnTick.Remove(S._ticking) end
        S._ticking = nil
        return
    end
    local keep = {}
    local jobs = S.jobs
    S.jobs = {}
    for _, job in ipairs(jobs) do
        if not job.done then
            if now() >= job.ctx.deadlineMs then job.ctx.final = true end
            local res = callPoll(job)
            if res ~= nil then finish(job, res) else keep[#keep + 1] = job end
        end
    end
    for _, job in ipairs(S.jobs) do keep[#keep + 1] = job end -- started meanwhile
    S.jobs = keep
end

-- OnServerCommand: a step asked by the server.
function S.onServerCommand(module, command, args)
    if module ~= S.MODULE or command ~= "ask" or type(args) ~= "table" then return end
    local seq, step = args.seq, args.step
    S.start(seq, step, args.args, args.ms, function(res)
        local player = type(getPlayer) == "function" and getPlayer() or nil
        if player == nil then
            log("ERROR: no local player to answer " .. tostring(step))
            return
        end
        sendClientCommand(player, S.MODULE, "answer", { seq = seq, step = step, status = res.status,
            message = res.message, data = res.data })
    end)
end

-- ---------------------------------------------------------------- authority side

local function nameOf(player)
    if player == nil then return nil end
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return nil
end

local function onlinePlayers()
    local out = {}
    if type(getOnlinePlayers) ~= "function" then return out end
    local ok = pcall(function()
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            local name = nameOf(p)
            if name ~= nil then out[#out + 1] = { name = name, player = p } end
        end
    end)
    if not ok then return {} end
    return out
end

-- Online player of an account on the server, or nil.
function S.playerOf(name)
    for _, e in ipairs(onlinePlayers()) do
        if e.name == name then return e.player end
    end
    return nil
end

function S.others(t)
    if not isServerSide() then return {} end
    local me = nameOf(t and t.ctx and t.ctx.player)
    local out = {}
    for _, e in ipairs(onlinePlayers()) do
        if e.name ~= me then out[#out + 1] = e.name end
    end
    return out
end

-- Targets of opts.target: list of { name, player } (player nil in solo).
function S.targets(t, target)
    target = target or "others"
    if S.isSolo() then
        if target == "requester" or target == "all" then return { { name = S.LOCAL } } end
        if type(target) == "table" then
            local out = {}
            for _, n in ipairs(target) do
                if n == S.LOCAL then out[#out + 1] = { name = S.LOCAL } end
            end
            return out
        end
        return {}
    end
    local me = nameOf(t and t.ctx and t.ctx.player)
    local out = {}
    for _, e in ipairs(onlinePlayers()) do
        local take
        if target == "all" then
            take = true
        elseif target == "requester" then
            take = e.name == me
        elseif target == "others" then
            take = e.name ~= me
        elseif type(target) == "table" then
            take = false
            for _, n in ipairs(target) do if n == e.name then take = true end end
        end
        if take then out[#out + 1] = e end
    end
    return out
end

local function describeTarget(target)
    if type(target) == "table" then return table.concat(target, ",") end
    return tostring(target or "others")
end

-- Result table handed to after(): every expected account, in the order of the targets.
function S.result(seq)
    local ask = S.asks[seq]
    local out = { list = {}, by = {}, none = ask == nil or #ask.users == 0 }
    if ask == nil then return out end
    for _, name in ipairs(ask.users) do
        local a = ask.answers[name]
        local e = { user = name, status = a and a.status or "MISSED", message = a and a.message or nil,
            data = a and a.data or nil }
        out.list[#out.list + 1] = e
        out.by[name] = e
    end
    return out
end

local function complete(ask)
    for _, name in ipairs(ask.users) do
        if ask.answers[name] == nil then return false end
    end
    return true
end

local function conclude(t, seq, opts)
    local ask = S.asks[seq]
    local result = S.result(seq)
    for _, e in ipairs(result.list) do
        local who = "client " .. e.user
        if e.status == "MISSED" then
            t:ok(false, who .. " missed step '" .. ask.step .. "' within " .. ask.ms .. " ms")
        elseif opts.assert ~= false then
            if e.status == "SKIP" then
                t:note(who .. ": step '" .. ask.step .. "' skipped: " .. tostring(e.message))
                t:ok(true)
            else
                t:ok(e.status == "PASS", who .. ": step '" .. ask.step .. "' " .. e.status .. ": "
                    .. tostring(e.message))
                if e.status == "PASS" and e.message then t:note(who .. ": " .. ask.step .. ": " .. e.message) end
            end
        end
    end
    S.asks[seq] = nil
    return result
end

function S.ask(t, step, args, opts, after)
    opts = opts or {}
    if isClientSide() then t:skip("RST.Steps.ask is for the authority (server or solo), not an MP client") end
    local ms = tonumber(opts.timeoutMs) or S.DEFAULT_MS
    local targets = S.targets(t, opts.target)
    if #targets == 0 then
        local why = "no " .. describeTarget(opts.target) .. " client online: step '" .. step .. "' not checked"
        if opts.none == "skip" then t:skip(why) end
        t:note(why)
        if after then return after(t, { list = {}, by = {}, none = true }) end
        return
    end
    S.seq = S.seq + 1
    local seq = S.seq
    local ask = { step = step, ms = ms, users = {}, expected = {}, answers = {} }
    for _, e in ipairs(targets) do
        ask.users[#ask.users + 1] = e.name
        ask.expected[e.name] = true
    end
    S.asks[seq] = ask
    if S.isSolo() then
        S.start(seq, step, args, ms, function(res)
            if S.asks[seq] then S.asks[seq].answers[S.LOCAL] = res end
        end)
    else
        for _, e in ipairs(targets) do
            local ok, err = pcall(sendServerCommand, e.player, S.MODULE, "ask", { seq = seq, step = step, args = args,
                ms = ms })
            if not ok then log("ERROR: step " .. step .. " not sent to " .. e.name .. ": " .. oneLine(err)) end
        end
        log("step " .. step .. " #" .. seq .. " asked to " .. table.concat(ask.users, ", "))
    end
    local deadline = now() + ms + S.MARGIN_MS
    t:waitQuiet(function() return complete(ask) or now() >= deadline end, nil, function(t2)
        local result = conclude(t2, seq, opts)
        if after then return after(t2, result) end
    end)
end

-- OnClientCommand (server): an answer.
function S.onClientCommand(module, command, player, args)
    if module ~= S.MODULE or command ~= "answer" or type(args) ~= "table" then return end
    local name = nameOf(player) or "?"
    local ask = S.asks[args.seq]
    if ask == nil or not ask.expected[name] or ask.answers[name] ~= nil then
        log("answer of " .. name .. " to step " .. tostring(args.step) .. " #" .. tostring(args.seq) .. " ignored")
        return
    end
    ask.answers[name] = normalize({ status = args.status, message = args.message, data = args.data })
    log("answer of " .. name .. " to step " .. ask.step .. " #" .. tostring(args.seq) .. ": " .. ask.answers[name].status)
end

-- ---------------------------------------------------------------- subscriptions (once per Lua state)

if not S._subscribed and type(Events) == "table" then
    if isServerSide() then
        if Events.OnClientCommand then
            Events.OnClientCommand.Add(function(module, command, player, args)
                RST.Steps.onClientCommand(module, command, player, args)
            end)
        end
    else
        if Events.OnServerCommand then
            Events.OnServerCommand.Add(function(module, command, args) RST.Steps.onServerCommand(module, command, args) end)
        end
    end
    S._subscribed = true
end

return S
