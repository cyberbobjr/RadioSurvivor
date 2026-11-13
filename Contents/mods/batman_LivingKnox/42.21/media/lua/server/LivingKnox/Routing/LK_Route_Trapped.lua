-- Living Knox : modèle d'itinéraire « trapped » (LK04-T20, inscrit en LK16-T11) : dernier recours d'un PNJ enfermé
-- (aucune porte utilisable pour sortir) : comme « npc », mais avec les décisions trapped de decide et decideWindow
-- (porte ou fenêtre du foyer d'un autre groupe abordée depuis ce foyer, fenêtre verrouillée abordée de l'intérieur) ;
-- barricade, chute, meuble à l'arrivée, fenêtre inamovible et alarme restent infranchissables. Chaque escalade coûte
-- ROUTE_PENALTY ; recherche bornée à ROUTE_EXIT_MAX_NODES cases. Moteur : LK_Routing.lua.
if isClient() then return end

require "LivingKnox/LK_Routing"

local Obstacles = LivingKnox.Obstacles
local Routing = Obstacles.Routing

Routing.registerModel("trapped", {
    maxNodes = function() return Obstacles.ROUTE_EXIT_MAX_NODES end,
    edgeCost = function(r, npcId, sqA, sqB, _, from)
        local P = Obstacles.ROUTE_PENALTY
        local k = r.kind
        if k == "door" then
            local d = r.obj
            if d:isBarricaded() then return nil end
            if Obstacles.isOpen(d) or Obstacles.decide(npcId, d, sqA, sqB, nil, from, true) == "open" then
                return 0, "door"
            end
            if Obstacles.isLowGate(d) then return P, "climb" end
            return nil
        elseif k == "window" then
            local w = r.obj
            if w:isBarricaded() then return nil end
            local far = from == sqA and sqB or sqA
            -- Fenêtre ouverte ou cassée : franchie par le moteur, mais jamais vers une chute ou un meuble bas.
            if not Obstacles.windowBlocks(w, r.wk) then
                if Obstacles.isDrop(far) or Obstacles.isFurnitureLanding(far) then return nil end
                return P, "climb"
            end
            if Obstacles.decideWindow(npcId, w, r.wk, sqA, sqB, far, true, from) == "open" then return P, "climb" end
            return nil
        end
        return P, "climb"   -- clôture basse
    end,
})
