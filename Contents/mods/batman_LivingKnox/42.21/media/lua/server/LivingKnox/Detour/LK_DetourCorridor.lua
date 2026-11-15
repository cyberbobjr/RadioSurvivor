-- Living Knox : couloir d'approche d'un detour (LK17-T01, correctif du 2026-11-15 : campagne
-- tools/autoclient/runs/20261115-193703-95dea46b0c64, corps repasse par la fenetre refusee pour gagner la porte).
-- Pour un zombie en marche, une fenetre fermee, verrouillee ou barricadee ne coute rien au chemin natif, et rien en Lua
-- ne lui fait eviter un bord (base pz-knowledge pathfinding-and-obstacles.md, « Ce que traverse le chemin d'un
-- zombie ») : le trajet du corps vers la case avant de la porte choisie par LK_Detour reprenait la fenetre refusee.
-- Ce module donne les points de passage du corps (px, py) a la case cible (tx, ty) tels que chaque segment droit entre
-- deux points consecutifs ne franchit aucun bord que grid.open refuse (mur, fenetre, cloture basse, porte refusee) :
-- le chemin le plus court entre eux n'a alors aucune raison de passer par une fenetre. Sert aux deux troncons d'un
-- detour (corps -> case avant de l'ouverture : plan ; case apres -> destination : toward, campagne
-- tools/autoclient/runs/20261115-202338-44940358ac9a, dernier troncon natif repasse par la fenetre refusee).
--   - recherche en largeur (4 voisins, ordre fixe N, E, S, W : deterministe) dans une boite bornee (margin cases) ;
--   - tirage du fil : depuis le corps, on garde la case la plus lointaine du chemin trouve encore visible en ligne
--     droite (segmentClear), puis on repart d'elle, jusqu'a la cible.
-- Algorithme seul, aucun appel au jeu : l'acces aux cases est injecte (grid), ce qui permet au banc de le conduire.
--   grid.square(x, y) : case chargee (x, y) du niveau etudie, ou nil ;
--   grid.open(a, b)   : vrai si le corps passe de la case a a sa voisine orthogonale b (bord franchissable, b
--                       praticable).
-- Autorite seulement, comme LK_Detour (un client MP charge aussi media/lua/server : il s'arrete ici).
if isClient() then return end

require "LivingKnox/LK_Core"

local Corridor = LivingKnox.DetourCorridor or {}
LivingKnox.DetourCorridor = Corridor

Corridor.STEP = 0.25   -- cases : pas d'echantillonnage d'un segment (comme Directives.hazardsOnLine)
-- Voisins de la recherche, ordre fixe : N, E, S, W.
Corridor.NEIGHBOURS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

-- Vrai si le corps passe de la case a (ax, ay) a la case (bx, by), voisine orthogonale ou diagonale. Diagonale : le
-- chemin du jeu peut couper le coin par l'une ou l'autre case laterale, les deux chemins en L doivent etre libres.
local function crossClear(grid, a, ax, ay, bx, by)
    local b = grid.square(bx, by)
    if b == nil then return false end
    if ax == bx or ay == by then return grid.open(a, b) end
    local m1, m2 = grid.square(bx, ay), grid.square(ax, by)
    return m1 ~= nil and m2 ~= nil and grid.open(a, m1) and grid.open(m1, b) and grid.open(a, m2)
        and grid.open(m2, b)
end

-- Vrai si le segment (x0, y0) -> (x1, y1) (coordonnees reelles) ne franchit aucun bord ferme entre deux cases
-- consecutives echantillonnees au pas STEP, toutes chargees.
function Corridor.segmentClear(grid, x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / Corridor.STEP))
    local cx, cy = math.floor(x0), math.floor(y0)
    local cur = grid.square(cx, cy)
    if cur == nil then return false end
    for i = 1, steps do
        local nx, ny = math.floor(x0 + dx * i / steps), math.floor(y0 + dy * i / steps)
        if nx ~= cx or ny ~= cy then
            if not crossClear(grid, cur, cx, cy, nx, ny) then return false end
            cx, cy = nx, ny
            cur = grid.square(cx, cy)
        end
    end
    return true
end

