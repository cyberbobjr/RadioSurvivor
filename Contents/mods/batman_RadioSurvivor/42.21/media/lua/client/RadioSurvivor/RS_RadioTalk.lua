-- Radio Survivor : parler dans une radio (chemin d'envoi commun au menu « Parler sur … » et au module « Émettre » de
-- la fenêtre radio, E06-T02), réponses du serveur, et dernières lignes entendues par fréquence.
-- Le client ne connaît aucune fréquence de voix (E05-T08) : toute phrase dite dans une radio émettrice allumée part au
-- serveur avec la fréquence de la radio ; le serveur trie. Logique sans interface : banc tests/test_radio_module.py.
local Const = require "RadioSurvivor/RadioSurvivor_Const"
-- Historique radio du carnet (E06-T04) : commandes du serveur et lignes reçues signalées au serveur.
local History = require "RadioSurvivor/RS_RadioHistory"
-- Repère d'une voix sur la carte (E07-T04) : commande map_mark du serveur.
local MapActions = require "RadioSurvivor/RS_MapActions"

local Talk = {}
Talk.History = History

-- Lignes gardées par fréquence (module : deux dernières lignes reçues) et fréquences gardées au plus.
Talk.LINES_PER_FREQUENCY = 2
Talk.MAX_FREQUENCIES = 16
-- Portée d'écoute d'un appareil du monde (radio posée, autoradio) : ±5 cases au même étage, comme le vanilla
-- (shared/RadioCom/ISRadioInteractions.lua:173-180, playerInRange).
Talk.HEARING_RANGE = 5
-- Même ligne reçue par deux appareils sur la même fréquence : comptée une fois dans cet intervalle (ms réelles).
Talk.DUPLICATE_MS = 2000

