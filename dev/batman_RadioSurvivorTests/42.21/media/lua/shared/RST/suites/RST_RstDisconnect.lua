--[[
rst.disconnect - a client disconnects while the server runs the suites it asked (E01-T05: "deconnexion pendant un
passage"; server/RST/RST_Server.lua: report kept in the server file when the requester is offline, next run
accepted). Base "rst.disconnect" of the phased MP run (autoclient.py --mp --clients 2 --phases reconnect2,...
--server-campaign mp-persist):
    rst.disconnect.before            (opt-in "manual", run by client 1) arms client 2 (RST.Steps "rst.run.later",
                                     RST_PeerChecks2.lua): as soon as the run in progress ends, client 2 sends the
                                     real RST.server request (module "RST", command "run") for rst.disconnect.slow,
                                     retried while the server answers "busy". Snapshot written: account of client 2.
    rst.disconnect.slow              (opt-in "manual", requested by client 2 only) the run of client 2: records its
                                     start in the snapshot, then waits until its requester is offline (the launcher
                                     quits client 2 for the reconnect2 action right after step 0), records it, and
                                     ends: the server finishes the run without its requester.
    rst.disconnect.after-reconnect2  (run by client 1 once client 2 is back) the snapshot says the run of client 2
                                     started, saw its requester leave and ended; the last server result
                                     (RST.Server.lastResult) is that run, written to the server report file with its
                                     test passed; this very run was accepted (the server is not left busy); client 2
                                     is online again. Then the snapshot is consumed.
Tags "server" and "manual" (no "world": nothing in the world is touched): authority only, exact names only. Solo
or without a second client: SKIP (explicit).
Snapshot: Zomboid/Lua/batman_RadioSurvivor/tests/rst-disconnect.txt of the server (RST_Persist).
Outside the game: tests/test_persist_suites.py (RstDisconnectTests).
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_Persist"
require "RST/RST_PeerChecks2"

RST.RstDisconnect = RST.RstDisconnect or {}
local D = RST.RstDisconnect
local Steps = RST.Steps

D.FILE = "rst-disconnect.txt"
D.HEADER = "RSTDISCONNECT1"
D.SLOW = "rst.disconnect.slow"
D.OFFLINE_MS = 180000   -- requester gone: the launcher quits client 2 right after step 0
D.BACK_MS = 60000       -- client 2 online again after the reconnection

local function isServerSide() return type(isServer) == "function" and isServer() end

local function nameOf(player)
    if player == nil then return nil end
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return nil
end

local function serverWithPeer(t)
    if not isServerSide() then
        t:skip("a disconnection during a run needs the phased MP run (autoclient.py --mp --clients 2 --phases "
            .. "reconnect2, base rst.disconnect)")
    end
    local others = Steps.others(t)
    if #others == 0 then t:skip("no second client online (--clients 2)") end
    return others[1]
end

local function update(t, fields)
    local snap = RST.Persist.read(D.FILE, D.HEADER) or {}
    for k, v in pairs(fields) do snap[k] = v end
    local ok, why = RST.Persist.write(D.FILE, D.HEADER, snap)
    t:ok(ok, "snapshot not written: " .. tostring(why))
    return snap
end

RST.suite("rst.disconnect.before", { tags = { "server", "manual" }, testTimeoutMs = 30000 }, function(s)
    s.test("client 2 armed to start its own run once this one ends (E01-T05)", function(t)
        local peer = serverWithPeer(t)
        local ok, why = RST.Persist.write(D.FILE, D.HEADER, { peer = peer, armedAt = RST.now() })
        t:ok(ok, "snapshot not written: " .. tostring(why))
        Steps.ask(t, "rst.run.later", { filter = { suite = D.SLOW, tags = { "manual" } } }, { target = { peer },
            timeoutMs = 5000 }, function(t2, res)
            local e = res.by[peer]
            t2:eq("PASS", e and e.status, "client " .. peer .. " not armed")
        end)
    end)
end)

RST.suite(D.SLOW, { tags = { "server", "manual" }, testTimeoutMs = D.OFFLINE_MS + 10000,
    timeoutMs = D.OFFLINE_MS + 20000 }, function(s)
    s.test("the run of client 2 goes on after its requester left", function(t)
        if not isServerSide() then t:skip("requested by an MP client only (rst.disconnect.before)") end
        local requester = nameOf(t.ctx and t.ctx.player)
        local snap = RST.Persist.read(D.FILE, D.HEADER)
        t:ok(snap ~= nil and snap.peer ~= nil, "no rst.disconnect snapshot: run rst.disconnect.before first")
        t:eq(snap.peer, requester, "requester of this run")
        update(t, { started = true, startedAt = RST.now() })
        t:waitUntil(function() return Steps.playerOf(requester) == nil end, D.OFFLINE_MS, function(t2)
            update(t2, { offline = true, offlineAt = RST.now() })
            t2:note("requester " .. requester .. " offline, run going on")
        end, "requester " .. tostring(requester) .. " never left during the run")
    end)
end)

-- Index of the result of test name of suite in a report, or nil.
local function resultOf(report, suite)
    for _, r in ipairs(report and report.results or {}) do
        if r.suite == suite then return r end
    end
    return nil
end

RST.suite("rst.disconnect.after-reconnect2", { tags = { "server", "manual" }, testTimeoutMs = D.BACK_MS + 10000 },
    function(s)
        s.test("the run cut by the disconnection ended, its report kept, the server not left busy (E01-T05)",
            function(t)
                serverWithPeer(t)
                local snap, why = RST.Persist.read(D.FILE, D.HEADER)
                t:ok(snap ~= nil, tostring(why))
                t:defer(function() RST.Persist.consume(D.FILE) end, "snapshot consumed")
                t:ok(snap.started == true, "client " .. tostring(snap.peer) .. " never started its run (armed request "
                    .. "not accepted before its disconnection)")
                t:ok(snap.offline == true, "the run of client " .. tostring(snap.peer) .. " did not see it leave")
                local last = RST.Server and RST.Server.lastResult or nil
                t:ok(type(last) == "table" and type(last.report) == "table", "no previous server result")
                local r = resultOf(last.report, D.SLOW)
                t:ok(r ~= nil, "last server result is not the run of client " .. tostring(snap.peer))
                t:eq("PASS", r.status, D.SLOW .. " in the cut run: " .. tostring(r.message))
                t:ok(last.written == true, "report of the cut run not written: " .. tostring(last.reason))
                t:ok(RST.running(), "this run is not running")
                t:note("cut run: " .. tostring(last.file) .. ", " .. RST.summaryLine(last.report))
                t:waitUntil(function() return Steps.playerOf(snap.peer) ~= nil end, D.BACK_MS, nil,
                    "client " .. tostring(snap.peer) .. " not back online")
            end)
    end)
