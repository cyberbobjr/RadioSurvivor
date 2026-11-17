-- Living Knox : source de blessure « blunt » (arme contondante), inscrite au registre des sources (LK21-T02, ADR
-- adr-blessures-soins.md D03). Règle de BodyDamage.DamageFromWeapon, J/characters/BodyDamage/BodyDamage.java (42.22) :
--   - prend l'arme des catégories Blunt ou SmallBlunt (:1022-1023, WeaponCategory) ;
--   - partie : celle du coup donnée par le moteur (OnHitZombie), sinon tirée de Hand_L à Foot_R (:1030-1032) ;
--   - plaie : 1 fois sur 4 une coupure (setCut, :1067-1069), sinon une griffure sans saignement
--     (setScratched(true, true), :1070-1073 ; BodyPart.java:719-745).
-- Écart : la défense des vêtements par partie (:1035-1048) n'est pas reprise (un PNJ n'en a pas).
require "LivingKnox/LK_WoundSources"

local Wounds = LivingKnox.Wounds

local CATEGORIES = { "BLUNT", "SMALL_BLUNT" }   -- champs de WeaponCategory (J/scripting/objects/WeaponCategory.java:13-18)

Wounds.registerSource("blunt", {
    order = 20,
    categories = CATEGORIES,
    match = function(hit)
        return Wounds.weaponIn(hit.weapon, CATEGORIES)
    end,
    wounds = function(hit, ctx)
        local part = Wounds.hintedPart(hit) or Wounds.partBetween(ctx, "Hand_L", "Foot_R")
        local kind = Wounds.oneIn(ctx, 4) and "laceration" or "scratch"
        return { { part = part, kind = kind } }
    end,
})
