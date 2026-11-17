-- Living Knox : registre des soins (LK21-T05, ADR docs/architecture/decisions/adr-blessures-soins.md D05). Un soin par
-- fichier (server/LivingKnox/Care/LK_Treat_<Id>.lua) appelle Care.registerTreatment(id, spec) ; ce module ne nomme aucun
-- soin. LK_Care.lua choisit le blessé et le soignant, puis demande ici le soin le plus urgent (Care.choose) ; le matériel
-- vient des sources de LK_CareSupplies.lua.
-- Autorité seulement : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- spec :
--   order     : rang entre soins qui répondent au même besoin (plus petit d'abord)
--   need      : besoin de plaie auquel le soin répond (Wounds.registerNeed, LK_WoundsNeeds.lua : son ordre y est déclaré)
--   wounds    : facultatif, fn(w, kindSpec) -> vrai si le soin traite cette plaie (sinon : toute plaie qui a le besoin)
--   gesture   : facultatif, geste du soignant pendant le soin (nœud généré par tools/gen_animsets.py) ; défaut
--               Care.TREAT_GESTURE
--   options   : { { duration = fn(level) -> durée de l'action vanilla (unités maxTime, 48 par seconde réelle),
--                   materials = { { id, match = fn(item) -> vrai, consume = fn(item, inv) -> info }, ... } }, ... } :
--               jeux de matériel possibles, le premier complet est pris ; une option sans matériel se fait à mains nues
--   effect    : fn(w, used, ectx) -> vrai si la plaie a changé ; used[id] = info rendue par consume ; ectx = { rnd,
--               level (compétence de soin simulée), inv (inventaire du soignant), wctx (contexte des plaies) }
-- Inscrire de nouveau un id le remplace (rechargement).
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Wounds"
require "LivingKnox/LK_WoundsNeeds"

local Care = LivingKnox.Care or {}
LivingKnox.Care = Care
local Wounds = LivingKnox.Wounds

Care.TREAT_GESTURE = "kneel"
Care.treatmentList = Care.treatmentList or {}
Care.treatmentById = Care.treatmentById or {}

local function validMaterial(m)
    return type(m) == "table" and type(m.id) == "string" and type(m.match) == "function"
        and type(m.consume) == "function"
end

local function validOption(o)
    if type(o) ~= "table" or type(o.duration) ~= "function" or type(o.materials) ~= "table" then return false end
    for _, m in ipairs(o.materials) do
        if not validMaterial(m) then return false end
    end
    return true
end

local function validTreatment(spec)
    if type(spec) ~= "table" or type(spec.need) ~= "string" or type(spec.effect) ~= "function"
        or type(spec.options) ~= "table" or #spec.options == 0 then
        return false, "treatment needs need, options and effect"
    end
    if spec.wounds ~= nil and type(spec.wounds) ~= "function" then return false, "wounds must be a function" end
    if spec.gesture ~= nil and type(spec.gesture) ~= "string" then return false, "gesture must be a string" end
    for _, o in ipairs(spec.options) do
        if not validOption(o) then return false, "option needs duration and materials { id, match, consume }" end
    end
    return true
end

local registry = LivingKnox.Registry.new("LivingKnox.Care.registerTreatment",
    { validate = validTreatment, items = Care.treatmentList, byKey = Care.treatmentById })

-- Inscrit le soin id (spec, voir l'en-tête) et rend spec ; spec refusée : erreur.
function Care.registerTreatment(id, spec)
    if type(spec) == "table" then spec.id = id end
    return registry:register(spec, 2)
end

-- Geste du soin t.
function Care.gestureOf(t)
    return t.gesture or Care.TREAT_GESTURE
end

-- Tirage dans [lo, hi] par le hasard r (fonction qui rend un nombre de [0, 1)).
function Care.roll(r, lo, hi)
    return lo + (hi - lo) * r()
end

-- Soins inscrits qui traitent la plaie w (entrée e de Wounds.needs) pour le besoin need.
local function treatmentsFor(need, w)
    local out = {}
    local spec = Wounds.kindById[w.kind]
    for _, t in ipairs(Care.treatmentList) do
        if t.need == need and (t.wounds == nil or t.wounds(w, spec)) then out[#out + 1] = t end
    end
    return out
end

-- Plaies de list qui demandent un soin inscrit (Wounds.needs, la plus urgente d'abord), chacune avec ses soins dans
-- l'ordre des besoins puis des soins : { { wound, index, bleed, treatments = { t... } }, ... }.
function Care.treatable(list, ctx)
    local out = {}
    for _, e in ipairs(Wounds.needs(list, ctx)) do
        local ts = {}
        for _, need in ipairs(e.care) do
            for _, t in ipairs(treatmentsFor(need, e.wound)) do ts[#ts + 1] = t end
        end
        if #ts > 0 then out[#out + 1] = { wound = e.wound, index = e.index, bleed = e.bleed, treatments = ts } end
    end
    return out
end

-- Soin le plus urgent faisable sur les plaies list : find(option) -> choix du matériel (picks) ou nil. Rend le plan
-- { id, part, kind, option, picks }, ou nil et la raison ("material" : un soin attend du matériel ; "none" : aucun).
function Care.choose(list, ctx, find)
    local why = "none"
    for _, e in ipairs(Care.treatable(list, ctx)) do
        for _, t in ipairs(e.treatments) do
            for i, o in ipairs(t.options) do
                local picks = find(o)
                if picks ~= nil then
                    return { id = t.id, part = e.wound.part, kind = e.wound.kind, option = i, picks = picks }
                end
                why = "material"
            end
        end
    end
    return nil, why
end

-- Plaie du blessé qui reçoit le soin du plan : la plus urgente que ce soin traite, de même partie d'abord ; ou nil.
function Care.target(list, ctx, plan)
    local other
    for _, e in ipairs(Care.treatable(list, ctx)) do
        for _, t in ipairs(e.treatments) do
            if t.id == plan.id then
                if e.wound.part == plan.part then return e.wound end
                other = other or e.wound
            end
        end
    end
    return other
end

return Care
