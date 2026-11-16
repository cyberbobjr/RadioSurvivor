-- Living Knox : règle des places d'arrêt (LK18-T03). ADR : docs/architecture/decisions/adr-ceder-le-passage.md (D04,
-- D05). Fiche : docs/annexes/conception/passage.md, section « Places d'arrêt ».
--
-- Une place où un PNJ s'arrête (garde, attente au foyer, repas, corvée, soin...) ne gêne jamais le passage :
--   - ni une case de porte ou de portail, ni un seuil : case dont un bord porte une porte, ouverte ou fermée
--     (IsoGridSquare.getDoorTo : IsoDoor ou IsoThumpable porte, vue des deux cases du bord,
--     J/iso/IsoGridSquare.java:3077-3112, 42.22) ;
--   - ni un passage d'une seule case de large : deux côtés opposés fermés (case absente ou impraticable, ou bord
--     fermé au sens de LivingKnox.EdgeRules.closed : mur, porte, fenêtre, cadre, clôture).
-- La règle elle-même est pure (LivingKnox.EdgeRules.stopRefusal, ADR adr-bords-des-cases.md) ; les faits des
-- bords viennent de LivingKnox.Edges. Ce module ne connaît que la règle ; chaque appelant garde ses propres critères
-- (bâtiment, case libre, escalier, foyer...) dans la fonction accept qu'il passe. Sans place qui respecte la règle,
-- la case de l'appelant reste (repli : un PNJ doit pouvoir s'arrêter quelque part). Autorité seulement : un client MP
-- charge aussi media/lua/server, il s'arrête ici.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/Edges/LK_Edges"

local StopPlace = LivingKnox.StopPlace or {}
LivingKnox.StopPlace = StopPlace

StopPlace.DOOR = LivingKnox.EdgeRules.DOOR
StopPlace.NARROW = LivingKnox.EdgeRules.NARROW
StopPlace.SHIFT_RADIUS = 2   -- décalage au plus d'une place relevée ailleurs (poste de guet)

-- Voisines nord, est, sud, ouest (ordre de LivingKnox.EdgeRules.stopRefusal).
local SIDES = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

-- Raison pour laquelle la case sq (chargée) gêne le passage (StopPlace.DOOR, StopPlace.NARROW), ou nil.
function StopPlace.blocksPassage(sq)
    local cell, Edges = getCell(), LivingKnox.Edges
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local sides = {}
    for i, d in ipairs(SIDES) do
        sides[i] = Edges.side(sq, cell:getGridSquare(x + d[1], y + d[2], z))
    end
    return LivingKnox.EdgeRules.stopRefusal(sides)
end

-- Vrai si la case sq peut servir de place d'arrêt selon la règle.
function StopPlace.allows(sq)
    return StopPlace.blocksPassage(sq) == nil
end

-- Place d'arrêt la plus proche de (x, y, z), à radius cases au plus (anneaux de LivingKnox.Bodies.ring : distance,
-- puis y, puis x), la rank-ième (1 par défaut) parmi les cases chargées qui satisfont accept(sq) et la règle ; sans
-- elle, la rank-ième qui satisfait accept seul (repli). Rend la case, ou nil.
function StopPlace.nearest(x, y, z, radius, accept, rank)
    rank = rank or 1
    local cell = getCell()
    local ring = LivingKnox.Bodies.ring
    local good, any, fallback = 0, 0, nil
    for r = 0, radius do
        for _, d in ipairs(ring(r)) do
            local sq = cell:getGridSquare(x + d[1], y + d[2], z)
            if sq ~= nil and accept(sq) then
                any = any + 1
                if fallback == nil and any >= rank then fallback = sq end
                if StopPlace.allows(sq) then
                    good = good + 1
                    if good >= rank then return sq end
                end
            end
        end
    end
    return fallback
end

-- Première des candidates (liste ordonnée par l'appelant) qui respecte la règle, sinon la première (repli). Rend
-- l'index retenu, ou nil si la liste est vide.
function StopPlace.firstAllowed(squares)
    if #squares == 0 then return nil end
    for i, sq in ipairs(squares) do
        if StopPlace.allows(sq) then return i end
    end
    return 1
end

return StopPlace
