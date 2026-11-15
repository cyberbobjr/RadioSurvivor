-- Living Knox : arbitrage du passage entre deux PNJ (LK18-T01). ADR : docs/architecture/decisions/
-- adr-ceder-le-passage.md (D01 à D03, D05). Fiche : docs/annexes/conception/passage.md.
--
-- Fonction pure : aucune lecture du monde, aucun registre global. Tout arrive en données simples ou en requête injectée,
-- testable hors jeu :
--   mover   = { id, kind, x, y, z }            PNJ qui avance sans progresser (le demandeur)
--   blocker = { id, kind, x, y, z, canMove }   PNJ sur son trajet ; canMove faux : blessé, en combat, mort...
--   free    = { { x, y, z }, ... }             cases libres autour du bloqueur, où il peut se tenir et qu'il peut
--                                              joindre (relevé de l'appelant, l'autorité)
--   path    = { { x, y }, ... }                prochaines cases du trajet du demandeur
--   priorityOf(kind) -> nombre                 priorité de passage d'un comportement (LivingKnox.Passage.priorityOf)
-- Rend { action = "stepAside", to = { x, y, z } }, { action = "backOff", to = { x, y, z } } ou nil (le demandeur
-- garde le traitement actuel du blocage : « stuck »). Kahlua : aucun next, aucun goto.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Identity"

local Arbiter = LivingKnox.PassageArbiter or {}
LivingKnox.PassageArbiter = Arbiter

Arbiter.STEP_ASIDE = "stepAside"
Arbiter.BACK_OFF = "backOff"

-- Vrai si l'identifiant a passe avant b à priorité égale : le plus petit numéro de PNJ (« lk-<n> »), sinon l'ordre du
-- texte (identifiant hors format : départage stable quand même).
local function idBefore(a, b)
    local Identity = LivingKnox.Identity
    local na, nb = Identity.idNumber(a), Identity.idNumber(b)
    if na ~= nil and nb ~= nil then return na < nb end
    return tostring(a) < tostring(b)
end

-- Vrai si le demandeur passe : priorité plus haute, ou égale et plus petit identifiant.
function Arbiter.moverPasses(mover, blocker, priorityOf)
    local pm, pb = priorityOf(mover.kind), priorityOf(blocker.kind)
    if pm ~= pb then return pm > pb end
    return idBefore(mover.id, blocker.id)
end

local function onPath(sq, path)
    for _, p in ipairs(path or {}) do
        if p.x == sq.x and p.y == sq.y then return true end
    end
    return false
end

local function cheb(ax, ay, bx, by)
    return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function d2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

-- Case retenue parmi free selon keep(sq), la plus proche du bloqueur, puis la plus loin du demandeur, puis y et x
-- (ordre stable). Rend la case ou nil.
local function best(free, blocker, mover, keep)
    local pick, pd, pm
    for _, sq in ipairs(free) do
        if (sq.z == nil or sq.z == blocker.z) and keep(sq) then
            local d, m = d2(sq.x, sq.y, blocker.x, blocker.y), d2(sq.x, sq.y, mover.x, mover.y)
            local better = pick == nil or d < pd or (d == pd and (m > pm or (m == pm
                and (sq.y < pick.y or (sq.y == pick.y and sq.x < pick.x)))))
            if better then pick, pd, pm = sq, d, m end
        end
    end
    return pick
end

-- Case utilisable par le bloqueur : ni la sienne, ni celle du demandeur, ni sur le trajet du demandeur.
local function usable(sq, mover, blocker, path)
    if sq.x == blocker.x and sq.y == blocker.y then return false end
    if sq.x == mover.x and sq.y == mover.y then return false end
    return not onPath(sq, path)
end

-- Décision de passage (voir l'en-tête). D03 : le bloqueur qui ne peut pas bouger, ou qui a la priorité, ne cède rien.
function Arbiter.decide(mover, blocker, free, path, priorityOf)
    if blocker.canMove == false then return nil end
    if not Arbiter.moverPasses(mover, blocker, priorityOf) then return nil end
    free = free or {}
    local aside = best(free, blocker, mover, function(sq)
        return cheb(sq.x, sq.y, blocker.x, blocker.y) == 1 and usable(sq, mover, blocker, path)
    end)
    if aside ~= nil then return { action = Arbiter.STEP_ASIDE, to = { x = aside.x, y = aside.y, z = blocker.z } } end
    -- Face à face sans case de côté : recul vers la case libre la plus proche derrière le bloqueur (côté opposé au
    -- demandeur), hors du trajet.
    local bx, by = blocker.x - mover.x, blocker.y - mover.y
    local back = best(free, blocker, mover, function(sq)
        return (sq.x - blocker.x) * bx + (sq.y - blocker.y) * by > 0 and usable(sq, mover, blocker, path)
    end)
    if back ~= nil then return { action = Arbiter.BACK_OFF, to = { x = back.x, y = back.y, z = blocker.z } } end
    return nil
end

return Arbiter