-- Parcours en largeur depuis la case (sx, sy) dans la boite box = { x1, y1, x2, y2 } ; visit(n) est appele pour
-- chaque noeud { x, y, sq, up } dans l'ordre de decouverte et arrete le parcours en rendant vrai. Rend le noeud
-- d'arret, ou nil.
local function explore(grid, sx, sy, box, visit)
    local start = grid.square(sx, sy)
    if start == nil then return nil end
    local seen = { [sx .. "," .. sy] = true }
    local queue, head = { { x = sx, y = sy, sq = start } }, 1
    while head <= #queue do
        local n = queue[head]
        head = head + 1
        if visit(n) then return n end
        for _, d in ipairs(Corridor.NEIGHBOURS) do
            local x, y = n.x + d[1], n.y + d[2]
            local k = x .. "," .. y
            if not seen[k] and x >= box[1] and x <= box[3] and y >= box[2] and y <= box[4] then
                local b = grid.square(x, y)
                if b ~= nil and grid.open(n.sq, b) then
                    seen[k] = true
                    queue[#queue + 1] = { x = x, y = y, sq = b, up = n }
                end
            end
        end
    end
    return nil
end

-- Chemin { { x, y }, ... } du depart au noeud n inclus (remonte les up).
local function pathTo(n)
    local rev = {}
    while n ~= nil do
        rev[#rev + 1] = { x = n.x, y = n.y }
        n = n.up
    end
    local path = {}
    for i = #rev, 1, -1 do path[#path + 1] = rev[i] end
    return path
end

-- Chemin de cases { { x, y }, ... } de (sx, sy) a (tx, ty) inclus, recherche en largeur dans la boite des deux cases
-- elargie de margin cases ; nil si la cible n'y est pas accessible.
function Corridor.search(grid, sx, sy, tx, ty, margin)
    local box = { math.min(sx, tx) - margin, math.min(sy, ty) - margin, math.max(sx, tx) + margin,
        math.max(sy, ty) + margin }
    local hit = explore(grid, sx, sy, box, function(n) return n.x == tx and n.y == ty end)
    if hit == nil then return nil end
    return pathTo(hit)
end

-- Case accessible depuis (sx, sy) dans la boite de cote 2 * margin + 1 centree sur elle, la plus proche du centre de
-- la case (tx, ty) (la premiere decouverte a egalite : deterministe). Rend x, y.
function Corridor.closest(grid, sx, sy, tx, ty, margin)
    local bx, by, bd = nil, nil, nil
    explore(grid, sx, sy, { sx - margin, sy - margin, sx + margin, sy + margin }, function(n)
        local dx, dy = n.x - tx, n.y - ty
        local d = dx * dx + dy * dy
        if bd == nil or d < bd then bx, by, bd = n.x, n.y, d end
        return false
    end)
    return bx, by
end

-- Coins du chemin de cases path (path[1] : case du corps au point (px, py), path[#path] : cible) : depuis le point de
-- depart, la case la plus lointaine encore visible en ligne droite, et ainsi de suite ; la cible n'est pas rendue.
-- nil si une case voisine du chemin n'est pas visible (ne devrait pas arriver : deux cases voisines forment un
-- rectangle convexe).
function Corridor.pull(grid, path, px, py)
    local corners = {}
    local ax, ay, i = px, py, 1
    while i < #path do
        local j = i
        while j < #path and Corridor.segmentClear(grid, ax, ay, path[j + 1].x + 0.5, path[j + 1].y + 0.5) do
            j = j + 1
        end
        if j == i then return nil end
        if j == #path then return corners end
        corners[#corners + 1] = path[j]
        ax, ay, i = path[j].x + 0.5, path[j].y + 0.5, j
    end
    return corners
end

-- Points de passage du corps (px, py) a la case (tx, ty) : liste de coins { { x, y }, ... } (vide : ligne droite
-- libre), ou nil si la cible n'est pas accessible dans la boite elargie de margin cases.
function Corridor.plan(grid, px, py, tx, ty, margin)
    if Corridor.segmentClear(grid, px, py, tx + 0.5, ty + 0.5) then return {} end
    local path = Corridor.search(grid, math.floor(px), math.floor(py), tx, ty, margin)
    if path == nil then return nil end
    return Corridor.pull(grid, path, px, py)
end

-- Points de passage du point (px, py) vers la case (tx, ty), boite bornee : cible a margin cases au plus (Tchebychev)
-- de la case de depart : Corridor.plan ; plus loin : coins jusqu'a la case accessible de la boite centree sur le
-- depart la plus proche de la cible (Corridor.closest), suivis de cette case (le chemin du jeu reprend de la) ; rien
-- si aucune case accessible n'est plus proche que le depart. nil : cible accessible attendue mais introuvable.
function Corridor.toward(grid, px, py, tx, ty, margin)
    local sx, sy = math.floor(px), math.floor(py)
    if math.abs(tx - sx) <= margin and math.abs(ty - sy) <= margin then
        return Corridor.plan(grid, px, py, tx, ty, margin)
    end
    local ex, ey = Corridor.closest(grid, sx, sy, tx, ty, margin)
    if ex == nil then return nil end
    if ex == sx and ey == sy then return {} end
    local way = Corridor.plan(grid, px, py, ex, ey, margin)
    if way == nil then return nil end
    way[#way + 1] = { x = ex, y = ey }
    return way
end
