--[[
RST_PeerChecks2 - client steps of the notebook, mission and test-engine checks of the second client (E01-T16:
E00-T01, E01-T05, E10-T04, E11-T05, E11-T06), asked by the authority through RST.Steps. Development mod only. Load
with: require "RST/RST_PeerChecks2" (shared: the suites that ask these steps require it, so every machine that loads
the suites registers the handlers; the authority helpers run on the server or in solo).

Client handlers (RST.Steps.on)
    carnet.claim   { character, waitMs }: this client sends the notebook "hello" claiming the character id given (the
                   identity of ANOTHER account, E00-T01) and returns the character of the "identity" answer of the
                   server in data { character } (RST.PeerRadio inbox; solo: the client module is tapped). FAIL when no
                   answer comes.
    rst.run        { filter, n }: this client sends the real command of RST.server (module "RST", command "run",
                   { id = n, filter }) and returns the first answer of the same id (denied, busy, refused, started,
                   report) in data { command, reason }. MP client only (SKIP elsewhere).
    rst.run.later  { filter, everyMs, maxMs }: arms this client to send the real RST.server request (as rst.run) every
                   everyMs while the server answers "busy", until it answers anything else or maxMs passed (E01-T05:
                   a run started by this client right after the run in progress, then cut by its disconnection).
                   Answers PASS "armed" at once; the attempts go on after the step (one OnTick poller, PC2.later).
    carnet.contact { id, groupName }: this client asks its notebook snapshot (RS_CarnetClient.send "snapshot", as the
                   notebook does when it opens) and waits until the contact id of RS_CarnetClient.snapshot shows that
                   group name (data { groupName, name } of the last row seen; FAIL with it at the deadline).
    map.zones      { mission, rings = { { x, y, r }, ... }, expect = "present" | "absent", line = { key, arg } }:
                   waits until a notebook snapshot holding the row of mission was received here (present) or one whose
                   row is no longer active or is gone (absent), then counts the mission rings of the world map of this
                   player (RS_MapActions: symbol ZONE_ICON with the zone colour at x, y) and their labels (any text at
                   x, y - r): present = one ring and one label per ring, absent = none. line = a notebook line
                   translated HERE (getText(key, arg)) that must exist (data.line). Data: rings, labels per ring.
Authority helpers
    PC2.notebook()                   RS_CarnetServer with its state, or nil
    PC2.boundOf(player)              notebook character bound to a player on the authority, or nil
    PC2.pushRows(t, rows, after)     sends every online client (solo: the local client module) a notebook snapshot
                                     whose missions are rows (M.projection rows of a test mission), then after(t)
    PC2.restore()                    real snapshots again (RS_CarnetServer.publish), the test rows go away
    PC2.zoneRow(M, m, character, uid) -> row, rings
                                     notebook row of a test mission as projected for a participant, unique id uid
    PC2.checkZones(t, row, rings, expect, line, after)
                                     row pushed to the clients, then map.zones asked to all clients (solo: the local
                                     player); real snapshots sent again at the end of the test (one cleanup per test,
                                     kept in PC2.restoring, never a field of t). Without the notebook state: FAIL on
                                     a server (the state exists there once the server started), SKIP in solo
    PC2.unchecked(t, why)            a check that cannot be made (no second client, no notebook state): FAIL on a
                                     dedicated server where another client is online (it should have answered), SKIP
                                     (explicit, with why) in solo or when the requester is the only client
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"
require "RST/RST_PeerChecksRadio"

RST.PeerChecks2 = RST.PeerChecks2 or {}
local PC2 = RST.PeerChecks2
local Steps = RST.Steps
local PR = RST.PeerRadio

PC2.CLAIM_MS = 5000
PC2.RUN_MS = 5000
PC2.ZONES_MS = 10000
PC2.RUN_ID0 = 900000          -- request numbers of this step: far above those of RST_Client (1, 2, ...)
PC2.RST_ANSWERS = { denied = true, busy = true, refused = true, started = true, report = true }
PC2.runReplies = PC2.runReplies or {}
PC2.restoring = PC2.restoring or {}  -- authority: tests whose real snapshots are sent again at their end
PC2.runSeq = PC2.runSeq or 0

local function isClientSide() return type(isClient) == "function" and isClient() end
local function isServerSide() return type(isServer) == "function" and isServer() end

local function carnet() return RS_CarnetClient end

-- ---------------------------------------------------------------- carnet.claim

Steps.on("carnet.claim", function(args)
    local C = carnet()
    if C == nil or type(C.send) ~= "function" then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    if type(args.character) ~= "string" or args.character == "" then return Steps.fail("no character to claim") end
    PR.tapSolo()
    local mark = PR.seq
    local Config = require "RadioSurvivor/RS_Config"
    C.send("hello", { v = Config.VERSION, character = args.character })
    return function(ctx)
        local got = PR.since(mark, PR.CARNET_MODULE, { identity = true })
        if #got > 0 then
            local character = got[#got].character
            return Steps.pass("claimed " .. tostring(args.character) .. ", identity answered " .. tostring(character),
                { character = character })
        end
        if ctx.final then return Steps.fail("no identity answer to the claim of " .. tostring(args.character)) end
        return nil
    end
end)

-- ---------------------------------------------------------------- rst.run

function PC2.onRstReply(module, command, args)
    if module ~= "RST" or not PC2.RST_ANSWERS[command] or type(args) ~= "table" or args.id == nil then return end
    if PC2.runReplies[args.id] == nil then
        PC2.runReplies[args.id] = { command = command, reason = args.reason }
    end
end

Steps.on("rst.run", function(args)
    if not isClientSide() then return Steps.skip("RST.server requests travel from an MP client only") end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    if player == nil then return Steps.fail("no local player") end
    PC2.runSeq = PC2.runSeq + 1
    local id = tonumber(args.n) or (PC2.RUN_ID0 + PC2.runSeq)
    PC2.runReplies[id] = nil
    sendClientCommand(player, "RST", "run", { id = id, filter = args.filter })
    return function(ctx)
        local r = PC2.runReplies[id]
        if r ~= nil then
            PC2.runReplies[id] = nil
            return Steps.pass("RST run #" .. id .. " answered " .. tostring(r.command) .. ": " .. tostring(r.reason),
                { command = r.command, reason = r.reason, id = id })
        end
        if ctx.final then return Steps.fail("no answer of the server to the RST run #" .. id) end
        return nil
    end
end)

-- ---------------------------------------------------------------- rst.run.later

PC2.LATER_EVERY_MS = 500
PC2.LATER_MAX_MS = 180000

-- One attempt of the armed request; the next one only after the answer to this one (or 5 s without answer).
function PC2.laterTick()
    local L = PC2.later
    if L == nil or L.done then return end
    local now = RST.now()
    if now > L.stopAt then
        L.done, L.outcome = true, "gave up after " .. L.attempts .. " attempt(s)"
        print("[RST-STEP] rst.run.later: " .. L.outcome)
        return
    end
    if L.id ~= nil then
        local r = PC2.runReplies[L.id]
        if r == nil and now - L.sentAt < 5000 then return end
        PC2.runReplies[L.id] = nil
        L.id = nil
        if r ~= nil and r.command ~= "busy" then
            L.done, L.outcome = true, tostring(r.command) .. ": " .. tostring(r.reason)
            print("[RST-STEP] rst.run.later: run request answered " .. L.outcome .. " after " .. L.attempts
                .. " attempt(s)")
            return
        end
    end
    if now - L.sentAt < L.every then return end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    if player == nil then return end
    PC2.runSeq = PC2.runSeq + 1
    L.id = PC2.RUN_ID0 + PC2.runSeq
    L.sentAt = now
    L.attempts = L.attempts + 1
    sendClientCommand(player, "RST", "run", { id = L.id, filter = L.filter })
end

Steps.on("rst.run.later", function(args)
    if not isClientSide() then return Steps.skip("RST.server requests travel from an MP client only") end
    if type(args.filter) ~= "table" then return Steps.fail("no filter for the later run request") end
    PC2.later = { filter = args.filter, every = tonumber(args.everyMs) or PC2.LATER_EVERY_MS,
        stopAt = RST.now() + (tonumber(args.maxMs) or PC2.LATER_MAX_MS), sentAt = 0, attempts = 0 }
    if not PC2._laterTick and type(Events) == "table" and Events.OnTick then
        Events.OnTick.Add(function() RST.PeerChecks2.laterTick() end)
        PC2._laterTick = true
    end
    return Steps.pass("armed: run request every " .. PC2.later.every .. " ms while the server is busy")
end)

-- ---------------------------------------------------------------- carnet.contact

local function contactRow(C, id)
    for _, row in ipairs(C.snapshot and C.snapshot.contacts or {}) do
        if row.id == id then return row end
    end
    return nil
end

Steps.on("carnet.contact", function(args)
    local C = carnet()
    if C == nil or type(C.send) ~= "function" then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    if C.world == nil then return Steps.fail("the notebook of this client has no session (no identity yet)") end
    C.send("snapshot", {})
    local last = "no contact " .. tostring(args.id) .. " in the notebook here"
    return function(ctx)
        local row = contactRow(C, args.id)
        if row ~= nil then
            last = "contact " .. tostring(row.name) .. ": group '" .. tostring(row.groupName) .. "'"
            if row.groupName == args.groupName then
                return Steps.pass(last, { groupName = row.groupName, name = row.name })
            end
        end
        if ctx.final then
            return Steps.fail(last .. " (expected '" .. tostring(args.groupName) .. "')",
                { groupName = row and row.groupName or nil })
        end
        return nil
    end
end)

-- ---------------------------------------------------------------- map.zones

local function missionRow(C, id)
    for _, row in ipairs(C.snapshot and C.snapshot.missions or {}) do
        if row.id == id then return row end
    end
    return nil
end

local function mapModule()
    local ok, M = pcall(require, "RadioSurvivor/RS_MapActions")
    if ok and type(M) == "table" then return M end
    return nil
end

local function close(a, b) return math.abs(a - b) < 0.01 end

-- Rings (zone icon in the zone colour at x, y) and labels (text at x, y - r) of each wanted ring on this map.
local function countZones(MA, api, rings)
    local c, tol = MA.ZONE_COLOR, MA.ZONE_COLOR_TOLERANCE or 0.02
    local out = {}
    for i = 1, #rings do out[i] = { rings = 0, labels = 0 } end
    for i = 0, api:getSymbolCount() - 1 do
        local s = api:getSymbolByIndex(i)
        if s ~= nil and math.abs(s:getAlpha() - c.a) < tol and math.abs(s:getRed() - c.r) < tol
            and math.abs(s:getGreen() - c.g) < tol and math.abs(s:getBlue() - c.b) < tol then
            for k, z in ipairs(rings) do
                if s:isTexture() and s:getSymbolID() == MA.ZONE_ICON and close(s:getWorldX(), z.x)
                    and close(s:getWorldY(), z.y) then
                    out[k].rings = out[k].rings + 1
                elseif s:isText() and close(s:getWorldX(), z.x) and close(s:getWorldY(), z.y - z.r) then
                    out[k].labels = out[k].labels + 1
                end
            end
        end
    end
    return out
end

local function describeCounts(counts)
    local parts = {}
    for i, n in ipairs(counts) do parts[i] = n.rings .. " ring(s) " .. n.labels .. " label(s)" end
    return table.concat(parts, "; ")
end

Steps.on("map.zones", function(args)
    local C = carnet()
    if C == nil then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    local MA = mapModule()
    if MA == nil or type(MA.symbolsAPI) ~= "function" then return Steps.fail("RS_MapActions not loaded here") end
    local rings = args.rings or {}
    local present = args.expect ~= "absent"
    local lineText = nil
    if type(args.line) == "table" and args.line.key then
        lineText = getText(args.line.key, args.line.arg)
        if lineText == nil or lineText == args.line.key then
            return Steps.fail("notebook line " .. tostring(args.line.key) .. " not translated here")
        end
    end
    local last = "no notebook snapshot with mission " .. tostring(args.mission) .. " received here"
    return function(ctx)
        local row = missionRow(C, args.mission)
        local reached
        if present then
            reached = row ~= nil and row.state == "active"
        else
            reached = row == nil or row.state ~= "active"
        end
        if reached then
            local api = MA.symbolsAPI()
            if api == nil then return Steps.fail("no world map here (RS_MapActions.symbolsAPI)") end
            local counts = countZones(MA, api, rings)
            local ok = true
            for _, n in ipairs(counts) do
                if present and (n.rings ~= 1 or n.labels ~= 1) then ok = false end
                if not present and (n.rings ~= 0 or n.labels ~= 0) then ok = false end
            end
            last = (present and "mission active" or "mission closed") .. " here: " .. describeCounts(counts)
                .. (lineText and (", line '" .. lineText .. "'") or "")
            if ok then return Steps.pass(last, { counts = counts, line = lineText }) end
        end
        if ctx.final then return Steps.fail(last) end
        return nil
    end
end)

-- ---------------------------------------------------------------- authority helpers

function PC2.notebook()
    local Server = RS_CarnetServer
    if type(Server) ~= "table" or type(Server.store) ~= "table" or Server.store.data == nil then return nil end
    return Server
end

function PC2.boundOf(player)
    local Server = PC2.notebook()
    if Server == nil or player == nil then return nil end
    return Server.bound[player]
end

-- Notebook snapshot holding the test rows, sent as the notebook server sends its own (world and run of its state).
local function payload(Server, rows)
    return { world = Server.store.data.world, run = Server.store.run, contacts = {}, missions = rows, selected = "",
        events = {}, inviteTargets = {}, npcProvider = true, storage = true, at = getTimestampMs() }
end

function PC2.pushRows(t, rows, after)
    local Server = PC2.notebook()
    if Server == nil then
        t:note("notebook server state not ready: mission rows not sent to the clients")
        if after then return after(t) end
        return
    end
    local Config = require "RadioSurvivor/RS_Config"
    if isServerSide() then
        local list = getOnlinePlayers()
        for i = 0, (list and list:size() or 0) - 1 do
            sendServerCommand(list:get(i), Config.MODULE, "snapshot", payload(Server, rows))
        end
    elseif RS_CarnetClient ~= nil then
        RS_CarnetClient.receive("snapshot", payload(Server, rows))
    end
    if after then return after(t) end
end

function PC2.restore()
    local Server = PC2.notebook()
    if Server ~= nil and type(Server.publish) == "function" then pcall(Server.publish) end
end

-- Notebook row of a test mission m as the server projects it for a participant (RS_Missions.projection), under a
-- unique id uid (the client draws a zone once per session and mission id); rings = its map circles.
function PC2.zoneRow(M, m, character, uid)
    local row = M.projection(m, character)
    row.id, row.requester, row.near = uid, "RST", false
    local rings = {}
    for _, z in ipairs({ row.mapZone or false, row.depotZone or false }) do
        if type(z) == "table" then rings[#rings + 1] = { x = z.x, y = z.y, r = z.r } end
    end
    return row, rings
end

-- The row is sent to the clients in a notebook snapshot, then every client (solo: the local player) checks the
-- circles of its map (map.zones); after(t). The real snapshots come back at the end of the test (PC2.restore, once).
-- Without the notebook state: FAIL on a server, SKIP in solo.
function PC2.unchecked(t, why)
    if isServerSide() and #Steps.others(t) > 0 then
        t:ok(false, why .. " (dedicated server with a second client online)")
    end
    t:skip(why)
end

function PC2.checkZones(t, row, rings, expect, line, after)
    if PC2.notebook() == nil then
        local why = "notebook server state not ready: circles of the mission not checked on the clients"
        if isServerSide() then t:ok(false, why) end
        t:skip(why)
    end
    if not PC2.restoring[t] then
        PC2.restoring[t] = true
        t:defer(function()
            PC2.restoring[t] = nil
            PC2.restore()
        end, "real notebook snapshots sent again")
    end
    PC2.pushRows(t, { row }, function(t1)
        local target = isServerSide() and "all" or "requester"
        Steps.ask(t1, "map.zones", { mission = row.id, rings = rings, expect = expect, line = line },
            { target = target, timeoutMs = PC2.ZONES_MS }, after)
    end)
end

-- ---------------------------------------------------------------- subscription (MP clients, once)

if not PC2._subscribed and type(Events) == "table" and Events.OnServerCommand and isClientSide() then
    Events.OnServerCommand.Add(function(module, command, args) RST.PeerChecks2.onRstReply(module, command, args) end)
    PC2._subscribed = true
end

return PC2
