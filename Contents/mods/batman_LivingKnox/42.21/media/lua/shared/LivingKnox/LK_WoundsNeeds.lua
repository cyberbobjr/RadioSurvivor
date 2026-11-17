-- Living Knox : soins demandés par les plaies (LK21-T01, ADR adr-blessures-soins.md D01, D05) : données lues par
-- LK_Care (LK21-T05) pour choisir le soin, sans règle de soin ici. Modèle des plaies : LK_Wounds.lua.
require "LivingKnox/LK_Wounds"

local Wounds = LivingKnox.Wounds

-- ================================================================ soins demandés (données pour LK_Care)
-- Registre des soins qu'une plaie peut demander : Wounds.registerNeed({ id, order, test = fn(w, spec) -> vrai }).
-- Les noms sont ceux des soins de LK21-T05 ; un nouveau soin s'inscrit sans toucher ce module.
Wounds.needList = Wounds.needList or {}
Wounds.needById = Wounds.needById or {}

local needRegistry = LivingKnox.Registry.new("LivingKnox.Wounds.registerNeed", {
    validate = function(spec)
        if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.test) ~= "function" then
            return false, "need needs id and test"
        end
        return true
    end,
    items = Wounds.needList, byKey = Wounds.needById })

function Wounds.registerNeed(spec)
    return needRegistry:register(spec, 2)
end

-- Soins demandés par chaque plaie qui en demande un, la plus urgente d'abord (saignement le plus fort, puis le plus de
-- soins, puis l'ordre de la liste) : { { wound, index, care = { id... }, bleed = fraction par heure } }.
function Wounds.needs(list, ctx)
    local out = {}
    for i, w in ipairs(list) do
        local spec = Wounds.kindById[w.kind]
        if spec ~= nil then
            local care = {}
            for _, need in ipairs(Wounds.needList) do
                if need.test(w, spec) then care[#care + 1] = need.id end
            end
            if #care > 0 then
                out[#out + 1] = { wound = w, index = i, care = care, bleed = Wounds.woundBleeding(w, ctx) }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.bleed ~= b.bleed then return a.bleed > b.bleed end
        if #a.care ~= #b.care then return #a.care > #b.care end
        return a.index < b.index
    end)
    return out
end

-- Plaie la plus urgente (première de Wounds.needs), ou nil.
function Wounds.worst(list, ctx)
    return Wounds.needs(list, ctx)[1]
end

-- Soins du vanilla (menus d'ISHealthPanel.lua : retrait :812, :844 ; points :1379 ; attelle :1609-1612).
Wounds.registerNeed({ id = "remove", order = 10, test = function(w) return w.foreign end })
Wounds.registerNeed({ id = "disinfect", order = 20,
    test = function(w) return w.infected and (w.alcohol or 0) <= 0 end })
Wounds.registerNeed({ id = "stitch", order = 30,
    test = function(w, spec) return spec.stitch == true and not w.foreign and w.stitch == nil and Wounds.hasTime(w) end })
Wounds.registerNeed({ id = "bandage", order = 40,
    test = function(w, spec)
        return spec.bandage == true and w.bandage == nil and (Wounds.hasTime(w) or w.foreign or w.bleed > 0 or w.stitch ~= nil)
    end })
Wounds.registerNeed({ id = "change", order = 50,
    test = function(w) return w.bandage ~= nil and w.bandage.life <= 0 end })
Wounds.registerNeed({ id = "splint", order = 60,
    test = function(w, spec) return spec.splint == true and w.splint == nil and Wounds.hasTime(w) end })

return Wounds
