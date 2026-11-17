-- Living Knox : sources de blessure, ouvertes à l'extension (LK21-T02, ADR docs/architecture/decisions/
-- adr-blessures-soins.md, D03). Une source traduit un coup en plaies : partie du corps et type (Wounds.registerKind).
-- Modèle des plaies : shared/LivingKnox/LK_Wounds.lua ; recherche docs/annexes/conception/blessures-moteur.md.
--
-- Un fichier par source (server/LivingKnox/Wounds/LK_WoundSource_<Id>.lua, chargé par le jeu, qui requiert ce module)
-- appelle Wounds.registerSource(id, spec). Ce module ne nomme aucune source ; LK_Health n'en nomme aucune non plus.
-- spec :
--   order  : rang dans le registre (nombre) ; le classement essaie les sources dans cet ordre
--   match  : facultatif, fn(hit) -> vrai si la source prend ce coup ; sans match, la source n'est appelée que par son
--            nom (hit.source : verre brisé, feu)
--   wounds : fn(hit, ctx) -> { { part = <Wounds.PARTS>, kind = <type inscrit>, opts = <opts de Wounds.add> }, ... }
--   after  : facultatif, fn(list, added, hit, ctx) appelée après l'ajout des plaies du coup (LK21-T04 : virus de Knox
--            transmis par la source « zombie », LivingKnox.Virus.fromWounds)
-- hit : { attacker, weapon, damage (santé retirée), part (partie indiquée par le moteur, OnHitZombie, ou nil),
--         source (nom imposé, ou nil), issue (issue déjà décidée, ex. attaque de zombie de LK_Zombies) }.
-- ctx : celui de Wounds.add (ctx.rnd exigé ; LK_WoundContext.lua pour le jeu).
--
-- Classement (Wounds.classify) : hit.source s'il est donné ; sinon la première source, dans l'ordre du registre, dont
-- match prend le coup ; aucune : le coup ne fait que des dégâts (aucune plaie). Les sources d'armes testent les
-- catégories vanilla de l'arme (WeaponCategory, HandWeapon.isOfWeaponCategory : J/inventory/types/HandWeapon.java:1158),
-- dans l'ordre de BodyDamage.DamageFromWeapon (contondant, puis arme à feu visée, sinon tranchant :
-- J/characters/BodyDamage/BodyDamage.java:1022-1028).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Registry"
require "LivingKnox/LK_Wounds"

local Wounds = LivingKnox.Wounds

Wounds.sourceList = Wounds.sourceList or {}
Wounds.sourceById = Wounds.sourceById or {}

local sourceRegistry = LivingKnox.Registry.new("LivingKnox.Wounds.registerSource", {
    validate = function(spec)
        if type(spec) ~= "table" or type(spec.id) ~= "string" then return false, "source needs an id" end
        if type(spec.wounds) ~= "function" then return false, spec.id .. " needs wounds" end
        if spec.match ~= nil and type(spec.match) ~= "function" then return false, spec.id .. ".match must be a function" end
        if spec.after ~= nil and type(spec.after) ~= "function" then return false, spec.id .. ".after must be a function" end
        return true
    end,
    items = Wounds.sourceList, byKey = Wounds.sourceById })

-- Inscrit la source id (même id : remplacée, rechargement).
function Wounds.registerSource(id, spec)
    if type(spec) == "table" then spec.id = id end
    return sourceRegistry:register(spec, 2)
end

function Wounds.source(id)
    return Wounds.sourceById[id]
end

-- Source qui prend le coup hit, ou nil (voir l'en-tête).
function Wounds.classify(hit)
    if hit == nil then return nil end
    if hit.source ~= nil then return Wounds.sourceById[hit.source] end
    for _, spec in ipairs(Wounds.sourceList) do
        if spec.match ~= nil and spec.match(hit) then return spec end
    end
    return nil
end

-- Plaies faites par le coup hit, ajoutées à list, puis suite propre à la source (spec.after). Rend les plaies ajoutées
-- (liste vide : aucune source, ou source sans plaie pour ce coup) et l'id de la source.
function Wounds.fromHit(list, hit, ctx)
    local added = {}
    local spec = Wounds.classify(hit)
    if spec == nil then return added, nil end
    for _, e in ipairs(spec.wounds(hit, ctx) or {}) do
        local w = Wounds.add(list, e.part, e.kind, ctx, e.opts)
        if w ~= nil then added[#added + 1] = w end
    end
    if spec.after ~= nil and #added > 0 then spec.after(list, added, hit, ctx) end
    return added, spec.id
end

-- ================================================================ outils des sources (tirages du vanilla)
-- Rand.Next(n) == 0, soit Rand.NextBool(n) : vrai une fois sur n (J/core/random/Rand.java).
function Wounds.oneIn(ctx, n)
    return ctx.rnd() * n < 1
end

-- Partie tirée comme Rand.Next(a, b) sur les index de BodyPartType : de first (compris) à last (compris), noms de
-- Wounds.PARTS (ordre de J/characters/BodyDamage/BodyPartType.java:16-32).
function Wounds.partBetween(ctx, first, last)
    local a, b
    for i, p in ipairs(Wounds.PARTS) do
        if p.id == first then a = i end
        if p.id == last then b = i end
    end
    if a == nil or b == nil or b < a then error("LivingKnox.Wounds.partBetween: bad range " .. tostring(first)
        .. ".." .. tostring(last), 2) end
    local i = a + math.floor(ctx.rnd() * (b - a + 1))
    if i > b then i = b end
    return Wounds.PARTS[i].id
end

-- Vrai si weapon est d'une des catégories vanilla names (champs de WeaponCategory : "BLUNT", "SMALL_BLUNT"...),
-- par HandWeapon.isOfWeaponCategory (J/inventory/types/HandWeapon.java:1158).
function Wounds.weaponIn(weapon, names)
    if weapon == nil then return false end
    for _, name in ipairs(names) do
        local c = WeaponCategory[name]
        if c ~= nil and weapon:isOfWeaponCategory(c) then return true end
    end
    return false
end

-- Partie indiquée par le moteur pour ce coup (hit.part, OnHitZombie), si c'est une partie connue ; sinon nil.
function Wounds.hintedPart(hit)
    local p = hit ~= nil and hit.part or nil
    if type(p) == "string" and Wounds.PART[p] ~= nil then return p end
    return nil
end

return Wounds
