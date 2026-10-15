--[[
rs.trade_run - weekly run of the smuggler (E13-T03, server/RadioSurvivor/RS_Trade.lua and RS_TradeRun.lua): hooks
installed on the authority, meeting window at night inside the week of the run, one booking per run (a second team
is refused "booked"), cancellation announced on the frequency of the voice with a translated text (no key).
Tags "world" and "server" (E01-T19: the server suites of RST.server and of the campaign mp take only "server" and
"shared" suites): the authority only (solo or dedicated server), on a save named rstest*. Solo:
RST.run({ suite = "rs.trade_run", tags = "world" }); dedicated server, from an admin client:
RST.server({ suite = "rs.trade_run", tags = "world" }). On a server the announcement is translated by the server
(the check "untranslated key" covers the raw keys of a server without the mod translations).

Changes to the world: none kept. The trade state of the save (S.data.trade) is copied before each test that books
or cancels and put back after it; the announcement is captured (RS_RadioServer.air wrapped), never aired.
]]

require "RST/RST"

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

-- Runs body with an empty run in this passage, then puts the trade state of the save back.
local function withFreshRun(t, Trade, S, body)
    if not S.data or S.blocked then t:skip("private state not loaded") end
    if Trade.rendezvous(Trade.worldHours(), Trade.passage()) == nil then
        t:skip("too late in the week of this run for a night crossing: try again next game week")
    end
    Trade.stock()
    local saved = deepCopy(S.data.trade)
    S.data.trade.run = nil
    local ok, err = pcall(body)
    S.data.trade = saved
    S.dirty = true
    if not ok then error(err, 0) end
end

RST.suite("rs.trade_run", { tags = { "world", "server" } }, function(s)
    s.test("hooks installed on the authority", function(t)
        local Trade, Run = authority(t)
        t:ok(Trade.onBooked == Run.onBooked, "Trade.onBooked is not RS_TradeRun.onBooked")
        t:eq(6041, Trade.PIER.x, "pier x")
        t:eq(5217, Trade.PIER.y, "pier y")
        t:ok(Run.library() ~= nil, "required mod Signal Smoke (batman_SignalSmoke) unusable: red flare not listened to")
    end)

    s.test("meeting window at night inside the week", function(t)
        local Trade = authority(t)
        local now = Trade.worldHours()
        local start = Trade.rendezvous(now, Trade.passage())
        if start == nil then t:skip("too late in the week of this run") end
        t:eq(1, (start + 7) % 24, "window start hour")
        t:ok(start >= now + Trade.LEAD_HOURS - 1e-6, "window too close: " .. tostring(start - now) .. " h")
        t:ok(start + Trade.WINDOW_HOURS <= Trade.passageEnd(Trade.passage()), "window after the week")
        t:note("run " .. Trade.passage() .. ": window in " .. string.format("%.1f", start - now) .. " game hours, cordon "
            .. tostring(Trade.cordon()))
    end)

    s.test("one booking per run", function(t)
        local Trade, _, S = authority(t)
        withFreshRun(t, Trade, S, function()
            local offer, why, booked = Trade.propose("rst-a", nil, "OutsideNews:1", nil, "rst-team-a",
                { voice = "gus" })
            t:ok(offer ~= nil, "first offer refused: " .. tostring(why))
            t:ok(booked == true, "first offer did not book the run")
            local status = Trade.runStatus("rst-team-a")
            t:eq("yours", status, "status of the booking team")
            t:eq("taken", (Trade.runStatus("rst-team-b")), "status of another team")
            local other, why2 = Trade.propose("rst-b", nil, "OutsideNews:1", nil, "rst-team-b", { voice = "gus" })
            t:eq(nil, other, "second team got an offer")
            t:eq("booked", why2, "refusal of the second team")
        end)
    end)

    s.test("cancellation announced on the voice frequency", function(t)
        local Trade, Run, S = authority(t)
        local radio = RS_RadioServer
        if type(radio) ~= "table" or not radio.frequency("gus") then t:skip("voice gus is not on the air") end
        withFreshRun(t, Trade, S, function()
            local _, why, booked = Trade.propose("rst-a", nil, "OutsideNews:1", nil, "rst-team-a", { voice = "gus" })
            t:ok(booked == true, "run not booked: " .. tostring(why))
            local original, captured = radio.air, nil
            radio.air = function(khz, lines) captured = { khz = khz, lines = lines } end
            local ok, run = pcall(Run.cancel, "storm")
            radio.air = original
            t:ok(ok, "Run.cancel raised: " .. tostring(run))
            t:eq("cancelled", run and run.state, "run state")
            t:ok(captured ~= nil, "nothing announced")
            t:eq(radio.frequency("gus"), captured.khz, "announced on another frequency")
            t:eq(3, #captured.lines, "announcement lines")
            t:ok(string.find(captured.lines[2], "IGUI_", 1, true) == nil, "untranslated key: " .. captured.lines[2])
            t:note(captured.lines[2])
            t:eq("run_over", select(2, Trade.propose("rst-a", nil, "OutsideNews:1", nil, "rst-team-a")),
                "offer accepted after the cancellation")
        end)
    end)
end)
