-- Living Knox : corvée « warm » (LK05-T04, inscrite en LK16-T07) : se réchauffer les mains devant un feu relevé au
-- foyer. Moteur : Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

LivingKnox.Routines.registerChore({ id = "warm", order = 20, gesture = "warmhands",
    duty = { keeper = 1, routine = 1 },
    trait = { drinker = 1 },
    avail = function(c) return #c.spots.fire > 0 end,
    plan = function(c) return c.place(c.nth(c.spots.fire)) end })
