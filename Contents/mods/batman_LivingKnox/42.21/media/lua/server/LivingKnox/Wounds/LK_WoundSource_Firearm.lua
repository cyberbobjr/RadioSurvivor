-- Living Knox : source de blessure « firearm » (arme à feu), inscrite au registre des sources (LK21-T02, ADR
-- adr-blessures-soins.md D03). Règle de BodyDamage.DamageFromWeapon, J/characters/BodyDamage/BodyDamage.java (42.22) :
--   - prend l'arme à feu visée qui n'est pas contondante (HandWeapon.isAimedFirearm, :1024-1028 ;
--     J/inventory/types/HandWeapon.java:1079) ; la source « blunt » passe avant (ordre du registre) ;
--   - partie : celle du coup donnée par le moteur (OnHitZombie), sinon tirée de Hand_L à Foot_R (:1030-1032) ;
--   - plaie : une balle logée (setHaveBullet(true, 0), :1076-1078 ; type « bullet »).
-- Écart : la défense des vêtements par partie (:1035-1048) n'est pas reprise (un PNJ n'en a pas).
require "LivingKnox/LK_WoundSources"

local Wounds = LivingKnox.Wounds

Wounds.registerSource("firearm", {
    order = 30,
    match = function(hit)
        return hit.weapon ~= nil and hit.weapon:isAimedFirearm()
    end,
    wounds = function(hit, ctx)
        local part = Wounds.hintedPart(hit) or Wounds.partBetween(ctx, "Hand_L", "Foot_R")
        return { { part = part, kind = "bullet" } }
    end,
})
