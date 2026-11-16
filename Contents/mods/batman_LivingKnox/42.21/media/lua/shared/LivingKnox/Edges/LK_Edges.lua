-- Living Knox : lecture des bords de cases dans le jeu (LK17-T03). ADR : docs/architecture/decisions/
-- adr-bords-des-cases.md (D01).
--
-- Seul module du déplacement qui demande au jeu ce qui sépare deux cases voisines (orthogonales). Il rend des faits en
-- valeurs simples (forme décrite en tête de LK_EdgeRules.lua) ; les règles de LivingKnox.EdgeRules décident.
-- Chargé partout (media/lua/shared) : l'exécutant (client MP, solo) et l'autorité (serveur, solo) le lisent.
-- Java 42.22 (J = zombie/iso/IsoGridSquare.java) : isWallTo 718, isBlockedTo 935-941, isHoppableTo 1043-1049,
-- getDoorTo 3077-3112, getWindowTo / getWindowThumpableTo / getWindowFrameTo 3131-3172, 3228-3236, getBuildingDef 7813.
require "LivingKnox/LK_Core"
require "LivingKnox/Edges/LK_EdgeRules"

local Edges = LivingKnox.Edges or {}
LivingKnox.Edges = Edges

-- Vrai si la porte est un portail bas (enjambé par le moteur, jamais ouvert : LK04-T08).
function Edges.isLowGate(door)
    return door:isHoppable() == true and door:isTallHoppable() ~= true
end

-- Fenêtre du bord commun des cases voisines sq et nb, et sa sorte : "window" (IsoWindow), "built" (fenêtre construite,
-- IsoThumpable) ou "frame" (cadre vide, IsoWindowFrame) ; nil s'il n'y en a pas.
function Edges.windowOf(sq, nb)
    local w = sq:getWindowTo(nb)
    if w ~= nil then return w, "window" end
    w = sq:getWindowThumpableTo(nb)
    if w ~= nil then return w, "built" end
    w = sq:getWindowFrameTo(nb)
    if w ~= nil then return w, "frame" end
    return nil
end

-- Table paresseuse : chaque fait est demandé au jeu à sa première lecture par reader[nom](), puis gardé (false pour
-- un fait absent : une règle ne lit que ce qu'il lui faut, le jeu n'est interrogé que pour cela).
local function lazy(fields, reader)
    return setmetatable(fields, { __index = function(t, k)
        local f = reader[k]
        if f == nil then return nil end
        local v = f()
        if v == nil then v = false end
        rawset(t, k, v)
        return v
    end })
end

-- Faits d'une fenêtre w de sorte kind (voir LK_EdgeRules.lua) ; IsOpen et isDestroyed seulement sur une IsoWindow.
function Edges.windowFacts(w, kind)
    local isWindow = kind == "window"
    return lazy({ obj = w, kind = kind }, {
        barricaded = function() return w:isBarricaded() == true end,
        open = function() return isWindow and w:IsOpen() == true end,
        destroyed = function() return isWindow and w:isDestroyed() == true end,
    })
end

-- Faits d'une porte d (voir LK_EdgeRules.lua).
function Edges.doorFacts(d)
    return lazy({ obj = d }, {
        open = function() return d:IsOpen() == true end,
        lowGate = function() return Edges.isLowGate(d) end,
    })
end

-- Clôture basse du bord commun des cases voisines sq et nb TELLE QUE LE MOTEUR LA VOIT : objet enjambable
-- (isHoppableTo) ET drapeau HoppableW/N de la case est (bord W) ou sud (N), que RecalcProperties retire quand un autre
-- objet du bord pose collideW/N sans Hoppable (mur ; IsoGridSquare.java:6144-6179, 6233-6236) ; le chemin natif et
-- l'enjambée à la collision ne lisent que ce drapeau (base pz-knowledge pathfinding-and-obstacles.md, « Classer le
-- bord commun de deux cases »).
function Edges.fenceTo(sq, nb)
    if not sq:isHoppableTo(nb) then return false end
    if nb:getX() ~= sq:getX() then
        local east = nb:getX() > sq:getX() and nb or sq
        return east:has(IsoFlagType.HoppableW) == true
    end
    local south = nb:getY() > sq:getY() and nb or sq
    return south:has(IsoFlagType.HoppableN) == true
end

-- Faits du bord commun des cases voisines orthogonales a et b (voir LK_EdgeRules.lua), lus à la demande.
function Edges.read(a, b)
    local f
    f = lazy({}, {
        blocked = function() return a:isBlockedTo(b) == true end,
        wall = function() return a:isWallTo(b) == true end,
        door = function()
            local d = a:getDoorTo(b)
            return d ~= nil and Edges.doorFacts(d) or false
        end,
        window = function()
            local w, kind = Edges.windowOf(a, b)
            return w ~= nil and Edges.windowFacts(w, kind) or false
        end,
        hoppable = function() return a:isHoppableTo(b) == true end,
        fence = function() return f.hoppable and Edges.fenceTo(a, b) end,
    })
    return f
end

-- Vrai si le corps ne traverse pas en ligne droite le bord commun des cases voisines a et b (EdgeRules.closed).
function Edges.closed(a, b)
    return LivingKnox.EdgeRules.closed(Edges.read(a, b))
end

-- Vrai si la case est dans un bâtiment.
function Edges.inside(sq)
    return sq:getBuildingDef() ~= nil
end

-- Vrai si un corps sur la case (x, y, z) ne peut pas se dire arrivé sur la case voisine (tx, ty, tz) : bord qui l'arrête
-- entre voisines orthogonales (EdgeRules.stopsArrival), l'une dedans et l'autre dehors en diagonale
-- (EdgeRules.stopsDiagonalArrival). Faux pour la même case, une case non voisine, un autre niveau ou une case non
-- chargée. Lu par l'exécutant (LK_Executor) et par l'autorité (Directives.arrivedAt).
function Edges.separates(x, y, z, tx, ty, tz)
    if z ~= tz then return false end
    local dx, dy = tx - x, ty - y
    if (dx == 0 and dy == 0) or math.abs(dx) > 1 or math.abs(dy) > 1 then return false end
    local cell = getCell()
    local sq, ts = cell:getGridSquare(x, y, z), cell:getGridSquare(tx, ty, tz)
    if sq == nil or ts == nil then return false end
    local Rules = LivingKnox.EdgeRules
    if dx ~= 0 and dy ~= 0 then return Rules.stopsDiagonalArrival(Edges.inside(sq), Edges.inside(ts)) end
    return Rules.stopsArrival(Edges.read(sq, ts))
end

-- Voisine nb de la case sq vue pour une place d'arrêt (EdgeRules.stopRefusal) : nil si absente, sinon praticable et
-- faits du bord commun.
function Edges.side(sq, nb)
    if nb == nil then return nil end
    return { walkable = nb:isFree(false) == true, edge = Edges.read(sq, nb) }
end

return Edges
