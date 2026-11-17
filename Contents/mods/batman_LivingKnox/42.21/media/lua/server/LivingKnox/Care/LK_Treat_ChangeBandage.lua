-- Living Knox : soin « changer un bandage sale » (LK21-T05, ADR adr-blessures-soins.md D05) : le bandage sale est
-- retiré comme ISApplyBandage sans doIt (media/lua/shared/TimedActions/ISApplyBandage.lua:128-140, 42.22) : l'objet du
-- bandage (type gardé sur la plaie) revient au soignant ; sale (vie 0) et sans l'étiquette ReusableBandage, il est
-- utilisé une fois (InventoryItem.Use : remplacé par son ReplaceOnUse, Bandage -> BandageDirty, ou retiré,
-- J/inventory/InventoryItem.java:1153-1200). Puis un bandage neuf est posé comme le soin « bander »
-- (LK_Treat_Bandage.lua : même matériel, même durée, même effet). Bandage sans type connu (posé hors du registre des
-- soins) : rien ne revient.
if isClient() then return end

require "LivingKnox/LK_CareTreatments"
require "LivingKnox/Care/LK_Treat_Bandage"

local Care = LivingKnox.Care

-- Objet du bandage retiré de w rendu dans l'inventaire inv ; rend l'objet rendu, ou nil.
local function giveBack(w, inv)
    local t = w.bandage ~= nil and w.bandage.item or nil
    if t == nil or inv == nil then return nil end
    local item = instanceItem(t)
    if item == nil then return nil end
    inv:AddItem(item)
    if w.bandage.life <= 0 and not item:hasTag(ItemTag.REUSABLE_BANDAGE) then item:Use() end
    return item
end

Care.registerTreatment("changebandage", {
    order = 10,
    need = "change",
    options = Care.BANDAGE_OPTIONS,
    effect = function(w, used, ectx)
        giveBack(w, ectx.inv)
        LivingKnox.Wounds.unbandage(w)
        return Care.bandageWith(w, used, ectx)
    end,
})
