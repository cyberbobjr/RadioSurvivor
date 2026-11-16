--[[
RST_PeerChecksSignal - client steps of the suite ca.mission.signal.client (E11-T07, CA_MissionSignalSuite.lua),
asked by the authority through RST.Steps (E01-T16; E21-T11: moved from batman_RadioSurvivorTests, steps renamed from
rs.signal.*). Development mod only. Load with: require "RST/RST_PeerChecksSignal"
(shared: the suite requires it, so every machine that loads the suite registers the steps; the handlers read the
notebook and the inventory of the local player of THIS machine).

What the requester sees of a signal mission is read on its client: the row of the mission in the notebook snapshot
(CoreAI.notebookClient.snapshot.missions, as the Missions page shows it) and the main inventory of the local player.

Steps (RST.Steps.on; solo: the local player answers in the same Lua state)
    carnet.signal.row    { mission, want = { field = value, ... }?, settleMs? }: with want, waits until the snapshot row
                         of the mission holds every wanted field (state, lit, toReport, claimed, engaged, zone), or the
                         client deadline (FAIL with the row seen); without want, reads the row after settleMs (a change
                         that should NOT happen had time to arrive). data = PS.summary(row) ({ missing = true } when no
                         row).
    carnet.signal.send   { command = "report" | "claim", mission, want }: the notebook button of that command (the same
                         request of the Missions tab (CA_NotebookMissions): CoreAI.notebookClient.send(command,
                         { mission, revision of the row shown here })), then waits until the row holds want; after a
                         claim, waits until the main inventory stopped changing for PS.SETTLE_MS (the items of the
                         server arrive by their own packets).
                         data = { row = PS.summary(row), gained = { [fullType] = count }, lastError }. Any other command
                         is refused (closed list PS.COMMANDS).
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerSignal = RST.PeerSignal or {}
local PS = RST.PeerSignal
local Steps = RST.Steps

PS.COMMANDS = { report = true, claim = true }   -- notebook buttons Report and Claim (CA_NotebookMissions.lua)
PS.SETTLE_MS = 1500

local function carnet() return CoreAI.notebookClient end

-- Snapshot row of the mission on this client, or nil.
function PS.row(C, id)
    for _, row in ipairs(C.snapshot and C.snapshot.missions or {}) do
        if row.id == id then return row end
    end
    return nil
end

-- Fields of a row the suite asserts, plain values only (they travel back to the server).
function PS.summary(row)
    if row == nil then return { missing = true } end
    return { state = row.state, lit = row.lit == true, toReport = row.toReport == true,
        claimed = type(row.claimedName) == "string" and row.claimedName ~= "", engaged = row.engaged == true,
        zone = row.mapZone ~= nil, revision = row.revision }
end

function PS.matches(summary, want)
    if type(want) ~= "table" then return true end
    for k, v in pairs(want) do
        if summary[k] ~= v then return false end
    end
    return true
end

function PS.describe(summary)
    if summary.missing then return "no row of the mission in the notebook here" end
    return "row " .. tostring(summary.state) .. ", lit " .. tostring(summary.lit) .. ", to report "
        .. tostring(summary.toReport) .. ", claimed " .. tostring(summary.claimed) .. ", engaged "
        .. tostring(summary.engaged) .. ", zone " .. tostring(summary.zone)
end

-- Count of each full type in the main inventory of the local player, or nil without a player.
function PS.counts()
    local p = type(getPlayer) == "function" and getPlayer() or nil
    if p == nil then return nil end
    local items = p:getInventory():getItems()
    local out = {}
    for i = 0, items:size() - 1 do
        local kind = items:get(i):getFullType()
        out[kind] = (out[kind] or 0) + 1
    end
    return out
end

-- Full types counted more in after than in before, with the difference; and a stable text of it.
function PS.gained(before, after)
    local out, keys = {}, {}
    for kind, n in pairs(after or {}) do
        local d = n - ((before or {})[kind] or 0)
        if d > 0 then
            out[kind] = d
            keys[#keys + 1] = kind
        end
    end
    table.sort(keys)
    local parts = {}
    for i, kind in ipairs(keys) do parts[i] = out[kind] .. " x " .. kind end
    return out, table.concat(parts, ", ")
end

Steps.on("carnet.signal.row", function(args)
    local C = carnet()
    if C == nil then return Steps.fail("notebook client (CoreAI.notebookClient) not loaded") end
    local want = type(args.want) == "table" and args.want or nil
    local settleAt = RST.now() + (tonumber(args.settleMs) or PS.SETTLE_MS)
    return function(ctx)
        local summary = PS.summary(PS.row(C, args.mission))
        local reached
        if want then
            reached = PS.matches(summary, want)
        else
            reached = RST.now() >= settleAt
        end
        if reached then return Steps.pass(PS.describe(summary), summary) end
        if ctx.final then return Steps.fail(PS.describe(summary) .. " (wanted state not reached)", summary) end
        return nil
    end
end)

Steps.on("carnet.signal.send", function(args)
    local C = carnet()
    if C == nil or type(C.send) ~= "function" then return Steps.fail("notebook client (CoreAI.notebookClient) not loaded") end
    local command = tostring(args.command)
    if not PS.COMMANDS[command] then return Steps.fail("refused: notebook command " .. command) end
    local row = PS.row(C, args.mission)
    if row == nil then return Steps.fail("no row of mission " .. tostring(args.mission) .. " in the notebook here") end
    local before = PS.counts()
    if before == nil then return Steps.fail("no local player") end
    C.lastError = nil
    C.send(command, { mission = row.id, revision = row.revision })
    local lastText, stableAt = nil, nil
    return function(ctx)
        local summary = PS.summary(PS.row(C, args.mission))
        local gained, text = PS.gained(before, PS.counts())
        local data = { row = summary, gained = gained,
            lastError = C.lastError ~= nil and tostring(C.lastError) or nil }
        local reached = PS.matches(summary, args.want)
        if reached and command == "claim" then
            -- The items reach the inventory by their own packets: wait until it stopped changing.
            if text ~= lastText then lastText, stableAt = text, RST.now() end
            reached = RST.now() - stableAt >= PS.SETTLE_MS
        end
        local message = command .. " sent: " .. PS.describe(summary)
            .. (text ~= "" and (", gained " .. text) or "")
            .. (data.lastError and (", refusal " .. data.lastError) or "")
        if reached then return Steps.pass(message, data) end
        if ctx.final then return Steps.fail(message .. " (wanted state not reached)", data) end
        return nil
    end
end)

return PS
