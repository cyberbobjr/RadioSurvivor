--[[
rs.placesurvey - places recorded in game for the voice workshop (E22-T08, ADR atelier-voix D08): the world context
menu "Voice workshop: record this place" (client/RadioSurvivor/RS_PlaceSurveyMenu.lua, solo or admin) asks the
authority (server/RadioSurvivor/RS_PlaceSurvey.lua) to append the clicked square, with the containers, room and
building it reads itself, to Zomboid/Lua/batman_RadioSurvivor/workshop-places.txt (last 200 records).
Checked here:
- module exports and a refusal without an allowed player (no data, nothing written);
- the requester client (admin on a server, the local player in solo) has the option on a container square near the
  target player (a dumpster preferred: container type "bin" or a sprite named trash/dumpster), chooses it, and the
  authority's file gets the line at=x,y,z with containers= (polled: the request is not ordered with the step answer);
- a real second client with the access level "user": no option on the same square, and its forged request refused
  "denied" without data, counted by the authority, the file unchanged (MP campaign, autoclient.py --mp --clients 2;
  SKIP in solo).
The survey file is restored to its previous lines at the end (t:defer). Tag "server": the authority runs it. Solo:
RST.run({ suite = "rs.placesurvey" }). Dedicated server: RST.server({ suite = "rs.placesurvey" }) from an admin client.
Outside the game: tests/test_rs_place_survey.py (Lua doubles), tests/test_atelier_surveys.py (bridge side).
]]

require "RST/RST"
require "RST/RST_ModRadioSurvivor"
require "RST/RST_PeerChecks"
require "RST/RST_RSViewSteps"

local ASK_MS = 15000
local FILE_MS = 10000
local SEARCH = 20

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("the survey file lives on the authority (RS_PlaceSurvey is not loaded on an MP client)")
    end
    local S = RS_PlaceSurvey
    t:ok(type(S) == "table" and type(S.request) == "function", "RS_PlaceSurvey is not loaded on this side")
    return S
end

local function target(t)
    local p = RST.Fixtures and RST.Fixtures.player(t) or (t.ctx and t.ctx.player)
    if p == nil then t:skip("no target player (t.ctx.player)") end
    return p
end

