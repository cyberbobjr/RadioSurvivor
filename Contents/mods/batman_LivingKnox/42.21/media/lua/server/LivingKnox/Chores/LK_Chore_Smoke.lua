-- Living Knox : corvée « smoke » (LK05-T04, inscrite en LK16-T07) : fumer, trait « smoker » seulement, à une fenêtre
-- libre du relevé, sinon sur place. Moteur : Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

LivingKnox.Routines.registerChore({ id = "smoke", order = 60, gesture = "smoke",
    trait = { smoker = 4 },
    plan = function(c)
        if #c.windows > 0 then return c.place(c.nth(c.windows)) end
        return nil
    end })
