-- Radio Survivor : côté autorité (serveur en multijoueur, jeu local en solo).
-- Reçoit les phrases des joueurs, les transmet au pont par fichier, relit les réponses et les
-- diffuse sur la chaîne du survivant : tous les joueurs réglés sur la fréquence les entendent.
-- Les voix viennent de leurs fiches (E05-T02, RS_Personas : Zomboid/Lua/batman_RadioSurvivor/personas/<id>.txt,
-- relues à chaud). Routage (E05-T03) : la fréquence de la radio de l'appelant désigne la voix ; la demande au pont
-- porte son identifiant (voice=), le pont y construit le prompt depuis la même fiche et garde un historique par
-- partie et par voix. Les règles d'accès (état, heures d'écoute, radio exigée, budget) sont tenues ici, côté autorité.
-- Le serveur trie (E05-T08) : aucun client ne reçoit les fréquences des voix ; toute phrase dite dans une radio
-- émettrice arrive ici avec la fréquence de la radio, et seule une voix qui tient cette fréquence y répond. Sur une
-- fréquence sans voix, la phrase part sur la radio et rien d'autre ne se passe (ni message, ni demande au pont).
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Transport = require "RadioSurvivor/RS_Transport"
local Personas = require "RadioSurvivor/RS_Personas"
-- Historique radio par personnage du carnet (E06-T04) : phrases dites, réponses, lignes entendues.
local Log = require "RadioSurvivor/RS_RadioLog"
-- Réponse radio structurée (E07-T01) : RSV2 comme les PNJ, actions jugées par RS_Actions.
local Codec = require "RadioSurvivor/RS_Codec"
local Actions = require "RadioSurvivor/RS_Actions"
-- Mémoire des voix (E07-T03) : exécuteur remember enregistré au chargement ; faits joints aux demandes (memory=).
local Memory = require "RadioSurvivor/RS_Memory"
-- État dynamique des voix (E07-T06) : exécuteur persona_state enregistré au chargement ; état joint (persona=).
local PersonaState = require "RadioSurvivor/RS_PersonaState"
-- Repère sur la carte (E07-T04) : exécuteur mark_map enregistré au chargement (rien d'autre à appeler ici).
require "RadioSurvivor/RS_MapMarks"
-- Mission donnée par une voix (E11-T08) : exécuteur start_mission enregistré au chargement ; compte rendu et contexte
-- de la mission joints aux demandes de l'appelant à cette voix (mission=).
local VoiceMissions = require "RadioSurvivor/RS_MissionVoice"; require "RadioSurvivor/RS_Caches" -- E11-T06: place_cache
-- Livre du passeur (E13-T02) : exécuteur propose_trade enregistré au chargement ; contexte joint (trade=).
local Trade = require "RadioSurvivor/RS_Trade"; local GroupRadio = require "RadioSurvivor/RS_GroupRadio" -- E08-T06
local Rep = require "RadioSurvivor/RS_Reputation" -- E04-T10: reputation of the caller in the voice request
local Comfort = require "RadioSurvivor/RS_Comfort" -- E05-T15: an answer on the air eases boredom and unhappiness
local Bonds = require "RadioSurvivor/RS_VoiceBonds" -- E07-T10: answers counted for an exceptional share_frequency

-- Demandes transmises au pont, dans l'ordre d'arrivée.
local pending = {}
-- Clé de l'appelant → instant (réel) de sa dernière demande acceptée.
local lastTalkMs = {}
-- Clé de l'appelant → instants (réels) de ses phrases reçues dans la fenêtre anti-spam, toutes fréquences.
local talkTimes = {}
-- Instants des demandes acceptées pendant la dernière heure (plafond global).
local acceptedTimes = {}
-- Identifiant de voix -> instants de ses demandes acceptées pendant la dernière heure (budget= de la fiche).
local voiceTimes = {}
-- Diffusions en attente { khz, lines, cid, onAir } : une réponse ne coupe jamais celle en cours (cid : personnage du
-- carnet de l'appelant, nil pour un appel spontané ; onAir : appelé quand la diffusion commence, E05-T15).
local airQueue = {}
local nextPollMs = 0
local sequence = 0

-- Identité de l'appelant : nom de compte en multijoueur ; en solo, le nom change à chaque
-- personnage, une seule clé suffit.
local function callerKey(player)
    if isServer() then return player:getUsername() end
    return "solo"
end

local function findPlayer(key)
    if not isServer() then return getPlayer() end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player:getUsername() == key then return player end
    end
    return nil
end

local function notify(key, command, args)
    local player = findPlayer(key)
    if player then Const.toClient(player, command, args) end
end

-- Partie courante, pour séparer les conversations dans le pont.
local function sessionKey()
    local world = getWorld()
    return Const.oneLine(world:getGameMode() .. "_" .. world:getWorld())
end

local function inGameDate()
    local gt = getGameTime()
    return string.format("%04d-%02d-%02d %02d:%02d", gt:getYear(), gt:getMonth() + 1, gt:getDay() + 1,
        gt:getHour(), gt:getMinutes())
end

-- Chaîne --------------------------------------------------------------------------------------

-- À chaque chargement du monde (ZomboidRadio.java:246) : les chaînes ne sont pas sauvegardées. RS_Personas
-- installe les fiches livrées, lit le dossier et crée une chaîne par fréquence servie. Les options sandbox sont
-- déjà chargées à ce moment. Après un rechargement du Lua (OnLoadRadioScripts ne se redéclenche pas), la
-- relecture périodique reprend les chaînes existantes. isNewGame (monde neuf) : les fréquences des voix à plages
-- sont tirées de nouveau (E05-T07).
local function onLoadRadioScripts(scriptManager, isNewGame)
    Personas.onLoadRadioScripts(scriptManager, isNewGame)
end

local function minuteOfDay()
    local gt = getGameTime()
    return gt:getHour() * 60 + gt:getMinutes()
end

-- Diffuse la tête de file dès que sa chaîne est libre ; une diffusion dont la chaîne a disparu (fiche
-- modifiée, voix retirée) est abandonnée.
local function airNext()
    while #airQueue > 0 do
        local head = airQueue[1]
        local channel = Personas.channel(head.khz)
        if channel then
            if channel:getAiringBroadcast() ~= nil then return end
            table.remove(airQueue, 1)
            sequence = sequence + 1
            local bc = RadioBroadCast.new("RSV-" .. tostring(sequence), -1, -1)
            local c = Const.LINE_COLOR
            for _, text in ipairs(head.lines) do
                -- Code de voix sur chaque ligne (Const.LINE_CODE) : couleur de la bulle MP du récepteur commun.
                bc:AddRadioLine(RadioLine.new(text, c.r, c.g, c.b, Const.LINE_CODE))
            end
            channel:setAiringBroadcast(bc)
            Log.broadcast(head.khz, head.lines, head.cid)
            if head.onAir then head.onAir() end
            return
        end
        table.remove(airQueue, 1)
    end
end

local function queueAir(khz, lines, cid, onAir)
    if not khz then return end
    airQueue[#airQueue + 1] = { khz = khz, lines = lines, cid = cid, onAir = onAir }
    airNext()
end

-- Fichiers d'échange avec le pont -------------------------------------------------------------

local function writeRequests()
    return Transport.setRadio(pending, sessionKey())
end

-- Ligne de réponse filtrée (balises, longueur) ; "" si rien ne reste. Le jeu interprète les balises <...> : seuls les
-- parasites vanilla passent.
local function replyLine(value)
    local text = Const.oneLine(value)
    if not string.match(text, "^<%a%a%a%a>$") then
        text = string.gsub(text, "[<>]", "")
    end
    if string.len(text) > Const.MAX_LINE_CHARS then
        text = string.sub(text, 1, Const.MAX_LINE_CHARS)
    end
    return text
end

-- Réponse radio structurée (E07-T01) : payload= RSV2 { version = 2, kind = "radio_reply", id, say = { lignes },
-- actions = { ... } } du même identifiant que resp=. Les lignes say repassent par le filtrage de line= ; nil si la
-- charge n'est pas une réponse radio de cet identifiant (une réponse PNJ npc_reply ou ack_reply, lue par
-- RS_Transport.readNpc dans le même fichier, est ignorée ici).
local function structuredReply(id, hex)
    local raw = Codec.unhexBytes(hex)
    local value = raw and Codec.decodeBytes(raw)
    if type(value) ~= "table" or value.version ~= 2 or value.kind ~= "radio_reply" or value.id ~= id then return nil end
    local lines = {}
    if type(value.say) == "table" then
        for _, line in ipairs(value.say) do
            if type(line) == "string" and #lines < Const.MAX_LINES then
                local text = replyLine(line)
                if text ~= "" then lines[#lines + 1] = text end
            end
        end
    end
    return lines, type(value.actions) == "table" and value.actions or nil
end

-- Réponses du pont : identifiant → lignes, et identifiant → actions proposées (réponse structurée) ; nil si le
-- fichier est absent ou incomplet.
local function readResponses()
    local reader = getFileReader(Const.RESPONSES_FILE, false)
    if not reader then return nil end
    local responses, actions, current, currentId, complete = {}, {}, nil, nil, false
    local line = reader:readLine()
    while line do
        if line == "end" then
            complete = true
            break
        end
        local key, value = string.match(line, "^(%a+)=(.*)$")
        if key == "resp" then
            current, currentId = {}, value
            responses[value] = current
        elseif key == "line" and current and #current < Const.MAX_LINES then
            local text = replyLine(value)
            if text ~= "" then current[#current + 1] = text end
        elseif key == "payload" and current then
            local lines, proposed = structuredReply(currentId, value)
            if lines then
                current = lines
                responses[currentId] = lines
                actions[currentId] = proposed
            end
        end
        line = reader:readLine()
    end
    reader:close()
    if not complete then return nil end
    return responses, actions
end

-- Réconfort social (E05-T15) : quand la réponse d'une voix à l'appelant passe à l'antenne, son personnage (s'il est
-- toujours connecté et le même) perd un peu d'ennui et de tristesse (RS_Comfort). Partagé avec RS_GroupRadio.
local function comfortOnAir(caller, cid)
    return function()
        local player = findPlayer(caller)
        if player then Comfort.answered(player, cid, Log.characterOf(player)) end
    end
end

-- Demandes des joueurs ------------------------------------------------------------------------

local function isInteger(n)
    return type(n) == "number" and n == math.floor(n)
end

-- Radio émettrice tenue en main ou portée sur le dos, éventuellement désignée par son identifiant (Const.isCarriedRadio :
-- prédicat partagé de Belt Walkie-Talkie, jamais à la ceinture ni rangée, décision 4). getItemWithID ne cherche que
-- dans l'inventaire principal, où restent les objets en main. Le serveur ne connaît l'allumage et le canal que des
-- radios tenues en main (GameServer.java:3499-3519), le micro jamais : ces réglages sont vérifiés côté client. En MP,
-- la phrase dite part aussi sur la radio par le vanilla depuis une radio de l'inventaire principal
-- (ChatManager.getTransmittingRadio, VoiceManagerData) ; en solo, seule la radio équipée la transmet
-- (ZomboidRadio.java:500-539), sans auditeur autre que le joueur.
local function carriedRadio(player, itemId)
    local candidates = { player:getPrimaryHandItem(), player:getSecondaryHandItem(), player:getClothingItem_Back() }
    if itemId ~= nil and isInteger(itemId) then
        local inventory = player:getInventory()
        candidates[4] = inventory and inventory:getItemWithID(itemId) or nil
    end
    for i = 1, 4 do
        local item = candidates[i]
        if item and instanceof(item, "Radio") and (itemId == nil or item:getID() == itemId)
                and Const.isCarriedRadio(player, item) then
            local data = item:getDeviceData()
            if data and data:getIsTwoWay() then return item end
        end
    end
    return nil
end

-- Radio posée (IsoWaveSignal) désignée par le client : case x, y, z et index dans la case, la clé du paquet vanilla
-- RadioDeviceDataState (GameServer.java:3480-3498). Index périmé (objets de la case réordonnés) : repli sur la seule
-- radio posée de la case, s'il n'y en a qu'une.
local function worldRadio(args)
    local x, y, z, index = tonumber(args.x), tonumber(args.y), tonumber(args.z), tonumber(args.index)
    if not isInteger(x) or not isInteger(y) or not isInteger(z) then return nil end
    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    if not sq then return nil end
    local objects = sq:getObjects()
    if isInteger(index) and index >= 0 and index < objects:size() then
        local obj = objects:get(index)
        if instanceof(obj, "IsoWaveSignal") then return obj end
    end
    local found = nil
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoWaveSignal") then
            if found then return nil end
            found = obj
        end
    end
    return found
end

-- Appareil d'où part la phrase, contrôlé par le serveur (E06-T03) : rend l'appareil (objet qui expose
-- getDeviceData) et sa source, ou nil et le motif de refus. Ce que le serveur sait :
-- - radio d'inventaire : allumage et canal connus seulement en main, micro jamais : jugés par le client ;
-- - radio posée (IsoWaveSignal) et autoradio (VehiclePart) : allumage et canal appliqués par le serveur à chaque
--   changement d'un client (GameServer.java:3480-3530, DeviceData.java:1088-1112 ; pile et courant revérifiés par
--   setIsTurnedOn, DeviceData.java:470-488), micro jamais transmis (setMicIsMuted, DeviceData.java:371-378) ;
-- - émettrice, haut de gamme, bornes de réglage et portée du micro : données de l'objet sauvegardées avec lui
--   (DeviceData.java:1228-1260 ; autoradio : recopiées de la radio installée, Vehicles.lua Create.Radio_HAM) ;
-- - places d'un véhicule : tenues par le serveur (VehicleEnterPacket.java:71-72, BaseVehicle.getSeat).
-- Une radio posée n'a pas de propriétaire : tout joueur à portée de son micro peut l'utiliser, comme en vanilla.
local function findRadio(player, args)
    local source = args.source
    if source == nil or source == Const.SOURCE.ITEM then
        local radio = carriedRadio(player, tonumber(args.itemId))
        if not radio then return nil, "NoRadio" end
        return radio, Const.SOURCE.ITEM
    end
    if source == Const.SOURCE.WORLD then
        local radio = worldRadio(args)
        local data = radio and radio:getDeviceData()
        if not data or not data:getIsTwoWay() then return nil, "NoRadio" end
        local sq = radio:getSquare()
        if not Const.inMicRange(player, data, sq:getX(), sq:getY(), sq:getZ()) then return nil, "TooFar" end
        if not data:getIsTurnedOn() then return nil, "Off" end
        return radio, source
    end
    if source == Const.SOURCE.VEHICLE then
        local vehicle = player:getVehicle()
        local vehicleId = tonumber(args.vehicleId)
        if not Const.inVehicle(player, vehicle) or (vehicleId ~= nil and vehicle:getId() ~= vehicleId) then
            return nil, "NotInVehicle"
        end
        local part = type(args.part) == "string" and vehicle:getPartById(args.part) or nil
        local data = part and part:getDeviceData()
        -- Seule l'autoradio du gabarit Radio_HAM est émettrice (Vehicles.lua : getIsTwoWay recopié de la radio).
        if not data or not data:getIsTwoWay() then return nil, "NoRadio" end
        if not data:getIsTurnedOn() then return nil, "Off" end
        return part, source
    end
    return nil, "NoRadio"
end

-- Nom de l'appareil pour le pont : nom de l'objet d'inventaire, sinon celui du DeviceData (radio posée, autoradio).
local function radioName(radio, source)
    if source == Const.SOURCE.ITEM then return radio:getDisplayName() end
    local name = radio:getDeviceData():getDeviceName()
    if type(name) ~= "string" or name == "" then return "Radio" end
    return name
end

local function hasPending(key)
    for _, req in ipairs(pending) do
        -- A mission briefing (E11-T09) is the voice speaking on its own: the caller may still talk.
        if req.caller == key and not req.briefing then return true end
    end
    return GroupRadio.waiting(key) -- E08-T06: call to a group voice still unanswered
end

-- Instants de la dernière heure réelle seulement.
local function lastHour(times, now)
    local kept = {}
    for _, t in ipairs(times or {}) do
        if now - t < 3600000 then kept[#kept + 1] = t end
    end
    return kept
end

local function underHourlyCap(now)
    acceptedTimes = lastHour(acceptedTimes, now)
    local max = Const.maxPerHour()
    return max == 0 or #acceptedTimes < max
end

-- Budget propre à la voix (budget= de la fiche, demandes par heure réelle), en plus du plafond global ; 0 = seul le
-- plafond global.
local function underVoiceBudget(sheet, now)
    voiceTimes[sheet.id] = lastHour(voiceTimes[sheet.id], now)
    return sheet.budget == 0 or #voiceTimes[sheet.id] < sheet.budget
end

-- La radio peut-elle atteindre cette fréquence ? Les bornes de réglage viennent du script de l'objet (Item.java,
-- setMinChannelRange/setMaxChannelRange à la création) et sont sauvegardées avec lui : le serveur les connaît pour
-- toute radio, contrairement au canal réglé (connu seulement pour une radio tenue en main, et peut-être périmé).
local function radioReaches(radio, khz)
    local data = radio:getDeviceData()
    local low, high = data:getMinChannelRange(), data:getMaxChannelRange()
    if type(low) ~= "number" or type(high) ~= "number" or high <= 0 then return true end
    return khz >= low and khz <= high
end

-- Radio exigée par la fiche : radio=high_tier demande un poste haut de gamme (DeviceData.getIsHighTier, 42.21 :
-- IsHighTier du script, WalkieTalkie5, ManPackRadio, HamRadio2, ou radio bricolée réussie ; DeviceData.java:249).
local function radioAccepted(sheet, radio)
    if sheet.radio ~= "high_tier" then return true end
    return radio:getDeviceData():getIsHighTier() == true
end

-- Anti-spam par joueur, toutes fréquences confondues (E05-T08) : au plus Const.SPAM_MAX phrases reçues par
-- Const.SPAM_WINDOW_MS réelles. Le client s'impose déjà un écart minimal (Const.CLIENT_MIN_INTERVAL_MS) qui reste
-- sous ce seuil : seul un client modifié l'atteint. Compte toute phrase reçue, même refusée ensuite.
local function underSpamLimit(key, now)
    local kept = {}
    for _, t in ipairs(talkTimes[key] or {}) do
        if now - t < Const.SPAM_WINDOW_MS then kept[#kept + 1] = t end
    end
    talkTimes[key] = kept
    if #kept >= Const.SPAM_MAX then return false end
    kept[#kept + 1] = now
    return true
end

-- La phrase part sur la radio (le client la prononce) et personne ne répond : même suite de commandes pour une
-- fréquence sans voix, une voix silencieuse, hors de ses heures, une radio trop faible ou un budget de voix épuisé,
-- pour ne rien révéler de la fréquence. Rien n'est envoyé au pont ; ni délai, ni plafond, ni budget consommés.
-- khz : fréquence contrôlée de la radio (phrase inscrite à l'historique), nil si illisible ou hors de portée.
local function silence(player, text, khz)
    if khz then Log.spoken(player, khz, text) end
    Const.toClient(player, Const.CMD.ACCEPTED, { text = text })
    Const.toClient(player, Const.CMD.DONE)
end

-- Ordre des contrôles (E05-T08) : tout ce qui peut refuser une phrase avec un message (option, radio, anti-spam,
-- attente, délai entre deux demandes, plafond global, file pleine) est jugé AVANT de regarder la fréquence, de la
-- même façon sur toutes les fréquences : un refus n'indique jamais si une voix y écoute. Ensuite, seule une voix
-- active, à l'écoute, joignable par cette radio et sous son budget coûte une demande au pont.
local function onTalk(player, args)
    local function reject(reason)
        Const.toClient(player, Const.CMD.REJECTED, { reason = reason })
    end
    if not Const.isEnabled() then return reject("Disabled") end
    local text = Const.oneLine(type(args) == "table" and args.text or "")
    if text == "" then return end
    if string.len(text) > Const.MAX_INPUT_CHARS then
        text = string.sub(text, 1, Const.MAX_INPUT_CHARS)
    end
    local radio, source = findRadio(player, type(args) == "table" and args or {})
    if not radio then return reject(source) end

    local key = callerKey(player)
    local now = getTimestampMs()
    if not underSpamLimit(key, now) then return reject("Spam") end
    if hasPending(key) then return reject("Waiting") end
    if lastTalkMs[key] and now - lastTalkMs[key] < Const.playerCooldownMs() then return reject("Cooldown") end
    if #pending >= Const.MAX_PENDING or not underHourlyCap(now) then return reject("Busy") end

    -- Routage : la fréquence de la radio désigne la voix. Radio d'inventaire : le client la donne (le serveur ne
    -- connaît le canal que d'une radio tenue en main, et un état réglé hors de la main y reste périmé : pas de
    -- comparaison possible). Radio posée et autoradio : le serveur connaît le canal et le prend ; une fréquence
    -- annoncée par le client qui en diffère (réglage changé à l'instant, paquet d'état pas encore arrivé) donne le
    -- silence. Le serveur contrôle que la fréquence est entière, que la radio peut l'atteindre et qu'une voix y a
    -- sa chaîne. Sans fréquence lisible ou hors de portée de la radio : silence, comme sur une fréquence sans voix.
    local khz = type(args) == "table" and tonumber(args.channel) or nil
    if source ~= Const.SOURCE.ITEM then
        local known = radio:getDeviceData():getChannel()
        if khz ~= nil and khz ~= known then khz = nil else khz = known end
    end
    if not isInteger(khz) or not radioReaches(radio, khz) then return silence(player, text, nil) end
    local voiceId = Personas.voiceAt(khz)
    local sheet = voiceId and Personas.get(voiceId)
    if not sheet or not Personas.isServed(voiceId, khz) or not Personas.channel(khz) then
        return silence(player, text, khz)
    end
    -- Voix d'un groupe équipé (E08-T06) : la phrase devient une demande du PNJ qui répond, dans la file et sous les
    -- quotas du carnet (RS_GroupRadio) ; un refus là-bas donne le silence, comme une voix muette.
    if sheet.group then
        local language = Const.callLanguage() or (Translator and Translator.getLanguage
            and tostring(Translator.getLanguage():name())) or "EN"
        local req, why = GroupRadio.talk(player, key, sheet, khz, text, language, Log.characterOf(player))
        if not req then
            Const.log("group radio: call on voice '" .. sheet.id .. "' not sent: " .. tostring(why))
            return silence(player, text, khz)
        end
        lastTalkMs[key] = now
        Log.spoken(player, khz, text)
        Const.toClient(player, Const.CMD.ACCEPTED, { text = text })
        return
    end
    -- Voix silencieuse (state=silent), hors de ses heures d'écoute, radio trop faible pour elle (radio=high_tier et
    -- poste ordinaire) ou budget de la voix épuisé : silence (ni parasites qui trahiraient une présence).
    if sheet.state ~= "active" or not Personas.isListening(sheet, minuteOfDay()) or not radioAccepted(sheet, radio)
            or not underVoiceBudget(sheet, now) then
        return silence(player, text, khz)
    end

    local desc = player:getDescriptor()
    local req = {
        id = string.format("%.0f", now) .. "-" .. tostring(ZombRand(100000, 999999)),
        sentAt = now,
        caller = Const.oneLine(key),
        voice = sheet.id,
        khz = khz,
        name = Const.oneLine(desc:getForename() .. " " .. desc:getSurname()),
        date = inGameDate(),
        days = string.format("%.1f", player:getHoursSurvived() / 24),
        radio = Const.oneLine(radioName(radio, source)),
        text = text,
        cid = Log.characterOf(player),
    }
    -- Souvenirs de cette voix sur cet appelant et ce personnage (E07-T03), absents s'il n'y en a pas.
    req.memory = Memory.field(sheet.id, req.caller, req.cid)
    -- État dynamique de la voix (E07-T06), absent tant qu'elle ne l'a jamais changé.
    req.persona = PersonaState.field(sheet.id)
    -- Mission de cette voix pour ce personnage (E11-T08), absente sinon. E11-T13 : rien n'est jugé ici ; objectif
    -- rempli (sondage serveur), turn = report_due : le modèle de la voix reconnaît le compte rendu et rend l'action
    -- report_mission, revérifiée par son exécuteur (RS_MissionVoice) ; avant, turn = not_yet.
    req.mission = VoiceMissions.field(VoiceMissions.heard(sheet, player, req.cid, khz))
    req.trade = Trade.field(sheet, req.caller, req.cid) -- E13-T02 : voix qui autorise propose_trade seulement
    -- E04-T10 (Q10) : réputation du personnage appelant (niveau et dernier acte public, hexadécimal RSV2), absente sans
    -- personnage du carnet ; jamais de score. Écrite par RS_Transport.write (clé reputation).
    local reputation = req.cid and Rep.publicContext(req.cid) or nil
    req.reputation = reputation and Codec.hexBytes(Codec.encodeBytes(reputation)) or nil
    pending[#pending + 1] = req
    if not writeRequests() then
        table.remove(pending)
        return reject("Bridge")
    end
    lastTalkMs[key] = now
    acceptedTimes[#acceptedTimes + 1] = now
    voiceTimes[sheet.id][#voiceTimes[sheet.id] + 1] = now
    Log.spoken(player, khz, text)
    Const.toClient(player, Const.CMD.ACCEPTED, { text = text })
end

local function onClientCommand(module, command, player, args)
    if module ~= Const.MODULE then return end
    -- Toute autre commande est ignorée (dont « frequencies » d'un client antérieur à E05-T08 : plus de liste).
    if command == Const.CMD.TALK then
        onTalk(player, args)
    elseif command == Const.CMD.HEARD then
        Log.heard(player, args)
    elseif command == Const.CMD.HISTORY then
        Log.sendAll(player)
    elseif command == Const.CMD.NOTE_READ then
        Log.noteRead(player, args)
    end
end

-- Appels spontanés (E05-T05) -------------------------------------------------------------------

-- Traductions des mods rechargées une fois sur un serveur MP : elles y sont lues avant les mods (getText rend alors
-- la clé brute, base api-42-21.md « un serveur MP ne connaît pas celles des mods »). Une ligne radio n'est jamais
-- traduite par le client : le texte doit être composé ici, dans la langue du processus serveur.
local translationsReloaded = false
-- Clés call_text introuvables déjà signalées (une ligne de journal par clé).
local missingCallText = {}

-- Texte fixe de l'appel (call_text de la fiche, %1 = fréquence affichée), ou nil si la clé n'existe pas.
local function callText(sheet, khz)
    local key = sheet.call_text
    if getTextOrNull(key) == nil and isServer() and not translationsReloaded then
        translationsReloaded = true
        Translator.loadFiles()
        Const.log("mod translations reloaded on the server (call text '" .. key .. "' was missing)")
    end
    if getTextOrNull(key) == nil then
        if not missingCallText[key] then
            missingCallText[key] = true
            Const.log("call of voice '" .. sheet.id .. "' skipped: no translation for call_text '" .. key .. "'")
        end
        return nil
    end
    return getText(key, Const.frequencyLabel(khz))
end

-- Langue des textes composés par l'autorité (celle du joueur en solo, du processus serveur en MP) : sans option
-- CallLanguage, le texte du pont et le texte fixe parlent la même langue.
local function authorityLanguage()
    local language = Translator and Translator.getLanguage and Translator.getLanguage()
    return language and tostring(language:name()) or "EN"
end

-- Langue d'un appel spontané (E05-T12) : option sandbox CallLanguage, la même pour tous les joueurs ; par défaut celle
-- de l'autorité. Seul le texte du pont la suit : le texte fixe de repli (callText) reste dans la langue de l'autorité.
local function callLanguage()
    return Const.callLanguage() or authorityLanguage()
end

-- Diffuse un appel sur la fréquence de sa voix, si elle peut encore appeler à cet instant : option, état, heures
-- d'écoute et fréquence revérifiés (le texte du pont arrive plusieurs secondes après le tirage). lines : texte du
-- pont (parasites seuls ou vide = texte fixe de la fiche).
local function airCall(req, lines)
    local sheet = Personas.get(req.voice)
    if not Const.isEnabled() or not Const.spontaneousCalls() or not sheet or sheet.state ~= "active"
            or not Personas.isListening(sheet, minuteOfDay()) or not Personas.isServed(req.voice, req.khz) then
        Const.log("call of voice '" .. req.voice .. "' dropped: the voice can no longer call")
        return
    end
    local words = {}
    for _, line in ipairs(lines or {}) do
        if not string.match(line, "^<%a%a%a%a>$") and #words < Const.CALL_MAX_LINES then words[#words + 1] = line end
    end
    if #words == 0 then
        local text = callText(sheet, req.khz)
        if not text then return end
        words = { text }
    end
    table.insert(words, 1, "<fzzt>")
    words[#words + 1] = "<szzt>"
    queueAir(req.khz, words)
end

-- Personne ne parle sur cette voix : aucune demande en attente pour elle, rien en file ni à l'antenne sur sa
-- fréquence.
local function voiceIdle(id, khz)
    for _, req in ipairs(pending) do
        if req.voice == id then return false end
    end
    for _, item in ipairs(airQueue) do
        if item.khz == khz then return false end
    end
    local channel = Personas.channel(khz)
    return channel ~= nil and channel:getAiringBroadcast() == nil
end

-- À chaque heure de jeu, chaque voix active, dans ses heures d'écoute, avec call_one_in > 0, sur sa première
-- fréquence servie et sans conversation en cours, tire une chance sur call_one_in. Une seule voix appelle par heure
-- (tirée au sort parmi les gagnantes) : un appel consomme une place du plafond global MaxPerHour, commun avec les
-- réponses, et du budget de la voix ; plafond ou budget atteints : pas d'appel. Le texte est demandé au pont
-- (kind=radio_call, docs/protocole-carnet-v2.md) ; pont absent ou muet après CALL_TIMEOUT_MS : texte fixe call_text.
local function onEveryHours()
    if not Const.isEnabled() or not Const.spontaneousCalls() then return end
    local minute = minuteOfDay()
    local winners = {}
    for _, id in ipairs(Personas.ids()) do
        local sheet = Personas.get(id)
        local khz = Personas.served(id)[1]
        if sheet and khz and sheet.state == "active" and sheet.call_one_in > 0 and Personas.isListening(sheet, minute)
                and voiceIdle(id, khz) and ZombRand(sheet.call_one_in) == 0 then
            winners[#winners + 1] = { sheet = sheet, khz = khz }
        end
    end
    if #winners == 0 then return end
    local pick = winners[1]
    if #winners > 1 then pick = winners[ZombRand(#winners) + 1] end
    local now = getTimestampMs()
    if #pending >= Const.MAX_PENDING or not underHourlyCap(now) or not underVoiceBudget(pick.sheet, now) then return end
    acceptedTimes[#acceptedTimes + 1] = now
    voiceTimes[pick.sheet.id][#voiceTimes[pick.sheet.id] + 1] = now
    local req = {
        id = string.format("%.0f", now) .. "-" .. tostring(ZombRand(100000, 999999)) .. "-call",
        sentAt = now,
        kind = "radio_call",
        call = true,
        voice = pick.sheet.id,
        khz = pick.khz,
        date = inGameDate(),
        language = callLanguage(),
    }
    pending[#pending + 1] = req
    if not writeRequests() then
        table.remove(pending)
        airCall(req, nil)
    end
end

-- Consignes de mission (E11-T09) ------------------------------------------------------------------

-- Texte « utilisateur » d'une demande de consigne : l'appelant reste à l'écoute (jamais dit par le joueur, ni dans
-- son historique). La voix répond avec la consigne du prompt (mission=, turn = briefing).
local BRIEFING_TEXT = "(stays on the line and waits for the details of the job)"
-- Demandes de consigne créées pendant le jugement des actions d'onTick, ajoutées à pending après la boucle.
local briefings = {}

-- RS_MissionVoice.onStarted : une mission de voix vient d'être créée par start_mission. ctx.request : la demande dont
-- la réponse a proposé l'action (même appelant, même voix, même fréquence). Une seule demande de plus, hors plafond
-- horaire et budget (elle prolonge l'échange qui a donné la mission), dans la limite de MAX_PENDING.
VoiceMissions.onStarted = function(m, ctx)
    local src = type(ctx) == "table" and ctx.request or nil
    if type(src) ~= "table" or src.call or src.briefing then return end
    if #pending + #briefings >= Const.MAX_PENDING then
        Const.log("voice mission " .. tostring(m.id) .. ": no briefing (too many pending requests)")
        return
    end
    local now = getTimestampMs()
    local req = {
        id = string.format("%.0f", now) .. "-" .. tostring(ZombRand(100000, 999999)) .. "-brief",
        sentAt = now,
        briefing = true,
        caller = src.caller,
        voice = src.voice,
        khz = src.khz,
        name = src.name,
        date = inGameDate(),
        days = src.days,
        radio = src.radio,
        text = BRIEFING_TEXT,
        cid = src.cid,
    }
    req.memory = Memory.field(src.voice, src.caller, src.cid)
    req.persona = PersonaState.field(src.voice)
    req.mission = VoiceMissions.field(VoiceMissions.context(m, "briefing"))
    req.trade = Trade.field(Personas.get(src.voice), src.caller, src.cid) -- E13-T02
    briefings[#briefings + 1] = req
end

-- Boucle --------------------------------------------------------------------------------------

local function onTick()
    airNext()
    if #pending == 0 then return end
    local now = getTimestampMs()
    if now < nextPollMs then return end
    nextPollMs = now + Const.POLL_MS

    local responses, proposed = readResponses()
    responses, proposed = responses or {}, proposed or {}
    local kept, changed = {}, false
    for _, req in ipairs(pending) do
        local lines = responses[req.id]
        if req.call then
            if lines or now - req.sentAt > Const.CALL_TIMEOUT_MS then
                changed = true
                airCall(req, lines)
            else
                kept[#kept + 1] = req
            end
        elseif req.handler then
            -- Demande d'un autre module serveur (RS_RadioServer.submit, E14-T02 bulletin du soir) : son handler diffuse
            -- le texte du pont ou son texte de secours (lines = nil après req.timeoutMs).
            if lines or now - req.sentAt > (req.timeoutMs or Const.CALL_TIMEOUT_MS) then
                changed = true
                req.handler(req, lines)
            else
                kept[#kept + 1] = req
            end
        elseif lines then
            changed = true
            table.insert(lines, 1, "<bzzt>")
            -- E05-T15 : une consigne (E11-T09) ne réconforte pas ; une réponse à la phrase du joueur, si.
            queueAir(req.khz, lines, req.cid, (not req.briefing) and comfortOnAir(req.caller, req.cid) or nil)
            if not req.briefing then Bonds.answered(req.cid, req.voice) end
            -- A briefing (E11-T09) is not an answer the caller waits for.
            if not req.briefing then notify(req.caller, Const.CMD.DONE) end
            -- Actions proposées (E07-T01) : jugées après la mise en file de la diffusion, contre la fiche actuelle.
            -- request : la demande d'origine, pour la consigne d'une mission créée (E11-T09).
            if proposed[req.id] then
                Actions.decide(Personas.get(req.voice), req.caller, proposed[req.id], now,
                    { player = findPlayer(req.caller), khz = req.khz, cid = req.cid, day = string.sub(inGameDate(), 1, 10),
                      request = req })
            end
        elseif req.briefing and now - req.sentAt > Const.TIMEOUT_MS then
            -- Consigne sans réponse : rien à l'antenne, l'appelant n'attend rien ; le carnet montre les indices.
            changed = true
            Const.log("no answer from the bridge for the mission briefing " .. req.id)
        elseif now - req.sentAt > Const.TIMEOUT_MS then
            changed = true
            Const.log("no answer from the bridge for " .. req.id .. " (is bridge\\radio_bridge.py running?)")
            queueAir(req.khz, { "<fzzt>", "<szzt>" })
            notify(req.caller, Const.CMD.REJECTED, { reason = "NoAnswer" })
        else
            kept[#kept + 1] = req
        end
    end
    for _, req in ipairs(briefings) do
        kept[#kept + 1] = req
        changed = true
    end
    briefings = {}
    if changed then
        pending = kept
        writeRequests()
    end
end

-- Relecture périodique des fiches, même en pause : sur un serveur dédié vide (PauseEmpty), seul
-- OnTickEvenPaused est déclenché.
local function onTickEvenPaused()
    Personas.tick(getTimestampMs())
    GroupRadio.tick(getTimestampMs()) -- E08-T06: generated voices, calls left unanswered
end

-- API pour les autres modules serveur (E14-T02, bulletin du soir de RS_Facts) --------------------------------
-- frequency(id) : première fréquence servie d'une voix active, ou nil. submit(req) : demande au pont hors des
-- phrases des joueurs (champs écrits par RS_Transport : kind, voice, date, language, facts ; hors plafond horaire) ;
-- req.handler(req, lignes ou nil) est appelé à la réponse ou après req.timeoutMs ; false si la file est pleine ou le
-- fichier d'échange impossible à écrire. air(khz, lignes) : met en file une diffusion sur la chaîne de la voix.
RS_RadioServer = {
    frequency = function(id)
        local sheet = Personas.get(id)
        if not sheet or sheet.state ~= "active" then return nil end
        return Personas.served(id)[1]
    end,
    submit = function(req)
        if #pending >= Const.MAX_PENDING then return false end
        local now = getTimestampMs()
        req.id = string.format("%.0f", now) .. "-" .. tostring(ZombRand(100000, 999999)) .. "-" .. tostring(req.kind)
        req.sentAt = now
        pending[#pending + 1] = req
        if not writeRequests() then
            table.remove(pending)
            return false
        end
        return true
    end,
    air = function(khz, lines) queueAir(khz, lines) end,
    date = inGameDate,
    language = callLanguage,
}

GroupRadio.bind(queueAir, notify, comfortOnAir) -- E08-T06: group replies on the air, caller told (E05-T15: comforted)
Events.OnLoadRadioScripts.Add(onLoadRadioScripts)
Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
Events.OnTickEvenPaused.Add(onTickEvenPaused)
Events.EveryHours.Add(onEveryHours)
