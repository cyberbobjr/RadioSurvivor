-- Living Knox : plaie « laceration » (coupure), inscrite au registre des plaies (LK21-T01, ADR adr-blessures-soins.md
-- D02). Nombres par tick vanilla, J/characters/BodyDamage/BodyPart.java (42.22) :
--   durée 10-20 (setCut :683) ; guérison 1e-6 à nu (:336), 5e-5 bandée (:329) ; usure du bandage 1e-5 (:330) ;
--   dégâts de partie 1.875 à nu (:155-157) ; saignement 0.7-1 x durée (generateBleeding :1786) ; infection de plaie
--   -25000 (:231-233) ; virus 25 % par un zombie (:701) ; douleur 2.5 x durée (:908-910).
-- Sang visible : la lacération de zombie appelle addBlood en griffure (J/characters/BodyDamage/BodyDamage.java:1312),
-- 5 tirages contre 20 pour une morsure (J/characters/IsoGameCharacter.java:12218-12223).
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("laceration", {
    order = 20,
    time = { 10, 20 },
    heal = { open = 1e-6, bandaged = 5e-5 },
    wear = 1e-5,
    damage = { open = 1.875 },
    bleed = { { 0.7, 1.0, perTime = true } },
    infect = 25000,
    virusChance = 25,
    virusRoute = "blood",      -- jamais en transmission « salive seule » (:710-712, LK_Virus)
    bandage = true,
    pain = { perTime = 2.5 },
    blood = 0.25,
})
