--[[
rst.selftest — self-test of the RST engine (assertions, waits in steps driven by ticks). Runs in game
(RST.run("rst")) and outside the game (lupa, tests/test_rst.py; Kahlua VM, tests/test_kahlua.py). Tag "shared": no
game API is used. Deliberate failures live in rst.failures (RST_Failures.lua, opt-in tag "selfcheck").
]]

require "RST/RST"

-- Tolerance of the measured 2 s sleep: one tick at 10 fps is 100 ms; a slow frame or a short hitch stays under
-- the margin. In solo, a pause freezes OnTick while the clock goes on: do not pause during this test.
local SLEEP_MS = 2000
local SLEEP_MARGIN_MS = 1500

RST.suite("rst.selftest", { tags = { "shared" } }, function(s)
    s.test("assertions", function(t)
        t:ok(true)
        t:eq({ a = 1, b = { 2, 3 } }, { a = 1, b = { 2, 3 } })
        t:ne({ 1 }, { 2 })
        t:near(0.3, 0.1 + 0.2, 1e-9)
        t:fails(function() error("expected boom") end, "expected boom")
        local same, path = RST.deepEqual({ x = { y = 1 } }, { x = { y = 2 } })
        t:eq(false, same)
        t:eq(".x.y", path)
    end)

    s.test("assertion signal comes back intact through pcall", function(t)
        local ok, err = pcall(function() t:eq(1, 2, "inner") end)
        t:eq(false, ok)
        t:eq("table", type(err), "raised object")
        t:eq("inner: expected 1, got 2", type(err) == "table" and err.message or tostring(err))
    end)

    s.test("sleep 2 s measured by RST.now", function(t)
        local t0 = RST.now()
        t:sleep(SLEEP_MS, function(t2)
            local elapsed = RST.now() - t0
            t2:ok(elapsed >= SLEEP_MS, "slept " .. tostring(elapsed) .. " ms, less than " .. SLEEP_MS)
            t2:ok(elapsed < SLEEP_MS + SLEEP_MARGIN_MS, "slept " .. tostring(elapsed) .. " ms, more than "
                .. (SLEEP_MS + SLEEP_MARGIN_MS))
        end)
    end)

    s.test("waitUntil passes the value to the next step after a few ticks", function(t)
        local calls = 0
        t:waitUntil(function()
            calls = calls + 1
            if calls >= 3 then return "ready" end
            return false
        end, 10000, function(t2, v)
            t2:eq("ready", v)
            t2:eq(3, calls)
        end, "condition never true")
    end)

    s.test("steps chain: waitUntil then sleep then a last step", function(t)
        local trail = { "body" }
        t:waitUntil(function() return true end, 1000, function(t2, v)
            trail[#trail + 1] = "until " .. tostring(v)
            t2:sleep(1, function(t3)
                trail[#trail + 1] = "slept"
                t3:eq({ "body", "until true", "slept" }, trail)
            end)
        end)
    end)

    s.test("a wait without continuation ends the test", function(t)
        t:waitUntil(function() return 1 end, 1000)
    end)
end)
