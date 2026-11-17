-- Radio Survivor : fiches des voix radio (E05-T01), lecture et validation stricte cote serveur.
-- Format : docs/specifications-techniques/persona-format.md. Le serveur est le seul lecteur complet (E20-T03, ADR D03) :
-- tete (lignes cle=valeur), sections [mission <id>], [rewards], [category <id>], [trade], [note], puis [prompt].
-- E25-T01 (ADR lieux communs) : les lieux vivent dans le fichier commun personas/_places.txt (Persona.parsePlaces :
-- sections [place <id>], un point at= ou une zone area=) ; une fiche nomme ceux dont elle se sert (marks= de la tete,
-- target=, drops= et points= de [mission], landing= de [trade], cache_place= de [rewards]).
-- bridge/persona_store.py lit la tete (marks= compris), le fichier des lieux et le prompt avec les memes regles et les
-- memes messages (« line N: raison », en anglais) et passe les sections sans les lire ; tests/test_personas.py compare
-- les deux lecteurs, tests/test_persona_sections.py couvre ce que seul le serveur valide.
-- Regles injectees (RS_Personas.rules, racine de composition) : template(nom) -> gabarit de mission donne par une
-- voix (CA_Missions.voiceTemplate, schema `params` declare par le gabarit), rewards (natures de recompense de
-- RS_Rewards.KINDS), skills (RS_Rewards.SKILLS), categories (catalogue partage personas/_categories.txt), arrivals
-- (modes d'arrivee des marchands, RS_TradeArrivals.NAMES), itemWeight(type) -> kg ou nil (poids d'un objet du troc lu
-- dans son script, RS_ItemWeights.of, E22-T12), places (lieux communs en service, id -> lieu, E25-T01), buildings
-- (genres de batiment d'un objectif tire, CA_Sites.KINDS, dans leur ordre, E25-T01).
-- Valeurs des parametres : RS_PersonaParams, un validateur par genre.
-- Aucun loadstring : chaque ligne est decoupee et controlee a la main.
-- Seulement de l'ASCII dans ce fichier : le lexeur Kahlua change les litteraux non ASCII en U+FFFD. Les
-- echappements d'octets UTF-8 ci-dessous donnent un seul caractere en Kahlua (une unite UTF-16, comme les
-- lignes rendues par getFileReader) et les memes octets sous Lua 5.1 (banc lupa).
if isClient() then return end

local Params = require "RadioSurvivor/RS_PersonaParams"
local Levels = require "RadioSurvivor/RS_RadioLevels"

local Persona = {}

Persona.FORMAT = "1"
Persona.SEPARATOR = "[prompt]"
local BOM = "\239\187\191"          -- U+FEFF
local REPLACEMENT = "\239\191\189"  -- U+FFFD : octets UTF-8 invalides decodes par InputStreamReader

local ACTION_LIST = { "say", "mark_map", "reveal_area", "signal", "place_cache", "place_scene", "start_mission",
    "persona_state", "propose_trade", "report_mission", "share_frequency" }
