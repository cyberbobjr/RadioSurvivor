-- Living Knox : plaie « fracture », inscrite au registre des plaies (LK21-T01, ADR adr-blessures-soins.md D02).
-- Nombres par tick vanilla (42.22) :
--   durée 50-80 (chute : J/characters/IsoGameCharacter.java:2170, generateFractureNew) ; guérison 5e-6 sans attelle,
--   5e-5 x facteur d'attelle (J/characters/BodyDamage/BodyPart.java:392-397) ; dégâts de partie 3.125 sans attelle,
--   bandage ou non (:179-181) ; douleur durée, moitié avec attelle (:920-922). Ne saigne pas, ne s'infecte pas (porte
--   :219). Facteur d'attelle (docteur + 1) / 2 (ISSplint.lua:89-94).
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("fracture", {
    order = 70,
    time = { 50, 80 },
    heal = { open = 5e-6, splinted = 5e-5 },
    damage = { open = 3.125, bandaged = 3.125, splinted = 0 },
    splint = true,
    pain = { perTime = 1, splinted = 0.5 },
})
