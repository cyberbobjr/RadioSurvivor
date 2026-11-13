-- Living Knox : modèle d'itinéraire « zombie-door » (LK04-T14, inscrit en LK16-T11) : chemin vanilla d'un corps,
-- mais chaque escalade coûte ROUTE_PENALTY et chaque porte refusée a le léger bonus ROUTE_ZOMBIE_CLIMB_BONUS : chemin
-- vanilla qui préférerait une porte refusée à une clôture ou une fenêtre (voir planDoorRoute). Moteur : LK_Routing.lua.
if isClient() then return end

require "LivingKnox/LK_Routing"

local Obstacles = LivingKnox.Obstacles
local Routing = Obstacles.Routing

Routing.registerModel("zombie-door", { vanilla = true,
    refusedCost = function() return Obstacles.ROUTE_ZOMBIE_CLIMB_BONUS end,
    edgeCost = function(r, npcId, sqA, sqB, _, from)
        return Routing.bodyCost(r, npcId, sqA, sqB, from, Obstacles.ROUTE_ZOMBIE_CLIMB_BONUS, Obstacles.ROUTE_PENALTY)
    end,
})
