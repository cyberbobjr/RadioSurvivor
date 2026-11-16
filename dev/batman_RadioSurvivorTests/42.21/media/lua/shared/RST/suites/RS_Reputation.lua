--[[
rs.reputation - reputation read by RadioSurvivor in game (E04-T11, E04-T14; server/CoreAI/CA_Reputation.lua, design
docs/annexes/conception/reputation-interne.md). Tags "server" and "world": the authority only (solo, or RST.server from an
admin client), save rstest* in debug mode (the test baseline CA_Reputation.testSetLevel refuses anything else).
Solo campaign solo-rs and MP campaign mp. E21-T11: the reputation of the core mod is ca.reputation (CA_Reputation.lua
of batman_CoreAITests, persistence base of mp-persist), the killed requester lk.reputation (RST_LKReputation.lua of
batman_LivingKnoxTests).

    smuggler margin      RS_Trade.marginRange of a fresh book: good 0.10, neutral 0.25, bad 0.40 (Q13)
The test restores the reputation entry of the character it touched (RST_ReputationHelpers.lua of batman_CoreAITests).
Outside the game: tests/test_rs_trade.py (doubles).
]]

require "RST/RST"
require "RST/RST_ModRadioSurvivor"
require "RST/RST_ReputationHelpers"

local RP = RST.ReputationSuite

RST.suite("rs.reputation", { tags = { "server", "world" }, testTimeoutMs = 90000, timeoutMs = 400000 }, function(s)
    s.test("the smuggler margin follows the level (E04-T11)", function(t)
        local c = RP.setup(t)
        RP.guard(t, c, c.cid)
        local Trade = require "RadioSurvivor/RS_Trade"
        if not Trade.specOf("gus") then t:skip("voice gus has no [trade] section loaded") end  -- E20-T07: per trader
        local caller = "rst-rep-caller"
        for _, case in ipairs({ { "good", 0.10 }, { "neutral", 0.25 }, { "bad", 0.40 } }) do
            RP.baseline(t, c, c.cid, case[1])
            local low = Trade.marginRange("gus", caller, c.cid)
            t:ok(math.abs(low - case[2]) < 0.001, case[1] .. ": lowest margin " .. tostring(low) .. ", expected "
                .. case[2])
        end
    end)
end)
