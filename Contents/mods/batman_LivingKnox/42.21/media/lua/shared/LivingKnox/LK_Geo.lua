-- Living Knox : petites fonctions géométriques pures, une seule copie pour tout le moteur (LK20-T01, ADR
-- docs/architecture/decisions/adr-simplification-livingknox.md, D01). Chargé par LK_Core ; les modules l'appellent
-- au moment de l'exécution (LivingKnox.Geo.cheb(...)), jamais par une capture au chargement.
-- Ne requiert pas LK_Core (LK_Core le requiert) : l'espace de noms est créé ici s'il manque.
LivingKnox = LivingKnox or {}

local Geo = LivingKnox.Geo or {}
LivingKnox.Geo = Geo

-- Distance de Chebyshev (en cases) entre (ax, ay) et (bx, by).
function Geo.cheb(ax, ay, bx, by)
    return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- Écart entre deux angles en degrés, de 0 à 180.
function Geo.angleGap(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then d = 360 - d end
    return d
end

-- Itérateur sur les cases (x, y) du carré plein de rayon r centré sur (cx, cy), dans l'ordre de
-- « for dy = -r, r do for dx = -r, r do » : par ligne de y, puis x. Rayon négatif : aucune case.
function Geo.squaresAround(cx, cy, r)
    local dx, dy = -r - 1, -r
    return function()
        dx = dx + 1
        if dx > r then
            dx = -r
            dy = dy + 1
        end
        if dy > r then return nil end
        return cx + dx, cy + dy
    end
end

return Geo
