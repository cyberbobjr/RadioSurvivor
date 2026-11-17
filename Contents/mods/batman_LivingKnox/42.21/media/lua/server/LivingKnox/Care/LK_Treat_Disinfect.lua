-- Living Knox : soin « nettoyer et désinfecter » (LK21-T05, ADR adr-blessures-soins.md D05), comme ISDisinfect de
-- media/lua/shared/TimedActions/ISDisinfect.lua 42.22 :
--   - matériel (HDisinfect:checkItem, media/lua/client/XpSystem/ISUI/ISHealthPanel.lua:1310-1320) : un récipient dont le
--     fluide compte au moins 40 % d'alcool et plus de 0,15 l (désinfectant, alcool fort), ou un consommable d'AlcoholPower
--     4 (lingettes, cotons alcoolisés : media/scripts/generated/items/drainable.txt:1503-1530) ;
--   - durée : 120 - 4 x niveau de soin (:102) ;
--   - usage : récipient vidé de 0,15 l (:83-85), consommable utilisé une fois (:86-87) ;
--   - effet : puissance d'alcool ajoutée à la plaie (Wounds.disinfect) : AlcoholPower du consommable (:71), ou
--     4 x alcool / quantité du récipient, relus avant l'usage (:74-77).
if isClient() then return end

require "LivingKnox/LK_CareTreatments"
require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Wounds"

local Care = LivingKnox.Care

local DOSE = 0.15          -- litres pris au récipient (ISDisinfect.lua:83-84)
local STRENGTH = 0.4       -- part d'alcool minimale (ISHealthPanel.lua:1313)
local WIPE_POWER = 4.0     -- AlcoholPower d'un consommable accepté (ISHealthPanel.lua:1318)

local function bottle(item)
    local fc = item:getFluidContainer()
    if fc == nil then return nil end
    local amount = fc:getAmount()
    if not LivingKnox.Num.finite(amount) or amount <= DOSE then return nil end
    local alcohol = fc:getProperties():getAlcohol()
    if not LivingKnox.Num.finite(alcohol) or alcohol / amount + 0.001 < STRENGTH then return nil end
    return fc, amount, alcohol
end

local function disinfectant(item)
    if bottle(item) ~= nil then return true end
    return item:IsDrainable() == true and item:getAlcoholPower() == WIPE_POWER
end

local function consume(item)
    local fc, amount, alcohol = bottle(item)
    if fc ~= nil then
        fc:adjustAmount(amount - DOSE)
        return { item = item, type = item:getFullType(), power = 4 * alcohol / amount }
    end
    local out = Care.USE(item)
    out.power = item:getAlcoholPower()
    return out
end

Care.registerTreatment("disinfect", {
    order = 10,
    need = "disinfect",
    options = {
        { duration = function(level) return 120 - 4 * level end,
          materials = { { id = "alcohol", match = disinfectant, consume = consume } } },
    },
    effect = function(w, used)
        LivingKnox.Wounds.disinfect(w, used.alcohol.power)
        return true
    end,
})
