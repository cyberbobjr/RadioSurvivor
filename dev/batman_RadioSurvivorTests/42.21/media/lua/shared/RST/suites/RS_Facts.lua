--[[
rs.facts - server fact log of the day (E14-T01, server/RadioSurvivor/RS_Facts.lua): closed list of kinds and fields,
bounds, places rounded to the town (never a coordinate), reading and purge for the evening bulletin, the lines of the
memorial (E14-T03) and the real Java readers it polls (power grid, running water, weather).
Tag "server": RS_Facts starts with "if isClient() then return end" (authority only). Read-only for the mod state:
the logic runs on in-memory books (Facts.newBook); the live log is only read. Solo: RST.server("rs.facts");
dedicated server: RST.server("rs.facts") from an admin client, or the autorun. Outside the game: tests/test_facts.py.

rs.bulletin - evening bulletin (E14-T02): radio API of the server, hour of the bulletin, then a forced bulletin
(the hour of the option is not awaited): request to the bridge, bridge text or fallback after its delay, aired on the
frequency of the chronicler, day marked as aired, facts read purged. Tags "world" and "server": it airs a real
bulletin and purges the live fact log of a test save (rstest*). Solo: RST.server("rs.bulletin"), tuned on the
frequency of the Night Owl to hear it. Outside the game: tests/test_bulletin.py.
]]

require "RST/RST"

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_Facts is not loaded on an MP client (authority only)")
    end
    local F = require "RadioSurvivor/RS_Facts"
    if type(F) ~= "table" then t:skip("RS_Facts did not return its table here") end
    return F
end

-- No field x, y or z; numbers only in n, day, hour; no string with three digits in a row.
local function coordinateFree(value, key)
    if type(value) == "table" then
        for k, v in pairs(value) do
            if k == "x" or k == "y" or k == "z" then return false, "field " .. tostring(k) end
            local ok, why = coordinateFree(v, k)
            if not ok then return false, why end
        end
    elseif type(value) == "number" then
        if key ~= "n" and key ~= "day" and key ~= "hour" then return false, "number in " .. tostring(key) end
    elseif type(value) == "string" and string.find(value, "%d%d%d") then
        return false, "digits in " .. tostring(key)
    end
    return true
end

