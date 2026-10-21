-- Radio Survivor : action `remember`, mémoire bornée d'une voix sur un appelant (E07-T03).
-- Le pont propose `remember` (paramètre unique `fact`) ; RS_Actions juge (catalogue, fiche, budget.remember du jour,
-- paramètres) puis l'exécuteur ci-dessous range le fait. Aucun effet de jeu : seulement la mémoire.
-- La mémoire vit côté autorité, dans l'état privé RS_State (S.data.memory, jamais en ModData globale) ; sinon (état
-- pas encore chargé ou bloqué) dans une table en mémoire, perdue au redémarrage du serveur, comme les compteurs de
-- RS_Actions. Clé : voix + appelant + personnage du carnet (ctx.cid s'il existe), pour qu'un nouveau personnage en
-- solo (une seule clé d'appelant, « solo ») n'hérite pas des souvenirs du précédent.
-- À chaque demande radio suivante du même appelant à la même voix, RadioSurvivor_Server joint les faits à la demande
-- (champ memory=, hexadécimal RSV2 d'une liste de chaînes, Memory.field) ; le pont les place dans le prompt comme
-- souvenirs non vérifiés, jamais comme preuve (docs/specifications-techniques/protocole-carnet-v2.md, « Mémoire des voix »).
-- Bornes (RadioSurvivor_Const) : MEMORY_MAX_FACTS faits par (voix, appelant, personnage), le plus ancien évincé ; un
-- fait identique après normalisation (casse, espaces) est rafraîchi, pas dupliqué ; MEMORY_MAX_CALLERS appelants par
-- voix, le moins récemment servi évincé ; MEMORY_FACT_CHARS caractères par fait.
-- Purge : la mort d'un personnage (RS_Carnet_Server.characterDeath, identité retirée) appelle forgetCharacter ; un
-- personnage déjà retiré n'est de toute façon jamais relu (filtre à la lecture).
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Codec = require "RadioSurvivor/RS_Codec"
local S = require "RadioSurvivor/RS_State"
local Actions = require "RadioSurvivor/RS_Actions"

local Memory = {}

-- Délai entre deux `remember` d'une même voix : aucun. Le délai de RS_Actions est par voix et non par appelant : un
-- délai ferait refuser le souvenir d'un deuxième appelant juste après celui d'un premier. Le budget du jour
-- (budget.remember de la fiche), les 3 actions au plus par réponse et les bornes ci-dessus suffisent à limiter
-- l'écriture.
Memory.COOLDOWN_MS = 0

-- Mémoire de secours quand RS_State n'est pas chargé (voir l'en-tête).
local volatile = {}

function Memory.resetForTests()
    volatile = {}
end

local function store()
    if S.data and not S.blocked then
        if type(S.data.memory) ~= "table" then S.data.memory = {} end
        return S.data.memory, true
    end
    return volatile, false
end

-- Fait sur une ligne : contrôles et retours en espaces, balises de texte riche retirées, espaces réduits, coupé à
-- MEMORY_FACT_CHARS (ou maxChars : lieu de RS_PersonaState) ; "" si rien ne reste.
function Memory.clean(text, maxChars)
    if type(text) ~= "string" then return "" end
    local limit = maxChars or Const.MEMORY_FACT_CHARS
    text = string.gsub(text, "[%c<>%[%]]", " ")
    text = Const.oneLine(string.gsub(text, "%s+", " "))
    if string.len(text) > limit then
        text = Const.oneLine(string.sub(text, 1, limit))
    end
    return text
end

-- Forme de comparaison (doublons) : minuscules, espaces déjà réduits par clean.
local function normal(text)
    return string.lower(text)
end

-- Clé d'un appelant : longueur de la clé de compte en tête, pour qu'aucun nom de compte ne se confonde avec un
-- autre couple (appelant, personnage).
local function keyOf(caller, cid)
    local who = tostring(caller or "?")
    return tostring(string.len(who)) .. ":" .. who .. "/" .. tostring(cid or "-")
end

local function voiceOf(all, voice, create)
    local v = all[voice]
    if type(v) ~= "table" then
        if not create then return nil end
        v = { seq = 0, callers = {} }
        all[voice] = v
    end
    if type(v.callers) ~= "table" then v.callers = {} end
    if type(v.seq) ~= "number" then v.seq = 0 end
    return v
end

-- Personnage retiré à la mort (ou disparu de l'état) : ses souvenirs ne sont plus lus.
local function retired(cid)
    if cid == nil or not S.data or type(S.data.characters) ~= "table" then return false end
    local record = S.data.characters[cid]
    return type(record) ~= "table" or record.retired == true
end

-- Retire l'appelant le moins récemment servi tant que la voix en garde plus que MEMORY_MAX_CALLERS.
local function evictCallers(v)
    while true do
        local count, oldestKey, oldestSeq = 0, nil, nil
        for key, entry in pairs(v.callers) do
            count = count + 1
            local seq = type(entry) == "table" and tonumber(entry.seq) or -1
            if oldestSeq == nil or seq < oldestSeq then oldestKey, oldestSeq = key, seq end
        end
        if count <= Const.MEMORY_MAX_CALLERS or oldestKey == nil then return end
        v.callers[oldestKey] = nil
    end
end

-- Range un fait déjà nettoyé. Rend true.
function Memory.add(voice, caller, cid, fact)
    local all, persistent = store()
    local v = voiceOf(all, voice, true)
    v.seq = v.seq + 1
    local key = keyOf(caller, cid)
    local entry = v.callers[key]
    if type(entry) ~= "table" or type(entry.facts) ~= "table" then
        entry = { caller = caller, cid = cid, facts = {} }
        v.callers[key] = entry
    end
    entry.seq = v.seq
    local wanted = normal(fact)
    local kept = {}
    for _, f in ipairs(entry.facts) do
        if type(f) == "table" and type(f.text) == "string" and normal(f.text) ~= wanted then kept[#kept + 1] = f end
    end
    kept[#kept + 1] = { text = fact, seq = v.seq }
    while #kept > Const.MEMORY_MAX_FACTS do table.remove(kept, 1) end
    entry.facts = kept
    evictCallers(v)
    if persistent then S.dirty = true end
    return true
end

-- Faits de l'appelant pour cette voix, du plus ancien au plus récent ; liste vide s'il n'y en a pas.
function Memory.facts(voice, caller, cid)
    local out = {}
    if voice == nil or retired(cid) then return out end
    local all = store()
    local v = voiceOf(all, voice, false)
    local entry = v and v.callers[keyOf(caller, cid)]
    if type(entry) ~= "table" or type(entry.facts) ~= "table" then return out end
    for _, f in ipairs(entry.facts) do
        if type(f) == "table" and type(f.text) == "string" and f.text ~= "" and #out < Const.MEMORY_MAX_FACTS then
            out[#out + 1] = f.text
        end
    end
    return out
end

-- Champ memory= d'une demande radio : hexadécimal RSV2 de la liste des faits (une ligne, réversible, taille bornée
-- par les bornes ci-dessus), ou nil sans souvenir (champ absent).
function Memory.field(voice, caller, cid)
    local facts = Memory.facts(voice, caller, cid)
    if #facts == 0 then return nil end
    return Codec.hexBytes(Codec.encodeBytes(facts))
end

-- Mort d'un personnage : ses souvenirs, toutes voix confondues, sont oubliés.
function Memory.forgetCharacter(cid)
    if cid == nil then return end
    local all, persistent = store()
    local removed = false
    for _, v in pairs(all) do
        if type(v) == "table" and type(v.callers) == "table" then
            local doomed = {}
            for key, entry in pairs(v.callers) do
                if type(entry) == "table" and entry.cid == cid then doomed[#doomed + 1] = key end
            end
            for _, key in ipairs(doomed) do
                v.callers[key] = nil
                removed = true
            end
        end
    end
    if removed and persistent then S.dirty = true end
end

-- Paramètre unique `fact` : chaîne non vide une fois nettoyée (RS_Actions en borne déjà la longueur brute).
local function validate(params)
    for key in pairs(params) do
        if key ~= "fact" then return false end
    end
    return Memory.clean(params.fact) ~= ""
end

local function execute(params, ctx)
    if type(ctx) ~= "table" or ctx.voice == nil or ctx.caller == nil then return false, "failed" end
    return Memory.add(ctx.voice, ctx.caller, ctx.cid, Memory.clean(params.fact))
end

function Memory.register()
    return Actions.register("remember", { validate = validate, cooldownMs = Memory.COOLDOWN_MS, execute = execute })
end

Memory.register()

return Memory
