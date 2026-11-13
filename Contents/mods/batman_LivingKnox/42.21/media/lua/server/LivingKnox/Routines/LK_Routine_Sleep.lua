-- Living Knox : routine « sommeil » des PNJ au foyer (LK05-T03, découpée en LK15-T02, ADR D05) : le membre va à son
-- couchage, s'y tourne et s'assoit au sol ; sans couchage, il s'assoit à l'intérieur (plan : Routines.plan). Activité
-- du comportement « sleep » ; le relevé, le plan et l'exécution sont dans LK_Routines.lua (Routines.runPlanned).
-- Autorité seulement.
if isClient() then return end

require "LivingKnox/LK_Routines"

LivingKnox.Routines.registerActivity({ id = "sleep", behaviour = "sleep", order = 10,
    run = function(id, st, ctx, g, fresh)
        return LivingKnox.Routines.runPlanned(id, st, ctx, g, fresh)
    end })
