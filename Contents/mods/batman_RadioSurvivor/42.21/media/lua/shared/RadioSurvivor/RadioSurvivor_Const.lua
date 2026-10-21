-- Radio Survivor : constantes, options sandbox et transport client ↔ serveur.
-- La fréquence de Walt n'est plus une option sandbox : elle vient de sa fiche (server/RadioSurvivor/RS_Personas.lua).
-- Le Lua du jeu n'a aucun accès réseau : le serveur (ou le jeu solo) échange avec le programme pont
-- (bridge\radio_bridge.py) par deux fichiers texte sous Zomboid\Lua\batman_RadioSurvivor\.
local Const = {}

Const.TAG = "[RadioSurvivor]"
Const.MODULE = "RadioSurvivor"
Const.CHANNEL_NAME = "Radio Survivor"
Const.CHANNEL_UUID = "batman_RadioSurvivor-channel-0001"
-- Début de l'identifiant (GUID) des chaînes des voix (RS_Personas) : chaînes déclarées au récepteur commun
-- Belt Walkie-Talkie (client/RadioSurvivor/RS_BeltRadio.lua).
Const.VOICE_CHANNEL_PREFIX = "batman_RadioSurvivor-voice-"

Const.REQUESTS_FILE = "batman_RadioSurvivor/requests.txt"
Const.RESPONSES_FILE = "batman_RadioSurvivor/responses.txt"
-- Journal admin des actions (E07-T02, server/RadioSurvivor/RS_ActionLog.lua) : au-delà de ces seuils, le fichier
-- courant devient actions-<partie>.1.log (l'ancien écrasé) et repart vide. Taille en caractères (unités Kahlua).
Const.ACTION_LOG_MAX_LINES = 2000
Const.ACTION_LOG_MAX_CHARS = 262144
-- Mémoire des voix (E07-T03, server/RadioSurvivor/RS_Memory.lua, action remember) : faits gardés par (voix, appelant,
-- personnage), le plus ancien évincé ; appelants gardés par voix, le moins récent évincé ; caractères par fait (la
-- borne des paramètres d'action de RS_Actions).
Const.MEMORY_MAX_FACTS = 5
Const.MEMORY_MAX_CALLERS = 50
Const.MEMORY_FACT_CHARS = 64
-- État dynamique des voix (E07-T06, server/RadioSurvivor/RS_PersonaState.lua, action persona_state) : moral et
-- réserves entiers de 0 à 10 (5 par défaut), changés d'au plus 2 par appel ; lieu dit par la voix, en caractères.
Const.PERSONA_LEVEL_MAX = 10
Const.PERSONA_LEVEL_DEFAULT = 5
Const.PERSONA_LEVEL_STEP = 2
Const.PERSONA_PLACE_CHARS = 40
-- Repère sur la carte (E07-T04, server/RadioSurvivor/RS_MapMarks.lua, action mark_map) : délai réel entre deux
-- repères d'une même voix (le délai de RS_Actions est par voix, tous appelants confondus).
Const.MAP_MARK_COOLDOWN_MS = 30000
-- Quartier révélé (E07-T05, server/RadioSurvivor/RS_MapMarks.lua, action reveal_area) : côté maximal du carré révélé
-- (cases), arrondi au nombre impair de blocs de 32 cases (WorldMapVisited) qui y tient, centré sur le bloc du lieu :
-- 160 = 5 blocs ; délai réel entre deux révélations d'une même voix.
Const.MAP_REVEAL_BLOCK = 32
Const.MAP_REVEAL_MAX_SIDE = 160
Const.MAP_REVEAL_COOLDOWN_MS = 60000
-- Mission donnée par une voix (E11-T08, server/RadioSurvivor/RS_MissionVoice.lua, action start_mission) : délai réel
-- entre deux missions lancées par une même voix (tous appelants confondus, délai de RS_Actions) ; le délai de M01
-- (RS_Config.OFFER_COOLDOWN_MS) s'y ajoute par appelant après la clôture de sa mission.
Const.START_MISSION_COOLDOWN_MS = 60000

Const.CMD = {
    -- client → serveur : { text, channel, source, ... } (channel : fréquence de la radio lue par le client, kHz).
    -- source (E06-T03) : nil ou "item" = radio d'inventaire { itemId } ; "world" = radio posée { x, y, z, index } ;
    -- "vehicle" = autoradio { vehicleId, part }. Un client antérieur n'envoie que { text, itemId, channel }.
    TALK = "talk",
    ACCEPTED = "accepted",  -- serveur → client : { text } phrase à prononcer (demande transmise ou silence)
    REJECTED = "rejected",  -- serveur → client : { reason }
    DONE = "done",          -- serveur → client : réponse mise en file de diffusion, ou personne ne répond
    -- Historique radio du carnet (E06-T04, server/RadioSurvivor/RS_RadioLog.lua) :
    HEARD = "heard",                 -- client → serveur : { khz, text } ligne reçue par une radio de ce client
    HISTORY = "history",             -- client → serveur : demande ; serveur → client : { character, frequencies }
    HISTORY_LINES = "history_lines", -- serveur → client : { character, khz, last, lines } une fréquence entière
    HISTORY_ADD = "history_add",     -- serveur → client : { character, khz, last, line } une ligne nouvelle
    -- E06-T07 : HISTORY (chaque fréquence), HISTORY_LINES et HISTORY_ADD portent aussi voice = { id, name, hours }
    -- quand le personnage connaît la voix de la fréquence (RS_RadioLog.voiceInfo).
    NOTE_READ = "note_read",         -- client → serveur : { itemId } note de fréquence ouverte (E06-T07)
    -- Plus de commande « frequencies » (E05-T08) : aucun client ne reçoit les fréquences des voix.
    -- Action mark_map (E07-T04) : serveur → client appelant seul, { x, y, z, label } un lieu de la fiche de la voix,
    -- ajouté par client/RadioSurvivor/RS_MapActions.lua comme symbole de la carte du monde du joueur.
    MAP_MARK = "map_mark",
    -- Action reveal_area (E07-T05) : serveur → client appelant seul, { x1, y1, x2, y2 } rectangle de cases (x2, y2
    -- exclus) aligné sur des blocs de 32 et plafonné, rendu « connu » sur la carte du monde (RS_MapActions.reveal).
    MAP_REVEAL = "map_reveal",
    -- Réconfort social (E05-T15, server/RadioSurvivor/RS_Comfort.lua) : serveur → client du personnage réconforté,
    -- { boredom, sadness } baisses réellement appliquées (0 = inchangée), affichées en halo par RS_RadioTalk.
    COMFORT = "comfort",
}

-- Délai réel d'abandon d'une demande radio (ms) : suit l'état du pont (E17-T16, « Battement du pont » en fin de fichier).
Const.TIMEOUT_MS = 90000
-- Appel spontané (E05-T05) : délai réel laissé au pont pour écrire le texte, avant le texte fixe de la fiche ; lignes
-- gardées au plus.
Const.CALL_TIMEOUT_MS = 30000
Const.CALL_MAX_LINES = 3
-- Le client oublie son attente un peu après le serveur (pont vivant compris), si aucune nouvelle n'arrive.
Const.CLIENT_TIMEOUT_MS = 160000
Const.POLL_MS = 500
Const.MAX_INPUT_CHARS = 200
-- Anti-spam (E05-T08) : écart minimal imposé par le client entre deux phrases (millisecondes réelles), et limite du
-- serveur par joueur, toutes fréquences confondues : SPAM_MAX phrases par SPAM_WINDOW_MS. 5 s d'écart donnent au
-- plus 12 phrases par minute, sous la limite du serveur : seul un client modifié l'atteint.
-- L'écart réel du client est Const.clientIntervalMs() : jamais moins que le délai du serveur entre deux demandes
-- (option PlayerCooldown, 10 s par défaut), plus une marge pour l'écart de latence entre deux envois, sinon le
-- serveur refuse en rouge (Cooldown) une phrase que le client laissait partir (essai solo du 2026-10-09).
Const.CLIENT_MIN_INTERVAL_MS = 5000
Const.CLIENT_COOLDOWN_MARGIN_MS = 1000
Const.SPAM_MAX = 15
Const.SPAM_WINDOW_MS = 60000
-- Demandes en attente simultanées, tous joueurs confondus.
Const.MAX_PENDING = 8
-- Garde-fous sur ce que le pont renvoie.
Const.MAX_LINES = 8
Const.MAX_LINE_CHARS = 140

Const.LINE_COLOR = { r = 1.0, g = 0.82, b = 0.55 }
-- Code posé sur chaque ligne diffusée par une voix (RadioLine, effets) : 4 caractères, ignoré par le vanilla
-- (ISRadioInteractions.checkPlayer ne traite que les jetons de plus de 4 caractères), transmis au client avec la
-- ligne (WaveSignalPacket) jusqu'à OnDeviceText. Le récepteur commun y reconnaît une voix pour colorer la bulle MP
-- d'une radio non tenue (fournisseur recognize, RS_BeltRadio.lua). Le même code pour toutes les voix : il ne révèle
-- aucune fréquence (E05-T08), le client n'apprend que celle qu'il écoute déjà.
Const.LINE_CODE = "RSVO"

-- Appareil d'où part une phrase (champ source de la commande talk, E06-T03).
Const.SOURCE = { ITEM = "item", WORLD = "world", VEHICLE = "vehicle" }
-- Portée du micro d'une radio posée quand l'appareil n'en donne pas : DeviceData.micRange vaut 5 par défaut
-- (zombie/radio/devices/DeviceData.java:70).
Const.DEFAULT_MIC_RANGE = 5

local KHZ_PER_MHZ = 1000
local OPTION_NAMESPACE = "RadioSurvivor."
local DEFAULTS = {
    Enabled = true,
    PlayerCooldown = 10,
    MaxPerHour = 60,
    SpontaneousCalls = true,
    NoteRarity = 3,
    CallLanguage = 1,
    LastPages = true,
    RescueDays = 3,
    ComfortBoredom = 3,
    ComfortSadness = 1,
    ComfortListen = 1,
    ComfortPerHour = 5,
}
-- Langue des appels spontanés (E05-T12) : option CallLanguage (enum 1 à 3) -> code de langue du jeu envoyé au pont ;
-- 1 = langue de l'autorité (aucun code ici), puis une entrée par langue livrée par le mod (Translate/EN, FR).
local CALL_LANGUAGES = { false, "EN", "FR" }
-- Notes de fréquences (E05-T09) : option NoteRarity (enum 1 à 4) -> facteur des poids de butin.
local NOTE_RARITY_FACTORS = { 0, 0.4, 1, 2.5 }

function Const.log(msg)
    print(Const.TAG .. " " .. tostring(msg))
end

-- Options enregistrées (Java) d'abord : en solo, l'éditeur en jeu ne met pas à jour SandboxVars
-- avant le prochain chargement. Repli : SandboxVars, puis valeur par défaut.
local function readOption(name)
    local options = getSandboxOptions and getSandboxOptions()
    local option = options and options:getOptionByName(OPTION_NAMESPACE .. name)
    if option then
        local value = option:getValue()
        if value ~= nil then return value end
    end
    local vars = SandboxVars and SandboxVars.RadioSurvivor
    local value = vars and vars[name]
    if value == nil then return DEFAULTS[name] end
    return value
end

local function readNumber(name)
    return tonumber(readOption(name)) or DEFAULTS[name]
end

function Const.isEnabled()
    return readOption("Enabled") == true
end

function Const.spontaneousCalls()
    return readOption("SpontaneousCalls") == true
end

-- Option LastPages (E15-T04) : relevé de vie et dernières pages. Lue à chaque passage : une coupure en cours de
-- partie est prise aussitôt (RS_LifeLog, RS_LastPages).
function Const.lastPages()
    return readOption("LastPages") == true
end

-- Fréquence (kHz) telle qu'affichée par les radios du jeu (ex. 145000 -> « 145.0 »).
function Const.frequencyLabel(khz)
    return string.format("%.1f", (tonumber(khz) or 0) / KHZ_PER_MHZ)
end

function Const.playerCooldownMs()
    return math.max(0, readNumber("PlayerCooldown")) * 1000
end

-- Écart minimal du client entre deux phrases (ms réelles), compté depuis l'envoi : le plus grand de
-- CLIENT_MIN_INTERVAL_MS et du délai du serveur (compté, lui, depuis la réception) augmenté de la marge. Le client
-- lit l'option comme le serveur (SandboxVars synchronisées en MP).
function Const.clientIntervalMs()
    local cooldown = Const.playerCooldownMs()
    if cooldown <= 0 then return Const.CLIENT_MIN_INTERVAL_MS end
    return math.max(Const.CLIENT_MIN_INTERVAL_MS, cooldown + Const.CLIENT_COOLDOWN_MARGIN_MS)
end

-- Facteur des poids de butin des notes de fréquences : 0 (aucune), 0,4 (rares), 1 (normales), 2,5 (fréquentes).
-- Valeur hors de l'énumération : normales.
function Const.noteRarityFactor()
    local index = math.floor(readNumber("NoteRarity"))
    return NOTE_RARITY_FACTORS[index] or NOTE_RARITY_FACTORS[DEFAULTS.NoteRarity]
end

-- Code de langue imposé aux appels spontanés ("EN", "FR"), ou nil : langue de l'autorité (valeur par défaut, ou
-- valeur hors de l'énumération). Lu à chaque appel : un changement en cours de partie est pris aussitôt.
function Const.callLanguage()
    local index = math.floor(readNumber("CallLanguage"))
    return CALL_LANGUAGES[index] or nil
end

-- Réserve de départ d'un secours, en jours de jeu (E12-T06, option RescueDays, = min / max / default de
-- sandbox-options.txt) : entier de 1 à 10 ; option absente, non entière ou hors bornes -> 3. Lue au lancement de chaque
-- secours (un secours en cours garde la sienne).
Const.RESCUE_DAYS_MIN, Const.RESCUE_DAYS_MAX = 1, 10

function Const.rescueDays()
    local value = tonumber(readOption("RescueDays"))
    if value == nil or value ~= value or math.floor(value) ~= value
        or value < Const.RESCUE_DAYS_MIN or value > Const.RESCUE_DAYS_MAX then
        return DEFAULTS.RescueDays
    end
    return value
end

-- Réconfort social (E05-T15, server/RadioSurvivor/RS_Comfort.lua) : baisse d'ennui et de tristesse par réponse d'un
-- PNJ, baisse d'ennui par conversation entre PNJ entendue, effets au plus par personnage et par heure de jeu. Entiers
-- positifs ou nuls (0 = désactivé) ; valeur absente, non numérique ou négative -> défaut. Lus à chaque effet.
local function readCount(name)
    local value = tonumber(readOption(name))
    if value == nil or value ~= value or value < 0 then return DEFAULTS[name] end
    return math.floor(value)
end

function Const.comfortBoredom() return readCount("ComfortBoredom") end
function Const.comfortSadness() return readCount("ComfortSadness") end
function Const.comfortListen() return readCount("ComfortListen") end
function Const.comfortPerHour() return readCount("ComfortPerHour") end

-- 0 = illimité.
function Const.maxPerHour()
    return math.max(0, math.floor(readNumber("MaxPerHour")))
end

-- Texte sur une seule ligne, sans espaces superflus. Linéaire (C22) : le motif "^%s*(.-)%s*$" revenait en arrière en
-- O(n²) sur une longue suite d'espaces suivie d'un caractère ; les bords sont trouvés par deux find (premier et dernier
-- caractère non blanc, chaque blanc n'est relu qu'une fois).
function Const.oneLine(text)
    text = string.gsub(tostring(text or ""), "[\r\n\t]", " ")
    local first = string.find(text, "%S")
    if not first then return "" end
    local last = string.find(text, "%S%s*$", first)
    return string.sub(text, first, last)
end

-- Le joueur parle-t-il dans le micro de la radio posée en x, y, z ? Même règle que la transmission vanilla
-- (zombie/radio/ZomboidRadio.java:519 et GetDistance :545-547 : distance entière, cases entières, < getMicRange()),
-- plus le même étage (le vanilla ne regarde pas z). Commun au client (motif affiché) et au serveur (contrôle).
function Const.inMicRange(player, data, x, y, z)
    if not player or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return false end
    if math.floor(player:getZ()) ~= math.floor(z) then return false end
    local range = data and data:getMicRange()
    if type(range) ~= "number" or range <= 0 then range = Const.DEFAULT_MIC_RANGE end
    local dx, dy = math.floor(player:getX()) - math.floor(x), math.floor(player:getY()) - math.floor(y)
    return math.floor(math.sqrt(dx * dx + dy * dy)) < range
end

-- Émission avec une radio d'inventaire (décision 4 de Belt Walkie-Talkie, commune à Military Drop, Opération Artemis
-- et Radio Survivor) : prédicat partagé BatmanRadioSupport.canTransmitWith du mod requis batman_BeltRadio
-- (shared/BatmanRadio/BatmanRadio_Support.lua, chargé en solo, sur un client MP et sur un serveur dédié). Radio
-- portative émettrice en main ou sur le dos ; jamais accrochée à la ceinture ni rangée (inventaire, sac).
-- Rend nil (acceptée) ou la raison du refus : "notRadio", "notTransmitter", "belt", "stowed", "off", "battery",
-- "micMuted" (client seulement), "noLibrary" (mod commun absent : refus).
function Const.transmitRefusal(player, item)
    local support = BatmanRadioSupport
    if type(support) ~= "table" or type(support.canTransmitWith) ~= "function" then return "noLibrary" end
    local ok, reason = support.canTransmitWith(player, item)
    if ok then return nil end
    return reason or "notRadio"
