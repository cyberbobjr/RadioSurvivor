-- Living Knox : corvée « repair » (LK05-T04, inscrite en LK16-T07) : marteler à une porte ou une fenêtre du relevé,
-- regard vers elle (direction du poste). Moteur : Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

LivingKnox.Routines.registerChore({ id = "repair", order = 50, gesture = "hammer",
    duty = { keeper = 1, forager = 1, builder = 5 },
    role = { maintain = 2, fortify = 1 },
    trait = { strong = 2 },
    avail = function(c) return #c.doors > 0 end,
    plan = function(c) return c.place(c.nth(c.doors)) end })
