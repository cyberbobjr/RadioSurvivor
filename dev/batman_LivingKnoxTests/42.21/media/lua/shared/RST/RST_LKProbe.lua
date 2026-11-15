--[[
RST_LKProbe - measures of the Living Knox engine on the machine that runs it (RST.LKProbe), for the milestone
suite lk.milestone1 (LK02-T08) and the observer measures of the MP session. Development mod only. Nothing of the
published mod is changed: the probe wraps, then restores, what the engine exposes.

    local P = RST.LKProbe
    local probe = P.start()        starts a probe here (wrappers installed at the next OnTickEvenPaused, then
                                   probe.installed is true); nil and a reason when one is already active
    P.split(probe, label)          closes the current phase under this label (cost and network of each phase are
                                   given apart by P.lines; the time after the last split is the phase "rest")
    P.stop(probe)                  removes it; returns the summary (also kept in probe.summary)
    P.lines(summary)               summary as text lines ("cost ...", "scan ...", "net ...", "stats ...")

What is wrapped while the probe is active, and restored by P.stop:
    - every OnTick subscriber of the engine (LivingKnox.handlers["OnTick/<key>"], registered by LivingKnox.subscribe):
      removed from Events.OnTick and added again inside a wrapper that reads getTimestampMs() before and after the
      call; same function, same arguments, no pcall (an error still reaches the engine as before). P.stop puts the
      original back unless the module was reloaded meanwhile (LivingKnox.subscribe then removed the wrapper already).
      Side effect: the engine subscribers move to the end of the OnTick list, in key order, and stay there.
    - LivingKnox.Bodies.scan (authority): counts the zombies examined per call and the size of the zombie list;
      slices = calls with the budget of Bodies.tick (Bodies.SCAN_BUDGET), full = other calls (scanAll);
    - the global sendServerCommand on a server (sendClientCommand on an MP client): messages of module
      "LivingKnox" counted per command, with an approximate size (sum of the key and string value lengths, 8 per
      number, 1 per boolean, 2 per table); received messages counted by an OnClientCommand (server) or
      OnServerCommand (client) subscriber of the probe. In solo nothing travels: every network counter stays 0.
    - an OnTick counter added last: ticks seen, and the engine time of each tick (max, ticks at 1 ms or more).

Resolution: getTimestampMs() has a 1 ms step (System.currentTimeMillis, LuaManager.java:7476-7479; Kahlua os.time
also reads it, OsLib.java:75): one call reads 0 or 1 ms. The mean over many calls is the estimate (each reading
is the true duration on average when the call starts at a random point of the millisecond); the max per call is
an upper bound to the next millisecond. Engine stats (LivingKnox.<Module>.stats) are compared before and after.

Console (debug mode, any machine; local read only, nothing is sent):
    LKM.start()    starts a probe here
    LKM.stop()     stops it and prints "[LKM] measure observer ..." lines (cost per tick, network, stats)
]]

require "RST/RST"

RST.LKProbe = RST.LKProbe or {}
local P = RST.LKProbe

P.MODULE = "LivingKnox"
P.STAT_MODULES = { "Bodies", "ZombieGuard", "Anim", "Equipment", "Directives", "Executor", "Presentation" }

local function now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

local function startsWith(s, prefix)
    return string.sub(s, 1, string.len(prefix)) == prefix
end

local function side()
    if isServer() then return "server" end
    if isClient() then return "client" end
    return "solo"
end

-- Approximate size of network arguments (see the header).
function P.size(v, depth)
    local t = type(v)
    if t == "string" then return string.len(v) end
    if t == "number" then return 8 end
    if t == "boolean" then return 1 end
    if t ~= "table" then return 0 end
    depth = depth or 0
    if depth > 8 then return 0 end
    local n = 2
    for k, x in pairs(v) do n = n + P.size(k, depth + 1) + P.size(x, depth + 1) end
    return n
end

local function count(bucket, command, args)
    local c = bucket.byCmd[command]
    if c == nil then
        c = { count = 0, bytes = 0 }
        bucket.byCmd[command] = c
    end
    local bytes = P.size(args)
    c.count = c.count + 1
    c.bytes = c.bytes + bytes
    bucket.count = bucket.count + 1
    bucket.bytes = bucket.bytes + bytes
end

-- Sent message: (module, command, args) or (player, module, command, args). The original is called with the same
-- arguments (varargs: never an extra nil, the Java overloads differ by their argument count).
local function countSent(bucket, ...)
    local a, b, c, d = ...
    if type(a) == "string" then
        if a == P.MODULE then count(bucket, tostring(b), c) end
    elseif b == P.MODULE then
        count(bucket, tostring(c), d)
    end
