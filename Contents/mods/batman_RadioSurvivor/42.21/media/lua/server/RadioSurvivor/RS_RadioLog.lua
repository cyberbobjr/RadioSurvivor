-- Radio Survivor : historique radio par personnage (E06-T04), gardé par l'autorité dans l'état privé du carnet
-- (RS_State : S.data.characters[<personnage>].radio), persistant (redémarrage, reconnexion), jamais envoyé qu'à son
-- personnage. Lignes typées par fréquence (kHz) :
--   said  : phrase acceptée de ce joueur (commande talk, réponse de voix ou silence) ;
--   reply : réponse d'une voix à ce joueur, inscrite quand elle passe à l'antenne ;
--   heard : ligne entendue par ce joueur, signalée par son client (OnDeviceText) et vérifiée ici : seule une ligne
--           réellement diffusée sur cette fréquence depuis peu (réponse à un autre joueur, appel spontané, phrase
--           d'un autre joueur passée par la commande talk) est admise. Le serveur ne sait pas quelle radio d'inventaire
--           écoute quoi (canal connu en main seulement, réception MP de toute radio allumée de l'inventaire) : le
--           client dit ce qu'il a reçu, le serveur en garantit le texte ;
--   mark  : repère reçu d'une voix (action mark_map acceptée, RS_MapMarks) sur la fréquence de sa réponse, pour le
--           seul appelant : libellé du lieu seul, jamais ses coordonnées (affiché « Repère reçu : <libellé> ») ;
--   reveal : quartier révélé par une voix (action reveal_area acceptée, RS_MapMarks, E07-T05), mêmes règles que mark
--           (affiché « Quartier révélé : <libellé> ») ;
--   mission : mission reçue d'une voix (action start_mission acceptée, RS_MissionVoice, E11-T08), même règles :
--           type du lieu seul (RS_Rescue.KINDS : house, church...), traduit par le carnet (« Mission reçue : maison »).
--   note  : note de fréquence lue par ce personnage (E06-T07, commande note_read vérifiée ici), texte = id de la voix.
-- Aucune fréquence n'entre dans l'historique d'un personnage sans que sa propre radio l'ait réglée (E05-T08) : phrase
-- dite sur sa radio, réponse à sa phrase, ou ligne que son client a reçue sur cette fréquence ; exceptions décidées :
-- note de fréquence lue (E06-T07), fréquence donnée par une voix (récompense, share_frequency).
-- Voix connue (E06-T07, décision de l'utilisateur du 2026-10-18) : la fréquence garde l'id de la voix (f.voice) dès
-- que ce personnage a eu un contact avec elle (réponse à sa phrase, ligne de la voix entendue), qu'il a lu sa note ou
-- qu'une voix lui a donné la fréquence. Le carnet reçoit alors son nom et ses heures d'écoute (Log.voiceInfo, relus
-- dans la fiche à chaque envoi) ; jamais pour une fréquence où le personnage n'a fait que parler (E05-T08 : un silence
-- ne dit pas si une voix y écoute).
-- Bornes : Log.MAX_LINES lignes par fréquence, Log.MAX_FREQUENCIES fréquences par personnage (la moins récemment
-- active est oubliée), textes coupés à Log.MAX_TEXT caractères.
if isClient() then return end
local S = require "RadioSurvivor/RS_State"
local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Personas = require "RadioSurvivor/RS_Personas"
local Notes = require "RadioSurvivor/RS_Notes"

local Log = {}
Log.MAX_LINES = 40
Log.MAX_FREQUENCIES = 8
Log.MAX_TEXT = 200
-- Lignes diffusées gardées par fréquence pour vérifier les signalements, et leur durée de validité (ms réelles).
Log.AIRED_KEEP = 24
Log.AIRED_MS = 300000
-- Signalements « entendu » par personnage : au plus REPORTS_MAX par minute réelle, et au plus REPORT_FREQUENCIES
-- fréquences distinctes par REPORT_WINDOW_MS (un client modifié ne peut pas sonder les fréquences une à une).
Log.REPORTS_MAX = 40
Log.REPORT_FREQUENCIES = 4
Log.REPORT_WINDOW_MS = 600000
Log.KINDS = { said = true, reply = true, heard = true, mark = true, reveal = true, mission = true, reward = true,
    note = true }
-- Bornes de fréquence admises (kHz) : celles des radios vanilla (200 kHz à 1 GHz, plus large que toute radio).
Log.MIN_KHZ = 100
Log.MAX_KHZ = 1000000

-- kHz -> { { text, at, got = { [personnage] = true } }, ... } (plus ancienne d'abord).
local aired = {}
-- personnage -> { times = { ms }, khz = { { khz, at } } }
local reports = {}

local function isInteger(n)
    return type(n) == "number" and n == math.floor(n)
end

function Log.validKhz(khz)
    return isInteger(khz) and khz >= Log.MIN_KHZ and khz <= Log.MAX_KHZ
end

-- Texte d'une ligne : une ligne, sans balises de texte riche, coupé à MAX_TEXT ; "" pour des parasites seuls.
function Log.cleanText(text)
    text = Const.oneLine(text)
    if string.match(text, "^<%a+>$") then return "" end
    text = Const.oneLine(string.gsub(text, "[<>%[%]]", " "))
    if string.len(text) > Log.MAX_TEXT then text = string.sub(text, 1, Log.MAX_TEXT) end
    return text
end

-- Heure de jeu de la ligne (mois/jour heure:minute).
function Log.when()
    local gt = getGameTime()
    return string.format("%02d/%02d %02d:%02d", gt:getMonth() + 1, gt:getDay() + 1, gt:getHour(), gt:getMinutes())
end

-- Personnage du carnet lié à ce joueur (RS_Carnet_Server, commande hello), ou nil : sans carnet lié ni état privé
-- lisible, aucun historique n'est tenu.
function Log.characterOf(player)
    local server = RS_CarnetServer
    local cid = server and player and server.bound[player]
    if not cid or not S.data or S.blocked then return nil end
    local record = S.data.characters[cid]
    if not record or record.retired then return nil end
    return cid, record
end

local function playerOf(cid)
    local server = RS_CarnetServer
    if not server then return nil end
    for player, id in pairs(server.bound) do
        if id == cid then return player end
    end
    return nil
end

local function frequency(record, khz, create)
    local radio = record.radio
    if not radio then
        if not create then return nil end
        radio = { seq = 0, frequencies = {} }
        record.radio = radio
    end
    for _, f in ipairs(radio.frequencies) do
        if f.khz == khz then return f end
    end
    if not create then return nil end
    local f = { khz = khz, last = radio.seq + 1, lines = {} }
    radio.frequencies[#radio.frequencies + 1] = f
    while #radio.frequencies > Log.MAX_FREQUENCIES do
        local oldest = 1
        for i, g in ipairs(radio.frequencies) do
            if g.last < radio.frequencies[oldest].last then oldest = i end
        end
        table.remove(radio.frequencies, oldest)
    end
    return f
end

-- Voix connue d'une fréquence pour le carnet (E06-T07) : { id, name, hours = { { from, to } } } (minutes du jour de
-- jeu, liste vide = à toute heure), relue dans la fiche ; nil si la voix n'est plus sur cette fréquence.
function Log.voiceInfo(f)
    if type(f) ~= "table" or type(f.voice) ~= "string" or Personas.voiceAt(f.khz) ~= f.voice then return nil end
    local sheet = Personas.get(f.voice)
    if not sheet then return nil end
    local hours = {}
    for i, range in ipairs(sheet.listen or {}) do hours[i] = { from = range.from, to = range.to } end
    return { id = f.voice, name = Const.oneLine(sheet.name), hours = hours }
end

-- Inscrit une ligne pour ce personnage et l'envoie à son joueur s'il est connecté. Rend la ligne, ou nil. voice (E06-T07) :
-- id de la voix que cette ligne fait connaître sur khz (contact, note, fréquence donnée), si elle y est encore.
function Log.add(cid, khz, kind, text, voice)
    if not S.data or S.blocked or not Log.KINDS[kind] or not Log.validKhz(khz) then return nil end
    local record = S.data.characters[cid]
    if not record or record.retired then return nil end
    text = Log.cleanText(text)
    if text == "" then return nil end
    local f = frequency(record, khz, true)
    if type(voice) == "string" and Personas.voiceAt(khz) == voice then f.voice = voice end
    local radio = record.radio
    radio.seq = radio.seq + 1
    f.last = radio.seq
    local line = { kind = kind, text = text, when = Log.when(), seq = radio.seq }
    f.lines[#f.lines + 1] = line
    while #f.lines > Log.MAX_LINES do table.remove(f.lines, 1) end
    S.dirty = true
    local player = playerOf(cid)
    if player then
        Const.toClient(player, Const.CMD.HISTORY_ADD, { character = cid, khz = khz, last = f.last, line = line,
            voice = Log.voiceInfo(f) })
    end
    return line
end

-- Ligne passée à l'antenne sur khz : gardée un moment pour vérifier les signalements des clients. owner : personnage
-- qui l'a déjà dans son historique (auteur de la phrase, appelant d'une réponse), jamais signalée par lui.
function Log.aired(khz, text, owner, now)
    text = Log.cleanText(text)
    if text == "" or not Log.validKhz(khz) then return nil end
    now = now or getTimestampMs()
    local list = aired[khz]
    if not list then
        list = {}
        aired[khz] = list
    end
    local entry = { text = text, at = now, got = {} }
    if owner then entry.got[owner] = true end
    list[#list + 1] = entry
    while #list > Log.AIRED_KEEP do table.remove(list, 1) end
    return entry
end

-- Fréquences sans ligne récente oubliées (appelé à chaque diffusion et signalement).
local function forgetAired(now)
    local kept = {}
    for khz, list in pairs(aired) do
        local fresh = {}
        for _, entry in ipairs(list) do
            if now - entry.at < Log.AIRED_MS then fresh[#fresh + 1] = entry end
        end
        if #fresh > 0 then kept[khz] = fresh end
    end
    aired = kept
end

-- Phrase acceptée de ce joueur sur sa radio réglée sur khz : « dit » pour lui, diffusée pour les autres.
function Log.spoken(player, khz, text)
    local cid = Log.characterOf(player)
    if not Log.validKhz(khz) then return end
    forgetAired(getTimestampMs())
    Log.aired(khz, text, cid)
    if cid then Log.add(cid, khz, "said", text) end
end

-- Diffusion d'une voix (lignes à l'antenne) : « répondu » pour l'appelant (cid, nil pour un appel spontané),
-- diffusée pour les autres. Les parasites (<bzzt>…) ne sont pas gardés. Ligne marquée de la voix de khz (E06-T07) :
-- l'entendre la fait connaître ; une phrase de joueur (Log.spoken) ne porte aucune voix.
function Log.broadcast(khz, lines, cid)
    if not Log.validKhz(khz) then return end
    forgetAired(getTimestampMs())
    local voice = Personas.voiceAt(khz)
    for _, text in ipairs(lines or {}) do
        local entry = Log.aired(khz, text, cid)
        if entry then entry.voice = voice end
        if entry and cid then Log.add(cid, khz, "reply", text, voice) end
    end
end

-- Le signalement est-il admis ? Débit par minute et nombre de fréquences distinctes par fenêtre.
local function reportAllowed(cid, khz, now)
    local r = reports[cid]
    if not r then
        r = { times = {}, khz = {} }
        reports[cid] = r
    end
    local times = {}
    for _, t in ipairs(r.times) do
        if now - t < 60000 then times[#times + 1] = t end
    end
    r.times = times
    if #times >= Log.REPORTS_MAX then return false end
    local seen, known = {}, false
    for _, k in ipairs(r.khz) do
        if now - k.at < Log.REPORT_WINDOW_MS then
            seen[#seen + 1] = k
            if k.khz == khz then
                known = true
                k.at = now
            end
        end
    end
    r.khz = seen
    if not known then
        if #seen >= Log.REPORT_FREQUENCIES then return false end
        seen[#seen + 1] = { khz = khz, at = now }
    end
    times[#times + 1] = now
    return true
end

-- Commande heard { khz, text } : ligne reçue par une radio de ce client. Admise si elle a été diffusée sur khz
-- depuis moins de AIRED_MS et que ce personnage ne l'a pas déjà ; sinon ignorée sans réponse.
function Log.heard(player, args)
    local cid = Log.characterOf(player)
    if not cid or type(args) ~= "table" then return false end
    local khz = tonumber(args.khz)
    local text = type(args.text) == "string" and Log.cleanText(args.text) or ""
    if text == "" or not Log.validKhz(khz) then return false end
    local now = getTimestampMs()
    if not reportAllowed(cid, khz, now) then return false end
    forgetAired(now)
    for _, entry in ipairs(aired[khz] or {}) do
        if entry.text == text and not entry.got[cid] then
            entry.got[cid] = true
            return Log.add(cid, khz, "heard", text, entry.voice) ~= nil
        end
    end
    return false
end

-- Commande history : tout l'historique de ce personnage, et de lui seul. Un en-tête (liste des fréquences), puis une
-- commande par fréquence (taille de chaque paquet bornée par MAX_LINES lignes).
function Log.sendAll(player)
    local cid, record = Log.characterOf(player)
    if not cid then return false end
    local list = {}
    local frequencies = record.radio and record.radio.frequencies or {}
    for i, f in ipairs(frequencies) do list[i] = { khz = f.khz, last = f.last, voice = Log.voiceInfo(f) } end
    Const.toClient(player, Const.CMD.HISTORY, { character = cid, frequencies = list })
    for _, f in ipairs(frequencies) do
        Const.toClient(player, Const.CMD.HISTORY_LINES, { character = cid, khz = f.khz, last = f.last, lines = f.lines,
            voice = Log.voiceInfo(f) })
    end
    return true
end

-- Ce personnage connaît-il déjà la voix (E06-T07 : f.voice d'une de ses fréquences) ? (E07-T10 : share_frequency.)
function Log.knowsVoice(cid, voice)
    local record = S.data and not S.blocked and S.data.characters[cid] or nil
    for _, f in ipairs(record and record.radio and record.radio.frequencies or {}) do
        if f.voice == voice then return true end
    end
    return false
end

-- Commande note_read { itemId } (E06-T07) : le client a ouvert une note de fréquence. Admise si l'objet est dans
-- l'inventaire de ce joueur (sacs compris) et porte la note d'une voix qui tient toujours cette fréquence (ModData
-- écrite par l'autorité à la création, RS_Notes) ; une fréquence déjà connue de cette voix n'ajoute rien. Rend la
-- ligne inscrite, ou nil.
function Log.noteRead(player, args)
    local cid, record = Log.characterOf(player)
    local id = type(args) == "table" and tonumber(args.itemId) or nil
    if not cid or not id then return nil end
    local inventory = player:getInventory()
    local item = inventory and inventory:getItemWithIDRecursiv(id)
    if not item or not item:hasModData() then return nil end
    local note = item:getModData()[Notes.MODDATA_KEY]
    local khz = type(note) == "table" and tonumber(note.khz) or nil
    local voice = type(note) == "table" and note.voice or nil
    if not Log.validKhz(khz) or type(voice) ~= "string" or Personas.voiceAt(khz) ~= voice then return nil end
    local f = frequency(record, khz, false)
    if f and f.voice == voice then return nil end
    return Log.add(cid, khz, "note", voice, voice)
end

-- Pour les tests uniquement.
function Log.resetForTests()
    aired, reports = {}, {}
end

return Log
