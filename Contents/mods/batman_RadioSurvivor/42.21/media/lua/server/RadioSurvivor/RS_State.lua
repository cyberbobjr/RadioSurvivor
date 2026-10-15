if isClient() then return end
local Codec = require 'RadioSurvivor/RS_Codec'
local S = {data = nil, generation = 0, blocked = false, dirty = false}

function S.uid(prefix)
    S.uidCounter = (S.uidCounter or 0) + 1
    if S.data then S.data.uidCounter = (S.data.uidCounter or 0) + 1 end
    local counter = S.data and S.data.uidCounter or S.uidCounter
    return prefix .. '-' .. string.format('%.0f', getTimestampMs()) .. '-' .. counter .. '-' .. ZombRand(100000, 999999)
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
    if type(data) ~= 'table' or data.schema ~= 2 or type(data.world) ~= 'string' then return nil, true end
    return {generation = gen, data = data}, true
end

function S.init(newWorld)
    local w = getWorld()
    local name = w:getGameMode() .. '/' .. w:getWorld()
    S.path = 'batman_RadioSurvivor/state-' .. Codec.hexBytes(name) -- historical per-unit name, never decoded
    local a, existsA = read(S.path .. '-0.txt')
    local b, existsB = read(S.path .. '-1.txt')
    local best = a
    if b and (not a or b.generation > a.generation) then best = b end
    if best and not newWorld then
        S.data, S.generation = best.data, best.generation
    elseif not newWorld and (existsA or existsB) then
        S.blocked = true
        print('[RS_Carnet] STORAGE BLOCKED: both state slots invalid; preserve files for recovery')
        return false
    else
        S.data = {schema = 2, world = S.uid('world'), npcs = {}, bindings = {}, characters = {}, missions = {}, outcomes = {}}
        S.generation = best and best.generation or 0
    end
    S.run = S.uid('run')
    S.blocked = false
    return S.save()
end

function S.save()
    if S.blocked or not S.data then return false end
    local ok, body = pcall(Codec.encodeBytes, S.data)
    if not ok then
        S.blocked = true
        print('[RS_Carnet] STORAGE BLOCKED: state exceeds serialization bounds')
        return false
    end
    local gen = S.generation + 1
    local path = S.path .. '-' .. (gen % 2) .. '.txt'
    local w = getFileWriter(path, true, false)
    if not w then S.blocked = true; return false end
    w:write('RSSTATE2=' .. gen .. '\n' .. Codec.hexBytes(body) .. '\n' .. Codec.checksumBytes(body) .. '\nend\n')
    w:close()
    local verify = read(path)
    if not verify or verify.generation ~= gen then
        S.blocked = true
        print('[RS_Carnet] STORAGE BLOCKED: state write verification failed')
        return false
    end
    S.generation, S.dirty = gen, false
    return true
end

return S