end

-- Raisons qui tiennent à l'objet ou à sa place (main, dos, ceinture, rangée), fiables aussi côté serveur.
local PLACEMENT_REFUSALS = { notRadio = true, notTransmitter = true, belt = true, stowed = true, noLibrary = true }

-- Radio d'inventaire émettrice tenue en main ou portée sur le dos (Const.transmitRefusal sans les raisons d'état).
-- Commun au client (menu) et au serveur (contrôle) : le serveur ne connaît l'allumage, la pile et le canal que d'une
-- radio en main, et jamais le micro (base pz-knowledge, multiplayer.md) ; ces états sont jugés par le client.
function Const.isCarriedRadio(player, item)
    if not player or not item then return false end
    local reason = Const.transmitRefusal(player, item)
    return reason == nil or not PLACEMENT_REFUSALS[reason]
end

-- Le joueur occupe-t-il une place (conducteur ou passager) de ce véhicule ? (BaseVehicle.getSeat, -1 hors du
-- véhicule.)
function Const.inVehicle(player, vehicle)
    if not player or not vehicle or player:getVehicle() ~= vehicle then return false end
    local seat = vehicle:getSeat(player)
    return type(seat) == "number" and seat >= 0
end

-- Serveur → client. En solo, sendServerCommand ne fait rien : le client s'inscrit ici
-- (clientHandler) et le serveur local l'appelle directement.
Const.clientHandler = nil

