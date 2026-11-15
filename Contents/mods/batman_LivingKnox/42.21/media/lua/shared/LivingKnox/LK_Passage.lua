-- Living Knox : priorités de passage des comportements (LK18-T01). ADR : docs/architecture/decisions/
-- adr-ceder-le-passage.md (D02, D05). Fiche : docs/annexes/conception/passage.md.
--
-- Registre seulement : chaque comportement ou directive déclare sa priorité dans son propre fichier,
--   require "LivingKnox/LK_Passage"
--   LivingKnox.Passage.priority("fight", 100)
-- Ce module ne nomme aucun comportement (ouvert/fermé). Un comportement non déclaré a la priorité DEFAULT, la plus
-- basse (une déclaration est refusée en dessous). Passage.arbitrate assemble le registre et l'arbitrage pur
-- (LK_PassageArbiter) pour l'autorité. Partagé : aucun appel au moteur du jeu.
-- LK18-T02 : nom de la commande « bloqué par un PNJ » (client propriétaire -> serveur), lu par l'exécutant
-- (LK_PassageSignal) et par l'autorité (LK_PassageAuthority).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_PassageArbiter"

local Passage = LivingKnox.Passage or {}
LivingKnox.Passage = Passage

Passage.DEFAULT = 0   -- comportement sans déclaration (repos, attente...) : le plus bas
Passage.MODULE = "LivingKnox"
Passage.CMD_BLOCKED = "passageBlocked"   -- client propriétaire -> serveur : { id, v, l, b, x, y, z, bx, by, bz, tx, ty }

local function validate(spec)
    if type(spec.kind) ~= "string" or spec.kind == "" then return false, "kind must be a non-empty string" end
    local n = spec.priority
    if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
        return false, "priority of " .. spec.kind .. " must be a finite number"
    end
    if n < Passage.DEFAULT then
        return false, "priority of " .. spec.kind .. " is below the default " .. Passage.DEFAULT
    end
    return true
end

-- Registre gardé au rechargement du module (déclarations des autres fichiers conservées).
Passage.registry = Passage.registry or LivingKnox.Registry.new("LivingKnox.Passage.priority",
    { key = "kind", sort = false, validate = validate })

-- Déclare la priorité n du comportement kind (une nouvelle déclaration remplace l'ancienne). Rend n ; erreur si la
-- déclaration est refusée.
function Passage.priority(kind, n)
    Passage.registry:register({ kind = kind, priority = n }, 2)
    return n
end

-- Priorité de passage du comportement kind ; DEFAULT s'il n'est pas déclaré.
function Passage.priorityOf(kind)
    local spec = kind ~= nil and Passage.registry:get(kind) or nil
    if spec == nil then return Passage.DEFAULT end
    return spec.priority
end

-- Arbitrage avec les priorités déclarées (LivingKnox.PassageArbiter.decide, mêmes arguments et même retour).
function Passage.arbitrate(mover, blocker, free, path)
    return LivingKnox.PassageArbiter.decide(mover, blocker, free, path, Passage.priorityOf)
end

return Passage
