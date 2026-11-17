-- Living Knox : source de blessure « fire » (feu), inscrite au registre des sources (LK21-T02, ADR
-- adr-blessures-soins.md D03). Règle du vanilla quand un personnage prend feu (IsoGameCharacter.SetOnFire,
-- J/characters/IsoGameCharacter.java:7499-7510, 42.22) :
--   - partie tirée de Hand_L à Foot_R (:7507) ;
--   - plaie : brûlure (BodyPart.setBurned, J/characters/BodyDamage/BodyPart.java:1204-1217) de durée 50-100
--     (x gravité sandbox, appliquée par Wounds.add) ; le type « burn » garde 30-50 pour les autres brûlures.
-- Sans match : appelée par son nom (hit.source = "fire"). Le corps d'un PNJ est invulnérable au feu vanilla
-- (LK_Health, en-tête) : aucun appelant aujourd'hui ; la simulation hors écran (LK21-T03) ou un autre mod s'en sert.
require "LivingKnox/LK_WoundSources"

local Wounds = LivingKnox.Wounds

Wounds.registerSource("fire", {
    order = 50,
    time = { 50, 100 },
    wounds = function(_, ctx)
        return { { part = Wounds.partBetween(ctx, "Hand_L", "Foot_R"), kind = "burn",
            opts = { time = Wounds.source("fire").time } } }
    end,
})
