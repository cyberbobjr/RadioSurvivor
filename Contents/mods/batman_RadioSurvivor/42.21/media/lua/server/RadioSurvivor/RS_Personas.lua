-- Radio Survivor : fiches des voix côté autorité (E05-T02) : installation des fiches livrées, relecture à chaud,
-- une chaîne radio dynamique par fréquence servie, conflits de fréquences.
--
-- Dossier de travail : Zomboid/Lua/batman_RadioSurvivor/personas/<id>.txt sur la machine qui exécute le serveur
-- (ou la partie solo). Format : docs/specifications-techniques/persona-format.md, lecteur RS_Persona.lua.
--
-- Fiches livrées : dossier « personas » de la variante du mod (42.21/personas/, hors de media/), lu par
-- getModFileReader / listFilesInModDirectory (LuaManager.java:4931-4998, 42.21.0). Seul exemplaire du dépôt
-- (E05-T10) : le pont les lit aussi là pour ses tests et son mode --test ; en jeu, il lit le dossier de travail.
-- Une fiche livrée absente est copiée ; une fiche installée que l'admin n'a pas modifiée est remplacée par la
-- version livrée quand celle-ci change (E05-T11, empreintes : section « Installation » ci-dessous) ; une fiche
-- modifiée par l'admin, ou une fiche sans équivalent livré, n'est jamais écrasée.
--
-- Relecture : toutes les RELOAD_MS millisecondes réelles (OnTick de RadioSurvivor_Server.lua) et à chaque
-- chargement du monde (OnLoadRadioScripts). Seuls les fichiers dont le texte a changé sont relus.
--   - fiche invalide : refusée et journalisée avec sa ligne (une fois par contenu) ; la dernière version valide
--     de la même voix reste en service ;
--   - fichier retiré, ou vidé (0 octet : Lua ne peut supprimer aucun fichier) : voix retirée, chaînes retirées ;
--   - état : active = chaîne et réponses ; silent = chaîne gardée (la voix écoute, sa fréquence reste réservée)
--     mais aucune réponse ni appel ; gone et dead = aucune chaîne, fréquence libérée ;
--   - conflit entre fiches : la voix chargée la première dans cette session garde la fréquence (au premier
--     chargement, ordre alphabétique des fichiers) ; l'autre voix perd seulement cette fréquence, journalisé ;
--   - fréquence prise par une chaîne du jeu ou d'un autre mod (AddChannel refusé) : journalisé, réessayé à
--     chaque relecture ;
--   - fréquence modifiée : une chaîne n'a pas de mutateur de fréquence (RadioChannel.java:45-65) ; l'ancienne
--     est retirée (RadioScriptManager:RemoveChannel, RadioScriptManager.java:105-110) et une nouvelle est créée
--     (AddChannel hors OnLoadRadioScripts : base radio-dynamic.md). Une diffusion en cours sur l'ancienne
--     fréquence est perdue (une diffusion n'est jamais sauvegardée).
--
-- Fréquence tirée au hasard (E05-T07, E24-T01) : une fiche radio=<niveau> reçoit une fréquence libre de la zone de
-- ce niveau (RS_RadioLevels), tirée à la première installation d'une partie neuve, puis mémorisée dans un fichier
-- serveur propre à la partie (jamais en ModData globale, lisible par les clients) ; une fiche frequency= garde sa
-- fréquence fixe. Détails : section « Tirage » ci-dessous et docs/specifications-techniques/persona-format.md.
-- Seul l'ASCII est utilisé dans le code (littéraux non ASCII changés en U+FFFD par le lexeur Kahlua).
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Persona = require "RadioSurvivor/RS_Persona"
local Codec = require "CoreAI/CA_Codec"
local Levels = require "RadioSurvivor/RS_RadioLevels"

local Personas = {}

Personas.MOD_ID = "batman_RadioSurvivor"
Personas.DIR = "batman_RadioSurvivor/personas"
Personas.BUNDLED_DIR = "personas"
-- Fiches livrées attendues si la liste du dossier du mod est vide (variante du mod mal installée).
Personas.BUNDLED_FALLBACK = { "walt.txt" }
Personas.RELOAD_MS = 30000
-- Voix d'origine : première de heldFrequencies (diagnostic). Depuis E05-T08, plus de fréquence par défaut pour un
-- client qui n'envoie pas la sienne ; toutes les voix répondent sur leurs fréquences (routage E05-T03).
Personas.MAIN_VOICE = "walt"
Personas.CHANNEL_PREFIX = Const.VOICE_CHANNEL_PREFIX
-- Tirage (E05-T07, E24-T01) : fichier de la partie, en-tête, écart minimal entre deux fréquences de voix différentes.
Personas.MEMORY_PREFIX = "batman_RadioSurvivor/frequencies-"
Personas.MEMORY_HEADER = "RSFREQ2"
Personas.MIN_GAP_KHZ = 1000
-- Empreintes des fiches installées (E05-T11) : hors du dossier des fiches (un *.txt y serait lu comme une voix),
-- extension admise par getFileWriter (ini, cfg, txt, log, json : base kahlua-lua.md).
Personas.FINGERPRINTS = "batman_RadioSurvivor/personas-fingerprints.txt"
Personas.FINGERPRINTS_HEADER = "RSFP1"
-- Catalogue partagé des catégories d'objets (E20-T03, ADR D04) : livré dans le dossier des fiches du mod, lu là (jamais
-- copié dans le dossier de travail), avant les fiches ; une fiche y ajoute ses catégories propres.
Personas.CATALOGUE = "_categories.txt"
-- Lieux communs à toutes les voix (E25-T01, ADR lieux communs D02, D06) : livrés dans le dossier des fiches du mod,
-- installés et mis à jour dans le dossier de travail comme une fiche livrée (empreintes), relus avec les fiches ; la
-- copie de travail fait foi (l'atelier l'édite). Nom en « _ » : jamais une voix.
Personas.PLACES = "_places.txt"
-- Empreintes (Personas.fingerprint) de toutes les versions livrées de chaque fiche, la version actuelle comprise :
-- reconnaissent une fiche non modifiée installée avant le fichier d'empreintes (E05-T02 à E05-T10). Versions des
-- commits 09d7474 et 24832ea (fréquences fixes ; Walt identique dans les deux), 486b21e (plages, E05-T07), puis
-- E05-T10, E05-T05, E20-T03, E20-T07, E20-T10, E20-T11 ([note] des fiches), E22-T12 (stock sans poids), E22-T14 (sans
-- knows, ignores ni secret), E23-T06, E24-T01 (radio=<niveau> a la place des plages), E25-T01 (lieux communs),
-- E27-T02 ([help]). Toute
-- nouvelle version livrée d'une fiche ajoute ici son empreinte (banc tests/radiosurvivor/test_personas_server.py) ; une fiche
-- livrée après E05-T11 (marchands des villes, E20-T11 ; lieux communs _places.txt, E25-T01) n'a jamais été installée
-- sans le fichier d'empreintes : aucune entrée.
Personas.KNOWN_DELIVERED = {
    walt = { "2105682694", "2759756800", "213942039", "1586801598", "2833011528", "1923829937",   -- E22-T14
        "4196879131",   -- E24-T01 : radio=<niveau>
        "1334134519" },   -- E24-T03 : socle commun des notes, sans corpse=
    darlene = { "611497886", "1134557996", "2120896689", "3998911546", "3957645400",
        "1182033778", "674887514", "2957274911", "3572312285",   -- E22-T14 : sans knows, ignores ni secret
        "3580043489",   -- E24-T01 : radio=<niveau>
        "1476664509",   -- E24-T03 : socle commun des notes, sans corpse=
        "1469846348",   -- E25-T01 : lieux communs (marks=, cache_place=)
        "536756451" },   -- E27-T02 : aide aux recettes [help]
    cody = { "3131466986", "673421833", "4032160620", "318842949", "1196981398",
        "1976566616", "1464760889", "2238673311",   -- E22-T14 : sans knows, ignores ni secret
        "3427747601",   -- E24-T01 : radio=<niveau>
        "69681901",   -- E24-T03 : socle commun des notes, sans corpse=
        "2025292335",   -- E25-T01 : lieux communs (marks=, drops=, cache_place=)
        "2033170993" },   -- E27-T02 : aide aux recettes [help]
    whitaker = { "4044533006", "3352221633", "2075828338", "1570277033",   -- E22-T14
        "3237976040" },   -- E24-T01 : radio=<niveau>
    nightowl = { "4175146858", "225312038", "1263236001", "326850688",   -- E22-T14
        "2694918921",   -- E24-T01 : radio=<niveau>
        "1281699557" },   -- E24-T03 : socle commun des notes, sans corpse=
    gus = { "2508366732", "2733824589", "2930912175", "1078646290", "1260582370", "3810027509", "4079538633",
        "3516644979", "78816791",   -- E22-T14 : sans knows, ignores ni secret
        "2872044854",              -- E23-T06 : accept=, troc par listes
        "3627338360",              -- E24-T01 : radio=<niveau>
        "3160852052",   -- E24-T03 : socle commun des notes, sans corpse=
        "923359829" },   -- E25-T01 : ponton dans les lieux communs
}