function Const.toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, Const.MODULE, command, args or {})
    elseif Const.clientHandler then
        Const.clientHandler(command, args or {})
    end
end

-- Battement du pont (E17-T16) ------------------------------------------------------------------------------------
-- Le pont écrit toute réponse, erreur comprise, au plus BRIDGE_REPLY_MS après l'envoi (bridge/radio_bridge.py :
-- MAX_AGE_S 75 + LLM_BUDGET_S 60) et, tant qu'il tourne, tient à jour BRIDGE_ALIVE_FILE (alive=<getTimestampMs> toutes
-- les 5 s, HEARTBEAT_S). Pont vu vivant (Const.bridgeAlive) : on l'attend BRIDGE_TIMEOUT_MS (borne + marge) ; pont
-- absent ou muet depuis ALIVE_STALE_MS (ou pont antérieur sans battement) : les secours partent après le délai court de
-- chaque demande, comme avant. Const.TIMEOUT_MS (radio de Walt) est tenu à jour par Const.refreshTimeout(), appelé à
-- chaque OnTickEvenPaused de l'autorité par server/RadioSurvivor/RS_BridgeAlive.lua.
Const.BRIDGE_ALIVE_FILE = "batman_RadioSurvivor/bridge-alive.txt"
Const.BRIDGE_REPLY_MS = 135000
Const.BRIDGE_TIMEOUT_MS = 150000      -- = RS_Config.REQUEST_TIMEOUT_MS (carnet)
Const.NO_BRIDGE_TIMEOUT_MS = 90000    -- radio de Walt sans pont : « <fzzt> » et refus NoAnswer
Const.ALIVE_STALE_MS = 20000
Const.ALIVE_READ_MS = 5000            -- relecture du battement au plus toutes les 5 s
Const.bridgeSeenMs = nil   -- dernier battement lu (getTimestampMs du pont), nil = jamais vu
local aliveReadAt = nil

