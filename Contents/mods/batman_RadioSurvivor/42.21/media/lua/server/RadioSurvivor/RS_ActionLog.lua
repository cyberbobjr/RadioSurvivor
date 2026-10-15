-- Radio Survivor : journal admin des actions des voix radio (E07-T02). Format : docs/protocole-carnet-v2.md,
-- « Journal admin des actions ».
-- Une ligne par action proposée, champs séparés par une tabulation, dans Zomboid/Lua/batman_RadioSurvivor/
-- actions-<partie>.log (<partie> : même dérivation hexadécimale que RS_State). N'écrit que le nom d'action filtré,
-- les paramètres déjà filtrés par RS_Actions (paramsOf) et la décision : jamais de fiche ni de texte `say`.
-- Rotation bornée : compteur de lignes et de caractères en mémoire, initialisé par une seule lecture au premier
-- usage (ou au changement de partie) ; au seuil (RadioSurvivor_Const.ACTION_LOG_MAX_LINES / MAX_CHARS), le contenu
-- courant est recopié dans actions-<partie>.1.log (ancien .1 écrasé) puis le fichier courant est vidé. Le jeu n'offre
-- pas de renommage de fichier en Lua : la copie coûte une lecture du fichier courant, une fois par rotation.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Codec = require "RadioSurvivor/RS_Codec"

local Log = {}

Log.HEADER = "# RadioSurvivor action log v1 (tab-separated): real_utc\tgame_time\tvoice\tcaller\taction\tparams"
    .. "\tdecision\treason"

-- Fichier courant connu : chemin, lignes et caractères (nil tant que non lu).
local current = { path = nil, lines = 0, chars = 0 }
local warned = false

function Log.resetForTests()
    current = { path = nil, lines = 0, chars = 0 }
    warned = false
end

-- Base du chemin pour la partie chargée : batman_RadioSurvivor/actions-<hex(mode/monde)>.
function Log.base()
    local w = getWorld()
    if not w then return nil end
    return "batman_RadioSurvivor/actions-" .. Codec.hexBytes(w:getGameMode() .. "/" .. w:getWorld())
end

-- Champ sur une ligne, sans séparateur : `%`, `=`, `;` et caractères de contrôle (tabulation, retours) encodés en
-- %XX, ce qui reste réversible pour l'admin. Vide -> "-".
local function field(value)
    local s = tostring(value == nil and "" or value)
    s = string.gsub(s, "[%%=;%c]", function(c) return string.format("%%%02X", string.byte(c)) end)
    if s == "" then return "-" end
    return s
end
Log.field = field

-- Paramètres triés par clé, `clé=valeur` séparés par `;` ; "-" sans paramètre ; "<invalid>" quand paramsOf les a
-- rejetés (nil), sans rien recopier de la proposition.
local function paramsField(params)
    if params == nil then return "<invalid>" end
    local keys = {}
    for k in pairs(params) do keys[#keys + 1] = tostring(k) end
    if #keys == 0 then return "-" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = field(k) .. "=" .. field(params[k]) end
    return table.concat(parts, ";")
end
Log.paramsField = paramsField

local function gameTime()
    local gt = getGameTime()
    if not gt then return "-" end
    return string.format("%04d-%02d-%02d %02d:%02d", gt:getYear(), gt:getMonth() + 1, gt:getDay() + 1,
        gt:getHour(), gt:getMinutes())
end

-- Ligne du journal pour une décision { type, params, accepted, reason } (type déjà filtré par l'appelant).
function Log.format(decision, voice, caller, actionName)
    return table.concat({
        os.date("!%Y-%m-%d %H:%M:%S") .. " UTC",
        gameTime(),
        field(voice),
        field(caller),
        field(actionName),
        paramsField(decision.params),
        decision.accepted and "accepted" or "refused",
        field(decision.reason),
    }, "\t")
end

local function readAll(path)
    local r = getFileReader(path, false)
    if not r then return {} end
    local lines = {}
    local line = r:readLine()
    while line ~= nil do
        lines[#lines + 1] = line
        line = r:readLine()
    end
    r:close()
    return lines
end

local function writeLines(path, lines, append)
    local w = getFileWriter(path, true, append)
    if not w then return false end
    for _, line in ipairs(lines) do w:write(line .. "\n") end
    w:close()
    return true
end

-- Premier usage pour ce chemin : une lecture pour connaître la taille du fichier existant.
local function load(path)
    if current.path == path then return end
    local lines = readAll(path .. ".log")
    local chars = 0
    for _, line in ipairs(lines) do chars = chars + string.len(line) + 1 end
    current = { path = path, lines = #lines, chars = chars }
end

local function rotate(path)
    writeLines(path .. ".1.log", readAll(path .. ".log"), false)
    writeLines(path .. ".log", {}, false)
    current.lines, current.chars = 0, 0
end

-- Ajoute des lignes au journal de la partie ; rotation avant d'écrire si le seuil serait dépassé. Rend true si écrit.
function Log.append(lines)
    if type(lines) ~= "table" or #lines == 0 then return false end
    local path = Log.base()
    if not path then return false end
    load(path)
    local add = {}
    if current.lines == 0 then add[1] = Log.HEADER end
    for _, line in ipairs(lines) do add[#add + 1] = line end
    local addChars = 0
    for _, line in ipairs(add) do addChars = addChars + string.len(line) + 1 end
    if current.lines > 0 and (current.lines + #add > Const.ACTION_LOG_MAX_LINES
            or current.chars + addChars > Const.ACTION_LOG_MAX_CHARS) then
        rotate(path)
        table.insert(add, 1, Log.HEADER)
        addChars = addChars + string.len(Log.HEADER) + 1
    end
    if not writeLines(path .. ".log", add, true) then
        if not warned then
            Const.log("action log unavailable: cannot write " .. path .. ".log")
            warned = true
        end
        return false
    end
    current.lines = current.lines + #add
    current.chars = current.chars + addChars
    return true
end

return Log
