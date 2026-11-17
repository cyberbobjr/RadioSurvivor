-- Living Knox : plaie « scratch » (griffure), inscrite au registre des plaies (LK21-T01, ADR adr-blessures-soins.md
-- D02). Nombres par tick vanilla, J/characters/BodyDamage/BodyPart.java (42.22) :
--   durée 7-15 (setScratched :727 ; griffure d'arme 5-10 :756, à régler par la source LK21-T02) ; guérison 1e-5 à nu
--   (:315), 1.5e-4 bandée (:308) ; usure du bandage 8e-5 (:309) ; dégâts de partie 0.9375 à nu (:152-154) ;
--   saignement 0.3-0.6 x durée (generateBleeding :1783), mais la griffure de zombie ne saigne pas (setScratched ne
--   l'appelle pas, :719-745 ; SetScratchedWeapon :766 et SetScratchedWindow le font) ; infection de plaie -20000
--   (:228-230) ; virus 7 % par un zombie (:744, generateZombieInfection :705-717) ; douleur 1.7 x durée (:905-907).
-- Sang visible : addBlood d'une griffure, 5 tirages contre 20 pour une morsure
-- (J/characters/IsoGameCharacter.java:12218-12223).
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("scratch", {
    order = 10,
    time = { 7, 15 },
    heal = { open = 1e-5, bandaged = 1.5e-4 },
    wear = 8e-5,
    damage = { open = 0.9375 },
    bleed = { { 0.3, 0.6, perTime = true } },
    bleedOnAdd = false,
    infect = 20000,
    virusChance = 7,
    virusRoute = "blood",      -- jamais en transmission « salive seule » (:710-712, LK_Virus)
    bandage = true,
    pain = { perTime = 1.7 },
    blood = 0.25,
})
