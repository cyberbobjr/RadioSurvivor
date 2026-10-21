-- Living Knox : fonctions de test de l'API publique (E01-T10, ajout compatible de la version 1). Documentation :
-- docs/specifications-techniques/api-living-knox.md, section « Fonctions de test (E01-T10) ».
-- Réservées aux parties de test : elles refusent d'agir hors de l'autorité (serveur dédié ou hébergé, solo), hors du
-- mode debug de la machine qui les exécute (isDebugEnabled() = Core.debug : client lancé avec -debug, serveur dédié
-- lancé avec la propriété Java -Ddebug ; E01-T18) et hors d'une partie dont le nom commence par API.TEST_SAVE_PREFIX
-- (getWorld():getWorld(), sans tenir compte de la casse ; même règle que la garde « world » du mod de test). Chaque
-- refus de testSpawnNpc/testRemoveNpc est écrit dans la console (en anglais).
-- Elles servent aux fixtures du moteur de tests en jeu : faire apparaître un PNJ sans groupe près d'un point, puis
-- le retirer. Un PNJ créé ici est un PNJ ordinaire du registre
-- (LivingKnox.Bodies.spawn) ; seuls les PNJ créés ici dans cette session Lua peuvent être retirés par
-- API.testRemoveNpc (aucun retrait d'un PNJ de la partie par cette voie).
-- Rien n'est rendu d'autre que des chaînes et des nombres : le corps se retrouve par le fournisseur du carnet ou par
-- LivingKnox.Bodies.find côté autorité.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_API"
require "LivingKnox/LK_Bodies"

local API = LivingKnox.API

API.TEST_SAVE_PREFIX = "rstest"
API.testState = API.testState or { spawned = {} }

local function saveName()
    if type(getWorld) ~= "function" then return nil end
    local ok, name = pcall(function()
        local world = getWorld()
        if world == nil then return nil end
        return world:getWorld()
    end)
    if not ok or type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Vrai si les fonctions de test peuvent agir ici ; sinon faux et la raison.
function API.testAllowed()
    if not LivingKnox.isAuthority() then return false, "not the authority (MP client)" end
    if type(isDebugEnabled) ~= "function" or isDebugEnabled() ~= true then
        return false, "debug mode off (isDebugEnabled() is false on this machine)"
    end
    local name = saveName()
    if name == nil then return false, "save name unavailable (getWorld():getWorld())" end
    local prefix = API.TEST_SAVE_PREFIX
    if string.lower(string.sub(name, 1, #prefix)) ~= prefix then
        return false, "save '" .. name .. "' is not a test save (" .. prefix .. "*)"
    end
    return true
end

local function refused(fn, why)
    print(LivingKnox.TAG .. " test API " .. fn .. " refused: " .. tostring(why))
end

local function isNumber(v) return type(v) == "number" and v == v end

-- Nouveau PNJ de test (sans groupe) et son corps sur la case libre et chargée la plus proche de (x, y, z).
-- profile facultatif : entrée de LivingKnox.Appearance.normalize ({} par défaut). Rend l'identifiant "lk-<n>", ou
-- nil et une raison (partie normale, mode debug coupé, client MP, moteur coupé, case non chargée, aucune case libre...).
function API.testSpawnNpc(x, y, z, profile)
    local ok, why = API.testAllowed()
    if not ok then refused("testSpawnNpc", why); return nil, why end
    if not isNumber(x) or not isNumber(y) or not isNumber(z) then return nil, "position must be three numbers" end
    if profile ~= nil and type(profile) ~= "table" then return nil, "profile must be a table" end
    local id, result = LivingKnox.Bodies.spawn(profile or {}, x, y, z)
    if id == nil then return nil, result end
    API.testState.spawned[id] = true
    return id
end

-- Retire un PNJ créé par API.testSpawnNpc : corps retiré, PNJ oublié du registre. Rend vrai et le nombre de corps
-- retirés (0 quand le corps était hors zone chargée : il sera retiré comme orphelin à son retour), ou faux et une
-- raison.
function API.testRemoveNpc(id)
    local ok, why = API.testAllowed()
    if not ok then refused("testRemoveNpc", why); return false, why end
    if type(id) ~= "string" or not API.testState.spawned[id] then
        return false, "npc " .. tostring(id) .. " was not created by testSpawnNpc"
    end
    local D = LivingKnox.Directives
    if D ~= nil and D.forget ~= nil then D.forget(id) end
    local done, result = LivingKnox.Bodies.despawn(id, true)
    if not done then return false, result end
    API.testState.spawned[id] = nil
    return true, result
end

-- Identifiants des PNJ de test encore présents, triés (copie).
function API.testNpcs()
    local out = {}
    for id in pairs(API.testState.spawned) do out[#out + 1] = id end
    table.sort(out)
    return out
end