local function lines(S)
    local out = {}
    local reader = getFileReader(S.FILE, false)
    if reader == nil then return out end
    local line = reader:readLine()
    while line ~= nil do
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then out[#out + 1] = line end
        line = reader:readLine()
    end
    reader:close()
    return out
end

-- Previous lines of the survey file written back after the test (header kept).
local function keepFile(t, S)
    local before = lines(S)
    t:defer(function()
        local writer = getFileWriter(S.FILE, true, false)
        if writer == nil then return end
        writer:write(S.HEADER .. "\n")
        for _, line in ipairs(before) do writer:write(line .. "\n") end
        writer:close()
    end, "survey file restored")
    return before
end

-- Score of a container square: 2 for a dumpster (type bin, sprite trash or dumpster), 1 for any container.
local function score(sq)
    local best = 0
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        for k = 0, o:getContainerCount() - 1 do
            local c = o:getContainerByIndex(k)
            local sprite = o:getSprite() and o:getSprite():getName() or ""
            local kind = c and c:getType() or ""
            local s = (kind == "bin" or string.find(sprite, "trash", 1, true) or string.find(sprite, "dumpster", 1, true))
                and 2 or 1
            if s > best then best = s end
        end
    end
    return best
end

-- A container square near the player (a dumpster first): { x, y, z, dumpster } or nil.
local function containerSquare(player)
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local cell = getCell()
    local found = nil
    for r = 0, SEARCH do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local sq = cell:getGridSquare(px + dx, py + dy, pz)
                    local s = sq and score(sq) or 0
                    if s == 2 then return { x = px + dx, y = py + dy, z = pz, dumpster = true } end
                    if s == 1 and found == nil then found = { x = px + dx, y = py + dy, z = pz, dumpster = false } end
                end
            end
        end
    end
    return found
end

local function lineOf(S, at)
    local key = "\tat=" .. at.x .. "," .. at.y .. "," .. at.z
    local all = lines(S)
    for i = #all, 1, -1 do
        if string.find(all[i], key, 1, true) ~= nil then return all[i], #all end
    end
    return nil, #all
end

RST.suite("rs.placesurvey", { tags = { "server" } }, function(s)
    s.test("module exports", function(t)
        local S = module(t)
        for _, name in ipairs({ "isAllowed", "request", "describe", "format", "append", "onClientCommand" }) do
            t:eq("function", type(S[name]), "RS_PlaceSurvey." .. name)
        end
        t:eq("RadioSurvivorSurvey", S.MODULE, "command module")
        t:eq("batman_RadioSurvivor/workshop-places.txt", S.FILE, "survey file")
        t:eq(200, S.MAX_RECORDS, "records kept")
    end)

    s.test("a request without an allowed player is refused without data", function(t)
        local S = module(t)
        local before = #lines(S)
        local r = S.request(nil, { op = S.OP, n = 5, x = 1, y = 1, z = 0 })
        t:eq(false, r.ok, "request accepted")
        t:eq("denied", r.err, "error")
        for k in pairs(r) do
            t:ok(k == "n" or k == "op" or k == "ok" or k == "err", "refusal carries the field " .. k)
        end
        t:eq(before, #lines(S), "records written by a refused request")
    end)

    s.test("the admin's menu records a container square in the file", function(t)
        local S = module(t)
        local player = target(t)
        local at = containerSquare(player)
        if at == nil then t:skip("no container within " .. SEARCH .. " squares of the target player") end
        t:note("square " .. at.x .. "," .. at.y .. "," .. at.z .. (at.dumpster and " (dumpster)" or " (container)"))
        keepFile(t, S)
        RST.Steps.ask(t, "survey.menu", { x = at.x, y = at.y, z = at.z, choose = true },
            { target = "requester", timeoutMs = ASK_MS, none = "skip" }, function(t2, res)
                local answer = res.list[1] or {}
                t2:eq(1, answer.data and answer.data.options, "survey options shown to the requester")
                t2:waitUntil(function() return lineOf(S, at) ~= nil end, FILE_MS, function(t3)
                    local line = lineOf(S, at)
                    t3:ok(string.find(line, "\tcontainers=", 1, true) ~= nil, "no containers in " .. line)
                    t3:ok(string.find(line, "^time=%d%d%d%d%-") ~= nil, "no real time in " .. line)
                    t3:ok(string.find(line, "\tby=", 1, true) ~= nil, "no recorder in " .. line)
                    t3:note(line)
                end, "line at=" .. at.x .. "," .. at.y .. "," .. at.z .. " in " .. S.FILE)
            end)
    end)

    -- E01-T16 pattern: a real second client with the access level "user".
    s.test("a user client has no option and its forged request is refused", function(t)
        local S = module(t)
        local player = target(t)
        local at = containerSquare(player) or { x = math.floor(player:getX()), y = math.floor(player:getY()),
            z = math.floor(player:getZ()) }
        keepFile(t, S)
        RST.PeerChecks.asUser(t, function(t2, user)
            RST.Steps.ask(t2, "survey.menu", { x = at.x, y = at.y, z = at.z, choose = true },
                { target = { user }, timeoutMs = ASK_MS }, function(t3, res)
                    local answer = res.by[user] or {}
                    if answer.status ~= "SKIP" then
                        t3:eq(0, answer.data and answer.data.options, "survey options shown to " .. user)
                    end
                    local before, refused = #lines(S), S.stats.refused or 0
                    RST.PeerChecks.requestsRefused(t3, user, { { label = "survey", spec = { module = S.MODULE,
                        command = S.CMD_REQUEST, args = { op = S.OP, n = 740, x = at.x, y = at.y, z = at.z } } } },
                        function(t4)
                            t4:eq(refused + 1, S.stats.refused, "refusal counted by the authority")
                            t4:eq(before, #lines(S), "records written for a user client")
                        end)
                end)
        end)
    end)
end)
