-- Living Knox : soin « recoudre » (LK21-T05, ADR adr-blessures-soins.md D05), comme ISStitch (doIt) de
-- media/lua/shared/TimedActions/ISStitch.lua 42.22 :
--   - matériel (HStitch, media/lua/client/XpSystem/ISUI/ISHealthPanel.lua:1365-1447) : une aiguille chirurgicale
--     (Base.SutureNeedle, aiguille et fil en un), sinon une aiguille à coudre (Base.Needle ou étiquette SewingNeedle,
--     gardée) et du fil (Base.Thread ou étiquette Thread, une utilisation sur 20, UseDelta 0,05 :
--     media/scripts/generated/items/drainable.txt:2277-2290) ; l'objet passé à l'action est utilisé une fois
--     (:100-101) : l'aiguille chirurgicale, ou le fil ;
--   - durée : 150 avec l'aiguille chirurgicale, 200 sinon, moins 4 x niveau de soin (:144-153 ; le porte-aiguille,
--     qui accélère aussi, relève de la trousse, LK21-T06) ;
--   - effet : points posés (Wounds.stitch, setStitched :108) avec un temps de départ (1 + niveau) / 2 x [2, 5]
--     (:118-120), puis une chance sur 5 + 2,5 x niveau que la plaie s'infecte (:122-125).
if isClient() then return end

require "LivingKnox/LK_CareTreatments"
require "LivingKnox/LK_CareSupplies"
require "LivingKnox/LK_Wounds"

local Care = LivingKnox.Care

local function sutureNeedle(item) return item:getType() == "SutureNeedle" end
local function needle(item) return item:getType() == "Needle" or item:hasTag(ItemTag.SEWING_NEEDLE) end
local function thread(item)
    return (item:getType() == "Thread" or item:hasTag(ItemTag.THREAD)) and item:getCurrentUsesFloat() >= 0
end

Care.registerTreatment("stitch", {
    order = 10,
    need = "stitch",
    options = {
        { duration = function(level) return 150 - 4 * level end,
          materials = { { id = "suture", match = sutureNeedle, consume = Care.USE } } },
        { duration = function(level) return 200 - 4 * level end,
          materials = { { id = "needle", match = needle, consume = Care.TOOL },
                        { id = "thread", match = thread, consume = Care.USE } } },
    },
    effect = function(w, _, ectx)
        local level = ectx.level
        if not LivingKnox.Wounds.stitch(w, (1 + level) / 2 * Care.roll(ectx.rnd, 2, 5)) then return false end
        if math.floor(ectx.rnd() * (5 + level * 2.5)) == 0 then w.infected = true end
        return true
    end,
})
