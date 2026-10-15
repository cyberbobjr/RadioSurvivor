--[[
rs.lifelog - life log of a notebook character (E15-T01, server/RadioSurvivor/RS_LifeLog.lua): the real Java readers
it polls on the server copy of the player (zombies killed, hours survived, profession), the town rule, and the live
logs (one per bound identity, none without one, bounded, no frequency nor coordinate).
Tag "server": RS_LifeLog starts with "if isClient() then return end" (authority only). The suite runs one poll of the
module (what the module itself does every POLL_MS); it changes nothing else. Solo: RST.server("rs.lifelog");
dedicated server: RST.server("rs.lifelog") from an admin client (the target player is the admin), or the autorun (no
player: player checks are SKIP). Outside the game: tests/test_lifelog.py.
]]

require "RST/RST"

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("RS_LifeLog is not loaded on an MP client (authority only)")
    end
    local L = require "RadioSurvivor/RS_LifeLog"
    if type(L) ~= "table" then t:skip("RS_LifeLog did not return its table here") end
    return L
end

local function state(t)
    local S = require "RadioSurvivor/RS_State"
    if type(S) ~= "table" or not S.data or S.blocked then t:skip("private state of the notebook not ready") end
    return S
end

local function player(t)
    local p = t.ctx and t.ctx.player or nil
    if not p then t:skip("no target player") end
    return p
end

local function boundId(p)
    local server = RS_CarnetServer
    return server and server.bound and server.bound[p] or nil
end

-- No field khz, x, y or z anywhere in a log.
local function clean(value)
    if type(value) ~= "table" then return true end
    for k, v in pairs(value) do
        if k == "khz" or k == "x" or k == "y" or k == "z" then return false, "field " .. tostring(k) end
        local ok, why = clean(v)
        if not ok then return false, why end
    end
    return true
end

RST.suite("rs.lifelog", { tags = { "server" } }, function(s)
    s.test("module exports", function(t)
        local L = module(t)
        for _, name in ipairs({ "poll", "tick", "characterDeath", "rescue", "get", "frozen", "release", "townAt" }) do
            t:eq("function", type(L[name]), "RS_LifeLog." .. name)
        end
    end)

    s.test("Java readers of the server player", function(t)
        module(t)
        local p = player(t)
        t:eq("number", type(p:getZombieKills()), "getZombieKills")
        t:eq("number", type(p:getHoursSurvived()), "getHoursSurvived")
        local prof = p:getDescriptor():getCharacterProfession()
        t:ok(prof ~= nil, "getCharacterProfession is nil")
        t:ok(type(prof:getName()) == "string" and prof:getName() ~= "", "profession name empty")
        t:note("kills " .. tostring(p:getZombieKills()) .. ", hours " .. tostring(p:getHoursSurvived())
            .. ", profession " .. tostring(prof:getName()) .. ", at " .. math.floor(p:getX()) .. ","
            .. math.floor(p:getY()) .. " town " .. tostring(require("RadioSurvivor/RS_LifeLog").townAt(p:getX(), p:getY())))
    end)

    s.test("town rule on the vanilla map", function(t)
        local L = module(t)
        local ok, dirs = pcall(getLotDirectories)
        local vanilla = false
        if ok and dirs then
            for i = 0, dirs:size() - 1 do
                if dirs:get(i) == "Muldraugh, KY" then vanilla = true end
            end
        end
        if not vanilla then
            t:eq(nil, L.townAt(10754, 9926), "a town found without the vanilla map")
            t:skip("vanilla map not loaded")
        end
        t:eq("Muldraugh", L.townAt(10754, 9926))
        t:eq("West Point", L.townAt(11654, 6864))
        t:eq(nil, L.townAt(10754 + 600, 9926), "outskirts counted as the town")
    end)

    s.test("target player: log of its identity after a poll", function(t)
        local L = module(t)
        local S = state(t)
        local p = player(t)
        local cid = boundId(p)
        if not cid then t:skip("target player has no notebook identity (open the notebook once)") end
        L.poll()
        local log = L.get(cid)
        t:ok(type(log) == "table", "no log for the bound identity " .. tostring(cid))
        t:eq(false, log.dead)
        t:eq(math.floor(p:getZombieKills()), log.kills, "kills")
        t:eq(p:getDescriptor():getCharacterProfession():getName(), log.profession, "profession")
        t:ok(math.abs(log.hours - p:getHoursSurvived()) < 0.2, "hours")
        local okClean, why = clean(log)
        t:ok(okClean, "log carries a frequency or a coordinate: " .. tostring(why))
        local size = #require("RadioSurvivor/RS_Codec").encodeBytes(log)
        t:ok(size <= L.MAX_BYTES, "log of " .. size .. " bytes")
        t:note(cid .. ": " .. log.kills .. " kills, " .. log.hours .. " h, " .. #log.towns .. " town(s), "
            .. #log.phrases .. " phrase(s), " .. #log.missions .. " mission(s), " .. size .. " bytes")
        t:ok(S.data.lifelogs.logs[cid] == log, "log not in the private state")
    end)

    s.test("live logs belong to usable identities, frozen logs bounded", function(t)
        local L = module(t)
        local S = state(t)
        L.poll()
        local problems, live, frozen = {}, 0, 0
        for cid, log in pairs(S.data.lifelogs and S.data.lifelogs.logs or {}) do
            local r = S.data.characters[cid]
            if log.dead then frozen = frozen + 1
            else
                live = live + 1
                if not r or r.retired then problems[#problems + 1] = cid .. " live without a usable identity" end
            end
        end
        t:ok(frozen <= L.MAX_FROZEN, frozen .. " frozen logs")
        t:eq(0, #problems, table.concat(problems, "; "))
        t:note(live .. " live log(s), " .. frozen .. " frozen log(s)")
    end)
end)
