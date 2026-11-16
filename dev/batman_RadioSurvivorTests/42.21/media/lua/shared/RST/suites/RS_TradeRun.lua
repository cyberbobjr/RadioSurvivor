--[[
rs.trade_run - run of a trader (E13-T03; E20-T07: Gus' [trade] section, state per trader; server/RadioSurvivor/
RS_Trade.lua and RS_TradeRun.lua): hooks installed on the authority, Gus' landing read from his sheet, meeting window
of the sheet inside the period of the run, one booking per run (a second team is refused "booked"), cancellation
announced on the frequency of the voice with a translated text (no key).
Tags "world" and "server" (E01-T19: the server suites of RST.server and of the campaign mp take only "server" and
"shared" suites): the authority only (solo or dedicated server), on a save named rstest*. Solo:
RST.run({ suite = "rs.trade_run", tags = "world" }); dedicated server, from an admin client:
RST.server({ suite = "rs.trade_run", tags = "world" }). On a server the announcement is translated by the server
(the check "untranslated key" covers the raw keys of a server without the mod translations).

Changes to the world: none kept. The trade state of Gus (S.data.trade.traders.gus) is copied before each test that
books or cancels and put back after it; the announcement is captured (RS_RadioServer.air wrapped), never aired.
]]

require "RST/RST"
require "RST/RST_ModRadioSurvivor"

local VOICE = "gus"     -- the delivered trader whose run is checked

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

local function authority(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the run is kept on the authority (server files not loaded on an MP client)")
    end
    local ok, Run = pcall(require, "RadioSurvivor/RS_TradeRun")
    t:ok(ok and type(Run) == "table", "RadioSurvivor/RS_TradeRun is not loaded on this side")
    return require "RadioSurvivor/RS_Trade", Run, require "RadioSurvivor/RS_State"
end

-- Runs body with an empty run of Gus in this passage, then puts his trade state back.
local function withFreshRun(t, Trade, S, body)
    if not S.data or S.blocked then t:skip("private state not loaded") end
    if not Trade.specOf(VOICE) then t:skip("voice " .. VOICE .. " has no [trade] section loaded") end
    if Trade.rendezvous(VOICE, Trade.worldHours(), Trade.passage(VOICE)) == nil then
        t:skip("too late in the period of this run for a meeting: try again next game week")
    end
    Trade.stock(VOICE)
    local saved = deepCopy(S.data.trade.traders[VOICE])
    S.data.trade.traders[VOICE].run = nil
    local ok, err = pcall(body)
    S.data.trade.traders[VOICE] = saved
    S.dirty = true
    if not ok then error(err, 0) end
end

RST.suite("rs.trade_run", { tags = { "world", "server" } }, function(s)
    s.test("hooks installed on the authority", function(t)
        local Trade, Run = authority(t)
        t:ok(Trade.onBooked == Run.onBooked, "Trade.onBooked is not RS_TradeRun.onBooked")
        local spec = Trade.specOf(VOICE)
        t:ok(spec ~= nil, "voice " .. VOICE .. " has no [trade] section loaded")
        t:eq({ 6041, 5217, "boat" }, { spec.landings[1].x, spec.landings[1].y, spec.arrival }, "landing and mode")
        t:ok(Run.library() ~= nil, "required mod Signal Smoke (batman_SignalSmoke) unusable: red flare not listened to")
    end)

    s.test("meeting window of the sheet inside the period", function(t)
        local Trade = authority(t)
        local spec = Trade.specOf(VOICE)
        if not spec then t:skip("voice " .. VOICE .. " has no [trade] section loaded") end
        local now, passage = Trade.worldHours(), Trade.passage(VOICE)
        local start = Trade.rendezvous(VOICE, now, passage)
        if start == nil then t:skip("too late in the period of this run") end
        t:eq(spec.from, (start + 7) % 24, "window start hour")
        t:ok(start >= now + Trade.LEAD_HOURS - 1e-6, "window too close: " .. tostring(start - now) .. " h")
        t:ok(start + spec.hours <= Trade.passageEnd(VOICE, passage), "window after the period")
        t:note("run " .. passage .. ": window in " .. string.format("%.1f", start - now) .. " game hours, cordon "
            .. tostring(Trade.cordon(VOICE)))
    end)

    s.test("one booking per run", function(t)
        local Trade, _, S = authority(t)
        withFreshRun(t, Trade, S, function()
            local offer, why, booked = Trade.propose(VOICE, "rst-a", nil, "OutsideNews:1", "MoneyBundle:1", "rst-team-a", {})
            t:ok(offer ~= nil, "first offer refused: " .. tostring(why))
            t:ok(booked == true, "first offer did not book the run")
            local status = Trade.runStatus(VOICE, "rst-team-a")
            t:eq("yours", status, "status of the booking team")
            t:eq("taken", (Trade.runStatus(VOICE, "rst-team-b")), "status of another team")
            local other, why2 = Trade.propose(VOICE, "rst-b", nil, "OutsideNews:1", "MoneyBundle:1", "rst-team-b", {})
            t:eq(nil, other, "second team got an offer")
            t:eq("booked", why2, "refusal of the second team")
        end)
    end)

    s.test("cancellation announced on the voice frequency", function(t)
        local Trade, Run, S = authority(t)
        local radio = RS_RadioServer
        if type(radio) ~= "table" or not radio.frequency(VOICE) then t:skip("voice " .. VOICE .. " is not on the air") end
        withFreshRun(t, Trade, S, function()
            local _, why, booked = Trade.propose(VOICE, "rst-a", nil, "OutsideNews:1", "MoneyBundle:1", "rst-team-a", {})
            t:ok(booked == true, "run not booked: " .. tostring(why))
            local original, captured = radio.air, nil
            radio.air = function(khz, lines) captured = { khz = khz, lines = lines } end
            local ok, run = pcall(Run.cancel, VOICE, "storm")
            radio.air = original
            t:ok(ok, "Run.cancel raised: " .. tostring(run))
            t:eq("cancelled", run and run.state, "run state")
            t:ok(captured ~= nil, "nothing announced")
            t:eq(radio.frequency(VOICE), captured.khz, "announced on another frequency")
            t:eq(3, #captured.lines, "announcement lines")
            t:ok(string.find(captured.lines[2], "IGUI_", 1, true) == nil, "untranslated key: " .. captured.lines[2])
            t:note(captured.lines[2])
            t:eq("run_over", select(2, Trade.propose(VOICE, "rst-a", nil, "OutsideNews:1", "MoneyBundle:1", "rst-team-a")),
                "offer accepted after the cancellation")
        end)
    end)
end)
