-- Living Knox : plaie « bite » (morsure), inscrite au registre des plaies (LK21-T01, ADR adr-blessures-soins.md D02).
-- Nombres par tick vanilla, J/characters/BodyDamage/BodyPart.java (42.22) :
--   durée 50-80 (SetBitten :609) ; guérison 5e-6 à nu (:187), 1e-4 bandée (:184) ; usure du bandage 1e-4 (:185) ;
--   dégâts de partie 2.1875 à nu (:158-160) ; saignement 7.5-15 (generateBleeding :1800-1802) ; plaie infectée dès la
--   morsure (:608) ; hors de la porte des tirages d'infection (:219) ; douleur 50 à nu, 30 bandée (:911-913).
-- virusChance : la morsure transmet le virus de Knox sauf option de transmission 4 (:616-623) ; le virus lui-même,
-- son délai et le relevé en zombie sont LK21-T04.
-- Sang visible : addBlood d'une morsure, 20 tirages (J/characters/IsoGameCharacter.java:12218-12220).
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("bite", {
    order = 40,
    time = { 50, 80 },
    heal = { open = 5e-6, bandaged = 1e-4 },
    wear = 1e-4,
    damage = { open = 2.1875 },
    bleed = { { 7.5, 15 } },
    infectedOnAdd = true,
    virusChance = 100,
    bandage = true,
    pain = { open = 50, bandaged = 30 },
    blood = 1,
})
