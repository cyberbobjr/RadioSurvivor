--[[
rst.failures — deliberate failures, to prove that a failing test never freezes the RST engine: assertion FAIL,
error() and a Java exception, in the test body, in a deferred step, in a waitUntil condition and in a cleanup.
Tags "shared" and "selfcheck": opt-in (RST.lua, "Opt-in suites"), only run when named exactly
(RST.run("rst.failures"), RST.server("rst.failures"), autorun line "rst.failures") or with tags = "selfcheck";
never by "rst", nil or the autorun default. The report is FAILED on purpose: each test name gives the expected
status; the last test must PASS (the engine went on). Checked by tests/test_kahlua.py and tests/test_rst.py.

Java exceptions, when the class ArrayList is exposed (game, Kahlua bench; outside, under lupa, these tests are SKIP):
    raised to Lua   list:get("x"): the Kahlua invoker finds no overload and raises a RuntimeException ("expected
                    argument of type int, got String"), caught by the pcall of the step: ERROR.
    logged          list:get(5): IndexOutOfBoundsException inside the Java method, caught and logged by the game
                    (MethodCaller.logException, Build 42.21): the call returns nothing and the step goes on (no Lua
                    error); the test then fails on purpose to show it went on.
]]

require "RST/RST"

local function javaAvailable()
    return ArrayList ~= nil and ArrayList.new ~= nil
end

-- Java exception raised to Lua by the Kahlua invoker (no overload for a string argument).
local function javaThrow(t)
    if not javaAvailable() then t:skip("ArrayList is not exposed here (no Java)") end
    local list = ArrayList.new()
    return list:get("x")
end

RST.suite("rst.failures", { tags = { "shared", RST.EXPLICIT_TAG } }, function(s)
    s.test("FAIL expected: assertion in the body", function(t)
        t:eq(1, 2, "deliberate")
    end)

    s.test("ERROR expected: error() in the body", function()
        error("deliberate error in the body", 0)
    end)

    s.test("ERROR expected: Java exception in the body", function(t)
        javaThrow(t)
    end)

    s.test("FAIL expected: Java exception logged by the game, the step goes on", function(t)
        if not javaAvailable() then t:skip("ArrayList is not exposed here (no Java)") end
        local v = ArrayList.new():get(5)
        t:ok(false, "deliberate: step went on after the logged Java exception (get returned " .. tostring(v) .. ")")
    end)

    s.test("FAIL expected: assertion in a deferred step", function(t)
        t:sleep(1, function(t2) t2:eq(1, 2, "deliberate") end)
    end)

    s.test("ERROR expected: error() in a deferred step", function(t)
        t:sleep(1, function() error("deliberate error in a deferred step", 0) end)
    end)

    s.test("ERROR expected: Java exception in a deferred step", function(t)
        if not javaAvailable() then t:skip("ArrayList is not exposed here (no Java)") end
        t:waitUntil(function() return true end, 1000, function(t2) javaThrow(t2) end)
    end)

    s.test("ERROR expected: Java exception in a waitUntil condition", function(t)
        if not javaAvailable() then t:skip("ArrayList is not exposed here (no Java)") end
        t:waitUntil(function() return javaThrow(t) end, 1000)
    end)

    s.test("ERROR expected: error() in a waitUntil condition", function(t)
        t:waitUntil(function() error("deliberate error in a condition", 0) end, 1000)
    end)

    s.test("FAIL expected: waitUntil timeout", function(t)
        t:waitUntil(function() return false end, 200, "deliberate")
    end)

    s.test("ERROR expected: assertion after a wait in the same step", function(t)
        t:sleep(1, function(t2) t2:ok(true) end)
        t:ok(true)
    end)

    s.test("ERROR expected: error() in a cleanup that waits", function(t)
        t:defer(function(tt)
            tt:sleep(1, function() error("deliberate error in a cleanup step", 0) end)
        end, "waiting cleanup")
        t:ok(true)
    end)

    s.test("PASS expected: the engine still runs after the failures", function(t)
        t:sleep(1, function(t2)
            t2:waitUntil(function() return true end, 1000, function(t3) t3:ok(true) end)
        end)
    end)
end)
