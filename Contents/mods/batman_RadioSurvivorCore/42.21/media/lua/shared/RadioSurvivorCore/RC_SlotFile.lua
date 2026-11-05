--[[
RadioSurvivorCore: private state files of the authority, written in two slots in turn (E18-T03).

Same layout as the registries of RadioSurvivor and Living Knox: each slot file <base>-<0|1>.txt holds

    <HEADER>=<write number>
    <RSV2 bytes in hex (RC_Codec, byte layer)>
    <checksum of the bytes>
    end

Reading keeps the valid slot with the highest write number. Writing goes to the other slot, then reads it back. Files
live under Zomboid/Lua (getFileWriter / getFileReader), never in a global ModData (readable by every client).
]]
local Codec = require "RadioSurvivorCore/RC_Codec"

local SlotFile = {}

-- Reads one slot: { seq, data } (data not validated), then exists (the file exists and is not empty).
function SlotFile.readSlot(path, header)
    local r = getFileReader(path, false)
    if not r then return nil, false end
    local head, raw, checksum, finish = r:readLine(), r:readLine(), r:readLine(), r:readLine()
    r:close()
    if head == nil and raw == nil then return nil, false end
    if not head or not raw or finish ~= "end" then return nil, true end
    local seq = tonumber(string.match(head, "^" .. header .. "=(%d+)$") or "")
    local body = Codec.unhexBytes(raw)
    if not seq or not body or tostring(Codec.checksumBytes(body)) ~= checksum then return nil, true end
    local data = Codec.decodeBytes(body)
    if type(data) ~= "table" then return nil, true end
    return { seq = seq, data = data }, true
end

-- Reads both slots of base: best { seq, data, slot } or nil, then broken (a file exists but none could be read).
function SlotFile.read(base, header)
    local best, any = nil, false
    for slot = 0, 1 do
        local got, exists = SlotFile.readSlot(base .. "-" .. slot .. ".txt", header)
        any = any or exists
        if got and (best == nil or got.seq > best.seq) then
            got.slot = slot
            best = got
        end
    end
    return best, best == nil and any
end

-- Writes data as write number seq into the slot (seq % 2) of base, then reads it back. Returns true when the file
-- read back holds the same bytes, or false and a reason.
function SlotFile.write(base, header, seq, data)
    local ok, body = pcall(Codec.encodeBytes, data)
    if not ok or type(body) ~= "string" then return false, "encode: " .. tostring(body) end
    local path = base .. "-" .. (seq % 2) .. ".txt"
    local w = getFileWriter(path, true, false)
    if not w then return false, "no writer for " .. path end
    local hex = Codec.hexOfBytes(body)
    w:write(header .. "=" .. seq .. "\n" .. hex .. "\n" .. Codec.checksumBytes(body) .. "\nend\n")
    w:close()
    local back = SlotFile.readSlot(path, header)
    if not back or back.seq ~= seq then return false, "read back failed for " .. path end
    return true
end

-- File base name of a world: <dir><name>-<hex of "game mode/world">.
function SlotFile.worldBase(dir, name)
    local w = getWorld()
    return dir .. name .. "-" .. Codec.hexBytes(tostring(w:getGameMode()) .. "/" .. tostring(w:getWorld()))
end

return SlotFile
