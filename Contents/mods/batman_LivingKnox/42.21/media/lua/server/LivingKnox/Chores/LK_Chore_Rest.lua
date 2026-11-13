-- Living Knox : corvée « rest » (LK05-T04, inscrite en LK16-T07) : s'asseoir sur place ; repli du tirage
-- (Routines.CHORE_FALLBACK). Moteur : Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

LivingKnox.Routines.registerChore({ id = "rest", order = 80, gesture = "sit",
    duty = { keeper = 2, carer = 1, forager = 2, builder = 1, routine = 3 },
    trait = { drinker = 2 } })
