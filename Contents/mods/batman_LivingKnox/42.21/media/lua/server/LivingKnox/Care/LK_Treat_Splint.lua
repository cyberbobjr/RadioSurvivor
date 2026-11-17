-- Living Knox : soin « poser une attelle » (LK21-T05, ADR adr-blessures-soins.md D05), comme ISSplint (doIt) de
-- media/lua/shared/TimedActions/ISSplint.lua 42.22 :
--   - matériel (HSplint:checkItem, media/lua/client/XpSystem/ISUI/ISHealthPanel.lua:1542-1552) : une attelle
--     (Base.Splint), sinon une planche, une branche ou un bâton (Plank, TreeBranch, TreeBranch2, WoodenStick,
--     WoodenStick2) et du tissu déchiré (RippedSheets) ; tout est retiré de l'inventaire (:95-102) ;
--   - durée : 140 - 4 x niveau de soin (:152) ;
--   - effet : attelle de facteur (niveau + 1) / 2 (Wounds.splint, :90-94).
if isClient() then return end

require "LivingKnox/LK_CareTreatments"
require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Wounds"

local Care = LivingKnox.Care

local STICKS = { Plank = true, TreeBranch = true, TreeBranch2 = true, WoodenStick = true, WoodenStick2 = true }

local function ofType(t) return function(item) return item:getType() == t end end
local function stick(item) return STICKS[item:getType()] == true end
local function duration(level) return 140 - 4 * level end

Care.registerTreatment("splint", {
    order = 10,
    need = "splint",
    options = {
        { duration = duration, materials = { { id = "splint", match = ofType("Splint"), consume = Care.WHOLE } } },
        { duration = duration, materials = { { id = "stick", match = stick, consume = Care.WHOLE },
                                              { id = "cloth", match = ofType("RippedSheets"), consume = Care.WHOLE } } },
    },
    effect = function(w, _, ectx)
        return LivingKnox.Wounds.splint(w, (ectx.level + 1) / 2)
    end,
})
