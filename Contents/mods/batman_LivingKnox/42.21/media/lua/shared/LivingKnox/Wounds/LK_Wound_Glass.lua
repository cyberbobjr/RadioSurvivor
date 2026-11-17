-- Living Knox : plaie « glass » (éclats de verre logés), inscrite au registre des plaies (LK21-T01, ADR
-- adr-blessures-soins.md D02). Plaie profonde avec éclat (generateDeepShardWound, J/characters/BodyDamage/
-- BodyPart.java:795-815, 42.22). Nombres par tick vanilla :
--   durée 15-20 (:797) ; guérison comme la plaie profonde (:349, :359), jamais sous 3 tant que l'éclat reste ou sans
--   bandage (:361-363) ; usure du bandage 1e-4 (:350), 0.005 tant qu'elle saigne (:205-206) ; dégâts de partie 3.125 à
--   nu, 1.5625 bandée (:145-151) ; saignement 0.7-1 x durée plus 5-10 pour l'éclat (generateBleeding :1792,
--   :1794-1796), jamais sous 3 tant que l'éclat reste (:213-215) ; infection de plaie -30000 et -24000 pour l'éclat
--   (:234-239), aggravation 1e-4 par tick avec l'éclat (:284-285) ; douleur 3.7 x durée plus 10 (:914-916, :926-928).
-- Retrait (setHaveGlass(false), :971-973) : la plaie profonde reste, avec sa durée et son saignement. Retrait à nu
-- seulement (ISHealthPanel.lua:844) ; on ne recoud qu'après (:1379).
-- Sang visible : approximation (5 tirages sur 20 comme une griffure), à confirmer par LK21-T09.
require "LivingKnox/LK_Wounds"

LivingKnox.Wounds.registerKind("glass", {
    order = 60,
    time = { 15, 20 },
    heal = { open = 2e-6, bandaged = 2e-5 },
    floor = { open = 3, foreign = 3 },
    foreign = { becomes = "deep" },
    wear = 1e-4,
    bleedWear = 0.005,
    damage = { open = 3.125, bandaged = 1.5625 },
    bleed = { { 0.7, 1.0, perTime = true }, { 5, 10 } },
    bleedFloor = { foreign = 3 },
    infect = 30000,
    foreignInfect = 24000,
    infectGrowth = 1e-4,
    bandage = true,
    pain = { perTime = 3.7, foreign = 10 },
    blood = 0.25,
})