-- Demande en cours : texte saisi et instant d'envoi (temps réel).
local waiting = nil
-- Instant (réel) du dernier envoi : écart minimal Const.clientIntervalMs() entre deux phrases.
local lastSentMs = nil
-- kHz -> { { text, at }, ... } (plus ancienne d'abord) ; ordre d'arrivée des fréquences, pour borner.
local heard = {}
local heardOrder = {}

-- Type d'appareil au sens de la fenêtre radio vanilla (client/RadioCom/ISRadioWindow.lua:225-227).
function Talk.deviceType(device)
    if device == nil then return nil end
    if instanceof(device, "Radio") then return "InventoryItem" end
    if instanceof(device, "IsoWaveSignal") then return "IsoObject" end
    if instanceof(device, "VehiclePart") then return "VehiclePart" end
    return nil
end

function Talk.isWaiting()
    if waiting and getTimestampMs() - waiting.sentAt > Const.CLIENT_TIMEOUT_MS then
        waiting = nil
    end
    return waiting ~= nil
end

-- Même délai que le serveur (Const.clientIntervalMs) : en usage normal, plus de refus rouge « Cooldown ».
function Talk.tooSoon()
    return lastSentMs ~= nil and getTimestampMs() - lastSentMs < Const.clientIntervalMs()
end

-- Le module « Émettre » s'affiche : mod actif, radio émettrice, allumée, micro ouvert (état connu de ce client).
function Talk.moduleShown(data)
    if not Const.isEnabled() or data == nil then return false end
    return data:getIsTwoWay() == true and data:getIsTurnedOn() == true and data:getMicIsMuted() ~= true
end

-- Motif passager qui grise la saisie (attente d'une réponse, écart Const.clientIntervalMs()), ou nil.
function Talk.busyReason()
    if Talk.isWaiting() then return getText("IGUI_RadioSurvivor_Reject_Waiting") end
    if Talk.tooSoon() then return getText("IGUI_RadioSurvivor_Reject_Spam") end
    return nil
end

-- Radio d'inventaire : motif si elle n'est ni en main ni sur le dos (Const.isCarriedRadio, prédicat de Belt
-- Walkie-Talkie) : à la ceinture ou rangée, « prenez le talkie en main » (décision 4) ; radio d'écoute seule :
-- « ne peut qu'écouter ». Allumage et micro : Talk.problem. Autre appareil : nil.
function Talk.placementProblem(player, device)
    if Talk.deviceType(device) ~= "InventoryItem" or Const.isCarriedRadio(player, device) then return nil end
    if Const.transmitRefusal(player, device) == "notTransmitter" then return getText("IGUI_RadioSurvivor_NotTwoWay") end
    return getText("IGUI_RadioSurvivor_NotEquipped")
end

-- Raison de refuser une phrase sur cet appareil, ou nil. Aucune condition de fréquence : la voix qui écoute (ou non),
-- la radio qu'elle exige, ses heures d'écoute et son état sont jugés par le serveur seul.
-- Radio posée : micro à portée (Const.inMicRange, même règle que le serveur). Autoradio : joueur assis dans le
-- véhicule, à n'importe quelle place. Le serveur refait ces contrôles (E06-T03) ; le micro, qu'il ne connaît pas
-- (DeviceData.setMicIsMuted n'est jamais transmis), n'est jugé qu'ici.
function Talk.problem(player, device)
    if not Const.isEnabled() then return getText("IGUI_RadioSurvivor_Reject_Disabled") end
    local kind = Talk.deviceType(device)
    if kind == nil then return getText("IGUI_RadioSurvivor_Reject_NoRadio") end
    local data = device:getDeviceData()
    if kind == "InventoryItem" then
        local placement = Talk.placementProblem(player, device)
        if placement then return placement end
    elseif kind == "IsoObject" then
        local sq = device:getSquare()
        if not sq then return getText("IGUI_RadioSurvivor_Reject_NoRadio") end
        if not Const.inMicRange(player, data, sq:getX(), sq:getY(), sq:getZ()) then
            return getText("IGUI_RadioSurvivor_Reject_TooFar")
        end
    elseif not Const.inVehicle(player, device:getVehicle()) then
        return getText("IGUI_RadioSurvivor_Reject_NotInVehicle")
    end
    if not data or not data:getIsTwoWay() then return getText("IGUI_RadioSurvivor_NotTwoWay") end
    if not data:getIsTurnedOn() then return getText("IGUI_RadioSurvivor_Off") end
    if data:getMicIsMuted() then return getText("IGUI_RadioSurvivor_MicMuted") end
    return Talk.busyReason()
end

-- Arguments de la commande talk qui désignent l'appareil (Const.CMD.TALK) : identifiant d'une radio d'inventaire,
-- case et index d'une radio posée, identifiant du véhicule et de la pièce d'une autoradio ; plus la fréquence lue par
-- ce client.
function Talk.commandArgs(device, text)
    local args = { text = text, channel = device:getDeviceData():getChannel() }
    local kind = Talk.deviceType(device)
    if kind == "InventoryItem" then
        args.itemId = device:getID()
    elseif kind == "IsoObject" then
        local sq = device:getSquare()
        args.source = Const.SOURCE.WORLD
        args.x, args.y, args.z = sq:getX(), sq:getY(), sq:getZ()
        args.index = device:getObjectIndex()
    else
        args.source = Const.SOURCE.VEHICLE
        args.vehicleId = device:getVehicle():getId()
        args.part = device:getId()
    end
    return args
end

-- Texte envoyé : une ligne, sans espaces superflus, coupé à Const.MAX_INPUT_CHARS.
function Talk.cleanText(text)
    text = Const.oneLine(text)
    if string.len(text) > Const.MAX_INPUT_CHARS then
        text = string.sub(text, 1, Const.MAX_INPUT_CHARS)
    end
    return text
end

-- Envoie une phrase dite dans la radio. Rend true si elle part au serveur ; sinon false et le motif (déjà affiché
-- au-dessus du joueur), ou false sans motif pour un texte vide.
function Talk.send(player, device, rawText)
    local text = Talk.cleanText(rawText)
    if text == "" then return false end
    local problem = Talk.problem(player, device)
    if problem then
        HaloTextHelper.addBadText(player, problem)
        return false, problem
    end
    waiting = { text = text, sentAt = getTimestampMs() }
    lastSentMs = waiting.sentAt
    sendClientCommand(player, Const.MODULE, Const.CMD.TALK, Talk.commandArgs(device, text))
    return true
end

-- La phrase est dite à voix haute et part sur la radio par le chemin vanilla : en multijoueur
-- par le chat « dire » (ChatManager → RadioChat, entendue des autres joueurs sur la fréquence),
-- en solo par Say (ZomboidRadio.update transmet la dernière ligne prononcée).
local function speak(player, text)
    if isClient() then
        processSayMessage(text)
    else
        player:Say(text)
    end
end

-- Réponses du serveur (OnServerCommand en multijoueur, appel direct en solo).
function Talk.handle(command, args)
    if History.receive(command, args) then return end
    if MapActions.receive(command, args) then return end
    local player = getPlayer()
    if command == Const.CMD.ACCEPTED then
        -- La phrase n'est prononcée qu'une fois acceptée : un refus ne la fait pas entendre.
        if player and args.text then speak(player, args.text) end
    elseif command == Const.CMD.DONE then
        waiting = nil
    elseif command == Const.CMD.REJECTED then
        waiting = nil
        if player and args.reason then
            HaloTextHelper.addBadText(player, getText("IGUI_RadioSurvivor_Reject_" .. tostring(args.reason)))
        end
    end
end

-- Dernières lignes entendues -------------------------------------------------------------------

-- Garde une ligne reçue sur la fréquence khz (bornée par fréquence et en nombre de fréquences).
function Talk.recordLine(khz, text, now)
    khz = tonumber(khz)
    text = Const.oneLine(text)
    if not khz or text == "" then return false end
    now = now or getTimestampMs()
    local lines = heard[khz]
    if not lines then
        lines = {}
        heard[khz] = lines
        heardOrder[#heardOrder + 1] = khz
        while #heardOrder > Talk.MAX_FREQUENCIES do
            heard[table.remove(heardOrder, 1)] = nil
        end
    end
    local last = lines[#lines]
    if last and last.text == text and now - last.at < Talk.DUPLICATE_MS then return false end
    lines[#lines + 1] = { text = text, at = now }
    while #lines > Talk.LINES_PER_FREQUENCY do table.remove(lines, 1) end
    return true
end

-- Textes des dernières lignes entendues sur khz (plus ancienne d'abord), liste éventuellement vide.
function Talk.lastLines(khz)
    local out = {}
    for _, line in ipairs(heard[tonumber(khz) or -1] or {}) do out[#out + 1] = line.text end
    return out
end

function Talk.forgetLines()
    heard, heardOrder = {}, {}
end

-- Le joueur entend-il l'appareil du monde en x, y, z ? (-1 = radio portée par le joueur.)
function Talk.inHearingRange(player, x, y, z)
    if x == -1 and y == -1 and z == -1 then return true end
    if not player or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return false end
    if math.floor(player:getZ()) ~= math.floor(z) then return false end
    local r = Talk.HEARING_RANGE
    return math.abs(player:getX() - x) <= r and math.abs(player:getY() - y) <= r
end

-- Events.OnDeviceText(guid, codes, x, y, z, line, device) : line est une chaîne, ou un ChatMessage pour la phrase
-- radio d'un autre joueur reçue par une radio d'inventaire en MP (zombie/inventory/types/Radio.java:90-101).
function Talk.onDeviceText(_guid, _codes, x, y, z, line, device)
    if Talk.deviceType(device) == nil then return end
    if type(line) ~= "string" then
        if line ~= nil and instanceof(line, "ChatMessage") then line = line:getText() else return end
    end
    if not Talk.inHearingRange(getPlayer(), x, y, z) then return end
    local data = device:getDeviceData()
    -- Ligne nouvelle (une seule fois si deux appareils la reçoivent) : signalée au serveur pour l'historique du carnet,
    -- qui ne l'admet que si elle a bien été diffusée sur cette fréquence.
    if data and Talk.recordLine(data:getChannel(), line) then History.report(data:getChannel(), line) end
end

-- Pour les tests uniquement : remet l'attente et l'écart à zéro.
function Talk.resetForTests()
    waiting, lastSentMs = nil, nil
end

return Talk
