-- Living Knox : sorte de chantier « repair » (LK14-T06, inscrite en LK16-T02) : réparation d'un ouvrage abîmé du foyer
-- (site.target : sorte réparée, dont la spec porte la réparation). Geste du marteau (son vanilla « Hammering » des deux
-- réparations), CFG.REPAIR_MINUTES[cible] minutes de jeu ; réparations non faisables notées comme besoin du groupe
-- (Fortify.needOf). Pas de rattrapage hors écran. Moteur : LK_Fortify.lua (plan, Fortify.repair).
if isClient() then return end

require "LivingKnox/LK_Fortify"

local Fortify = LivingKnox.Fortify

Fortify.registerKind({ id = "repair", order = 40, unit = "repair(s)", need = true,
    work = function(site, c)
        return c.GESTURE, (c.REPAIR_MINUTES or {})[site.target] or c.PLANK_MINUTES, Fortify.repair
    end,
})
