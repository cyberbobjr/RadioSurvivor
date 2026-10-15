--[[
lk.load - load measure of the Living Knox engine on the authority (LK13-T02, shared/LivingKnox/LK_Load.lua, request
{ op = "load" } of server/LivingKnox/LK_Admin.lua). Checked here: a request without an allowed player is refused
without data; a measure started by the administrator (t.ctx.player) wraps the engine subscribers at the next tick,
measures for RST_LK_LOAD_MS (default 20000 ms of real time), then the report gives the cost per tick and per module,
the network commands, the registry writes, the saved state size and the budget check (all report lines are kept as
notes of the test, also written to console.txt as "load: ..." lines), and the stop restores the network wrapper.
Tag "server" only: nothing in the world is changed (no "world" tag, no test save needed). Solo:
RST.run({ suite = "lk.load", tags = "server" }). Dedicated server: RST.server({ suite = "lk.load" }) from an admin
client (moderator or admin role); RST_LK_LOAD_MS = 60000 on the server Lua state is not reachable from a client, so
the default length applies there.
A measure already running (started by an administrator) is left alone: the measure test is then skipped.
Not checked here: the measure on an MP client (debug console LivingKnox.Load.start() / .print() / .stop()), the 5
groups and 4 players protocol of docs/validation/charge-protocole.md. Outside the game: tests/test_lk_load.py.
Solo window (2026-10-15, solo client only, skipped elsewhere): the measure is started, read and stopped with the
buttons of the admin window (client/LivingKnox/LK_AdminView.lua, op "load"); the report shown in the window gives the
cost per tick, one line per module and the budget verdict; screenshot lk_load_window_*.png (Zomboid/Screenshots).
]]

require "RST/RST"

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the load measure of the authority is not reachable from an MP client")
    end
    local E = LK()
    if E == nil or type(E.Load) ~= "table" or type(E.Load.start) ~= "function" or type(E.Admin) ~= "table"
        or type(E.Admin.request) ~= "function" then
        t:skip("LivingKnox.Load / LivingKnox.Admin (LK13-T02) are not loaded here")
    end
    return E
end

local function measureMs()
    local v = tonumber(RST_LK_LOAD_MS)
    if v == nil or v < 2000 then return 20000 end
    return v
end

