-- Radio Survivor : action `persona_state`, état dynamique d'une voix (E07-T06).
-- La voix fait évoluer son propre état au fil du récit : moral (`morale`), réserves en général (`supplies` : vivres,
-- eau, munitions) et lieu où elle dit se trouver (`place`, texte libre). Le pont propose, RS_Actions juge (catalogue,
-- fiche, budget.persona_state du jour, paramètres), puis l'exécuteur ci-dessous range l'état de ctx.voice, jamais
-- celui d'une autre voix. Aucun effet de jeu : `place` n'est qu'un récit, sans lien avec coords= de la fiche ni avec
-- un contrôle de distance.
-- L'état vit côté autorité, dans l'état privé RS_State (S.data.personaState[voix] = { morale, supplies, place }),
-- jamais dans le fichier de fiche édité par l'admin ni en ModData globale ; sinon (état pas encore chargé ou bloqué)
-- dans une table en mémoire, perdue au redémarrage du serveur, comme les compteurs de RS_Actions.
-- À chaque demande radio suivante à cette voix, RadioSurvivor_Server joint l'état (champ persona=, hexadécimal RSV2
-- d'une table, PersonaState.field) dès qu'il a été modifié une fois ; le pont l'injecte dans le prompt système
-- (docs/specifications-techniques/protocole-carnet-v2.md, « État dynamique des voix »).
-- Bornes (RadioSurvivor_Const) : morale et supplies entiers de 0 à PERSONA_LEVEL_MAX, PERSONA_LEVEL_DEFAULT avant tout
-- changement ; au plus PERSONA_LEVEL_STEP d'écart par appel avec la valeur courante (une demande au-delà, ou hors
-- bornes, est ramenée, pas refusée) ; place nettoyé comme un souvenir (RS_Memory.clean), PERSONA_PLACE_CHARS
-- caractères au plus.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Codec = require "RadioSurvivor/RS_Codec"
local S = require "RadioSurvivor/RS_State"
local Actions = require "RadioSurvivor/RS_Actions"
local Memory = require "RadioSurvivor/RS_Memory"

local PersonaState = {}

-- Aucun délai : le budget du jour (budget.persona_state de la fiche) et les 3 actions par réponse suffisent.
PersonaState.COOLDOWN_MS = 0

local PARAMS = { morale = true, supplies = true, place = true }

-- État de secours quand RS_State n'est pas chargé (voir l'en-tête).
local volatile = {}

function PersonaState.resetForTests()
    volatile = {}
end

local function store()
    if S.data and not S.blocked then
        if type(S.data.personaState) ~= "table" then S.data.personaState = {} end
        return S.data.personaState, true
    end
    return volatile, false
end

local function isLevel(value)
    return type(value) == "number" and value >= 0 and value <= Const.PERSONA_LEVEL_MAX and math.floor(value) == value
end

-- Valeur courante lisible (entier de 0 à PERSONA_LEVEL_MAX), sinon la valeur par défaut.
local function level(value)
    if isLevel(value) then return value end
    return Const.PERSONA_LEVEL_DEFAULT
end

-- Valeur demandée ramenée aux bornes, puis au pas maximal autour de la valeur courante.
local function stepped(current, wanted)
    local low = math.max(0, current - Const.PERSONA_LEVEL_STEP)
    local high = math.min(Const.PERSONA_LEVEL_MAX, current + Const.PERSONA_LEVEL_STEP)
    if wanted < low then return low end
    if wanted > high then return high end
    return wanted
end

-- État de la voix { morale, supplies, place } (copie), ou nil s'il n'a jamais été modifié.
function PersonaState.get(voice)
    if voice == nil then return nil end
    local all = store()
    local entry = all[voice]
    if type(entry) ~= "table" then return nil end
    local place = type(entry.place) == "string" and entry.place or ""
    return { morale = level(entry.morale), supplies = level(entry.supplies), place = place }
end

-- Applique les paramètres déjà validés à l'état de la voix. Rend true.
function PersonaState.apply(voice, params)
    local all, persistent = store()
    local current = PersonaState.get(voice)
        or { morale = Const.PERSONA_LEVEL_DEFAULT, supplies = Const.PERSONA_LEVEL_DEFAULT, place = "" }
    if params.morale ~= nil then current.morale = stepped(current.morale, params.morale) end
    if params.supplies ~= nil then current.supplies = stepped(current.supplies, params.supplies) end
    if params.place ~= nil then current.place = Memory.clean(params.place, Const.PERSONA_PLACE_CHARS) end
    all[voice] = current
    if persistent then S.dirty = true end
    return true
end

-- Champ persona= d'une demande radio : hexadécimal RSV2 de { morale, supplies, place } (place omis s'il est vide),
-- ou nil tant que la voix n'a jamais changé son état (champ absent).
function PersonaState.field(voice)
    local state = PersonaState.get(voice)
    if state == nil then return nil end
    local out = { morale = state.morale, supplies = state.supplies }
    if state.place ~= "" then out.place = state.place end
    return Codec.hexBytes(Codec.encodeBytes(out))
end

-- Paramètres : au moins un de morale, supplies, place ; aucun autre. morale et supplies : nombres entiers (toute
-- valeur, ramenée ensuite) ; place : chaîne non vide une fois nettoyée (RS_Actions en borne déjà la longueur brute).
local function validate(params)
    local count = 0
    for key, value in pairs(params) do
        if not PARAMS[key] then return false end
        count = count + 1
        if key == "place" then
            if Memory.clean(value, Const.PERSONA_PLACE_CHARS) == "" then return false end
        elseif type(value) ~= "number" or math.floor(value) ~= value then
            return false
        end
    end
    return count > 0
end

local function execute(params, ctx)
    if type(ctx) ~= "table" or ctx.voice == nil then return false, "failed" end
    return PersonaState.apply(ctx.voice, params)
end

function PersonaState.register()
    return Actions.register("persona_state", {
        validate = validate, cooldownMs = PersonaState.COOLDOWN_MS, execute = execute })
end

PersonaState.register()

return PersonaState
