-- Living Knox : routine « guet et ronde » des PNJ au foyer (LK05-T03, découpée en LK15-T02, ADR D05) : guetteur à son
-- poste, ronde autour du foyer (comportements « guard » et « patrol » ; plan : Routines.plan). Activités inscrites ici :
-- le relevé, le plan et l'exécution sont dans LK_Routines.lua (Routines.runPlanned). Autorité seulement.
if isClient() then return end

require "LivingKnox/LK_Routines"

local function run(id, st, ctx, g, fresh)
    return LivingKnox.Routines.runPlanned(id, st, ctx, g, fresh)
end

LivingKnox.Routines.registerActivity({ id = "watch.guard", behaviour = "guard", order = 10, run = run })
LivingKnox.Routines.registerActivity({ id = "watch.patrol", behaviour = "patrol", order = 10, run = run })
