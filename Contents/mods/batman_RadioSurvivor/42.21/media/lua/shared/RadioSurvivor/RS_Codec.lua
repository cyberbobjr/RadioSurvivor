--[[
RSV2: typed, length-prefixed UTF-8 byte strings. No JSON or executable Lua.

Two kinds of strings are handled here:
- Lua strings: the text the mod works with. In Kahlua (the game) a string is a Java String: #s and string.byte count
  UTF-16 units ("e acute" is one unit of code 233, U+2019 one unit of code 8217, a character outside the BMP is a
  surrogate pair). Under Lua 5.1 (lupa test benches) a string is already a sequence of UTF-8 bytes.
- Byte strings: one character per byte, codes 0-255. RSV2 lengths, hex, checksums and limits (C.MAX_BYTES, 256 KiB
  exchange envelopes) count these bytes, which are exactly the bytes the Python bridge reads (bridge/npc_protocol.py).

C.toUtf8 / C.fromUtf8 convert between them, without bitwise operators (math.floor and divisions only). UTF-16
surrogate pairs become one 4-byte code point; a lone surrogate becomes U+FFFD so the bytes stay valid UTF-8 for the
bridge's strict decoder.

Runtime detection, without any game global: the literal "\195\169" is 2 bytes under Lua 5.1, but the Kahlua lexer
decodes a string literal as UTF-8 (org.luaj.kahluafork.compiler.LexState.newstring), so it is one character in game.
Under Lua 5.1 both conversions are the identity. Tests may force the UTF-16 branch with C._utf16 = true (and restore
nil): under Lua 5.1 the branch then treats each byte as a UTF-16 unit, which covers U+0000-U+00FF only.

Tolerance (old saved states): before E00-T08, hex wrote each UTF-16 unit as is, so a U+0080-U+00FF character was one
Latin-1 byte (e9 for "e acute") with a length prefix counting it as 1. fromUtf8 keeps any byte that does not start a
valid UTF-8 sequence as the character of the same code (0-255) instead of failing. Read through the byte layer
(unhexBytes, checksumBytes, decodeBytes), such an old state keeps its checksum and its lengths and decodes to the
same text; an old ASCII-only state is byte-for-byte what the new code writes. Old states with a character above
U+00FF were already unreadable (more than two hex digits per unit) and stay so.

Layers:
- byte layer (storage and exchange files): encodeBytes, decodeBytes, hexBytes, unhexBytes, checksumBytes.
  hexBytes is the historical per-unit hex; on a Lua string with units above 255 it gives more than two digits per
  unit (kept only for the historical state file name, which is never decoded).
- text layer (Lua strings in, Lua strings out): encode, decode, hex, unhex, checksum.
]]
local C = {}
C.MAX_BYTES = 4194304 -- private state; exchange envelopes have a stricter 256 KiB limit

