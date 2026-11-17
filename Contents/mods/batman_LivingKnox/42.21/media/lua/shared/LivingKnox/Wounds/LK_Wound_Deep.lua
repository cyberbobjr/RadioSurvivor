-- Living Knox : plaie « deep » (plaie profonde), inscrite au registre des plaies (LK21-T01, ADR adr-blessures-soins.md
-- D02). Nombres par tick vanilla, J/characters/BodyDamage/BodyPart.java (42.22) :
--   durée 15-20 (generateDeepWound :776) ; guérison 2e-6 à nu (:359), 2e-5 bandée (:349), jamais sous 3 sans bandage
--   (:361-363) ; usure du bandage 1e-4 (:350), 0.005 tant qu'elle saigne (:205-206) ; dégâts de partie 3.125 à nu,
--   1.5625 bandée, aucun une fois recousue (:145-151) ; saignement 0.7-1 x durée (generateBleeding :1792) ; infection
--   de plaie -30000 (:234-236) ; douleur 3.7 x durée (:914-916). Se recoud (ISHealthPanel.lua:1379).
-- Sang visible : approximation (5 tirages sur 20 comme une griffure), à confirmer par LK21-T09.
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("deep", {
    order = 30,
    time = { 15, 20 },
    heal = { open = 2e-6, bandaged = 2e-5 },
    floor = { open = 3 },
    wear = 1e-4,
    bleedWear = 0.005,
    damage = { open = 3.125, bandaged = 1.5625 },
    bleed = { { 0.7, 1.0, perTime = true } },
    infect = 30000,
    stitch = true,
    bandage = true,
    pain = { perTime = 3.7 },
    blood = 0.25,
})
