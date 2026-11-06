-- Living Knox : histoires des groupes composées par le serveur (LK10-T01). Fiche : docs/annexes/conception/recits.md.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Stories.compose(groupType, seed, opts) -> story, ou nil et une raison. Déterministe : même type, même graine, mêmes
-- options = même histoire (aucune autre source de hasard). Gabarits : media/lua/shared/LivingKnox/Data/Stories.lua.
--   groupType : identifiant de type de groupe (registre LivingKnox.GroupTypes, LK08-T02) ; non contrôlé contre le
--               registre : un type sans fragment propre n'utilise que les fragments sans liste types.
--   seed      : entier (|seed| <= 2^50) ou chaîne non vide.
--   opts      : facultatif, { leaderName = <1..NAME_MAX octets> (sinon tiré), female = booléen (sinon tiré),
--               secrets = 1..SECRETS_MAX (SECRETS_DEFAULT sinon) }.
-- story = { format = 1, type, seed,
--           origin = { id, en, fr }, motivation = { id, en, fr }, tone = { id, en, fr },
--           leader = { name, female, past = { id, en, fr } },   -- fr déjà accordé au sexe du chef
--           summary = { en, fr },                               -- <= SUMMARY_MAX octets chacun (champ story de LK_Groups)
--           secrets = { { id, en, fr, private = true }, ... } } -- PRIVÉ : voir PRIVATE_FIELDS et publicView
-- Langue : le serveur compose l'anglais ET le français (le texte est dans les données, pas dans les traductions .json,
-- que getText ne résout pas sur un serveur MP) ; le consommateur choisit par Stories.text(story, lang).
-- Secrets : jamais envoyés aux clients ni écrits en ModData globale. Tout ce qui sort du serveur passe par
-- Stories.publicView(story), qui retire les champs de PRIVATE_FIELDS.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/Data/Stories"

local Stories = LivingKnox.Stories or {}
LivingKnox.Stories = Stories

Stories.FORMAT = 1
Stories.SUMMARY_MAX = 600       -- = LivingKnox.Groups.STORY_MAX ; vérifié par le banc
Stories.NAME_MAX = 32
Stories.TYPE_MAX = 24
Stories.SECRETS_DEFAULT = 2
Stories.SECRETS_MAX = 3
Stories.SEED_MAX = 1125899906842624 -- 2^50 : quotient de % sous 2^31 en Kahlua (base kahlua-lua.md)
Stories.LANGS = { "en", "fr" }
Stories.CATEGORIES = { "origins", "motivations", "tones", "leaderPasts", "secrets" }
Stories.PRIVATE_FIELDS = { "secrets" }

local LEADER_LINE = { en = { "Their leader is ", ", ", "." }, fr = { "Leur chef est ", ", ", "." } }

local function data() return LivingKnox.StoryData end
local function log() return LivingKnox.Log end

local function inList(list, value)
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Tirage reproductible : Park-Miller (sans opérateurs binaires, quotients sous 2^31 en Kahlua) suivi d'un mélange
-- non linéaire (reste modulo 65521), pour que des graines voisines donnent des histoires différentes.
-- Rend draw(n) -> entier de 1 à n.
local M = 2147483647

local function hashText(s, h)
    for i = 1, #s do
        h = (h * 31 + string.byte(s, i)) % M
    end
    return h
end

local function stream(seedValue, groupType)
    local base
    if type(seedValue) == "string" then
        base = hashText(seedValue, 17)
    else
        base = math.abs(seedValue) % M
    end
    local x = (base * 7919 + hashText(groupType, 3) * 104729 + 1) % M
    if x == 0 then x = 1 end
    local function draw(n)
        x = (x * 48271) % M
        x = (x + (x % 65521) * 31337) % M
        if x == 0 then x = 1 end
        return 1 + math.floor(x / M * n)
    end
    for _ = 1, 6 do draw(1) end
    return draw
end

-- Règles de compatibilité ------------------------------------------------------------------------------------------

-- Vrai si a exclut une étiquette de b.
local function excludesTag(a, b)
    if type(a.excludes) ~= "table" or type(b.tags) ~= "table" then return false end
    for _, tag in ipairs(a.excludes) do
        if inList(b.tags, tag) then return true end
    end
    return false
end

-- Le fragment est-il permis pour ce type ?
function Stories.allowedFor(frag, groupType)
    return frag.types == nil or inList(frag.types, groupType)
end

-- Compatibilité d'un fragment avec ceux déjà choisis (exclusions dans les deux sens, étiquettes requises).
function Stories.compatible(frag, chosen)
    local any = frag.requires == nil
    for _, other in ipairs(chosen) do
        if excludesTag(frag, other) or excludesTag(other, frag) then return false end
        if not any then
            for _, tag in ipairs(frag.requires) do
                if inList(other.tags, tag) then any = true end
            end
        end
    end
    return any