local UTF16 = (#"\195\169" == 1)
local NONASCII = '[^\1-\127]'
local floor = math.floor

local function utf16()
    if C._utf16 ~= nil then return C._utf16 end
    return UTF16
end

local function utf8Char(cp)
    if cp < 128 then return string.char(cp) end
    if cp < 2048 then return string.char(192 + floor(cp / 64), 128 + cp % 64) end
    if cp < 65536 then return string.char(224 + floor(cp / 4096), 128 + floor(cp / 64) % 64, 128 + cp % 64) end
    return string.char(240 + floor(cp / 262144), 128 + floor(cp / 4096) % 64, 128 + floor(cp / 64) % 64, 128 + cp % 64)
end

function C.toUtf8(s)
    if not utf16() or not s:find(NONASCII) then return s end
    local out, n, i, len = {}, 0, 1, #s
    while i <= len do
        local j = s:find(NONASCII, i)
        if not j then
            n = n + 1; out[n] = s:sub(i)
            break
        end
        if j > i then n = n + 1; out[n] = s:sub(i, j - 1) end
        local c = s:byte(j)
        i = j + 1
        if c >= 55296 and c <= 56319 then
            local d = s:byte(i)
            if d and d >= 56320 and d <= 57343 then
                c = 65536 + (c - 55296) * 1024 + (d - 56320)
                i = i + 1
            else
                c = 65533
            end
        elseif c >= 56320 and c <= 57343 then
            c = 65533
        end
        n = n + 1; out[n] = utf8Char(c)
    end
    return table.concat(out)
end

local function cont(b, k)
    local d = b:byte(k)
    if d and d >= 128 and d <= 191 then return d - 128 end
    return nil
end

-- Code point and size of the UTF-8 sequence starting at b[j] (lead code c), or nil if it is not valid UTF-8.
local function utf8At(b, j, c)
    if c < 128 then return c, 1 end
    if c >= 194 and c <= 223 then
        local d1 = cont(b, j + 1)
        if d1 then return (c - 192) * 64 + d1, 2 end
    elseif c >= 224 and c <= 239 then
        local d1, d2 = cont(b, j + 1), cont(b, j + 2)
        if d1 and d2 then
            local cp = (c - 224) * 4096 + d1 * 64 + d2
            if cp >= 2048 and (cp < 55296 or cp > 57343) then return cp, 3 end
        end
    elseif c >= 240 and c <= 244 then
        local d1, d2, d3 = cont(b, j + 1), cont(b, j + 2), cont(b, j + 3)
        if d1 and d2 and d3 then
            local cp = (c - 240) * 262144 + d1 * 4096 + d2 * 64 + d3
            if cp >= 65536 and cp <= 1114111 then return cp, 4 end
        end
    end
    return nil
end

function C.fromUtf8(b)
    if not utf16() or not b:find(NONASCII) then return b end
    local out, n, i, len = {}, 0, 1, #b
    while i <= len do
        local j = b:find(NONASCII, i)
        if not j then
            n = n + 1; out[n] = b:sub(i)
            break
        end
        if j > i then n = n + 1; out[n] = b:sub(i, j - 1) end
        local c = b:byte(j)
        local cp, size = utf8At(b, j, c)
        n = n + 1
        if not cp then
            out[n] = string.char(c) -- invalid UTF-8: the byte is kept as U+0000-U+00FF (old Latin-1 states)
            i = j + 1
        elseif cp >= 65536 then
            local v = cp - 65536
            out[n] = string.char(55296 + floor(v / 1024), 56320 + v % 1024)
            i = j + size
        else
            out[n] = string.char(cp)
            i = j + size
        end
    end
    return table.concat(out)
end

-- Byte layer ----------------------------------------------------------------------------------------------------

function C.hexBytes(s)
    return (s:gsub('.', function(c) return string.format('%02x', string.byte(c)) end))
end

function C.unhexBytes(s)
    if type(s) ~= 'string' or #s > C.MAX_BYTES * 2 or #s % 2 ~= 0 or s:find('[^0-9a-f]') then return nil end
    return (s:gsub('..', function(c) return string.char(tonumber(c, 16)) end))
end

-- Keys of a table in RSV2 order: by type name then text (type(k) .. tostring(k)), the order of the historical
-- comparator. Each sort text is built once and the texts are sorted with the default comparison, without a Lua call
-- per comparison (LK13-T10: whole encoding about 20 % faster, under Lua 5.1 and in the Kahlua VM, where table.sort
-- is the quicksort written in Lua in the game's stdlib.lua). Same bytes:
-- the texts of distinct keys differ, so both sorts give the one order of the keys. If two keys share a text (two
-- numbers equal to 14 digits under Lua 5.1; never in Kahlua, whose Double.toString is exact), the historical
-- comparator is used, as before.
--
-- LK13-T06 (same bytes, about 2.3 times faster in the Kahlua VM on the group registry): one flat output buffer
-- joined once (no nested table.concat, which copied each byte once per level); within one encodeBytes call, the
-- sort text and the encoded form of each key, and the encoded form of short strings, are computed once (the same keys
-- and words come back in every member and group); small tables sorted by insertion in place (no call per
-- comparison). Nothing is kept between calls (no stale entry if tostring or C._utf16 changes, as in tests).
local function legacyLess(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end

local SHORT = 64        -- strings up to this length are encoded once per call
local INSERTION = 12    -- tables up to this many keys are sorted by insertion

-- Encodes value at depth into out (from index n + 1); cache = { keyText, keyEnc, str } of this call. Returns the
-- new last index.
local function packInto(out, n, value, depth, cache)
    assert(depth <= 12, 'RSV2 depth')
    local kind = type(value)
    if kind == 'string' then
        local e = cache.str[value]
        if e == nil then
            local s = C.toUtf8(value)
            e = 's' .. #s .. ':' .. s
            if #value <= SHORT then cache.str[value] = e end
        end
        out[n + 1] = e
        return n + 1
    end
    if kind == 'number' then
        local s = tostring(value)
        out[n + 1] = 'n' .. #s .. ':' .. s
        return n + 1
    end
    if kind == 'boolean' then
        out[n + 1] = value and 'b1' or 'b0'
        return n + 1
    end
    assert(kind == 'table', 'RSV2 type')
    local keyText, keyEnc = cache.keyText, cache.keyEnc
    local texts, byText, count, legacy = {}, {}, 0, false
    for k in pairs(value) do
        local text = keyText[k]
        if text == nil then
            local kk = type(k)
            assert(kk == 'string' or kk == 'number', 'RSV2 key')
            local ks = tostring(k)
            text = kk .. ks
            local e
            if kk == 'string' then
                local u = C.toUtf8(k)
                e = 's' .. #u .. ':' .. u
            else
                e = 'n' .. #ks .. ':' .. ks
            end
            if k ~= 0 then keyText[k], keyEnc[k] = text, e end   -- 0 and -0 are one table key, two texts
        end
        if byText[text] ~= nil then legacy = true end
        count = count + 1
        texts[count] = text
        byText[text] = k
    end
    n = n + 1
    out[n] = 't' .. count .. ':'
    local keys
    if legacy then
        keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, legacyLess)
    else
        if count > INSERTION then
            table.sort(texts)
        else
            for i = 2, count do
                local v = texts[i]
                local j = i - 1
                while j >= 1 and v < texts[j] do
                    texts[j + 1] = texts[j]
                    j = j - 1
                end
                texts[j + 1] = v
            end
        end
        keys = texts
        for i = 1, count do keys[i] = byText[texts[i]] end
    end
    for i = 1, count do
        local k = keys[i]
        local e = keyEnc[k]
        if e == nil then   -- key 0, or not seen in this call
            n = packInto(out, n, k, depth + 1, cache)
        else
            n = n + 1
            out[n] = e
        end
        n = packInto(out, n, value[k], depth + 1, cache)
    end
    return n
end

function C.encodeBytes(value)
    local out = {}
    packInto(out, 0, value, 0, { keyText = {}, keyEnc = {}, str = {} })
    local result = table.concat(out)
    assert(#result <= C.MAX_BYTES, 'RSV2 size')
    return result
end

function C.decodeBytes(s)
    if type(s) ~= 'string' or #s > C.MAX_BYTES then return nil end
    local pos, nodes = 1, 0
    local function read(depth)
        nodes = nodes + 1
        assert(depth <= 12 and nodes <= 200000, 'RSV2 complexity')
        local kind = s:sub(pos, pos)
        pos = pos + 1
        if kind == 'b' then
            local b = s:sub(pos, pos)
            pos = pos + 1
            assert(b == '0' or b == '1', 'RSV2 boolean')
            return b == '1'
        end
        assert(kind == 't' or kind == 'n' or kind == 's', 'RSV2 tag')
        local colon = s:find(':', pos, true)
        assert(colon and colon - pos <= 7, 'RSV2 length')
        local digits = s:sub(pos, colon - 1)
        assert(digits:match('^%d+$'), 'RSV2 digits')
        local len = tonumber(digits)
        assert(len <= C.MAX_BYTES, 'RSV2 length limit')
        pos = colon + 1
        if kind == 't' then
            assert(len <= 10000, 'RSV2 entries')
            local t = {}
            for _ = 1, len do
                local k = read(depth + 1)
                assert(type(k) == 'string' or type(k) == 'number', 'RSV2 key')
                assert(t[k] == nil, 'RSV2 duplicate')
                t[k] = read(depth + 1)
            end
            return t
        end
        assert(pos + len - 1 <= #s, 'RSV2 truncated')
        local v = s:sub(pos, pos + len - 1)
        pos = pos + len
        if kind == 'n' then
            v = tonumber(v)
            assert(v and v == v and math.abs(v) < math.huge, 'RSV2 number')
        else
            v = C.fromUtf8(v)
        end
        return v
    end
    local ok, value = pcall(read, 0)
    if ok and pos == #s + 1 then return value end
    return nil
end

function C.checksumBytes(s)
    local a, b = 1, 0
    for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end
    return string.format('%.0f', b * 65536 + a)
end

-- Text layer ----------------------------------------------------------------------------------------------------

function C.encode(value)
    return C.fromUtf8(C.encodeBytes(value))
end

function C.decode(s)
    if type(s) ~= 'string' or #s > C.MAX_BYTES then return nil end
    return C.decodeBytes(C.toUtf8(s))
end

function C.hex(s)
    return C.hexBytes(C.toUtf8(s))
end

function C.unhex(s)
    local bytes = C.unhexBytes(s)
    return bytes and C.fromUtf8(bytes)
end

function C.checksum(s)
    return C.checksumBytes(C.toUtf8(s))
end

return C
