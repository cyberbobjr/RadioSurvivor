-- Radio Survivor : copie client de l'historique radio de ce personnage (E06-T04), pour l'onglet « Radio » du carnet.
-- L'autorité tient l'historique (server/RadioSurvivor/RS_RadioLog.lua) et n'envoie que celui du personnage connecté :
-- tout l'historique à la demande (ouverture du carnet ou de l'onglet), puis chaque ligne nouvelle. Une ligne arrivée
-- carnet fermé, réduit ou sur un autre onglet allume le voyant (unread) jusqu'à sa lecture ; une ligne arrivée sur une
-- fréquence que le joueur ne lit pas allume aussi le point de cette fréquence (f.unread, état client seul, E06-T06),
-- éteint quand il la sélectionne.
-- Réglage d'un clic : la radio équipée (main ou dos, getEquipedRadio) passe sur la fréquence par l'action vanilla
-- ISRadioAction « SetChannel » (celle du module de canal de la fenêtre radio), qui synchronise l'état en MP.
-- Logique sans interface : banc tests/test_radio_history.py.
local Const = require "RadioSurvivor/RadioSurvivor_Const"

local History = {}
History.MAX_LINES = 40
History.MAX_FREQUENCIES = 8

-- { { khz, last, unread, lines = { { kind, text, when, seq } } } }, personnage de ces données, voyant.
History.frequencies = {}
History.character = nil
History.unread = false
-- Rappels posés par le carnet : changement des données ; le joueur lit-il l'onglet Radio en ce moment
-- (isViewing()), et cette fréquence (isViewing(khz)) ?
History.onChange = nil
History.isViewing = nil

local function player()
    return getSpecificPlayer and getSpecificPlayer(0) or getPlayer()
end

local function send(command, args)
    local p = player()
    if not p then return false end
    sendClientCommand(p, Const.MODULE, command, args)
    return true
end

-- Demande tout l'historique de ce personnage au serveur.
function History.request()
    return send(Const.CMD.HISTORY, { v = 1 })
end

-- Signale une ligne reçue par une radio de ce client sur khz (OnDeviceText) ; le serveur la vérifie.
function History.report(khz, text)
    khz = tonumber(khz)
    text = Const.oneLine(text)
    if not khz or text == "" or string.match(text, "^<%a+>$") then return false end
    return send(Const.CMD.HEARD, { khz = khz, text = text })
end

