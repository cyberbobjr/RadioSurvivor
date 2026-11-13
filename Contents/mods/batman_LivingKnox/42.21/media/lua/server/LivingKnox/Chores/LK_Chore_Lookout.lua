-- Living Knox : corvée « lookout » (LK05-T04, inscrite en LK16-T07) : regarder dehors, debout, à une fenêtre du relevé
-- que nul guetteur ne tient (aucun geste). Moteur : Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

LivingKnox.Routines.registerChore({ id = "lookout", order = 40,
    duty = { keeper = 2, forager = 1, routine = 1 },
    role = { guard = 1, patrol = 1, scout = 1 },
    trait = { nervous = 3, keenHearing = 2 },
    avail = function(c) return #c.windows > 0 end,
    plan = function(c) return c.place(c.nth(c.windows)) end })
