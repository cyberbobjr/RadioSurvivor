--[[
rst.guard - the world guard of RST.lua seen from a real game (E01-T06): the save name read from the running world
(getWorld():getWorld()) lets world suites run on this rstest* save, and the very same plan is refused, every test
SKIP with the reason, when the save name is not a test save. The second case is played by replacing RST.saveName for
the time of one RST.plan call (restored at once, and by t:defer): no other save is loaded.
Tags "world" and "shared": solo (RST.run({ suite = "rst.guard", tags = "world" })) or server.
]]

require "RST/RST"

RST.suite("rst.guard", { tags = { "world", "shared" } }, function(s)
    s.test("this save is a test save for the real world name", function(t)
        local name = RST.saveName()
        t:ok(name ~= nil, "no save name from getWorld():getWorld()")
        t:eq("rstest", string.lower(string.sub(name, 1, 6)), "save name " .. tostring(name))
        t:eq(true, (RST.worldGuard()), "world guard on " .. tostring(name))
        t:note("save " .. name)
    end)

    s.test("a normal save refuses every world test with the reason", function(t)
        local real = RST.saveName
        t:defer(function() RST.saveName = real end, "restore RST.saveName")
        RST.saveName = function() return "Muldraugh-normal" end
        local ok, jobs = pcall(RST.plan, { suite = "rst.fixtures", tags = "world" })
        RST.saveName = real
        t:ok(ok, "RST.plan raised: " .. tostring(jobs))
        t:ok(#jobs > 0, "rst.fixtures not selected")
        for _, job in ipairs(jobs) do
            t:ok(type(job.refused) == "string" and string.find(job.refused, "not a test save", 1, true) ~= nil,
                "job " .. tostring(job.test and job.test.name) .. " not refused: " .. tostring(job.refused))
        end
        local report = RST.newReport()
        RST.runJob(jobs[1], report, t.ctx)
        t:eq("SKIP", report.results[1].status, "status of a refused world test")
        t:note(#jobs .. " world tests refused: " .. tostring(report.results[1].message))
    end)
end)