end

local function newBucket() return { count = 0, bytes = 0, byCmd = {} } end

local function snapshotStats()
    local out = {}
    for _, name in ipairs(P.STAT_MODULES) do
        local m = LivingKnox and LivingKnox[name]
        if type(m) == "table" and type(m.stats) == "table" then
            local copy = {}
            for k, v in pairs(m.stats) do
                if type(v) == "number" then copy[k] = v end
            end
            out[name] = copy
        end
    end
    return out
end

-- ---------------------------------------------------------------- wrappers

local function wrapTicks(probe)
    local handlers = LivingKnox and LivingKnox.handlers or {}
    local slots = {}
    for slot, fn in pairs(handlers) do
        if startsWith(slot, "OnTick/") and type(fn) == "function" then slots[#slots + 1] = slot end
    end
    table.sort(slots)
    for _, slot in ipairs(slots) do
        local fn = handlers[slot]
        local h = { slot = slot, fn = fn, calls = 0, ms = 0, max = 0 }
        local cur = probe.current
        h.wrapper = function(...)
            local t0 = now()
            fn(...)
            local dt = now() - t0
            h.calls = h.calls + 1
            h.ms = h.ms + dt
            if dt > h.max then h.max = dt end
            cur.ms = cur.ms + dt
        end
        Events.OnTick.Remove(fn)
        Events.OnTick.Add(h.wrapper)
        handlers[slot] = h.wrapper
        probe.ticks[#probe.ticks + 1] = h
    end
end

local function unwrapTicks(probe)
    local handlers = LivingKnox and LivingKnox.handlers or {}
    for _, h in ipairs(probe.ticks) do
        if handlers[h.slot] == h.wrapper then
            Events.OnTick.Remove(h.wrapper)
            Events.OnTick.Add(h.fn)
            handlers[h.slot] = h.fn
        else
            probe.reloaded[#probe.reloaded + 1] = h.slot
        end
    end
end

local function wrapScan(probe)
    local Bodies = LivingKnox and LivingKnox.Bodies
    if type(Bodies) ~= "table" or type(Bodies.scan) ~= "function" then return end
    local original = Bodies.scan
    local s = probe.scan
    local wrapper = function(budget)
        local n = original(budget)
        local list = getCell() and getCell():getZombieList()
        local size = list and list:size() or 0
        if budget == Bodies.SCAN_BUDGET then
            s.slices = s.slices + 1
            s.examined = s.examined + n
            if n > s.max then s.max = n end
        else
            s.full = s.full + 1
            s.fullExamined = s.fullExamined + n
        end
        if size > s.maxList then s.maxList = size end
        return n
    end
    Bodies.scan = wrapper
    probe.scanHook = { original = original, wrapper = wrapper }
end

local function unwrapScan(probe)
    local hook = probe.scanHook
    local Bodies = LivingKnox and LivingKnox.Bodies
    if hook and Bodies and Bodies.scan == hook.wrapper then Bodies.scan = hook.original end
end

local function wrapNet(probe)
    local out, inc = probe.net.out, probe.net.inc
    if isServer() and type(sendServerCommand) == "function" then
        local original = sendServerCommand
        local wrapper = function(...)
            countSent(out, ...)
            return original(...)
        end
        sendServerCommand = wrapper
        probe.netHook = { name = "sendServerCommand", original = original, wrapper = wrapper }
        probe.recv = function(module, command, _, args)
            if module == P.MODULE then count(inc, tostring(command), args) end
        end
        Events.OnClientCommand.Add(probe.recv)
        probe.recvEvent = "OnClientCommand"
    elseif isClient() and type(sendClientCommand) == "function" then
        local original = sendClientCommand
        local wrapper = function(...)
            countSent(out, ...)
            return original(...)
        end
        sendClientCommand = wrapper
        probe.netHook = { name = "sendClientCommand", original = original, wrapper = wrapper }
        probe.recv = function(module, command, args)
            if module == P.MODULE then count(inc, tostring(command), args) end
        end
        Events.OnServerCommand.Add(probe.recv)
        probe.recvEvent = "OnServerCommand"
    end
end

local function unwrapNet(probe)
    local hook = probe.netHook
    if hook then
        if hook.name == "sendServerCommand" and sendServerCommand == hook.wrapper then
            sendServerCommand = hook.original
        elseif hook.name == "sendClientCommand" and sendClientCommand == hook.wrapper then
            sendClientCommand = hook.original
        end
    end
    if probe.recv then Events[probe.recvEvent].Remove(probe.recv) end
end

-- ---------------------------------------------------------------- start / split / stop

local function snap(probe, label)
    local engine = 0
    for _, h in ipairs(probe.ticks) do engine = engine + h.ms end
    local o, i, sc = probe.net.out, probe.net.inc, probe.scan
    return { label = label, ms = now(), ticks = probe.tick.count, engine = engine, sent = o.count, sentB = o.bytes,
        recv = i.count, recvB = i.bytes, slices = sc.slices, examined = sc.examined }
end

function P.split(probe, label)
    probe = probe or P.active
    if probe == nil or probe.summary then return false end
    probe.splits[#probe.splits + 1] = snap(probe, tostring(label))
    return true
end

local function phases(probe)
    local out = {}
    local list = probe.splits
    for i = 2, #list do
        local a, b = list[i - 1], list[i]
        local ticks = b.ticks - a.ticks
        out[#out + 1] = { label = b.label, ms = b.ms - a.ms, ticks = ticks, engine = b.engine - a.engine,
            perTickMs = ticks > 0 and (b.engine - a.engine) / ticks or 0, sent = b.sent - a.sent,
            sentB = b.sentB - a.sentB, recv = b.recv - a.recv, recvB = b.recvB - a.recvB,
            slices = b.slices - a.slices, examined = b.examined - a.examined }
    end
    return out
end

local function install(probe)
    Events.OnTickEvenPaused.Remove(probe.installer)
    probe.installed = true
    probe.startMs = now()
    probe.stats0 = snapshotStats()
    probe.splits = { snap(probe, "start") }
    wrapTicks(probe)
    wrapScan(probe)
    wrapNet(probe)
    -- Added last: runs after the engine wrappers of the same tick and closes the tick.
    local cur, tk = probe.current, probe.tick
    probe.counter = function()
        tk.count = tk.count + 1
        tk.total = tk.total + cur.ms
        if cur.ms > tk.max then tk.max = cur.ms end
        if cur.ms >= 1 then tk.busy = tk.busy + 1 end
        cur.ms = 0
    end
    Events.OnTick.Add(probe.counter)
end

-- The wrappers are installed by a one-shot OnTickEvenPaused subscriber: that event comes before OnTick in the same
-- frame (IngameState.java:1380 and 1681), so no engine subscriber is called twice or skipped in the frame of the
-- installation, whether P.start is called from OnTick (RST in solo), OnTickEvenPaused (RST on a server) or the
-- console. probe.installed tells when the measure has begun.
function P.start()
    if P.active ~= nil then return nil, "a probe is already active" end
    if type(LivingKnox) ~= "table" then return nil, "LivingKnox is not loaded" end
    local probe = { side = side(), startMs = now(), ticks = {}, reloaded = {}, current = { ms = 0 },
        tick = { count = 0, max = 0, busy = 0, total = 0 },
        scan = { slices = 0, examined = 0, max = 0, full = 0, fullExamined = 0, maxList = 0 },
        net = { out = newBucket(), inc = newBucket() }, installed = false }
    probe.splits = { snap(probe, "start") }
    probe.stats0 = snapshotStats()
    probe.installer = function() install(probe) end
    Events.OnTickEvenPaused.Add(probe.installer)
    P.active = probe
    return probe
end

local function diffStats(a, b)
    local out = {}
    for name, now1 in pairs(b) do
        local before = a[name] or {}
        local d = {}
        for k, v in pairs(now1) do
            local delta = v - (before[k] or 0)
            if delta ~= 0 then d[k] = delta end
        end
        out[name] = d
    end
    return out
end

function P.stop(probe)
    probe = probe or P.active
    if probe == nil then return nil, "no active probe" end
    if probe.summary then return probe.summary end
    Events.OnTickEvenPaused.Remove(probe.installer)
    if probe.counter then Events.OnTick.Remove(probe.counter) end
    local last = probe.splits[#probe.splits]
    if probe.tick.count > last.ticks or #probe.splits == 1 then P.split(probe, "rest") end
    unwrapTicks(probe)
    unwrapScan(probe)
    unwrapNet(probe)
    if P.active == probe then P.active = nil end
    local handlers = {}
    local calls, ms = 0, 0
    for _, h in ipairs(probe.ticks) do
        handlers[#handlers + 1] = { key = string.sub(h.slot, 8), calls = h.calls, ms = h.ms, max = h.max }
        calls = calls + h.calls
        ms = ms + h.ms
    end
    local tk = probe.tick
    local summary = { side = probe.side, durationMs = now() - probe.startMs, ticks = tk.count, engineMs = ms,
        calls = calls, perTickMs = tk.count > 0 and ms / tk.count or 0, maxTickMs = tk.max, busyTicks = tk.busy,
        handlers = handlers, scan = probe.scan, net = probe.net, reloaded = probe.reloaded, phases = phases(probe),
        stats = diffStats(probe.stats0, snapshotStats()) }
    probe.summary = summary
    return summary
end

-- ---------------------------------------------------------------- text

local function fixed(v, decimals)
    local m = 10 ^ (decimals or 3)
    return tostring(math.floor(v * m + 0.5) / m)
end
P.fixed = fixed

local function bucketText(b)
    local parts = {}
    local names = {}
    for name in pairs(b.byCmd) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local c = b.byCmd[name]
        parts[#parts + 1] = name .. " " .. c.count .. "/" .. c.bytes .. "B"
    end
    return b.count .. " msg, " .. b.bytes .. " B" .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
end

function P.lines(s)
    local out = {}
    local per = {}
    for _, h in ipairs(s.handlers) do
        per[#per + 1] = h.key .. " " .. fixed(h.calls > 0 and h.ms / h.calls or 0) .. " ms/call x" .. h.calls
            .. " (max " .. h.max .. ")"
    end
    out[#out + 1] = "cost on " .. s.side .. ": " .. fixed(s.perTickMs) .. " ms/tick over " .. s.ticks .. " ticks ("
        .. s.engineMs .. " ms in " .. s.calls .. " engine OnTick calls, max " .. s.maxTickMs .. " ms in one tick, "
        .. s.busyTicks .. " ticks >= 1 ms, " .. fixed(s.durationMs / 1000, 1) .. " s); " .. table.concat(per, "; ")
    local sc = s.scan
    out[#out + 1] = "scan: " .. sc.slices .. " slices, " .. fixed(sc.slices > 0 and sc.examined / sc.slices or 0, 2)
        .. " zombies examined per slice (max " .. sc.max .. "), zombie list up to " .. sc.maxList .. ", "
        .. sc.full .. " full scans (" .. sc.fullExamined .. " examined)"
    out[#out + 1] = "net on " .. s.side .. ": sent " .. bucketText(s.net.out) .. "; received " .. bucketText(s.net.inc)
    if #s.phases > 1 then
        for _, ph in ipairs(s.phases) do
            out[#out + 1] = "phase " .. ph.label .. ": " .. fixed(ph.perTickMs) .. " ms/tick over " .. ph.ticks
                .. " ticks (" .. fixed(ph.ms / 1000, 1) .. " s), sent " .. ph.sent .. " msg / " .. ph.sentB
                .. " B, received " .. ph.recv .. " msg / " .. ph.recvB .. " B, scan " .. ph.slices .. " slices / "
                .. ph.examined .. " examined"
        end
    end
    local mods = {}
    for _, name in ipairs(P.STAT_MODULES) do
        local d = s.stats[name]
        if d then
            local keys = {}
            for k in pairs(d) do keys[#keys + 1] = k end
            table.sort(keys)
            local kv = {}
            for _, k in ipairs(keys) do kv[#kv + 1] = k .. "=" .. tostring(d[k]) end
            if #kv > 0 then mods[#mods + 1] = name .. " " .. table.concat(kv, " ") end
        end
    end
    out[#out + 1] = "stats delta: " .. (#mods > 0 and table.concat(mods, "; ") or "none")
    if #s.reloaded > 0 then
        out[#out + 1] = "reloaded during the probe (not measured to the end): " .. table.concat(s.reloaded, ", ")
    end
    return out
end

-- ---------------------------------------------------------------- console (observer)

LKM = LKM or {}

function LKM.start()
    if type(isDebugEnabled) == "function" and not isDebugEnabled() then
        print("[LKM] refused: debug mode is off (start the game with -debug)")
        return false
    end
    local probe, why = P.start()
    if probe == nil then
        print("[LKM] probe not started: " .. tostring(why))
        return false
    end
    print("[LKM] probe started on " .. probe.side .. " (measures from the next tick on)")
    return true
end

function LKM.stop()
    local s, why = P.stop()
    if s == nil then
        print("[LKM] " .. tostring(why))
        return false
    end
    for _, line in ipairs(P.lines(s)) do print("[LKM] measure observer " .. line) end
    if LivingKnox and LivingKnox.Presentation and LivingKnox.Presentation.stats then
        local st = LivingKnox.Presentation.stats
        print("[LKM] measure observer pose relay delay: last " .. tostring(st.lastDelay) .. " ms, max "
            .. tostring(st.maxDelay) .. " ms, mean " .. fixed(LivingKnox.Presentation.meanDelay(), 1) .. " ms over "
            .. tostring(st.samples) .. " pose(s)")
    end
    return true
end

return P
