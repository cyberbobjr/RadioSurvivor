-- Living Knox : soin « retirer des éclats de verre » (LK21-T05, ADR adr-blessures-soins.md D05), comme ISRemoveGlass
-- de media/lua/shared/TimedActions/ISRemoveGlass.lua 42.22 :
--   - plaies : éclats de verre (type « glass » avec son corps étranger) ;
--   - matériel (HRemoveGlass, media/lua/client/XpSystem/ISUI/ISHealthPanel.lua:1484-1529) : une pince (étiquette
--     RemoveGlass, Tweezers, SutureNeedleHolder), gardée ; sinon à mains nues ;
--   - durée : 150 avec l'outil, 300 à mains nues, moins 4 x niveau de soin (:82-92) ;
--   - effet : corps étranger retiré (Wounds.extract, setHaveGlass(false) :73).
if isClient() then return end

require "LivingKnox/LK_CareTreatments"
require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Wounds"

local Care = LivingKnox.Care

local function remover(item)
    local t = item:getType()
    return item:hasTag(ItemTag.REMOVE_GLASS) or t == "SutureNeedleHolder" or t == "Tweezers"
end

Care.registerTreatment("removeglass", {
    order = 10,
    need = "remove",
    wounds = function(w) return w.kind == "glass" end,
    options = {
        { duration = function(level) return 150 - 4 * level end,
          materials = { { id = "tool", match = remover, consume = Care.TOOL } } },
        { duration = function(level) return 300 - 4 * level end, materials = {} },
    },
    effect = function(w, _, ectx)
        return LivingKnox.Wounds.extract(w, ectx.wctx, ectx.level)
    end,
})
