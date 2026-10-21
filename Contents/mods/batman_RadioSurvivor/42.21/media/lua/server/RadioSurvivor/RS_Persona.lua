-- Radio Survivor : fiches des voix radio (E05-T01), lecture et validation stricte côté serveur.
-- Format : docs/specifications-techniques/persona-format.md. Mêmes règles et mêmes messages (« line N: raison », en anglais) que
-- bridge/persona_store.py ; tests/test_personas.py compare les deux lecteurs sur les mêmes fichiers.
-- Aucun loadstring : chaque ligne est découpée et contrôlée à la main.
-- Utilisé par RS_Personas.lua (chargement et relecture à chaud des fiches, E05-T02 ; tirage des fréquences dans
-- les plages frequency_range, E05-T07).
-- Seulement de l'ASCII dans ce fichier : le lexeur Kahlua change les littéraux non ASCII en U+FFFD. Les
-- échappements d'octets UTF-8 ci-dessous donnent un seul caractère en Kahlua (une unité UTF-16, comme les
-- lignes rendues par getFileReader) et les mêmes octets sous Lua 5.1 (banc lupa).
if isClient() then return end

local Persona = {}

Persona.FORMAT = "1"
Persona.SEPARATOR = "[prompt]"
local BOM = "\239\187\191"          -- U+FEFF
local REPLACEMENT = "\239\191\189"  -- U+FFFD : octets UTF-8 invalides décodés par InputStreamReader

local ACTION_LIST = { "say", "mark_map", "reveal_area", "signal", "place_cache", "place_scene", "start_mission",
    "persona_state", "remember", "propose_trade", "report_mission", "share_frequency" }
local RADIO_LIST = { "any", "high_tier" }
local LOCATION_LIST = { "none", "fixed", "rescue" }
local CACHE_TABLES = { "medical", "ammo", "tools", "food", "radio" }
local MISSION_TEMPLATES = { "scout", "deliver", "retrieve", "clear", "signal" }
local REWARDS = { "cache", "frequency", "stashmap", "lesson" }
local TEACHES = { "Doctor", "Aiming", "Reloading", "Woodwork", "Mechanics", "Electricity", "MetalWelding",
    "Cooking", "Farming", "Fishing", "Trapping", "PlantScavenging" }
local STATE_LIST = { "active", "silent", "gone", "dead" }
local KEY_LIST = { "format", "id", "name", "language", "frequencies", "frequency_range", "radio", "listen",
    "location", "coords", "knows", "ignores", "secret", "place", "actions", "budget", "call_one_in", "call_text",
    "state", "cache_table", "shares", "teaches", "missions", "rewards" }
