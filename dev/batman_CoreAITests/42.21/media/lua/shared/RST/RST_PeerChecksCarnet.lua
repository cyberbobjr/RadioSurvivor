--[[
RST_PeerChecksCarnet - client steps of the notebook and team suites (E00-T01, E00-T04, E09-T03, E18-T20), asked by
the authority through RST.Steps (E01-T16). E21-T11: moved from RST_PeerChecksRadio.lua of batman_RadioSurvivorTests.
Development mod only. Load with: require "RST/RST_PeerChecksCarnet" (shared: the suites that ask these steps require
it, so every client that loads the suites has the handlers).

What a client sees from the notebook server is read on the client itself:
    MP client   one OnServerCommand listener (installed once when this file loads on a client) keeps the last commands
                of the module "CoreAI" (notebook: snapshot, identity, error...) in RST.PeerCarnet.inbox, numbered.
    solo        the authority hands these commands to the notebook client directly (CoreAI.notebookClient.receive):
                wrapped once, at the first step that needs it, to fill the same inbox (the wrapped function is called
                first and unchanged).

Client handlers (RST.Steps.on)
    carnet.claim   { character, waitMs }: this client sends the notebook "hello" claiming the character id given (the
                   identity of ANOTHER account, E00-T01) and returns the character of the "identity" answer of the
                   server in data { character } (RST.PeerCarnet inbox; solo: the client module is tapped). FAIL when no
                   answer comes.
    core.faction   { op = "create" | "rename" | "disband", name }: vanilla faction packets of the faction panel
                   (sendFactionCreate, sendFactionChangeTitle, sendFactionDisband), MP only.
    carnet.mandate { member, action = "grant" | "revoke", waitMs }: command "mandate" of the core mod (Team tab buttons);
                   data { lastError } after waitMs, or as soon as the server refused.
    carnet.count   { ms }: during ms, snapshots received from the notebook server and snapshot or hello requests sent by
                   this client (CoreAI.notebookClient.send, wrapped for the window): data { snapshots, pulls, other }.
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerCarnet = RST.PeerCarnet or {}
local PC = RST.PeerCarnet
local Steps = RST.Steps

PC.CARNET_MODULE = "CoreAI"
PC.INBOX_MAX = 200
PC.CLAIM_MS = 5000
PC.FACTION_MS = 10000
PC.MANDATE_MS = 3000
PC.inbox = PC.inbox or {}
PC.seq = PC.seq or 0

local function isClientSide() return type(isClient) == "function" and isClient() end
local function isServerSide() return type(isServer) == "function" and isServer() end

local function safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- Keeps one command of the notebook module received from the server, numbered.
function PC.record(module, command, args)
    if module ~= PC.CARNET_MODULE then return end
    PC.seq = PC.seq + 1
    local entry = { n = PC.seq, module = module, command = command, at = RST.now() }
    if type(args) == "table" then
        entry.reason = args.reason
        entry.character = args.character
    end
    PC.inbox[#PC.inbox + 1] = entry
    while #PC.inbox > PC.INBOX_MAX do table.remove(PC.inbox, 1) end
end

-- Entries after mark (a value of PC.seq), optionally of a set of commands.
function PC.since(mark, commands)
    local out = {}
    for _, e in ipairs(PC.inbox) do
        if e.n > mark and (commands == nil or commands[e.command]) then out[#out + 1] = e end
    end
    return out
end

-- Solo: the authority calls the notebook client directly; wrapped once (the original runs first, unchanged).
function PC.tapSolo()
    if isClientSide() or isServerSide() then return end
    local C = CoreAI.notebookClient
    if type(C) == "table" and not PC._carnetTapped and type(C.receive) == "function" then
        local receive = C.receive
        C.receive = function(command, args)
            receive(command, args)
            PC.record(PC.CARNET_MODULE, command, args)
        end
        PC._carnetTapped = true
    end
end

local function localPlayer()
    if type(getPlayer) ~= "function" then return nil end
    return safe(getPlayer)
end

-- ---------------------------------------------------------------- client handlers

-- ---------------------------------------------------------------- carnet.claim (E21-T07: from RST_PeerChecks2.lua)

Steps.on("carnet.claim", function(args)
    local C = CoreAI.notebookClient
    if C == nil or type(C.send) ~= "function" then return Steps.fail("notebook client (CoreAI.notebookClient) not loaded") end
    if type(args.character) ~= "string" or args.character == "" then return Steps.fail("no character to claim") end
    PC.tapSolo()
    local mark = PC.seq
    local Config = require "CoreAI/CA_NotebookConfig"
    C.send("hello", { v = Config.VERSION, character = args.character })
    return function(ctx)
        local got = PC.since(mark, { identity = true })
        if #got > 0 then
            local character = got[#got].character
            return Steps.pass("claimed " .. tostring(args.character) .. ", identity answered " .. tostring(character),
                { character = character })
        end
        if ctx.final then return Steps.fail("no identity answer to the claim of " .. tostring(args.character)) end
        return nil
    end
end)

Steps.on("core.faction", function(args)
    if not isClientSide() then return Steps.skip("vanilla factions exist on a server only") end
    local p = localPlayer()
    if p == nil then return Steps.fail("no local player") end
    local op, name = tostring(args.op), args.name
    if op == "create" then
        if type(name) ~= "string" or string.len(name) < 3 or string.len(name) > 15 then
            return Steps.fail("refused: faction name '" .. tostring(name) .. "'")
        end
        sendFactionCreate(name, p:getUsername())
        return Steps.pass("faction " .. name .. " asked")
    end
    if op ~= "rename" and op ~= "disband" then return Steps.fail("refused: faction operation " .. op) end
    return function(ctx)
        local f = Faction.getPlayerFaction(p)
        if f == nil then
            if ctx.final then return Steps.fail("no faction of this player on this client") end
            return nil
        end
        if op == "rename" then
            sendFactionChangeTitle(f, tostring(name))
            return Steps.pass("rename to " .. tostring(name) .. " sent")
        end
        sendFactionDisband(f)
        return Steps.pass("disband of " .. tostring(f:getName()) .. " sent")
    end
end)

-- E18-T20: answers of the core mod to the command "mandate" (CA_Teams): its "error" reason, read by carnet.mandate.
local CoreAnswer = { lastError = nil }
if Events ~= nil and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(function(module, command, a)
        if module == "CoreAI" and command == "error" and type(a) == "table" then CoreAnswer.lastError = a.reason end
    end)
end

Steps.on("carnet.mandate", function(args)
    -- E18-T20: command "mandate" of the core mod (CA_Teams).
    local C = CoreAnswer
    if args.action ~= "grant" and args.action ~= "revoke" then return Steps.fail("refused: action " .. tostring(args.action)) end
    C.lastError = nil
    sendClientCommand(getPlayer(), "CoreAI", "mandate", { member = tostring(args.member), action = args.action })
    local waitMs = tonumber(args.waitMs) or PC.MANDATE_MS
    local started = RST.now()
    return function(ctx)
        if C.lastError ~= nil or RST.now() - started >= waitMs or ctx.final then
            return Steps.pass("mandate " .. args.action .. " " .. tostring(args.member) .. ": lastError "
                .. tostring(C.lastError), { lastError = C.lastError })
        end
        return nil
    end
end)

local SNAPSHOT = { snapshot = true }
local PULLS = { snapshot = true, hello = true }

Steps.on("carnet.count", function(args)
    PC.tapSolo()
    local C = CoreAI.notebookClient
    if C == nil or type(C.send) ~= "function" then return Steps.fail("notebook client (CoreAI.notebookClient) not loaded") end
    local ms = tonumber(args.ms) or 10000
    local mark, started = PC.seq, RST.now()
    local counts = { pulls = 0, other = 0 }
    local send = C.send
    C.send = function(command, a)
        if PULLS[command] then counts.pulls = counts.pulls + 1 else counts.other = counts.other + 1 end
        return send(command, a)
    end
    local restored = false
    local function restore()
        if not restored and C.send ~= send then C.send = send end
        restored = true
    end
    return function(ctx)
        if RST.now() - started < ms and not ctx.final then return nil end
        restore()
        local snapshots = #PC.since(mark, SNAPSHOT)
        return Steps.pass(snapshots .. " snapshot(s) received, " .. counts.pulls .. " request(s) sent in " .. ms .. " ms",
            { snapshots = snapshots, pulls = counts.pulls, other = counts.other })
    end
end)

-- ---------------------------------------------------------------- subscription (MP clients, once per Lua state)

if not PC._subscribed and isClientSide() and type(Events) == "table" and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(function(module, command, args) RST.PeerCarnet.record(module, command, args) end)
    PC._subscribed = true
end

return PC
