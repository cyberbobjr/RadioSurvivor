if isClient() then return end
--[[
Private notebook state (authority only), two slots written in turn: batman_RadioSurvivor/state-<hex>-<0|1>.txt =
"RSSTATE2=<generation>", RSV2 bytes in hex, checksum, "end".

- Corrupted storage (both slots exist and none is readable, or a schema newer than this code): S.blocked, nothing is
  written, the files are kept for recovery. Only S.init clears it.
- Failed write (no file writer, unreadable write, state over the codec bounds): NOT blocked (C19). The state stays in
  memory with S.dirty, the slot of the failed generation is written again at the next save (the other slot keeps the
  last good file), S.failures counts the streak. Over the bounds (C18), S.reducers (registered by the server, e.g.
  the purge of dead characters) are run once with force, then the save is refused: never a file the decoder refuses.
- Verification read: at the first write of the session and after a failure (C20); fast hex and checksum (RS_Codec).
- Schema: S.SCHEMA; S.MIGRATIONS[n](data) turns schema n into n + 1 (S.upgrade). None yet: schema 2 is current.
]]
local Codec = require 'RadioSurvivor/RS_Codec'
local S = {data = nil, generation = 0, blocked = false, dirty = false, failures = 0, verified = false}
S.SCHEMA = 2
S.MIGRATIONS = {}
S.reducers = S.reducers or {}
S.WARN_RATIO = 0.7   -- console warning when the state reaches 70 % of a codec bound

function S.uid(prefix)
    S.uidCounter = (S.uidCounter or 0) + 1
    if S.data then S.data.uidCounter = (S.data.uidCounter or 0) + 1 end
    local counter = S.data and S.data.uidCounter or S.uidCounter
    return prefix .. '-' .. string.format('%.0f', getTimestampMs()) .. '-' .. counter .. '-' .. ZombRand(100000, 999999)
end

-- Brings data up to S.SCHEMA. Returns the old schema when migrated, false when already current, nil when unknown
-- (newer than this code or no migration path).
function S.upgrade(data)
    if type(data) ~= 'table' or type(data.schema) ~= 'number' then return nil end
    local from = data.schema
    if from == S.SCHEMA then return false end
    if from > S.SCHEMA then return nil end
    while data.schema < S.SCHEMA do
        local step = S.MIGRATIONS[data.schema]
        if not step then return nil end
        step(data)
        data.schema = data.schema + 1
    end
    return from
end

local function read(path)
    local r = getFileReader(path, false)
    if not r then return nil, false end
    local header, raw, checksum, finish = r:readLine(), r:readLine(), r:readLine(), r:readLine()
    r:close()
    if not header or not raw or finish ~= 'end' then return nil, true end
    local gen = tonumber(header:match('^RSSTATE2=(%d+)$'))
    local body = Codec.unhexBytes(raw) -- byte layer: old Latin-1 states keep their checksum
    if not gen or not body or Codec.checksumBytes(body) ~= checksum then return nil, true end
    local data = Codec.decodeBytes(body)
    if type(data) ~= 'table' or type(data.world) ~= 'string' then return nil, true end
    local from = S.upgrade(data)
    if from == nil then return nil, true, true end -- unknown schema (newer mod version): never fall back to the other slot
    return {generation = gen, data = data, migrated = from}, true
end
S._read = read

function S.init(newWorld)
    local w = getWorld()
    local name = w:getGameMode() .. '/' .. w:getWorld()
    S.path = 'batman_RadioSurvivor/state-' .. Codec.hexBytes(name) -- historical per-unit name, never decoded
    local a, existsA, newerA = read(S.path .. '-0.txt')
    local b, existsB, newerB = read(S.path .. '-1.txt')
    local best = a
    if b and (not a or b.generation > a.generation) then best = b end
    S.failures, S.verified, S.warned = 0, false, false
    if not newWorld and (newerA or newerB) then
        S.blocked = true
        print('[RS_Carnet] STORAGE BLOCKED: state written by a newer schema; preserve files for recovery')
        return false
    elseif best and not newWorld then
        S.data, S.generation = best.data, best.generation
        if best.migrated then print('[RS_Carnet] state migrated from schema ' .. tostring(best.migrated)) end
    elseif not newWorld and (existsA or existsB) then
        S.blocked = true
        print('[RS_Carnet] STORAGE BLOCKED: both state slots invalid; preserve files for recovery')
        return false
    else
        S.data = {schema = S.SCHEMA, world = S.uid('world'), npcs = {}, bindings = {}, characters = {}, missions = {},
            outcomes = {}}
        S.generation = best and best.generation or 0
    end
    S.run = S.uid('run')
    S.blocked = false
    return S.save()
end

local function failed(reason)
    S.failures = (S.failures or 0) + 1
    S.dirty, S.verified = true, false
    -- First failure of a streak, then every 20th: the save is retried by the next S.save (tick, command, OnSave).
    if S.failures == 1 or S.failures % 20 == 0 then
        print('[RS_Carnet] STORAGE WRITE FAILED (' .. reason .. '), attempt ' .. S.failures
            .. '; state kept in memory, retried at the next save')
    end
    return false
end

local function encode()
    local ok, body = pcall(Codec.encodeBytes, S.data)
    if ok then return body end
    -- Over the codec bounds: reducers once (forced purge of what the players no longer see), then refused.
    local reduced = false
    for _, reduce in ipairs(S.reducers) do
        local okR, changed = pcall(reduce, S.data, true)
        if okR and changed then reduced = true end
    end
    if reduced then
        ok, body = pcall(Codec.encodeBytes, S.data)
        if ok then
            print('[RS_Carnet] state reduced to fit the serialization bounds')
            return body
        end
    end
    return nil, tostring(body)
end

local function warnSize(body)
    local ratio = math.max(#body / Codec.MAX_BYTES, (Codec.lastNodes or 0) / Codec.MAX_NODES)
    if ratio >= S.WARN_RATIO and not S.warned then
        S.warned = true
        print(string.format('[RS_Carnet] WARNING: notebook state at %d %% of its size limit (%d bytes, %d nodes)',
            math.floor(ratio * 100), #body, Codec.lastNodes or 0))
    elseif ratio < S.WARN_RATIO * 0.9 then
        S.warned = false
    end
end

function S.save()
    if S.blocked or not S.data then return false end
    local body, why = encode()
    if not body then return failed('state exceeds serialization bounds: ' .. tostring(why)) end
    warnSize(body)
    local gen = S.generation + 1
    local path = S.path .. '-' .. (gen % 2) .. '.txt'
    local w = getFileWriter(path, true, false)
    if not w then return failed('cannot open ' .. path) end
    w:write('RSSTATE2=' .. gen .. '\n' .. Codec.hexOfBytes(body) .. '\n' .. Codec.checksumBytes(body) .. '\nend\n')
    w:close()
    if not S.verified then
        local verify = read(path)
        if not verify or verify.generation ~= gen then return failed('write verification failed') end
        S.verified = true
    end
    if (S.failures or 0) > 0 then
        print('[RS_Carnet] storage write recovered after ' .. S.failures .. ' failed attempt(s)')
    end
    S.generation, S.dirty, S.failures = gen, false, 0
    return true
end

require('RadioSurvivor/RS_StatePurge').attach(S) -- C17: dead characters purged, reducer over the codec bounds

return S
