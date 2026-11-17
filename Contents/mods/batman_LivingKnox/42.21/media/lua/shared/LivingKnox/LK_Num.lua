-- Living Knox : petites fonctions numériques pures, une seule copie pour tout le moteur (LK20-T01, ADR
-- docs/architecture/decisions/adr-simplification-livingknox.md, D01). Chargé par LK_Core ; les modules l'appellent
-- au moment de l'exécution (LivingKnox.Num.finite(v)), jamais par une capture au chargement.
-- Ne requiert pas LK_Core (LK_Core le requiert) : l'espace de noms est créé ici s'il manque.
LivingKnox = LivingKnox or {}

local Num = LivingKnox.Num or {}
LivingKnox.Num = Num

-- Nombre fini et raisonnable : ni NaN, ni infini, strictement entre -1e9 et 1e9.
function Num.finite(v)
    return type(v) == "number" and v == v and v > -1e9 and v < 1e9
end

-- Entier de lo à hi inclus (ni NaN, ni chaîne).
function Num.isInt(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

-- v ramené dans [lo, hi].
function Num.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

return Num
