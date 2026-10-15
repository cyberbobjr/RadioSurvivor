--[[
RST_PeerChecksRadio - client steps of the radio, notebook and faction suites (E00-T04, E06-T03, E06-T05, E09-T03),
asked by the authority through RST.Steps (E01-T16). Development mod only. Load with:
require "RST/RST_PeerChecksRadio" (shared: the suites that ask these steps require it, so every client that loads the
suites has the handlers; the authority helpers below run on the server or in solo).

What a client sees from the server is read on the client itself:
    MP client   one OnServerCommand listener (installed once when this file loads on a client) keeps the last commands
                of the modules "RadioSurvivor" (radio: accepted, rejected, done, history, history_lines, history_add)
                and "RS_Carnet" (notebook: snapshot, identity, error...) in RST.PeerRadio.inbox, numbered.
    solo        the authority hands these commands to the client modules directly (RadioSurvivor_Const.clientHandler,
                RS_CarnetClient.receive): both are wrapped once, at the first step that needs them, to fill the same
                inbox (the wrapped functions are called first and unchanged).

Client handlers (RST.Steps.on)
    rs.talk        { args, waitMs }: sends the real radio command "talk" (module RadioSurvivor) with args (text,
                   channel, itemId, or source = "world" x y z index, or source = "vehicle" vehicleId part) and returns
                   the first answer of the server (accepted or rejected) in data { command, reason, text }.
    rs.vehicle     { op = "enter" | "exit", vehicleId, seat }: the player enters seat of the vehicle (getVehicleById,
                   BaseVehicle:enter, as ISEnterVehicle:perform) or leaves it (BaseVehicle:exit, as ISExitVehicle);
                   PASS once getPlayer():getVehicle() says so.
    rs.history     { texts }: asks the whole radio history of this character (RS_RadioHistory.request, the notebook
                   Radio tab) and returns, once the server answered, data { character, found = { [text] = { "khz:kind",
                   ... } }, characters = every character named by a history command this client received since
                   this file loaded (sorted), frequencies }.
    rs.faction     { op = "create" | "rename" | "disband", name }: vanilla faction packets of the faction panel
                   (sendFactionCreate, sendFactionChangeTitle, sendFactionDisband), MP only.
    carnet.mandate { member, action = "grant" | "revoke", waitMs }: notebook command "mandate" (Team tab buttons);
                   data { lastError } after waitMs, or as soon as the server refused.
    carnet.count   { ms }: during ms, snapshots received from the notebook server and snapshot or hello requests sent by
                   this client (RS_CarnetClient.send, wrapped for the window): data { snapshots, pulls, other }.
Authority helpers
    PR.stripHistory(prefix) -> n   radio history lines whose text starts with prefix removed from every notebook
                                   character (private state RS_State, marked dirty); cleanup of the radio suites.
    PR.player(t, user)             server player of an account answering a step ("local" in solo: the target player)
Kahlua: no next(), no goto, ASCII only; messages in English.
]]

require "RST/RST"
require "RST/RST_Steps"

RST.PeerRadio = RST.PeerRadio or {}
local PR = RST.PeerRadio
local Steps = RST.Steps

PR.RADIO_MODULE = "RadioSurvivor"
PR.CARNET_MODULE = "RS_Carnet"
PR.INBOX_MAX = 200
PR.TALK_MS = 8000
PR.VEHICLE_MS = 10000
PR.HISTORY_MS = 8000
PR.FACTION_MS = 10000
PR.MANDATE_MS = 3000
PR.inbox = PR.inbox or {}
PR.seq = PR.seq or 0
PR.characters = PR.characters or {}   -- character id -> history commands received naming it

local HISTORY_COMMANDS = { history = true, history_lines = true, history_add = true }

local function isClientSide() return type(isClient) == "function" and isClient() end
local function isServerSide() return type(isServer) == "function" and isServer() end

local function safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function historyModule()
    local ok, H = pcall(require, "RadioSurvivor/RS_RadioHistory")
    if ok and type(H) == "table" then return H end
    return nil
end

