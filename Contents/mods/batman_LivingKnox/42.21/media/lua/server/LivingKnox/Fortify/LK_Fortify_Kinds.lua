-- Living Knox : fortification du foyer, registre des sortes de chantier (Fortify.registerKind, tables dérivées
-- KINDS, OFF_KINDS, STAGES, REPAIRS...)
-- LK20-T07 : sorti de LK_Fortify.lua sans changement de comportement ; façade et vue d'ensemble : LK_Fortify.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/Fortify/LK_Fortify_Common"

local Fortify = LivingKnox.Fortify

-- ================================================================ sortes de chantier (LK16-T02)
-- Ce module ne décrit AUCUNE sorte de chantier : chacune s'inscrit par Fortify.registerKind(spec) depuis son fichier
-- media/lua/server/LivingKnox/Fortify/LK_Fortify_<Nom>.lua (chargé par le jeu, sous-dossiers compris, après LK_Fortify.lua
-- qu'il requiert). Les tables KINDS, OFF_KINDS, STAGES, REPAIRS, STRUCTURES, les codes et les motifs de la forme
-- compacte en sont DÉRIVÉS à chaque inscription. spec :
--   id       : nom unique (site.kind ; identifiant de chantier « <id>:x,y,zF »), minuscules, chiffres, « _ »
--   order    : rang dans le registre, plus petit d'abord ; à égalité, par id (ordre stable, sans next : Kahlua)
--   unit     : unité du journal de fin de chantier (« plank(s) »)
--   work(site, c) : geste, minutes de jeu de travail avant chaque pose (c = Fortify.CFG) et effet(site, gid, who)
--              qui pose une étape : rend un texte et les étapes faites, ou nil et une raison
--   stages   : facultatif, étapes d'un ouvrage du pourtour { entity, prev, sprites = { W, N }, materials, tool,
--              time (clé de CFG.TIME) } ; site du plan, travail et rattrapage hors écran en sont tirés
--   names    : facultatif, { [nom d'objet vanilla] = étapes faites } reconnus sur un bord par le relevé
--   ring     : facultatif, style de foyer (« building », « camp ») dont le pourtour est fait de cette sorte
--   repair   : facultatif, réparation de cet ouvrage (site.target = id) : { run(site, gid, who) } ; ouvrage du pourtour :
--              plus la recette vanilla { tools, part = { type, n }, options = { { type, n }... } }
--   need     : facultatif, vrai si ses chantiers non faisables sont notés comme besoin du groupe (réparations)
--   plan(survey, opts) : facultatif, chantiers de plus relevés par la sorte (liste de sites complets), placés après
--              le pourtour (opts.urgent : plan après une attaque)
--   code, offscreen : facultatifs ensemble, rattrapage hors écran : code = une lettre minuscule unique (forme
--              compacte) ; offscreen = { nextStage(e, c) -> besoins, outil, minutes ; remaining(e) -> besoins ;
--              apply(gid, op, mark) -> issue, objet marqué, étapes posées, raison ; skip(site) facultatif (chantier
--              du plan non gardé hors écran) ; types facultatif (types de matériaux comptés hors écran, en plus de ceux
--              des étapes) }
-- Inscrire de nouveau un id le remplace (rechargement) ; un code déjà pris par une autre sorte est refusé.
Fortify.kinds = Fortify.kinds or { list = {}, byId = {}, byCode = {} }

local KIND_FIELDS = { work = "function", plan = "function", stages = "table", names = "table", repair = "table" }

-- Raison du refus de spec, ou nil. Règle propre à ce registre : un code déjà pris par une autre sorte est refusé.
local function kindProblem(spec)
    if type(spec) ~= "table" then return "spec must be a table" end
    if type(spec.id) ~= "string" or string.match(spec.id, "^[a-z][a-z0-9_]*$") == nil then
        return "id must be a lowercase name"
    end
    if type(spec.order) ~= "number" or type(spec.unit) ~= "string" or type(spec.work) ~= "function" then
        return spec.id .. " needs order, unit and work"
    end
    for field, t in pairs(KIND_FIELDS) do
        if spec[field] ~= nil and type(spec[field]) ~= t then return spec.id .. "." .. field .. " must be a " .. t end
    end
    if spec.repair ~= nil and type(spec.repair.run) ~= "function" then return spec.id .. ".repair needs run" end
    local off = spec.offscreen
    if off == nil and spec.code == nil then return nil end
    if type(off) ~= "table" or type(off.nextStage) ~= "function" or type(off.remaining) ~= "function"
        or type(off.apply) ~= "function" then
        return spec.id .. ".offscreen needs nextStage, remaining and apply"
    end
    if type(spec.code) ~= "string" or string.match(spec.code, "^[a-z]$") == nil then
        return spec.id .. ".code must be one lowercase letter"
    end
    local owner = Fortify.kinds.byCode[spec.code]
    if owner ~= nil and owner ~= spec.id then
        return 'code "' .. spec.code .. '" already used by ' .. owner
    end
    return nil
end

local function validKind(spec)
    local why = kindProblem(spec)
    return why == nil, why
end

-- LK16-T01 : socle commun (LivingKnox.Registry) ; Fortify.kinds.list et Fortify.kinds.byId en sont la liste triée et
-- l'index (mêmes tables d'une inscription à l'autre).
local kindRegistry = LivingKnox.Registry.new("LivingKnox.Fortify.registerKind",
    { validate = validKind, items = Fortify.kinds.list, byKey = Fortify.kinds.byId })

-- Tables dérivées du registre (une seule source : les specs inscrites).
local function deriveKinds()
    local K = Fortify.kinds
    local byCode, codes = {}, {}
    local kinds, off, stages, repairs, names, structures, types, seen = {}, {}, {}, {}, {}, {}, {}, {}
    local function addType(t)
        if not seen[t] then
            seen[t] = true
            types[#types + 1] = t
        end
    end
    for _, s in ipairs(K.list) do
        kinds[s.id] = true
        if s.stages ~= nil then
            stages[s.id] = s.stages
            for _, st in ipairs(s.stages) do
                if st.sprites ~= nil then structures[st.entity] = st.sprites end
            end
        end
        for name, n in pairs(s.names or {}) do names[name] = { kind = s.id, steps = n } end
        if s.repair ~= nil and s.repair.part ~= nil then repairs[s.id] = s.repair end
        if s.offscreen ~= nil then
            off[s.id] = true
            byCode[s.code] = s.id
            codes[#codes + 1] = s.code
            for _, t in ipairs(s.offscreen.types or {}) do addType(t) end
            for _, st in ipairs(s.stages or {}) do
                for _, r in ipairs(st.materials) do
                    for _, t in ipairs(r.types) do addType(t) end
                end
            end
        end
    end
    K.byCode = byCode
    local set = table.concat(codes)
    K.sitePattern = set ~= "" and ("^([" .. set .. "])([guo])(%-?%d+),(%-?%d+),(%-?%d+)([NW])([01])(%d)(%d)$") or nil
    K.opPattern = set ~= "" and ("^(%d+):([" .. set .. "])(%-?%d+),(%-?%d+),(%-?%d+)([NW])([01])(%d)(%d)$") or nil
    Fortify.KINDS, Fortify.OFF_KINDS, Fortify.STAGES, Fortify.REPAIRS = kinds, off, stages, repairs
    Fortify.BUILT_NAMES, Fortify.STRUCTURES, Fortify.OFF_TYPES = names, structures, types
end

-- Inscrit la sorte de chantier spec (voir plus haut) ; rend spec. Erreur claire si spec est invalide ou si son code
-- est déjà pris : rien n'est inscrit.
function Fortify.registerKind(spec)
    kindRegistry:register(spec, 2)
    deriveKinds()
    return spec
end

-- Sortes inscrites, dans l'ordre du registre (liste à ne pas modifier).
function Fortify.kindList()
    return kindRegistry:list()
end

-- Spec de la sorte id, ou nil.
function Fortify.kindOf(id)
    return kindRegistry:get(id)
end

-- Sorte dont le pourtour d'un foyer de style style est fait (premier dans l'ordre du registre), ou nil.
function Fortify.ringKindOf(style)
    for _, s in ipairs(Fortify.kinds.list) do
        if s.ring == style then return s.id end
    end
    return nil
end

deriveKinds()
