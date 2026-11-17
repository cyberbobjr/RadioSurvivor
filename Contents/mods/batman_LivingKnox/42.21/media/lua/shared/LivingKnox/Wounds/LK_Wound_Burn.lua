-- Living Knox : plaie « burn » (brûlure), inscrite au registre des plaies (LK21-T01, ADR adr-blessures-soins.md D02).
-- Nombres par tick vanilla (42.22) :
--   durée 30-50 (feu : J/characters/BodyDamage/BodyDamage.java:2641) ; guérison 5e-6 à nu, 1e-4 bandée
--   (J/characters/BodyDamage/BodyPart.java:190-196) ; usure du bandage 1e-4 (:193) ; dégâts de partie 3.75 à nu
--   (:176-178) ; douleur durée (:929-931). Le feu ne tire pas de saignement. Une brûlure seule est hors de la porte des
--   tirages d'infection (:219) : son retrait -23000 (:240-244) ne compte qu'avec une autre plaie de la même partie,
--   ce que le modèle par plaie ne fait pas (LK_Wounds.lua, en-tête). Lavage des brûlures (needBurnWash) non repris.
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("burn", {
    order = 80,
    time = { 30, 50 },
    heal = { open = 5e-6, bandaged = 1e-4 },
    wear = 1e-4,
    damage = { open = 3.75 },
    bandage = true,
    pain = { perTime = 1 },
})