-- Keeps one command received from the server (both modules), numbered; counts history commands of another character.
function PR.record(module, command, args)
    if module ~= PR.RADIO_MODULE and module ~= PR.CARNET_MODULE then return end
    PR.seq = PR.seq + 1
    local entry = { n = PR.seq, module = module, command = command, at = RST.now() }
    if type(args) == "table" then
        entry.reason = args.reason
        entry.text = args.text
        entry.character = args.character
        if type(args.frequencies) == "table" then entry.frequencies = #args.frequencies end
    end
    if module == PR.RADIO_MODULE and HISTORY_COMMANDS[command] and entry.character ~= nil then
        -- Every character named by a history command this client received (RS_RadioHistory.owner switches to the
        -- last one: its own state cannot tell a foreign history afterwards).
        local key = tostring(entry.character)
        PR.characters[key] = (PR.characters[key] or 0) + 1
    end
    PR.inbox[#PR.inbox + 1] = entry
    while #PR.inbox > PR.INBOX_MAX do table.remove(PR.inbox, 1) end
end

-- Entries after mark (a value of PR.seq), optionally of one module and a set of commands.
function PR.since(mark, module, commands)
    local out = {}
    for _, e in ipairs(PR.inbox) do
        if e.n > mark and (module == nil or e.module == module) and (commands == nil or commands[e.command]) then
            out[#out + 1] = e
        end
    end
    return out
end

-- Solo: the authority calls the client modules directly; wrapped once (the original runs first, unchanged).
function PR.tapSolo()
    if isClientSide() or isServerSide() then return end
    local okConst, Const = pcall(require, "RadioSurvivor/RadioSurvivor_Const")
    if okConst and type(Const) == "table" and not PR._constTapped and type(Const.clientHandler) == "function" then
        local handler = Const.clientHandler
        Const.clientHandler = function(command, args)
            handler(command, args)
            PR.record(PR.RADIO_MODULE, command, args)
        end
        PR._constTapped = true
    end
    local C = RS_CarnetClient
    if type(C) == "table" and not PR._carnetTapped and type(C.receive) == "function" then
        local receive = C.receive
        C.receive = function(command, args)
            receive(command, args)
            PR.record(PR.CARNET_MODULE, command, args)
        end
        PR._carnetTapped = true
    end
end

local function localPlayer()
    if type(getPlayer) ~= "function" then return nil end
    return safe(getPlayer)
end

-- ---------------------------------------------------------------- client handlers

local ANSWERS = { accepted = true, rejected = true }

Steps.on("rs.talk", function(args)
    PR.tapSolo()
    local p = localPlayer()
    if p == nil then return Steps.fail("no local player") end
    local a = type(args.args) == "table" and args.args or {}
    if type(a.text) ~= "string" or a.text == "" then return Steps.fail("refused: talk without text") end
    local mark = PR.seq
    sendClientCommand(p, PR.RADIO_MODULE, "talk", a)
    return function(ctx)
        local got = PR.since(mark, PR.RADIO_MODULE, ANSWERS)[1]
        if got ~= nil then
            return Steps.pass(got.command .. (got.reason and (" " .. tostring(got.reason)) or ""),
                { command = got.command, reason = got.reason, text = got.text })
        end
        if ctx.final then return Steps.fail("no answer of the server to the talk command") end
        return nil
    end
end)

Steps.on("rs.vehicle", function(args)
    local p = localPlayer()
    if p == nil then return Steps.fail("no local player") end
    if type(getVehicleById) ~= "function" then return Steps.fail("getVehicleById missing") end
    if args.op ~= "enter" and args.op ~= "exit" then return Steps.fail("refused: vehicle operation " .. tostring(args.op)) end
    local id, asked = tonumber(args.vehicleId) or -1, false
    -- The vehicle reaches this client by the vehicle streaming of the server: polled until known.
    return function(ctx)
        local v = getVehicleById(id)
        if v == nil then
            if ctx.final then return Steps.fail("vehicle " .. tostring(args.vehicleId) .. " not known on this client") end
            return nil
        end
        if args.op == "enter" then
            if not asked and p:getVehicle() ~= v then
                asked = true
                if not v:enter(tonumber(args.seat) or 1, p) then
                    return Steps.fail("BaseVehicle:enter refused seat " .. tostring(args.seat))
                end
            end
            if p:getVehicle() == v then
                return Steps.pass("in vehicle " .. tostring(args.vehicleId) .. ", seat " .. tostring(v:getSeat(p)))
            end
            if ctx.final then return Steps.fail("not in the vehicle") end
            return nil
        end
        if not asked and p:getVehicle() == v then
            asked = true
            v:exit(p)
        end
        if p:getVehicle() == nil then return Steps.pass("out of the vehicle") end
        if ctx.final then return Steps.fail("still in a vehicle") end
        return nil
    end
end)

local LINES = { history = true, history_lines = true }

Steps.on("rs.history", function(args)
    PR.tapSolo()
    local H = historyModule()
    if H == nil then return Steps.fail("RadioSurvivor/RS_RadioHistory not loaded on this client") end
    local mark = PR.seq
    if not H.request() then return Steps.fail("history request not sent (no local player)") end
    return function(ctx)
        local got = PR.since(mark, PR.RADIO_MODULE, LINES)
        local header, lines = nil, 0
        for _, e in ipairs(got) do
            if e.command == "history" then header = e else lines = lines + 1 end
        end
        if header == nil or lines < (header.frequencies or 0) then
            if ctx.final then
                return Steps.fail("history not received (header " .. tostring(header ~= nil) .. ", " .. lines
                    .. " frequency packet(s))")
            end
            return nil
        end
        local found, freqs = {}, {}
        for _, text in ipairs(args.texts or {}) do found[text] = {} end
        for _, f in ipairs(H.frequencies) do
            freqs[#freqs + 1] = f.khz
            for _, line in ipairs(f.lines or {}) do
                local list = found[line.text]
                if list ~= nil then list[#list + 1] = tostring(f.khz) .. ":" .. tostring(line.kind) end
            end
        end
        local named = {}
        for cid in pairs(PR.characters) do named[#named + 1] = cid end
        table.sort(named)
        return Steps.pass(#H.frequencies .. " frequency(ies) in the Radio tab",
            { character = H.character, found = found, characters = named, frequencies = freqs })
    end
end)

Steps.on("rs.faction", function(args)
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

Steps.on("carnet.mandate", function(args)
    local C = RS_CarnetClient
    if C == nil then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    if args.action ~= "grant" and args.action ~= "revoke" then return Steps.fail("refused: action " .. tostring(args.action)) end
    C.lastError = nil
    C.send("mandate", { member = tostring(args.member), action = args.action })
    local waitMs = tonumber(args.waitMs) or PR.MANDATE_MS
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
    PR.tapSolo()
    local C = RS_CarnetClient
    if C == nil or type(C.send) ~= "function" then return Steps.fail("notebook client (RS_CarnetClient) not loaded") end
    local ms = tonumber(args.ms) or 10000
    local mark, started = PR.seq, RST.now()
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
        local snapshots = #PR.since(mark, PR.CARNET_MODULE, SNAPSHOT)
        return Steps.pass(snapshots .. " snapshot(s) received, " .. counts.pulls .. " request(s) sent in " .. ms .. " ms",
            { snapshots = snapshots, pulls = counts.pulls, other = counts.other })
    end
end)

-- ---------------------------------------------------------------- authority helpers

function PR.player(t, user)
    if user == Steps.LOCAL then
        local p = t and t.ctx and t.ctx.player or nil
        if p == nil and not isServerSide() then p = localPlayer() end
        return p
    end
    return Steps.playerOf(user)
end

function PR.stripHistory(prefix)
    local S = safe(require, "RadioSurvivor/RS_State")
    if type(S) ~= "table" or type(S.data) ~= "table" or type(S.data.characters) ~= "table" then return 0 end
    local n = 0
    for _, record in pairs(S.data.characters) do
        local radio = type(record) == "table" and record.radio or nil
        for _, f in ipairs(radio and radio.frequencies or {}) do
            local kept = {}
            for _, line in ipairs(f.lines or {}) do
                if type(line.text) == "string" and string.sub(line.text, 1, string.len(prefix)) == prefix then
                    n = n + 1
                else
                    kept[#kept + 1] = line
                end
            end
            f.lines = kept
        end
    end
    if n > 0 then S.dirty = true end
    return n
end

-- ---------------------------------------------------------------- subscription (MP clients, once per Lua state)

if not PR._subscribed and isClientSide() and type(Events) == "table" and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(function(module, command, args) RST.PeerRadio.record(module, command, args) end)
    PR._subscribed = true
end

return PR
