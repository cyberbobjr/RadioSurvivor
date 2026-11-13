-- Living Knox : modèle d'itinéraire « npc » (LK04-T09, inscrit en LK16-T11) : porte d'abord (fenêtre, clôture basse
-- et portail refusé à ROUTE_PENALTY, porte refusée et barricade infranchissables). Moteur : LK_Routing.lua.
if isClient() then return end

require "LivingKnox/LK_Routing"

local Obstacles = LivingKnox.Obstacles
local Routing = Obstacles.Routing

Routing.registerModel("npc", {
    edgeCost = function(r, npcId, sqA, sqB, _, from)
        return Routing.doorFirstCost(r, npcId, sqA, sqB, from, Obstacles.ROUTE_PENALTY)
    end,
})
