-- Living Knox : modèle d'itinéraire « exit » (LK04-T15, inscrit en LK16-T11) : comme « npc », mais une escalade dont
-- une case est dans un bâtiment de exitKeys (identifiants getIDString -> vrai) coûte ROUTE_EXIT_PENALTY ; recherche
-- bornée à ROUTE_EXIT_MAX_NODES cases. Moteur : LK_Routing.lua.
if isClient() then return end

require "LivingKnox/LK_Routing"

local Obstacles = LivingKnox.Obstacles
local Routing = Obstacles.Routing

Routing.registerModel("exit", {
    maxNodes = function() return Obstacles.ROUTE_EXIT_MAX_NODES end,
    edgeCost = function(r, npcId, sqA, sqB, exitKeys, from)
        local P = Obstacles.ROUTE_PENALTY
        if exitKeys ~= nil then
            local ia, ib = Obstacles.buildingOf(sqA), Obstacles.buildingOf(sqB)
            if (ia ~= nil and exitKeys[ia]) or (ib ~= nil and exitKeys[ib]) then P = Obstacles.ROUTE_EXIT_PENALTY end
        end
        return Routing.doorFirstCost(r, npcId, sqA, sqB, from, P)
    end,
})
