-- Living Knox : modèle d'itinéraire « exit-loose » (LK04-T16, inscrit en LK16-T11) : comme « exit », mais une porte
-- ou une fenêtre que le PNJ ne passera pas (refusée, barricadée) coûte ROUTE_LOOSE_PENALTY au lieu d'être
-- infranchissable, marquée "refused" : destination hors d'atteinte par les règles (pièce derrière une porte verrouillée
-- sans clé), sortie du bâtiment de départ par une porte quand même. Moteur : LK_Routing.lua.
if isClient() then return end

require "LivingKnox/LK_Routing"

local Obstacles = LivingKnox.Obstacles
local Routing = Obstacles.Routing

require "LivingKnox/Routing/LK_Route_Exit"

Routing.registerModel("exit-loose", {
    maxNodes = function() return Obstacles.ROUTE_EXIT_MAX_NODES end,
    edgeCost = function(r, npcId, sqA, sqB, exitKeys, from)
        local c, what = Routing.get("exit").edgeCost(r, npcId, sqA, sqB, exitKeys, from)
        if c == nil then return Obstacles.ROUTE_LOOSE_PENALTY, "refused" end
        return c, what
    end,
})
