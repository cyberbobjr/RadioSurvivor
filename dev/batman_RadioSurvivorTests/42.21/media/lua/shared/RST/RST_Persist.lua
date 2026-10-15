--[[
RST_Persist - snapshot files of the persistence suites (E01-T17: <base>.before, then <base>.after-reconnect,
<base>.after-reconnect2 or <base>.after-restart in autoclient.py --mp --phases). Development mod only.

    RST.Persist.write(name, header, data)  -> true, or false and a reason
    RST.Persist.read(name, header)         -> data, or nil and a reason ("run <header>.before first" when absent)
    RST.Persist.consume(name)              -> the file is replaced by the single line "consumed" (read refuses it)

File: Zomboid/Lua/batman_RadioSurvivor/tests/<name> of the machine running the suite (the server in MP; it survives a
restart of the dedicated server: same cache). Format (four lines): header, RS_Codec bytes of data in hexadecimal,
checksum of the bytes, "end". data: plain table (strings, numbers, booleans, nested tables), RS_Codec rules.
The snapshot stands in for what the mod keeps in its private state when a test works on an in-memory state (a work
store): it is written by the test, never by the mod, and never read by the mod.
]]

require "RST/RST"

RST.Persist = RST.Persist or {}
local P = RST.Persist

local function codec()
    return require "RadioSurvivor/RS_Codec"
end

local function path(name)
    return RST.FILE_DIR .. name
end

function P.write(name, header, data)
    if type(data) ~= "table" then return false, "snapshot data must be a table" end
    local C = codec()
    local ok, body = pcall(C.encodeBytes, data)
    if not ok then return false, "snapshot not encodable: " .. tostring(body) end
    return RST.writeLines(path(name), { header, C.hexBytes(body), C.checksumBytes(body), "end" })
end

local function readLines(file)
    if type(getFileReader) ~= "function" then return nil end
    local ok, reader = pcall(getFileReader, file, false)
    if not ok or reader == nil then return nil end
    local lines = {}
    pcall(function()
        while #lines < 8 do
            local line = reader:readLine()
            if line == nil then break end
            lines[#lines + 1] = tostring(line)
        end
    end)
    pcall(function() reader:close() end)
    return lines
end

function P.read(name, header)
    local file = path(name)
    local lines = readLines(file)
    if lines == nil or #lines == 0 then return nil, "no snapshot " .. file .. ": run the .before suite first" end
    if lines[1] == "consumed" then return nil, "snapshot " .. file .. " already used: run the .before suite again" end
    if lines[1] ~= header or lines[4] ~= "end" then return nil, "snapshot " .. file .. " is incomplete" end
    local C = codec()
    local body = C.unhexBytes(lines[2])
    if not body or C.checksumBytes(body) ~= lines[3] then return nil, "snapshot " .. file .. " is corrupt" end
    local ok, data = pcall(C.decodeBytes, body)
    if not ok or type(data) ~= "table" then return nil, "snapshot " .. file .. " cannot be decoded" end
    return data
end

function P.consume(name)
    return RST.writeLines(path(name), { "consumed" })
end

return P