local function fresh()
    return {
        voices = {},      -- id -> { sheet, rank, served = { kHz... } }
        rank = 0,
        files = {},       -- id -> texte lu au dernier passage (valide ou non)
        places = {},      -- lieux communs en service (id -> lieu), dernière version valide de _places.txt
        placesText = nil, -- texte de _places.txt lu au dernier passage (valide ou non), "" absent ou vide
        channels = {},    -- kHz -> { id, uuid } : chaînes créées par ce module dans le gestionnaire courant
        warned = {},      -- clé -> true : avertissements de conflit ou de refus déjà écrits
        installed = false,
        nextReloadMs = 0,
        newGame = false,  -- monde neuf (OnLoadRadioScripts) : le fichier de tirage d'un ancien monde est ignoré
        draws = nil,      -- id -> { level, khz } : tirages de la partie (nil = fichier pas encore lu)
    }
end

local state = fresh()

-- Pour les tests : état interne (lecture seule).
function Personas.state()
    return state
end

local function log(msg)
    Const.log("personas: " .. msg)
end

local function javaList(list)
    local out = {}
    if list == nil then return out end
    for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    return out
end

-- Vrai pour un nom de fiche de voix : « *.txt », sauf un nom qui commence par « _ » (CATALOGUE, PLACES).
function Personas.isSheetName(name)
    name = tostring(name)
    return string.len(name) > 4 and string.sub(name, -4) == ".txt" and string.sub(name, 1, 1) ~= "_"
end

