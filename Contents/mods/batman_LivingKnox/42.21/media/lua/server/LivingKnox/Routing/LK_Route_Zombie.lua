-- Living Knox : modèle d'itinéraire « zombie » (LK04-T09, inscrit en LK16-T11) : chemin vanilla d'un corps (portes,
-- fenêtres et clôtures basses traversées sans surcoût, portail fermé enjambé ; fiche deplacement.md, section 2) ; une
-- porte que le PNJ ne passera pas (doorRefusal) est franchie comme les autres mais marquée "refused" (LK04-T14).
-- Léger bonus d'escalade (essai solo du 2026-10-11) : à longueur égale ou presque, le chemin vanilla peut passer par une
-- fenêtre que l'A* aurait départagée autrement ; le modèle choisit donc l'escalade dans le doute, pour que la
-- vérification des tronçons soit prudente. Moteur : LK_Routing.lua.
if isClient() then return end

require "LivingKnox/LK_Routing"

local Obstacles = LivingKnox.Obstacles
local Routing = Obstacles.Routing

Routing.registerModel("zombie", { vanilla = true,
    refusedCost = function() return 0 end,
    edgeCost = function(r, npcId, sqA, sqB, _, from)
        return Routing.bodyCost(r, npcId, sqA, sqB, from, 0, Obstacles.ROUTE_ZOMBIE_CLIMB_BONUS)
    end,
})
