--[[
Driver of the Kahlua bench (tests/test_kahlua.py, KRun.java). Loaded first: game-like globals, require on the files
loaded by KRun (LOADED[name]), a simulated clock injected through RST.clock, and the functions called by KRun:
    START(filter)   RST.start(filter, { attach = false }) ; onDone stores the report in DONE
    TICK()          one game tick: RST.step(), then the clock moves on by TICK_MS; returns true while the run goes on
    RESULT(label)   text block: "KR-BEGIN label", "KR-DONE yes|no", one "KR-STATUS status<TAB>suite<TAB>test<TAB>
                    message" line per result, the report lines, "KR-END label"
Only ASCII here (Kahlua lexer, base kahlua-lua.md).
]]

require = function(name)
    local v = LOADED[name]
    if v == nil then error("module not loaded by KRun: " .. tostring(name), 2) end
    return v
end

CLOCK = 1000000
TICK_MS = 100
getTimestampMs = function() return CLOCK end
isServer = function() return false end
isClient = function() return false end

function START(filter)
    DONE = nil
    RST.clock = function() return CLOCK end
    local ok, why = RST.start(filter, { attach = false, ctx = { side = "kahlua" },
        onDone = function(report) DONE = report end })
    if not ok then return "KR-START-REFUSED " .. tostring(why) end
    return "KR-STARTED " .. tostring(filter)
end

function TICK()
    local going = RST.step()
    CLOCK = CLOCK + TICK_MS
    return going
end

function RESULT(label)
    local out = { "KR-BEGIN " .. label }
    out[#out + 1] = "KR-DONE " .. (DONE and "yes" or "no")
    local report = DONE or (RST._run and RST._run.report)
    if report then
        for _, r in ipairs(report.results) do
            out[#out + 1] = "KR-STATUS " .. r.status .. "\t" .. r.suite .. "\t" .. r.test .. "\t"
                .. string.gsub(tostring(r.message or ""), "[\r\n\t]", " ")
        end
        if DONE then
            for _, line in ipairs(RST.formatReport(DONE)) do out[#out + 1] = line end
        end
    end
    out[#out + 1] = "KR-END " .. label
    return table.concat(out, "\n")
end
