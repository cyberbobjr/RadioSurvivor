--[[
lk.fitness - "wounded" and "afraid" thresholds of Living Knox members read from the sandbox options (LK05-T16,
shared/LivingKnox/LK_Config.lua Config.FITNESS, server/LivingKnox/LK_Decisions.lua Decisions.woundRatio, fearHigh,
unfitOf). Checked here on the authority: the values read by the engine are those of the REAL options
LivingKnox.WoundedHealth (percent of the health at birth) and LivingKnox.AfraidFear (fear 0..100) returned by
getSandboxOptions():getOptionByName; a member just under the wounded threshold, or at the afraid threshold, is unfit
(no fight); then each option is changed in memory (option:setValue, as an admin would in game) and the very next call
uses the new value, without any event. Cleanup (t:defer): both options set back to their value before the test.
Tag "server": the authority only. Solo: RST.run({ suite = "lk.fitness" }). Prints "[LKF] measure ..." lines.
Outside the game: tests/test_lk_fitness.py (decisions of the cascade, expeditions, invalid values).
]]

require "RST/RST"

local function LK() return LivingKnox end

local function measure(msg) print("[LKF] measure " .. msg) end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Decisions is not loaded on an MP client (authority only)")
    end
    local E = LK()
    if E == nil or type(E.Decisions) ~= "table" or type(E.Decisions.woundRatio) ~= "function"
        or type(E.Config) ~= "table" or type(E.Config.FITNESS) ~= "table" then
        t:skip("LivingKnox.Decisions with the LK05-T16 thresholds is not loaded here")
    end
    return E
end

local function option(t, name)
    local options = getSandboxOptions and getSandboxOptions()
    local o = options and options:getOptionByName("LivingKnox." .. name)
    if o == nil then t:skip("option LivingKnox." .. name .. " missing (sandbox-options.txt not loaded)") end
    return o
end

RST.suite("lk.fitness", { tags = { "server" }, testTimeoutMs = 30000 }, function(s)
    s.test("wounded and afraid thresholds follow the sandbox options at the next call", function(t)
        local E = module(t)
        local D = E.Decisions
        local ow, of = option(t, "WoundedHealth"), option(t, "AfraidFear")
        local w0, f0 = ow:getValue(), of:getValue()
        t:defer(function()
            ow:setValue(w0)
            of:setValue(f0)
        end)
        measure(string.format("thresholds: WoundedHealth %s -> ratio %s, AfraidFear %s -> fear %s", tostring(w0),
            tostring(D.woundRatio()), tostring(f0), tostring(D.fearHigh())))
        t:eq(w0 / 100, D.woundRatio(), "wound ratio read from LivingKnox.WoundedHealth")
        t:eq(f0, D.fearHigh(), "afraid threshold read from LivingKnox.AfraidFear")
        t:ok(D.unfitOf({ health = (w0 - 1) / 100 }) ~= nil, "member just under the wounded threshold is fit")
        t:eq(nil, D.unfitOf({ health = w0 / 100 }), "member at the wounded threshold is unfit")
        t:ok(D.unfitOf({ needs = { fear = f0 } }) ~= nil, "member at the afraid threshold is fit")
        t:eq(nil, D.unfitOf({ needs = { fear = f0 - 1 } }), "member under the afraid threshold is unfit")
        -- Change in memory, as an admin would during the game: read again at the next call.
        local w1 = w0 == 50 and 30 or 50
        local f1 = f0 == 70 and 90 or 70
        ow:setValue(w1)
        of:setValue(f1)
        measure(string.format("changed: WoundedHealth %d -> ratio %s, AfraidFear %d -> fear %s", w1,
            tostring(D.woundRatio()), f1, tostring(D.fearHigh())))
        t:eq(w1 / 100, D.woundRatio(), "wound ratio after the change")
        t:eq(f1, D.fearHigh(), "afraid threshold after the change")
        local h = (math.min(w0, w1) + math.max(w0, w1)) / 200   -- health between both thresholds
        t:eq(w1 > w0, D.unfitOf({ health = h }) ~= nil, "decision on the health between both thresholds")
        local fear = math.min(f0, f1)                          -- fear at the lower of both thresholds
        t:eq(f1 <= f0, D.unfitOf({ needs = { fear = fear } }) ~= nil, "decision on the fear between both thresholds")
    end)
end)