-- Radio necessaire (E24-T01) : niveaux de RS_RadioLevels, du talkie le plus simple au materiel militaire.
local RADIO_LIST = Levels.ids()
local LOCATION_LIST = { "none", "fixed", "rescue" }
local STATE_LIST = { "active", "silent", "gone", "dead" }
-- E25-T01 (ADR D01) : distances d'un objectif tire autour de l'appelant (target=), jamais un identifiant de lieu.
-- Bandes en cases : CA_MissionConfig (E25-T02).
local DISTANCE_LIST = { "near", "far", "very_far" }
Persona.DISTANCES = DISTANCE_LIST
-- Portee d'un enchainement de missions (E20-T08, RS_MissionChain) : reussite par personnage ou par equipe.
local SCOPE_LIST = { "character", "team" }
-- Texte story= d'une mission, ajoute a la description du travail dite au modele (jobs=, RS_MissionVoice.jobs).
local MAX_STORY_BYTES = 200
-- E22-T07 : textes ecrits dans la fiche et montres au joueur : appel spontane (call=, une ligne radio) et lignes de la
-- note manuscrite (text= de [note], une ligne de la page chacune).
local MAX_CALL_BYTES = 200
local MAX_NOTE_LINE_BYTES = 40
local MAX_NOTE_LINES = 8
-- Puis radio ou frequency (l'une des deux exactement : E24-T01).
local REQUIRED = { "format", "id", "name" }
local MIN_KHZ, MAX_KHZ, STEP_KHZ = Levels.minKhz(), Levels.maxKhz(), Levels.STEP_KHZ
local MAX_COUNT = 999999
local MAX_CALL_ONE_IN = 1000
-- Lieux communs (E25-T01) : au plus MAX_PLACES sections [place] dans _places.txt, libelle d'au plus
-- MAX_PLACE_LABEL_BYTES octets en UTF-8 (comptes comme le pont, voir utf8Bytes), zone de cote 1 a MAX_AREA_SIDE cases ;
-- une fiche donne au plus MAX_MARKS reperes (marks=).
local MAX_PLACES = 500
local MAX_PLACE_LABEL_BYTES = 48
local MAX_AREA_SIDE = 1500
local MAX_MARKS = 12
Persona.MAX_PLACES = MAX_PLACES
Persona.MAX_MARKS = MAX_MARKS
Persona.PLACES_SEPARATOR = "[place <id>]"
-- Kahlua : un litteral d'octets UTF-8 devient un seul caractere (une unite UTF-16) ; Lua 5.1 (banc lupa) : 2 octets.
local KAHLUA = string.len("\195\169") == 1
local function set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local ACTIONS = set(ACTION_LIST)
-- Cle de tete budget.<action> : budget par jour de jeu d'une action de la liste actions.
local BUDGET_PREFIX = "budget."
Persona.ACTIONS = ACTION_LIST
-- Sans regles (banc, fiche sans section) : aucun gabarit, aucune nature de recompense, aucune categorie, aucun lieu.
local function noTemplate() return nil end
local NO_RULES = { template = noTemplate, rewards = {}, skills = {}, categories = {}, places = {}, buildings = {} }

-- Erreur : levee par error({ line, reason }) dans l'analyse, rendue en « line N: reason ».
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

-- Decoupe sur un separateur d'un caractere ; chaque morceau sans espaces autour.
local function split(value, sep)
    local parts, start = {}, 1
    while true do
        local at = string.find(value, sep, start, true)
        if not at then
            parts[#parts + 1] = trim(string.sub(value, start))
            return parts
        end
        parts[#parts + 1] = trim(string.sub(value, start, at - 1))
        start = at + 1
    end
end

local function splitList(value)
    return split(value, ",")
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

-- Poids d'un tirage : entier de 1 a MAX_COUNT.
local function weight(value, key, line)
    if not digitsOnly(value, 6) or tonumber(value) < 1 then
        fail(line, "bad " .. key .. " '" .. value .. "' (whole number from 1 to " .. tostring(MAX_COUNT) .. ")")
    end
    return tonumber(value)
end

-- Frequence fixe (frequency=, E24-T01) : MHz a une decimale, rendue en kHz, dans les bornes de toutes les radios et
-- sur leur pas.
local function oneFrequency(part, line)
    local whole, tenth = string.match(part, "^([0-9]+)%.([0-9])$")
    if not whole or string.len(whole) > 4 then
        fail(line, "bad frequency '" .. part .. "' (MHz with one decimal, e.g. 145.0)")
    end
    local khz = tonumber(whole) * 1000 + tonumber(tenth) * 100
    if khz < MIN_KHZ or khz > MAX_KHZ then
        fail(line, "frequency " .. part .. " out of range (" .. string.format("%.1f", MIN_KHZ / 1000) .. " to "
            .. string.format("%.1f", MAX_KHZ / 1000) .. " MHz)")
    end
    if khz % STEP_KHZ ~= 0 then
        fail(line, "frequency " .. part .. " is not on the " .. string.format("%.1f", STEP_KHZ / 1000)
            .. " MHz step of the radios")
    end
    return khz
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

-- x,y,z entiers, ou nil.
local function parseCoords(value)
    local x, y, z = string.match(value, "^([0-9]+),([0-9]+),(%-?[0-9]+)$")
    local zDigits = z and string.gsub(z, "^%-", "")
    if not x or string.len(x) > 6 or string.len(y) > 6 or string.len(zDigits) > 2
            or tonumber(z) < -32 or tonumber(z) > 31 then
        return nil
    end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

local function coords(value, line)
    local c = parseCoords(value)
    if not c then fail(line, "bad coords '" .. value .. "' (x,y,z whole numbers, z from -32 to 31)") end
    return c
end

-- Longueur en octets UTF-8, la meme que len(text.encode('utf-8')) du pont. Kahlua : chaque unite UTF-16 compte
-- 1, 2 ou 3 octets, chaque moitie d'une paire de substitution 2 (4 pour la paire) ; Lua 5.1 : les octets memes.
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

-- Texte ecrit dans la fiche et montre au joueur (call=, text= de [note]), au plus maxBytes octets UTF-8 : ni <, > ni ^
-- (balises et sauts de ligne des documents printMedia), % seulement dans %1 (frequence affichee ; getText, par
-- lequel la fenetre des documents repasse le texte, formaterait tout autre %).
local function writtenText(value, key, line, maxBytes)
    if utf8Bytes(value) > maxBytes then
        fail(line, key .. " too long (" .. tostring(maxBytes) .. " bytes of UTF-8 at most)")
    end
    if string.find(value, "[<>%^]") or string.find((string.gsub(value, "%%1", "")), "%", 1, true) then
        fail(line, "bad " .. key .. " '" .. value .. "' (no <, > or ^; % only in %1, the frequency)")
    end
    return value
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

local function isName(value)
    return string.match(value, "^[a-z][a-z0-9_]*$") ~= nil and string.len(value) <= 32
end

-- Identifiant de section (lieu, mission, categorie) : a-z, 0-9, _, 32 caracteres au plus.
local function isSectionId(value)
    return string.match(value, "^[a-z0-9_]+$") ~= nil and string.len(value) <= 32
end

-- Liste sans doublon ; allowed nil : chaque entree est un nom (isName).
local function closedList(value, key, allowed, line, hint)
    local result = {}
    for _, part in ipairs(splitList(value)) do
        if (allowed and not contains(allowed, part)) or (not allowed and not isName(part)) then
            fail(line, "bad " .. key .. " entry '" .. part .. "'" .. (hint or ""))
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

-- Tete : un lecteur par cle (values : valeurs lues, value : texte, line : numero de ligne). Kahlua : une erreur levee
-- a travers une fonction anonyme rangee dans une table casse pcall (NullPointerException « Method name is null ») ;
-- chaque lecteur est donc une fonction locale nommee.
local function headFormat(values, value, line)
    if value ~= Persona.FORMAT then
        fail(line, "unsupported format '" .. value .. "' (expected " .. Persona.FORMAT .. ")")
    end
    values.format = value
end

local function headId(values, value, line)
    if not isName(value) then
        fail(line, "bad id '" .. value .. "' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")
    end
    values.id = value
end

local function headName(values, value) values.name = value end

local function headLanguage(values, value, line)
    if not string.match(value, "^[a-z][a-z]$") then
        fail(line, "bad language '" .. value .. "' (two lowercase letters, e.g. en)")
    end
    values.language = value
end

local function headFrequency(values, value, line) values.frequency = oneFrequency(value, line) end
local function headRadio(values, value, line) values.radio = choice(value, "radio", RADIO_LIST, line) end
local function headListen(values, value, line) values.listen = listen(value, line) end
local function headLocation(values, value, line) values.location = choice(value, "location", LOCATION_LIST, line) end
local function headCoords(values, value, line) values.coords = coords(value, line) end
local function headShares(values, value, line) values.shares = closedList(value, "shares", nil, line) end
local function headActions(values, value, line) values.actions = actions(value, line) end
local function headBudget(values, value, line) values.budget = count(value, "budget", line) end

local function headCallOneIn(values, value, line)
    values.call_one_in = count(value, "call_one_in", line, MAX_CALL_ONE_IN)
end

local function headCallText(values, value, line)
    if not string.match(value, "^[A-Za-z0-9_]+$") then
        fail(line, "bad call_text '" .. value .. "' (translation key: A to Z, a to z, 0 to 9 and _)")
    end
    values.call_text = value
end

-- E22-T07 : texte de l'appel ecrit dans la fiche (%1 = frequence affichee), a la place de la cle call_text.
local function headCall(values, value, line) values.call = writtenText(value, "call", line, MAX_CALL_BYTES) end

local function headState(values, value, line) values.state = choice(value, "state", STATE_LIST, line) end

-- E25-T01 (ADR D04) : reperes que la voix peut donner (mark_map, reveal_area, repere d'une mission sans [rewards]),
-- lieux communs (points ou zones) dans l'ordre de la ligne, sans doublon, MAX_MARKS au plus.
local function headMarks(values, value, line, ctx)
    local marks, seen = {}, {}
    for _, id in ipairs(splitList(value)) do
        if not isSectionId(id) then fail(line, "bad marks entry '" .. id .. "'") end
        if seen[id] then fail(line, "duplicate marks entry '" .. id .. "'") end
        local place = ctx.shared[id]
        if not place then fail(line, "unknown place '" .. id .. "'") end
        seen[id] = true
        marks[#marks + 1] = place
    end
    if #marks > MAX_MARKS then fail(line, "too many marks (" .. tostring(MAX_MARKS) .. " at most)") end
    values.marks = marks
end

local HEAD = {
    format = headFormat, id = headId, name = headName, language = headLanguage, frequency = headFrequency,
    radio = headRadio, listen = headListen, location = headLocation,
    coords = headCoords, shares = headShares, actions = headActions, budget = headBudget,
    call_one_in = headCallOneIn, call_text = headCallText, call = headCall, state = headState, marks = headMarks,
}

-- Sections ----------------------------------------------------------------------------------------------------
-- Chaque section est un gestionnaire de la table SECTIONS : rank (ordre des messages et de la resolution), example
-- (identifiant d'exemple ; nil = section sans identifiant), repeatable (cles repetables), open(sec, ctx) a l'en-tete,
-- key(sec, key, value, line, ctx) a chaque ligne, close(sec, ctx) a la fin de la section, resolve(sec, ctx) apres
-- toute la fiche (references vers d'autres sections), finish(ctx) une fois apres toutes ses resolutions.
-- sec = { name, id, line, values = { cle -> valeur }, lines = { cle -> ligne }, keys = { cles dans l'ordre } }.

local function title(sec)
    if sec.id then return "[" .. sec.name .. " " .. sec.id .. "]" end
    return "[" .. sec.name .. "]"
end

local function unknownKey(sec, key, line)
    fail(line, "unknown key '" .. key .. "' in " .. title(sec))
end

local function requireKeys(sec, keys)
    for _, key in ipairs(keys) do
        if sec.values[key] == nil then fail(sec.line, "missing key '" .. key .. "' in " .. title(sec)) end
    end
end

-- Contexte des validateurs de RS_PersonaParams.
local function paramsContext(ctx)
    return { places = ctx.shared, categories = ctx.categories, skills = ctx.rules.skills or {},
        split = splitList }
end

local function param(kind, value, line, ctx)
    local parsed, reason = Params.check(kind, value, paramsContext(ctx))
    if parsed == nil then fail(line, reason) end
    return parsed
end

-- Point des lieux communs (planque, rendez-vous, cache : ADR D05) nomme par id, ou erreur a cette ligne.
local function pointAt(id, line, ctx)
    local place, reason = Params.point(id, paramsContext(ctx))
    if not place then fail(line, reason) end
    return place
end

-- [place <id>] du fichier commun _places.txt (E25-T01) : un point (at=x,y,z) ou une zone (area=x1,y1,x2,y2,z : deux
-- coins opposes dans n'importe quel ordre, ranges du plus petit au plus grand, cotes de 1 a MAX_AREA_SIDE cases,
-- bornes comprises), et label. Point : { id, label, x, y, z } ; zone : { id, label, z, area = { x1, y1, x2, y2 } }.
local function placeWhere(sec, key, line)
    local other = key == "at" and "area" or "at"
    if sec.lines[other] then fail(line, "place '" .. sec.id .. "' has both at and area") end
end

local function placeAt(sec, value, line)
    placeWhere(sec, "at", line)
    local c = parseCoords(value)
    if not c then fail(line, "bad place coords '" .. value .. "' (x,y,z whole numbers, z from -32 to 31)") end
    sec.place.x, sec.place.y, sec.place.z = c.x, c.y, c.z
end

-- x1,y1,x2,y2,z -> { x1, y1, x2, y2 } (plus petit d'abord) et z, ou nil.
local function parseArea(value)
    local a, b, c, d, z = string.match(value, "^([0-9]+),([0-9]+),([0-9]+),([0-9]+),(%-?[0-9]+)$")
    local corners = parseCoords((a or "") .. "," .. (b or "") .. "," .. (z or ""))
    local other = parseCoords((c or "") .. "," .. (d or "") .. "," .. (z or ""))
    if not corners or not other then return nil end
    local area = { x1 = math.min(corners.x, other.x), y1 = math.min(corners.y, other.y),
        x2 = math.max(corners.x, other.x), y2 = math.max(corners.y, other.y) }
    if area.x2 - area.x1 + 1 > MAX_AREA_SIDE or area.y2 - area.y1 + 1 > MAX_AREA_SIDE then return nil end
    return area, corners.z
end

local function placeArea(sec, value, line)
    placeWhere(sec, "area", line)
    local area, z = parseArea(value)
    if not area then
        fail(line, "bad place area '" .. value .. "' (x1,y1,x2,y2,z whole numbers, sides 1 to "
            .. tostring(MAX_AREA_SIDE) .. ")")
    end
    sec.place.area, sec.place.z = area, z
end

local function placeLabel(sec, value, line)
    if utf8Bytes(value) > MAX_PLACE_LABEL_BYTES then
        fail(line, "place label of '" .. sec.id .. "' too long (" .. tostring(MAX_PLACE_LABEL_BYTES)
            .. " bytes of UTF-8 at most)")
    end
    sec.place.label = value
end

local PLACE_KEYS = { at = placeAt, area = placeArea, label = placeLabel }

local function placeOpen(sec, ctx)
    if contains(DISTANCE_LIST, sec.id) then
        fail(sec.line, "place id '" .. sec.id .. "' is reserved (near, far and very_far are distances)")
    end
    if #ctx.places >= MAX_PLACES then
        fail(sec.line, "too many places (" .. tostring(MAX_PLACES) .. " at most)")
    end
    sec.place = { id = sec.id }
end

local function placeKey(sec, key, value, line)
    local reader = PLACE_KEYS[key]
    if not reader then unknownKey(sec, key, line) end
    reader(sec, value, line)
end

local PLACE_REQUIRED = { "label" }

local function placeClose(sec, ctx)
    if not sec.lines.at and not sec.lines.area then
        fail(sec.line, "missing key 'at' or 'area' in " .. title(sec))
    end
    requireKeys(sec, PLACE_REQUIRED)
    ctx.places[#ctx.places + 1] = sec.place
    ctx.placeById[sec.id] = sec.place
end

-- [mission <id>] : cles communes a toute mission ; les autres sont les parametres declares par le gabarit (params).
local function missionType() end
local function missionWeight(m, value, line) m.weight = weight(value, "weight", line) end
local function missionAfter(m, value, line) m.after, m.afterLine = value, line end
local function missionStory(m, value, line, ctx)
    if utf8Bytes(value) > MAX_STORY_BYTES then
        fail(line, "story too long (" .. tostring(MAX_STORY_BYTES) .. " bytes of UTF-8 at most)")
    end
    m.story = param("text", value, line, ctx)
end
-- E20-T08 : scope= de l'enchainement (after=) : par personnage (defaut) ou par equipe.
local function missionScope(m, value, line) m.scope = choice(value, "scope", SCOPE_LIST, line) end
-- E20-T08 : sets_state= : etat de recit de la voix pose a la reussite (un nom, distinct de state= de la tete).
local function missionSetsState(m, value, line)
    if not isName(value) then
        fail(line, "bad sets_state '" .. value
            .. "' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)")
    end
    m.sets_state = value
end

-- drops= : planques de la mission, des points (ADR D05), sans doublon ; identifiants dans l'ordre de la ligne.
local function missionDrops(m, value, line, ctx)
    for _, id in ipairs(splitList(value)) do
        param("place", id, line, ctx)
        if contains(m.drops, id) then fail(line, "duplicate drops entry '" .. id .. "'") end
        m.drops[#m.drops + 1] = id
    end
end

-- E25-T01 (ADR D01) : target= : un lieu commun (point ou zone) -> { kind = 'place', id }, ou une distance de
-- l'appelant (near, far, very_far) -> { kind = <distance> }. Sans la cle : near.
local function missionTarget(m, value, line, ctx)
    if contains(DISTANCE_LIST, value) then
        m.target = { kind = value }
        return
    end
    if not ctx.shared[value] then fail(line, "unknown place '" .. value .. "'") end
    m.target = { kind = "place", id = value }
end

-- E25-T01 (ADR D03) : building= : genre de batiment tire (CA_Sites.KINDS), avec une zone ou une distance seulement.
local function missionBuilding(m, value, line, ctx)
    m.building = choice(value, "building", ctx.buildings, line)
    m.buildingLine = line
end

local MISSION_KEYS = { type = missionType, weight = missionWeight, after = missionAfter, story = missionStory,
    drops = missionDrops, target = missionTarget, building = missionBuilding, scope = missionScope,
    sets_state = missionSetsState }

local function missionKey() end  -- cles connues seulement avec le type : missionResolve
local MISSION_REQUIRED = { "type" }
local function missionClose(sec) requireKeys(sec, MISSION_REQUIRED) end

-- Objectif complet (target et building) ; un point ne prend pas de genre de batiment.
local function missionAim(m, ctx)
    m.target = m.target or { kind = DISTANCE_LIST[1] }
    if m.building then
        local place = m.target.kind == "place" and ctx.shared[m.target.id]
        if place and not place.area then fail(m.buildingLine, "building needs a zone or a distance target") end
        m.target.building = m.building
    end
    m.building, m.buildingLine = nil, nil
end

local function missionResolve(sec, ctx)
    local voiceType = sec.values.type
    local _, template = ctx.rules.template(voiceType)
    if not template then fail(sec.lines.type, "unknown mission type '" .. voiceType .. "'") end
    local declared = type(template.params) == "table" and template.params or {}
    local m = { id = sec.id, type = voiceType, weight = 1, scope = "character", drops = {}, params = {} }
    for _, key in ipairs(sec.keys) do
        local value, line = sec.values[key], sec.lines[key]
        if MISSION_KEYS[key] then
            MISSION_KEYS[key](m, value, line, ctx)
        elseif declared[key] then
            m.params[key] = param(declared[key], value, line, ctx)
        else
            fail(line, "unknown key '" .. key .. "' for mission type '" .. voiceType .. "'")
        end
    end
    -- E25-T01 : un gabarit a planques (declaration dropAccepts du mod commun : deliver, retrieve, item) les exige.
    if template.dropAccepts ~= nil and #m.drops == 0 then
        fail(sec.line, "missing key 'drops' in " .. title(sec))
    end
    missionAim(m, ctx)
    ctx.missions[#ctx.missions + 1] = m
    ctx.missionById[m.id] = m
end

-- after= : une mission de la fiche, sans boucle.
local function missionFinish(ctx)
    for _, m in ipairs(ctx.missions) do
        if m.after and not ctx.missionById[m.after] then
            fail(m.afterLine, "unknown mission '" .. m.after .. "' in after=")
        end
    end
    for _, m in ipairs(ctx.missions) do
        local seen, step = {}, m
        while step and step.after and not seen[step.id] do
            seen[step.id] = true
            step = ctx.missionById[step.after]
            if step == m then fail(m.afterLine, "after= cycle through mission '" .. m.id .. "'") end
        end
    end
    for _, m in ipairs(ctx.missions) do m.afterLine = nil end
end

-- [rewards] : pool= entrees nature:poids ou nature:parametre:poids, dans l'ordre de la fiche ; E25-T01 : cache_place=,
-- point ou une nature qui declare `place` (cache) est laissee, obligatoire avec une telle nature.
local REWARDS_KEYS = { pool = true, cache_place = true }
local REWARDS_REQUIRED = { "pool" }

local function rewardsKey(sec, key, _, line)
    if not REWARDS_KEYS[key] then unknownKey(sec, key, line) end
end

local function rewardsClose(sec) requireKeys(sec, REWARDS_REQUIRED) end

local function rewardsResolve(sec, ctx)
    local line, kinds, seen = sec.lines.pool, ctx.rules.rewards or {}, {}
    local names = {}
    for name in pairs(kinds) do names[#names + 1] = name end
    table.sort(names)
    for _, entry in ipairs(splitList(sec.values.pool)) do
        local parts = split(entry, ":")
        if #parts < 2 or #parts > 3 then
            fail(line, "bad reward '" .. entry .. "' (kind:weight or kind:parameter:weight, e.g. cache:medical:3)")
        end
        local kind = parts[1]
        local def = kinds[kind]
        if not def then
            fail(line, "unknown reward '" .. kind .. "' (expected " .. table.concat(names, ", ") .. ")")
        end
        if def.param and #parts == 2 then
            fail(line, "reward '" .. kind .. "' needs a parameter (kind:parameter:weight)")
        end
        if not def.param and #parts == 3 then
            fail(line, "reward '" .. kind .. "' takes no parameter (kind:weight)")
        end
        local reward = { kind = kind, weight = weight(parts[#parts], "reward weight", line) }
        local key = kind
        if def.param then
            reward.param = param(def.param, parts[2], line, ctx)
            key = kind .. ":" .. parts[2]
        end
        if seen[key] then fail(line, "duplicate reward '" .. key .. "'") end
        seen[key] = true
        if def.place and not sec.values.cache_place then fail(line, kind .. " reward needs cache_place") end
        ctx.rewards[#ctx.rewards + 1] = reward
    end
    if sec.values.cache_place then ctx.cachePlace = pointAt(sec.values.cache_place, sec.lines.cache_place, ctx) end
end

-- [category <id>] : item=Module.Type:quantite (quantite : genre range de RS_PersonaParams), repetable.
local function categoryOpen(sec, ctx)
    if ctx.rules.categories and ctx.rules.categories[sec.id] then
        fail(sec.line, "category '" .. sec.id .. "' already exists in the shared catalogue")
    end
    sec.category = { id = sec.id, items = {} }
end

local CATEGORY_KEYS = { item = true }
local CATEGORY_REQUIRED = { "item" }

local function categoryKey(sec, key, value, line, ctx)
    if not CATEGORY_KEYS[key] then unknownKey(sec, key, line) end
    local itemType, quantity = string.match(value, "^([A-Za-z0-9_]+%.[A-Za-z0-9_]+):([^:]+)$")
    if not itemType then
        fail(line, "bad item '" .. value .. "' (Module.Type:quantity, e.g. Base.Bandage:2-4)")
    end
    for _, item in ipairs(sec.category.items) do
        if item.type == itemType then
            fail(line, "duplicate item '" .. itemType .. "' in " .. title(sec))
        end
    end
    local range = param("range", quantity, line, ctx)
    sec.category.items[#sec.category.items + 1] = { type = itemType, min = range.min, max = range.max }
end

local function categoryClose(sec, ctx)
    requireKeys(sec, CATEGORY_REQUIRED)
    ctx.ownCategories[sec.id] = sec.category
    ctx.categories[sec.id] = sec.category
end

-- [trade] (E20-T07, ADR D07) : troc de la voix. landing (points des lieux communs), arrival (mode d'arrivee inscrit,
-- regles arrivals), every_days (un passage tous les N jours de jeu), hours (fenetre du rendez-vous), delay_hours
-- (facultatif : heures de jeu hors de vue avant l'echange), margin (facultatif : marge la plus basse et la plus
-- haute), item= repetable (Module.Type:quantite ; quantite : fourchette, ou nom d'un groupe ; E22-T12 : poids lu dans
-- le script de l'objet par la regle injectee itemWeight, RS_ItemWeights, type inconnu refuse), group= repetable
-- (nom:total[:sortes] : total tire dans le groupe, au plus `sortes` objets differents), accept= repetable (E23-T06 :
-- ce que la voix accepte en paiement, un objet Module.Type ou le nom d'une categorie, partagee ou de la fiche ; un objet
-- doit avoir une valeur de vente, regle injectee sellValue, CA_TradeValues.sellValue par defaut ; une categorie apporte
-- ses objets qui en ont une, et au moins un). Resolu apres toute la fiche : trade.accepts = liste des types acceptes,
-- dans l'ordre, sans doublon.
local MAX_TRADE_ITEMS = 40
local MAX_TRADE_ACCEPTS = 60
local MAX_EVERY_DAYS = 28
local MAX_DELAY_HOURS = 48
Persona.TRADE_MARGIN = { min = 0.10, max = 0.50 }

-- Nombre positif ecrit en chiffres avec au plus deux decimales, au plus maximum ; sinon erreur.
local function decimal(value, key, line, maximum)
    local whole = string.match(value, "^([0-9]+)$") or string.match(value, "^([0-9]+)%.[0-9][0-9]?$")
    local n = whole and string.len(whole) <= 3 and tonumber(value)
    if not n or n > maximum then
        fail(line, "bad " .. key .. " '" .. value .. "' (number from 0 to " .. tostring(maximum)
            .. ", two decimals at most)")
    end
    return n
end

local function minutesOf(h, m)
    return tonumber(h) * 60 + tonumber(m)
end

-- landing= : rendez-vous du marchand, des points des lieux communs (ADR D05), un tire par passage s'il y en a plusieurs.
local function tradeLanding(trade, value, line, ctx)
    for _, id in ipairs(splitList(value)) do
        local p = pointAt(id, line, ctx)
        for _, other in ipairs(trade.landings) do
            if other.id == id then fail(line, "duplicate landing entry '" .. id .. "'") end
        end
        trade.landings[#trade.landings + 1] = p
    end
end

local function tradeArrival(trade, value, line, ctx)
    local names = {}
    for name in pairs(ctx.rules.arrivals or {}) do names[#names + 1] = name end
    table.sort(names)
    if not (ctx.rules.arrivals or {})[value] then
        fail(line, "unknown arrival '" .. value .. "' (expected " .. table.concat(names, ", ") .. ")")
    end
    trade.arrival = value
end

local function tradeEveryDays(trade, value, line)
    local n = count(value, "every_days", line, MAX_EVERY_DAYS)
    if n < 1 then fail(line, "bad every_days '" .. value .. "' (whole number from 1 to " .. MAX_EVERY_DAYS .. ")") end
    trade.everyDays = n
end

local function tradeHours(trade, value, line)
    local h1, m1, h2, m2 = string.match(value, "^([0-9][0-9]):([0-9][0-9])%-([0-9][0-9]):([0-9][0-9])$")
    if not h1 or tonumber(h1) > 23 or tonumber(h2) > 23 or tonumber(m1) > 59 or tonumber(m2) > 59 then
        fail(line, "bad trade hours '" .. value .. "' (one HH:MM-HH:MM range of the meeting, e.g. 01:00-03:00)")
    end
    local from, to = minutesOf(h1, m1), minutesOf(h2, m2)
    if from == to then fail(line, "empty trade hours '" .. value .. "'") end
    trade.from, trade.hours = from / 60, ((to - from) % 1440) / 60
end

local function tradeDelay(trade, value, line)
    trade.delayHours = decimal(value, "delay_hours", line, MAX_DELAY_HOURS)
end

local function tradeMargin(trade, value, line)
    local low, high = string.match(value, "^([^-]+)%-([^-]+)$")
    local hint = "bad margin '" .. value .. "' (lowest-highest from 0 to 1, e.g. 0.10-0.50)"
    if not low then fail(line, hint) end
    low, high = decimal(trim(low), "margin", line, 1), decimal(trim(high), "margin", line, 1)
    if low > high then fail(line, hint) end
    trade.marginMin, trade.marginMax = low, high
end

local function tradeItem(trade, value, line, ctx)
    local itemType, quantity = string.match(value, "^([A-Za-z0-9_]+%.[A-Za-z0-9_]+):([^:]+)$")
    if not itemType then
        fail(line, "bad trade item '" .. value .. "' (Module.Type:quantity, e.g. Base.Battery:4-12)")
    end
    local kg = ctx.rules.itemWeight and ctx.rules.itemWeight(itemType)
    if type(kg) ~= "number" then fail(line, "unknown trade item '" .. itemType .. "' (no item script of that type)") end
    if #trade.items >= MAX_TRADE_ITEMS then
        fail(line, "too many trade items (" .. tostring(MAX_TRADE_ITEMS) .. " at most)")
    end
    local name = string.match(itemType, "%.(.+)$")
    for _, item in ipairs(trade.items) do
        if string.lower(item.n) == string.lower(name) then fail(line, "duplicate trade item '" .. name .. "'") end
    end
    local item = { n = name, t = itemType, w = kg, line = line }
    if string.match(quantity, "^[a-z][a-z0-9_]*$") then
        item.gr = quantity
    else
        local range = param("range", quantity, line, ctx)
        item.min, item.max = range.min, range.max
    end
    trade.items[#trade.items + 1] = item
end

local function tradeGroup(trade, value, line, ctx)
    local id, total, kinds = string.match(value, "^([a-z][a-z0-9_]*):([0-9%-]+):?([0-9]*)$")
    if not id then fail(line, "bad trade group '" .. value .. "' (name:total[:kinds], e.g. seeds:3-8:4)") end
    if trade.groupById[id] then fail(line, "duplicate trade group '" .. id .. "'") end
    local range = param("range", total, line, ctx)
    local group = { id = id, min = range.min, max = range.max, line = line }
    if kinds ~= "" then
        group.kinds = count(kinds, "group kinds", line, MAX_TRADE_ITEMS)
        if group.kinds < 1 then fail(line, "bad group kinds '" .. kinds .. "' (whole number from 1)") end
    end
    trade.groups[#trade.groups + 1] = group
    trade.groupById[id] = group
end

-- accept= : lu apres toute la fiche (categories de la fiche) ; ici la forme seulement.
local function tradeAccept(trade, value, line)
    if not (string.match(value, "^[A-Za-z0-9_]+%.[A-Za-z0-9_]+$") or string.match(value, "^[a-z][a-z0-9_]*$")) then
        fail(line, "bad trade accept '" .. value .. "' (Module.Type or a category, e.g. Base.MoneyBundle or ammo)")
    end
    for _, e in ipairs(trade.acceptLines) do
        if e.value == value then fail(line, "duplicate trade accept '" .. value .. "'") end
    end
    if #trade.acceptLines >= MAX_TRADE_ACCEPTS then
        fail(line, "too many trade accepts (" .. tostring(MAX_TRADE_ACCEPTS) .. " at most)")
    end
    trade.acceptLines[#trade.acceptLines + 1] = { value = value, line = line }
end

local TRADE_KEYS = { landing = tradeLanding, arrival = tradeArrival, every_days = tradeEveryDays, hours = tradeHours,
    delay_hours = tradeDelay, margin = tradeMargin, item = tradeItem, group = tradeGroup, accept = tradeAccept }

local function tradeOpen(sec)
    sec.trade = { landings = {}, items = {}, groups = {}, groupById = {}, acceptLines = {}, accepts = {},
        marginMin = Persona.TRADE_MARGIN.min,
        marginMax = Persona.TRADE_MARGIN.max }
end

-- landing se lit apres toute la fiche (lieux) ; les autres cles a leur ligne, sauf les references aux groupes.
local function tradeKey(sec, key, value, line, ctx)
    local reader = TRADE_KEYS[key]
    if not reader then unknownKey(sec, key, line) end
    if key == "landing" then return end
    reader(sec.trade, value, line, ctx)
end

local TRADE_REQUIRED = { "landing", "arrival", "every_days", "hours", "item", "accept" }

local function tradeClose(sec)
    requireKeys(sec, TRADE_REQUIRED)
    local trade, used = sec.trade, {}
    for _, item in ipairs(trade.items) do
        if item.gr then
            if not trade.groupById[item.gr] then fail(item.line, "unknown trade group '" .. item.gr .. "'") end
            used[item.gr] = (used[item.gr] or 0) + 1
        end
        item.line = nil
    end
    for _, group in ipairs(trade.groups) do
        if not used[group.id] then fail(group.line, "trade group '" .. group.id .. "' has no item") end
        if group.kinds and group.kinds > used[group.id] then
            fail(group.line, "trade group '" .. group.id .. "' has fewer items than its kinds")
        end
        group.line = nil
    end
end

-- Types acceptes en paiement (accept=) : objets a valeur de vente, categories resolues en leurs objets qui en ont une.
local function tradeAccepts(trade, ctx)
    -- Bareme charge seulement pour une fiche qui troque (bancs sans le mod commun).
    local sell, seen = ctx.rules.sellValue or require("CoreAI/CA_TradeValues").sellValue, {}
    local function add(itemType)
        if not seen[itemType] then
            seen[itemType] = true
            trade.accepts[#trade.accepts + 1] = itemType
        end
    end
    for _, e in ipairs(trade.acceptLines) do
        if string.find(e.value, ".", 1, true) then
            if sell(e.value) <= 0 then
                fail(e.line, "trade accept '" .. e.value .. "' has no trade value (an item a trader cannot take)")
            end
            add(e.value)
        else
            local category = ctx.categories[e.value]
            if not category then fail(e.line, "unknown category '" .. e.value .. "' in trade accept") end
            local any = false
            for _, item in ipairs(category.items) do
                if sell(item.type) > 0 then
                    add(item.type)
                    any = true
                end
            end
            if not any then fail(e.line, "category '" .. e.value .. "' has no item with a trade value") end
        end
    end
    trade.acceptLines = nil
end

local function tradeResolve(sec, ctx)
    tradeLanding(sec.trade, sec.values.landing, sec.lines.landing, ctx)
    tradeAccepts(sec.trade, ctx)
    ctx.trade, ctx.tradeLine = sec.trade, sec.line
end

-- [note] (E20-T11) : note de frequence de la voix trouvee dans le butin (RS_Notes, RS_NotesServer). item (objet du
-- document, Module.Type d'un script d'objets dont OnCreate est RadioSurvivorNotes.onCreate ; plusieurs voix peuvent
-- partager un objet), key (racine des traductions Print_Media_<module>_<key>_title et _info,
-- Print_Text_<module>_<key>_info), loot= repetable (liste procedurale vanilla:poids), glovebox= repetable (liste
-- VehicleDistributions:poids) : listes a theme, en plus du socle commun de toute note (RS_NotesBase, E24-T03).
-- E22-T07 : ou text= repetable (une ligne de la page chacune, %1 = frequence) a la place de item et key : la note est
-- alors la note manuscrite generique du mod (RS_Notes.GENERIC_ITEM), qui porte ce texte.
local MAX_NOTE_LISTS = 16
local MAX_LOOT_WEIGHT = 100

local function noteOpen(sec)
    sec.note = { loot = {}, glovebox = {}, text = {} }
end

local function noteList(note, key, value, line)
    local list, w = string.match(value, "^([A-Za-z0-9_]+):([0-9.]+)$")
    if not list then
        fail(line, "bad " .. key .. " '" .. value .. "' (list:weight, e.g. OfficeDesk:4)")
    end
    local n = decimal(w, key .. " weight", line, MAX_LOOT_WEIGHT)
    if n <= 0 then fail(line, "bad " .. key .. " weight '" .. w .. "' (above 0)") end
    local lists = note[key]
    for _, e in ipairs(lists) do
        if e.list == list then fail(line, "duplicate " .. key .. " list '" .. list .. "'") end
    end
    if #lists >= MAX_NOTE_LISTS then fail(line, "too many " .. key .. " lists (" .. MAX_NOTE_LISTS .. " at most)") end
    lists[#lists + 1] = { list = list, weight = n }
end

local function noteItem(note, _, value, line)
    local module, itemType = string.match(value, "^([A-Za-z0-9_]+)%.([A-Za-z0-9_]+)$")
    if not module then fail(line, "bad note item '" .. value .. "' (Module.Type, e.g. RadioSurvivor.NoteWalt)") end
    note.item, note.module, note.type = value, module, itemType
end

local function noteTextKey(note, _, value, line)
    if not string.match(value, "^[A-Za-z0-9_]+$") then
        fail(line, "bad note key '" .. value .. "' (A to Z, a to z, 0 to 9 and _)")
    end
    note.key = value
end

local function noteText(note, _, value, line)
    if #note.text >= MAX_NOTE_LINES then
        fail(line, "too many note text lines (" .. tostring(MAX_NOTE_LINES) .. " at most)")
    end
    note.text[#note.text + 1] = writtenText(value, "note text", line, MAX_NOTE_LINE_BYTES)
end

local NOTE_KEYS = { item = noteItem, key = noteTextKey, loot = noteList, glovebox = noteList, text = noteText }

local function noteKey(sec, key, value, line)
    local reader = NOTE_KEYS[key]
    if not reader then unknownKey(sec, key, line) end
    reader(sec.note, key, value, line)
end

-- Aucune cle toujours obligatoire : text, ou bien item et key (noteClose).
local NOTE_REQUIRED = {}
local NOTE_OWN_ITEM = { "item", "key" }

-- Vrai si une ligne du texte porte %1 (la frequence).
local function showsFrequency(text)
    for _, line in ipairs(text) do
        if string.find(line, "%1", 1, true) then return true end
    end
    return false
end

local function noteClose(sec, ctx)
    local note, lines = sec.note, sec.lines
    if #note.text > 0 then
        if lines.item or lines.key then
            fail(lines.item or lines.key, "item and key cannot be used with text in [note] (text goes on the "
                .. "handwritten note of the mod)")
        end
        if not showsFrequency(note.text) then
            fail(sec.line, "note text needs %1 (the frequency) on one of its lines")
        end
    elseif lines.item == nil and lines.key == nil then
        fail(sec.line, "missing key 'text' in [note] (or item and key)")
    else
        requireKeys(sec, NOTE_OWN_ITEM)
    end
    ctx.note = note
end

-- keys, required, choices (listes fermees de valeurs par cle) et ruleChoices (cle -> champ des regles dont les noms
-- sont les valeurs admises) ne servent qu'a Persona.grammar (E22-T01) : les memes tables que les lecteurs ci-dessus.
local SECTIONS = {
    place = { rank = 1, example = "mill", open = placeOpen, key = placeKey, close = placeClose,
        keys = PLACE_KEYS, required = PLACE_REQUIRED },
    mission = { rank = 2, example = "meds", key = missionKey, close = missionClose, resolve = missionResolve,
        finish = missionFinish, keys = MISSION_KEYS, required = MISSION_REQUIRED,
        choices = { scope = SCOPE_LIST }, ruleChoices = { building = "buildings" } },
    rewards = { rank = 3, key = rewardsKey, close = rewardsClose, resolve = rewardsResolve,
        keys = REWARDS_KEYS, required = REWARDS_REQUIRED },
    category = { rank = 4, example = "snacks", repeatable = { item = true }, open = categoryOpen, key = categoryKey,
        close = categoryClose, keys = CATEGORY_KEYS, required = CATEGORY_REQUIRED },
    trade = { rank = 5, repeatable = { item = true, group = true, accept = true }, open = tradeOpen, key = tradeKey,
        close = tradeClose, resolve = tradeResolve, keys = TRADE_KEYS, required = TRADE_REQUIRED,
        ruleChoices = { arrival = "arrivals" } },
    note = { rank = 6, repeatable = { loot = true, glovebox = true, text = true }, open = noteOpen, key = noteKey,
        close = noteClose, keys = NOTE_KEYS, required = NOTE_REQUIRED },
}

-- Noms de SECTIONS (ou d'un sous-ensemble) dans l'ordre de leur rang.
local function ranked(names)
    table.sort(names, function(a, b) return SECTIONS[a].rank < SECTIONS[b].rank end)
    return names
end

-- En-tete « [nom] » ou « [nom id] » (espaces permis autour) -> nom, id ("" sans id) ; nil si la ligne n'en est pas un.
local function header(text)
    return string.match(text, "^%[[ \t]*([^ \t%]]*)[ \t]*(.-)[ \t]*%]$")
end

-- Ligne cle=valeur -> cle, valeur (cle de forme [a-z_]+, ou a.b si dotted). separator : ligne qui peut aussi venir
-- ici, dite par le message d'une ligne sans = ([prompt] dans une fiche, [place <id>] dans le fichier des lieux).
local function keyValue(text, line, dotted, separator)
    local eq = string.find(text, "=", 1, true)
    if not eq then fail(line, "expected key=value or " .. separator) end
    local key, value = trim(string.sub(text, 1, eq - 1)), trim(string.sub(text, eq + 1))
    if not string.match(key, "^[a-z_]+$") and not (dotted and string.match(key, "^[a-z_]+%.[a-z_]+$")) then
        fail(line, "bad key '" .. key .. "'")
    end
    return key, value
end

local function emptyValue(key, value, line)
    if value == "" then fail(line, "empty value for key '" .. key .. "'") end
end

local function newContext(rules, separator)
    local categories = {}
    for id, category in pairs(rules.categories or {}) do categories[id] = category end
    -- shared : lieux communs que la fiche peut nommer (rules.places, aucun sans la regle) ; places et placeById : lieux
    -- lus dans le fichier commun lui-meme (parsePlaces).
    return { rules = rules, separator = separator or Persona.SEPARATOR, sections = {}, firstLine = {}, places = {},
        placeById = {}, shared = rules.places or {}, buildings = rules.buildings or {}, missions = {}, missionById = {},
        rewards = {}, ownCategories = {}, categories = categories }
end

-- Ouvre la section de l'en-tete (allowed : noms permis ; expected : texte du message d'une section inconnue).
local function openSection(name, id, line, ctx, allowed, expected)
    local handler = allowed[name] and SECTIONS[name]
    if not handler then fail(line, "unknown section '" .. name .. "' (expected " .. expected .. ")") end
    if handler.example and id == "" then
        fail(line, "section [" .. name .. "] needs an id, e.g. [" .. name .. " " .. handler.example .. "]")
    end
    if not handler.example and id ~= "" then fail(line, "section [" .. name .. "] takes no id") end
    if id ~= "" and not isSectionId(id) then
        fail(line, "bad " .. name .. " id '" .. id .. "' (a to z, 0 to 9 and _, 32 characters at most)")
    end
    local first = ctx.firstLine[name] or {}
    ctx.firstLine[name] = first
    if first[id] then
        if id == "" then
            fail(line, "duplicate section [" .. name .. "] (first set on line " .. tostring(first[id]) .. ")")
        end
        fail(line, "duplicate " .. name .. " '" .. id .. "' (first set on line " .. tostring(first[id]) .. ")")
    end
    first[id] = line
    local sec = { name = name, id = id ~= "" and id or nil, line = line, values = {}, lines = {}, keys = {} }
    if handler.open then handler.open(sec, ctx) end
    local list = ctx.sections[name] or {}
    ctx.sections[name] = list
    list[#list + 1] = sec
    return sec
end

local function sectionLine(sec, text, line, ctx)
    local handler = SECTIONS[sec.name]
    local key, value = keyValue(text, line, false, ctx.separator)
    if sec.lines[key] and not (handler.repeatable and handler.repeatable[key]) then
        fail(line, "duplicate key '" .. key .. "' in " .. title(sec) .. " (first set on line "
            .. tostring(sec.lines[key]) .. ")")
    end
    emptyValue(key, value, line)
    if not sec.lines[key] then sec.keys[#sec.keys + 1] = key end
    sec.values[key], sec.lines[key] = value, line
    handler.key(sec, key, value, line, ctx)
end

local function closeSection(sec, ctx)
    if sec then SECTIONS[sec.name].close(sec, ctx) end
end

-- Resolutions apres toute la fiche (references entre sections), dans l'ordre des rangs.
local function resolveSections(ctx)
    local names = {}
    for name in pairs(SECTIONS) do names[#names + 1] = name end
    for _, name in ipairs(ranked(names)) do
        local handler = SECTIONS[name]
        if handler.resolve then
            for _, sec in ipairs(ctx.sections[name] or {}) do handler.resolve(sec, ctx) end
        end
        if handler.finish then handler.finish(ctx) end
    end
end

local function checkRaw(raw, number)
    if number == 1 and startsWith(raw, BOM) then
        fail(1, "file starts with a byte order mark (save it as UTF-8 without BOM)")
    end
    if string.find(raw, REPLACEMENT, 1, true) then
        fail(number, "invalid UTF-8 (save the file as UTF-8)")
    end
end

-- E25-T01 : plus de [place] dans une fiche (fichier commun _places.txt, parsePlaces).
local SHEET_SECTIONS = { mission = true, rewards = true, category = true, trade = true, note = true }
local SHEET_EXPECTED = (function()
    local names = {}
    for name in pairs(SHEET_SECTIONS) do names[#names + 1] = name end
    return table.concat(ranked(names), ", ") .. " or prompt"
end)()

local function headLine(values, seen, budgetLines, text, number, ctx)
    local key, value = keyValue(text, number, true, Persona.SEPARATOR)
    local action = nil
    if startsWith(key, BUDGET_PREFIX) then
        action = string.sub(key, string.len(BUDGET_PREFIX) + 1)
        if not ACTIONS[action] then
            fail(number, "unknown action '" .. action .. "' in key '" .. key .. "'")
        end
    elseif not HEAD[key] then
        fail(number, "unknown key '" .. key .. "'")
    end
    if seen[key] then
        fail(number, "duplicate key '" .. key .. "' (first set on line " .. tostring(seen[key]) .. ")")
    end
    seen[key] = number
    emptyValue(key, value, number)
    if action then
        values.budgets[action] = count(value, key, number)
        budgetLines[#budgetLines + 1] = { action = action, line = number }
    else
        HEAD[key](values, value, number, ctx)
    end
end

local function parse(lines, expectedId, rules)
    local values = { budgets = {} }
    local ctx = newContext(rules or NO_RULES)
    local seen = {}
    local budgetLines = {}
    local separator = nil
    local current = nil
    for number, raw in ipairs(lines) do
        checkRaw(raw, number)
        local text = trim(raw)
        -- Apres le separateur : texte libre, rien a controler de plus.
        if not separator and text ~= "" and string.sub(text, 1, 1) ~= "#" then
            local name, id = header(text)
            if name == "prompt" and id == "" then
                closeSection(current, ctx)
                current, separator = nil, number
            elseif name then
                closeSection(current, ctx)
                current = openSection(name, id, number, ctx, SHEET_SECTIONS, SHEET_EXPECTED)
            elseif current then
                sectionLine(current, text, number, ctx)
            else
                headLine(values, seen, budgetLines, text, number, ctx)
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
    if values.radio == nil and values.frequency == nil then
        fail(separator, "missing key 'radio' or 'frequency'")
    end
    if values.radio ~= nil and values.frequency ~= nil then
        fail(math.max(seen.radio, seen.frequency),
            "radio and frequency cannot be used together (a radio level to draw a free frequency, or one fixed frequency)")
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
    if values.call ~= nil and values.call_text ~= nil then
        fail(math.max(seen.call, seen.call_text),
            "call and call_text cannot be used together (text written in the sheet or translation key)")
    end
    if (values.call_one_in or 0) > 0 and values.call == nil and values.call_text == nil then
        fail(seen.call_one_in, "call_one_in needs a call or call_text line")
    end
    local allowed = values.actions or { "say" }
    for _, b in ipairs(budgetLines) do
        if not contains(allowed, b.action) then
            fail(b.line, BUDGET_PREFIX .. b.action .. " set but action '" .. b.action .. "' is not in actions")
        end
    end
    resolveSections(ctx)
    -- Le troc (E20-T07) : l'action propose_trade et la section [trade] vont ensemble.
    if contains(allowed, "propose_trade") and not ctx.trade then
        fail(seen.actions, "action propose_trade needs a [trade] section")
    end
    if ctx.trade and not contains(allowed, "propose_trade") then
        fail(ctx.tradeLine, "section [trade] needs the action propose_trade")
    end

    return {
        -- frequency : kHz fixes ou nil (tiree dans la zone de radio) ; radio : ecrite, ou deduite de frequency.
        format = values.format, id = values.id, name = values.name, frequency = values.frequency,
        radio = values.radio or Levels.levelOf(values.frequency),
        prompt = table.concat(body, "\n"), language = values.language or "en",
        listen = values.listen or {}, location = location, coords = values.coords,
        -- E25-T01 : reperes (marks=, lieux communs dans leur ordre) ; places : lieux communs en service a la lecture
        -- (id -> lieu), table de resolution des identifiants nommes par la fiche (Persona.placeOf) ; cachePlace : point
        -- de cache_place= de [rewards].
        marks = values.marks or {}, places = ctx.shared, cachePlace = ctx.cachePlace, actions = allowed,
        budget = values.budget or 0, budgets = values.budgets, call_one_in = values.call_one_in or 0,
        call_text = values.call_text or "", call = values.call or "", state = values.state or "active",
        shares = values.shares or {},
        missions = ctx.missions, rewards = ctx.rewards, categories = ctx.ownCategories, trade = ctx.trade,
        note = ctx.note,
    }
end

-- Catalogue partage (personas/_categories.txt) : sections [category <id>] seulement.
local CATALOGUE_SECTIONS = { category = true }

local function parseCatalogue(lines)
    local ctx = newContext(NO_RULES)
    local current = nil
    for number, raw in ipairs(lines) do
        checkRaw(raw, number)
        local text = trim(raw)
        if text ~= "" and string.sub(text, 1, 1) ~= "#" then
            local name, id = header(text)
            if name then
                closeSection(current, ctx)
                current = openSection(name, id, number, ctx, CATALOGUE_SECTIONS, "category")
            elseif current then
                sectionLine(current, text, number, ctx)
            else
                fail(number, "expected [category <id>]")
            end
        end
    end
    closeSection(current, ctx)
    return ctx.ownCategories
end

-- E25-T01 : fichier commun des lieux (personas/_places.txt) : une tete format=1, puis des sections [place <id>]
-- seulement. Tete absente : refus a la ligne de la premiere section (a la derniere ligne sans section).
local PLACES_FILE_SECTIONS = { place = true }
local PLACES_FILE_HEAD = { format = headFormat }

local function parsePlaces(lines)
    local ctx = newContext(NO_RULES, Persona.PLACES_SEPARATOR)
    local values, seen, current, firstSection = {}, {}, nil, nil
    for number, raw in ipairs(lines) do
        checkRaw(raw, number)
        local text = trim(raw)
        if text ~= "" and string.sub(text, 1, 1) ~= "#" then
            local name, id = header(text)
            if name then
                closeSection(current, ctx)
                firstSection = firstSection or number
                current = openSection(name, id, number, ctx, PLACES_FILE_SECTIONS, "place")
            elseif current then
                sectionLine(current, text, number, ctx)
            else
                local key, value = keyValue(text, number, false, Persona.PLACES_SEPARATOR)
                if not PLACES_FILE_HEAD[key] then fail(number, "unknown key '" .. key .. "'") end
                if seen[key] then
                    fail(number, "duplicate key '" .. key .. "' (first set on line " .. tostring(seen[key]) .. ")")
                end
                seen[key] = number
                emptyValue(key, value, number)
                PLACES_FILE_HEAD[key](values, value, number)
            end
        end
    end
    closeSection(current, ctx)
    if values.format == nil then fail(firstSection or math.max(#lines, 1), "missing key 'format'") end
    return ctx.placeById
end

-- Erreur de fiche -> nil, « line N: raison » ; toute autre erreur est une erreur de programmation, relevee telle quelle.
local function guarded(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    if type(result) == "table" and result.rsPersonaLine then
        return nil, "line " .. tostring(result.rsPersonaLine) .. ": " .. result.reason
    end
    error(result, 0) -- erreur de programmation : ne pas la deguiser en fiche refusee
end

-- Fiche donnee en lignes (table de chaines, comme getFileReader les rend). expectedId : nom du fichier sans
-- « .txt », ou nil. rules : regles du serveur (RS_Personas.rules), ou nil (aucun gabarit ni recompense ni
-- categorie : une fiche sans section [mission], [rewards] ni [category]). Rend la fiche, ou nil et « line N: raison ».
function Persona.parseLines(lines, expectedId, rules)
    return guarded(parse, lines, expectedId, rules)
end

-- Catalogue de categories en lignes -> table id -> { id, items = { { type, min, max } } }, ou nil et « line N: raison ».
function Persona.parseCatalogue(lines)
    return guarded(parseCatalogue, lines)
end

-- E25-T01 : fichier commun des lieux en lignes -> table id -> lieu (point { id, label, x, y, z } ou zone { id, label,
-- z, area = { x1, y1, x2, y2 } }), ou nil et « line N: raison ».
function Persona.parsePlaces(lines)
    return guarded(parsePlaces, lines)
end

-- Fichier sous Zomboid\Lua (chemin relatif, ex. « batman_RadioSurvivor/personas/walt.txt »). Son id doit etre
-- le nom du fichier sans « .txt ».
function Persona.readFile(path, rules)
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
    return Persona.parseLines(lines, stem, rules)
end

-- E22-T01 (atelier des voix, ADR D03) : ce qu'une fiche peut contenir, lu par tools/gen_atelier_catalog.py (catalogue
-- de l'atelier). Construit depuis les tables memes du lecteur (rien n'est redit) : tete (cles, obligatoires,
-- repetables, prefixe des budgets, listes fermees) et chaque section de SECTIONS (cles, obligatoires, repetables,
-- listes fermees, identifiant ou non). Copies triees. rules (RS_Personas.rules, ou nil) donne les listes fermees par
-- un registre (ruleChoices : modes d'arrivee) ; les cles des [mission] declarees par un gabarit (params) et les natures
-- de recompense restent dans leurs registres.
local function sortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

local function copyChoices(choices)
    local out = {}
    for key, list in pairs(choices or {}) do out[key] = copyList(list) end
    return out
end

-- Noms admis d'un champ des regles : une liste (dans son ordre) ou les cles d'une table (triees).
local function ruleNames(value)
    if type(value) == "table" and value[1] ~= nil then return copyList(value) end
    return sortedKeys(value)
end

-- Grammaire d'une section de SECTIONS.
local function sectionGrammar(s, rules)
    local choices = copyChoices(s.choices)
    for key, field in pairs(s.ruleChoices or {}) do choices[key] = ruleNames(rules[field]) end
    return { rank = s.rank, hasId = s.example ~= nil, keys = sortedKeys(s.keys), required = copyList(s.required),
        repeatable = sortedKeys(s.repeatable), choices = choices }
end

-- E25-T01 : sections : celles d'une fiche ; places : le fichier commun des lieux (tete format=, sections [place],
-- une cle at ou area obligatoire, MAX_PLACES lieux) ; maxMarks : reperes d'une fiche ; distances : objectifs tires
-- (target=, en plus d'un lieu).
function Persona.grammar(rules)
    rules = rules or NO_RULES
    local sections = {}
    for name in pairs(SHEET_SECTIONS) do sections[name] = sectionGrammar(SECTIONS[name], rules) end
    local places = sectionGrammar(SECTIONS.place, rules)
    places.oneOf = { "at", "area" }
    places.maxAreaSide, places.maxLabelBytes = MAX_AREA_SIDE, MAX_PLACE_LABEL_BYTES
    return {
        format = Persona.FORMAT, separator = Persona.SEPARATOR, maxPlaces = MAX_PLACES, maxMarks = MAX_MARKS,
        distances = copyList(DISTANCE_LIST),
        head = { keys = sortedKeys(HEAD), required = copyList(REQUIRED),
            budgetPrefix = BUDGET_PREFIX, choices = copyChoices({ actions = ACTION_LIST, radio = RADIO_LIST,
                location = LOCATION_LIST, state = STATE_LIST }) },
        sections = sections,
        places = places,
    }
end

-- E25-T01 : lieu commun d'identifiant id tel que la fiche l'a lu (point ou zone), ou nil. Les identifiants nommes par
-- une fiche valide (target=, drops=, points=) existent toujours dans sheet.places.
function Persona.placeOf(sheet, id)
    local places = type(sheet) == "table" and type(sheet.places) == "table" and sheet.places or nil
    return places and type(id) == "string" and places[id] or nil
end

return Persona