local function find(khz, create)
    for _, f in ipairs(History.frequencies) do
        if f.khz == khz then return f end
    end
    if not create then return nil end
    local f = { khz = khz, last = 0, lines = {} }
    History.frequencies[#History.frequencies + 1] = f
    return f
end

local function trim()
    while #History.frequencies > History.MAX_FREQUENCIES do
        local oldest = 1
        for i, f in ipairs(History.frequencies) do
            if f.last < History.frequencies[oldest].last then oldest = i end
        end
        table.remove(History.frequencies, oldest)
    end
end

local function copyLine(line)
    if type(line) ~= "table" or type(line.text) ~= "string" then return nil end
    return { kind = tostring(line.kind or "heard"), text = line.text, when = tostring(line.when or ""),
        seq = tonumber(line.seq) or 0 }
end

-- Voix connue d'une fréquence (E06-T07) : copie bornée de { id, name, hours = { { from, to } } }, ou nil.
local function copyVoice(voice)
    if type(voice) ~= "table" or type(voice.id) ~= "string" or type(voice.name) ~= "string" then return nil end
    local hours = {}
    for _, range in ipairs(type(voice.hours) == "table" and voice.hours or {}) do
        local from, to = tonumber(range.from), tonumber(range.to)
        if from and to and #hours < 8 then hours[#hours + 1] = { from = from, to = to } end
    end
    return { id = voice.id, name = voice.name, hours = hours }
end

-- Données d'un autre personnage (mort, autre partie) : effacées.
local function owner(character)
    if History.character ~= nil and character ~= History.character then
        History.frequencies, History.unread = {}, false
    end
    History.character = character
end

local function changed()
    if History.onChange then History.onChange() end
end

local function viewing(khz)
    return History.isViewing ~= nil and History.isViewing(khz) == true
end

-- Commandes du serveur (module Const.MODULE). Rend true si la commande est pour l'historique.
function History.receive(command, args)
    args = args or {}
    if command == Const.CMD.HISTORY then
        owner(args.character)
        local kept = {}
        for _, item in ipairs(args.frequencies or {}) do
            local khz = tonumber(item.khz)
            if khz then
                local f = find(khz, false) or { khz = khz, lines = {} }
                f.last = tonumber(item.last) or 0
                f.voice = copyVoice(item.voice)
                kept[#kept + 1] = f
            end
        end
        History.frequencies = kept
        trim()
        changed()
        return true
    elseif command == Const.CMD.HISTORY_LINES then
        owner(args.character)
        local khz = tonumber(args.khz)
        if not khz then return true end
        local f = find(khz, true)
        f.last = tonumber(args.last) or f.last
        f.voice = copyVoice(args.voice)
        f.lines = {}
        for _, line in ipairs(args.lines or {}) do
            local copy = copyLine(line)
            if copy then f.lines[#f.lines + 1] = copy end
        end
        while #f.lines > History.MAX_LINES do table.remove(f.lines, 1) end
        trim()
        changed()
        return true
    elseif command == Const.CMD.HISTORY_ADD then
        owner(args.character)
        local khz = tonumber(args.khz)
        local line = copyLine(args.line)
        if not khz or not line then return true end
        local f = find(khz, true)
        f.last = tonumber(args.last) or f.last
        f.voice = copyVoice(args.voice) or f.voice
        local previous = f.lines[#f.lines]
        if not previous or previous.seq ~= line.seq then
            f.lines[#f.lines + 1] = line
            while #f.lines > History.MAX_LINES do table.remove(f.lines, 1) end
        end
        trim()
        if not viewing() then History.unread = true end
        if not viewing(khz) then f.unread = true end
        changed()
        return true
    end
    return false
end

-- Fréquences, la plus récemment active d'abord. Chaque entrée : { id = khz, khz, last, when, count, unread }.
function History.sorted()
    local out = {}
    for _, f in ipairs(History.frequencies) do
        local last = f.lines[#f.lines]
        out[#out + 1] = { id = f.khz, khz = f.khz, last = f.last, when = last and last.when or "", count = #f.lines,
            unread = f.unread == true, voice = f.voice }
    end
    table.sort(out, function(a, b) return a.last > b.last end)
    return out
end

-- Lignes de la fréquence (plus ancienne d'abord), liste éventuellement vide.
function History.lines(khz)
    local f = find(tonumber(khz) or -1, false)
    return f and f.lines or {}
end

-- Nom affiché d'une voix (E06-T07) : nom de scène traduit s'il existe (IGUI_RS_Voice_<id>), sinon nom de la fiche.
function History.voiceName(voice)
    if type(voice) ~= "table" then return nil end
    return getTextOrNull("IGUI_RS_Voice_" .. tostring(voice.id)) or voice.name
end

local function clock(minute)
    minute = math.floor(tonumber(minute) or 0) % 1440
    return string.format("%02d:%02d", math.floor(minute / 60), minute % 60)
end

-- Heures d'écoute d'une voix en texte (« 19:00-22:00, 03:00-06:00 »), ou nil : à toute heure.
function History.hoursText(voice)
    if type(voice) ~= "table" or type(voice.hours) ~= "table" or #voice.hours == 0 then return nil end
    local parts = {}
    for i, range in ipairs(voice.hours) do parts[i] = clock(range.from) .. "-" .. clock(range.to) end
    return table.concat(parts, ", ")
end

function History.markRead()
    History.unread = false
end

-- Point « non lu » de la fréquence éteint (le joueur l'a sélectionnée dans l'onglet Radio).
function History.markFrequencyRead(khz)
    local f = find(tonumber(khz) or -1, false)
    if f then f.unread = nil end
end

-- Motif de refus du réglage de la radio équipée sur khz (texte traduit) et la radio ; nil et la radio si possible.
-- Mêmes conditions que l'action vanilla (ISRadioAction:isValidSetChannel : allumée, alimentée) plus les bornes de
-- réglage de la radio (DeviceData min/maxChannelRange).
function History.tuneProblem(p, khz)
    local radio = p and p:getEquipedRadio()
    local data = radio and radio:getDeviceData()
    if not data then return getText("IGUI_RS_RadioNoEquipped"), nil end
    if not data:getIsTurnedOn() then return getText("IGUI_RadioSurvivor_Off"), radio end
    if data:getPower() <= 0 then return getText("IGUI_RS_RadioNoPower"), radio end
    local low, high = data:getMinChannelRange(), data:getMaxChannelRange()
    if type(low) == "number" and type(high) == "number" and high > 0 and (khz < low or khz > high) then
        return getText("IGUI_RS_RadioOutOfRange", Const.frequencyLabel(khz), Const.frequencyLabel(low),
            Const.frequencyLabel(high)), radio
    end
    return nil, radio
end

-- Règle la radio équipée sur khz par l'action vanilla. Rend true si l'action est mise en file.
function History.tune(khz)
    local p = player()
    khz = tonumber(khz)
    if not p or not khz then return false end
    local problem, radio = History.tuneProblem(p, khz)
    if problem then
        HaloTextHelper.addBadText(p, problem)
        return false
    end
    if radio:getDeviceData():getChannel() == khz then
        HaloTextHelper.addGoodText(p, getText("IGUI_RS_RadioAlreadyTuned", Const.frequencyLabel(khz)))
        return false
    end
    ISTimedActionQueue.add(ISRadioAction:new("SetChannel", p, radio, khz))
    return true
end

-- Pour les tests uniquement.
function History.resetForTests()
    History.frequencies, History.character, History.unread = {}, nil, false
end

return History
