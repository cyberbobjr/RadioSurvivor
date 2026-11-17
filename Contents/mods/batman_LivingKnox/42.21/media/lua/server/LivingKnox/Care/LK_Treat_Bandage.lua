-- Living Knox : soin « bander » (LK21-T05, ADR adr-blessures-soins.md D05), comme ISApplyBandage (doIt) de
-- media/lua/shared/TimedActions/ISApplyBandage.lua 42.22 :
--   - matériel : un objet que le vanilla accepte pour panser (InventoryItem.isCanBandage, script CanBandage,
--     J/inventory/InventoryItem.java:2617) ; un objet propre d'abord (type sans « Dirty »), sinon un sale ;
--   - durée : 120 - 4 x niveau de soin (:161) ; objet retiré de l'inventaire (:120) ;
--   - effet : vie du bandage tirée dans [(niveau + 1) x 0,5, (niveau + 1) x 1] plus BandagePower, 0 avec un objet sale
--     (:112-115) ; bandage à l'alcool si l'objet l'est (isAlcoholic, :119) ; type de l'objet gardé sur la plaie (rendu
--     sale au changement, LK_Treat_ChangeBandage.lua). L'infection par un objet infecté (:125-127) relève de LK21-T04.
if isClient() then return end

require "LivingKnox/LK_CareTreatments"
require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Wounds"

local Care = LivingKnox.Care

local function dirty(item)
    return string.find(item:getType(), "Dirty", 1, true) ~= nil
end

local function canBandage(item) return item:isCanBandage() == true end
local function cleanBandage(item) return canBandage(item) and not dirty(item) end

local function duration(level) return 120 - 4 * level end

-- Bandage posé sur w avec l'objet used.bandage (partagé avec le changement de bandage).
function Care.bandageWith(w, used, ectx)
    local item = used.bandage.item
    local level = ectx.level
    local life = 0
    if not dirty(item) then
        local power = item:getBandagePower()
        if not LivingKnox.Num.finite(power) or power < 0 then power = 0 end
        life = Care.roll(ectx.rnd, (level + 1) * 0.5, (level + 1) * 1.0) + power
    end
    LivingKnox.Wounds.bandage(w, life, item:isAlcoholic() == true)
    w.bandage.item = used.bandage.type
    return true
end

-- Matériel et durée d'un bandage (partagés avec le changement de bandage) : objet propre d'abord, sinon sale.
Care.BANDAGE_OPTIONS = {
    { duration = duration, materials = { { id = "bandage", match = cleanBandage, consume = Care.WHOLE } } },
    { duration = duration, materials = { { id = "bandage", match = canBandage, consume = Care.WHOLE } } },
}

Care.registerTreatment("bandage", {
    order = 10,
    need = "bandage",
    options = Care.BANDAGE_OPTIONS,
    effect = Care.bandageWith,
})
