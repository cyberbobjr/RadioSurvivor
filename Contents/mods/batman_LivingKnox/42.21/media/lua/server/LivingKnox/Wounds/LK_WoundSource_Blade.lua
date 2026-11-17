-- Living Knox : source de blessure « blade » (arme tranchante), inscrite au registre des sources (LK21-T02, ADR
-- adr-blessures-soins.md D03). Règle de BodyDamage.DamageFromWeapon, J/characters/BodyDamage/BodyDamage.java (42.22) :
--   - prend toute arme qui n'est ni contondante ni à feu visée (:1024-1025) : dernière arme du registre, les sources
--     « blunt » et « firearm » passent avant ;
--   - partie : celle du coup donnée par le moteur (OnHitZombie), sinon tirée de Hand_L à Foot_R (:1030-1032) ;
--   - plaie : 1 fois sur 6 une plaie profonde (generateDeepWound, :1055-1057), sinon 1 fois sur 3 une coupure
--     (setCut, :1058-1060), sinon une griffure sans saignement (setScratched(true, true), :1061-1064 ;
--     BodyPart.java:719-745).
-- Écart : la défense des vêtements par partie (:1035-1048) n'est pas reprise (un PNJ n'en a pas).
require "LivingKnox/LK_WoundSources"

local Wounds = LivingKnox.Wounds

Wounds.registerSource("blade", {
    order = 90,
    match = function(hit)
        return hit.weapon ~= nil
    end,
    wounds = function(hit, ctx)
        local part = Wounds.hintedPart(hit) or Wounds.partBetween(ctx, "Hand_L", "Foot_R")
        local kind = "scratch"
        if Wounds.oneIn(ctx, 6) then kind = "deep"
        elseif Wounds.oneIn(ctx, 3) then kind = "laceration" end
        return { { part = part, kind = kind } }
    end,
})
