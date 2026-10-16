-- Radio Survivor : réconfort social (E05-T15, décision de l'utilisateur du 2026-10-17).
--
-- Parler avec quelqu'un apaise : la réponse d'un PNJ à la radio d'un personnage (voix d'E05, groupe équipé d'E08-T06)
-- lui retire de l'ennui et de la tristesse quand elle passe à l'antenne ; entendre deux PNJ discuter (E08-T04) retire
-- un peu d'ennui, une fois par conversation. Toutes les voix comptent, hostiles comprises. Au plus
-- Const.comfortPerHour() effets par personnage et par heure de jeu, tous effets confondus.
--
-- Même mécanisme que la caresse d'un animal (IsoPlayer.petAnimal, IsoPlayer.java:8106-8118) : stats changées par
-- l'autorité, puis SyncPlayerStats vers le client (syncPlayerStats, LuaManager.java:9339, sans effet hors serveur MP).
-- Le client affiche le halo vanilla (RS_RadioTalk, Const.CMD.COMFORT), seulement pour une stat réellement changée.
-- Plafond en mémoire du serveur (perdu au redémarrage : sans conséquence). Autorité seulement. Messages en anglais.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"

local Comfort = {}

-- Clé de personnage -> { hour = heure de jeu entière, given = effets accordés pendant cette heure }.
local counts = {}
Comfort.counts = counts
-- Compteurs (bancs, diagnostic) : effets appliqués, refusés par le plafond.
Comfort.stats = { applied = 0, capped = 0 }

-- Masque SyncPlayerStatsPacket d'une stat : 1 << rang dans CharacterStat.ORDERED_STATS (SyncPlayerStatsPacket.java:28).
-- Repli (classe absente) : rangs 42.21 de BOREDOM (1) et UNHAPPINESS (20), CharacterStat.java:38.
local FALLBACK_MASKS = { Boredom = 2, Unhappiness = 1048576 }

local function maskOf(stat, name)
    local packet = SyncPlayerStatsPacket
    local mask = packet and packet.getBitMaskForStat and packet.getBitMaskForStat(stat)
    if type(mask) == "number" and mask > 0 then return mask end
    return FALLBACK_MASKS[name]
end

-- Entrée du plafond de ce personnage pour l'heure de jeu en cours, ou nil s'il est atteint (ou réglé à 0).
local function allowance(key)
    local limit = Const.comfortPerHour()
    if limit <= 0 then return nil end
    local hour = math.floor(getGameTime():getWorldAgeHours())
    local entry = counts[key]
    if not entry or entry.hour ~= hour then
        entry = { hour = hour, given = 0 }
        counts[key] = entry
    end
    if entry.given >= limit then
        Comfort.stats.capped = Comfort.stats.capped + 1
        return nil
    end
    return entry
end

-- Retire boredom et sadness (déjà lus des options) au joueur ; rend vrai si une stat a changé (effet compté).
local function apply(player, key, boredom, sadness)
    if not player or (player.isDead and player:isDead()) then return false end
    if boredom <= 0 and sadness <= 0 then return false end
    local entry = allowance(key)
    if not entry then return false end
    local stats = player:getStats()
    if not stats then return false end
    local eased = { boredom = 0, sadness = 0 }
    local mask = 0
    if boredom > 0 and stats:remove(CharacterStat.BOREDOM, boredom) then
        eased.boredom = boredom
        mask = mask + maskOf(CharacterStat.BOREDOM, "Boredom")
    end
    if sadness > 0 and stats:remove(CharacterStat.UNHAPPINESS, sadness) then
        eased.sadness = sadness
        mask = mask + maskOf(CharacterStat.UNHAPPINESS, "Unhappiness")
    end
    -- Rien n'a changé (jauges déjà à zéro) : aucun effet compté, ni synchro ni halo.
    if mask == 0 then return false end
    entry.given = entry.given + 1
    Comfort.stats.applied = Comfort.stats.applied + 1
    if isServer() and syncPlayerStats then syncPlayerStats(player, mask) end
    Const.toClient(player, Const.CMD.COMFORT, eased)
    return true
end

-- Clé du plafond : personnage du carnet s'il y en a un, sinon compte (serveur) ou « solo ».
local function keyOf(player, cid)
    if cid then return "c:" .. tostring(cid) end
    if isServer() then return "u:" .. tostring(player:getUsername()) end
    return "solo"
end

-- Une réponse d'un PNJ à ce joueur passe à l'antenne. cid : personnage du carnet de l'appelant au moment de sa phrase
-- (nil sans carnet) ; un autre personnage depuis (mort, nouveau personnage) ne reçoit rien.
function Comfort.answered(player, cid, currentCid)
    if not player then return false end
    if cid ~= currentCid then return false end
    return apply(player, keyOf(player, cid), Const.comfortBoredom(), Const.comfortSadness())
end

-- Le joueur entend une réplique d'une conversation entre PNJ ; seen : table propre à cette conversation (clé de
-- personnage -> vrai), un seul effet par conversation et par personnage (tentative comptée même si le plafond refuse).
function Comfort.overheard(player, cid, seen)
    if not player or type(seen) ~= "table" then return false end
    local key = keyOf(player, cid)
    if seen[key] then return false end
    seen[key] = true
    return apply(player, key, Const.comfortListen(), 0)
end

-- Tests : état remis à zéro.
function Comfort.reset()
    for k in pairs(counts) do counts[k] = nil end
    Comfort.stats.applied, Comfort.stats.capped = 0, 0
end

return Comfort
