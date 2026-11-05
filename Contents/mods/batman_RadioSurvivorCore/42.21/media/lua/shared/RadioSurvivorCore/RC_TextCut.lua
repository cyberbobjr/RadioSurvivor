-- RadioSurvivorCore: cuts a line of speech into pieces shown one after the other (E17-T12; moved to the core mod by
-- E18-T02). Design note: docs/annexes/conception/radio-groupes.md, section on cutting the lines.
--
-- TextCut.pieces(text, max) -> { piece, ... }: blanks collapsed, each piece at most max units long
-- (string.len: UTF-16 units in Kahlua, bytes under Lua 5.1), cut, from the most to the least wanted:
--   1. after the end of a sentence: . ! ? or an ellipsis (U+2026), optionally followed by " ' ) or a closing
--      guillemet (U+00BB), then a space ("9.5" is not the end of a sentence: no space follows the dot);
--   2. after a comma, a semicolon or a colon followed by a space;
--   3. between two words (before a French detached punctuation, ? ! : ; U+00BB U+2026, only when no other space
--      fits);
--   4. a single word longer than max: cut at max, never inside a character (UTF-8 continuation byte under Lua 5.1,
--      surrogate pair in Kahlua).
-- Each piece is the longest possible in its class. Punctuation read character by character: no word list, no
-- language rule. Python mirror: bridge/radio_bridge.py cut_pieces (same rules, length in characters; equality
-- checked in the real Kahlua VM by tests/test_kahlua.py).
local TextCut = {}

-- Kahlua decodes the escape into a single character (knowledge base kahlua-lua.md); Lua 5.1 keeps the bytes.
local KAHLUA = #"\195\169" == 1
TextCut.ELLIPSIS = "\226\128\166"
local CLOSERS = { '"', "'", ")", "\194\187" }                       -- U+00BB last: 2 bytes under Lua 5.1
local DETACHED = { "?", "!", ":", ";", "\194\187", TextCut.ELLIPSIS } -- punctuation preceded by a space

local function endsWith(text, e, s)
    local n = string.len(s)
    return e >= n and string.sub(text, e - n + 1, e) == s
end

local function startsWith(text, i, s)
    return string.sub(text, i, i + string.len(s) - 1) == s
end

-- End of the useful text before the closing quotes or parentheses that end text[1..e].
local function beforeClosers(text, e)
    local moved = true
    while moved and e > 0 do
        moved = false
        for _, c in ipairs(CLOSERS) do
            if endsWith(text, e, c) then
                e = e - string.len(c)
                moved = true
                break
            end
        end
    end
    return e
end

-- Class of a cut after text[1..e] (the space follows): 3 end of sentence, 2 pause, 1 between two words.
local function classAt(text, e)
    local k = beforeClosers(text, e)
    if k < 1 then return 1 end
    local ch = string.sub(text, k, k)
    if ch == "." or ch == "!" or ch == "?" or endsWith(text, k, TextCut.ELLIPSIS) then return 3 end
    if ch == "," or ch == ";" or ch == ":" then return 2 end
    return 1
end

local function detachedAt(text, i)
    for _, p in ipairs(DETACHED) do
        if startsWith(text, i, p) then return true end
    end
    return false
end

-- Blanks: space and control characters (tab, line breaks). Not %s, which depends on the C locale under Lua 5.1
-- (the byte 0xA0 of a UTF-8 "a grave" is taken there for a blank).
local BLANK = "[ %c]"

local function trim(text)
    return (string.gsub(string.gsub(text, "^" .. BLANK .. "+", ""), BLANK .. "+$", ""))
end

-- Last position of a forced cut inside a word: never before a continuation byte (Lua 5.1) nor between the two
-- units of a surrogate pair (Kahlua).
local function hardCut(text, max)
    local e = max
    if KAHLUA then
        local b = string.byte(text, e)
        if e > 1 and b ~= nil and b >= 55296 and b <= 56319 then e = e - 1 end
    else
        while e > 1 do
            local b = string.byte(text, e + 1)
            if b == nil or b < 128 or b >= 192 then break end
            e = e - 1
        end
    end
    return e
end

-- End of the first piece of a text longer than max, and start of the rest.
local function firstCut(text, max)
    local best, bestClass = nil, 0
    for s = max + 1, 2, -1 do
        if string.sub(text, s, s) == " " then
            local c = classAt(text, s - 1)
            if c == 1 and detachedAt(text, s + 1) then c = 0.5 end   -- allowed only when no other space fits
            if c > bestClass then best, bestClass = s, c end   -- right to left: the first one is the longest
            if bestClass == 3 then break end
        end
    end
    if best ~= nil then return best - 1, best + 1 end
    local e = hardCut(text, max)
    return e, e + 1
end

function TextCut.pieces(text, max)
    local out = {}
    text = trim((string.gsub(tostring(text or ""), BLANK .. "+", " ")))
    max = math.floor(tonumber(max) or 0)
    if max < 1 then
        if text ~= "" then out[1] = text end
        return out
    end
    while string.len(text) > max do
        local e, rest = firstCut(text, max)
        local piece = trim(string.sub(text, 1, e))
        if piece ~= "" then out[#out + 1] = piece end
        text = trim(string.sub(text, rest))
    end
    if text ~= "" then out[#out + 1] = text end
    return out
end

-- True when the piece ends a sentence (checks of the in-game suites and of the benches).
function TextCut.endsSentence(piece)
    return classAt(piece, string.len(piece)) == 3
end

return TextCut
