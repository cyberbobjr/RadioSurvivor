-- Living Knox : plaie « bullet » (balle logée), inscrite au registre des plaies (LK21-T01, ADR adr-blessures-soins.md
-- D02). Nombres par tick vanilla, J/characters/BodyDamage/BodyPart.java (42.22) :
--   pas de durée : la balle reste jusqu'au retrait (haveBullet) ; dégâts de partie 3.125 à nu, 1.5625 bandée
--   (:169-175) ; saignement 5-10 (generateBleeding :1797-1799) ; douleur 50 (:923-925). Hors de la porte des tirages
--   d'infection (:219). Retrait (setHaveBullet(false, docteur), :1074-1097) : plaie profonde de 17-23 moins docteur / 2,
--   nouveau saignement. Retrait à nu seulement (ISHealthPanel.lua:812).
-- Sang visible : approximation (10 tirages sur 20), à confirmer par LK21-T09.
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("bullet", {
    order = 50,
    foreign = { becomes = "deep", time = { 17, 23 } },
    damage = { open = 3.125, bandaged = 1.5625 },
    bleed = { { 5, 10 } },
    bandage = true,
    pain = { foreign = 50 },
    blood = 0.5,
})