local function nowMs(now)
    if now then return now end
    -- nil checks, not type() == "function": a Java function or a bench double (lupa userdata)
    return getTimestampMs and getTimestampMs() or 0
end

local function readAlive()
    if not getFileReader then return nil end
    local reader = getFileReader(Const.BRIDGE_ALIVE_FILE, false)
    if not reader then return nil end
    local stamp = nil
    local line = reader:readLine()
    while line do
        local v = tonumber(string.match(line, "^alive=(%d+)"))
        if v then stamp = v end
        line = reader:readLine()
    end
    reader:close()
    return stamp
end

-- Vrai si le pont a écrit son battement depuis moins de ALIVE_STALE_MS (fichier relu au plus toutes les
-- ALIVE_READ_MS ; force = relire tout de suite).
function Const.bridgeAlive(now, force)
    now = nowMs(now)
    if force or aliveReadAt == nil or now - aliveReadAt >= Const.ALIVE_READ_MS or now < aliveReadAt then
        aliveReadAt = now
        Const.bridgeSeenMs = readAlive()
    end
    local seen = Const.bridgeSeenMs
    return seen ~= nil and now - seen <= Const.ALIVE_STALE_MS and seen - now <= Const.ALIVE_STALE_MS
end

-- Attente d'une demande au pont : shortMs (secours sans pont) ou, pont vivant, au moins BRIDGE_TIMEOUT_MS.
function Const.waitMs(shortMs, now)
    if Const.bridgeAlive(now) then return math.max(shortMs, Const.BRIDGE_TIMEOUT_MS) end
    return shortMs
end

-- Const.TIMEOUT_MS (radio de Walt, RadioSurvivor_Server.lua) suit l'état du pont : appelé à chaque OnTickEvenPaused
-- de l'autorité par server/RadioSurvivor/RS_BridgeAlive.lua (abonnement hors de ce module partagé, requis partout).
function Const.refreshTimeout(now)
    Const.TIMEOUT_MS = Const.waitMs(Const.NO_BRIDGE_TIMEOUT_MS, now)
end

return Const