-- Puis frequencies ou frequency_range (l'une des deux, pas les deux : E05-T07).
local REQUIRED = { "format", "id", "name" }
local MIN_KHZ, MAX_KHZ, STEP_KHZ = 1000, 999800, 200
local MAX_COUNT = 999999
local MAX_CALL_ONE_IN = 1000
-- Lieux connus de la voix (E07-T04, action mark_map) : au plus MAX_PLACES lignes place=, libellé d'au plus
-- MAX_PLACE_LABEL_BYTES octets en UTF-8 (comptés comme le pont, voir utf8Bytes).
local MAX_PLACES = 12
local MAX_PLACE_LABEL_BYTES = 48
Persona.MAX_PLACES = MAX_PLACES
-- Kahlua : un littéral d'octets UTF-8 devient un seul caractère (une unité UTF-16) ; Lua 5.1 (banc lupa) : 2 octets.
local KAHLUA = string.len("\195\169") == 1
local function set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local ACTIONS = set(ACTION_LIST)
local KEYS = set(KEY_LIST)
local REPEATABLE = set({ "knows", "ignores", "secret", "place" })
Persona.ACTIONS = ACTION_LIST

-- Erreur : levée par error({ line, reason }) dans l'analyse, rendue en « line N: reason ».
local function fail(line, reason)
    error({ rsPersonaLine = line, reason = reason }, 0)
end

local function trim(s)
    return (string.match(s, "^[ \t]*(.-)[ \t]*$"))
end

local function startsWith(s, prefix)
    return string.sub(s, 1, string.len(prefix)) == prefix
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Découpe sur les virgules ; chaque morceau sans espaces autour.
local function splitList(value)
    local parts, start = {}, 1
    while true do
        local comma = string.find(value, ",", start, true)
        if not comma then
            parts[#parts + 1] = trim(string.sub(value, start))
            return parts
        end
        parts[#parts + 1] = trim(string.sub(value, start, comma - 1))
        start = comma + 1
    end
end

local function digitsOnly(s, maxLen)
    return string.match(s, "^[0-9]+$") ~= nil and string.len(s) <= maxLen
end

local function count(value, key, line, maximum)
    maximum = maximum or MAX_COUNT
    if not digitsOnly(value, 6) or tonumber(value) > maximum then
        fail(line, "bad " .. key .. " '" .. value .. "' (whole number from 0 to " .. tostring(maximum) .. ")")
    end
    return tonumber(value)
end

-- Une fréquence en MHz à une décimale, rendue en kHz.
local function oneFrequency(part, line)
    local whole, tenth = string.match(part, "^([0-9]+)%.([0-9])$")
    if not whole or string.len(whole) > 3 then
        fail(line, "bad frequency '" .. part .. "' (MHz with one decimal, e.g. 145.0)")
    end
    local khz = tonumber(whole) * 1000 + tonumber(tenth) * 100
    if khz < MIN_KHZ or khz > MAX_KHZ then
        fail(line, "frequency " .. part .. " out of range (1.0 to 999.8 MHz)")
    end
    if khz % STEP_KHZ ~= 0 then
        fail(line, "frequency " .. part .. " is not on the 0.2 MHz step of the radios")
    end
    return khz
end

local function frequencies(value, line)
    local result = {}
    for _, part in ipairs(splitList(value)) do
        local khz = oneFrequency(part, line)
        if contains(result, khz) then
            fail(line, "duplicate frequency " .. part)
        end
        result[#result + 1] = khz
    end
    return result
end

-- Plages de tirage (E05-T07) : « bas-haut » en MHz, bas < haut, sans chevauchement entre plages de la fiche.
local function frequencyRanges(value, line)
    local result = {}
    for _, part in ipairs(splitList(value)) do
        local lowText, highText = string.match(part, "^([^-]*)%-([^-]*)$")
        local badRange = "bad frequency range '" .. part
            .. "' (two frequencies in MHz, lowest first, e.g. 140.0-150.0)"
        if not lowText then fail(line, badRange) end
        local low, high = oneFrequency(trim(lowText), line), oneFrequency(trim(highText), line)
        if low >= high then fail(line, badRange) end
        for _, other in ipairs(result) do
            if low <= other.high and high >= other.low then
                fail(line, "frequency range '" .. part .. "' overlaps another range of the sheet")
            end
        end
        result[#result + 1] = { low = low, high = high }
    end
    return result
end

local function listen(value, line)
    local result = {}
    if value == "always" then return result end
    for _, part in ipairs(splitList(value)) do
        local h1, m1, h2, m2 = string.match(part, "^([0-9][0-9]):([0-9][0-9])%-([0-9][0-9]):([0-9][0-9])$")
        if not h1 or tonumber(h1) > 23 or tonumber(h2) > 23 or tonumber(m1) > 59 or tonumber(m2) > 59 then
            fail(line, "bad listening hours '" .. part .. "' (always, or HH:MM-HH:MM ranges separated by commas)")
        end
        local from, to = tonumber(h1) * 60 + tonumber(m1), tonumber(h2) * 60 + tonumber(m2)
        if from == to then
            fail(line, "empty listening range '" .. part .. "'")
        end
        result[#result + 1] = { from = from, to = to }
    end
    return result
end

local function coords(value, line)
    local x, y, z = string.match(value, "^([0-9]+),([0-9]+),(%-?[0-9]+)$")
    local zDigits = z and string.gsub(z, "^%-", "")
    if not x or string.len(x) > 6 or string.len(y) > 6 or string.len(zDigits) > 2
            or tonumber(z) < -32 or tonumber(z) > 31 then
        fail(line, "bad coords '" .. value .. "' (x,y,z whole numbers, z from -32 to 31)")
    end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

-- Longueur en octets UTF-8, la même que len(text.encode('utf-8')) du pont. Kahlua : chaque unité UTF-16 compte
-- 1, 2 ou 3 octets, chaque moitié d'une paire de substitution 2 (4 pour la paire) ; Lua 5.1 : les octets mêmes.
local function utf8Bytes(text)
    if not KAHLUA then return string.len(text) end
    local total = 0
    for i = 1, string.len(text) do
        local c = string.byte(text, i)
        if c < 128 then
            total = total + 1
        elseif c < 2048 or (c >= 55296 and c <= 57343) then
            total = total + 2
        else
            total = total + 3
        end
    end
    return total
end

-- Une ligne place= (E07-T04) : « <id> <x>,<y>,<z> <libellé> ». places : lieux déjà lus ; placeLines : id -> ligne.
local function place(value, line, places, placeLines)
    local id, where, label = string.match(value, "^([^ \t]+)[ \t]+([^ \t]+)[ \t]+(.+)$")
    if not id then
        fail(line, "bad place '" .. value .. "' (id x,y,z label, e.g. mill 10600,9300,0 Old mill)")
    end
    if not string.match(id, "^[a-z0-9_]+$") or string.len(id) > 32 then
        fail(line, "bad place id '" .. id .. "' (a to z, 0 to 9 and _, 32 characters at most)")
    end
    local x, y, z = string.match(where, "^([0-9]+),([0-9]+),(%-?[0-9]+)$")
    local zDigits = z and string.gsub(z, "^%-", "")
    if not x or string.len(x) > 6 or string.len(y) > 6 or string.len(zDigits) > 2
            or tonumber(z) < -32 or tonumber(z) > 31 then
        fail(line, "bad place coords '" .. where .. "' (x,y,z whole numbers, z from -32 to 31)")
    end
    if utf8Bytes(label) > MAX_PLACE_LABEL_BYTES then
        fail(line, "place label of '" .. id .. "' too long (" .. tostring(MAX_PLACE_LABEL_BYTES)
            .. " bytes of UTF-8 at most)")
    end
    if placeLines[id] then
        fail(line, "duplicate place '" .. id .. "' (first set on line " .. tostring(placeLines[id]) .. ")")
    end
    if #places >= MAX_PLACES then
        fail(line, "too many places (" .. tostring(MAX_PLACES) .. " at most)")
    end
    placeLines[id] = line
    return { id = id, x = tonumber(x), y = tonumber(y), z = tonumber(z), label = label }
end

local function actions(value, line)
    local result = {}
    for _, part in ipairs(splitList(value)) do
        if not ACTIONS[part] then fail(line, "unknown action '" .. part .. "'") end
        if contains(result, part) then fail(line, "duplicate action '" .. part .. "'") end
        result[#result + 1] = part
    end
    return result
end

local function closedList(value, key, allowed, line)
    local result = {}
    for _, part in ipairs(splitList(value)) do
        if (allowed and not contains(allowed, part)) or (not allowed
                and (not string.match(part, "^[a-z][a-z0-9_]*$") or string.len(part) > 32)) then
            fail(line, "bad " .. key .. " entry '" .. part .. "'")
        end
        if contains(result, part) then fail(line, "duplicate " .. key .. " entry '" .. part .. "'") end
        result[#result + 1] = part
    end
    return result
end

local function choice(value, key, list, line)
    if not contains(list, value) then
        fail(line, "bad " .. key .. " '" .. value .. "' (expected " .. table.concat(list, ", ") .. ")")
    end
    return value
end

local function parse(lines, expectedId)
    local values = { knows = {}, ignores = {}, secret = {}, budgets = {}, places = {} }
    local placeLines = {}
    local seen = {}
    local budgetLines = {}
    local separator = nil
    for number, raw in ipairs(lines) do
        if number == 1 and startsWith(raw, BOM) then
            fail(1, "file starts with a byte order mark (save it as UTF-8 without BOM)")
        end
        if string.find(raw, REPLACEMENT, 1, true) then
            fail(number, "invalid UTF-8 (save the file as UTF-8)")
        end
        local text = trim(raw)
        -- Après le séparateur : texte libre, rien à contrôler de plus.
        if not separator and text == Persona.SEPARATOR then
            separator = number
        elseif not separator and text ~= "" and string.sub(text, 1, 1) ~= "#" then
            local eq = string.find(text, "=", 1, true)
            if not eq then fail(number, "expected key=value or " .. Persona.SEPARATOR) end
            local key, value = trim(string.sub(text, 1, eq - 1)), trim(string.sub(text, eq + 1))
            if not string.match(key, "^[a-z_]+$") and not string.match(key, "^[a-z_]+%.[a-z_]+$") then
                fail(number, "bad key '" .. key .. "'")
            end
            local action = nil
            if startsWith(key, "budget.") then
                action = string.sub(key, string.len("budget.") + 1)
                if not ACTIONS[action] then
                    fail(number, "unknown action '" .. action .. "' in key '" .. key .. "'")
                end
            elseif not KEYS[key] then
                fail(number, "unknown key '" .. key .. "'")
            end
            if not REPEATABLE[key] then
                if seen[key] then
                    fail(number, "duplicate key '" .. key .. "' (first set on line " .. tostring(seen[key]) .. ")")
                end
                seen[key] = number
            end
            if value == "" then fail(number, "empty value for key '" .. key .. "'") end

            if action then
                values.budgets[action] = count(value, key, number)
                budgetLines[#budgetLines + 1] = { action = action, line = number }
            elseif key == "format" then
                if value ~= Persona.FORMAT then
                    fail(number, "unsupported format '" .. value .. "' (expected " .. Persona.FORMAT .. ")")
                end
                values.format = value
            elseif key == "id" then
                if not string.match(value, "^[a-z][a-z0-9_]*$") or string.len(value) > 32 then
                    fail(number, "bad id '" .. value
                        .. "' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")
                end
                values.id = value
            elseif key == "language" then
                if not string.match(value, "^[a-z][a-z]$") then
                    fail(number, "bad language '" .. value .. "' (two lowercase letters, e.g. en)")
                end
                values.language = value
            elseif key == "frequencies" then
                values.frequencies = frequencies(value, number)
            elseif key == "frequency_range" then
                values.frequency_ranges = frequencyRanges(value, number)
            elseif key == "radio" then
                values.radio = choice(value, key, RADIO_LIST, number)
            elseif key == "listen" then
                values.listen = listen(value, number)
            elseif key == "location" then
                values.location = choice(value, key, LOCATION_LIST, number)
            elseif key == "coords" then
                values.coords = coords(value, number)
            elseif key == "cache_table" or key == "teaches" then
                values[key] = choice(value, key, key == "cache_table" and CACHE_TABLES or TEACHES, number)
            elseif key == "shares" or key == "missions" or key == "rewards" then
                local entries = key == "missions" and MISSION_TEMPLATES or (key == "rewards" and REWARDS or nil)
                values[key] = closedList(value, key, entries, number)
            elseif key == "actions" then
                values.actions = actions(value, number)
            elseif key == "budget" then
                values.budget = count(value, key, number)
            elseif key == "call_one_in" then
                values.call_one_in = count(value, key, number, MAX_CALL_ONE_IN)
            elseif key == "call_text" then
                if not string.match(value, "^[A-Za-z0-9_]+$") then
                    fail(number, "bad call_text '" .. value .. "' (translation key: A to Z, a to z, 0 to 9 and _)")
                end
                values.call_text = value
            elseif key == "state" then
                values.state = choice(value, key, STATE_LIST, number)
            elseif key == "place" then
                values.places[#values.places + 1] = place(value, number, values.places, placeLines)
            elseif REPEATABLE[key] then
                local list = values[key]
                list[#list + 1] = value
            else
                values[key] = value -- name
            end
        end
    end

    local last = math.max(#lines, 1)
    if not separator then
        fail(last, "missing " .. Persona.SEPARATOR .. " line before the prompt text")
    end
    local first, stop = separator + 1, #lines
    while first <= stop and trim(lines[first]) == "" do first = first + 1 end
    while stop >= first and trim(lines[stop]) == "" do stop = stop - 1 end
    if first > stop then
        fail(separator, "empty prompt text after " .. Persona.SEPARATOR)
    end
    local body = {}
    for i = first, stop do body[#body + 1] = lines[i] end
    for _, key in ipairs(REQUIRED) do
        if values[key] == nil then fail(separator, "missing key '" .. key .. "'") end
    end
    if values.frequencies == nil and values.frequency_ranges == nil then
        fail(separator, "missing key 'frequencies' or 'frequency_range'")
    end
    if values.frequencies ~= nil and values.frequency_ranges ~= nil then
        fail(math.max(seen.frequencies, seen.frequency_range),
            "frequencies and frequency_range cannot be used together (fixed frequencies or ranges to draw from)")
    end
    if expectedId ~= nil and values.id ~= expectedId then
        fail(seen.id, "id '" .. values.id .. "' does not match the file name '" .. expectedId .. ".txt'")
    end
    local location = values.location or "none"
    if location == "fixed" and values.coords == nil then
        fail(seen.location, "location fixed needs a coords line")
    end
    if location ~= "fixed" and values.coords ~= nil then
        fail(seen.coords, "coords is only allowed with location=fixed")
    end
    if (values.call_one_in or 0) > 0 and values.call_text == nil then
        fail(seen.call_one_in, "call_one_in needs a call_text line")
    end
    local allowed = values.actions or { "say" }
    for _, b in ipairs(budgetLines) do
        if not contains(allowed, b.action) then
            fail(b.line, "budget." .. b.action .. " set but action '" .. b.action .. "' is not in actions")
        end
    end

    return {
        format = values.format, id = values.id, name = values.name, frequencies = values.frequencies or {},
        frequency_ranges = values.frequency_ranges or {},
        prompt = table.concat(body, "\n"), language = values.language or "en", radio = values.radio or "any",
        listen = values.listen or {}, location = location, coords = values.coords, knows = values.knows,
        ignores = values.ignores, secrets = values.secret, places = values.places, actions = allowed, budget = values.budget or 0,
        budgets = values.budgets, call_one_in = values.call_one_in or 0, call_text = values.call_text or "",
        state = values.state or "active",
        cache_table = values.cache_table or "", shares = values.shares or {}, teaches = values.teaches or "",
        missions = values.missions or { "scout" }, rewards = values.rewards or {},
    }
end

-- Fiche donnée en lignes (table de chaînes, comme getFileReader les rend). expectedId : nom du fichier sans
-- « .txt », ou nil. Rend la fiche, ou nil et « line N: raison ».
function Persona.parseLines(lines, expectedId)
    local ok, result = pcall(parse, lines, expectedId)
    if ok then return result end
    if type(result) == "table" and result.rsPersonaLine then
        return nil, "line " .. tostring(result.rsPersonaLine) .. ": " .. result.reason
    end
    error(result, 0) -- erreur de programmation : ne pas la déguiser en fiche refusée
end

-- Fichier sous Zomboid\Lua (chemin relatif, ex. « batman_RadioSurvivor/personas/walt.txt »). Son id doit être
-- le nom du fichier sans « .txt ».
function Persona.readFile(path)
    local reader = getFileReader(path, false)
    if not reader then return nil, "cannot read " .. tostring(path) end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    local stem = string.match(path, "([^/\\]+)%.txt$")
    return Persona.parseLines(lines, stem)
end

return Persona