RST.suite("lk.load", { tags = { "server" }, testTimeoutMs = 180000 }, function(s)
    s.test("module exports", function(t)
        local E = module(t)
        for _, name in ipairs({ "start", "install", "counter", "summary", "lines", "stop", "stateSize", "check" }) do
            t:eq("function", type(E.Load[name]), "LivingKnox.Load." .. name)
        end
        t:eq(true, E.Admin.OPS.load, "admin operation load")
    end)

    s.test("a request without an allowed player is refused without data", function(t)
        local E = module(t)
        local before = E.Load.active
        local r = E.Admin.request(nil, { op = "load", action = "start", n = 5 })
        t:eq(false, r.ok, "start accepted")
        t:eq("denied", r.err, "error")
        for k in pairs(r) do
            t:ok(k == "n" or k == "op" or k == "ok" or k == "err", "refusal carries the field " .. k)
        end
        t:ok(E.Load.active == before, "a refused request changed the measure")
    end)

    s.test("solo window: measure started, read and stopped with the admin window buttons", function(t)
        local E = module(t)
        if type(isServer) == "function" and isServer() then t:skip("solo client window (not on a server)") end
        local V = E.AdminView
        if type(V) ~= "table" or V.open == nil or V.loadSend == nil then
            t:skip("admin window with the load buttons is not loaded here (solo client only)")
        end
        if E.Load.active ~= nil then t:skip("a measure is already running (LivingKnox.Load.stop() to end it)") end
        local win = V.open()
        t:ok(win ~= nil and win.loadStartBtn ~= nil, "admin window without the load buttons")
        t:defer(function()
            if E.Load.active ~= nil then E.Load.stop() end
            if V.state.window ~= nil then V.state.window:close() end
        end, "stop the measure, close the window")
        local function press(b) b.onclick(b.target, b) end
        press(win.loadStartBtn)
        t:ok(E.Load.active ~= nil, "measure not started by the window button")
        t:ok(V.state.load ~= nil and V.state.load.running == true, "window does not show the running measure")
        t:eq(false, win.loadStartBtn.enable, "start button enabled while the measure runs")
        t:waitUntil(function()
            local cur = E.Load.active
            return cur ~= nil and cur.installed and cur.ticks > 0
        end, 10000, function(t2)
            t2:sleep(5000, function(t3)
                press(win.loadReportBtn)
                local rep = V.state.load
                t3:ok(rep ~= nil and rep.action == "report" and rep.running == true, "report not shown by the window")
                local text = tostring(win.detail.text)
                t3:ok(string.find(text, getText("IGUI_LK_Admin_LoadTitle"), 1, true) ~= nil, "report title missing")
                local tick, mod, budget = false, false, false
                for _, line in ipairs(rep.lines or {}) do
                    if string.find(line, "ms/tick", 1, true) and string.find(line, "load on", 1, true) then tick = true end
                    if string.find(line, "module ", 1, true) == 1 then mod = true end
                    if string.find(line, "budget: ", 1, true) == 1 then budget = true end
                end
                t3:ok(tick, "no cost per tick in the report")
                t3:ok(mod, "no module line in the report")
                t3:ok(budget, "no budget verdict in the report")
                t3:ok(string.find(text, "budget: ", 1, true) ~= nil, "budget verdict not shown in the window")
                t3:sleep(1000, function(t4)
                    local shot = "lk_load_window_" .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight()
                        .. ".png"
                    local okShot, err = pcall(takeScreenshot, shot)
                    t4:ok(okShot, "screenshot failed: " .. tostring(err))
                    t:note("screenshot " .. shot)
                    press(win.loadStopBtn)
                    t4:eq(nil, E.Load.active, "measure still active after the stop button")
                    t4:ok(V.state.load ~= nil and V.state.load.running == false, "window does not show the stop")
                    t4:ok(win.loadStartBtn.enable ~= false, "start button disabled after the stop")
                    for _, line in ipairs(V.state.load.lines or {}) do t:note(line) end
                end)
            end)
        end, "the measure was not installed within 10 s")
    end)

    s.test("measure of the authority: cost, network, saves, state, budget", function(t)
        local E = module(t)
        if E.Load.active ~= nil then t:skip("a measure is already running (LivingKnox.Load.stop() to end it)") end
        local p = t.ctx and t.ctx.player
        -- An admin request needs a requesting player: none on a dedicated server run without client (autorun).
        if p == nil then t:skip("no requesting player (t.ctx.player): run it from a client (RST.server)") end
        local A = E.Admin
        local r = A.request(p, { op = "load", action = "start", n = 1, windowMs = 5000 })
        t:ok(r.ok, "start refused: " .. tostring(r.err))
        t:defer(function()
            if E.Load.active ~= nil then E.Load.stop() end
        end, "stop the measure")
        local sendBefore = sendServerCommand
        t:note("measuring for " .. measureMs() .. " ms")
        t:waitUntil(function()
            local cur = E.Load.active
            return cur ~= nil and cur.installed and cur.ticks > 0
        end, 10000, function(t2)
            t2:sleep(measureMs(), function(t3)
                local rep = A.request(p, { op = "load", action = "report", n = 2 })
                t3:ok(rep.ok, "report refused: " .. tostring(rep.err))
                t3:ok(rep.running == true, "report: measure not running")
                local stop = A.request(p, { op = "load", action = "stop", n = 3 })
                t3:ok(stop.ok, "stop refused: " .. tostring(stop.err))
                t3:eq(false, stop.running, "running after stop")
                for _, line in ipairs(stop.lines or {}) do t3:note(line) end
                local sum = E.Load.last
                t3:ok(sum ~= nil and sum.ticks > 0, "no tick measured")
                t3:ok(sum.measured > 0, "no engine subscriber measured")
                t3:ok(#sum.modules > 0, "no module in the report")
                t3:ok(type(sum.state) == "table" and sum.state.groups >= 0, "no saved state size")
                t3:ok(type(sum.over) == "table", "no budget check")
                t3:ok(sendServerCommand == sendBefore, "network wrapper not removed by the stop")
                t3:eq(nil, E.Load.active, "measure still active")
            end)
        end, "the measure was not installed within 10 s")
    end)
end)
