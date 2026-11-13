-- Living Knox : corvée « fire » (LK05-T04, inscrite en LK16-T07) : s'agenouiller devant une cheminée, un poêle ou une
-- cuisinière relevés au foyer. Moteur : Routines/LK_Routine_Chores.lua. Autorité seulement.
if isClient() then return end

require "LivingKnox/Routines/LK_Routine_Chores"

LivingKnox.Routines.registerChore({ id = "fire", order = 10, gesture = "kneel",
    duty = { keeper = 3, carer = 1, builder = 1, routine = 1 },
    role = { cook = 2, chores = 1 },
    avail = function(c) return #c.spots.fire > 0 end,
    plan = function(c) return c.place(c.nth(c.spots.fire)) end })
