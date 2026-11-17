-- Living Knox : règles des bords de cases (LK17-T03). ADR : docs/architecture/decisions/adr-bords-des-cases.md (D02).
--
-- Fonctions pures : aucune lecture du jeu. Elles reçoivent les faits d'un bord rendus par LivingKnox.Edges.read
-- (shared/LivingKnox/Edges/LK_Edges.lua, seul lecteur du jeu) :
--   edge = {
--     door     = absente (nil ou false) | { open, lowGate, obj }  porte du bord (lowGate : portail bas enjambé)
--     window   = absente | { kind, open, destroyed, glassRemoved, barricaded, obj } fenêtre ("window"), fenêtre
--                                                                construite ("built") ou cadre ("frame") ; open,
--                                                                destroyed et glassRemoved : "window" seule
--     fence    = booléen    clôture basse telle que le moteur la voit (drapeau Hoppable de la case)
--     hoppable = booléen    objet enjambable sur le bord (isHoppableTo), même sous un mur
--     wall     = booléen    mur (isWallTo)
--     blocked  = booléen    bord bloqué pour le moteur (isBlockedTo : mur, escalier, porte fermée...)
--   }
-- Un fait se lit par indexation seulement (la table peut être paresseuse : LK_Edges ne demande au jeu que les faits
-- lus). Kahlua : aucun next, aucun goto.
require "LivingKnox/LK_Core"

local Rules = LivingKnox.EdgeRules or {}
LivingKnox.EdgeRules = Rules

Rules.DOOR = "door edge"
Rules.NARROW = "one-square-wide passage"

-- Vrai si le bord porte quoi que ce soit qu'un corps ne traverse pas en ligne droite : mur, escalier, porte (même
-- ouverte), fenêtre de toute sorte, objet enjambable. Ligne dégagée du déblocage (LK04-T05), passage étroit.
function Rules.closed(edge)
    if edge.blocked == true then return true end
    if edge.door then return true end
    if edge.window then return true end
    return edge.hoppable == true
end

-- Vrai si la porte arrête le corps : fermée, et pas un portail bas (enjambé par le moteur,
-- J/characters/IsoZombie.java:1075, 3051-3058 ; LK04-T08).
function Rules.doorStops(door)
    return door.open ~= true and door.lowGate ~= true
end

-- Vrai si la fenêtre arrête le corps : barricadée, ou fenêtre fermée et intacte. Fenêtre ouverte, cassée, cadre vide
-- et fenêtre construite non barricadés : franchis par le moteur (IsoWindow.java:1220-1238, IsoWindowFrame.java:348-372,
-- IsoThumpable.java:2175-2186).
function Rules.windowStops(window)
    if window.barricaded == true then return true end
    return window.kind == "window" and window.open ~= true and window.destroyed ~= true
end

-- Vrai si enjamber la fenêtre expose au verre brisé (LK21-T12, ADR adr-blessures-soins.md D03, « Verre brisé ») :
-- fenêtre brisée dont le verre n'a pas été retiré, non barricadée (ClimbThroughWindowState.java:532 : isDestroyed et
-- pas isGlassRemoved). Fenêtre ouverte intacte, verre retiré, cadre vide, fenêtre construite : aucun verre.
function Rules.glassLeft(window)
    return window.kind == "window" and window.destroyed == true and window.glassRemoved ~= true
        and window.barricaded ~= true
end

-- Conduite devant la fenêtre (LK21-T12) : "remove" (retirer d'abord le verre, comme l'action vanilla, puis enjamber)
-- pour un PNJ qui n'est pas pressé, "risk" (enjamber aussitôt et courir le risque du vanilla) pour un PNJ pressé
-- (hurry : fuite, combat, urgence), nil sans verre à craindre.
function Rules.glassStep(window, hurry)
    if not Rules.glassLeft(window) then return nil end
    return hurry and "risk" or "remove"
end

-- Vrai si un corps sur une case ne peut pas se dire arrivé sur la case voisine (orthogonale) de l'autre côté du bord :
-- porte qui l'arrête (LK04-T17, lk.traversal du 2026-10-12), fenêtre même ouverte ou mur (lk.windowsally du
-- 2026-11-16 : corps resté dehors sous la fenêtre, « arrivé » dedans).
function Rules.stopsArrival(edge)
    if edge.door then return Rules.doorStops(edge.door) end
    if edge.window then return true end
    return edge.wall == true
end

-- Vrai si un corps ne peut pas se dire arrivé sur une case en diagonale : l'une dedans, l'autre dehors.
function Rules.stopsDiagonalArrival(insideA, insideB)
    return (insideA == true) ~= (insideB == true)
end

-- Raison pour laquelle une case gêne le passage et ne sert pas de place d'arrêt (LK18-T03, ADR adr-ceder-le-passage.md
-- D04, D05), ou nil. sides : voisines nord, est, sud, ouest ([1] à [4]), chacune nil (case absente) ou
-- { walkable, edge } (case praticable, faits du bord commun). Porte sur un bord, ouverte ou fermée : Rules.DOOR ; deux
-- côtés opposés fermés (absente, impraticable ou bord fermé) : Rules.NARROW.
function Rules.stopRefusal(sides)
    local closed = {}
    for i = 1, 4 do
        local s = sides[i]
        if s ~= nil and s.edge.door then return Rules.DOOR end
        closed[i] = s == nil or s.walkable ~= true or Rules.closed(s.edge)
    end
    if (closed[1] and closed[3]) or (closed[2] and closed[4]) then return Rules.NARROW end
    return nil
end

-- Vrai si le couloir d'un détour passe ce bord (LK17-T01, base pz-knowledge pathfinding-and-obstacles.md, « Classer
-- le bord commun de deux cases ») : porte jugée par doorPasses() (règle de contact de l'appelant) ; fenêtre de toute
-- sorte et clôture basse refusées ; sinon libre si le moteur ne le bloque pas (mur, escalier).
function Rules.corridorStep(edge, doorPasses)
    if edge.door then return doorPasses() == true end
    if edge.window or edge.fence == true then return false end
    return edge.blocked ~= true
end

return Rules