RST.suite("rs.facts", { tags = { "server" } }, function(s)
    s.test("module exports", function(t)
        local F = module(t)
        for _, name in ipairs({ "record", "list", "purge", "expire", "place", "placeText", "add", "read", "drop",
            "expireBook", "newBook", "validate", "waterOn", "chain" }) do
            t:eq("function", type(F[name]), "RS_Facts." .. name)
        end
    end)

    s.test("closed list, bounds and no coordinate on a book", function(t)
        local F = module(t)
        local book = F.newBook()
        t:eq(nil, (F.add(book, "rumour", {}, 3, 12)), "unknown kind accepted")
        local _, why = F.add(book, "death", { name = "Ann", x = 10754 }, 3, 12)
        t:eq("field x", why)
        _, why = F.add(book, "death", { name = "Ann 10754,9926" }, 3, 12)
        t:eq("missing name", why, "a name with a coordinate kept")
        local n = F.add(book, "death", { name = "Ann Lee", place = { key = "TownIn", town = "Muldraugh" } }, 3, 12, "k")
        t:eq(1, n)
        _, why = F.add(book, "death", { name = "Ann Lee" }, 3, 12, "k")
        t:eq("duplicate", why)
        for _ = 1, F.CAPS.weather do F.add(book, "weather", { weather = "storm" }, 3, 13) end
        _, why = F.add(book, "weather", { weather = "storm" }, 3, 14)
        t:eq("cap", why)
        for _, f in ipairs(F.read(book, 0)) do
            local ok, what = coordinateFree(f)
            t:ok(ok, what)
        end
    end)

    s.test("read, purge after the bulletin, expiry without bulletin", function(t)
        local F = module(t)
        local book = F.newBook()
        F.add(book, "death", { name = "Ann Lee" }, 3, 20)
        F.add(book, "power_cut", {}, 3, 21)
        local read = F.read(book, 0)
        t:eq(2, #read)
        t:eq(2, F.drop(book, read[#read].n))
        F.add(book, "passage", { event = "crossing" }, 3, 22)
        t:eq(1, #F.read(book, 0))
        t:eq(0, F.expireBook(book, 4), "a fact of yesterday dropped")
        t:eq(1, F.expireBook(book, 5))
        t:eq(0, #F.read(book, 0))
    end)

    s.test("memorial: each death read once, no name given to the bridge (E14-T03)", function(t)
        local F = module(t)
        local book = F.newBook()
        F.add(book, "death", { name = "Ann Lee" }, 3, 20, "a")
        F.add(book, "death", { name = "Ann Lee" }, 3, 20, "a")
        F.add(book, "weather", { weather = "storm" }, 3, 20)
        F.add(book, "death", { name = "Bo Kim" }, 3, 21, "b")
        local lines = F.memorialLines(F.read(book, 0))
        t:eq("Ann Lee, Bo Kim.", lines[#lines], "names once, in order")
        t:ok(#lines == 2 and getTextOrNull("IGUI_RS_Bulletin_Memorial") ~= nil, "translated opening line")
        local text = F.deathsText(2)
        t:ok(string.find(text, "Ann", 1, true) == nil, "no name in the sentence for the bridge")
        t:eq(0, #F.memorialLines({}), "no memorial without death")
        t:note(lines[1])
    end)

    s.test("place rounded to the town", function(t)
        local F = module(t)
        local place = F.place(10754, 9926)
        if place == nil then
            t:note("no place: the vanilla map is not loaded (getLotDirectories)")
            return
        end
        t:eq({ key = "TownIn", town = "Muldraugh" }, place)
        t:eq("in Muldraugh", F.placeText(place))
        t:eq({ key = "TownFar" }, F.place(5, 5))
    end)

    s.test("real readers of the world", function(t)
        local F = module(t)
        local Triggers = require "RadioSurvivor/RS_ObservationTriggers"
        t:eq("boolean", type(Triggers.gridPower()), "doesPowerGridExist")
        t:eq("boolean", type(F.waterOn()), "getWaterShutModifier / getWorldAgeDaysSinceBegin")
        local day, hour = F.now()
        t:ok(type(day) == "number" and day >= 1, "game day")
        t:ok(type(hour) == "number" and hour >= 0 and hour <= 23, "hour of the day")
        t:note("grid " .. tostring(Triggers.gridPower()) .. ", water " .. tostring(F.waterOn())
            .. ", weather " .. tostring(Triggers.weatherNow()) .. ", day " .. tostring(day) .. ", hour " .. tostring(hour))
    end)

    s.test("live log: chained listener and no coordinate", function(t)
        local F = module(t)
        local M = require "RadioSurvivor/RS_Missions"
        local Triggers = require "RadioSurvivor/RS_ObservationTriggers"
        F.chain()
        t:eq("function", type(M.onFinished))
        t:ne(Triggers.missionFinished, M.onFinished, "facts listener not chained")
        local live = F.list()
        t:note(#live.facts .. " fact(s) in the live log, next " .. tostring(live.next))
        for _, f in ipairs(live.facts) do
            local ok, what = coordinateFree(f)
            t:ok(ok, what)
            t:note("#" .. f.n .. " " .. f.kind .. " day " .. f.day .. " " .. F.placeText(f.place))
        end
    end)
end)

RST.suite("rs.bulletin", { tags = { "world", "server" }, testTimeoutMs = 120000 }, function(s)
    s.test("radio API, hour of the bulletin and chronicler on the air", function(t)
        local F = module(t)
        t:eq("table", type(RS_RadioServer), "RS_RadioServer (RadioSurvivor_Server.lua)")
        for _, name in ipairs({ "frequency", "submit", "air", "date", "language" }) do
            t:eq("function", type(RS_RadioServer[name]), "RS_RadioServer." .. name)
        end
        local hour = F.chronicleHour()
        t:ok(hour >= 0 and hour <= 23 and hour == math.floor(hour), "ChronicleHour " .. tostring(hour))
        local khz = RS_RadioServer.frequency(F.CHRONICLER)
        t:ok(type(khz) == "number", "chronicler " .. F.CHRONICLER .. " active with a frequency")
        t:note("bulletin at " .. hour .. ":00 on " .. tostring(khz and khz / 1000) .. " MHz, last aired day "
            .. tostring(F.book() and F.book().aired))
    end)

    s.test("forced bulletin aired on the chronicler frequency, facts read purged", function(t)
        local F = module(t)
        if F.flight then t:skip("a bulletin is already waiting for the bridge") end
        local day = F.now()
        local before = F.list()
        local through = before.next - 1
        local ok, why = F.bulletin(true)
        t:ok(ok, "bulletin started: " .. tostring(why))
        t:note(#before.facts .. " fact(s) read; aired by the bridge, or by the fallback after "
            .. F.BULLETIN_TIMEOUT_MS / 1000 .. " s")
        t:waitUntil(function() return F.flight == nil end, F.BULLETIN_TIMEOUT_MS + 30000, function(t2)
            t2:eq(day, F.book().aired, "day marked as aired")
            for _, f in ipairs(F.list().facts) do
                t2:ok(f.n > through, "fact #" .. f.n .. " read but not purged")
            end
        end, "bulletin aired")
    end)
end)