-- Noms de fiches de voix triés.
local function sheetNames(names)
    local out = {}
    for _, name in ipairs(names) do
        if Personas.isSheetName(name) then out[#out + 1] = tostring(name) end
    end
    table.sort(out)
    return out
end

local function readLines(reader)
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Installation des fiches livrées --------------------------------------------------------------

-- Empreintes (E05-T11). Empreinte d'une fiche : Adler-32 (CA_Codec.checksum, décimal) de ses octets UTF-8, lignes
-- rejointes par "\n" telles que readLine les rend : indépendante des fins de ligne, égale pour la fiche livrée et
-- pour sa copie (écrite ligne par ligne). Fichier FINGERPRINTS : en-tête FINGERPRINTS_HEADER puis une ligne
-- « nom.txt empreinte » par fiche livrée installée, l'empreinte du texte écrit par le serveur.
--   - fiche absente : copiée, empreinte mémorisée ;
--   - fiche identique à la version livrée : rien (empreinte mémorisée si elle manquait) ;
--   - fiche différente, empreinte égale à celle mémorisée (non modifiée depuis sa copie) : remplacée par la version
--     livrée, journalisé ; empreinte différente : gardée, avertissement ;
--   - fiche sans empreinte mémorisée (installée avant E05-T11, ou fichier d'empreintes absent ou vidé) : non
--     modifiée si son empreinte est celle d'une version livrée connue (KNOWN_DELIVERED), sinon modifiée ;
--   - fichier d'empreintes abîmé : ignoré prudemment, aucune fiche remplacée et le fichier n'est pas réécrit
--     (l'admin le vide pour revenir aux versions livrées connues) ; les fiches absentes sont copiées quand même ;
--   - fiche de l'admin sans équivalent livré : jamais lue ici.

function Personas.fingerprint(lines)
    return Codec.checksum(table.concat(lines, "\n"))
end

local function isKnownDelivered(id, fingerprint)
    return contains(Personas.KNOWN_DELIVERED[id] or {}, fingerprint)
end

-- Fichier d'empreintes -> table nom -> empreinte, puis nil ou la raison d'un fichier abîmé. Absent ou vide : table
-- vide.
local function readFingerprints()
    local record = {}
    local reader = getFileReader(Personas.FINGERPRINTS, false)
    if not reader then return record, nil end
    local lines = readLines(reader)
    if #lines == 0 then return record, nil end
    if lines[1] ~= Personas.FINGERPRINTS_HEADER then return {}, "line 1: expected " .. Personas.FINGERPRINTS_HEADER end
    for number = 2, #lines do
        local name, fingerprint = string.match(lines[number], "^(_?[a-z][a-z0-9_]*%.txt) ([0-9]+)$")
        if not name or record[name] then return {}, "line " .. tostring(number) .. ": " .. lines[number] end
        record[name] = fingerprint
    end
    return record, nil
end

local function writeFingerprints(record)
    local out = {}
    for name, fingerprint in pairs(record) do out[#out + 1] = name .. " " .. fingerprint end
    table.sort(out)
    local writer = getFileWriter(Personas.FINGERPRINTS, true, false)
    if not writer then
        log("ERROR: cannot write Zomboid/Lua/" .. Personas.FINGERPRINTS .. "; unmodified sheets will be recognised"
            .. " by their delivered versions only")
        return
    end
    writer:write(Personas.FINGERPRINTS_HEADER .. "\n")
    for _, line in ipairs(out) do writer:write(line .. "\n") end
    writer:close()
end

local function writeSheet(target, lines)
    local writer = getFileWriter(target, true, false)
    if not writer then
        log("ERROR: cannot write " .. target)
        return false
    end
    for _, line in ipairs(lines) do writer:write(line .. "\n") end
    writer:close()
    return true
end

-- Nom d'un fichier livré dans les journaux : la voix, ou le fichier commun des lieux (E25-T01).
local function deliveredName(name)
    if name == Personas.PLACES then return "shared places file '" .. name .. "'" end
    return "voice '" .. string.sub(name, 1, -5) .. "'"
end

-- Fichiers livrés à installer : les fiches de voix du dossier du mod, puis le fichier commun des lieux (E25-T01).
local function deliveredNames()
    local listing = javaList(listFilesInModDirectory and listFilesInModDirectory(Personas.MOD_ID, Personas.BUNDLED_DIR))
    local names = sheetNames(listing)
    if #names == 0 then
        log("ERROR: no bundled persona sheet in the mod folder " .. Personas.BUNDLED_DIR .. "/")
        names = {}
        for _, name in ipairs(Personas.BUNDLED_FALLBACK) do names[#names + 1] = name end
        names[#names + 1] = Personas.PLACES
    elseif contains(listing, Personas.PLACES) then
        names[#names + 1] = Personas.PLACES
    end
    return names
end

-- Installe ou met à jour un fichier livré (règles ci-dessus) ; rend "copied", "updated" ou nil.
local function installOne(name, record, damaged)
    local target = Personas.DIR .. "/" .. name
    local source = getModFileReader(Personas.MOD_ID, Personas.BUNDLED_DIR .. "/" .. name, false)
    if not source then
        log("ERROR: cannot read the bundled sheet " .. Personas.BUNDLED_DIR .. "/" .. name)
        return nil
    end
    local delivered = readLines(source)
    local deliveredPrint = Personas.fingerprint(delivered)
    local existing = getFileReader(target, false)
    if not existing then
        if not writeSheet(target, delivered) then return nil end
        log("installed the bundled sheet " .. target)
        record[name] = deliveredPrint
        return "copied"
    end
    local current = Personas.fingerprint(readLines(existing))
    if current == deliveredPrint then
        if record[name] ~= current then
            record[name] = current
            return "recorded"
        end
        return nil
    end
    if damaged then
        log("WARNING: " .. deliveredName(name) .. " differs from its delivered version, kept (fingerprint file"
            .. " damaged)")
        return nil
    end
    local unmodified
    if record[name] ~= nil then
        unmodified = current == record[name]
    else
        unmodified = isKnownDelivered(string.sub(name, 1, -5), current)
    end
    if not unmodified then
        log("WARNING: " .. deliveredName(name) .. " modified by the admin, delivered version not applied"
            .. " (Zomboid/Lua/" .. target .. ")")
        return nil
    end
    if not writeSheet(target, delivered) then return nil end
    record[name] = deliveredPrint
    log("INFO: " .. deliveredName(name) .. " updated to the delivered version (Zomboid/Lua/" .. target .. ")")
    return "updated"
end

-- Copie chaque fiche livrée absente du dossier de travail et remplace les fiches installées non modifiées dont la
-- version livrée a changé ; de même pour le fichier commun des lieux (E25-T01). Rend le nombre de fichiers copiés et
-- le nombre de fichiers remplacés.
function Personas.install()
    local names = deliveredNames()
    local record, damaged = readFingerprints()
    if damaged then
        log("WARNING: Zomboid/Lua/" .. Personas.FINGERPRINTS .. " is damaged (" .. damaged .. "): ignored, no"
            .. " installed sheet is replaced by its delivered version; empty this file to let the server recognise"
            .. " the unmodified sheets again")
    end
    local copied, updated, changed = 0, 0, false
    for _, name in ipairs(names) do
        local done = installOne(name, record, damaged)
        if done == "copied" then copied = copied + 1 end
        if done == "updated" then updated = updated + 1 end
        changed = changed or done ~= nil
    end
    if changed and not damaged then writeFingerprints(record) end
    return copied, updated
end

-- Lecture du dossier ---------------------------------------------------------------------------

-- Règles des fiches (racine de composition, E20-T03) ----------------------------------------------------------

local catalogue = nil

-- Catalogue livré, lu une fois par session Lua (fichier du mod) ; illisible ou refusé : vide, journalisé.
local function loadCatalogue()
    if catalogue then return catalogue end
    local path = Personas.BUNDLED_DIR .. "/" .. Personas.CATALOGUE
    local reader = getModFileReader(Personas.MOD_ID, path, false)
    if not reader then
        log("ERROR: cannot read the shared category catalogue " .. path .. " of the mod")
        catalogue = {}
        return catalogue
    end
    local parsed, err = Persona.parseCatalogue(readLines(reader))
    if not parsed then log("ERROR: " .. path .. " of the mod refused, " .. err) end
    catalogue = parsed or {}
    return catalogue
end

-- Règles injectées dans RS_Persona : gabarits de mission donnés par une voix (registre du mod commun), natures de
-- récompense et compétences (RS_Rewards), catégories, modes d'arrivée (RS_TradeArrivals), poids des objets du troc
-- (RS_ItemWeights, E22-T12), valeur de vente de ce que la voix accepte (CA_TradeValues, E23-T06), lieux communs en
-- service et genres de bâtiment d'un objectif tiré (CA_Sites.KINDS, E25-T01). Lu à l'appel :
-- le jeu a tout chargé (gabarits, natures et modes inscrits, scripts
-- d'objets) avant la lecture des fiches (OnLoadRadioScripts).
function Personas.rules()
    local Missions = require "CoreAI/CA_Missions"
    local Rewards, Arrivals = require "RadioSurvivor/RS_Rewards", require "RadioSurvivor/RS_TradeArrivals"
    local ItemWeights = require "RadioSurvivor/RS_ItemWeights"
    local buildings = {}
    for _, rule in ipairs(require("CoreAI/CA_Sites").KINDS) do buildings[#buildings + 1] = rule.kind end
    return { template = Missions.voiceTemplate, rewards = Rewards.KINDS, skills = Rewards.SKILLS,
        categories = loadCatalogue(), arrivals = Arrivals.NAMES, itemWeight = ItemWeights.of,
        sellValue = require("CoreAI/CA_TradeValues").sellValue, places = state.places, buildings = buildings }
end

-- Lieux communs en service (id -> lieu), dernière version valide du fichier de travail (E25-T01).
function Personas.places()
    return state.places
end

-- E25-T01 : relit le fichier commun des lieux du dossier de travail quand son texte a changé. Valide : il entre en
-- service et toutes les fiches seront relues (state.files oublié : une fiche qui nomme un lieu retiré est alors
-- refusée avec sa ligne). Refusé : journalisé une fois par contenu avec sa ligne, la dernière version valide reste en
-- service. Absent ou vide : aucun lieu.
local function scanPlaces()
    local path = Personas.DIR .. "/" .. Personas.PLACES
    local reader = getFileReader(path, false)
    local lines = reader and readLines(reader) or {}
    local text = table.concat(lines, "\n")
    if state.placesText == text then return end
    state.placesText = text
    local places, err = {}, nil
    if #lines > 0 then places, err = Persona.parsePlaces(lines) end
    if not places then
        log("ERROR: " .. path .. " refused, " .. err .. "; the previous valid places stay in service")
        return
    end
    state.places = places
    state.files = {}
    local count = 0
    for _ in pairs(places) do count = count + 1 end
    log("shared places loaded: " .. tostring(count) .. " place(s)")
end

local function removeVoice(id, why)
    if state.voices[id] then
        state.voices[id] = nil
        log("voice '" .. id .. "' removed (" .. why .. ")")
    end
end

-- Fréquence de la fiche pour le journal : fixe, ou radio dont la zone donne le tirage.
local function sheetFrequencies(sheet)
    if sheet.frequency then return "frequency " .. Const.frequencyLabel(sheet.frequency) end
    return "radio " .. sheet.radio
end

local function setVoice(id, sheet)
    local voice = state.voices[id]
    if voice then
        voice.sheet = sheet
        log("voice '" .. id .. "' updated: state " .. sheet.state .. ", " .. sheetFrequencies(sheet))
    else
        state.rank = state.rank + 1
        state.voices[id] = { sheet = sheet, rank = state.rank, served = {}, frequencies = {} }
        log("voice '" .. id .. "' loaded: state " .. sheet.state .. ", " .. sheetFrequencies(sheet))
    end
end

local function scan()
    scanPlaces()
    local names = sheetNames(javaList(listFilesInZomboidLuaDirectory(Personas.DIR)))
    local seen = {}
    for _, name in ipairs(names) do
        local id = string.sub(name, 1, -5)
        local path = Personas.DIR .. "/" .. name
        local reader = getFileReader(path, false)
        if reader then
            seen[id] = true
            local lines = readLines(reader)
            local text = table.concat(lines, "\n")
            if state.files[id] ~= text then
                state.files[id] = text
                if #lines == 0 then
                    removeVoice(id, "empty file")
                else
                    local sheet, err = Persona.parseLines(lines, id, Personas.rules())
                    if sheet then
                        setVoice(id, sheet)
                    elseif state.voices[id] then
                        log("ERROR: " .. path .. " refused, " .. err .. "; the previous valid version stays in service")
                    else
                        log("ERROR: " .. path .. " refused, " .. err)
                    end
                end
            end
        end
    end
    local gone = {}
    for id, voice in pairs(state.voices) do
        if not seen[id] and not voice.generated then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do
        removeVoice(id, "file removed")
        state.files[id] = nil
    end
end

-- Tirage (E05-T07, E24-T01) ---------------------------------------------------------------------
--
-- Une fiche radio=<niveau> reçoit une fréquence tirée uniformément par ZombRand parmi les fréquences libres de la zone
-- du niveau (RS_RadioLevels.zones : captées par ce niveau, pas par les radios plus simples ; pas de 0,2 MHz). Une
-- fréquence n'est pas libre si :
--   - une chaîne qui n'est pas une voix de ce module l'occupe (getChannelsList : chaînes vanilla de RadioData.xml,
--     alerte d'urgence AEBS, chaînes des mods déjà inscrites), ou si la ModData de GameTime la donne à une chaîne
--     dynamique vanilla (dynamicRadio : fréquence de l'AEBS de la partie) ;
--   - elle est à moins de MIN_GAP_KHZ d'une fréquence d'une autre voix chargée (fixe, tirée ou mémorisée, quel que
--     soit son état : une voix gone peut revenir) : jamais deux voix sur la même fréquence.
-- L'AEBS est déjà créée au moment du tirage : les fichiers Lua vanilla sont chargés avant ceux des mods
-- (LuaManager.LoadDirBase, LuaManager.java:1197-1198, 42.21.0), donc l'abonné OnLoadRadioScripts de
-- ISDynamicRadio.lua passe avant le nôtre ; la lecture de dynamicRadio couvre aussi l'ordre inverse. Une chaîne
-- de mod inscrite après nous et tirée par getRandomFrequency évite nos fréquences (knownFrequencies,
-- ZomboidRadio.java:139-147, 179-183).
-- Mémoire : fichier MEMORY_PREFIX .. hex("mode/nom de la partie") .. ".txt" sur la machine qui fait autorité,
-- en-tête MEMORY_HEADER puis une ligne « id niveau kHz » par voix tirée. Monde neuf (OnLoadRadioScripts(_, true),
-- ZomboidRadio.java:246 : savedWorldVersion == -1) : l'ancien fichier du même nom (monde effacé puis recréé sous
-- le même nom, base multiplayer.md) est ignoré, puis réécrit. Sinon les fréquences mémorisées sont reprises. Une
-- fréquence mémorisée devenue prise (chaîne étrangère, fréquence fixe ou déjà attribuée d'une autre voix trop
-- proche) ou une radio changée dans la fiche donne un nouveau tirage de cette voix seulement, journalisé.

local function memoryPath()
    local world = getWorld()
    return Personas.MEMORY_PREFIX .. Codec.hexBytes(tostring(world:getGameMode()) .. "/" .. tostring(world:getWorld()))
        .. ".txt"
end

-- Fichier de tirage de la partie -> table id -> { level, khz }. Une ligne invalide (niveau inconnu, fréquence hors de
-- sa zone ou hors du pas) est ignorée et journalisée : sa voix est tirée de nouveau.
local function readMemory()
    local draws = {}
    local path = memoryPath()
    local reader = getFileReader(path, false)
    if not reader then
        log("no drawn frequencies remembered for this game yet (Zomboid/Lua/" .. path .. ")")
        return draws
    end
    for number, line in ipairs(readLines(reader)) do
        if not (number == 1 and line == Personas.MEMORY_HEADER) and line ~= "" then
            local id, level, khz = string.match(line, "^([a-z][a-z0-9_]*) ([a-z_]+) ([0-9]+)$")
            khz = tonumber(khz)
            if not id or not Levels.inZone(level, khz) or not Levels.onGrid(khz) then
                log("WARNING: Zomboid/Lua/" .. path .. " line " .. tostring(number) .. " ignored: " .. line)
            else
                draws[id] = { level = level, khz = khz }
            end
        end
    end
    return draws
end

local function writeMemory()
    local path = memoryPath()
    local out = {}
    for id, drawn in pairs(state.draws) do out[#out + 1] = id .. " " .. drawn.level .. " " .. tostring(drawn.khz) end
    table.sort(out)
    local writer = getFileWriter(path, true, false)
    if not writer then
        log("ERROR: cannot write Zomboid/Lua/" .. path .. "; the frequencies will be drawn again at the next start")
        return
    end
    writer:write(Personas.MEMORY_HEADER .. "\n")
    for _, line in ipairs(out) do writer:write(line .. "\n") end
    writer:close()
end

local function ensureMemory()
    if state.draws then return end
    if state.newGame then
        state.draws = {}
        log("new game: the frequencies of the voices are drawn")
    else
        state.draws = readMemory()
    end
end

-- Fréquences occupées par des chaînes qui ne sont pas des voix de ce module : kHz -> nom de la chaîne.
local function foreignFrequencies(manager)
    local foreign = {}
    local prefixLength = string.len(Personas.CHANNEL_PREFIX)
    for _, channel in ipairs(javaList(manager:getChannelsList())) do
        if string.sub(tostring(channel:getGUID()), 1, prefixLength) ~= Personas.CHANNEL_PREFIX then
            foreign[channel:GetFrequency()] = tostring(channel:GetName())
        end
    end
    local gameTime = getGameTime and getGameTime()
    local modData = gameTime and gameTime:getModData()
    local dynamic = modData and modData.dynamicRadio
    if type(dynamic) == "table" then
        for _, channel in ipairs(dynamic) do
            if type(channel) == "table" and type(channel.freq) == "number" and not foreign[channel.freq] then
                foreign[channel.freq] = tostring(channel.name)
            end
        end
    end
    return foreign
end

-- Revendication d'une autre voix à moins de MIN_GAP_KHZ de khz, ou nil.
local function tooClose(claims, id, khz)
    for _, claim in ipairs(claims) do
        if claim.id ~= id and math.abs(claim.khz - khz) < Personas.MIN_GAP_KHZ then return claim end
    end
    return nil
end

-- Fréquence libre tirée dans la zone du niveau, ou nil.
local function draw(level, id, claims, foreign)
    local free = {}
    for _, zone in ipairs(Levels.zones(level) or {}) do
        for khz = zone.low, zone.high, Levels.STEP_KHZ do
            if not foreign[khz] and not tooClose(claims, id, khz) then free[#free + 1] = khz end
        end
    end
    if #free == 0 then return nil end
    return free[ZombRand(#free) + 1]
end

-- Raison de tirer de nouveau la fréquence mémorisée d'une voix, ou nil pour la garder.
local function redrawReason(remembered, level, id, final, foreign)
    if remembered == nil then
        return state.newGame and "new game" or "no frequency remembered for this voice"
    end
    if remembered.level ~= level then return "radio changed from " .. remembered.level end
    local khz = remembered.khz
    if foreign[khz] then return Const.frequencyLabel(khz) .. " taken by the radio channel '" .. foreign[khz] .. "'" end
    local claim = tooClose(final, id, khz)
    if claim then
        return Const.frequencyLabel(khz) .. " too close to " .. Const.frequencyLabel(claim.khz) .. " of voice '"
            .. claim.id .. "'"
    end
    return nil
end

-- Fréquence d'une voix à tirer : mémorisée si elle reste libre, sinon tirée. claims : revendications de toutes les
-- voix ; final : celles qui font refuser une fréquence mémorisée. Rend la liste (une fréquence, ou vide) et vrai si
-- la mémoire de la voix a changé.
local function resolveDraw(voice, claims, final, foreign)
    local id, level = voice.sheet.id, voice.sheet.radio
    local remembered = state.draws[id]
    local why = redrawReason(remembered, level, id, final, foreign)
    local khz = remembered and remembered.khz
    if why then
        khz = draw(level, id, claims, foreign)
        if khz then
            log("voice '" .. id .. "' drew " .. Const.frequencyLabel(khz) .. " MHz for the radio " .. level .. " ("
                .. why .. ")")
        else
            log("ERROR: voice '" .. id .. "': no free frequency left for the radio " .. level .. " (" .. why
                .. "); choose a stronger radio in its sheet")
        end
    end
    if not khz then
        state.draws[id] = nil
        return {}, why ~= nil
    end
    state.draws[id] = { level = level, khz = khz }
    claims[#claims + 1] = { id = id, khz = khz }
    final[#final + 1] = { id = id, khz = khz }
    return { khz }, why ~= nil
end

-- Fréquences effectives de chaque voix (voice.frequencies) : sa fréquence fixe, ou celle tirée pour sa radio. Voix
-- traitées dans leur ordre de chargement ; une fréquence fixe d'une autre voix l'emporte toujours sur une fréquence
-- tirée (la voix tirée change de fréquence).
local function resolveFrequencies(manager)
    local voices = {}
    for _, voice in pairs(state.voices) do voices[#voices + 1] = voice end
    table.sort(voices, function(a, b) return a.rank < b.rank end)
    local anyDraw = false
    for _, voice in ipairs(voices) do
        voice.frequencies = voice.sheet.frequency and { voice.sheet.frequency } or {}
        if not voice.sheet.frequency then anyDraw = true end
    end
    if not anyDraw then return end
    ensureMemory()
    local foreign = foreignFrequencies(manager)
    -- claims : fréquences fixes et mémorisées (radio actuelle) de toutes les voix, puis tirages définitifs ;
    -- final : fréquences fixes, puis fréquences définitives des voix déjà traitées.
    local claims, final = {}, {}
    for _, voice in ipairs(voices) do
        local id = voice.sheet.id
        if voice.sheet.frequency then
            claims[#claims + 1] = { id = id, khz = voice.sheet.frequency }
            final[#final + 1] = { id = id, khz = voice.sheet.frequency }
        else
            local remembered = state.draws[id]
            if remembered and remembered.level == voice.sheet.radio then
                claims[#claims + 1] = { id = id, khz = remembered.khz }
            end
        end
    end
    local changed = false
    for _, voice in ipairs(voices) do
        local id = voice.sheet.id
        if not voice.sheet.frequency then
            local list, voiceChanged = resolveDraw(voice, claims, final, foreign)
            voice.frequencies = list
            changed = changed or voiceChanged
        elseif state.draws[id] then
            state.draws[id] = nil
            changed = true
        end
    end
    if changed then writeMemory() end
end

-- Chaînes --------------------------------------------------------------------------------------

local function sortedVoices()
    local list = {}
    for _, voice in pairs(state.voices) do list[#list + 1] = voice end
    table.sort(list, function(a, b) return a.rank < b.rank end)
    return list
end

-- Une voix active ou silencieuse occupe ses fréquences ; gone et dead les libèrent.
function Personas.holdsFrequencies(sheet)
    return sheet.state == "active" or sheet.state == "silent"
end

local function warnOnce(warned, key, msg)
    warned[key] = true
    if not state.warned[key] then log(msg) end
end

local function applyChannels(manager)
    local want, warned = {}, {}
    for _, voice in ipairs(sortedVoices()) do
        local id = voice.sheet.id
        if Personas.holdsFrequencies(voice.sheet) then
            for _, khz in ipairs(voice.frequencies) do
                local owner = want[khz]
                if owner then
                    warnOnce(warned, "conflict " .. id .. " " .. khz, "WARNING: frequency " .. Const.frequencyLabel(khz)
                        .. " of voice '" .. id .. "' refused, already used by voice '" .. owner
                        .. "' (the sheet loaded first keeps it)")
                else
                    want[khz] = id
                end
            end
        end
    end

    local stale = {}
    for khz, channel in pairs(state.channels) do
        if want[khz] ~= channel.id then stale[#stale + 1] = khz end
    end
    for _, khz in ipairs(stale) do
        local channel = state.channels[khz]
        if manager:getRadioChannel(channel.uuid) ~= nil then manager:RemoveChannel(khz) end
        state.channels[khz] = nil
        log("channel of voice '" .. channel.id .. "' removed from " .. Const.frequencyLabel(khz) .. " MHz")
    end

    for khz, id in pairs(want) do
        if not state.channels[khz] then
            local uuid = Personas.CHANNEL_PREFIX .. id .. "-" .. tostring(khz)
            -- Après un rechargement du Lua, la chaîne est encore dans le gestionnaire : la reprendre.
            local channel = manager:getRadioChannel(uuid)
            if channel == nil then
                manager:AddChannel(DynamicRadioChannel.new(Const.CHANNEL_NAME, khz, ChannelCategory.Amateur, uuid), false)
                channel = manager:getRadioChannel(uuid)
            end
            if channel ~= nil then
                -- Le panneau de la radio affiche « Chaîne inconnue » plutôt que le nom du mod.
                getZomboidRadio():removeChannelName(khz)
                state.channels[khz] = { id = id, uuid = uuid }
                log("channel of voice '" .. id .. "' created on " .. Const.frequencyLabel(khz) .. " MHz")
            else
                warnOnce(warned, "taken " .. id .. " " .. khz, "WARNING: frequency " .. Const.frequencyLabel(khz)
                    .. " of voice '" .. id .. "' already used by another radio channel (game or other mod)")
            end
        end
    end
    state.warned = warned

    for _, voice in pairs(state.voices) do
        local served = {}
        for _, khz in ipairs(voice.frequencies) do
            local channel = state.channels[khz]
            if channel and channel.id == voice.sheet.id then served[#served + 1] = khz end
        end
        voice.served = served
    end
end

-- Fréquences servies des voix active ou silent, celles de Walt d'abord puis les autres voix dans leur ordre de
-- chargement. Côté autorité seulement (tests, diagnostic) : depuis E05-T08, rien de cette liste ne part chez les
-- clients, qui découvrent les fréquences en jeu ; le serveur trie chaque phrase reçue (RadioSurvivor_Server.lua).
function Personas.heldFrequencies()
    local out = {}
    local function add(voice)
        if voice and Personas.holdsFrequencies(voice.sheet) then
            for _, khz in ipairs(voice.served) do out[#out + 1] = khz end
        end
    end
    add(state.voices[Personas.MAIN_VOICE])
    for _, voice in ipairs(sortedVoices()) do
        if voice.sheet.id ~= Personas.MAIN_VOICE then add(voice) end
    end
    return out
end

local function currentManager()
    local radio = getZomboidRadio()
    return radio and radio:getScriptManager()
end

-- Relecture complète : installation (une fois par monde), dossier, chaînes. Rend false sans rien faire si le mod
-- est désactivé ou si le gestionnaire de chaînes n'existe pas (client MP). Rien n'est annoncé aux clients (E05-T08).
function Personas.reload(manager)
    state.nextReloadMs = getTimestampMs() + Personas.RELOAD_MS
    if not Const.isEnabled() then return false end
    manager = manager or currentManager()
    if not manager then return false end
    if not state.installed then
        state.installed = true
        Personas.install()
    end
    scan(); Personas.applyGenerated() -- E08-T06: generated voices
    resolveFrequencies(manager)
    applyChannels(manager)
    return true
end

-- À chaque chargement du monde : nouveau gestionnaire de chaînes, état oublié, tout relu. isNewGame : second
-- argument d'OnLoadRadioScripts, vrai pour un monde neuf (ZomboidRadio.java:246) : nouveau tirage des fréquences.
function Personas.onLoadRadioScripts(manager, isNewGame)
    state = fresh()
    state.newGame = isNewGame == true
    return Personas.reload(manager)
end

function Personas.tick(now)
    if now >= state.nextReloadMs then Personas.reload() end
end

-- Accès -----------------------------------------------------------------------------------------

-- Dernière version valide de la fiche, ou nil.
function Personas.get(id)
    local voice = state.voices[id]
    return voice and voice.sheet
end

-- Fréquences (kHz) de la voix pour cette partie : sa fréquence fixe, ou celle tirée pour sa radio (E24-T01), dans
-- une liste d'au plus un élément ; servie ou non.
function Personas.frequencies(id)
    local voice = state.voices[id]
    return voice and voice.frequencies or {}
end

-- Fréquences (kHz) réellement servies par une chaîne de la voix.
function Personas.served(id)
    local voice = state.voices[id]
    return voice and voice.served or {}
end

-- Chaîne du gestionnaire courant pour une fréquence servie, ou nil.
function Personas.channel(khz)
    local channel = state.channels[khz]
    local manager = channel and currentManager()
    return manager and manager:getRadioChannel(channel.uuid)
end

-- Voix qui occupe une fréquence, ou nil.
function Personas.voiceAt(khz)
    local channel = state.channels[khz]
    return channel and channel.id
end

function Personas.isServed(id, khz)
    return contains(Personas.served(id), khz)
end

-- Heures d'écoute (minutes du jour de jeu). Une plage inclut sa minute de début et exclut sa minute de fin
-- (06:00-12:00 : de 06:00 à 11:59) ; une plage qui passe minuit (22:00-06:00) couvre 22:00 à 05:59.
function Personas.isListening(sheet, minute)
    if #sheet.listen == 0 then return true end
    for _, range in ipairs(sheet.listen) do
        if range.from < range.to then
            if minute >= range.from and minute < range.to then return true end
        elseif minute >= range.from or minute < range.to then
            return true
        end
    end
    return false
end

-- Identifiants des voix chargées, dans leur ordre de chargement (appels spontanés, E05-T05).
function Personas.ids()
    local out = {}
    for _, voice in ipairs(sortedVoices()) do out[#out + 1] = voice.sheet.id end
    return out
end

-- Fiches engendrées (E08-T06) ----------------------------------------------------------------------
-- Voix sans fichier, données par un autre module serveur (RS_GroupRadio : une voix par groupe équipé d'un poste
-- émetteur). Même traitement qu'une fiche lue (tirage pour sa radio mémorisé dans le fichier de la partie, chaîne,
-- fréquence libérée quand la voix disparaît) ; jamais écrites dans le dossier des fiches (le pont ne les lit pas : elles
-- répondent par la file des PNJ du carnet). Un fichier de même identifiant l'emporte (avertissement). state.generated :
-- id -> { sheet, key }, remis à zéro avec l'état (monde chargé) ; placé en fin de fichier (références de rs.env).

local generatedWarned = {}

function Personas.applyGenerated()
    state.generated = state.generated or {}
    for id, entry in pairs(state.generated) do
        local voice = state.voices[id]
        if voice and not voice.generated then
            if not generatedWarned[id] then
                generatedWarned[id] = true
                log("WARNING: generated voice '" .. id .. "' ignored, a sheet file has this id")
            end
        elseif not voice or voice.key ~= entry.key then
            setVoice(id, entry.sheet)
            state.voices[id].generated, state.voices[id].key = true, entry.key
        end
    end
    local gone = {}
    for id, voice in pairs(state.voices) do
        if voice.generated and not state.generated[id] then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do removeVoice(id, "generated voice withdrawn") end
end

-- Remplace l'ensemble des fiches engendrées : map id -> { lines = lignes au format des fiches, group = référence }.
-- Une fiche invalide est refusée et journalisée. Rend vrai si l'ensemble a changé (l'appelant relit alors : reload).
function Personas.setGenerated(map)
    local out, changed = {}, false
    for id, entry in pairs(map or {}) do
        local key = table.concat(entry.lines, "\n")
        local old = state.generated and state.generated[id]
        if old and old.key == key then
            out[id] = old
        else
            local sheet, err = Persona.parseLines(entry.lines, id, Personas.rules())
            if sheet then
                sheet.group, sheet.generated = entry.group, true
                out[id] = { sheet = sheet, key = key }
                changed = true
            else
                log("ERROR: generated voice '" .. tostring(id) .. "' refused, " .. tostring(err))
            end
        end
    end
    for id in pairs(state.generated or {}) do
        if not out[id] then changed = true end
    end
    state.generated = out
    return changed
end

return Personas
