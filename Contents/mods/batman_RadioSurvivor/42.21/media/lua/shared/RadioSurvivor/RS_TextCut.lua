-- Radio Survivor : découpe d'une réplique en morceaux affichés l'un après l'autre (E17-T12). Fiche :
-- docs/conception/radio-groupes.md, « Découpe des répliques ».
--
-- TextCut.pieces(texte, max) -> { morceau, ... } : espaces regroupés, chaque morceau de max unités au plus
-- (string.len : unités UTF-16 en Kahlua, octets sous Lua 5.1), coupé, du plus au moins souhaitable :
--   1. après une fin de phrase : . ! ? ou points de suspension (U+2026), éventuellement suivis de " ' ) ou », puis
--      d'un espace (« 9.5 » n'est pas une fin de phrase : le point n'est pas suivi d'un espace) ;
--   2. après une virgule, un point-virgule ou deux-points suivis d'un espace ;
--   3. entre deux mots (devant une ponctuation détachée à la française, ? ! : ; » …, seulement à défaut d'autre
--      espace) ;
--   4. un mot seul plus long que max : coupé à max, jamais au milieu d'un caractère (octet de continuation UTF-8 sous
--      Lua 5.1, paire de substitution en Kahlua).
-- Chaque morceau est le plus long possible dans sa catégorie. Ponctuation lue caractère par caractère : aucune liste
-- de mots, aucune règle de langue. Miroir Python : bridge/radio_bridge.py cut_pieces (mêmes règles, longueur en
-- caractères ; égalité vérifiée dans la VM Kahlua réelle par tests/test_kahlua.py).
local TextCut = {}

-- Kahlua décode l'échappement en un seul caractère (base kahlua-lua.md) ; Lua 5.1 garde les octets.
local KAHLUA = #"\195\169" == 1
TextCut.ELLIPSIS = "\226\128\166"
local CLOSERS = { '"', "'", ")", "\194\187" }                       -- » en dernier : 2 octets sous Lua 5.1
local DETACHED = { "?", "!", ":", ";", "\194\187", TextCut.ELLIPSIS } -- ponctuation précédée d'un espace

local function endsWith(text, e, s)
    local n = string.len(s)
    return e >= n and string.sub(text, e - n + 1, e) == s
end

local function startsWith(text, i, s)
    return string.sub(text, i, i + string.len(s) - 1) == s
end

-- Fin du texte utile avant les guillemets ou parenthèses fermants qui terminent text[1..e].
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

-- Catégorie d'une coupe après text[1..e] (l'espace suit) : 3 fin de phrase, 2 pause, 1 entre deux mots.
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

-- Blancs : espace et caractères de contrôle (tabulation, sauts de ligne). Pas %s, qui dépend de la locale du C sous
-- Lua 5.1 (l'octet 0xA0 de « à » y est pris pour un blanc).
local BLANK = "[ %c]"

local function trim(text)
    return (string.gsub(string.gsub(text, "^" .. BLANK .. "+", ""), BLANK .. "+$", ""))
end

-- Dernière position d'une coupe forcée dans un mot : jamais avant un octet de continuation (Lua 5.1) ni entre les
-- deux unités d'une paire de substitution (Kahlua).
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

-- Fin du premier morceau d'un texte plus long que max, et début du reste.
local function firstCut(text, max)
    local best, bestClass = nil, 0
    for s = max + 1, 2, -1 do
        if string.sub(text, s, s) == " " then
            local c = classAt(text, s - 1)
            if c == 1 and detachedAt(text, s + 1) then c = 0.5 end   -- admis seulement à défaut d'autre espace
            if c > bestClass then best, bestClass = s, c end   -- de droite à gauche : le premier est le plus long
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

-- Vrai si le morceau se termine par une fin de phrase (contrôle des suites en jeu et des bancs).
function TextCut.endsSentence(piece)
    return classAt(piece, string.len(piece)) == 3
end

return TextCut
