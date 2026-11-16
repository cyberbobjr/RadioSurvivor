-- Radio Survivor : niveaux de radio des voix (E24-T01, ADR atelier D12). Une fiche choisit la radio dont le joueur a
-- besoin pour entendre la voix (radio=<niveau>) ; le serveur tire a chaque partie une frequence libre de la zone de ce
-- niveau (RS_Personas), ou la fiche fixe une frequence (frequency=) dont le niveau se deduit (levelOf).
--
-- Seule table des plages de reglage : lue par le lecteur des fiches (RS_Persona), le tirage (RS_Personas) et le
-- catalogue de l'atelier (tools/gen_atelier_catalog.py, catalog.json radioLevels). Chaque niveau donne la plage de
-- reglage (kHz, bornes comprises) du poste le plus faible du niveau et les objets du jeu qui l'ont, lus dans
-- media/scripts/generated/items/radio.txt (42.22, MinChannel / MaxChannel ; banc tests/test_radio_levels.py) :
--   any_talkie  : WalkieTalkie1 (Toys-R-Mine), WalkieTalkieMakeShift                 75-150 MHz
--   good_talkie : WalkieTalkie2 (ValuTech)                                           50-200 MHz
--   pro_talkie  : WalkieTalkie3 (Premium Technologies)                               25-300 MHz
--   tactical    : WalkieTalkie4 (tactique), HamRadio1 (HAM Premium), HamRadioMakeShift 10-500 MHz
--   military    : WalkieTalkie5, ManPackRadio, HamRadio2 (US Army)                   0.2-1000 MHz
-- Chaque plage contient celle du niveau precedent. Zone d'un niveau : les frequences que son poste le plus faible
-- capte et que le niveau precedent ne capte pas (niveau 1 : toute sa plage, que tout le monde entend). Pas des
-- radios : 0.2 MHz (RWMChannel.lua:138, 42.22), frequences en kHz multiples de STEP_KHZ.
-- Seul l'ASCII est utilise dans ce fichier (lexeur Kahlua).
local Levels = {}

Levels.STEP_KHZ = 200

Levels.LIST = {
    { id = "any_talkie", minKhz = 75000, maxKhz = 150000, devices = { "WalkieTalkie1", "WalkieTalkieMakeShift" } },
    { id = "good_talkie", minKhz = 50000, maxKhz = 200000, devices = { "WalkieTalkie2" } },
    { id = "pro_talkie", minKhz = 25000, maxKhz = 300000, devices = { "WalkieTalkie3" } },
    { id = "tactical", minKhz = 10000, maxKhz = 500000, devices = { "WalkieTalkie4", "HamRadio1", "HamRadioMakeShift" } },
    { id = "military", minKhz = 200, maxKhz = 1000000, devices = { "WalkieTalkie5", "ManPackRadio", "HamRadio2" } },
}

-- Identifiants des niveaux, du plus faible au plus fort.
function Levels.ids()
    local out = {}
    for i, level in ipairs(Levels.LIST) do out[i] = level.id end
    return out
end

-- Rang (1 = le plus faible) d'un niveau, ou nil.
local function rankOf(id)
    for i, level in ipairs(Levels.LIST) do
        if level.id == id then return i end
    end
    return nil
end

-- Niveau { id, minKhz, maxKhz, devices }, ou nil.
function Levels.get(id)
    local rank = rankOf(id)
    return rank and Levels.LIST[rank] or nil
end

-- Bornes de toutes les radios (kHz) : plage du niveau le plus fort.
function Levels.minKhz() return Levels.LIST[#Levels.LIST].minKhz end
function Levels.maxKhz() return Levels.LIST[#Levels.LIST].maxKhz end

function Levels.onGrid(khz)
    return khz % Levels.STEP_KHZ == 0
end

local function tunes(level, khz)
    return khz >= level.minKhz and khz <= level.maxKhz
end

-- Zone d'un niveau : liste de plages { low, high } (kHz, bornes comprises, sur le pas des radios), ou nil.
function Levels.zones(id)
    local rank = rankOf(id)
    if not rank then return nil end
    local level, weaker = Levels.LIST[rank], Levels.LIST[rank - 1]
    if not weaker then return { { low = level.minKhz, high = level.maxKhz } } end
    local out = {}
    if level.minKhz < weaker.minKhz then
        out[#out + 1] = { low = level.minKhz, high = weaker.minKhz - Levels.STEP_KHZ }
    end
    if level.maxKhz > weaker.maxKhz then
        out[#out + 1] = { low = weaker.maxKhz + Levels.STEP_KHZ, high = level.maxKhz }
    end
    return out
end

-- Vrai si khz est dans la zone du niveau id.
function Levels.inZone(id, khz)
    for _, zone in ipairs(Levels.zones(id) or {}) do
        if khz >= zone.low and khz <= zone.high then return true end
    end
    return false
end

-- Niveau le plus faible qui capte khz (radio necessaire pour une frequence fixe), ou nil hors de toutes les radios.
function Levels.levelOf(khz)
    for _, level in ipairs(Levels.LIST) do
        if tunes(level, khz) then return level.id end
    end
    return nil
end

return Levels
