-- Living Knox : sorte de chantier « barricade » (LK14-T03, inscrite en LK16-T02) : planches clouées sur une ouverture
-- extérieure du foyer (cadre vide, fenêtre, porte), une planche et un clou par étape, marteau (recette vanilla
-- M/entities/barricades/entity_barricade_planks.txt:46-60). Moteur : LK_Fortify.lua (plan des ouvertures, pose
-- Fortify.nailPlank, réparation de la planche extérieure Fortify.repairPlank, pose hors écran Fortify.applyBarricade).
-- Forme compacte du relevé hors écran : lettre « b ».
if isClient() then return end

require "LivingKnox/LK_Fortify"

local Fortify = LivingKnox.Fortify
local req = Fortify.req

-- Besoins de n planches clouées : n planches et n clous.
local function planks(n)
    return { req({ Fortify.PLANK }, n), req({ Fortify.NAILS }, n) }
end

Fortify.registerKind({ id = "barricade", code = "b", order = 10, unit = "plank(s)",
    work = function(_, c) return c.GESTURE, c.PLANK_MINUTES, Fortify.nailPlank end,
    repair = { run = function(site, gid, who) return Fortify.repairPlank(site, gid, who) end },
    offscreen = {
        types = { Fortify.PLANK, Fortify.NAILS },
        nextStage = function(_, c) return planks(1), "HAMMER", c.PLANK_MINUTES end,
        remaining = function(e) return planks(e.s - e.h) end,
        apply = function(gid, op, mark) return Fortify.applyBarricade(gid, op, mark) end,
        -- Porte ouverte : refusée en jeu (« door open »), donc pas gardée pour le rattrapage hors écran.
        skip = function(site)
            if site.opening ~= "door" then return false end
            local o = Fortify.openingOf(site)
            return o ~= nil and o:IsOpen() == true
        end,
    },
})