end

-- Fragments candidats d'une liste, dans l'ordre des données.
function Stories.candidates(list, groupType, chosen)
    local out = {}
    for _, frag in ipairs(list or {}) do
        if Stories.allowedFor(frag, groupType) and Stories.compatible(frag, chosen) then out[#out + 1] = frag end
    end
    return out
end

-- Composition ------------------------------------------------------------------------------------------------------

local function textOf(frag, female)
    local fr = frag.fr
    if female and frag.frF then fr = frag.frF end
    return { id = frag.id, en = frag.en, fr = fr }
end

local function checkSeed(seed)
    if type(seed) == "string" then return #seed > 0 end
    return type(seed) == "number" and seed == seed and math.floor(seed) == seed and math.abs(seed) <= Stories.SEED_MAX
end

local function checkType(groupType)
    return type(groupType) == "string" and #groupType >= 1 and #groupType <= Stories.TYPE_MAX
        and groupType:match("^[a-z0-9_]+$") ~= nil
end

-- Résumé d'une langue : origine, motivation, chef, ton. Au-delà de SUMMARY_MAX (données trop longues : le banc
-- l'interdit), le ton puis la motivation sont retirés, puis le texte est coupé.
function Stories.summary(story, lang)
    local line = LEADER_LINE[lang]
    local leader = line[1] .. story.leader.name .. line[2] .. story.leader.past[lang] .. line[3]
    local parts = { story.origin[lang], story.motivation[lang], leader, story.tone[lang] }
    local text = table.concat(parts, " ")
    if #text > Stories.SUMMARY_MAX then
        text = table.concat({ parts[1], parts[2], parts[3] }, " ")
    end
    if #text > Stories.SUMMARY_MAX then
        text = parts[1] .. " " .. parts[3]
    end
    if #text > Stories.SUMMARY_MAX then
        log().warn("stories: summary of type '%s' cut to %d characters", tostring(story.type), Stories.SUMMARY_MAX)
        text = string.sub(text, 1, Stories.SUMMARY_MAX)
    end
    return text
end

function Stories.compose(groupType, seed, opts)
    local D = data()
    if type(D) ~= "table" then return nil, "no story data" end
    if not checkType(groupType) then return nil, "bad type" end
    if not checkSeed(seed) then return nil, "bad seed" end
    if opts ~= nil and type(opts) ~= "table" then return nil, "bad options" end
    opts = opts or {}
    local count = opts.secrets or Stories.SECRETS_DEFAULT
    if type(count) ~= "number" or math.floor(count) ~= count or count < 1 or count > Stories.SECRETS_MAX then
        return nil, "bad secret count"
    end
    if opts.female ~= nil and type(opts.female) ~= "boolean" then return nil, "bad female flag" end
    if opts.leaderName ~= nil and not (type(opts.leaderName) == "string" and #opts.leaderName >= 1
            and #opts.leaderName <= Stories.NAME_MAX) then
        return nil, "bad leader name"
    end

    local draw = stream(seed, groupType)
    local chosen = {}
    local picked = {}
    for _, category in ipairs({ "origins", "motivations", "tones", "leaderPasts" }) do
        local list = Stories.candidates(D[category], groupType, chosen)
        if #list == 0 then
            log().warn("stories: no %s fragment fits type '%s'", category, groupType)
            return nil, "no " .. category .. " fragment"
        end
        local frag = list[draw(#list)]
        chosen[#chosen + 1] = frag
        picked[category] = frag
    end

    -- Chef : sexe et nom tirés seulement s'ils manquent (le tirage suit toujours le même ordre).
    local femaleDraw = draw(2) == 2
    local female = opts.female
    if female == nil then female = femaleDraw end
    local firsts = female and D.firstNamesFemale or D.firstNamesMale
    local name = firsts[draw(#firsts)] .. " " .. D.surnames[draw(#D.surnames)]
    if opts.leaderName then name = opts.leaderName end

    -- Secrets : sans remise, chacun compatible avec tout ce qui est déjà choisi.
    local secrets = {}
    for _ = 1, count do
        local list = Stories.candidates(D.secrets, groupType, chosen)
        local free = {}
        for _, frag in ipairs(list) do
            if not inList(chosen, frag) then free[#free + 1] = frag end
        end
        if #free == 0 then
            log().warn("stories: not enough secrets for type '%s'", groupType)
            return nil, "not enough secrets"
        end
        local frag = free[draw(#free)]
        chosen[#chosen + 1] = frag
        local s = textOf(frag)
        s.private = true
        secrets[#secrets + 1] = s
    end

    local story = {
        format = Stories.FORMAT, type = groupType, seed = seed,
        origin = textOf(picked.origins), motivation = textOf(picked.motivations), tone = textOf(picked.tones),
        leader = { name = name, female = female, past = textOf(picked.leaderPasts, female) },
        secrets = secrets,
    }
    story.summary = { en = Stories.summary(story, "en"), fr = Stories.summary(story, "fr") }
    return story
end

-- Lecture --------------------------------------------------------------------------------------------------------

-- Résumé dans une langue : "fr" / "FR" (Translator.getLanguage():name()) donne le français, toute autre l'anglais.
function Stories.text(story, lang)
    if type(story) ~= "table" or type(story.summary) ~= "table" then return nil end
    if type(lang) == "string" and string.lower(lang) == "fr" then return story.summary.fr end
    return story.summary.en
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Copie de l'histoire sans les champs privés : seule forme à envoyer à un client, à journaliser ou à publier.
function Stories.publicView(story)
    if type(story) ~= "table" then return nil end
    local out = copy(story)
    for _, field in ipairs(Stories.PRIVATE_FIELDS) do out[field] = nil end
    return out
end

-- Contrôle des données ---------------------------------------------------------------------------------------------

local FIELDS = { id = "string", types = "list", tags = "list", excludes = "list", requires = "list",
                 en = "string", fr = "string", frF = "string" }

local function isStringList(v)
    if type(v) ~= "table" then return false end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n ~= #v then return false end
    for _, x in ipairs(v) do
        if type(x) ~= "string" or x == "" then return false end
    end
    return true
end

-- Types à couvrir : ceux du registre LivingKnox.GroupTypes (LK08-T02, rempli par les fichiers de données partagés,
-- chargés avant media/lua/server), sinon les types livrés.
Stories.BUILTIN_TYPES = { "neutrals", "raiders", "settlers" }

function Stories.groupTypes()
    local registry = LivingKnox.GroupTypes
    if type(registry) == "table" and type(registry.ids) == "function" then
        local ids = registry.ids()
        if #ids > 0 then return ids end
    end
    return Stories.BUILTIN_TYPES
end

-- Liste des problèmes des gabarits (vide = données valides) : champs, identifiants uniques, textes non vides,
-- et pour chaque type de Stories.groupTypes() au moins un fragment par catégorie et SECRETS_MAX secrets.
function Stories.checkData()
    local D, problems = data(), {}
    if type(D) ~= "table" then return { "no story data" } end
    for _, category in ipairs(Stories.CATEGORIES) do
        local list = D[category]
        if type(list) ~= "table" or #list == 0 then
            problems[#problems + 1] = category .. ": empty"
        else
            local seen = {}
            for i, frag in ipairs(list) do
                local where = category .. "[" .. i .. "]"
                for key, value in pairs(frag) do
                    local kind = FIELDS[key]
                    if kind == nil or (key == "frF" and category ~= "leaderPasts") then
                        problems[#problems + 1] = where .. ": unknown field " .. tostring(key)
                    elseif kind == "list" and not isStringList(value) then
                        problems[#problems + 1] = where .. ": bad list " .. key
                    elseif kind == "string" and (type(value) ~= "string" or value == "") then
                        problems[#problems + 1] = where .. ": bad text " .. key
                    end
                end
                if type(frag.id) ~= "string" or type(frag.en) ~= "string" or type(frag.fr) ~= "string" then
                    problems[#problems + 1] = where .. ": id, en and fr required"
                elseif seen[frag.id] then
                    problems[#problems + 1] = where .. ": duplicate id " .. frag.id
                end
                if type(frag.id) == "string" then seen[frag.id] = true end
            end
        end
    end
    for _, key in ipairs({ "firstNamesMale", "firstNamesFemale", "surnames" }) do
        if not isStringList(D[key]) or #D[key] == 0 then problems[#problems + 1] = key .. ": empty" end
    end
    for _, groupType in ipairs(Stories.groupTypes()) do
        for _, category in ipairs(Stories.CATEGORIES) do
            local n = 0
            for _, frag in ipairs(D[category] or {}) do
                if type(frag) == "table" and Stories.allowedFor(frag, groupType) and frag.requires == nil then
                    n = n + 1
                end
            end
            local need = category == "secrets" and Stories.SECRETS_MAX or 1
            if n < need then
                problems[#problems + 1] = category .. ": " .. n .. " fragment(s) for type " .. groupType
            end
        end
    end
    return problems
end

return Stories
