-- Living Knox : routine « sommeil » des PNJ au foyer (LK05-T03, découpée en LK15-T02, ADR D05) : le membre va à son
-- couchage, s'y tourne et s'assoit au sol ; sans couchage, il s'assoit à l'intérieur. Activité du comportement
-- « sleep » qui porte son plan (LK16-T07) ; le relevé, les couchages et l'exécution sont dans LK_Routines.lua
-- (Routines.bedFor, Routines.runPlanned). Autorité seulement.
if isClient() then return end

require "LivingKnox/LK_Routines"

local Routines = LivingKnox.Routines

local function sleepPlan(posts, g, mid)
    local bed = Routines.bedFor(posts, g, mid)
    if bed == nil then return { kind = "sit", key = "sit" } end
    return { kind = "bed", key = string.format("bed %d,%d,%d", bed.x, bed.y, bed.z), x = bed.x, y = bed.y, z = bed.z,
        a = bed.a, sit = true }
end

Routines.registerActivity({ id = "sleep", behaviour = "sleep", order = 10, plan = sleepPlan })
