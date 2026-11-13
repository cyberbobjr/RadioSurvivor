-- Living Knox : modèle d'itinéraire « detour » (LK04-T14, inscrit en LK16-T11) : règle porte d'abord coupée
-- (DOORS_FIRST faux) : fenêtres et clôtures sans surcoût, mais portes et fenêtres refusées infranchissables. Moteur :
-- LK_Routing.lua.
if isClient() then return end

require "LivingKnox/LK_Routing"

local Obstacles = LivingKnox.Obstacles
local Routing = Obstacles.Routing

Routing.registerModel("detour", {
    edgeCost = function(r, npcId, sqA, sqB, _, from)
        return Routing.doorFirstCost(r, npcId, sqA, sqB, from, 0)
    end,
})
