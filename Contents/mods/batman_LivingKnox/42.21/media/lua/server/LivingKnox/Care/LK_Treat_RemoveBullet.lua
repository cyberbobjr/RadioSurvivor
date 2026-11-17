-- Living Knox : soin « retirer une balle » (LK21-T05, ADR adr-blessures-soins.md D05), comme ISRemoveBullet de
-- media/lua/shared/TimedActions/ISRemoveBullet.lua 42.22 :
--   - plaies : balle restée dans la plaie (type « bullet ») ;
--   - matériel (HRemoveBullet, media/lua/client/XpSystem/ISUI/ISHealthPanel.lua:1674-1705) : une pince (étiquette
--     RemoveBullet, Tweezers, SutureNeedleHolder), gardée ; pas de retrait à mains nues ;
--   - durée : 250 - 6 x niveau de soin (:78-84) ;
--   - effet : balle retirée (Wounds.extract : plaie profonde, nouvelle durée et nouveau saignement selon le niveau,
--     setHaveBullet(false, niveau) :69).
if isClient() then return end

require "LivingKnox/LK_CareTreatments"
require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Wounds"

local Care = LivingKnox.Care

local function remover(item)
    local t = item:getType()
    return item:hasTag(ItemTag.REMOVE_BULLET) or t == "SutureNeedleHolder" or t == "Tweezers"
end

Care.registerTreatment("removebullet", {
    order = 10,
    need = "remove",
    wounds = function(w) return w.kind == "bullet" end,
    options = {
        { duration = function(level) return 250 - 6 * level end,
          materials = { { id = "tool", match = remover, consume = Care.TOOL } } },
    },
    effect = function(w, _, ectx)
        return LivingKnox.Wounds.extract(w, ectx.wctx, ectx.level)
    end,
})
