-- JSON encoder of the files RadioSurvivor writes for the bridge (E27-T01: recipe index). Encode only.
-- Output is pure ASCII: every character above U+007F is written \uXXXX (UTF-16 units, surrogate pairs for code
-- points above U+FFFF), so the bytes are the same whether Kahlua's file writer encodes Java strings in UTF-8 or not.
-- Strings go through CA_Codec.toUtf8 first (Kahlua strings are UTF-16 units, Lua 5.1 strings UTF-8 bytes).
-- Tables: a table whose keys are exactly 1..n is an array, an empty table is the empty array []; any other table is
-- an object with string keys, written in sorted key order (stable files). Numbers: integers without decimals; NaN and
-- infinities are refused. Functions and other types are refused (error). ASCII only (Kahlua lexer).
local Codec = require "CoreAI/CA_Codec"

local Json = {}

local floor = math.floor
-- Any byte outside printable ASCII; then the quote and the backslash. ASCII escapes only: a decimal escape above 127
-- in a pattern is decoded as UTF-8 by the Kahlua lexer.
local NOT_PRINTABLE = '[^\32-\126]'
local QUOTE_OR_BACKSLASH = '["\\]'
local SHORT = { [8] = '\\b', [9] = '\\t', [10] = '\\n', [12] = '\\f', [13] = '\\r', [34] = '\\"', [92] = '\\\\' }

local function unit(n)
    return string.format('\\u%04x', n)
end

-- Code point of the UTF-8 sequence at byte i of b, and the next index; a malformed byte stands for U+FFFD.
local function codePoint(b, i)
    local c = string.byte(b, i)
    local size, cp
    if c < 192 then return (c < 128) and c or 65533, i + 1
    elseif c < 224 then size, cp = 2, c - 192
    elseif c < 240 then size, cp = 3, c - 224
    elseif c < 248 then size, cp = 4, c - 240
    else return 65533, i + 1 end
    for k = 1, size - 1 do
        local d = string.byte(b, i + k)
        if d == nil or d < 128 or d >= 192 then return 65533, i + 1 end
        cp = cp * 64 + (d - 128)
    end
    return cp, i + size
end

function Json.string(s)
    local b = Codec.toUtf8(s)
    if not b:find(NOT_PRINTABLE) and not b:find(QUOTE_OR_BACKSLASH) then return '"' .. b .. '"' end
    local out, n, i, len = { '"' }, 1, 1, #b
    while i <= len do
        local c = string.byte(b, i)
        local piece
        if c >= 32 and c < 128 and c ~= 34 and c ~= 92 then
            piece = string.char(c)
            i = i + 1
        elseif c < 128 then
            piece = SHORT[c] or unit(c)
            i = i + 1
        else
            local cp
            cp, i = codePoint(b, i)
            if cp > 65535 then
                cp = cp - 65536
                piece = unit(55296 + floor(cp / 1024)) .. unit(56320 + cp % 1024)
            else
                piece = unit(cp)
            end
        end
        n = n + 1
        out[n] = piece
    end
    out[n + 1] = '"'
    return table.concat(out)
end

local function number(v)
    if v ~= v or v == math.huge or v == -math.huge then error('RS_Json: number not representable: ' .. tostring(v)) end
    if v == floor(v) and v > -1e15 and v < 1e15 then return string.format('%.0f', v) end
    return string.format('%.14g', v)
end

local encode

local function isArray(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count == #t
end

local function encodeTable(t, depth)
    if depth > 32 then error('RS_Json: table too deep') end
    local out = {}
    if isArray(t) then
        for i = 1, #t do out[i] = encode(t[i], depth + 1) end
        return '[' .. table.concat(out, ',') .. ']'
    end
    local keys = {}
    for k in pairs(t) do
        if type(k) ~= 'string' then error('RS_Json: object key is not a string: ' .. tostring(k)) end
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for i, k in ipairs(keys) do out[i] = Json.string(k) .. ':' .. encode(t[k], depth + 1) end
    return '{' .. table.concat(out, ',') .. '}'
end

encode = function(v, depth)
    local kind = type(v)
    if kind == 'string' then return Json.string(v) end
    if kind == 'number' then return number(v) end
    if kind == 'boolean' then return v and 'true' or 'false' end
    if kind == 'table' then return encodeTable(v, depth) end
    error('RS_Json: cannot encode a value of type ' .. kind)
end

-- JSON text of a Lua value (string, number, boolean, table as above).
function Json.encode(v)
    return encode(v, 0)
end

return Json
