--[[
RadioSurvivorCore: the one queue of the LLM requests and answers (E18-T04, moved from the RS_Transport module of RadioSurvivor).

One writer for every mod (the Python bridge stays one process and one lock): each mod registers its kinds of
requests as LANES (Transport.register), keeps the requests of a lane in Transport[name] (a list) and calls
Transport.write after a change; the file holds every lane, by increasing order, then by registration. Caps stay with
each mod (decision of 2026-11-05: one queue, separate caps).

Requests file (Bridge.REQUESTS_FILE), protocol 2:
    protocol=2 / session=<Transport.session> / generation=<n>
    per request: req=<id>, then the lines of the lane format: default (RSV2) kind=<kind>, payload=<hex RSV2 of the
    request>; a lane may give its own format(out, request) (RadioSurvivor radio lane: key=value lines)
    commit=<n> / end
Answers file (Bridge.RESPONSES_FILE): resp=<id>, payload=<hex RSV2 of the answer>, ..., end; read by
Transport.readResponses for every lane (a file without "end" is not read yet).
Authority only (dedicated server or solo); a multiplayer client never writes the queue.
]]
local Bridge = require "RadioSurvivorCore/RC_Bridge"
local Codec = require "RadioSurvivorCore/RC_Codec"

local T = RC_Transport or { session = "initializing", generation = 0, order = {}, lanes = {} }
RC_Transport = T

T.MAX_RESPONSE_BYTES = 1048576

local function rsv2(out, r)
    out[#out + 1] = "kind=" .. r.kind
    out[#out + 1] = "payload=" .. Codec.hexBytes(Codec.encodeBytes(r))
end
T.rsv2 = rsv2

-- Registers the lane name (opts.order: place in the file, default 100; opts.format: line writer of one request,
-- default RSV2). Registering again keeps the place, the format and the requests already queued.
function T.register(name, opts)
    if T.lanes[name] ~= nil then return T[name] end
    opts = opts or {}
    T.lanes[name] = { order = tonumber(opts.order) or 100, format = opts.format or rsv2, seq = #T.order + 1 }
    T.order[#T.order + 1] = name
    table.sort(T.order, function(a, b)
        local la, lb = T.lanes[a], T.lanes[b]
        if la.order ~= lb.order then return la.order < lb.order end
        return la.seq < lb.seq
    end)
    if type(T[name]) ~= "table" then T[name] = {} end
    return T[name]
end

function T.write()
    if isClient() then return false end
    T.generation = T.generation + 1
    local out = { "protocol=2", "session=" .. T.session, "generation=" .. T.generation }
    for _, name in ipairs(T.order) do
        local format = T.lanes[name].format
        for _, r in ipairs(T[name] or {}) do
            out[#out + 1] = "req=" .. r.id
            format(out, r)
        end
    end
    out[#out + 1] = "commit=" .. T.generation
    out[#out + 1] = "end"
    local writer = getFileWriter(Bridge.REQUESTS_FILE, true, false)
    if not writer then return false end
    writer:write(table.concat(out, "\n") .. "\n")
    writer:close()
    return true
end

-- Answers of every lane: { [request id] = decoded answer }, or nil while the file is absent or incomplete.
function T.readResponses()
    local reader = getFileReader(Bridge.RESPONSES_FILE, false)
    if not reader then return nil end
    local answers, current, bytes, complete = {}, nil, 0, false
    local line = reader:readLine()
    while line do
        bytes = bytes + #line
        if bytes > T.MAX_RESPONSE_BYTES then break end
        if line == "end" then complete = true; break end
        local k, v = line:match("^(%a+)=(.*)$")
        if k == "resp" then current = v end
        if k == "payload" and current then
            local raw = Codec.unhexBytes(v)
            local decoded = raw and Codec.decodeBytes(raw)
            if type(decoded) == "table" and decoded.id == current then answers[current] = decoded end
        end
        line = reader:readLine()
    end
    reader:close()
    return complete and answers or nil
end

return T
