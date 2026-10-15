--[[
rs.codec — pure logic of RadioSurvivor/RS_Codec (RSV2 format): round trip, types, depth, sorted keys, hex/unhex,
invalid input, limits. Tag "shared": no game API is used; runs in game (RST.run("rs.codec"), RST.server, dedicated
server autorun) and outside the game (lupa, tests/test_rs_suites.py) on the real module of batman_RadioSurvivor.

Strings: in Kahlua a string is a Java String (#s, string.byte count UTF-16 units); under lupa (Lua 5.1) they count
UTF-8 bytes. RS_Codec converts Lua strings to UTF-8 bytes (C.toUtf8 / C.fromUtf8, E00-T08), so hex forms, length
prefixes and checksums of non-ASCII text are the same in both machines and are asserted as constants (UTF-8 bytes).
Non-ASCII literals are written as decimal escapes of their UTF-8 bytes ("caf\195\169" = "café"): the Kahlua lexer
keeps only the low byte of each source character, then decodes the literal as UTF-8 (org.luaj.kahluafork.compiler.
LexState.save / newstring), so a raw "é" in a string literal becomes U+FFFD in game. With byte escapes, the game
builds the right character (one UTF-16 unit) and lupa the same UTF-8 bytes.
Numbers: Lua 5.1 tostring keeps 14 significant digits, Kahlua keeps Java's shortest exact form; exact round trips
are only asserted on numbers that both print exactly (integers below 1e14, binary fractions like 0.5).
]]

require "RST/RST"

local function codec()
    return require "RadioSurvivor/RS_Codec"
end

-- n nested one-element tables around the string "x".
local function nest(n)
    local v = "x"
    for _ = 1, n do v = { v } end
    return v
end

RST.suite("rs.codec", { tags = { "shared" } }, function(s)
    s.test("module loads with its limits", function(t)
        local C = codec()
        t:eq("table", type(C))
        for _, name in ipairs({ "hex", "unhex", "encode", "decode", "checksum", "toUtf8", "fromUtf8", "hexBytes",
            "unhexBytes", "encodeBytes", "decodeBytes", "checksumBytes" }) do
            t:eq("function", type(C[name]), "RS_Codec." .. name)
        end
        t:eq(4194304, C.MAX_BYTES)
    end)

    s.test("round trip of every value type", function(t)
        local C = codec()
        local value = {
            flag = true, off = false, int = 42, neg = -3, half = 0.5, frac = -2.75, zero = 0, big = 123456789012,
            empty = "", text = "s5:not a tag; t2: colon:", digits = "12345", newline = "a\nb\r\tc",
            list = { 10, 20, "thirty", { inner = true } }, nothing = {},
            [1] = "numeric key", [2.5] = "fractional key", [-7] = "negative key",
        }
        local encoded = C.encode(value)
        t:eq("string", type(encoded))
        t:eq(value, C.decode(encoded))
        t:eq(encoded, C.encode(C.decode(encoded)), "encoding is stable")
        for _, scalar in ipairs({ true, false, 0, -1, 0.25, "", "plain" }) do
            t:eq(scalar, C.decode(C.encode(scalar)), "scalar " .. tostring(scalar))
        end
    end)

    s.test("number with many digits keeps 12 significant digits", function(t)
        -- Lua 5.1 prints 14 significant digits, Kahlua the exact Java form: only near equality is portable.
        local C = codec()
        t:near(1 / 3, C.decode(C.encode(1 / 3)), 1e-12)
        t:near(-123.456789, C.decode(C.encode(-123.456789)), 1e-9)
    end)

    s.test("exact encoded form of ASCII values", function(t)
        local C = codec()
        t:eq("b1", C.encode(true))
        t:eq("b0", C.encode(false))
        t:eq("n2:42", C.encode(42))
        t:eq("n2:-3", C.encode(-3))
        t:eq("n3:0.5", C.encode(0.5))
        t:eq("s5:hello", C.encode("hello"))
        t:eq("s0:", C.encode(""))
        t:eq("t0:", C.encode({}))
        t:eq("t2:s1:an1:1s1:bb1", C.encode({ b = true, a = 1 }))
    end)

    s.test("keys sorted by type then text", function(t)
        local C = codec()
        -- "number10" < "number2" < "stringx": the order is textual, numbers before strings.
        t:eq("t3:n2:10s1:bn1:2s1:as1:xs1:y", C.encode({ [2] = "a", [10] = "b", x = "y" }))
        -- Same table built in another insertion order: same bytes.
        local other = {}
        other.x = "y"; other[10] = "b"; other[2] = "a"
        t:eq(C.encode({ [2] = "a", [10] = "b", x = "y" }), C.encode(other))
    end)

    s.test("depth limit is 12 nested tables", function(t)
        local C = codec()
        local ok12, enc12 = pcall(C.encode, nest(12))
        t:ok(ok12, "12 nested tables refused: " .. tostring(enc12))
        t:eq(nest(12), C.decode(enc12))
        t:fails(function() C.encode(nest(13)) end, "RSV2 depth")
        t:eq(nil, C.decode(string.rep("t1:n1:1", 13) .. "s1:x"), "13 nested tables decoded")
        t:ok(C.decode(string.rep("t1:n1:1", 12) .. "s1:x") ~= nil, "12 nested tables not decoded")
    end)

    s.test("unsupported types and keys raise", function(t)
        local C = codec()
        t:fails(function() C.encode(function() end) end, "RSV2 type")
        t:fails(function() C.encode(nil) end, "RSV2 type")
        t:fails(function() C.encode({ f = function() end }) end, "RSV2 type")
        t:fails(function() C.encode({ [true] = 1 }) end, "RSV2 key")
        t:fails(function() C.encode({ [{}] = 1 }) end, "RSV2 key")
    end)

    s.test("hex and unhex on ASCII", function(t)
        local C = codec()
        t:eq("415a3a0a00", C.hex("AZ:\n\0"))
        t:eq("AZ:\n\0", C.unhex("415a3a0a00"))
        t:eq("", C.hex(""))
        t:eq("", C.unhex(""))
        local all = {}
        for i = 0, 127 do all[#all + 1] = string.char(i) end
        local ascii = table.concat(all)
        t:eq(ascii, C.unhex(C.hex(ascii)))
        t:eq(256, #C.hex(ascii))
    end)

    s.test("unhex refuses invalid text", function(t)
        local C = codec()
        t:eq(nil, C.unhex("abc"), "odd length")
        t:eq(nil, C.unhex("4A"), "upper case")
        t:eq(nil, C.unhex("zz"), "not hex")
        t:eq(nil, C.unhex("41 2"), "space")
        t:eq(nil, C.unhex(nil), "nil")
        t:eq(nil, C.unhex(41), "number")
    end)

    s.test("round trip of non-ASCII text", function(t)
        -- Same UTF-8 bytes in both machines: hex form, length prefix (in bytes) and checksum are constants.
        local C = codec()
        local text = "caf\195\169 cr\195\168me" -- "café crème"
        t:eq(text, C.decode(C.encode(text)), "encode/decode")
        t:eq(text, C.unhex(C.hex(text)), "hex/unhex")
        t:eq("636166c3a9206372c3a86d65", C.hex(text), "UTF-8 hex")
        t:eq("s12:", C.encodeBytes(text):sub(1, 4), "length prefix in bytes")
        t:eq("615056841", C.checksum(text), "checksum of the UTF-8 bytes")
        local key, value = "cl\195\169", "\195\169t\195\169" -- "clé", "été"
        t:eq({ [key] = value }, C.decode(C.encode({ [key] = value })))
    end)

    s.test("hex round trip of characters above U+00FF", function(t)
        -- Kahlua: string.byte gives the UTF-16 unit (8217 for U+2019) and %02x prints 4 digits, so unhex cannot
        -- rebuild it. lupa sees 3 UTF-8 bytes. A failure here in game is a bug of RS_Codec.hex, not of the suite.
        local C = codec()
        -- "l’abri € œuvre": U+2019, U+20AC, U+0153.
        local text = "l\226\128\153abri \226\130\172 \197\147uvre"
        t:eq(text, C.decode(C.encode(text)), "encode/decode")
        local hex = C.hex(text)
        t:eq(0, #hex % 2, "odd hex length " .. #hex)
        t:eq(text, C.unhex(hex), "hex/unhex")
        t:eq("6ce280996162726920e282ac20c59375767265", hex, "UTF-8 hex")
        -- U+1F4FB (outside the BMP): one surrogate pair in Kahlua, 4 UTF-8 bytes on the wire.
        local radio = "\240\159\147\187 ok"
        t:eq("f09f93bb206f6b", C.hex(radio), "4-byte UTF-8 hex")
        t:eq(radio, C.unhex(C.hex(radio)), "hex/unhex outside the BMP")
        t:eq(radio, C.decode(C.encode(radio)), "encode/decode outside the BMP")
    end)

    s.test("old state written before E00-T08 is read unchanged", function(t)
        -- RSSTATE2 body and checksum written by the previous codec (per-unit hex) for an ASCII-only state: the byte
        -- layer used by RS_State gives the same hex, the same checksum and the same table.
        local C = codec()
        local value = { schema = 2, world = "world-1", npcs = { a = { name = "Walt", order = 3 } } }
        local oldHex = "74333a73343a6e70637374313a73313a6174323a73343a6e616d6573343a57616c7473353a6f726465726e313a33"
            .. "73363a736368656d616e313a3273353a776f726c6473373a776f726c642d31"
        t:eq(oldHex, C.hexBytes(C.encodeBytes(value)), "same hex as the old code")
        local body = C.unhexBytes(oldHex)
        t:eq("4149549645", C.checksumBytes(body), "same checksum as the old code")
        t:eq(value, C.decodeBytes(body))
        -- Old Latin-1 byte (U+00E9 written as e9, length 4) in game: kept as U+00E9 by fromUtf8, not refused.
        -- Under lupa (no UTF-16 strings) the byte stays the raw byte 233: only the game form is asserted.
        local latin = C.decodeBytes(C.unhexBytes("74313a73343a6e616d6573343a636166e9"))
        t:ok(latin ~= nil, "old Latin-1 state refused")
        if #"\195\169" == 1 then t:eq({ name = "caf\195\169" }, latin) end
    end)

    s.test("decode refuses invalid input", function(t)
        local C = codec()
        local bad = {
            { nil, "nil" }, { 12, "number" }, { "", "empty" }, { "x", "unknown tag" }, { "b2", "bad boolean" },
            { "b1x", "trailing text" }, { "s5:ab", "truncated" }, { "s:ab", "no length" }, { "s-1:", "negative" },
            { "s12345678:a", "length over 7 digits" }, { "sx:a", "length not digits" }, { "s1a", "no colon" },
            { "n3:abc", "not a number" }, { "n8:Infinity", "infinity" }, { "n5:1e400", "overflow" },
            { "n3:nan", "nan" }, { "t2:s1:ab1s1:ab0", "duplicate key" }, { "t1:t0:b1", "table key" },
            { "t1:b1b1", "boolean key" }, { "t2:s1:ab1", "missing entry" }, { "t10001:", "too many entries" },
        }
        for _, case in ipairs(bad) do
            t:eq(nil, C.decode(case[1]), case[2])
        end
    end)

    s.test("size limits", function(t)
        -- The limit is read from C.MAX_BYTES at each call: lowered here and restored before any assertion, in
        -- the same synchronous step (no other Lua of the mod can run with the lowered value).
        local C = codec()
        local saved = C.MAX_BYTES
        local results = {}
        local ok, err = pcall(function()
            C.MAX_BYTES = 10
            results.encodeSmall = C.encode("12345")          -- s5:12345 = 8 characters
            results.encodeBig = pcall(C.encode, "123456789") -- s9:... = 12 characters
            results.decodeBig = C.decode("s9:123456789")
            results.decodeSmall = C.decode("s5:12345")
            results.unhexBig = C.unhex(string.rep("41", 11))
            results.unhexSmall = C.unhex(string.rep("41", 10))
        end)
        C.MAX_BYTES = saved
        t:ok(ok, "limit checks raised: " .. tostring(err))
        t:eq(4194304, C.MAX_BYTES, "limit restored")
        t:eq("s5:12345", results.encodeSmall)
        t:eq(false, results.encodeBig, "encode over the limit")
        t:eq(nil, results.decodeBig, "decode over the limit")
        t:eq("12345", results.decodeSmall)
        t:eq(nil, results.unhexBig, "unhex over twice the limit")
        t:eq(string.rep("A", 10), results.unhexSmall)
    end)

    s.test("checksum is Adler-32 printed in decimal", function(t)
        local C = codec()
        t:eq("1", C.checksum(""))
        t:eq("38600999", C.checksum("abc"))
        t:eq("2424862", C.checksum(string.rep("\0", 7) .. "\29"))
        local body = C.encode({ a = 1 })
        t:eq(C.checksum(body), C.checksum(C.encode(C.decode(body))))
    end)
end)
