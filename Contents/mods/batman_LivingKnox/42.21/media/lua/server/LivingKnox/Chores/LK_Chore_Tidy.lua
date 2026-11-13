-- Living Knox : corvée « tidy » (LK05-T04, inscrite en LK16-T07) : fouiller un meuble à ranger relevé au foyer (lecture
-- seule : aucun conteneur ouvert ni modifié). Moteur : Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

LivingKnox.Routines.registerChore({ id = "tidy", order = 30, gesture = "rummage",
    duty = { keeper = 3, carer = 1, forager = 3, builder = 1, routine = 1 },
    role = { chores = 1, scavenge = 1 },
    trait = { tidy = 3 },
    avail = function(c) return #c.spots.furniture > 0 end,
    plan = function(c) return c.place(c.nth(c.spots.furniture)) end })
