-- Living Knox : socle commun des registres du moteur (LK16-T01). ADR : docs/architecture/decisions/
-- adr-remise-en-ordre-solid.md (D02). Partagé : les types de groupes (shared) s'en servent comme les registres du serveur.
--
-- LivingKnox.Registry.new(name, opts) rend un registre :
--   name : nom public de la fonction d'inscription (« LivingKnox.Upkeep.registerJob ») ; préfixe des erreurs
--   opts.key      : champ identifiant d'une inscription (« id » par défaut, « kind » pour les tâches d'entretien)
--   opts.validate : facultatif, fn(spec) -> vrai, ou faux et une raison ; règles propres au registre (champs requis,
--                   code déjà pris, identifiant déjà enregistré...) ; appelée AVANT tout contrôle du socle
--   opts.sort     : vrai par défaut : liste triée par order (nombre requis) puis clé ; faux : ordre d'inscription
--   opts.items, opts.byKey : facultatifs, tables publiques existantes reprises telles quelles (même identité : un
--                   module rechargé garde les tables lues ailleurs)
-- Une seule politique de doublon : une inscription de même clé remplace l'ancienne (rechargement). Un registre qui
-- refuse un doublon le dit dans son validate. Liste tenue à l'inscription, sans next (absent de Kahlua).
require "LivingKnox/LK_Core"

local Registry = LivingKnox.Registry or {}
LivingKnox.Registry = Registry

local Methods = {}
Methods.__index = Methods

-- Raison du refus de spec, ou nil : règles du registre d'abord, puis clé et ordre exigés par le socle.
function Methods:check(spec)
    if self.validate ~= nil then
        local ok, why = self.validate(spec)
        if not ok then return why or "invalid spec" end
    end
    if type(spec) ~= "table" or spec[self.key] == nil then return "spec needs " .. self.key end
    if self.sorted and type(spec.order) ~= "number" then return "spec needs order" end
    return nil
end

local function sortList(list, key)
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a[key] < b[key]
    end)
end

-- Inscrit spec déjà contrôlée ; remplace l'inscription de même clé.
function Methods:put(spec)
    local key, items = self.key, self.items
    local k = spec[key]
    for i = #items, 1, -1 do
        if items[i][key] == k then table.remove(items, i) end
    end
    items[#items + 1] = spec
    self.byKey[k] = spec
    if self.sorted then sortList(items, key) end
    return spec
end

-- Inscrit spec et la rend ; spec refusée : erreur « <name>: <raison> », rien n'est inscrit. level : niveau de l'erreur
-- vu de l'appelant de register (1 par défaut : cet appelant ; 2 : l'appelant de la fonction publique qui l'enveloppe).
function Methods:register(spec, level)
    local why = self:check(spec)
    if why ~= nil then error(self.name .. ": " .. tostring(why), (level or 1) + 1) end
    return self:put(spec)
end

-- Comme register, sans erreur : rend spec, ou nil et la raison du refus.
function Methods:try(spec)
    local why = self:check(spec)
    if why ~= nil then return nil, why end
    return self:put(spec)
end

-- Inscriptions, dans l'ordre du registre (table vivante, à ne pas modifier).
function Methods:list()
    return self.items
end

-- Inscription de clé k, ou nil.
function Methods:get(k)
    return self.byKey[k]
end

function Registry.new(name, opts)
    opts = opts or {}
    local self = setmetatable({ name = name, key = opts.key or "id", validate = opts.validate,
        sorted = opts.sort ~= false, items = opts.items or {}, byKey = opts.byKey or {} }, Methods)
    for _, s in ipairs(self.items) do self.byKey[s[self.key]] = s end
    return self
end

return Registry
