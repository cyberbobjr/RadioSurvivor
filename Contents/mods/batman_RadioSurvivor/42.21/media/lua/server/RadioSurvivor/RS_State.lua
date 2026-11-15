if isClient() then return end
--[[
Private state of the radio voices (authority only), two slots written in turn: batman_RadioSurvivor/state-<hex>-<0|1>.txt
= "RSSTATE2=<generation>", RSV2 bytes in hex, checksum, "end". E21-T04: data of the voices only (trade, personaState,
memory, facts, rescues, lifelogs, voiceDonors, voiceTeamChains, voiceStory, actionCounters, rewards ledgers); the
characters, NPC fiches and bindings of the notebook are the core mod's store (CA_NotebookStore), its missions and
exchange histories the core mod's files too.

- Companion of the notebook store (CA_NotebookStore.addCompanion): loaded by its init with the same world start, written
  by its save after the notebook file. S.save() saves the whole chain (missions, histories, notebook, then this file);
  before the notebook store is ready (benches), this file only.
- Corrupted storage (both slots exist and none is readable, or a schema newer than this code): S.blocked, nothing is
  written, the files are kept for recovery. Only S.init clears it (the notebook store is blocked with it).
- Failed write (C19, over the codec bounds included): NOT blocked. The state stays in memory with S.dirty, the slot of
  the failed generation is written again at the next save (the other slot keeps the last good file), S.failures counts
  the streak.
- Verification read: at the first write of the session and after a failure (C20); fast hex and checksum (CA_Codec).
- Schema: S.SCHEMA; S.MIGRATIONS[n](data) turns schema n into n + 1 (S.upgrade). None: schema 2 is current.
]]
local Codec = require 'CoreAI/CA_Codec'
local NotebookStore = require 'CoreAI/CA_NotebookStore'
local S = {data = nil, generation = 0, blocked = false, dirty = false, failures = 0, verified = false}
S.SCHEMA = 2
S.MIGRATIONS = {}
S.WARN_RATIO = 0.7   -- console warning when the state reaches 70 % of a codec bound

local function log(msg) print('[RS_State] ' .. tostring(msg)) end

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
    if type(data) ~= 'table' then return nil, true end
    local from = S.upgrade(data)
    if from == nil then return nil, true, true end -- unknown schema (newer mod version): never fall back to the other slot
    return {generation = gen, data = data, migrated = from}, true
end
S._read = read

function S.init(newWorld)
    local w = getWorld()
    local name = tostring(w:getGameMode()) .. '/' .. tostring(w:getWorld()) -- 42.22: GameMode object
    S.path = 'batman_RadioSurvivor/state-' .. Codec.hexBytes(name) -- historical per-unit name, never decoded
    local a, existsA, newerA = read(S.path .. '-0.txt')
    local b, existsB, newerB = read(S.path .. '-1.txt')
    local best = a
    if b and (not a or b.generation > a.generation) then best = b end
    S.failures, S.verified, S.warned = 0, false, false
    if not newWorld and (newerA or newerB) then
        S.blocked = true
        log('STORAGE BLOCKED: state written by a newer schema; preserve files for recovery')
        return false
    elseif best and not newWorld then
        S.data, S.generation = best.data, best.generation
        if best.migrated then log('state migrated from schema ' .. tostring(best.migrated)) end
    elseif not newWorld and (existsA or existsB) then
        S.blocked = true
        log('STORAGE BLOCKED: both state slots invalid; preserve files for recovery')
        return false
    else
        S.data = {schema = S.SCHEMA}
        S.generation = best and best.generation or 0
    end
    S.blocked = false
    return S.write()
end

local function failed(reason)
    S.failures = (S.failures or 0) + 1
    S.dirty, S.verified = true, false
    -- First failure of a streak, then every 20th: the save is retried by the next S.save (tick, command, OnSave).
    if S.failures == 1 or S.failures % 20 == 0 then
        log('STORAGE WRITE FAILED (' .. reason .. '), attempt ' .. S.failures
            .. '; state kept in memory, retried at the next save')
    end
    return false
end

local function warnSize(body)
    local ratio = math.max(#body / Codec.MAX_BYTES, (Codec.lastNodes or 0) / Codec.MAX_NODES)
    if ratio >= S.WARN_RATIO and not S.warned then
        S.warned = true
        log(string.format('WARNING: voice state at %d %% of its size limit (%d bytes, %d nodes)',
            math.floor(ratio * 100), #body, Codec.lastNodes or 0))
    elseif ratio < S.WARN_RATIO * 0.9 then
        S.warned = false
    end
end

-- Writes this file only (companion save of the notebook store).
function S.write()
    if S.blocked or not S.data then return false end
    local ok, body = pcall(Codec.encodeBytes, S.data)
    if not ok then return failed('state exceeds serialization bounds: ' .. tostring(body)) end
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
    if (S.failures or 0) > 0 then log('storage write recovered after ' .. S.failures .. ' failed attempt(s)') end
    S.generation, S.dirty, S.failures = gen, false, 0
    return true
end

-- Saves the whole chain once the notebook store is ready (missions, histories, notebook, then this file).
function S.save()
    if S.blocked or not S.data then return false end
    if NotebookStore.data then return NotebookStore.save() end
    return S.write()
end

NotebookStore.addCompanion({init = S.init, save = S.write, dirty = function() return S.dirty == true end})
require('RadioSurvivor/RS_MissionHooks').attach() -- E18-T05: giver of the radio voices in the core mission engine

return S
